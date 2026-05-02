`timescale 1ns / 1ps
// OV2640 DVP 采集接口。
//
// 输入是摄像头原始 DVP 信号：
//   camera_pclk  : 像素时钟
//   camera_href  : 行有效
//   camera_vsync : 帧同步
//   camera_d     : 8bit 数据字节
//
// 输出是后级更容易使用的事件流：
//   frame_start/frame_end : 单拍帧边界
//   line_start/line_end   : 单拍行边界
//   pix_valid/pix_data    : href 有效期间的 8bit 字节流
//   x_cnt/y_cnt           : 当前字节横坐标、行计数
//
// 说明：OV2640 在 RGB565 模式下一个像素由两个字节组成，本模块只负责采集字节；
// 真正的 16bit RGB565 打包在 buffer/ov2640_rgb565_packer.v 中完成。

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

    // 先把 vsync/href 打两拍，既用于边沿检测，也能让组合边沿判断只依赖寄存后的信号。
    reg vsync_d0, vsync_d1;
    reg href_d0,  href_d1;

    // 有些 OV2640 配置下有效帧边界可能表现为 vsync 上升沿，有些可能是下降沿。
    // 这里在第一次看到 href 前后的 vsync 边沿后锁定“哪个边沿代表新帧开始”，
    // 后续 frame_boundary_evt 就按这个边沿产生 frame_start/frame_end。
    reg frame_edge_valid;
    reg frame_start_on_rise;
    reg last_vsync_edge_valid;
    reg last_vsync_edge_was_rise;
    reg frame_seen;

    wire vsync_rise;
    wire vsync_fall;
    wire href_rise;
    wire href_fall;
    wire vsync_edge;
    wire frame_boundary_evt;

    assign vsync_rise = (vsync_d0 == 1'b1) && (vsync_d1 == 1'b0);
    assign vsync_fall = (vsync_d0 == 1'b0) && (vsync_d1 == 1'b1);
    assign href_rise  = (href_d0  == 1'b1) && (href_d1  == 1'b0);
    assign href_fall  = (href_d0  == 1'b0) && (href_d1  == 1'b1);
    assign vsync_edge = vsync_rise | vsync_fall;

    // 已经锁定帧边沿后，只在对应 vsync 边沿上产生帧边界事件。
    assign frame_boundary_evt = frame_edge_valid &&
                                (( frame_start_on_rise && vsync_rise) ||
                                 (~frame_start_on_rise && vsync_fall));

    // 所有输出脉冲默认每拍清 0，遇到对应事件时拉高一个 camera_pclk 周期。
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

            // 记录最近一次 vsync 边沿，供下一次 href_rise 判断帧开始边沿极性。
            if (vsync_edge) begin
                last_vsync_edge_valid    <= 1'b1;
                last_vsync_edge_was_rise <= vsync_rise;
            end

            // 第一次看到有效行时，利用当前或最近一次 vsync 边沿锁定帧边界极性。
            if (!frame_edge_valid && href_rise && (vsync_edge || last_vsync_edge_valid)) begin
                frame_edge_valid    <= 1'b1;
                frame_start_on_rise <= vsync_edge ? vsync_rise : last_vsync_edge_was_rise;
            end

            // 每个帧边界都产生 frame_start；从第二个边界开始，前一帧也可认为结束。
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

            // href 高电平期间，每个 pclk 采一个数据字节。
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
