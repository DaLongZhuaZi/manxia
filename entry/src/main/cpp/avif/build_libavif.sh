#!/bin/bash
# AVIF库编译脚本 - 用于在WSL2中编译HarmonyOS版本的libavif
# 使用方法: 
#   1. 在WSL2中运行此脚本
#   2. 确保已安装OpenHarmony SDK
#   3. ./build_libavif.sh

set -e

echo "=========================================="
echo "libavif for HarmonyOS Build Script"
echo "=========================================="

# 配置路径（根据实际情况修改）
OHOS_SDK_PATH="${OHOS_SDK_PATH:-/opt/ohos-sdk}"
OUTPUT_DIR="${OUTPUT_DIR:-./output}"
ARCH="${ARCH:-arm64-v8a}"  # arm64-v8a 或 armeabi-v7a

# 检查SDK
if [ ! -d "$OHOS_SDK_PATH" ]; then
    echo "Error: OpenHarmony SDK not found at $OHOS_SDK_PATH"
    echo "Please set OHOS_SDK_PATH environment variable"
    exit 1
fi

# 创建工作目录
WORK_DIR=$(mktemp -d)
echo "Working directory: $WORK_DIR"
cd "$WORK_DIR"

# 克隆tpc_c_cplusplus仓库
echo "Cloning tpc_c_cplusplus repository..."
git clone https://gitee.com/openharmony-sig/tpc_c_cplusplus.git --depth=1

cd tpc_c_cplusplus/lycium

# 设置环境变量
export OHOS_SDK="$OHOS_SDK_PATH"

# 编译libavif
echo "Building libavif for $ARCH..."
./build.sh libavif

# 检查编译结果
if [ -d "usr/libavif/$ARCH" ]; then
    echo "Build successful!"
    
    # 创建输出目录
    mkdir -p "$OUTPUT_DIR/$ARCH"
    
    # 复制库文件
    cp -r usr/libavif/$ARCH/lib/* "$OUTPUT_DIR/$ARCH/"
    cp -r usr/libavif/$ARCH/include "$OUTPUT_DIR/"
    
    # 复制依赖库
    if [ -d "usr/libaom/$ARCH/lib" ]; then
        cp usr/libaom/$ARCH/lib/*.a "$OUTPUT_DIR/$ARCH/" 2>/dev/null || true
    fi
    if [ -d "usr/libyuv/$ARCH/lib" ]; then
        cp usr/libyuv/$ARCH/lib/*.so* "$OUTPUT_DIR/$ARCH/" 2>/dev/null || true
    fi
    
    echo "Libraries copied to $OUTPUT_DIR/$ARCH"
    ls -la "$OUTPUT_DIR/$ARCH"
else
    echo "Build failed - output directory not found"
    exit 1
fi

# 清理
cd /
rm -rf "$WORK_DIR"

echo "=========================================="
echo "Build complete!"
echo "Copy the following files to your project:"
echo "  - $OUTPUT_DIR/$ARCH/*.so -> entry/libs/$ARCH/"
echo "  - $OUTPUT_DIR/$ARCH/*.a -> entry/libs/$ARCH/"
echo "  - $OUTPUT_DIR/include -> entry/src/main/cpp/avif/thirdparty/libavif/"
echo "=========================================="
