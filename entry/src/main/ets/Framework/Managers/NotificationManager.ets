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
  CHAPTER_UPDATE = 'chapter_update',        // 章节更新
  VALIDATION_PROGRESS = 'validation_progress', // 校验进度
  VALIDATION_COMPLETE = 'validation_complete', // 校验完成
  VALIDATION_CANCELLED = 'validation_cancelled' // 校验已取消
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
  private supportDownloadTemplate: boolean | null = null;

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
  public async requestPermission(context: common.UIAbilityContext): Promise<boolean> {
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

      // 如果有进度信息，优先使用系统模板进度通知
      if (config.progress) {
        const progressPercent = this.calculateProgressPercent(config.progress.current, config.progress.max);
        const canUseTemplate = await this.ensureDownloadTemplateSupport();
        if (canUseTemplate) {
          notificationRequest.template = {
            name: 'downloadTemplate',
            data: {
              title: config.title,
              fileName: config.text,
              progressValue: progressPercent
            }
          };
        } else {
          notificationRequest.content = {
            notificationContentType: notificationManager.ContentType.NOTIFICATION_CONTENT_BASIC_TEXT,
            normal: {
              title: config.title,
              text: config.text,
              additionalText: config.additionalText || `${progressPercent}%`
            }
          };
        }

        if (
          config.type === NotificationType.DOWNLOAD_PROGRESS ||
          config.type === NotificationType.VALIDATION_PROGRESS
        ) {
          notificationRequest.isOngoing = true;
          notificationRequest.isAlertOnce = true;
        }
      } else {
        notificationRequest.isOngoing = false;
      }

      if (
        config.type === NotificationType.DOWNLOAD_COMPLETE ||
        config.type === NotificationType.DOWNLOAD_FAILED ||
        config.type === NotificationType.VALIDATION_COMPLETE ||
        config.type === NotificationType.VALIDATION_CANCELLED
      ) {
        notificationRequest.isOngoing = false;
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

  private async ensureDownloadTemplateSupport(): Promise<boolean> {
    if (this.supportDownloadTemplate !== null) {
      return this.supportDownloadTemplate;
    }
    try {
      this.supportDownloadTemplate = await notificationManager.isSupportTemplate('downloadTemplate');
    } catch (error) {
      const err = error as BusinessError;
      logger.warn(TAG, `检测通知模板能力失败: ${err.code}, ${err.message}`);
      this.supportDownloadTemplate = false;
    }
    return this.supportDownloadTemplate;
  }

  private calculateProgressPercent(current: number, total: number): number {
    if (total <= 0) {
      return 0;
    }
    const progress = Math.floor((current / total) * 100);
    return Math.max(0, Math.min(100, progress));
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
    const progress = this.calculateProgressPercent(current, total);
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
   * 发送详细的下载完成通知
   * 显示缓存内容的详细信息，包括书名、章节范围、成功/失败数量
   */
  public async sendDetailedDownloadCompleteNotification(
    taskId: string,
    contentTitle: string,
    contentType: 'novel' | 'manga',
    successCount: number,
    failCount: number,
    startChapter?: number,
    endChapter?: number
  ): Promise<boolean> {
    const totalCount = successCount + failCount;
    const typeName = contentType === 'novel' ? '小说' : '漫画';
    
    // 构建标题
    let title: string;
    if (failCount === 0) {
      title = `${typeName}缓存完成`;
    } else if (failCount === totalCount) {
      title = `${typeName}缓存失败`;
    } else {
      title = `${typeName}缓存完成(部分失败)`;
    }
    
    // 构建正文
    let text = contentTitle;
    if (startChapter !== undefined && endChapter !== undefined) {
      if (startChapter === endChapter) {
        text += ` 第${startChapter + 1}章`;
      } else {
        text += ` 第${startChapter + 1}-${endChapter + 1}章`;
      }
    }
    
    // 构建附加文本
    let additionalText: string;
    if (failCount === 0) {
      additionalText = `成功缓存${successCount}章`;
    } else if (failCount === totalCount) {
      additionalText = `全部${totalCount}章缓存失败`;
    } else {
      additionalText = `成功${successCount}章，失败${failCount}章`;
    }
    
    const config: NotificationConfig = {
      id: this.getNotificationId(taskId),
      title: title,
      text: text,
      additionalText: additionalText,
      type: failCount === totalCount ? NotificationType.DOWNLOAD_FAILED : NotificationType.DOWNLOAD_COMPLETE
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
   * 发送校验进度通知
   */
  public async sendValidationProgressNotification(
    taskId: string,
    current: number,
    total: number,
    validCount: number,
    invalidCount: number
  ): Promise<boolean> {
    const progress = this.calculateProgressPercent(current, total);
    const config: NotificationConfig = {
      id: this.getNotificationId(taskId),
      title: '书源校验中',
      text: `进度: ${current}/${total} (有效:${validCount} 失效:${invalidCount})`,
      additionalText: `${progress}%`,
      progress: { current, max: total },
      type: NotificationType.VALIDATION_PROGRESS
    };
    return this.sendNotification(config);
  }

  /**
   * 发送校验完成通知
   */
  public async sendValidationCompleteNotification(
    taskId: string,
    total: number,
    validCount: number,
    invalidCount: number
  ): Promise<boolean> {
    const config: NotificationConfig = {
      id: this.getNotificationId(taskId),
      title: '书源校验完成',
      text: `共${total}个书源，有效:${validCount}，失效:${invalidCount}`,
      type: NotificationType.VALIDATION_COMPLETE
    };
    return this.sendNotification(config);
  }

  /**
   * 发送校验取消通知
   */
  public async sendValidationCancelledNotification(
    taskId: string,
    completed: number,
    total: number
  ): Promise<boolean> {
    const config: NotificationConfig = {
      id: this.getNotificationId(taskId),
      title: '书源校验已取消',
      text: `已完成 ${completed}/${total}`,
      type: NotificationType.VALIDATION_CANCELLED
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
