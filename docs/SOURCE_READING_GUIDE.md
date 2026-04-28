# 源码阅读指南

本指南用于按系统链路阅读项目源码。建议先理解整体数据流，再进入单个模块，不要按文件名顺序逐个硬读。

## 阅读目标

读完源码后应能回答：

- 摄像头图像如何进入 FPGA。
- FPGA 如何生成预览帧和遥测状态。
- Linux 服务如何接收、解析和展示数据。
- Web 页面如何框选 ROI 并下发参数。
- 告警从 `bright_count` 超阈值到事件记录和蜂鸣器提示，中间经过哪些模块。

## 1. 先读系统文档

优先阅读：

```text
README.md
docs/ARCHITECTURE.md
数据包格式.txt
docs/DEMO_GUIDE.md
```

重点关注：

- 图像路径和遥测路径是两条链路。
- 预览帧和状态包是不同 UDP 数据。
- 命令通道从 Linux 发往 FPGA。
- ROI、阈值、告警使能都是运行时参数。

## 2. Linux C++ 服务

建议先读 Linux 服务，因为它最容易建立全局视角。

### 入口和配置

```text
edge_node_service/src/main.cpp
edge_node_service/src/config.cpp
edge_node_service/include/config.hpp
edge_node_service/config/config.json
```

阅读重点：

- 服务如何加载配置。
- UDP 端口、HTTP 端口、FPGA IP 如何配置。
- 默认 ROI、亮度阈值、告警阈值在哪里定义。

### 协议解析

```text
edge_node_service/include/protocol.hpp
数据包格式.txt
```

阅读重点：

- 32 字节遥测包字段。
- `status_bits` 每一位含义。
- 预览分片包如何描述 frame、chunk、offset。
- 命令包如何封装寄存器写入。

### 服务主逻辑

```text
edge_node_service/include/service.hpp
edge_node_service/src/service.cpp
```

推荐阅读顺序：

1. `EdgeNodeService::start`
2. `rx_loop`
3. `http_loop`
4. `watchdog_loop`
5. `handle_http_request`
6. `build_status_json`
7. `apply_params`
8. `send_command_packet`

阅读重点：

- 三个线程分别负责什么。
- `mutex` 如何保护状态、预览帧和告警事件。
- FPGA 遥测包如何更新 `state_`。
- RGB565 预览分片如何重组并转换为 BMP。
- 告警事件为何只在 `alarm_active` 上升沿记录。
- `/api/status` 返回的数据如何被 Web 使用。

## 3. Web 控制台

文件：

```text
edge_node_service/web/index.html
```

推荐阅读顺序：

1. 页面布局：状态卡片、参数面板、预览区、事件表。
2. `fetchStatus`
3. `renderStatus`
4. `loadPreview`
5. `applyParams`
6. `updateRoiOverlay`
7. `beginRoiDrag / moveRoiDrag / finishRoiDrag`

阅读重点：

- Web 如何周期性读取 `/api/status`。
- 预览图片如何通过 `/api/preview` 刷新。
- ROI 框如何按 `preview_width / preview_height` 映射到页面坐标。
- 鼠标拖拽坐标如何换算成 FPGA ROI 坐标。
- `paramsEditPending` 为什么能防止状态轮询覆盖用户未下发输入。
- 告警状态如何驱动红色边框、Alarm 卡片和事件表。

## 4. FPGA 顶层

从顶层开始看：

```text
edge_vision_node_fpga/rtl/top/top_ov2640_ddr3_udp_preview.v
```

阅读重点：

- 顶层端口和 ACX750 引脚约束如何对应。
- `camera_pclk`、`eth_clk125m`、`sys_clk` 分别负责什么。
- 摄像头采集、DDR3、预处理、UDP、命令 RX 如何连接。
- 哪些信号需要跨时钟域同步。
- 蜂鸣器为什么在保持窗口内输出约 2 kHz 方波。

建议把顶层按区域读：

1. 时钟和复位。
2. 摄像头初始化和采集。
3. DDR3 framebuffer。
4. ROI/亮点统计。
5. 遥测和预览 UDP 发送。
6. UDP 命令接收和寄存器组。
7. LED 和蜂鸣器调试输出。

## 5. 摄像头采集

相关文件：

```text
edge_vision_node_fpga/rtl/camera/ov2640_power_seq.v
edge_vision_node_fpga/rtl/camera/ov2640_sccb_init.v
edge_vision_node_fpga/rtl/camera/ov2640_init_table_svga_rgb565.v
edge_vision_node_fpga/rtl/camera/sccb_master_write.v
edge_vision_node_fpga/rtl/camera/ov2640_capture_if.v
edge_vision_node_fpga/rtl/buffer/ov2640_rgb565_packer.v
```

阅读重点：

- SCCB 如何写 OV2640 寄存器表。
- `VSYNC / HREF / PCLK / D[7:0]` 如何组成帧、行、像素。
- 两个 8-bit 摄像头数据如何拼成一个 RGB565 像素。
- `frame_start / frame_end / pix_valid` 如何产生。

## 6. FPGA 预处理和告警

相关文件：

```text
edge_vision_node_fpga/rtl/preproc/vision_preprocess_core.v
edge_vision_node_fpga/rtl/preproc/stats_async_fifo.v
edge_vision_node_fpga/rtl/net/frame_stats_packet_parallel.v
```

阅读重点：

- ROI 边界如何判断。
- `roi_sum` 如何累加。
- `bright_count` 如何根据亮度阈值统计。
- 为什么在帧结束时更新一帧统计结果。
- `stats_async_fifo` 如何把相机域统计送到网络域。
- 32 字节状态包如何打包。

## 7. DDR3 图像路径

相关文件：

```text
edge_vision_node_fpga/rtl/buffer/edge_ddr3_framebuffer.v
edge_vision_node_fpga/rtl/buffer/edge_ddr3_ctrl_2port.v
edge_vision_node_fpga/rtl/buffer/edge_fifo2mig_axi.v
edge_vision_node_fpga/rtl/net/rgb565_udp_preview_payload_gen.v
```

阅读重点：

- 为什么引入 DDR3 帧缓存。
- 写入路径和读出路径如何解耦。
- AXI burst 什么时候启动。
- 如何避免 FIFO 数据不足时写入无效 beat。
- RGB565 帧如何被拆成 UDP preview chunk。

## 8. UDP/RGMII 网络路径

相关文件：

```text
edge_vision_node_fpga/rtl/net/eth_udp_tx_gmii.v
edge_vision_node_fpga/rtl/net/eth_udp_rx_gmii.v
edge_vision_node_fpga/rtl/net/gmii_to_rgmii.v
edge_vision_node_fpga/rtl/net/rgmii_to_gmii.v
edge_vision_node_fpga/rtl/net/eth_phase_mmcm.v
edge_vision_node_fpga/rtl/net/edge_eth_udp_cfg.v
```

阅读重点：

- GMII 与 RGMII 如何转换。
- TX 如何生成以太网帧、IP、UDP 和 CRC。
- RX 如何从以太网帧中解析 UDP payload。
- RGMII RX 为什么需要相位调整。
- 预览包和遥测包如何共享 UDP TX。

## 9. 命令接收和寄存器组

相关文件：

```text
edge_vision_node_fpga/rtl/ctrl/udp_cmd_packet_parser.v
edge_vision_node_fpga/rtl/ctrl/cmd_async_fifo.v
edge_vision_node_fpga/rtl/ctrl/vision_reg_bank.v
```

阅读重点：

- Linux 命令包如何被 FPGA 校验。
- 命令如何跨到系统/寄存器时钟域。
- `ROI_X / ROI_Y / ROI_W / ROI_H` 如何写入。
- `START_CAPTURE / STOP_CAPTURE / BUZZER_ON / BUZZER_OFF` 如何影响状态。
- ROI 和阈值如何同步到 `camera_pclk` 域并在帧开始生效。

## 10. 约束和 Vivado 工程

相关文件：

```text
edge_vision_node_fpga/constrs/top_ov2640_ddr3_udp_preview.xdc
edge_vision_node_fpga/doc/VIVADO_SOURCE_LIST_DDR3.md
edge_vision_node_fpga/doc/IP_REQUIREMENTS_DDR3.md
```

阅读重点：

- 顶层端口和 ACX750 引脚映射。
- 哪些 IP 需要在 Vivado 中创建。
- 哪些时钟域是异步的。
- CDC 约束为什么不能简单全局 false path。

## 11. 建议补充注释的位置

不建议给每行代码加注释。推荐只在关键工程点补少量注释：

- 顶层时钟域划分。
- CDC 双触发器和异步 FIFO。
- ROI 参数在帧开始锁存。
- DDR3 burst 启动条件。
- RGMII RX 相位调整。
- 状态包字段打包。
- Web ROI 坐标换算。
- 蜂鸣器方波驱动。

## 12. 推荐学习节奏

第一遍：

```text
README -> ARCHITECTURE -> service.cpp -> index.html -> top_ov2640_ddr3_udp_preview.v
```

第二遍：

```text
protocol.hpp -> vision_preprocess_core.v -> stats_async_fifo.v -> frame_stats_packet_parallel.v
```

第三遍：

```text
DDR3 buffer modules -> UDP/RGMII modules -> command parser/register bank
```

最后结合 `docs/DEMO_GUIDE.md` 和实际 Web 页面，把每个功能点对应到具体源码位置。
