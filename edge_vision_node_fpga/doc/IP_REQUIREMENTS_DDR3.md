# DDR3 路线新增 IP 要求

本文件只说明 DDR3 路线第一阶段新增的 IP。

推荐参考官方例程：

- `D:\桌面\学习计划\盘A_ACX750开发板标准配套资料\02 设计实例\高速收发器例程（含SFP和PCIE）\100T\ov5640_sfp_ddr3_vga_hdmi`

## 1. `clk_wiz_ddr3_200m`

用途：

- 给 `mig_7series_0.sys_clk_i` 提供参考时钟

建议配置：

- Input clock: `50 MHz`
- Output clock: `200 MHz`
- Reset port: enabled
- Locked port: enabled

## 2. `wr_ddr3_fifo`

用途：

- 相机 `camera_pclk` 域 `16bit RGB565` 写入
- `ui_clk` 域 `128bit` 读出

建议配置：

- FIFO Generator / Independent Clocks
- Write width: `16`
- Read width: `128`
- Write depth: `512`
- 开启 `wr_data_count`
- 开启 `rd_data_count`
- 开启 `wr_rst_busy`
- 开启 `rd_rst_busy`

## 3. `rd_ddr3_fifo`

用途：

- `ui_clk` 域 `128bit` 写入
- 读取侧时钟域 `16bit` 读出

建议配置：

- FIFO Generator / Independent Clocks
- Write width: `128`
- Read width: `16`
- Write depth: `64`
- 开启 `wr_data_count`
- 开启 `rd_data_count`
- 开启 `wr_rst_busy`
- 开启 `rd_rst_busy`

## 4. `mig_7series_0`

用途：

- ACX750 板载 DDR3 控制器

建议：

- 不要从零重新配
- 直接复用官方 MIG 配置和约束
- UI AXI 数据宽度应保持 `128bit`
- DDR3 接口应保持 `x32`

## 5. 需要手动合并的约束

`top_ov2640_ddr3_framebuffer.xdc` 只给了：

- `FPGA_CLK`
- `S0`
- `UART_TXD`
- `LED0..LED7`
- `BEEP`
- `camera_*`

DDR3 相关约束请直接从官方 DDR3 例程复制：

- `ddr3_dq[31:0]`
- `ddr3_dqs_n[3:0]`
- `ddr3_dqs_p[3:0]`
- `ddr3_addr[14:0]`
- `ddr3_ba[2:0]`
- `ddr3_ras_n / ddr3_cas_n / ddr3_we_n`
- `ddr3_reset_n`
- `ddr3_ck_p / ddr3_ck_n`
- `ddr3_cke / ddr3_cs_n / ddr3_dm / ddr3_odt`
