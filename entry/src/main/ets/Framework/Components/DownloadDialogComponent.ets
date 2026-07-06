// 文件路径: entry/src/main/ets/Framework/Components/DownloadDialogComponent.ets
// 职责: 下载/缓存章节选择对话框组件，从UnifiedDetailPage提取的独立组件

import { ThemeAwareState, ThemeAwareHelper } from './ThemeAware';
import { SourceDialogScaffold } from './SourceDialogScaffold';
import { UnifiedContent, UnifiedChapter, UnifiedContentType } from '../../Models/UnifiedContentModels';

@Component
export struct DownloadDialogComponent {
  // 从父组件接收的属性
  @Prop content: UnifiedContent | null = null;
  @Prop themeState: ThemeAwareState = new ThemeAwareState();
  @StorageLink('appFontFamily') appFontFamily: string = 'HarmonyOS Sans';
  @Prop @Watch('onLoadSignalChanged') loadSignal: number = 0;
  @Prop @Watch('onCacheStateSignalChanged') cacheStateSignal: number = 0;

  // 下载进度（从父组件同步）
  @Prop isDownloading: boolean = false;
  @Prop downloadProgressCurrent: number = 0;
  @Prop downloadProgressTotal: number = 0;
  @Prop downloadCurrentChapterTitle: string = '';

  // 回调函数
  onStartDownload?: (selectedIndexes: number[]) => void;
  onClearCache?: (contentType: string) => void;
  isChapterFullyCached?: (chapterId: string) => boolean;
  isChapterPartiallyCached?: (chapterId: string) => boolean;
  getNovelCacheActionTitle?: () => string;
  getNovelDownloadedTagLabel?: () => string;
  getNovelCacheCountActionLabel?: (count: number) => string;
  isCurrentNovelAudioSource?: () => boolean;

  // 对话框内部状态
  @State showDownloadDialog: boolean = false;
  @State downloadSelectionMode: 'range' | 'individual' = 'range';
  @State downloadRangeStart: number = 0;
  @State downloadRangeEnd: number = 0;
  @State downloadSelectedChapters: Set<number> = new Set();
  @State downloadChapterListExpanded: boolean = false;

  // 生命周期
  onLoadSignalChanged(): void {
    if (this.loadSignal > 0) {
      this.showDownloadOptions();
    }
  }

  onCacheStateSignalChanged(): void {
    if (this.showDownloadDialog) {
      this.reconcileSelectionWithCacheState();
    }
  }

  // ==================== 对话框控制 ====================

  showDownloadOptions(): void {
    if (!this.content || this.content.chapters.length === 0) {
      return;
    }

    this.downloadSelectionMode = 'range';
    this.downloadChapterListExpanded = false;

    const firstUncachedIndex = this.findFirstDownloadableChapterIndex();
    const lastUncachedIndex = this.findLastDownloadableChapterIndex();

    this.downloadRangeStart = firstUncachedIndex;
    this.downloadRangeEnd = lastUncachedIndex >= firstUncachedIndex ? lastUncachedIndex : firstUncachedIndex;
    this.downloadSelectedChapters = new Set<number>();
    this.getUIContext().animateTo({
      duration: 220,
      curve: Curve.EaseOut
    }, () => {
      this.showDownloadDialog = true;
    });
  }

  closeDownloadDialog(): void {
    this.getUIContext().animateTo({
      duration: 180,
      curve: Curve.EaseIn
    }, () => {
      this.showDownloadDialog = false;
    });
  }

  // ==================== 选择逻辑 ====================

  private isChapterCachedForDownload(index: number): boolean {
    if (!this.content || index < 0 || index >= this.content.chapters.length) {
      return true;
    }
    const chapter = this.content.chapters[index];
    if (this.isChapterFullyCached) {
      return this.isChapterFullyCached(chapter.id);
    }
    return chapter.isDownloaded;
  }

  private findFirstDownloadableChapterIndex(): number {
    if (!this.content || this.content.chapters.length === 0) {
      return 0;
    }
    for (let i = 0; i < this.content.chapters.length; i++) {
      if (!this.isChapterCachedForDownload(i)) {
        return i;
      }
    }
    return 0;
  }

  private findLastDownloadableChapterIndex(): number {
    if (!this.content || this.content.chapters.length === 0) {
      return 0;
    }
    for (let i = this.content.chapters.length - 1; i >= 0; i--) {
      if (!this.isChapterCachedForDownload(i)) {
        return i;
      }
    }
    return -1;
  }

  private reconcileSelectionWithCacheState(): void {
    if (!this.content) {
      return;
    }

    if (this.downloadSelectionMode === 'individual') {
      const nextSelected: Set<number> = new Set<number>();
      this.downloadSelectedChapters.forEach((index: number) => {
        if (!this.isChapterCachedForDownload(index)) {
          nextSelected.add(index);
        }
      });
      this.downloadSelectedChapters = nextSelected;
      return;
    }

    if (this.getSelectedChapterCount() > 0) {
      return;
    }

    const firstDownloadable = this.findFirstDownloadableChapterIndex();
    this.downloadRangeStart = firstDownloadable;
    this.downloadRangeEnd = firstDownloadable;
  }

  private toggleChapterSelection(index: number): void {
    if (this.isChapterCachedForDownload(index)) {
      return;
    }

    const newSet = new Set(this.downloadSelectedChapters);
    if (newSet.has(index)) {
      newSet.delete(index);
    } else {
      newSet.add(index);
    }
    this.downloadSelectedChapters = newSet;
  }

  private getSelectedChapterCount(): number {
    if (!this.content) {
      return 0;
    }

    if (this.downloadSelectionMode === 'range') {
      let count = 0;
      for (let i = this.downloadRangeStart; i <= this.downloadRangeEnd; i++) {
        if (!this.isChapterCachedForDownload(i)) {
          count++;
        }
      }
      return count;
    }
    let count = 0;
    this.downloadSelectedChapters.forEach((index: number) => {
      if (!this.isChapterCachedForDownload(index)) {
        count++;
      }
    });
    return count;
  }

  private executeDownloadSelected(): void {
    if (!this.content) {
      return;
    }

    const selectedCount = this.getSelectedChapterCount();
    if (selectedCount === 0) {
      this.getUIContext().getPromptAction().showToast({
        message: this.content.contentType === UnifiedContentType.NOVEL && this.isCurrentNovelAudioSource?.()
          ? '未选择要缓存的音频章节'
          : '未选择要缓存的章节'
      });
      return;
    }

    const selectedIndexes: number[] = [];
    if (this.downloadSelectionMode === 'range') {
      for (let i = this.downloadRangeStart; i <= this.downloadRangeEnd; i++) {
        if (!this.isChapterCachedForDownload(i)) {
          selectedIndexes.push(i);
        }
      }
    } else {
      this.downloadSelectedChapters.forEach((idx: number) => {
        if (!this.isChapterCachedForDownload(idx)) {
          selectedIndexes.push(idx);
        }
      });
      selectedIndexes.sort((a: number, b: number) => a - b);
    }

    this.closeDownloadDialog();
    this.onStartDownload?.(selectedIndexes);
  }

  private handleClearCache(): void {
    this.closeDownloadDialog();
    if (this.content?.contentType === UnifiedContentType.NOVEL) {
      this.onClearCache?.('novel');
    } else {
      this.onClearCache?.('manga');
    }
  }

  // ==================== Builder 方法 ====================

  @Builder
  private buildSingleChapterDownloadView() {
    Column({ space: 16 }) {
      Row({ space: 12 }) {
        Column() {
          SymbolGlyph($r('sys.symbol.arrow_down_circle'))
            .fontSize(24)
            .fontColor([ThemeAwareHelper.getTestManagementThemedColor('accent_primary', this.themeState.currentTheme)])
        }
        .width(48)
        .height(48)
        .backgroundColor(ThemeAwareHelper.getTestManagementThemedColor('accent_primary', this.themeState.currentTheme) + '15')
        .borderRadius(12)
        .justifyContent(FlexAlign.Center)

        Column({ space: 4 }) {
          Text(this.content?.chapters[0]?.title || '第1章')
            .fontSize(15)
            .fontWeight(FontWeight.Medium)
            .fontFamily(this.appFontFamily)
            .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_primary', this.themeState.currentTheme))
            .maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis })

          Row({ space: 8 }) {
            if (this.content?.chapters[0]?.pageCount && this.content.chapters[0].pageCount > 0) {
              Text(`${this.content.chapters[0].pageCount} 页`)
                .fontSize(12)
                .fontFamily(this.appFontFamily)
                .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_muted', this.themeState.currentTheme))
            }

            if (this.isChapterCachedForDownload(0)) {
              Row({ space: 4 }) {
                SymbolGlyph($r('sys.symbol.checkmark_circle_fill'))
                  .fontSize(12)
                  .fontColor([ThemeAwareHelper.getTestManagementThemedColor('accent_green', this.themeState.currentTheme)])
                Text('已缓存')
                  .fontSize(12)
                  .fontFamily(this.appFontFamily)
                  .fontColor(ThemeAwareHelper.getTestManagementThemedColor('accent_green', this.themeState.currentTheme))
              }
            }
          }
        }
        .alignItems(HorizontalAlign.Start)
        .layoutWeight(1)
      }
      .width('100%')
      .padding(12)
      .backgroundColor(ThemeAwareHelper.getTestManagementThemedColor('comp_background_tertiary', this.themeState.currentTheme))
      .borderRadius(12)

      if (this.isChapterCachedForDownload(0)) {
        Text('该章节已缓存，可离线阅读')
          .fontSize(13)
          .fontFamily(this.appFontFamily)
          .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_secondary', this.themeState.currentTheme))
          .width('100%')
          .textAlign(TextAlign.Center)
      } else {
        Text('点击下载按钮缓存该章节，缓存后可离线阅读')
          .fontSize(13)
          .fontFamily(this.appFontFamily)
          .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_secondary', this.themeState.currentTheme))
          .width('100%')
          .textAlign(TextAlign.Center)
      }
    }
    .width('100%')
  }

  @Builder
  buildDownloadDialog() {
    if (this.showDownloadDialog && this.content) {
      SourceDialogScaffold({
        themeState: this.themeState,
        onMaskTap: () => this.closeDownloadDialog(),
        dialogWidth: '90%',
        maxWidth: 400,
        contentPadding: 24,
        useMaskBlur: true
      }) {
        Column({ space: 20 }) {
            // 标题栏
            Row() {
              Text(this.content.contentType === UnifiedContentType.NOVEL
                ? (this.getNovelCacheActionTitle?.() || '缓存章节')
                : '缓存章节')
                .fontSize(20)
                .fontWeight(FontWeight.Medium)
                .fontFamily(this.appFontFamily)
                .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_primary', this.themeState.currentTheme))

              Blank()

              Button() {
                SymbolGlyph($r('sys.symbol.xmark'))
                  .fontSize(18)
                  .fontColor([ThemeAwareHelper.getTestManagementThemedColor('text_secondary',
                    this.themeState.currentTheme)])
              }
              .width(32)
              .height(32)
              .backgroundColor(Color.Transparent)
              .onClick(() => this.closeDownloadDialog())
            }
            .width('100%')

            // 根据章节数量显示不同的UI
            if (this.content.chapters.length === 1) {
              this.buildSingleChapterDownloadView()
            } else {
              // 多章节：显示完整的选择界面
              Row({ space: 8 }) {
                Button() {
                  Row({ space: 6 }) {
                    SymbolGlyph($r('sys.symbol.slider_horizontal_2_1'))
                      .fontSize(14)
                      .fontColor([this.downloadSelectionMode === 'range'
                        ? Color.White
                        : ThemeAwareHelper.getTestManagementThemedColor('text_primary', this.themeState.currentTheme)])
                    Text('区间选择')
                      .fontSize(13)
                      .fontFamily(this.appFontFamily)
                      .fontColor(this.downloadSelectionMode === 'range'
                        ? Color.White
                        : ThemeAwareHelper.getTestManagementThemedColor('text_primary', this.themeState.currentTheme))
                  }
                }
                .height(36)
                .padding({ left: 14, right: 14 })
                .backgroundColor(this.downloadSelectionMode === 'range'
                  ? ThemeAwareHelper.getTestManagementThemedColor('accent_primary', this.themeState.currentTheme)
                  : ThemeAwareHelper.getTestManagementThemedColor('comp_background_tertiary',
                    this.themeState.currentTheme))
                .borderRadius(18)
                .animation({ duration: 200, curve: Curve.EaseOut })
                .onClick(() => {
                  this.getUIContext().animateTo({ duration: 200, curve: Curve.EaseOut }, () => {
                    this.downloadSelectionMode = 'range';
                  });
                })

                Button() {
                  Row({ space: 6 }) {
                    SymbolGlyph($r('sys.symbol.checkmark_circle'))
                      .fontSize(14)
                      .fontColor([this.downloadSelectionMode === 'individual'
                        ? Color.White
                        : ThemeAwareHelper.getTestManagementThemedColor('text_primary', this.themeState.currentTheme)])
                    Text('单独选择')
                      .fontSize(13)
                      .fontFamily(this.appFontFamily)
                      .fontColor(this.downloadSelectionMode === 'individual'
                        ? Color.White
                        : ThemeAwareHelper.getTestManagementThemedColor('text_primary', this.themeState.currentTheme))
                  }
                }
                .height(36)
                .padding({ left: 14, right: 14 })
                .backgroundColor(this.downloadSelectionMode === 'individual'
                  ? ThemeAwareHelper.getTestManagementThemedColor('accent_primary', this.themeState.currentTheme)
                  : ThemeAwareHelper.getTestManagementThemedColor('comp_background_tertiary',
                    this.themeState.currentTheme))
                .borderRadius(18)
                .animation({ duration: 200, curve: Curve.EaseOut })
                .onClick(() => {
                  this.getUIContext().animateTo({ duration: 200, curve: Curve.EaseOut }, () => {
                    this.downloadSelectionMode = 'individual';
                    this.downloadChapterListExpanded = true;
                  });
                })
              }
              .width('100%')

              // 区间选择模式
              if (this.downloadSelectionMode === 'range') {
                Column({ space: 12 }) {
                  Row() {
                    Text(`第 ${this.downloadRangeStart + 1} 章`)
                      .fontSize(14)
                      .fontWeight(FontWeight.Medium)
                      .fontFamily(this.appFontFamily)
                      .fontColor(ThemeAwareHelper.getTestManagementThemedColor('accent_primary',
                        this.themeState.currentTheme))

                    Text(' — ')
                      .fontSize(14)
                      .fontFamily(this.appFontFamily)
                      .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_muted',
                        this.themeState.currentTheme))

                    Text(`第 ${this.downloadRangeEnd + 1} 章`)
                      .fontSize(14)
                      .fontWeight(FontWeight.Medium)
                      .fontFamily(this.appFontFamily)
                      .fontColor(ThemeAwareHelper.getTestManagementThemedColor('accent_primary',
                        this.themeState.currentTheme))

                    Blank()

                    Text(`可缓存 ${this.getSelectedChapterCount()} 章`)
                      .fontSize(12)
                      .fontFamily(this.appFontFamily)
                      .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_secondary',
                        this.themeState.currentTheme))
                  }
                  .width('100%')

                  Column({ space: 4 }) {
                    Text('开始章节')
                      .fontSize(12)
                      .fontFamily(this.appFontFamily)
                      .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_muted',
                        this.themeState.currentTheme))

                    Slider({
                      value: this.downloadRangeStart,
                      min: 0,
                      max: this.content.chapters.length - 1,
                      step: 1,
                      style: SliderStyle.OutSet
                    })
                      .blockColor(ThemeAwareHelper.getTestManagementThemedColor('accent_primary',
                        this.themeState.currentTheme))
                      .trackColor(ThemeAwareHelper.getTestManagementThemedColor('comp_background_tertiary',
                        this.themeState.currentTheme))
                      .selectedColor(ThemeAwareHelper.getTestManagementThemedColor('accent_primary',
                        this.themeState.currentTheme))
                      .onChange((value: number) => {
                        this.downloadRangeStart = Math.round(value);
                        if (this.downloadRangeStart > this.downloadRangeEnd) {
                          this.downloadRangeEnd = this.downloadRangeStart;
                        }
                      })
                  }
                  .width('100%')
                  .alignItems(HorizontalAlign.Start)

                  Column({ space: 4 }) {
                    Text('结束章节')
                      .fontSize(12)
                      .fontFamily(this.appFontFamily)
                      .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_muted',
                        this.themeState.currentTheme))

                    Slider({
                      value: this.downloadRangeEnd,
                      min: 0,
                      max: this.content.chapters.length - 1,
                      step: 1,
                      style: SliderStyle.OutSet
                    })
                      .blockColor(ThemeAwareHelper.getTestManagementThemedColor('accent_primary',
                        this.themeState.currentTheme))
                      .trackColor(ThemeAwareHelper.getTestManagementThemedColor('comp_background_tertiary',
                        this.themeState.currentTheme))
                      .selectedColor(ThemeAwareHelper.getTestManagementThemedColor('accent_primary',
                        this.themeState.currentTheme))
                      .onChange((value: number) => {
                        this.downloadRangeEnd = Math.round(value);
                        if (this.downloadRangeEnd < this.downloadRangeStart) {
                          this.downloadRangeStart = this.downloadRangeEnd;
                        }
                      })
                  }
                  .width('100%')
                  .alignItems(HorizontalAlign.Start)

                  Row({ space: 8 }) {
                    Button('全部')
                      .fontSize(12)
                      .fontFamily(this.appFontFamily)
                      .height(28)
                      .padding({ left: 12, right: 12 })
                      .backgroundColor(ThemeAwareHelper.getTestManagementThemedColor('comp_background_tertiary',
                        this.themeState.currentTheme))
                      .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_primary',
                        this.themeState.currentTheme))
                      .borderRadius(14)
                      .onClick(() => {
                        this.getUIContext().animateTo({ duration: 150 }, () => {
                          this.downloadRangeStart = 0;
                          this.downloadRangeEnd = this.content!.chapters.length - 1;
                        });
                      })

                    Button('前50章')
                      .fontSize(12)
                      .fontFamily(this.appFontFamily)
                      .height(28)
                      .padding({ left: 12, right: 12 })
                      .backgroundColor(ThemeAwareHelper.getTestManagementThemedColor('comp_background_tertiary',
                        this.themeState.currentTheme))
                      .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_primary',
                        this.themeState.currentTheme))
                      .borderRadius(14)
                      .onClick(() => {
                        this.getUIContext().animateTo({ duration: 150 }, () => {
                          this.downloadRangeStart = 0;
                          this.downloadRangeEnd = Math.min(49, this.content!.chapters.length - 1);
                        });
                      })

                    Button('后50章')
                      .fontSize(12)
                      .fontFamily(this.appFontFamily)
                      .height(28)
                      .padding({ left: 12, right: 12 })
                      .backgroundColor(ThemeAwareHelper.getTestManagementThemedColor('comp_background_tertiary',
                        this.themeState.currentTheme))
                      .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_primary',
                        this.themeState.currentTheme))
                      .borderRadius(14)
                      .onClick(() => {
                        this.getUIContext().animateTo({ duration: 150 }, () => {
                          const total = this.content!.chapters.length;
                          this.downloadRangeStart = Math.max(0, total - 50);
                          this.downloadRangeEnd = total - 1;
                        });
                      })
                  }
                  .width('100%')
                }
                .width('100%')
                .animation({ duration: 200, curve: Curve.EaseOut })
              } else {
                // 单独选择模式
                Column({ space: 8 }) {
                  Row() {
                    Text(`已选择 ${this.getSelectedChapterCount()} 章`)
                      .fontSize(14)
                      .fontFamily(this.appFontFamily)
                      .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_secondary',
                        this.themeState.currentTheme))

                    Blank()

                    Button(this.downloadChapterListExpanded ? '收起' : '展开列表')
                      .fontSize(12)
                      .fontFamily(this.appFontFamily)
                      .height(28)
                      .padding({ left: 12, right: 12 })
                      .backgroundColor(ThemeAwareHelper.getTestManagementThemedColor('comp_background_tertiary',
                        this.themeState.currentTheme))
                      .fontColor(ThemeAwareHelper.getTestManagementThemedColor('accent_primary',
                        this.themeState.currentTheme))
                      .borderRadius(14)
                      .onClick(() => {
                        this.getUIContext().animateTo({ duration: 200, curve: Curve.EaseOut }, () => {
                          this.downloadChapterListExpanded = !this.downloadChapterListExpanded;
                        });
                      })
                  }
                  .width('100%')

                  if (this.downloadChapterListExpanded) {
                    List() {
                      ForEach(this.content.chapters, (chapter: UnifiedChapter, index: number) => {
                        ListItem() {
                          Row() {
                            Checkbox({ name: `chapter_${index}` })
                              .select(this.downloadSelectedChapters.has(index))
                              .selectedColor(ThemeAwareHelper.getTestManagementThemedColor('accent_primary',
                                this.themeState.currentTheme))
                              .enabled(!this.isChapterCachedForDownload(index))
                              .hitTestBehavior(HitTestMode.Block)
                              .onChange((checked: boolean) => {
                                if (this.isChapterCachedForDownload(index)) return;

                                const newSet = new Set(this.downloadSelectedChapters);
                                if (checked) {
                                  newSet.add(index);
                                } else {
                                  newSet.delete(index);
                                }
                                this.downloadSelectedChapters = newSet;
                              })

                            Text(`${index + 1}. ${chapter.title}`)
                              .fontSize(13)
                              .fontFamily(this.appFontFamily)
                              .fontColor(this.isChapterCachedForDownload(index)
                                ? ThemeAwareHelper.getTestManagementThemedColor('text_muted',
                                  this.themeState.currentTheme)
                                : ThemeAwareHelper.getTestManagementThemedColor('text_primary',
                                  this.themeState.currentTheme))
                              .maxLines(1)
                              .textOverflow({ overflow: TextOverflow.Ellipsis })
                              .layoutWeight(1)

                            if (this.isChapterCachedForDownload(index)) {
                              Text(this.content?.contentType === UnifiedContentType.NOVEL
                                ? (this.getNovelDownloadedTagLabel?.() || '已缓存')
                                : '已缓存')
                                .fontSize(11)
                                .fontFamily(this.appFontFamily)
                                .fontColor(ThemeAwareHelper.getTestManagementThemedColor('accent_green',
                                  this.themeState.currentTheme))
                            } else if (this.isChapterPartiallyCached?.(chapter.id)) {
                              Text('部分缓存')
                                .fontSize(11)
                                .fontFamily(this.appFontFamily)
                                .fontColor(ThemeAwareHelper.getTestManagementThemedColor('accent_orange',
                                  this.themeState.currentTheme))
                            }
                          }
                          .width('100%')
                          .height(40)
                          .padding({ left: 8, right: 8 })
                          .backgroundColor(this.downloadSelectedChapters.has(index)
                            ? ThemeAwareHelper.getTestManagementThemedColor('accent_primary',
                              this.themeState.currentTheme) + '15'
                            : Color.Transparent)
                          .borderRadius(8)
                          .enabled(!this.isChapterCachedForDownload(index))
                          .opacity(this.isChapterCachedForDownload(index) ? 0.5 : 1)
                          .onClick(() => this.toggleChapterSelection(index))
                        }
                      }, (chapter: UnifiedChapter,
                        index: number) => `dl_chapter_${index}_${chapter.id}_${this.downloadSelectedChapters.has(index)}_${this.cacheStateSignal}_${this.isChapterCachedForDownload(index)}`)
                    }
                    .width('100%')
                    .height(200)
                    .scrollBar(BarState.Auto)
                    .edgeEffect(EdgeEffect.Spring)
                    .cachedCount(10)
                  }

                  Row({ space: 8 }) {
                    Button('全选')
                      .fontSize(12)
                      .fontFamily(this.appFontFamily)
                      .height(28)
                      .padding({ left: 12, right: 12 })
                      .backgroundColor(ThemeAwareHelper.getTestManagementThemedColor('comp_background_tertiary',
                        this.themeState.currentTheme))
                      .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_primary',
                        this.themeState.currentTheme))
                      .borderRadius(14)
                      .onClick(() => {
                        const newSet = new Set<number>();
                        const total = this.content ? this.content.chapters.length : 0;
                        for (let i = 0; i < total; i++) {
                          if (!this.isChapterCachedForDownload(i)) {
                            newSet.add(i);
                          }
                        }
                        this.downloadSelectedChapters = newSet;
                      })

                    Button('全不选')
                      .fontSize(12)
                      .fontFamily(this.appFontFamily)
                      .height(28)
                      .padding({ left: 12, right: 12 })
                      .backgroundColor(ThemeAwareHelper.getTestManagementThemedColor('comp_background_tertiary',
                        this.themeState.currentTheme))
                      .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_primary',
                        this.themeState.currentTheme))
                      .borderRadius(14)
                      .onClick(() => {
                        this.downloadSelectedChapters = new Set();
                      })
                  }
                  .width('100%')
                }
                .width('100%')
                .animation({ duration: 200, curve: Curve.EaseOut })
              }
            }

            // 底部按钮
            Row({ space: 12 }) {
              Button() {
                Row({ space: 6 }) {
                  SymbolGlyph($r('sys.symbol.trash'))
                    .fontSize(16)
                    .fontColor([Color.White])
                  Text(`清除缓存`)
                    .fontSize(14)
                    .fontFamily(this.appFontFamily)
                    .fontColor(Color.White)
                }
              }
              .fontSize(14)
              .fontFamily(this.appFontFamily)
              .height(44)
              .backgroundColor('#FF5252')
              .layoutWeight(1)
              .borderRadius(22)
              .onClick(() => this.handleClearCache())

              Button() {
                Row({ space: 6 }) {
                  SymbolGlyph($r('sys.symbol.arrow_down_circle'))
                    .fontSize(16)
                    .fontColor([Color.White])
                  Text(this.content.contentType === UnifiedContentType.NOVEL
                    ? (this.getNovelCacheCountActionLabel?.(this.getSelectedChapterCount()) || `缓存 ${this.getSelectedChapterCount()} 章`)
                    : `缓存 ${this.getSelectedChapterCount()} 章`)
                    .fontSize(14)
                    .fontFamily(this.appFontFamily)
                    .fontColor(Color.White)
                }
              }
              .height(44)
              .backgroundColor(ThemeAwareHelper.getTestManagementThemedColor('accent_primary',
                this.themeState.currentTheme))
              .layoutWeight(2)
              .borderRadius(22)
              .enabled(this.getSelectedChapterCount() > 0 && !this.isDownloading)
              .onClick(() => this.executeDownloadSelected())
            }
            .width('100%')
          }
          .width('100%')
      }
    }
  }

  build() {
    if (this.showDownloadDialog && this.content) {
      this.buildDownloadDialog()
    } else {
      Column()
    }
  }
}
