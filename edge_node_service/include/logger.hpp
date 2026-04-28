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
