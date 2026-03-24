// 文件路径: entry/src/main/ets/Framework/Components/AppGuideOverlay.ets
/**
 * 应用统一引导遮罩
 * 提供全屏遮罩、局部高亮和步骤说明卡片
 */

import { ThemeAwareHelper, ThemeAwareState } from './ThemeAware';
import { ThemeType } from '../Managers/ThemeManager';

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
  @Prop highlightVerticalOffsetRatio: number = 0;
  @Prop immersiveMode: boolean = false;
  @Prop showSkip: boolean = true;
  @Prop themeState?: ThemeAwareState;
  onNext?: () => void;
  onSkip?: () => void;

  @StorageLink('appFontFamily') appFontFamily: string = 'HarmonyOS Sans';
  @StorageProp('navigationBarHeight') navigationBarHeight: number = 0;
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

  private getMaskColor(): string {
    return this.getThemeState().currentTheme === ThemeType.DARK
      ? 'rgba(3, 8, 18, 0.54)'
      : 'rgba(6, 14, 28, 0.38)';
  }

  private getCardBackgroundColor(): string {
    return this.getThemeState().currentTheme === ThemeType.DARK
      ? 'rgba(20, 26, 38, 0.96)'
      : 'rgba(252, 253, 255, 0.97)';
  }

  private getCardBorderColor(): string {
    return this.getThemeState().currentTheme === ThemeType.DARK
      ? 'rgba(255, 255, 255, 0.12)'
      : 'rgba(15, 23, 42, 0.08)';
  }

  private getSecondaryButtonBackgroundColor(): string {
    return this.getThemeState().currentTheme === ThemeType.DARK
      ? 'rgba(255, 255, 255, 0.08)'
      : 'rgba(15, 23, 42, 0.08)';
  }

  private getMaskBlurOptions(): BackgroundBlurStyleOptions {
    return {
      colorMode: ThemeColorMode.SYSTEM,
      adaptiveColor: AdaptiveColor.DEFAULT,
      scale: 0.18
    };
  }

  private getCardBlurOptions(): BackgroundBlurStyleOptions {
    return {
      colorMode: ThemeColorMode.SYSTEM,
      adaptiveColor: AdaptiveColor.DEFAULT,
      scale: 1.0
    };
  }

  private isHighlightGeometryUsable(): boolean {
    if (!this.highlightRect || this.screenWidth <= 0 || this.screenHeight <= 0) {
      return false;
    }
    const width = Math.max(0, this.highlightRect.width);
    const height = Math.max(0, this.highlightRect.height);
    if (width < 8 || height < 8) {
      return false;
    }
    const right = this.highlightRect.x + width;
    const bottom = this.highlightRect.y + height;
    return right > 0 && bottom > 0 && this.highlightRect.x < this.screenWidth && this.highlightRect.y < this.screenHeight;
  }

  private getCardWidth(): number {
    return Math.min(Math.max(this.screenWidth - 40, 280), 320);
  }

  private getCardHeight(): number {
    return this.progressText.length > 0 ? 236 : 220;
  }

  private getCardSafeTop(): number {
    return 24;
  }

  private getCardSafeBottom(): number {
    if (this.immersiveMode) {
      return 24;
    }
    return Math.max(24, this.navigationBarHeight + 24);
  }

  private clampCardTop(candidateTop: number, cardHeight: number): number {
    const minTop = this.getCardSafeTop();
    const maxTop = Math.max(minTop, this.screenHeight - cardHeight - this.getCardSafeBottom());
    return Math.max(minTop, Math.min(maxTop, candidateTop));
  }

  private getCardTop(): number {
    const cardHeight = this.getCardHeight();
    if (!this.isHighlightGeometryUsable() || this.screenHeight <= 0) {
      return this.clampCardTop((this.screenHeight - cardHeight) / 2, cardHeight);
    }
    const margin = 18;
    const highlightY = this.getHighlightY();
    const highlightBottom = this.getHighlightBottom();
    const highlightHeight = this.getHighlightHeight();
    const topCandidate = highlightY - cardHeight - margin;
    const bottomCandidate = highlightBottom + margin;
    const minTop = this.getCardSafeTop();
    const maxTop = Math.max(minTop, this.screenHeight - cardHeight - this.getCardSafeBottom());
    const topFits = topCandidate >= minTop;
    const bottomFits = bottomCandidate <= maxTop;
    if (this.cardPosition === 'top') {
      if (topFits) {
        return this.clampCardTop(topCandidate, cardHeight);
      }
      if (bottomFits) {
        return this.clampCardTop(bottomCandidate, cardHeight);
      }
    }
    if (this.cardPosition === 'bottom') {
      if (bottomFits) {
        return this.clampCardTop(bottomCandidate, cardHeight);
      }
      if (topFits) {
        return this.clampCardTop(topCandidate, cardHeight);
      }
    }
    const centered = this.clampCardTop((this.screenHeight - cardHeight) / 2, cardHeight);
    const centeredBottom = centered + cardHeight;
    if (centeredBottom <= highlightY - margin || centered >= highlightBottom + margin) {
      return centered;
    }
    if (bottomFits) {
      return this.clampCardTop(bottomCandidate, cardHeight);
    }
    if (topFits) {
      return this.clampCardTop(topCandidate, cardHeight);
    }
    return this.clampCardTop(highlightY + highlightHeight + margin, cardHeight);
  }

  private getCardLeft(): number {
    if (!this.isHighlightGeometryUsable() || this.screenWidth <= 0) {
      return Math.max(20, (this.screenWidth - this.getCardWidth()) / 2);
    }
    const cardWidth = this.getCardWidth();
    const centered = this.getHighlightX() + this.getHighlightWidth() / 2 - cardWidth / 2;
    return Math.max(20, Math.min(this.screenWidth - cardWidth - 20, centered));
  }

  private shouldUseHighlightMask(): boolean {
    return this.isHighlightGeometryUsable();
  }

  private getHighlightVerticalOffset(): number {
    if (this.immersiveMode) {
      return 0;
    }
    return Math.max(0, this.navigationBarHeight * Math.max(0, this.highlightVerticalOffsetRatio));
  }

  private hasHighlight(): boolean {
    return this.isHighlightGeometryUsable();
  }

  private getHighlightX(): number {
    if (!this.isHighlightGeometryUsable() || !this.highlightRect) {
      return 0;
    }
    return Math.max(0, Math.min(this.screenWidth, this.highlightRect.x));
  }

  private getHighlightY(): number {
    if (!this.isHighlightGeometryUsable() || !this.highlightRect) {
      return 0;
    }
    return Math.max(0, Math.min(this.screenHeight, this.highlightRect.y - this.getHighlightVerticalOffset()));
  }

  private getHighlightWidth(): number {
    if (!this.isHighlightGeometryUsable() || !this.highlightRect) {
      return 0;
    }
    return Math.max(0, Math.min(this.highlightRect.width, this.screenWidth - this.getHighlightX()));
  }

  private getHighlightHeight(): number {
    if (!this.isHighlightGeometryUsable() || !this.highlightRect) {
      return 0;
    }
    return Math.max(0, Math.min(this.highlightRect.height, this.screenHeight - this.getHighlightY()));
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

  private getHighlightFramePadding(): number {
    return 4;
  }

  private getHighlightFrameX(): number {
    return Math.max(0, this.getHighlightX() - this.getHighlightFramePadding());
  }

  private getHighlightFrameY(): number {
    return Math.max(0, this.getHighlightY() - this.getHighlightFramePadding());
  }

  private getHighlightFrameWidth(): number {
    return Math.max(0, Math.min(this.screenWidth - this.getHighlightFrameX(),
      this.getHighlightWidth() + this.getHighlightFramePadding() * 2));
  }

  private getHighlightFrameHeight(): number {
    return Math.max(0, Math.min(this.screenHeight - this.getHighlightFrameY(),
      this.getHighlightHeight() + this.getHighlightFramePadding() * 2));
  }

  private getHighlightFrameBorderRadius(): number {
    return this.getHighlightBorderRadius() + this.getHighlightFramePadding();
  }

  private getHighlightFillColor(): string {
    return this.getThemeState().currentTheme === ThemeType.DARK
      ? 'rgba(255, 255, 255, 0.10)'
      : 'rgba(255, 255, 255, 0.18)';
  }

  private getHighlightBorderColor(): Resource {
    return ThemeAwareHelper.getTestManagementThemedColor('accent_primary', this.getThemeState().currentTheme);
  }

  private getHighlightOuterGlowColor(): string {
    return this.getThemeState().currentTheme === ThemeType.DARK
      ? 'rgba(96, 165, 250, 0.26)'
      : 'rgba(59, 130, 246, 0.20)';
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
        .backgroundColor(this.getMaskColor())
        .backgroundBlurStyle(BlurStyle.BACKGROUND_THIN, this.getMaskBlurOptions())
        .opacity(this.overlayOpacity)
    } else {
      Column()
        .width(this.screenWidth)
        .height(Math.max(0, this.getHighlightY()))
        .backgroundColor(this.getMaskColor())
        .backgroundBlurStyle(BlurStyle.BACKGROUND_THIN, this.getMaskBlurOptions())
        .position({ x: 0, y: 0 })
        .opacity(this.overlayOpacity)
      Column()
        .width(this.screenWidth)
        .height(Math.max(0, this.screenHeight - this.getHighlightBottom()))
        .backgroundColor(this.getMaskColor())
        .backgroundBlurStyle(BlurStyle.BACKGROUND_THIN, this.getMaskBlurOptions())
        .position({ x: 0, y: this.getHighlightBottom() })
        .opacity(this.overlayOpacity)
      Column()
        .width(Math.max(0, this.getHighlightX()))
        .height(this.getHighlightHeight())
        .backgroundColor(this.getMaskColor())
        .backgroundBlurStyle(BlurStyle.BACKGROUND_THIN, this.getMaskBlurOptions())
        .position({ x: 0, y: this.getHighlightY() })
        .opacity(this.overlayOpacity)
      Column()
        .width(Math.max(0, this.screenWidth - this.getHighlightRight()))
        .height(this.getHighlightHeight())
        .backgroundColor(this.getMaskColor())
        .backgroundBlurStyle(BlurStyle.BACKGROUND_THIN, this.getMaskBlurOptions())
        .position({ x: this.getHighlightRight(), y: this.getHighlightY() })
        .opacity(this.overlayOpacity)
    }
  }

  @Builder
  private buildHighlight(): void {
    if (this.hasHighlight()) {
      Stack() {
        Column()
          .width(this.getHighlightWidth())
          .height(this.getHighlightHeight())
          .borderRadius(this.getHighlightBorderRadius())
          .clip(true)
          .backgroundColor(this.getHighlightFillColor())

        Column()
          .width(this.getHighlightFrameWidth())
          .height(this.getHighlightFrameHeight())
          .borderRadius(this.getHighlightFrameBorderRadius())
          .border({
            width: 2,
            color: this.getHighlightBorderColor()
          })
          .shadow({
            radius: 18,
            color: this.getHighlightOuterGlowColor(),
            offsetX: 0,
            offsetY: 0
          })
      }
      .position({
        x: this.getHighlightFrameX(),
        y: this.getHighlightFrameY()
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
            .backgroundColor(this.getSecondaryButtonBackgroundColor())
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
    .width(this.getCardWidth())
    .padding(18)
    .backgroundColor(this.getCardBackgroundColor())
    .backgroundBlurStyle(BlurStyle.BACKGROUND_THICK, this.getCardBlurOptions())
    .borderRadius(18)
    .border({
      width: 1,
      color: this.getCardBorderColor()
    })
    .shadow({
      radius: 22,
      color: this.getThemeState().currentTheme === ThemeType.DARK
        ? 'rgba(0, 0, 0, 0.42)'
        : 'rgba(15, 23, 42, 0.16)',
      offsetX: 0,
      offsetY: 10
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
      .expandSafeArea([SafeAreaType.SYSTEM, SafeAreaType.CUTOUT], [
        SafeAreaEdge.TOP,
        SafeAreaEdge.BOTTOM,
        SafeAreaEdge.START,
        SafeAreaEdge.END
      ])
      .ignoreLayoutSafeArea([LayoutSafeAreaType.SYSTEM], [LayoutSafeAreaEdge.TOP, LayoutSafeAreaEdge.BOTTOM])
      .onAreaChange((_oldValue: Area, newValue: Area) => {
        this.screenWidth = Number(newValue.width);
        this.screenHeight = Number(newValue.height);
      })
      .zIndex(99997)
    }
  }
}
