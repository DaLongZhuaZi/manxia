/**
 * 动画设置管理器
 * 统一管理APP内所有动画的开关和配置
 * 提供全局访问接口，确保动画设置在各页面间保持一致
 */

import { logger } from '../../Utils/Logger';
import { SettingsManager, SettingKeys } from '../Managers/SettingsManager';

const TAG = 'AnimationSettingsManager';

/**
 * 动画设置配置接口
 */
export interface AnimationSettings {
  // 书籍打开/关闭动画
  bookOpenEnabled: boolean;       // 书籍打开动画开关
  bookCloseEnabled: boolean;      // 书籍关闭动画开关
  bookOpenDuration: number;       // 书籍打开动画时长(ms)
  bookCloseDuration: number;      // 书籍关闭动画时长(ms)
  // 主页面底栏动画
  mainPageBottomBarAnimationEnabled: boolean; // 主页面底栏动画开关（关闭后底栏常驻）
}

/**
 * 默认动画设置
 */
export const DEFAULT_ANIMATION_SETTINGS: AnimationSettings = {
  bookOpenEnabled: true,
  bookCloseEnabled: true,
  bookOpenDuration: 400,
  bookCloseDuration: 350,
  mainPageBottomBarAnimationEnabled: true // 默认开启底栏动画
};

/**
 * 动画设置变化监听器类型
 */
export type AnimationSettingsListener = (settings: AnimationSettings) => void;

/**
 * 动画设置管理器类（单例）
 */
export class AnimationSettingsManager {
  private static instance: AnimationSettingsManager | null = null;
  private settingsManager: SettingsManager;
  private currentSettings: AnimationSettings;
  private listeners: Set<AnimationSettingsListener> = new Set();
  private initialized: boolean = false;

  private constructor() {
    this.settingsManager = SettingsManager.getInstance();
    this.currentSettings = this.copySettings(DEFAULT_ANIMATION_SETTINGS);
  }

  /**
   * 获取单例实例
   */
  public static getInstance(): AnimationSettingsManager {
    if (!AnimationSettingsManager.instance) {
      AnimationSettingsManager.instance = new AnimationSettingsManager();
    }
    return AnimationSettingsManager.instance;
  }

  /**
   * 初始化动画设置管理器
   * 从持久化存储加载设置
   */
  public async initialize(): Promise<void> {
    if (this.initialized) {
      return;
    }

    try {
      await this.loadSettings();
      this.initialized = true;
      logger.info(TAG, '✅ 动画设置管理器初始化完成');
    } catch (error) {
      logger.error(TAG, '❌ 动画设置管理器初始化失败', String(error));
      // 使用默认设置
      this.currentSettings = this.copySettings(DEFAULT_ANIMATION_SETTINGS);
      this.initialized = true;
    }
  }

  /**
   * 从持久化存储加载设置
   */
  private async loadSettings(): Promise<void> {
    this.currentSettings = {
      bookOpenEnabled: this.settingsManager.getBoolean(
        SettingKeys.ANIMATION_BOOK_OPEN_ENABLED,
        DEFAULT_ANIMATION_SETTINGS.bookOpenEnabled
      ),
      bookCloseEnabled: this.settingsManager.getBoolean(
        SettingKeys.ANIMATION_BOOK_CLOSE_ENABLED,
        DEFAULT_ANIMATION_SETTINGS.bookCloseEnabled
      ),
      bookOpenDuration: this.settingsManager.getNumber(
        SettingKeys.ANIMATION_BOOK_OPEN_DURATION,
        DEFAULT_ANIMATION_SETTINGS.bookOpenDuration
      ),
      bookCloseDuration: this.settingsManager.getNumber(
        SettingKeys.ANIMATION_BOOK_CLOSE_DURATION,
        DEFAULT_ANIMATION_SETTINGS.bookCloseDuration
      ),
      mainPageBottomBarAnimationEnabled: this.settingsManager.getBoolean(
        SettingKeys.ANIMATION_MAIN_PAGE_BOTTOM_BAR_ENABLED,
        DEFAULT_ANIMATION_SETTINGS.mainPageBottomBarAnimationEnabled
      )
    };

    logger.info(TAG, `📦 动画设置已加载: 打开动画=${this.currentSettings.bookOpenEnabled}, 关闭动画=${this.currentSettings.bookCloseEnabled}, 底栏动画=${this.currentSettings.mainPageBottomBarAnimationEnabled}`);
  }

  /**
   * 复制设置对象（ArkTS不支持展开运算符）
   */
  private copySettings(settings: AnimationSettings): AnimationSettings {
    return {
      bookOpenEnabled: settings.bookOpenEnabled,
      bookCloseEnabled: settings.bookCloseEnabled,
      bookOpenDuration: settings.bookOpenDuration,
      bookCloseDuration: settings.bookCloseDuration,
      mainPageBottomBarAnimationEnabled: settings.mainPageBottomBarAnimationEnabled
    };
  }

  /**
   * 获取当前动画设置
   */
  public getSettings(): AnimationSettings {
    return this.copySettings(this.currentSettings);
  }

  /**
   * 检查书籍打开动画是否启用
   */
  public isBookOpenAnimationEnabled(): boolean {
    return this.currentSettings.bookOpenEnabled;
  }

  /**
   * 检查书籍关闭动画是否启用
   */
  public isBookCloseAnimationEnabled(): boolean {
    return this.currentSettings.bookCloseEnabled;
  }

  /**
   * 获取书籍打开动画时长
   */
  public getBookOpenDuration(): number {
    return this.currentSettings.bookOpenDuration;
  }

  /**
   * 获取书籍关闭动画时长
   */
  public getBookCloseDuration(): number {
    return this.currentSettings.bookCloseDuration;
  }

  /**
   * 检查主页面底栏动画是否启用
   */
  public isMainPageBottomBarAnimationEnabled(): boolean {
    return this.currentSettings.mainPageBottomBarAnimationEnabled;
  }

  /**
   * 设置书籍打开动画开关
   */
  public async setBookOpenAnimationEnabled(enabled: boolean): Promise<void> {
    if (this.currentSettings.bookOpenEnabled === enabled) {
      return;
    }

    this.currentSettings.bookOpenEnabled = enabled;
    await this.settingsManager.setBoolean(SettingKeys.ANIMATION_BOOK_OPEN_ENABLED, enabled);
    this.notifyListeners();
    logger.info(TAG, `📝 书籍打开动画设置已更新: ${enabled}`);
  }

  /**
   * 设置书籍关闭动画开关
   */
  public async setBookCloseAnimationEnabled(enabled: boolean): Promise<void> {
    if (this.currentSettings.bookCloseEnabled === enabled) {
      return;
    }

    this.currentSettings.bookCloseEnabled = enabled;
    await this.settingsManager.setBoolean(SettingKeys.ANIMATION_BOOK_CLOSE_ENABLED, enabled);
    this.notifyListeners();
    logger.info(TAG, `📝 书籍关闭动画设置已更新: ${enabled}`);
  }

  /**
   * 设置书籍打开动画时长
   */
  public async setBookOpenDuration(duration: number): Promise<void> {
    // 限制范围: 100ms - 1000ms
    const clampedDuration = Math.max(100, Math.min(1000, duration));
    if (this.currentSettings.bookOpenDuration === clampedDuration) {
      return;
    }

    this.currentSettings.bookOpenDuration = clampedDuration;
    await this.settingsManager.setNumber(SettingKeys.ANIMATION_BOOK_OPEN_DURATION, clampedDuration);
    this.notifyListeners();
    logger.info(TAG, `📝 书籍打开动画时长已更新: ${clampedDuration}ms`);
  }

  /**
   * 设置书籍关闭动画时长
   */
  public async setBookCloseDuration(duration: number): Promise<void> {
    // 限制范围: 100ms - 1000ms
    const clampedDuration = Math.max(100, Math.min(1000, duration));
    if (this.currentSettings.bookCloseDuration === clampedDuration) {
      return;
    }

    this.currentSettings.bookCloseDuration = clampedDuration;
    await this.settingsManager.setNumber(SettingKeys.ANIMATION_BOOK_CLOSE_DURATION, clampedDuration);
    this.notifyListeners();
    logger.info(TAG, `📝 书籍关闭动画时长已更新: ${clampedDuration}ms`);
  }

  /**
   * 设置主页面底栏动画开关
   */
  public async setMainPageBottomBarAnimationEnabled(enabled: boolean): Promise<void> {
    if (this.currentSettings.mainPageBottomBarAnimationEnabled === enabled) {
      return;
    }

    this.currentSettings.mainPageBottomBarAnimationEnabled = enabled;
    await this.settingsManager.setBoolean(SettingKeys.ANIMATION_MAIN_PAGE_BOTTOM_BAR_ENABLED, enabled);
    this.notifyListeners();
    logger.info(TAG, `📝 主页面底栏动画设置已更新: ${enabled}`);
  }

  /**
   * 批量更新动画设置
   */
  public async updateSettings(settings: Partial<AnimationSettings>): Promise<void> {
    let changed = false;

    if (settings.bookOpenEnabled !== undefined && settings.bookOpenEnabled !== this.currentSettings.bookOpenEnabled) {
      this.currentSettings.bookOpenEnabled = settings.bookOpenEnabled;
      await this.settingsManager.setBoolean(SettingKeys.ANIMATION_BOOK_OPEN_ENABLED, settings.bookOpenEnabled);
      changed = true;
    }

    if (settings.bookCloseEnabled !== undefined && settings.bookCloseEnabled !== this.currentSettings.bookCloseEnabled) {
      this.currentSettings.bookCloseEnabled = settings.bookCloseEnabled;
      await this.settingsManager.setBoolean(SettingKeys.ANIMATION_BOOK_CLOSE_ENABLED, settings.bookCloseEnabled);
      changed = true;
    }

    if (settings.bookOpenDuration !== undefined) {
      const clampedDuration = Math.max(100, Math.min(1000, settings.bookOpenDuration));
      if (clampedDuration !== this.currentSettings.bookOpenDuration) {
        this.currentSettings.bookOpenDuration = clampedDuration;
        await this.settingsManager.setNumber(SettingKeys.ANIMATION_BOOK_OPEN_DURATION, clampedDuration);
        changed = true;
      }
    }

    if (settings.bookCloseDuration !== undefined) {
      const clampedDuration = Math.max(100, Math.min(1000, settings.bookCloseDuration));
      if (clampedDuration !== this.currentSettings.bookCloseDuration) {
        this.currentSettings.bookCloseDuration = clampedDuration;
        await this.settingsManager.setNumber(SettingKeys.ANIMATION_BOOK_CLOSE_DURATION, clampedDuration);
        changed = true;
      }
    }

    if (settings.mainPageBottomBarAnimationEnabled !== undefined && settings.mainPageBottomBarAnimationEnabled !== this.currentSettings.mainPageBottomBarAnimationEnabled) {
      this.currentSettings.mainPageBottomBarAnimationEnabled = settings.mainPageBottomBarAnimationEnabled;
      await this.settingsManager.setBoolean(SettingKeys.ANIMATION_MAIN_PAGE_BOTTOM_BAR_ENABLED, settings.mainPageBottomBarAnimationEnabled);
      changed = true;
    }

    if (changed) {
      this.notifyListeners();
      logger.info(TAG, '📝 动画设置已批量更新');
    }
  }

  /**
   * 重置为默认设置
   */
  public async resetToDefault(): Promise<void> {
    await this.updateSettings(DEFAULT_ANIMATION_SETTINGS);
    logger.info(TAG, '🔄 动画设置已重置为默认值');
  }

  /**
   * 添加设置变化监听器
   */
  public addListener(listener: AnimationSettingsListener): void {
    this.listeners.add(listener);
  }

  /**
   * 移除设置变化监听器
   */
  public removeListener(listener: AnimationSettingsListener): void {
    this.listeners.delete(listener);
  }

  /**
   * 通知所有监听器设置已变化
   */
  private notifyListeners(): void {
    const settings = this.getSettings();
    this.listeners.forEach(listener => {
      try {
        listener(settings);
      } catch (error) {
        logger.error(TAG, '监听器回调执行失败', String(error));
      }
    });
  }

  /**
   * 检查是否已初始化
   */
  public isInitialized(): boolean {
    return this.initialized;
  }
}

// 导出单例实例的便捷访问函数
export function getAnimationSettingsManager(): AnimationSettingsManager {
  return AnimationSettingsManager.getInstance();
}

// 导出便捷函数
export function isBookOpenAnimationEnabled(): boolean {
  return AnimationSettingsManager.getInstance().isBookOpenAnimationEnabled();
}

export function isBookCloseAnimationEnabled(): boolean {
  return AnimationSettingsManager.getInstance().isBookCloseAnimationEnabled();
}

export function isMainPageBottomBarAnimationEnabled(): boolean {
  return AnimationSettingsManager.getInstance().isMainPageBottomBarAnimationEnabled();
}
