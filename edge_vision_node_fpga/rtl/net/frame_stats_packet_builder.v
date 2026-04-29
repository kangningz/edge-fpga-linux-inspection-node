`timescale 1ns / 1ps
// 帧统计遥测包构建模块。
// 把统计 FIFO 中的帧信息和状态位打包为固定 32 字节 UDP 状态载荷。

module frame_stats_packet_builder (
    input  wire        clk,
    input  wire        rst_n,

    input  wire [15:0] status_bits,
    input  wire [15:0] error_code,

    input  wire [159:0] stats_dout,
    input  wire         stats_empty,
    output reg          stats_rd_en,

    output wire         tx_valid,
    output wire [7:0]   tx_data,
    output wire         tx_last,
    input  wire         tx_ready,

    output wire         pkt_busy

// 端口列表到此结束，下面进入内部寄存器、组合连线和时序逻辑。
);

    // reg 信号保存跨周期状态、计数器、握手标志和流水线寄存结果。
    reg sending;
    reg [5:0] pkt_idx;
    reg [7:0] packet_mem [0:31];

    integer i;
    reg [7:0] checksum_tmp;

    reg [15:0] frame_id_r;
    reg [31:0] timestamp_r;
    reg [15:0] frame_width_r;
    reg [15:0] frame_height_r;
    reg [31:0] active_cnt_r;
    reg [31:0] roi_sum_r;
    reg [15:0] bright_cnt_r;

    // 连续赋值用于输出固定映射、组合判断或协议字段拼接。
    assign tx_valid = sending;

    // 连续赋值用于输出固定映射、组合判断或协议字段拼接。
    assign tx_data  = packet_mem[pkt_idx];
    assign tx_last  = sending && (pkt_idx == 6'd31);
    assign pkt_busy = sending;

    // 时序逻辑：在指定时钟沿更新状态，并在复位时恢复到安全初值。
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            sending    <= 1'b0;
            pkt_idx    <= 6'd0;
            stats_rd_en <= 1'b0;

            for (i = 0; i < 32; i = i + 1)
                packet_mem[i] <= 8'd0;
        end else begin
            stats_rd_en <= 1'b0;

            if (!sending) begin
                if (!stats_empty) begin
                    frame_id_r     = stats_dout[159:144];
                    timestamp_r    = stats_dout[143:112];
                    frame_width_r  = stats_dout[111:96];
                    frame_height_r = stats_dout[95:80];
                    active_cnt_r   = stats_dout[79:48];
                    roi_sum_r      = stats_dout[47:16];
                    bright_cnt_r   = stats_dout[15:0];

                    packet_mem[0]  = 8'h45;
                    packet_mem[1]  = 8'h56;
                    packet_mem[2]  = 8'h01;
                    packet_mem[3]  = 8'h01;

                    packet_mem[4]  = frame_id_r[15:8];
                    packet_mem[5]  = frame_id_r[7:0];

                    packet_mem[6]  = status_bits[15:8];
                    packet_mem[7]  = status_bits[7:0];

                    packet_mem[8]  = timestamp_r[31:24];
                    packet_mem[9]  = timestamp_r[23:16];
                    packet_mem[10] = timestamp_r[15:8];
                    packet_mem[11] = timestamp_r[7:0];

                    packet_mem[12] = frame_width_r[15:8];
                    packet_mem[13] = frame_width_r[7:0];

                    packet_mem[14] = frame_height_r[15:8];
                    packet_mem[15] = frame_height_r[7:0];

                    packet_mem[16] = active_cnt_r[31:24];
                    packet_mem[17] = active_cnt_r[23:16];
                    packet_mem[18] = active_cnt_r[15:8];
                    packet_mem[19] = active_cnt_r[7:0];

                    packet_mem[20] = roi_sum_r[31:24];
                    packet_mem[21] = roi_sum_r[23:16];
                    packet_mem[22] = roi_sum_r[15:8];
                    packet_mem[23] = roi_sum_r[7:0];

                    packet_mem[24] = bright_cnt_r[15:8];
                    packet_mem[25] = bright_cnt_r[7:0];

                    packet_mem[26] = error_code[15:8];
                    packet_mem[27] = error_code[7:0];

                    packet_mem[28] = 8'h00;
                    packet_mem[29] = 8'h00;
                    packet_mem[30] = 8'h00;

                    checksum_tmp = 8'h00;
                    for (i = 0; i < 31; i = i + 1)
                        checksum_tmp = checksum_tmp ^ packet_mem[i];

                    packet_mem[31] = checksum_tmp;

                    stats_rd_en <= 1'b1;
                    sending     <= 1'b1;
                    pkt_idx     <= 6'd0;
                end
            end else begin
                if (tx_ready) begin
                    if (pkt_idx == 6'd31) begin
                        sending <= 1'b0;
                        pkt_idx <= 6'd0;
                    end else begin
                        pkt_idx <= pkt_idx + 1'b1;
                    end
                end
            end
        end
    end

endmodule
