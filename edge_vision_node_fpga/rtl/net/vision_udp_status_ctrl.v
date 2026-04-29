`timescale 1ns / 1ps
// 视觉状态 UDP 发送控制模块。
// 在有新统计数据时申请发送状态包，并处理发送忙时的保持逻辑。

module vision_udp_status_ctrl (
    input  wire clk,
    input  wire rst_n,

    input  wire pkt_valid,
    input  wire payload_busy,
    input  wire tx_done,

    output reg  send_start

// 端口列表到此结束，下面进入内部寄存器、组合连线和时序逻辑。
);

    // reg 信号保存跨周期状态、计数器、握手标志和流水线寄存结果。
    reg sending;

    // 时序逻辑：在指定时钟沿更新状态，并在复位时恢复到安全初值。
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            sending    <= 1'b0;
            send_start <= 1'b0;
        end else begin
            send_start <= 1'b0;

            if (!sending) begin
                if (pkt_valid && !payload_busy) begin
                    send_start <= 1'b1;
                    sending    <= 1'b1;
                end
            end else begin
                if (tx_done) begin
                    sending <= 1'b0;
                end
            end
        end
    end

endmodule
