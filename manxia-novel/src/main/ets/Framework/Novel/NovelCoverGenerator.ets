/**
 * 小说封面生成器
 * 为没有封面的网络小说生成本地封面图片
 * 
 * 文件路径: entry/src/main/ets/Framework/Novel/NovelCoverGenerator.ets
 */

import { image } from '@kit.ImageKit';
import { fileIo } from '@kit.CoreFileKit';
import { UIContext } from '@kit.ArkUI';
import { logger } from 'manxia_core/src/main/ets/Utils/Logger';

const TAG = 'NovelCoverGenerator';

/**
 * 封面生成配置
 */
interface CoverConfig {
  width: number;
  height: number;
  titleAreaTop: number;
  titleAreaBottom: number;
  titleAreaLeft: number;
  titleAreaRight: number;
}

/**
 * 小说封面生成器
 * 单例模式
 */
export class NovelCoverGenerator {
  private static instance: NovelCoverGenerator | null = null;
  private coverDir: string = '';
  private isInitialized: boolean = false;
  
  // 封面尺寸配置（基于 ebook.webp 图片）
  private static readonly CONFIG: CoverConfig = {
    width: 400,
    height: 600,
    titleAreaTop: 0.130,
    titleAreaBottom: 0.345,
    titleAreaLeft: 0.110,
    titleAreaRight: 0.895
  };

  private constructor() {}

  static getInstance(): NovelCoverGenerator {
    if (!NovelCoverGenerator.instance) {
      NovelCoverGenerator.instance = new NovelCoverGenerator();
    }
    return NovelCoverGenerator.instance;
  }

  /**
   * 初始化封面生成器
   * @param context 应用上下文
   */
  async initialize(filesDir: string): Promise<void> {
    if (this.isInitialized) {
      return;
    }
    
    try {
      // 设置封面存储目录
      this.coverDir = `${filesDir}/novel_covers`;
      
      // 确保目录存在
      try {
        await fileIo.mkdir(this.coverDir);
        logger.info(TAG, `封面目录已创建: ${this.coverDir}`);
      } catch (e) {
        // 目录可能已存在
      }
      
      this.isInitialized = true;
      logger.info(TAG, '封面生成器初始化完成');
    } catch (error) {
      logger.error(TAG, `初始化失败: ${String(error)}`);
      throw error as Error;
    }
  }

  /**
   * 获取封面存储目录
   */
  getCoverDir(): string {
    return this.coverDir;
  }

  /**
   * 生成封面图片
   * @param bookId 书籍ID
   * @param title 书籍标题
   * @param builderFunc 构建封面组件的函数
   * @returns 生成的封面路径，失败返回空字符串
   */
  async generateCover(bookId: string, title: string, builderFunc: () => void, uiContext: UIContext): Promise<string> {
    if (!this.isInitialized) {
      logger.error(TAG, '封面生成器未初始化');
      return '';
    }
    
    try {
      logger.info(TAG, `开始生成封面: ${title}`);
      
      // 使用 componentSnapshot.createFromBuilder 生成 PixelMap
      const pixelMap = await uiContext.getComponentSnapshot().createFromBuilder(builderFunc);
      
      if (!pixelMap) {
        logger.warn(TAG, '封面生成失败: PixelMap 为空');
        return '';
      }
      
      // 生成文件名（使用bookId的hash避免特殊字符）
      const safeFileName = this.generateSafeFileName(bookId);
      const outputPath = `${this.coverDir}/${safeFileName}.webp`;
      
      // 保存 PixelMap 为图片文件
      const saveSuccess = await this.savePixelMapToFile(pixelMap, outputPath);
      
      // 释放 PixelMap
      pixelMap.release();
      
      if (saveSuccess) {
        logger.info(TAG, `封面生成成功: ${outputPath}`);
        return outputPath;
      } else {
        logger.warn(TAG, '封面生成失败: 保存图片失败');
        return '';
      }
    } catch (error) {
      logger.error(TAG, `封面生成异常: ${String(error)}`);
      return '';
    }
  }

  /**
   * 生成安全的文件名
   */
  private generateSafeFileName(bookId: string): string {
    // 简单hash函数
    let hash = 0;
    for (let i = 0; i < bookId.length; i++) {
      const char = bookId.charCodeAt(i);
      hash = ((hash << 5) - hash) + char;
      hash = hash & hash;
    }
    return `novel_cover_${Math.abs(hash).toString(16)}`;
  }

  /**
   * 将 PixelMap 保存为图片文件
   */
  private async savePixelMapToFile(pixelMap: image.PixelMap, filePath: string): Promise<boolean> {
    try {
      // 确保目录存在
      const dirPath = filePath.substring(0, filePath.lastIndexOf('/'));
      try {
        await fileIo.mkdir(dirPath);
      } catch (e) {
        // 目录可能已存在
      }
      
      // 创建图片打包器
      const imagePacker = image.createImagePacker();
      
      // 打包为 WebP 格式
      const packOptions: image.PackingOption = {
        format: 'image/webp',
        quality: 90
      };
      
      const arrayBuffer = await imagePacker.packToData(pixelMap, packOptions);
      
      // 写入文件
      const file = await fileIo.open(filePath, fileIo.OpenMode.CREATE | fileIo.OpenMode.WRITE_ONLY | fileIo.OpenMode.TRUNC);
      await fileIo.write(file.fd, arrayBuffer);
      await fileIo.close(file.fd);
      
      // 释放打包器
      imagePacker.release();
      
      logger.info(TAG, `封面图片已保存: ${filePath}`);
      return true;
    } catch (error) {
      logger.error(TAG, `保存图片失败: ${error instanceof Error ? error.message : String(error)}`);
      return false;
    }
  }

  /**
   * 检查封面是否已存在
   */
  async coverExists(bookId: string): Promise<string | null> {
    if (!this.isInitialized) {
      return null;
    }
    
    const safeFileName = this.generateSafeFileName(bookId);
    const coverPath = `${this.coverDir}/${safeFileName}.webp`;
    
    try {
      await fileIo.access(coverPath);
      return coverPath;
    } catch (e) {
      return null;
    }
  }

  /**
   * 删除封面
   */
  async deleteCover(bookId: string): Promise<boolean> {
    if (!this.isInitialized) {
      return false;
    }
    
    const safeFileName = this.generateSafeFileName(bookId);
    const coverPath = `${this.coverDir}/${safeFileName}.webp`;
    
    try {
      await fileIo.unlink(coverPath);
      logger.info(TAG, `封面已删除: ${coverPath}`);
      return true;
    } catch (e) {
      return false;
    }
  }

  /**
   * 格式化封面标题（处理过长的标题）
   */
  static formatCoverTitle(title: string): string {
    // 移除文件扩展名
    let cleanTitle = title.replace(/\.(txt|epub|pdf|mobi|azw3?)$/i, '');
    // 如果标题过长，截断并添加省略号
    if (cleanTitle.length > 20) {
      cleanTitle = cleanTitle.substring(0, 17) + '...';
    }
    return cleanTitle;
  }

  /**
   * 根据标题长度计算合适的字体大小
   */
  static calculateCoverFontSize(title: string): number {
    const length = title.length;
    if (length <= 2) {
      return 70;
    } else if (length <= 4) {
      return 56;
    } else if (length <= 6) {
      return 48;
    } else if (length <= 8) {
      return 36;
    } else if (length <= 12) {
      return 32;
    } else if (length <= 16) {
      return 28;
    } else {
      return 24;
    }
  }

  /**
   * 获取封面配置
   */
  static getConfig(): CoverConfig {
    return NovelCoverGenerator.CONFIG;
  }
}

/**
 * 获取封面生成器实例
 */
export function getNovelCoverGenerator(): NovelCoverGenerator {
  return NovelCoverGenerator.getInstance();
}
