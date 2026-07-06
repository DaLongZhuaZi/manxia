// 文件路径: entry/src/main/ets/Framework/Components/ChangeSourceDialogComponent.ets
// 职责: 换源对话框组件，从UnifiedDetailPage提取的独立组件

import { promptAction } from '@kit.ArkUI';
import { logger } from '../../Utils/Logger';
import { ThemeAwareState, ThemeAwareHelper } from './ThemeAware';
import { SourceDialogScaffold } from './SourceDialogScaffold';
import { UnifiedContent, UnifiedContentType } from '../../Models/UnifiedContentModels';
import { getNovelSourceSearchService, SourceSearchResult, SearchTaskHandle } from '../Novel/NovelSourceSearchService';
import { NovelSearchResult } from '../../Models/NovelModels';

const TAG = 'ChangeSourceDialogComponent';

@Component
export struct ChangeSourceDialogComponent {
  // 从父组件接收的属性
  @Prop content: UnifiedContent | null = null;
  @Prop themeState: ThemeAwareState = new ThemeAwareState();
  @StorageLink('appFontFamily') appFontFamily: string = 'HarmonyOS Sans';
  @Prop @Watch('onLoadSignalChanged') loadSignal: number = 0;
  @Prop currentSourceId: string = '';

  // 回调函数
  onSourceSelected?: (source: NovelSearchResult) => void;

  // 对话框内部状态
  @State showChangeSourceDialog: boolean = false;
  @State isSearchingSource: boolean = false;
  @State searchSourceProgress: number = 0;
  @State searchSourceTotal: number = 0;
  @State searchSourceCompleted: number = 0;
  @State alternativeSourceResults: SourceSearchResult[] = [];
  @State alternativeSources: NovelSearchResult[] = [];
  @State changeSourceKeyword: string = '';

  private searchTaskHandle: SearchTaskHandle | null = null;
  private sourceSearchService = getNovelSourceSearchService();

  // 生命周期
  onLoadSignalChanged(): void {
    if (this.loadSignal > 0) {
      this.openChangeSourceDialog();
    }
  }

  // ==================== 对话框控制 ====================

  openChangeSourceDialog(): void {
    if (!this.content || this.content.contentType !== UnifiedContentType.NOVEL) return;

    this.changeSourceKeyword = this.content.title;

    this.getUIContext().animateTo({
      duration: 220,
      curve: Curve.EaseOut
    }, () => {
      this.showChangeSourceDialog = true;
    });

    this.startChangeSourceSearch(false);
  }

  closeChangeSourceDialog(): void {
    if (this.searchTaskHandle) {
      this.searchTaskHandle.cancel();
      this.searchTaskHandle = null;
    }
    this.isSearchingSource = false;

    this.getUIContext().animateTo({
      duration: 180,
      curve: Curve.EaseIn
    }, () => {
      this.showChangeSourceDialog = false;
    });
  }

  // ==================== 搜索逻辑 ====================

  private startChangeSourceSearch(forceRefresh: boolean = false): void {
    if (this.searchTaskHandle) {
      this.searchTaskHandle.cancel();
    }

    const keyword = this.changeSourceKeyword.trim();
    if (!keyword) {
      this.getUIContext().getPromptAction().showToast({ message: '请输入搜索关键词' });
      return;
    }

    const bookAuthor = this.content?.author;

    if (!forceRefresh) {
      const cached = this.sourceSearchService.getCachedResults(keyword, bookAuthor);
      if (cached) {
        this.alternativeSources = cached.results;
        this.alternativeSourceResults = cached.sourceResults;
        this.searchSourceCompleted = cached.sourceResults.length;
        this.searchSourceTotal = cached.sourceResults.length;
        this.searchSourceProgress = 100;
        this.isSearchingSource = false;
        logger.info(TAG, `使用缓存的换源搜索结果: ${keyword}`);
        return;
      }
    } else {
      this.sourceSearchService.clearCache(keyword, bookAuthor);
    }

    this.isSearchingSource = true;
    this.alternativeSources = [];
    this.alternativeSourceResults = [];
    this.searchSourceCompleted = 0;
    this.searchSourceTotal = this.sourceSearchService.getSearchableSourceCount();
    this.searchSourceProgress = 0;

    logger.info(TAG, `开始换源搜索: ${keyword}, 共 ${this.searchSourceTotal} 个书源`);

    this.searchTaskHandle = this.sourceSearchService.searchForSource(
      keyword,
      bookAuthor,
      {
        onSourceComplete: (sourceResult: SourceSearchResult) => {
          this.alternativeSourceResults = [...this.alternativeSourceResults, sourceResult];
          this.alternativeSources = [...this.alternativeSources, ...sourceResult.results];
        },
        onProgress: (completed: number, total: number) => {
          this.searchSourceCompleted = completed;
          this.searchSourceTotal = total;
          this.searchSourceProgress = total > 0 ? Math.round((completed / total) * 100) : 0;
        },
        onComplete: (allResults: NovelSearchResult[], sourceResults: SourceSearchResult[]) => {
          this.isSearchingSource = false;
          this.searchSourceProgress = 100;
          this.searchTaskHandle = null;
          logger.info(TAG, `换源搜索完成: 共 ${sourceResults.length} 个书源有结果`);
        },
        onCancelled: () => {
          this.isSearchingSource = false;
          this.searchTaskHandle = null;
          logger.info(TAG, '换源搜索已取消');
        }
      },
      0
    );
  }

  private handleSourceSelected(source: NovelSearchResult): void {
    if (source.sourceId === this.currentSourceId) {
      return;
    }
    this.closeChangeSourceDialog();
    this.onSourceSelected?.(source);
  }

  // ==================== Builder 方法 ====================

  @Builder
  buildChangeSourceDialog() {
    if (this.showChangeSourceDialog) {
      SourceDialogScaffold({
        themeState: this.themeState,
        onMaskTap: () => this.closeChangeSourceDialog(),
        dialogWidth: '90%',
        maxWidth: 420,
        maxHeight: '80%',
        contentPadding: 24,
        useMaskBlur: true
      }) {
        Column({ space: 20 }) {

            // 标题栏
            Row() {
              Column() {
                Row({ space: 8 }) {
                  SymbolGlyph($r('sys.symbol.arrow_2_circlepath'))
                    .fontSize(20)
                    .fontColor([ThemeAwareHelper.getTestManagementThemedColor('accent_green',
                      this.themeState.currentTheme)])

                  Text('换源')
                    .fontSize(20)
                    .fontWeight(FontWeight.Medium)
                    .fontFamily(this.appFontFamily)
                    .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_primary',
                      this.themeState.currentTheme))

                  if (this.alternativeSourceResults.length > 0) {
                    Text(`(${this.alternativeSourceResults.length}个书源)`)
                      .fontSize(12)
                      .fontFamily(this.appFontFamily)
                      .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_tertiary',
                        this.themeState.currentTheme))
                      .animation({ duration: 200, curve: Curve.EaseOut })
                  }
                }

                if (this.isSearchingSource) {
                  Row() {
                    Progress({ value: this.searchSourceProgress, total: 100, type: ProgressType.Linear })
                      .width('100%')
                      .height(3)
                      .color(ThemeAwareHelper.getTestManagementThemedColor('accent_green',
                        this.themeState.currentTheme))
                      .backgroundColor(ThemeAwareHelper.getTestManagementThemedColor('divider',
                        this.themeState.currentTheme))
                      .animation({ duration: 150, curve: Curve.EaseOut })
                  }
                  .width('100%')
                  .margin({ top: 10 })
                }
              }
              .alignItems(HorizontalAlign.Start)
              .layoutWeight(1)

              Row({ space: 8 }) {
                if (this.isSearchingSource) {
                  Text(`${this.searchSourceCompleted}/${this.searchSourceTotal}`)
                    .fontSize(12)
                    .fontFamily(this.appFontFamily)
                    .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_tertiary',
                      this.themeState.currentTheme))
                    .animation({ duration: 200, curve: Curve.EaseOut })
                }

                Button() {
                  SymbolGlyph($r('sys.symbol.xmark'))
                    .fontSize(18)
                    .fontColor([ThemeAwareHelper.getTestManagementThemedColor('text_secondary',
                      this.themeState.currentTheme)])
                }
                .width(32)
                .height(32)
                .backgroundColor(Color.Transparent)
                .onClick(() => this.closeChangeSourceDialog())
              }
            }
            .width('100%')

            // 搜索关键词输入框
            Row({ space: 8 }) {
              Row() {
                SymbolGlyph($r('sys.symbol.magnifyingglass'))
                  .fontSize(16)
                  .fontColor([ThemeAwareHelper.getTestManagementThemedColor('text_tertiary',
                    this.themeState.currentTheme)])

                TextInput({ text: this.changeSourceKeyword, placeholder: '输入搜索关键词' })
                  .layoutWeight(1)
                  .height(36)
                  .backgroundColor(Color.Transparent)
                  .fontSize(14)
                  .fontFamily(this.appFontFamily)
                  .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_primary',
                    this.themeState.currentTheme))
                  .placeholderColor(ThemeAwareHelper.getTestManagementThemedColor('text_tertiary',
                    this.themeState.currentTheme))
                  .caretColor(ThemeAwareHelper.getTestManagementThemedColor('accent_green',
                    this.themeState.currentTheme))
                  .padding({ left: 8, right: 8 })
                  .onChange((value: string) => {
                    this.changeSourceKeyword = value;
                  })
                  .onSubmit(() => {
                    this.startChangeSourceSearch(true);
                  })

                if (this.changeSourceKeyword.length > 0) {
                  Button() {
                    SymbolGlyph($r('sys.symbol.xmark_circle_fill'))
                      .fontSize(16)
                      .fontColor([ThemeAwareHelper.getTestManagementThemedColor('text_tertiary',
                        this.themeState.currentTheme)])
                  }
                  .width(28)
                  .height(28)
                  .backgroundColor(Color.Transparent)
                  .onClick(() => {
                    this.changeSourceKeyword = '';
                  })
                }
              }
              .layoutWeight(1)
              .height(40)
              .padding({ left: 12, right: 4 })
              .backgroundColor(ThemeAwareHelper.getTestManagementThemedColor('comp_background_tertiary',
                this.themeState.currentTheme))
              .borderRadius(20)

              Button() {
                if (this.isSearchingSource) {
                  LoadingProgress()
                    .width(18)
                    .height(18)
                    .color(Color.White)
                } else {
                  Text('搜索')
                    .fontSize(14)
                    .fontFamily(this.appFontFamily)
                    .fontColor(Color.White)
                }
              }
              .width(60)
              .height(40)
              .backgroundColor(ThemeAwareHelper.getTestManagementThemedColor('accent_green',
                this.themeState.currentTheme))
              .borderRadius(20)
              .enabled(!this.isSearchingSource && this.changeSourceKeyword.trim().length > 0)
              .opacity(!this.isSearchingSource && this.changeSourceKeyword.trim().length > 0 ? 1 : 0.5)
              .onClick(() => {
                this.startChangeSourceSearch(true);
              })
            }
            .width('100%')
            .padding({ left: 16, right: 16, top: 8, bottom: 12 })
            .animation({ duration: 200, curve: Curve.EaseOut })

            // 搜索结果列表
            if (this.isSearchingSource && this.alternativeSourceResults.length === 0) {
              Column() {
                LoadingProgress()
                  .width(40)
                  .height(40)
                  .color(ThemeAwareHelper.getTestManagementThemedColor('accent_green', this.themeState.currentTheme))

                Text(`正在搜索可用书源...`)
                  .fontSize(14)
                  .fontFamily(this.appFontFamily)
                  .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_tertiary',
                    this.themeState.currentTheme))
                  .margin({ top: 16 })

                Text(`${this.searchSourceCompleted} / ${this.searchSourceTotal}`)
                  .fontSize(24)
                  .fontWeight(FontWeight.Bold)
                  .fontFamily(this.appFontFamily)
                  .fontColor(ThemeAwareHelper.getTestManagementThemedColor('accent_primary',
                    this.themeState.currentTheme))
                  .margin({ top: 8 })
              }
              .width('100%')
              .height(280)
              .justifyContent(FlexAlign.Center)
              .animation({ duration: 300, curve: Curve.EaseOut })
            } else if (!this.isSearchingSource && this.alternativeSourceResults.length === 0) {
              Column() {
                SymbolGlyph($r('sys.symbol.magnifyingglass'))
                  .fontSize(56)
                  .fontColor([ThemeAwareHelper.getTestManagementThemedColor('text_tertiary',
                    this.themeState.currentTheme)])

                Text('未找到其他书源')
                  .fontSize(16)
                  .fontWeight(FontWeight.Medium)
                  .fontFamily(this.appFontFamily)
                  .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_secondary',
                    this.themeState.currentTheme))
                  .margin({ top: 16 })

                Text('试试导入更多书源后再换源')
                  .fontSize(13)
                  .fontFamily(this.appFontFamily)
                  .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_tertiary',
                    this.themeState.currentTheme))
                  .margin({ top: 6 })
              }
              .width('100%')
              .height(280)
              .justifyContent(FlexAlign.Center)
            } else {
              List() {
                ForEach(this.alternativeSourceResults, (sourceResult: SourceSearchResult, sourceIndex: number) => {
                  ListItem() {
                    Row() {
                      Row({ space: 6 }) {
                        Text(sourceResult.sourceName)
                          .fontSize(13)
                          .fontWeight(FontWeight.Medium)
                          .fontFamily(this.appFontFamily)
                          .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_secondary',
                            this.themeState.currentTheme))

                        Text(`${sourceResult.results.length}本`)
                          .fontSize(11)
                          .fontFamily(this.appFontFamily)
                          .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_tertiary',
                            this.themeState.currentTheme))
                      }

                      Blank()

                      if (sourceResult.sourceGroup && sourceResult.sourceGroup !== '未分组') {
                        Text(sourceResult.sourceGroup)
                          .fontSize(10)
                          .fontFamily(this.appFontFamily)
                          .fontColor(ThemeAwareHelper.getTestManagementThemedColor('accent_primary',
                            this.themeState.currentTheme))
                          .backgroundColor(ThemeAwareHelper.getTestManagementThemedColor('accent_primary',
                            this.themeState.currentTheme) + '20')
                          .padding({ left: 8, right: 8, top: 3, bottom: 3 })
                          .borderRadius(10)
                      }
                    }
                    .width('100%')
                    .padding({ left: 20, right: 20, top: 12, bottom: 6 })
                    .backgroundColor(ThemeAwareHelper.getTestManagementThemedColor('comp_background_tertiary',
                      this.themeState.currentTheme))
                  }
                  .animation({ duration: 250, delay: sourceIndex * 30, curve: Curve.EaseOut })

                  ForEach(sourceResult.results, (book: NovelSearchResult, bookIndex: number) => {
                    ListItem() {
                      Row() {
                        Column() {
                          Row({ space: 6 }) {
                            Text(book.name)
                              .fontSize(14)
                              .fontWeight(FontWeight.Medium)
                              .fontFamily(this.appFontFamily)
                              .fontColor(book.sourceId === this.currentSourceId
                                ? ThemeAwareHelper.getTestManagementThemedColor('accent_green',
                                  this.themeState.currentTheme)
                                : ThemeAwareHelper.getTestManagementThemedColor('text_primary',
                                  this.themeState.currentTheme))
                              .maxLines(1)
                              .textOverflow({ overflow: TextOverflow.Ellipsis })

                            if (book.author) {
                              Text(`· ${book.author}`)
                                .fontSize(12)
                                .fontFamily(this.appFontFamily)
                                .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_tertiary',
                                  this.themeState.currentTheme))
                                .maxLines(1)
                            }
                          }

                          Text(book.latestChapterTitle || '暂无最新章节信息')
                            .fontSize(12)
                            .fontFamily(this.appFontFamily)
                            .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_tertiary',
                              this.themeState.currentTheme))
                            .margin({ top: 4 })
                            .maxLines(1)
                            .textOverflow({ overflow: TextOverflow.Ellipsis })
                        }
                        .alignItems(HorizontalAlign.Start)
                        .layoutWeight(1)

                        if (book.sourceId === this.currentSourceId) {
                          Row({ space: 4 }) {
                            SymbolGlyph($r('sys.symbol.checkmark_circle_fill'))
                              .fontSize(14)
                              .fontColor([ThemeAwareHelper.getTestManagementThemedColor('accent_green',
                                this.themeState.currentTheme)])
                            Text('当前')
                              .fontSize(12)
                              .fontFamily(this.appFontFamily)
                              .fontColor(ThemeAwareHelper.getTestManagementThemedColor('accent_green',
                                this.themeState.currentTheme))
                          }
                          .padding({ left: 10, right: 10, top: 5, bottom: 5 })
                          .backgroundColor(ThemeAwareHelper.getTestManagementThemedColor('accent_green',
                            this.themeState.currentTheme) + '20')
                          .borderRadius(12)
                        } else {
                          SymbolGlyph($r('sys.symbol.chevron_right'))
                            .fontSize(16)
                            .fontColor([ThemeAwareHelper.getTestManagementThemedColor('text_tertiary',
                              this.themeState.currentTheme)])
                        }
                      }
                      .width('100%')
                      .padding({ left: 20, right: 16, top: 12, bottom: 12 })
                      .backgroundColor(book.sourceId === this.currentSourceId
                        ? ThemeAwareHelper.getTestManagementThemedColor('accent_green', this.themeState.currentTheme) + '08'
                        : Color.Transparent)
                      .onClick(() => this.handleSourceSelected(book))
                    }
                    .animation({ duration: 200, delay: sourceIndex * 30 + bookIndex * 20, curve: Curve.EaseOut })
                  }, (book: NovelSearchResult) => `${sourceResult.sourceId}_${book.bookUrl}`)
                }, (sourceResult: SourceSearchResult) => sourceResult.sourceId)
              }
              .width('100%')
              .height(350)
              .scrollBar(BarState.Auto)
              .edgeEffect(EdgeEffect.Spring)
              .divider({
                strokeWidth: 0.5,
                color: ThemeAwareHelper.getTestManagementThemedColor('divider', this.themeState.currentTheme),
                startMargin: 20,
                endMargin: 16
              })
            }
          }
          .width('100%')
      }
    }
  }

  build() {
    if (this.showChangeSourceDialog) {
      this.buildChangeSourceDialog()
    } else {
      Column()
    }
  }
}
