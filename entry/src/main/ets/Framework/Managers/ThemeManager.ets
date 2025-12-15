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

const TAG = 'ThemeManager';

/**
 * 主题类型枚举
 */
export enum ThemeType {
  LIGHT = 'light',
  DARK = 'dark',
  AUTO = 'auto'
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
  blurLevel: number;
  primaryColor: string;
  isDark: boolean;
  createTime: number;
  lastModified: number;
}

/**
 * 全局自定义主题状态键接口
 */
export interface CustomThemeKeys {
  BACKGROUND_IMAGE: string;
  BACKGROUND_IMAGE_LIGHT: string;
  BACKGROUND_IMAGE_DARK: string;
  SPLASH_BACKGROUND_IMAGE: string;
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

/**
 * 玻璃效果参数接口（显式类型，避免未类型化对象字面量）
 */
export interface GlassEffectOptions {
  backgroundColorResource: Resource; // 背景颜色必须使用资源，避免硬编码
  blurStyle: BlurStyle;
  radius: number;
  shadowColor: string; // 阴影颜色暂用字符串，与现有shadow调用保持一致
}

/**
 * 主题配置常量
 */
export const THEME_CONFIGS: Record<ThemeType, ThemeConfig> = {
  [ThemeType.LIGHT]: {
    name: 'light',
    displayName: '浅色主题',
    primaryColor: '#007AFF',
    backgroundColor: '#FFFFFF',
    textColor: '#000000',
    cardColor: '#F8F8F8',
    borderColor: '#E0E0E0',
    shadowColor: 'rgba(0, 0, 0, 0.1)'
  },
  [ThemeType.DARK]: {
    name: 'dark',
    displayName: '深色主题',
    primaryColor: '#0A84FF',
    backgroundColor: '#000000',
    textColor: '#FFFFFF',
    cardColor: '#1C1C1E',
    borderColor: '#38383A',
    shadowColor: 'rgba(255, 255, 255, 0.1)'
  },
  [ThemeType.AUTO]: {
    name: 'auto',
    displayName: '跟随系统',
    primaryColor: '#007AFF',
    backgroundColor: '#FFFFFF',
    textColor: '#000000',
    cardColor: '#F8F8F8',
    borderColor: '#E0E0E0',
    shadowColor: 'rgba(0, 0, 0, 0.1)'
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

      // 3.6. 如果自定义主题处于激活状态，则强制使用AUTO以跟随系统
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

  /**
   * 获取浅色主题下玻璃背景颜色（带透明度），统一全局风格
   */
  public getLightModeGlassBackgroundColor(): string {
    // 仅在浅色主题启用玻璃模糊时返回半透明白色
    const isLight: boolean = this.getActualThemeSync() === ThemeType.LIGHT;
    if (isLight && this.glassBlurEnabledInLightMode) {
      return '#40FFFFFF';
    }
    // 非浅色或未启用时返回透明，交由具体组件决定
    return 'transparent';
  }

  /**
   * 获取浅色主题下的模糊样式
   */
  public getLightModeBlurStyle(): BlurStyle {
    return BlurStyle.Thin;
  }

  /**
   * 获取深色主题下的模糊样式（与浅色保持一致）
   */
  public getDarkModeBlurStyle(): BlurStyle {
    return BlurStyle.Thin;
  }

  /**
   * 获取浅色玻璃投影颜色
   */
  public getLightModeGlassShadowColor(): string {
    return '#20000000';
  }

  /**
   * 获取深色主题下玻璃投影颜色（与浅色保持一致）
   */
  public getDarkModeGlassShadowColor(): string {
    return '#20000000';
  }

  /**
   * 获取浅色玻璃圆角半径（与页面默认R角统一）
   */
  public getLightModeGlassRadius(): number {
    return 12;
  }

  /**
   * 获取深色玻璃圆角半径（与浅色保持一致）
   */
  public getDarkModeGlassRadius(): number {
    return 12;
  }

  /**
   * 创建浅色主题玻璃模糊修饰符（不含边距与内边距，便于组件自行控制布局）
   */
  public createLightModeGlassModifier(): CommonModifier {
    const modifier: CommonModifier = new CommonModifier();
    const bg: string = this.getLightModeGlassBackgroundColor();
    const radius: number = this.getLightModeGlassRadius();
    const shadowColor: string = this.getLightModeGlassShadowColor();
    if (bg !== 'transparent') {
      modifier
        .backgroundColor(bg)
        .backgroundBlurStyle(this.getLightModeBlurStyle())
        .borderRadius(radius)
        .shadow({ radius: radius, color: shadowColor });
    }
    return modifier;
  }

  /**
   * 获取通用玻璃背景颜色（不区分主题），与历史实现保持一致
   */
  public getGlassBackgroundColor(): string {
    return '#40FFFFFF';
  }

  /**
   * 获取通用玻璃模糊样式（不区分主题）
   */
  public getGlassBlurStyle(): BlurStyle {
    const theme: ThemeType = this.getActualThemeSync();
    if (theme === ThemeType.LIGHT) {
      return this.getLightModeBlurStyle();
    }
    if (theme === ThemeType.DARK) {
      return this.getDarkModeBlurStyle();
    }
    // AUTO 模式下按实际主题处理
    return this.getLightModeBlurStyle();
  }

  /**
   * 获取通用玻璃阴影颜色（不区分主题）
   */
  public getGlassShadowColor(): string {
    const theme: ThemeType = this.getActualThemeSync();
    if (theme === ThemeType.LIGHT) {
      return this.getLightModeGlassShadowColor();
    }
    if (theme === ThemeType.DARK) {
      return this.getDarkModeGlassShadowColor();
    }
    return this.getLightModeGlassShadowColor();
  }

  /**
   * 获取通用玻璃圆角半径（不区分主题）
   */
  public getGlassRadius(): number {
    const theme: ThemeType = this.getActualThemeSync();
    if (theme === ThemeType.LIGHT) {
      return this.getLightModeGlassRadius();
    }
    if (theme === ThemeType.DARK) {
      return this.getDarkModeGlassRadius();
    }
    return this.getLightModeGlassRadius();
  }

  /**
   * 创建通用玻璃模糊修饰符（不含边距与内边距），适用于任意主题
   */
  public createGlassModifier(): CommonModifier {
    const modifier: CommonModifier = new CommonModifier();
    const radius: number = this.getGlassRadius();
    modifier
      .backgroundColor(this.getGlassBackgroundResource())
      .backgroundBlurStyle(this.getGlassBlurStyle())
      .borderRadius(radius)
      .shadow({ radius: radius, color: this.getGlassShadowColor() });
    return modifier;
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
    const radius: number = this.getGlassRadius();
    const base: GlassEffectOptions = {
      backgroundColorResource: this.getGlassBackgroundResource(),
      blurStyle: this.getGlassBlurStyle(),
      radius: radius,
      shadowColor: this.getGlassShadowColor()
    };

    if (context === GlassEffectContext.POPUP) {
      // 弹窗更厚的模糊与稍大的圆角
      return {
        backgroundColorResource: colorMap['app.color.system_resource_background_overlay'] ?? base.backgroundColorResource,
        blurStyle: BlurStyle.Thick,
        radius: radius + 4,
        shadowColor: base.shadowColor
      } as GlassEffectOptions;
    }

    if (context === GlassEffectContext.MENU) {
      // 菜单场景略微增厚的模糊
      return {
        backgroundColorResource: base.backgroundColorResource,
        blurStyle: BlurStyle.Regular,
        radius: radius,
        shadowColor: base.shadowColor
      } as GlassEffectOptions;
    }

    return base;
  }

  /**
   * 使用给定的玻璃效果参数创建修饰符（不含边距/内边距）
   */
  public createGlassModifierWithOptions(options: GlassEffectOptions): CommonModifier {
    const modifier: CommonModifier = new CommonModifier();
    modifier
      .backgroundColor(options.backgroundColorResource)
      .backgroundBlurStyle(options.blurStyle)
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

  /**
   * 应用自定义主题
   * 将自定义主题的背景图片和主色调设置为全局状态
   */
  public async applyCustomTheme(themeData: CustomThemeData): Promise<void> {
    try {
      logger.info(TAG, `开始应用自定义主题: ${themeData.name}`);
      
      // 1. 设置全局状态（双版本背景）
      AppStorage.setOrCreate(CUSTOM_THEME_KEYS.BACKGROUND_IMAGE_LIGHT, themeData.backgroundImagePath);
      if (themeData.backgroundImagePathDark && themeData.backgroundImagePathDark.length > 0) {
        AppStorage.setOrCreate(CUSTOM_THEME_KEYS.BACKGROUND_IMAGE_DARK, themeData.backgroundImagePathDark);
      } else {
        // 若未提供深色版本，则先使用浅色版本占位
        AppStorage.setOrCreate(CUSTOM_THEME_KEYS.BACKGROUND_IMAGE_DARK, themeData.backgroundImagePath);
      }
      if (themeData.splashBackgroundImagePath && themeData.splashBackgroundImagePath.length > 0) {
        AppStorage.setOrCreate(CUSTOM_THEME_KEYS.SPLASH_BACKGROUND_IMAGE, themeData.splashBackgroundImagePath);
      }
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
        if (themeData.splashBackgroundImagePath && themeData.splashBackgroundImagePath.length > 0) {
          await this.preferencesStore.put('custom_theme_splash_background', themeData.splashBackgroundImagePath);
        }
        await this.preferencesStore.put('custom_theme_color', themeData.primaryColor);
        await this.preferencesStore.flush();
      }
      
      logger.info(TAG, `✅ 自定义主题应用成功: ${themeData.name}`);
      logger.info(TAG, `   浅色背景: ${themeData.backgroundImagePath}`);
      logger.info(TAG, `   深色背景: ${themeData.backgroundImagePathDark && themeData.backgroundImagePathDark.length > 0 ? themeData.backgroundImagePathDark : themeData.backgroundImagePath}`);
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
      AppStorage.setOrCreate(CUSTOM_THEME_KEYS.PRIMARY_COLOR, '');
      AppStorage.setOrCreate(CUSTOM_THEME_KEYS.IS_CUSTOM_THEME_ACTIVE, false);
      AppStorage.setOrCreate(CUSTOM_THEME_KEYS.CURRENT_THEME_ID, '');
      
      // 2. 清除首选项
      if (this.preferencesStore) {
        await this.preferencesStore.delete('custom_theme_active');
        await this.preferencesStore.delete('custom_theme_id');
        await this.preferencesStore.delete('custom_theme_background_light');
        await this.preferencesStore.delete('custom_theme_background_dark');
        await this.preferencesStore.delete('custom_theme_splash_background');
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
      const splashBackground: string = await this.preferencesStore.get('custom_theme_splash_background', '') as string;
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
        if (splashBackground && splashBackground.length > 0) {
          AppStorage.setOrCreate(CUSTOM_THEME_KEYS.SPLASH_BACKGROUND_IMAGE, splashBackground);
        } else {
          AppStorage.setOrCreate(CUSTOM_THEME_KEYS.SPLASH_BACKGROUND_IMAGE, '');
        }
        AppStorage.setOrCreate(CUSTOM_THEME_KEYS.PRIMARY_COLOR, color);
        
        logger.info(TAG, `已加载自定义主题状态: ID=${themeId}, 主色调=${color}`);
      } else {
        // 确保初始化默认状态
        AppStorage.setOrCreate(CUSTOM_THEME_KEYS.IS_CUSTOM_THEME_ACTIVE, false);
        AppStorage.setOrCreate(CUSTOM_THEME_KEYS.CURRENT_THEME_ID, '');
        AppStorage.setOrCreate(CUSTOM_THEME_KEYS.BACKGROUND_IMAGE, '');
        AppStorage.setOrCreate(CUSTOM_THEME_KEYS.BACKGROUND_IMAGE_LIGHT, '');
        AppStorage.setOrCreate(CUSTOM_THEME_KEYS.BACKGROUND_IMAGE_DARK, '');
        AppStorage.setOrCreate(CUSTOM_THEME_KEYS.SPLASH_BACKGROUND_IMAGE, '');
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