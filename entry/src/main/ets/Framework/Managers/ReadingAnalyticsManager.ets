// 文件路径: entry/src/main/ets/Framework/Managers/ReadingAnalyticsManager.ets
/**
 * 阅读报告管理器
 * 负责管理阅读数据收集开关、保留天数等设置
 */

import { preferences } from '@kit.ArkData';
import { common } from '@kit.AbilityKit';
import { logger } from '../../Utils/Logger';
import { getContext } from '../../GlobalContext';

const TAG = 'ReadingAnalyticsManager';

/**
 * 阅读报告设置接口
 */
export interface ReadingAnalyticsSettings {
  enabled: boolean;           // 是否启用阅读数据收集
  retentionDays: number;      // 数据保留天数
  lastCleanupTime: number;    // 上次清理时间
  hasAskedPermission: boolean; // 是否已询问过用户权限
}

/**
 * 保留天数选项
 */
export const RETENTION_DAYS_OPTIONS: number[] = [7, 14, 30, 60, 90, 180, 365];

/**
 * 阅读报告管理器类
 */
export class ReadingAnalyticsManager {
  private static instance: ReadingAnalyticsManager | null = null;
  private preferencesStore: preferences.Preferences | null = null;
  private readonly PREFERENCES_NAME = 'reading_analytics_preferences';
  
  // 设置键名
  private readonly KEY_ENABLED = 'analytics_enabled';
  private readonly KEY_RETENTION_DAYS = 'retention_days';
  private readonly KEY_LAST_CLEANUP = 'last_cleanup_time';
  private readonly KEY_HAS_ASKED = 'has_asked_permission';
  
  // 默认设置
  private settings: ReadingAnalyticsSettings = {
    enabled: false,           // 默认关闭
    retentionDays: 30,        // 默认保留30天
    lastCleanupTime: 0,
    hasAskedPermission: false
  };
  
  private isInitialized: boolean = false;

  private constructor() {
    // 私有构造函数
  }

  /**
   * 获取单例实例
   */
  public static getInstance(): ReadingAnalyticsManager {
    if (!ReadingAnalyticsManager.instance) {
      ReadingAnalyticsManager.instance = new ReadingAnalyticsManager();
    }
    return ReadingAnalyticsManager.instance;
  }

  /**
   * 初始化管理器
   */
  public async initialize(): Promise<void> {
    if (this.isInitialized) {
      logger.debug(TAG, '阅读报告管理器已初始化，跳过');
      return;
    }

    try {
      logger.info(TAG, '开始初始化阅读报告管理器');
      
      const context = getContext() as common.UIAbilityContext;
      if (!context) {
        logger.error(TAG, '获取上下文失败');
        return;
      }

      this.preferencesStore = await preferences.getPreferences(context, this.PREFERENCES_NAME);
      
      // 加载设置
      await this.loadSettings();
      
      this.isInitialized = true;
      logger.info(TAG, `阅读报告管理器初始化完成，启用状态: ${this.settings.enabled}, 保留天数: ${this.settings.retentionDays}`);
    } catch (error) {
      logger.error(TAG, `初始化阅读报告管理器失败: ${String(error)}`);
    }
  }

  /**
   * 加载设置
   */
  private async loadSettings(): Promise<void> {
    if (!this.preferencesStore) return;

    try {
      this.settings.enabled = await this.preferencesStore.get(this.KEY_ENABLED, false) as boolean;
      this.settings.retentionDays = await this.preferencesStore.get(this.KEY_RETENTION_DAYS, 30) as number;
      this.settings.lastCleanupTime = await this.preferencesStore.get(this.KEY_LAST_CLEANUP, 0) as number;
      this.settings.hasAskedPermission = await this.preferencesStore.get(this.KEY_HAS_ASKED, false) as boolean;
      
      logger.debug(TAG, `加载设置: enabled=${this.settings.enabled}, retentionDays=${this.settings.retentionDays}`);
    } catch (error) {
      logger.error(TAG, `加载设置失败: ${String(error)}`);
    }
  }

  /**
   * 保存设置
   */
  private async saveSettings(): Promise<void> {
    if (!this.preferencesStore) return;

    try {
      await this.preferencesStore.put(this.KEY_ENABLED, this.settings.enabled);
      await this.preferencesStore.put(this.KEY_RETENTION_DAYS, this.settings.retentionDays);
      await this.preferencesStore.put(this.KEY_LAST_CLEANUP, this.settings.lastCleanupTime);
      await this.preferencesStore.put(this.KEY_HAS_ASKED, this.settings.hasAskedPermission);
      await this.preferencesStore.flush();
      
      logger.debug(TAG, '设置已保存');
    } catch (error) {
      logger.error(TAG, `保存设置失败: ${String(error)}`);
    }
  }

  /**
   * 获取当前设置
   */
  public getSettings(): ReadingAnalyticsSettings {
    const result: ReadingAnalyticsSettings = {
      enabled: this.settings.enabled,
      retentionDays: this.settings.retentionDays,
      lastCleanupTime: this.settings.lastCleanupTime,
      hasAskedPermission: this.settings.hasAskedPermission
    };
    return result;
  }

  /**
   * 是否启用阅读数据收集
   */
  public isEnabled(): boolean {
    return this.settings.enabled;
  }

  /**
   * 设置启用状态
   */
  public async setEnabled(enabled: boolean): Promise<void> {
    this.settings.enabled = enabled;
    await this.saveSettings();
    logger.info(TAG, `阅读数据收集已${enabled ? '启用' : '禁用'}`);
  }

  /**
   * 获取数据保留天数
   */
  public getRetentionDays(): number {
    return this.settings.retentionDays;
  }

  /**
   * 设置数据保留天数
   */
  public async setRetentionDays(days: number): Promise<void> {
    if (RETENTION_DAYS_OPTIONS.includes(days)) {
      this.settings.retentionDays = days;
      await this.saveSettings();
      logger.info(TAG, `数据保留天数已设置为: ${days}天`);
    } else {
      logger.warn(TAG, `无效的保留天数: ${days}`);
    }
  }

  /**
   * 是否已询问过用户权限
   */
  public hasAskedPermission(): boolean {
    return this.settings.hasAskedPermission;
  }

  /**
   * 标记已询问过用户权限
   */
  public async markAskedPermission(): Promise<void> {
    this.settings.hasAskedPermission = true;
    await this.saveSettings();
    logger.info(TAG, '已标记询问过用户权限');
  }
  
  /**
   * 重置权限询问状态（用于清除数据并关闭功能时）
   */
  public async resetAskedPermission(): Promise<void> {
    this.settings.hasAskedPermission = false;
    await this.saveSettings();
    logger.info(TAG, '已重置权限询问状态');
  }

  /**
   * 获取保留天数选项列表（用于 TextPicker）
   */
  public getRetentionDaysOptions(): string[] {
    return RETENTION_DAYS_OPTIONS.map(days => `${days}天`);
  }

  /**
   * 获取当前保留天数在选项中的索引
   */
  public getRetentionDaysIndex(): number {
    const index = RETENTION_DAYS_OPTIONS.indexOf(this.settings.retentionDays);
    return index >= 0 ? index : 2; // 默认返回30天的索引
  }

  /**
   * 根据索引设置保留天数
   */
  public async setRetentionDaysByIndex(index: number): Promise<void> {
    if (index >= 0 && index < RETENTION_DAYS_OPTIONS.length) {
      await this.setRetentionDays(RETENTION_DAYS_OPTIONS[index]);
    }
  }
}
