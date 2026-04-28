`timescale 1ns / 1ps

module pulse_sync_toggle (
    input  wire src_clk,
    input  wire src_rst_n,
    input  wire src_pulse,

    input  wire dst_clk,
    input  wire dst_rst_n,
    output wire dst_pulse
);

    reg src_toggle;
    always @(posedge src_clk or negedge src_rst_n) begin
        if (!src_rst_n) begin
            src_toggle <= 1'b0;
        end else if (src_pulse) begin
            src_toggle <= ~src_toggle;
        end
    end

    (* ASYNC_REG = "TRUE" *) reg dst_ff0;
    (* ASYNC_REG = "TRUE" *) reg dst_ff1;
    reg dst_ff2;

    always @(posedge dst_clk or negedge dst_rst_n) begin
        if (!dst_rst_n) begin
            dst_ff0 <= 1'b0;
            dst_ff1 <= 1'b0;
            dst_ff2 <= 1'b0;
        end else begin
            dst_ff0 <= src_toggle;
            dst_ff1 <= dst_ff0;
            dst_ff2 <= dst_ff1;
        end
    end

    assign dst_pulse = dst_ff1 ^ dst_ff2;

endmodule
