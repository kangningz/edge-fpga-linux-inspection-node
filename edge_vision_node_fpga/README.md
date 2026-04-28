# edge_vision_node_fpga

FPGA 侧主工程，面向 `ACX750 / XC7A100T` 开发板和 `OV2640` 摄像头。当前主线是 DDR3 RGB565 预览 + 遥测统计 + UDP 命令闭环。

## 当前主顶层

```text
rtl/top/top_ov2640_ddr3_udp_preview.v
```

约束：

```text
constrs/top_ov2640_ddr3_udp_preview.xdc
```

## 已实现能力

- OV2640 SCCB 初始化，输出 `SVGA 800x600 RGB565`。
- DVP 采集，识别 `VSYNC/HREF/PCLK`，生成帧/行/像素有效信号。
- DDR3 帧缓存，支持 RGB565 预览帧回传。
- ROI/亮点统计，输出 `active_pixel_count / roi_sum / bright_count`。
- 统计异步 FIFO，跨 `camera_pclk` 到 `eth_clk125m`。
- UDP/RGMII 发送预览帧和 32 字节遥测包。
- RGMII RX 命令接收，支持 Linux 侧运行时参数热更新。
- 告警状态输出和蜂鸣器保持时间。

## 关键模块

- `rtl/top/top_ov2640_ddr3_udp_preview.v`：当前主顶层。
- `rtl/camera/ov2640_sccb_init.v`：摄像头 SCCB 初始化控制。
- `rtl/camera/ov2640_init_table_svga_rgb565.v`：OV2640 SVGA RGB565 初始化表。
- `rtl/camera/ov2640_capture_if.v`：DVP 采集接口。
- `rtl/buffer/edge_ddr3_framebuffer.v`：DDR3 帧缓存路径。
- `rtl/buffer/edge_fifo2mig_axi.v`：FIFO 到 MIG/AXI 写入路径。
- `rtl/preproc/vision_preprocess_core.v`：ROI/亮点统计与告警判断。
- `rtl/preproc/stats_async_fifo.v`：统计包跨时钟域 FIFO。
- `rtl/ctrl/vision_reg_bank.v`：命令寄存器组。
- `rtl/ctrl/udp_cmd_packet_parser.v`：UDP 命令包解析。
- `rtl/net/eth_udp_tx_gmii.v`：UDP 发送链。
- `rtl/net/eth_udp_rx_gmii.v`：UDP 接收链。
- `rtl/net/rgb565_udp_preview_payload_gen.v`：RGB565 预览分片。
- `rtl/net/frame_stats_packet_parallel.v`：遥测包生成。

## 状态位

`status_bits` 从低到高：

- bit0：`cam_init_done`
- bit1：`frame_locked`
- bit2：`fifo_overflow`
- bit3：`udp_busy_or_drop`
- bit4：`capture_enable`
- bit5：`alarm_active`
- bit6：`phy_init_done`
- bit7：`cmd_error`
- bit8：`alarm_enable`
- bit9：`dbg_pkt_seen`
- bit10：`dbg_vsync_seen`
- bit11：`dbg_href_seen`
- bit12：`dbg_frame_start_seen`
- bit13：`dbg_frame_end_seen`
- bit14：`dbg_pix_valid_seen`
- bit15：`dbg_stats_wr_seen`

## 命令和寄存器

Linux 到 FPGA 命令包固定 20 字节，`magic = 0x43 0x4D`。

支持命令：

- `0x01 WRITE_REG`
- `0x02 READ_REG`
- `0x03 START_CAPTURE`
- `0x04 STOP_CAPTURE`
- `0x05 QUERY_STATUS`
- `0x06 CLEAR_ERROR`
- `0x07 BUZZER_ON`
- `0x08 BUZZER_OFF`

关键寄存器：

- `0x0000 CTRL`：`capture_enable / alarm_enable / debug_uart_enable`
- `0x0010 ROI_X`
- `0x0011 ROI_Y`
- `0x0012 ROI_W`
- `0x0013 ROI_H`
- `0x0014 BRIGHT_THRESHOLD`
- `0x0015 TX_MODE`
- `0x0016 ALARM_COUNT_THRESHOLD`

## Vivado 工程

参考：

- `doc/VIVADO_SOURCE_LIST_DDR3.md`
- `doc/IP_REQUIREMENTS_DDR3.md`
- `doc/DDR3_UDP_PREVIEW_GUIDE.md`
- `doc/DDR3_PREVIEW_TELEMETRY_NOTES_20260423.md`

本地 `iverilog` 只能做部分语法检查，完整综合必须在 Vivado 中完成，因为工程依赖 `MIG / FIFO Generator / XPM / MMCM / ODDR/IDDR` 等 Xilinx IP 和原语。
