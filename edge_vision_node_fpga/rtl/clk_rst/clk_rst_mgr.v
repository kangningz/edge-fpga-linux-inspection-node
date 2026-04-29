`timescale 1ns / 1ps
// 系统时钟和复位管理模块。
// 从板级时钟生成内部控制时钟和 OV2640 XCLK，并在时钟稳定后释放复位。

module clk_rst_mgr #(

    // 参数用于适配不同图像尺寸、时钟频率、缓冲深度或网络地址。
    parameter integer SYS_CLK_HZ  = 50_000_000,

    // 参数用于适配不同图像尺寸、时钟频率、缓冲深度或网络地址。
    parameter integer CAM_XCLK_HZ = 25_000_000
)(
    input  wire fpga_clk_in,
    input  wire ext_rst_n,

    output wire sys_clk,
    output reg  cam_xclk,
    output reg  rst_n_sys

// 端口列表到此结束，下面进入内部寄存器、组合连线和时序逻辑。
);

    // 连续赋值用于输出固定映射、组合判断或协议字段拼接。
    assign sys_clk = fpga_clk_in;

    // 本地常量定义状态编码、计数上限或协议字段，避免魔法数字散落在逻辑中。
    localparam integer CAM_DIV = (SYS_CLK_HZ / (CAM_XCLK_HZ * 2));
    initial cam_xclk = 1'b0;

    integer cam_div_cnt;

    // 时序逻辑：在指定时钟沿更新状态，并在复位时恢复到安全初值。
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

    // reg 信号保存跨周期状态、计数器、握手标志和流水线寄存结果。
    reg [3:0] rst_sync_ff;

    // 时序逻辑：在指定时钟沿更新状态，并在复位时恢复到安全初值。
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
