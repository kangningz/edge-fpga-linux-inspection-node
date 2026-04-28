# 演示验收清单

用于录制演示视频或答辩前自检。

## 设备检查

- ACX750 FPGA 板已上电。
- OV2640 摄像头排线连接稳定。
- 网线连接到树莓派 5 或同一局域网。
- FPGA bitstream 是 `top_ov2640_ddr3_udp_preview` 对应版本。
- 树莓派服务已启动：`sudo systemctl status edge-node.service`。

## 基础状态

执行：

```bash
curl http://127.0.0.1:5000/api/status
```

通过条件：

- `online=true`
- `has_packet=true`
- `has_telemetry_packet=true`
- `preview_stream_only=false`
- `last_peer_ip=192.168.50.2`
- `error_code=0`
- `rx_errors=0`

## FPGA 状态位

通过条件：

- `cam_init_done=1`
- `frame_locked=1`
- `fifo_overflow=0`
- `udp_busy_or_drop=0`
- `capture_enable=1`
- `phy_init_done=1`
- `cmd_error=0`
- `dbg_vsync_seen=1`
- `dbg_href_seen=1`
- `dbg_pix_valid_seen=1`
- `dbg_stats_wr_seen=1`

## 预览画面

通过条件：

- Web 页面摄像头预览能显示真实画面。
- `/api/status` 中 `preview_available=true`。
- `preview_width=800`。
- `preview_height=600`。
- `preview_format=rgb565_bmp`。
- `preview_frame_id` 会增长。

## 参数热更新

执行：

```bash
curl "http://127.0.0.1:5000/api/apply_params?roi_x=320&roi_y=240&roi_w=160&roi_h=120&bright_threshold=40&alarm_count_threshold=20000&tx_mode=2"
sleep 1
curl http://127.0.0.1:5000/api/status
```

通过条件：

- `current_roi_x=320`
- `current_roi_y=240`
- `current_roi_w=160`
- `current_roi_h=120`
- `current_bright_threshold=40`
- `current_alarm_count_threshold=20000`
- `current_tx_mode=2`

## 告警闭环

先关闭误触发：

```bash
curl "http://127.0.0.1:5000/api/command?name=buzzer_off"
```

验证关闭：

- `alarm_enable=false`
- Web 页面 Alarm 显示 `DISABLED`

再打开并触发：

```bash
curl "http://127.0.0.1:5000/api/command?name=buzzer_on"
curl "http://127.0.0.1:5000/api/apply_params?roi_x=320&roi_y=240&roi_w=160&roi_h=120&bright_threshold=40&alarm_count_threshold=1000&tx_mode=2"
sleep 1
curl http://127.0.0.1:5000/api/status
```

通过条件：

- `alarm_enable=true`
- `bright_count > current_alarm_count_threshold`
- `alarm_active=1`
- Web 页面 Alarm 显示 `ACTIVE`
- 蜂鸣器可听到，且不是一瞬间极短脉冲。
- Web 页面“告警事件”新增一条记录。
- `/api/status` 中 `alarm_event_count` 增加，`alarm_events[0]` 记录当前帧号、亮点数和阈值。
- `alarm_events[0].image_url` 非空时，Web 页面可点击“查看快照”打开告警现场图。

## 演示视频建议

- 时长控制在 1 到 2 分钟。
- 第一屏先展示整体 Web 页面和摄像头预览。
- 第二屏展示 `/api/status` 关键字段。
- 第三屏展示参数下发和告警状态变化。
- 最后展示蜂鸣器开关和页面 `ACTIVE / DISABLED`。

## 常见异常

- `preview_available=false`：先确认 FPGA 是否烧录 DDR3 UDP 预览顶层。
- `has_telemetry_packet=false`：检查 FPGA 遥测包是否发送、树莓派端口 `9002` 是否监听。
- `cmd_error=1`：检查命令地址或命令包格式。
- `alarm_active=0` 但 `bright_count` 超阈值：先看 `alarm_enable` 是否为 `true`。
- `frame_locked=0`：检查 OV2640 初始化、PCLK、VSYNC/HREF 接线。
