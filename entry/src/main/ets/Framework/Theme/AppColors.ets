/**
 * 统一主题色系统 - AppColors
 * 
 * 设计理念：
 * 1. 语义化颜色角色 - 类似Material Design的颜色系统
 * 2. 自动适配深浅主题 - 通过ThemeManager自动切换
 * 3. 集中管理 - 所有颜色定义在一处，便于维护
 * 4. 类型安全 - 使用枚举和接口确保类型安全
 * 
 * 使用方式：
 * ```typescript
 * import { AppColors } from '../Framework/Theme/AppColors';
 * 
 * // 在组件中使用
 * .backgroundColor(AppColors.surface)
 * .fontColor(AppColors.onSurface)
 * .borderColor(AppColors.outline)
 * ```
 */

import { ThemeManager, ThemeType, GlassLevel, GlassStyleToken } from '../Managers/ThemeManager';

/**
 * 颜色角色枚举 - 定义所有语义化颜色角色
 */
export enum ColorRole {
  // 主色系
  PRIMARY = 'primary',
  ON_PRIMARY = 'onPrimary',
  PRIMARY_CONTAINER = 'primaryContainer',
  ON_PRIMARY_CONTAINER = 'onPrimaryContainer',
  
  // 次要色系
  SECONDARY = 'secondary',
  ON_SECONDARY = 'onSecondary',
  SECONDARY_CONTAINER = 'secondaryContainer',
  ON_SECONDARY_CONTAINER = 'onSecondaryContainer',
  
  // 第三色系
  TERTIARY = 'tertiary',
  ON_TERTIARY = 'onTertiary',
  TERTIARY_CONTAINER = 'tertiaryContainer',
  ON_TERTIARY_CONTAINER = 'onTertiaryContainer',
  
  // 表面色系
  SURFACE = 'surface',
  ON_SURFACE = 'onSurface',
  SURFACE_VARIANT = 'surfaceVariant',
  ON_SURFACE_VARIANT = 'onSurfaceVariant',
  SURFACE_CONTAINER = 'surfaceContainer',
  SURFACE_CONTAINER_LOW = 'surfaceContainerLow',
  SURFACE_CONTAINER_HIGH = 'surfaceContainerHigh',
  SURFACE_CONTAINER_HIGHEST = 'surfaceContainerHighest',
  
  // 背景色系
  BACKGROUND = 'background',
  ON_BACKGROUND = 'onBackground',
  
  // 状态色系
  ERROR = 'error',
  ON_ERROR = 'onError',
  ERROR_CONTAINER = 'errorContainer',
  ON_ERROR_CONTAINER = 'onErrorContainer',
  
  SUCCESS = 'success',
  ON_SUCCESS = 'onSuccess',
  
  WARNING = 'warning',
  ON_WARNING = 'onWarning',
  
  INFO = 'info',
  ON_INFO = 'onInfo',
  
  // 边框和分割线
  OUTLINE = 'outline',
  OUTLINE_VARIANT = 'outlineVariant',
  
  // 阴影
  SHADOW = 'shadow',
  SCRIM = 'scrim',
  
  // 反色（用于深色内容上的浅色元素）
  INVERSE_SURFACE = 'inverseSurface',
  INVERSE_ON_SURFACE = 'inverseOnSurface',
  INVERSE_PRIMARY = 'inversePrimary',
  
  // 文字层级
  TEXT_PRIMARY = 'textPrimary',
  TEXT_SECONDARY = 'textSecondary',
  TEXT_TERTIARY = 'textTertiary',
  TEXT_DISABLED = 'textDisabled',
  TEXT_HINT = 'textHint',
  
  // 图标层级
  ICON_PRIMARY = 'iconPrimary',
  ICON_SECONDARY = 'iconSecondary',
  ICON_DISABLED = 'iconDisabled',
  
  // 按钮专用
  BUTTON_PRIMARY = 'buttonPrimary',
  BUTTON_PRIMARY_TEXT = 'buttonPrimaryText',
  BUTTON_SECONDARY = 'buttonSecondary',
  BUTTON_SECONDARY_TEXT = 'buttonSecondaryText',
  BUTTON_DISABLED = 'buttonDisabled',
  BUTTON_DISABLED_TEXT = 'buttonDisabledText',
  
  // 特殊用途
  DIVIDER = 'divider',
  OVERLAY = 'overlay',
  RIPPLE = 'ripple'
}

/**
 * 颜色值接口 - 定义单个颜色的深浅主题值
 */
interface ColorValue {
  light: string;
  dark: string;
}

/**
 * 主题调色板 - 定义所有颜色角色的具体值
 */
const ThemePalette: Record<ColorRole, ColorValue> = {
  // ==================== 主色系 ====================
  // 品牌主色 - 用于主要按钮、FAB、重要强调元素
  [ColorRole.PRIMARY]: {
    light: '#007DFF',  // HarmonyOS蓝
    dark: '#4BA3FF'    // 深色模式下稍亮
  },
  [ColorRole.ON_PRIMARY]: {
    light: '#FFFFFF',
    dark: '#003258'
  },
  [ColorRole.PRIMARY_CONTAINER]: {
    light: '#D4E4FF',
    dark: '#004785'
  },
  [ColorRole.ON_PRIMARY_CONTAINER]: {
    light: '#001C38',
    dark: '#D4E4FF'
  },
  
  // ==================== 次要色系 ====================
  // 次要强调色 - 用于次要按钮、筛选器、进度条等
  [ColorRole.SECONDARY]: {
    light: '#5C5F71',
    dark: '#C4C6DC'
  },
  [ColorRole.ON_SECONDARY]: {
    light: '#FFFFFF',
    dark: '#2D3042'
  },
  [ColorRole.SECONDARY_CONTAINER]: {
    light: '#E1E2F4',
    dark: '#444659'
  },
  [ColorRole.ON_SECONDARY_CONTAINER]: {
    light: '#191B2C',
    dark: '#E1E2F4'
  },
  
  // ==================== 第三色系 ====================
  // 第三强调色 - 用于特殊标签、徽章等
  [ColorRole.TERTIARY]: {
    light: '#78536B',
    dark: '#E8B9D5'
  },
  [ColorRole.ON_TERTIARY]: {
    light: '#FFFFFF',
    dark: '#45263B'
  },
  [ColorRole.TERTIARY_CONTAINER]: {
    light: '#FFD8ED',
    dark: '#5D3C52'
  },
  [ColorRole.ON_TERTIARY_CONTAINER]: {
    light: '#2E1126',
    dark: '#FFD8ED'
  },
  
  // ==================== 表面色系 ====================
  // 表面色 - 用于卡片、对话框、底部栏等
  [ColorRole.SURFACE]: {
    light: '#FFFFFF',
    dark: '#1C1C1E'
  },
  [ColorRole.ON_SURFACE]: {
    light: '#1C1B1F',
    dark: '#E6E1E5'
  },
  [ColorRole.SURFACE_VARIANT]: {
    light: '#F5F5F5',
    dark: '#2C2C2E'
  },
  [ColorRole.ON_SURFACE_VARIANT]: {
    light: '#49454F',
    dark: '#CAC4D0'
  },
  [ColorRole.SURFACE_CONTAINER]: {
    light: '#F3F3F3',
    dark: '#242426'
  },
  [ColorRole.SURFACE_CONTAINER_LOW]: {
    light: '#F7F7F7',
    dark: '#1E1E20'
  },
  [ColorRole.SURFACE_CONTAINER_HIGH]: {
    light: '#ECECEC',
    dark: '#2E2E30'
  },
  [ColorRole.SURFACE_CONTAINER_HIGHEST]: {
    light: '#E6E6E6',
    dark: '#383838'
  },
  
  // ==================== 背景色系 ====================
  // 背景色 - 用于页面整体背景
  [ColorRole.BACKGROUND]: {
    light: '#FAFAFA',
    dark: '#121214'
  },
  [ColorRole.ON_BACKGROUND]: {
    light: '#1C1B1F',
    dark: '#E6E1E5'
  },
  
  // ==================== 状态色系 ====================
  // 错误色
  [ColorRole.ERROR]: {
    light: '#BA1A1A',
    dark: '#FFB4AB'
  },
  [ColorRole.ON_ERROR]: {
    light: '#FFFFFF',
    dark: '#690005'
  },
  [ColorRole.ERROR_CONTAINER]: {
    light: '#FFDAD6',
    dark: '#93000A'
  },
  [ColorRole.ON_ERROR_CONTAINER]: {
    light: '#410002',
    dark: '#FFDAD6'
  },
  
  // 成功色
  [ColorRole.SUCCESS]: {
    light: '#4CAF50',
    dark: '#81C784'
  },
  [ColorRole.ON_SUCCESS]: {
    light: '#FFFFFF',
    dark: '#1B5E20'
  },
  
  // 警告色
  [ColorRole.WARNING]: {
    light: '#FF9800',
    dark: '#FFB74D'
  },
  [ColorRole.ON_WARNING]: {
    light: '#FFFFFF',
    dark: '#3E2723'
  },
  
  // 信息色
  [ColorRole.INFO]: {
    light: '#2196F3',
    dark: '#64B5F6'
  },
  [ColorRole.ON_INFO]: {
    light: '#FFFFFF',
    dark: '#0D47A1'
  },
  
  // ==================== 边框和分割线 ====================
  [ColorRole.OUTLINE]: {
    light: '#79747E',
    dark: '#938F99'
  },
  [ColorRole.OUTLINE_VARIANT]: {
    light: '#E0E0E0',
    dark: '#444746'
  },
  
  // ==================== 阴影 ====================
  [ColorRole.SHADOW]: {
    light: '#000000',
    dark: '#000000'
  },
  [ColorRole.SCRIM]: {
    light: '#000000',
    dark: '#000000'
  },
  
  // ==================== 反色 ====================
  [ColorRole.INVERSE_SURFACE]: {
    light: '#313033',
    dark: '#E6E1E5'
  },
  [ColorRole.INVERSE_ON_SURFACE]: {
    light: '#F4EFF4',
    dark: '#313033'
  },
  [ColorRole.INVERSE_PRIMARY]: {
    light: '#A8C8FF',
    dark: '#0061A4'
  },
  
  // ==================== 文字层级 ====================
  [ColorRole.TEXT_PRIMARY]: {
    light: '#000000',
    dark: '#FFFFFF'
  },
  [ColorRole.TEXT_SECONDARY]: {
    light: '#666666',
    dark: '#B3B3B3'
  },
  [ColorRole.TEXT_TERTIARY]: {
    light: '#999999',
    dark: '#808080'
  },
  [ColorRole.TEXT_DISABLED]: {
    light: '#BDBDBD',
    dark: '#5C5C5C'
  },
  [ColorRole.TEXT_HINT]: {
    light: '#9E9E9E',
    dark: '#757575'
  },
  
  // ==================== 图标层级 ====================
  [ColorRole.ICON_PRIMARY]: {
    light: '#212121',
    dark: '#FFFFFF'
  },
  [ColorRole.ICON_SECONDARY]: {
    light: '#757575',
    dark: '#B3B3B3'
  },
  [ColorRole.ICON_DISABLED]: {
    light: '#BDBDBD',
    dark: '#5C5C5C'
  },
  
  // ==================== 按钮专用 ====================
  [ColorRole.BUTTON_PRIMARY]: {
    light: '#007DFF',
    dark: '#4BA3FF'
  },
  [ColorRole.BUTTON_PRIMARY_TEXT]: {
    light: '#FFFFFF',
    dark: '#FFFFFF'
  },
  [ColorRole.BUTTON_SECONDARY]: {
    light: '#E8E8E8',
    dark: '#3C3C3E'
  },
  [ColorRole.BUTTON_SECONDARY_TEXT]: {
    light: '#333333',
    dark: '#E0E0E0'
  },
  [ColorRole.BUTTON_DISABLED]: {
    light: '#E0E0E0',
    dark: '#3A3A3A'
  },
  [ColorRole.BUTTON_DISABLED_TEXT]: {
    light: '#9E9E9E',
    dark: '#666666'
  },
  
  // ==================== 特殊用途 ====================
  [ColorRole.DIVIDER]: {
    light: '#E0E0E0',
    dark: '#3A3A3A'
  },
  [ColorRole.OVERLAY]: {
    light: '#00000080',  // 50% 黑色
    dark: '#00000099'    // 60% 黑色
  },
  [ColorRole.RIPPLE]: {
    light: '#00000014',  // 8% 黑色
    dark: '#FFFFFF14'    // 8% 白色
  }
};

/**
 * 获取当前主题下的颜色值
 * 优先使用用户自定义主色（通过ThemeManager），否则使用默认调色板
 * @param role 颜色角色
 * @returns 当前主题对应的颜色字符串
 */
function getColorForCurrentTheme(role: ColorRole): string {
  const themeManager = ThemeManager.getInstance();
  const isDark = themeManager.isDarkThemeSync();
  
  // 尝试获取用户自定义主色（通过ThemeManager的自定义主题功能）
  if (role === ColorRole.PRIMARY || role === ColorRole.BUTTON_PRIMARY) {
    const customPrimaryColor = themeManager.getCustomThemePrimaryColor();
    if (customPrimaryColor && customPrimaryColor.length > 0) {
      return customPrimaryColor;
    }
  }
  
  const colorValue = ThemePalette[role];
  return isDark ? colorValue.dark : colorValue.light;
}

/**
 * 获取指定主题下的颜色值
 * @param role 颜色角色
 * @param theme 主题类型
 * @returns 指定主题对应的颜色字符串
 */
function getColorForTheme(role: ColorRole, theme: ThemeType): string {
  const isDark = theme === ThemeType.DARK || theme === ThemeType.PRIVACY;
  const colorValue = ThemePalette[role];
  return isDark ? colorValue.dark : colorValue.light;
}

/**
 * AppColors - 统一主题色访问接口
 * 
 * 使用静态getter实现动态获取当前主题颜色
 * 每次访问都会根据当前主题返回正确的颜色值
 */
export class AppColors {
  // ==================== 主色系 ====================
  static get primary(): string { return getColorForCurrentTheme(ColorRole.PRIMARY); }
  static get onPrimary(): string { return getColorForCurrentTheme(ColorRole.ON_PRIMARY); }
  static get primaryContainer(): string { return getColorForCurrentTheme(ColorRole.PRIMARY_CONTAINER); }
  static get onPrimaryContainer(): string { return getColorForCurrentTheme(ColorRole.ON_PRIMARY_CONTAINER); }
  
  // ==================== 次要色系 ====================
  static get secondary(): string { return getColorForCurrentTheme(ColorRole.SECONDARY); }
  static get onSecondary(): string { return getColorForCurrentTheme(ColorRole.ON_SECONDARY); }
  static get secondaryContainer(): string { return getColorForCurrentTheme(ColorRole.SECONDARY_CONTAINER); }
  static get onSecondaryContainer(): string { return getColorForCurrentTheme(ColorRole.ON_SECONDARY_CONTAINER); }
  
  // ==================== 第三色系 ====================
  static get tertiary(): string { return getColorForCurrentTheme(ColorRole.TERTIARY); }
  static get onTertiary(): string { return getColorForCurrentTheme(ColorRole.ON_TERTIARY); }
  static get tertiaryContainer(): string { return getColorForCurrentTheme(ColorRole.TERTIARY_CONTAINER); }
  static get onTertiaryContainer(): string { return getColorForCurrentTheme(ColorRole.ON_TERTIARY_CONTAINER); }
  
  // ==================== 表面色系 ====================
  static get surface(): string { return getColorForCurrentTheme(ColorRole.SURFACE); }
  static get onSurface(): string { return getColorForCurrentTheme(ColorRole.ON_SURFACE); }
  static get surfaceVariant(): string { return getColorForCurrentTheme(ColorRole.SURFACE_VARIANT); }
  static get onSurfaceVariant(): string { return getColorForCurrentTheme(ColorRole.ON_SURFACE_VARIANT); }
  static get surfaceContainer(): string { return getColorForCurrentTheme(ColorRole.SURFACE_CONTAINER); }
  static get surfaceContainerLow(): string { return getColorForCurrentTheme(ColorRole.SURFACE_CONTAINER_LOW); }
  static get surfaceContainerHigh(): string { return getColorForCurrentTheme(ColorRole.SURFACE_CONTAINER_HIGH); }
  static get surfaceContainerHighest(): string { return getColorForCurrentTheme(ColorRole.SURFACE_CONTAINER_HIGHEST); }
  
  // ==================== 背景色系 ====================
  static get background(): string { return getColorForCurrentTheme(ColorRole.BACKGROUND); }
  static get onBackground(): string { return getColorForCurrentTheme(ColorRole.ON_BACKGROUND); }
  
  // ==================== 状态色系 ====================
  static get error(): string { return getColorForCurrentTheme(ColorRole.ERROR); }
  static get onError(): string { return getColorForCurrentTheme(ColorRole.ON_ERROR); }
  static get errorContainer(): string { return getColorForCurrentTheme(ColorRole.ERROR_CONTAINER); }
  static get onErrorContainer(): string { return getColorForCurrentTheme(ColorRole.ON_ERROR_CONTAINER); }
  
  static get success(): string { return getColorForCurrentTheme(ColorRole.SUCCESS); }
  static get onSuccess(): string { return getColorForCurrentTheme(ColorRole.ON_SUCCESS); }
  
  static get warning(): string { return getColorForCurrentTheme(ColorRole.WARNING); }
  static get onWarning(): string { return getColorForCurrentTheme(ColorRole.ON_WARNING); }
  
  static get info(): string { return getColorForCurrentTheme(ColorRole.INFO); }
  static get onInfo(): string { return getColorForCurrentTheme(ColorRole.ON_INFO); }
  
  // ==================== 边框和分割线 ====================
  static get outline(): string { return getColorForCurrentTheme(ColorRole.OUTLINE); }
  static get outlineVariant(): string { return getColorForCurrentTheme(ColorRole.OUTLINE_VARIANT); }
  
  // ==================== 阴影 ====================
  static get shadow(): string { return getColorForCurrentTheme(ColorRole.SHADOW); }
  static get scrim(): string { return getColorForCurrentTheme(ColorRole.SCRIM); }
  
  // ==================== 反色 ====================
  static get inverseSurface(): string { return getColorForCurrentTheme(ColorRole.INVERSE_SURFACE); }
  static get inverseOnSurface(): string { return getColorForCurrentTheme(ColorRole.INVERSE_ON_SURFACE); }
  static get inversePrimary(): string { return getColorForCurrentTheme(ColorRole.INVERSE_PRIMARY); }
  
  // ==================== 文字层级 ====================
  static get textPrimary(): string { return getColorForCurrentTheme(ColorRole.TEXT_PRIMARY); }
  static get textSecondary(): string { return getColorForCurrentTheme(ColorRole.TEXT_SECONDARY); }
  static get textTertiary(): string { return getColorForCurrentTheme(ColorRole.TEXT_TERTIARY); }
  static get textDisabled(): string { return getColorForCurrentTheme(ColorRole.TEXT_DISABLED); }
  static get textHint(): string { return getColorForCurrentTheme(ColorRole.TEXT_HINT); }
  
  // ==================== 图标层级 ====================
  static get iconPrimary(): string { return getColorForCurrentTheme(ColorRole.ICON_PRIMARY); }
  static get iconSecondary(): string { return getColorForCurrentTheme(ColorRole.ICON_SECONDARY); }
  static get iconDisabled(): string { return getColorForCurrentTheme(ColorRole.ICON_DISABLED); }
  
  // ==================== 按钮专用 ====================
  static get buttonPrimary(): string { return getColorForCurrentTheme(ColorRole.BUTTON_PRIMARY); }
  static get buttonPrimaryText(): string { return getColorForCurrentTheme(ColorRole.BUTTON_PRIMARY_TEXT); }
  static get buttonSecondary(): string { return getColorForCurrentTheme(ColorRole.BUTTON_SECONDARY); }
  static get buttonSecondaryText(): string { return getColorForCurrentTheme(ColorRole.BUTTON_SECONDARY_TEXT); }
  static get buttonDisabled(): string { return getColorForCurrentTheme(ColorRole.BUTTON_DISABLED); }
  static get buttonDisabledText(): string { return getColorForCurrentTheme(ColorRole.BUTTON_DISABLED_TEXT); }
  
  // ==================== 特殊用途 ====================
  static get divider(): string { return getColorForCurrentTheme(ColorRole.DIVIDER); }
  static get overlay(): string { return getColorForCurrentTheme(ColorRole.OVERLAY); }
  static get ripple(): string { return getColorForCurrentTheme(ColorRole.RIPPLE); }

  // ==================== Glass Tokens ====================
  static get glassHero(): string { return AppColors.getGlassToken(GlassLevel.HERO).backgroundColor; }
  static get glassNavigation(): string { return AppColors.getGlassToken(GlassLevel.NAVIGATION).backgroundColor; }
  static get glassCard(): string { return AppColors.getGlassToken(GlassLevel.CARD).backgroundColor; }
  static get glassSheet(): string { return AppColors.getGlassToken(GlassLevel.SHEET).backgroundColor; }
  static get glassFloating(): string { return AppColors.getGlassToken(GlassLevel.FLOATING).backgroundColor; }

  static get glassHeroBorder(): string { return AppColors.getGlassToken(GlassLevel.HERO).borderColor; }
  static get glassNavigationBorder(): string { return AppColors.getGlassToken(GlassLevel.NAVIGATION).borderColor; }
  static get glassCardBorder(): string { return AppColors.getGlassToken(GlassLevel.CARD).borderColor; }
  static get glassSheetBorder(): string { return AppColors.getGlassToken(GlassLevel.SHEET).borderColor; }
  static get glassFloatingBorder(): string { return AppColors.getGlassToken(GlassLevel.FLOATING).borderColor; }
  
  // ==================== 工具方法 ====================

  static getGlassToken(level: GlassLevel = GlassLevel.CARD): GlassStyleToken {
    return ThemeManager.getInstance().getGlassToken(level);
  }

  static getGlassBackground(level: GlassLevel = GlassLevel.CARD): string {
    return AppColors.getGlassToken(level).backgroundColor;
  }

  static getGlassBorder(level: GlassLevel = GlassLevel.CARD): string {
    return AppColors.getGlassToken(level).borderColor;
  }

  static getGlassShadow(level: GlassLevel = GlassLevel.CARD): string {
    return AppColors.getGlassToken(level).shadowColor;
  }
  
  /**
   * 根据颜色角色获取颜色
   * @param role 颜色角色
   * @returns 当前主题对应的颜色字符串
   */
  static getColor(role: ColorRole): string {
    return getColorForCurrentTheme(role);
  }
  
  /**
   * 根据颜色角色和主题获取颜色
   * @param role 颜色角色
   * @param theme 主题类型
   * @returns 指定主题对应的颜色字符串
   */
  static getColorForTheme(role: ColorRole, theme: ThemeType): string {
    return getColorForTheme(role, theme);
  }
  
  /**
   * 获取带透明度的颜色
   * @param role 颜色角色
   * @param alpha 透明度 (0-1)
   * @returns 带透明度的颜色字符串
   */
  static withAlpha(role: ColorRole, alpha: number): string {
    const color = getColorForCurrentTheme(role);
    const alphaHex = Math.round(alpha * 255).toString(16).padStart(2, '0');
    // 将 #RRGGBB 转换为 #AARRGGBB
    if (color.length === 7) {
      return `#${alphaHex}${color.substring(1)}`;
    }
    // 如果已经有透明度，替换它
    if (color.length === 9) {
      return `#${alphaHex}${color.substring(3)}`;
    }
    return color;
  }
  
  /**
   * 获取阴影颜色（带透明度）
   * @param elevation 阴影高度 (0-24)
   * @returns 阴影颜色字符串
   */
  static getShadowColor(elevation: number): string {
    // 根据elevation计算透明度，范围从0.05到0.3
    const alpha = Math.min(0.05 + elevation * 0.01, 0.3);
    return AppColors.withAlpha(ColorRole.SHADOW, alpha);
  }
  
  /**
   * 获取当前是否为深色主题
   */
  static get isDark(): boolean {
    const themeManager = ThemeManager.getInstance();
    return themeManager.isDarkThemeSync();
  }
  
  // ==================== 用户配置访问 ====================
  
  /**
   * 获取用户配置的透明度
   * @param component 组件类型
   * @returns 透明度值 (0-1)
   */
  static getTransparency(component: 'navigationBar' | 'tabBar' | 'card' | 'dialog' | 'floatingBall' | 'menu' | 'sidebar'): number {
    try {
      const themeManager = ThemeManager.getInstance();
      return themeManager.getComponentTransparency(component);
    } catch {
      return 1.0;
    }
  }
  
  /**
   * 检查是否启用模糊效果
   */
  static get blurEnabled(): boolean {
    try {
      const themeManager = ThemeManager.getInstance();
      return themeManager.isBlurEffectEnabled();
    } catch {
      return true;
    }
  }
  
  /**
   * 获取模糊强度
   */
  static get blurIntensity(): number {
    try {
      const themeManager = ThemeManager.getInstance();
      return themeManager.getUserThemeProfile().effects.blurIntensity;
    } catch {
      return 50;
    }
  }
  
  /**
   * 检查是否启用阴影效果
   */
  static get shadowEnabled(): boolean {
    try {
      const themeManager = ThemeManager.getInstance();
      return themeManager.isShadowEffectEnabled();
    } catch {
      return true;
    }
  }
  
  /**
   * 检查是否启用动画效果
   */
  static get animationEnabled(): boolean {
    try {
      const themeManager = ThemeManager.getInstance();
      return themeManager.isAnimationEnabled();
    } catch {
      return true;
    }
  }
  
  /**
   * 获取动画速度倍率
   */
  static get animationSpeed(): number {
    try {
      const themeManager = ThemeManager.getInstance();
      return themeManager.getAnimationSpeed();
    } catch {
      return 1.0;
    }
  }
  
  /**
   * 获取组件圆角大小
   */
  static get cornerRadius(): number {
    try {
      const themeManager = ThemeManager.getInstance();
      return themeManager.getUserCornerRadius();
    } catch {
      return 12;
    }
  }

  /**
   * 获取封面图片圆角大小
   */
  static get coverCornerRadius(): number {
    try {
      const themeManager = ThemeManager.getInstance();
      return themeManager.getUserCoverCornerRadius();
    } catch {
      return 12;
    }
  }
  
  /**
   * 检查是否启用玻璃拟态效果
   */
  static get glassmorphismEnabled(): boolean {
    try {
      const themeManager = ThemeManager.getInstance();
      return themeManager.getUserThemeProfile().effects.enableGlassmorphism;
    } catch {
      return true;
    }
  }
}

/**
 * 导出调色板，便于高级自定义
 */
export { ThemePalette };
