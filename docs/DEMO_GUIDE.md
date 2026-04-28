# 演示指南

目标是在 3 到 5 分钟内证明这不是单点实验，而是一个完整的 FPGA + Linux 边缘巡检节点。

## 演示前准备

FPGA：

- 烧录 `top_ov2640_ddr3_udp_preview` 对应 bitstream。
- 确认 OV2640、以太网、DDR3 已连接。
- 确认树莓派 IP 与 FPGA 配置匹配。

Linux：

```bash
cd ~/edge_node_service/build
cmake ..
make -j4
sudo systemctl restart edge-node.service
curl http://127.0.0.1:5000/api/status
```

状态期望：

- `online=true`
- `has_telemetry_packet=true`
- `preview_available=true`
- `frame_width=800`
- `frame_height=600`
- `error_code=0`
- `cmd_error=0`

## 口播结构

一句话版本：

```text
这个项目把 OV2640 摄像头、FPGA 实时采集预处理、DDR3 缓冲、UDP 传输和树莓派 Linux C++ 服务组成了一个边缘智能巡检感知节点。
```

## 演示步骤

### 1. 展示系统在线

打开：

```text
http://树莓派IP:5000/
```

展示：

- Node State：`ONLINE`
- Resolution：`800 x 600`
- 摄像头预览画面正常刷新
- `frame_id` 持续增长

### 2. 展示 FPGA 遥测

命令：

```bash
curl http://127.0.0.1:5000/api/status
```

重点讲：

- `status_text` 说明 FPGA 采集、帧同步、命令接收、统计写入都正常。
- `active_pixel_count=480000` 对应 `800x600`。
- `roi_sum` 和 `bright_count` 是 FPGA 侧实时统计，不是 Linux 后处理。

### 3. 展示 ROI 框选和参数热更新

在 Web 页面上操作：

- 在摄像头预览画面上拖拽框选一块巡检区域。
- 页面自动换算 `ROI_X / ROI_Y / ROI_W / ROI_H`。
- 预览图上出现黄色 ROI 框。
- 点击 `下发当前 ROI`。

讲解：

- `/api/status` 中的 `current_roi_x/y/w/h` 会更新。
- `bright_count` 会跟随 ROI 和阈值变化。
- 这说明参数不是写死在 FPGA bitstream 里，而是 Linux 侧运行时下发到 FPGA 寄存器。

### 4. 展示告警触发

在 Web 页面点击：

- `低阈值演示`

期望：

- `alarm_enable=true`
- `bright_count >= current_alarm_count_threshold`
- `alarm_active=1`
- ROI 框和预览边框变红
- 蜂鸣器响约 0.5 秒
- 告警事件表新增一行，包含时间、帧号、ROI、`bright_count/threshold`、`roi_sum` 和快照链接

### 5. 展示告警关闭

```bash
curl "http://127.0.0.1:5000/api/command?name=buzzer_off"
sleep 1
curl http://127.0.0.1:5000/api/status
```

期望：

- `alarm_enable=false`
- `status_text` 中 `alarm_enable=0`
- Web 页面 Alarm 显示 `DISABLED`
- 再次触发条件满足时也不会响，说明告警使能和告警判定是分开的

### 6. 展示恢复

```bash
curl "http://127.0.0.1:5000/api/command?name=buzzer_on"
```

如果当前场景仍满足阈值条件，系统会重新进入 `alarm_active=1`。

### 7. 展示事件快照

在告警事件表中点击 `查看`：

- 说明快照由 Linux 服务在告警上升沿保存。
- 说明事件不是单纯页面效果，而是服务端记录，便于后续扩展日志导出或巡检报告。

## 讲解重点

- FPGA 侧处理了真实输入和实时数据通路，不只是透传。
- DDR3 用于帧缓存，FIFO 用于跨时钟域和链路解耦。
- Linux 侧不是简单脚本，而是多线程 C++ 服务。
- Web 展示、ROI 框选、状态 API、命令 API 和事件快照形成可演示的系统闭环。
- 告警阈值可在线调整，适合解释为巡检场景中的规则型边缘智能。
