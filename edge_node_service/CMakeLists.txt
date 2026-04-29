# edge_node_service 构建脚本。
# 使用 C++17 编译后台服务，并把 include、src 与 pthread 链接关系集中声明在这里。
cmake_minimum_required(VERSION 3.16)

project(edge_node_service VERSION 1.0.0 LANGUAGES CXX)

set(CMAKE_CXX_STANDARD 17)
set(CMAKE_CXX_STANDARD_REQUIRED ON)
set(CMAKE_CXX_EXTENSIONS OFF)

find_package(Threads REQUIRED)

add_executable(edge_node_service
    src/config.cpp
    src/logger.cpp
    src/main.cpp
    src/service.cpp
)

target_include_directories(edge_node_service PRIVATE include)
target_link_libraries(edge_node_service PRIVATE Threads::Threads)

if(CMAKE_CXX_COMPILER_ID MATCHES "GNU|Clang")
    target_compile_options(edge_node_service PRIVATE -Wall -Wextra -Wpedantic)
endif()
