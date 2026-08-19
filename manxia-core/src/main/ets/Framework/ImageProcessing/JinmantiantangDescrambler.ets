/**
 * 禁漫天堂图片解扰算法实现
 * 基于MD5哈希的图片分割还原算法
 */

import { image } from '@kit.ImageKit';
import { cryptoFramework } from '@kit.CryptoArchitectureKit';
import { logger } from '../../Utils/Logger';
import { util } from '@kit.ArkTS';

const TAG = 'JinmantiantangDescrambler';

/**
 * 模数规则接口
 */
interface ModulusRule {
  minAid: number;
  modulus: number;
}

/**
 * 禁漫天堂解扰算法参数
 */
export interface JinmantiantangParameters {
  aid: number;
  imgIndex: string;
  scrambleIdThreshold?: number;
  outputQuality?: number;
}

/**
 * 图片信息接口
 */
export interface ImageInfo {
  aid: number;
  imgIndex: string;
}

/**
 * 禁漫天堂图片解扰器
 */
export class JinmantiantangDescrambler {
  readonly name: string = 'jinmantiantang';
  readonly version: string = '1.0.0';
  readonly description: string = '禁漫天堂图片解扰算法 - 基于MD5哈希的图片分割还原';

  private readonly DEFAULT_SCRAMBLE_ID: number = 220980;
  private readonly DEFAULT_QUALITY: number = 90;

  // 模数规则
  private getModulusRules(): ModulusRule[] {
    const rule1: ModulusRule = { minAid: 421926, modulus: 8 };
    const rule2: ModulusRule = { minAid: 268850, modulus: 10 };
    const rule3: ModulusRule = { minAid: 0, modulus: 10 };
    return [rule1, rule2, rule3];
  }

  /**
   * 字符串转Uint8Array
   */
  private stringToUint8Array(str: string): Uint8Array {
    const encoder = new util.TextEncoder();
    return encoder.encodeInto(str);
  }

  /**
   * 计算MD5哈希的最后一个字符的字符码
   */
  private async md5LastCharCode(input: string): Promise<number> {
    try {
      const md = cryptoFramework.createMd('MD5');
      const inputData: cryptoFramework.DataBlob = { data: this.stringToUint8Array(input) };
      await md.update(inputData);
      const result = await md.digest();

      // 获取最后一个字节
      const lastByte = result.data[result.data.length - 1];
      // 转换为16进制字符串并取最后一个字符
      const hexStr = lastByte.toString(16).padStart(2, '0');
      const lastChar = hexStr.charAt(hexStr.length - 1);

      return lastChar.charCodeAt(0);
    } catch (error) {
      const errMsg = error instanceof Error ? error.message : String(error);
      logger.error(TAG, `MD5计算失败: ${errMsg}`);
      throw new Error(`MD5计算失败: ${errMsg}`);
    }
  }

  /**
   * 根据章节ID和图片索引计算分割行数
   */
  private async getRows(aid: number, imgIndex: string): Promise<number> {
    const rules = this.getModulusRules();

    // 根据章节ID确定模数
    let modulus = 10;
    for (const rule of rules) {
      if (aid >= rule.minAid) {
        modulus = rule.modulus;
        break;
      }
    }

    // 计算分割行数
    const hashCode = await this.md5LastCharCode(aid.toString() + imgIndex);
    const rows = 2 * (hashCode % modulus) + 2;

    logger.debug(TAG, `章节ID=${aid}, 图片索引=${imgIndex}, 模数=${modulus}, 行数=${rows}`);
    return rows;
  }

  /**
   * 检查是否需要解扰
   */
  shouldDescramble(url: string, parameters: JinmantiantangParameters): boolean {
    const threshold = parameters.scrambleIdThreshold !== undefined ? parameters.scrambleIdThreshold : this.DEFAULT_SCRAMBLE_ID;
    return url.includes('media/photos') && parameters.aid >= threshold;
  }

  /**
   * 解扰图片
   */
  async descramble(imageData: ArrayBuffer, parameters: JinmantiantangParameters): Promise<ArrayBuffer> {
    const startTime = Date.now();

    try {
      logger.info(TAG, `开始解扰图片: aid=${parameters.aid}, imgIndex=${parameters.imgIndex}`);

      // 1. 创建ImageSource和PixelMap
      const imageSource = image.createImageSource(imageData);
      const imageInfo = await imageSource.getImageInfo();
      const width = imageInfo.size.width;
      const height = imageInfo.size.height;
      logger.debug(TAG, `图片尺寸: ${width}x${height}`);

      // 2. 计算分割参数
      const rows = await this.getRows(parameters.aid, parameters.imgIndex);
      const remainder = height % rows;

      // 3. 创建源PixelMap并读取所有像素
      // [修复] 指定解码选项，确保像素格式一致
      const decodingOptions: image.DecodingOptions = {
        desiredPixelFormat: image.PixelMapFormat.BGRA_8888  // 使用BGRA格式避免反色
      };
      const sourcePixelMap = await imageSource.createPixelMap(decodingOptions);
      const sourceBuffer = new ArrayBuffer(width * height * 4);
      await sourcePixelMap.readPixelsToBuffer(sourceBuffer);
      const sourcePixels = new Uint8Array(sourceBuffer);

      // 4. 创建目标像素数组
      const resultBuffer = new ArrayBuffer(width * height * 4);
      const resultPixels = new Uint8Array(resultBuffer);

      // 5. 逆序拼接图片
      for (let x = 0; x < rows; x++) {
        let copyH = Math.floor(height / rows);
        let py = copyH * x;
        const y = height - (copyH * (x + 1)) - remainder;

        if (x === 0) {
          copyH += remainder;
        } else {
          py += remainder;
        }

        // 复制像素行
        for (let row = 0; row < copyH; row++) {
          const srcOffset = ((y + row) * width) * 4;
          const dstOffset = ((py + row) * width) * 4;
          const rowBytes = width * 4;
          
          for (let i = 0; i < rowBytes; i++) {
            resultPixels[dstOffset + i] = sourcePixels[srcOffset + i];
          }
        }
      }

      // 6. 创建结果PixelMap
      // [修复] 使用与源图片相同的BGRA格式
      const initOptions: image.InitializationOptions = {
        size: { width: width, height: height },
        pixelFormat: image.PixelMapFormat.BGRA_8888,
        editable: true
      };
      const resultPixelMap = await image.createPixelMap(resultBuffer, initOptions);

      // 7. 编码为JPEG
      const packer = image.createImagePacker();
      const quality = parameters.outputQuality !== undefined ? parameters.outputQuality : this.DEFAULT_QUALITY;
      const packOpts: image.PackingOption = {
        format: 'image/jpeg',
        quality: quality
      };
      const resultData = await packer.packToData(resultPixelMap, packOpts);

      // 8. 清理资源
      await sourcePixelMap.release();
      await resultPixelMap.release();

      const elapsed = Date.now() - startTime;
      logger.info(TAG, `图片解扰完成，耗时: ${elapsed}ms`);

      return resultData;
    } catch (error) {
      const errMsg = error instanceof Error ? error.message : String(error);
      logger.error(TAG, `图片解扰失败: ${errMsg}`);
      throw new Error(`图片解扰失败: ${errMsg}`);
    }
  }

  /**
   * 从URL提取章节ID和图片索引
   */
  static extractImageInfo(url: string): ImageInfo | null {
    try {
      // URL格式: https://cdn.xxx.com/media/photos/123456/00001.jpg
      const match = url.match(/\/photos\/(\d+)\/(\d+)\./);
      if (match !== null && match.length >= 3) {
        const result: ImageInfo = {
          aid: parseInt(match[1]),
          imgIndex: match[2]
        };
        return result;
      }
      return null;
    } catch (error) {
      const errMsg = error instanceof Error ? error.message : String(error);
      logger.error(TAG, `提取图片信息失败: ${errMsg}`);
      return null;
    }
  }
}
