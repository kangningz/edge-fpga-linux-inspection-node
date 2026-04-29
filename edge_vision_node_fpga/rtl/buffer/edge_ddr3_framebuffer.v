`timescale 1ns / 1ps
// DDR3 帧缓冲封装模块，把摄像头像素写入外部 DDR3 并为网络预览提供读接口。
// 该模块隐藏 MIG 初始化、地址递增和读写仲裁细节，顶层只关心帧开始、像素有效和读请求握手。

module edge_ddr3_framebuffer #(

    // 参数用于适配不同图像尺寸、时钟频率、缓冲深度或网络地址。
    parameter FRAME_WIDTH     = 800,

    // 参数用于适配不同图像尺寸、时钟频率、缓冲深度或网络地址。
    parameter FRAME_HEIGHT    = 600,

    // 参数用于适配不同图像尺寸、时钟频率、缓冲深度或网络地址。
    parameter FRAME_BASE_ADDR = 32'h0000_0000,

    // 参数用于适配不同图像尺寸、时钟频率、缓冲深度或网络地址。
    parameter FRAME_BYTES     = 32'd960000,

    // 参数用于适配不同图像尺寸、时钟频率、缓冲深度或网络地址。
    parameter BURST_BYTES     = 32'd512
)(
    input  wire       sys_rst_n,

    input  wire       camera_pclk,
    input  wire       frame_start,
    input  wire       frame_end,
    input  wire       line_start,
    input  wire       line_end,
    input  wire       pix_valid,
    input  wire [7:0] pix_data,

    input  wire       rd_clk,
    input  wire       rd_frame_restart,
    input  wire       rd_en,
    output wire [15:0] rd_pixel,
    output wire       rd_empty,
    output wire [8:0] rd_count,

    input  wire       ddr3_clk200m,
    input  wire       ddr3_rst_n,
    output wire       ddr3_init_done,
    output wire       ddr3_mmcm_locked,
    output wire       ddr3_calib_done,
    output wire       ddr3_wr_axi_seen,
    output wire       ddr3_rd_axi_seen,
    output reg        wr_frame_done_dbg,
    output reg        rd_frame_done_dbg,
    output wire       ui_clk,
    output wire       ui_rst,

    inout  wire [31:0] ddr3_dq,
    inout  wire [3:0]  ddr3_dqs_n,
    inout  wire [3:0]  ddr3_dqs_p,
    output wire [14:0] ddr3_addr,
    output wire [2:0]  ddr3_ba,
    output wire        ddr3_ras_n,
    output wire        ddr3_cas_n,
    output wire        ddr3_we_n,
    output wire        ddr3_reset_n,
    output wire [0:0]  ddr3_ck_p,
    output wire [0:0]  ddr3_ck_n,
    output wire [0:0]  ddr3_cke,
    output wire [0:0]  ddr3_cs_n,
    output wire [3:0]  ddr3_dm,
    output wire [0:0]  ddr3_odt,

    output wire       frame_start_16_dbg,
    output wire       frame_end_16_dbg,
    output wire       packer_error_dbg,
    output wire       wrfifo_full_dbg

// 端口列表到此结束，下面进入内部寄存器、组合连线和时序逻辑。
);

    // 本地常量定义状态编码、计数上限或协议字段，避免魔法数字散落在逻辑中。
    localparam integer FRAME_PIXELS = FRAME_WIDTH * FRAME_HEIGHT;

    // wire 信号承载组合逻辑结果或子模块之间的连接。
    wire pixel_valid_16;
    wire [15:0] pixel_data_16;
    wire frame_start_16;
    wire frame_end_16;
    wire line_start_16;
    wire line_end_16;
    wire packer_error;
    (* ASYNC_REG = "TRUE" *) reg cam_rst_ff0 = 1'b0;
    (* ASYNC_REG = "TRUE" *) reg cam_rst_ff1 = 1'b0;
    (* ASYNC_REG = "TRUE" *) reg rd_rst_ff0 = 1'b0;
    (* ASYNC_REG = "TRUE" *) reg rd_rst_ff1 = 1'b0;

    // reg 信号保存跨周期状态、计数器、握手标志和流水线寄存结果。
    reg [19:0] wr_pixel_cnt;
    reg [19:0] rd_pixel_cnt;

    reg wrfifo_clr;
    reg rdfifo_clr;
    reg wr_bank_cam;
    reg latest_completed_bank_cam;
    reg rd_bank_sel_rd;
    reg rd_busy_rd;

    (* ASYNC_REG = "TRUE" *) reg latest_completed_bank_rd_ff0 = 1'b0;
    (* ASYNC_REG = "TRUE" *) reg latest_completed_bank_rd_ff1 = 1'b0;
    (* ASYNC_REG = "TRUE" *) reg rd_busy_cam_ff0 = 1'b0;
    (* ASYNC_REG = "TRUE" *) reg rd_busy_cam_ff1 = 1'b0;
    (* ASYNC_REG = "TRUE" *) reg rd_bank_cam_ff0 = 1'b0;
    (* ASYNC_REG = "TRUE" *) reg rd_bank_cam_ff1 = 1'b0;
    (* ASYNC_REG = "TRUE" *) reg wr_bank_ui_ff0 = 1'b0;
    (* ASYNC_REG = "TRUE" *) reg wr_bank_ui_ff1 = 1'b0;
    reg wr_bank_ui;
    (* ASYNC_REG = "TRUE" *) reg rd_bank_ui_ff0 = 1'b0;
    (* ASYNC_REG = "TRUE" *) reg rd_bank_ui_ff1 = 1'b0;
    reg rd_bank_ui;

    wire cam_rst_n = cam_rst_ff1;
    wire rd_rst_n  = rd_rst_ff1;
    wire latest_completed_bank_rd = latest_completed_bank_rd_ff1;
    wire rd_busy_cam = rd_busy_cam_ff1;
    wire rd_bank_cam = rd_bank_cam_ff1;
    wire [31:0] wr_addr_begin = FRAME_BASE_ADDR + (wr_bank_ui ? FRAME_BYTES : 32'd0);
    wire [31:0] wr_addr_end   = wr_addr_begin + FRAME_BYTES - BURST_BYTES;
    wire [31:0] rd_addr_begin = FRAME_BASE_ADDR + (rd_bank_ui ? FRAME_BYTES : 32'd0);
    wire [31:0] rd_addr_end   = rd_addr_begin + FRAME_BYTES - BURST_BYTES;

    // 时序逻辑：在指定时钟沿更新状态，并在复位时恢复到安全初值。
    always @(posedge camera_pclk) begin
        cam_rst_ff0 <= sys_rst_n;
        cam_rst_ff1 <= cam_rst_ff0;
    end

    // 时序逻辑：在指定时钟沿更新状态，并在复位时恢复到安全初值。
    always @(posedge rd_clk) begin
        rd_rst_ff0 <= sys_rst_n;
        rd_rst_ff1 <= rd_rst_ff0;
    end

    // 时序逻辑：在指定时钟沿更新状态，并在复位时恢复到安全初值。
    always @(posedge rd_clk) begin
        latest_completed_bank_rd_ff0 <= latest_completed_bank_cam;
        latest_completed_bank_rd_ff1 <= latest_completed_bank_rd_ff0;
    end

    // 时序逻辑：在指定时钟沿更新状态，并在复位时恢复到安全初值。
    always @(posedge camera_pclk) begin
        rd_busy_cam_ff0 <= rd_busy_rd;
        rd_busy_cam_ff1 <= rd_busy_cam_ff0;
        rd_bank_cam_ff0 <= rd_bank_sel_rd;
        rd_bank_cam_ff1 <= rd_bank_cam_ff0;
    end

    // 时序逻辑：在指定时钟沿更新状态，并在复位时恢复到安全初值。
    always @(posedge ui_clk or posedge ui_rst) begin
        if (ui_rst) begin
            wr_bank_ui_ff0 <= 1'b0;
            wr_bank_ui_ff1 <= 1'b0;
            wr_bank_ui     <= 1'b0;
            rd_bank_ui_ff0 <= 1'b0;
            rd_bank_ui_ff1 <= 1'b0;
            rd_bank_ui     <= 1'b0;
        end else begin
            wr_bank_ui_ff0 <= wr_bank_cam;
            wr_bank_ui_ff1 <= wr_bank_ui_ff0;
            wr_bank_ui     <= wr_bank_ui_ff1;
            rd_bank_ui_ff0 <= rd_bank_sel_rd;
            rd_bank_ui_ff1 <= rd_bank_ui_ff0;
            rd_bank_ui     <= rd_bank_ui_ff1;
        end
    end

    ov2640_rgb565_packer u_ov2640_rgb565_packer (
        .rst_n           (cam_rst_n),
        .camera_pclk     (camera_pclk),
        .frame_start     (frame_start),
        .frame_end       (frame_end),
        .line_start      (line_start),
        .line_end        (line_end),
        .pix_valid       (pix_valid),
        .pix_data        (pix_data),
        .pixel_valid     (pixel_valid_16),
        .pixel_data      (pixel_data_16),
        .frame_start_16  (frame_start_16),
        .frame_end_16    (frame_end_16),
        .line_start_16   (line_start_16),
        .line_end_16     (line_end_16),
        .byte_phase_error(packer_error)
    );

    // 时序逻辑：在指定时钟沿更新状态，并在复位时恢复到安全初值。
    always @(posedge camera_pclk) begin
        if (!cam_rst_n) begin
            wrfifo_clr <= 1'b1;
        end else begin
            wrfifo_clr <= frame_start_16;
        end
    end

    // 时序逻辑：在指定时钟沿更新状态，并在复位时恢复到安全初值。
    always @(posedge camera_pclk) begin
        if (!cam_rst_n) begin
            wr_pixel_cnt      <= 20'd0;
            wr_frame_done_dbg <= 1'b0;
            wr_bank_cam       <= 1'b0;
            latest_completed_bank_cam <= 1'b0;
        end else begin
            wr_frame_done_dbg <= 1'b0;
            if (frame_start_16) begin
                wr_pixel_cnt <= 20'd0;
            end else if (pixel_valid_16) begin
                if (wr_pixel_cnt < FRAME_PIXELS) begin
                    wr_pixel_cnt <= wr_pixel_cnt + 1'b1;
                end
            end

            if (frame_end_16 &&
                ((wr_pixel_cnt >= FRAME_PIXELS) ||
                 (pixel_valid_16 && (wr_pixel_cnt >= FRAME_PIXELS - 1)))) begin
                wr_frame_done_dbg <= 1'b1;
                latest_completed_bank_cam <= wr_bank_cam;
                if (rd_busy_cam && ((~wr_bank_cam) == rd_bank_cam)) begin
                    wr_bank_cam <= wr_bank_cam;
                end else begin
                    wr_bank_cam <= ~wr_bank_cam;
                end
            end
        end
    end

    // 时序逻辑：在指定时钟沿更新状态，并在复位时恢复到安全初值。
    always @(posedge rd_clk) begin
        if (!rd_rst_n) begin
            rdfifo_clr <= 1'b1;
        end else if (rd_frame_restart) begin
            rdfifo_clr <= 1'b1;
        end else begin
            rdfifo_clr <= 1'b0;
        end
    end

    // 时序逻辑：在指定时钟沿更新状态，并在复位时恢复到安全初值。
    always @(posedge rd_clk) begin
        if (!rd_rst_n) begin
            rd_pixel_cnt      <= 20'd0;
            rd_frame_done_dbg <= 1'b0;
            rd_bank_sel_rd    <= 1'b0;
            rd_busy_rd        <= 1'b0;
        end else begin
            rd_frame_done_dbg <= 1'b0;
            if (rdfifo_clr) begin
                rd_pixel_cnt      <= 20'd0;
                rd_bank_sel_rd    <= latest_completed_bank_rd;
                rd_busy_rd        <= 1'b1;
            end else if (rd_en && !rd_empty) begin
                if (rd_pixel_cnt < FRAME_PIXELS) begin
                    rd_pixel_cnt <= rd_pixel_cnt + 1'b1;
                end
                if (rd_pixel_cnt >= FRAME_PIXELS - 1) begin
                    rd_frame_done_dbg <= 1'b1;
                    rd_busy_rd        <= 1'b0;
                end
            end
        end
    end

    edge_ddr3_ctrl_2port u_edge_ddr3_ctrl_2port (
        .ddr3_clk200m (ddr3_clk200m),
        .ddr3_rst_n   (ddr3_rst_n),
        .ddr3_init_done(ddr3_init_done),
        .ddr3_mmcm_locked(ddr3_mmcm_locked),
        .ddr3_calib_done(ddr3_calib_done),
        .ddr3_wr_axi_seen(ddr3_wr_axi_seen),
        .ddr3_rd_axi_seen(ddr3_rd_axi_seen),
        .wrfifo_clr   (wrfifo_clr),
        .wrfifo_clk   (camera_pclk),
        .wrfifo_wren  (pixel_valid_16),
        .wrfifo_din   (pixel_data_16),
        .wrfifo_full  (wrfifo_full_dbg),
        .wrfifo_wr_cnt(),
        .wr_ddr_addr_begin(wr_addr_begin),
        .wr_ddr_addr_end(wr_addr_end),
        .rdfifo_clr   (rdfifo_clr),
        .rdfifo_clk   (rd_clk),
        .rdfifo_rden  (rd_en),
        .rdfifo_dout  (rd_pixel),
        .rdfifo_empty (rd_empty),
        .rdfifo_rd_cnt(rd_count),
        .rd_ddr_addr_begin(rd_addr_begin),
        .rd_ddr_addr_end(rd_addr_end),
        .ui_clk       (ui_clk),
        .ui_rst       (ui_rst),
        .ddr3_dq      (ddr3_dq),
        .ddr3_dqs_n   (ddr3_dqs_n),
        .ddr3_dqs_p   (ddr3_dqs_p),
        .ddr3_addr    (ddr3_addr),
        .ddr3_ba      (ddr3_ba),
        .ddr3_ras_n   (ddr3_ras_n),
        .ddr3_cas_n   (ddr3_cas_n),
        .ddr3_we_n    (ddr3_we_n),
        .ddr3_reset_n (ddr3_reset_n),
        .ddr3_ck_p    (ddr3_ck_p),
        .ddr3_ck_n    (ddr3_ck_n),
        .ddr3_cke     (ddr3_cke),
        .ddr3_cs_n    (ddr3_cs_n),
        .ddr3_dm      (ddr3_dm),
        .ddr3_odt     (ddr3_odt)
    );

    // 连续赋值用于输出固定映射、组合判断或协议字段拼接。
    assign frame_start_16_dbg = frame_start_16;

    // 连续赋值用于输出固定映射、组合判断或协议字段拼接。
    assign frame_end_16_dbg   = frame_end_16;
    assign packer_error_dbg   = packer_error;

endmodule
