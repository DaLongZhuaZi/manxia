@echo off
REM AVIF库Windows编译脚本
REM 使用OpenHarmony SDK在Windows上交叉编译libavif

setlocal enabledelayedexpansion

echo ==========================================
echo libavif for HarmonyOS - Windows Build
echo ==========================================

REM 配置SDK路径（根据实际情况修改）
set SDK_PATH=F:\HarmonyOS\SDK\18
set ARCH=arm64-v8a

REM 检查SDK
if not exist "%SDK_PATH%\native\build-tools\cmake\bin\cmake.exe" (
    echo 错误: 未找到SDK，请检查路径: %SDK_PATH%
    echo 请修改脚本中的SDK_PATH变量
    pause
    exit /b 1
)

echo SDK路径: %SDK_PATH%
echo 目标架构: %ARCH%
echo.

REM 设置工具路径
set CMAKE=%SDK_PATH%\native\build-tools\cmake\bin\cmake.exe
set NINJA=%SDK_PATH%\native\build-tools\cmake\bin\ninja.exe
set TOOLCHAIN=%SDK_PATH%\native\build\cmake\ohos.toolchain.cmake

REM 创建工作目录
set WORK_DIR=%~dp0build_temp
if not exist "%WORK_DIR%" mkdir "%WORK_DIR%"
cd /d "%WORK_DIR%"

echo ==========================================
echo 步骤1: 下载libavif源码
echo ==========================================

if not exist "libavif" (
    echo 正在克隆libavif...
    git clone https://github.com/AOMediaCodec/libavif.git --depth=1 --branch v1.0.4
    if errorlevel 1 (
        echo 克隆失败，尝试使用gitee镜像...
        git clone https://gitee.com/mirrors/libavif.git --depth=1
    )
)

cd libavif

echo ==========================================
echo 步骤2: 配置CMake
echo ==========================================

REM 创建构建目录
if not exist "build_%ARCH%" mkdir "build_%ARCH%"
cd "build_%ARCH%"

REM 运行CMake配置
echo 运行CMake配置...
"%CMAKE%" -G Ninja ^
    -DCMAKE_TOOLCHAIN_FILE="%TOOLCHAIN%" ^
    -DCMAKE_MAKE_PROGRAM="%NINJA%" ^
    -DCMAKE_BUILD_TYPE=Release ^
    -DCMAKE_BUILD_WITH_INSTALL_RPATH=true ^
    -DOHOS_ARCH=%ARCH% ^
    -DAVIF_CODEC_AOM=OFF ^
    -DAVIF_CODEC_DAV1D=OFF ^
    -DAVIF_CODEC_LIBGAV1=OFF ^
    -DAVIF_CODEC_RAV1E=OFF ^
    -DAVIF_CODEC_SVT=OFF ^
    -DAVIF_BUILD_APPS=OFF ^
    -DAVIF_BUILD_TESTS=OFF ^
    -DAVIF_ENABLE_WERROR=OFF ^
    -DBUILD_SHARED_LIBS=ON ^
    ..

if errorlevel 1 (
    echo CMake配置失败！
    pause
    exit /b 1
)

echo ==========================================
echo 步骤3: 编译
echo ==========================================

"%CMAKE%" --build .

if errorlevel 1 (
    echo 编译失败！
    pause
    exit /b 1
)

echo ==========================================
echo 步骤4: 复制结果
echo ==========================================

set OUTPUT_DIR=%~dp0..\..\..\..\..\libs\%ARCH%
if not exist "%OUTPUT_DIR%" mkdir "%OUTPUT_DIR%"

echo 复制库文件到: %OUTPUT_DIR%
copy /Y *.so* "%OUTPUT_DIR%\" 2>nul
copy /Y *.dll "%OUTPUT_DIR%\" 2>nul

REM 复制头文件
set INCLUDE_DIR=%~dp0thirdparty\libavif\include\avif
if not exist "%INCLUDE_DIR%" mkdir "%INCLUDE_DIR%"
copy /Y ..\include\avif\*.h "%INCLUDE_DIR%\"

echo ==========================================
echo 编译完成！
echo ==========================================
echo.
echo 库文件位置: %OUTPUT_DIR%
echo 头文件位置: %INCLUDE_DIR%
echo.

pause
