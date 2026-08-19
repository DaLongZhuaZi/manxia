import { SafeFileUtils } from 'manxia_core/src/main/ets/Utils/SafeFileUtils';
import { SafeUtils } from 'manxia_core/src/main/ets/Utils/SafeUtils';
import { common } from '@kit.AbilityKit';
import { preferences } from '@kit.ArkData';
import { cryptoFramework } from '@kit.CryptoArchitectureKit';
import { fileUri } from '@kit.CoreFileKit';
import fs from '@ohos.file.fs';
import { logger } from 'manxia_core/src/main/ets/Utils/Logger';
import { sanitizeFileName } from 'manxia_core/src/main/ets/Utils/FileNameUtils';
import {
  aes256GcmEncrypt,
  aes256GcmDecrypt,
  generateAes256Key,
  exportSymKeyToBase64,
  importSymKeyFromBase64
} from 'manxia_core/src/main/ets/Utils/CryptoUtils';
import { FTPConfig, FTPFileInfo, FTPListResult, FTPNativeClient } from '../FTP/FTPNativeClient';
import {
  SMBClientAdapter,
  SMBDirectoryEntry,
  SMBDirectoryListResult,
  SMBOperationResult
} from './SMBClientAdapter';
import {
  WebDAVNativeClient,
  WebDAVNativeConfig,
  WebDAVNativeFileInfo,
  WebDAVNativeListResult
} from '../WebDAV/WebDAVNativeClient';
import { WebDAVClient, WebDAVConfig, WebDAVFile } from '../WebDAV/WebDAVClient';
import { SandboxManager } from 'manxia_core/src/main/ets/Framework/Storage/SandboxManager';
import DownloadDirManager from '../Storage/DownloadDirManager';
import {
  NetworkFolderBrowseResult,
  NetworkFolderCacheDetail,
  NetworkFolderDirectoryCacheDetail,
  NetworkFolderDownloadCacheDetail,
  NetworkFolderCacheStats,
  NetworkFolderConnection,
  NetworkFolderDownloadResult,
  NetworkFolderEntry,
  NetworkFolderImportCategory,
  inferNetworkFolderImportCategory,
  joinRelativeNetworkFolderPath,
  normalizeConnectionBasePath,
  normalizeRelativeNetworkFolderPath
} from '../../Models/NetworkFolderModels';

const TAG = 'NetworkFolderManager';

const PREF_NAME = 'network_folder_preferences';
const CONNECTIONS_KEY = 'connections';
const LAST_CONNECTION_KEY = 'last_connection_id';
const LAST_PATHS_KEY = 'last_paths';
const FAVORITE_PATHS_KEY = 'favorite_paths';
const STATE_FILE_NAME = 'network_folder_state.json';
const STATE_VERSION = 1;
const DIRECTORY_CACHE_FRESH_TTL_MS = 5 * 60 * 1000;
const DIRECTORY_CACHE_RETENTION_MS = 2 * 24 * 60 * 60 * 1000;
const DIRECTORY_CACHE_MAX_ENTRIES = 120;
const DOWNLOAD_CACHE_MAX_AGE_MS = 7 * 24 * 60 * 60 * 1000;
const DOWNLOAD_CACHE_MAX_BYTES = 1024 * 1024 * 1024;
const ENCRYPTION_KEY_PREF = '__nf_enc_key_v1';
const PASSWORD_ENCRYPTED_PREFIX = 'enc_v1:';

interface CachedDirectoryEntry {
  connectionId: string;
  relativePath: string;
  fetchedAt: number;
  entries: NetworkFolderEntry[];
}

interface CachedDownloadEntry {
  connectionId: string;
  relativePath: string;
  localPath: string;
  fileName: string;
  size: number;
  versionTag: string;
  cachedAt: number;
  lastAccessedAt: number;
  importCategory: NetworkFolderImportCategory;
}

interface PersistedNetworkFolderState {
  version: number;
  directoryCache: CachedDirectoryEntry[];
  downloadCache: CachedDownloadEntry[];
  updatedAt: number;
}

interface ParsedPreferencesConnections {
  connections: NetworkFolderConnection[];
  lastConnectionId: string;
  lastPaths: Map<string, string>;
}

interface NetworkFolderConnectionTestResult {
  success: boolean;
  message: string;
}

interface NetworkFolderEntryOptions {
  name: string;
  relativePath: string;
  actualPath: string;
  size: number;
  isDirectory: boolean;
  lastModified: number;
  etag: string;
  contentType: string;
  permissions: string;
}

interface PersistedLastPathEntry {
  connectionId: string;
  relativePath: string;
}

interface FavoritePathEntry {
  connectionId: string;
  relativePath: string;
}

interface CachedDirectoryPair {
  key: string;
  value: CachedDirectoryEntry;
}

interface CachedDownloadPair {
  key: string;
  value: CachedDownloadEntry;
}

export class NetworkFolderManager {
  private static instance: NetworkFolderManager | null = null;

  private context: common.UIAbilityContext | null = null;
  private pref: preferences.Preferences | null = null;
  private sandboxManager: SandboxManager = SandboxManager.getInstance();
  private downloadDirManager = DownloadDirManager;
  private smbClient: SMBClientAdapter = new SMBClientAdapter();
  private initialized: boolean = false;

  private connections: NetworkFolderConnection[] = [];
  private lastConnectionId: string = '';
  private lastPaths: Map<string, string> = new Map<string, string>();
  private directoryCache: Map<string, CachedDirectoryEntry> = new Map<string, CachedDirectoryEntry>();
  private downloadCache: Map<string, CachedDownloadEntry> = new Map<string, CachedDownloadEntry>();
  private favoritePaths: Map<string, Set<string>> = new Map<string, Set<string>>();
  private encryptionKey: cryptoFramework.SymKey | null = null;

  private rootDir: string = '';
  private downloadsDir: string = '';
  private stateFilePath: string = '';

  private constructor() {}

  public static getInstance(): NetworkFolderManager {
    if (!NetworkFolderManager.instance) {
      NetworkFolderManager.instance = new NetworkFolderManager();
    }
    return NetworkFolderManager.instance;
  }

  public async initialize(context: common.UIAbilityContext): Promise<void> {
    if (this.initialized && this.context === context) {
      return;
    }

    logger.info(TAG, '开始初始化网络文件夹管理器');
    this.context = context;
    await this.sandboxManager.initialize(context);
    this.downloadDirManager.setContext(context);

    this.rootDir = `${this.sandboxManager.getDirectory('files')}/network_folder`;
    this.downloadsDir = '';
    this.stateFilePath = `${this.rootDir}/${STATE_FILE_NAME}`;

    this.ensureDir(this.rootDir);
    this.tryResolveDownloadCacheRootFromManager();

    this.pref = await preferences.getPreferences(context, { name: PREF_NAME });

    await this.loadPreferencesState();
    this.loadPersistedState();
    await this.pruneCaches();

    this.initialized = true;
    logger.info(TAG, '网络文件夹管理器初始化完成');
  }

  public getConnections(): NetworkFolderConnection[] {
    const sorted: NetworkFolderConnection[] = [];
    for (const item of this.connections) {
      sorted.push(this.cloneConnection(item));
    }
    sorted.sort((left: NetworkFolderConnection, right: NetworkFolderConnection) => right.lastUsedAt - left.lastUsedAt);
    return sorted;
  }

  public getConnection(connectionId: string): NetworkFolderConnection | undefined {
    return this.connections.find((item: NetworkFolderConnection) => item.id === connectionId);
  }

  public getLastConnectionId(): string {
    return this.lastConnectionId;
  }

  public getLastPath(connectionId: string): string {
    return this.lastPaths.get(connectionId) ?? '/';
  }

  public async saveConnection(connection: NetworkFolderConnection): Promise<void> {
    this.ensureInitialized();
    const normalized = this.normalizeConnection(connection);
    logger.info(TAG, `保存网络连接配置：${normalized.name} (${normalized.protocol})`);
    const index = this.connections.findIndex((item: NetworkFolderConnection) => item.id === normalized.id);
    let shouldResetRuntimeState = false;
    if (index >= 0) {
      const existing = this.connections[index];
      const updatedConnection = this.cloneConnection(normalized);
      updatedConnection.createdAt = existing.createdAt;
      updatedConnection.lastUsedAt = existing.lastUsedAt;
      shouldResetRuntimeState = this.shouldResetConnectionRuntimeState(existing, updatedConnection);
      this.connections[index] = updatedConnection;
    } else {
      this.connections.push(normalized);
    }

    if (shouldResetRuntimeState) {
      logger.info(TAG, `连接关键配置已变更，重置缓存与浏览状态：${normalized.id}`);
      await this.clearCacheForConnection(normalized.id);
      this.lastPaths.set(normalized.id, '/');
      if (this.lastConnectionId === normalized.id) {
        this.lastConnectionId = normalized.id;
      }
      await this.persistLastState();
    }

    await this.persistConnections();
    logger.info(TAG, `网络连接配置已保存：${normalized.name}`);
  }

  public async deleteConnection(connectionId: string): Promise<void> {
    this.ensureInitialized();
    logger.info(TAG, `删除网络连接：${connectionId}`);
    this.connections = this.connections.filter((item: NetworkFolderConnection) => item.id !== connectionId);
    this.lastPaths.delete(connectionId);
    this.favoritePaths.delete(connectionId);
    if (this.lastConnectionId === connectionId) {
      this.lastConnectionId = '';
    }
    await this.clearCacheForConnection(connectionId);
    await this.persistConnections();
    await this.persistLastState();
    logger.info(TAG, `网络连接已删除：${connectionId}`);
  }

  public isFavoriteFolder(connectionId: string, path: string): boolean {
    const normalizedPath = normalizeRelativeNetworkFolderPath(path);
    const pathSet = this.favoritePaths.get(connectionId);
    return pathSet ? pathSet.has(normalizedPath) : false;
  }

  public async toggleFavoriteFolder(connectionId: string, path: string): Promise<boolean> {
    this.ensureInitialized();
    const normalizedPath = normalizeRelativeNetworkFolderPath(path);
    let pathSet = this.favoritePaths.get(connectionId);
    if (!pathSet) {
      pathSet = new Set<string>();
      this.favoritePaths.set(connectionId, pathSet);
    }

    let newState: boolean;
    if (pathSet.has(normalizedPath)) {
      pathSet.delete(normalizedPath);
      newState = false;
      logger.info(TAG, `取消收藏文件夹：connection=${connectionId}，path=${normalizedPath}`);
    } else {
      pathSet.add(normalizedPath);
      newState = true;
      logger.info(TAG, `收藏文件夹：connection=${connectionId}，path=${normalizedPath}`);
    }

    await this.persistFavoritePaths();
    return newState;
  }

  public getFavoriteFolders(connectionId: string): string[] {
    const pathSet = this.favoritePaths.get(connectionId);
    if (!pathSet || pathSet.size === 0) {
      return [];
    }
    const result: string[] = [];
    pathSet.forEach((path: string) => {
      result.push(path);
    });
    return result;
  }

  public async testConnection(connection: NetworkFolderConnection): Promise<NetworkFolderConnectionTestResult> {
    this.ensureInitialized();
    logger.info(TAG, `开始测试网络连接：${connection.name} (${connection.protocol})`);

    if (connection.protocol === 'webdav') {
      const client = new WebDAVNativeClient(this.buildWebDAVConfig(connection));
      try {
        const result = await client.testConnection();
        const testResult: NetworkFolderConnectionTestResult = {
          success: result.success,
          message: result.message
        };
        return testResult;
      } finally {
        client.destroy();
      }
    }

    if (connection.protocol === 'ftp' || connection.protocol === 'ftps' || connection.protocol === 'sftp') {
      const client = new FTPNativeClient(this.buildFTPConfig(connection));
      try {
        const result = await client.testConnection();
        if (!result.success) {
          return result;
        }
        const listResult = await client.listWithResult(this.resolveActualPath(connection, '/'));
        if (listResult.success) {
          const successResult: NetworkFolderConnectionTestResult = {
            success: true,
            message: '连接成功'
          };
          return successResult;
        }
        const failureResult: NetworkFolderConnectionTestResult = {
          success: false,
          message: listResult.message || '无法访问远程基准目录'
        };
        return failureResult;
      } finally {
        client.destroy();
      }
    }

    const smbResult: SMBOperationResult = await this.smbClient.testConnection(connection);
    const testResult: NetworkFolderConnectionTestResult = {
      success: smbResult.success,
      message: smbResult.message
    };
    return testResult;
  }

  public async browseDirectory(
    connectionId: string,
    relativePath: string = '/',
    forceRefresh: boolean = false
  ): Promise<NetworkFolderBrowseResult> {
    this.ensureInitialized();

    const connection = this.requireConnection(connectionId);
    const normalizedPath = normalizeRelativeNetworkFolderPath(relativePath);
    logger.info(TAG, `浏览远程目录：${connection.name} ${normalizedPath}，强制刷新=${forceRefresh}`);
    const cacheKey = this.buildDirectoryCacheKey(connectionId, normalizedPath);
    const now = Date.now();
    const cachedEntry = this.directoryCache.get(cacheKey);

    if (!forceRefresh && cachedEntry && now - cachedEntry.fetchedAt <= DIRECTORY_CACHE_FRESH_TTL_MS) {
      await this.markConnectionUsed(connectionId, normalizedPath);
      return {
        success: true,
        message: '已从缓存加载目录',
        entries: this.decorateEntriesWithCache(connectionId, cachedEntry.entries),
        fromCache: true,
        stale: false,
        loadedAt: cachedEntry.fetchedAt
      };
    }

    let remoteResult: NetworkFolderBrowseResult;
    if (connection.protocol === 'webdav') {
      remoteResult = await this.browseWebDAV(connection, normalizedPath);
    } else if (connection.protocol === 'ftp' || connection.protocol === 'ftps' || connection.protocol === 'sftp') {
      remoteResult = await this.browseFTP(connection, normalizedPath);
    } else {
      remoteResult = await this.browseSMB(connection, normalizedPath);
    }

    if (remoteResult.success) {
      const cacheEntries = this.cleanEntriesForCache(remoteResult.entries);
      this.directoryCache.set(cacheKey, {
        connectionId: connectionId,
        relativePath: normalizedPath,
        fetchedAt: remoteResult.loadedAt,
        entries: cacheEntries
      });
      this.limitDirectoryCacheEntries();
      await this.markConnectionUsed(connectionId, normalizedPath);
      await this.persistCacheState();
      return {
        success: remoteResult.success,
        message: remoteResult.message,
        entries: this.decorateEntriesWithCache(connectionId, cacheEntries),
        fromCache: false,
        stale: false,
        loadedAt: remoteResult.loadedAt
      };
    }

    if (cachedEntry && now - cachedEntry.fetchedAt <= DIRECTORY_CACHE_RETENTION_MS) {
      await this.markConnectionUsed(connectionId, normalizedPath);
      return {
        success: true,
        message: remoteResult.message || '远程目录访问失败，已回退到缓存数据',
        entries: this.decorateEntriesWithCache(connectionId, cachedEntry.entries),
        fromCache: true,
        stale: true,
        loadedAt: cachedEntry.fetchedAt
      };
    }

    return remoteResult;
  }

  public async downloadFileToCache(
    connectionId: string,
    entry: NetworkFolderEntry
  ): Promise<NetworkFolderDownloadResult> {
    this.ensureInitialized();

    if (entry.isDirectory) {
      return this.buildDownloadFailure('目录不支持直接缓存');
    }

    const connection = this.requireConnection(connectionId);
    logger.info(TAG, `开始缓存远程文件：${connection.name} ${entry.relativePath}`);
    const normalizedRelativePath = normalizeRelativeNetworkFolderPath(entry.relativePath);
    const downloadKey = this.buildDownloadCacheKey(connectionId, normalizedRelativePath);
    const versionTag = entry.versionTag || this.buildVersionTag(entry);
    const cachedEntry = this.downloadCache.get(downloadKey);
    const now = Date.now();

    if (cachedEntry && cachedEntry.versionTag === versionTag && this.fileExists(cachedEntry.localPath)) {
      cachedEntry.lastAccessedAt = now;
      this.tryResolveDownloadCacheRootFromManager();
      const preferredCacheDir = this.getConnectionFileCacheDir(connectionId, normalizedRelativePath);
      if (preferredCacheDir.length > 0) {
        this.ensureDir(preferredCacheDir);
        const preferredPath = `${preferredCacheDir}/${this.buildDownloadFileName(entry.name)}`;
        if (preferredPath !== cachedEntry.localPath) {
          try {
            if (this.fileExists(preferredPath)) {
              this.deleteFileIfExists(cachedEntry.localPath);
              cachedEntry.localPath = preferredPath;
            } else {
              SafeFileUtils.renameSync(cachedEntry.localPath, preferredPath);
              cachedEntry.localPath = preferredPath;
            }
            logger.info(TAG, `已将缓存文件路径更新为原文件名策略：${entry.name}`);
          } catch (error) {
            logger.warn(TAG, `迁移缓存文件名失败，继续使用旧路径：${String(error)}`);
          }
        }
      }
      this.downloadCache.set(downloadKey, cachedEntry);
      await this.markConnectionUsed(connectionId, this.getParentRelativePath(normalizedRelativePath));
      await this.persistCacheState();
      return {
        success: true,
        message: '已复用缓存文件',
        localPath: cachedEntry.localPath,
        fileUri: fileUri.getUriFromPath(cachedEntry.localPath),
        reusedCache: true,
        importCategory: entry.importCategory
      };
    }

    try {
      await this.ensureDownloadCacheRootReady();
    } catch (error) {
      return this.buildDownloadFailure(`准备 Download 应用目录失败：${String(error)}`);
    }
    const connectionDir = this.getConnectionDownloadsDir(connectionId);
    if (connectionDir.length === 0) {
      return this.buildDownloadFailure('Download 应用目录未就绪，无法缓存远程文件');
    }
    this.ensureDir(connectionDir);

    const fileCacheDir = this.getConnectionFileCacheDir(connectionId, normalizedRelativePath);
    this.ensureDir(fileCacheDir);
    const finalPath = `${fileCacheDir}/${this.buildDownloadFileName(entry.name)}`;
    const tempPath = `${finalPath}.part`;
    this.deleteFileIfExists(tempPath);

    let downloadMessage = '远程文件下载完成';
    let downloadSuccess = false;

    try {
      if (connection.protocol === 'webdav') {
        const client = new WebDAVNativeClient(this.buildWebDAVConfig(connection));
        try {
          const result = await client.downloadFile(this.resolveWebDAVClientPath(normalizedRelativePath), tempPath);
          downloadSuccess = result.success;
          downloadMessage = result.message || downloadMessage;
        } finally {
          client.destroy();
        }
      } else if (connection.protocol === 'ftp' || connection.protocol === 'ftps' || connection.protocol === 'sftp') {
        const client = new FTPNativeClient(this.buildFTPConfig(connection));
        try {
          const result = await client.download(this.resolveActualPath(connection, normalizedRelativePath), tempPath);
          downloadSuccess = result.success;
          downloadMessage = result.message || downloadMessage;
        } finally {
          client.destroy();
        }
      } else {
        const result = await this.smbClient.downloadFile(connection, normalizedRelativePath, tempPath);
        downloadSuccess = result.success;
        downloadMessage = result.message || downloadMessage;
      }

      if (!downloadSuccess) {
        this.deleteFileIfExists(tempPath);
        return this.buildDownloadFailure(downloadMessage);
      }

      if (!this.fileExists(tempPath)) {
        return this.buildDownloadFailure('文件下载完成，但缓存文件不存在');
      }

      if (this.fileExists(finalPath)) {
        this.deleteFileIfExists(finalPath);
      }
      SafeFileUtils.renameSync(tempPath, finalPath);
      const stat = SafeFileUtils.statSync(finalPath);
      const nextCachedEntry: CachedDownloadEntry = {
        connectionId: connectionId,
        relativePath: normalizedRelativePath,
        localPath: finalPath,
        fileName: entry.name,
        size: Number(stat.size) || entry.size || 0,
        versionTag: versionTag,
        cachedAt: now,
        lastAccessedAt: now,
        importCategory: entry.importCategory
      };

      if (cachedEntry && cachedEntry.localPath !== finalPath) {
        this.deleteFileIfExists(cachedEntry.localPath);
      }

      this.downloadCache.set(downloadKey, nextCachedEntry);
      await this.markConnectionUsed(connectionId, this.getParentRelativePath(normalizedRelativePath));
      await this.pruneCaches();
      await this.persistCacheState();

      return {
        success: true,
        message: downloadMessage,
        localPath: finalPath,
        fileUri: fileUri.getUriFromPath(finalPath),
        reusedCache: false,
        importCategory: entry.importCategory
      };
    } catch (error) {
      this.deleteFileIfExists(tempPath);
      return this.buildDownloadFailure(`远程文件下载失败：${String(error)}`);
    }
  }

  public getCacheStats(connectionId?: string): NetworkFolderCacheStats {
    this.ensureInitialized();

    const filterConnectionId = connectionId?.trim() ?? '';
    let directoryCount = 0;
    let fileCount = 0;
    let totalBytes = 0;

    for (const item of this.directoryCache.values()) {
      if (!filterConnectionId || item.connectionId === filterConnectionId) {
        directoryCount++;
      }
    }

    for (const item of this.downloadCache.values()) {
      if (!filterConnectionId || item.connectionId === filterConnectionId) {
        fileCount++;
        totalBytes += item.size;
      }
    }

    return {
      directoryCount: directoryCount,
      fileCount: fileCount,
      totalBytes: totalBytes
    };
  }

  public getCacheDetail(connectionId?: string): NetworkFolderCacheDetail {
    this.ensureInitialized();

    const filterConnectionId = connectionId?.trim() ?? '';
    const directories: NetworkFolderDirectoryCacheDetail[] = [];
    const files: NetworkFolderDownloadCacheDetail[] = [];

    for (const item of this.directoryCache.values()) {
      if (filterConnectionId.length > 0 && item.connectionId !== filterConnectionId) {
        continue;
      }
      directories.push({
        connectionId: item.connectionId,
        relativePath: item.relativePath,
        fetchedAt: item.fetchedAt,
        entryCount: item.entries.length
      });
    }

    for (const item of this.downloadCache.values()) {
      if (filterConnectionId.length > 0 && item.connectionId !== filterConnectionId) {
        continue;
      }
      files.push({
        connectionId: item.connectionId,
        relativePath: item.relativePath,
        localPath: item.localPath,
        fileName: item.fileName,
        size: item.size,
        versionTag: item.versionTag,
        cachedAt: item.cachedAt,
        lastAccessedAt: item.lastAccessedAt,
        importCategory: item.importCategory,
        fileExists: this.fileExists(item.localPath)
      });
    }

    directories.sort((left: NetworkFolderDirectoryCacheDetail, right: NetworkFolderDirectoryCacheDetail) => {
      return right.fetchedAt - left.fetchedAt;
    });
    files.sort((left: NetworkFolderDownloadCacheDetail, right: NetworkFolderDownloadCacheDetail) => {
      return right.lastAccessedAt - left.lastAccessedAt;
    });

    return {
      stats: this.getCacheStats(connectionId),
      directories: directories,
      files: files
    };
  }

  public async deleteCachedFile(connectionId: string, relativePath: string, localPath: string): Promise<boolean> {
    this.ensureInitialized();

    const normalizedConnectionId = connectionId.trim();
    const normalizedRelativePath = normalizeRelativeNetworkFolderPath(relativePath);
    const normalizedLocalPath = localPath.trim();
    logger.info(TAG, `删除文件缓存：connection=${normalizedConnectionId}, path=${normalizedRelativePath}`);

    let removed = false;
    const targetKey = this.buildDownloadCacheKey(normalizedConnectionId, normalizedRelativePath);
    const targetEntry = this.downloadCache.get(targetKey);
    if (targetEntry) {
      this.deleteFileIfExists(targetEntry.localPath);
      this.downloadCache.delete(targetKey);
      removed = true;
    }

    if (!removed && normalizedLocalPath.length > 0) {
      const downloadPairs = this.getDownloadCachePairs();
      for (const pair of downloadPairs) {
        if (pair.value.connectionId !== normalizedConnectionId) {
          continue;
        }
        if (pair.value.localPath === normalizedLocalPath) {
          this.deleteFileIfExists(pair.value.localPath);
          this.downloadCache.delete(pair.key);
          removed = true;
          break;
        }
      }
    }

    if (!removed && normalizedLocalPath.length > 0) {
      this.deleteFileIfExists(normalizedLocalPath);
      logger.warn(TAG, `缓存记录不存在，已尝试删除本地文件：${normalizedLocalPath}`);
    }

    await this.persistCacheState();
    if (removed) {
      logger.info(TAG, `文件缓存删除完成：connection=${normalizedConnectionId}, path=${normalizedRelativePath}`);
    }
    return removed;
  }

  public async clearCacheForConnection(connectionId: string): Promise<void> {
    this.ensureInitialized();
    logger.info(TAG, `清理指定连接缓存：${connectionId}`);

    const directoryKeys: string[] = [];
    const directoryPairs = this.getDirectoryCachePairs();
    for (const pair of directoryPairs) {
      if (pair.value.connectionId === connectionId) {
        directoryKeys.push(pair.key);
      }
    }
    directoryKeys.forEach((key: string) => this.directoryCache.delete(key));

    const downloadKeys: string[] = [];
    const downloadPairs = this.getDownloadCachePairs();
    for (const pair of downloadPairs) {
      if (pair.value.connectionId === connectionId) {
        downloadKeys.push(pair.key);
        this.deleteFileIfExists(pair.value.localPath);
      }
    }
    downloadKeys.forEach((key: string) => this.downloadCache.delete(key));

    const connectionDir = this.getConnectionDownloadsDir(connectionId);
    if (connectionDir.length > 0) {
      this.deleteDirectoryIfExists(connectionDir);
    }
    await this.persistCacheState();
    logger.info(TAG, `指定连接缓存清理完成：${connectionId}`);
  }

  public async clearAllCaches(): Promise<void> {
    this.ensureInitialized();
    logger.info(TAG, '开始清理全部网络文件夹缓存');

    for (const item of this.downloadCache.values()) {
      this.deleteFileIfExists(item.localPath);
    }

    this.directoryCache.clear();
    this.downloadCache.clear();
    if (this.downloadsDir.length > 0) {
      this.deleteDirectoryContents(this.downloadsDir);
    }
    await this.persistCacheState();
    logger.info(TAG, '全部网络文件夹缓存清理完成');
  }

  private async browseWebDAV(
    connection: NetworkFolderConnection,
    relativePath: string
  ): Promise<NetworkFolderBrowseResult> {
    // 优先使用 Native 客户端
    const nativeClient = new WebDAVNativeClient(this.buildWebDAVConfig(connection));
    try {
      const result: WebDAVNativeListResult = await nativeClient.getDirectoryContents(this.resolveWebDAVClientPath(relativePath));
      if (result.success) {
        const entries = this.normalizeWebDAVEntries(connection, relativePath, result.files);
        return {
          success: true,
          message: result.message || `WebDAV 目录加载完成，共 ${entries.length} 项`,
          entries: entries,
          fromCache: false,
          stale: false,
          loadedAt: Date.now()
        };
      }
      // Native 失败，降级到 ArkTS HTTP 客户端
      logger.warn(TAG, `Native WebDAV 失败(${result.message})，降级到 ArkTS HTTP 客户端`);
    } catch (error) {
      logger.warn(TAG, `Native WebDAV 异常(${String(error)})，降级到 ArkTS HTTP 客户端`);
    } finally {
      nativeClient.destroy();
    }

    // 降级：使用纯 ArkTS HTTP 实现
    try {
      const fallbackConfig: WebDAVConfig = {
        serverUrl: connection.serverUrl.trim(),
        username: connection.username,
        password: connection.password,
        basePath: normalizeConnectionBasePath(connection.basePath)
      };
      const fallbackClient = new WebDAVClient(fallbackConfig);
      const webdavPath = this.resolveWebDAVClientPath(relativePath);
      const files: WebDAVFile[] = await fallbackClient.getDirectoryContents(webdavPath);
      const entries = this.normalizeWebDAVFallbackEntries(connection, relativePath, files);
      return {
        success: true,
        message: `WebDAV 目录加载完成(ArkTS HTTP)，共 ${entries.length} 项`,
        entries: entries,
        fromCache: false,
        stale: false,
        loadedAt: Date.now()
      };
    } catch (error) {
      return {
        success: false,
        message: `加载 WebDAV 目录失败：${String(error)}`,
        entries: [],
        fromCache: false,
        stale: false,
        loadedAt: 0
      };
    }
  }

  private async browseFTP(
    connection: NetworkFolderConnection,
    relativePath: string
  ): Promise<NetworkFolderBrowseResult> {
    const protocolLabel = connection.protocol === 'sftp' ? 'SFTP' : 'FTP';
    const client = new FTPNativeClient(this.buildFTPConfig(connection));
    try {
      const result: FTPListResult = await client.listWithResult(this.resolveActualPath(connection, relativePath));
      if (!result.success) {
        return {
          success: false,
          message: result.message || `加载 ${protocolLabel} 目录失败`,
          entries: [],
          fromCache: false,
          stale: false,
          loadedAt: 0
        };
      }

      const entries = this.normalizeFTPEntries(connection, relativePath, result.files);
      return {
        success: true,
        message: result.message || `${protocolLabel} 目录加载完成，共 ${entries.length} 项`,
        entries: entries,
        fromCache: false,
        stale: false,
        loadedAt: Date.now()
      };
    } catch (error) {
      return {
        success: false,
        message: `加载 ${protocolLabel} 目录失败：${String(error)}`,
        entries: [],
        fromCache: false,
        stale: false,
        loadedAt: 0
      };
    } finally {
      client.destroy();
    }
  }

  private async browseSMB(
    connection: NetworkFolderConnection,
    relativePath: string
  ): Promise<NetworkFolderBrowseResult> {
    const result: SMBDirectoryListResult = await this.smbClient.listDirectory(connection, relativePath);
    if (!result.success) {
      return {
        success: false,
        message: result.message || '加载 SMB 目录失败',
        entries: [],
        fromCache: false,
        stale: false,
        loadedAt: 0
      };
    }

    const entries = this.normalizeSMBEntries(connection, relativePath, result.entries);
    return {
      success: true,
      message: result.message || `SMB 目录加载完成，共 ${entries.length} 项`,
      entries: entries,
      fromCache: false,
      stale: false,
      loadedAt: Date.now()
    };
  }

  private normalizeWebDAVEntries(
    connection: NetworkFolderConnection,
    currentRelativePath: string,
    files: WebDAVNativeFileInfo[]
  ): NetworkFolderEntry[] {
    const entries: NetworkFolderEntry[] = [];
    const normalizedCurrentPath = normalizeRelativeNetworkFolderPath(currentRelativePath);

    for (const file of files) {
      const trimmedName = (file.name || '').trim();
      if (!trimmedName || trimmedName === '.' || trimmedName === '..') {
        continue;
      }

      let relativePath = this.normalizeRemoteActualPathToRelative(connection, file.path || '');
      if (relativePath === normalizedCurrentPath) {
        continue;
      }
      if (relativePath === '/') {
        relativePath = joinRelativeNetworkFolderPath(normalizedCurrentPath, trimmedName);
      }

      entries.push(this.createEntry({
        name: trimmedName,
        relativePath: relativePath,
        actualPath: this.resolveActualPath(connection, relativePath),
        size: file.isDirectory ? 0 : (Number(file.size) || 0),
        isDirectory: file.isDirectory,
        lastModified: Number(file.lastModified) || 0,
        etag: file.etag || '',
        contentType: file.contentType || '',
        permissions: ''
      }));
    }

    return this.sortEntries(entries);
  }

  private normalizeWebDAVFallbackEntries(
    connection: NetworkFolderConnection,
    currentRelativePath: string,
    files: WebDAVFile[]
  ): NetworkFolderEntry[] {
    const entries: NetworkFolderEntry[] = [];
    const normalizedCurrentPath = normalizeRelativeNetworkFolderPath(currentRelativePath);

    for (const file of files) {
      const trimmedName = (file.name || '').trim();
      if (!trimmedName || trimmedName === '.' || trimmedName === '..') {
        continue;
      }

      let relativePath = this.normalizeRemoteActualPathToRelative(connection, file.path || '');
      if (relativePath === normalizedCurrentPath) {
        continue;
      }
      if (relativePath === '/') {
        relativePath = joinRelativeNetworkFolderPath(normalizedCurrentPath, trimmedName);
      }

      entries.push(this.createEntry({
        name: trimmedName,
        relativePath: relativePath,
        actualPath: this.resolveActualPath(connection, relativePath),
        size: file.isDirectory ? 0 : (Number(file.size) || 0),
        isDirectory: file.isDirectory,
        lastModified: Number(file.lastModified) || 0,
        etag: file.etag || '',
        contentType: file.contentType || '',
        permissions: ''
      }));
    }

    return this.sortEntries(entries);
  }

  private normalizeFTPEntries(
    connection: NetworkFolderConnection,
    currentRelativePath: string,
    files: FTPFileInfo[]
  ): NetworkFolderEntry[] {
    const entries: NetworkFolderEntry[] = [];
    const normalizedCurrentPath = normalizeRelativeNetworkFolderPath(currentRelativePath);

    for (const file of files) {
      const trimmedName = (file.name || '').trim();
      if (!trimmedName || trimmedName === '.' || trimmedName === '..') {
        continue;
      }

      let relativePath = this.normalizeRemoteActualPathToRelative(connection, file.path || '');
      if (relativePath === '/' || relativePath === normalizedCurrentPath) {
        relativePath = joinRelativeNetworkFolderPath(normalizedCurrentPath, trimmedName);
      }

      entries.push(this.createEntry({
        name: trimmedName,
        relativePath: relativePath,
        actualPath: file.path || this.resolveActualPath(connection, relativePath),
        size: file.isDirectory ? 0 : (Number(file.size) || 0),
        isDirectory: file.isDirectory,
        lastModified: Number(file.lastModified) || 0,
        etag: '',
        contentType: '',
        permissions: file.permissions || ''
      }));
    }

    return this.sortEntries(entries);
  }

  private normalizeSMBEntries(
    connection: NetworkFolderConnection,
    currentRelativePath: string,
    files: SMBDirectoryEntry[]
  ): NetworkFolderEntry[] {
    const entries: NetworkFolderEntry[] = [];
    const normalizedCurrentPath = normalizeRelativeNetworkFolderPath(currentRelativePath);

    for (const file of files) {
      const trimmedName = (file.name || '').trim();
      if (!trimmedName || trimmedName === '.' || trimmedName === '..') {
        continue;
      }

      const relativePath = joinRelativeNetworkFolderPath(normalizedCurrentPath, trimmedName);
      entries.push(this.createEntry({
        name: trimmedName,
        relativePath: relativePath,
        actualPath: this.buildSMBUNCPath(connection, relativePath),
        size: file.isDirectory ? 0 : (Number(file.size) || 0),
        isDirectory: file.isDirectory,
        lastModified: Number(file.lastModified) || 0,
        etag: '',
        contentType: '',
        permissions: this.formatSMBAttributes(file.attributes)
      }));
    }

    return this.sortEntries(entries);
  }

  private createEntry(options: NetworkFolderEntryOptions): NetworkFolderEntry {
    const importCategory = options.isDirectory ? 'unsupported' : inferNetworkFolderImportCategory(options.name);
    const relativePath = normalizeRelativeNetworkFolderPath(options.relativePath);
    const entry: NetworkFolderEntry = {
      key: relativePath,
      name: options.name,
      relativePath: relativePath,
      actualPath: options.actualPath,
      size: options.size,
      isDirectory: options.isDirectory,
      lastModified: options.lastModified,
      etag: options.etag,
      contentType: options.contentType,
      permissions: options.permissions,
      importCategory: importCategory,
      cacheStatus: 'none',
      cachedLocalPath: '',
      versionTag: ''
    };
    entry.versionTag = this.buildVersionTag(entry);
    entry.key = relativePath;
    return entry;
  }

  private decorateEntriesWithCache(connectionId: string, entries: NetworkFolderEntry[]): NetworkFolderEntry[] {
    const decoratedEntries: NetworkFolderEntry[] = [];
    for (const entry of entries) {
      const decoratedEntry = this.cloneEntry(entry);
      if (entry.isDirectory) {
        decoratedEntry.cacheStatus = 'none';
        decoratedEntry.cachedLocalPath = '';
        decoratedEntries.push(decoratedEntry);
        continue;
      }

      const cached = this.downloadCache.get(this.buildDownloadCacheKey(connectionId, entry.relativePath));
      if (!cached || !this.fileExists(cached.localPath)) {
        decoratedEntry.cacheStatus = 'none';
        decoratedEntry.cachedLocalPath = '';
        decoratedEntries.push(decoratedEntry);
        continue;
      }

      decoratedEntry.cacheStatus = cached.versionTag === entry.versionTag ? 'cached' : 'stale';
      decoratedEntry.cachedLocalPath = cached.localPath;
      decoratedEntries.push(decoratedEntry);
    }
    return decoratedEntries;
  }

  private cleanEntriesForCache(entries: NetworkFolderEntry[]): NetworkFolderEntry[] {
    const cleanedEntries: NetworkFolderEntry[] = [];
    for (const entry of entries) {
      const cleanedEntry = this.cloneEntry(entry);
      cleanedEntry.cacheStatus = 'none';
      cleanedEntry.cachedLocalPath = '';
      cleanedEntries.push(cleanedEntry);
    }
    return cleanedEntries;
  }

  private buildVersionTag(entry: NetworkFolderEntry): string {
    if (entry.etag && entry.etag.trim().length > 0) {
      return entry.etag.trim();
    }
    return `${entry.isDirectory ? 'dir' : 'file'}|${entry.size}|${entry.lastModified}|${entry.contentType}|${entry.permissions}|${entry.name}`;
  }

  private sortEntries(entries: NetworkFolderEntry[]): NetworkFolderEntry[] {
    const sorted: NetworkFolderEntry[] = [];
    for (const entry of entries) {
      sorted.push(this.cloneEntry(entry));
    }
    sorted.sort((left: NetworkFolderEntry, right: NetworkFolderEntry) => {
      if (left.isDirectory !== right.isDirectory) {
        return left.isDirectory ? -1 : 1;
      }
      return left.name.localeCompare(right.name);
    });
    return sorted;
  }

  private async loadPreferencesState(): Promise<void> {
    this.ensurePreferenceStore();
    const parsed: ParsedPreferencesConnections = {
      connections: [],
      lastConnectionId: '',
      lastPaths: new Map<string, string>()
    };

    let needsMigration: boolean = false;
    try {
      await this.ensureEncryptionKey();

      const rawConnections = String(await this.pref!.get(CONNECTIONS_KEY, '[]'));
      const rawLastConnectionId = String(await this.pref!.get(LAST_CONNECTION_KEY, ''));
      const rawLastPaths = String(await this.pref!.get(LAST_PATHS_KEY, '[]'));

      const connectionArray = this.safeParseJson<NetworkFolderConnection[]>(rawConnections, []);
      for (let i = 0; i < connectionArray.length; i++) {
        const item = connectionArray[i];
        if (item.password.startsWith(PASSWORD_ENCRYPTED_PREFIX)) {
          try {
            const ciphertext = item.password.substring(PASSWORD_ENCRYPTED_PREFIX.length);
            item.password = await aes256GcmDecrypt(ciphertext, this.encryptionKey!);
          } catch (decryptError) {
            logger.error(TAG, `密码解密失败(connection=${item.id})，已置空: ${String(decryptError)}`);
            item.password = '';
          }
        } else if (item.password.length > 0) {
          needsMigration = true;
        }
        parsed.connections.push(this.normalizeConnection(item));
      }

      const rawLastPathItems = this.safeParseJson<PersistedLastPathEntry[]>(rawLastPaths, []);
      if (Array.isArray(rawLastPathItems)) {
        rawLastPathItems.forEach((lastPathItem: PersistedLastPathEntry) => {
          if (!lastPathItem || !lastPathItem.connectionId) {
            return;
          }
          parsed.lastPaths.set(
            lastPathItem.connectionId,
            normalizeRelativeNetworkFolderPath(lastPathItem.relativePath || '/')
          );
        });
      }

      parsed.lastConnectionId = rawLastConnectionId.trim();
    } catch (error) {
      logger.error(TAG, `加载网络连接偏好失败：${String(error)}`);
    }

    this.connections = parsed.connections;
    this.lastConnectionId = parsed.lastConnectionId;
    this.lastPaths = parsed.lastPaths;

    // 自动迁移：将旧版明文密码加密存储
    if (needsMigration && this.connections.length > 0) {
      try {
        await this.persistConnections();
        logger.info(TAG, `已自动迁移 ${this.connections.length} 个连接的密码为加密存储`);
      } catch (migrationError) {
        logger.error(TAG, `密码加密迁移失败: ${String(migrationError)}`);
      }
    }

    try {
      const rawFavorites = String(await this.pref!.get(FAVORITE_PATHS_KEY, '[]'));
      const favoriteItems = this.safeParseJson<FavoritePathEntry[]>(rawFavorites, []);
      this.favoritePaths.clear();
      if (Array.isArray(favoriteItems)) {
        favoriteItems.forEach((item: FavoritePathEntry) => {
          if (!item || !item.connectionId) {
            return;
          }
          const normalizedPath = normalizeRelativeNetworkFolderPath(item.relativePath || '/');
          let pathSet = this.favoritePaths.get(item.connectionId);
          if (!pathSet) {
            pathSet = new Set<string>();
            this.favoritePaths.set(item.connectionId, pathSet);
          }
          pathSet.add(normalizedPath);
        });
      }
    } catch (error) {
      logger.error(TAG, `加载收藏夹偏好失败：${String(error)}`);
    }
  }

  private loadPersistedState(): void {
    this.directoryCache.clear();
    this.downloadCache.clear();

    if (!this.fileExists(this.stateFilePath)) {
      this.persistCacheStateSync();
      return;
    }

    try {
      const raw = SafeFileUtils.readTextSync(this.stateFilePath);
      if (!raw || raw.trim().length === 0) {
        return;
      }

      const state = this.safeParseJson<PersistedNetworkFolderState | null>(raw, null);
      if (!state) {
        return;
      }

      const validConnectionIds = this.buildConnectionIdSet();
      const directoryItems = Array.isArray(state.directoryCache) ? state.directoryCache : [];
      const downloadItems = Array.isArray(state.downloadCache) ? state.downloadCache : [];

      directoryItems.forEach((item: CachedDirectoryEntry) => {
        if (!item || !validConnectionIds.has(item.connectionId)) {
          return;
        }
        const normalizedPath = normalizeRelativeNetworkFolderPath(item.relativePath);
        const fetchedAt = Number(item.fetchedAt) || 0;
        const entries = Array.isArray(item.entries)
          ? item.entries.map((entry: NetworkFolderEntry) => this.normalizeCachedEntry(entry))
          : [];
        this.directoryCache.set(this.buildDirectoryCacheKey(item.connectionId, normalizedPath), {
          connectionId: item.connectionId,
          relativePath: normalizedPath,
          fetchedAt: fetchedAt,
          entries: entries
        });
      });

      downloadItems.forEach((item: CachedDownloadEntry) => {
        if (!item || !validConnectionIds.has(item.connectionId)) {
          return;
        }
        const normalizedPath = normalizeRelativeNetworkFolderPath(item.relativePath);
        const inferredImportCategory = inferNetworkFolderImportCategory(item.fileName || '');
        const normalizedImportCategory = item.importCategory && item.importCategory !== 'unsupported'
          ? item.importCategory
          : inferredImportCategory;
        this.downloadCache.set(this.buildDownloadCacheKey(item.connectionId, normalizedPath), {
          connectionId: item.connectionId,
          relativePath: normalizedPath,
          localPath: item.localPath || '',
          fileName: item.fileName || '',
          size: Number(item.size) || 0,
          versionTag: item.versionTag || '',
          cachedAt: Number(item.cachedAt) || 0,
          lastAccessedAt: Number(item.lastAccessedAt) || Number(item.cachedAt) || 0,
          importCategory: normalizedImportCategory
        });
      });
    } catch (error) {
      logger.error(TAG, `加载网络缓存状态失败：${String(error)}`);
    }
  }

  private async pruneCaches(): Promise<void> {
    const now = Date.now();
    const validConnectionIds = this.buildConnectionIdSet();
    const canValidateLocalFiles = this.downloadDirManager.isReady();
    let changed = false;

    const directoryPairs = this.getDirectoryCachePairs();
    for (const pair of directoryPairs) {
      if (!validConnectionIds.has(pair.value.connectionId) || now - pair.value.fetchedAt > DIRECTORY_CACHE_RETENTION_MS) {
        this.directoryCache.delete(pair.key);
        changed = true;
      }
    }

    if (this.directoryCache.size > DIRECTORY_CACHE_MAX_ENTRIES) {
      const sortedDirectoryEntries = this.getDirectoryCachePairs();
      sortedDirectoryEntries.sort((left: CachedDirectoryPair, right: CachedDirectoryPair) => {
        return right.value.fetchedAt - left.value.fetchedAt;
      });
      const keep = new Set<string>();
      for (let index = 0; index < sortedDirectoryEntries.length && index < DIRECTORY_CACHE_MAX_ENTRIES; index++) {
        keep.add(sortedDirectoryEntries[index].key);
      }
      for (const key of this.directoryCache.keys()) {
        if (!keep.has(key)) {
          this.directoryCache.delete(key);
          changed = true;
        }
      }
    }

    const downloadPairs = this.getDownloadCachePairs();
    for (const pair of downloadPairs) {
      const expired = now - pair.value.lastAccessedAt > DOWNLOAD_CACHE_MAX_AGE_MS;
      const invalidConnection = !validConnectionIds.has(pair.value.connectionId);
      const missingLocalFile = canValidateLocalFiles && !this.fileExists(pair.value.localPath);
      const invalid = invalidConnection || missingLocalFile;
      if (expired || invalid) {
        this.deleteFileIfExists(pair.value.localPath);
        this.downloadCache.delete(pair.key);
        changed = true;
      }
    }

    let totalBytes = this.getDownloadCacheTotalBytes();
    if (totalBytes > DOWNLOAD_CACHE_MAX_BYTES) {
      const sortedDownloads = this.getDownloadCachePairs();
      sortedDownloads.sort((left: CachedDownloadPair, right: CachedDownloadPair) => {
        return left.value.lastAccessedAt - right.value.lastAccessedAt;
      });
      for (const pair of sortedDownloads) {
        if (totalBytes <= DOWNLOAD_CACHE_MAX_BYTES) {
          break;
        }
        this.deleteFileIfExists(pair.value.localPath);
        this.downloadCache.delete(pair.key);
        totalBytes -= pair.value.size;
        changed = true;
      }
    }

    if (changed) {
      await this.persistCacheState();
    }
  }

  private cloneConnection(connection: NetworkFolderConnection): NetworkFolderConnection {
    return {
      id: connection.id,
      name: connection.name,
      protocol: connection.protocol,
      serverUrl: connection.serverUrl,
      host: connection.host,
      shareName: connection.shareName,
      domain: connection.domain,
      clientIP: connection.clientIP,
      port: connection.port,
      username: connection.username,
      password: connection.password,
      basePath: connection.basePath,
      passive: connection.passive,
      verifySSL: connection.verifySSL,
      verifyHostKey: connection.verifyHostKey,
      timeoutMs: connection.timeoutMs,
      createdAt: connection.createdAt,
      lastUsedAt: connection.lastUsedAt
    };
  }

  private cloneEntry(entry: NetworkFolderEntry): NetworkFolderEntry {
    return {
      key: entry.key,
      name: entry.name,
      relativePath: entry.relativePath,
      actualPath: entry.actualPath,
      size: entry.size,
      isDirectory: entry.isDirectory,
      lastModified: entry.lastModified,
      etag: entry.etag,
      contentType: entry.contentType,
      permissions: entry.permissions,
      importCategory: entry.importCategory,
      cacheStatus: entry.cacheStatus,
      cachedLocalPath: entry.cachedLocalPath,
      versionTag: entry.versionTag
    };
  }

  private buildConnectionIdSet(): Set<string> {
    const ids = new Set<string>();
    for (const item of this.connections) {
      ids.add(item.id);
    }
    return ids;
  }

  private getDirectoryCachePairs(): CachedDirectoryPair[] {
    const pairs: CachedDirectoryPair[] = [];
    this.directoryCache.forEach((value: CachedDirectoryEntry, key: string) => {
      pairs.push({
        key: key,
        value: value
      });
    });
    return pairs;
  }

  private getDownloadCachePairs(): CachedDownloadPair[] {
    const pairs: CachedDownloadPair[] = [];
    this.downloadCache.forEach((value: CachedDownloadEntry, key: string) => {
      pairs.push({
        key: key,
        value: value
      });
    });
    return pairs;
  }

  private ensureInitialized(): void {
    if (!this.initialized) {
      throw new Error('网络文件夹管理器尚未初始化');
    }
  }

  private ensurePreferenceStore(): void {
    if (!this.pref) {
      throw new Error('网络文件夹偏好存储尚未初始化');
    }
  }

  private async ensureEncryptionKey(): Promise<void> {
    if (this.encryptionKey !== null) {
      return;
    }
    this.ensurePreferenceStore();
    const storedKey = String(await this.pref!.get(ENCRYPTION_KEY_PREF, ''));
    if (storedKey.length > 0) {
      this.encryptionKey = await importSymKeyFromBase64(storedKey);
    } else {
      this.encryptionKey = await generateAes256Key();
      const exportedKey = exportSymKeyToBase64(this.encryptionKey);
      await this.pref!.put(ENCRYPTION_KEY_PREF, exportedKey);
      await this.pref!.flush();
    }
  }

  private async persistConnections(): Promise<void> {
    this.ensurePreferenceStore();
    await this.ensureEncryptionKey();
    const encryptedConnections: NetworkFolderConnection[] = [];
    for (let i = 0; i < this.connections.length; i++) {
      const conn = this.connections[i];
      if (conn.password.length > 0) {
        const encrypted = await aes256GcmEncrypt(conn.password, this.encryptionKey!);
        const copy: NetworkFolderConnection = {
          id: conn.id,
          name: conn.name,
          protocol: conn.protocol,
          serverUrl: conn.serverUrl,
          host: conn.host,
          shareName: conn.shareName,
          domain: conn.domain,
          clientIP: conn.clientIP,
          port: conn.port,
          username: conn.username,
          password: PASSWORD_ENCRYPTED_PREFIX + encrypted,
          basePath: conn.basePath,
          passive: conn.passive,
          verifySSL: conn.verifySSL,
          verifyHostKey: conn.verifyHostKey,
          timeoutMs: conn.timeoutMs,
          createdAt: conn.createdAt,
          lastUsedAt: conn.lastUsedAt
        };
        encryptedConnections.push(copy);
      } else {
        encryptedConnections.push(conn);
      }
    }
    await this.pref!.put(CONNECTIONS_KEY, JSON.stringify(encryptedConnections));
    await this.pref!.flush();
  }

  private async persistLastState(): Promise<void> {
    this.ensurePreferenceStore();
    const lastPathItems: PersistedLastPathEntry[] = [];
    this.lastPaths.forEach((value: string, key: string) => {
      lastPathItems.push({
        connectionId: key,
        relativePath: value
      });
    });
    await this.pref!.put(LAST_CONNECTION_KEY, this.lastConnectionId);
    await this.pref!.put(LAST_PATHS_KEY, JSON.stringify(lastPathItems));
    await this.pref!.flush();
  }

  private async persistFavoritePaths(): Promise<void> {
    this.ensurePreferenceStore();
    const favoriteItems: FavoritePathEntry[] = [];
    this.favoritePaths.forEach((pathSet: Set<string>, connectionId: string) => {
      pathSet.forEach((path: string) => {
        favoriteItems.push({
          connectionId: connectionId,
          relativePath: path
        });
      });
    });
    await this.pref!.put(FAVORITE_PATHS_KEY, JSON.stringify(favoriteItems));
    await this.pref!.flush();
  }

  private async persistCacheState(): Promise<void> {
    this.persistCacheStateSync();
  }

  private persistCacheStateSync(): void {
    try {
      this.ensureDir(this.rootDir);
      const state: PersistedNetworkFolderState = {
        version: STATE_VERSION,
        directoryCache: Array.from(this.directoryCache.values()),
        downloadCache: Array.from(this.downloadCache.values()),
        updatedAt: Date.now()
      };
      const file = SafeFileUtils.openSync(this.stateFilePath, fs.OpenMode.CREATE | fs.OpenMode.TRUNC | fs.OpenMode.WRITE_ONLY);
      try {
        SafeFileUtils.writeSync(file.fd, JSON.stringify(state));
      } finally {
        SafeFileUtils.closeSync(file);
      }
    } catch (error) {
      logger.error(TAG, `持久化网络缓存状态失败：${String(error)}`);
    }
  }

  private buildWebDAVConfig(connection: NetworkFolderConnection): WebDAVNativeConfig {
    return {
      serverUrl: connection.serverUrl.trim(),
      username: connection.username,
      password: connection.password,
      basePath: normalizeConnectionBasePath(connection.basePath),
      timeoutMs: connection.timeoutMs,
      verifySSL: connection.verifySSL
    };
  }

  private buildFTPConfig(connection: NetworkFolderConnection): FTPConfig {
    return {
      host: connection.host.trim(),
      port: connection.port,
      username: connection.username,
      password: connection.password,
      useFTPS: connection.protocol === 'ftps',
      useSFTP: connection.protocol === 'sftp',
      passive: connection.passive,
      timeoutMs: connection.timeoutMs
    };
  }

  private buildSMBUNCPath(connection: NetworkFolderConnection, relativePath: string): string {
    const shareBase = `\\\\${connection.host.trim()}\\${connection.shareName.trim()}`;
    const actualPath = this.resolveActualPath(connection, relativePath);
    if (actualPath === '/') {
      return shareBase;
    }
    const shareRelativePath = actualPath.substring(1).replace(/\//g, '\\');
    return shareRelativePath.length > 0 ? `${shareBase}\\${shareRelativePath}` : shareBase;
  }

  private resolveActualPath(connection: NetworkFolderConnection, relativePath: string): string {
    const normalizedRelativePath = normalizeRelativeNetworkFolderPath(relativePath);
    const basePath = normalizeConnectionBasePath(connection.basePath);
    if (basePath === '/') {
      return normalizedRelativePath;
    }
    if (normalizedRelativePath === '/') {
      return basePath;
    }
    return `${basePath}${normalizedRelativePath}`;
  }

  private resolveWebDAVClientPath(relativePath: string): string {
    const normalizedRelativePath = normalizeRelativeNetworkFolderPath(relativePath);
    return normalizedRelativePath === '/' ? '' : normalizedRelativePath;
  }

  private normalizeRemoteActualPathToRelative(connection: NetworkFolderConnection, actualPath: string): string {
    const trimmed = (actualPath || '').trim();
    if (!trimmed) {
      return '/';
    }

    let normalized = trimmed;
    const serverUrl = connection.serverUrl.trim().replace(/\/+$/g, '');
    if (serverUrl && normalized.startsWith(serverUrl)) {
      normalized = normalized.substring(serverUrl.length);
    }

    normalized = normalized.replace(/^[a-zA-Z]+:\/\/[^/]+/, '');
    normalized = normalized.replace(/[?#].*$/, '');
    normalized = normalized.replace(/\\/g, '/');
    if (!normalized.startsWith('/')) {
      normalized = `/${normalized}`;
    }
    normalized = normalized.replace(/\/+/g, '/');
    if (normalized.length > 1 && normalized.endsWith('/')) {
      normalized = normalized.substring(0, normalized.length - 1);
    }

    const basePath = normalizeConnectionBasePath(connection.basePath);
    if (basePath !== '/') {
      if (normalized === basePath) {
        return '/';
      }
      if (normalized.startsWith(`${basePath}/`)) {
        return normalizeRelativeNetworkFolderPath(normalized.substring(basePath.length));
      }
    }

    return normalizeRelativeNetworkFolderPath(normalized);
  }

  private shouldResetConnectionRuntimeState(
    previous: NetworkFolderConnection,
    next: NetworkFolderConnection
  ): boolean {
    if (previous.protocol !== next.protocol) {
      return true;
    }
    if (previous.serverUrl !== next.serverUrl) {
      return true;
    }
    if (previous.host !== next.host) {
      return true;
    }
    if (previous.shareName !== next.shareName) {
      return true;
    }
    if (previous.domain !== next.domain) {
      return true;
    }
    if (previous.port !== next.port) {
      return true;
    }
    if (previous.username !== next.username) {
      return true;
    }
    if (previous.basePath !== next.basePath) {
      return true;
    }
    if (previous.passive !== next.passive) {
      return true;
    }
    return previous.verifySSL !== next.verifySSL;
  }

  private normalizeSMBHost(hostValue: string): string {
    let normalized = hostValue.trim();
    normalized = normalized.replace(/^smb:\/\//i, '');
    normalized = normalized.replace(/^\\\\+/, '');
    normalized = normalized.replace(/^\/+/, '');
    normalized = normalized.replace(/\\/g, '/');
    const separatorIndex = normalized.indexOf('/');
    if (separatorIndex >= 0) {
      normalized = normalized.substring(0, separatorIndex);
    }
    return normalized.trim();
  }

  private normalizeSMBShareName(hostValue: string, shareValue: string): string {
    const normalizedHost = this.normalizeSMBHost(hostValue);
    let normalized = shareValue.trim();
    if (normalized.length === 0) {
      const normalizedHostSource = hostValue.trim()
        .replace(/^smb:\/\//i, '')
        .replace(/^\\\\+/, '')
        .replace(/^\/+/, '')
        .replace(/\\/g, '/');
      const hostParts = normalizedHostSource.split('/').filter((item: string) => item.length > 0);
      if (hostParts.length > 1) {
        return hostParts[1];
      }
      return '';
    }

    normalized = normalized.replace(/^smb:\/\//i, '');
    normalized = normalized.replace(/^\\\\+/, '');
    normalized = normalized.replace(/^\/+/, '');
    normalized = normalized.replace(/\\/g, '/');

    const parts = normalized.split('/').filter((item: string) => item.length > 0);
    if (parts.length === 0) {
      return '';
    }
    if (parts.length === 1) {
      return parts[0];
    }
    if (normalizedHost.length > 0 && parts[0].toLowerCase() === normalizedHost.toLowerCase()) {
      return parts[1];
    }
    return parts[0];
  }

  private normalizeSMBBasePath(basePath: string, shareName: string): string {
    let normalizedPath = normalizeConnectionBasePath(basePath);
    const normalizedShareName = this.normalizeSMBShareName('', shareName);
    if (normalizedShareName.length === 0) {
      return normalizedPath;
    }

    const sharePrefix = `/${normalizedShareName}`;
    const lowerPath = normalizedPath.toLowerCase();
    const lowerSharePrefix = sharePrefix.toLowerCase();
    if (lowerPath === lowerSharePrefix) {
      return '/';
    }
    if (lowerPath.startsWith(`${lowerSharePrefix}/`)) {
      normalizedPath = normalizedPath.substring(sharePrefix.length);
    }
    return normalizeConnectionBasePath(normalizedPath);
  }

  private normalizeConnection(connection: NetworkFolderConnection): NetworkFolderConnection {
    const protocol = connection.protocol === 'ftp' ||
      connection.protocol === 'ftps' ||
      connection.protocol === 'sftp' ||
      connection.protocol === 'smb'
      ? connection.protocol
      : 'webdav';
    const normalizedHost = protocol === 'smb'
      ? this.normalizeSMBHost(String(connection.host || ''))
      : String(connection.host || '').trim();
    const normalizedShareName = protocol === 'smb'
      ? this.normalizeSMBShareName(normalizedHost, String(connection.shareName || ''))
      : String(connection.shareName || '').trim();
    const normalizedBasePath = protocol === 'smb'
      ? this.normalizeSMBBasePath(connection.basePath || '/', normalizedShareName)
      : normalizeConnectionBasePath(connection.basePath || '/');
    return {
      id: String(connection.id || '').trim(),
      name: String(connection.name || '').trim(),
      protocol: protocol,
      serverUrl: String(connection.serverUrl || '').trim(),
      host: normalizedHost,
      shareName: normalizedShareName,
      domain: String(connection.domain || '').trim(),
      clientIP: String(connection.clientIP || '').trim(),
      port: Number(connection.port) > 0
        ? Math.floor(Number(connection.port))
        : (protocol === 'ftps' ? 990 : protocol === 'ftp' ? 21 : protocol === 'sftp' ? 22 : protocol === 'smb' ? 445 : 443),
      username: String(connection.username || '').trim(),
      password: String(connection.password || ''),
      basePath: normalizedBasePath,
      passive: connection.passive !== false,
      verifySSL: connection.verifySSL !== false,
      verifyHostKey: connection.verifyHostKey !== false,
      timeoutMs: Number(connection.timeoutMs) > 0 ? Math.floor(Number(connection.timeoutMs)) : 30000,
      createdAt: Number(connection.createdAt) || Date.now(),
      lastUsedAt: Number(connection.lastUsedAt) || 0
    };
  }

  private normalizeCachedEntry(entry: NetworkFolderEntry): NetworkFolderEntry {
    const relativePath = normalizeRelativeNetworkFolderPath(entry.relativePath || '/');
    const inferredImportCategory = inferNetworkFolderImportCategory(entry.name || '');
    const normalizedImportCategory = entry.importCategory && entry.importCategory !== 'unsupported'
      ? entry.importCategory
      : inferredImportCategory;
    const normalized: NetworkFolderEntry = {
      key: entry.key || relativePath,
      name: entry.name || relativePath.split('/').pop() || '',
      relativePath: relativePath,
      actualPath: entry.actualPath || relativePath,
      size: Number(entry.size) || 0,
      isDirectory: entry.isDirectory === true,
      lastModified: Number(entry.lastModified) || 0,
      etag: entry.etag || '',
      contentType: entry.contentType || '',
      permissions: entry.permissions || '',
      importCategory: normalizedImportCategory,
      cacheStatus: 'none',
      cachedLocalPath: '',
      versionTag: entry.versionTag || ''
    };
    normalized.versionTag = normalized.versionTag || this.buildVersionTag(normalized);
    normalized.key = relativePath;
    return normalized;
  }

  private requireConnection(connectionId: string): NetworkFolderConnection {
    const connection = this.getConnection(connectionId);
    if (!connection) {
      throw new Error(`未找到网络连接：${connectionId}`);
    }
    return connection;
  }

  private async markConnectionUsed(connectionId: string, relativePath: string): Promise<void> {
    const normalizedPath = normalizeRelativeNetworkFolderPath(relativePath);
    let connectionChanged = false;
    const now = Date.now();

    for (let index = 0; index < this.connections.length; index++) {
      const item = this.connections[index];
      if (item.id !== connectionId) {
        continue;
      }
      const updatedConnection = this.cloneConnection(item);
      updatedConnection.lastUsedAt = now;
      this.connections[index] = updatedConnection;
      connectionChanged = true;
      break;
    }

    if (this.lastConnectionId !== connectionId) {
      this.lastConnectionId = connectionId;
    }
    if (this.lastPaths.get(connectionId) !== normalizedPath) {
      this.lastPaths.set(connectionId, normalizedPath);
    }

    if (connectionChanged) {
      await this.persistConnections();
    }
    await this.persistLastState();
  }

  private buildDirectoryCacheKey(connectionId: string, relativePath: string): string {
    return `${connectionId}|${normalizeRelativeNetworkFolderPath(relativePath)}`;
  }

  private buildDownloadCacheKey(connectionId: string, relativePath: string): string {
    return `${connectionId}|${normalizeRelativeNetworkFolderPath(relativePath)}`;
  }

  private limitDirectoryCacheEntries(): void {
    if (this.directoryCache.size <= DIRECTORY_CACHE_MAX_ENTRIES) {
      return;
    }
    const sorted = this.getDirectoryCachePairs();
    sorted.sort((left: CachedDirectoryPair, right: CachedDirectoryPair) => right.value.fetchedAt - left.value.fetchedAt);
    const keep = new Set<string>();
    for (let index = 0; index < sorted.length && index < DIRECTORY_CACHE_MAX_ENTRIES; index++) {
      keep.add(sorted[index].key);
    }
    for (const key of this.directoryCache.keys()) {
      if (!keep.has(key)) {
        this.directoryCache.delete(key);
      }
    }
  }

  private getDownloadCacheTotalBytes(): number {
    let totalBytes = 0;
    for (const item of this.downloadCache.values()) {
      totalBytes += item.size;
    }
    return totalBytes;
  }

  private tryResolveDownloadCacheRootFromManager(): void {
    if (!this.downloadDirManager.isReady()) {
      return;
    }
    try {
      this.downloadsDir = this.downloadDirManager.ensureDirectory('cache/network_folder/downloads');
      this.ensureDir(this.downloadsDir);
      logger.info(TAG, `网络文件夹缓存目录已准备：${this.downloadsDir}`);
    } catch (error) {
      logger.warn(TAG, `初始化 Download 缓存目录失败，将在首次缓存时重试：${String(error)}`);
      this.downloadsDir = '';
    }
  }

  private async ensureDownloadCacheRootReady(): Promise<void> {
    if (this.downloadsDir.length > 0 && this.fileExists(this.downloadsDir)) {
      return;
    }
    if (!this.context) {
      throw new Error('上下文未初始化，无法准备 Download 应用目录');
    }
    this.downloadDirManager.setContext(this.context);
    if (!this.downloadDirManager.isReady()) {
      const granted = await this.downloadDirManager.requestAccess();
      if (!granted || !this.downloadDirManager.isReady()) {
        throw new Error('未授予 Download 应用目录权限');
      }
    }
    this.downloadsDir = this.downloadDirManager.ensureDirectory('cache/network_folder/downloads');
    this.ensureDir(this.downloadsDir);
    logger.info(TAG, `网络文件夹缓存目录已就绪：${this.downloadsDir}`);
  }

  private getConnectionDownloadsDir(connectionId: string): string {
    if (this.downloadsDir.length === 0) {
      return '';
    }
    return `${this.downloadsDir}/${this.hashString(connectionId)}`;
  }

  private getConnectionFileCacheDir(connectionId: string, relativePath: string): string {
    const baseDir = this.getConnectionDownloadsDir(connectionId);
    if (baseDir.length === 0) {
      return '';
    }
    const parentRelativePath = this.getParentRelativePath(relativePath);
    if (parentRelativePath === '/') {
      return `${baseDir}/_root`;
    }
    return `${baseDir}/${this.hashString(parentRelativePath)}`;
  }

  private buildDownloadFileName(
    fileName: string
  ): string {
    return sanitizeFileName(fileName, 'remote_file', 120);
  }

  private getParentRelativePath(relativePath: string): string {
    const normalized = normalizeRelativeNetworkFolderPath(relativePath);
    if (normalized === '/') {
      return '/';
    }
    const lastSlash = normalized.lastIndexOf('/');
    if (lastSlash <= 0) {
      return '/';
    }
    return normalized.substring(0, lastSlash);
  }

  private buildDownloadFailure(message: string): NetworkFolderDownloadResult {
    return {
      success: false,
      message: message,
      localPath: '',
      fileUri: '',
      reusedCache: false,
      importCategory: 'unsupported'
    };
  }

  private formatSMBAttributes(attributes: number): string {
    if (!Number.isFinite(attributes) || attributes <= 0) {
      return '';
    }
    return `0x${Math.floor(attributes).toString(16).toUpperCase()}`;
  }

  private ensureDir(path: string): void {
    if (!path || path.trim().length === 0) {
      return;
    }
    if (!this.fileExists(path)) {
      SafeFileUtils.mkdirSync(path, true);
    }
  }

  private fileExists(path: string): boolean {
    if (!path || path.trim().length === 0) {
      return false;
    }
    try {
      return SafeFileUtils.accessSync(path);
    } catch (error) {
      return false;
    }
  }

  private deleteFileIfExists(path: string): void {
    if (!this.fileExists(path)) {
      return;
    }
    try {
      const stat = SafeFileUtils.statSync(path);
      if (!stat.isDirectory()) {
        SafeFileUtils.unlinkSync(path);
      }
    } catch (error) {
      logger.warn(TAG, `删除缓存文件失败：${path}，原因：${String(error)}`);
    }
  }

  private deleteDirectoryIfExists(path: string): void {
    if (!this.fileExists(path)) {
      return;
    }
    try {
      const stat = SafeFileUtils.statSync(path);
      if (!stat.isDirectory()) {
        SafeFileUtils.unlinkSync(path);
        return;
      }
      this.deleteDirectoryContents(path);
      SafeFileUtils.rmdirSync(path);
    } catch (error) {
      logger.warn(TAG, `删除缓存目录失败：${path}，原因：${String(error)}`);
    }
  }

  private deleteDirectoryContents(path: string): void {
    if (!this.fileExists(path)) {
      return;
    }
    try {
      const names = SafeFileUtils.listFileSync(path);
      names.forEach((name: string) => {
        const childPath = `${path}/${name}`;
        const stat = SafeFileUtils.statSync(childPath);
        if (stat.isDirectory()) {
          this.deleteDirectoryIfExists(childPath);
        } else {
          SafeFileUtils.unlinkSync(childPath);
        }
      });
    } catch (error) {
      logger.warn(TAG, `清空缓存目录失败：${path}，原因：${String(error)}`);
    }
  }

  private safeParseJson<T>(raw: string, fallback: T): T {
    try {
      if (!raw || raw.trim().length === 0) {
        return fallback;
      }
      return SafeUtils.parseObj(raw) as T;
    } catch (error) {
      return fallback;
    }
  }

  private hashString(value: string): string {
    let hash = 2166136261;
    for (let index = 0; index < value.length; index++) {
      hash ^= value.charCodeAt(index);
      hash += (hash << 1) + (hash << 4) + (hash << 7) + (hash << 8) + (hash << 24);
    }
    return (hash >>> 0).toString(16).padStart(8, '0');
  }
}

export function getNetworkFolderManager(): NetworkFolderManager {
  return NetworkFolderManager.getInstance();
}
