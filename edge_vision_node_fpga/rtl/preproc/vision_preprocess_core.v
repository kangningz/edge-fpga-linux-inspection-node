`timescale 1ns / 1ps

// Per-frame statistics and alarm generation in the camera_pclk domain.
//
// This module does not modify the pixel stream. It observes capture timing and
// produces one compact stats record at frame_end:
// {frame_id, timestamp, width, height, active_pixel_count, roi_sum, bright_count}
//
// Linux receives this record through the stats FIFO and UDP telemetry path.

module vision_preprocess_core #(
    parameter [15:0] REPORT_WIDTH = 16'd800,
    parameter [15:0] REPORT_HEIGHT = 16'd600,
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
);

    reg [15:0] frame_id;
    reg [31:0] timestamp_cnt;

    reg [15:0] line_cnt_cur;
    reg [15:0] line_width_last;
    reg [15:0] line_pixel_cnt_cur;

    reg [31:0] active_pixel_cnt_cur;
    reg [31:0] roi_sum_cur;
    reg [15:0] bright_cnt_cur;

    // Extend by one bit before adding x/y + width/height so ROI end comparison
    // does not wrap when the ROI approaches the frame boundary.
    wire [11:0] roi_x_end = {1'b0, roi_x} + {1'b0, roi_w};
    wire [11:0] roi_y_end = {1'b0, roi_y} + {1'b0, roi_h};
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
                fifo_overflow_flag <= 1'b0;
                alarm_active       <= 1'b0;
            end

            // Start each frame with fresh accumulators. The reported values are
            // committed only at frame_end, so Linux always sees full-frame stats.
            if (frame_start) begin
                line_cnt_cur         <= 16'd0;
                line_width_last      <= 16'd0;
                line_pixel_cnt_cur   <= 16'd0;
                active_pixel_cnt_cur <= 32'd0;
                roi_sum_cur          <= 32'd0;
                bright_cnt_cur       <= 16'd0;
            end

            if (line_start) begin
                line_pixel_cnt_cur <= 16'd0;
            end

            if (capture_enable && pix_valid) begin
                line_pixel_cnt_cur   <= line_pixel_cnt_cur + 1'b1;
                active_pixel_cnt_cur <= active_pixel_cnt_cur + 1'b1;

                if (in_roi) begin
                    // pix_data is the byte-level brightness proxy used by this
                    // lightweight rule. For RGB565 input, BYTES_PER_PIXEL=2 so
                    // the final active pixel count is divided by two below.
                    roi_sum_cur <= roi_sum_cur + pix_data;
                    if (pix_data >= bright_threshold) begin
                        bright_cnt_cur <= bright_cnt_cur + 1'b1;
                    end
                end
            end

            if (line_end) begin
                if (capture_enable) begin
                    line_cnt_cur    <= line_cnt_cur + 1'b1;
                    line_width_last <= line_width_pixels;
                end
            end

            if (frame_end && capture_enable) begin
                frame_id <= frame_id + 1'b1;
                // alarm_enable gates the result. This lets Linux disable the
                // buzzer/alarm path without changing the statistics pipeline.
                alarm_active <= alarm_enable &&
                                (bright_cnt_cur >= alarm_count_threshold);

                if (!stats_full) begin
                    // stats_din is intentionally fixed-width so the downstream
                    // async FIFO and packet formatter stay simple.
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
