// RGMII 到 GMII 接收适配模块。
// 用 DDR 输入触发器在接收时钟双沿采样 4 位数据，恢复为 8 位 GMII 数据和控制信号。


module rgmii_to_gmii(
    reset_n,
    gmii_rx_clk,
    gmii_rxdv,
    gmii_rxd,
    gmii_rxerr,

    rgmii_rx_clk,
    rgmii_rxd,
    rgmii_rxdv

// 端口列表到此结束，下面进入内部寄存器、组合连线和时序逻辑。
);
    input         reset_n;

    output        gmii_rx_clk;
    output [7:0]  gmii_rxd;
    output        gmii_rxdv;
    output        gmii_rxerr;

    input         rgmii_rx_clk;
    input  [3:0]  rgmii_rxd;
    input         rgmii_rxdv;

    // wire 信号承载组合逻辑结果或子模块之间的连接。
    wire gmii_rxer;

    // 连续赋值用于输出固定映射、组合判断或协议字段拼接。
    assign gmii_rx_clk = rgmii_rx_clk;

    // 连续赋值用于输出固定映射、组合判断或协议字段拼接。
    assign gmii_rxerr = gmii_rxer^gmii_rxdv ;

    genvar i;
    generate
        for(i=0;i<4;i=i+1)
        begin: rgmii_rxd_i
        IDDR #(

            .DDR_CLK_EDGE("SAME_EDGE_PIPELINED"),

            .INIT_Q1(1'b0   ),
            .INIT_Q2(1'b0   ),
            .SRTYPE ("SYNC" )
        ) IDDR_rxd (
            .Q1(gmii_rxd[i]),
            .Q2(gmii_rxd[i+4]),
            .C    (rgmii_rx_clk  ),
            .CE   (1'b1          ),
            .D    (rgmii_rxd[i]  ),
            .R    (!reset_n      ),
            .S    (1'b0          )
        );
        end
    endgenerate

    IDDR #(

        .DDR_CLK_EDGE("SAME_EDGE_PIPELINED"),
        .INIT_Q1(1'b0   ),
        .INIT_Q2(1'b0   ),
        .SRTYPE ("SYNC" )
    ) IDDR_rxdv (
        .Q1(gmii_rxdv),
        .Q2(gmii_rxer),
        .C    (rgmii_rx_clk ),
        .CE   (1'b1         ),
        .D    (rgmii_rxdv   ),
        .R    (!reset_n     ),
        .S    (1'b0         )
    );

endmodule
