# DDR3 路线第一阶段说明

## 这一阶段做什么

先把 DDR3 路线做成一个清晰的 bring-up 工程：

- `OV2640 RGB565 -> FPGA 采集`
- `8bit DVP -> 16bit RGB565 打包`
- `写 FIFO -> MIG AXI -> DDR3`
- `从 DDR3 读回 -> 读 FIFO`
- 用 `LED` 观察相机初始化、DDR3 初始化、帧锁定和读回活动

## 这一阶段不做什么

- 不做 HDMI / VGA 显示
- 不做图像 UDP 上传
- 不做复杂多帧管理
- 不做 Linux 侧图像预览

## 新顶层

- `rtl/top/top_ov2640_ddr3_framebuffer.v`

## LED 含义

- `LED0`：心跳
- `LED1`：OV2640 初始化成功
- `LED2`：DDR3 初始化成功
- `LED3`：相机帧锁定
- `LED4`：采集/缓存使能
- `LED5`：至少看到一次 `frame_end_16`
- `LED6`：读回侧见过像素
- `LED7`：打包错相 / FIFO 满 / 初始化错误

## 你在 Vivado 里需要做的事

1. 新建工程
2. 顶层设为 `top_ov2640_ddr3_framebuffer`
3. 加入 `VIVADO_SOURCE_LIST_DDR3.md` 里列出的源码
4. 手动创建 `IP_REQUIREMENTS_DDR3.md` 里的 IP
5. 加入 `top_ov2640_ddr3_framebuffer.xdc`
6. 再从官方 DDR3 例程里复制 MIG/DDR3 引脚约束

## 官方例程建议

优先参考：

- `D:\桌面\学习计划\盘A_ACX750开发板标准配套资料\02 设计实例\高速收发器例程（含SFP和PCIE）\100T\ov5640_sfp_ddr3_vga_hdmi`

重点看：

- `ddr3_ctrl_2port.v`
- `fifo2mig_axi.v`
- `io.xdc`

## 下一阶段建议

当这一阶段确认：

- OV2640 初始化稳定
- DDR3 初始化稳定
- 能持续写入并读回
- `LED6` 能亮起

再继续做：

1. 读回侧接本地显示
2. 读回侧做抽帧上传
3. 再把 DDR3 路线并回主项目闭环
