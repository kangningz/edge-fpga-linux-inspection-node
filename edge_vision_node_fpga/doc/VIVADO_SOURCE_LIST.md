# Vivado 建议加入的源文件

## 当前目录下正式使用的文件

- `rtl/top/top_edge_vision_node.v`
- `rtl/camera/ov2640_capture_if.v`
- `rtl/camera/ov2640_sccb_init.v`
- `rtl/camera/ov2640_init_table_svga_rgb565.v`
- `rtl/camera/sccb_master_write.v`
- `rtl/camera/frame_sync_counter.v`
- `rtl/clk_rst/clk_rst_mgr.v`
- `rtl/debug/frame_stats_core.v`
- `rtl/preproc/stats_async_fifo.v`
- `rtl/ctrl/udp_cmd_packet_parser.v`
- `rtl/ctrl/cmd_async_fifo.v`
- `rtl/ctrl/vision_reg_bank.v`
- `rtl/net/vision32_payload_gen.v`
- `rtl/net/vision_packet_formatter.v`
- `rtl/net/vision_udp_status_ctrl.v`
- `rtl/net/edge_eth_udp_cfg.v`

## 调试顶层

按需加入：

- `rtl/top/top_ov2640_stage2_debug.v`
- `rtl/top/top_ov2640_udp_tx_only.v`

## 约束

正式工程：

- `constrs/top_edge_vision_node.xdc`

调试工程：

- `constrs/top_ov2640_stage2_debug.xdc`
- `constrs/top_ov2640_udp_tx_only.xdc`

## 需要继续复用的低层链路文件

把你现有工程里的低层以太网链路一并加入：

- `crc32_d8.v`
- `eth_udp_tx_gmii.v`
- `eth_udp_rx_gmii.v`
- `gmii_to_rgmii.v`
- `rgmii_to_gmii.v`
- `ip_checksum.v`
- `mdio_bit_shift.v`
- `phy_reg_config.v`
- `pulse_sync_toggle.v`

## IP

- `clk_wiz_125m`
- `eth_phase_mmcm`
