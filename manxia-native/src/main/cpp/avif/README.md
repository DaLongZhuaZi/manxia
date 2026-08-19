# AVIF图片解码模块

本模块为HarmonyOS应用提供AVIF格式图片的解码支持。

## 背景

HarmonyOS的ArkTS `PixelMap` 原生不支持AVIF格式解码。本模块通过Native C++层集成libavif库来实现AVIF解码功能。

## 架构

```
┌─────────────────────────────────────┐
│         ArkTS Layer                 │
│  AvifDecoder.ets (Framework/Image)  │
└──────────────┬──────────────────────┘
               │ NAPI
┌──────────────▼──────────────────────┐
│         Native C++ Layer            │
│  avif_napi.cpp + avif_decoder.cpp   │
└──────────────┬──────────────────────┘
               │
┌──────────────▼──────────────────────┐
│         libavif Library             │
│  (需要预编译的.so/.a文件)            │
└─────────────────────────────────────┘
```

## 使用方法

### 1. 在ArkTS中使用

```typescript
import { AvifDecoder, isAvifSupported, decodeAvif } from '../Framework/Image/AvifDecoder';

// 检查是否支持AVIF
if (isAvifSupported()) {
  console.log('AVIF解码可用');
}

// 解码AVIF图片
const avifData: ArrayBuffer = ...; // AVIF图片数据
const pixelMap = await decodeAvif(avifData);
if (pixelMap) {
  // 使用pixelMap显示图片
  Image(pixelMap)
}
```

### 2. 检查图片格式

```typescript
import { isAvifFormat } from '../Framework/Image/AvifDecoder';

const data: ArrayBuffer = ...;
if (isAvifFormat(data)) {
  // 是AVIF格式
}
```

## 编译libavif库

由于libavif需要交叉编译，建议在Linux环境（如WSL2）中进行：

### 方法一：使用编译脚本（推荐）

```bash
# 在WSL2中执行
cd entry/src/main/cpp/avif
chmod +x build_libavif.sh
OHOS_SDK_PATH=/path/to/ohos-sdk ./build_libavif.sh
```

### 方法二：手动编译

1. 克隆OpenHarmony三方库仓库：
```bash
git clone https://gitee.com/openharmony-sig/tpc_c_cplusplus.git --depth=1
```

2. 编译libavif：
```bash
cd tpc_c_cplusplus/lycium
export OHOS_SDK=/path/to/ohos-sdk
./build.sh libavif
```

3. 复制编译产物：
```bash
# 库文件
cp usr/libavif/arm64-v8a/lib/*.so entry/libs/arm64-v8a/
cp usr/libaom/arm64-v8a/lib/*.a entry/libs/arm64-v8a/
cp usr/libyuv/arm64-v8a/lib/*.so entry/libs/arm64-v8a/

# 头文件
mkdir -p entry/src/main/cpp/avif/thirdparty/libavif/include
cp -r usr/libavif/arm64-v8a/include/* entry/src/main/cpp/avif/thirdparty/libavif/include/
```

## 文件结构

```
entry/src/main/cpp/avif/
├── CMakeLists.txt      # CMake构建配置
├── avif_decoder.h      # 解码器头文件
├── avif_decoder.cpp    # 解码器实现
├── avif_napi.cpp       # NAPI接口
├── build_libavif.sh    # 编译脚本
├── README.md           # 本文档
└── thirdparty/         # 第三方库（需要手动添加）
    └── libavif/
        └── include/
            └── avif/
                └── avif.h

entry/libs/
├── arm64-v8a/          # 64位库
│   ├── libavif.so
│   ├── libaom.a
│   └── libyuv.so
└── armeabi-v7a/        # 32位库（可选）
    ├── libavif.so
    ├── libaom.a
    └── libyuv.so
```

## 依赖库说明

| 库名 | 说明 | 类型 |
|------|------|------|
| libavif | AVIF编解码核心库 | 动态库(.so) |
| libaom | AV1编解码器 | 静态库(.a) |
| libyuv | YUV颜色空间转换 | 动态库(.so) |

## 回退模式

如果libavif库不可用，模块会进入回退模式：
- `isAvifSupported()` 返回 `false`
- `decodeAvif()` 返回 `null`
- 日志中会输出如何启用AVIF支持的说明

## 注意事项

1. **性能**：AVIF解码比JPEG/PNG更耗时，建议在后台线程执行
2. **内存**：大图片解码会占用较多内存，注意及时释放PixelMap
3. **兼容性**：本模块支持AVIF、AVIS、HEIC、MIF1等相关格式
4. **动画**：当前版本只解码第一帧，不支持动画AVIF

## 常见问题

### Q: 编译时找不到avif.h
A: 确保已将libavif的头文件复制到 `thirdparty/libavif/include/` 目录

### Q: 运行时报找不到libavif.so
A: 确保已将.so文件复制到 `entry/libs/${OHOS_ARCH}/` 目录

### Q: 解码返回null
A: 检查日志输出，可能是：
- libavif未正确加载
- 输入数据不是有效的AVIF格式
- 图片损坏或不支持的AVIF特性

## 参考资料

- [libavif GitHub](https://github.com/AOMediaCodec/libavif)
- [OpenHarmony三方库](https://gitee.com/openharmony-sig/tpc_c_cplusplus)
- [HarmonyOS NDK开发指南](https://developer.huawei.com/consumer/cn/doc/harmonyos-guides-V5/ndk-development-overview-V5)
