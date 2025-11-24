/**
 * 通知管理器
 * 负责应用通知权限管理和通知发送
 */

import { notificationManager } from '@kit.NotificationKit';
import { logger } from '../../Utils/Logger';
import { common } from '@kit.AbilityKit';
import { BusinessError } from '@kit.BasicServicesKit';

const TAG = 'NotificationManager';

/**
 * 通知类型
 */
export enum NotificationType {
  DOWNLOAD_PROGRESS = 'download_progress',  // 下载进度
  DOWNLOAD_COMPLETE = 'download_complete',  // 下载完成
  DOWNLOAD_FAILED = 'download_failed',      // 下载失败
  UPDATE_AVAILABLE = 'update_available',    // 更新可用
  CHAPTER_UPDATE = 'chapter_update'         // 章节更新
}

/**
 * 进度信息
 */
export interface ProgressInfo {
  current: number;
  max: number;
}

/**
 * 通知配置
 */
export interface NotificationConfig {
  id: number;
  title: string;
  text: string;
  additionalText?: string;
  progress?: ProgressInfo;
  type: NotificationType;
}

/**
 * 通知管理器类
 */
export class AppNotificationManager {
  private static instance: AppNotificationManager;
  private hasPermission: boolean = false;
  private isChecking: boolean = false;
  private notificationIdCounter: number = 1000;

  private constructor() {
    logger.info(TAG, '通知管理器初始化');
  }

  public static getInstance(): AppNotificationManager {
    if (!AppNotificationManager.instance) {
      AppNotificationManager.instance = new AppNotificationManager();
    }
    return AppNotificationManager.instance;
  }

  /**
   * 检查通知权限
   */
  public async checkPermission(): Promise<boolean> {
    if (this.isChecking) {
      logger.debug(TAG, '正在检查权限，跳过重复检查');
      return this.hasPermission;
    }

    this.isChecking = true;
    try {
      const isEnabled = await notificationManager.isNotificationEnabled();
      this.hasPermission = isEnabled;
      logger.info(TAG, `通知权限状态: ${isEnabled ? '已授权' : '未授权'}`);
      return isEnabled;
    } catch (error) {
      const err = error as BusinessError;
      logger.error(TAG, `检查通知权限失败: ${err.code}, ${err.message}`);
      this.hasPermission = false;
      return false;
    } finally {
      this.isChecking = false;
    }
  }

  /**
   * 请求通知权限
   * 应在应用首次启动时调用
   */
  public async requestPermission(context?: common.UIAbilityContext): Promise<boolean> {
    try {
      // 先检查是否已有权限
      const hasPermission = await this.checkPermission();
      if (hasPermission) {
        logger.info(TAG, '已有通知权限，无需请求');
        return true;
      }

      // 请求通知权限
      logger.info(TAG, '请求通知权限');
      await notificationManager.requestEnableNotification(context);
      
      // 再次检查权限状态
      const newStatus = await this.checkPermission();
      logger.info(TAG, `通知权限请求结果: ${newStatus ? '成功' : '失败'}`);
      return newStatus;
    } catch (error) {
      const err = error as BusinessError;
      logger.error(TAG, `请求通知权限失败: ${err.code}, ${err.message}`);
      return false;
    }
  }

  /**
   * 发送通知
   */
  public async sendNotification(config: NotificationConfig): Promise<boolean> {
    try {
      // 检查权限
      if (!this.hasPermission) {
        const hasPermission = await this.checkPermission();
        if (!hasPermission) {
          logger.warn(TAG, '没有通知权限，无法发送通知');
          return false;
        }
      }

      // 构建通知内容
      const notificationRequest: notificationManager.NotificationRequest = {
        id: config.id,
        content: {
          notificationContentType: notificationManager.ContentType.NOTIFICATION_CONTENT_BASIC_TEXT,
          normal: {
            title: config.title,
            text: config.text,
            additionalText: config.additionalText || ''
          }
        },
        actionButtons: []
      };

      // 如果有进度信息，使用进度条样式
      if (config.progress) {
        notificationRequest.content = {
          notificationContentType: notificationManager.ContentType.NOTIFICATION_CONTENT_BASIC_TEXT,
          normal: {
            title: config.title,
            text: config.text,
            additionalText: config.additionalText || ''
          }
        };
      }

      // 发送通知
      await notificationManager.publish(notificationRequest);
      logger.info(TAG, `通知发送成功: ${config.title}`);
      return true;
    } catch (error) {
      const err = error as BusinessError;
      logger.error(TAG, `发送通知失败: ${err.code}, ${err.message}`);
      return false;
    }
  }

  /**
   * 发送下载进度通知
   */
  public async sendDownloadProgressNotification(
    taskId: string,
    fileName: string,
    current: number,
    total: number
  ): Promise<boolean> {
    const progress = Math.floor((current / total) * 100);
    const progressInfo: ProgressInfo = { current: current, max: total };
    const config: NotificationConfig = {
      id: this.getNotificationId(taskId),
      title: '下载中',
      text: fileName,
      additionalText: `${progress}%`,
      progress: progressInfo,
      type: NotificationType.DOWNLOAD_PROGRESS
    };
    return this.sendNotification(config);
  }

  /**
   * 发送下载完成通知
   */
  public async sendDownloadCompleteNotification(
    taskId: string,
    fileName: string
  ): Promise<boolean> {
    const config: NotificationConfig = {
      id: this.getNotificationId(taskId),
      title: '下载完成',
      text: fileName,
      type: NotificationType.DOWNLOAD_COMPLETE
    };
    return this.sendNotification(config);
  }

  /**
   * 发送下载失败通知
   */
  public async sendDownloadFailedNotification(
    taskId: string,
    fileName: string,
    reason: string
  ): Promise<boolean> {
    const config: NotificationConfig = {
      id: this.getNotificationId(taskId),
      title: '下载失败',
      text: fileName,
      additionalText: reason,
      type: NotificationType.DOWNLOAD_FAILED
    };
    return this.sendNotification(config);
  }

  /**
   * 取消通知
   */
  public async cancelNotification(notificationId: number): Promise<void> {
    try {
      await notificationManager.cancel(notificationId);
      logger.info(TAG, `通知已取消: ${notificationId}`);
    } catch (error) {
      const err = error as BusinessError;
      logger.error(TAG, `取消通知失败: ${err.code}, ${err.message}`);
    }
  }

  /**
   * 取消所有通知
   */
  public async cancelAllNotifications(): Promise<void> {
    try {
      await notificationManager.cancelAll();
      logger.info(TAG, '所有通知已取消');
    } catch (error) {
      const err = error as BusinessError;
      logger.error(TAG, `取消所有通知失败: ${err.code}, ${err.message}`);
    }
  }

  /**
   * 根据任务ID生成通知ID
   */
  private getNotificationId(taskId: string): number {
    // 使用简单的哈希算法生成唯一ID
    let hash = 0;
    for (let i = 0; i < taskId.length; i++) {
      const char = taskId.charCodeAt(i);
      hash = ((hash << 5) - hash) + char;
      hash = hash & hash; // Convert to 32bit integer
    }
    return Math.abs(hash) % 100000 + this.notificationIdCounter;
  }

  /**
   * 生成新的通知ID
   */
  public generateNotificationId(): number {
    return this.notificationIdCounter++;
  }
}

// 导出单例
export default AppNotificationManager.getInstance();
