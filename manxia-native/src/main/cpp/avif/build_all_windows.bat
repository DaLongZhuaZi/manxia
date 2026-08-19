@echo off
REM ==========================================
REM AVIF完整编译脚本 - Windows版
REM 编译libavif及所有依赖库（zlib, libaom）
REM ==========================================

setlocal enabledelayedexpansion
chcp 65001 >nul

echo ==========================================
echo libavif for HarmonyOS - Windows完整编译
echo ==========================================
echo.

REM ============================================
REM 配置区域
REM ============================================
set SDK_PATH=F:\HarmonyOS\SDK\18
set ARCH=arm64-v8a
set WORK_DIR=%~dp0build_windows
set OUTPUT_DIR=%~dp0..\..\..\..\..\libs\%ARCH%
set INCLUDE_OUTPUT=%~dp0thirdparty\libavif\include

REM SDK工具路径
set CMAKE=%SDK_PATH%\native\build-tools\cmake\bin\cmake.exe
set NINJA=%SDK_PATH%\native\build-tools\cmake\bin\ninja.exe
set TOOLCHAIN=%SDK_PATH%\native\build\cmake\ohos.toolchain.cmake

REM 添加Strawberry Perl到PATH
set PATH=C:\Strawberry\perl\bin;C:\Strawberry\c\bin;%PATH%

REM 检查SDK
if not exist "%CMAKE%" (
    echo 错误: 未找到CMake，请检查SDK路径
    echo 路径: %CMAKE%
    pause
    exit /b 1
)

echo SDK路径: %SDK_PATH%
echo 目标架构: %ARCH%
echo 工作目录: %WORK_DIR%
echo.

REM 创建目录
if not exist "%WORK_DIR%" mkdir "%WORK_DIR%"
if not exist "%OUTPUT_DIR%" mkdir "%OUTPUT_DIR%"
if not exist "%INCLUDE_OUTPUT%\avif" mkdir "%INCLUDE_OUTPUT%\avif"

cd /d "%WORK_DIR%"

REM ==========================================
echo 步骤1: 下载源码
REM ==========================================

REM 下载zlib
if not exist "zlib" (
    echo 下载zlib...
    git clone https://github.com/madler/zlib.git --depth=1 --branch v1.3.1
    if errorlevel 1 (
        echo 尝试gitee镜像...
        git clone https://gitee.com/mirrors/zlib.git --depth=1
    )
)

REM 下载libaom (AV1编解码器)
if not exist "aom" (
    echo 下载libaom...
    git clone https://aomedia.googlesource.com/aom --depth=1 --branch v3.8.0
    if errorlevel 1 (
        echo 尝试github镜像...
        git clone https://github.com/nickshanks/aom.git --depth=1
    )
)

REM 下载libavif
if not exist "libavif" (
    echo 下载libavif...
    git clone https://github.com/AOMediaCodec/libavif.git --depth=1 --branch v1.0.4
    if errorlevel 1 (
        echo 尝试gitee镜像...
        git clone https://gitee.com/nickshanks/libavif.git --depth=1
    )
)

REM ==========================================
echo.
echo 步骤2: 编译zlib
REM ==========================================

cd /d "%WORK_DIR%\zlib"
if not exist "build_%ARCH%" mkdir "build_%ARCH%"
cd "build_%ARCH%"

echo 配置zlib...
"%CMAKE%" -G Ninja ^
    -DCMAKE_TOOLCHAIN_FILE="%TOOLCHAIN%" ^
    -DCMAKE_MAKE_PROGRAM="%NINJA%" ^
    -DCMAKE_BUILD_TYPE=Release ^
    -DCMAKE_BUILD_WITH_INSTALL_RPATH=true ^
    -DOHOS_ARCH=%ARCH% ^
    -DCMAKE_INSTALL_PREFIX="%WORK_DIR%\install\%ARCH%" ^
    ..

if errorlevel 1 (
    echo zlib配置失败！
    pause
    exit /b 1
)

echo 编译zlib...
"%CMAKE%" --build . --config Release

if errorlevel 1 (
    echo zlib编译失败！
    pause
    exit /b 1
)

echo 安装zlib...
"%CMAKE%" --install .

echo zlib编译完成！
echo.

REM ==========================================
echo 步骤3: 编译libaom
REM ==========================================

cd /d "%WORK_DIR%\aom"
if not exist "build_%ARCH%" mkdir "build_%ARCH%"
cd "build_%ARCH%"

echo 配置libaom...
"%CMAKE%" -G Ninja ^
    -DCMAKE_TOOLCHAIN_FILE="%TOOLCHAIN%" ^
    -DCMAKE_MAKE_PROGRAM="%NINJA%" ^
    -DCMAKE_BUILD_TYPE=Release ^
    -DCMAKE_BUILD_WITH_INSTALL_RPATH=true ^
    -DOHOS_ARCH=%ARCH% ^
    -DCMAKE_INSTALL_PREFIX="%WORK_DIR%\install\%ARCH%" ^
    -DENABLE_DOCS=OFF ^
    -DENABLE_EXAMPLES=OFF ^
    -DENABLE_TESTDATA=OFF ^
    -DENABLE_TESTS=OFF ^
    -DENABLE_TOOLS=OFF ^
    -DCONFIG_AV1_ENCODER=1 ^
    -DCONFIG_AV1_DECODER=1 ^
    -DCONFIG_MULTITHREAD=0 ^
    -DCONFIG_RUNTIME_CPU_DETECT=0 ^
    -DBUILD_SHARED_LIBS=OFF ^
    -DAOM_TARGET_CPU=generic ^
    -DCONFIG_AV1_HIGHBITDEPTH=0 ^
    -DENABLE_NASM=OFF ^
    -DCONFIG_PIC=1 ^
    ..

if errorlevel 1 (
    echo libaom配置失败！
    pause
    exit /b 1
)

echo 编译libaom（这可能需要几分钟）...
"%CMAKE%" --build . --config Release

if errorlevel 1 (
    echo libaom编译失败！
    pause
    exit /b 1
)

echo 安装libaom...
"%CMAKE%" --install .

echo libaom编译完成！
echo.

REM ==========================================
echo 步骤4: 编译libavif
REM ==========================================

cd /d "%WORK_DIR%\libavif"
if not exist "build_%ARCH%" mkdir "build_%ARCH%"
cd "build_%ARCH%"

echo 配置libavif...
"%CMAKE%" -G Ninja ^
    -DCMAKE_TOOLCHAIN_FILE="%TOOLCHAIN%" ^
    -DCMAKE_MAKE_PROGRAM="%NINJA%" ^
    -DCMAKE_BUILD_TYPE=Release ^
    -DCMAKE_BUILD_WITH_INSTALL_RPATH=true ^
    -DOHOS_ARCH=%ARCH% ^
    -DCMAKE_INSTALL_PREFIX="%WORK_DIR%\install\%ARCH%" ^
    -DCMAKE_PREFIX_PATH="%WORK_DIR%\install\%ARCH%" ^
    -DAVIF_CODEC_AOM=SYSTEM ^
    -DAVIF_CODEC_DAV1D=OFF ^
    -DAVIF_CODEC_LIBGAV1=OFF ^
    -DAVIF_CODEC_RAV1E=OFF ^
    -DAVIF_CODEC_SVT=OFF ^
    -DAVIF_BUILD_APPS=OFF ^
    -DAVIF_BUILD_TESTS=OFF ^
    -DAVIF_ENABLE_WERROR=OFF ^
    -DBUILD_SHARED_LIBS=ON ^
    -DAOM_LIBRARY="%WORK_DIR%\install\%ARCH%\lib\libaom.a" ^
    -DAOM_INCLUDE_DIR="%WORK_DIR%\install\%ARCH%\include" ^
    ..

if errorlevel 1 (
    echo libavif配置失败！
    pause
    exit /b 1
)

echo 编译libavif...
"%CMAKE%" --build . --config Release

if errorlevel 1 (
    echo libavif编译失败！
    pause
    exit /b 1
)

echo 安装libavif...
"%CMAKE%" --install .

echo libavif编译完成！
echo.

REM ==========================================
echo 步骤5: 复制结果文件
REM ==========================================

echo 复制库文件...
copy /Y "%WORK_DIR%\install\%ARCH%\lib\*.so*" "%OUTPUT_DIR%\" 2>nul
copy /Y "%WORK_DIR%\install\%ARCH%\lib\*.a" "%OUTPUT_DIR%\" 2>nul
copy /Y "%WORK_DIR%\install\%ARCH%\bin\*.so*" "%OUTPUT_DIR%\" 2>nul

echo 复制头文件...
copy /Y "%WORK_DIR%\libavif\include\avif\*.h" "%INCLUDE_OUTPUT%\avif\" 2>nul

echo.
echo ==========================================
echo 编译完成！
echo ==========================================
echo.
echo 库文件位置: %OUTPUT_DIR%
echo 头文件位置: %INCLUDE_OUTPUT%
echo.
echo 请在DevEco Studio中重新编译项目。
echo.

dir "%OUTPUT_DIR%"

pause
