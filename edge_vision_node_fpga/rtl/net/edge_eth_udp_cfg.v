`timescale 1ns / 1ps
// 以太网和 UDP 默认地址配置。
// 集中保存本机/对端 MAC、IP 和端口参数，方便顶层和收发模块统一引用。

module edge_eth_udp_cfg (
    output wire [47:0] local_mac,
    output wire [31:0] local_ip,
    output wire [15:0] local_port,
    output wire [47:0] dest_mac,
    output wire [31:0] dest_ip,
    output wire [15:0] dest_port,
    output wire [15:0] cmd_port

// 端口列表到此结束，下面进入内部寄存器、组合连线和时序逻辑。
);

    // 连续赋值用于输出固定映射、组合判断或协议字段拼接。
    assign local_mac  = 48'h02_12_34_56_78_9A;

    // 连续赋值用于输出固定映射、组合判断或协议字段拼接。
    assign local_ip   = {8'd192, 8'd168, 8'd50, 8'd2};
    assign local_port = 16'd4000;

    assign dest_mac  = 48'h88_A2_9E_55_F3_5F;
    assign dest_ip   = {8'd192, 8'd168, 8'd50, 8'd1};
    assign dest_port = 16'd9002;
    assign cmd_port  = 16'd9003;

endmodule
