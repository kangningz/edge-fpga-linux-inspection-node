`timescale 1ns / 1ps
// OV2640 最小初始化寄存器表。
// SCCB 初始化状态机会按索引读取该表，把地址和值依次写入摄像头。

module ov2640_init_table_min (
    input  wire [7:0] index,
    output reg  [7:0] reg_addr,
    output reg  [7:0] reg_data,
    output reg        is_delay,
    output reg [23:0] delay_ms,
    output reg        table_end

// 端口列表到此结束，下面进入内部寄存器、组合连线和时序逻辑。
);

    // 组合逻辑：根据当前状态和输入信号计算下一拍控制结果。
    always @(*) begin
        reg_addr  = 8'h00;
        reg_data  = 8'h00;
        is_delay  = 1'b0;
        delay_ms  = 24'd0;
        table_end = 1'b0;

            // 状态机分支：按当前阶段执行握手、计数或数据搬运动作。
        case (index)
            8'd0: begin
                reg_addr = 8'h12;
                reg_data = 8'h80;
            end

            8'd1: begin
                is_delay = 1'b1;
                delay_ms = 24'd5;
            end

            8'd2: begin
                reg_addr = 8'hFF;
                reg_data = 8'h00;
            end

            8'd3: begin
                reg_addr = 8'hFF;
                reg_data = 8'h01;
            end

            default: begin
                table_end = 1'b1;
            end

            // 状态机分支结束，未命中的情况由默认分支回到安全状态。
        endcase
    end

endmodule
