`timescale 1ns / 1ps

module top_ov2640_ddr3_udp_preview (
    input  wire FPGA_CLK,
    input  wire S0,

    input  wire [7:0] camera_d,
    input  wire       camera_pclk,
    input  wire       camera_href,
    input  wire       camera_vsync,

    output wire       camera_xclk,
    inout  wire       camera_scl,
    inout  wire       camera_sda,

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

    output wire        eth_reset_n,
    output wire        rgmii_tx_clk,
    output wire [3:0]  rgmii_txd,
    output wire        rgmii_txen,
    input  wire        rgmii_rx_clk_i,
    input  wire [3:0]  rgmii_rxd,
    input  wire        rgmii_rxdv,

    output reg         LED0,
    output reg         LED1,
    output reg         LED2,
    output reg         LED3,
    output reg         LED4,
    output reg         LED5,
    output reg         LED6,
    output reg         LED7,
    output wire        BEEP
);

    localparam integer FRAME_WIDTH      = 800;
    localparam integer FRAME_HEIGHT     = 600;
    localparam integer FRAME_BYTES      = FRAME_WIDTH * FRAME_HEIGHT * 2;
    localparam integer INIT_WAIT_CYCLES = 1_000_000;
    // Stretch short alarm pulses and drive a tone for passive buzzers.
    // With the current OV2640 PCLK this is about 0.5 s and about 2 kHz.
    localparam [24:0] BEEP_HOLD_CYCLES = 25'd12500000;
    localparam [12:0] BEEP_TONE_HALF_CYCLES = 13'd6250;
    localparam        BEEP_ACTIVE_LEVEL = 1'b1;

    wire manual_rst_n = S0;
    wire sys_clk;
    wire rst_n_sys;
    wire cam_xclk_int;

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
    assign camera_xclk = cam_xclk_int;

    wire ddr3_clk200m;
    wire ddr3_clk_locked;
    clk_wiz_ddr3_200m u_clk_wiz_ddr3_200m (
        .clk_in1 (FPGA_CLK),
        .reset   (~manual_rst_n),
        .clk_out1(ddr3_clk200m),
        .locked  (ddr3_clk_locked)
    );

    wire eth_clk125m;
    wire eth_clk_locked;
    clk_wiz_eth125m u_clk_wiz_eth125m (
        .clk_in1 (FPGA_CLK),
        .reset   (~manual_rst_n),
        .clk_out1(eth_clk125m),
        .locked  (eth_clk_locked)
    );

    reg [19:0] init_wait_cnt;
    reg init_start_pulse;
    reg init_started;
    reg init_done_sticky_sys;
    reg init_error_sticky_sys;
    wire cam_init_busy;
    wire cam_init_done;
    wire cam_init_error;

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

    wire        cap_frame_start;
    wire        cap_frame_end;
    wire        cap_line_start;
    wire        cap_line_end;
    wire        cap_pix_valid;
    wire [7:0]  cap_pix_data;
    wire [10:0] cap_x_cnt;
    wire [10:0] cap_y_cnt;

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

    pulse_sync_toggle u_clear_error_to_cam (
        .src_clk   (eth_clk125m),
        .src_rst_n (manual_rst_n & eth_clk_locked),
        .src_pulse (clear_error_eth_pulse),
        .dst_clk   (camera_pclk),
        .dst_rst_n (rst_n_sys),
        .dst_pulse (clear_error_cam_pulse)
    );

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

    wire        stats_fifo_full;
    wire        stats_wr_en;
    wire [159:0] stats_din;
    wire        stats_fifo_overflow_dbg;
    wire        alarm_active_cam;

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

    pulse_sync_toggle u_wr_frame_done_to_eth (
        .src_clk   (camera_pclk),
        .src_rst_n (manual_rst_n),
        .src_pulse (wr_frame_done_dbg),
        .dst_clk   (eth_clk125m),
        .dst_rst_n (manual_rst_n & eth_clk_locked),
        .dst_pulse (wr_frame_done_eth_pulse)
    );

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

    wire rgmii_rx_clk_phase;
    wire rx_phase_locked;
    eth_phase_mmcm u_eth_phase_mmcm (
        .clk_in1 (rgmii_rx_clk_i),
        .reset   (~manual_rst_n),
        .clk_out1(rgmii_rx_clk_phase),
        .locked  (rx_phase_locked)
    );

    (* ASYNC_REG = "TRUE" *) reg [2:0] rst_rx_sync_ff;
    always @(posedge rgmii_rx_clk_phase or negedge manual_rst_n or negedge rx_phase_locked) begin
        if (!manual_rst_n || !rx_phase_locked) begin
            rst_rx_sync_ff <= 3'b000;
        end else begin
            rst_rx_sync_ff <= {rst_rx_sync_ff[1:0], 1'b1};
        end
    end
    wire rst_rx_n = rst_rx_sync_ff[2];

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

    assign cmd_valid_eth = ~cmd_fifo_empty;
    assign cmd_code_eth  = cmd_fifo_dout[103:96];
    assign cmd_seq_eth   = cmd_fifo_dout[95:80];
    assign cmd_addr_eth  = cmd_fifo_dout[79:64];
    assign cmd_data0_eth = cmd_fifo_dout[63:32];
    assign cmd_data1_eth = cmd_fifo_dout[31:0];

    always @(posedge eth_clk125m or negedge manual_rst_n) begin
        if (!manual_rst_n) begin
            cmd_fifo_rd_en <= 1'b0;
        end else begin
            cmd_fifo_rd_en <= cmd_valid_eth;
        end
    end

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
    assign error_code = init_error_eth ? 16'h0001 :
                        packer_error_eth ? 16'h0002 :
                        wrfifo_full_eth  ? 16'h0003 :
                        stats_overflow_eth ? 16'h0004 :
                        last_cmd_error_eth_cfg ? 16'h0005 : 16'h0000;

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

    vision_udp_status_ctrl u_vision_udp_status_ctrl (
        .clk         (eth_clk125m),
        .rst_n       (manual_rst_n & eth_clk_locked & ddr3_init_done_eth),
        .pkt_valid   (telem_pkt_valid),
        .payload_busy(telem_payload_busy | udp_tx_busy_mux),
        .tx_done     (udp_tx_done & udp_tx_busy_mux & udp_tx_src_sel),
        .send_start  (telem_send_start)
    );

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

    assign eth_reset_n = eth_clk_locked;

    reg preview_packet_seen;
    reg preview_frame_seen;
    reg [25:0] hb_cnt;
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
