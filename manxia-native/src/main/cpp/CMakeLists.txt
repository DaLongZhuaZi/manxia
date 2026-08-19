cmake_minimum_required(VERSION 3.5.0)
project(ManxiaNative)

set(CMAKE_CXX_STANDARD 17)
set(CMAKE_CXX_STANDARD_REQUIRED ON)

# 预编译第三方库目录：entry/libs 因 ACL(Administrators 属主)无法迁移，用相对路径指向原位置
# 语义：CMAKE_CURRENT_SOURCE_DIR = manxia-native/src/main/cpp => 上4级 = 仓库根 => entry/libs/{OHOS_ARCH}
set(MANXIA_ENTRY_LIBS_DIR ${CMAKE_CURRENT_SOURCE_DIR}/../../../../entry/libs/${OHOS_ARCH})
message(STATUS "MANXIA_ENTRY_LIBS_DIR=${MANXIA_ENTRY_LIBS_DIR}")

# ===== JSVM Engine（原 entry 根 add_library(jsvm_engine) 原样迁移）=====
add_library(jsvm_engine SHARED
    jsvm_engine.cpp
)
set(JSVM_ENGINE_OUTPUT_DIR ${CMAKE_CURRENT_BINARY_DIR}/jsvm_engine_output)
set_target_properties(jsvm_engine PROPERTIES
    LIBRARY_OUTPUT_DIRECTORY ${JSVM_ENGINE_OUTPUT_DIR}
    RUNTIME_OUTPUT_DIRECTORY ${JSVM_ENGINE_OUTPUT_DIR}
    ARCHIVE_OUTPUT_DIRECTORY ${JSVM_ENGINE_OUTPUT_DIR}
)
target_link_libraries(jsvm_engine PUBLIC
    libace_napi.z.so
    libjsvm.so
    libhilog_ndk.z.so
)
target_compile_definitions(jsvm_engine PRIVATE
    LOG_DOMAIN=0x3200
    LOG_TAG="JSVMEngine"
)

# ===== 模块子项目 ======
add_subdirectory(quickjs)      # libquickjs_engine.so
add_subdirectory(webdav)       # libwebdav_native.so (SMB/curl/mbedTLS)
add_subdirectory(avif)         # libavif_decoder.so
add_subdirectory(transfer_rtc) # libtransfer_rtc_native.so
