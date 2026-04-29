`timescale 1ns / 1ps
// 帧统计跨时钟 FIFO。
// 摄像头像素域写入统计记录，网络发送域读取并打包成 UDP 遥测。

module stats_async_fifo #(

    // 参数用于适配不同图像尺寸、时钟频率、缓冲深度或网络地址。
    parameter integer DATA_WIDTH = 160,

    // 参数用于适配不同图像尺寸、时钟频率、缓冲深度或网络地址。
    parameter integer FIFO_DEPTH = 16
)(
    input  wire                   rst_n,

    input  wire                   wr_clk,
    input  wire                   wr_en,
    input  wire [DATA_WIDTH-1:0]  din,
    output wire                   full,

    input  wire                   rd_clk,
    input  wire                   rd_en,
    output wire [DATA_WIDTH-1:0]  dout,
    output wire                   empty

// 端口列表到此结束，下面进入内部寄存器、组合连线和时序逻辑。
);

    // wire 信号承载组合逻辑结果或子模块之间的连接。
    wire rst = ~rst_n;

    xpm_fifo_async #(
        .CASCADE_HEIGHT      (0),
        .CDC_SYNC_STAGES     (2),
        .DOUT_RESET_VALUE    ("0"),
        .ECC_MODE            ("no_ecc"),
        .FIFO_MEMORY_TYPE    ("auto"),
        .FIFO_READ_LATENCY   (0),
        .FIFO_WRITE_DEPTH    (FIFO_DEPTH),
        .FULL_RESET_VALUE    (0),
        .PROG_EMPTY_THRESH   (10),
        .PROG_FULL_THRESH    (10),
        .RD_DATA_COUNT_WIDTH (5),
        .READ_DATA_WIDTH     (DATA_WIDTH),
        .READ_MODE           ("fwft"),
        .RELATED_CLOCKS      (0),
        .SIM_ASSERT_CHK      (0),
        .USE_ADV_FEATURES    ("0707"),
        .WAKEUP_TIME         (0),
        .WRITE_DATA_WIDTH    (DATA_WIDTH),
        .WR_DATA_COUNT_WIDTH (5)
    ) u_xpm_fifo_async (
        .sleep         (1'b0),
        .rst           (rst),

        .wr_clk        (wr_clk),
        .wr_en         (wr_en),
        .din           (din),
        .full          (full),
        .prog_full     (),
        .wr_data_count (),
        .overflow      (),
        .wr_ack        (),
        .wr_rst_busy   (),

        .rd_clk        (rd_clk),
        .rd_en         (rd_en),
        .dout          (dout),
        .empty         (empty),
        .prog_empty    (),
        .rd_data_count (),
        .underflow     (),
        .data_valid    (),
        .rd_rst_busy   (),

        .almost_empty  (),
        .almost_full   (),
        .dbiterr       (),
        .sbiterr       (),
        .injectdbiterr (1'b0),
        .injectsbiterr (1'b0)
    );

endmodule
