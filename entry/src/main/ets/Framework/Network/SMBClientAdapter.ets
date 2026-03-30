import { connection } from '@kit.NetworkKit';
import { logger } from '../../Utils/Logger';
import {
  NetworkFolderConnection,
  normalizeConnectionBasePath,
  normalizeRelativeNetworkFolderPath
} from '../../Models/NetworkFolderModels';
import {
  SMBJBridgeClient,
  SMBJBridgeConfig,
  SMBJBridgeDirectoryEntry,
  SMBJBridgeDirectoryListResult,
  SMBJBridgeOperationResult
} from './SMBJBridge';

const TAG = 'SMBClientAdapter';
const FILE_ATTRIBUTE_DIRECTORY = 0x00000010;
const DEFAULT_CLIENT_IP = '0.0.0.0';
const DEFAULT_PACKET_CONCURRENCY = 20;

interface SMBAuthParts {
  domain: string;
  username: string;
}

interface SMBAuthVariant {
  label: string;
  domain: string;
  username: string;
}

interface SMBResolvedConfig {
  authLabel: string;
  authKey: string;
  config: SMBJBridgeConfig;
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

export class SMBClientAdapter {
  private bridge: SMBJBridgeClient = new SMBJBridgeClient();
  private preferredAuthKeyByConnection: Map<string, string> = new Map<string, string>();

  public async testConnection(connectionInfo: NetworkFolderConnection): Promise<SMBOperationResult> {
    const configs = await this.buildConfigs(connectionInfo);
    const remotePath = this.buildRemotePath(connectionInfo, '/');
    const displayName = this.buildConnectionDisplayName(connectionInfo, configs);
    logger.info(TAG, `Testing SMB connection: ${displayName}, auth variants=${configs.length}`);

    let lastResult: SMBOperationResult = {
      success: false,
      message: 'SMB connection failed'
    };

    for (let index = 0; index < configs.length; index++) {
      const resolved = configs[index];
      logger.info(TAG, `Trying SMB auth [${index + 1}/${configs.length}] ${displayName} via ${resolved.authLabel}`);
      const result = await this.bridge.testConnection(resolved.config, remotePath);
      if (result.success) {
        this.rememberPreferredAuth(connectionInfo, resolved.authKey);
        logger.info(TAG, `SMB connection success: ${displayName}, auth=${resolved.authLabel}`);
        return this.toOperationResult(result);
      }

      lastResult = this.toOperationResult(result);
      logger.warn(TAG, `SMB auth failed [${index + 1}/${configs.length}] ${displayName}, auth=${resolved.authLabel}, reason=${result.message}`);
      if (!this.shouldRetryWithNextAuth(result.message) || index >= configs.length - 1) {
        break;
      }
    }

    logger.warn(TAG, `SMB connection failed: ${displayName}, reason=${lastResult.message}`);
    return lastResult;
  }

  public async listDirectory(
    connectionInfo: NetworkFolderConnection,
    relativePath: string
  ): Promise<SMBDirectoryListResult> {
    const configs = await this.buildConfigs(connectionInfo);
    const remotePath = this.buildRemotePath(connectionInfo, relativePath);
    const displayName = this.buildConnectionDisplayName(connectionInfo, configs);
    logger.info(TAG, `Listing SMB directory: ${displayName} ${relativePath}, auth variants=${configs.length}`);

    let lastResult: SMBDirectoryListResult = {
      success: false,
      message: 'SMB directory load failed',
      entries: []
    };

    for (let index = 0; index < configs.length; index++) {
      const resolved = configs[index];
      logger.info(TAG, `Trying SMB directory auth [${index + 1}/${configs.length}] ${displayName} ${relativePath}, auth=${resolved.authLabel}`);
      const result = await this.bridge.listDirectory(resolved.config, remotePath);
      if (result.success) {
        this.rememberPreferredAuth(connectionInfo, resolved.authKey);
        const entries = this.mapEntries(result.entries);
        logger.info(TAG, `SMB directory success: ${displayName} ${relativePath}, auth=${resolved.authLabel}, entries=${entries.length}`);
        return {
          success: true,
          message: result.message.length > 0 ? result.message : `SMB directory loaded: ${entries.length} entries`,
          entries: entries
        };
      }

      lastResult = {
        success: false,
        message: result.message.length > 0 ? result.message : 'SMB directory load failed',
        entries: []
      };
      logger.warn(TAG, `SMB directory auth failed [${index + 1}/${configs.length}] ${displayName} ${relativePath}, auth=${resolved.authLabel}, reason=${lastResult.message}`);
      if (!this.shouldRetryWithNextAuth(lastResult.message) || index >= configs.length - 1) {
        break;
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
    const configs = await this.buildConfigs(connectionInfo);
    const remotePath = this.buildRemotePath(connectionInfo, relativePath);
    const displayName = this.buildConnectionDisplayName(connectionInfo, configs);
    logger.info(TAG, `Downloading SMB file: ${displayName} ${relativePath} -> ${localPath}, auth variants=${configs.length}`);

    let lastResult: SMBOperationResult = {
      success: false,
      message: 'SMB download failed'
    };

    for (let index = 0; index < configs.length; index++) {
      const resolved = configs[index];
      logger.info(TAG, `Trying SMB download auth [${index + 1}/${configs.length}] ${displayName} ${relativePath}, auth=${resolved.authLabel}`);
      const result = await this.bridge.downloadFile(resolved.config, remotePath, localPath);
      if (result.success) {
        this.rememberPreferredAuth(connectionInfo, resolved.authKey);
        logger.info(TAG, `SMB download success: ${displayName} ${relativePath}, auth=${resolved.authLabel}`);
        return this.toOperationResult(result);
      }

      lastResult = this.toOperationResult(result);
      logger.warn(TAG, `SMB download auth failed [${index + 1}/${configs.length}] ${displayName} ${relativePath}, auth=${resolved.authLabel}, reason=${result.message}`);
      if (!this.shouldRetryWithNextAuth(result.message) || index >= configs.length - 1) {
        break;
      }
    }

    logger.warn(TAG, `SMB download failed: ${displayName} ${relativePath}, reason=${lastResult.message}`);
    return lastResult;
  }

  private async buildConfigs(connectionInfo: NetworkFolderConnection): Promise<SMBResolvedConfig[]> {
    const host = this.normalizeHost(connectionInfo.host);
    const shareName = this.normalizeShareName(host, connectionInfo.shareName);
    const clientIP = await this.resolveClientIP(connectionInfo.clientIP);
    const authVariants = this.buildAuthVariants(connectionInfo.domain, connectionInfo.username);
    const resolvedConfigs: SMBResolvedConfig[] = [];
    const seen = new Set<string>();

    for (let index = 0; index < authVariants.length; index++) {
      const auth = authVariants[index];
      const authKey = `${auth.domain}\u0000${auth.username}`;
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
          clientIP: clientIP,
          timeoutMs: connectionInfo.timeoutMs > 0 ? connectionInfo.timeoutMs : 30000,
          packetConcurrency: DEFAULT_PACKET_CONCURRENCY
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

  private toOperationResult(result: SMBJBridgeOperationResult): SMBOperationResult {
    return {
      success: result.success,
      message: result.message
    };
  }

  private buildAuthVariants(domainValue: string, usernameValue: string): SMBAuthVariant[] {
    const rawDomain = domainValue.trim();
    const rawUsername = usernameValue.trim();
    const variants: SMBAuthVariant[] = [];

    if (rawDomain.length > 0) {
      const strippedUser = this.stripDomainPrefix(rawDomain, rawUsername);
      variants.push({
        label: 'explicit-domain',
        domain: rawDomain,
        username: strippedUser
      });
      variants.push({
        label: 'explicit-domain-keep-username',
        domain: rawDomain,
        username: rawUsername
      });
      variants.push({
        label: 'domain-merged-into-username',
        domain: '',
        username: `${rawDomain}\\${strippedUser}`
      });
      return variants;
    }

    const backslashParts = this.trySplitUserAuth(rawUsername, '\\');
    if (backslashParts !== null) {
      variants.push({
        label: 'backslash-domain',
        domain: backslashParts.domain,
        username: backslashParts.username
      });
      variants.push({
        label: 'backslash-original',
        domain: '',
        username: rawUsername
      });
      return variants;
    }

    const semicolonParts = this.trySplitUserAuth(rawUsername, ';');
    if (semicolonParts !== null) {
      variants.push({
        label: 'semicolon-domain',
        domain: semicolonParts.domain,
        username: semicolonParts.username
      });
      variants.push({
        label: 'semicolon-original',
        domain: '',
        username: rawUsername
      });
      return variants;
    }

    const upnParts = this.trySplitUserPrincipalName(rawUsername);
    if (upnParts !== null) {
      variants.push({
        label: 'upn-original',
        domain: '',
        username: rawUsername
      });
      variants.push({
        label: 'upn-split-domain',
        domain: upnParts.domain,
        username: upnParts.username
      });
      return variants;
    }

    variants.push({
      label: 'local-account',
      domain: '',
      username: rawUsername
    });
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
    return {
      domain: domain,
      username: username
    };
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
    return {
      domain: domain,
      username: username
    };
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
    return `${host}\u0000${shareName}\u0000${connectionInfo.domain.trim()}\u0000${connectionInfo.username.trim()}`;
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

  private mapEntries(files: SMBJBridgeDirectoryEntry[]): SMBDirectoryEntry[] {
    const entries: SMBDirectoryEntry[] = [];
    for (let index = 0; index < files.length; index++) {
      const file = files[index];
      const isDirectory = file.isDirectory;
      entries.push({
        name: file.name,
        isDirectory: isDirectory,
        size: isDirectory ? 0 : Math.max(0, Math.floor(file.size)),
        lastModified: Math.max(0, Math.floor(file.lastModified)),
        attributes: isDirectory ? FILE_ATTRIBUTE_DIRECTORY : Math.max(0, Math.floor(file.attributes))
      });
    }
    return entries;
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

  private async resolveClientIP(clientIPValue: string): Promise<string> {
    const trimmedValue = clientIPValue.trim();
    if (this.isUsableIpv4(trimmedValue)) {
      return trimmedValue;
    }

    if (trimmedValue.length > 0) {
      logger.warn(TAG, `SMB client IP is not a usable IPv4 address, auto-detect instead: ${trimmedValue}`);
    }

    try {
      const netHandle = await connection.getDefaultNet();
      const properties = await connection.getConnectionProperties(netHandle);
      const linkAddresses = properties.linkAddresses || [];
      for (let index = 0; index < linkAddresses.length; index++) {
        const linkAddress = linkAddresses[index];
        const netAddress = linkAddress.address;
        const address = (netAddress.address || '').trim();
        const family = netAddress.family ?? 1;
        if (family === 1 && this.isUsableIpv4(address)) {
          logger.info(TAG, `Auto-detected SMB client IPv4: ${address}`);
          return address;
        }
      }
    } catch (error) {
      logger.warn(TAG, `Auto-detect SMB client IP failed: ${this.describeError(error as Object)}`);
    }

    logger.warn(TAG, `No usable SMB client IPv4 detected, fallback to ${DEFAULT_CLIENT_IP}`);
    return DEFAULT_CLIENT_IP;
  }

  private isUsableIpv4(address: string): boolean {
    if (!this.isIpv4(address)) {
      return false;
    }
    if (address === DEFAULT_CLIENT_IP) {
      return false;
    }
    if (address.startsWith('127.')) {
      return false;
    }
    if (address.startsWith('169.254.')) {
      return false;
    }
    return true;
  }

  private isIpv4(address: string): boolean {
    const trimmed = address.trim();
    const parts = trimmed.split('.');
    if (parts.length !== 4) {
      return false;
    }
    for (let index = 0; index < parts.length; index++) {
      const part = parts[index];
      if (!/^\d{1,3}$/.test(part)) {
        return false;
      }
      const value = Number(part);
      if (!Number.isFinite(value) || value < 0 || value > 255) {
        return false;
      }
    }
    return true;
  }

  private describeError(error: Object): string {
    try {
      const serialized = JSON.stringify(error);
      if (serialized && serialized !== '{}') {
        return serialized;
      }
    } catch (_ignored) {
    }
    return String(error);
  }
}
