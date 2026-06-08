import { SafeFileUtils } from '../../Utils/SafeFileUtils';
import { SafeUtils } from '../../Utils/SafeUtils';
/**
 * WebDAV备份管理器
 * 管理WebDAV云端备份的上传、下载、同步等操作
 * 
 * 已升级为使用Native C++ WebDAV客户端，支持完整的WebDAV协议
 * 
 * 文件路径: entry/src/main/ets/Framework/WebDAV/WebDAVBackupManager.ets
 */

import { WebDAVClient, WebDAVConfig, WebDAVFile } from './WebDAVClient';
import { WebDAVNativeClient, WebDAVNativeConfig, isNativeModuleAvailable, getNativeModuleError } from './WebDAVNativeClient';
import { BackupMetadata, BackupOptions, BackupItemCounts } from '../../Models/BackupModels';
import { SandboxManager } from '../Storage/SandboxManager';
import { logger } from '../../Utils/Logger';
import { fileIo } from '@kit.CoreFileKit';

const TAG = 'WebDAVBackupManager';
const ARKTS_WEBDAV_FALLBACK_MAX_FILE_BYTES = 32 * 1024 * 1024;
const ARKTS_WEBDAV_FALLBACK_MAX_FILE_MIB = ARKTS_WEBDAV_FALLBACK_MAX_FILE_BYTES / 1024 / 1024;

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

interface RawBackupIndex {
  version?: number | string;
  lastUpdated?: number | string;
  backups?: RawRemoteBackupInfo[];
}

interface RawRemoteBackupInfo {
  fileName?: string;
  size?: number | string;
  lastModified?: number | string;
  metadata?: RawBackupMetadata;
}

interface RawBackupMetadata {
  version?: string;
  appVersion?: string;
  timestamp?: number | string;
  deviceInfo?: string;
  itemCounts?: BackupItemCounts;
  options?: BackupOptions;
  fileSize?: number | string;
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
  private nativeClient: WebDAVNativeClient | null = null;
  private config: WebDAVConfig | null = null;
  private useNative: boolean = true; // 优先使用Native客户端
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
    
    // 尝试初始化Native客户端
    logger.info(TAG, `配置WebDAV: useNative=${this.useNative}, nativeAvailable=${isNativeModuleAvailable()}`);
    if (this.useNative && isNativeModuleAvailable()) {
      try {
        const nativeConfig: WebDAVNativeConfig = {
          serverUrl: config.serverUrl,
          username: config.username,
          password: config.password,
          basePath: config.basePath,
          timeoutMs: 30000,
          verifySSL: config.verifySSL !== false
        };
        this.nativeClient = new WebDAVNativeClient(nativeConfig);
        const initResult = await this.nativeClient.initialize();
        
        if (initResult) {
          // 测试Native连接
          const testResult = await this.nativeClient.testConnection();
          if (testResult.success) {
            logger.info(TAG, 'WebDAV Native客户端配置成功');
            // 预创建ArkTS客户端作为降级兜底，避免Native异常时无可用通道
            this.client = new WebDAVClient(config);
            // 确保备份目录存在
            await this.ensureBackupDirectory();
            return;
          } else {
            logger.warn(TAG, `Native连接测试失败: ${testResult.message}，回退到ArkTS客户端`);
          }
        } else {
          logger.warn(TAG, 'Native客户端初始化失败，回退到ArkTS客户端');
        }
      } catch (e) {
        logger.warn(TAG, `Native客户端异常: ${e}，回退到ArkTS客户端`);
      }
      this.nativeClient = null;
    }
    
    // 回退到ArkTS客户端
    this.client = new WebDAVClient(config);
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
    return (this.client !== null || this.nativeClient !== null) && this.config !== null;
  }

  /**
   * 检查是否使用Native客户端
   */
  isUsingNative(): boolean {
    return this.nativeClient !== null;
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
    if (!this.client && !this.nativeClient) {
      const errorMsg = 'WebDAV未配置';
      throw new Error(errorMsg);
    }
    if (this.syncStatus.isUploading || this.syncStatus.isDownloading) {
      throw new Error('同步任务正在执行，请稍后重试');
    }

    try {
      this.syncStatus.isUploading = true;
      this.syncStatus.uploadProgress = 0;
      this.syncStatus.error = undefined;

      const fileName = this.sanitizeBackupFileName(localBackupPath.split('/').pop() || 'backup.mxbak');
      const remotePath = this.buildBackupRemotePath(fileName);

      logger.info(TAG, `开始上传备份: ${fileName}`);

      // 获取文件大小
      const stat = SafeFileUtils.statSyncStrict(localBackupPath);
      const fileSize = stat.size;

      // 优先使用Native客户端
      if (this.nativeClient) {
        const result = await this.nativeClient.uploadFile(localBackupPath, remotePath);
        if (!result.success) {
          logger.warn(TAG, `Native上传失败，尝试ArkTS回退: ${result.message}`);
          if (this.client) {
            this.ensureArkTSFallbackFileSize(fileSize, '上传');
            await this.client.upload(localBackupPath, remotePath, (progress) => {
              this.syncStatus.uploadProgress = progress;
            });
          } else {
            throw new Error(result.message);
          }
        } else {
          this.syncStatus.uploadProgress = 100;
        }
      } else if (this.client) {
        this.ensureArkTSFallbackFileSize(fileSize, '上传');
        await this.client.upload(localBackupPath, remotePath, (progress) => {
          this.syncStatus.uploadProgress = progress;
        });
      }

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
      throw new Error(String(error));
    } finally {
      this.syncStatus.isUploading = false;
      this.syncStatus.uploadProgress = 0;
    }
  }

  /**
   * 从云端下载备份
   */
  async downloadBackup(remoteBackupInfo: RemoteBackupInfo): Promise<string> {
    if (!this.client && !this.nativeClient) {
      const errorMsg = 'WebDAV未配置';
      throw new Error(errorMsg);
    }
    if (this.syncStatus.isUploading || this.syncStatus.isDownloading) {
      throw new Error('同步任务正在执行，请稍后重试');
    }

    try {
      this.syncStatus.isDownloading = true;
      this.syncStatus.downloadProgress = 0;
      this.syncStatus.error = undefined;

      const backupsDir = `${this.sandboxManager.getDirectory('files')}/backups`;
      if (!await this.sandboxManager.exists(backupsDir)) {
        await this.sandboxManager.createDirectory(backupsDir);
      }

      const safeFileName = this.sanitizeBackupFileName(remoteBackupInfo.fileName);
      const localPath = `${backupsDir}/${safeFileName}`;

      logger.info(TAG, `开始下载备份: ${safeFileName}`);

      // 优先使用Native客户端
      const safeRemotePath = this.buildBackupRemotePath(safeFileName);

      if (this.nativeClient) {
        const result = await this.nativeClient.downloadFile(safeRemotePath, localPath);
        if (!result.success) {
          logger.warn(TAG, `Native下载失败，尝试ArkTS回退: ${result.message}`);
          if (this.client) {
            this.ensureArkTSFallbackFileSize(remoteBackupInfo.size, '下载');
            await this.client.download(safeRemotePath, localPath, (progress) => {
              this.syncStatus.downloadProgress = progress;
            });
          } else {
            throw new Error(result.message);
          }
        } else {
          this.syncStatus.downloadProgress = 100;
        }
      } else if (this.client) {
        this.ensureArkTSFallbackFileSize(remoteBackupInfo.size, '下载');
        await this.client.download(safeRemotePath, localPath, (progress) => {
          this.syncStatus.downloadProgress = progress;
        });
      }

      this.syncStatus.lastSyncTime = Date.now();
      logger.info(TAG, `备份下载成功: ${safeFileName}`);

      return localPath;
    } catch (error) {
      this.syncStatus.error = String(error);
      logger.error(TAG, `下载备份失败: ${error}`);
      throw new Error(String(error));
    } finally {
      this.syncStatus.isDownloading = false;
      this.syncStatus.downloadProgress = 0;
    }
  }

  /**
   * 检查索引文件是否存在
   */
  async checkIndexExists(): Promise<boolean> {
    if (!this.client && !this.nativeClient) {
      return false;
    }

    try {
      const indexPath = `backups/${BACKUP_INDEX_FILE}`;
      let content: string = '';
      
      if (this.nativeClient) {
        content = await this.nativeClient.getFileContents(indexPath);
      } else if (this.client) {
        const result = await this.client.getFileContents(indexPath, 'string');
        content = typeof result === 'string' ? result : '';
      }
      
      if (content.trim().length > 0) {
        // 验证是否是有效的JSON
        const parsed = this.normalizeBackupIndex(SafeUtils.parseObj<RawBackupIndex>(content));
        logger.info(TAG, `索引文件存在，包含 ${parsed.backups.length} 个备份`);
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
    if (!this.client && !this.nativeClient) {
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
    if (!this.client && !this.nativeClient) {
      return { version: 1, lastUpdated: 0, backups: [] };
    }

    try {
      const indexPath = `backups/${BACKUP_INDEX_FILE}`;
      let content: string = '';
      
      if (this.nativeClient) {
        content = await this.nativeClient.getFileContents(indexPath);
      } else if (this.client) {
        const result = await this.client.getFileContents(indexPath, 'string');
        content = typeof result === 'string' ? result : '';
      }
      
      if (content.trim()) {
        const index = this.normalizeBackupIndex(SafeUtils.parseObj<RawBackupIndex>(content));
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
    if (!this.client && !this.nativeClient) {
      throw new Error('WebDAV未配置');
    }

    try {
      index.lastUpdated = Date.now();
      const indexPath = `backups/${BACKUP_INDEX_FILE}`;
      const content = JSON.stringify(index, null, 2);
      
      if (this.nativeClient) {
        const result = await this.nativeClient.putFileContents(indexPath, content);
        if (!result.success) {
          throw new Error(result.message);
        }
      } else if (this.client) {
        await this.client.putFileContents(indexPath, content);
      }
      logger.info(TAG, `备份索引已保存，包含 ${index.backups.length} 个备份`);
    } catch (error) {
      logger.error(TAG, `保存备份索引失败: ${error}`);
      throw new Error(String(error));
    }
  }

  /**
   * 添加备份到索引
   */
  private async addToBackupIndex(backupInfo: RemoteBackupInfo): Promise<void> {
    const index = await this.readBackupIndex();
    
    // 检查是否已存在
    const safeBackupInfo: RemoteBackupInfo = {
      fileName: this.sanitizeBackupFileName(backupInfo.fileName),
      remotePath: this.buildBackupRemotePath(backupInfo.fileName),
      size: backupInfo.size,
      lastModified: backupInfo.lastModified,
      metadata: backupInfo.metadata
    };

    const existingIndex = index.backups.findIndex(b => this.sanitizeBackupFileName(b.fileName) === safeBackupInfo.fileName);
    if (existingIndex >= 0) {
      index.backups[existingIndex] = safeBackupInfo;
    } else {
      index.backups.push(safeBackupInfo);
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
    const safeFileName = this.sanitizeBackupFileName(fileName);
    index.backups = index.backups.filter(b => this.sanitizeBackupFileName(b.fileName) !== safeFileName);
    await this.saveBackupIndex(index);
  }

  /**
   * 列出云端所有备份（从索引文件读取）
   */
  async listRemoteBackups(): Promise<RemoteBackupInfo[]> {
    if (!this.client && !this.nativeClient) {
      const errorMsg = 'WebDAV未配置';
      throw new Error(errorMsg);
    }

    try {
      const index = await this.readBackupIndex();
      logger.info(TAG, `找到 ${index.backups.length} 个云端备份`);
      const safeBackups: RemoteBackupInfo[] = [];
      for (const backup of index.backups) {
        const safeBackup: RemoteBackupInfo = {
          fileName: this.sanitizeBackupFileName(backup.fileName),
          remotePath: this.buildBackupRemotePath(backup.fileName),
          size: backup.size,
          lastModified: backup.lastModified,
          metadata: backup.metadata
        };
        safeBackups.push(safeBackup);
      }
      return safeBackups;
    } catch (error) {
      logger.error(TAG, `列出云端备份失败: ${error}`);
      return [];
    }
  }

  /**
   * 删除云端备份
   */
  async deleteRemoteBackup(remoteBackupInfo: RemoteBackupInfo): Promise<void> {
    if (!this.client && !this.nativeClient) {
      const errorMsg = 'WebDAV未配置';
      throw new Error(errorMsg);
    }

    try {
      const safeFileName = this.sanitizeBackupFileName(remoteBackupInfo.fileName);
      const safeRemotePath = this.buildBackupRemotePath(remoteBackupInfo.fileName);
      if (this.nativeClient) {
        const result = await this.nativeClient.deleteFile(safeRemotePath);
        if (!result.success) {
          throw new Error(result.message);
        }
      } else if (this.client) {
        await this.client.delete(safeRemotePath);
      }
      
      // 从索引中移除
      await this.removeFromBackupIndex(remoteBackupInfo.fileName);
      
      logger.info(TAG, `删除云端备份成功: ${safeFileName}`);
    } catch (error) {
      logger.error(TAG, `删除云端备份失败: ${error}`);
      throw new Error(String(error));
    }
  }

  /**
   * 自动备份（上传最新的本地备份）
   */
  async autoBackup(): Promise<void> {
    if (!this.client && !this.nativeClient) {
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
      const backupFiles = files.filter(f => f.endsWith('.mxbackup') || f.endsWith('.mxbak'));
      
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
      throw new Error(String(error));
    }
  }

  /**
   * 清理旧备份（保留最近N个）
   */
  async cleanOldBackups(keepCount: number = 5): Promise<void> {
    if (!this.client && !this.nativeClient) {
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
      throw new Error(String(error));
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
   * Native客户端支持MKCOL方法，可以直接创建目录
   */
  private async ensureBackupDirectory(): Promise<void> {
    if (!this.client && !this.nativeClient) return;

    try {
      // Native客户端支持直接创建目录
      if (this.nativeClient) {
        const existsResult = await this.nativeClient.exists('backups');
        if (!existsResult) {
          const createResult = await this.nativeClient.createDirectory('backups');
          if (createResult.success) {
            logger.info(TAG, '备份目录创建成功');
          } else {
            logger.info(TAG, '备份目录可能已存在或将在上传时自动创建');
          }
        }
      } else if (this.client) {
        const exists = await this.client.exists('backups');
        if (!exists) {
          logger.info(TAG, '备份目录不存在，将在上传时自动创建');
        }
      }
    } catch (error) {
      // 忽略检查错误，上传时会自动创建目录
      logger.warn(TAG, `检查备份目录时出错: ${error}`);
    }
  }

  private ensureArkTSFallbackFileSize(size: number, operationName: string): void {
    if (size > ARKTS_WEBDAV_FALLBACK_MAX_FILE_BYTES) {
      throw new Error(`ArkTS WebDAV回退客户端不支持${operationName}超过 ${ARKTS_WEBDAV_FALLBACK_MAX_FILE_MIB} MiB 的备份文件，请使用Native WebDAV客户端`);
    }
  }

  private normalizeBackupIndex(rawIndex: RawBackupIndex): BackupIndex {
    const backups: RemoteBackupInfo[] = [];
    const rawBackups = rawIndex.backups;
    if (Array.isArray(rawBackups)) {
      for (const rawBackup of rawBackups) {
        const backup = this.normalizeRemoteBackupInfo(rawBackup);
        if (backup) {
          backups.push(backup);
        }
      }
    }

    const index: BackupIndex = {
      version: Number(rawIndex.version || 1),
      lastUpdated: Number(rawIndex.lastUpdated || 0),
      backups: backups
    };
    return index;
  }

  private normalizeRemoteBackupInfo(rawBackup: RawRemoteBackupInfo): RemoteBackupInfo | null {
    const baseName = this.getBackupBaseName(rawBackup.fileName || '');
    if (!baseName.endsWith('.mxbak') && !baseName.endsWith('.mxbackup')) {
      return null;
    }
    const safeFileName = this.sanitizeBackupFileName(baseName);
    const metadata = this.normalizeBackupMetadata(rawBackup.metadata);
    const backup: RemoteBackupInfo = {
      fileName: safeFileName,
      remotePath: this.buildBackupRemotePath(safeFileName),
      size: Number(rawBackup.size || 0),
      lastModified: Number(rawBackup.lastModified || 0)
    };
    if (metadata) {
      backup.metadata = metadata;
    }
    return backup;
  }

  private normalizeBackupMetadata(rawMetadata?: RawBackupMetadata): BackupMetadata | undefined {
    if (!rawMetadata) {
      return undefined;
    }
    if (!rawMetadata.itemCounts || !rawMetadata.options) {
      return undefined;
    }

    const metadata: BackupMetadata = {
      version: rawMetadata.version || '',
      appVersion: rawMetadata.appVersion || '',
      timestamp: Number(rawMetadata.timestamp || 0),
      deviceInfo: rawMetadata.deviceInfo,
      itemCounts: rawMetadata.itemCounts,
      options: rawMetadata.options,
      fileSize: Number(rawMetadata.fileSize || 0)
    };
    return metadata;
  }

  private sanitizeBackupFileName(fileName: string): string {
    const baseName = this.getBackupBaseName(fileName);
    let safeName = baseName.replace(/[\\/:*?"<>|]/g, '_').trim();
    if (safeName.length === 0) {
      safeName = `backup_${Date.now()}.mxbak`;
    }
    if (!safeName.endsWith('.mxbak') && !safeName.endsWith('.mxbackup')) {
      safeName = `${safeName}.mxbak`;
    }
    return safeName;
  }

  private getBackupBaseName(fileName: string): string {
    const slashParts = fileName.replace(/\\/g, '/').split('/');
    return slashParts.length > 0 ? slashParts[slashParts.length - 1].trim() : '';
  }

  private buildBackupRemotePath(fileName: string): string {
    return `backups/${this.sanitizeBackupFileName(fileName)}`;
  }
}

export function getWebDAVBackupManager(): WebDAVBackupManager {
  return WebDAVBackupManager.getInstance();
}
