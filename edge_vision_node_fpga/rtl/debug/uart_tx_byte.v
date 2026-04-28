`timescale 1ns / 1ps

module uart_tx_byte #(
    parameter integer CLK_HZ   = 50_000_000,
    parameter integer BAUDRATE = 115200
)(
    input  wire clk,
    input  wire rst_n,

    input  wire start,
    input  wire [7:0] tx_data,

    output reg  txd,
    output reg  busy,
    output reg  done
);

    localparam integer CLKS_PER_BIT = CLK_HZ / BAUDRATE;

    localparam [2:0]
        S_IDLE  = 3'd0,
        S_START = 3'd1,
        S_DATA  = 3'd2,
        S_STOP  = 3'd3,
        S_DONE  = 3'd4;

    reg [2:0] state;
    reg [15:0] clk_cnt;
    reg [2:0] bit_idx;
    reg [7:0] data_buf;

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
            endcase
        end
    end

endmodule