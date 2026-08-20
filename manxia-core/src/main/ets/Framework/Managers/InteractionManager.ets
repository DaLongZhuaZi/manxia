import { SafeUtils } from 'manxia_core/src/main/ets/Utils/SafeUtils';
/**
 * 全局交互管理器
 * 管理震动、触觉反馈等交互体验
 * 采用单例模式，支持按页面/功能配置
 */

import { vibrator } from '@kit.SensorServiceKit';
import { logger } from 'manxia_core/src/main/ets/Utils/Logger';
import { preferences } from '@kit.ArkData';
import { getContext } from 'manxia_theme/src/main/ets/GlobalContext';

const TAG = 'InteractionManager';

/**
 * 震动场景枚举
 */
export enum VibrationScene {
  // 通用场景
  BUTTON_CLICK = 'button_click',           // 按钮点击
  TOGGLE_SWITCH = 'toggle_switch',         // 开关切换
  LIST_ITEM_SELECT = 'list_item_select',   // 列表项选择
  LONG_PRESS = 'long_press',               // 长按
  SWIPE_ACTION = 'swipe_action',           // 滑动操作
  
  // 阅读器场景
  PAGE_TURN = 'page_turn',                 // 翻页
  CHAPTER_CHANGE = 'chapter_change',       // 章节切换
  BOOKMARK_ADD = 'bookmark_add',           // 添加书签
  
  // 下载场景
  DOWNLOAD_COMPLETE = 'download_complete', // 下载完成
  DOWNLOAD_ERROR = 'download_error',       // 下载错误
  
  // 系统场景
  SUCCESS = 'success',                     // 成功反馈
  ERROR = 'error',                         // 错误反馈
  WARNING = 'warning',                     // 警告反馈
  NOTIFICATION = 'notification',           // 通知
}

/**
 * 震动强度枚举
 */
export enum VibrationIntensity {
  LEVEL_1 = 'level_1',   // 1档
  LEVEL_2 = 'level_2',   // 2档
  LEVEL_3 = 'level_3',   // 3档
  LEVEL_4 = 'level_4',   // 4档
  LEVEL_5 = 'level_5',   // 5档
}

/**
 * 交互设置接口
 */
export interface InteractionSettings {
  // 全局开关
  vibrationEnabled: boolean;
  
  // 按场景配置
  sceneSettings: Record<string, boolean>;
  
  // 震动强度
  vibrationIntensity: VibrationIntensity;
}

/**
 * 默认交互设置
 */
const DEFAULT_SETTINGS: InteractionSettings = {
  vibrationEnabled: true,
  sceneSettings: {
    [VibrationScene.BUTTON_CLICK]: true,
    [VibrationScene.TOGGLE_SWITCH]: true,
    [VibrationScene.LIST_ITEM_SELECT]: true,
    [VibrationScene.LONG_PRESS]: true,
    [VibrationScene.SWIPE_ACTION]: true,
    [VibrationScene.PAGE_TURN]: false,        // 翻页默认关闭，避免频繁震动
    [VibrationScene.CHAPTER_CHANGE]: true,
    [VibrationScene.BOOKMARK_ADD]: true,
    [VibrationScene.DOWNLOAD_COMPLETE]: true,
    [VibrationScene.DOWNLOAD_ERROR]: true,
    [VibrationScene.SUCCESS]: true,
    [VibrationScene.ERROR]: true,
    [VibrationScene.WARNING]: true,
    [VibrationScene.NOTIFICATION]: true,
  },
  vibrationIntensity: VibrationIntensity.LEVEL_3,
};

/**
 * 全局交互管理器类
 */
export class InteractionManager {
  private static instance: InteractionManager | null = null;
  private settings: InteractionSettings = this.createDefaultSettings();
  private preferencesStore: preferences.Preferences | null = null;
  private readonly SETTINGS_KEY = 'interaction_settings';
  private isInitialized: boolean = false;

  private constructor() {
    this.settings = this.createDefaultSettings();
  }

  private createDefaultSettings(): InteractionSettings {
    const sceneSettings: Record<string, boolean> = {};
    sceneSettings[VibrationScene.BUTTON_CLICK] = true;
    sceneSettings[VibrationScene.TOGGLE_SWITCH] = true;
    sceneSettings[VibrationScene.LIST_ITEM_SELECT] = true;
    sceneSettings[VibrationScene.LONG_PRESS] = true;
    sceneSettings[VibrationScene.SWIPE_ACTION] = true;
    sceneSettings[VibrationScene.PAGE_TURN] = false;
    sceneSettings[VibrationScene.CHAPTER_CHANGE] = true;
    sceneSettings[VibrationScene.BOOKMARK_ADD] = true;
    sceneSettings[VibrationScene.DOWNLOAD_COMPLETE] = true;
    sceneSettings[VibrationScene.DOWNLOAD_ERROR] = true;
    sceneSettings[VibrationScene.SUCCESS] = true;
    sceneSettings[VibrationScene.ERROR] = true;
    sceneSettings[VibrationScene.WARNING] = true;
    sceneSettings[VibrationScene.NOTIFICATION] = true;
    
    const settings: InteractionSettings = {
      vibrationEnabled: true,
      sceneSettings: sceneSettings,
      vibrationIntensity: VibrationIntensity.LEVEL_3,
    };
    return settings;
  }

  /**
   * 获取单例实例
   */
  public static getInstance(): InteractionManager {
    if (!InteractionManager.instance) {
      InteractionManager.instance = new InteractionManager();
    }
    return InteractionManager.instance;
  }

  /**
   * 初始化
   */
  public async initialize(): Promise<void> {
    if (this.isInitialized) {
      return;
    }

    try {
      const context = getContext();
      if (context) {
        this.preferencesStore = await preferences.getPreferences(context, 'interaction_prefs');
        await this.loadSettings();
      }
      this.isInitialized = true;
      logger.info(TAG, '交互管理器初始化完成');
    } catch (error) {
      logger.error(TAG, `初始化失败: ${String(error)}`);
      this.isInitialized = true; // 即使失败也标记为已初始化
    }
  }

  /**
   * 加载设置
   */
  private async loadSettings(): Promise<void> {
    try {
      if (!this.preferencesStore) return;
      
      const settingsJson = await this.preferencesStore.get(this.SETTINGS_KEY, '') as string;
      if (settingsJson) {
        const saved = SafeUtils.parseObj(settingsJson) as InteractionSettings;
        if (saved.vibrationEnabled !== undefined) {
          this.settings.vibrationEnabled = saved.vibrationEnabled;
        }
        if (saved.vibrationIntensity !== undefined) {
          this.settings.vibrationIntensity = saved.vibrationIntensity;
        }
        if (saved.sceneSettings) {
          const scenes = Object.keys(saved.sceneSettings);
          for (let i = 0; i < scenes.length; i++) {
            const scene = scenes[i];
            this.settings.sceneSettings[scene] = saved.sceneSettings[scene];
          }
        }
      }
      logger.debug(TAG, '设置加载完成');
    } catch (error) {
      logger.error(TAG, `加载设置失败: ${String(error)}`);
    }
  }

  /**
   * 保存设置
   */
  private async saveSettings(): Promise<void> {
    try {
      if (!this.preferencesStore) return;
      
      await this.preferencesStore.put(this.SETTINGS_KEY, JSON.stringify(this.settings));
      await this.preferencesStore.flush();
      logger.debug(TAG, '设置保存完成');
    } catch (error) {
      logger.error(TAG, `保存设置失败: ${String(error)}`);
    }
  }

  /**
   * 触发震动
   * @param scene 震动场景
   */
  public vibrate(scene: VibrationScene): void {
    // 检查全局开关
    if (!this.settings.vibrationEnabled) {
      return;
    }

    // 检查场景开关
    if (this.settings.sceneSettings[scene] === false) {
      return;
    }

    try {
      const duration = this.getVibrationDuration(scene);
      vibrator.startVibration({
        type: 'time',
        duration: duration,
      }, {
        id: 0,
        usage: 'touch',
      });
    } catch (error) {
      // 震动失败不影响主流程，静默处理
      logger.debug(TAG, `震动失败: ${String(error)}`);
    }
  }

  /**
   * 根据场景和强度获取震动时长
   */
  private getVibrationDuration(scene: VibrationScene): number {
    // 基础震动时长（毫秒）- 大幅提高基础值
    const baseDurations: Record<VibrationScene, number> = {
      [VibrationScene.BUTTON_CLICK]: 50,
      [VibrationScene.TOGGLE_SWITCH]: 60,
      [VibrationScene.LIST_ITEM_SELECT]: 50,
      [VibrationScene.LONG_PRESS]: 100,
      [VibrationScene.SWIPE_ACTION]: 60,
      [VibrationScene.PAGE_TURN]: 30,
      [VibrationScene.CHAPTER_CHANGE]: 80,
      [VibrationScene.BOOKMARK_ADD]: 80,
      [VibrationScene.DOWNLOAD_COMPLETE]: 150,
      [VibrationScene.DOWNLOAD_ERROR]: 200,
      [VibrationScene.SUCCESS]: 100,
      [VibrationScene.ERROR]: 180,
      [VibrationScene.WARNING]: 120,
      [VibrationScene.NOTIFICATION]: 100,
    };

    const base = baseDurations[scene] || 50;
    
    // 根据5档强度调整（1档=原强烈，5档=最强）
    switch (this.settings.vibrationIntensity) {
      case VibrationIntensity.LEVEL_1:
        return base;
      case VibrationIntensity.LEVEL_2:
        return base * 1.3;
      case VibrationIntensity.LEVEL_3:
        return base * 1.6;
      case VibrationIntensity.LEVEL_4:
        return base * 2.0;
      case VibrationIntensity.LEVEL_5:
        return base * 2.5;
      default:
        return base * 1.6;
    }
  }

  /**
   * 获取当前设置
   */
  public getSettings(): InteractionSettings {
    const copy: InteractionSettings = {
      vibrationEnabled: this.settings.vibrationEnabled,
      sceneSettings: {},
      vibrationIntensity: this.settings.vibrationIntensity,
    };
    const scenes = Object.keys(this.settings.sceneSettings);
    for (let i = 0; i < scenes.length; i++) {
      const scene = scenes[i];
      copy.sceneSettings[scene] = this.settings.sceneSettings[scene];
    }
    return copy;
  }

  /**
   * 设置全局震动开关
   */
  public async setVibrationEnabled(enabled: boolean): Promise<void> {
    this.settings.vibrationEnabled = enabled;
    await this.saveSettings();
  }

  /**
   * 设置场景震动开关
   */
  public async setSceneEnabled(scene: VibrationScene, enabled: boolean): Promise<void> {
    this.settings.sceneSettings[scene] = enabled;
    await this.saveSettings();
  }

  /**
   * 设置震动强度
   */
  public async setVibrationIntensity(intensity: VibrationIntensity): Promise<void> {
    this.settings.vibrationIntensity = intensity;
    await this.saveSettings();
  }

  /**
   * 重置为默认设置
   */
  public async resetToDefault(): Promise<void> {
    this.settings = this.createDefaultSettings();
    await this.saveSettings();
    logger.info(TAG, '已重置为默认设置');
  }

  /**
   * 获取场景显示名称
   */
  public static getSceneDisplayName(scene: VibrationScene): string {
    const names: Record<VibrationScene, string> = {
      [VibrationScene.BUTTON_CLICK]: '按钮点击',
      [VibrationScene.TOGGLE_SWITCH]: '开关切换',
      [VibrationScene.LIST_ITEM_SELECT]: '列表选择',
      [VibrationScene.LONG_PRESS]: '长按操作',
      [VibrationScene.SWIPE_ACTION]: '滑动操作',
      [VibrationScene.PAGE_TURN]: '翻页',
      [VibrationScene.CHAPTER_CHANGE]: '章节切换',
      [VibrationScene.BOOKMARK_ADD]: '添加书签',
      [VibrationScene.DOWNLOAD_COMPLETE]: '下载完成',
      [VibrationScene.DOWNLOAD_ERROR]: '下载错误',
      [VibrationScene.SUCCESS]: '成功提示',
      [VibrationScene.ERROR]: '错误提示',
      [VibrationScene.WARNING]: '警告提示',
      [VibrationScene.NOTIFICATION]: '通知提醒',
    };
    return names[scene] || scene;
  }

  /**
   * 获取所有场景列表
   */
  public static getAllScenes(): VibrationScene[] {
    return [
      VibrationScene.BUTTON_CLICK, VibrationScene.TOGGLE_SWITCH, VibrationScene.LIST_ITEM_SELECT,
      VibrationScene.LONG_PRESS, VibrationScene.SWIPE_ACTION, VibrationScene.PAGE_TURN,
      VibrationScene.CHAPTER_CHANGE, VibrationScene.BOOKMARK_ADD, VibrationScene.DOWNLOAD_COMPLETE,
      VibrationScene.DOWNLOAD_ERROR, VibrationScene.SUCCESS, VibrationScene.ERROR,
      VibrationScene.WARNING, VibrationScene.NOTIFICATION
    ];
  }

  /**
   * 获取强度显示名称
   */
  public static getIntensityDisplayName(intensity: VibrationIntensity): string {
    const names: Record<VibrationIntensity, string> = {
      [VibrationIntensity.LEVEL_1]: '1档',
      [VibrationIntensity.LEVEL_2]: '2档',
      [VibrationIntensity.LEVEL_3]: '3档',
      [VibrationIntensity.LEVEL_4]: '4档',
      [VibrationIntensity.LEVEL_5]: '5档',
    };
    return names[intensity] || intensity;
  }

  /**
   * 获取所有强度列表
   */
  public static getAllIntensities(): VibrationIntensity[] {
    return [
      VibrationIntensity.LEVEL_1,
      VibrationIntensity.LEVEL_2,
      VibrationIntensity.LEVEL_3,
      VibrationIntensity.LEVEL_4,
      VibrationIntensity.LEVEL_5,
    ];
  }
}
