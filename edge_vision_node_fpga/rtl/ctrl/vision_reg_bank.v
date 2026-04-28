`timescale 1ns / 1ps

// Runtime control register bank in the Ethernet/control clock domain.
//
// Linux sends UDP command packets. udp_cmd_packet_parser validates the packet,
// cmd_async_fifo crosses it into this clock domain, and this module updates the
// registers consumed by capture, preprocessing, telemetry, and alarm logic.

module vision_reg_bank (
    input  wire        clk,
    input  wire        rst_n,
    input  wire        cmd_valid,
    input  wire [7:0]  cmd_code,
    input  wire [15:0] cmd_seq,
    input  wire [15:0] cmd_addr,
    input  wire [31:0] cmd_data0,
    input  wire [31:0] cmd_data1,

    output reg         capture_enable,
    output reg         alarm_enable,
    output reg         debug_uart_enable,
    output reg  [10:0] roi_x,
    output reg  [10:0] roi_y,
    output reg  [10:0] roi_w,
    output reg  [10:0] roi_h,
    output reg  [7:0]  bright_threshold,
    output reg  [15:0] alarm_count_threshold,
    output reg  [1:0]  tx_mode,
    output reg         force_status_send,
    output reg         clear_error_pulse,
    output reg         last_cmd_error,
    output reg  [15:0] last_cmd_seq
);

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            capture_enable    <= 1'b1;
            alarm_enable      <= 1'b1;
            debug_uart_enable <= 1'b0;
            roi_x             <= 11'd0;
            roi_y             <= 11'd0;
            roi_w             <= 11'd64;
            roi_h             <= 11'd64;
            bright_threshold  <= 8'd128;
            alarm_count_threshold <= 16'd256;
            tx_mode           <= 2'd2;
            force_status_send <= 1'b0;
            clear_error_pulse <= 1'b0;
            last_cmd_error    <= 1'b0;
            last_cmd_seq      <= 16'd0;
        end else begin
            // These are one-cycle pulses. They automatically return to zero
            // unless the current command explicitly asserts them.
            force_status_send <= 1'b0;
            clear_error_pulse <= 1'b0;

            if (cmd_valid) begin
                last_cmd_seq <= cmd_seq;
                force_status_send <= 1'b1;

                case (cmd_code)
                    // 0x01: Write register. The address map is shared with the
                    // Linux protocol.hpp definitions and 数据包格式.txt.
                    8'h01: begin
                        case (cmd_addr)
                            16'h0000: begin
                                capture_enable    <= cmd_data0[0];
                                alarm_enable      <= cmd_data0[1];
                                debug_uart_enable <= cmd_data0[2];
                                last_cmd_error    <= 1'b0;
                            end
                            16'h0010: begin roi_x <= cmd_data0[10:0]; last_cmd_error <= 1'b0; end
                            16'h0011: begin roi_y <= cmd_data0[10:0]; last_cmd_error <= 1'b0; end
                            // Width/height and alarm threshold are clamped away
                            // from zero so downstream comparisons remain valid.
                            16'h0012: begin roi_w <= (cmd_data0[10:0] == 11'd0) ? 11'd1 : cmd_data0[10:0]; last_cmd_error <= 1'b0; end
                            16'h0013: begin roi_h <= (cmd_data0[10:0] == 11'd0) ? 11'd1 : cmd_data0[10:0]; last_cmd_error <= 1'b0; end
                            16'h0014: begin bright_threshold <= cmd_data0[7:0]; last_cmd_error <= 1'b0; end
                            16'h0015: begin tx_mode <= cmd_data0[1:0]; last_cmd_error <= 1'b0; end
                            16'h0016: begin alarm_count_threshold <= (cmd_data0[15:0] == 16'd0) ? 16'd1 : cmd_data0[15:0]; last_cmd_error <= 1'b0; end
                            default: begin last_cmd_error <= 1'b1; end
                        endcase
                    end
                    8'h02: begin
                        // Read command is acknowledged through status update in
                        // this demo design; no separate readback packet is sent.
                        last_cmd_error <= 1'b0;
                    end
                    8'h03: begin
                        // START_CAPTURE
                        capture_enable <= 1'b1;
                        last_cmd_error <= 1'b0;
                    end
                    8'h04: begin
                        // STOP_CAPTURE
                        capture_enable <= 1'b0;
                        last_cmd_error <= 1'b0;
                    end
                    8'h05: begin
                        last_cmd_error <= 1'b0;
                    end
                    8'h06: begin
                        // CLEAR_ERROR also clears camera-domain sticky flags via
                        // pulse_sync_toggle in the top-level module.
                        clear_error_pulse <= 1'b1;
                        last_cmd_error    <= 1'b0;
                    end
                    8'h07: begin
                        // BUZZER_ON enables the alarm path; it does not force an
                        // alarm unless bright_count crosses the threshold.
                        alarm_enable   <= 1'b1;
                        last_cmd_error <= 1'b0;
                    end
                    8'h08: begin
                        // BUZZER_OFF disables alarm output while statistics
                        // continue to be reported normally.
                        alarm_enable   <= 1'b0;
                        last_cmd_error <= 1'b0;
                    end
                    default: begin
                        last_cmd_error <= 1'b1;
                    end
                endcase
            end
        end
    end

endmodule
