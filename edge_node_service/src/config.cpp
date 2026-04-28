#include "config.hpp"

#include <filesystem>
#include <fstream>
#include <regex>
#include <sstream>

namespace {

bool read_file(const std::string& path, std::string& text, std::string& err) {
    std::ifstream ifs(path);
    if (!ifs.is_open()) {
        err = "cannot open file";
        return false;
    }
    std::ostringstream oss;
    oss << ifs.rdbuf();
    text = oss.str();
    return true;
}

bool extract_string(const std::string& text, const std::string& key, std::string& out) {
    const std::regex pattern("\"" + key + "\"\\s*:\\s*\"([^\"]*)\"");
    std::smatch match;
    if (!std::regex_search(text, match, pattern)) {
        return false;
    }
    out = match[1].str();
    return true;
}

bool extract_bool(const std::string& text, const std::string& key, bool& out) {
    const std::regex pattern("\"" + key + "\"\\s*:\\s*(true|false)");
    std::smatch match;
    if (!std::regex_search(text, match, pattern)) {
        return false;
    }
    out = (match[1].str() == "true");
    return true;
}

bool extract_int(const std::string& text, const std::string& key, int& out) {
    const std::regex pattern("\"" + key + "\"\\s*:\\s*(-?(?:0[xX][0-9a-fA-F]+|\\d+))");
    std::smatch match;
    if (!std::regex_search(text, match, pattern)) {
        return false;
    }
    out = std::stoi(match[1].str(), nullptr, 0);
    return true;
}

std::string resolve_config_relative_path(const std::string& config_path, const std::string& raw_path) {
    if (raw_path.empty()) {
        return raw_path;
    }

    const std::filesystem::path candidate(raw_path);
    if (candidate.is_absolute()) {
        return candidate.lexically_normal().string();
    }

    const std::filesystem::path cfg_path(config_path);
    const std::filesystem::path base_dir = cfg_path.has_parent_path() ? cfg_path.parent_path() : std::filesystem::current_path();
    const std::filesystem::path primary = (base_dir / candidate).lexically_normal();

    // Backward compatibility:
    // older configs used "./web" / "./logs/..." while config.json lives in ./config/.
    // If that legacy relative path does not exist under the config directory,
    // fall back to the project root one level above.
    if (raw_path.rfind("./", 0) == 0 && base_dir.filename() == "config") {
        const std::filesystem::path fallback = (base_dir.parent_path() / raw_path.substr(2)).lexically_normal();
        if (!std::filesystem::exists(primary) && !std::filesystem::exists(primary.parent_path())) {
            return fallback.string();
        }
    }

    return primary.string();
}

} // namespace

bool load_config_file(const std::string& path, ServiceConfig& cfg, std::string& err) {
    std::string text;
    if (!read_file(path, text, err)) {
        return false;
    }

    extract_string(text, "bind_ip", cfg.bind_ip);
    extract_int(text, "bind_port", cfg.bind_port);

    extract_string(text, "fpga_ip", cfg.fpga_ip);
    extract_int(text, "fpga_port", cfg.fpga_port);

    extract_string(text, "http_bind_ip", cfg.http_bind_ip);
    extract_int(text, "http_port", cfg.http_port);
    extract_string(text, "static_dir", cfg.static_dir);

    extract_string(text, "log_file", cfg.log_file);
    extract_int(text, "offline_timeout_ms", cfg.offline_timeout_ms);
    extract_int(text, "config_reload_sec", cfg.config_reload_sec);
    extract_int(text, "socket_timeout_ms", cfg.socket_timeout_ms);

    extract_bool(text, "auto_initialize", cfg.auto_initialize);
    extract_bool(text, "auto_start_capture", cfg.auto_start_capture);

    {
        int value = static_cast<int>(cfg.initial_seq);
        if (extract_int(text, "initial_seq", value)) {
            cfg.initial_seq = static_cast<std::uint16_t>(value);
        }
    }
    {
        int value = static_cast<int>(cfg.default_roi_x);
        if (extract_int(text, "default_roi_x", value)) {
            cfg.default_roi_x = static_cast<std::uint16_t>(value);
        }
    }
    {
        int value = static_cast<int>(cfg.default_roi_y);
        if (extract_int(text, "default_roi_y", value)) {
            cfg.default_roi_y = static_cast<std::uint16_t>(value);
        }
    }
    {
        int value = static_cast<int>(cfg.default_roi_w);
        if (extract_int(text, "default_roi_w", value)) {
            cfg.default_roi_w = static_cast<std::uint16_t>(value);
        }
    }
    {
        int value = static_cast<int>(cfg.default_roi_h);
        if (extract_int(text, "default_roi_h", value)) {
            cfg.default_roi_h = static_cast<std::uint16_t>(value);
        }
    }
    {
        int value = static_cast<int>(cfg.default_bright_threshold);
        if (extract_int(text, "default_bright_threshold", value)) {
            cfg.default_bright_threshold = static_cast<std::uint16_t>(value);
        }
    }
    {
        int value = static_cast<int>(cfg.default_alarm_count_threshold);
        if (extract_int(text, "default_alarm_count_threshold", value)) {
            cfg.default_alarm_count_threshold = static_cast<std::uint16_t>(value);
        }
    }
    {
        int value = static_cast<int>(cfg.default_tx_mode);
        if (extract_int(text, "default_tx_mode", value)) {
            cfg.default_tx_mode = static_cast<std::uint16_t>(value);
        }
    }

    cfg.static_dir = resolve_config_relative_path(path, cfg.static_dir);
    cfg.log_file = resolve_config_relative_path(path, cfg.log_file);

    err.clear();
    return true;
}
