`timescale 1ns / 1ps

module clk_rst_mgr #(
    parameter integer SYS_CLK_HZ  = 50_000_000,
    parameter integer CAM_XCLK_HZ = 25_000_000
)(
    input  wire fpga_clk_in,   // ACX750 板载 50MHz 时钟
    input  wire ext_rst_n,     // 外部低有效复位

    output wire sys_clk,       // 当前先直接等于板载 50MHz
    output reg  cam_xclk,      // 给 OV2640 的 XCLK
    output reg  rst_n_sys      // 同步后的系统复位
);

    assign sys_clk = fpga_clk_in;

    // ------------------------------------------------------------
    // XCLK 发生器
    // 这里先用最简单的整数分频。
    // 50MHz -> 25MHz 时，每 1 个 sys_clk 翻转一次即可。
    // ------------------------------------------------------------
    localparam integer CAM_DIV = (SYS_CLK_HZ / (CAM_XCLK_HZ * 2));
    initial cam_xclk = 1'b0;

    integer cam_div_cnt;
    always @(posedge fpga_clk_in or negedge ext_rst_n) begin
        if (!ext_rst_n) begin
            cam_div_cnt <= 0;
            cam_xclk    <= 1'b0;
        end else begin
            if (cam_div_cnt == CAM_DIV - 1) begin
                cam_div_cnt <= 0;
                cam_xclk    <= ~cam_xclk;
            end else begin
                cam_div_cnt <= cam_div_cnt + 1;
            end
        end
    end

    // ------------------------------------------------------------
    // 复位同步
    // ------------------------------------------------------------
    reg [3:0] rst_sync_ff;
    always @(posedge fpga_clk_in or negedge ext_rst_n) begin
        if (!ext_rst_n) begin
            rst_sync_ff <= 4'b0000;
            rst_n_sys   <= 1'b0;
        end else begin
            rst_sync_ff <= {rst_sync_ff[2:0], 1'b1};
            rst_n_sys   <= rst_sync_ff[3];
        end
    end

endmodule