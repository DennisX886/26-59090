`timescale 1ns/1ps

// ============================================================
// 640x480 8-bit Sobel edge detector, streaming interface
// Verilog-2001 / Icarus Verilog compatible
//
// Input:
//   start_frame : one-cycle pulse before the first pixel of a frame
//   in_valid    : one-cycle pulse for each valid pixel, raster order
//   in_pixel    : 8-bit grayscale pixel
//
// Output:
//   out_valid   : valid Sobel result; result is for center pixel
//                 (x-1, y-1) when current input is (x, y)
//   out_pixel   : binary edge image, 0 or 255
//   out_x/out_y : coordinates of the result pixel
//   frame_done  : one-cycle pulse after the last output pixel
//
// Image size is fixed at 640x480 to match the team interface document.
// ============================================================
module sobel_edge #(
    parameter IMG_W = 640,
    parameter IMG_H = 480,
    parameter THRESHOLD = 128
)(
    input              clk,
    input              rst_n,

    input              start_frame,
    input              in_valid,
    input      [7:0]   in_pixel,

    output reg         out_valid,
    output reg [7:0]   out_pixel,
    output reg [9:0]   out_x,
    output reg [8:0]   out_y,
    output reg         frame_done
);

    // Two previous image rows.
    // line1[x] = previous row
    // line2[x] = two rows before current row
    reg [7:0] line1 [0:IMG_W-1];
    reg [7:0] line2 [0:IMG_W-1];

    reg [9:0] x_cnt;
    reg [8:0] y_cnt;

    // Horizontal shift registers for the two previous rows.
    reg [7:0] top_d1, top_d2;
    reg [7:0] mid_d1, mid_d2;
    reg [7:0] bot_d1, bot_d2;

    // Current vertical pixels, read from line buffers.
    reg [7:0] top_cur, mid_cur;

    // Sobel calculation signals.
    reg signed [12:0] gx_calc;
    reg signed [12:0] gy_calc;
    reg        [12:0] abs_gx;
    reg        [12:0] abs_gy;
    reg        [13:0] mag_calc;

    integer i;

    // Read the old line-buffer contents at the current x position.
    // Because line1/line2 are updated on the clock edge, these values
    // represent the two previous rows.
    always @* begin
        top_cur = line2[x_cnt];
        mid_cur = line1[x_cnt];

        // Sobel:
        // Gx = [-1 0 +1;
        //       -2 0 +2;
        //       -1 0 +1]
        gx_calc =
              -$signed({1'b0,top_d2})
              +$signed({1'b0,top_cur})
              -($signed({1'b0,mid_d2}) <<< 1)
              +($signed({1'b0,mid_cur}) <<< 1)
              -$signed({1'b0,bot_d2})
              +$signed({1'b0,in_pixel});

        // Gy = [-1 -2 -1;
        //        0  0  0;
        //       +1 +2 +1]
        gy_calc =
              -$signed({1'b0,top_d2})
              -($signed({1'b0,top_d1}) <<< 1)
              -$signed({1'b0,top_cur})
              +$signed({1'b0,bot_d2})
              +($signed({1'b0,bot_d1}) <<< 1)
              +$signed({1'b0,in_pixel});

        if (gx_calc < 0)
            abs_gx = -gx_calc;
        else
            abs_gx = gx_calc;

        if (gy_calc < 0)
            abs_gy = -gy_calc;
        else
            abs_gy = gy_calc;

        // L1 approximation: |Gx| + |Gy|.
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

                // Shift the 3x3 window horizontally.
                top_d2 <= top_d1;
                top_d1 <= top_cur;

                mid_d2 <= mid_d1;
                mid_d1 <= mid_cur;

                bot_d2 <= bot_d1;
                bot_d1 <= in_pixel;

                // The window becomes valid at x>=2 and y>=2.
                // Its center is (x-1, y-1).
                if ((x_cnt >= 2) && (y_cnt >= 2)) begin
                    out_valid <= 1'b1;
                    out_x     <= x_cnt - 1'b1;
                    out_y     <= y_cnt - 1'b1;

                    if (mag_calc >= THRESHOLD)
                        out_pixel <= 8'hFF;
                    else
                        out_pixel <= 8'h00;
                end

                // Update line buffers after using the old contents.
                line2[x_cnt] <= line1[x_cnt];
                line1[x_cnt] <= in_pixel;

                // Raster scan counters.
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
//
// IMPORTANT:
// The uploaded team interface document defines only the
// frame-level handshake:
//   frame_wr_done / buf_sel / proc_rd_ready
//   edge_frame_done / edge_buf_sel
//
// It does NOT define the DDR3 native/AXI read port. Therefore,
// this wrapper intentionally exposes a generic pixel-stream input
// instead of inventing an Efinity DDR interface.
//
// Once the teammate provides the exact DDR read interface,
// connect that interface to the stream below.
// ============================================================
module edge_detect #(
    parameter IMG_W = 640,
    parameter IMG_H = 480,
    parameter THRESHOLD = 128
)(
    input             clk,
    input             rst_n,

    // From camera/DDR frame manager
    input             frame_wr_done,
    input      [1:0]  buf_sel,
    output reg        proc_rd_ready,

    // Generic frame read stream from the DDR reader
    input             rd_frame_start,
    input             rd_pixel_valid,
    input      [7:0]  rd_pixel,

    // Result frame-level handshake to display module
    output reg        edge_frame_done,
    output reg [1:0]  edge_buf_sel,

    // Processed pixel stream (for the display-side DDR writer)
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
            proc_rd_ready <= 1'b1;
            edge_frame_done <= 1'b0;
            edge_buf_sel <= 2'd0;
            busy <= 1'b0;
            work_buf_sel <= 2'd0;
        end else begin
            edge_frame_done <= 1'b0;

            // A frame is available when the camera module pulses
            // frame_wr_done. Accept it only when we are idle.
            if (frame_wr_done && !busy && proc_rd_ready) begin
                busy <= 1'b1;
                proc_rd_ready <= 1'b0;
                work_buf_sel <= buf_sel;
            end

            // The external DDR reader is expected to issue
            // rd_frame_start / rd_pixel_valid after acceptance.
            if (sobel_done) begin
                busy <= 1'b0;
                proc_rd_ready <= 1'b1;
                edge_frame_done <= 1'b1;
                edge_buf_sel <= work_buf_sel;
            end
        end
    end

    sobel_edge #(
        .IMG_W(IMG_W),
        .IMG_H(IMG_H),
        .THRESHOLD(THRESHOLD)
    ) u_sobel (
        .clk        (clk),
        .rst_n      (rst_n),
        .start_frame(rd_frame_start),
        .in_valid   (rd_pixel_valid),
        .in_pixel   (rd_pixel),
        .out_valid  (edge_pixel_valid),
        .out_pixel  (edge_pixel),
        .out_x      (edge_x),
        .out_y      (edge_y),
        .frame_done (sobel_done)
    );

endmodule
