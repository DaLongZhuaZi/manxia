/**
 * 内容过滤管理器
 * 负责管理SFW/NSFW内容过滤，提供一键SFW模式
 */

import { logger } from '../../Utils/Logger';
import { SettingsManager, SettingKeys } from './SettingsManager';

const TAG = 'ContentFilterManager';

/**
 * 过滤统计信息接口
 */
export interface FilterStats {
  total: number;
  nsfw: number;
  sfw: number;
  filtered: number;
}

/**
 * 内容过滤管理器类
 */
export class ContentFilterManager {
  private static instance: ContentFilterManager;
  private settingsManager: SettingsManager;
  private sfwModeEnabled: boolean = false;
  private listeners: Set<(enabled: boolean) => void> = new Set();

  private constructor() {
    this.settingsManager = SettingsManager.getInstance();
    this.loadSFWModeSetting();
  }

  public static getInstance(): ContentFilterManager {
    if (!ContentFilterManager.instance) {
      ContentFilterManager.instance = new ContentFilterManager();
    }
    return ContentFilterManager.instance;
  }

  /**
   * 加载SFW模式设置
   */
  private async loadSFWModeSetting(): Promise<void> {
    try {
      const enabled = await this.settingsManager.getBoolean(SettingKeys.SFW_MODE_ENABLED, false);
      this.sfwModeEnabled = enabled;
      logger.info(TAG, `SFW模式已加载: ${enabled ? '启用' : '禁用'}`);
    } catch (error) {
      logger.error(TAG, `加载SFW模式设置失败: ${error}`);
      this.sfwModeEnabled = false;
    }
  }

  /**
   * 获取SFW模式状态
   */
  public isSFWModeEnabled(): boolean {
    return this.sfwModeEnabled;
  }

  /**
   * 设置SFW模式
   */
  public async setSFWMode(enabled: boolean): Promise<void> {
    try {
      await this.settingsManager.setBoolean(SettingKeys.SFW_MODE_ENABLED, enabled);
      this.sfwModeEnabled = enabled;
      logger.info(TAG, `SFW模式已${enabled ? '启用' : '禁用'}`);
      
      // 通知所有监听器
      this.notifyListeners(enabled);
    } catch (error) {
      logger.error(TAG, `设置SFW模式失败: ${error}`);
      throw new Error(String(error));
    }
  }

  /**
   * 切换SFW模式
   */
  public async toggleSFWMode(): Promise<boolean> {
    const newState = !this.sfwModeEnabled;
    await this.setSFWMode(newState);
    return newState;
  }

  /**
   * 检查内容是否应该被过滤
   * @param isNSFW 内容是否为NSFW
   * @returns true表示应该过滤（隐藏），false表示应该显示
   */
  public shouldFilterContent(isNSFW?: boolean): boolean {
    if (!this.sfwModeEnabled) {
      return false; // SFW模式未启用，不过滤任何内容
    }
    return isNSFW === true; // SFW模式启用时，过滤NSFW内容
  }

  /**
   * 过滤内容列表（漫画、电子书、小说、图源等）
   */
  public filterContentList<T>(items: T[]): T[] {
    if (!this.isSFWModeEnabled()) {
      logger.debug(TAG, `[NSFW调试] SFW模式未启用，不过滤内容`);
      return items;
    }

    const filtered = items.filter((item: T) => {
      // 检查是否为NSFW内容
      const itemObj: ESObject = item as ESObject;
      const isNSFW: boolean = itemObj.isNSFW === true || itemObj.isNSFW === 1;
      const title: string = itemObj.title as string || itemObj.name as string || 'Unknown';
      logger.debug(TAG, `[NSFW调试] 检查内容: title="${title}", isNSFW=${itemObj.isNSFW}, 判定为NSFW=${isNSFW}, 是否过滤=${isNSFW}`);
      return !isNSFW; // 只保留非NSFW内容
    });
    
    logger.info(TAG, `[NSFW调试] 过滤完成: 原始${items.length}个, 过滤后${filtered.length}个`);
    return filtered;
  }

  /**
   * 添加SFW模式变化监听器
   */
  public addListener(listener: (enabled: boolean) => void): void {
    this.listeners.add(listener);
  }

  /**
   * 移除SFW模式变化监听器
   */
  public removeListener(listener: (enabled: boolean) => void): void {
    this.listeners.delete(listener);
  }

  /**
   * 通知所有监听器
   */
  private notifyListeners(enabled: boolean): void {
    this.listeners.forEach(listener => {
      try {
        listener(enabled);
      } catch (error) {
        logger.error(TAG, `通知监听器失败: ${error}`);
      }
    });
  }

  /**
   * 获取过滤统计信息
   */
  public getFilterStats<T>(items: T[]): FilterStats {
    const total = items.length;
    const nsfw = items.filter(item => (item as ESObject).isNSFW === true).length;
    const sfw = total - nsfw;
    const filtered = this.sfwModeEnabled ? nsfw : 0;

    const stats: FilterStats = { total, nsfw, sfw, filtered };
    return stats;
  }
}
