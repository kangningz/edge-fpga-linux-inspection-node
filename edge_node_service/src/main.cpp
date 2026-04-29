// 后台服务入口。
// 负责加载配置、初始化日志、启动 EdgeNodeService，并处理 SIGINT/SIGTERM 退出请求。
#include <atomic>
#include <csignal>
#include <iostream>
#include <thread>

#include "config.hpp"
#include "logger.hpp"
#include "service.hpp"

namespace {

std::atomic<bool> g_stop{false};

void on_signal(int) {
    g_stop.store(true);
}

}

// 程序入口，按命令行参数选择配置文件并维持服务运行。
int main(int argc, char* argv[]) {
    const std::string config_path = (argc >= 2) ? argv[1] : "./config/config.json";

    ServiceConfig config;
    std::string config_error;

// 读取配置文件并覆盖默认配置，缺省字段保留结构体中的默认值。
    if (!load_config_file(config_path, config, config_error)) {
        std::cerr << "Failed to load config from " << config_path << ": " << config_error << "\n";
        return 1;
    }

    Logger logger(config.log_file);
    logger.info("edge_node_service booting");

    EdgeNodeService service(config_path, config, logger);
    if (!service.start()) {
        logger.error("service start failed");
        return 1;
    }

    std::signal(SIGINT, on_signal);
    std::signal(SIGTERM, on_signal);

    while (!g_stop.load()) {
        std::this_thread::sleep_for(std::chrono::milliseconds(200));
    }

    logger.info("stop signal received");
    service.stop();
    logger.info("edge_node_service exited");
    return 0;
}
