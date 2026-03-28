import { logger } from '../../Utils/Logger';
import {
  NetworkFolderConnection,
  normalizeConnectionBasePath,
  normalizeRelativeNetworkFolderPath
} from '../../Models/NetworkFolderModels';
import {
  SMBNativeClient,
  SMBNativeConfig,
  SMBNativeFileInfo,
  SMBNativeListResult,
  SMBNativeResult
} from './SMBNativeClient';

const TAG = 'SMBClientAdapter';
const FILE_ATTRIBUTE_DIRECTORY = 0x00000010;
const DEFAULT_WORKSTATION = 'MANXIA_OHOS';

interface SMBAuthParts {
  domain: string;
  username: string;
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

export class SMBClientAdapter {
  public async testConnection(connectionInfo: NetworkFolderConnection): Promise<SMBOperationResult> {
    const client = new SMBNativeClient(this.buildConfig(connectionInfo));
    const remotePath = this.buildRemotePath(connectionInfo, '/');
    logger.info(TAG, `开始测试 SMB 连接：${connectionInfo.host}/${connectionInfo.shareName}`);

    try {
      const result: SMBNativeResult = await client.testConnection(remotePath);
      return {
        success: result.success,
        message: result.message.length > 0
          ? result.message
          : (result.success ? 'SMB 连接成功' : 'SMB 连接失败')
      };
    } finally {
      client.destroy();
    }
  }

  public async listDirectory(
    connectionInfo: NetworkFolderConnection,
    relativePath: string
  ): Promise<SMBDirectoryListResult> {
    const client = new SMBNativeClient(this.buildConfig(connectionInfo));
    const remotePath = this.buildRemotePath(connectionInfo, relativePath);
    logger.info(TAG, `开始读取 SMB 目录：${connectionInfo.host}/${connectionInfo.shareName} ${relativePath}`);

    try {
      const result: SMBNativeListResult = await client.list(remotePath);
      if (!result.success) {
        return {
          success: false,
          message: result.message.length > 0 ? result.message : '读取 SMB 目录失败',
          entries: []
        };
      }

      const entries = this.mapEntries(result.files);
      return {
        success: true,
        message: result.message.length > 0 ? result.message : `SMB 目录读取完成，共 ${entries.length} 项`,
        entries: entries
      };
    } finally {
      client.destroy();
    }
  }

  public async downloadFile(
    connectionInfo: NetworkFolderConnection,
    relativePath: string,
    localPath: string
  ): Promise<SMBOperationResult> {
    const client = new SMBNativeClient(this.buildConfig(connectionInfo));
    const remotePath = this.buildRemotePath(connectionInfo, relativePath);
    logger.info(TAG, `开始下载 SMB 文件：${connectionInfo.host}/${connectionInfo.shareName} ${relativePath}`);

    try {
      const result: SMBNativeResult = await client.download(remotePath, localPath);
      return {
        success: result.success,
        message: result.message.length > 0
          ? result.message
          : (result.success ? 'SMB 文件下载完成' : '下载 SMB 文件失败')
      };
    } finally {
      client.destroy();
    }
  }

  private buildConfig(connectionInfo: NetworkFolderConnection): SMBNativeConfig {
    const auth = this.normalizeAuth(connectionInfo.domain, connectionInfo.username);
    return {
      host: connectionInfo.host.trim(),
      shareName: connectionInfo.shareName.trim(),
      port: connectionInfo.port > 0 ? connectionInfo.port : 445,
      username: auth.username,
      password: connectionInfo.password,
      domain: auth.domain,
      workstation: this.buildWorkstation(connectionInfo.clientIP),
      timeoutMs: connectionInfo.timeoutMs > 0 ? connectionInfo.timeoutMs : 30000,
      enableEncryption: false
    };
  }

  private normalizeAuth(domainValue: string, usernameValue: string): SMBAuthParts {
    let domain = domainValue.trim();
    let username = usernameValue.trim();

    if (domain.length === 0) {
      const backslashIndex = username.indexOf('\\');
      if (backslashIndex > 0) {
        domain = username.substring(0, backslashIndex).trim();
        username = username.substring(backslashIndex + 1).trim();
      }
    }

    if (domain.length === 0) {
      const semicolonIndex = username.indexOf(';');
      if (semicolonIndex > 0) {
        domain = username.substring(0, semicolonIndex).trim();
        username = username.substring(semicolonIndex + 1).trim();
      }
    }

    return {
      domain: domain,
      username: username
    };
  }

  private buildWorkstation(clientIP: string): string {
    const trimmedValue = clientIP.trim();
    if (trimmedValue.length === 0) {
      return DEFAULT_WORKSTATION;
    }

    const isIpv4 = /^(\d{1,3}\.){3}\d{1,3}$/.test(trimmedValue);
    const isSimpleName = /^[A-Za-z0-9_-]+$/.test(trimmedValue);
    if (isSimpleName && !isIpv4) {
      return trimmedValue;
    }
    return DEFAULT_WORKSTATION;
  }

  private mapEntries(files: SMBNativeFileInfo[]): SMBDirectoryEntry[] {
    const entries: SMBDirectoryEntry[] = [];
    for (let index = 0; index < files.length; index++) {
      const file = files[index];
      const isDirectory = file.isDirectory;
      entries.push({
        name: file.name,
        isDirectory: isDirectory,
        size: isDirectory ? 0 : Math.max(0, Math.floor(file.size)),
        lastModified: Math.max(0, Math.floor(file.lastModified)),
        attributes: isDirectory ? FILE_ATTRIBUTE_DIRECTORY : 0
      });
    }
    return entries;
  }

  private buildRemotePath(connectionInfo: NetworkFolderConnection, relativePath: string): string {
    const basePath = normalizeConnectionBasePath(connectionInfo.basePath);
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

    return combinedPath.substring(1);
  }
}
