`timescale 1ns / 1ps
// 包数据到 UART 调试输出模块。
// 把字节流按串口发送，便于不用网络链路时观察内部数据。

module packet_stream_to_uart #(

    // 参数用于适配不同图像尺寸、时钟频率、缓冲深度或网络地址。
    parameter integer CLK_HZ   = 50_000_000,

    // 参数用于适配不同图像尺寸、时钟频率、缓冲深度或网络地址。
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

// 端口列表到此结束，下面进入内部寄存器、组合连线和时序逻辑。
);

    // reg 信号保存跨周期状态、计数器、握手标志和流水线寄存结果。
    reg uart_start;

    // wire 信号承载组合逻辑结果或子模块之间的连接。
    wire uart_done;
    reg [7:0] uart_data_reg;

    // 连续赋值用于输出固定映射、组合判断或协议字段拼接。
    assign s_ready = ~uart_busy;

    // 时序逻辑：在指定时钟沿更新状态，并在复位时恢复到安全初值。
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
