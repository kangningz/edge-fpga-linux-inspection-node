`timescale 1ns / 1ps

module frame_sync_counter (
    input  wire rst_n,
    input  wire camera_pclk,

    input  wire frame_start,
    input  wire frame_end,
    input  wire line_start,
    input  wire line_end,
    input  wire pix_valid,

    output reg [15:0] frame_cnt,
    output reg [15:0] line_cnt_last,
    output reg [31:0] pixel_cnt_last,
    output reg        frame_locked
);

    reg [15:0] line_cnt_cur;
    reg [31:0] pixel_cnt_cur;
    reg [31:0] last_good_pixel_cnt;
    reg [15:0] last_good_line_cnt;

    always @(posedge camera_pclk or negedge rst_n) begin
        if (!rst_n) begin
            frame_cnt          <= 16'd0;
            line_cnt_last      <= 16'd0;
            pixel_cnt_last     <= 32'd0;
            frame_locked       <= 1'b0;
            line_cnt_cur       <= 16'd0;
            pixel_cnt_cur      <= 32'd0;
            last_good_pixel_cnt<= 32'd0;
            last_good_line_cnt <= 16'd0;
        end else begin
            if (frame_start) begin
                line_cnt_cur  <= 16'd0;
                pixel_cnt_cur <= 32'd0;
            end

            if (line_start) begin
                line_cnt_cur <= line_cnt_cur + 1'b1;
            end

            if (pix_valid) begin
                pixel_cnt_cur <= pixel_cnt_cur + 1'b1;
            end

            if (frame_end) begin
                frame_cnt      <= frame_cnt + 1'b1;
                line_cnt_last  <= line_cnt_cur;
                pixel_cnt_last <= pixel_cnt_cur;

                if ((pixel_cnt_cur != 32'd0) && (line_cnt_cur != 16'd0)) begin
                    if ((last_good_pixel_cnt == 32'd0) || (last_good_line_cnt == 16'd0)) begin
                        frame_locked <= 1'b1;
                    end else begin
                        frame_locked <= 1'b1;
                    end
                    last_good_pixel_cnt <= pixel_cnt_cur;
                    last_good_line_cnt  <= line_cnt_cur;
                end else begin
                    frame_locked <= 1'b0;
                end
            end
        end
    end

endmodule