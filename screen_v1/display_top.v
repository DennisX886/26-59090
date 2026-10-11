module display_top(
    input               sys_clk_100m,     //【100M写时钟域】系统全局时钟100MHz
    input               pix_clk_25m,       //【25M读时钟域】LCD像素时钟25M
    input               rst_n,             //全局低电平复位

    //================ 联调对接【边缘检测模块】输入接口【100M时钟域】================
    input               edge_frame_done,  //一帧图像处理完成，100M域，单周期脉冲
    input        [1:0]  edge_buf_sel,      //帧缓存选择信号 0:BUF0 1:BUF1，100M域
    input               fifo_wr,           //FIFO写使能，100M域，高有效，由边缘模块输出
    input        [7:0]  fifo_wdata,        //FIFO写入像素数据，100M域，由边缘模块输出

    //================ 输出到LVDS TX IP并行LCD信号【25M时钟域】================
    output              lcd_hs,
    output              lcd_vs,
    output              lcd_de,
    output [7:0]        lcd_r,
    output [7:0]        lcd_g,
    output [7:0]        lcd_b
);

parameter H_ACT = 640;
parameter V_ACT = 480;

//内部信号
wire fifo_rd;
wire [7:0] fifo_rdata;
wire fifo_full;
wire fifo_empty;

//------------------------------------------
// 异步FIFO IP：fifo_async_8bit_2048
// 写时钟100M，读时钟25M，位宽8bit，深度2048
//------------------------------------------
fifo_async_8bit_2048 u_fifo_async_8bit_2048(
    .wr_clk  (sys_clk_100m),
    .rd_clk  (pix_clk_25m),
    .wr_rst_n(rst_n),
    .rd_rst_n(rst_n),
    .wr_en   (fifo_wr),
    .rd_en   (fifo_rd),
    .din     (fifo_wdata),
    .dout    (fifo_rdata),
    .full    (fifo_full),
    .empty   (fifo_empty)
);

//------------------------------------------
// VGA时序模块：vga_640_480_timing
//------------------------------------------
wire [9:0] h_cnt;
wire [9:0] v_cnt;
vga_640_480_timing u_vga_timing(
    .pix_clk(pix_clk_25m),
    .rst_n(rst_n),
    .hs(lcd_hs),
    .vs(lcd_vs),
    .de(lcd_de),
    .h_cnt(h_cnt),
    .v_cnt(v_cnt)
);

//------------------------------------------
// FIFO读控制逻辑：LCD有效显示区域时读取像素【25M域】
// 屏幕DE有效，且FIFO非空，就读出像素
//------------------------------------------
assign fifo_rd = lcd_de & (~fifo_empty);

//像素输出至LVDS
assign lcd_r = fifo_rdata;
assign lcd_g = fifo_rdata;
assign lcd_b = fifo_rdata;

endmodule
