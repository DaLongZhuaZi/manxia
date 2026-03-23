// 文件路径: entry/src/main/ets/Framework/Components/AppGuideOverlay.ets
/**
 * 应用统一引导遮罩
 * 提供全屏遮罩、局部高亮和步骤说明卡片
 */

import { ThemeAwareHelper, ThemeAwareState } from './ThemeAware';

export interface GuideHighlightRect {
  x: number;
  y: number;
  width: number;
  height: number;
  borderRadius?: number;
}

@Component
export struct AppGuideOverlay {
  @Prop @Watch('handleVisibleChanged') visible: boolean = false;
  @Prop title: string = '功能引导';
  @Prop message: string = '';
  @Prop progressText: string = '';
  @Prop nextButtonText: string = '下一步';
  @Prop skipButtonText: string = '跳过';
  @Prop cardPosition: 'top' | 'bottom' | 'center' = 'center';
  @Prop highlightRect?: GuideHighlightRect | null;
  @Prop showSkip: boolean = true;
  @Prop themeState?: ThemeAwareState;
  onNext?: () => void;
  onSkip?: () => void;

  @StorageLink('appFontFamily') appFontFamily: string = 'HarmonyOS Sans';
  @State private overlayOpacity: number = 0;
  @State private cardOpacity: number = 0;
  @State private cardScale: number = 0.92;
  @State private screenWidth: number = 0;
  @State private screenHeight: number = 0;
  private uiContext: UIContext | null = null;

  aboutToAppear(): void {
    this.uiContext = this.getUIContext();
    if (this.visible) {
      this.playEnterAnimation();
    }
  }

  handleVisibleChanged(): void {
    if (this.visible) {
      this.playEnterAnimation();
      return;
    }
    this.playExitAnimation();
  }

  private playEnterAnimation(): void {
    if (!this.uiContext) {
      this.uiContext = this.getUIContext();
    }
    if (!this.uiContext) {
      return;
    }

    this.uiContext.animateTo({ duration: 220, curve: Curve.EaseOut }, () => {
      this.overlayOpacity = 1;
    });
    this.uiContext.animateTo({ duration: 260, curve: Curve.Friction }, () => {
      this.cardOpacity = 1;
      this.cardScale = 1;
    });
  }

  private playExitAnimation(): void {
    if (!this.uiContext) {
      this.uiContext = this.getUIContext();
    }
    if (!this.uiContext) {
      return;
    }

    this.uiContext.animateTo({ duration: 160, curve: Curve.EaseIn }, () => {
      this.overlayOpacity = 0;
      this.cardOpacity = 0;
      this.cardScale = 0.95;
    });
  }

  private getThemeState(): ThemeAwareState {
    return this.themeState ?? new ThemeAwareState();
  }

  private getCardTop(): number {
    if (!this.highlightRect || this.screenHeight <= 0) {
      return Math.max(96, (this.screenHeight - 220) / 2);
    }
    const cardHeight = 220;
    const margin = 18;
    if (this.cardPosition === 'top') {
      return Math.max(72, this.highlightRect.y - cardHeight - margin);
    }
    if (this.cardPosition === 'bottom') {
      return Math.min(this.screenHeight - cardHeight - 32, this.highlightRect.y + this.highlightRect.height + margin);
    }
    return Math.max(96, (this.screenHeight - cardHeight) / 2);
  }

  private getCardLeft(): number {
    if (!this.highlightRect || this.screenWidth <= 0) {
      return 20;
    }
    const cardWidth = Math.min(this.screenWidth - 40, 320);
    const centered = this.highlightRect.x + this.highlightRect.width / 2 - cardWidth / 2;
    return Math.max(20, Math.min(this.screenWidth - cardWidth - 20, centered));
  }

  private shouldUseHighlightMask(): boolean {
    return !!this.highlightRect && this.screenWidth > 0 && this.screenHeight > 0;
  }

  private hasHighlight(): boolean {
    return !!this.highlightRect;
  }

  private getHighlightX(): number {
    return this.highlightRect ? this.highlightRect.x : 0;
  }

  private getHighlightY(): number {
    return this.highlightRect ? this.highlightRect.y : 0;
  }

  private getHighlightWidth(): number {
    return this.highlightRect ? this.highlightRect.width : 0;
  }

  private getHighlightHeight(): number {
    return this.highlightRect ? this.highlightRect.height : 0;
  }

  private getHighlightRight(): number {
    return this.getHighlightX() + this.getHighlightWidth();
  }

  private getHighlightBottom(): number {
    return this.getHighlightY() + this.getHighlightHeight();
  }

  private getHighlightBorderRadius(): number {
    return this.highlightRect?.borderRadius ?? 16;
  }

  private shouldRenderOverlay(): boolean {
    return this.visible || this.overlayOpacity > 0 || this.cardOpacity > 0;
  }

  @Builder
  private buildMask(): void {
    if (!this.shouldUseHighlightMask()) {
      Column()
        .width('100%')
        .height('100%')
        .backgroundColor('rgba(8, 14, 28, 0.72)')
        .opacity(this.overlayOpacity)
    } else {
      Column()
        .width(this.screenWidth)
        .height(Math.max(0, this.getHighlightY()))
        .backgroundColor('rgba(8, 14, 28, 0.72)')
        .position({ x: 0, y: 0 })
        .opacity(this.overlayOpacity)
      Column()
        .width(this.screenWidth)
        .height(Math.max(0, this.screenHeight - this.getHighlightBottom()))
        .backgroundColor('rgba(8, 14, 28, 0.72)')
        .position({ x: 0, y: this.getHighlightBottom() })
        .opacity(this.overlayOpacity)
      Column()
        .width(Math.max(0, this.getHighlightX()))
        .height(this.getHighlightHeight())
        .backgroundColor('rgba(8, 14, 28, 0.72)')
        .position({ x: 0, y: this.getHighlightY() })
        .opacity(this.overlayOpacity)
      Column()
        .width(Math.max(0, this.screenWidth - this.getHighlightRight()))
        .height(this.getHighlightHeight())
        .backgroundColor('rgba(8, 14, 28, 0.72)')
        .position({ x: this.getHighlightRight(), y: this.getHighlightY() })
        .opacity(this.overlayOpacity)
    }
  }

  @Builder
  private buildHighlight(): void {
    if (this.hasHighlight()) {
      Stack() {
        Column()
          .width(this.getHighlightWidth() + 10)
          .height(this.getHighlightHeight() + 10)
          .borderRadius(this.getHighlightBorderRadius() + 5)
          .border({
            width: 2,
            color: ThemeAwareHelper.getTestManagementThemedColor('accent_primary', this.getThemeState().currentTheme)
          })
          .opacity(0.68)

        Column()
          .width(this.getHighlightWidth())
          .height(this.getHighlightHeight())
          .borderRadius(this.getHighlightBorderRadius())
          .border({
            width: 2,
            color: Color.White
          })
          .shadow({
            radius: 18,
            color: 'rgba(255, 255, 255, 0.26)',
            offsetX: 0,
            offsetY: 0
          })
      }
      .position({
        x: Math.max(0, this.getHighlightX() - 5),
        y: Math.max(0, this.getHighlightY() - 5)
      })
    }
  }

  @Builder
  private buildCard(): void {
    Column({ space: 14 }) {
      if (this.progressText.length > 0) {
        Text(this.progressText)
          .fontSize(11)
          .fontFamily(this.appFontFamily)
          .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_muted', this.getThemeState().currentTheme))
          .width('100%')
      }

      Text(this.title)
        .fontSize(18)
        .fontFamily(this.appFontFamily)
        .fontWeight(FontWeight.Bold)
        .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_primary', this.getThemeState().currentTheme))
        .width('100%')

      Text(this.message)
        .fontSize(14)
        .fontFamily(this.appFontFamily)
        .lineHeight(22)
        .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_secondary', this.getThemeState().currentTheme))
        .width('100%')

      Row({ space: 10 }) {
        if (this.showSkip) {
          Button(this.skipButtonText)
            .layoutWeight(1)
            .height(38)
            .fontSize(14)
            .fontFamily(this.appFontFamily)
            .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_secondary', this.getThemeState().currentTheme))
            .backgroundColor(ThemeAwareHelper.getTestManagementThemedColor('button_inactive', this.getThemeState().currentTheme))
            .borderRadius(12)
            .onClick(() => {
              this.onSkip?.();
            })
        }

        Button(this.nextButtonText)
          .layoutWeight(1)
          .height(38)
          .fontSize(14)
          .fontFamily(this.appFontFamily)
          .fontColor(Color.White)
          .backgroundColor(ThemeAwareHelper.getTestManagementThemedColor('accent_primary', this.getThemeState().currentTheme))
          .borderRadius(12)
          .onClick(() => {
            this.onNext?.();
          })
      }
      .width('100%')
    }
    .width(Math.min(Math.max(this.screenWidth - 40, 280), 320))
    .padding(18)
    .backgroundColor(ThemeAwareHelper.getTestManagementThemedColor('panel_background', this.getThemeState().currentTheme))
    .borderRadius(18)
    .border({
      width: 1,
      color: ThemeAwareHelper.getTestManagementThemedColor('panel_border', this.getThemeState().currentTheme)
    })
    .shadow({
      radius: 18,
      color: 'rgba(0, 0, 0, 0.28)',
      offsetX: 0,
      offsetY: 8
    })
    .position({
      x: this.getCardLeft(),
      y: this.getCardTop()
    })
    .opacity(this.cardOpacity)
    .scale({ x: this.cardScale, y: this.cardScale })
  }

  build() {
    if (this.shouldRenderOverlay()) {
      Stack() {
        this.buildMask()
        this.buildHighlight()
        this.buildCard()
      }
      .width('100%')
      .height('100%')
      .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.TOP, SafeAreaEdge.BOTTOM, SafeAreaEdge.START, SafeAreaEdge.END])
      .onAreaChange((_oldValue: Area, newValue: Area) => {
        this.screenWidth = Number(newValue.width);
        this.screenHeight = Number(newValue.height);
      })
      .zIndex(99997)
    }
  }
}
