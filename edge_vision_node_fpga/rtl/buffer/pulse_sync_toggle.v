`timescale 1ns / 1ps
// 跨时钟域单脉冲同步器。
// 源域把脉冲翻转为电平变化，目标域双触发采样后恢复为单周期脉冲。

module pulse_sync_toggle (
    input  wire src_clk,
    input  wire src_rst_n,
    input  wire src_pulse,

    input  wire dst_clk,
    input  wire dst_rst_n,
    output wire dst_pulse

// 端口列表到此结束，下面进入内部寄存器、组合连线和时序逻辑。
);

    // reg 信号保存跨周期状态、计数器、握手标志和流水线寄存结果。
    reg src_toggle;

    // 时序逻辑：在指定时钟沿更新状态，并在复位时恢复到安全初值。
    always @(posedge src_clk or negedge src_rst_n) begin
        if (!src_rst_n) begin
            src_toggle <= 1'b0;
        end else if (src_pulse) begin
            src_toggle <= ~src_toggle;
        end
    end

    (* ASYNC_REG = "TRUE" *) reg dst_ff0;
    (* ASYNC_REG = "TRUE" *) reg dst_ff1;
    reg dst_ff2;

    // 时序逻辑：在指定时钟沿更新状态，并在复位时恢复到安全初值。
    always @(posedge dst_clk or negedge dst_rst_n) begin
        if (!dst_rst_n) begin
            dst_ff0 <= 1'b0;
            dst_ff1 <= 1'b0;
            dst_ff2 <= 1'b0;
        end else begin
            dst_ff0 <= src_toggle;
            dst_ff1 <= dst_ff0;
            dst_ff2 <= dst_ff1;
        end
    end

    // 连续赋值用于输出固定映射、组合判断或协议字段拼接。
    assign dst_pulse = dst_ff1 ^ dst_ff2;

endmodule
