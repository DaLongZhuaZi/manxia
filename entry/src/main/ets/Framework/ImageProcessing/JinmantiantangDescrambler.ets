/**
 * 禁漫天堂图片解扰算法实现
 * 基于MD5哈希的图片分割还原算法
 */

import { image } from '@kit.ImageKit';
import { cryptoFramework } from '@kit.CryptoArchitectureKit';
import { logger } from '../../Utils/Logger';
import { DescramblerAlgorithm } from './ImageDescramblerRegistry';

const TAG = 'JinmantiantangDescrambler';

/**
 * 禁漫天堂解扰算法参数
 */
export interface JinmantiantangParameters {
  /** 章节ID */
  aid: number;
  /** 图片索引 */
  imgIndex: string;
  /** 解扰ID阈值（默认220980） */
  scrambleIdThreshold?: number;
  /** 模数规则 */
  modulusRules?: Array<{ minAid: number; modulus: number }>;
  /** 输出质量（1-100，默认90） */
  outputQuality?: number;
}

/**
 * 禁漫天堂图片解扰器
 */
export class JinmantiantangDescrambler implements DescramblerAlgorithm {
  readonly name = 'jinmantiantang';
  readonly version = '1.0.0';
  readonly description = '禁漫天堂图片解扰算法 - 基于MD5哈希的图片分割还原';

  private readonly DEFAULT_SCRAMBLE_ID = 220980;
  private readonly DEFAULT_MODULUS_RULES = [
    { minAid: 421926, modulus: 8 },
    { minAid: 268850, modulus: 10 },
    { minAid: 0, modulus: 10 }
  ];
  private readonly DEFAULT_QUALITY = 90;

  /**
   * 计算MD5哈希的最后一个字符的字符码
   */
  private async md5LastCharCode(input: string): Promise<number> {
    try {
      const md = cryptoFramework.createMd('MD5');
      const inputData = new Uint8Array(Buffer.from(input, 'utf-8'));
      await md.update({ data: inputData });
      const result = await md.digest();

      // 获取最后一个字节
      const lastByte = result.data[result.data.length - 1];
      // 转换为16进制字符串并取最后一个字符
      const hexStr = lastByte.toString(16).padStart(2, '0');
      const lastChar = hexStr.charAt(hexStr.length - 1);

      return lastChar.charCodeAt(0);
    } catch (error) {
      logger.error(TAG, `MD5计算失败: ${error}`);
      throw error;
    }
  }

  /**
   * 根据章节ID和图片索引计算分割行数
   */
  private async getRows(aid: number, imgIndex: string, modulusRules?: Array<{ minAid: number; modulus: number }>): Promise<number> {
    const rules = modulusRules || this.DEFAULT_MODULUS_RULES;

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
  shouldDescramble(url: string, parameters: ESObject): boolean {
    const params = parameters as JinmantiantangParameters;
    const threshold = params.scrambleIdThreshold || this.DEFAULT_SCRAMBLE_ID;
    return url.includes('media/photos') && params.aid >= threshold;
  }

  /**
   * 解扰图片
   */
  async descramble(imageData: ArrayBuffer, parameters: ESObject): Promise<ArrayBuffer> {
    const params = parameters as JinmantiantangParameters;
    const startTime = Date.now();

    try {
      logger.info(TAG, `开始解扰图片: aid=${params.aid}, imgIndex=${params.imgIndex}`);

      // 1. 创建ImageSource
      const imageSource = image.createImageSource(imageData);
      const imageInfo = await imageSource.getImageInfo();

      const width = imageInfo.size.width;
      const height = imageInfo.size.height;
      logger.debug(TAG, `图片尺寸: ${width}x${height}`);

      // 2. 计算分割参数
      const rows = await this.getRows(params.aid, params.imgIndex, params.modulusRules);
      const remainder = height % rows;

      // 3. 创建源PixelMap
      const sourcePixelMap = await imageSource.createPixelMap();

      // 4. 创建目标PixelMap
      const resultPixelMap = await image.createPixelMap({
        size: { width, height },
        pixelFormat: image.PixelMapFormat.RGBA_8888,
        editable: true
      });

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

        // 读取源区域
        const sourceRegion = {
          x: 0,
          y: y,
          size: { width: width, height: copyH }
        };

        const pixels = new ArrayBuffer(width * copyH * 4);
        await sourcePixelMap.readPixelsToBuffer(pixels);

        // 写入目标区域
        const targetRegion = {
          x: 0,
          y: py,
          size: { width: width, height: copyH }
        };

        await resultPixelMap.writeBufferToPixels(pixels);
      }

      // 6. 编码为JPEG
      const packer = image.createImagePacker();
      const quality = params.outputQuality || this.DEFAULT_QUALITY;
      const packOpts: image.PackingOption = {
        format: 'image/jpeg',
        quality: quality
      };

      const resultData = await packer.packing(resultPixelMap, packOpts);

      // 7. 清理资源
      await sourcePixelMap.release();
      await resultPixelMap.release();

      const elapsed = Date.now() - startTime;
      logger.info(TAG, `图片解扰完成，耗时: ${elapsed}ms`);

      return resultData;
    } catch (error) {
      logger.error(TAG, `图片解扰失败: ${error}`);
      throw error;
    }
  }

  /**
   * 从URL提取章节ID和图片索引
   */
  static extractImageInfo(url: string): { aid: number; imgIndex: string } | null {
    try {
      // URL格式: https://cdn.xxx.com/media/photos/123456/00001.jpg
      const match = url.match(/\/photos\/(\d+)\/(\d+)\./);
      if (match) {
        return {
          aid: parseInt(match[1]),
          imgIndex: match[2]
        };
      }
      return null;
    } catch (error) {
      logger.error(TAG, `提取图片信息失败: ${error}`);
      return null;
    }
  }
}
