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

# 日志打印配置
add_definitions("-DLOG_DOMAIN=0x3200")
add_definitions("-DLOG_TAG=\"JSVMEngine\"")

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
