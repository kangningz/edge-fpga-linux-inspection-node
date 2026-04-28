`timescale 1ns / 1ps

module ov2640_init_table_min (
    input  wire [7:0] index,
    output reg  [7:0] reg_addr,
    output reg  [7:0] reg_data,
    output reg        is_delay,      // 1: 这一项不是写寄存器，而是延时命令
    output reg [23:0] delay_ms,
    output reg        table_end
);

    // ------------------------------------------------------------
    // 最小 bring-up 表
    // 目的：先验证 SCCB 写通路。
    //
    // 说明：
    // 1) 第 0 项：软件复位
    // 2) 第 1 项：延时 5ms
    // 3) 第 2 项：切 DSP bank
    // 4) 第 3 项：切 Sensor bank
    //
    // 这不是最终成像配置表。
    // 后面你把 OV2640 例程或寄存器表贴给我后，我再把它替换成完整版本。
    // ------------------------------------------------------------

    always @(*) begin
        reg_addr  = 8'h00;
        reg_data  = 8'h00;
        is_delay  = 1'b0;
        delay_ms  = 24'd0;
        table_end = 1'b0;

        case (index)
            8'd0: begin
                reg_addr = 8'h12;
                reg_data = 8'h80; // COM7 software reset
            end

            8'd1: begin
                is_delay = 1'b1;
                delay_ms = 24'd5;
            end

            8'd2: begin
                reg_addr = 8'hFF;
                reg_data = 8'h00; // DSP bank
            end

            8'd3: begin
                reg_addr = 8'hFF;
                reg_data = 8'h01; // Sensor bank
            end

            default: begin
                table_end = 1'b1;
            end
        endcase
    end

endmodule