# Vivado 2022.2 IP 要求

这套源码需要你在 Vivado 中手动补两个时钟类 IP。

## 1. `clk_wiz_125m`

用途：

- 为 UDP / RGMII 发送链提供 `125 MHz` 时钟

建议配置：

- Input clock: `50 MHz`
- Output clock: `125 MHz`
- Reset port: enabled
- Locked port: enabled

## 2. `eth_phase_mmcm`

用途：

- 为 RGMII RX 采样链提供相位偏移后的 `125 MHz` 时钟

建议配置：

- Input clock: `125 MHz`
- Output clock: `125 MHz`
- Output phase: `90 degree`
- Reset port: enabled
- Locked port: enabled

## 3. `xpm_fifo_async`

说明：

- 不需要单独生成 IP
- 这是 Vivado 自带 XPM 宏，源码中直接实例化即可

## 可选

- `ILA`
  只有在你需要抓包、抓相机时序时再加，当前正式源码不依赖 ILA
