// 文件路径: entry/src/main/ets/Framework/Enforcement/UnifiedDetailPageEnforcer.ets
/**
 * 统一详情页强制执行器
 * 在APP启动时强制检测并覆盖所有详情页设置为统一详情页
 * 
 * 功能：
 * 1. 启动时自动检测所有详情页设置
 * 2. 强制将所有场景的详情页类型覆盖为统一详情页（UNIFIED）
 * 3. 提供全局开关控制是否启用强制模式
 * 4. 记录执行日志便于调试
 */

import { logger } from 'manxia_core/src/main/ets/Utils/Logger';
import { SettingsManager, SettingKeys } from 'manxia_core/src/main/ets/Framework/Managers/SettingsManager';
import { DetailPageType, PageSettingKeys } from '../../pages/settings/PageSettingsSubPage';

const TAG = 'UnifiedDetailPageEnforcer';

/**
 * 强制执行结果
 */
export interface EnforcementResult {
  success: boolean;
  enforced: boolean;  // 是否执行了强制覆盖
  changes: EnforcementChange[];  // 变更记录
  message: string;
}

/**
 * 变更记录
 */
export interface EnforcementChange {
  scene: string;       // 场景名称
  settingKey: string;  // 设置键
  oldValue: string;    // 原值
  newValue: string;    // 新值
}

/**
 * 强制执行配置
 */
export interface EnforcementConfig {
  enabled: boolean;           // 是否启用强制模式
  targetType: DetailPageType; // 目标详情页类型（默认为 UNIFIED）
  logChanges: boolean;        // 是否记录变更日志
  showToast: boolean;         // 是否显示Toast提示
}

/**
 * 场景配置接口
 */
interface SceneConfig {
  name: string;
  key: string;
}

/**
 * 详情页设置状态接口
 */
export interface DetailPageStatus {
  manga: string;
  ebook: string;
  novel: string;
  forceEnabled: string;
  lastEnforcement: string;
}

/**
 * 设置键常量（扩展）
 */
export class EnforcementSettingKeys {
  // 强制使用统一详情页开关
  static readonly FORCE_UNIFIED_DETAIL_PAGE = 'force_unified_detail_page_enabled';
  // 强制执行上次执行时间戳
  static readonly LAST_ENFORCEMENT_TIMESTAMP = 'unified_detail_enforcement_timestamp';
}

/**
 * 统一详情页强制执行器类
 */
export class UnifiedDetailPageEnforcer {
  private static instance: UnifiedDetailPageEnforcer;
  private settingsManager: SettingsManager | null = null;
  private initialized: boolean = false;
  private lastEnforcementResult: EnforcementResult | null = null;

  private constructor() {}

  /**
   * 获取单例实例
   */
  static getInstance(): UnifiedDetailPageEnforcer {
    if (!UnifiedDetailPageEnforcer.instance) {
      UnifiedDetailPageEnforcer.instance = new UnifiedDetailPageEnforcer();
    }
    return UnifiedDetailPageEnforcer.instance;
  }

  /**
   * 初始化强制执行器
   * 必须在 SettingsManager 初始化后调用
   */
  async initialize(): Promise<void> {
    if (this.initialized) {
      logger.warn(TAG, '强制执行器已初始化，跳过');
      return;
    }

    try {
      this.settingsManager = SettingsManager.getInstance();
      
      if (!this.settingsManager.isInitialized()) {
        throw new Error('SettingsManager 尚未初始化');
      }

      this.initialized = true;
      logger.info(TAG, '✅ 统一详情页强制执行器初始化完成');
    } catch (error) {
      logger.error(TAG, `❌ 初始化失败: ${String(error)}`);
      throw error as Error;
    }
  }

  /**
   * 执行强制覆盖
   * 检测所有详情页设置并强制覆盖为统一详情页
   * 
   * @param config 可选配置，默认强制使用 UNIFIED
   * @returns 执行结果
   */
  async enforce(config?: EnforcementConfig): Promise<EnforcementResult> {
    // 手动合并配置，避免使用 spread 操作符
    const finalConfig: EnforcementConfig = {
      enabled: config !== undefined ? config.enabled : true,
      targetType: config !== undefined ? config.targetType : DetailPageType.UNIFIED,
      logChanges: config !== undefined ? config.logChanges : true,
      showToast: config !== undefined ? config.showToast : false
    };

    const result: EnforcementResult = {
      success: false,
      enforced: false,
      changes: [],
      message: ''
    };

    try {
      if (!this.initialized || !this.settingsManager) {
        throw new Error('强制执行器未初始化');
      }

      // 检查是否启用强制模式（全局开关）
      const forceEnabled = this.isForceEnabled();
      if (!forceEnabled && !finalConfig.enabled) {
        result.success = true;
        result.message = '强制模式未启用，跳过执行';
        logger.info(TAG, result.message);
        return result;
      }

      logger.info(TAG, '🔧 开始执行统一详情页强制覆盖...');

      // 定义需要检查的场景和对应的设置键
      const scenes: SceneConfig[] = this.getSceneConfigs();

      // 检测并覆盖每个场景的设置
      for (const scene of scenes) {
        const currentValue = this.settingsManager.getString(scene.key, DetailPageType.DEFAULT);
        
        if (currentValue !== finalConfig.targetType) {
          // 需要覆盖
          const change: EnforcementChange = {
            scene: scene.name,
            settingKey: scene.key,
            oldValue: currentValue,
            newValue: finalConfig.targetType
          };

          // 执行覆盖
          await this.settingsManager.setString(scene.key, finalConfig.targetType);
          
          result.changes.push(change);
          result.enforced = true;

          if (finalConfig.logChanges) {
            logger.info(TAG, `📝 ${scene.name}详情页: ${currentValue} → ${finalConfig.targetType}`);
          }
        } else {
          if (finalConfig.logChanges) {
            logger.debug(TAG, `✓ ${scene.name}详情页已是统一详情页，无需覆盖`);
          }
        }
      }

      // 记录执行时间戳
      await this.settingsManager.setString(
        EnforcementSettingKeys.LAST_ENFORCEMENT_TIMESTAMP,
        Date.now().toString()
      );

      result.success = true;
      if (result.enforced) {
        result.message = `已强制覆盖 ${result.changes.length} 个详情页设置为统一详情页`;
        logger.info(TAG, `✅ ${result.message}`);
      } else {
        result.message = '所有详情页设置已是统一详情页，无需覆盖';
        logger.info(TAG, `✅ ${result.message}`);
      }

      this.lastEnforcementResult = result;
      return result;

    } catch (error) {
      result.success = false;
      result.message = `强制覆盖失败: ${String(error)}`;
      logger.error(TAG, `❌ ${result.message}`);
      this.lastEnforcementResult = result;
      return result;
    }
  }

  /**
   * 检查强制模式是否启用
   * 默认为 true（强制启用统一详情页）
   */
  isForceEnabled(): boolean {
    if (!this.settingsManager) {
      return true; // 默认启用
    }
    return this.settingsManager.getBoolean(EnforcementSettingKeys.FORCE_UNIFIED_DETAIL_PAGE, true);
  }

  /**
   * 设置强制模式开关
   */
  async setForceEnabled(enabled: boolean): Promise<void> {
    if (!this.settingsManager) {
      throw new Error('强制执行器未初始化');
    }
    await this.settingsManager.setBoolean(EnforcementSettingKeys.FORCE_UNIFIED_DETAIL_PAGE, enabled);
    logger.info(TAG, `强制模式已${enabled ? '启用' : '禁用'}`);
  }

  /**
   * 获取上次执行结果
   */
  getLastEnforcementResult(): EnforcementResult | null {
    return this.lastEnforcementResult;
  }

  /**
   * 获取上次执行时间戳
   */
  getLastEnforcementTimestamp(): number {
    if (!this.settingsManager) {
      return 0;
    }
    const timestamp = this.settingsManager.getString(EnforcementSettingKeys.LAST_ENFORCEMENT_TIMESTAMP, '0');
    return parseInt(timestamp, 10) || 0;
  }

  /**
   * 检查当前所有设置是否都是统一详情页
   */
  isAllUnified(): boolean {
    if (!this.settingsManager) {
      return false;
    }

    const keys = [
      PageSettingKeys.MANGA_DETAIL_PAGE_TYPE,
      PageSettingKeys.EBOOK_DETAIL_PAGE_TYPE,
      PageSettingKeys.NOVEL_DETAIL_PAGE_TYPE
    ];

    for (const key of keys) {
      const value = this.settingsManager.getString(key, DetailPageType.DEFAULT);
      if (value !== DetailPageType.UNIFIED) {
        return false;
      }
    }
    return true;
  }

  /**
   * 获取场景配置列表
   */
  private getSceneConfigs(): SceneConfig[] {
    const mangaScene: SceneConfig = { name: '漫画', key: PageSettingKeys.MANGA_DETAIL_PAGE_TYPE };
    const ebookScene: SceneConfig = { name: '电子书', key: PageSettingKeys.EBOOK_DETAIL_PAGE_TYPE };
    const novelScene: SceneConfig = { name: '小说', key: PageSettingKeys.NOVEL_DETAIL_PAGE_TYPE };
    const scenes: SceneConfig[] = [mangaScene, ebookScene, novelScene];
    return scenes;
  }

  /**
   * 获取当前详情页设置状态
   */
  getCurrentStatus(): DetailPageStatus {
    const emptyStatus: DetailPageStatus = {
      manga: '',
      ebook: '',
      novel: '',
      forceEnabled: 'false',
      lastEnforcement: ''
    };
    
    if (!this.settingsManager) {
      return emptyStatus;
    }

    const status: DetailPageStatus = {
      manga: this.settingsManager.getString(PageSettingKeys.MANGA_DETAIL_PAGE_TYPE, DetailPageType.DEFAULT),
      ebook: this.settingsManager.getString(PageSettingKeys.EBOOK_DETAIL_PAGE_TYPE, DetailPageType.DEFAULT),
      novel: this.settingsManager.getString(PageSettingKeys.NOVEL_DETAIL_PAGE_TYPE, DetailPageType.DEFAULT),
      forceEnabled: this.isForceEnabled().toString(),
      lastEnforcement: new Date(this.getLastEnforcementTimestamp()).toISOString()
    };
    return status;
  }

  /**
   * 重置为默认设置（所有场景使用默认详情页）
   * 仅供测试或特殊情况使用
   */
  async resetToDefault(): Promise<void> {
    if (!this.settingsManager) {
      throw new Error('强制执行器未初始化');
    }

    await this.settingsManager.setString(PageSettingKeys.MANGA_DETAIL_PAGE_TYPE, DetailPageType.DEFAULT);
    await this.settingsManager.setString(PageSettingKeys.EBOOK_DETAIL_PAGE_TYPE, DetailPageType.DEFAULT);
    await this.settingsManager.setString(PageSettingKeys.NOVEL_DETAIL_PAGE_TYPE, DetailPageType.DEFAULT);
    
    logger.info(TAG, '已重置所有详情页设置为默认值');
  }

  /**
   * 检查是否已初始化
   */
  isInitialized(): boolean {
    return this.initialized;
  }
}

// 导出单例获取函数
export function getUnifiedDetailPageEnforcer(): UnifiedDetailPageEnforcer {
  return UnifiedDetailPageEnforcer.getInstance();
}
