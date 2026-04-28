`timescale 1ns / 1ps

// Decode the 20-byte Linux -> FPGA command payload.
//
// The Ethernet/UDP RX block already filters MAC/IP/UDP. This parser only checks
// the application payload magic/version/checksum and emits one-cycle cmd_valid_o
// pulses for valid commands.

module udp_cmd_packet_parser (
    input  wire        clk,
    input  wire        rst_n,

    input  wire        payload_valid_i,
    input  wire [7:0]  payload_dat_i,
    input  wire [15:0] rx_data_length_i,
    input  wire        one_pkt_done_i,
    input  wire        pkt_error_i,

    output reg         cmd_valid_o,
    output reg  [7:0]  cmd_code_o,
    output reg  [15:0] cmd_seq_o,
    output reg  [15:0] cmd_addr_o,
    output reg  [31:0] cmd_data0_o,
    output reg  [31:0] cmd_data1_o
);

    reg [7:0] byte_buf [0:19];
    reg [4:0] byte_cnt;
    integer i;
    reg [7:0] checksum_calc;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            byte_cnt    <= 5'd0;
            cmd_valid_o <= 1'b0;
            cmd_code_o  <= 8'd0;
            cmd_seq_o   <= 16'd0;
            cmd_addr_o  <= 16'd0;
            cmd_data0_o <= 32'd0;
            cmd_data1_o <= 32'd0;
        end else begin
            cmd_valid_o <= 1'b0;

            // Store at most one fixed-size command. Longer payloads will fail
            // length validation at packet end.
            if (payload_valid_i && byte_cnt < 5'd20) begin
                byte_buf[byte_cnt] <= payload_dat_i;
                byte_cnt <= byte_cnt + 1'b1;
            end

            if (one_pkt_done_i) begin
                // XOR checksum is intentionally simple so it maps to small RTL
                // and matches protocol::build_command_packet on Linux.
                checksum_calc = 8'h00;
                for (i = 0; i < 19; i = i + 1) begin
                    checksum_calc = checksum_calc ^ byte_buf[i];
                end

                if (!pkt_error_i &&
                    rx_data_length_i == 16'd20 &&
                    byte_buf[0] == 8'h43 &&
                    byte_buf[1] == 8'h4D &&
                    byte_buf[2] == 8'h01 &&
                    checksum_calc == byte_buf[19]) begin
                    // Multi-byte fields are big-endian/network order.
                    cmd_valid_o <= 1'b1;
                    cmd_code_o  <= byte_buf[3];
                    cmd_seq_o   <= {byte_buf[4], byte_buf[5]};
                    cmd_addr_o  <= {byte_buf[6], byte_buf[7]};
                    cmd_data0_o <= {byte_buf[8], byte_buf[9], byte_buf[10], byte_buf[11]};
                    cmd_data1_o <= {byte_buf[12], byte_buf[13], byte_buf[14], byte_buf[15]};
                end

                byte_cnt <= 5'd0;
            end
        end
    end

endmodule
