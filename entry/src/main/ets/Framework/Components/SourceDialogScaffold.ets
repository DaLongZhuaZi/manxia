import { ThemeAwareState } from 'manxia_theme/src/main/ets/Framework/Components/ThemeAware';
import { DialogSurfaceStyleHelper } from 'manxia_features_ui/src/main/ets/Framework/Components/DialogSurfaceStyleHelper';

export enum SourceDialogLayoutMode {
  CENTER = 0,
  TOP = 1,
  BOTTOM = 2
}

/**
 * 书源/订阅源统一对话框外壳
 * - 使用系统模糊与系统资源色，保证可读性
 * - 支持居中/顶部/底部三种弹层布局
 * - 支持滚动内容容器，便于复用到复杂对话框
 */
@Component
export struct SourceDialogScaffold {
  @Prop themeState: ThemeAwareState;
  @Prop closeOnMaskTap: boolean = true;
  @Prop dialogWidth: Length = '90%';
  @Prop maxHeight: string = '86%';
  @Prop maxWidth: number = 560;
  @Prop minWidth: number = 280;
  @Prop zIndexValue: number = 3000;
  @Prop layoutMode: SourceDialogLayoutMode = SourceDialogLayoutMode.CENTER;
  @Prop topOffset: number = 72;
  @Prop bottomOffset: number = 24;
  @Prop contentPadding: number = 24;
  @Prop contentScrollable: boolean = false;
  @Prop useMaskBlur: boolean = true;
  @Prop maskBlurStyle: BlurStyle = DialogSurfaceStyleHelper.getPopupMaskBlurStyle();
  @Prop maskBlurOptions: BackgroundBlurStyleOptions = DialogSurfaceStyleHelper.getPopupMaskBlurOptions();
  @Prop maskColor: ResourceColor = DialogSurfaceStyleHelper.getPopupMaskColor();
  @Prop maskBackgroundEffect: BackgroundEffectOptions | undefined = DialogSurfaceStyleHelper.getPopupMaskBackgroundEffect();
  @Prop dialogRadius: number = DialogSurfaceStyleHelper.getPopupCardRadius();
  @Prop shadowOffsetY: number = 8;
  onMaskTap: () => void = () => {};
  @BuilderParam content: () => void = this.emptyContentBuilder;
  @State private maskTapEnabled: boolean = false;

  @Builder
  private emptyContentBuilder() {
  }

  @Builder
  private buildDialogBody() {
    if (this.contentScrollable) {
      Scroll() {
        Column() {
          this.content();
        }
        .width('100%')
      }
      .width('100%')
      .scrollBar(BarState.Auto)
    } else {
      Column() {
        this.content();
      }
      .width('100%')
    }
  }

  @Builder
  private buildDialogCard() {
    Column() {
      this.buildDialogBody();
    }
    .width(this.dialogWidth)
    .constraintSize({ minWidth: this.minWidth, maxWidth: this.maxWidth, maxHeight: this.maxHeight })
    .padding(this.contentPadding)
    .backgroundColor(DialogSurfaceStyleHelper.getPopupCardBackground(this.themeState))
    .backgroundBlurStyle(
      DialogSurfaceStyleHelper.getPopupCardBlurStyle(),
      DialogSurfaceStyleHelper.getPopupCardBlurOptions()
    )
    .backgroundEffect(DialogSurfaceStyleHelper.getPopupCardBackgroundEffect())
    .borderRadius(this.dialogRadius)
    .clip(true)
    .border({
      width: DialogSurfaceStyleHelper.getPopupCardBorderWidth(this.themeState),
      color: DialogSurfaceStyleHelper.getPopupCardBorderColor(this.themeState)
    })
    .shadow({
      radius: this.dialogRadius + 4,
      color: DialogSurfaceStyleHelper.getPopupCardShadowColor(this.themeState),
      offsetX: 0,
      offsetY: this.shadowOffsetY
    })
    .zIndex(1)
    .transition(
      TransitionEffect.OPACITY.animation({ duration: 180, curve: Curve.EaseOut })
        .combine(TransitionEffect.scale({ x: 0.96, y: 0.96 }).animation({ duration: 220, curve: Curve.EaseOut }))
    )
    .onClick(() => {
    })
  }

  build() {
    Stack({ alignContent: Alignment.Center }) {
      if (this.useMaskBlur) {
        Column()
          .width('100%')
          .height('100%')
          .backgroundBlurStyle(this.maskBlurStyle, this.maskBlurOptions)
          .backgroundColor(this.maskColor)
          .backgroundEffect(this.maskBackgroundEffect)
          .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.TOP, SafeAreaEdge.BOTTOM])
          .zIndex(0)
          .onClick(() => {
            if (this.closeOnMaskTap && this.maskTapEnabled) {
              this.onMaskTap();
            }
          })
      } else {
        Column()
          .width('100%')
          .height('100%')
          .backgroundColor(this.maskColor)
          .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.TOP, SafeAreaEdge.BOTTOM])
          .zIndex(0)
          .onClick(() => {
            if (this.closeOnMaskTap && this.maskTapEnabled) {
              this.onMaskTap();
            }
          })
      }

      if (this.layoutMode === SourceDialogLayoutMode.TOP) {
        Column() {
          this.buildDialogCard();
          Blank().layoutWeight(1)
        }
        .width('100%')
        .height('100%')
        .padding({ top: this.topOffset, left: 0, right: 0, bottom: 0 })
      } else if (this.layoutMode === SourceDialogLayoutMode.BOTTOM) {
        Column() {
          Blank().layoutWeight(1)
          this.buildDialogCard();
        }
        .width('100%')
        .height('100%')
        .padding({ top: 0, left: 0, right: 0, bottom: this.bottomOffset })
      } else {
        this.buildDialogCard();
      }
    }
    .width('100%')
    .height('100%')
    .position({ x: 0, y: 0 })
    .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.TOP, SafeAreaEdge.BOTTOM])
    .zIndex(this.zIndexValue)
    .transition(TransitionEffect.OPACITY.animation({ duration: 180, curve: Curve.EaseOut }))
  }

  aboutToAppear(): void {
    this.maskTapEnabled = false;
    setTimeout(() => {
      this.maskTapEnabled = true;
    }, 120);
  }
}
