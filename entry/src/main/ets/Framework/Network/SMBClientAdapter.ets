import { connection } from '@kit.NetworkKit';
import { logger } from '../../Utils/Logger';
import {
  NetworkFolderConnection,
  normalizeConnectionBasePath,
  normalizeRelativeNetworkFolderPath
} from '../../Models/NetworkFolderModels';
import webdavNativeModuleImport from 'libwebdav_native.so';

const TAG = 'SMBClientAdapter';
const FILE_ATTRIBUTE_DIRECTORY = 0x00000010;
const DEFAULT_CLIENT_IP = '0.0.0.0';

interface SMBAuthParts {
  domain: string;
  username: string;
}

interface SMBAuthVariant {
  label: string;
  domain: string;
  username: string;
}

interface SMBNativeConfig {
  host: string;
  shareName: string;
  port: number;
  username: string;
  password: string;
  domain: string;
  workstation: string;
  timeoutMs: number;
  enableEncryption: boolean;
}

interface SMBResolvedConfig {
  authLabel: string;
  authKey: string;
  config: SMBNativeConfig;
}

interface SMBNativeResult {
  success: boolean;
  statusCode: number;
  message: string;
  data: string;
}

interface SMBNativeFileInfo {
  path: string;
  name: string;
  size: number;
  lastModified: number;
  isDirectory: boolean;
}

interface SMBNativeListResult {
  success: boolean;
  statusCode: number;
  message: string;
  files: SMBNativeFileInfo[];
}

interface NativeModule {
  smbInit(config: SMBNativeConfig): boolean;
  smbTestConnection(remotePath: string): SMBNativeResult;
  smbList(remotePath: string): SMBNativeListResult;
  smbDownload(remotePath: string, localPath: string): SMBNativeResult;
  smbDestroy(): void;
}

export interface SMBDirectoryEntry {
  name: string;
  isDirectory: boolean;
  size: number;
  lastModified: number;
  attributes: number;
}

export interface SMBOperationResult {
  success: boolean;
  message: string;
}

export interface SMBDirectoryListResult extends SMBOperationResult {
  entries: SMBDirectoryEntry[];
}

export function isSMBFeatureEnabled(): boolean {
  return true;
}

let nativeModule: NativeModule | null = null;
let nativeModuleChecked: boolean = false;

function getNativeModule(): NativeModule | null {
  if (nativeModuleChecked) {
    return nativeModule;
  }
  nativeModuleChecked = true;
  try {
    if (webdavNativeModuleImport) {
      const mod = webdavNativeModuleImport as NativeModule;
      if (typeof mod.smbInit === 'function') {
        nativeModule = mod;
        logger.info(TAG, 'SMB Native模块加载成功');
      } else {
        logger.warn(TAG, 'SMB Native方法不可用');
      }
    }
  } catch (error) {
    logger.error(TAG, `SMB Native模块加载失败：${String(error)}`);
  }
  return nativeModule;
}

export class SMBClientAdapter {
  private preferredAuthKeyByConnection: Map<string, string> = new Map<string, string>();

  public async testConnection(connectionInfo: NetworkFolderConnection): Promise<SMBOperationResult> {
    const mod = getNativeModule();
    if (!mod) {
      return { success: false, message: 'SMB Native模块未加载' };
    }

    const configs = this.buildConfigs(connectionInfo);
    const displayName = this.buildConnectionDisplayName(connectionInfo, configs);
    logger.info(TAG, `Testing SMB connection: ${displayName}, auth variants=${configs.length}`);

    let lastResult: SMBOperationResult = { success: false, message: 'SMB connection failed' };

    for (let index = 0; index < configs.length; index++) {
      const resolved = configs[index];
      logger.info(TAG, `Trying SMB auth [${index + 1}/${configs.length}] ${displayName} via ${resolved.authLabel}`);

      try {
        mod.smbInit(resolved.config);
        const result = mod.smbTestConnection('');
        mod.smbDestroy();

        if (result.success) {
          this.rememberPreferredAuth(connectionInfo, resolved.authKey);
          logger.info(TAG, `SMB connection success: ${displayName}, auth=${resolved.authLabel}`);
          return { success: true, message: result.message.length > 0 ? result.message : '连接成功' };
        }

        lastResult = { success: false, message: result.message.length > 0 ? result.message : 'SMB连接失败' };
        logger.warn(TAG, `SMB auth failed [${index + 1}/${configs.length}] ${displayName}, auth=${resolved.authLabel}, reason=${lastResult.message}`);

        if (!this.shouldRetryWithNextAuth(lastResult.message) || index >= configs.length - 1) {
          break;
        }
      } catch (error) {
        try { mod.smbDestroy(); } catch (_e) { /* ignore */ }
        lastResult = { success: false, message: String(error) };
        logger.warn(TAG, `SMB auth exception [${index + 1}/${configs.length}] ${displayName}: ${lastResult.message}`);
        if (!this.shouldRetryWithNextAuth(lastResult.message) || index >= configs.length - 1) {
          break;
        }
      }
    }

    logger.warn(TAG, `SMB connection failed: ${displayName}, reason=${lastResult.message}`);
    return lastResult;
  }

  public async listDirectory(
    connectionInfo: NetworkFolderConnection,
    relativePath: string
  ): Promise<SMBDirectoryListResult> {
    const mod = getNativeModule();
    if (!mod) {
      return { success: false, message: 'SMB Native模块未加载', entries: [] };
    }

    const configs = this.buildConfigs(connectionInfo);
    const remotePath = this.buildRemotePath(connectionInfo, relativePath);
    const displayName = this.buildConnectionDisplayName(connectionInfo, configs);
    logger.info(TAG, `Listing SMB directory: ${displayName} ${relativePath}, auth variants=${configs.length}`);

    let lastResult: SMBDirectoryListResult = { success: false, message: 'SMB directory load failed', entries: [] };

    for (let index = 0; index < configs.length; index++) {
      const resolved = configs[index];
      logger.info(TAG, `Trying SMB directory auth [${index + 1}/${configs.length}] ${displayName} ${relativePath}, auth=${resolved.authLabel}`);

      try {
        mod.smbInit(resolved.config);
        const result = mod.smbList(remotePath);
        mod.smbDestroy();

        if (result.success) {
          this.rememberPreferredAuth(connectionInfo, resolved.authKey);
          const entries = this.mapNativeEntries(result.files);
          logger.info(TAG, `SMB directory success: ${displayName} ${relativePath}, auth=${resolved.authLabel}, entries=${entries.length}`);
          return {
            success: true,
            message: result.message.length > 0 ? result.message : `SMB directory loaded: ${entries.length} entries`,
            entries: entries
          };
        }

        lastResult = { success: false, message: result.message.length > 0 ? result.message : 'SMB directory load failed', entries: [] };
        logger.warn(TAG, `SMB directory auth failed [${index + 1}/${configs.length}] ${displayName} ${relativePath}, auth=${resolved.authLabel}, reason=${lastResult.message}`);
        if (!this.shouldRetryWithNextAuth(lastResult.message) || index >= configs.length - 1) {
          break;
        }
      } catch (error) {
        try { mod.smbDestroy(); } catch (_e) { /* ignore */ }
        lastResult = { success: false, message: String(error), entries: [] };
        logger.warn(TAG, `SMB directory exception [${index + 1}/${configs.length}] ${displayName} ${relativePath}: ${lastResult.message}`);
        if (!this.shouldRetryWithNextAuth(lastResult.message) || index >= configs.length - 1) {
          break;
        }
      }
    }

    logger.warn(TAG, `SMB directory failed: ${displayName} ${relativePath}, reason=${lastResult.message}`);
    return lastResult;
  }

  public async downloadFile(
    connectionInfo: NetworkFolderConnection,
    relativePath: string,
    localPath: string
  ): Promise<SMBOperationResult> {
    const mod = getNativeModule();
    if (!mod) {
      return { success: false, message: 'SMB Native模块未加载' };
    }

    const configs = this.buildConfigs(connectionInfo);
    const remotePath = this.buildRemotePath(connectionInfo, relativePath);
    const displayName = this.buildConnectionDisplayName(connectionInfo, configs);
    logger.info(TAG, `Downloading SMB file: ${displayName} ${relativePath} -> ${localPath}, auth variants=${configs.length}`);

    let lastResult: SMBOperationResult = { success: false, message: 'SMB download failed' };

    for (let index = 0; index < configs.length; index++) {
      const resolved = configs[index];
      logger.info(TAG, `Trying SMB download auth [${index + 1}/${configs.length}] ${displayName} ${relativePath}, auth=${resolved.authLabel}`);

      try {
        mod.smbInit(resolved.config);
        const result = mod.smbDownload(remotePath, localPath);
        mod.smbDestroy();

        if (result.success) {
          this.rememberPreferredAuth(connectionInfo, resolved.authKey);
          logger.info(TAG, `SMB download success: ${displayName} ${relativePath}, auth=${resolved.authLabel}`);
          return { success: true, message: result.message.length > 0 ? result.message : '下载完成' };
        }

        lastResult = { success: false, message: result.message.length > 0 ? result.message : 'SMB download failed' };
        logger.warn(TAG, `SMB download auth failed [${index + 1}/${configs.length}] ${displayName} ${relativePath}, auth=${resolved.authLabel}, reason=${lastResult.message}`);
        if (!this.shouldRetryWithNextAuth(lastResult.message) || index >= configs.length - 1) {
          break;
        }
      } catch (error) {
        try { mod.smbDestroy(); } catch (_e) { /* ignore */ }
        lastResult = { success: false, message: String(error) };
        logger.warn(TAG, `SMB download exception [${index + 1}/${configs.length}] ${displayName} ${relativePath}: ${lastResult.message}`);
        if (!this.shouldRetryWithNextAuth(lastResult.message) || index >= configs.length - 1) {
          break;
        }
      }
    }

    logger.warn(TAG, `SMB download failed: ${displayName} ${relativePath}, reason=${lastResult.message}`);
    return lastResult;
  }

  private buildConfigs(connectionInfo: NetworkFolderConnection): SMBResolvedConfig[] {
    const host = this.normalizeHost(connectionInfo.host);
    const shareName = this.normalizeShareName(host, connectionInfo.shareName);
    const authVariants = this.buildAuthVariants(connectionInfo.domain, connectionInfo.username);
    const resolvedConfigs: SMBResolvedConfig[] = [];
    const seen = new Set<string>();

    for (let index = 0; index < authVariants.length; index++) {
      const auth = authVariants[index];
      const authKey = `${auth.domain} ${auth.username}`;
      if (seen.has(authKey)) {
        continue;
      }
      seen.add(authKey);
      resolvedConfigs.push({
        authLabel: auth.label,
        authKey: authKey,
        config: {
          host: host,
          shareName: shareName,
          port: connectionInfo.port > 0 ? connectionInfo.port : 445,
          username: auth.username,
          password: connectionInfo.password,
          domain: auth.domain,
          workstation: 'MANXIA_OHOS',
          timeoutMs: connectionInfo.timeoutMs > 0 ? connectionInfo.timeoutMs : 30000,
          enableEncryption: false
        }
      });
    }

    const preferredAuthKey = this.preferredAuthKeyByConnection.get(this.buildConnectionCacheKey(connectionInfo));
    if (preferredAuthKey && resolvedConfigs.length > 1) {
      resolvedConfigs.sort((left: SMBResolvedConfig, right: SMBResolvedConfig) => {
        if (left.authKey === preferredAuthKey && right.authKey !== preferredAuthKey) {
          return -1;
        }
        if (right.authKey === preferredAuthKey && left.authKey !== preferredAuthKey) {
          return 1;
        }
        return 0;
      });
    }

    return resolvedConfigs;
  }

  private mapNativeEntries(files: SMBNativeFileInfo[]): SMBDirectoryEntry[] {
    const entries: SMBDirectoryEntry[] = [];
    if (!Array.isArray(files)) {
      return entries;
    }
    for (let index = 0; index < files.length; index++) {
      const file = files[index];
      const isDir = file.isDirectory === true;
      entries.push({
        name: file.name,
        isDirectory: isDir,
        size: isDir ? 0 : Math.max(0, Math.floor(file.size)),
        lastModified: Math.max(0, Math.floor(file.lastModified)),
        attributes: isDir ? FILE_ATTRIBUTE_DIRECTORY : 0
      });
    }
    return entries;
  }

  private buildAuthVariants(domainValue: string, usernameValue: string): SMBAuthVariant[] {
    const rawDomain = domainValue.trim();
    const rawUsername = usernameValue.trim();
    const variants: SMBAuthVariant[] = [];

    if (rawDomain.length > 0) {
      const strippedUser = this.stripDomainPrefix(rawDomain, rawUsername);
      variants.push({ label: 'explicit-domain', domain: rawDomain, username: strippedUser });
      variants.push({ label: 'explicit-domain-keep-username', domain: rawDomain, username: rawUsername });
      variants.push({ label: 'domain-merged-into-username', domain: '', username: `${rawDomain}\\${strippedUser}` });
      return variants;
    }

    const backslashParts = this.trySplitUserAuth(rawUsername, '\\');
    if (backslashParts !== null) {
      variants.push({ label: 'backslash-domain', domain: backslashParts.domain, username: backslashParts.username });
      variants.push({ label: 'backslash-original', domain: '', username: rawUsername });
      return variants;
    }

    const semicolonParts = this.trySplitUserAuth(rawUsername, ';');
    if (semicolonParts !== null) {
      variants.push({ label: 'semicolon-domain', domain: semicolonParts.domain, username: semicolonParts.username });
      variants.push({ label: 'semicolon-original', domain: '', username: rawUsername });
      return variants;
    }

    const upnParts = this.trySplitUserPrincipalName(rawUsername);
    if (upnParts !== null) {
      variants.push({ label: 'upn-original', domain: '', username: rawUsername });
      variants.push({ label: 'upn-split-domain', domain: upnParts.domain, username: upnParts.username });
      return variants;
    }

    variants.push({ label: 'local-account', domain: '', username: rawUsername });
    return variants;
  }

  private trySplitUserAuth(usernameValue: string, separator: string): SMBAuthParts | null {
    const separatorIndex = usernameValue.indexOf(separator);
    if (separatorIndex <= 0 || separatorIndex >= usernameValue.length - 1) {
      return null;
    }
    const domain = usernameValue.substring(0, separatorIndex).trim();
    const username = usernameValue.substring(separatorIndex + 1).trim();
    if (domain.length === 0 || username.length === 0) {
      return null;
    }
    return { domain, username };
  }

  private trySplitUserPrincipalName(usernameValue: string): SMBAuthParts | null {
    const atIndex = usernameValue.lastIndexOf('@');
    if (atIndex <= 0 || atIndex >= usernameValue.length - 1) {
      return null;
    }
    const username = usernameValue.substring(0, atIndex).trim();
    const domain = usernameValue.substring(atIndex + 1).trim();
    if (domain.length === 0 || username.length === 0) {
      return null;
    }
    if (domain.indexOf('/') >= 0 || domain.indexOf('\\') >= 0) {
      return null;
    }
    return { domain, username };
  }

  private stripDomainPrefix(domainValue: string, usernameValue: string): string {
    const normalizedUsername = usernameValue.trim();
    const normalizedDomain = domainValue.trim();
    const prefix = `${normalizedDomain}\\`;
    if (normalizedUsername.startsWith(prefix)) {
      return normalizedUsername.substring(prefix.length).trim();
    }
    const semicolonPrefix = `${normalizedDomain};`;
    if (normalizedUsername.startsWith(semicolonPrefix)) {
      return normalizedUsername.substring(semicolonPrefix.length).trim();
    }
    const upnSuffix = `@${normalizedDomain}`;
    if (normalizedUsername.endsWith(upnSuffix)) {
      return normalizedUsername.substring(0, normalizedUsername.length - upnSuffix.length).trim();
    }
    return normalizedUsername;
  }

  private shouldRetryWithNextAuth(message: string): boolean {
    const normalized = message.trim().toUpperCase();
    if (normalized.length === 0) {
      return true;
    }
    if (normalized.indexOf('LOGON') >= 0 || normalized.indexOf('ACCESS_DENIED') >= 0) {
      return true;
    }
    if (normalized.indexOf('AUTH') >= 0 || normalized.indexOf('CREDENTIAL') >= 0) {
      return true;
    }
    if (normalized.indexOf('ACCOUNT') >= 0 || normalized.indexOf('PASSWORD') >= 0) {
      return true;
    }
    return false;
  }

  private buildConnectionCacheKey(connectionInfo: NetworkFolderConnection): string {
    const host = this.normalizeHost(connectionInfo.host);
    const shareName = this.normalizeShareName(host, connectionInfo.shareName);
    return `${host} ${shareName} ${connectionInfo.domain.trim()} ${connectionInfo.username.trim()}`;
  }

  private rememberPreferredAuth(connectionInfo: NetworkFolderConnection, authKey: string): void {
    this.preferredAuthKeyByConnection.set(this.buildConnectionCacheKey(connectionInfo), authKey);
  }

  private buildConnectionDisplayName(
    connectionInfo: NetworkFolderConnection,
    configs: SMBResolvedConfig[]
  ): string {
    if (configs.length > 0) {
      return `${configs[0].config.host}/${configs[0].config.shareName}`;
    }
    const host = this.normalizeHost(connectionInfo.host);
    const shareName = this.normalizeShareName(host, connectionInfo.shareName);
    return `${host}/${shareName}`;
  }

  private normalizeHost(hostValue: string): string {
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

  private normalizeShareName(hostValue: string, shareValue: string): string {
    const normalizedHost = this.normalizeHost(hostValue);
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

  private buildRemotePath(connectionInfo: NetworkFolderConnection, relativePath: string): string {
    const normalizedShareName = this.normalizeShareName(connectionInfo.host, connectionInfo.shareName);
    let basePath = normalizeConnectionBasePath(connectionInfo.basePath);
    if (normalizedShareName.length > 0) {
      const sharePrefix = `/${normalizedShareName}`;
      const lowerBasePath = basePath.toLowerCase();
      const lowerSharePrefix = sharePrefix.toLowerCase();
      if (lowerBasePath === lowerSharePrefix) {
        basePath = '/';
      } else if (lowerBasePath.startsWith(`${lowerSharePrefix}/`)) {
        basePath = basePath.substring(sharePrefix.length);
      }
    }
    const normalizedRelativePath = normalizeRelativeNetworkFolderPath(relativePath);

    let combinedPath = '/';
    if (basePath === '/') {
      combinedPath = normalizedRelativePath;
    } else if (normalizedRelativePath === '/') {
      combinedPath = basePath;
    } else {
      combinedPath = `${basePath}${normalizedRelativePath}`;
    }

    if (combinedPath === '/') {
      return '';
    }

    return combinedPath.substring(1).replace(/\//g, '\\');
  }
}
