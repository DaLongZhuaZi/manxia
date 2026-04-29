@ECHO OFF
@SETLOCAL

REM ============================================================
REM HarmonyOS libcurl HTTPS+SFTP版 交叉编译脚本
REM 依赖: 需要先运行 build_mbedtls_ohos.bat 编译 mbedTLS
REM 可选: 运行 build_libssh2_ohos.bat 编译 libssh2 以启用 SFTP
REM ============================================================

REM 设置 OHOS NDK 路径
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

REM mbedTLS 安装路径
SET MBEDTLS_DIR=%CD%\install-mbedtls-arm64

REM libssh2 安装路径 (可选, 用于 SFTP 支持)
SET LIBSSH2_DIR=%CD%\install-libssh2-arm64

REM 检查依赖
IF NOT EXIST "%CURL_DIR%" (
    ECHO.
    ECHO 错误: curl 源码不存在！请先下载 curl-%CURL_VERSION%.tar.gz
    PAUSE
    EXIT /B 1
)

IF NOT EXIST "%MBEDTLS_DIR%\lib" (
    ECHO.
    ECHO 错误: mbedTLS 未编译！请先运行 build_mbedtls_ohos.bat
    PAUSE
    EXIT /B 1
)

REM 检查 libssh2 (可选)
SET USE_LIBSSH2=OFF
IF EXIST "%LIBSSH2_DIR%\lib\libssh2.a" (
    SET USE_LIBSSH2=ON
    ECHO.
    ECHO 检测到 libssh2，将启用 SFTP 支持
) ELSE (
    ECHO.
    ECHO 未检测到 libssh2，SFTP 将不可用
    ECHO 如需 SFTP 支持，请先运行 build_libssh2_ohos.bat
)

ECHO.
ECHO ============================================================
ECHO 开始编译 libcurl HTTPS版 for HarmonyOS arm64-v8a
ECHO 使用 mbedTLS 提供 SSL/TLS 支持
ECHO ============================================================
ECHO.

REM 创建构建目录
IF EXIST build-curl-https-arm64 RMDIR /S /Q build-curl-https-arm64
MKDIR build-curl-https-arm64
PUSHD build-curl-https-arm64

REM 配置 CMake - 启用 mbedTLS + libssh2 (SFTP)
ECHO 正在配置 CMake...

REM 如果 libssh2 可用，添加 SFTP 支持
IF "%USE_LIBSSH2%"=="ON" GOTO :BUILD_WITH_SFTP
IF "%USE_LIBSSH2%"=="OFF" GOTO :BUILD_WITHOUT_SFTP

:BUILD_WITH_SFTP
ECHO 启用 libssh2 SFTP 支持...
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
    -DCURL_USE_MBEDTLS=ON ^
    -DMBEDTLS_INCLUDE_DIRS="%MBEDTLS_DIR%\include" ^
    -DMBEDTLS_LIBRARY="%MBEDTLS_DIR%\lib\libmbedtls.so" ^
    -DMBEDX509_LIBRARY="%MBEDTLS_DIR%\lib\libmbedx509.so" ^
    -DMBEDCRYPTO_LIBRARY="%MBEDTLS_DIR%\lib\libmbedcrypto.so" ^
    -DCURL_ZLIB=OFF ^
    -DENABLE_UNIX_SOCKETS=OFF ^
    -DCURL_USE_LIBSSH2=ON ^
    -DLIBSSH2_INCLUDE_DIR="%LIBSSH2_DIR%\include" ^
    -DLIBSSH2_LIBRARY="%LIBSSH2_DIR%\lib\libssh2.a" ^
    -DCMAKE_INSTALL_PREFIX=../install-curl-https-arm64 ^
    ../%CURL_DIR%
GOTO :CMAKE_DONE

:BUILD_WITHOUT_SFTP
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
    -DCURL_USE_MBEDTLS=ON ^
    -DMBEDTLS_INCLUDE_DIRS="%MBEDTLS_DIR%\include" ^
    -DMBEDTLS_LIBRARY="%MBEDTLS_DIR%\lib\libmbedtls.so" ^
    -DMBEDX509_LIBRARY="%MBEDTLS_DIR%\lib\libmbedx509.so" ^
    -DMBEDCRYPTO_LIBRARY="%MBEDTLS_DIR%\lib\libmbedcrypto.so" ^
    -DCURL_ZLIB=OFF ^
    -DENABLE_UNIX_SOCKETS=OFF ^
    -DCURL_USE_LIBSSH2=OFF ^
    -DCMAKE_INSTALL_PREFIX=../install-curl-https-arm64 ^
    ../%CURL_DIR%

:CMAKE_DONE

IF %ERRORLEVEL% NEQ 0 (
    ECHO.
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
    ECHO.
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
ECHO libcurl HTTPS版 编译完成！
ECHO.
ECHO 支持的协议:
ECHO   - HTTP / HTTPS (WebDAV, 安全WebDAV)
ECHO   - FTP / FTPS   (文件传输, 安全FTP)
ECHO   - FILE         (本地文件)
IF "%USE_LIBSSH2%"=="ON" (
    ECHO   - SFTP         (SSH文件传输) [已启用]
) ELSE (
    ECHO   - SFTP         (SSH文件传输) [未启用 - 需要 libssh2]
)
ECHO.
ECHO 输出文件位置:
ECHO   头文件: install-curl-https-arm64\include\curl\
ECHO   库文件: install-curl-https-arm64\lib\libcurl.so
ECHO.
ECHO 需要复制的文件:
ECHO   1. libcurl.so      -> entry\libs\arm64-v8a\
ECHO   2. libmbedtls.so   -> entry\libs\arm64-v8a\
ECHO   3. libmbedx509.so  -> entry\libs\arm64-v8a\
ECHO   4. libmbedcrypto.so -> entry\libs\arm64-v8a\
IF "%USE_LIBSSH2%"=="ON" (
    ECHO   注意: SFTP 使用静态链接，libssh2 已编译进 libcurl.so
)
ECHO ============================================================
ECHO.

PAUSE
@ENDLOCAL
