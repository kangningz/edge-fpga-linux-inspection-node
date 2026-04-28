`timescale 1ns / 1ps

module ov2640_status_bus (
    input  wire        init_done,
    input  wire        init_error,
    input  wire        frame_locked,
    input  wire [15:0] frame_cnt,
    input  wire [15:0] line_cnt_last,
    input  wire [31:0] pixel_cnt_last,

    output wire [63:0] status_bus
);

    assign status_bus = {
        12'd0,
        init_done,          // bit 51
        init_error,         // bit 50
        frame_locked,       // bit 49
        1'b0,               // bit 48
        frame_cnt,          // bit 47:32
        line_cnt_last,      // bit 31:16
        pixel_cnt_last[15:0]// bit 15:0
    };

endmodule