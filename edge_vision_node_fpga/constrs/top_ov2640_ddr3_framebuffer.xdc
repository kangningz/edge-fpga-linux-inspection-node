######################################################################
# ACX750 - top_ov2640_ddr3_framebuffer.xdc
#
# 注意：
# 1) 本文件只包含通用 IO 和 OV2640 相关约束
# 2) DDR3 引脚约束请直接从官方 MIG/DDR3 例程里复制
# 3) 不要手猜 DDR3 pinout
######################################################################

set_property BITSTREAM.CONFIG.UNUSEDPIN Pullnone [current_design]

set_property PACKAGE_PIN W19 [get_ports FPGA_CLK]
set_property IOSTANDARD LVCMOS33 [get_ports FPGA_CLK]
create_clock -name FPGA_CLK -period 20.000 [get_ports FPGA_CLK]

set_property PACKAGE_PIN D21 [get_ports S0]
set_property IOSTANDARD LVCMOS33 [get_ports S0]

set_property PACKAGE_PIN M21 [get_ports UART_TXD]
set_property IOSTANDARD LVCMOS33 [get_ports UART_TXD]

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

# DDR3 相关 pin / IO standard / INTERNAL_VREF / SLEW / termination
# 请直接合并官方例程中的 MIG 约束。
