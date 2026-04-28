#include "service.hpp"

#include <algorithm>
#include <array>
#include <arpa/inet.h>
#include <cerrno>
#include <cstring>
#include <fstream>
#include <iomanip>
#include <netinet/in.h>
#include <sstream>
#include <sys/socket.h>
#include <unistd.h>

namespace {

constexpr int kHttpBacklog = 8;
constexpr auto kPreviewSnapshotInterval = std::chrono::seconds(1);

bool send_all(int fd, const char* data, std::size_t size) {
    std::size_t sent_total = 0;
    while (sent_total < size) {
        const ssize_t sent = ::send(fd, data + sent_total, size - sent_total, 0);
        if (sent < 0) {
            if (errno == EINTR) {
                continue;
            }
            return false;
        }
        if (sent == 0) {
            return false;
        }
        sent_total += static_cast<std::size_t>(sent);
    }
    return true;
}

std::string build_binary_http_response(
    const std::string& status_line,
    const std::string& content_type,
    const std::uint8_t* data,
    std::size_t size) {
    std::ostringstream header;
    header << "HTTP/1.1 " << status_line << "\r\n";
    header << "Content-Type: " << content_type << "\r\n";
    header << "Content-Length: " << size << "\r\n";
    header << "Cache-Control: no-store\r\n";
    header << "Connection: close\r\n\r\n";

    std::string response = header.str();
    if (data != nullptr && size != 0) {
        response.append(reinterpret_cast<const char*>(data), size);
    }
    return response;
}

bool write_binary_file(const std::filesystem::path& path, const std::vector<std::uint8_t>& data) {
    std::error_code ec;
    std::filesystem::create_directories(path.parent_path(), ec);

    const auto temp_path = path.string() + ".tmp";
    {
        std::ofstream ofs(temp_path, std::ios::binary | std::ios::trunc);
        if (!ofs.is_open()) {
            return false;
        }
        if (!data.empty()) {
            ofs.write(reinterpret_cast<const char*>(data.data()), static_cast<std::streamsize>(data.size()));
        }
        if (!ofs.good()) {
            return false;
        }
    }

    std::filesystem::rename(temp_path, path, ec);
    if (!ec) {
        return true;
    }

    ec.clear();
    std::filesystem::copy_file(temp_path, path, std::filesystem::copy_options::overwrite_existing, ec);
    std::filesystem::remove(temp_path, ec);
    return !ec;
}

std::string hex_prefix(const std::vector<std::uint8_t>& data, std::size_t n) {
    std::ostringstream oss;
    oss << std::hex << std::setfill('0');
    const std::size_t count = std::min(n, data.size());
    for (std::size_t i = 0; i < count; ++i) {
        if (i != 0) {
            oss << ' ';
        }
        oss << std::setw(2) << static_cast<int>(data[i]);
    }
    return oss.str();
}

std::string hex_suffix(const std::vector<std::uint8_t>& data, std::size_t n) {
    std::ostringstream oss;
    oss << std::hex << std::setfill('0');
    const std::size_t count = std::min(n, data.size());
    const std::size_t start = data.size() - count;
    for (std::size_t i = start; i < data.size(); ++i) {
        if (i != start) {
            oss << ' ';
        }
        oss << std::setw(2) << static_cast<int>(data[i]);
    }
    return oss.str();
}

std::string format_system_time(const std::chrono::system_clock::time_point& tp) {
    if (tp.time_since_epoch().count() == 0) {
        return "n/a";
    }

    const auto t = std::chrono::system_clock::to_time_t(tp);
    std::tm tm_buf{};
#if defined(_WIN32)
    localtime_s(&tm_buf, &t);
#else
    localtime_r(&t, &tm_buf);
#endif

    std::ostringstream oss;
    oss << std::put_time(&tm_buf, "%Y-%m-%d %H:%M:%S");
    return oss.str();
}

std::string compact_system_time(const std::chrono::system_clock::time_point& tp) {
    const auto t = std::chrono::system_clock::to_time_t(tp);
    std::tm tm_buf{};
#if defined(_WIN32)
    localtime_s(&tm_buf, &t);
#else
    localtime_r(&t, &tm_buf);
#endif

    std::ostringstream oss;
    oss << std::put_time(&tm_buf, "%Y%m%d_%H%M%S");
    return oss.str();
}

std::string guess_content_type(const std::string& path) {
    if (path.size() >= 5 && path.substr(path.size() - 5) == ".html") {
        return "text/html; charset=utf-8";
    }
    if (path.size() >= 3 && path.substr(path.size() - 3) == ".js") {
        return "application/javascript; charset=utf-8";
    }
    if (path.size() >= 4 && path.substr(path.size() - 4) == ".css") {
        return "text/css; charset=utf-8";
    }
    if ((path.size() >= 4 && path.substr(path.size() - 4) == ".jpg") ||
        (path.size() >= 5 && path.substr(path.size() - 5) == ".jpeg")) {
        return "image/jpeg";
    }
    if (path.size() >= 4 && path.substr(path.size() - 4) == ".bmp") {
        return "image/bmp";
    }
    return "text/plain; charset=utf-8";
}

void write_le16(std::uint8_t* p, std::uint16_t value) {
    p[0] = static_cast<std::uint8_t>(value & 0xFFU);
    p[1] = static_cast<std::uint8_t>((value >> 8U) & 0xFFU);
}

void write_le32(std::uint8_t* p, std::uint32_t value) {
    p[0] = static_cast<std::uint8_t>(value & 0xFFU);
    p[1] = static_cast<std::uint8_t>((value >> 8U) & 0xFFU);
    p[2] = static_cast<std::uint8_t>((value >> 16U) & 0xFFU);
    p[3] = static_cast<std::uint8_t>((value >> 24U) & 0xFFU);
}

std::vector<std::uint8_t> rgb565_to_bmp(
    const std::uint8_t* src,
    std::uint16_t width,
    std::uint16_t height) {
    if (src == nullptr || width == 0 || height == 0) {
        return {};
    }

    const std::uint32_t row_bytes = static_cast<std::uint32_t>(width) * 3U;
    const std::uint32_t row_stride = (row_bytes + 3U) & ~3U;
    const std::uint32_t pixel_bytes = row_stride * static_cast<std::uint32_t>(height);
    const std::uint32_t file_size = 54U + pixel_bytes;

    std::vector<std::uint8_t> bmp(file_size, 0);
    bmp[0] = 'B';
    bmp[1] = 'M';
    write_le32(&bmp[2], file_size);
    write_le32(&bmp[10], 54U);
    write_le32(&bmp[14], 40U);
    write_le32(&bmp[18], width);
    write_le32(&bmp[22], height);
    write_le16(&bmp[26], 1U);
    write_le16(&bmp[28], 24U);
    write_le32(&bmp[34], pixel_bytes);

    for (std::uint32_t y = 0; y < height; ++y) {
        const std::uint32_t src_y = height - 1U - y;
        const std::uint32_t src_row_off = src_y * static_cast<std::uint32_t>(width) * 2U;
        const std::uint32_t dst_row_off = 54U + y * row_stride;
        for (std::uint32_t x = 0; x < width; ++x) {
            const std::uint32_t src_off = src_row_off + x * 2U;
            const std::uint16_t pixel =
                static_cast<std::uint16_t>(src[src_off]) |
                (static_cast<std::uint16_t>(src[src_off + 1U]) << 8U);
            const std::uint8_t r = static_cast<std::uint8_t>(((pixel >> 11U) & 0x1FU) * 255U / 31U);
            const std::uint8_t g = static_cast<std::uint8_t>(((pixel >> 5U) & 0x3FU) * 255U / 63U);
            const std::uint8_t b = static_cast<std::uint8_t>((pixel & 0x1FU) * 255U / 31U);
            const std::uint32_t dst_off = dst_row_off + x * 3U;
            bmp[dst_off + 0U] = b;
            bmp[dst_off + 1U] = g;
            bmp[dst_off + 2U] = r;
        }
    }

    return bmp;
}

std::vector<std::uint8_t> rgb565_swapped_to_bmp(
    const std::uint8_t* src,
    std::uint16_t width,
    std::uint16_t height) {
    if (src == nullptr || width == 0 || height == 0) {
        return {};
    }

    const std::uint32_t row_bytes = static_cast<std::uint32_t>(width) * 3U;
    const std::uint32_t row_stride = (row_bytes + 3U) & ~3U;
    const std::uint32_t pixel_bytes = row_stride * static_cast<std::uint32_t>(height);
    const std::uint32_t file_size = 54U + pixel_bytes;

    std::vector<std::uint8_t> bmp(file_size, 0);
    bmp[0] = 'B';
    bmp[1] = 'M';
    write_le32(&bmp[2], file_size);
    write_le32(&bmp[10], 54U);
    write_le32(&bmp[14], 40U);
    write_le32(&bmp[18], width);
    write_le32(&bmp[22], height);
    write_le16(&bmp[26], 1U);
    write_le16(&bmp[28], 24U);
    write_le32(&bmp[34], pixel_bytes);

    for (std::uint32_t y = 0; y < height; ++y) {
        const std::uint32_t src_y = height - 1U - y;
        const std::uint32_t src_row_off = src_y * static_cast<std::uint32_t>(width) * 2U;
        const std::uint32_t dst_row_off = 54U + y * row_stride;
        for (std::uint32_t x = 0; x < width; ++x) {
            const std::uint32_t src_off = src_row_off + x * 2U;
            const std::uint16_t pixel =
                static_cast<std::uint16_t>(src[src_off + 1U]) |
                (static_cast<std::uint16_t>(src[src_off]) << 8U);
            const std::uint8_t r = static_cast<std::uint8_t>(((pixel >> 11U) & 0x1FU) * 255U / 31U);
            const std::uint8_t g = static_cast<std::uint8_t>(((pixel >> 5U) & 0x3FU) * 255U / 63U);
            const std::uint8_t b = static_cast<std::uint8_t>((pixel & 0x1FU) * 255U / 31U);
            const std::uint32_t dst_off = dst_row_off + x * 3U;
            bmp[dst_off + 0U] = b;
            bmp[dst_off + 1U] = g;
            bmp[dst_off + 2U] = r;
        }
    }

    return bmp;
}

std::uint8_t clamp_u8(int value) {
    return static_cast<std::uint8_t>(std::clamp(value, 0, 255));
}

void yuv_to_rgb(
    int y,
    int u,
    int v,
    std::uint8_t& r,
    std::uint8_t& g,
    std::uint8_t& b) {
    const int c = y - 16;
    const int d = u - 128;
    const int e = v - 128;
    const int r_tmp = (298 * c + 409 * e + 128) >> 8;
    const int g_tmp = (298 * c - 100 * d - 208 * e + 128) >> 8;
    const int b_tmp = (298 * c + 516 * d + 128) >> 8;
    r = clamp_u8(r_tmp);
    g = clamp_u8(g_tmp);
    b = clamp_u8(b_tmp);
}

std::vector<std::uint8_t> yuv422_to_bmp(
    const std::uint8_t* src,
    std::uint16_t width,
    std::uint16_t height,
    bool uyvy_mode) {
    if (src == nullptr || width == 0 || height == 0) {
        return {};
    }

    const std::uint32_t row_bytes = static_cast<std::uint32_t>(width) * 3U;
    const std::uint32_t row_stride = (row_bytes + 3U) & ~3U;
    const std::uint32_t pixel_bytes = row_stride * static_cast<std::uint32_t>(height);
    const std::uint32_t file_size = 54U + pixel_bytes;

    std::vector<std::uint8_t> bmp(file_size, 0);
    bmp[0] = 'B';
    bmp[1] = 'M';
    write_le32(&bmp[2], file_size);
    write_le32(&bmp[10], 54U);
    write_le32(&bmp[14], 40U);
    write_le32(&bmp[18], width);
    write_le32(&bmp[22], height);
    write_le16(&bmp[26], 1U);
    write_le16(&bmp[28], 24U);
    write_le32(&bmp[34], pixel_bytes);

    for (std::uint32_t y = 0; y < height; ++y) {
        const std::uint32_t src_y = height - 1U - y;
        const std::uint32_t src_row_off = src_y * static_cast<std::uint32_t>(width) * 2U;
        const std::uint32_t dst_row_off = 54U + y * row_stride;
        for (std::uint32_t x = 0; x < width; x += 2U) {
            const std::uint32_t src_off = src_row_off + x * 2U;
            const std::uint8_t b0 = src[src_off + 0U];
            const std::uint8_t b1 = src[src_off + 1U];
            const std::uint8_t b2 = src[src_off + 2U];
            const std::uint8_t b3 = src[src_off + 3U];

            int y0 = 0;
            int y1 = 0;
            int u = 128;
            int v = 128;
            if (uyvy_mode) {
                u = b0;
                y0 = b1;
                v = b2;
                y1 = b3;
            } else {
                y0 = b0;
                u = b1;
                y1 = b2;
                v = b3;
            }

            std::uint8_t r0 = 0;
            std::uint8_t g0 = 0;
            std::uint8_t bl0 = 0;
            std::uint8_t r1 = 0;
            std::uint8_t g1 = 0;
            std::uint8_t bl1 = 0;
            yuv_to_rgb(y0, u, v, r0, g0, bl0);
            yuv_to_rgb(y1, u, v, r1, g1, bl1);

            const std::uint32_t dst_off0 = dst_row_off + x * 3U;
            bmp[dst_off0 + 0U] = bl0;
            bmp[dst_off0 + 1U] = g0;
            bmp[dst_off0 + 2U] = r0;

            if (x + 1U < width) {
                const std::uint32_t dst_off1 = dst_row_off + (x + 1U) * 3U;
                bmp[dst_off1 + 0U] = bl1;
                bmp[dst_off1 + 1U] = g1;
                bmp[dst_off1 + 2U] = r1;
            }
        }
    }

    return bmp;
}

std::vector<std::uint8_t> build_preview_debug_image(
    const std::vector<std::uint8_t>& payload,
    const std::string& decode_mode,
    std::string& content_type,
    std::string& format_text) {
    content_type = "image/bmp";
    format_text = decode_mode;

    if (payload.size() < 4) {
        return {};
    }

    const std::uint16_t width = protocol::read_be16(payload.data());
    const std::uint16_t height = protocol::read_be16(payload.data() + 2);
    const std::size_t expected_bytes =
        4U + static_cast<std::size_t>(width) * static_cast<std::size_t>(height) * 2U;
    if (width == 0 || height == 0 || payload.size() != expected_bytes) {
        return {};
    }

    const std::uint8_t* pixels = payload.data() + 4;
    if (decode_mode == "rgb565_swap") {
        format_text = "rgb565_swap_bmp";
        return rgb565_swapped_to_bmp(pixels, width, height);
    }
    if (decode_mode == "yuyv") {
        format_text = "yuyv_bmp";
        return yuv422_to_bmp(pixels, width, height, false);
    }
    if (decode_mode == "uyvy") {
        format_text = "uyvy_bmp";
        return yuv422_to_bmp(pixels, width, height, true);
    }

    format_text = "rgb565_bmp";
    return rgb565_to_bmp(pixels, width, height);
}

} // namespace

EdgeNodeService::EdgeNodeService(std::string config_path, ServiceConfig config, Logger& logger)
    : config_path_(std::move(config_path)),
      config_(std::move(config)),
      logger_(logger),
      next_seq_(config_.initial_seq) {
    current_params_.roi_x = config_.default_roi_x;
    current_params_.roi_y = config_.default_roi_y;
    current_params_.roi_w = config_.default_roi_w;
    current_params_.roi_h = config_.default_roi_h;
    current_params_.bright_threshold = config_.default_bright_threshold;
    current_params_.alarm_count_threshold = config_.default_alarm_count_threshold;
    current_params_.tx_mode = config_.default_tx_mode;
}

EdgeNodeService::~EdgeNodeService() {
    stop();
}

bool EdgeNodeService::start() {
    std::string err;
    if (!open_sockets(err)) {
        logger_.error("socket setup failed: " + err);
        return false;
    }

    stop_requested_.store(false);
    rx_thread_ = std::thread(&EdgeNodeService::rx_loop, this);
    watchdog_thread_ = std::thread(&EdgeNodeService::watchdog_loop, this);
    http_thread_ = std::thread(&EdgeNodeService::http_loop, this);

    if (config_.auto_initialize) {
        std::string init_err;
        if (!apply_default_registers(init_err)) {
            logger_.warn("default register write failed during startup: " + init_err);
        } else {
            logger_.info("default register set applied");
        }
    }

    if (config_.auto_start_capture) {
        std::string cmd_err;
        if (!send_simple_command(protocol::CommandCode::StartCapture, cmd_err)) {
            logger_.warn("startup capture command failed: " + cmd_err);
        } else {
            logger_.info("startup capture command sent");
        }
    }

    logger_.info("service started");
    return true;
}

void EdgeNodeService::stop() {
    const bool already_stopping = stop_requested_.exchange(true);
    if (already_stopping) {
        return;
    }

    close_sockets();

    if (rx_thread_.joinable()) {
        rx_thread_.join();
    }
    if (watchdog_thread_.joinable()) {
        watchdog_thread_.join();
    }
    if (http_thread_.joinable()) {
        http_thread_.join();
    }

    logger_.info("service stopped");
}

bool EdgeNodeService::open_sockets(std::string& err) {
    std::lock_guard<std::mutex> lock(config_mutex_);

    rx_socket_ = ::socket(AF_INET, SOCK_DGRAM, 0);
    tx_socket_ = ::socket(AF_INET, SOCK_DGRAM, 0);
    http_socket_ = ::socket(AF_INET, SOCK_STREAM, 0);
    if (rx_socket_ < 0 || tx_socket_ < 0 || http_socket_ < 0) {
        err = "socket() failed";
        close_sockets();
        return false;
    }

    const int reuse = 1;
    ::setsockopt(rx_socket_, SOL_SOCKET, SO_REUSEADDR, &reuse, sizeof(reuse));
    ::setsockopt(http_socket_, SOL_SOCKET, SO_REUSEADDR, &reuse, sizeof(reuse));

    const timeval tv{
        config_.socket_timeout_ms / 1000,
        (config_.socket_timeout_ms % 1000) * 1000
    };
    ::setsockopt(rx_socket_, SOL_SOCKET, SO_RCVTIMEO, &tv, sizeof(tv));
    ::setsockopt(http_socket_, SOL_SOCKET, SO_RCVTIMEO, &tv, sizeof(tv));

    sockaddr_in rx_addr{};
    rx_addr.sin_family = AF_INET;
    rx_addr.sin_port = htons(static_cast<std::uint16_t>(config_.bind_port));
    if (::inet_pton(AF_INET, config_.bind_ip.c_str(), &rx_addr.sin_addr) != 1) {
        err = "invalid bind_ip";
        close_sockets();
        return false;
    }
    if (::bind(rx_socket_, reinterpret_cast<sockaddr*>(&rx_addr), sizeof(rx_addr)) < 0) {
        err = "bind UDP failed: " + std::string(std::strerror(errno));
        close_sockets();
        return false;
    }

    sockaddr_in http_addr{};
    http_addr.sin_family = AF_INET;
    http_addr.sin_port = htons(static_cast<std::uint16_t>(config_.http_port));
    if (::inet_pton(AF_INET, config_.http_bind_ip.c_str(), &http_addr.sin_addr) != 1) {
        err = "invalid http_bind_ip";
        close_sockets();
        return false;
    }
    if (::bind(http_socket_, reinterpret_cast<sockaddr*>(&http_addr), sizeof(http_addr)) < 0) {
        err = "bind HTTP failed: " + std::string(std::strerror(errno));
        close_sockets();
        return false;
    }
    if (::listen(http_socket_, kHttpBacklog) < 0) {
        err = "listen HTTP failed: " + std::string(std::strerror(errno));
        close_sockets();
        return false;
    }

    if (std::filesystem::exists(config_path_)) {
        last_config_mtime_ = std::filesystem::last_write_time(config_path_);
        last_config_seen_ = true;
    }

    err.clear();
    return true;
}

void EdgeNodeService::close_sockets() {
    const int sockets[] = {rx_socket_, tx_socket_, http_socket_};
    for (int fd : sockets) {
        if (fd >= 0) {
            ::close(fd);
        }
    }
    rx_socket_ = -1;
    tx_socket_ = -1;
    http_socket_ = -1;
}

void EdgeNodeService::record_event(const std::string& event_text) {
    std::lock_guard<std::mutex> lock(state_mutex_);
    state_.recent_events.push_front(now_iso8601() + " " + event_text);
    while (state_.recent_events.size() > 20) {
        state_.recent_events.pop_back();
    }
}

void EdgeNodeService::rx_loop() {
    std::array<std::uint8_t, 2048> buffer{};

    while (!stop_requested_.load()) {
        sockaddr_in src{};
        socklen_t src_len = sizeof(src);
        const ssize_t received = ::recvfrom(
            rx_socket_,
            buffer.data(),
            buffer.size(),
            0,
            reinterpret_cast<sockaddr*>(&src),
            &src_len);

        if (received < 0) {
            if (errno == EAGAIN || errno == EWOULDBLOCK || errno == EINTR) {
                continue;
            }
            logger_.warn("recvfrom failed: " + std::string(std::strerror(errno)));
            continue;
        }

        char ip_text[64] = {0};
        ::inet_ntop(AF_INET, &src.sin_addr, ip_text, sizeof(ip_text));
        const int peer_port = ntohs(src.sin_port);

        bool first_packet = false;
        const auto rx_steady = std::chrono::steady_clock::now();
        const auto rx_wall = std::chrono::system_clock::now();

        protocol::FrameStatsPacket packet;
        std::string parse_err;
        if (protocol::parse_frame_stats_packet(buffer.data(), static_cast<std::size_t>(received), packet, parse_err)) {
            RuntimeParams params_snapshot;
            {
                std::lock_guard<std::mutex> params_lock(params_mutex_);
                params_snapshot = current_params_;
            }
            {
                std::lock_guard<std::mutex> lock(state_mutex_);
                first_packet = !state_.has_packet;
                ++state_.rx_packets;
                state_.online = true;
                state_.has_packet = true;
                state_.has_telemetry_packet = true;
                state_.last_packet = packet;
                state_.last_peer_ip = ip_text;
                state_.last_peer_port = peer_port;
                state_.last_rx_steady = rx_steady;
                state_.last_rx_wall = rx_wall;
                state_.last_error = "none";
            }

            const bool alarm_active = ((packet.status_bits >> 5U) & 0x1U) != 0;
            bool should_record_alarm = false;
            {
                std::lock_guard<std::mutex> alarm_lock(alarm_mutex_);
                should_record_alarm = alarm_active && !alarm_state_.last_alarm_active;
                alarm_state_.last_alarm_active = alarm_active;
            }

            bool alarm_event_created = false;
            AlarmEvent alarm_event;
            if (should_record_alarm) {
                alarm_event.timestamp = now_iso8601();
                alarm_event.frame_id = packet.frame_id;
                alarm_event.bright_count = packet.bright_count;
                alarm_event.alarm_count_threshold = params_snapshot.alarm_count_threshold;
                alarm_event.roi_sum = packet.roi_sum;
                alarm_event.roi_x = params_snapshot.roi_x;
                alarm_event.roi_y = params_snapshot.roi_y;
                alarm_event.roi_w = params_snapshot.roi_w;
                alarm_event.roi_h = params_snapshot.roi_h;

                std::vector<std::uint8_t> snapshot_image;
                std::string snapshot_ext = ".bin";
                {
                    std::lock_guard<std::mutex> preview_lock(preview_mutex_);
                    if (preview_.available && !preview_.latest_image.empty()) {
                        snapshot_image = preview_.latest_image;
                        if (preview_.latest_content_type == "image/bmp") {
                            snapshot_ext = ".bmp";
                        } else if (preview_.latest_content_type == "image/jpeg") {
                            snapshot_ext = ".jpg";
                        }
                    }
                }

                if (!snapshot_image.empty()) {
                    ServiceConfig cfg_copy;
                    {
                        std::lock_guard<std::mutex> cfg_lock(config_mutex_);
                        cfg_copy = config_;
                    }
                    const std::string snapshot_name =
                        "alarm_" + compact_system_time(rx_wall) +
                        "_frame" + std::to_string(packet.frame_id) + snapshot_ext;
                    const auto snapshot_path =
                        std::filesystem::path(cfg_copy.static_dir) /
                        "alarm_snapshots" /
                        snapshot_name;
                    if (write_binary_file(snapshot_path, snapshot_image)) {
                        alarm_event.image_url = "/static/alarm_snapshots/" + snapshot_name;
                    } else {
                        logger_.warn("failed to write alarm snapshot to " + snapshot_path.string());
                    }
                }

                {
                    std::lock_guard<std::mutex> alarm_lock(alarm_mutex_);
                    alarm_state_.events.push_front(alarm_event);
                    ++alarm_state_.event_count;
                    while (alarm_state_.events.size() > 20) {
                        alarm_state_.events.pop_back();
                    }
                }
                alarm_event_created = true;
            }

            if (first_packet) {
                record_event("telemetry online from " + std::string(ip_text) + ":" + std::to_string(peer_port));
            }
            if (alarm_event_created) {
                const std::string text =
                    "alarm triggered frame=" + std::to_string(alarm_event.frame_id) +
                    " bright=" + std::to_string(alarm_event.bright_count) +
                    " threshold=" + std::to_string(alarm_event.alarm_count_threshold);
                record_event(text);
                logger_.warn(text);
            }

            if ((packet.frame_id % 30U) == 0U) {
                logger_.info("rx " + std::string(ip_text) + ":" + std::to_string(peer_port) + " " + protocol::packet_brief(packet));
            }
            continue;
        }

        protocol::PreviewChunkPacket preview_packet;
        std::string preview_err;
        if (protocol::parse_preview_chunk_packet(buffer.data(), static_cast<std::size_t>(received), preview_packet, preview_err)) {
            {
                std::lock_guard<std::mutex> lock(state_mutex_);
                first_packet = !state_.has_packet;
                ++state_.rx_packets;
                state_.online = true;
                state_.has_packet = true;
                state_.last_peer_ip = ip_text;
                state_.last_peer_port = peer_port;
                state_.last_rx_steady = rx_steady;
                state_.last_rx_wall = rx_wall;
                state_.last_error = "none";
            }

            bool preview_complete = false;
            std::uint16_t completed_frame_id = 0;
            std::string completed_file_name = "latest_preview.jpg";
            std::string completed_content_type = "image/jpeg";
            std::string completed_format = "jpeg";
            std::uint16_t completed_width = 0;
            std::uint16_t completed_height = 0;
            std::vector<std::uint8_t> completed_payload;
            std::vector<std::uint8_t> completed_image;
            {
                std::lock_guard<std::mutex> lock(preview_mutex_);
                ++preview_.preview_packets;

                if (preview_packet.flags & 0x01U) {
                    preview_assembly_.active = true;
                    preview_assembly_.frame_id = preview_packet.frame_id;
                    preview_assembly_.msg_type = preview_packet.msg_type;
                    preview_assembly_.next_chunk_id = 0;
                    preview_assembly_.expected_offset = 0;
                    preview_assembly_.buffer.clear();
                }

                if (preview_assembly_.active &&
                    preview_packet.frame_id == preview_assembly_.frame_id &&
                    preview_packet.msg_type == preview_assembly_.msg_type &&
                    preview_packet.chunk_id == preview_assembly_.next_chunk_id &&
                    preview_packet.chunk_offset == preview_assembly_.expected_offset) {
                    preview_assembly_.buffer.insert(
                        preview_assembly_.buffer.end(),
                        preview_packet.payload,
                        preview_packet.payload + preview_packet.chunk_size);
                    ++preview_assembly_.next_chunk_id;
                    preview_assembly_.expected_offset += preview_packet.chunk_size;

                    if (preview_packet.flags & 0x02U) {
                        completed_payload = preview_assembly_.buffer;
                        completed_frame_id = preview_packet.frame_id;

                        if (preview_assembly_.msg_type == protocol::kPreviewMsgTypeRgb565) {
                            if (completed_payload.size() >= 4) {
                                completed_width = protocol::read_be16(completed_payload.data());
                                completed_height = protocol::read_be16(completed_payload.data() + 2);
                                const std::size_t expected_bytes =
                                    4U + static_cast<std::size_t>(completed_width) *
                                    static_cast<std::size_t>(completed_height) * 2U;
                                if (completed_width != 0 &&
                                    completed_height != 0 &&
                                    completed_payload.size() == expected_bytes) {
                                    completed_image = rgb565_to_bmp(
                                        completed_payload.data() + 4,
                                        completed_width,
                                        completed_height);
                                    completed_file_name = "latest_preview.bmp";
                                    completed_content_type = "image/bmp";
                                    completed_format = "rgb565_bmp";
                                    preview_complete = !completed_image.empty();
                                } else {
                                    logger_.warn(
                                        "preview rgb565 frame size mismatch frame_id=" +
                                        std::to_string(completed_frame_id) +
                                        " width=" + std::to_string(completed_width) +
                                        " height=" + std::to_string(completed_height) +
                                        " bytes=" + std::to_string(completed_payload.size()));
                                }
                            } else {
                                logger_.warn(
                                    "preview rgb565 frame too short frame_id=" +
                                    std::to_string(completed_frame_id));
                            }
                        } else {
                            completed_image = completed_payload;
                            completed_file_name = "latest_preview.jpg";
                            completed_content_type = "image/jpeg";
                            completed_format = "jpeg";
                            preview_complete = !completed_image.empty();
                        }

                        if (preview_complete) {
                            preview_.available = true;
                            preview_.latest_frame_id = completed_frame_id;
                            preview_.latest_width = completed_width;
                            preview_.latest_height = completed_height;
                            preview_.last_preview_wall = rx_wall;
                            preview_.latest_format = completed_format;
                            preview_.latest_file_name = completed_file_name;
                            preview_.latest_content_type = completed_content_type;
                            preview_.latest_payload = completed_payload;
                            preview_.latest_image = completed_image;
                            ++preview_.preview_frames_completed;
                        }

                        preview_assembly_.active = false;
                    }
                } else if (!(preview_packet.flags & 0x01U)) {
                    preview_assembly_.active = false;
                    preview_assembly_.buffer.clear();
                }
            }

            if (first_packet) {
                record_event("preview stream online from " + std::string(ip_text) + ":" + std::to_string(peer_port));
            }
            if (preview_complete) {
                bool write_snapshot = false;
                {
                    std::lock_guard<std::mutex> preview_lock(preview_mutex_);
                    if (preview_.last_snapshot_wall.time_since_epoch().count() == 0 ||
                        (rx_wall - preview_.last_snapshot_wall) >= kPreviewSnapshotInterval) {
                        preview_.last_snapshot_wall = rx_wall;
                        write_snapshot = true;
                    }
                }

                if (write_snapshot) {
                    ServiceConfig cfg_copy;
                    {
                        std::lock_guard<std::mutex> cfg_lock(config_mutex_);
                        cfg_copy = config_;
                    }
                    const auto preview_path = std::filesystem::path(cfg_copy.static_dir) / completed_file_name;
                    if (!write_binary_file(preview_path, completed_image)) {
                        logger_.warn("failed to write preview snapshot to " + preview_path.string());
                    }
                }
            }
            if (preview_complete && ((completed_frame_id % 10U) == 0U)) {
                logger_.info("preview frame completed frame_id=" + std::to_string(completed_frame_id));
            }
            continue;
        }

        std::lock_guard<std::mutex> lock(state_mutex_);
        ++state_.rx_errors;
        state_.last_error = parse_err;
    }
}

void EdgeNodeService::watchdog_loop() {
    auto last_reload_check = std::chrono::steady_clock::now();

    while (!stop_requested_.load()) {
        std::this_thread::sleep_for(std::chrono::milliseconds(200));
        mark_offline_if_needed();

        const auto now = std::chrono::steady_clock::now();
        int reload_sec = 1;
        {
            std::lock_guard<std::mutex> lock(config_mutex_);
            reload_sec = (config_.config_reload_sec <= 0) ? 1 : config_.config_reload_sec;
        }
        if (now - last_reload_check >= std::chrono::seconds(reload_sec)) {
            reload_config_if_needed();
            last_reload_check = now;
        }
    }
}

void EdgeNodeService::http_loop() {
    while (!stop_requested_.load()) {
        sockaddr_in client{};
        socklen_t client_len = sizeof(client);
        const int client_fd = ::accept(http_socket_, reinterpret_cast<sockaddr*>(&client), &client_len);
        if (client_fd < 0) {
            if (errno == EAGAIN || errno == EWOULDBLOCK || errno == EINTR) {
                continue;
            }
            if (!stop_requested_.load()) {
                logger_.warn("accept failed: " + std::string(std::strerror(errno)));
            }
            continue;
        }

        std::array<char, 4096> request_buf{};
        const ssize_t n = ::recv(client_fd, request_buf.data(), request_buf.size() - 1, 0);
        if (n > 0) {
            request_buf[static_cast<std::size_t>(n)] = '\0';
            const std::string response = handle_http_request(request_buf.data());
            if (!send_all(client_fd, response.data(), response.size())) {
                logger_.warn("http send failed: " + std::string(std::strerror(errno)));
            }
        }
        ::close(client_fd);
    }
}

void EdgeNodeService::mark_offline_if_needed() {
    std::lock_guard<std::mutex> config_lock(config_mutex_);
    const auto timeout = std::chrono::milliseconds(config_.offline_timeout_ms);

    std::lock_guard<std::mutex> state_lock(state_mutex_);
    if (!state_.has_packet) {
        return;
    }

    const auto now = std::chrono::steady_clock::now();
    if (state_.online && (now - state_.last_rx_steady) > timeout) {
        state_.online = false;
        state_.last_error = "timeout waiting for FPGA telemetry";
        logger_.warn("telemetry timeout, node marked offline");
        state_.recent_events.push_front(now_iso8601() + " telemetry timeout, node marked offline");
        while (state_.recent_events.size() > 20) {
            state_.recent_events.pop_back();
        }
    }
}

void EdgeNodeService::reload_config_if_needed() {
    ServiceConfig reloaded;
    std::string err;

    if (!std::filesystem::exists(config_path_)) {
        return;
    }

    const auto current_mtime = std::filesystem::last_write_time(config_path_);
    if (last_config_seen_ && current_mtime == last_config_mtime_) {
        return;
    }

    if (!load_config_file(config_path_, reloaded, err)) {
        logger_.warn("config reload failed: " + err);
        return;
    }

    {
        std::lock_guard<std::mutex> lock(config_mutex_);
        const int old_bind_port = config_.bind_port;
        const int old_http_port = config_.http_port;
        const std::string old_bind_ip = config_.bind_ip;
        const std::string old_http_bind_ip = config_.http_bind_ip;

        config_ = reloaded;
        if (old_bind_port != config_.bind_port || old_bind_ip != config_.bind_ip ||
            old_http_port != config_.http_port || old_http_bind_ip != config_.http_bind_ip) {
            logger_.warn("config hot reload updated runtime settings, but socket endpoint changes still require service restart");
        }
    }

    last_config_mtime_ = current_mtime;
    last_config_seen_ = true;
    logger_.info("config reloaded from " + config_path_);
}

bool EdgeNodeService::send_command_packet(
    protocol::CommandCode code,
    std::uint16_t addr,
    std::uint32_t data0,
    std::uint32_t data1,
    std::string& err) {
    std::lock_guard<std::mutex> send_lock(send_mutex_);
    std::lock_guard<std::mutex> config_lock(config_mutex_);

    const auto packet = protocol::build_command_packet(code, next_seq_, addr, data0, data1);

    sockaddr_in target{};
    target.sin_family = AF_INET;
    target.sin_port = htons(static_cast<std::uint16_t>(config_.fpga_port));
    if (::inet_pton(AF_INET, config_.fpga_ip.c_str(), &target.sin_addr) != 1) {
        err = "invalid fpga_ip";
        return false;
    }

    const ssize_t sent = ::sendto(
        tx_socket_,
        packet.data(),
        packet.size(),
        0,
        reinterpret_cast<sockaddr*>(&target),
        sizeof(target));
    if (sent != static_cast<ssize_t>(packet.size())) {
        err = "sendto failed: " + std::string(std::strerror(errno));
        return false;
    }

    {
        std::lock_guard<std::mutex> state_lock(state_mutex_);
        ++state_.commands_sent;
    }

    std::ostringstream addr_text;
    addr_text << std::hex << std::setw(4) << std::setfill('0') << addr;
    logger_.info(
        std::string("tx command=") + protocol::command_name(code) +
        " seq=" + std::to_string(next_seq_) +
        " addr=0x" + addr_text.str());
    record_event(std::string("command ") + protocol::command_name(code) + " sent");

    ++next_seq_;
    err.clear();
    return true;
}

bool EdgeNodeService::send_simple_command(protocol::CommandCode code, std::string& err) {
    return send_command_packet(code, 0, 0, 0, err);
}

bool EdgeNodeService::write_register(std::uint16_t addr, std::uint32_t value, std::string& err) {
    return send_command_packet(protocol::CommandCode::WriteReg, addr, value, 0, err);
}

bool EdgeNodeService::send_named_command(const std::string& command_name, std::string& err) {
    if (command_name == "query_status") {
        return send_simple_command(protocol::CommandCode::QueryStatus, err);
    }
    if (command_name == "start_capture") {
        return send_simple_command(protocol::CommandCode::StartCapture, err);
    }
    if (command_name == "stop_capture") {
        return send_simple_command(protocol::CommandCode::StopCapture, err);
    }
    if (command_name == "clear_error") {
        return send_simple_command(protocol::CommandCode::ClearError, err);
    }
    if (command_name == "buzzer_on") {
        return send_simple_command(protocol::CommandCode::BuzzerOn, err);
    }
    if (command_name == "buzzer_off") {
        return send_simple_command(protocol::CommandCode::BuzzerOff, err);
    }
    if (command_name == "apply_defaults") {
        return apply_default_registers(err);
    }

    err = "unsupported command";
    return false;
}

bool EdgeNodeService::apply_default_registers(std::string& err) {
    ServiceConfig cfg_copy;
    {
        std::lock_guard<std::mutex> lock(config_mutex_);
        cfg_copy = config_;
    }

    if (!write_register(protocol::RegRoiX, cfg_copy.default_roi_x, err)) {
        return false;
    }
    if (!write_register(protocol::RegRoiY, cfg_copy.default_roi_y, err)) {
        return false;
    }
    if (!write_register(protocol::RegRoiW, cfg_copy.default_roi_w, err)) {
        return false;
    }
    if (!write_register(protocol::RegRoiH, cfg_copy.default_roi_h, err)) {
        return false;
    }
    if (!write_register(protocol::RegBrightThreshold, cfg_copy.default_bright_threshold, err)) {
        return false;
    }
    if (!write_register(protocol::RegAlarmCountThreshold, cfg_copy.default_alarm_count_threshold, err)) {
        return false;
    }
    if (!write_register(protocol::RegTxMode, cfg_copy.default_tx_mode, err)) {
        return false;
    }
    {
        std::lock_guard<std::mutex> lock(params_mutex_);
        current_params_.roi_x = cfg_copy.default_roi_x;
        current_params_.roi_y = cfg_copy.default_roi_y;
        current_params_.roi_w = cfg_copy.default_roi_w;
        current_params_.roi_h = cfg_copy.default_roi_h;
        current_params_.bright_threshold = cfg_copy.default_bright_threshold;
        current_params_.alarm_count_threshold = cfg_copy.default_alarm_count_threshold;
        current_params_.tx_mode = cfg_copy.default_tx_mode;
    }
    return true;
}

bool EdgeNodeService::apply_runtime_params(
    std::uint32_t roi_x,
    std::uint32_t roi_y,
    std::uint32_t roi_w,
    std::uint32_t roi_h,
    std::uint32_t bright_threshold,
    std::uint32_t alarm_count_threshold,
    std::uint32_t tx_mode,
    std::string& err) {
    if (!write_register(protocol::RegRoiX, roi_x, err)) {
        return false;
    }
    if (!write_register(protocol::RegRoiY, roi_y, err)) {
        return false;
    }
    if (!write_register(protocol::RegRoiW, roi_w, err)) {
        return false;
    }
    if (!write_register(protocol::RegRoiH, roi_h, err)) {
        return false;
    }
    if (!write_register(protocol::RegBrightThreshold, bright_threshold, err)) {
        return false;
    }
    if (!write_register(protocol::RegAlarmCountThreshold, alarm_count_threshold, err)) {
        return false;
    }
    if (!write_register(protocol::RegTxMode, tx_mode, err)) {
        return false;
    }
    {
        std::lock_guard<std::mutex> lock(params_mutex_);
        current_params_.roi_x = roi_x;
        current_params_.roi_y = roi_y;
        current_params_.roi_w = roi_w;
        current_params_.roi_h = roi_h;
        current_params_.bright_threshold = bright_threshold;
        current_params_.alarm_count_threshold = alarm_count_threshold;
        current_params_.tx_mode = tx_mode;
    }
    return true;
}

std::string EdgeNodeService::status_json() const {
    RuntimeState state_copy;
    ServiceConfig cfg_copy;
    RuntimeParams params_copy;
    AlarmState alarm_copy;
    bool preview_available = false;
    std::uint64_t preview_packets = 0;
    std::uint64_t preview_frames_completed = 0;
    std::uint16_t preview_frame_id = 0;
    std::uint16_t preview_width = 0;
    std::uint16_t preview_height = 0;
    std::size_t preview_bytes = 0;
    std::chrono::system_clock::time_point preview_last_wall{};
    std::string preview_format = "none";
    std::string preview_file_name = "latest_preview.jpg";
    std::string preview_head_hex;
    std::string preview_tail_hex;
    bool preview_has_soi = false;
    bool preview_has_eoi = false;
    {
        std::lock_guard<std::mutex> state_lock(state_mutex_);
        state_copy = state_;
    }
    {
        std::lock_guard<std::mutex> params_lock(params_mutex_);
        params_copy = current_params_;
    }
    {
        std::lock_guard<std::mutex> alarm_lock(alarm_mutex_);
        alarm_copy = alarm_state_;
    }
    {
        std::lock_guard<std::mutex> preview_lock(preview_mutex_);
        preview_available = preview_.available;
        preview_packets = preview_.preview_packets;
        preview_frames_completed = preview_.preview_frames_completed;
        preview_frame_id = preview_.latest_frame_id;
        preview_width = preview_.latest_width;
        preview_height = preview_.latest_height;
        preview_format = preview_.latest_format;
        preview_file_name = preview_.latest_file_name;
        preview_bytes = preview_.latest_image.size();
        preview_last_wall = preview_.last_preview_wall;
        preview_head_hex = hex_prefix(preview_.latest_payload, 8);
        preview_tail_hex = hex_suffix(preview_.latest_payload, 8);
        preview_has_soi = preview_.latest_payload.size() >= 2 &&
                          preview_.latest_payload[0] == 0xFF &&
                          preview_.latest_payload[1] == 0xD8;
        preview_has_eoi = preview_.latest_payload.size() >= 2 &&
                          preview_.latest_payload[preview_.latest_payload.size() - 2] == 0xFF &&
                          preview_.latest_payload[preview_.latest_payload.size() - 1] == 0xD9;
    }
    {
        std::lock_guard<std::mutex> cfg_lock(config_mutex_);
        cfg_copy = config_;
    }

    const bool has_telemetry = state_copy.has_telemetry_packet;
    const std::string status_text = has_telemetry
        ? protocol::status_bits_text(state_copy.last_packet.status_bits)
        : "no_telemetry_packet_yet";

    std::ostringstream oss;
    oss << "{";
    oss << "\"online\":" << (state_copy.online ? "true" : "false") << ",";
    oss << "\"has_packet\":" << (state_copy.has_packet ? "true" : "false") << ",";
    oss << "\"has_telemetry_packet\":" << (has_telemetry ? "true" : "false") << ",";
    oss << "\"preview_stream_only\":" << ((state_copy.has_packet && !has_telemetry) ? "true" : "false") << ",";
    oss << "\"rx_packets\":" << state_copy.rx_packets << ",";
    oss << "\"rx_errors\":" << state_copy.rx_errors << ",";
    oss << "\"commands_sent\":" << state_copy.commands_sent << ",";
    oss << "\"last_error\":\"" << json_escape(state_copy.last_error) << "\",";
    oss << "\"last_peer_ip\":\"" << json_escape(state_copy.last_peer_ip) << "\",";
    oss << "\"last_peer_port\":" << state_copy.last_peer_port << ",";
    oss << "\"last_rx_time\":\"" << json_escape(format_system_time(state_copy.last_rx_wall)) << "\",";
    oss << "\"status_bits\":" << state_copy.last_packet.status_bits << ",";
    oss << "\"status_text\":\"" << json_escape(status_text) << "\",";
    oss << "\"alarm_enable\":" << (((state_copy.last_packet.status_bits >> 8U) & 0x1U) ? "true" : "false") << ",";
    oss << "\"error_code\":" << state_copy.last_packet.error_code << ",";
    oss << "\"frame_id\":" << state_copy.last_packet.frame_id << ",";
    oss << "\"frame_width\":" << state_copy.last_packet.frame_width << ",";
    oss << "\"frame_height\":" << state_copy.last_packet.frame_height << ",";
    oss << "\"active_pixel_count\":" << state_copy.last_packet.active_pixel_count << ",";
    oss << "\"roi_sum\":" << state_copy.last_packet.roi_sum << ",";
    oss << "\"bright_count\":" << state_copy.last_packet.bright_count << ",";
    oss << "\"msg_type\":" << static_cast<int>(state_copy.last_packet.msg_type) << ",";
    oss << "\"fpga_target\":\"" << json_escape(cfg_copy.fpga_ip + ":" + std::to_string(cfg_copy.fpga_port)) << "\",";
    oss << "\"default_roi_x\":" << cfg_copy.default_roi_x << ",";
    oss << "\"default_roi_y\":" << cfg_copy.default_roi_y << ",";
    oss << "\"default_roi_w\":" << cfg_copy.default_roi_w << ",";
    oss << "\"default_roi_h\":" << cfg_copy.default_roi_h << ",";
    oss << "\"default_bright_threshold\":" << cfg_copy.default_bright_threshold << ",";
    oss << "\"default_alarm_count_threshold\":" << cfg_copy.default_alarm_count_threshold << ",";
    oss << "\"default_tx_mode\":" << cfg_copy.default_tx_mode << ",";
    oss << "\"current_roi_x\":" << params_copy.roi_x << ",";
    oss << "\"current_roi_y\":" << params_copy.roi_y << ",";
    oss << "\"current_roi_w\":" << params_copy.roi_w << ",";
    oss << "\"current_roi_h\":" << params_copy.roi_h << ",";
    oss << "\"current_bright_threshold\":" << params_copy.bright_threshold << ",";
    oss << "\"current_alarm_count_threshold\":" << params_copy.alarm_count_threshold << ",";
    oss << "\"current_tx_mode\":" << params_copy.tx_mode << ",";
    oss << "\"offline_timeout_ms\":" << cfg_copy.offline_timeout_ms << ",";
    oss << "\"preview_available\":" << (preview_available ? "true" : "false") << ",";
    oss << "\"preview_frame_id\":" << preview_frame_id << ",";
    oss << "\"preview_width\":" << preview_width << ",";
    oss << "\"preview_height\":" << preview_height << ",";
    oss << "\"preview_bytes\":" << preview_bytes << ",";
    oss << "\"preview_packets\":" << preview_packets << ",";
    oss << "\"preview_frames_completed\":" << preview_frames_completed << ",";
    oss << "\"preview_format\":\"" << json_escape(preview_format) << "\",";
    oss << "\"preview_has_soi\":" << (preview_has_soi ? "true" : "false") << ",";
    oss << "\"preview_has_eoi\":" << (preview_has_eoi ? "true" : "false") << ",";
    oss << "\"preview_head_hex\":\"" << json_escape(preview_head_hex) << "\",";
    oss << "\"preview_tail_hex\":\"" << json_escape(preview_tail_hex) << "\",";
    oss << "\"preview_file_url\":\"" << json_escape("/static/" + preview_file_name) << "\",";
    oss << "\"preview_api_url\":\"/api/preview\",";
    oss << "\"preview_last_time\":\"" << json_escape(format_system_time(preview_last_wall)) << "\",";
    oss << "\"alarm_event_count\":" << alarm_copy.event_count << ",";
    oss << "\"alarm_events\":[";
    for (std::size_t i = 0; i < alarm_copy.events.size(); ++i) {
        if (i != 0) {
            oss << ",";
        }
        const AlarmEvent& event = alarm_copy.events[i];
        oss << "{"
            << "\"time\":\"" << json_escape(event.timestamp) << "\","
            << "\"frame_id\":" << event.frame_id << ","
            << "\"bright_count\":" << event.bright_count << ","
            << "\"alarm_count_threshold\":" << event.alarm_count_threshold << ","
            << "\"roi_sum\":" << event.roi_sum << ","
            << "\"roi_x\":" << event.roi_x << ","
            << "\"roi_y\":" << event.roi_y << ","
            << "\"roi_w\":" << event.roi_w << ","
            << "\"roi_h\":" << event.roi_h << ","
            << "\"image_url\":\"" << json_escape(event.image_url) << "\""
            << "}";
    }
    oss << "],";
    oss << "\"recent_events\":[";
    for (std::size_t i = 0; i < state_copy.recent_events.size(); ++i) {
        if (i != 0) {
            oss << ",";
        }
        oss << "\"" << json_escape(state_copy.recent_events[i]) << "\"";
    }
    oss << "]";
    oss << "}";
    return oss.str();
}

std::string EdgeNodeService::dashboard_html() const {
    ServiceConfig cfg_copy;
    {
        std::lock_guard<std::mutex> lock(config_mutex_);
        cfg_copy = config_;
    }

    std::filesystem::path page_path = std::filesystem::path(cfg_copy.static_dir) / "index.html";
    std::ifstream ifs(page_path);
    if (!ifs.is_open()) {
        return "<html><body><h1>edge_node_service</h1><p>dashboard file missing</p></body></html>";
    }

    std::ostringstream oss;
    oss << ifs.rdbuf();
    return oss.str();
}

std::string EdgeNodeService::build_http_response(
    const std::string& status_line,
    const std::string& content_type,
    const std::string& body) const {
    std::ostringstream oss;
    oss << "HTTP/1.1 " << status_line << "\r\n";
    oss << "Content-Type: " << content_type << "\r\n";
    oss << "Content-Length: " << body.size() << "\r\n";
    oss << "Connection: close\r\n\r\n";
    oss << body;
    return oss.str();
}

std::string EdgeNodeService::handle_http_request(const std::string& request) {
    std::istringstream iss(request);
    std::string method;
    std::string target;
    std::string version;
    iss >> method >> target >> version;

    if (method.empty() || target.empty()) {
        return build_http_response("400 Bad Request", "text/plain; charset=utf-8", "bad request");
    }

    if (target == "/" || target == "/index.html") {
        return build_http_response("200 OK", "text/html; charset=utf-8", dashboard_html());
    }

    if (target == "/api/status") {
        return build_http_response("200 OK", "application/json; charset=utf-8", status_json());
    }

    if (target.rfind("/api/preview", 0) == 0) {
        const std::string decode_mode = get_query_value(target, "decode");
        std::vector<std::uint8_t> image_copy;
        std::string content_type = "image/jpeg";
        {
            std::lock_guard<std::mutex> lock(preview_mutex_);
            if (!decode_mode.empty() &&
                preview_.latest_format == "rgb565_bmp" &&
                !preview_.latest_payload.empty()) {
                std::string format_text;
                image_copy = build_preview_debug_image(
                    preview_.latest_payload,
                    decode_mode,
                    content_type,
                    format_text);
            }
            if (image_copy.empty()) {
                image_copy = preview_.latest_image;
                content_type = preview_.latest_content_type;
            }
        }
        if (image_copy.empty()) {
            return build_http_response("404 Not Found", "text/plain; charset=utf-8", "preview not ready");
        }
        return build_binary_http_response("200 OK", content_type, image_copy.data(), image_copy.size());
    }

    if (target.rfind("/api/preview.jpg", 0) == 0) {
        const std::string decode_mode = get_query_value(target, "decode");
        std::vector<std::uint8_t> image_copy;
        std::string content_type = "image/jpeg";
        {
            std::lock_guard<std::mutex> lock(preview_mutex_);
            if (!decode_mode.empty() &&
                preview_.latest_format == "rgb565_bmp" &&
                !preview_.latest_payload.empty()) {
                std::string format_text;
                image_copy = build_preview_debug_image(
                    preview_.latest_payload,
                    decode_mode,
                    content_type,
                    format_text);
            }
            if (image_copy.empty()) {
                image_copy = preview_.latest_image;
                content_type = preview_.latest_content_type;
            }
        }
        if (image_copy.empty()) {
            return build_http_response("404 Not Found", "text/plain; charset=utf-8", "preview not ready");
        }
        return build_binary_http_response("200 OK", content_type, image_copy.data(), image_copy.size());
    }

    if (target.rfind("/api/command", 0) == 0) {
        const std::string name = get_query_value(target, "name");
        std::string err;
        const bool ok = send_named_command(name, err);
        std::ostringstream body;
        body << "{"
             << "\"ok\":" << (ok ? "true" : "false") << ","
             << "\"command\":\"" << json_escape(name) << "\","
             << "\"message\":\"" << json_escape(ok ? "sent" : err) << "\""
             << "}";
        return build_http_response(ok ? "200 OK" : "400 Bad Request", "application/json; charset=utf-8", body.str());
    }

    if (target.rfind("/api/write_reg", 0) == 0) {
        const std::string addr_text = get_query_value(target, "addr");
        const std::string data_text = get_query_value(target, "data0");
        std::uint32_t addr = 0;
        std::uint32_t data0 = 0;
        if (!parse_u32(addr_text, addr) || !parse_u32(data_text, data0)) {
            return build_http_response("400 Bad Request", "application/json; charset=utf-8", "{\"ok\":false,\"message\":\"invalid addr or data0\"}");
        }

        std::string err;
        const bool ok = send_command_packet(
            protocol::CommandCode::WriteReg,
            static_cast<std::uint16_t>(addr),
            data0,
            0,
            err);
        std::ostringstream body;
        body << "{"
             << "\"ok\":" << (ok ? "true" : "false") << ","
             << "\"message\":\"" << json_escape(ok ? "sent" : err) << "\""
             << "}";
        return build_http_response(ok ? "200 OK" : "400 Bad Request", "application/json; charset=utf-8", body.str());
    }

    if (target.rfind("/api/apply_params", 0) == 0) {
        std::uint32_t roi_x = 0;
        std::uint32_t roi_y = 0;
        std::uint32_t roi_w = 0;
        std::uint32_t roi_h = 0;
        std::uint32_t bright_threshold = 0;
        std::uint32_t alarm_count_threshold = 0;
        std::uint32_t tx_mode = 0;
        const bool parsed =
            parse_u32(get_query_value(target, "roi_x"), roi_x) &&
            parse_u32(get_query_value(target, "roi_y"), roi_y) &&
            parse_u32(get_query_value(target, "roi_w"), roi_w) &&
            parse_u32(get_query_value(target, "roi_h"), roi_h) &&
            parse_u32(get_query_value(target, "bright_threshold"), bright_threshold) &&
            parse_u32(get_query_value(target, "alarm_count_threshold"), alarm_count_threshold) &&
            parse_u32(get_query_value(target, "tx_mode"), tx_mode);
        if (!parsed) {
            return build_http_response(
                "400 Bad Request",
                "application/json; charset=utf-8",
                "{\"ok\":false,\"message\":\"invalid roi_x/roi_y/roi_w/roi_h/bright_threshold/alarm_count_threshold/tx_mode\"}");
        }

        std::string err;
        const bool ok = apply_runtime_params(
            roi_x,
            roi_y,
            roi_w,
            roi_h,
            bright_threshold,
            alarm_count_threshold,
            tx_mode,
            err);
        std::ostringstream body;
        body << "{"
             << "\"ok\":" << (ok ? "true" : "false") << ","
             << "\"message\":\"" << json_escape(ok ? "runtime params applied" : err) << "\","
             << "\"roi_x\":" << roi_x << ","
             << "\"roi_y\":" << roi_y << ","
             << "\"roi_w\":" << roi_w << ","
             << "\"roi_h\":" << roi_h << ","
             << "\"bright_threshold\":" << bright_threshold << ","
             << "\"alarm_count_threshold\":" << alarm_count_threshold << ","
             << "\"tx_mode\":" << tx_mode
             << "}";
        return build_http_response(ok ? "200 OK" : "400 Bad Request", "application/json; charset=utf-8", body.str());
    }

    if (target.rfind("/static/", 0) == 0) {
        ServiceConfig cfg_copy;
        {
            std::lock_guard<std::mutex> lock(config_mutex_);
            cfg_copy = config_;
        }

        std::string static_target = target;
        const auto query_pos = static_target.find('?');
        if (query_pos != std::string::npos) {
            static_target = static_target.substr(0, query_pos);
        }

        const std::string relative = static_target.substr(std::string("/static/").size());
        if (relative.empty() || relative.find("..") != std::string::npos) {
            return build_http_response("400 Bad Request", "text/plain; charset=utf-8", "invalid static path");
        }
        const std::filesystem::path path = std::filesystem::path(cfg_copy.static_dir) / relative;
        std::ifstream ifs(path, std::ios::binary);
        if (!ifs.is_open()) {
            return build_http_response("404 Not Found", "text/plain; charset=utf-8", "not found");
        }
        const std::vector<std::uint8_t> data((std::istreambuf_iterator<char>(ifs)), std::istreambuf_iterator<char>());
        return build_binary_http_response("200 OK", guess_content_type(path.string()), data.data(), data.size());
    }

    return build_http_response("404 Not Found", "text/plain; charset=utf-8", "not found");
}

std::string EdgeNodeService::json_escape(const std::string& text) {
    std::ostringstream oss;
    for (char ch : text) {
        switch (ch) {
        case '\\': oss << "\\\\"; break;
        case '"': oss << "\\\""; break;
        case '\n': oss << "\\n"; break;
        case '\r': oss << "\\r"; break;
        case '\t': oss << "\\t"; break;
        default: oss << ch; break;
        }
    }
    return oss.str();
}

std::string EdgeNodeService::now_iso8601() {
    const auto now = std::chrono::system_clock::now();
    const auto t = std::chrono::system_clock::to_time_t(now);
    std::tm tm_buf{};
#if defined(_WIN32)
    localtime_s(&tm_buf, &t);
#else
    localtime_r(&t, &tm_buf);
#endif

    std::ostringstream oss;
    oss << std::put_time(&tm_buf, "%Y-%m-%dT%H:%M:%S");
    return oss.str();
}

std::string EdgeNodeService::url_decode(const std::string& input) {
    std::string output;
    output.reserve(input.size());

    for (std::size_t i = 0; i < input.size(); ++i) {
        if (input[i] == '+') {
            output.push_back(' ');
        } else if (input[i] == '%' && i + 2 < input.size()) {
            const std::string hex = input.substr(i + 1, 2);
            const char decoded = static_cast<char>(std::stoi(hex, nullptr, 16));
            output.push_back(decoded);
            i += 2;
        } else {
            output.push_back(input[i]);
        }
    }
    return output;
}

std::string EdgeNodeService::get_query_value(const std::string& target, const std::string& key) {
    const auto pos = target.find('?');
    if (pos == std::string::npos) {
        return {};
    }

    std::istringstream query_stream(target.substr(pos + 1));
    std::string item;
    while (std::getline(query_stream, item, '&')) {
        const auto eq = item.find('=');
        if (eq == std::string::npos) {
            continue;
        }
        const std::string name = item.substr(0, eq);
        if (name == key) {
            return url_decode(item.substr(eq + 1));
        }
    }
    return {};
}

bool EdgeNodeService::parse_u32(const std::string& text, std::uint32_t& value) {
    if (text.empty()) {
        return false;
    }
    try {
        value = static_cast<std::uint32_t>(std::stoul(text, nullptr, 0));
        return true;
    } catch (...) {
        return false;
    }
}
