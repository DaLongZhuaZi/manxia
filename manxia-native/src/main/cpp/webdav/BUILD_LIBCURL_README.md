# HarmonyOS libcurl 交叉编译指南

本文档详细说明如何为 HarmonyOS (API 18, arm64-v8a) 交叉编译 libcurl 库。

## 前置条件

1. **DevEco Studio** 已安装，且已下载 Native SDK
2. **Windows 系统**（本脚本针对 Windows 编写）
3. SDK 路径：`F:\DevEco Studio\sdk\default\openharmony\native`

## 步骤一：下载 curl 源码

1. 访问 curl 官网下载页面：https://curl.se/download.html
2. 或直接下载：https://curl.se/download/curl-8.5.0.tar.gz
3. 解压到 `entry\src\main\cpp\webdav\` 目录下
4. 确保存在 `curl-8.5.0` 文件夹

## 步骤二：运行编译脚本

1. 打开命令提示符（CMD）
2. 进入 webdav 目录：
   ```cmd
   cd F:\DevEcoStudioProject\manxia\entry\src\main\cpp\webdav
   ```
3. 运行编译脚本：
   ```cmd
   build_libcurl_ohos.bat
   ```

## 步骤三：集成到项目

编译完成后，需要将生成的文件复制到项目中：

### 3.1 复制头文件

将 `install-curl-arm64\include\curl\` 目录复制到：
```
entry\src\main\cpp\webdav\include\curl\
```

### 3.2 复制库文件

将 `install-curl-arm64\lib\libcurl.so` 复制到：
```
entry\libs\arm64-v8a\libcurl.so
```

如果 `libs\arm64-v8a` 目录不存在，请创建它。

### 3.3 更新 CMakeLists.txt

确保 `webdav\CMakeLists.txt` 正确链接 libcurl：

```cmake
# 设置头文件搜索目录
include_directories(
    ${CMAKE_CURRENT_SOURCE_DIR}
    ${CMAKE_CURRENT_SOURCE_DIR}/include
)

# 添加预编译的 libcurl
add_library(curl SHARED IMPORTED)
set_target_properties(curl PROPERTIES
    IMPORTED_LOCATION ${CMAKE_SOURCE_DIR}/../../../libs/${OHOS_ARCH}/libcurl.so
)

# 链接 libcurl
target_link_libraries(webdav_native PUBLIC
    libace_napi.z.so
    libhilog_ndk.z.so
    curl
)
```

## 常见问题

### Q1: CMake 配置失败

确保 OHOS_NDK 路径正确，检查 `ohos.toolchain.cmake` 文件是否存在。

### Q2: 编译时找不到头文件

确保 curl 源码已正确解压，且目录名为 `curl-8.5.0`。

### Q3: 链接时找不到 libcurl.so

确保库文件已复制到正确位置，且 CMakeLists.txt 中的路径正确。

## 编译选项说明

脚本中禁用了以下功能以减小库体积：
- LDAP/LDAPS
- Telnet
- DICT
- TFTP
- RTSP
- POP3/IMAP/SMTP
- Gopher
- SMB
- SSL（如需 HTTPS 支持，需要额外编译 OpenSSL）

如需启用 HTTPS 支持，需要：
1. 先交叉编译 OpenSSL 或 mbedTLS
2. 修改编译脚本，启用 `-DCURL_USE_OPENSSL=ON` 或 `-DCURL_USE_MBEDTLS=ON`
3. 添加 OpenSSL/mbedTLS 的头文件和库文件路径

## 目录结构

编译完成后的目录结构应该如下：

```
entry/
├── libs/
│   └── arm64-v8a/
│       └── libcurl.so
└── src/main/cpp/
    └── webdav/
        ├── include/
        │   └── curl/
        │       ├── curl.h
        │       ├── curlver.h
        │       └── ...
        ├── webdav_client.h
        ├── webdav_client.cpp
        ├── webdav_napi.cpp
        └── CMakeLists.txt
```
