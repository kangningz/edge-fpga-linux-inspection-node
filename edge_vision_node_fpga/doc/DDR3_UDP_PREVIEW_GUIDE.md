# DDR3 UDP Preview Guide

## 目标

这一版的目标是把 `OV2640 -> RGB565 -> DDR3 -> 读回 -> UDP 分片 -> Linux/Web 预览` 路线打通。

和 `top_ov2640_ddr3_framebuffer` 的区别：

- `top_ov2640_ddr3_framebuffer`
  - 用来做 DDR3 bring-up
  - 重点看 DDR3 初始化、整帧写入、整帧读回调试灯
- `top_ov2640_ddr3_udp_preview`
  - 用来做 DDR3 读回后的网络预览
  - 重点看树莓派 Web 页面是否能显示最近一帧

## Vivado 顶层

使用这个顶层：

- `D:\桌面\1\edge_vision_node_fpga\rtl\top\top_ov2640_ddr3_udp_preview.v`

## 需要加入的 RTL 文件

### 顶层

- `D:\桌面\1\edge_vision_node_fpga\rtl\top\top_ov2640_ddr3_udp_preview.v`

### DDR3 / Buffer

- `D:\桌面\1\edge_vision_node_fpga\rtl\buffer\edge_ddr3_framebuffer.v`
- `D:\桌面\1\edge_vision_node_fpga\rtl\buffer\edge_ddr3_ctrl_2port.v`
- `D:\桌面\1\edge_vision_node_fpga\rtl\buffer\edge_fifo2mig_axi.v`
- `D:\桌面\1\edge_vision_node_fpga\rtl\buffer\ov2640_rgb565_packer.v`

### Camera

- `D:\桌面\1\edge_vision_node_fpga\rtl\camera\ov2640_capture_if.v`
- `D:\桌面\1\edge_vision_node_fpga\rtl\camera\frame_sync_counter.v`
- `D:\桌面\1\edge_vision_node_fpga\rtl\camera\ov2640_sccb_init.v`
- `D:\桌面\1\edge_vision_node_fpga\rtl\camera\ov2640_init_table_svga_rgb565.v`
- `D:\桌面\1\edge_vision_node_fpga\rtl\camera\sccb_master_write.v`

### Clock / Reset

- `D:\桌面\1\edge_vision_node_fpga\rtl\clk_rst\clk_rst_mgr.v`

### Network

- `D:\桌面\1\edge_vision_node_fpga\rtl\net\edge_eth_udp_cfg.v`
- `D:\桌面\1\edge_vision_node_fpga\rtl\net\eth_udp_tx_gmii.v`
- `D:\桌面\1\edge_vision_node_fpga\rtl\net\gmii_to_rgmii.v`
- `D:\桌面\1\edge_vision_node_fpga\rtl\net\crc32_d8.v`
- `D:\桌面\1\edge_vision_node_fpga\rtl\net\ip_checksum.v`
- `D:\桌面\1\edge_vision_node_fpga\rtl\net\rgb565_udp_preview_payload_gen.v`

## 需要生成的 IP

- `clk_wiz_ddr3_200m`
- `clk_wiz_eth125m`
- `wr_ddr3_fifo`
- `rd_ddr3_fifo`
- `mig_7series_0`

## IP 关键要求

### clk_wiz_eth125m

- 输入：`50 MHz`
- 输出：`125 MHz`
- 端口风格：
  - `clk_in1`
  - `reset`
  - `clk_out1`
  - `locked`

### wr_ddr3_fifo

- `Independent Clocks Block RAM`
- `Standard FIFO`
- `Write Width = 16`
- `Write Depth = 512`
- `Read Width = 128`
- 打开：
  - `Reset Pin`
  - `Enable Reset Synchronization`
  - `Enable Safety Circuit`
  - `Write Data Count`
  - `Read Data Count`

### rd_ddr3_fifo

- `Independent Clocks Block RAM`
- `Standard FIFO`
- `Write Width = 128`
- `Write Depth = 64`
- `Read Width = 16`
- 打开：
  - `Reset Pin`
  - `Enable Reset Synchronization`
  - `Enable Safety Circuit`
  - `Write Data Count`
- 这版不要求 `Read Data Count`

### mig_7series_0

关键项：

- `DDR3 SDRAM`
- `AXI`
- `Clock Period = 2500 ps`
- `Input Clock = 5000 ps (200 MHz)`
- `PHY Ratio = 4:1`
- `Memory Part = MT41K256M16XX-125`
- `Data Width = 32`
- `AXI Data Width = 128`
- `ID Width = 4`
- `Ordering = Strict`
- `BANK_ROW_COLUMN`
- `System Clock = No Buffer`
- `Reference Clock = Use System Clock`
- `System Reset Polarity = ACTIVE LOW`

## 约束文件

启用：

- `D:\桌面\1\edge_vision_node_fpga\constrs\top_ov2640_ddr3_udp_preview.xdc`
- 当前工程生成的 `mig_7series_0.xdc`

不要启用：

- 官方旧工程里的 `mig_7series_0.xdc`
- `mig_7series_0_ooc.xdc`

## LED 含义

- `LED0`：心跳
- `LED1`：相机初始化成功
- `LED2`：外部 `clk_wiz_ddr3_200m.locked`
- `LED3`：`MIG mmcm_locked`
- `LED4`：`frame_locked`
- `LED5`：`init_calib_complete`
- `LED6`：至少见过一个预览分片发送完成
- `LED7`：至少见过一帧预览图发送完成

## Linux 端

Linux 端继续使用现有工程：

- `D:\桌面\1\edge_node_service`

重编命令：

```bash
cd ~/edge_node_service/build
cmake ..
make -j4
sudo systemctl restart edge-node.service
```

查看：

- `/api/status`
- `/api/preview`
- Web 页面右侧预览框

## 成功标志

### FPGA 板上

- `LED1~LED5` 亮
- `LED6` 亮：说明至少发出过预览分片
- `LED7` 亮：说明至少完成过一帧预览图发送

### 树莓派 / Web

- `/api/status` 中：
  - `preview_available = true`
  - `preview_frames_completed > 0`
  - `preview_bytes > 0`
- 页面右侧能看到周期性刷新的相机图像
