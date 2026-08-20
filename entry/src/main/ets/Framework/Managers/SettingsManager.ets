import { SafeUtils } from 'manxia_core/src/main/ets/Utils/SafeUtils';
import { SettingKeys } from 'manxia_core/src/main/ets/Framework/Contracts/SettingKeys';
/**
 * 设置管理器
 * 负责管理应用的所有设置，使用数据库持久化存储
 */

import { logger } from 'manxia_core/src/main/ets/Utils/Logger';
import { DataManager } from '../Data/DataManager';
import { UserSettingsDatabaseRecord } from 'manxia_core/src/main/ets/Framework/Database/DatabaseTypes';

const TAG = 'SettingsManager';

/**
 * 设置键名常量
 */

export { SettingKeys };


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
      return SafeUtils.parseObj(value) as T;
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
   * 默认显示基本标签: 书库(1), 图源(3), 书源(4), Suwayomi(5), Komga(7), 管理(6)
   */
  async getVisibleTabs(): Promise<number[]> {
    const defaultTabs: number[] = [1, 3, 4, 5, 7, 6];
    const savedValue = this.settingsCache.get(SettingKeys.VISIBLE_TABS);
    if (savedValue === undefined || savedValue.trim().length === 0) {
      return defaultTabs;
    }
    const savedTabs = this.getJSON<number[]>(SettingKeys.VISIBLE_TABS, defaultTabs);
    if (!Array.isArray(savedTabs)) {
      logger.warn(TAG, `底栏可见标签配置格式无效，使用默认配置: ${savedValue}`);
      return defaultTabs;
    }
    return savedTabs;
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
   * 获取底栏样式
   * @returns 'custom'（经典自定义底栏）| 'hds'（HDS系统底栏）
   */
  getBottomBarStyle(): string {
    return this.getString(SettingKeys.BOTTOM_BAR_STYLE, 'custom');
  }

  /**
   * 设置底栏样式
   */
  async setBottomBarStyle(style: string): Promise<void> {
    await this.setString(SettingKeys.BOTTOM_BAR_STYLE, style);
  }

  getGlobalSearchV2Enabled(): boolean {
    return this.getBoolean(SettingKeys.GLOBAL_SEARCH_V2_ENABLED, true);
  }

  async setGlobalSearchV2Enabled(enabled: boolean): Promise<void> {
    await this.setBoolean(SettingKeys.GLOBAL_SEARCH_V2_ENABLED, enabled);
  }

  getGlobalSearchDebugMetricsEnabled(): boolean {
    return this.getBoolean(SettingKeys.GLOBAL_SEARCH_DEBUG_METRICS_ENABLED, false);
  }

  async setGlobalSearchDebugMetricsEnabled(enabled: boolean): Promise<void> {
    await this.setBoolean(SettingKeys.GLOBAL_SEARCH_DEBUG_METRICS_ENABLED, enabled);
  }

  getGlobalSearchOnlineCacheEnabled(): boolean {
    return this.getBoolean(SettingKeys.GLOBAL_SEARCH_ONLINE_CACHE_ENABLED, true);
  }

  async setGlobalSearchOnlineCacheEnabled(enabled: boolean): Promise<void> {
    await this.setBoolean(SettingKeys.GLOBAL_SEARCH_ONLINE_CACHE_ENABLED, enabled);
  }

  getLegadoV2ExecutionPolicy(): string {
    // V2 is the production default. `legacy_only` remains an explicit
    // operator-selected recovery mode and is never selected merely because a
    // fresh install does not have a persisted value yet.
    return this.getString(SettingKeys.LEGADO_V2_EXECUTION_POLICY, 'v2_full_cutover');
  }

  async setLegadoV2ExecutionPolicy(policy: string): Promise<void> {
    await this.setString(SettingKeys.LEGADO_V2_EXECUTION_POLICY, policy);
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
   * 获取重复检测是否启用
   */
  async getDuplicateDetectionEnabled(): Promise<boolean> {
    return this.getBoolean(SettingKeys.DUPLICATE_DETECTION_ENABLED, false);
  }

  /**
   * 设置重复检测是否启用
   */
  async setDuplicateDetectionEnabled(enabled: boolean): Promise<void> {
    await this.setBoolean(SettingKeys.DUPLICATE_DETECTION_ENABLED, enabled);
  }

  /**
   * 获取重复检测相似度阈值
   */
  async getDuplicateDetectionThreshold(): Promise<number> {
    return this.getNumber(SettingKeys.DUPLICATE_DETECTION_THRESHOLD, 0.5);
  }

  /**
   * 设置重复检测相似度阈值
   */
  async setDuplicateDetectionThreshold(threshold: number): Promise<void> {
    await this.setNumber(SettingKeys.DUPLICATE_DETECTION_THRESHOLD, threshold);
  }

  /**
   * 获取重复检测范围
   */
  async getDuplicateDetectionScope(): Promise<string> {
    return this.getString(SettingKeys.DUPLICATE_DETECTION_SCOPE, 'same_type');
  }

  /**
   * 设置重复检测范围
   */
  async setDuplicateDetectionScope(scope: string): Promise<void> {
    await this.setString(SettingKeys.DUPLICATE_DETECTION_SCOPE, scope);
  }

  /**
   * 获取重复检测标题权重
   */
  async getDuplicateDetectionTitleWeight(): Promise<number> {
    return this.getNumber(SettingKeys.DUPLICATE_DETECTION_TITLE_WEIGHT, 0.7);
  }

  /**
   * 设置重复检测标题权重
   */
  async setDuplicateDetectionTitleWeight(weight: number): Promise<void> {
    await this.setNumber(SettingKeys.DUPLICATE_DETECTION_TITLE_WEIGHT, weight);
  }

  /**
   * 检查是否已初始化
   */
  isInitialized(): boolean {
    return this.initialized;
  }
}
