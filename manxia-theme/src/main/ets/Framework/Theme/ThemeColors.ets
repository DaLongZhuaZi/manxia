/**
 * ThemeColors - 响应式主题色状态管理
 * 
 * 提供与@State配合使用的响应式主题色系统
 * 当主题切换时，自动触发UI更新
 * 
 * 使用方式：
 * ```typescript
 * @Component
 * struct MyComponent {
 *   @State colors: ThemeColorState = new ThemeColorState();
 *   
 *   aboutToAppear() {
 *     ThemeColorManager.register(this.colors, (newColors) => {
 *       this.colors = newColors;
 *     });
 *   }
 *   
 *   aboutToDisappear() {
 *     ThemeColorManager.unregister(this.colors);
 *   }
 *   
 *   build() {
 *     Column()
 *       .backgroundColor(this.colors.surface)
 *       .fontColor(this.colors.onSurface)
 *   }
 * }
 * ```
 */

import { ThemeManager, ThemeType, ThemeChangeCallback } from '../Managers/ThemeManager';
import { AppColors, ColorRole, ThemePalette } from './AppColors';
import { logger } from 'manxia_core/src/main/ets/Utils/Logger';

const TAG = 'ThemeColors';

/**
 * 主题色状态类 - 用于@State响应式绑定
 * 
 * 包含所有常用颜色的当前值，当主题切换时整体替换以触发UI更新
 */
@Observed
export class ThemeColorState {
  // 当前主题
  theme: ThemeType = ThemeType.DARK;
  isDark: boolean = true;
  
  // 主色系
  primary: string = '';
  onPrimary: string = '';
  primaryContainer: string = '';
  onPrimaryContainer: string = '';
  
  // 次要色系
  secondary: string = '';
  onSecondary: string = '';
  secondaryContainer: string = '';
  onSecondaryContainer: string = '';
  
  // 第三色系
  tertiary: string = '';
  onTertiary: string = '';
  tertiaryContainer: string = '';
  onTertiaryContainer: string = '';
  
  // 表面色系
  surface: string = '';
  onSurface: string = '';
  surfaceVariant: string = '';
  onSurfaceVariant: string = '';
  surfaceContainer: string = '';
  surfaceContainerLow: string = '';
  surfaceContainerHigh: string = '';
  surfaceContainerHighest: string = '';
  
  // 背景色系
  background: string = '';
  onBackground: string = '';
  
  // 状态色系
  error: string = '';
  onError: string = '';
  errorContainer: string = '';
  onErrorContainer: string = '';
  success: string = '';
  onSuccess: string = '';
  warning: string = '';
  onWarning: string = '';
  info: string = '';
  onInfo: string = '';
  
  // 边框和分割线
  outline: string = '';
  outlineVariant: string = '';
  
  // 阴影
  shadow: string = '';
  scrim: string = '';
  
  // 反色
  inverseSurface: string = '';
  inverseOnSurface: string = '';
  inversePrimary: string = '';
  
  // 文字层级
  textPrimary: string = '';
  textSecondary: string = '';
  textTertiary: string = '';
  textDisabled: string = '';
  textHint: string = '';
  
  // 图标层级
  iconPrimary: string = '';
  iconSecondary: string = '';
  iconDisabled: string = '';
  
  // 按钮专用
  buttonPrimary: string = '';
  buttonPrimaryText: string = '';
  buttonSecondary: string = '';
  buttonSecondaryText: string = '';
  buttonDisabled: string = '';
  buttonDisabledText: string = '';
  
  // 特殊用途
  divider: string = '';
  overlay: string = '';
  ripple: string = '';
  
  // 内部ID，用于管理器追踪
  private _id: string = '';
  
  constructor() {
    this._id = `theme_color_${Date.now()}_${Math.random().toString(36).substring(2, 9)}`;
    this.updateColors();
  }
  
  /**
   * 获取状态ID
   */
  getId(): string {
    return this._id;
  }
  
  /**
   * 更新所有颜色值
   */
  updateColors(): void {
    const themeManager = ThemeManager.getInstance();
    this.theme = themeManager.getActualThemeSync();
    this.isDark = this.theme === ThemeType.DARK || this.theme === ThemeType.PRIVACY;
    
    // 主色系
    this.primary = AppColors.primary;
    this.onPrimary = AppColors.onPrimary;
    this.primaryContainer = AppColors.primaryContainer;
    this.onPrimaryContainer = AppColors.onPrimaryContainer;
    
    // 次要色系
    this.secondary = AppColors.secondary;
    this.onSecondary = AppColors.onSecondary;
    this.secondaryContainer = AppColors.secondaryContainer;
    this.onSecondaryContainer = AppColors.onSecondaryContainer;
    
    // 第三色系
    this.tertiary = AppColors.tertiary;
    this.onTertiary = AppColors.onTertiary;
    this.tertiaryContainer = AppColors.tertiaryContainer;
    this.onTertiaryContainer = AppColors.onTertiaryContainer;
    
    // 表面色系
    this.surface = AppColors.surface;
    this.onSurface = AppColors.onSurface;
    this.surfaceVariant = AppColors.surfaceVariant;
    this.onSurfaceVariant = AppColors.onSurfaceVariant;
    this.surfaceContainer = AppColors.surfaceContainer;
    this.surfaceContainerLow = AppColors.surfaceContainerLow;
    this.surfaceContainerHigh = AppColors.surfaceContainerHigh;
    this.surfaceContainerHighest = AppColors.surfaceContainerHighest;
    
    // 背景色系
    this.background = AppColors.background;
    this.onBackground = AppColors.onBackground;
    
    // 状态色系
    this.error = AppColors.error;
    this.onError = AppColors.onError;
    this.errorContainer = AppColors.errorContainer;
    this.onErrorContainer = AppColors.onErrorContainer;
    this.success = AppColors.success;
    this.onSuccess = AppColors.onSuccess;
    this.warning = AppColors.warning;
    this.onWarning = AppColors.onWarning;
    this.info = AppColors.info;
    this.onInfo = AppColors.onInfo;
    
    // 边框和分割线
    this.outline = AppColors.outline;
    this.outlineVariant = AppColors.outlineVariant;
    
    // 阴影
    this.shadow = AppColors.shadow;
    this.scrim = AppColors.scrim;
    
    // 反色
    this.inverseSurface = AppColors.inverseSurface;
    this.inverseOnSurface = AppColors.inverseOnSurface;
    this.inversePrimary = AppColors.inversePrimary;
    
    // 文字层级
    this.textPrimary = AppColors.textPrimary;
    this.textSecondary = AppColors.textSecondary;
    this.textTertiary = AppColors.textTertiary;
    this.textDisabled = AppColors.textDisabled;
    this.textHint = AppColors.textHint;
    
    // 图标层级
    this.iconPrimary = AppColors.iconPrimary;
    this.iconSecondary = AppColors.iconSecondary;
    this.iconDisabled = AppColors.iconDisabled;
    
    // 按钮专用
    this.buttonPrimary = AppColors.buttonPrimary;
    this.buttonPrimaryText = AppColors.buttonPrimaryText;
    this.buttonSecondary = AppColors.buttonSecondary;
    this.buttonSecondaryText = AppColors.buttonSecondaryText;
    this.buttonDisabled = AppColors.buttonDisabled;
    this.buttonDisabledText = AppColors.buttonDisabledText;
    
    // 特殊用途
    this.divider = AppColors.divider;
    this.overlay = AppColors.overlay;
    this.ripple = AppColors.ripple;
  }
  
  /**
   * 创建当前状态的副本（用于触发@State更新）
   */
  clone(): ThemeColorState {
    const newState = new ThemeColorState();
    // 复制ID以保持追踪
    newState._id = this._id;
    return newState;
  }
  
  /**
   * 获取带透明度的颜色
   * @param colorValue 颜色值
   * @param alpha 透明度 (0-1)
   */
  withAlpha(colorValue: string, alpha: number): string {
    const alphaHex = Math.round(alpha * 255).toString(16).padStart(2, '0');
    if (colorValue.length === 7) {
      return `#${alphaHex}${colorValue.substring(1)}`;
    }
    if (colorValue.length === 9) {
      return `#${alphaHex}${colorValue.substring(3)}`;
    }
    return colorValue;
  }
}

/**
 * 主题色状态更新回调类型
 */
export type ThemeColorUpdateCallback = (newState: ThemeColorState) => void;

/**
 * 注册信息接口
 */
interface RegistrationInfo {
  state: ThemeColorState;
  callback: ThemeColorUpdateCallback;
  themeCallback: ThemeChangeCallback;
}

/**
 * ThemeColorManager - 主题色状态管理器
 * 
 * 负责管理所有ThemeColorState实例，当主题变化时自动更新
 */
export class ThemeColorManager {
  private static registrations: Map<string, RegistrationInfo> = new Map();
  
  /**
   * 注册主题色状态
   * @param state ThemeColorState实例
   * @param callback 状态更新回调，用于更新@State变量
   */
  static register(state: ThemeColorState, callback: ThemeColorUpdateCallback): void {
    const id = state.getId();
    
    // 如果已注册，先取消
    if (ThemeColorManager.registrations.has(id)) {
      ThemeColorManager.unregister(state);
    }
    
    // 创建主题变化回调
    const themeCallback: ThemeChangeCallback = (theme: ThemeType) => {
      const newState = state.clone();
      callback(newState);
      logger.debug(TAG, `主题色状态已更新: ${id}, 主题: ${theme}`);
    };
    
    // 注册到ThemeManager
    const themeManager = ThemeManager.getInstance();
    themeManager.onThemeChange(themeCallback);
    
    // 保存注册信息
    ThemeColorManager.registrations.set(id, {
      state,
      callback,
      themeCallback
    });
    
    logger.debug(TAG, `已注册主题色状态: ${id}`);
  }
  
  /**
   * 取消注册主题色状态
   * @param state ThemeColorState实例
   */
  static unregister(state: ThemeColorState): void {
    const id = state.getId();
    const registration = ThemeColorManager.registrations.get(id);
    
    if (registration) {
      // 从ThemeManager取消注册
      const themeManager = ThemeManager.getInstance();
      themeManager.offThemeChange(registration.themeCallback);
      
      // 移除注册信息
      ThemeColorManager.registrations.delete(id);
      
      logger.debug(TAG, `已取消注册主题色状态: ${id}`);
    }
  }
  
  /**
   * 获取当前注册数量
   */
  static getRegistrationCount(): number {
    return ThemeColorManager.registrations.size;
  }
  
  /**
   * 强制刷新所有注册的状态
   */
  static refreshAll(): void {
    ThemeColorManager.registrations.forEach((registration, id) => {
      const newState = registration.state.clone();
      registration.callback(newState);
    });
    logger.info(TAG, `已刷新所有主题色状态，数量: ${ThemeColorManager.registrations.size}`);
  }
}

/**
 * 便捷函数：创建并初始化主题色状态
 * 
 * 使用示例：
 * ```typescript
 * @State colors: ThemeColorState = createThemeColors();
 * ```
 */
export function createThemeColors(): ThemeColorState {
  return new ThemeColorState();
}
