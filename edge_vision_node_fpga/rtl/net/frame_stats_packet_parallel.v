`timescale 1ns / 1ps
// 并行输入的帧统计包构建模块。
// 当各统计字段已经并行可用时，直接生成 32 字节遥测载荷。

module frame_stats_packet_parallel (
    input  wire        clk,
    input  wire        rst_n,

    input  wire [15:0] status_bits,
    input  wire [15:0] error_code,

    input  wire [159:0] stats_dout,
    input  wire         stats_empty,
    output reg          stats_rd_en,

    output reg  [255:0] pkt_data_256,
    output reg          pkt_valid,
    input  wire         pkt_accept

// 端口列表到此结束，下面进入内部寄存器、组合连线和时序逻辑。
);

    integer i;

    // reg 信号保存跨周期状态、计数器、握手标志和流水线寄存结果。
    reg [7:0] b [0:31];
    reg [7:0] checksum_tmp;

    reg [15:0] frame_id_r;
    reg [31:0] timestamp_r;
    reg [15:0] frame_width_r;
    reg [15:0] frame_height_r;
    reg [31:0] active_cnt_r;
    reg [31:0] roi_sum_r;
    reg [15:0] bright_cnt_r;

    // 时序逻辑：在指定时钟沿更新状态，并在复位时恢复到安全初值。
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            stats_rd_en   <= 1'b0;
            pkt_data_256  <= 256'd0;
            pkt_valid     <= 1'b0;
        end else begin
            stats_rd_en <= 1'b0;

            if (pkt_valid) begin
                if (pkt_accept)
                    pkt_valid <= 1'b0;
            end else begin
                if (!stats_empty) begin
                    frame_id_r     = stats_dout[159:144];
                    timestamp_r    = stats_dout[143:112];
                    frame_width_r  = stats_dout[111:96];
                    frame_height_r = stats_dout[95:80];
                    active_cnt_r   = stats_dout[79:48];
                    roi_sum_r      = stats_dout[47:16];
                    bright_cnt_r   = stats_dout[15:0];

                    b[0]  = 8'h45;
                    b[1]  = 8'h56;
                    b[2]  = 8'h01;
                    b[3]  = 8'h01;

                    b[4]  = frame_id_r[15:8];
                    b[5]  = frame_id_r[7:0];

                    b[6]  = status_bits[15:8];
                    b[7]  = status_bits[7:0];

                    b[8]  = timestamp_r[31:24];
                    b[9]  = timestamp_r[23:16];
                    b[10] = timestamp_r[15:8];
                    b[11] = timestamp_r[7:0];

                    b[12] = frame_width_r[15:8];
                    b[13] = frame_width_r[7:0];

                    b[14] = frame_height_r[15:8];
                    b[15] = frame_height_r[7:0];

                    b[16] = active_cnt_r[31:24];
                    b[17] = active_cnt_r[23:16];
                    b[18] = active_cnt_r[15:8];
                    b[19] = active_cnt_r[7:0];

                    b[20] = roi_sum_r[31:24];
                    b[21] = roi_sum_r[23:16];
                    b[22] = roi_sum_r[15:8];
                    b[23] = roi_sum_r[7:0];

                    b[24] = bright_cnt_r[15:8];
                    b[25] = bright_cnt_r[7:0];

                    b[26] = error_code[15:8];
                    b[27] = error_code[7:0];

                    b[28] = 8'h00;
                    b[29] = 8'h00;
                    b[30] = 8'h00;

                    checksum_tmp = 8'h00;
                    for (i = 0; i < 31; i = i + 1)
                        checksum_tmp = checksum_tmp ^ b[i];

                    b[31] = checksum_tmp;

                    for (i = 0; i < 32; i = i + 1)
                        pkt_data_256[i*8 +: 8] <= b[i];

                    stats_rd_en <= 1'b1;
                    pkt_valid   <= 1'b1;
                end
            end
        end
    end

endmodule
