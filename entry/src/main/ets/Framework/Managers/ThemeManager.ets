// 文件路径: src/main/ets/Framework/Managers/ThemeManager.ets
/**
 * 主题管理器
 * 负责应用主题的切换、保存和加载
 * 采用单例模式，支持主题变化监听
 */

import { logger } from '../../Utils/Logger';
import { preferences } from '@kit.ArkData';
import { Configuration } from '@kit.AbilityKit';
import { getContext } from '../../GlobalContext';
import { CommonModifier } from '@kit.ArkUI';
import { colorMap } from '../../Data/ResourceMap';
import { AppColors, ColorRole } from '../Theme/AppColors';
import { UserThemeConfigManager, UserThemeProfile } from '../Theme/UserThemeConfig';

const TAG = 'ThemeManager';

/**
 * 主题类型枚举
 */
export enum ThemeType {
  LIGHT = 'light',
  DARK = 'dark',
  AUTO = 'auto',
  PRIVACY = 'privacy'
}

/**
 * 主题配置接口
 */
export interface ThemeConfig {
  name: string;
  displayName: string;
  primaryColor: string;
  backgroundColor: string;
  textColor: string;
  cardColor: string;
  borderColor: string;
  shadowColor: string;
}

/**
 * 自定义主题数据接口
 */
export interface CustomThemeData {
  id: string;
  name: string;
  backgroundImagePath: string;
  // 深色模式背景图片路径（可选，兼容旧版本未提供暗色图）
  backgroundImagePathDark?: string;
  splashBackgroundImagePath?: string;
  splashBackgroundImagePaths?: string[];
  splashRotationRule?: SplashRotationRule;
  splashRotationCursor?: number;
  splashRotationLastDateKey?: string;
  hideSplashLogo?: boolean;
  hideSplashProgress?: boolean;
  blurLevel: number;
  primaryColor: string;
  isDark: boolean;
  createTime: number;
  lastModified: number;
}

interface SplashResolveResult {
  selectedPath: string;
  cursor: number;
  lastDateKey: string;
}

export enum SplashRotationRule {
  EVERY_LAUNCH = 'every_launch',
  DAILY = 'daily',
  FIXED_FIRST = 'fixed_first'
}

/**
 * 全局自定义主题状态键接口
 */
export interface CustomThemeKeys {
  BACKGROUND_IMAGE: string;
  BACKGROUND_IMAGE_LIGHT: string;
  BACKGROUND_IMAGE_DARK: string;
  SPLASH_BACKGROUND_IMAGE: string;
  SPLASH_BACKGROUND_IMAGES: string;
  SPLASH_ROTATION_RULE: string;
  HIDE_SPLASH_LOGO: string;
  HIDE_SPLASH_PROGRESS: string;
  PRIMARY_COLOR: string;
  IS_CUSTOM_THEME_ACTIVE: string;
  CURRENT_THEME_ID: string;
}

/**
 * 全局自定义主题状态键常量
 */
export const CUSTOM_THEME_KEYS: CustomThemeKeys = {
  BACKGROUND_IMAGE: 'custom_theme_background_image',
  BACKGROUND_IMAGE_LIGHT: 'custom_theme_background_image_light',
  BACKGROUND_IMAGE_DARK: 'custom_theme_background_image_dark',
  SPLASH_BACKGROUND_IMAGE: 'custom_theme_splash_background_image',
  SPLASH_BACKGROUND_IMAGES: 'custom_theme_splash_background_images',
  SPLASH_ROTATION_RULE: 'custom_theme_splash_rotation_rule',
  HIDE_SPLASH_LOGO: 'custom_theme_hide_splash_logo',
  HIDE_SPLASH_PROGRESS: 'custom_theme_hide_splash_progress',
  PRIMARY_COLOR: 'custom_theme_primary_color',
  IS_CUSTOM_THEME_ACTIVE: 'custom_theme_is_active',
  CURRENT_THEME_ID: 'custom_theme_current_id'
};

/**
 * 玻璃效果上下文枚举（名义类型）
 * 用于根据不同使用场景返回更合适的默认参数
 */
export enum GlassEffectContext {
  CONTAINER = 'container',
  POPUP = 'popup',
  MENU = 'menu'
}

export enum GlassLevel {
  HERO = 'hero',
  NAVIGATION = 'navigation',
  CARD = 'card',
  SHEET = 'sheet',
  FLOATING = 'floating',
  FEATURED = 'featured'
}

export interface GlassStyleToken {
  level: GlassLevel;
  backgroundColor: string;
  backgroundColorResource: Resource;
  blurStyle: BlurStyle;
  blurOptions: BackgroundBlurStyleOptions;
  backgroundEffect?: BackgroundEffectOptions;
  radius: number;
  shadowColor: string;
  borderColor: string;
  borderWidth: number;
  opacity: number;
  renderGroup: boolean;
}

/**
 * 玻璃效果参数接口（显式类型，避免未类型化对象字面量）
 */
export interface GlassEffectOptions {
  backgroundColorResource: Resource; // 背景颜色必须使用资源，避免硬编码
  blurStyle: BlurStyle;
  radius: number;
  backgroundColor?: string;
  backgroundEffect?: BackgroundEffectOptions;
  borderColor?: string;
  borderWidth?: number;
  blurOptions?: BackgroundBlurStyleOptions;
  opacity?: number;
  renderGroup?: boolean;
  shadowColor: string; // 阴影颜色暂用字符串，与现有shadow调用保持一致
}

/**
 * 主题配置常量
 * 注意：推荐使用 AppColors 系统获取颜色，此配置仅用于兼容旧代码
 * @deprecated 请使用 AppColors 替代
 */
export const THEME_CONFIGS: Record<ThemeType, ThemeConfig> = {
  [ThemeType.LIGHT]: {
    name: 'light',
    displayName: '浅色主题',
    primaryColor: '#007DFF',
    backgroundColor: '#FAFAFA',
    textColor: '#000000',
    cardColor: '#FFFFFF',
    borderColor: '#E0E0E0',
    shadowColor: '#1F000000'
  },
  [ThemeType.DARK]: {
    name: 'dark',
    displayName: '深色主题',
    primaryColor: '#4BA3FF',
    backgroundColor: '#121214',
    textColor: '#FFFFFF',
    cardColor: '#1C1C1E',
    borderColor: '#3A3A3A',
    shadowColor: '#1F000000'
  },
  [ThemeType.AUTO]: {
    name: 'auto',
    displayName: '跟随系统',
    primaryColor: '#007DFF',
    backgroundColor: '#FAFAFA',
    textColor: '#000000',
    cardColor: '#FFFFFF',
    borderColor: '#E0E0E0',
    shadowColor: '#1F000000'
  },
  [ThemeType.PRIVACY]: {
    name: 'privacy',
    displayName: '隐私模式',
    primaryColor: '#8B00FF',
    backgroundColor: '#0A0A0F',
    textColor: '#E0D5FF',
    cardColor: '#1A1A2E',
    borderColor: '#4A3A6A',
    shadowColor: '#33000000'
  }
};

/**
 * 主题变化回调函数类型
 */
export type ThemeChangeCallback = (theme: ThemeType) => void;

/**
 * 主题管理器类
 */
export class ThemeManager {
  private static instance: ThemeManager | null = null;
  private currentTheme: ThemeType = ThemeType.DARK; // 改为DARK
  private actualTheme: ThemeType = ThemeType.DARK; // 实际显示的主题
  private themeChangeCallbacks: Set<ThemeChangeCallback> = new Set();
  private preferencesStore: preferences.Preferences | null = null;
  private readonly THEME_KEY = 'app_theme';
  private readonly CUSTOM_THEME_SPLASH_BACKGROUND_KEY = 'custom_theme_splash_background';
  private readonly CUSTOM_THEME_SPLASH_BACKGROUNDS_KEY = 'custom_theme_splash_backgrounds';
  private readonly CUSTOM_THEME_SPLASH_ROTATION_RULE_KEY = 'custom_theme_splash_rotation_rule';
  private readonly CUSTOM_THEME_SPLASH_ROTATION_CURSOR_KEY = 'custom_theme_splash_rotation_cursor';
  private readonly CUSTOM_THEME_SPLASH_ROTATION_DATE_KEY = 'custom_theme_splash_rotation_date';
  private readonly CUSTOM_THEME_HIDE_SPLASH_LOGO_KEY = 'custom_theme_hide_splash_logo';
  private readonly CUSTOM_THEME_HIDE_SPLASH_PROGRESS_KEY = 'custom_theme_hide_splash_progress';
  private isInitialized: boolean = false; // 添加初始化标志
  // 轻量玻璃模糊在浅色主题下启用
  private glassBlurEnabledInLightMode: boolean = true;
  // 轻量玻璃模糊在深色主题下启用（与浅色保持一致）
  private glassBlurEnabledInDarkMode: boolean = true;

  /**
   * 私有构造函数
   */
  private constructor() {
    // 延迟初始化，避免在GlobalContext未初始化时访问
    // 初始化将在第一次使用时进行
  }

  /**
   * 获取单例实例
   */
  public static getInstance(): ThemeManager {
    if (!ThemeManager.instance) {
      ThemeManager.instance = new ThemeManager();
    }
    return ThemeManager.instance;
  }

  public isReady(): boolean {
    return this.isInitialized;
  }

  /**
   * 公开的初始化方法
   * 由SplashPage在适当时机调用，确保主题在UI渲染前完全初始化
   */
  public async initialize(): Promise<void> {
    if (this.isInitialized) {
      logger.debug(TAG, 'ThemeManager已初始化，跳过重复初始化');
      return;
    }

    try {
      logger.info(TAG, '🎨 开始ThemeManager初始化');
      
      // 1. 首先检测系统主题
      this.detectSystemTheme();
      logger.info(TAG, `📱 系统主题检测完成: ${this.actualTheme}`);
      
      // 2. 初始化首选项存储
      await this.initializePreferences();
      
      // 3. 加载保存的主题设置
      await this.loadTheme();
      logger.info(TAG, `💾 用户主题设置: ${this.currentTheme}`);
      
      // 3.5. 加载自定义主题状态
      await this.loadCustomThemeState();
      
      // 3.6. 初始化用户主题配置管理器
      await this.initializeUserThemeConfig();

      // 3.7. 如果自定义主题处于激活状态，则强制使用AUTO以跟随系统
      // 避免用户之前保存的固定深色/浅色导致与系统不一致
      const customActive: boolean = this.isCustomThemeActive();
      if (customActive && this.currentTheme !== ThemeType.AUTO) {
        this.currentTheme = ThemeType.AUTO;
        await this.saveTheme(ThemeType.AUTO);
        logger.info(TAG, '自定义主题已激活，已切换到AUTO以跟随系统主题');
      }
      
      // 4. 确定最终显示的主题
      const finalTheme = this.getActualThemeSync();
      logger.info(TAG, `🎯 最终显示主题: ${finalTheme}`);
      
      // 5. 主动通知所有监听器当前主题（无论是AUTO还是固定主题）
      // 这确保所有组件都能获得初始主题，避免组件使用默认值
      this.notifyThemeChange(finalTheme);
      logger.info(TAG, `📢 已向 ${this.themeChangeCallbacks.size} 个监听器通知初始主题: ${finalTheme}`);
      
      this.isInitialized = true;
      logger.info(TAG, '✅ ThemeManager初始化完成');
    } catch (error) {
      logger.error(TAG, 'ThemeManager初始化失败', error);
      // 即使初始化失败，也设置为已初始化，避免重复尝试
      this.isInitialized = true;
      // 使用默认主题
      this.currentTheme = ThemeType.AUTO;
      this.notifyThemeChange(this.actualTheme);
    }
  }

  /**
   * 延迟初始化方法（内部使用）
   * 在第一次使用时才进行初始化，确保GlobalContext已经准备好
   */
  private async ensureInitialized(): Promise<void> {
    if (this.isInitialized) {
      return;
    }
    
    // 如果还没有初始化，调用公开的初始化方法
    await this.initialize();
  }

  /**
   * 初始化首选项存储
   */
  private async initializePreferences(): Promise<void> {
    try {
      const context = getContext();
      this.preferencesStore = await preferences.getPreferences(context, 'theme_preferences');
      logger.info(TAG, '主题首选项存储初始化成功');
    } catch (error) {
      logger.error(TAG, '主题首选项存储初始化失败', error);
      this.currentTheme = ThemeType.AUTO;
    }
  }

  /**
   * 加载保存的主题
   */
  private async loadTheme(): Promise<void> {
    try {
      if (!this.preferencesStore) {
        await this.initializePreferences();
      }

      if (this.preferencesStore) {
        const savedTheme = await this.preferencesStore.get(this.THEME_KEY, ThemeType.AUTO);
        this.currentTheme = savedTheme as ThemeType;
        if (this.currentTheme === ThemeType.PRIVACY) {
          this.currentTheme = ThemeType.AUTO;
          await this.saveTheme(ThemeType.AUTO);
          logger.warn(TAG, '检测到持久化的隐私主题，已重置为AUTO以恢复系统主题跟随');
        }
        
        // 临时重置：如果保存的是特定主题，重置为AUTO以跟随系统
        // if (this.currentTheme !== ThemeType.AUTO) {
        //   logger.info(TAG, `重置主题从 ${this.currentTheme} 到 AUTO 以跟随系统主题`);
        //   this.currentTheme = ThemeType.AUTO;
        //   await this.saveTheme(ThemeType.AUTO);
        // }
        
        logger.info(TAG, `加载保存的主题: ${this.currentTheme}`);
      }
    } catch (error) {
      logger.error(TAG, '加载主题失败，使用默认主题', error);
      this.currentTheme = ThemeType.AUTO;
    }
  }

  /**
   * 检测系统主题
   */
  private detectSystemTheme(): void {
    try {
      const context = getContext();
      if (!context) {
        logger.warn(TAG, '无法获取上下文，使用默认深色主题');
        this.actualTheme = ThemeType.DARK;
        return;
      }

      if (!context.config) {
        logger.warn(TAG, '无法获取系统配置，使用默认深色主题');
        this.actualTheme = ThemeType.DARK;
        return;
      }

      const colorMode = context.config.colorMode;
      logger.debug(TAG, `系统颜色模式原始值: ${colorMode}`);

      // ColorMode: -1=未设置, 0=深色, 1=浅色
      switch (colorMode) {
        case -1: // COLOR_MODE_NOT_SET
          // 未设置时，默认使用深色主题
          this.actualTheme = ThemeType.DARK;
          logger.info(TAG, '系统主题未设置，默认使用深色主题');
          break;
        case 0: // COLOR_MODE_DARK
          this.actualTheme = ThemeType.DARK;
          logger.info(TAG, '检测到系统深色主题');
          break;
        case 1: // COLOR_MODE_LIGHT
          this.actualTheme = ThemeType.LIGHT;
          logger.info(TAG, '检测到系统浅色主题');
          break;
        default:
          // 未知值，使用深色作为默认值
          this.actualTheme = ThemeType.DARK;
          logger.warn(TAG, `未知的colorMode值: ${colorMode}，使用深色主题`);
          break;
      }

      logger.info(TAG, `系统主题检测完成: colorMode=${colorMode}, actualTheme=${this.actualTheme}`);
    } catch (error) {
      logger.error(TAG, '检测系统主题失败，使用默认深色主题', error);
      this.actualTheme = ThemeType.DARK;
    }
  }

  /**
   * 保存主题到首选项
   */
  private async saveTheme(theme: ThemeType): Promise<void> {
    try {
      if (!this.preferencesStore) {
        await this.initializePreferences();
      }

      if (this.preferencesStore) {
        await this.preferencesStore.put(this.THEME_KEY, theme);
        await this.preferencesStore.flush();
        logger.info(TAG, `主题已保存: ${theme}`);
      }
    } catch (error) {
      logger.error(TAG, '保存主题失败', error);
    }
  }

  /**
   * 获取当前主题（异步，确保完全初始化）
   */
  public async getCurrentTheme(): Promise<ThemeType> {
    await this.ensureInitialized();
    return this.currentTheme;
  }

  /**
   * 获取当前主题（同步，用于UI组件快速访问）
   * 注意：如果ThemeManager未初始化，返回默认值
   */
  public getCurrentThemeSync(): ThemeType {
    return this.currentTheme;
  }

  /**
   * 获取实际显示的主题（考虑AUTO模式）（异步）
   */
  public async getActualTheme(): Promise<ThemeType> {
    await this.ensureInitialized();
    if (this.currentTheme === ThemeType.AUTO) {
      return this.actualTheme;
    }
    return this.currentTheme;
  }

  /**
   * 获取实际显示的主题（同步，用于UI组件快速访问）
   */
  public getActualThemeSync(): ThemeType {
    if (this.currentTheme === ThemeType.AUTO) {
      return this.actualTheme;
    }
    return this.currentTheme;
  }

  /**
   * 更新系统主题（由系统配置变化调用）
   */
  public updateSystemTheme(colorMode: number): void {
    const newActualTheme = colorMode === 0 ? ThemeType.DARK : ThemeType.LIGHT;
    
    if (this.actualTheme !== newActualTheme) {
      this.actualTheme = newActualTheme;
      logger.info(TAG, `系统主题更新: colorMode=${colorMode}, actualTheme=${this.actualTheme}`);
      
      // 如果当前是AUTO模式，通知主题变化
      if (this.currentTheme === ThemeType.AUTO) {
        this.notifyThemeChange(this.actualTheme);
      }
    }
  }

  /**
   * 设置主题
   */
  public async setTheme(theme: ThemeType): Promise<void> {
    await this.ensureInitialized();
    
    if (this.currentTheme === theme) {
      logger.debug(TAG, `主题已经是 ${theme}，无需切换`);
      return;
    }

    try {
      const oldTheme = this.currentTheme;
      const oldActualTheme = this.getActualThemeSync();
      
      logger.info(TAG, `开始主题切换: ${oldTheme} -> ${theme} (当前实际显示: ${oldActualTheme})`);
      
      // 更新主题设置
      this.currentTheme = theme;

      // 保存主题
      await this.saveTheme(theme);
      logger.debug(TAG, `主题已保存到存储: ${theme}`);

      // 确定要通知的主题
      let themeToNotify: ThemeType;
      if (theme === ThemeType.AUTO) {
        // AUTO模式下，通知实际的系统主题
        themeToNotify = this.actualTheme;
        logger.info(TAG, `切换到AUTO模式，应用系统主题: ${themeToNotify}`);
      } else {
        // 非AUTO模式下，直接通知设置的主题
        themeToNotify = theme;
        logger.info(TAG, `切换到固定主题: ${themeToNotify}`);
      }

      // 通知所有监听器
      this.notifyThemeChange(themeToNotify);
      logger.info(TAG, `✅ 主题切换完成: ${oldTheme} -> ${theme}, 实际显示: ${themeToNotify}, 通知了 ${this.themeChangeCallbacks.size} 个监听器`);
      
    } catch (error) {
      const errorMessage = error instanceof Error ? error.message : String(error);
      logger.error(TAG, `主题切换失败: ${theme}`, error);
      // 切换失败时，尝试恢复到之前的主题（不改变currentTheme，保持原状）
      throw new Error(`主题切换失败: ${errorMessage}`);
    }
  }

  /**
   * 切换主题（强制切换当前实际显示的主题）
   * 如果当前实际显示浅色 -> 切换到深色
   * 如果当前实际显示深色 -> 切换到浅色
   * 注意：这会覆盖AUTO模式，强制使用固定主题
   */
  public async toggleTheme(): Promise<void> {
    // 获取当前实际显示的主题（考虑AUTO模式）
    const actualTheme = this.getActualThemeSync();
    let newTheme: ThemeType;
    
    // 基于实际显示的主题进行切换
    if (actualTheme === ThemeType.LIGHT) {
      newTheme = ThemeType.DARK;
    } else {
      newTheme = ThemeType.LIGHT;
    }
    
    logger.info(TAG, `主题切换: 实际显示=${actualTheme}, 配置=${this.currentTheme} -> 新主题=${newTheme}`);
    await this.setTheme(newTheme);
  }

  /**
   * 获取主题配置（异步）
   */
  public async getThemeConfig(theme?: ThemeType): Promise<ThemeConfig> {
    const targetTheme = theme || await this.getActualTheme();
    return THEME_CONFIGS[targetTheme];
  }

  /**
   * 获取主题配置（同步）
   */
  public getThemeConfigSync(theme?: ThemeType): ThemeConfig {
    const targetTheme = theme || this.getActualThemeSync();
    return THEME_CONFIGS[targetTheme];
  }

  /**
   * 获取当前主题配置（异步）
   */
  public async getCurrentThemeConfig(): Promise<ThemeConfig> {
    return await this.getThemeConfig();
  }

  /**
   * 获取当前主题配置（同步）
   */
  public getCurrentThemeConfigSync(): ThemeConfig {
    return this.getThemeConfigSync();
  }

  private clampNumber(value: number, min: number, max: number): number {
    if (value < min) {
      return min;
    }
    if (value > max) {
      return max;
    }
    return value;
  }

  private isDarkLikeTheme(theme: ThemeType): boolean {
    return theme === ThemeType.DARK || theme === ThemeType.PRIVACY;
  }

  private getGlassTransparencyForLevel(level: GlassLevel): number {
    switch (level) {
      case GlassLevel.NAVIGATION:
        return this.getComponentTransparency('navigationBar');
      case GlassLevel.CARD:
        return this.getComponentTransparency('card');
      case GlassLevel.SHEET:
        return (this.getComponentTransparency('dialog') + this.getComponentTransparency('menu')) / 2;
      case GlassLevel.FLOATING:
        return this.getComponentTransparency('floatingBall');
      case GlassLevel.FEATURED:
        return this.getComponentTransparency('card');
      case GlassLevel.HERO:
      default:
        return this.getComponentTransparency('card');
    }
  }

  private getBaseGlassAlpha(level: GlassLevel): number {
    const isDark: boolean = this.isDarkLikeTheme(this.getActualThemeSync());
    switch (level) {
      case GlassLevel.HERO:
        return isDark ? 0.82 : 0.68;
      case GlassLevel.NAVIGATION:
        return isDark ? 0.76 : 0.58;
      case GlassLevel.CARD:
        return isDark ? 0.72 : 0.54;
      case GlassLevel.SHEET:
        return isDark ? 0.9 : 0.8;
      case GlassLevel.FEATURED:
        return isDark ? 0.12 : 0.10;
      case GlassLevel.FLOATING:
      default:
        return isDark ? 0.84 : 0.68;
    }
  }

  private getGlassBackgroundColorForLevel(level: GlassLevel): string {
    const theme: ThemeType = this.getActualThemeSync();
    const alpha: number = this.clampNumber(
      this.getBaseGlassAlpha(level) * (0.45 + this.getGlassTransparencyForLevel(level) * 0.55),
      level === GlassLevel.FEATURED ? 0.04 : 0.18,
      level === GlassLevel.FEATURED ? 0.24 : 0.96
    );

    if (this.isDarkLikeTheme(theme)) {
      switch (level) {
        case GlassLevel.HERO:
          return `rgba(10, 16, 26, ${alpha})`;
        case GlassLevel.NAVIGATION:
          return `rgba(16, 22, 34, ${alpha})`;
        case GlassLevel.SHEET:
          return `rgba(18, 24, 36, ${alpha})`;
        case GlassLevel.FLOATING:
          return `rgba(20, 28, 40, ${alpha})`;
        case GlassLevel.FEATURED:
          return `rgba(10, 18, 30, ${alpha})`;
        case GlassLevel.CARD:
        default:
          return `rgba(18, 24, 36, ${alpha})`;
      }
    }

    switch (level) {
      case GlassLevel.HERO:
        return `rgba(255, 255, 255, ${alpha})`;
      case GlassLevel.NAVIGATION:
        return `rgba(248, 251, 255, ${alpha})`;
      case GlassLevel.SHEET:
        return `rgba(255, 255, 255, ${this.clampNumber(alpha + 0.08, 0.24, 0.98)})`;
      case GlassLevel.FLOATING:
        return `rgba(252, 253, 255, ${alpha})`;
      case GlassLevel.FEATURED:
        return `rgba(210, 228, 255, ${alpha})`;
      case GlassLevel.CARD:
      default:
        return `rgba(255, 255, 255, ${alpha})`;
    }
  }

  private getGlassBorderColorForLevel(level: GlassLevel): string {
    const isDark: boolean = this.isDarkLikeTheme(this.getActualThemeSync());
    switch (level) {
      case GlassLevel.HERO:
        return isDark ? 'rgba(255, 255, 255, 0.12)' : 'rgba(255, 255, 255, 0.52)';
      case GlassLevel.NAVIGATION:
        return isDark ? 'rgba(255, 255, 255, 0.10)' : 'rgba(255, 255, 255, 0.62)';
      case GlassLevel.SHEET:
        return isDark ? 'rgba(255, 255, 255, 0.16)' : 'rgba(255, 255, 255, 0.74)';
      case GlassLevel.FLOATING:
        return isDark ? 'rgba(255, 255, 255, 0.14)' : 'rgba(255, 255, 255, 0.68)';
      case GlassLevel.FEATURED:
        return isDark ? 'rgba(226, 240, 255, 0.16)' : 'rgba(255, 255, 255, 0.54)';
      case GlassLevel.CARD:
      default:
        return isDark ? 'rgba(255, 255, 255, 0.09)' : 'rgba(255, 255, 255, 0.58)';
    }
  }

  private getGlassShadowColorForLevel(level: GlassLevel): string {
    if (!this.isShadowEffectEnabled()) {
      return 'rgba(0, 0, 0, 0)';
    }

    const isDark: boolean = this.isDarkLikeTheme(this.getActualThemeSync());
    const intensity: number = this.clampNumber(this.getUserThemeProfile().effects.shadowIntensity / 100, 0, 1);
    let levelFactor: number = 0.7;

    switch (level) {
      case GlassLevel.HERO:
        levelFactor = 1.0;
        break;
      case GlassLevel.NAVIGATION:
        levelFactor = 0.45;
        break;
      case GlassLevel.SHEET:
        levelFactor = 0.9;
        break;
      case GlassLevel.FLOATING:
        levelFactor = 0.82;
        break;
      case GlassLevel.FEATURED:
        levelFactor = 0.68;
        break;
      case GlassLevel.CARD:
      default:
        levelFactor = 0.7;
        break;
    }

    const baseAlpha: number = isDark ? 0.28 : 0.12;
    const alpha: number = this.clampNumber(baseAlpha * (0.4 + intensity * 0.9) * levelFactor, 0.0, 0.36);
    return `rgba(0, 0, 0, ${alpha})`;
  }

  private getGlassBlurStyleForLevel(level: GlassLevel): BlurStyle {
    if (!this.isBlurEffectEnabled() || !this.getUserThemeProfile().effects.enableGlassmorphism) {
      return BlurStyle.NONE;
    }

    switch (level) {
      case GlassLevel.HERO:
      case GlassLevel.SHEET:
        return BlurStyle.Thick;
      case GlassLevel.NAVIGATION:
      case GlassLevel.FLOATING:
        return BlurStyle.Regular;
      case GlassLevel.FEATURED:
        return BlurStyle.BACKGROUND_ULTRA_THICK;
      case GlassLevel.CARD:
      default:
        return BlurStyle.Thin;
    }
  }

  private getGlassBlurOptionsForLevel(level: GlassLevel): BackgroundBlurStyleOptions {
    const blurEnabled: boolean = this.isBlurEffectEnabled() && this.getUserThemeProfile().effects.enableGlassmorphism;
    const intensity: number = blurEnabled ? this.clampNumber(this.getUserThemeProfile().effects.blurIntensity / 100, 0, 1) : 0;
    const isDark: boolean = this.isDarkLikeTheme(this.getActualThemeSync());

    if (level === GlassLevel.FEATURED) {
      return {
        colorMode: ThemeColorMode.SYSTEM,
        adaptiveColor: AdaptiveColor.DEFAULT,
        scale: blurEnabled ? this.clampNumber((isDark ? 1.10 : 1.04) + intensity * 0.22, 0.78, 1.32) : 0.0,
        policy: BlurStyleActivePolicy.ALWAYS_ACTIVE
      };
    }

    let levelMultiplier: number = 0.82;

    switch (level) {
      case GlassLevel.HERO:
        levelMultiplier = 1.08;
        break;
      case GlassLevel.NAVIGATION:
        levelMultiplier = 0.92;
        break;
      case GlassLevel.SHEET:
        levelMultiplier = 1.0;
        break;
      case GlassLevel.FLOATING:
        levelMultiplier = 0.88;
        break;
      case GlassLevel.CARD:
      default:
        levelMultiplier = 0.82;
        break;
    }

    return {
      colorMode: ThemeColorMode.SYSTEM,
      adaptiveColor: AdaptiveColor.DEFAULT,
      scale: blurEnabled ? this.clampNumber((0.45 + intensity * 0.65) * levelMultiplier, 0.35, 1.15) : 0.0,
      policy: BlurStyleActivePolicy.ALWAYS_ACTIVE
    };
  }

  private getGlassBackgroundEffectForLevel(level: GlassLevel): BackgroundEffectOptions | undefined {
    const blurEnabled: boolean = this.isBlurEffectEnabled() && this.getUserThemeProfile().effects.enableGlassmorphism;
    if (!blurEnabled) {
      return undefined;
    }

    const isDark: boolean = this.isDarkLikeTheme(this.getActualThemeSync());
    switch (level) {
      case GlassLevel.FEATURED:
        return {
          radius: isDark ? 36 : 34,
          saturation: isDark ? 1.36 : 1.44,
          brightness: isDark ? 1.04 : 1.12,
          color: isDark ? 'rgba(132, 188, 255, 0.022)' : 'rgba(126, 182, 255, 0.020)',
          adaptiveColor: AdaptiveColor.DEFAULT
        };
      case GlassLevel.HERO:
      case GlassLevel.NAVIGATION:
      case GlassLevel.CARD:
      case GlassLevel.SHEET:
      case GlassLevel.FLOATING:
      default:
        return undefined;
    }
  }

  private getGlassRadiusForLevel(level: GlassLevel): number {
    const baseRadius: number = Math.max(8, this.getUserCornerRadius());
    switch (level) {
      case GlassLevel.HERO:
        return baseRadius + 10;
      case GlassLevel.NAVIGATION:
        return baseRadius + 6;
      case GlassLevel.SHEET:
        return baseRadius + 8;
      case GlassLevel.FLOATING:
        return baseRadius + 4;
      case GlassLevel.FEATURED:
        return baseRadius + 6;
      case GlassLevel.CARD:
      default:
        return baseRadius + 2;
    }
  }

  /**
   * 获取浅色主题下玻璃背景颜色（带透明度），统一全局风格
   */
  public getLightModeGlassBackgroundColor(): string {
    return this.getGlassBackgroundColorForLevel(GlassLevel.CARD);
  }

  /**
   * 获取浅色主题下的模糊样式
   */
  public getLightModeBlurStyle(): BlurStyle {
    return this.getGlassBlurStyleForLevel(GlassLevel.CARD);
  }

  /**
   * 获取深色主题下的模糊样式（与浅色保持一致）
   */
  public getDarkModeBlurStyle(): BlurStyle {
    return this.getGlassBlurStyleForLevel(GlassLevel.CARD);
  }

  /**
   * 获取浅色玻璃投影颜色
   */
  public getLightModeGlassShadowColor(): string {
    return this.getGlassShadowColorForLevel(GlassLevel.CARD);
  }

  /**
   * 获取深色主题下玻璃投影颜色（与浅色保持一致）
   */
  public getDarkModeGlassShadowColor(): string {
    return this.getGlassShadowColorForLevel(GlassLevel.CARD);
  }

  /**
   * 获取浅色玻璃圆角半径（与页面默认R角统一）
   */
  public getLightModeGlassRadius(): number {
    return this.getGlassRadiusForLevel(GlassLevel.CARD);
  }

  /**
   * 获取深色玻璃圆角半径（与浅色保持一致）
   */
  public getDarkModeGlassRadius(): number {
    return this.getGlassRadiusForLevel(GlassLevel.CARD);
  }

  private mapGlassContextToLevel(context: GlassEffectContext): GlassLevel {
    switch (context) {
      case GlassEffectContext.POPUP:
        return GlassLevel.SHEET;
      case GlassEffectContext.MENU:
        return GlassLevel.FLOATING;
      case GlassEffectContext.CONTAINER:
      default:
        return GlassLevel.CARD;
    }
  }

  public getGlassToken(level: GlassLevel = GlassLevel.CARD): GlassStyleToken {
    return {
      level: level,
      backgroundColor: this.getGlassBackgroundColorForLevel(level),
      backgroundColorResource: this.getGlassBackgroundResource(),
      blurStyle: this.getGlassBlurStyleForLevel(level),
      blurOptions: this.getGlassBlurOptionsForLevel(level),
      backgroundEffect: this.getGlassBackgroundEffectForLevel(level),
      radius: this.getGlassRadiusForLevel(level),
      shadowColor: this.getGlassShadowColorForLevel(level),
      borderColor: this.getGlassBorderColorForLevel(level),
      borderWidth: 1,
      opacity: this.getGlassTransparencyForLevel(level),
      renderGroup: level === GlassLevel.HERO || level === GlassLevel.SHEET || level === GlassLevel.FLOATING || level === GlassLevel.FEATURED
    };
  }

  public createGlassModifierForLevel(level: GlassLevel = GlassLevel.CARD): CommonModifier {
    const token: GlassStyleToken = this.getGlassToken(level);
    const modifier: CommonModifier = new CommonModifier();
    modifier
      .backgroundColor(token.backgroundColor)
      .backgroundBlurStyle(token.blurStyle, token.blurOptions)
      .border({
        width: token.borderWidth,
        color: token.borderColor
      })
      .borderRadius(token.radius)
      .shadow({
        radius: token.radius,
        color: token.shadowColor
      });
    return modifier;
  }

  /**
   * 创建浅色主题玻璃模糊修饰符（不含边距与内边距，便于组件自行控制布局）
   */
  public createLightModeGlassModifier(): CommonModifier {
    return this.createGlassModifierForLevel(GlassLevel.CARD);
  }

  /**
   * 获取通用玻璃背景颜色（不区分主题），与历史实现保持一致
   */
  public getGlassBackgroundColor(): string {
    return this.getGlassToken(GlassLevel.CARD).backgroundColor;
  }

  /**
   * 获取通用玻璃模糊样式（不区分主题）
   */
  public getGlassBlurStyle(): BlurStyle {
    return this.getGlassToken(GlassLevel.CARD).blurStyle;
  }

  /**
   * 获取通用玻璃阴影颜色（不区分主题）
   */
  public getGlassShadowColor(): string {
    return this.getGlassToken(GlassLevel.CARD).shadowColor;
  }

  /**
   * 获取通用玻璃圆角半径（不区分主题）
   */
  public getGlassRadius(): number {
    return this.getGlassToken(GlassLevel.CARD).radius;
  }

  /**
   * 创建通用玻璃模糊修饰符（不含边距与内边距），适用于任意主题
   */
  public createGlassModifier(): CommonModifier {
    return this.createGlassModifierForLevel(GlassLevel.CARD);
  }

  /**
   * 返回通用玻璃背景颜色的资源对象（资源化，统一管理）
   * 优先使用资源映射中的 app.color.glass_background_overlay，其次回退到 app.color.background_overlay
   */
  public getGlassBackgroundResource(): Resource {
    const glassRes: Resource | undefined = colorMap['app.color.glass_background_overlay'];
    if (glassRes !== undefined) {
      return glassRes;
    }
    const overlayRes: Resource | undefined = colorMap['app.color.background_overlay'];
    if (overlayRes !== undefined) {
      return overlayRes;
    }
    // 若资源不存在，记录日志并回退到透明以避免硬编码颜色
    logger.warn(TAG, '缺少 app.color.glass_background_overlay 与 app.color.background_overlay 资源，回退为透明背景');
    return $r('app.color.transparent');
  }

  /**
   * 根据上下文返回默认的玻璃效果参数配置
   */
  public getGlassEffectOptions(context: GlassEffectContext = GlassEffectContext.CONTAINER): GlassEffectOptions {
    const token: GlassStyleToken = this.getGlassToken(this.mapGlassContextToLevel(context));
    return {
      backgroundColorResource: token.backgroundColorResource,
      backgroundColor: token.backgroundColor,
      blurStyle: token.blurStyle,
      blurOptions: token.blurOptions,
      backgroundEffect: token.backgroundEffect,
      radius: token.radius,
      shadowColor: token.shadowColor,
      borderColor: token.borderColor,
      borderWidth: token.borderWidth,
      opacity: token.opacity,
      renderGroup: token.renderGroup
    };
  }

  /**
   * 使用给定的玻璃效果参数创建修饰符（不含边距/内边距）
   */
  public createGlassModifierWithOptions(options: GlassEffectOptions): CommonModifier {
    const modifier: CommonModifier = new CommonModifier();
    modifier
      .backgroundColor(options.backgroundColor ?? options.backgroundColorResource)
      .backgroundBlurStyle(options.blurStyle, options.blurOptions)
      .border({
        width: options.borderWidth ?? 1,
        color: options.borderColor ?? 'rgba(255, 255, 255, 0)'
      })
      .borderRadius(options.radius)
      .shadow({ radius: options.radius, color: options.shadowColor });
    return modifier;
  }

  /**
   * 便捷方法：获取弹窗/对话框建议的玻璃效果参数
   */
  public getPopupBlurOptions(): GlassEffectOptions {
    return this.getGlassEffectOptions(GlassEffectContext.POPUP);
  }

  /**
   * 注册主题变化监听器
   * 注册后会立即通知当前主题（如果已初始化）
   */
  public onThemeChange(callback: ThemeChangeCallback): void {
    this.themeChangeCallbacks.add(callback);
    logger.debug(TAG, `注册主题变化监听器，当前监听器数量: ${this.themeChangeCallbacks.size}`);
    
    // 如果ThemeManager已经初始化，立即通知新监听器当前主题
    // 这确保后注册的监听器也能获得正确的初始主题
    if (this.isInitialized) {
      const currentTheme = this.getActualThemeSync();
      try {
        callback(currentTheme);
        logger.debug(TAG, `已向新监听器通知当前主题: ${currentTheme}`);
      } catch (error) {
        logger.error(TAG, '通知新监听器当前主题失败', String(error));
      }
    }
  }

  /**
   * 移除主题变化监听器
   */
  public offThemeChange(callback: ThemeChangeCallback): void {
    this.themeChangeCallbacks.delete(callback);
    logger.debug(TAG, `移除主题变化监听器，当前监听器数量: ${this.themeChangeCallbacks.size}`);
  }

  /**
   * 通知所有监听器主题变化
   */
  private notifyThemeChange(theme: ThemeType): void {
    this.themeChangeCallbacks.forEach(callback => {
      try {
        callback(theme);
      } catch (error) {
        logger.error(TAG, '主题变化回调执行失败', String(error));
      }
    });
    // 自定义主题的背景响应系统深/浅变化
    this.refreshCustomBackgroundForCurrentTheme();
  }

  /**
   * 判断是否为深色主题（异步）
   */
  public async isDarkTheme(): Promise<boolean> {
    return await this.getActualTheme() === ThemeType.DARK;
  }

  /**
   * 判断是否为深色主题（同步）
   */
  public isDarkThemeSync(): boolean {
    return this.getActualThemeSync() === ThemeType.DARK;
  }

  /**
   * 判断是否为浅色主题（异步）
   */
  public async isLightTheme(): Promise<boolean> {
    return await this.getActualTheme() === ThemeType.LIGHT;
  }

  /**
   * 判断是否为浅色主题（同步）
   */
  public isLightThemeSync(): boolean {
    return this.getActualThemeSync() === ThemeType.LIGHT;
  }

  /**
   * 获取所有可用主题
   */
  public getAvailableThemes(): ThemeType[] {
    return Object.values(ThemeType);
  }

  /**
   * 获取主题显示名称
   */
  public getThemeDisplayName(theme?: ThemeType): string {
    const targetTheme = theme || this.currentTheme;
    return THEME_CONFIGS[targetTheme].displayName;
  }

  /**
   * 重置为默认主题
   */
  public async resetToDefault(): Promise<void> {
    await this.setTheme(ThemeType.AUTO);
  }

  // ==================== AppColors 便捷访问方法 ====================
  // 推荐直接使用 AppColors 类，以下方法仅为便捷访问

  /**
   * 获取主色
   */
  public getPrimaryColor(): string {
    return AppColors.primary;
  }

  /**
   * 获取背景色
   */
  public getBackgroundColor(): string {
    return AppColors.background;
  }

  /**
   * 获取表面色
   */
  public getSurfaceColor(): string {
    return AppColors.surface;
  }

  /**
   * 获取主要文字颜色
   */
  public getTextPrimaryColor(): string {
    return AppColors.textPrimary;
  }

  /**
   * 获取次要文字颜色
   */
  public getTextSecondaryColor(): string {
    return AppColors.textSecondary;
  }

  /**
   * 获取边框颜色
   */
  public getOutlineColor(): string {
    return AppColors.outline;
  }

  /**
   * 获取分割线颜色
   */
  public getDividerColor(): string {
    return AppColors.divider;
  }

  /**
   * 获取指定颜色角色的颜色
   */
  public getColorByRole(role: ColorRole): string {
    return AppColors.getColor(role);
  }
  
  // ==================== 用户主题配置管理 ====================
  
  /**
   * 初始化用户主题配置管理器
   */
  private async initializeUserThemeConfig(): Promise<void> {
    try {
      const userConfigManager = UserThemeConfigManager.getInstance();
      await userConfigManager.initialize();
      logger.info(TAG, '用户主题配置管理器初始化完成');
    } catch (error) {
      logger.error(TAG, '用户主题配置管理器初始化失败', error);
    }
  }
  
  /**
   * 获取用户主题配置管理器
   */
  public getUserThemeConfigManager(): UserThemeConfigManager {
    return UserThemeConfigManager.getInstance();
  }
  
  /**
   * 获取当前用户主题配置
   */
  public getUserThemeProfile(): UserThemeProfile {
    return UserThemeConfigManager.getInstance().getCurrentProfile();
  }
  
  /**
   * 检查是否启用模糊效果
   */
  public isBlurEffectEnabled(): boolean {
    try {
      return UserThemeConfigManager.getInstance().blurEnabled;
    } catch {
      return true;
    }
  }
  
  /**
   * 检查是否启用阴影效果
   */
  public isShadowEffectEnabled(): boolean {
    try {
      return UserThemeConfigManager.getInstance().shadowEnabled;
    } catch {
      return true;
    }
  }
  
  /**
   * 检查是否启用动画效果
   */
  public isAnimationEnabled(): boolean {
    try {
      return UserThemeConfigManager.getInstance().animationEnabled;
    } catch {
      return true;
    }
  }
  
  /**
   * 获取动画速度倍率
   */
  public getAnimationSpeed(): number {
    try {
      return UserThemeConfigManager.getInstance().animationSpeed;
    } catch {
      return 1.0;
    }
  }
  
  /**
   * 获取用户配置的组件圆角大小
   */
  public getUserCornerRadius(): number {
    try {
      return UserThemeConfigManager.getInstance().componentCornerRadius;
    } catch {
      return 12;
    }
  }

  /**
   * 获取用户配置的封面图片圆角大小
   */
  public getUserCoverCornerRadius(): number {
    try {
      return UserThemeConfigManager.getInstance().coverCornerRadius;
    } catch {
      return 12;
    }
  }
  
  /**
   * 获取组件透明度
   */
  public getComponentTransparency(component: 'navigationBar' | 'tabBar' | 'card' | 'dialog' | 'floatingBall' | 'menu' | 'sidebar'): number {
    try {
      const profile = UserThemeConfigManager.getInstance().getCurrentProfile();
      if (component === 'navigationBar') return profile.transparency.navigationBar;
      if (component === 'tabBar') return profile.transparency.tabBar;
      if (component === 'card') return profile.transparency.card;
      if (component === 'dialog') return profile.transparency.dialog;
      if (component === 'floatingBall') return profile.transparency.floatingBall;
      if (component === 'menu') return profile.transparency.menu;
      if (component === 'sidebar') return profile.transparency.sidebar;
      return 1.0;
    } catch {
      return 1.0;
    }
  }

  /**
   * 获取主题系统的诊断信息
   */
  public getDiagnostics(): string {
    return `ThemeManager 诊断信息:
- 初始化状态: ${this.isInitialized}
- 当前主题设置: ${this.currentTheme}
- 实际系统主题: ${this.actualTheme}
- 最终显示主题: ${this.getActualThemeSync()}
- 注册的监听器数量: ${this.themeChangeCallbacks.size}
- 存储状态: ${this.preferencesStore ? '已初始化' : '未初始化'}`;
  }

  /**
   * 强制刷新主题
   */
  public async refreshTheme(): Promise<void> {
    logger.info(TAG, '开始强制刷新主题');
    
    // 重新检测系统主题
    this.detectSystemTheme();
    
    // 重新加载保存的主题
    await this.loadTheme();

    // 当自定义主题激活时，确保跟随系统
    const customActive: boolean = this.isCustomThemeActive();
    if (customActive && this.currentTheme !== ThemeType.AUTO) {
      this.currentTheme = ThemeType.AUTO;
      await this.saveTheme(ThemeType.AUTO);
      logger.info(TAG, '自定义主题激活，刷新时强制AUTO以跟随系统');
    }
    
    // 通知当前主题
    const currentTheme = this.getActualThemeSync();
    this.notifyThemeChange(currentTheme);
    
    logger.info(TAG, `主题刷新完成: ${currentTheme}`);
    logger.debug(TAG, this.getDiagnostics());
  }

  private normalizeSplashBackgroundPaths(themeData: CustomThemeData): string[] {
    const normalized: string[] = [];
    if (themeData.splashBackgroundImagePaths && themeData.splashBackgroundImagePaths.length > 0) {
      let idx: number = 0;
      while (idx < themeData.splashBackgroundImagePaths.length) {
        const candidate: string = themeData.splashBackgroundImagePaths[idx];
        if (candidate && candidate.length > 0 && !normalized.includes(candidate)) {
          normalized.push(candidate);
        }
        idx = idx + 1;
      }
    }
    if (
      normalized.length === 0 &&
      themeData.splashBackgroundImagePath &&
      themeData.splashBackgroundImagePath.length > 0
    ) {
      normalized.push(themeData.splashBackgroundImagePath);
    }
    return normalized;
  }

  private sanitizeSplashRotationRule(rawRule: SplashRotationRule | string | undefined): SplashRotationRule {
    if (rawRule === SplashRotationRule.DAILY) {
      return SplashRotationRule.DAILY;
    }
    if (rawRule === SplashRotationRule.FIXED_FIRST) {
      return SplashRotationRule.FIXED_FIRST;
    }
    return SplashRotationRule.EVERY_LAUNCH;
  }

  private encodeSplashBackgrounds(paths: string[]): string {
    if (paths.length === 0) {
      return '';
    }
    return paths.join('\n');
  }

  private decodeSplashBackgrounds(raw: string): string[] {
    if (!raw || raw.length === 0) {
      return [];
    }
    const normalized: string[] = [];
    const parts: string[] = raw.split('\n');
    let idx: number = 0;
    while (idx < parts.length) {
      const candidate: string = parts[idx].trim();
      if (candidate.length > 0 && !normalized.includes(candidate)) {
        normalized.push(candidate);
      }
      idx = idx + 1;
    }
    return normalized;
  }

  private getCurrentDateKey(): string {
    const now: Date = new Date();
    const year: string = now.getFullYear().toString();
    const month: string = (now.getMonth() + 1).toString().padStart(2, '0');
    const day: string = now.getDate().toString().padStart(2, '0');
    return `${year}-${month}-${day}`;
  }

  private normalizeSplashCursor(cursor: number, count: number): number {
    if (count <= 0) {
      return -1;
    }
    if (cursor < 0) {
      return -1;
    }
    return cursor % count;
  }

  private resolveSplashBackgroundByRule(
    splashPaths: string[],
    rule: SplashRotationRule,
    storedCursor: number,
    storedDateKey: string
  ): SplashResolveResult {
    if (splashPaths.length === 0) {
      return {
        selectedPath: '',
        cursor: -1,
        lastDateKey: ''
      } as SplashResolveResult;
    }

    if (rule === SplashRotationRule.FIXED_FIRST) {
      return {
        selectedPath: splashPaths[0],
        cursor: 0,
        lastDateKey: ''
      } as SplashResolveResult;
    }

    if (rule === SplashRotationRule.DAILY) {
      const todayKey: string = this.getCurrentDateKey();
      const safeCursor: number = this.normalizeSplashCursor(storedCursor, splashPaths.length);
      if (storedDateKey !== todayKey) {
        const nextCursor: number = safeCursor < 0 ? 0 : (safeCursor + 1) % splashPaths.length;
        return {
          selectedPath: splashPaths[nextCursor],
          cursor: nextCursor,
          lastDateKey: todayKey
        } as SplashResolveResult;
      }
      return {
        selectedPath: splashPaths[safeCursor < 0 ? 0 : safeCursor],
        cursor: safeCursor < 0 ? 0 : safeCursor,
        lastDateKey: todayKey
      } as SplashResolveResult;
    }

    if (storedCursor < 0) {
      return {
        selectedPath: splashPaths[0],
        cursor: 0,
        lastDateKey: storedDateKey
      } as SplashResolveResult;
    }
    const nextCursor: number = (this.normalizeSplashCursor(storedCursor, splashPaths.length) + 1) % splashPaths.length;
    return {
      selectedPath: splashPaths[nextCursor],
      cursor: nextCursor,
      lastDateKey: storedDateKey
    } as SplashResolveResult;
  }

  /**
   * 应用自定义主题
   * 将自定义主题的背景图片和主色调设置为全局状态
   */
  public async applyCustomTheme(themeData: CustomThemeData): Promise<void> {
    try {
      logger.info(TAG, `开始应用自定义主题: ${themeData.name}`);
      const splashPaths: string[] = this.normalizeSplashBackgroundPaths(themeData);
      const splashRule: SplashRotationRule = this.sanitizeSplashRotationRule(themeData.splashRotationRule);
      const splashCursorInput: number = themeData.splashRotationCursor !== undefined ? themeData.splashRotationCursor : -1;
      const splashDateInput: string = themeData.splashRotationLastDateKey ? themeData.splashRotationLastDateKey : '';
      const splashResolved = this.resolveSplashBackgroundByRule(splashPaths, splashRule, splashCursorInput, splashDateInput);
      const hideSplashLogo: boolean = themeData.hideSplashLogo === true;
      const hideSplashProgress: boolean = themeData.hideSplashProgress === true;
      
      // 1. 设置全局状态（双版本背景）
      AppStorage.setOrCreate(CUSTOM_THEME_KEYS.BACKGROUND_IMAGE_LIGHT, themeData.backgroundImagePath);
      if (themeData.backgroundImagePathDark && themeData.backgroundImagePathDark.length > 0) {
        AppStorage.setOrCreate(CUSTOM_THEME_KEYS.BACKGROUND_IMAGE_DARK, themeData.backgroundImagePathDark);
      } else {
        // 若未提供深色版本，则先使用浅色版本占位
        AppStorage.setOrCreate(CUSTOM_THEME_KEYS.BACKGROUND_IMAGE_DARK, themeData.backgroundImagePath);
      }
      AppStorage.setOrCreate(CUSTOM_THEME_KEYS.SPLASH_BACKGROUND_IMAGE, splashResolved.selectedPath);
      AppStorage.setOrCreate(CUSTOM_THEME_KEYS.SPLASH_BACKGROUND_IMAGES, this.encodeSplashBackgrounds(splashPaths));
      AppStorage.setOrCreate(CUSTOM_THEME_KEYS.SPLASH_ROTATION_RULE, splashRule);
      AppStorage.setOrCreate(CUSTOM_THEME_KEYS.HIDE_SPLASH_LOGO, hideSplashLogo);
      AppStorage.setOrCreate(CUSTOM_THEME_KEYS.HIDE_SPLASH_PROGRESS, hideSplashProgress);
      AppStorage.setOrCreate(CUSTOM_THEME_KEYS.PRIMARY_COLOR, themeData.primaryColor);
      // 必须先设置 IS_CUSTOM_THEME_ACTIVE 为 true，再调用 refreshCustomBackgroundForCurrentTheme
      // 否则该函数会因为检查到 IS_CUSTOM_THEME_ACTIVE 不为 true 而提前返回
      AppStorage.setOrCreate(CUSTOM_THEME_KEYS.IS_CUSTOM_THEME_ACTIVE, true);
      AppStorage.setOrCreate(CUSTOM_THEME_KEYS.CURRENT_THEME_ID, themeData.id);
      // 根据当前实际主题刷新通用背景键，确保旧组件兼容
      this.refreshCustomBackgroundForCurrentTheme();
      
      // 2. 启用自定义主题时，强制将主题设置为AUTO以跟随系统
      // 避免用户之前固定为DARK/LIGHT导致与系统不一致
      if (this.currentTheme !== ThemeType.AUTO) {
        this.currentTheme = ThemeType.AUTO;
        await this.saveTheme(ThemeType.AUTO);
        // 主动通知为系统当前主题
        this.notifyThemeChange(this.actualTheme);
      }
      
      // 3. 保存自定义主题信息到首选项
      if (this.preferencesStore) {
        await this.preferencesStore.put('custom_theme_active', true);
        await this.preferencesStore.put('custom_theme_id', themeData.id);
        await this.preferencesStore.put('custom_theme_background_light', themeData.backgroundImagePath);
        await this.preferencesStore.put('custom_theme_background_dark', themeData.backgroundImagePathDark && themeData.backgroundImagePathDark.length > 0
          ? themeData.backgroundImagePathDark
          : themeData.backgroundImagePath);
        await this.preferencesStore.put(this.CUSTOM_THEME_SPLASH_BACKGROUND_KEY, splashResolved.selectedPath);
        await this.preferencesStore.put(this.CUSTOM_THEME_SPLASH_BACKGROUNDS_KEY, this.encodeSplashBackgrounds(splashPaths));
        await this.preferencesStore.put(this.CUSTOM_THEME_SPLASH_ROTATION_RULE_KEY, splashRule);
        await this.preferencesStore.put(this.CUSTOM_THEME_SPLASH_ROTATION_CURSOR_KEY, splashResolved.cursor);
        await this.preferencesStore.put(this.CUSTOM_THEME_SPLASH_ROTATION_DATE_KEY, splashResolved.lastDateKey);
        await this.preferencesStore.put(this.CUSTOM_THEME_HIDE_SPLASH_LOGO_KEY, hideSplashLogo);
        await this.preferencesStore.put(this.CUSTOM_THEME_HIDE_SPLASH_PROGRESS_KEY, hideSplashProgress);
        await this.preferencesStore.put('custom_theme_color', themeData.primaryColor);
        await this.preferencesStore.flush();
      }
      
      logger.info(TAG, `✅ 自定义主题应用成功: ${themeData.name}`);
      logger.info(TAG, `   浅色背景: ${themeData.backgroundImagePath}`);
      logger.info(TAG, `   深色背景: ${themeData.backgroundImagePathDark && themeData.backgroundImagePathDark.length > 0 ? themeData.backgroundImagePathDark : themeData.backgroundImagePath}`);
      logger.info(TAG, `   开屏轮换规则: ${splashRule}, 开屏图数量: ${splashPaths.length}`);
      logger.info(TAG, `   启动页隐藏Logo: ${hideSplashLogo}`);
      logger.info(TAG, `   启动页隐藏进度: ${hideSplashProgress}`);
      logger.info(TAG, `   主色调: ${themeData.primaryColor}`);
      logger.info(TAG, `   当前显示主题: ${this.getActualThemeSync()}`);
    } catch (error) {
      const errorMsg = error instanceof Error ? error.message : String(error);
      logger.error(TAG, `应用自定义主题失败: ${errorMsg}`);
      throw new Error(`应用自定义主题失败: ${errorMsg}`);
    }
  }

  /**
   * 清除自定义主题，恢复默认主题
   */
  public async clearCustomTheme(): Promise<void> {
    try {
      logger.info(TAG, '开始清除自定义主题');
      
      // 1. 清除全局状态
      AppStorage.setOrCreate(CUSTOM_THEME_KEYS.BACKGROUND_IMAGE, '');
      AppStorage.setOrCreate(CUSTOM_THEME_KEYS.BACKGROUND_IMAGE_LIGHT, '');
      AppStorage.setOrCreate(CUSTOM_THEME_KEYS.BACKGROUND_IMAGE_DARK, '');
      AppStorage.setOrCreate(CUSTOM_THEME_KEYS.SPLASH_BACKGROUND_IMAGE, '');
      AppStorage.setOrCreate(CUSTOM_THEME_KEYS.SPLASH_BACKGROUND_IMAGES, '');
      AppStorage.setOrCreate(CUSTOM_THEME_KEYS.SPLASH_ROTATION_RULE, SplashRotationRule.EVERY_LAUNCH);
      AppStorage.setOrCreate(CUSTOM_THEME_KEYS.HIDE_SPLASH_LOGO, false);
      AppStorage.setOrCreate(CUSTOM_THEME_KEYS.HIDE_SPLASH_PROGRESS, false);
      AppStorage.setOrCreate(CUSTOM_THEME_KEYS.PRIMARY_COLOR, '');
      AppStorage.setOrCreate(CUSTOM_THEME_KEYS.IS_CUSTOM_THEME_ACTIVE, false);
      AppStorage.setOrCreate(CUSTOM_THEME_KEYS.CURRENT_THEME_ID, '');
      
      // 2. 清除首选项
      if (this.preferencesStore) {
        await this.preferencesStore.delete('custom_theme_active');
        await this.preferencesStore.delete('custom_theme_id');
        await this.preferencesStore.delete('custom_theme_background_light');
        await this.preferencesStore.delete('custom_theme_background_dark');
        await this.preferencesStore.delete(this.CUSTOM_THEME_SPLASH_BACKGROUND_KEY);
        await this.preferencesStore.delete(this.CUSTOM_THEME_SPLASH_BACKGROUNDS_KEY);
        await this.preferencesStore.delete(this.CUSTOM_THEME_SPLASH_ROTATION_RULE_KEY);
        await this.preferencesStore.delete(this.CUSTOM_THEME_SPLASH_ROTATION_CURSOR_KEY);
        await this.preferencesStore.delete(this.CUSTOM_THEME_SPLASH_ROTATION_DATE_KEY);
        await this.preferencesStore.delete(this.CUSTOM_THEME_HIDE_SPLASH_LOGO_KEY);
        await this.preferencesStore.delete(this.CUSTOM_THEME_HIDE_SPLASH_PROGRESS_KEY);
        await this.preferencesStore.delete('custom_theme_color');
        await this.preferencesStore.flush();
      }
      
      // 3. 恢复默认主题（AUTO模式）
      await this.setTheme(ThemeType.AUTO);
      
      logger.info(TAG, '✅ 自定义主题已清除，恢复默认主题');
    } catch (error) {
      const errorMsg = error instanceof Error ? error.message : String(error);
      logger.error(TAG, `清除自定义主题失败: ${errorMsg}`);
      throw new Error(`清除自定义主题失败: ${errorMsg}`);
    }
  }

  /**
   * 检查是否有激活的自定义主题
   */
  public isCustomThemeActive(): boolean {
    const isActive = AppStorage.get<boolean>(CUSTOM_THEME_KEYS.IS_CUSTOM_THEME_ACTIVE);
    return isActive === true;
  }

  /**
   * 获取当前自定义主题的背景图片路径
   */
  public getCustomThemeBackground(): string {
    return AppStorage.get<string>(CUSTOM_THEME_KEYS.BACKGROUND_IMAGE) || '';
  }

  /**
   * 获取当前自定义主题的开屏背景图片路径
   */
  public getCustomThemeSplashBackground(): string {
    return AppStorage.get<string>(CUSTOM_THEME_KEYS.SPLASH_BACKGROUND_IMAGE) || '';
  }

  /**
   * 获取当前自定义主题是否隐藏启动页Logo
   */
  public isSplashLogoHiddenByTheme(): boolean {
    return AppStorage.get<boolean>(CUSTOM_THEME_KEYS.HIDE_SPLASH_LOGO) === true;
  }

  /**
   * 获取当前自定义主题是否隐藏启动页进度
   */
  public isSplashProgressHiddenByTheme(): boolean {
    return AppStorage.get<boolean>(CUSTOM_THEME_KEYS.HIDE_SPLASH_PROGRESS) === true;
  }

  /**
   * 在启动页展示前刷新一次开屏背景选择结果。
   * 说明：
   * 1. 冷启动时 initialize() 内部已完成一次决策，不应重复调用本方法；
   * 2. 当 ThemeManager 已初始化且再次进入启动页时，可调用本方法按规则轮换。
   */
  public async refreshSplashBackgroundForLaunch(): Promise<void> {
    try {
      if (!this.isCustomThemeActive()) {
        return;
      }
      if (!this.preferencesStore) {
        await this.initializePreferences();
      }

      let splashBackgroundsRaw: string = AppStorage.get<string>(CUSTOM_THEME_KEYS.SPLASH_BACKGROUND_IMAGES) || '';
      let splashPaths: string[] = this.decodeSplashBackgrounds(splashBackgroundsRaw);
      let splashRuleRaw: string = AppStorage.get<string>(CUSTOM_THEME_KEYS.SPLASH_ROTATION_RULE) || '';
      const currentSplash: string = AppStorage.get<string>(CUSTOM_THEME_KEYS.SPLASH_BACKGROUND_IMAGE) || '';

      if (this.preferencesStore) {
        if (splashBackgroundsRaw.length === 0) {
          splashBackgroundsRaw = await this.preferencesStore.get(this.CUSTOM_THEME_SPLASH_BACKGROUNDS_KEY, '') as string;
          splashPaths = this.decodeSplashBackgrounds(splashBackgroundsRaw);
        }
        if (splashRuleRaw.length === 0) {
          splashRuleRaw = await this.preferencesStore.get(this.CUSTOM_THEME_SPLASH_ROTATION_RULE_KEY, '') as string;
        }
      }

      if (splashPaths.length === 0 && currentSplash.length > 0) {
        splashPaths.push(currentSplash);
      }
      if (splashPaths.length === 0) {
        return;
      }

      let splashCursorRaw: number = -1;
      let splashDateKey: string = '';
      if (this.preferencesStore) {
        splashCursorRaw = await this.preferencesStore.get(this.CUSTOM_THEME_SPLASH_ROTATION_CURSOR_KEY, -1) as number;
        splashDateKey = await this.preferencesStore.get(this.CUSTOM_THEME_SPLASH_ROTATION_DATE_KEY, '') as string;
      }

      const splashRuleInput: string = splashRuleRaw && splashRuleRaw.length > 0
        ? splashRuleRaw
        : SplashRotationRule.EVERY_LAUNCH;
      const splashRule: SplashRotationRule = this.sanitizeSplashRotationRule(splashRuleInput);
      const splashResolved: SplashResolveResult = this.resolveSplashBackgroundByRule(
        splashPaths,
        splashRule,
        splashCursorRaw,
        splashDateKey
      );

      AppStorage.setOrCreate(CUSTOM_THEME_KEYS.SPLASH_BACKGROUND_IMAGE, splashResolved.selectedPath);
      AppStorage.setOrCreate(CUSTOM_THEME_KEYS.SPLASH_BACKGROUND_IMAGES, this.encodeSplashBackgrounds(splashPaths));
      AppStorage.setOrCreate(CUSTOM_THEME_KEYS.SPLASH_ROTATION_RULE, splashRule);

      if (this.preferencesStore) {
        await this.preferencesStore.put(this.CUSTOM_THEME_SPLASH_BACKGROUND_KEY, splashResolved.selectedPath);
        await this.preferencesStore.put(this.CUSTOM_THEME_SPLASH_BACKGROUNDS_KEY, this.encodeSplashBackgrounds(splashPaths));
        await this.preferencesStore.put(this.CUSTOM_THEME_SPLASH_ROTATION_RULE_KEY, splashRule);
        await this.preferencesStore.put(this.CUSTOM_THEME_SPLASH_ROTATION_CURSOR_KEY, splashResolved.cursor);
        await this.preferencesStore.put(this.CUSTOM_THEME_SPLASH_ROTATION_DATE_KEY, splashResolved.lastDateKey);
        await this.preferencesStore.flush();
      }

      logger.info(
        TAG,
        `启动页轮换开屏图完成: 规则=${splashRule}, 索引=${splashResolved.cursor}, 数量=${splashPaths.length}`
      );
    } catch (error) {
      const errorMsg: string = error instanceof Error ? error.message : String(error);
      logger.error(TAG, `启动页轮换开屏图失败: ${errorMsg}`);
    }
  }

  /**
   * 获取当前自定义主题的主色调
   */
  public getCustomThemePrimaryColor(): string {
    return AppStorage.get<string>(CUSTOM_THEME_KEYS.PRIMARY_COLOR) || '';
  }

  /**
   * 获取当前自定义主题的ID
   */
  public getCurrentCustomThemeId(): string {
    return AppStorage.get<string>(CUSTOM_THEME_KEYS.CURRENT_THEME_ID) || '';
  }

  /**
   * 初始化自定义主题状态（从存储加载）
   * 在ThemeManager初始化时调用
   */
  private async loadCustomThemeState(): Promise<void> {
    try {
      if (!this.preferencesStore) {
        return;
      }
      
      const isActive: boolean = await this.preferencesStore.get('custom_theme_active', false) as boolean;
      const themeId: string = await this.preferencesStore.get('custom_theme_id', '') as string;
      let backgroundLight: string = await this.preferencesStore.get('custom_theme_background_light', '') as string;
      let backgroundDark: string = await this.preferencesStore.get('custom_theme_background_dark', '') as string;
      const legacySplashBackground: string = await this.preferencesStore.get(this.CUSTOM_THEME_SPLASH_BACKGROUND_KEY, '') as string;
      const splashBackgroundsRaw: string = await this.preferencesStore.get(this.CUSTOM_THEME_SPLASH_BACKGROUNDS_KEY, '') as string;
      const splashRotationRuleRaw: string = await this.preferencesStore.get(this.CUSTOM_THEME_SPLASH_ROTATION_RULE_KEY, '') as string;
      const splashCursorRaw: number = await this.preferencesStore.get(this.CUSTOM_THEME_SPLASH_ROTATION_CURSOR_KEY, -1) as number;
      const splashDateKey: string = await this.preferencesStore.get(this.CUSTOM_THEME_SPLASH_ROTATION_DATE_KEY, '') as string;
      const hideSplashLogo: boolean = await this.preferencesStore.get(this.CUSTOM_THEME_HIDE_SPLASH_LOGO_KEY, false) as boolean;
      const hideSplashProgress: boolean = await this.preferencesStore.get(this.CUSTOM_THEME_HIDE_SPLASH_PROGRESS_KEY, false) as boolean;
      const color: string = await this.preferencesStore.get('custom_theme_color', '') as string;

      // 媒体资源模式迁移：默认/第二自定义主题不应使用本地文件路径
      const isDefaultOrSecondary: boolean = (themeId === 'default_custom_theme' || themeId === 'secondary_custom_theme');
      const hasLegacyFilePath: boolean = (backgroundLight.indexOf('/custom_themes/') >= 0) || (backgroundDark.indexOf('/custom_themes/') >= 0);
      if (isActive && isDefaultOrSecondary && hasLegacyFilePath) {
        backgroundLight = '';
        backgroundDark = '';
        await this.preferencesStore.put('custom_theme_background_light', '');
        await this.preferencesStore.put('custom_theme_background_dark', '');
        await this.preferencesStore.flush();
        logger.info(TAG, '🔧 已迁移默认/次级自定义主题到媒体资源模式（清空旧文件路径）');
      }

      const splashPaths: string[] = this.decodeSplashBackgrounds(splashBackgroundsRaw);
      if (splashPaths.length === 0 && legacySplashBackground.length > 0) {
        splashPaths.push(legacySplashBackground);
      }
      const splashRuleInput: string = splashRotationRuleRaw && splashRotationRuleRaw.length > 0
        ? splashRotationRuleRaw
        : (splashPaths.length > 0 ? SplashRotationRule.FIXED_FIRST : SplashRotationRule.EVERY_LAUNCH);
      const splashRule: SplashRotationRule = this.sanitizeSplashRotationRule(splashRuleInput);
      const splashResolved = this.resolveSplashBackgroundByRule(splashPaths, splashRule, splashCursorRaw, splashDateKey);
      
      // 显式布尔判断，避免 ArkTS 将字符串参与条件导致类型错误
      const hasColor: boolean = (color.length > 0);
      const hasBackground: boolean = ((backgroundLight.length > 0) || (backgroundDark.length > 0));
      // 允许默认/次级主题在空路径情况下保持激活，展示层将使用媒体资源回退
      const allowEmptyForResourceMode: boolean = isDefaultOrSecondary && isActive && hasColor;
      if ((isActive && hasColor && hasBackground) || allowEmptyForResourceMode) {
        AppStorage.setOrCreate(CUSTOM_THEME_KEYS.IS_CUSTOM_THEME_ACTIVE, true);
        AppStorage.setOrCreate(CUSTOM_THEME_KEYS.CURRENT_THEME_ID, themeId);
        // 保存双版本，并刷新通用键
        AppStorage.setOrCreate(CUSTOM_THEME_KEYS.BACKGROUND_IMAGE_LIGHT, backgroundLight ? backgroundLight : backgroundDark);
        AppStorage.setOrCreate(CUSTOM_THEME_KEYS.BACKGROUND_IMAGE_DARK, backgroundDark ? backgroundDark : backgroundLight);
        this.refreshCustomBackgroundForCurrentTheme();
        AppStorage.setOrCreate(CUSTOM_THEME_KEYS.SPLASH_BACKGROUND_IMAGE, splashResolved.selectedPath);
        AppStorage.setOrCreate(CUSTOM_THEME_KEYS.SPLASH_BACKGROUND_IMAGES, this.encodeSplashBackgrounds(splashPaths));
        AppStorage.setOrCreate(CUSTOM_THEME_KEYS.SPLASH_ROTATION_RULE, splashRule);
        AppStorage.setOrCreate(CUSTOM_THEME_KEYS.HIDE_SPLASH_LOGO, hideSplashLogo === true);
        AppStorage.setOrCreate(CUSTOM_THEME_KEYS.HIDE_SPLASH_PROGRESS, hideSplashProgress === true);
        AppStorage.setOrCreate(CUSTOM_THEME_KEYS.PRIMARY_COLOR, color);

        const needUpdateCursor: boolean = splashResolved.cursor !== splashCursorRaw;
        const needUpdateDate: boolean = splashResolved.lastDateKey !== splashDateKey;
        const needWriteBackList: boolean = splashBackgroundsRaw.length === 0 && splashPaths.length > 0;
        const needWriteBackRule: boolean = splashRotationRuleRaw.length === 0;
        if (needUpdateCursor || needUpdateDate || needWriteBackList || needWriteBackRule) {
          await this.preferencesStore.put(this.CUSTOM_THEME_SPLASH_BACKGROUND_KEY, splashResolved.selectedPath);
          await this.preferencesStore.put(this.CUSTOM_THEME_SPLASH_BACKGROUNDS_KEY, this.encodeSplashBackgrounds(splashPaths));
          await this.preferencesStore.put(this.CUSTOM_THEME_SPLASH_ROTATION_RULE_KEY, splashRule);
          await this.preferencesStore.put(this.CUSTOM_THEME_SPLASH_ROTATION_CURSOR_KEY, splashResolved.cursor);
          await this.preferencesStore.put(this.CUSTOM_THEME_SPLASH_ROTATION_DATE_KEY, splashResolved.lastDateKey);
          await this.preferencesStore.flush();
        }
        
        logger.info(TAG, `已加载自定义主题状态: ID=${themeId}, 主色调=${color}, 开屏图=${splashPaths.length}`);
      } else {
        // 确保初始化默认状态
        AppStorage.setOrCreate(CUSTOM_THEME_KEYS.IS_CUSTOM_THEME_ACTIVE, false);
        AppStorage.setOrCreate(CUSTOM_THEME_KEYS.CURRENT_THEME_ID, '');
        AppStorage.setOrCreate(CUSTOM_THEME_KEYS.BACKGROUND_IMAGE, '');
        AppStorage.setOrCreate(CUSTOM_THEME_KEYS.BACKGROUND_IMAGE_LIGHT, '');
        AppStorage.setOrCreate(CUSTOM_THEME_KEYS.BACKGROUND_IMAGE_DARK, '');
        AppStorage.setOrCreate(CUSTOM_THEME_KEYS.SPLASH_BACKGROUND_IMAGE, '');
        AppStorage.setOrCreate(CUSTOM_THEME_KEYS.SPLASH_BACKGROUND_IMAGES, '');
        AppStorage.setOrCreate(CUSTOM_THEME_KEYS.SPLASH_ROTATION_RULE, SplashRotationRule.EVERY_LAUNCH);
        AppStorage.setOrCreate(CUSTOM_THEME_KEYS.HIDE_SPLASH_LOGO, false);
        AppStorage.setOrCreate(CUSTOM_THEME_KEYS.HIDE_SPLASH_PROGRESS, false);
        AppStorage.setOrCreate(CUSTOM_THEME_KEYS.PRIMARY_COLOR, '');
      }
    } catch (error) {
      const errMsg: string = error instanceof Error ? error.message : String(error);
      logger.error(TAG, '加载自定义主题状态失败: ' + errMsg);
      // 初始化默认状态
      AppStorage.setOrCreate(CUSTOM_THEME_KEYS.IS_CUSTOM_THEME_ACTIVE, false);
      AppStorage.setOrCreate(CUSTOM_THEME_KEYS.CURRENT_THEME_ID, '');
      AppStorage.setOrCreate(CUSTOM_THEME_KEYS.BACKGROUND_IMAGE, '');
      AppStorage.setOrCreate(CUSTOM_THEME_KEYS.BACKGROUND_IMAGE_LIGHT, '');
      AppStorage.setOrCreate(CUSTOM_THEME_KEYS.BACKGROUND_IMAGE_DARK, '');
      AppStorage.setOrCreate(CUSTOM_THEME_KEYS.SPLASH_BACKGROUND_IMAGE, '');
      AppStorage.setOrCreate(CUSTOM_THEME_KEYS.SPLASH_BACKGROUND_IMAGES, '');
      AppStorage.setOrCreate(CUSTOM_THEME_KEYS.SPLASH_ROTATION_RULE, SplashRotationRule.EVERY_LAUNCH);
      AppStorage.setOrCreate(CUSTOM_THEME_KEYS.HIDE_SPLASH_LOGO, false);
      AppStorage.setOrCreate(CUSTOM_THEME_KEYS.HIDE_SPLASH_PROGRESS, false);
      AppStorage.setOrCreate(CUSTOM_THEME_KEYS.PRIMARY_COLOR, '');
    }
  }

  /**
   * 根据当前实际主题刷新通用背景键，使旧组件透明兼容
   */
  private refreshCustomBackgroundForCurrentTheme(): void {
    const isActive = AppStorage.get<boolean>(CUSTOM_THEME_KEYS.IS_CUSTOM_THEME_ACTIVE);
    if (isActive !== true) {
      // 未启用自定义主题时，保持默认值
      return;
    }
    const lightPath = AppStorage.get<string>(CUSTOM_THEME_KEYS.BACKGROUND_IMAGE_LIGHT) || '';
    const darkPath = AppStorage.get<string>(CUSTOM_THEME_KEYS.BACKGROUND_IMAGE_DARK) || '';
    const actual = this.getActualThemeSync();
    const chosen = actual === ThemeType.DARK ? (darkPath || lightPath) : (lightPath || darkPath);
    AppStorage.setOrCreate(CUSTOM_THEME_KEYS.BACKGROUND_IMAGE, chosen);
    logger.info(TAG, `已刷新自定义背景为当前主题版本: ${actual}, path=${chosen}`);
  }

  /**
   * 清理资源
   */
  public destroy(): void {
    this.themeChangeCallbacks.clear();
    this.preferencesStore = null;
    ThemeManager.instance = null;
    logger.info(TAG, '主题管理器已销毁');
  }
}

/**
 * 导出默认实例（可选）
 */
export const themeManager = ThemeManager.getInstance();
