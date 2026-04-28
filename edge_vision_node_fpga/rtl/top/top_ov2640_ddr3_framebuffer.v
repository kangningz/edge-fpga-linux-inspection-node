`timescale 1ns / 1ps

module top_ov2640_ddr3_framebuffer (
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

    output wire       UART_TXD,
    output reg        LED0,
    output reg        LED1,
    output reg        LED2,
    output reg        LED3,
    output reg        LED4,
    output reg        LED5,
    output reg        LED6,
    output reg        LED7,
    output wire       BEEP
);

    localparam integer FRAME_WIDTH  = 800;
    localparam integer FRAME_HEIGHT = 600;
    localparam integer FRAME_BYTES  = FRAME_WIDTH * FRAME_HEIGHT * 2;
    localparam integer INIT_WAIT_CYCLES = 1_000_000;

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
        .rst_n       (rst_n_sys),
        .camera_pclk (camera_pclk),
        .camera_vsync(camera_vsync),
        .camera_href (camera_href),
        .camera_d    (camera_d),
        .frame_start (cap_frame_start),
        .frame_end   (cap_frame_end),
        .line_start  (cap_line_start),
        .line_end    (cap_line_end),
        .pix_valid   (cap_pix_valid),
        .pix_data    (cap_pix_data),
        .x_cnt       (cap_x_cnt),
        .y_cnt       (cap_y_cnt)
    );

    wire [15:0] frame_cnt_dbg;
    wire [15:0] line_cnt_last_dbg;
    wire [31:0] pixel_cnt_last_dbg;
    wire frame_locked_dbg;
    frame_sync_counter u_frame_sync_counter (
        .rst_n         (rst_n_sys),
        .camera_pclk   (camera_pclk),
        .frame_start   (cap_frame_start),
        .frame_end     (cap_frame_end),
        .line_start    (cap_line_start),
        .line_end      (cap_line_end),
        .pix_valid     (cap_pix_valid),
        .frame_cnt     (frame_cnt_dbg),
        .line_cnt_last (line_cnt_last_dbg),
        .pixel_cnt_last(pixel_cnt_last_dbg),
        .frame_locked  (frame_locked_dbg)
    );

    reg capture_enable_sys;
    always @(posedge sys_clk or negedge rst_n_sys) begin
        if (!rst_n_sys) begin
            capture_enable_sys <= 1'b0;
        end else if (cam_init_done && ddr3_init_done) begin
            capture_enable_sys <= 1'b1;
        end
    end

    wire [15:0] rd_pixel;
    wire rd_empty;
    wire [8:0] rd_count;
    wire ddr3_init_done;
    wire ddr3_clk_locked_dbg;
    wire ddr3_mmcm_locked_dbg;
    wire ddr3_calib_done_dbg;
    wire ddr3_wr_axi_seen_dbg;
    wire ddr3_rd_axi_seen_dbg;
    wire wr_frame_done_dbg;
    wire rd_frame_done_dbg;
    wire ui_clk;
    wire ui_rst;
    wire frame_start_16_dbg;
    wire frame_end_16_dbg;
    wire packer_error_dbg;
    wire wrfifo_full_dbg;

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
        .rd_clk            (sys_clk),
        .rd_frame_restart  (1'b0),
        .rd_en             (capture_enable_sys & ddr3_init_done & ~rd_empty),
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

    assign ddr3_clk_locked_dbg = ddr3_clk_locked;

    reg rd_seen;
    always @(posedge sys_clk or negedge rst_n_sys) begin
        if (!rst_n_sys) begin
            rd_seen <= 1'b0;
        end else if (capture_enable_sys && ddr3_init_done && !rd_empty) begin
            rd_seen <= 1'b1;
        end
    end

    reg [25:0] hb_cnt;
    always @(posedge sys_clk or negedge rst_n_sys) begin
        if (!rst_n_sys) begin
            hb_cnt <= 26'd0;
            LED0   <= 1'b0;
            LED1   <= 1'b0;
            LED2   <= 1'b0;
            LED3   <= 1'b0;
            LED4   <= 1'b0;
            LED5   <= 1'b0;
            LED6   <= 1'b0;
            LED7   <= 1'b0;
        end else begin
            hb_cnt <= hb_cnt + 1'b1;
            LED0   <= hb_cnt[25];
            LED1   <= init_done_sticky_sys;
            LED2   <= ddr3_clk_locked_dbg;
            LED3   <= ddr3_mmcm_locked_dbg;
            LED4   <= frame_locked_dbg;
            LED5   <= ddr3_calib_done_dbg;
            LED6   <= wr_frame_done_dbg;
            LED7   <= rd_frame_done_dbg;
        end
    end

    assign UART_TXD = 1'b1;
    assign BEEP     = 1'b0;

endmodule
