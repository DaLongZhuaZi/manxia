import fileIo from '@ohos.file.fs';
import { logger } from '../../Utils/Logger';
import common from '@ohos.app.ability.common';

const TAG = 'DistributedFileManager';
const DISTRIBUTED_CACHE_DIR = 'reading_cache';

export class DistributedFileManager {
  private static instance: DistributedFileManager;
  private context: common.UIAbilityContext | null = null;
  private distributedRoot: string = '';

  private constructor() {}

  public static getInstance(): DistributedFileManager {
    if (!DistributedFileManager.instance) {
      DistributedFileManager.instance = new DistributedFileManager();
    }
    return DistributedFileManager.instance;
  }

  public initialize(context: common.UIAbilityContext): void {
    this.context = context;
    try {
      this.distributedRoot = context.distributedFilesDir;
      const cacheDir = this.getDistributedCachePath();
      if (!fileIo.accessSync(cacheDir)) {
        fileIo.mkdirSync(cacheDir);
        logger.info(TAG, `Created distributed cache directory at ${cacheDir}`);
      }
    } catch (e) {
      logger.error(TAG, `Failed to initialize DistributedFileManager: ${String(e)}`);
    }
  }

  private getDistributedCachePath(): string {
    return `${this.distributedRoot}/${DISTRIBUTED_CACHE_DIR}`;
  }

  /**
   * 将本地缓存内容复制到分布式文件沙箱中，以便目标设备访问
   */
  public copyToDistributed(localFilePath: string, destFileName: string): boolean {
    if (!this.distributedRoot) {
      logger.warn(TAG, 'Distributed root is not initialized.');
      return false;
    }

    try {
      if (!fileIo.accessSync(localFilePath)) {
        logger.warn(TAG, `Source file does not exist: ${localFilePath}`);
        return false;
      }
      
      const destPath = `${this.getDistributedCachePath()}/${destFileName}`;
      
      // 如果目标已存在，先删除
      if (fileIo.accessSync(destPath)) {
        fileIo.unlinkSync(destPath);
      }
      
      fileIo.copyFileSync(localFilePath, destPath);
      logger.info(TAG, `Successfully copied file to distributed sandbox: ${destFileName}`);
      return true;
    } catch (e) {
      logger.error(TAG, `Failed to copy file to distributed: ${String(e)}`);
      return false;
    }
  }

  /**
   * 从分布式沙箱读取文件路径
   */
  public getDistributedFilePath(fileName: string): string | null {
    if (!this.distributedRoot) return null;
    
    const path = `${this.getDistributedCachePath()}/${fileName}`;
    try {
      if (fileIo.accessSync(path)) {
        return path;
      }
    } catch (e) {
      logger.error(TAG, `Failed to access distributed file ${fileName}: ${String(e)}`);
    }
    return null;
  }

  /**
   * 将文本内容直接写入分布式沙箱（例如小说章节文本）
   */
  public writeTextToDistributed(fileName: string, content: string): boolean {
    if (!this.distributedRoot) return false;
    
    const path = `${this.getDistributedCachePath()}/${fileName}`;
    try {
      const file = fileIo.openSync(path, fileIo.OpenMode.READ_WRITE | fileIo.OpenMode.CREATE | fileIo.OpenMode.TRUNC);
      fileIo.writeSync(file.fd, content);
      fileIo.closeSync(file);
      logger.info(TAG, `Successfully wrote text to distributed sandbox: ${fileName}`);
      return true;
    } catch (e) {
      logger.error(TAG, `Failed to write text to distributed sandbox: ${String(e)}`);
      return false;
    }
  }

  /**
   * 读取分布式沙箱中的文本内容
   */
  public readTextFromDistributed(fileName: string): string | null {
    if (!this.distributedRoot) return null;
    
    const path = `${this.getDistributedCachePath()}/${fileName}`;
    try {
      if (fileIo.accessSync(path)) {
        return fileIo.readTextSync(path);
      }
    } catch (e) {
      logger.error(TAG, `Failed to read text from distributed sandbox: ${String(e)}`);
    }
    return null;
  }

  /**
   * 清理过期或不再需要的分布式缓存
   */
  public clearDistributedCache(): void {
    if (!this.distributedRoot) return;
    
    try {
      const cacheDir = this.getDistributedCachePath();
      const files = fileIo.listFileSync(cacheDir);
      for (const file of files) {
        fileIo.unlinkSync(`${cacheDir}/${file}`);
      }
      logger.info(TAG, 'Successfully cleared distributed cache.');
    } catch (e) {
      logger.error(TAG, `Failed to clear distributed cache: ${String(e)}`);
    }
  }
}

export const distributedFileManager = DistributedFileManager.getInstance();
