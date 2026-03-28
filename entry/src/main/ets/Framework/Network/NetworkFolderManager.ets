import { common } from '@kit.AbilityKit';
import { preferences } from '@kit.ArkData';
import { fileUri } from '@kit.CoreFileKit';
import fs from '@ohos.file.fs';
import { logger } from '../../Utils/Logger';
import { sanitizeFileName } from '../../Utils/FileNameUtils';
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
import { SandboxManager } from '../Storage/SandboxManager';
import {
  NetworkFolderBrowseResult,
  NetworkFolderCacheStats,
  NetworkFolderConnection,
  NetworkFolderDownloadResult,
  NetworkFolderEntry,
  inferNetworkFolderImportCategory,
  isNetworkFolderImportSupported,
  joinRelativeNetworkFolderPath,
  normalizeConnectionBasePath,
  normalizeRelativeNetworkFolderPath
} from '../../Models/NetworkFolderModels';

const TAG = 'NetworkFolderManager';

const PREF_NAME = 'network_folder_preferences';
const CONNECTIONS_KEY = 'connections';
const LAST_CONNECTION_KEY = 'last_connection_id';
const LAST_PATHS_KEY = 'last_paths';
const STATE_FILE_NAME = 'network_folder_state.json';
const STATE_VERSION = 1;
const DIRECTORY_CACHE_FRESH_TTL_MS = 5 * 60 * 1000;
const DIRECTORY_CACHE_RETENTION_MS = 2 * 24 * 60 * 60 * 1000;
const DIRECTORY_CACHE_MAX_ENTRIES = 120;
const DOWNLOAD_CACHE_MAX_AGE_MS = 7 * 24 * 60 * 60 * 1000;
const DOWNLOAD_CACHE_MAX_BYTES = 1024 * 1024 * 1024;

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
  private smbClient: SMBClientAdapter = new SMBClientAdapter();
  private initialized: boolean = false;

  private connections: NetworkFolderConnection[] = [];
  private lastConnectionId: string = '';
  private lastPaths: Map<string, string> = new Map<string, string>();
  private directoryCache: Map<string, CachedDirectoryEntry> = new Map<string, CachedDirectoryEntry>();
  private downloadCache: Map<string, CachedDownloadEntry> = new Map<string, CachedDownloadEntry>();

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

    this.rootDir = `${this.sandboxManager.getDirectory('files')}/network_folder`;
    this.downloadsDir = `${this.sandboxManager.getDirectory('cache')}/network_folder/downloads`;
    this.stateFilePath = `${this.rootDir}/${STATE_FILE_NAME}`;

    this.ensureDir(this.rootDir);
    this.ensureDir(this.downloadsDir);

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
    if (index >= 0) {
      const existing = this.connections[index];
      const updatedConnection = this.cloneConnection(normalized);
      updatedConnection.createdAt = existing.createdAt;
      updatedConnection.lastUsedAt = existing.lastUsedAt;
      this.connections[index] = updatedConnection;
    } else {
      this.connections.push(normalized);
    }
    await this.persistConnections();
    logger.info(TAG, `网络连接配置已保存：${normalized.name}`);
  }

  public async deleteConnection(connectionId: string): Promise<void> {
    this.ensureInitialized();
    logger.info(TAG, `删除网络连接：${connectionId}`);
    this.connections = this.connections.filter((item: NetworkFolderConnection) => item.id !== connectionId);
    this.lastPaths.delete(connectionId);
    if (this.lastConnectionId === connectionId) {
      this.lastConnectionId = '';
    }
    await this.clearCacheForConnection(connectionId);
    await this.persistConnections();
    await this.persistLastState();
    logger.info(TAG, `网络连接已删除：${connectionId}`);
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

    if (connection.protocol === 'ftp' || connection.protocol === 'ftps') {
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
    } else if (connection.protocol === 'ftp' || connection.protocol === 'ftps') {
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
    if (!isNetworkFolderImportSupported(entry.importCategory)) {
      return this.buildDownloadFailure('当前文件类型暂不支持缓存或导入');
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

    const connectionDir = this.getConnectionDownloadsDir(connectionId);
    this.ensureDir(connectionDir);

    const finalPath = `${connectionDir}/${this.buildDownloadFileName(connectionId, normalizedRelativePath, versionTag, entry.name)}`;
    const tempPath = `${finalPath}.part`;
    this.deleteFileIfExists(tempPath);
    this.deleteFileIfExists(finalPath);

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
      } else if (connection.protocol === 'ftp' || connection.protocol === 'ftps') {
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

      fs.renameSync(tempPath, finalPath);
      const stat = fs.statSync(finalPath);
      const nextCachedEntry: CachedDownloadEntry = {
        connectionId: connectionId,
        relativePath: normalizedRelativePath,
        localPath: finalPath,
        fileName: entry.name,
        size: Number(stat.size) || entry.size || 0,
        versionTag: versionTag,
        cachedAt: now,
        lastAccessedAt: now
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
    this.deleteDirectoryIfExists(connectionDir);
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
    this.deleteDirectoryContents(this.downloadsDir);
    await this.persistCacheState();
    logger.info(TAG, '全部网络文件夹缓存清理完成');
  }

  private async browseWebDAV(
    connection: NetworkFolderConnection,
    relativePath: string
  ): Promise<NetworkFolderBrowseResult> {
    const client = new WebDAVNativeClient(this.buildWebDAVConfig(connection));
    try {
      const result: WebDAVNativeListResult = await client.getDirectoryContents(this.resolveWebDAVClientPath(relativePath));
      if (!result.success) {
        return {
          success: false,
          message: result.message || '加载 WebDAV 目录失败',
          entries: [],
          fromCache: false,
          stale: false,
          loadedAt: 0
        };
      }

      const entries = this.normalizeWebDAVEntries(connection, relativePath, result.files);
      return {
        success: true,
        message: result.message || `WebDAV 目录加载完成，共 ${entries.length} 项`,
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
    } finally {
      client.destroy();
    }
  }

  private async browseFTP(
    connection: NetworkFolderConnection,
    relativePath: string
  ): Promise<NetworkFolderBrowseResult> {
    const client = new FTPNativeClient(this.buildFTPConfig(connection));
    try {
      const result: FTPListResult = await client.listWithResult(this.resolveActualPath(connection, relativePath));
      if (!result.success) {
        return {
          success: false,
          message: result.message || '加载 FTP 目录失败',
          entries: [],
          fromCache: false,
          stale: false,
          loadedAt: 0
        };
      }

      const entries = this.normalizeFTPEntries(connection, relativePath, result.files);
      return {
        success: true,
        message: result.message || `FTP 目录加载完成，共 ${entries.length} 项`,
        entries: entries,
        fromCache: false,
        stale: false,
        loadedAt: Date.now()
      };
    } catch (error) {
      return {
        success: false,
        message: `加载 FTP 目录失败：${String(error)}`,
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

    try {
      const rawConnections = String(await this.pref!.get(CONNECTIONS_KEY, '[]'));
      const rawLastConnectionId = String(await this.pref!.get(LAST_CONNECTION_KEY, ''));
      const rawLastPaths = String(await this.pref!.get(LAST_PATHS_KEY, '[]'));

      const connectionArray = this.safeParseJson<NetworkFolderConnection[]>(rawConnections, []);
      connectionArray.forEach((item: NetworkFolderConnection) => {
        parsed.connections.push(this.normalizeConnection(item));
      });

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
  }

  private loadPersistedState(): void {
    this.directoryCache.clear();
    this.downloadCache.clear();

    if (!this.fileExists(this.stateFilePath)) {
      this.persistCacheStateSync();
      return;
    }

    try {
      const raw = fs.readTextSync(this.stateFilePath);
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
        this.downloadCache.set(this.buildDownloadCacheKey(item.connectionId, normalizedPath), {
          connectionId: item.connectionId,
          relativePath: normalizedPath,
          localPath: item.localPath || '',
          fileName: item.fileName || '',
          size: Number(item.size) || 0,
          versionTag: item.versionTag || '',
          cachedAt: Number(item.cachedAt) || 0,
          lastAccessedAt: Number(item.lastAccessedAt) || Number(item.cachedAt) || 0
        });
      });
    } catch (error) {
      logger.error(TAG, `加载网络缓存状态失败：${String(error)}`);
    }
  }

  private async pruneCaches(): Promise<void> {
    const now = Date.now();
    const validConnectionIds = this.buildConnectionIdSet();
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
      const invalid = !validConnectionIds.has(pair.value.connectionId) || !this.fileExists(pair.value.localPath);
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

  private async persistConnections(): Promise<void> {
    this.ensurePreferenceStore();
    await this.pref!.put(CONNECTIONS_KEY, JSON.stringify(this.connections));
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
      const file = fs.openSync(this.stateFilePath, fs.OpenMode.CREATE | fs.OpenMode.TRUNC | fs.OpenMode.WRITE_ONLY);
      try {
        fs.writeSync(file.fd, JSON.stringify(state));
      } finally {
        fs.closeSync(file);
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

  private normalizeConnection(connection: NetworkFolderConnection): NetworkFolderConnection {
    const protocol = connection.protocol === 'ftp' || connection.protocol === 'ftps' || connection.protocol === 'smb'
      ? connection.protocol
      : 'webdav';
    return {
      id: String(connection.id || '').trim(),
      name: String(connection.name || '').trim(),
      protocol: protocol,
      serverUrl: String(connection.serverUrl || '').trim(),
      host: String(connection.host || '').trim(),
      shareName: String(connection.shareName || '').trim(),
      domain: String(connection.domain || '').trim(),
      clientIP: String(connection.clientIP || '').trim(),
      port: Number(connection.port) > 0
        ? Math.floor(Number(connection.port))
        : (protocol === 'ftps' ? 990 : protocol === 'ftp' ? 21 : protocol === 'smb' ? 445 : 443),
      username: String(connection.username || '').trim(),
      password: String(connection.password || ''),
      basePath: normalizeConnectionBasePath(connection.basePath || '/'),
      passive: connection.passive !== false,
      verifySSL: connection.verifySSL !== false,
      timeoutMs: Number(connection.timeoutMs) > 0 ? Math.floor(Number(connection.timeoutMs)) : 30000,
      createdAt: Number(connection.createdAt) || Date.now(),
      lastUsedAt: Number(connection.lastUsedAt) || 0
    };
  }

  private normalizeCachedEntry(entry: NetworkFolderEntry): NetworkFolderEntry {
    const relativePath = normalizeRelativeNetworkFolderPath(entry.relativePath || '/');
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
      importCategory: entry.importCategory || inferNetworkFolderImportCategory(entry.name || ''),
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

  private getConnectionDownloadsDir(connectionId: string): string {
    return `${this.downloadsDir}/${this.hashString(connectionId)}`;
  }

  private buildDownloadFileName(
    connectionId: string,
    relativePath: string,
    versionTag: string,
    fileName: string
  ): string {
    const safeName = sanitizeFileName(fileName, 'remote_file', 120);
    const hash = this.hashString(`${connectionId}|${relativePath}|${versionTag}`);
    return `${hash}_${safeName}`;
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
      fs.mkdirSync(path, true);
    }
  }

  private fileExists(path: string): boolean {
    if (!path || path.trim().length === 0) {
      return false;
    }
    try {
      return fs.accessSync(path);
    } catch (error) {
      return false;
    }
  }

  private deleteFileIfExists(path: string): void {
    if (!this.fileExists(path)) {
      return;
    }
    try {
      const stat = fs.statSync(path);
      if (!stat.isDirectory()) {
        fs.unlinkSync(path);
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
      const stat = fs.statSync(path);
      if (!stat.isDirectory()) {
        fs.unlinkSync(path);
        return;
      }
      this.deleteDirectoryContents(path);
      fs.rmdirSync(path);
    } catch (error) {
      logger.warn(TAG, `删除缓存目录失败：${path}，原因：${String(error)}`);
    }
  }

  private deleteDirectoryContents(path: string): void {
    if (!this.fileExists(path)) {
      return;
    }
    try {
      const names = fs.listFileSync(path);
      names.forEach((name: string) => {
        const childPath = `${path}/${name}`;
        const stat = fs.statSync(childPath);
        if (stat.isDirectory()) {
          this.deleteDirectoryIfExists(childPath);
        } else {
          fs.unlinkSync(childPath);
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
      return JSON.parse(raw) as T;
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
