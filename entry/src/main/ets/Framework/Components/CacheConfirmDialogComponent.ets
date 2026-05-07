/**
 * 缓存确认对话框组件
 * 从 UnifiedDetailPage 提取，用于清理缓存前的确认提示
 */

import { curves } from '@kit.ArkUI';
import { ThemeAwareState, ThemeAwareHelper } from './ThemeAware';
import { SourceDialogScaffold } from './SourceDialogScaffold';
import { DialogSurfaceStyleHelper } from './DialogSurfaceStyleHelper';
import { DialogAnimationState } from '../../Utils/DialogAnimationState';
import { ThemeType } from '../Managers/ThemeManager';

/** 缓存确认对话框配置 */
export interface CacheConfirmConfig {
  title: string;
  message: string;
  actionLabel: string;
  actionKind: 'danger' | 'primary';
  pendingAction: string;
}

@Component
export struct CacheConfirmDialogComponent {
  @Prop themeState!: ThemeAwareState;
  @Prop @Watch('onLoadSignalChanged') loadSignal: number = 0;
  @Prop config!: CacheConfirmConfig;
  onConfirm?: (pendingAction: string) => void;
  onCancel?: () => void;

  @StorageLink('appFontFamily') appFontFamily: string = 'HarmonyOS Sans';
  @State isVisible: boolean = false;
  @State anim: DialogAnimationState = new DialogAnimationState({
    initialScale: 0.8,
    initialTranslateY: 28,
    inCurve: curves.springMotion(0.6, 0.9),
    closeScale: 0.86,
    closeTranslateY: 28
  });

  private lastSignal: number = 0;

  onLoadSignalChanged(): void {
    if (this.loadSignal > this.lastSignal) {
      this.lastSignal = this.loadSignal;
      this.showDialog();
    }
  }

  private showDialog(): void {
    this.isVisible = true;
    this.anim.animateIn(this.getUIContext());
  }

  private hideDialog(): void {
    this.anim.animateOut(this.getUIContext(), () => {
      this.isVisible = false;
    });
  }

  build() {
    if (this.isVisible) {
      SourceDialogScaffold({
        themeState: this.themeState,
        onMaskTap: () => {
          this.hideDialog();
          this.onCancel?.();
        },
        dialogWidth: '88%',
        maxWidth: 420,
        contentPadding: 0,
        dialogRadius: 26,
        zIndexValue: 120,
        useMaskBlur: true,
        maskBlurStyle: DialogSurfaceStyleHelper.getPopupMaskBlurStyle(),
        maskColor: DialogSurfaceStyleHelper.getPopupMaskColor()
      }) {
        Stack({ alignContent: Alignment.TopStart }) {
          // dialog chrome
          Column()
            .width('100%')
            .height(1)
            .backgroundColor(this.themeState.currentTheme === ThemeType.DARK
              ? 'rgba(255, 255, 255, 0.18)'
              : 'rgba(255, 255, 255, 0.58)')
          Column()
            .width('100%')
            .height(1)
            .align(Alignment.Bottom)
            .backgroundColor(this.themeState.currentTheme === ThemeType.DARK
              ? 'rgba(154, 196, 255, 0.08)'
              : 'rgba(126, 166, 220, 0.10)')

          Column({ space: 14 }) {
            Text(this.config.title)
              .fontSize(18)
              .fontWeight(FontWeight.Bold)
              .fontFamily(this.appFontFamily)
              .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_primary', this.themeState.currentTheme))

            Text(this.config.message)
              .fontSize(13)
              .lineHeight(22)
              .fontFamily(this.appFontFamily)
              .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_secondary', this.themeState.currentTheme))
              .width('100%')

            Row({ space: 10 }) {
              Button('取消')
                .layoutWeight(1)
                .height(40)
                .fontSize(14)
                .fontFamily(this.appFontFamily)
                .backgroundColor(ThemeAwareHelper.getTestManagementThemedColor('comp_background_secondary', this.themeState.currentTheme))
                .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_primary', this.themeState.currentTheme))
                .borderRadius(20)
                .onClick(() => {
                  this.hideDialog();
                  this.onCancel?.();
                })

              Button(this.config.actionLabel)
                .layoutWeight(1)
                .height(40)
                .fontSize(14)
                .fontFamily(this.appFontFamily)
                .backgroundColor(this.config.actionKind === 'danger'
                  ? ThemeAwareHelper.getTestManagementThemedColor('color_error', this.themeState.currentTheme)
                  : ThemeAwareHelper.getTestManagementThemedColor('accent_primary', this.themeState.currentTheme))
                .fontColor(Color.White)
                .borderRadius(20)
                .onClick(() => {
                  this.hideDialog();
                  this.onConfirm?.(this.config.pendingAction);
                })
            }
            .width('100%')
          }
          .width('100%')
          .padding(20)
        }
        .width('100%')
        .scale({ x: this.anim.scale, y: this.anim.scale })
        .translate({ y: this.anim.translateY })
        .opacity(this.anim.opacity)
        .borderRadius(18)
        .clip(true)
        .onClick(() => {})
      }
    }
  }
}
