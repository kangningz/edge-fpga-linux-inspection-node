`timescale 1ns / 1ps
// OV2640 状态总线打包模块。
// 把若干分散的摄像头状态信号组合成统一调试总线。

module ov2640_status_bus (
    input  wire        init_done,
    input  wire        init_error,
    input  wire        frame_locked,
    input  wire [15:0] frame_cnt,
    input  wire [15:0] line_cnt_last,
    input  wire [31:0] pixel_cnt_last,

    output wire [63:0] status_bus

// 端口列表到此结束，下面进入内部寄存器、组合连线和时序逻辑。
);

    // 连续赋值用于输出固定映射、组合判断或协议字段拼接。
    assign status_bus = {
        12'd0,
        init_done,
        init_error,
        frame_locked,
        1'b0,
        frame_cnt,
        line_cnt_last,
        pixel_cnt_last[15:0]
    };

endmodule
