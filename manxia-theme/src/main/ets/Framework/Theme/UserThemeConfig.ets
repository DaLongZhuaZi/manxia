import { SafeUtils } from 'manxia_core/src/main/ets/Utils/SafeUtils';
/**
 * 用户自定义主题配置系统（精简版）
 * 
 * 功能：
 * 1. 组件透明度自定义
 * 2. 特效开关（模糊、动画、阴影等）
 * 3. 与现有ThemeSettingsPage集成
 * 
 * 文件路径: entry/src/main/ets/Framework/Theme/UserThemeConfig.ets
 */

import { logger } from 'manxia_core/src/main/ets/Utils/Logger';
import { preferences } from '@kit.ArkData';
import { getContext } from 'manxia_core/src/main/ets/GlobalContext';

const TAG = 'UserThemeConfig';

// AppStorage keys for user theme config (用于声明式UI绑定)
export class USER_THEME_KEYS {
  static readonly CARD_OPACITY: string = 'userTheme_cardOpacity';
  static readonly NAV_BAR_OPACITY: string = 'userTheme_navBarOpacity';
  static readonly TAB_BAR_OPACITY: string = 'userTheme_tabBarOpacity';
  static readonly DIALOG_OPACITY: string = 'userTheme_dialogOpacity';
  static readonly FLOATING_BALL_OPACITY: string = 'userTheme_floatingBallOpacity';
  static readonly MENU_OPACITY: string = 'userTheme_menuOpacity';
  static readonly SIDEBAR_OPACITY: string = 'userTheme_sidebarOpacity';
  static readonly COMPONENT_CORNER_RADIUS: string = 'userTheme_componentCornerRadius';
  static readonly COVER_CORNER_RADIUS: string = 'userTheme_coverCornerRadius';
  static readonly CORNER_RADIUS: string = 'userTheme_cornerRadius';
  static readonly BLUR_ENABLED: string = 'userTheme_blurEnabled';
  static readonly SHADOW_ENABLED: string = 'userTheme_shadowEnabled';
  static readonly ANIMATION_ENABLED: string = 'userTheme_animationEnabled';
  static readonly GLASSMORPHISM_ENABLED: string = 'userTheme_glassmorphismEnabled';
  static readonly HDS_TAB_OPACITY_RATIO: string = 'userTheme_hdsTabOpacityRatio';
  static readonly HDS_TAB_MIN_OPACITY: string = 'userTheme_hdsTabMinOpacity';
  static readonly HDS_TAB_MAX_OPACITY: string = 'userTheme_hdsTabMaxOpacity';
  static readonly HDS_TAB_LIGHT_HIGHLIGHT_OPACITY: string = 'userTheme_hdsTabLightHighlightOpacity';
  static readonly HDS_TAB_DARK_HIGHLIGHT_OPACITY: string = 'userTheme_hdsTabDarkHighlightOpacity';
  static readonly HDS_TAB_MATERIAL_LEVEL: string = 'userTheme_hdsTabMaterialLevel';
  static readonly HDS_TAB_BLUR_ENABLED: string = 'userTheme_hdsTabBlurEnabled';
  static readonly HDS_TAB_SIDE_MARGIN: string = 'userTheme_hdsTabSideMargin';
  static readonly HDS_TAB_BOTTOM_MARGIN: string = 'userTheme_hdsTabBottomMargin';
}

// 保留旧的key以兼容
export const USER_THEME_CONFIG_VERSION_KEY = 'userThemeConfigVersion';

// ==================== 类型定义 ====================

/**
 * 透明度配置 - 组件透明度设置
 */
export interface TransparencyConfig {
  /** 导航栏透明度 (0-1) */
  navigationBar: number;
  /** 标签栏透明度 (0-1) */
  tabBar: number;
  /** 卡片透明度 (0-1) */
  card: number;
  /** 对话框透明度 (0-1) */
  dialog: number;
  /** 悬浮球透明度 (0-1) */
  floatingBall: number;
  /** 菜单透明度 (0-1) */
  menu: number;
  /** 侧边栏透明度 (0-1) */
  sidebar: number;
}

/**
 * 特效配置 - 视觉特效开关
 */
export interface EffectsConfig {
  /** 启用模糊效果 */
  enableBlur: boolean;
  /** 模糊强度 (0-100) */
  blurIntensity: number;
  /** 启用阴影效果 */
  enableShadow: boolean;
  /** 阴影强度 (0-100) */
  shadowIntensity: number;
  /** 启用动画效果 */
  enableAnimation: boolean;
  /** 动画速度倍率 (0.5-2.0) */
  animationSpeed: number;
  /** 启用圆角效果 */
  enableRoundedCorners: boolean;
  /** 组件圆角大小 (0-32) */
  componentCornerRadius: number;
  /** 封面图片圆角大小 (0-32) */
  coverCornerRadius: number;
  /** 启用玻璃拟态效果 */
  enableGlassmorphism: boolean;
}

/**
 * HdsTab 特效配置 - 主页面 HDS 底栏专用
 */
export interface HdsTabEffectsConfig {
  /** 透明度倍率 (0-1)，叠加主标签栏透明度 */
  opacityRatio: number;
  /** 最小可见不透明度 (0-1) */
  minOpacity: number;
  /** 最大可见不透明度 (0-1) */
  maxOpacity: number;
  /** 浅色模式高光强度 (0-1) */
  lightHighlightOpacity: number;
  /** 深色模式高光强度 (0-1) */
  darkHighlightOpacity: number;
  /** 材质档位，-1 表示跟随全局视觉效果设置 */
  materialLevel: number;
  /** 启用 HDS 自身模糊策略 */
  blurEnabled: boolean;
  /** 浮动条侧边留白 */
  sideMargin: number;
  /** 浮动条底部偏移 */
  bottomMargin: number;
}

interface StoredEffectsConfig extends Partial<EffectsConfig> {
  cornerRadius?: number;
}

interface StoredUserThemeProfile {
  id?: string;
  name?: string;
  lastModified?: number;
  transparency?: Partial<TransparencyConfig>;
  effects?: StoredEffectsConfig;
  hdsTabEffects?: Partial<HdsTabEffectsConfig>;
}

/**
 * 完整的用户主题配置
 */
export interface UserThemeProfile {
  /** 配置ID */
  id: string;
  /** 配置名称 */
  name: string;
  /** 最后修改时间 */
  lastModified: number;
  /** 透明度配置 */
  transparency: TransparencyConfig;
  /** 特效配置 */
  effects: EffectsConfig;
  /** HdsTab 特效配置 */
  hdsTabEffects: HdsTabEffectsConfig;
}

// ==================== 默认配置 ====================

/**
 * 默认透明度配置
 */
const DEFAULT_TRANSPARENCY: TransparencyConfig = {
  navigationBar: 1.0,
  tabBar: 1.0,
  card: 1.0,
  dialog: 0.95,
  floatingBall: 0.9,
  menu: 0.95,
  sidebar: 1.0
};

/**
 * 默认特效配置
 */
const DEFAULT_EFFECTS: EffectsConfig = {
  enableBlur: true,
  blurIntensity: 50,
  enableShadow: true,
  shadowIntensity: 30,
  enableAnimation: true,
  animationSpeed: 1.0,
  enableRoundedCorners: true,
  componentCornerRadius: 12,
  coverCornerRadius: 12,
  enableGlassmorphism: true
};

/**
 * 默认 HdsTab 特效配置
 */
const DEFAULT_HDS_TAB_EFFECTS: HdsTabEffectsConfig = {
  opacityRatio: 0.82,
  minOpacity: 0.68,
  maxOpacity: 0.90,
  lightHighlightOpacity: 0.50,
  darkHighlightOpacity: 0.34,
  materialLevel: 0,
  blurEnabled: true,
  sideMargin: 8,
  bottomMargin: 0
};

const LEGACY_DEFAULT_HDS_TAB_EFFECTS: HdsTabEffectsConfig = {
  opacityRatio: 0.72,
  minOpacity: 0.56,
  maxOpacity: 0.82,
  lightHighlightOpacity: 0.42,
  darkHighlightOpacity: 0.22,
  materialLevel: -1,
  blurEnabled: true,
  sideMargin: 8,
  bottomMargin: 0
};

function clampHdsTabUnitValue(value: number): number {
  return Math.max(0, Math.min(1, value));
}

function clampHdsTabSideMargin(value: number): number {
  return Math.max(0, Math.min(24, value));
}

function clampHdsTabBottomMargin(value: number): number {
  return Math.max(-8, Math.min(16, value));
}

function normalizeHdsTabMaterialLevel(value: number): number {
  if (value === -1 || value === 0 || value === 1 || value === 2) {
    return value;
  }
  return DEFAULT_HDS_TAB_EFFECTS.materialLevel;
}

/**
 * 复制透明度配置
 */
function copyTransparency(source: TransparencyConfig): TransparencyConfig {
  return {
    navigationBar: source.navigationBar,
    tabBar: source.tabBar,
    card: source.card,
    dialog: source.dialog,
    floatingBall: source.floatingBall,
    menu: source.menu,
    sidebar: source.sidebar
  };
}

/**
 * 复制特效配置
 */
function copyEffects(source: EffectsConfig): EffectsConfig {
  return {
    enableBlur: source.enableBlur,
    blurIntensity: source.blurIntensity,
    enableShadow: source.enableShadow,
    shadowIntensity: source.shadowIntensity,
    enableAnimation: source.enableAnimation,
    animationSpeed: source.animationSpeed,
    enableRoundedCorners: source.enableRoundedCorners,
    componentCornerRadius: source.componentCornerRadius,
    coverCornerRadius: source.coverCornerRadius,
    enableGlassmorphism: source.enableGlassmorphism
  };
}

/**
 * 复制 HdsTab 特效配置
 */
function copyHdsTabEffects(source: HdsTabEffectsConfig): HdsTabEffectsConfig {
  return {
    opacityRatio: source.opacityRatio,
    minOpacity: source.minOpacity,
    maxOpacity: source.maxOpacity,
    lightHighlightOpacity: source.lightHighlightOpacity,
    darkHighlightOpacity: source.darkHighlightOpacity,
    materialLevel: source.materialLevel,
    blurEnabled: source.blurEnabled,
    sideMargin: source.sideMargin,
    bottomMargin: source.bottomMargin
  };
}

function isLegacyDefaultHdsTabEffects(source: Partial<HdsTabEffectsConfig>): boolean {
  return source.opacityRatio === LEGACY_DEFAULT_HDS_TAB_EFFECTS.opacityRatio &&
    source.minOpacity === LEGACY_DEFAULT_HDS_TAB_EFFECTS.minOpacity &&
    source.maxOpacity === LEGACY_DEFAULT_HDS_TAB_EFFECTS.maxOpacity &&
    source.lightHighlightOpacity === LEGACY_DEFAULT_HDS_TAB_EFFECTS.lightHighlightOpacity &&
    source.darkHighlightOpacity === LEGACY_DEFAULT_HDS_TAB_EFFECTS.darkHighlightOpacity &&
    source.materialLevel === LEGACY_DEFAULT_HDS_TAB_EFFECTS.materialLevel &&
    source.blurEnabled === LEGACY_DEFAULT_HDS_TAB_EFFECTS.blurEnabled &&
    source.sideMargin === LEGACY_DEFAULT_HDS_TAB_EFFECTS.sideMargin &&
    source.bottomMargin === LEGACY_DEFAULT_HDS_TAB_EFFECTS.bottomMargin;
}

/**
 * 合并透明度配置（用partial覆盖base）
 */
function mergeTransparency(base: TransparencyConfig, partial: Partial<TransparencyConfig>): TransparencyConfig {
  return {
    navigationBar: partial.navigationBar !== undefined ? partial.navigationBar : base.navigationBar,
    tabBar: partial.tabBar !== undefined ? partial.tabBar : base.tabBar,
    card: partial.card !== undefined ? partial.card : base.card,
    dialog: partial.dialog !== undefined ? partial.dialog : base.dialog,
    floatingBall: partial.floatingBall !== undefined ? partial.floatingBall : base.floatingBall,
    menu: partial.menu !== undefined ? partial.menu : base.menu,
    sidebar: partial.sidebar !== undefined ? partial.sidebar : base.sidebar
  };
}

/**
 * 合并特效配置（用partial覆盖base）
 */
function mergeEffects(base: EffectsConfig, partial: Partial<EffectsConfig>): EffectsConfig {
  return {
    enableBlur: partial.enableBlur !== undefined ? partial.enableBlur : base.enableBlur,
    blurIntensity: partial.blurIntensity !== undefined ? partial.blurIntensity : base.blurIntensity,
    enableShadow: partial.enableShadow !== undefined ? partial.enableShadow : base.enableShadow,
    shadowIntensity: partial.shadowIntensity !== undefined ? partial.shadowIntensity : base.shadowIntensity,
    enableAnimation: partial.enableAnimation !== undefined ? partial.enableAnimation : base.enableAnimation,
    animationSpeed: partial.animationSpeed !== undefined ? partial.animationSpeed : base.animationSpeed,
    enableRoundedCorners: partial.enableRoundedCorners !== undefined ? partial.enableRoundedCorners : base.enableRoundedCorners,
    componentCornerRadius: partial.componentCornerRadius !== undefined ? partial.componentCornerRadius : base.componentCornerRadius,
    coverCornerRadius: partial.coverCornerRadius !== undefined ? partial.coverCornerRadius : base.coverCornerRadius,
    enableGlassmorphism: partial.enableGlassmorphism !== undefined ? partial.enableGlassmorphism : base.enableGlassmorphism
  };
}

/**
 * 合并 HdsTab 特效配置（用partial覆盖base）
 */
function mergeHdsTabEffects(base: HdsTabEffectsConfig, partial: Partial<HdsTabEffectsConfig>): HdsTabEffectsConfig {
  const minOpacity: number = clampHdsTabUnitValue(
    partial.minOpacity !== undefined ? partial.minOpacity : base.minOpacity
  );
  const rawMaxOpacity: number = clampHdsTabUnitValue(
    partial.maxOpacity !== undefined ? partial.maxOpacity : base.maxOpacity
  );
  return {
    opacityRatio: clampHdsTabUnitValue(
      partial.opacityRatio !== undefined ? partial.opacityRatio : base.opacityRatio
    ),
    minOpacity: minOpacity,
    maxOpacity: Math.max(minOpacity, rawMaxOpacity),
    lightHighlightOpacity: partial.lightHighlightOpacity !== undefined
      ? clampHdsTabUnitValue(partial.lightHighlightOpacity)
      : clampHdsTabUnitValue(base.lightHighlightOpacity),
    darkHighlightOpacity: partial.darkHighlightOpacity !== undefined
      ? clampHdsTabUnitValue(partial.darkHighlightOpacity)
      : clampHdsTabUnitValue(base.darkHighlightOpacity),
    materialLevel: normalizeHdsTabMaterialLevel(
      partial.materialLevel !== undefined ? partial.materialLevel : base.materialLevel
    ),
    blurEnabled: partial.blurEnabled !== undefined ? partial.blurEnabled : base.blurEnabled,
    sideMargin: clampHdsTabSideMargin(partial.sideMargin !== undefined ? partial.sideMargin : base.sideMargin),
    bottomMargin: clampHdsTabBottomMargin(
      partial.bottomMargin !== undefined ? partial.bottomMargin : base.bottomMargin
    )
  };
}

/**
 * 创建默认主题配置
 */
function createDefaultProfile(): UserThemeProfile {
  return {
    id: 'default',
    name: '默认配置',
    lastModified: Date.now(),
    transparency: copyTransparency(DEFAULT_TRANSPARENCY),
    effects: copyEffects(DEFAULT_EFFECTS),
    hdsTabEffects: copyHdsTabEffects(DEFAULT_HDS_TAB_EFFECTS)
  };
}

// ==================== 用户主题配置管理器 ====================

/**
 * 用户主题配置管理器
 * 单例模式，负责管理用户自定义主题配置
 */
export class UserThemeConfigManager {
  private static instance: UserThemeConfigManager | null = null;
  private preferencesStore: preferences.Preferences | null = null;
  private currentProfile: UserThemeProfile;
  private isInitialized: boolean = false;
  private changeCallbacks: Set<(profile: UserThemeProfile) => void> = new Set();
  
  private readonly PREFS_NAME = 'user_theme_config';
  private readonly CURRENT_PROFILE_KEY = 'current_profile';
  
  private constructor() {
    this.currentProfile = createDefaultProfile();
  }
  
  /**
   * 获取单例实例
   */
  public static getInstance(): UserThemeConfigManager {
    if (!UserThemeConfigManager.instance) {
      UserThemeConfigManager.instance = new UserThemeConfigManager();
    }
    return UserThemeConfigManager.instance;
  }
  
  /**
   * 初始化
   */
  public async initialize(): Promise<void> {
    if (this.isInitialized) return;
    
    try {
      logger.info(TAG, '开始初始化用户主题配置管理器');
      
      const context = getContext();
      this.preferencesStore = await preferences.getPreferences(context, this.PREFS_NAME);
      
      // 初始化AppStorage版本号
      if (!AppStorage.has(USER_THEME_CONFIG_VERSION_KEY)) {
        AppStorage.setOrCreate<number>(USER_THEME_CONFIG_VERSION_KEY, 0);
      }
      
      // 加载保存的配置
      await this.loadCurrentProfile();
      
      // 初始化时同步到AppStorage
      this.syncToAppStorage();
      
      this.isInitialized = true;
      logger.info(TAG, '用户主题配置管理器初始化完成');
    } catch (error) {
      const errMsg = error instanceof Error ? error.message : String(error);
      logger.error(TAG, `初始化失败: ${errMsg}`);
      this.isInitialized = true;
    }
  }
  
  /**
   * 加载当前配置
   */
  private async loadCurrentProfile(): Promise<void> {
    try {
      if (!this.preferencesStore) return;
      
      const profileJson = await this.preferencesStore.get(this.CURRENT_PROFILE_KEY, '') as string;
      if (profileJson && profileJson.length > 0) {
        const loaded = SafeUtils.parseObj(profileJson) as StoredUserThemeProfile;
        const loadedEffects: StoredEffectsConfig = loaded.effects ? loaded.effects : {};
        const legacyCornerRadius = loadedEffects.cornerRadius;
        const normalizedEffects: Partial<EffectsConfig> = {
          enableBlur: loadedEffects.enableBlur,
          blurIntensity: loadedEffects.blurIntensity,
          enableShadow: loadedEffects.enableShadow,
          shadowIntensity: loadedEffects.shadowIntensity,
          enableAnimation: loadedEffects.enableAnimation,
          animationSpeed: loadedEffects.animationSpeed,
          enableRoundedCorners: loadedEffects.enableRoundedCorners,
          componentCornerRadius: loadedEffects.componentCornerRadius !== undefined
            ? loadedEffects.componentCornerRadius
            : legacyCornerRadius,
          coverCornerRadius: loadedEffects.coverCornerRadius !== undefined
            ? loadedEffects.coverCornerRadius
            : legacyCornerRadius,
          enableGlassmorphism: loadedEffects.enableGlassmorphism
        };
        // 合并默认值，确保新增字段有默认值
        const defaultProfile = createDefaultProfile();
        const loadedHdsTabEffects: Partial<HdsTabEffectsConfig> = loaded.hdsTabEffects ? loaded.hdsTabEffects : {};
        const shouldMigrateHdsTabDefaults: boolean = isLegacyDefaultHdsTabEffects(loadedHdsTabEffects);
        const mergedHdsTabEffects: HdsTabEffectsConfig = mergeHdsTabEffects(
          DEFAULT_HDS_TAB_EFFECTS,
          shouldMigrateHdsTabDefaults ? {} : loadedHdsTabEffects
        );
        this.currentProfile = {
          id: loaded.id ? loaded.id : defaultProfile.id,
          name: loaded.name ? loaded.name : defaultProfile.name,
          lastModified: loaded.lastModified ? loaded.lastModified : defaultProfile.lastModified,
          transparency: mergeTransparency(DEFAULT_TRANSPARENCY, loaded.transparency ? loaded.transparency : {}),
          effects: mergeEffects(DEFAULT_EFFECTS, normalizedEffects),
          hdsTabEffects: mergedHdsTabEffects
        };
        if (shouldMigrateHdsTabDefaults) {
          await this.saveCurrentProfile();
          logger.info(TAG, '已将旧版 HdsTab 默认效果迁移到新版默认效果');
        }
        logger.info(TAG, `加载当前配置: ${this.currentProfile.name}`);
      }
    } catch (error) {
      logger.error(TAG, '加载当前配置失败', error);
      this.currentProfile = createDefaultProfile();
    }
  }
  
  /**
   * 保存当前配置
   */
  private async saveCurrentProfile(): Promise<void> {
    try {
      if (!this.preferencesStore) return;
      
      this.currentProfile.lastModified = Date.now();
      await this.preferencesStore.put(this.CURRENT_PROFILE_KEY, JSON.stringify(this.currentProfile));
      await this.preferencesStore.flush();
      
      logger.debug(TAG, '当前配置已保存');
    } catch (error) {
      logger.error(TAG, '保存当前配置失败', error);
    }
  }
  
  // ==================== 公开API ====================
  
  /**
   * 获取当前配置
   */
  public getCurrentProfile(): UserThemeProfile {
    return {
      id: this.currentProfile.id,
      name: this.currentProfile.name,
      lastModified: this.currentProfile.lastModified,
      transparency: copyTransparency(this.currentProfile.transparency),
      effects: copyEffects(this.currentProfile.effects),
      hdsTabEffects: copyHdsTabEffects(this.currentProfile.hdsTabEffects)
    };
  }
  
  /**
   * 设置透明度配置
   */
  public async setTransparency(transparency: Partial<TransparencyConfig>): Promise<void> {
    this.currentProfile.transparency = mergeTransparency(this.currentProfile.transparency, transparency);
    await this.saveCurrentProfile();
    this.notifyChange();
  }
  
  /**
   * 设置特效配置
   */
  public async setEffects(effects: Partial<EffectsConfig>): Promise<void> {
    this.currentProfile.effects = mergeEffects(this.currentProfile.effects, effects);
    await this.saveCurrentProfile();
    this.notifyChange();
  }

  /**
   * 设置 HdsTab 特效配置
   */
  public async setHdsTabEffects(hdsTabEffects: Partial<HdsTabEffectsConfig>): Promise<void> {
    this.currentProfile.hdsTabEffects = mergeHdsTabEffects(this.currentProfile.hdsTabEffects, hdsTabEffects);
    await this.saveCurrentProfile();
    this.notifyChange();
  }
  
  /**
   * 重置为默认配置
   */
  public async resetToDefault(): Promise<void> {
    this.currentProfile = createDefaultProfile();
    await this.saveCurrentProfile();
    this.notifyChange();
    logger.info(TAG, '重置为默认配置');
  }
  
  /**
   * 注册配置变化监听器
   */
  public onConfigChange(callback: (profile: UserThemeProfile) => void): void {
    this.changeCallbacks.add(callback);
  }
  
  /**
   * 移除配置变化监听器
   */
  public offConfigChange(callback: (profile: UserThemeProfile) => void): void {
    this.changeCallbacks.delete(callback);
  }
  
  /**
   * 通知配置变化
   */
  private notifyChange(): void {
    const profile = this.getCurrentProfile();
    this.changeCallbacks.forEach(callback => {
      try {
        callback(profile);
      } catch (error) {
        logger.error(TAG, '配置变化回调执行失败', error);
      }
    });
    
    // 同步配置值到AppStorage以触发声明式UI刷新
    this.syncToAppStorage();
  }
  
  /**
   * 同步配置到AppStorage（用于声明式UI绑定）
   */
  private syncToAppStorage(): void {
    try {
      const profile = this.currentProfile;
      // 透明度配置
      AppStorage.setOrCreate<number>(USER_THEME_KEYS.CARD_OPACITY, profile.transparency.card);
      AppStorage.setOrCreate<number>(USER_THEME_KEYS.NAV_BAR_OPACITY, profile.transparency.navigationBar);
      AppStorage.setOrCreate<number>(USER_THEME_KEYS.TAB_BAR_OPACITY, profile.transparency.tabBar);
      AppStorage.setOrCreate<number>(USER_THEME_KEYS.DIALOG_OPACITY, profile.transparency.dialog);
      AppStorage.setOrCreate<number>(USER_THEME_KEYS.FLOATING_BALL_OPACITY, profile.transparency.floatingBall);
      AppStorage.setOrCreate<number>(USER_THEME_KEYS.MENU_OPACITY, profile.transparency.menu);
      AppStorage.setOrCreate<number>(USER_THEME_KEYS.SIDEBAR_OPACITY, profile.transparency.sidebar);
      // 特效配置
      AppStorage.setOrCreate<number>(USER_THEME_KEYS.COMPONENT_CORNER_RADIUS, profile.effects.componentCornerRadius);
      AppStorage.setOrCreate<number>(USER_THEME_KEYS.COVER_CORNER_RADIUS, profile.effects.coverCornerRadius);
      AppStorage.setOrCreate<number>(USER_THEME_KEYS.CORNER_RADIUS, profile.effects.componentCornerRadius);
      AppStorage.setOrCreate<boolean>(USER_THEME_KEYS.BLUR_ENABLED, profile.effects.enableBlur);
      AppStorage.setOrCreate<boolean>(USER_THEME_KEYS.SHADOW_ENABLED, profile.effects.enableShadow);
      AppStorage.setOrCreate<boolean>(USER_THEME_KEYS.ANIMATION_ENABLED, profile.effects.enableAnimation);
      AppStorage.setOrCreate<boolean>(USER_THEME_KEYS.GLASSMORPHISM_ENABLED, profile.effects.enableGlassmorphism);
      // HdsTab 特效配置
      AppStorage.setOrCreate<number>(USER_THEME_KEYS.HDS_TAB_OPACITY_RATIO, profile.hdsTabEffects.opacityRatio);
      AppStorage.setOrCreate<number>(USER_THEME_KEYS.HDS_TAB_MIN_OPACITY, profile.hdsTabEffects.minOpacity);
      AppStorage.setOrCreate<number>(USER_THEME_KEYS.HDS_TAB_MAX_OPACITY, profile.hdsTabEffects.maxOpacity);
      AppStorage.setOrCreate<number>(
        USER_THEME_KEYS.HDS_TAB_LIGHT_HIGHLIGHT_OPACITY,
        profile.hdsTabEffects.lightHighlightOpacity
      );
      AppStorage.setOrCreate<number>(
        USER_THEME_KEYS.HDS_TAB_DARK_HIGHLIGHT_OPACITY,
        profile.hdsTabEffects.darkHighlightOpacity
      );
      AppStorage.setOrCreate<number>(USER_THEME_KEYS.HDS_TAB_MATERIAL_LEVEL, profile.hdsTabEffects.materialLevel);
      AppStorage.setOrCreate<boolean>(USER_THEME_KEYS.HDS_TAB_BLUR_ENABLED, profile.hdsTabEffects.blurEnabled);
      AppStorage.setOrCreate<number>(USER_THEME_KEYS.HDS_TAB_SIDE_MARGIN, profile.hdsTabEffects.sideMargin);
      AppStorage.setOrCreate<number>(USER_THEME_KEYS.HDS_TAB_BOTTOM_MARGIN, profile.hdsTabEffects.bottomMargin);
      logger.debug(TAG, '配置已同步到AppStorage');
    } catch (error) {
      logger.error(TAG, '同步配置到AppStorage失败', error);
    }
  }
  
  // ==================== 便捷访问方法 ====================
  
  /** 是否启用模糊 */
  public get blurEnabled(): boolean {
    return this.currentProfile.effects.enableBlur;
  }
  
  /** 获取模糊强度 */
  public get blurIntensity(): number {
    return this.currentProfile.effects.blurIntensity;
  }
  
  /** 是否启用阴影 */
  public get shadowEnabled(): boolean {
    return this.currentProfile.effects.enableShadow;
  }
  
  /** 是否启用动画 */
  public get animationEnabled(): boolean {
    return this.currentProfile.effects.enableAnimation;
  }
  
  /** 获取动画速度 */
  public get animationSpeed(): number {
    return this.currentProfile.effects.animationSpeed;
  }
  
  /** 获取组件圆角大小 */
  public get componentCornerRadius(): number {
    return this.currentProfile.effects.enableRoundedCorners ? this.currentProfile.effects.componentCornerRadius : 0;
  }

  /** 获取封面图片圆角大小 */
  public get coverCornerRadius(): number {
    return this.currentProfile.effects.enableRoundedCorners ? this.currentProfile.effects.coverCornerRadius : 0;
  }

  /** 兼容旧调用，等价于组件圆角 */
  public get cornerRadius(): number {
    return this.componentCornerRadius;
  }
  
  /** 是否启用玻璃拟态 */
  public get glassmorphismEnabled(): boolean {
    return this.currentProfile.effects.enableGlassmorphism;
  }

  /** 获取 HdsTab 特效配置 */
  public get hdsTabEffects(): HdsTabEffectsConfig {
    return copyHdsTabEffects(this.currentProfile.hdsTabEffects);
  }
  
  /** 获取导航栏透明度 */
  public get navigationBarTransparency(): number {
    return this.currentProfile.transparency.navigationBar;
  }
  
  /** 获取卡片透明度 */
  public get cardTransparency(): number {
    return this.currentProfile.transparency.card;
  }
  
  /** 获取对话框透明度 */
  public get dialogTransparency(): number {
    return this.currentProfile.transparency.dialog;
  }
  
  /** 获取悬浮球透明度 */
  public get floatingBallTransparency(): number {
    return this.currentProfile.transparency.floatingBall;
  }
}

/**
 * 导出单例实例
 */
export const userThemeConfig = UserThemeConfigManager.getInstance();
