`timescale 1ns / 1ps

module edge_ddr3_ctrl_2port (
    input           ddr3_clk200m,
    input           ddr3_rst_n,
    output          ddr3_init_done,
    output          ddr3_mmcm_locked,
    output          ddr3_calib_done,
    output          ddr3_wr_axi_seen,
    output          ddr3_rd_axi_seen,

    input           wrfifo_clr,
    input           wrfifo_clk,
    input           wrfifo_wren,
    input  [15:0]   wrfifo_din,
    output          wrfifo_full,
    output [8:0]    wrfifo_wr_cnt,
    input  [31:0]   wr_ddr_addr_begin,
    input  [31:0]   wr_ddr_addr_end,

    input           rdfifo_clr,
    input           rdfifo_clk,
    input           rdfifo_rden,
    output [15:0]   rdfifo_dout,
    output          rdfifo_empty,
    output [8:0]    rdfifo_rd_cnt,
    input  [31:0]   rd_ddr_addr_begin,
    input  [31:0]   rd_ddr_addr_end,

    output          ui_clk,
    output          ui_rst,

    inout  [31:0]   ddr3_dq,
    inout  [3:0]    ddr3_dqs_n,
    inout  [3:0]    ddr3_dqs_p,
    output [14:0]   ddr3_addr,
    output [2:0]    ddr3_ba,
    output          ddr3_ras_n,
    output          ddr3_cas_n,
    output          ddr3_we_n,
    output          ddr3_reset_n,
    output [0:0]    ddr3_ck_p,
    output [0:0]    ddr3_ck_n,
    output [0:0]    ddr3_cke,
    output [0:0]    ddr3_cs_n,
    output [3:0]    ddr3_dm,
    output [0:0]    ddr3_odt
);

    wire          wrfifo_rden;
    wire [127:0]  wrfifo_dout;
    wire [5:0]    wrfifo_rd_cnt_int;
    wire          wrfifo_empty;
    wire          wrfifo_wr_rst_busy;
    wire          wrfifo_rd_rst_busy;

    wire          rdfifo_wren;
    wire [127:0]  rdfifo_din;
    wire [5:0]    rdfifo_wr_cnt;
    wire          rdfifo_full;
    wire          rdfifo_wr_rst_busy;
    wire          rdfifo_rd_rst_busy;

    wire          ui_clk_sync_rst;
    wire          mmcm_locked;
    wire          init_calib_complete;
    wire          wr_addr_clr_pulse;
    wire          rd_addr_clr_pulse;
    reg           wr_addr_clr_ui;
    reg           rd_addr_clr_ui;

    wire [3:0]    s_axi_awid;
    wire [29:0]   s_axi_awaddr;
    wire [7:0]    s_axi_awlen;
    wire [2:0]    s_axi_awsize;
    wire [1:0]    s_axi_awburst;
    wire [0:0]    s_axi_awlock;
    wire [3:0]    s_axi_awcache;
    wire [2:0]    s_axi_awprot;
    wire [3:0]    s_axi_awqos;
    wire          s_axi_awvalid;
    wire          s_axi_awready;

    wire [127:0]  s_axi_wdata;
    wire [15:0]   s_axi_wstrb;
    wire          s_axi_wlast;
    wire          s_axi_wvalid;
    wire          s_axi_wready;

    wire [3:0]    s_axi_bid;
    wire [1:0]    s_axi_bresp;
    wire          s_axi_bvalid;
    wire          s_axi_bready;

    wire [3:0]    s_axi_arid;
    wire [29:0]   s_axi_araddr;
    wire [7:0]    s_axi_arlen;
    wire [2:0]    s_axi_arsize;
    wire [1:0]    s_axi_arburst;
    wire [0:0]    s_axi_arlock;
    wire [3:0]    s_axi_arcache;
    wire [2:0]    s_axi_arprot;
    wire [3:0]    s_axi_arqos;
    wire          s_axi_arvalid;
    wire          s_axi_arready;

    wire [3:0]    s_axi_rid;
    wire [127:0]  s_axi_rdata;
    wire [1:0]    s_axi_rresp;
    wire          s_axi_rlast;
    wire          s_axi_rvalid;
    wire          s_axi_rready;
    wire [11:0]   device_temp;
    reg           wr_axi_seen_reg;
    reg           rd_axi_seen_reg;

    assign ddr3_init_done = mmcm_locked && init_calib_complete;
    assign ddr3_mmcm_locked = mmcm_locked;
    assign ddr3_calib_done  = init_calib_complete;
    assign ddr3_wr_axi_seen = wr_axi_seen_reg;
    assign ddr3_rd_axi_seen = rd_axi_seen_reg;
    assign ui_rst = ui_clk_sync_rst;
    assign device_temp = 12'h000;

    wr_ddr3_fifo u_wr_ddr3_fifo (
        .rst           (wrfifo_clr),
        .wr_clk        (wrfifo_clk),
        .rd_clk        (ui_clk),
        .din           (wrfifo_din),
        .wr_en         (wrfifo_wren),
        .rd_en         (wrfifo_rden),
        .dout          (wrfifo_dout),
        .full          (wrfifo_full),
        .empty         (wrfifo_empty),
        .rd_data_count (wrfifo_rd_cnt_int),
        .wr_data_count (wrfifo_wr_cnt),
        .wr_rst_busy   (wrfifo_wr_rst_busy),
        .rd_rst_busy   (wrfifo_rd_rst_busy)
    );

    wire [8:0] rdfifo_rd_cnt_int;

    rd_ddr3_fifo u_rd_ddr3_fifo (
        .rst           (rdfifo_clr),
        .wr_clk        (ui_clk),
        .rd_clk        (rdfifo_clk),
        .din           (rdfifo_din),
        .wr_en         (rdfifo_wren),
        .rd_en         (rdfifo_rden),
        .dout          (rdfifo_dout),
        .full          (rdfifo_full),
        .empty         (rdfifo_empty),
        .wr_data_count (rdfifo_wr_cnt),
        .wr_rst_busy   (rdfifo_wr_rst_busy),
        .rd_rst_busy   (rdfifo_rd_rst_busy)
    );

    assign rdfifo_rd_cnt_int = {3'b000, rdfifo_wr_cnt};
    assign rdfifo_rd_cnt     = rdfifo_rd_cnt_int;

    pulse_sync_toggle u_wrfifo_clr_to_ui (
        .src_clk   (wrfifo_clk),
        .src_rst_n (ddr3_rst_n),
        .src_pulse (wrfifo_clr),
        .dst_clk   (ui_clk),
        .dst_rst_n (ddr3_rst_n),
        .dst_pulse (wr_addr_clr_pulse)
    );

    pulse_sync_toggle u_rdfifo_clr_to_ui (
        .src_clk   (rdfifo_clk),
        .src_rst_n (ddr3_rst_n),
        .src_pulse (rdfifo_clr),
        .dst_clk   (ui_clk),
        .dst_rst_n (ddr3_rst_n),
        .dst_pulse (rd_addr_clr_pulse)
    );

    always @(posedge ui_clk or posedge ui_clk_sync_rst) begin
        if (ui_clk_sync_rst) begin
            wr_addr_clr_ui <= 1'b0;
            rd_addr_clr_ui <= 1'b0;
        end else begin
            wr_addr_clr_ui <= wr_addr_clr_pulse;
            rd_addr_clr_ui <= rd_addr_clr_pulse;
        end
    end

    always @(posedge ui_clk or posedge ui_clk_sync_rst) begin
        if (ui_clk_sync_rst) begin
            wr_axi_seen_reg <= 1'b0;
            rd_axi_seen_reg <= 1'b0;
        end else begin
            if ((s_axi_awvalid && s_axi_awready) || (s_axi_wvalid && s_axi_wready)) begin
                wr_axi_seen_reg <= 1'b1;
            end
            if ((s_axi_arvalid && s_axi_arready) || (s_axi_rvalid && s_axi_rready)) begin
                rd_axi_seen_reg <= 1'b1;
            end
        end
    end

    edge_fifo2mig_axi #(
        .AXI_ID  (4'b0000),
        .AXI_LEN (8'd31)
    ) u_edge_fifo2mig_axi (
        .wr_addr_clr         (wr_addr_clr_ui),
        .wr_addr_begin       (wr_ddr_addr_begin),
        .wr_addr_end         (wr_ddr_addr_end),
        .wr_fifo_rdreq       (wrfifo_rden),
        .wr_fifo_rddata      (wrfifo_dout),
        .wr_fifo_empty       (wrfifo_empty),
        .wr_fifo_rd_cnt      (wrfifo_rd_cnt_int),
        .wr_fifo_rst_busy    (wrfifo_wr_rst_busy | wrfifo_rd_rst_busy),
        .rd_addr_clr         (rd_addr_clr_ui),
        .rd_addr_begin       (rd_ddr_addr_begin),
        .rd_addr_end         (rd_ddr_addr_end),
        .rd_fifo_wrreq       (rdfifo_wren),
        .rd_fifo_wrdata      (rdfifo_din),
        .rd_fifo_alfull      (rdfifo_full),
        .rd_fifo_wr_cnt      (rdfifo_wr_cnt),
        .rd_fifo_rst_busy    (rdfifo_wr_rst_busy | rdfifo_rd_rst_busy),
        .ui_clk              (ui_clk),
        .ui_clk_sync_rst     (ui_clk_sync_rst),
        .mmcm_locked         (mmcm_locked),
        .init_calib_complete (init_calib_complete),
        .m_axi_awid          (s_axi_awid),
        .m_axi_awaddr        (s_axi_awaddr),
        .m_axi_awlen         (s_axi_awlen),
        .m_axi_awsize        (s_axi_awsize),
        .m_axi_awburst       (s_axi_awburst),
        .m_axi_awlock        (s_axi_awlock),
        .m_axi_awcache       (s_axi_awcache),
        .m_axi_awprot        (s_axi_awprot),
        .m_axi_awqos         (s_axi_awqos),
        .m_axi_awvalid       (s_axi_awvalid),
        .m_axi_awready       (s_axi_awready),
        .m_axi_wdata         (s_axi_wdata),
        .m_axi_wstrb         (s_axi_wstrb),
        .m_axi_wlast         (s_axi_wlast),
        .m_axi_wvalid        (s_axi_wvalid),
        .m_axi_wready        (s_axi_wready),
        .m_axi_bid           (s_axi_bid),
        .m_axi_bresp         (s_axi_bresp),
        .m_axi_bvalid        (s_axi_bvalid),
        .m_axi_bready        (s_axi_bready),
        .m_axi_arid          (s_axi_arid),
        .m_axi_araddr        (s_axi_araddr),
        .m_axi_arlen         (s_axi_arlen),
        .m_axi_arsize        (s_axi_arsize),
        .m_axi_arburst       (s_axi_arburst),
        .m_axi_arlock        (s_axi_arlock),
        .m_axi_arcache       (s_axi_arcache),
        .m_axi_arprot        (s_axi_arprot),
        .m_axi_arqos         (s_axi_arqos),
        .m_axi_arvalid       (s_axi_arvalid),
        .m_axi_arready       (s_axi_arready),
        .m_axi_rid           (s_axi_rid),
        .m_axi_rdata         (s_axi_rdata),
        .m_axi_rresp         (s_axi_rresp),
        .m_axi_rlast         (s_axi_rlast),
        .m_axi_rvalid        (s_axi_rvalid),
        .m_axi_rready        (s_axi_rready)
    );

    mig_7series_0 u_mig_7series_0 (
        .ddr3_addr           (ddr3_addr),
        .ddr3_ba             (ddr3_ba),
        .ddr3_cas_n          (ddr3_cas_n),
        .ddr3_ck_n           (ddr3_ck_n),
        .ddr3_ck_p           (ddr3_ck_p),
        .ddr3_cke            (ddr3_cke),
        .ddr3_ras_n          (ddr3_ras_n),
        .ddr3_reset_n        (ddr3_reset_n),
        .ddr3_we_n           (ddr3_we_n),
        .ddr3_dq             (ddr3_dq),
        .ddr3_dqs_n          (ddr3_dqs_n),
        .ddr3_dqs_p          (ddr3_dqs_p),
        .init_calib_complete (init_calib_complete),
        .ddr3_cs_n           (ddr3_cs_n),
        .ddr3_dm             (ddr3_dm),
        .ddr3_odt            (ddr3_odt),
        .ui_clk              (ui_clk),
        .ui_clk_sync_rst     (ui_clk_sync_rst),
        .mmcm_locked         (mmcm_locked),
        .aresetn             (ddr3_rst_n),
        .app_sr_req          (1'b0),
        .app_ref_req         (1'b0),
        .app_zq_req          (1'b0),
        .app_sr_active       (),
        .app_ref_ack         (),
        .app_zq_ack          (),
        .s_axi_awid          (s_axi_awid),
        .s_axi_awaddr        (s_axi_awaddr),
        .s_axi_awlen         (s_axi_awlen),
        .s_axi_awsize        (s_axi_awsize),
        .s_axi_awburst       (s_axi_awburst),
        .s_axi_awlock        (s_axi_awlock),
        .s_axi_awcache       (s_axi_awcache),
        .s_axi_awprot        (s_axi_awprot),
        .s_axi_awqos         (s_axi_awqos),
        .s_axi_awvalid       (s_axi_awvalid),
        .s_axi_awready       (s_axi_awready),
        .s_axi_wdata         (s_axi_wdata),
        .s_axi_wstrb         (s_axi_wstrb),
        .s_axi_wlast         (s_axi_wlast),
        .s_axi_wvalid        (s_axi_wvalid),
        .s_axi_wready        (s_axi_wready),
        .s_axi_bid           (s_axi_bid),
        .s_axi_bresp         (s_axi_bresp),
        .s_axi_bvalid        (s_axi_bvalid),
        .s_axi_bready        (s_axi_bready),
        .s_axi_arid          (s_axi_arid),
        .s_axi_araddr        (s_axi_araddr),
        .s_axi_arlen         (s_axi_arlen),
        .s_axi_arsize        (s_axi_arsize),
        .s_axi_arburst       (s_axi_arburst),
        .s_axi_arlock        (s_axi_arlock),
        .s_axi_arcache       (s_axi_arcache),
        .s_axi_arprot        (s_axi_arprot),
        .s_axi_arqos         (s_axi_arqos),
        .s_axi_arvalid       (s_axi_arvalid),
        .s_axi_arready       (s_axi_arready),
        .s_axi_rid           (s_axi_rid),
        .s_axi_rdata         (s_axi_rdata),
        .s_axi_rresp         (s_axi_rresp),
        .s_axi_rlast         (s_axi_rlast),
        .s_axi_rvalid        (s_axi_rvalid),
        .s_axi_rready        (s_axi_rready),
        .device_temp         (device_temp),
        .sys_clk_i           (ddr3_clk200m),
        // MIG was configured with ACTIVE LOW system reset, so feed the
        // deasserted-high reset_n signal directly instead of inverting it.
        .sys_rst             (ddr3_rst_n)
    );

endmodule
