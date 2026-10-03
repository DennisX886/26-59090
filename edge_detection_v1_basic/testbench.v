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

    integer x;
    integer y;
    integer out_count;
    integer f_out;
    integer i;
    reg [7:0] result_img [0:IMG_W*IMG_H-1];

    // Device under test
    sobel_edge #(
        .IMG_W(IMG_W),
        .IMG_H(IMG_H),
        .THRESHOLD(THRESHOLD)
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

    // Store a complete 640x480 output frame.
    // The 1-pixel border is initialized to black because a 3x3 Sobel
    // window cannot be formed there.
    initial begin
        out_count = 0;
        for (i = 0; i < IMG_W*IMG_H; i = i + 1)
            result_img[i] = 8'd0;
    end

    always @(posedge clk) begin
        if (out_valid) begin
            result_img[out_y*IMG_W + out_x] = out_pixel;
            out_count = out_count + 1;
        end

        if (frame_done) begin
            // frame_done and the final out_valid can occur together.
            // Blocking assignment above has already stored the final pixel.
            f_out = $fopen("edge_result.pgm", "wb");
            $fwrite(f_out, "P5\n%d %d\n255\n", IMG_W, IMG_H);
            for (i = 0; i < IMG_W*IMG_H; i = i + 1)
                $fwrite(f_out, "%c", result_img[i]);
            $fclose(f_out);

            $display("============================================");
            $display("Sobel simulation finished.");
            $display("Output valid pixels = %0d", out_count);
            $display("Expected valid pixels = %0d", (IMG_W-2)*(IMG_H-2));
            $display("Generated: edge_result.pgm (640x480)");
            $display("Generated: sim.vcd");
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

        // Start frame.
        @(posedge clk);
        start_frame <= 1'b1;
        @(posedge clk);
        start_frame <= 1'b0;

        // Raster scan: one pixel per clock.
        for (y = 0; y < IMG_H; y = y + 1) begin
            for (x = 0; x < IMG_W; x = x + 1) begin
                @(posedge clk);
                in_valid <= 1'b1;
                in_pixel <= make_pixel(x, y);
            end
        end

        @(posedge clk);
        in_valid <= 1'b0;
        in_pixel <= 8'd0;
    end

endmodule
