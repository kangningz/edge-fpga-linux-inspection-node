// 服务配置结构声明，集中描述 UDP、HTTP、路径、超时和默认寄存器参数。
// 该头文件只保存跨模块共享的数据形状，具体读取和兼容路径处理在 config.cpp 中完成。
#pragma once

#include <cstdint>
#include <string>

struct ServiceConfig {
    std::string bind_ip = "0.0.0.0";
    int bind_port = 9002;

    std::string fpga_ip = "192.168.50.2";
    int fpga_port = 9003;

    std::string http_bind_ip = "0.0.0.0";
    int http_port = 5000;
    std::string static_dir = "./web";

    std::string log_file = "./logs/edge_node_service.log";
    int offline_timeout_ms = 5000;
    int config_reload_sec = 2;
    int socket_timeout_ms = 500;

    bool auto_initialize = true;
    bool auto_start_capture = true;
    std::uint16_t initial_seq = 1;

    std::uint16_t default_roi_x = 0;
    std::uint16_t default_roi_y = 0;
    std::uint16_t default_roi_w = 64;
    std::uint16_t default_roi_h = 64;
    std::uint16_t default_bright_threshold = 128;
    std::uint16_t default_alarm_count_threshold = 256;
    std::uint16_t default_tx_mode = 2;
};

bool load_config_file(const std::string& path, ServiceConfig& cfg, std::string& err);
