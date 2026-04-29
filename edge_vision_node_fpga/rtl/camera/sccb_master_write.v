`timescale 1ns / 1ps
// SCCB 单寄存器写主机。
// 该模块产生 SIOC/SIOD 时序，依次发送设备地址、寄存器地址和寄存器数据并采样应答。

module sccb_master_write #(

    // 参数用于适配不同图像尺寸、时钟频率、缓冲深度或网络地址。
    parameter integer CLK_HZ      = 50_000_000,

    // 参数用于适配不同图像尺寸、时钟频率、缓冲深度或网络地址。
    parameter integer SCCB_FREQ_HZ = 100_000
)(
    input  wire clk,
    input  wire rst_n,

    input  wire start,
    input  wire [7:0] dev_addr_w,
    input  wire [7:0] reg_addr,
    input  wire [7:0] reg_data,

    inout  wire sccb_scl,
    inout  wire sccb_sda,

    output reg  busy,
    output reg  done,
    output reg  ack_error

// 端口列表到此结束，下面进入内部寄存器、组合连线和时序逻辑。
);

    // reg 信号保存跨周期状态、计数器、握手标志和流水线寄存结果。
    reg scl_drive_low;
    reg sda_drive_low;

    // 连续赋值用于输出固定映射、组合判断或协议字段拼接。
    assign sccb_scl = scl_drive_low ? 1'b0 : 1'bz;

    // 连续赋值用于输出固定映射、组合判断或协议字段拼接。
    assign sccb_sda = sda_drive_low ? 1'b0 : 1'bz;

    // wire 信号承载组合逻辑结果或子模块之间的连接。
    wire sda_in = sccb_sda;

    // 本地常量定义状态编码、计数上限或协议字段，避免魔法数字散落在逻辑中。
    localparam integer DIVIDER = (CLK_HZ / (SCCB_FREQ_HZ * 4));
    reg [15:0] div_cnt;
    reg tick;

    // 时序逻辑：在指定时钟沿更新状态，并在复位时恢复到安全初值。
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            div_cnt <= 16'd0;
            tick    <= 1'b0;
        end else begin
            if (div_cnt == DIVIDER - 1) begin
                div_cnt <= 16'd0;
                tick    <= 1'b1;
            end else begin
                div_cnt <= div_cnt + 1'b1;
                tick    <= 1'b0;
            end
        end
    end

    localparam [3:0]
        S_IDLE  = 4'd0,
        S_START = 4'd1,
        S_SEND  = 4'd2,
        S_ACK   = 4'd3,
        S_STOP  = 4'd4,
        S_DONE  = 4'd5;

    reg [3:0] state;
    reg [1:0] phase;
    reg [1:0] byte_idx;
    reg [2:0] bit_idx;
    reg [7:0] cur_byte;
    reg start_pending;

    function [7:0] select_byte;
        input [1:0] idx;
        input [7:0] dev_addr_w_i;
        input [7:0] reg_addr_i;
        input [7:0] reg_data_i;
        begin

            // 状态机分支：按当前阶段执行握手、计数或数据搬运动作。
            case (idx)
                2'd0: select_byte = dev_addr_w_i;
                2'd1: select_byte = reg_addr_i;
                2'd2: select_byte = reg_data_i;
                default: select_byte = 8'h00;

            // 状态机分支结束，未命中的情况由默认分支回到安全状态。
            endcase
        end
    endfunction

    // 时序逻辑：在指定时钟沿更新状态，并在复位时恢复到安全初值。
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state         <= S_IDLE;
            phase         <= 2'd0;
            byte_idx      <= 2'd0;
            bit_idx       <= 3'd7;
            cur_byte      <= 8'h00;
            start_pending <= 1'b0;
            busy          <= 1'b0;
            done          <= 1'b0;
            ack_error     <= 1'b0;
            scl_drive_low <= 1'b0;
            sda_drive_low <= 1'b0;
        end else begin
            done <= 1'b0;

            if (start)
                start_pending <= 1'b1;

            if (tick) begin

            // 状态机分支：按当前阶段执行握手、计数或数据搬运动作。
                case (state)
                    S_IDLE: begin
                        scl_drive_low <= 1'b0;
                        sda_drive_low <= 1'b0;
                        busy          <= 1'b0;
                        ack_error     <= 1'b0;
                        phase         <= 2'd0;
                        if (start_pending) begin
                            start_pending <= 1'b0;
                            busy     <= 1'b1;
                            byte_idx <= 2'd0;
                            cur_byte <= dev_addr_w;
                            bit_idx  <= 3'd7;
                            state    <= S_START;
                        end
                    end

                    S_START: begin

            // 状态机分支：按当前阶段执行握手、计数或数据搬运动作。
                        case (phase)
                            2'd0: begin
                                scl_drive_low <= 1'b0;
                                sda_drive_low <= 1'b0;
                                phase         <= 2'd1;
                            end
                            2'd1: begin
                                scl_drive_low <= 1'b0;
                                sda_drive_low <= 1'b1;
                                phase         <= 2'd2;
                            end
                            2'd2: begin
                                scl_drive_low <= 1'b1;
                                sda_drive_low <= 1'b1;
                                phase         <= 2'd3;
                            end
                            2'd3: begin
                                phase  <= 2'd0;
                                state  <= S_SEND;
                            end

            // 状态机分支结束，未命中的情况由默认分支回到安全状态。
                        endcase
                    end

                    S_SEND: begin
                        case (phase)
                            2'd0: begin
                                scl_drive_low <= 1'b1;
                                sda_drive_low <= ~cur_byte[bit_idx];
                                phase         <= 2'd1;
                            end
                            2'd1: begin
                                scl_drive_low <= 1'b0;
                                phase         <= 2'd2;
                            end
                            2'd2: begin
                                scl_drive_low <= 1'b0;
                                phase         <= 2'd3;
                            end
                            2'd3: begin
                                scl_drive_low <= 1'b1;
                                if (bit_idx == 3'd0) begin
                                    phase <= 2'd0;
                                    state <= S_ACK;
                                end else begin
                                    bit_idx <= bit_idx - 1'b1;
                                    phase   <= 2'd0;
                                end
                            end

            // 状态机分支结束，未命中的情况由默认分支回到安全状态。
                        endcase
                    end

                    S_ACK: begin
                        case (phase)
                            2'd0: begin
                                scl_drive_low <= 1'b1;
                                sda_drive_low <= 1'b0;
                                phase         <= 2'd1;
                            end
                            2'd1: begin
                                scl_drive_low <= 1'b0;
                                phase         <= 2'd2;
                            end
                            2'd2: begin

                                if (sda_in == 1'b1)
                                    ack_error <= 1'b1;
                                phase <= 2'd3;
                            end
                            2'd3: begin
                                scl_drive_low <= 1'b1;
                                sda_drive_low <= 1'b0;

                                if (byte_idx == 2'd2) begin
                                    phase <= 2'd0;
                                    state <= S_STOP;
                                end else begin
                                    byte_idx <= byte_idx + 1'b1;
                                    cur_byte <= select_byte(byte_idx + 1'b1, dev_addr_w, reg_addr, reg_data);
                                    bit_idx  <= 3'd7;
                                    phase    <= 2'd0;
                                    state    <= S_SEND;
                                end
                            end

            // 状态机分支结束，未命中的情况由默认分支回到安全状态。
                        endcase
                    end

                    S_STOP: begin
                        case (phase)
                            2'd0: begin
                                scl_drive_low <= 1'b1;
                                sda_drive_low <= 1'b1;
                                phase         <= 2'd1;
                            end
                            2'd1: begin
                                scl_drive_low <= 1'b0;
                                sda_drive_low <= 1'b1;
                                phase         <= 2'd2;
                            end
                            2'd2: begin
                                scl_drive_low <= 1'b0;
                                sda_drive_low <= 1'b0;
                                phase         <= 2'd3;
                            end
                            2'd3: begin
                                phase <= 2'd0;
                                state <= S_DONE;
                            end

            // 状态机分支结束，未命中的情况由默认分支回到安全状态。
                        endcase
                    end

                    S_DONE: begin
                        scl_drive_low <= 1'b0;
                        sda_drive_low <= 1'b0;
                        busy          <= 1'b0;
                        done          <= 1'b1;
                        state         <= S_IDLE;
                    end

                    default: begin
                        state         <= S_IDLE;
                        phase         <= 2'd0;
                        busy          <= 1'b0;
                        done          <= 1'b0;
                        ack_error     <= 1'b0;
                        scl_drive_low <= 1'b0;
                        sda_drive_low <= 1'b0;
                    end

            // 状态机分支结束，未命中的情况由默认分支回到安全状态。
                endcase
            end
        end
    end

endmodule
