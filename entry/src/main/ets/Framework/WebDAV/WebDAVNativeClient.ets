/**
 * WebDAV Native Client ArkTS Wrapper
 * 封装Native C++ WebDAV模块，提供完整的WebDAV协议支持
 * 
 * 支持的WebDAV方法：
 * - PROPFIND: 获取目录列表和文件属性
 * - MKCOL: 创建目录
 * - PUT: 上传文件
 * - GET: 下载文件
 * - DELETE: 删除文件/目录
 * - COPY: 复制文件
 * - MOVE: 移动文件
 * 
 * 文件路径: entry/src/main/ets/Framework/WebDAV/WebDAVNativeClient.ets
 */

import { logger } from '../../Utils/Logger';
import webdavNativeModuleImport from 'libwebdav_native.so';

const TAG = 'WebDAVNativeClient';

/**
 * WebDAV配置接口
 */
export interface WebDAVNativeConfig {
  serverUrl: string;
  username: string;
  password: string;
  basePath: string;
  timeoutMs?: number;
  verifySSL?: boolean;
}

/**
 * 操作结果接口
 */
export interface WebDAVNativeResult {
  success: boolean;
  statusCode: number;
  message: string;
  data: string;
}

/**
 * 文件信息接口
 */
export interface WebDAVNativeFileInfo {
  path: string;
  name: string;
  size: number;
  lastModified: number;
  isDirectory: boolean;
  etag: string;
  contentType: string;
}

/**
 * 目录列表结果接口
 */
export interface WebDAVNativeListResult {
  success: boolean;
  statusCode: number;
  message: string;
  files: WebDAVNativeFileInfo[];
}

/**
 * 磁盘配额结果接口
 */
export interface WebDAVNativeQuotaResult {
  success: boolean;
  statusCode: number;
  message: string;
  usedBytes: number;
  availableBytes: number;
}

/**
 * 连接测试结果接口
 */
export interface WebDAVNativeTestResult {
  success: boolean;
  needCreateDir: boolean;
  message: string;
}

/**
 * 进度回调类型
 */
export type ProgressCallback = (current: number, total: number) => void;

/**
 * Native模块接口定义
 */
interface WebDAVNativeModule {
  init(config: WebDAVNativeConfig): boolean;
  testConnection(): WebDAVNativeResult;
  exists(remotePath: string): WebDAVNativeResult;
  list(remotePath: string, depth: number): WebDAVNativeListResult;
  createDirectory(remotePath: string): WebDAVNativeResult;
  createDirectoryRecursive(remotePath: string): WebDAVNativeResult;
  deleteResource(remotePath: string): WebDAVNativeResult;
  putFileContents(remotePath: string, data: string): WebDAVNativeResult;
  getFileContents(remotePath: string): WebDAVNativeResult;
  uploadFile(localPath: string, remotePath: string): WebDAVNativeResult;
  downloadFile(remotePath: string, localPath: string): WebDAVNativeResult;
  copyFile(sourcePath: string, destPath: string, overwrite: boolean): WebDAVNativeResult;
  moveFile(sourcePath: string, destPath: string, overwrite: boolean): WebDAVNativeResult;
  getQuota(): WebDAVNativeQuotaResult;
  destroy(): void;
}

// Native模块状态
let webdavNativeModule: WebDAVNativeModule | null = null;
let nativeModuleLoadError: string = '';
let nativeModuleChecked: boolean = false;

// 延迟检查Native模块是否可用
function checkNativeModule(): void {
  if (nativeModuleChecked) return;
  nativeModuleChecked = true;
  
  try {
    // 打印模块信息用于调试
    logger.info(TAG, `Native模块类型: ${typeof webdavNativeModuleImport}`);
    if (webdavNativeModuleImport) {
      const moduleObj = webdavNativeModuleImport as WebDAVNativeModule;
      const keys = Object.keys(webdavNativeModuleImport);
      logger.info(TAG, `Native模块导出的属性: ${keys.join(', ')}`);
      logger.info(TAG, `init类型: ${typeof moduleObj.init}`);
    }
    
    if (webdavNativeModuleImport && typeof webdavNativeModuleImport.init === 'function') {
      webdavNativeModule = webdavNativeModuleImport as WebDAVNativeModule;
      logger.info(TAG, 'WebDAV Native模块加载成功');
    } else {
      const moduleObj = webdavNativeModuleImport as WebDAVNativeModule;
      nativeModuleLoadError = `Native模块加载成功但接口不完整, init类型=${typeof moduleObj?.init}`;
      logger.warn(TAG, nativeModuleLoadError);
    }
  } catch (e) {
    nativeModuleLoadError = `Native模块检查失败: ${String(e)}`;
    logger.warn(TAG, `${nativeModuleLoadError}，将使用ArkTS客户端`);
  }
}

// 获取Native模块的辅助函数
function getNativeModule(): WebDAVNativeModule {
  checkNativeModule();
  if (!webdavNativeModule) {
    throw new Error(`WebDAV Native模块未加载: ${nativeModuleLoadError}`);
  }
  return webdavNativeModule;
}

/**
 * 检查Native模块是否可用
 */
export function isNativeModuleAvailable(): boolean {
  checkNativeModule();
  return webdavNativeModule !== null;
}

/**
 * 获取Native模块加载错误信息
 */
export function getNativeModuleError(): string {
  return nativeModuleLoadError;
}

/**
 * WebDAV Native客户端类
 * 使用Native C++实现，支持完整的WebDAV协议
 */
export class WebDAVNativeClient {
  private config: WebDAVNativeConfig;
  private initialized: boolean = false;

  constructor(config: WebDAVNativeConfig) {
    this.config = config;
  }

  /**
   * 初始化客户端
   */
  async initialize(): Promise<boolean> {
    try {
      logger.info(TAG, `初始化WebDAV Native客户端: ${this.config.serverUrl}`);
      
      const result: boolean = getNativeModule().init({
        serverUrl: this.config.serverUrl,
        username: this.config.username,
        password: this.config.password,
        basePath: this.config.basePath,
        timeoutMs: this.config.timeoutMs ?? 30000,
        verifySSL: this.config.verifySSL ?? true
      });
      
      this.initialized = result;
      
      if (result) {
        logger.info(TAG, 'WebDAV Native客户端初始化成功');
      } else {
        logger.error(TAG, 'WebDAV Native客户端初始化失败');
      }
      
      return result;
    } catch (error) {
      logger.error(TAG, `初始化失败: ${error}`);
      return false;
    }
  }

  /**
   * 测试连接
   */
  async testConnection(): Promise<WebDAVNativeTestResult> {
    if (!this.initialized) {
      await this.initialize();
    }
    
    try {
      logger.info(TAG, '测试WebDAV连接');
      const result: WebDAVNativeResult = getNativeModule().testConnection();
      
      logger.info(TAG, `连接测试结果: success=${result.success}, status=${result.statusCode}`);
      
      return {
        success: result.success,
        needCreateDir: result.statusCode === 404 || result.statusCode === 409,
        message: result.message
      };
    } catch (error) {
      logger.error(TAG, `连接测试失败: ${error}`);
      return {
        success: false,
        needCreateDir: false,
        message: `连接测试失败: ${error}`
      };
    }
  }

  /**
   * 检查文件/目录是否存在
   */
  async exists(remotePath: string): Promise<boolean> {
    if (!this.initialized) {
      await this.initialize();
    }
    
    try {
      const result: WebDAVNativeResult = getNativeModule().exists(remotePath);
      return result.success;
    } catch (error) {
      logger.error(TAG, `检查存在失败: ${error}`);
      return false;
    }
  }

  /**
   * 获取目录内容 (PROPFIND)
   */
  async list(remotePath: string = '', depth: number = 1): Promise<WebDAVNativeFileInfo[]> {
    if (!this.initialized) {
      await this.initialize();
    }
    
    try {
      logger.info(TAG, `获取目录内容: ${remotePath}, depth=${depth}`);
      const result: WebDAVNativeListResult = getNativeModule().list(remotePath, depth);
      
      if (result.success) {
        logger.info(TAG, `获取到 ${result.files.length} 个文件/目录`);
        return result.files;
      } else {
        logger.warn(TAG, `获取目录内容失败: ${result.message}`);
        return [];
      }
    } catch (error) {
      logger.error(TAG, `获取目录内容失败: ${error}`);
      return [];
    }
  }

  /**
   * 获取目录内容（返回完整结果）
   */
  async getDirectoryContents(remotePath: string = ''): Promise<WebDAVNativeListResult> {
    if (!this.initialized) {
      await this.initialize();
    }
    
    try {
      logger.info(TAG, `获取目录内容: ${remotePath}`);
      const result: WebDAVNativeListResult = getNativeModule().list(remotePath, 1);
      return result;
    } catch (error) {
      logger.error(TAG, `获取目录内容失败: ${error}`);
      return {
        success: false,
        statusCode: 0,
        message: `获取目录内容失败: ${error}`,
        files: []
      };
    }
  }

  /**
   * 创建目录 (MKCOL)
   */
  async createDirectory(remotePath: string): Promise<WebDAVNativeResult> {
    if (!this.initialized) {
      await this.initialize();
    }
    
    try {
      logger.info(TAG, `创建目录: ${remotePath}`);
      const result: WebDAVNativeResult = getNativeModule().createDirectory(remotePath);
      
      if (result.success) {
        logger.info(TAG, `目录创建成功: ${remotePath}`);
      } else {
        logger.warn(TAG, `目录创建失败: ${result.message}`);
      }
      
      return result;
    } catch (error) {
      logger.error(TAG, `创建目录失败: ${error}`);
      return {
        success: false,
        statusCode: 0,
        message: `创建目录失败: ${error}`,
        data: ''
      };
    }
  }

  /**
   * 递归创建目录
   */
  async createDirectoryRecursive(remotePath: string): Promise<WebDAVNativeResult> {
    if (!this.initialized) {
      await this.initialize();
    }
    
    try {
      logger.info(TAG, `递归创建目录: ${remotePath}`);
      const result: WebDAVNativeResult = getNativeModule().createDirectoryRecursive(remotePath);
      return result;
    } catch (error) {
      logger.error(TAG, `递归创建目录失败: ${error}`);
      return {
        success: false,
        statusCode: 0,
        message: `递归创建目录失败: ${error}`,
        data: ''
      };
    }
  }

  /**
   * 删除文件或目录 (DELETE)
   */
  async deleteFile(remotePath: string): Promise<WebDAVNativeResult> {
    if (!this.initialized) {
      await this.initialize();
    }
    
    try {
      logger.info(TAG, `删除: ${remotePath}`);
      const result: WebDAVNativeResult = getNativeModule().deleteResource(remotePath);
      
      if (result.success) {
        logger.info(TAG, `删除成功: ${remotePath}`);
      } else {
        logger.warn(TAG, `删除失败: ${result.message}`);
      }
      
      return result;
    } catch (error) {
      logger.error(TAG, `删除失败: ${error}`);
      return {
        success: false,
        statusCode: 0,
        message: `删除失败: ${error}`,
        data: ''
      };
    }
  }

  /**
   * 上传文件内容 (PUT)
   */
  async putFileContents(remotePath: string, data: string): Promise<WebDAVNativeResult> {
    if (!this.initialized) {
      await this.initialize();
    }
    
    try {
      logger.info(TAG, `上传文件内容: ${remotePath}, size=${data.length}`);
      const result: WebDAVNativeResult = getNativeModule().putFileContents(remotePath, data);
      
      if (result.success) {
        logger.info(TAG, `上传成功: ${remotePath}`);
      } else {
        logger.warn(TAG, `上传失败: ${result.message}`);
      }
      
      return result;
    } catch (error) {
      logger.error(TAG, `上传失败: ${error}`);
      return {
        success: false,
        statusCode: 0,
        message: `上传失败: ${error}`,
        data: ''
      };
    }
  }

  /**
   * 下载文件内容 (GET)
   */
  async getFileContents(remotePath: string): Promise<string> {
    if (!this.initialized) {
      await this.initialize();
    }
    
    try {
      logger.info(TAG, `下载文件内容: ${remotePath}`);
      const result: WebDAVNativeResult = getNativeModule().getFileContents(remotePath);
      
      if (result.success) {
        logger.info(TAG, `下载成功: ${remotePath}, size=${result.data.length}`);
        return result.data;
      } else {
        logger.warn(TAG, `下载失败: ${result.message}`);
        throw new Error(result.message);
      }
    } catch (error) {
      logger.error(TAG, `下载失败: ${error}`);
      throw error as Error;
    }
  }

  /**
   * 上传本地文件
   */
  async uploadFile(localPath: string, remotePath: string): Promise<WebDAVNativeResult> {
    if (!this.initialized) {
      await this.initialize();
    }
    
    try {
      logger.info(TAG, `上传本地文件: ${localPath} -> ${remotePath}`);
      const result: WebDAVNativeResult = getNativeModule().uploadFile(localPath, remotePath);
      
      if (result.success) {
        logger.info(TAG, `上传成功: ${remotePath}`);
      } else {
        logger.warn(TAG, `上传失败: ${result.message}`);
      }
      
      return result;
    } catch (error) {
      logger.error(TAG, `上传失败: ${error}`);
      return {
        success: false,
        statusCode: 0,
        message: `上传失败: ${error}`,
        data: ''
      };
    }
  }

  /**
   * 下载文件到本地
   */
  async downloadFile(remotePath: string, localPath: string): Promise<WebDAVNativeResult> {
    if (!this.initialized) {
      await this.initialize();
    }
    
    try {
      logger.info(TAG, `下载文件到本地: ${remotePath} -> ${localPath}`);
      const result: WebDAVNativeResult = getNativeModule().downloadFile(remotePath, localPath);
      
      if (result.success) {
        logger.info(TAG, `下载成功: ${localPath}`);
      } else {
        logger.warn(TAG, `下载失败: ${result.message}`);
      }
      
      return result;
    } catch (error) {
      logger.error(TAG, `下载失败: ${error}`);
      return {
        success: false,
        statusCode: 0,
        message: `下载失败: ${error}`,
        data: ''
      };
    }
  }

  /**
   * 复制文件 (COPY)
   */
  async copyFile(sourcePath: string, destPath: string, overwrite: boolean = true): Promise<WebDAVNativeResult> {
    if (!this.initialized) {
      await this.initialize();
    }
    
    try {
      logger.info(TAG, `复制文件: ${sourcePath} -> ${destPath}`);
      const result: WebDAVNativeResult = getNativeModule().copyFile(sourcePath, destPath, overwrite);
      return result;
    } catch (error) {
      logger.error(TAG, `复制失败: ${error}`);
      return {
        success: false,
        statusCode: 0,
        message: `复制失败: ${error}`,
        data: ''
      };
    }
  }

  /**
   * 移动文件 (MOVE)
   */
  async moveFile(sourcePath: string, destPath: string, overwrite: boolean = true): Promise<WebDAVNativeResult> {
    if (!this.initialized) {
      await this.initialize();
    }
    
    try {
      logger.info(TAG, `移动文件: ${sourcePath} -> ${destPath}`);
      const result: WebDAVNativeResult = getNativeModule().moveFile(sourcePath, destPath, overwrite);
      return result;
    } catch (error) {
      logger.error(TAG, `移动失败: ${error}`);
      return {
        success: false,
        statusCode: 0,
        message: `移动失败: ${error}`,
        data: ''
      };
    }
  }

  /**
   * 获取磁盘配额信息
   */
  async getQuota(): Promise<WebDAVNativeQuotaResult> {
    if (!this.initialized) {
      await this.initialize();
    }
    
    try {
      logger.info(TAG, '获取磁盘配额');
      const result: WebDAVNativeQuotaResult = getNativeModule().getQuota();
      return result;
    } catch (error) {
      logger.error(TAG, `获取配额失败: ${error}`);
      return {
        success: false,
        statusCode: 0,
        message: `获取配额失败: ${error}`,
        usedBytes: -1,
        availableBytes: -1
      };
    }
  }

  /**
   * 销毁客户端
   */
  destroy(): void {
    try {
      logger.info(TAG, '销毁WebDAV Native客户端');
      getNativeModule().destroy();
      this.initialized = false;
    } catch (error) {
      logger.error(TAG, `销毁失败: ${error}`);
    }
  }

  /**
   * 检查是否已初始化
   */
  isInitialized(): boolean {
    return this.initialized;
  }
}

/**
 * 创建WebDAV Native客户端实例
 */
export function createWebDAVNativeClient(config: WebDAVNativeConfig): WebDAVNativeClient {
  return new WebDAVNativeClient(config);
}
