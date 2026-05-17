# CMakeLists.txt for QuickJS Engine
# QuickJS JavaScript引擎的HarmonyOS移植

cmake_minimum_required(VERSION 3.5.0)
project(QuickJSEngine)

# 设置C标准（QuickJS是C99）
set(CMAKE_C_STANDARD 99)
set(CMAKE_C_STANDARD_REQUIRED ON)

# 设置C++标准（NAPI绑定使用C++）
set(CMAKE_CXX_STANDARD 17)
set(CMAKE_CXX_STANDARD_REQUIRED ON)

# QuickJS配置（全局）
add_definitions("-DCONFIG_VERSION=\"2024-01-13\"")
add_definitions("-D_GNU_SOURCE")
# 启用BigNum支持（BigInt/BigFloat/BigDecimal）
add_definitions("-DCONFIG_BIGNUM")

# 设置头文件搜索目录
set(QUICKJS_ROOT ${CMAKE_CURRENT_SOURCE_DIR})
include_directories(
    ${QUICKJS_ROOT}
    ${QUICKJS_ROOT}/quickjs
)

# QuickJS源文件
# libbf.c是必需的，因为quickjs.c中的BigInt功能依赖它
set(QUICKJS_SOURCES
    quickjs/quickjs.c
    quickjs/libregexp.c
    quickjs/libunicode.c
    quickjs/cutils.c
    quickjs/quickjs-libc.c
    quickjs/libbf.c
)

# NAPI绑定源文件
set(NAPI_SOURCES
    quickjs_napi.cpp
    legado_api_full.cpp
)

# 添加库
add_library(quickjs_engine SHARED 
    ${NAPI_SOURCES}
    ${QUICKJS_SOURCES}
)

set(QUICKJS_ENGINE_OUTPUT_DIR ${CMAKE_CURRENT_BINARY_DIR}/quickjs_engine_output)
set_target_properties(quickjs_engine PROPERTIES
    LIBRARY_OUTPUT_DIRECTORY ${QUICKJS_ENGINE_OUTPUT_DIR}
    RUNTIME_OUTPUT_DIRECTORY ${QUICKJS_ENGINE_OUTPUT_DIR}
    ARCHIVE_OUTPUT_DIRECTORY ${QUICKJS_ENGINE_OUTPUT_DIR}
)

# 链接库
target_link_libraries(quickjs_engine PUBLIC 
    libace_napi.z.so 
    libhilog_ndk.z.so
)

# 编译选项
target_compile_options(quickjs_engine PRIVATE
    -Wall
    -Wno-unused-parameter
    -Wno-sign-compare
)

# QuickJS专用日志配置（覆盖父级定义）
target_compile_definitions(quickjs_engine PRIVATE
    LOG_DOMAIN=0x3201
    LOG_TAG="QuickJSEngine"
)
