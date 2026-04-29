

`timescale 1ps/1ps

(* CORE_GENERATION_INFO = "eth_phase_mmcm,clk_wiz_v6_0_11_0_0,{component_name=eth_phase_mmcm,use_phase_alignment=true,use_min_o_jitter=false,use_max_i_jitter=false,use_dyn_phase_shift=false,use_inclk_switchover=false,use_dyn_reconfig=false,enable_axi=0,feedback_source=FDBK_AUTO,PRIMITIVE=MMCM,num_out_clk=1,clkin1_period=8.000,clkin2_period=10.000,use_power_down=false,use_reset=true,use_locked=true,use_inclk_stopped=false,feedback_type=SINGLE,CLOCK_MGR_TYPE=NA,manual_override=false}" *)
// RGMII 接收采样相位调整封装。
// 通过 MMCM 生成相移后的接收时钟，提高 DDR 输入采样裕量。

module eth_phase_mmcm
 (

  output        clk_out1,

  input         reset,
  output        locked,

  input         clk_in1

// 端口列表到此结束，下面进入内部寄存器、组合连线和时序逻辑。
 );

  eth_phase_mmcm_clk_wiz inst
  (

  .clk_out1(clk_out1),

  .reset(reset),
  .locked(locked),

  .clk_in1(clk_in1)
  );

endmodule
