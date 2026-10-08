`timescale 1ns/1ps

// ============================================================
// ddr_frame_buffer.v
//
// 独立 DDR 帧缓冲模块，模拟"采集-存储-读取-处理-显示"闭环。
//
// 对 testbench 完全透明：
//   输入接口和 sobel_edge 完全一致（start_frame/in_valid/in_pixel）
//   输出接口和 sobel_edge 完全一致（out_valid/out_pixel/out_x/out_y/frame_done）
//
// 内部结构（三段式状态机）：
//   S_CAPTURE : 接收 in_valid/in_pixel 流，写入 DDR 的 Ping 缓冲区
//   S_PROCESS : 从 DDR Ping 逐像素读出，喂给 sobel_edge；
//               sobel 的输出写回 DDR 的 Pong 缓冲区
//   S_DISPLAY : 从 DDR Pong 逐像素读出，通过 out_valid/out_pixel 输出
//   S_DONE    : 拉高 frame_done
//
// DDR 布局：
//   [0         .. IMG_SIZE-1]    : Ping 缓冲（原始图）
//   [IMG_SIZE  .. 2*IMG_SIZE-1]  : Pong 缓冲（边缘图）
// ============================================================
module ddr_frame_buffer #(
    parameter IMG_W = 640,
    parameter IMG_H = 480,
    parameter MEDIAN_ENABLE = 1
)(
    input              clk,
    input              rst_n,

    // 与 testbench 一致的输入接口（模拟摄像头）
    input              start_frame,
    input              in_valid,
    input      [7:0]   in_pixel,
    input      [7:0]   threshold,

    // 与 testbench 一致的输出接口（模拟显示）
    output reg         out_valid,
    output reg [7:0]   out_pixel,
    output reg [9:0]   out_x,
    output reg [8:0]   out_y,
    output reg         frame_done
);

    localparam IMG_SIZE = IMG_W * IMG_H;

    // ========================================================
    // DDR 存储模型（Ping + Pong 两个缓冲区）
    // ========================================================
    reg [7:0] ddr_mem [0:2*IMG_SIZE-1];

    // 初始化 DDR 内容为 0，避免仿真读到 x
    integer j;
    initial begin
        for (j = 0; j < 2*IMG_SIZE; j = j + 1)
            ddr_mem[j] = 8'd0;
    end

    // ========================================================
    // 内部例化 sobel_edge（保持你原来的流式接口）
    // ========================================================
    reg        sobel_start_frame;
    reg        sobel_in_valid;
    reg  [7:0] sobel_in_pixel;

    wire       sobel_out_valid;
    wire [7:0] sobel_out_pixel;
    wire [9:0] sobel_out_x;
    wire [8:0] sobel_out_y;
    wire       sobel_frame_done;

    sobel_edge #(
        .IMG_W(IMG_W),
        .IMG_H(IMG_H),
        .MEDIAN_ENABLE(MEDIAN_ENABLE)
    ) u_sobel (
        .clk         (clk),
        .rst_n       (rst_n),
        .start_frame (sobel_start_frame),
        .in_valid    (sobel_in_valid),
        .in_pixel    (sobel_in_pixel),
        .threshold   (threshold),
        .out_valid   (sobel_out_valid),
        .out_pixel   (sobel_out_pixel),
        .out_x       (sobel_out_x),
        .out_y       (sobel_out_y),
        .frame_done  (sobel_frame_done)
    );

    // ========================================================
    // 主状态机
    // ========================================================
    localparam S_CAPTURE = 2'd0;
    localparam S_PROCESS = 2'd1;
    localparam S_DISPLAY = 2'd2;
    localparam S_DONE    = 2'd3;

    reg [1:0]  state;
    reg [18:0] pix_cnt;   // 0 ~ 2*IMG_SIZE-1 (19位足够)

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state             <= S_CAPTURE;
            pix_cnt           <= 19'd0;
            sobel_start_frame <= 1'b0;
            sobel_in_valid    <= 1'b0;
            sobel_in_pixel    <= 8'd0;
            out_valid         <= 1'b0;
            out_pixel         <= 8'd0;
            out_x             <= 10'd0;
            out_y             <= 9'd0;
            frame_done        <= 1'b0;
        end else begin
            frame_done <= 1'b0;
            out_valid  <= 1'b0;

            case (state)
                // ---------------------------------------------
                // 第一段：接收输入流，写入 DDR Ping 缓冲
                // ---------------------------------------------
                S_CAPTURE: begin
                    if (start_frame) begin
                        pix_cnt <= 19'd0;
                    end else if (in_valid) begin
                        // Ping 缓冲基地址 = 0
                        ddr_mem[pix_cnt] <= in_pixel;
                        if (pix_cnt == IMG_SIZE - 1) begin
                            state   <= S_PROCESS;
                            pix_cnt <= 19'd0;
                        end else begin
                            pix_cnt <= pix_cnt + 1'b1;
                        end
                    end
                end

                // ---------------------------------------------
                // 第二段：从 DDR Ping 读出，喂给 sobel
                //        sobel 结果通过 ddr_wr 控制器写 DDR Pong
                // ---------------------------------------------
                S_PROCESS: begin
                    if (pix_cnt == 19'd0) begin
                        // 第一个周期：发 start_frame 脉冲
                        sobel_start_frame <= 1'b1;
                        sobel_in_valid    <= 1'b0;
                        pix_cnt           <= pix_cnt + 1'b1;
                    end else if (pix_cnt <= IMG_SIZE) begin
                        // 逐像素从 DDR Ping 读出
                        sobel_start_frame <= 1'b0;
                        sobel_in_valid    <= 1'b1;
                        sobel_in_pixel    <= ddr_mem[pix_cnt - 1];
                        pix_cnt           <= pix_cnt + 1'b1;
                    end else begin
                        sobel_in_valid <= 1'b0;
                    end

                    // sobel 完成整帧处理后，进入显示段
                    if (sobel_frame_done) begin
                        state   <= S_DISPLAY;
                        pix_cnt <= 19'd0;
                    end
                end

                // ---------------------------------------------
                // 第三段：从 DDR Pong 读出结果并输出
                // ---------------------------------------------
                S_DISPLAY: begin
                    out_valid <= 1'b1;
                    out_pixel <= ddr_mem[IMG_SIZE + pix_cnt]; // Pong 基地址
                    out_x     <= pix_cnt % IMG_W;
                    out_y     <= pix_cnt / IMG_W;

                    if (pix_cnt == IMG_SIZE - 1) begin
                        state   <= S_DONE;
                        pix_cnt <= 19'd0;
                    end else begin
                        pix_cnt <= pix_cnt + 1'b1;
                    end
                end

                // ---------------------------------------------
                // 结束：拉高 frame_done，回到采集
                // ---------------------------------------------
                S_DONE: begin
                    out_valid  <= 1'b0;
                    frame_done <= 1'b1;
                    state      <= S_CAPTURE;
                end
            endcase
        end
    end

    // ========================================================
    // DDR 写控制器：把 sobel 的输出写回 DDR Pong 缓冲
    // ========================================================
    always @(posedge clk) begin
        if (sobel_out_valid) begin
            ddr_mem[IMG_SIZE + sobel_out_y * IMG_W + sobel_out_x] <= sobel_out_pixel;
        end
    end

endmodule