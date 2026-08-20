// 文件路径: entry/src/main/ets/Framework/Components/ReadAloudCacheDialogComponent.ets
// 职责: 听书缓存对话框组件，从UnifiedDetailPage提取的独立组件


import { promptAction } from '@kit.ArkUI';
import { logger } from 'manxia_core/src/main/ets/Utils/Logger';
import { ThemeAwareState, ThemeAwareHelper } from 'manxia_theme/src/main/ets/Framework/Components/ThemeAware';
import { SourceDialogScaffold } from './SourceDialogScaffold';
import { SettingsPageSurfaceManager, SettingsPageSurfaceStyle } from 'manxia_features_ui/src/main/ets/pages/settings/SettingsPageSurfaceManager';
import { SettingsGlassStyleHelper } from 'manxia_features_ui/src/main/ets/pages/settings/SettingsGlassStyleHelper';
import { eventBus, GameEvent, IEventPayload, ReadAloudCacheUpdatedPayload } from '../EventBus';
import {
  UnifiedContent,
  UnifiedContentType,
  UnifiedReadStatus
} from 'manxia_core/src/main/ets/Models/UnifiedContentModels';
import { EBookAdapter } from '../Adapters/UnifiedContentAdapter';
import { buildLocalTextNovelBookId } from '../Adapters/LocalTextNovelAdapter';
import {
  RemoteReadAloudCacheChapterSummary,
  RemoteReadAloudCacheChapterDetail,
  getRemoteReadAloudCacheService,
  RemoteReadAloudCacheBookSummary,
  RemoteReadAloudCacheManifestSummary,
  RemoteReadAloudCacheSegmentDetail,
  RemoteReadAloudCacheSegmentSummary,
  RemoteReadAloudCacheTargetSuggestion,
  RemoteReadAloudCacheTargetSegment,
  RemoteReadAloudCacheTaskProgress
} from '../ReadAloud/RemoteReadAloudCacheService';
import {
  DEFAULT_REMOTE_READ_ALOUD_PRESET_ID,
  DEFAULT_REMOTE_READ_ALOUD_SETTINGS,
  extractRemoteReadAloudPresetConfig,
  getXiaomiMimoRemoteReadAloudVoiceLabel,
  hasRemoteReadAloudStylePrompt,
  isXiaomiMimoRemoteReadAloud,
  isRemoteReadAloudPresetConfigEqual,
  mergeRemoteReadAloudSettings,
  normalizeRemoteReadAloudStylePrompt,
  RemoteReadAloudChoiceOption,
  RemoteReadAloudPreset,
  RemoteReadAloudPresetConfig,
  RemoteReadAloudSettings,
  RemoteReadAloudStyleCategory,
  toggleRemoteReadAloudStylePrompt,
  XIAOMI_MIMO_REMOTE_READ_ALOUD_STYLE_CATEGORIES,
  XIAOMI_MIMO_REMOTE_READ_ALOUD_VOICE_OPTIONS
} from 'manxia_core/src/main/ets/Models/TextReaderModels';
import { EBookFormat } from 'manxia_core/src/main/ets/Models/EBookModels';
import { AppGuideStep } from 'manxia_core/src/main/ets/Framework/Managers/AppGuideManager';
import { GuideHighlightRect } from './AppGuideOverlay';

const TAG = 'ReadAloudCacheDialogComponent';

@Component
export struct ReadAloudCacheDialogComponent {
  // 从父组件接收的属性
  @Prop content: UnifiedContent | null = null;
  @Prop supportsReadAloudCache: boolean = false;
  @Prop isCurrentNovelAudioSource: boolean = false;
  @Prop isLocalTxtNovelEBook: boolean = false;
  @Prop @Watch('onLoadSignalChanged') loadSignal: number = 0;
  @StorageLink('appFontFamily') appFontFamily: string = 'HarmonyOS Sans';

  // 回调函数
  onOpenCacheDialog?: (trigger: string) => void;
  onSummaryChanged?: (summary: RemoteReadAloudCacheBookSummary | null) => void;

  // 服务
  private remoteReadAloudCacheService = getRemoteReadAloudCacheService();

  // 主题状态
  @State private themeState: ThemeAwareState = new ThemeAwareState();
  private componentId: string = `ReadAloudCacheDialog_${Date.now()}`;

  // 听书缓存状态
  @State readAloudCacheSummary: RemoteReadAloudCacheBookSummary | null = null;
  @State private appGuideStep: AppGuideStep | null = null;
  @State private appGuideHighlightRect: GuideHighlightRect | null = null;
  @State isReadAloudCacheLoading: boolean = false;
  @State isReadAloudCacheExpanded: boolean = true;
  @State showReadAloudCacheDialog: boolean = false;
  @State readAloudCacheDialogActiveTab: number = 0;
  @State readAloudCacheSelectionMode: 'range' | 'individual' = 'range';
  @State readAloudCacheRangeStart: number = 0;
  @State readAloudCacheRangeEnd: number = 0;
  @State readAloudCacheSelectedChapters: Set<number> = new Set();
  @State readAloudCacheChapterListExpanded: boolean = true;
  @State readAloudCacheTaskSettings: RemoteReadAloudSettings = DEFAULT_REMOTE_READ_ALOUD_SETTINGS;
  @State readAloudCacheManageChapterIndex: number = 0;
  @State readAloudCacheManageDetail: RemoteReadAloudCacheChapterDetail | null = null;
  @State isReadAloudCacheManageLoading: boolean = false;
  @State isReadAloudCacheManageMutating: boolean = false;
  @State readAloudCacheManageChapterSectionExpanded: boolean = true;
  @State readAloudCacheManageTargetSectionExpanded: boolean = true;
  @State readAloudCacheManageSourceSectionExpanded: boolean = true;
  @State readAloudCacheManageSelectedTargetIndex: number = -1;
  @State readAloudCacheManageBlockedSuggestionKeys: Set<string> = new Set();
  @State readAloudCacheManageStatusMessage: string = '';
  @State readAloudCachePresetDraftName: string = '';
  @State readAloudCachePresetStatusMessage: string = '';
  @State isReadAloudCurrentSettingsSaving: boolean = false;
  @State isReadAloudPrecaching: boolean = false;
  @State readAloudPrecachingStatusText: string = '';
  @State readAloudPrecachingDetailText: string = '';
  @State readAloudPrecachingChapterOrder: number = 0;
  @State readAloudPrecachingChapterTotal: number = 0;
  @State readAloudPrecachingSegmentDone: number = 0;
  @State readAloudPrecachingSegmentTotal: number = 0;
  @State readAloudPrecachingBytes: number = 0;
  private readAloudCacheRefreshTimer: number = -1;
  private readAloudCacheManageLoadToken: number = 0;

  // 事件处理
  private onReadAloudCacheUpdated: (payload: IEventPayload) => void = (payload: IEventPayload): void => {
    const cachePayload = payload as ReadAloudCacheUpdatedPayload;
    const currentBookId = this.getCurrentReadAloudCacheBookId();
    if (!currentBookId || cachePayload.bookId !== currentBookId) {
      return;
    }
    this.scheduleReadAloudCacheRefresh(cachePayload.reason || 'event');
  };

  // 生命周期
  aboutToAppear(): void {
    void ThemeAwareHelper.initializeThemeAware(this.componentId, this.themeState, undefined, (newState: ThemeAwareState) => {
      this.themeState = newState;
    });
    eventBus.subscribe(GameEvent.READ_ALOUD_CACHE_UPDATED, this.onReadAloudCacheUpdated);
  }

  aboutToDisappear(): void {
    ThemeAwareHelper.cleanupThemeAware(this.componentId);
    eventBus.unsubscribe(GameEvent.READ_ALOUD_CACHE_UPDATED, this.onReadAloudCacheUpdated);
    this.clearReadAloudCacheRefreshTimer();
  }

  onLoadSignalChanged(): void {
    void this.loadReadAloudCacheSummary();
  }

  // ==================== 辅助方法 ====================

  private getNovelCacheBookId(sourceId: string, bookUrl: string): string {
    return `${sourceId}_${encodeURIComponent(bookUrl)}`;
  }

  private formatRelativeTime(timestamp: number): string {
    const date = new Date(timestamp);
    const now = new Date();
    const diff = now.getTime() - date.getTime();
    const days = Math.floor(diff / (1000 * 60 * 60 * 24));
    if (days === 0) return '今天';
    if (days === 1) return '昨天';
    if (days < 7) return `${days}天前`;
    if (days < 30) return `${Math.floor(days / 7)}周前`;
    if (days < 365) return `${Math.floor(days / 30)}月前`;
    return `${date.getFullYear()}/${date.getMonth() + 1}/${date.getDate()}`;
  }

  private getSectionSurfaceStyle(): SettingsPageSurfaceStyle {
    return SettingsPageSurfaceManager.getManagementContentSurfaceStyle(this.themeState.currentTheme);
  }

  private getSectionBackgroundColor(): ResourceColor {
    return this.getSectionSurfaceStyle().backgroundColor;
  }

  private getSectionBlurStyle(): BlurStyle | undefined {
    return this.getSectionSurfaceStyle().blurStyle;
  }

  private getSectionBlurOptions(): BackgroundBlurStyleOptions {
    return this.getSectionSurfaceStyle().blurOptions;
  }

  private getSectionBackgroundEffect(): BackgroundEffectOptions | undefined {
    return this.getSectionSurfaceStyle().backgroundEffect;
  }

  private getSectionRadius(): number {
    return this.getSectionSurfaceStyle().radius;
  }

  private getSectionBorderColor(): ResourceColor {
    return this.getSectionSurfaceStyle().borderColor;
  }

  private getSectionBorderWidth(): number {
    return this.getSectionSurfaceStyle().borderWidth;
  }

  private getSectionShadowColor(): string {
    return this.getSectionSurfaceStyle().shadowColor;
  }

  @Builder
  private buildGlassSectionChrome() {
    Column()
      .width('100%')
      .height(1)
      .backgroundColor(this.getSectionSurfaceStyle().topEdgeColor)
    Column()
      .width('100%')
      .height(1)
      .align(Alignment.Bottom)
      .backgroundColor(this.getSectionSurfaceStyle().bottomEdgeColor)
  }

  // ==================== Handler 方法 ====================

  private getCurrentReadAloudCacheBookId(): string {
    if (this.readAloudCacheSummary?.bookId) {
      return this.readAloudCacheSummary.bookId;
    }
    if (!this.content) {
      return '';
    }
    if (this.content.contentType === UnifiedContentType.NOVEL) {
      return this.getNovelCacheBookId((this.content.sourceId || 'local').trim(), this.content.id);
    }
    if (this.isLocalTxtNovelEBook) {
      const ebook = EBookAdapter.getOriginalEBook(this.content);
      return ebook ? buildLocalTextNovelBookId(ebook.id) : '';
    }
    return '';
  }

  private clearReadAloudCacheRefreshTimer(): void {
    if (this.readAloudCacheRefreshTimer < 0) {
      return;
    }
    clearTimeout(this.readAloudCacheRefreshTimer);
    this.readAloudCacheRefreshTimer = -1;
  }

  private scheduleReadAloudCacheRefresh(reason: string): void {
    if (!this.supportsReadAloudCache) {
      return;
    }
    this.clearReadAloudCacheRefreshTimer();
    this.readAloudCacheRefreshTimer = setTimeout(() => {
      this.readAloudCacheRefreshTimer = -1;
      logger.debug(TAG, `刷新听书缓存摘要: reason=${reason}`);
      void this.loadReadAloudCacheSummary();
    }, 180);
  }

  private toggleReadAloudCacheExpanded(): void {
    this.getUIContext().animateTo({ duration: 300, curve: Curve.EaseInOut }, () => {
      this.isReadAloudCacheExpanded = !this.isReadAloudCacheExpanded;
    });
  }

  private async loadReadAloudCacheSummary(showToastOnError: boolean = false): Promise<void> {
    if (!this.supportsReadAloudCache) {
      this.readAloudCacheSummary = null;
      this.onSummaryChanged?.(null);
      this.isReadAloudCacheLoading = false;
      return;
    }
    this.isReadAloudCacheLoading = true;
    try {
      this.readAloudCacheSummary = await this.remoteReadAloudCacheService.inspectBookCache(this.content);
      this.onSummaryChanged?.(this.readAloudCacheSummary);
      const chapterCount = this.readAloudCacheSummary?.chapterCount ?? 0;
      if (chapterCount > 0 && this.readAloudCacheManageChapterIndex >= chapterCount) {
        this.readAloudCacheManageChapterIndex = chapterCount - 1;
      }
      if (this.showReadAloudCacheDialog && this.readAloudCacheDialogActiveTab === 1 && !this.isReadAloudCacheManageMutating) {
        await this.loadReadAloudCacheManageDetail();
      }
    } catch (error) {
      logger.error(TAG, `加载听书缓存失败: ${String(error)}`);
      this.readAloudCacheSummary = null;
      this.onSummaryChanged?.(null);
      if (showToastOnError) {
        this.getUIContext().getPromptAction().showToast({ message: '加载听书缓存失败', duration: 1400 });
      }
    } finally {
      this.isReadAloudCacheLoading = false;
    }
  }

  private formatReadAloudCacheSize(bytes: number): string {
    const safeBytes = Math.max(0, Math.floor(bytes));
    if (safeBytes >= 1024 * 1024 * 1024) {
      return `${(safeBytes / (1024 * 1024 * 1024)).toFixed(2)} GB`;
    }
    if (safeBytes >= 1024 * 1024) {
      return `${(safeBytes / (1024 * 1024)).toFixed(1)} MB`;
    }
    if (safeBytes >= 1024) {
      return `${(safeBytes / 1024).toFixed(1)} KB`;
    }
    return `${safeBytes} B`;
  }

  private getReadAloudCacheUpdatedLabel(timestamp: number): string {
    if (!timestamp || timestamp <= 0) {
      return '未缓存';
    }
    return this.formatRelativeTime(timestamp);
  }

  private getReadAloudCacheQuickSelectionStart(): number {
    const chapters = this.readAloudCacheSummary?.chapters ?? [];
    for (let index = 0; index < chapters.length; index++) {
      if (!chapters[index].cached) {
        return index;
      }
    }
    if (this.content && this.content.lastReadChapterIndex >= 0 && this.content.lastReadChapterIndex < chapters.length) {
      return this.content.lastReadChapterIndex;
    }
    return 0;
  }

  private openReadAloudCacheDialog(): void {
    if (this.isCurrentNovelAudioSource) {
      this.onOpenCacheDialog?.('read_aloud_cache_section');
      return;
    }
    if (!this.supportsReadAloudCache) {
      return;
    }
    const totalChapters = Math.max(1, this.readAloudCacheSummary?.chapterCount ?? this.content?.chapters.length ?? 1);
    const quickStart = this.getReadAloudCacheQuickSelectionStart();
    this.readAloudCacheDialogActiveTab = 0;
    this.readAloudCacheSelectionMode = 'range';
    this.readAloudCacheRangeStart = Math.max(0, Math.min(quickStart, totalChapters - 1));
    this.readAloudCacheRangeEnd = Math.max(this.readAloudCacheRangeStart, totalChapters - 1);
    this.readAloudCacheSelectedChapters = new Set<number>();
    this.readAloudCacheChapterListExpanded = true;
    this.readAloudCacheManageChapterIndex = Math.max(0, Math.min(quickStart, totalChapters - 1));
    this.readAloudCacheManageDetail = null;
    this.isReadAloudCacheManageLoading = false;
    this.isReadAloudCacheManageMutating = false;
    this.readAloudCacheManageChapterSectionExpanded = true;
    this.readAloudCacheManageTargetSectionExpanded = true;
    this.readAloudCacheManageSourceSectionExpanded = true;
    this.readAloudCacheManageSelectedTargetIndex = -1;
    this.readAloudCacheManageBlockedSuggestionKeys = new Set();
    this.readAloudCacheManageStatusMessage = '';
    this.readAloudCacheTaskSettings = this.remoteReadAloudCacheService.buildEditableRemoteSettings(this.content, {
      cacheAudioFiles: true
    });
    this.syncReadAloudCachePresetDraftName();
    this.readAloudCachePresetStatusMessage = '';
    this.getUIContext().animateTo({
      duration: 220,
      curve: Curve.EaseOut
    }, () => {
      this.showReadAloudCacheDialog = true;
    });
  }

  private handleReadAloudCacheDialogTabChange(index: number): void {
    if (this.readAloudCacheDialogActiveTab === index) {
      return;
    }
    this.getUIContext().animateTo({ duration: 220, curve: Curve.EaseInOut }, () => {
      this.readAloudCacheDialogActiveTab = index;
    });
    if (index === 1) {
      this.readAloudCacheManageSelectedTargetIndex = -1;
      void this.loadReadAloudCacheManageDetail();
      return;
    }
    if (index === 2) {
      this.syncReadAloudCachePresetDraftName();
      this.readAloudCachePresetStatusMessage = '';
    }
  }

  private closeReadAloudCacheDialog(): void {
    this.getUIContext().animateTo({
      duration: 180,
      curve: Curve.EaseIn
    }, () => {
      this.showReadAloudCacheDialog = false;
    });
  }

  private async loadReadAloudCacheManageDetail(showToastOnError: boolean = false): Promise<void> {
    if (!this.supportsReadAloudCache) {
      this.readAloudCacheManageDetail = null;
      this.isReadAloudCacheManageLoading = false;
      return;
    }
    const requestToken = this.readAloudCacheManageLoadToken + 1;
    this.readAloudCacheManageLoadToken = requestToken;
    const requestedChapterIndex = this.readAloudCacheManageChapterIndex;
    this.isReadAloudCacheManageLoading = true;
    try {
      const detail = await this.remoteReadAloudCacheService.inspectChapterCacheDetail(
        this.content,
        requestedChapterIndex
      );
      if (requestToken !== this.readAloudCacheManageLoadToken || requestedChapterIndex !== this.readAloudCacheManageChapterIndex) {
        return;
      }
      this.readAloudCacheManageDetail = detail;
    } catch (error) {
      if (requestToken !== this.readAloudCacheManageLoadToken) {
        return;
      }
      logger.error(TAG, `加载听书缓存管理明细失败: chapter=${requestedChapterIndex}, error=${String(error)}`);
      this.readAloudCacheManageDetail = null;
      if (showToastOnError) {
        this.getUIContext().getPromptAction().showToast({ message: '加载听书缓存管理明细失败', duration: 1400 });
      }
    } finally {
      if (requestToken === this.readAloudCacheManageLoadToken) {
        this.isReadAloudCacheManageLoading = false;
      }
    }
  }

  private selectReadAloudCacheManageChapter(chapterIndex: number): void {
    this.getUIContext().animateTo({ duration: 220, curve: Curve.EaseInOut }, () => {
      this.readAloudCacheManageChapterIndex = Math.max(0, chapterIndex);
      this.readAloudCacheManageDetail = null;
      this.readAloudCacheManageSelectedTargetIndex = -1;
      this.readAloudCacheManageBlockedSuggestionKeys = new Set();
      this.readAloudCacheManageStatusMessage = '';
    });
    void this.loadReadAloudCacheManageDetail();
  }

  private selectReadAloudCacheManageTarget(segmentIndex: number): void {
    this.getUIContext().animateTo({ duration: 180, curve: Curve.EaseOut }, () => {
      this.readAloudCacheManageSelectedTargetIndex = this.readAloudCacheManageSelectedTargetIndex === segmentIndex ? -1 : segmentIndex;
    });
  }

  private toggleReadAloudCacheManageSection(section: 'chapter' | 'target' | 'source'): void {
    this.getUIContext().animateTo({ duration: 280, curve: Curve.EaseInOut }, () => {
      switch (section) {
        case 'chapter':
          this.readAloudCacheManageChapterSectionExpanded = !this.readAloudCacheManageChapterSectionExpanded;
          break;
        case 'target':
          this.readAloudCacheManageTargetSectionExpanded = !this.readAloudCacheManageTargetSectionExpanded;
          break;
        default:
          this.readAloudCacheManageSourceSectionExpanded = !this.readAloudCacheManageSourceSectionExpanded;
          break;
      }
    });
  }

  private buildReadAloudCacheSuggestionPairKey(
    segment: RemoteReadAloudCacheSegmentDetail,
    targetSegmentIndex: number
  ): string {
    return `${segment.manifestPath ?? ''}::${segment.segmentIndex}::${targetSegmentIndex}`;
  }

  private getEffectiveReadAloudCacheSuggestedTarget(
    segment: RemoteReadAloudCacheSegmentDetail,
    blockedKeys?: Set<string>
  ): RemoteReadAloudCacheTargetSuggestion | null {
    const effectiveBlockedKeys = blockedKeys ?? this.readAloudCacheManageBlockedSuggestionKeys;
    const suggestions = segment.suggestedTargets ?? [];
    for (let index = 0; index < suggestions.length; index++) {
      const suggestion = suggestions[index];
      if (!effectiveBlockedKeys.has(this.buildReadAloudCacheSuggestionPairKey(segment, suggestion.targetSegmentIndex))) {
        return suggestion;
      }
    }
    return null;
  }

  private getReadAloudCacheBlockedSuggestionCount(segment: RemoteReadAloudCacheSegmentDetail): number {
    let count = 0;
    const suggestions = segment.suggestedTargets ?? [];
    for (let index = 0; index < suggestions.length; index++) {
      if (this.readAloudCacheManageBlockedSuggestionKeys.has(
        this.buildReadAloudCacheSuggestionPairKey(segment, suggestions[index].targetSegmentIndex)
      )) {
        count += 1;
      }
    }
    return count;
  }

  private async attachReadAloudCacheSourceSegmentToTarget(
    segment: RemoteReadAloudCacheSegmentDetail,
    targetSegmentIndex: number,
    successMessage: string
  ): Promise<void> {
    if (this.isReadAloudCacheManageMutating || targetSegmentIndex < 0) {
      return;
    }
    this.readAloudCacheManageSelectedTargetIndex = targetSegmentIndex;
    this.isReadAloudCacheManageMutating = true;
    try {
      await this.remoteReadAloudCacheService.attachSegmentToCurrentSlot(
        this.content,
        this.readAloudCacheManageChapterIndex,
        targetSegmentIndex,
        segment.manifestPath ?? '',
        segment.segmentIndex
      );
      await this.loadReadAloudCacheSummary();
      await this.loadReadAloudCacheManageDetail();
      this.readAloudCacheManageStatusMessage = successMessage;
      this.getUIContext().getPromptAction().showToast({ message: '已完成分段匹配', duration: 1400 });
    } catch (error) {
      logger.error(TAG, `匹配听书分段失败: target=${targetSegmentIndex}, error=${String(error)}`);
      this.readAloudCacheManageStatusMessage = '分段匹配失败';
      this.getUIContext().getPromptAction().showToast({ message: '分段匹配失败', duration: 1400 });
    } finally {
      this.isReadAloudCacheManageMutating = false;
    }
  }

  private async attachReadAloudCacheSourceSegment(segment: RemoteReadAloudCacheSegmentDetail): Promise<void> {
    if (this.readAloudCacheManageSelectedTargetIndex < 0) {
      return;
    }
    await this.attachReadAloudCacheSourceSegmentToTarget(
      segment,
      this.readAloudCacheManageSelectedTargetIndex,
      `已将分段匹配到当前文本槽位 S${this.readAloudCacheManageSelectedTargetIndex + 1}`
    );
  }

  private async attachReadAloudCacheSourceSegmentToSuggestedTarget(segment: RemoteReadAloudCacheSegmentDetail): Promise<void> {
    const suggestion = this.getEffectiveReadAloudCacheSuggestedTarget(segment);
    if (!suggestion) {
      this.readAloudCacheManageStatusMessage = '当前没有可直接采用的建议槽位';
      this.getUIContext().getPromptAction().showToast({ message: '当前没有可直接采用的建议槽位', duration: 1400 });
      return;
    }
    await this.attachReadAloudCacheSourceSegmentToTarget(
      segment,
      suggestion.targetSegmentIndex,
      `已将分段按建议匹配到 S${suggestion.targetSegmentIndex + 1}`
    );
  }

  private forbidReadAloudCacheSuggestedTarget(segment: RemoteReadAloudCacheSegmentDetail): void {
    const suggestion = this.getEffectiveReadAloudCacheSuggestedTarget(segment);
    if (!suggestion) {
      this.readAloudCacheManageStatusMessage = '该分段已经没有可建议的目标槽位';
      return;
    }
    const nextBlockedKeys = new Set(this.readAloudCacheManageBlockedSuggestionKeys);
    nextBlockedKeys.add(this.buildReadAloudCacheSuggestionPairKey(segment, suggestion.targetSegmentIndex));
    const nextSuggestion = this.getEffectiveReadAloudCacheSuggestedTarget(segment, nextBlockedKeys);
    this.getUIContext().animateTo({ duration: 220, curve: Curve.EaseInOut }, () => {
      this.readAloudCacheManageBlockedSuggestionKeys = nextBlockedKeys;
    });
    if (nextSuggestion) {
      this.readAloudCacheManageStatusMessage = `已禁止建议到 S${suggestion.targetSegmentIndex + 1}，当前改为建议 S${nextSuggestion.targetSegmentIndex + 1}`;
      return;
    }
    this.readAloudCacheManageStatusMessage = `已禁止建议到 S${suggestion.targetSegmentIndex + 1}，该分段暂时不再推荐匹配`;
  }

  private async removeReadAloudCacheManageSegment(segment: RemoteReadAloudCacheSegmentDetail): Promise<void> {
    if (this.isReadAloudCacheManageMutating) {
      return;
    }
    this.isReadAloudCacheManageMutating = true;
    try {
      await this.remoteReadAloudCacheService.removeSegmentFromManifest(
        this.content,
        this.readAloudCacheManageChapterIndex,
        segment.manifestPath ?? '',
        segment.segmentIndex
      );
      await this.loadReadAloudCacheSummary();
      await this.loadReadAloudCacheManageDetail();
      this.readAloudCacheManageStatusMessage = `已删除分段 S${segment.segmentIndex + 1}`;
      this.getUIContext().getPromptAction().showToast({ message: '已删除分段缓存记录', duration: 1400 });
    } catch (error) {
      logger.error(TAG, `删除听书分段失败: segment=${segment.segmentIndex}, error=${String(error)}`);
      this.readAloudCacheManageStatusMessage = '删除分段失败';
      this.getUIContext().getPromptAction().showToast({ message: '删除分段失败', duration: 1400 });
    } finally {
      this.isReadAloudCacheManageMutating = false;
    }
  }

  private toggleReadAloudCacheChapterSelection(index: number): void {
    const next = new Set(this.readAloudCacheSelectedChapters);
    if (next.has(index)) {
      next.delete(index);
    } else {
      next.add(index);
    }
    this.readAloudCacheSelectedChapters = next;
  }

  private getSelectedReadAloudChapterIndexes(): number[] {
    const totalChapters = this.readAloudCacheSummary?.chapterCount ?? this.content?.chapters.length ?? 0;
    if (totalChapters <= 0) {
      return [];
    }
    if (this.readAloudCacheSelectionMode === 'range') {
      const start = Math.max(0, Math.min(this.readAloudCacheRangeStart, totalChapters - 1));
      const end = Math.max(start, Math.min(this.readAloudCacheRangeEnd, totalChapters - 1));
      const indexes: number[] = [];
      for (let index = start; index <= end; index++) {
        indexes.push(index);
      }
      return indexes;
    }
    return Array.from(this.readAloudCacheSelectedChapters.values())
      .filter((index: number) => index >= 0 && index < totalChapters)
      .sort((left: number, right: number) => left - right);
  }

  private getSelectedReadAloudChapterCount(): number {
    return this.getSelectedReadAloudChapterIndexes().length;
  }

  private updateReadAloudCacheTaskSettings(partial: Partial<RemoteReadAloudSettings>): void {
    const mergedSettings = mergeRemoteReadAloudSettings(this.readAloudCacheTaskSettings, partial);
    mergedSettings.cacheAudioFiles = true;
    this.readAloudCacheTaskSettings = mergedSettings;
  }

  private isMiMoReadAloudCacheSettings(): boolean {
    return isXiaomiMimoRemoteReadAloud(this.readAloudCacheTaskSettings);
  }

  private getReadAloudCacheStylePrompt(): string {
    return normalizeRemoteReadAloudStylePrompt(this.readAloudCacheTaskSettings.stylePrompt);
  }

  private isReadAloudCacheStyleSelected(style: string): boolean {
    return hasRemoteReadAloudStylePrompt(this.getReadAloudCacheStylePrompt(), style);
  }

  private toggleReadAloudCacheStyle(style: string): void {
    this.updateReadAloudCacheTaskSettings({
      stylePrompt: toggleRemoteReadAloudStylePrompt(this.getReadAloudCacheStylePrompt(), style)
    });
  }

  private getReadAloudCacheVoiceLabel(voice: string): string {
    if (this.isMiMoReadAloudCacheSettings()) {
      return getXiaomiMimoRemoteReadAloudVoiceLabel(voice);
    }
    const normalizedVoice = voice.trim();
    return normalizedVoice.length > 0 ? normalizedVoice : '默认音色';
  }

  private syncReadAloudCachePresetDraftName(): void {
    const activePreset = this.getActiveReadAloudCachePreset();
    this.readAloudCachePresetDraftName = activePreset ? activePreset.name : '';
  }

  private getReadAloudCacheCurrentConfig(): RemoteReadAloudPresetConfig {
    return extractRemoteReadAloudPresetConfig(this.readAloudCacheTaskSettings);
  }

  private getReadAloudCacheConfigWithoutApiKey(config: RemoteReadAloudPresetConfig): RemoteReadAloudPresetConfig {
    return {
      endpoint: config.endpoint,
      apiPath: config.apiPath,
      apiKey: '',
      model: config.model,
      voice: config.voice,
      stylePrompt: config.stylePrompt,
      audioFormat: config.audioFormat,
      streamEnabled: config.streamEnabled,
      prefetchSegments: config.prefetchSegments,
      connectTimeoutMs: config.connectTimeoutMs,
      readTimeoutMs: config.readTimeoutMs,
      maxInputChars: config.maxInputChars,
      reservedInputChars: config.reservedInputChars,
      minChunkChars: config.minChunkChars,
      targetChunkChars: config.targetChunkChars,
      maxChunkChars: config.maxChunkChars,
      cacheAudioFiles: config.cacheAudioFiles,
      autoConcatAudio: config.autoConcatAudio,
      customHeadersJson: config.customHeadersJson,
      extraBodyJson: config.extraBodyJson
    };
  }

  private getActiveReadAloudCachePreset(): RemoteReadAloudPreset | null {
    const activePresetId = this.readAloudCacheTaskSettings.activePresetId ?? '';
    if (activePresetId.length <= 0) {
      return null;
    }
    return this.readAloudCacheTaskSettings.presets.find((preset: RemoteReadAloudPreset) => preset.id === activePresetId) ?? null;
  }

  private isCurrentReadAloudCacheConfigMatchingPreset(preset: RemoteReadAloudPreset): boolean {
    const current = this.getReadAloudCacheCurrentConfig();
    if (isRemoteReadAloudPresetConfigEqual(current, preset.settings)) {
      return true;
    }
    if (!preset.builtIn) {
      return false;
    }
    return isRemoteReadAloudPresetConfigEqual(
      this.getReadAloudCacheConfigWithoutApiKey(current),
      this.getReadAloudCacheConfigWithoutApiKey(preset.settings)
    );
  }

  private getReadAloudCachePresetSummary(): string {
    const activePreset = this.getActiveReadAloudCachePreset();
    if (!activePreset) {
      return '当前配置还没有保存为预设';
    }
    if (this.isCurrentReadAloudCacheConfigMatchingPreset(activePreset)) {
      return `当前预设：${activePreset.name}`;
    }
    return `当前基于“${activePreset.name}”修改`;
  }

  private buildReadAloudCachePresetDescriptionFromCurrentConfig(): string {
    const remote = this.readAloudCacheTaskSettings;
    if (remote.endpoint.toLowerCase().includes('xiaomimimo.com') || remote.model.toLowerCase() === 'mimo-v2-tts') {
      const stylePrompt = this.getReadAloudCacheStylePrompt();
      const voiceLabel = this.getReadAloudCacheVoiceLabel(remote.voice);
      return stylePrompt.length > 0
        ? `基于 Xiaomi MiMo-V2-TTS / ${voiceLabel} / ${stylePrompt}`
        : `基于 Xiaomi MiMo-V2-TTS / ${voiceLabel}`;
    }
    const model = remote.model.trim().length > 0 ? remote.model.trim() : '自定义模型';
    const voice = this.getReadAloudCacheVoiceLabel(remote.voice);
    return `${model} / ${voice}`;
  }

  private generateReadAloudCachePresetId(): string {
    return `remote_preset_${Date.now()}_${Math.floor(Math.random() * 10000)}`;
  }

  private canEditActiveReadAloudCachePreset(): boolean {
    const activePreset = this.getActiveReadAloudCachePreset();
    return activePreset !== null && activePreset.builtIn !== true;
  }

  private buildReadAloudCacheSettingsUpdate(
    config: RemoteReadAloudPresetConfig,
    activePresetId: string,
    presets?: RemoteReadAloudPreset[]
  ): Partial<RemoteReadAloudSettings> {
    const update: Partial<RemoteReadAloudSettings> = {
      endpoint: config.endpoint,
      apiPath: config.apiPath,
      apiKey: config.apiKey,
      model: config.model,
      voice: config.voice,
      stylePrompt: config.stylePrompt,
      audioFormat: config.audioFormat,
      streamEnabled: config.streamEnabled,
      prefetchSegments: config.prefetchSegments,
      connectTimeoutMs: config.connectTimeoutMs,
      readTimeoutMs: config.readTimeoutMs,
      maxInputChars: config.maxInputChars,
      reservedInputChars: config.reservedInputChars,
      minChunkChars: config.minChunkChars,
      targetChunkChars: config.targetChunkChars,
      maxChunkChars: config.maxChunkChars,
      cacheAudioFiles: config.cacheAudioFiles,
      autoConcatAudio: config.autoConcatAudio,
      customHeadersJson: config.customHeadersJson,
      extraBodyJson: config.extraBodyJson,
      activePresetId
    };
    if (presets !== undefined) {
      update.presets = presets;
    }
    return update;
  }

  private saveReadAloudCachePresetAsNew(): void {
    const name = this.readAloudCachePresetDraftName.trim().length > 0 ? this.readAloudCachePresetDraftName.trim() : '新的远程预设';
    const nextPreset: RemoteReadAloudPreset = {
      id: this.generateReadAloudCachePresetId(),
      name,
      description: this.buildReadAloudCachePresetDescriptionFromCurrentConfig(),
      builtIn: false,
      settings: this.getReadAloudCacheCurrentConfig()
    };
    const nextPresets = this.readAloudCacheTaskSettings.presets.slice();
    nextPresets.push(nextPreset);
    this.updateReadAloudCacheTaskSettings(this.buildReadAloudCacheSettingsUpdate(nextPreset.settings, nextPreset.id, nextPresets));
    this.readAloudCachePresetDraftName = name;
    this.readAloudCachePresetStatusMessage = `已保存预设：${name}`;
  }

  private updateCurrentReadAloudCachePreset(): void {
    const activePreset = this.getActiveReadAloudCachePreset();
    if (!activePreset || activePreset.builtIn) {
      this.saveReadAloudCachePresetAsNew();
      return;
    }
    const name = this.readAloudCachePresetDraftName.trim().length > 0 ? this.readAloudCachePresetDraftName.trim() : activePreset.name;
    const nextPresets = this.readAloudCacheTaskSettings.presets.map((preset: RemoteReadAloudPreset) => {
      if (preset.id !== activePreset.id) {
        return preset;
      }
      return {
        id: preset.id,
        name,
        description: this.buildReadAloudCachePresetDescriptionFromCurrentConfig(),
        builtIn: false,
        settings: this.getReadAloudCacheCurrentConfig()
      };
    });
    this.updateReadAloudCacheTaskSettings({
      activePresetId: activePreset.id,
      presets: nextPresets
    });
    this.readAloudCachePresetDraftName = name;
    this.readAloudCachePresetStatusMessage = `已更新预设：${name}`;
  }

  private applyReadAloudCachePreset(preset: RemoteReadAloudPreset): void {
    const currentRemote = this.readAloudCacheTaskSettings;
    const presetApiKey = preset.settings.apiKey ?? '';
    const shouldPreserveApiKey = preset.builtIn === true &&
      presetApiKey.trim().length <= 0 &&
      currentRemote.apiKey.trim().length > 0;
    const appliedConfig: RemoteReadAloudPresetConfig = {
      endpoint: preset.settings.endpoint,
      apiPath: preset.settings.apiPath,
      apiKey: shouldPreserveApiKey ? currentRemote.apiKey : presetApiKey,
      model: preset.settings.model,
      voice: preset.settings.voice,
      stylePrompt: preset.settings.stylePrompt,
      audioFormat: preset.settings.audioFormat,
      streamEnabled: preset.settings.streamEnabled,
      prefetchSegments: preset.settings.prefetchSegments,
      connectTimeoutMs: preset.settings.connectTimeoutMs,
      readTimeoutMs: preset.settings.readTimeoutMs,
      maxInputChars: preset.settings.maxInputChars,
      reservedInputChars: preset.settings.reservedInputChars,
      minChunkChars: preset.settings.minChunkChars,
      targetChunkChars: preset.settings.targetChunkChars,
      maxChunkChars: preset.settings.maxChunkChars,
      cacheAudioFiles: preset.settings.cacheAudioFiles,
      autoConcatAudio: preset.settings.autoConcatAudio,
      customHeadersJson: preset.settings.customHeadersJson,
      extraBodyJson: preset.settings.extraBodyJson
    };
    this.updateReadAloudCacheTaskSettings(this.buildReadAloudCacheSettingsUpdate(appliedConfig, preset.id));
    this.readAloudCachePresetDraftName = preset.name;
    this.readAloudCachePresetStatusMessage = `已应用预设：${preset.name}`;
  }

  private deleteCurrentReadAloudCachePreset(): void {
    const activePreset = this.getActiveReadAloudCachePreset();
    if (!activePreset) {
      this.readAloudCachePresetStatusMessage = '当前没有可删除的预设';
      return;
    }
    if (activePreset.builtIn) {
      this.readAloudCachePresetStatusMessage = '内置预设不可删除';
      return;
    }
    const nextPresets = this.readAloudCacheTaskSettings.presets.filter((preset: RemoteReadAloudPreset) => preset.id !== activePreset.id);
    const fallbackPreset = nextPresets.find((preset: RemoteReadAloudPreset) => preset.id === DEFAULT_REMOTE_READ_ALOUD_PRESET_ID) ??
      (nextPresets.length > 0 ? nextPresets[0] : null);
    if (fallbackPreset) {
      this.updateReadAloudCacheTaskSettings(this.buildReadAloudCacheSettingsUpdate(fallbackPreset.settings, fallbackPreset.id, nextPresets));
      this.readAloudCachePresetDraftName = fallbackPreset.name;
    } else {
      this.updateReadAloudCacheTaskSettings({
        activePresetId: '',
        presets: nextPresets
      });
      this.readAloudCachePresetDraftName = '';
    }
    this.readAloudCachePresetStatusMessage = `已删除预设：${activePreset.name}`;
  }

  private parseReadAloudCacheIntegerInput(text: string, fallback: number, min: number, max: number): number {
    const parsed = Math.floor(Number(text));
    if (!Number.isFinite(parsed)) {
      return fallback;
    }
    return Math.max(min, Math.min(max, parsed));
  }

  private async applyReadAloudCacheTaskSettingsToCurrent(): Promise<void> {
    if (this.isReadAloudCurrentSettingsSaving) {
      return;
    }
    this.isReadAloudCurrentSettingsSaving = true;
    try {
      await this.remoteReadAloudCacheService.saveCurrentRemoteSettings(this.content, this.readAloudCacheTaskSettings);
      await this.loadReadAloudCacheSummary();
      this.readAloudCacheTaskSettings = this.remoteReadAloudCacheService.buildEditableRemoteSettings(this.content, {
        cacheAudioFiles: true
      });
      this.syncReadAloudCachePresetDraftName();
      if (this.showReadAloudCacheDialog && this.readAloudCacheDialogActiveTab === 1) {
        await this.loadReadAloudCacheManageDetail();
      }
      this.getUIContext().getPromptAction().showToast({ message: '已保存当前书籍远程 TTS 设置', duration: 1500 });
    } catch (error) {
      logger.error(TAG, `保存当前远程TTS设置失败: ${String(error)}`);
      this.getUIContext().getPromptAction().showToast({ message: '保存当前远程 TTS 设置失败', duration: 1500 });
    } finally {
      this.isReadAloudCurrentSettingsSaving = false;
    }
  }

  private buildReadAloudCacheChapterLabel(index: number): string {
    const summaryChapter = this.readAloudCacheSummary?.chapters[index];
    if (summaryChapter) {
      return summaryChapter.chapterTitle || `第 ${index + 1} 章`;
    }
    const contentChapter = this.content?.chapters[index];
    if (contentChapter) {
      return contentChapter.title || `第 ${index + 1} 章`;
    }
    return `第 ${index + 1} 章`;
  }

  private async quickPrecacheReadAloudChapter(chapterIndex: number): Promise<void> {
    if (this.isReadAloudPrecaching) {
      return;
    }
    const chapterTitle = this.buildReadAloudCacheChapterLabel(chapterIndex);
    try {
      await this.runReadAloudPrecacheTask([chapterIndex], false);
      this.getUIContext().getPromptAction().showToast({ message: `已缓存 ${chapterTitle}`, duration: 1400 });
    } catch (error) {
      logger.error(TAG, `单章听书缓存失败: chapter=${chapterIndex}, error=${String(error)}`);
      this.getUIContext().getPromptAction().showToast({ message: '当前章节缓存失败', duration: 1400 });
    }
  }

  private async clearReadAloudCacheChapter(chapterIndex: number): Promise<void> {
    if (this.isReadAloudPrecaching) {
      return;
    }
    try {
      await this.remoteReadAloudCacheService.clearChapterCache(this.content, chapterIndex);
      await this.loadReadAloudCacheSummary();
      this.getUIContext().getPromptAction().showToast({ message: `已清理第 ${chapterIndex + 1} 章听书缓存`, duration: 1400 });
    } catch (error) {
      logger.error(TAG, `清理章节听书缓存失败: chapter=${chapterIndex}, error=${String(error)}`);
      this.getUIContext().getPromptAction().showToast({ message: '清理章节缓存失败', duration: 1400 });
    }
  }

  private async clearReadAloudCacheBook(): Promise<void> {
    if (this.isReadAloudPrecaching) {
      return;
    }
    try {
      await this.remoteReadAloudCacheService.clearBookCache(this.content);
      await this.loadReadAloudCacheSummary();
      this.getUIContext().getPromptAction().showToast({ message: '已清理当前小说听书缓存', duration: 1400 });
    } catch (error) {
      logger.error(TAG, `清理当前小说听书缓存失败: ${String(error)}`);
      this.getUIContext().getPromptAction().showToast({ message: '清理听书缓存失败', duration: 1400 });
    }
  }

  private async startReadAloudCacheTaskFromDialog(): Promise<void> {
    const targetIndexes = this.getSelectedReadAloudChapterIndexes();
    if (targetIndexes.length <= 0) {
      this.getUIContext().getPromptAction().showToast({ message: '请先选择要缓存的章节', duration: 1400 });
      return;
    }
    try {
      await this.runReadAloudPrecacheTask(targetIndexes, true);
      await this.loadReadAloudCacheSummary();
      this.getUIContext().getPromptAction().showToast({ message: `已完成 ${targetIndexes.length} 章听书缓存`, duration: 1500 });
    } catch (error) {
      logger.error(TAG, `批量听书缓存失败: ${String(error)}`);
      this.getUIContext().getPromptAction().showToast({ message: '听书缓存任务失败', duration: 1500 });
    }
  }

  private async runReadAloudPrecacheTask(chapterIndexes: number[], closeDialogOnSuccess: boolean): Promise<void> {
    if (this.isReadAloudPrecaching) {
      return;
    }
    this.isReadAloudPrecaching = true;
    this.readAloudPrecachingStatusText = '正在准备听书缓存';
    this.readAloudPrecachingDetailText = '';
    this.readAloudPrecachingChapterOrder = 0;
    this.readAloudPrecachingChapterTotal = chapterIndexes.length;
    this.readAloudPrecachingSegmentDone = 0;
    this.readAloudPrecachingSegmentTotal = 0;
    this.readAloudPrecachingBytes = 0;
    try {
      if (!this.showReadAloudCacheDialog) {
        this.readAloudCacheTaskSettings = this.remoteReadAloudCacheService.buildEditableRemoteSettings(this.content, {
          cacheAudioFiles: true
        });
      }
      const effectiveRemoteSettings = mergeRemoteReadAloudSettings(this.readAloudCacheTaskSettings, {
        cacheAudioFiles: true
      });
      await this.remoteReadAloudCacheService.saveCurrentRemoteSettings(this.content, effectiveRemoteSettings);
      await this.remoteReadAloudCacheService.precacheChapters(this.content, chapterIndexes, {
        remoteOverrides: effectiveRemoteSettings,
        onProgress: (progress: RemoteReadAloudCacheTaskProgress) => {
          this.readAloudPrecachingChapterOrder = progress.chapterOrder;
          this.readAloudPrecachingChapterTotal = progress.chapterTotal;
          this.readAloudPrecachingSegmentDone = progress.segmentProgress.completedSegments;
          this.readAloudPrecachingSegmentTotal = progress.segmentProgress.totalSegments;
          this.readAloudPrecachingBytes = progress.totalCachedBytes;
          this.readAloudPrecachingStatusText = `正在缓存 ${progress.chapterTitle}`;
          this.readAloudPrecachingDetailText = `章节 ${progress.chapterOrder}/${progress.chapterTotal} · 分片 ${progress.segmentProgress.completedSegments}/${progress.segmentProgress.totalSegments}`;
        }
      });
      await this.loadReadAloudCacheSummary();
      if (closeDialogOnSuccess) {
        this.closeReadAloudCacheDialog();
      }
    } finally {
      this.isReadAloudPrecaching = false;
    }
  }

  private getReadAloudCacheProgressPercent(): number {
    const total = Math.max(0, this.readAloudCacheSummary?.chapterCount ?? this.content?.chapters.length ?? 0);
    if (total <= 0) {
      return 0;
    }
    const cached = Math.max(0, Math.min(this.readAloudCacheSummary?.cachedChapterCount ?? 0, total));
    return Math.round((cached / total) * 100);
  }

  private getReadAloudCacheSectionDescription(): string {
    return this.isLocalTxtNovelEBook
      ? '当前 TXT 电子书的远程 TTS 音频缓存，可按章节批量生成整章听书音频。'
      : '当前小说的远程 TTS 音频缓存，可按章节批量生成整章听书音频。';
  }

  private getReadAloudCacheSelectionSummary(): string {
    const count = this.getSelectedReadAloudChapterCount();
    return count > 0 ? `已选择 ${count} 章` : '未选择章节';
  }

  private getReadAloudCachePreviewIndexes(): number[] {
    const chapters = this.readAloudCacheSummary?.chapters ?? [];
    if (chapters.length <= 0) {
      return [];
    }
    const start = Math.max(0, Math.min(this.getReadAloudCacheQuickSelectionStart(), chapters.length - 1));
    const result: number[] = [];
    for (let index = start; index < chapters.length && result.length < 3; index++) {
      result.push(index);
    }
    for (let index = 0; index < start && result.length < 3; index++) {
      result.push(index);
    }
    return result;
  }

  private getReadAloudCacheEffectiveChapterStatusText(chapter: RemoteReadAloudCacheChapterSummary): string {
    if (chapter.cached) {
      const sizeText = chapter.currentTotalBytes > 0 ? this.formatReadAloudCacheSize(chapter.currentTotalBytes) : '0 B';
      const updatedText = this.getReadAloudCacheUpdatedLabel(chapter.currentLastUpdatedAt);
      return `当前配置已缓存 · ${chapter.currentSegmentCount} 段 · ${sizeText} · ${updatedText}`;
    }
    if (chapter.variantCount > 0) {
      const historySize = chapter.totalBytes > 0 ? this.formatReadAloudCacheSize(chapter.totalBytes) : '0 B';
      return `当前配置未命中 · 历史有 ${chapter.variantCount} 个版本 · ${historySize}`;
    }
    return '当前配置未缓存';
  }

  private isReadAloudCacheChapterSelected(index: number): boolean {
    const total = this.readAloudCacheSummary?.chapterCount ?? this.content?.chapters.length ?? 0;
    if (index < 0 || index >= total) {
      return false;
    }
    if (this.readAloudCacheSelectionMode === 'range') {
      const start = Math.max(0, Math.min(this.readAloudCacheRangeStart, total - 1));
      const end = Math.max(start, Math.min(this.readAloudCacheRangeEnd, total - 1));
      return index >= start && index <= end;
    }
    return this.readAloudCacheSelectedChapters.has(index);
  }

  private getReadAloudCacheChapterStatusText(chapter: RemoteReadAloudCacheChapterSummary): string {
    const statusText = chapter.cached ? '已缓存' : '未缓存';
    const sizeText = chapter.totalBytes > 0 ? this.formatReadAloudCacheSize(chapter.totalBytes) : '0 B';
    const updatedText = chapter.cached ? this.getReadAloudCacheUpdatedLabel(chapter.lastUpdatedAt) : '等待生成';
    return `${statusText} · ${chapter.segmentCount} 段 · ${sizeText} · ${updatedText}`;
  }

  private getReadAloudCacheSegmentSourceLabel(chapter: RemoteReadAloudCacheChapterSummary): string {
    switch (chapter.displaySegmentsSource) {
      case 'current':
        return '当前命中';
      case 'history':
        return '历史版本';
      default:
        return '无文本映射';
    }
  }

  private formatReadAloudCacheSegmentRange(segment: RemoteReadAloudCacheSegmentSummary): string {
    return this.formatReadAloudCacheCharRange(segment.startCharIndex, segment.endCharIndex);
  }

  private formatReadAloudCacheTargetSegmentRange(segment: RemoteReadAloudCacheTargetSegment): string {
    return this.formatReadAloudCacheCharRange(segment.startCharIndex, segment.endCharIndex);
  }

  private formatReadAloudCacheCharRange(startCharIndex: number, endCharIndex: number): string {
    const start = Math.max(0, Math.floor(startCharIndex)) + 1;
    const end = Math.max(start, Math.max(0, Math.floor(endCharIndex) - 1) + 1);
    return `${start}-${end}`;
  }

  private getReadAloudCacheFadeSlideTransition(offsetY: number = 10) {
    return TransitionEffect.OPACITY.combine(TransitionEffect.translate({ y: offsetY }));
  }

  private shouldShowChapterListExpandToggle(): boolean {
    return !(this.content?.contentType === UnifiedContentType.EBOOK && this.content.chapters.length === 0);
  }

  private toggleChapterListExpanded(): void {
    if (!this.shouldShowChapterListExpandToggle()) {
      return;
    }
    this.getUIContext().animateTo({ duration: 300, curve: Curve.EaseInOut }, () => {
      this.readAloudCacheChapterListExpanded = !this.readAloudCacheChapterListExpanded;
    });
  }

  private getReadAloudCacheSegmentPreviewText(
    chapter: RemoteReadAloudCacheChapterSummary,
    maxSegments: number = 3
  ): string {
    const segments = chapter.displaySegments ?? [];
    if (segments.length <= 0) {
      return '';
    }
    const lines: string[] = [];
    const limit = Math.max(1, Math.min(maxSegments, segments.length));
    for (let index = 0; index < limit; index++) {
      const segment = segments[index];
      const preview = segment.textPreview && segment.textPreview.length > 0
        ? segment.textPreview
        : `${Math.max(0, segment.textLength)} 字符`;
      lines.push(
        `S${segment.segmentIndex + 1} · ${this.formatReadAloudCacheSegmentRange(segment)} · ${preview}`
      );
    }
    if (segments.length > limit) {
      lines.push(`还有 ${segments.length - limit} 个分片`);
    }
    return lines.join('\n');
  }

  private applyReadAloudCacheQuickRange(mode: 'uncached' | 'current' | 'full'): void {
    const total = this.readAloudCacheSummary?.chapterCount ?? this.content?.chapters.length ?? 0;
    if (total <= 0) {
      return;
    }
    if (mode === 'full') {
      this.readAloudCacheRangeStart = 0;
      this.readAloudCacheRangeEnd = total - 1;
      return;
    }
    if (mode === 'current' && this.content && this.content.lastReadChapterIndex >= 0 && this.content.lastReadChapterIndex < total) {
      this.readAloudCacheRangeStart = this.content.lastReadChapterIndex;
      this.readAloudCacheRangeEnd = total - 1;
      return;
    }
    const quickStart = Math.max(0, Math.min(this.getReadAloudCacheQuickSelectionStart(), total - 1));
    this.readAloudCacheRangeStart = quickStart;
    this.readAloudCacheRangeEnd = total - 1;
  }

  // ==================== Builder 方法 ====================

  @Builder
  buildReadAloudCacheSection() {
    if (this.supportsReadAloudCache) {
      if (!this.readAloudCacheSummary && this.isReadAloudCacheLoading) {
        Stack({ alignContent: Alignment.TopStart }) {
          this.buildGlassSectionChrome()
          Row({ space: 8 }) {
            LoadingProgress()
              .width(16)
              .height(16)
              .color(ThemeAwareHelper.getTestManagementThemedColor('text_muted', this.themeState.currentTheme))
            Text('正在加载听书缓存...')
              .fontSize(12)
              .fontFamily(this.appFontFamily)
              .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_muted', this.themeState.currentTheme))
          }
          .width('100%')
          .height(72)
          .justifyContent(FlexAlign.Center)
        }
        .width('100%')
        .backgroundColor(this.getSectionBackgroundColor())
        .backgroundBlurStyle(this.getSectionBlurStyle(), this.getSectionBlurOptions())
        .backgroundEffect(this.getSectionBackgroundEffect())
        .borderRadius(this.getSectionRadius())
        .clip(true)
        .border({ width: this.getSectionBorderWidth(), color: this.getSectionBorderColor() })
        .shadow({ radius: this.getSectionRadius() + 4, color: this.getSectionShadowColor(), offsetX: 0, offsetY: 8 })
      } else if (!this.readAloudCacheSummary) {
        Stack({ alignContent: Alignment.TopStart }) {
          this.buildGlassSectionChrome()
          Column({ space: 10 }) {
            Row({ space: 8 }) {
              SymbolGlyph($r('sys.symbol.speaker'))
                .fontSize(16)
                .fontColor([ThemeAwareHelper.getTestManagementThemedColor('text_muted', this.themeState.currentTheme)])
              Text('听书缓存暂不可用')
                .fontSize(14)
                .fontWeight(FontWeight.Medium)
                .fontFamily(this.appFontFamily)
                .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_primary', this.themeState.currentTheme))
            }
            .width('100%')

            Text('稍后可重试加载当前书籍的远程 TTS 缓存摘要。')
              .fontSize(12)
              .fontFamily(this.appFontFamily)
              .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_secondary', this.themeState.currentTheme))
              .width('100%')

            Button() {
              Row({ space: 6 }) {
                SymbolGlyph($r('sys.symbol.arrow_clockwise'))
                  .fontSize(13)
                  .fontColor([Color.White])
                Text('重新加载')
                  .fontSize(12)
                  .fontFamily(this.appFontFamily)
                  .fontColor(Color.White)
              }
            }
            .height(32)
            .padding({ left: 14, right: 14 })
            .backgroundColor(ThemeAwareHelper.getTestManagementThemedColor('accent_primary', this.themeState.currentTheme))
            .borderRadius(16)
            .onClick(() => {
              void this.loadReadAloudCacheSummary(true);
            })
          }
          .width('100%')
          .padding(18)
          .alignItems(HorizontalAlign.Start)
        }
        .width('100%')
        .backgroundColor(this.getSectionBackgroundColor())
        .backgroundBlurStyle(this.getSectionBlurStyle(), this.getSectionBlurOptions())
        .backgroundEffect(this.getSectionBackgroundEffect())
        .borderRadius(this.getSectionRadius())
        .clip(true)
        .border({ width: this.getSectionBorderWidth(), color: this.getSectionBorderColor() })
        .shadow({ radius: this.getSectionRadius() + 4, color: this.getSectionShadowColor(), offsetX: 0, offsetY: 8 })
      } else {
        Stack({ alignContent: Alignment.TopStart }) {
          this.buildGlassSectionChrome()
          Column({ space: 12 }) {
            Row({ space: 10 }) {
              Row({ space: 10 }) {
                SymbolGlyph($r('sys.symbol.speaker'))
                  .fontSize(16)
                  .fontColor([ThemeAwareHelper.getTestManagementThemedColor('accent_primary', this.themeState.currentTheme)])
                Column({ space: 2 }) {
                  Text('听书缓存')
                    .fontSize(14)
                    .fontWeight(FontWeight.Medium)
                    .fontFamily(this.appFontFamily)
                    .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_primary', this.themeState.currentTheme))
                  Text(this.isLocalTxtNovelEBook ? '本地 TXT 电子书' : '远程 TTS 章节缓存')
                    .fontSize(11)
                    .fontFamily(this.appFontFamily)
                    .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_muted', this.themeState.currentTheme))
                }
                .alignItems(HorizontalAlign.Start)
              }

              Blank()

              Row() {
                Text(`当前 ${this.readAloudCacheSummary.cachedChapterCount}/${Math.max(1, this.readAloudCacheSummary.chapterCount)}`)
                  .fontSize(11)
                  .fontWeight(FontWeight.Medium)
                  .fontFamily(this.appFontFamily)
                  .fontColor(ThemeAwareHelper.getTestManagementThemedColor('accent_primary', this.themeState.currentTheme))
              }
              .padding({ left: 10, right: 10, top: 6, bottom: 6 })
              .backgroundColor(ThemeAwareHelper.getTestManagementThemedColor('comp_background_tertiary', this.themeState.currentTheme))
              .borderRadius(12)

              SymbolGlyph($r('sys.symbol.chevron_down'))
                .fontSize(16)
                .fontColor([ThemeAwareHelper.getTestManagementThemedColor('text_muted', this.themeState.currentTheme)])
                .rotate({ angle: this.isReadAloudCacheExpanded ? 0 : -90 })
                .animation({ duration: 250, curve: Curve.EaseInOut })
                .onClick(() => {
                  this.toggleReadAloudCacheExpanded();
                })
            }
            .width('100%')
            .onClick(() => {
              this.toggleReadAloudCacheExpanded();
            })

            if (this.isReadAloudCacheExpanded) {
              Column({ space: 12 }) {
                Text(this.getReadAloudCacheSectionDescription())
                  .fontSize(12)
                  .fontFamily(this.appFontFamily)
                  .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_secondary', this.themeState.currentTheme))
                  .width('100%')

                if (this.isReadAloudPrecaching) {
                  Column({ space: 8 }) {
                    Row({ space: 8 }) {
                      LoadingProgress()
                        .width(14)
                        .height(14)
                        .color(ThemeAwareHelper.getTestManagementThemedColor('accent_green', this.themeState.currentTheme))
                      Text(this.readAloudPrecachingStatusText || '正在缓存听书音频')
                        .fontSize(12)
                        .fontWeight(FontWeight.Medium)
                        .fontFamily(this.appFontFamily)
                        .fontColor(ThemeAwareHelper.getTestManagementThemedColor('accent_green', this.themeState.currentTheme))
                      Blank()
                      Text(`${this.readAloudPrecachingChapterOrder}/${Math.max(1, this.readAloudPrecachingChapterTotal)}`)
                        .fontSize(11)
                        .fontFamily(this.appFontFamily)
                        .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_secondary', this.themeState.currentTheme))
                    }
                    .width('100%')

                    if (this.readAloudPrecachingDetailText) {
                      Text(this.readAloudPrecachingDetailText)
                        .fontSize(11)
                        .fontFamily(this.appFontFamily)
                        .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_muted', this.themeState.currentTheme))
                        .width('100%')
                    }

                    Progress({
                      value: this.readAloudPrecachingSegmentTotal > 0
                        ? Math.round((this.readAloudPrecachingSegmentDone / this.readAloudPrecachingSegmentTotal) * 100)
                        : 0,
                      total: 100,
                      type: ProgressType.Linear
                    })
                      .width('100%')
                      .height(6)
                      .color(ThemeAwareHelper.getTestManagementThemedColor('accent_green', this.themeState.currentTheme))
                      .backgroundColor(ThemeAwareHelper.getTestManagementThemedColor('comp_background_tertiary', this.themeState.currentTheme))
                      .borderRadius(3)
                  }
                  .width('100%')
                  .padding(12)
                  .backgroundColor(ThemeAwareHelper.getTestManagementThemedColor('comp_background_tertiary', this.themeState.currentTheme))
                  .borderRadius(12)
                }

                Row({ space: 8 }) {
                  this.buildReadAloudCacheMetric(
                    `${this.readAloudCacheSummary.cachedChapterCount}/${this.readAloudCacheSummary.chapterCount}`,
                    '当前命中章节',
                    ThemeAwareHelper.getTestManagementThemedColor('accent_primary', this.themeState.currentTheme)
                  )
                  this.buildReadAloudCacheMetric(
                    `${this.readAloudCacheSummary.currentSettings.totalSegments}`,
                    '当前分片',
                    ThemeAwareHelper.getTestManagementThemedColor('accent_blue', this.themeState.currentTheme)
                  )
                  this.buildReadAloudCacheMetric(
                    this.formatReadAloudCacheSize(this.readAloudCacheSummary.currentSettings.totalBytes),
                    '当前占用',
                    ThemeAwareHelper.getTestManagementThemedColor('accent_orange', this.themeState.currentTheme)
                  )
                  this.buildReadAloudCacheMetric(
                    this.getReadAloudCacheUpdatedLabel(this.readAloudCacheSummary.currentSettings.latestUpdatedAt),
                    '最近更新',
                    ThemeAwareHelper.getTestManagementThemedColor('accent_green', this.themeState.currentTheme)
                  )
                }
                .width('100%')

                Progress({ value: this.getReadAloudCacheProgressPercent(), total: 100, type: ProgressType.Linear })
                  .width('100%')
                  .height(4)
                  .color(ThemeAwareHelper.getTestManagementThemedColor('accent_primary', this.themeState.currentTheme))
                  .backgroundColor(ThemeAwareHelper.getTestManagementThemedColor('comp_background_tertiary', this.themeState.currentTheme))

                Text(`历史缓存版本 ${this.readAloudCacheSummary.variantCount} 个，历史整章音频 ${this.readAloudCacheSummary.mergedAudioCount} 个`)
                  .fontSize(11)
                  .fontFamily(this.appFontFamily)
                  .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_muted', this.themeState.currentTheme))
                  .width('100%')

                Text(`当前配置来源 ${this.readAloudCacheSummary.settingsSourceLabel} · 当前命中 ${this.readAloudCacheSummary.currentSettings.cachedChapterCount} 章 · 当前占用 ${this.formatReadAloudCacheSize(this.readAloudCacheSummary.currentSettings.totalBytes)}`)
                  .fontSize(11)
                  .fontFamily(this.appFontFamily)
                  .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_muted', this.themeState.currentTheme))
                  .width('100%')

                if ((this.readAloudCacheSummary.chapters.length ?? 0) > 0) {
                  Column({ space: 8 }) {
                    Row() {
                      Text('章节预览')
                        .fontSize(12)
                        .fontWeight(FontWeight.Medium)
                        .fontFamily(this.appFontFamily)
                        .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_primary', this.themeState.currentTheme))
                      Blank()
                      Text('可进入管理面板查看全部章节')
                        .fontSize(11)
                        .fontFamily(this.appFontFamily)
                        .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_muted', this.themeState.currentTheme))
                    }
                    .width('100%')

                    ForEach(this.getReadAloudCachePreviewIndexes(), (chapterIndex: number) => {
                      if (this.readAloudCacheSummary) {
                        this.buildReadAloudCachePreviewRow(this.readAloudCacheSummary.chapters[chapterIndex])
                      }
                    }, (chapterIndex: number) => `read_aloud_cache_preview_${chapterIndex}`)
                  }
                  .width('100%')
                }

                Row({ space: 10 }) {
                  Button() {
                    Row({ space: 6 }) {
                      SymbolGlyph($r('sys.symbol.arrow_clockwise'))
                        .fontSize(13)
                        .fontColor([ThemeAwareHelper.getTestManagementThemedColor('accent_primary', this.themeState.currentTheme)])
                      Text('刷新')
                        .fontSize(12)
                        .fontFamily(this.appFontFamily)
                        .fontColor(ThemeAwareHelper.getTestManagementThemedColor('accent_primary', this.themeState.currentTheme))
                    }
                  }
                  .layoutWeight(1)
                  .height(34)
                  .backgroundColor(ThemeAwareHelper.getTestManagementThemedColor('comp_background_secondary', this.themeState.currentTheme))
                  .borderRadius(17)
                  .enabled(!this.isReadAloudCacheLoading)
                  .onClick(() => {
                    void this.loadReadAloudCacheSummary(true);
                  })

                  Button() {
                    Row({ space: 6 }) {
                      SymbolGlyph($r('sys.symbol.gearshape'))
                        .fontSize(13)
                        .fontColor([Color.White])
                      Text('管理听书缓存')
                        .fontSize(12)
                        .fontFamily(this.appFontFamily)
                        .fontColor(Color.White)
                    }
                  }
                  .layoutWeight(1)
                  .height(34)
                  .backgroundColor(ThemeAwareHelper.getTestManagementThemedColor('accent_primary', this.themeState.currentTheme))
                  .borderRadius(17)
                  .onClick(() => {
                    this.openReadAloudCacheDialog();
                  })
                }
                .width('100%')
              }
              .width('100%')
              .transition(TransitionEffect.OPACITY.combine(TransitionEffect.translate({ y: -8 })))
            }
          }
          .width('100%')
          .padding(18)
        }
        .width('100%')
        .backgroundColor(this.getSectionBackgroundColor())
        .backgroundBlurStyle(this.getSectionBlurStyle(), this.getSectionBlurOptions())
        .backgroundEffect(this.getSectionBackgroundEffect())
        .borderRadius(this.getSectionRadius())
        .clip(true)
        .border({ width: this.getSectionBorderWidth(), color: this.getSectionBorderColor() })
        .shadow({ radius: this.getSectionRadius() + 4, color: this.getSectionShadowColor(), offsetX: 0, offsetY: 8 })
      }
    }
  }

  @Builder
  private buildReadAloudCacheMetric(value: string, label: string, accentColor: ResourceColor) {
    Column({ space: 4 }) {
      Text(value)
        .fontSize(16)
        .fontWeight(FontWeight.Bold)
        .fontFamily(this.appFontFamily)
        .fontColor(accentColor)
        .maxLines(2)
        .textAlign(TextAlign.Center)
      Text(label)
        .fontSize(11)
        .fontFamily(this.appFontFamily)
        .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_muted', this.themeState.currentTheme))
        .textAlign(TextAlign.Center)
    }
    .layoutWeight(1)
    .alignItems(HorizontalAlign.Center)
  }

  @Builder
  private buildReadAloudCachePreviewRow(chapter: RemoteReadAloudCacheChapterSummary) {
    Row({ space: 10 }) {
      Column({ space: 4 }) {
        Text(this.buildReadAloudCacheChapterLabel(chapter.chapterIndex))
          .fontSize(13)
          .fontFamily(this.appFontFamily)
          .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_primary', this.themeState.currentTheme))
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
          .width('100%')
        Text(`${this.getReadAloudCacheSegmentSourceLabel(chapter)} · ${this.getReadAloudCacheEffectiveChapterStatusText(chapter)}`)
          .fontSize(11)
          .fontFamily(this.appFontFamily)
          .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_muted', this.themeState.currentTheme))
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
          .width('100%')
        if (this.getReadAloudCacheSegmentPreviewText(chapter, 2).length > 0) {
          Text(this.getReadAloudCacheSegmentPreviewText(chapter, 2))
            .fontSize(10)
            .fontFamily(this.appFontFamily)
            .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_secondary', this.themeState.currentTheme))
            .maxLines(3)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
            .width('100%')
        }
      }
      .layoutWeight(1)
      .alignItems(HorizontalAlign.Start)

      if (!chapter.cached) {
        Button() {
          SymbolGlyph($r('sys.symbol.arrow_down_circle'))
            .fontSize(15)
            .fontColor([Color.White])
        }
        .width(30)
        .height(30)
        .backgroundColor(ThemeAwareHelper.getTestManagementThemedColor('accent_primary', this.themeState.currentTheme))
        .borderRadius(15)
        .enabled(!this.isReadAloudPrecaching)
        .onClick(() => {
          void this.quickPrecacheReadAloudChapter(chapter.chapterIndex);
        })
      } else {
        Button() {
          SymbolGlyph($r('sys.symbol.trash'))
            .fontSize(14)
            .fontColor([Color.White])
        }
        .width(30)
        .height(30)
        .backgroundColor('#FF5252')
        .borderRadius(15)
        .enabled(!this.isReadAloudPrecaching)
        .onClick(() => {
          void this.clearReadAloudCacheChapter(chapter.chapterIndex);
        })
      }
    }
    .width('100%')
    .padding(10)
    .backgroundColor(ThemeAwareHelper.getTestManagementThemedColor('comp_background_tertiary', this.themeState.currentTheme))
    .borderRadius(12)
  }

  @Builder
  buildReadAloudCacheDialog() {
    if (this.showReadAloudCacheDialog && this.content && this.supportsReadAloudCache) {
      SourceDialogScaffold({
        themeState: this.themeState,
        onMaskTap: () => {
          this.closeReadAloudCacheDialog();
        },
        dialogWidth: '90%',
        maxWidth: 640,
        contentPadding: 24,
        zIndexValue: 120,
        useMaskBlur: true
      }) {
        Column({ space: 20 }) {

          Row() {
            Text('听书缓存')
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
            .onClick(() => {
              this.closeReadAloudCacheDialog();
            })
          }
          .width('100%')

          Row({ space: 8 }) {
            this.buildReadAloudCacheDialogTabButton('缓存', $r('sys.symbol.arrow_down_circle'), 0)
            this.buildReadAloudCacheDialogTabButton('管理', $r('sys.symbol.list_bullet'), 1)
            this.buildReadAloudCacheDialogTabButton('设置', $r('sys.symbol.gearshape'), 2)
          }
          .width('100%')
          .padding(4)
          .backgroundColor(ThemeAwareHelper.getTestManagementThemedColor('comp_background_tertiary',
            this.themeState.currentTheme))
          .borderRadius(18)

          if (this.isReadAloudPrecaching) {
            Column({ space: 8 }) {
              Row({ space: 8 }) {
                LoadingProgress()
                  .width(14)
                  .height(14)
                  .color(ThemeAwareHelper.getTestManagementThemedColor('accent_green', this.themeState.currentTheme))
                Text(this.readAloudPrecachingStatusText || '正在缓存听书音频')
                  .fontSize(12)
                  .fontWeight(FontWeight.Medium)
                  .fontFamily(this.appFontFamily)
                  .fontColor(ThemeAwareHelper.getTestManagementThemedColor('accent_green',
                    this.themeState.currentTheme))
                Blank()
                Text(this.formatReadAloudCacheSize(this.readAloudPrecachingBytes))
                  .fontSize(11)
                  .fontFamily(this.appFontFamily)
                  .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_secondary',
                    this.themeState.currentTheme))
              }
              .width('100%')

              if (this.readAloudPrecachingDetailText) {
                Text(this.readAloudPrecachingDetailText)
                  .fontSize(11)
                  .fontFamily(this.appFontFamily)
                  .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_muted',
                    this.themeState.currentTheme))
                  .width('100%')
              }

              Progress({
                value: this.readAloudPrecachingSegmentTotal > 0
                  ? Math.round((this.readAloudPrecachingSegmentDone / this.readAloudPrecachingSegmentTotal) * 100)
                  : 0,
                total: 100,
                type: ProgressType.Linear
              })
                .width('100%')
                .height(6)
                .color(ThemeAwareHelper.getTestManagementThemedColor('accent_green', this.themeState.currentTheme))
                .backgroundColor(ThemeAwareHelper.getTestManagementThemedColor('comp_background_secondary',
                  this.themeState.currentTheme))
                .borderRadius(3)
            }
            .width('100%')
            .padding(12)
            .backgroundColor(ThemeAwareHelper.getTestManagementThemedColor('comp_background_tertiary',
              this.themeState.currentTheme))
            .borderRadius(12)
            .transition(this.getReadAloudCacheFadeSlideTransition(8))
          }

          Scroll() {
            Column({ space: 12 }) {
              if (this.readAloudCacheDialogActiveTab === 0) {
                this.buildReadAloudCacheChapterSelectionTab()
              } else if (this.readAloudCacheDialogActiveTab === 1) {
                this.buildReadAloudCacheManagementTab()
              } else {
                this.buildReadAloudCacheSettingsTab()
              }
            }
            .width('100%')
            .alignItems(HorizontalAlign.Start)
            .animation({ duration: 220, curve: Curve.EaseOut })
          }
          .width('100%')
          .constraintSize({ maxHeight: 500 })
          .scrollBar(BarState.Auto)

          this.buildReadAloudCacheDialogFooter()
        }
        .width('100%')
      }
    }
  }


  @Builder
  private buildReadAloudCacheDialogTabButton(label: string, icon: Resource, index: number) {
    Row({ space: 6 }) {
      SymbolGlyph(icon)
        .fontSize(13)
        .fontColor([this.readAloudCacheDialogActiveTab === index
          ? Color.White
          : ThemeAwareHelper.getTestManagementThemedColor('text_secondary', this.themeState.currentTheme)])
      Text(label)
        .fontSize(13)
        .fontFamily(this.appFontFamily)
        .fontWeight(FontWeight.Medium)
        .fontColor(this.readAloudCacheDialogActiveTab === index
          ? Color.White
          : ThemeAwareHelper.getTestManagementThemedColor('text_secondary', this.themeState.currentTheme))
    }
    .layoutWeight(1)
    .height(34)
    .justifyContent(FlexAlign.Center)
    .backgroundColor(this.readAloudCacheDialogActiveTab === index
      ? ThemeAwareHelper.getTestManagementThemedColor('accent_primary', this.themeState.currentTheme)
      : Color.Transparent)
    .borderRadius(14)
    .scale({
      x: this.readAloudCacheDialogActiveTab === index ? 1 : 0.97,
      y: this.readAloudCacheDialogActiveTab === index ? 1 : 0.97
    })
    .animation({ duration: 160, curve: Curve.EaseOut })
    .onClick(() => {
      this.handleReadAloudCacheDialogTabChange(index);
    })
  }

  private formatReadAloudCacheDuration(durationMs: number): string {
    const safeMs = Math.max(0, Math.floor(durationMs));
    if (safeMs <= 0) {
      return '0s';
    }
    const totalSeconds = Math.round(safeMs / 1000);
    const minutes = Math.floor(totalSeconds / 60);
    const seconds = totalSeconds % 60;
    return minutes > 0 ? `${minutes}m ${seconds}s` : `${seconds}s`;
  }

  private getReadAloudCacheDigestShortLabel(digest: string | undefined): string {
    const normalized = (digest ?? '').trim();
    if (normalized.length <= 8) {
      return normalized.length > 0 ? normalized : '未生成';
    }
    return `${normalized.slice(0, 8)}…`;
  }

  private getReadAloudCachePercentValue(numerator: number, denominator: number): number {
    const safeNumerator = Number.isFinite(numerator) ? Math.max(0, numerator) : 0;
    const safeDenominator = Number.isFinite(denominator) ? Math.max(0, denominator) : 0;
    if (safeDenominator <= 0) {
      return 0;
    }
    return Math.max(0, Math.min(100, (safeNumerator / safeDenominator) * 100));
  }

  private formatReadAloudCacheCoveragePercent(coveredTextChars: number, totalTextChars: number): string {
    return `${this.getReadAloudCachePercentValue(coveredTextChars, totalTextChars).toFixed(1)}%`;
  }

  private formatReadAloudCacheMatchPercent(score: number): string {
    const safeScore = Number.isFinite(score) ? Math.max(0, Math.min(1, score)) : 0;
    return `${(safeScore * 100).toFixed(1)}%`;
  }

  private getReadAloudCacheSuggestedTargetReasonText(reason: string | undefined): string {
    switch (reason) {
      case 'exact_digest':
        return '文本摘要一致';
      case 'cache_key':
        return '缓存键一致';
      case 'range_overlap':
        return '字符区间最接近';
      case 'preview_similarity':
        return '文本预览最相似';
      case 'length_similarity':
        return '文本长度最接近';
      case 'segment_index':
        return '分段序号接近';
      default:
        return '弱匹配，仅供参考';
    }
  }

  private getReadAloudCacheSuggestedTargetLabel(segment: RemoteReadAloudCacheSegmentDetail): string {
    const suggestion = this.getEffectiveReadAloudCacheSuggestedTarget(segment);
    if (!suggestion) {
      if (segment.suggestedTargets.length > 0 && this.getReadAloudCacheBlockedSuggestionCount(segment) > 0) {
        return '当前已禁止所有建议匹配，可继续手动指定槽位';
      }
      return '暂未找到可建议的目标槽位';
    }
    const blockedCount = this.getReadAloudCacheBlockedSuggestionCount(segment);
    const blockedSuffix = blockedCount > 0 ? ` · 已跳过 ${blockedCount} 个建议` : '';
    return `最匹配目标槽位 S${suggestion.targetSegmentIndex + 1} · ${this.formatReadAloudCacheMatchPercent(suggestion.score)} · ${this.getReadAloudCacheSuggestedTargetReasonText(suggestion.reason)}${blockedSuffix}`;
  }

  private getReadAloudCacheSuggestedTargetDetailText(segment: RemoteReadAloudCacheSegmentDetail): string {
    const suggestion = this.getEffectiveReadAloudCacheSuggestedTarget(segment);
    const detail = this.readAloudCacheManageDetail;
    if (!suggestion || !detail) {
      return '';
    }
    const target = detail.targetSegments.find((item: RemoteReadAloudCacheTargetSegment) =>
      item.segmentIndex === suggestion.targetSegmentIndex
    ) ?? null;
    if (!target) {
      return '';
    }
    const preview = target.textPreview.length > 0 ? target.textPreview : `${target.textLength} 字符`;
    return `目标范围 ${this.formatReadAloudCacheTargetSegmentRange(target)} · ${preview}`;
  }

  private getReadAloudCacheSuggestedTargetColor(segment: RemoteReadAloudCacheSegmentDetail): ResourceColor {
    const suggestion = this.getEffectiveReadAloudCacheSuggestedTarget(segment);
    if (!suggestion) {
      return ThemeAwareHelper.getTestManagementThemedColor('text_muted', this.themeState.currentTheme);
    }
    if (suggestion.score >= 0.85) {
      return ThemeAwareHelper.getTestManagementThemedColor('accent_green', this.themeState.currentTheme);
    }
    if (suggestion.score >= 0.6) {
      return ThemeAwareHelper.getTestManagementThemedColor('accent_primary', this.themeState.currentTheme);
    }
    return ThemeAwareHelper.getTestManagementThemedColor('accent_orange', this.themeState.currentTheme);
  }

  private getReadAloudCacheSuggestedAttachButtonText(segment: RemoteReadAloudCacheSegmentDetail): string {
    const suggestion = this.getEffectiveReadAloudCacheSuggestedTarget(segment);
    if (!suggestion) {
      return '暂无建议槽位';
    }
    return `按建议匹配到 S${suggestion.targetSegmentIndex + 1}`;
  }

  private hasReadAloudCacheSuggestedTarget(segment: RemoteReadAloudCacheSegmentDetail): boolean {
    return this.getEffectiveReadAloudCacheSuggestedTarget(segment) !== null;
  }

  private getReadAloudCacheTargetStatusText(segment: RemoteReadAloudCacheTargetSegment): string {
    if (!segment.attachedSegment) {
      return '当前槽位尚未挂接音频';
    }
    const matchMode = segment.attachedSegment.matchMode === 'manual' ? '手动挂接' : '自动命中';
    return `${matchMode} · ${this.formatReadAloudCacheSize(segment.attachedSegment.bytes)} · ${this.formatReadAloudCacheDuration(segment.attachedSegment.durationMs)}`;
  }

  private getReadAloudCacheSourceSegmentStatusText(segment: RemoteReadAloudCacheSegmentDetail): string {
    const labels: string[] = [];
    switch (segment.matchMode) {
      case 'current_unmatched':
        labels.push('当前残留');
        break;
      case 'manual':
        labels.push('手动挂接');
        break;
      default:
        labels.push('历史缓存');
        break;
    }
    labels.push(segment.isCurrentConfigMatch ? '同配置' : '跨配置');
    labels.push(segment.isCurrentTextMatch ? '同文本版本' : '历史文本版本');
    labels.push(`S${segment.segmentIndex + 1}`);
    labels.push(this.formatReadAloudCacheSize(segment.bytes));
    return labels.join(' · ');
  }

  private getReadAloudCacheManageSummaryText(): string {
    if (this.readAloudCacheDialogActiveTab === 0) {
      return this.getReadAloudCacheSelectionSummary();
    }
    if (this.readAloudCacheDialogActiveTab === 1) {
      const chapterLabel = this.buildReadAloudCacheChapterLabel(this.readAloudCacheManageChapterIndex);
      const targetLabel = this.readAloudCacheManageSelectedTargetIndex >= 0
        ? `已选槽位 S${this.readAloudCacheManageSelectedTargetIndex + 1}`
        : '未选择目标槽位';
      return `${chapterLabel} · ${targetLabel}`;
    }
    return this.getReadAloudCachePresetSummary();
  }

  @Builder
  private buildReadAloudCacheDialogFooter() {
    Column({ space: 10 }) {
      Row() {
        Text(this.getReadAloudCacheManageSummaryText())
          .fontSize(12)
          .fontFamily(this.appFontFamily)
          .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_secondary', this.themeState.currentTheme))
        Blank()
        if (this.readAloudCacheSummary) {
          Text(`总占用 ${this.formatReadAloudCacheSize(this.readAloudCacheSummary.totalBytes)}`)
            .fontSize(12)
            .fontFamily(this.appFontFamily)
            .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_muted', this.themeState.currentTheme))
        }
      }
      .width('100%')

      if (this.readAloudCacheDialogActiveTab === 0) {
        Row({ space: 10 }) {
          Button() {
            Row({ space: 6 }) {
              SymbolGlyph($r('sys.symbol.trash'))
                .fontSize(13)
                .fontColor([ThemeAwareHelper.getTestManagementThemedColor('color_error', this.themeState.currentTheme)])
              Text('清理本书缓存')
                .fontSize(12)
                .fontFamily(this.appFontFamily)
                .fontColor(ThemeAwareHelper.getTestManagementThemedColor('color_error', this.themeState.currentTheme))
            }
          }
          .layoutWeight(1)
          .height(36)
          .backgroundColor(ThemeAwareHelper.getTestManagementThemedColor('comp_background_secondary', this.themeState.currentTheme))
          .borderRadius(18)
          .enabled((this.readAloudCacheSummary?.totalBytes ?? 0) > 0 && !this.isReadAloudPrecaching)
          .onClick(() => {
            void this.clearReadAloudCacheBook();
          })

          Button() {
            Row({ space: 6 }) {
              SymbolGlyph($r('sys.symbol.arrow_down_circle'))
                .fontSize(13)
                .fontColor([Color.White])
              Text(this.isReadAloudPrecaching ? '缓存中...' : `开始缓存 ${this.getSelectedReadAloudChapterCount()} 章`)
                .fontSize(12)
                .fontFamily(this.appFontFamily)
                .fontColor(Color.White)
            }
          }
          .layoutWeight(1)
          .height(36)
          .backgroundColor(ThemeAwareHelper.getTestManagementThemedColor('accent_primary', this.themeState.currentTheme))
          .borderRadius(18)
          .enabled(!this.isReadAloudPrecaching)
          .onClick(() => {
            void this.startReadAloudCacheTaskFromDialog();
          })
        }
        .width('100%')
      } else if (this.readAloudCacheDialogActiveTab === 1) {
        Row({ space: 10 }) {
          Button('清理本章')
            .layoutWeight(1)
            .height(36)
            .fontSize(12)
            .fontFamily(this.appFontFamily)
            .backgroundColor(ThemeAwareHelper.getTestManagementThemedColor('comp_background_secondary', this.themeState.currentTheme))
            .fontColor(ThemeAwareHelper.getTestManagementThemedColor('color_error', this.themeState.currentTheme))
            .borderRadius(18)
            .enabled(!this.isReadAloudPrecaching && !this.isReadAloudCacheManageMutating)
            .onClick(() => {
              void this.clearReadAloudCacheChapter(this.readAloudCacheManageChapterIndex);
            })

          Button(this.isReadAloudCacheManageLoading ? '刷新中...' : '刷新明细')
            .layoutWeight(1)
            .height(36)
            .fontSize(12)
            .fontFamily(this.appFontFamily)
            .backgroundColor(ThemeAwareHelper.getTestManagementThemedColor('accent_primary', this.themeState.currentTheme))
            .fontColor(Color.White)
            .borderRadius(18)
            .enabled(!this.isReadAloudCacheManageLoading && !this.isReadAloudCacheManageMutating)
            .onClick(() => {
              void this.loadReadAloudCacheManageDetail(true);
            })
        }
            .width('100%')
            .transition(this.getReadAloudCacheFadeSlideTransition(8))
        } else {
        Row({ space: 10 }) {
          Button() {
            Row({ space: 6 }) {
              SymbolGlyph($r('sys.symbol.trash'))
                .fontSize(13)
                .fontColor([ThemeAwareHelper.getTestManagementThemedColor('color_error', this.themeState.currentTheme)])
              Text('清理本书缓存')
                .fontSize(12)
                .fontFamily(this.appFontFamily)
                .fontColor(ThemeAwareHelper.getTestManagementThemedColor('color_error', this.themeState.currentTheme))
            }
          }
          .layoutWeight(1)
          .height(36)
          .backgroundColor(ThemeAwareHelper.getTestManagementThemedColor('comp_background_secondary', this.themeState.currentTheme))
          .borderRadius(18)
          .enabled((this.readAloudCacheSummary?.totalBytes ?? 0) > 0 && !this.isReadAloudPrecaching)
          .onClick(() => {
            void this.clearReadAloudCacheBook();
          })

          Button(this.isReadAloudCurrentSettingsSaving ? '保存中...' : '设为当前内容默认')
            .layoutWeight(1)
            .height(36)
            .fontSize(12)
            .fontFamily(this.appFontFamily)
            .backgroundColor(ThemeAwareHelper.getTestManagementThemedColor('accent_primary', this.themeState.currentTheme))
            .fontColor(Color.White)
            .borderRadius(18)
            .enabled(!this.isReadAloudCurrentSettingsSaving)
            .onClick(() => {
              void this.applyReadAloudCacheTaskSettingsToCurrent();
            })
        }
        .width('100%')
      }
    }
    .width('100%')
    .animation({ duration: 200, curve: Curve.EaseOut })
  }

  @Builder
  private buildReadAloudCacheManagementTab() {
    Column({ space: 12 }) {
      Column({ space: 10 }) {
        Row() {
          Text('章节管理')
            .fontSize(14)
            .fontWeight(FontWeight.Medium)
            .fontFamily(this.appFontFamily)
            .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_primary', this.themeState.currentTheme))
          Blank()
          if (this.readAloudCacheManageDetail) {
            Text(`精确命中 ${this.readAloudCacheManageDetail.currentExactMatchedCount}/${this.readAloudCacheManageDetail.targetSegments.length}`)
              .fontSize(12)
              .fontFamily(this.appFontFamily)
              .fontColor(ThemeAwareHelper.getTestManagementThemedColor('accent_primary', this.themeState.currentTheme))
          }
        }
        .width('100%')

        Text('这里会同时显示当前文本应该生成的目标分段槽位、当前已挂接的音频，以及历史版本里可复用的音频来源。选中一个目标槽位后，就可以把任意历史分段手动挂接过来。')
          .fontSize(12)
          .fontFamily(this.appFontFamily)
          .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_secondary', this.themeState.currentTheme))
          .width('100%')

        if (this.readAloudCacheManageDetail) {
          Text(`当前文本摘要 ${this.getReadAloudCacheDigestShortLabel(this.readAloudCacheManageDetail.currentContentDigest)} · 当前配置摘要 ${this.getReadAloudCacheDigestShortLabel(this.readAloudCacheManageDetail.currentRemoteDigest)}`)
            .fontSize(11)
            .fontFamily(this.appFontFamily)
            .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_muted', this.themeState.currentTheme))
            .width('100%')
        }
      }
      .width('100%')
      .padding(12)
      .backgroundColor(ThemeAwareHelper.getTestManagementThemedColor('comp_background_tertiary', this.themeState.currentTheme))
      .borderRadius(12)
      .transition(this.getReadAloudCacheFadeSlideTransition(6))

      this.buildReadAloudCacheCoverageCard()

      Column({ space: 10 }) {
        Row() {
          Text('选择章节')
            .fontSize(14)
            .fontWeight(FontWeight.Medium)
            .fontFamily(this.appFontFamily)
            .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_primary', this.themeState.currentTheme))
          Blank()
          Text(`当前：${this.buildReadAloudCacheChapterLabel(this.readAloudCacheManageChapterIndex)}`)
            .fontSize(12)
            .fontFamily(this.appFontFamily)
            .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_secondary', this.themeState.currentTheme))
          Button() {
            SymbolGlyph($r(this.readAloudCacheManageChapterSectionExpanded ? 'sys.symbol.chevron_down' : 'sys.symbol.chevron_right'))
              .fontSize(14)
              .fontColor([ThemeAwareHelper.getTestManagementThemedColor('text_secondary', this.themeState.currentTheme)])
              .rotate({ angle: this.readAloudCacheManageChapterSectionExpanded ? 0 : -90 })
              .animation({ duration: 250, curve: Curve.EaseInOut })
          }
          .width(28)
          .height(28)
          .backgroundColor(Color.Transparent)
          .onClick(() => {
            this.toggleReadAloudCacheManageSection('chapter');
          })
        }
        .width('100%')

        if (this.readAloudCacheManageChapterSectionExpanded) {
          Scroll() {
            Column({ space: 8 }) {
              ForEach(this.readAloudCacheSummary?.chapters ?? [], (chapter: RemoteReadAloudCacheChapterSummary) => {
                this.buildReadAloudCacheManageChapterRow(chapter)
              }, (chapter: RemoteReadAloudCacheChapterSummary) => `read_aloud_cache_manage_${chapter.chapterIndex}`)
            }
            .width('100%')
          }
          .width('100%')
          .constraintSize({ maxHeight: 180 })
          .scrollBar(BarState.Auto)
          .transition(this.getReadAloudCacheFadeSlideTransition(8))
        } else {
          Text('章节列表已收起，展开后可切换当前管理章节。')
            .fontSize(11)
            .fontFamily(this.appFontFamily)
            .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_muted', this.themeState.currentTheme))
            .width('100%')
            .transition(this.getReadAloudCacheFadeSlideTransition(6))
        }
      }
      .width('100%')
      .padding(12)
      .backgroundColor(ThemeAwareHelper.getTestManagementThemedColor('comp_background_tertiary', this.themeState.currentTheme))
      .borderRadius(12)
      .transition(this.getReadAloudCacheFadeSlideTransition(8))

      if (this.isReadAloudCacheManageLoading) {
        Row({ space: 8 }) {
          LoadingProgress()
            .width(16)
            .height(16)
            .color(ThemeAwareHelper.getTestManagementThemedColor('accent_primary', this.themeState.currentTheme))
          Text('正在加载章节缓存明细...')
            .fontSize(12)
            .fontFamily(this.appFontFamily)
            .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_secondary', this.themeState.currentTheme))
        }
        .width('100%')
        .padding(14)
        .justifyContent(FlexAlign.Center)
        .backgroundColor(ThemeAwareHelper.getTestManagementThemedColor('comp_background_tertiary', this.themeState.currentTheme))
        .borderRadius(12)
        .transition(this.getReadAloudCacheFadeSlideTransition(10))
      } else if (this.readAloudCacheManageDetail) {
        Column({ space: 12 }) {
          Column({ space: 8 }) {
            Row() {
              Text('目标文本槽位')
                .fontSize(14)
                .fontWeight(FontWeight.Medium)
                .fontFamily(this.appFontFamily)
                .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_primary', this.themeState.currentTheme))
              Blank()
              Text(this.readAloudCacheManageSelectedTargetIndex >= 0
                ? `已选 S${this.readAloudCacheManageSelectedTargetIndex + 1}`
                : '请选择一个槽位')
                .fontSize(12)
                .fontFamily(this.appFontFamily)
                .fontColor(ThemeAwareHelper.getTestManagementThemedColor('accent_primary', this.themeState.currentTheme))
              Button() {
                SymbolGlyph($r(this.readAloudCacheManageTargetSectionExpanded ? 'sys.symbol.chevron_down' : 'sys.symbol.chevron_right'))
                  .fontSize(14)
                  .fontColor([ThemeAwareHelper.getTestManagementThemedColor('text_secondary', this.themeState.currentTheme)])
                  .rotate({ angle: this.readAloudCacheManageTargetSectionExpanded ? 0 : -90 })
                  .animation({ duration: 250, curve: Curve.EaseInOut })
              }
              .width(28)
              .height(28)
              .backgroundColor(Color.Transparent)
              .onClick(() => {
                this.toggleReadAloudCacheManageSection('target');
              })
            }
            .width('100%')

            if (this.readAloudCacheManageTargetSectionExpanded) {
              ForEach(this.readAloudCacheManageDetail.targetSegments, (segment: RemoteReadAloudCacheTargetSegment) => {
                this.buildReadAloudCacheTargetSegmentRow(segment)
              }, (segment: RemoteReadAloudCacheTargetSegment) => `read_aloud_target_${segment.segmentIndex}`)
            } else {
              Text('目标槽位列表已收起，展开后可查看每个文本槽位的挂接情况。')
                .fontSize(11)
                .fontFamily(this.appFontFamily)
                .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_muted', this.themeState.currentTheme))
                .width('100%')
                .transition(this.getReadAloudCacheFadeSlideTransition(6))
            }
          }
          .width('100%')
          .padding(12)
          .backgroundColor(ThemeAwareHelper.getTestManagementThemedColor('comp_background_tertiary', this.themeState.currentTheme))
          .borderRadius(12)
          .transition(this.getReadAloudCacheFadeSlideTransition(8))

          Column({ space: 8 }) {
            Row() {
              Text('可复用音频来源')
                .fontSize(14)
                .fontWeight(FontWeight.Medium)
                .fontFamily(this.appFontFamily)
                .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_primary', this.themeState.currentTheme))
              Blank()
              Text(`来源 ${this.readAloudCacheManageDetail.sourceSegments.length} 个`)
                .fontSize(12)
                .fontFamily(this.appFontFamily)
                .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_secondary', this.themeState.currentTheme))
              Button() {
                SymbolGlyph($r(this.readAloudCacheManageSourceSectionExpanded ? 'sys.symbol.chevron_down' : 'sys.symbol.chevron_right'))
                  .fontSize(14)
                  .fontColor([ThemeAwareHelper.getTestManagementThemedColor('text_secondary', this.themeState.currentTheme)])
                  .rotate({ angle: this.readAloudCacheManageSourceSectionExpanded ? 0 : -90 })
                  .animation({ duration: 250, curve: Curve.EaseInOut })
              }
              .width(28)
              .height(28)
              .backgroundColor(Color.Transparent)
              .onClick(() => {
                this.toggleReadAloudCacheManageSection('source');
              })
            }
            .width('100%')

            if (this.readAloudCacheManageStatusMessage.length > 0) {
              Text(this.readAloudCacheManageStatusMessage)
                .fontSize(11)
                .fontFamily(this.appFontFamily)
                .fontColor(ThemeAwareHelper.getTestManagementThemedColor('accent_primary', this.themeState.currentTheme))
                .width('100%')
                .transition(this.getReadAloudCacheFadeSlideTransition(6))
            }

            if (!this.readAloudCacheManageSourceSectionExpanded) {
              Text('可复用音频列表已收起，展开后可继续查看建议槽位、快速匹配和禁止建议操作。')
                .fontSize(11)
                .fontFamily(this.appFontFamily)
                .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_muted', this.themeState.currentTheme))
                .width('100%')
                .transition(this.getReadAloudCacheFadeSlideTransition(6))
            } else if (this.readAloudCacheManageDetail.sourceSegments.length <= 0) {
              Text('当前没有可复用的历史分段。可以先缓存本章，或者切换到其他章节查看历史版本。')
                .fontSize(12)
                .fontFamily(this.appFontFamily)
                .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_secondary', this.themeState.currentTheme))
                .width('100%')
            } else {
              ForEach(this.readAloudCacheManageDetail.sourceSegments, (segment: RemoteReadAloudCacheSegmentDetail) => {
                this.buildReadAloudCacheSourceSegmentRow(segment)
              }, (segment: RemoteReadAloudCacheSegmentDetail) =>
                `read_aloud_source_${segment.manifestPath}_${segment.segmentIndex}`
              )
            }
          }
          .width('100%')
          .padding(12)
          .backgroundColor(ThemeAwareHelper.getTestManagementThemedColor('comp_background_tertiary', this.themeState.currentTheme))
          .borderRadius(12)
          .transition(this.getReadAloudCacheFadeSlideTransition(10))

          Column({ space: 8 }) {
            Row() {
              Text('Manifest 版本')
                .fontSize(14)
                .fontWeight(FontWeight.Medium)
                .fontFamily(this.appFontFamily)
                .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_primary', this.themeState.currentTheme))
              Blank()
              Text(`${this.readAloudCacheManageDetail.manifests.length} 个版本`)
                .fontSize(12)
                .fontFamily(this.appFontFamily)
                .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_secondary', this.themeState.currentTheme))
            }
            .width('100%')

            ForEach(this.readAloudCacheManageDetail.manifests, (manifest: RemoteReadAloudCacheManifestSummary) => {
              Column({ space: 4 }) {
                Text(`${manifest.isCurrentManifest ? '当前版本' : '历史版本'} · ${manifest.segmentCount} 段 · ${this.formatReadAloudCacheSize(manifest.mergedFileBytes)} 整章音频`)
                  .fontSize(12)
                  .fontFamily(this.appFontFamily)
                  .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_primary', this.themeState.currentTheme))
                  .width('100%')
                Text(`文本 ${this.getReadAloudCacheDigestShortLabel(manifest.contentDigest)} · 配置 ${this.getReadAloudCacheDigestShortLabel(manifest.remoteDigest)} · ${this.getReadAloudCacheUpdatedLabel(manifest.updatedAt)}`)
                  .fontSize(11)
                  .fontFamily(this.appFontFamily)
                  .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_muted', this.themeState.currentTheme))
                  .width('100%')
              }
              .width('100%')
              .padding(10)
              .backgroundColor(ThemeAwareHelper.getTestManagementThemedColor('comp_background_secondary', this.themeState.currentTheme))
              .borderRadius(10)
              .animation({ duration: 180, curve: Curve.EaseOut })
            }, (manifest: RemoteReadAloudCacheManifestSummary) => `read_aloud_manifest_${manifest.manifestPath}`)
          }
          .width('100%')
          .padding(12)
          .backgroundColor(ThemeAwareHelper.getTestManagementThemedColor('comp_background_tertiary', this.themeState.currentTheme))
          .borderRadius(12)
          .transition(this.getReadAloudCacheFadeSlideTransition(12))
        }
        .width('100%')
        .transition(this.getReadAloudCacheFadeSlideTransition(12))
      }
    }
    .width('100%')
    .transition(this.getReadAloudCacheFadeSlideTransition(12))
  }

  @Builder
  private buildReadAloudCacheCoverageCard() {
    Column({ space: 10 }) {
      Row() {
        Text('覆盖情况')
          .fontSize(14)
          .fontWeight(FontWeight.Medium)
          .fontFamily(this.appFontFamily)
          .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_primary', this.themeState.currentTheme))
        Blank()
        Text(`当前章节：${this.buildReadAloudCacheChapterLabel(this.readAloudCacheManageChapterIndex)}`)
          .fontSize(12)
          .fontFamily(this.appFontFamily)
          .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_secondary', this.themeState.currentTheme))
      }
      .width('100%')

      if (
        this.readAloudCacheManageDetail &&
        this.readAloudCacheManageDetail.chapterIndex === this.readAloudCacheManageChapterIndex
      ) {
        Text(`已命中 ${this.readAloudCacheManageDetail.coverage.coveredTextChars}/${this.readAloudCacheManageDetail.coverage.totalTextChars} 字`)
          .fontSize(12)
          .fontFamily(this.appFontFamily)
          .fontColor(ThemeAwareHelper.getTestManagementThemedColor('accent_primary', this.themeState.currentTheme))
          .width('100%')

        Row({ space: 8 }) {
          this.buildReadAloudCacheMetric(
            this.formatReadAloudCacheCoveragePercent(
              this.readAloudCacheManageDetail.coverage.coveredTextChars,
              this.readAloudCacheManageDetail.coverage.totalTextChars
            ),
            '文本覆盖率',
            ThemeAwareHelper.getTestManagementThemedColor('accent_primary', this.themeState.currentTheme)
          )
          this.buildReadAloudCacheMetric(
            `${this.readAloudCacheManageDetail.coverage.coveredTargetCount}/${this.readAloudCacheManageDetail.coverage.totalTargetCount}`,
            '已命中槽位',
            ThemeAwareHelper.getTestManagementThemedColor('accent_green', this.themeState.currentTheme)
          )
          this.buildReadAloudCacheMetric(
            `${this.readAloudCacheManageDetail.coverage.uncoveredTextChars} 字`,
            '待补全文本',
            ThemeAwareHelper.getTestManagementThemedColor('accent_orange', this.themeState.currentTheme)
          )
        }
        .width('100%')

        Progress({
          value: this.getReadAloudCachePercentValue(
            this.readAloudCacheManageDetail.coverage.coveredTextChars,
            this.readAloudCacheManageDetail.coverage.totalTextChars
          ),
          total: 100,
          type: ProgressType.Linear
        })
          .width('100%')
          .height(6)
          .color(ThemeAwareHelper.getTestManagementThemedColor('accent_primary', this.themeState.currentTheme))
          .backgroundColor(ThemeAwareHelper.getTestManagementThemedColor('comp_background_secondary', this.themeState.currentTheme))
          .borderRadius(3)

        Column({ space: 4 }) {
          Text(`自动命中 ${this.readAloudCacheManageDetail.coverage.exactCoveredTextChars} 字 · ${this.formatReadAloudCacheCoveragePercent(this.readAloudCacheManageDetail.coverage.exactCoveredTextChars, this.readAloudCacheManageDetail.coverage.totalTextChars)} · ${this.readAloudCacheManageDetail.coverage.exactCoveredTargetCount} 个槽位`)
            .fontSize(11)
            .fontFamily(this.appFontFamily)
            .fontColor(ThemeAwareHelper.getTestManagementThemedColor('accent_green', this.themeState.currentTheme))
            .width('100%')
          Text(`手动挂接 ${this.readAloudCacheManageDetail.coverage.manualCoveredTextChars} 字 · ${this.formatReadAloudCacheCoveragePercent(this.readAloudCacheManageDetail.coverage.manualCoveredTextChars, this.readAloudCacheManageDetail.coverage.totalTextChars)} · ${this.readAloudCacheManageDetail.coverage.manualCoveredTargetCount} 个槽位`)
            .fontSize(11)
            .fontFamily(this.appFontFamily)
            .fontColor(ThemeAwareHelper.getTestManagementThemedColor('accent_blue', this.themeState.currentTheme))
            .width('100%')
          Text(`待补全文本 ${this.readAloudCacheManageDetail.coverage.uncoveredTextChars} 字 · ${this.formatReadAloudCacheCoveragePercent(this.readAloudCacheManageDetail.coverage.uncoveredTextChars, this.readAloudCacheManageDetail.coverage.totalTextChars)} · ${this.readAloudCacheManageDetail.coverage.uncoveredTargetCount} 个槽位`)
            .fontSize(11)
            .fontFamily(this.appFontFamily)
            .fontColor(ThemeAwareHelper.getTestManagementThemedColor('accent_orange', this.themeState.currentTheme))
            .width('100%')
        }
        .width('100%')
        .transition(this.getReadAloudCacheFadeSlideTransition(6))

        Text('按当前已选择章节的文本字数实时统计，自动命中和手动挂接都会计入已覆盖。')
          .fontSize(11)
          .fontFamily(this.appFontFamily)
          .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_muted', this.themeState.currentTheme))
          .width('100%')
      } else {
        Row({ space: 8 }) {
          LoadingProgress()
            .width(14)
            .height(14)
            .color(ThemeAwareHelper.getTestManagementThemedColor('accent_primary', this.themeState.currentTheme))
          Text('正在刷新当前章节的覆盖情况...')
            .fontSize(12)
            .fontFamily(this.appFontFamily)
            .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_secondary', this.themeState.currentTheme))
        }
        .width('100%')
        .transition(this.getReadAloudCacheFadeSlideTransition(6))
      }
    }
    .width('100%')
    .padding(12)
    .backgroundColor(ThemeAwareHelper.getTestManagementThemedColor('comp_background_tertiary', this.themeState.currentTheme))
    .borderRadius(12)
    .animation({ duration: 220, curve: Curve.EaseOut })
    .transition(this.getReadAloudCacheFadeSlideTransition(7))
  }

  @Builder
  private buildReadAloudCacheManageChapterRow(chapter: RemoteReadAloudCacheChapterSummary) {
    Row({ space: 10 }) {
      Column({ space: 4 }) {
        Text(this.buildReadAloudCacheChapterLabel(chapter.chapterIndex))
          .fontSize(13)
          .fontFamily(this.appFontFamily)
          .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_primary', this.themeState.currentTheme))
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
          .width('100%')
        Text(`${this.getReadAloudCacheSegmentSourceLabel(chapter)} · ${this.getReadAloudCacheEffectiveChapterStatusText(chapter)}`)
          .fontSize(11)
          .fontFamily(this.appFontFamily)
          .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_muted', this.themeState.currentTheme))
          .maxLines(2)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
          .width('100%')
      }
      .layoutWeight(1)
      .alignItems(HorizontalAlign.Start)

      SymbolGlyph($r(this.readAloudCacheManageChapterIndex === chapter.chapterIndex ? 'sys.symbol.checkmark_circle_fill' : 'sys.symbol.chevron_right'))
        .fontSize(16)
        .fontColor([this.readAloudCacheManageChapterIndex === chapter.chapterIndex
          ? ThemeAwareHelper.getTestManagementThemedColor('accent_primary', this.themeState.currentTheme)
          : ThemeAwareHelper.getTestManagementThemedColor('text_muted', this.themeState.currentTheme)])
    }
    .width('100%')
    .padding(10)
    .backgroundColor(this.readAloudCacheManageChapterIndex === chapter.chapterIndex
      ? ThemeAwareHelper.getTestManagementThemedColor('accent_primary', this.themeState.currentTheme) + '18'
      : ThemeAwareHelper.getTestManagementThemedColor('comp_background_secondary', this.themeState.currentTheme))
    .borderRadius(12)
    .animation({ duration: 200, curve: Curve.EaseOut })
    .onClick(() => {
      this.selectReadAloudCacheManageChapter(chapter.chapterIndex);
    })
  }

  @Builder
  private buildReadAloudCacheTargetSegmentRow(segment: RemoteReadAloudCacheTargetSegment) {
    Row({ space: 10 }) {
      Column({ space: 4 }) {
        Text(`S${segment.segmentIndex + 1} · ${this.formatReadAloudCacheTargetSegmentRange(segment)}`)
          .fontSize(13)
          .fontWeight(FontWeight.Medium)
          .fontFamily(this.appFontFamily)
          .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_primary', this.themeState.currentTheme))
          .width('100%')
        Text(segment.textPreview.length > 0 ? segment.textPreview : `${segment.textLength} 字符`)
          .fontSize(11)
          .fontFamily(this.appFontFamily)
          .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_secondary', this.themeState.currentTheme))
          .maxLines(2)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
          .width('100%')
        Text(this.getReadAloudCacheTargetStatusText(segment))
          .fontSize(11)
          .fontFamily(this.appFontFamily)
          .fontColor(segment.attachedSegment
            ? ThemeAwareHelper.getTestManagementThemedColor('accent_green', this.themeState.currentTheme)
            : ThemeAwareHelper.getTestManagementThemedColor('text_muted', this.themeState.currentTheme))
          .width('100%')
      }
      .layoutWeight(1)
      .alignItems(HorizontalAlign.Start)

      if (segment.attachedSegment) {
        Button() {
          SymbolGlyph($r('sys.symbol.trash'))
            .fontSize(13)
            .fontColor([Color.White])
        }
        .width(28)
        .height(28)
        .backgroundColor('#FF5252')
        .borderRadius(14)
        .enabled(!this.isReadAloudCacheManageMutating)
        .onClick(() => {
          const attachedSegment = segment.attachedSegment;
          if (attachedSegment) {
            void this.removeReadAloudCacheManageSegment(attachedSegment);
          }
        })
      }
    }
    .width('100%')
    .padding(10)
    .backgroundColor(this.readAloudCacheManageSelectedTargetIndex === segment.segmentIndex
      ? ThemeAwareHelper.getTestManagementThemedColor('accent_primary', this.themeState.currentTheme) + '18'
      : ThemeAwareHelper.getTestManagementThemedColor('comp_background_secondary', this.themeState.currentTheme))
    .borderRadius(12)
    .border({
      width: this.readAloudCacheManageSelectedTargetIndex === segment.segmentIndex ? 1 : 0,
      color: ThemeAwareHelper.getTestManagementThemedColor('accent_primary', this.themeState.currentTheme)
    })
    .animation({ duration: 200, curve: Curve.EaseOut })
    .transition(this.getReadAloudCacheFadeSlideTransition(8))
    .onClick(() => {
      this.selectReadAloudCacheManageTarget(segment.segmentIndex);
    })
  }

  @Builder
  private buildReadAloudCacheSourceSegmentRow(segment: RemoteReadAloudCacheSegmentDetail) {
    Column({ space: 8 }) {
      Text(`S${segment.segmentIndex + 1} · ${this.formatReadAloudCacheSegmentRange(segment)}`)
        .fontSize(13)
        .fontWeight(FontWeight.Medium)
        .fontFamily(this.appFontFamily)
        .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_primary', this.themeState.currentTheme))
        .width('100%')
      Text(segment.textPreview.length > 0 ? segment.textPreview : `${segment.textLength} 字符`)
        .fontSize(11)
        .fontFamily(this.appFontFamily)
        .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_secondary', this.themeState.currentTheme))
        .maxLines(3)
        .textOverflow({ overflow: TextOverflow.Ellipsis })
        .width('100%')
      Text(this.getReadAloudCacheSourceSegmentStatusText(segment))
        .fontSize(11)
        .fontFamily(this.appFontFamily)
        .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_muted', this.themeState.currentTheme))
        .width('100%')
      Text(this.getReadAloudCacheSuggestedTargetLabel(segment))
        .fontSize(11)
        .fontFamily(this.appFontFamily)
        .fontColor(this.getReadAloudCacheSuggestedTargetColor(segment))
        .width('100%')
      if (this.getReadAloudCacheSuggestedTargetDetailText(segment).length > 0) {
        Text(this.getReadAloudCacheSuggestedTargetDetailText(segment))
          .fontSize(10)
          .fontFamily(this.appFontFamily)
          .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_secondary', this.themeState.currentTheme))
          .maxLines(2)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
          .width('100%')
          .transition(this.getReadAloudCacheFadeSlideTransition(4))
      }
      Text(`cacheKey ${segment.cacheKey ?? '未记录'} · 文本 ${this.getReadAloudCacheDigestShortLabel(segment.textDigest)}`)
        .fontSize(10)
        .fontFamily(this.appFontFamily)
        .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_muted', this.themeState.currentTheme))
        .width('100%')
      Row({ space: 8 }) {
        Button(this.getReadAloudCacheSuggestedAttachButtonText(segment))
          .layoutWeight(1)
          .height(30)
          .fontSize(11)
          .fontFamily(this.appFontFamily)
          .backgroundColor(ThemeAwareHelper.getTestManagementThemedColor('accent_green', this.themeState.currentTheme))
          .fontColor(Color.White)
          .borderRadius(15)
          .enabled(this.hasReadAloudCacheSuggestedTarget(segment) && !this.isReadAloudCacheManageMutating)
          .onClick(() => {
            void this.attachReadAloudCacheSourceSegmentToSuggestedTarget(segment);
          })

        Button(this.hasReadAloudCacheSuggestedTarget(segment) ? '禁止该建议' : '已无建议')
          .height(30)
          .padding({ left: 12, right: 12 })
          .fontSize(11)
          .fontFamily(this.appFontFamily)
          .backgroundColor(ThemeAwareHelper.getTestManagementThemedColor('comp_background_secondary', this.themeState.currentTheme))
          .fontColor(ThemeAwareHelper.getTestManagementThemedColor('accent_orange', this.themeState.currentTheme))
          .borderRadius(15)
          .enabled(this.hasReadAloudCacheSuggestedTarget(segment) && !this.isReadAloudCacheManageMutating)
          .onClick(() => {
            this.forbidReadAloudCacheSuggestedTarget(segment);
          })
      }
      .width('100%')
      .transition(this.getReadAloudCacheFadeSlideTransition(4))
      Row({ space: 8 }) {
        Button(this.readAloudCacheManageSelectedTargetIndex >= 0
          ? `匹配到 S${this.readAloudCacheManageSelectedTargetIndex + 1}`
          : '先选择槽位')
          .layoutWeight(1)
          .height(30)
          .fontSize(11)
          .fontFamily(this.appFontFamily)
          .backgroundColor(ThemeAwareHelper.getTestManagementThemedColor('accent_primary', this.themeState.currentTheme))
          .fontColor(Color.White)
          .borderRadius(15)
          .enabled(this.readAloudCacheManageSelectedTargetIndex >= 0 && !this.isReadAloudCacheManageMutating)
          .onClick(() => {
            void this.attachReadAloudCacheSourceSegment(segment);
          })

        Button('删除')
          .height(30)
          .padding({ left: 12, right: 12 })
          .fontSize(11)
          .fontFamily(this.appFontFamily)
          .backgroundColor(ThemeAwareHelper.getTestManagementThemedColor('comp_background_secondary', this.themeState.currentTheme))
          .fontColor(ThemeAwareHelper.getTestManagementThemedColor('color_error', this.themeState.currentTheme))
          .borderRadius(15)
          .enabled(!this.isReadAloudCacheManageMutating)
          .onClick(() => {
            void this.removeReadAloudCacheManageSegment(segment);
          })
      }
      .width('100%')
    }
    .width('100%')
    .padding(12)
    .backgroundColor(ThemeAwareHelper.getTestManagementThemedColor('comp_background_secondary', this.themeState.currentTheme))
    .borderRadius(12)
    .animation({ duration: 200, curve: Curve.EaseOut })
    .transition(this.getReadAloudCacheFadeSlideTransition(8))
  }

  @Builder
  private buildReadAloudCacheChapterSelectionTab() {
    Column({ space: 12 }) {
      Column({ space: 10 }) {
        Row() {
          Text('章节范围')
            .fontSize(14)
            .fontWeight(FontWeight.Medium)
            .fontFamily(this.appFontFamily)
            .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_primary', this.themeState.currentTheme))
          Blank()
          if (this.readAloudCacheSummary) {
            Text(`当前已缓存 ${this.readAloudCacheSummary.cachedChapterCount}/${this.readAloudCacheSummary.chapterCount} 章`)
              .fontSize(12)
              .fontFamily(this.appFontFamily)
              .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_secondary', this.themeState.currentTheme))
          }
        }
        .width('100%')

        Row({ space: 8 }) {
          Button() {
            Row({ space: 6 }) {
              SymbolGlyph($r('sys.symbol.slider_horizontal_2_1'))
                .fontSize(14)
                .fontColor([this.readAloudCacheSelectionMode === 'range'
                  ? Color.White
                  : ThemeAwareHelper.getTestManagementThemedColor('text_primary', this.themeState.currentTheme)])
              Text('区间选择')
                .fontSize(13)
                .fontFamily(this.appFontFamily)
                .fontColor(this.readAloudCacheSelectionMode === 'range'
                  ? Color.White
                  : ThemeAwareHelper.getTestManagementThemedColor('text_primary', this.themeState.currentTheme))
            }
          }
          .height(36)
          .padding({ left: 14, right: 14 })
          .backgroundColor(this.readAloudCacheSelectionMode === 'range'
            ? ThemeAwareHelper.getTestManagementThemedColor('accent_primary', this.themeState.currentTheme)
            : ThemeAwareHelper.getTestManagementThemedColor('comp_background_secondary', this.themeState.currentTheme))
          .borderRadius(18)
          .animation({ duration: 200, curve: Curve.EaseOut })
          .onClick(() => {
            this.getUIContext().animateTo({ duration: 220, curve: Curve.EaseInOut }, () => {
              this.readAloudCacheSelectionMode = 'range';
            });
          })

          Button() {
            Row({ space: 6 }) {
              SymbolGlyph($r('sys.symbol.checkmark_circle'))
                .fontSize(14)
                .fontColor([this.readAloudCacheSelectionMode === 'individual'
                  ? Color.White
                  : ThemeAwareHelper.getTestManagementThemedColor('text_primary', this.themeState.currentTheme)])
              Text('单独选择')
                .fontSize(13)
                .fontFamily(this.appFontFamily)
                .fontColor(this.readAloudCacheSelectionMode === 'individual'
                  ? Color.White
                  : ThemeAwareHelper.getTestManagementThemedColor('text_primary', this.themeState.currentTheme))
            }
          }
          .height(36)
          .padding({ left: 14, right: 14 })
          .backgroundColor(this.readAloudCacheSelectionMode === 'individual'
            ? ThemeAwareHelper.getTestManagementThemedColor('accent_primary', this.themeState.currentTheme)
            : ThemeAwareHelper.getTestManagementThemedColor('comp_background_secondary', this.themeState.currentTheme))
          .borderRadius(18)
          .animation({ duration: 200, curve: Curve.EaseOut })
          .onClick(() => {
            this.getUIContext().animateTo({ duration: 220, curve: Curve.EaseInOut }, () => {
              this.readAloudCacheSelectionMode = 'individual';
              this.readAloudCacheChapterListExpanded = true;
            });
          })
        }
        .width('100%')

        if ((this.readAloudCacheSummary?.chapterCount ?? this.content?.chapters.length ?? 0) <= 1) {
          Text('当前书籍只有一个章节，可直接生成整章听书缓存。')
            .fontSize(12)
            .fontFamily(this.appFontFamily)
            .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_secondary', this.themeState.currentTheme))
            .width('100%')
        } else if (this.readAloudCacheSelectionMode === 'range') {
          Column({ space: 12 }) {
            Row() {
              Text(`第 ${this.readAloudCacheRangeStart + 1} 章`)
                .fontSize(14)
                .fontWeight(FontWeight.Medium)
                .fontFamily(this.appFontFamily)
                .fontColor(ThemeAwareHelper.getTestManagementThemedColor('accent_primary', this.themeState.currentTheme))
              Text(' 至 ')
                .fontSize(14)
                .fontFamily(this.appFontFamily)
                .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_muted', this.themeState.currentTheme))
              Text(`第 ${this.readAloudCacheRangeEnd + 1} 章`)
                .fontSize(14)
                .fontWeight(FontWeight.Medium)
                .fontFamily(this.appFontFamily)
                .fontColor(ThemeAwareHelper.getTestManagementThemedColor('accent_primary', this.themeState.currentTheme))
              Blank()
              Text(this.getReadAloudCacheSelectionSummary())
                .fontSize(12)
                .fontFamily(this.appFontFamily)
                .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_secondary', this.themeState.currentTheme))
            }
            .width('100%')

            Row({ space: 8 }) {
              Button('未缓存起点')
                .layoutWeight(1)
                .height(28)
                .fontSize(12)
                .fontFamily(this.appFontFamily)
                .backgroundColor(ThemeAwareHelper.getTestManagementThemedColor('comp_background_secondary', this.themeState.currentTheme))
                .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_primary', this.themeState.currentTheme))
                .borderRadius(14)
                .onClick(() => {
                  this.applyReadAloudCacheQuickRange('uncached');
                })
              Button('当前阅读章')
                .layoutWeight(1)
                .height(28)
                .fontSize(12)
                .fontFamily(this.appFontFamily)
                .backgroundColor(ThemeAwareHelper.getTestManagementThemedColor('comp_background_secondary', this.themeState.currentTheme))
                .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_primary', this.themeState.currentTheme))
                .borderRadius(14)
                .onClick(() => {
                  this.applyReadAloudCacheQuickRange('current');
                })
              Button('整本')
                .layoutWeight(1)
                .height(28)
                .fontSize(12)
                .fontFamily(this.appFontFamily)
                .backgroundColor(ThemeAwareHelper.getTestManagementThemedColor('comp_background_secondary', this.themeState.currentTheme))
                .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_primary', this.themeState.currentTheme))
                .borderRadius(14)
                .onClick(() => {
                  this.applyReadAloudCacheQuickRange('full');
                })
            }
            .width('100%')

            Column({ space: 4 }) {
              Text('开始章节')
                .fontSize(12)
                .fontFamily(this.appFontFamily)
                .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_muted', this.themeState.currentTheme))

              Slider({
                value: this.readAloudCacheRangeStart,
                min: 0,
                max: Math.max(0, (this.readAloudCacheSummary?.chapterCount ?? this.content?.chapters.length ?? 1) - 1),
                step: 1,
                style: SliderStyle.OutSet
              })
                .showTips(true)
                .blockColor(ThemeAwareHelper.getTestManagementThemedColor('accent_primary', this.themeState.currentTheme))
                .trackColor(ThemeAwareHelper.getTestManagementThemedColor('comp_background_secondary', this.themeState.currentTheme))
                .selectedColor(ThemeAwareHelper.getTestManagementThemedColor('accent_primary', this.themeState.currentTheme))
                .onChange((value: number) => {
                  const safeValue = Math.round(value);
                  this.readAloudCacheRangeStart = safeValue;
                  if (this.readAloudCacheRangeEnd < safeValue) {
                    this.readAloudCacheRangeEnd = safeValue;
                  }
                })
            }
            .width('100%')

            Column({ space: 4 }) {
              Text('结束章节')
                .fontSize(12)
                .fontFamily(this.appFontFamily)
                .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_muted', this.themeState.currentTheme))

              Slider({
                value: this.readAloudCacheRangeEnd,
                min: this.readAloudCacheRangeStart,
                max: Math.max(this.readAloudCacheRangeStart, (this.readAloudCacheSummary?.chapterCount ?? this.content?.chapters.length ?? 1) - 1),
                step: 1,
                style: SliderStyle.OutSet
              })
                .showTips(true)
                .blockColor(ThemeAwareHelper.getTestManagementThemedColor('accent_primary', this.themeState.currentTheme))
                .trackColor(ThemeAwareHelper.getTestManagementThemedColor('comp_background_secondary', this.themeState.currentTheme))
                .selectedColor(ThemeAwareHelper.getTestManagementThemedColor('accent_primary', this.themeState.currentTheme))
                .onChange((value: number) => {
                  this.readAloudCacheRangeEnd = Math.max(this.readAloudCacheRangeStart, Math.round(value));
                })
            }
            .width('100%')
            }
            .width('100%')
            .transition(this.getReadAloudCacheFadeSlideTransition(8))
        } else {
          Text('点击下方章节即可加入或移出批量缓存队列。')
            .fontSize(12)
            .fontFamily(this.appFontFamily)
            .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_secondary', this.themeState.currentTheme))
            .width('100%')
        }
      }
      .width('100%')
      .padding(12)
      .backgroundColor(ThemeAwareHelper.getTestManagementThemedColor('comp_background_tertiary', this.themeState.currentTheme))
      .borderRadius(12)
      .transition(this.getReadAloudCacheFadeSlideTransition(8))

      Column({ space: 10 }) {
        Row() {
          Text('章节缓存状态')
            .fontSize(14)
            .fontWeight(FontWeight.Medium)
            .fontFamily(this.appFontFamily)
            .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_primary', this.themeState.currentTheme))
          Blank()
          Button() {
            SymbolGlyph($r(this.readAloudCacheChapterListExpanded ? 'sys.symbol.chevron_down' : 'sys.symbol.chevron_right'))
              .fontSize(14)
              .fontColor([ThemeAwareHelper.getTestManagementThemedColor('text_secondary', this.themeState.currentTheme)])
              .rotate({ angle: this.readAloudCacheChapterListExpanded ? 0 : -90 })
              .animation({ duration: 250, curve: Curve.EaseInOut })
          }
          .width(28)
          .height(28)
          .backgroundColor(Color.Transparent)
          .onClick(() => {
            this.getUIContext().animateTo({ duration: 300, curve: Curve.EaseInOut }, () => {
              this.readAloudCacheChapterListExpanded = !this.readAloudCacheChapterListExpanded;
            });
          })
        }
        .width('100%')

        if (this.readAloudCacheChapterListExpanded) {
          Scroll() {
            Column({ space: 8 }) {
              ForEach(this.readAloudCacheSummary?.chapters ?? [], (chapter: RemoteReadAloudCacheChapterSummary) => {
                this.buildReadAloudCacheDialogChapterRow(chapter)
              }, (chapter: RemoteReadAloudCacheChapterSummary) => `read_aloud_cache_dialog_${chapter.chapterIndex}`)
            }
            .width('100%')
          }
          .width('100%')
          .constraintSize({ maxHeight: 280 })
          .scrollBar(BarState.Auto)
          .transition(this.getReadAloudCacheFadeSlideTransition(10))
        }
      }
      .width('100%')
      .padding(12)
      .backgroundColor(ThemeAwareHelper.getTestManagementThemedColor('comp_background_tertiary', this.themeState.currentTheme))
      .borderRadius(12)
      .transition(this.getReadAloudCacheFadeSlideTransition(10))
    }
    .width('100%')
    .transition(this.getReadAloudCacheFadeSlideTransition(12))
  }

  @Builder
  private buildReadAloudCacheDialogChapterRow(chapter: RemoteReadAloudCacheChapterSummary) {
    Row({ space: 10 }) {
      if (this.readAloudCacheSelectionMode === 'individual') {
        SymbolGlyph($r(this.readAloudCacheSelectedChapters.has(chapter.chapterIndex)
          ? 'sys.symbol.checkmark_circle_fill'
          : 'sys.symbol.circle'))
          .fontSize(16)
          .fontColor([this.readAloudCacheSelectedChapters.has(chapter.chapterIndex)
            ? ThemeAwareHelper.getTestManagementThemedColor('accent_primary', this.themeState.currentTheme)
            : ThemeAwareHelper.getTestManagementThemedColor('text_muted', this.themeState.currentTheme)])
      } else {
        SymbolGlyph($r(chapter.cached ? 'sys.symbol.checkmark_circle_fill' : 'sys.symbol.circle'))
          .fontSize(16)
          .fontColor([chapter.cached
            ? ThemeAwareHelper.getTestManagementThemedColor('accent_green', this.themeState.currentTheme)
            : ThemeAwareHelper.getTestManagementThemedColor('text_muted', this.themeState.currentTheme)])
      }

      Column({ space: 4 }) {
        Text(this.buildReadAloudCacheChapterLabel(chapter.chapterIndex))
          .fontSize(13)
          .fontFamily(this.appFontFamily)
          .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_primary', this.themeState.currentTheme))
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
          .width('100%')
        Text(`${this.getReadAloudCacheSegmentSourceLabel(chapter)} · ${this.getReadAloudCacheEffectiveChapterStatusText(chapter)}`)
          .fontSize(11)
          .fontFamily(this.appFontFamily)
          .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_muted', this.themeState.currentTheme))
          .maxLines(2)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
          .width('100%')
        if (this.getReadAloudCacheSegmentPreviewText(chapter, 3).length > 0) {
          Text(this.getReadAloudCacheSegmentPreviewText(chapter, 3))
            .fontSize(10)
            .fontFamily(this.appFontFamily)
            .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_secondary', this.themeState.currentTheme))
            .maxLines(4)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
            .width('100%')
        }
      }
      .layoutWeight(1)
      .alignItems(HorizontalAlign.Start)

      Row({ space: 6 }) {
        Button() {
          SymbolGlyph($r('sys.symbol.arrow_down_circle'))
            .fontSize(14)
            .fontColor([Color.White])
        }
        .width(28)
        .height(28)
        .backgroundColor(ThemeAwareHelper.getTestManagementThemedColor('accent_primary', this.themeState.currentTheme))
        .borderRadius(14)
        .enabled(!this.isReadAloudPrecaching)
        .onClick(() => {
          void this.quickPrecacheReadAloudChapter(chapter.chapterIndex);
        })

        if (chapter.cached) {
          Button() {
            SymbolGlyph($r('sys.symbol.trash'))
              .fontSize(13)
              .fontColor([Color.White])
          }
          .width(28)
          .height(28)
          .backgroundColor('#FF5252')
          .borderRadius(14)
          .enabled(!this.isReadAloudPrecaching)
          .onClick(() => {
            void this.clearReadAloudCacheChapter(chapter.chapterIndex);
          })
        }
      }
    }
    .width('100%')
    .padding(10)
    .backgroundColor(this.isReadAloudCacheChapterSelected(chapter.chapterIndex)
      ? ThemeAwareHelper.getTestManagementThemedColor('accent_primary', this.themeState.currentTheme) + '18'
      : ThemeAwareHelper.getTestManagementThemedColor('comp_background_secondary', this.themeState.currentTheme))
    .borderRadius(12)
    .animation({ duration: 200, curve: Curve.EaseOut })
    .onClick(() => {
      if (this.readAloudCacheSelectionMode === 'individual') {
        this.toggleReadAloudCacheChapterSelection(chapter.chapterIndex);
      }
    })
  }

  @Builder
  private buildReadAloudCacheChoiceChip(label: string, selected: boolean, onClick: () => void) {
    Button(label)
      .height(32)
      .padding({ left: 12, right: 12 })
      .fontSize(12)
      .fontFamily(this.appFontFamily)
      .backgroundColor(selected
        ? ThemeAwareHelper.getTestManagementThemedColor('accent_primary', this.themeState.currentTheme)
        : ThemeAwareHelper.getTestManagementThemedColor('comp_background_secondary', this.themeState.currentTheme))
      .fontColor(selected
        ? Color.White
        : ThemeAwareHelper.getTestManagementThemedColor('text_primary', this.themeState.currentTheme))
      .borderRadius(16)
      .scale({ x: selected ? 1 : 0.98, y: selected ? 1 : 0.98 })
      .animation({ duration: 180, curve: Curve.EaseOut })
      .onClick(() => {
        onClick();
      })
  }

  @Builder
  private buildReadAloudCacheMiMoVoiceSelector() {
    Column({ space: 8 }) {
      Text('MiMo 预设音色')
        .fontSize(12)
        .fontFamily(this.appFontFamily)
        .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_muted', this.themeState.currentTheme))
      Flex({ wrap: FlexWrap.Wrap, justifyContent: FlexAlign.Start, alignItems: ItemAlign.Center }) {
        ForEach(XIAOMI_MIMO_REMOTE_READ_ALOUD_VOICE_OPTIONS, (option: RemoteReadAloudChoiceOption) => {
          this.buildReadAloudCacheChoiceChip(
            option.label,
            this.readAloudCacheTaskSettings.voice.trim() === option.value,
            () => this.updateReadAloudCacheTaskSettings({ voice: option.value })
          )
        }, (option: RemoteReadAloudChoiceOption) => `read_aloud_cache_voice_${option.value}`)
      }
      .width('100%')
    }
    .width('100%')
  }

  @Builder
  private buildReadAloudCacheMiMoStyleSelector() {
    Column({ space: 8 }) {
      Text('MiMo 风格控制')
        .fontSize(12)
        .fontFamily(this.appFontFamily)
        .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_muted', this.themeState.currentTheme))
      Text('支持多选风格，也可手动输入；生成时会自动写成 <style>风格...</style> 正文。')
        .fontSize(12)
        .fontFamily(this.appFontFamily)
        .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_secondary', this.themeState.currentTheme))
        .width('100%')
      ForEach(XIAOMI_MIMO_REMOTE_READ_ALOUD_STYLE_CATEGORIES, (category: RemoteReadAloudStyleCategory) => {
        Column({ space: 6 }) {
          Text(category.label)
            .fontSize(11)
            .fontFamily(this.appFontFamily)
            .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_secondary', this.themeState.currentTheme))
            .width('100%')
          Flex({ wrap: FlexWrap.Wrap, justifyContent: FlexAlign.Start, alignItems: ItemAlign.Center }) {
            ForEach(category.styles, (style: string) => {
              this.buildReadAloudCacheChoiceChip(style, this.isReadAloudCacheStyleSelected(style), () => {
                this.toggleReadAloudCacheStyle(style);
              })
            }, (style: string) => `read_aloud_cache_style_${category.label}_${style}`)
          }
          .width('100%')
        }
        .width('100%')
      }, (category: RemoteReadAloudStyleCategory) => `read_aloud_cache_style_category_${category.label}`)

      Column({ space: 6 }) {
        Text('自定义风格')
          .fontSize(12)
          .fontFamily(this.appFontFamily)
          .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_muted', this.themeState.currentTheme))
        TextInput({ text: this.getReadAloudCacheStylePrompt(), placeholder: '如 开心 东北话' })
          .height(38)
          .fontSize(13)
          .fontFamily(this.appFontFamily)
          .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_primary', this.themeState.currentTheme))
          .placeholderColor(ThemeAwareHelper.getTestManagementThemedColor('text_tertiary', this.themeState.currentTheme))
          .caretColor(ThemeAwareHelper.getTestManagementThemedColor('accent_primary', this.themeState.currentTheme))
          .padding({ left: 10, right: 10 })
          .backgroundColor(ThemeAwareHelper.getTestManagementThemedColor('comp_background_secondary', this.themeState.currentTheme))
          .borderRadius(12)
          .onChange((value: string) => {
            this.updateReadAloudCacheTaskSettings({ stylePrompt: value });
          })
      }
      .width('100%')

      if (this.getReadAloudCacheStylePrompt().length > 0) {
        Text(`实际发送：<style>${this.getReadAloudCacheStylePrompt()}</style>待合成内容`)
          .fontSize(12)
          .fontFamily(this.appFontFamily)
          .fontColor(ThemeAwareHelper.getTestManagementThemedColor('accent_primary', this.themeState.currentTheme))
          .width('100%')
      }
    }
    .width('100%')
  }

  @Builder
  private buildReadAloudCacheTextInput(
    label: string,
    value: string,
    placeholder: string,
    onChange: (value: string) => void
  ) {
    Column({ space: 6 }) {
      Text(label)
        .fontSize(12)
        .fontFamily(this.appFontFamily)
        .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_muted', this.themeState.currentTheme))
        .width('100%')
      TextInput({ text: value, placeholder })
        .height(38)
        .fontSize(13)
        .fontFamily(this.appFontFamily)
        .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_primary', this.themeState.currentTheme))
        .placeholderColor(ThemeAwareHelper.getTestManagementThemedColor('text_tertiary', this.themeState.currentTheme))
        .caretColor(ThemeAwareHelper.getTestManagementThemedColor('accent_primary', this.themeState.currentTheme))
        .padding({ left: 10, right: 10 })
        .backgroundColor(ThemeAwareHelper.getTestManagementThemedColor('comp_background_secondary', this.themeState.currentTheme))
        .borderRadius(12)
        .onChange((nextValue: string) => {
          onChange(nextValue);
        })
    }
    .width('100%')
  }

  @Builder
  private buildReadAloudCacheNumberInput(
    label: string,
    value: number,
    min: number,
    max: number,
    onChange: (value: number) => void
  ) {
    Column({ space: 6 }) {
      Row() {
        Text(label)
          .fontSize(12)
          .fontFamily(this.appFontFamily)
          .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_muted', this.themeState.currentTheme))
        Blank()
        Text(`${value}`)
          .fontSize(12)
          .fontFamily(this.appFontFamily)
          .fontColor(ThemeAwareHelper.getTestManagementThemedColor('accent_primary', this.themeState.currentTheme))
      }
      .width('100%')
      TextInput({ text: `${value}`, placeholder: `${min}-${max}` })
        .type(InputType.Number)
        .height(38)
        .fontSize(13)
        .fontFamily(this.appFontFamily)
        .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_primary', this.themeState.currentTheme))
        .placeholderColor(ThemeAwareHelper.getTestManagementThemedColor('text_tertiary', this.themeState.currentTheme))
        .caretColor(ThemeAwareHelper.getTestManagementThemedColor('accent_primary', this.themeState.currentTheme))
        .padding({ left: 10, right: 10 })
        .backgroundColor(ThemeAwareHelper.getTestManagementThemedColor('comp_background_secondary', this.themeState.currentTheme))
        .borderRadius(12)
        .onChange((nextValue: string) => {
          onChange(this.parseReadAloudCacheIntegerInput(nextValue, value, min, max));
        })
    }
    .width('100%')
  }

  @Builder
  private buildReadAloudCacheJsonInput(
    label: string,
    value: string,
    placeholder: string,
    onChange: (value: string) => void
  ) {
    Column({ space: 6 }) {
      Text(label)
        .fontSize(12)
        .fontFamily(this.appFontFamily)
        .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_muted', this.themeState.currentTheme))
        .width('100%')
      TextArea({ text: value, placeholder })
        .height(92)
        .fontSize(12)
        .fontFamily(this.appFontFamily)
        .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_primary', this.themeState.currentTheme))
        .placeholderColor(ThemeAwareHelper.getTestManagementThemedColor('text_tertiary', this.themeState.currentTheme))
        .padding(10)
        .backgroundColor(ThemeAwareHelper.getTestManagementThemedColor('comp_background_secondary', this.themeState.currentTheme))
        .borderRadius(12)
        .onChange((nextValue: string) => {
          onChange(nextValue);
        })
    }
    .width('100%')
  }

  @Builder
  private buildReadAloudCacheToggleRow(
    title: string,
    description: string,
    value: boolean,
    enabled: boolean,
    onChange: (value: boolean) => void
  ) {
    Column({ space: 6 }) {
      Row() {
        Column({ space: 2 }) {
          Text(title)
            .fontSize(13)
            .fontWeight(FontWeight.Medium)
            .fontFamily(this.appFontFamily)
            .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_primary', this.themeState.currentTheme))
            .width('100%')
          Text(description)
            .fontSize(11)
            .fontFamily(this.appFontFamily)
            .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_secondary', this.themeState.currentTheme))
            .width('100%')
        }
        .layoutWeight(1)
        .alignItems(HorizontalAlign.Start)
        Toggle({ type: ToggleType.Switch, isOn: value })
          .enabled(enabled)
          .onChange((isOn: boolean) => {
            onChange(isOn);
          })
      }
      .width('100%')
    }
    .width('100%')
    .padding(12)
    .backgroundColor(ThemeAwareHelper.getTestManagementThemedColor('comp_background_tertiary', this.themeState.currentTheme))
    .borderRadius(12)
  }

  @Builder
  private buildReadAloudCacheSettingsTab() {
    Column({ space: 12 }) {
      Column({ space: 10 }) {
        Row() {
          Text('远程预设')
            .fontSize(14)
            .fontWeight(FontWeight.Medium)
            .fontFamily(this.appFontFamily)
            .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_primary', this.themeState.currentTheme))
          Blank()
          Text(this.readAloudCacheSummary?.settingsSourceLabel ?? '全局默认设置')
            .fontSize(12)
            .fontFamily(this.appFontFamily)
            .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_secondary', this.themeState.currentTheme))
        }
        .width('100%')

        Text('这里的配置既会用于当前详情页的缓存任务，也可以保存为当前内容的默认远程 TTS 配置，和阅读器内直接听书共用。')
          .fontSize(12)
          .fontFamily(this.appFontFamily)
          .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_secondary', this.themeState.currentTheme))
          .width('100%')

        Text(this.getReadAloudCachePresetSummary())
          .fontSize(11)
          .fontFamily(this.appFontFamily)
          .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_muted', this.themeState.currentTheme))
          .width('100%')

        ForEach(
          this.readAloudCacheTaskSettings.presets,
          (preset: RemoteReadAloudPreset) => {
            Column({ space: 6 }) {
              Button(
                `${preset.name}${this.readAloudCacheTaskSettings.activePresetId === preset.id ? ' · 当前' : ''}`
              )
                .fontSize(12)
                .fontFamily(this.appFontFamily)
                .height(36)
                .width('100%')
                .backgroundColor(
                  this.readAloudCacheTaskSettings.activePresetId === preset.id
                    ? ThemeAwareHelper.getTestManagementThemedColor('accent_primary', this.themeState.currentTheme)
                    : ThemeAwareHelper.getTestManagementThemedColor('comp_background_secondary', this.themeState.currentTheme)
                )
                .fontColor(
                  this.readAloudCacheTaskSettings.activePresetId === preset.id
                    ? Color.White
                    : ThemeAwareHelper.getTestManagementThemedColor('text_primary', this.themeState.currentTheme)
                )
                .borderRadius(18)
                .animation({ duration: 180, curve: Curve.EaseOut })
                .onClick(() => {
                  this.applyReadAloudCachePreset(preset);
                })

              if (preset.description.length > 0) {
                Text(preset.description)
                  .fontSize(11)
                  .fontFamily(this.appFontFamily)
                  .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_secondary', this.themeState.currentTheme))
                  .width('100%')
              }
            }
            .width('100%')
          },
          (preset: RemoteReadAloudPreset) => preset.id
        )

        this.buildReadAloudCacheTextInput(
          '预设名称',
          this.readAloudCachePresetDraftName,
          '输入名称后保存为新预设',
          (value: string) => {
            this.readAloudCachePresetDraftName = value;
          }
        )

        Row({ space: 8 }) {
          Button('保存为新预设')
            .layoutWeight(1)
            .height(34)
            .fontSize(11)
            .fontFamily(this.appFontFamily)
            .backgroundColor(ThemeAwareHelper.getTestManagementThemedColor('comp_background_secondary', this.themeState.currentTheme))
            .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_primary', this.themeState.currentTheme))
            .borderRadius(17)
            .onClick(() => {
              this.saveReadAloudCachePresetAsNew();
            })

          Button('更新当前预设')
            .layoutWeight(1)
            .height(34)
            .fontSize(11)
            .fontFamily(this.appFontFamily)
            .backgroundColor(ThemeAwareHelper.getTestManagementThemedColor('comp_background_secondary', this.themeState.currentTheme))
            .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_primary', this.themeState.currentTheme))
            .borderRadius(17)
            .enabled(this.canEditActiveReadAloudCachePreset())
            .onClick(() => {
              this.updateCurrentReadAloudCachePreset();
            })

          Button('删除当前预设')
            .layoutWeight(1)
            .height(34)
            .fontSize(11)
            .fontFamily(this.appFontFamily)
            .backgroundColor(ThemeAwareHelper.getTestManagementThemedColor('comp_background_secondary', this.themeState.currentTheme))
            .fontColor(ThemeAwareHelper.getTestManagementThemedColor('color_error', this.themeState.currentTheme))
            .borderRadius(17)
            .enabled(this.canEditActiveReadAloudCachePreset())
            .onClick(() => {
              this.deleteCurrentReadAloudCachePreset();
            })
        }
        .width('100%')

        if (this.readAloudCachePresetStatusMessage.length > 0) {
          Text(this.readAloudCachePresetStatusMessage)
            .fontSize(11)
            .fontFamily(this.appFontFamily)
            .fontColor(ThemeAwareHelper.getTestManagementThemedColor('accent_primary', this.themeState.currentTheme))
            .width('100%')
            .transition(this.getReadAloudCacheFadeSlideTransition(6))
        }
      }
      .width('100%')
      .padding(12)
      .backgroundColor(ThemeAwareHelper.getTestManagementThemedColor('comp_background_tertiary', this.themeState.currentTheme))
      .borderRadius(12)
      .transition(this.getReadAloudCacheFadeSlideTransition(6))

      Column({ space: 10 }) {
        Text('基础连接')
          .fontSize(14)
          .fontWeight(FontWeight.Medium)
          .fontFamily(this.appFontFamily)
          .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_primary', this.themeState.currentTheme))
        this.buildReadAloudCacheTextInput(
          'Endpoint',
          this.readAloudCacheTaskSettings.endpoint,
          'https://api.xiaomimimo.com',
          (value: string) => this.updateReadAloudCacheTaskSettings({ endpoint: value.trim() })
        )
        this.buildReadAloudCacheTextInput(
          'API Path',
          this.readAloudCacheTaskSettings.apiPath,
          '/v1/chat/completions',
          (value: string) => this.updateReadAloudCacheTaskSettings({ apiPath: value.trim() })
        )
        this.buildReadAloudCacheTextInput(
          'API Key',
          this.readAloudCacheTaskSettings.apiKey,
          '输入远程 TTS API Key',
          (value: string) => this.updateReadAloudCacheTaskSettings({ apiKey: value })
        )
        this.buildReadAloudCacheTextInput(
          'Model',
          this.readAloudCacheTaskSettings.model,
          'mimo-v2-tts',
          (value: string) => this.updateReadAloudCacheTaskSettings({ model: value.trim() })
        )
        if (this.isMiMoReadAloudCacheSettings()) {
          this.buildReadAloudCacheMiMoVoiceSelector()
          this.buildReadAloudCacheMiMoStyleSelector()
        }
        this.buildReadAloudCacheTextInput(
          'Voice',
          this.readAloudCacheTaskSettings.voice,
          this.isMiMoReadAloudCacheSettings() ? 'mimo_default / default_zh / default_en' : '输入 voice 参数',
          (value: string) => this.updateReadAloudCacheTaskSettings({ voice: value.trim() })
        )
      }
      .width('100%')
      .padding(12)
      .backgroundColor(ThemeAwareHelper.getTestManagementThemedColor('comp_background_tertiary', this.themeState.currentTheme))
      .borderRadius(12)
      .transition(this.getReadAloudCacheFadeSlideTransition(8))

      Column({ space: 10 }) {
        Text('输出与缓存')
          .fontSize(14)
          .fontWeight(FontWeight.Medium)
          .fontFamily(this.appFontFamily)
          .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_primary', this.themeState.currentTheme))
        Row({ space: 8 }) {
          ForEach(['wav', 'mp3'], (format: string) => {
            Button(format.toUpperCase())
              .layoutWeight(1)
              .height(32)
              .fontSize(12)
              .fontFamily(this.appFontFamily)
              .backgroundColor(this.readAloudCacheTaskSettings.audioFormat === format
                ? ThemeAwareHelper.getTestManagementThemedColor('accent_primary', this.themeState.currentTheme)
                : ThemeAwareHelper.getTestManagementThemedColor('comp_background_secondary', this.themeState.currentTheme))
              .fontColor(this.readAloudCacheTaskSettings.audioFormat === format
                ? Color.White
                : ThemeAwareHelper.getTestManagementThemedColor('text_primary', this.themeState.currentTheme))
              .borderRadius(16)
              .animation({ duration: 180, curve: Curve.EaseOut })
              .onClick(() => {
                this.updateReadAloudCacheTaskSettings({ audioFormat: format });
              })
          }, (format: string) => `read_aloud_cache_format_${format}`)
        }
        .width('100%')
        this.buildReadAloudCacheToggleRow(
          '流式响应',
          '是否使用服务端流式返回音频。部分接口关闭后更稳定。',
          this.readAloudCacheTaskSettings.streamEnabled,
          true,
          (value: boolean) => this.updateReadAloudCacheTaskSettings({ streamEnabled: value })
        )
        this.buildReadAloudCacheToggleRow(
          '整章合成',
          '章节缓存完成后自动尝试生成整章合并音频。',
          this.readAloudCacheTaskSettings.autoConcatAudio,
          true,
          (value: boolean) => this.updateReadAloudCacheTaskSettings({ autoConcatAudio: value })
        )
        this.buildReadAloudCacheToggleRow(
          '音频文件缓存',
          '为了章节缓存管理、阅读器命中和手动分段挂接稳定工作，这里固定开启。',
          true,
          false,
          (_value: boolean) => {
          }
        )
      }
      .width('100%')
      .padding(12)
      .backgroundColor(ThemeAwareHelper.getTestManagementThemedColor('comp_background_tertiary', this.themeState.currentTheme))
      .borderRadius(12)
      .transition(this.getReadAloudCacheFadeSlideTransition(10))

      Column({ space: 10 }) {
        Text('分段与超时')
          .fontSize(14)
          .fontWeight(FontWeight.Medium)
          .fontFamily(this.appFontFamily)
          .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_primary', this.themeState.currentTheme))
        this.buildReadAloudCacheNumberInput(
          '预取分段数',
          this.readAloudCacheTaskSettings.prefetchSegments,
          1,
          8,
          (value: number) => this.updateReadAloudCacheTaskSettings({ prefetchSegments: value })
        )
        this.buildReadAloudCacheNumberInput(
          '连接超时（ms）',
          this.readAloudCacheTaskSettings.connectTimeoutMs,
          3000,
          120000,
          (value: number) => this.updateReadAloudCacheTaskSettings({ connectTimeoutMs: value })
        )
        this.buildReadAloudCacheNumberInput(
          '读取超时（ms）',
          this.readAloudCacheTaskSettings.readTimeoutMs,
          5000,
          300000,
          (value: number) => this.updateReadAloudCacheTaskSettings({ readTimeoutMs: value })
        )
        this.buildReadAloudCacheNumberInput(
          '最大输入字符',
          this.readAloudCacheTaskSettings.maxInputChars,
          256,
          12000,
          (value: number) => this.updateReadAloudCacheTaskSettings({ maxInputChars: value })
        )
        this.buildReadAloudCacheNumberInput(
          '保留字符数',
          this.readAloudCacheTaskSettings.reservedInputChars,
          0,
          2000,
          (value: number) => this.updateReadAloudCacheTaskSettings({ reservedInputChars: value })
        )
        this.buildReadAloudCacheNumberInput(
          '最小分段字符',
          this.readAloudCacheTaskSettings.minChunkChars,
          32,
          5000,
          (value: number) => this.updateReadAloudCacheTaskSettings({ minChunkChars: value })
        )
        this.buildReadAloudCacheNumberInput(
          '目标分段字符',
          this.readAloudCacheTaskSettings.targetChunkChars,
          64,
          7000,
          (value: number) => this.updateReadAloudCacheTaskSettings({ targetChunkChars: value })
        )
        this.buildReadAloudCacheNumberInput(
          '最大分段字符',
          this.readAloudCacheTaskSettings.maxChunkChars,
          80,
          9000,
          (value: number) => this.updateReadAloudCacheTaskSettings({ maxChunkChars: value })
        )
      }
      .width('100%')
      .padding(12)
      .backgroundColor(ThemeAwareHelper.getTestManagementThemedColor('comp_background_tertiary', this.themeState.currentTheme))
      .borderRadius(12)
      .transition(this.getReadAloudCacheFadeSlideTransition(12))

      Column({ space: 10 }) {
        Text('自定义请求')
          .fontSize(14)
          .fontWeight(FontWeight.Medium)
          .fontFamily(this.appFontFamily)
          .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_primary', this.themeState.currentTheme))
        this.buildReadAloudCacheJsonInput(
          '自定义请求头 JSON',
          this.readAloudCacheTaskSettings.customHeadersJson,
          '{\"X-Trace\": \"manxia\"}',
          (value: string) => this.updateReadAloudCacheTaskSettings({ customHeadersJson: value })
        )
        this.buildReadAloudCacheJsonInput(
          '额外请求体 JSON',
          this.readAloudCacheTaskSettings.extraBodyJson,
          '{\"temperature\": 0.2}',
          (value: string) => this.updateReadAloudCacheTaskSettings({ extraBodyJson: value })
        )
      }
      .width('100%')
      .padding(12)
      .backgroundColor(ThemeAwareHelper.getTestManagementThemedColor('comp_background_tertiary', this.themeState.currentTheme))
      .borderRadius(12)
      .transition(this.getReadAloudCacheFadeSlideTransition(14))

      Column({ space: 8 }) {
        Row({ space: 6 }) {
          SymbolGlyph($r('sys.symbol.info_circle'))
            .fontSize(13)
            .fontColor([ThemeAwareHelper.getTestManagementThemedColor('accent_primary', this.themeState.currentTheme)])
          Text('当前生效说明')
            .fontSize(13)
            .fontWeight(FontWeight.Medium)
            .fontFamily(this.appFontFamily)
            .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_primary', this.themeState.currentTheme))
        }
        .width('100%')

        Text(`模型：${this.readAloudCacheTaskSettings.model} / ${this.getReadAloudCacheVoiceLabel(this.readAloudCacheTaskSettings.voice)}`)
          .fontSize(12)
          .fontFamily(this.appFontFamily)
          .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_secondary', this.themeState.currentTheme))
          .width('100%')
        if (this.getReadAloudCacheStylePrompt().length > 0) {
          Text(`风格：${this.getReadAloudCacheStylePrompt()}`)
            .fontSize(12)
            .fontFamily(this.appFontFamily)
            .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_secondary', this.themeState.currentTheme))
            .width('100%')
        }
        Text('开始缓存前会自动把当前任务配置同步为当前内容默认远程 TTS，确保统一详情页缓存和阅读器内直接听书使用同一套配置与缓存索引。')
          .fontSize(12)
          .fontFamily(this.appFontFamily)
          .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_secondary', this.themeState.currentTheme))
          .width('100%')
      }
      .width('100%')
      .padding(12)
      .backgroundColor(ThemeAwareHelper.getTestManagementThemedColor('comp_background_tertiary', this.themeState.currentTheme))
      .borderRadius(12)
      .transition(this.getReadAloudCacheFadeSlideTransition(14))
    }
    .width('100%')
    .transition(this.getReadAloudCacheFadeSlideTransition(12))
  }

  build() {
    Column() {
      this.buildReadAloudCacheSection()
      this.buildReadAloudCacheDialog()
    }
    .width('100%')
  }
}
