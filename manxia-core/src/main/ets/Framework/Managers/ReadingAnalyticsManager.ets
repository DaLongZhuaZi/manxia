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
  isLongTermView: boolean;    // 视图模式：true=长期视图, false=日视图
}

/**
 * 阅读目标设置接口
 */
export interface ReadingGoalsSettings {
  mangaGoalMinutes: number;   // 漫画阅读目标（分钟），0表示未设置
  ebookGoalMinutes: number;   // 电子书阅读目标（分钟），0表示未设置
  novelGoalMinutes: number;   // 小说阅读目标（分钟），0表示未设置
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
  private readonly KEY_IS_LONG_TERM_VIEW = 'is_long_term_view';
  private readonly KEY_MANGA_GOAL = 'manga_goal_minutes';
  private readonly KEY_EBOOK_GOAL = 'ebook_goal_minutes';
  private readonly KEY_NOVEL_GOAL = 'novel_goal_minutes';
  
  // 默认设置
  private settings: ReadingAnalyticsSettings = {
    enabled: false,           // 默认关闭
    retentionDays: 30,        // 默认保田30天
    lastCleanupTime: 0,
    hasAskedPermission: false,
    isLongTermView: true      // 默认长期视图
  };
  
  // 阅读目标设置
  private goalsSettings: ReadingGoalsSettings = {
    mangaGoalMinutes: 0,
    ebookGoalMinutes: 0,
    novelGoalMinutes: 0
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
      logger.debug(TAG, `阅读报告管理器已初始化，跳过。当前状态: enabled=${this.settings.enabled}, hasAsked=${this.settings.hasAskedPermission}`);
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
      this.settings.isLongTermView = await this.preferencesStore.get(this.KEY_IS_LONG_TERM_VIEW, true) as boolean;
      
      // 加载阅读目标
      this.goalsSettings.mangaGoalMinutes = await this.preferencesStore.get(this.KEY_MANGA_GOAL, 0) as number;
      this.goalsSettings.ebookGoalMinutes = await this.preferencesStore.get(this.KEY_EBOOK_GOAL, 0) as number;
      this.goalsSettings.novelGoalMinutes = await this.preferencesStore.get(this.KEY_NOVEL_GOAL, 0) as number;
      
      logger.debug(TAG, `加载设置: enabled=${this.settings.enabled}, retentionDays=${this.settings.retentionDays}, isLongTermView=${this.settings.isLongTermView}`);
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
      await this.preferencesStore.put(this.KEY_IS_LONG_TERM_VIEW, this.settings.isLongTermView);
      await this.preferencesStore.flush();
      
      logger.debug(TAG, '设置已保存');
    } catch (error) {
      logger.error(TAG, `保存设置失败: ${String(error)}`);
    }
  }
  
  /**
   * 保存阅读目标设置
   */
  private async saveGoalsSettings(): Promise<void> {
    if (!this.preferencesStore) return;

    try {
      await this.preferencesStore.put(this.KEY_MANGA_GOAL, this.goalsSettings.mangaGoalMinutes);
      await this.preferencesStore.put(this.KEY_EBOOK_GOAL, this.goalsSettings.ebookGoalMinutes);
      await this.preferencesStore.put(this.KEY_NOVEL_GOAL, this.goalsSettings.novelGoalMinutes);
      await this.preferencesStore.flush();
      
      logger.debug(TAG, '阅读目标已保存');
    } catch (error) {
      logger.error(TAG, `保存阅读目标失败: ${String(error)}`);
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
      hasAskedPermission: this.settings.hasAskedPermission,
      isLongTermView: this.settings.isLongTermView
    };
    return result;
  }

  /**
   * 是否启用阅读数据收集
   */
  public isEnabled(): boolean {
    logger.debug(TAG, `isEnabled() 被调用，返回: ${this.settings.enabled}`);
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
  
  // ==================== 视图模式管理 ====================
  
  /**
   * 获取视图模式
   */
  public isLongTermView(): boolean {
    return this.settings.isLongTermView;
  }
  
  /**
   * 设置视图模式
   */
  public async setLongTermView(isLongTerm: boolean): Promise<void> {
    this.settings.isLongTermView = isLongTerm;
    await this.saveSettings();
    logger.info(TAG, `视图模式已设置为: ${isLongTerm ? '长期视图' : '日视图'}`);
  }
  
  // ==================== 阅读目标管理 ====================
  
  /**
   * 获取阅读目标设置
   */
  public getReadingGoals(): ReadingGoalsSettings {
    const result: ReadingGoalsSettings = {
      mangaGoalMinutes: this.goalsSettings.mangaGoalMinutes,
      ebookGoalMinutes: this.goalsSettings.ebookGoalMinutes,
      novelGoalMinutes: this.goalsSettings.novelGoalMinutes
    };
    return result;
  }
  
  /**
   * 设置漫画阅读目标
   */
  public async setMangaGoal(minutes: number): Promise<void> {
    this.goalsSettings.mangaGoalMinutes = Math.max(0, minutes);
    await this.saveGoalsSettings();
    logger.info(TAG, `漫画阅读目标已设置为: ${minutes}分钟`);
  }
  
  /**
   * 设置电子书阅读目标
   */
  public async setEbookGoal(minutes: number): Promise<void> {
    this.goalsSettings.ebookGoalMinutes = Math.max(0, minutes);
    await this.saveGoalsSettings();
    logger.info(TAG, `电子书阅读目标已设置为: ${minutes}分钟`);
  }
  
  /**
   * 设置小说阅读目标
   */
  public async setNovelGoal(minutes: number): Promise<void> {
    this.goalsSettings.novelGoalMinutes = Math.max(0, minutes);
    await this.saveGoalsSettings();
    logger.info(TAG, `小说阅读目标已设置为: ${minutes}分钟`);
  }
  
  /**
   * 清除某类型的阅读目标
   */
  public async clearGoal(type: 'manga' | 'ebook' | 'novel'): Promise<void> {
    switch (type) {
      case 'manga':
        this.goalsSettings.mangaGoalMinutes = 0;
        break;
      case 'ebook':
        this.goalsSettings.ebookGoalMinutes = 0;
        break;
      case 'novel':
        this.goalsSettings.novelGoalMinutes = 0;
        break;
    }
    await this.saveGoalsSettings();
    logger.info(TAG, `已清除${type}阅读目标`);
  }
}
