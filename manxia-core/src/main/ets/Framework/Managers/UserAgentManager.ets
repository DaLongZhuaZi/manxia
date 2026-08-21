/**
 * UserAgent管理器
 * 统一管理全局和图源级别的User-Agent设置
 */

import { logger } from '../../Utils/Logger';
import { SettingKeys } from '../Contracts/SettingKeys';
import { ISettingsManagerFacade, SettingsManagerHolder } from '../Contracts/ISettingsManagerFacade';
import { IDataManagerFacade, DataManagerHolder } from '../Contracts/IDataManagerFacade';
import { UserSettingsDatabaseRecord } from '../Database/DatabaseTypes';

const TAG = 'UserAgentManager';

/**
 * 默认User-Agent常量
 */
// 默认User-Agent接口
interface DefaultUserAgents {
  MOBILE_CHROME: string;
  DESKTOP_CHROME: string;
  DESKTOP_FIREFOX: string;
  MOBILE_SAFARI: string;
}

export const DEFAULT_USER_AGENTS: DefaultUserAgents = {
  MOBILE_CHROME: 'Mozilla/5.0 (Linux; Android 14; Pixel 8) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Mobile Safari/537.36',
  DESKTOP_CHROME: 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36',
  DESKTOP_FIREFOX: 'Mozilla/5.0 (Windows NT 10.0; Win64; x64; rv:121.0) Gecko/20100101 Firefox/121.0',
  MOBILE_SAFARI: 'Mozilla/5.0 (iPhone; CPU iPhone OS 17_2 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.2 Mobile/15E148 Safari/604.1'
};

/**
 * UserAgent管理器类
 */
export class UserAgentManager {
  private static instance: UserAgentManager;
  private settingsManager: ISettingsManagerFacade;
  private dataManager: IDataManagerFacade;
  
  // 缓存图源级别的UA设置
  private sourceUACache: Map<number, string | null> = new Map();

  private constructor() {
    this.settingsManager = SettingsManagerHolder.get();
    this.dataManager = DataManagerHolder.get();
  }

  static getInstance(): UserAgentManager {
    if (!UserAgentManager.instance) {
      UserAgentManager.instance = new UserAgentManager();
    }
    return UserAgentManager.instance;
  }

  /**
   * 获取指定图源应使用的User-Agent
   * 优先级：图源级别设置 > 全局设置 > 图源JSON配置 > 默认值
   * @param sourceId 图源ID
   * @param sourceConfigUA 图源JSON配置中的UA（可选）
   * @returns User-Agent字符串
   */
  async getUserAgent(sourceId: number, sourceConfigUA?: string): Promise<string> {
    try {
      // 1. 检查图源级别的自定义UA设置
      const sourceUA = await this.getSourceUserAgent(sourceId);
      if (sourceUA) {
        logger.debug(TAG, `使用图源级别UA: sourceId=${sourceId}`);
        return sourceUA;
      }

      // 2. 检查全局自定义UA设置
      const globalUA = this.getGlobalUserAgent();
      if (globalUA) {
        logger.debug(TAG, `使用全局UA: sourceId=${sourceId}`);
        return globalUA;
      }

      // 3. 使用图源JSON配置中的UA
      if (sourceConfigUA && sourceConfigUA.length > 0) {
        logger.debug(TAG, `使用图源配置UA: sourceId=${sourceId}`);
        return sourceConfigUA;
      }

      // 4. 返回默认UA
      logger.debug(TAG, `使用默认UA: sourceId=${sourceId}`);
      return DEFAULT_USER_AGENTS.MOBILE_CHROME;
    } catch (error) {
      logger.error(TAG, `获取UA失败: sourceId=${sourceId}`, String(error));
      return DEFAULT_USER_AGENTS.MOBILE_CHROME;
    }
  }

  /**
   * 获取图源级别的自定义User-Agent
   * @param sourceId 图源ID
   * @returns User-Agent字符串，如果未启用则返回null
   */
  async getSourceUserAgent(sourceId: number): Promise<string | null> {
    try {
      // 检查缓存
      if (this.sourceUACache.has(sourceId)) {
        return this.sourceUACache.get(sourceId) || null;
      }

      // 从数据库加载
      const enabledRecord: UserSettingsDatabaseRecord | null = 
        await this.dataManager.getSourceUserSetting(sourceId, 'network.userAgentEnabled');
      
      if (!enabledRecord || enabledRecord.settingValue !== '1') {
        this.sourceUACache.set(sourceId, null);
        return null;
      }

      const uaRecord: UserSettingsDatabaseRecord | null = 
        await this.dataManager.getSourceUserSetting(sourceId, 'network.userAgent');
      
      if (uaRecord && uaRecord.settingValue && uaRecord.settingValue.length > 0) {
        this.sourceUACache.set(sourceId, uaRecord.settingValue);
        return uaRecord.settingValue;
      }

      this.sourceUACache.set(sourceId, null);
      return null;
    } catch (error) {
      logger.error(TAG, `获取图源UA失败: sourceId=${sourceId}`, String(error));
      return null;
    }
  }

  /**
   * 获取全局自定义User-Agent
   * @returns User-Agent字符串，如果未启用则返回null
   */
  getGlobalUserAgent(): string | null {
    try {
      const enabled = this.settingsManager.getBoolean(SettingKeys.GLOBAL_USER_AGENT_ENABLED, false);
      if (!enabled) {
        return null;
      }

      const ua = this.settingsManager.getString(SettingKeys.GLOBAL_USER_AGENT, '');
      if (ua && ua.length > 0) {
        return ua;
      }

      return null;
    } catch (error) {
      logger.error(TAG, '获取全局UA失败', String(error));
      return null;
    }
  }

  /**
   * 清除图源UA缓存
   * @param sourceId 图源ID，不传则清除所有缓存
   */
  clearCache(sourceId?: number): void {
    if (sourceId !== undefined) {
      this.sourceUACache.delete(sourceId);
    } else {
      this.sourceUACache.clear();
    }
  }

  /**
   * 获取默认User-Agent
   */
  getDefaultUserAgent(): string {
    return DEFAULT_USER_AGENTS.MOBILE_CHROME;
  }
}
