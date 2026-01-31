/**
 * WebDAV自动备份调度管理器
 * 负责检查和执行自动备份任务
 * 
 * 文件路径: entry/src/main/ets/Framework/WebDAV/WebDAVAutoBackupScheduler.ets
 */

import { logger } from '../../Utils/Logger';
import { preferences } from '@kit.ArkData';
import { common } from '@kit.AbilityKit';
import { getWebDAVBackupManager } from './WebDAVBackupManager';
import { getEnhancedBackupManager } from '../Managers/EnhancedBackupManager';
import { WebDAVSettings } from '../../Models/WebDAVModels';

const TAG = 'WebDAVAutoBackupScheduler';

// 备份间隔常量（毫秒）
const BACKUP_INTERVAL_DAILY: number = 24 * 60 * 60 * 1000;   // 24小时
const BACKUP_INTERVAL_WEEKLY: number = 7 * 24 * 60 * 60 * 1000;  // 7天

/**
 * 根据间隔类型获取间隔毫秒数
 */
function getBackupIntervalMs(interval: 'daily' | 'weekly'): number {
  if (interval === 'daily') {
    return BACKUP_INTERVAL_DAILY;
  } else {
    return BACKUP_INTERVAL_WEEKLY;
  }
}

/**
 * 自动备份调度器状态
 */
export interface AutoBackupStatus {
  enabled: boolean;
  interval: 'daily' | 'weekly';
  lastBackupTime: number;
  nextBackupTime: number;
  isRunning: boolean;
  lastError?: string;
}

/**
 * WebDAV自动备份调度管理器
 */
export class WebDAVAutoBackupScheduler {
  private static instance: WebDAVAutoBackupScheduler | null = null;
  private context: common.UIAbilityContext | null = null;
  private isRunning: boolean = false;
  private checkIntervalId: number | null = null;
  private lastError: string = '';
  
  private constructor() {}
  
  static getInstance(): WebDAVAutoBackupScheduler {
    if (!WebDAVAutoBackupScheduler.instance) {
      WebDAVAutoBackupScheduler.instance = new WebDAVAutoBackupScheduler();
    }
    return WebDAVAutoBackupScheduler.instance;
  }
  
  /**
   * 初始化调度器
   */
  async initialize(context: common.UIAbilityContext): Promise<void> {
    this.context = context;
    logger.info(TAG, '自动备份调度器初始化');
    
    // 检查是否需要执行备份
    await this.checkAndExecuteBackup();
    
    // 启动定时检查（每小时检查一次）
    this.startPeriodicCheck();
  }
  
  /**
   * 启动定时检查
   */
  private startPeriodicCheck(): void {
    if (this.checkIntervalId !== null) {
      clearInterval(this.checkIntervalId);
    }
    
    // 每小时检查一次是否需要备份
    const checkInterval = 60 * 60 * 1000; // 1小时
    this.checkIntervalId = setInterval(() => {
      this.checkAndExecuteBackup();
    }, checkInterval);
    
    logger.info(TAG, '已启动定时检查（每小时）');
  }
  
  /**
   * 停止定时检查
   */
  stopPeriodicCheck(): void {
    if (this.checkIntervalId !== null) {
      clearInterval(this.checkIntervalId);
      this.checkIntervalId = null;
      logger.info(TAG, '已停止定时检查');
    }
  }
  
  /**
   * 检查并执行备份
   */
  async checkAndExecuteBackup(): Promise<boolean> {
    if (!this.context) {
      logger.warn(TAG, '调度器未初始化');
      return false;
    }
    
    if (this.isRunning) {
      logger.info(TAG, '备份任务正在执行中，跳过');
      return false;
    }
    
    try {
      // 加载WebDAV设置
      const settings = await this.loadWebDAVSettings();
      
      if (!settings) {
        logger.debug(TAG, '未配置WebDAV');
        return false;
      }
      
      if (!settings.enabled) {
        logger.debug(TAG, 'WebDAV未启用');
        return false;
      }
      
      if (!settings.autoBackup) {
        logger.debug(TAG, '自动备份未启用');
        return false;
      }
      
      if (settings.connectionStatus !== 'success') {
        logger.debug(TAG, 'WebDAV连接状态不正常');
        return false;
      }
      
      // 检查是否需要备份
      const needBackup = this.shouldBackupNow(settings);
      
      if (!needBackup) {
        logger.debug(TAG, '尚未到备份时间');
        return false;
      }
      
      // 执行备份
      logger.info(TAG, '开始执行自动备份');
      await this.executeAutoBackup(settings);
      
      return true;
    } catch (error) {
      this.lastError = String(error);
      logger.error(TAG, `自动备份检查失败: ${error}`);
      return false;
    }
  }
  
  /**
   * 检查是否需要立即备份
   */
  private shouldBackupNow(settings: WebDAVSettings): boolean {
    const lastBackupTime = settings.lastSyncTime || 0;
    const now = Date.now();
    
    const intervalType = settings.autoBackupInterval as 'daily' | 'weekly';
    const interval = getBackupIntervalMs(intervalType);
    
    const timeSinceLastBackup = now - lastBackupTime;
    const shouldBackup = timeSinceLastBackup >= interval;
    
    logger.info(TAG, `上次备份时间: ${new Date(lastBackupTime).toLocaleString()}, ` +
      `距今: ${Math.round(timeSinceLastBackup / 1000 / 60 / 60)}小时, ` +
      `间隔要求: ${Math.round(interval / 1000 / 60 / 60)}小时, ` +
      `需要备份: ${shouldBackup}`);
    
    return shouldBackup;
  }
  
  /**
   * 执行自动备份
   */
  private async executeAutoBackup(settings: WebDAVSettings): Promise<void> {
    this.isRunning = true;
    this.lastError = '';
    
    try {
      const webdavManager = getWebDAVBackupManager();
      const backupManager = getEnhancedBackupManager();
      
      // 检查WebDAV是否已配置
      if (!webdavManager.isConfigured()) {
        // 重新配置
        await webdavManager.configure({
          serverUrl: settings.serverUrl,
          username: settings.username,
          password: settings.password,
          basePath: settings.basePath
        });
      }
      
      // 1. 创建新的本地备份
      logger.info(TAG, '正在创建本地备份...');
      const backupPath = await backupManager.createBackup();
      
      logger.info(TAG, `本地备份创建成功: ${backupPath}`);
      
      // 2. 上传到云端
      logger.info(TAG, '正在上传到云端...');
      await webdavManager.uploadBackup(backupPath);
      logger.info(TAG, '上传成功');
      
      // 3. 清理旧备份
      if (settings.keepBackupCount > 0) {
        logger.info(TAG, `清理旧备份，保留最近 ${settings.keepBackupCount} 个`);
        await webdavManager.cleanOldBackups(settings.keepBackupCount);
      }
      
      // 4. 更新最后备份时间
      settings.lastSyncTime = Date.now();
      await this.saveWebDAVSettings(settings);
      
      logger.info(TAG, '自动备份完成');
    } catch (error) {
      this.lastError = String(error);
      logger.error(TAG, `自动备份执行失败: ${error}`);
      throw error as Error;
    } finally {
      this.isRunning = false;
    }
  }
  
  /**
   * 手动触发备份
   */
  async triggerManualBackup(): Promise<void> {
    if (!this.context) {
      throw new Error('调度器未初始化');
    }
    
    const settings = await this.loadWebDAVSettings();
    if (!settings || !settings.enabled) {
      throw new Error('WebDAV未配置或未启用');
    }
    
    await this.executeAutoBackup(settings);
  }
  
  /**
   * 获取自动备份状态
   */
  async getStatus(): Promise<AutoBackupStatus> {
    const settings = await this.loadWebDAVSettings();
    
    if (!settings || !settings.autoBackup) {
      return {
        enabled: false,
        interval: 'daily',
        lastBackupTime: 0,
        nextBackupTime: 0,
        isRunning: this.isRunning,
        lastError: this.lastError
      };
    }
    
    const lastBackupTime = settings.lastSyncTime || 0;
    const intervalType = settings.autoBackupInterval as 'daily' | 'weekly';
    const interval = getBackupIntervalMs(intervalType);
    const nextBackupTime = lastBackupTime + interval;
    
    return {
      enabled: settings.autoBackup,
      interval: settings.autoBackupInterval as 'daily' | 'weekly',
      lastBackupTime,
      nextBackupTime,
      isRunning: this.isRunning,
      lastError: this.lastError
    };
  }
  
  /**
   * 加载WebDAV设置
   */
  private async loadWebDAVSettings(): Promise<WebDAVSettings | null> {
    if (!this.context) return null;
    
    try {
      const options: preferences.Options = { name: 'webdav_settings' };
      const dataPreferences = await preferences.getPreferences(this.context, options);
      
      const serverUrl = dataPreferences.getSync('serverUrl', '') as string;
      if (!serverUrl) return null;
      
      return {
        serverUrl,
        username: dataPreferences.getSync('username', '') as string,
        password: dataPreferences.getSync('password', '') as string,
        basePath: dataPreferences.getSync('basePath', '/manxia') as string,
        enabled: dataPreferences.getSync('enabled', false) as boolean,
        autoBackup: dataPreferences.getSync('autoBackup', false) as boolean,
        autoBackupInterval: dataPreferences.getSync('autoBackupInterval', 'daily') as 'daily' | 'weekly',
        keepBackupCount: dataPreferences.getSync('keepBackupCount', 5) as number,
        lastSyncTime: dataPreferences.getSync('lastSyncTime', 0) as number,
        connectionStatus: dataPreferences.getSync('connectionStatus', 'untested') as 'untested' | 'testing' | 'success' | 'failed',
        lastTestTime: dataPreferences.getSync('lastTestTime', 0) as number,
        lastTestMessage: dataPreferences.getSync('lastTestMessage', '') as string,
        needCreateDir: dataPreferences.getSync('needCreateDir', false) as boolean
      };
    } catch (error) {
      logger.error(TAG, `加载WebDAV设置失败: ${error}`);
      return null;
    }
  }
  
  /**
   * 保存WebDAV设置
   */
  private async saveWebDAVSettings(settings: WebDAVSettings): Promise<void> {
    if (!this.context) return;
    
    try {
      const options: preferences.Options = { name: 'webdav_settings' };
      const dataPreferences = await preferences.getPreferences(this.context, options);
      
      await dataPreferences.put('lastSyncTime', settings.lastSyncTime);
      await dataPreferences.flush();
      
      logger.info(TAG, '已更新lastSyncTime');
    } catch (error) {
      logger.error(TAG, `保存WebDAV设置失败: ${error}`);
    }
  }
}

/**
 * 获取自动备份调度器实例
 */
export function getAutoBackupScheduler(): WebDAVAutoBackupScheduler {
  return WebDAVAutoBackupScheduler.getInstance();
}

/**
 * 格式化下次备份时间
 */
export function formatNextBackupTime(timestamp: number): string {
  if (timestamp <= 0) return '未设置';
  
  const now = Date.now();
  if (timestamp <= now) return '即将执行';
  
  const diff = timestamp - now;
  const hours = Math.floor(diff / (1000 * 60 * 60));
  const minutes = Math.floor((diff % (1000 * 60 * 60)) / (1000 * 60));
  
  if (hours > 24) {
    const days = Math.floor(hours / 24);
    return `约 ${days} 天后`;
  } else if (hours > 0) {
    return `约 ${hours} 小时 ${minutes} 分钟后`;
  } else {
    return `约 ${minutes} 分钟后`;
  }
}
