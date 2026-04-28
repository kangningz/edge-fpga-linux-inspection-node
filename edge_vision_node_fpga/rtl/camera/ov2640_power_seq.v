`timescale 1ns / 1ps

module ov2640_power_seq #(
    parameter integer CLK_HZ = 50_000_000
)(
    input  wire clk,
    input  wire rst_n,

    output reg  camera_pwdn,    // 高电平掉电，低电平工作
    output reg  camera_rst_n,   // 低有效硬复位
    output reg  seq_done
);

    // 这里采用保守 bring-up 时序：
    // 1) 上电后先保持 PWDN=1, RESET=0
    // 2) 等 5ms 后释放 PWDN -> 0
    // 3) 再等 1ms 后释放 RESET -> 1
    // 4) 再等 20ms 后认为时序完成，允许进入 SCCB 初始化
    //
    // 这不是在声称 OV2640 必须严格按这个值，
    // 而是一个稳妥的上电时序骨架，便于先 bring-up。

    localparam integer T_5MS  = CLK_HZ / 200;
    localparam integer T_1MS  = CLK_HZ / 1000;
    localparam integer T_20MS = CLK_HZ / 50;

    localparam [1:0]
        S_HOLD_PWDN = 2'd0,
        S_RELEASE_P = 2'd1,
        S_RELEASE_R = 2'd2,
        S_DONE      = 2'd3;

    reg [1:0] state;
    reg [31:0] cnt;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state        <= S_HOLD_PWDN;
            cnt          <= 32'd0;
            camera_pwdn  <= 1'b1;
            camera_rst_n <= 1'b0;
            seq_done     <= 1'b0;
        end else begin
            case (state)
                S_HOLD_PWDN: begin
                    camera_pwdn  <= 1'b1;
                    camera_rst_n <= 1'b0;
                    seq_done     <= 1'b0;
                    if (cnt >= T_5MS - 1) begin
                        cnt   <= 32'd0;
                        state <= S_RELEASE_P;
                    end else begin
                        cnt <= cnt + 1'b1;
                    end
                end

                S_RELEASE_P: begin
                    camera_pwdn  <= 1'b0;
                    camera_rst_n <= 1'b0;
                    if (cnt >= T_1MS - 1) begin
                        cnt   <= 32'd0;
                        state <= S_RELEASE_R;
                    end else begin
                        cnt <= cnt + 1'b1;
                    end
                end

                S_RELEASE_R: begin
                    camera_pwdn  <= 1'b0;
                    camera_rst_n <= 1'b1;
                    if (cnt >= T_20MS - 1) begin
                        cnt   <= 32'd0;
                        state <= S_DONE;
                    end else begin
                        cnt <= cnt + 1'b1;
                    end
                end

                S_DONE: begin
                    camera_pwdn  <= 1'b0;
                    camera_rst_n <= 1'b1;
                    seq_done     <= 1'b1;
                end

                default: begin
                    state        <= S_HOLD_PWDN;
                    cnt          <= 32'd0;
                    camera_pwdn  <= 1'b1;
                    camera_rst_n <= 1'b0;
                    seq_done     <= 1'b0;
                end
            endcase
        end
    end

endmodule