`timescale 1ns / 1ps
// 32 字节视觉状态载荷发送辅助模块。
// 按发送模块请求逐字节输出已经准备好的固定长度状态包。

module vision32_payload_gen (
    input  wire        clk,
    input  wire        rst_n,

    input  wire [255:0] pkt_data_256,
    input  wire         pkt_valid,
    output reg          pkt_accept,

    input  wire         send_start,
    input  wire         payload_req,

    output reg  [7:0]   payload_data,
    output wire [15:0]  payload_len,
    output reg          busy,
    output reg          send_done

// 端口列表到此结束，下面进入内部寄存器、组合连线和时序逻辑。
);

    // 连续赋值用于输出固定映射、组合判断或协议字段拼接。
    assign payload_len = 16'd32;

    // reg 信号保存跨周期状态、计数器、握手标志和流水线寄存结果。
    reg [255:0] pkt_buf;
    reg [5:0] byte_idx;
    reg active_send;

    // 时序逻辑：在指定时钟沿更新状态，并在复位时恢复到安全初值。
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            pkt_accept   <= 1'b0;
            payload_data <= 8'd0;
            busy         <= 1'b0;
            send_done    <= 1'b0;
            pkt_buf      <= 256'd0;
            byte_idx     <= 6'd0;
            active_send  <= 1'b0;
        end else begin
            pkt_accept <= 1'b0;
            send_done  <= 1'b0;

            if (!active_send) begin
                busy <= 1'b0;
                byte_idx <= 6'd0;

                if (send_start && pkt_valid) begin
                    pkt_buf     <= pkt_data_256;

                    payload_data <= pkt_data_256[0 +: 8];
                    pkt_accept  <= 1'b1;
                    active_send <= 1'b1;
                    busy        <= 1'b1;
                    byte_idx    <= 6'd1;
                end
            end else begin
                busy <= 1'b1;

                if (payload_req) begin
                    if (byte_idx <= 6'd31) begin

                        payload_data <= pkt_buf[byte_idx*8 +: 8];
                    end

                    if (byte_idx == 6'd32) begin
                        active_send <= 1'b0;
                        busy        <= 1'b0;
                        send_done   <= 1'b1;
                        byte_idx    <= 6'd0;
                    end else begin
                        byte_idx <= byte_idx + 1'b1;
                    end
                end
            end
        end
    end

endmodule
