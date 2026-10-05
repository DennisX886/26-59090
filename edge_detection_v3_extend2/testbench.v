`timescale 1ns/1ps

// ============================================================
// Simulation testbench
// REQUIRED module name: sim
//
// 本版本重点验证：
//   1. 同一张“固定噪声输入图”在不同 threshold 下处理
//   2. 模拟 KEY+ / KEY- 实时调节 threshold
//   3. 统计每个 threshold 下的白色边缘像素数量
//   4. 保存不同 threshold 下的边缘结果
//
// 注意：电脑仿真中的 key_plus/key_minus 是 Verilog testbench
//       模拟的按键信号，不是直接读取 Windows 键盘。
// ============================================================
module sim;

    localparam IMG_W = 640;
    localparam IMG_H = 480;

    // 1 = 中值滤波 -> Sobel；0 = 直接 Sobel
    localparam MEDIAN_ENABLE = 1;

    // ------------------------------------------------------------
    // Noise simulation parameters
    // 为了让不同 threshold 的比较公平：
    // 噪声只生成一次，后面的所有帧都使用完全相同的 noisy_img。
    // ------------------------------------------------------------
    localparam NOISE_ENABLE        = 1;
    localparam NOISE_MODE          = 0;   // 0=salt-and-pepper, 1=uniform noise
    localparam NOISE_RATE_PERMILLE = 15;  // 1.5%
    localparam NOISE_AMPLITUDE     = 20;

    reg clk;
    reg rst_n;

    reg start_frame;
    reg in_valid;
    reg [7:0] in_pixel;

    // 模拟真实按键
    reg key_plus;
    reg key_minus;

    wire [7:0] threshold;

    wire       out_valid;
    wire [7:0] out_pixel;
    wire [9:0] out_x;
    wire [8:0] out_y;
    wire       frame_done;

    // 单独观察中值滤波结果
    wire       median_dbg_valid;
    wire [7:0] median_dbg_pixel;
    wire       median_dbg_done;

    integer x;
    integer y;
    integer out_count;
    integer edge_count;
    integer median_out_index;
    integer f_out;
    integer i;
    integer noise_seed;
    integer frame_index;
    integer saved_threshold;

    integer rand_value;
    integer signed_noise;
    integer noisy_value;
    reg [7:0] current_noisy_pixel;

    // ------------------------------------------------------------
    // 图像缓存
    // noisy_img 只生成一次，所有 threshold 使用同一份输入。
    // ------------------------------------------------------------
    reg [7:0] noisy_img  [0:IMG_W*IMG_H-1];
    reg [7:0] result_img [0:IMG_W*IMG_H-1];
    reg [7:0] median_img [0:IMG_W*IMG_H-1];

    // ------------------------------------------------------------
    // 阈值控制模块
    // 仿真把消抖周期设置得很小，方便快速验证。
    // 实际 FPGA 使用时应根据系统时钟重新设置。
    // ------------------------------------------------------------
    key_control #(
        .DEBOUNCE_CYCLES(4),
        .INIT_THRESHOLD(128),
        .STEP(10)
    ) u_key_control (
        .clk      (clk),
        .rst_n    (rst_n),
        .key_plus (key_plus),
        .key_minus(key_minus),
        .threshold(threshold)
    );

    // ------------------------------------------------------------
    // Device under test
    // ------------------------------------------------------------
    sobel_edge #(
        .IMG_W(IMG_W),
        .IMG_H(IMG_H),
        .THRESHOLD(128),       // 仅保留参数兼容性
        .MEDIAN_ENABLE(MEDIAN_ENABLE)
    ) dut (
        .clk        (clk),
        .rst_n      (rst_n),
        .start_frame(start_frame),
        .in_valid   (in_valid),
        .in_pixel   (in_pixel),
        .threshold  (threshold),
        .out_valid  (out_valid),
        .out_pixel  (out_pixel),
        .out_x      (out_x),
        .out_y      (out_y),
        .frame_done (frame_done)
    );

    // ------------------------------------------------------------
    // 单独例化一个中值滤波器，仅用于观察中间结果。
    // ------------------------------------------------------------
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

    // ------------------------------------------------------------
    // 100 MHz clock
    // ------------------------------------------------------------
    initial begin
        clk = 1'b0;
        forever #5 clk = ~clk;
    end

    // ------------------------------------------------------------
    // 创建“适合验证实时阈值”的测试图像。
    //
    // 背景 = 20
    // 弱边缘区域 = 52   -> 灰度差 32，Sobel最大响应约 128
    // 中弱边缘区域 = 55 -> 灰度差 35，Sobel最大响应约 140
    // 中强边缘区域 = 100 -> 灰度差 80
    // 强边缘区域 = 220 -> 灰度差 200
    //
    // 因此 threshold = 128 / 138 / 148 时，应该出现明显变化：
    //   128：可以看到较弱和中等边缘
    //   138：最弱边缘减少/消失，中等边缘仍存在
    //   148：更弱的边缘进一步减少，只保留较强边缘
    // ------------------------------------------------------------
    function [7:0] make_pixel;
        input integer px;
        input integer py;
        begin
            make_pixel = 8'd20;

            // 弱边缘：20 -> 52
            if ((px >= 50) && (px < 170) &&
                (py >= 50) && (py < 160))
                make_pixel = 8'd52;

            // 中弱边缘：20 -> 55
            if ((px >= 220) && (px < 340) &&
                (py >= 50) && (py < 160))
                make_pixel = 8'd55;

            // 中强边缘：20 -> 100
            if ((px >= 390) && (px < 510) &&
                (py >= 50) && (py < 160))
                make_pixel = 8'd100;

            // 强边缘：20 -> 220
            if ((px >= 130) && (px < 330) &&
                (py >= 250) && (py < 400))
                make_pixel = 8'd220;
        end
    endfunction

    // ------------------------------------------------------------
    // 给原始测试图增加噪声。
    // 该函数只在“生成固定输入图”阶段调用一次。
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
                    if (r < NOISE_RATE_PERMILLE) begin
                        if (($urandom(noise_seed) & 32'h1) == 0)
                            make_noisy_pixel = 8'd0;
                        else
                            make_noisy_pixel = 8'd255;
                    end
                end else begin
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

    // ------------------------------------------------------------
    // 只生成一次固定的 noisy_img。
    // ------------------------------------------------------------
    task generate_fixed_input;
        begin
            $display("============================================");
            $display("Generating ONE fixed noisy input frame...");
            $display("============================================");

            for (y = 0; y < IMG_H; y = y + 1) begin
                for (x = 0; x < IMG_W; x = x + 1) begin
                    noisy_img[y*IMG_W + x] = make_noisy_pixel(x, y);
                end
            end

            // 保存固定输入图，之后所有 threshold 都使用这一张图。
            f_out = $fopen("noisy_input.pgm", "wb");
            $fwrite(f_out, "P5\n%d %d\n255\n", IMG_W, IMG_H);
            for (i = 0; i < IMG_W*IMG_H; i = i + 1)
                $fwrite(f_out, "%c", noisy_img[i]);
            $fclose(f_out);

            $display("Fixed noisy input saved: noisy_input.pgm");
        end
    endtask

    // ------------------------------------------------------------
    // 每帧开始时清空结果缓存。
    // ------------------------------------------------------------
    task clear_frame_buffers;
        begin
            out_count = 0;
            edge_count = 0;
            median_out_index = 0;

            for (i = 0; i < IMG_W*IMG_H; i = i + 1) begin
                result_img[i] = 8'd0;
                median_img[i] = 8'd0;
            end
        end
    endtask

    // ------------------------------------------------------------
    // 模拟一次“按+键”。
    // ------------------------------------------------------------
    task press_plus;
        begin
            $display("[KEY] press +, threshold before = %0d", threshold);

            @(negedge clk);
            key_plus = 1'b1;
            repeat (8) @(negedge clk);
            key_plus = 1'b0;
            repeat (8) @(negedge clk);

            $display("[KEY] release +, threshold after  = %0d", threshold);
        end
    endtask

    // ------------------------------------------------------------
    // 模拟一次“按-键”。
    // ------------------------------------------------------------
    task press_minus;
        begin
            $display("[KEY] press -, threshold before = %0d", threshold);

            @(negedge clk);
            key_minus = 1'b1;
            repeat (8) @(negedge clk);
            key_minus = 1'b0;
            repeat (8) @(negedge clk);

            $display("[KEY] release -, threshold after  = %0d", threshold);
        end
    endtask

    // ------------------------------------------------------------
    // 发送一整帧。
    // 重点：这里不再调用 make_noisy_pixel()，而是直接发送
    // 已经生成好的 noisy_img，因此四次处理的输入完全相同。
    // ------------------------------------------------------------
    task send_frame;
        begin
            clear_frame_buffers;

            saved_threshold = threshold;
            $display("--------------------------------------------");
            $display("Start frame %0d, threshold = %0d", frame_index, saved_threshold);

            @(negedge clk);
            start_frame = 1'b1;
            @(negedge clk);
            start_frame = 1'b0;

            for (y = 0; y < IMG_H; y = y + 1) begin
                for (x = 0; x < IMG_W; x = x + 1) begin
                    current_noisy_pixel = noisy_img[y*IMG_W + x];

                    @(negedge clk);
                    in_valid = 1'b1;
                    in_pixel = current_noisy_pixel;
                end
            end

            @(negedge clk);
            in_valid = 1'b0;
            in_pixel = 8'd0;

            // 等待 DUT 完成当前帧
            wait (frame_done);
            @(negedge clk);

            // 根据 frame_index 保存结果
            if (frame_index == 0) begin
                f_out = $fopen("edge_result_threshold_128.pgm", "wb");
            end else if (frame_index == 1) begin
                f_out = $fopen("edge_result_threshold_138.pgm", "wb");
            end else if (frame_index == 2) begin
                f_out = $fopen("edge_result_threshold_148.pgm", "wb");
            end else begin
                f_out = $fopen("edge_result_threshold_138_after_minus.pgm", "wb");
            end

            $fwrite(f_out, "P5\n%d %d\n255\n", IMG_W, IMG_H);
            for (i = 0; i < IMG_W*IMG_H; i = i + 1)
                $fwrite(f_out, "%c", result_img[i]);
            $fclose(f_out);

            $display("Saved edge image, threshold = %0d", saved_threshold);
            $display("Valid pixels = %0d / %0d", out_count, (IMG_W-2)*(IMG_H-2));
            $display("WHITE edge pixels = %0d", edge_count);
            $display("--------------------------------------------");

            frame_index = frame_index + 1;
        end
    endtask

    // ------------------------------------------------------------
    // 统计 DUT 输出
    // ------------------------------------------------------------
    always @(posedge clk) begin
        if (out_valid) begin
            result_img[out_y*IMG_W + out_x] = out_pixel;
            out_count = out_count + 1;

            if (out_pixel == 8'hFF)
                edge_count = edge_count + 1;
        end

        if (median_dbg_valid) begin
            if (median_out_index < IMG_W*IMG_H) begin
                median_img[median_out_index] = median_dbg_pixel;
                median_out_index = median_out_index + 1;
            end
        end
    end

    // ------------------------------------------------------------
    // 主仿真流程
    // ------------------------------------------------------------
    initial begin
        $dumpfile("sim.vcd");
        $dumpvars(0, sim);

        rst_n       = 1'b0;
        start_frame = 1'b0;
        in_valid    = 1'b0;
        in_pixel    = 8'd0;
        key_plus    = 1'b0;
        key_minus   = 1'b0;
        frame_index = 0;
        noise_seed  = 32'h13572468;
        out_count   = 0;
        edge_count  = 0;
        median_out_index = 0;

        #100;
        rst_n = 1'b1;

        // --------------------------------------------------------
        // 第一步：只生成一次固定输入图
        // --------------------------------------------------------
        generate_fixed_input;

        // --------------------------------------------------------
        // 第二步：同一张图，threshold = 128
        // --------------------------------------------------------
        send_frame;

        // --------------------------------------------------------
        // 第三步：模拟 +，128 -> 138
        // --------------------------------------------------------
        press_plus;
        send_frame;

        // --------------------------------------------------------
        // 第四步：模拟 +，138 -> 148
        // --------------------------------------------------------
        press_plus;
        send_frame;

        // --------------------------------------------------------
        // 第五步：模拟 -，148 -> 138
        // --------------------------------------------------------
        press_minus;
        send_frame;

        // --------------------------------------------------------
        // 保存中值滤波结果
        // --------------------------------------------------------
        f_out = $fopen("median_result.pgm", "wb");
        $fwrite(f_out, "P5\n%d %d\n255\n", IMG_W, IMG_H);
        for (i = 0; i < IMG_W*IMG_H; i = i + 1)
            $fwrite(f_out, "%c", median_img[i]);
        $fclose(f_out);

        $display("============================================");
        $display("Realtime threshold simulation finished.");
        $display("Final threshold = %0d", threshold);
        $display("The four edge images use EXACTLY the same noisy input.");
        $display("Generated:");
        $display("  noisy_input.pgm");
        $display("  median_result.pgm");
        $display("  edge_result_threshold_128.pgm");
        $display("  edge_result_threshold_138.pgm");
        $display("  edge_result_threshold_148.pgm");
        $display("  edge_result_threshold_138_after_minus.pgm");
        $display("  sim.vcd");
        $display("============================================");

        #20;
        $finish;
    end

endmodule
