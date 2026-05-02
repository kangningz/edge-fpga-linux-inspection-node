`timescale 1ns / 1ps
// 边缘视觉节点完整顶层。
//
// 主数据通路：
//   OV2640 DVP(8bit) -> RGB565 打包 -> DDR3 双缓冲 -> DDR3 读回 -> UDP RGB565 预览分片
//
// 辅助通路：
//   1. 摄像头像素流同步送入 ROI/亮点统计，帧尾生成遥测统计包。
//   2. 以太网 RX 接收 Linux 侧 UDP 命令，写入寄存器组后动态修改 ROI、阈值、告警等参数。
//   3. 预览包和遥测包共用一个 UDP TX，因此顶层做一个简单发送源仲裁。
//
// 本文件是工程阅读入口，重点看清 3 个时钟域：
//   sys_clk      : 50 MHz 系统/摄像头初始化/LED 状态
//   camera_pclk  : OV2640 像素时钟域，所有采集和图像统计在这里发生
//   eth_clk125m  : 千兆以太网 TX/命令寄存器/遥测与预览发送域
// 另外 DDR3 MIG 内部会产生 ui_clk，帧缓冲模块内部负责和 MIG/AXI 对接。

module top_ov2640_ddr3_udp_preview (
    input  wire FPGA_CLK,       // 板载 50 MHz 输入时钟，供系统、DDR3、以太网 PLL/MMCM 使用。
    input  wire S0,             // 外部手动复位，低有效语义由板级按键/开关决定，这里直接作为 rst_n 使用。

    input  wire [7:0] camera_d,     // OV2640 DVP 8bit 数据总线，RGB565 时每个像素分两个字节送出。
    input  wire       camera_pclk,  // OV2640 像素时钟，采集接口在该时钟上锁存 camera_d/href/vsync。
    input  wire       camera_href,  // 行有效，高电平期间 camera_d 输出当前行字节流。
    input  wire       camera_vsync, // 帧同步信号，不同寄存器配置下有效沿可能不同，采集模块会自适应边沿。

    output wire       camera_xclk,  // 输出给 OV2640 的主时钟，本工程配置为 25 MHz。
    inout  wire       camera_scl,   // SCCB/I2C 类配置总线时钟。
    inout  wire       camera_sda,   // SCCB/I2C 类配置总线数据。

    // DDR3 物理接口，直接连接 MIG IP 的外部存储器端口。
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

    output wire        eth_reset_n,    // 输出给 PHY 的复位释放信号。
    output wire        rgmii_tx_clk,   // RGMII 发送时钟，由 GMII->RGMII 模块输出。
    output wire [3:0]  rgmii_txd,      // RGMII 发送半字节数据。
    output wire        rgmii_txen,     // RGMII 发送有效。
    input  wire        rgmii_rx_clk_i, // PHY 送回的 RGMII 接收时钟。
    input  wire [3:0]  rgmii_rxd,      // RGMII 接收半字节数据。
    input  wire        rgmii_rxdv,     // RGMII 接收有效。

    // 板载状态输出。具体含义见文件末尾 LED 赋值处。
    output reg         LED0,
    output reg         LED1,
    output reg         LED2,
    output reg         LED3,
    output reg         LED4,
    output reg         LED5,
    output reg         LED6,
    output reg         LED7,
    output wire        BEEP

// 端口列表到此结束，下面进入内部寄存器、组合连线和时序逻辑。
);

    // 图像尺寸和帧大小必须与 OV2640 初始化表、Linux/Web 预览端保持一致。
    // RGB565 每像素 2 字节，所以单帧字节数为 800 * 600 * 2 = 960000。
    localparam integer FRAME_WIDTH      = 800;
    localparam integer FRAME_HEIGHT     = 600;
    localparam integer FRAME_BYTES      = FRAME_WIDTH * FRAME_HEIGHT * 2;

    // 上电后延迟一段时间再发 SCCB 初始化，给摄像头电源、XCLK 和内部复位留稳定时间。
    localparam integer INIT_WAIT_CYCLES = 1_000_000;

    // 蜂鸣器保持和音调参数。计数发生在 camera_pclk 域，当前值约为一次告警后保持数百毫秒。
    localparam [24:0] BEEP_HOLD_CYCLES = 25'd12500000;
    localparam [12:0] BEEP_TONE_HALF_CYCLES = 13'd6250;
    localparam        BEEP_ACTIVE_LEVEL = 1'b1;

    // ----------------------------
    // 时钟和全局复位
    // ----------------------------
    // manual_rst_n 是顶层外部复位释放信号。不同子系统还会叠加各自 PLL/MMCM locked 信号，
    // 防止时钟未稳定时提前运行状态机。
    wire manual_rst_n = S0;
    wire sys_clk;
    wire rst_n_sys;
    wire cam_xclk_int;

    // 生成 50 MHz 系统时钟、25 MHz 摄像头 XCLK，以及同步到 sys_clk 的系统复位。
    clk_rst_mgr #(
        .SYS_CLK_HZ  (50_000_000),
        .CAM_XCLK_HZ (25_000_000)
    ) u_clk_rst_mgr (
        .fpga_clk_in (FPGA_CLK),
        .ext_rst_n   (manual_rst_n),
        .sys_clk     (sys_clk),
        .cam_xclk    (cam_xclk_int),
        .rst_n_sys   (rst_n_sys)
    );

    // 摄像头外部时钟直接从时钟复位管理模块输出到管脚。
    assign camera_xclk = cam_xclk_int;

    wire ddr3_clk200m;
    wire ddr3_clk_locked;

    // DDR3 MIG 需要 200 MHz 参考/系统时钟，locked 只说明该外部 clock wizard 已锁定；
    // 真正 DDR3 可用还要等 MIG calibration done，在帧缓冲模块里输出 ddr3_init_done。
    clk_wiz_ddr3_200m u_clk_wiz_ddr3_200m (
        .clk_in1 (FPGA_CLK),
        .reset   (~manual_rst_n),
        .clk_out1(ddr3_clk200m),
        .locked  (ddr3_clk_locked)
    );

    wire eth_clk125m;
    wire eth_clk_locked;

    // 千兆以太网发送链路工作在 125 MHz。命令寄存器、遥测包和预览包发送也统一放在该域。
    clk_wiz_eth125m u_clk_wiz_eth125m (
        .clk_in1 (FPGA_CLK),
        .reset   (~manual_rst_n),
        .clk_out1(eth_clk125m),
        .locked  (eth_clk_locked)
    );

    // ----------------------------
    // OV2640 SCCB 初始化
    // ----------------------------
    // init_start_pulse 只打一拍，启动初始化表写入。done/error 做 sticky 保存，
    // 后续通过 LED 和遥测状态位观察，即使原始 done/error 只有一拍也不会丢。
    reg [19:0] init_wait_cnt;
    reg init_start_pulse;
    reg init_started;
    reg init_done_sticky_sys;
    reg init_error_sticky_sys;
    wire cam_init_busy;
    wire cam_init_done;
    wire cam_init_error;

    // 上电后等待 INIT_WAIT_CYCLES 个 sys_clk 周期，再启动 SCCB 配置。
    // 这里不反复重试；如果初始化失败，init_error_sticky_sys 会保持为 1，等待外部复位。
    always @(posedge sys_clk or negedge rst_n_sys) begin
        if (!rst_n_sys) begin
            init_wait_cnt         <= 20'd0;
            init_start_pulse      <= 1'b0;
            init_started          <= 1'b0;
            init_done_sticky_sys  <= 1'b0;
            init_error_sticky_sys <= 1'b0;
        end else begin
            init_start_pulse <= 1'b0;
            if (!init_started) begin
                if (init_wait_cnt == INIT_WAIT_CYCLES - 1) begin
                    init_start_pulse <= 1'b1;
                    init_started     <= 1'b1;
                end else begin
                    init_wait_cnt <= init_wait_cnt + 1'b1;
                end
            end

            if (cam_init_done) begin
                init_done_sticky_sys <= 1'b1;
            end
            if (cam_init_error) begin
                init_error_sticky_sys <= 1'b1;
            end
        end
    end

    // 通过 SCCB 写 OV2640 寄存器表。本工程 JPEG_MODE=0，配置为 SVGA RGB565 输出。
    ov2640_sccb_init #(
        .CLK_HZ            (50_000_000),
        .OV2640_DEV_ADDR_W (8'h60),
        .JPEG_MODE         (1'b0)
    ) u_ov2640_sccb_init (
        .clk        (sys_clk),
        .rst_n      (rst_n_sys),
        .start      (init_start_pulse),
        .camera_scl (camera_scl),
        .camera_sda (camera_sda),
        .init_busy  (cam_init_busy),
        .init_done  (cam_init_done),
        .init_error (cam_init_error)
    );

    // ----------------------------
    // 摄像头 DVP 采集和基础帧同步统计
    // ----------------------------
    // cap_* 信号全部属于 camera_pclk 域。pix_data 仍是 8bit 字节流，后面 DDR3 帧缓冲会再打包成 16bit RGB565。
    wire        cap_frame_start;
    wire        cap_frame_end;
    wire        cap_line_start;
    wire        cap_line_end;
    wire        cap_pix_valid;
    wire [7:0]  cap_pix_data;
    wire [10:0] cap_x_cnt;
    wire [10:0] cap_y_cnt;

    // 把 OV2640 的 VSYNC/HREF/PCLK/D[7:0] 转换成更容易消费的帧开始、帧结束、行开始、行结束和字节有效脉冲。
    ov2640_capture_if u_ov2640_capture_if (
        .rst_n        (rst_n_sys),
        .camera_pclk  (camera_pclk),
        .camera_vsync (camera_vsync),
        .camera_href  (camera_href),
        .camera_d     (camera_d),
        .frame_start  (cap_frame_start),
        .frame_end    (cap_frame_end),
        .line_start   (cap_line_start),
        .line_end     (cap_line_end),
        .pix_valid    (cap_pix_valid),
        .pix_data     (cap_pix_data),
        .x_cnt        (cap_x_cnt),
        .y_cnt        (cap_y_cnt)
    );

    // 调试用帧同步计数器：统计上一帧行数/像素数，并给出 frame_locked，方便判断摄像头是否稳定输出。
    wire [15:0] frame_cnt_dbg;
    wire [15:0] line_cnt_last_dbg;
    wire [31:0] pixel_cnt_last_dbg;
    wire frame_locked_dbg;
    frame_sync_counter u_frame_sync_counter (
        .rst_n          (rst_n_sys),
        .camera_pclk    (camera_pclk),
        .frame_start    (cap_frame_start),
        .frame_end      (cap_frame_end),
        .line_start     (cap_line_start),
        .line_end       (cap_line_end),
        .pix_valid      (cap_pix_valid),
        .frame_cnt      (frame_cnt_dbg),
        .line_cnt_last  (line_cnt_last_dbg),
        .pixel_cnt_last (pixel_cnt_last_dbg),
        .frame_locked   (frame_locked_dbg)
    );

    // ----------------------------
    // 以太网命令寄存器组
    // ----------------------------
    // Linux 侧 UDP 命令最终会被搬到 eth_clk125m 域，写入这个寄存器组。
    // 输出的 capture/alarm/roi/threshold 等配置需要同步到 camera_pclk 域后才能给图像统计逻辑使用。
    wire        capture_enable_eth_cfg;
    wire        alarm_enable_eth_cfg;
    wire        debug_uart_enable_eth_cfg;
    wire [10:0] roi_x_eth_cfg;
    wire [10:0] roi_y_eth_cfg;
    wire [10:0] roi_w_eth_cfg;
    wire [10:0] roi_h_eth_cfg;
    wire [7:0]  bright_threshold_eth_cfg;
    wire [15:0] alarm_count_threshold_eth_cfg;
    wire [1:0]  tx_mode_eth_cfg;
    wire        force_status_send_eth;
    wire        clear_error_eth_pulse;
    wire        last_cmd_error_eth_cfg;
    wire [15:0] last_cmd_seq_eth_cfg;
    wire        cmd_valid_eth;
    wire [7:0]  cmd_code_eth;
    wire [15:0] cmd_seq_eth;
    wire [15:0] cmd_addr_eth;
    wire [31:0] cmd_data0_eth;
    wire [31:0] cmd_data1_eth;

    // 命令寄存器组：解析后的命令在 eth_clk125m 域生效。
    // 典型功能：启停采集、调整 ROI、调整亮点阈值、清除错误/告警。
    vision_reg_bank u_vision_reg_bank (
        .clk              (eth_clk125m),
        .rst_n            (manual_rst_n & eth_clk_locked),
        .cmd_valid        (cmd_valid_eth),
        .cmd_code         (cmd_code_eth),
        .cmd_seq          (cmd_seq_eth),
        .cmd_addr         (cmd_addr_eth),
        .cmd_data0        (cmd_data0_eth),
        .cmd_data1        (cmd_data1_eth),
        .capture_enable   (capture_enable_eth_cfg),
        .alarm_enable     (alarm_enable_eth_cfg),
        .debug_uart_enable(debug_uart_enable_eth_cfg),
        .roi_x            (roi_x_eth_cfg),
        .roi_y            (roi_y_eth_cfg),
        .roi_w            (roi_w_eth_cfg),
        .roi_h            (roi_h_eth_cfg),
        .bright_threshold (bright_threshold_eth_cfg),
        .alarm_count_threshold(alarm_count_threshold_eth_cfg),
        .tx_mode          (tx_mode_eth_cfg),
        .force_status_send(force_status_send_eth),
        .clear_error_pulse(clear_error_eth_pulse),
        .last_cmd_error   (last_cmd_error_eth_cfg),
        .last_cmd_seq     (last_cmd_seq_eth_cfg)
    );

    // 这些 *_cam_ff0/ff1 是从 eth_clk125m 到 camera_pclk 的两级同步寄存器。
    // 对于多 bit 配置值，严格 CDC 设计通常需要握手或异步 FIFO；这里配置变化很慢，
    // 且 ROI/阈值短暂不一致只影响一两拍统计结果，因此采用简单两级同步。
    reg        capture_enable_cam_ff0;
    reg        capture_enable_cam_ff1;
    reg        alarm_enable_cam_ff0;
    reg        alarm_enable_cam_ff1;
    reg [10:0] roi_x_cam_ff0;
    reg [10:0] roi_x_cam_ff1;
    reg [10:0] roi_y_cam_ff0;
    reg [10:0] roi_y_cam_ff1;
    reg [10:0] roi_w_cam_ff0;
    reg [10:0] roi_w_cam_ff1;
    reg [10:0] roi_h_cam_ff0;
    reg [10:0] roi_h_cam_ff1;
    reg [7:0]  bright_threshold_cam_ff0;
    reg [7:0]  bright_threshold_cam_ff1;
    reg [15:0] alarm_count_threshold_cam_ff0;
    reg [15:0] alarm_count_threshold_cam_ff1;
    wire       clear_error_cam_pulse;

    // clear_error 是单拍命令，不能直接用两级寄存器同步，否则可能丢脉冲；
    // pulse_sync_toggle 用翻转位把源域单拍可靠搬到目标域。
    pulse_sync_toggle u_clear_error_to_cam (
        .src_clk   (eth_clk125m),
        .src_rst_n (manual_rst_n & eth_clk_locked),
        .src_pulse (clear_error_eth_pulse),
        .dst_clk   (camera_pclk),
        .dst_rst_n (rst_n_sys),
        .dst_pulse (clear_error_cam_pulse)
    );

    // 将以太网寄存器配置同步到摄像头像素域。复位默认值让系统上电后自动采集并打开告警。
    always @(posedge camera_pclk or negedge rst_n_sys) begin
        if (!rst_n_sys) begin
            capture_enable_cam_ff0    <= 1'b1;
            capture_enable_cam_ff1    <= 1'b1;
            alarm_enable_cam_ff0      <= 1'b1;
            alarm_enable_cam_ff1      <= 1'b1;
            roi_x_cam_ff0             <= 11'd0;
            roi_x_cam_ff1             <= 11'd0;
            roi_y_cam_ff0             <= 11'd0;
            roi_y_cam_ff1             <= 11'd0;
            roi_w_cam_ff0             <= 11'd64;
            roi_w_cam_ff1             <= 11'd64;
            roi_h_cam_ff0             <= 11'd64;
            roi_h_cam_ff1             <= 11'd64;
            bright_threshold_cam_ff0  <= 8'd128;
            bright_threshold_cam_ff1  <= 8'd128;
            alarm_count_threshold_cam_ff0 <= 16'd256;
            alarm_count_threshold_cam_ff1 <= 16'd256;
        end else begin
            capture_enable_cam_ff0    <= capture_enable_eth_cfg;
            capture_enable_cam_ff1    <= capture_enable_cam_ff0;
            alarm_enable_cam_ff0      <= alarm_enable_eth_cfg;
            alarm_enable_cam_ff1      <= alarm_enable_cam_ff0;
            roi_x_cam_ff0             <= roi_x_eth_cfg;
            roi_x_cam_ff1             <= roi_x_cam_ff0;
            roi_y_cam_ff0             <= roi_y_eth_cfg;
            roi_y_cam_ff1             <= roi_y_cam_ff0;
            roi_w_cam_ff0             <= roi_w_eth_cfg;
            roi_w_cam_ff1             <= roi_w_cam_ff0;
            roi_h_cam_ff0             <= roi_h_eth_cfg;
            roi_h_cam_ff1             <= roi_h_cam_ff0;
            bright_threshold_cam_ff0  <= bright_threshold_eth_cfg;
            bright_threshold_cam_ff1  <= bright_threshold_cam_ff0;
            alarm_count_threshold_cam_ff0 <= alarm_count_threshold_eth_cfg;
            alarm_count_threshold_cam_ff1 <= alarm_count_threshold_cam_ff0;
        end
    end

    // ----------------------------
    // ROI 统计、亮点计数和告警判断
    // ----------------------------
    // stats_din 是一条 160bit 统计记录，帧尾写入异步 FIFO，之后在 eth_clk125m 域打包成遥测 UDP。
    wire        stats_fifo_full;
    wire        stats_wr_en;
    wire [159:0] stats_din;
    wire        stats_fifo_overflow_dbg;
    wire        alarm_active_cam;

    // 不改变原始图像流，只旁路观察 pix_data/x/y，统计 ROI 内亮度和亮点数量。
    // alarm_active_cam 会驱动蜂鸣器，也会同步到以太网域上报状态。
    vision_preprocess_core #(
        .REPORT_WIDTH          (FRAME_WIDTH),
        .REPORT_HEIGHT         (FRAME_HEIGHT),
        .BYTES_PER_PIXEL       (2)
    ) u_vision_preprocess_core (
        .rst_n             (rst_n_sys),
        .camera_pclk       (camera_pclk),
        .capture_enable    (capture_enable_cam_ff1),
        .alarm_enable      (alarm_enable_cam_ff1),
        .clear_error       (clear_error_cam_pulse),
        .frame_start       (cap_frame_start),
        .frame_end         (cap_frame_end),
        .line_start        (cap_line_start),
        .line_end          (cap_line_end),
        .pix_valid         (cap_pix_valid),
        .pix_data          (cap_pix_data),
        .x_cnt             (cap_x_cnt),
        .y_cnt             (cap_y_cnt),
        .roi_x             (roi_x_cam_ff1),
        .roi_y             (roi_y_cam_ff1),
        .roi_w             (roi_w_cam_ff1),
        .roi_h             (roi_h_cam_ff1),
        .bright_threshold  (bright_threshold_cam_ff1),
        .alarm_count_threshold(alarm_count_threshold_cam_ff1),
        .stats_full        (stats_fifo_full),
        .stats_wr_en       (stats_wr_en),
        .stats_din         (stats_din),
        .fifo_overflow_flag(stats_fifo_overflow_dbg),
        .alarm_active      (alarm_active_cam)
    );

    // ----------------------------
    // DDR3 帧缓冲和预览读接口
    // ----------------------------
    // 摄像头写侧：camera_pclk 域写入最新一帧 RGB565。
    // 网络读侧：eth_clk125m 域按 UDP 分片生成器的请求读出像素。
    // 帧缓冲模块内部用双缓冲避免网络读正在读的 bank 被摄像头写侧覆盖。
    wire [15:0] rd_pixel;
    wire        rd_empty;
    wire [8:0]  rd_count;
    wire        ddr3_init_done;
    wire        ddr3_mmcm_locked_dbg;
    wire        ddr3_calib_done_dbg;
    wire        ddr3_wr_axi_seen_dbg;
    wire        ddr3_rd_axi_seen_dbg;
    wire        wr_frame_done_dbg;
    wire        rd_frame_done_dbg;
    wire        ui_clk;
    wire        ui_rst;
    wire        frame_start_16_dbg;
    wire        frame_end_16_dbg;
    wire        packer_error_dbg;
    wire        wrfifo_full_dbg;

    wire        preview_rd_restart;
    wire        preview_rd_en;
    wire        wr_frame_done_eth_pulse;
    wire        preview_packet_done_sys_pulse;
    wire        preview_frame_done_sys_pulse;
    (* ASYNC_REG = "TRUE" *) reg ddr3_init_done_eth_ff0;
    (* ASYNC_REG = "TRUE" *) reg ddr3_init_done_eth_ff1;
    reg ddr3_init_done_eth;
    (* ASYNC_REG = "TRUE" *) reg init_done_eth_ff0;
    (* ASYNC_REG = "TRUE" *) reg init_done_eth_ff1;
    reg init_done_eth;
    (* ASYNC_REG = "TRUE" *) reg init_error_eth_ff0;
    (* ASYNC_REG = "TRUE" *) reg init_error_eth_ff1;
    reg init_error_eth;
    (* ASYNC_REG = "TRUE" *) reg frame_locked_eth_ff0;
    (* ASYNC_REG = "TRUE" *) reg frame_locked_eth_ff1;
    reg frame_locked_eth;
    (* ASYNC_REG = "TRUE" *) reg packer_error_eth_ff0;
    (* ASYNC_REG = "TRUE" *) reg packer_error_eth_ff1;
    reg packer_error_eth;
    (* ASYNC_REG = "TRUE" *) reg wrfifo_full_eth_ff0;
    (* ASYNC_REG = "TRUE" *) reg wrfifo_full_eth_ff1;
    reg wrfifo_full_eth;
    (* ASYNC_REG = "TRUE" *) reg stats_overflow_eth_ff0;
    (* ASYNC_REG = "TRUE" *) reg stats_overflow_eth_ff1;
    reg stats_overflow_eth;
    (* ASYNC_REG = "TRUE" *) reg alarm_active_eth_ff0;
    (* ASYNC_REG = "TRUE" *) reg alarm_active_eth_ff1;
    reg alarm_active_eth;
    reg dbg_vsync_seen_cam;
    reg dbg_href_seen_cam;
    reg dbg_frame_start_seen_cam;
    reg dbg_frame_end_seen_cam;
    reg dbg_pix_valid_seen_cam;
    reg dbg_stats_wr_seen_cam;
    (* ASYNC_REG = "TRUE" *) reg dbg_vsync_seen_eth_ff0;
    (* ASYNC_REG = "TRUE" *) reg dbg_vsync_seen_eth_ff1;
    reg dbg_vsync_seen_eth;
    (* ASYNC_REG = "TRUE" *) reg dbg_href_seen_eth_ff0;
    (* ASYNC_REG = "TRUE" *) reg dbg_href_seen_eth_ff1;
    reg dbg_href_seen_eth;
    (* ASYNC_REG = "TRUE" *) reg dbg_frame_start_seen_eth_ff0;
    (* ASYNC_REG = "TRUE" *) reg dbg_frame_start_seen_eth_ff1;
    reg dbg_frame_start_seen_eth;
    (* ASYNC_REG = "TRUE" *) reg dbg_frame_end_seen_eth_ff0;
    (* ASYNC_REG = "TRUE" *) reg dbg_frame_end_seen_eth_ff1;
    reg dbg_frame_end_seen_eth;
    (* ASYNC_REG = "TRUE" *) reg dbg_pix_valid_seen_eth_ff0;
    (* ASYNC_REG = "TRUE" *) reg dbg_pix_valid_seen_eth_ff1;
    reg dbg_pix_valid_seen_eth;
    (* ASYNC_REG = "TRUE" *) reg dbg_stats_wr_seen_eth_ff0;
    (* ASYNC_REG = "TRUE" *) reg dbg_stats_wr_seen_eth_ff1;
    reg dbg_stats_wr_seen_eth;
    reg dbg_pkt_seen_eth;
    reg dbg_cmd_seen_eth;

    // DDR3 帧缓冲封装模块：
    //   - 写入端接收 8bit 摄像头字节流，内部打包成 16bit RGB565。
    //   - 写 FIFO/读 FIFO 和 MIG AXI 由子模块处理。
    //   - 读出端输出 16bit RGB565 像素，供 UDP 预览分片模块按需拉取。
    edge_ddr3_framebuffer #(
        .FRAME_WIDTH     (FRAME_WIDTH),
        .FRAME_HEIGHT    (FRAME_HEIGHT),
        .FRAME_BASE_ADDR (32'h0000_0000),
        .FRAME_BYTES     (FRAME_BYTES),
        .BURST_BYTES     (32'd512)
    ) u_edge_ddr3_framebuffer (
        .sys_rst_n         (rst_n_sys),
        .camera_pclk       (camera_pclk),
        .frame_start       (cap_frame_start),
        .frame_end         (cap_frame_end),
        .line_start        (cap_line_start),
        .line_end          (cap_line_end),
        .pix_valid         (cap_pix_valid),
        .pix_data          (cap_pix_data),
        .rd_clk            (eth_clk125m),
        .rd_frame_restart  (preview_rd_restart),
        .rd_en             (preview_rd_en),
        .rd_pixel          (rd_pixel),
        .rd_empty          (rd_empty),
        .rd_count          (rd_count),
        .ddr3_clk200m      (ddr3_clk200m),
        .ddr3_rst_n        (manual_rst_n & ddr3_clk_locked),
        .ddr3_init_done    (ddr3_init_done),
        .ddr3_mmcm_locked  (ddr3_mmcm_locked_dbg),
        .ddr3_calib_done   (ddr3_calib_done_dbg),
        .ddr3_wr_axi_seen  (ddr3_wr_axi_seen_dbg),
        .ddr3_rd_axi_seen  (ddr3_rd_axi_seen_dbg),
        .wr_frame_done_dbg (wr_frame_done_dbg),
        .rd_frame_done_dbg (rd_frame_done_dbg),
        .ui_clk            (ui_clk),
        .ui_rst            (ui_rst),
        .ddr3_dq           (ddr3_dq),
        .ddr3_dqs_n        (ddr3_dqs_n),
        .ddr3_dqs_p        (ddr3_dqs_p),
        .ddr3_addr         (ddr3_addr),
        .ddr3_ba           (ddr3_ba),
        .ddr3_ras_n        (ddr3_ras_n),
        .ddr3_cas_n        (ddr3_cas_n),
        .ddr3_we_n         (ddr3_we_n),
        .ddr3_reset_n      (ddr3_reset_n),
        .ddr3_ck_p         (ddr3_ck_p),
        .ddr3_ck_n         (ddr3_ck_n),
        .ddr3_cke          (ddr3_cke),
        .ddr3_cs_n         (ddr3_cs_n),
        .ddr3_dm           (ddr3_dm),
        .ddr3_odt          (ddr3_odt),
        .frame_start_16_dbg(frame_start_16_dbg),
        .frame_end_16_dbg  (frame_end_16_dbg),
        .packer_error_dbg  (packer_error_dbg),
        .wrfifo_full_dbg   (wrfifo_full_dbg)
    );

    // 摄像头域“整帧已写入 DDR3”的单拍事件同步到以太网域，触发一次预览帧发送。
    pulse_sync_toggle u_wr_frame_done_to_eth (
        .src_clk   (camera_pclk),
        .src_rst_n (manual_rst_n),
        .src_pulse (wr_frame_done_dbg),
        .dst_clk   (eth_clk125m),
        .dst_rst_n (manual_rst_n & eth_clk_locked),
        .dst_pulse (wr_frame_done_eth_pulse)
    );

    // 摄像头域调试 sticky 位。只要见过对应事件就置 1，便于 LED/遥测判断摄像头链路是否跑起来。
    always @(posedge camera_pclk or negedge rst_n_sys) begin
        if (!rst_n_sys) begin
            dbg_vsync_seen_cam       <= 1'b0;
            dbg_href_seen_cam        <= 1'b0;
            dbg_frame_start_seen_cam <= 1'b0;
            dbg_frame_end_seen_cam   <= 1'b0;
            dbg_pix_valid_seen_cam   <= 1'b0;
            dbg_stats_wr_seen_cam    <= 1'b0;
        end else begin
            if (camera_vsync) begin
                dbg_vsync_seen_cam <= 1'b1;
            end
            if (camera_href) begin
                dbg_href_seen_cam <= 1'b1;
            end
            if (cap_frame_start) begin
                dbg_frame_start_seen_cam <= 1'b1;
            end
            if (cap_frame_end) begin
                dbg_frame_end_seen_cam <= 1'b1;
            end
            if (cap_pix_valid) begin
                dbg_pix_valid_seen_cam <= 1'b1;
            end
            if (stats_wr_en) begin
                dbg_stats_wr_seen_cam <= 1'b1;
            end
        end
    end

    // 将分散在 sys/camera/DDR3 域的状态同步到 eth_clk125m 域，供 status_bits/error_code 打包上报。
    // 这些都是慢变状态或 sticky 标志，用两级同步即可；单拍事件另用 pulse_sync_toggle。
    always @(posedge eth_clk125m or negedge manual_rst_n) begin
        if (!manual_rst_n) begin
            ddr3_init_done_eth_ff0 <= 1'b0;
            ddr3_init_done_eth_ff1 <= 1'b0;
            ddr3_init_done_eth     <= 1'b0;
            init_done_eth_ff0      <= 1'b0;
            init_done_eth_ff1      <= 1'b0;
            init_done_eth          <= 1'b0;
            init_error_eth_ff0     <= 1'b0;
            init_error_eth_ff1     <= 1'b0;
            init_error_eth         <= 1'b0;
            frame_locked_eth_ff0   <= 1'b0;
            frame_locked_eth_ff1   <= 1'b0;
            frame_locked_eth       <= 1'b0;
            packer_error_eth_ff0   <= 1'b0;
            packer_error_eth_ff1   <= 1'b0;
            packer_error_eth       <= 1'b0;
            wrfifo_full_eth_ff0    <= 1'b0;
            wrfifo_full_eth_ff1    <= 1'b0;
            wrfifo_full_eth        <= 1'b0;
            stats_overflow_eth_ff0 <= 1'b0;
            stats_overflow_eth_ff1 <= 1'b0;
            stats_overflow_eth     <= 1'b0;
            alarm_active_eth_ff0   <= 1'b0;
            alarm_active_eth_ff1   <= 1'b0;
            alarm_active_eth       <= 1'b0;
            dbg_vsync_seen_eth_ff0 <= 1'b0;
            dbg_vsync_seen_eth_ff1 <= 1'b0;
            dbg_vsync_seen_eth     <= 1'b0;
            dbg_href_seen_eth_ff0  <= 1'b0;
            dbg_href_seen_eth_ff1  <= 1'b0;
            dbg_href_seen_eth      <= 1'b0;
            dbg_frame_start_seen_eth_ff0 <= 1'b0;
            dbg_frame_start_seen_eth_ff1 <= 1'b0;
            dbg_frame_start_seen_eth     <= 1'b0;
            dbg_frame_end_seen_eth_ff0 <= 1'b0;
            dbg_frame_end_seen_eth_ff1 <= 1'b0;
            dbg_frame_end_seen_eth     <= 1'b0;
            dbg_pix_valid_seen_eth_ff0 <= 1'b0;
            dbg_pix_valid_seen_eth_ff1 <= 1'b0;
            dbg_pix_valid_seen_eth     <= 1'b0;
            dbg_stats_wr_seen_eth_ff0 <= 1'b0;
            dbg_stats_wr_seen_eth_ff1 <= 1'b0;
            dbg_stats_wr_seen_eth     <= 1'b0;
            dbg_pkt_seen_eth          <= 1'b0;
            dbg_cmd_seen_eth          <= 1'b0;
        end else begin
            ddr3_init_done_eth_ff0 <= ddr3_init_done;
            ddr3_init_done_eth_ff1 <= ddr3_init_done_eth_ff0;
            ddr3_init_done_eth     <= ddr3_init_done_eth_ff1;
            init_done_eth_ff0      <= init_done_sticky_sys;
            init_done_eth_ff1      <= init_done_eth_ff0;
            init_done_eth          <= init_done_eth_ff1;
            init_error_eth_ff0     <= init_error_sticky_sys;
            init_error_eth_ff1     <= init_error_eth_ff0;
            init_error_eth         <= init_error_eth_ff1;
            frame_locked_eth_ff0   <= frame_locked_dbg;
            frame_locked_eth_ff1   <= frame_locked_eth_ff0;
            frame_locked_eth       <= frame_locked_eth_ff1;
            packer_error_eth_ff0   <= packer_error_dbg;
            packer_error_eth_ff1   <= packer_error_eth_ff0;
            packer_error_eth       <= packer_error_eth_ff1;
            wrfifo_full_eth_ff0    <= wrfifo_full_dbg;
            wrfifo_full_eth_ff1    <= wrfifo_full_eth_ff0;
            wrfifo_full_eth        <= wrfifo_full_eth_ff1;
            stats_overflow_eth_ff0 <= stats_fifo_overflow_dbg;
            stats_overflow_eth_ff1 <= stats_overflow_eth_ff0;
            stats_overflow_eth     <= stats_overflow_eth_ff1;
            alarm_active_eth_ff0   <= alarm_active_cam;
            alarm_active_eth_ff1   <= alarm_active_eth_ff0;
            alarm_active_eth       <= alarm_active_eth_ff1;
            dbg_vsync_seen_eth_ff0 <= dbg_vsync_seen_cam;
            dbg_vsync_seen_eth_ff1 <= dbg_vsync_seen_eth_ff0;
            dbg_vsync_seen_eth     <= dbg_vsync_seen_eth_ff1;
            dbg_href_seen_eth_ff0  <= dbg_href_seen_cam;
            dbg_href_seen_eth_ff1  <= dbg_href_seen_eth_ff0;
            dbg_href_seen_eth      <= dbg_href_seen_eth_ff1;
            dbg_frame_start_seen_eth_ff0 <= dbg_frame_start_seen_cam;
            dbg_frame_start_seen_eth_ff1 <= dbg_frame_start_seen_eth_ff0;
            dbg_frame_start_seen_eth     <= dbg_frame_start_seen_eth_ff1;
            dbg_frame_end_seen_eth_ff0 <= dbg_frame_end_seen_cam;
            dbg_frame_end_seen_eth_ff1 <= dbg_frame_end_seen_eth_ff0;
            dbg_frame_end_seen_eth     <= dbg_frame_end_seen_eth_ff1;
            dbg_pix_valid_seen_eth_ff0 <= dbg_pix_valid_seen_cam;
            dbg_pix_valid_seen_eth_ff1 <= dbg_pix_valid_seen_eth_ff0;
            dbg_pix_valid_seen_eth     <= dbg_pix_valid_seen_eth_ff1;
            dbg_stats_wr_seen_eth_ff0 <= dbg_stats_wr_seen_cam;
            dbg_stats_wr_seen_eth_ff1 <= dbg_stats_wr_seen_eth_ff0;
            dbg_stats_wr_seen_eth     <= dbg_stats_wr_seen_eth_ff1;
            if (preview_packet_done_pulse) begin
                dbg_pkt_seen_eth <= 1'b1;
            end
            if (cmd_valid_eth) begin
                dbg_cmd_seen_eth <= 1'b1;
            end
        end
    end

    // ----------------------------
    // 以太网 RX：接收 Linux 侧 UDP 命令
    // ----------------------------
    // edge_eth_udp_cfg 集中定义本机/目标 MAC、IP、端口。修改网络地址通常只需要看这个子模块。
    wire [47:0] local_mac;
    wire [31:0] local_ip;
    wire [15:0] local_port;
    wire [47:0] dest_mac;
    wire [31:0] dest_ip;
    wire [15:0] dest_port;
    wire [15:0] cmd_port;
    edge_eth_udp_cfg u_edge_eth_udp_cfg (
        .local_mac (local_mac),
        .local_ip  (local_ip),
        .local_port(local_port),
        .dest_mac  (dest_mac),
        .dest_ip   (dest_ip),
        .dest_port (dest_port),
        .cmd_port  (cmd_port)
    );

    // RGMII RX 需要相位调整后的接收时钟，eth_phase_mmcm 对 PHY 返回的 rgmii_rx_clk_i 做相位处理。
    wire rgmii_rx_clk_phase;
    wire rx_phase_locked;
    eth_phase_mmcm u_eth_phase_mmcm (
        .clk_in1 (rgmii_rx_clk_i),
        .reset   (~manual_rst_n),
        .clk_out1(rgmii_rx_clk_phase),
        .locked  (rx_phase_locked)
    );

    (* ASYNC_REG = "TRUE" *) reg [2:0] rst_rx_sync_ff;

    // 在相位调整后的 RX 时钟域释放复位。rx_phase_locked 未锁定时保持 RX 链路复位。
    always @(posedge rgmii_rx_clk_phase or negedge manual_rst_n or negedge rx_phase_locked) begin
        if (!manual_rst_n || !rx_phase_locked) begin
            rst_rx_sync_ff <= 3'b000;
        end else begin
            rst_rx_sync_ff <= {rst_rx_sync_ff[1:0], 1'b1};
        end
    end
    wire rst_rx_n = rst_rx_sync_ff[2];

    // 把 PHY 的 RGMII 4bit DDR 接收接口转换成内部 GMII 8bit 接口。
    wire       gmii_rx_clk;
    wire [7:0] gmii_rxd;
    wire       gmii_rxdv;
    wire       gmii_rxerr;
    rgmii_to_gmii u_rgmii_to_gmii (
        .reset_n     (rst_rx_n),
        .gmii_rx_clk (gmii_rx_clk),
        .gmii_rxdv   (gmii_rxdv),
        .gmii_rxd    (gmii_rxd),
        .gmii_rxerr  (gmii_rxerr),
        .rgmii_rx_clk(rgmii_rx_clk_phase),
        .rgmii_rxd   (rgmii_rxd),
        .rgmii_rxdv  (rgmii_rxdv)
    );

    // 以太网/IPv4/UDP 接收链路。这里只接收 cmd_port 端口上的 UDP 载荷，输出连续 payload 字节。
    wire        rx_clk125m;
    wire [47:0] rx_exter_mac;
    wire [31:0] rx_exter_ip;
    wire [15:0] rx_exter_port;
    wire [15:0] rx_data_length;
    wire        rx_payload_valid;
    wire [7:0]  rx_payload_dat;
    wire        rx_one_pkt_done;
    wire        rx_pkt_error;
    wire [31:0] rx_debug_crc_check;
    eth_udp_rx_gmii u_eth_udp_rx_gmii (
        .reset_p        (~rst_rx_n),
        .local_mac      (local_mac),
        .local_ip       (local_ip),
        .local_port     (cmd_port),
        .clk125m_o      (rx_clk125m),
        .exter_mac      (rx_exter_mac),
        .exter_ip       (rx_exter_ip),
        .exter_port     (rx_exter_port),
        .rx_data_length (rx_data_length),
        .data_overflow_i(1'b0),
        .payload_valid_o(rx_payload_valid),
        .payload_dat_o  (rx_payload_dat),
        .one_pkt_done   (rx_one_pkt_done),
        .pkt_error      (rx_pkt_error),
        .debug_crc_check(rx_debug_crc_check),
        .gmii_rx_clk    (gmii_rx_clk),
        .gmii_rxdv      (gmii_rxdv),
        .gmii_rxd       (gmii_rxd)
    );

    // 将 UDP payload 解析成固定格式命令字段：cmd_code/seq/addr/data0/data1。
    wire        cmd_pkt_valid_rx;
    wire [7:0]  cmd_code_rx;
    wire [15:0] cmd_seq_rx;
    wire [15:0] cmd_addr_rx;
    wire [31:0] cmd_data0_rx;
    wire [31:0] cmd_data1_rx;
    udp_cmd_packet_parser u_udp_cmd_packet_parser (
        .clk             (rx_clk125m),
        .rst_n           (rst_rx_n),
        .payload_valid_i (rx_payload_valid),
        .payload_dat_i   (rx_payload_dat),
        .rx_data_length_i(rx_data_length),
        .one_pkt_done_i  (rx_one_pkt_done),
        .pkt_error_i     (rx_pkt_error),
        .cmd_valid_o     (cmd_pkt_valid_rx),
        .cmd_code_o      (cmd_code_rx),
        .cmd_seq_o       (cmd_seq_rx),
        .cmd_addr_o      (cmd_addr_rx),
        .cmd_data0_o     (cmd_data0_rx),
        .cmd_data1_o     (cmd_data1_rx)
    );

    // RX 解析时钟来自接收链路，寄存器组工作在 eth_clk125m；
    // 异步 FIFO 负责跨时钟域，并把命令字段打包为 104bit。
    wire        cmd_fifo_full;
    wire        cmd_fifo_empty;
    wire [103:0] cmd_fifo_dout;
    reg         cmd_fifo_rd_en;

    cmd_async_fifo #(
        .DATA_WIDTH(104),
        .FIFO_DEPTH(16)
    ) u_cmd_async_fifo (
        .rst_n (manual_rst_n & eth_clk_locked & rx_phase_locked),
        .wr_clk(rx_clk125m),
        .wr_en (cmd_pkt_valid_rx & ~cmd_fifo_full),
        .din   ({cmd_code_rx, cmd_seq_rx, cmd_addr_rx, cmd_data0_rx, cmd_data1_rx}),
        .full  (cmd_fifo_full),
        .rd_clk(eth_clk125m),
        .rd_en (cmd_fifo_rd_en),
        .dout  (cmd_fifo_dout),
        .empty (cmd_fifo_empty)
    );

    // FIFO 非空就表示当前 dout 上有一条待执行命令；下一拍 cmd_fifo_rd_en 会把它消费掉。
    assign cmd_valid_eth = ~cmd_fifo_empty;
    assign cmd_code_eth  = cmd_fifo_dout[103:96];
    assign cmd_seq_eth   = cmd_fifo_dout[95:80];
    assign cmd_addr_eth  = cmd_fifo_dout[79:64];
    assign cmd_data0_eth = cmd_fifo_dout[63:32];
    assign cmd_data1_eth = cmd_fifo_dout[31:0];

    // 简单“一拍读一条”命令消费逻辑。cmd_valid_eth 同时送给寄存器组作为写命令有效。
    always @(posedge eth_clk125m or negedge manual_rst_n) begin
        if (!manual_rst_n) begin
            cmd_fifo_rd_en <= 1'b0;
        end else begin
            cmd_fifo_rd_en <= cmd_valid_eth;
        end
    end

    // ----------------------------
    // 以太网 TX：RGB565 预览和遥测包共用发送器
    // ----------------------------
    // preview_* 是大流量图像分片，telem_* 是小的 32 字节状态/统计包。
    // 两类包共享 eth_udp_tx_gmii，因此下面用 udp_tx_src_sel 记录当前正在发送哪一类 payload。
    wire [15:0] preview_data_length;
    wire [7:0]  preview_payload_dat;
    wire        preview_payload_req;
    wire        preview_tx_launch_pulse;
    wire        preview_tx_done;
    wire        udp_payload_req;
    wire        udp_tx_en_pulse;
    wire        udp_tx_done;
    wire        preview_packet_done_pulse;
    wire        preview_frame_done_pulse;
    wire [15:0] preview_frame_id_dbg;
    wire        telem_send_start;
    wire [7:0]  telem_payload_dat;
    wire [15:0] telem_payload_len;
    wire        telem_payload_req;
    wire        telem_payload_busy;
    wire        telem_send_done;
    localparam  UDP_SRC_PREVIEW = 1'b0;
    localparam  UDP_SRC_TELEM   = 1'b1;
    reg         udp_tx_busy_mux;
    reg         udp_tx_src_sel;
    wire        udp_launch_telem;
    wire        udp_launch_preview;
    wire        udp_src_sel_now;
    wire [15:0] udp_data_length;
    wire [7:0]  udp_payload_dat;

    // 从 DDR3 读出完整 RGB565 帧，按 CHUNK_DATA_BYTES 分片。
    // 每片前面加 16 字节预览头，Linux/Web 端可根据 frame_id/chunk_id/offset 重组或显示。
    rgb565_udp_preview_payload_gen #(
        .FRAME_WIDTH      (FRAME_WIDTH),
        .FRAME_HEIGHT     (FRAME_HEIGHT),
        .CHUNK_DATA_BYTES (1400),
        .PREVIEW_MSG_TYPE (8'h12)
    ) u_rgb565_udp_preview_payload_gen (
        .clk               (eth_clk125m),
        .rst_n             (manual_rst_n & eth_clk_locked & ddr3_init_done_eth),
        .frame_ready       (wr_frame_done_eth_pulse),
        .tx_busy           (udp_tx_busy_mux | telem_send_start),
        .rd_frame_restart  (preview_rd_restart),
        .rd_en             (preview_rd_en),
        .rd_pixel          (rd_pixel),
        .rd_empty          (rd_empty),
        .tx_en_pulse       (preview_tx_launch_pulse),
        .tx_done           (preview_tx_done),
        .payload_req       (preview_payload_req),
        .data_length       (preview_data_length),
        .payload_dat       (preview_payload_dat),
        .preview_frame_id  (preview_frame_id_dbg),
        .preview_packet_done(preview_packet_done_pulse),
        .preview_frame_done(preview_frame_done_pulse)
    );

    // 统计记录从 camera_pclk 域写入，在 eth_clk125m 域读出打包。
    // FIFO 满会在 vision_preprocess_core 里置 overflow 标志，并通过 status/error_code 上报。
    wire [159:0] stats_fifo_dout;
    wire         stats_fifo_empty;
    wire         stats_fifo_rd_en;

    stats_async_fifo #(
        .DATA_WIDTH(160),
        .FIFO_DEPTH(16)
    ) u_stats_async_fifo (
        .rst_n (rst_n_sys),
        .wr_clk(camera_pclk),
        .wr_en (stats_wr_en),
        .din   (stats_din),
        .full  (stats_fifo_full),
        .rd_clk(eth_clk125m),
        .rd_en (stats_fifo_rd_en),
        .dout  (stats_fifo_dout),
        .empty (stats_fifo_empty)
    );

    wire [15:0] status_bits;
    wire [15:0] error_code;

    // status_bits 会进入遥测包。注意拼接时最下面一项是 bit0，最上面一项是 bit15：
    // bit0  init_done_eth
    // bit1  frame_locked_eth
    // bit2  stats_overflow_eth | wrfifo_full_eth
    // bit3  udp_tx_busy_mux
    // bit4  capture_enable_eth_cfg
    // bit5  alarm_active_eth
    // bit6  eth_clk_locked
    // bit7  last_cmd_error_eth_cfg
    // bit8  alarm_enable_eth_cfg
    // bit9  dbg_pkt_seen_eth | dbg_cmd_seen_eth
    // bit10 dbg_vsync_seen_eth
    // bit11 dbg_href_seen_eth
    // bit12 dbg_frame_start_seen_eth
    // bit13 dbg_frame_end_seen_eth
    // bit14 dbg_pix_valid_seen_eth
    // bit15 dbg_stats_wr_seen_eth
    assign status_bits = {
        dbg_stats_wr_seen_eth,
        dbg_pix_valid_seen_eth,
        dbg_frame_end_seen_eth,
        dbg_frame_start_seen_eth,
        dbg_href_seen_eth,
        dbg_vsync_seen_eth,
        (dbg_pkt_seen_eth | dbg_cmd_seen_eth),
        alarm_enable_eth_cfg,
        last_cmd_error_eth_cfg,
        eth_clk_locked,
        alarm_active_eth,
        capture_enable_eth_cfg,
        udp_tx_busy_mux,
        (stats_overflow_eth | wrfifo_full_eth),
        frame_locked_eth,
        init_done_eth
    };
    // error_code 只给出当前最高优先级错误，便于 Linux 侧快速定位：
    // 0001 摄像头初始化失败，0002 RGB565 字节相位错误，0003 写 FIFO 满，
    // 0004 统计 FIFO 溢出，0005 最后一条命令格式/地址错误。
    assign error_code = init_error_eth ? 16'h0001 :
                        packer_error_eth ? 16'h0002 :
                        wrfifo_full_eth  ? 16'h0003 :
                        stats_overflow_eth ? 16'h0004 :
                        last_cmd_error_eth_cfg ? 16'h0005 : 16'h0000;

    // 把 160bit 统计记录 + 状态位 + 错误码整理成固定 256bit 遥测包。
    wire [255:0] telem_pkt_data_256;
    wire         telem_pkt_valid;
    wire         telem_pkt_accept;

    frame_stats_packet_parallel u_frame_stats_packet_parallel (
        .clk         (eth_clk125m),
        .rst_n       (manual_rst_n & eth_clk_locked & ddr3_init_done_eth),
        .status_bits (status_bits),
        .error_code  (error_code),
        .stats_dout  (stats_fifo_dout),
        .stats_empty (stats_fifo_empty),
        .stats_rd_en (stats_fifo_rd_en),
        .pkt_data_256(telem_pkt_data_256),
        .pkt_valid   (telem_pkt_valid),
        .pkt_accept  (telem_pkt_accept)
    );

    // 遥测发送控制：当有统计包或状态需要上报，并且 payload/UDP 发送器空闲时，拉起 telem_send_start。
    vision_udp_status_ctrl u_vision_udp_status_ctrl (
        .clk         (eth_clk125m),
        .rst_n       (manual_rst_n & eth_clk_locked & ddr3_init_done_eth),
        .pkt_valid   (telem_pkt_valid),
        .payload_busy(telem_payload_busy | udp_tx_busy_mux),
        .tx_done     (udp_tx_done & udp_tx_busy_mux & udp_tx_src_sel),
        .send_start  (telem_send_start)
    );

    // 将 256bit 遥测包按 UDP TX 的 payload_req 节奏转换成 8bit payload 字节流。
    vision32_payload_gen u_vision32_payload_gen (
        .clk         (eth_clk125m),
        .rst_n       (manual_rst_n & eth_clk_locked & ddr3_init_done_eth),
        .pkt_data_256(telem_pkt_data_256),
        .pkt_valid   (telem_pkt_valid),
        .pkt_accept  (telem_pkt_accept),
        .send_start  (telem_send_start & ~udp_tx_busy_mux),
        .payload_req (telem_payload_req),
        .payload_data(telem_payload_dat),
        .payload_len (telem_payload_len),
        .busy        (telem_payload_busy),
        .send_done   (telem_send_done)
    );

    // UDP TX 源选择规则：
    //   1. 遥测包优先级高于预览分片，避免状态上报被大图像流长期占用。
    //   2. 一旦某个源启动发送，直到 udp_tx_done 前 udp_tx_src_sel 保持不变。
    //   3. payload_req 只回送给当前被选中的 payload 生成器。
    assign udp_launch_telem   = telem_send_start & ~udp_tx_busy_mux;
    assign udp_launch_preview = preview_tx_launch_pulse & ~udp_tx_busy_mux & ~udp_launch_telem;
    assign udp_src_sel_now    = udp_tx_busy_mux ? udp_tx_src_sel :
                                (udp_launch_telem ? UDP_SRC_TELEM : UDP_SRC_PREVIEW);
    assign udp_data_length    = udp_src_sel_now ? telem_payload_len : preview_data_length;
    assign udp_payload_dat    = udp_src_sel_now ? telem_payload_dat : preview_payload_dat;
    assign udp_tx_en_pulse        = udp_launch_telem | udp_launch_preview;
    assign preview_payload_req    = udp_payload_req & udp_tx_busy_mux & (udp_tx_src_sel == UDP_SRC_PREVIEW);
    assign telem_payload_req      = udp_payload_req & udp_tx_busy_mux & (udp_tx_src_sel == UDP_SRC_TELEM);
    assign preview_tx_done        = udp_tx_done & udp_tx_busy_mux & (udp_tx_src_sel == UDP_SRC_PREVIEW);

    // UDP 发送源锁存。空闲时响应 launch；发送中等待 eth_udp_tx_gmii 返回 udp_tx_done。
    always @(posedge eth_clk125m or negedge manual_rst_n) begin
        if (!manual_rst_n) begin
            udp_tx_busy_mux <= 1'b0;
            udp_tx_src_sel  <= UDP_SRC_PREVIEW;
        end else begin
            if (!udp_tx_busy_mux) begin
                if (udp_launch_telem) begin
                    udp_tx_busy_mux <= 1'b1;
                    udp_tx_src_sel  <= UDP_SRC_TELEM;
                end else if (udp_launch_preview) begin
                    udp_tx_busy_mux <= 1'b1;
                    udp_tx_src_sel  <= UDP_SRC_PREVIEW;
                end
            end else if (udp_tx_done) begin
                udp_tx_busy_mux <= 1'b0;
            end
        end
    end

    // 组 UDP/IPv4/以太网帧并输出 GMII 8bit TX。payload_req_o 是拉取式接口：
    // 发送器需要下一个 payload 字节时拉高，当前源在 udp_payload_dat 上给出对应字节。
    wire       gmii_tx_clk;
    wire [7:0] gmii_txd;
    wire       gmii_txen;

    eth_udp_tx_gmii u_eth_udp_tx_gmii (
        .clk125M       (eth_clk125m),
        .reset_n       (manual_rst_n & eth_clk_locked & ddr3_init_done_eth),
        .tx_en_pulse   (udp_tx_en_pulse),
        .tx_done       (udp_tx_done),
        .dst_mac       (dest_mac),
        .src_mac       (local_mac),
        .dst_ip        (dest_ip),
        .src_ip        (local_ip),
        .dst_port      (dest_port),
        .src_port      (local_port),
        .data_length   (udp_data_length),
        .payload_req_o (udp_payload_req),
        .payload_dat_i (udp_payload_dat),
        .gmii_tx_clk   (gmii_tx_clk),
        .gmii_txen     (gmii_txen),
        .gmii_txd      (gmii_txd)
    );

    // 把内部 GMII 8bit 发送接口转换为 PHY 所需 RGMII 4bit DDR 接口。
    gmii_to_rgmii u_gmii_to_rgmii (
        .reset_n      (manual_rst_n & eth_clk_locked & ddr3_init_done_eth),
        .gmii_tx_clk  (gmii_tx_clk),
        .gmii_txd     (gmii_txd),
        .gmii_txen    (gmii_txen),
        .gmii_txer    (1'b0),
        .rgmii_tx_clk (rgmii_tx_clk),
        .rgmii_txd    (rgmii_txd),
        .rgmii_txen   (rgmii_txen)
    );

    // 预览包/帧完成事件同步回 sys_clk 域，用于 LED sticky 指示。
    pulse_sync_toggle u_preview_packet_done_to_sys (
        .src_clk   (eth_clk125m),
        .src_rst_n (manual_rst_n & eth_clk_locked),
        .src_pulse (preview_packet_done_pulse),
        .dst_clk   (sys_clk),
        .dst_rst_n (rst_n_sys),
        .dst_pulse (preview_packet_done_sys_pulse)
    );

    pulse_sync_toggle u_preview_frame_done_to_sys (
        .src_clk   (eth_clk125m),
        .src_rst_n (manual_rst_n & eth_clk_locked),
        .src_pulse (preview_frame_done_pulse),
        .dst_clk   (sys_clk),
        .dst_rst_n (rst_n_sys),
        .dst_pulse (preview_frame_done_sys_pulse)
    );

    // PHY 复位释放。目前只依赖发送侧 125 MHz clock wizard locked；
    // 如果板级 PHY 还需要额外上电延迟，可在这里增加计数器。
    assign eth_reset_n = eth_clk_locked;

    reg preview_packet_seen;
    reg preview_frame_seen;
    reg [25:0] hb_cnt;

    // LED 状态指示：
    //   LED0 心跳，说明 sys_clk/rst_n_sys 正常。
    //   LED1 摄像头 SCCB 初始化完成。
    //   LED2 DDR3 200 MHz clock wizard locked。
    //   LED3 MIG 内部 MMCM locked。
    //   LED4 摄像头帧同步稳定。
    //   LED5 DDR3 MIG 校准完成。
    //   LED6 至少完成过一个预览 UDP 分片。
    //   LED7 至少完成过一整帧预览发送。
    always @(posedge sys_clk or negedge rst_n_sys) begin
        if (!rst_n_sys) begin
            hb_cnt             <= 26'd0;
            preview_packet_seen<= 1'b0;
            preview_frame_seen <= 1'b0;
            LED0 <= 1'b0;
            LED1 <= 1'b0;
            LED2 <= 1'b0;
            LED3 <= 1'b0;
            LED4 <= 1'b0;
            LED5 <= 1'b0;
            LED6 <= 1'b0;
            LED7 <= 1'b0;
        end else begin
            hb_cnt <= hb_cnt + 1'b1;
            if (preview_packet_done_sys_pulse) begin
                preview_packet_seen <= 1'b1;
            end
            if (preview_frame_done_sys_pulse) begin
                preview_frame_seen <= 1'b1;
            end

            LED0 <= hb_cnt[25];
            LED1 <= init_done_sticky_sys;
            LED2 <= ddr3_clk_locked;
            LED3 <= ddr3_mmcm_locked_dbg;
            LED4 <= frame_locked_dbg;
            LED5 <= ddr3_calib_done_dbg;
            LED6 <= preview_packet_seen;
            LED7 <= preview_frame_seen;
        end
    end

    reg [24:0] beep_hold_cnt;
    reg [12:0] beep_tone_cnt;
    reg        beep_tone_level;
    wire       beep_hold_active = (beep_hold_cnt != 25'd0);
    wire       beep_drive_active = alarm_enable_cam_ff1 && beep_hold_active && beep_tone_level;

    // 蜂鸣器逻辑运行在 camera_pclk 域，因为告警判断也在该域。
    // alarm_active_cam 置位时刷新保持计数，并按 BEEP_TONE_HALF_CYCLES 翻转输出形成方波。
    // 告警关闭或 clear_error 命令到达时立即静音。
    always @(posedge camera_pclk or negedge rst_n_sys) begin
        if (!rst_n_sys) begin
            beep_hold_cnt <= 25'd0;
            beep_tone_cnt <= 13'd0;
            beep_tone_level <= 1'b0;
        end else if (!alarm_enable_cam_ff1 || clear_error_cam_pulse) begin
            beep_hold_cnt <= 25'd0;
            beep_tone_cnt <= 13'd0;
            beep_tone_level <= 1'b0;
        end else if (alarm_active_cam) begin
            beep_hold_cnt <= BEEP_HOLD_CYCLES;
            if (beep_tone_cnt >= (BEEP_TONE_HALF_CYCLES - 1'b1)) begin
                beep_tone_cnt <= 13'd0;
                beep_tone_level <= ~beep_tone_level;
            end else begin
                beep_tone_cnt <= beep_tone_cnt + 1'b1;
            end
        end else if (beep_hold_cnt != 25'd0) begin
            beep_hold_cnt <= beep_hold_cnt - 1'b1;
            if (beep_tone_cnt >= (BEEP_TONE_HALF_CYCLES - 1'b1)) begin
                beep_tone_cnt <= 13'd0;
                beep_tone_level <= ~beep_tone_level;
            end else begin
                beep_tone_cnt <= beep_tone_cnt + 1'b1;
            end
        end else begin
            beep_tone_cnt <= 13'd0;
            beep_tone_level <= 1'b0;
        end
    end

    assign BEEP = beep_drive_active ? BEEP_ACTIVE_LEVEL : ~BEEP_ACTIVE_LEVEL;

endmodule
