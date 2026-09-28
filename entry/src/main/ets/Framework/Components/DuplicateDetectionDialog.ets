/**
 * 内容重复检测弹窗组件
 * 显示可能重复的内容列表，让用户决定是否继续添加
 */

import { ThemeAwareState, ThemeAwareHelper } from 'manxia_theme/src/main/ets/Framework/Components/ThemeAware';
import { SourceDialogScaffold } from './SourceDialogScaffold';
import {
  DuplicateMatchItem,
  DuplicateCheckContentType,
  getContentTypeDisplayName,
  formatSimilarityPercent
} from '../DuplicateDetection/DuplicateDetectionModels';

@Component
export struct DuplicateDetectionDialog {
  @Prop themeState: ThemeAwareState = new ThemeAwareState();
  @Prop @Watch('onLoadSignalChanged') loadSignal: number = 0;
  @Prop newItemTitle: string = '';
  @Prop newItemAuthor: string = '';
  @Prop newItemContentType: DuplicateCheckContentType = DuplicateCheckContentType.MANGA;
  @Prop matches: DuplicateMatchItem[] = [];
  onConfirm?: () => void;
  onCancel?: () => void;

  @StorageLink('appFontFamily') appFontFamily: string = 'HarmonyOS Sans';
  @State isVisible: boolean = false;

  private lastSignal: number = 0;

  onLoadSignalChanged(): void {
    if (this.loadSignal > this.lastSignal) {
      this.lastSignal = this.loadSignal;
      this.getUIContext().animateTo({ duration: 220, curve: Curve.EaseOut }, () => {
        this.isVisible = true;
      });
    }
  }

  private hideDialog(): void {
    this.getUIContext().animateTo({ duration: 180, curve: Curve.EaseIn }, () => {
      this.isVisible = false;
    });
  }

  private getSimilarityColor(similarity: number): string {
    if (similarity >= 0.8) {
      return '#E74C3C';
    } else if (similarity >= 0.5) {
      return '#F39C12';
    }
    return '#3498DB';
  }

  private getContentTypeColor(contentType: DuplicateCheckContentType): string {
    if (contentType === DuplicateCheckContentType.MANGA) {
      return '#9B59B6';
    } else if (contentType === DuplicateCheckContentType.EBOOK) {
      return '#2ECC71';
    }
    return '#3498DB';
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
        maxWidth: 400,
        contentPadding: 24,
        useMaskBlur: true
      }) {
        Column({ space: 20 }) {
            // 标题栏
            Row() {
              Row({ space: 8 }) {
                SymbolGlyph($r('sys.symbol.exclamationmark_triangle'))
                  .fontSize(20)
                  .fontColor([ThemeAwareHelper.getTestManagementThemedColor('accent_orange', this.themeState.currentTheme)])

                Text('检测到可能重复的内容')
                  .fontSize(20)
                  .fontWeight(FontWeight.Medium)
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

            // 新内容信息
            Column({ space: 4 }) {
              Text('待添加内容')
                .fontSize(11)
                .fontFamily(this.appFontFamily)
                .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_tertiary', this.themeState.currentTheme))
                .padding({ left: 8, right: 8, top: 2, bottom: 2 })
                .backgroundColor(ThemeAwareHelper.getTestManagementThemedColor('text_tertiary', this.themeState.currentTheme) + '20')
                .borderRadius(4)

              Text(this.newItemTitle)
                .fontSize(15)
                .fontWeight(FontWeight.Medium)
                .fontFamily(this.appFontFamily)
                .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_primary', this.themeState.currentTheme))
                .maxLines(2)
                .textOverflow({ overflow: TextOverflow.Ellipsis })
                .width('100%')

              if (this.newItemAuthor.length > 0) {
                Text(this.newItemAuthor)
                  .fontSize(13)
                  .fontFamily(this.appFontFamily)
                  .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_secondary', this.themeState.currentTheme))
                  .maxLines(1)
                  .textOverflow({ overflow: TextOverflow.Ellipsis })
                  .width('100%')
              }
            }
            .width('100%')
            .padding(12)
            .alignItems(HorizontalAlign.Start)
            .backgroundColor(ThemeAwareHelper.getTestManagementThemedColor('comp_background_tertiary', this.themeState.currentTheme))
            .borderRadius(12)

            // 匹配列表
            Column({ space: 8 }) {
              Text('以下内容可能与您要添加的内容重复')
                .fontSize(12)
                .fontFamily(this.appFontFamily)
                .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_muted', this.themeState.currentTheme))

              List({ space: 8 }) {
                ForEach(this.matches, (match: DuplicateMatchItem) => {
                  ListItem() {
                    Row({ space: 10 }) {
                      // 封面占位
                      Column() {
                        if (match.coverUrl.length > 0) {
                          Image(match.coverUrl)
                            .width(48)
                            .height(64)
                            .objectFit(ImageFit.Cover)
                            .borderRadius(6)
                        } else {
                          Column()
                            .width(48)
                            .height(64)
                            .borderRadius(6)
                            .backgroundColor(ThemeAwareHelper.getTestManagementThemedColor('comp_background_secondary', this.themeState.currentTheme))
                        }
                      }

                      // 信息区域
                      Column({ space: 4 }) {
                        // 标题行 + 类型标签
                        Row({ space: 6 }) {
                          Text(match.title)
                            .fontSize(14)
                            .fontWeight(FontWeight.Medium)
                            .fontFamily(this.appFontFamily)
                            .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_primary', this.themeState.currentTheme))
                            .maxLines(1)
                            .textOverflow({ overflow: TextOverflow.Ellipsis })
                            .layoutWeight(1)

                          Text(getContentTypeDisplayName(match.contentType))
                            .fontSize(10)
                            .fontFamily(this.appFontFamily)
                            .fontColor(Color.White)
                            .padding({ left: 6, right: 6, top: 2, bottom: 2 })
                            .backgroundColor(this.getContentTypeColor(match.contentType))
                            .borderRadius(4)
                        }
                        .width('100%')

                        // 作者
                        if (match.author.length > 0) {
                          Text(match.author)
                            .fontSize(12)
                            .fontFamily(this.appFontFamily)
                            .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_secondary', this.themeState.currentTheme))
                            .maxLines(1)
                            .textOverflow({ overflow: TextOverflow.Ellipsis })
                            .width('100%')
                        }

                        // 相似度 + 章节数
                        Row({ space: 12 }) {
                          Text(`相似度 ${formatSimilarityPercent(match.overallSimilarity)}`)
                            .fontSize(12)
                            .fontWeight(FontWeight.Medium)
                            .fontFamily(this.appFontFamily)
                            .fontColor(this.getSimilarityColor(match.overallSimilarity))

                          if (match.chapterCount > 0) {
                            Text(`${match.chapterCount} 章`)
                              .fontSize(12)
                              .fontFamily(this.appFontFamily)
                              .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_muted', this.themeState.currentTheme))
                          }

                          if (match.sourceName.length > 0) {
                            Text(match.sourceName)
                              .fontSize(11)
                              .fontFamily(this.appFontFamily)
                              .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_tertiary', this.themeState.currentTheme))
                              .maxLines(1)
                              .textOverflow({ overflow: TextOverflow.Ellipsis })
                              .layoutWeight(1)
                          }
                        }
                        .width('100%')
                      }
                      .layoutWeight(1)
                    }
                    .width('100%')
                    .padding(10)
                    .backgroundColor(ThemeAwareHelper.getTestManagementThemedColor('comp_background_secondary', this.themeState.currentTheme))
                    .borderRadius(10)
                  }
                }, (match: DuplicateMatchItem) => `dup_${match.id}`)
              }
              .width('100%')
              .height(this.matches.length > 3 ? 260 : undefined)
              .alignListItem(ListItemAlign.Center)
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

              Button('仍然添加')
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
      }
    }
  }
}
