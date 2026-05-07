/**
 * 生成封面对话框组件
 * 从 UnifiedDetailPage 提取，用于生成自定义封面
 */

import { ThemeAwareState, ThemeAwareHelper } from './ThemeAware';
import { SourceDialogScaffold } from './SourceDialogScaffold';
import { DialogSurfaceStyleHelper } from './DialogSurfaceStyleHelper';
import { DialogAnimationState } from '../../Utils/DialogAnimationState';
import { ThemeType } from '../Managers/ThemeManager';

@Component
export struct GenerateCoverDialogComponent {
  @Prop themeState!: ThemeAwareState;
  @Prop @Watch('onLoadSignalChanged') loadSignal: number = 0;
  @Prop defaultTitle: string = '';
  onConfirm?: (title: string, fontScale: number) => void;
  onCancel?: () => void;

  @StorageLink('appFontFamily') appFontFamily: string = 'HarmonyOS Sans';
  @State isVisible: boolean = false;
  @State anim: DialogAnimationState = new DialogAnimationState({ initialScale: 0.8, initialTranslateY: 30 });
  @State coverTitleInput: string = '';
  @State coverFontScale: number = 1.0;

  private lastSignal: number = 0;

  onLoadSignalChanged(): void {
    if (this.loadSignal > this.lastSignal) {
      this.lastSignal = this.loadSignal;
      this.coverTitleInput = this.defaultTitle;
      this.coverFontScale = 1.0;
      this.isVisible = true;
      this.anim.animateIn(this.getUIContext());
    }
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
        dialogWidth: '80%',
        maxWidth: 400,
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

          Column({ space: 20 }) {
            Text('生成封面')
              .fontSize(18)
              .fontWeight(FontWeight.Bold)
              .fontFamily(this.appFontFamily)
              .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_primary', this.themeState.currentTheme))

            Column({ space: 8 }) {
              Text('请输入要显示在封面上的标题：')
                .fontSize(14)
                .fontFamily(this.appFontFamily)
                .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_secondary', this.themeState.currentTheme))

              TextInput({ text: this.coverTitleInput })
                .fontSize(14)
                .fontFamily(this.appFontFamily)
                .backgroundColor(ThemeAwareHelper.getTestManagementThemedColor('comp_background_tertiary', this.themeState.currentTheme))
                .onChange((value: string) => {
                  this.coverTitleInput = value;
                })
            }
            .alignItems(HorizontalAlign.Start)
            .width('100%')

            Column({ space: 8 }) {
              Row() {
                Text('字体倍率：')
                  .fontSize(14)
                  .fontFamily(this.appFontFamily)
                  .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_secondary', this.themeState.currentTheme))

                Text(this.coverFontScale.toFixed(1) + 'x')
                  .fontSize(14)
                  .fontFamily(this.appFontFamily)
                  .fontWeight(FontWeight.Medium)
                  .fontColor(ThemeAwareHelper.getTestManagementThemedColor('accent_primary', this.themeState.currentTheme))
              }
              .width('100%')
              .justifyContent(FlexAlign.SpaceBetween)

              Slider({
                value: this.coverFontScale,
                min: 0.1,
                max: 2.0,
                step: 0.1,
                style: SliderStyle.OutSet
              })
                .blockColor(ThemeAwareHelper.getTestManagementThemedColor('accent_primary', this.themeState.currentTheme))
                .trackColor(ThemeAwareHelper.getTestManagementThemedColor('comp_background_tertiary', this.themeState.currentTheme))
                .selectedColor(ThemeAwareHelper.getTestManagementThemedColor('accent_primary', this.themeState.currentTheme))
                .showSteps(false)
                .showTips(false)
                .onChange((value: number) => {
                  this.coverFontScale = value;
                })
            }
            .alignItems(HorizontalAlign.Start)
            .width('100%')

            Row({ space: 12 }) {
              Button('取消')
                .fontSize(14)
                .fontFamily(this.appFontFamily)
                .backgroundColor(ThemeAwareHelper.getTestManagementThemedColor('comp_background_tertiary', this.themeState.currentTheme))
                .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_primary', this.themeState.currentTheme))
                .layoutWeight(1)
                .onClick(() => {
                  this.hideDialog();
                  this.onCancel?.();
                })

              Button('确定')
                .fontSize(14)
                .fontFamily(this.appFontFamily)
                .backgroundColor(ThemeAwareHelper.getTestManagementThemedColor('accent_primary', this.themeState.currentTheme))
                .fontColor(Color.White)
                .layoutWeight(1)
                .onClick(() => {
                  const title = this.coverTitleInput;
                  const scale = this.coverFontScale;
                  this.hideDialog();
                  this.onConfirm?.(title, scale);
                })
            }
            .width('100%')
          }
          .width('100%')
          .padding(24)
          .scale({ x: this.anim.scale, y: this.anim.scale })
          .translate({ y: this.anim.translateY })
          .opacity(this.anim.opacity)
          .borderRadius(26)
          .clip(true)
          .onClick(() => {})
        }
      }
    }
  }
}
