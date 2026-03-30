import { logger } from '../../Utils/Logger';
import {
  NetworkFolderConnection,
  normalizeRelativeNetworkFolderPath
} from '../../Models/NetworkFolderModels';
import {
  SMBClientAdapter,
  SMBDirectoryListResult,
  SMBOperationResult,
  isSMBFeatureEnabled
} from './SMBClientAdapter';

const TAG = 'SMBNativeClient';
const COMPAT_CONNECTION_ID = '__legacy_smb_native_client__';

export interface SMBNativeConfig {
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

export interface SMBNativeResult {
  success: boolean;
  statusCode: number;
  message: string;
  data: string;
}

export interface SMBNativeFileInfo {
  path: string;
  name: string;
  size: number;
  lastModified: number;
  isDirectory: boolean;
}

export interface SMBNativeListResult {
  success: boolean;
  statusCode: number;
  message: string;
  files: SMBNativeFileInfo[];
}

export function isSMBNativeAvailable(): boolean {
  return isSMBFeatureEnabled();
}

export function getSMBNativeError(): string {
  return '';
}

export class SMBNativeClient {
  private config: SMBNativeConfig;
  private initialized: boolean = false;
  private adapter: SMBClientAdapter = new SMBClientAdapter();

  constructor(config: SMBNativeConfig) {
    this.config = config;
  }

  public async initialize(): Promise<boolean> {
    const validationMessage = this.validateConfig();
    if (validationMessage.length > 0) {
      logger.error(TAG, validationMessage);
      this.initialized = false;
      return false;
    }

    logger.info(TAG, `SMB client ready via @ohos/smbj public entry: ${this.config.host.trim()}/${this.config.shareName.trim()}`);
    this.initialized = true;
    return true;
  }

  public async testConnection(remotePath: string = ''): Promise<SMBNativeResult> {
    const readyError = await this.ensureReady();
    if (readyError.length > 0) {
      return this.buildFailureResult(readyError);
    }

    try {
      const connection = this.buildCompatConnection();
      const normalizedPath = this.normalizeRemotePath(remotePath);
      logger.info(TAG, `Testing SMB connection via adapter: ${connection.host}/${connection.shareName} ${normalizedPath}`);

      if (normalizedPath !== '/') {
        const listResult: SMBDirectoryListResult = await this.adapter.listDirectory(connection, normalizedPath);
        return this.buildResultFromOperation(listResult);
      }

      const result: SMBOperationResult = await this.adapter.testConnection(connection);
      return this.buildResultFromOperation(result);
    } catch (error) {
      return this.buildFailureResult(`SMB connection failed: ${String(error)}`);
    }
  }

  public async list(remotePath: string = ''): Promise<SMBNativeListResult> {
    const readyError = await this.ensureReady();
    if (readyError.length > 0) {
      return this.buildListFailureResult(readyError);
    }

    try {
      const connection = this.buildCompatConnection();
      const normalizedPath = this.normalizeRemotePath(remotePath);
      logger.info(TAG, `Listing SMB directory via adapter: ${connection.host}/${connection.shareName} ${normalizedPath}`);
      const result: SMBDirectoryListResult = await this.adapter.listDirectory(connection, normalizedPath);
      if (!result.success) {
        return this.buildListFailureResult(result.message);
      }

      const files: SMBNativeFileInfo[] = [];
      for (let index = 0; index < result.entries.length; index++) {
        const entry = result.entries[index];
        const relativePrefix = normalizedPath === '/' ? '' : normalizedPath;
        files.push({
          path: entry.name.length > 0 ? `${relativePrefix}/${entry.name}` : normalizedPath,
          name: entry.name,
          size: entry.size,
          lastModified: entry.lastModified,
          isDirectory: entry.isDirectory
        });
      }

      return {
        success: true,
        statusCode: 0,
        message: result.message,
        files: files
      };
    } catch (error) {
      return this.buildListFailureResult(`SMB directory load failed: ${String(error)}`);
    }
  }

  public async download(remotePath: string, localPath: string): Promise<SMBNativeResult> {
    const readyError = await this.ensureReady();
    if (readyError.length > 0) {
      return this.buildFailureResult(readyError);
    }

    try {
      const connection = this.buildCompatConnection();
      const normalizedPath = this.normalizeRemotePath(remotePath);
      logger.info(TAG, `Downloading SMB file via adapter: ${connection.host}/${connection.shareName} ${normalizedPath}`);
      const result: SMBOperationResult = await this.adapter.downloadFile(connection, normalizedPath, localPath);
      return this.buildResultFromOperation(result);
    } catch (error) {
      return this.buildFailureResult(`SMB download failed: ${String(error)}`);
    }
  }

  public destroy(): void {
    if (this.initialized) {
      logger.info(TAG, 'SMB adapter client destroyed');
    }
    this.initialized = false;
  }

  private async ensureReady(): Promise<string> {
    if (this.initialized) {
      return '';
    }

    const initialized = await this.initialize();
    if (initialized) {
      return '';
    }
    return 'SMB initialization failed';
  }

  private validateConfig(): string {
    if (this.config.host.trim().length === 0) {
      return 'SMB host is required';
    }
    if (this.config.shareName.trim().length === 0) {
      return 'SMB share name is required';
    }
    return '';
  }

  private buildCompatConnection(): NetworkFolderConnection {
    const now = Date.now();
    return {
      id: COMPAT_CONNECTION_ID,
      name: `${this.config.host.trim()}/${this.config.shareName.trim()}`,
      protocol: 'smb',
      serverUrl: '',
      host: this.config.host.trim(),
      shareName: this.config.shareName.trim(),
      domain: this.config.domain.trim(),
      clientIP: '',
      port: this.config.port > 0 ? this.config.port : 445,
      username: this.config.username.trim(),
      password: this.config.password,
      basePath: '/',
      passive: true,
      verifySSL: false,
      timeoutMs: this.config.timeoutMs > 0 ? this.config.timeoutMs : 30000,
      createdAt: now,
      lastUsedAt: 0
    };
  }

  private normalizeRemotePath(remotePath: string): string {
    return normalizeRelativeNetworkFolderPath(remotePath.length > 0 ? remotePath : '/');
  }

  private buildResultFromOperation(result: SMBOperationResult): SMBNativeResult {
    if (!result.success) {
      return this.buildFailureResult(result.message);
    }
    return {
      success: true,
      statusCode: 0,
      message: result.message,
      data: ''
    };
  }

  private buildFailureResult(message: string): SMBNativeResult {
    return {
      success: false,
      statusCode: 0,
      message: message,
      data: ''
    };
  }

  private buildListFailureResult(message: string): SMBNativeListResult {
    return {
      success: false,
      statusCode: 0,
      message: message,
      files: []
    };
  }
}
