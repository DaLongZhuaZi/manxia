/**
 * 设置管理器
 * 负责管理应用的所有设置，使用数据库持久化存储
 */

import { logger } from '../../Utils/Logger';
import { DataManager } from '../Data/DataManager';
import { UserSettingsDatabaseRecord } from '../Database/DatabaseTypes';

const TAG = 'SettingsManager';

/**
 * 设置键名常量
 */
export class SettingKeys {
  // 高级功能
  static readonly ADVANCED_MODE_ENABLED = 'advanced_mode_enabled';
  static readonly ENABLE_LOG_FLOATING_WINDOW = 'enable_log_floating_window';
  static readonly PRELOAD_DEBUG_MODE = 'preload_debug_mode'; // 预加载调试模式：off/on/always
  
  // 生命周期监控
  static readonly LIFECYCLE_MONITOR_ENABLED = 'lifecycle_monitor_enabled'; // 启用生命周期监控
  static readonly LIFECYCLE_FLOATING_BALL_ENABLED = 'lifecycle_floating_ball_enabled'; // 启用生命周期悬浮球
  
  // 漫画全局阅读设置
  static readonly GLOBAL_READING_MODE = 'global_reading_mode';
  static readonly GLOBAL_READING_DIRECTION = 'global_reading_direction';
  static readonly GLOBAL_BRIGHTNESS = 'global_brightness';
  static readonly GLOBAL_KEEP_SCREEN_ON = 'global_keep_screen_on';
  static readonly GLOBAL_VOLUME_KEY_NAVIGATION = 'global_volume_key_navigation';
  static readonly GLOBAL_PAGE_TURN_ANIMATION = 'global_page_turn_animation';
  
  // 电子书全局阅读设置
  static readonly GLOBAL_EBOOK_FONT_SIZE = 'global_ebook_font_size';
  static readonly GLOBAL_EBOOK_LINE_HEIGHT = 'global_ebook_line_height';
  static readonly GLOBAL_EBOOK_PAGE_MARGIN = 'global_ebook_page_margin';
  static readonly GLOBAL_EBOOK_THEME = 'global_ebook_theme';
  static readonly GLOBAL_EBOOK_PAGE_MODE = 'global_ebook_page_mode';
  
  // 纯文本阅读器全局设置
  static readonly GLOBAL_TEXT_FONT_SIZE = 'global_text_font_size';
  static readonly GLOBAL_TEXT_FONT_FAMILY = 'global_text_font_family';  // 字体
  static readonly GLOBAL_TEXT_FONT_WEIGHT = 'global_text_font_weight';  // 字体粗细
  static readonly GLOBAL_TEXT_LINE_HEIGHT = 'global_text_line_height';
  static readonly GLOBAL_TEXT_PARAGRAPH_SPACING = 'global_text_paragraph_spacing';
  static readonly GLOBAL_TEXT_FIRST_LINE_INDENT = 'global_text_first_line_indent';
  static readonly GLOBAL_TEXT_LETTER_SPACING = 'global_text_letter_spacing';
  static readonly GLOBAL_TEXT_ALIGNMENT = 'global_text_alignment';
  static readonly GLOBAL_TEXT_PAGE_MARGIN = 'global_text_page_margin';
  static readonly GLOBAL_TEXT_BG_COLOR = 'global_text_bg_color';
  static readonly GLOBAL_TEXT_TEXT_COLOR = 'global_text_text_color';
  static readonly GLOBAL_TEXT_PAGE_TURN_ANIMATION = 'global_text_page_turn_animation';
  static readonly GLOBAL_TEXT_KEEP_SCREEN_ON = 'global_text_keep_screen_on';
  static readonly GLOBAL_TEXT_VOLUME_KEY_NAV = 'global_text_volume_key_nav';
  static readonly GLOBAL_TEXT_TAP_TO_TURN = 'global_text_tap_to_turn';
  static readonly GLOBAL_TEXT_BG_IMAGE_PATH = 'global_text_bg_image_path';
  static readonly GLOBAL_TEXT_BG_IMAGE_OPACITY = 'global_text_bg_image_opacity';
  static readonly GLOBAL_TEXT_USE_BG_IMAGE = 'global_text_use_bg_image';
  // 底部信息栏设置
  static readonly GLOBAL_TEXT_SHOW_TIME = 'global_text_show_time';
  static readonly GLOBAL_TEXT_SHOW_BATTERY = 'global_text_show_battery';
  static readonly GLOBAL_TEXT_SHOW_PAGE_NUMBER = 'global_text_show_page_number';
  static readonly GLOBAL_TEXT_SHOW_PROGRESS = 'global_text_show_progress';
  
  // 下载设置
  static readonly DOWNLOAD_WIFI_ONLY = 'download_wifi_only';
  static readonly MAX_CONCURRENT_DOWNLOADS = 'max_concurrent_downloads';
  
  // 通知设置
  static readonly ENABLE_DOWNLOAD_NOTIFICATIONS = 'enable_download_notifications';
  static readonly ENABLE_UPDATE_NOTIFICATIONS = 'enable_update_notifications';
  
  // 其他设置
  static readonly AUTO_CHECK_UPDATES = 'auto_check_updates';
  static readonly CLEAR_CACHE_ON_EXIT = 'clear_cache_on_exit';
  static readonly FORCE_TABLET_MODE = 'force_tablet_mode';
  static readonly FORCE_LANDSCAPE_MODE = 'force_landscape_mode';
  
  // Download同步设置
  static readonly DOWNLOAD_SYNC_DIR_PATH = 'download_sync_dir_path';
  static readonly DOWNLOAD_SYNC_DIR_URI = 'download_sync_dir_uri';
  
  // 小说阅读器设置（使用TextReaderSettings）
  static readonly NOVEL_READER_SETTINGS = 'novel_reader_settings';
  // 小说搜索设置
  static readonly NOVEL_SEARCH_MAX_SOURCES = 'novel_search_max_sources';
  
  // 底部导航栏自定义设置
  static readonly VISIBLE_TABS = 'visible_tabs'; // JSON数组，存储可见的标签索引
  
  // 内容过滤设置
  static readonly SFW_MODE_ENABLED = 'sfw_mode_enabled'; // 启用SFW模式（隐藏NSFW内容）
  
  // 全局UserAgent设置
  static readonly GLOBAL_USER_AGENT = 'global_user_agent'; // 全局自定义User-Agent
  static readonly GLOBAL_USER_AGENT_ENABLED = 'global_user_agent_enabled'; // 是否启用全局自定义UA
  
  // 隐私保护设置
  static readonly BACKGROUND_BLUR_ENABLED = 'background_blur_enabled'; // 后台任务界面模糊遮罩
  static readonly BACKGROUND_BLUR_BG_TYPE = 'background_blur_bg_type'; // 后台遮罩背景类型: 'solid' | 'custom'
  static readonly BACKGROUND_BLUR_BG_IMAGE = 'background_blur_bg_image'; // 自定义背景图片路径
  static readonly BACKGROUND_BLUR_ICON_TYPE = 'background_blur_icon_type'; // 图标类型: 'shield' | 'logo'
}

/**
 * 设置类型
 */
export enum SettingType {
  BOOLEAN = 'boolean',
  STRING = 'string',
  NUMBER = 'number',
  JSON = 'json'
}

/**
 * 设置管理器类
 */
export class SettingsManager {
  private static instance: SettingsManager;
  private dataManager: DataManager | null = null;
  private settingsCache: Map<string, string> = new Map();
  private initialized: boolean = false;

  private constructor() {}

  static getInstance(): SettingsManager {
    if (!SettingsManager.instance) {
      SettingsManager.instance = new SettingsManager();
    }
    return SettingsManager.instance;
  }

  /**
   * 初始化设置管理器
   */
  async initialize(): Promise<void> {
    try {
      this.dataManager = DataManager.getInstance();
      
      // 加载所有设置到缓存
      await this.loadAllSettings();
      
      this.initialized = true;
      logger.info(TAG, '✅ 设置管理器初始化完成');
    } catch (error) {
      logger.error(TAG, '❌ 设置管理器初始化失败', String(error));
      throw error as Error;
    }
  }

  /**
   * 加载所有设置到缓存
   */
  private async loadAllSettings(): Promise<void> {
    try {
      if (!this.dataManager) {
        throw new Error('DataManager未初始化');
      }

      const settings = await this.dataManager.getAllSettings();
      this.settingsCache.clear();
      
      settings.forEach((setting: UserSettingsDatabaseRecord) => {
        this.settingsCache.set(setting.settingKey, setting.settingValue);
      });
      
      logger.info(TAG, `📦 已加载${settings.length}个设置到缓存`);
    } catch (error) {
      logger.error(TAG, '加载设置失败', String(error));
    }
  }

  /**
   * 获取布尔值设置
   */
  getBoolean(key: string, defaultValue: boolean = false): boolean {
    const value = this.settingsCache.get(key);
    if (value === undefined) {
      return defaultValue;
    }
    return value === 'true';
  }

  /**
   * 获取字符串设置
   */
  getString(key: string, defaultValue: string = ''): string {
    return this.settingsCache.get(key) || defaultValue;
  }

  /**
   * 获取数字设置
   */
  getNumber(key: string, defaultValue: number = 0): number {
    const value = this.settingsCache.get(key);
    if (value === undefined) {
      return defaultValue;
    }
    const num = Number(value);
    return isNaN(num) ? defaultValue : num;
  }

  /**
   * 获取JSON对象设置
   */
  getJSON<T>(key: string, defaultValue: T): T {
    const value = this.settingsCache.get(key);
    if (!value) {
      return defaultValue;
    }
    try {
      return JSON.parse(value) as T;
    } catch (error) {
      logger.error(TAG, `解析JSON设置失败: ${key}`, String(error));
      return defaultValue;
    }
  }

  /**
   * 设置布尔值
   */
  async setBoolean(key: string, value: boolean): Promise<void> {
    await this.setValue(key, String(value), SettingType.BOOLEAN);
  }

  /**
   * 设置字符串
   */
  async setString(key: string, value: string): Promise<void> {
    await this.setValue(key, value, SettingType.STRING);
  }

  /**
   * 设置数字
   */
  async setNumber(key: string, value: number): Promise<void> {
    await this.setValue(key, String(value), SettingType.NUMBER);
  }

  /**
   * 设置JSON对象
   */
  async setJSON<T>(key: string, value: T): Promise<void> {
    await this.setValue(key, JSON.stringify(value), SettingType.JSON);
  }

  /**
   * 获取底部导航栏可见标签
   */
  async getVisibleTabs(): Promise<number[]> {
    const defaultTabs = [0, 1, 2, 3];
    return this.getJSON<number[]>(SettingKeys.VISIBLE_TABS, defaultTabs);
  }

  /**
   * 设置底部导航栏可见标签
   */
  async setVisibleTabs(tabs: number[]): Promise<void> {
    await this.setJSON(SettingKeys.VISIBLE_TABS, tabs);
  }

  /**
   * 获取生命周期监控是否启用
   */
  async getLifecycleMonitorEnabled(): Promise<boolean> {
    return this.getBoolean(SettingKeys.LIFECYCLE_MONITOR_ENABLED, false);
  }

  /**
   * 设置生命周期监控是否启用
   */
  async setLifecycleMonitorEnabled(enabled: boolean): Promise<void> {
    await this.setBoolean(SettingKeys.LIFECYCLE_MONITOR_ENABLED, enabled);
  }

  /**
   * 获取生命周期悬浮球是否启用
   */
  async getLifecycleMonitorFloatingBallEnabled(): Promise<boolean> {
    return this.getBoolean(SettingKeys.LIFECYCLE_FLOATING_BALL_ENABLED, false);
  }

  /**
   * 设置生命周期悬浮球是否启用
   */
  async setLifecycleMonitorFloatingBallEnabled(enabled: boolean): Promise<void> {
    await this.setBoolean(SettingKeys.LIFECYCLE_FLOATING_BALL_ENABLED, enabled);
  }

  /**
   * 设置值（内部方法）
   */
  private async setValue(key: string, value: string, type: SettingType): Promise<void> {
    try {
      if (!this.dataManager) {
        throw new Error('DataManager未初始化');
      }

      // 更新缓存
      this.settingsCache.set(key, value);

      // 保存到数据库
      await this.dataManager.saveSetting(key, value, type);
      
      logger.debug(TAG, `✅ 设置已保存: ${key} = ${value}`);
    } catch (error) {
      logger.error(TAG, `保存设置失败: ${key}`, String(error));
      throw error as Error;
    }
  }

  /**
   * 删除设置
   */
  async deleteSetting(key: string): Promise<void> {
    try {
      if (!this.dataManager) {
        throw new Error('DataManager未初始化');
      }

      this.settingsCache.delete(key);
      await this.dataManager.deleteSetting(key);
      
      logger.info(TAG, `🗑️ 设置已删除: ${key}`);
    } catch (error) {
      logger.error(TAG, `删除设置失败: ${key}`, String(error));
      throw error as Error;
    }
  }

  /**
   * 清空所有设置
   */
  async clearAllSettings(): Promise<void> {
    try {
      if (!this.dataManager) {
        throw new Error('DataManager未初始化');
      }

      this.settingsCache.clear();
      await this.dataManager.clearAllSettings();
      
      logger.info(TAG, '🗑️ 所有设置已清空');
    } catch (error) {
      logger.error(TAG, '清空设置失败', String(error));
      throw error as Error;
    }
  }

  /**
   * 同步设置到AppStorage
   */
  syncToAppStorage(): void {
    try {
      this.settingsCache.forEach((value: string, key: string) => {
        AppStorage.setOrCreate(key, value === 'true' ? true : value === 'false' ? false : value);
      });
      
      // 特别处理Download同步目录设置，使用特定的AppStorage键名
      const downloadSyncDirPath = this.settingsCache.get(SettingKeys.DOWNLOAD_SYNC_DIR_PATH);
      const downloadSyncDirUri = this.settingsCache.get(SettingKeys.DOWNLOAD_SYNC_DIR_URI);
      if (downloadSyncDirPath) {
        AppStorage.setOrCreate('downloadSyncDirPath', downloadSyncDirPath);
        logger.info(TAG, `✅ Download同步目录已加载: ${downloadSyncDirPath}`);
      }
      if (downloadSyncDirUri) {
        AppStorage.setOrCreate('downloadSyncDirUri', downloadSyncDirUri);
      }
      
      logger.info(TAG, '✅ 设置已同步到AppStorage');
    } catch (error) {
      logger.error(TAG, '同步设置到AppStorage失败', String(error));
    }
  }

  /**
   * 检查是否已初始化
   */
  isInitialized(): boolean {
    return this.initialized;
  }
}
