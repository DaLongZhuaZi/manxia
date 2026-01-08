/**
 * Download同步管理器
 * 负责在APP启动时初始化Download同步目录和保留文件夹
 * 
 * 文件路径: entry/src/main/ets/Framework/Managers/DownloadSyncManager.ets
 */

import { logger } from '../../Utils/Logger';
import { fileIo as fs } from '@kit.CoreFileKit';

const TAG = 'DownloadSyncManager';

// 保留文件夹列表（与DownloadSyncPage保持一致）
const RESERVED_FOLDERS: string[] = ['ebooks', 'manga', 'novel', 'storage', 'covers', 'temp', 'backup', 'legadoextensions'];

/**
 * Download同步管理器
 * 单例模式，负责管理Download同步目录的初始化和保留文件夹的创建
 */
export class DownloadSyncManager {
  private static instance: DownloadSyncManager;
  private initialized: boolean = false;

  private constructor() {}

  static getInstance(): DownloadSyncManager {
    if (!DownloadSyncManager.instance) {
      DownloadSyncManager.instance = new DownloadSyncManager();
    }
    return DownloadSyncManager.instance;
  }

  /**
   * 初始化Download同步目录
   * 在APP启动时调用，检查并创建保留文件夹
   */
  async initialize(): Promise<void> {
    if (this.initialized) {
      logger.info(TAG, 'Download同步管理器已初始化，跳过');
      return;
    }

    try {
      // 从AppStorage获取已保存的Download同步目录路径
      const downloadDirPath = AppStorage.get<string>('downloadSyncDirPath');
      
      if (!downloadDirPath) {
        logger.info(TAG, 'Download同步目录未配置，跳过初始化');
        this.initialized = true;
        return;
      }

      logger.info(TAG, `检查Download同步目录: ${downloadDirPath}`);

      // 检查目录是否存在
      try {
        fs.accessSync(downloadDirPath);
      } catch (e) {
        logger.warn(TAG, `Download同步目录不存在或无法访问: ${downloadDirPath}`);
        this.initialized = true;
        return;
      }

      // 创建保留文件夹
      await this.createReservedFolders(downloadDirPath);

      this.initialized = true;
      logger.info(TAG, '✅ Download同步管理器初始化完成');
    } catch (error) {
      logger.error(TAG, `Download同步管理器初始化失败: ${String(error)}`);
      this.initialized = true; // 即使失败也标记为已初始化，避免重复尝试
    }
  }

  /**
   * 创建保留文件夹
   */
  private async createReservedFolders(downloadDirPath: string): Promise<void> {
    let createdCount = 0;
    let existingCount = 0;

    for (const folderName of RESERVED_FOLDERS) {
      try {
        const folderPath = `${downloadDirPath}/${folderName}`;
        
        try {
          fs.accessSync(folderPath);
          existingCount++;
        } catch (e) {
          // 文件夹不存在，创建它
          fs.mkdirSync(folderPath);
          createdCount++;
          logger.info(TAG, `创建保留文件夹: ${folderName}`);
        }
      } catch (error) {
        logger.warn(TAG, `创建保留文件夹 ${folderName} 失败: ${String(error)}`);
      }
    }

    logger.info(TAG, `保留文件夹检查完成: ${createdCount} 个新建, ${existingCount} 个已存在`);
  }

  /**
   * 检查Download同步目录是否已配置
   */
  isConfigured(): boolean {
    const downloadDirPath = AppStorage.get<string>('downloadSyncDirPath');
    return !!downloadDirPath;
  }

  /**
   * 获取Download同步目录路径
   */
  getDownloadDirPath(): string | undefined {
    return AppStorage.get<string>('downloadSyncDirPath');
  }

  /**
   * 获取保留文件夹路径
   */
  getReservedFolderPath(folderName: string): string | undefined {
    const downloadDirPath = this.getDownloadDirPath();
    if (!downloadDirPath) {
      return undefined;
    }
    return `${downloadDirPath}/${folderName}`;
  }

  /**
   * 确保保留文件夹存在
   */
  ensureReservedFolder(folderName: string): string | undefined {
    const folderPath = this.getReservedFolderPath(folderName);
    if (!folderPath) {
      return undefined;
    }

    try {
      try {
        fs.accessSync(folderPath);
      } catch (e) {
        fs.mkdirSync(folderPath);
        logger.info(TAG, `创建保留文件夹: ${folderName}`);
      }
      return folderPath;
    } catch (error) {
      logger.error(TAG, `确保保留文件夹存在失败: ${folderName}, ${String(error)}`);
      return undefined;
    }
  }
}

export function getDownloadSyncManager(): DownloadSyncManager {
  return DownloadSyncManager.getInstance();
}
