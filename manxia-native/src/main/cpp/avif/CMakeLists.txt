# CMakeLists.txt for AVIF Decoder Native Module
cmake_minimum_required(VERSION 3.5.0)

project(AvifDecoder)

# 设置C++标准
set(CMAKE_CXX_STANDARD 17)
set(CMAKE_CXX_STANDARD_REQUIRED ON)

# 设置头文件搜索目录
include_directories(
    ${CMAKE_CURRENT_SOURCE_DIR}
    ${CMAKE_CURRENT_SOURCE_DIR}/include
)

# 预编译库路径
# CMAKE_SOURCE_DIR = entry/src/main/cpp (顶层CMakeLists.txt目录)
set(AVIF_LIB_PATH ${MANXIA_ENTRY_LIBS_DIR})
message(STATUS "AVIF_LIB_PATH: ${AVIF_LIB_PATH}")

# 添加预编译的libavif库
add_library(avif SHARED IMPORTED)
set_target_properties(avif PROPERTIES
    IMPORTED_LOCATION ${AVIF_LIB_PATH}/libavif.so
)

# 添加预编译的libaom库（静态库）
add_library(aom STATIC IMPORTED)
set_target_properties(aom PROPERTIES
    IMPORTED_LOCATION ${AVIF_LIB_PATH}/libaom.a
)

# 添加AVIF解码器库
add_library(avif_decoder SHARED
    avif_decoder.cpp
    avif_napi.cpp
)

# Hvigor 会把 native 产物同步到 CMAKE_LIBRARY_OUTPUT_DIRECTORY。若目标本身也直接输出到
# 该目录，Windows 上的同路径 hardlink/copy 判定可能误删源文件；先输出到子目录再交给
# Hvigor 同步，避免 libavif_decoder.so -> libavif_decoder.so 的同路径复制。
set(AVIF_DECODER_OUTPUT_DIR ${CMAKE_CURRENT_BINARY_DIR}/avif_decoder_output)
set_target_properties(avif_decoder PROPERTIES
    LIBRARY_OUTPUT_DIRECTORY ${AVIF_DECODER_OUTPUT_DIR}
    RUNTIME_OUTPUT_DIRECTORY ${AVIF_DECODER_OUTPUT_DIR}
    ARCHIVE_OUTPUT_DIRECTORY ${AVIF_DECODER_OUTPUT_DIR}
)

# 设置头文件目录
target_include_directories(avif_decoder PRIVATE
    ${CMAKE_CURRENT_SOURCE_DIR}/thirdparty/libavif/include
)

# 链接系统库和预编译库
target_link_libraries(avif_decoder PUBLIC
    libace_napi.z.so
    libhilog_ndk.z.so
    libimage_ndk.z.so
    libpixelmap_ndk.z.so
    avif
    aom
)

# 启用libavif支持
target_compile_definitions(avif_decoder PRIVATE HAVE_LIBAVIF=1)

# 日志配置
target_compile_definitions(avif_decoder PRIVATE
    LOG_DOMAIN=0x3201
    LOG_TAG="AvifDecoder"
)
