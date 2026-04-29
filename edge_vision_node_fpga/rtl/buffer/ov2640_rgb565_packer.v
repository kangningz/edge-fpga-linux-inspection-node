`timescale 1ns / 1ps
// OV2640 字节流到 RGB565 像素打包模块。
// 摄像头每个像素输出两个字节，本模块在 href 有效期间合并为 16 位像素并给出像素有效脉冲。

module ov2640_rgb565_packer (
    input  wire       rst_n,
    input  wire       camera_pclk,
    input  wire       frame_start,
    input  wire       frame_end,
    input  wire       line_start,
    input  wire       line_end,
    input  wire       pix_valid,
    input  wire [7:0] pix_data,

    output reg        pixel_valid,
    output reg [15:0] pixel_data,
    output reg        frame_start_16,
    output reg        frame_end_16,
    output reg        line_start_16,
    output reg        line_end_16,
    output reg        byte_phase_error

// 端口列表到此结束，下面进入内部寄存器、组合连线和时序逻辑。
);

    // reg 信号保存跨周期状态、计数器、握手标志和流水线寄存结果。
    reg       byte_phase;
    reg [7:0] first_byte;
    reg       pending_frame_start;
    reg       pending_line_start;
    reg       pending_frame_end;
    reg       pending_line_end;

    // 时序逻辑：在指定时钟沿更新状态，并在复位时恢复到安全初值。
    always @(posedge camera_pclk or negedge rst_n) begin
        if (!rst_n) begin
            pixel_valid          <= 1'b0;
            pixel_data           <= 16'd0;
            frame_start_16       <= 1'b0;
            frame_end_16         <= 1'b0;
            line_start_16        <= 1'b0;
            line_end_16          <= 1'b0;
            byte_phase_error     <= 1'b0;
            byte_phase           <= 1'b0;
            first_byte           <= 8'd0;
            pending_frame_start  <= 1'b0;
            pending_line_start   <= 1'b0;
            pending_frame_end    <= 1'b0;
            pending_line_end     <= 1'b0;
        end else begin
            pixel_valid    <= 1'b0;
            frame_start_16 <= 1'b0;
            frame_end_16   <= 1'b0;
            line_start_16  <= 1'b0;
            line_end_16    <= 1'b0;

            if (frame_start) pending_frame_start <= 1'b1;
            if (line_start)  pending_line_start  <= 1'b1;
            if (frame_end)   pending_frame_end   <= 1'b1;
            if (line_end) begin
                pending_line_end <= 1'b1;
                if (byte_phase) begin
                    byte_phase       <= 1'b0;
                    byte_phase_error <= 1'b1;
                end
            end

            if (pix_valid) begin
                if (!byte_phase) begin
                    first_byte <= pix_data;
                    byte_phase <= 1'b1;
                end else begin
                    pixel_valid    <= 1'b1;
                    pixel_data     <= {first_byte, pix_data};
                    frame_start_16 <= pending_frame_start;
                    frame_end_16   <= pending_frame_end;
                    line_start_16  <= pending_line_start;
                    line_end_16    <= pending_line_end;

                    pending_frame_start <= 1'b0;
                    pending_frame_end   <= 1'b0;
                    pending_line_start  <= 1'b0;
                    pending_line_end    <= 1'b0;
                    byte_phase          <= 1'b0;
                end
            end
        end
    end

endmodule
