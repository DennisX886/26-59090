`timescale 1ns/1ps

// ============================================================
// Simulation testbench
// REQUIRED module name: sim
//
// Test image:
//   640x480 synthetic grayscale image
//   - dark background
//   - bright rectangle
//   - bright diagonal line
//   - horizontal/vertical intensity boundaries
//
// Output:
//   edge_result.pgm  : binary PGM (P5) edge image
//   sim.vcd          : waveform for GTKWave
//
// Run with Icarus:
//   iverilog -g2012 -o sim.out edge_sobel.v sim.v
//   vvp sim.out
//   gtkwave sim.vcd
// ============================================================
module sim;

    localparam IMG_W = 640;
    localparam IMG_H = 480;
    localparam THRESHOLD = 128;
    // 0 = 基础Sobel；1 = 中值滤波 -> Sobel（扩展功能）
    localparam MEDIAN_ENABLE = 1;

    // ------------------------------------------------------------
    // Noise simulation parameters
    // NOISE_ENABLE = 1 : enable noise
    // NOISE_MODE   = 0 : salt-and-pepper impulse noise
    //                 1 : additive random noise
    // NOISE_RATE_PERMILLE : impulse-noise probability in ‰
    //                       15 = 1.5% pixels affected
    // NOISE_AMPLITUDE     : additive-noise maximum amplitude
    //                       20 means approximately +/-20
    // ------------------------------------------------------------
    localparam NOISE_ENABLE       = 1;
    localparam NOISE_MODE         = 0;
    localparam NOISE_RATE_PERMILLE = 15;
    localparam NOISE_AMPLITUDE    = 20;

    reg clk;
    reg rst_n;

    reg start_frame;
    reg in_valid;
    reg [7:0] in_pixel;

    wire out_valid;
    wire [7:0] out_pixel;
    wire [9:0] out_x;
    wire [8:0] out_y;
    wire frame_done;

    // 单独观察中值滤波结果，便于确认“噪声 -> 中值 -> Sobel”是否正确。
    wire       median_dbg_valid;
    wire [7:0] median_dbg_pixel;
    wire       median_dbg_done;

    integer x;
    integer y;
    integer out_count;
    integer median_out_index;
    integer f_out;
    integer i;
    integer noise_seed;
    integer rand_value;
    integer signed_noise;
    integer noisy_value;
    reg [7:0] current_noisy_pixel;
    reg [7:0] result_img [0:IMG_W*IMG_H-1];
    reg [7:0] noisy_img  [0:IMG_W*IMG_H-1];
    reg [7:0] median_img [0:IMG_W*IMG_H-1];

    // Device under test
    sobel_edge #(
        .IMG_W(IMG_W),
        .IMG_H(IMG_H),
        .THRESHOLD(THRESHOLD),
        .MEDIAN_ENABLE(MEDIAN_ENABLE)
    ) dut (
        .clk        (clk),
        .rst_n      (rst_n),
        .start_frame(start_frame),
        .in_valid   (in_valid),
        .in_pixel   (in_pixel),
        .out_valid  (out_valid),
        .out_pixel  (out_pixel),
        .out_x      (out_x),
        .out_y      (out_y),
        .frame_done (frame_done)
    );

    // 额外例化一个中值滤波器，仅用于把中间结果保存成 median_result.pgm。
    // DUT内部也有同一个中值滤波器，因此不会改变主处理链。
    median_filter #(
        .IMG_W(IMG_W),
        .IMG_H(IMG_H)
    ) median_debug (
        .clk        (clk),
        .rst_n      (rst_n),
        .start_frame(start_frame),
        .in_valid   (in_valid),
        .in_pixel   (in_pixel),
        .out_valid  (median_dbg_valid),
        .out_pixel  (median_dbg_pixel),
        .frame_done (median_dbg_done)
    );

    // 100 MHz clock
    initial begin
        clk = 1'b0;
        forever #5 clk = ~clk;
    end

    // Create a simple deterministic test image.
    function [7:0] make_pixel;
        input integer px;
        input integer py;
        begin
            // Background
            make_pixel = 8'd20;

            // Large bright rectangle
            if ((px >= 100) && (px < 300) &&
                (py >= 80)  && (py < 240))
                make_pixel = 8'd220;

            // Horizontal bright bar
            if ((py >= 320) && (py < 350))
                make_pixel = 8'd180;

            // Vertical bright bar
            if ((px >= 420) && (px < 450))
                make_pixel = 8'd200;

            // Diagonal line
            if ((px > 20) && (px < 460) &&
                (py > 20) && (py < 460) &&
                ((py - px) >= -2) && ((py - px) <= 2))
                make_pixel = 8'd255;
        end
    endfunction

    // ------------------------------------------------------------
    // Add simulated image noise.
    //
    // Mode 0: salt-and-pepper noise.
    //   With probability NOISE_RATE_PERMILLE / 1000, a pixel becomes
    //   either 0 or 255. This is useful for checking the robustness
    //   of the Sobel detector against isolated noise points.
    //
    // Mode 1: additive random noise.
    //   Pixel value is changed by approximately +/- NOISE_AMPLITUDE.
    // ------------------------------------------------------------
    function [7:0] make_noisy_pixel;
        input integer px;
        input integer py;
        reg [7:0] base_pixel;
        integer r;
        integer delta;
        integer value;
        begin
            base_pixel = make_pixel(px, py);
            make_noisy_pixel = base_pixel;

            if (NOISE_ENABLE != 0) begin
                r = $urandom(noise_seed) % 1000;

                if (NOISE_MODE == 0) begin
                    // Salt-and-pepper impulse noise
                    if (r < NOISE_RATE_PERMILLE) begin
                        if (($urandom(noise_seed) & 32'h1) == 0)
                            make_noisy_pixel = 8'd0;
                        else
                            make_noisy_pixel = 8'd255;
                    end
                end
                else begin
                    // Additive +/- random noise
                    delta = $urandom(noise_seed) % (2*NOISE_AMPLITUDE + 1);
                    delta = delta - NOISE_AMPLITUDE;
                    value = base_pixel + delta;

                    if (value < 0)
                        value = 0;
                    else if (value > 255)
                        value = 255;

                    make_noisy_pixel = value[7:0];
                end
            end
        end
    endfunction

    // Store a complete 640x480 output frame.
    // The 1-pixel border is initialized to black because a 3x3 Sobel
    // window cannot be formed there.
    initial begin
        out_count = 0;
        median_out_index = 0;
        noise_seed = 32'h13572468;
        for (i = 0; i < IMG_W*IMG_H; i = i + 1) begin
            result_img[i] = 8'd0;
            noisy_img[i]  = 8'd0;
            median_img[i] = 8'd0;
        end
    end

    always @(posedge clk) begin
        if (out_valid) begin
            result_img[out_y*IMG_W + out_x] = out_pixel;
            out_count = out_count + 1;
        end

        if (median_dbg_valid) begin
            // 中值滤波保持完整640x480像素流，因此这里按输入顺序记录。
            median_img[median_out_index] = median_dbg_pixel;
            median_out_index = median_out_index + 1;
        end

        if (frame_done) begin
            // frame_done and the final out_valid can occur together.
            // Blocking assignment above has already stored the final pixel.

            // Save the actual noisy input frame for visual comparison.
            f_out = $fopen("noisy_input.pgm", "wb");
            $fwrite(f_out, "P5\n%d %d\n255\n", IMG_W, IMG_H);
            for (i = 0; i < IMG_W*IMG_H; i = i + 1)
                $fwrite(f_out, "%c", noisy_img[i]);
            $fclose(f_out);

            f_out = $fopen("median_result.pgm", "wb");
            $fwrite(f_out, "P5\n%d %d\n255\n", IMG_W, IMG_H);
            for (i = 0; i < IMG_W*IMG_H; i = i + 1)
                $fwrite(f_out, "%c", median_img[i]);
            $fclose(f_out);

            f_out = $fopen("edge_result.pgm", "wb");
            $fwrite(f_out, "P5\n%d %d\n255\n", IMG_W, IMG_H);
            for (i = 0; i < IMG_W*IMG_H; i = i + 1)
                $fwrite(f_out, "%c", result_img[i]);
            $fclose(f_out);

            $display("============================================");
            $display("Sobel simulation finished.");
            $display("Median filter enable = %0d", MEDIAN_ENABLE);
            $display("Output valid pixels = %0d", out_count);
            $display("Expected valid pixels = %0d", (IMG_W-2)*(IMG_H-2));
            $display("Generated: noisy_input.pgm (640x480)");
            $display("Generated: median_result.pgm (640x480)");
            $display("Generated: edge_result.pgm (640x480)");
            $display("Generated: sim.vcd");
            $display("Noise enable = %0d, mode = %0d, rate = %0d/1000",
                     NOISE_ENABLE, NOISE_MODE, NOISE_RATE_PERMILLE);
            $display("============================================");
            #20;
            $finish;
        end
    end

    initial begin
        $dumpfile("sim.vcd");
        $dumpvars(0, sim);

        rst_n = 1'b0;
        start_frame = 1'b0;
        in_valid = 1'b0;
        in_pixel = 8'd0;

        #100;
        rst_n = 1'b1;

        // Start frame：在时钟下降沿改变输入，让DUT在下一个上升沿稳定采样。
        @(negedge clk);
        start_frame = 1'b1;
        @(negedge clk);
        start_frame = 1'b0;

        // Raster scan：每个上升沿采样一个像素。
        for (y = 0; y < IMG_H; y = y + 1) begin
            for (x = 0; x < IMG_W; x = x + 1) begin
                current_noisy_pixel = make_noisy_pixel(x, y);
                noisy_img[y*IMG_W + x] = current_noisy_pixel;

                @(negedge clk);
                in_valid = 1'b1;
                in_pixel = current_noisy_pixel;
            end
        end

        @(negedge clk);
        in_valid = 1'b0;
        in_pixel = 8'd0;
    end

endmodule
