`timescale 1ns / 1ps
// UART 单字节发送器。
// 按配置波特率生成起始位、8 位数据位和停止位。

module uart_tx_byte #(

    // 参数用于适配不同图像尺寸、时钟频率、缓冲深度或网络地址。
    parameter integer CLK_HZ   = 50_000_000,

    // 参数用于适配不同图像尺寸、时钟频率、缓冲深度或网络地址。
    parameter integer BAUDRATE = 115200
)(
    input  wire clk,
    input  wire rst_n,

    input  wire start,
    input  wire [7:0] tx_data,

    output reg  txd,
    output reg  busy,
    output reg  done

// 端口列表到此结束，下面进入内部寄存器、组合连线和时序逻辑。
);

    // 本地常量定义状态编码、计数上限或协议字段，避免魔法数字散落在逻辑中。
    localparam integer CLKS_PER_BIT = CLK_HZ / BAUDRATE;

    localparam [2:0]
        S_IDLE  = 3'd0,
        S_START = 3'd1,
        S_DATA  = 3'd2,
        S_STOP  = 3'd3,
        S_DONE  = 3'd4;

    // reg 信号保存跨周期状态、计数器、握手标志和流水线寄存结果。
    reg [2:0] state;
    reg [15:0] clk_cnt;
    reg [2:0] bit_idx;
    reg [7:0] data_buf;

    // 时序逻辑：在指定时钟沿更新状态，并在复位时恢复到安全初值。
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state   <= S_IDLE;
            clk_cnt <= 16'd0;
            bit_idx <= 3'd0;
            data_buf<= 8'd0;
            txd     <= 1'b1;
            busy    <= 1'b0;
            done    <= 1'b0;
        end else begin
            done <= 1'b0;

            // 状态机分支：按当前阶段执行握手、计数或数据搬运动作。
            case (state)
                S_IDLE: begin
                    txd  <= 1'b1;
                    busy <= 1'b0;
                    clk_cnt <= 16'd0;
                    bit_idx <= 3'd0;
                    if (start) begin
                        data_buf <= tx_data;
                        busy     <= 1'b1;
                        state    <= S_START;
                    end
                end

                S_START: begin
                    txd <= 1'b0;
                    if (clk_cnt == CLKS_PER_BIT - 1) begin
                        clk_cnt <= 16'd0;
                        state   <= S_DATA;
                    end else begin
                        clk_cnt <= clk_cnt + 1'b1;
                    end
                end

                S_DATA: begin
                    txd <= data_buf[bit_idx];
                    if (clk_cnt == CLKS_PER_BIT - 1) begin
                        clk_cnt <= 16'd0;
                        if (bit_idx == 3'd7) begin
                            bit_idx <= 3'd0;
                            state   <= S_STOP;
                        end else begin
                            bit_idx <= bit_idx + 1'b1;
                        end
                    end else begin
                        clk_cnt <= clk_cnt + 1'b1;
                    end
                end

                S_STOP: begin
                    txd <= 1'b1;
                    if (clk_cnt == CLKS_PER_BIT - 1) begin
                        clk_cnt <= 16'd0;
                        state   <= S_DONE;
                    end else begin
                        clk_cnt <= clk_cnt + 1'b1;
                    end
                end

                S_DONE: begin
                    txd  <= 1'b1;
                    busy <= 1'b0;
                    done <= 1'b1;
                    state<= S_IDLE;
                end

                default: begin
                    state   <= S_IDLE;
                    txd     <= 1'b1;
                    busy    <= 1'b0;
                    done    <= 1'b0;
                    clk_cnt <= 16'd0;
                    bit_idx <= 3'd0;
                end

            // 状态机分支结束，未命中的情况由默认分支回到安全状态。
            endcase
        end
    end

endmodule
