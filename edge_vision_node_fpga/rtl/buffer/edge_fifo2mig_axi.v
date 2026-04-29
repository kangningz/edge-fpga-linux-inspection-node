`timescale 1ns / 1ps
// FIFO 到 MIG AXI 写通道桥接模块。
// 它把连续像素数据整理成 AXI 写突发，处理地址推进、写响应和背压。

module edge_fifo2mig_axi #(

    // 参数用于适配不同图像尺寸、时钟频率、缓冲深度或网络地址。
    parameter AXI_ID  = 4'b0000,

    // 参数用于适配不同图像尺寸、时钟频率、缓冲深度或网络地址。
    parameter AXI_LEN = 8'd31
)(
    input               wr_addr_clr,
    input     [31:0]    wr_addr_begin,
    input     [31:0]    wr_addr_end,
    output              wr_fifo_rdreq,
    input     [127:0]   wr_fifo_rddata,
    input               wr_fifo_empty,
    input     [5:0]     wr_fifo_rd_cnt,
    input               wr_fifo_rst_busy,

    input               rd_addr_clr,
    input     [31:0]    rd_addr_begin,
    input     [31:0]    rd_addr_end,
    output              rd_fifo_wrreq,
    output    [127:0]   rd_fifo_wrdata,
    input               rd_fifo_alfull,
    input     [5:0]     rd_fifo_wr_cnt,
    input               rd_fifo_rst_busy,

    input               ui_clk,
    input               ui_clk_sync_rst,
    input               mmcm_locked,
    input               init_calib_complete,

    output    [3:0]     m_axi_awid,
    output reg [29:0]   m_axi_awaddr,
    output    [7:0]     m_axi_awlen,
    output    [2:0]     m_axi_awsize,
    output    [1:0]     m_axi_awburst,
    output    [0:0]     m_axi_awlock,
    output    [3:0]     m_axi_awcache,
    output    [2:0]     m_axi_awprot,
    output    [3:0]     m_axi_awqos,
    output reg          m_axi_awvalid,
    input               m_axi_awready,

    output    [127:0]   m_axi_wdata,
    output    [15:0]    m_axi_wstrb,
    output reg          m_axi_wlast,
    output reg          m_axi_wvalid,
    input               m_axi_wready,

    input     [3:0]     m_axi_bid,
    input     [1:0]     m_axi_bresp,
    input               m_axi_bvalid,
    output              m_axi_bready,

    output    [3:0]     m_axi_arid,
    output reg [29:0]   m_axi_araddr,
    output    [7:0]     m_axi_arlen,
    output    [2:0]     m_axi_arsize,
    output    [1:0]     m_axi_arburst,
    output    [0:0]     m_axi_arlock,
    output    [3:0]     m_axi_arcache,
    output    [2:0]     m_axi_arprot,
    output    [3:0]     m_axi_arqos,
    output reg          m_axi_arvalid,
    input               m_axi_arready,

    input     [3:0]     m_axi_rid,
    input     [127:0]   m_axi_rdata,
    input     [1:0]     m_axi_rresp,
    input               m_axi_rlast,
    input               m_axi_rvalid,
    output              m_axi_rready

// 端口列表到此结束，下面进入内部寄存器、组合连线和时序逻辑。
);

    // 本地常量定义状态编码、计数上限或协议字段，避免魔法数字散落在逻辑中。
    localparam S_IDLE    = 7'b0000001;
    localparam S_ARB     = 7'b0000010;
    localparam S_WR_ADDR = 7'b0000100;
    localparam S_WR_DATA = 7'b0001000;
    localparam S_WR_RESP = 7'b0010000;
    localparam S_RD_ADDR = 7'b0100000;
    localparam S_RD_RESP = 7'b1000000;

    // wire 信号承载组合逻辑结果或子模块之间的连接。
    wire [5:0] burst_beats       = AXI_LEN[5:0] + 6'd1;
    wire [5:0] wr_req_cnt_thresh = burst_beats;
    wire [5:0] rd_req_cnt_thresh = burst_beats;
    (* ASYNC_REG = "TRUE" *) reg wr_fifo_rst_busy_ff0;
    (* ASYNC_REG = "TRUE" *) reg wr_fifo_rst_busy_ff1;

    // reg 信号保存跨周期状态、计数器、握手标志和流水线寄存结果。
    reg wr_fifo_rst_busy_ui;
    (* ASYNC_REG = "TRUE" *) reg rd_fifo_rst_busy_ff0;
    (* ASYNC_REG = "TRUE" *) reg rd_fifo_rst_busy_ff1;
    reg rd_fifo_rst_busy_ui;

    wire wr_ddr3_req = (wr_fifo_rst_busy_ui == 1'b0) && (wr_fifo_rd_cnt >= wr_req_cnt_thresh);
    wire rd_ddr3_req = (rd_fifo_rst_busy_ui == 1'b0) && (rd_fifo_wr_cnt <= rd_req_cnt_thresh);

    reg [6:0] curr_state;
    reg [6:0] next_state;
    reg       wr_rd_poll;
    reg [7:0] wr_data_cnt;

    // 连续赋值用于输出固定映射、组合判断或协议字段拼接。
    assign m_axi_awid    = AXI_ID;

    // 连续赋值用于输出固定映射、组合判断或协议字段拼接。
    assign m_axi_awsize  = 3'b100;
    assign m_axi_awburst = 2'b01;
    assign m_axi_awlock  = 1'b0;
    assign m_axi_awcache = 4'b0000;
    assign m_axi_awprot  = 3'b000;
    assign m_axi_awqos   = 4'b0000;
    assign m_axi_awlen   = AXI_LEN;

    assign m_axi_wdata   = wr_fifo_rddata;
    assign m_axi_wstrb   = 16'hffff;
    assign m_axi_bready  = 1'b1;

    assign m_axi_arid    = AXI_ID;
    assign m_axi_arsize  = 3'b100;
    assign m_axi_arburst = 2'b01;
    assign m_axi_arlock  = 1'b0;
    assign m_axi_arcache = 4'b0000;
    assign m_axi_arprot  = 3'b000;
    assign m_axi_arqos   = 4'b0000;
    assign m_axi_arlen   = AXI_LEN;
    assign m_axi_rready  = ~rd_fifo_alfull;

    assign wr_fifo_rdreq  = m_axi_wvalid && m_axi_wready;
    assign rd_fifo_wrreq  = m_axi_rvalid && m_axi_rready;
    assign rd_fifo_wrdata = m_axi_rdata;

    // 时序逻辑：在指定时钟沿更新状态，并在复位时恢复到安全初值。
    always @(posedge ui_clk or posedge ui_clk_sync_rst) begin
        if (ui_clk_sync_rst) begin
            wr_fifo_rst_busy_ff0 <= 1'b1;
            wr_fifo_rst_busy_ff1 <= 1'b1;
            wr_fifo_rst_busy_ui  <= 1'b1;
            rd_fifo_rst_busy_ff0 <= 1'b1;
            rd_fifo_rst_busy_ff1 <= 1'b1;
            rd_fifo_rst_busy_ui  <= 1'b1;
        end else begin
            wr_fifo_rst_busy_ff0 <= wr_fifo_rst_busy;
            wr_fifo_rst_busy_ff1 <= wr_fifo_rst_busy_ff0;
            wr_fifo_rst_busy_ui  <= wr_fifo_rst_busy_ff1;
            rd_fifo_rst_busy_ff0 <= rd_fifo_rst_busy;
            rd_fifo_rst_busy_ff1 <= rd_fifo_rst_busy_ff0;
            rd_fifo_rst_busy_ui  <= rd_fifo_rst_busy_ff1;
        end
    end

    // 时序逻辑：在指定时钟沿更新状态，并在复位时恢复到安全初值。
    always @(posedge ui_clk or posedge ui_clk_sync_rst) begin
        if (ui_clk_sync_rst) begin
            m_axi_awaddr <= wr_addr_begin[29:0];
        end else if (wr_addr_clr) begin
            m_axi_awaddr <= wr_addr_begin[29:0];
        end else if (m_axi_awaddr >= wr_addr_end[29:0]) begin
            m_axi_awaddr <= wr_addr_begin[29:0];
        end else if ((curr_state == S_WR_RESP) && m_axi_bready && m_axi_bvalid &&
                     (m_axi_bresp == 2'b00) && (m_axi_bid == AXI_ID)) begin
            m_axi_awaddr <= m_axi_awaddr + ((m_axi_awlen + 1'b1) << 4);
        end
    end

    // 时序逻辑：在指定时钟沿更新状态，并在复位时恢复到安全初值。
    always @(posedge ui_clk or posedge ui_clk_sync_rst) begin
        if (ui_clk_sync_rst) begin
            m_axi_awvalid <= 1'b0;
        end else if ((curr_state == S_WR_ADDR) && m_axi_awready && m_axi_awvalid) begin
            m_axi_awvalid <= 1'b0;
        end else if (curr_state == S_WR_ADDR) begin
            m_axi_awvalid <= 1'b1;
        end
    end

    // 时序逻辑：在指定时钟沿更新状态，并在复位时恢复到安全初值。
    always @(posedge ui_clk or posedge ui_clk_sync_rst) begin
        if (ui_clk_sync_rst) begin
            m_axi_wvalid <= 1'b0;
        end else if ((curr_state == S_WR_DATA) && m_axi_wready && m_axi_wvalid && m_axi_wlast) begin
            m_axi_wvalid <= 1'b0;
        end else if (curr_state == S_WR_DATA) begin

            m_axi_wvalid <= ~wr_fifo_empty;
        end else begin
            m_axi_wvalid <= 1'b0;
        end
    end

    // 时序逻辑：在指定时钟沿更新状态，并在复位时恢复到安全初值。
    always @(posedge ui_clk or posedge ui_clk_sync_rst) begin
        if (ui_clk_sync_rst) begin
            wr_data_cnt <= 8'd0;
        end else if (curr_state == S_ARB) begin
            wr_data_cnt <= 8'd0;
        end else if (curr_state == S_WR_DATA && m_axi_wready && m_axi_wvalid) begin
            wr_data_cnt <= wr_data_cnt + 1'b1;
        end
    end

    // 时序逻辑：在指定时钟沿更新状态，并在复位时恢复到安全初值。
    always @(posedge ui_clk or posedge ui_clk_sync_rst) begin
        if (ui_clk_sync_rst) begin
            m_axi_wlast <= 1'b0;
        end else if (curr_state == S_WR_DATA && m_axi_wready && m_axi_wvalid && m_axi_wlast) begin
            m_axi_wlast <= 1'b0;
        end else if (curr_state == S_WR_DATA && m_axi_awlen == 8'd0) begin
            m_axi_wlast <= 1'b1;
        end else if (curr_state == S_WR_DATA && m_axi_wready && m_axi_wvalid &&
                     (wr_data_cnt == m_axi_awlen - 1'b1)) begin
            m_axi_wlast <= 1'b1;
        end
    end

    // 时序逻辑：在指定时钟沿更新状态，并在复位时恢复到安全初值。
    always @(posedge ui_clk or posedge ui_clk_sync_rst) begin
        if (ui_clk_sync_rst) begin
            m_axi_araddr <= rd_addr_begin[29:0];
        end else if (rd_addr_clr) begin
            m_axi_araddr <= rd_addr_begin[29:0];
        end else if (m_axi_araddr >= rd_addr_end[29:0]) begin
            m_axi_araddr <= rd_addr_begin[29:0];
        end else if ((curr_state == S_RD_RESP) && m_axi_rready && m_axi_rvalid &&
                     m_axi_rlast && (m_axi_rresp == 2'b00) && (m_axi_rid == AXI_ID)) begin
            m_axi_araddr <= m_axi_araddr + ((m_axi_awlen + 1'b1) << 4);
        end
    end

    // 时序逻辑：在指定时钟沿更新状态，并在复位时恢复到安全初值。
    always @(posedge ui_clk or posedge ui_clk_sync_rst) begin
        if (ui_clk_sync_rst) begin
            m_axi_arvalid <= 1'b0;
        end else if ((curr_state == S_RD_ADDR) && m_axi_arready && m_axi_arvalid) begin
            m_axi_arvalid <= 1'b0;
        end else if (curr_state == S_RD_ADDR) begin
            m_axi_arvalid <= 1'b1;
        end
    end

    // 时序逻辑：在指定时钟沿更新状态，并在复位时恢复到安全初值。
    always @(posedge ui_clk or posedge ui_clk_sync_rst) begin
        if (ui_clk_sync_rst) begin
            wr_rd_poll <= 1'b0;
        end else if (curr_state == S_ARB) begin

            wr_rd_poll <= ~wr_rd_poll;
        end
    end

    // 时序逻辑：在指定时钟沿更新状态，并在复位时恢复到安全初值。
    always @(posedge ui_clk or posedge ui_clk_sync_rst) begin
        if (ui_clk_sync_rst) begin
            curr_state <= S_IDLE;
        end else begin
            curr_state <= next_state;
        end
    end

    // 组合逻辑：根据当前状态和输入信号计算下一拍控制结果。
    always @(*) begin

            // 状态机分支：按当前阶段执行握手、计数或数据搬运动作。
        case (curr_state)
            S_IDLE:    next_state = (mmcm_locked && init_calib_complete) ? S_ARB : S_IDLE;
            S_ARB:     next_state = (wr_ddr3_req && !wr_rd_poll) ? S_WR_ADDR :
                                    (rd_ddr3_req &&  wr_rd_poll) ? S_RD_ADDR : S_ARB;
            S_WR_ADDR: next_state = (m_axi_awready && m_axi_awvalid) ? S_WR_DATA : S_WR_ADDR;
            S_WR_DATA: next_state = (m_axi_wready  && m_axi_wvalid  && m_axi_wlast) ? S_WR_RESP : S_WR_DATA;
            S_WR_RESP: next_state = (m_axi_bready  && m_axi_bvalid  && (m_axi_bresp == 2'b00) && (m_axi_bid == AXI_ID)) ? S_ARB :
                                    (m_axi_bready  && m_axi_bvalid) ? S_IDLE : S_WR_RESP;
            S_RD_ADDR: next_state = (m_axi_arready && m_axi_arvalid) ? S_RD_RESP : S_RD_ADDR;
            S_RD_RESP: next_state = (m_axi_rready  && m_axi_rvalid  && m_axi_rlast && (m_axi_rresp == 2'b00) && (m_axi_rid == AXI_ID)) ? S_ARB :
                                    (m_axi_rready  && m_axi_rvalid  && m_axi_rlast) ? S_IDLE : S_RD_RESP;
            default:   next_state = S_IDLE;

            // 状态机分支结束，未命中的情况由默认分支回到安全状态。
        endcase
    end

endmodule
