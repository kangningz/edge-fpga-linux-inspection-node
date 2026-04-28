#pragma once

#include <cstdint>
#include <iomanip>
#include <sstream>
#include <string>
#include <vector>

namespace protocol {

// FPGA -> Linux telemetry packet. The RTL emits this compact 32-byte packet
// once per frame so Linux can update status without parsing the preview image.
constexpr std::size_t kFrameStatsPacketSize = 32;
// Linux -> FPGA command packet. Register writes and simple controls share this
// fixed layout, which keeps the FPGA UDP command parser small.
constexpr std::size_t kCommandPacketSize = 20;
// FPGA -> Linux preview chunk. Large RGB565/JPEG frames are split into chunks
// and reassembled by the service before being exposed through /api/preview.
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

// Preview packets carry a pointer into the received UDP buffer. The service
// must copy the payload before the receive buffer is reused by the next packet.
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

// Validate and decode the 32-byte FPGA status packet. Multi-byte fields are
// big-endian because the Verilog packet formatter writes network-order bytes.
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

// Decode one preview chunk. The first/last chunk flags let the service reset
// assembly cleanly if a frame is dropped or arrives out of order.
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

// Build the UDP command payload sent to the FPGA command parser. For register
// writes, addr selects the FPGA register and data0 carries the new value.
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

// Human-readable status text is useful for Web display and interview/demo
// debugging because the raw status_bits field is otherwise opaque.
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

} // namespace protocol
