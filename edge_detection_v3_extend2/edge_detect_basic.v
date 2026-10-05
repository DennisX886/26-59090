`timescale 1ns/1ps

// ============================================================
// 640x480 8-bit Sobel edge detector, streaming interface
//
// 现在的处理链：
//   输入图像 -> [可选3x3中值滤波] -> Sobel -> 阈值化
//
// MEDIAN_ENABLE = 0：基础功能，直接Sobel
// MEDIAN_ENABLE = 1：扩展功能，中值滤波后再Sobel
// ============================================================
module sobel_edge #(
    parameter IMG_W = 640,
    parameter IMG_H = 480,
    parameter THRESHOLD = 128,
    parameter MEDIAN_ENABLE = 1
)(
    input              clk,
    input              rst_n,
    input              start_frame,
    input              in_valid,
    input      [7:0]   in_pixel,
    input      [7:0]   threshold,

    output reg         out_valid,
    output reg [7:0]   out_pixel,
    output reg [9:0]   out_x,
    output reg [8:0]   out_y,
    output reg         frame_done
);

    // ========================================================
    // 第一部分：可选中值滤波
    // ========================================================
    wire       med_valid;
    wire [7:0] med_pixel;
    wire       med_frame_done;

    median_filter #(
        .IMG_W(IMG_W),
        .IMG_H(IMG_H)
    ) u_median_filter (
        .clk        (clk),
        .rst_n      (rst_n),
        .start_frame(start_frame),
        .in_valid   (in_valid),
        .in_pixel   (in_pixel),
        .out_valid  (med_valid),
        .out_pixel  (med_pixel),
        .frame_done (med_frame_done)
    );

    // MEDIAN_ENABLE=0时直接旁路。
    // 注意：median_filter本身仍然工作，但不会影响Sobel输入。
    wire       proc_valid = (MEDIAN_ENABLE != 0) ? med_valid : in_valid;
    wire [7:0] proc_pixel = (MEDIAN_ENABLE != 0) ? med_pixel : in_pixel;

    // ========================================================
    // 第二部分：Sobel自己的3x3窗口
    // ========================================================
    reg [7:0] line1 [0:IMG_W-1];
    reg [7:0] line2 [0:IMG_W-1];

    reg [9:0] x_cnt;
    reg [8:0] y_cnt;

    reg [7:0] top_d1, top_d2;
    reg [7:0] mid_d1, mid_d2;
    reg [7:0] bot_d1, bot_d2;

    reg [7:0] top_cur;
    reg [7:0] mid_cur;

    reg signed [12:0] gx_calc;
    reg signed [12:0] gy_calc;
    reg        [12:0] abs_gx;
    reg        [12:0] abs_gy;
    reg        [13:0] mag_calc;

    integer i;

    // 当前Sobel窗口使用“滤波后的完整图像流”。
    always @* begin
        top_cur = line2[x_cnt];
        mid_cur = line1[x_cnt];

        // Gx = [-1 0 +1;
        //       -2 0 +2;
        //       -1 0 +1]
        gx_calc =
              -$signed({1'b0,top_d2})
              +$signed({1'b0,top_cur})
              -($signed({1'b0,mid_d2}) <<< 1)
              +($signed({1'b0,mid_cur}) <<< 1)
              -$signed({1'b0,bot_d2})
              +$signed({1'b0,proc_pixel});

        // Gy = [-1 -2 -1;
        //        0  0  0;
        //       +1 +2 +1]
        gy_calc =
              -$signed({1'b0,top_d2})
              -($signed({1'b0,top_d1}) <<< 1)
              -$signed({1'b0,top_cur})
              +$signed({1'b0,bot_d2})
              +($signed({1'b0,bot_d1}) <<< 1)
              +$signed({1'b0,proc_pixel});

        if (gx_calc < 0)
            abs_gx = -gx_calc;
        else
            abs_gx = gx_calc;

        if (gy_calc < 0)
            abs_gy = -gy_calc;
        else
            abs_gy = gy_calc;

        // L1近似：|Gx| + |Gy|
        mag_calc = abs_gx + abs_gy;
    end

    always @(posedge clk) begin
        if (!rst_n) begin
            x_cnt      <= 10'd0;
            y_cnt      <= 9'd0;
            top_d1     <= 8'd0;
            top_d2     <= 8'd0;
            mid_d1     <= 8'd0;
            mid_d2     <= 8'd0;
            bot_d1     <= 8'd0;
            bot_d2     <= 8'd0;
            out_valid  <= 1'b0;
            out_pixel  <= 8'd0;
            out_x      <= 10'd0;
            out_y      <= 9'd0;
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
            end else if (proc_valid) begin
                // 注意：这里处理的是“中值滤波后的整帧像素流”。
                top_d2 <= top_d1;
                top_d1 <= top_cur;
                mid_d2 <= mid_d1;
                mid_d1 <= mid_cur;
                bot_d2 <= bot_d1;
                bot_d1 <= proc_pixel;

                // 3x3窗口完整后，输出中心像素。
                if ((x_cnt >= 2) && (y_cnt >= 2)) begin
                    out_valid <= 1'b1;
                    out_x     <= x_cnt - 1'b1;
                    out_y     <= y_cnt - 1'b1;

                    if (mag_calc >= threshold)
                        out_pixel <= 8'hFF;
                    else
                        out_pixel <= 8'h00;
                end

                line2[x_cnt] <= line1[x_cnt];
                line1[x_cnt] <= proc_pixel;

                if (x_cnt == IMG_W-1) begin
                    x_cnt <= 10'd0;

                    if (y_cnt == IMG_H-1) begin
                        y_cnt      <= 9'd0;
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
// Team-facing wrapper.
// 保留你原来的接口，不改变队友的帧级握手方式。
// ============================================================
module edge_detect #(
    parameter IMG_W = 640,
    parameter IMG_H = 480,
    parameter THRESHOLD = 128,
    parameter MEDIAN_ENABLE = 1
)(
    input             clk,
    input             rst_n,

    input             frame_wr_done,
    input      [1:0]  buf_sel,
    output reg        proc_rd_ready,

    input             rd_frame_start,
    input             rd_pixel_valid,
    input      [7:0]  rd_pixel,
    input      [7:0]  threshold,

    output reg        edge_frame_done,
    output reg [1:0]  edge_buf_sel,

    output            edge_pixel_valid,
    output     [7:0]  edge_pixel,
    output     [9:0]  edge_x,
    output     [8:0]  edge_y
);

    reg busy;
    reg [1:0] work_buf_sel;
    wire sobel_done;

    always @(posedge clk) begin
        if (!rst_n) begin
            proc_rd_ready  <= 1'b1;
            edge_frame_done <= 1'b0;
            edge_buf_sel    <= 2'd0;
            busy            <= 1'b0;
            work_buf_sel    <= 2'd0;
        end else begin
            edge_frame_done <= 1'b0;

            if (frame_wr_done && !busy && proc_rd_ready) begin
                busy         <= 1'b1;
                proc_rd_ready <= 1'b0;
                work_buf_sel <= buf_sel;
            end

            if (sobel_done) begin
                busy            <= 1'b0;
                proc_rd_ready   <= 1'b1;
                edge_frame_done <= 1'b1;
                edge_buf_sel    <= work_buf_sel;
            end
        end
    end

    sobel_edge #(
        .IMG_W(IMG_W),
        .IMG_H(IMG_H),
        .THRESHOLD(THRESHOLD),
        .MEDIAN_ENABLE(MEDIAN_ENABLE)
    ) u_sobel (
        .clk        (clk),
        .rst_n      (rst_n),
        .start_frame(rd_frame_start),
        .in_valid   (rd_pixel_valid),
        .in_pixel   (rd_pixel),
        .threshold   (threshold),
        .out_valid  (edge_pixel_valid),
        .out_pixel  (edge_pixel),
        .out_x      (edge_x),
        .out_y      (edge_y),
        .frame_done (sobel_done)
    );

endmodule
