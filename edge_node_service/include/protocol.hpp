// Linux 服务与 FPGA 固件之间的二进制协议定义。
// 这里固定遥测包、预览分片和命令包的字段布局，必须与 RTL 打包模块保持一致。
#pragma once

#include <cstdint>
#include <iomanip>
#include <sstream>
#include <string>
#include <vector>

namespace protocol {

constexpr std::size_t kFrameStatsPacketSize = 32;

constexpr std::size_t kCommandPacketSize = 20;

constexpr std::size_t kPreviewHeaderSize = 16;
constexpr std::uint8_t kPreviewMsgTypeJpeg = 0x10;
constexpr std::uint8_t kPreviewMsgTypeRgb565 = 0x12;

enum class CommandCode : std::uint8_t {
    WriteReg = 0x01,
    ReadReg = 0x02,
    StartCapture = 0x03,
    StopCapture = 0x04,
    QueryStatus = 0x05,
    ClearError = 0x06,
    BuzzerOn = 0x07,
    BuzzerOff = 0x08,
};

enum RegisterAddress : std::uint16_t {
    RegCtrl = 0x0000,
    RegStatus = 0x0001,
    RegRoiX = 0x0010,
    RegRoiY = 0x0011,
    RegRoiW = 0x0012,
    RegRoiH = 0x0013,
    RegBrightThreshold = 0x0014,
    RegTxMode = 0x0015,
    RegAlarmCountThreshold = 0x0016,
};

// 32 字节 FPGA 遥测包解析结果，与 RTL 状态包字段一一对应。
struct FrameStatsPacket {
    std::uint8_t magic0 = 0;
    std::uint8_t magic1 = 0;
    std::uint8_t version = 0;
    std::uint8_t msg_type = 0;
    std::uint16_t frame_id = 0;
    std::uint16_t status_bits = 0;
    std::uint32_t timestamp_low = 0;
    std::uint16_t frame_width = 0;
    std::uint16_t frame_height = 0;
    std::uint32_t active_pixel_count = 0;
    std::uint32_t roi_sum = 0;
    std::uint16_t bright_count = 0;
    std::uint16_t error_code = 0;
    std::uint8_t reserved0 = 0;
    std::uint8_t reserved1 = 0;
    std::uint8_t reserved2 = 0;
    std::uint8_t checksum = 0;
};

// 预览分片头解析结果，payload 指向当前 UDP 接收缓冲区中的图像载荷。
struct PreviewChunkPacket {
    std::uint8_t magic0 = 0;
    std::uint8_t magic1 = 0;
    std::uint8_t version = 0;
    std::uint8_t msg_type = 0;
    std::uint16_t frame_id = 0;
    std::uint16_t chunk_id = 0;
    std::uint16_t chunk_size = 0;
    std::uint8_t flags = 0;
    std::uint8_t reserved = 0;
    std::uint32_t chunk_offset = 0;
    const std::uint8_t* payload = nullptr;
};

inline std::uint16_t read_be16(const std::uint8_t* p) {
    return (static_cast<std::uint16_t>(p[0]) << 8U) |
           static_cast<std::uint16_t>(p[1]);
}

inline std::uint32_t read_be32(const std::uint8_t* p) {
    return (static_cast<std::uint32_t>(p[0]) << 24U) |
           (static_cast<std::uint32_t>(p[1]) << 16U) |
           (static_cast<std::uint32_t>(p[2]) << 8U) |
           static_cast<std::uint32_t>(p[3]);
}

inline void write_be16(std::uint8_t* p, std::uint16_t value) {
    p[0] = static_cast<std::uint8_t>((value >> 8U) & 0xFFU);
    p[1] = static_cast<std::uint8_t>(value & 0xFFU);
}

inline void write_be32(std::uint8_t* p, std::uint32_t value) {
    p[0] = static_cast<std::uint8_t>((value >> 24U) & 0xFFU);
    p[1] = static_cast<std::uint8_t>((value >> 16U) & 0xFFU);
    p[2] = static_cast<std::uint8_t>((value >> 8U) & 0xFFU);
    p[3] = static_cast<std::uint8_t>(value & 0xFFU);
}

inline std::uint8_t xor_checksum(const std::uint8_t* data, std::size_t len) {
    std::uint8_t value = 0;
    for (std::size_t i = 0; i < len; ++i) {
        value ^= data[i];
    }
    return value;
}

// 校验并解析固定 32 字节遥测包，所有多字节字段均按网络字节序读取。
inline bool parse_frame_stats_packet(
    const std::uint8_t* data,
    std::size_t len,
    FrameStatsPacket& out,
    std::string& err) {
    if (len != kFrameStatsPacketSize) {
        err = "packet length is not 32";
        return false;
    }
    if (data[0] != 0x45 || data[1] != 0x56) {
        err = "packet magic mismatch";
        return false;
    }
    if (xor_checksum(data, kFrameStatsPacketSize - 1) != data[kFrameStatsPacketSize - 1]) {
        err = "packet checksum mismatch";
        return false;
    }

    out.magic0 = data[0];
    out.magic1 = data[1];
    out.version = data[2];
    out.msg_type = data[3];
    out.frame_id = read_be16(&data[4]);
    out.status_bits = read_be16(&data[6]);
    out.timestamp_low = read_be32(&data[8]);
    out.frame_width = read_be16(&data[12]);
    out.frame_height = read_be16(&data[14]);
    out.active_pixel_count = read_be32(&data[16]);
    out.roi_sum = read_be32(&data[20]);
    out.bright_count = read_be16(&data[24]);
    out.error_code = read_be16(&data[26]);
    out.reserved0 = data[28];
    out.reserved1 = data[29];
    out.reserved2 = data[30];
    out.checksum = data[31];
    return true;
}

// 校验并解析预览分片头，分片载荷由调用方在接收缓冲区复用前复制。
inline bool parse_preview_chunk_packet(
    const std::uint8_t* data,
    std::size_t len,
    PreviewChunkPacket& out,
    std::string& err) {
    if (len < kPreviewHeaderSize) {
        err = "preview packet too short";
        return false;
    }
    if (data[0] != 0x4A || data[1] != 0x50) {
        err = "preview packet magic mismatch";
        return false;
    }

    out.magic0 = data[0];
    out.magic1 = data[1];
    out.version = data[2];
    out.msg_type = data[3];
    out.frame_id = read_be16(&data[4]);
    out.chunk_id = read_be16(&data[6]);
    out.chunk_size = read_be16(&data[8]);
    out.flags = data[10];
    out.reserved = data[11];
    out.chunk_offset = read_be32(&data[12]);
    out.payload = data + kPreviewHeaderSize;

    if (len != kPreviewHeaderSize + out.chunk_size) {
        err = "preview chunk length mismatch";
        return false;
    }
    return true;
}

// 构造 Linux 发往 FPGA 的统一命令包，并在最后一个字节写入异或校验。
inline std::vector<std::uint8_t> build_command_packet(
    CommandCode cmd,
    std::uint16_t seq,
    std::uint16_t addr,
    std::uint32_t data0,
    std::uint32_t data1) {
    std::vector<std::uint8_t> packet(kCommandPacketSize, 0);
    packet[0] = 0x43;
    packet[1] = 0x4D;
    packet[2] = 0x01;
    packet[3] = static_cast<std::uint8_t>(cmd);
    write_be16(&packet[4], seq);
    write_be16(&packet[6], addr);
    write_be32(&packet[8], data0);
    write_be32(&packet[12], data1);
    packet[19] = xor_checksum(packet.data(), 19);
    return packet;
}

inline const char* command_name(CommandCode code) {
    switch (code) {
    case CommandCode::WriteReg: return "write_reg";
    case CommandCode::ReadReg: return "read_reg";
    case CommandCode::StartCapture: return "start_capture";
    case CommandCode::StopCapture: return "stop_capture";
    case CommandCode::QueryStatus: return "query_status";
    case CommandCode::ClearError: return "clear_error";
    case CommandCode::BuzzerOn: return "buzzer_on";
    case CommandCode::BuzzerOff: return "buzzer_off";
    default: return "unknown";
    }
}

// 把硬件状态位展开为可读文本，便于网页展示和现场调试。
inline std::string status_bits_text(std::uint16_t status_bits) {
    std::ostringstream oss;
    oss << "cam_init_done=" << ((status_bits >> 0U) & 0x1U)
        << " frame_locked=" << ((status_bits >> 1U) & 0x1U)
        << " fifo_overflow=" << ((status_bits >> 2U) & 0x1U)
        << " udp_busy_or_drop=" << ((status_bits >> 3U) & 0x1U)
        << " capture_enable=" << ((status_bits >> 4U) & 0x1U)
        << " alarm_active=" << ((status_bits >> 5U) & 0x1U)
        << " phy_init_done=" << ((status_bits >> 6U) & 0x1U)
        << " cmd_error=" << ((status_bits >> 7U) & 0x1U)
        << " alarm_enable=" << ((status_bits >> 8U) & 0x1U)
        << " dbg_pkt_seen=" << ((status_bits >> 9U) & 0x1U)
        << " dbg_vsync_seen=" << ((status_bits >> 10U) & 0x1U)
        << " dbg_href_seen=" << ((status_bits >> 11U) & 0x1U)
        << " dbg_frame_start_seen=" << ((status_bits >> 12U) & 0x1U)
        << " dbg_frame_end_seen=" << ((status_bits >> 13U) & 0x1U)
        << " dbg_pix_valid_seen=" << ((status_bits >> 14U) & 0x1U)
        << " dbg_stats_wr_seen=" << ((status_bits >> 15U) & 0x1U);
    return oss.str();
}

inline std::string packet_brief(const FrameStatsPacket& packet) {
    std::ostringstream oss;
    oss << "msg_type=0x" << std::hex << std::setw(2) << std::setfill('0')
        << static_cast<int>(packet.msg_type)
        << " frame_id=" << std::dec << packet.frame_id
        << " size=" << packet.frame_width << "x" << packet.frame_height
        << " active=" << packet.active_pixel_count
        << " bright=" << packet.bright_count
        << " roi_sum=" << packet.roi_sum
        << " error=0x" << std::hex << std::setw(4) << std::setfill('0') << packet.error_code;
    return oss.str();
}

}
