`timescale 1ns / 1ps
// RGB565 预览 UDP 载荷生成器。
//
// 该模块不直接发送以太网帧，只生成 UDP payload：
//   1. frame_ready 到来后，从 DDR3 读侧接口重新读取最近完成的一帧。
//   2. 将一帧数据切成多个 UDP payload，每片最多 CHUNK_DATA_BYTES 字节图像数据。
//   3. 每片 payload 前 16 字节是预览分片头，后面是 4 字节图像元信息 + RGB565 像素流的一段。
//
// 输出给 eth_udp_tx_gmii 的接口是拉取式：
//   tx_en_pulse 启动一次 UDP 发送；
//   UDP 发送器每拉高 payload_req 一次，本模块在 payload_dat 给出当前字节。

module rgb565_udp_preview_payload_gen #(

    parameter integer FRAME_WIDTH        = 800,
    parameter integer FRAME_HEIGHT       = 600,

    // 每个 UDP 分片承载的“数据区”最大长度，不含 16 字节分片头。
    // 这里通常选 1400 左右，避开以太网 MTU 限制。
    parameter integer CHUNK_DATA_BYTES   = 1024,

    // 预览消息类型字段，Linux 侧据此区分不同 payload。
    parameter [7:0]   PREVIEW_MSG_TYPE   = 8'h12
)(
    input  wire       clk,
    input  wire       rst_n,

    input  wire       frame_ready,
    input  wire       tx_busy,

    output reg        rd_frame_restart,
    output reg        rd_en,
    input  wire [15:0] rd_pixel,
    input  wire       rd_empty,

    output reg        tx_en_pulse,
    input  wire       tx_done,
    input  wire       payload_req,
    output wire [15:0] data_length,
    output wire [7:0] payload_dat,

    output reg [15:0] preview_frame_id,
    output reg        preview_packet_done,
    output reg        preview_frame_done

// 端口列表到此结束，下面进入内部寄存器、组合连线和时序逻辑。
);

    // 逻辑上的完整预览流长度：
    //   前 4 字节：图像宽高，便于接收端自描述解析。
    //   后续字节：FRAME_WIDTH * FRAME_HEIGHT 个 RGB565 像素，每个像素 2 字节。
    localparam integer STREAM_TOTAL_BYTES = 4 + FRAME_WIDTH * FRAME_HEIGHT * 2;

    // payload_mem 保存“16 字节分片头 + 当前分片数据区”。
    localparam integer PAYLOAD_MAX_BYTES  = 16 + CHUNK_DATA_BYTES;

    // 状态机：
    //   IDLE    等待一帧写入完成
    //   RESTART 通知 DDR3 读侧从帧首重新开始
    //   PREPARE 计算当前分片长度并写入分片头
    //   FILL    从 DDR3 拉像素并填充 payload_mem
    //   LAUNCH  请求 UDP TX 发送
    //   WAIT_TX 等待本片发送完成，决定继续下一片或结束本帧
    localparam [2:0] S_IDLE      = 3'd0;
    localparam [2:0] S_RESTART   = 3'd1;
    localparam [2:0] S_PREPARE   = 3'd2;
    localparam [2:0] S_FILL      = 3'd3;
    localparam [2:0] S_LAUNCH    = 3'd4;
    localparam [2:0] S_WAIT_TX   = 3'd5;

    reg [2:0]  state;
    reg [15:0] chunk_id;

    // frame_offset 指向逻辑预览流中的当前位置，包含最前面的 4 字节宽高元信息。
    reg [31:0] frame_offset;
    reg [15:0] chunk_data_len;
    reg [15:0] payload_total_len;

    // fill_idx 用于填 payload_mem；send_idx 用于响应 payload_req 输出 payload 字节。
    reg [15:0] payload_fill_idx;
    reg [15:0] payload_send_idx;

    // DDR3 读接口一次给 16bit 像素，而 UDP payload 一次输出 8bit；
    // low_byte_pending/rd_pending 用来把一个像素拆成两个连续字节。
    reg [15:0] pixel_hold;
    reg        low_byte_pending;
    reg        rd_pending;
    reg        frame_pending;

    reg [7:0] payload_mem [0:PAYLOAD_MAX_BYTES-1];

    integer i;
    reg [31:0] stream_pos;
    reg [31:0] remaining_stream;
    reg [15:0] chunk_size_calc;

    function [15:0] min16;
        input [31:0] a;
        input [31:0] b;
        begin
            if (a < b) begin
                min16 = a[15:0];
            end else begin
                min16 = b[15:0];
            end
        end
    endfunction

    function [7:0] meta_byte_at;
        input [1:0] idx;
        begin

            case (idx)
                2'd0: meta_byte_at = FRAME_WIDTH[15:8];
                2'd1: meta_byte_at = FRAME_WIDTH[7:0];
                2'd2: meta_byte_at = FRAME_HEIGHT[15:8];
                default: meta_byte_at = FRAME_HEIGHT[7:0];
            endcase
        end
    endfunction

    // 当前待发送 UDP payload 长度。
    assign data_length = payload_total_len;

    // UDP 发送器拉取字节时，send_idx 指向当前 payload_mem 字节。
    assign payload_dat = payload_mem[payload_send_idx];

    // 主状态机。所有输出脉冲默认每拍清 0，进入对应状态时拉高一拍。
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state              <= S_IDLE;
            rd_frame_restart   <= 1'b0;
            rd_en              <= 1'b0;
            tx_en_pulse        <= 1'b0;
            preview_frame_id   <= 16'd0;
            preview_packet_done<= 1'b0;
            preview_frame_done <= 1'b0;
            chunk_id           <= 16'd0;
            frame_offset       <= 32'd0;
            chunk_data_len     <= 16'd0;
            payload_total_len  <= 16'd0;
            payload_fill_idx   <= 16'd0;
            payload_send_idx   <= 16'd0;
            pixel_hold         <= 16'd0;
            low_byte_pending   <= 1'b0;
            rd_pending         <= 1'b0;
            frame_pending      <= 1'b0;
        end else begin
            rd_frame_restart    <= 1'b0;
            rd_en               <= 1'b0;
            tx_en_pulse         <= 1'b0;
            preview_packet_done <= 1'b0;
            preview_frame_done  <= 1'b0;
            if (frame_ready) begin
                // 如果正在发送上一帧，先记住“又有新帧可读”；当前帧发送完后再启动下一帧。
                frame_pending <= 1'b1;
            end

            case (state)
                S_IDLE: begin
                    if (frame_pending) begin
                        frame_pending     <= 1'b0;
                        preview_frame_id <= preview_frame_id + 1'b1;
                        chunk_id         <= 16'd0;
                        frame_offset     <= 32'd0;
                        state            <= S_RESTART;
                    end
                end

                S_RESTART: begin
                    // 通知 DDR3 读侧选择最近完成的 bank，并从帧首开始填读 FIFO。
                    rd_frame_restart <= 1'b1;
                    state            <= S_PREPARE;
                end

                S_PREPARE: begin
                    // 计算本片数据区长度，写入 16 字节分片头。
                    // 头格式：
                    //   [0:1]   magic 'J''P'
                    //   [2]     version
                    //   [3]     msg_type
                    //   [4:5]   frame_id
                    //   [6:7]   chunk_id
                    //   [8:9]   chunk_data_len
                    //   [10]    flags: bit1=last_chunk, bit0=first_chunk
                    //   [12:15] frame_offset
                    remaining_stream  = STREAM_TOTAL_BYTES - frame_offset;
                    chunk_size_calc   = min16(remaining_stream, CHUNK_DATA_BYTES);
                    chunk_data_len    <= chunk_size_calc;
                    payload_total_len <= 16 + chunk_size_calc;
                    payload_fill_idx  <= 16;
                    payload_send_idx  <= 16'd0;
                    low_byte_pending  <= 1'b0;
                    rd_pending        <= 1'b0;

                    payload_mem[0]  <= 8'h4A;
                    payload_mem[1]  <= 8'h50;
                    payload_mem[2]  <= 8'h01;
                    payload_mem[3]  <= PREVIEW_MSG_TYPE;
                    payload_mem[4]  <= preview_frame_id[15:8];
                    payload_mem[5]  <= preview_frame_id[7:0];
                    payload_mem[6]  <= chunk_id[15:8];
                    payload_mem[7]  <= chunk_id[7:0];
                    payload_mem[8]  <= chunk_size_calc[15:8];
                    payload_mem[9]  <= chunk_size_calc[7:0];
                    payload_mem[10] <= {6'b0,
                                        ((frame_offset + chunk_size_calc) >= STREAM_TOTAL_BYTES),
                                        (frame_offset == 32'd0)};
                    payload_mem[11] <= 8'h00;
                    payload_mem[12] <= frame_offset[31:24];
                    payload_mem[13] <= frame_offset[23:16];
                    payload_mem[14] <= frame_offset[15:8];
                    payload_mem[15] <= frame_offset[7:0];
                    state           <= S_FILL;
                end

                S_FILL: begin
                    if (payload_fill_idx >= payload_total_len) begin
                        state <= S_LAUNCH;
                    end else begin
                        stream_pos = frame_offset + (payload_fill_idx - 16);
                        if (stream_pos < 4) begin
                            // 逻辑流前 4 字节是宽高：width[15:8], width[7:0], height[15:8], height[7:0]。
                            payload_mem[payload_fill_idx] <= meta_byte_at(stream_pos[1:0]);
                            payload_fill_idx <= payload_fill_idx + 1'b1;
                        end else if (low_byte_pending) begin
                            // 已经输出了当前 RGB565 像素低字节，这里补高字节。
                            payload_mem[payload_fill_idx] <= pixel_hold[15:8];
                            payload_fill_idx <= payload_fill_idx + 1'b1;
                            low_byte_pending <= 1'b0;
                        end else if (rd_pending) begin
                            // rd_en 后下一拍使用 rd_pixel。先发低字节，再等待下一拍发高字节。
                            pixel_hold <= rd_pixel;
                            payload_mem[payload_fill_idx] <= rd_pixel[7:0];
                            payload_fill_idx <= payload_fill_idx + 1'b1;
                            rd_pending <= 1'b0;
                            low_byte_pending <= 1'b1;
                        end else if (!rd_empty) begin
                            // 读 FIFO 有数据时，向 DDR3 读侧消费一个 16bit 像素。
                            rd_en      <= 1'b1;
                            rd_pending <= 1'b1;
                        end
                    end
                end

                S_LAUNCH: begin
                    if (!tx_busy) begin
                        // 启动一次 UDP 发送。发送过程中 payload_req 会推进 payload_send_idx。
                        tx_en_pulse      <= 1'b1;
                        payload_send_idx <= 16'd0;
                        state            <= S_WAIT_TX;
                    end
                end

                S_WAIT_TX: begin
                    // UDP TX 每请求一个字节，发送索引前进一步。
                    if (payload_req && (payload_send_idx < payload_total_len - 1'b1)) begin
                        payload_send_idx <= payload_send_idx + 1'b1;
                    end

                    if (tx_done) begin
                        // 本片发送完成。若已经覆盖完整逻辑流，则整帧预览完成；否则准备下一片。
                        preview_packet_done <= 1'b1;
                        if ((frame_offset + chunk_data_len) >= STREAM_TOTAL_BYTES) begin
                            preview_frame_done <= 1'b1;
                            state              <= S_IDLE;
                        end else begin
                            frame_offset <= frame_offset + chunk_data_len;
                            chunk_id     <= chunk_id + 1'b1;
                            state        <= S_PREPARE;
                        end
                    end
                end

                default: begin
                    state <= S_IDLE;
                end
            endcase
        end
    end

endmodule
