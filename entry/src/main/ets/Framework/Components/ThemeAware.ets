// 文件路径: src/main/ets/Framework/Components/ThemeAware.ets
/**
 * 主题感知组件基类
 * 提供主题切换的基础功能，简化主题相关组件的开发
 */

import { ThemeManager, ThemeType } from '../Managers/ThemeManager';
import { logger } from '../../Utils/Logger';

// 定义类型
interface AnimateParam {
  duration: number;
  curve: Curve;
  iterations: number;
  playMode: PlayMode;
}

/**
 * 主题感知状态基类
 */
@Observed
export class ThemeAwareState {
  public currentTheme: ThemeType = ThemeType.DARK;
  public isThemeTransitioning: boolean = false;

  constructor() {
    const themeManager = ThemeManager.getInstance();
    this.currentTheme = themeManager.getCurrentThemeSync();
  }

  /**
   * 更新当前主题
   */
  public updateTheme(theme: ThemeType): void {
    this.currentTheme = theme;
  }

  /**
   * 设置主题过渡状态
   */
  public setThemeTransitioning(transitioning: boolean): void {
    this.isThemeTransitioning = transitioning;
  }

  /**
   * 判断是否为暗色主题
   */
  public isDarkTheme(): boolean {
    return this.currentTheme === ThemeType.DARK;
  }

  /**
   * 判断是否为浅色主题
   */
  public isLightTheme(): boolean {
    return this.currentTheme === ThemeType.LIGHT;
  }
}

/**
 * 主题感知组件辅助类
 */
interface GeneratedTypeLiteralInterface_1 {
  light: string;
  dark: string;
}

export class ThemeAwareHelper {
  private static themeChangeCallbacks = new Map<string, (theme: ThemeType) => void>();

  /**
   * 初始化主题感知功能
   */
  public static async initializeThemeAware(
    componentId: string,
    state: ThemeAwareState,
    callback?: (theme: ThemeType) => void,
    stateUpdater?: (newState: ThemeAwareState) => void
  ): Promise<void> {
    const themeManager = ThemeManager.getInstance();
    
    // 创建主题变化回调
    const themeChangeCallback = (theme: ThemeType) => {
      // 创建新的状态对象以触发响应式更新
      const newState = new ThemeAwareState();
      newState.updateTheme(theme);
      newState.setThemeTransitioning(true);
      
      // 如果提供了状态更新器，使用它来更新@State变量
      if (stateUpdater) {
        stateUpdater(newState);
      } else {
        // 兼容旧的方式，直接修改原对象（可能不会触发UI更新）
        state.setThemeTransitioning(true);
        state.updateTheme(theme);
      }
      
      // 执行自定义回调
      if (callback) {
        callback(theme);
      }
      
      // 延迟重置过渡状态
      setTimeout(() => {
        if (stateUpdater) {
          const finalState = new ThemeAwareState();
          finalState.updateTheme(theme);
          finalState.setThemeTransitioning(false);
          stateUpdater(finalState);
        } else {
          state.setThemeTransitioning(false);
        }
      }, 300);
    };

    // 注册回调
    ThemeAwareHelper.themeChangeCallbacks.set(componentId, themeChangeCallback);
    themeManager.onThemeChange(themeChangeCallback);

    // 初始化当前主题 - 使用实际显示的主题而不是配置值
    const actualTheme = await themeManager.getActualTheme();
    if (stateUpdater) {
      const initialState = new ThemeAwareState();
      initialState.updateTheme(actualTheme);
      stateUpdater(initialState);
    } else {
      state.updateTheme(actualTheme);
    }

    logger.debug('ThemeAwareHelper', `组件 ${componentId} 主题感知功能已初始化，实际主题: ${actualTheme}`);
  }

  /**
   * 清理主题感知功能
   */
  public static cleanupThemeAware(componentId: string): void {
    const callback = ThemeAwareHelper.themeChangeCallbacks.get(componentId);
    if (callback) {
      const themeManager = ThemeManager.getInstance();
      themeManager.offThemeChange(callback);
      ThemeAwareHelper.themeChangeCallbacks.delete(componentId);
      
      logger.debug('ThemeAwareHelper', `组件 ${componentId} 主题感知功能已清理`);
    }
  }

  /**
   * 获取主题相关的颜色资源
   */
  public static getThemedColor(
    lightColorKey: string,
    darkColorKey: string,
    theme: ThemeType
  ): Resource {
    return theme === ThemeType.LIGHT 
      ? $r(`app.color.${lightColorKey}`)
      : $r(`app.color.${darkColorKey}`);
  }

  /**
   * 获取测试管理页面的主题颜色
   */
  public static getTestManagementThemedColor(
    colorType: 'background' | 'text_primary' | 'text_secondary' | 'button_background' | 
              'panel_background' | 'panel_border' | 'accent_primary' | 'accent_primary_dimmed' |
              'button_primary' | 'button_secondary' | 'button_inactive' | 'divider' | 'text_white' | 
              'text_black' | 'text_muted' | 'accent_green' | 'button_danger' | 'brand' | 
              'button_success' | 'button_warning' | 'button_purple' | 'button_info' | 'border_light' | 
              'border_active' | 'text_placeholder' | 'background_darker' | 'panel_dark' | 
              'border_subtle' | 'row_even' | 'row_odd' | 'text_light' | 'background_secondary' | 
              'background_dark' | 'background_overlay' | 'comp_background_tertiary' | 
              'icon_primary' | 'font_secondary' | 'text_dim' | 'accent_blue' | 'accent_orange' | 
              'accent_secondary' | 'color_error' | 'color_success' | 'color_warning' | 
              'color_info' | 'color_neutral' | 'text_inverse' | 'background_inverse' | 
              'brand_secondary' | 'brand_tertiary' | 'background_primary' | 'shadow_black' |
              'border_dark' | 'brand_blue' | 'button_text_primary' | 'button_text_secondary' |
              'comp_background_primary' | 'comp_background_secondary' | 'success_border' | 'error_border' |
              'comp_border_primary' | 'success_text' | 'error_text' |
              'manga_detail_gradient_start' | 'manga_detail_gradient_mid' | 'manga_detail_gradient_end' |
              'comp_divider' | 'text_tertiary',
    theme: ThemeType
  ): Resource {
    // 颜色映射表，将通用颜色类型映射到具体的颜色资源名称
    const colorMapping: Record<string, GeneratedTypeLiteralInterface_1> = {
      // 背景颜色
      'background': { 
        light: 'test_management_background_primary_light', 
        dark: 'test_management_background_primary_dark' 
      },
      'background_primary': { 
        light: 'test_management_background_primary_light', 
        dark: 'test_management_background_primary_dark' 
      },
      'background_secondary': { 
        light: 'test_management_background_secondary_light', 
        dark: 'test_management_background_secondary_dark' 
      },
      'background_dark': { 
        light: 'test_management_background_dark_light', 
        dark: 'test_management_background_dark_dark' 
      },
      'background_overlay': { 
        light: 'test_management_background_overlay_light', 
        dark: 'test_management_background_overlay_dark' 
      },
      'background_darker': { 
        light: 'test_management_background_darker_light', 
        dark: 'test_management_background_darker_dark' 
      },
      'background_inverse': { 
        light: 'test_management_background_inverse_light', 
        dark: 'test_management_background_inverse_dark' 
      },

      // 漫画详情页：渐变颜色资源键（按主题）
      'manga_detail_gradient_start': {
        light: 'manga_detail_gradient_start_light',
        dark: 'manga_detail_gradient_start_dark'
      },
      'manga_detail_gradient_mid': {
        light: 'manga_detail_gradient_mid_light',
        dark: 'manga_detail_gradient_mid_dark'
      },
      'manga_detail_gradient_end': {
        light: 'manga_detail_gradient_end_light',
        dark: 'manga_detail_gradient_end_dark'
      },
      
      // 文字颜色
      'text_primary': { 
        light: 'test_management_text_primary_light', 
        dark: 'test_management_text_primary_dark' 
      },
      'text_secondary': { 
        light: 'test_management_font_secondary_light', 
        dark: 'test_management_font_secondary_dark' 
      },
      'text_white': { 
        light: 'test_management_text_white_light', 
        dark: 'test_management_text_white_dark' 
      },
      'button_background': { 
        light: 'test_management_button_background_light', 
        dark: 'test_management_button_background_dark' 
      },
      'button_text_primary': { 
        light: 'test_management_button_text_primary_light', 
        dark: 'test_management_button_text_primary_dark' 
      },
      'button_text_secondary': { 
        light: 'test_management_button_text_secondary_light', 
        dark: 'test_management_button_text_secondary_dark' 
      },
      'text_black': { 
        light: 'test_management_text_black_light', 
        dark: 'test_management_text_black_dark' 
      },
      'text_muted': { 
        light: 'test_management_text_muted_light', 
        dark: 'test_management_text_muted_dark' 
      },
      'text_light': { 
        light: 'test_management_text_light_light', 
        dark: 'test_management_text_light_dark' 
      },
      'text_dim': { 
        light: 'test_management_font_secondary_light', 
        dark: 'test_management_font_secondary_dark' 
      },
      'text_placeholder': { 
        light: 'test_management_text_placeholder_light', 
        dark: 'test_management_text_placeholder_dark' 
      },
      'text_inverse': { 
        light: 'test_management_text_inverse_light', 
        dark: 'test_management_text_inverse_dark' 
      },
      
      // 按钮颜色
      'button_primary': { 
        light: 'test_management_button_primary_light', 
        dark: 'test_management_button_primary_dark' 
      },
      'button_secondary': { 
        light: 'test_management_button_secondary_light', 
        dark: 'test_management_button_secondary_dark' 
      },
      'button_inactive': {
        light: 'test_management_button_inactive_light',
        dark: 'test_management_button_inactive_dark'
      },
      'button_danger': { 
        light: 'test_management_color_error_light', 
        dark: 'test_management_color_error_dark' 
      },
      'button_success': { 
        light: 'test_management_button_success_light', 
        dark: 'test_management_button_success_dark' 
      },
      'button_warning': { 
        light: 'test_management_button_warning_light', 
        dark: 'test_management_button_warning_dark' 
      },
      'button_purple': { 
        light: 'test_management_button_purple_light', 
        dark: 'test_management_button_purple_dark' 
      },
      'button_info': { 
        light: 'test_management_button_info_light', 
        dark: 'test_management_button_info_dark' 
      },
      
      // 面板颜色
      'panel_background': { 
        light: 'test_management_panel_background_light', 
        dark: 'test_management_comp_background_tertiary_dark' 
      },
      'panel_border': { 
        light: 'test_management_panel_border_light', 
        dark: 'test_management_border_light_dark' 
      },
      'panel_dark': { 
        light: 'test_management_panel_dark_light', 
        dark: 'test_management_panel_dark_dark' 
      },
      
      // 强调色
      'accent_primary': { 
        light: 'test_management_accent_primary_light', 
        dark: 'test_management_accent_primary_dark' 
      },
      'accent_primary_dimmed': { 
        light: 'test_management_accent_primary_dimmed_light', 
        dark: 'test_management_accent_primary_dimmed_dark' 
      },
      'accent_blue': { 
        light: 'test_management_accent_blue_light', 
        dark: 'test_management_accent_blue_dark' 
      },
      'accent_orange': { 
        light: 'test_management_accent_orange_light', 
        dark: 'test_management_accent_orange_dark' 
      },
      'accent_green': { 
        light: 'test_management_accent_green_light', 
        dark: 'test_management_accent_green_dark' 
      },
      'accent_secondary': { 
        light: 'test_management_accent_secondary_light', 
        dark: 'test_management_accent_secondary_dark' 
      },
      
      // 状态颜色
      'color_error': { 
        light: 'test_management_color_error_light', 
        dark: 'test_management_color_error_dark' 
      },
      'color_success': { 
        light: 'test_management_color_success_light', 
        dark: 'test_management_color_success_dark' 
      },
      'color_warning': { 
        light: 'test_management_color_warning_light', 
        dark: 'test_management_color_warning_dark' 
      },
      'color_info': { 
        light: 'test_management_color_info_light', 
        dark: 'test_management_color_info_dark' 
      },
      'color_neutral': { 
        light: 'test_management_color_neutral_light', 
        dark: 'test_management_color_neutral_dark' 
      },
      
      // 边框颜色
      'border_light': { 
        light: 'test_management_border_light_light', 
        dark: 'test_management_border_light_dark' 
      },
      'border_active': { 
        light: 'test_management_border_active_light', 
        dark: 'test_management_border_active_dark' 
      },
      'border_subtle': { 
        light: 'test_management_border_subtle_light', 
        dark: 'test_management_border_subtle_dark' 
      },
      'border_dark': { 
        light: 'test_management_border_dark_light', 
        dark: 'test_management_border_dark_dark' 
      },
      
      // 品牌颜色
      'brand': { 
        light: 'test_management_brand_light', 
        dark: 'test_management_brand_dark' 
      },
      'brand_blue': { 
        light: 'test_management_brand_blue_light', 
        dark: 'test_management_brand_blue_dark' 
      },
      'brand_secondary': { 
        light: 'test_management_brand_secondary_light', 
        dark: 'test_management_brand_secondary_dark' 
      },
      'brand_tertiary': { 
        light: 'test_management_brand_tertiary_light', 
        dark: 'test_management_brand_tertiary_dark' 
      },
      
      // 其他颜色
      'divider': { 
        light: 'test_management_divider_light', 
        dark: 'test_management_divider_dark' 
      },
      'shadow_black': { 
        light: 'test_management_shadow_black_light', 
        dark: 'test_management_shadow_black_dark' 
      },
      'row_even': { 
        light: 'test_management_row_even_light', 
        dark: 'test_management_row_even_dark' 
      },
      'row_odd': { 
        light: 'test_management_row_odd_light', 
        dark: 'test_management_row_odd_dark' 
      },
      'comp_background_tertiary': { 
        light: 'test_management_comp_background_tertiary_light', 
        dark: 'test_management_comp_background_tertiary_dark' 
      },
      'comp_background_secondary': { 
        light: 'test_management_comp_background_secondary_light', 
        dark: 'test_management_comp_background_secondary_dark' 
      },
      'comp_background_primary': { 
        light: 'test_management_comp_background_primary_light', 
        dark: 'test_management_comp_background_primary_dark' 
      },
      'icon_primary': { 
        light: 'test_management_icon_primary_light', 
        dark: 'test_management_icon_primary_dark' 
      },
      'font_secondary': { 
        light: 'test_management_font_secondary_light', 
        dark: 'test_management_font_secondary_dark' 
      },
      'comp_divider': { 
        light: 'test_management_divider_light', 
        dark: 'test_management_divider_dark' 
      },
      'text_tertiary': { 
        light: 'test_management_text_placeholder_light', 
        dark: 'test_management_text_placeholder_dark' 
      }
    };

    const mapping = colorMapping[colorType];
    if (!mapping) {
      logger.warn('ThemeAwareHelper', `未找到颜色类型 ${colorType} 的映射，使用默认颜色`);
      return theme === ThemeType.LIGHT ? $r('app.color.text_primary') : $r('app.color.text_secondary');
    }

    const colorName = theme === ThemeType.LIGHT ? mapping.light : mapping.dark;
    return $r(`app.color.${colorName}`);
  }

  /**
   * 获取主题过渡动画配置
   */
  public static getThemeTransitionAnimation(duration: number = 300): AnimateParam {
    return {
      duration: duration,
      curve: Curve.EaseInOut,
      iterations: 1,
      playMode: PlayMode.Normal
    };
  }

  /**
   * 创建主题感知的样式对象
   */
  public static createThemedStyle<T>(
    lightStyle: T,
    darkStyle: T,
    theme: ThemeType
  ): T {
    return theme === ThemeType.LIGHT ? lightStyle : darkStyle;
  }
}