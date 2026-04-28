`timescale 1ns / 1ps

module sccb_master_write #(
    parameter integer CLK_HZ      = 50_000_000,
    parameter integer SCCB_FREQ_HZ = 100_000
)(
    input  wire clk,
    input  wire rst_n,

    input  wire start,
    input  wire [7:0] dev_addr_w, // 8bit 写地址，例如 8'h60
    input  wire [7:0] reg_addr,
    input  wire [7:0] reg_data,

    inout  wire sccb_scl,
    inout  wire sccb_sda,

    output reg  busy,
    output reg  done,
    output reg  ack_error
);

    // ------------------------------------------------------------
    // 开漏输出：拉低为 0，释放为 Z，由外部上拉变成 1
    // ------------------------------------------------------------
    reg scl_drive_low;
    reg sda_drive_low;

    assign sccb_scl = scl_drive_low ? 1'b0 : 1'bz;
    assign sccb_sda = sda_drive_low ? 1'b0 : 1'bz;

    wire sda_in = sccb_sda;

    // ------------------------------------------------------------
    // quarter tick 发生器：1 个 tick = SCCB 周期的 1/4
    // ------------------------------------------------------------
    localparam integer DIVIDER = (CLK_HZ / (SCCB_FREQ_HZ * 4));
    reg [15:0] div_cnt;
    reg tick;

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

    // ------------------------------------------------------------
    // 写状态机：start -> dev_addr -> reg_addr -> reg_data -> stop
    // ------------------------------------------------------------
    localparam [3:0]
        S_IDLE  = 4'd0,
        S_START = 4'd1,
        S_SEND  = 4'd2,
        S_ACK   = 4'd3,
        S_STOP  = 4'd4,
        S_DONE  = 4'd5;

    reg [3:0] state;
    reg [1:0] phase;
    reg [1:0] byte_idx;   // 0:dev, 1:reg, 2:data
    reg [2:0] bit_idx;
    reg [7:0] cur_byte;
    reg start_pending;

    function [7:0] select_byte;
        input [1:0] idx;
        input [7:0] dev_addr_w_i;
        input [7:0] reg_addr_i;
        input [7:0] reg_data_i;
        begin
            case (idx)
                2'd0: select_byte = dev_addr_w_i;
                2'd1: select_byte = reg_addr_i;
                2'd2: select_byte = reg_data_i;
                default: select_byte = 8'h00;
            endcase
        end
    endfunction

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

            // Lock the one-cycle request until the SCCB state machine reaches its own tick.
            if (start)
                start_pending <= 1'b1;

            if (tick) begin
                case (state)
                    S_IDLE: begin
                        scl_drive_low <= 1'b0; // release high
                        sda_drive_low <= 1'b0; // release high
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
                        case (phase)
                            2'd0: begin
                                scl_drive_low <= 1'b0;
                                sda_drive_low <= 1'b0;
                                phase         <= 2'd1;
                            end
                            2'd1: begin
                                scl_drive_low <= 1'b0;
                                sda_drive_low <= 1'b1; // SDA low while SCL high
                                phase         <= 2'd2;
                            end
                            2'd2: begin
                                scl_drive_low <= 1'b1; // pull SCL low
                                sda_drive_low <= 1'b1;
                                phase         <= 2'd3;
                            end
                            2'd3: begin
                                phase  <= 2'd0;
                                state  <= S_SEND;
                            end
                        endcase
                    end

                    S_SEND: begin
                        case (phase)
                            2'd0: begin
                                scl_drive_low <= 1'b1; // SCL low, set data
                                sda_drive_low <= ~cur_byte[bit_idx]; // bit=0 拉低；bit=1 释放
                                phase         <= 2'd1;
                            end
                            2'd1: begin
                                scl_drive_low <= 1'b0; // SCL high
                                phase         <= 2'd2;
                            end
                            2'd2: begin
                                scl_drive_low <= 1'b0; // keep high
                                phase         <= 2'd3;
                            end
                            2'd3: begin
                                scl_drive_low <= 1'b1; // SCL low
                                if (bit_idx == 3'd0) begin
                                    phase <= 2'd0;
                                    state <= S_ACK;
                                end else begin
                                    bit_idx <= bit_idx - 1'b1;
                                    phase   <= 2'd0;
                                end
                            end
                        endcase
                    end

                    S_ACK: begin
                        case (phase)
                            2'd0: begin
                                scl_drive_low <= 1'b1; // low
                                sda_drive_low <= 1'b0; // release SDA for ACK
                                phase         <= 2'd1;
                            end
                            2'd1: begin
                                scl_drive_low <= 1'b0; // high
                                phase         <= 2'd2;
                            end
                            2'd2: begin
                                // ACK=0, NACK=1
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
                        endcase
                    end

                    S_STOP: begin
                        case (phase)
                            2'd0: begin
                                scl_drive_low <= 1'b1;
                                sda_drive_low <= 1'b1; // SDA low
                                phase         <= 2'd1;
                            end
                            2'd1: begin
                                scl_drive_low <= 1'b0; // SCL high
                                sda_drive_low <= 1'b1;
                                phase         <= 2'd2;
                            end
                            2'd2: begin
                                scl_drive_low <= 1'b0;
                                sda_drive_low <= 1'b0; // SDA release -> stop
                                phase         <= 2'd3;
                            end
                            2'd3: begin
                                phase <= 2'd0;
                                state <= S_DONE;
                            end
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
                endcase
            end
        end
    end

endmodule
