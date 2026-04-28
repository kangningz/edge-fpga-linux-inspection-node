# edge_node_service

树莓派 5 侧 C++ 控制服务，负责接收 FPGA 遥测和预览帧、下发 UDP 命令、提供 Web 控制台、日志、配置和在线状态判定。

## 职责

- 接收 FPGA 上报的 32 字节遥测包。
- 接收 FPGA 回传的 RGB565 预览分片并重组最近一帧。
- 将 RGB565 转换为 BMP，供 Web 页面显示。
- 向 FPGA 下发命令和寄存器写入。
- 提供 HTTP 控制台和 JSON API。
- 支持配置热重载、日志记录、离线超时判定和 systemd 部署。

## 构建

```bash
cd ~/edge_node_service
rm -rf build
mkdir build
cd build
cmake ..
make -j4
```

## 运行

前台运行：

```bash
./edge_node_service ../config/config.json
```

systemd：

```bash
sudo cp edge-node.service /etc/systemd/system/
sudo systemctl daemon-reload
sudo systemctl enable edge-node.service
sudo systemctl restart edge-node.service
```

## 默认端口

- FPGA 遥测/预览上报到 Pi：`9002`
- Pi 命令发送到 FPGA：`9003`
- HTTP 控制台：`5000`

访问：

```text
http://树莓派IP:5000/
```

## API

状态：

```bash
curl http://127.0.0.1:5000/api/status
```

预览：

```bash
curl http://127.0.0.1:5000/api/preview --output latest_preview.bmp
```

基础命令：

```bash
curl "http://127.0.0.1:5000/api/command?name=query_status"
curl "http://127.0.0.1:5000/api/command?name=start_capture"
curl "http://127.0.0.1:5000/api/command?name=stop_capture"
curl "http://127.0.0.1:5000/api/command?name=clear_error"
curl "http://127.0.0.1:5000/api/command?name=buzzer_on"
curl "http://127.0.0.1:5000/api/command?name=buzzer_off"
curl "http://127.0.0.1:5000/api/command?name=apply_defaults"
```

参数热更新：

```bash
curl "http://127.0.0.1:5000/api/apply_params?roi_x=320&roi_y=240&roi_w=160&roi_h=120&bright_threshold=40&alarm_count_threshold=1000&tx_mode=2"
```

单寄存器写入：

```bash
curl "http://127.0.0.1:5000/api/write_reg?addr=0x0014&data0=128"
curl "http://127.0.0.1:5000/api/write_reg?addr=0x0016&data0=1000"
```

## 关键状态字段

- `online`：节点是否在线。
- `has_telemetry_packet`：是否收到 FPGA 遥测包。
- `preview_available`：是否已有可显示预览帧。
- `status_text`：FPGA 状态位解析。
- `alarm_enable`：告警使能是否打开。
- `alarm_active`：在 `status_text` 中显示，表示当前是否触发告警。
- `alarm_event_count`：服务启动以来记录的告警触发次数。
- `alarm_events`：最近 20 条告警事件，包含时间、帧号、亮点数、阈值、ROI 和告警快照 URL。
- `current_*`：Linux 最近一次成功下发的运行参数镜像。
- `bright_count`：FPGA 侧统计出的亮点数量。
- `roi_sum`：FPGA 侧统计出的 ROI 亮度累加。

## 典型验证

```bash
curl "http://127.0.0.1:5000/api/command?name=buzzer_on"
curl "http://127.0.0.1:5000/api/apply_params?roi_x=320&roi_y=240&roi_w=160&roi_h=120&bright_threshold=40&alarm_count_threshold=1000&tx_mode=2"
sleep 1
curl http://127.0.0.1:5000/api/status
```

期望：

- `alarm_enable=true`
- `current_alarm_count_threshold=1000`
- `bright_count` 大于阈值时 `alarm_active=1`
- `error_code=0`
- `cmd_error=0`

## 实现结构

- `src/main.cpp`：启动入口。
- `src/service.cpp`：UDP、HTTP、状态管理、预览重组、命令下发。
- `src/config.cpp`：配置文件解析。
- `src/logger.cpp`：日志。
- `web/index.html`：本地控制台。
- `config/config.json`：默认配置。
