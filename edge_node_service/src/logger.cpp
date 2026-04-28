#include "logger.hpp"

#include <chrono>
#include <filesystem>
#include <iomanip>
#include <iostream>
#include <sstream>

namespace {

std::string now_string() {
    using namespace std::chrono;
    const auto now = system_clock::now();
    const auto t = system_clock::to_time_t(now);
    const auto ms = duration_cast<milliseconds>(now.time_since_epoch()) % 1000;

    std::tm tm_buf{};
#if defined(_WIN32)
    localtime_s(&tm_buf, &t);
#else
    localtime_r(&t, &tm_buf);
#endif

    std::ostringstream oss;
    oss << std::put_time(&tm_buf, "%Y-%m-%d %H:%M:%S")
        << "."
        << std::setw(3) << std::setfill('0') << ms.count();
    return oss.str();
}

} // namespace

Logger::Logger(const std::string& file_path) {
    const std::filesystem::path path(file_path);
    if (!path.parent_path().empty()) {
        std::filesystem::create_directories(path.parent_path());
    }
    stream_.open(file_path, std::ios::app);
}

void Logger::info(const std::string& message) {
    write("INFO", message);
}

void Logger::warn(const std::string& message) {
    write("WARN", message);
}

void Logger::error(const std::string& message) {
    write("ERROR", message);
}

void Logger::write(const char* level, const std::string& message) {
    std::lock_guard<std::mutex> lock(mutex_);
    const std::string line = "[" + now_string() + "][" + level + "] " + message;
    std::cout << line << std::endl;
    if (stream_.is_open()) {
        stream_ << line << "\n";
        stream_.flush();
    }
}
