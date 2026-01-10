/**
 * FTP连接配置数据模型
 * 
 * 文件路径: entry/src/main/ets/Models/FTPModels.ets
 */

/**
 * FTP保存的连接配置
 */
export interface SavedFTPConnection {
  id: string;
  name: string;
  host: string;
  port: number;
  username: string;
  password: string;
  useFTPS: boolean;
  passive: boolean;
  timeoutMs: number;
  createdAt: number;
  lastUsedAt: number;
}

/**
 * 默认FTP连接配置
 */
export const DEFAULT_FTP_CONNECTION: SavedFTPConnection = {
  id: '',
  name: '',
  host: '',
  port: 21,
  username: '',
  password: '',
  useFTPS: false,
  passive: true,
  timeoutMs: 30000,
  createdAt: 0,
  lastUsedAt: 0
};

/**
 * 创建新的FTP连接配置
 */
export function createFTPConnection(name: string, host: string, port: number, username: string, password: string, useFTPS: boolean, passive: boolean): SavedFTPConnection {
  return {
    id: generateFTPConnectionId(),
    name: name,
    host: host,
    port: port,
    username: username,
    password: password,
    useFTPS: useFTPS,
    passive: passive,
    timeoutMs: 30000,
    createdAt: Date.now(),
    lastUsedAt: Date.now()
  };
}

/**
 * 生成唯一的连接ID
 */
function generateFTPConnectionId(): string {
  return 'ftp_' + Date.now().toString(36) + '_' + Math.random().toString(36).substring(2, 9);
}
