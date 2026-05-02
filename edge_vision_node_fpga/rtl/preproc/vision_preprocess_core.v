`timescale 1ns / 1ps
// 逐帧视觉预处理和告警判断核心。
//
// 本模块是“旁路统计”模块：它观察摄像头像素流，但不阻塞、不修改原始图像数据。
// 每帧统计以下信息：
//   active_pixel_count : 本帧有效像素数
//   roi_sum            : ROI 区域内字节亮度/数据累加值
//   bright_count       : ROI 区域内 >= bright_threshold 的字节数量
//   line_count/width   : 行数和最近一行宽度，用于调试摄像头输出是否正常
//
// 帧尾如果 stats FIFO 未满，就把 160bit 统计记录写出；如果 FIFO 满，则置 overflow sticky 标志。

module vision_preprocess_core #(

    // 上报给 Linux 侧的图像尺寸字段，不参与坐标计数，只进入统计包。
    parameter [15:0] REPORT_WIDTH = 16'd800,
    parameter [15:0] REPORT_HEIGHT = 16'd600,

    // pix_valid 是字节有效；RGB565 每像素 2 字节，因此统计像素数时需要除以 2。
    parameter integer BYTES_PER_PIXEL = 2
)(
    input  wire        rst_n,
    input  wire        camera_pclk,
    input  wire        capture_enable,
    input  wire        alarm_enable,
    input  wire        clear_error,

    input  wire        frame_start,
    input  wire        frame_end,
    input  wire        line_start,
    input  wire        line_end,
    input  wire        pix_valid,
    input  wire [7:0]  pix_data,
    input  wire [10:0] x_cnt,
    input  wire [10:0] y_cnt,

    input  wire [10:0] roi_x,
    input  wire [10:0] roi_y,
    input  wire [10:0] roi_w,
    input  wire [10:0] roi_h,
    input  wire [7:0]  bright_threshold,
    input  wire [15:0] alarm_count_threshold,

    input  wire        stats_full,

    output reg         stats_wr_en,
    output reg [159:0] stats_din,
    output reg         fifo_overflow_flag,
    output reg         alarm_active

// 端口列表到此结束，下面进入内部寄存器、组合连线和时序逻辑。
);

    // frame_id 每输出一帧统计包递增；timestamp_cnt 是 camera_pclk 域自由运行计数器。
    reg [15:0] frame_id;
    reg [31:0] timestamp_cnt;

    // 行级调试计数。line_pixel_cnt_cur 先按字节计数，line_width_pixels 再换算成像素。
    reg [15:0] line_cnt_cur;
    reg [15:0] line_width_last;
    reg [15:0] line_pixel_cnt_cur;

    // 帧内累计值。active_pixel_cnt_cur 也是先按字节计数，帧尾按 BYTES_PER_PIXEL 换算。
    reg [31:0] active_pixel_cnt_cur;
    reg [31:0] roi_sum_cur;
    reg [15:0] bright_cnt_cur;

    // ROI 右/下边界采用开区间判断：[roi_x, roi_x + roi_w)，[roi_y, roi_y + roi_h)。
    wire [11:0] roi_x_end = {1'b0, roi_x} + {1'b0, roi_w};
    wire [11:0] roi_y_end = {1'b0, roi_y} + {1'b0, roi_h};

    // 将字节数换算成像素数。RGB565 时 x_cnt 本质上也是字节坐标，所以行宽需要右移一位。
    wire [15:0] line_width_pixels =
        (BYTES_PER_PIXEL == 2) ? {1'b0, line_pixel_cnt_cur[15:1]} :
        line_pixel_cnt_cur;
    wire [31:0] active_pixel_count_pixels =
        (BYTES_PER_PIXEL == 2) ? {1'b0, active_pixel_cnt_cur[31:1]} :
        active_pixel_cnt_cur;
    wire in_roi = capture_enable &&
                  pix_valid &&
                  ({1'b0, x_cnt} >= {1'b0, roi_x}) &&
                  ({1'b0, x_cnt} < roi_x_end) &&
                  ({1'b0, y_cnt} >= {1'b0, roi_y}) &&
                  ({1'b0, y_cnt} < roi_y_end);

    // 主统计逻辑。所有帧内累计值在 frame_start 清零，在 frame_end 打包输出。
    always @(posedge camera_pclk or negedge rst_n) begin
        if (!rst_n) begin
            frame_id             <= 16'd0;
            timestamp_cnt        <= 32'd0;
            line_cnt_cur         <= 16'd0;
            line_width_last      <= 16'd0;
            line_pixel_cnt_cur   <= 16'd0;
            active_pixel_cnt_cur <= 32'd0;
            roi_sum_cur          <= 32'd0;
            bright_cnt_cur       <= 16'd0;
            stats_wr_en          <= 1'b0;
            stats_din            <= 160'd0;
            fifo_overflow_flag   <= 1'b0;
            alarm_active         <= 1'b0;
        end else begin
            timestamp_cnt <= timestamp_cnt + 1'b1;
            stats_wr_en   <= 1'b0;

            if (clear_error) begin
                // clear_error 只清 sticky 错误/告警，不清 frame_id/timestamp。
                fifo_overflow_flag <= 1'b0;
                alarm_active       <= 1'b0;
            end

            if (frame_start) begin
                // 新帧开始，清空本帧累计统计。
                line_cnt_cur         <= 16'd0;
                line_width_last      <= 16'd0;
                line_pixel_cnt_cur   <= 16'd0;
                active_pixel_cnt_cur <= 32'd0;
                roi_sum_cur          <= 32'd0;
                bright_cnt_cur       <= 16'd0;
            end

            if (line_start) begin
                // 每行重新统计当前行宽。
                line_pixel_cnt_cur <= 16'd0;
            end

            if (capture_enable && pix_valid) begin
                // pix_valid 是字节有效，所以这里先按字节累计；帧尾/行尾再换算成像素。
                line_pixel_cnt_cur   <= line_pixel_cnt_cur + 1'b1;
                active_pixel_cnt_cur <= active_pixel_cnt_cur + 1'b1;

                if (in_roi) begin
                    // 当前实现直接累加 8bit 字节值，适合做轻量亮度/活动量指标。
                    // 如果后续要严格按 RGB565 亮度统计，可在这里先把两个字节恢复成 RGB 分量。
                    roi_sum_cur <= roi_sum_cur + pix_data;
                    if (pix_data >= bright_threshold) begin
                        bright_cnt_cur <= bright_cnt_cur + 1'b1;
                    end
                end
            end

            if (line_end) begin
                if (capture_enable) begin
                    // 记录行数和最近一行宽度，随统计包上报给上位机。
                    line_cnt_cur    <= line_cnt_cur + 1'b1;
                    line_width_last <= line_width_pixels;
                end
            end

            if (frame_end && capture_enable) begin
                frame_id <= frame_id + 1'b1;

                // 告警条件：ROI 内亮点数量达到阈值。alarm_enable 为 0 时强制不置告警。
                alarm_active <= alarm_enable &&
                                (bright_cnt_cur >= alarm_count_threshold);

                if (!stats_full) begin
                    // stats_din 打包顺序从高位到低位：
                    //   frame_id_next, timestamp, width, height,
                    //   active_pixel_count, roi_sum, bright_count
                    stats_wr_en <= 1'b1;
                    stats_din   <= {
                        frame_id + 1'b1,
                        timestamp_cnt,
                        REPORT_WIDTH,
                        REPORT_HEIGHT,
                        active_pixel_count_pixels,
                        roi_sum_cur,
                        bright_cnt_cur
                    };
                end else begin
                    fifo_overflow_flag <= 1'b1;
                end
            end
        end
    end

endmodule
