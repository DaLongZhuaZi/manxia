// 文件路径: src/main/ets/Framework/Components/ThemeToggle.ets
/**
 * 主题切换组件
 * 提供主题切换的UI组件，可在多个页面中复用
 */

import { ThemeManager, ThemeType, THEME_CONFIGS } from '../Managers/ThemeManager';
import { logger } from 'manxia_core/src/main/ets/Utils/Logger';


// 主题切换组件状态
@Observed
export class ThemeToggleState {
  public currentTheme: ThemeType = ThemeType.DARK;
  public isAnimating: boolean = false;

  constructor() {
    this.currentTheme = ThemeManager.getInstance().getCurrentThemeSync();
  }
}

/**
 * 主题切换组件
 */
@Component
export struct ThemeToggle {
  @State private state: ThemeToggleState = new ThemeToggleState();
  @Prop showLabel: boolean = true; // 是否显示标签
  @Prop iconSize: number = 24; // 图标大小
  @Prop animationDuration: number = 300; // 动画持续时间
  private themeManager: ThemeManager = ThemeManager.getInstance();

  aboutToAppear(): void {
    // 监听主题变化
    this.themeManager.onThemeChange((theme: ThemeType) => {
      this.state.currentTheme = theme;
    });

    // 初始化当前主题
    this.state.currentTheme = this.themeManager.getCurrentThemeSync();
    logger.info('ThemeToggle', '主题切换组件初始化完成');
  }

  aboutToDisappear(): void {
    // 清理监听器
    this.themeManager.offThemeChange((theme: ThemeType) => {
      this.state.currentTheme = theme;
    });
  }

  /**
   * 处理主题切换
   */
  private async handleThemeToggle(): Promise<void> {
    if (this.state.isAnimating) {
      return;
    }

    try {
      this.state.isAnimating = true;
      await this.themeManager.toggleTheme();
      
      // 动画延迟
      setTimeout(() => {
        this.state.isAnimating = false;
      }, this.animationDuration);

      logger.info('ThemeToggle', `主题已切换到: ${this.state.currentTheme}`);
    } catch (error) {
      this.state.isAnimating = false;
      logger.error('ThemeToggle', '主题切换失败', error);
    }
  }

  /**
   * 获取当前主题图标
   */
  private getThemeIcon(): Resource {
    switch (this.state.currentTheme) {
      case ThemeType.LIGHT:
        return $r('app.media.SculptureLargeAnimalistA');   // 浅色模式图标
      case ThemeType.DARK:
        return $r('app.media.SculptureLargeAnimalistA');   // 深色模式图标
      case ThemeType.AUTO:
      default:
        return $r('app.media.SculptureLargeAnimalistA');   // 自动模式图标
    }
  }

  /**
   * 获取当前主题描述
   */
  private getThemeDescription(): string {
    return THEME_CONFIGS[this.state.currentTheme].name;
  }

  /**
   * 获取主题颜色
   */
  private getThemedColor(
    colorType: 'background' | 'text_primary' | 'text_secondary' | 'button_background' | 
              'panel_background' | 'panel_border' | 'accent_primary' | 'button_primary' |
              'button_secondary' | 'button_inactive' | 'divider' | 'text_white' | 'text_black' | 
              'text_muted' | 'accent_green' | 'button_danger' | 'brand' | 'button_success' | 
              'button_warning' | 'button_purple' | 'button_info' | 'button_primary' | 
              'border_light' | 'border_active' | 'text_placeholder' | 'background_darker' | 
              'panel_dark' | 'border_subtle' | 'row_even' | 'row_odd' | 'text_light' | 
              'background_secondary' | 'background_dark' | 'background_overlay' | 
              'comp_background_tertiary' | 'icon_primary' | 'font_secondary' | 'text_dim' | 
              'accent_blue' | 'accent_orange' | 'accent_secondary' | 'button_primary' | 
              'button_secondary' | 'color_error' | 'color_success' | 'color_warning' | 
              'color_info' | 'color_neutral' | 'text_inverse' | 'background_inverse' | 
              'brand_secondary' | 'brand_tertiary'
  ): Resource {
    // AUTO模式下，根据实际主题来选择颜色；其他模式直接使用当前主题
    let effectiveTheme = this.state.currentTheme;
    if (this.state.currentTheme === ThemeType.AUTO) {
      // AUTO模式下，需要获取实际的系统主题
      effectiveTheme = this.themeManager.getActualThemeSync();
    }
    
    const suffix = effectiveTheme === ThemeType.LIGHT ? '_light' : '_dark';
    return $r(`app.color.test_management_${colorType}${suffix}`);
  }

  build() {
    Row() {
      // 主题图标按钮
      Button() {
        Image(this.getThemeIcon())
          .width(this.iconSize)
          .height(this.iconSize)
          .fillColor(this.getThemedColor('text_primary'))
          .rotate({
            angle: this.state.isAnimating ? 180 : 0
          })
          .animation({
            duration: this.animationDuration,
            curve: Curve.EaseInOut
          })
      }
      .type(ButtonType.Circle)
      .width(this.iconSize + 16)
      .height(this.iconSize + 16)
      .backgroundColor(this.getThemedColor('button_background'))
      .onClick(() => this.handleThemeToggle())
      .enabled(!this.state.isAnimating)
      .opacity(this.state.isAnimating ? 0.6 : 1.0)
      .animation({
        duration: 200,
        curve: Curve.EaseInOut
      })

      // 主题标签（可选）
      if (this.showLabel) {
        Text(this.getThemeDescription())
          .fontSize(14)
          .fontColor(this.getThemedColor('text_secondary'))
          .margin({ left: 8 })
          .opacity(this.state.isAnimating ? 0.6 : 1.0)
          .animation({
            duration: 200,
            curve: Curve.EaseInOut
          })
      }
    }
    .alignItems(VerticalAlign.Center)
  }
}

/**
 * 紧凑型主题切换组件（仅图标）
 */
@Component
export struct CompactThemeToggle {
  @Prop iconSize: number = 20;
  
  build() {
    ThemeToggle({
      showLabel: false,
      iconSize: this.iconSize
    })
  }
}

/**
 * 带标签的主题切换组件
 */
@Component
export struct LabeledThemeToggle {
  @Prop iconSize: number = 24;
  
  build() {
    ThemeToggle({
      showLabel: true,
      iconSize: this.iconSize
    })
  }
}