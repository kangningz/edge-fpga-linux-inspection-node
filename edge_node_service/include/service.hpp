// 边缘节点后台服务主类声明。
// 该类负责 UDP 收发、HTTP 接口、预览帧重组、告警记录、配置热加载和运行参数下发。
#pragma once

#include <atomic>
#include <chrono>
#include <cstdint>
#include <deque>
#include <filesystem>
#include <mutex>
#include <string>
#include <thread>
#include <vector>

#include "config.hpp"
#include "logger.hpp"
#include "protocol.hpp"

// EdgeNodeService 封装后台服务生命周期和所有跨线程共享状态。
class EdgeNodeService {
public:
    EdgeNodeService(std::string config_path, ServiceConfig config, Logger& logger);
    ~EdgeNodeService();

    bool start();
    void stop();

    std::string status_json() const;
    std::string dashboard_html() const;

    bool send_named_command(const std::string& command_name, std::string& err);
    bool apply_default_registers(std::string& err);
    bool apply_runtime_params(
        std::uint32_t roi_x,
        std::uint32_t roi_y,
        std::uint32_t roi_w,
        std::uint32_t roi_h,
        std::uint32_t bright_threshold,
        std::uint32_t alarm_count_threshold,
        std::uint32_t tx_mode,
        std::string& err);

private:

    // 保存 FPGA 链路和遥测的最新状态，HTTP 状态接口会从这里取快照。
    struct RuntimeState {
        bool online = false;
        bool has_packet = false;
        bool has_telemetry_packet = false;
        std::uint64_t rx_packets = 0;
        std::uint64_t rx_errors = 0;
        std::uint64_t commands_sent = 0;
        std::string last_error = "none";
        std::string last_peer_ip = "n/a";
        int last_peer_port = 0;
        protocol::FrameStatsPacket last_packet{};
        std::chrono::steady_clock::time_point last_rx_steady{};
        std::chrono::system_clock::time_point last_rx_wall{};
        std::deque<std::string> recent_events;
    };

    // 保存已经重组完成的最新预览图及其元数据。
    struct PreviewState {
        bool available = false;
        std::uint64_t preview_packets = 0;
        std::uint64_t preview_frames_completed = 0;
        std::uint16_t latest_frame_id = 0;
        std::uint16_t latest_width = 0;
        std::uint16_t latest_height = 0;
        std::chrono::system_clock::time_point last_preview_wall{};
        std::chrono::system_clock::time_point last_snapshot_wall{};
        std::string latest_format = "none";
        std::string latest_file_name = "latest_preview.jpg";
        std::string latest_content_type = "image/jpeg";
        std::vector<std::uint8_t> latest_image;
        std::vector<std::uint8_t> latest_payload;
    };

    // 保存当前正在接收的预览帧分片重组进度。
    struct PreviewAssembly {
        bool active = false;
        std::uint16_t frame_id = 0;
        std::uint8_t msg_type = 0;
        std::uint16_t next_chunk_id = 0;
        std::uint32_t expected_offset = 0;
        std::vector<std::uint8_t> buffer;
    };

    // 保存当前已经下发到 FPGA 的运行参数，便于前端表单回显。
    struct RuntimeParams {
        std::uint32_t roi_x = 0;
        std::uint32_t roi_y = 0;
        std::uint32_t roi_w = 64;
        std::uint32_t roi_h = 64;
        std::uint32_t bright_threshold = 128;
        std::uint32_t alarm_count_threshold = 256;
        std::uint32_t tx_mode = 2;
    };

    // 记录一次告警发生时的时间、统计值、ROI 参数和快照地址。
    struct AlarmEvent {
        std::string timestamp;
        std::uint16_t frame_id = 0;
        std::uint32_t bright_count = 0;
        std::uint32_t alarm_count_threshold = 0;
        std::uint32_t roi_sum = 0;
        std::uint32_t roi_x = 0;
        std::uint32_t roi_y = 0;
        std::uint32_t roi_w = 0;
        std::uint32_t roi_h = 0;
        std::string image_url;
    };

    // 保存告警边沿检测状态和最近告警事件队列。
    struct AlarmState {
        bool last_alarm_active = false;
        std::uint64_t event_count = 0;
        std::deque<AlarmEvent> events;
    };

    bool open_sockets(std::string& err);
    void close_sockets();
    void rx_loop();
    void watchdog_loop();
    void http_loop();
    void record_event(const std::string& event_text);

    void mark_offline_if_needed();
    void reload_config_if_needed();

    bool send_command_packet(
        protocol::CommandCode code,
        std::uint16_t addr,
        std::uint32_t data0,
        std::uint32_t data1,
        std::string& err);
    bool write_register(std::uint16_t addr, std::uint32_t value, std::string& err);

    bool send_simple_command(protocol::CommandCode code, std::string& err);
    std::string build_http_response(
        const std::string& status_line,
        const std::string& content_type,
        const std::string& body) const;
    std::string handle_http_request(const std::string& request);

    static std::string json_escape(const std::string& text);
    static std::string now_iso8601();
    static std::string url_decode(const std::string& input);
    static std::string get_query_value(const std::string& target, const std::string& key);
    static bool parse_u32(const std::string& text, std::uint32_t& value);

    std::string config_path_;
    mutable std::mutex config_mutex_;
    ServiceConfig config_;

    Logger& logger_;
    std::atomic<bool> stop_requested_{false};
    std::thread rx_thread_;
    std::thread watchdog_thread_;
    std::thread http_thread_;

    int rx_socket_ = -1;
    int tx_socket_ = -1;
    int http_socket_ = -1;

    mutable std::mutex state_mutex_;
    RuntimeState state_;

    mutable std::mutex params_mutex_;
    RuntimeParams current_params_;

    mutable std::mutex alarm_mutex_;
    AlarmState alarm_state_;

    mutable std::mutex preview_mutex_;
    PreviewState preview_;
    PreviewAssembly preview_assembly_;

    std::mutex send_mutex_;
    std::uint16_t next_seq_ = 1;
    std::filesystem::file_time_type last_config_mtime_{};
    bool last_config_seen_ = false;
};
