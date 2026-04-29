`timescale 1ns / 1ps
// OV2640 上电复位时序模块。
// 按照电源稳定、PWDN、RESET 和配置启动之间的延时要求产生摄像头控制信号。

module ov2640_power_seq #(

    // 参数用于适配不同图像尺寸、时钟频率、缓冲深度或网络地址。
    parameter integer CLK_HZ = 50_000_000
)(
    input  wire clk,
    input  wire rst_n,

    output reg  camera_pwdn,
    output reg  camera_rst_n,
    output reg  seq_done

// 端口列表到此结束，下面进入内部寄存器、组合连线和时序逻辑。
);

    // 本地常量定义状态编码、计数上限或协议字段，避免魔法数字散落在逻辑中。
    localparam integer T_5MS  = CLK_HZ / 200;
    localparam integer T_1MS  = CLK_HZ / 1000;
    localparam integer T_20MS = CLK_HZ / 50;

    localparam [1:0]
        S_HOLD_PWDN = 2'd0,
        S_RELEASE_P = 2'd1,
        S_RELEASE_R = 2'd2,
        S_DONE      = 2'd3;

    // reg 信号保存跨周期状态、计数器、握手标志和流水线寄存结果。
    reg [1:0] state;
    reg [31:0] cnt;

    // 时序逻辑：在指定时钟沿更新状态，并在复位时恢复到安全初值。
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state        <= S_HOLD_PWDN;
            cnt          <= 32'd0;
            camera_pwdn  <= 1'b1;
            camera_rst_n <= 1'b0;
            seq_done     <= 1'b0;
        end else begin

            // 状态机分支：按当前阶段执行握手、计数或数据搬运动作。
            case (state)
                S_HOLD_PWDN: begin
                    camera_pwdn  <= 1'b1;
                    camera_rst_n <= 1'b0;
                    seq_done     <= 1'b0;
                    if (cnt >= T_5MS - 1) begin
                        cnt   <= 32'd0;
                        state <= S_RELEASE_P;
                    end else begin
                        cnt <= cnt + 1'b1;
                    end
                end

                S_RELEASE_P: begin
                    camera_pwdn  <= 1'b0;
                    camera_rst_n <= 1'b0;
                    if (cnt >= T_1MS - 1) begin
                        cnt   <= 32'd0;
                        state <= S_RELEASE_R;
                    end else begin
                        cnt <= cnt + 1'b1;
                    end
                end

                S_RELEASE_R: begin
                    camera_pwdn  <= 1'b0;
                    camera_rst_n <= 1'b1;
                    if (cnt >= T_20MS - 1) begin
                        cnt   <= 32'd0;
                        state <= S_DONE;
                    end else begin
                        cnt <= cnt + 1'b1;
                    end
                end

                S_DONE: begin
                    camera_pwdn  <= 1'b0;
                    camera_rst_n <= 1'b1;
                    seq_done     <= 1'b1;
                end

                default: begin
                    state        <= S_HOLD_PWDN;
                    cnt          <= 32'd0;
                    camera_pwdn  <= 1'b1;
                    camera_rst_n <= 1'b0;
                    seq_done     <= 1'b0;
                end

            // 状态机分支结束，未命中的情况由默认分支回到安全状态。
            endcase
        end
    end

endmodule
