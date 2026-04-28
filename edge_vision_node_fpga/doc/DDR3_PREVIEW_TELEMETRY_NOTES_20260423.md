# DDR3 Preview + Telemetry Notes (2026-04-23)

## Goal

This round moves the DDR3 preview design from:

- `OV2640 -> RGB565 -> DDR3 -> UDP preview`

to:

- `OV2640 -> RGB565 -> DDR3 preview`
- `OV2640 -> frame stats -> telemetry UDP`
- `Raspberry Pi service receives both preview and telemetry`

## RTL files touched

- `rtl/top/top_ov2640_ddr3_udp_preview.v`
- `rtl/buffer/edge_ddr3_framebuffer.v`
- `rtl/buffer/edge_ddr3_ctrl_2port.v`
- `rtl/buffer/edge_fifo2mig_axi.v`
- `rtl/net/rgb565_udp_preview_payload_gen.v`
- `rtl/preproc/vision_preprocess_core.v`
- `rtl/net/rgmii_to_gmii.v`
- `rtl/net/eth_udp_rx_gmii.v`
- `rtl/net/eth_phase_mmcm.v`
- `rtl/net/eth_phase_mmcm_clk_wiz.v`

## Extra RTL files required in Vivado

If they are not already in the project, add:

- `rtl/ctrl/vision_reg_bank.v`
- `rtl/ctrl/udp_cmd_packet_parser.v`
- `rtl/ctrl/cmd_async_fifo.v`
- `rtl/preproc/vision_preprocess_core.v`
- `rtl/preproc/stats_async_fifo.v`
- `rtl/net/frame_stats_packet_parallel.v`
- `rtl/net/vision32_payload_gen.v`
- `rtl/net/vision_udp_status_ctrl.v`
- `rtl/net/rgmii_to_gmii.v`
- `rtl/net/eth_udp_rx_gmii.v`
- `rtl/net/eth_phase_mmcm.v`
- `rtl/net/eth_phase_mmcm_clk_wiz.v`

## What changed

### 1. DDR3 path stability / FPS

- AXI write burst launch now waits for a full burst of FIFO data.
- AXI write data no longer pushes invalid beats when write FIFO becomes empty mid-burst.
- Framebuffer path now uses two DDR3 banks so capture and preview readback do not fully serialize.
- Preview generator keeps the latest pending frame if TX is busy.

### 2. Preview transport

- RGB565 preview UDP chunk size increased to `1400` bytes to reduce packet count.

### 3. Telemetry path

- Added `vision_preprocess_core` in the camera clock domain for ROI / threshold / alarm control.
- Added `stats_async_fifo` for camera-to-ethernet clock crossing.
- Added `frame_stats_packet_parallel` to build 32-byte `EV` telemetry packets.
- Added `vision_udp_status_ctrl` and `vision32_payload_gen`.
- Added a simple TX arbiter so preview and telemetry share the same UDP sender.

### 4. Status bits

`status_bits` are now aligned with the Raspberry Pi service parser:

- bit0: `cam_init_done`
- bit1: `frame_locked`
- bit2: `fifo_overflow`
- bit3: `udp_busy_or_drop`
- bit4: `capture_enable`
- bit5: `alarm_active`
- bit6: `phy_init_done`
- bit7: `cmd_error`
- bit9: `dbg_pkt_seen`
- bit10: `dbg_vsync_seen`
- bit11: `dbg_href_seen`
- bit12: `dbg_frame_start_seen`
- bit13: `dbg_frame_end_seen`
- bit14: `dbg_pix_valid_seen`
- bit15: `dbg_stats_wr_seen`

Current mapping notes:

- `fifo_overflow` is driven by stats FIFO overflow or write FIFO full.
- `udp_busy_or_drop` is currently driven by the UDP TX busy state.
- `capture_enable` comes from `vision_reg_bank` and currently defaults to `1`.
- `alarm_active` is generated once per frame from ROI `bright_count`.
- `cmd_error` comes from `vision_reg_bank`; camera init errors are still reported through `error_code`.
- `BEEP` is driven by `alarm_active`.

### 5. UDP command RX

- Added RGMII RX top-level ports.
- Added `eth_phase_mmcm`, `rgmii_to_gmii` and `eth_udp_rx_gmii`.
- Added `udp_cmd_packet_parser` and `cmd_async_fifo`.
- Linux `write_reg/apply_params/start_capture/stop_capture/clear_error/buzzer_on/buzzer_off` commands can now enter `vision_reg_bank`.

### 6. Configurable alarm threshold

- Added register `0x0016` for `alarm_count_threshold`.
- `alarm_active` is now driven by:
  - `alarm_enable == 1`
  - `bright_count >= alarm_count_threshold`
- Linux config / API / Web defaults now include `default_alarm_count_threshold`.

## Expected Linux-side result

After rebuilding FPGA and restarting the Pi service, `/api/status` should move from:

- `has_telemetry_packet=false`

to:

- `has_telemetry_packet=true`
- `preview_stream_only=false`
- non-zero `frame_id`
- `frame_width=800`
- `frame_height=600`
- non-zero `active_pixel_count`

## Validation sequence

1. Rebuild bitstream and program FPGA.
2. Restart Pi service.
3. Open `/api/status`.
4. Confirm telemetry fields are updating.
5. Confirm preview still updates normally.

## Known limitation

The RX path now uses a 90-degree shifted clock from `eth_phase_mmcm` before `rgmii_to_gmii`, matching the old working command-RX design more closely.
