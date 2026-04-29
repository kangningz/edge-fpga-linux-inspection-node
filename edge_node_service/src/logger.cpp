// 日志写入实现。
// 所有日志记录都带本地时间戳，并用互斥锁保证多线程输出不会交叉。
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

}

// 创建日志目录并打开追加写入的日志文件。
Logger::Logger(const std::string& file_path) {
    const std::filesystem::path path(file_path);
    if (!path.parent_path().empty()) {
        std::filesystem::create_directories(path.parent_path());
    }
    stream_.open(file_path, std::ios::app);
}

// 写入信息级日志。
void Logger::info(const std::string& message) {
    write("INFO", message);
}

// 写入警告级日志。
void Logger::warn(const std::string& message) {
    write("WARN", message);
}

// 写入错误级日志。
void Logger::error(const std::string& message) {
    write("ERROR", message);
}

// 统一格式化并输出一条日志记录。
void Logger::write(const char* level, const std::string& message) {
    std::lock_guard<std::mutex> lock(mutex_);
    const std::string line = "[" + now_string() + "][" + level + "] " + message;
    std::cout << line << std::endl;
    if (stream_.is_open()) {
        stream_ << line << "\n";
        stream_.flush();
    }
}
