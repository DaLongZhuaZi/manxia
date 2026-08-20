/**
 * FTP Native Client ArkTS Wrapper
 * 封装Native C++ libcurl模块，提供 FTP/FTPS/SFTP 协议支持
 * 
 * 支持的协议操作：
 * - 连接测试
 * - 目录列表
 * - 上传文件
 * - 下载文件
 * - 删除文件
 * - 创建目录
 * - 删除目录
 * 
 * 文件路径: entry/src/main/ets/Framework/FTP/FTPNativeClient.ets
 */

import { logger } from 'manxia_core/src/main/ets/Utils/Logger';
import webdavNativeModuleImport from 'libwebdav_native.so';

const TAG = 'FTPNativeClient';

/**
 * FTP配置接口
 */
export interface FTPConfig {
  host: string;
  port: number;
  username: string;
  password: string;
  useFTPS: boolean; // 是否使用FTPS (FTP over SSL)
  useSFTP?: boolean; // 是否使用SFTP (SSH File Transfer Protocol)
  passive: boolean; // 是否使用被动模式
  timeoutMs?: number;
}

/**
 * FTP文件信息接口
 */
export interface FTPFileInfo {
  name: string;
  path: string;
  size: number;
  isDirectory: boolean;
  lastModified: number;
  permissions: string;
}

/**
 * FTP操作结果接口
 */
export interface FTPResult {
  success: boolean;
  message: string;
  data?: string;
}

/**
 * FTP目录列表结果接口
 */
export interface FTPListResult {
  success: boolean;
  message: string;
  files: FTPFileInfo[];
}

/**
 * Native模块接口（复用WebDAV模块的底层libcurl）
 */
interface NativeModule {
  // FTP专用方法
  ftpInit(config: FTPConfig): boolean;
  ftpTestConnection(): FTPResult;
  ftpList(remotePath: string): FTPListResult;
  ftpUpload(localPath: string, remotePath: string): FTPResult;
  ftpDownload(remotePath: string, localPath: string): FTPResult;
  ftpDelete(remotePath: string): FTPResult;
  ftpMkdir(remotePath: string): FTPResult;
  ftpRmdir(remotePath: string): FTPResult;
  ftpDestroy(): void;
}

// Native模块状态
let nativeModule: NativeModule | null = null;
let nativeModuleError: string = '';
let moduleChecked: boolean = false;

// 检查Native模块
function checkNativeModule(): void {
  if (moduleChecked) return;
  moduleChecked = true;
  
  try {
    if (webdavNativeModuleImport) {
      const mod = webdavNativeModuleImport as NativeModule;
      // 检查是否有FTP专用方法
      if (typeof mod.ftpInit === 'function') {
        nativeModule = mod;
        logger.info(TAG, 'FTP Native模块加载成功');
      } else {
        nativeModuleError = 'FTP NAPI接口未找到';
        logger.warn(TAG, nativeModuleError);
      }
    } else {
      nativeModuleError = 'Native模块未加载';
      logger.warn(TAG, nativeModuleError);
    }
  } catch (e) {
    nativeModuleError = `Native模块加载失败: ${String(e)}`;
    logger.error(TAG, nativeModuleError);
  }
}

/**
 * 检查FTP Native模块是否可用
 */
export function isFTPNativeAvailable(): boolean {
  checkNativeModule();
  return nativeModule !== null;
}

/**
 * 获取FTP Native模块错误信息
 */
export function getFTPNativeError(): string {
  return nativeModuleError || 'FTP功能需要在Native层添加支持';
}

/**
 * FTP Native客户端类
 */
export class FTPNativeClient {
  private config: FTPConfig;
  private initialized: boolean = false;
  private currentPath: string = '/';

  constructor(config: FTPConfig) {
    this.config = config;
  }

  /**
   * 获取FTP URL
   */
  private getFTPUrl(path: string = ''): string {
    const useSFTP = this.config.useSFTP === true;
    const protocol = useSFTP ? 'sftp' : (this.config.useFTPS ? 'ftps' : 'ftp');
    const port = this.config.port || (useSFTP ? 22 : (this.config.useFTPS ? 990 : 21));
    const fullPath = path.startsWith('/') ? path : `/${path}`;
    return `${protocol}://${this.config.host}:${port}${fullPath}`;
  }

  /**
   * 初始化客户端
   */
  async initialize(): Promise<boolean> {
    checkNativeModule();
    
    if (!nativeModule) {
      logger.error(TAG, 'Native模块未加载');
      return false;
    }

    try {
      const protocol = this.config.useSFTP === true ? 'sftp' : (this.config.useFTPS ? 'ftps' : 'ftp');
      logger.info(TAG, `初始化FTP客户端: ${protocol}://${this.config.host}:${this.config.port}`);
      
      const initConfig: FTPConfig = {
        host: this.config.host,
        port: this.config.port,
        username: this.config.username,
        password: this.config.password,
        useFTPS: this.config.useFTPS,
        useSFTP: this.config.useSFTP === true,
        passive: this.config.passive,
        timeoutMs: this.config.timeoutMs || 30000
      };
      const result = nativeModule.ftpInit(initConfig);
      
      this.initialized = result;
      return result;
    } catch (error) {
      logger.error(TAG, `初始化失败: ${error}`);
      return false;
    }
  }

  /**
   * 测试连接
   */
  async testConnection(): Promise<FTPResult> {
    if (!this.initialized) {
      await this.initialize();
    }

    if (!nativeModule) {
      return {
        success: false,
        message: `FTP Native模块未加载: ${nativeModuleError}`
      };
    }

    try {
      logger.info(TAG, '测试FTP连接');
      return nativeModule.ftpTestConnection();
    } catch (error) {
      logger.error(TAG, `连接测试失败: ${error}`);
      return {
        success: false,
        message: `连接测试失败: ${error}`
      };
    }
  }

  /**
   * 获取目录列表
   */
  async list(remotePath: string = '/'): Promise<FTPFileInfo[]> {
    if (!this.initialized) {
      await this.initialize();
    }

    if (!nativeModule) {
      logger.warn(TAG, 'FTP Native模块未加载');
      return [];
    }

    try {
      logger.info(TAG, `获取目录列表: ${remotePath}`);
      const result = nativeModule.ftpList(remotePath);
      
      if (result.success) {
        this.currentPath = remotePath;
        return result.files;
      } else {
        logger.warn(TAG, `获取目录列表失败: ${result.message}`);
        return [];
      }
    } catch (error) {
      logger.error(TAG, `获取目录列表失败: ${error}`);
      return [];
    }
  }

  /**
   * 获取目录列表结果（保留错误信息）
   */
  async listWithResult(remotePath: string = '/'): Promise<FTPListResult> {
    if (!this.initialized) {
      await this.initialize();
    }

    if (!nativeModule) {
      const message = `FTP Native模块未加载: ${nativeModuleError}`;
      logger.warn(TAG, message);
      return {
        success: false,
        message: message,
        files: []
      };
    }

    try {
      logger.info(TAG, `获取目录列表结果: ${remotePath}`);
      const result = nativeModule.ftpList(remotePath);
      if (result.success) {
        this.currentPath = remotePath;
      }
      return result;
    } catch (error) {
      const message = `获取目录列表失败: ${error}`;
      logger.error(TAG, message);
      return {
        success: false,
        message: message,
        files: []
      };
    }
  }

  /**
   * 上传文件
   */
  async upload(localPath: string, remotePath: string): Promise<FTPResult> {
    if (!this.initialized) {
      await this.initialize();
    }

    if (!nativeModule) {
      return {
        success: false,
        message: `FTP Native模块未加载: ${nativeModuleError}`
      };
    }

    try {
      logger.info(TAG, `上传文件: ${localPath} -> ${remotePath}`);
      return nativeModule.ftpUpload(localPath, remotePath);
    } catch (error) {
      logger.error(TAG, `上传失败: ${error}`);
      return {
        success: false,
        message: `上传失败: ${error}`
      };
    }
  }

  /**
   * 下载文件
   */
  async download(remotePath: string, localPath: string): Promise<FTPResult> {
    if (!this.initialized) {
      await this.initialize();
    }

    if (!nativeModule) {
      return {
        success: false,
        message: `FTP Native模块未加载: ${nativeModuleError}`
      };
    }

    try {
      logger.info(TAG, `下载文件: ${remotePath} -> ${localPath}`);
      return nativeModule.ftpDownload(remotePath, localPath);
    } catch (error) {
      logger.error(TAG, `下载失败: ${error}`);
      return {
        success: false,
        message: `下载失败: ${error}`
      };
    }
  }

  /**
   * 删除文件
   */
  async deleteFile(remotePath: string): Promise<FTPResult> {
    if (!this.initialized) {
      await this.initialize();
    }

    if (!nativeModule) {
      return {
        success: false,
        message: `FTP Native模块未加载: ${nativeModuleError}`
      };
    }

    try {
      logger.info(TAG, `删除文件: ${remotePath}`);
      return nativeModule.ftpDelete(remotePath);
    } catch (error) {
      logger.error(TAG, `删除失败: ${error}`);
      return {
        success: false,
        message: `删除失败: ${error}`
      };
    }
  }

  /**
   * 创建目录
   */
  async mkdir(remotePath: string): Promise<FTPResult> {
    if (!this.initialized) {
      await this.initialize();
    }

    if (!nativeModule) {
      return {
        success: false,
        message: `FTP Native模块未加载: ${nativeModuleError}`
      };
    }

    try {
      logger.info(TAG, `创建目录: ${remotePath}`);
      return nativeModule.ftpMkdir(remotePath);
    } catch (error) {
      logger.error(TAG, `创建目录失败: ${error}`);
      return {
        success: false,
        message: `创建目录失败: ${error}`
      };
    }
  }

  /**
   * 删除目录
   */
  async rmdir(remotePath: string): Promise<FTPResult> {
    if (!this.initialized) {
      await this.initialize();
    }

    if (!nativeModule) {
      return {
        success: false,
        message: `FTP Native模块未加载: ${nativeModuleError}`
      };
    }

    try {
      logger.info(TAG, `删除目录: ${remotePath}`);
      return nativeModule.ftpRmdir(remotePath);
    } catch (error) {
      logger.error(TAG, `删除目录失败: ${error}`);
      return {
        success: false,
        message: `删除目录失败: ${error}`
      };
    }
  }

  /**
   * 获取当前路径
   */
  getCurrentPath(): string {
    return this.currentPath;
  }

  /**
   * 设置当前路径
   */
  setCurrentPath(path: string): void {
    this.currentPath = path;
  }

  /**
   * 销毁客户端
   */
  destroy(): void {
    if (nativeModule?.ftpDestroy) {
      nativeModule.ftpDestroy();
    }
    this.initialized = false;
    logger.info(TAG, 'FTP客户端已销毁');
  }
}

/**
 * 默认FTP配置
 */
export const DEFAULT_FTP_CONFIG: FTPConfig = {
  host: '',
  port: 21,
  username: '',
  password: '',
  useFTPS: false,
  useSFTP: false,
  passive: true,
  timeoutMs: 30000
};
