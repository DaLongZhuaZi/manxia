/**
 * WebDAV相关数据模型
 * 
 * 文件路径: entry/src/main/ets/Models/WebDAVModels.ets
 */

// 连接测试状态
export type ConnectionStatus = 'untested' | 'testing' | 'success' | 'failed';

export interface WebDAVSettings {
  enabled: boolean;           // 是否启用WebDAV
  serverUrl: string;          // 服务器地址
  username: string;           // 用户名
  password: string;           // 密码（加密存储）
  basePath: string;           // 基础路径
  autoBackup: boolean;        // 是否自动备份
  autoBackupInterval: 'daily' | 'weekly';  // 自动备份间隔
  keepBackupCount: number;    // 保留备份数量
  lastSyncTime: number;       // 最后同步时间
  // 新增字段
  connectionStatus: ConnectionStatus;  // 连接状态
  lastTestTime: number;       // 最后测试时间
  lastTestMessage: string;    // 最后测试消息
  needCreateDir: boolean;     // 是否需要创建目录
}

export const DEFAULT_WEBDAV_SETTINGS: WebDAVSettings = {
  enabled: false,
  serverUrl: '',
  username: '',
  password: '',
  basePath: '/manxia',
  autoBackup: false,
  autoBackupInterval: 'daily',
  keepBackupCount: 5,
  lastSyncTime: 0,
  connectionStatus: 'untested',
  lastTestTime: 0,
  lastTestMessage: '',
  needCreateDir: false
};

export interface WebDAVServerInfo {
  serverName: string;
  version: string;
}

export interface WebDAVTestResult {
  success: boolean;
  message: string;
  serverInfo?: WebDAVServerInfo;
}
