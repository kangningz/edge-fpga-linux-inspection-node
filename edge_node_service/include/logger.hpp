// 线程安全日志接口声明，服务线程可并发写入同一个日志文件。
// 日志类同时向标准输出和磁盘文件写入，便于现场调试和后台运行排障。
#pragma once

#include <mutex>
#include <fstream>
#include <string>

class Logger {
public:
    explicit Logger(const std::string& file_path);

    void info(const std::string& message);
    void warn(const std::string& message);
    void error(const std::string& message);

private:
    void write(const char* level, const std::string& message);

    std::mutex mutex_;
    std::ofstream stream_;
};
