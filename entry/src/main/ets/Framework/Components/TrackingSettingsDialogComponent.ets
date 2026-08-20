// 文件路径: entry/src/main/ets/Framework/Components/TrackingSettingsDialogComponent.ets
// 职责: 内容跟踪设置对话框组件，从UnifiedDetailPage提取的独立组件


import { promptAction } from '@kit.ArkUI';
import { logger } from 'manxia_core/src/main/ets/Utils/Logger';
import { common } from '@kit.AbilityKit';
import { ThemeAwareState, ThemeAwareHelper } from 'manxia_theme/src/main/ets/Framework/Components/ThemeAware';
import { SourceDialogScaffold } from './SourceDialogScaffold';
import { SettingsPageSurfaceManager, SettingsPageSurfaceStyle } from 'manxia_features_ui/src/main/ets/pages/settings/SettingsPageSurfaceManager';
import {
  ContentTrackingCardCallbacks,
  ContentTrackingCardState,
  ContentTrackingHighlight,
  ContentTrackingHighlightTone,
  ContentTrackingStatusCard
} from '../../components/ContentTrackingStatusCard';
import {
  getSubscriptionInitializer,
  getSubscriptionManager,
  convertSubscriptionIntervalDisplayToMinutes,
  SubscriptionActionType,
  SubscriptionConditionMatchMode,
  SubscriptionConditionType,
  SubscriptionContentType,
  SubscriptionExecutionRecord,
  SubscriptionExecutionStatus,
  SubscriptionIntervalUnit,
  SubscriptionProviderType,
  SubscriptionRule,
  SubscriptionRuleCreateOptions,
  SubscriptionManager,
  formatSubscriptionIntervalSchedule,
  getSubscriptionIntervalUnitLabel,
  splitSubscriptionIntervalMinutesForDisplay
} from '../Subscription';
import {
  UnifiedContent,
  UnifiedContentType
} from 'manxia_core/src/main/ets/Models/UnifiedContentModels';
import { MangaAdapter, NovelAdapter } from '../Adapters/UnifiedContentAdapter';
import { Manga } from 'manxia_core/src/main/ets/Models/MangaModels';
import { NovelBook, NovelReadStatus } from 'manxia_core/src/main/ets/Models/NovelModels';
import { RemoteLibraryMangaBridge } from '../Source/RemoteLibraryMangaBridge';
import { getNovelDataManager } from '../Novel/NovelDataManager';

const TAG = 'TrackingSettingsDialogComponent';

export interface UnifiedDetailTrackingTargetInfo {
supported: boolean;
unsupportedReason: string;
contentType: SubscriptionContentType;
targetId: string;
targetTitle: string;
sourceId: string;
sourceName: string;
providerType: SubscriptionProviderType;
}

@Component
export struct TrackingSettingsDialogComponent {
  // 从父组件接收的属性
  @Prop content: UnifiedContent | null = null;
  @Prop themeState: ThemeAwareState = new ThemeAwareState();
  @StorageLink('appFontFamily') appFontFamily: string = 'HarmonyOS Sans';
  @Prop @Watch('onLoadSignalChanged') loadSignal: number = 0;

  // 回调函数
  onNavigate?: (pageName: string, params: object | null) => void;
  getCurrentNovelSourceId?: () => string;
  getCurrentNovelBookUrl?: () => string;
  isCurrentLocalImportedContent?: () => boolean;
  isLocalImportedEBookContent?: () => boolean;
  getNovelCacheBookId?: (sourceId: string, bookUrl: string) => string;
  onTrackingStateChanged?: (state: ContentTrackingCardState, callbacks: ContentTrackingCardCallbacks) => void;
  getLocalCoverPath?: () => string;
  getIsFavorite?: () => boolean;
  isOnlineContent?: () => boolean;

  // 服务
  private subscriptionManager: SubscriptionManager = getSubscriptionManager();
  private novelDataManager = getNovelDataManager();

  // 跟踪状态
  private trackingTargetInfo: UnifiedDetailTrackingTargetInfo | null = null;
  @State trackingRule: SubscriptionRule | null = null;
  @State trackingExecution: SubscriptionExecutionRecord | null = null;
  @State isTrackingLoading: boolean = false;
  @State isTrackingBusy: boolean = false;
  @State trackingSupported: boolean = false;
  @State trackingUnsupportedReason: string = '';
  @State showTrackingSettingsDialog: boolean = false;
  @State trackingSettingsActiveTab: number = 0;
  @State trackingCheckIntervalText: string = '3';
  @State trackingCheckIntervalUnit: SubscriptionIntervalUnit = SubscriptionIntervalUnit.HOUR;
  @State trackingMinNewItemsText: string = '1';
  @State trackingAutoDownloadCountText: string = '0';
  @State trackingConditionMatchMode: SubscriptionConditionMatchMode = SubscriptionConditionMatchMode.ALL;
  @State trackingRequireFavorite: boolean = false;
  @State trackingExcludeNSFW: boolean = false;
  @State trackingTitleKeywordText: string = '';
  @State trackingTagKeywordText: string = '';
  @State trackingSourceKeywordText: string = '';
  @State trackingEnableNotify: boolean = true;
  @State trackingAutoCreateAttempted: boolean = false;
  @State trackingAutoCreatedThisSession: boolean = false;
  @State trackingAutoCreatedTargetId: string = '';

  // 生命周期
  aboutToAppear(): void {
    void this.refreshTrackingState();
  }

  onLoadSignalChanged(): void {
    void this.refreshTrackingState();
  }

  // ==================== 辅助方法 ====================

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

  private normalizeTrackingText(value: string | undefined | null): string {
    if (value === undefined || value === null || typeof value !== 'string') {
      return '';
    }
    return value.trim();
  }

  private getSectionBackgroundEffect(): BackgroundEffectOptions {
    return this.getSectionSurfaceStyle().backgroundEffect as BackgroundEffectOptions;
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

  private shouldShowTrackingStatusSection(): boolean {
    return !!this.content && !this.isCurrentLocalImportedContent?.();
  }


  private async ensureContentTrackingReady(): Promise<boolean> {
    try {
      const hostContext = (this.getUIContext().getHostContext() as common.UIAbilityContext) as common.UIAbilityContext;
      if (!hostContext) {
        return false;
      }
      await getSubscriptionInitializer().initialize(hostContext);
      return true;
    } catch (error) {
      logger.warn(TAG, `初始化内容跟踪模块失败: ${String(error)}`);
      return false;
    }
  }


  private resolveCurrentMangaTrackingProviderType(
    manga: Manga | null,
    fallbackMangaId: string
  ): SubscriptionProviderType {
    if (manga !== null && manga.sourceInfo?.providerType === 'suwayomi') {
      return SubscriptionProviderType.SUWAYOMI;
    }
    if (manga !== null && manga.sourceInfo?.providerType === 'komga') {
      return SubscriptionProviderType.KOMGA;
    }
    const parsedProvider = RemoteLibraryMangaBridge.parseProviderMangaId(fallbackMangaId);
    if (parsedProvider !== null) {
      if (parsedProvider.providerType === 'suwayomi') {
        return SubscriptionProviderType.SUWAYOMI;
      }
      if (parsedProvider.providerType === 'komga') {
        return SubscriptionProviderType.KOMGA;
      }
    }
    return SubscriptionProviderType.WEBVIEW;
  }


  private async resolveCurrentTrackingTargetInfo(): Promise<UnifiedDetailTrackingTargetInfo> {
    const unsupportedTarget: UnifiedDetailTrackingTargetInfo = {
      supported: false,
      unsupportedReason: '这类内容暂时还不能自动检查',
      contentType: SubscriptionContentType.MIXED,
      targetId: '',
      targetTitle: this.content?.title || '',
      sourceId: this.normalizeTrackingText(this.content?.sourceId),
      sourceName: this.normalizeTrackingText(this.content?.sourceName),
      providerType: SubscriptionProviderType.NONE
    };
    if (!this.content) {
      unsupportedTarget.unsupportedReason = '内容还在加载中';
      return unsupportedTarget;
    }
    if (this.isCurrentLocalImportedContent?.()) {
      unsupportedTarget.unsupportedReason = '本地导入内容不显示更新提醒';
      if (this.content.contentType === UnifiedContentType.NOVEL) {
        unsupportedTarget.contentType = SubscriptionContentType.NOVEL;
        unsupportedTarget.providerType = SubscriptionProviderType.LEGADO;
      } else if (this.content.contentType === UnifiedContentType.MANGA) {
        unsupportedTarget.contentType = SubscriptionContentType.MANGA;
      } else if (this.content.contentType === UnifiedContentType.EBOOK) {
        unsupportedTarget.contentType = SubscriptionContentType.EBOOK;
      }
      return unsupportedTarget;
    }

    if (this.content.contentType === UnifiedContentType.NOVEL) {
      const sourceId = this.getCurrentNovelSourceId?.() || '';
      const bookUrl = this.normalizeTrackingText(typeof this.content.id === 'string' ? this.content.id : '');
      if (sourceId.length <= 0 || bookUrl.length <= 0) {
        unsupportedTarget.unsupportedReason = '这本小说缺少来源信息，暂时不能开启提醒';
        unsupportedTarget.contentType = SubscriptionContentType.NOVEL;
        unsupportedTarget.providerType = SubscriptionProviderType.LEGADO;
        return unsupportedTarget;
      }
      let novelBookId = await this.resolveExistingNovelTrackingBookId(sourceId, bookUrl);
      if (novelBookId.length <= 0) {
        novelBookId = this.getNovelCacheBookId?.(sourceId, bookUrl) || `${sourceId}_${encodeURIComponent(bookUrl)}`;
      }
        return {
          supported: true,
          unsupportedReason: '',
          contentType: SubscriptionContentType.NOVEL,
          targetId: novelBookId,
          targetTitle: this.content.title,
          sourceId: sourceId,
          sourceName: this.normalizeTrackingText(this.content.sourceName),
          providerType: SubscriptionProviderType.LEGADO
        };
    }

    if (this.content.contentType === UnifiedContentType.MANGA) {
      const originalManga = MangaAdapter.getOriginalManga(this.content);
      const fallbackMangaId = this.normalizeTrackingText(typeof this.content.id === 'string' ? this.content.id : '');
      const providerType = this.resolveCurrentMangaTrackingProviderType(originalManga, fallbackMangaId);
      if ((providerType === SubscriptionProviderType.SUWAYOMI || providerType === SubscriptionProviderType.KOMGA) &&
        fallbackMangaId.length > 0) {
        const originalMangaId = originalManga !== null ? this.normalizeTrackingText(originalManga.id) : '';
        const targetId = originalMangaId.length > 0 ? originalMangaId : fallbackMangaId;
        return {
          supported: true,
          unsupportedReason: '',
          contentType: SubscriptionContentType.MANGA,
          targetId: targetId,
          targetTitle: this.content.title,
          sourceId: this.normalizeTrackingText(this.content.sourceId),
          sourceName: this.normalizeTrackingText(this.content.sourceName),
          providerType: providerType
        };
      }
      if (providerType === SubscriptionProviderType.WEBVIEW && !this.content.isLocal && fallbackMangaId.length > 0) {
        const originalMangaId = originalManga !== null ? this.normalizeTrackingText(originalManga.id) : '';
        const targetId = originalMangaId.length > 0 ? originalMangaId : fallbackMangaId;
        return {
          supported: true,
          unsupportedReason: '',
          contentType: SubscriptionContentType.MANGA,
          targetId: targetId,
          targetTitle: this.content.title,
          sourceId: this.normalizeTrackingText(this.content.sourceId),
          sourceName: this.normalizeTrackingText(this.content.sourceName),
          providerType: SubscriptionProviderType.WEBVIEW
        };
      }
      unsupportedTarget.contentType = SubscriptionContentType.MANGA;
      unsupportedTarget.providerType = providerType;
      unsupportedTarget.unsupportedReason = this.content.isLocal
        ? '本地漫画暂时还不能自动检查'
        : '这种在线漫画暂时还不能自动检查';
      return unsupportedTarget;
    }

    if (this.content.contentType === UnifiedContentType.EBOOK) {
      unsupportedTarget.contentType = SubscriptionContentType.EBOOK;
      unsupportedTarget.unsupportedReason = '电子书的更新提醒还在准备中';
      return unsupportedTarget;
    }

    return unsupportedTarget;
  }


  private async resolveExistingNovelTrackingBookId(sourceId: string, bookUrl: string): Promise<string> {
    const originalNovel = this.content !== null ? NovelAdapter.getOriginalNovel(this.content) : null;
    if (originalNovel !== null && this.normalizeTrackingText(originalNovel.id).length > 0) {
      return this.normalizeTrackingText(originalNovel.id);
    }

    const storedBook = await this.novelDataManager.getBookByUrl(sourceId, bookUrl);
    if (storedBook !== null && this.normalizeTrackingText(storedBook.id).length > 0) {
      return this.normalizeTrackingText(storedBook.id);
    }

    const constructedId = this.getNovelCacheBookId?.(sourceId, bookUrl) || `${sourceId}_${encodeURIComponent(bookUrl)}`;
    const constructedBook = await this.novelDataManager.getBook(constructedId);
    if (constructedBook !== null && this.normalizeTrackingText(constructedBook.id).length > 0) {
      return this.normalizeTrackingText(constructedBook.id);
    }
    return '';
  }


  private async ensureNovelTrackingBookId(): Promise<string> {
    if (!this.content || this.content.contentType !== UnifiedContentType.NOVEL) {
      throw new Error('当前内容不是小说，暂时不能这样开启提醒');
    }

    const sourceId = this.getCurrentNovelSourceId?.() || '';
    const bookUrl = this.normalizeTrackingText(typeof this.content.id === 'string' ? this.content.id : '');
    if (sourceId.length <= 0 || bookUrl.length <= 0) {
      throw new Error('这本小说缺少来源信息，暂时不能开启提醒');
    }

    const existingBookId = await this.resolveExistingNovelTrackingBookId(sourceId, bookUrl);
    if (existingBookId.length > 0) {
      return existingBookId;
    }

    const now = Date.now();
    const latestChapterTitle = this.content.chapters.length > 0
      ? this.content.chapters[this.content.chapters.length - 1].title
      : '';
    const novelTags = this.content.tags && this.content.tags.length > 0
      ? this.content.tags.join('，')
      : '';
    const bookId = this.getNovelCacheBookId?.(sourceId, bookUrl) || `${sourceId}_${encodeURIComponent(bookUrl)}`;
    const newBook: NovelBook = {
      id: bookId,
      sourceId: sourceId,
      sourceName: this.normalizeTrackingText(this.content.sourceName),
      bookUrl: bookUrl,
      name: this.content.title,
      author: this.content.author,
      kind: novelTags.length > 0 ? novelTags : undefined,
      intro: this.content.description,
      coverUrl: this.content.coverUrl,
      coverLocalPath: (this.getLocalCoverPath?.() ?? '').length > 0 ? this.getLocalCoverPath?.() : undefined,
      latestChapterTitle: latestChapterTitle.length > 0 ? latestChapterTitle : undefined,
      chapterCount: this.content.totalChapters,
      readStatus: NovelReadStatus.UNREAD,
      totalReadingTime: 0,
      isFavorite: this.getIsFavorite?.() ?? false,
      isNSFW: this.content.isNSFW,
      createTime: now,
      updateDbTime: now
    };
    await this.novelDataManager.saveBook(newBook);
    logger.info(TAG, `已为内容跟踪补建小说本地记录: ${newBook.name}`);
    return bookId;
  }


  private shouldAutoCreateTrackingOnInitialEntry(targetInfo: UnifiedDetailTrackingTargetInfo): boolean {
    if (!targetInfo.supported || this.trackingAutoCreateAttempted || !(this.isOnlineContent?.() ?? false)) {
      return false;
    }
    if (targetInfo.contentType === SubscriptionContentType.NOVEL) {
      return true;
    }
    return targetInfo.contentType === SubscriptionContentType.MANGA &&
      (targetInfo.providerType === SubscriptionProviderType.SUWAYOMI ||
        targetInfo.providerType === SubscriptionProviderType.KOMGA ||
        targetInfo.providerType === SubscriptionProviderType.WEBVIEW);
  }


  private async autoCreateTrackingRule(targetInfo: UnifiedDetailTrackingTargetInfo): Promise<SubscriptionRule | null> {
    if (targetInfo.contentType === SubscriptionContentType.NOVEL) {
      const novelBookId = await this.ensureNovelTrackingBookId();
      return this.subscriptionManager.createOrUpdateNovelItemRule(novelBookId);
    }
    if (targetInfo.contentType === SubscriptionContentType.MANGA &&
      (targetInfo.providerType === SubscriptionProviderType.SUWAYOMI ||
        targetInfo.providerType === SubscriptionProviderType.KOMGA)) {
      return this.subscriptionManager.createOrUpdateRemoteMangaItemRule(targetInfo.targetId);
    }
    if (targetInfo.contentType === SubscriptionContentType.MANGA &&
      targetInfo.providerType === SubscriptionProviderType.WEBVIEW) {
      return this.subscriptionManager.createOrUpdateOnlineMangaItemRule(targetInfo.targetId);
    }
    return null;
  }


  private getTrackingProviderName(providerType: SubscriptionProviderType): string {
    if (providerType === SubscriptionProviderType.SUWAYOMI) {
      return 'Suwayomi';
    }
    if (providerType === SubscriptionProviderType.KOMGA) {
      return 'Komga';
    }
    if (providerType === SubscriptionProviderType.LEGADO) {
      return 'Legado';
    }
    if (providerType === SubscriptionProviderType.WEBVIEW) {
      return 'WebView';
    }
    return '通用';
  }


  private getTrackingProviderText(): string {
    if (this.trackingRule !== null) {
      const providerName = this.getTrackingProviderName(this.trackingRule.providerType);
      if (this.trackingRule.sourceName.length > 0 && this.trackingRule.sourceName !== providerName) {
        return `${providerName} · ${this.trackingRule.sourceName}`;
      }
      return providerName;
    }
    if (this.trackingTargetInfo !== null) {
      const providerName = this.getTrackingProviderName(this.trackingTargetInfo.providerType);
      if (this.trackingTargetInfo.sourceName.length > 0 && this.trackingTargetInfo.sourceName !== providerName) {
        return `${providerName} · ${this.trackingTargetInfo.sourceName}`;
      }
      return providerName;
    }
    return '';
  }


  private getTrackingExecutionStatusLabel(status: SubscriptionExecutionStatus): string {
    if (status === SubscriptionExecutionStatus.SUCCESS) {
      return '发现更新';
    }
    if (status === SubscriptionExecutionStatus.NO_UPDATE) {
      return '没有更新';
    }
    if (status === SubscriptionExecutionStatus.SKIPPED) {
      return '已跳过';
    }
    if (status === SubscriptionExecutionStatus.FAILED) {
      return '检查失败';
    }
    return '暂不支持';
  }


  private formatTrackingTimestamp(timestamp: number): string {
    if (timestamp <= 0) {
      return '还没检查过';
    }
    try {
      return new Date(timestamp).toLocaleString();
    } catch (_error) {
      return `${timestamp}`;
    }
  }


  private getTrackingMinNewItems(rule: SubscriptionRule): number {
    for (let index = 0; index < rule.conditions.length; index++) {
      const condition = rule.conditions[index];
      if (condition.type === SubscriptionConditionType.MIN_NEW_ITEMS && condition.enabled) {
        return condition.numericValue > 0 ? condition.numericValue : 1;
      }
    }
    return 1;
  }


  private trackingRequiresFavorite(rule: SubscriptionRule): boolean {
    for (let index = 0; index < rule.conditions.length; index++) {
      const condition = rule.conditions[index];
      if (condition.type === SubscriptionConditionType.ONLY_IF_FAVORITE && condition.enabled) {
        return true;
      }
    }
    return false;
  }


  private getTrackingConditionMatchMode(rule: SubscriptionRule): SubscriptionConditionMatchMode {
    for (let index = 0; index < rule.conditions.length; index++) {
      const condition = rule.conditions[index];
      if (condition.type === SubscriptionConditionType.MATCH_MODE && condition.enabled) {
        return condition.textValue === SubscriptionConditionMatchMode.ANY
          ? SubscriptionConditionMatchMode.ANY
          : SubscriptionConditionMatchMode.ALL;
      }
    }
    return SubscriptionConditionMatchMode.ALL;
  }


  private getTrackingPositiveConditionCount(rule: SubscriptionRule): number {
    let count = 0;
    if (this.trackingRequiresFavorite(rule)) {
      count++;
    }
    if (this.getTrackingConditionText(rule, SubscriptionConditionType.TITLE_KEYWORD).length > 0) {
      count++;
    }
    if (this.getTrackingConditionText(rule, SubscriptionConditionType.TAG_KEYWORD).length > 0) {
      count++;
    }
    if (this.getTrackingConditionText(rule, SubscriptionConditionType.SOURCE_KEYWORD).length > 0) {
      count++;
    }
    return count;
  }


  private getTrackingConditionMatchModeSummary(rule: SubscriptionRule): string {
    if (this.getTrackingPositiveConditionCount(rule) <= 1) {
      return '';
    }
    return this.getTrackingConditionMatchMode(rule) === SubscriptionConditionMatchMode.ANY
      ? '满足任意一项'
      : '需要全部满足';
  }


  private trackingExcludesNSFW(rule: SubscriptionRule): boolean {
    for (let index = 0; index < rule.conditions.length; index++) {
      const condition = rule.conditions[index];
      if (condition.type === SubscriptionConditionType.EXCLUDE_NSFW && condition.enabled) {
        return true;
      }
    }
    return false;
  }


  private getTrackingConditionText(rule: SubscriptionRule, conditionType: SubscriptionConditionType): string {
    for (let index = 0; index < rule.conditions.length; index++) {
      const condition = rule.conditions[index];
      if (condition.type === conditionType && condition.enabled && condition.textValue.trim().length > 0) {
        return condition.textValue.trim();
      }
    }
    return '';
  }


  private getTrackingConditionSummary(rule: SubscriptionRule | null): string {
    if (rule === null) {
      return '';
    }
    const parts: string[] = [formatSubscriptionIntervalSchedule(rule.checkIntervalMin), `至少新增 ${this.getTrackingMinNewItems(rule)}`];
    const matchModeSummary = this.getTrackingConditionMatchModeSummary(rule);
    if (matchModeSummary.length > 0) {
      parts.push(matchModeSummary);
    }
    if (this.trackingRequiresFavorite(rule)) {
      parts.push('只检查已收藏的内容');
    }
    if (this.trackingExcludesNSFW(rule)) {
      parts.push('跳过 NSFW');
    }
    const titleKeyword = this.getTrackingConditionText(rule, SubscriptionConditionType.TITLE_KEYWORD);
    if (titleKeyword.length > 0) {
      parts.push(`标题包含 ${titleKeyword}`);
    }
    const tagKeyword = this.getTrackingConditionText(rule, SubscriptionConditionType.TAG_KEYWORD);
    if (tagKeyword.length > 0) {
      parts.push(`标签包含 ${tagKeyword}`);
    }
    const sourceKeyword = this.getTrackingConditionText(rule, SubscriptionConditionType.SOURCE_KEYWORD);
    if (sourceKeyword.length > 0) {
      parts.push(`来源包含 ${sourceKeyword}`);
    }
    return parts.join(' · ');
  }


  private getTrackingActionSummary(rule: SubscriptionRule | null): string {
    if (rule === null) {
      return '';
    }
    const parts: string[] = [];
    for (let index = 0; index < rule.actions.length; index++) {
      const action = rule.actions[index];
      if (!action.enabled) {
        continue;
      }
      if (action.type === SubscriptionActionType.NOTIFY) {
        parts.push('提醒我');
      } else if (action.type === SubscriptionActionType.AUTO_DOWNLOAD_NEW) {
        parts.push(`自动下载 ${action.limitCount > 0 ? action.limitCount : '全部'}`);
      }
    }
    if (parts.length <= 0) {
      return '只检查，不自动处理';
    }
    return parts.join(' · ');
  }


  private createTrackingHighlight(
    id: string,
    text: string,
    tone: ContentTrackingHighlightTone
  ): ContentTrackingHighlight {
    return {
      id: id,
      text: text,
      tone: tone
    };
  }


  private buildTrackingConditionHighlights(rule: SubscriptionRule | null): ContentTrackingHighlight[] {
    const highlights: ContentTrackingHighlight[] = [];
    if (rule === null) {
      return highlights;
    }

    if (this.trackingAutoCreatedThisSession) {
      highlights.push(this.createTrackingHighlight(
        'auto_created',
        '这次已自动开启',
        ContentTrackingHighlightTone.INFO
      ));
    }

    highlights.push(this.createTrackingHighlight(
      'interval',
      formatSubscriptionIntervalSchedule(rule.checkIntervalMin),
      ContentTrackingHighlightTone.NEUTRAL
    ));
    highlights.push(this.createTrackingHighlight(
      'min_new_items',
      `至少新增 ${this.getTrackingMinNewItems(rule)}`,
      ContentTrackingHighlightTone.INFO
    ));

    if (this.getTrackingPositiveConditionCount(rule) > 1) {
      highlights.push(this.createTrackingHighlight(
        'match_mode',
        this.getTrackingConditionMatchMode(rule) === SubscriptionConditionMatchMode.ANY ? '满足任意一项' : '需要全部满足',
        ContentTrackingHighlightTone.PRIMARY
      ));
    }

    if (this.trackingRequiresFavorite(rule)) {
      highlights.push(this.createTrackingHighlight(
        'favorite_only',
        '只看已收藏',
        ContentTrackingHighlightTone.INFO
      ));
    }

    if (this.trackingExcludesNSFW(rule)) {
      highlights.push(this.createTrackingHighlight(
        'exclude_nsfw',
        '跳过 NSFW',
        ContentTrackingHighlightTone.WARNING
      ));
    }

    const titleKeyword = this.getTrackingConditionText(rule, SubscriptionConditionType.TITLE_KEYWORD);
    if (titleKeyword.length > 0) {
      highlights.push(this.createTrackingHighlight(
        'title_keyword',
        `标题: ${titleKeyword}`,
        ContentTrackingHighlightTone.PRIMARY
      ));
    }

    const tagKeyword = this.getTrackingConditionText(rule, SubscriptionConditionType.TAG_KEYWORD);
    if (tagKeyword.length > 0) {
      highlights.push(this.createTrackingHighlight(
        'tag_keyword',
        `标签: ${tagKeyword}`,
        ContentTrackingHighlightTone.SUCCESS
      ));
    }

    const sourceKeyword = this.getTrackingConditionText(rule, SubscriptionConditionType.SOURCE_KEYWORD);
    if (sourceKeyword.length > 0) {
      highlights.push(this.createTrackingHighlight(
        'source_keyword',
        `来源: ${sourceKeyword}`,
        ContentTrackingHighlightTone.INFO
      ));
    }

    return highlights;
  }


  private buildTrackingActionHighlights(rule: SubscriptionRule | null): ContentTrackingHighlight[] {
    const highlights: ContentTrackingHighlight[] = [];
    if (rule === null) {
      return highlights;
    }

    let hasExtraAction = false;
    for (let index = 0; index < rule.actions.length; index++) {
      const action = rule.actions[index];
      if (!action.enabled || action.type === SubscriptionActionType.CHECK_UPDATE) {
        continue;
      }
      hasExtraAction = true;
      if (action.type === SubscriptionActionType.NOTIFY) {
        highlights.push(this.createTrackingHighlight(
          'notify',
          '提醒我',
          ContentTrackingHighlightTone.INFO
        ));
      } else if (action.type === SubscriptionActionType.AUTO_DOWNLOAD_NEW) {
        highlights.push(this.createTrackingHighlight(
          'auto_download',
          action.limitCount > 0 ? `自动下载 ${action.limitCount} 项` : '自动下载全部',
          ContentTrackingHighlightTone.SUCCESS
        ));
      }
    }

    if (!hasExtraAction) {
      highlights.push(this.createTrackingHighlight(
        'check_only',
        '只检查更新',
        ContentTrackingHighlightTone.NEUTRAL
      ));
    }
    return highlights;
  }


  private getTrackingStatusText(): string {
    if (!this.trackingSupported) {
      return this.trackingUnsupportedReason.length > 0
        ? this.trackingUnsupportedReason
        : '这类内容暂时还不能自动检查';
    }
    if (this.trackingRule === null) {
      return '这本内容还没开始提醒';
    }
    if (this.trackingExecution !== null) {
      const label = this.getTrackingExecutionStatusLabel(this.trackingExecution.status);
      if (this.trackingExecution.message.length > 0) {
        return `${label} · ${this.trackingExecution.message}`;
      }
      return label;
    }
    if (this.trackingAutoCreatedThisSession) {
      return '已自动开启提醒，之后会在 APP 回到前台时按设置补查';
    }
    if (!this.trackingRule.enabled) {
      return '提醒已存在，当前已暂停';
    }
    return '提醒已开启，还没检查过';
  }


  private getTrackingChapterSummaryText(): string {
    if (!this.trackingSupported) {
      return '暂不支持';
    }
    if (this.trackingRule === null) {
      return '还没有提醒';
    }
    if (this.trackingExecution !== null) {
      if (this.trackingExecution.deltaCount > 0) {
        return `发现 ${this.trackingExecution.deltaCount} 个新内容`;
      }
      if (this.trackingExecution.status === SubscriptionExecutionStatus.NO_UPDATE) {
        return '最近没发现新内容';
      }
      if (this.trackingExecution.status === SubscriptionExecutionStatus.FAILED) {
        return '上次检查失败';
      }
      if (this.trackingExecution.status === SubscriptionExecutionStatus.SKIPPED) {
        return '这次没有检查';
      }
      if (this.trackingExecution.status === SubscriptionExecutionStatus.SUCCESS) {
        return '已经发现更新';
      }
      return '暂不支持';
    }
    if (this.trackingAutoCreatedThisSession) {
      return '已自动开启提醒';
    }
    if (!this.trackingRule.enabled) {
      return '已暂停自动检查';
    }
    return '还没检查过';
  }


  private buildTrackingCardState(): ContentTrackingCardState {
    let lastStatus = SubscriptionExecutionStatus.NO_UPDATE;
    if (this.trackingExecution !== null) {
      lastStatus = this.trackingExecution.status;
    } else if (this.trackingRule !== null && !this.trackingRule.enabled) {
      lastStatus = SubscriptionExecutionStatus.SKIPPED;
    }

    let lastCheckText = '尚未执行';
    if (this.trackingExecution !== null) {
      lastCheckText = this.formatTrackingTimestamp(this.trackingExecution.checkedAt);
    } else if (this.trackingRule !== null && this.trackingRule.lastCheckTime > 0) {
      lastCheckText = this.formatTrackingTimestamp(this.trackingRule.lastCheckTime);
    }

    let latestInfoText = '';
    if (this.trackingExecution !== null && this.trackingExecution.deltaCount > 0) {
      latestInfoText = `这次发现 ${this.trackingExecution.deltaCount} 个新内容`;
    } else if (this.trackingAutoCreatedThisSession && this.trackingRule !== null) {
      latestInfoText = '这次已自动开启提醒';
    }

    return {
      isLoading: this.isTrackingLoading,
      isBusy: this.isTrackingBusy,
      supported: this.trackingSupported,
      unsupportedReason: this.trackingUnsupportedReason,
      hasRule: this.trackingRule !== null,
      enabled: this.trackingRule !== null && this.trackingRule.enabled,
      autoCreatedThisSession: this.trackingAutoCreatedThisSession,
      ruleName: this.trackingRule !== null ? this.trackingRule.name : '',
      providerText: this.getTrackingProviderText(),
      conditionSummary: this.getTrackingConditionSummary(this.trackingRule),
      actionSummary: this.getTrackingActionSummary(this.trackingRule),
      statusText: this.getTrackingStatusText(),
      lastCheckText: lastCheckText,
      chapterSummary: this.getTrackingChapterSummaryText(),
      latestItemTitle: latestInfoText,
      lastStatus: lastStatus,
      conditionHighlights: this.buildTrackingConditionHighlights(this.trackingRule),
      actionHighlights: this.buildTrackingActionHighlights(this.trackingRule)
    };
  }


  private buildTrackingCardCallbacks(): ContentTrackingCardCallbacks {
    return {
      onConfigure: () => {
        void this.openTrackingSettingsDialog();
      },
      onRunNow: () => {
        void this.runCurrentContentTrackingNow();
      },
      onToggleEnabled: () => {
        void this.toggleCurrentContentTrackingEnabled();
      },
      onOpenManagement: () => {
        this.openTrackingManagementPage();
      }
    };
  }


  private async refreshTrackingState(showToastOnError: boolean = false): Promise<void> {
    if (!this.content) {
      this.trackingTargetInfo = null;
      this.trackingRule = null;
      this.trackingExecution = null;
      this.trackingSupported = false;
      this.trackingUnsupportedReason = '当前内容尚未加载完成';
      return;
    }
    if (this.isCurrentLocalImportedContent?.()) {
      this.trackingTargetInfo = null;
      this.trackingRule = null;
      this.trackingExecution = null;
      this.trackingSupported = false;
      this.trackingUnsupportedReason = '本地导入内容不显示更新提醒';
      this.isTrackingLoading = false;
      return;
    }

    this.isTrackingLoading = true;
    try {
      const targetInfo = await this.resolveCurrentTrackingTargetInfo();
      this.trackingTargetInfo = targetInfo;
      this.trackingSupported = targetInfo.supported;
      this.trackingUnsupportedReason = targetInfo.unsupportedReason;
      if (this.trackingAutoCreatedTargetId.length > 0 && this.trackingAutoCreatedTargetId !== targetInfo.targetId) {
        this.trackingAutoCreatedThisSession = false;
        this.trackingAutoCreatedTargetId = '';
      }

      if (!targetInfo.supported) {
        this.trackingRule = null;
        this.trackingExecution = null;
        return;
      }

      const ready = await this.ensureContentTrackingReady();
      if (!ready) {
        this.trackingRule = null;
        this.trackingExecution = null;
        this.trackingSupported = false;
        this.trackingUnsupportedReason = '更新提醒暂时没准备好';
        return;
      }

      let currentRule = await this.subscriptionManager.getItemRule(targetInfo.contentType, targetInfo.targetId);
      if (currentRule === null && this.shouldAutoCreateTrackingOnInitialEntry(targetInfo)) {
        this.trackingAutoCreateAttempted = true;
        try {
          currentRule = await this.autoCreateTrackingRule(targetInfo);
          if (currentRule !== null) {
            this.trackingAutoCreatedThisSession = true;
            this.trackingAutoCreatedTargetId = targetInfo.targetId;
            logger.info(TAG, `统一详情页首次进入已自动建立内容跟踪: ${targetInfo.targetTitle}`);
          }
        } catch (autoCreateError) {
          logger.warn(TAG, `首次进入自动建立内容跟踪失败: ${String(autoCreateError)}`);
        }
      }

      this.trackingRule = currentRule;
      if (currentRule !== null) {
        this.trackingExecution = await this.subscriptionManager.getLatestExecution(currentRule.id);
      } else {
        this.trackingExecution = null;
      }
    } catch (error) {
      logger.warn(TAG, `刷新内容跟踪状态失败: ${String(error)}`);
      this.trackingTargetInfo = null;
      this.trackingRule = null;
      this.trackingExecution = null;
      this.trackingSupported = false;
      this.trackingUnsupportedReason = '没能读到提醒状态';
      if (showToastOnError) {
        this.getUIContext().getPromptAction().showToast({ message: `没能读到提醒状态: ${String(error)}`, duration: 2000 });
      }
    } finally {
      this.isTrackingLoading = false;
      this.onTrackingStateChanged?.(this.buildTrackingCardState(), this.buildTrackingCardCallbacks());
    }
  }


  private parseTrackingPositiveInteger(text: string, defaultValue: number, minValue: number): number {
    const parsedValue = Number(text.trim());
    if (Number.isNaN(parsedValue) || !Number.isFinite(parsedValue)) {
      return defaultValue;
    }
    const normalizedValue = Math.floor(parsedValue);
    if (normalizedValue < minValue) {
      return minValue;
    }
    return normalizedValue;
  }


  private fillTrackingDialogFromRule(rule: SubscriptionRule | null): void {
    if (rule === null) {
      this.trackingCheckIntervalText = '3';
      this.trackingCheckIntervalUnit = SubscriptionIntervalUnit.HOUR;
      this.trackingMinNewItemsText = '1';
      this.trackingAutoDownloadCountText = '0';
      this.trackingConditionMatchMode = SubscriptionConditionMatchMode.ALL;
      this.trackingRequireFavorite = false;
      this.trackingExcludeNSFW = false;
      this.trackingTitleKeywordText = '';
      this.trackingTagKeywordText = '';
      this.trackingSourceKeywordText = '';
      this.trackingEnableNotify = true;
      return;
    }

    const intervalDisplay = splitSubscriptionIntervalMinutesForDisplay(rule.checkIntervalMin);
    this.trackingCheckIntervalText = intervalDisplay.valueText;
    this.trackingCheckIntervalUnit = intervalDisplay.unit;
    this.trackingMinNewItemsText = `${this.getTrackingMinNewItems(rule)}`;
    this.trackingAutoDownloadCountText = '0';
    this.trackingConditionMatchMode = this.getTrackingConditionMatchMode(rule);
    this.trackingEnableNotify = false;
    for (let index = 0; index < rule.actions.length; index++) {
      const action = rule.actions[index];
      if (action.type === SubscriptionActionType.NOTIFY && action.enabled) {
        this.trackingEnableNotify = true;
      } else if (action.type === SubscriptionActionType.AUTO_DOWNLOAD_NEW && action.enabled) {
        this.trackingAutoDownloadCountText = `${action.limitCount > 0 ? action.limitCount : 0}`;
      }
    }
    this.trackingRequireFavorite = this.trackingRequiresFavorite(rule);
    this.trackingExcludeNSFW = this.trackingExcludesNSFW(rule);
    this.trackingTitleKeywordText = this.getTrackingConditionText(rule, SubscriptionConditionType.TITLE_KEYWORD);
    this.trackingTagKeywordText = this.getTrackingConditionText(rule, SubscriptionConditionType.TAG_KEYWORD);
    this.trackingSourceKeywordText = this.getTrackingConditionText(rule, SubscriptionConditionType.SOURCE_KEYWORD);
  }


  private buildTrackingCreateOptions(): Partial<SubscriptionRuleCreateOptions> {
    return {
      checkIntervalMin: convertSubscriptionIntervalDisplayToMinutes(
        this.trackingCheckIntervalText,
        this.trackingCheckIntervalUnit,
        180
      ),
      minNewItems: this.parseTrackingPositiveInteger(this.trackingMinNewItemsText, 1, 1),
      autoDownloadCount: this.parseTrackingPositiveInteger(this.trackingAutoDownloadCountText, 0, 0),
      conditionMatchMode: this.trackingConditionMatchMode,
      requireFavorite: this.trackingRequireFavorite,
      enableNotify: this.trackingEnableNotify,
      excludeNSFW: this.trackingExcludeNSFW,
      titleKeyword: this.trackingTitleKeywordText.trim(),
      tagKeyword: this.trackingTagKeywordText.trim(),
      sourceKeyword: this.trackingSourceKeywordText.trim()
    };
  }


  private async openTrackingSettingsDialog(): Promise<void> {
    if (this.isTrackingBusy) {
      return;
    }
    if (this.trackingTargetInfo === null || (this.trackingRule === null && !this.trackingSupported)) {
      await this.refreshTrackingState(true);
    }
    if (!this.trackingSupported) {
      this.getUIContext().getPromptAction().showToast({
        message: this.trackingUnsupportedReason.length > 0 ? this.trackingUnsupportedReason : '这类内容暂时还不能添加提醒',
        duration: 2000
      });
      return;
    }

    this.fillTrackingDialogFromRule(this.trackingRule);
    this.trackingSettingsActiveTab = 0;
    this.getUIContext().animateTo({
      duration: 220,
      curve: Curve.EaseOut
    }, () => {
      this.showTrackingSettingsDialog = true;
    });
  }


  private closeTrackingSettingsDialog(): void {
    this.getUIContext().animateTo({
      duration: 180,
      curve: Curve.EaseIn
    }, () => {
      this.showTrackingSettingsDialog = false;
    });
  }


  private async saveCurrentContentTracking(): Promise<void> {
    if (this.isTrackingBusy) {
      return;
    }
    const targetInfo = this.trackingTargetInfo;
    if (targetInfo === null || !targetInfo.supported) {
      this.getUIContext().getPromptAction().showToast({ message: '这类内容暂时还不能在这里开启提醒', duration: 2000 });
      return;
    }

    this.isTrackingBusy = true;
    const hadExistingRule = this.trackingRule !== null;
    try {
      const createOptions = this.buildTrackingCreateOptions();
      if (targetInfo.contentType === SubscriptionContentType.NOVEL) {
        const novelBookId = await this.ensureNovelTrackingBookId();
        this.trackingRule = await this.subscriptionManager.createOrUpdateNovelItemRule(novelBookId, createOptions);
      } else if (targetInfo.contentType === SubscriptionContentType.MANGA &&
        (targetInfo.providerType === SubscriptionProviderType.SUWAYOMI || targetInfo.providerType === SubscriptionProviderType.KOMGA)) {
        this.trackingRule = await this.subscriptionManager.createOrUpdateRemoteMangaItemRule(targetInfo.targetId, createOptions);
      } else {
        throw new Error('这类内容暂时还不能在详情页开启提醒');
      }

      await this.refreshTrackingState();
      this.closeTrackingSettingsDialog();
      this.getUIContext().getPromptAction().showToast({
        message: hadExistingRule
          ? '提醒设置已更新，之后会在 APP 回到前台时补查'
          : '已为当前内容开启提醒，之后会在 APP 回到前台时补查',
        duration: 1800
      });
    } catch (error) {
      logger.error(TAG, `保存内容跟踪配置失败: ${String(error)}`);
      this.getUIContext().getPromptAction().showToast({ message: `保存失败: ${String(error)}`, duration: 2000 });
    } finally {
      this.isTrackingBusy = false;
    }
  }


  private async runCurrentContentTrackingNow(): Promise<void> {
    if (this.trackingRule === null || this.isTrackingBusy) {
      return;
    }
    this.isTrackingBusy = true;
    try {
      const result = await this.subscriptionManager.runRuleNow(this.trackingRule.id, 'detail_page_manual');
      await this.refreshTrackingState();
      this.getUIContext().getPromptAction().showToast({
        message: result.message.length > 0 ? result.message : '已开始检查当前内容',
        duration: 2000
      });
    } catch (error) {
      logger.error(TAG, `立即执行内容跟踪失败: ${String(error)}`);
      this.getUIContext().getPromptAction().showToast({ message: `执行失败: ${String(error)}`, duration: 2000 });
    } finally {
      this.isTrackingBusy = false;
    }
  }


  private async toggleCurrentContentTrackingEnabled(): Promise<void> {
    if (this.trackingRule === null || this.isTrackingBusy) {
      return;
    }
    this.isTrackingBusy = true;
    try {
      await this.subscriptionManager.setRuleEnabled(this.trackingRule.id, !this.trackingRule.enabled);
      await this.refreshTrackingState();
      this.getUIContext().getPromptAction().showToast({
        message: this.trackingRule !== null && this.trackingRule.enabled
          ? '已开启更新提醒，APP 回到前台时会自动补查'
          : '已暂停更新提醒',
        duration: 1600
      });
    } catch (error) {
      logger.error(TAG, `切换内容跟踪启用状态失败: ${String(error)}`);
      this.getUIContext().getPromptAction().showToast({ message: `操作失败: ${String(error)}`, duration: 2000 });
    } finally {
      this.isTrackingBusy = false;
    }
  }


  private confirmDeleteCurrentContentTracking(): void {
    if (this.trackingRule === null) {
      return;
    }
    const ruleName = this.trackingRule.name.length > 0
      ? this.trackingRule.name
      : (this.content ? this.content.title : '当前内容');
    this.getUIContext().getPromptAction().showDialog({
      title: '关闭更新提醒',
      message: `确认关闭「${ruleName}」的更新提醒？`,
      buttons: [
        { text: '取消', color: '#666666' },
        { text: '关闭', color: '#FF4D4F' }
      ]
    }).then((dialogResult: promptAction.ShowDialogSuccessResponse) => {
      if (dialogResult.index === 1) {
        void this.deleteCurrentContentTracking();
      }
    });
  }


  private async deleteCurrentContentTracking(): Promise<void> {
    if (this.trackingRule === null || this.isTrackingBusy) {
      return;
    }
    this.isTrackingBusy = true;
    try {
      await this.subscriptionManager.deleteRule(this.trackingRule.id);
      this.closeTrackingSettingsDialog();
      await this.refreshTrackingState();
      this.getUIContext().getPromptAction().showToast({ message: '已关闭当前内容的更新提醒', duration: 1800 });
    } catch (error) {
      logger.error(TAG, `删除内容跟踪规则失败: ${String(error)}`);
      this.getUIContext().getPromptAction().showToast({ message: `删除失败: ${String(error)}`, duration: 2000 });
    } finally {
      this.isTrackingBusy = false;
    }
  }


  private openTrackingManagementPage(): void {
    this.onNavigate?.('SubscriptionManagementPage', null);
  }


  // ==================== Builder 方法 ====================

  @Builder
  buildTrackingStatusSection() {
    if (this.shouldShowTrackingStatusSection()) {
      Stack({ alignContent: Alignment.TopStart }) {
        this.buildGlassSectionChrome()
        ContentTrackingStatusCard({
          state: this.buildTrackingCardState(),
          themeState: this.themeState,
          appFontFamily: this.appFontFamily,
          callbacks: this.buildTrackingCardCallbacks()
        })
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
      .id('' as string)
    }
  }


  @Builder
  private buildTrackingToggleRow(
    titleText: string,
    subtitleText: string,
    isOn: boolean,
    onChange: (value: boolean) => void
  ) {
    Row() {
      Column({ space: 4 }) {
        Text(titleText)
          .fontSize(13)
          .fontWeight(FontWeight.Medium)
          .fontFamily(this.appFontFamily)
          .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_primary', this.themeState.currentTheme))
        Text(subtitleText)
          .fontSize(11)
          .lineHeight(17)
          .fontFamily(this.appFontFamily)
          .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_secondary', this.themeState.currentTheme))
          .width('100%')
      }
      .layoutWeight(1)
      .alignItems(HorizontalAlign.Start)

      Toggle({ type: ToggleType.Switch, isOn: isOn })
        .selectedColor(ThemeAwareHelper.getTestManagementThemedColor('accent_primary', this.themeState.currentTheme))
        .onChange((value: boolean) => {
          onChange(value);
        })
    }
    .width('100%')
    .padding(12)
    .backgroundColor(ThemeAwareHelper.getTestManagementThemedColor('comp_background_secondary', this.themeState.currentTheme))
    .borderRadius(12)
  }


  private getTrackingIntervalPreviewText(): string {
    const totalMinutes = convertSubscriptionIntervalDisplayToMinutes(
      this.trackingCheckIntervalText,
      this.trackingCheckIntervalUnit,
      180
    );
    return `当前会按 ${formatSubscriptionIntervalSchedule(totalMinutes)}，并在 APP 回到前台时补查`;
  }


  @Builder
  private buildTrackingIntervalUnitOption(unit: SubscriptionIntervalUnit) {
    Button(getSubscriptionIntervalUnitLabel(unit))
      .layoutWeight(1)
      .height(34)
      .fontSize(12)
      .fontWeight(FontWeight.Medium)
      .fontFamily(this.appFontFamily)
      .fontColor(this.trackingCheckIntervalUnit === unit
        ? Color.White
        : ThemeAwareHelper.getTestManagementThemedColor('text_primary', this.themeState.currentTheme))
      .backgroundColor(this.trackingCheckIntervalUnit === unit
        ? ThemeAwareHelper.getTestManagementThemedColor('accent_primary', this.themeState.currentTheme)
        : ThemeAwareHelper.getTestManagementThemedColor('comp_background_secondary', this.themeState.currentTheme))
      .borderRadius(12)
      .border({
        width: 1,
        color: this.trackingCheckIntervalUnit === unit
          ? ThemeAwareHelper.getTestManagementThemedColor('accent_primary', this.themeState.currentTheme)
          : ThemeAwareHelper.getTestManagementThemedColor('panel_border', this.themeState.currentTheme)
      })
      .onClick(() => {
        this.trackingCheckIntervalUnit = unit;
      })
  }


  @Builder
  private buildTrackingIntervalInput() {
    Column({ space: 8 }) {
      Column({ space: 6 }) {
        Text('多久检查一次')
          .fontSize(12)
          .fontFamily(this.appFontFamily)
          .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_secondary', this.themeState.currentTheme))
          .width('100%')
        TextInput({ placeholder: '例如 3', text: $$this.trackingCheckIntervalText })
          .width('100%')
          .height(40)
          .type(InputType.Number)
          .fontSize(13)
          .fontFamily(this.appFontFamily)
          .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_primary', this.themeState.currentTheme))
          .placeholderColor(ThemeAwareHelper.getTestManagementThemedColor('text_tertiary', this.themeState.currentTheme))
          .caretColor(ThemeAwareHelper.getTestManagementThemedColor('accent_primary', this.themeState.currentTheme))
          .padding({ left: 10, right: 10 })
          .backgroundColor(ThemeAwareHelper.getTestManagementThemedColor('comp_background_secondary', this.themeState.currentTheme))
          .borderRadius(12)
      }
      .width('100%')

      Column({ space: 8 }) {
        Text('时间单位')
          .fontSize(12)
          .fontFamily(this.appFontFamily)
          .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_secondary', this.themeState.currentTheme))
          .width('100%')
        Row({ space: 8 }) {
          this.buildTrackingIntervalUnitOption(SubscriptionIntervalUnit.MINUTE)
          this.buildTrackingIntervalUnitOption(SubscriptionIntervalUnit.HOUR)
          this.buildTrackingIntervalUnitOption(SubscriptionIntervalUnit.DAY)
          this.buildTrackingIntervalUnitOption(SubscriptionIntervalUnit.WEEK)
        }
        .width('100%')
        Text(this.getTrackingIntervalPreviewText())
          .fontSize(11)
          .lineHeight(17)
          .fontFamily(this.appFontFamily)
          .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_secondary', this.themeState.currentTheme))
          .width('100%')
      }
      .width('100%')
    }
    .width('100%')
  }


  @Builder
  private buildTrackingConditionMatchModeSelector() {
    Column({ space: 8 }) {
      Text('条件怎么判断')
        .fontSize(12)
        .fontFamily(this.appFontFamily)
        .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_secondary', this.themeState.currentTheme))
        .width('100%')
      Row({ space: 8 }) {
        this.buildTrackingConditionMatchModeOption(
          SubscriptionConditionMatchMode.ALL,
          '全部满足',
          '设定的条件都满足时才继续'
        )
        this.buildTrackingConditionMatchModeOption(
          SubscriptionConditionMatchMode.ANY,
          '任意一项',
          '满足其中一项就继续'
        )
      }
      .width('100%')
    }
    .width('100%')
  }


  @Builder
  private buildTrackingConditionMatchModeOption(
    optionMode: SubscriptionConditionMatchMode,
    titleText: string,
    subtitleText: string
  ) {
    Button() {
      Column({ space: 4 }) {
        Text(titleText)
          .fontSize(13)
          .fontWeight(FontWeight.Medium)
          .fontFamily(this.appFontFamily)
          .fontColor(this.trackingConditionMatchMode === optionMode
            ? '#FFFFFF'
            : ThemeAwareHelper.getTestManagementThemedColor('text_primary', this.themeState.currentTheme))
        Text(subtitleText)
          .fontSize(10)
          .lineHeight(15)
          .fontFamily(this.appFontFamily)
          .fontColor(this.trackingConditionMatchMode === optionMode
            ? '#FFFFFFCC'
            : ThemeAwareHelper.getTestManagementThemedColor('text_secondary', this.themeState.currentTheme))
          .textAlign(TextAlign.Center)
      }
      .width('100%')
      .alignItems(HorizontalAlign.Center)
    }
    .layoutWeight(1)
    .padding(12)
    .backgroundColor(this.trackingConditionMatchMode === optionMode
      ? ThemeAwareHelper.getTestManagementThemedColor('accent_primary', this.themeState.currentTheme)
      : ThemeAwareHelper.getTestManagementThemedColor('comp_background_primary', this.themeState.currentTheme))
    .borderRadius(14)
    .onClick(() => {
      this.trackingConditionMatchMode = optionMode;
    })
  }


  @Builder
  private buildTrackingSettingsTabButton(label: string, icon: Resource, index: number) {
    Row({ space: 6 }) {
      SymbolGlyph(icon)
        .fontSize(13)
        .fontColor([this.trackingSettingsActiveTab === index
          ? Color.White
          : ThemeAwareHelper.getTestManagementThemedColor('text_secondary', this.themeState.currentTheme)])
      Text(label)
        .fontSize(13)
        .fontFamily(this.appFontFamily)
        .fontWeight(FontWeight.Medium)
        .fontColor(this.trackingSettingsActiveTab === index
          ? Color.White
          : ThemeAwareHelper.getTestManagementThemedColor('text_secondary', this.themeState.currentTheme))
    }
    .layoutWeight(1)
    .height(34)
    .justifyContent(FlexAlign.Center)
    .backgroundColor(this.trackingSettingsActiveTab === index
      ? ThemeAwareHelper.getTestManagementThemedColor('accent_primary', this.themeState.currentTheme)
      : Color.Transparent)
    .borderRadius(14)
    .scale({
      x: this.trackingSettingsActiveTab === index ? 1 : 0.97,
      y: this.trackingSettingsActiveTab === index ? 1 : 0.97
    })
    .animation({ duration: 160, curve: Curve.EaseOut })
    .onClick(() => {
      this.handleTrackingSettingsDialogTabChange(index);
    })
  }


  private handleTrackingSettingsDialogTabChange(index: number): void {
    if (this.trackingSettingsActiveTab === index) {
      return;
    }
    this.getUIContext().animateTo({ duration: 220, curve: Curve.EaseInOut }, () => {
      this.trackingSettingsActiveTab = index;
    });
  }


  private getTrackingDialogStatusColor(): ResourceColor {
    if (this.trackingExecution !== null) {
      if (this.trackingExecution.status === SubscriptionExecutionStatus.SUCCESS) {
        return ThemeAwareHelper.getTestManagementThemedColor('accent_green', this.themeState.currentTheme);
      }
      if (this.trackingExecution.status === SubscriptionExecutionStatus.NO_UPDATE) {
        return ThemeAwareHelper.getTestManagementThemedColor('accent_blue', this.themeState.currentTheme);
      }
      if (this.trackingExecution.status === SubscriptionExecutionStatus.SKIPPED) {
        return ThemeAwareHelper.getTestManagementThemedColor('accent_orange', this.themeState.currentTheme);
      }
      if (this.trackingExecution.status === SubscriptionExecutionStatus.FAILED) {
        return ThemeAwareHelper.getTestManagementThemedColor('color_error', this.themeState.currentTheme);
      }
    }
    if (this.trackingRule !== null && !this.trackingRule.enabled) {
      return ThemeAwareHelper.getTestManagementThemedColor('accent_orange', this.themeState.currentTheme);
    }
    return ThemeAwareHelper.getTestManagementThemedColor('accent_blue', this.themeState.currentTheme);
  }


  private getTrackingDialogLastCheckText(): string {
    if (this.trackingExecution !== null) {
      return this.formatTrackingTimestamp(this.trackingExecution.checkedAt);
    }
    if (this.trackingRule !== null && this.trackingRule.lastCheckTime > 0) {
      return this.formatTrackingTimestamp(this.trackingRule.lastCheckTime);
    }
    if (this.trackingAutoCreatedThisSession && this.trackingRule !== null) {
      return '本次已自动开启';
    }
    return '还没检查过';
  }


  private isTrackingRuleEnabled(): boolean {
    return this.trackingRule !== null && this.trackingRule.enabled;
  }


  private getTrackingDialogFooterHintText(): string {
    if (this.trackingRule === null) {
      return '保存后会开始记录，但自动检查只会在 APP 回到前台时补查。';
    }
    if (this.trackingSettingsActiveTab === 0) {
      return this.isTrackingRuleEnabled()
        ? '可以先手动检查一次；自动检查目前只会在 APP 回到前台时补查。'
        : '提醒当前已暂停，重新开启后也只会在 APP 回到前台时自动补查。';
    }
    if (this.trackingSettingsActiveTab === 1) {
      return '这些筛选条件会决定哪些更新会被算进去；自动检查仍只会在 APP 回到前台时补查。';
    }
    return '这里决定发现更新后要提醒你，还是顺手自动下载；这些动作会跟着前台补查一起执行。';
  }


  private getTrackingOverviewInlineText(): string {
    const parts: string[] = [];
    const providerText = this.getTrackingProviderText().trim();
    if (providerText.length > 0) {
      parts.push(providerText);
    }

    if (this.trackingRule === null) {
      parts.push('还没开启提醒');
    } else if (!this.trackingRule.enabled) {
      parts.push('已暂停');
    } else if (this.trackingExecution !== null) {
      parts.push(this.getTrackingExecutionStatusLabel(this.trackingExecution.status));
    } else if (this.trackingAutoCreatedThisSession) {
      parts.push('本次已自动开启');
    } else {
      parts.push('已开启');
    }

    const lastCheckText = this.getTrackingDialogLastCheckText();
    if (lastCheckText.length > 0) {
      parts.push(`上次 ${lastCheckText}`);
    }

    if (this.trackingExecution !== null && this.trackingExecution.deltaCount > 0) {
      parts.push(`新增 ${this.trackingExecution.deltaCount}`);
    }

    return parts.join(' · ');
  }


  @Builder
  private buildTrackingSettingsMetricCard(labelText: string, valueText: string, accentColor: ResourceColor) {
    Column({ space: 6 }) {
      Text(labelText)
        .fontSize(11)
        .fontFamily(this.appFontFamily)
        .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_muted', this.themeState.currentTheme))
        .width('100%')
      Text(valueText)
        .fontSize(13)
        .fontWeight(FontWeight.Medium)
        .fontFamily(this.appFontFamily)
        .fontColor(accentColor)
        .width('100%')
        .maxLines(2)
        .textOverflow({ overflow: TextOverflow.Ellipsis })
    }
    .layoutWeight(1)
    .padding(12)
    .backgroundColor(ThemeAwareHelper.getTestManagementThemedColor('comp_background_secondary', this.themeState.currentTheme))
    .borderRadius(12)
    .alignItems(HorizontalAlign.Start)
  }


  @Builder
  private buildTrackingSettingsOverviewCard() {
    Column({ space: 6 }) {
      Text(this.getTrackingOverviewInlineText())
        .fontSize(12)
        .fontFamily(this.appFontFamily)
        .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_secondary', this.themeState.currentTheme))
        .width('100%')
        .maxLines(1)
        .textOverflow({ overflow: TextOverflow.Ellipsis })
      Text('当前版本只会在 APP 回到前台时自动补查，后台不会定时执行。')
        .fontSize(11)
        .lineHeight(17)
        .fontFamily(this.appFontFamily)
        .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_muted', this.themeState.currentTheme))
        .width('100%')
    }
    .width('100%')
    .padding({ left: 12, right: 12, top: 10, bottom: 10 })
    .backgroundColor(ThemeAwareHelper.getTestManagementThemedColor('comp_background_tertiary', this.themeState.currentTheme))
    .borderRadius(12)
  }


  @Builder
  private buildTrackingSettingsDialogFooter() {
    Column({ space: 10 }) {
      Row() {
        Text(this.getTrackingDialogFooterHintText())
          .fontSize(12)
          .fontFamily(this.appFontFamily)
          .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_secondary', this.themeState.currentTheme))
          .layoutWeight(1)
          .maxLines(2)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
        if (this.trackingRule !== null) {
          Text(this.getTrackingDialogLastCheckText())
            .fontSize(11)
            .fontFamily(this.appFontFamily)
            .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_muted', this.themeState.currentTheme))
        }
      }
      .width('100%')

      if (this.trackingRule !== null && this.trackingSettingsActiveTab === 0) {
        Row({ space: 10 }) {
          Button(this.isTrackingRuleEnabled() ? '暂停提醒' : '开启提醒')
            .layoutWeight(1)
            .height(36)
            .fontSize(12)
            .fontFamily(this.appFontFamily)
            .backgroundColor(ThemeAwareHelper.getTestManagementThemedColor('comp_background_secondary', this.themeState.currentTheme))
            .fontColor(this.isTrackingRuleEnabled()
              ? ThemeAwareHelper.getTestManagementThemedColor('accent_orange', this.themeState.currentTheme)
              : ThemeAwareHelper.getTestManagementThemedColor('accent_green', this.themeState.currentTheme))
            .borderRadius(18)
            .enabled(!this.isTrackingBusy)
            .onClick(() => {
              void this.toggleCurrentContentTrackingEnabled();
            })

          Button(this.isTrackingBusy ? '检查中...' : '立即检查')
            .layoutWeight(1)
            .height(36)
            .fontSize(12)
            .fontFamily(this.appFontFamily)
            .backgroundColor(ThemeAwareHelper.getTestManagementThemedColor('accent_primary', this.themeState.currentTheme))
            .fontColor(Color.White)
            .borderRadius(18)
            .enabled(!this.isTrackingBusy)
            .onClick(() => {
              void this.runCurrentContentTrackingNow();
            })
        }
        .width('100%')
      } else if (this.trackingRule !== null && this.trackingSettingsActiveTab === 2) {
        Row({ space: 10 }) {
          Button('关闭提醒')
            .layoutWeight(1)
            .height(36)
            .fontSize(12)
            .fontFamily(this.appFontFamily)
            .backgroundColor(ThemeAwareHelper.getTestManagementThemedColor('comp_background_secondary', this.themeState.currentTheme))
            .fontColor(ThemeAwareHelper.getTestManagementThemedColor('color_error', this.themeState.currentTheme))
            .borderRadius(18)
            .enabled(!this.isTrackingBusy)
            .onClick(() => {
              this.confirmDeleteCurrentContentTracking();
            })

          Button(this.isTrackingBusy ? '保存中...' : '保存设置')
            .layoutWeight(1)
            .height(36)
            .fontSize(12)
            .fontFamily(this.appFontFamily)
            .backgroundColor(ThemeAwareHelper.getTestManagementThemedColor('accent_primary', this.themeState.currentTheme))
            .fontColor(Color.White)
            .borderRadius(18)
            .enabled(!this.isTrackingBusy)
            .onClick(() => {
              void this.saveCurrentContentTracking();
            })
        }
        .width('100%')
      } else {
        Row({ space: 10 }) {
          Button('取消')
            .layoutWeight(1)
            .height(36)
            .fontSize(12)
            .fontFamily(this.appFontFamily)
            .backgroundColor(ThemeAwareHelper.getTestManagementThemedColor('comp_background_secondary', this.themeState.currentTheme))
            .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_primary', this.themeState.currentTheme))
            .borderRadius(18)
            .enabled(!this.isTrackingBusy)
            .onClick(() => {
              this.closeTrackingSettingsDialog();
            })

          Button(this.isTrackingBusy ? '保存中...' : (this.trackingRule !== null ? '保存设置' : '开启提醒'))
            .layoutWeight(1)
            .height(36)
            .fontSize(12)
            .fontFamily(this.appFontFamily)
            .backgroundColor(ThemeAwareHelper.getTestManagementThemedColor('accent_primary', this.themeState.currentTheme))
            .fontColor(Color.White)
            .borderRadius(18)
            .enabled(!this.isTrackingBusy)
            .onClick(() => {
              void this.saveCurrentContentTracking();
            })
        }
        .width('100%')
      }
    }
    .width('100%')
    .animation({ duration: 200, curve: Curve.EaseOut })
  }


  @Builder
  private buildTrackingDialogHintCard(titleText: string, descriptionText: string) {
    Column({ space: 6 }) {
      Text(titleText)
        .fontSize(13)
        .fontWeight(FontWeight.Medium)
        .fontFamily(this.appFontFamily)
        .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_primary', this.themeState.currentTheme))
        .width('100%')
      Text(descriptionText)
        .fontSize(11)
        .lineHeight(17)
        .fontFamily(this.appFontFamily)
        .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_secondary', this.themeState.currentTheme))
        .width('100%')
    }
    .width('100%')
    .padding(12)
    .backgroundColor(ThemeAwareHelper.getTestManagementThemedColor('comp_background_secondary', this.themeState.currentTheme))
    .borderRadius(14)
  }


  @Builder
  private buildTrackingBasicSettingsTab() {
    Column({ space: 12 }) {
      this.buildTrackingDialogHintCard('基础设置', '先决定多久检查一次，以及最少出现多少新内容时再提醒你。当前版本只会在 APP 回到前台时自动补查。')

      Column({ space: 12 }) {
        this.buildTrackingIntervalInput()

        Column({ space: 6 }) {
          Text('至少新增多少才提醒')
            .fontSize(12)
            .fontFamily(this.appFontFamily)
            .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_secondary', this.themeState.currentTheme))
            .width('100%')
          TextInput({ placeholder: '例如 1', text: $$this.trackingMinNewItemsText })
            .width('100%')
            .height(40)
            .type(InputType.Number)
            .fontSize(13)
            .fontFamily(this.appFontFamily)
            .backgroundColor(ThemeAwareHelper.getTestManagementThemedColor('comp_background_secondary', this.themeState.currentTheme))
            .borderRadius(12)
        }
        .width('100%')
      }
      .width('100%')
      .padding(12)
      .backgroundColor(ThemeAwareHelper.getTestManagementThemedColor('comp_background_tertiary', this.themeState.currentTheme))
      .borderRadius(14)
    }
    .width('100%')
  }


  @Builder
  private buildTrackingFilterSettingsTab() {
    Column({ space: 12 }) {
      this.buildTrackingDialogHintCard('筛选条件', '这些条件会先帮你筛一遍内容。你可以选“全部满足”或“任意一项”；同一个输入框里用逗号分隔多个词，命中一个就算通过。')

      Column({ space: 12 }) {
        this.buildTrackingConditionMatchModeSelector()

        Column({ space: 6 }) {
          Text('标题包含')
            .fontSize(12)
            .fontFamily(this.appFontFamily)
            .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_secondary', this.themeState.currentTheme))
            .width('100%')
          TextInput({ placeholder: '例如：番外，合集', text: $$this.trackingTitleKeywordText })
            .width('100%')
            .height(40)
            .fontSize(13)
            .fontFamily(this.appFontFamily)
            .backgroundColor(ThemeAwareHelper.getTestManagementThemedColor('comp_background_primary', this.themeState.currentTheme))
            .borderRadius(12)
        }
        .width('100%')

        Column({ space: 6 }) {
          Text('标签包含')
            .fontSize(12)
            .fontFamily(this.appFontFamily)
            .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_secondary', this.themeState.currentTheme))
            .width('100%')
          TextInput({ placeholder: '例如：校园，悬疑', text: $$this.trackingTagKeywordText })
            .width('100%')
            .height(40)
            .fontSize(13)
            .fontFamily(this.appFontFamily)
            .backgroundColor(ThemeAwareHelper.getTestManagementThemedColor('comp_background_primary', this.themeState.currentTheme))
            .borderRadius(12)
        }
        .width('100%')

        Column({ space: 6 }) {
          Text('来源包含')
            .fontSize(12)
            .fontFamily(this.appFontFamily)
            .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_secondary', this.themeState.currentTheme))
            .width('100%')
          TextInput({ placeholder: '例如：Suwayomi，Komga，书源名', text: $$this.trackingSourceKeywordText })
            .width('100%')
            .height(40)
            .fontSize(13)
            .fontFamily(this.appFontFamily)
            .backgroundColor(ThemeAwareHelper.getTestManagementThemedColor('comp_background_primary', this.themeState.currentTheme))
            .borderRadius(12)
        }
        .width('100%')

        this.buildTrackingToggleRow('只检查已收藏的内容', '取消收藏后会自动跳过。', this.trackingRequireFavorite, (value: boolean) => {
          this.trackingRequireFavorite = value;
        })

        this.buildTrackingToggleRow('跳过 NSFW 内容', '内容带有 NSFW 标记时会直接跳过。', this.trackingExcludeNSFW, (value: boolean) => {
          this.trackingExcludeNSFW = value;
        })
      }
      .width('100%')
      .padding(12)
      .backgroundColor(ThemeAwareHelper.getTestManagementThemedColor('comp_background_tertiary', this.themeState.currentTheme))
      .borderRadius(14)
    }
    .width('100%')
  }


  @Builder
  private buildTrackingActionSettingsTab() {
    Column({ space: 12 }) {
      this.buildTrackingDialogHintCard('发现更新后', '这里决定发现更新以后要做什么。支持的内容可以自动下载，不需要的也可以只提醒；这些动作会跟着前台补查一起执行。')

      Column({ space: 12 }) {
        Column({ space: 6 }) {
          Text('自动下载数量（填 0 关闭）')
            .fontSize(12)
            .fontFamily(this.appFontFamily)
            .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_secondary', this.themeState.currentTheme))
            .width('100%')
          TextInput({ placeholder: '例如 0 / 3 / 10', text: $$this.trackingAutoDownloadCountText })
            .width('100%')
            .height(40)
            .type(InputType.Number)
            .fontSize(13)
            .fontFamily(this.appFontFamily)
            .backgroundColor(ThemeAwareHelper.getTestManagementThemedColor('comp_background_secondary', this.themeState.currentTheme))
            .borderRadius(12)
        }
        .width('100%')

        this.buildTrackingToggleRow('更新时提醒我', '有更新时发应用内通知。提醒会跟着前台补查一起触发。', this.trackingEnableNotify, (value: boolean) => {
          this.trackingEnableNotify = value;
        })
      }
      .width('100%')
      .padding(12)
      .backgroundColor(ThemeAwareHelper.getTestManagementThemedColor('comp_background_tertiary', this.themeState.currentTheme))
      .borderRadius(14)
    }
    .width('100%')
  }


  @Builder
  private buildTrackingSettingsDialog() {
    if (this.showTrackingSettingsDialog && this.content && this.shouldShowTrackingStatusSection()) {
      SourceDialogScaffold({
        themeState: this.themeState,
        onMaskTap: () => {
          if (!this.isTrackingBusy) {
            this.closeTrackingSettingsDialog();
          }
        },
        dialogWidth: '90%',
        maxWidth: 620,
        contentPadding: 24,
        zIndexValue: 121,
        useMaskBlur: true
      }) {
        Column({ space: 20 }) {
          Row() {
            Text(this.trackingRule !== null ? '调整更新提醒' : '开启更新提醒')
              .fontSize(20)
              .fontWeight(FontWeight.Medium)
              .fontFamily(this.appFontFamily)
              .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_primary', this.themeState.currentTheme))
            Blank()
            Button() {
              SymbolGlyph($r('sys.symbol.xmark'))
                .fontSize(18)
                .fontColor([ThemeAwareHelper.getTestManagementThemedColor('text_secondary', this.themeState.currentTheme)])
            }
            .width(32)
            .height(32)
            .backgroundColor(Color.Transparent)
            .enabled(!this.isTrackingBusy)
            .onClick(() => {
              this.closeTrackingSettingsDialog();
            })
          }
          .width('100%')

          this.buildTrackingSettingsOverviewCard()

          Row({ space: 8 }) {
            this.buildTrackingSettingsTabButton('基础', $r('sys.symbol.bell'), 0)
            this.buildTrackingSettingsTabButton('筛选', $r('sys.symbol.funnel'), 1)
            this.buildTrackingSettingsTabButton('操作', $r('sys.symbol.gearshape'), 2)
          }
          .width('100%')
          .padding(4)
          .backgroundColor(ThemeAwareHelper.getTestManagementThemedColor('comp_background_tertiary', this.themeState.currentTheme))
          .borderRadius(18)

          Scroll() {
            Column({ space: 12 }) {
              if (this.trackingSettingsActiveTab === 0) {
                this.buildTrackingBasicSettingsTab()
              } else if (this.trackingSettingsActiveTab === 1) {
                this.buildTrackingFilterSettingsTab()
              } else {
                this.buildTrackingActionSettingsTab()
              }
            }
            .width('100%')
            .alignItems(HorizontalAlign.Start)
            .animation({ duration: 220, curve: Curve.EaseOut })
          }
          .width('100%')
          .constraintSize({ maxHeight: 420 })
          .scrollBar(BarState.Auto)
          .edgeEffect(EdgeEffect.Spring)

          this.buildTrackingSettingsDialogFooter()
        }
        .width('100%')
      }
    }
  }


  build() {
    this.buildTrackingSettingsDialog()
  }
}
