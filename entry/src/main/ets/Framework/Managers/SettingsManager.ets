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
