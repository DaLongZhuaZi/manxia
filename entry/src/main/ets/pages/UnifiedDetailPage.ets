import { SafeFileUtils } from '../Utils/SafeFileUtils';
import { SafeUtils } from '../Utils/SafeUtils';
// 文件路径: entry/src/main/ets/pages/UnifiedDetailPage.ets
/**
 * 统一详情页
 * 支持显示漫画、电子书、小说的详细信息
 * 通过适配器模式将不同类型数据转换为统一展示格式
 */

import { HdsNavDestination, HdsNavDestinationAttribute, ScrollEffectType } from '@kit.UIDesignKit';
import { LengthMetrics, promptAction, curves } from '@kit.ArkUI';
import { common, Want } from '@kit.AbilityKit';
import { pasteboard } from '@kit.BasicServicesKit';
import { photoAccessHelper } from '@kit.MediaLibraryKit';
import { fileIo as fs, fileUri } from '@kit.CoreFileKit';
import { http } from '@kit.NetworkKit';
import { systemShare } from '@kit.ShareKit';
import { uniformTypeDescriptor as utd, preferences } from '@kit.ArkData';
import { util } from '@kit.ArkTS';
import { logger } from '../Utils/Logger';
import { WindowManager, DisplayMode } from '../Utils/WindowManager';
import { PageWindowCoordinator } from '../Utils/PageWindowCoordinator';
import { PageLifecycleManager } from '../Framework/Lifecycle';
import { ThemeAwareState, ThemeAwareHelper } from '../Framework/Components/ThemeAware';
import { ThemeManager, ThemeType } from '../Framework/Managers/ThemeManager';
import { FontAwareHelper, FontAwareState } from '../Framework/Components/FontAware';
import { DeviceAdaptationManager, DeviceInfo, DeviceChangeListener, Breakpoint } from '../Framework/Managers/DeviceAdaptationManager';
import { ResponsiveLayoutHelper } from '../Framework/Utils/ResponsiveLayout';
import { ContentFilterManager } from '../Framework/Managers/ContentFilterManager';
import { SettingsManager, SettingKeys } from '../Framework/Managers/SettingsManager';
import CookieManager from '../Framework/Managers/CookieManager';
import {
  ContentTrackingCardCallbacks,
  ContentTrackingCardState,
  ContentTrackingStatusCard
} from '../components/ContentTrackingStatusCard';
import {
  getSubscriptionManager,
  SubscriptionIntervalUnit,
  SubscriptionManager
} from '../Framework/Subscription';

import {
  UnifiedContent,
  UnifiedChapter,
  UnifiedContentType,
  UnifiedReadStatus,
  UnifiedDetailPageParams,
  RemoteVerificationInfo,
  UnifiedContentActions,
  ChapterFilterType,
  ChapterSortOrder,
  ChapterDisplayMode,
  OriginalBookInfo
} from '../Models/UnifiedContentModels';

import {
  UnifiedContentAdapterFactory,
  MangaAdapter,
  EBookAdapter,
  NovelAdapter,
  AdapterOptions
} from '../Framework/Adapters/UnifiedContentAdapter';
import {
  inspectEBookImagePageSignals,
  resolveEBookReaderRouteName
} from '../Framework/Adapters/EBookImageReaderAdapter';
import { LOCAL_TXT_NOVEL_SOURCE_ID, buildLocalTextNovelBookId, buildNovelReaderParamsFromTxtEBook } from '../Framework/Adapters/LocalTextNovelAdapter';

// 重复检测导入
import { DuplicateDetectionService } from '../Framework/DuplicateDetection/DuplicateDetectionService';
import { DuplicateCheckContentType, DuplicateMatchItem } from '../Framework/DuplicateDetection/DuplicateDetectionModels';
import { DuplicateDetectionDialog } from '../Framework/Components/DuplicateDetectionDialog';
import { OnlineEBookDetailPageParams } from './OnlineEBookDetailPage';

// 数据管理器导入
import { DataManager, ComicInfo, ChapterInfo, PageInfo, OnlineChapterInfo, OnlineComicInfo } from '../Framework/Data/DataManager';
import { DatabaseRecord } from '../Framework/Database/DatabaseTypes';
import { DataService } from '../Framework/Services/DataService';
import { MangaDetailLoader, MangaDetailLoadParams, MangaDetailLoadResult, MangaLoadProgressCallback, ChapterProgressInfo } from '../Framework/Loaders/MangaDetailLoader';
import { MangaIdentityResolver, MangaIdentityResolveResult } from '../Framework/Reader/MangaIdentityResolver';
import webview from '@ohos.web.webview';
import { EBookDataManager } from '../Framework/Data/EBookDataManager';
import { SourceManager, SourceInfo } from '../Framework/Source/SourceManager';
import { RemoteLibraryMangaBridge } from '../Framework/Source/RemoteLibraryMangaBridge';
import { getRemoteLibraryShelfManager, RemoteLibraryShelfManager } from '../Framework/Source/RemoteLibraryShelfManager';
import { MangaSourceEngine, EngineConfig } from '../Framework/WebView/MangaSourceEngine';
import { WebViewSourceManager } from '../Framework/WebView/WebViewSourceManager';
import { WebViewAuthManager } from '../Framework/WebView/WebViewAuthManager';
import { AntiCrawlerConfig, PageRequestHeader } from '../Framework/WebView/MangaSourceTypes';
import { getNovelSourceManager } from '../Framework/Novel/NovelSourceManager';
import { getNovelDataManager } from '../Framework/Novel/NovelDataManager';
import { getNovelChapterCacheManager } from '../Framework/Novel/NovelChapterCacheManager';
import { getNovelContentProcessor } from '../Framework/Novel/NovelContentProcessor';
import { getNovelTxtTocRuleManager, TxtTocRule } from '../Framework/Novel/NovelTxtTocRuleManager';
import { NovelReplaceRuleManager, ReplaceScope, ReplaceRule } from '../Framework/Novel/NovelReplaceRuleManager';
import { getLegadoMangaSourceBridge, LegadoMangaPageResult } from '../Framework/Novel/LegadoMangaSourceBridge';

import { getCacheStatusService, CacheStatusService, ContentCacheStats, CacheContentType } from '../Framework/Services/CacheStatusService';
import { getUnifiedDownloadManager, UnifiedDownloadManager, UnifiedDownloadType, UnifiedTaskStatus, UnifiedDownloadTask, UnifiedDownloadCallback, MangaChapterDownloadItem, PageListFetcher, DownloadPageItem } from '../Framework/Download/UnifiedDownloadManager';
import { CoverCacheManager } from '../Framework/Cache/CoverCacheManager';
import { getCoverImageManager, CoverImageManager } from '../Framework/Image/CoverImageManager';
import { OnlineLoadOptions, RequestHeaders } from '../Framework/Cache/OnlineImageLoader';
import { LibraryCoverManager, LibraryCoverType } from '../Framework/Storage/LibraryCoverManager';
import { image } from '@kit.ImageKit';
import { LabelUtils } from '../Utils/LabelUtils';
import { getNovelCoverGenerator, NovelCoverGenerator } from '../Framework/Novel/NovelCoverGenerator';
import { ZLibraryReaderParams } from './ZLibraryReaderPage';
import { AvifImage } from '../components/AvifImage';
import {
  eventBus,
  GameEvent,
  IEventPayload,
  CoverChangedPayload,
  BasePayload,
  MangaDeletedPayload,
  MangaFavoriteChangedPayload,
  ReadAloudCacheUpdatedPayload,
  MangaCacheUpdatedPayload
} from '../Framework/EventBus';
import { getTypeShelfManager, TypeShelfManager, TypeShelf, ShelfType, ShelfContentType } from '../Framework/Data/TypeShelfManager';
import { BookshelfCategoryManager, ContentType, CategoryItem } from '../Framework/Data/BookshelfCategoryManager';
import { GlobalSearchPageParams } from './GlobalSearchPage';
import { GlobalSearchService, UnifiedSearchItem } from '../Framework/Services/GlobalSearchService';
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
} from '../Framework/ReadAloud/RemoteReadAloudCacheService';
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
} from '../Models/TextReaderModels';

// 模型导入
import { Manga, MangaChapter, MangaPage, ReadingProgress, ReadingSettings, MangaBookmark, MangaMetadata, ImageSourceType, DEFAULT_READING_SETTINGS } from '../Models/MangaModels';
import { DownloadStatus, MangaStatus, ReadingStatus } from '../Framework/Types/StatusEnums';
import { EBook, EBookChapter, EBookFormat, EBookStatus, EBookMetadata } from '../Models/EBookModels';
import { LegadoBook, LegadoChapter, LegadoBookSource, LegadoBookSourceType } from '../Framework/Novel/LegadoSourceTypes';
import { NovelBook, NovelReadStatus, NovelSearchResult } from '../Models/NovelModels';

// 阅读器参数导入
import { MangaReaderPageParams, MangaReaderContentType } from './MangaReaderPage';
import { openMangaReaderInIsolatedAbility } from '../Framework/Reader/MangaReaderAbilityLauncher';
import { MangaSettingsPageParams } from './MangaSettingsPage';
import { EBookSettingsPageParams } from './EBookDetailPage';
import { EBookReaderParams } from './EBookReaderRouteTypes';
import { NovelReaderPageParams } from './NovelBookshelfPage';
import { openEBookReaderRouterPage } from '../Framework/Adapters/EBookReaderRouteNavigator';
import { openEBookReaderInIsolatedAbility } from '../Framework/Reader/EBookReaderAbilityLauncher';
import { openNovelReaderInIsolatedAbility } from '../Framework/Reader/NovelReaderAbilityLauncher';
import { openReadAloudPlayerInIsolatedAbility } from '../Framework/ReadAloud/ReadAloudPlayerAbilityLauncher';

import { startBookOpenTransitionWithComponentId, EBookBackgroundSettings } from '../components/BookTransitionOverlay';
import { AppGuideOverlay, GuideHighlightRect } from '../Framework/Components/AppGuideOverlay';
import { ensureGuideAnchorVisibleInScroller, resolveGuideHighlightRectInRoot } from '../Framework/Components/AppGuideSupport';
import { AppGuideManager, AppGuidePageId, AppGuideStep } from '../Framework/Managers/AppGuideManager';
import { SettingsGlassStyleHelper } from './settings/SettingsGlassStyleHelper';
import { SettingsPageSurfaceManager, SettingsPageSurfaceStyle } from './settings/SettingsPageSurfaceManager';
import { ReadAloudCacheDialogComponent } from '../Framework/Components/ReadAloudCacheDialogComponent';
import { TrackingSettingsDialogComponent, UnifiedDetailTrackingTargetInfo } from '../Framework/Components/TrackingSettingsDialogComponent';
import { NovelSettingsDialogComponent } from '../Framework/Components/NovelSettingsDialogComponent';
import { DownloadDialogComponent } from '../Framework/Components/DownloadDialogComponent';
import { ShareLinkDialogComponent } from '../Framework/Components/ShareLinkDialogComponent';
import { ChangeSourceDialogComponent } from '../Framework/Components/ChangeSourceDialogComponent';
import { CacheConfirmDialogComponent, CacheConfirmConfig } from '../Framework/Components/CacheConfirmDialogComponent';
import { GenerateCoverDialogComponent } from '../Framework/Components/GenerateCoverDialogComponent';
import { AddToShelfDialogComponent } from '../Framework/Components/AddToShelfDialogComponent';
import { ReplaceBookDialogComponent } from '../Framework/Components/ReplaceBookDialogComponent';

const TAG = 'UnifiedDetailPage';
const TITLE_BAR_HEIGHT = 56;
const COVER_HEIGHT = 200;
const COVER_WIDTH = 140;
const PHOTOS18_ORIGIN = 'https://www.photos18.com';
const PHOTOS18_COVER_UA = 'Mozilla/5.0 (Linux; Android 13; Pixel 7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Mobile Safari/537.36';
const NOVEL_SETTINGS_STORE = 'novel_settings';
const NOVEL_SETTING_ENABLE_DIRECTORY_PARSING = 'enableNovelDirectoryParsing';
const NOVEL_SETTING_ENABLE_REPLACE_RULES = 'enableNovelReplaceRules';
const NOVEL_BOOK_RULE_SETTINGS_STORE = 'novel_book_rule_settings';
const NOVEL_BOOK_TOC_RULE_IDS_PREFIX = 'book_toc_rule_ids_';
const NOVEL_BOOK_REPLACE_RULE_IDS_PREFIX = 'book_replace_rule_ids_';

// ==================== 智能推荐栏常量 ====================
const RECOMMEND_CARD_COVER_W = 90;   // 推荐卡片封面宽度
const RECOMMEND_CARD_COVER_H = 130;  // 推荐卡片封面高度
const RECOMMEND_MAX_COUNT = 8;       // 最多显示推荐数量
const RECOMMEND_MIN_SCORE = 15;      // 本地推荐最低相关度阈值

// ==================== 同书架内容常量 ====================
const SHELF_CONTENT_CARD_COVER_W = 90;   // 同书架卡片封面宽度
const SHELF_CONTENT_CARD_COVER_H = 130;  // 同书架卡片封面高度
const SHELF_CONTENT_MAX_COUNT = 20;      // 最多显示同书架内容数量
const SHELF_CONTENT_CANDIDATE_SCAN_COUNT = 60;

/**
 * 同书架内容筛选类型
 */
type ShelfContentFilterType = 'all' | 'manga' | 'novel' | 'ebook';

/**
 * 同书架内容项
 */
interface ShelfContentItem {
  id: string;
  title: string;
  coverUrl: string;
  contentType: UnifiedContentType;
  /** 导航时使用的内容ID */
  navContentId: string;
  /** 导航时使用的图源ID（在线内容） */
  navSourceId?: string;
}

/**
 * 同书架筛选标签
 */
interface ShelfFilterTab {
  key: ShelfContentFilterType;
  label: string;
}

/**
 * 智能推荐内容项
 */
interface RecommendationItem {
  id: string;
  title: string;
  coverUrl: string;
  contentType: UnifiedContentType;
  isFavorited: boolean;
  isLocal: boolean;
  sourceId?: string;
  sourceName?: string;
  score: number;
  /** 导航时使用的内容ID */
  navContentId: string;
  /** 导航时使用的图源ID（在线内容） */
  navSourceId?: string;
}

interface TagChipItem {
  id: string;
  rawLabel: string;
  isGenre: boolean;
}

interface OnlineEBookDetailRecord {
  id?: string;
  title?: string;
  author?: string;
  description?: string;
  cover?: string;
  categories?: string;
  tags?: string;
  readerUrl?: string;
}

interface OnlineEBookExtendedData {
  sourceId?: string;
  sourceName?: string;
  sourcePkg?: string;
  onlineReaderUrl?: string;
  detailRequestValue?: string;
  verificationStatus?: string;
  verificationMessage?: string;
  verificationPageUrl?: string;
  verificationPageTitle?: string;
  verificationCooldownText?: string;
  verificationCooldownSeconds?: number;
  verificationCanRetry?: boolean;
  verificationAttempt?: number;
  verificationUpdatedAt?: number;
}

interface OnlineEBookWorkflowAction {
  type?: string;
  url?: string;
}

interface OnlineEBookWorkflowDefinition {
  actions?: OnlineEBookWorkflowAction[];
}

interface OnlineEBookWorkflowCollection {
  getBookDetail?: OnlineEBookWorkflowDefinition;
}

interface OnlineEBookSourceConfig {
  workflows?: OnlineEBookWorkflowCollection;
}

interface OnlineEBookVerificationState {
  url: string;
  title: string;
  isVerifyEntry: boolean;
  cooldownText: string;
  canRetryVerification: boolean;
}

interface DialogResult {
  index: number;
}

interface UnifiedDeleteTarget {
  contentType: UnifiedContentType;
  contentId: string;
  title: string;
  contentTypeLabel: string;
  isRemoteProviderManga: boolean;
}

@Component
export struct UnifiedDetailPage {
  @State pathStack: NavPathStack = new NavPathStack();
  @State themeState: ThemeAwareState = new ThemeAwareState();
  @State fontState: FontAwareState = new FontAwareState();
  @StorageLink('appFontFamily') appFontFamily: string = 'HarmonyOS Sans';
  private componentId: string = `UnifiedDetailPage_${Date.now()}`;
  private scroller: Scroller = new Scroller();

  // 沉浸式显示状态
  @StorageProp('statusBarHeight') statusBarHeight: number = 0;
  @StorageProp('navigationBarHeight') navigationBarHeight: number = 0;

  // 响应式布局
  private deviceManager: DeviceAdaptationManager = DeviceAdaptationManager.getInstance();
  private deviceChangeListener: DeviceChangeListener | null = null;
  @State responsive_contentPadding: number = 16;
  @State responsive_maxContentWidth: number = 1200;
  @State responsive_isLandscape: boolean = false;

  // 页面参数
  private pageParams: UnifiedDetailPageParams | null = null;

  // 统一内容数据
  @State content: UnifiedContent | null = null;
  @State resolvedDisplaySourceName: string = '';
  @State isLoading: boolean = true;
  @State errorMessage: string = '';
  
  // 分阶段加载状态
  @State isBasicInfoLoaded: boolean = false;  // 基本信息是否加载完成
  @State isCoverLoading: boolean = true;      // 封面是否正在加载
  @State isChaptersLoading: boolean = true;   // 章节是否正在加载
  @State isPagesPreloading: boolean = false;  // 页面是否正在预加载
  @State chaptersLoadProgress: string = '';   // 章节加载进度文本
  
  // 下拉刷新状态
  @State isRefreshing: boolean = false;       // 是否正在刷新
  @State refreshProgress: string = '';        // 刷新进度文本
  @State onlineEBookVerificationInfo: RemoteVerificationInfo | null = null;
  
  // 重新获取状态（在线漫画）
  @State isRefetchingManga: boolean = false;  // 是否正在重新获取漫画信息
  @State isRefetchingCover: boolean = false;  // 是否正在重新获取封面
  
  // 封面预览状态
  @State showCoverPreview: boolean = false;   // 是否显示封面全屏预览
  @State coverPreviewOpacity: number = 0;     // 封面预览背景透明度
  @State coverPreviewScale: number = 0.3;     // 封面预览缩放比例
  @State isSavingCover: boolean = false;      // 是否正在保存封面
  
  // 在线漫画封面缓存
  @State localCoverPath: string = '';         // 本地缓存的封面路径
  @State coverPixelMap: image.PixelMap | null = null;  // 封面 PixelMap（优先使用）
  private coverPixelMapOwned: boolean = false;         // 是否拥有 PixelMap 的所有权（需要负责释放）
  
  // 漫画章节进度数据
  @State chapterProgressMap: Map<string, ChapterProgressInfo> = new Map();
  
  // 缓存状态服务和数据
  private cacheStatusService: CacheStatusService = getCacheStatusService();
  private unifiedDownloadManager: UnifiedDownloadManager = getUnifiedDownloadManager();
  private remoteReadAloudCacheService = getRemoteReadAloudCacheService();
  private appGuideManager: AppGuideManager = AppGuideManager.getInstance();
  @State cacheStats: ContentCacheStats | null = null;
  @State isCacheStatsLoading: boolean = false;
  @State showCacheStatusCard: boolean = false;  // 控制是否显示缓存卡片
  @State isDownloading: boolean = false;        // 是否正在下载

  // 听书缓存状态（已提取至 ReadAloudCacheDialogComponent）
  @State readAloudCacheLoadSignal: number = 0;
  @State readAloudCacheSummary: RemoteReadAloudCacheBookSummary | null = null;

  // 应用引导状态
  @State private appGuideStep: AppGuideStep | null = null;
  @State private appGuideHighlightRect: GuideHighlightRect | null = null;

  private onMangaCacheUpdated: (payload: IEventPayload) => void = (payload: IEventPayload): void => {
    const cachePayload = payload as MangaCacheUpdatedPayload;
    if (!this.content || !this.isOnlineManga() || cachePayload.mangaId !== this.content.id) {
      return;
    }
    void this.loadCacheStatus();
    logger.info(TAG, `收到漫画缓存更新事件，刷新详情页缓存状态: chapterId=${cachePayload.chapterId}, reason=${cachePayload.reason}`);
  };
  
  // 下载对话框状态（已提取至 DownloadDialogComponent）
  @State downloadDialogLoadSignal: number = 0;

  // 分享链接对话框状态
  @State shareDialogLoadSignal: number = 0;

  // 小说设置对话框状态（已提取至 NovelSettingsDialogComponent）
  @State novelSettingsLoadSignal: number = 0;
  
  // 下载进度实时显示状态
  @State downloadProgressCurrent: number = 0;           // 当前下载进度
  @State downloadProgressTotal: number = 0;             // 总下载数量
  @State downloadCurrentChapterTitle: string = '';      // 当前正在下载的章节标题
  private downloadCallbackRegistered: boolean = false;  // 是否已注册下载回调
  private downloadCallback: UnifiedDownloadCallback | null = null;
  private cacheStatusRefreshTimer: number = -1;
  
  // 换源对话框状态（已提取至 ChangeSourceDialogComponent）
  @State changeSourceDialogLoadSignal: number = 0;
  
  // 换源替换相关状态
  @State isFromChangeSource: boolean = false;           // 是否来自换源
  @State originalBookInfo: OriginalBookInfo | null = null;  // 原书信息
  @State replaceBookDialogLoadSignal: number = 0;
  @State matchedChapterIndex: number = -1;              // 匹配到的新书章节索引

  // UI状态
  @State isFavorite: boolean = false;
  @State showFullDescription: boolean = false;
  @State expandedTagChipIds: string[] = [];
  @State descriptionSelectedText: string = '';  // 简介中当前选中的文本
  @State showChapterPanel: boolean = false;
  @State chapterFilter: ChapterFilterType = ChapterFilterType.ALL;
  @State chapterSortOrder: ChapterSortOrder = ChapterSortOrder.ASCENDING;
  @State chapterDisplayMode: ChapterDisplayMode = ChapterDisplayMode.LIST;
  
  // 书架相关状态
  private typeShelfManager: TypeShelfManager = getTypeShelfManager();
  private remoteLibraryShelfManager: RemoteLibraryShelfManager = getRemoteLibraryShelfManager();
  @State isInShelf: boolean = false;                    // 是否已在书架中
  @State currentShelfName: string = '';                 // 当前所在书架名称
  @State currentShelfId: string = '';                   // 当前所在书架ID
  @State addToShelfDialogLoadSignal: number = 0;
  @State availableCustomShelves: TypeShelf[] = [];      // 可用的自定义书架列表（传递给组件）
  @State isShelfActionPending: boolean = false;         // 书架操作进行中（防重复点击）
  @State isDeletingContent: boolean = false;            // 内容删除进行中（防重复点击）

  // 重复检测状态
  @State duplicateDetectionMatches: DuplicateMatchItem[] = [];
  @State duplicateDetectionLoadSignal: number = 0;
  private pendingFavoriteAction: (() => Promise<void>) | null = null;

  // 内容跟踪状态（已提取至 TrackingSettingsDialogComponent）
  @State trackingLoadSignal: number = 0;
  @State trackingCardState: ContentTrackingCardState | null = null;
  @State trackingCardCallbacks: ContentTrackingCardCallbacks | null = null;
  
  // 同书架内容状态
  @State shelfContentItems: ShelfContentItem[] = [];    // 同书架的其他内容
  @State isLoadingShelfContent: boolean = false;        // 是否正在加载同书架内容
  @State shelfContentFilter: ShelfContentFilterType = 'all';  // 内容类型筛选
  @State isChapterListExpanded: boolean = true;         // 章节列表区域是否展开
  @State isShelfContentExpanded: boolean = true;        // 同书架内容是否展开
  @State isRecommendationsExpanded: boolean = true;     // 相关推荐是否展开

  // 数据管理器
  private dataManager: DataManager = DataManager.getInstance();
  private ebookDataManager: EBookDataManager = EBookDataManager.getInstance();
  private novelSourceManager = getNovelSourceManager();
  private novelDataManager = getNovelDataManager();
  private subscriptionManager: SubscriptionManager = getSubscriptionManager();
  private novelCacheManager = getNovelChapterCacheManager();
  private coverGenerator = getNovelCoverGenerator();

  // 生成封面状态
  @State isGeneratingCover: boolean = false;
  @State generateCoverDialogLoadSignal: number = 0;
  @State coverRefreshKey: number = 0;

  @State cacheConfirmDialogLoadSignal: number = 0;
  @State cacheConfirmConfig: CacheConfirmConfig = { title: '', message: '', actionLabel: '', actionKind: 'danger', pendingAction: '' };

  // 封面生成器常量
  static readonly COVER_WIDTH = 400;
  static readonly COVER_HEIGHT = 600;
  static readonly TITLE_AREA_TOP_PERCENT = 0.130;
  static readonly TITLE_AREA_BOTTOM_PERCENT = 0.345;
  static readonly TITLE_AREA_LEFT_PERCENT = 0.110;
  static readonly TITLE_AREA_RIGHT_PERCENT = 0.895;
  
  // 漫画详情加载器
  private mangaDetailLoader: MangaDetailLoader = MangaDetailLoader.getInstance();
  // 已解析的图源信息（从 SourceManager 查找，用于生成稳定链接等）
  private resolvedSourceName: string = '';
  private resolvedSourcePkg: string = '';
  private webViewController: webview.WebviewController = new webview.WebviewController();
  private webViewManager: WebViewSourceManager = WebViewSourceManager.getInstance();
  @State private webViewControllerAttached: boolean = false;
  private pendingInitialContentLoad: boolean = false;
  private initialContentLoadTriggered: boolean = false;
  
  /**
   * 生成小说缓存用的bookId
   * 格式与NovelReaderPage保持一致：${sourceId}_${encodeURIComponent(bookUrl)}
   */
  private getNovelCacheBookId(sourceId: string, bookUrl: string): string {
    return `${sourceId}_${encodeURIComponent(bookUrl)}`;
  }

  private normalizeTrackingText(value: string | undefined | null): string {
    if (value === undefined || value === null || typeof value !== 'string') {
      return '';
    }
    return value.trim();
  }

  private loadGlobalChapterSortOrderPreference(): void {
    const storedValue = this.settingsManager.getString(
      SettingKeys.GLOBAL_UNIFIED_DETAIL_CHAPTER_SORT_ORDER,
      ChapterSortOrder.ASCENDING
    );
    if (storedValue === ChapterSortOrder.DESCENDING) {
      this.chapterSortOrder = ChapterSortOrder.DESCENDING;
      return;
    }
    this.chapterSortOrder = ChapterSortOrder.ASCENDING;
  }

  private persistGlobalChapterSortOrderPreference(sortOrder: ChapterSortOrder): void {
    void this.settingsManager.setString(SettingKeys.GLOBAL_UNIFIED_DETAIL_CHAPTER_SORT_ORDER, sortOrder);
  }

  private toggleGlobalChapterSortOrder(): void {
    this.chapterSortOrder = this.chapterSortOrder === ChapterSortOrder.ASCENDING
      ? ChapterSortOrder.DESCENDING
      : ChapterSortOrder.ASCENDING;
    this.persistGlobalChapterSortOrderPreference(this.chapterSortOrder);
  }

  private normalizeDisplaySourceText(value: string | undefined | null): string {
    const rawText: string = this.normalizeTrackingText(value);
    if (rawText.length <= 0) {
      return '';
    }
    let normalized: string = this.stripHtmlTags(rawText).trim();
    if (normalized.length >= 2 &&
      ((normalized.startsWith('"') && normalized.endsWith('"')) ||
        (normalized.startsWith("'") && normalized.endsWith("'")))) {
      normalized = normalized.substring(1, normalized.length - 1).trim();
    }
    normalized = this.decodeEscapedUnicodeText(normalized);
    normalized = this.decodePercentEncodedText(normalized);
    normalized = this.decodeMojibakeSourceText(normalized);
    return normalized.trim();
  }

  private decodeEscapedUnicodeText(value: string): string {
    if (value.indexOf('\\u') < 0 && value.indexOf('\\x') < 0) {
      return value;
    }
    try {
      return value
        .replace(/\\u([0-9a-fA-F]{4})/g, (_match: string, hex: string): string => {
          const parsed: number = parseInt(hex, 16);
          return Number.isFinite(parsed) && parsed > 0 ? String.fromCharCode(parsed) : '';
        })
        .replace(/\\x([0-9a-fA-F]{2})/g, (_match: string, hex: string): string => {
          const parsed: number = parseInt(hex, 16);
          return Number.isFinite(parsed) && parsed > 0 ? String.fromCharCode(parsed) : '';
        });
    } catch (error) {
      logger.debug(TAG, `解码来源Unicode转义失败: ${String(error)}`);
      return value;
    }
  }

  private decodePercentEncodedText(value: string): string {
    if (value.indexOf('%') < 0) {
      return value;
    }
    try {
      return decodeURIComponent(value.replace(/\+/g, '%20'));
    } catch (error) {
      logger.debug(TAG, `解码来源URL编码失败: ${String(error)}`);
      return value;
    }
  }

  private containsMojibakeMarker(value: string): boolean {
    const markers: string[] = ['Ã', 'Â', 'Ä', 'Å', 'æ', 'è', 'ç', 'å', 'ä', 'é', 'ï¿½'];
    for (let i = 0; i < markers.length; i++) {
      if (value.indexOf(markers[i]) >= 0) {
        return true;
      }
    }
    return false;
  }

  private countCjkCharacters(value: string): number {
    let count: number = 0;
    for (let i = 0; i < value.length; i++) {
      const code: number = value.charCodeAt(i);
      if ((code >= 0x3400 && code <= 0x9FFF) || (code >= 0xF900 && code <= 0xFAFF)) {
        count++;
      }
    }
    return count;
  }

  private decodeMojibakeSourceText(value: string): string {
    if (!this.containsMojibakeMarker(value)) {
      return value;
    }
    try {
      const bytes: Uint8Array = new Uint8Array(value.length);
      for (let i = 0; i < value.length; i++) {
        const code: number = value.charCodeAt(i);
        if (code > 255) {
          return value;
        }
        bytes[i] = code;
      }
      const decoder: util.TextDecoder = util.TextDecoder.create('utf-8');
      const decoded: string = decoder.decodeToString(bytes).trim();
      if (decoded.length > 0 && this.countCjkCharacters(decoded) > this.countCjkCharacters(value)) {
        return decoded;
      }
      return value;
    } catch (error) {
      logger.debug(TAG, `修复来源乱码失败: ${String(error)}`);
      return value;
    }
  }

  private isLikelySourceIdentifier(value: string): boolean {
    const normalized: string = value.trim();
    if (normalized.length <= 0) {
      return false;
    }
    const lower: string = normalized.toLowerCase();
    if (lower.startsWith('http://') || lower.startsWith('https://') || lower.indexOf('://') >= 0) {
      return true;
    }
    if (lower.startsWith('id_')) {
      return true;
    }
    if (lower.startsWith('com.') && lower.indexOf('.extension.') >= 0) {
      return true;
    }
    return /^[a-z0-9_-]+(\.[a-z0-9_-]+){2,}$/i.test(normalized);
  }

  private findSourceInfoByIdentity(
    sources: SourceInfo[],
    sourceId: string,
    sourcePkg: string,
    sourceName: string
  ): SourceInfo | null {
    const numericSourceId: number = Number(sourceId);
    if (Number.isFinite(numericSourceId) && numericSourceId > 0) {
      for (let i = 0; i < sources.length; i++) {
        if (sources[i].id === numericSourceId) {
          return sources[i];
        }
      }
    }

    const normalizedSourceId: string = sourceId.trim();
    if (normalizedSourceId.length > 0 && !Number.isFinite(numericSourceId)) {
      for (let i = 0; i < sources.length; i++) {
        const pkg: string = sources[i].pkg || '';
        if (pkg === normalizedSourceId || sources[i].name === normalizedSourceId) {
          return sources[i];
        }
      }
    }

    const normalizedPkg: string = sourcePkg.trim();
    if (normalizedPkg.length > 0) {
      for (let i = 0; i < sources.length; i++) {
        const pkg: string = sources[i].pkg || '';
        if (pkg === normalizedPkg) {
          return sources[i];
        }
      }
    }

    const normalizedName: string = this.normalizeDisplaySourceText(sourceName);
    if (normalizedName.length > 0) {
      for (let i = 0; i < sources.length; i++) {
        if (sources[i].name === normalizedName || sources[i].pkg === normalizedName) {
          return sources[i];
        }
      }
    }
    return null;
  }

  private async resolveMangaSourceDisplayName(
    sourceId: string | undefined | null,
    sourcePkg: string | undefined | null,
    sourceName: string | undefined | null
  ): Promise<string> {
    const normalizedSourceId: string = this.normalizeTrackingText(sourceId);
    const normalizedSourcePkg: string = this.normalizeTrackingText(sourcePkg);
    const normalizedSourceName: string = this.normalizeDisplaySourceText(sourceName);
    try {
      const sources: SourceInfo[] = await this.sourceManager.getAllSources();
      const sourceInfo: SourceInfo | null = this.findSourceInfoByIdentity(
        sources,
        normalizedSourceId,
        normalizedSourcePkg,
        normalizedSourceName
      );
      if (sourceInfo !== null) {
        this.resolvedSourceName = this.normalizeDisplaySourceText(sourceInfo.name);
        this.resolvedSourcePkg = sourceInfo.pkg || this.resolvedSourcePkg;
        return this.resolvedSourceName;
      }
    } catch (error) {
      logger.warn(TAG, `解析图源显示名称失败: ${String(error)}`);
    }
    return this.isLikelySourceIdentifier(normalizedSourceName) ? '' : normalizedSourceName;
  }

  private shouldMatchNovelSourceHost(bookUrl: string): boolean {
    const normalizedBookUrl: string = bookUrl.trim().toLowerCase();
    return normalizedBookUrl.startsWith('http://') || normalizedBookUrl.startsWith('https://');
  }

  private resolveNovelSourceById(
    sourceId: string | undefined | null,
    bookUrl: string | undefined | null
  ): LegadoBookSource | null {
    const normalizedSourceId: string = this.normalizeTrackingText(sourceId);
    if (normalizedSourceId.length <= 0) {
      return null;
    }
    const normalizedBookUrl: string = this.normalizeTrackingText(bookUrl);
    const shouldMatchHost: boolean = this.shouldMatchNovelSourceHost(normalizedBookUrl);
    const lookupCandidates: string[] = this.buildNovelSourceLookupCandidates(normalizedSourceId);
    for (let i = 0; i < lookupCandidates.length; i++) {
      const source: LegadoBookSource | null = this.novelSourceManager.getSource(lookupCandidates[i]);
      if (source === null) {
        continue;
      }
      if (shouldMatchHost) {
        const sourceUrl: string = this.normalizeTrackingText(source.bookSourceUrl);
        if (!this.areNovelSourceHostsCompatible(sourceUrl, normalizedBookUrl)) {
          continue;
        }
      }
      return source;
    }
    return null;
  }

  private getNovelSourceTypeById(
    sourceId: string | undefined | null,
    bookUrl: string | undefined | null
  ): LegadoBookSourceType {
    const source: LegadoBookSource | null = this.resolveNovelSourceById(sourceId, bookUrl);
    if (source === null) {
      return LegadoBookSourceType.TEXT;
    }
    return source.bookSourceType;
  }

  private resolveNovelSourceDisplayName(
    sourceId: string | undefined | null,
    sourceName: string | undefined | null,
    bookUrl: string | undefined | null
  ): string {
    const source: LegadoBookSource | null = this.resolveNovelSourceById(sourceId, bookUrl);
    if (source !== null) {
      const sourceBookName: string = this.normalizeDisplaySourceText(source.bookSourceName);
      if (sourceBookName.length > 0) {
        return sourceBookName;
      }
    }

    const normalizedSourceName: string = this.normalizeDisplaySourceText(sourceName);
    return this.isLikelySourceIdentifier(normalizedSourceName) ? '' : normalizedSourceName;
  }

  private async syncCurrentSourceDisplayName(): Promise<void> {
    if (!this.content) {
      this.resolvedDisplaySourceName = '';
      return;
    }

    let displayName: string = '';
    if (this.content.contentType === UnifiedContentType.MANGA) {
      displayName = await this.resolveMangaSourceDisplayName(
        this.content.sourceId || this.pageParams?.sourceId,
        this.content.sourcePkg || this.pageParams?.sourcePkg,
        this.content.sourceName || this.pageParams?.sourceName
      );
    } else if (this.content.contentType === UnifiedContentType.EBOOK) {
      if (!this.content.isLocal || this.hasOnlineEBookExtendedData(this.content.filePath)) {
        const extendedData: OnlineEBookExtendedData | null = this.getOnlineEBookExtendedData(this.content.filePath);
        displayName = await this.resolveMangaSourceDisplayName(
          this.content.sourceId || extendedData?.sourceId || this.pageParams?.sourceId,
          this.content.sourcePkg || extendedData?.sourcePkg || this.pageParams?.sourcePkg,
          this.content.sourceName || extendedData?.sourceName || this.pageParams?.sourceName
        );
      }
    } else if (this.content.contentType === UnifiedContentType.NOVEL) {
      displayName = this.resolveNovelSourceDisplayName(
        this.content.sourceId || this.pageParams?.sourceId,
        this.content.sourceName || this.pageParams?.sourceName,
        this.content.id || this.pageParams?.contentId
      );
    }

    this.resolvedDisplaySourceName = displayName;
    if (displayName.length > 0 && this.content.sourceName !== displayName) {
      this.updateCurrentContentSourceDisplayName(displayName);
    }
  }

  private updateCurrentContentSourceDisplayName(sourceName: string): void {
    if (!this.content) {
      return;
    }
    const currentContent: UnifiedContent = this.content;
    this.content = {
      id: currentContent.id,
      title: currentContent.title,
      coverUrl: currentContent.coverUrl,
      author: currentContent.author,
      description: currentContent.description,
      contentType: currentContent.contentType,
      genres: currentContent.genres,
      tags: currentContent.tags,
      readStatus: currentContent.readStatus,
      isFavorite: currentContent.isFavorite,
      isNSFW: currentContent.isNSFW,
      totalChapters: currentContent.totalChapters,
      readChapters: currentContent.readChapters,
      lastReadChapterIndex: currentContent.lastReadChapterIndex,
      lastReadChapterTitle: currentContent.lastReadChapterTitle,
      lastReadTime: currentContent.lastReadTime,
      readProgress: currentContent.readProgress,
      sourceId: currentContent.sourceId,
      sourceName: sourceName,
      sourcePkg: currentContent.sourcePkg,
      sourceUrl: currentContent.sourceUrl,
      isLocal: currentContent.isLocal,
      remoteVerificationInfo: currentContent.remoteVerificationInfo,
      publisher: currentContent.publisher,
      publishDate: currentContent.publishDate,
      isbn: currentContent.isbn,
      fileSize: currentContent.fileSize,
      filePath: currentContent.filePath,
      format: currentContent.format,
      chapters: currentContent.chapters,
      originalData: currentContent.originalData,
      originalType: currentContent.originalType
    };
  }

  private getDisplaySourceName(): string {
    const resolvedName: string = this.normalizeDisplaySourceText(this.resolvedDisplaySourceName);
    if (resolvedName.length > 0) {
      return resolvedName;
    }
    const sourceName: string = this.normalizeDisplaySourceText(this.content?.sourceName);
    return this.isLikelySourceIdentifier(sourceName) ? '' : sourceName;
  }

  private getOnlineEBookExtendedData(filePath: string | undefined | null): OnlineEBookExtendedData | null {
    const text: string = this.normalizeTrackingText(filePath);
    if (text.length <= 0 || !text.startsWith('{') ||
      (text.indexOf('"sourceId"') < 0 && text.indexOf('"onlineReaderUrl"') < 0)) {
      return null;
    }
    try {
      return SafeUtils.parseObj(text) as OnlineEBookExtendedData;
    } catch (error) {
      logger.warn(TAG, `解析在线电子书扩展数据失败: ${String(error)}`);
      return null;
    }
  }

  private getNormalizedOnlineEBookBaseUrl(sourceInfo: SourceInfo | null): string {
    const rawBaseUrl: string = this.normalizeTrackingText(sourceInfo?.baseUrl);
    if (rawBaseUrl.endsWith('/')) {
      return rawBaseUrl.substring(0, rawBaseUrl.length - 1);
    }
    return rawBaseUrl;
  }

  private buildAbsoluteOnlineEBookUrl(baseUrl: string, pathOrUrl: string): string {
    const normalizedValue: string = this.normalizeTrackingText(pathOrUrl);
    if (normalizedValue.length <= 0) {
      return '';
    }
    if (this.isHttpUrl(normalizedValue)) {
      return normalizedValue;
    }
    if (baseUrl.length <= 0) {
      return normalizedValue;
    }
    if (normalizedValue.startsWith('/')) {
      return `${baseUrl}${normalizedValue}`;
    }
    return `${baseUrl}/${normalizedValue}`;
  }

  private extractOnlineEBookDetailUrlTemplate(sourceConfig: OnlineEBookSourceConfig | null): string {
    if (!sourceConfig || !sourceConfig.workflows || !sourceConfig.workflows.getBookDetail) {
      return '';
    }
    const actions: OnlineEBookWorkflowAction[] | undefined = sourceConfig.workflows.getBookDetail.actions;
    if (!actions || !Array.isArray(actions)) {
      return '';
    }
    for (let index = 0; index < actions.length; index++) {
      const action: OnlineEBookWorkflowAction = actions[index];
      if (action.type === 'navigate' && action.url && action.url.trim().length > 0) {
        return action.url.trim();
      }
    }
    return '';
  }

  private async resolveOnlineEBookDetailRequestValue(
    bookId: string,
    sourceId: string,
    sourceInfo: SourceInfo | null,
    extendedData: OnlineEBookExtendedData | null
  ): Promise<string> {
    const normalizedBookId: string = this.normalizeTrackingText(bookId);
    if (normalizedBookId.length <= 0) {
      return '';
    }

    const storedRequestValue: string = this.normalizeTrackingText(extendedData?.detailRequestValue);
    if (storedRequestValue.length > 0) {
      return storedRequestValue;
    }

    if (this.isHttpUrl(normalizedBookId)) {
      return normalizedBookId;
    }

    const baseUrl: string = this.getNormalizedOnlineEBookBaseUrl(sourceInfo);
    if (normalizedBookId.startsWith('/')) {
      return this.buildAbsoluteOnlineEBookUrl(baseUrl, normalizedBookId);
    }

    const numericSourceId: number = Number(sourceId);
    if (numericSourceId > 0) {
      try {
        const rawSourceConfig = await this.dataManager.getSourceConfig(numericSourceId) as OnlineEBookSourceConfig | null;
        const detailUrlTemplate: string = this.extractOnlineEBookDetailUrlTemplate(rawSourceConfig);
        if (detailUrlTemplate.includes('{{bookId}}')) {
          return normalizedBookId;
        }
        if (detailUrlTemplate.includes('{{mangaUrl}}')) {
          return this.buildAbsoluteOnlineEBookUrl(baseUrl, normalizedBookId);
        }
      } catch (error) {
        logger.warn(TAG, `解析在线电子书详情模板失败: ${String(error)}`);
      }
    }

    return normalizedBookId;
  }

  private isOnlineEBookDownloadOnlyContent(): boolean {
    if (!this.content || this.content.contentType !== UnifiedContentType.EBOOK) {
      return false;
    }
    if (this.content.isLocal) {
      return false;
    }
    return this.normalizeTrackingText(this.onlineReaderUrl).length <= 0;
  }

  private beginOnlineEBookRecovery(statusText: string): void {
    this.isOnlineEBookRecoveryInProgress = true;
    this.onlineEBookRecoveryStatusText = statusText;
    this.refreshProgress = statusText;
    this.isLoading = true;
    this.isChaptersLoading = true;
    this.isLoadingRecommendations = true;
    this.isLoadingShelfContent = true;
    if (this.content && this.content.contentType === UnifiedContentType.EBOOK) {
      if (!this.content.description || this.content.description.includes('安全验证页面')) {
        this.content.description = statusText;
      }
    }
  }

  private endOnlineEBookRecovery(): void {
    this.isOnlineEBookRecoveryInProgress = false;
    this.onlineEBookRecoveryStatusText = '';
    if (this.refreshProgress.includes('安全验证')) {
      this.refreshProgress = '';
    }
    this.isLoading = false;
    this.isLoadingRecommendations = false;
    this.isLoadingShelfContent = false;
  }

  private isReadActionBusy(): boolean {
    return this.isOpeningOnlineEBookDownloadDetail || this.isOnlineEBookRecoveryInProgress || this.isLoading || this.isChaptersLoading;
  }

  private clearOnlineEBookRecoveryTimer(): void {
    if (this.onlineEBookRecoveryTimer >= 0) {
      clearTimeout(this.onlineEBookRecoveryTimer);
      this.onlineEBookRecoveryTimer = -1;
    }
  }

  private clearCacheStatusRefreshTimer(): void {
    if (this.cacheStatusRefreshTimer >= 0) {
      clearTimeout(this.cacheStatusRefreshTimer);
      this.cacheStatusRefreshTimer = -1;
    }
  }

  private scheduleCacheStatusRefresh(): void {
    if (this.cacheStatusRefreshTimer >= 0) {
      return;
    }
    this.cacheStatusRefreshTimer = setTimeout(() => {
      this.cacheStatusRefreshTimer = -1;
      void this.loadCacheStatus();
    }, 800);
  }

  private buildOnlineEBookVerificationInfo(
    status: string,
    message: string,
    pageUrl: string,
    pageTitle: string,
    cooldownText: string,
    cooldownSeconds: number,
    canRetryVerification: boolean,
    attempt: number
  ): RemoteVerificationInfo {
    const info: RemoteVerificationInfo = {
      status: status,
      message: message,
      pageUrl: pageUrl,
      pageTitle: pageTitle,
      cooldownText: cooldownText,
      cooldownSeconds: cooldownSeconds,
      canRetryVerification: canRetryVerification,
      attempt: attempt,
      lastUpdatedTime: Date.now()
    };
    return info;
  }

  private extractOnlineEBookVerificationInfo(extendedData: OnlineEBookExtendedData | null): RemoteVerificationInfo | null {
    if (!extendedData) {
      return null;
    }
    const status: string = this.normalizeTrackingText(extendedData.verificationStatus);
    const message: string = this.normalizeTrackingText(extendedData.verificationMessage);
    const pageUrl: string = this.normalizeTrackingText(extendedData.verificationPageUrl);
    const pageTitle: string = this.normalizeDisplaySourceText(extendedData.verificationPageTitle || '');
    const cooldownText: string = this.normalizeTrackingText(extendedData.verificationCooldownText);
    const cooldownSeconds: number = Number(extendedData.verificationCooldownSeconds || 0);
    const canRetryRaw: string = this.normalizeTrackingText(String(extendedData.verificationCanRetry ?? ''));
    const canRetryVerification: boolean = canRetryRaw === 'true' || canRetryRaw === '1';
    const attempt: number = Number(extendedData.verificationAttempt || 0);
    const lastUpdatedTime: number = Number(extendedData.verificationUpdatedAt || 0);
    if (status.length <= 0 && message.length <= 0 && pageUrl.length <= 0 && pageTitle.length <= 0 && cooldownText.length <= 0) {
      return null;
    }
    return {
      status: status,
      message: message,
      pageUrl: pageUrl,
      pageTitle: pageTitle,
      cooldownText: cooldownText,
      cooldownSeconds: cooldownSeconds,
      canRetryVerification: canRetryVerification,
      attempt: attempt,
      lastUpdatedTime: lastUpdatedTime
    };
  }

  private async persistOnlineEBookVerificationInfo(info: RemoteVerificationInfo | null): Promise<void> {
    if (!this.content || this.content.contentType !== UnifiedContentType.EBOOK) {
      return;
    }
    try {
      const ebook: EBook | null = await this.ebookDataManager.getEBookById(this.content.id);
      if (!ebook) {
        return;
      }
      const extendedData: OnlineEBookExtendedData | null = this.getOnlineEBookExtendedData(ebook.filePath);
      if (!extendedData) {
        return;
      }
      const nextData: OnlineEBookExtendedData = {
        sourceId: extendedData.sourceId || this.content.sourceId || '',
        sourceName: extendedData.sourceName || this.content.sourceName || '',
        sourcePkg: extendedData.sourcePkg || this.content.sourcePkg || '',
        onlineReaderUrl: extendedData.onlineReaderUrl || this.onlineReaderUrl || '',
        detailRequestValue: extendedData.detailRequestValue || this.onlineEBookDetailRequestValue || '',
        verificationStatus: info ? info.status : '',
        verificationMessage: info ? info.message : '',
        verificationPageUrl: info ? (info.pageUrl || '') : '',
        verificationPageTitle: info ? (info.pageTitle || '') : '',
        verificationCooldownText: info ? (info.cooldownText || '') : '',
        verificationCooldownSeconds: info ? (info.cooldownSeconds || 0) : 0,
        verificationCanRetry: info ? (info.canRetryVerification === true) : false,
        verificationAttempt: info ? (info.attempt || 0) : 0,
        verificationUpdatedAt: info ? (info.lastUpdatedTime || Date.now()) : 0
      };
      const nextJson: string = JSON.stringify(nextData);
      if (nextJson === ebook.filePath) {
        return;
      }
      ebook.filePath = nextJson;
      await this.ebookDataManager.saveEBook(ebook, { skipReadingSettings: true });
    } catch (error) {
      logger.warn(TAG, `持久化在线电子书验证信息失败: ${String(error)}`);
    }
  }

  private applyOnlineEBookVerificationInfo(info: RemoteVerificationInfo | null, persistToLocal: boolean): void {
    this.onlineEBookVerificationInfo = info;
    if (this.content) {
      this.content.remoteVerificationInfo = info || undefined;
    }
    if (persistToLocal) {
      void this.persistOnlineEBookVerificationInfo(info);
    }
  }

  private parseCooldownTextToSeconds(text: string): number {
    const normalizedText: string = this.normalizeTrackingText(text);
    if (normalizedText.length <= 0) {
      return 0;
    }
    const minuteMatch: RegExpMatchArray | null = normalizedText.match(/(\d+)\s*分钟/);
    if (minuteMatch && minuteMatch.length > 1) {
      return Number(minuteMatch[1]) * 60;
    }
    const secondMatch: RegExpMatchArray | null = normalizedText.match(/(\d+)\s*秒/);
    if (secondMatch && secondMatch.length > 1) {
      return Number(secondMatch[1]);
    }
    return 0;
  }

  private async getOnlineEBookVerificationState(): Promise<OnlineEBookVerificationState> {
    const fallback: OnlineEBookVerificationState = {
      url: '',
      title: '',
      isVerifyEntry: false,
      cooldownText: '',
      canRetryVerification: false
    };
    try {
      const script = `JSON.stringify({
        url: location.href || '',
        title: document.title || '',
        isVerifyEntry: (location.pathname || '').includes('verify_entry') || (document.title || '').includes('安全检查'),
        cooldownText: (document.querySelector('.cooldown-time') && document.querySelector('.cooldown-time').textContent) ? document.querySelector('.cooldown-time').textContent.trim() : '',
        canRetryVerification: typeof window.retryVerification === 'function'
      })`;
      const resultStr = await new Promise<string>((resolve, reject) => {
        this.webViewController.runJavaScript(script, (error: Error | null, result: string) => {
          if (error) {
            reject(error);
          } else {
            resolve(String(result));
          }
        });
      });
      let cleanResult = resultStr;
      if (cleanResult.startsWith('"') && cleanResult.endsWith('"')) {
        cleanResult = cleanResult.slice(1, -1).replace(/\\"/g, '"');
      }
      const parsed = SafeUtils.parseObj(cleanResult) as Record<string, ESObject>;
      return {
        url: String(parsed['url'] || ''),
        title: String(parsed['title'] || ''),
        isVerifyEntry: Boolean(parsed['isVerifyEntry']),
        cooldownText: String(parsed['cooldownText'] || ''),
        canRetryVerification: Boolean(parsed['canRetryVerification'])
      };
    } catch (error) {
      logger.warn(TAG, `读取在线电子书验证状态失败: ${String(error)}`);
      return fallback;
    }
  }

  private async triggerOnlineEBookVerificationRetry(): Promise<boolean> {
    try {
      const resultStr = await new Promise<string>((resolve, reject) => {
        this.webViewController.runJavaScript(
          `(() => { if (typeof window.retryVerification === 'function') { window.retryVerification(); return 'true'; } return 'false'; })()`,
          (error: Error | null, result: string) => {
            if (error) {
              reject(error);
            } else {
              resolve(String(result));
            }
          }
        );
      });
      const normalized: string = resultStr.replace(/^"+|"+$/g, '').trim().toLowerCase();
      return normalized === 'true';
    } catch (error) {
      logger.warn(TAG, `触发在线电子书站点验证失败: ${String(error)}`);
      return false;
    }
  }

  private scheduleOnlineEBookRecovery(
    bookId: string,
    sourceId: string,
    retryAttempt: number,
    delayMs: number,
    statusText: string
  ): void {
    this.clearOnlineEBookRecoveryTimer();
    this.beginOnlineEBookRecovery(statusText);
    this.onlineEBookRecoveryTimer = setTimeout(() => {
      this.onlineEBookRecoveryTimer = -1;
      void this.loadOnlineEBookContent(bookId, sourceId, retryAttempt);
    }, delayMs);
  }

  private isInvalidOnlineEBookDetailResult(detail: OnlineEBookDetailRecord, sourceInfo: SourceInfo | null): boolean {
    const detailId: string = this.normalizeTrackingText(detail.id);
    const detailTitle: string = this.normalizeDisplaySourceText(detail.title);
    if (detailTitle.includes('安全检查') || detailId.includes('verify_entry')) {
      return true;
    }
    const baseUrl: string = this.normalizeTrackingText(sourceInfo?.baseUrl).toLowerCase();
    if (baseUrl.includes('tstrs.me') && detailId.startsWith('/')) {
      return true;
    }
    return false;
  }

  private openOnlineEBookDownloadDetailPage(): void {
    if (!this.content) {
      return;
    }
    const sourceIdText: string = this.normalizeTrackingText(this.content.sourceId || this.pageParams?.sourceId);
    const numericSourceId: number = Number(sourceIdText);
    if (!(numericSourceId > 0)) {
      this.getUIContext().getPromptAction().showToast({ message: '缺少在线电子书图源信息', duration: 1500 });
      return;
    }
    const params: OnlineEBookDetailPageParams = {
      sourceId: numericSourceId,
      bookId: this.content.id || this.pageParams?.contentId || '',
      cachedCoverPath: this.localCoverPath || this.pageParams?.cachedCoverPath || undefined,
      cachedTitle: this.content.title || this.pageParams?.cachedTitle || undefined,
      cachedCover: this.content.coverUrl || this.pageParams?.cachedCover || undefined,
      autoStartDownload: true
    };
    logger.info(TAG, `打开在线电子书下载详情页: sourceId=${numericSourceId}, bookId=${params.bookId}`);
    this.navigateWithManagedWindowTransition('OnlineEBookDetailPage', params);
  }

  private async retryOnlineEBookDetailAfterVerification(
    bookId: string,
    sourceId: string,
    retryAttempt: number
  ): Promise<void> {
    const verificationState: OnlineEBookVerificationState = await this.getOnlineEBookVerificationState();
    const cooldownSeconds: number = this.parseCooldownTextToSeconds(verificationState.cooldownText);
    if (cooldownSeconds > 0) {
      const delayMs: number = Math.max(5000, (cooldownSeconds * 1000) + 1500);
      const statusText: string = `站点安全验证冷却中，约 ${verificationState.cooldownText} 后自动重试...`;
      this.applyOnlineEBookVerificationInfo(
        this.buildOnlineEBookVerificationInfo(
          'cooldown',
          statusText,
          verificationState.url,
          verificationState.title,
          verificationState.cooldownText,
          cooldownSeconds,
          verificationState.canRetryVerification,
          retryAttempt
        ),
        true
      );
      this.scheduleOnlineEBookRecovery(bookId, sourceId, retryAttempt, delayMs, statusText);
      return;
    }
    if (verificationState.canRetryVerification) {
      const triggered: boolean = await this.triggerOnlineEBookVerificationRetry();
      if (triggered) {
        const statusText: string = `正在通过站点安全验证（第 ${retryAttempt}/${this.onlineEBookRecoveryMaxAttempts} 次）...`;
        this.applyOnlineEBookVerificationInfo(
          this.buildOnlineEBookVerificationInfo(
            'verifying',
            statusText,
            verificationState.url,
            verificationState.title,
            verificationState.cooldownText,
            cooldownSeconds,
            true,
            retryAttempt
          ),
          true
        );
        this.scheduleOnlineEBookRecovery(bookId, sourceId, retryAttempt, 6500, statusText);
        return;
      }
    }
    const fallbackStatusText: string = `站点安全验证中，正在第 ${retryAttempt}/${this.onlineEBookRecoveryMaxAttempts} 次重试...`;
    this.applyOnlineEBookVerificationInfo(
      this.buildOnlineEBookVerificationInfo(
        'retrying',
        fallbackStatusText,
        verificationState.url,
        verificationState.title,
        verificationState.cooldownText,
        cooldownSeconds,
        verificationState.canRetryVerification,
        retryAttempt
      ),
      true
    );
    this.scheduleOnlineEBookRecovery(bookId, sourceId, retryAttempt, 2000 * retryAttempt, fallbackStatusText);
  }

  private getCurrentNovelSourceId(): string {
    if (!this.content || this.content.contentType !== UnifiedContentType.NOVEL) {
      return '';
    }
    const contentSourceId = this.normalizeTrackingText(this.content.sourceId);
    if (contentSourceId.length > 0) {
      return contentSourceId;
    }
    return this.normalizeTrackingText(this.pageParams?.sourceId);
  }

  private getCurrentNovelBookUrl(): string {
    if (!this.content || this.content.contentType !== UnifiedContentType.NOVEL) {
      return '';
    }
    const contentId: string = this.normalizeTrackingText(typeof this.content.id === 'string' ? this.content.id : '');
    if (contentId.length > 0) {
      return contentId;
    }
    return this.normalizeTrackingText(this.pageParams ? this.pageParams.contentId : '');
  }

  private isCurrentLocalImportedContent(): boolean {
    if (!this.content) {
      return false;
    }
    return this.content.isLocal === true;
  }

  private isLocalImportedEBookContent(): boolean {
    if (!this.content || this.content.contentType !== UnifiedContentType.EBOOK) {
      return false;
    }
    return this.content.isLocal === true;
  }

  private normalizeNovelSourceLookupId(sourceId: string): string {
    let normalized: string = sourceId.trim();
    const extensionSeparator: number = normalized.indexOf('##');
    if (extensionSeparator >= 0) {
      normalized = normalized.substring(0, extensionSeparator).trim();
    }
    const fragmentIndex: number = normalized.indexOf('#');
    if (fragmentIndex >= 0) {
      normalized = normalized.substring(0, fragmentIndex).trim();
    }
    if (normalized.length > 1 && normalized.endsWith('/')) {
      normalized = normalized.substring(0, normalized.length - 1);
    }
    return normalized;
  }

  private appendNovelSourceLookupCandidate(candidates: string[], candidate: string): void {
    const normalizedCandidate: string = candidate.trim();
    if (normalizedCandidate.length <= 0) {
      return;
    }
    if (!candidates.includes(normalizedCandidate)) {
      candidates.push(normalizedCandidate);
    }
  }

  private extractNovelSourceDomainId(sourceId: string): string {
    const match = sourceId.match(/^(https?:\/\/[^\/?#]+)/i);
    if (match && match[1]) {
      return match[1];
    }
    return sourceId;
  }

  private buildNovelSourceLookupCandidates(sourceId: string): string[] {
    const candidates: string[] = [];
    const trimmedSourceId: string = sourceId.trim();
    const normalizedSourceId: string = this.normalizeNovelSourceLookupId(trimmedSourceId);
    this.appendNovelSourceLookupCandidate(candidates, trimmedSourceId);
    this.appendNovelSourceLookupCandidate(candidates, normalizedSourceId);
    if (normalizedSourceId.length > 0) {
      this.appendNovelSourceLookupCandidate(candidates, `${normalizedSourceId}/`);
    }

    const domainId: string = this.extractNovelSourceDomainId(normalizedSourceId);
    this.appendNovelSourceLookupCandidate(candidates, domainId);
    if (domainId.length > 0) {
      this.appendNovelSourceLookupCandidate(candidates, `${domainId}/`);
    }

    if (normalizedSourceId.startsWith('http://')) {
      const httpsVariant: string = `https://${normalizedSourceId.substring('http://'.length)}`;
      this.appendNovelSourceLookupCandidate(candidates, httpsVariant);
      this.appendNovelSourceLookupCandidate(candidates, `${httpsVariant}/`);
    } else if (normalizedSourceId.startsWith('https://')) {
      const httpVariant: string = `http://${normalizedSourceId.substring('https://'.length)}`;
      this.appendNovelSourceLookupCandidate(candidates, httpVariant);
      this.appendNovelSourceLookupCandidate(candidates, `${httpVariant}/`);
    } else if (normalizedSourceId.length > 0 && normalizedSourceId.indexOf('://') < 0) {
      const httpsVariantNoScheme: string = `https://${normalizedSourceId}`;
      const httpVariantNoScheme: string = `http://${normalizedSourceId}`;
      this.appendNovelSourceLookupCandidate(candidates, httpsVariantNoScheme);
      this.appendNovelSourceLookupCandidate(candidates, `${httpsVariantNoScheme}/`);
      this.appendNovelSourceLookupCandidate(candidates, httpVariantNoScheme);
      this.appendNovelSourceLookupCandidate(candidates, `${httpVariantNoScheme}/`);
    }

    return candidates;
  }

  private extractNovelHostFromUrl(url: string): string {
    const match = url.trim().match(/^(?:https?:\/\/)?([^\/?#]+)/i);
    if (match && match[1]) {
      return match[1].toLowerCase();
    }
    return '';
  }

  private areNovelSourceHostsCompatible(sourceUrl: string, bookUrl: string): boolean {
    const sourceHost: string = this.extractNovelHostFromUrl(sourceUrl);
    const bookHost: string = this.extractNovelHostFromUrl(bookUrl);
    if (sourceHost.length <= 0 || bookHost.length <= 0) {
      return true;
    }
    if (sourceHost === bookHost) {
      return true;
    }
    if (sourceHost.endsWith(`.${bookHost}`) || bookHost.endsWith(`.${sourceHost}`)) {
      return true;
    }
    return false;
  }

  private normalizeNovelSourceName(sourceName: string): string {
    return sourceName.trim().replace(/\s+/g, '').toLowerCase();
  }

  private isNovelSourceNameCompatible(expectedSourceName: string, actualSourceName: string): boolean {
    const normalizedExpected: string = this.normalizeNovelSourceName(expectedSourceName);
    const normalizedActual: string = this.normalizeNovelSourceName(actualSourceName);
    if (normalizedExpected.length <= 0 || normalizedActual.length <= 0) {
      return true;
    }
    if (normalizedExpected === normalizedActual) {
      return true;
    }
    if (normalizedExpected.includes(normalizedActual) || normalizedActual.includes(normalizedExpected)) {
      return true;
    }
    return false;
  }

  private resolveCurrentNovelSource(): LegadoBookSource | null {
    if (!this.content || this.content.contentType !== UnifiedContentType.NOVEL) {
      return null;
    }
    const sourceId: string = this.getCurrentNovelSourceId();
    if (sourceId.length <= 0) {
      return null;
    }
    const sourceName: string = typeof this.content.sourceName === 'string' ? this.content.sourceName.trim() : '';
    const bookUrl: string = this.getCurrentNovelBookUrl();
    const lookupCandidates: string[] = this.buildNovelSourceLookupCandidates(sourceId);

    for (const candidate of lookupCandidates) {
      const source = this.novelSourceManager.getSource(candidate);
      if (!source) {
        continue;
      }
      const sourceUrl: string = typeof source.bookSourceUrl === 'string' ? source.bookSourceUrl.trim() : '';
      const sourceBookName: string = typeof source.bookSourceName === 'string' ? source.bookSourceName.trim() : '';
      if (!this.isNovelSourceNameCompatible(sourceName, sourceBookName)) {
        continue;
      }
      if (!this.areNovelSourceHostsCompatible(sourceUrl, bookUrl)) {
        continue;
      }
      return source;
    }

    return null;
  }

  private getCurrentNovelSourceType(): LegadoBookSourceType {
    const source: LegadoBookSource | null = this.resolveCurrentNovelSource();
    if (!source) {
      return LegadoBookSourceType.TEXT;
    }
    return source.bookSourceType;
  }

  private isCurrentNovelAudioSource(): boolean {
    return this.content?.contentType === UnifiedContentType.NOVEL &&
      this.getCurrentNovelSourceType() === LegadoBookSourceType.AUDIO;
  }

  private getNovelCacheSectionTitle(): string {
    return this.isCurrentNovelAudioSource() ? '听书缓存' : '章节缓存';
  }

  private getNovelCachedCountLabel(): string {
    return this.isCurrentNovelAudioSource() ? '已缓存音频' : '已缓存章节';
  }

  private getNovelCacheActionTitle(): string {
    return this.isCurrentNovelAudioSource() ? '听书缓存' : '缓存章节';
  }

  private getNovelDownloadedTagLabel(): string {
    return this.isCurrentNovelAudioSource() ? '已缓存音频' : '已缓存';
  }

  private getNovelCacheCountActionLabel(count: number): string {
    return this.isCurrentNovelAudioSource() ? `缓存 ${count} 章音频` : `缓存 ${count} 章`;
  }

  private getNovelCacheWorkingLabel(): string {
    return this.isCurrentNovelAudioSource() ? '正在缓存听书音频...' : '正在缓存中...';
  }

  private getCacheActionButtonLabel(): string {
    if (!this.content) {
      return '缓存';
    }
    if (this.content.contentType === UnifiedContentType.NOVEL) {
      return this.getNovelCacheActionTitle();
    }
    if (this.content.contentType === UnifiedContentType.MANGA) {
      return '缓存章节';
    }
    return '缓存';
  }

  private openCacheDialogFromDetail(trigger: string): void {
    if (!this.content) {
      return;
    }
    if (this.content.contentType === UnifiedContentType.NOVEL) {
      logger.info(
        TAG,
        `打开小说缓存对话框: 触发源=${trigger}, 听书源=${this.isCurrentNovelAudioSource()}, 图源=${this.getCurrentNovelSourceId()}`
      );
      this.downloadDialogLoadSignal++;
      return;
    }
    if (this.content.contentType === UnifiedContentType.MANGA) {
      logger.info(TAG, `打开漫画缓存对话框: 触发源=${trigger}`);
      this.downloadDialogLoadSignal++;
      return;
    }
    logger.info(TAG, `打开通用缓存对话框: 触发源=${trigger}, 内容类型=${this.content.contentType}`);
    this.downloadDialogLoadSignal++;
  }

  /**
   * 打开分享链接对话框
   */
  private openShareDialogFromDetail(): void {
    if (!this.content) {
      return;
    }
    if (this.shouldShareAsLocalFile()) {
      void this.shareLocalContentFile();
      return;
    }
    logger.info(TAG, `打开分享链接对话框: 内容类型=${this.content.contentType}, source=${this.content.sourceName}`);
    this.shareDialogLoadSignal++;
  }

  private shouldShareAsLocalFile(): boolean {
    if (!this.content) {
      return false;
    }
    if (this.content.contentType === UnifiedContentType.MANGA) {
      return this.shouldShareMangaAsLocalFile();
    }
    if (this.content.contentType === UnifiedContentType.EBOOK) {
      return !this.isOnlineEBookContentForShare();
    }
    if (this.content.contentType === UnifiedContentType.NOVEL) {
      return !this.isOnlineNovelContentForShare();
    }
    return false;
  }

  private shouldShareMangaAsLocalFile(): boolean {
    if (!this.content || this.content.contentType !== UnifiedContentType.MANGA) {
      return false;
    }
    const pageSourceId: string = this.normalizeTrackingText(this.pageParams?.sourceId);
    const contentSourceId: string = this.normalizeTrackingText(this.content.sourceId);
    const sourceId: string = contentSourceId.length > 0 ? contentSourceId : pageSourceId;
    const pageSourcePkg: string = this.normalizeTrackingText(this.pageParams?.sourcePkg);
    const contentSourcePkg: string = this.normalizeTrackingText(this.content.sourcePkg);
    const sourcePkg: string = contentSourcePkg.length > 0 ? contentSourcePkg : pageSourcePkg;
    if (sourceId.length <= 0) {
      if (sourcePkg.length > 0 || this.content.isLocal === false) {
        return false;
      }
      return true;
    }
    if (!this.isLocalMangaShareSourceId(sourceId)) {
      return false;
    }
    return true;
  }

  private isOnlineEBookContentForShare(): boolean {
    if (!this.content || this.content.contentType !== UnifiedContentType.EBOOK) {
      return false;
    }
    const contentSourceId: string = this.normalizeTrackingText(this.content.sourceId);
    const pageSourceId: string = this.normalizeTrackingText(this.pageParams?.sourceId);
    if (contentSourceId.length > 0 || pageSourceId.length > 0) {
      return true;
    }
    if (this.isHttpUrl(this.content.id)) {
      return true;
    }
    if (this.normalizeTrackingText(this.onlineReaderUrl).length > 0) {
      return true;
    }
    if (this.hasOnlineEBookExtendedData(this.content.filePath)) {
      return true;
    }
    const ebook: EBook | null = EBookAdapter.getOriginalEBook(this.content);
    if (!ebook) {
      return false;
    }
    if (this.isHttpUrl(ebook.id)) {
      return true;
    }
    return this.hasOnlineEBookExtendedData(ebook.filePath);
  }

  private isOnlineNovelContentForShare(): boolean {
    if (!this.content || this.content.contentType !== UnifiedContentType.NOVEL) {
      return false;
    }
    const sourceId: string = this.getCurrentNovelSourceId();
    if (sourceId.length <= 0 || sourceId === 'local' || sourceId === LOCAL_TXT_NOVEL_SOURCE_ID) {
      return false;
    }
    return true;
  }

  private isLocalMangaShareSourceId(sourceId: string): boolean {
    const normalized: string = sourceId.trim();
    return normalized.length <= 0 ||
      normalized === '0' ||
      normalized === 'local' ||
      normalized === 'local_import' ||
      normalized === 'local_pdf' ||
      normalized === 'download_import';
  }

  private isHttpUrl(value: string | undefined | null): boolean {
    const text: string = this.normalizeTrackingText(value);
    return text.startsWith('http://') || text.startsWith('https://');
  }

  private hasOnlineEBookExtendedData(filePath: string | undefined | null): boolean {
    const text: string = this.normalizeTrackingText(filePath);
    if (text.length <= 0) {
      return false;
    }
    return text.startsWith('{') &&
      (text.includes('"sourceId"') || text.includes('"onlineReaderUrl"'));
  }

  private async shareLocalContentFile(): Promise<void> {
    if (!this.content) {
      return;
    }
    try {
      const context: common.UIAbilityContext | null = this.getShareAbilityContext();
      if (!context) {
        throw new Error('hostContext is null');
      }

      const sharePath: string = await this.resolveLocalContentSharePath();
      if (sharePath.length <= 0) {
        this.getUIContext().getPromptAction().showToast({ message: '未找到可分享的本地文件', duration: 1800 });
        return;
      }

      const normalizedPath: string = this.normalizeShareFilePath(sharePath);
      if (!this.isExistingSharePath(normalizedPath)) {
        this.getUIContext().getPromptAction().showToast({ message: '本地文件不存在，无法分享', duration: 1800 });
        logger.warn(TAG, `本地分享失败，文件不存在: ${normalizedPath}`);
        return;
      }

      const shareUri: string = fileUri.getUriFromPath(normalizedPath);
      const shareData: systemShare.SharedData = new systemShare.SharedData({
        utd: this.getLocalContentShareUtd(normalizedPath),
        uri: shareUri,
        title: this.getLocalContentShareTitle(),
        description: this.getLocalContentShareDescription()
      });
      const controller: systemShare.ShareController = new systemShare.ShareController(shareData);
      await controller.show(context, {
        previewMode: systemShare.SharePreviewMode.DETAIL,
        selectionMode: systemShare.SelectionMode.SINGLE
      });
      logger.info(TAG, `本地文件分享面板已打开: ${normalizedPath}`);
    } catch (error) {
      const errorMessage: string = error instanceof Error ? error.message : String(error);
      logger.error(TAG, `本地文件分享失败: ${errorMessage}`);
      this.getUIContext().getPromptAction().showToast({ message: `分享失败: ${errorMessage}`, duration: 2000 });
    }
  }

  private async resolveLocalContentSharePath(): Promise<string> {
    if (!this.content) {
      return '';
    }
    const contentPath: string = this.getExistingSharePath(this.content.filePath);
    if (contentPath.length > 0) {
      return contentPath;
    }
    if (this.content.contentType === UnifiedContentType.EBOOK) {
      return this.getLocalEBookSharePath();
    }
    if (this.content.contentType === UnifiedContentType.MANGA) {
      return await this.getLocalMangaSharePath();
    }
    if (this.content.contentType === UnifiedContentType.NOVEL) {
      return this.getLocalNovelSharePath();
    }
    return '';
  }

  private getLocalEBookSharePath(): string {
    if (!this.content) {
      return '';
    }
    const ebook: EBook | null = EBookAdapter.getOriginalEBook(this.content);
    if (!ebook) {
      return '';
    }
    return this.getExistingSharePath(ebook.filePath);
  }

  private getLocalNovelSharePath(): string {
    if (!this.content) {
      return '';
    }
    return this.getExistingSharePath(this.content.filePath);
  }

  private async getLocalMangaSharePath(): Promise<string> {
    if (!this.content) {
      return '';
    }
    const originalManga: Manga | null = MangaAdapter.getOriginalManga(this.content);
    if (originalManga) {
      const originalChapterPath: string = this.getExistingMangaChapterSharePath(originalManga.chapters);
      if (originalChapterPath.length > 0) {
        return originalChapterPath;
      }
    }

    try {
      const chapters: ChapterInfo[] = await this.dataManager.getComicChapters(this.content.id);
      const chapterPath: string = this.getExistingDataChapterSharePath(chapters);
      if (chapterPath.length > 0) {
        return chapterPath;
      }

      for (let i = 0; i < chapters.length; i++) {
        const pages: PageInfo[] = await this.dataManager.getChapterPages(chapters[i].id);
        const pagePath: string = this.getExistingPageSharePath(pages);
        if (pagePath.length > 0) {
          return pagePath;
        }
      }
    } catch (error) {
      logger.warn(TAG, `解析本地漫画分享路径失败: ${String(error)}`);
    }

    return '';
  }

  private getExistingMangaChapterSharePath(chapters: MangaChapter[]): string {
    for (let i = 0; i < chapters.length; i++) {
      const chapter = chapters[i];
      const chapterPath: string = this.getMangaChapterContainerSharePath(chapter.localPath);
      if (chapterPath.length > 0) {
        return chapterPath;
      }
      const pagePath: string = this.getExistingMangaPageSharePath(chapter.pages);
      if (pagePath.length > 0) {
        return pagePath;
      }
    }
    return '';
  }

  private getExistingMangaPageSharePath(pages: MangaPage[]): string {
    for (let i = 0; i < pages.length; i++) {
      const page = pages[i];
      const localPath: string = this.getMangaPageContainerSharePath(page.localPath);
      if (localPath.length > 0) {
        return localPath;
      }
      const imagePath: string = this.isHttpUrl(page.imagePath) ? '' : this.getMangaPageContainerSharePath(page.imagePath);
      if (imagePath.length > 0) {
        return imagePath;
      }
    }
    return '';
  }

  private getExistingDataChapterSharePath(chapters: ChapterInfo[]): string {
    for (let i = 0; i < chapters.length; i++) {
      const chapterPath: string = this.getMangaChapterContainerSharePath(chapters[i].downloadPath);
      if (chapterPath.length > 0) {
        return chapterPath;
      }
    }
    return '';
  }

  private getExistingPageSharePath(pages: PageInfo[]): string {
    for (let i = 0; i < pages.length; i++) {
      const localPath: string = this.getMangaPageContainerSharePath(pages[i].localPath);
      if (localPath.length > 0) {
        return localPath;
      }
      const imageUrl: string = this.isHttpUrl(pages[i].imageUrl) ? '' : this.getMangaPageContainerSharePath(pages[i].imageUrl);
      if (imageUrl.length > 0) {
        return imageUrl;
      }
    }
    return '';
  }

  private getMangaChapterContainerSharePath(path: string | undefined | null): string {
    const existingPath: string = this.getExistingSharePath(path);
    if (existingPath.length <= 0) {
      return '';
    }
    if (!this.isDirectorySharePath(existingPath)) {
      return existingPath;
    }
    const parentPath: string = this.getExistingParentSharePath(existingPath);
    return parentPath.length > 0 ? parentPath : existingPath;
  }

  private getMangaPageContainerSharePath(path: string | undefined | null): string {
    const existingPath: string = this.getExistingSharePath(path);
    if (existingPath.length <= 0) {
      return '';
    }
    const parentPath: string = this.getExistingParentSharePath(existingPath);
    return parentPath.length > 0 ? parentPath : existingPath;
  }

  private getExistingParentSharePath(path: string): string {
    const parentPath: string = this.getParentSharePath(path);
    if (parentPath.length > 0 && this.isExistingSharePath(parentPath)) {
      return parentPath;
    }
    return '';
  }

  private getParentSharePath(path: string): string {
    const normalizedPath: string = this.normalizeShareFilePath(path);
    const separatorIndex: number = normalizedPath.lastIndexOf('/');
    if (separatorIndex <= 0) {
      return '';
    }
    return normalizedPath.substring(0, separatorIndex);
  }

  private getExistingSharePath(path: string | undefined | null): string {
    const normalizedPath: string = this.normalizeShareFilePath(path);
    if (normalizedPath.length > 0 && this.isExistingSharePath(normalizedPath)) {
      return normalizedPath;
    }
    return '';
  }

  private normalizeShareFilePath(path: string | undefined | null): string {
    const rawPath: string = this.normalizeTrackingText(path);
    if (rawPath.length <= 0) {
      return '';
    }
    if (rawPath.startsWith('file://')) {
      try {
        const uriObj: fileUri.FileUri = new fileUri.FileUri(rawPath);
        return uriObj.path;
      } catch (error) {
        logger.debug(TAG, `fileUri 路径解析失败，使用 file:// 截断路径: ${String(error)}`);
        return rawPath.substring('file://'.length);
      }
    }
    return rawPath;
  }

  private isExistingSharePath(path: string): boolean {
    const normalizedPath: string = this.normalizeShareFilePath(path);
    if (normalizedPath.length <= 0) {
      return false;
    }
    try {
      return SafeFileUtils.accessSync(normalizedPath);
    } catch (error) {
      return false;
    }
  }

  private isDirectorySharePath(path: string): boolean {
    const normalizedPath: string = this.normalizeShareFilePath(path);
    if (normalizedPath.length <= 0) {
      return false;
    }
    try {
      const stat: fs.Stat = SafeFileUtils.statSync(normalizedPath);
      return stat.isDirectory();
    } catch (error) {
      return false;
    }
  }

  private getLocalContentShareUtd(path: string): string {
    if (this.isDirectorySharePath(path)) {
      return utd.UniformDataType.FOLDER;
    }
    const extension: string = this.getFileExtensionForShare(path);
    if (extension === 'txt' || extension === 'log' || extension === 'md') {
      return utd.UniformDataType.PLAIN_TEXT;
    }
    if (extension === 'epub') {
      return utd.UniformDataType.EPUB;
    }
    if (extension === 'mobi') {
      return utd.UniformDataType.MOBI;
    }
    if (extension === 'azw') {
      return utd.UniformDataType.AZW;
    }
    if (extension === 'azw3') {
      return utd.UniformDataType.AZW3;
    }
    if (extension === 'pdf') {
      return utd.UniformDataType.PDF;
    }
    if (extension === 'jpg' || extension === 'jpeg') {
      return utd.UniformDataType.JPEG;
    }
    if (extension === 'png') {
      return utd.UniformDataType.PNG;
    }
    if (extension === 'gif') {
      return utd.UniformDataType.GIF;
    }
    if (extension === 'tif' || extension === 'tiff') {
      return utd.UniformDataType.TIFF;
    }
    if (extension === 'bmp') {
      return utd.UniformDataType.BMP;
    }
    if (extension === 'webp' || extension === 'avif' || extension === 'heic' || extension === 'heif') {
      return utd.UniformDataType.IMAGE;
    }
    if (extension === 'zip' || extension === 'cbz') {
      return utd.UniformDataType.ZIP_ARCHIVE;
    }
    if (extension === 'rar' || extension === 'cbr') {
      return utd.UniformDataType.RAR_ARCHIVE;
    }
    if (extension === '7z') {
      return utd.UniformDataType.SEVEN_ZIP_ARCHIVE;
    }
    if (extension === 'tar' || extension === 'gz' || extension === 'tgz' ||
      extension === 'bz2' || extension === 'xz' || extension === 'lzma') {
      return utd.UniformDataType.ARCHIVE;
    }
    return utd.UniformDataType.FILE;
  }

  private getFileExtensionForShare(path: string): string {
    const normalizedPath: string = this.normalizeShareFilePath(path);
    const separatorIndex: number = normalizedPath.lastIndexOf('/');
    const fileName: string = separatorIndex >= 0 ? normalizedPath.substring(separatorIndex + 1) : normalizedPath;
    const dotIndex: number = fileName.lastIndexOf('.');
    if (dotIndex < 0 || dotIndex >= fileName.length - 1) {
      return '';
    }
    return fileName.substring(dotIndex + 1).toLowerCase();
  }

  private getLocalContentShareTitle(): string {
    if (!this.content) {
      return '本地文件';
    }
    return this.content.title.length > 0 ? this.content.title : '本地文件';
  }

  private getLocalContentShareDescription(): string {
    if (!this.content) {
      return '来自漫匣的本地文件';
    }
    const author: string = this.normalizeTrackingText(this.content.author);
    if (author.length > 0) {
      return `${this.content.title} - ${author}`;
    }
    return `${this.getContentTypeName()} - 本地文件`;
  }

  private getShareAbilityContext(): common.UIAbilityContext | null {
    const uiContext = this.getUIContext();
    const hostContext = uiContext ? uiContext.getHostContext() : null;
    if (!hostContext) {
      return null;
    }
    return hostContext as common.UIAbilityContext;
  }
  
  /**
   * 判断下载任务是否属于当前内容
   * 小说使用 novelCacheBookId 格式，漫画使用原始 id
   */
  private isCurrentContentTask(task: UnifiedDownloadTask): boolean {
    if (!this.content) return false;
    
    // 小说使用特殊的 bookId 格式
    if (this.content.contentType === UnifiedContentType.NOVEL) {
      const sourceId = this.getCurrentNovelSourceId();
      if (sourceId) {
        const novelCacheBookId = this.getNovelCacheBookId(sourceId, this.content.id);
        return task.contentId === novelCacheBookId;
      }
    }
    
    // 漫画和其他类型直接比较原始 id
    return task.contentId === this.content.id;
  }
  
  // 在线电子书相关
  private sourceManager: SourceManager = SourceManager.getInstance();
  private ebookSourceEngine: MangaSourceEngine | null = null;
  @State private ebookWebViewReady: boolean = false;
  @State private ebookSourceInfo: SourceInfo | null = null;
  @State private onlineReaderUrl: string = '';
  private onlineEBookDetailRequestValue: string = '';
  private webViewAuthManager: WebViewAuthManager = WebViewAuthManager.getInstance();
  @State private isOnlineEBookRecoveryInProgress: boolean = false;
  @State private onlineEBookRecoveryStatusText: string = '';
  @State private isOpeningOnlineEBookDownloadDetail: boolean = false;
  private readonly onlineEBookRecoveryMaxAttempts: number = 2;
  private onlineEBookRecoveryTimer: number = -1;
  
  // 设置管理器
  private settingsManager: SettingsManager = SettingsManager.getInstance();
  
  // 智能推荐状态
  @State recommendedItems: RecommendationItem[] = [];
  @State isLoadingRecommendations: boolean = false;
  @State isPrimarySectionReady: boolean = false;

  private applyPageDisplayMode(mode: DisplayMode): void {
    WindowManager.setDisplayMode(mode, this.getUIContext());
  }

  private navigateWithManagedWindowTransition(targetPageName: string, params: Object | null): void {
    const navigateAction = (): void => {
      this.pathStack.pushPathByName(targetPageName, params);
    };
    try {
      PageWindowCoordinator.navigateWithManagedTransition(
        'UnifiedDetailPage',
        targetPageName,
        navigateAction,
        this.getUIContext(),
        WindowManager.getCurrentMode()
      );
    } catch (error) {
      logger.warn(TAG, `统一详情页托管窗口跳转失败，回退直接跳转: target=${targetPageName}, error=${String(error)}`);
      navigateAction();
    }
  }

  aboutToAppear(): void {
    this.applyPageDisplayMode(DisplayMode.STATUS_SAFE_BOTTOM_IMMERSIVE);
    this.loadGlobalChapterSortOrderPreference();
    ThemeAwareHelper.initializeThemeAware(this.componentId, this.themeState, (theme: ThemeType) => {
      logger.info(TAG, `主题切换: ${theme}`);
    });

    FontAwareHelper.initializeFontAware(
      this.componentId,
      this.fontState,
      (newState: FontAwareState) => {
        this.fontState = newState;
      }
    );

    this.initializeResponsiveLayout();
    this.webViewControllerAttached = false;
    eventBus.subscribe(GameEvent.MANGA_CACHE_UPDATED, this.onMangaCacheUpdated);
    logger.info(TAG, 'Waiting hidden WebView controller attach');
    void this.refreshPageGuide('aboutToAppear');
  }

  private resolveGuideHighlightRect(anchorId?: string, borderRadius: number = 18): GuideHighlightRect | null {
    if (!anchorId || anchorId.length <= 0) {
      return null;
    }
    try {
      return resolveGuideHighlightRectInRoot(this.getUIContext(), anchorId, borderRadius, 'guide_unified_detail_root');
    } catch (error) {
      logger.warn(TAG, `获取统一详情页引导锚点失败: ${String(error)}`);
      return null;
    }
  }

  private alignGuideViewport(anchorId?: string): boolean {
    if (this.responsive_isLandscape || !anchorId || anchorId === 'guide_unified_detail_header') {
      return false;
    }
    const scrollResult = ensureGuideAnchorVisibleInScroller(
      this.getUIContext(),
      this.scroller,
      anchorId,
      'guide_unified_detail_root',
      TITLE_BAR_HEIGHT + 24,
      280,
      280
    );
    return scrollResult.scrolled;
  }

  private async refreshPageGuide(trigger: string): Promise<void> {
    await this.appGuideManager.initialize();
    if (!this.appGuideManager.getCurrentStep()) {
      await this.appGuideManager.tryAutoStartFlowByPage(AppGuidePageId.UNIFIED_DETAIL);
    }
    const step = this.appGuideManager.getCurrentStep();
    if (!step || step.pageId !== AppGuidePageId.UNIFIED_DETAIL) {
      this.appGuideStep = null;
      this.appGuideHighlightRect = null;
      return;
    }
    if (this.alignGuideViewport(step.anchorId) && !trigger.endsWith('_retry_scroll')) {
      this.appGuideStep = null;
      this.appGuideHighlightRect = null;
      setTimeout(() => {
        void this.refreshPageGuide(`${trigger}_retry_scroll`);
      }, 320);
      return;
    }
    this.appGuideStep = step;
    this.appGuideHighlightRect = this.resolveGuideHighlightRect(step.anchorId, step.borderRadius ?? 18);
    if (!this.appGuideHighlightRect && !trigger.endsWith('_retry_layout')) {
      setTimeout(() => {
        void this.refreshPageGuide(`${trigger}_retry_layout`);
      }, 120);
    }
    logger.debug(TAG, `统一详情页引导已刷新: trigger=${trigger}, step=${step.id}`);
  }

  private handlePageGuideNext(): void {
    void this.appGuideManager.nextStep().then(() => {
      void this.refreshPageGuide('next');
    });
  }

  private handlePageGuideSkip(): void {
    void this.appGuideManager.skipCurrentFlow().then(() => {
      void this.refreshPageGuide('skip');
    });
  }

  private triggerInitialContentLoadIfReady(): void {
    if (this.initialContentLoadTriggered || !this.pageParams) {
      return;
    }

    if (!this.webViewControllerAttached) {
      this.pendingInitialContentLoad = true;
      logger.info(TAG, 'WebView控制器未附加，延迟加载详情页内容');
      return;
    }

    this.pendingInitialContentLoad = false;
    this.initialContentLoadTriggered = true;
    this.loadContent();
  }

  private lifecycle = new PageLifecycleManager('UnifiedDetailPage', { enableDebug: true });

  aboutToDisappear(): void {
    // 注意：不要在离开时强制恢复窗口模式，避免前进跳转过程中覆盖目标页沉浸策略。
    // 目标页由各自的页面策略接管；本页在 aboutToAppear/onShown 时重新声明自身模式。
    this.lifecycle.destroy();
    ThemeAwareHelper.cleanupThemeAware(this.componentId);
    FontAwareHelper.cleanupFontAware(this.componentId);
    eventBus.unsubscribe(GameEvent.MANGA_CACHE_UPDATED, this.onMangaCacheUpdated);

    if (this.deviceChangeListener) {
      this.deviceManager.removeListener(this.deviceChangeListener);
      this.deviceChangeListener = null;
    }

    this.webViewControllerAttached = false;
    this.pendingInitialContentLoad = false;
    this.initialContentLoadTriggered = false;
    this.clearOnlineEBookRecoveryTimer();
    this.clearCacheStatusRefreshTimer();
    
    // 取消下载回调注册
    if (this.downloadCallbackRegistered) {
      this.unregisterDownloadCallback();
    }
    
    // 释放封面 PixelMap 资源（仅释放自己拥有的，不释放从 CoverImageManager 借用的）
    if (this.coverPixelMap && this.coverPixelMapOwned) {
      this.coverPixelMap.release();
    }
    this.coverPixelMap = null;
    this.coverPixelMapOwned = false;
  }

  private initializeResponsiveLayout(): void {
    try {
      this.updateResponsiveParams();
      this.deviceChangeListener = (deviceInfo: DeviceInfo) => {
        logger.info(TAG, `设备状态变化: 断点=${deviceInfo.breakpoint}, 方向=${deviceInfo.orientation}`);
        this.updateResponsiveParams();
      };
      this.deviceManager.addListener(this.deviceChangeListener);
    } catch (error) {
      logger.error(TAG, '响应式布局初始化失败', String(error));
    }
  }

  private updateResponsiveParams(): void {
    const layoutParams = ResponsiveLayoutHelper.getLayoutParams();
    const deviceInfo = this.deviceManager.getDeviceInfo();
    this.responsive_contentPadding = layoutParams.contentPadding;
    this.responsive_isLandscape = deviceInfo.isLandscape;
    switch (deviceInfo.breakpoint) {
      case Breakpoint.XS:
        this.responsive_maxContentWidth = 600;
        break;
      case Breakpoint.SM:
        this.responsive_maxContentWidth = 840;
        break;
      case Breakpoint.MD:
        this.responsive_maxContentWidth = 1024;
        break;
      case Breakpoint.LG:
        this.responsive_maxContentWidth = 1200;
        break;
    }
  }

  /**
   * 加载内容数据
   */
  private async loadContent(): Promise<void> {
    if (!this.pageParams) {
      this.errorMessage = '缺少页面参数';
      this.isLoading = false;
      return;
    }

    try {
      this.isLoading = true;
      this.errorMessage = '';
      this.expandedTagChipIds = [];
      this.resolvedDisplaySourceName = '';
      this.isPrimarySectionReady = this.hasRenderablePrimaryContent();

      switch (this.pageParams.contentType) {
        case UnifiedContentType.MANGA:
          await this.loadMangaContent();
          break;
        case UnifiedContentType.EBOOK:
          await this.loadEBookContent();
          break;
        case UnifiedContentType.NOVEL:
          await this.loadNovelContent();
          break;
        default:
          this.errorMessage = '未知的内容类型';
      }

      if (this.content) {
        this.normalizeCurrentContentReadProgress();
        await this.syncCurrentSourceDisplayName();
      }

      // 检查SFW模式
      if (this.content && this.content.isNSFW) {
        const sfwEnabled = ContentFilterManager.getInstance().isSFWModeEnabled();
        if (sfwEnabled) {
          logger.warn(TAG, 'SFW模式已启用，阻止访问NSFW内容');
          this.getUIContext().getPromptAction().showToast({
            message: 'SFW模式已启用，无法查看此内容',
            duration: 2000
          });
          this.pathStack.pop();
          return;
        }
      }
      
      // 加载缓存状态（在线漫画和小说）
      await this.loadCacheStatus();
      this.readAloudCacheLoadSignal++;
      
      // 检查是否已在书架中
      await this.checkIfInShelf();
      this.trackingLoadSignal++;
      
      // 加载同书架内容（非阻塞，仅当在自定义书架中且设置开启时）
      if (this.currentShelfId && this.settingsManager.getBoolean(SettingKeys.SHELF_CONTENT_ENABLED, true)) {
        this.loadShelfContent();
      } else {
        logger.debug(TAG, '同书架内容功能已关闭或不在自定义书架中，跳过加载');
      }
      
      // 触发智能推荐加载（非阻塞，仅当设置开启时）
      if (this.settingsManager.getBoolean(SettingKeys.RECOMMENDATION_ENABLED, true)) {
        this.loadRecommendations();
      } else {
        logger.debug(TAG, '相关推荐功能已关闭，跳过加载');
      }

    } catch (error) {
      logger.error(TAG, '加载内容失败', String(error));
      this.errorMessage = '加载失败，请重试';
    } finally {
      this.isLoading = false;
      this.isPrimarySectionReady = this.hasRenderablePrimaryContent();
    }
  }

  /**
   * 加载漫画内容（使用MangaDetailLoader分阶段加载）
   */
  private async loadMangaContent(): Promise<void> {
    if (!this.pageParams) return;

    let mangaId = this.pageParams.contentId;
    let sourceId = this.pageParams.sourceId;
    logger.info(TAG, `加载漫画内容: mangaId=${mangaId}, sourceId=${sourceId}`);

    // 解析图源名称和包名（优先用 pageParams，fallback 到 SourceManager 查找）
    this.resolvedSourceName = this.normalizeDisplaySourceText(this.pageParams.sourceName);
    this.resolvedSourcePkg = this.pageParams.sourcePkg || '';
    const resolvedMangaSourceName: string = await this.resolveMangaSourceDisplayName(
      sourceId,
      this.resolvedSourcePkg,
      this.resolvedSourceName
    );
    if (resolvedMangaSourceName.length > 0) {
      this.resolvedSourceName = resolvedMangaSourceName;
      this.resolvedDisplaySourceName = resolvedMangaSourceName;
      logger.info(TAG, `图源信息已解析: name=${this.resolvedSourceName}, pkg=${this.resolvedSourcePkg}`);
    }

    let externalMangaId: string = '';
    const identityInput = MangaIdentityResolver.getInstance().buildInput(
      mangaId,
      '',
      sourceId ? Number(sourceId) : -1,
      String(this.pageParams.contentType),
      'UnifiedDetailPage.loadMangaContent'
    );
    identityInput.sourceName = this.resolvedSourceName;
    identityInput.sourcePkg = this.resolvedSourcePkg;
    const identityResult: MangaIdentityResolveResult = await MangaIdentityResolver.getInstance().resolve(identityInput);
    if (identityResult.success) {
      if (identityResult.canonicalMangaId.length > 0 && identityResult.canonicalMangaId !== mangaId) {
        logger.info(TAG, `统一详情页漫画ID已校准: ${mangaId} -> ${identityResult.canonicalMangaId}`);
        mangaId = identityResult.canonicalMangaId;
        this.pageParams.contentId = mangaId;
      }
      if (identityResult.sourceId > 0 && String(identityResult.sourceId) !== String(sourceId || '')) {
        sourceId = String(identityResult.sourceId);
        this.pageParams.sourceId = sourceId;
      }
      if (identityResult.externalMangaId.length > 0) {
        externalMangaId = identityResult.externalMangaId;
      }
    } else {
      logger.warn(TAG, `统一详情页漫画身份未解析，继续使用原始参数: ${identityResult.detail}`);
    }

    // 重置加载状态
    this.isBasicInfoLoaded = false;
    this.isCoverLoading = true;
    this.isChaptersLoading = true;
    this.isPagesPreloading = false;
    this.chaptersLoadProgress = '';

    // 设置WebView控制器
    this.mangaDetailLoader.setWebViewController(this.webViewController);

    // 构建加载参数
    const loadParams: MangaDetailLoadParams = {
      mangaId: mangaId,
      sourceId: sourceId ? Number(sourceId) : undefined,
      sourceName: this.resolvedSourceName || undefined,
      sourcePkg: this.resolvedSourcePkg || undefined,
      cachedTitle: this.pageParams.cachedTitle,
      cachedCoverPath: this.pageParams.cachedCoverPath,
      cachedCover: this.pageParams.cachedCover,
      forceRefresh: false,
      externalMangaId: externalMangaId.length > 0 ? externalMangaId : undefined
    };

    // 构建已读/已下载/书签章节ID集合
    const readChapterIds = new Set<string>();
    const downloadedChapterIds = new Set<string>();
    const bookmarkedChapterIds = new Set<string>();
    let lastReadChapterIndex = -1;

    // 分阶段加载回调
    const progressCallback: MangaLoadProgressCallback = {
      onBasicInfoLoaded: async (manga: Manga, isFavorite: boolean): Promise<void> => {
        logger.info(TAG, `[分阶段] 基本信息已加载: ${manga.title}`);
        this.isFavorite = isFavorite;
        this.isBasicInfoLoaded = true;
        this.isPrimarySectionReady = true;
        this.isLoading = false;  // 基本信息加载完成，停止主加载动画
        
        // 先显示基本信息（无章节）
        this.content = MangaAdapter.toUnifiedContent(
          manga,
          [],  // 章节稍后加载
          isFavorite,
          readChapterIds,
          downloadedChapterIds,
          bookmarkedChapterIds,
          lastReadChapterIndex,
          sourceId,
          this.resolvedSourceName,
          this.resolvedSourcePkg
        );

        // 封面加载完成
        this.isCoverLoading = false;
        
        // 在线漫画：加载本地缓存的封面
        if (sourceId && Number(sourceId) > 0) {
          const coverExternalId: string = this.getOnlineMangaExternalIdForCover(manga, mangaId);
          await this.persistOnlineMangaCoverUrlForMainMenu(coverExternalId, manga.coverImagePath || '');
          void this.loadCachedCover(Number(sourceId), coverExternalId);
        }
      },
      
      onChaptersLoaded: async (chapters: MangaChapter[]) => {
        logger.info(TAG, `[分阶段] 章节已加载: ${chapters.length}章`);
        logger.debug(TAG, `[DEBUG-1] onChaptersLoaded 开始执行`);
        this.isChaptersLoading = false;
        
        // 标记已下载章节
        logger.debug(TAG, `[DEBUG-2] 开始标记已下载章节`);
        chapters.forEach((ch: MangaChapter) => {
          if (ch.isDownloaded) {
            downloadedChapterIds.add(ch.id);
          }
        });
        logger.debug(TAG, `[DEBUG-3] 已下载章节标记完成`);
        
        // 加载章节进度数据
        logger.debug(TAG, `[DEBUG-4] 开始加载章节进度数据`);
        const isOnline = sourceId !== undefined && Number(sourceId) > 0;
        const progressData = await this.mangaDetailLoader.loadChapterProgressData(
          mangaId, 
          chapters, 
          isOnline
        );
        logger.debug(TAG, `[DEBUG-5] 章节进度数据加载完成`);
        
        // 更新已读章节ID集合和最后阅读章节索引
        logger.debug(TAG, `[DEBUG-6] 开始更新已读章节ID集合`);
        progressData.readChapterIds.forEach(id => readChapterIds.add(id));
        lastReadChapterIndex = progressData.lastReadChapterIndex;
        logger.debug(TAG, `[DEBUG-7] lastReadChapterIndex 原始值: ${lastReadChapterIndex}`);
        
        // [修复] 确保 lastReadChapterIndex 在有效范围内
        if (typeof lastReadChapterIndex !== 'number' || isNaN(lastReadChapterIndex)) {
          lastReadChapterIndex = -1;
        } else if (lastReadChapterIndex >= chapters.length) {
          lastReadChapterIndex = -1;
        }
        logger.debug(TAG, `[DEBUG-8] lastReadChapterIndex 验证后: ${lastReadChapterIndex}`);
        
        // 保存章节进度到Map中（用于UI显示）
        logger.debug(TAG, `[DEBUG-9] 开始保存章节进度到Map`);
        const newProgressMap = new Map<string, ChapterProgressInfo>();
        progressData.progressList.forEach((progress: ChapterProgressInfo) => {
          newProgressMap.set(progress.chapterId, progress);
        });
        this.chapterProgressMap = newProgressMap;
        logger.debug(TAG, `[DEBUG-10] 章节进度Map保存完成, 大小: ${newProgressMap.size}`);
        
        // [修复] 安全获取最后阅读章节的信息
        logger.debug(TAG, `[DEBUG-11] 开始安全获取最后阅读章节`);
        let lastReadChapter: MangaChapter | null = null;
        if (lastReadChapterIndex >= 0 && lastReadChapterIndex < chapters.length) {
          lastReadChapter = chapters[lastReadChapterIndex];
        }
        let lastReadProgress: ChapterProgressInfo | null = null;
        if (lastReadChapter !== null) {
          const progress = this.chapterProgressMap.get(lastReadChapter.id);
          if (progress !== undefined) {
            lastReadProgress = progress;
          }
        }
        logger.debug(TAG, `[DEBUG-12] 最后阅读章节获取完成: lastReadChapter=${lastReadChapter !== null ? lastReadChapter.id : 'null'}`);
        
        // 更新内容，添加章节
        logger.debug(TAG, `[DEBUG-13] 检查 this.content: ${this.content !== undefined && this.content !== null}`);
        if (this.content) {
          // 获取原始Manga对象以保留genres等元数据
          logger.debug(TAG, `[DEBUG-14] 开始获取原始Manga`);
          const originalManga = MangaAdapter.getOriginalManga(this.content);
          const finalCoverPath = this.resolveUnifiedCoverImagePath(originalManga);
          const finalCoverSourceType = this.resolveCoverSourceType(finalCoverPath);
          logger.debug(TAG, `[DEBUG-15] 原始Manga获取完成: ${originalManga !== null}`);
          
          logger.debug(TAG, `[DEBUG-16] 开始构建 updatedManga`);
          const updatedManga: Manga = {
            id: this.content.id,
            title: this.content.title,
            alternativeTitles: originalManga?.alternativeTitles || [],
            description: this.content.description,
            coverImagePath: finalCoverPath,
            coverSourceType: finalCoverSourceType,
            status: originalManga?.status || MangaStatus.UNKNOWN,
            metadata: {
              authors: this.content.author ? [this.content.author] : [],
              artists: originalManga?.metadata?.artists || [],
              genres: this.content.genres || originalManga?.metadata?.genres || [],
              themes: this.content.tags || originalManga?.metadata?.themes || [],
              demographics: originalManga?.metadata?.demographics || []
            },
            chapters: chapters,
            readingProgress: {
              currentChapterId: lastReadChapter !== null ? lastReadChapter.id : '',
              currentPageIndex: lastReadProgress !== null ? lastReadProgress.lastReadPageIndex : 0,
              lastReadAt: Date.now(),
              readingStatus: readChapterIds.size > 0 ? ReadingStatus.READING : ReadingStatus.UNREAD,
              totalReadingTime: 0,
              readingPercentage: chapters.length > 0 ? Math.round((readChapterIds.size / chapters.length) * 100) : 0
            },
            bookmarks: originalManga?.bookmarks || [],
            readingSettings: originalManga?.readingSettings || DEFAULT_READING_SETTINGS,
            isFavorite: this.isFavorite,
            lastUpdatedAt: Date.now(),
            isNSFW: this.content.isNSFW || false,
            sourceInfo: originalManga?.sourceInfo
          };
          logger.debug(TAG, `[DEBUG-17] updatedManga 构建完成`);
          
          logger.debug(TAG, `[DEBUG-18] 准备调用 toUnifiedContent, 参数: chapters=${chapters.length}, lastReadChapterIndex=${lastReadChapterIndex}`);
          this.content = MangaAdapter.toUnifiedContent(
            updatedManga,
            chapters,
            this.isFavorite,
            readChapterIds,
            downloadedChapterIds,
            bookmarkedChapterIds,
            lastReadChapterIndex,
            sourceId,
            this.resolvedSourceName,
            this.resolvedSourcePkg
          );
          logger.debug(TAG, `[DEBUG-19] toUnifiedContent 调用完成`);
          
          logger.info(TAG, `章节进度已更新: 已读${readChapterIds.size}章, 最后阅读章节=${lastReadChapterIndex}`);
        }
        logger.debug(TAG, `[DEBUG-20] onChaptersLoaded 回调执行完成`);
      },
      
      onChapterPagesLoaded: (chapterId: string, pageCount: number) => {
        logger.debug(TAG, `[分阶段] 章节页面已加载: ${chapterId}, ${pageCount}页`);
        // 可以在这里更新章节的页数显示
      },
      
      onPagesPreloadProgress: (current: number, total: number) => {
        this.isPagesPreloading = true;
        this.chaptersLoadProgress = `预加载页面 ${current}/${total}`;
        logger.debug(TAG, `[分阶段] 页面预加载进度: ${current}/${total}`);
      },
      
      onPagesPreloadComplete: () => {
        this.isPagesPreloading = false;
        this.chaptersLoadProgress = '';
        logger.info(TAG, `[分阶段] 页面预加载完成`);
      },
      
      onError: (error: string) => {
        logger.error(TAG, `[分阶段] 加载错误: ${error}`);
        this.errorMessage = error;
        this.isLoading = false;
        this.isChaptersLoading = false;
        this.isCoverLoading = false;
      }
    };

    // 使用分阶段加载
    const result = await this.mangaDetailLoader.loadMangaDetailWithProgress(loadParams, progressCallback);

    if (!result.success) {
      logger.error(TAG, `漫画加载失败: ${result.errorMessage}`);
      if (!this.isBasicInfoLoaded) {
        const fallbackApplied: boolean = await this.applyCachedMangaFallbackContent(
          mangaId,
          sourceId,
          readChapterIds,
          downloadedChapterIds,
          bookmarkedChapterIds
        );
        if (!fallbackApplied) {
          this.errorMessage = result.errorMessage || '漫画加载失败';
        }
      }
    } else {
      logger.info(TAG, `漫画内容加载完成: ${this.content?.title}`);
    }
  }

  private async applyCachedMangaFallbackContent(
    mangaId: string,
    sourceId: string | undefined,
    readChapterIds: Set<string>,
    downloadedChapterIds: Set<string>,
    bookmarkedChapterIds: Set<string>
  ): Promise<boolean> {
    if (!this.pageParams || !this.pageParams.cachedManga) {
      return false;
    }

    const cachedManga: Manga = this.pageParams.cachedManga;
    const chapters: MangaChapter[] = cachedManga.chapters || [];
    const isOnline: boolean = sourceId !== undefined && Number(sourceId) > 0;
    let lastReadChapterIndex: number = -1;

    try {
      for (let i: number = 0; i < chapters.length; i++) {
        const chapter = chapters[i];
        if (chapter.isDownloaded) {
          downloadedChapterIds.add(chapter.id);
        }
      }

      if (chapters.length > 0) {
        const progressData = await this.mangaDetailLoader.loadChapterProgressData(
          mangaId,
          chapters,
          isOnline
        );
        progressData.readChapterIds.forEach((id: string) => readChapterIds.add(id));
        const newProgressMap = new Map<string, ChapterProgressInfo>();
        progressData.progressList.forEach((progress: ChapterProgressInfo) => {
          newProgressMap.set(progress.chapterId, progress);
        });
        this.chapterProgressMap = newProgressMap;
        lastReadChapterIndex = progressData.lastReadChapterIndex;
      }
    } catch (error) {
      logger.warn(TAG, `缓存漫画兜底加载进度失败: mangaId=${mangaId}, ${String(error)}`);
    }

    this.content = MangaAdapter.toUnifiedContent(
      cachedManga,
      chapters,
      cachedManga.isFavorite || this.isFavorite,
      readChapterIds,
      downloadedChapterIds,
      bookmarkedChapterIds,
      lastReadChapterIndex,
      sourceId,
      this.resolvedSourceName,
      this.resolvedSourcePkg
    );
    this.isFavorite = cachedManga.isFavorite || this.isFavorite;
    this.isBasicInfoLoaded = true;
    this.isPrimarySectionReady = true;
    this.isLoading = false;
    this.isCoverLoading = false;
    this.isChaptersLoading = false;
    this.errorMessage = '';
    logger.warn(TAG, `已使用导航缓存漫画恢复详情页: mangaId=${mangaId}, title=${cachedManga.title}, chapters=${chapters.length}`);
    return true;
  }

  /**
   * 下拉刷新处理
   */
  private async onRefresh(): Promise<void> {
    if (!this.content || !this.pageParams) {
      this.isRefreshing = false;
      return;
    }
    
    logger.info(TAG, `开始刷新: ${this.content.contentType}`);
    this.isRefreshing = true;
    this.refreshProgress = '正在刷新...';
    
    try {
      switch (this.content.contentType) {
        case UnifiedContentType.MANGA:
          await this.refreshMangaContent();
          break;
        case UnifiedContentType.NOVEL:
          await this.refreshNovelContent();
          break;
        case UnifiedContentType.EBOOK:
          // 电子书是本地文件，不需要刷新
          this.refreshProgress = '电子书无需刷新';
          break;
      }
      
      this.refreshProgress = '刷新完成';
      logger.info(TAG, '刷新完成');
    } catch (error) {
      logger.error(TAG, `刷新失败: ${String(error)}`);
      this.refreshProgress = '刷新失败';
    } finally {
      // 延迟关闭刷新状态，让用户看到结果
      setTimeout(() => {
        this.isRefreshing = false;
        this.refreshProgress = '';
      }, 500);
    }
  }
  
  /**
   * 刷新漫画内容（增量更新）
   */
  private async refreshMangaContent(): Promise<void> {
    if (!this.pageParams || !this.content) return;
    
    const mangaId = this.pageParams.contentId;
    const sourceId = this.pageParams.sourceId;
    
    // 只有在线漫画才需要刷新
    if (!sourceId || Number(sourceId) <= 0) {
      this.refreshProgress = '本地漫画无需刷新';
      return;
    }
    
    this.refreshProgress = '获取最新章节...';
    
    // 设置WebView控制器
    this.mangaDetailLoader.setWebViewController(this.webViewController);
    
    // 构建加载参数，强制刷新
    const loadParams: MangaDetailLoadParams = {
      mangaId: mangaId,
      sourceId: Number(sourceId),
      forceRefresh: true
    };
    
    // 保存当前内容用于增量更新
    const currentChapterCount = this.content.chapters.length;
    const currentChapterIds = new Set(this.content.chapters.map(ch => ch.id));
    
    // 使用分阶段加载刷新
    const progressCallback: MangaLoadProgressCallback = {
      onBasicInfoLoaded: (manga: Manga, isFavorite: boolean) => {
        try {
          this.refreshProgress = '更新基本信息...';
          // 增量更新：只更新有变化的字段
          if (this.content && manga.description && manga.description !== this.content.description) {
            // 更新描述等基本信息
            logger.info(TAG, '更新漫画描述');
          }
        } catch (error) {
          logger.error(TAG, `onBasicInfoLoaded 回调异常: ${String(error)}`);
        }
      },
      
      onChaptersLoaded: (chapters: MangaChapter[]) => {
        try {
          const newChapterCount = chapters.length;
          const addedCount = newChapterCount - currentChapterCount;
          
          if (addedCount > 0) {
            this.refreshProgress = `发现 ${addedCount} 个新章节`;
            logger.info(TAG, `刷新发现 ${addedCount} 个新章节`);
          } else {
            this.refreshProgress = '已是最新';
          }
          
          // 更新章节列表
          if (this.content) {
            const readChapterIds = new Set<string>();
            const downloadedChapterIds = new Set<string>();
            const bookmarkedChapterIds = new Set<string>();
            
            // 保留已有的阅读/下载/书签状态
            this.content.chapters.forEach(ch => {
              if (ch.isRead) readChapterIds.add(ch.id);
              if (ch.isDownloaded) downloadedChapterIds.add(ch.id);
              if (ch.isBookmarked) bookmarkedChapterIds.add(ch.id);
            });
            
            // 获取原始Manga对象并更新章节
            const originalManga = MangaAdapter.getOriginalManga(this.content);
            if (originalManga) {
              originalManga.chapters = chapters;
              
              // 确保 lastReadChapterIndex 在有效范围内
              let safeLastReadIndex = this.content.lastReadChapterIndex;
              if (typeof safeLastReadIndex !== 'number' || isNaN(safeLastReadIndex)) {
                safeLastReadIndex = -1;
              } else if (safeLastReadIndex >= chapters.length) {
                // 如果旧的索引超出新章节列表范围，重置为 -1
                safeLastReadIndex = -1;
              }
              
              this.content = MangaAdapter.toUnifiedContent(
                originalManga,
                chapters,
                this.isFavorite,
                readChapterIds,
                downloadedChapterIds,
                bookmarkedChapterIds,
                safeLastReadIndex,
                this.pageParams?.sourceId,
                this.resolvedSourceName,
                this.resolvedSourcePkg
              );
            }
          }
        } catch (error) {
          logger.error(TAG, `onChaptersLoaded 回调异常: ${String(error)}`);
        }
      },
      
      onError: (error: string) => {
        this.refreshProgress = `刷新失败: ${error}`;
        logger.error(TAG, `刷新漫画失败: ${error}`);
      }
    };
    
    await this.mangaDetailLoader.loadMangaDetailWithProgress(loadParams, progressCallback);
  }
  
  /**
   * 刷新小说内容（增量更新）
   */
  private async refreshNovelContent(): Promise<void> {
    if (!this.pageParams || !this.content) return;
    
    // [修复] 优先使用content.sourceId和content.id（bookUrl），因为loadNovelContent已经从数据库获取了正确的值
    const sourceId = this.content.sourceId || this.pageParams.sourceId || '';
    const bookUrl = this.content.id || this.pageParams.contentId;
    
    if (!sourceId) {
      this.refreshProgress = '缺少图源信息';
      return;
    }
    
    this.refreshProgress = '获取最新章节...';
    
    try {
      // 获取原始小说数据
      const originalBook = NovelAdapter.getOriginalNovel(this.content);
      if (!originalBook) {
        this.refreshProgress = '无法获取小说数据';
        return;
      }
      
      // 从网络获取最新章节列表（需要传递LegadoBook对象）
      const chapters = await this.novelSourceManager.getChapterList(sourceId, originalBook);
      
      if (!chapters || chapters.length === 0) {
        this.refreshProgress = '获取章节失败';
        return;
      }
      
      const currentChapterCount = this.content.chapters.length;
      const newChapterCount = chapters.length;
      const addedCount = newChapterCount - currentChapterCount;
      
      if (addedCount > 0) {
        this.refreshProgress = `发现 ${addedCount} 个新章节`;
        logger.info(TAG, `刷新发现 ${addedCount} 个新章节`);
      } else {
        this.refreshProgress = '已是最新';
      }
      
      // 获取缓存状态（使用与NovelReaderPage一致的bookId格式）
      const novelCacheBookId = this.getNovelCacheBookId(sourceId, bookUrl);
      const cachedIndexes = new Set<number>();
      for (let i = 0; i < chapters.length; i++) {
        const isCached = await this.novelCacheManager.isChapterCached(novelCacheBookId, i);
        if (isCached) {
          cachedIndexes.add(i);
        }
      }
      
      // 更新内容
      this.content = NovelAdapter.toUnifiedContent(
        originalBook,
        chapters,
        this.isFavorite,
        cachedIndexes,
        this.content.lastReadChapterIndex,
        sourceId
      );
    } catch (error) {
      this.refreshProgress = `刷新失败: ${String(error)}`;
      logger.error(TAG, `刷新小说失败: ${String(error)}`);
    }
  }

  /**
   * 加载电子书内容
   */
  private async loadEBookContent(): Promise<void> {
    if (!this.pageParams) return;

    const bookId = this.pageParams.contentId;
    const sourceId = this.pageParams.sourceId;
    logger.info(TAG, `加载电子书内容: bookId=${bookId}, sourceId=${sourceId}`);

    // 判断是在线电子书还是本地电子书
    if (sourceId && sourceId.length > 0) {
      // 在线电子书 - 使用WebView引擎加载
      await this.loadOnlineEBookContent(bookId, sourceId);
    } else {
      // 本地电子书 - 从数据库加载
      await this.loadLocalEBookContent(bookId);
    }
  }

  /**
   * 加载本地电子书内容
   */
  private async loadLocalEBookContent(bookId: string): Promise<void> {
    this.onlineReaderUrl = '';
    this.onlineEBookDetailRequestValue = '';
    this.applyOnlineEBookVerificationInfo(null, false);
    // 重置加载状态
    this.isChaptersLoading = true;
    this.chaptersLoadProgress = '';
    
    // 获取电子书数据
    const ebook = await this.ebookDataManager.getEBookById(bookId);
    if (!ebook) {
      this.errorMessage = '电子书不存在';
      logger.error(TAG, `电子书不存在: ${bookId}`);
      this.isChaptersLoading = false;
      return;
    }

    logger.info(TAG, `电子书加载成功: ${ebook.metadata?.title}, 章节数: ${ebook.chapters?.length || 0}`);

    // 检查收藏状态
    this.isFavorite = ebook.isFavorite || false;

    // 转换为统一模型
    this.content = EBookAdapter.toUnifiedContent(ebook, this.isFavorite);
    logger.info(TAG, `统一模型转换完成: 章节数=${this.content.totalChapters}`);
    
    // 章节加载完成
    this.isPrimarySectionReady = true;
    this.isChaptersLoading = false;

    const extendedData: OnlineEBookExtendedData | null = this.getOnlineEBookExtendedData(ebook.filePath);
    const extendedSourceId: string = this.normalizeTrackingText(extendedData?.sourceId);
    const isOnlineEbook: boolean = this.isHttpUrl(bookId) || extendedSourceId.length > 0;
    if (isOnlineEbook && ebook.filePath) {
      try {
        const sourceId: string = extendedData?.sourceId || '';
        const onlineReaderUrl: string = extendedData?.onlineReaderUrl || '';
        const sourceName: string = await this.resolveMangaSourceDisplayName(
          sourceId,
          extendedData?.sourcePkg,
          extendedData?.sourceName
        );
        this.content.isLocal = false;
        if (sourceId.length > 0) {
          this.content.sourceId = sourceId;
        }
        if (extendedData?.sourcePkg && extendedData.sourcePkg.length > 0) {
          this.content.sourcePkg = extendedData.sourcePkg;
        }
        if (extendedData?.detailRequestValue && extendedData.detailRequestValue.length > 0) {
          this.onlineEBookDetailRequestValue = extendedData.detailRequestValue;
        }
        this.applyOnlineEBookVerificationInfo(this.extractOnlineEBookVerificationInfo(extendedData), false);
        if (sourceName.length > 0) {
          this.resolvedDisplaySourceName = sourceName;
          this.content.sourceName = sourceName;
        }
        
        logger.info(TAG, `检测到在线电子书，sourceId=${sourceId}, onlineReaderUrl=${onlineReaderUrl.substring(0, 50)}...`);
        
        if (onlineReaderUrl) {
          // 直接使用存储的onlineReaderUrl
          this.onlineReaderUrl = onlineReaderUrl;
          logger.info(TAG, `从存储中恢复在线阅读器URL`);
        } else if (sourceId) {
          // 如果没有存储onlineReaderUrl，则重新获取
          this.loadOnlineReaderUrl(bookId, sourceId);
        }
      } catch (e) {
        logger.warn(TAG, `解析在线电子书扩展数据失败: ${e}`);
      }
    }
  }

  /**
   * 加载在线电子书内容
   */
  private async loadOnlineEBookContent(bookId: string, sourceId: string, retryAttempt: number = 0): Promise<void> {
    logger.info(TAG, `加载在线电子书: bookId=${bookId}, sourceId=${sourceId}`);
    if (retryAttempt === 0) {
      this.onlineReaderUrl = '';
      this.onlineEBookDetailRequestValue = '';
      this.endOnlineEBookRecovery();
      this.applyOnlineEBookVerificationInfo(null, false);
    }
    
    // 重置加载状态
    this.isBasicInfoLoaded = false;
    this.isCoverLoading = true;
    this.isChaptersLoading = true;
    
    try {
      // 加载图源信息
      const sources = await this.sourceManager.getAllSources();
      this.ebookSourceInfo = sources.find((s: SourceInfo) => s.id === Number(sourceId)) || null;
      
      if (!this.ebookSourceInfo) {
        this.errorMessage = '图源不存在';
        logger.error(TAG, `图源不存在: ${sourceId}`);
        this.isChaptersLoading = false;
        return;
      }
      
      logger.info(TAG, `图源信息加载完成: ${this.ebookSourceInfo.name}`);
      
      // 先设置缓存的基本信息
      const cachedTitle = this.pageParams?.cachedTitle || '未知书名';
      const cachedCover = this.pageParams?.cachedCoverPath || this.pageParams?.cachedCover || '';
      
      // 创建初始的UnifiedContent
      const emptyGenres: string[] = [];
      const emptyTags: string[] = [];
      const emptyChapters: UnifiedChapter[] = [];
      const emptyOriginalData: Object = new Object();
      const initialContent: UnifiedContent = {
        id: bookId,
        title: cachedTitle,
        coverUrl: cachedCover,
        author: '',
        description: '',
        contentType: UnifiedContentType.EBOOK,
        genres: emptyGenres,
        tags: emptyTags,
        readStatus: UnifiedReadStatus.UNREAD,
        isFavorite: false,
        isNSFW: false,
        totalChapters: 0,
        readChapters: 0,
        lastReadChapterIndex: -1,
        lastReadChapterTitle: '',
        readProgress: 0,
        sourceId: sourceId,
        sourceName: this.ebookSourceInfo.name,
        sourcePkg: this.ebookSourceInfo.pkg,
        isLocal: false,
        remoteVerificationInfo: this.onlineEBookVerificationInfo || undefined,
        chapters: emptyChapters,
        originalData: emptyOriginalData,
        originalType: UnifiedContentType.EBOOK
      };
      this.content = initialContent;
      
      this.isBasicInfoLoaded = true;
      this.isCoverLoading = false;
      this.isLoading = false;
      
      // 初始化WebView引擎并获取详情
      await this.initializeEBookWebViewEngine(Number(sourceId));
      
      if (this.ebookSourceEngine && this.ebookWebViewReady) {
        const extendedData: OnlineEBookExtendedData | null = this.getOnlineEBookExtendedData(this.content?.filePath);
        const detailRequestValue: string = await this.resolveOnlineEBookDetailRequestValue(
          bookId,
          sourceId,
          this.ebookSourceInfo,
          extendedData
        );
        this.onlineEBookDetailRequestValue = detailRequestValue;
        logger.info(TAG, `使用WebView获取电子书详情: bookId=${bookId}, detailRequestValue=${detailRequestValue}`);
        const result = await this.ebookSourceEngine.getBookDetail(detailRequestValue);
        
        if (result.success && result.data) {
          const detail = result.data as OnlineEBookDetailRecord;
          if (this.isInvalidOnlineEBookDetailResult(detail, this.ebookSourceInfo)) {
            logger.warn(TAG, `在线电子书详情命中非目标页面，跳过覆盖: id=${String(detail.id || '')}, title=${String(detail.title || '')}`);
            const verificationState: OnlineEBookVerificationState = await this.getOnlineEBookVerificationState();
            const verificationInfo: RemoteVerificationInfo = this.buildOnlineEBookVerificationInfo(
              verificationState.isVerifyEntry ? 'verify_entry' : 'failed',
              verificationState.cooldownText.length > 0 ? `站点安全验证冷却中：${verificationState.cooldownText}` : '站点返回了安全验证页面',
              verificationState.url,
              verificationState.title,
              verificationState.cooldownText,
              this.parseCooldownTextToSeconds(verificationState.cooldownText),
              verificationState.canRetryVerification,
              retryAttempt
            );
            this.applyOnlineEBookVerificationInfo(verificationInfo, true);
            if (retryAttempt < this.onlineEBookRecoveryMaxAttempts) {
              void this.retryOnlineEBookDetailAfterVerification(bookId, sourceId, retryAttempt + 1);
              return;
            }
            this.endOnlineEBookRecovery();
            this.refreshProgress = '站点仍在安全验证中，请稍后下拉刷新。';
            if (this.content) {
              this.content.description = '站点仍在安全验证中，请稍后下拉刷新。';
            }
            this.isChaptersLoading = false;
            return;
          }
          this.applyOnlineEBookVerificationInfo(null, true);
          this.endOnlineEBookRecovery();
          logger.info(TAG, `电子书详情获取成功: ${JSON.stringify(detail).substring(0, 200)}`);
          
          // 更新内容
          if (this.content) {
            this.content.title = String(detail.title || cachedTitle);
            this.content.author = String(detail.author || '');
            this.content.description = String(detail.description || '');
            this.content.coverUrl = String(detail.cover || cachedCover);
            if (detail.categories) {
              this.content.genres = [String(detail.categories)];
            }
            if (detail.tags) {
              this.content.tags = [String(detail.tags)];
            }
          }
          
          // 保存在线阅读器URL
          const readerUrlValue: string = String(detail.readerUrl || '');
          logger.info(TAG, `readerUrl字段值: ${readerUrlValue.substring(0, 80)}`);
          if (readerUrlValue && readerUrlValue.length > 0) {
            this.onlineReaderUrl = readerUrlValue;
            logger.info(TAG, `获取到在线阅读器URL: ${this.onlineReaderUrl.substring(0, 80)}...`);
          } else {
            logger.warn(TAG, '未获取到在线阅读器URL');
          }
          
          logger.info(TAG, `在线电子书详情加载成功: ${this.content?.title}`);
        } else {
          logger.warn(TAG, `获取电子书详情失败: ${result.error}`);
        }
      } else {
        logger.warn(TAG, 'WebView引擎未就绪，使用缓存数据');
      }
      
      this.isChaptersLoading = false;
      
    } catch (error) {
      logger.error(TAG, `加载在线电子书失败: ${String(error)}`);
      this.errorMessage = `加载失败: ${String(error)}`;
    }
  }

  /**
   * 加载在线阅读器URL（用于已收藏的在线电子书）
   */
  private async loadOnlineReaderUrl(bookId: string, sourceId: string, retryAttempt: number = 0): Promise<void> {
    try {
      // 加载图源信息
      const sources = await this.sourceManager.getAllSources();
      const sourceInfo = sources.find((s: SourceInfo) => s.id === Number(sourceId)) || null;
      
      if (!sourceInfo) {
        logger.warn(TAG, `图源不存在: ${sourceId}`);
        return;
      }

      // 初始化WebView引擎
      await this.initializeEBookWebViewEngine(Number(sourceId));
      
      if (this.ebookWebViewReady && this.ebookSourceEngine) {
        const extendedData: OnlineEBookExtendedData | null = this.getOnlineEBookExtendedData(this.content?.filePath);
        const detailRequestValue: string = await this.resolveOnlineEBookDetailRequestValue(
          bookId,
          sourceId,
          sourceInfo,
          extendedData
        );
        this.onlineEBookDetailRequestValue = detailRequestValue;
        const result = await this.ebookSourceEngine.getBookDetail(detailRequestValue);
        
        if (result.success && result.data) {
          const detail = result.data as OnlineEBookDetailRecord;
          if (this.isInvalidOnlineEBookDetailResult(detail, sourceInfo)) {
            logger.warn(TAG, `加载在线阅读器URL命中非目标页面，跳过: id=${String(detail.id || '')}, title=${String(detail.title || '')}`);
            if (retryAttempt < this.onlineEBookRecoveryMaxAttempts) {
              void this.loadOnlineReaderUrl(bookId, sourceId, retryAttempt + 1);
            }
            return;
          }
          const readerUrlValue: string = String(detail.readerUrl || '');
          if (readerUrlValue && readerUrlValue.length > 0) {
            this.onlineReaderUrl = readerUrlValue;
            logger.info(TAG, `获取到在线阅读器URL: ${this.onlineReaderUrl.substring(0, 80)}...`);
          }
        }
      }
    } catch (error) {
      logger.error(TAG, `加载在线阅读器URL失败: ${String(error)}`);
    }
  }

  /**
   * 初始化电子书WebView引擎
   */
  private async initializeEBookWebViewEngine(sourceId: number): Promise<void> {
    try {
      // 获取图源配置
      const sourceConfig = await this.dataManager.getSourceConfig(sourceId) as Record<string, Object> | null;
      if (!sourceConfig) {
        logger.warn(TAG, '无法获取图源配置');
        return;
      }
      
      // 将配置对象序列化为JSON字符串
      const configJson = JSON.stringify(sourceConfig);
      
      // 初始化WebView引擎
      const engineConfig: EngineConfig = {
        webViewController: this.webViewController,
        antiCrawlerConfig: {} as AntiCrawlerConfig,
        debug: false,
        timeout: 30000,
        caseSensitive: false,
        sourceId: sourceId
      };
      this.ebookSourceEngine = new MangaSourceEngine(engineConfig);
      await this.webViewAuthManager.applyCookiesToController(sourceId, this.webViewController);
      
      const loadResult = await this.ebookSourceEngine.loadConfig(configJson, true);
      if (!loadResult.success) {
        logger.error(TAG, `加载图源配置失败: ${loadResult.error}`);
        return;
      }
      
      this.ebookWebViewReady = true;
      logger.info(TAG, '电子书WebView引擎初始化成功（跳过initialize工作流）');
    } catch (error) {
      logger.error(TAG, `初始化电子书WebView引擎失败: ${String(error)}`);
    }
  }

  /**
   * 加载小说内容
   */
  private async loadNovelContent(): Promise<void> {
    if (!this.pageParams) return;

    // 重置加载状态
    this.isChaptersLoading = true;
    this.chaptersLoadProgress = '';

    const sourceId = this.pageParams.sourceId || '';
    const bookUrl = this.pageParams.contentId;
    let enableDirectoryParsing = true;
    let enableReplaceRules = true;
    
    logger.debug(TAG, `loadNovelContent: sourceId=${sourceId}, bookUrl=${bookUrl}`);
    try {
      const context = (this.getUIContext().getHostContext() as common.UIAbilityContext) as common.UIAbilityContext;
      const store = await preferences.getPreferences(context, NOVEL_SETTINGS_STORE);
      enableDirectoryParsing = await store.get(NOVEL_SETTING_ENABLE_DIRECTORY_PARSING, true) as boolean;
      enableReplaceRules = await store.get(NOVEL_SETTING_ENABLE_REPLACE_RULES, true) as boolean;
    } catch (error) {
      logger.warn(TAG, `加载目录解析设置失败，使用默认值: ${String(error)}`);
      enableDirectoryParsing = true;
      enableReplaceRules = true;
    }
    const chapterListCacheHours = enableDirectoryParsing ? 24 : 36500;

    // 优先从数据库获取书籍信息（尝试多种查询方式）
    let bookInDb = await this.novelDataManager.getBookByUrl(sourceId, bookUrl);
    
    // 如果按 sourceId + bookUrl 查询不到，尝试直接按 ID 查询
    if (!bookInDb) {
      // 尝试直接用 bookUrl 作为 ID 查询（可能传入的是 novel.id 格式）
      bookInDb = await this.novelDataManager.getBook(bookUrl);
      logger.debug(TAG, `尝试按ID查询: ${bookUrl}, 结果: ${bookInDb ? '找到' : '未找到'}`);
    }
    
    // 如果还是查不到，尝试构建 ID 来查询
    if (!bookInDb && sourceId) {
      const constructedId = this.getNovelCacheBookId(sourceId, bookUrl);
      bookInDb = await this.novelDataManager.getBook(constructedId);
      logger.debug(TAG, `尝试按构建ID查询: ${constructedId}, 结果: ${bookInDb ? '找到' : '未找到'}`);
    }
    
    // 重要：如果通过任何方式找到了书籍，使用数据库中的正确 sourceId 和 bookUrl
    // 这确保后续加载章节等操作使用正确的值
    let actualSourceId = sourceId;
    let actualBookUrl = bookUrl;
    if (bookInDb) {
      actualSourceId = bookInDb.sourceId || sourceId;
      actualBookUrl = bookInDb.bookUrl || bookUrl;
      logger.debug(TAG, `使用数据库中的值: sourceId=${actualSourceId}, bookUrl=${actualBookUrl}`);
    }
    
    let book: LegadoBook | null = null;
    let chapters: LegadoChapter[] = [];
    
    // 换源模式：强制从网络加载并保存
    const shouldForceNetworkLoad = this.isFromChangeSource;

    if (bookInDb && !shouldForceNetworkLoad) {
      // 数据库中有书籍信息，尝试从缓存获取章节
      logger.info(TAG, `从数据库加载小说: ${bookInDb.name}`);
      
      // 使用缓存的书籍信息构建LegadoBook
      book = {
        id: bookInDb.id,
        origin: actualSourceId,
        originName: this.resolveNovelSourceDisplayName(actualSourceId, bookInDb.sourceName, actualBookUrl) || bookInDb.sourceName,
        bookUrl: bookInDb.bookUrl,
        name: bookInDb.name,
        author: bookInDb.author,
        kind: bookInDb.kind,
        intro: bookInDb.intro,
        coverUrl: bookInDb.coverLocalPath || bookInDb.coverUrl,
        tocUrl: bookInDb.tocUrl,
        latestChapterTitle: bookInDb.latestChapterTitle,
        wordCount: bookInDb.wordCount,
        type: this.getNovelSourceTypeById(actualSourceId, actualBookUrl)
      } as LegadoBook;

      // 优先从缓存获取章节列表（缓存时效由小说设置控制）
      chapters = await this.novelCacheManager.getCachedChapterList(actualBookUrl, chapterListCacheHours) || [];
      
      if (chapters.length === 0) {
        // 缓存不存在或已过期，从网络获取
        try {
          chapters = await this.novelSourceManager.getChapterList(actualSourceId, book);
          // 保存章节列表到缓存
          if (chapters.length > 0) {
            await this.novelCacheManager.saveChapterList(actualBookUrl, chapters);
          }
        } catch (error) {
          logger.warn(TAG, `获取章节列表失败: ${String(error)}`);
          chapters = [];
        }
      }
    } else {
      // 数据库中没有（或换源模式强制从网络加载）
      // 换源模式下使用原始sourceId（不是actualSourceId）
      const loadSourceId = shouldForceNetworkLoad ? sourceId : actualSourceId;
      const loadBookUrl = shouldForceNetworkLoad ? bookUrl : actualBookUrl;
      
      logger.info(TAG, `从网络加载小说: ${loadBookUrl}, 换源模式=${shouldForceNetworkLoad}`);
      book = await this.novelSourceManager.getBookInfo(loadSourceId, loadBookUrl);
      if (!book) {
        this.errorMessage = '小说不存在';
        this.isChaptersLoading = false;
        return;
      }

      // 获取章节列表
      try {
        chapters = await this.novelSourceManager.getChapterList(loadSourceId, book);
        // 保存章节列表到缓存（避免下次重新加载）
        if (chapters.length > 0) {
          await this.novelCacheManager.saveChapterList(loadBookUrl, chapters);
        }
      } catch (error) {
        logger.warn(TAG, `获取章节列表失败: ${String(error)}`);
        chapters = [];
      }
      
      // 获取书源名称
      let sourceName = '';
      try {
        const sourceInfo: LegadoBookSource | null = this.novelSourceManager.getSource(loadSourceId);
        sourceName = sourceInfo?.bookSourceName || '';
      } catch (e) {
        logger.warn(TAG, `获取书源名称失败: ${String(e)}`);
      }

      // 保存小说信息到数据库（持久化缓存）
      try {
        const novelBook: NovelBook = {
          id: this.getNovelCacheBookId(loadSourceId, book.bookUrl),
          sourceId: loadSourceId,
          sourceName: sourceName,
          bookUrl: book.bookUrl,
          name: book.name || '未知书名',
          author: book.author || '未知作者',
          kind: book.kind,
          intro: book.intro,
          coverUrl: book.coverUrl,
          tocUrl: book.tocUrl,
          latestChapterTitle: book.latestChapterTitle,
          wordCount: book.wordCount,
          chapterCount: chapters.length,
          readStatus: NovelReadStatus.UNREAD,
          totalReadingTime: 0,
          isFavorite: false,
          createTime: Date.now(),
          updateDbTime: Date.now()
        };
        await this.novelDataManager.saveBook(novelBook);
        logger.info(TAG, `小说信息已保存到数据库: ${book.name}, 书源: ${sourceName}`);
        // 更新bookInDb引用
        bookInDb = novelBook;
        
        // 换源模式下更新actualSourceId和actualBookUrl
        if (shouldForceNetworkLoad) {
          actualSourceId = loadSourceId;
          actualBookUrl = loadBookUrl;
        }
      } catch (error) {
        logger.warn(TAG, `保存小说信息失败: ${String(error)}`);
      }
    }

    // 获取缓存状态（使用与NovelReaderPage一致的bookId格式）
    const novelCacheBookId = this.getNovelCacheBookId(actualSourceId, actualBookUrl);
    const cachedIndexes = new Set<number>();
    for (let i = 0; i < chapters.length; i++) {
      const isCached = await this.novelCacheManager.isChapterCached(novelCacheBookId, i);
      if (isCached) {
        cachedIndexes.add(i);
      }
    }

    // 获取阅读进度（使用之前已查询的bookInDb）
    const lastReadIndex = bookInDb?.lastReadChapterIndex ?? -1;

    // 检查收藏状态
    this.isFavorite = bookInDb?.isFavorite || false;

    // 转换为统一模型
    this.content = NovelAdapter.toUnifiedContent(
      book,
      chapters,
      this.isFavorite,
      cachedIndexes,
      lastReadIndex,
      actualSourceId
    );
    const ruleScopeId = this.getNovelCacheBookId(actualSourceId, actualBookUrl);
    const scopedTocRuleIds = await this.getScopedRuleIds(ruleScopeId, this.buildBookTocRuleKey(ruleScopeId));
    const scopedReplaceRuleIds = await this.getScopedRuleIds(ruleScopeId, this.buildBookReplaceRuleKey(ruleScopeId));
    const selectedTocRuleIds: string[] = scopedTocRuleIds !== null ? scopedTocRuleIds : [];
    const selectedReplaceRuleIds: string[] = scopedReplaceRuleIds !== null ? scopedReplaceRuleIds : [];
    logger.info(
      TAG,
      `小说规则生效: scopeId=${ruleScopeId}, scopedToc=${scopedTocRuleIds === null ? 'default' : scopedTocRuleIds.length}, scopedReplace=${scopedReplaceRuleIds === null ? 'default' : scopedReplaceRuleIds.length}`
    );
    await this.applyDirectoryRulesToCurrentContent(enableDirectoryParsing, selectedTocRuleIds);
    await this.applyReplaceRulesToCurrentNovelContent(enableReplaceRules, scopedReplaceRuleIds);
    
    // 章节加载完成
    this.isPrimarySectionReady = true;
    this.isChaptersLoading = false;
  }

  private buildBookTocRuleKey(scopeId: string): string {
    return `${NOVEL_BOOK_TOC_RULE_IDS_PREFIX}${scopeId}`;
  }

  private buildBookReplaceRuleKey(scopeId: string): string {
    return `${NOVEL_BOOK_REPLACE_RULE_IDS_PREFIX}${scopeId}`;
  }

  private parseRuleIdArray(rawValue: string): string[] {
    if (!rawValue || rawValue.length === 0) {
      return [];
    }
    try {
      const parsed = SafeUtils.parseArr(rawValue) as Array<string>;
      if (!Array.isArray(parsed)) {
        return [];
      }
      const result: string[] = [];
      for (const item of parsed) {
        if (typeof item === 'string' && item.length > 0) {
          result.push(item);
        }
      }
      return result;
    } catch (error) {
      logger.warn(TAG, `解析规则ID数组失败: ${String(error)}`);
      return [];
    }
  }

  private async getScopedRuleIds(scopeId: string, key: string): Promise<string[] | null> {
    if (scopeId.length === 0) {
      return null;
    }
    try {
      const context = (this.getUIContext().getHostContext() as common.UIAbilityContext) as common.UIAbilityContext;
      const store = await preferences.getPreferences(context, NOVEL_BOOK_RULE_SETTINGS_STORE);
      const raw = await store.get(key, '') as string;
      if (!raw || raw.length === 0) {
        return null;
      }
      return this.parseRuleIdArray(raw);
    } catch (error) {
      logger.warn(TAG, `读取书籍规则失败: key=${key}, error=${String(error)}`);
      return null;
    }
  }

  private async applyDirectoryRulesToCurrentContent(enableDirectoryParsing: boolean, selectedTocRuleIds: string[]): Promise<void> {
    if (!this.content || this.content.contentType !== UnifiedContentType.NOVEL || !enableDirectoryParsing) {
      return;
    }
    if (selectedTocRuleIds.length === 0) {
      return;
    }
    const tocRuleManager = getNovelTxtTocRuleManager();
    await tocRuleManager.initialize();
    const regexList: RegExp[] = [];
    for (const ruleId of selectedTocRuleIds) {
      const rule = tocRuleManager.getRule(ruleId);
      if (!rule || !rule.rule) {
        continue;
      }
      try {
        regexList.push(new RegExp(rule.rule, 'm'));
      } catch (error) {
        logger.warn(TAG, `目录规则无效正则: id=${ruleId}, error=${String(error)}`);
      }
    }
    if (regexList.length === 0) {
      return;
    }
    const currentContent = this.content;
    const nextChapters: UnifiedChapter[] = [];
    let matchedCount = 0;
    let changedCount = 0;
    for (const chapter of currentContent.chapters) {
      const baseTitle = chapter.title || '';
      let nextTitle = baseTitle;
      for (const regex of regexList) {
        regex.lastIndex = 0;
        const matched = regex.exec(baseTitle);
        if (matched && matched[0]) {
          matchedCount += 1;
          nextTitle = matched[0].trim();
          break;
        }
      }
      if (nextTitle !== baseTitle) {
        changedCount += 1;
      }
      const updatedChapter: UnifiedChapter = {
        id: chapter.id,
        title: nextTitle,
        index: chapter.index,
        isRead: chapter.isRead,
        isDownloaded: chapter.isDownloaded,
        isBookmarked: chapter.isBookmarked,
        pageCount: chapter.pageCount,
        wordCount: chapter.wordCount,
        publishDate: chapter.publishDate,
        originalData: chapter.originalData,
        originalType: chapter.originalType
      };
      nextChapters.push(updatedChapter);
    }
    if (changedCount <= 0) {
      logger.info(TAG, `目录规则已应用: 匹配章节=${matchedCount}, 标题变化=${changedCount}`);
      return;
    }
    this.content = {
      id: currentContent.id,
      title: currentContent.title,
      coverUrl: currentContent.coverUrl,
      author: currentContent.author,
      description: currentContent.description,
      contentType: currentContent.contentType,
      genres: currentContent.genres,
      tags: currentContent.tags,
      readStatus: currentContent.readStatus,
      isFavorite: currentContent.isFavorite,
      isNSFW: currentContent.isNSFW,
      totalChapters: currentContent.totalChapters,
      readChapters: currentContent.readChapters,
      lastReadChapterIndex: currentContent.lastReadChapterIndex,
      lastReadChapterTitle: currentContent.lastReadChapterTitle,
      lastReadTime: currentContent.lastReadTime,
      readProgress: currentContent.readProgress,
      sourceId: currentContent.sourceId,
      sourceName: currentContent.sourceName,
      sourcePkg: currentContent.sourcePkg,
      sourceUrl: currentContent.sourceUrl,
      isLocal: currentContent.isLocal,
      remoteVerificationInfo: currentContent.remoteVerificationInfo,
      publisher: currentContent.publisher,
      publishDate: currentContent.publishDate,
      isbn: currentContent.isbn,
      fileSize: currentContent.fileSize,
      filePath: currentContent.filePath,
      format: currentContent.format,
      chapters: nextChapters,
      originalData: currentContent.originalData,
      originalType: currentContent.originalType
    };
    logger.info(TAG, `目录规则已应用: 匹配章节=${matchedCount}, 标题变化=${changedCount}`);
  }

  private async applyReplaceRulesToCurrentNovelContent(
    enableReplaceRules: boolean,
    selectedRuleIds: string[] | null = null
  ): Promise<void> {
    if (!this.content) {
      return;
    }
    if (this.isLocalImportedEBookContent()) {
      await this.applyReplaceRulesToCurrentEBookContent(enableReplaceRules, selectedRuleIds);
      return;
    }
    if (this.content.contentType !== UnifiedContentType.NOVEL) {
      return;
    }
    const sourceId = this.content.sourceId || this.pageParams?.sourceId;
    const originalNovel = NovelAdapter.getOriginalNovel(this.content);
    if (!originalNovel) {
      return;
    }
    if (enableReplaceRules) {
      const replaceRuleManager = NovelReplaceRuleManager.getInstance();
      await replaceRuleManager.initialize();
      await replaceRuleManager.refreshRules();
    }
    const contentProcessor = getNovelContentProcessor();
    const baseDescription = originalNovel.intro || this.content.description;
    const scopedRuleIds = selectedRuleIds === null ? undefined : selectedRuleIds;
    const nextDescription = enableReplaceRules
      ? contentProcessor.quickReplace(baseDescription, ReplaceScope.CONTENT, sourceId, scopedRuleIds)
      : baseDescription;

    const nextChapters: UnifiedChapter[] = [];
    for (const chapter of this.content.chapters) {
      const originalChapter = NovelAdapter.getOriginalChapter(chapter);
      if (!originalChapter) {
        nextChapters.push(chapter);
        continue;
      }
      const baseTitle = originalChapter.title || chapter.title;
      const nextTitle = enableReplaceRules
        ? contentProcessor.processTitle(baseTitle, sourceId, scopedRuleIds)
        : baseTitle;
      const updatedChapter: UnifiedChapter = {
        id: chapter.id,
        title: nextTitle,
        index: chapter.index,
        isRead: chapter.isRead,
        isDownloaded: chapter.isDownloaded,
        isBookmarked: chapter.isBookmarked,
        pageCount: chapter.pageCount,
        wordCount: chapter.wordCount,
        publishDate: chapter.publishDate,
        originalData: chapter.originalData,
        originalType: chapter.originalType
      };
      nextChapters.push(updatedChapter);
    }
    let nextLastReadChapterTitle = this.content.lastReadChapterTitle;
    if (this.content.lastReadChapterIndex >= 0 && this.content.lastReadChapterIndex < nextChapters.length) {
      nextLastReadChapterTitle = nextChapters[this.content.lastReadChapterIndex].title;
    }
    const currentContent = this.content;
    this.content = {
      id: currentContent.id,
      title: currentContent.title,
      coverUrl: currentContent.coverUrl,
      author: currentContent.author,
      description: nextDescription,
      contentType: currentContent.contentType,
      genres: currentContent.genres,
      tags: currentContent.tags,
      readStatus: currentContent.readStatus,
      isFavorite: currentContent.isFavorite,
      isNSFW: currentContent.isNSFW,
      totalChapters: currentContent.totalChapters,
      readChapters: currentContent.readChapters,
      lastReadChapterIndex: currentContent.lastReadChapterIndex,
      lastReadChapterTitle: nextLastReadChapterTitle,
      lastReadTime: currentContent.lastReadTime,
      readProgress: currentContent.readProgress,
      sourceId: currentContent.sourceId,
      sourceName: currentContent.sourceName,
      sourcePkg: currentContent.sourcePkg,
      sourceUrl: currentContent.sourceUrl,
      isLocal: currentContent.isLocal,
      remoteVerificationInfo: currentContent.remoteVerificationInfo,
      publisher: currentContent.publisher,
      publishDate: currentContent.publishDate,
      isbn: currentContent.isbn,
      fileSize: currentContent.fileSize,
      filePath: currentContent.filePath,
      format: currentContent.format,
      chapters: nextChapters,
      originalData: currentContent.originalData,
      originalType: currentContent.originalType
    };
  }

  private async applyReplaceRulesToCurrentEBookContent(
    enableReplaceRules: boolean,
    selectedRuleIds: string[] | null = null
  ): Promise<void> {
    if (!this.content) {
      return;
    }
    const ebook = EBookAdapter.getOriginalEBook(this.content);
    if (!ebook) {
      return;
    }
    if (enableReplaceRules) {
      const replaceRuleManager = NovelReplaceRuleManager.getInstance();
      await replaceRuleManager.initialize();
      await replaceRuleManager.refreshRules();
    }
    const contentProcessor = getNovelContentProcessor();
    const scopedRuleIds = selectedRuleIds === null ? undefined : selectedRuleIds;
    const nextDescription = enableReplaceRules
      ? contentProcessor.quickReplace(ebook.metadata?.description || this.content.description, ReplaceScope.CONTENT, '', scopedRuleIds)
      : (ebook.metadata?.description || this.content.description);

    const nextChapters: UnifiedChapter[] = [];
    for (const chapter of this.content.chapters) {
      const baseTitle = chapter.title || '';
      const nextTitle = enableReplaceRules
        ? contentProcessor.processTitle(baseTitle, '', scopedRuleIds)
        : baseTitle;
      const updatedChapter: UnifiedChapter = {
        id: chapter.id,
        title: nextTitle,
        index: chapter.index,
        isRead: chapter.isRead,
        isDownloaded: chapter.isDownloaded,
        isBookmarked: chapter.isBookmarked,
        pageCount: chapter.pageCount,
        wordCount: chapter.wordCount,
        publishDate: chapter.publishDate,
        originalData: chapter.originalData,
        originalType: chapter.originalType
      };
      nextChapters.push(updatedChapter);
    }
    let nextLastReadChapterTitle = this.content.lastReadChapterTitle;
    if (this.content.lastReadChapterIndex >= 0 && this.content.lastReadChapterIndex < nextChapters.length) {
      nextLastReadChapterTitle = nextChapters[this.content.lastReadChapterIndex].title;
    }
    const currentContent = this.content;
    this.content = {
      id: currentContent.id,
      title: currentContent.title,
      coverUrl: currentContent.coverUrl,
      author: currentContent.author,
      description: nextDescription,
      contentType: currentContent.contentType,
      genres: currentContent.genres,
      tags: currentContent.tags,
      readStatus: currentContent.readStatus,
      isFavorite: currentContent.isFavorite,
      isNSFW: currentContent.isNSFW,
      totalChapters: currentContent.totalChapters,
      readChapters: currentContent.readChapters,
      lastReadChapterIndex: currentContent.lastReadChapterIndex,
      lastReadChapterTitle: nextLastReadChapterTitle,
      lastReadTime: currentContent.lastReadTime,
      readProgress: currentContent.readProgress,
      sourceId: currentContent.sourceId,
      sourceName: currentContent.sourceName,
      sourcePkg: currentContent.sourcePkg,
      sourceUrl: currentContent.sourceUrl,
      isLocal: currentContent.isLocal,
      publisher: currentContent.publisher,
      publishDate: currentContent.publishDate,
      isbn: currentContent.isbn,
      fileSize: currentContent.fileSize,
      filePath: currentContent.filePath,
      format: currentContent.format,
      chapters: nextChapters,
      originalData: currentContent.originalData,
      originalType: currentContent.originalType
    };
  }

  /**
   * 开始阅读
   */
  private startReading(chapterIndex: number): void {
    if (!this.content || !this.pageParams) return;

    const chapter = this.content.chapters[chapterIndex];
    if (!chapter) return;

    switch (this.content.contentType) {
      case UnifiedContentType.MANGA:
        this.openMangaReader(chapterIndex);
        break;
      case UnifiedContentType.EBOOK:
        this.openEBookReader(chapterIndex);
        break;
      case UnifiedContentType.NOVEL:
        this.openNovelReader(chapterIndex);
        break;
      }
  }

  private getShelfButtonLabel(): string {
    if (this.isShelfActionPending) {
      return '处理中...';
    }
    if (!this.isInShelf) {
      return '添加书架';
    }
    return this.currentShelfName ? `在「${this.currentShelfName}」书架中` : '在书架中';
  }

  private hasReadingRecord(): boolean {
    if (!this.content) return false;
    const lastIndex = this.content.lastReadChapterIndex;
    return lastIndex >= 0 && lastIndex < this.content.chapters.length;
  }

  private getReadButtonLabel(): string {
    if (this.isOpeningOnlineEBookDownloadDetail) {
      return '正在准备下载...';
    }
    if (this.isCurrentNovelAudioSource()) {
      return this.hasReadingRecord() ? '继续听书' : '开始听书';
    }
    // 在线电子书显示"下载后阅读"
    if (this.content && this.content.contentType === UnifiedContentType.EBOOK && !this.content.isLocal) {
      return this.isOnlineEBookRecoveryInProgress ? '站点验证中...' : '下载后阅读';
    }
    return this.hasReadingRecord() ? '继续阅读' : '开始阅读';
  }

  private getReadAloudButtonLabel(): string {
    return this.hasReadingRecord() ? '继续听书' : '开始听书';
  }

  private canShowReadAloudButton(): boolean {
    if (!this.content) {
      return false;
    }
    if (this.isCurrentNovelAudioSource()) {
      return false;
    }
    return this.content.contentType === UnifiedContentType.NOVEL || this.isLocalReadAloudCapableEBookContent();
  }

  /**
   * 继续阅读
   */
  private continueReading(): void {
    if (!this.content) return;
    if (this.isReadActionBusy()) return;

    logger.info(TAG, `continueReading: contentType=${this.content.contentType}, onlineReaderUrl=${this.onlineReaderUrl ? this.onlineReaderUrl.substring(0, 50) + '...' : 'null'}, sourceId=${this.content.sourceId}`);

    // 电子书特殊处理
    if (this.content.contentType === UnifiedContentType.EBOOK) {
      // 在线电子书：直接跳转到下载详情页（不依赖在线阅读器）
      if (!this.content.isLocal) {
        logger.info(TAG, '在线电子书，转到下载详情页');
        this.isOpeningOnlineEBookDownloadDetail = true;
        this.refreshProgress = '正在准备下载信息...';
        this.isChaptersLoading = true;
        this.isLoadingRecommendations = true;
        this.isLoadingShelfContent = true;
        this.openOnlineEBookDownloadDetailPage();
        return;
      }
      // 本地电子书：直接打开阅读器
      logger.info(TAG, '使用本地电子书阅读器');
      this.openEBookReader(0);
      return;
    }

    const lastIndex = this.content.lastReadChapterIndex;
    if (lastIndex >= 0 && lastIndex < this.content.chapters.length) {
      this.startReading(lastIndex);
    } else {
      // 从第一章开始
      this.startReading(0);
    }
  }

  /**
   * 继续听书（小说 / 本地 TXT 电子书）
   */
  private continueReadAloud(): void {
    if (!this.content) return;

    const lastIndex = this.content.lastReadChapterIndex;
    const targetChapterIndex = lastIndex >= 0 && lastIndex < this.content.chapters.length ? lastIndex : 0;
    if (this.content.contentType === UnifiedContentType.NOVEL) {
      this.openNovelReadAloudPage(targetChapterIndex);
      return;
    }
    if (this.isLocalTxtNovelEBookContent()) {
      this.openLocalTxtEBookReadAloudPage(targetChapterIndex);
      return;
    }
    if (this.isLocalWebTextEBookContent()) {
      this.openEBookReader(targetChapterIndex, true);
    }
  }

  /**
   * 打开在线电子书阅读器（ZLibrary等）
   */
  private openOnlineEBookReader(): void {
    if (!this.content || !this.onlineReaderUrl) return;

    logger.info(TAG, `打开在线电子书阅读器: ${this.content.title}, URL: ${this.onlineReaderUrl.substring(0, 50)}...`);

    const params: ZLibraryReaderParams = {
      readerUrl: this.onlineReaderUrl,
      bookTitle: this.content.title,
      sourceId: this.content.sourceId || ''
    };

    this.navigateWithManagedWindowTransition('ZLibraryReaderPage', params);
  }

  /**
   * 打开漫画阅读器
   */
  private openMangaReader(chapterIndex: number): void {
    if (!this.content) return;

    const chapter = this.content.chapters[chapterIndex];
    
    // 获取原始Manga对象
    const originalManga = MangaAdapter.getOriginalManga(this.content);
    
    // 构建阅读器参数（参考MangaDetailPage的实现）
    const readerParams: MangaReaderPageParams = {
      fromPage: 'UnifiedDetailPage'
    } as MangaReaderPageParams;
    readerParams.readerTitle = this.content.title;
    
    // 判断是否为在线漫画
    const hasSourceId = this.content.sourceId && Number(this.content.sourceId) > 0;
    
    if (hasSourceId && originalManga) {
      // 在线漫画：传递完整的manga对象和sourceId
      readerParams.manga = originalManga;
      readerParams.sourceId = Number(this.content.sourceId);
      readerParams.mangaId = this.content.id;
      readerParams.sourceName = this.content.sourceName || '';
      readerParams.sourcePkg = this.content.sourcePkg || this.pageParams?.sourcePkg || undefined;
      
      // 判断章节是否已下载
      const isDownloaded = chapter.isDownloaded || false;
      readerParams.contentType = isDownloaded ? MangaReaderContentType.OnlineDownloaded : MangaReaderContentType.OnlineUndownloaded;
      
      // 对于WebView图源，需要传递外部章节ID
      const originalChapter = originalManga.chapters.find(ch => ch.id === chapter.id);
      if (originalChapter?.externalId) {
        readerParams.chapterId = originalChapter.externalId;
        logger.info(TAG, `转换章节ID: 内部ID=${chapter.id} -> 外部ID=${originalChapter.externalId}`);
      } else {
        readerParams.chapterId = chapter.id;
      }
      
      logger.info(TAG, `在线漫画阅读: sourceId=${readerParams.sourceId}, mangaId=${readerParams.mangaId}, chapterId=${readerParams.chapterId}`);
    } else {
      // 本地漫画：传递详情页已恢复的 Manga 对象，阅读器会继续水合章节和页面
      if (originalManga) {
        readerParams.manga = originalManga;
      }
      readerParams.mangaId = this.content.id;
      readerParams.chapterId = chapter.id;
      readerParams.contentType = MangaReaderContentType.Local;
      readerParams.sourceName = 'LOCAL';
      logger.info(TAG, `本地漫画阅读: mangaId=${readerParams.mangaId}, chapterId=${readerParams.chapterId}`);
    }
    
    // [修复] 使用章节阅读进度中的页码，而不是总是从第一页开始
    const chapterProgress = this.chapterProgressMap.get(chapter.id);
    const rawPageIndex: number = chapterProgress ? chapterProgress.lastReadPageIndex : 0;
    readerParams.pageIndex = Number.isFinite(rawPageIndex) && rawPageIndex >= 0 ? Math.floor(rawPageIndex) : 0;
    logger.info(TAG, `阅读页码: chapterId=${chapter.id}, pageIndex=${readerParams.pageIndex} (来源: ${chapterProgress ? 'chapterProgressMap' : '默认'})`);

    // 触发翻开过渡动画
    // 优先使用本地缓存的封面路径（可直接加载PixelMap），回退到网络URL
    const coverPath: string = this.resolveUnifiedCoverImagePath(originalManga);
    const coverComponentId: string = `cover_${this.componentId}`;
    readerParams.coverComponentId = coverComponentId;
    
    logger.info(TAG, `触发漫画翻开过渡动画: coverPath=${coverPath}, componentId=${coverComponentId}, candidates=${this.buildCoverCandidateDebugText(originalManga)}`);
    startBookOpenTransitionWithComponentId(
      coverPath,
      coverComponentId,
      this.content.id,
      'manga',
      () => {
        // 动画完成时触发导航
        logger.info(TAG, '漫画翻开过渡动画触发导航');
        openMangaReaderInIsolatedAbility(this.getUIContext(), this.pathStack, readerParams, TAG, false);
      },
      undefined,
      {
        title: this.content.title,
        author: this.content.author,
        intro: this.content.description
      }
    );
  }

  /**
   * 打开电子书阅读器
   */
  private openEBookReader(chapterIndex: number, autoStartReadAloud: boolean = false): void {
    if (!this.content) return;
    const originalEBook = EBookAdapter.getOriginalEBook(this.content);

    // EBookReaderParams只需要bookId，章节索引通过阅读进度恢复
    const params: EBookReaderParams = {
      bookId: this.content.id,
      readerTitle: this.content.title
    };
    if (autoStartReadAloud) {
      params.autoStartReadAloud = true;
      params.autoOpenReadAloudPlayer = true;
    }

    // 触发翻开过渡动画
    // 优先使用本地缓存的封面路径（可直接加载PixelMap），回退到网络URL
    const coverPath: string = this.localCoverPath || this.content.coverUrl || '';
    const coverComponentId: string = `cover_${this.componentId}`;
    params.coverComponentId = coverComponentId;
    const txtNovelReaderParams = originalEBook
      ? buildNovelReaderParamsFromTxtEBook(originalEBook, coverComponentId)
      : null;
    const ebookBackground = this.getUnifiedEBookTransitionBackground();
    
    logger.info(TAG, `触发电子书翻开过渡动画: coverPath=${coverPath}, componentId=${coverComponentId}, 有背景设置=${ebookBackground ? '是' : '否'}`);
    startBookOpenTransitionWithComponentId(
      coverPath,
      coverComponentId,
      this.content.id,
      'ebook',
      () => {
        // 动画完成时触发导航
        logger.info(TAG, '电子书翻开过渡动画触发导航');
        const ebookRouteName = resolveEBookReaderRouteName(originalEBook);
        const signalStats = inspectEBookImagePageSignals(originalEBook);
        const firstChapter = originalEBook && originalEBook.chapters.length > 0
          ? originalEBook.chapters[0]
          : null;
        logger.info(
          TAG,
          `电子书阅读页路由判定: route=${ebookRouteName}, format=${originalEBook?.format || 'null'}, ` +
            `contentMode=${originalEBook?.contentMode || 'null'}, ` +
            `preferredReaderEngine=${originalEBook?.preferredReaderEngine || 'null'}, ` +
            `chapters=${signalStats.totalChapters}, strongSignalChapters=${signalStats.strongSignalChapters}, ` +
            `sparsePageLikeChapters=${signalStats.sparsePageLikeChapters}, ` +
            `firstChapterTitle=${firstChapter?.title || ''}, firstChapterLayout=${firstChapter?.resourceLayoutType || ''}, ` +
            `firstChapterImagePath=${(firstChapter?.resourceImagePath || '').substring(0, 96)}, ` +
            `firstChapterImageRelativePath=${(firstChapter?.resourceImageRelativePath || '').substring(0, 96)}`
        );
        if (txtNovelReaderParams && originalEBook?.format === EBookFormat.TXT) {
          if (autoStartReadAloud) {
            txtNovelReaderParams.autoStartReadAloud = true;
            txtNovelReaderParams.autoOpenReadAloudPlayer = true;
          }
          txtNovelReaderParams.readerTitle = this.content?.title || '';
          if (!openNovelReaderInIsolatedAbility(this.getUIContext(), this.pathStack, txtNovelReaderParams, TAG, false)) {
            this.navigateWithManagedWindowTransition('NovelReaderPage', txtNovelReaderParams);
          }
        } else {
          if (!openEBookReaderInIsolatedAbility(this.getUIContext(), this.pathStack, params, TAG, false)) {
            if (ebookRouteName === 'EBookReaderPage') {
              openEBookReaderRouterPage(this.getUIContext(), params, TAG);
            } else {
              this.navigateWithManagedWindowTransition(ebookRouteName, params);
            }
          }
        }
      },
      ebookBackground,
      {
        title: this.content.title,
        author: this.content.author,
        intro: this.content.description
      }
    );
  }

  /**
   * 打开小说阅读器
   */
  private openNovelReader(chapterIndex: number): void {
    if (!this.content) return;

    const chapter = this.content.chapters[chapterIndex];
    if (!chapter) return;

    // 获取原始小说章节数据
    const originalChapter = NovelAdapter.getOriginalChapter(chapter);
    const originalBook = NovelAdapter.getOriginalNovel(this.content);
    const sourceId = this.content.sourceId || '';
    const sourceType: LegadoBookSourceType = this.getNovelSourceTypeById(sourceId, this.content.id);

    if (sourceType === LegadoBookSourceType.AUDIO) {
      logger.info(TAG, `听书内容跳过翻书动画，直接打开播放器页: 章节索引=${chapterIndex}, 图源=${sourceId}`);
      this.openNovelReadAloudPage(chapterIndex);
      return;
    }

    const params: NovelReaderPageParams = {
      sourceId,
      bookUrl: this.content.id,
      bookName: this.content.title,
      chapterUrl: originalChapter?.url || '',
      chapterTitle: chapter.title,
      chapterIndex: chapterIndex,
      totalChapters: this.content.totalChapters,
      tocUrl: originalBook?.tocUrl,
      author: this.content.author,
      coverUrl: this.content.coverUrl
    };

    // 触发翻开过渡动画
    // 优先使用本地缓存的封面路径（可直接加载PixelMap），回退到网络URL
    const coverPath: string = this.localCoverPath || this.content.coverUrl || '';
    const coverComponentId: string = `cover_${this.componentId}`;
    const transitionBookId = this.getUnifiedNovelTransitionBookId();
    params.coverComponentId = coverComponentId;
    
    logger.info(TAG, `触发小说翻开过渡动画: coverPath=${coverPath}, componentId=${coverComponentId}, transitionBookId=${transitionBookId}`);
    startBookOpenTransitionWithComponentId(
      coverPath,
      coverComponentId,
      transitionBookId,
      'novel',
      () => {
        // 动画完成时触发导航
        logger.info(TAG, '小说翻开过渡动画触发导航');
        params.readerTitle = this.content?.title || '';
        if (!openNovelReaderInIsolatedAbility(this.getUIContext(), this.pathStack, params, TAG, false)) {
          this.navigateWithManagedWindowTransition('NovelReaderPage', params);
        }
      },
      undefined,
      {
        title: this.content.title,
        author: this.content.author,
        intro: this.content.description
      }
    );
  }

  private getUnifiedEBookTransitionBackground(): EBookBackgroundSettings | undefined {
    if (!this.content) {
      return undefined;
    }

    const ebook = EBookAdapter.getOriginalEBook(this.content);
    if (!ebook) {
      return undefined;
    }

    const defaultBackgroundColor = ThemeManager.getInstance().isDarkThemeSync() ? '#1E1E1E' : '#FFFFFF';
    const followSystemTheme = ebook.readingSettings?.followSystemTheme !== false;

    const background: EBookBackgroundSettings = {
      backgroundColor: followSystemTheme
        ? defaultBackgroundColor
        : (ebook.readingSettings?.backgroundColor || defaultBackgroundColor)
    };

    const isTxtBook = ebook.format === EBookFormat.TXT;
    const hasCustomImage = !followSystemTheme
      && ebook.readingSettings?.backgroundType === 'IMAGE'
      && typeof ebook.readingSettings?.backgroundImagePath === 'string'
      && ebook.readingSettings.backgroundImagePath.length > 0;

    if (isTxtBook && hasCustomImage) {
      background.backgroundImagePath = ebook.readingSettings?.backgroundImagePath;
      background.backgroundImageOpacity = ebook.readingSettings?.backgroundImageOpacity ?? 0.3;
    }

    return background;
  }

  private getUnifiedNovelTransitionBookId(): string {
    if (!this.content) {
      return '';
    }

    if (this.content.sourceId && this.content.sourceId.length > 0) {
      return `${this.content.sourceId}_${encodeURIComponent(this.content.id)}`;
    }

    return this.content.id;
  }

  /**
   * 打开小说听书播放器
   */
  private openNovelReadAloudPage(chapterIndex: number): void {
    if (!this.content) return;

    const chapter = this.content.chapters[chapterIndex];
    if (!chapter) return;

    const originalChapter = NovelAdapter.getOriginalChapter(chapter);
    const originalBook = NovelAdapter.getOriginalNovel(this.content);
    const sourceId = this.content.sourceId || '';
    const sourceType: LegadoBookSourceType = this.getNovelSourceTypeById(sourceId, this.content.id);
    const shouldDisableTransition = sourceType === LegadoBookSourceType.AUDIO;
    const readAloudCoverComponentId = shouldDisableTransition ? undefined : `cover_${this.componentId}`;

    const params: NovelReaderPageParams = {
      sourceId,
      bookUrl: this.content.id,
      bookName: this.content.title,
      chapterUrl: originalChapter?.url || '',
      chapterTitle: chapter.title,
      chapterIndex: chapterIndex,
      totalChapters: this.content.totalChapters,
      tocUrl: originalBook?.tocUrl,
      author: this.content.author,
      coverUrl: this.content.coverUrl,
      coverComponentId: readAloudCoverComponentId
    };

    if (sourceType === LegadoBookSourceType.AUDIO) {
      params.autoStartReadAloud = true;
      AppStorage.setOrCreate('ReadAloudPlayerOpeningAt', Date.now());
      logger.info(TAG, `开始听书直达播放器页: 章节索引=${chapterIndex}, 图源=${sourceId}, 章节地址=${params.chapterUrl}`);
      openReadAloudPlayerInIsolatedAbility(
        this.getUIContext(),
        this.pathStack,
        TAG,
        'UnifiedDetailPage',
        WindowManager.getCurrentMode(),
        params
      );
      return;
    }
    params.autoStartReadAloud = true;
    params.autoOpenReadAloudPlayer = true;
    params.readerTitle = this.content.title;
    if (!openNovelReaderInIsolatedAbility(this.getUIContext(), this.pathStack, params, TAG)) {
      this.navigateWithManagedWindowTransition('NovelReaderPage', params);
    }
  }

  private openLocalTxtEBookReadAloudPage(chapterIndex: number): void {
    if (!this.content) {
      return;
    }
    const ebook = EBookAdapter.getOriginalEBook(this.content);
    if (!ebook || ebook.format !== EBookFormat.TXT) {
      return;
    }
    const safeChapterIndex = Math.max(0, Math.min(chapterIndex, Math.max(ebook.chapters.length, 1) - 1));
    const chapter = ebook.chapters[safeChapterIndex];
    const params = buildNovelReaderParamsFromTxtEBook(ebook, `cover_${this.componentId}`);
    params.chapterIndex = safeChapterIndex;
    params.chapterUrl = chapter?.id || `local_txt_chapter_${safeChapterIndex}`;
    params.chapterTitle = chapter?.title || `Chapter ${safeChapterIndex + 1}`;
    if ((ebook.readingProgress?.currentChapterIndex ?? -1) !== safeChapterIndex) {
      params.chapterPageIndex = 0;
    }
    params.autoStartReadAloud = true;
    params.autoOpenReadAloudPlayer = true;
    params.readerTitle = this.content.title;
    if (!openNovelReaderInIsolatedAbility(this.getUIContext(), this.pathStack, params, TAG)) {
      this.navigateWithManagedWindowTransition('NovelReaderPage', params);
    }
  }

  /**
   * 切换收藏状态
   */
  /**
   * 执行重复检测，如果检测到重复则弹窗并暂存操作，返回 true 表示已暂停（等待弹窗回调）
   * @param action 检测通过后要执行的操作
   * @param actionDescription 操作描述（用于日志）
   * @returns true 表示检测到重复并已暂停，false 表示无重复可继续
   */
  private async checkDuplicateAndExecute(action: () => Promise<void>, actionDescription: string): Promise<boolean> {
    if (!this.content) {
      return false;
    }

    const detectionService = DuplicateDetectionService.getInstance();
    const contentType = this.mapToDuplicateCheckContentType(this.content.contentType);
    logger.info(TAG, `开始重复检测(${actionDescription}): title="${this.content.title}", author="${this.content.author}", contentType=${contentType}`);
    const checkResult = await detectionService.checkDuplicates({
      title: this.content.title,
      author: this.content.author,
      contentType: contentType,
      sourceId: this.content.sourceId,
      externalId: this.content.id
    });

    logger.info(TAG, `重复检测结果: hasDuplicates=${checkResult.hasDuplicates}, matches=${checkResult.matches.length}, checkedCount=${checkResult.checkedCount}`);

    if (checkResult.hasDuplicates) {
      this.pendingFavoriteAction = action;
      this.duplicateDetectionMatches = checkResult.matches;
      this.duplicateDetectionLoadSignal++;
      return true;
    }

    return false;
  }

  /**
   * Toggle favorite state.
   */
  private async toggleFavorite(): Promise<void> {
    if (!this.content) {
      return;
    }

    const previousState = this.isFavorite;
    const targetState = !previousState;

    logger.info(TAG, `toggleFavorite: previousState=${previousState}, targetState=${targetState}, title="${this.content.title}"`);

    // 添加到收藏时进行重复检测
    if (targetState) {
      const shouldStop = await this.checkDuplicateAndExecute(async () => {
        try {
          await this.setFavoriteStatus(true);
          this.getUIContext().getPromptAction().showToast({ message: '已添加到收藏', duration: 1500 });
        } catch (error) {
          logger.error(TAG, `Failed to add to favorites: ${String(error)}`);
          this.isFavorite = previousState;
          if (this.content) {
            this.content.isFavorite = previousState;
          }
          this.getUIContext().getPromptAction().showToast({ message: '操作失败', duration: 1500 });
        }
      }, '收藏');

      if (shouldStop) {
        return;
      }
    }

    try {
      await this.setFavoriteStatus(targetState);
      this.getUIContext().getPromptAction().showToast({
        message: targetState ? '已添加到收藏' : '已取消收藏',
        duration: 1500
      });
    } catch (error) {
      logger.error(TAG, `Failed to toggle favorite state: ${String(error)}`);
      this.isFavorite = previousState;
      this.content.isFavorite = previousState;
      this.getUIContext().getPromptAction().showToast({
        message: '操作失败',
        duration: 1500
      });
    }
  }

  /**
   * 将 UnifiedContentType 映射为 DuplicateCheckContentType
   */
  private mapToDuplicateCheckContentType(contentType: UnifiedContentType): DuplicateCheckContentType {
    if (contentType === UnifiedContentType.MANGA) {
      return DuplicateCheckContentType.MANGA;
    } else if (contentType === UnifiedContentType.EBOOK) {
      return DuplicateCheckContentType.EBOOK;
    } else {
      return DuplicateCheckContentType.NOVEL;
    }
  }

  private async showDeleteContentConfirm(): Promise<void> {
    if (!this.content || this.isDeletingContent) {
      return;
    }

    const target: UnifiedDeleteTarget | null = await this.resolveDeleteTarget();
    if (!target || target.contentId.length <= 0) {
      this.getUIContext().getPromptAction().showToast({ message: '未找到可删除的内容记录', duration: 1800 });
      return;
    }

    const actionText: string = target.isRemoteProviderManga ? '移除' : '删除';
    const message: string = target.isRemoteProviderManga
      ? `确定要将「${target.title}」从本地书架移除吗？\n\n此操作会移除本地书架记录和本地封面缓存，不会删除远程服务端内容。`
      : `确定要删除「${target.title}」吗？\n\n此操作会删除${target.contentTypeLabel}记录、阅读进度、相关缓存和本地文件，且不可撤销。`;
    this.getUIContext().getPromptAction().showDialog({
      title: target.isRemoteProviderManga ? '确认移除' : '确认删除',
      message: message,
      buttons: [
        { text: '取消', color: $r('sys.color.ohos_id_color_text_secondary') },
        { text: actionText, color: ThemeAwareHelper.getTestManagementThemedColor('button_danger', this.themeState.currentTheme) }
      ]
    }).then((result: DialogResult) => {
      if (result.index === 1) {
        void this.deleteCurrentContent(target);
      }
    });
  }

  private async resolveDeleteTarget(): Promise<UnifiedDeleteTarget | null> {
    if (!this.content) {
      return null;
    }

    let contentId: string = this.content.id || '';
    let isRemoteProviderManga: boolean = false;
    if (this.content.contentType === UnifiedContentType.MANGA) {
      contentId = await this.resolveMangaDeleteId(contentId);
      isRemoteProviderManga = this.isRemoteProviderMangaContent();
    } else if (this.content.contentType === UnifiedContentType.EBOOK) {
      const ebook: EBook | null = EBookAdapter.getOriginalEBook(this.content);
      contentId = ebook?.id || contentId;
    } else if (this.content.contentType === UnifiedContentType.NOVEL) {
      contentId = await this.resolveNovelDeleteId();
    }

    const target: UnifiedDeleteTarget = {
      contentType: this.content.contentType,
      contentId: contentId,
      title: this.content.title || this.getContentTypeName(),
      contentTypeLabel: this.getContentTypeName(),
      isRemoteProviderManga: isRemoteProviderManga
    };
    return target;
  }

  private isRemoteProviderMangaContent(): boolean {
    if (!this.content || this.content.contentType !== UnifiedContentType.MANGA) {
      return false;
    }

    const originalManga: Manga | null = MangaAdapter.getOriginalManga(this.content);
    if (originalManga) {
      return RemoteLibraryMangaBridge.getInstance().isRemoteProviderManga(originalManga);
    }

    return RemoteLibraryMangaBridge.parseProviderMangaId(this.content.id) !== null;
  }

  private async resolveMangaDeleteId(currentContentId: string): Promise<string> {
    if (currentContentId.length > 0) {
      const directComic: ComicInfo | null = await this.dataManager.getComicById(currentContentId);
      if (directComic) {
        return currentContentId;
      }
      const onlineComic: OnlineComicInfo | null = await this.dataManager.getOnlineComicInfoById(currentContentId);
      if (onlineComic) {
        return currentContentId;
      }
    }

    const paramId: string = this.pageParams?.contentId || '';
    if (paramId.length > 0 && paramId !== currentContentId) {
      const paramComic: ComicInfo | null = await this.dataManager.getComicById(paramId);
      if (paramComic) {
        return paramId;
      }
      const paramOnlineComic: OnlineComicInfo | null = await this.dataManager.getOnlineComicInfoById(paramId);
      if (paramOnlineComic) {
        return paramId;
      }
    }

    if (paramId.length > 0) {
      const externalRecord: DatabaseRecord | null = await this.dataManager.getComicByExternalId(paramId);
      if (externalRecord) {
        const externalComicId: string = String(externalRecord.id || '');
        if (externalComicId.length > 0) {
          return externalComicId;
        }
      }
      const onlineComicByExternal: OnlineComicInfo | null = await this.dataManager.getOnlineComicByExternalId(paramId);
      if (onlineComicByExternal && onlineComicByExternal.id.length > 0) {
        return onlineComicByExternal.id;
      }
    }

    return currentContentId || paramId;
  }

  private async resolveNovelDeleteId(): Promise<string> {
    if (!this.content) {
      return '';
    }

    const originalNovel: LegadoBook | null = NovelAdapter.getOriginalNovel(this.content);
    if (originalNovel?.id && originalNovel.id.length > 0) {
      const directBook: NovelBook | null = await this.novelDataManager.getBook(originalNovel.id);
      if (directBook) {
        return directBook.id;
      }
    }

    const sourceId: string = this.content.sourceId || this.pageParams?.sourceId || '';
    const bookUrl: string = this.content.id || this.pageParams?.contentId || '';
    const bookByUrl: NovelBook | null = await this.novelDataManager.getBookByUrl(sourceId, bookUrl);
    if (bookByUrl) {
      return bookByUrl.id;
    }

    const directByContentId: NovelBook | null = await this.novelDataManager.getBook(bookUrl);
    if (directByContentId) {
      return directByContentId.id;
    }

    if (sourceId.length > 0 && bookUrl.length > 0) {
      const constructedId: string = this.getNovelCacheBookId(sourceId, bookUrl);
      const constructedBook: NovelBook | null = await this.novelDataManager.getBook(constructedId);
      if (constructedBook) {
        return constructedBook.id;
      }
      return constructedId;
    }

    return bookUrl;
  }

  private mapUnifiedTypeToCategoryType(contentType: UnifiedContentType): ContentType {
    switch (contentType) {
      case UnifiedContentType.MANGA:
        return ContentType.MANGA;
      case UnifiedContentType.EBOOK:
        return ContentType.EBOOK;
      case UnifiedContentType.NOVEL:
        return ContentType.NOVEL;
      default:
        return ContentType.MANGA;
    }
  }

  private async removeDeletedContentFromShelves(target: UnifiedDeleteTarget): Promise<void> {
    const categoryManager: BookshelfCategoryManager = this.typeShelfManager.getCategoryManager();
    const contentType: ContentType = this.mapUnifiedTypeToCategoryType(target.contentType);
    await categoryManager.removeItemFromCategory(target.contentId, contentType);
    if (this.content && this.content.id.length > 0 && target.contentId !== this.content.id) {
      await categoryManager.removeItemFromCategory(this.content.id, contentType);
    }
  }

  private publishContentDeletedEvent(target: UnifiedDeleteTarget): void {
    switch (target.contentType) {
      case UnifiedContentType.MANGA:
        eventBus.publish(GameEvent.MANGA_DELETED, new MangaDeletedPayload(target.contentId));
        break;
      case UnifiedContentType.EBOOK:
        eventBus.publish(GameEvent.EBOOK_LIST_REFRESH_NEEDED, new BasePayload());
        eventBus.publish(GameEvent.EBOOK_UPDATED, new BasePayload());
        break;
      case UnifiedContentType.NOVEL:
        eventBus.publish(GameEvent.NOVEL_LIST_REFRESH_NEEDED, new BasePayload());
        eventBus.publish(GameEvent.NOVEL_UPDATED, new BasePayload());
        break;
    }
  }

  private returnAfterDelete(): void {
    try {
      const globalStack: NavPathStack | undefined = AppStorage.get<NavPathStack>('GlobalNavStack');
      if (globalStack && globalStack.size() > 0) {
        globalStack.pop();
        return;
      }
    } catch (error) {
      logger.warn(TAG, `删除后返回全局导航栈失败: ${String(error)}`);
    }

    try {
      if (this.pathStack.size() > 0) {
        this.pathStack.pop();
      }
    } catch (error) {
      logger.warn(TAG, `删除后返回当前导航栈失败: ${String(error)}`);
    }
  }

  private getLibraryFilesDir(): string {
    const hostContext: common.UIAbilityContext = (this.getUIContext().getHostContext() as common.UIAbilityContext) as common.UIAbilityContext;
    if (!hostContext || typeof hostContext.filesDir !== 'string') {
      return '';
    }
    return hostContext.filesDir;
  }

  private async removeRemoteProviderMangaFromShelf(): Promise<void> {
    if (!this.content) {
      throw new Error('当前内容为空');
    }

    const originalManga: Manga | null = MangaAdapter.getOriginalManga(this.content);
    if (!originalManga) {
      throw new Error('未找到远程漫画记录');
    }

    const filesDir: string = this.getLibraryFilesDir();
    if (filesDir.length <= 0) {
      throw new Error('无法获取本地书架目录');
    }

    await this.remoteLibraryShelfManager.removeFromLocalLibrary(originalManga, filesDir);
  }

  private async deleteCurrentContent(target: UnifiedDeleteTarget): Promise<void> {
    if (this.isDeletingContent) {
      return;
    }

    this.isDeletingContent = true;
    try {
      logger.info(TAG, `开始删除统一详情页内容: type=${target.contentType}, id=${target.contentId}, title=${target.title}`);
      switch (target.contentType) {
        case UnifiedContentType.MANGA:
          if (target.isRemoteProviderManga) {
            await this.removeRemoteProviderMangaFromShelf();
          } else {
            await this.dataManager.deleteComic(target.contentId);
          }
          break;
        case UnifiedContentType.EBOOK:
          await this.ebookDataManager.deleteEBook(target.contentId);
          break;
        case UnifiedContentType.NOVEL:
          await this.novelDataManager.deleteBook(target.contentId);
          break;
      }

      await this.removeDeletedContentFromShelves(target);
      this.publishContentDeletedEvent(target);
      const successMessage: string = target.isRemoteProviderManga ? '移除成功' : '删除成功';
      this.getUIContext().getPromptAction().showToast({ message: successMessage, duration: 1500 });
      this.returnAfterDelete();
    } catch (error) {
      const errorMessage: string = error instanceof Error ? error.message : String(error);
      logger.error(TAG, `删除统一详情页内容失败: ${errorMessage}`);
      this.getUIContext().getPromptAction().showToast({ message: `删除失败: ${errorMessage}`, duration: 2200 });
    } finally {
      this.isDeletingContent = false;
    }
  }

  /**
   * 获取过滤后的章节列表
   */
  private getFilteredChapters(): UnifiedChapter[] {
    if (!this.content) return [];

    let chapters = [...this.content.chapters];

    // 应用过滤
    switch (this.chapterFilter) {
      case ChapterFilterType.UNREAD:
        chapters = chapters.filter((chapter: UnifiedChapter) => !this.isNovelChapterReadForDisplay(chapter));
        break;
      case ChapterFilterType.DOWNLOADED:
        chapters = chapters.filter((chapter: UnifiedChapter) => this.isNovelChapterCachedForDisplay(chapter));
        break;
      case ChapterFilterType.BOOKMARKED:
        chapters = chapters.filter(c => c.isBookmarked);
        break;
    }

    // 应用排序
    if (this.chapterSortOrder === ChapterSortOrder.DESCENDING) {
      chapters.reverse();
    }

    return chapters;
  }

  private getSafeLastReadChapterIndexForDisplay(): number {
    if (!this.content) {
      return -1;
    }
    const rawIndex = this.content.lastReadChapterIndex;
    if (!Number.isFinite(rawIndex)) {
      return -1;
    }
    const safeIndex = Math.floor(rawIndex);
    if (safeIndex < 0 || safeIndex >= this.content.chapters.length) {
      return -1;
    }
    return safeIndex;
  }

  private isNovelChapterCachedForDisplay(chapter: UnifiedChapter): boolean {
    if (this.isCurrentNovelAudioSource()) {
      const summaryChapter = this.readAloudCacheSummary?.chapters[chapter.index];
      if (summaryChapter) {
        return summaryChapter.cached;
      }
    }
    return chapter.isDownloaded;
  }

  private isNovelChapterReadForDisplay(chapter: UnifiedChapter): boolean {
    if (!this.isCurrentNovelAudioSource()) {
      return chapter.isRead;
    }
    if (chapter.isRead) {
      return true;
    }
    const lastReadChapterIndex = this.getSafeLastReadChapterIndexForDisplay();
    return lastReadChapterIndex >= 0 && chapter.index < lastReadChapterIndex;
  }

  private isNovelChapterCurrentForDisplay(chapter: UnifiedChapter): boolean {
    return chapter.index === this.getSafeLastReadChapterIndexForDisplay();
  }

  private getNovelChapterProgressStatusLabel(chapter: UnifiedChapter): string {
    if (this.isCurrentNovelAudioSource()) {
      if (this.isNovelChapterCurrentForDisplay(chapter)) {
        return '播放中';
      }
      if (this.isNovelChapterReadForDisplay(chapter)) {
        return '已播放';
      }
      return '未播放';
    }
    if (this.isNovelChapterReadForDisplay(chapter)) {
      return '已读';
    }
    if (this.isNovelChapterCurrentForDisplay(chapter)) {
      return '阅读中';
    }
    return '';
  }

  private getNovelChapterProgressStatusColor(chapter: UnifiedChapter): ResourceColor {
    if (this.isNovelChapterCurrentForDisplay(chapter)) {
      return ThemeAwareHelper.getTestManagementThemedColor('accent_primary', this.themeState.currentTheme);
    }
    if (this.isNovelChapterReadForDisplay(chapter)) {
      return ThemeAwareHelper.getTestManagementThemedColor('accent_blue', this.themeState.currentTheme);
    }
    return ThemeAwareHelper.getTestManagementThemedColor('text_muted', this.themeState.currentTheme);
  }

  private getNovelChapterProgressStatusBackground(chapter: UnifiedChapter): ResourceColor {
    if (this.isNovelChapterCurrentForDisplay(chapter)) {
      return ThemeAwareHelper.getTestManagementThemedColor('accent_primary', this.themeState.currentTheme) + '15';
    }
    if (this.isNovelChapterReadForDisplay(chapter)) {
      return ThemeAwareHelper.getTestManagementThemedColor('accent_blue', this.themeState.currentTheme) + '15';
    }
    return ThemeAwareHelper.getTestManagementThemedColor('comp_background_tertiary', this.themeState.currentTheme);
  }

  /**
   * 获取内容类型显示名称
   * 对于在线漫画显示"在线漫画"，本地漫画显示"本地漫画"
   */
  private getContentTypeName(): string {
    if (!this.content) {
      switch (this.pageParams?.contentType) {
        case UnifiedContentType.MANGA:
          if (this.pageParams?.sourceId && Number(this.pageParams.sourceId) > 0) {
            return '在线漫画';
          }
          return '漫画';
        case UnifiedContentType.EBOOK:
          return '电子书';
        case UnifiedContentType.NOVEL:
          return '小说';
        default:
          return '';
      }
    }
    switch (this.content.contentType) {
      case UnifiedContentType.MANGA:
        // 判断是否为在线漫画
        if (this.isOnlineManga()) {
          return '在线漫画';
        }
        return '本地漫画';
      case UnifiedContentType.EBOOK:
        return this.content.isLocal ? '本地电子书' : '在线电子书';
      case UnifiedContentType.NOVEL:
        return this.isCurrentNovelAudioSource() ? '听书' : '小说';
      default:
        return '';
    }
  }
  
  /**
   * 判断当前内容是否为在线漫画
   */
  private isOnlineManga(): boolean {
    if (!this.content || this.content.contentType !== UnifiedContentType.MANGA) {
      return false;
    }
    // 有sourceId且大于0表示在线漫画
    const sourceId = this.pageParams?.sourceId;
    return sourceId !== undefined && sourceId !== '' && Number(sourceId) > 0;
  }
  
  /**
   * 判断当前内容是否为在线内容（在线漫画或小说）
   * 用于决定是否显示下载按钮
   */
  private isOnlineContent(): boolean {
    if (!this.content) return false;
    
    // 在线漫画
    if (this.content.contentType === UnifiedContentType.MANGA) {
      return this.isOnlineManga();
    }
    
    // 小说始终被视为在线内容（因为小说来源于书源）
    if (this.content.contentType === UnifiedContentType.NOVEL) {
      return true;
    }
    
    // 电子书：根据 isLocal 判断
    if (this.content.contentType === UnifiedContentType.EBOOK) {
      return !this.content.isLocal;
    }
    
    return false;
  }
  
  /**
   * 创建图片列表获取函数
   * 用于漫画下载时延迟获取图片URL列表
   */
  private createPageListFetcher(): PageListFetcher {
    const dataManager = this.dataManager;
    const sourceIdText: string = this.normalizeTrackingText(this.content?.sourceId || this.pageParams?.sourceId);
    const sourceId: number = Number(sourceIdText);
    const fetcher: PageListFetcher = async (chapterId: string, mangaId: string): Promise<string[] | DownloadPageItem[]> => {
      if (sourceId > 0 && await getLegadoMangaSourceBridge().isLegadoMangaSourceId(sourceId)) {
        const legadoItems = await this.fetchLegadoMangaDownloadPages(sourceId, chapterId, mangaId);
        if (legadoItems.length > 0) {
          return legadoItems;
        }
      }
      const pages = await dataManager.getOnlineChapterPages(chapterId);
      return pages.map(p => p.imageUrl);
    };
    return fetcher;
  }

  private async fetchLegadoMangaDownloadPages(
    sourceId: number,
    chapterId: string,
    mangaId: string
  ): Promise<DownloadPageItem[]> {
    const comicInfo: OnlineComicInfo | null = await this.dataManager.getOnlineComicInfoById(mangaId);
    const chapterInfo: OnlineChapterInfo | null = await this.dataManager.getOnlineChapterById(chapterId);
    const mangaExternalId: string = comicInfo && comicInfo.externalId.length > 0 ? comicInfo.externalId : mangaId;
    const chapterExternalId: string = chapterInfo && chapterInfo.externalId.length > 0 ? chapterInfo.externalId : chapterId;

    const bridgeResult: LegadoMangaPageResult | null =
      await getLegadoMangaSourceBridge().loadPageList(sourceId, mangaExternalId, chapterExternalId);
    if (!bridgeResult || bridgeResult.pages.length <= 0) {
      return [];
    }

    getLegadoMangaSourceBridge().savePagesToDatabase(chapterId, bridgeResult.pages).catch((error: Error) => {
      logger.warn(TAG, `保存Legado漫画下载页面失败: chapterId=${chapterId}, ${String(error)}`);
    });

    const items: DownloadPageItem[] = [];
    for (let i = 0; i < bridgeResult.pages.length; i++) {
      const page = bridgeResult.pages[i];
      if (!page || !page.imageUrl || page.imageUrl.trim().length <= 0) {
        continue;
      }
      const item: DownloadPageItem = {
        url: page.imageUrl,
        headers: this.buildDownloadHeaderRecord(page.requestHeaders)
      };
      items.push(item);
    }
    return items;
  }

  private buildDownloadHeaderRecord(headers?: PageRequestHeader[]): Record<string, string> | undefined {
    if (!headers || headers.length <= 0) {
      return undefined;
    }
    const result: Record<string, string> = {};
    for (let i = 0; i < headers.length; i++) {
      const header = headers[i];
      if (!header || !header.name || !header.value) {
        continue;
      }
      const name = String(header.name).trim();
      const value = String(header.value).trim();
      if (name.length > 0 && value.length > 0) {
        result[name] = value;
      }
    }
    return Object.keys(result).length > 0 ? result : undefined;
  }

  private isPhotos18Content(): boolean {
    if (!this.content || this.content.contentType !== UnifiedContentType.MANGA) {
      return false;
    }
    const sourceName = this.content.sourceName ? this.content.sourceName.toLowerCase() : '';
    if (sourceName.includes('photos18')) {
      return true;
    }
    const sourceUrl = this.content.sourceUrl ? this.content.sourceUrl.toLowerCase() : '';
    if (sourceUrl.includes('photos18.com')) {
      return true;
    }
    const coverUrl = this.content.coverUrl ? this.content.coverUrl.toLowerCase() : '';
    if (coverUrl.includes('photos18.com')) {
      return true;
    }
    return false;
  }

  private getPhotos18Origin(): string {
    return PHOTOS18_ORIGIN;
  }

  private isInvalidPhotos18RefererCandidate(value: string): boolean {
    const trimmed = value.trim();
    return trimmed.length === 0 || trimmed.startsWith('id_') || trimmed.startsWith('local_');
  }

  private buildPhotos18GalleryUrl(rawValue: string): string {
    let candidate = rawValue.trim();
    if (candidate.length === 0) {
      return '';
    }
    const schemeIndex = candidate.indexOf('://');
    if (schemeIndex >= 0) {
      const pathIndex = candidate.indexOf('/', schemeIndex + 3);
      candidate = pathIndex >= 0 ? candidate.substring(pathIndex) : '';
    }
    const queryIndex = candidate.indexOf('?');
    if (queryIndex >= 0) {
      candidate = candidate.substring(0, queryIndex);
    }
    const hashIndex = candidate.indexOf('#');
    if (hashIndex >= 0) {
      candidate = candidate.substring(0, hashIndex);
    }
    if (candidate.startsWith('/zh-hans/')) {
      candidate = candidate.substring('/zh-hans/'.length);
    } else if (candidate === '/zh-hans') {
      candidate = '';
    }
    candidate = candidate.replace(/^\/+/, '').replace(/\/+$/, '');
    if (candidate.startsWith('v/')) {
      candidate = candidate.substring(2);
    }
    if (candidate.length === 0) {
      return '';
    }
    return `${this.getPhotos18Origin()}/v/${candidate}`;
  }

  private resolvePhotos18CoverReferer(externalId: string): string {
    let candidate = '';
    if (this.content && this.content.sourceUrl && !this.isInvalidPhotos18RefererCandidate(this.content.sourceUrl)) {
      candidate = this.content.sourceUrl;
    }
    if (candidate.length === 0 && this.content && !this.isInvalidPhotos18RefererCandidate(this.content.id)) {
      candidate = this.content.id;
    }
    if (candidate.length === 0 && !this.isInvalidPhotos18RefererCandidate(externalId)) {
      candidate = externalId;
    }
    const referer = this.buildPhotos18GalleryUrl(candidate);
    return referer.length > 0 ? referer : this.getPhotos18Origin();
  }

  private buildPhotos18CoverCachePartition(externalId: string, referer: string): string {
    const safeExternalId = externalId.replace(/[^a-zA-Z0-9_-]/g, '_');
    const normalizedReferer = referer.trim().length > 0 ? referer.trim() : this.getPhotos18Origin();
    let hash = 0;
    for (let i = 0; i < normalizedReferer.length; i++) {
      const charCode = normalizedReferer.charCodeAt(i);
      hash = ((hash << 5) - hash) + charCode;
      hash = hash & hash;
    }
    return `photos18_detail_cover_${safeExternalId}_${Math.abs(hash).toString(36)}`;
  }

  private async buildPhotos18CoverLoadOptions(sourceId: number, externalId: string): Promise<OnlineLoadOptions> {
    const referer = this.resolvePhotos18CoverReferer(externalId);
    const headers: RequestHeaders = {} as RequestHeaders;
    headers.userAgent = PHOTOS18_COVER_UA;
    headers.accept = 'image/avif,image/webp,image/png,image/jpeg;q=0.9,*/*;q=0.5';
    headers.referer = referer;
    headers.origin = this.getPhotos18Origin();
    headers.acceptLanguage = 'zh-CN,zh;q=0.9,en-US;q=0.8,en;q=0.7';
    headers.secFetchDest = 'image';
    headers.secFetchMode = 'no-cors';
    headers.secFetchSite = 'same-origin';
    headers.cachePartition = this.buildPhotos18CoverCachePartition(externalId, referer);
    const cookie = await CookieManager.getInstance().getCookieString(sourceId);
    if (cookie.length > 0) {
      headers.cookie = cookie;
    }
    const loadOptions: OnlineLoadOptions = {
      sourceId: sourceId,
      headers: headers,
      priority: 5,
      partitionKey: headers.cachePartition
    };
    return loadOptions;
  }

  private getOnlineMangaExternalIdForCover(manga: Manga, fallbackId: string): string {
    const sourceExternalId: string = typeof manga.sourceInfo?.externalId === 'string'
      ? manga.sourceInfo.externalId.trim()
      : '';
    if (sourceExternalId.length > 0) {
      return sourceExternalId;
    }
    const mangaId: string = manga.id ? manga.id.trim() : '';
    if (mangaId.length > 0) {
      return mangaId;
    }
    return fallbackId ? fallbackId.trim() : '';
  }

  private async persistOnlineMangaCoverUrlForMainMenu(comicId: string, coverUrl: string): Promise<void> {
    const normalizedComicId: string = comicId ? comicId.trim() : '';
    const normalizedCoverUrl: string = coverUrl ? coverUrl.trim() : '';
    if (normalizedComicId.length <= 0 || normalizedCoverUrl.length <= 0) {
      return;
    }
    if (normalizedCoverUrl.startsWith('app.media.') || normalizedCoverUrl.startsWith('$r(')) {
      return;
    }
    try {
      await this.dataManager.updateOnlineComicCoverUrl(normalizedComicId, normalizedCoverUrl);
    } catch (error) {
      logger.warn(
        TAG,
        `同步在线漫画封面到MainMenu失败: comicId=${normalizedComicId}, cover=${normalizedCoverUrl}, error=${String(error)}`
      );
    }
  }
  
  /**
   * 加载封面（在线漫画）
   * 优先级：
   * 1. CoverCacheManager 磁盘缓存（最快）
   * 2. CoverImageManager 内存缓存（快）
   * 3. 触发 CoverImageManager 预加载
   */
  private async loadCachedCover(sourceId: number, externalId: string): Promise<void> {
    try {
      // 1. 尝试从 CoverCacheManager 获取本地磁盘缓存
      const coverCache = CoverCacheManager.getInstance();
      const isPhotos18 = this.isPhotos18Content();
      const photos18Referer = isPhotos18 ? this.resolvePhotos18CoverReferer(externalId) : '';
      let localPath: string | null = null;
      if (isPhotos18) {
        localPath = await coverCache.getLocalCoverPathWithReferer(sourceId, externalId, photos18Referer);
        if (!localPath) {
          localPath = await coverCache.getLocalCoverPath(sourceId, externalId);
        }
      } else {
        localPath = await coverCache.getLocalCoverPath(sourceId, externalId);
      }
      
      if (localPath) {
        logger.info(TAG, `找到本地磁盘缓存封面: ${localPath}`);
        
        // 使用 PixelMap 加载封面
        const imageSource = image.createImageSource(localPath);
        const pixelMap = await imageSource.createPixelMap({ 
          desiredSize: { width: COVER_WIDTH * 2, height: COVER_HEIGHT * 2 } 
        });
        imageSource.release();
        
        if (pixelMap) {
          if (this.coverPixelMap && this.coverPixelMapOwned) {
            this.coverPixelMap.release();
          }
          this.coverPixelMap = pixelMap;
          this.coverPixelMapOwned = true;  // 我们拥有这个 PixelMap
          this.localCoverPath = localPath;
          logger.info(TAG, `封面 PixelMap 加载成功（磁盘缓存）`);
          return;
        }
      }
      
      // 2. 尝试从 CoverImageManager 获取内存缓存或预加载
      const coverUrl = this.content?.coverUrl || '';
      if (coverUrl && (coverUrl.startsWith('http://') || coverUrl.startsWith('https://'))) {
        const coverImageManager = getCoverImageManager();
        const photos18LoadOptions: OnlineLoadOptions | null = isPhotos18
          ? await this.buildPhotos18CoverLoadOptions(sourceId, externalId)
          : null;
        
        // 先检查内存缓存
        let cachedPixelMap = coverImageManager.getCachedPixelMap(coverUrl);
        if (cachedPixelMap) {
          logger.info(TAG, `找到内存缓存封面`);
          if (this.coverPixelMap && this.coverPixelMapOwned) {
            this.coverPixelMap.release();
          }
          this.coverPixelMap = cachedPixelMap;
          this.coverPixelMapOwned = false;  // 从 CoverImageManager 借用，不拥有所有权
          return;
        }
        
        // 触发预加载
        logger.info(TAG, `触发封面预加载: ${coverUrl.substring(0, 50)}...`);
        if (photos18LoadOptions) {
          logger.info(TAG, `Photos18 cover preload referer: ${photos18Referer}`);
        }
        const preloadedPixelMap = photos18LoadOptions
          ? await coverImageManager.preloadCover(coverUrl, photos18LoadOptions)
          : await coverImageManager.preloadCover(coverUrl);
        if (preloadedPixelMap) {
          if (this.coverPixelMap && this.coverPixelMapOwned) {
            this.coverPixelMap.release();
          }
          this.coverPixelMap = preloadedPixelMap;
          this.coverPixelMapOwned = false;  // 从 CoverImageManager 借用，不拥有所有权
          logger.info(TAG, `封面预加载成功`);
        } else {
          logger.warn(TAG, `封面预加载失败，将回退到 AvifImage 组件`);
        }
      } else {
        logger.debug(TAG, `未找到本地缓存封面且无网络 URL: sourceId=${sourceId}, externalId=${externalId}`);
      }
    } catch (error) {
      logger.warn(TAG, `加载封面失败: ${String(error)}`);
    }
  }
  
  /**
   * 判断章节是否完全缓存
   */
  private isChapterFullyCached(chapterId: string): boolean {
    if (this.cacheStats && this.cacheStats.chapterStats) {
      const stat = this.cacheStats.chapterStats.find(s => s.chapterId === chapterId);
      if (stat) {
        return stat.isCached;
      }
    }
    // 回退到 chapter.isDownloaded
    const chapter = this.content?.chapters.find(c => c.id === chapterId);
    return chapter?.isDownloaded || false;
  }

  /**
   * 判断章节是否部分缓存
   */
  private isChapterPartiallyCached(chapterId: string): boolean {
    if (this.cacheStats && this.cacheStats.chapterStats) {
      const stat = this.cacheStats.chapterStats.find(s => s.chapterId === chapterId);
      if (stat) {
        return stat.isPartiallyCached === true;
      }
    }
    return false;
  }

  /**
   * 获取部分缓存描述文本
   */
  private getPartialCacheText(chapterId: string): string {
    if (this.cacheStats && this.cacheStats.chapterStats) {
      const stat = this.cacheStats.chapterStats.find(s => s.chapterId === chapterId);
      if (stat && stat.isPartiallyCached) {
        return `部分缓存 ${stat.cachedPageCount}/${stat.totalPageCount}`;
      }
    }
    return '部分缓存';
  }

  /**
   * 检查是否存在部分缓存的章节
   */
  private hasPartiallyCachedChapters(): boolean {
    if (this.cacheStats && this.cacheStats.chapterStats) {
      return this.cacheStats.chapterStats.some(s => s.isPartiallyCached === true);
    }
    return false;
  }

  /**
   * 保存所有部分缓存的章节为部分归档
   */
  private async savePartiallyCachedChapters(): Promise<void> {
    if (!this.content || !this.cacheStats || !this.cacheStats.chapterStats) {
      return;
    }

    const partialChapters = this.cacheStats.chapterStats.filter(s => s.isPartiallyCached === true);
    if (partialChapters.length === 0) {
      return;
    }

    this.isDownloading = true;
    let savedCount = 0;

    try {
      for (const chapter of partialChapters) {
        const success = await this.unifiedDownloadManager.savePartialDownload(this.content.id, chapter.chapterId);
        if (success) {
          savedCount++;
        }
      }

      if (savedCount > 0) {
        this.getUIContext().getPromptAction().showToast({ message: `已保存 ${savedCount} 个章节` });
        await this.loadCacheStatus();
      } else {
        this.getUIContext().getPromptAction().showToast({ message: '保存失败' });
      }
    } catch (error) {
      logger.error(TAG, `保存部分缓存章节失败: ${String(error)}`);
      this.getUIContext().getPromptAction().showToast({ message: '保存失败' });
    } finally {
      this.isDownloading = false;
    }
  }

  /**
   * 加载缓存状态信息
   * 对于在线漫画和小说，检查并加载缓存状态
   */
  private async loadCacheStatus(): Promise<void> {
    if (!this.content || !this.pageParams) return;
    
    try {
      // 判断是否需要显示缓存卡片
      const isOnline = this.isOnlineManga();
      const isNovel = this.content.contentType === UnifiedContentType.NOVEL;
      
      // 只有在线漫画和小说需要显示缓存状态
      if (!isOnline && !isNovel) {
        this.showCacheStatusCard = false;
        return;
      }
      
      this.isCacheStatsLoading = true;
      
      if (isOnline) {
        // 在线漫画：检查边看边下载是否开启
        const sourceId = Number(this.pageParams.sourceId);
        const downloadWhileReadingEnabled = await this.cacheStatusService.isDownloadWhileReadingEnabled(sourceId);
        
        if (downloadWhileReadingEnabled) {
          // 加载漫画缓存状态
          this.cacheStats = await this.cacheStatusService.getMangaCacheStatus(
            sourceId,
            this.content.id,
            this.content.title
          );
          this.showCacheStatusCard = true;
          logger.info(TAG, `漫画缓存状态加载完成: ${this.cacheStats.cachedChapterCount}/${this.cacheStats.totalChapterCount}章`);
        } else {
          // 边看边下载未开启，不显示缓存卡片
          this.showCacheStatusCard = false;
          this.cacheStats = null;
        }
      } else if (isNovel) {
        // 小说：始终加载并显示缓存状态（使用与NovelReaderPage一致的bookId格式）
        const sourceId = this.getCurrentNovelSourceId();
        const novelCacheBookId = this.getNovelCacheBookId(sourceId, this.content.id);
        this.cacheStats = await this.cacheStatusService.getNovelCacheStatus(
          novelCacheBookId,
          this.content.title,
          this.content.totalChapters
        );
        // 小说始终显示缓存卡片，方便用户了解缓存情况和进行下载操作
        this.showCacheStatusCard = true;
        logger.info(
          TAG,
          `${this.isCurrentNovelAudioSource() ? '听书缓存' : '小说缓存'}状态加载完成: ${this.cacheStats.cachedChapterCount}/${this.cacheStats.totalChapterCount}章`
        );
      }
    } catch (error) {
      logger.error(TAG, `加载缓存状态失败: ${String(error)}`);
      this.showCacheStatusCard = false;
      this.cacheStats = null;
    } finally {
      this.isCacheStatsLoading = false;
    }
  }

  private supportsReadAloudCacheSection(): boolean {
    if (this.isCurrentNovelAudioSource()) {
      return false;
    }
    return this.remoteReadAloudCacheService.supportsContent(this.content);
  }

  private isLocalTxtNovelEBookContent(): boolean {
    if (!this.content || this.content.contentType !== UnifiedContentType.EBOOK) {
      return false;
    }
    const ebook = EBookAdapter.getOriginalEBook(this.content);
    return !!ebook && ebook.format === EBookFormat.TXT;
  }

  private isLocalWebTextEBookContent(): boolean {
    if (!this.content || !this.isLocalImportedEBookContent()) {
      return false;
    }
    const ebook = EBookAdapter.getOriginalEBook(this.content);
    if (!ebook) {
      return false;
    }
    if (ebook.format === EBookFormat.MOBI ||
      ebook.format === EBookFormat.AZW ||
      ebook.format === EBookFormat.AZW3) {
      return true;
    }
    if (ebook.format !== EBookFormat.EPUB) {
      return false;
    }
    return resolveEBookReaderRouteName(ebook) === 'EpubWebViewReaderPage';
  }

  private isLocalReadAloudCapableEBookContent(): boolean {
    return this.isLocalTxtNovelEBookContent() || this.isLocalWebTextEBookContent();
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
      this.isChapterListExpanded = !this.isChapterListExpanded;
    });
  }

  private isValidReadProgressPercent(value: number | undefined | null): boolean {
    return typeof value === 'number' && Number.isFinite(value) && value >= 0 && value <= 100;
  }

  private clampReadProgressPercent(value: number): number {
    if (!Number.isFinite(value)) {
      return 0;
    }
    return Math.max(0, Math.min(100, Math.round(value)));
  }

  private getChapterAlignedReadProgressPercent(lastReadChapterIndex: number, totalChapters: number): number {
    if (!Number.isFinite(lastReadChapterIndex) || totalChapters <= 0 || lastReadChapterIndex < 0) {
      return 0;
    }
    const safeLastReadChapterIndex = Math.max(0, Math.min(Math.floor(lastReadChapterIndex), totalChapters - 1));
    return this.clampReadProgressPercent(((safeLastReadChapterIndex + 1) / totalChapters) * 100);
  }

  private hasEBookReadingRecord(ebook: EBook | null): boolean {
    if (!this.content) {
      return false;
    }
    if (this.content.readStatus === UnifiedReadStatus.COMPLETED) {
      return true;
    }
    const progress = ebook?.readingProgress;
    if (!progress) {
      return this.content.readStatus === UnifiedReadStatus.READING && this.content.lastReadChapterIndex >= 0;
    }
    if (this.isValidReadProgressPercent(progress.progress) && progress.progress > 0) {
      return true;
    }
    if ((progress.domPos || '').trim().length > 0) {
      return true;
    }
    if ((progress.currentPosition ?? 0) > 0) {
      return true;
    }
    if ((progress.currentChapterIndex ?? 0) > 0) {
      return true;
    }
    return (progress.lastReadTime ?? 0) > 0 || this.content.readStatus === UnifiedReadStatus.READING;
  }

  private resolveDisplayReadProgressPercent(): number {
    if (!this.content) {
      return 0;
    }
    if (this.content.readStatus === UnifiedReadStatus.COMPLETED) {
      return 100;
    }

    const chapterAlignedProgress = this.getChapterAlignedReadProgressPercent(
      this.content.lastReadChapterIndex,
      this.content.totalChapters
    );

    switch (this.content.contentType) {
      case UnifiedContentType.EBOOK: {
        const ebook = EBookAdapter.getOriginalEBook(this.content);
        const rawProgress = ebook?.readingProgress?.progress ?? this.content.readProgress;
        if (this.isValidReadProgressPercent(rawProgress)) {
          const normalizedProgress = this.clampReadProgressPercent(rawProgress);
          if (this.content.totalChapters > 1 && chapterAlignedProgress > 0 && this.hasEBookReadingRecord(ebook)) {
            return Math.max(normalizedProgress, chapterAlignedProgress);
          }
          return normalizedProgress;
        }
        if (chapterAlignedProgress > 0 && this.hasEBookReadingRecord(ebook)) {
          return chapterAlignedProgress;
        }
        return this.hasEBookReadingRecord(ebook) ? 1 : 0;
      }
      case UnifiedContentType.NOVEL: {
        if (this.isValidReadProgressPercent(this.content.readProgress)) {
          const normalizedProgress = this.clampReadProgressPercent(this.content.readProgress);
          if (this.content.totalChapters > 1 && chapterAlignedProgress > 0) {
            return Math.max(normalizedProgress, chapterAlignedProgress);
          }
          return normalizedProgress;
        }
        if (chapterAlignedProgress > 0) {
          return chapterAlignedProgress;
        }
        return this.content.readStatus === UnifiedReadStatus.READING ? 1 : 0;
      }
      default: {
        if (this.isValidReadProgressPercent(this.content.readProgress)) {
          return this.clampReadProgressPercent(this.content.readProgress);
        }
        if (chapterAlignedProgress > 0) {
          return chapterAlignedProgress;
        }
        return this.content.readStatus === UnifiedReadStatus.READING ? 1 : 0;
      }
    }
  }

  private normalizeCurrentContentReadProgress(): void {
    if (!this.content) {
      return;
    }
    this.content.readProgress = this.resolveDisplayReadProgressPercent();
  }

  /**
   * 获取阅读状态显示文本
   */
  private getReadStatusText(): string {
    if (!this.content) return '';
    switch (this.content.readStatus) {
      case UnifiedReadStatus.UNREAD:
        return '未读';
      case UnifiedReadStatus.READING:
        return `阅读中 ${this.resolveDisplayReadProgressPercent()}%`;
      case UnifiedReadStatus.COMPLETED:
        return '已读完';
      default:
        return '';
    }
  }

  // ==================== 快捷搜索功能 ====================
  
  /**
   * 复制文本到剪贴板
   */
  private copyToClipboard(text: string): void {
    try {
      const cleanText = this.stripHtmlTags(text).trim();
      if (!cleanText) return;
      const pasteData = pasteboard.createData(pasteboard.MIMETYPE_TEXT_PLAIN, cleanText);
      const systemPasteboard = pasteboard.getSystemPasteboard();
      systemPasteboard.setData(pasteData);
      this.getUIContext().getPromptAction().showToast({ message: '已复制', duration: 1500 });
    } catch (error) {
      logger.error(TAG, `复制到剪贴板失败: ${String(error)}`);
      this.getUIContext().getPromptAction().showToast({ message: '复制失败', duration: 1500 });
    }
  }
  
  /**
   * 导航到全局搜索页面
   * 根据当前内容类型自动设置搜索范围：
   * - 漫画：仅搜索已开启的图源+本地漫画
   * - 小说：仅搜索已开启的书源+本地小说
   * - 电子书：仅搜索本地内容
   */
  private navigateToSearch(keyword: string): void {
    if (!keyword || keyword.trim() === '') return;
    
    const cleanKeyword = this.stripHtmlTags(keyword).trim();
    if (!cleanKeyword) return;
    
    // 根据当前内容类型确定搜索范围
    let initialContentType: string = 'all';
    let initialSourceType: string = 'all';
    
    if (this.content) {
      switch (this.content.contentType) {
        case UnifiedContentType.MANGA:
          // 漫画：搜索漫画类型，本地+已开启图源
          initialContentType = 'manga';
          initialSourceType = 'all';
          break;
        case UnifiedContentType.NOVEL:
          // 小说：搜索小说类型，本地+已开启书源
          initialContentType = 'novel';
          initialSourceType = 'all';
          break;
        case UnifiedContentType.EBOOK:
          // 电子书：仅搜索本地内容
          initialContentType = 'all';
          initialSourceType = 'local';
          break;
      }
    }
    
    const params: GlobalSearchPageParams = {
      initialKeyword: cleanKeyword,
      initialContentType: initialContentType,
      initialSourceType: initialSourceType,
      autoSelectAllSources: initialSourceType !== 'local'  // 非纯本地搜索时自动选中所有已开启源
    };
    
    logger.info(TAG, `快捷搜索: keyword="${cleanKeyword}", contentType=${initialContentType}, sourceType=${initialSourceType}`);
    this.navigateWithManagedWindowTransition('GlobalSearchPage', params);
  }

  // ==================== 智能推荐功能 ====================

  /**
   * 判断当前内容是否应使用在线推荐（搜索图源）
   * 小说始终使用本地推荐（在数据库中搜索），因为小说数据本地化存储
   * 在线漫画 / 在线电子书 使用图源搜索
   */
  private shouldUseOnlineRecommendation(): boolean {
    if (!this.content) return false;
    if (this.content.contentType === UnifiedContentType.NOVEL) return false;
    if (this.isPhotos18Content()) {
      logger.info(TAG, 'Photos18详情页跳过在线推荐，避免复用隐藏WebView打断页面预加载');
      return false;
    }
    return this.isOnlineContent();
  }

  /**
   * 拆分多作者字符串
   * 支持中文/日文/英文常见分隔符：，、·/&,；×xX 及空格
   */
  private splitAuthorNames(authorStr: string): string[] {
    if (!authorStr || !authorStr.trim()) return [];
    return authorStr
      .split(/[，、·\/&,；\s×xX]+/)
      .map((a: string) => a.trim())
      .filter((a: string) => a.length > 0);
  }

  /**
   * 计算字符串 bigram 集合（用于相似度计算）
   */
  private computeBigramSet(text: string): string[] {
    if (!text || text.length < 2) return text.length === 1 ? [text] : [];
    const bigrams: string[] = [];
    for (let i = 0; i < text.length - 1; i++) {
      bigrams.push(text.substring(i, i + 2));
    }
    return bigrams;
  }

  /**
   * Bigram Jaccard 相似度（0~1）
   * 用于估算两个字符串的相关程度
   */
  private bigramJaccard(a: string, b: string): number {
    if (!a || !b) return 0;
    if (a === b) return 1;
    const bigramsA = this.computeBigramSet(a);
    const bigramsB = this.computeBigramSet(b);
    if (bigramsA.length === 0 || bigramsB.length === 0) return 0;
    const setB = new Set<string>(bigramsB);
    let intersection = 0;
    for (let i = 0; i < bigramsA.length; i++) {
      if (setB.has(bigramsA[i])) intersection++;
    }
    const union = bigramsA.length + bigramsB.length - intersection;
    return union > 0 ? intersection / union : 0;
  }

  /**
   * 计算候选内容与当前内容的综合相关度评分
   * 标题（权重3）> 作者（权重2）> 标签（每个 10 分，上限 30）
   */
  private calculateRelevanceScore(
    currentTitle: string,
    currentAuthor: string,
    currentTags: string[],
    candidateTitle: string,
    candidateAuthor: string,
    candidateTags: string[]
  ): number {
    let score = 0;

    // 标题相似度（权重 3）
    const titleSim = this.bigramJaccard(currentTitle, candidateTitle);
    score += titleSim * 100 * 3;

    // 作者匹配（权重 2）
    if (currentAuthor && candidateAuthor) {
      if (currentAuthor === candidateAuthor) {
        score += 80 * 2;
      } else if (currentAuthor.includes(candidateAuthor) || candidateAuthor.includes(currentAuthor)) {
        score += 40 * 2;
      }
    }

    // 标签重叠（每个 10 分，上限 30）
    if (currentTags.length > 0 && candidateTags.length > 0) {
      let tagMatches = 0;
      for (let i = 0; i < currentTags.length; i++) {
        if (candidateTags.indexOf(currentTags[i]) >= 0) tagMatches++;
      }
      score += Math.min(tagMatches * 10, 30);
    }

    return Math.round(score);
  }

  private async getFavoritedMangaIdSet(): Promise<Set<string>> {
    const favoritedIds: Set<string> = new Set<string>();
    try {
      const favorites = await this.dataManager.getUserFavorites('default_user');
      for (let index = 0; index < favorites.length; index++) {
        const favoriteComicId = favorites[index].comicId;
        if (favoriteComicId && favoriteComicId.trim().length > 0) {
          favoritedIds.add(favoriteComicId);
        }
      }
    } catch (error) {
      logger.warn(TAG, `加载漫画收藏ID列表失败: ${String(error)}`);
    }
    return favoritedIds;
  }

  private async isOnlineRecommendationFavorited(
    recommendationContentId: string,
    recommendationType: UnifiedContentType,
    favoritedMangaIds: Set<string>
  ): Promise<boolean> {
    if (recommendationType === UnifiedContentType.MANGA) {
      return favoritedMangaIds.has(recommendationContentId);
    }
    if (recommendationType === UnifiedContentType.EBOOK) {
      const ebook = await this.ebookDataManager.getEBookById(recommendationContentId);
      return ebook !== null && ebook.isFavorite;
    }
    return false;
  }

  /**
   * 触发智能推荐加载（内容加载完成后调用）
   */
  private async loadRecommendations(): Promise<void> {
    if (!this.content) return;

    this.isLoadingRecommendations = true;
    this.recommendedItems = [];

    try {
      if (this.shouldUseOnlineRecommendation()) {
        await this.loadOnlineRecommendations();
      } else {
        await this.loadLocalRecommendations();
      }
    } catch (error) {
      logger.warn(TAG, `智能推荐加载失败: ${String(error)}`);
    } finally {
      this.isLoadingRecommendations = false;
    }
  }

  /**
   * 本地推荐：在本地数据库中搜索相关内容并按相关度排序
   * 覆盖本地漫画、本地电子书、数据库中的小说
   */
  private async loadLocalRecommendations(): Promise<void> {
    if (!this.content) return;

    const currentId = this.content.id;
    const currentTitle = this.stripHtmlTags(this.content.title || '').toLowerCase().trim();
    const currentAuthor = this.stripHtmlTags(this.content.author || '').toLowerCase().trim();
    const currentGenres = (this.content.genres || []).map((g: string) => this.stripHtmlTags(g).toLowerCase().trim());
    const currentTags = (this.content.tags || []).map((t: string) => this.stripHtmlTags(t).toLowerCase().trim());
    const allCurrentTags: string[] = [...currentGenres, ...currentTags].filter((t: string) => t.length > 0);

    const candidates: RecommendationItem[] = [];
    const favoritedMangaIds = await this.getFavoritedMangaIdSet();

    // ---- 查询本地漫画 ----
    // [性能优化] 使用 SQL LIKE 预过滤，缩小候选集
    try {
      const comics = await this.dataManager.getRecommendationCandidateComics(currentAuthor, allCurrentTags);
      for (let ci = 0; ci < comics.length; ci++) {
        const comic = comics[ci];
        if (comic.id === currentId) continue;
        if (!favoritedMangaIds.has(comic.id)) continue;
        const cTitle = (comic.title || '').toLowerCase().trim();
        const cAuthor = (comic.author || '').toLowerCase().trim();
        const cTags = (comic.tags || []).map((t: string) => t.toLowerCase().trim());
        const score = this.calculateRelevanceScore(currentTitle, currentAuthor, allCurrentTags, cTitle, cAuthor, cTags);
        if (score >= RECOMMEND_MIN_SCORE) {
          const coverUrl = comic.coverLocalPath || comic.coverUrl || '';
          const item: RecommendationItem = {
            id: `rec_manga_${comic.id}`,
            title: comic.title || '未知标题',
            coverUrl: coverUrl,
            contentType: UnifiedContentType.MANGA,
            isFavorited: true,
            isLocal: true,
            score: score,
            navContentId: comic.id
          };
          candidates.push(item);
        }
      }
    } catch (e) {
      logger.warn(TAG, `本地漫画推荐查询失败: ${String(e)}`);
    }

    // ---- 查询本地电子书 ----
    try {
      const ebooks = await this.ebookDataManager.getNonPrivateEBooks();
      for (let ei = 0; ei < ebooks.length; ei++) {
        const ebook = ebooks[ei];
        if (!ebook.metadata) continue;
        if (ebook.id === currentId) continue;
        if (!ebook.isFavorite) continue;
        const cTitle = (ebook.metadata.title || '').toLowerCase().trim();
        const cAuthor = (ebook.metadata.author || '').toLowerCase().trim();
        const cTags = (ebook.metadata.tags || []).map((t: string) => t.toLowerCase().trim());
        const score = this.calculateRelevanceScore(currentTitle, currentAuthor, allCurrentTags, cTitle, cAuthor, cTags);
        if (score >= RECOMMEND_MIN_SCORE) {
          const item: RecommendationItem = {
            id: `rec_ebook_${ebook.id}`,
            title: ebook.metadata.title || '未知标题',
            coverUrl: ebook.metadata.coverImagePath || '',
            contentType: UnifiedContentType.EBOOK,
            isFavorited: true,
            isLocal: true,
            score: score,
            navContentId: ebook.id
          };
          candidates.push(item);
        }
      }
    } catch (e) {
      logger.warn(TAG, `本地电子书推荐查询失败: ${String(e)}`);
    }

    // ---- 查询数据库中的小说 ----
    try {
      const novels = await this.novelDataManager.getNonPrivateBooks();
      for (let ni = 0; ni < novels.length; ni++) {
        const novel = novels[ni];
        if (novel.bookUrl === currentId || novel.id === currentId) continue;
        if (!novel.isFavorite) continue;
        const cTitle = (novel.name || '').toLowerCase().trim();
        const cAuthor = (novel.author || '').toLowerCase().trim();
        // kind 字段存放分类/标签，按逗号等分隔
        const cTags = (novel.kind || '')
          .split(/[,，、\s]+/)
          .map((t: string) => t.trim().toLowerCase())
          .filter((t: string) => t.length > 0);
        const score = this.calculateRelevanceScore(currentTitle, currentAuthor, allCurrentTags, cTitle, cAuthor, cTags);
        if (score >= RECOMMEND_MIN_SCORE) {
          const item: RecommendationItem = {
            id: `rec_novel_${novel.id}`,
            title: novel.name || '未知标题',
            coverUrl: novel.coverLocalPath || novel.coverUrl || '',
            contentType: UnifiedContentType.NOVEL,
            isFavorited: true,
            isLocal: false,
            sourceName: novel.sourceName,
            score: score,
            navContentId: novel.bookUrl,
            navSourceId: novel.sourceId
          };
          candidates.push(item);
        }
      }
    } catch (e) {
      logger.warn(TAG, `小说推荐查询失败: ${String(e)}`);
    }

    // 按相关度降序排列，取前 RECOMMEND_MAX_COUNT 条
    candidates.sort((a: RecommendationItem, b: RecommendationItem) => b.score - a.score);
    this.recommendedItems = candidates.slice(0, RECOMMEND_MAX_COUNT);
    logger.info(TAG, `本地推荐加载完成: ${this.recommendedItems.length} 条（仅已收藏）`);
  }

  /**
   * 在线推荐：使用当前内容的作者名在同图源搜索
   * 适用于在线漫画、在线电子书
   */
  private async loadOnlineRecommendations(): Promise<void> {
    if (!this.content) return;

    const authorStr = this.stripHtmlTags(this.content.author || '').trim();
    if (!authorStr) {
      logger.info(TAG, '在线推荐: 无作者信息，跳过');
      return;
    }

    // 拆分多作者，取第一个作为搜索关键词
    const authors = this.splitAuthorNames(authorStr);
    if (authors.length === 0) return;
    const searchKeyword = authors[0];

    const sourceIdNum = this.content.sourceId ? Number(this.content.sourceId) : 0;
    if (!sourceIdNum || sourceIdNum <= 0) return;

    const currentContentId = this.content.id;
    const results: RecommendationItem[] = [];
    const seenIds = new Set<string>();
    seenIds.add(currentContentId);
    const favoritedMangaIds = this.content.contentType === UnifiedContentType.MANGA
      ? await this.getFavoritedMangaIdSet()
      : new Set<string>();

    try {
      logger.info(TAG, `在线推荐搜索: sourceId=${sourceIdNum}, keyword="${searchKeyword}"`);
      const globalSearch = GlobalSearchService.getInstance();
      const searchItems = await globalSearch.searchOnlineManga(sourceIdNum, searchKeyword);

      for (let si = 0; si < searchItems.length; si++) {
        if (results.length >= RECOMMEND_MAX_COUNT) break;
        const item = searchItems[si];
        const comic = item.rawOnlineComic;
        if (!comic) continue;
        const comicId = comic.id || comic.url || '';
        if (!comicId || seenIds.has(comicId)) continue;
        const isFavorited = await this.isOnlineRecommendationFavorited(
          comicId,
          this.content.contentType,
          favoritedMangaIds
        );
        if (!isFavorited) continue;
        seenIds.add(comicId);

        const recItem: RecommendationItem = {
          id: `rec_online_${sourceIdNum}_${comicId}`,
          title: item.title || '未知标题',
          coverUrl: item.coverUrl || '',
          contentType: this.content.contentType,
          isFavorited: true,
          isLocal: false,
          sourceId: String(sourceIdNum),
          sourceName: this.getDisplaySourceName(),
          score: 0,
          navContentId: comicId,
          navSourceId: String(sourceIdNum)
        };
        results.push(recItem);
      }
    } catch (e) {
      logger.warn(TAG, `在线推荐搜索失败: ${String(e)}`);
    }

    this.recommendedItems = results;
    logger.info(TAG, `在线推荐加载完成: ${this.recommendedItems.length} 条（仅已收藏）`);
  }

  /**
   * 点击推荐项，导航到对应的统一详情页
   */
  private navigateToRecommendedItem(item: RecommendationItem): void {
    const params: UnifiedDetailPageParams = {
      contentType: item.contentType,
      contentId: item.navContentId,
      sourceId: item.navSourceId,
      cachedTitle: item.title,
      cachedCoverPath: item.coverUrl && !item.coverUrl.startsWith('http://') && !item.coverUrl.startsWith('https://')
        ? item.coverUrl
        : undefined,
      cachedCover: item.coverUrl
    };
    logger.info(TAG, `跳转推荐内容: type=${item.contentType}, id=${item.navContentId}`);
    this.navigateWithManagedWindowTransition('UnifiedDetailPage', params);
  }

  // ==================== 同书架内容功能 ====================

  /**
   * 加载同书架的其他内容
   * 仅当内容在自定义书架中时执行
   */
  private async loadShelfContent(): Promise<void> {
    if (!this.content || !this.currentShelfId) return;

    this.isLoadingShelfContent = true;
    this.shelfContentItems = [];
    this.shelfContentFilter = 'all';

    try {
      const shelfItems: CategoryItem[] = this.typeShelfManager.getShelfItems(this.currentShelfId);
      const currentId = this.content.id;
      const candidateItems: CategoryItem[] = [];
      const mangaCandidateIds: string[] = [];
      const items: ShelfContentItem[] = [];

      for (let i = 0; i < shelfItems.length && candidateItems.length < SHELF_CONTENT_CANDIDATE_SCAN_COUNT; i++) {
        const catItem = shelfItems[i];
        if (catItem.itemId === currentId) {
          continue;
        }
        candidateItems.push(catItem);
        if (catItem.contentType === ContentType.MANGA && !mangaCandidateIds.includes(catItem.itemId)) {
          mangaCandidateIds.push(catItem.itemId);
        }
      }

      const mangaInfoMap: Map<string, ComicInfo> = await this.dataManager.getComicsByIds(mangaCandidateIds);

      for (let i = 0; i < candidateItems.length && items.length < SHELF_CONTENT_MAX_COUNT; i++) {
        const catItem = candidateItems[i];

        try {
          switch (catItem.contentType) {
            case ContentType.MANGA: {
              const comic = mangaInfoMap.get(catItem.itemId);
              if (comic) {
                const coverUrl = comic.coverLocalPath || comic.coverUrl || '';
                const item: ShelfContentItem = {
                  id: `shelf_manga_${catItem.itemId}`,
                  title: comic.title || '未知标题',
                  coverUrl: coverUrl,
                  contentType: UnifiedContentType.MANGA,
                  navContentId: catItem.itemId
                };
                items.push(item);
              }
              break;
            }
            case ContentType.EBOOK: {
              const ebook = await this.ebookDataManager.getEBookById(catItem.itemId);
              if (ebook && ebook.metadata) {
                const item: ShelfContentItem = {
                  id: `shelf_ebook_${catItem.itemId}`,
                  title: ebook.metadata.title || '未知标题',
                  coverUrl: ebook.metadata.coverImagePath || '',
                  contentType: UnifiedContentType.EBOOK,
                  navContentId: catItem.itemId
                };
                items.push(item);
              }
              break;
            }
            case ContentType.NOVEL: {
              const novel = await this.novelDataManager.getBook(catItem.itemId);
              if (novel) {
                const item: ShelfContentItem = {
                  id: `shelf_novel_${catItem.itemId}`,
                  title: novel.name || '未知标题',
                  coverUrl: novel.coverLocalPath || novel.coverUrl || '',
                  contentType: UnifiedContentType.NOVEL,
                  navContentId: novel.bookUrl,
                  navSourceId: novel.sourceId
                };
                items.push(item);
              }
              break;
            }
          }
        } catch (e) {
          logger.warn(TAG, `加载书架内容项失败: ${catItem.itemId}, ${String(e)}`);
        }
      }

      this.shelfContentItems = items;
      logger.info(TAG, `同书架内容加载完成: ${items.length} 项 (书架: ${this.currentShelfName})`);
    } catch (error) {
      logger.warn(TAG, `加载同书架内容失败: ${String(error)}`);
    } finally {
      this.isLoadingShelfContent = false;
    }
  }

  /**
   * 获取经筛选后的同书架内容列表
   */
  private getFilteredShelfContentItems(): ShelfContentItem[] {
    if (this.shelfContentFilter === 'all') {
      return this.shelfContentItems;
    }
    const filterType: UnifiedContentType = this.shelfContentFilter === 'manga'
      ? UnifiedContentType.MANGA
      : this.shelfContentFilter === 'novel'
        ? UnifiedContentType.NOVEL
        : UnifiedContentType.EBOOK;
    return this.shelfContentItems.filter((item: ShelfContentItem) => item.contentType === filterType);
  }

  /**
   * 点击同书架内容项，导航到对应的统一详情页
   */
  private navigateToShelfContentItem(item: ShelfContentItem): void {
    const params: UnifiedDetailPageParams = {
      contentType: item.contentType,
      contentId: item.navContentId,
      sourceId: item.navSourceId,
      cachedTitle: item.title,
      cachedCoverPath: item.coverUrl && !item.coverUrl.startsWith('http://') && !item.coverUrl.startsWith('https://')
        ? item.coverUrl
        : undefined,
      cachedCover: item.coverUrl
    };
    logger.info(TAG, `跳转同书架内容: type=${item.contentType}, id=${item.navContentId}`);
    this.navigateWithManagedWindowTransition('UnifiedDetailPage', params);
  }

  /**
   * 检查同书架内容是否包含多种类型（用于决定是否显示筛选栏）
   */
  private hasMultipleContentTypes(): boolean {
    const types = new Set<UnifiedContentType>();
    for (const item of this.shelfContentItems) {
      types.add(item.contentType);
      if (types.size > 1) return true;
    }
    return false;
  }

  // ==================== UI构建 ====================

  /**
   * 获取封面图片路径（处理本地文件路径）
   */
  private getCoverImageSource(): string | Resource {
    const coverUrl = this.getRawCoverImagePath();
    if (!coverUrl) {
      return '';
    }

    if (coverUrl.startsWith('app.media.')) {
      return this.resolveAppMediaCoverResource(coverUrl);
    }

    if (coverUrl.startsWith('http://') || coverUrl.startsWith('https://')) {
      return coverUrl;
    }

    if (coverUrl.startsWith('file://')) {
      return coverUrl;
    }

    if (coverUrl.startsWith('/')) {
      return `file://${coverUrl}`;
    }

    return coverUrl;
  }

  private getRawCoverImagePath(): string {
    const originalManga = this.content && this.content.contentType === UnifiedContentType.MANGA
      ? MangaAdapter.getOriginalManga(this.content)
      : null;
    return this.resolveUnifiedCoverImagePath(originalManga);
  }

  private normalizeCoverPathCandidate(value: string | undefined | null): string {
    if (value === undefined || value === null) {
      return '';
    }
    return String(value).trim();
  }

  private resolveUnifiedCoverImagePath(originalManga?: Manga | null): string {
    const candidates: string[] = [
      this.normalizeCoverPathCandidate(this.localCoverPath),
      this.normalizeCoverPathCandidate(this.content?.coverUrl),
      this.normalizeCoverPathCandidate(originalManga?.coverImagePath),
      this.normalizeCoverPathCandidate(this.pageParams?.cachedCoverPath),
      this.normalizeCoverPathCandidate(this.pageParams?.cachedCover)
    ];
    for (let i = 0; i < candidates.length; i++) {
      const candidate = candidates[i];
      if (candidate.length > 0) {
        return candidate;
      }
    }
    return '';
  }

  private resolveCoverSourceType(coverPath: string): ImageSourceType {
    if (coverPath.startsWith('http://') || coverPath.startsWith('https://')) {
      return ImageSourceType.NETWORK;
    }
    if (coverPath.startsWith('app.media.')) {
      return ImageSourceType.RESOURCE;
    }
    if (coverPath.length > 0) {
      return ImageSourceType.LOCAL;
    }
    if (this.content?.isLocal) {
      return ImageSourceType.LOCAL;
    }
    return ImageSourceType.NETWORK;
  }

  private buildCoverCandidateDebugText(originalManga?: Manga | null): string {
    const parts: string[] = [];
    parts.push(`local=${this.localCoverPath ? 'yes' : 'no'}`);
    parts.push(`content=${this.content?.coverUrl ? 'yes' : 'no'}`);
    parts.push(`original=${originalManga?.coverImagePath ? 'yes' : 'no'}`);
    parts.push(`cachedPath=${this.pageParams?.cachedCoverPath ? 'yes' : 'no'}`);
    parts.push(`cached=${this.pageParams?.cachedCover ? 'yes' : 'no'}`);
    parts.push(`pixelMap=${this.coverPixelMap ? 'yes' : 'no'}`);
    return parts.join(',');
  }

  private getDisplayTitleText(): string {
    const contentTitle: string = this.stripHtmlTags(this.content?.title || '').trim();
    if (contentTitle.length > 0) {
      return contentTitle;
    }
    const cachedTitle: string = this.stripHtmlTags(this.pageParams?.cachedTitle || '').trim();
    if (cachedTitle.length > 0) {
      return cachedTitle;
    }
    return '加载中...';
  }

  private getDisplayAuthorText(): string {
    const contentAuthor: string = this.stripHtmlTags(this.content?.author || '').trim();
    if (contentAuthor.length > 0) {
      return contentAuthor;
    }
    const cachedAuthor: string = this.stripHtmlTags(this.pageParams?.cachedAuthor || '').trim();
    return cachedAuthor;
  }

  private hasRenderablePrimaryContent(): boolean {
    if (this.content !== null) {
      return true;
    }
    const cachedTitle: string = this.stripHtmlTags(this.pageParams?.cachedTitle || '').trim();
    const cachedCover: string = (this.pageParams?.cachedCoverPath || this.pageParams?.cachedCover || '').trim();
    const cachedAuthor: string = this.stripHtmlTags(this.pageParams?.cachedAuthor || '').trim();
    return cachedTitle.length > 0 || cachedCover.length > 0 || cachedAuthor.length > 0;
  }

  private hasCoverImageSource(): boolean {
    return this.getRawCoverImagePath().length > 0;
  }

  private isNetworkCover(): boolean {
    const coverUrl = this.getRawCoverImagePath();
    return coverUrl.startsWith('http://') || coverUrl.startsWith('https://');
  }

  private resolveAppMediaCoverResource(raw: string): Resource {
    const resourceName = raw.substring('app.media.'.length);
    if (resourceName === 'mangabook') {
      return $r('app.media.mangabook');
    }
    if (resourceName === 'ebook') {
      return $r('app.media.ebook');
    }
    if (resourceName === 'ic_ebook') {
      return $r('app.media.ic_ebook');
    }
    if (resourceName === 'icon') {
      return $r('app.media.icon');
    }
    if (resourceName === 'ic_source_novel' || resourceName === 'ic_novel') {
      return $r('app.media.ic_source_novel');
    }
    return $r('app.media.ebook');
  }
  
  /**
   * 清理章节标题，移除"第X话"等前缀，只保留真实标题
   * 支持多种语言格式
   * @returns [prefix, cleanTitle] 数组
   */
  private cleanChapterTitle(title: string, chapterIndex: number): string[] {
    const defaultPrefix = `第${chapterIndex + 1}话`;
    
    if (!title) {
      return [defaultPrefix, ''];
    }
    
    // 匹配各种章节前缀格式
    const prefixPatterns: RegExp[] = [
      // 中文格式
      /^第\s*(\d+(?:\.\d+)?)\s*[话話章回集卷]/,
      /^第\s*([零一二三四五六七八九十百千万]+)\s*[话話章回集卷]/,
      // 日文格式
      /^第\s*(\d+(?:\.\d+)?)\s*話/,
      // 英文格式
      /^(?:Chapter|Ch\.?|Episode|Ep\.?|Vol\.?|Part)\s*(\d+(?:\.\d+)?)/i,
      // 韩文格式
      /^(\d+)\s*화/,
      // 纯数字格式
      /^(\d+(?:\.\d+)?)\s*[\.:\-\s]/,
    ];
    
    for (const pattern of prefixPatterns) {
      const match = title.match(pattern);
      if (match) {
        const matchedPrefix = match[0];
        let cleanTitle = title.substring(matchedPrefix.length).trim();
        
        // 移除可能的分隔符
        cleanTitle = cleanTitle.replace(/^[\s\-:：\.\|]+/, '').trim();
        
        // 如果清理后的标题为空，使用原标题
        if (!cleanTitle) {
          return [defaultPrefix, title];
        }
        
        return [defaultPrefix, cleanTitle];
      }
    }
    
    // 没有匹配到前缀，返回原标题
    return [defaultPrefix, title];
  }

  @Builder
  buildHeader() {
    Row({ space: 16 }) {
      // 封面（优先使用本地缓存的 PixelMap）
      Stack() {
        if (this.coverPixelMap) {
          // 优先使用本地缓存的 PixelMap（速度最快）
          Image(this.coverPixelMap)
            .width(COVER_WIDTH)
            .height(COVER_HEIGHT)
            .objectFit(ImageFit.Cover)
            .borderRadius(8)
        } else if (this.isCoverLoading && !this.hasCoverImageSource()) {
          Column({ space: 10 }) {
            LoadingProgress()
              .width(24)
              .height(24)
              .color(ThemeAwareHelper.getTestManagementThemedColor('accent_primary', this.themeState.currentTheme))
          }
          .width(COVER_WIDTH)
          .height(COVER_HEIGHT)
          .backgroundColor(ThemeAwareHelper.getTestManagementThemedColor('comp_background_tertiary', this.themeState.currentTheme))
          .borderRadius(8)
          .justifyContent(FlexAlign.Center)
        } else if (this.hasCoverImageSource() && !this.isNetworkCover()) {
          Image(this.getCoverImageSource())
            .width(COVER_WIDTH)
            .height(COVER_HEIGHT)
            .objectFit(ImageFit.Cover)
            .borderRadius(8)
            .onError(() => {
              logger.warn(TAG, `封面加载失败: ${this.getRawCoverImagePath()}`);
            })
        } else if (this.hasCoverImageSource()) {
          AvifImage({
            src: this.getCoverImageSource() as string,
            imageWidth: COVER_WIDTH,
            imageHeight: COVER_HEIGHT,
            objectFit: ImageFit.Cover,
            imageBorderRadius: 8
          })
        } else {
          // 占位符
          Column() {
            SymbolGlyph($r('sys.symbol.book_open_fill'))
              .fontSize(48)
              .fontColor([ThemeAwareHelper.getTestManagementThemedColor('text_muted', this.themeState.currentTheme)])
          }
          .width(COVER_WIDTH)
          .height(COVER_HEIGHT)
          .backgroundColor(ThemeAwareHelper.getTestManagementThemedColor('comp_background_tertiary', this.themeState.currentTheme))
          .borderRadius(8)
          .justifyContent(FlexAlign.Center)
        }

        // 内容类型标签
        Text(this.getContentTypeName())
          .fontSize(10)
          .fontColor(Color.White)
          .backgroundColor('rgba(0,0,0,0.6)')
          .padding({ left: 6, right: 6, top: 2, bottom: 2 })
          .borderRadius(4)
          .position({ x: 4, y: 4 })

        if (LabelUtils.isTranslatedContent(this.getDisplayTitleText())) {
          Text('汉化')
            .fontSize(10)
            .fontColor(Color.White)
            .backgroundColor('#E6F44336')
            .padding({ left: 4, right: 4, top: 2, bottom: 2 })
            .borderRadius({ bottomLeft: 6, topRight: 8 })
            .position({ right: 0, top: 0 })
        }
        
        // 在线漫画封面刷新按钮（右下角）
        if (this.isOnlineManga()) {
          Button() {
            if (this.isRefetchingCover) {
              LoadingProgress()
                .width(16)
                .height(16)
                .color(Color.White)
            } else {
              SymbolGlyph($r('sys.symbol.arrow_clockwise'))
                .fontSize(14)
                .fontColor([Color.White])
            }
          }
          .width(28)
          .height(28)
          .backgroundColor('rgba(0,0,0,0.5)')
          .borderRadius(14)
          .position({ x: COVER_WIDTH - 32, y: COVER_HEIGHT - 32 })
          .enabled(!this.isRefetchingCover)
          .onClick(() => this.refetchCoverImage())
        }
      }
      .id(`cover_${this.componentId}`)
      .onClick(() => this.openCoverPreview())

      // 信息区域
      Column({ space: 8 }) {
        if (this.getDisplayTitleText().length > 0) {
          Text(this.getDisplayTitleText())
            .fontSize(20)
            .fontWeight(FontWeight.Bold)
            .fontFamily(this.appFontFamily)
            .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_primary', this.themeState.currentTheme))
            .maxLines(2)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
            .width('100%')
            .onClick(() => {
              const titleText = this.getDisplayTitleText();
              this.navigateToSearch(titleText);
            })
        } else {
          Blank()
            .width('72%')
            .height(24)
            .borderRadius(12)
            .backgroundColor(ThemeAwareHelper.getTestManagementThemedColor('comp_background_tertiary', this.themeState.currentTheme))
        }

        if (this.getDisplayAuthorText().length > 0) {
          Text(this.getDisplayAuthorText())
            .fontSize(14)
            .fontFamily(this.appFontFamily)
            .fontColor(ThemeAwareHelper.getTestManagementThemedColor('accent_primary', this.themeState.currentTheme))
            .maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
            .width('100%')
            .onClick(() => {
              this.navigateToSearch(this.getDisplayAuthorText());
            })
        } else {
          Blank()
            .width('100%')
            .height(16)
        }

        Row({ space: 8 }) {
          Text(this.getReadStatusText())
            .fontSize(12)
            .fontFamily(this.appFontFamily)
            .fontColor(ThemeAwareHelper.getTestManagementThemedColor('accent_primary', this.themeState.currentTheme))
            .maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
            .layoutWeight(1)

          Text(`${this.content?.totalChapters || 0}章`)
            .fontSize(12)
            .fontFamily(this.appFontFamily)
            .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_muted', this.themeState.currentTheme))
        }
        .width('100%')

        if (this.getDisplaySourceName().length > 0) {
          Text(`来源: ${this.getDisplaySourceName()}`)
            .fontSize(12)
            .fontFamily(this.appFontFamily)
            .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_muted', this.themeState.currentTheme))
            .maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
            .width('100%')
        }

        Blank()

        // 操作按钮
        Column({ space: 8 }) {
          // 添加书架/替换原小说按钮
          if (this.isFromChangeSource && this.originalBookInfo) {
            // 换源模式：显示替换原小说按钮
            Button('替换原小说')
              .fontSize(14)
              .fontFamily(this.appFontFamily)
              .backgroundColor(ThemeAwareHelper.getTestManagementThemedColor('accent_orange', this.themeState.currentTheme))
              .fontColor(Color.White)
              .height(32)
              .width('100%')
              .onClick(() => this.openReplaceBookDialog())
          } else {
            // 正常模式：显示添加书架按钮
            Button() {
              Row({ space: 6 }) {
                SymbolGlyph($r('sys.symbol.bookshelf'))
                  .fontSize(14)
                  .fontColor([this.isInShelf
                    ? ThemeAwareHelper.getTestManagementThemedColor('accent_green', this.themeState.currentTheme)
                    : ThemeAwareHelper.getTestManagementThemedColor('text_primary', this.themeState.currentTheme)])
                Text(this.getShelfButtonLabel())
                  .fontSize(14)
                  .fontFamily(this.appFontFamily)
                  .fontColor(this.isInShelf
                    ? ThemeAwareHelper.getTestManagementThemedColor('accent_green', this.themeState.currentTheme)
                    : ThemeAwareHelper.getTestManagementThemedColor('text_primary', this.themeState.currentTheme))
                  .maxLines(1)
                  .textOverflow({ overflow: TextOverflow.Ellipsis })
              }
            }
              .backgroundColor(this.isInShelf 
                ? ThemeAwareHelper.getTestManagementThemedColor('accent_green', this.themeState.currentTheme) + '20'
                : ThemeAwareHelper.getTestManagementThemedColor('comp_background_tertiary', this.themeState.currentTheme))
              .height(32)
              .width('100%')
              .enabled(!this.isShelfActionPending)
              .onClick(() => this.showAddToShelfSelection())
          }

          // 阅读按钮
          Button() {
            Row({ space: 6 }) {
              if (this.isReadActionBusy()) {
                LoadingProgress()
                  .width(14)
                  .height(14)
                  .color(Color.White)
              } else {
                SymbolGlyph($r('sys.symbol.book_open_fill'))
                  .fontSize(14)
                  .fontColor([Color.White])
              }
              Text(this.getReadButtonLabel())
                .fontSize(14)
                .fontFamily(this.appFontFamily)
                .fontColor(Color.White)
            }
          }
            .backgroundColor(ThemeAwareHelper.getTestManagementThemedColor('accent_primary', this.themeState.currentTheme))
            .height(36)
            .width('100%')
            .id('' as string)
            .enabled(!this.isReadActionBusy())
            .onClick(() => this.continueReading())

          if (this.canShowReadAloudButton()) {
            Button() {
              Row({ space: 6 }) {
                SymbolGlyph($r('sys.symbol.speaker'))
                  .fontSize(14)
                  .fontColor([Color.White])
                Text(this.getReadAloudButtonLabel())
                  .fontSize(14)
                  .fontFamily(this.appFontFamily)
                  .fontColor(Color.White)
              }
            }
              .linearGradient({
                angle: 135,
                colors: [
                  ['#00C2FF', 0],
                  ['#4B7BFF', 0.55],
                  ['#7A5CFF', 1]
                ]
              })
              .height(34)
              .width('100%')
              .onClick(() => this.continueReadAloud())
          }
        }
        .width('100%')
      }
      .layoutWeight(1)
      .alignItems(HorizontalAlign.Start)
      .constraintSize({ minHeight: COVER_HEIGHT })
    }
    .alignItems(VerticalAlign.Top)
    .width('100%')
    .id('' as string)
    .padding(16)
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

  private getFloatingBackgroundColor(): ResourceColor {
    return SettingsGlassStyleHelper.getFloatingBackground();
  }

  private getFloatingBlurStyle(): BlurStyle {
    return SettingsGlassStyleHelper.getFloatingBlurStyle();
  }

  private getFloatingBlurOptions(): BackgroundBlurStyleOptions {
    return SettingsGlassStyleHelper.getFloatingBlurOptions();
  }

  private getFloatingRadius(): number {
    return SettingsGlassStyleHelper.getFloatingRadius();
  }

  private getFloatingBorderColor(): ResourceColor {
    return SettingsGlassStyleHelper.getFloatingBorderColor();
  }

  private getFloatingBorderWidth(): number {
    return SettingsGlassStyleHelper.getFloatingBorderWidth();
  }

  private getFloatingShadowColor(): string {
    return SettingsGlassStyleHelper.getFloatingShadowColor();
  }

  private getDialogBackgroundColor(): ResourceColor {
    return SettingsGlassStyleHelper.getSheetBackground();
  }

  private getDialogBlurStyle(): BlurStyle {
    return SettingsGlassStyleHelper.getSheetBlurStyle();
  }

  private getDialogBlurOptions(): BackgroundBlurStyleOptions {
    return SettingsGlassStyleHelper.getSheetBlurOptions();
  }

  private getDialogRadius(): number {
    return SettingsGlassStyleHelper.getSheetRadius();
  }

  private getDialogBorderColor(): ResourceColor {
    return SettingsGlassStyleHelper.getSheetBorderColor();
  }

  private getDialogBorderWidth(): number {
    return SettingsGlassStyleHelper.getSheetBorderWidth();
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

  /**
   * 简介文本选中后的自定义工具栏（长按选中触发）
   * 具备主题背景、阴影、边框和按下反馈效果
   */
  @Builder
  buildDescriptionSelectionMenu() {
    Row({ space: 0 }) {
      Button('复制', { type: ButtonType.Normal })
        .fontSize(14)
        .fontFamily(this.appFontFamily)
        .fontWeight(FontWeight.Medium)
        .fontColor(ThemeAwareHelper.getTestManagementThemedColor('accent_primary', this.themeState.currentTheme))
        .height(40)
        .padding({ left: 20, right: 14 })
        .backgroundColor(Color.Transparent)
        .borderRadius(0)
        .onClick(() => {
          if (this.descriptionSelectedText) {
            this.copyToClipboard(this.descriptionSelectedText);
          }
          this.descriptionSelectedText = '';
        })

      Column()
        .width(0.5)
        .height(18)
        .backgroundColor(ThemeAwareHelper.getTestManagementThemedColor('panel_border', this.themeState.currentTheme))

      Button('搜索', { type: ButtonType.Normal })
        .fontSize(14)
        .fontFamily(this.appFontFamily)
        .fontWeight(FontWeight.Medium)
        .fontColor(ThemeAwareHelper.getTestManagementThemedColor('accent_primary', this.themeState.currentTheme))
        .height(40)
        .padding({ left: 14, right: 20 })
        .backgroundColor(Color.Transparent)
        .borderRadius(0)
        .onClick(() => {
          if (this.descriptionSelectedText) {
            this.navigateToSearch(this.descriptionSelectedText);
          }
          this.descriptionSelectedText = '';
        })
    }
    .height(40)
    .alignItems(VerticalAlign.Center)
    .backgroundColor(this.getFloatingBackgroundColor())
    .backgroundBlurStyle(this.getFloatingBlurStyle(), this.getFloatingBlurOptions())
    .borderRadius(this.getFloatingRadius())
    .border({
      width: this.getFloatingBorderWidth(),
      color: this.getFloatingBorderColor()
    })
    .shadow({ radius: this.getFloatingRadius() + 2, color: this.getFloatingShadowColor(), offsetX: 0, offsetY: 4 })
    .clip(true)
  }

  private getTagChipItems(): TagChipItem[] {
    const result: TagChipItem[] = [];
    if (!this.content) {
      return result;
    }

    const genres = this.content.genres ? this.content.genres : [];
    for (let index = 0; index < genres.length; index++) {
      const rawLabel = genres[index];
      if (this.normalizeTagLabel(rawLabel).length === 0) {
        continue;
      }
      result.push({
        id: `genre_${index}_${this.normalizeTagLabel(rawLabel)}`,
        rawLabel: rawLabel,
        isGenre: true
      });
    }

    const tags = this.content.tags ? this.content.tags : [];
    for (let index = 0; index < tags.length; index++) {
      const rawLabel = tags[index];
      if (this.normalizeTagLabel(rawLabel).length === 0) {
        continue;
      }
      result.push({
        id: `tag_${index}_${this.normalizeTagLabel(rawLabel)}`,
        rawLabel: rawLabel,
        isGenre: false
      });
    }
    return result;
  }

  private shouldShowOnlineEBookVerificationInfo(): boolean {
    return this.content?.contentType === UnifiedContentType.EBOOK && this.onlineEBookVerificationInfo !== null;
  }

  private getOnlineEBookVerificationCardTitle(): string {
    if (!this.onlineEBookVerificationInfo) {
      return '站点状态';
    }
    const status = this.normalizeTrackingText(this.onlineEBookVerificationInfo.status);
    if (status === 'cooldown') {
      return '站点冷却中';
    }
    if (status === 'verifying') {
      return '站点验证中';
    }
    return '站点状态';
  }

  private formatOnlineEBookVerificationUpdatedAt(timestamp: number | undefined): string {
    const safeTimestamp: number = Number(timestamp || 0);
    if (!(safeTimestamp > 0)) {
      return '';
    }
    const date = new Date(safeTimestamp);
    const year = date.getFullYear();
    const month = `${date.getMonth() + 1}`.padStart(2, '0');
    const day = `${date.getDate()}`.padStart(2, '0');
    const hour = `${date.getHours()}`.padStart(2, '0');
    const minute = `${date.getMinutes()}`.padStart(2, '0');
    const second = `${date.getSeconds()}`.padStart(2, '0');
    return `${year}-${month}-${day} ${hour}:${minute}:${second}`;
  }

  @Builder
  private buildOnlineEBookVerificationInfoCard() {
    Column({ space: 8 }) {
      Row({ space: 8 }) {
        Text(this.getOnlineEBookVerificationCardTitle())
          .fontSize(14)
          .fontWeight(FontWeight.Bold)
          .fontFamily(this.appFontFamily)
          .fontColor(ThemeAwareHelper.getTestManagementThemedColor('accent_orange', this.themeState.currentTheme))
        if (this.onlineEBookVerificationInfo && this.onlineEBookVerificationInfo.attempt && this.onlineEBookVerificationInfo.attempt > 0) {
          Text(`第 ${this.onlineEBookVerificationInfo.attempt} 次`)
            .fontSize(11)
            .fontFamily(this.appFontFamily)
            .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_muted', this.themeState.currentTheme))
        }
      }
      .width('100%')

      Text(this.onlineEBookVerificationInfo ? this.onlineEBookVerificationInfo.message : '')
        .fontSize(13)
        .lineHeight(20)
        .fontFamily(this.appFontFamily)
        .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_secondary', this.themeState.currentTheme))

      if (this.onlineEBookVerificationInfo && this.onlineEBookVerificationInfo.cooldownText && this.onlineEBookVerificationInfo.cooldownText.length > 0) {
        Text(`冷却时间: ${this.onlineEBookVerificationInfo.cooldownText}`)
          .fontSize(12)
          .fontFamily(this.appFontFamily)
          .fontColor(ThemeAwareHelper.getTestManagementThemedColor('accent_primary', this.themeState.currentTheme))
      }

      if (this.onlineEBookVerificationInfo && this.onlineEBookVerificationInfo.pageTitle && this.onlineEBookVerificationInfo.pageTitle.length > 0) {
        Text(`页面标题: ${this.onlineEBookVerificationInfo.pageTitle}`)
          .fontSize(11)
          .fontFamily(this.appFontFamily)
          .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_muted', this.themeState.currentTheme))
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
      }

      if (this.onlineEBookVerificationInfo && this.onlineEBookVerificationInfo.pageUrl && this.onlineEBookVerificationInfo.pageUrl.length > 0) {
        Text(`页面地址: ${this.onlineEBookVerificationInfo.pageUrl}`)
          .fontSize(11)
          .fontFamily(this.appFontFamily)
          .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_muted', this.themeState.currentTheme))
          .maxLines(2)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
      }

      if (this.onlineEBookVerificationInfo && this.formatOnlineEBookVerificationUpdatedAt(this.onlineEBookVerificationInfo.lastUpdatedTime).length > 0) {
        Text(`记录时间: ${this.formatOnlineEBookVerificationUpdatedAt(this.onlineEBookVerificationInfo.lastUpdatedTime)}`)
          .fontSize(11)
          .fontFamily(this.appFontFamily)
          .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_muted', this.themeState.currentTheme))
      }
    }
    .width('100%')
    .padding(12)
    .alignItems(HorizontalAlign.Start)
    .backgroundColor(ThemeAwareHelper.getTestManagementThemedColor('comp_background_tertiary', this.themeState.currentTheme))
    .borderRadius(16)
  }

  private normalizeTagLabel(rawLabel: string): string {
    return this.stripHtmlTags(rawLabel).trim();
  }

  private estimateTagLabelUnits(label: string): number {
    let units = 0;
    for (let index = 0; index < label.length; index++) {
      const code = label.charCodeAt(index);
      const isWideChar = (code >= 0x4E00 && code <= 0x9FFF)
        || (code >= 0x3400 && code <= 0x4DBF)
        || (code >= 0x3040 && code <= 0x30FF)
        || (code >= 0xAC00 && code <= 0xD7AF)
        || (code >= 0xFF01 && code <= 0xFF60)
        || (code >= 0xFFE0 && code <= 0xFFEE);
      units += isWideChar ? 2 : 1;
    }
    return units;
  }

  private getTagChipExpandLimit(compact: boolean): number {
    return compact ? 22 : 24;
  }

  private shouldShowTagChipExpandToggle(label: string, compact: boolean): boolean {
    return this.estimateTagLabelUnits(label) > this.getTagChipExpandLimit(compact);
  }

  private isTagChipExpanded(tagChipId: string): boolean {
    return this.expandedTagChipIds.indexOf(tagChipId) >= 0;
  }

  private toggleTagChipExpansion(tagChipId: string): void {
    const expanded = this.isTagChipExpanded(tagChipId);
    this.getUIContext().animateTo({ duration: 220, curve: Curve.EaseInOut }, () => {
      const nextIds: string[] = [];
      for (let index = 0; index < this.expandedTagChipIds.length; index++) {
        const currentId = this.expandedTagChipIds[index];
        if (currentId !== tagChipId) {
          nextIds.push(currentId);
        }
      }
      if (!expanded) {
        nextIds.push(tagChipId);
      }
      this.expandedTagChipIds = nextIds;
    });
  }

  private toggleDescriptionExpanded(): void {
    this.getUIContext().animateTo({ duration: 240, curve: Curve.EaseInOut }, () => {
      this.showFullDescription = !this.showFullDescription;
    });
  }

  private getTagChipLabel(item: TagChipItem): string {
    return this.normalizeTagLabel(item.rawLabel);
  }

  private canExpandTagChip(item: TagChipItem, compact: boolean): boolean {
    return this.shouldShowTagChipExpandToggle(this.getTagChipLabel(item), compact);
  }

  private getTagChipTextMaxWidth(item: TagChipItem, compact: boolean): number {
    if (this.canExpandTagChip(item, compact)) {
      return compact ? 96 : 136;
    }
    return compact ? 164 : 200;
  }

  private getTagChipMaxWidth(compact: boolean): number {
    return compact ? 180 : 220;
  }

  private getTagChipPrimaryColor(): ResourceColor {
    return ThemeAwareHelper.getTestManagementThemedColor('accent_primary', this.themeState.currentTheme);
  }

  private getTagChipTextColor(item: TagChipItem): ResourceColor {
    if (item.isGenre) {
      return this.getTagChipPrimaryColor();
    }
    return ThemeAwareHelper.getTestManagementThemedColor('text_secondary', this.themeState.currentTheme);
  }

  private getTagChipBackgroundColor(item: TagChipItem, compact: boolean): ResourceColor {
    if (compact) {
      if (item.isGenre) {
        return ThemeAwareHelper.getTestManagementThemedColor('accent_primary_dimmed', this.themeState.currentTheme);
      }
      return ThemeAwareHelper.getTestManagementThemedColor('panel_border', this.themeState.currentTheme);
    }
    if (item.isGenre) {
      return ThemeAwareHelper.getTestManagementThemedColor('accent_primary', this.themeState.currentTheme) + '16';
    }
    return ThemeAwareHelper.getTestManagementThemedColor('comp_background_tertiary', this.themeState.currentTheme);
  }

  private getTagChipBorderColor(item: TagChipItem): ResourceColor {
    if (item.isGenre) {
      return ThemeAwareHelper.getTestManagementThemedColor('accent_primary', this.themeState.currentTheme) + '28';
    }
    return ThemeAwareHelper.getTestManagementThemedColor('divider', this.themeState.currentTheme);
  }

  @Builder
  private buildTagChip(item: TagChipItem, compact: boolean) {
    Row({ space: compact ? 4 : 6 }) {
      Text(this.getTagChipLabel(item))
        .fontSize(compact ? 11 : 12)
        .fontFamily(this.appFontFamily)
        .fontColor(this.getTagChipTextColor(item))
        .maxLines(this.canExpandTagChip(item, compact) && this.isTagChipExpanded(item.id) ? 4 : 1)
        .textOverflow({ overflow: TextOverflow.Ellipsis })
        .constraintSize({ maxWidth: this.getTagChipTextMaxWidth(item, compact) })
        .onClick(() => {
          this.navigateToSearch(this.getTagChipLabel(item));
        })

      if (this.canExpandTagChip(item, compact)) {
        Row({ space: 2 }) {
          Text(this.isTagChipExpanded(item.id) ? '收起' : '展开')
            .fontSize(compact ? 9 : 10)
            .fontFamily(this.appFontFamily)
            .fontColor(this.getTagChipPrimaryColor())
          SymbolGlyph($r('sys.symbol.chevron_down'))
            .fontSize(compact ? 9 : 10)
            .fontColor([this.getTagChipPrimaryColor()])
            .rotate({ angle: this.isTagChipExpanded(item.id) ? 180 : 0 })
            .animation({ duration: 220, curve: Curve.EaseInOut })
        }
        .padding({ left: 4, right: 4, top: 2, bottom: 2 })
        .backgroundColor(ThemeAwareHelper.getTestManagementThemedColor('comp_background_secondary', this.themeState.currentTheme))
        .borderRadius(compact ? 9 : 10)
        .onClick(() => {
          this.toggleTagChipExpansion(item.id);
        })
      }
    }
    .constraintSize({ maxWidth: this.getTagChipMaxWidth(compact) })
    .padding(compact
      ? { left: 8, right: 8, top: 4, bottom: 4 }
      : { left: 12, right: 12, top: 6, bottom: 6 })
    .backgroundColor(this.getTagChipBackgroundColor(item, compact))
    .borderRadius(compact ? 12 : 14)
    .border(compact
      ? { width: 0, color: Color.Transparent }
      : { width: 1, color: this.getTagChipBorderColor(item) })
    .margin(compact ? { right: 6, bottom: 6 } : { right: 8, bottom: 8 })
    .transition(TransitionEffect.OPACITY.combine(TransitionEffect.scale({ x: 0.92, y: 0.92 })))
    .animation({ duration: 220, curve: Curve.EaseInOut })
  }

  @Builder
  buildDescription() {
    Stack({ alignContent: Alignment.TopStart }) {
      this.buildGlassSectionChrome()
      Column({ space: 14 }) {
        if (this.shouldShowOnlineEBookVerificationInfo()) {
          this.buildOnlineEBookVerificationInfoCard()
        }

        if (this.content && ((this.content.genres && this.content.genres.length > 0) || (this.content.tags && this.content.tags.length > 0))) {
          Column({ space: 10 }) {
            Row({ space: 8 }) {
              SymbolGlyph($r('sys.symbol.bookmark_fill'))
                .fontSize(16)
                .fontColor([ThemeAwareHelper.getTestManagementThemedColor('accent_primary', this.themeState.currentTheme)])
              Text('标签')
                .fontSize(16)
                .fontWeight(FontWeight.Bold)
                .fontFamily(this.appFontFamily)
                .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_primary', this.themeState.currentTheme))
            }
            .width('100%')

            Flex({ wrap: FlexWrap.Wrap, alignItems: ItemAlign.Center }) {
              ForEach(this.getTagChipItems(), (item: TagChipItem) => {
                this.buildTagChip(item, false);
              }, (item: TagChipItem) => `desc_${item.id}`)
            }
            .animation({ duration: 240, curve: Curve.EaseInOut })
          }
          .width('100%')
          .padding(12)
          .alignItems(HorizontalAlign.Start)
          .backgroundColor(ThemeAwareHelper.getTestManagementThemedColor('comp_background_tertiary', this.themeState.currentTheme))
          .borderRadius(16)
        }

        Column({ space: 10 }) {
          Row() {
            Text('简介')
              .fontSize(16)
              .fontWeight(FontWeight.Bold)
              .fontFamily(this.appFontFamily)
              .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_primary', this.themeState.currentTheme))
            Blank()
            if (this.content?.description && this.content.description.length > 100) {
              Button(this.showFullDescription ? '收起' : '展开')
                .fontSize(12)
                .fontFamily(this.appFontFamily)
                .height(28)
                .padding({ left: 12, right: 12 })
                .backgroundColor(ThemeAwareHelper.getTestManagementThemedColor('comp_background_tertiary', this.themeState.currentTheme))
                .fontColor(ThemeAwareHelper.getTestManagementThemedColor('accent_primary', this.themeState.currentTheme))
                .borderRadius(14)
                .border({ width: 1, color: ThemeAwareHelper.getTestManagementThemedColor('divider', this.themeState.currentTheme) })
                .onClick(() => {
                  this.toggleDescriptionExpanded();
                })
            }
          }
          .width('100%')

          Text(this.stripHtmlTags(this.content?.description || (this.isOnlineEBookRecoveryInProgress ? this.onlineEBookRecoveryStatusText : (this.isLoading ? '正在加载简介...' : '暂无简介'))))
            .fontSize(14)
            .lineHeight(22)
            .fontFamily(this.appFontFamily)
            .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_secondary', this.themeState.currentTheme))
            .maxLines(this.showFullDescription ? undefined : 4)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
            .animation({ duration: 240, curve: Curve.EaseInOut })
            .copyOption(CopyOptions.InApp)
            .onTextSelectionChange((start: number, end: number) => {
              const fullText = this.stripHtmlTags(this.content?.description || '');
              if (start >= 0 && end > start) {
                this.descriptionSelectedText = fullText.substring(start, end);
              }
            })
            .bindSelectionMenu(TextSpanType.TEXT, this.buildDescriptionSelectionMenu, TextResponseType.LONG_PRESS, {
              onDisappear: () => { this.descriptionSelectedText = ''; }
            })
        }
        .width('100%')
        .padding(12)
        .alignItems(HorizontalAlign.Start)
        .backgroundColor(ThemeAwareHelper.getTestManagementThemedColor('comp_background_secondary', this.themeState.currentTheme))
        .borderRadius(16)
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
    .id('' as string)
  }

  @Builder
  private buildActionBarLoadingPlaceholder() {
    Stack({ alignContent: Alignment.TopStart }) {
      this.buildGlassSectionChrome()
      Flex({
        wrap: FlexWrap.Wrap,
        justifyContent: FlexAlign.Start,
        alignItems: ItemAlign.Start,
        space: { main: LengthMetrics.vp(8), cross: LengthMetrics.vp(8) }
      }) {
        Column()
          .width(92)
          .height(36)
          .backgroundColor(ThemeAwareHelper.getTestManagementThemedColor('comp_background_tertiary', this.themeState.currentTheme))
          .borderRadius(18)

        Column()
          .width(118)
          .height(36)
          .backgroundColor(ThemeAwareHelper.getTestManagementThemedColor('comp_background_tertiary', this.themeState.currentTheme))
          .borderRadius(18)

        Column()
          .width(78)
          .height(36)
          .backgroundColor(ThemeAwareHelper.getTestManagementThemedColor('comp_background_tertiary', this.themeState.currentTheme))
          .borderRadius(18)
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

  @Builder
  buildActionBar() {
    if (!this.content) {
      this.buildActionBarLoadingPlaceholder()
    } else {
      Stack({ alignContent: Alignment.TopStart }) {
      this.buildGlassSectionChrome()
      Flex({
        wrap: FlexWrap.Wrap,
        justifyContent: FlexAlign.Start,
        alignItems: ItemAlign.Start,
        space: { main: LengthMetrics.vp(8), cross: LengthMetrics.vp(8) }
      }) {
        if (this.content?.contentType === UnifiedContentType.MANGA) {
          Button() {
            Row({ space: 6 }) {
              SymbolGlyph($r('sys.symbol.gearshape'))
                .fontSize(16)
                .fontColor([ThemeAwareHelper.getTestManagementThemedColor('text_primary', this.themeState.currentTheme)])
              Text('漫画设置')
                .fontSize(14)
                .fontFamily(this.appFontFamily)
                .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_primary', this.themeState.currentTheme))
            }
          }
          .height(36)
          .padding({ left: 16, right: 16 })
          .backgroundColor(ThemeAwareHelper.getTestManagementThemedColor('comp_background_tertiary', this.themeState.currentTheme))
          .borderRadius(18)
          .onClick(() => this.openMangaSettings())

          if (this.isOnlineManga()) {
            Button() {
              Row({ space: 6 }) {
                SymbolGlyph($r('sys.symbol.arrow_clockwise'))
                  .fontSize(16)
                  .fontColor([this.isRefetchingManga
                    ? ThemeAwareHelper.getTestManagementThemedColor('text_muted', this.themeState.currentTheme)
                    : ThemeAwareHelper.getTestManagementThemedColor('accent_primary', this.themeState.currentTheme)])
                Text(this.isRefetchingManga ? '获取中...' : '重新获取')
                  .fontSize(14)
                  .fontFamily(this.appFontFamily)
                  .fontColor(this.isRefetchingManga
                    ? ThemeAwareHelper.getTestManagementThemedColor('text_muted', this.themeState.currentTheme)
                    : ThemeAwareHelper.getTestManagementThemedColor('accent_primary', this.themeState.currentTheme))
              }
            }
            .height(36)
            .padding({ left: 16, right: 16 })
            .backgroundColor(ThemeAwareHelper.getTestManagementThemedColor('comp_background_tertiary', this.themeState.currentTheme))
            .borderRadius(18)
            .enabled(!this.isRefetchingManga)
            .onClick(() => {
              void this.refetchOnlineMangaInfo();
            })

            Button() {
              Row({ space: 6 }) {
                SymbolGlyph($r('sys.symbol.globe_and_keyboard'))
                  .fontSize(16)
                  .fontColor([ThemeAwareHelper.getTestManagementThemedColor('accent_blue', this.themeState.currentTheme)])
                Text('浏览器')
                  .fontSize(14)
                  .fontFamily(this.appFontFamily)
                  .fontColor(ThemeAwareHelper.getTestManagementThemedColor('accent_blue', this.themeState.currentTheme))
              }
            }
            .height(36)
            .padding({ left: 16, right: 16 })
            .backgroundColor(ThemeAwareHelper.getTestManagementThemedColor('comp_background_tertiary', this.themeState.currentTheme))
            .borderRadius(18)
            .onClick(() => {
              void this.openInBrowser();
            })
          }
        } else if (this.content?.contentType === UnifiedContentType.EBOOK) {
          Button() {
            Row({ space: 6 }) {
              SymbolGlyph($r('sys.symbol.gearshape'))
                .fontSize(16)
                .fontColor([ThemeAwareHelper.getTestManagementThemedColor('text_primary', this.themeState.currentTheme)])
              Text('电子书设置')
                .fontSize(14)
                .fontFamily(this.appFontFamily)
                .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_primary', this.themeState.currentTheme))
            }
          }
          .height(36)
          .padding({ left: 16, right: 16 })
          .backgroundColor(ThemeAwareHelper.getTestManagementThemedColor('comp_background_tertiary', this.themeState.currentTheme))
          .borderRadius(18)
          .onClick(() => {
            if (this.isLocalImportedEBookContent()) {
              this.novelSettingsLoadSignal++;
            } else {
              this.openEBookSettings();
            }
          })

          Button() {
            Row({ space: 6 }) {
              SymbolGlyph($r('sys.symbol.picture'))
                .fontSize(16)
                .fontColor([this.isGeneratingCover
                  ? ThemeAwareHelper.getTestManagementThemedColor('text_muted', this.themeState.currentTheme)
                  : ThemeAwareHelper.getTestManagementThemedColor('accent_primary', this.themeState.currentTheme)])
              Text(this.isGeneratingCover ? '生成中...' : '生成封面')
                .fontSize(14)
                .fontFamily(this.appFontFamily)
                .fontColor(this.isGeneratingCover
                  ? ThemeAwareHelper.getTestManagementThemedColor('text_muted', this.themeState.currentTheme)
                  : ThemeAwareHelper.getTestManagementThemedColor('accent_primary', this.themeState.currentTheme))
            }
          }
          .height(36)
          .padding({ left: 16, right: 16 })
          .backgroundColor(ThemeAwareHelper.getTestManagementThemedColor('comp_background_tertiary', this.themeState.currentTheme))
          .borderRadius(18)
          .enabled(!this.isGeneratingCover)
          .onClick(() => this.showGenerateCoverPrompt())
        } else if (this.content?.contentType === UnifiedContentType.NOVEL) {
          Button() {
            Row({ space: 6 }) {
              SymbolGlyph($r('sys.symbol.gearshape'))
                .fontSize(16)
                .fontColor([ThemeAwareHelper.getTestManagementThemedColor('text_primary', this.themeState.currentTheme)])
              Text('小说设置')
                .fontSize(14)
                .fontFamily(this.appFontFamily)
                .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_primary', this.themeState.currentTheme))
            }
          }
          .height(36)
          .padding({ left: 16, right: 16 })
          .backgroundColor(ThemeAwareHelper.getTestManagementThemedColor('comp_background_tertiary', this.themeState.currentTheme))
          .borderRadius(18)
          .onClick(() => {
            this.novelSettingsLoadSignal++;
          })

          Button() {
            Row({ space: 6 }) {
              SymbolGlyph($r('sys.symbol.picture'))
                .fontSize(16)
                .fontColor([this.isGeneratingCover
                  ? ThemeAwareHelper.getTestManagementThemedColor('text_muted', this.themeState.currentTheme)
                  : ThemeAwareHelper.getTestManagementThemedColor('accent_primary', this.themeState.currentTheme)])
              Text(this.isGeneratingCover ? '生成中...' : '生成封面')
                .fontSize(14)
                .fontFamily(this.appFontFamily)
                .fontColor(this.isGeneratingCover
                  ? ThemeAwareHelper.getTestManagementThemedColor('text_muted', this.themeState.currentTheme)
                  : ThemeAwareHelper.getTestManagementThemedColor('accent_primary', this.themeState.currentTheme))
            }
          }
          .height(36)
          .padding({ left: 16, right: 16 })
          .backgroundColor(ThemeAwareHelper.getTestManagementThemedColor('comp_background_tertiary', this.themeState.currentTheme))
          .borderRadius(18)
          .enabled(!this.isGeneratingCover)
          .onClick(() => this.showGenerateCoverPrompt())

          Button() {
            Row({ space: 6 }) {
              SymbolGlyph($r('sys.symbol.arrow_clockwise'))
                .fontSize(16)
                .fontColor([ThemeAwareHelper.getTestManagementThemedColor('accent_green', this.themeState.currentTheme)])
              Text('换源')
                .fontSize(14)
                .fontFamily(this.appFontFamily)
                .fontColor(ThemeAwareHelper.getTestManagementThemedColor('accent_green', this.themeState.currentTheme))
            }
          }
          .height(36)
          .padding({ left: 16, right: 16 })
          .backgroundColor(ThemeAwareHelper.getTestManagementThemedColor('comp_background_tertiary', this.themeState.currentTheme))
          .borderRadius(18)
          .onClick(() => this.changeSourceDialogLoadSignal++)
        }

        if (this.isOnlineContent()) {
          Button() {
            if (this.isDownloading) {
              Row({ space: 6 }) {
                LoadingProgress()
                  .width(16)
                  .height(16)
                  .color(ThemeAwareHelper.getTestManagementThemedColor('accent_blue', this.themeState.currentTheme))
                Text('缓存中...')
                  .fontSize(14)
                  .fontFamily(this.appFontFamily)
                  .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_muted', this.themeState.currentTheme))
              }
            } else {
              Row({ space: 6 }) {
                SymbolGlyph($r('sys.symbol.arrow_down_circle'))
                  .fontSize(16)
                  .fontColor([ThemeAwareHelper.getTestManagementThemedColor('accent_blue', this.themeState.currentTheme)])
                Text(this.getCacheActionButtonLabel())
                  .fontSize(14)
                  .fontFamily(this.appFontFamily)
                  .fontColor(ThemeAwareHelper.getTestManagementThemedColor('accent_blue', this.themeState.currentTheme))
              }
            }
          }
          .height(36)
          .padding({ left: 16, right: 16 })
          .backgroundColor(ThemeAwareHelper.getTestManagementThemedColor('comp_background_tertiary', this.themeState.currentTheme))
          .borderRadius(18)
          .enabled(!this.isDownloading)
          .onClick(() => this.openCacheDialogFromDetail('action_bar'))
        }

        // 分享按钮
        Button() {
          Row({ space: 6 }) {
            SymbolGlyph($r('sys.symbol.share'))
              .fontSize(16)
              .fontColor([ThemeAwareHelper.getTestManagementThemedColor('accent_blue', this.themeState.currentTheme)])
            Text('分享')
              .fontSize(14)
              .fontFamily(this.appFontFamily)
              .fontColor(ThemeAwareHelper.getTestManagementThemedColor('accent_blue', this.themeState.currentTheme))
          }
        }
        .height(36)
        .padding({ left: 16, right: 16 })
        .backgroundColor(ThemeAwareHelper.getTestManagementThemedColor('comp_background_tertiary', this.themeState.currentTheme))
        .borderRadius(18)
        .onClick(() => this.openShareDialogFromDetail())

        Button() {
          Row({ space: 6 }) {
            SymbolGlyph($r('sys.symbol.trash'))
              .fontSize(16)
              .fontColor([this.isDeletingContent
                ? ThemeAwareHelper.getTestManagementThemedColor('text_muted', this.themeState.currentTheme)
                : ThemeAwareHelper.getTestManagementThemedColor('button_danger', this.themeState.currentTheme)])
            Text(this.isDeletingContent ? '删除中...' : '删除')
              .fontSize(14)
              .fontFamily(this.appFontFamily)
              .fontColor(this.isDeletingContent
                ? ThemeAwareHelper.getTestManagementThemedColor('text_muted', this.themeState.currentTheme)
                : ThemeAwareHelper.getTestManagementThemedColor('button_danger', this.themeState.currentTheme))
          }
        }
        .height(36)
        .padding({ left: 16, right: 16 })
        .backgroundColor(ThemeAwareHelper.getTestManagementThemedColor('comp_background_tertiary', this.themeState.currentTheme))
        .borderRadius(18)
        .borderWidth(1)
        .borderColor(ThemeAwareHelper.getTestManagementThemedColor('button_danger', this.themeState.currentTheme))
        .enabled(!this.isDeletingContent)
        .onClick(() => {
          void this.showDeleteContentConfirm();
        })

        Button() {
          Row({ space: 6 }) {
            SymbolGlyph($r('sys.symbol.exclamationmark_triangle'))
              .fontSize(16)
              .fontColor(['#FF9800'])
            Text('NSFW')
              .fontSize(14)
              .fontWeight(FontWeight.Bold)
              .fontFamily(this.appFontFamily)
              .fontColor('#FF9800')
          }
        }
        .height(36)
        .padding({ left: 16, right: 16 })
        .backgroundColor(this.content?.isNSFW ? '#1A1A1A' : Color.Transparent)
        .borderRadius(18)
        .borderWidth(this.content?.isNSFW ? 0 : 1)
        .borderColor('#FF9800')
        .onClick(() => {
          void this.toggleNSFW();
        })
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
    .id('' as string)
    }
  }

  private async toggleNSFW(): Promise<void> {
    if (!this.content) {
      return;
    }

    const newNSFW = !(this.content.isNSFW || false);
    const targetContentId = this.resolveNsfwTargetContentId();
    logger.info(TAG, `切换NSFW标记: ${targetContentId}, ${this.content.isNSFW} -> ${newNSFW}`);

    try {
      const success = await this.dataManager.updateContentNSFW(targetContentId, newNSFW);
      if (success) {
        this.content.isNSFW = newNSFW;
        this.getUIContext().getPromptAction().showToast({
          message: newNSFW ? '已标记为NSFW' : '已取消NSFW标记',
          duration: 1500
        });
        logger.info(TAG, `NSFW标记更新成功: ${targetContentId}, isNSFW=${newNSFW}`);
      } else {
        this.getUIContext().getPromptAction().showToast({
          message: 'NSFW标记更新失败',
          duration: 1500
        });
        logger.error(TAG, `NSFW标记更新失败: ${targetContentId}`);
      }
    } catch (error) {
      logger.error(TAG, `切换NSFW标记异常: ${String(error)}`);
      this.getUIContext().getPromptAction().showToast({
        message: '操作失败，请重试',
        duration: 1500
      });
    }
  }

  private resolveNsfwTargetContentId(): string {
    if (!this.content) {
      return '';
    }

    if (this.content.contentType === UnifiedContentType.NOVEL) {
      const originalNovel = this.content.originalData as LegadoBook | NovelBook | undefined;
      return originalNovel?.id || this.content.id;
    }

    if (this.content.contentType === UnifiedContentType.EBOOK) {
      const originalEbook = this.content.originalData as EBook | undefined;
      return originalEbook?.id || this.content.id;
    }

    return this.content.id;
  }

  @Builder
  buildCacheStatusCard() {
    if (this.showCacheStatusCard && this.cacheStats) {
      Stack({ alignContent: Alignment.TopStart }) {
        this.buildGlassSectionChrome()
        Column({ space: 12 }) {
          Row() {
            Row({ space: 6 }) {
              SymbolGlyph($r('sys.symbol.arrow_down_circle'))
                .fontSize(16)
                .fontColor([ThemeAwareHelper.getTestManagementThemedColor('accent_green', this.themeState.currentTheme)])
              Text(this.cacheStats.contentType === CacheContentType.MANGA ? '漫画缓存' : this.getNovelCacheSectionTitle())
                .fontSize(14)
                .fontWeight(FontWeight.Medium)
                .fontFamily(this.appFontFamily)
                .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_primary', this.themeState.currentTheme))
            }

            Blank()

            if (this.cacheStats.cacheSize > 0) {
              Button() {
                Row({ space: 4 }) {
                  SymbolGlyph($r('sys.symbol.trash'))
                    .fontSize(12)
                    .fontColor([Color.White])
                  Text('清理')
                    .fontSize(12)
                    .fontFamily(this.appFontFamily)
                    .fontColor(Color.White)
                }
              }
              .height(28)
              .padding({ left: 12, right: 12 })
              .backgroundColor('#FF5252')
              .borderRadius(14)
              .onClick(() => this.showClearCacheConfirm())
            }
          }
          .width('100%')

          Row({ space: 16 }) {
            Column({ space: 4 }) {
              Text(`${this.cacheStats.cachedChapterCount}/${this.cacheStats.totalChapterCount}`)
                .fontSize(20)
                .fontWeight(FontWeight.Bold)
                .fontFamily(this.appFontFamily)
                .fontColor(ThemeAwareHelper.getTestManagementThemedColor('accent_primary', this.themeState.currentTheme))
              Text(this.cacheStats.contentType === CacheContentType.MANGA ? '已缓存章节' : this.getNovelCachedCountLabel())
                .fontSize(11)
                .fontFamily(this.appFontFamily)
                .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_muted', this.themeState.currentTheme))
            }
            .layoutWeight(1)
            .alignItems(HorizontalAlign.Center)

            Divider()
              .vertical(true)
              .height(36)
              .color(ThemeAwareHelper.getTestManagementThemedColor('divider', this.themeState.currentTheme))

            Column({ space: 4 }) {
              if (this.cacheStats.contentType === CacheContentType.MANGA) {
                Text(`${this.cacheStats.cachedPageCount}/${this.cacheStats.totalPageCount}`)
                  .fontSize(20)
                  .fontWeight(FontWeight.Bold)
                  .fontFamily(this.appFontFamily)
                  .fontColor(ThemeAwareHelper.getTestManagementThemedColor('accent_blue', this.themeState.currentTheme))
                Text('已缓存页面')
                  .fontSize(11)
                  .fontFamily(this.appFontFamily)
                  .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_muted', this.themeState.currentTheme))
              } else {
                Text(`${this.cacheStatusService.calculateProgress(this.cacheStats)}%`)
                  .fontSize(20)
                  .fontWeight(FontWeight.Bold)
                  .fontFamily(this.appFontFamily)
                  .fontColor(ThemeAwareHelper.getTestManagementThemedColor('accent_blue', this.themeState.currentTheme))
                Text('缓存进度')
                  .fontSize(11)
                  .fontFamily(this.appFontFamily)
                  .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_muted', this.themeState.currentTheme))
              }
            }
            .layoutWeight(1)
            .alignItems(HorizontalAlign.Center)

            Divider()
              .vertical(true)
              .height(36)
              .color(ThemeAwareHelper.getTestManagementThemedColor('divider', this.themeState.currentTheme))

            Column({ space: 4 }) {
              Text(this.cacheStatusService.formatSize(this.cacheStats.cacheSize))
                .fontSize(20)
                .fontWeight(FontWeight.Bold)
                .fontFamily(this.appFontFamily)
                .fontColor(ThemeAwareHelper.getTestManagementThemedColor('accent_orange', this.themeState.currentTheme))
              Text('缓存大小')
                .fontSize(11)
                .fontFamily(this.appFontFamily)
                .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_muted', this.themeState.currentTheme))
            }
            .layoutWeight(1)
            .alignItems(HorizontalAlign.Center)
          }
          .width('100%')

          Column({ space: 4 }) {
            Progress({ value: this.cacheStatusService.calculateProgress(this.cacheStats), total: 100, type: ProgressType.Linear })
              .width('100%')
              .height(4)
              .color(ThemeAwareHelper.getTestManagementThemedColor('accent_primary', this.themeState.currentTheme))
              .backgroundColor(ThemeAwareHelper.getTestManagementThemedColor('comp_background_tertiary', this.themeState.currentTheme))
          }
          .width('100%')

          if (this.content && this.isOnlineContent()) {
            Row({ space: 10 }) {
              Button() {
                Row({ space: 6 }) {
                  SymbolGlyph($r('sys.symbol.arrow_down_circle'))
                    .fontSize(13)
                    .fontColor([Color.White])
                  Text(this.getCacheActionButtonLabel())
                    .fontSize(12)
                    .fontFamily(this.appFontFamily)
                    .fontColor(Color.White)
                }
              }
              .height(34)
              .padding({ left: 14, right: 14 })
              .backgroundColor(ThemeAwareHelper.getTestManagementThemedColor('accent_primary', this.themeState.currentTheme))
              .borderRadius(17)
              .enabled(!this.isDownloading)
              .onClick(() => this.openCacheDialogFromDetail('cache_status_card'))

              // 部分缓存章节存在时，显示保存已下载按钮
              if (this.hasPartiallyCachedChapters()) {
                Button() {
                  Row({ space: 6 }) {
                    SymbolGlyph($r('sys.symbol.externaldrive'))
                      .fontSize(13)
                      .fontColor([Color.White])
                    Text('保存已下载')
                      .fontSize(12)
                      .fontFamily(this.appFontFamily)
                      .fontColor(Color.White)
                  }
                }
                .height(34)
                .padding({ left: 14, right: 14 })
                .backgroundColor(ThemeAwareHelper.getTestManagementThemedColor('accent_green', this.themeState.currentTheme))
                .borderRadius(17)
                .enabled(!this.isDownloading)
                .onClick(() => this.savePartiallyCachedChapters())
              }
            }
            .width('100%')
          }

          if (this.isDownloading && this.downloadProgressTotal > 0) {
            Column({ space: 8 }) {
              Divider()
                .color(ThemeAwareHelper.getTestManagementThemedColor('divider', this.themeState.currentTheme))

              Row({ space: 6 }) {
                LoadingProgress()
                  .width(14)
                  .height(14)
                  .color(ThemeAwareHelper.getTestManagementThemedColor('accent_green', this.themeState.currentTheme))
                Text(this.cacheStats.contentType === CacheContentType.NOVEL ? this.getNovelCacheWorkingLabel() : '正在缓存中...')
                  .fontSize(12)
                  .fontWeight(FontWeight.Medium)
                  .fontFamily(this.appFontFamily)
                  .fontColor(ThemeAwareHelper.getTestManagementThemedColor('accent_green', this.themeState.currentTheme))
                Blank()
                Text(`${this.downloadProgressCurrent}/${this.downloadProgressTotal}`)
                  .fontSize(12)
                  .fontFamily(this.appFontFamily)
                  .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_secondary', this.themeState.currentTheme))
              }
              .width('100%')

              if (this.downloadCurrentChapterTitle) {
                Text(this.downloadCurrentChapterTitle)
                  .fontSize(11)
                  .fontFamily(this.appFontFamily)
                  .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_muted', this.themeState.currentTheme))
                  .maxLines(1)
                  .textOverflow({ overflow: TextOverflow.Ellipsis })
                  .width('100%')
              }

              Progress({
                value: this.downloadProgressTotal > 0 ? Math.round((this.downloadProgressCurrent / this.downloadProgressTotal) * 100) : 0,
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
    } else if (this.isCacheStatsLoading) {
      Stack({ alignContent: Alignment.TopStart }) {
        this.buildGlassSectionChrome()
        Row({ space: 8 }) {
          LoadingProgress()
            .width(16)
            .height(16)
            .color(ThemeAwareHelper.getTestManagementThemedColor('text_muted', this.themeState.currentTheme))
          Text('加载缓存状态...')
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
    }
  }

  private showClearCacheConfirm(): void {
    if (!this.cacheStats) {
      return;
    }

    const isManga = this.cacheStats.contentType === CacheContentType.MANGA;
    const contentTypeName = isManga ? '漫画' : (this.isCurrentNovelAudioSource() ? '听书' : '小说');
    const cachedLabel = isManga ? '已缓存章节' : this.getNovelCachedCountLabel();
    const restoreTip = isManga
      ? '清理后需要重新阅读才能再次缓存。'
      : (this.isCurrentNovelAudioSource() ? '清理后需要重新缓存才能离线播放。' : '清理后需要重新阅读才能再次缓存。');
    const sizeText = this.cacheStatusService.formatSize(this.cacheStats.cacheSize);
    this.cacheConfirmConfig = {
      title: '清理缓存',
      message: `确定要清理此${contentTypeName}的所有缓存吗？\n\n缓存大小: ${sizeText}\n${cachedLabel}: ${this.cacheStats.cachedChapterCount}章\n\n${restoreTip}`,
      actionLabel: '清理',
      actionKind: 'danger',
      pendingAction: 'clear_content'
    };
    this.cacheConfirmDialogLoadSignal++;
  }

  private async clearContentCache(): Promise<void> {
    if (!this.cacheStats || !this.content) {
      return;
    }

    try {
      const sourceId = this.cacheStats.contentType === CacheContentType.MANGA
        ? Number(this.pageParams?.sourceId)
        : undefined;
      const targetContentId = this.cacheStats.contentType === CacheContentType.NOVEL
        ? this.getNovelCacheBookId(this.getCurrentNovelSourceId(), this.content.id)
        : this.content.id;
      const success = await this.cacheStatusService.clearContentCache(
        this.cacheStats.contentType,
        targetContentId,
        sourceId
      );

      if (success) {
        this.getUIContext().getPromptAction().showToast({ message: '缓存已清理', duration: 2000 });
        await this.loadCacheStatus();
      } else {
        this.getUIContext().getPromptAction().showToast({ message: '清理失败', duration: 2000 });
      }
    } catch (error) {
      logger.error(TAG, `清理缓存失败: ${String(error)}`);
      this.getUIContext().getPromptAction().showToast({ message: '清理失败', duration: 2000 });
    }
  }

  @Builder
  buildShelfContentSection() {
    if (this.isLoadingShelfContent || this.shelfContentItems.length > 0) {
      Stack({ alignContent: Alignment.TopStart }) {
        this.buildGlassSectionChrome()
        Column({ space: 12 }) {
          Row() {
            Row({ space: 6 }) {
              SymbolGlyph($r('sys.symbol.bookshelf'))
                .fontSize(16)
                .fontColor([ThemeAwareHelper.getTestManagementThemedColor('accent_primary', this.themeState.currentTheme)])
              Text(this.currentShelfName ? `「${this.currentShelfName}」书架` : '同书架内容')
                .fontSize(16)
                .fontWeight(FontWeight.Bold)
                .fontFamily(this.appFontFamily)
                .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_primary', this.themeState.currentTheme))
            }
            Blank()
            if (this.isLoadingShelfContent) {
              LoadingProgress()
                .width(16)
                .height(16)
                .color(ThemeAwareHelper.getTestManagementThemedColor('text_muted', this.themeState.currentTheme))
            }
            if (this.shelfContentItems.length > 0) {
              SymbolGlyph($r('sys.symbol.chevron_down'))
                .fontSize(16)
                .fontColor([ThemeAwareHelper.getTestManagementThemedColor('text_muted', this.themeState.currentTheme)])
                .rotate({ angle: this.isShelfContentExpanded ? 0 : -90 })
                .animation({ duration: 250, curve: Curve.EaseInOut })
                .onClick(() => {
                  this.getUIContext().animateTo({ duration: 300, curve: Curve.EaseInOut }, () => {
                    this.isShelfContentExpanded = !this.isShelfContentExpanded;
                  });
                })
            }
          }
          .width('100%')
          .onClick(() => {
            if (this.shelfContentItems.length > 0) {
              this.getUIContext().animateTo({ duration: 300, curve: Curve.EaseInOut }, () => {
                this.isShelfContentExpanded = !this.isShelfContentExpanded;
              });
            }
          })

          if (this.isShelfContentExpanded) {
            Column({ space: 12 }) {
              if (this.shelfContentItems.length > 0 && this.hasMultipleContentTypes()) {
                Row({ space: 8 }) {
                  ForEach(
                    [
                      { key: 'all' as ShelfContentFilterType, label: '全部' },
                      { key: 'manga' as ShelfContentFilterType, label: '漫画' },
                      { key: 'novel' as ShelfContentFilterType, label: '小说' },
                      { key: 'ebook' as ShelfContentFilterType, label: '电子书' }
                    ],
                    (tab: ShelfFilterTab) => {
                      Text(tab.label)
                        .fontSize(12)
                        .fontFamily(this.appFontFamily)
                        .fontColor(this.shelfContentFilter === tab.key
                          ? Color.White
                          : ThemeAwareHelper.getTestManagementThemedColor('text_secondary', this.themeState.currentTheme))
                        .backgroundColor(this.shelfContentFilter === tab.key
                          ? ThemeAwareHelper.getTestManagementThemedColor('accent_primary', this.themeState.currentTheme)
                          : ThemeAwareHelper.getTestManagementThemedColor('comp_background_tertiary', this.themeState.currentTheme))
                        .padding({ left: 12, right: 12, top: 4, bottom: 4 })
                        .borderRadius(14)
                        .animation({ duration: 200, curve: Curve.EaseInOut })
                        .onClick(() => {
                          this.getUIContext().animateTo({ duration: 250, curve: Curve.EaseInOut }, () => {
                            this.shelfContentFilter = tab.key;
                          });
                        })
                    },
                    (tab: ShelfFilterTab) => `filter_${tab.key}`
                  )
                }
                .width('100%')
              }

              if (this.shelfContentItems.length > 0) {
                Scroll() {
                  Row({ space: 12 }) {
                    ForEach(this.getFilteredShelfContentItems(), (item: ShelfContentItem) => {
                      Column({ space: 6 }) {
                        Stack() {
                          if (item.coverUrl && (item.coverUrl.startsWith('http://') || item.coverUrl.startsWith('https://'))) {
                            AvifImage({
                              src: item.coverUrl,
                              imageWidth: SHELF_CONTENT_CARD_COVER_W,
                              imageHeight: SHELF_CONTENT_CARD_COVER_H,
                              objectFit: ImageFit.Cover,
                              imageBorderRadius: 6
                            })
                          } else if (item.coverUrl) {
                            Image(`file://${item.coverUrl}`)
                              .width(SHELF_CONTENT_CARD_COVER_W)
                              .height(SHELF_CONTENT_CARD_COVER_H)
                              .objectFit(ImageFit.Cover)
                              .borderRadius(6)
                          } else {
                            Column() {
                              SymbolGlyph($r('sys.symbol.book_open_fill'))
                                .fontSize(32)
                                .fontColor([ThemeAwareHelper.getTestManagementThemedColor('text_muted', this.themeState.currentTheme)])
                            }
                            .width(SHELF_CONTENT_CARD_COVER_W)
                            .height(SHELF_CONTENT_CARD_COVER_H)
                            .backgroundColor(ThemeAwareHelper.getTestManagementThemedColor('comp_background_tertiary', this.themeState.currentTheme))
                            .borderRadius(6)
                            .justifyContent(FlexAlign.Center)
                          }

                          Text(item.contentType === UnifiedContentType.MANGA ? '漫画'
                            : item.contentType === UnifiedContentType.EBOOK ? '电子书' : '小说')
                            .fontSize(9)
                            .fontColor(Color.White)
                            .backgroundColor('rgba(0,0,0,0.55)')
                            .padding({ left: 4, right: 4, top: 2, bottom: 2 })
                            .borderRadius(3)
                            .position({ x: 4, y: 4 })
                        }

                        Text(item.title)
                          .fontSize(11)
                          .fontFamily(this.appFontFamily)
                          .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_primary', this.themeState.currentTheme))
                          .maxLines(2)
                          .textOverflow({ overflow: TextOverflow.Ellipsis })
                          .width(SHELF_CONTENT_CARD_COVER_W)
                      }
                      .alignItems(HorizontalAlign.Start)
                      .onClick(() => this.navigateToShelfContentItem(item))
                    }, (item: ShelfContentItem) => `${item.id}_${this.shelfContentFilter}`)
                  }
                  .padding({ left: 4, right: 4 })
                }
                .scrollable(ScrollDirection.Horizontal)
                .scrollBar(BarState.Off)
                .width('100%')
                .transition(TransitionEffect.OPACITY.combine(TransitionEffect.translate({ y: -8 })))
              }
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

  /**
   * 智能推荐区域
   * 在内容加载完成后异步填充，显示横向可滚动的推荐卡片列表
   * 仅在有推荐内容或正在加载时渲染
   */
  @Builder
  buildRecommendationSection() {
    if (this.isLoadingRecommendations || this.recommendedItems.length > 0) {
      Stack({ alignContent: Alignment.TopStart }) {
        this.buildGlassSectionChrome()
        Column({ space: 12 }) {
          Row() {
            Row({ space: 6 }) {
              SymbolGlyph($r('sys.symbol.diamond'))
                .fontSize(16)
                .fontColor([ThemeAwareHelper.getTestManagementThemedColor('accent_primary', this.themeState.currentTheme)])
              Text('相关推荐')
                .fontSize(16)
                .fontWeight(FontWeight.Bold)
                .fontFamily(this.appFontFamily)
                .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_primary', this.themeState.currentTheme))
            }
            Blank()
            if (this.isLoadingRecommendations) {
              LoadingProgress()
                .width(16)
                .height(16)
                .color(ThemeAwareHelper.getTestManagementThemedColor('text_muted', this.themeState.currentTheme))
            }
            if (this.recommendedItems.length > 0) {
              SymbolGlyph($r('sys.symbol.chevron_down'))
                .fontSize(16)
                .fontColor([ThemeAwareHelper.getTestManagementThemedColor('text_muted', this.themeState.currentTheme)])
                .rotate({ angle: this.isRecommendationsExpanded ? 0 : -90 })
                .animation({ duration: 250, curve: Curve.EaseInOut })
                .onClick(() => {
                  this.getUIContext().animateTo({ duration: 300, curve: Curve.EaseInOut }, () => {
                    this.isRecommendationsExpanded = !this.isRecommendationsExpanded;
                  });
                })
            }
          }
          .width('100%')
          .onClick(() => {
            if (this.recommendedItems.length > 0) {
              this.getUIContext().animateTo({ duration: 300, curve: Curve.EaseInOut }, () => {
                this.isRecommendationsExpanded = !this.isRecommendationsExpanded;
              });
            }
          })

          if (this.isRecommendationsExpanded && this.recommendedItems.length > 0) {
            Scroll() {
              Row({ space: 12 }) {
                ForEach(this.recommendedItems, (item: RecommendationItem) => {
                  Column({ space: 6 }) {
                    Stack() {
                      if (item.coverUrl && (item.coverUrl.startsWith('http://') || item.coverUrl.startsWith('https://'))) {
                        AvifImage({
                          src: item.coverUrl,
                          imageWidth: RECOMMEND_CARD_COVER_W,
                          imageHeight: RECOMMEND_CARD_COVER_H,
                          objectFit: ImageFit.Cover,
                          imageBorderRadius: 6
                        })
                      } else if (item.coverUrl) {
                        Image(`file://${item.coverUrl}`)
                          .width(RECOMMEND_CARD_COVER_W)
                          .height(RECOMMEND_CARD_COVER_H)
                          .objectFit(ImageFit.Cover)
                          .borderRadius(6)
                      } else {
                        Column() {
                          SymbolGlyph($r('sys.symbol.book_open_fill'))
                            .fontSize(32)
                            .fontColor([ThemeAwareHelper.getTestManagementThemedColor('text_muted', this.themeState.currentTheme)])
                        }
                        .width(RECOMMEND_CARD_COVER_W)
                        .height(RECOMMEND_CARD_COVER_H)
                        .backgroundColor(ThemeAwareHelper.getTestManagementThemedColor('comp_background_tertiary', this.themeState.currentTheme))
                        .borderRadius(6)
                        .justifyContent(FlexAlign.Center)
                      }

                      Text(item.contentType === UnifiedContentType.MANGA ? '漫画'
                        : item.contentType === UnifiedContentType.EBOOK ? '电子书' : '小说')
                        .fontSize(9)
                        .fontColor(Color.White)
                        .backgroundColor('rgba(0,0,0,0.55)')
                        .padding({ left: 4, right: 4, top: 2, bottom: 2 })
                        .borderRadius(3)
                        .position({ x: 4, y: 4 })
                    }

                    Text(item.title)
                      .fontSize(11)
                      .fontFamily(this.appFontFamily)
                      .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_primary', this.themeState.currentTheme))
                      .maxLines(2)
                      .textOverflow({ overflow: TextOverflow.Ellipsis })
                      .width(RECOMMEND_CARD_COVER_W)
                  }
                  .alignItems(HorizontalAlign.Start)
                  .onClick(() => this.navigateToRecommendedItem(item))
                }, (item: RecommendationItem) => item.id)
              }
              .padding({ left: 4, right: 4 })
            }
            .scrollable(ScrollDirection.Horizontal)
            .scrollBar(BarState.Off)
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

  @Builder
  buildChapterList() {
    if (this.content?.contentType === UnifiedContentType.EBOOK && this.content.chapters.length === 0) {
      this.buildEBookProgressInfo()
    } else {
      Stack({ alignContent: Alignment.TopStart }) {
        this.buildGlassSectionChrome()
        Column({ space: 12 }) {
          Row() {
            Text(`章节列表 (${this.isChaptersLoading ? '...' : (this.content?.totalChapters || 0)})`)
              .fontSize(16)
              .fontWeight(FontWeight.Bold)
              .fontFamily(this.appFontFamily)
              .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_primary', this.themeState.currentTheme))

            Blank()

            Row({ space: 8 }) {
              if (!this.isChaptersLoading) {
                Button() {
                  SymbolGlyph(this.chapterSortOrder === ChapterSortOrder.ASCENDING
                    ? $r('sys.symbol.arrow_up')
                    : $r('sys.symbol.arrow_down'))
                    .fontSize(16)
                    .fontColor([ThemeAwareHelper.getTestManagementThemedColor('text_primary', this.themeState.currentTheme)])
                }
                .width(32)
                .height(32)
                .backgroundColor(Color.Transparent)
                .onClick(() => {
                  this.toggleGlobalChapterSortOrder();
                })
              }

              Button() {
                Row({ space: 4 }) {
                  Text(this.isChapterListExpanded ? '收起' : '展开')
                    .fontSize(12)
                    .fontFamily(this.appFontFamily)
                    .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_secondary', this.themeState.currentTheme))

                  SymbolGlyph($r('sys.symbol.chevron_down'))
                    .fontSize(14)
                    .fontColor([ThemeAwareHelper.getTestManagementThemedColor('text_secondary', this.themeState.currentTheme)])
                    .rotate({ angle: this.isChapterListExpanded ? 0 : -90 })
                    .animation({ duration: 250, curve: Curve.EaseInOut })
                }
              }
              .height(32)
              .padding({ left: 10, right: 10 })
              .backgroundColor(ThemeAwareHelper.getTestManagementThemedColor('comp_background_tertiary', this.themeState.currentTheme))
              .borderRadius(14)
              .onClick(() => {
                this.toggleChapterListExpanded();
              })
            }
          }
          .width('100%')

          if (this.isChapterListExpanded) {
            Column() {
              if (this.content?.contentType === UnifiedContentType.MANGA) {
                this.buildMangaChapterList()
              } else if (this.content?.contentType === UnifiedContentType.NOVEL) {
                this.buildNovelChapterList()
              } else if (this.content?.contentType === UnifiedContentType.EBOOK) {
                this.buildEBookChapterList()
              }

              if (this.isChaptersLoading) {
                Column({ space: 12 }) {
                  LoadingProgress()
                    .width(36)
                    .height(36)
                    .color(ThemeAwareHelper.getTestManagementThemedColor('accent_primary', this.themeState.currentTheme))

                  Text(this.chaptersLoadProgress || '正在加载章节列表...')
                    .fontSize(13)
                    .fontFamily(this.appFontFamily)
                    .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_secondary', this.themeState.currentTheme))
                }
                .width('100%')
                .height(120)
                .justifyContent(FlexAlign.Center)
                .alignItems(HorizontalAlign.Center)
              }
            }
            .width('100%')
            .transition(this.getReadAloudCacheFadeSlideTransition(8))
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

  @Builder
  buildEBookProgressInfo() {
    Stack({ alignContent: Alignment.TopStart }) {
      this.buildGlassSectionChrome()
      Column({ space: 16 }) {
        Text('阅读信息')
          .fontSize(16)
          .fontWeight(FontWeight.Bold)
          .fontFamily(this.appFontFamily)
          .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_primary', this.themeState.currentTheme))

        Column({ space: 8 }) {
          Row() {
            Text('阅读进度')
              .fontSize(14)
              .fontFamily(this.appFontFamily)
              .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_secondary', this.themeState.currentTheme))
            Blank()
            Text(`${this.resolveDisplayReadProgressPercent()}%`)
              .fontSize(14)
              .fontFamily(this.appFontFamily)
              .fontColor(ThemeAwareHelper.getTestManagementThemedColor('accent_primary', this.themeState.currentTheme))
          }
          .width('100%')

          Progress({ value: this.resolveDisplayReadProgressPercent(), total: 100, type: ProgressType.Linear })
            .width('100%')
            .height(4)
            .color(ThemeAwareHelper.getTestManagementThemedColor('accent_primary', this.themeState.currentTheme))
            .backgroundColor(ThemeAwareHelper.getTestManagementThemedColor('divider', this.themeState.currentTheme))
        }

        if (this.content?.lastReadChapterTitle) {
          Row() {
            Text('当前章节')
              .fontSize(14)
              .fontFamily(this.appFontFamily)
              .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_secondary', this.themeState.currentTheme))
            Blank()
            Text(this.content.lastReadChapterTitle)
              .fontSize(14)
              .fontFamily(this.appFontFamily)
              .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_primary', this.themeState.currentTheme))
              .maxLines(1)
              .textOverflow({ overflow: TextOverflow.Ellipsis })
              .constraintSize({ maxWidth: '60%' })
          }
          .width('100%')
        }

        Row() {
          Text('文件格式')
            .fontSize(14)
            .fontFamily(this.appFontFamily)
            .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_secondary', this.themeState.currentTheme))
          Blank()
          Text(this.getEBookFormat())
            .fontSize(14)
            .fontFamily(this.appFontFamily)
            .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_primary', this.themeState.currentTheme))
        }
        .width('100%')
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
    .id('' as string)
  }

  private openMangaSettings(): void {
    if (!this.content || !this.pageParams) {
      return;
    }

    const params: MangaSettingsPageParams = {
      mangaId: this.content.id,
      fromPage: 'UnifiedDetailPage'
    };
    this.navigateWithManagedWindowTransition('MangaSettingsPage', params);
  }

  private async refetchOnlineMangaInfo(): Promise<void> {
    if (!this.content || !this.pageParams || !this.isOnlineManga()) {
      return;
    }

    const mangaId = this.pageParams.contentId;
    const sourceId = this.pageParams.sourceId;
    if (!sourceId || Number(sourceId) <= 0) {
      this.getUIContext().getPromptAction().showToast({ message: '缺少图源信息', duration: 2000 });
      return;
    }

    logger.info(TAG, `开始重新获取在线漫画信息: mangaId=${mangaId}, sourceId=${sourceId}`);
    this.isRefetchingManga = true;

    try {
      this.mangaDetailLoader.setWebViewController(this.webViewController);

      const currentReadChapterIds = new Set<string>();
      const currentDownloadedChapterIds = new Set<string>();
      const currentBookmarkedChapterIds = new Set<string>();
      const currentLastReadChapterIndex = this.content.lastReadChapterIndex;

      this.content.chapters.forEach((ch: UnifiedChapter) => {
        if (ch.isRead) {
          currentReadChapterIds.add(ch.id);
        }
        if (ch.isDownloaded) {
          currentDownloadedChapterIds.add(ch.id);
        }
        if (ch.isBookmarked) {
          currentBookmarkedChapterIds.add(ch.id);
        }
      });

      const loadParams: MangaDetailLoadParams = {
        mangaId: mangaId,
        sourceId: Number(sourceId),
        forceRefresh: true
      };

      const progressCallback: MangaLoadProgressCallback = {
        onBasicInfoLoaded: async (manga: Manga, isFavorite: boolean): Promise<void> => {
          logger.info(TAG, `[重新获取] 基本信息已更新: ${manga.title}, 封面=${manga.coverImagePath}, 简介长度=${manga.description?.length || 0}`);
          this.isFavorite = isFavorite;
          if (this.content) {
            if (manga.title && manga.title.trim() !== '') {
              this.content.title = manga.title;
            }
            if (manga.description && manga.description.trim() !== '') {
              this.content.description = manga.description;
            }
            if (manga.metadata?.authors?.[0]) {
              this.content.author = manga.metadata.authors[0];
            }
            if (manga.metadata?.genres && manga.metadata.genres.length > 0) {
              this.content.genres = manga.metadata.genres;
            }
            if (manga.coverImagePath && manga.coverImagePath.trim() !== '') {
              this.content.coverUrl = manga.coverImagePath;
              await this.persistOnlineMangaCoverUrlForMainMenu(
                this.getOnlineMangaExternalIdForCover(manga, mangaId),
                manga.coverImagePath
              );
            }
            logger.info(TAG, `[重新获取] UI已更新: 标题=${this.content.title}, 封面=${this.content.coverUrl}`);
          }
        },
        onChaptersLoaded: (chapters: MangaChapter[]) => {
          logger.info(TAG, `[重新获取] 章节已更新: ${chapters.length}章`);
          const currentChapterCount = this.content?.chapters.length || 0;
          const newChapterCount = chapters.length;
          const addedCount = newChapterCount - currentChapterCount;

          if (addedCount > 0) {
            this.getUIContext().getPromptAction().showToast({ message: `新增 ${addedCount} 个新章节`, duration: 2000 });
          } else {
            this.getUIContext().getPromptAction().showToast({ message: '信息已更新', duration: 1500 });
          }

          if (this.content) {
            const originalManga = MangaAdapter.getOriginalManga(this.content);
            if (originalManga) {
              originalManga.chapters = chapters;
              this.content = MangaAdapter.toUnifiedContent(
                originalManga,
                chapters,
                this.isFavorite,
                currentReadChapterIds,
                currentDownloadedChapterIds,
                currentBookmarkedChapterIds,
                currentLastReadChapterIndex,
                sourceId,
                this.resolvedSourceName,
                this.resolvedSourcePkg
              );
            }
          }
        },
        onError: (error: string) => {
          logger.error(TAG, `[重新获取] 失败: ${error}`);
          this.getUIContext().getPromptAction().showToast({ message: `获取失败: ${error}`, duration: 2000 });
        }
      };

      await this.mangaDetailLoader.loadMangaDetailWithProgress(loadParams, progressCallback);
      logger.info(TAG, '重新获取在线漫画信息完成');
    } catch (error) {
      logger.error(TAG, `重新获取在线漫画信息异常: ${String(error)}`);
      this.getUIContext().getPromptAction().showToast({ message: `获取失败: ${String(error)}`, duration: 2000 });
    } finally {
      this.isRefetchingManga = false;
    }
  }

  private async refetchCoverImage(): Promise<void> {
    if (!this.isOnlineManga() || !this.pageParams) {
      return;
    }

    this.isRefetchingCover = true;

    try {
      const sourceId = Number(this.pageParams.sourceId);
      const mangaId = this.pageParams.contentId;
      const comicInfo = await this.dataManager.getComicById(mangaId);
      const externalId = comicInfo?.externalId || mangaId;
      logger.info(TAG, `重新获取封面: sourceId=${sourceId}, externalId=${externalId}`);

      await this.loadSourceName(sourceId);
      const mangaEngine = await this.webViewManager.getMangaEngine(sourceId, this.currentSourceName);
      if (mangaEngine) {
        const detailResult = await mangaEngine.getMangaDetail(externalId);
        if (detailResult.success && detailResult.data?.cover) {
          const newCoverUrl = detailResult.data.cover;
          logger.info(TAG, `获取到新封面: ${newCoverUrl}`);
          if (this.content) {
            this.content.coverUrl = newCoverUrl;
          }
          await this.persistOnlineMangaCoverUrlForMainMenu(mangaId, newCoverUrl);
          this.getUIContext().getPromptAction().showToast({ message: '封面已更新', duration: 1500 });
        } else {
          this.getUIContext().getPromptAction().showToast({ message: '获取封面失败', duration: 2000 });
        }
      }
    } catch (error) {
      logger.error(TAG, `重新获取封面失败: ${String(error)}`);
      this.getUIContext().getPromptAction().showToast({ message: `获取失败: ${String(error)}`, duration: 2000 });
    } finally {
      this.isRefetchingCover = false;
    }
  }

  private currentSourceName: string = '';

  private async loadSourceName(sourceId: number): Promise<void> {
    try {
      const sources: SourceInfo[] = await this.sourceManager.getAllSources();
      const sourceInfo: SourceInfo | undefined = sources.find((s: SourceInfo) => s.id === sourceId);
      if (sourceInfo) {
        this.currentSourceName = sourceInfo.name;
      }
    } catch (error) {
      logger.warn(TAG, `加载图源名称失败: ${String(error)}`);
    }
  }

  private async getSourceInfoById(sourceId: number): Promise<SourceInfo | null> {
    try {
      const sources: SourceInfo[] = await this.sourceManager.getAllSources();
      const sourceInfo: SourceInfo | undefined = sources.find((s: SourceInfo) => s.id === sourceId);
      return sourceInfo || null;
    } catch (error) {
      logger.warn(TAG, `获取图源信息失败: ${String(error)}`);
      return null;
    }
  }

  private async openInBrowser(): Promise<void> {
    if (!this.isOnlineManga() || !this.pageParams) {
      this.getUIContext().getPromptAction().showToast({ message: '无法获取网页地址', duration: 2000 });
      return;
    }

    try {
      const sourceId = Number(this.pageParams.sourceId);
      const mangaId = this.pageParams.contentId;
      const comicInfo = await this.dataManager.getComicById(mangaId);
      const externalId = comicInfo?.externalId || mangaId;
      const sourceInfo: SourceInfo | null = await this.getSourceInfoById(sourceId);
      if (!sourceInfo || !sourceInfo.baseUrl) {
        this.getUIContext().getPromptAction().showToast({ message: '无法获取图源信息', duration: 2000 });
        return;
      }

      let mangaUrl: string = sourceInfo.baseUrl;
      if (!mangaUrl.endsWith('/')) {
        mangaUrl += '/';
      }
      mangaUrl += externalId;

      logger.info(TAG, `在浏览器中打开: ${mangaUrl}`);
      const context = this.getUIContext()?.getHostContext() as common.UIAbilityContext;
      const want: Want = {
        action: 'ohos.want.action.viewData',
        uri: mangaUrl
      };
      await context.startAbility(want);
    } catch (error) {
      logger.error(TAG, `打开浏览器失败: ${String(error)}`);
      this.getUIContext().getPromptAction().showToast({ message: `打开失败: ${String(error)}`, duration: 2000 });
    }
  }

  private openEBookSettings(): void {
    if (!this.content || !this.pageParams) {
      return;
    }

    const params: EBookSettingsPageParams = {
      bookId: this.content.id
    };
    this.navigateWithManagedWindowTransition('EBookSettingsPage', params);
  }

  private async executeDownloadWithIndexes(selectedIndexes: number[]): Promise<void> {
    if (!this.content || selectedIndexes.length === 0) {
      return;
    }

    if (this.content.contentType === UnifiedContentType.NOVEL) {
      await this.downloadSelectedNovelChapters(selectedIndexes);
    } else if (this.content.contentType === UnifiedContentType.MANGA) {
      await this.downloadSelectedMangaChapters(selectedIndexes);
    }
  }

  private async downloadSelectedNovelChapters(selectedIndexes: number[]): Promise<void> {
    if (!this.content) {
      return;
    }

    const sourceId = this.getCurrentNovelSourceId();
    if (!sourceId) {
      this.getUIContext().getPromptAction().showToast({ message: '缺少书源信息' });
      return;
    }

    const chapters: LegadoChapter[] = [];
    for (const idx of selectedIndexes) {
      if (idx < this.content.chapters.length) {
        const originalChapter = NovelAdapter.getOriginalChapter(this.content.chapters[idx]);
        if (originalChapter) {
          chapters.push(originalChapter);
        }
      }
    }

    if (chapters.length === 0) {
      this.getUIContext().getPromptAction().showToast({ message: this.isCurrentNovelAudioSource() ? '无可缓存的章节音频' : '无可缓存的章节' });
      return;
    }

    this.registerDownloadCallback();
    this.isDownloading = true;
    this.downloadProgressCurrent = 0;
    this.downloadProgressTotal = chapters.length;
    this.downloadCurrentChapterTitle = '';

    const novelCacheBookId = this.getNovelCacheBookId(sourceId, this.content.id);
    this.getUIContext().getPromptAction().showToast({
      message: this.isCurrentNovelAudioSource()
        ? `开始缓存 ${chapters.length} 章音频...`
        : `开始缓存 ${chapters.length} 章...`
    });

    try {
      await this.unifiedDownloadManager.downloadNovelChapters({
        bookId: novelCacheBookId,
        bookTitle: this.content.title,
        sourceId: sourceId,
        chapters: chapters,
        startIndex: selectedIndexes[0],
        endIndex: selectedIndexes[selectedIndexes.length - 1]
      });
      this.getUIContext().getPromptAction().showToast({
        message: this.isCurrentNovelAudioSource()
          ? '听书缓存任务已创建，后台继续处理中...'
          : '缓存任务已创建，后台继续处理中...'
      });
    } catch (error) {
      logger.error(TAG, `缓存小说选中章节失败: ${String(error)}`);
      this.getUIContext().getPromptAction().showToast({ message: `缓存失败: ${String(error)}` });
      this.isDownloading = false;
      this.downloadProgressCurrent = 0;
      this.downloadProgressTotal = 0;
    }
  }

  private async downloadSelectedMangaChapters(selectedIndexes: number[]): Promise<void> {
    if (!this.content || !this.isOnlineManga()) {
      return;
    }

    const sourceId = Number(this.pageParams?.sourceId);
    if (!sourceId || sourceId <= 0) {
      this.getUIContext().getPromptAction().showToast({ message: '缺少图源信息' });
      return;
    }

    const chaptersToDownload = selectedIndexes
      .filter((idx: number) => idx < this.content!.chapters.length && !this.isChapterFullyCached(this.content!.chapters[idx].id))
      .map((idx: number) => this.content!.chapters[idx]);

    if (chaptersToDownload.length === 0) {
      this.getUIContext().getPromptAction().showToast({ message: '选中的章节已全部缓存' });
      return;
    }

    this.registerDownloadCallback();
    this.isDownloading = true;
    this.downloadProgressCurrent = 0;
    this.downloadProgressTotal = chaptersToDownload.length;
    this.downloadCurrentChapterTitle = '';

    this.getUIContext().getPromptAction().showToast({ message: `开始缓存 ${chaptersToDownload.length} 章...` });

    try {
      const downloadChapters: MangaChapterDownloadItem[] = [];
      for (const ch of chaptersToDownload) {
        const item: MangaChapterDownloadItem = {
          chapterId: ch.id,
          chapterTitle: ch.title,
          chapterIndex: ch.index,
          pageListFetcher: this.createPageListFetcher()
        };
        downloadChapters.push(item);
      }

      await this.unifiedDownloadManager.downloadMangaChapters(
        this.content.id,
        this.content.title,
        sourceId,
        downloadChapters
      );
      this.getUIContext().getPromptAction().showToast({ message: '缓存任务已创建，后台继续处理中...' });
    } catch (error) {
      logger.error(TAG, `缓存漫画选中章节失败: ${String(error)}`);
      this.getUIContext().getPromptAction().showToast({ message: `缓存失败: ${String(error)}` });
      this.isDownloading = false;
      this.downloadProgressCurrent = 0;
      this.downloadProgressTotal = 0;
    }
  }

  private registerDownloadCallback(): void {
    if (this.downloadCallbackRegistered) {
      return;
    }

    const callback: UnifiedDownloadCallback = {
      onProgress: (task: UnifiedDownloadTask) => {
        if (this.content && this.isCurrentContentTask(task)) {
          const previousDownloaded = this.downloadProgressCurrent;
          this.downloadProgressCurrent = task.downloadedCount;
          this.downloadProgressTotal = task.totalCount;
          this.downloadCurrentChapterTitle = task.chapterTitle || '';
          this.isDownloading = task.status === UnifiedTaskStatus.DOWNLOADING || task.status === UnifiedTaskStatus.PENDING;
          if (task.downloadedCount > 0 && task.downloadedCount !== previousDownloaded) {
            this.scheduleCacheStatusRefresh();
          }
        }
      },
      onComplete: (task: UnifiedDownloadTask) => {
        if (this.content && this.isCurrentContentTask(task)) {
          this.isDownloading = false;
          this.downloadProgressCurrent = 0;
          this.downloadProgressTotal = 0;
          this.downloadCurrentChapterTitle = '';
          this.clearCacheStatusRefreshTimer();
          void this.loadCacheStatus();
          logger.info(TAG, `缓存完成: ${task.contentTitle}`);
        }
      },
      onError: (task: UnifiedDownloadTask, error: string) => {
        if (this.content && this.isCurrentContentTask(task)) {
          this.isDownloading = false;
          this.downloadCurrentChapterTitle = '';
          this.clearCacheStatusRefreshTimer();
          logger.error(TAG, `缓存失败: ${task.contentTitle}, ${error}`);
        }
      }
    };

    this.unifiedDownloadManager.registerGlobalCallback(callback);
    this.downloadCallback = callback;
    this.downloadCallbackRegistered = true;
    logger.info(TAG, '已注册缓存进度回调');
  }

  private unregisterDownloadCallback(): void {
    if (this.downloadCallback) {
      this.unifiedDownloadManager.unregisterGlobalCallback(this.downloadCallback);
      this.downloadCallback = null;
    }
    this.clearCacheStatusRefreshTimer();
    this.downloadCallbackRegistered = false;
    logger.info(TAG, '已标记缓存回调为未注册');
  }

  private async clearMangaCache(): Promise<void> {
    if (!this.content || !this.isOnlineManga()) {
      return;
    }

    const sourceId = Number(this.pageParams?.sourceId);
    if (!sourceId || sourceId <= 0) {
      return;
    }

    try {
      await this.cacheStatusService.clearContentCache(
        CacheContentType.MANGA,
        this.content.id,
        sourceId
      );
      this.getUIContext().getPromptAction().showToast({ message: '漫画缓存已清理' });
      await this.loadCacheStatus();
    } catch (error) {
      this.getUIContext().getPromptAction().showToast({ message: `清理漫画缓存失败: ${String(error)}` });
    }
  }

  private async clearNovelCache(): Promise<void> {
    if (!this.content) {
      return;
    }

    try {
      const sourceId = this.getCurrentNovelSourceId();
      const novelCacheBookId = this.getNovelCacheBookId(sourceId, this.content.id);
      await this.novelCacheManager.clearBookCache(novelCacheBookId);
      this.getUIContext().getPromptAction().showToast({ message: `${this.isCurrentNovelAudioSource() ? '听书缓存' : '小说缓存'}已清理` });
      this.content.chapters.forEach((ch: UnifiedChapter) => {
        ch.isDownloaded = false;
      });
      await this.loadCacheStatus();
    } catch (error) {
      this.getUIContext().getPromptAction().showToast({
        message: `${this.isCurrentNovelAudioSource() ? '清理听书缓存失败' : '清理小说缓存失败'}: ${String(error)}`
      });
    }
  }

  private showNovelCacheClearConfirm(): void {
    this.cacheConfirmConfig = {
      title: this.isCurrentNovelAudioSource() ? '清理听书缓存' : '清理小说缓存',
      message: this.isCurrentNovelAudioSource()
        ? '确定要清理当前小说的听书缓存吗？清理后需要重新缓存才能离线播放。'
        : '确定要清理当前小说的章节缓存吗？清理后需要重新缓存才能离线阅读。',
      actionLabel: '清理',
      actionKind: 'danger',
      pendingAction: 'clear_novel'
    };
    this.cacheConfirmDialogLoadSignal++;
  }

  private showMangaCacheClearConfirm(): void {
    this.cacheConfirmConfig = {
      title: '清理漫画缓存',
      message: '确定要清理当前漫画的章节与页面缓存吗？清理后需要重新缓存才能离线阅读。',
      actionLabel: '清理',
      actionKind: 'danger',
      pendingAction: 'clear_manga'
    };
    this.cacheConfirmDialogLoadSignal++;
  }

  private async handleCacheConfirmAction(pendingAction: string): Promise<void> {
    if (pendingAction === 'clear_content') {
      await this.clearContentCache();
    } else if (pendingAction === 'clear_novel') {
      await this.clearNovelCache();
    } else if (pendingAction === 'clear_manga') {
      await this.clearMangaCache();
    }
  }

  @Builder
  private buildCacheConfirmDialog() {
    CacheConfirmDialogComponent({
      themeState: this.themeState,
      loadSignal: this.cacheConfirmDialogLoadSignal,
      config: this.cacheConfirmConfig,
      onConfirm: (pendingAction: string) => {
        void this.handleCacheConfirmAction(pendingAction);
      }
    })
  }

  /**
   * 获取电子书格式
   */
  private getEBookFormat(): string {
    if (!this.content) return '未知';
    const originalEBook = EBookAdapter.getOriginalEBook(this.content);
    if (originalEBook && originalEBook.format) {
      return originalEBook.format.toUpperCase();
    }
    // 对于在线电子书，尝试从content.format获取
    if (this.content.format) {
      return this.content.format.toUpperCase();
    }
    return '未知';
  }

  /**
   * 漫画章节列表（显示图片数量、阅读进度、更新时间等）
   */
  @Builder
  buildMangaChapterList() {
    List() {
      ForEach(this.getFilteredChapters(), (chapter: UnifiedChapter) => {
        ListItem() {
          Row({ space: 12 }) {
            // 左侧：已读指示器
            Column() {
              if (chapter.isRead) {
                Circle()
                  .width(8)
                  .height(8)
                  .fill(ThemeAwareHelper.getTestManagementThemedColor('accent_blue', this.themeState.currentTheme))
              } else {
                Circle()
                  .width(8)
                  .height(8)
                  .fill(Color.Transparent)
                  .stroke(ThemeAwareHelper.getTestManagementThemedColor('text_muted', this.themeState.currentTheme))
                  .strokeWidth(1)
              }
            }
            .width(20)
            .justifyContent(FlexAlign.Center)

            // 中间：章节信息
            Column({ space: 4 }) {
              // 章节号 + 清理后的标题
              Row({ space: 6 }) {
                // 固定的章节号前缀
                Text(this.cleanChapterTitle(chapter.title, chapter.index)[0])
                  .fontSize(13)
                  .fontFamily(this.appFontFamily)
                  .fontWeight(FontWeight.Medium)
                  .fontColor(chapter.isRead 
                    ? ThemeAwareHelper.getTestManagementThemedColor('text_muted', this.themeState.currentTheme)
                    : ThemeAwareHelper.getTestManagementThemedColor('accent_primary', this.themeState.currentTheme))
                  .flexShrink(0)
                
                // 清理后的真实标题
                Text(this.cleanChapterTitle(chapter.title, chapter.index)[1])
                  .fontSize(12)
                  .fontFamily(this.appFontFamily)
                  .fontWeight(chapter.isRead ? FontWeight.Normal : FontWeight.Medium)
                  .fontColor(chapter.isRead 
                    ? ThemeAwareHelper.getTestManagementThemedColor('text_muted', this.themeState.currentTheme)
                    : ThemeAwareHelper.getTestManagementThemedColor('text_primary', this.themeState.currentTheme))
                  .maxLines(1)
                  .textOverflow({ overflow: TextOverflow.Ellipsis })
                  .layoutWeight(1)
              }
              .width('100%')

              Row({ space: 12 }) {
                // 章节进度信息（从chapterProgressMap获取）
                Text(this.getChapterProgressText(chapter.id))
                  .fontSize(11)
                  .fontFamily(this.appFontFamily)
                  .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_muted', this.themeState.currentTheme))
                  .maxLines(1)
                  .textOverflow({ overflow: TextOverflow.Ellipsis })
                  .constraintSize({ maxWidth: 180 })
                
                // 更新时间
                if (chapter.publishDate) {
                  Text(this.formatDate(chapter.publishDate))
                    .fontSize(11)
                    .fontFamily(this.appFontFamily)
                    .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_muted', this.themeState.currentTheme))
                }
              }
            }
            .alignItems(HorizontalAlign.Start)
            .layoutWeight(1)

            // 右侧：状态图标/文字
            Row({ space: 6 }) {
              // 在线漫画显示缓存状态标记
              if (this.isChapterFullyCached(chapter.id) && !this.content?.isLocal) {
                Text('已下载')
                  .fontSize(10)
                  .fontFamily(this.appFontFamily)
                  .fontColor(ThemeAwareHelper.getTestManagementThemedColor('accent_green', this.themeState.currentTheme))
                  .padding({ left: 6, right: 6, top: 3, bottom: 3 })
                  .backgroundColor(ThemeAwareHelper.getTestManagementThemedColor('accent_green', this.themeState.currentTheme) + '15')
                  .borderRadius(8)
              } else if (this.isChapterPartiallyCached(chapter.id) && !this.content?.isLocal) {
                Text(this.getPartialCacheText(chapter.id))
                  .fontSize(10)
                  .fontFamily(this.appFontFamily)
                  .fontColor(ThemeAwareHelper.getTestManagementThemedColor('accent_orange', this.themeState.currentTheme))
                  .padding({ left: 6, right: 6, top: 3, bottom: 3 })
                  .backgroundColor(ThemeAwareHelper.getTestManagementThemedColor('accent_orange', this.themeState.currentTheme) + '15')
                  .borderRadius(8)
              }
              if (chapter.isBookmarked) {
                SymbolGlyph($r('sys.symbol.bookmark_fill'))
                  .fontSize(16)
                  .fontColor([ThemeAwareHelper.getTestManagementThemedColor('accent_orange', this.themeState.currentTheme)])
              }
            }
          }
          .width('100%')
          .padding({ top: 12, bottom: 12 })
          .onClick(() => this.startReading(chapter.index))
        }
      }, (chapter: UnifiedChapter) => chapter.id)
    }
    .width('100%')
    .layoutWeight(1)
    .scrollBar(BarState.Auto)
    .edgeEffect(EdgeEffect.Spring)
    .divider({ strokeWidth: 0.5, color: ThemeAwareHelper.getTestManagementThemedColor('divider', this.themeState.currentTheme) })
  }

  /**
   * 小说章节列表（更直观的已读/未读状态）
   */
  @Builder
  buildNovelChapterList() {
    List() {
      ForEach(this.getFilteredChapters(), (chapter: UnifiedChapter) => {
        ListItem() {
          Row({ space: 12 }) {
            // 左侧：章节序号和已读状态
            Column() {
              Text(`${chapter.index + 1}`)
                .fontSize(12)
                .fontFamily(this.appFontFamily)
                .fontColor(this.isNovelChapterReadForDisplay(chapter)
                  ? ThemeAwareHelper.getTestManagementThemedColor('accent_blue', this.themeState.currentTheme)
                  : ThemeAwareHelper.getTestManagementThemedColor('text_muted', this.themeState.currentTheme))
                .fontWeight(this.isNovelChapterReadForDisplay(chapter) ? FontWeight.Bold : FontWeight.Normal)
            }
            .width(36)
            .height(36)
            .borderRadius(18)
            .backgroundColor(this.isNovelChapterReadForDisplay(chapter)
              ? ThemeAwareHelper.getTestManagementThemedColor('accent_blue', this.themeState.currentTheme) + '20'
              : ThemeAwareHelper.getTestManagementThemedColor('comp_background_tertiary', this.themeState.currentTheme))
            .justifyContent(FlexAlign.Center)

            // 中间：章节标题
            Column({ space: 2 }) {
              Text(chapter.title)
                .fontSize(14)
                .fontFamily(this.appFontFamily)
                .fontWeight(this.isNovelChapterReadForDisplay(chapter) ? FontWeight.Normal : FontWeight.Medium)
                .fontColor(this.isNovelChapterReadForDisplay(chapter)
                  ? ThemeAwareHelper.getTestManagementThemedColor('text_muted', this.themeState.currentTheme)
                  : ThemeAwareHelper.getTestManagementThemedColor('text_primary', this.themeState.currentTheme))
                .maxLines(1)
                .textOverflow({ overflow: TextOverflow.Ellipsis })

              // 字数和缓存状态
              Row({ space: 8 }) {
                if (chapter.wordCount) {
                  Text(`${chapter.wordCount}字`)
                    .fontSize(11)
                    .fontFamily(this.appFontFamily)
                    .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_muted', this.themeState.currentTheme))
                }
                if (this.isNovelChapterCachedForDisplay(chapter)) {
                  Row({ space: 2 }) {
                    SymbolGlyph($r('sys.symbol.checkmark_circle_fill'))
                      .fontSize(10)
                      .fontColor([ThemeAwareHelper.getTestManagementThemedColor('accent_green', this.themeState.currentTheme)])
                    Text(this.getNovelDownloadedTagLabel())
                      .fontSize(10)
                      .fontFamily(this.appFontFamily)
                      .fontColor(ThemeAwareHelper.getTestManagementThemedColor('accent_green', this.themeState.currentTheme))
                  }
                }
              }
            }
            .alignItems(HorizontalAlign.Start)
            .layoutWeight(1)

            // 右侧：阅读状态标签
            if (this.getNovelChapterProgressStatusLabel(chapter).length > 0) {
              Text(this.getNovelChapterProgressStatusLabel(chapter))
                .fontSize(10)
                .fontFamily(this.appFontFamily)
                .fontColor(this.getNovelChapterProgressStatusColor(chapter))
                .padding({ left: 8, right: 8, top: 4, bottom: 4 })
                .backgroundColor(this.getNovelChapterProgressStatusBackground(chapter))
                .borderRadius(10)
            }
          }
          .width('100%')
          .padding({ top: 10, bottom: 10 })
          .onClick(() => this.startReading(chapter.index))
        }
      }, (chapter: UnifiedChapter) => chapter.id)
    }
    .width('100%')
    .layoutWeight(1)
    .scrollBar(BarState.Auto)
    .edgeEffect(EdgeEffect.Spring)
  }

  /**
   * 电子书章节列表
   */
  @Builder
  buildEBookChapterList() {
    List() {
      ForEach(this.getFilteredChapters(), (chapter: UnifiedChapter) => {
        ListItem() {
          Row({ space: 12 }) {
            // 左侧：章节信息
            Column({ space: 4 }) {
              // 章节标题
              Text(chapter.title)
                .fontSize(14)
                .fontFamily(this.appFontFamily)
                .fontWeight(chapter.isRead ? FontWeight.Normal : FontWeight.Medium)
                .fontColor(chapter.isRead 
                  ? ThemeAwareHelper.getTestManagementThemedColor('text_muted', this.themeState.currentTheme)
                  : ThemeAwareHelper.getTestManagementThemedColor('text_primary', this.themeState.currentTheme))
                .maxLines(1)
                .textOverflow({ overflow: TextOverflow.Ellipsis })

              // 字数信息
              if (chapter.wordCount && chapter.wordCount > 0) {
                Text(`${chapter.wordCount}字`)
                  .fontSize(11)
                  .fontFamily(this.appFontFamily)
                  .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_muted', this.themeState.currentTheme))
              }
            }
            .alignItems(HorizontalAlign.Start)
            .layoutWeight(1)

            // 右侧：阅读状态标签
            if (chapter.isRead) {
              Text('已读')
                .fontSize(10)
                .fontFamily(this.appFontFamily)
                .fontColor(ThemeAwareHelper.getTestManagementThemedColor('accent_blue', this.themeState.currentTheme))
                .padding({ left: 8, right: 8, top: 4, bottom: 4 })
                .backgroundColor(ThemeAwareHelper.getTestManagementThemedColor('accent_blue', this.themeState.currentTheme) + '15')
                .borderRadius(10)
            } else if (chapter.index === this.content?.lastReadChapterIndex) {
              Text('阅读中')
                .fontSize(10)
                .fontFamily(this.appFontFamily)
                .fontColor(ThemeAwareHelper.getTestManagementThemedColor('accent_primary', this.themeState.currentTheme))
                .padding({ left: 8, right: 8, top: 4, bottom: 4 })
                .backgroundColor(ThemeAwareHelper.getTestManagementThemedColor('accent_primary', this.themeState.currentTheme) + '15')
                .borderRadius(10)
            }
          }
          .width('100%')
          .padding({ top: 12, bottom: 12 })
          .onClick(() => this.startReading(chapter.index))
        }
      }, (chapter: UnifiedChapter) => chapter.id)
    }
    .width('100%')
    .layoutWeight(1)
    .scrollBar(BarState.Auto)
    .edgeEffect(EdgeEffect.Spring)
    .divider({ strokeWidth: 0.5, color: ThemeAwareHelper.getTestManagementThemedColor('divider', this.themeState.currentTheme) })
  }

  /**
   * 格式化日期（支持时间戳和ISO字符串）
   */
  private formatDate(dateValue: string | number | undefined): string {
    if (!dateValue) return '';
    
    let timestamp: number;
    if (typeof dateValue === 'string') {
      // ISO字符串格式
      const parsed = Date.parse(dateValue);
      if (isNaN(parsed)) return '';
      timestamp = parsed;
    } else {
      timestamp = dateValue;
    }
    
    return this.formatRelativeTime(timestamp);
  }

  /**
   * 移除HTML标签和实体
   */
  private stripHtmlTags(text: string): string {
    if (!text) return text;
    return text
      .replace(/<br\s*\/?>/gi, '\n')  // 将<br>转换为换行
      .replace(/<\/p>/gi, '\n')       // 将</p>转换为换行
      .replace(/<[^>]*>/g, '')        // 移除所有HTML标签
      .replace(/&nbsp;/g, ' ')        // 转换空格实体
      .replace(/&amp;/g, '&')         // 转换&实体
      .replace(/&lt;/g, '<')          // 转换<实体
      .replace(/&gt;/g, '>')          // 转换>实体
      .replace(/&quot;/g, '"')        // 转换"实体
      .replace(/&#39;/g, "'")         // 转换'实体
      .replace(/\n\s*\n/g, '\n')      // 移除多余空行
      .trim();
  }

  /**
   * 格式化时间戳为相对时间
   */
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
  
  /**
   * 获取章节进度显示文本
   */
  private getChapterProgressText(chapterId: string): string {
    const progress = this.chapterProgressMap.get(chapterId);
    if (!progress) {
      return '页数未知';
    }
    
    const total = progress.totalPages;
    if (total <= 0) {
      return '页数未知';
    }
    
    const current = progress.lastReadPageIndex >= 0 ? (progress.lastReadPageIndex + 1) : 0;
    if (current > 0) {
      return `共 ${total} 页 • 已读 ${current}/${total}`;
    }
    return `共 ${total} 页 • 未开始`;
  }

  @Builder
  buildLoadingView() {
    Column() {
      LoadingProgress()
        .width(48)
        .height(48)
        .color(ThemeAwareHelper.getTestManagementThemedColor('accent_primary', this.themeState.currentTheme))
      Text('加载中...')
        .fontSize(14)
        .fontFamily(this.appFontFamily)
        .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_muted', this.themeState.currentTheme))
        .margin({ top: 16 })
    }
    .width('100%')
    .height('100%')
    .justifyContent(FlexAlign.Center)
  }

  @Builder
  buildErrorView() {
    Column({ space: 16 }) {
      SymbolGlyph($r('sys.symbol.exclamationmark_triangle'))
        .fontSize(48)
        .fontColor([ThemeAwareHelper.getTestManagementThemedColor('color_error', this.themeState.currentTheme)])

      Text(this.errorMessage)
        .fontSize(14)
        .fontFamily(this.appFontFamily)
        .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_secondary', this.themeState.currentTheme))

      Button('重试')
        .fontSize(14)
        .fontFamily(this.appFontFamily)
        .onClick(() => this.loadContent())
    }
    .width('100%')
    .height('100%')
    .justifyContent(FlexAlign.Center)
  }

  /**
   * 打开封面预览（带动画）
   */
  private openCoverPreview(): void {
    if (!this.content?.coverUrl) {
      this.getUIContext().getPromptAction().showToast({ message: '无封面图片', duration: 2000 });
      return;
    }
    
    // 初始化动画状态
    this.coverPreviewOpacity = 0;
    this.coverPreviewScale = 0.3;
    this.showCoverPreview = true;
    
    // 延迟执行动画，确保 UI 已渲染
    setTimeout(() => {
      this.getUIContext().animateTo({
        duration: 300,
        curve: curves.springMotion(0.6, 0.9)
      }, () => {
        this.coverPreviewOpacity = 1;
        this.coverPreviewScale = 1;
      });
    }, 16);
  }
  
  /**
   * 关闭封面预览（带动画）
   */
  private closeCoverPreview(): void {
    this.getUIContext().animateTo({
      duration: 200,
      curve: Curve.EaseOut
    }, () => {
      this.coverPreviewOpacity = 0;
      this.coverPreviewScale = 0.3;
    });
    
    setTimeout(() => {
      this.showCoverPreview = false;
    }, 200);
  }

  /**
   * 封面预览弹窗
   */
  @Builder
  buildCoverPreviewOverlay() {
    Stack() {
      // 背景层：封面图片高斯模糊效果
      Stack() {
        // 封面图片作为背景（高斯模糊）
        if (this.coverPixelMap) {
          Image(this.coverPixelMap)
            .width('100%')
            .height('100%')
            .objectFit(ImageFit.Cover)
            .blur(50)
            .brightness(0.7)
            .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.TOP, SafeAreaEdge.BOTTOM])
        } else if (this.hasCoverImageSource() && !this.isNetworkCover()) {
          Image(this.getCoverImageSource())
            .width('100%')
            .height('100%')
            .objectFit(ImageFit.Cover)
            .blur(50)
            .brightness(0.7)
            .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.TOP, SafeAreaEdge.BOTTOM])
        } else {
          AvifImage({
            src: this.getCoverImageSource() as string,
            imageWidth: '100%',
            imageHeight: '100%',
            objectFit: ImageFit.Cover
          })
            .blur(50)
            .brightness(0.7)
            .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.TOP, SafeAreaEdge.BOTTOM])
        }
        
        // 暗色遮罩层
        Column()
          .width('100%')
          .height('100%')
          .backgroundColor('rgba(0,0,0,0.3)')
          .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.TOP, SafeAreaEdge.BOTTOM])
      }
      .width('100%')
      .height('100%')
      .opacity(this.coverPreviewOpacity)
      .onClick(() => this.closeCoverPreview())
      .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.TOP, SafeAreaEdge.BOTTOM])
      
      // 封面图片（居中显示，带缩放动画）
      Column() {
        if (this.coverPixelMap) {
          Image(this.coverPixelMap)
            .width('100%')
            .height('70%')
            .objectFit(ImageFit.Contain)
        } else if (this.hasCoverImageSource() && !this.isNetworkCover()) {
          Image(this.getCoverImageSource())
            .width('100%')
            .height('70%')
            .objectFit(ImageFit.Contain)
        } else {
          AvifImage({
            src: this.getCoverImageSource() as string,
            imageWidth: '100%',
            imageHeight: '70%',
            objectFit: ImageFit.Contain
          })
        }
      }
      .width('100%')
      .height('100%')
      .justifyContent(FlexAlign.Center)
      .alignItems(HorizontalAlign.Center)
      .scale({ x: this.coverPreviewScale, y: this.coverPreviewScale })
      .opacity(this.coverPreviewOpacity)
      
      // 底部操作按钮（保存、分享、关闭）
      Row({ space: 24 }) {
        // 保存到相册
        Button() {
          Column({ space: 4 }) {
            if (this.isSavingCover) {
              LoadingProgress()
                .width(22)
                .height(22)
                .color(Color.White)
            } else {
              SymbolGlyph($r('sys.symbol.square_and_arrow_down'))
                .fontSize(24)
                .fontColor([Color.White])
            }
            Text('保存')
              .fontSize(12)
              .fontFamily(this.appFontFamily)
              .fontColor(Color.White)
          }
        }
        .width(70)
        .height(70)
        .backgroundColor('rgba(255,255,255,0.2)')
        .borderRadius(35)
        .enabled(!this.isSavingCover)
        .onClick(() => this.saveCoverToGallery())
        
        // 分享
        Button() {
          Column({ space: 4 }) {
            SymbolGlyph($r('sys.symbol.share'))
              .fontSize(24)
              .fontColor([Color.White])
            Text('分享')
              .fontSize(12)
              .fontFamily(this.appFontFamily)
              .fontColor(Color.White)
          }
        }
        .width(70)
        .height(70)
        .backgroundColor('rgba(255,255,255,0.2)')
        .borderRadius(35)
        .onClick(() => this.shareCover())
        
        // 关闭按钮
        Button() {
          Column({ space: 4 }) {
            SymbolGlyph($r('sys.symbol.xmark'))
              .fontSize(24)
              .fontColor([Color.White])
            Text('关闭')
              .fontSize(12)
              .fontFamily(this.appFontFamily)
              .fontColor(Color.White)
          }
        }
        .width(70)
        .height(70)
        .backgroundColor('rgba(255,255,255,0.2)')
        .borderRadius(35)
        .onClick(() => this.closeCoverPreview())
      }
      .width('100%')
      .justifyContent(FlexAlign.Center)
      .padding({ bottom: this.navigationBarHeight + 32 })
      .position({ x: 0, y: '85%' })
      .opacity(this.coverPreviewOpacity)
    }
    .width('100%')
    .height('100%')
    .position({ x: 0, y: 0 })
    .zIndex(100)
    .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.TOP, SafeAreaEdge.BOTTOM])
  }
  
  /**
   * 保存封面到相册
   * 使用 showAssetsCreationDialog 方式，无需申请权限
   */
  private async saveCoverToGallery(): Promise<void> {
    const coverUrl = this.getRawCoverImagePath();
    if (!coverUrl) {
      this.getUIContext().getPromptAction().showToast({ message: '无封面图片', duration: 2000 });
      return;
    }
    if (coverUrl.startsWith('app.media.')) {
      this.getUIContext().getPromptAction().showToast({ message: '内置资源封面暂不支持保存', duration: 2000 });
      return;
    }
    
    this.isSavingCover = true;
    
    try {
      const context = (this.getUIContext().getHostContext() as common.UIAbilityContext) as common.UIAbilityContext;
      let localFilePath: string;
      
      // 判断是本地文件还是网络图片
      if (coverUrl.startsWith('http://') || coverUrl.startsWith('https://')) {
        // 网络图片：先下载到沙箱临时文件
        const httpRequest = http.createHttp();
        const response = await httpRequest.request(coverUrl, {
          method: http.RequestMethod.GET,
          expectDataType: http.HttpDataType.ARRAY_BUFFER
        });
        httpRequest.destroy();
        
        if (response.responseCode !== 200) {
          throw new Error(`下载失败: ${response.responseCode}`);
        }
        
        const imageData = response.result as ArrayBuffer;
        localFilePath = `${context.cacheDir}/save_cover_${Date.now()}.jpg`;
        const tempFile = SafeFileUtils.openSync(localFilePath, fs.OpenMode.CREATE | fs.OpenMode.WRITE_ONLY);
        SafeFileUtils.writeSync(tempFile.fd, imageData);
        SafeFileUtils.closeSync(tempFile);
      } else {
        // 本地文件：直接使用
        localFilePath = coverUrl.startsWith('file://') ? coverUrl.substring(7) : coverUrl;
      }
      
      // 获取文件后缀名
      const lastDotIndex = localFilePath.lastIndexOf('.');
      const fileExtension = lastDotIndex > 0 ? localFilePath.substring(lastDotIndex + 1) : 'jpg';
      
      // 转换为沙箱文件 URI
      const sandboxUri = fileUri.getUriFromPath(localFilePath);
      
      // 创建 photoAccessHelper
      const phAccessHelper = photoAccessHelper.getPhotoAccessHelper(context);
      
      // 准备保存配置
      const srcFileUris: Array<string> = [sandboxUri];
      const photoCreationConfigs: Array<photoAccessHelper.PhotoCreationConfig> = [{
        title: `cover_${this.content?.title || 'image'}`,
        fileNameExtension: fileExtension,
        photoType: photoAccessHelper.PhotoType.IMAGE,
        subtype: photoAccessHelper.PhotoSubtype.DEFAULT
      }];
      
      // 显示保存对话框让用户确认
      const desFileUris: Array<string> = await phAccessHelper.showAssetsCreationDialog(srcFileUris, photoCreationConfigs);
      
      if (desFileUris.length > 0) {
        // 打开目标文件和源文件
        const destFile = await fs.open(desFileUris[0], fs.OpenMode.WRITE_ONLY);
        const srcFile = await fs.open(sandboxUri, fs.OpenMode.READ_ONLY);
        
        // 复制文件内容
        await fs.copyFile(srcFile.fd, destFile.fd);
        
        // 关闭文件
        SafeFileUtils.closeSync(destFile);
        SafeFileUtils.closeSync(srcFile);
        
        logger.info(TAG, `封面已保存到相册: ${desFileUris[0]}`);
        this.getUIContext().getPromptAction().showToast({ message: '已保存到相册', duration: 2000 });
      } else {
        logger.info(TAG, '用户取消保存');
      }
      
    } catch (error) {
      logger.error(TAG, `保存封面失败: ${String(error)}`);
      this.getUIContext().getPromptAction().showToast({ message: `保存失败: ${String(error)}`, duration: 2000 });
    } finally {
      this.isSavingCover = false;
    }
  }
  
  /**
   * 分享封面
   * 使用系统 Share Kit API
   */
  private async shareCover(): Promise<void> {
    const coverUrl = this.getRawCoverImagePath();
    if (!coverUrl) {
      this.getUIContext().getPromptAction().showToast({ message: '无封面图片', duration: 2000 });
      return;
    }
    if (coverUrl.startsWith('app.media.')) {
      this.getUIContext().getPromptAction().showToast({ message: '内置资源封面暂不支持分享', duration: 2000 });
      return;
    }
    
    try {
      const context = (this.getUIContext().getHostContext() as common.UIAbilityContext) as common.UIAbilityContext;
      let localFilePath: string;
      
      // 判断是本地文件还是网络图片
      if (coverUrl.startsWith('http://') || coverUrl.startsWith('https://')) {
        // 网络图片：先下载到临时文件
        const httpRequest = http.createHttp();
        const response = await httpRequest.request(coverUrl, {
          method: http.RequestMethod.GET,
          expectDataType: http.HttpDataType.ARRAY_BUFFER
        });
        httpRequest.destroy();
        
        if (response.responseCode !== 200) {
          throw new Error(`下载失败: ${response.responseCode}`);
        }
        
        const imageData = response.result as ArrayBuffer;
        localFilePath = `${context.cacheDir}/share_cover_${Date.now()}.jpg`;
        const tempFile = SafeFileUtils.openSync(localFilePath, fs.OpenMode.CREATE | fs.OpenMode.WRITE_ONLY);
        SafeFileUtils.writeSync(tempFile.fd, imageData);
        SafeFileUtils.closeSync(tempFile);
      } else {
        // 本地文件：直接使用
        localFilePath = coverUrl.startsWith('file://') ? coverUrl.substring(7) : coverUrl;
      }
      
      // 转换为 URI
      const shareUri = fileUri.getUriFromPath(localFilePath);
      
      // 构建分享数据
      const shareData: systemShare.SharedData = new systemShare.SharedData({
        utd: utd.UniformDataType.JPEG,
        uri: shareUri,
        title: this.content?.title || '封面图片',
        description: `${this.content?.title || ''} - ${this.content?.author || ''}`
      });
      
      // 构建 ShareController
      const controller: systemShare.ShareController = new systemShare.ShareController(shareData);
      
      // 显示分享面板
      await controller.show(context, {
        previewMode: systemShare.SharePreviewMode.DETAIL,
        selectionMode: systemShare.SelectionMode.SINGLE
      });
      
      logger.info(TAG, '封面分享成功');
      
    } catch (error) {
      logger.error(TAG, `分享封面失败: ${String(error)}`);
      this.getUIContext().getPromptAction().showToast({ message: `分享失败: ${String(error)}`, duration: 2000 });
    }
  }

  // ==================== 横屏布局 ====================

  /**
   * 横屏布局 - 左侧面板
   * 包含：封面图片、标题/作者、标签、简介、书架按钮
   */
  @Builder
  buildLandscapeLeftPanel() {
    Scroll() {
      Column({ space: 16 }) {
        // 封面图片
        Stack() {
          if (this.coverPixelMap) {
            Image(this.coverPixelMap)
              .width('100%')
              .aspectRatio(COVER_WIDTH / COVER_HEIGHT)
              .objectFit(ImageFit.Cover)
              .borderRadius(12)
          } else if (this.hasCoverImageSource() && this.isNetworkCover()) {
            AvifImage({
              src: this.getCoverImageSource() as string,
              imageWidth: '100%',
              imageHeight: undefined,
              objectFit: ImageFit.Cover,
              imageBorderRadius: 12
            })
              .aspectRatio(COVER_WIDTH / COVER_HEIGHT)
          } else if (this.hasCoverImageSource()) {
            Image(this.getCoverImageSource())
              .width('100%')
              .aspectRatio(COVER_WIDTH / COVER_HEIGHT)
              .objectFit(ImageFit.Cover)
              .borderRadius(12)
          } else {
            Column() {
              SymbolGlyph($r('sys.symbol.book_open_fill'))
                .fontSize(48)
                .fontColor([ThemeAwareHelper.getTestManagementThemedColor('text_muted', this.themeState.currentTheme)])
            }
            .width('100%')
            .aspectRatio(COVER_WIDTH / COVER_HEIGHT)
            .backgroundColor(ThemeAwareHelper.getTestManagementThemedColor('comp_background_tertiary', this.themeState.currentTheme))
            .borderRadius(12)
            .justifyContent(FlexAlign.Center)
          }

          // 内容类型标签
          Text(this.getContentTypeName())
            .fontSize(10)
            .fontColor(Color.White)
            .backgroundColor('rgba(0,0,0,0.6)')
            .padding({ left: 6, right: 6, top: 2, bottom: 2 })
            .borderRadius(4)
            .position({ x: 8, y: 8 })

          if (LabelUtils.isTranslatedContent(this.getDisplayTitleText())) {
            Text('汉化')
              .fontSize(10)
              .fontColor(Color.White)
              .backgroundColor('#E6F44336')
              .padding({ left: 4, right: 4, top: 2, bottom: 2 })
              .borderRadius({ bottomLeft: 6, topRight: 8 })
              .position({ right: 0, top: 0 })
          }

          // 在线漫画封面刷新按钮
          if (this.isOnlineManga()) {
            Button() {
              if (this.isRefetchingCover) {
                LoadingProgress()
                  .width(16)
                  .height(16)
                  .color(Color.White)
              } else {
                SymbolGlyph($r('sys.symbol.arrow_clockwise'))
                  .fontSize(14)
                  .fontColor([Color.White])
              }
            }
            .width(28)
            .height(28)
            .backgroundColor('rgba(0,0,0,0.5)')
            .borderRadius(14)
            .position({ right: 4, bottom: 4 })
            .enabled(!this.isRefetchingCover)
            .onClick(() => this.refetchCoverImage())
          }
        }
        .id(`cover_${this.componentId}`)
        .width('100%')
        .onClick(() => this.openCoverPreview())

        // 标题和作者
        Column({ space: 6 }) {
          Text(this.stripHtmlTags(this.content?.title || '加载中...'))
            .fontSize(18)
            .fontWeight(FontWeight.Bold)
            .fontFamily(this.appFontFamily)
            .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_primary', this.themeState.currentTheme))
            .maxLines(2)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
            .onClick(() => {
              this.navigateToSearch(this.content?.title || '');
            })

          Text(this.stripHtmlTags(this.content?.author || (this.isOnlineEBookRecoveryInProgress ? '正在验证站点信息...' : '')))
            .fontSize(13)
            .fontFamily(this.appFontFamily)
            .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_secondary', this.themeState.currentTheme))
            .maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
            .width('100%')
            .onClick(() => {
              this.navigateToSearch(this.content?.author || '');
            })

          Row({ space: 8 }) {
            Text(this.getReadStatusText())
              .fontSize(12)
              .fontFamily(this.appFontFamily)
              .fontColor(ThemeAwareHelper.getTestManagementThemedColor('accent_primary', this.themeState.currentTheme))
              .maxLines(1)
              .textOverflow({ overflow: TextOverflow.Ellipsis })
              .layoutWeight(1)
            Text(`${this.content?.totalChapters || 0}章`)
              .fontSize(12)
              .fontFamily(this.appFontFamily)
              .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_muted', this.themeState.currentTheme))
          }
          .width('100%')

          if (this.getDisplaySourceName().length > 0) {
            Text(`来源: ${this.getDisplaySourceName()}`)
              .fontSize(12)
              .fontFamily(this.appFontFamily)
              .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_muted', this.themeState.currentTheme))
              .maxLines(1)
              .textOverflow({ overflow: TextOverflow.Ellipsis })
              .width('100%')
          }
        }
        .width('100%')
        .alignItems(HorizontalAlign.Start)

        // 标签区域
        if (this.content && ((this.content.genres && this.content.genres.length > 0) || (this.content.tags && this.content.tags.length > 0))) {
          Column({ space: 8 }) {
            Row({ space: 8 }) {
              Text('标签')
                .fontSize(13)
                .fontWeight(FontWeight.Medium)
                .fontFamily(this.appFontFamily)
                .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_primary', this.themeState.currentTheme))
            }
            .width('100%')

            Flex({ wrap: FlexWrap.Wrap, alignItems: ItemAlign.Center }) {
              ForEach(this.getTagChipItems(), (item: TagChipItem) => {
                this.buildTagChip(item, true);
              }, (item: TagChipItem) => `ls_${item.id}`)
            }
            .width('100%')
            .animation({ duration: 240, curve: Curve.EaseInOut })
          }
          .width('100%')
        }

        // 简介
        Column({ space: 6 }) {
          Text('简介')
            .fontSize(14)
            .fontWeight(FontWeight.Bold)
            .fontFamily(this.appFontFamily)
            .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_primary', this.themeState.currentTheme))

          Text(this.stripHtmlTags(this.content?.description || '暂无简介'))
            .fontSize(13)
            .fontFamily(this.appFontFamily)
            .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_secondary', this.themeState.currentTheme))
            .maxLines(this.showFullDescription ? undefined : 4)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
            .animation({ duration: 240, curve: Curve.EaseInOut })
            .copyOption(CopyOptions.InApp)
            .onTextSelectionChange((start: number, end: number) => {
              const fullText = this.stripHtmlTags(this.content?.description || '');
              if (start >= 0 && end > start) {
                this.descriptionSelectedText = fullText.substring(start, end);
              }
            })
            .bindSelectionMenu(TextSpanType.TEXT, this.buildDescriptionSelectionMenu, TextResponseType.LONG_PRESS, {
              onDisappear: () => { this.descriptionSelectedText = ''; }
            })

          if (this.content?.description && this.content.description.length > 80) {
            Text(this.showFullDescription ? '收起' : '展开')
              .fontSize(11)
              .fontFamily(this.appFontFamily)
              .fontColor(ThemeAwareHelper.getTestManagementThemedColor('accent_primary', this.themeState.currentTheme))
              .onClick(() => {
                this.toggleDescriptionExpanded();
              })
          }
        }
        .width('100%')
        .alignItems(HorizontalAlign.Start)

        // 书架按钮
        if (this.isFromChangeSource && this.originalBookInfo) {
          Button('替换原小说')
            .fontSize(13)
            .fontFamily(this.appFontFamily)
            .backgroundColor(ThemeAwareHelper.getTestManagementThemedColor('accent_orange', this.themeState.currentTheme))
            .fontColor(Color.White)
            .height(36)
            .width('100%')
            .borderRadius(18)
            .onClick(() => this.openReplaceBookDialog())
        } else {
          Button() {
            Row({ space: 6 }) {
              SymbolGlyph($r('sys.symbol.bookshelf'))
                .fontSize(13)
                .fontColor([this.isInShelf
                  ? ThemeAwareHelper.getTestManagementThemedColor('accent_green', this.themeState.currentTheme)
                  : ThemeAwareHelper.getTestManagementThemedColor('text_primary', this.themeState.currentTheme)])
              Text(this.getShelfButtonLabel())
                .fontSize(13)
                .fontFamily(this.appFontFamily)
                .fontColor(this.isInShelf
                  ? ThemeAwareHelper.getTestManagementThemedColor('accent_green', this.themeState.currentTheme)
                  : ThemeAwareHelper.getTestManagementThemedColor('text_primary', this.themeState.currentTheme))
                .maxLines(1)
                .textOverflow({ overflow: TextOverflow.Ellipsis })
            }
          }
            .backgroundColor(this.isInShelf
              ? ThemeAwareHelper.getTestManagementThemedColor('accent_green', this.themeState.currentTheme) + '20'
              : ThemeAwareHelper.getTestManagementThemedColor('comp_background_tertiary', this.themeState.currentTheme))
            .height(36)
            .width('100%')
            .borderRadius(18)
            .enabled(!this.isShelfActionPending)
            .onClick(() => this.showAddToShelfSelection())
        }

        // 同书架内容
        this.buildShelfContentSection()

        // 智能推荐
        this.buildRecommendationSection()

        Blank().height(16)
      }
      .width('100%')
      .padding(16)
    }
    .width('100%')
    .height('100%')
    .scrollBar(BarState.Off)
    .edgeEffect(EdgeEffect.Spring)
  }

  @Builder
  buildTrackingStatusSection() {
    if (this.content && !this.isCurrentLocalImportedContent() && this.trackingCardState !== null && this.trackingCardCallbacks !== null) {
      Stack({ alignContent: Alignment.TopStart }) {
        this.buildGlassSectionChrome()
        ContentTrackingStatusCard({
          state: this.trackingCardState,
          themeState: this.themeState,
          appFontFamily: this.appFontFamily,
          callbacks: this.trackingCardCallbacks
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

  /**
   * 横屏布局 - 右侧面板
   * 包含：工具栏、缓存状态卡片、章节列表，右下角浮动阅读按钮
   */
  @Builder
  buildLandscapeRightPanel() {
    Stack() {
      // 主内容区
      Column({ space: 12 }) {
        // 工具栏
        this.buildActionBar()

        // 内容跟踪
        this.buildTrackingStatusSection()

        // 听书缓存
        ReadAloudCacheDialogComponent({
          content: this.content,
          supportsReadAloudCache: this.supportsReadAloudCacheSection(),
          isCurrentNovelAudioSource: this.isCurrentNovelAudioSource(),
          isLocalTxtNovelEBook: this.isLocalTxtNovelEBookContent(),
          loadSignal: this.readAloudCacheLoadSignal,
          onOpenCacheDialog: (trigger: string) => {
            this.openCacheDialogFromDetail(trigger);
          },
          onSummaryChanged: (summary: RemoteReadAloudCacheBookSummary | null) => {
            this.readAloudCacheSummary = summary;
          }
        })

        // 缓存状态卡片
        this.buildCacheStatusCard()

        // 章节列表（占满剩余空间）
        Column() {
          this.buildChapterList()
        }
        .layoutWeight(this.isChapterListExpanded ? 1 : 0)
        .animation({ duration: 300, curve: Curve.EaseInOut })
      }
      .width('100%')
      .height('100%')
      .padding({ left: 8, right: 16, top: 16, bottom: 16 })

      // 右下角浮动阅读按钮组
      Column({ space: 10 }) {
        Button() {
          Row({ space: 6 }) {
            if (this.isReadActionBusy()) {
              LoadingProgress()
                .width(14)
                .height(14)
                .color(Color.White)
            } else {
              SymbolGlyph($r('sys.symbol.book_open_fill'))
                .fontSize(14)
                .fontColor([Color.White])
            }
            Text(this.getReadButtonLabel())
              .fontSize(14)
              .fontFamily(this.appFontFamily)
              .fontColor(Color.White)
          }
        }
          .backgroundColor(ThemeAwareHelper.getTestManagementThemedColor('accent_primary', this.themeState.currentTheme))
          .height(44)
          .padding({ left: 24, right: 24 })
          .borderRadius(22)
          .shadow({
            radius: 12,
            color: 'rgba(0,0,0,0.15)',
            offsetX: 0,
            offsetY: 4
          })
          .enabled(!this.isReadActionBusy())
          .onClick(() => this.continueReading())

        if (this.canShowReadAloudButton()) {
          Button() {
            Row({ space: 6 }) {
              SymbolGlyph($r('sys.symbol.speaker'))
                .fontSize(13)
                .fontColor([Color.White])
              Text(this.getReadAloudButtonLabel())
                .fontSize(13)
                .fontFamily(this.appFontFamily)
                .fontColor(Color.White)
            }
          }
            .linearGradient({
              angle: 135,
              colors: [
                ['#00C2FF', 0],
                ['#4B7BFF', 0.55],
                ['#7A5CFF', 1]
              ]
            })
            .height(40)
            .padding({ left: 20, right: 20 })
            .borderRadius(20)
            .onClick(() => this.continueReadAloud())
        }
      }
      .position({ right: 24, bottom: 24 })
    }
    .width('100%')
    .height('100%')
  }

  /**
   * 横屏布局 - 主容器
   * 左侧封面信息 + 右侧章节列表
   */
  @Builder
  buildLandscapeLayout() {
    Row() {
      // 左侧面板（封面、标签、简介、书架按钮）
      Column() {
        this.buildLandscapeLeftPanel()
      }
      .width('38%')
      .height('100%')
      .backgroundColor(ThemeAwareHelper.getTestManagementThemedColor('panel_background', this.themeState.currentTheme) + '80')
      .borderRadius({ topRight: 16, bottomRight: 16 })

      // 右侧面板（工具栏、章节列表、阅读按钮）
      Column() {
        this.buildLandscapeRightPanel()
      }
      .layoutWeight(1)
      .height('100%')
    }
    .width('100%')
    .height('100%')
  }

  build() {
    NavDestination() {
      Stack() {
        // 隐藏的WebView用于执行在线电子书脚本
        Web({ src: 'about:blank', controller: this.webViewController })
          .width(1)
          .height(1)
          .opacity(0)
          .position({ x: 0, y: 0 })
          .zIndex(-1)
          .onControllerAttached(() => {
            logger.info(TAG, '隐藏WebView控制器已附加');
            this.webViewControllerAttached = true;
            try {
              this.webViewManager.setGlobalWebViewController(this.webViewController);
            } catch (error) {
              logger.warn(TAG, `设置全局WebView控制器失败: ${String(error)}`);
            }
            if (this.pendingInitialContentLoad || !this.initialContentLoadTriggered) {
              this.triggerInitialContentLoadIfReady();
            }
          })
          .onPageBegin((event) => {
            const sourceIdText: string = this.normalizeTrackingText(this.pageParams?.sourceId || this.content?.sourceId);
            const numericSourceId: number = Number(sourceIdText);
            logger.debug(TAG, `隐藏WebView页面开始加载: ${event.url}`);
            if (numericSourceId > 0) {
              void this.webViewAuthManager.applyCookiesToController(numericSourceId, this.webViewController);
            }
          })
          .onPageEnd((event) => {
            const sourceIdText: string = this.normalizeTrackingText(this.pageParams?.sourceId || this.content?.sourceId);
            const numericSourceId: number = Number(sourceIdText);
            logger.debug(TAG, `隐藏WebView页面加载完成: ${event.url}`);
            if (numericSourceId > 0) {
              void this.webViewAuthManager.captureCookiesFromController(numericSourceId, this.webViewController);
            }
          })
        
        // 背景层：封面图片毛玻璃效果
        Stack() {
          // 默认背景色（防止闪烁）
          Column()
            .width('100%')
            .height('100%')
            .backgroundColor(this.themeState.currentTheme === ThemeType.DARK ? '#1A1A1A' : '#F5F5F5')
            .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.TOP, SafeAreaEdge.BOTTOM])
          
          // 封面图片作为背景（优先使用 PixelMap）
          if (this.coverPixelMap) {
            Image(this.coverPixelMap)
              .width('100%')
              .height('100%')
              .objectFit(ImageFit.Cover)
              .blur(30)
              .opacity(0.5)
              .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.TOP, SafeAreaEdge.BOTTOM])
              .transition({ type: TransitionType.Insert, opacity: 0 })
              .animation({ duration: 300, curve: Curve.EaseOut })
          } else if (this.hasCoverImageSource() && this.isNetworkCover()) {
            AvifImage({
              src: this.getCoverImageSource() as string,
              imageWidth: '100%',
              imageHeight: '100%',
              objectFit: ImageFit.Cover
            })
              .blur(30)
              .opacity(0.5)
              .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.TOP, SafeAreaEdge.BOTTOM])
              .transition({ type: TransitionType.Insert, opacity: 0 })
              .animation({ duration: 300, curve: Curve.EaseOut })
          } else if (this.hasCoverImageSource()) {
            Image(this.getCoverImageSource())
              .width('100%')
              .height('100%')
              .objectFit(ImageFit.Cover)
              .blur(30)
              .opacity(0.5)
              .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.TOP, SafeAreaEdge.BOTTOM])
              .transition({ type: TransitionType.Insert, opacity: 0 })
              .animation({ duration: 300, curve: Curve.EaseOut })
          }
          // 渐变遮罩
          Column()
            .width('100%')
            .height('100%')
            .linearGradient({
              direction: GradientDirection.Bottom,
              colors: [
                [this.themeState.currentTheme === ThemeType.DARK ? 'rgba(26,26,26,0.2)' : 'rgba(245,245,245,0.2)', 0],
                [this.themeState.currentTheme === ThemeType.DARK ? 'rgba(26,26,26,0.7)' : 'rgba(245,245,245,0.7)', 0.3],
                [this.themeState.currentTheme === ThemeType.DARK ? '#1A1A1A' : '#F5F5F5', 0.6]
              ]
            })
            .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.TOP, SafeAreaEdge.BOTTOM])
        }
        .width('100%')
        .height('100%')
        .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.TOP, SafeAreaEdge.BOTTOM])

        Column() {
          if (this.errorMessage && !this.hasRenderablePrimaryContent()) {
            this.buildErrorView()
          } else if (this.responsive_isLandscape) {
            // 横屏布局：左侧封面信息 + 右侧章节列表
            this.buildLandscapeLayout()
          } else {
            // 竖屏布局：垂直滚动
            Refresh({ refreshing: $$this.isRefreshing }) {
              Scroll(this.scroller) {
                Column({ space: 16 }) {
                  // 刷新进度提示
                  if (this.refreshProgress) {
                    Text(this.refreshProgress)
                      .fontSize(12)
                      .fontColor(this.themeState.currentTheme === ThemeType.DARK ? '#AAAAAA' : '#666666')
                      .padding({ top: 8, bottom: 8 })
                  }
                  
                  this.buildHeader()
                  this.buildDescription()
                  this.buildActionBar()
                  this.buildTrackingStatusSection()
                  ReadAloudCacheDialogComponent({
                    content: this.content,
                    supportsReadAloudCache: this.supportsReadAloudCacheSection(),
                    isCurrentNovelAudioSource: this.isCurrentNovelAudioSource(),
                    isLocalTxtNovelEBook: this.isLocalTxtNovelEBookContent(),
                    loadSignal: this.readAloudCacheLoadSignal,
                    onOpenCacheDialog: (trigger: string) => {
                      this.openCacheDialogFromDetail(trigger);
                    },
                    onSummaryChanged: (summary: RemoteReadAloudCacheBookSummary | null) => {
                      this.readAloudCacheSummary = summary;
                    }
                  })
                  this.buildCacheStatusCard()
                  this.buildShelfContentSection()
                  this.buildRecommendationSection()
                  this.buildChapterList()

                  Blank().height(40)
                }
                .width('100%')
                .constraintSize({ maxWidth: this.responsive_maxContentWidth })
                .padding({ left: this.responsive_contentPadding, right: this.responsive_contentPadding, bottom: 40 })
              }
              .width('100%')
              .height('100%')
              .align(Alignment.TopStart)
              .scrollBar(BarState.Off)
              .edgeEffect(EdgeEffect.Spring)
            }
            .onRefreshing(() => {
              this.onRefresh();
            })
            .width('100%')
            .height('100%')
          }
        }
        .width('100%')
        .height('100%')
        .id('' as string)
        .padding({ top: this.statusBarHeight })
        
        // 封面预览弹窗
        if (this.showCoverPreview && this.content?.coverUrl) {
          this.buildCoverPreviewOverlay()
        }
        
        // 生成封面对话框
        this.buildGenerateCoverDialog()
        
        // 下载章节选择对话框
        DownloadDialogComponent({
          content: this.content,
          themeState: this.themeState,
          loadSignal: this.downloadDialogLoadSignal,
          isDownloading: this.isDownloading,
          downloadProgressCurrent: this.downloadProgressCurrent,
          downloadProgressTotal: this.downloadProgressTotal,
          downloadCurrentChapterTitle: this.downloadCurrentChapterTitle,
          onStartDownload: (selectedIndexes: number[]) => {
            this.executeDownloadWithIndexes(selectedIndexes);
          },
          onClearCache: (contentType: string) => {
            if (contentType === 'novel') {
              this.showNovelCacheClearConfirm();
            } else {
              this.showMangaCacheClearConfirm();
            }
          },
          isChapterFullyCached: (chapterId: string) => this.isChapterFullyCached(chapterId),
          isChapterPartiallyCached: (chapterId: string) => this.isChapterPartiallyCached(chapterId),
          getNovelCacheActionTitle: () => this.getNovelCacheActionTitle(),
          getNovelDownloadedTagLabel: () => this.getNovelDownloadedTagLabel(),
          getNovelCacheCountActionLabel: (count: number) => this.getNovelCacheCountActionLabel(count),
          isCurrentNovelAudioSource: () => this.isCurrentNovelAudioSource()
        })

        // 分享链接对话框
        ShareLinkDialogComponent({
          content: this.content,
          displaySourceName: this.getDisplaySourceName(),
          themeState: this.themeState,
          loadSignal: this.shareDialogLoadSignal
        })

        // 小说设置对话框
        NovelSettingsDialogComponent({
          content: this.content,
          themeState: this.themeState,
          pageParams: this.pageParams,
          loadSignal: this.novelSettingsLoadSignal,
          onNavigate: (pageName: string, params: object | null) => {
            this.navigateWithManagedWindowTransition(pageName, params);
          },
          isLocalImportedEBookContent: () => this.isLocalImportedEBookContent(),
          getNovelCacheBookId: (sourceId: string, bookUrl: string) => this.getNovelCacheBookId(sourceId, bookUrl),
          loadNovelContent: async () => {
            await this.loadNovelContent();
          },
          onContentUpdated: (content: UnifiedContent) => {
            this.content = content;
            this.coverRefreshKey = Date.now();
          },
          onCoverChanged: (bookId: string, coverPath: string) => {
            eventBus.publish(GameEvent.EBOOK_COVER_CHANGED, { bookId, coverPath });
          },
          onChaptersReloaded: () => {
            this.isChaptersLoading = false;
          }
        })

        // 内容跟踪设置对话框
        TrackingSettingsDialogComponent({
          content: this.content,
          themeState: this.themeState,
          loadSignal: this.trackingLoadSignal,
          onNavigate: (pageName: string, params: object | null) => {
            this.navigateWithManagedWindowTransition(pageName, params);
          },
          getCurrentNovelSourceId: () => this.getCurrentNovelSourceId(),
          isCurrentLocalImportedContent: () => this.isCurrentLocalImportedContent(),
          isLocalImportedEBookContent: () => this.isLocalImportedEBookContent(),
          getNovelCacheBookId: (sourceId: string, bookUrl: string) => this.getNovelCacheBookId(sourceId, bookUrl),
          onTrackingStateChanged: (state: ContentTrackingCardState, callbacks: ContentTrackingCardCallbacks) => {
            this.trackingCardState = state;
            this.trackingCardCallbacks = callbacks;
          }
        })
        
        // 换源对话框
        ChangeSourceDialogComponent({
          content: this.content,
          themeState: this.themeState,
          loadSignal: this.changeSourceDialogLoadSignal,
          currentSourceId: this.pageParams?.sourceId || '',
          onSourceSelected: (source: NovelSearchResult) => {
            this.changeNovelSource(source);
          }
        })
        
        // 添加书架选择对话框
        this.buildAddToShelfDialog()
        
        // 替换小说对话框
        this.buildReplaceBookDialog()

        this.buildReplaceBookDialog()
        this.buildCacheConfirmDialog()

        // 重复检测弹窗
        this.buildDuplicateDetectionDialog()
 
        if (this.appGuideStep) {

          AppGuideOverlay({
            visible: this.appGuideStep !== null,
            title: this.appGuideStep.title,
            message: this.appGuideStep.message,
            progressText: this.appGuideManager.getCurrentProgressText(),
            nextButtonText: this.appGuideStep.nextButtonText ?? '下一步',
            cardPosition: this.appGuideStep.cardPosition,
            highlightRect: this.appGuideHighlightRect,
            showSkip: this.appGuideStep.showSkip !== false,
            themeState: this.themeState,
            onNext: () => {
              this.handlePageGuideNext();
            },
            onSkip: () => {
              this.handlePageGuideSkip();
            }
          })
        }

      }
      .width('100%')
      .height('100%')
    }
    .hideTitleBar(true)
    .onReady((context: NavDestinationContext) => {
      this.pathStack = context.pathStack;
      const params = context.pathInfo?.param as UnifiedDetailPageParams;
      if (params) {
        this.pageParams = params;
        this.localCoverPath = params.cachedCoverPath || '';
        this.pendingInitialContentLoad = false;
        this.initialContentLoadTriggered = false;
        this.triggerInitialContentLoadIfReady();
      }
      setTimeout(() => {
        void this.refreshPageGuide('onReady');
      }, 80);
    })
    .onShown(() => {
      this.applyPageDisplayMode(DisplayMode.STATUS_SAFE_BOTTOM_IMMERSIVE);
      this.isOpeningOnlineEBookDownloadDetail = false;
      if (this.refreshProgress === '正在准备下载信息...') {
        this.refreshProgress = '';
      }
      if (!this.isOnlineEBookRecoveryInProgress) {
        this.isLoadingRecommendations = false;
        this.isLoadingShelfContent = false;
      }
      // 页面显示时刷新阅读记录（从阅读器返回时）
      this.refreshReadingProgress();
      this.readAloudCacheLoadSignal++;
      void this.refreshPageGuide('onShown');
    })
    .backgroundColor(Color.Transparent)
  }
  
  /**
   * 刷新阅读进度（页面返回时调用）
   */
  private async refreshReadingProgress(): Promise<void> {
    if (!this.content || !this.pageParams) return;
    
    try {
      logger.info(TAG, `刷新阅读进度: ${this.content.contentType}`);
      
      switch (this.content.contentType) {
        case UnifiedContentType.MANGA:
          await this.refreshMangaReadingProgress();
          break;
        case UnifiedContentType.EBOOK:
          await this.refreshEBookReadingProgress();
          break;
        case UnifiedContentType.NOVEL:
          await this.refreshNovelReadingProgress();
          break;
      }
      this.normalizeCurrentContentReadProgress();
    } catch (error) {
      logger.error(TAG, `刷新阅读进度失败: ${String(error)}`);
    }
  }
  
  /**
   * 刷新漫画阅读进度
   */
  private async refreshMangaReadingProgress(): Promise<void> {
    if (!this.content) return;
    
    const mangaId = this.content.id;
    const isOnline = this.content.sourceId !== undefined && Number(this.content.sourceId) > 0;
    const chapters = this.content.chapters.map(ch => {
      const originalChapter = MangaAdapter.getOriginalChapter(ch);
      return originalChapter as MangaChapter;
    }).filter(ch => ch !== null);
    
    if (chapters.length === 0) return;
    
    // 重新加载章节进度
    const progressData = await this.mangaDetailLoader.loadChapterProgressData(mangaId, chapters, isOnline);
    
    // 更新章节进度Map
    const newProgressMap = new Map<string, ChapterProgressInfo>();
    progressData.progressList.forEach((progress: ChapterProgressInfo) => {
      newProgressMap.set(progress.chapterId, progress);
    });
    this.chapterProgressMap = newProgressMap;
    
    // 更新章节已读状态
    const updatedChapters: UnifiedChapter[] = [];
    for (let i = 0; i < this.content.chapters.length; i++) {
      const ch = this.content.chapters[i];
      const isRead = progressData.readChapterIds.has(ch.id);
      const updatedChapter: UnifiedChapter = {
        id: ch.id,
        title: ch.title,
        index: ch.index,
        isRead: isRead,
        isDownloaded: ch.isDownloaded,
        isBookmarked: ch.isBookmarked,
        pageCount: ch.pageCount,
        publishDate: ch.publishDate,
        originalData: ch.originalData,
        originalType: ch.originalType
      };
      updatedChapters.push(updatedChapter);
    }
    
    // 更新content（显式赋值而不是spread）
    this.content.chapters = updatedChapters;
    this.content.readChapters = progressData.readChapterIds.size;
    this.content.lastReadChapterIndex = progressData.lastReadChapterIndex;
    this.content.readProgress = this.content.totalChapters > 0 
      ? Math.round((progressData.readChapterIds.size / this.content.totalChapters) * 100) 
      : 0;
    
    logger.info(TAG, `漫画阅读进度已刷新: 已读${progressData.readChapterIds.size}章`);
  }
  
  /**
   * 刷新电子书阅读进度
   */
  private async refreshEBookReadingProgress(): Promise<void> {
    if (!this.content) return;
    
    try {
      const ebook: EBook | null = await this.ebookDataManager.getEBookById(this.content.id);
      if (ebook) {
        const rawChapterIndex: number = ebook.readingProgress?.currentChapterIndex || 0;
        const chapterCount = ebook.chapters?.length || 0;
        const currentChapterIndex: number = chapterCount > 0
          ? Math.max(0, Math.min(rawChapterIndex, chapterCount - 1))
          : 0;
        const progress: number = ebook.readingProgress?.progress || 0;
        
        this.content.lastReadChapterIndex = currentChapterIndex;
        this.content.lastReadChapterTitle = currentChapterIndex < (ebook.chapters?.length || 0) 
          ? ebook.chapters![currentChapterIndex].title 
          : '';
        this.content.originalData = ebook;
        this.content.originalType = UnifiedContentType.EBOOK;
        this.content.readProgress = Math.round(progress);
        this.normalizeCurrentContentReadProgress();
        
        logger.info(TAG, `电子书阅读进度已刷新: 章节${currentChapterIndex}, 进度${this.content.readProgress}%`);
      }
    } catch (error) {
      logger.error(TAG, `刷新电子书阅读进度失败: ${String(error)}`);
    }
  }
  
  /**
   * 刷新小说阅读进度
   */
  private async refreshNovelReadingProgress(): Promise<void> {
    if (!this.content) return;

    try {
      const novelBook: NovelBook | null = await this.novelDataManager.getBookByUrl(
        this.content.sourceId || '',
        this.content.id
      );

      if (novelBook) {
        const maxChapterIndex = Math.max(-1, this.content.totalChapters - 1);
        const rawLastChapterIndex = novelBook.lastReadChapterIndex ?? -1;
        const lastChapterIndex = Math.max(-1, Math.min(rawLastChapterIndex, maxChapterIndex));
        const readChapters = lastChapterIndex >= 0 ? (lastChapterIndex + 1) : 0;

        let readProgress = this.content.totalChapters > 0
          ? Math.round((readChapters / this.content.totalChapters) * 100)
          : 0;
        const progressData = await this.novelDataManager.getReadProgress(novelBook.id);
        if (progressData) {
          const preciseProgress = Math.round(progressData.progress);
          if (preciseProgress > readProgress) {
            readProgress = preciseProgress;
          }
        }

        this.content.lastReadChapterIndex = lastChapterIndex;
        this.content.readChapters = readChapters;
        this.content.readProgress = readProgress;
        this.normalizeCurrentContentReadProgress();

        logger.info(TAG, `小说阅读进度已刷新: 章节${lastChapterIndex}, 进度${this.content.readProgress}%`);
      }
    } catch (error) {
      logger.error(TAG, `刷新小说阅读进度失败: ${String(error)}`);
    }
  }
  
  /**
   * 显示生成封面提示对话框
   */
  private showGenerateCoverPrompt(): void {
    this.generateCoverDialogLoadSignal++;
  }
  
  /**
   * 生成封面
   */
  private async generateCoverForContent(title: string, fontScale: number): Promise<void> {
    if (!this.content || !title.trim()) {
      this.getUIContext().getPromptAction().showToast({ message: '请输入标题', duration: 2000 });
      return;
    }

    this.isGeneratingCover = true;

    try {
      logger.info(TAG, `开始生成封面: ${title}`);

      const coverPath = await this.coverGenerator.generateCover(
        this.content.id,
        title,
        () => { this.buildCoverForSnapshot(title, fontScale); },
        this.getUIContext()
      );
      
      if (coverPath) {
        await this.updateContentCover(coverPath);
        // 强制刷新封面显示
        this.coverRefreshKey = Date.now();
        this.getUIContext().getPromptAction().showToast({ message: '封面生成成功', duration: 2000 });
        logger.info(TAG, `封面生成成功: ${coverPath}`);
      } else {
        this.getUIContext().getPromptAction().showToast({ message: '封面生成失败', duration: 2000 });
        logger.warn(TAG, '封面生成失败');
      }
    } catch (error) {
      logger.error(TAG, `生成封面异常: ${String(error)}`);
      this.getUIContext().getPromptAction().showToast({ message: `生成失败: ${String(error)}`, duration: 2000 });
    } finally {
      this.isGeneratingCover = false;
    }
  }
  
  /**
   * 更新内容封面
   */
  private async updateContentCover(coverPath: string): Promise<void> {
    if (!this.content) return;
    
    try {
      if (this.content.contentType === UnifiedContentType.EBOOK) {
        await this.ebookDataManager.updateEBookCover(this.content.id, coverPath);
        this.content.coverUrl = coverPath;
        logger.info(TAG, '电子书封面已更新');
        // 发送事件通知书库页面刷新
        const ebookPayload: CoverChangedPayload = { 
          bookId: this.content.id, 
          coverPath: coverPath 
        };
        eventBus.publish(GameEvent.EBOOK_COVER_CHANGED, ebookPayload);
      } else if (this.content.contentType === UnifiedContentType.NOVEL) {
        const novel = await this.novelDataManager.getBookByUrl(
          this.content.sourceId || '',
          this.content.id
        );
        if (novel) {
          // 本地生成的封面应该存储在coverLocalPath字段
          novel.coverLocalPath = coverPath;
          await this.novelDataManager.saveBook(novel);
          this.content.coverUrl = coverPath;
          logger.info(TAG, '小说封面已更新');
          // 发送事件通知书库页面刷新
          const novelPayload: CoverChangedPayload = { 
            bookId: this.content.id, 
            coverPath: coverPath 
          };
          eventBus.publish(GameEvent.NOVEL_COVER_CHANGED, novelPayload);
        }
      }
    } catch (error) {
      logger.error(TAG, `更新封面失败: ${String(error)}`);
      throw error as Error;
    }
  }
  
  /**
   * 构建封面组件（用于componentSnapshot）
   */
  @Builder
  buildCoverForSnapshot(title: string, fontScale: number = 1.0) {
    Stack() {
      Image($r('app.media.ebook'))
        .width(COVER_WIDTH)
        .height(COVER_HEIGHT)
        .objectFit(ImageFit.Cover)

      Text(this.formatCoverTitle(title))
        .fontFamily(this.appFontFamily)
        .fontSize(this.calculateCoverFontSize(title, fontScale))
        .fontWeight(FontWeight.Bold)
        .fontColor('#1a1a1a')
        .textAlign(TextAlign.Center)
        .maxLines(2)
        .textOverflow({ overflow: TextOverflow.Ellipsis })
        .lineHeight(this.calculateCoverFontSize(title, fontScale) * 1.3)
        .width(COVER_WIDTH * (UnifiedDetailPage.TITLE_AREA_RIGHT_PERCENT - UnifiedDetailPage.TITLE_AREA_LEFT_PERCENT) - 24)
        .constraintSize({
          maxHeight: COVER_HEIGHT * (UnifiedDetailPage.TITLE_AREA_BOTTOM_PERCENT - UnifiedDetailPage.TITLE_AREA_TOP_PERCENT) - 20
        })
        .position({
          x: COVER_WIDTH * UnifiedDetailPage.TITLE_AREA_LEFT_PERCENT + 12,
          y: COVER_HEIGHT * (UnifiedDetailPage.TITLE_AREA_TOP_PERCENT + UnifiedDetailPage.TITLE_AREA_BOTTOM_PERCENT) / 2 - this.calculateCoverFontSize(title, fontScale) * 0.65
        })
    }
    .width(COVER_WIDTH)
    .height(COVER_HEIGHT)
  }
  
  /**
   * 格式化封面标题
   */
  private formatCoverTitle(title: string): string {
    let cleanTitle = title.replace(/\.(txt|epub|pdf|mobi|azw3?)$/i, '');
    if (cleanTitle.length > 20) {
      cleanTitle = cleanTitle.substring(0, 17) + '...';
    }
    return cleanTitle;
  }
  
  /**
   * 计算封面字体大小
   */
  private calculateCoverFontSize(title: string, fontScale: number = 1.0): number {
    const length = title.length;
    let baseSize = 24;
    if (length <= 2) baseSize = 70;
    else if (length <= 4) baseSize = 56;
    else if (length <= 6) baseSize = 48;
    else if (length <= 8) baseSize = 36;
    else if (length <= 12) baseSize = 32;
    else if (length <= 16) baseSize = 28;

    return baseSize * fontScale;
  }
  

  /**
   * 切换小说书源
   */
  private async changeNovelSource(source: NovelSearchResult): Promise<void> {
    if (!this.content) return;
    
    logger.info(TAG, `切换书源: ${source.sourceName}`);
    
    // 保存原书信息（只要进行了换源操作，就允许替换）
    let originalInfo: OriginalBookInfo | null = null;
    let originalShelfId: string = '';  // 原书所在的书架ID
    if (this.content.contentType === UnifiedContentType.NOVEL) {
      // 获取原书的详细信息（尝试多种方式查询）
      const sourceId = this.content.sourceId || this.pageParams?.sourceId || '';
      let bookInDb = await this.novelDataManager.getBookByUrl(sourceId, this.content.id);
      
      // 如果找不到，尝试用构建ID查询
      if (!bookInDb) {
        const constructedId = this.getNovelCacheBookId(sourceId, this.content.id);
        bookInDb = await this.novelDataManager.getBook(constructedId);
        logger.info(TAG, `通过构建ID查询原书: ${constructedId}, 结果: ${bookInDb ? '找到' : '未找到'}`);
      }
      
      // 查找原书所在的书架
      if (bookInDb) {
        const allShelves = this.typeShelfManager.getShelves();
        // 使用完整的novel.id格式查找（${sourceId}_${bookUrl}）
        const originalBookId = bookInDb.id;
        for (const shelf of allShelves) {
          if (shelf.isSystem) continue;
          const itemIds = this.typeShelfManager.getShelfItemIdsByType(shelf.id, ContentType.NOVEL);
          if (itemIds.includes(originalBookId)) {
            originalShelfId = shelf.id;
            logger.info(TAG, `原书在书架: ${shelf.name} (${shelf.id}), bookId=${originalBookId}`);
            break;
          }
        }
      }
      
      // 获取原书最后阅读章节标题
      let lastReadChapterTitle = '';
      if (this.content.lastReadChapterIndex >= 0 && this.content.lastReadChapterIndex < this.content.chapters.length) {
        lastReadChapterTitle = this.content.chapters[this.content.lastReadChapterIndex].title;
      }
      
      originalInfo = {
        bookId: bookInDb?.id || '',
        bookUrl: this.content.id,
        sourceId: sourceId,
        sourceName: this.getDisplaySourceName(),
        name: this.content.title,
        author: this.content.author,
        coverUrl: this.content.coverUrl,
        lastReadChapterIndex: bookInDb?.lastReadChapterIndex ?? this.content.lastReadChapterIndex,
        lastReadChapterTitle: lastReadChapterTitle,
        lastReadPosition: bookInDb?.lastReadPosition || 0,
        chapterCount: this.content.totalChapters,
        isFavorite: bookInDb?.isFavorite || this.isFavorite,
        shelfId: originalShelfId  // 保存原书所在书架
      };
      logger.info(TAG, `保存原书信息: ${originalInfo.name}, 阅读至第${originalInfo.lastReadChapterIndex}章, 原书收藏状态=${originalInfo.isFavorite}, 书架ID=${originalShelfId}`);
    }
    
    // 显示加载状态
    this.isLoading = true;
    
    try {
      // 设置换源标记和原书信息
      this.isFromChangeSource = originalInfo !== null;
      this.originalBookInfo = originalInfo;
      
      // 更新页面参数
      if (this.pageParams) {
        this.pageParams.sourceId = source.sourceId;
        this.pageParams.contentId = source.bookUrl;
        this.pageParams.isFromChangeSource = this.isFromChangeSource;
        this.pageParams.originalBookInfo = originalInfo || undefined;
      }
      
      // 重新加载内容
      await this.loadContent();
      
      if (this.isFromChangeSource) {
        this.getUIContext().getPromptAction().showToast({ message: `已切换到: ${source.sourceName}，点“替换原小说”按钮进行替换` });
      } else {
        this.getUIContext().getPromptAction().showToast({ message: `已切换到: ${source.sourceName}` });
      }
    } catch (error) {
      logger.error(TAG, `切换书源失败: ${String(error)}`);
      this.getUIContext().getPromptAction().showToast({ message: '切换失败，请重试' });
      // 失败时重置换源标记
      this.isFromChangeSource = false;
      this.originalBookInfo = null;
    } finally {
      this.isLoading = false;
    }
  }
  
  /**
   * 打开替换小说对话框
   */
  private openReplaceBookDialog(): void {
    if (!this.content || !this.originalBookInfo) return;

    // 计算章节匹配
    this.matchedChapterIndex = this.findMatchingChapterIndex(
      this.originalBookInfo.lastReadChapterTitle,
      this.originalBookInfo.lastReadChapterIndex
    );

    logger.info(TAG, `打开替换对话框: 原章节=${this.originalBookInfo.lastReadChapterIndex}, 匹配章节=${this.matchedChapterIndex}`);

    // 显示对话框
    this.replaceBookDialogLoadSignal++;
  }
  
  /**
   * 章节匹配算法
   * 根据原书的阅读位置在新书中找到对应章节
   */
  private findMatchingChapterIndex(originalChapterTitle: string, originalChapterIndex: number): number {
    if (!this.content || this.content.chapters.length === 0) {
      return -1;
    }
    
    // 1. 精确匹配：章节标题完全相同
    for (let i = 0; i < this.content.chapters.length; i++) {
      if (this.content.chapters[i].title === originalChapterTitle) {
        logger.info(TAG, `精确匹配章节: "${originalChapterTitle}" -> 第${i}章`);
        return i;
      }
    }
    
    // 2. 模糊匹配：章节标题包含关系
    const normalizedOriginal = this.normalizeChapterTitle(originalChapterTitle);
    for (let i = 0; i < this.content.chapters.length; i++) {
      const normalizedNew = this.normalizeChapterTitle(this.content.chapters[i].title);
      if (normalizedOriginal === normalizedNew ||
          normalizedNew.includes(normalizedOriginal) ||
          normalizedOriginal.includes(normalizedNew)) {
        logger.info(TAG, `模糊匹配章节: "${originalChapterTitle}" -> "${this.content.chapters[i].title}" (第${i}章)`);
        return i;
      }
    }
    
    // 3. 序号回退：使用相同索引或最近的索引
    if (originalChapterIndex >= 0) {
      if (originalChapterIndex < this.content.chapters.length) {
        logger.info(TAG, `序号回退匹配: 第${originalChapterIndex}章`);
        return originalChapterIndex;
      }
      // 如果原索引超出范围，返回最后一章
      logger.info(TAG, `序号回退匹配(超出范围): 第${this.content.chapters.length - 1}章`);
      return this.content.chapters.length - 1;
    }
    
    return -1;
  }
  
  /**
   * 标准化章节标题（用于模糊匹配）
   */
  private normalizeChapterTitle(title: string): string {
    return title
      .replace(/\s+/g, '')  // 移除空白
      .replace(/[，。！？、：；“”‘’【】《》「」『』—…]/g, '')  // 移除中文标点
      .replace(/[,.!?;:"'\[\]<>\-\.]/g, '')  // 移除英文标点
      .toLowerCase();
  }
  
  /**
   * 执行替换小说
   */
  private async executeReplaceBook(): Promise<void> {
    if (!this.content || !this.originalBookInfo) return;

    this.isLoading = true;
    
    try {
      const originalInfo = this.originalBookInfo;
      const newSourceId = this.content.sourceId || this.pageParams?.sourceId || '';
      const newBookUrl = this.content.id;
      
      logger.info(TAG, `开始替换小说: ${originalInfo.name} -> ${this.content.title}`);
      logger.info(TAG, `新书源信息: sourceId=${newSourceId}, bookUrl=${newBookUrl}`);
      
      // 1. 获取新书信息（尝试多种方式查询）
      let newBookInDb = await this.novelDataManager.getBookByUrl(newSourceId, newBookUrl);
      
      // 如果找不到，尝试用构建ID查询
      if (!newBookInDb) {
        const constructedId = this.getNovelCacheBookId(newSourceId, newBookUrl);
        newBookInDb = await this.novelDataManager.getBook(constructedId);
        logger.info(TAG, `通过构建ID查询: ${constructedId}, 结果: ${newBookInDb ? '找到' : '未找到'}`);
      }
      
      // 2. 计算新的阅读位置
      const newLastReadIndex = this.matchedChapterIndex >= 0 ? this.matchedChapterIndex : 0;
      const newLastReadChapterId = newLastReadIndex < this.content.chapters.length 
        ? this.content.chapters[newLastReadIndex].id 
        : '';
      
      // 3. 更新或创建新书的收藏状态和阅读进度
      if (newBookInDb) {
        // 更新现有记录
        newBookInDb.isFavorite = true;
        newBookInDb.lastReadChapterIndex = newLastReadIndex;
        newBookInDb.lastReadChapterId = newLastReadChapterId;
        newBookInDb.lastReadPosition = 0;  // 重置位置，从章节开头开始
        newBookInDb.lastReadTime = Date.now();
        newBookInDb.readStatus = originalInfo.lastReadChapterIndex >= 0 ? NovelReadStatus.READING : NovelReadStatus.UNREAD;
        await this.novelDataManager.saveBook(newBookInDb);
        logger.info(TAG, `新书已更新: isFavorite=true, lastReadIndex=${newLastReadIndex}`);
      } else {
        // 创建新记录（理论上 loadNovelContent 应该已经创建，但以防万一）
        logger.warn(TAG, `未找到新书记录，创建新记录`);
        const now = Date.now();
        const newBook: NovelBook = {
          id: `${newSourceId}_${newBookUrl}`,
          sourceId: newSourceId,
          sourceName: this.getDisplaySourceName(),
          bookUrl: newBookUrl,
          name: this.content.title,
          author: this.content.author,
          intro: this.content.description,
          coverUrl: this.content.coverUrl,
          chapterCount: this.content.totalChapters,
          readStatus: originalInfo.lastReadChapterIndex >= 0 ? NovelReadStatus.READING : NovelReadStatus.UNREAD,
          totalReadingTime: 0,
          isFavorite: true,
          lastReadChapterIndex: newLastReadIndex,
          lastReadChapterId: newLastReadChapterId,
          lastReadPosition: 0,
          lastReadTime: now,
          createTime: now,
          updateDbTime: now
        };
        await this.novelDataManager.saveBook(newBook);
        logger.info(TAG, `新书已创建: ${newBook.name}, lastReadIndex=${newLastReadIndex}`);
      }
      
      // 4. 确保章节列表已缓存（避免返回书架后重新加载）
      if (this.content.chapters.length > 0) {
        const originalNovel = NovelAdapter.getOriginalNovel(this.content);
        if (originalNovel) {
          const legadoChapters: LegadoChapter[] = this.content.chapters.map((ch: UnifiedChapter) => {
            const original = NovelAdapter.getOriginalChapter(ch);
            return original || { title: ch.title, url: ch.id } as LegadoChapter;
          });
          await this.novelCacheManager.saveChapterList(newBookUrl, legadoChapters);
          logger.info(TAG, `章节列表已缓存: ${legadoChapters.length}章`);
        }
      }
      
      // 5. 将新书添加到书架（如果原书在某个书架中，将新书也添加到同一个书架）
      const newBookId = newBookInDb?.id || `${newSourceId}_${newBookUrl}`;
      if (originalInfo.shelfId) {
        // 原书在自定义书架中，将新书添加到同一个书架
        // 注意：itemId必须使用完整的novel.id格式（${sourceId}_${bookUrl}），与数据库中的NovelBook.id一致
        await this.typeShelfManager.moveItemToShelf(newBookId, ContentType.NOVEL, originalInfo.shelfId);
        logger.info(TAG, `新书已添加到书架: ${originalInfo.shelfId}, bookId=${newBookId}`);
      } else {
        // 原书不在自定义书架中，只设置收藏状态（已在步骤3中完成）
        logger.info(TAG, `新书已设置为收藏状态`);
      }
      
      // 6. 删除原书数据
      if (originalInfo.bookId && originalInfo.isFavorite) {
        // 从书架分类中移除原书
        try {
          const categoryManager = this.typeShelfManager.getCategoryManager();
          // 注意：itemId必须使用完整的novel.id格式（${sourceId}_${bookUrl}）
          await categoryManager.removeItemFromCategory(originalInfo.bookId, ContentType.NOVEL);
          logger.info(TAG, `原书已从书架分类移除: ${originalInfo.bookId}`);
        } catch (e) {
          logger.warn(TAG, `从书架移除原书失败: ${String(e)}`);
        }
        
        // 删除原书章节缓存
        const originalCacheBookId = this.getNovelCacheBookId(originalInfo.sourceId, originalInfo.bookUrl);
        await this.novelCacheManager.clearBookCache(originalCacheBookId);
        logger.info(TAG, `原书章节缓存已清除: ${originalCacheBookId}`);
        
        // 删除原书数据库记录
        await this.novelDataManager.deleteBook(originalInfo.bookId);
        logger.info(TAG, `原书已删除: ${originalInfo.name}`);
      }
      
      // 7. 重置换源标记
      this.isFromChangeSource = false;
      this.originalBookInfo = null;
      
      // 8. 更新UI状态
      this.isFavorite = true;
      this.isInShelf = true;
      if (this.content) {
        this.content.lastReadChapterIndex = newLastReadIndex;
        this.content.isFavorite = true;
      }
      
      // 9. 检查更新书架状态
      await this.checkIfInShelf();
      
      this.getUIContext().getPromptAction().showToast({ 
        message: `已替换为「${this.content?.sourceName || '新书源'}」的版本`, 
        duration: 2500 
      });
      
      // 10. 发布事件通知 MainMenuPage 刷新小说列表
      eventBus.publish(GameEvent.NOVEL_LIST_REFRESH_NEEDED, new BasePayload());
      
      logger.info(TAG, `替换小说完成: ${this.content?.title}`);
      
    } catch (error) {
      logger.error(TAG, `替换小说失败: ${String(error)}`);
      this.getUIContext().getPromptAction().showToast({ message: `替换失败: ${String(error)}`, duration: 2000 });
    } finally {
      this.isLoading = false;
    }
  }
  
  /**
   * 生成封面对话框
   */
  @Builder
  buildGenerateCoverDialog() {
    GenerateCoverDialogComponent({
      themeState: this.themeState,
      loadSignal: this.generateCoverDialogLoadSignal,
      defaultTitle: this.content?.title || '',
      onConfirm: (title: string, fontScale: number) => {
        void this.generateCoverForContent(title, fontScale);
      }
    })
  }

  /**
   * 添加书架选择对话框
   */
  @Builder
  buildAddToShelfDialog() {
    AddToShelfDialogComponent({
      themeState: this.themeState,
      loadSignal: this.addToShelfDialogLoadSignal,
      shelves: this.availableCustomShelves,
      isPending: this.isShelfActionPending,
      onShelfSelected: (shelf: TypeShelf) => {
        void this.addToShelf(shelf);
      },
      onFavoriteOnly: () => {
        void this.addToFavoriteOnly();
      }
    })
  }

  /**
   * 替换小说对话框
   */
  @Builder
  buildReplaceBookDialog() {
    if (this.originalBookInfo && this.content) {
      ReplaceBookDialogComponent({
        themeState: this.themeState,
        loadSignal: this.replaceBookDialogLoadSignal,
        originalBookInfo: this.originalBookInfo,
        newSourceName: this.getDisplaySourceName(),
        newChapterCount: this.content.totalChapters,
        matchedChapterIndex: this.matchedChapterIndex,
        onConfirm: () => {
          void this.executeReplaceBook();
        }
      })
    }
  }

  /**
   * 重复检测弹窗
   */
  @Builder
  buildDuplicateDetectionDialog() {
    if (this.content) {
      DuplicateDetectionDialog({
        themeState: this.themeState,
        loadSignal: this.duplicateDetectionLoadSignal,
        newItemTitle: this.content.title,
        newItemAuthor: this.content.author,
        newItemContentType: this.mapToDuplicateCheckContentType(this.content.contentType),
        matches: this.duplicateDetectionMatches,
        onConfirm: () => {
          // 用户选择"仍然添加"
          if (this.pendingFavoriteAction) {
            void this.pendingFavoriteAction();
            this.pendingFavoriteAction = null;
          }
        },
        onCancel: () => {
          this.pendingFavoriteAction = null;
          this.isShelfActionPending = false;
        }
      })
    }
  }

  /**
   * 显示添加书架选择
   */
  private async showAddToShelfSelection(): Promise<void> {
    if (!this.content || this.isShelfActionPending) return;

    // 如果已在书架中，提示用户
    if (this.isInShelf) {
      this.getUIContext().getPromptAction().showToast({
        message: this.currentShelfName ? `已在「${this.currentShelfName}」中` : '已在书架中',
        duration: 1500
      });
      return;
    }

    this.isShelfActionPending = true;
    try {
      // 获取可用的自定义书架
      await this.getAvailableCustomShelves();

      // 显示对话框
      this.addToShelfDialogLoadSignal++;
    } finally {
      this.isShelfActionPending = false;
    }
  }

  /**
   * 检查内容是否已在书架中
   */
  private async checkIfInShelf(): Promise<void> {
    if (!this.content) return;
    
    try {
      // 获取所有书架
      const allShelves: TypeShelf[] = this.typeShelfManager.getShelves();
      
      // 遍历检查是否在某个自定义书架中
      for (const shelf of allShelves) {
        // 跳过系统书架
        if (shelf.isSystem) continue;
        
        // 根据内容类型检查
        let contentType: ContentType;
        switch (this.content.contentType) {
          case UnifiedContentType.MANGA:
            contentType = ContentType.MANGA;
            break;
          case UnifiedContentType.EBOOK:
            contentType = ContentType.EBOOK;
            break;
          case UnifiedContentType.NOVEL:
            contentType = ContentType.NOVEL;
            break;
          default:
            continue;
        }
        
        // 检查书架是否包含该内容
        const itemIds = this.typeShelfManager.getShelfItemIdsByType(shelf.id, contentType);
        if (itemIds.includes(this.content.id)) {
          this.isInShelf = true;
          this.currentShelfName = shelf.name;
          this.currentShelfId = shelf.id;
          return;
        }
      }
      
      // 如果不在任何自定义书架中，检查是否已收藏
      if (this.isFavorite) {
        this.isInShelf = true;
        this.currentShelfName = '';  // 已收藏但不在自定义书架中
        this.currentShelfId = '';
        return;
      }
      
      this.isInShelf = false;
      this.currentShelfName = '';
      this.currentShelfId = '';
    } catch (error) {
      logger.error(TAG, `检查书架状态失败: ${String(error)}`);
      this.isInShelf = false;
      this.currentShelfName = '';
      this.currentShelfId = '';
    }
  }

  /**
   * 获取可用的自定义书架
   */
  private async getAvailableCustomShelves(): Promise<void> {
    if (!this.content) {
      this.availableCustomShelves = [];
      return;
    }
    
    try {
      // 根据内容类型获取对应的书架
      let contentType: ContentType;
      switch (this.content.contentType) {
        case UnifiedContentType.MANGA:
          contentType = ContentType.MANGA;
          break;
        case UnifiedContentType.EBOOK:
          contentType = ContentType.EBOOK;
          break;
        case UnifiedContentType.NOVEL:
          contentType = ContentType.NOVEL;
          break;
        default:
          this.availableCustomShelves = [];
          return;
      }
      
      // 获取包含该内容类型的自定义书架（getShelvesForContentType已排除系统书架）
      this.availableCustomShelves = this.typeShelfManager.getShelvesForContentType(contentType);
    } catch (error) {
      logger.error(TAG, `获取自定义书架失败: ${String(error)}`);
      this.availableCustomShelves = [];
    }
  }

  /**
   * 添加到指定书架
   */
  private async addToShelf(shelf: TypeShelf): Promise<void> {
    if (!this.content || this.isShelfActionPending) return;
    
    this.isShelfActionPending = true;
    try {
      // 根据内容类型获取类型
      let contentType: ContentType;
      switch (this.content.contentType) {
        case UnifiedContentType.MANGA:
          contentType = ContentType.MANGA;
          break;
        case UnifiedContentType.EBOOK:
          contentType = ContentType.EBOOK;
          break;
        case UnifiedContentType.NOVEL:
          contentType = ContentType.NOVEL;
          break;
        default:
          return;
      }
      
      const doAddToShelf = async (): Promise<void> => {
        try {
          // 添加到书架
          await this.typeShelfManager.moveItemToShelf(this.content!.id, contentType, shelf.id);

          // 同时设置为收藏
          if (!this.isFavorite) {
            await this.setFavoriteStatus(true);
          }

          // 更新状态
          this.isInShelf = true;
          this.currentShelfName = shelf.name;
          this.currentShelfId = shelf.id;

          // 加载同书架内容
          this.loadShelfContent();

          this.getUIContext().getPromptAction().showToast({
            message: `已添加到「${shelf.name}」书架`,
            duration: 1500
          });
        } catch (error) {
          logger.error(TAG, `添加到书架失败: ${String(error)}`);
          this.getUIContext().getPromptAction().showToast({
            message: '添加失败，请重试',
            duration: 1500
          });
        }
      };

      // 需要设置收藏时进行重复检测
      if (!this.isFavorite) {
        const shouldStop = await this.checkDuplicateAndExecute(doAddToShelf, '添加到书架');
        if (shouldStop) {
          return;
        }
      }

      await doAddToShelf();
    } catch (error) {
      logger.error(TAG, `添加到书架失败: ${String(error)}`);
      this.getUIContext().getPromptAction().showToast({ 
        message: '添加失败，请重试',
        duration: 1500 
      });
    } finally {
      this.isShelfActionPending = false;
    }
  }

  /**
   * 仅添加到收藏（没有自定义书架时调用）
   */
  private async addToFavoriteOnly(): Promise<void> {
    if (!this.content || this.isShelfActionPending) return;

    this.isShelfActionPending = true;

    const doAdd = async (): Promise<void> => {
      try {
        await this.setFavoriteStatus(true);
        this.isInShelf = true;
        this.currentShelfName = '';
        this.getUIContext().getPromptAction().showToast({
          message: '已添加到默认书架',
          duration: 1500
        });
      } catch (error) {
        logger.error(TAG, `添加到收藏失败: ${String(error)}`);
        this.getUIContext().getPromptAction().showToast({
          message: '添加失败，请重试',
          duration: 1500
        });
      } finally {
        this.isShelfActionPending = false;
      }
    };

    const shouldStop = await this.checkDuplicateAndExecute(doAdd, '添加到默认书架');
    if (!shouldStop) {
      await doAdd();
    }
    // shouldStop=true 时：弹窗已显示，isShelfActionPending 的重置由弹窗回调处理
  }

  /**
   * 设置收藏状态（内部方法）
   */
  private resolveCoverSourceForPersistence(): string {
    if (!this.content) {
      return '';
    }
    const candidates: string[] = [
      this.localCoverPath || '',
      this.content.coverUrl || '',
      this.pageParams?.cachedCoverPath || '',
      this.pageParams?.cachedCover || ''
    ];
    for (const candidate of candidates) {
      if (candidate && candidate.trim().length > 0) {
        return candidate.trim();
      }
    }
    return '';
  }

  private mapLibraryCoverType(contentType: UnifiedContentType): LibraryCoverType {
    switch (contentType) {
      case UnifiedContentType.NOVEL:
        return LibraryCoverType.NOVEL;
      case UnifiedContentType.EBOOK:
        return LibraryCoverType.EBOOK;
      case UnifiedContentType.MANGA:
      default:
        return LibraryCoverType.MANGA;
    }
  }

  private async persistCoverForFavorite(contentType: UnifiedContentType): Promise<string> {
    if (!this.content) {
      return '';
    }
    const sourceCover = this.resolveCoverSourceForPersistence();
    if (!sourceCover) {
      return '';
    }
    const hostContext = (this.getUIContext().getHostContext() as common.UIAbilityContext) as common.UIAbilityContext;
    if (!hostContext || !hostContext.filesDir) {
      return '';
    }

    const persistedPath = await LibraryCoverManager.persistCoverByFilesDir(
      hostContext.filesDir,
      this.mapLibraryCoverType(contentType),
      `${this.content.sourceId || 'local'}_${this.content.id}`,
      sourceCover
    );

    if (persistedPath) {
      logger.info(TAG, `封面持久化完成: ${persistedPath}`);
      return persistedPath;
    }
    return '';
  }

  private publishMangaFavoriteChanged(isFavorite: boolean): void {
    if (!this.content || this.content.contentType !== UnifiedContentType.MANGA) {
      return;
    }

    let externalId: string = this.content.id || '';
    const originalManga: Manga | null = MangaAdapter.getOriginalManga(this.content);
    if (originalManga) {
      if (originalManga.sourceInfo && originalManga.sourceInfo.externalId && originalManga.sourceInfo.externalId.length > 0) {
        externalId = originalManga.sourceInfo.externalId;
      } else if (originalManga.id && originalManga.id.length > 0) {
        externalId = originalManga.id;
      }
    }

    const payload = new MangaFavoriteChangedPayload(
      this.content.id || '',
      externalId,
      this.content.sourceId || '',
      this.content.sourceName || '',
      this.content.sourcePkg || '',
      isFavorite
    );
    eventBus.publish(GameEvent.MANGA_FAVORITE_CHANGED, payload);
    logger.debug(TAG, `漫画收藏状态事件已发布: sourceId=${payload.sourceId}, sourcePkg=${payload.sourcePkg}, externalId=${payload.externalId}, isFavorite=${String(isFavorite)}`);
  }

  private async setFavoriteStatus(isFavorite: boolean): Promise<void> {
    if (!this.content) return;
    
    this.isFavorite = isFavorite;
    this.content.isFavorite = isFavorite;
    const persistedCoverPath = isFavorite
      ? await this.persistCoverForFavorite(this.content.contentType)
      : '';
    
    switch (this.content.contentType) {
      case UnifiedContentType.MANGA:
        const dataService = DataService.getInstance();
        if (isFavorite) {
          await dataService.addToFavorites(this.content.id);
          if (persistedCoverPath) {
            await this.dataManager.updateComicCoverForLibrary(this.content.id, persistedCoverPath);
            this.content.coverUrl = persistedCoverPath;
            this.localCoverPath = persistedCoverPath;
          }
        } else {
          await dataService.removeFromFavorites(this.content.id);
        }
        break;
      case UnifiedContentType.EBOOK:
        const ebook = EBookAdapter.getOriginalEBook(this.content);
        if (ebook && ebook.metadata) {
          ebook.isFavorite = isFavorite;
          if (isFavorite && persistedCoverPath) {
            ebook.metadata.coverImagePath = persistedCoverPath;
            this.content.coverUrl = persistedCoverPath;
            this.localCoverPath = persistedCoverPath;
          }
          await this.ebookDataManager.saveEBook(ebook);
        } else if (isFavorite && this.content.sourceId) {
          // 在线电子书：创建新的EBook对象并保存
          const now = Date.now();
          const finalCoverPath = persistedCoverPath || this.content.coverUrl;
          const metadata: EBookMetadata = {
            title: this.content.title,
            author: this.content.author,
            publisher: '',
            publishDate: '',
            isbn: '',
            language: '',
            description: this.content.description,
            coverImagePath: finalCoverPath,
            tags: this.content.tags || [],
            rating: 0
          };
          const emptyChapters: EBookChapter[] = [];
          const extendedDataMap = new Map<string, string>();
          extendedDataMap.set('sourceId', this.content.sourceId || '');
          extendedDataMap.set('sourceName', this.content.sourceName || '');
          extendedDataMap.set('sourcePkg', this.content.sourcePkg || '');
          extendedDataMap.set('onlineReaderUrl', this.onlineReaderUrl || '');
          extendedDataMap.set('detailRequestValue', this.onlineEBookDetailRequestValue || '');
          if (this.onlineEBookVerificationInfo) {
            extendedDataMap.set('verificationStatus', this.onlineEBookVerificationInfo.status || '');
            extendedDataMap.set('verificationMessage', this.onlineEBookVerificationInfo.message || '');
            extendedDataMap.set('verificationPageUrl', this.onlineEBookVerificationInfo.pageUrl || '');
            extendedDataMap.set('verificationPageTitle', this.onlineEBookVerificationInfo.pageTitle || '');
            extendedDataMap.set('verificationCooldownText', this.onlineEBookVerificationInfo.cooldownText || '');
            extendedDataMap.set('verificationCooldownSeconds', String(this.onlineEBookVerificationInfo.cooldownSeconds || 0));
            extendedDataMap.set('verificationCanRetry', this.onlineEBookVerificationInfo.canRetryVerification ? 'true' : 'false');
            extendedDataMap.set('verificationAttempt', String(this.onlineEBookVerificationInfo.attempt || 0));
            extendedDataMap.set('verificationUpdatedAt', String(this.onlineEBookVerificationInfo.lastUpdatedTime || 0));
          }
          const extendedDataObj: Record<string, string> = {};
          extendedDataMap.forEach((value: string, key: string) => {
            extendedDataObj[key] = value;
          });
          const extendedDataJson = JSON.stringify(extendedDataObj);
          const onlineEbook = new EBook(
            this.content.id,
            EBookFormat.EPUB,
            extendedDataJson,
            0,
            metadata,
            emptyChapters
          );
          onlineEbook.metadata = metadata;
          onlineEbook.status = EBookStatus.UNREAD;
          onlineEbook.addTime = now;
          onlineEbook.lastUpdateTime = now;
          onlineEbook.isFavorite = true;
          onlineEbook.totalWordCount = 0;
          onlineEbook.isPrivate = false;
          onlineEbook.isNSFW = this.content.isNSFW || false;
          await this.ebookDataManager.saveEBook(onlineEbook);
          if (persistedCoverPath) {
            this.content.coverUrl = persistedCoverPath;
            this.localCoverPath = persistedCoverPath;
          }
        }
        break;
      case UnifiedContentType.NOVEL:
        const novelBook = await this.novelDataManager.getBookByUrl(this.content.sourceId || '', this.content.id);
        if (novelBook) {
          novelBook.isFavorite = isFavorite;
          if (isFavorite && persistedCoverPath) {
            novelBook.coverLocalPath = persistedCoverPath;
            this.content.coverUrl = persistedCoverPath;
            this.localCoverPath = persistedCoverPath;
          }
          await this.novelDataManager.saveBook(novelBook);
        } else if (isFavorite) {
          const now = Date.now();
          const newBook: NovelBook = {
            id: '',
            sourceId: this.content.sourceId || '',
            sourceName: this.getDisplaySourceName(),
            bookUrl: this.content.id,
            name: this.content.title,
            author: this.content.author,
            intro: this.content.description,
            coverUrl: this.content.coverUrl,
            coverLocalPath: persistedCoverPath || undefined,
            chapterCount: this.content.totalChapters,
            readStatus: NovelReadStatus.UNREAD,
            totalReadingTime: 0,
            isFavorite: true,
            createTime: now,
            updateDbTime: now
          };
          await this.novelDataManager.saveBook(newBook);
          if (persistedCoverPath) {
            this.content.coverUrl = persistedCoverPath;
            this.localCoverPath = persistedCoverPath;
          }
        }
        break;
    }

    this.publishMangaFavoriteChanged(isFavorite);
    this.trackingLoadSignal++;
  }
}

