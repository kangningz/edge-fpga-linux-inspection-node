`timescale 1ns / 1ps

module packet_stream_to_uart #(
    parameter integer CLK_HZ   = 50_000_000,
    parameter integer BAUDRATE = 115200
)(
    input  wire clk,
    input  wire rst_n,

    input  wire       s_valid,
    input  wire [7:0] s_data,
    input  wire       s_last,
    output wire       s_ready,

    output wire uart_txd,
    output wire uart_busy
);

    reg uart_start;
    wire uart_done;
    reg [7:0] uart_data_reg;

    assign s_ready = ~uart_busy;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            uart_start    <= 1'b0;
            uart_data_reg <= 8'd0;
        end else begin
            uart_start <= 1'b0;

            if (s_valid && s_ready) begin
                uart_data_reg <= s_data;
                uart_start    <= 1'b1;
            end
        end
    end

    uart_tx_byte #(
        .CLK_HZ(CLK_HZ),
        .BAUDRATE(BAUDRATE)
    ) u_uart_tx_byte (
        .clk(clk),
        .rst_n(rst_n),
        .start(uart_start),
        .tx_data(uart_data_reg),
        .txd(uart_txd),
        .busy(uart_busy),
        .done(uart_done)
    );

endmodule