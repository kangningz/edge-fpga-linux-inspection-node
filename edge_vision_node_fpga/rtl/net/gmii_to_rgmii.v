// GMII 到 RGMII 发送适配模块。
// 把 8 位 GMII 数据在时钟双沿压缩为 4 位 RGMII DDR 数据，并同步发送控制信号。


module gmii_to_rgmii(
  reset_n,

  gmii_tx_clk,
  gmii_txd,
  gmii_txen,
  gmii_txer,

  rgmii_tx_clk,
  rgmii_txd,
  rgmii_txen

// 端口列表到此结束，下面进入内部寄存器、组合连线和时序逻辑。
);

  input        reset_n;

  input        gmii_tx_clk;
  input  [7:0] gmii_txd;
  input        gmii_txen;
  input        gmii_txer;

  output       rgmii_tx_clk;
  output [3:0] rgmii_txd;
  output       rgmii_txen;

  genvar i;
  generate
    for(i=0;i<4;i=i+1)
    begin: rgmii_txd_o
      ODDR #(
        .DDR_CLK_EDGE("SAME_EDGE"),
        .INIT  (1'b0   ),
        .SRTYPE("SYNC" )
      ) ODDR_rgmii_txd (
        .Q   (rgmii_txd[i]     ),
        .C   (gmii_tx_clk      ),
        .CE  (1'b1             ),
        .D1  (gmii_txd[i]      ),
        .D2  (gmii_txd[i+4]    ),
        .R   (~reset_n         ),
        .S   (1'b0             )
      );
    end
  endgenerate

  ODDR #(
    .DDR_CLK_EDGE("SAME_EDGE"),
    .INIT  (1'b0   ),
    .SRTYPE("SYNC" )
  ) ODDR_rgmii_txd (
    .Q   (rgmii_txen          ),
    .C   (gmii_tx_clk         ),
    .CE  (1'b1                ),
    .D1  (gmii_txen           ),
    .D2  (gmii_txen^gmii_txer ),
    .R   (~reset_n            ),
    .S   (1'b0                )
  );

  ODDR #(
    .DDR_CLK_EDGE("SAME_EDGE"),
    .INIT  (1'b0   ),
    .SRTYPE("SYNC" )
  ) ODDR_rgmii_clk (
    .Q   (rgmii_tx_clk  ),
    .C   (gmii_tx_clk   ),
    .CE  (1'b1          ),
    .D1  (1'b1          ),
    .D2  (1'b0          ),
    .R   (~reset_n      ),
    .S   (1'b0          )
  );

endmodule
