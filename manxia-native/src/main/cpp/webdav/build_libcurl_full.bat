@ECHO OFF
@SETLOCAL

REM ============================================================
REM HarmonyOS libcurl 完整版交叉编译脚本
REM 支持更多协议: HTTP, HTTPS, FTP, FTPS, FILE
REM ============================================================

REM 设置 OHOS NDK 路径 (请根据实际安装路径修改)
SET OHOS_NDK=F:\DevEco Studio\sdk\default\openharmony\native

REM 设置工具路径
SET CMAKE_EXE=%OHOS_NDK%\build-tools\cmake\bin\cmake.exe
SET NINJA_EXE=%OHOS_NDK%\build-tools\cmake\bin\ninja.exe
SET TOOLCHAIN_FILE=%OHOS_NDK%\build\cmake\ohos.toolchain.cmake

REM 设置 PATH
SET PATH=%OHOS_NDK%\llvm\bin;%OHOS_NDK%\build-tools\cmake\bin;%PATH%

REM curl 源码版本
SET CURL_VERSION=8.5.0
SET CURL_DIR=curl-%CURL_VERSION%

REM 检查 curl 源码是否存在
IF NOT EXIST "%CURL_DIR%" (
    ECHO.
    ECHO ============================================================
    ECHO 请先下载 curl 源码！
    ECHO.
    ECHO 下载地址: https://curl.se/download/curl-%CURL_VERSION%.tar.gz
    ECHO ============================================================
    ECHO.
    PAUSE
    EXIT /B 1
)

ECHO.
ECHO ============================================================
ECHO 开始编译 libcurl 完整版 for HarmonyOS arm64-v8a
ECHO 支持协议: HTTP, HTTPS, FTP, FTPS, FILE
ECHO ============================================================
ECHO.

REM 创建构建目录
IF EXIST build-curl-full-arm64 RMDIR /S /Q build-curl-full-arm64
MKDIR build-curl-full-arm64
PUSHD build-curl-full-arm64

REM 配置 CMake - 启用更多协议
ECHO 正在配置 CMake...
"%CMAKE_EXE%" -G Ninja ^
    -DCMAKE_TOOLCHAIN_FILE="%TOOLCHAIN_FILE%" ^
    -DCMAKE_MAKE_PROGRAM="%NINJA_EXE%" ^
    -DOHOS_ARCH="arm64-v8a" ^
    -DCMAKE_BUILD_TYPE=Release ^
    -DBUILD_SHARED_LIBS=ON ^
    -DBUILD_CURL_EXE=OFF ^
    -DCURL_DISABLE_LDAP=ON ^
    -DCURL_DISABLE_LDAPS=ON ^
    -DCURL_DISABLE_TELNET=ON ^
    -DCURL_DISABLE_DICT=ON ^
    -DCURL_DISABLE_FILE=OFF ^
    -DCURL_DISABLE_TFTP=ON ^
    -DCURL_DISABLE_RTSP=ON ^
    -DCURL_DISABLE_POP3=ON ^
    -DCURL_DISABLE_IMAP=ON ^
    -DCURL_DISABLE_SMTP=ON ^
    -DCURL_DISABLE_GOPHER=ON ^
    -DCURL_DISABLE_SMB=ON ^
    -DCURL_DISABLE_FTP=OFF ^
    -DHTTP_ONLY=OFF ^
    -DCURL_USE_OPENSSL=OFF ^
    -DCURL_USE_MBEDTLS=OFF ^
    -DCURL_ZLIB=OFF ^
    -DENABLE_UNIX_SOCKETS=OFF ^
    -DCMAKE_INSTALL_PREFIX=../install-curl-full-arm64 ^
    ../%CURL_DIR%

IF %ERRORLEVEL% NEQ 0 (
    ECHO CMake 配置失败！
    POPD
    PAUSE
    EXIT /B 1
)

REM 编译
ECHO.
ECHO 正在编译...
"%CMAKE_EXE%" --build . --parallel %NUMBER_OF_PROCESSORS%

IF %ERRORLEVEL% NEQ 0 (
    ECHO 编译失败！
    POPD
    PAUSE
    EXIT /B 1
)

REM 安装
ECHO.
ECHO 正在安装...
"%CMAKE_EXE%" --build . --target install

POPD

ECHO.
ECHO ============================================================
ECHO 编译完成！
ECHO.
ECHO 当前支持的协议:
ECHO   - HTTP  (WebDAV)
ECHO   - FTP   (文件传输)
ECHO   - FILE  (本地文件)
ECHO.
ECHO 注意: HTTPS/FTPS 需要额外编译 OpenSSL/mbedTLS
ECHO ============================================================
ECHO.

PAUSE
@ENDLOCAL
