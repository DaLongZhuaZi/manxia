/**
 * 替换书籍对话框组件
 * 从 UnifiedDetailPage 提取，用于换源后的书籍替换确认
 */

import { ThemeAwareState, ThemeAwareHelper } from './ThemeAware';
import { SourceDialogScaffold } from './SourceDialogScaffold';
import { DialogSurfaceStyleHelper } from './DialogSurfaceStyleHelper';
import { DialogAnimationState } from '../../Utils/DialogAnimationState';
import { ThemeType } from '../Managers/ThemeManager';
import { OriginalBookInfo } from '../../Models/UnifiedContentModels';

@Component
export struct ReplaceBookDialogComponent {
  @Prop themeState!: ThemeAwareState;
  @Prop @Watch('onLoadSignalChanged') loadSignal: number = 0;
  @Prop originalBookInfo!: OriginalBookInfo;
  @Prop newSourceName: string = '';
  @Prop newChapterCount: number = 0;
  @Prop matchedChapterIndex: number = -1;
  onConfirm?: () => void;
  onCancel?: () => void;

  @StorageLink('appFontFamily') appFontFamily: string = 'HarmonyOS Sans';
  @State isVisible: boolean = false;
  @State anim: DialogAnimationState = new DialogAnimationState({ initialScale: 0.8, initialTranslateY: 30 });

  private lastSignal: number = 0;

  onLoadSignalChanged(): void {
    if (this.loadSignal > this.lastSignal) {
      this.lastSignal = this.loadSignal;
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
        dialogWidth: '90%',
        maxWidth: 380,
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

          Column({ space: 16 }) {
            // 标题栏
            Row() {
              Row({ space: 8 }) {
                SymbolGlyph($r('sys.symbol.wrench_arrow_counterclockwise'))
                  .fontSize(20)
                  .fontColor([ThemeAwareHelper.getTestManagementThemedColor('accent_orange', this.themeState.currentTheme)])

                Text('替换小说')
                  .fontSize(18)
                  .fontWeight(FontWeight.Bold)
                  .fontFamily(this.appFontFamily)
                  .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_primary', this.themeState.currentTheme))
              }

              Blank()

              Button() {
                SymbolGlyph($r('sys.symbol.xmark'))
                  .fontSize(18)
                  .fontColor([ThemeAwareHelper.getTestManagementThemedColor('text_secondary', this.themeState.currentTheme)])
              }
              .width(32)
              .height(32)
              .backgroundColor(Color.Transparent)
              .onClick(() => {
                this.hideDialog();
                this.onCancel?.();
              })
            }
            .width('100%')

            // 对比信息
            Column({ space: 12 }) {
              // 原书信息卡片
              Column({ space: 8 }) {
                Row() {
                  Text('原书源')
                    .fontSize(11)
                    .fontFamily(this.appFontFamily)
                    .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_tertiary', this.themeState.currentTheme))
                    .padding({ left: 8, right: 8, top: 2, bottom: 2 })
                    .backgroundColor(ThemeAwareHelper.getTestManagementThemedColor('text_tertiary', this.themeState.currentTheme) + '20')
                    .borderRadius(4)
                }
                .width('100%')

                Text(this.originalBookInfo.sourceName || '未知书源')
                  .fontSize(14)
                  .fontWeight(FontWeight.Medium)
                  .fontFamily(this.appFontFamily)
                  .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_secondary', this.themeState.currentTheme))
                  .maxLines(2)
                  .textOverflow({ overflow: TextOverflow.Ellipsis })
                  .width('100%')

                Row({ space: 6 }) {
                  Text('共')
                    .fontSize(12)
                    .fontFamily(this.appFontFamily)
                    .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_muted', this.themeState.currentTheme))
                  Text(`${this.originalBookInfo.chapterCount}`)
                    .fontSize(14)
                    .fontWeight(FontWeight.Bold)
                    .fontFamily(this.appFontFamily)
                    .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_secondary', this.themeState.currentTheme))
                  Text('章')
                    .fontSize(12)
                    .fontFamily(this.appFontFamily)
                    .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_muted', this.themeState.currentTheme))
                }
                .width('100%')
              }
              .width('100%')
              .padding(12)
              .alignItems(HorizontalAlign.Start)
              .backgroundColor(ThemeAwareHelper.getTestManagementThemedColor('comp_background_tertiary', this.themeState.currentTheme))
              .borderRadius(12)

              // 箭头指示
              Row() {
                SymbolGlyph($r('sys.symbol.arrow_down'))
                  .fontSize(20)
                  .fontColor([ThemeAwareHelper.getTestManagementThemedColor('accent_orange', this.themeState.currentTheme)])
              }
              .width('100%')
              .justifyContent(FlexAlign.Center)

              // 新书源信息卡片
              Column({ space: 8 }) {
                Row() {
                  Text('新书源')
                    .fontSize(11)
                    .fontFamily(this.appFontFamily)
                    .fontColor(Color.White)
                    .padding({ left: 8, right: 8, top: 2, bottom: 2 })
                    .backgroundColor(ThemeAwareHelper.getTestManagementThemedColor('accent_orange', this.themeState.currentTheme))
                    .borderRadius(4)
                }
                .width('100%')

                Text(this.newSourceName || '未知书源')
                  .fontSize(14)
                  .fontWeight(FontWeight.Medium)
                  .fontFamily(this.appFontFamily)
                  .fontColor(ThemeAwareHelper.getTestManagementThemedColor('accent_orange', this.themeState.currentTheme))
                  .maxLines(2)
                  .textOverflow({ overflow: TextOverflow.Ellipsis })
                  .width('100%')

                Row({ space: 6 }) {
                  Text('共')
                    .fontSize(12)
                    .fontFamily(this.appFontFamily)
                    .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_muted', this.themeState.currentTheme))
                  Text(`${this.newChapterCount}`)
                    .fontSize(16)
                    .fontWeight(FontWeight.Bold)
                    .fontFamily(this.appFontFamily)
                    .fontColor(ThemeAwareHelper.getTestManagementThemedColor('accent_green', this.themeState.currentTheme))
                  Text('章')
                    .fontSize(12)
                    .fontFamily(this.appFontFamily)
                    .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_muted', this.themeState.currentTheme))

                  if (this.newChapterCount !== this.originalBookInfo.chapterCount) {
                    Text(`(${this.newChapterCount > this.originalBookInfo.chapterCount ? '+' : ''}${this.newChapterCount - this.originalBookInfo.chapterCount})`)
                      .fontSize(12)
                      .fontWeight(FontWeight.Medium)
                      .fontFamily(this.appFontFamily)
                      .fontColor(this.newChapterCount > this.originalBookInfo.chapterCount
                        ? ThemeAwareHelper.getTestManagementThemedColor('accent_green', this.themeState.currentTheme)
                        : ThemeAwareHelper.getTestManagementThemedColor('accent_orange', this.themeState.currentTheme))
                  }
                }
                .width('100%')
              }
              .width('100%')
              .padding(12)
              .alignItems(HorizontalAlign.Start)
              .backgroundColor(ThemeAwareHelper.getTestManagementThemedColor('accent_orange', this.themeState.currentTheme) + '15')
              .borderRadius(12)
              .border({
                width: 1,
                color: ThemeAwareHelper.getTestManagementThemedColor('accent_orange', this.themeState.currentTheme) + '40'
              })

              // 阅读进度迁移信息
              if (this.originalBookInfo.lastReadChapterIndex >= 0) {
                Column({ space: 6 }) {
                  Row({ space: 6 }) {
                    SymbolGlyph($r('sys.symbol.bookmark_fill'))
                      .fontSize(14)
                      .fontColor([ThemeAwareHelper.getTestManagementThemedColor('accent_primary', this.themeState.currentTheme)])
                    Text('阅读进度迁移')
                      .fontSize(13)
                      .fontWeight(FontWeight.Medium)
                      .fontFamily(this.appFontFamily)
                      .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_primary', this.themeState.currentTheme))
                  }

                  Text(`原书阅读至: 第${this.originalBookInfo.lastReadChapterIndex + 1}章`)
                    .fontSize(12)
                    .fontFamily(this.appFontFamily)
                    .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_secondary', this.themeState.currentTheme))

                  if (this.originalBookInfo.lastReadChapterTitle) {
                    Text(`「${this.originalBookInfo.lastReadChapterTitle}」`)
                      .fontSize(12)
                      .fontFamily(this.appFontFamily)
                      .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_tertiary', this.themeState.currentTheme))
                      .maxLines(1)
                      .textOverflow({ overflow: TextOverflow.Ellipsis })
                  }

                  Row({ space: 4 }) {
                    SymbolGlyph($r('sys.symbol.arrow_right_circle'))
                      .fontSize(12)
                      .fontColor([ThemeAwareHelper.getTestManagementThemedColor('accent_green', this.themeState.currentTheme)])

                    if (this.matchedChapterIndex >= 0) {
                      Text(`将从新书第${this.matchedChapterIndex + 1}章继续`)
                        .fontSize(12)
                        .fontFamily(this.appFontFamily)
                        .fontColor(ThemeAwareHelper.getTestManagementThemedColor('accent_green', this.themeState.currentTheme))
                    } else {
                      Text('将从第1章开始')
                        .fontSize(12)
                        .fontFamily(this.appFontFamily)
                        .fontColor(ThemeAwareHelper.getTestManagementThemedColor('accent_green', this.themeState.currentTheme))
                    }
                  }
                  .margin({ top: 4 })
                }
                .width('100%')
                .alignItems(HorizontalAlign.Start)
                .padding(12)
                .backgroundColor(ThemeAwareHelper.getTestManagementThemedColor('accent_primary', this.themeState.currentTheme) + '10')
                .borderRadius(12)
              }

              Text(this.originalBookInfo.isFavorite
                ? '替换后原书将从书架中删除，缓存数据也将清除'
                : '新书将添加到书架收藏')
                .fontSize(12)
                .fontFamily(this.appFontFamily)
                .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_muted', this.themeState.currentTheme))
                .textAlign(TextAlign.Center)
            }
            .width('100%')

            // 按钮栏
            Row({ space: 12 }) {
              Button('取消')
                .fontSize(14)
                .fontFamily(this.appFontFamily)
                .backgroundColor(ThemeAwareHelper.getTestManagementThemedColor('comp_background_tertiary', this.themeState.currentTheme))
                .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_primary', this.themeState.currentTheme))
                .height(44)
                .layoutWeight(1)
                .borderRadius(22)
                .onClick(() => {
                  this.hideDialog();
                  this.onCancel?.();
                })

              Button('确认替换')
                .fontSize(14)
                .fontFamily(this.appFontFamily)
                .backgroundColor(ThemeAwareHelper.getTestManagementThemedColor('accent_orange', this.themeState.currentTheme))
                .fontColor(Color.White)
                .height(44)
                .layoutWeight(1)
                .borderRadius(22)
                .onClick(() => {
                  this.hideDialog();
                  this.onConfirm?.();
                })
            }
            .width('100%')
          }
          .width('100%')
          .padding(20)
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
