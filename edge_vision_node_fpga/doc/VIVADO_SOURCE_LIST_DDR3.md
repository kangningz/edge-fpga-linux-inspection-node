# DDR3 路线建议加入的源文件

## 顶层

- `rtl/top/top_ov2640_ddr3_udp_preview.v`

## 新增 buffer 模块

- `rtl/buffer/pulse_sync_toggle.v`
- `rtl/buffer/ov2640_rgb565_packer.v`
- `rtl/buffer/edge_fifo2mig_axi.v`
- `rtl/buffer/edge_ddr3_ctrl_2port.v`
- `rtl/buffer/edge_ddr3_framebuffer.v`

## 复用 camera / debug / clk 模块

- `rtl/camera/ov2640_capture_if.v`
- `rtl/camera/ov2640_sccb_init.v`
- `rtl/camera/ov2640_init_table_svga_rgb565.v`
- `rtl/camera/sccb_master_write.v`
- `rtl/camera/frame_sync_counter.v`
- `rtl/clk_rst/clk_rst_mgr.v`
- `rtl/ctrl/vision_reg_bank.v`
- `rtl/ctrl/udp_cmd_packet_parser.v`
- `rtl/ctrl/cmd_async_fifo.v`
- `rtl/preproc/vision_preprocess_core.v`

## 约束

- `constrs/top_ov2640_ddr3_udp_preview.xdc`

## 预览 + Telemetry 网络模块

- `rtl/preproc/stats_async_fifo.v`
- `rtl/net/frame_stats_packet_parallel.v`
- `rtl/net/vision32_payload_gen.v`
- `rtl/net/vision_udp_status_ctrl.v`
- `rtl/net/edge_eth_udp_cfg.v`
- `rtl/net/eth_udp_tx_gmii.v`
- `rtl/net/eth_udp_rx_gmii.v`
- `rtl/net/gmii_to_rgmii.v`
- `rtl/net/rgmii_to_gmii.v`
- `rtl/net/eth_phase_mmcm.v`
- `rtl/net/eth_phase_mmcm_clk_wiz.v`
- `rtl/net/crc32_d8.v`
- `rtl/net/ip_checksum.v`
- `rtl/net/rgb565_udp_preview_payload_gen.v`

## 需要手动加入的 IP

- `clk_wiz_ddr3_200m`
- `wr_ddr3_fifo`
- `rd_ddr3_fifo`
- `mig_7series_0`

## 官方优先参考

- `ddr3_ctrl_2port.v`
- `fifo2mig_axi.v`
- 官方 DDR3 MIG 约束文件
