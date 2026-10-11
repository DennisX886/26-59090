module vga_640_480_timing(
    input               pix_clk,
    input               rst_n,
    output reg          hs,
    output reg          vs,
    output reg          de,
    output reg [9:0]    h_cnt,
    output reg [9:0]    v_cnt
);

//640x480@60Hz，25MHz
parameter H_SYNC  = 96;
parameter H_BACK  = 48;
parameter H_ACT   = 640;
parameter H_FRONT = 16;
parameter H_TOTAL = H_SYNC + H_BACK + H_ACT + H_FRONT;

parameter V_SYNC  = 2;
parameter V_BACK  = 33;
parameter V_ACT   = 480;
parameter V_FRONT = 10;
parameter V_TOTAL = V_SYNC + V_BACK + V_ACT + V_FRONT;

always @(posedge pix_clk or negedge rst_n) begin
    if(!rst_n) begin
        h_cnt <= 10'd0;
        v_cnt <= 10'd0;
    end
    else begin
        if(h_cnt < H_TOTAL - 1) begin
            h_cnt <= h_cnt + 10'd1;
        end
        else begin
            h_cnt <= 10'd0;
            if(v_cnt < V_TOTAL -1)
                v_cnt <= v_cnt + 10'd1;
            else
                v_cnt <= 10'd0;
        end
    end
end

always @(*) begin
    hs = (h_cnt < H_SYNC) ? 1'b0 : 1'b1;
    vs = (v_cnt < V_SYNC) ? 1'b0 : 1'b1;
    de = ( (h_cnt >= H_SYNC+H_BACK) && (h_cnt < H_SYNC+H_BACK+H_ACT)
         && (v_cnt >= V_SYNC+V_BACK) && (v_cnt < V_SYNC+V_BACK+V_ACT) );
end

endmodule
