# CMakeLists.txt for JSVM Native Module
# 声明使用 CMAKE 的最小版本号
cmake_minimum_required(VERSION 3.5.0)

# 配置项目信息
project(JSVMEngine)

# 设置C++标准
set(CMAKE_CXX_STANDARD 17)
set(CMAKE_CXX_STANDARD_REQUIRED ON)

# set命令，格式为set(key value)，表示设置key的值为value
set(NATIVERENDER_ROOT_PATH ${CMAKE_CURRENT_SOURCE_DIR})

# 日志打印配置（仅用于jsvm_engine，不传递到子目录）
# 注意：使用target_compile_definitions而不是add_definitions，避免影响子目录

# 设置头文件的搜索目录
include_directories(
    ${NATIVERENDER_ROOT_PATH}
    ${NATIVERENDER_ROOT_PATH}/include
)

# 添加名为jsvm_engine的库，库文件名为libjsvm_engine.so
add_library(jsvm_engine SHARED 
    jsvm_engine.cpp
)

# 构建此可执行文件需要链接的库
target_link_libraries(jsvm_engine PUBLIC 
    libace_napi.z.so 
    libjsvm.so 
    libhilog_ndk.z.so
)

# jsvm_engine专用日志配置
target_compile_definitions(jsvm_engine PRIVATE
    LOG_DOMAIN=0x3200
    LOG_TAG="JSVMEngine"
)

# QuickJS引擎模块（可选，用于替代JSVM）
add_subdirectory(quickjs)

# WebDAV Native模块（使用libcurl实现完整WebDAV协议）
add_subdirectory(webdav)

# AVIF图片解码模块（使用libavif实现AVIF格式支持）
add_subdirectory(avif)
