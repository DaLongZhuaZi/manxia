@ECHO OFF
@SETLOCAL

REM ============================================================
REM HarmonyOS libssh2 交叉编译脚本
REM 依赖: 需要先运行 build_mbedtls_ohos.bat 编译 mbedTLS
REM 用途: 为 libcurl 提供 SFTP 支持
REM ============================================================

REM 设置 OHOS NDK 路径
SET OHOS_NDK=F:\DevEco Studio\sdk\default\openharmony\native

REM 设置工具路径
SET CMAKE_EXE=%OHOS_NDK%\build-tools\cmake\bin\cmake.exe
SET NINJA_EXE=%OHOS_NDK%\build-tools\cmake\bin\ninja.exe
SET TOOLCHAIN_FILE=%OHOS_NDK%\build\cmake\ohos.toolchain.cmake

REM 设置 PATH
SET PATH=%OHOS_NDK%\llvm\bin;%OHOS_NDK%\build-tools\cmake\bin;%PATH%

REM libssh2 版本
SET LIBSSH2_VERSION=1.11.0
SET LIBSSH2_DIR=libssh2-%LIBSSH2_VERSION%

REM mbedTLS 安装路径 (已编译好的)
SET MBEDTLS_DIR=%CD%\install-mbedtls-arm64

REM 检查依赖
IF NOT EXIST "%LIBSSH2_DIR%" (
    ECHO.
    ECHO ============================================================
    ECHO 请先下载 libssh2 源码！
    ECHO.
    ECHO 下载地址: https://github.com/libssh2/libssh2/releases/download/libssh2-%LIBSSH2_VERSION%/libssh2-%LIBSSH2_VERSION%.tar.gz
    ECHO.
    ECHO 或使用 git clone:
    ECHO   git clone --branch libssh2-%LIBSSH2_VERSION% https://github.com/libssh2/libssh2.git %LIBSSH2_DIR%
    ECHO.
    ECHO 下载后解压到当前目录，确保存在 %LIBSSH2_DIR% 文件夹
    ECHO ============================================================
    ECHO.
    PAUSE
    EXIT /B 1
)

IF NOT EXIST "%MBEDTLS_DIR%\lib" (
    ECHO.
    ECHO 错误: mbedTLS 未编译！请先运行 build_mbedtls_ohos.bat
    PAUSE
    EXIT /B 1
)

ECHO.
ECHO ============================================================
ECHO 开始编译 libssh2 for HarmonyOS arm64-v8a
ECHO 使用 mbedTLS 作为加密后端
ECHO ============================================================
ECHO.

REM 创建构建目录
IF EXIST build-libssh2-arm64 RMDIR /S /Q build-libssh2-arm64
MKDIR build-libssh2-arm64
PUSHD build-libssh2-arm64

REM 配置 CMake - 使用 mbedTLS 后端
ECHO 正在配置 CMake...
"%CMAKE_EXE%" -G Ninja ^
    -DCMAKE_TOOLCHAIN_FILE="%TOOLCHAIN_FILE%" ^
    -DCMAKE_MAKE_PROGRAM="%NINJA_EXE%" ^
    -DOHOS_ARCH="arm64-v8a" ^
    -DCMAKE_BUILD_TYPE=Release ^
    -DCRYPTO_BACKEND=mbedTLS ^
    -DMBEDTLS_INCLUDE_DIRS="%MBEDTLS_DIR%\include" ^
    -DMBEDTLS_LIBRARY="%MBEDTLS_DIR%\lib\libmbedtls.so" ^
    -DMBEDX509_LIBRARY="%MBEDTLS_DIR%\lib\libmbedx509.so" ^
    -DMBEDCRYPTO_LIBRARY="%MBEDTLS_DIR%\lib\libmbedcrypto.so" ^
    -DENABLE_ZLIB_COMPRESSION=OFF ^
    -DBUILD_SHARED_LIBS=OFF ^
    -DBUILD_EXAMPLES=OFF ^
    -DBUILD_TESTING=OFF ^
    -DCMAKE_INSTALL_PREFIX=../install-libssh2-arm64 ^
    ../%LIBSSH2_DIR%

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
ECHO libssh2 编译完成！
ECHO.
ECHO 输出文件位置:
ECHO   头文件: install-libssh2-arm64\include\
ECHO   库文件: install-libssh2-arm64\lib\libssh2.a
ECHO.
ECHO 接下来请运行 build_libcurl_https.bat 重新编译 libcurl
ECHO libcurl 将自动检测 libssh2 并启用 SFTP 支持
ECHO ============================================================
ECHO.

PAUSE
@ENDLOCAL
