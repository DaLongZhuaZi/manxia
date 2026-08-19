@ECHO OFF
@SETLOCAL

REM ============================================================
REM HarmonyOS mbedTLS 交叉编译脚本
REM 用于为 libcurl 提供 HTTPS 支持
REM ============================================================

REM 设置 OHOS NDK 路径
SET OHOS_NDK=F:\DevEco Studio\sdk\default\openharmony\native

REM 设置工具路径
SET CMAKE_EXE=%OHOS_NDK%\build-tools\cmake\bin\cmake.exe
SET NINJA_EXE=%OHOS_NDK%\build-tools\cmake\bin\ninja.exe
SET TOOLCHAIN_FILE=%OHOS_NDK%\build\cmake\ohos.toolchain.cmake

REM 设置 PATH
SET PATH=%OHOS_NDK%\llvm\bin;%OHOS_NDK%\build-tools\cmake\bin;%PATH%

REM mbedTLS 版本
SET MBEDTLS_VERSION=3.5.1
SET MBEDTLS_DIR=mbedtls-%MBEDTLS_VERSION%

REM 检查 mbedTLS 源码是否存在
IF NOT EXIST "%MBEDTLS_DIR%" (
    ECHO.
    ECHO ============================================================
    ECHO 请先下载 mbedTLS 源码！
    ECHO.
    ECHO 下载地址: https://github.com/Mbed-TLS/mbedtls/releases/download/v%MBEDTLS_VERSION%/mbedtls-%MBEDTLS_VERSION%.tar.bz2
    ECHO.
    ECHO 或使用 git clone:
    ECHO   git clone --branch v%MBEDTLS_VERSION% https://github.com/Mbed-TLS/mbedtls.git %MBEDTLS_DIR%
    ECHO.
    ECHO 下载后解压到当前目录，确保存在 %MBEDTLS_DIR% 文件夹
    ECHO ============================================================
    ECHO.
    PAUSE
    EXIT /B 1
)

ECHO.
ECHO ============================================================
ECHO 开始编译 mbedTLS for HarmonyOS arm64-v8a
ECHO ============================================================
ECHO.

REM 创建构建目录
IF EXIST build-mbedtls-arm64 RMDIR /S /Q build-mbedtls-arm64
MKDIR build-mbedtls-arm64
PUSHD build-mbedtls-arm64

REM 配置 CMake
ECHO 正在配置 CMake...
"%CMAKE_EXE%" -G Ninja ^
    -DCMAKE_TOOLCHAIN_FILE="%TOOLCHAIN_FILE%" ^
    -DCMAKE_MAKE_PROGRAM="%NINJA_EXE%" ^
    -DOHOS_ARCH="arm64-v8a" ^
    -DCMAKE_BUILD_TYPE=Release ^
    -DENABLE_PROGRAMS=OFF ^
    -DENABLE_TESTING=OFF ^
    -DUSE_SHARED_MBEDTLS_LIBRARY=ON ^
    -DUSE_STATIC_MBEDTLS_LIBRARY=OFF ^
    -DMBEDTLS_FATAL_WARNINGS=OFF ^
    -DCMAKE_C_FLAGS="-Wno-error -Wno-unused-command-line-argument" ^
    -DCMAKE_INSTALL_PREFIX=../install-mbedtls-arm64 ^
    ../%MBEDTLS_DIR%

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
ECHO mbedTLS 编译完成！
ECHO.
ECHO 输出文件位置:
ECHO   头文件: install-mbedtls-arm64\include\
ECHO   库文件: install-mbedtls-arm64\lib\
ECHO.
ECHO 接下来请运行 build_libcurl_https.bat 编译支持 HTTPS 的 libcurl
ECHO ============================================================
ECHO.

PAUSE
@ENDLOCAL
