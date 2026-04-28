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

} // namespace

int main(int argc, char* argv[]) {
    const std::string config_path = (argc >= 2) ? argv[1] : "./config/config.json";

    ServiceConfig config;
    std::string config_error;
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
