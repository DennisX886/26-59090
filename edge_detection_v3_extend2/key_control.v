`timescale 1ns/1ps

// ============================================================
// 实时阈值按键控制模块
//
// 功能：
//   key_plus  : 按一次，threshold 增加 STEP
//   key_minus : 按一次，threshold 减少 STEP
//
// 内部包含：
//   1. 两级同步
//   2. 按键消抖
//   3. 单脉冲检测
//   4. 阈值寄存器
//
// 默认阈值：128
// 默认步进：10
// 默认消抖时间：20 ms @ 50 MHz
//
// 仿真时可以把 DEBOUNCE_CYCLES 调小，例如设为 4。
// ============================================================
module key_control #(
    parameter CLK_FREQ_HZ    = 50_000_000,
    parameter DEBOUNCE_MS    = 20,
    parameter DEBOUNCE_CYCLES = (CLK_FREQ_HZ / 1000) * DEBOUNCE_MS,
    parameter INIT_THRESHOLD = 128,
    parameter STEP           = 10
)(
    input            clk,
    input            rst_n,
    input            key_plus,
    input            key_minus,

    output reg [7:0] threshold
);

    // ------------------------------------------------------------
    // 两级同步，避免按键异步输入直接进入逻辑。
    // ------------------------------------------------------------
    reg plus_sync1,  plus_sync2;
    reg minus_sync1, minus_sync2;

    // ------------------------------------------------------------
    // 消抖后的稳定按键状态
    // ------------------------------------------------------------
    reg plus_state;
    reg minus_state;

    integer plus_cnt;
    integer minus_cnt;

    // ------------------------------------------------------------
    // 用于检测“稳定状态从0变1”，形成一个时钟周期的按键脉冲。
    // ------------------------------------------------------------
    reg plus_state_d;
    reg minus_state_d;

    wire plus_pulse  = plus_state  & ~plus_state_d;
    wire minus_pulse = minus_state & ~minus_state_d;

    localparam [7:0] INIT_THRESHOLD_VALUE = INIT_THRESHOLD;
    localparam [7:0] STEP_VALUE           = STEP;

    // ------------------------------------------------------------
    // 按键同步 + 消抖 + 阈值调整
    // ------------------------------------------------------------
    always @(posedge clk) begin
        if (!rst_n) begin
            plus_sync1  <= 1'b0;
            plus_sync2  <= 1'b0;
            minus_sync1 <= 1'b0;
            minus_sync2 <= 1'b0;

            plus_state  <= 1'b0;
            minus_state <= 1'b0;

            plus_state_d  <= 1'b0;
            minus_state_d <= 1'b0;

            plus_cnt  <= 0;
            minus_cnt <= 0;

            threshold <= INIT_THRESHOLD_VALUE;
        end else begin
            // 两级同步
            plus_sync1  <= key_plus;
            plus_sync2  <= plus_sync1;
            minus_sync1 <= key_minus;
            minus_sync2 <= minus_sync1;

            // ----------------------------------------------------
            // +键消抖
            // 输入与当前稳定状态不同，开始计数。
            // 连续稳定 DEBOUNCE_CYCLES 个时钟后才更新状态。
            // ----------------------------------------------------
            if (plus_sync2 == plus_state) begin
                plus_cnt <= 0;
            end else begin
                if (plus_cnt >= DEBOUNCE_CYCLES - 1) begin
                    plus_state <= plus_sync2;
                    plus_cnt   <= 0;
                end else begin
                    plus_cnt <= plus_cnt + 1;
                end
            end

            // ----------------------------------------------------
            // -键消抖
            // ----------------------------------------------------
            if (minus_sync2 == minus_state) begin
                minus_cnt <= 0;
            end else begin
                if (minus_cnt >= DEBOUNCE_CYCLES - 1) begin
                    minus_state <= minus_sync2;
                    minus_cnt   <= 0;
                end else begin
                    minus_cnt <= minus_cnt + 1;
                end
            end

            // 保存上一拍的稳定状态，用于边沿检测。
            plus_state_d  <= plus_state;
            minus_state_d <= minus_state;

            // ----------------------------------------------------
            // 阈值寄存器
            // 上限255，下限0，防止8位寄存器溢出。
            // ----------------------------------------------------
            if (plus_pulse && !minus_pulse) begin
                if (threshold > (8'd255 - STEP_VALUE))
                    threshold <= 8'd255;
                else
                    threshold <= threshold + STEP_VALUE;
            end else if (minus_pulse && !plus_pulse) begin
                if (threshold < STEP_VALUE)
                    threshold <= 8'd0;
                else
                    threshold <= threshold - STEP_VALUE;
            end
        end
    end

endmodule
