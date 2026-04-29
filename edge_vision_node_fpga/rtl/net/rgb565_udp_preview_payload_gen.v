`timescale 1ns / 1ps
// RGB565 预览 UDP 载荷生成器。
// 它从 DDR3 读出帧像素，按分片头加宽高和像素数据，和遥测包一起仲裁发送。

module rgb565_udp_preview_payload_gen #(

    // 参数用于适配不同图像尺寸、时钟频率、缓冲深度或网络地址。
    parameter integer FRAME_WIDTH        = 800,

    // 参数用于适配不同图像尺寸、时钟频率、缓冲深度或网络地址。
    parameter integer FRAME_HEIGHT       = 600,

    // 参数用于适配不同图像尺寸、时钟频率、缓冲深度或网络地址。
    parameter integer CHUNK_DATA_BYTES   = 1024,

    // 参数用于适配不同图像尺寸、时钟频率、缓冲深度或网络地址。
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

    // 本地常量定义状态编码、计数上限或协议字段，避免魔法数字散落在逻辑中。
    localparam integer STREAM_TOTAL_BYTES = 4 + FRAME_WIDTH * FRAME_HEIGHT * 2;
    localparam integer PAYLOAD_MAX_BYTES  = 16 + CHUNK_DATA_BYTES;

    localparam [2:0] S_IDLE      = 3'd0;
    localparam [2:0] S_RESTART   = 3'd1;
    localparam [2:0] S_PREPARE   = 3'd2;
    localparam [2:0] S_FILL      = 3'd3;
    localparam [2:0] S_LAUNCH    = 3'd4;
    localparam [2:0] S_WAIT_TX   = 3'd5;

    // reg 信号保存跨周期状态、计数器、握手标志和流水线寄存结果。
    reg [2:0]  state;
    reg [15:0] chunk_id;
    reg [31:0] frame_offset;
    reg [15:0] chunk_data_len;
    reg [15:0] payload_total_len;
    reg [15:0] payload_fill_idx;
    reg [15:0] payload_send_idx;
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

            // 状态机分支：按当前阶段执行握手、计数或数据搬运动作。
            case (idx)
                2'd0: meta_byte_at = FRAME_WIDTH[15:8];
                2'd1: meta_byte_at = FRAME_WIDTH[7:0];
                2'd2: meta_byte_at = FRAME_HEIGHT[15:8];
                default: meta_byte_at = FRAME_HEIGHT[7:0];

            // 状态机分支结束，未命中的情况由默认分支回到安全状态。
            endcase
        end
    endfunction

    // 连续赋值用于输出固定映射、组合判断或协议字段拼接。
    assign data_length = payload_total_len;

    // 连续赋值用于输出固定映射、组合判断或协议字段拼接。
    assign payload_dat = payload_mem[payload_send_idx];

    // 时序逻辑：在指定时钟沿更新状态，并在复位时恢复到安全初值。
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

                frame_pending <= 1'b1;
            end

            // 状态机分支：按当前阶段执行握手、计数或数据搬运动作。
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

                    rd_frame_restart <= 1'b1;
                    state            <= S_PREPARE;
                end

                S_PREPARE: begin

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

                            payload_mem[payload_fill_idx] <= meta_byte_at(stream_pos[1:0]);
                            payload_fill_idx <= payload_fill_idx + 1'b1;
                        end else if (low_byte_pending) begin
                            payload_mem[payload_fill_idx] <= pixel_hold[15:8];
                            payload_fill_idx <= payload_fill_idx + 1'b1;
                            low_byte_pending <= 1'b0;
                        end else if (rd_pending) begin

                            pixel_hold <= rd_pixel;
                            payload_mem[payload_fill_idx] <= rd_pixel[7:0];
                            payload_fill_idx <= payload_fill_idx + 1'b1;
                            rd_pending <= 1'b0;
                            low_byte_pending <= 1'b1;
                        end else if (!rd_empty) begin
                            rd_en      <= 1'b1;
                            rd_pending <= 1'b1;
                        end
                    end
                end

                S_LAUNCH: begin
                    if (!tx_busy) begin

                        tx_en_pulse      <= 1'b1;
                        payload_send_idx <= 16'd0;
                        state            <= S_WAIT_TX;
                    end
                end

                S_WAIT_TX: begin
                    if (payload_req && (payload_send_idx < payload_total_len - 1'b1)) begin
                        payload_send_idx <= payload_send_idx + 1'b1;
                    end

                    if (tx_done) begin
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

            // 状态机分支结束，未命中的情况由默认分支回到安全状态。
            endcase
        end
    end

endmodule
