# CMakeLists.txt for WebDAV Native Module
# 支持 HTTPS (使用 mbedTLS)
cmake_minimum_required(VERSION 3.5.0)

project(WebDAVNative)

set(CMAKE_CXX_STANDARD 17)
set(CMAKE_CXX_STANDARD_REQUIRED ON)

# 设置头文件搜索目录
include_directories(
    ${CMAKE_CURRENT_SOURCE_DIR}
    ${CMAKE_CURRENT_SOURCE_DIR}/include
)

# 添加预编译的 mbedTLS 库
add_library(mbedcrypto SHARED IMPORTED)
set_target_properties(mbedcrypto PROPERTIES
    IMPORTED_LOCATION ${CMAKE_SOURCE_DIR}/../../../libs/${OHOS_ARCH}/libmbedcrypto.so
)

add_library(mbedx509 SHARED IMPORTED)
set_target_properties(mbedx509 PROPERTIES
    IMPORTED_LOCATION ${CMAKE_SOURCE_DIR}/../../../libs/${OHOS_ARCH}/libmbedx509.so
)

add_library(mbedtls SHARED IMPORTED)
set_target_properties(mbedtls PROPERTIES
    IMPORTED_LOCATION ${CMAKE_SOURCE_DIR}/../../../libs/${OHOS_ARCH}/libmbedtls.so
)

# 添加预编译的 libcurl 库 (HTTPS版，链接mbedTLS)
add_library(curl SHARED IMPORTED)
set_target_properties(curl PROPERTIES
    IMPORTED_LOCATION ${CMAKE_SOURCE_DIR}/../../../libs/${OHOS_ARCH}/libcurl.so
)

# 添加WebDAV库（包含FTP支持）
add_library(webdav_native SHARED
    curl_global.cpp
    webdav_client.cpp
    webdav_napi.cpp
    ftp_client.cpp
    ftp_napi.cpp
)

# 链接依赖库
target_link_libraries(webdav_native PUBLIC
    libace_napi.z.so
    libhilog_ndk.z.so
    curl
    mbedtls
    mbedx509
    mbedcrypto
)

# 日志配置
target_compile_definitions(webdav_native PRIVATE
    LOG_DOMAIN=0x3201
    LOG_TAG="WebDAVNative"
)
