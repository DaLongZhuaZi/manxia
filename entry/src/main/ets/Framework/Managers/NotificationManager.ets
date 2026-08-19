/**
 * 通知管理器
 * 负责应用通知权限管理和通知发送
 */

import { notificationManager } from '@kit.NotificationKit';
import { logger } from 'manxia_core/src/main/ets/Utils/Logger';
import { common } from '@kit.AbilityKit';
import wantAgent, { WantAgent } from '@ohos.app.ability.wantAgent';
import { BusinessError } from '@kit.BasicServicesKit';
import { Want } from '@kit.AbilityKit';
import { TaskNavigationTarget } from '../Task/TaskNavigationTypes';

const TAG = 'NotificationManager';
const TASK_NOTIFICATION_ID_BASE = 100000;
const TASK_NOTIFICATION_ID_RANGE = 900000;

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
  VALIDATION_CANCELLED = 'validation_cancelled', // 校验已取消
  PDF_IMPORT_PROGRESS = 'pdf_import_progress', // PDF 导入进度
  PDF_IMPORT_COMPLETE = 'pdf_import_complete', // PDF 导入完成
  PDF_IMPORT_FAILED = 'pdf_import_failed', // PDF 导入失败
  TRANSFER_SERVICE_RUNNING = 'transfer_service_running', // 局域网传书服务运行中
  TRANSFER_UPLOAD_PROGRESS = 'transfer_upload_progress', // 局域网传书上传中
  TRANSFER_UPLOAD_COMPLETE = 'transfer_upload_complete', // 局域网传书上传完成
  TRANSFER_UPLOAD_FAILED = 'transfer_upload_failed', // 局域网传书上传失败
  SOURCE_AUTO_CHECK_PROGRESS = 'source_auto_check_progress', // 图源巡检进度
  SOURCE_AUTO_CHECK_COMPLETE = 'source_auto_check_complete', // 图源巡检完成
  SOURCE_AUTO_CHECK_FAILED = 'source_auto_check_failed' // 图源巡检失败
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
  navigation?: TaskNavigationTarget;
  context?: common.UIAbilityContext;
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

      const clickWantAgent: WantAgent | undefined = await this.buildClickWantAgent(config);
      if (clickWantAgent !== undefined) {
        notificationRequest.wantAgent = clickWantAgent;
        notificationRequest.tapDismissed = config.type !== NotificationType.SOURCE_AUTO_CHECK_PROGRESS;
      }

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
          config.type === NotificationType.VALIDATION_PROGRESS ||
          config.type === NotificationType.PDF_IMPORT_PROGRESS ||
          config.type === NotificationType.TRANSFER_UPLOAD_PROGRESS ||
          config.type === NotificationType.SOURCE_AUTO_CHECK_PROGRESS
        ) {
          notificationRequest.isOngoing = true;
          notificationRequest.isAlertOnce = true;
        }
      } else {
        notificationRequest.isOngoing = false;
      }

      if (config.type === NotificationType.TRANSFER_SERVICE_RUNNING) {
        notificationRequest.isOngoing = true;
        notificationRequest.isAlertOnce = true;
      }

      if (
        config.type === NotificationType.DOWNLOAD_COMPLETE ||
        config.type === NotificationType.DOWNLOAD_FAILED ||
        config.type === NotificationType.VALIDATION_COMPLETE ||
        config.type === NotificationType.VALIDATION_CANCELLED ||
        config.type === NotificationType.PDF_IMPORT_COMPLETE ||
        config.type === NotificationType.PDF_IMPORT_FAILED ||
        config.type === NotificationType.TRANSFER_UPLOAD_COMPLETE ||
        config.type === NotificationType.TRANSFER_UPLOAD_FAILED ||
        config.type === NotificationType.SOURCE_AUTO_CHECK_COMPLETE ||
        config.type === NotificationType.SOURCE_AUTO_CHECK_FAILED
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

  private async buildClickWantAgent(config: NotificationConfig): Promise<WantAgent | undefined> {
    if (config.context === undefined || config.navigation === undefined) {
      return undefined;
    }
    try {
      const notificationWant: Want = {
        bundleName: config.context.abilityInfo.bundleName,
        abilityName: 'EntryAbility',
        parameters: {
          notificationRouteName: config.navigation.routeName,
          notificationSourceId: config.navigation.sourceId !== undefined ? config.navigation.sourceId : 0,
          notificationSourceName: config.navigation.sourceName !== undefined ? config.navigation.sourceName : '',
          notificationSourcePkg: config.navigation.sourcePkg !== undefined ? config.navigation.sourcePkg : '',
          notificationInitialUrl: config.navigation.initialUrl !== undefined ? config.navigation.initialUrl : '',
          notificationAutoCheckTaskId: config.navigation.autoCheckTaskId !== undefined ? config.navigation.autoCheckTaskId : '',
          notificationOpenAutoCheckReport: config.navigation.openAutoCheckReport === true
        }
      };
      const info: wantAgent.WantAgentInfo = {
        wants: [notificationWant],
        actionType: wantAgent.OperationType.START_ABILITY,
        requestCode: config.id,
        actionFlags: [wantAgent.WantAgentFlags.UPDATE_PRESENT_FLAG]
      };
      return await wantAgent.getWantAgent(info);
    } catch (error) {
      logger.warn(TAG, `构建通知点击跳转失败: ${String(error)}`);
      return undefined;
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
   * 发送 PDF 导入进度通知
   */
  public async sendPdfImportProgressNotification(
    taskId: string,
    fileName: string,
    current: number,
    total: number,
    stageText?: string
  ): Promise<boolean> {
    const progress = this.calculateProgressPercent(current, total);
    const text = stageText && stageText.length > 0
      ? `${fileName} - ${stageText}`
      : fileName;
    const config: NotificationConfig = {
      id: this.getNotificationId(taskId),
      title: 'PDF导入中',
      text: text,
      additionalText: `${progress}%`,
      progress: { current, max: total },
      type: NotificationType.PDF_IMPORT_PROGRESS
    };
    return this.sendNotification(config);
  }

  /**
   * 发送 PDF 导入完成通知
   */
  public async sendPdfImportCompleteNotification(
    taskId: string,
    fileName: string
  ): Promise<boolean> {
    const config: NotificationConfig = {
      id: this.getNotificationId(taskId),
      title: 'PDF导入完成',
      text: fileName,
      type: NotificationType.PDF_IMPORT_COMPLETE
    };
    return this.sendNotification(config);
  }

  /**
   * 发送 PDF 导入失败通知
   */
  public async sendPdfImportFailedNotification(
    taskId: string,
    fileName: string,
    reason: string
  ): Promise<boolean> {
    const config: NotificationConfig = {
      id: this.getNotificationId(taskId),
      title: 'PDF导入失败',
      text: fileName,
      additionalText: reason,
      type: NotificationType.PDF_IMPORT_FAILED
    };
    return this.sendNotification(config);
  }

  /**
   * 发送图源巡检进度通知
   */
  public async sendSourceAutoCheckProgressNotification(
    taskId: string,
    sourceName: string,
    current: number,
    total: number,
    stageText: string,
    navigation?: TaskNavigationTarget,
    context?: common.UIAbilityContext
  ): Promise<boolean> {
    const progress = this.calculateProgressPercent(current, total);
    const config: NotificationConfig = {
      id: this.getNotificationId(taskId),
      title: '图源巡检中',
      text: sourceName,
      additionalText: stageText.length > 0 ? `${progress}% · ${stageText}` : `${progress}%`,
      progress: { current: current, max: total },
      type: NotificationType.SOURCE_AUTO_CHECK_PROGRESS,
      navigation: navigation,
      context: context
    };
    return this.sendNotification(config);
  }

  /**
   * 发送图源巡检完成通知
   */
  public async sendSourceAutoCheckCompleteNotification(
    taskId: string,
    sourceName: string,
    summary: string,
    navigation?: TaskNavigationTarget,
    context?: common.UIAbilityContext
  ): Promise<boolean> {
    const config: NotificationConfig = {
      id: this.getNotificationId(taskId),
      title: '图源巡检完成',
      text: sourceName,
      additionalText: summary,
      type: NotificationType.SOURCE_AUTO_CHECK_COMPLETE,
      navigation: navigation,
      context: context
    };
    return this.sendNotification(config);
  }

  /**
   * 发送图源巡检失败通知
   */
  public async sendSourceAutoCheckFailedNotification(
    taskId: string,
    sourceName: string,
    reason: string,
    navigation?: TaskNavigationTarget,
    context?: common.UIAbilityContext
  ): Promise<boolean> {
    const config: NotificationConfig = {
      id: this.getNotificationId(taskId),
      title: '图源巡检失败',
      text: sourceName,
      additionalText: reason,
      type: NotificationType.SOURCE_AUTO_CHECK_FAILED,
      navigation: navigation,
      context: context
    };
    return this.sendNotification(config);
  }

  /**
   * 发送局域网传书服务运行通知
   */
  public async sendTransferServiceRunningNotification(
    taskId: string,
    addressText: string,
    pairCode: string
  ): Promise<boolean> {
    const config: NotificationConfig = {
      id: this.getNotificationId(taskId),
      title: '局域网传书运行中',
      text: addressText,
      additionalText: pairCode.length > 0 ? `配对码 ${pairCode}` : '等待生成配对码',
      type: NotificationType.TRANSFER_SERVICE_RUNNING
    };
    return this.sendNotification(config);
  }

  /**
   * 发送局域网传书上传进度通知
   */
  public async sendTransferUploadProgressNotification(
    taskId: string,
    fileName: string,
    current: number,
    total: number
  ): Promise<boolean> {
    const progress = this.calculateProgressPercent(current, total);
    const config: NotificationConfig = {
      id: this.getNotificationId(taskId),
      title: '正在接收传书文件',
      text: fileName,
      additionalText: `${progress}%`,
      progress: { current: current, max: total },
      type: NotificationType.TRANSFER_UPLOAD_PROGRESS
    };
    return this.sendNotification(config);
  }

  /**
   * 发送局域网传书上传完成通知
   */
  public async sendTransferUploadCompleteNotification(
    taskId: string,
    fileName: string
  ): Promise<boolean> {
    const config: NotificationConfig = {
      id: this.getNotificationId(taskId),
      title: '传书文件已保存',
      text: fileName,
      additionalText: '文件已在设备上，可到收件箱继续导入',
      type: NotificationType.TRANSFER_UPLOAD_COMPLETE
    };
    return this.sendNotification(config);
  }

  /**
   * 发送局域网传书上传失败通知
   */
  public async sendTransferUploadFailedNotification(
    taskId: string,
    fileName: string,
    reason: string
  ): Promise<boolean> {
    const config: NotificationConfig = {
      id: this.getNotificationId(taskId),
      title: '传书失败',
      text: fileName.length > 0 ? fileName : '未命名文件',
      additionalText: reason,
      type: NotificationType.TRANSFER_UPLOAD_FAILED
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
   * 按任务 ID 取消通知
   */
  public async cancelTaskNotification(taskId: string): Promise<void> {
    await this.cancelNotification(this.getNotificationId(taskId));
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
    // 同一任务必须稳定映射到同一通知 ID，才能用完成/失败通知覆盖进度通知。
    let hash = 0;
    for (let i = 0; i < taskId.length; i++) {
      const char = taskId.charCodeAt(i);
      hash = ((hash << 5) - hash) + char;
      hash = hash & hash; // Convert to 32bit integer
    }
    return TASK_NOTIFICATION_ID_BASE + (Math.abs(hash) % TASK_NOTIFICATION_ID_RANGE);
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
