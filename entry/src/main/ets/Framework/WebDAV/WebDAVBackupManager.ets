/**
 * WebDAV备份管理器
 * 管理WebDAV云端备份的上传、下载、同步等操作
 * 
 * 文件路径: entry/src/main/ets/Framework/WebDAV/WebDAVBackupManager.ets
 */

import { WebDAVClient, WebDAVConfig, WebDAVFile } from './WebDAVClient';
import { BackupMetadata } from '../../Models/BackupModels';
import { SandboxManager } from '../Storage/SandboxManager';
import { logger } from '../../Utils/Logger';
import { fileIo } from '@kit.CoreFileKit';

const TAG = 'WebDAVBackupManager';

export interface RemoteBackupInfo {
  fileName: string;
  remotePath: string;
  size: number;
  lastModified: number;
  metadata?: BackupMetadata;
}

// 备份索引文件结构
interface BackupIndex {
  version: number;
  lastUpdated: number;
  backups: RemoteBackupInfo[];
}

const BACKUP_INDEX_FILE = 'backups_index.json';

export interface WebDAVSyncStatus {
  isUploading: boolean;
  isDownloading: boolean;
  uploadProgress: number;
  downloadProgress: number;
  lastSyncTime: number;
  error?: string;
}

export class WebDAVBackupManager {
  private static instance: WebDAVBackupManager;
  private client: WebDAVClient | null = null;
  private config: WebDAVConfig | null = null;
  private sandboxManager = SandboxManager.getInstance();
  private syncStatus: WebDAVSyncStatus = {
    isUploading: false,
    isDownloading: false,
    uploadProgress: 0,
    downloadProgress: 0,
    lastSyncTime: 0
  };

  private constructor() {}

  static getInstance(): WebDAVBackupManager {
    if (!WebDAVBackupManager.instance) {
      WebDAVBackupManager.instance = new WebDAVBackupManager();
    }
    return WebDAVBackupManager.instance;
  }

  /**
   * 配置WebDAV
   */
  async configure(config: WebDAVConfig): Promise<void> {
    this.config = config;
    this.client = new WebDAVClient(config);
    
    // 测试连接
    const isConnected = await this.client.testConnection();
    if (!isConnected) {
      const errorMsg = '无法连接到WebDAV服务器';
      throw new Error(errorMsg);
    }
    
    // 确保备份目录存在
    await this.ensureBackupDirectory();
    
    logger.info(TAG, 'WebDAV配置成功');
  }

  /**
   * 检查是否已配置
   */
  isConfigured(): boolean {
    return this.client !== null && this.config !== null;
  }

  /**
   * 获取当前配置
   */
  getConfig(): WebDAVConfig | null {
    return this.config;
  }

  /**
   * 上传备份到云端
   */
  async uploadBackup(localBackupPath: string): Promise<void> {
    if (!this.client) {
      const errorMsg = 'WebDAV未配置';
      throw new Error(errorMsg);
    }

    try {
      this.syncStatus.isUploading = true;
      this.syncStatus.uploadProgress = 0;
      this.syncStatus.error = undefined;

      const fileName = localBackupPath.split('/').pop() || 'backup.mxbackup';
      const remotePath = `backups/${fileName}`;

      logger.info(TAG, `开始上传备份: ${fileName}`);

      // 获取文件大小
      const stat = fileIo.statSync(localBackupPath);
      const fileSize = stat.size;

      await this.client.upload(localBackupPath, remotePath, (progress) => {
        this.syncStatus.uploadProgress = progress;
      });

      // 更新备份索引
      const backupInfo: RemoteBackupInfo = {
        fileName: fileName,
        remotePath: remotePath,
        size: fileSize,
        lastModified: Date.now()
      };
      await this.addToBackupIndex(backupInfo);

      this.syncStatus.lastSyncTime = Date.now();
      logger.info(TAG, `备份上传成功: ${fileName}`);
    } catch (error) {
      this.syncStatus.error = String(error);
      logger.error(TAG, `上传备份失败: ${error}`);
      const err = error as Error;
      throw err;
    } finally {
      this.syncStatus.isUploading = false;
      this.syncStatus.uploadProgress = 0;
    }
  }

  /**
   * 从云端下载备份
   */
  async downloadBackup(remoteBackupInfo: RemoteBackupInfo): Promise<string> {
    if (!this.client) {
      const errorMsg = 'WebDAV未配置';
      throw new Error(errorMsg);
    }

    try {
      this.syncStatus.isDownloading = true;
      this.syncStatus.downloadProgress = 0;
      this.syncStatus.error = undefined;

      const backupsDir = `${this.sandboxManager.getDirectory('files')}/backups`;
      if (!await this.sandboxManager.exists(backupsDir)) {
        await this.sandboxManager.createDirectory(backupsDir);
      }

      const localPath = `${backupsDir}/${remoteBackupInfo.fileName}`;

      logger.info(TAG, `开始下载备份: ${remoteBackupInfo.fileName}`);

      await this.client.download(remoteBackupInfo.remotePath, localPath, (progress) => {
        this.syncStatus.downloadProgress = progress;
      });

      this.syncStatus.lastSyncTime = Date.now();
      logger.info(TAG, `备份下载成功: ${remoteBackupInfo.fileName}`);

      return localPath;
    } catch (error) {
      this.syncStatus.error = String(error);
      logger.error(TAG, `下载备份失败: ${error}`);
      const err = error as Error;
      throw err;
    } finally {
      this.syncStatus.isDownloading = false;
      this.syncStatus.downloadProgress = 0;
    }
  }

  /**
   * 检查索引文件是否存在
   */
  async checkIndexExists(): Promise<boolean> {
    if (!this.client) {
      return false;
    }

    try {
      const indexPath = `backups/${BACKUP_INDEX_FILE}`;
      const content = await this.client.getFileContents(indexPath, 'string');
      
      if (typeof content === 'string' && content.trim().length > 0) {
        // 验证是否是有效的JSON
        const parsed = JSON.parse(content) as BackupIndex;
        logger.info(TAG, `索引文件存在，包含 ${parsed.backups?.length || 0} 个备份`);
        return true;
      }
      return false;
    } catch (error) {
      logger.debug(TAG, `检查索引文件失败: ${error}`);
      return false;
    }
  }

  /**
   * 初始化云端备份（创建索引文件）
   */
  async initializeCloudBackup(): Promise<void> {
    if (!this.client) {
      throw new Error('WebDAV未配置');
    }

    logger.info(TAG, '初始化云端备份索引');
    
    const index: BackupIndex = {
      version: 1,
      lastUpdated: Date.now(),
      backups: []
    };
    
    await this.saveBackupIndex(index);
    logger.info(TAG, '云端备份索引已创建');
  }

  /**
   * 读取备份索引文件
   */
  private async readBackupIndex(): Promise<BackupIndex> {
    if (!this.client) {
      return { version: 1, lastUpdated: 0, backups: [] };
    }

    try {
      const indexPath = `backups/${BACKUP_INDEX_FILE}`;
      const content = await this.client.getFileContents(indexPath, 'string');
      
      if (typeof content === 'string' && content.trim()) {
        const index = JSON.parse(content) as BackupIndex;
        logger.info(TAG, `读取到备份索引，包含 ${index.backups.length} 个备份`);
        return index;
      }
    } catch (error) {
      logger.warn(TAG, `读取备份索引失败: ${error}`);
    }

    return { version: 1, lastUpdated: 0, backups: [] };
  }

  /**
   * 保存备份索引文件
   */
  private async saveBackupIndex(index: BackupIndex): Promise<void> {
    if (!this.client) {
      throw new Error('WebDAV未配置');
    }

    try {
      index.lastUpdated = Date.now();
      const indexPath = `backups/${BACKUP_INDEX_FILE}`;
      const content = JSON.stringify(index, null, 2);
      
      await this.client.putFileContents(indexPath, content);
      logger.info(TAG, `备份索引已保存，包含 ${index.backups.length} 个备份`);
    } catch (error) {
      logger.error(TAG, `保存备份索引失败: ${error}`);
      throw error as Error;
    }
  }

  /**
   * 添加备份到索引
   */
  private async addToBackupIndex(backupInfo: RemoteBackupInfo): Promise<void> {
    const index = await this.readBackupIndex();
    
    // 检查是否已存在
    const existingIndex = index.backups.findIndex(b => b.fileName === backupInfo.fileName);
    if (existingIndex >= 0) {
      index.backups[existingIndex] = backupInfo;
    } else {
      index.backups.push(backupInfo);
    }
    
    // 按时间倒序排序
    index.backups.sort((a, b) => b.lastModified - a.lastModified);
    
    await this.saveBackupIndex(index);
  }

  /**
   * 从索引中移除备份
   */
  private async removeFromBackupIndex(fileName: string): Promise<void> {
    const index = await this.readBackupIndex();
    index.backups = index.backups.filter(b => b.fileName !== fileName);
    await this.saveBackupIndex(index);
  }

  /**
   * 列出云端所有备份（从索引文件读取）
   */
  async listRemoteBackups(): Promise<RemoteBackupInfo[]> {
    if (!this.client) {
      const errorMsg = 'WebDAV未配置';
      throw new Error(errorMsg);
    }

    try {
      const index = await this.readBackupIndex();
      logger.info(TAG, `找到 ${index.backups.length} 个云端备份`);
      return index.backups;
    } catch (error) {
      logger.error(TAG, `列出云端备份失败: ${error}`);
      return [];
    }
  }

  /**
   * 删除云端备份
   */
  async deleteRemoteBackup(remoteBackupInfo: RemoteBackupInfo): Promise<void> {
    if (!this.client) {
      const errorMsg = 'WebDAV未配置';
      throw new Error(errorMsg);
    }

    try {
      await this.client.delete(remoteBackupInfo.remotePath);
      
      // 从索引中移除
      await this.removeFromBackupIndex(remoteBackupInfo.fileName);
      
      logger.info(TAG, `删除云端备份成功: ${remoteBackupInfo.fileName}`);
    } catch (error) {
      logger.error(TAG, `删除云端备份失败: ${error}`);
      const err = error as Error;
      throw err;
    }
  }

  /**
   * 自动备份（上传最新的本地备份）
   */
  async autoBackup(): Promise<void> {
    if (!this.client) {
      const errorMsg = 'WebDAV未配置';
      throw new Error(errorMsg);
    }

    try {
      // 获取最新的本地备份
      const backupsDir = `${this.sandboxManager.getDirectory('files')}/backups`;
      if (!await this.sandboxManager.exists(backupsDir)) {
        logger.warn(TAG, '没有本地备份可以上传');
        return;
      }

      const files = await fileIo.listFile(backupsDir);
      const backupFiles = files.filter(f => f.endsWith('.mxbackup'));
      
      if (backupFiles.length === 0) {
        logger.warn(TAG, '没有本地备份可以上传');
        return;
      }

      // 获取最新的备份文件
      let latestFile = backupFiles[0];
      let latestTime = 0;
      
      for (const file of backupFiles) {
        const filePath = `${backupsDir}/${file}`;
        const stat = await fileIo.stat(filePath);
        if (stat.mtime > latestTime) {
          latestTime = stat.mtime;
          latestFile = file;
        }
      }

      const latestBackupPath = `${backupsDir}/${latestFile}`;
      
      // 检查云端是否已存在
      const remoteBackups = await this.listRemoteBackups();
      const exists = remoteBackups.some(b => b.fileName === latestFile);
      
      if (exists) {
        logger.info(TAG, `云端已存在该备份: ${latestFile}`);
        return;
      }

      // 上传
      await this.uploadBackup(latestBackupPath);
    } catch (error) {
      logger.error(TAG, `自动备份失败: ${error}`);
      const err = error as Error;
      throw err;
    }
  }

  /**
   * 清理旧备份（保留最近N个）
   */
  async cleanOldBackups(keepCount: number = 5): Promise<void> {
    if (!this.client) {
      const errorMsg = 'WebDAV未配置';
      throw new Error(errorMsg);
    }

    try {
      const remoteBackups = await this.listRemoteBackups();
      
      if (remoteBackups.length <= keepCount) {
        logger.info(TAG, `云端备份数量 ${remoteBackups.length} <= ${keepCount}，无需清理`);
        return;
      }

      const toDelete = remoteBackups.slice(keepCount);
      
      for (const backup of toDelete) {
        await this.deleteRemoteBackup(backup);
      }

      logger.info(TAG, `清理了 ${toDelete.length} 个旧备份`);
    } catch (error) {
      logger.error(TAG, `清理旧备份失败: ${error}`);
      const err = error as Error;
      throw err;
    }
  }

  /**
   * 获取同步状态
   */
  getSyncStatus(): WebDAVSyncStatus {
    return {
      isUploading: this.syncStatus.isUploading,
      isDownloading: this.syncStatus.isDownloading,
      uploadProgress: this.syncStatus.uploadProgress,
      downloadProgress: this.syncStatus.downloadProgress,
      lastSyncTime: this.syncStatus.lastSyncTime,
      error: this.syncStatus.error
    };
  }

  /**
   * 确保备份目录存在
   * 注意：HarmonyOS不支持MKCOL方法，目录会在首次上传文件时自动创建
   */
  private async ensureBackupDirectory(): Promise<void> {
    if (!this.client) return;

    try {
      const exists = await this.client.exists('backups');
      if (!exists) {
        // 通过上传测试文件来创建目录
        logger.info(TAG, '备份目录不存在，将在上传时自动创建');
      }
    } catch (error) {
      // 忽略检查错误，上传时会自动创建目录
      logger.warn(TAG, `检查备份目录时出错: ${error}`);
    }
  }
}

export function getWebDAVBackupManager(): WebDAVBackupManager {
  return WebDAVBackupManager.getInstance();
}
