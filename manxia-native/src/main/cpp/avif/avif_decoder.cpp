/**
 * AVIF图片解码器实现
 * 支持两种模式：
 * 1. 使用libavif库（完整功能）
 * 2. 回退模式（基础功能，用于libavif不可用时）
 */

#include "avif_decoder.h"
#include <cstring>
#include <hilog/log.h>

#ifdef HAVE_LIBAVIF
#if HAVE_LIBAVIF
#include <avif/avif.h>
#endif
#endif

#undef LOG_TAG
#define LOG_TAG "AvifDecoder"
#define LOG_DOMAIN 0x3201

#define AVIF_LOGI(...) OH_LOG_INFO(LOG_APP, __VA_ARGS__)
#define AVIF_LOGE(...) OH_LOG_ERROR(LOG_APP, __VA_ARGS__)
#define AVIF_LOGD(...) OH_LOG_DEBUG(LOG_APP, __VA_ARGS__)

namespace avif {

// AVIF文件签名
// ftyp box with brand 'avif' or 'avis'
static const uint8_t AVIF_SIGNATURE[] = {0x00, 0x00, 0x00};  // 前4字节是box size
static const char FTYP_BOX[] = "ftyp";
static const char AVIF_BRAND[] = "avif";
static const char AVIS_BRAND[] = "avis";
static const char HEIC_BRAND[] = "heic";
static const char MIFF_BRAND[] = "mif1";

AvifDecoder::AvifDecoder() {
    AVIF_LOGI("AvifDecoder created, libavif available: %d", IsLibavifAvailable());
}

AvifDecoder::~AvifDecoder() {
}

bool AvifDecoder::IsAvifFormat(const uint8_t* data, size_t size) {
    if (!data || size < 12) {
        return false;
    }
    
    // 检查ftyp box
    // 格式: [4字节size][4字节'ftyp'][4字节brand]
    if (data[4] != 'f' || data[5] != 't' || data[6] != 'y' || data[7] != 'p') {
        return false;
    }
    
    // 检查brand是否为avif/avis/heic/mif1
    const char* brand = reinterpret_cast<const char*>(data + 8);
    if (strncmp(brand, AVIF_BRAND, 4) == 0 ||
        strncmp(brand, AVIS_BRAND, 4) == 0 ||
        strncmp(brand, HEIC_BRAND, 4) == 0 ||
        strncmp(brand, MIFF_BRAND, 4) == 0) {
        return true;
    }
    
    return false;
}

bool AvifDecoder::IsLibavifAvailable() {
#ifdef HAVE_LIBAVIF
#if HAVE_LIBAVIF
    return true;
#else
    return false;
#endif
#else
    return false;
#endif
}

DecodedImage AvifDecoder::Decode(const uint8_t* data, size_t size) {
    if (!data || size == 0) {
        DecodedImage result;
        result.success = false;
        result.error = "Invalid input data";
        return result;
    }
    
    if (!IsAvifFormat(data, size)) {
        DecodedImage result;
        result.success = false;
        result.error = "Not a valid AVIF format";
        return result;
    }
    
    AVIF_LOGI("Decoding AVIF image, size: %zu bytes", size);
    
#ifdef HAVE_LIBAVIF
#if HAVE_LIBAVIF
    return DecodeWithLibavif(data, size);
#else
    return DecodeWithFallback(data, size);
#endif
#else
    return DecodeWithFallback(data, size);
#endif
}

bool AvifDecoder::GetImageInfo(const uint8_t* data, size_t size, uint32_t& width, uint32_t& height) {
    if (!data || size < 12 || !IsAvifFormat(data, size)) {
        return false;
    }
    
#ifdef HAVE_LIBAVIF
#if HAVE_LIBAVIF
    avifDecoder* decoder = avifDecoderCreate();
    if (!decoder) {
        return false;
    }
    
    avifResult result = avifDecoderSetIOMemory(decoder, data, size);
    if (result != AVIF_RESULT_OK) {
        avifDecoderDestroy(decoder);
        return false;
    }
    
    result = avifDecoderParse(decoder);
    if (result != AVIF_RESULT_OK) {
        avifDecoderDestroy(decoder);
        return false;
    }
    
    width = decoder->image->width;
    height = decoder->image->height;
    
    avifDecoderDestroy(decoder);
    return true;
#endif
#endif
    
    // 回退：无法获取信息
    width = 0;
    height = 0;
    return false;
}

#ifdef HAVE_LIBAVIF
#if HAVE_LIBAVIF
DecodedImage AvifDecoder::DecodeWithLibavif(const uint8_t* data, size_t size) {
    DecodedImage result;
    result.success = false;
    
    AVIF_LOGI("DecodeWithLibavif: creating decoder");
    avifDecoder* decoder = avifDecoderCreate();
    if (!decoder) {
        result.error = "Failed to create AVIF decoder";
        AVIF_LOGE("DecodeWithLibavif: failed to create decoder");
        return result;
    }
    
    // 设置解码选项 - 使用单线程避免多线程问题
    decoder->maxThreads = 1;
    decoder->codecChoice = AVIF_CODEC_CHOICE_AUTO;
    decoder->strictFlags = AVIF_STRICT_DISABLED;
    
    AVIF_LOGI("DecodeWithLibavif: setting IO memory");
    // 设置输入数据
    avifResult avifResult = avifDecoderSetIOMemory(decoder, data, size);
    if (avifResult != AVIF_RESULT_OK) {
        result.error = std::string("Failed to set IO memory: ") + avifResultToString(avifResult);
        AVIF_LOGE("DecodeWithLibavif: %s", result.error.c_str());
        avifDecoderDestroy(decoder);
        return result;
    }
    
    AVIF_LOGI("DecodeWithLibavif: parsing image");
    // 解析图片
    avifResult = avifDecoderParse(decoder);
    if (avifResult != AVIF_RESULT_OK) {
        result.error = std::string("Failed to parse AVIF: ") + avifResultToString(avifResult);
        AVIF_LOGE("DecodeWithLibavif: %s", result.error.c_str());
        avifDecoderDestroy(decoder);
        return result;
    }
    
    AVIF_LOGI("DecodeWithLibavif: decoding first frame (this may take a while)");
    // 解码第一帧
    avifResult = avifDecoderNextImage(decoder);
    if (avifResult != AVIF_RESULT_OK) {
        result.error = std::string("Failed to decode AVIF: ") + avifResultToString(avifResult);
        AVIF_LOGE("DecodeWithLibavif: %s", result.error.c_str());
        avifDecoderDestroy(decoder);
        return result;
    }
    
    avifImage* image = decoder->image;
    result.width = image->width;
    result.height = image->height;
    result.depth = image->depth;
    result.channels = 4;  // 输出RGBA
    
    AVIF_LOGI("DecodeWithLibavif: decoded %ux%u, depth=%u, allocating buffer", result.width, result.height, result.depth);
    
    // 分配RGBA缓冲区
    size_t pixelCount = result.width * result.height * 4;
    result.pixels.resize(pixelCount);
    
    // 创建RGB结构用于转换
    // HarmonyOS PixelMap使用BGRA格式，所以这里输出BGRA
    avifRGBImage rgb;
    avifRGBImageSetDefaults(&rgb, image);
    rgb.format = AVIF_RGB_FORMAT_BGRA;  // 改为BGRA以匹配HarmonyOS
    rgb.depth = 8;
    rgb.pixels = result.pixels.data();
    rgb.rowBytes = result.width * 4;
    
    AVIF_LOGI("DecodeWithLibavif: converting YUV to RGB");
    // YUV转RGB
    avifResult = avifImageYUVToRGB(image, &rgb);
    if (avifResult != AVIF_RESULT_OK) {
        result.error = std::string("Failed to convert YUV to RGB: ") + avifResultToString(avifResult);
        AVIF_LOGE("DecodeWithLibavif: %s", result.error.c_str());
        result.pixels.clear();
        avifDecoderDestroy(decoder);
        return result;
    }
    
    avifDecoderDestroy(decoder);
    result.success = true;
    
    AVIF_LOGI("DecodeWithLibavif: success, pixel data size: %zu", result.pixels.size());
    return result;
}
#endif
#endif

DecodedImage AvifDecoder::DecodeWithFallback(const uint8_t* data, size_t size) {
    DecodedImage result;
    result.success = false;
    result.error = "AVIF decoding requires libavif library. Please compile and install libavif for HarmonyOS.";
    
    AVIF_LOGE("Fallback decoder called - libavif not available");
    AVIF_LOGI("To enable AVIF support:");
    AVIF_LOGI("1. Clone tpc_c_cplusplus from gitee.com/openharmony-sig/tpc_c_cplusplus");
    AVIF_LOGI("2. Build libavif: cd lycium && ./build.sh libavif");
    AVIF_LOGI("3. Copy libs to entry/libs/${OHOS_ARCH}/");
    
    return result;
}

} // namespace avif
