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

    struct PreviewAssembly {
        bool active = false;
        std::uint16_t frame_id = 0;
        std::uint8_t msg_type = 0;
        std::uint16_t next_chunk_id = 0;
        std::uint32_t expected_offset = 0;
        std::vector<std::uint8_t> buffer;
    };

    struct RuntimeParams {
        std::uint32_t roi_x = 0;
        std::uint32_t roi_y = 0;
        std::uint32_t roi_w = 64;
        std::uint32_t roi_h = 64;
        std::uint32_t bright_threshold = 128;
        std::uint32_t alarm_count_threshold = 256;
        std::uint32_t tx_mode = 2;
    };

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
