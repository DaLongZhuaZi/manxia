import { logger } from '../../Utils/Logger';
import webdavNativeModuleImport from 'libwebdav_native.so';

const TAG = 'SMBNativeClient';

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

interface NativeModule {
  smbInit(config: SMBNativeConfig): boolean;
  smbTestConnection(remotePath: string): SMBNativeResult;
  smbList(remotePath: string): SMBNativeListResult;
  smbDownload(remotePath: string, localPath: string): SMBNativeResult;
  smbDestroy(): void;
}

let nativeModule: NativeModule | null = null;
let nativeModuleError: string = '';
let nativeModuleChecked: boolean = false;

function checkNativeModule(): void {
  if (nativeModuleChecked) {
    return;
  }
  nativeModuleChecked = true;

  try {
    if (webdavNativeModuleImport && typeof webdavNativeModuleImport.smbInit === 'function') {
      nativeModule = webdavNativeModuleImport as NativeModule;
      logger.info(TAG, 'SMB 原生模块加载成功');
      return;
    }

    nativeModuleError = 'SMB 原生模块接口不完整';
    logger.warn(TAG, nativeModuleError);
  } catch (error) {
    nativeModuleError = `SMB 原生模块加载失败: ${String(error)}`;
    logger.error(TAG, nativeModuleError);
  }
}

export function isSMBNativeAvailable(): boolean {
  checkNativeModule();
  return nativeModule !== null;
}

export function getSMBNativeError(): string {
  return nativeModuleError;
}

export class SMBNativeClient {
  private config: SMBNativeConfig;
  private initialized: boolean = false;

  constructor(config: SMBNativeConfig) {
    this.config = config;
  }

  public async initialize(): Promise<boolean> {
    checkNativeModule();
    if (!nativeModule) {
      logger.error(TAG, `SMB 原生模块不可用: ${nativeModuleError}`);
      return false;
    }

    try {
      logger.info(TAG, `初始化 SMB 原生客户端：${this.config.host}/${this.config.shareName}`);
      this.initialized = nativeModule.smbInit(this.config);
      if (!this.initialized) {
        logger.error(TAG, 'SMB 原生客户端初始化失败');
      }
      return this.initialized;
    } catch (error) {
      logger.error(TAG, `初始化 SMB 原生客户端异常: ${String(error)}`);
      return false;
    }
  }

  public async testConnection(remotePath: string = ''): Promise<SMBNativeResult> {
    if (!this.initialized) {
      await this.initialize();
    }

    if (!nativeModule) {
      return this.buildFailureResult(`SMB 原生模块不可用: ${nativeModuleError}`);
    }

    try {
      logger.info(TAG, `测试 SMB 连接：${this.config.host}/${this.config.shareName} ${remotePath}`);
      return nativeModule.smbTestConnection(remotePath);
    } catch (error) {
      return this.buildFailureResult(`SMB 连接测试失败: ${String(error)}`);
    }
  }

  public async list(remotePath: string = ''): Promise<SMBNativeListResult> {
    if (!this.initialized) {
      await this.initialize();
    }

    if (!nativeModule) {
      return {
        success: false,
        statusCode: 0,
        message: `SMB 原生模块不可用: ${nativeModuleError}`,
        files: []
      };
    }

    try {
      logger.info(TAG, `读取 SMB 目录：${this.config.host}/${this.config.shareName} ${remotePath}`);
      return nativeModule.smbList(remotePath);
    } catch (error) {
      return {
        success: false,
        statusCode: 0,
        message: `读取 SMB 目录失败: ${String(error)}`,
        files: []
      };
    }
  }

  public async download(remotePath: string, localPath: string): Promise<SMBNativeResult> {
    if (!this.initialized) {
      await this.initialize();
    }

    if (!nativeModule) {
      return this.buildFailureResult(`SMB 原生模块不可用: ${nativeModuleError}`);
    }

    try {
      logger.info(TAG, `下载 SMB 文件：${this.config.host}/${this.config.shareName} ${remotePath}`);
      return nativeModule.smbDownload(remotePath, localPath);
    } catch (error) {
      return this.buildFailureResult(`下载 SMB 文件失败: ${String(error)}`);
    }
  }

  public destroy(): void {
    if (nativeModule) {
      try {
        nativeModule.smbDestroy();
      } catch (error) {
        logger.warn(TAG, `销毁 SMB 原生客户端失败: ${String(error)}`);
      }
    }
    this.initialized = false;
  }

  private buildFailureResult(message: string): SMBNativeResult {
    return {
      success: false,
      statusCode: 0,
      message: message,
      data: ''
    };
  }
}
