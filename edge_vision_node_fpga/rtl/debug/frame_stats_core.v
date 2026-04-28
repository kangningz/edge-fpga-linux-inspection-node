`timescale 1ns / 1ps

module frame_stats_core #(
    parameter [10:0] ROI_X      = 11'd0,
    parameter [10:0] ROI_Y      = 11'd0,
    parameter [10:0] ROI_W      = 11'd64,
    parameter [10:0] ROI_H      = 11'd64,
    parameter [7:0]  BRIGHT_TH  = 8'd128,
    parameter integer BYTES_PER_PIXEL = 2
)(
    input  wire        rst_n,
    input  wire        camera_pclk,

    input  wire        frame_start,
    input  wire        frame_end,
    input  wire        line_start,
    input  wire        line_end,
    input  wire        pix_valid,
    input  wire [7:0]  pix_data,
    input  wire [10:0] x_cnt,
    input  wire [10:0] y_cnt,

    input  wire        stats_full,

    output reg         stats_wr_en,
    output reg [159:0] stats_din,          // {frame_id,timestamp,width,height,active_cnt,roi_sum,bright_cnt}
    output reg         fifo_overflow_flag
);

    reg [15:0] frame_id;
    reg [31:0] timestamp_cnt;

    reg [15:0] line_cnt_cur;
    reg [15:0] line_width_last;
    reg [15:0] line_pixel_cnt_cur;

    reg [31:0] active_pixel_cnt_cur;
    reg [31:0] roi_sum_cur;
    reg [15:0] bright_cnt_cur;

    wire in_roi;
    wire [15:0] line_width_pixels;
    wire [31:0] active_pixel_count_pixels;
    wire [15:0] frame_width_report;
    wire [15:0] frame_height_report;
    assign in_roi =
        pix_valid &&
        (x_cnt >= ROI_X) &&
        (x_cnt < (ROI_X + ROI_W)) &&
        (y_cnt >= ROI_Y) &&
        (y_cnt < (ROI_Y + ROI_H));

    assign line_width_pixels =
        (BYTES_PER_PIXEL == 2) ? {1'b0, line_pixel_cnt_cur[15:1]} :
        line_pixel_cnt_cur;

    assign active_pixel_count_pixels =
        (BYTES_PER_PIXEL == 2) ? {1'b0, active_pixel_cnt_cur[31:1]} :
        active_pixel_cnt_cur;

    assign frame_width_report = line_end ? line_width_pixels : line_width_last;
    assign frame_height_report = line_cnt_cur + (line_end ? 16'd1 : 16'd0);

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
        end else begin
            timestamp_cnt <= timestamp_cnt + 1'b1;
            stats_wr_en   <= 1'b0;

            if (frame_start) begin
                line_cnt_cur         <= 16'd0;
                line_width_last      <= 16'd0;
                line_pixel_cnt_cur   <= 16'd0;
                active_pixel_cnt_cur <= 32'd0;
                roi_sum_cur          <= 32'd0;
                bright_cnt_cur       <= 16'd0;
            end

            if (pix_valid) begin
                line_pixel_cnt_cur <= line_start ? 16'd1 : (line_pixel_cnt_cur + 1'b1);
                active_pixel_cnt_cur <= frame_start ? 32'd1 : (active_pixel_cnt_cur + 1'b1);

                if (in_roi) begin
                    roi_sum_cur <= frame_start ? {{24{1'b0}}, pix_data} : (roi_sum_cur + pix_data);
                    if (pix_data >= BRIGHT_TH)
                        bright_cnt_cur <= frame_start ? 16'd1 : (bright_cnt_cur + 1'b1);
                end
            end else if (line_start) begin
                line_pixel_cnt_cur <= 16'd0;
            end

            if (line_end) begin
                line_cnt_cur    <= line_cnt_cur + 1'b1;
                line_width_last <= line_width_pixels;
            end

            if (frame_end) begin
                frame_id <= frame_id + 1'b1;

                if (!stats_full) begin
                    stats_wr_en <= 1'b1;
                    stats_din   <= {
                        frame_id + 1'b1,       // [159:144]
                        timestamp_cnt,         // [143:112]
                        frame_width_report,    // [111:96]
                        frame_height_report,   // [95:80]
                        active_pixel_count_pixels,  // [79:48]
                        roi_sum_cur,           // [47:16]
                        bright_cnt_cur         // [15:0]
                    };
                end else begin
                    fifo_overflow_flag <= 1'b1;
                end
            end
        end
    end

endmodule
