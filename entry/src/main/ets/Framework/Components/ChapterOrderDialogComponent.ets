import { logger } from 'manxia_core/src/main/ets/Utils/Logger';
import {
  ChapterOrderPersistResult,
  UnifiedChapter,
  UnifiedContent
} from '../../Models/UnifiedContentModels';
import { getNovelTxtTocRuleManager, TxtTocRule } from '../Novel/NovelTxtTocRuleManager';
import {
  ChapterOrderRuleSorter,
  ChapterRuleSortResult,
  getChapterOrderRuleSorter
} from '../Services/ChapterOrderRuleSorter';
import { SourceDialogScaffold } from './SourceDialogScaffold';
import { ThemeAwareHelper, ThemeAwareState } from 'manxia_theme/src/main/ets/Framework/Components/ThemeAware';

const TAG = 'ChapterOrderDialogComponent';

@Component
export struct ChapterOrderDialogComponent {
  @Prop content: UnifiedContent | null = null;
  @Prop themeState: ThemeAwareState = new ThemeAwareState();
  @Prop @Watch('onLoadSignalChanged') loadSignal: number = 0;
  @Prop isSaving: boolean = false;

  onConfirm?: (orderedChapters: UnifiedChapter[]) => Promise<ChapterOrderPersistResult>;
  onRequestSourceOrder?: () => Promise<UnifiedChapter[]>;

  @StorageLink('appFontFamily') appFontFamily: string = 'HarmonyOS Sans';
  @State isVisible: boolean = false;
  @State draftChapters: UnifiedChapter[] = [];
  @State ruleOptions: TxtTocRule[] = [];
  @State selectedRuleId: string = '';
  @State selectedRuleLabel: string = '全部启用规则';
  @State statusText: string = '';
  @State showRulePicker: boolean = false;
  @State isApplyingRule: boolean = false;
  @State isLoadingSourceOrder: boolean = false;
  @State draggingChapterKey: string = '';
  @State draggingChapterTitle: string = '';
  @State dragSourceIndex: number = -1;
  @State dragTargetIndex: number = -1;
  private lastSignal: number = 0;
  private sorter: ChapterOrderRuleSorter = getChapterOrderRuleSorter();

  onLoadSignalChanged(): void {
    if (this.loadSignal > this.lastSignal) {
      this.lastSignal = this.loadSignal;
      this.openDialog();
    }
  }

  private openDialog(): void {
    if (!this.content || this.content.chapters.length === 0) {
      logger.warn(TAG, `打开章节排序对话框失败: ${this.buildContentLogText()}, chapters=0`);
      this.getUIContext().getPromptAction().showToast({ message: '当前没有可排序章节', duration: 1500 });
      return;
    }
    this.draftChapters = this.cloneChapterArray(this.content.chapters);
    this.selectedRuleId = '';
    this.selectedRuleLabel = '全部启用规则';
    this.statusText = this.buildDraftSummaryText();
    this.showRulePicker = false;
    this.clearDragState();
    this.getUIContext().animateTo({ duration: 220, curve: Curve.EaseOut }, () => {
      this.isVisible = true;
    });
    logger.info(TAG, `打开章节排序对话框: ${this.buildContentLogText()}, chapters=${this.draftChapters.length}`);
    void this.loadRules();
  }

  private closeDialog(): void {
    if (this.isSaving || this.isApplyingRule || this.isLoadingSourceOrder) {
      return;
    }
    this.getUIContext().animateTo({ duration: 180, curve: Curve.EaseIn }, () => {
      this.isVisible = false;
      this.draftChapters = [];
      this.statusText = '';
      this.showRulePicker = false;
      this.clearDragState();
    });
    logger.info(TAG, `关闭章节排序对话框并丢弃草稿: ${this.buildContentLogText()}`);
  }

  private async loadRules(): Promise<void> {
    try {
      const manager = getNovelTxtTocRuleManager();
      await manager.initialize();
      this.ruleOptions = manager.getEnabledRules();
      logger.info(TAG, `TXT章节规则加载完成: ${this.buildContentLogText()}, enabledRules=${this.ruleOptions.length}`);
    } catch (error) {
      const message = `加载TXT规则失败: ${String(error)}`;
      logger.warn(TAG, message);
      this.statusText = message;
    }
  }

  private async applyTxtRuleSort(): Promise<void> {
    if (this.isSaving || this.isApplyingRule || this.isLoadingSourceOrder) {
      return;
    }
    if (this.ruleOptions.length === 0) {
      await this.loadRules();
    }
    logger.info(
      TAG,
      `开始应用TXT规则排序草稿: ${this.buildContentLogText()}, ruleId=${this.selectedRuleId}, ` +
        `ruleLabel=${this.selectedRuleLabel}, draftChapters=${this.draftChapters.length}`
    );
    this.animateDialogState(() => {
      this.isApplyingRule = true;
      this.statusText = '正在根据TXT章节规则生成排序草稿...';
      this.showRulePicker = false;
    });
    try {
      const result: ChapterRuleSortResult = this.sorter.sortByTxtRules(
        this.draftChapters,
        this.ruleOptions,
        this.selectedRuleId
      );
      this.animateDialogState(() => {
        this.draftChapters = this.cloneChapterArray(result.orderedChapters);
        this.statusText = `${result.message}，未解析 ${result.unresolvedCount} 章`;
        this.clearDragState();
      }, 220);
      logger.info(
        TAG,
        `TXT规则排序草稿完成: ${this.buildContentLogText()}, appliedRule=${result.appliedRuleName}, ` +
          `matched=${result.matchedCount}, moved=${result.movedCount}, unresolved=${result.unresolvedCount}`
      );
      this.getUIContext().getPromptAction().showToast({ message: result.message, duration: 1600 });
    } catch (error) {
      const message = `应用TXT规则失败: ${String(error)}`;
      logger.error(TAG, message);
      this.statusText = message;
      this.getUIContext().getPromptAction().showToast({ message: message, duration: 2200 });
    } finally {
      this.animateDialogState(() => {
        this.isApplyingRule = false;
      });
    }
  }

  private async restoreSourceOrderDraft(): Promise<void> {
    if (this.isSaving || this.isApplyingRule || this.isLoadingSourceOrder || !this.onRequestSourceOrder) {
      return;
    }
    logger.info(TAG, `开始恢复来源顺序草稿: ${this.buildContentLogText()}, draftChapters=${this.draftChapters.length}`);
    this.animateDialogState(() => {
      this.isLoadingSourceOrder = true;
      this.statusText = '正在生成来源顺序草稿...';
      this.showRulePicker = false;
    });
    try {
      const orderedChapters = await this.onRequestSourceOrder();
      this.animateDialogState(() => {
        this.draftChapters = this.cloneChapterArray(orderedChapters);
        this.statusText = this.buildDraftSummaryText();
        this.clearDragState();
      }, 220);
      logger.info(TAG, `来源顺序草稿恢复完成: ${this.buildContentLogText()}, chapters=${orderedChapters.length}`);
      this.getUIContext().getPromptAction().showToast({ message: '已恢复为来源顺序草稿', duration: 1500 });
    } catch (error) {
      const message = `恢复来源顺序草稿失败: ${String(error)}`;
      logger.error(TAG, message);
      this.statusText = message;
      this.getUIContext().getPromptAction().showToast({ message: message, duration: 2200 });
    } finally {
      this.animateDialogState(() => {
        this.isLoadingSourceOrder = false;
      });
    }
  }

  private async confirmOrder(): Promise<void> {
    if (this.isSaving || this.isApplyingRule || this.isLoadingSourceOrder || !this.onConfirm) {
      return;
    }
    logger.info(
      TAG,
      `开始确认章节排序草稿: ${this.buildContentLogText()}, draftChapters=${this.draftChapters.length}, ` +
        `movedFromContent=${this.countMovedFromContent()}`
    );
    this.animateDialogState(() => {
      this.statusText = '正在确认章节顺序...';
      this.showRulePicker = false;
      this.clearDragState();
    });
    try {
      const result = await this.onConfirm(this.cloneChapterArray(this.draftChapters));
      this.animateDialogState(() => {
        this.statusText = result.message;
      });
      logger.info(
        TAG,
        `章节排序草稿确认完成: ${this.buildContentLogText()}, success=${result.success}, ` +
          `moved=${result.movedCount}, message=${result.message}`
      );
      if (result.success) {
        this.closeAfterSuccess();
      }
    } catch (error) {
      const message = `确认章节排序失败: ${String(error)}`;
      logger.error(TAG, message);
      this.statusText = message;
      this.getUIContext().getPromptAction().showToast({ message: message, duration: 2200 });
    }
  }

  private closeAfterSuccess(): void {
    this.getUIContext().animateTo({ duration: 180, curve: Curve.EaseIn }, () => {
      this.isVisible = false;
      this.draftChapters = [];
      this.statusText = '';
      this.showRulePicker = false;
      this.clearDragState();
    });
    logger.info(TAG, `章节排序对话框确认成功后关闭: ${this.buildContentLogText()}`);
  }

  private moveDraftItem(fromIndex: number, targetIndex: number): void {
    if (this.isSaving || this.isApplyingRule || this.isLoadingSourceOrder) {
      return;
    }
    const count = this.draftChapters.length;
    if (count <= 1 || fromIndex < 0 || fromIndex >= count) {
      return;
    }
    let normalizedTarget = targetIndex;
    if (normalizedTarget < 0) {
      normalizedTarget = 0;
    }
    if (normalizedTarget >= count) {
      normalizedTarget = count - 1;
    }
    if (normalizedTarget === fromIndex) {
      return;
    }

    const moving = this.draftChapters[fromIndex];
    const movingKey = this.buildChapterKey(moving);
    const withoutMoving: UnifiedChapter[] = [];
    for (let i = 0; i < count; i++) {
      if (i !== fromIndex) {
        withoutMoving.push(this.draftChapters[i]);
      }
    }

    const nextDraft: UnifiedChapter[] = [];
    for (let i = 0; i <= withoutMoving.length; i++) {
      if (i === normalizedTarget) {
        nextDraft.push(moving);
      }
      if (i < withoutMoving.length) {
        nextDraft.push(withoutMoving[i]);
      }
    }
    this.animateDialogState(() => {
      this.draftChapters = nextDraft;
      this.draggingChapterKey = movingKey;
      this.draggingChapterTitle = moving.title;
      this.dragSourceIndex = fromIndex;
      this.dragTargetIndex = normalizedTarget;
      this.statusText = this.buildDraftSummaryText();
    }, 180);
    logger.info(
      TAG,
      `章节排序草稿拖拽移动: ${this.buildContentLogText()}, from=${fromIndex}, to=${normalizedTarget}, ` +
        `chapterId=${moving.id}, title=${moving.title}`
    );
  }

  private selectRule(ruleId: string, label: string): void {
    if (this.isSaving || this.isApplyingRule || this.isLoadingSourceOrder) {
      return;
    }
    this.selectedRuleId = ruleId;
    this.selectedRuleLabel = label;
    this.animateDialogState(() => {
      this.showRulePicker = false;
    });
    logger.info(TAG, `选择TXT排序规则: ${this.buildContentLogText()}, ruleId=${ruleId}, label=${label}`);
  }

  private toggleRulePicker(): void {
    if (this.getActionDisabled()) {
      return;
    }
    const nextVisible = !this.showRulePicker;
    this.animateDialogState(() => {
      this.showRulePicker = nextVisible;
    });
    logger.info(TAG, `切换TXT排序规则选择器: ${this.buildContentLogText()}, visible=${nextVisible}`);
  }

  private buildDragEventHandler(): ItemDragEventHandler {
    const handler: ItemDragEventHandler = {
      onLongPress: (index: number) => {
        this.beginDragging(index, 'longPress');
      },
      onDragStart: (index: number) => {
        this.beginDragging(index, 'dragStart');
      },
      onMoveThrough: (from: number, to: number) => {
        this.updateDragTarget(from, to);
      },
      onDrop: (index: number) => {
        this.finishDragging(index);
      }
    };
    return handler;
  }

  private beginDragging(index: number, stage: string): void {
    if (this.getActionDisabled()) {
      return;
    }
    if (index < 0 || index >= this.draftChapters.length) {
      return;
    }
    const chapter = this.draftChapters[index];
    this.animateDialogState(() => {
      this.draggingChapterKey = this.buildChapterKey(chapter);
      this.draggingChapterTitle = chapter.title;
      this.dragSourceIndex = index;
      this.dragTargetIndex = index;
      this.statusText = `正在拖拽「${chapter.title}」，松手后更新草稿顺序`;
    }, 160);
    logger.info(
      TAG,
      `章节拖拽开始: ${this.buildContentLogText()}, stage=${stage}, index=${index}, ` +
        `chapterId=${chapter.id}, title=${chapter.title}`
    );
  }

  private updateDragTarget(from: number, to: number): void {
    if (this.getActionDisabled()) {
      return;
    }
    let normalizedTarget = to;
    if (normalizedTarget < 0) {
      normalizedTarget = 0;
    }
    if (normalizedTarget >= this.draftChapters.length) {
      normalizedTarget = this.draftChapters.length - 1;
    }
    this.dragSourceIndex = from;
    this.dragTargetIndex = normalizedTarget;
    logger.debug(TAG, `章节拖拽经过: ${this.buildContentLogText()}, from=${from}, to=${normalizedTarget}`);
  }

  private finishDragging(index: number): void {
    if (this.draggingChapterKey.length === 0) {
      return;
    }
    const title = this.draggingChapterTitle;
    const from = this.dragSourceIndex;
    const to = this.dragTargetIndex;
    this.animateDialogState(() => {
      this.clearDragState();
      this.statusText = this.buildDraftSummaryText();
    }, 180);
    logger.info(
      TAG,
      `章节拖拽结束: ${this.buildContentLogText()}, from=${from}, to=${to}, dropIndex=${index}, title=${title}`
    );
  }

  private clearDragState(): void {
    this.draggingChapterKey = '';
    this.draggingChapterTitle = '';
    this.dragSourceIndex = -1;
    this.dragTargetIndex = -1;
  }

  private animateDialogState(action: () => void, duration: number = 180): void {
    this.getUIContext().animateTo({ duration: duration, curve: Curve.EaseOut }, action);
  }

  private buildDraftSummaryText(): string {
    const movedCount = this.countMovedFromContent();
    return movedCount > 0 ? `当前草稿已移动 ${movedCount} 章` : '当前草稿与详情页顺序一致';
  }

  private countMovedFromContent(): number {
    if (!this.content) {
      return 0;
    }
    const source = this.content.chapters;
    let moved = 0;
    for (let i = 0; i < source.length && i < this.draftChapters.length; i++) {
      if (source[i].id !== this.draftChapters[i].id || source[i].index !== this.draftChapters[i].index) {
        moved++;
      }
    }
    return moved;
  }

  private cloneChapterArray(chapters: UnifiedChapter[]): UnifiedChapter[] {
    const result: UnifiedChapter[] = [];
    for (let i = 0; i < chapters.length; i++) {
      result.push(this.cloneChapter(chapters[i]));
    }
    return result;
  }

  private cloneChapter(chapter: UnifiedChapter): UnifiedChapter {
    const cloned: UnifiedChapter = {
      id: chapter.id,
      title: chapter.title,
      index: chapter.index,
      isRead: chapter.isRead,
      isDownloaded: chapter.isDownloaded,
      isBookmarked: chapter.isBookmarked,
      originalData: chapter.originalData,
      originalType: chapter.originalType
    };
    if (chapter.pageCount !== undefined) {
      cloned.pageCount = chapter.pageCount;
    }
    if (chapter.wordCount !== undefined) {
      cloned.wordCount = chapter.wordCount;
    }
    if (chapter.publishDate !== undefined) {
      cloned.publishDate = chapter.publishDate;
    }
    return cloned;
  }

  private buildChapterKey(chapter: UnifiedChapter): string {
    return `${chapter.id}_${chapter.index}_${chapter.title}`;
  }

  private isDraggingChapter(chapter: UnifiedChapter): boolean {
    return this.draggingChapterKey.length > 0 && this.draggingChapterKey === this.buildChapterKey(chapter);
  }

  private buildRowSubText(chapter: UnifiedChapter): string {
    if (this.isDraggingChapter(chapter)) {
      if (this.dragTargetIndex >= 0) {
        return `拖拽中，目标位置 ${this.dragTargetIndex + 1}`;
      }
      return '拖拽中，松手后更新草稿';
    }
    return `原序号 ${chapter.index + 1}`;
  }

  private buildContentLogText(): string {
    if (!this.content) {
      return 'content=null';
    }
    return `contentId=${this.content.id}, contentType=${this.content.contentType}, sourceId=${this.content.sourceId}`;
  }

  private getActionDisabled(): boolean {
    return this.isSaving || this.isApplyingRule || this.isLoadingSourceOrder;
  }

  @Builder
  buildHeader() {
    Row({ space: 10 }) {
      Column({ space: 4 }) {
        Text('章节排序')
          .fontSize(20)
          .fontWeight(FontWeight.Medium)
          .fontFamily(this.appFontFamily)
          .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_primary', this.themeState.currentTheme))
        Text(`${this.draftChapters.length} 章`)
          .fontSize(12)
          .fontFamily(this.appFontFamily)
          .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_secondary', this.themeState.currentTheme))
      }
      .layoutWeight(1)
      .alignItems(HorizontalAlign.Start)

      Button() {
        SymbolGlyph($r('sys.symbol.xmark'))
          .fontSize(18)
          .fontColor([ThemeAwareHelper.getTestManagementThemedColor('text_secondary', this.themeState.currentTheme)])
      }
      .width(32)
      .height(32)
      .backgroundColor(Color.Transparent)
      .enabled(!this.getActionDisabled())
      .onClick(() => this.closeDialog())
    }
    .width('100%')
  }

  @Builder
  buildRuleTools() {
    Column({ space: 8 }) {
      Row({ space: 8 }) {
        Button() {
          Row({ space: 6 }) {
            SymbolGlyph($r('sys.symbol.textformat'))
              .fontSize(15)
              .fontColor([ThemeAwareHelper.getTestManagementThemedColor('accent_primary', this.themeState.currentTheme)])
            Text(this.selectedRuleLabel)
              .fontSize(12)
              .fontFamily(this.appFontFamily)
              .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_primary', this.themeState.currentTheme))
              .maxLines(1)
              .textOverflow({ overflow: TextOverflow.Ellipsis })
              .layoutWeight(1)
            SymbolGlyph($r('sys.symbol.chevron_down'))
              .fontSize(13)
              .fontColor([ThemeAwareHelper.getTestManagementThemedColor('text_secondary', this.themeState.currentTheme)])
              .rotate({ angle: this.showRulePicker ? 180 : 0 })
          }
          .width('100%')
        }
        .layoutWeight(1)
        .height(36)
        .padding({ left: 10, right: 10 })
        .backgroundColor(ThemeAwareHelper.getTestManagementThemedColor('comp_background_secondary', this.themeState.currentTheme))
        .borderRadius(12)
        .enabled(!this.getActionDisabled())
        .onClick(() => {
          this.toggleRulePicker();
        })

        Button() {
          if (this.isApplyingRule) {
            LoadingProgress()
              .width(14)
              .height(14)
              .color(Color.White)
          } else {
            SymbolGlyph($r('sys.symbol.checkmark_circle'))
              .fontSize(15)
              .fontColor([Color.White])
          }
        }
        .width(40)
        .height(36)
        .backgroundColor(ThemeAwareHelper.getTestManagementThemedColor('accent_primary', this.themeState.currentTheme))
        .borderRadius(12)
        .enabled(!this.getActionDisabled())
        .onClick(() => {
          void this.applyTxtRuleSort();
        })

        Button() {
          SymbolGlyph($r('sys.symbol.arrow_clockwise'))
            .fontSize(15)
            .fontColor([ThemeAwareHelper.getTestManagementThemedColor('accent_orange', this.themeState.currentTheme)])
        }
        .width(40)
        .height(36)
        .backgroundColor(ThemeAwareHelper.getTestManagementThemedColor('accent_orange', this.themeState.currentTheme) + '15')
        .borderRadius(12)
        .enabled(!this.getActionDisabled())
        .onClick(() => {
          void this.restoreSourceOrderDraft();
        })
      }
      .width('100%')

      if (this.showRulePicker) {
        this.buildRulePicker()
      }
    }
    .width('100%')
  }

  @Builder
  buildRulePicker() {
    List() {
      ListItem() {
        this.buildRuleOption('', '全部启用规则')
      }
      ForEach(this.ruleOptions, (rule: TxtTocRule) => {
        ListItem() {
          this.buildRuleOption(rule.id, rule.name)
        }
      }, (rule: TxtTocRule) => rule.id)
    }
    .width('100%')
    .height(168)
    .scrollBar(BarState.Auto)
    .edgeEffect(EdgeEffect.Spring)
    .divider({ strokeWidth: 0.5, color: ThemeAwareHelper.getTestManagementThemedColor('divider', this.themeState.currentTheme) })
    .backgroundColor(ThemeAwareHelper.getTestManagementThemedColor('comp_background_secondary', this.themeState.currentTheme))
    .borderRadius(12)
    .transition(
      TransitionEffect.OPACITY.animation({ duration: 160, curve: Curve.EaseOut })
        .combine(TransitionEffect.translate({ y: -6 }).animation({ duration: 180, curve: Curve.EaseOut }))
    )
  }

  @Builder
  buildRuleOption(ruleId: string, label: string) {
    Row({ space: 8 }) {
      SymbolGlyph(this.selectedRuleId === ruleId ? $r('sys.symbol.checkmark_circle_fill') : $r('sys.symbol.circle'))
        .fontSize(15)
        .fontColor([this.selectedRuleId === ruleId
          ? ThemeAwareHelper.getTestManagementThemedColor('accent_primary', this.themeState.currentTheme)
          : ThemeAwareHelper.getTestManagementThemedColor('text_muted', this.themeState.currentTheme)])
      Text(label)
        .fontSize(13)
        .fontFamily(this.appFontFamily)
        .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_primary', this.themeState.currentTheme))
        .maxLines(1)
        .textOverflow({ overflow: TextOverflow.Ellipsis })
        .layoutWeight(1)
    }
    .width('100%')
    .height(40)
    .padding({ left: 12, right: 12 })
    .onClick(() => this.selectRule(ruleId, label))
  }

  @Builder
  buildDragHint() {
    Row({ space: 8 }) {
      SymbolGlyph($r('sys.symbol.hand_tap'))
        .fontSize(16)
        .fontColor([ThemeAwareHelper.getTestManagementThemedColor('accent_primary', this.themeState.currentTheme)])

      Column({ space: 2 }) {
        Text('按住章节行拖拽调整顺序')
          .fontSize(12)
          .fontFamily(this.appFontFamily)
          .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_primary', this.themeState.currentTheme))
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
        Text('所有更改会先进入草稿，确认排序后生效')
          .fontSize(10)
          .fontFamily(this.appFontFamily)
          .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_secondary', this.themeState.currentTheme))
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
      }
      .layoutWeight(1)
      .alignItems(HorizontalAlign.Start)
    }
    .width('100%')
    .padding({ left: 12, right: 12, top: 10, bottom: 10 })
    .backgroundColor(ThemeAwareHelper.getTestManagementThemedColor('accent_primary', this.themeState.currentTheme) + '12')
    .borderRadius(12)
    .animation({ duration: 180, curve: Curve.EaseOut })
  }

  @Builder
  buildDragHandle(chapter: UnifiedChapter) {
    Column({ space: 2 }) {
      if (this.isDraggingChapter(chapter)) {
        SymbolGlyph($r('sys.symbol.hand_tap'))
          .fontSize(16)
          .fontColor([ThemeAwareHelper.getTestManagementThemedColor('accent_primary', this.themeState.currentTheme)])
      } else {
        SymbolGlyph($r('sys.symbol.line_3_horizontal'))
          .fontSize(16)
          .fontColor([ThemeAwareHelper.getTestManagementThemedColor('text_muted', this.themeState.currentTheme)])
      }

      Text(this.isDraggingChapter(chapter) ? '拖拽中' : '拖动')
        .fontSize(9)
        .fontFamily(this.appFontFamily)
        .fontColor(this.isDraggingChapter(chapter)
          ? ThemeAwareHelper.getTestManagementThemedColor('accent_primary', this.themeState.currentTheme)
          : ThemeAwareHelper.getTestManagementThemedColor('text_muted', this.themeState.currentTheme))
        .maxLines(1)
    }
    .width(44)
    .alignItems(HorizontalAlign.Center)
    .scale({ x: this.isDraggingChapter(chapter) ? 1.08 : 1, y: this.isDraggingChapter(chapter) ? 1.08 : 1 })
    .animation({ duration: 160, curve: Curve.EaseOut })
  }

  @Builder
  buildDraftList() {
    List() {
      ForEach(this.draftChapters, (chapter: UnifiedChapter, index: number) => {
        ListItem() {
          Row({ space: 10 }) {
            this.buildDragHandle(chapter)

            Text(`${index + 1}`)
              .fontSize(12)
              .fontFamily(this.appFontFamily)
              .fontColor(ThemeAwareHelper.getTestManagementThemedColor('accent_primary', this.themeState.currentTheme))
              .width(36)

            Column({ space: 3 }) {
              Text(chapter.title)
                .fontSize(13)
                .fontFamily(this.appFontFamily)
                .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_primary', this.themeState.currentTheme))
                .maxLines(1)
                .textOverflow({ overflow: TextOverflow.Ellipsis })
              Text(this.buildRowSubText(chapter))
                .fontSize(10)
                .fontFamily(this.appFontFamily)
                .fontColor(this.isDraggingChapter(chapter)
                  ? ThemeAwareHelper.getTestManagementThemedColor('accent_primary', this.themeState.currentTheme)
                  : ThemeAwareHelper.getTestManagementThemedColor('text_muted', this.themeState.currentTheme))
                .maxLines(1)
                .textOverflow({ overflow: TextOverflow.Ellipsis })
            }
            .alignItems(HorizontalAlign.Start)
            .layoutWeight(1)
          }
          .width('100%')
          .height(52)
          .padding({ left: 12, right: 12 })
          .backgroundColor(this.isDraggingChapter(chapter)
            ? ThemeAwareHelper.getTestManagementThemedColor('accent_primary', this.themeState.currentTheme) + '12'
            : Color.Transparent)
          .borderRadius(12)
          .border({
            width: this.isDraggingChapter(chapter) ? 1 : 0,
            color: this.isDraggingChapter(chapter)
              ? ThemeAwareHelper.getTestManagementThemedColor('accent_primary', this.themeState.currentTheme) + '55'
              : Color.Transparent
          })
          .shadow({
            radius: this.isDraggingChapter(chapter) ? 12 : 0,
            color: this.isDraggingChapter(chapter)
              ? ThemeAwareHelper.getTestManagementThemedColor('accent_primary', this.themeState.currentTheme) + '22'
              : Color.Transparent,
            offsetX: 0,
            offsetY: this.isDraggingChapter(chapter) ? 4 : 0
          })
          .scale({ x: this.isDraggingChapter(chapter) ? 1.01 : 1, y: this.isDraggingChapter(chapter) ? 1.01 : 1 })
          .animation({ duration: 180, curve: Curve.EaseOut })
        }
      }, (chapter: UnifiedChapter) => this.buildChapterKey(chapter))
      .onMove((from: number, to: number) => {
        this.moveDraftItem(from, to);
      }, this.buildDragEventHandler())
    }
    .width('100%')
    .height(380)
    .scrollBar(BarState.Auto)
    .edgeEffect(EdgeEffect.Spring)
    .divider({ strokeWidth: 0.5, color: ThemeAwareHelper.getTestManagementThemedColor('divider', this.themeState.currentTheme) })
    .backgroundColor(ThemeAwareHelper.getTestManagementThemedColor('comp_background_secondary', this.themeState.currentTheme))
    .borderRadius(14)
  }

  @Builder
  buildFooter() {
    Column({ space: 10 }) {
      Text(this.statusText)
        .fontSize(12)
        .fontFamily(this.appFontFamily)
        .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_secondary', this.themeState.currentTheme))
        .width('100%')
        .maxLines(2)
        .textOverflow({ overflow: TextOverflow.Ellipsis })

      Row({ space: 10 }) {
        Button('取消')
          .layoutWeight(1)
          .height(40)
          .fontSize(14)
          .fontFamily(this.appFontFamily)
          .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_primary', this.themeState.currentTheme))
          .backgroundColor(ThemeAwareHelper.getTestManagementThemedColor('comp_background_secondary', this.themeState.currentTheme))
          .borderRadius(20)
          .enabled(!this.getActionDisabled())
          .onClick(() => this.closeDialog())

        Button() {
          Row({ space: 6 }) {
            if (this.isSaving) {
              LoadingProgress()
                .width(14)
                .height(14)
                .color(Color.White)
            }
            Text(this.isSaving ? '确认中' : '确认排序')
              .fontSize(14)
              .fontFamily(this.appFontFamily)
              .fontColor(Color.White)
          }
        }
        .layoutWeight(1)
        .height(40)
        .backgroundColor(ThemeAwareHelper.getTestManagementThemedColor('accent_primary', this.themeState.currentTheme))
        .borderRadius(20)
        .enabled(!this.getActionDisabled())
        .onClick(() => {
          void this.confirmOrder();
        })
      }
      .width('100%')
    }
    .width('100%')
  }

  build() {
    if (this.isVisible) {
      SourceDialogScaffold({
        themeState: this.themeState,
        closeOnMaskTap: !this.getActionDisabled(),
        onMaskTap: () => this.closeDialog(),
        dialogWidth: '90%',
        maxWidth: 620,
        maxHeight: '88%',
        contentPadding: 24,
        contentScrollable: true,
        useMaskBlur: true
      }) {
        Column({ space: 20 }) {
          this.buildHeader()
          this.buildRuleTools()
          this.buildDragHint()
          this.buildDraftList()
          this.buildFooter()
        }
        .width('100%')
      }
    }
  }
}
