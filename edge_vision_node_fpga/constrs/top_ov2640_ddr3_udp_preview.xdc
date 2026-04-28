######################################################################
# ACX750 - top_ov2640_ddr3_udp_preview.xdc
#
# This file constrains:
# - common board IO
# - OV2640 camera IO
# - RGMII TX pins only
#
# DDR3 pin constraints must come from the generated mig_7series_0.xdc.
# Do not enable mig_7series_0_ooc.xdc.
######################################################################

set_property BITSTREAM.CONFIG.UNUSEDPIN Pullnone [current_design]

set_property PACKAGE_PIN W19 [get_ports FPGA_CLK]
set_property IOSTANDARD LVCMOS33 [get_ports FPGA_CLK]
create_clock -name FPGA_CLK -period 20.000 [get_ports FPGA_CLK]

set_property PACKAGE_PIN D21 [get_ports S0]
set_property IOSTANDARD LVCMOS33 [get_ports S0]

set_property PACKAGE_PIN U22 [get_ports LED0]
set_property IOSTANDARD LVCMOS33 [get_ports LED0]
set_property PACKAGE_PIN V22 [get_ports LED1]
set_property IOSTANDARD LVCMOS33 [get_ports LED1]
set_property PACKAGE_PIN W21 [get_ports LED2]
set_property IOSTANDARD LVCMOS33 [get_ports LED2]
set_property PACKAGE_PIN W22 [get_ports LED3]
set_property IOSTANDARD LVCMOS33 [get_ports LED3]
set_property PACKAGE_PIN Y21 [get_ports LED4]
set_property IOSTANDARD LVCMOS33 [get_ports LED4]
set_property PACKAGE_PIN Y22 [get_ports LED5]
set_property IOSTANDARD LVCMOS33 [get_ports LED5]
set_property PACKAGE_PIN N13 [get_ports LED6]
set_property IOSTANDARD LVCMOS33 [get_ports LED6]
set_property PACKAGE_PIN N17 [get_ports LED7]
set_property IOSTANDARD LVCMOS33 [get_ports LED7]

set_property PACKAGE_PIN V17 [get_ports BEEP]
set_property IOSTANDARD LVCMOS33 [get_ports BEEP]

set_property PACKAGE_PIN M15 [get_ports camera_xclk]
set_property IOSTANDARD LVCMOS33 [get_ports camera_xclk]
set_property DRIVE 8 [get_ports camera_xclk]
set_property SLEW FAST [get_ports camera_xclk]

set_property PACKAGE_PIN J16 [get_ports camera_scl]
set_property IOSTANDARD LVCMOS33 [get_ports camera_scl]

set_property PACKAGE_PIN M17 [get_ports camera_sda]
set_property IOSTANDARD LVCMOS33 [get_ports camera_sda]

set_property PACKAGE_PIN M20 [get_ports {camera_d[0]}]
set_property IOSTANDARD LVCMOS33 [get_ports {camera_d[0]}]
set_property PACKAGE_PIN N20 [get_ports {camera_d[1]}]
set_property IOSTANDARD LVCMOS33 [get_ports {camera_d[1]}]
set_property PACKAGE_PIN K19 [get_ports {camera_d[2]}]
set_property IOSTANDARD LVCMOS33 [get_ports {camera_d[2]}]
set_property PACKAGE_PIN K16 [get_ports {camera_d[3]}]
set_property IOSTANDARD LVCMOS33 [get_ports {camera_d[3]}]
set_property PACKAGE_PIN L16 [get_ports {camera_d[4]}]
set_property IOSTANDARD LVCMOS33 [get_ports {camera_d[4]}]
set_property PACKAGE_PIN L18 [get_ports {camera_d[5]}]
set_property IOSTANDARD LVCMOS33 [get_ports {camera_d[5]}]
set_property PACKAGE_PIN M18 [get_ports {camera_d[6]}]
set_property IOSTANDARD LVCMOS33 [get_ports {camera_d[6]}]
set_property PACKAGE_PIN M16 [get_ports {camera_d[7]}]
set_property IOSTANDARD LVCMOS33 [get_ports {camera_d[7]}]

set_property PACKAGE_PIN N18 [get_ports camera_href]
set_property IOSTANDARD LVCMOS33 [get_ports camera_href]

set_property PACKAGE_PIN N19 [get_ports camera_vsync]
set_property IOSTANDARD LVCMOS33 [get_ports camera_vsync]

set_property PACKAGE_PIN K18 [get_ports camera_pclk]
set_property IOSTANDARD LVCMOS33 [get_ports camera_pclk]
create_clock -name CAMERA_PCLK -period 20.000 [get_ports camera_pclk]
create_clock -name RGMII_RX_CLK -period 8.000 [get_ports rgmii_rx_clk_i]

# Asynchronous user clock domains used by the UDP preview path.
# Use top-level nets so the constraints survive generated-clock naming differences.
set_clock_groups -asynchronous \
  -group [get_clocks FPGA_CLK] \
  -group [get_clocks CAMERA_PCLK] \
  -group [get_clocks RGMII_RX_CLK] \
  -group [get_clocks -include_generated_clocks -of_objects [get_nets eth_clk125m]] \
  -group [get_clocks -include_generated_clocks -of_objects [get_pins -hier -filter {NAME =~ *u_mig_7series_0/ui_clk}]]

set_property PACKAGE_PIN P14 [get_ports eth_reset_n]
set_property IOSTANDARD LVCMOS33 [get_ports eth_reset_n]

set_property PACKAGE_PIN AA19 [get_ports rgmii_txen]
set_property IOSTANDARD LVCMOS33 [get_ports rgmii_txen]

set_property PACKAGE_PIN AB20 [get_ports {rgmii_txd[0]}]
set_property IOSTANDARD LVCMOS33 [get_ports {rgmii_txd[0]}]
set_property PACKAGE_PIN Y19 [get_ports {rgmii_txd[1]}]
set_property IOSTANDARD LVCMOS33 [get_ports {rgmii_txd[1]}]
set_property PACKAGE_PIN AB22 [get_ports {rgmii_txd[2]}]
set_property IOSTANDARD LVCMOS33 [get_ports {rgmii_txd[2]}]
set_property PACKAGE_PIN W20 [get_ports {rgmii_txd[3]}]
set_property IOSTANDARD LVCMOS33 [get_ports {rgmii_txd[3]}]

set_property PACKAGE_PIN AB21 [get_ports rgmii_tx_clk]
set_property IOSTANDARD LVCMOS33 [get_ports rgmii_tx_clk]

set_property PACKAGE_PIN Y18 [get_ports rgmii_rx_clk_i]
set_property IOSTANDARD LVCMOS33 [get_ports rgmii_rx_clk_i]

set_property PACKAGE_PIN T20 [get_ports rgmii_rxdv]
set_property IOSTANDARD LVCMOS33 [get_ports rgmii_rxdv]

set_property PACKAGE_PIN P20 [get_ports {rgmii_rxd[0]}]
set_property IOSTANDARD LVCMOS33 [get_ports {rgmii_rxd[0]}]
set_property PACKAGE_PIN N15 [get_ports {rgmii_rxd[1]}]
set_property IOSTANDARD LVCMOS33 [get_ports {rgmii_rxd[1]}]
set_property PACKAGE_PIN AA18 [get_ports {rgmii_rxd[2]}]
set_property IOSTANDARD LVCMOS33 [get_ports {rgmii_rxd[2]}]
set_property PACKAGE_PIN AB18 [get_ports {rgmii_rxd[3]}]
set_property IOSTANDARD LVCMOS33 [get_ports {rgmii_rxd[3]}]

set_property CLOCK_DEDICATED_ROUTE FALSE [get_nets rgmii_rx_clk_i]

# Explicit CDC exceptions for synchronizer first-stage flops only.
set_false_path -to [get_pins -hier -filter {NAME =~ *u_wr_frame_done_to_eth*/dst_ff0_reg/D}]
set_false_path -to [get_pins -hier -filter {NAME =~ *u_preview_packet_done_to_sys*/dst_ff0_reg/D}]
set_false_path -to [get_pins -hier -filter {NAME =~ *u_preview_frame_done_to_sys*/dst_ff0_reg/D}]
set_false_path -to [get_pins -hier -filter {NAME =~ *ddr3_init_done_eth_ff0_reg/D}]
set_false_path -to [get_pins -hier -filter {NAME =~ *u_wrfifo_clr_to_ui*/dst_ff0_reg/D}]
set_false_path -to [get_pins -hier -filter {NAME =~ *u_rdfifo_clr_to_ui*/dst_ff0_reg/D}]
set_false_path -to [get_pins -hier -filter {NAME =~ *cam_rst_ff0_reg/D}]
set_false_path -to [get_pins -hier -filter {NAME =~ *rd_rst_ff0_reg/D}]
set_false_path -to [get_pins -hier -filter {NAME =~ *wr_fifo_rst_busy_ff0_reg/D}]
set_false_path -to [get_pins -hier -filter {NAME =~ *rd_fifo_rst_busy_ff0_reg/D}]
