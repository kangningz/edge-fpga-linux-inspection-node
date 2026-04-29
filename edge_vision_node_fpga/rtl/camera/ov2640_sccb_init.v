`timescale 1ns / 1ps
// OV2640 SCCB 初始化控制器。
// 复位释放后按初始化表逐项调用 SCCB 写主机，完成后给出 cam_init_done。

module ov2640_sccb_init #(

    // 参数用于适配不同图像尺寸、时钟频率、缓冲深度或网络地址。
    parameter integer CLK_HZ = 50_000_000,

    // 参数用于适配不同图像尺寸、时钟频率、缓冲深度或网络地址。
    parameter [7:0] OV2640_DEV_ADDR_W = 8'h60,

    // 参数用于适配不同图像尺寸、时钟频率、缓冲深度或网络地址。
    parameter        JPEG_MODE = 1'b0
)(
    input  wire clk,
    input  wire rst_n,
    input  wire start,

    inout  wire camera_scl,
    inout  wire camera_sda,

    output reg  init_busy,
    output reg  init_done,
    output reg  init_error

// 端口列表到此结束，下面进入内部寄存器、组合连线和时序逻辑。
);

    // 本地常量定义状态编码、计数上限或协议字段，避免魔法数字散落在逻辑中。
    localparam [2:0]
        S_IDLE      = 3'd0,
        S_LOAD      = 3'd1,
        S_WRITE     = 3'd2,
        S_WAIT_WR   = 3'd3,
        S_DELAY     = 3'd4,
        S_NEXT      = 3'd5,
        S_DONE      = 3'd6;

    // reg 信号保存跨周期状态、计数器、握手标志和流水线寄存结果。
    reg [2:0] state;
    reg [7:0] table_idx;

    // wire 信号承载组合逻辑结果或子模块之间的连接。
    wire [7:0] tbl_reg_addr;
    wire [7:0] tbl_reg_data;
    wire       tbl_is_delay;
    wire [23:0] tbl_delay_ms;
    wire       tbl_end;

    ov2640_init_table_svga_rgb565 u_table (
        .index(table_idx),
        .reg_addr(tbl_reg_addr),
        .reg_data(tbl_reg_data),
        .is_delay(tbl_is_delay),
        .delay_ms(tbl_delay_ms),
        .table_end(tbl_end)
    );

    reg wr_start;
    wire wr_busy;
    wire wr_done;
    wire wr_ack_error;

    sccb_master_write #(
        .CLK_HZ(CLK_HZ),
        .SCCB_FREQ_HZ(100_000)
    ) u_sccb_wr (
        .clk(clk),
        .rst_n(rst_n),
        .start(wr_start),
        .dev_addr_w(OV2640_DEV_ADDR_W),
        .reg_addr(tbl_reg_addr),
        .reg_data(tbl_reg_data),
        .sccb_scl(camera_scl),
        .sccb_sda(camera_sda),
        .busy(wr_busy),
        .done(wr_done),
        .ack_error(wr_ack_error)
    );

    reg [31:0] delay_cnt;
    wire [31:0] delay_target = (CLK_HZ / 1000) * tbl_delay_ms;

    // 时序逻辑：在指定时钟沿更新状态，并在复位时恢复到安全初值。
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state      <= S_IDLE;
            table_idx  <= 8'd0;
            wr_start   <= 1'b0;
            delay_cnt  <= 32'd0;
            init_busy  <= 1'b0;
            init_done  <= 1'b0;
            init_error <= 1'b0;
        end else begin
            wr_start  <= 1'b0;
            init_done <= 1'b0;

            // 状态机分支：按当前阶段执行握手、计数或数据搬运动作。
            case (state)
                S_IDLE: begin
                    table_idx  <= 8'd0;
                    delay_cnt  <= 32'd0;
                    init_busy  <= 1'b0;
                    init_error <= 1'b0;
                    if (start) begin
                        init_busy <= 1'b1;
                        state     <= S_LOAD;
                    end
                end

                S_LOAD: begin
                    if (tbl_end) begin
                        state <= S_DONE;
                    end else if (tbl_is_delay) begin
                        delay_cnt <= 32'd0;
                        state     <= S_DELAY;
                    end else begin
                        state <= S_WRITE;
                    end
                end

                S_WRITE: begin
                    wr_start <= 1'b1;
                    state    <= S_WAIT_WR;
                end

                S_WAIT_WR: begin
                    if (wr_done) begin
                        if (wr_ack_error)
                            init_error <= 1'b1;
                        state <= S_NEXT;
                    end
                end

                S_DELAY: begin
                    if (delay_cnt >= delay_target - 1) begin
                        state <= S_NEXT;
                    end else begin
                        delay_cnt <= delay_cnt + 1'b1;
                    end
                end

                S_NEXT: begin
                    table_idx <= table_idx + 1'b1;
                    state     <= S_LOAD;
                end

                S_DONE: begin
                    init_busy <= 1'b0;
                    init_done <= 1'b1;
                    state     <= S_IDLE;
                end

                default: begin
                    state      <= S_IDLE;
                    table_idx  <= 8'd0;
                    wr_start   <= 1'b0;
                    delay_cnt  <= 32'd0;
                    init_busy  <= 1'b0;
                    init_done  <= 1'b0;
                    init_error <= 1'b0;
                end

            // 状态机分支结束，未命中的情况由默认分支回到安全状态。
            endcase
        end
    end

endmodule
