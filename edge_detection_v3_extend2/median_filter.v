`timescale 1ns/1ps

// ============================================================
// Streaming 3x3 median filter
//
// 输入：一帧8bit灰度图，按 raster order（逐行、逐像素）输入
// 输出：与输入保持相同数量的像素，因此可以直接级联到 Sobel
//
// 边界处理：前两行/前两列没有完整3x3窗口时，直接输出原像素。
// 内部区域使用3x3窗口的第5小值（中值）。
// ============================================================
module median_filter #(
    parameter IMG_W = 640,
    parameter IMG_H = 480
)(
    input              clk,
    input              rst_n,
    input              start_frame,
    input              in_valid,
    input      [7:0]   in_pixel,

    output reg         out_valid,
    output reg [7:0]   out_pixel,
    output reg         frame_done
);

    reg [7:0] line1 [0:IMG_W-1];
    reg [7:0] line2 [0:IMG_W-1];

    reg [9:0] x_cnt;
    reg [8:0] y_cnt;

    reg [7:0] top_d1, top_d2;
    reg [7:0] mid_d1, mid_d2;
    reg [7:0] bot_d1, bot_d2;

    reg [7:0] top_cur;
    reg [7:0] mid_cur;

    wire [7:0] median_window;
    reg  [7:0] median_comb;

    integer i;

    // 当前3x3窗口：
    // top_d2 top_d1 top_cur
    // mid_d2 mid_d1 mid_cur
    // bot_d2 bot_d1 in_pixel
    median9_comb u_median (
        .p11(top_d2), .p12(top_d1), .p13(top_cur),
        .p21(mid_d2), .p22(mid_d1), .p23(mid_cur),
        .p31(bot_d2), .p32(bot_d1), .p33(in_pixel),
        .median_pixel(median_window)
    );

    always @* begin
        top_cur = line2[x_cnt];
        mid_cur = line1[x_cnt];

        // 边界没有完整3x3窗口，直接保留原像素。
        // 这样输出仍然保持640x480的完整像素流，方便后级Sobel使用。
        if ((x_cnt >= 2) && (y_cnt >= 2))
            median_comb = median_window;
        else
            median_comb = in_pixel;
    end

    always @(posedge clk) begin
        if (!rst_n) begin
            x_cnt     <= 10'd0;
            y_cnt     <= 9'd0;
            top_d1    <= 8'd0;
            top_d2    <= 8'd0;
            mid_d1    <= 8'd0;
            mid_d2    <= 8'd0;
            bot_d1    <= 8'd0;
            bot_d2    <= 8'd0;
            out_valid <= 1'b0;
            out_pixel <= 8'd0;
            frame_done <= 1'b0;

            for (i = 0; i < IMG_W; i = i + 1) begin
                line1[i] <= 8'd0;
                line2[i] <= 8'd0;
            end
        end else begin
            out_valid  <= 1'b0;
            frame_done <= 1'b0;

            if (start_frame) begin
                x_cnt  <= 10'd0;
                y_cnt  <= 9'd0;
                top_d1 <= 8'd0;
                top_d2 <= 8'd0;
                mid_d1 <= 8'd0;
                mid_d2 <= 8'd0;
                bot_d1 <= 8'd0;
                bot_d2 <= 8'd0;
            end else if (in_valid) begin
                // median_comb对应当前输入像素位置的滤波结果。
                out_valid <= 1'b1;
                out_pixel <= median_comb;

                // 横向移动窗口
                top_d2 <= top_d1;
                top_d1 <= top_cur;
                mid_d2 <= mid_d1;
                mid_d1 <= mid_cur;
                bot_d2 <= bot_d1;
                bot_d1 <= in_pixel;

                // 保存前两行
                line2[x_cnt] <= line1[x_cnt];
                line1[x_cnt] <= in_pixel;

                if (x_cnt == IMG_W-1) begin
                    x_cnt <= 10'd0;
                    if (y_cnt == IMG_H-1) begin
                        y_cnt <= 9'd0;
                        frame_done <= 1'b1;
                    end else begin
                        y_cnt <= y_cnt + 1'b1;
                    end
                end else begin
                    x_cnt <= x_cnt + 1'b1;
                end
            end
        end
    end

endmodule

// ============================================================
// 9输入中值计算：先排序，再取第5个数。
// 这里保持你原来的“冒泡排序”思路，便于你学习和对照。
// ============================================================
module median9_comb(
    input  wire [7:0] p11, p12, p13,
    input  wire [7:0] p21, p22, p23,
    input  wire [7:0] p31, p32, p33,
    output reg  [7:0] median_pixel
);
    reg [7:0] temp [0:8];
    reg [7:0] tmp;
    integer i, j;

    always @* begin
        temp[0] = p11;
        temp[1] = p12;
        temp[2] = p13;
        temp[3] = p21;
        temp[4] = p22;
        temp[5] = p23;
        temp[6] = p31;
        temp[7] = p32;
        temp[8] = p33;

        for (i = 0; i < 9; i = i + 1) begin
            for (j = 0; j < 8-i; j = j + 1) begin
                if (temp[j] > temp[j+1]) begin
                    tmp       = temp[j];
                    temp[j]   = temp[j+1];
                    temp[j+1] = tmp;
                end
            end
        end

        median_pixel = temp[4];
    end
endmodule
