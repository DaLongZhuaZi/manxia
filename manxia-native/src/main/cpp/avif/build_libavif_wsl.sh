#!/bin/bash
# AVIF库编译脚本 - 专为你的环境配置
# 在WSL2 Ubuntu中执行此脚本

set -e

echo "=========================================="
echo "libavif for HarmonyOS Build Script"
echo "=========================================="

# ============================================
# 配置区域 - 根据你的实际环境设置
# ============================================

# OpenHarmony SDK路径（两个可选路径，脚本会自动检测）
SDK_PATH_1="/mnt/f/HarmonyOS/SDK"
SDK_PATH_2="/mnt/f/DevEco Studio/sdk/default/openharmony"

# 自动检测SDK路径
if [ -d "$SDK_PATH_1/native/llvm/bin" ]; then
    export OHOS_SDK="$SDK_PATH_1"
    echo "使用SDK路径: $SDK_PATH_1"
elif [ -d "$SDK_PATH_2/native/llvm/bin" ]; then
    export OHOS_SDK="$SDK_PATH_2"
    echo "使用SDK路径: $SDK_PATH_2"
else
    echo "错误: 未找到有效的OpenHarmony SDK"
    echo "请检查以下路径:"
    echo "  - $SDK_PATH_1"
    echo "  - $SDK_PATH_2"
    echo ""
    echo "确保路径下存在 native/llvm/bin/clang 文件"
    exit 1
fi

# 验证SDK
if [ ! -f "$OHOS_SDK/native/llvm/bin/clang" ]; then
    echo "错误: SDK路径无效，找不到 clang 编译器"
    echo "路径: $OHOS_SDK/native/llvm/bin/clang"
    exit 1
fi

echo "SDK验证通过: $OHOS_SDK"
echo ""

# 工作目录
WORK_DIR="/mnt/c/Users/13359/tpc_c_cplusplus"
OUTPUT_DIR="/mnt/f/DevEcoStudioProject/manxia/entry/libs"

# 检查tpc_c_cplusplus是否已克隆
if [ ! -d "$WORK_DIR" ]; then
    echo "克隆 tpc_c_cplusplus 仓库..."
    cd /mnt/c/Users/13359
    git clone https://gitee.com/openharmony-sig/tpc_c_cplusplus.git --depth=1
fi

cd "$WORK_DIR/lycium"

echo "开始编译 libavif..."
echo "这可能需要几分钟时间..."
echo ""

# 编译libavif（包含所有依赖）
./build.sh libavif

echo ""
echo "=========================================="
echo "编译完成，开始复制文件..."
echo "=========================================="

# 创建输出目录
mkdir -p "$OUTPUT_DIR/arm64-v8a"
mkdir -p "$OUTPUT_DIR/armeabi-v7a"

# 复制64位库
if [ -d "usr/libavif/arm64-v8a/lib" ]; then
    echo "复制 arm64-v8a 库文件..."
    cp -v usr/libavif/arm64-v8a/lib/*.so* "$OUTPUT_DIR/arm64-v8a/" 2>/dev/null || true
    cp -v usr/libaom/arm64-v8a/lib/*.a "$OUTPUT_DIR/arm64-v8a/" 2>/dev/null || true
    cp -v usr/libyuv/arm64-v8a/lib/*.so* "$OUTPUT_DIR/arm64-v8a/" 2>/dev/null || true
fi

# 复制32位库
if [ -d "usr/libavif/armeabi-v7a/lib" ]; then
    echo "复制 armeabi-v7a 库文件..."
    cp -v usr/libavif/armeabi-v7a/lib/*.so* "$OUTPUT_DIR/armeabi-v7a/" 2>/dev/null || true
    cp -v usr/libaom/armeabi-v7a/lib/*.a "$OUTPUT_DIR/armeabi-v7a/" 2>/dev/null || true
    cp -v usr/libyuv/armeabi-v7a/lib/*.so* "$OUTPUT_DIR/armeabi-v7a/" 2>/dev/null || true
fi

# 复制头文件
INCLUDE_DIR="/mnt/f/DevEcoStudioProject/manxia/entry/src/main/cpp/avif/thirdparty/libavif/include"
mkdir -p "$INCLUDE_DIR"
if [ -d "usr/libavif/arm64-v8a/include" ]; then
    echo "复制头文件..."
    cp -rv usr/libavif/arm64-v8a/include/* "$INCLUDE_DIR/" 2>/dev/null || true
fi

echo ""
echo "=========================================="
echo "完成！"
echo "=========================================="
echo ""
echo "库文件已复制到:"
echo "  - $OUTPUT_DIR/arm64-v8a/"
echo "  - $OUTPUT_DIR/armeabi-v7a/"
echo ""
echo "头文件已复制到:"
echo "  - $INCLUDE_DIR/"
echo ""
echo "现在可以在DevEco Studio中重新编译项目了。"
