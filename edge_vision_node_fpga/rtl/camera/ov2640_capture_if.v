`timescale 1ns / 1ps
// OV2640 采集接口。
// 它在摄像头像素时钟域解析 vsync、href 和 8 位数据，输出帧边界、行有效和 RGB565 字节流。

module ov2640_capture_if (
    input  wire rst_n,
    input  wire camera_pclk,
    input  wire camera_vsync,
    input  wire camera_href,
    input  wire [7:0] camera_d,

    output reg        frame_start,
    output reg        frame_end,
    output reg        line_start,
    output reg        line_end,
    output reg        pix_valid,
    output reg [7:0]  pix_data,
    output reg [10:0] x_cnt,
    output reg [10:0] y_cnt

// 端口列表到此结束，下面进入内部寄存器、组合连线和时序逻辑。
);

    // reg 信号保存跨周期状态、计数器、握手标志和流水线寄存结果。
    reg vsync_d0, vsync_d1;
    reg href_d0,  href_d1;
    reg frame_edge_valid;
    reg frame_start_on_rise;
    reg last_vsync_edge_valid;
    reg last_vsync_edge_was_rise;
    reg frame_seen;

    // wire 信号承载组合逻辑结果或子模块之间的连接。
    wire vsync_rise;
    wire vsync_fall;
    wire href_rise;
    wire href_fall;
    wire vsync_edge;
    wire frame_boundary_evt;

    // 连续赋值用于输出固定映射、组合判断或协议字段拼接。
    assign vsync_rise = (vsync_d0 == 1'b1) && (vsync_d1 == 1'b0);

    // 连续赋值用于输出固定映射、组合判断或协议字段拼接。
    assign vsync_fall = (vsync_d0 == 1'b0) && (vsync_d1 == 1'b1);

    assign href_rise  = (href_d0  == 1'b1) && (href_d1  == 1'b0);
    assign href_fall  = (href_d0  == 1'b0) && (href_d1  == 1'b1);
    assign vsync_edge = vsync_rise | vsync_fall;
    assign frame_boundary_evt = frame_edge_valid &&
                                (( frame_start_on_rise && vsync_rise) ||
                                 (~frame_start_on_rise && vsync_fall));

    // 时序逻辑：在指定时钟沿更新状态，并在复位时恢复到安全初值。
    always @(posedge camera_pclk or negedge rst_n) begin
        if (!rst_n) begin
            vsync_d0    <= 1'b0;
            vsync_d1    <= 1'b0;
            href_d0     <= 1'b0;
            href_d1     <= 1'b0;
            frame_edge_valid <= 1'b0;
            frame_start_on_rise <= 1'b0;
            last_vsync_edge_valid <= 1'b0;
            last_vsync_edge_was_rise <= 1'b0;
            frame_seen  <= 1'b0;

            frame_start <= 1'b0;
            frame_end   <= 1'b0;
            line_start  <= 1'b0;
            line_end    <= 1'b0;
            pix_valid   <= 1'b0;
            pix_data    <= 8'd0;
            x_cnt       <= 11'd0;
            y_cnt       <= 11'd0;
        end else begin
            vsync_d0 <= camera_vsync;
            vsync_d1 <= vsync_d0;
            href_d0  <= camera_href;
            href_d1  <= href_d0;

            frame_start <= 1'b0;
            frame_end   <= 1'b0;
            line_start  <= 1'b0;
            line_end    <= 1'b0;
            pix_valid   <= 1'b0;

            if (vsync_edge) begin
                last_vsync_edge_valid    <= 1'b1;
                last_vsync_edge_was_rise <= vsync_rise;
            end

            if (!frame_edge_valid && href_rise && (vsync_edge || last_vsync_edge_valid)) begin
                frame_edge_valid    <= 1'b1;
                frame_start_on_rise <= vsync_edge ? vsync_rise : last_vsync_edge_was_rise;
            end

            if (frame_boundary_evt) begin
                if (frame_seen)
                    frame_end <= 1'b1;
                frame_start <= 1'b1;
                frame_seen   <= 1'b1;
                x_cnt       <= 11'd0;
                y_cnt       <= 11'd0;
            end

            if (href_rise) begin
                line_start <= 1'b1;
                x_cnt      <= 11'd0;
            end

            if (camera_href) begin
                pix_valid <= 1'b1;
                pix_data  <= camera_d;
                x_cnt     <= x_cnt + 1'b1;
            end

            if (href_fall) begin
                line_end <= 1'b1;
                x_cnt    <= 11'd0;
                y_cnt    <= y_cnt + 1'b1;
            end
        end
    end

endmodule
