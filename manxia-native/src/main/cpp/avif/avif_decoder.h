/**
 * AVIF图片解码器头文件
 * 提供AVIF格式图片的解码功能
 */

#ifndef AVIF_DECODER_H
#define AVIF_DECODER_H

#include <cstdint>
#include <cstddef>
#include <memory>
#include <vector>
#include <string>

namespace avif {

/**
 * 解码后的图片数据结构
 */
struct DecodedImage {
    uint32_t width;           // 图片宽度
    uint32_t height;          // 图片高度
    uint32_t depth;           // 位深度（通常为8）
    uint32_t channels;        // 通道数（3=RGB, 4=RGBA）
    std::vector<uint8_t> pixels;  // RGBA像素数据
    bool success;             // 解码是否成功
    std::string error;        // 错误信息
};

/**
 * AVIF解码器类
 */
class AvifDecoder {
public:
    AvifDecoder();
    ~AvifDecoder();

    /**
     * 检查数据是否为AVIF格式
     * @param data 图片数据
     * @param size 数据大小
     * @return 是否为AVIF格式
     */
    static bool IsAvifFormat(const uint8_t* data, size_t size);

    /**
     * 解码AVIF图片
     * @param data AVIF图片数据
     * @param size 数据大小
     * @return 解码后的图片数据
     */
    DecodedImage Decode(const uint8_t* data, size_t size);

    /**
     * 获取AVIF图片信息（不完全解码）
     * @param data AVIF图片数据
     * @param size 数据大小
     * @param width 输出宽度
     * @param height 输出高度
     * @return 是否成功获取信息
     */
    bool GetImageInfo(const uint8_t* data, size_t size, uint32_t& width, uint32_t& height);

    /**
     * 检查libavif是否可用
     */
    static bool IsLibavifAvailable();

private:
    // 使用libavif解码
    DecodedImage DecodeWithLibavif(const uint8_t* data, size_t size);
    
    // 回退解码器（简单实现，功能有限）
    DecodedImage DecodeWithFallback(const uint8_t* data, size_t size);
};

} // namespace avif

#endif // AVIF_DECODER_H
