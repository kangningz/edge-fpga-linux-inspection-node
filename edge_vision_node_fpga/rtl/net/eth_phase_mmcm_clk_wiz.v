

`timescale 1ps/1ps
// Vivado Clocking Wizard 生成的 MMCM 网络表。
// 保留用于产生 RGMII 接收相位时钟，注释已改为中文以便工程阅读。

module eth_phase_mmcm_clk_wiz

 (

  output        clk_out1,

  input         reset,
  output        locked,
  input         clk_in1

// 端口列表到此结束，下面进入内部寄存器、组合连线和时序逻辑。
 );

    // wire 信号承载组合逻辑结果或子模块之间的连接。
wire clk_in1_eth_phase_mmcm;
wire clk_in2_eth_phase_mmcm;
  IBUF clkin1_ibufg
   (.O (clk_in1_eth_phase_mmcm),
    .I (clk_in1));

  wire        clk_out1_eth_phase_mmcm;
  wire        clk_out2_eth_phase_mmcm;
  wire        clk_out3_eth_phase_mmcm;
  wire        clk_out4_eth_phase_mmcm;
  wire        clk_out5_eth_phase_mmcm;
  wire        clk_out6_eth_phase_mmcm;
  wire        clk_out7_eth_phase_mmcm;

  wire [15:0] do_unused;
  wire        drdy_unused;
  wire        psdone_unused;
  wire        locked_int;
  wire        clkfbout_eth_phase_mmcm;
  wire        clkfbout_buf_eth_phase_mmcm;
  wire        clkfboutb_unused;
    wire clkout0b_unused;
   wire clkout1_unused;
   wire clkout1b_unused;
   wire clkout2_unused;
   wire clkout2b_unused;
   wire clkout3_unused;
   wire clkout3b_unused;
   wire clkout4_unused;
  wire        clkout5_unused;
  wire        clkout6_unused;
  wire        clkfbstopped_unused;
  wire        clkinstopped_unused;
  wire        reset_high;

  MMCME2_ADV
  #(.BANDWIDTH            ("OPTIMIZED"),
    .CLKOUT4_CASCADE      ("FALSE"),
    .COMPENSATION         ("ZHOLD"),
    .STARTUP_WAIT         ("FALSE"),
    .DIVCLK_DIVIDE        (1),
    .CLKFBOUT_MULT_F      (8.000),
    .CLKFBOUT_PHASE       (0.000),
    .CLKFBOUT_USE_FINE_PS ("FALSE"),
    .CLKOUT0_DIVIDE_F     (8.000),
    .CLKOUT0_PHASE        (90.000),
    .CLKOUT0_DUTY_CYCLE   (0.500),
    .CLKOUT0_USE_FINE_PS  ("FALSE"),
    .CLKIN1_PERIOD        (8.000))
  mmcm_adv_inst

   (
    .CLKFBOUT            (clkfbout_eth_phase_mmcm),
    .CLKFBOUTB           (clkfboutb_unused),
    .CLKOUT0             (clk_out1_eth_phase_mmcm),
    .CLKOUT0B            (clkout0b_unused),
    .CLKOUT1             (clkout1_unused),
    .CLKOUT1B            (clkout1b_unused),
    .CLKOUT2             (clkout2_unused),
    .CLKOUT2B            (clkout2b_unused),
    .CLKOUT3             (clkout3_unused),
    .CLKOUT3B            (clkout3b_unused),
    .CLKOUT4             (clkout4_unused),
    .CLKOUT5             (clkout5_unused),
    .CLKOUT6             (clkout6_unused),

    .CLKFBIN             (clkfbout_buf_eth_phase_mmcm),
    .CLKIN1              (clk_in1_eth_phase_mmcm),
    .CLKIN2              (1'b0),

    .CLKINSEL            (1'b1),

    .DADDR               (7'h0),
    .DCLK                (1'b0),
    .DEN                 (1'b0),
    .DI                  (16'h0),
    .DO                  (do_unused),
    .DRDY                (drdy_unused),
    .DWE                 (1'b0),

    .PSCLK               (1'b0),
    .PSEN                (1'b0),
    .PSINCDEC            (1'b0),
    .PSDONE              (psdone_unused),

    .LOCKED              (locked_int),
    .CLKINSTOPPED        (clkinstopped_unused),
    .CLKFBSTOPPED        (clkfbstopped_unused),
    .PWRDWN              (1'b0),
    .RST                 (reset_high));

    // 连续赋值用于输出固定映射、组合判断或协议字段拼接。
  assign reset_high = reset;

    // 连续赋值用于输出固定映射、组合判断或协议字段拼接。
  assign locked = locked_int;

  BUFG clkf_buf
   (.O (clkfbout_buf_eth_phase_mmcm),
    .I (clkfbout_eth_phase_mmcm));

  BUFG clkout1_buf
   (.O   (clk_out1),
    .I   (clk_out1_eth_phase_mmcm));

endmodule
