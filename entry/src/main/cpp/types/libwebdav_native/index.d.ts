/**
 * WebDAV Native Module TypeScript Definitions
 * 
 * 文件路径: entry/src/main/cpp/types/libwebdav_native/index.d.ts
 */

/**
 * WebDAV配置
 */
export interface WebDAVConfig {
  serverUrl: string;
  username: string;
  password: string;
  basePath: string;
  timeoutMs?: number;
  verifySSL?: boolean;
}

/**
 * 操作结果
 */
export interface WebDAVResult {
  success: boolean;
  statusCode: number;
  message: string;
  data: string;
}

/**
 * 文件/目录信息
 */
export interface WebDAVFileInfo {
  path: string;
  name: string;
  size: number;
  lastModified: number;
  isDirectory: boolean;
  etag: string;
  contentType: string;
}

/**
 * 目录列表结果
 */
export interface WebDAVListResult {
  success: boolean;
  statusCode: number;
  message: string;
  files: WebDAVFileInfo[];
}

/**
 * 磁盘配额结果
 */
export interface WebDAVQuotaResult {
  success: boolean;
  statusCode: number;
  message: string;
  usedBytes: number;
  availableBytes: number;
}

/**
 * 初始化WebDAV客户端
 * @param config WebDAV配置
 * @returns 是否初始化成功
 */
export function init(config: WebDAVConfig): boolean;

/**
 * 测试WebDAV连接
 * @returns 连接测试结果
 */
export function testConnection(): WebDAVResult;

/**
 * 检查文件/目录是否存在
 * @param remotePath 远程路径
 * @returns 检查结果
 */
export function exists(remotePath: string): WebDAVResult;

/**
 * 获取目录内容 (PROPFIND)
 * @param remotePath 远程路径
 * @param depth 深度 (默认1)
 * @returns 目录列表结果
 */
export function list(remotePath: string, depth?: number): WebDAVListResult;

/**
 * 创建目录 (MKCOL)
 * @param remotePath 远程路径
 * @returns 操作结果
 */
export function createDirectory(remotePath: string): WebDAVResult;

/**
 * 递归创建目录
 * @param remotePath 远程路径
 * @returns 操作结果
 */
export function createDirectoryRecursive(remotePath: string): WebDAVResult;

/**
 * 删除文件或目录 (DELETE)
 * @param remotePath 远程路径
 * @returns 操作结果
 */
export function deleteResource(remotePath: string): WebDAVResult;

/**
 * 上传文件内容 (PUT)
 * @param remotePath 远程路径
 * @param data 文件内容
 * @returns 操作结果
 */
export function putFileContents(remotePath: string, data: string): WebDAVResult;

/**
 * 下载文件内容 (GET)
 * @param remotePath 远程路径
 * @returns 操作结果 (data字段包含文件内容)
 */
export function getFileContents(remotePath: string): WebDAVResult;

/**
 * 上传本地文件
 * @param localPath 本地文件路径
 * @param remotePath 远程路径
 * @returns 操作结果
 */
export function uploadFile(localPath: string, remotePath: string): WebDAVResult;

/**
 * 下载文件到本地
 * @param remotePath 远程路径
 * @param localPath 本地文件路径
 * @returns 操作结果
 */
export function downloadFile(remotePath: string, localPath: string): WebDAVResult;

/**
 * 复制文件 (COPY)
 * @param sourcePath 源路径
 * @param destPath 目标路径
 * @param overwrite 是否覆盖 (默认true)
 * @returns 操作结果
 */
export function copyFile(sourcePath: string, destPath: string, overwrite?: boolean): WebDAVResult;

/**
 * 移动文件 (MOVE)
 * @param sourcePath 源路径
 * @param destPath 目标路径
 * @param overwrite 是否覆盖 (默认true)
 * @returns 操作结果
 */
export function moveFile(sourcePath: string, destPath: string, overwrite?: boolean): WebDAVResult;

/**
 * 获取磁盘配额信息
 * @returns 配额结果
 */
export function getQuota(): WebDAVQuotaResult;

/**
 * 销毁客户端
 */
export function destroy(): void;

// ==================== FTP 接口 ====================

/**
 * FTP配置
 */
export interface FTPConfig {
  host: string;
  port: number;
  username: string;
  password: string;
  useFTPS: boolean;
  passive: boolean;
  timeoutMs?: number;
}

/**
 * FTP操作结果
 */
export interface FTPResult {
  success: boolean;
  message: string;
  data?: string;
}

/**
 * FTP文件信息
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
 * FTP目录列表结果
 */
export interface FTPListResult {
  success: boolean;
  message: string;
  files: FTPFileInfo[];
}

/**
 * 初始化FTP客户端
 * @param config FTP配置
 * @returns 是否初始化成功
 */
export function ftpInit(config: FTPConfig): boolean;

/**
 * 测试FTP连接
 * @returns 连接测试结果
 */
export function ftpTestConnection(): FTPResult;

/**
 * 获取FTP目录列表
 * @param remotePath 远程路径
 * @returns 目录列表结果
 */
export function ftpList(remotePath: string): FTPListResult;

/**
 * FTP上传文件
 * @param localPath 本地文件路径
 * @param remotePath 远程路径
 * @returns 操作结果
 */
export function ftpUpload(localPath: string, remotePath: string): FTPResult;

/**
 * FTP下载文件
 * @param remotePath 远程路径
 * @param localPath 本地文件路径
 * @returns 操作结果
 */
export function ftpDownload(remotePath: string, localPath: string): FTPResult;

/**
 * FTP删除文件
 * @param remotePath 远程路径
 * @returns 操作结果
 */
export function ftpDelete(remotePath: string): FTPResult;

/**
 * FTP创建目录
 * @param remotePath 远程路径
 * @returns 操作结果
 */
export function ftpMkdir(remotePath: string): FTPResult;

/**
 * FTP删除目录
 * @param remotePath 远程路径
 * @returns 操作结果
 */
export function ftpRmdir(remotePath: string): FTPResult;

/**
 * 销毁FTP客户端
 */
export function ftpDestroy(): void;
