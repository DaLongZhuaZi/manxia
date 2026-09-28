# 编译支持HTTPS的libcurl for HarmonyOS

本文档说明如何为HarmonyOS交叉编译支持HTTPS的libcurl。

## 概述

要支持HTTPS，需要：
1. 先编译 mbedTLS（轻量级SSL库）
2. 再编译 libcurl（链接mbedTLS）

## 步骤1：下载源码

### mbedTLS 3.5.1
```
下载地址: https://github.com/Mbed-TLS/mbedtls/releases/download/v3.5.1/mbedtls-3.5.1.tar.bz2
```

解压到 `entry/src/main/cpp/webdav/mbedtls-3.5.1/`

### curl 8.5.0
```
下载地址: https://curl.se/download/curl-8.5.0.tar.gz
```

解压到 `entry/src/main/cpp/webdav/curl-8.5.0/`

## 步骤2：编译mbedTLS

```batch
cd entry\src\main\cpp\webdav
build_mbedtls_ohos.bat
```

编译完成后，输出在 `install-mbedtls-arm64/` 目录。

## 步骤3：编译libcurl（HTTPS版）

```batch
build_libcurl_https.bat
```

编译完成后，输出在 `install-curl-https-arm64/` 目录。

## 步骤4：集成到项目

### 复制库文件到 `entry/libs/arm64-v8a/`：

```
install-curl-https-arm64/lib/libcurl.so
install-mbedtls-arm64/lib/libmbedtls.so
install-mbedtls-arm64/lib/libmbedx509.so
install-mbedtls-arm64/lib/libmbedcrypto.so
```

### 更新 CMakeLists.txt

修改 `entry/src/main/cpp/webdav/CMakeLists.txt`：

```cmake
# 添加预编译的 mbedTLS 库
add_library(mbedtls SHARED IMPORTED)
set_target_properties(mbedtls PROPERTIES
    IMPORTED_LOCATION ${CMAKE_SOURCE_DIR}/../../../libs/${OHOS_ARCH}/libmbedtls.so
)

add_library(mbedx509 SHARED IMPORTED)
set_target_properties(mbedx509 PROPERTIES
    IMPORTED_LOCATION ${CMAKE_SOURCE_DIR}/../../../libs/${OHOS_ARCH}/libmbedx509.so
)

add_library(mbedcrypto SHARED IMPORTED)
set_target_properties(mbedcrypto PROPERTIES
    IMPORTED_LOCATION ${CMAKE_SOURCE_DIR}/../../../libs/${OHOS_ARCH}/libmbedcrypto.so
)

# 添加预编译的 libcurl 库
add_library(curl SHARED IMPORTED)
set_target_properties(curl PROPERTIES
    IMPORTED_LOCATION ${CMAKE_SOURCE_DIR}/../../../libs/${OHOS_ARCH}/libcurl.so
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
```

## 支持的协议

编译完成后，libcurl将支持：

| 协议 | 状态 | 说明 |
|------|------|------|
| HTTP | ✅ | WebDAV基础协议 |
| HTTPS | ✅ | 安全WebDAV |
| FTP | ✅ | 文件传输 |
| FTPS | ✅ | 安全FTP |
| FILE | ✅ | 本地文件 |

## 验证HTTPS支持

在Native测试页面测试HTTPS WebDAV服务器：
1. 配置HTTPS WebDAV服务器地址（如 `https://your-server.com/webdav`）
2. 运行Native测试
3. 检查连接测试是否成功

## 常见问题

### Q: 编译mbedTLS失败
A: 确保使用正确版本的HarmonyOS SDK，检查NDK路径是否正确。

### Q: libcurl找不到mbedTLS
A: 确保mbedTLS已正确编译，检查路径配置。

### Q: HTTPS连接失败
A: 检查证书验证设置，可能需要禁用SSL验证进行测试：
```cpp
curl_easy_setopt(curl, CURLOPT_SSL_VERIFYPEER, 0L);
curl_easy_setopt(curl, CURLOPT_SSL_VERIFYHOST, 0L);
```

### Q: 运行时找不到.so文件
A: 确保所有.so文件都已复制到 `libs/arm64-v8a/` 目录，并在build-profile.json5中正确配置。
