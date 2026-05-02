`timescale 1ns / 1ps
// DDR3 帧缓冲封装模块。
//
// 功能边界：
//   1. camera_pclk 域接收 OV2640 8bit 字节流，内部打包成 16bit RGB565。
//   2. 通过写 FIFO -> MIG/AXI 写入外部 DDR3。
//   3. rd_clk 域按预览分片模块的 rd_en 请求，从 DDR3 读回 16bit RGB565 像素。
//   4. 使用两个 DDR3 bank 做帧级双缓冲：摄像头写一个 bank，网络读最近完成的另一个 bank。
//
// 本模块只处理“整帧缓存”的策略，真正 AXI/MIG 时序在 edge_ddr3_ctrl_2port 内。

module edge_ddr3_framebuffer #(

    // 图像宽高必须与摄像头初始化表和网络预览协议一致。
    parameter FRAME_WIDTH     = 800,
    parameter FRAME_HEIGHT    = 600,

    // 双缓冲第一块帧缓存基地址；第二块从 FRAME_BASE_ADDR + FRAME_BYTES 开始。
    parameter FRAME_BASE_ADDR = 32'h0000_0000,

    // 单帧字节数，RGB565 为 width * height * 2。
    parameter FRAME_BYTES     = 32'd960000,

    // DDR3 控制器每次突发传输的地址跨度，需与底层 FIFO/MIG 搬运粒度匹配。
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

    // 一帧像素数量。计数用它判断“写完一帧/读完一帧”。
    localparam integer FRAME_PIXELS = FRAME_WIDTH * FRAME_HEIGHT;

    // 8bit 摄像头字节流经 packer 后变为 16bit RGB565 像素流。
    wire pixel_valid_16;
    wire [15:0] pixel_data_16;
    wire frame_start_16;
    wire frame_end_16;
    wire line_start_16;
    wire line_end_16;
    wire packer_error;

    // sys_rst_n 是外部系统复位，这里分别同步到 camera_pclk 和 rd_clk 域。
    (* ASYNC_REG = "TRUE" *) reg cam_rst_ff0 = 1'b0;
    (* ASYNC_REG = "TRUE" *) reg cam_rst_ff1 = 1'b0;
    (* ASYNC_REG = "TRUE" *) reg rd_rst_ff0 = 1'b0;
    (* ASYNC_REG = "TRUE" *) reg rd_rst_ff1 = 1'b0;

    // 写/读像素计数用于在帧尾确认已经搬够一整帧。
    reg [19:0] wr_pixel_cnt;
    reg [19:0] rd_pixel_cnt;

    // wrfifo_clr/rdfifo_clr 用来在新帧开始或读帧重启时清空异步 FIFO，避免上一帧残留字节混入。
    reg wrfifo_clr;
    reg rdfifo_clr;

    // bank 选择：
    //   wr_bank_cam               : 摄像头下一帧写入的 bank
    //   latest_completed_bank_cam  : 最近完整写好的 bank
    //   rd_bank_sel_rd            : 当前网络读侧选择的 bank
    //   rd_busy_rd                : 网络读侧正在读取一帧，写侧据此避免覆盖正在读的 bank
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

    // 复位同步到摄像头写侧。
    always @(posedge camera_pclk) begin
        cam_rst_ff0 <= sys_rst_n;
        cam_rst_ff1 <= cam_rst_ff0;
    end

    // 复位同步到网络读侧。
    always @(posedge rd_clk) begin
        rd_rst_ff0 <= sys_rst_n;
        rd_rst_ff1 <= rd_rst_ff0;
    end

    // 最近完成写入的 bank 从摄像头域同步到网络读域，新一轮预览读取会锁存这个 bank。
    always @(posedge rd_clk) begin
        latest_completed_bank_rd_ff0 <= latest_completed_bank_cam;
        latest_completed_bank_rd_ff1 <= latest_completed_bank_rd_ff0;
    end

    // 网络读忙状态和当前读 bank 同步回摄像头域，用来避免写侧切换到正在被读的 bank。
    always @(posedge camera_pclk) begin
        rd_busy_cam_ff0 <= rd_busy_rd;
        rd_busy_cam_ff1 <= rd_busy_cam_ff0;
        rd_bank_cam_ff0 <= rd_bank_sel_rd;
        rd_bank_cam_ff1 <= rd_bank_cam_ff0;
    end

    // bank 选择同步到 MIG ui_clk 域，底层 DDR 控制器在 ui_clk 域使用这些地址。
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

    // 把 OV2640 8bit 字节流组装为 16bit RGB565 像素。
    // byte_phase_error 表示帧/行边界打断了两个字节的配对，可用于定位摄像头时序或初始化问题。
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

    // 新帧开始时清写 FIFO，确保 DDR3 中每帧从帧首地址开始写入，且不会带入上一帧尾部残留。
    always @(posedge camera_pclk) begin
        if (!cam_rst_n) begin
            wrfifo_clr <= 1'b1;
        end else begin
            wrfifo_clr <= frame_start_16;
        end
    end

    // 写侧帧完成判断和双缓冲切换。
    // frame_end_16 到来且像素数达到一帧时，标记当前 bank 为 latest_completed。
    // 如果另一个 bank 正在被网络读侧使用，则暂停切 bank，避免覆盖正在发送的帧。
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

    // 读侧每次收到 rd_frame_restart 都清读 FIFO，并准备从最近完成的 bank 重新读一整帧。
    always @(posedge rd_clk) begin
        if (!rd_rst_n) begin
            rdfifo_clr <= 1'b1;
        end else if (rd_frame_restart) begin
            rdfifo_clr <= 1'b1;
        end else begin
            rdfifo_clr <= 1'b0;
        end
    end

    // 读侧像素计数。预览分片模块每成功消费一个 rd_pixel，就通过 rd_en 推进一个像素。
    // 读满 FRAME_PIXELS 后产生 rd_frame_done_dbg。
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

    // 两端口 DDR3 控制器封装：
    //   写端口：camera_pclk + wrfifo_*，地址使用 wr_addr_begin/end。
    //   读端口：rd_clk + rdfifo_*，地址使用 rd_addr_begin/end。
    // 底层会将 FIFO 数据搬运到 MIG AXI 总线。
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

    // 调试信号透传给顶层 LED/遥测。
    assign frame_start_16_dbg = frame_start_16;
    assign frame_end_16_dbg   = frame_end_16;
    assign packer_error_dbg   = packer_error;

endmodule
