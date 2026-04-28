`timescale 1ns / 1ps

module vision_udp_status_ctrl (
    input  wire clk,
    input  wire rst_n,

    input  wire pkt_valid,
    input  wire payload_busy,
    input  wire tx_done,

    output reg  send_start
);

    reg sending;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            sending    <= 1'b0;
            send_start <= 1'b0;
        end else begin
            send_start <= 1'b0;

            if (!sending) begin
                if (pkt_valid && !payload_busy) begin
                    send_start <= 1'b1;
                    sending    <= 1'b1;
                end
            end else begin
                if (tx_done) begin
                    sending <= 1'b0;
                end
            end
        end
    end

endmodule