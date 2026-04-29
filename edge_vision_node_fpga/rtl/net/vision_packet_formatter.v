`timescale 1ns / 1ps
// 视觉遥测包格式化模块。
// 把帧统计、状态位和校验和整理成 Linux 服务端可解析的协议字节序。

module vision_packet_formatter (
    input  wire        clk,
    input  wire        rst_n,
    input  wire        start,

    input  wire [7:0]   msg_type,
    input  wire [15:0]  frame_id,
    input  wire [15:0]  status_bits,
    input  wire [31:0]  timestamp_low,
    input  wire [15:0]  frame_width,
    input  wire [15:0]  frame_height,
    input  wire [31:0]  active_pixel_count,
    input  wire [31:0]  roi_sum,
    input  wire [15:0]  bright_count,
    input  wire [15:0]  error_code,

    output reg          busy,
    output reg          done,
    output reg  [255:0] packet_data_256

// 端口列表到此结束，下面进入内部寄存器、组合连线和时序逻辑。
);

    // reg 信号保存跨周期状态、计数器、握手标志和流水线寄存结果。
    reg [7:0]   msg_type_r;
    reg [15:0]  frame_id_r;
    reg [15:0]  status_bits_r;
    reg [31:0]  timestamp_low_r;
    reg [15:0]  frame_width_r;
    reg [15:0]  frame_height_r;
    reg [31:0]  active_pixel_count_r;
    reg [31:0]  roi_sum_r;
    reg [15:0]  bright_count_r;
    reg [15:0]  error_code_r;

    reg [5:0] byte_idx;
    reg [7:0] checksum;

    function [7:0] payload_byte;
        input [5:0] idx;
        begin

            // 状态机分支：按当前阶段执行握手、计数或数据搬运动作。
            case (idx)
                6'd0:  payload_byte = 8'h45;
                6'd1:  payload_byte = 8'h56;
                6'd2:  payload_byte = 8'h01;
                6'd3:  payload_byte = msg_type_r;
                6'd4:  payload_byte = frame_id_r[15:8];
                6'd5:  payload_byte = frame_id_r[7:0];
                6'd6:  payload_byte = status_bits_r[15:8];
                6'd7:  payload_byte = status_bits_r[7:0];
                6'd8:  payload_byte = timestamp_low_r[31:24];
                6'd9:  payload_byte = timestamp_low_r[23:16];
                6'd10: payload_byte = timestamp_low_r[15:8];
                6'd11: payload_byte = timestamp_low_r[7:0];
                6'd12: payload_byte = frame_width_r[15:8];
                6'd13: payload_byte = frame_width_r[7:0];
                6'd14: payload_byte = frame_height_r[15:8];
                6'd15: payload_byte = frame_height_r[7:0];
                6'd16: payload_byte = active_pixel_count_r[31:24];
                6'd17: payload_byte = active_pixel_count_r[23:16];
                6'd18: payload_byte = active_pixel_count_r[15:8];
                6'd19: payload_byte = active_pixel_count_r[7:0];
                6'd20: payload_byte = roi_sum_r[31:24];
                6'd21: payload_byte = roi_sum_r[23:16];
                6'd22: payload_byte = roi_sum_r[15:8];
                6'd23: payload_byte = roi_sum_r[7:0];
                6'd24: payload_byte = bright_count_r[15:8];
                6'd25: payload_byte = bright_count_r[7:0];
                6'd26: payload_byte = error_code_r[15:8];
                6'd27: payload_byte = error_code_r[7:0];
                6'd28: payload_byte = 8'h00;
                6'd29: payload_byte = 8'h00;
                6'd30: payload_byte = 8'h00;
                default: payload_byte = 8'h00;

            // 状态机分支结束，未命中的情况由默认分支回到安全状态。
            endcase
        end
    endfunction

    // wire 信号承载组合逻辑结果或子模块之间的连接。
    wire [7:0] curr_payload_byte = payload_byte(byte_idx);

    // 时序逻辑：在指定时钟沿更新状态，并在复位时恢复到安全初值。
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            msg_type_r           <= 8'd0;
            frame_id_r           <= 16'd0;
            status_bits_r        <= 16'd0;
            timestamp_low_r      <= 32'd0;
            frame_width_r        <= 16'd0;
            frame_height_r       <= 16'd0;
            active_pixel_count_r <= 32'd0;
            roi_sum_r            <= 32'd0;
            bright_count_r       <= 16'd0;
            error_code_r         <= 16'd0;
            byte_idx             <= 6'd0;
            checksum             <= 8'd0;
            busy                 <= 1'b0;
            done                 <= 1'b0;
            packet_data_256      <= 256'd0;
        end else begin
            done <= 1'b0;

            if (!busy) begin
                if (start) begin
                    msg_type_r           <= msg_type;
                    frame_id_r           <= frame_id;
                    status_bits_r        <= status_bits;
                    timestamp_low_r      <= timestamp_low;
                    frame_width_r        <= frame_width;
                    frame_height_r       <= frame_height;
                    active_pixel_count_r <= active_pixel_count;
                    roi_sum_r            <= roi_sum;
                    bright_count_r       <= bright_count;
                    error_code_r         <= error_code;
                    byte_idx             <= 6'd0;
                    checksum             <= 8'd0;
                    packet_data_256      <= 256'd0;
                    busy                 <= 1'b1;
                end
            end else begin
                if (byte_idx < 6'd31) begin
                    packet_data_256[byte_idx*8 +: 8] <= curr_payload_byte;
                    checksum <= checksum ^ curr_payload_byte;
                    byte_idx <= byte_idx + 1'b1;
                end else begin
                    packet_data_256[31*8 +: 8] <= checksum;
                    busy <= 1'b0;
                    done <= 1'b1;
                end
            end
        end
    end

endmodule
