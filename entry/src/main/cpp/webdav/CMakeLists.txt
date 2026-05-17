# CMakeLists.txt for WebDAV Native Module
# 支持 HTTPS (使用 mbedTLS)
cmake_minimum_required(VERSION 3.5.0)

project(WebDAVNative)

set(CMAKE_CXX_STANDARD 17)
set(CMAKE_CXX_STANDARD_REQUIRED ON)
set(CMAKE_POSITION_INDEPENDENT_CODE ON)

# 设置头文件搜索目录
set(LIBSMB2_DIR ${CMAKE_CURRENT_SOURCE_DIR}/../third_party/libsmb2)

include_directories(
    ${CMAKE_CURRENT_SOURCE_DIR}
    ${CMAKE_CURRENT_SOURCE_DIR}/include
    ${LIBSMB2_DIR}/include
    ${LIBSMB2_DIR}/include/smb2
    ${CMAKE_CURRENT_BINARY_DIR}
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

# 添加 WebDAV/FTP 原生模块

# libsmb2 源文件
set(LIBSMB2_SOURCES
    ${LIBSMB2_DIR}/lib/aes.c
    ${LIBSMB2_DIR}/lib/aes_reference.c
    ${LIBSMB2_DIR}/lib/aes128ccm.c
    ${LIBSMB2_DIR}/lib/alloc.c
    ${LIBSMB2_DIR}/lib/asn1-ber.c
    ${LIBSMB2_DIR}/lib/compat.c
    ${LIBSMB2_DIR}/lib/dcerpc.c
    ${LIBSMB2_DIR}/lib/dcerpc-lsa.c
    ${LIBSMB2_DIR}/lib/dcerpc-srvsvc.c
    ${LIBSMB2_DIR}/lib/errors.c
    ${LIBSMB2_DIR}/lib/hmac.c
    ${LIBSMB2_DIR}/lib/hmac-md5.c
    ${LIBSMB2_DIR}/lib/init.c
    ${LIBSMB2_DIR}/lib/libsmb2.c
    ${LIBSMB2_DIR}/lib/md4c.c
    ${LIBSMB2_DIR}/lib/md5.c
    ${LIBSMB2_DIR}/lib/ntlmssp.c
    ${LIBSMB2_DIR}/lib/pdu.c
    ${LIBSMB2_DIR}/lib/sha1.c
    ${LIBSMB2_DIR}/lib/sha224-256.c
    ${LIBSMB2_DIR}/lib/sha384-512.c
    ${LIBSMB2_DIR}/lib/smb2-cmd-close.c
    ${LIBSMB2_DIR}/lib/smb2-cmd-create.c
    ${LIBSMB2_DIR}/lib/smb2-cmd-echo.c
    ${LIBSMB2_DIR}/lib/smb2-cmd-error.c
    ${LIBSMB2_DIR}/lib/smb2-cmd-flush.c
    ${LIBSMB2_DIR}/lib/smb2-cmd-ioctl.c
    ${LIBSMB2_DIR}/lib/smb2-cmd-lock.c
    ${LIBSMB2_DIR}/lib/smb2-cmd-logoff.c
    ${LIBSMB2_DIR}/lib/smb2-cmd-negotiate.c
    ${LIBSMB2_DIR}/lib/smb2-cmd-notify-change.c
    ${LIBSMB2_DIR}/lib/smb2-cmd-oplock-break.c
    ${LIBSMB2_DIR}/lib/smb2-cmd-query-directory.c
    ${LIBSMB2_DIR}/lib/smb2-cmd-query-info.c
    ${LIBSMB2_DIR}/lib/smb2-cmd-read.c
    ${LIBSMB2_DIR}/lib/smb2-cmd-session-setup.c
    ${LIBSMB2_DIR}/lib/smb2-cmd-set-info.c
    ${LIBSMB2_DIR}/lib/smb2-cmd-tree-connect.c
    ${LIBSMB2_DIR}/lib/smb2-cmd-tree-disconnect.c
    ${LIBSMB2_DIR}/lib/smb2-cmd-write.c
    ${LIBSMB2_DIR}/lib/smb2-data-file-info.c
    ${LIBSMB2_DIR}/lib/smb2-data-filesystem-info.c
    ${LIBSMB2_DIR}/lib/smb2-data-security-descriptor.c
    ${LIBSMB2_DIR}/lib/smb2-data-reparse-point.c
    ${LIBSMB2_DIR}/lib/smb2-share-enum.c
    ${LIBSMB2_DIR}/lib/smb3-seal.c
    ${LIBSMB2_DIR}/lib/smb2-signing.c
    ${LIBSMB2_DIR}/lib/socket.c
    ${LIBSMB2_DIR}/lib/spnego-wrapper.c
    ${LIBSMB2_DIR}/lib/sync.c
    ${LIBSMB2_DIR}/lib/timestamps.c
    ${LIBSMB2_DIR}/lib/unicode.c
    ${LIBSMB2_DIR}/lib/usha.c
)

add_library(webdav_native SHARED
    curl_global.cpp
    webdav_client.cpp
    webdav_napi.cpp
    ftp_client.cpp
    ftp_napi.cpp
    smb_client.cpp
    smb_napi.cpp
    network_scanner.cpp
    scanner_napi.cpp
    ${LIBSMB2_SOURCES}
)

set(WEBDAV_NATIVE_OUTPUT_DIR ${CMAKE_CURRENT_BINARY_DIR}/webdav_native_output)
set_target_properties(webdav_native PROPERTIES
    LIBRARY_OUTPUT_DIRECTORY ${WEBDAV_NATIVE_OUTPUT_DIR}
    RUNTIME_OUTPUT_DIRECTORY ${WEBDAV_NATIVE_OUTPUT_DIR}
    ARCHIVE_OUTPUT_DIRECTORY ${WEBDAV_NATIVE_OUTPUT_DIR}
)

# libsmb2 编译配置
target_compile_definitions(webdav_native PRIVATE HAVE_CONFIG_H)
target_compile_definitions(webdav_native PRIVATE _GNU_SOURCE)
target_compile_definitions(webdav_native PRIVATE "_U_=__attribute__((unused))")

# 将 config.h 复制到构建目录（libsmb2 源码通过 #include "config.h" 引用）
configure_file(${CMAKE_CURRENT_SOURCE_DIR}/smb2_config.h ${CMAKE_CURRENT_BINARY_DIR}/config.h COPYONLY)

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
