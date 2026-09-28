// 文件路径: src/main/ets/Framework/Storage/SandboxManager.ets
/**
 * 沙箱存储管理器
 * 基于HarmonyOS安全沙箱机制实现文件存储管理
 */

import { fileIo } from '@kit.CoreFileKit';
import { logger } from '../../Utils/Logger';
import { BusinessError } from '@kit.BasicServicesKit';
import { util } from '@kit.ArkTS';

// 存储服务标签
const TAG = 'SandboxManager';

// 存储配置接口
export interface StorageConfig {
  maxCacheSize: number;        // 最大缓存大小（字节）
  maxFileAge: number;          // 文件最大存活时间（毫秒）
  cleanupInterval: number;     // 清理间隔（毫秒）
}

// 文件信息接口
export interface FileInfo {
  path: string;
  size: number;
  createTime: number;
  lastAccessTime: number;
  mimeType?: string;
}


/**
 * 目录路径接口
 */
interface DirectoryPaths {
  files: string;
  cache: string;
  comics: string;
  covers: string;
  chapters: string;
  temp: string;
  database: string;
  plugins: string;
  ebooks: string;
}

/**
 * 目录条目接口
 */
interface DirectoryEntry {
  key: keyof DirectoryPaths;
  value: string;
}

// 存储统计信息接口
interface StorageStats {
  totalSize: number;
  cacheSize: number;
  comicsSize: number;
  coversSize: number;
  chaptersSize: number;
  tempSize: number;
}

// 文件信息扩展接口
interface FileInfoExtended {
  path: string;
  atime: number;
  size: number;
}

export class SandboxManager {
  private static instance: SandboxManager | null = null;
  private context: Context | null = null;
  private cleanupTimer: number | null = null;
  
  // 默认配置
  private config: StorageConfig = {
    maxCacheSize: 500 * 1024 * 1024,  // 500MB
    maxFileAge: 7 * 24 * 60 * 60 * 1000,  // 7天
    cleanupInterval: 60 * 60 * 1000  // 1小时
  };

  // 沙箱目录路径
  private readonly directories: DirectoryPaths = {
    // 应用数据目录 - el2/base/files/
    files: '',
    // 缓存目录
    cache: '',
    // 漫画数据目录
    comics: '',
    // 封面缓存目录
    covers: '',
    // 章节下载目录
    chapters: '',
    // 临时文件目录
    temp: '',
    // 数据库目录
    database: '',
    // 插件目录
    plugins: '',
    // 电子书目录
    ebooks: ''
  };

  private constructor() {}

  /**
   * 获取单例实例
   */
  public static getInstance(): SandboxManager {
    if (!SandboxManager.instance) {
      SandboxManager.instance = new SandboxManager();
    }
    return SandboxManager.instance;
  }

  /**
   * 初始化沙箱管理器
   */
  public async initialize(context: Context, config?: Partial<StorageConfig>): Promise<void> {
    try {
      logger.info(TAG, '沙箱管理器开始初始化...');
      if (!context) {
        throw new Error('初始化时传入的Context为null');
      }
      this.context = context;
      logger.info(TAG, '✅ Context已设置到SandboxManager');
      
      // 合并配置
      if (config) {
        this.config.maxCacheSize = config.maxCacheSize ?? this.config.maxCacheSize;
        this.config.maxFileAge = config.maxFileAge ?? this.config.maxFileAge;
        this.config.cleanupInterval = config.cleanupInterval ?? this.config.cleanupInterval;
      }

      // 初始化目录路径
      await this.initializeDirectories();
      logger.info(TAG, '✅ 目录路径已初始化');
      
      // 创建必要的目录
      await this.createDirectories();
      logger.info(TAG, '✅ 必要的目录已创建');
      
      // 启动定期清理
      this.startCleanupTimer();
      
      logger.info(TAG, '✅ 沙箱管理器初始化完成');
    } catch (error) {
      logger.error(TAG, `❌ 沙箱管理器初始化失败: ${String(error)}`);
      throw error as Error;
    }
  }

  /**
   * 初始化目录路径
   */
  private async initializeDirectories(): Promise<void> {
    if (!this.context) {
      throw new Error('Context未初始化');
    }

    try {
      // 获取应用文件目录 - el2/base/files/
      const filesDir = this.context.filesDir;
      
      this.directories.files = filesDir;
      this.directories.cache = `${filesDir}/cache`;
      this.directories.comics = `${filesDir}/comics`;
      this.directories.covers = `${filesDir}/covers`;
      this.directories.chapters = `${filesDir}/chapters`;
      this.directories.temp = `${filesDir}/temp`;
      this.directories.database = `${filesDir}/database`;
      this.directories.plugins = `${filesDir}/plugins`;
      this.directories.ebooks = `${filesDir}/ebooks`;
      
      logger.debug(TAG, `文件目录: ${filesDir}`);
    } catch (error) {
      logger.error(TAG, '初始化目录路径失败' + String(error));
      throw error as Error;
    }
  }

  /**
   * 创建必要的目录
   */
  private async createDirectories(): Promise<void> {
    try {
      // 直接遍历目录值，避免索引访问
      const directoryEntries: Array<DirectoryEntry> = [
        { key: 'files', value: this.directories.files },
        { key: 'cache', value: this.directories.cache },
        { key: 'comics', value: this.directories.comics },
        { key: 'covers', value: this.directories.covers },
        { key: 'chapters', value: this.directories.chapters },
        { key: 'temp', value: this.directories.temp },
        { key: 'database', value: this.directories.database },
        { key: 'plugins', value: this.directories.plugins },
        { key: 'ebooks', value: this.directories.ebooks }
      ];
      
      for (const entry of directoryEntries) {
        if (entry.value && !await this.exists(entry.value)) {
          await this.createDirectory(entry.value);
          logger.debug(TAG, `创建目录: ${entry.value}`);
        }
      }
    } catch (error) {
      logger.error(TAG, '创建目录失败' + String(error));
      throw error as Error;
    }
  }

  /**
   * 获取目录路径
   */
  public getDirectory(type: keyof DirectoryPaths): string {
    // 检查Context是否已初始化
    if (!this.context) {
      const errorMsg = `SandboxManager未初始化，无法获取目录路径: ${type}`;
      logger.error(TAG, errorMsg);
      throw new Error(errorMsg);
    }
    
    // 使用显式属性访问替代索引访问
    let path: string = '';
    
    switch (type) {
      case 'files':
        path = this.directories.files;
        break;
      case 'cache':
        path = this.directories.cache;
        break;
      case 'comics':
        path = this.directories.comics;
        break;
      case 'covers':
        path = this.directories.covers;
        break;
      case 'chapters':
        path = this.directories.chapters;
        break;
      case 'temp':
        path = this.directories.temp;
        break;
      case 'database':
        path = this.directories.database;
        break;
      case 'plugins':
        path = this.directories.plugins;
        break;
      case 'ebooks':
        path = this.directories.ebooks;
        break;
      default:
        throw new Error(`未知的目录类型: ${type}`);
    }
    
    if (!path) {
      const errorMsg = `目录路径为空: type=${type}, context已初始化但路径未设置`;
      logger.error(TAG, errorMsg);
      throw new Error(errorMsg);
    }
    
    logger.debug(TAG, `获取目录路径: ${type} -> ${path}`);
    return path;
  }

  /**
   * 检查文件或目录是否存在
   */
  public async exists(path: string): Promise<boolean> {
    try {
      const stat = await fileIo.stat(path);
      return stat !== null;
    } catch (error) {
      return false;
    }
  }

  /**
   * 检查路径本身是否为符号链接。导入扫描必须使用 lstat，不能跟随链接
   * 进入沙箱之外的目录或把链接目标当成可复制的漫画页面。
   */
  public async isSymbolicLink(path: string): Promise<boolean> {
    try {
      const stat = await fileIo.lstat(path);
      return stat.isSymbolicLink();
    } catch (error) {
      return false;
    }
  }

  /**
   * 创建目录
   */
  public async createDirectory(path: string): Promise<void> {
    try {
      // 检查目录是否已存在
      if (await this.exists(path)) {
        logger.debug(TAG, `目录已存在，跳过创建: ${path}`);
        return;
      }
      
      await fileIo.mkdir(path, true);
      logger.debug(TAG, `目录创建成功: ${path}`);
    } catch (error) {
      logger.error(TAG, `创建目录失败: ${path}` + String(error));
      throw error as Error;
    }
  }

  /**
   * 写入文件
   */
  public async writeFile(path: string, data: string | ArrayBuffer): Promise<void> {
    try {
      // 确保父目录存在
      const parentDir = path.substring(0, path.lastIndexOf('/'));
      if (parentDir && !await this.exists(parentDir)) {
        await this.createDirectory(parentDir);
      }

      const file = await fileIo.open(path, fileIo.OpenMode.CREATE | fileIo.OpenMode.WRITE_ONLY);
      
      if (typeof data === 'string') {
        await fileIo.write(file.fd, data);
      } else {
        await fileIo.write(file.fd, data);
      }
      
      await fileIo.close(file.fd);
      logger.debug(TAG, `文件写入成功: ${path}`);
    } catch (error) {
      logger.error(TAG, `写入文件失败: ${path}` + String(error));
      throw error as Error;
    }
  }

  /**
   * 读取文件
   */
  public async readFile(path: string): Promise<ArrayBuffer> {
    try {
      const file = await fileIo.open(path, fileIo.OpenMode.READ_ONLY);
      const stat = await fileIo.stat(path);
      const buffer = new ArrayBuffer(stat.size);
      
      await fileIo.read(file.fd, buffer);
      await fileIo.close(file.fd);
      
      logger.debug(TAG, `文件读取成功: ${path}`);
      return buffer;
    } catch (error) {
      logger.error(TAG, `读取文件失败: ${path}` + String(error));
      throw error as Error;
    }
  }

  /**
   * 读取文本文件
   */
  public async readTextFile(path: string, encoding: string = 'utf-8'): Promise<string> {
    try {
      const buffer = await this.readFile(path);
      const decoder = new util.TextDecoder(encoding);
      return decoder.decodeToString(new Uint8Array(buffer));
    } catch (error) {
      logger.error(TAG, `读取文本文件失败: ${path}` + String(error));
      throw error as Error;
    }
  }

  /**
   * 复制文件
   * URI 通过只读 FD 交给系统流式复制，兼容 file://docs、相册和数据共享 URI。
   */
  public async copyFile(sourcePath: string, targetPath: string): Promise<void> {
    try {
      // 确保目标目录存在
      const parentDir = targetPath.substring(0, targetPath.lastIndexOf('/'));
      if (parentDir && !await this.exists(parentDir)) {
        await this.createDirectory(parentDir);
      }

      if (sourcePath.includes('://')) {
        let sourceFile: fileIo.File | null = null;
        try {
          sourceFile = await fileIo.open(sourcePath, fileIo.OpenMode.READ_ONLY);
          const sourceStat = await fileIo.stat(sourceFile.fd);
          await fileIo.copyFile(sourceFile.fd, targetPath);
          const targetStat = await fileIo.stat(targetPath);
          if (targetStat.size !== sourceStat.size) {
            throw new Error(`文件复制不完整: 期望 ${sourceStat.size} 字节，实际 ${targetStat.size} 字节`);
          }
          logger.debug(TAG, `从URI复制文件成功: ${sourcePath} -> ${targetPath}`);
        } finally {
          if (sourceFile) {
            await fileIo.close(sourceFile);
          }
        }
      } else {
        // 普通文件路径直接复制
        await fileIo.copyFile(sourcePath, targetPath);
        logger.debug(TAG, `文件复制成功: ${sourcePath} -> ${targetPath}`);
      }
    } catch (error) {
      logger.error(TAG, `复制文件失败: ${sourcePath} -> ${targetPath}` + String(error));
      throw error as Error;
    }
  }

  /**
   * 移动文件
   */
  public async moveFile(sourcePath: string, targetPath: string): Promise<void> {
    try {
      await this.copyFile(sourcePath, targetPath);
      await this.deleteFile(sourcePath);
      logger.debug(TAG, `文件移动成功: ${sourcePath} -> ${targetPath}`);
    } catch (error) {
      logger.error(TAG, `移动文件失败: ${sourcePath} -> ${targetPath}` + String(error));
      throw error as Error;
    }
  }

  /**
   * 删除文件
   */
  public async deleteFile(path: string): Promise<void> {
    try {
      await fileIo.unlink(path);
      logger.debug(TAG, `文件删除成功: ${path}`);
    } catch (error) {
      logger.error(TAG, `删除文件失败: ${path}` + String(error));
      throw error as Error;
    }
  }

  /**
   * 删除目录
   */
  public async deleteDirectory(path: string, recursive: boolean = false): Promise<void> {
    try {
      if (recursive) {
        await this.deleteDirectoryRecursive(path);
      } else {
        await fileIo.rmdir(path);
      }
      logger.debug(TAG, `目录删除成功: ${path}`);
    } catch (error) {
      logger.error(TAG, `删除目录失败: ${path}` + String(error));
      throw error as Error;
    }
  }

  private async deleteDirectoryRecursive(path: string): Promise<void> {
    const rootStat = await fileIo.lstat(path);
    if (rootStat.isSymbolicLink()) {
      await fileIo.unlink(path);
      return;
    }
    if (!rootStat.isDirectory()) {
      await fileIo.unlink(path);
      return;
    }
    const entries: string[] = await fileIo.listFile(path);
    for (const entry of entries) {
      const entryPath: string = `${path}/${entry}`;
      const stat = await fileIo.lstat(entryPath);
      if (stat.isSymbolicLink()) {
        await fileIo.unlink(entryPath);
      } else if (stat.isDirectory()) {
        await this.deleteDirectoryRecursive(entryPath);
      } else {
        await fileIo.unlink(entryPath);
      }
    }
    await fileIo.rmdir(path);
  }

  /**
   * 获取文件信息
   */
  public async getFileInfo(path: string): Promise<FileInfo> {
    try {
      const stat = await fileIo.stat(path);
      const fileInfo: FileInfo = {
        path: path,
        size: stat.size,
        createTime: stat.ctime,
        lastAccessTime: stat.atime
      };
      return fileInfo;
    } catch (error) {
      logger.error(TAG, `获取文件信息失败: ${path}` + String(error));
      throw error as Error;
    }
  }

  /**
   * 列出目录内容
   */
  public async listDirectory(path: string): Promise<string[]> {
    try {
      const stat = await fileIo.stat(path);
      if (!stat.isDirectory()) {
        logger.warn(TAG, `目标路径不是目录，跳过列出: ${path}`);
        return [];
      }
      const files = await fileIo.listFile(path);
      logger.debug(TAG, `列出目录内容: ${path}, 文件数: ${files.length}`);
      return files;
    } catch (error) {
      logger.error(TAG, `列出目录内容失败: ${path}` + String(error));
      throw error as Error;
    }
  }

  /**
   * 获取目录大小
   */
  public async getDirectorySize(path: string): Promise<number> {
    try {
      let totalSize = 0;
      const files = await this.listDirectory(path);
      
      for (const file of files) {
        const filePath = `${path}/${file}`;
        const stat = await fileIo.stat(filePath);
        
        if (stat.isDirectory()) {
          totalSize += await this.getDirectorySize(filePath);
        } else {
          totalSize += stat.size;
        }
      }
      
      return totalSize;
    } catch (error) {
      logger.error(TAG, `获取目录大小失败: ${path}` + String(error));
      return 0;
    }
  }

  /**
   * 清理过期文件
   */
  public async cleanupExpiredFiles(): Promise<void> {
    try {
      const now = Date.now();
      const cacheDir = this.directories.cache;
      const tempDir = this.directories.temp;
      
      await this.cleanupDirectoryByAge(cacheDir, now - this.config.maxFileAge);
      await this.cleanupDirectoryByAge(tempDir, now - this.config.maxFileAge);
      
      logger.info(TAG, '过期文件清理完成');
    } catch (error) {
      logger.error(TAG, '清理过期文件失败' + String(error));
    }
  }

  /**
   * 按年龄清理目录
   */
  private async cleanupDirectoryByAge(path: string, maxAge: number): Promise<void> {
    try {
      if (!await this.exists(path)) {
        return;
      }

      const files = await this.listDirectory(path);
      
      for (const file of files) {
        const filePath = `${path}/${file}`;
        const stat = await fileIo.stat(filePath);
        
        if (stat.isDirectory()) {
          await this.cleanupDirectoryByAge(filePath, maxAge);
        } else if (stat.ctime < maxAge) {
          await this.deleteFile(filePath);
          logger.debug(TAG, `删除过期文件: ${filePath}`);
        }
      }
    } catch (error) {
      logger.error(TAG, `清理目录失败: ${path}` + String(error));
    }
  }

  /**
   * 检查并清理缓存大小
   */
  public async checkAndCleanupCache(): Promise<void> {
    try {
      const cacheSize = await this.getDirectorySize(this.directories.cache);
      
      if (cacheSize > this.config.maxCacheSize) {
        logger.info(TAG, `缓存大小超限: ${cacheSize} > ${this.config.maxCacheSize}`);
        await this.cleanupCacheBySize();
      }
    } catch (error) {
      logger.error(TAG, '检查缓存大小失败' + String(error));
    }
  }

  /**
   * 按大小清理缓存
   */
  private async cleanupCacheBySize(): Promise<void> {
    try {
      const cacheDir = this.directories.cache;
      const files = await this.listDirectory(cacheDir);
      
      // 获取文件信息并按访问时间排序
      const fileInfos: FileInfoExtended[] = [];
      
      for (const file of files) {
        const filePath = `${cacheDir}/${file}`;
        const stat = await fileIo.stat(filePath);
        
        if (!stat.isDirectory()) {
          const fileInfo: FileInfoExtended = {
            path: filePath,
            atime: stat.atime,
            size: stat.size
          };
          fileInfos.push(fileInfo);
        }
      }
      
      // 按访问时间排序（最旧的在前）
      fileInfos.sort((a, b) => a.atime - b.atime);
      
      // 删除最旧的文件直到缓存大小合适
      let currentSize = await this.getDirectorySize(cacheDir);
      const targetSize = this.config.maxCacheSize * 0.8; // 清理到80%
      
      for (const fileInfo of fileInfos) {
        if (currentSize <= targetSize) {
          break;
        }
        
        await this.deleteFile(fileInfo.path);
        currentSize -= fileInfo.size;
        logger.debug(TAG, `删除缓存文件: ${fileInfo.path}`);
      }
      
      logger.info(TAG, '缓存大小清理完成');
    } catch (error) {
      logger.error(TAG, '按大小清理缓存失败' + String(error));
    }
  }

  /**
   * 启动定期清理定时器
   */
  private startCleanupTimer(): void {
    if (this.cleanupTimer) {
      clearInterval(this.cleanupTimer);
    }
    
    this.cleanupTimer = setInterval(() => {
      this.cleanupExpiredFiles();
      this.checkAndCleanupCache();
    }, this.config.cleanupInterval);
    
    logger.debug(TAG, '定期清理定时器已启动');
  }

  /**
   * 停止定期清理定时器
   */
  private stopCleanupTimer(): void {
    if (this.cleanupTimer) {
      clearInterval(this.cleanupTimer);
      this.cleanupTimer = null;
      logger.debug(TAG, '定期清理定时器已停止');
    }
  }

  /**
   * 获取存储统计信息
   */
  public async getStorageStats(): Promise<StorageStats> {
    try {
      const cacheSize = await this.getDirectorySize(this.directories.cache);
      const comicsSize = await this.getDirectorySize(this.directories.comics);
      const coversSize = await this.getDirectorySize(this.directories.covers);
      const chaptersSize = await this.getDirectorySize(this.directories.chapters);
      const tempSize = await this.getDirectorySize(this.directories.temp);
      
      const totalSize = cacheSize + comicsSize + coversSize + chaptersSize + tempSize;
      
      const stats: StorageStats = {
        totalSize,
        cacheSize,
        comicsSize,
        coversSize,
        chaptersSize,
        tempSize
      };
      
      return stats;
    } catch (error) {
      logger.error(TAG, '获取存储统计信息失败' + String(error));
      throw error as Error;
    }
  }

  /**
   * 销毁管理器
   */
  public destroy(): void {
    this.stopCleanupTimer();
    this.context = null;
    SandboxManager.instance = null;
    logger.info(TAG, '沙箱管理器已销毁');
  }
}
