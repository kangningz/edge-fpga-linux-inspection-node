`timescale 1ns / 1ps

module edge_eth_udp_cfg (
    output wire [47:0] local_mac,
    output wire [31:0] local_ip,
    output wire [15:0] local_port,
    output wire [47:0] dest_mac,
    output wire [31:0] dest_ip,
    output wire [15:0] dest_port,
    output wire [15:0] cmd_port
);

    assign local_mac  = 48'h02_12_34_56_78_9A;
    assign local_ip   = {8'd192, 8'd168, 8'd50, 8'd2};
    assign local_port = 16'd4000;

    // 这里必须改成树莓派 eth0 的真实 MAC。
    // 可在树莓派上执行：ip link show eth0
    assign dest_mac  = 48'h88_A2_9E_55_F3_5F;
    assign dest_ip   = {8'd192, 8'd168, 8'd50, 8'd1};
    assign dest_port = 16'd9002;
    assign cmd_port  = 16'd9003;

endmodule
