// 文件路径: entry/src/main/ets/Framework/Components/GuideOverlay.ets
/**
 * 引导提示遮罩组件
 * 用于在页面上高亮显示特定区域并提供引导提示
 */

import { logger } from '../../Utils/Logger';
import { ThemeAwareHelper, ThemeAwareState } from './ThemeAware';
import { FontAwareHelper, FontAwareState } from './FontAware';
// 已弃用自定义 AnimatedButton，改用原生 ArkUI Button

const TAG = 'GuideOverlay';

/**
 * 高亮区域配置接口
 */
export interface HighlightArea {
  x: number;
  y: number;
  width: number;
  height: number;
  borderRadius?: number;
}

/**
 * 引导提示配置接口
 */
export interface GuideTip {
  title: string;
  message: string;
  position: 'top' | 'bottom' | 'left' | 'right' | 'center';
  offsetX?: number;
  offsetY?: number;
}

/**
 * 引导遮罩组件参数接口
 */
export interface GuideOverlayParams {
  visible: boolean;
  highlightArea?: HighlightArea;
  tip: GuideTip;
  showNextButton?: boolean;
  showSkipButton?: boolean;
  nextButtonText?: string;
  skipButtonText?: string;
  onNext?: () => void;
  onSkip?: () => void;
  onDismiss?: () => void;
  themeState?: ThemeAwareState;
}

/**
 * 引导遮罩组件
 */
@Component
export struct GuideOverlay {
  @Prop visible: boolean = false;
  @Prop highlightArea?: HighlightArea;
  @Prop tip: GuideTip = {
    title: '引导提示',
    message: '这是一个引导提示',
    position: 'center'
  };
  @Prop showNextButton: boolean = true;
  @Prop showSkipButton: boolean = true;
  @Prop nextButtonText: string = '下一步';
  @Prop skipButtonText: string = '跳过';
  @Prop showLogToggle: boolean = false;
  // 回调函数不能使用@Prop装饰器
  onNext?: () => void;
  onSkip?: () => void;
  onDismiss?: () => void;
  @Prop themeState?: ThemeAwareState;
  @StorageLink('appFontFamily') appFontFamily: string = 'HarmonyOS Sans';

  @State private overlayOpacity: number = 0;
  @State private tipOpacity: number = 0;
  @State private tipScale: number = 0.8;
  @State private enableLogFloatingWindow: boolean = false;

  private uiContext: UIContext | undefined = undefined;

  aboutToAppear(): void {
    this.uiContext = this.getUIContext();
    const saved = AppStorage.get<boolean>('enable_log_floating_window');
    if (saved !== undefined) {
      this.enableLogFloatingWindow = saved;
    }
    if (this.visible) {
      this.startEntranceAnimation();
    }
  }

  /**
   * 监听visible变化
   */
  @Watch('onVisibleChange')
  onVisibleChange(): void {
    if (this.visible) {
      this.startEntranceAnimation();
    } else {
      this.startExitAnimation();
    }
  }

  /**
   * 启动入场动画
   */
  private startEntranceAnimation(): void {
    if (!this.uiContext) return;

    const animateOptions: AnimateParam = {
      duration: 300,
      curve: Curve.EaseOut,
      iterations: 1,
      playMode: PlayMode.Normal
    };

    this.uiContext.animateTo(animateOptions, () => {
      this.overlayOpacity = 1;
    });

    setTimeout(() => {
      if (!this.uiContext) return;

      const tipAnimateOptions: AnimateParam = {
        duration: 400,
        curve: Curve.EaseOut,
        iterations: 1,
        playMode: PlayMode.Normal
      };

      this.uiContext.animateTo(tipAnimateOptions, () => {
        this.tipOpacity = 1;
        this.tipScale = 1;
      });
    }, 200);
  }

  /**
   * 启动退出动画
   */
  private startExitAnimation(): void {
    if (!this.uiContext) return;

    const animateOptions: AnimateParam = {
      duration: 200,
      curve: Curve.EaseIn,
      iterations: 1,
      playMode: PlayMode.Normal
    };

    this.uiContext.animateTo(animateOptions, () => {
      this.overlayOpacity = 0;
      this.tipOpacity = 0;
      this.tipScale = 0.8;
    });
  }

  /**
   * 处理下一步按钮点击
   */
  private handleNext(): void {
    logger.info(TAG, '点击下一步');
    if (this.onNext) {
      this.onNext();
    }
  }

  /**
   * 处理跳过按钮点击
   */
  private handleSkip(): void {
    logger.info(TAG, '点击跳过');
    if (this.onSkip) {
      this.onSkip();
    }
  }

  /**
   * 处理遮罩点击（关闭）
   */
  private handleDismiss(): void {
    logger.info(TAG, '点击遮罩关闭');
    if (this.onDismiss) {
      this.onDismiss();
    }
  }

  /**
   * 获取提示框位置
   */
  private getTipPosition(): { x: string | number, y: string | number } {
    if (!this.highlightArea) {
      return { x: '50%', y: '50%' };
    }

    const offsetX = this.tip.offsetX ?? 0;
    const offsetY = this.tip.offsetY ?? 0;

    switch (this.tip.position) {
      case 'top':
        return {
          x: this.highlightArea.x + this.highlightArea.width / 2 + offsetX,
          y: this.highlightArea.y - 20 + offsetY
        };
      case 'bottom':
        return {
          x: this.highlightArea.x + this.highlightArea.width / 2 + offsetX,
          y: this.highlightArea.y + this.highlightArea.height + 20 + offsetY
        };
      case 'left':
        return {
          x: this.highlightArea.x - 20 + offsetX,
          y: this.highlightArea.y + this.highlightArea.height / 2 + offsetY
        };
      case 'right':
        return {
          x: this.highlightArea.x + this.highlightArea.width + 20 + offsetX,
          y: this.highlightArea.y + this.highlightArea.height / 2 + offsetY
        };
      case 'center':
      default:
        return { x: '50%', y: '50%' };
    }
  }

  /**
   * 获取当前主题状态
   */
  private getCurrentThemeState(): ThemeAwareState {
    return this.themeState ?? new ThemeAwareState();
  }

  /**
   * 构建高亮区域
   */
  @Builder
  buildHighlightArea() {
    if (this.highlightArea) {
      Column()
        .width(this.highlightArea.width)
        .height(this.highlightArea.height)
        .position({ x: this.highlightArea.x, y: this.highlightArea.y })
        .borderRadius(this.highlightArea.borderRadius ?? 8)
        .border({
          width: 2,
          color: ThemeAwareHelper.getTestManagementThemedColor('accent_blue', this.getCurrentThemeState().currentTheme),
          style: BorderStyle.Solid
        })
        .backgroundColor(Color.Transparent)
        .shadow({
          radius: 12,
          color: ThemeAwareHelper.getTestManagementThemedColor('accent_blue', this.getCurrentThemeState().currentTheme),
          offsetX: 0,
          offsetY: 0
        })
    }
  }

  /**
   * 构建提示卡片
   */
  @Builder
  buildTipCard() {
    const position = this.getTipPosition();
    
    Column({ space: 16 }) {
      // 标题
      Text(this.tip.title)
        .fontSize(18)
        .fontFamily(this.appFontFamily)
        .fontWeight(FontWeight.Bold)
        .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_primary', this.getCurrentThemeState().currentTheme))

      // 消息
      Text(this.tip.message)
        .fontSize(14)
        .fontFamily(this.appFontFamily)
        .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_secondary', this.getCurrentThemeState().currentTheme))
        .lineHeight(22)

      if (this.showLogToggle) {
        Row() {
          Text('启用日志悬浮窗口')
            .fontSize(14)
            .fontFamily(this.appFontFamily)
            .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_primary', this.getCurrentThemeState().currentTheme))
          Toggle({ type: ToggleType.Switch, isOn: this.enableLogFloatingWindow })
            .selectedColor(ThemeAwareHelper.getTestManagementThemedColor('accent_blue', this.getCurrentThemeState().currentTheme))
            .onChange((isOn: boolean) => {
              this.enableLogFloatingWindow = isOn;
              AppStorage.setOrCreate('enable_log_floating_window', this.enableLogFloatingWindow);
            })
        }
        .width('100%')
        .justifyContent(FlexAlign.SpaceBetween)
      }

      // 按钮组
      Row({ space: 12 }) {
        if (this.showSkipButton) {
          Button({ stateEffect: true }) {
            Text(this.skipButtonText)
              .fontSize(14)
              .fontFamily(this.appFontFamily)
              .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_secondary', this.getCurrentThemeState().currentTheme))
          }
            .height(36)
            .width(80)
            .backgroundColor(ThemeAwareHelper.getTestManagementThemedColor('button_inactive', this.getCurrentThemeState().currentTheme))
            .borderRadius(18)
            .onClick(() => {
              this.handleSkip();
            })
        }

        if (this.showNextButton) {
          Button({ stateEffect: true }) {
            Text(this.nextButtonText)
              .fontSize(14)
              .fontFamily(this.appFontFamily)
              .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_white', this.getCurrentThemeState().currentTheme))
          }
            .height(36)
            .width(80)
            .backgroundColor(ThemeAwareHelper.getTestManagementThemedColor('accent_blue', this.getCurrentThemeState().currentTheme))
            .borderRadius(18)
            .onClick(() => {
              this.handleNext();
            })
        }
      }
      .justifyContent(FlexAlign.End)
      .width('100%')
    }
    .padding(20)
    .backgroundColor(ThemeAwareHelper.getTestManagementThemedColor('panel_background', this.getCurrentThemeState().currentTheme))
    .borderRadius(12)
    .shadow({
      radius: 20,
      color: '#33000000',
      offsetX: 0,
      offsetY: 4
    })
    .width('80%')
    .maxWidth(320)
    .position(position)
    .opacity(this.tipOpacity)
    .scale({ x: this.tipScale, y: this.tipScale })
  }

  build() {
    if (this.visible) {
      Stack() {
        // 半透明遮罩层
        Column()
          .width('100%')
          .height('100%')
          .backgroundColor('#CC000000')
          .opacity(this.overlayOpacity)
          .onClick(() => {
            // 点击遮罩层时可选择关闭
            // this.handleDismiss();
          })

        // 高亮区域（镂空效果）
        this.buildHighlightArea()

        // 提示卡片
        this.buildTipCard()
      }
      .width('100%')
      .height('100%')
      .position({ x: 0, y: 0 })
    }
  }
}

