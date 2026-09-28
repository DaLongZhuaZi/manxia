/**
 * AVIF图片解码器
 * 通过Native C++层实现AVIF格式图片的解码
 */

import { image } from '@kit.ImageKit';
import { logger } from 'manxia_core/src/main/ets/Utils/Logger';
import avifDecoderNativeImport from 'libavif_decoder.so';

const TAG = 'AvifDecoder';

/**
 * AVIF解码结果
 */
interface AvifDecodeResult {
  width: number;
  height: number;
  pixels: Uint8Array;
}

/**
 * AVIF图片信息
 */
interface AvifImageInfo {
  width: number;
  height: number;
}

/**
 * Native AVIF解码器接口
 */
interface NativeAvifDecoder {
  isAvifFormat(data: ArrayBuffer): boolean;
  isLibavifAvailable(): boolean;
  decodeAvifToRgba(data: ArrayBuffer): AvifDecodeResult | null;
  decodeAvifAsync(data: ArrayBuffer): Promise<AvifDecodeResult | null>;
  getAvifInfo(data: ArrayBuffer): AvifImageInfo | null;
}

// Native模块引用（延迟加载）
let nativeDecoder: NativeAvifDecoder | null = null;
let nativeLoadAttempted: boolean = false;
let nativeLoadError: string = '';

/**
 * 检查并加载Native AVIF解码器
 */
function checkNativeModule(): void {
  if (nativeLoadAttempted) return;
  nativeLoadAttempted = true;
  
  try {
    // 打印模块信息用于调试
    logger.info(TAG, `Native模块类型: ${typeof avifDecoderNativeImport}`);
    if (avifDecoderNativeImport) {
      const moduleObj = avifDecoderNativeImport as NativeAvifDecoder;
      const keys = Object.keys(avifDecoderNativeImport);
      logger.info(TAG, `Native模块导出的属性: ${keys.join(', ')}`);
      logger.info(TAG, `isLibavifAvailable类型: ${typeof moduleObj.isLibavifAvailable}`);
    }
    
    if (avifDecoderNativeImport && typeof (avifDecoderNativeImport as NativeAvifDecoder).isLibavifAvailable === 'function') {
      nativeDecoder = avifDecoderNativeImport as NativeAvifDecoder;
      logger.info(TAG, 'Native AVIF解码器加载成功');
      
      // 检查异步解码是否可用
      const hasAsyncDecode = typeof nativeDecoder.decodeAvifAsync === 'function';
      logger.info(TAG, `异步解码支持: ${hasAsyncDecode ? '可用' : '不可用'}`);
      
      if (nativeDecoder.isLibavifAvailable()) {
        logger.info(TAG, 'libavif可用 - AVIF完整支持已启用');
      } else {
        logger.warn(TAG, 'libavif不可用 - AVIF支持受限（编译时未链接libavif）');
      }
    } else {
      const moduleObj = avifDecoderNativeImport as NativeAvifDecoder;
      nativeLoadError = `Native模块加载成功但接口不完整, isLibavifAvailable类型=${typeof moduleObj?.isLibavifAvailable}`;
      logger.warn(TAG, nativeLoadError);
    }
  } catch (error) {
    nativeLoadError = `Native模块检查失败: ${String(error)}`;
    logger.warn(TAG, nativeLoadError);
  }
}

/**
 * 加载Native AVIF解码器
 */
function loadNativeDecoder(): NativeAvifDecoder | null {
  checkNativeModule();
  return nativeDecoder;
}

/**
 * AVIF解码器类
 */
export class AvifDecoder {
  private static instance: AvifDecoder | null = null;
  
  private constructor() {
    // 初始化时尝试加载Native模块
    loadNativeDecoder();
  }
  
  /**
   * 获取单例实例
   */
  static getInstance(): AvifDecoder {
    if (!AvifDecoder.instance) {
      AvifDecoder.instance = new AvifDecoder();
    }
    return AvifDecoder.instance;
  }
  
  /**
   * 检查是否支持AVIF解码
   */
  isSupported(): boolean {
    const decoder = loadNativeDecoder();
    return decoder !== null && decoder.isLibavifAvailable();
  }
  
  /**
   * 检查数据是否为AVIF格式
   * @param data 图片数据
   */
  isAvifFormat(data: ArrayBuffer | Uint8Array): boolean {
    // 首先进行简单的签名检查
    const bytes = data instanceof Uint8Array ? data : new Uint8Array(data);
    if (bytes.length < 12) {
      return false;
    }
    
    // 检查ftyp box
    if (bytes[4] !== 0x66 || bytes[5] !== 0x74 || bytes[6] !== 0x79 || bytes[7] !== 0x70) {
      return false;
    }
    
    // 检查brand
    const brand = String.fromCharCode(bytes[8], bytes[9], bytes[10], bytes[11]);
    if (brand === 'avif' || brand === 'avis' || brand === 'heic' || brand === 'mif1') {
      return true;
    }
    
    // 使用Native检查（如果可用）
    const decoder = loadNativeDecoder();
    if (decoder) {
      try {
        const buffer = data instanceof ArrayBuffer ? data : (data.buffer.slice(data.byteOffset, data.byteOffset + data.byteLength) as ArrayBuffer);
        return decoder.isAvifFormat(buffer);
      } catch (error) {
        logger.warn(TAG, `Native isAvifFormat failed: ${error}`);
      }
    }
    
    return false;
  }
  
  /**
   * 解码AVIF图片为PixelMap（异步，不阻塞主线程）
   * @param data AVIF图片数据
   * @returns PixelMap或null
   */
  async decode(data: ArrayBuffer | Uint8Array): Promise<image.PixelMap | null> {
    const decoder = loadNativeDecoder();
    if (!decoder) {
      logger.error(TAG, 'Native AVIF解码器不可用');
      return null;
    }
    
    if (!decoder.isLibavifAvailable()) {
      logger.error(TAG, 'libavif不可用 - 无法解码AVIF');
      return null;
    }
    
    try {
      const buffer = data instanceof ArrayBuffer ? data : (data.buffer.slice(data.byteOffset, data.byteOffset + data.byteLength) as ArrayBuffer);
      
      logger.info(TAG, `异步解码AVIF图片，大小: ${buffer.byteLength} 字节`);
      
      // 使用异步解码API（在后台线程执行，不阻塞主线程）
      let result: AvifDecodeResult | null = null;
      
      if (typeof decoder.decodeAvifAsync === 'function') {
        // 优先使用异步解码
        result = await decoder.decodeAvifAsync(buffer);
      } else {
        // 降级到同步解码（可能导致ANR）
        logger.warn(TAG, '异步解码不可用，使用同步解码（可能导致卡顿）');
        result = decoder.decodeAvifToRgba(buffer);
      }
      
      if (!result) {
        logger.error(TAG, 'Native AVIF解码返回null');
        return null;
      }
      
      logger.info(TAG, `AVIF解码完成: ${result.width}x${result.height}, 像素数据: ${result.pixels.length} 字节`);
      
      // 创建PixelMap
      const pixelMap = await this.createPixelMapFromRgba(result.pixels, result.width, result.height);
      return pixelMap;
    } catch (error) {
      logger.error(TAG, `AVIF解码失败: ${error}`);
      return null;
    }
  }
  
  /**
   * 获取AVIF图片信息（不完全解码）
   * @param data AVIF图片数据
   */
  getImageInfo(data: ArrayBuffer | Uint8Array): AvifImageInfo | null {
    const decoder = loadNativeDecoder();
    if (!decoder) {
      return null;
    }
    
    try {
      const buffer = data instanceof ArrayBuffer ? data : (data.buffer.slice(data.byteOffset, data.byteOffset + data.byteLength) as ArrayBuffer);
      return decoder.getAvifInfo(buffer);
    } catch (error) {
      logger.warn(TAG, `获取图片信息失败: ${error}`);
      return null;
    }
  }
  
  /**
   * 从RGBA像素数据创建PixelMap
   */
  private async createPixelMapFromRgba(pixels: Uint8Array, width: number, height: number): Promise<image.PixelMap | null> {
    try {
      // 创建ImageSource的初始化选项
      const initOptions: image.InitializationOptions = {
        size: { width, height },
        pixelFormat: image.PixelMapFormat.RGBA_8888,
        alphaType: image.AlphaType.PREMUL,
        editable: false
      };
      
      // 直接从像素数据创建PixelMap
      const pixelMap = await image.createPixelMap(pixels.buffer as ArrayBuffer, initOptions);
      
      logger.info(TAG, `PixelMap创建成功: ${width}x${height}`);
      return pixelMap;
    } catch (error) {
      logger.error(TAG, `从RGBA创建PixelMap失败: ${error}`);
      return null;
    }
  }
}

/**
 * 检查是否支持AVIF格式
 */
export function isAvifSupported(): boolean {
  return AvifDecoder.getInstance().isSupported();
}

/**
 * 检查数据是否为AVIF格式
 */
export function isAvifFormat(data: ArrayBuffer | Uint8Array): boolean {
  return AvifDecoder.getInstance().isAvifFormat(data);
}

/**
 * 解码AVIF图片
 */
export async function decodeAvif(data: ArrayBuffer | Uint8Array): Promise<image.PixelMap | null> {
  return AvifDecoder.getInstance().decode(data);
}
