import { SafeUtils } from 'manxia_core/src/main/ets/Utils/SafeUtils';
// 文件路径: src/main/ets/Framework/Cache/DiskCacheManager.ets
/**
 * 磁盘缓存管理器
 * 实现LRU缓存策略，用于在线漫画图片的持久化缓存
 * 特性：
 * 1. LRU淘汰策略（最近最少使用）
 * 2. 自动清理过期缓存
 * 3. 缓存大小限制
 * 4. 缓存索引管理
 * 5. 全异步文件IO，不阻塞主线程
 */

import { image } from '@kit.ImageKit';
import { logger } from 'manxia_core/src/main/ets/Utils/Logger';
import fs from '@ohos.file.fs';
import { cryptoFramework } from '@kit.CryptoArchitectureKit';
import { util } from '@kit.ArkTS';

const TAG = 'DiskCacheManager';

interface DiskCacheStats {
  count: number;
  totalSize: number;
  maxSize: number;
  usagePercent: number;
}

interface CacheEntry {
  key: string;
  filePath: string;
  size: number;
  createTime: number;
  lastAccessTime: number;
  accessCount: number;
}

interface CacheIndex {
  version: number;
  entries: Map<string, CacheEntry>;
  totalSize: number;
}

export class DiskCacheManager {
  private static instance: DiskCacheManager | null = null;

  // 缓存配置
  private readonly MAX_CACHE_SIZE = 500 * 1024 * 1024;  // 500MB
  private readonly MAX_CACHE_AGE = 7 * 24 * 60 * 60 * 1000;  // 7天
  private readonly INDEX_VERSION = 1;

  // 缓存目录
  private cacheDir: string = '';
  private indexFilePath: string = '';

  // 缓存索引
  private cacheIndex: Map<string, CacheEntry> = new Map();
  private totalSize: number = 0;

  // 初始化状态
  private initialized: boolean = false;
  private initPromise: Promise<void> | null = null;

  private constructor() {
    logger.info(TAG, '磁盘缓存管理器初始化');
  }

  /**
   * 获取单例实例
   */
  public static getInstance(): DiskCacheManager {
    if (!DiskCacheManager.instance) {
      DiskCacheManager.instance = new DiskCacheManager();
    }
    return DiskCacheManager.instance;
  }

  /**
   * 初始化缓存目录和索引
   */
  public async initialize(baseDir: string): Promise<void> {
    if (this.initialized) {
      return;
    }

    if (this.initPromise) {
      return this.initPromise;
    }

    this.initPromise = this.doInitialize(baseDir);
    await this.initPromise;
  }

  private async doInitialize(baseDir: string): Promise<void> {
    try {
      logger.info(TAG, `开始初始化磁盘缓存管理器，baseDir: ${baseDir}`);

      // 验证baseDir参数
      if (!baseDir || baseDir.trim() === '') {
        throw new Error('baseDir参数为空或无效');
      }

      // 检查baseDir是否存在
      const baseDirExists = await fs.access(baseDir);
      if (!baseDirExists) {
        logger.warn(TAG, `baseDir不存在，尝试创建: ${baseDir}`);
        try {
          await fs.mkdir(baseDir);
          logger.info(TAG, `✅ 成功创建baseDir: ${baseDir}`);
        } catch (mkdirError) {
          throw new Error(`无法创建baseDir: ${baseDir}, 错误: ${String(mkdirError)}`);
        }
      }

      this.cacheDir = `${baseDir}/image_cache`;
      this.indexFilePath = `${this.cacheDir}/cache_index.json`;

      logger.debug(TAG, `缓存目录: ${this.cacheDir}`);
      logger.debug(TAG, `索引文件: ${this.indexFilePath}`);

      // 创建缓存目录
      const cacheDirExists = await fs.access(this.cacheDir);
      if (!cacheDirExists) {
        await fs.mkdir(this.cacheDir);
        logger.info(TAG, `✅ 创建缓存目录: ${this.cacheDir}`);
      } else {
        logger.debug(TAG, `缓存目录已存在: ${this.cacheDir}`);
      }

      // 加载缓存索引
      logger.debug(TAG, '开始加载缓存索引...');
      await this.loadIndex();
      logger.debug(TAG, `✅ 缓存索引加载完成: ${this.cacheIndex.size}条记录`);

      // 清理过期缓存
      logger.debug(TAG, '开始清理过期缓存...');
      await this.cleanExpiredCache();
      logger.debug(TAG, '✅ 过期缓存清理完成');

      this.initialized = true;
      logger.info(TAG, `✅ 磁盘缓存初始化完成: 缓存数=${this.cacheIndex.size}, 总大小=${(this.totalSize / 1024 / 1024).toFixed(2)}MB`);

    } catch (error) {
      const err = error as Error;
      logger.error(TAG, `❌ 初始化失败: ${err.message}, stack: ${err.stack}`);
      this.initialized = false;
      throw error as Error;
    }
  }

  /**
   * 加载缓存索引
   */
  private async loadIndex(): Promise<void> {
    try {
      const indexExists = await fs.access(this.indexFilePath);
      if (indexExists) {
        const file = await fs.open(this.indexFilePath, fs.OpenMode.READ_ONLY);
        const stat = await fs.stat(this.indexFilePath);
        const buffer = new ArrayBuffer(stat.size);
        await fs.read(file.fd, buffer);
        await fs.close(file);

        const uint8Array = new Uint8Array(buffer);
        const decoder = new util.TextDecoder('utf-8');
        const content = decoder.decodeToString(uint8Array);

        interface IndexData {
          version: number;
          entries: Array<[string, CacheEntry]>;
          totalSize: number;
        }
        const indexData = SafeUtils.parseObj(content) as IndexData;

        if (indexData.version === this.INDEX_VERSION) {
          this.cacheIndex = new Map(indexData.entries);
          this.totalSize = indexData.totalSize;
          logger.info(TAG, `加载缓存索引: ${this.cacheIndex.size}条记录`);
        } else {
          logger.warn(TAG, `缓存索引版本不匹配，重建索引`);
          await this.rebuildIndex();
        }
      } else {
        logger.info(TAG, `缓存索引不存在，创建新索引`);
        await this.saveIndex();
      }
    } catch (error) {
      logger.error(TAG, `加载缓存索引失败: ${String(error)}`);
      await this.rebuildIndex();
    }
  }

  /**
   * 保存缓存索引
   */
  private async saveIndex(): Promise<void> {
    try {
      interface IndexData {
        version: number;
        entries: Array<[string, CacheEntry]>;
        totalSize: number;
      }
      const indexData: IndexData = {
        version: this.INDEX_VERSION,
        entries: Array.from(this.cacheIndex.entries()),
        totalSize: this.totalSize
      };

      const content = JSON.stringify(indexData);
      const encoder = new util.TextEncoder();
      const buffer = encoder.encodeInto(content);

      const file = await fs.open(this.indexFilePath, fs.OpenMode.CREATE | fs.OpenMode.TRUNC | fs.OpenMode.WRITE_ONLY);
      await fs.write(file.fd, buffer.buffer);
      await fs.close(file);

      logger.debug(TAG, `保存缓存索引: ${this.cacheIndex.size}条记录`);
    } catch (error) {
      logger.error(TAG, `保存缓存索引失败: ${String(error)}`);
    }
  }

  /**
   * 重建缓存索引
   */
  private async rebuildIndex(): Promise<void> {
    try {
      this.cacheIndex.clear();
      this.totalSize = 0;

      const cacheDirExists = await fs.access(this.cacheDir);
      if (!cacheDirExists) {
        return;
      }

      const files = await fs.listFile(this.cacheDir);
      for (const fileName of files) {
        if (fileName === 'cache_index.json') {
          continue;
        }

        const filePath = `${this.cacheDir}/${fileName}`;
        try {
          const stat = await fs.stat(filePath);
          const entry: CacheEntry = {
            key: fileName,
            filePath: filePath,
            size: stat.size,
            createTime: stat.ctime,
            lastAccessTime: stat.atime,
            accessCount: 0
          };

          this.cacheIndex.set(fileName, entry);
          this.totalSize += stat.size;
        } catch (e) {
          logger.warn(TAG, `跳过无效文件: ${fileName}`);
        }
      }

      await this.saveIndex();
      logger.info(TAG, `重建缓存索引完成: ${this.cacheIndex.size}条记录`);
    } catch (error) {
      logger.error(TAG, `重建缓存索引失败: ${String(error)}`);
    }
  }

  /**
   * 生成缓存键（URL的MD5哈希）
   */
  private async generateCacheKey(url: string): Promise<string> {
    try {
      const md5 = cryptoFramework.createMd('MD5');
      const encoder = new util.TextEncoder();
      const urlBytes = encoder.encodeInto(url);
      await md5.update({ data: new Uint8Array(urlBytes) });
      const hashResult = await md5.digest();
      const hashArray = new Uint8Array(hashResult.data);
      return Array.from(hashArray).map(b => b.toString(16).padStart(2, '0')).join('');
    } catch (error) {
      logger.error(TAG, `生成缓存键失败: ${String(error)}`);
      return url.replace(/[^a-zA-Z0-9]/g, '_').substring(0, 64);
    }
  }

  /**
   * 检查是否已初始化
   */
  public isInitialized(): boolean {
    return this.initialized;
  }

  /**
   * 从缓存获取图片
   */
  public async get(url: string): Promise<image.PixelMap | null> {
    if (!this.initialized) {
      // 改为debug级别，避免日志泛滥
      logger.debug(TAG, '缓存未初始化，跳过磁盘缓存读取');
      return null;
    }

    try {
      const cacheKey = await this.generateCacheKey(url);
      const entry = this.cacheIndex.get(cacheKey);

      if (!entry) {
        return null;
      }

      // 检查文件是否存在
      const fileExists = await fs.access(entry.filePath);
      if (!fileExists) {
        logger.warn(TAG, `缓存文件不存在: ${entry.filePath}`);
        this.cacheIndex.delete(cacheKey);
        await this.saveIndex();
        return null;
      }

      // 检查是否过期
      const now = Date.now();
      if (now - entry.createTime > this.MAX_CACHE_AGE) {
        logger.debug(TAG, `缓存已过期: ${url.substring(0, 80)}`);
        await this.remove(cacheKey);
        return null;
      }

      // 读取图片
      const imageSource = image.createImageSource(entry.filePath);
      const pixelMap = await imageSource.createPixelMap();

      // 更新访问时间
      entry.lastAccessTime = now;
      entry.accessCount++;
      await this.saveIndex();

      logger.debug(TAG, `从磁盘缓存读取: ${url.substring(0, 80)}`);
      return pixelMap;

    } catch (error) {
      logger.error(TAG, `从缓存读取失败: ${String(error)}`);
      return null;
    }
  }

  /**
   * 保存图片到缓存
   */
  public async put(url: string, pixelMap: image.PixelMap): Promise<void> {
    if (!this.initialized) {
      // 改为debug级别，避免日志泛滥
      logger.debug(TAG, '缓存未初始化，跳过磁盘缓存写入');
      return;
    }

    try {
      const cacheKey = await this.generateCacheKey(url);
      const filePath = `${this.cacheDir}/${cacheKey}.webp`;

      // 打包为WebP格式
      const packer = image.createImagePacker();
      const packOpts: image.PackingOption = {
        format: 'image/webp',
        quality: 85
      };

      const buffer = await packer.packToData(pixelMap, packOpts);
      const size = buffer.byteLength;

      // 检查缓存大小，必要时清理
      await this.ensureCacheSpace(size);

      // 写入文件
      const file = await fs.open(filePath, fs.OpenMode.CREATE | fs.OpenMode.TRUNC | fs.OpenMode.WRITE_ONLY);
      await fs.write(file.fd, buffer);
      await fs.close(file);

      // 更新索引
      const now = Date.now();
      const entry: CacheEntry = {
        key: cacheKey,
        filePath: filePath,
        size: size,
        createTime: now,
        lastAccessTime: now,
        accessCount: 1
      };

      // 如果已存在，先减去旧的大小
      const oldEntry = this.cacheIndex.get(cacheKey);
      if (oldEntry) {
        this.totalSize -= oldEntry.size;
      }

      this.cacheIndex.set(cacheKey, entry);
      this.totalSize += size;

      await this.saveIndex();

      logger.debug(TAG, `保存到磁盘缓存: ${url.substring(0, 80)}, size=${(size / 1024).toFixed(2)}KB`);

    } catch (error) {
      logger.error(TAG, `保存到缓存失败: ${String(error)}`);
    }
  }

  /**
   * 确保有足够的缓存空间
   */
  private async ensureCacheSpace(requiredSize: number): Promise<void> {
    if (this.totalSize + requiredSize <= this.MAX_CACHE_SIZE) {
      return;
    }

    logger.info(TAG, `缓存空间不足，开始清理: 当前=${(this.totalSize / 1024 / 1024).toFixed(2)}MB, 需要=${(requiredSize / 1024 / 1024).toFixed(2)}MB`);

    // 按LRU策略排序（最近最少使用的在前）
    const entries = Array.from(this.cacheIndex.values()).sort((a, b) => {
      return a.lastAccessTime - b.lastAccessTime;
    });

    // 删除最旧的缓存，直到有足够空间
    for (const entry of entries) {
      if (this.totalSize + requiredSize <= this.MAX_CACHE_SIZE) {
        break;
      }

      await this.remove(entry.key);
      logger.debug(TAG, `清理缓存: ${entry.key}, size=${(entry.size / 1024).toFixed(2)}KB`);
    }

    logger.info(TAG, `缓存清理完成: 当前=${(this.totalSize / 1024 / 1024).toFixed(2)}MB`);
  }

  /**
   * 删除缓存项
   */
  private async remove(cacheKey: string): Promise<void> {
    try {
      const entry = this.cacheIndex.get(cacheKey);
      if (!entry) {
        return;
      }

      // 删除文件
      const fileExists = await fs.access(entry.filePath);
      if (fileExists) {
        await fs.unlink(entry.filePath);
      }

      // 更新索引
      this.cacheIndex.delete(cacheKey);
      this.totalSize -= entry.size;

    } catch (error) {
      logger.error(TAG, `删除缓存失败: ${String(error)}`);
    }
  }

  /**
   * 清理过期缓存
   */
  private async cleanExpiredCache(): Promise<void> {
    try {
      const now = Date.now();
      const expiredKeys: string[] = [];

      const entries = Array.from(this.cacheIndex.entries());
      for (let i = 0; i < entries.length; i++) {
        const key = entries[i][0];
        const entry = entries[i][1];
        if (now - entry.createTime > this.MAX_CACHE_AGE) {
          expiredKeys.push(key);
        }
      }

      if (expiredKeys.length > 0) {
        logger.info(TAG, `清理过期缓存: ${expiredKeys.length}项`);
        for (const key of expiredKeys) {
          await this.remove(key);
        }
        await this.saveIndex();
      }

    } catch (error) {
      logger.error(TAG, `清理过期缓存失败: ${String(error)}`);
    }
  }

  /**
   * 清空所有缓存
   */
  public async clear(): Promise<void> {
    try {
      logger.info(TAG, '清空所有缓存');

      for (const entry of this.cacheIndex.values()) {
        const fileExists = await fs.access(entry.filePath);
        if (fileExists) {
          await fs.unlink(entry.filePath);
        }
      }

      this.cacheIndex.clear();
      this.totalSize = 0;
      await this.saveIndex();

      logger.info(TAG, '缓存已清空');
    } catch (error) {
      logger.error(TAG, `清空缓存失败: ${String(error)}`);
    }
  }

  /**
   * 获取缓存统计信息
   */
  public getStats(): DiskCacheStats {
    const stats: DiskCacheStats = {
      count: this.cacheIndex.size,
      totalSize: this.totalSize,
      maxSize: this.MAX_CACHE_SIZE,
      usagePercent: (this.totalSize / this.MAX_CACHE_SIZE) * 100
    };
    return stats;
  }

  /**
   * 获取缓存文件路径（用于同步到数据库）
   */
  public async getCacheFilePath(url: string): Promise<string | null> {
    if (!this.initialized) {
      return null;
    }

    try {
      const cacheKey = await this.generateCacheKey(url);
      const entry = this.cacheIndex.get(cacheKey);

      if (entry) {
        const fileExists = await fs.access(entry.filePath);
        if (fileExists) {
          return entry.filePath;
        }
      }

      return null;
    } catch (error) {
      logger.error(TAG, `获取缓存文件路径失败: ${String(error)}`);
      return null;
    }
  }

  /**
   * 获取缓存文件大小
   */
  public async getCacheFileSize(url: string): Promise<number> {
    if (!this.initialized) {
      return 0;
    }

    try {
      const cacheKey = await this.generateCacheKey(url);
      const entry = this.cacheIndex.get(cacheKey);

      return entry ? entry.size : 0;
    } catch (error) {
      logger.error(TAG, `获取缓存文件大小失败: ${String(error)}`);
      return 0;
    }
  }
}
