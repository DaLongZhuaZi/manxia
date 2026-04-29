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
import { logger } from '../Utils/Logger';
import { WindowManager, DisplayMode } from '../Utils/WindowManager';
import { PageWindowCoordinator } from '../Utils/PageWindowCoordinator';
import { PageLifecycleManager } from '../Framework/Lifecycle';
import { ThemeAwareState, ThemeAwareHelper } from '../Framework/Components/ThemeAware';
import { SourceDialogScaffold } from '../Framework/Components/SourceDialogScaffold';
import { DialogSurfaceStyleHelper } from '../Framework/Components/DialogSurfaceStyleHelper';
import { ScraperDialog, ScraperDialogConfig, ScraperDialogResult } from '../Framework/Components/ScraperDialog';
import { ScraperContentType } from '../Framework/Scraper/ScraperTypes';
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
  ContentTrackingHighlight,
  ContentTrackingHighlightTone,
  ContentTrackingStatusCard
} from '../components/ContentTrackingStatusCard';
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
} from '../Framework/Subscription';

import {
  UnifiedContent,
  UnifiedChapter,
  UnifiedContentType,
  UnifiedReadStatus,
  UnifiedDetailPageParams,
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
import { buildLocalTextNovelBookId, buildNovelReaderParamsFromTxtEBook } from '../Framework/Adapters/LocalTextNovelAdapter';

// 数据管理器导入
import { DataManager, ChapterInfo, OnlineChapterInfo } from '../Framework/Data/DataManager';
import { DataService } from '../Framework/Services/DataService';
import { MangaDetailLoader, MangaDetailLoadParams, MangaDetailLoadResult, MangaLoadProgressCallback, ChapterProgressInfo } from '../Framework/Loaders/MangaDetailLoader';
import webview from '@ohos.web.webview';
import { EBookDataManager } from '../Framework/Data/EBookDataManager';
import { SourceManager, SourceInfo } from '../Framework/Source/SourceManager';
import { RemoteLibraryMangaBridge } from '../Framework/Source/RemoteLibraryMangaBridge';
import { MangaSourceEngine, EngineConfig } from '../Framework/WebView/MangaSourceEngine';
import { WebViewSourceManager } from '../Framework/WebView/WebViewSourceManager';
import { AntiCrawlerConfig } from '../Framework/WebView/MangaSourceTypes';
import { getNovelSourceManager } from '../Framework/Novel/NovelSourceManager';
import { getNovelDataManager } from '../Framework/Novel/NovelDataManager';
import { getNovelChapterCacheManager } from '../Framework/Novel/NovelChapterCacheManager';
import { getNovelContentProcessor } from '../Framework/Novel/NovelContentProcessor';
import { getNovelTxtTocRuleManager, TxtTocRule } from '../Framework/Novel/NovelTxtTocRuleManager';
import { NovelReplaceRuleManager, ReplaceScope, ReplaceRule } from '../Framework/Novel/NovelReplaceRuleManager';
import { getNovelSourceSearchService, SourceSearchResult, SearchTaskHandle, SearchResultCache } from '../Framework/Novel/NovelSourceSearchService';
import { getCacheStatusService, CacheStatusService, ContentCacheStats, CacheContentType } from '../Framework/Services/CacheStatusService';
import { getUnifiedDownloadManager, UnifiedDownloadManager, UnifiedDownloadType, UnifiedTaskStatus, UnifiedDownloadTask, UnifiedDownloadCallback, MangaChapterDownloadItem, PageListFetcher } from '../Framework/Download/UnifiedDownloadManager';
import { CoverCacheManager } from '../Framework/Cache/CoverCacheManager';
import { getCoverImageManager, CoverImageManager } from '../Framework/Image/CoverImageManager';
import { OnlineLoadOptions, RequestHeaders } from '../Framework/Cache/OnlineImageLoader';
import { LibraryCoverManager, LibraryCoverType } from '../Framework/Storage/LibraryCoverManager';
import { image } from '@kit.ImageKit';
import { getNovelCoverGenerator, NovelCoverGenerator } from '../Framework/Novel/NovelCoverGenerator';
import { ZLibraryReaderParams } from './ZLibraryReaderPage';
import { AvifImage } from '../components/AvifImage';
import {
  eventBus,
  GameEvent,
  IEventPayload,
  CoverChangedPayload,
  BasePayload,
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
import { Manga, MangaChapter, ReadingProgress, ReadingSettings, MangaBookmark, MangaMetadata, ImageSourceType, DEFAULT_READING_SETTINGS } from '../Models/MangaModels';
import { DownloadStatus, MangaStatus, ReadingStatus } from '../Framework/Types/StatusEnums';
import { EBook, EBookChapter, EBookFormat, EBookStatus, EBookMetadata } from '../Models/EBookModels';
import { LegadoBook, LegadoChapter, LegadoBookSource, LegadoBookSourceType } from '../Framework/Novel/LegadoSourceTypes';
import { NovelBook, NovelReadStatus, NovelSearchResult } from '../Models/NovelModels';

// 阅读器参数导入
import { MangaReaderPageParams, MangaReaderContentType } from './MangaReaderPage';
import { MangaSettingsPageParams } from './MangaSettingsPage';
import { EBookSettingsPageParams } from './EBookDetailPage';
import { EBookReaderParams } from './EBookReaderRouteTypes';
import { NovelReaderPageParams } from './NovelBookshelfPage';
import { openEBookReaderRouterPage } from '../Framework/Adapters/EBookReaderRouteNavigator';

import { startBookOpenTransitionWithComponentId, EBookBackgroundSettings } from '../components/BookTransitionOverlay';
import { AppGuideOverlay, GuideHighlightRect } from '../Framework/Components/AppGuideOverlay';
import { ensureGuideAnchorVisibleInScroller, resolveGuideHighlightRectInRoot } from '../Framework/Components/AppGuideSupport';
import { AppGuideManager, AppGuidePageId, AppGuideStep } from '../Framework/Managers/AppGuideManager';
import { SettingsGlassStyleHelper } from './settings/SettingsGlassStyleHelper';
import { SettingsPageSurfaceManager, SettingsPageSurfaceStyle } from './settings/SettingsPageSurfaceManager';


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

interface UnifiedDetailTrackingTargetInfo {
  supported: boolean;
  unsupportedReason: string;
  contentType: SubscriptionContentType;
  targetId: string;
  targetTitle: string;
  sourceId: string;
  sourceName: string;
  providerType: SubscriptionProviderType;
}

interface OnlineEBookDetailRecord {
  title?: string;
  author?: string;
  description?: string;
  cover?: string;
  categories?: string;
  tags?: string;
  readerUrl?: string;
}

interface DialogResult {
  index: number;
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

  // 听书缓存状态
  @State readAloudCacheSummary: RemoteReadAloudCacheBookSummary | null = null;
  @State private appGuideStep: AppGuideStep | null = null;
  @State private appGuideHighlightRect: GuideHighlightRect | null = null;
  @State isReadAloudCacheLoading: boolean = false;
  @State isReadAloudCacheExpanded: boolean = true;
  @State showReadAloudCacheDialog: boolean = false;
  @State readAloudCacheDialogOpacity: number = 0;
  @State readAloudCacheDialogScale: number = 0.8;
  @State readAloudCacheDialogTranslateY: number = 50;
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

  private onReadAloudCacheUpdated: (payload: IEventPayload) => void = (payload: IEventPayload): void => {
    const cachePayload = payload as ReadAloudCacheUpdatedPayload;
    const currentBookId = this.getCurrentReadAloudCacheBookId();
    if (!currentBookId || cachePayload.bookId !== currentBookId) {
      return;
    }
    this.scheduleReadAloudCacheRefresh(cachePayload.reason || 'event');
  };

  private onMangaCacheUpdated: (payload: IEventPayload) => void = (payload: IEventPayload): void => {
    const cachePayload = payload as MangaCacheUpdatedPayload;
    if (!this.content || !this.isOnlineManga() || cachePayload.mangaId !== this.content.id) {
      return;
    }
    void this.loadCacheStatus();
    logger.info(TAG, `收到漫画缓存更新事件，刷新详情页缓存状态: chapterId=${cachePayload.chapterId}, reason=${cachePayload.reason}`);
  };
  
  // 下载对话框状态
  @State showDownloadDialog: boolean = false;           // 显示下载对话框
  @State downloadDialogOpacity: number = 0;             // 对话框背景透明度
  @State downloadDialogScale: number = 0.8;             // 对话框缩放
  @State downloadDialogTranslateY: number = 50;         // 对话框Y偏移
  @State downloadSelectionMode: 'range' | 'individual' = 'range';  // 选择模式
  @State downloadRangeStart: number = 0;                // 区间开始
  @State downloadRangeEnd: number = 0;                  // 区间结束
  @State downloadSelectedChapters: Set<number> = new Set();  // 单独选中的章节
  @State downloadChapterListExpanded: boolean = false;  // 章节列表是否展开

  // 小说设置对话框状态
  @State showNovelSettingsDialog: boolean = false;
  @State novelSettingsDialogOpacity: number = 0;
  @State novelSettingsDialogScale: number = 0.8;
  @State novelSettingsDialogTranslateY: number = 50;
  @State novelEnableReadWhileDownload: boolean = true;
  @State novelDefaultLoadChapters: number = 50;
  @State novelEnableDirectoryParsing: boolean = true;
  @State novelEnableReplaceRules: boolean = true;
  @State novelSettingsActiveTab: number = 0;
  @State novelDirectoryParsingSelection: boolean = true;
  @State novelReplaceRulesSelection: boolean = true;
  @State novelTocRules: TxtTocRule[] = [];
  @State novelReplaceRules: ReplaceRule[] = [];
  @State novelSelectedTocRuleIds: string[] = [];
  @State novelSelectedReplaceRuleIds: string[] = [];
  @State novelAppliedTocRuleIds: string[] = [];
  @State novelAppliedReplaceRuleIds: string[] = [];
  @State novelDirectoryRulesDirty: boolean = false;
  @State novelReplaceRulesDirty: boolean = false;
  @State isApplyingNovelDirectoryParsing: boolean = false;
  @State isApplyingNovelReplaceRules: boolean = false;
  @State ebookInfoTitle: string = '';
  @State ebookInfoAuthor: string = '';
  @State ebookInfoPublisher: string = '';
  @State ebookInfoPublishDate: string = '';
  @State ebookInfoIsbn: string = '';
  @State ebookInfoLanguage: string = '';
  @State ebookInfoDescription: string = '';
  @State ebookInfoTagsText: string = '';
  @State ebookInfoCoverPath: string = '';
  @State ebookInfoDirty: boolean = false;
  @State isSavingEBookInfo: boolean = false;
  private ebookInfoScraperDialogController: CustomDialogController | null = null;
  
  // 下载进度实时显示状态
  @State downloadProgressCurrent: number = 0;           // 当前下载进度
  @State downloadProgressTotal: number = 0;             // 总下载数量
  @State downloadCurrentChapterTitle: string = '';      // 当前正在下载的章节标题
  private downloadCallbackRegistered: boolean = false;  // 是否已注册下载回调
  private downloadCallback: UnifiedDownloadCallback | null = null;
  
  // 换源对话框状态
  @State showChangeSourceDialog: boolean = false;       // 显示换源对话框
  @State changeSourceDialogOpacity: number = 0;         // 对话框背景透明度
  @State changeSourceDialogScale: number = 0.8;         // 对话框缩放
  @State changeSourceDialogTranslateY: number = 30;     // 对话框Y偏移
  @State isSearchingSource: boolean = false;            // 是否正在搜索书源
  @State searchSourceProgress: number = 0;              // 搜索进度(0-100)
  @State searchSourceTotal: number = 0;                 // 总书源数
  @State searchSourceCompleted: number = 0;             // 已完成搜索的书源数
  @State alternativeSourceResults: SourceSearchResult[] = [];  // 按书源分组的搜索结果
  @State alternativeSources: NovelSearchResult[] = [];  // 所有搜索结果
  @State changeSourceKeyword: string = '';              // 换源搜索关键词
  private searchTaskHandle: SearchTaskHandle | null = null;    // 搜索任务句柄
  private sourceSearchService = getNovelSourceSearchService(); // 换源搜索服务
  
  // 换源替换相关状态
  @State isFromChangeSource: boolean = false;           // 是否来自换源
  @State originalBookInfo: OriginalBookInfo | null = null;  // 原书信息
  @State showReplaceBookDialog: boolean = false;        // 显示替换小说对话框
  @State replaceDialogOpacity: number = 0;              // 替换对话框透明度
  @State replaceDialogScale: number = 0.8;              // 替换对话框缩放
  @State replaceDialogTranslateY: number = 30;          // 替换对话框Y偏移
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
  @State isInShelf: boolean = false;                    // 是否已在书架中
  @State currentShelfName: string = '';                 // 当前所在书架名称
  @State currentShelfId: string = '';                   // 当前所在书架ID
  @State showAddToShelfDialog: boolean = false;         // 显示添加到书架对话框
  @State addToShelfDialogOpacity: number = 0;           // 对话框背景透明度
  @State addToShelfDialogScale: number = 0.8;           // 对话框缩放
  @State availableCustomShelves: TypeShelf[] = [];      // 可用的自定义书架列表
  @State isShelfActionPending: boolean = false;         // 书架操作进行中（防重复点击）

  // 内容跟踪状态
  @State trackingRule: SubscriptionRule | null = null;
  @State trackingExecution: SubscriptionExecutionRecord | null = null;
  @State isTrackingLoading: boolean = false;
  @State isTrackingBusy: boolean = false;
  @State trackingSupported: boolean = false;
  @State trackingUnsupportedReason: string = '';
  @State showTrackingSettingsDialog: boolean = false;
  @State trackingDialogOpacity: number = 0;
  @State trackingDialogScale: number = 0.8;
  @State trackingDialogTranslateY: number = 36;
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
  private trackingTargetInfo: UnifiedDetailTrackingTargetInfo | null = null;
  
  // 生成封面状态
  @State isGeneratingCover: boolean = false;
  @State showGenerateCoverDialog: boolean = false;
  @State coverTitleInput: string = '';
  @State coverFontScale: number = 1.0;
  @State dialogOpacity: number = 0;
  @State dialogScale: number = 0.8;
  @State dialogTranslateY: number = 30;
  @State coverRefreshKey: number = 0;

  @State isCacheConfirmDialogVisible: boolean = false;
  @State cacheConfirmDialogOpacity: number = 0;
  @State cacheConfirmDialogScale: number = 0.8;
  @State cacheConfirmDialogTranslateY: number = 28;
  @State cacheConfirmTitle: string = '';
  @State cacheConfirmMessage: string = '';
  @State cacheConfirmActionLabel: string = '';
  @State cacheConfirmActionKind: 'danger' | 'primary' = 'danger';
  @State cacheConfirmPendingAction: '' | 'clear_content' | 'clear_novel' | 'clear_manga' = '';

  @State isNovelSettingsCloseConfirmDialogVisible: boolean = false;
  @State novelSettingsCloseConfirmOpacity: number = 0;
  @State novelSettingsCloseConfirmScale: number = 0.8;
  @State novelSettingsCloseConfirmTranslateY: number = 28;
  private novelSettingsCloseAfterClose: (() => void) | undefined = undefined;


  // 封面生成器常量
  static readonly COVER_WIDTH = 400;
  static readonly COVER_HEIGHT = 600;
  static readonly TITLE_AREA_TOP_PERCENT = 0.130;
  static readonly TITLE_AREA_BOTTOM_PERCENT = 0.345;
  static readonly TITLE_AREA_LEFT_PERCENT = 0.110;
  static readonly TITLE_AREA_RIGHT_PERCENT = 0.895;
  
  // 漫画详情加载器
  private mangaDetailLoader: MangaDetailLoader = MangaDetailLoader.getInstance();
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

  private isNovelSettingsDialogForLocalEBook(): boolean {
    return this.showNovelSettingsDialog && this.isLocalImportedEBookContent();
  }

  private canUseNovelStyleSettingsDialog(): boolean {
    if (!this.content) {
      return false;
    }
    if (this.content.contentType === UnifiedContentType.NOVEL) {
      return true;
    }
    return this.isLocalImportedEBookContent();
  }

  private shouldShowTrackingStatusSection(): boolean {
    return !!this.content && !this.isCurrentLocalImportedContent();
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
      this.showDownloadOptions();
      return;
    }
    if (this.content.contentType === UnifiedContentType.MANGA) {
      logger.info(TAG, `打开漫画缓存对话框: 触发源=${trigger}`);
      this.showDownloadOptions();
      return;
    }
    logger.info(TAG, `打开通用缓存对话框: 触发源=${trigger}, 内容类型=${this.content.contentType}`);
    this.showDownloadOptions();
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
  
  // 设置管理器
  private settingsManager: SettingsManager = SettingsManager.getInstance();
  
  // 智能推荐状态
  @State recommendedItems: RecommendationItem[] = [];
  @State isLoadingRecommendations: boolean = false;

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
    eventBus.subscribe(GameEvent.READ_ALOUD_CACHE_UPDATED, this.onReadAloudCacheUpdated);
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
    eventBus.unsubscribe(GameEvent.READ_ALOUD_CACHE_UPDATED, this.onReadAloudCacheUpdated);
    eventBus.unsubscribe(GameEvent.MANGA_CACHE_UPDATED, this.onMangaCacheUpdated);
    this.clearReadAloudCacheRefreshTimer();

    if (this.deviceChangeListener) {
      this.deviceManager.removeListener(this.deviceChangeListener);
      this.deviceChangeListener = null;
    }

    this.webViewControllerAttached = false;
    this.pendingInitialContentLoad = false;
    this.initialContentLoadTriggered = false;
    
    // 取消下载回调注册
    if (this.downloadCallbackRegistered) {
      this.unregisterDownloadCallback();
    }
    
    // 取消正在进行的换源搜索
    if (this.searchTaskHandle) {
      this.searchTaskHandle.cancel();
      this.searchTaskHandle = null;
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
      this.trackingAutoCreateAttempted = false;
      this.trackingAutoCreatedThisSession = false;

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
      }

      // 检查SFW模式
      if (this.content && this.content.isNSFW) {
        const sfwEnabled = ContentFilterManager.getInstance().isSFWModeEnabled();
        if (sfwEnabled) {
          logger.warn(TAG, 'SFW模式已启用，阻止访问NSFW内容');
          promptAction.showToast({
            message: 'SFW模式已启用，无法查看此内容',
            duration: 2000
          });
          this.pathStack.pop();
          return;
        }
      }
      
      // 加载缓存状态（在线漫画和小说）
      await this.loadCacheStatus();
      await this.loadReadAloudCacheSummary();
      
      // 检查是否已在书架中
      await this.checkIfInShelf();
      await this.refreshTrackingState();
      
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
    }
  }

  private async ensureContentTrackingReady(): Promise<boolean> {
    try {
      const hostContext = this.getUIContext().getHostContext() as common.UIAbilityContext;
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
    if (this.isCurrentLocalImportedContent()) {
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
      const sourceId = this.getCurrentNovelSourceId();
      const bookUrl = this.normalizeTrackingText(typeof this.content.id === 'string' ? this.content.id : '');
      if (sourceId.length <= 0 || bookUrl.length <= 0) {
        unsupportedTarget.unsupportedReason = '这本小说缺少来源信息，暂时不能开启提醒';
        unsupportedTarget.contentType = SubscriptionContentType.NOVEL;
        unsupportedTarget.providerType = SubscriptionProviderType.LEGADO;
        return unsupportedTarget;
      }
      let novelBookId = await this.resolveExistingNovelTrackingBookId(sourceId, bookUrl);
      if (novelBookId.length <= 0) {
        novelBookId = this.getNovelCacheBookId(sourceId, bookUrl);
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

    const constructedId = this.getNovelCacheBookId(sourceId, bookUrl);
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

    const sourceId = this.getCurrentNovelSourceId();
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
    const bookId = this.getNovelCacheBookId(sourceId, bookUrl);
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
      coverLocalPath: this.localCoverPath.length > 0 ? this.localCoverPath : undefined,
      latestChapterTitle: latestChapterTitle.length > 0 ? latestChapterTitle : undefined,
      chapterCount: this.content.totalChapters,
      readStatus: NovelReadStatus.UNREAD,
      totalReadingTime: 0,
      isFavorite: this.isFavorite,
      isNSFW: this.content.isNSFW,
      createTime: now,
      updateDbTime: now
    };
    await this.novelDataManager.saveBook(newBook);
    logger.info(TAG, `已为内容跟踪补建小说本地记录: ${newBook.name}`);
    return bookId;
  }

  private shouldAutoCreateTrackingOnInitialEntry(targetInfo: UnifiedDetailTrackingTargetInfo): boolean {
    if (!targetInfo.supported || this.trackingAutoCreateAttempted || !this.isOnlineContent()) {
      return false;
    }
    if (targetInfo.contentType === SubscriptionContentType.NOVEL) {
      return true;
    }
    return targetInfo.contentType === SubscriptionContentType.MANGA &&
      (targetInfo.providerType === SubscriptionProviderType.SUWAYOMI ||
        targetInfo.providerType === SubscriptionProviderType.KOMGA);
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
    if (this.isCurrentLocalImportedContent()) {
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
        promptAction.showToast({ message: `没能读到提醒状态: ${String(error)}`, duration: 2000 });
      }
    } finally {
      this.isTrackingLoading = false;
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
      promptAction.showToast({
        message: this.trackingUnsupportedReason.length > 0 ? this.trackingUnsupportedReason : '这类内容暂时还不能添加提醒',
        duration: 2000
      });
      return;
    }

    this.fillTrackingDialogFromRule(this.trackingRule);
    this.trackingSettingsActiveTab = 0;
    this.showTrackingSettingsDialog = true;
    animateTo({
      duration: 260,
      curve: Curve.EaseOut
    }, () => {
      this.trackingDialogOpacity = 1;
      this.trackingDialogScale = 1;
      this.trackingDialogTranslateY = 0;
    });
  }

  private closeTrackingSettingsDialog(): void {
    animateTo({
      duration: 180,
      curve: Curve.EaseIn
    }, () => {
      this.trackingDialogOpacity = 0;
      this.trackingDialogScale = 0.96;
      this.trackingDialogTranslateY = 12;
    });
    setTimeout(() => {
      this.showTrackingSettingsDialog = false;
    }, 200);
  }

  private async saveCurrentContentTracking(): Promise<void> {
    if (this.isTrackingBusy) {
      return;
    }
    const targetInfo = this.trackingTargetInfo;
    if (targetInfo === null || !targetInfo.supported) {
      promptAction.showToast({ message: '这类内容暂时还不能在这里开启提醒', duration: 2000 });
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
      promptAction.showToast({
        message: hadExistingRule
          ? '提醒设置已更新，之后会在 APP 回到前台时补查'
          : '已为当前内容开启提醒，之后会在 APP 回到前台时补查',
        duration: 1800
      });
    } catch (error) {
      logger.error(TAG, `保存内容跟踪配置失败: ${String(error)}`);
      promptAction.showToast({ message: `保存失败: ${String(error)}`, duration: 2000 });
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
      promptAction.showToast({
        message: result.message.length > 0 ? result.message : '已开始检查当前内容',
        duration: 2000
      });
    } catch (error) {
      logger.error(TAG, `立即执行内容跟踪失败: ${String(error)}`);
      promptAction.showToast({ message: `执行失败: ${String(error)}`, duration: 2000 });
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
      promptAction.showToast({
        message: this.trackingRule !== null && this.trackingRule.enabled
          ? '已开启更新提醒，APP 回到前台时会自动补查'
          : '已暂停更新提醒',
        duration: 1600
      });
    } catch (error) {
      logger.error(TAG, `切换内容跟踪启用状态失败: ${String(error)}`);
      promptAction.showToast({ message: `操作失败: ${String(error)}`, duration: 2000 });
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
    promptAction.showDialog({
      title: '关闭更新提醒',
      message: `确认关闭「${ruleName}」的更新提醒？`,
      buttons: [
        { text: '取消', color: '#666666' },
        { text: '关闭', color: '#FF4D4F' }
      ]
    }).then((dialogResult: DialogResult) => {
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
      promptAction.showToast({ message: '已关闭当前内容的更新提醒', duration: 1800 });
    } catch (error) {
      logger.error(TAG, `删除内容跟踪规则失败: ${String(error)}`);
      promptAction.showToast({ message: `删除失败: ${String(error)}`, duration: 2000 });
    } finally {
      this.isTrackingBusy = false;
    }
  }

  private openTrackingManagementPage(): void {
    this.navigateWithManagedWindowTransition('SubscriptionManagementPage', null);
  }

  /**
   * 加载漫画内容（使用MangaDetailLoader分阶段加载）
   */
  private async loadMangaContent(): Promise<void> {
    if (!this.pageParams) return;

    const mangaId = this.pageParams.contentId;
    const sourceId = this.pageParams.sourceId;
    logger.info(TAG, `加载漫画内容: mangaId=${mangaId}, sourceId=${sourceId}`);

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
      cachedTitle: this.pageParams.cachedTitle,
      cachedCoverPath: this.pageParams.cachedCoverPath,
      cachedCover: this.pageParams.cachedCover,
      forceRefresh: false
    };

    // 构建已读/已下载/书签章节ID集合
    const readChapterIds = new Set<string>();
    const downloadedChapterIds = new Set<string>();
    const bookmarkedChapterIds = new Set<string>();
    let lastReadChapterIndex = -1;

    // 分阶段加载回调
    const progressCallback: MangaLoadProgressCallback = {
      onBasicInfoLoaded: (manga: Manga, isFavorite: boolean) => {
        logger.info(TAG, `[分阶段] 基本信息已加载: ${manga.title}`);
        this.isFavorite = isFavorite;
        this.isBasicInfoLoaded = true;
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
          sourceId
        );
        
        // 封面加载完成
        this.isCoverLoading = false;
        
        // 在线漫画：加载本地缓存的封面
        if (sourceId && Number(sourceId) > 0) {
          this.loadCachedCover(Number(sourceId), mangaId);
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
          const finalCoverPath = this.localCoverPath || this.content.coverUrl || originalManga?.coverImagePath || '';
          const finalCoverSourceType = this.localCoverPath
            ? ImageSourceType.LOCAL
            : (this.content.isLocal ? ImageSourceType.LOCAL : ImageSourceType.NETWORK);
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
            sourceId
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
        this.errorMessage = result.errorMessage || '漫画加载失败';
      }
    } else {
      logger.info(TAG, `漫画内容加载完成: ${this.content?.title}`);
    }
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
                this.pageParams?.sourceId
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
    this.isChaptersLoading = false;

    // 检测是否为在线电子书（filePath是JSON格式的扩展数据且id是URL）
    const isOnlineEbook = bookId.startsWith('http://') || bookId.startsWith('https://');
    if (isOnlineEbook && ebook.filePath) {
      try {
        // 尝试从filePath解析扩展数据
        const extendedData = JSON.parse(ebook.filePath) as Record<string, string>;
        const sourceId = extendedData['sourceId'] || '';
        const onlineReaderUrl = extendedData['onlineReaderUrl'] || '';
        
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
  private async loadOnlineEBookContent(bookId: string, sourceId: string): Promise<void> {
    logger.info(TAG, `加载在线电子书: bookId=${bookId}, sourceId=${sourceId}`);
    
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
        isLocal: false,
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
        // 使用WebView获取详情
        // 构建完整的URL：如果bookId不是完整路径，需要添加baseUrl
        let fullUrl = bookId;
        if (!bookId.startsWith('http')) {
          // bookId可能是/book/xxx格式或者只是文件名
          if (bookId.startsWith('/')) {
            fullUrl = `${this.ebookSourceInfo?.baseUrl || 'https://zh.chris101.ru'}${bookId}`;
          } else {
            // 尝试从缓存的URL构建
            fullUrl = `${this.ebookSourceInfo?.baseUrl || 'https://zh.chris101.ru'}/${bookId}`;
          }
        }
        logger.info(TAG, `使用WebView获取电子书详情: bookId=${bookId}, fullUrl=${fullUrl}`);
        const result = await this.ebookSourceEngine.getBookDetail(fullUrl);
        
        if (result.success && result.data) {
          const detail = result.data as OnlineEBookDetailRecord;
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
  private async loadOnlineReaderUrl(bookId: string, sourceId: string): Promise<void> {
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
        // 获取电子书详情
        const result = await this.ebookSourceEngine.getBookDetail(bookId);
        
        if (result.success && result.data) {
          const detail = result.data as OnlineEBookDetailRecord;
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
      const context = getContext(this) as common.UIAbilityContext;
      const store = await preferences.getPreferences(context, NOVEL_SETTINGS_STORE);
      enableDirectoryParsing = await store.get(NOVEL_SETTING_ENABLE_DIRECTORY_PARSING, true) as boolean;
      enableReplaceRules = await store.get(NOVEL_SETTING_ENABLE_REPLACE_RULES, true) as boolean;
    } catch (error) {
      logger.warn(TAG, `加载目录解析设置失败，使用默认值: ${String(error)}`);
      enableDirectoryParsing = true;
      enableReplaceRules = true;
    }
    this.novelEnableDirectoryParsing = enableDirectoryParsing;
    this.novelEnableReplaceRules = enableReplaceRules;
    this.novelDirectoryParsingSelection = enableDirectoryParsing;
    this.novelReplaceRulesSelection = enableReplaceRules;
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
        bookUrl: bookInDb.bookUrl,
        name: bookInDb.name,
        author: bookInDb.author,
        kind: bookInDb.kind,
        intro: bookInDb.intro,
        coverUrl: bookInDb.coverLocalPath || bookInDb.coverUrl,
        tocUrl: bookInDb.tocUrl,
        latestChapterTitle: bookInDb.latestChapterTitle,
        wordCount: bookInDb.wordCount
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
    if (scopedTocRuleIds !== null) {
      this.novelSelectedTocRuleIds = scopedTocRuleIds;
    } else {
      this.novelSelectedTocRuleIds = [];
    }
    if (scopedReplaceRuleIds !== null) {
      this.novelSelectedReplaceRuleIds = scopedReplaceRuleIds;
    } else {
      this.novelSelectedReplaceRuleIds = [];
    }
    logger.info(
      TAG,
      `小说规则生效: scopeId=${ruleScopeId}, scopedToc=${scopedTocRuleIds === null ? 'default' : scopedTocRuleIds.length}, scopedReplace=${scopedReplaceRuleIds === null ? 'default' : scopedReplaceRuleIds.length}`
    );
    await this.applyDirectoryRulesToCurrentContent(enableDirectoryParsing, this.novelSelectedTocRuleIds);
    await this.applyReplaceRulesToCurrentNovelContent(enableReplaceRules, scopedReplaceRuleIds);
    
    // 章节加载完成
    this.isChaptersLoading = false;
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
    if (this.isCurrentNovelAudioSource()) {
      return this.hasReadingRecord() ? '继续听书' : '开始听书';
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

    logger.info(TAG, `continueReading: contentType=${this.content.contentType}, onlineReaderUrl=${this.onlineReaderUrl ? this.onlineReaderUrl.substring(0, 50) + '...' : 'null'}, sourceId=${this.content.sourceId}`);

    // 电子书特殊处理
    if (this.content.contentType === UnifiedContentType.EBOOK) {
      // 在线电子书：如果有在线阅读器URL，跳转到ZLibraryReaderPage
      if (this.onlineReaderUrl) {
        logger.info(TAG, '使用在线阅读器');
        this.openOnlineEBookReader();
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
    
    // 判断是否为在线漫画
    const hasSourceId = this.content.sourceId && Number(this.content.sourceId) > 0;
    
    if (hasSourceId && originalManga) {
      // 在线漫画：传递完整的manga对象和sourceId
      readerParams.manga = originalManga;
      readerParams.sourceId = Number(this.content.sourceId);
      readerParams.mangaId = this.content.id;
      readerParams.sourceName = this.content.sourceName || '';
      
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
      // 本地漫画：不传递manga对象，让MangaReaderPage从数据库加载完整的章节和页面信息
      readerParams.mangaId = this.content.id;
      readerParams.chapterId = chapter.id;
      readerParams.contentType = MangaReaderContentType.Local;
      readerParams.sourceName = 'LOCAL';
      // 注意：不传递manga对象，因为传递的manga对象中章节的pages数组可能为空
      // MangaReaderPage会通过mangaId从数据库加载完整的章节和页面信息
      logger.info(TAG, `本地漫画阅读: mangaId=${readerParams.mangaId}, chapterId=${readerParams.chapterId}`);
    }
    
    // [修复] 使用章节阅读进度中的页码，而不是总是从第一页开始
    const chapterProgress = this.chapterProgressMap.get(chapter.id);
    readerParams.pageIndex = chapterProgress ? chapterProgress.lastReadPageIndex : 0;
    logger.info(TAG, `阅读页码: chapterId=${chapter.id}, pageIndex=${readerParams.pageIndex} (来源: ${chapterProgress ? 'chapterProgressMap' : '默认'})`);

    // 触发翻开过渡动画
    // 优先使用本地缓存的封面路径（可直接加载PixelMap），回退到网络URL
    const coverPath: string = this.localCoverPath || this.content.coverUrl || '';
    const coverComponentId: string = `cover_${this.componentId}`;
    readerParams.coverComponentId = coverComponentId;
    
    logger.info(TAG, `触发漫画翻开过渡动画: coverPath=${coverPath}, componentId=${coverComponentId}`);
    startBookOpenTransitionWithComponentId(
      coverPath,
      coverComponentId,
      this.content.id,
      'manga',
      () => {
        // 动画完成时触发导航
        logger.info(TAG, '漫画翻开过渡动画触发导航');
        this.navigateWithManagedWindowTransition('MangaReaderPage', readerParams);
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
      bookId: this.content.id
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
          this.navigateWithManagedWindowTransition('NovelReaderPage', txtNovelReaderParams);
        } else {
          if (ebookRouteName === 'EBookReaderPage') {
            openEBookReaderRouterPage(this.getUIContext(), params, TAG);
          } else {
            this.navigateWithManagedWindowTransition(ebookRouteName, params);
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
    const sourceType = sourceId.length > 0
      ? (this.novelSourceManager.getSource(sourceId)?.bookSourceType ?? LegadoBookSourceType.TEXT)
      : LegadoBookSourceType.TEXT;

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
        this.navigateWithManagedWindowTransition('NovelReaderPage', params);
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
    const sourceType = sourceId.length > 0
      ? (this.novelSourceManager.getSource(sourceId)?.bookSourceType ?? LegadoBookSourceType.TEXT)
      : LegadoBookSourceType.TEXT;
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
      AppStorage.setOrCreate('ReadAloudPlayerReturnHostPage', 'UnifiedDetailPage');
      AppStorage.setOrCreate('ReadAloudPlayerReturnDisplayMode', WindowManager.getCurrentMode());
      AppStorage.setOrCreate('ReadAloudPlayerOpeningAt', Date.now());
      logger.info(TAG, `开始听书直达播放器页: 章节索引=${chapterIndex}, 图源=${sourceId}, 章节地址=${params.chapterUrl}`);
      this.navigateWithManagedWindowTransition('ReadAloudPlayerPage', params);
      return;
    }
    params.autoStartReadAloud = true;
    params.autoOpenReadAloudPlayer = true;
    this.navigateWithManagedWindowTransition('NovelReaderPage', params);
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
    this.navigateWithManagedWindowTransition('NovelReaderPage', params);
  }

  /**
   * 切换收藏状态
   */
  /**
   * Toggle favorite state.
   */
  private async toggleFavorite(): Promise<void> {
    if (!this.content) {
      return;
    }

    const previousState = this.isFavorite;
    const targetState = !previousState;
    try {
      await this.setFavoriteStatus(targetState);
      promptAction.showToast({
        message: targetState ? 'Added to favorites' : 'Removed from favorites',
        duration: 1500
      });
    } catch (error) {
      logger.error(TAG, `Failed to toggle favorite state: ${String(error)}`);
      this.isFavorite = previousState;
      this.content.isFavorite = previousState;
      promptAction.showToast({
        message: 'Operation failed',
        duration: 1500
      });
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
    if (!this.content) return '';
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
    const fetcher: PageListFetcher = async (chapterId: string, mangaId: string): Promise<string[]> => {
      const pages = await dataManager.getOnlineChapterPages(chapterId);
      return pages.map(p => p.imageUrl);
    };
    return fetcher;
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
    if (this.isLocalTxtNovelEBookContent()) {
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
    if (!this.supportsReadAloudCacheSection()) {
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
    animateTo({ duration: 300, curve: Curve.EaseInOut }, () => {
      this.isReadAloudCacheExpanded = !this.isReadAloudCacheExpanded;
    });
  }

  private async loadReadAloudCacheSummary(showToastOnError: boolean = false): Promise<void> {
    if (!this.supportsReadAloudCacheSection()) {
      this.readAloudCacheSummary = null;
      this.isReadAloudCacheLoading = false;
      return;
    }
    this.isReadAloudCacheLoading = true;
    try {
      this.readAloudCacheSummary = await this.remoteReadAloudCacheService.inspectBookCache(this.content);
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
      if (showToastOnError) {
        promptAction.showToast({ message: '加载听书缓存失败', duration: 1400 });
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
    if (this.isCurrentNovelAudioSource()) {
      this.openCacheDialogFromDetail('read_aloud_cache_section');
      return;
    }
    if (!this.supportsReadAloudCacheSection()) {
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
    this.showReadAloudCacheDialog = true;
    animateTo({
      duration: 260,
      curve: Curve.EaseOut
    }, () => {
      this.readAloudCacheDialogOpacity = 1;
      this.readAloudCacheDialogScale = 1;
      this.readAloudCacheDialogTranslateY = 0;
    });
  }

  private handleReadAloudCacheDialogTabChange(index: number): void {
    if (this.readAloudCacheDialogActiveTab === index) {
      return;
    }
    animateTo({ duration: 220, curve: Curve.EaseInOut }, () => {
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
    animateTo({
      duration: 180,
      curve: Curve.EaseIn
    }, () => {
      this.readAloudCacheDialogOpacity = 0;
      this.readAloudCacheDialogScale = 0.96;
      this.readAloudCacheDialogTranslateY = 12;
    });
    setTimeout(() => {
      this.showReadAloudCacheDialog = false;
    }, 200);
  }

  private async loadReadAloudCacheManageDetail(showToastOnError: boolean = false): Promise<void> {
    if (!this.supportsReadAloudCacheSection()) {
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
        promptAction.showToast({ message: '加载听书缓存管理明细失败', duration: 1400 });
      }
    } finally {
      if (requestToken === this.readAloudCacheManageLoadToken) {
        this.isReadAloudCacheManageLoading = false;
      }
    }
  }

  private selectReadAloudCacheManageChapter(chapterIndex: number): void {
    animateTo({ duration: 220, curve: Curve.EaseInOut }, () => {
      this.readAloudCacheManageChapterIndex = Math.max(0, chapterIndex);
      this.readAloudCacheManageDetail = null;
      this.readAloudCacheManageSelectedTargetIndex = -1;
      this.readAloudCacheManageBlockedSuggestionKeys = new Set();
      this.readAloudCacheManageStatusMessage = '';
    });
    void this.loadReadAloudCacheManageDetail();
  }

  private selectReadAloudCacheManageTarget(segmentIndex: number): void {
    animateTo({ duration: 180, curve: Curve.EaseOut }, () => {
      this.readAloudCacheManageSelectedTargetIndex = this.readAloudCacheManageSelectedTargetIndex === segmentIndex ? -1 : segmentIndex;
    });
  }

  private toggleReadAloudCacheManageSection(section: 'chapter' | 'target' | 'source'): void {
    animateTo({ duration: 280, curve: Curve.EaseInOut }, () => {
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
      promptAction.showToast({ message: '已完成分段匹配', duration: 1400 });
    } catch (error) {
      logger.error(TAG, `匹配听书分段失败: target=${targetSegmentIndex}, error=${String(error)}`);
      this.readAloudCacheManageStatusMessage = '分段匹配失败';
      promptAction.showToast({ message: '分段匹配失败', duration: 1400 });
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
      promptAction.showToast({ message: '当前没有可直接采用的建议槽位', duration: 1400 });
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
    animateTo({ duration: 220, curve: Curve.EaseInOut }, () => {
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
      promptAction.showToast({ message: '已删除分段缓存记录', duration: 1400 });
    } catch (error) {
      logger.error(TAG, `删除听书分段失败: segment=${segment.segmentIndex}, error=${String(error)}`);
      this.readAloudCacheManageStatusMessage = '删除分段失败';
      promptAction.showToast({ message: '删除分段失败', duration: 1400 });
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
      promptAction.showToast({ message: '已保存当前书籍远程 TTS 设置', duration: 1500 });
    } catch (error) {
      logger.error(TAG, `保存当前远程TTS设置失败: ${String(error)}`);
      promptAction.showToast({ message: '保存当前远程 TTS 设置失败', duration: 1500 });
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
      promptAction.showToast({ message: `已缓存 ${chapterTitle}`, duration: 1400 });
    } catch (error) {
      logger.error(TAG, `单章听书缓存失败: chapter=${chapterIndex}, error=${String(error)}`);
      promptAction.showToast({ message: '当前章节缓存失败', duration: 1400 });
    }
  }

  private async clearReadAloudCacheChapter(chapterIndex: number): Promise<void> {
    if (this.isReadAloudPrecaching) {
      return;
    }
    try {
      await this.remoteReadAloudCacheService.clearChapterCache(this.content, chapterIndex);
      await this.loadReadAloudCacheSummary();
      promptAction.showToast({ message: `已清理第 ${chapterIndex + 1} 章听书缓存`, duration: 1400 });
    } catch (error) {
      logger.error(TAG, `清理章节听书缓存失败: chapter=${chapterIndex}, error=${String(error)}`);
      promptAction.showToast({ message: '清理章节缓存失败', duration: 1400 });
    }
  }

  private async clearReadAloudCacheBook(): Promise<void> {
    if (this.isReadAloudPrecaching) {
      return;
    }
    try {
      await this.remoteReadAloudCacheService.clearBookCache(this.content);
      await this.loadReadAloudCacheSummary();
      promptAction.showToast({ message: '已清理当前小说听书缓存', duration: 1400 });
    } catch (error) {
      logger.error(TAG, `清理当前小说听书缓存失败: ${String(error)}`);
      promptAction.showToast({ message: '清理听书缓存失败', duration: 1400 });
    }
  }

  private async startReadAloudCacheTaskFromDialog(): Promise<void> {
    const targetIndexes = this.getSelectedReadAloudChapterIndexes();
    if (targetIndexes.length <= 0) {
      promptAction.showToast({ message: '请先选择要缓存的章节', duration: 1400 });
      return;
    }
    try {
      await this.runReadAloudPrecacheTask(targetIndexes, true);
      await this.loadReadAloudCacheSummary();
      promptAction.showToast({ message: `已完成 ${targetIndexes.length} 章听书缓存`, duration: 1500 });
    } catch (error) {
      logger.error(TAG, `批量听书缓存失败: ${String(error)}`);
      promptAction.showToast({ message: '听书缓存任务失败', duration: 1500 });
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
    return this.isLocalTxtNovelEBookContent()
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
    animateTo({ duration: 300, curve: Curve.EaseInOut }, () => {
      this.isChapterListExpanded = !this.isChapterListExpanded;
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
      promptAction.showToast({ message: '已复制', duration: 1500 });
    } catch (error) {
      logger.error(TAG, `复制到剪贴板失败: ${String(error)}`);
      promptAction.showToast({ message: '复制失败', duration: 1500 });
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
          sourceName: this.content.sourceName,
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
      const items: ShelfContentItem[] = [];

      for (let i = 0; i < shelfItems.length && items.length < SHELF_CONTENT_MAX_COUNT; i++) {
        const catItem = shelfItems[i];

        // 跳过当前内容
        if (catItem.itemId === currentId) continue;

        try {
          switch (catItem.contentType) {
            case ContentType.MANGA: {
              const comic = await this.dataManager.getComicById(catItem.itemId);
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
    return this.localCoverPath || this.content?.coverUrl || '';
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
            SymbolGlyph($r('sys.symbol.text_book_closed'))
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
        Text(this.stripHtmlTags(this.content?.title || '加载中...'))
          .fontSize(20)
          .fontWeight(FontWeight.Bold)
          .fontFamily(this.appFontFamily)
          .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_primary', this.themeState.currentTheme))
          .maxLines(2)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
          .width('100%')
          .onClick(() => {
            this.navigateToSearch(this.content?.title || '');
          })

        if (this.content?.author) {
          Text(this.stripHtmlTags(this.content.author))
            .fontSize(14)
            .fontFamily(this.appFontFamily)
            .fontColor(ThemeAwareHelper.getTestManagementThemedColor('accent_primary', this.themeState.currentTheme))
            .maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
            .width('100%')
            .onClick(() => {
              this.navigateToSearch(this.content?.author || '');
            })
        } else {
          Text('')
            .fontSize(14)
            .width('100%')
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

        if (this.content?.sourceName) {
          Text(`来源: ${this.content.sourceName}`)
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
                SymbolGlyph($r('sys.symbol.books_vertical_fill'))
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
              SymbolGlyph($r('sys.symbol.text_book_closed'))
                .fontSize(14)
                .fontColor([Color.White])
              Text(this.getReadButtonLabel())
                .fontSize(14)
                .fontFamily(this.appFontFamily)
                .fontColor(Color.White)
            }
          }
            .backgroundColor(ThemeAwareHelper.getTestManagementThemedColor('accent_primary', this.themeState.currentTheme))
            .height(36)
            .width('100%')
            .id('guide_unified_detail_primary_action')
            .onClick(() => this.continueReading())

          if (this.canShowReadAloudButton()) {
            Button() {
              Row({ space: 6 }) {
                SymbolGlyph($r('sys.symbol.Celia'))
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
    .id('guide_unified_detail_header')
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

  private getDialogShadowColor(): string {
    return SettingsGlassStyleHelper.getSheetShadowColor();
  }

  private getDialogMaskColor(): ResourceColor {
    return DialogSurfaceStyleHelper.getPopupMaskColor();
  }

  private getDialogMaskBlurStyle(): BlurStyle {
    return DialogSurfaceStyleHelper.getPopupMaskBlurStyle();
  }

  private getDialogChromeTopEdgeColor(): ResourceColor {
    return this.themeState.currentTheme === ThemeType.DARK
      ? 'rgba(255, 255, 255, 0.18)'
      : 'rgba(255, 255, 255, 0.58)';
  }

  private getDialogChromeBottomEdgeColor(): ResourceColor {
    return this.themeState.currentTheme === ThemeType.DARK
      ? 'rgba(154, 196, 255, 0.08)'
      : 'rgba(126, 166, 220, 0.10)';
  }

  private getDialogChromeGradient(): LinearGradient {
    return this.themeState.currentTheme === ThemeType.DARK
      ? {
          angle: 145,
          colors: [
            ['rgba(220, 236, 255, 0.10)', 0],
            ['rgba(54, 78, 116, 0.04)', 0.32],
            ['rgba(12, 18, 28, 0.03)', 0.76],
            ['rgba(154, 196, 255, 0.06)', 1]
          ]
        }
      : {
          angle: 145,
          colors: [
            ['rgba(255, 255, 255, 0.38)', 0],
            ['rgba(222, 236, 252, 0.16)', 0.30],
            ['rgba(202, 222, 246, 0.08)', 0.72],
            ['rgba(255, 255, 255, 0.16)', 1]
          ]
        };
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

  @Builder
  private buildDialogChrome(radius?: number) {
    Column()
      .width('100%')
      .height(1)
      .backgroundColor(this.getDialogChromeTopEdgeColor())

    Column()
      .width('100%')
      .height(1)
      .align(Alignment.Bottom)
      .backgroundColor(this.getDialogChromeBottomEdgeColor())
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
    animateTo({ duration: 220, curve: Curve.EaseInOut }, () => {
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
    animateTo({ duration: 240, curve: Curve.EaseInOut }, () => {
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

          Text(this.stripHtmlTags(this.content?.description || '暂无简介'))
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
    .id('guide_unified_detail_description')
  }


  @Builder
  buildActionBar() {
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
                SymbolGlyph($r('sys.symbol.worldclock_fill_1'))
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
              void this.openNovelSettings();
            } else {
              this.openEBookSettings();
            }
          })

          Button() {
            Row({ space: 6 }) {
              SymbolGlyph($r('sys.symbol.Celia'))
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
            void this.openNovelSettings();
          })

          Button() {
            Row({ space: 6 }) {
              SymbolGlyph($r('sys.symbol.Celia'))
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
                .fontColor([this.isSearchingSource
                  ? ThemeAwareHelper.getTestManagementThemedColor('text_muted', this.themeState.currentTheme)
                  : ThemeAwareHelper.getTestManagementThemedColor('accent_green', this.themeState.currentTheme)])
              Text(this.isSearchingSource ? '搜索中...' : '换源')
                .fontSize(14)
                .fontFamily(this.appFontFamily)
                .fontColor(this.isSearchingSource
                  ? ThemeAwareHelper.getTestManagementThemedColor('text_muted', this.themeState.currentTheme)
                  : ThemeAwareHelper.getTestManagementThemedColor('accent_green', this.themeState.currentTheme))
            }
          }
          .height(36)
          .padding({ left: 16, right: 16 })
          .backgroundColor(ThemeAwareHelper.getTestManagementThemedColor('comp_background_tertiary', this.themeState.currentTheme))
          .borderRadius(18)
          .enabled(!this.isSearchingSource)
          .onClick(() => this.openChangeSourceDialog())
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
    .id('guide_unified_detail_action_bar')
  }

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
      .id('guide_unified_detail_tracking')
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
    animateTo({ duration: 220, curve: Curve.EaseInOut }, () => {
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
        contentPadding: 0,
        dialogRadius: 26,
        zIndexValue: 121,
        useMaskBlur: true,
        maskBlurStyle: this.getDialogMaskBlurStyle(),
        maskColor: this.getDialogMaskColor()
      }) {
        Stack({ alignContent: Alignment.TopStart }) {
          this.buildDialogChrome(26)
          Column({ space: 16 }) {
            Row() {
              Text(this.trackingRule !== null ? '调整更新提醒' : '开启更新提醒')
                .fontSize(18)
                .fontWeight(FontWeight.Bold)
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
              this.buildTrackingSettingsTabButton('基础', $r('sys.symbol.bookshelf_badge_checkmark'), 0)
              this.buildTrackingSettingsTabButton('筛选', $r('sys.symbol.bookshelf_badge_checkmark'), 1)
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
          .padding(20)
          .scale({ x: this.trackingDialogScale, y: this.trackingDialogScale })
          .translate({ y: this.trackingDialogTranslateY })
          .opacity(this.trackingDialogOpacity)
          .borderRadius(26)
          .clip(true)
          .onClick(() => {
          })
        }
      }
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
        promptAction.showToast({
          message: newNSFW ? '已标记为NSFW' : '已取消NSFW标记',
          duration: 1500
        });
        logger.info(TAG, `NSFW标记更新成功: ${targetContentId}, isNSFW=${newNSFW}`);
      } else {
        promptAction.showToast({
          message: 'NSFW标记更新失败',
          duration: 1500
        });
        logger.error(TAG, `NSFW标记更新失败: ${targetContentId}`);
      }
    } catch (error) {
      logger.error(TAG, `切换NSFW标记异常: ${String(error)}`);
      promptAction.showToast({
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
            Row() {
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

  @Builder
  buildReadAloudCacheSection() {
    if (this.supportsReadAloudCacheSection()) {
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
              SymbolGlyph($r('sys.symbol.book'))
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
                SymbolGlyph($r('sys.symbol.book'))
                  .fontSize(16)
                  .fontColor([ThemeAwareHelper.getTestManagementThemedColor('accent_primary', this.themeState.currentTheme)])
                Column({ space: 2 }) {
                  Text('听书缓存')
                    .fontSize(14)
                    .fontWeight(FontWeight.Medium)
                    .fontFamily(this.appFontFamily)
                    .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_primary', this.themeState.currentTheme))
                  Text(this.isLocalTxtNovelEBookContent() ? '本地 TXT 电子书' : '远程 TTS 章节缓存')
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
    this.cacheConfirmTitle = '清理缓存';
    this.cacheConfirmMessage = `确定要清理此${contentTypeName}的所有缓存吗？\n\n缓存大小: ${sizeText}\n${cachedLabel}: ${this.cacheStats.cachedChapterCount}章\n\n${restoreTip}`;
    this.cacheConfirmActionLabel = '清理';
    this.cacheConfirmActionKind = 'danger';
    this.cacheConfirmPendingAction = 'clear_content';
    this.isCacheConfirmDialogVisible = true;
    animateTo({ duration: 260, curve: curves.springMotion(0.6, 0.9) }, () => {
      this.cacheConfirmDialogOpacity = 1;
      this.cacheConfirmDialogScale = 1;
      this.cacheConfirmDialogTranslateY = 0;
    });
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
        promptAction.showToast({ message: '缓存已清理', duration: 2000 });
        await this.loadCacheStatus();
      } else {
        promptAction.showToast({ message: '清理失败', duration: 2000 });
      }
    } catch (error) {
      logger.error(TAG, `清理缓存失败: ${String(error)}`);
      promptAction.showToast({ message: '清理失败', duration: 2000 });
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
              SymbolGlyph($r('sys.symbol.heart_square_stack_fill'))
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
                  animateTo({ duration: 300, curve: Curve.EaseInOut }, () => {
                    this.isShelfContentExpanded = !this.isShelfContentExpanded;
                  });
                })
            }
          }
          .width('100%')
          .onClick(() => {
            if (this.shelfContentItems.length > 0) {
              animateTo({ duration: 300, curve: Curve.EaseInOut }, () => {
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
                          animateTo({ duration: 250, curve: Curve.EaseInOut }, () => {
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
                              SymbolGlyph($r('sys.symbol.text_book_closed'))
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
                  animateTo({ duration: 300, curve: Curve.EaseInOut }, () => {
                    this.isRecommendationsExpanded = !this.isRecommendationsExpanded;
                  });
                })
            }
          }
          .width('100%')
          .onClick(() => {
            if (this.recommendedItems.length > 0) {
              animateTo({ duration: 300, curve: Curve.EaseInOut }, () => {
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
                          SymbolGlyph($r('sys.symbol.text_book_closed'))
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
                  this.chapterSortOrder = this.chapterSortOrder === ChapterSortOrder.ASCENDING
                    ? ChapterSortOrder.DESCENDING
                    : ChapterSortOrder.ASCENDING;
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
              } else {
                if (this.content?.contentType === UnifiedContentType.MANGA) {
                  this.buildMangaChapterList()
                } else if (this.content?.contentType === UnifiedContentType.NOVEL) {
                  this.buildNovelChapterList()
                } else if (this.content?.contentType === UnifiedContentType.EBOOK) {
                  this.buildEBookChapterList()
                }
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
    .id('guide_unified_detail_chapter_section')
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
      promptAction.showToast({ message: '缺少图源信息', duration: 2000 });
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
        onBasicInfoLoaded: (manga: Manga, isFavorite: boolean) => {
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
            promptAction.showToast({ message: `新增 ${addedCount} 个新章节`, duration: 2000 });
          } else {
            promptAction.showToast({ message: '信息已更新', duration: 1500 });
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
                sourceId
              );
            }
          }
        },
        onError: (error: string) => {
          logger.error(TAG, `[重新获取] 失败: ${error}`);
          promptAction.showToast({ message: `获取失败: ${error}`, duration: 2000 });
        }
      };

      await this.mangaDetailLoader.loadMangaDetailWithProgress(loadParams, progressCallback);
      logger.info(TAG, '重新获取在线漫画信息完成');
    } catch (error) {
      logger.error(TAG, `重新获取在线漫画信息异常: ${String(error)}`);
      promptAction.showToast({ message: `获取失败: ${String(error)}`, duration: 2000 });
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
          await this.dataManager.updateComicCoverUrl(mangaId, newCoverUrl);
          promptAction.showToast({ message: '封面已更新', duration: 1500 });
        } else {
          promptAction.showToast({ message: '获取封面失败', duration: 2000 });
        }
      }
    } catch (error) {
      logger.error(TAG, `重新获取封面失败: ${String(error)}`);
      promptAction.showToast({ message: `获取失败: ${String(error)}`, duration: 2000 });
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
      promptAction.showToast({ message: '无法获取网页地址', duration: 2000 });
      return;
    }

    try {
      const sourceId = Number(this.pageParams.sourceId);
      const mangaId = this.pageParams.contentId;
      const comicInfo = await this.dataManager.getComicById(mangaId);
      const externalId = comicInfo?.externalId || mangaId;
      const sourceInfo: SourceInfo | null = await this.getSourceInfoById(sourceId);
      if (!sourceInfo || !sourceInfo.baseUrl) {
        promptAction.showToast({ message: '无法获取图源信息', duration: 2000 });
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
      promptAction.showToast({ message: `打开失败: ${String(error)}`, duration: 2000 });
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

  private async openNovelSettings(): Promise<void> {
    if (!this.content || !this.pageParams || !this.canUseNovelStyleSettingsDialog()) {
      return;
    }
    await this.loadNovelSettingsDialogConfig();
    await this.loadNovelRuleConfigurations();
    if (this.isLocalImportedEBookContent()) {
      this.initializeEBookInfoEditState();
    }
    logger.info(
      TAG,
      `打开小说设置: contentType=${this.content.contentType}, online=${this.isOnlineNovelContent()}, prefetchEnabled=${this.novelEnableReadWhileDownload}, prefetchCount=${this.novelDefaultLoadChapters}`
    );
    this.novelSettingsActiveTab = 0;
    this.showNovelSettingsDialog = true;
    animateTo({
      duration: 260,
      curve: Curve.EaseOut
    }, () => {
      this.novelSettingsDialogOpacity = 1;
      this.novelSettingsDialogScale = 1;
      this.novelSettingsDialogTranslateY = 0;
    });
  }

  private closeNovelSettingsDialog(): void {
    animateTo({
      duration: 180,
      curve: Curve.EaseIn
    }, () => {
      this.novelSettingsDialogOpacity = 0;
      this.novelSettingsDialogScale = 0.96;
      this.novelSettingsDialogTranslateY = 12;
    });
    setTimeout(() => {
      this.showNovelSettingsDialog = false;
    }, 200);
  }

  private cloneRuleIdList(source: string[]): string[] {
    const result: string[] = [];
    for (const id of source) {
      result.push(id);
    }
    return result;
  }

  private areSameRuleIdList(a: string[], b: string[]): boolean {
    if (a.length !== b.length) {
      return false;
    }
    for (const id of a) {
      if (b.indexOf(id) < 0) {
        return false;
      }
    }
    return true;
  }

  private refreshNovelRuleDirtyState(): void {
    this.novelDirectoryRulesDirty = !this.areSameRuleIdList(this.novelSelectedTocRuleIds, this.novelAppliedTocRuleIds);
    this.novelReplaceRulesDirty = !this.areSameRuleIdList(this.novelSelectedReplaceRuleIds, this.novelAppliedReplaceRuleIds);
  }

  private hasPendingNovelSettingChanges(): boolean {
    return this.novelDirectoryRulesDirty ||
      this.novelReplaceRulesDirty ||
      (this.isLocalImportedEBookContent() && this.ebookInfoDirty);
  }

  private async applyPendingNovelSettingsChanges(): Promise<void> {
    if (this.novelDirectoryRulesDirty) {
      await this.applyNovelDirectoryParsingSelection();
    }
    if (this.novelReplaceRulesDirty) {
      await this.applyNovelReplaceRulesSelection();
    }
    if (this.isLocalImportedEBookContent() && this.ebookInfoDirty) {
      await this.saveEBookInfoEdit();
    }
  }

  private async requestCloseNovelSettingsDialog(afterClose?: () => void): Promise<void> {
    if (!this.showNovelSettingsDialog) {
      if (afterClose) {
        afterClose();
      }
      return;
    }
    if (this.isApplyingNovelDirectoryParsing || this.isApplyingNovelReplaceRules || this.isSavingEBookInfo) {
      return;
    }
    if (!this.hasPendingNovelSettingChanges()) {
      this.closeNovelSettingsDialog();
      if (afterClose) {
        afterClose();
      }
      return;
    }
    this.novelSettingsCloseAfterClose = afterClose;
    this.isNovelSettingsCloseConfirmDialogVisible = true;
    animateTo({ duration: 240, curve: curves.springMotion(0.65, 0.92) }, () => {
      this.novelSettingsCloseConfirmOpacity = 1;
      this.novelSettingsCloseConfirmScale = 1;
      this.novelSettingsCloseConfirmTranslateY = 0;
    });
  }

  private isOnlineNovelContent(): boolean {
    if (!this.content || this.content.contentType !== UnifiedContentType.NOVEL) {
      return false;
    }
    return !this.content.isLocal && !!this.content.sourceId;
  }

  private pushUniqueRuleScopeId(target: string[], scopeId: string): void {
    if (scopeId.length <= 0 || target.indexOf(scopeId) >= 0) {
      return;
    }
    target.push(scopeId);
  }

  private getCurrentNovelRuleScopeIds(): string[] {
    const scopeIds: string[] = [];
    if (!this.content) {
      return scopeIds;
    }
    if (this.content.contentType === UnifiedContentType.NOVEL) {
      const sourceId = this.content.sourceId || this.pageParams?.sourceId || 'local';
      this.pushUniqueRuleScopeId(scopeIds, this.getNovelCacheBookId(sourceId, this.content.id));
      return scopeIds;
    }
    if (this.isLocalImportedEBookContent()) {
      const ebook = EBookAdapter.getOriginalEBook(this.content);
      if (!ebook) {
        return scopeIds;
      }
      if (ebook.format === EBookFormat.TXT) {
        this.pushUniqueRuleScopeId(scopeIds, buildLocalTextNovelBookId(ebook.id));
      }
      this.pushUniqueRuleScopeId(scopeIds, ebook.id);
    }
    return scopeIds;
  }

  private getCurrentNovelRuleScopeId(): string {
    const scopeIds = this.getCurrentNovelRuleScopeIds();
    if (scopeIds.length <= 0) {
      return '';
    }
    return scopeIds[0];
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
      const parsed = JSON.parse(rawValue) as Array<string>;
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
      logger.warn(TAG, `解析规则ID列表失败: ${String(error)}`);
      return [];
    }
  }

  private isRuleSelected(selectedIds: string[], ruleId: string): boolean {
    return selectedIds.indexOf(ruleId) >= 0;
  }

  private toggleRuleSelection(selectedIds: string[], ruleId: string, enabled: boolean): string[] {
    const result: string[] = [];
    for (const id of selectedIds) {
      if (id !== ruleId) {
        result.push(id);
      }
    }
    if (enabled) {
      result.push(ruleId);
    }
    return result;
  }

  private getReplaceRuleScopeLabel(scope: ReplaceScope): string {
    if (scope === ReplaceScope.TITLE) {
      return '标题';
    }
    if (scope === ReplaceScope.CONTENT) {
      return '内容';
    }
    return '全部';
  }

  private getReplaceRuleSourceLabel(rule: ReplaceRule): string {
    if (!rule.sourceIds || rule.sourceIds.length === 0) {
      return '全部书源';
    }
    return `指定书源(${rule.sourceIds.length})`;
  }

  private async loadNovelRuleConfigurations(): Promise<void> {
    try {
      const tocRuleManager = getNovelTxtTocRuleManager();
      await tocRuleManager.initialize();
      this.novelTocRules = tocRuleManager.getAllRules();

      const replaceRuleManager = NovelReplaceRuleManager.getInstance();
      await replaceRuleManager.initialize();
      await replaceRuleManager.refreshRules();
      this.novelReplaceRules = replaceRuleManager.getAllRules();

      const scopeIds = this.getCurrentNovelRuleScopeIds();
      const primaryScopeId = scopeIds.length > 0 ? scopeIds[0] : '';
      let scopedTocRuleIds: string[] = [];
      let scopedReplaceRuleIds: string[] = [];
      let hasScopedTocRuleIds = false;
      let hasScopedReplaceRuleIds = false;
      if (scopeIds.length > 0) {
        const context = this.getUIContext()?.getHostContext() as common.UIAbilityContext;
        const store = await preferences.getPreferences(context, NOVEL_BOOK_RULE_SETTINGS_STORE);
        for (const scopeId of scopeIds) {
          if (!hasScopedTocRuleIds) {
            const rawTocRuleIds = await store.get(this.buildBookTocRuleKey(scopeId), '') as string;
            if (rawTocRuleIds.length > 0) {
              hasScopedTocRuleIds = true;
              scopedTocRuleIds = this.parseRuleIdArray(rawTocRuleIds);
            }
          }
          if (!hasScopedReplaceRuleIds) {
            const rawReplaceRuleIds = await store.get(this.buildBookReplaceRuleKey(scopeId), '') as string;
            if (rawReplaceRuleIds.length > 0) {
              hasScopedReplaceRuleIds = true;
              scopedReplaceRuleIds = this.parseRuleIdArray(rawReplaceRuleIds);
            }
          }
          if (hasScopedTocRuleIds && hasScopedReplaceRuleIds) {
            break;
          }
        }
      }
      if (!hasScopedTocRuleIds) {
        scopedTocRuleIds = this.novelTocRules.filter((rule: TxtTocRule) => rule.enabled).map((rule: TxtTocRule) => rule.id);
      }
      if (!hasScopedReplaceRuleIds) {
        scopedReplaceRuleIds = this.novelReplaceRules.filter((rule: ReplaceRule) => rule.enabled).map((rule: ReplaceRule) => rule.id);
      }
      this.novelSelectedTocRuleIds = scopedTocRuleIds;
      this.novelSelectedReplaceRuleIds = scopedReplaceRuleIds;
      this.novelAppliedTocRuleIds = this.cloneRuleIdList(this.novelSelectedTocRuleIds);
      this.novelAppliedReplaceRuleIds = this.cloneRuleIdList(this.novelSelectedReplaceRuleIds);
      this.novelDirectoryRulesDirty = false;
      this.novelReplaceRulesDirty = false;
      logger.info(
        TAG,
        `小说规则配置已加载: scopeId=${primaryScopeId}, scopeCount=${scopeIds.length}, tocRules=${this.novelSelectedTocRuleIds.length}, replaceRules=${this.novelSelectedReplaceRuleIds.length}`
      );
    } catch (error) {
      logger.warn(TAG, `加载小说规则配置失败: ${String(error)}`);
      this.novelTocRules = [];
      this.novelReplaceRules = [];
      this.novelSelectedTocRuleIds = [];
      this.novelSelectedReplaceRuleIds = [];
      this.novelAppliedTocRuleIds = [];
      this.novelAppliedReplaceRuleIds = [];
      this.novelDirectoryRulesDirty = false;
      this.novelReplaceRulesDirty = false;
    }
  }

  private async loadNovelSettingsDialogConfig(): Promise<void> {
    try {
      const context = this.getUIContext()?.getHostContext() as common.UIAbilityContext;
      const store = await preferences.getPreferences(context, NOVEL_SETTINGS_STORE);
      this.novelEnableReadWhileDownload = await store.get('enableReadWhileDownload', true) as boolean;
      this.novelDefaultLoadChapters = Number(await store.get('defaultLoadChapters', 50));
      this.novelEnableDirectoryParsing = await store.get(NOVEL_SETTING_ENABLE_DIRECTORY_PARSING, true) as boolean;
      this.novelEnableReplaceRules = await store.get(NOVEL_SETTING_ENABLE_REPLACE_RULES, true) as boolean;
      this.novelDirectoryParsingSelection = this.novelEnableDirectoryParsing;
      this.novelReplaceRulesSelection = this.novelEnableReplaceRules;
      logger.info(
        TAG,
        `加载小说设置: prefetchEnabled=${this.novelEnableReadWhileDownload}, prefetchCount=${this.novelDefaultLoadChapters}, directory=${this.novelEnableDirectoryParsing}, replace=${this.novelEnableReplaceRules}`
      );
      if (!Number.isFinite(this.novelDefaultLoadChapters) || this.novelDefaultLoadChapters < 0) {
        this.novelDefaultLoadChapters = 50;
      }
    } catch (error) {
      logger.warn(TAG, `加载小说设置对话框配置失败: ${String(error)}`);
      this.novelEnableReadWhileDownload = true;
      this.novelDefaultLoadChapters = 50;
      this.novelEnableDirectoryParsing = true;
      this.novelEnableReplaceRules = true;
      this.novelDirectoryParsingSelection = true;
      this.novelReplaceRulesSelection = true;
    }
  }

  private async saveNovelSettingValue(key: string, value: number | boolean): Promise<boolean> {
    try {
      const context = this.getUIContext()?.getHostContext() as common.UIAbilityContext;
      const store = await preferences.getPreferences(context, NOVEL_SETTINGS_STORE);
      await store.put(key, value);
      await store.flush();
      logger.info(TAG, `小说设置已保存: ${key}=${String(value)}`);
      return true;
    } catch (error) {
      logger.error(TAG, `保存小说设置失败: key=${key}, error=${String(error)}`);
      promptAction.showToast({ message: '保存设置失败', duration: 1200 });
      return false;
    }
  }

  private getNovelPrefetchChapterOptions(): number[] {
    return [10, 20, 50, 100, 200, 9999];
  }

  private formatNovelPrefetchChapterCount(value: number): string {
    if (value >= 9999) {
      return '全部';
    }
    return `${value}章`;
  }

  private onNovelPrefetchChapterCountChange(value: number): void {
    this.novelDefaultLoadChapters = value;
    logger.info(TAG, `小说预下载范围切换: ${value}章`);
    void this.saveNovelSettingValue('defaultLoadChapters', value);
  }

  private async saveBookScopedRuleIds(tocRuleIds: string[], replaceRuleIds: string[]): Promise<boolean> {
    const scopeIds = this.getCurrentNovelRuleScopeIds();
    if (scopeIds.length === 0) {
      return false;
    }
    try {
      const context = this.getUIContext()?.getHostContext() as common.UIAbilityContext;
      const store = await preferences.getPreferences(context, NOVEL_BOOK_RULE_SETTINGS_STORE);
      for (const scopeId of scopeIds) {
        await store.put(this.buildBookTocRuleKey(scopeId), JSON.stringify(tocRuleIds));
        await store.put(this.buildBookReplaceRuleKey(scopeId), JSON.stringify(replaceRuleIds));
      }
      await store.flush();
      logger.info(
        TAG,
        `小说书籍专属规则已保存: scopeIds=${scopeIds.join('|')}, tocRules=${tocRuleIds.length}, replaceRules=${replaceRuleIds.length}`
      );
      return true;
    } catch (error) {
      logger.error(TAG, `保存小说书籍专属规则失败: ${String(error)}`);
      return false;
    }
  }

  private async getScopedRuleIds(scopeId: string, key: string): Promise<string[] | null> {
    if (scopeId.length === 0) {
      return null;
    }
    try {
      const context = this.getUIContext()?.getHostContext() as common.UIAbilityContext;
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

  private async applyNovelDirectoryParsingSelection(): Promise<void> {
    if (this.isApplyingNovelDirectoryParsing || !this.content || this.content.contentType !== UnifiedContentType.NOVEL) {
      return;
    }
    this.isApplyingNovelDirectoryParsing = true;
    try {
      const nextEnabled = true;
      this.novelDirectoryParsingSelection = true;
      const saved = await this.saveNovelSettingValue(NOVEL_SETTING_ENABLE_DIRECTORY_PARSING, nextEnabled);
      if (!saved) {
        return;
      }
      const scopedSaved = await this.saveBookScopedRuleIds(this.novelSelectedTocRuleIds, this.novelSelectedReplaceRuleIds);
      if (!scopedSaved) {
        promptAction.showToast({ message: '保存书籍规则失败', duration: 1400 });
        return;
      }
      this.novelEnableDirectoryParsing = nextEnabled;
      await this.refreshNovelContentByDirectorySetting(nextEnabled, this.novelSelectedTocRuleIds);
      this.novelAppliedTocRuleIds = this.cloneRuleIdList(this.novelSelectedTocRuleIds);
      this.refreshNovelRuleDirtyState();
      logger.info(TAG, `目录解析应用完成: enabled=${nextEnabled}, selectedRules=${this.novelSelectedTocRuleIds.length}`);
      promptAction.showToast({ message: '目录规则已应用并刷新章节', duration: 1400 });
    } catch (error) {
      logger.error(TAG, `应用目录解析规则失败: ${String(error)}`);
      promptAction.showToast({ message: '应用目录解析规则失败', duration: 1400 });
    } finally {
      this.isApplyingNovelDirectoryParsing = false;
    }
  }

  private async applyNovelReplaceRulesSelection(): Promise<void> {
    if (this.isApplyingNovelReplaceRules || !this.content ||
      (this.content.contentType !== UnifiedContentType.NOVEL && !this.isLocalImportedEBookContent())) {
      return;
    }
    this.isApplyingNovelReplaceRules = true;
    try {
      const nextEnabled = true;
      this.novelReplaceRulesSelection = true;
      const saved = await this.saveNovelSettingValue(NOVEL_SETTING_ENABLE_REPLACE_RULES, nextEnabled);
      if (!saved) {
        return;
      }
      const scopedSaved = await this.saveBookScopedRuleIds(this.novelSelectedTocRuleIds, this.novelSelectedReplaceRuleIds);
      if (!scopedSaved) {
        promptAction.showToast({ message: '保存书籍规则失败', duration: 1400 });
        return;
      }
      this.novelEnableReplaceRules = nextEnabled;
      await this.applyReplaceRulesToCurrentNovelContent(nextEnabled, this.novelSelectedReplaceRuleIds);
      this.novelAppliedReplaceRuleIds = this.cloneRuleIdList(this.novelSelectedReplaceRuleIds);
      this.refreshNovelRuleDirtyState();
      logger.info(TAG, `净化规则应用完成: enabled=${nextEnabled}, selectedRules=${this.novelSelectedReplaceRuleIds.length}`);
      promptAction.showToast({ message: '净化规则已应用到当前内容', duration: 1400 });
    } catch (error) {
      logger.error(TAG, `应用净化规则失败: ${String(error)}`);
      promptAction.showToast({ message: '应用净化规则失败', duration: 1400 });
    } finally {
      this.isApplyingNovelReplaceRules = false;
    }
  }

  private openNovelTxtTocRulePage(): void {
    void this.requestCloseNovelSettingsDialog(() => {
      try {
        this.navigateWithManagedWindowTransition('NovelTxtTocRulePage', null);
      } catch (error) {
        logger.error(TAG, `打开TXT目录规则页失败: ${String(error)}`);
      }
    });
  }

  private openNovelReplaceRulePage(): void {
    void this.requestCloseNovelSettingsDialog(() => {
      try {
        this.navigateWithManagedWindowTransition('NovelReplaceRulePage', null);
      } catch (error) {
        logger.error(TAG, `打开净化规则页失败: ${String(error)}`);
      }
    });
  }

  private async refreshNovelContentByDirectorySetting(enableDirectoryParsing: boolean, selectedTocRuleIds: string[]): Promise<void> {
    if (!this.content || this.content.contentType !== UnifiedContentType.NOVEL) {
      return;
    }
    const previousContent = this.content;
    if (enableDirectoryParsing && this.isOnlineNovelContent() && this.content.id) {
      await this.novelCacheManager.clearChapterListCache(this.content.id);
    }
    await this.loadNovelContent();
    await this.applyDirectoryRulesToCurrentContent(enableDirectoryParsing, selectedTocRuleIds);
    if (
      previousContent &&
      previousContent.chapters.length > 0 &&
      (!this.content || this.content.contentType !== UnifiedContentType.NOVEL || this.content.chapters.length === 0)
    ) {
      this.content = previousContent;
      this.isChaptersLoading = false;
      logger.warn(TAG, '目录解析结果为空，已回退到应用前内容');
      promptAction.showToast({ message: '目录解析结果为空，已恢复原目录', duration: 1400 });
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
    const updatedContent: UnifiedContent = {
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
    this.content = updatedContent;
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
    const updatedContent: UnifiedContent = {
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
    this.content = updatedContent;
  }

  private async applyReplaceRulesToCurrentEBookContent(
    enableReplaceRules: boolean,
    selectedRuleIds: string[] | null = null
  ): Promise<void> {
    if (!this.content || !this.isLocalImportedEBookContent()) {
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
    const baseDescription = ebook.metadata?.description || this.content.description;
    const nextDescription = enableReplaceRules
      ? contentProcessor.quickReplace(baseDescription, ReplaceScope.CONTENT, undefined, scopedRuleIds)
      : baseDescription;

    const nextChapters: UnifiedChapter[] = [];
    for (const chapter of this.content.chapters) {
      const originalChapter = EBookAdapter.getOriginalChapter(chapter);
      const baseTitle = originalChapter ? (originalChapter.title || chapter.title) : chapter.title;
      const nextTitle = enableReplaceRules
        ? contentProcessor.processTitle(baseTitle, undefined, scopedRuleIds)
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
    const updatedContent: UnifiedContent = {
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
    this.content = updatedContent;
  }

  private initializeEBookInfoEditState(): void {
    const ebook = this.content ? EBookAdapter.getOriginalEBook(this.content) : null;
    const metadata = ebook?.metadata;
    this.ebookInfoTitle = metadata?.title || this.content?.title || '';
    this.ebookInfoAuthor = metadata?.author || this.content?.author || '';
    this.ebookInfoPublisher = metadata?.publisher || this.content?.publisher || '';
    this.ebookInfoPublishDate = metadata?.publishDate || this.content?.publishDate || '';
    this.ebookInfoIsbn = metadata?.isbn || this.content?.isbn || '';
    this.ebookInfoLanguage = metadata?.language || '';
    this.ebookInfoDescription = metadata?.description || this.content?.description || '';
    this.ebookInfoCoverPath = metadata?.coverImagePath || this.content?.coverUrl || '';
    const tags: string[] = metadata?.tags || this.content?.tags || [];
    this.ebookInfoTagsText = tags.join(', ');
    this.ebookInfoDirty = false;
  }

  private markEBookInfoDirty(): void {
    this.ebookInfoDirty = true;
  }

  private parseEBookInfoTags(tagsText: string): string[] {
    if (!tagsText || tagsText.trim().length === 0) {
      return [];
    }
    return tagsText
      .split(/[,，、]/)
      .map((tag: string) => tag.trim())
      .filter((tag: string) => tag.length > 0);
  }

  private buildEBookMetadataFromInfoDraft(ebook: EBook): EBookMetadata {
    const metadata: EBookMetadata = {
      title: this.ebookInfoTitle.trim(),
      author: this.ebookInfoAuthor.trim(),
      publisher: this.ebookInfoPublisher.trim(),
      publishDate: this.ebookInfoPublishDate.trim(),
      isbn: this.ebookInfoIsbn.trim(),
      language: this.ebookInfoLanguage.trim(),
      description: this.ebookInfoDescription.trim(),
      coverImagePath: this.ebookInfoCoverPath.trim(),
      tags: this.parseEBookInfoTags(this.ebookInfoTagsText),
      rating: ebook.metadata?.rating ?? 0
    };
    return metadata;
  }

  private isNetworkPath(path: string): boolean {
    return path.startsWith('http://') || path.startsWith('https://');
  }

  private syncCurrentContentFromEBookInfo(ebook: EBook, previousCoverPath: string): void {
    if (!this.content) {
      return;
    }
    const metadata = ebook.metadata;
    this.content.title = metadata.title;
    this.content.author = metadata.author;
    this.content.description = metadata.description;
    this.content.coverUrl = metadata.coverImagePath;
    this.content.publisher = metadata.publisher;
    this.content.publishDate = metadata.publishDate;
    this.content.isbn = metadata.isbn;
    this.content.tags = metadata.tags;
    this.coverRefreshKey = Date.now();
    this.localCoverPath = this.isNetworkPath(metadata.coverImagePath) ? '' : metadata.coverImagePath;
    if (previousCoverPath !== metadata.coverImagePath) {
      const ebookPayload: CoverChangedPayload = {
        bookId: ebook.id,
        coverPath: metadata.coverImagePath
      };
      eventBus.publish(GameEvent.EBOOK_COVER_CHANGED, ebookPayload);
    }
  }

  private async saveEBookInfoEdit(): Promise<void> {
    if (this.isSavingEBookInfo || !this.content || !this.isLocalImportedEBookContent()) {
      return;
    }
    const ebook = EBookAdapter.getOriginalEBook(this.content);
    if (!ebook) {
      promptAction.showToast({ message: '未找到电子书数据', duration: 1400 });
      return;
    }
    if (this.ebookInfoTitle.trim().length <= 0) {
      promptAction.showToast({ message: '请输入书名', duration: 1400 });
      return;
    }
    if (this.ebookInfoAuthor.trim().length <= 0) {
      promptAction.showToast({ message: '请输入作者', duration: 1400 });
      return;
    }
    this.isSavingEBookInfo = true;
    try {
      const previousCoverPath = ebook.metadata?.coverImagePath || '';
      ebook.metadata = this.buildEBookMetadataFromInfoDraft(ebook);
      ebook.lastUpdateTime = Date.now();
      await this.ebookDataManager.saveEBook(ebook, { skipReadingSettings: true });
      this.syncCurrentContentFromEBookInfo(ebook, previousCoverPath);
      eventBus.publish(GameEvent.EBOOK_UPDATED, new BasePayload());
      this.ebookInfoDirty = false;
      logger.info(TAG, `本地电子书信息已保存: ${ebook.id}, title=${ebook.metadata.title}`);
      promptAction.showToast({ message: '电子书信息已保存', duration: 1400 });
    } catch (error) {
      logger.error(TAG, `保存电子书信息失败: ${String(error)}`);
      promptAction.showToast({ message: '保存电子书信息失败', duration: 1600 });
    } finally {
      this.isSavingEBookInfo = false;
    }
  }

  private openEBookInfoScraperDialog(): void {
    const config: ScraperDialogConfig = {
      initialKeyword: this.ebookInfoTitle || this.content?.title || '',
      contentType: ScraperContentType.BOOK,
      title: '搜索电子书信息'
    };
    this.ebookInfoScraperDialogController = new CustomDialogController({
      builder: ScraperDialog({
        themeState: this.themeState,
        config: config,
        onConfirm: (result: ScraperDialogResult) => {
          this.applyEBookInfoScraperResult(result);
        },
        onCancel: () => {
          logger.info(TAG, '用户取消电子书信息刮削');
        }
      }),
      autoCancel: true,
      alignment: DialogAlignment.Center,
      customStyle: true
    });
    this.ebookInfoScraperDialogController.open();
  }

  private appendUniqueEBookInfoTags(target: string[], values: string[] | undefined): void {
    if (!values || values.length <= 0) {
      return;
    }
    for (const value of values) {
      const normalized = value.trim();
      if (normalized.length > 0 && target.indexOf(normalized) < 0) {
        target.push(normalized);
      }
    }
  }

  private applyEBookInfoScraperResult(result: ScraperDialogResult): void {
    const metadata = result.metadata;
    logger.info(TAG, `应用电子书刮削结果到编辑字段: ${metadata.title}`);
    if (metadata.title && metadata.title.trim().length > 0) {
      this.ebookInfoTitle = metadata.title.trim();
    }
    if (result.applyAuthor) {
      if (metadata.author && metadata.author.trim().length > 0) {
        this.ebookInfoAuthor = metadata.author.trim();
      } else if (metadata.authors && metadata.authors.length > 0) {
        this.ebookInfoAuthor = metadata.authors.join(', ');
      }
    }
    if (result.applyDescription) {
      const description = metadata.description || metadata.summary || '';
      if (description.trim().length > 0) {
        this.ebookInfoDescription = description.trim();
      }
    }
    if (result.applyPublisher && metadata.publisher && metadata.publisher.trim().length > 0) {
      this.ebookInfoPublisher = metadata.publisher.trim();
    }
    if (metadata.releaseDate && metadata.releaseDate.trim().length > 0) {
      this.ebookInfoPublishDate = metadata.releaseDate.trim();
    }
    if (result.applyTags) {
      const tags: string[] = [];
      this.appendUniqueEBookInfoTags(tags, metadata.genres);
      this.appendUniqueEBookInfoTags(tags, metadata.tags);
      this.appendUniqueEBookInfoTags(tags, metadata.themes);
      if (tags.length > 0) {
        this.ebookInfoTagsText = tags.join(', ');
      }
    }
    if (result.applyCover) {
      const coverPath = metadata.coverUrlLarge || metadata.coverUrl || metadata.coverUrlMedium || metadata.coverUrlSmall || '';
      if (coverPath.trim().length > 0) {
        this.ebookInfoCoverPath = coverPath.trim();
      }
    }
    this.ebookInfoDirty = true;
    promptAction.showToast({ message: '刮削信息已填入，请确认保存', duration: 1400 });
  }

  private showDownloadOptions(): void {
    if (!this.content || this.content.chapters.length === 0) {
      return;
    }

    this.downloadSelectionMode = 'range';
    this.downloadChapterListExpanded = false;

    let firstUncachedIndex = 0;
    for (let i = 0; i < this.content.chapters.length; i++) {
      if (!this.content.chapters[i].isDownloaded) {
        firstUncachedIndex = i;
        break;
      }
    }

    this.downloadRangeStart = firstUncachedIndex;
    this.downloadRangeEnd = this.content.chapters.length - 1;
    this.downloadSelectedChapters = new Set<number>();
    this.showDownloadDialog = true;
    animateTo({
      duration: 260,
      curve: Curve.EaseOut
    }, () => {
      this.downloadDialogOpacity = 1;
      this.downloadDialogScale = 1;
      this.downloadDialogTranslateY = 0;
    });
  }

  private closeDownloadDialog(): void {
    animateTo({
      duration: 180,
      curve: Curve.EaseIn
    }, () => {
      this.downloadDialogOpacity = 0;
      this.downloadDialogScale = 0.96;
      this.downloadDialogTranslateY = 12;
    });
    setTimeout(() => {
      this.showDownloadDialog = false;
    }, 200);
  }

  private toggleChapterSelection(index: number): void {
    if (this.content && this.content.chapters[index]?.isDownloaded) {
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
        if (!this.content.chapters[i]?.isDownloaded) {
          count++;
        }
      }
      return count;
    }
    return this.downloadSelectedChapters.size;
  }

  private async executeDownloadSelected(): Promise<void> {
    if (!this.content) {
      return;
    }

    const selectedCount = this.getSelectedChapterCount();
    if (selectedCount === 0) {
      promptAction.showToast({
        message: this.content.contentType === UnifiedContentType.NOVEL && this.isCurrentNovelAudioSource()
          ? '未选择要缓存的音频章节'
          : '未选择要缓存的章节'
      });
      return;
    }

    this.closeDownloadDialog();
    if (this.content.contentType === UnifiedContentType.NOVEL) {
      await this.downloadSelectedNovelChapters();
    } else if (this.content.contentType === UnifiedContentType.MANGA) {
      await this.downloadSelectedMangaChapters();
    }
  }

  private async downloadSelectedNovelChapters(): Promise<void> {
    if (!this.content) {
      return;
    }

    const sourceId = this.getCurrentNovelSourceId();
    if (!sourceId) {
      promptAction.showToast({ message: '缺少书源信息' });
      return;
    }

    const selectedIndexes: number[] = [];
    if (this.downloadSelectionMode === 'range') {
      for (let i = this.downloadRangeStart; i <= this.downloadRangeEnd; i++) {
        selectedIndexes.push(i);
      }
    } else {
      this.downloadSelectedChapters.forEach((idx: number) => selectedIndexes.push(idx));
      selectedIndexes.sort((a: number, b: number) => a - b);
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
      promptAction.showToast({ message: this.isCurrentNovelAudioSource() ? '无可缓存的章节音频' : '无可缓存的章节' });
      return;
    }

    this.registerDownloadCallback();
    this.isDownloading = true;
    this.downloadProgressCurrent = 0;
    this.downloadProgressTotal = chapters.length;
    this.downloadCurrentChapterTitle = '';

    const novelCacheBookId = this.getNovelCacheBookId(sourceId, this.content.id);
    promptAction.showToast({
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
      promptAction.showToast({
        message: this.isCurrentNovelAudioSource()
          ? '听书缓存任务已创建，后台继续处理中...'
          : '缓存任务已创建，后台继续处理中...'
      });
    } catch (error) {
      logger.error(TAG, `缓存小说选中章节失败: ${String(error)}`);
      promptAction.showToast({ message: `缓存失败: ${String(error)}` });
      this.isDownloading = false;
      this.downloadProgressCurrent = 0;
      this.downloadProgressTotal = 0;
    }
  }

  private async downloadSelectedMangaChapters(): Promise<void> {
    if (!this.content || !this.isOnlineManga()) {
      return;
    }

    const sourceId = Number(this.pageParams?.sourceId);
    if (!sourceId || sourceId <= 0) {
      promptAction.showToast({ message: '缺少图源信息' });
      return;
    }

    const selectedIndexes: number[] = [];
    if (this.downloadSelectionMode === 'range') {
      for (let i = this.downloadRangeStart; i <= this.downloadRangeEnd; i++) {
        selectedIndexes.push(i);
      }
    } else {
      this.downloadSelectedChapters.forEach((idx: number) => selectedIndexes.push(idx));
      selectedIndexes.sort((a: number, b: number) => a - b);
    }

    const chaptersToDownload = selectedIndexes
      .filter((idx: number) => idx < this.content!.chapters.length && !this.content!.chapters[idx].isDownloaded)
      .map((idx: number) => this.content!.chapters[idx]);

    if (chaptersToDownload.length === 0) {
      promptAction.showToast({ message: '选中的章节已全部缓存' });
      return;
    }

    this.registerDownloadCallback();
    this.isDownloading = true;
    this.downloadProgressCurrent = 0;
    this.downloadProgressTotal = chaptersToDownload.length;
    this.downloadCurrentChapterTitle = '';

    promptAction.showToast({ message: `开始缓存 ${chaptersToDownload.length} 章...` });

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
      promptAction.showToast({ message: '缓存任务已创建，后台继续处理中...' });
    } catch (error) {
      logger.error(TAG, `缓存漫画选中章节失败: ${String(error)}`);
      promptAction.showToast({ message: `缓存失败: ${String(error)}` });
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
            void this.loadCacheStatus();
          }
        }
      },
      onComplete: (task: UnifiedDownloadTask) => {
        if (this.content && this.isCurrentContentTask(task)) {
          this.isDownloading = false;
          this.downloadProgressCurrent = 0;
          this.downloadProgressTotal = 0;
          this.downloadCurrentChapterTitle = '';
          void this.loadCacheStatus();
          logger.info(TAG, `缓存完成: ${task.contentTitle}`);
        }
      },
      onError: (task: UnifiedDownloadTask, error: string) => {
        if (this.content && this.isCurrentContentTask(task)) {
          this.isDownloading = false;
          this.downloadCurrentChapterTitle = '';
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
      promptAction.showToast({ message: '漫画缓存已清理' });
      await this.loadCacheStatus();
    } catch (error) {
      promptAction.showToast({ message: `清理漫画缓存失败: ${String(error)}` });
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
      promptAction.showToast({ message: `${this.isCurrentNovelAudioSource() ? '听书缓存' : '小说缓存'}已清理` });
      this.content.chapters.forEach((ch: UnifiedChapter) => {
        ch.isDownloaded = false;
      });
      await this.loadCacheStatus();
    } catch (error) {
      promptAction.showToast({
        message: `${this.isCurrentNovelAudioSource() ? '清理听书缓存失败' : '清理小说缓存失败'}: ${String(error)}`
      });
    }
  }

  private showNovelCacheClearConfirm(): void {
    if (this.isCurrentNovelAudioSource()) {
      this.cacheConfirmTitle = '清理听书缓存';
      this.cacheConfirmMessage = '确定要清理当前小说的听书缓存吗？清理后需要重新缓存才能离线播放。';
    } else {
      this.cacheConfirmTitle = '清理小说缓存';
      this.cacheConfirmMessage = '确定要清理当前小说的章节缓存吗？清理后需要重新缓存才能离线阅读。';
    }
    this.cacheConfirmActionLabel = '清理';
    this.cacheConfirmActionKind = 'danger';
    this.cacheConfirmPendingAction = 'clear_novel';
    this.isCacheConfirmDialogVisible = true;
    animateTo({ duration: 260, curve: curves.springMotion(0.6, 0.9) }, () => {
      this.cacheConfirmDialogOpacity = 1;
      this.cacheConfirmDialogScale = 1;
      this.cacheConfirmDialogTranslateY = 0;
    });
  }

  private showMangaCacheClearConfirm(): void {
    this.cacheConfirmTitle = '清理漫画缓存';
    this.cacheConfirmMessage = '确定要清理当前漫画的章节与页面缓存吗？清理后需要重新缓存才能离线阅读。';
    this.cacheConfirmActionLabel = '清理';
    this.cacheConfirmActionKind = 'danger';
    this.cacheConfirmPendingAction = 'clear_manga';
    this.isCacheConfirmDialogVisible = true;
    animateTo({ duration: 260, curve: curves.springMotion(0.6, 0.9) }, () => {
      this.cacheConfirmDialogOpacity = 1;
      this.cacheConfirmDialogScale = 1;
      this.cacheConfirmDialogTranslateY = 0;
    });
  }

  private hideCacheConfirmDialog(): void {
    animateTo({ duration: 220, curve: Curve.EaseOut }, () => {
      this.cacheConfirmDialogOpacity = 0;
      this.cacheConfirmDialogScale = 0.86;
      this.cacheConfirmDialogTranslateY = 28;
    });
    setTimeout(() => {
      this.isCacheConfirmDialogVisible = false;
      this.cacheConfirmPendingAction = '';
    }, 230);
  }

  private async confirmCacheAction(): Promise<void> {
    const pendingAction = this.cacheConfirmPendingAction;
    this.hideCacheConfirmDialog();
    if (pendingAction === 'clear_content') {
      await this.clearContentCache();
    } else if (pendingAction === 'clear_novel') {
      await this.clearNovelCache();
    } else if (pendingAction === 'clear_manga') {
      await this.clearMangaCache();
    }
  }

  private closeNovelSettingsDialogImmediately(): void {
    this.novelDirectoryRulesDirty = false;
    this.novelReplaceRulesDirty = false;
    this.closeNovelSettingsDialog();
    const afterClose = this.novelSettingsCloseAfterClose;
    this.novelSettingsCloseAfterClose = undefined;
    if (afterClose) {
      afterClose();
    }
  }

  private hideNovelSettingsCloseConfirmDialog(): void {
    animateTo({ duration: 180, curve: Curve.EaseIn }, () => {
      this.novelSettingsCloseConfirmOpacity = 0;
      this.novelSettingsCloseConfirmScale = 0.96;
      this.novelSettingsCloseConfirmTranslateY = 12;
    });
    setTimeout(() => {
      this.isNovelSettingsCloseConfirmDialogVisible = false;
      this.novelSettingsCloseAfterClose = undefined;
    }, 200);
  }

  @Builder
  private buildCacheConfirmDialog() {
    if (this.isCacheConfirmDialogVisible) {
      SourceDialogScaffold({
        themeState: this.themeState,
        onMaskTap: () => this.hideCacheConfirmDialog(),
        dialogWidth: '88%',
        maxWidth: 420,
        contentPadding: 0,
        dialogRadius: 26,
        zIndexValue: 120,
        useMaskBlur: true,
        maskBlurStyle: this.getDialogMaskBlurStyle(),
        maskColor: this.getDialogMaskColor()
      }) {
        Stack({ alignContent: Alignment.TopStart }) {
          this.buildDialogChrome(26)
          Column({ space: 14 }) {
            Text(this.cacheConfirmTitle)
              .fontSize(18)
              .fontWeight(FontWeight.Bold)
              .fontFamily(this.appFontFamily)
              .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_primary', this.themeState.currentTheme))

            Text(this.cacheConfirmMessage)
              .fontSize(13)
              .lineHeight(22)
              .fontFamily(this.appFontFamily)
              .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_secondary', this.themeState.currentTheme))
              .width('100%')

            Row({ space: 10 }) {
              Button('取消')
                .layoutWeight(1)
                .height(40)
                .fontSize(14)
                .fontFamily(this.appFontFamily)
                .backgroundColor(ThemeAwareHelper.getTestManagementThemedColor('comp_background_secondary', this.themeState.currentTheme))
                .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_primary', this.themeState.currentTheme))
                .borderRadius(20)
                .onClick(() => this.hideCacheConfirmDialog())

              Button(this.cacheConfirmActionLabel)
                .layoutWeight(1)
                .height(40)
                .fontSize(14)
                .fontFamily(this.appFontFamily)
                .backgroundColor(this.cacheConfirmActionKind === 'danger'
                  ? ThemeAwareHelper.getTestManagementThemedColor('color_error', this.themeState.currentTheme)
                  : ThemeAwareHelper.getTestManagementThemedColor('accent_primary', this.themeState.currentTheme))
                .fontColor(Color.White)
                .borderRadius(20)
                .onClick(() => {
                  void this.confirmCacheAction();
                })
            }
            .width('100%')
          }
          .width('100%')
          .padding(20)
        }
        .width('100%')
        .scale({ x: this.cacheConfirmDialogScale, y: this.cacheConfirmDialogScale })
        .translate({ y: this.cacheConfirmDialogTranslateY })
        .opacity(this.cacheConfirmDialogOpacity)
        .borderRadius(18)
        .clip(true)
        .onClick(() => {})
      }
    }
  }

  @Builder
  private buildNovelSettingsCloseConfirmDialog() {
    if (this.isNovelSettingsCloseConfirmDialogVisible) {
      SourceDialogScaffold({
        themeState: this.themeState,
        onMaskTap: () => this.hideNovelSettingsCloseConfirmDialog(),
        dialogWidth: '92%',
        maxWidth: 520,
        contentPadding: 0,
        dialogRadius: 26,
        zIndexValue: 120,
        useMaskBlur: true,
        maskBlurStyle: this.getDialogMaskBlurStyle(),
        maskColor: this.getDialogMaskColor()
      }) {
        Stack({ alignContent: Alignment.TopStart }) {
          this.buildDialogChrome(26)
          Column({ space: 14 }) {
            Text('存在未应用修改')
              .fontSize(18)
              .fontWeight(FontWeight.Bold)
              .fontFamily(this.appFontFamily)
              .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_primary', this.themeState.currentTheme))

            Text(this.isLocalImportedEBookContent()
              ? '净化规则或信息修改还有未保存内容。你可以先应用再退出，也可以直接退出。'
              : '目录规则或净化规则还有未应用的修改。你可以先应用再退出，也可以直接退出。')
              .fontSize(13)
              .lineHeight(22)
              .fontFamily(this.appFontFamily)
              .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_secondary', this.themeState.currentTheme))
              .width('100%')

            Row({ space: 10 }) {
              Button('继续编辑')
                .layoutWeight(1)
                .height(40)
                .fontSize(14)
                .fontFamily(this.appFontFamily)
                .backgroundColor(ThemeAwareHelper.getTestManagementThemedColor('comp_background_secondary', this.themeState.currentTheme))
                .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_primary', this.themeState.currentTheme))
                .borderRadius(20)
                .onClick(() => this.hideNovelSettingsCloseConfirmDialog())

              Button('直接退出')
                .layoutWeight(1)
                .height(40)
                .fontSize(14)
                .fontFamily(this.appFontFamily)
                .backgroundColor(ThemeAwareHelper.getTestManagementThemedColor('comp_background_secondary', this.themeState.currentTheme))
                .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_secondary', this.themeState.currentTheme))
                .borderRadius(20)
                .onClick(() => {
                  this.hideNovelSettingsCloseConfirmDialog();
                  this.closeNovelSettingsDialogImmediately();
                })

              Button('应用后退出')
                .layoutWeight(1)
                .height(40)
                .fontSize(14)
                .fontFamily(this.appFontFamily)
                .backgroundColor(ThemeAwareHelper.getTestManagementThemedColor('accent_primary', this.themeState.currentTheme))
                .fontColor(Color.White)
                .borderRadius(20)
                .enabled(!this.isApplyingNovelDirectoryParsing && !this.isApplyingNovelReplaceRules && !this.isSavingEBookInfo)
                .onClick(() => {
                  void (async () => {
                    await this.applyPendingNovelSettingsChanges();
                    if (!this.hasPendingNovelSettingChanges()) {
                      this.hideNovelSettingsCloseConfirmDialog();
                      this.closeNovelSettingsDialog();
                      const afterClose = this.novelSettingsCloseAfterClose;
                      this.novelSettingsCloseAfterClose = undefined;
                      if (afterClose) {
                        afterClose();
                      }
                    }
                  })();
                })
            }
            .width('100%')
          }
          .width('100%')
          .padding(20)
        }
        .width('100%')
        .scale({ x: this.novelSettingsCloseConfirmScale, y: this.novelSettingsCloseConfirmScale })
        .translate({ y: this.novelSettingsCloseConfirmTranslateY })
        .opacity(this.novelSettingsCloseConfirmOpacity)
        .borderRadius(26)
        .clip(true)
        .onClick(() => {})
      }
    }
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
              // 在线漫画显示"已下载"文字标记
              if (chapter.isDownloaded && !this.content?.isLocal) {
                Text('已下载')
                  .fontSize(10)
                  .fontFamily(this.appFontFamily)
                  .fontColor(ThemeAwareHelper.getTestManagementThemedColor('accent_green', this.themeState.currentTheme))
                  .padding({ left: 6, right: 6, top: 3, bottom: 3 })
                  .backgroundColor(ThemeAwareHelper.getTestManagementThemedColor('accent_green', this.themeState.currentTheme) + '15')
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
      promptAction.showToast({ message: '无封面图片', duration: 2000 });
      return;
    }
    
    // 初始化动画状态
    this.coverPreviewOpacity = 0;
    this.coverPreviewScale = 0.3;
    this.showCoverPreview = true;
    
    // 延迟执行动画，确保 UI 已渲染
    setTimeout(() => {
      animateTo({
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
    animateTo({
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
            SymbolGlyph($r('sys.symbol.arrowshape_turn_up_right'))
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
      promptAction.showToast({ message: '无封面图片', duration: 2000 });
      return;
    }
    if (coverUrl.startsWith('app.media.')) {
      promptAction.showToast({ message: '内置资源封面暂不支持保存', duration: 2000 });
      return;
    }
    
    this.isSavingCover = true;
    
    try {
      const context = getContext(this) as common.UIAbilityContext;
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
        const tempFile = fs.openSync(localFilePath, fs.OpenMode.CREATE | fs.OpenMode.WRITE_ONLY);
        fs.writeSync(tempFile.fd, imageData);
        fs.closeSync(tempFile);
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
        fs.closeSync(destFile);
        fs.closeSync(srcFile);
        
        logger.info(TAG, `封面已保存到相册: ${desFileUris[0]}`);
        promptAction.showToast({ message: '已保存到相册', duration: 2000 });
      } else {
        logger.info(TAG, '用户取消保存');
      }
      
    } catch (error) {
      logger.error(TAG, `保存封面失败: ${String(error)}`);
      promptAction.showToast({ message: `保存失败: ${String(error)}`, duration: 2000 });
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
      promptAction.showToast({ message: '无封面图片', duration: 2000 });
      return;
    }
    if (coverUrl.startsWith('app.media.')) {
      promptAction.showToast({ message: '内置资源封面暂不支持分享', duration: 2000 });
      return;
    }
    
    try {
      const context = getContext(this) as common.UIAbilityContext;
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
        const tempFile = fs.openSync(localFilePath, fs.OpenMode.CREATE | fs.OpenMode.WRITE_ONLY);
        fs.writeSync(tempFile.fd, imageData);
        fs.closeSync(tempFile);
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
      promptAction.showToast({ message: `分享失败: ${String(error)}`, duration: 2000 });
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
              SymbolGlyph($r('sys.symbol.text_book_closed'))
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

          Text(this.stripHtmlTags(this.content?.author || ''))
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

          if (this.content?.sourceName) {
            Text(`来源: ${this.content.sourceName}`)
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
              SymbolGlyph($r('sys.symbol.books_vertical_fill'))
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
        if (this.shouldShowTrackingStatusSection()) {
          this.buildTrackingStatusSection()
        }

        // 听书缓存
        this.buildReadAloudCacheSection()

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
            SymbolGlyph($r('sys.symbol.text_book_closed'))
              .fontSize(14)
              .fontColor([Color.White])
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
          .onClick(() => this.continueReading())

        if (this.canShowReadAloudButton()) {
          Button() {
            Row({ space: 6 }) {
              SymbolGlyph($r('sys.symbol.Celia'))
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
          if (this.isLoading) {
            this.buildLoadingView()
          } else if (this.errorMessage) {
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
                  if (this.shouldShowTrackingStatusSection()) {
                    this.buildTrackingStatusSection()
                  }
                  this.buildReadAloudCacheSection()
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
        .id('guide_unified_detail_root')
        .padding({ top: this.statusBarHeight })
        
        // 封面预览弹窗
        if (this.showCoverPreview && this.content?.coverUrl) {
          this.buildCoverPreviewOverlay()
        }
        
        // 生成封面对话框
        this.buildGenerateCoverDialog()
        
        // 下载章节选择对话框
        this.buildDownloadDialog()

        // 听书缓存管理对话框
        this.buildReadAloudCacheDialog()

        // 小说设置对话框
        this.buildNovelSettingsDialog()

        // 内容跟踪设置对话框
        this.buildTrackingSettingsDialog()
        
        // 换源对话框
        this.buildChangeSourceDialog()
        
        // 添加书架选择对话框
        this.buildAddToShelfDialog()
        
        // 替换小说对话框
        this.buildReplaceBookDialog()

        this.buildReplaceBookDialog()
        this.buildCacheConfirmDialog()
        this.buildNovelSettingsCloseConfirmDialog()
 
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
      // 页面显示时刷新阅读记录（从阅读器返回时）
      this.refreshReadingProgress();
      void this.loadReadAloudCacheSummary();
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
    this.coverTitleInput = this.content?.title || '';
    this.coverFontScale = 1.0;
    
    // 重置动画状态
    this.dialogOpacity = 0;
    this.dialogScale = 0.8;
    this.dialogTranslateY = 30;
    
    // 显示对话框
    this.showGenerateCoverDialog = true;
    
    // 触发入场动画
    animateTo({
      duration: 260,
      curve: Curve.EaseOut
    }, () => {
      this.dialogOpacity = 1;
      this.dialogScale = 1;
      this.dialogTranslateY = 0;
    });
  }
  
  /**
   * 生成封面
   */
  private async generateCoverForContent(): Promise<void> {
    if (!this.content || !this.coverTitleInput.trim()) {
      promptAction.showToast({ message: '请输入标题', duration: 2000 });
      return;
    }
    
    this.isGeneratingCover = true;
    this.showGenerateCoverDialog = false;
    
    try {
      logger.info(TAG, `开始生成封面: ${this.coverTitleInput}`);
      
      const coverPath = await this.coverGenerator.generateCover(
        this.content.id,
        this.coverTitleInput,
        () => { this.buildCoverForSnapshot(this.coverTitleInput); }
      );
      
      if (coverPath) {
        await this.updateContentCover(coverPath);
        // 强制刷新封面显示
        this.coverRefreshKey = Date.now();
        promptAction.showToast({ message: '封面生成成功', duration: 2000 });
        logger.info(TAG, `封面生成成功: ${coverPath}`);
      } else {
        promptAction.showToast({ message: '封面生成失败', duration: 2000 });
        logger.warn(TAG, '封面生成失败');
      }
    } catch (error) {
      logger.error(TAG, `生成封面异常: ${String(error)}`);
      promptAction.showToast({ message: `生成失败: ${String(error)}`, duration: 2000 });
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
  buildCoverForSnapshot(title: string) {
    Stack() {
      Image($r('app.media.ebook'))
        .width(COVER_WIDTH)
        .height(COVER_HEIGHT)
        .objectFit(ImageFit.Cover)
      
      Text(this.formatCoverTitle(title))
        .fontFamily(this.appFontFamily)
        .fontSize(this.calculateCoverFontSize(title))
        .fontWeight(FontWeight.Bold)
        .fontColor('#1a1a1a')
        .textAlign(TextAlign.Center)
        .maxLines(2)
        .textOverflow({ overflow: TextOverflow.Ellipsis })
        .lineHeight(this.calculateCoverFontSize(title) * 1.3)
        .width(COVER_WIDTH * (UnifiedDetailPage.TITLE_AREA_RIGHT_PERCENT - UnifiedDetailPage.TITLE_AREA_LEFT_PERCENT) - 24)
        .constraintSize({
          maxHeight: COVER_HEIGHT * (UnifiedDetailPage.TITLE_AREA_BOTTOM_PERCENT - UnifiedDetailPage.TITLE_AREA_TOP_PERCENT) - 20
        })
        .position({
          x: COVER_WIDTH * UnifiedDetailPage.TITLE_AREA_LEFT_PERCENT + 12,
          y: COVER_HEIGHT * (UnifiedDetailPage.TITLE_AREA_TOP_PERCENT + UnifiedDetailPage.TITLE_AREA_BOTTOM_PERCENT) / 2 - this.calculateCoverFontSize(title) * 0.65
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
  private calculateCoverFontSize(title: string): number {
    const length = title.length;
    let baseSize = 24;
    if (length <= 2) baseSize = 70;
    else if (length <= 4) baseSize = 56;
    else if (length <= 6) baseSize = 48;
    else if (length <= 8) baseSize = 36;
    else if (length <= 12) baseSize = 32;
    else if (length <= 16) baseSize = 28;
    
    return baseSize * this.coverFontScale;
  }
  
  /**
   * 关闭生成封面对话框（带动画）
   */
  private closeGenerateCoverDialog(): void {
    animateTo({
      duration: 180,
      curve: Curve.EaseIn
    }, () => {
      this.dialogOpacity = 0;
      this.dialogScale = 0.96;
      this.dialogTranslateY = 12;
    });

    setTimeout(() => {
      this.showGenerateCoverDialog = false;
    }, 200);
  }
  
  /**
   * 单章节下载视图（针对只有1章的漫画）
   */
  @Builder
  buildSingleChapterDownloadView() {
    Column({ space: 16 }) {
      // 章节信息卡片
      Row({ space: 12 }) {
        // 章节图标
        Column() {
          SymbolGlyph($r('sys.symbol.doc_plaintext_2'))
            .fontSize(24)
            .fontColor([ThemeAwareHelper.getTestManagementThemedColor('accent_primary', this.themeState.currentTheme)])
        }
        .width(48)
        .height(48)
        .backgroundColor(ThemeAwareHelper.getTestManagementThemedColor('accent_primary', this.themeState.currentTheme) + '15')
        .borderRadius(12)
        .justifyContent(FlexAlign.Center)
        
        // 章节信息
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
            
            if (this.content?.chapters[0]?.isDownloaded) {
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
      
      // 提示文字
      if (this.content?.chapters[0]?.isDownloaded) {
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

  /**
   * 听书缓存管理对话框
   */
  @Builder
  buildReadAloudCacheDialog() {
    if (this.showReadAloudCacheDialog && this.content && this.supportsReadAloudCacheSection()) {
      SourceDialogScaffold({
        themeState: this.themeState,
        onMaskTap: () => {
          this.closeReadAloudCacheDialog();
        },
        dialogWidth: '90%',
        maxWidth: 640,
        contentPadding: 0,
        dialogRadius: 26,
        zIndexValue: 120,
        useMaskBlur: true,
        maskBlurStyle: this.getDialogMaskBlurStyle(),
        maskColor: this.getDialogMaskColor()
      }) {
        Stack({ alignContent: Alignment.TopStart }) {
          this.buildDialogChrome(26)
          Column({ space: 16 }) {

            Row() {
              Text('听书缓存')
                .fontSize(18)
                .fontWeight(FontWeight.Bold)
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
              this.buildReadAloudCacheDialogTabButton('管理', $r('sys.symbol.rectangle_stack'), 1)
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
          .padding(20)
          .scale({ x: this.readAloudCacheDialogScale, y: this.readAloudCacheDialogScale })
          .translate({ y: this.readAloudCacheDialogTranslateY })
          .opacity(this.readAloudCacheDialogOpacity)
          .borderRadius(26)
          .clip(true)
          .onClick(() => {
          })
        }
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
            animateTo({ duration: 220, curve: Curve.EaseInOut }, () => {
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
            animateTo({ duration: 220, curve: Curve.EaseInOut }, () => {
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
            animateTo({ duration: 300, curve: Curve.EaseInOut }, () => {
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
  
  /**
   * 小说设置对话框
   */
  @Builder
  buildNovelSettingsDialog() {
    if (this.showNovelSettingsDialog && this.content && this.canUseNovelStyleSettingsDialog()) {
      SourceDialogScaffold({
        themeState: this.themeState,
        onMaskTap: () => {
          void this.requestCloseNovelSettingsDialog();
        },
        dialogWidth: '90%',
        maxWidth: 400,
        contentPadding: 0,
        dialogRadius: 26,
        zIndexValue: 120,
        useMaskBlur: true,
        maskBlurStyle: this.getDialogMaskBlurStyle(),
        maskColor: this.getDialogMaskColor()
      }) {
        Stack({ alignContent: Alignment.TopStart }) {
          this.buildDialogChrome(26)
          Column({ space: 16 }) {

            Row() {
              Text(this.isNovelSettingsDialogForLocalEBook() ? '电子书设置' : '小说设置')
                .fontSize(18)
                .fontWeight(FontWeight.Bold)
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
                void this.requestCloseNovelSettingsDialog();
              })
            }
            .width('100%')

            Row({ space: 8 }) {
              if (this.isNovelSettingsDialogForLocalEBook()) {
                this.buildNovelSettingsTabButton('净化规则', 0)
                this.buildNovelSettingsTabButton('信息修改', 1)
              } else {
                this.buildNovelSettingsTabButton('预下载', 0)
                this.buildNovelSettingsTabButton('目录解析', 1)
                this.buildNovelSettingsTabButton('净化规则', 2)
              }
            }
            .width('100%')
            .padding(4)
            .backgroundColor(ThemeAwareHelper.getTestManagementThemedColor('comp_background_tertiary',
              this.themeState.currentTheme))
            .borderRadius(18)

            Scroll() {
              Column({ space: 12 }) {
                if (this.isNovelSettingsDialogForLocalEBook()) {
                  if (this.novelSettingsActiveTab === 0) {
                    this.buildNovelReplaceRuleSettingsTab()
                  } else {
                    this.buildEBookInfoEditTab()
                  }
                } else {
                  if (this.novelSettingsActiveTab === 0) {
                    this.buildNovelPrefetchSettingsTab()
                  } else if (this.novelSettingsActiveTab === 1) {
                    this.buildNovelDirectorySettingsTab()
                  } else {
                    this.buildNovelReplaceRuleSettingsTab()
                  }
                }
              }
              .width('100%')
              .alignItems(HorizontalAlign.Start)
            }
            .width('100%')
            .constraintSize({ maxHeight: 420 })
            .scrollBar(BarState.Auto)
          }
          .width('100%')
          .padding(20)
          .scale({ x: this.novelSettingsDialogScale, y: this.novelSettingsDialogScale })
          .translate({ y: this.novelSettingsDialogTranslateY })
          .opacity(this.novelSettingsDialogOpacity)
          .borderRadius(26)
          .clip(true)
          .onClick(() => {
          })
        }
      }
    }
  }


  @Builder
  private buildNovelSettingsTabButton(label: string, index: number) {
    Row() {
      Text(label)
        .fontSize(13)
        .fontFamily(this.appFontFamily)
        .fontWeight(FontWeight.Medium)
        .fontColor(this.novelSettingsActiveTab === index
          ? Color.White
          : ThemeAwareHelper.getTestManagementThemedColor('text_secondary', this.themeState.currentTheme))
    }
    .layoutWeight(1)
    .height(34)
    .justifyContent(FlexAlign.Center)
    .backgroundColor(this.novelSettingsActiveTab === index
      ? ThemeAwareHelper.getTestManagementThemedColor('accent_primary', this.themeState.currentTheme)
      : Color.Transparent)
    .borderRadius(14)
    .animation({ duration: 160, curve: Curve.EaseOut })
    .onClick(() => {
      logger.info(TAG, `小说设置标签切换: ${label}`);
      this.novelSettingsActiveTab = index;
    })
  }

  @Builder
  private buildNovelPrefetchSettingsTab() {
    Column({ space: 10 }) {
      Row() {
        Text('预下载设置（仅在线）')
          .fontSize(14)
          .fontWeight(FontWeight.Medium)
          .fontFamily(this.appFontFamily)
          .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_primary', this.themeState.currentTheme))
        Blank()
        if (this.isOnlineNovelContent()) {
          Toggle({ type: ToggleType.Switch, isOn: this.novelEnableReadWhileDownload })
            .onChange((isOn: boolean) => {
              this.novelEnableReadWhileDownload = isOn;
              logger.info(TAG, `小说预下载开关变更: ${isOn}`);
              void this.saveNovelSettingValue('enableReadWhileDownload', isOn);
            })
        }
      }
      .width('100%')

      if (this.isOnlineNovelContent()) {
        Text('在阅读时提前缓存后续章节，设置实时生效')
          .fontSize(12)
          .fontFamily(this.appFontFamily)
          .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_secondary', this.themeState.currentTheme))
          .width('100%')

        if (this.novelEnableReadWhileDownload) {
          Column({ space: 8 }) {
            Text(`预下载范围：${this.formatNovelPrefetchChapterCount(this.novelDefaultLoadChapters)}`)
              .fontSize(12)
              .fontFamily(this.appFontFamily)
              .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_secondary', this.themeState.currentTheme))
              .width('100%')
            Row({ space: 8 }) {
              ForEach(this.getNovelPrefetchChapterOptions(), (count: number) => {
                Button(this.formatNovelPrefetchChapterCount(count))
                  .fontSize(12)
                  .fontFamily(this.appFontFamily)
                  .height(28)
                  .padding({ left: 10, right: 10 })
                  .backgroundColor(this.novelDefaultLoadChapters === count
                    ? ThemeAwareHelper.getTestManagementThemedColor('accent_primary', this.themeState.currentTheme)
                    : ThemeAwareHelper.getTestManagementThemedColor('comp_background_secondary', this.themeState.currentTheme))
                  .fontColor(this.novelDefaultLoadChapters === count
                    ? Color.White
                    : ThemeAwareHelper.getTestManagementThemedColor('text_primary', this.themeState.currentTheme))
                  .borderRadius(14)
                  .onClick(() => this.onNovelPrefetchChapterCountChange(count))
              }, (count: number) => `novel_prefetch_${count}`)
            }
            .width('100%')
          }
          .width('100%')
          .alignItems(HorizontalAlign.Start)
        }
      } else {
        Text('当前为本地小说，预下载仅在线小说可用')
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
  }

  @Builder
  private buildNovelDirectorySettingsTab() {
    Column({ space: 10 }) {
      Text('目录解析（书籍专属）')
        .fontSize(14)
        .fontWeight(FontWeight.Medium)
        .fontFamily(this.appFontFamily)
        .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_primary', this.themeState.currentTheme))
      Text('为当前小说单独选择目录解析规则，点击“应用”后会保存并重新解析目录')
        .fontSize(12)
        .fontFamily(this.appFontFamily)
        .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_secondary', this.themeState.currentTheme))
        .width('100%')
      Row({ space: 8 }) {
        Button(this.isApplyingNovelDirectoryParsing ? '应用中...' : '应用')
          .layoutWeight(1)
          .height(32)
          .borderRadius(16)
          .fontSize(12)
          .fontFamily(this.appFontFamily)
          .backgroundColor(ThemeAwareHelper.getTestManagementThemedColor('accent_primary', this.themeState.currentTheme))
          .fontColor(Color.White)
          .enabled(!this.isApplyingNovelDirectoryParsing)
          .onClick(() => {
            void this.applyNovelDirectoryParsingSelection();
          })
        Button('管理目录规则')
          .layoutWeight(1)
          .height(32)
          .borderRadius(16)
          .fontSize(12)
          .fontFamily(this.appFontFamily)
          .backgroundColor(ThemeAwareHelper.getTestManagementThemedColor('comp_background_secondary', this.themeState.currentTheme))
          .fontColor(ThemeAwareHelper.getTestManagementThemedColor('accent_primary', this.themeState.currentTheme))
          .onClick(() => {
            this.openNovelTxtTocRulePage();
          })
      }
      .width('100%')

      if (this.novelTocRules.length <= 0) {
        Text('暂无目录规则')
          .fontSize(12)
          .fontFamily(this.appFontFamily)
          .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_secondary', this.themeState.currentTheme))
      } else {
        ForEach(this.novelTocRules, (rule: TxtTocRule) => {
          Row({ space: 8 }) {
            Column({ space: 4 }) {
              Text(rule.name)
                .fontSize(13)
                .fontFamily(this.appFontFamily)
                .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_primary', this.themeState.currentTheme))
                .maxLines(1)
                .textOverflow({ overflow: TextOverflow.Ellipsis })
              Text(rule.rule)
                .fontSize(11)
                .fontFamily(this.appFontFamily)
                .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_secondary', this.themeState.currentTheme))
                .maxLines(3)
                .textOverflow({ overflow: TextOverflow.Ellipsis })
              Text(`序号：${rule.serialNumber}  默认：${rule.enabled ? '启用' : '禁用'}`)
                .fontSize(11)
                .fontFamily(this.appFontFamily)
                .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_muted', this.themeState.currentTheme))
                .maxLines(1)
                .textOverflow({ overflow: TextOverflow.Ellipsis })
              if (rule.example && rule.example.length > 0) {
                Text(`示例：${rule.example}`)
                  .fontSize(11)
                  .fontFamily(this.appFontFamily)
                  .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_muted', this.themeState.currentTheme))
                  .maxLines(1)
                  .textOverflow({ overflow: TextOverflow.Ellipsis })
              }
            }
            .layoutWeight(1)
            .alignItems(HorizontalAlign.Start)
            Toggle({ type: ToggleType.Switch, isOn: this.isRuleSelected(this.novelSelectedTocRuleIds, rule.id) })
              .onChange((isOn: boolean) => {
                this.novelSelectedTocRuleIds = this.toggleRuleSelection(this.novelSelectedTocRuleIds, rule.id, isOn);
                this.refreshNovelRuleDirtyState();
                logger.info(TAG, `目录规则选择变更: rule=${rule.name}, enabled=${isOn}`);
              })
          }
          .width('100%')
          .padding(10)
          .backgroundColor(ThemeAwareHelper.getTestManagementThemedColor('comp_background_secondary', this.themeState.currentTheme))
          .borderRadius(10)
        }, (rule: TxtTocRule) => `toc_rule_${rule.id}`)
      }
    }
    .width('100%')
    .padding(12)
    .backgroundColor(ThemeAwareHelper.getTestManagementThemedColor('comp_background_tertiary', this.themeState.currentTheme))
    .borderRadius(12)
  }

  @Builder
  private buildNovelReplaceRuleSettingsTab() {
    Column({ space: 10 }) {
      Text('净化规则（书籍专属）')
        .fontSize(14)
        .fontWeight(FontWeight.Medium)
        .fontFamily(this.appFontFamily)
        .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_primary', this.themeState.currentTheme))
      Text(this.isNovelSettingsDialogForLocalEBook()
        ? '为当前电子书单独选择净化规则，点击“应用”后会保存到阅读器并立即作用于详情页内容'
        : '为当前小说单独选择净化规则，点击“应用”后会立即作用于当前内容并持久化')
        .fontSize(12)
        .fontFamily(this.appFontFamily)
        .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_secondary', this.themeState.currentTheme))
        .width('100%')
      Row({ space: 8 }) {
        Button(this.isApplyingNovelReplaceRules ? '应用中...' : '应用')
          .layoutWeight(1)
          .height(32)
          .borderRadius(16)
          .fontSize(12)
          .fontFamily(this.appFontFamily)
          .backgroundColor(ThemeAwareHelper.getTestManagementThemedColor('accent_primary', this.themeState.currentTheme))
          .fontColor(Color.White)
          .enabled(!this.isApplyingNovelReplaceRules)
          .onClick(() => {
            void this.applyNovelReplaceRulesSelection();
          })
        Button('管理净化规则')
          .layoutWeight(1)
          .height(32)
          .borderRadius(16)
          .fontSize(12)
          .fontFamily(this.appFontFamily)
          .backgroundColor(ThemeAwareHelper.getTestManagementThemedColor('comp_background_secondary', this.themeState.currentTheme))
          .fontColor(ThemeAwareHelper.getTestManagementThemedColor('accent_primary', this.themeState.currentTheme))
          .onClick(() => {
            this.openNovelReplaceRulePage();
          })
      }
      .width('100%')

      if (this.novelReplaceRules.length <= 0) {
        Text('暂无净化规则')
          .fontSize(12)
          .fontFamily(this.appFontFamily)
          .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_secondary', this.themeState.currentTheme))
      } else {
        ForEach(this.novelReplaceRules, (rule: ReplaceRule) => {
          Row({ space: 8 }) {
            Column({ space: 4 }) {
              Text(rule.name)
                .fontSize(13)
                .fontFamily(this.appFontFamily)
                .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_primary', this.themeState.currentTheme))
                .maxLines(1)
                .textOverflow({ overflow: TextOverflow.Ellipsis })
              Text(`匹配：${rule.pattern}`)
                .fontSize(11)
                .fontFamily(this.appFontFamily)
                .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_secondary', this.themeState.currentTheme))
                .maxLines(3)
                .textOverflow({ overflow: TextOverflow.Ellipsis })
              Text(`替换：${rule.replacement}`)
                .fontSize(11)
                .fontFamily(this.appFontFamily)
                .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_muted', this.themeState.currentTheme))
                .maxLines(2)
                .textOverflow({ overflow: TextOverflow.Ellipsis })
              Text(`范围：${this.getReplaceRuleScopeLabel(rule.scope)}  来源：${this.getReplaceRuleSourceLabel(rule)}  默认：${rule.enabled ? '启用' : '禁用'}`)
                .fontSize(11)
                .fontFamily(this.appFontFamily)
                .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_muted', this.themeState.currentTheme))
                .maxLines(1)
                .textOverflow({ overflow: TextOverflow.Ellipsis })
            }
            .layoutWeight(1)
            .alignItems(HorizontalAlign.Start)
            Toggle({ type: ToggleType.Switch, isOn: this.isRuleSelected(this.novelSelectedReplaceRuleIds, rule.id) })
              .onChange((isOn: boolean) => {
                this.novelSelectedReplaceRuleIds = this.toggleRuleSelection(this.novelSelectedReplaceRuleIds, rule.id, isOn);
                this.refreshNovelRuleDirtyState();
                logger.info(TAG, `净化规则选择变更: rule=${rule.name}, enabled=${isOn}`);
              })
          }
          .width('100%')
          .padding(10)
          .backgroundColor(ThemeAwareHelper.getTestManagementThemedColor('comp_background_secondary', this.themeState.currentTheme))
          .borderRadius(10)
        }, (rule: ReplaceRule) => `replace_rule_${rule.id}`)
      }
    }
    .width('100%')
    .padding(12)
    .backgroundColor(ThemeAwareHelper.getTestManagementThemedColor('comp_background_tertiary', this.themeState.currentTheme))
    .borderRadius(12)
  }

  private normalizeEBookInfoCoverPath(path: string): string {
    const trimmed = path.trim();
    if (trimmed.length <= 0) {
      return '';
    }
    if (trimmed.startsWith('http://') || trimmed.startsWith('https://') || trimmed.startsWith('file://')) {
      return trimmed;
    }
    if (trimmed.startsWith('/')) {
      return `file://${trimmed}`;
    }
    return trimmed;
  }

  private getEBookInfoCoverPreviewSource(): string {
    const normalizedPath = this.normalizeEBookInfoCoverPath(this.ebookInfoCoverPath);
    if (normalizedPath.startsWith('http://') || normalizedPath.startsWith('https://')) {
      const connector = normalizedPath.indexOf('?') >= 0 ? '&' : '?';
      return `${normalizedPath}${connector}refresh=${this.coverRefreshKey}`;
    }
    return normalizedPath;
  }

  @Builder
  private buildEBookInfoTextInput(
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
      TextInput({ text: value, placeholder: placeholder })
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
          this.markEBookInfoDirty();
        })
    }
    .width('100%')
  }

  @Builder
  private buildEBookInfoTextArea(
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
      TextArea({ text: value, placeholder: placeholder })
        .height(92)
        .fontSize(13)
        .fontFamily(this.appFontFamily)
        .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_primary', this.themeState.currentTheme))
        .placeholderColor(ThemeAwareHelper.getTestManagementThemedColor('text_tertiary', this.themeState.currentTheme))
        .padding(10)
        .backgroundColor(ThemeAwareHelper.getTestManagementThemedColor('comp_background_secondary', this.themeState.currentTheme))
        .borderRadius(12)
        .onChange((nextValue: string) => {
          onChange(nextValue);
          this.markEBookInfoDirty();
        })
    }
    .width('100%')
  }

  @Builder
  private buildEBookInfoEditTab() {
    Column({ space: 12 }) {
      Row() {
        Column({ space: 4 }) {
          Text('信息修改')
            .fontSize(14)
            .fontWeight(FontWeight.Medium)
            .fontFamily(this.appFontFamily)
            .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_primary', this.themeState.currentTheme))
          Text(this.ebookInfoDirty ? '有未保存修改' : '修改后会同步到书库与详情页')
            .fontSize(12)
            .fontFamily(this.appFontFamily)
            .fontColor(this.ebookInfoDirty
              ? ThemeAwareHelper.getTestManagementThemedColor('accent_orange', this.themeState.currentTheme)
              : ThemeAwareHelper.getTestManagementThemedColor('text_secondary', this.themeState.currentTheme))
        }
        .layoutWeight(1)
        .alignItems(HorizontalAlign.Start)

        Button() {
          Row({ space: 5 }) {
            SymbolGlyph($r('sys.symbol.magnifyingglass'))
              .fontSize(13)
              .fontColor([ThemeAwareHelper.getTestManagementThemedColor('accent_primary', this.themeState.currentTheme)])
            Text('刮削')
              .fontSize(12)
              .fontFamily(this.appFontFamily)
              .fontColor(ThemeAwareHelper.getTestManagementThemedColor('accent_primary', this.themeState.currentTheme))
          }
        }
        .height(30)
        .padding({ left: 10, right: 10 })
        .backgroundColor(ThemeAwareHelper.getTestManagementThemedColor('accent_primary', this.themeState.currentTheme) + '18')
        .borderRadius(15)
        .onClick(() => {
          this.openEBookInfoScraperDialog();
        })
      }
      .width('100%')

      Row({ space: 12 }) {
        if (this.ebookInfoCoverPath.trim().length > 0) {
          Image(this.getEBookInfoCoverPreviewSource())
            .width(68)
            .height(96)
            .objectFit(ImageFit.Cover)
            .borderRadius(6)
        } else {
          Image($r('app.media.ebook'))
            .width(68)
            .height(96)
            .objectFit(ImageFit.Cover)
            .borderRadius(6)
        }
        Column({ space: 8 }) {
          this.buildEBookInfoTextInput('封面路径 / URL', this.ebookInfoCoverPath, '可填本地路径或网络封面 URL', (value: string) => {
            this.ebookInfoCoverPath = value;
          })
          Button('清空封面')
            .height(30)
            .fontSize(12)
            .fontFamily(this.appFontFamily)
            .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_secondary', this.themeState.currentTheme))
            .backgroundColor(ThemeAwareHelper.getTestManagementThemedColor('comp_background_secondary', this.themeState.currentTheme))
            .borderRadius(15)
            .onClick(() => {
              this.ebookInfoCoverPath = '';
              this.markEBookInfoDirty();
            })
        }
        .layoutWeight(1)
        .alignItems(HorizontalAlign.Start)
      }
      .width('100%')

      this.buildEBookInfoTextInput('书名 *', this.ebookInfoTitle, '请输入书名', (value: string) => {
        this.ebookInfoTitle = value;
      })
      this.buildEBookInfoTextInput('作者 *', this.ebookInfoAuthor, '请输入作者', (value: string) => {
        this.ebookInfoAuthor = value;
      })
      this.buildEBookInfoTextInput('出版社', this.ebookInfoPublisher, '请输入出版社', (value: string) => {
        this.ebookInfoPublisher = value;
      })
      this.buildEBookInfoTextInput('出版日期', this.ebookInfoPublishDate, '例如 2024-03 或 2024年3月', (value: string) => {
        this.ebookInfoPublishDate = value;
      })
      this.buildEBookInfoTextInput('ISBN', this.ebookInfoIsbn, '请输入 ISBN', (value: string) => {
        this.ebookInfoIsbn = value;
      })
      this.buildEBookInfoTextInput('语言', this.ebookInfoLanguage, '例如 zh-CN、en、ja', (value: string) => {
        this.ebookInfoLanguage = value;
      })
      this.buildEBookInfoTextArea('简介', this.ebookInfoDescription, '请输入简介', (value: string) => {
        this.ebookInfoDescription = value;
      })
      this.buildEBookInfoTextInput('标签（逗号分隔）', this.ebookInfoTagsText, '例如 科幻, 推理, 历史', (value: string) => {
        this.ebookInfoTagsText = value;
      })

      Button(this.isSavingEBookInfo ? '保存中...' : '保存信息')
        .width('100%')
        .height(36)
        .fontSize(13)
        .fontWeight(FontWeight.Medium)
        .fontFamily(this.appFontFamily)
        .fontColor(Color.White)
        .backgroundColor(ThemeAwareHelper.getTestManagementThemedColor('accent_primary', this.themeState.currentTheme))
        .borderRadius(18)
        .enabled(!this.isSavingEBookInfo)
        .onClick(() => {
          void this.saveEBookInfoEdit();
        })
    }
    .width('100%')
    .padding(12)
    .backgroundColor(ThemeAwareHelper.getTestManagementThemedColor('comp_background_tertiary', this.themeState.currentTheme))
    .borderRadius(12)
  }

  /**
   * 下载章节选择对话框
   */
  @Builder
  buildDownloadDialog() {
    if (this.showDownloadDialog && this.content) {
      SourceDialogScaffold({
        themeState: this.themeState,
        onMaskTap: () => this.closeDownloadDialog(),
        dialogWidth: '90%',
        maxWidth: 400,
        contentPadding: 0,
        dialogRadius: 26,
        zIndexValue: 120,
        useMaskBlur: true,
        maskBlurStyle: this.getDialogMaskBlurStyle(),
        maskColor: this.getDialogMaskColor()
      }) {
        Stack({ alignContent: Alignment.TopStart }) {
          this.buildDialogChrome(26)
          Column({ space: 16 }) {
            // 标题栏

            Row() {
              Text(this.content.contentType === UnifiedContentType.NOVEL ? this.getNovelCacheActionTitle() : '缓存章节')
                .fontSize(18)
                .fontWeight(FontWeight.Bold)
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
              // 单章节漫画：简化UI
              this.buildSingleChapterDownloadView()
            } else {
              // 多章节：显示完整的选择界面
              // 选择模式切换
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
                  animateTo({ duration: 200, curve: Curve.EaseOut }, () => {
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
                  animateTo({ duration: 200, curve: Curve.EaseOut }, () => {
                    this.downloadSelectionMode = 'individual';
                    // 单独选择模式默认展开章节列表
                    this.downloadChapterListExpanded = true;
                  });
                })
              }
              .width('100%')

              // 区间选择模式
              if (this.downloadSelectionMode === 'range') {
                Column({ space: 12 }) {
                  // 区间显示
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

                    Text(`共 ${this.downloadRangeEnd - this.downloadRangeStart + 1} 章`)
                      .fontSize(12)
                      .fontFamily(this.appFontFamily)
                      .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_secondary',
                        this.themeState.currentTheme))
                  }
                  .width('100%')

                  // 开始位置滑块
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

                  // 结束位置滑块
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

                  // 快捷选择按钮
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
                        animateTo({ duration: 150 }, () => {
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
                        animateTo({ duration: 150 }, () => {
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
                        animateTo({ duration: 150 }, () => {
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
                    Text(`已选择 ${this.downloadSelectedChapters.size} 章`)
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
                        animateTo({ duration: 200, curve: Curve.EaseOut }, () => {
                          this.downloadChapterListExpanded = !this.downloadChapterListExpanded;
                        });
                      })
                  }
                  .width('100%')

                  // 章节列表
                  if (this.downloadChapterListExpanded) {
                    List() {
                      ForEach(this.content.chapters, (chapter: UnifiedChapter, index: number) => {
                        ListItem() {
                          Row() {
                            Checkbox({ name: `chapter_${index}` })
                              .select(this.downloadSelectedChapters.has(index))
                              .selectedColor(ThemeAwareHelper.getTestManagementThemedColor('accent_primary',
                                this.themeState.currentTheme))
                              .enabled(!chapter.isDownloaded)  // 已缓存章节禁用选择
                              .hitTestBehavior(HitTestMode.Block)  // 阻止事件穿透到Row
                              .onChange((checked: boolean) => {
                                // 已缓存章节不可选中
                                if (chapter.isDownloaded) return;

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
                              .fontColor(chapter.isDownloaded
                                ? ThemeAwareHelper.getTestManagementThemedColor('text_muted',
                                  this.themeState.currentTheme)
                                : ThemeAwareHelper.getTestManagementThemedColor('text_primary',
                                  this.themeState.currentTheme))
                              .maxLines(1)
                              .textOverflow({ overflow: TextOverflow.Ellipsis })
                              .layoutWeight(1)

                            if (chapter.isDownloaded) {
                              Text(this.content?.contentType === UnifiedContentType.NOVEL ? this.getNovelDownloadedTagLabel() : '已缓存')
                                .fontSize(11)
                                .fontFamily(this.appFontFamily)
                                .fontColor(ThemeAwareHelper.getTestManagementThemedColor('accent_green',
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
                          .enabled(!chapter.isDownloaded) // 已缓存章节整行不可点击
                          .opacity(chapter.isDownloaded ? 0.5 : 1) // 已缓存章节半透明
                          .onClick(() => this.toggleChapterSelection(index))
                        }
                      }, (chapter: UnifiedChapter,
                        index: number) => `dl_chapter_${index}_${chapter.id}_${this.downloadSelectedChapters.has(index)}`)
                    }
                    .width('100%')
                    .height(200)
                    .scrollBar(BarState.Auto)
                    .edgeEffect(EdgeEffect.Spring)
                    .cachedCount(10) // 缓存列表项，提升滚动性能
                  }

                  // 快捷选择
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
                        // 全选只选中未缓存的章节
                        const newSet = new Set<number>();
                        this.content!.chapters.forEach((ch, idx) => {
                          if (!ch.isDownloaded) {
                            newSet.add(idx);
                          }
                        });
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
            } // 多章节UI结束

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
              .onClick(() => {
                this.closeDownloadDialog();
                if (this.content?.contentType === UnifiedContentType.NOVEL) {
                  this.showNovelCacheClearConfirm();
                } else {
                  this.showMangaCacheClearConfirm();
                }
              })


              Button() {
                Row({ space: 6 }) {
                  SymbolGlyph($r('sys.symbol.arrow_down_circle'))
                    .fontSize(16)
                    .fontColor([Color.White])
                  Text(this.content.contentType === UnifiedContentType.NOVEL
                    ? this.getNovelCacheCountActionLabel(this.getSelectedChapterCount())
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
              .onClick(() => this.executeDownloadSelected())
            }
            .width('100%')
          }
          .width('100%')
          .padding(20)
          .scale({ x: this.downloadDialogScale, y: this.downloadDialogScale })
          .translate({ y: this.downloadDialogTranslateY })
          .opacity(this.downloadDialogOpacity)
          .borderRadius(26)
          .clip(true)
          .onClick(() => {
          })
        }
      }
    }
  }

  
  /**
   * 打开换源对话框
   */
  private openChangeSourceDialog(): void {
    if (!this.content || this.content.contentType !== UnifiedContentType.NOVEL) return;
    
    // 初始化搜索关键词
    this.changeSourceKeyword = this.content.title;
    
    // 显示对话框（带动画）
    this.showChangeSourceDialog = true;
    animateTo({
      duration: 260,
      curve: Curve.EaseOut
    }, () => {
      this.changeSourceDialogOpacity = 1;
      this.changeSourceDialogScale = 1;
      this.changeSourceDialogTranslateY = 0;
    });
    
    // 开始搜索（使用缓存）
    this.startChangeSourceSearch(false);
  }
  
  /**
   * 开始换源搜索
   * @param forceRefresh 是否强制刷新（手动点击搜索按钮时为true）
   */
  private startChangeSourceSearch(forceRefresh: boolean = false): void {
    // 取消之前的搜索任务
    if (this.searchTaskHandle) {
      this.searchTaskHandle.cancel();
    }
    
    const keyword = this.changeSourceKeyword.trim();
    if (!keyword) {
      promptAction.showToast({ message: '请输入搜索关键词' });
      return;
    }
    
    const bookAuthor = this.content?.author;
    
    // 检查缓存（非强制刷新模式）
    if (!forceRefresh) {
      const cached = this.sourceSearchService.getCachedResults(keyword, bookAuthor);
      if (cached) {
        // 使用缓存结果
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
      // 强制刷新时清除缓存
      this.sourceSearchService.clearCache(keyword, bookAuthor);
    }
    
    // 重置状态
    this.isSearchingSource = true;
    this.alternativeSources = [];
    this.alternativeSourceResults = [];
    this.searchSourceCompleted = 0;
    this.searchSourceTotal = this.sourceSearchService.getSearchableSourceCount();
    this.searchSourceProgress = 0;
    
    logger.info(TAG, `开始换源搜索: ${keyword}, 共 ${this.searchSourceTotal} 个书源`);
    
    // 使用换源搜索服务，传入 0 表示不限制书源数量
    this.searchTaskHandle = this.sourceSearchService.searchForSource(
      keyword,
      bookAuthor,
      {
        onSourceComplete: (sourceResult: SourceSearchResult) => {
          // 实时更新结果
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
      0  // 传入 0 表示搜索所有启用的书源
    );
  }
  
  /**
   * 关闭换源对话框（带动画）
   */
  private closeChangeSourceDialog(): void {
    // 取消搜索
    if (this.searchTaskHandle) {
      this.searchTaskHandle.cancel();
      this.searchTaskHandle = null;
    }
    this.isSearchingSource = false;
    
    animateTo({
      duration: 180,
      curve: Curve.EaseIn
    }, () => {
      this.changeSourceDialogOpacity = 0;
      this.changeSourceDialogScale = 0.96;
      this.changeSourceDialogTranslateY = 12;
    });

    setTimeout(() => {
      this.showChangeSourceDialog = false;
    }, 200);
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
        sourceName: this.content.sourceName || '',
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
    
    // 关闭对话框
    this.closeChangeSourceDialog();
    
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
        promptAction.showToast({ message: `已切换到: ${source.sourceName}，点“替换原小说”按钮进行替换` });
      } else {
        promptAction.showToast({ message: `已切换到: ${source.sourceName}` });
      }
    } catch (error) {
      logger.error(TAG, `切换书源失败: ${String(error)}`);
      promptAction.showToast({ message: '切换失败，请重试' });
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
    this.showReplaceBookDialog = true;
    animateTo({
      duration: 260,
      curve: Curve.EaseOut
    }, () => {
      this.replaceDialogOpacity = 1;
      this.replaceDialogScale = 1;
      this.replaceDialogTranslateY = 0;
    });
  }
  
  /**
   * 关闭替换小说对话框
   */
  private closeReplaceBookDialog(): void {
    animateTo({
      duration: 180,
      curve: Curve.EaseIn
    }, () => {
      this.replaceDialogOpacity = 0;
      this.replaceDialogScale = 0.96;
      this.replaceDialogTranslateY = 12;
    });
    
    setTimeout(() => {
      this.showReplaceBookDialog = false;
    }, 200);
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
    
    this.closeReplaceBookDialog();
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
          sourceName: this.content.sourceName || '',
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
      
      promptAction.showToast({ 
        message: `已替换为「${this.content?.sourceName || '新书源'}」的版本`, 
        duration: 2500 
      });
      
      // 10. 发布事件通知 MainMenuPage 刷新小说列表
      eventBus.publish(GameEvent.NOVEL_LIST_REFRESH_NEEDED, new BasePayload());
      
      logger.info(TAG, `替换小说完成: ${this.content?.title}`);
      
    } catch (error) {
      logger.error(TAG, `替换小说失败: ${String(error)}`);
      promptAction.showToast({ message: `替换失败: ${String(error)}`, duration: 2000 });
    } finally {
      this.isLoading = false;
    }
  }
  
  /**
   * 生成封面对话框
   */
  @Builder
  buildGenerateCoverDialog() {
    if (this.showGenerateCoverDialog) {
      SourceDialogScaffold({
        themeState: this.themeState,
        onMaskTap: () => {
          this.closeGenerateCoverDialog();
        },
        dialogWidth: '80%',
        maxWidth: 400,
        contentPadding: 0,
        dialogRadius: 26,
        zIndexValue: 120,
        useMaskBlur: true,
        maskBlurStyle: this.getDialogMaskBlurStyle(),
        maskColor: this.getDialogMaskColor()
      }) {
        Stack({ alignContent: Alignment.TopStart }) {
          this.buildDialogChrome(26)
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
                .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_secondary',
                  this.themeState.currentTheme))

              TextInput({ text: this.coverTitleInput })
                .fontSize(14)
                .fontFamily(this.appFontFamily)
                .backgroundColor(ThemeAwareHelper.getTestManagementThemedColor('comp_background_tertiary',
                  this.themeState.currentTheme))
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
                  .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_secondary',
                    this.themeState.currentTheme))

                Text(this.coverFontScale.toFixed(1) + 'x')
                  .fontSize(14)
                  .fontFamily(this.appFontFamily)
                  .fontWeight(FontWeight.Medium)
                  .fontColor(ThemeAwareHelper.getTestManagementThemedColor('accent_primary',
                    this.themeState.currentTheme))
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
                .blockColor(ThemeAwareHelper.getTestManagementThemedColor('accent_primary',
                  this.themeState.currentTheme))
                .trackColor(ThemeAwareHelper.getTestManagementThemedColor('comp_background_tertiary',
                  this.themeState.currentTheme))
                .selectedColor(ThemeAwareHelper.getTestManagementThemedColor('accent_primary',
                  this.themeState.currentTheme))
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
                .backgroundColor(ThemeAwareHelper.getTestManagementThemedColor('comp_background_tertiary',
                  this.themeState.currentTheme))
                .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_primary', this.themeState.currentTheme))
                .layoutWeight(1)
                .onClick(() => {
                  this.closeGenerateCoverDialog();
                })

              Button('确定')
                .fontSize(14)
                .fontFamily(this.appFontFamily)
                .backgroundColor(ThemeAwareHelper.getTestManagementThemedColor('accent_primary',
                  this.themeState.currentTheme))
                .fontColor(Color.White)
                .layoutWeight(1)
                .onClick(() => {
                  this.generateCoverForContent();
                })
            }
            .width('100%')
          }
          .width('100%')
          .padding(24)
          .scale({ x: this.dialogScale, y: this.dialogScale })
          .translate({ y: this.dialogTranslateY })
          .opacity(this.dialogOpacity)
          .borderRadius(26)
          .clip(true)
          .onClick(() => {
          })
        }
      }
    }
  }

  
  /**
   * 换源对话框（带丰富动画效果）
   */
  @Builder
  buildChangeSourceDialog() {
    if (this.showChangeSourceDialog) {
      SourceDialogScaffold({
        themeState: this.themeState,
        onMaskTap: () => this.closeChangeSourceDialog(),
        dialogWidth: '92%',
        maxWidth: 420,
        maxHeight: '80%',
        contentPadding: 0,
        dialogRadius: 26,
        zIndexValue: 120,
        useMaskBlur: true,
        maskBlurStyle: this.getDialogMaskBlurStyle(),
        maskColor: this.getDialogMaskColor()
      }) {
        Stack({ alignContent: Alignment.TopStart }) {
          this.buildDialogChrome(26)
          Column({ space: 0 }) {

            // 标题栏
            Row() {
              Column() {
                Row({ space: 8 }) {
                  SymbolGlyph($r('sys.symbol.arrow_clockwise'))
                    .fontSize(20)
                    .fontColor([ThemeAwareHelper.getTestManagementThemedColor('accent_green',
                      this.themeState.currentTheme)])

                  Text('换源')
                    .fontSize(18)
                    .fontWeight(FontWeight.Bold)
                    .fontFamily(this.appFontFamily)
                    .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_primary',
                      this.themeState.currentTheme))

                  if (this.alternativeSourceResults.length > 0) {
                    Text(`(${this.alternativeSourceResults.length}个书源)`)
                      .fontSize(12)
                      .fontFamily(this.appFontFamily)
                      .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_tertiary',
                        this.themeState.currentTheme))
                      .opacity(this.changeSourceDialogOpacity)
                      .animation({ duration: 200, curve: Curve.EaseOut })
                  }
                }

                // 进度条
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
            .padding({
              left: 20,
              right: 16,
              top: 16,
              bottom: 12
            })
            .backgroundColor(ThemeAwareHelper.getTestManagementThemedColor('panel_background',
              this.themeState.currentTheme))

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
                    this.startChangeSourceSearch(true); // 手动输入后回车强制刷新
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
                this.startChangeSourceSearch(true); // 手动点击搜索按钮强制刷新
              })
            }
            .width('100%')
            .padding({
              left: 16,
              right: 16,
              top: 8,
              bottom: 12
            })
            .animation({ duration: 200, curve: Curve.EaseOut })

            // 搜索结果列表
            if (this.isSearchingSource && this.alternativeSourceResults.length === 0) {
              // 正在搜索且还没有结果
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
              // 搜索完成但没有结果
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
              // 有结果，按书源分组展示
              List() {
                ForEach(this.alternativeSourceResults, (sourceResult: SourceSearchResult, sourceIndex: number) => {
                  // 书源分组标题
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
                          .padding({
                            left: 8,
                            right: 8,
                            top: 3,
                            bottom: 3
                          })
                          .borderRadius(10)
                      }
                    }
                    .width('100%')
                    .padding({
                      left: 20,
                      right: 20,
                      top: 12,
                      bottom: 6
                    })
                    .backgroundColor(ThemeAwareHelper.getTestManagementThemedColor('comp_background_tertiary',
                      this.themeState.currentTheme))
                  }
                  .animation({
                    duration: 250,
                    delay: sourceIndex * 30,
                    curve: Curve.EaseOut
                  })

                  // 该书源下的书籍列表
                  ForEach(sourceResult.results, (book: NovelSearchResult, bookIndex: number) => {
                    ListItem() {
                      Row() {
                        Column() {
                          Row({ space: 6 }) {
                            Text(book.name)
                              .fontSize(14)
                              .fontWeight(FontWeight.Medium)
                              .fontFamily(this.appFontFamily)
                              .fontColor(book.sourceId === this.pageParams?.sourceId
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

                        if (book.sourceId === this.pageParams?.sourceId) {
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
                          .padding({
                            left: 10,
                            right: 10,
                            top: 5,
                            bottom: 5
                          })
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
                      .padding({
                        left: 20,
                        right: 16,
                        top: 12,
                        bottom: 12
                      })
                      .backgroundColor(book.sourceId === this.pageParams?.sourceId
                        ? ThemeAwareHelper.getTestManagementThemedColor('accent_green', this.themeState.currentTheme) +
                          '08'
                        : Color.Transparent)
                      .onClick(() => {
                        if (book.sourceId !== this.pageParams?.sourceId) {
                          this.changeNovelSource(book);
                        }
                      })
                    }
                    .animation({
                      duration: 200,
                      delay: sourceIndex * 30 + bookIndex * 20,
                      curve: Curve.EaseOut
                    })
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
          .scale({ x: this.changeSourceDialogScale, y: this.changeSourceDialogScale })
          .translate({ y: this.changeSourceDialogTranslateY })
          .opacity(this.changeSourceDialogOpacity)
          .borderRadius(26)
          .clip(true)
          .onClick(() => {
          })
        }
      }
    }
  }


  /**
   * 添加书架选择对话框
   */
  @Builder
  buildAddToShelfDialog() {
    if (this.showAddToShelfDialog) {
      SourceDialogScaffold({
        themeState: this.themeState,
        onMaskTap: () => this.closeAddToShelfDialog(),
        dialogWidth: '90%',
        maxWidth: 360,
        contentPadding: 0,
        dialogRadius: 26,
        zIndexValue: 120,
        useMaskBlur: true,
        maskBlurStyle: this.getDialogMaskBlurStyle(),
        maskColor: this.getDialogMaskColor()
      }) {
        Stack({ alignContent: Alignment.TopStart }) {
          this.buildDialogChrome(26)
          Column({ space: 16 }) {

            // 标题栏
            Row() {
              Text('添加到书架')
                .fontSize(18)
                .fontWeight(FontWeight.Bold)
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
              .enabled(!this.isShelfActionPending)
              .onClick(() => this.closeAddToShelfDialog())
            }
            .width('100%')

            // 书架列表（始终显示默认书架选项）
            List({ space: 8 }) {
              // 默认书架选项（始终显示在最前面）
              ListItem() {
                Row({ space: 12 }) {
                  // 默认书架图标
                  Column() {
                    SymbolGlyph($r('sys.symbol.books_vertical_fill'))
                      .fontSize(24)
                      .fontColor([ThemeAwareHelper.getTestManagementThemedColor('accent_primary',
                        this.themeState.currentTheme)])
                  }
                  .width(44)
                  .height(44)
                  .justifyContent(FlexAlign.Center)
                  .backgroundColor(ThemeAwareHelper.getTestManagementThemedColor('accent_primary',
                    this.themeState.currentTheme) + '15')
                  .borderRadius(10)

                  // 默认书架信息
                  Column({ space: 4 }) {
                    Text('默认书架')
                      .fontSize(15)
                      .fontWeight(FontWeight.Medium)
                      .fontFamily(this.appFontFamily)
                      .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_primary',
                        this.themeState.currentTheme))

                    Text('仅收藏到默认书库，不添加到自定义书架')
                      .fontSize(12)
                      .fontFamily(this.appFontFamily)
                      .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_tertiary',
                        this.themeState.currentTheme))
                  }
                  .alignItems(HorizontalAlign.Start)
                  .layoutWeight(1)

                  SymbolGlyph($r('sys.symbol.chevron_right'))
                    .fontSize(16)
                    .fontColor([ThemeAwareHelper.getTestManagementThemedColor('text_tertiary',
                      this.themeState.currentTheme)])
                }
                .width('100%')
                .padding({
                  left: 12,
                  right: 12,
                  top: 10,
                  bottom: 10
                })
                .backgroundColor(ThemeAwareHelper.getTestManagementThemedColor('comp_background_tertiary',
                  this.themeState.currentTheme))
                .borderRadius(12)
                .onClick(async () => {
                  if (this.isShelfActionPending) {
                    return;
                  }
                  await this.addToFavoriteOnly();
                  this.closeAddToShelfDialog();
                })
              }

              // 自定义书架列表
              ForEach(this.availableCustomShelves, (shelf: TypeShelf) => {
                ListItem() {
                  Row({ space: 12 }) {
                    // 书架图标
                    Column() {
                      SymbolGlyph($r('sys.symbol.books_vertical_fill'))
                        .fontSize(24)
                        .fontColor([ThemeAwareHelper.getTestManagementThemedColor('accent_primary',
                          this.themeState.currentTheme)])
                    }
                    .width(44)
                    .height(44)
                    .justifyContent(FlexAlign.Center)
                    .backgroundColor(ThemeAwareHelper.getTestManagementThemedColor('accent_primary',
                      this.themeState.currentTheme) + '15')
                    .borderRadius(10)

                    // 书架信息
                    Column({ space: 4 }) {
                      Text(shelf.name)
                        .fontSize(15)
                        .fontWeight(FontWeight.Medium)
                        .fontFamily(this.appFontFamily)
                        .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_primary',
                          this.themeState.currentTheme))

                      Text(shelf.shelfType === ShelfType.MIXED ? '混合书架' :
                        shelf.shelfType === ShelfType.DYNAMIC ? '动态书架' :
                          shelf.contentTypes.includes(ShelfContentType.MANGA) ? '漫画' :
                            shelf.contentTypes.includes(ShelfContentType.EBOOK) ? '电子书' : '小说')
                        .fontSize(12)
                        .fontFamily(this.appFontFamily)
                        .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_tertiary',
                          this.themeState.currentTheme))
                    }
                    .alignItems(HorizontalAlign.Start)
                    .layoutWeight(1)

                    // 选中指示
                    SymbolGlyph($r('sys.symbol.chevron_right'))
                      .fontSize(16)
                      .fontColor([ThemeAwareHelper.getTestManagementThemedColor('text_tertiary',
                        this.themeState.currentTheme)])
                  }
                  .width('100%')
                  .padding({
                    left: 12,
                    right: 12,
                    top: 10,
                    bottom: 10
                  })
                  .backgroundColor(ThemeAwareHelper.getTestManagementThemedColor('comp_background_tertiary',
                    this.themeState.currentTheme))
                  .borderRadius(12)
                  .onClick(() => {
                    if (this.isShelfActionPending) {
                      return;
                    }
                    void this.addToShelf(shelf);
                  })
                }
              }, (shelf: TypeShelf) => shelf.id)
            }
            .width('100%')
            .constraintSize({ maxHeight: 300 })
            .scrollBar(BarState.Off)
            .edgeEffect(EdgeEffect.Spring)
          }
          .width('100%')
          .padding(20)
          .scale({ x: this.addToShelfDialogScale, y: this.addToShelfDialogScale })
          .opacity(this.addToShelfDialogOpacity)
          .borderRadius(26)
          .clip(true)
          .onClick(() => {
          })
        }
      }
    }
  }

  
  /**
   * 替换小说对话框
   */
  @Builder
  buildReplaceBookDialog() {
    if (this.showReplaceBookDialog && this.originalBookInfo && this.content) {
      SourceDialogScaffold({
        themeState: this.themeState,
        onMaskTap: () => this.closeReplaceBookDialog(),
        dialogWidth: '90%',
        maxWidth: 380,
        contentPadding: 0,
        dialogRadius: 26,
        zIndexValue: 120,
        useMaskBlur: true,
        maskBlurStyle: this.getDialogMaskBlurStyle(),
        maskColor: this.getDialogMaskColor()
      }) {
        Stack({ alignContent: Alignment.TopStart }) {
          this.buildDialogChrome(26)
          Column({ space: 16 }) {

            // 标题栏
            Row() {
              Row({ space: 8 }) {
                SymbolGlyph($r('sys.symbol.wrench_arrow_counterclockwise'))
                  .fontSize(20)
                  .fontColor([ThemeAwareHelper.getTestManagementThemedColor('accent_orange',
                    this.themeState.currentTheme)])

                Text('替换小说')
                  .fontSize(18)
                  .fontWeight(FontWeight.Bold)
                  .fontFamily(this.appFontFamily)
                  .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_primary',
                    this.themeState.currentTheme))
              }

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
              .onClick(() => this.closeReplaceBookDialog())
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
                    .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_tertiary',
                      this.themeState.currentTheme))
                    .padding({
                      left: 8,
                      right: 8,
                      top: 2,
                      bottom: 2
                    })
                    .backgroundColor(ThemeAwareHelper.getTestManagementThemedColor('text_tertiary',
                      this.themeState.currentTheme) + '20')
                    .borderRadius(4)
                }
                .width('100%')

                Text(this.originalBookInfo.sourceName || '未知书源')
                  .fontSize(14)
                  .fontWeight(FontWeight.Medium)
                  .fontFamily(this.appFontFamily)
                  .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_secondary',
                    this.themeState.currentTheme))
                  .maxLines(2)
                  .textOverflow({ overflow: TextOverflow.Ellipsis })
                  .width('100%')

                Row({ space: 6 }) {
                  Text('共')
                    .fontSize(12)
                    .fontFamily(this.appFontFamily)
                    .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_muted',
                      this.themeState.currentTheme))

                  Text(`${this.originalBookInfo.chapterCount}`)
                    .fontSize(14)
                    .fontWeight(FontWeight.Bold)
                    .fontFamily(this.appFontFamily)
                    .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_secondary',
                      this.themeState.currentTheme))

                  Text('章')
                    .fontSize(12)
                    .fontFamily(this.appFontFamily)
                    .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_muted',
                      this.themeState.currentTheme))
                }
                .width('100%')
              }
              .width('100%')
              .padding(12)
              .alignItems(HorizontalAlign.Start)
              .backgroundColor(ThemeAwareHelper.getTestManagementThemedColor('comp_background_tertiary',
                this.themeState.currentTheme))
              .borderRadius(12)

              // 箭头指示
              Row() {
                SymbolGlyph($r('sys.symbol.arrow_down'))
                  .fontSize(20)
                  .fontColor([ThemeAwareHelper.getTestManagementThemedColor('accent_orange',
                    this.themeState.currentTheme)])
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
                    .padding({
                      left: 8,
                      right: 8,
                      top: 2,
                      bottom: 2
                    })
                    .backgroundColor(ThemeAwareHelper.getTestManagementThemedColor('accent_orange',
                      this.themeState.currentTheme))
                    .borderRadius(4)
                }
                .width('100%')

                Text(this.content.sourceName || '未知书源')
                  .fontSize(14)
                  .fontWeight(FontWeight.Medium)
                  .fontFamily(this.appFontFamily)
                  .fontColor(ThemeAwareHelper.getTestManagementThemedColor('accent_orange',
                    this.themeState.currentTheme))
                  .maxLines(2)
                  .textOverflow({ overflow: TextOverflow.Ellipsis })
                  .width('100%')

                Row({ space: 6 }) {
                  Text('共')
                    .fontSize(12)
                    .fontFamily(this.appFontFamily)
                    .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_muted',
                      this.themeState.currentTheme))

                  Text(`${this.content.totalChapters}`)
                    .fontSize(16)
                    .fontWeight(FontWeight.Bold)
                    .fontFamily(this.appFontFamily)
                    .fontColor(ThemeAwareHelper.getTestManagementThemedColor('accent_green',
                      this.themeState.currentTheme))

                  Text('章')
                    .fontSize(12)
                    .fontFamily(this.appFontFamily)
                    .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_muted',
                      this.themeState.currentTheme))

                  // 显示章节数差异
                  if (this.content.totalChapters !== this.originalBookInfo.chapterCount) {
                    Text(`(${this.content.totalChapters > this.originalBookInfo.chapterCount ? '+' :
                      ''}${this.content.totalChapters - this.originalBookInfo.chapterCount})`)
                      .fontSize(12)
                      .fontWeight(FontWeight.Medium)
                      .fontFamily(this.appFontFamily)
                      .fontColor(this.content.totalChapters > this.originalBookInfo.chapterCount
                        ? ThemeAwareHelper.getTestManagementThemedColor('accent_green', this.themeState.currentTheme)
                        : ThemeAwareHelper.getTestManagementThemedColor('accent_orange', this.themeState.currentTheme))
                  }
                }
                .width('100%')
              }
              .width('100%')
              .padding(12)
              .alignItems(HorizontalAlign.Start)
              .backgroundColor(ThemeAwareHelper.getTestManagementThemedColor('accent_orange',
                this.themeState.currentTheme) + '15')
              .borderRadius(12)
              .border({
                width: 1,
                color: ThemeAwareHelper.getTestManagementThemedColor('accent_orange', this.themeState.currentTheme) +
                  '40'
              })

              // 阅读进度迁移信息
              if (this.originalBookInfo.lastReadChapterIndex >= 0) {
                Column({ space: 6 }) {
                  Row({ space: 6 }) {
                    SymbolGlyph($r('sys.symbol.bookmark_fill'))
                      .fontSize(14)
                      .fontColor([ThemeAwareHelper.getTestManagementThemedColor('accent_primary',
                        this.themeState.currentTheme)])

                    Text('阅读进度迁移')
                      .fontSize(13)
                      .fontWeight(FontWeight.Medium)
                      .fontFamily(this.appFontFamily)
                      .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_primary',
                        this.themeState.currentTheme))
                  }

                  Text(`原书阅读至: 第${this.originalBookInfo.lastReadChapterIndex + 1}章`)
                    .fontSize(12)
                    .fontFamily(this.appFontFamily)
                    .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_secondary',
                      this.themeState.currentTheme))

                  if (this.originalBookInfo.lastReadChapterTitle) {
                    Text(`「${this.originalBookInfo.lastReadChapterTitle}」`)
                      .fontSize(12)
                      .fontFamily(this.appFontFamily)
                      .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_tertiary',
                        this.themeState.currentTheme))
                      .maxLines(1)
                      .textOverflow({ overflow: TextOverflow.Ellipsis })
                  }

                  Row({ space: 4 }) {
                    SymbolGlyph($r('sys.symbol.arrow_right_circle'))
                      .fontSize(12)
                      .fontColor([ThemeAwareHelper.getTestManagementThemedColor('accent_green',
                        this.themeState.currentTheme)])

                    if (this.matchedChapterIndex >= 0) {
                      Text(`将从新书第${this.matchedChapterIndex + 1}章继续`)
                        .fontSize(12)
                        .fontFamily(this.appFontFamily)
                        .fontColor(ThemeAwareHelper.getTestManagementThemedColor('accent_green',
                          this.themeState.currentTheme))
                    } else {
                      Text('将从第1章开始')
                        .fontSize(12)
                        .fontFamily(this.appFontFamily)
                        .fontColor(ThemeAwareHelper.getTestManagementThemedColor('accent_green',
                          this.themeState.currentTheme))
                    }
                  }
                  .margin({ top: 4 })
                }
                .width('100%')
                .alignItems(HorizontalAlign.Start)
                .padding(12)
                .backgroundColor(ThemeAwareHelper.getTestManagementThemedColor('accent_primary',
                  this.themeState.currentTheme) + '10')
                .borderRadius(12)
              }

              // 提示文字（根据原书是否在收藏中显示不同内容）
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
                .backgroundColor(ThemeAwareHelper.getTestManagementThemedColor('comp_background_tertiary',
                  this.themeState.currentTheme))
                .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_primary', this.themeState.currentTheme))
                .height(44)
                .layoutWeight(1)
                .borderRadius(22)
                .onClick(() => this.closeReplaceBookDialog())

              Button('确认替换')
                .fontSize(14)
                .fontFamily(this.appFontFamily)
                .backgroundColor(ThemeAwareHelper.getTestManagementThemedColor('accent_orange',
                  this.themeState.currentTheme))
                .fontColor(Color.White)
                .height(44)
                .layoutWeight(1)
                .borderRadius(22)
                .onClick(() => this.executeReplaceBook())
            }
            .width('100%')
          }
          .width('100%')
          .padding(20)
          .scale({ x: this.replaceDialogScale, y: this.replaceDialogScale })
          .translate({ y: this.replaceDialogTranslateY })
          .opacity(this.replaceDialogOpacity)
          .borderRadius(26)
          .clip(true)
          .borderRadius(20)
          .clip(true)
          .onClick(() => {
          })
        }
      }
    }
  }


  /**
   * 显示添加书架选择
   */
  private async showAddToShelfSelection(): Promise<void> {
    if (!this.content || this.isShelfActionPending) return;
    
    // 如果已在书架中，提示用户
    if (this.isInShelf) {
      promptAction.showToast({ 
        message: this.currentShelfName ? `已在「${this.currentShelfName}」中` : '已在书架中',
        duration: 1500 
      });
      return;
    }

    this.isShelfActionPending = true;
    try {
      // 获取可用的自定义书架
      await this.getAvailableCustomShelves();
      
      // 始终显示对话框（包含默认书架选项）
      this.showAddToShelfDialog = true;
      animateTo({
        duration: 260,
        curve: Curve.EaseOut
      }, () => {
        this.addToShelfDialogOpacity = 1;
        this.addToShelfDialogScale = 1;
      });
    } finally {
      this.isShelfActionPending = false;
    }
  }

  /**
   * 关闭添加书架对话框
   */
  private closeAddToShelfDialog(force: boolean = false): void {
    if (this.isShelfActionPending && !force) {
      return;
    }
    animateTo({
      duration: 180,
      curve: Curve.EaseIn
    }, () => {
      this.addToShelfDialogOpacity = 0;
      this.addToShelfDialogScale = 0.96;
    });

    setTimeout(() => {
      this.showAddToShelfDialog = false;
    }, 200);
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
      
      // 添加到书架
      await this.typeShelfManager.moveItemToShelf(this.content.id, contentType, shelf.id);
      
      // 同时设置为收藏
      if (!this.isFavorite) {
        await this.setFavoriteStatus(true);
      }
      
      // 更新状态
      this.isInShelf = true;
      this.currentShelfName = shelf.name;
      this.currentShelfId = shelf.id;
      
      // 关闭对话框
      this.closeAddToShelfDialog(true);
      
      // 加载同书架内容
      this.loadShelfContent();
      
      promptAction.showToast({ 
        message: `已添加到「${shelf.name}」书架`,
        duration: 1500 
      });
    } catch (error) {
      logger.error(TAG, `添加到书架失败: ${String(error)}`);
      promptAction.showToast({ 
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
    try {
      await this.setFavoriteStatus(true);
      this.isInShelf = true;
      this.currentShelfName = '';
      promptAction.showToast({ 
        message: '已添加到默认书架',
        duration: 1500 
      });
    } catch (error) {
      logger.error(TAG, `添加到收藏失败: ${String(error)}`);
      promptAction.showToast({ 
        message: '添加失败，请重试',
        duration: 1500 
      });
    } finally {
      this.isShelfActionPending = false;
    }
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
    const hostContext = this.getUIContext().getHostContext() as common.UIAbilityContext;
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
          extendedDataMap.set('onlineReaderUrl', this.onlineReaderUrl || '');
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
            sourceName: this.content.sourceName || '',
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

    await this.refreshTrackingState();
  }
}


