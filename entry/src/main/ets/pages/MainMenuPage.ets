// 文件路径: src/main/ets/pages/MainMenuPage.ets
// 职责: 漫画阅读应用主入口页面，采用底部导航栏设计，参考Mihon、komikku等现代漫画阅读软件

import { logger } from '../Utils/Logger';
import { common } from '@kit.AbilityKit';
import { deviceInfo, BusinessError } from '@kit.BasicServicesKit';
import { CommonModifier, LengthMetrics, router } from '@kit.ArkUI';
import { image } from '@kit.ImageKit';
import fs from '@ohos.file.fs';
import { picker } from '@kit.CoreFileKit';
import { InteractionManager, VibrationScene } from '../Framework/Managers/InteractionManager';

// 主题相关导入
import { ComicConverter } from '../Framework/Utils/ComicConverter';
import { ThemeAwareState, ThemeAwareHelper } from '../Framework/Components/ThemeAware';
import { GlobalBackgroundLayer } from '../Framework/Components/GlobalBackgroundLayer';
import { AppNotificationManager } from '../Framework/Managers/NotificationManager';

// 导入页面组件
// 测试页面导入已移除，测试功能仍保留在代码中但不再从主菜单导航
// import { TestManagementPage } from './TestManagementPage';
import { DataManagementPage } from './DataManagementPage';
import { DownloadSyncPage } from './DownloadSyncPage';
import { MangaReaderPage } from './MangaReaderPage';
import { MangaDetailPage, MangaDetailPageParams } from './MangaDetailPage';
import { WebViewConfigurableSystemTestPage } from './WebViewConfigurableSystemTestPage';
import { MangaSourceTestPage } from './MangaSourceTestPage';
import { DummyPage } from './DummyPage';
import { SystemAnimationDemoPage } from './SystemAnimationDemoPage';
import { SystemResourceDemoPage } from './SystemResourceDemoPage';
import { HelloWorldPage } from './HelloWorldPage';
import { SystemStatusPage } from './SystemStatusPage';
import { SearchPage } from './SearchPage';
import { GlobalSearchPage } from './GlobalSearchPage';
import { MangaSettingsPage } from './MangaSettingsPage';
import { GlobalSettingsPage } from './settings/GlobalSettingsPage';
import { ReadingSettingsSubPage } from './settings/ReadingSettingsSubPage';
import { NetworkSettingsSubPage } from './settings/NetworkSettingsSubPage';
import { NotificationSettingsSubPage } from './settings/NotificationSettingsSubPage';
import { AdvancedSettingsSubPage } from './settings/AdvancedSettingsSubPage';
import { InteractionSettingsSubPage } from './settings/InteractionSettingsSubPage';
import { DownloadManagerPage } from './DownloadManagerPage';
import { AboutPage } from './AboutPage';
import { ReadingAnalyticsPage } from './ReadingAnalyticsPage';
import { MangaFeedbackPage } from './MangaFeedbackPage';
import { LogManagerPage } from './LogManagerPage';
import { OpenSourceLicensePage } from './OpenSourceLicensePage';
import { UserAgreementPage } from './UserAgreementPage';
import { PrivacyPolicyPage } from './PrivacyPolicyPage';
import { SourceGuidePage } from './SourceGuidePage';
import { SourceDetailPage } from './SourceDetailPage';
import { WebViewContainer, GlobalWebViewContainer } from '../Framework/WebView/WebViewContainerPage';
import { BookTransitionOverlay, startBookOpenTransition, startBookOpenTransitionWithComponentId, CoverPosition, EBookBackgroundSettings } from '../components/BookTransitionOverlay';
import { EBookReaderPage, EBookReaderParams } from './EBookReaderPage';
import { ThemeSettingsPage } from './ThemeSettingsPage';
import { CoverSelectionPage } from './CoverSelectionPage';
import { LogFloatingWindow } from '../Utils/LogFloatingWindow';
import { WindowManager } from '../Utils/WindowManager';
import { StorageManagementPage } from './StorageManagementPage';
import { TaskFloatingBall } from '../Framework/Components/TaskFloatingBall';
import { HelpPanelOverlayV2 } from '../Framework/Components/HelpPanelV2';
import { SourceSettingsPage, SourceSettingsPageParams } from './SourceSettingsPage';
import { SourceLoginPage } from './SourceLoginPage';
import { BookSourceManagementPage } from './BookSourceManagementPage';
import { BackupPage } from './BackupPage';

// 小说页面导入
import { NovelBookshelfPage, NovelDetailPageParams, NovelSearchPageParams, NovelReaderPageParams, NovelSourceManagementPageParams } from './NovelBookshelfPage';
import { NovelSearchPage } from './NovelSearchPage';
import { NovelDetailPage } from './NovelDetailPage';
import { NovelReaderPage } from './NovelReaderPage';
import { NovelSourceManagementPage } from './NovelSourceManagementPage';
import { NovelExplorePage } from './NovelExplorePage';
import { NovelSourceLoginPage } from './NovelSourceLoginPage';
import { NovelReplaceRulePage } from './NovelReplaceRulePage';
import { NovelSettingsPage } from './NovelSettingsPage';
import { NovelSourceDebugPage } from './NovelSourceDebugPage';
import { NovelTxtTocRulePage } from './NovelTxtTocRulePage';
import { NovelDictRulePage } from './NovelDictRulePage';
import { JsvmPlaygroundPage } from './JsvmPlaygroundPage';
import { LifecycleMonitorPage } from './LifecycleMonitorPage';
import { FileEditorPage } from './FileEditorPage';
import { BackgroundBlurOverlay } from '../Framework/Components/BackgroundBlurOverlay';
import { SystemResourcePreviewPage } from './SystemResourcePreviewPage';
import { HelpCenterPage } from './HelpCenterPage';
import { FontSettingsSubPage } from './settings/FontSettingsSubPage';
import { FontAwareHelper, FontAwareState } from '../Framework/Components/FontAware';

// 测试页面导入已移除
// import { ReaderKitTestPage } from './ReaderKitTestPage';
// import { PdfKitTestPage } from './PdfKitTestPage';
// import { ScraperTestPage } from './ScraperTestPage';  // 已移除，备份为 .bak

// 示例数据已移除，使用手册通过 WelcomeGuideManager 初始化
import { MangaReaderPageParams, MangaReaderContentType } from './MangaReaderPage';
import { Manga, MangaChapter, MangaMetadata, ReadingProgress, ReadingSettings, FilterSettings, ImageSourceType,
  ReadingMode,
  ReadingDirection,
  DEFAULT_READING_SETTINGS} from '../Models/MangaModels';
import { MangaStatus, ReadingStatus, StatusConverter, DownloadStatus } from '../Framework/Types/StatusEnums';
import { isOnlineManga, isLocalManga, MangaSourceType } from '../Framework/Types/MangaTypes';

// 导入图源相关
import { SourceManager, SourceInfo } from '../Framework/Source/SourceManager';
import { SourceRepositoryManager, SavedRepository, SourceRepositoryEntry, SyncResult, SyncProgressCallback } from '../Framework/Source/SourceRepositoryManager';

// 导入数据管理器
import { DataManager, ComicInfo, ReadHistory, PageInfo, ChapterInfo,
  OnlineComicInfo } from '../Framework/Data/DataManager';
import { ComicSourceDatabaseRecord } from '../Framework/Database/DatabaseTypes';
import { DatabaseManager } from '../Framework/Database/DatabaseManager';

import { ThemeManager, ThemeType, GlassEffectContext } from '../Framework/Managers/ThemeManager';
import { DataService } from '../Framework/Services/DataService';
import { EBookDataManager } from '../Framework/Data/EBookDataManager';

// 导入电子书相关模型
import { EBook, EBookStatus, EBookFormat } from '../Models/EBookModels';
import { EBookDetailPage, EBookDetailPageParams, EBookSettingsPageParams } from './EBookDetailPage';
import { OnlineEBookDetailPage } from './OnlineEBookDetailPage';
import { EBookSettingsPage } from './EBookSettingsPage';

// 导入小说相关模型
import { NovelBook, NovelReadStatus } from '../Models/NovelModels';
import { getNovelDataManager, NovelDataManager } from '../Framework/Novel/NovelDataManager';

// 导入事件总线
import { eventBus, GameEvent, IEventPayload, MangaImportCompletedPayload, FileImportRequestedPayload, MangaDeletedPayload } from '../Framework/EventBus';
import { WelcomeGuideManager } from '../Framework/Managers/WelcomeGuideManager';
import { getChangelogManager } from '../Framework/Managers/ChangelogManager';
import { SourceUpdateManager } from '../Framework/Managers/SourceUpdateManager';
import { ContentFilterManager } from '../Framework/Managers/ContentFilterManager';
import { PrivacyModeManager } from '../Framework/Managers/PrivacyModeManager';
import { ProxyManager, ProxyConfig, DEFAULT_PROXY_CONFIG } from '../Framework/Network/ProxyManager';
import { BookshelfCategoryManager, BookshelfCategory, ContentType, CategoryItem } from '../Framework/Data/BookshelfCategoryManager';

// 导入响应式布局
import { DeviceAdaptationManager, DeviceInfo, DeviceChangeListener,
  Breakpoint, FoldStatus } from '../Framework/Managers/DeviceAdaptationManager';
import { ResponsiveLayoutHelper } from '../Framework/Utils/ResponsiveLayout';
import { util } from '@kit.ArkTS';



const TAG = 'MainMenuPage';

/**
 * 恢复目标接口
 */
interface ResumeTarget {
  chapterId: string;
  pageIndex: number;
}

/**
 * 通用导航参数接口（不使用索引签名，遵守arkts-no-indexed-signatures规则）
 */
interface NavigationParams {
  fromPage?: string;
  timestamp?: number;
  mangaId?: string;
  chapterId?: string;
  pageIndex?: number;
}

/**
 * 导航路径参数接口
 */
interface NavigationPathParam {
  fromPage: string;
  timestamp: number;
}

/**
 * 导航路径接口
 */
interface NavigationPath {
  name: string;
  param: NavigationPathParam;
}

enum CoverOrientation {
  PORTRAIT = 0,
  LANDSCAPE = 1,
  SQUARE = 2
}

interface CoverAspectInfo {
  id: string;
  aspect: number;
  orientation: CoverOrientation;
}

/**
 * 电子书阅读器页面参数接口
 */


// 保留本地定义的电子书详情页参数

/**
 * 图源详情页面参数接口
 */
interface SourceDetailPageParams {
  sourceId: number;
  initialTab?: string;  // 初始标签ID（如 'popular', 'latest', 'search'）
  searchKeyword?: string;  // 搜索关键词（当initialTab为'search'时使用）
}

/**
 * 底部导航标签页枚举
 */
enum TabIndex {
  HOME = 0,
  LIBRARY = 1,
  DISCOVER = 2,
  SOURCE = 3,      // 图源（高级模式）
  // BOOK_SOURCE = 4, // 书源（已暂时注释）
  SETTINGS = 4
}

/**
 * 书库内容类型枚举
 */
enum LibraryContentType {
  MANGA = 'manga',     // 漫画
  EBOOK = 'ebook',     // 电子书
  NOVEL = 'novel'      // 小说
}

/**
 * 书库筛选类型枚举
 */
enum LibraryFilterType {
  ALL = 'all',           // 全部
  UNREAD = 'unread',     // 未读
  READING = 'reading',   // 阅读中
  COMPLETED = 'completed', // 已完结
  FAVORITE = 'favorite'  // 收藏
}

/**
 * 书库视图模式枚举
 */
enum LibraryViewMode {
  LIST = 'list',     // 列表视图
  GRID = 'grid',     // 网格视图
  CATEGORY = 'category' // 分类视图（类似iOS App Library）
}

/**
 * 导航标签配置接口
 */
interface TabConfig {
  title: string;
  icon: Resource;
  selectedIcon: Resource;
  systemIcon?: Resource; // 系统图标（SymbolGlyph）
  useSystemIcon?: boolean; // 是否使用系统图标
  hasMultiColor?: boolean; // 是否支持多色效果
  index: number;
  required: boolean; // 是否必须显示
}

/**
 * Toast配置接口
 */
interface ToastConfig {
  message: string;
  duration: number;
  bottom: number;
}

interface bannerData {
  title: string;
  subtitle: string;
  image: ResourceStr;
  backgroundColor: string;
}

interface GeneratedTypeLiteralInterface_1 {
  title: string;
  subtitle: string;
  image: ResourceStr;
  backgroundColor: string;
}

interface ActionMenuResult {
  index: number;
}

@Entry
@Component
struct MainMenuPage {
  // 全局上下文
  private uiContext: UIContext = this.getUIContext();

  // 创建并提供 pathStack 给子页面使用
  @Provide('NavPathStack') pathStack: NavPathStack = new NavPathStack();

  // 主题相关状态
  @State themeState: ThemeAwareState = new ThemeAwareState();
  private themeManager: ThemeManager = ThemeManager.getInstance();
  
  // 字体相关状态
  @State fontState: FontAwareState = new FontAwareState();
  @StorageLink('appFontFamily') @Watch('onAppFontFamilyChange') appFontFamily: string = 'HarmonyOS Sans';
  @State private fontRefreshKey: number = 0;
  private welcomeGuideManager: WelcomeGuideManager = WelcomeGuideManager.getInstance();
  private contentFilterManager: ContentFilterManager = ContentFilterManager.getInstance();
  private privacyModeManager: PrivacyModeManager = PrivacyModeManager.getInstance();
  private sfwModeListener: ((enabled: boolean) => void) | null = null;
  private privacyModeListener: ((isPrivacy: boolean) => void) | null = null;
  private componentId: string = 'MainMenuPage';
  
  // 隐私模式状态
  @State private isPrivacyMode: boolean = false;

  // 底部导航状态
  @State currentTabIndex: number = TabIndex.HOME;
  private tabsController: TabsController = new TabsController();

  // 引导相关状态
  @State private fromGuide: boolean = false;
  @State private targetPage: string = '';
  @State private targetTab: number = -1;


  // 轮播相关状态
  @State currentBannerIndex: number = 0;
  private swiperController: SwiperController = new SwiperController();

  // 漫画列表相关状态
  @State mangaList: Manga[] = [];
  @State isLoadingMangaList: boolean = false;
  @State isRefreshing: boolean = false;
  private dataManager: DataManager = DataManager.getInstance();
  private dataService: DataService = DataService.getInstance();
  @State recentCoverAspectInfos: CoverAspectInfo[] = [];

  // 书库筛选和视图相关状态
  @State libraryContentType: LibraryContentType = LibraryContentType.MANGA; // 书库内容类型（漫画/电子书）
  @State libraryFilterType: LibraryFilterType = LibraryFilterType.ALL; // 默认选择"全部"
  @State libraryViewMode: LibraryViewMode = LibraryViewMode.GRID;
  @State showLibraryFilterDialog: boolean = false;
  @State showLibraryFilterPopup: boolean = false;
  @State filteredMangaList: Manga[] = [];
  
  // 分类书架相关状态
  private categoryManager: BookshelfCategoryManager = BookshelfCategoryManager.getInstance();
  @State bookshelfCategories: BookshelfCategory[] = [];
  @State selectedCategoryId: string = ''; // 当前选中的分类ID（用于展开详情）
  @State showCategoryDetail: boolean = false; // 是否显示分类详情
  @State showCreateCategoryDialog: boolean = false; // 是否显示创建分类对话框
  @State showEditCategoryDialog: boolean = false; // 是否显示编辑分类对话框
  @State editingCategory: BookshelfCategory | null = null; // 正在编辑的分类
  @State newCategoryName: string = ''; // 新分类名称
  @State showMoveToCategoryDialog: boolean = false; // 是否显示移动到分类对话框
  @State categoryDetailAnimationProgress: number = 0; // 分类详情展开动画进度
  @State movingMangaId: string = ''; // 正在移动的漫画ID
  @State movingEBookId: string = ''; // 正在移动的电子书ID
  @State movingNovelId: string = ''; // 正在移动的小说ID
  @State movingContentType: string = 'manga'; // 正在移动的内容类型
  @State isCategoryEditMode: boolean = false; // 是否处于分类编辑模式（用于拖动排序）
  @State draggingCategoryId: string = ''; // 正在拖动的分类ID

  // 多选模式相关状态
  @State isMultiSelectMode: boolean = false;
  @State selectedMangaIds: Set<string> = new Set();
  @State isDeletingManga: boolean = false;
  // 列表条目左滑删除手势相关状态（仅用于书库 LIST 样式）
  @State private activeSwipeId: string = '';
  @State private isSwipeActive: boolean = false;
  @State private swipeOffset: number = 0; // 当前激活条目的左滑偏移量（px）
  @State private swipeThreshold: number = 100; // 左滑删除触发阈值（px）

  // 电子书相关状态
  @State ebookList: EBook[] = [];
  @State filteredEbookList: EBook[] = [];
  @State isLoadingEbookList: boolean = false;
  private ebookDataManager: EBookDataManager = EBookDataManager.getInstance();

  // PDF电子书相关状态（contentType='ebook'的漫画，显示在电子书列表中，但使用漫画阅读器）
  @State pdfEbookList: Manga[] = [];
  @State filteredPdfEbookList: Manga[] = [];

  // 电子书多选模式相关状态
  @State isEBookMultiSelectMode: boolean = false;
  @State selectedEBookIds: Set<string> = new Set();
  @State isDeletingEBook: boolean = false;
  // 电子书列表条目左滑删除手势相关状态
  @State private activeEBookSwipeId: string = '';
  @State private isEBookSwipeActive: boolean = false;
  @State private ebookSwipeOffset: number = 0;

  // 小说相关状态
  @State novelList: NovelBook[] = [];
  @State filteredNovelList: NovelBook[] = [];
  @State isLoadingNovelList: boolean = false;
  private novelDataManager: NovelDataManager | null = null;
  // 小说多选模式相关状态
  @State isNovelMultiSelectMode: boolean = false;
  @State selectedNovelIds: Set<string> = new Set();
  @State isDeletingNovel: boolean = false;
  // 小说列表条目左滑删除手势相关状态
  @State private activeNovelSwipeId: string = '';
  @State private isNovelSwipeActive: boolean = false;
  @State private novelSwipeOffset: number = 0;


  // 图源仓库相关状态
  @State showSourceRepoDialog: boolean = false;
  @State sourceRepoUrl: string = '';
  @State isSyncingRepo: boolean = false;
  @State savedRepositories: SavedRepository[] = [];
  @State selectedRepositoryId: string = '';
  @State showRepositorySelector: boolean = false;
  @State showDeleteRepoPopup: boolean = false;
  @State repositoryToDelete: SavedRepository | null = null;
  @State syncLogMessages: string[] = []; // 同步日志消息
  @State syncProgress: number = 0; // 同步进度 (0-100)
  @State syncProgressMessage: string = ''; // 同步进度消息
  private sourceRepoDialogController: CustomDialogController | undefined = undefined;
  private repositoryManager: SourceRepositoryManager = SourceRepositoryManager.getInstance();

  // 最近阅读相关状态
  @State recentReadingList: Manga[] = [];
  @State recentEBookList: EBook[] = [];
  @State recentNovelList: NovelBook[] = []; // 最近阅读的小说
  @State isLoadingRecentReading: boolean = false;
  private readonly RECENT_HISTORY_LIMIT: number = 100;
  
  // 后台模糊遮罩相关状态
  @StorageProp('isInBackground') isInBackground: boolean = false;
  @StorageProp('backgroundBlurEnabled') backgroundBlurEnabled: boolean = false;
  @StorageProp('backgroundBlurBgType') backgroundBlurBgType: string = 'solid';
  @StorageProp('backgroundBlurBgImage') backgroundBlurBgImage: string = '';
  @StorageProp('backgroundBlurIconType') backgroundBlurIconType: string = 'shield';

  // 发现页面相关状态
  @State allTags: string[] = []; // 所有标签（按出现次数倒序）
  @State allAuthors: string[] = []; // 所有作者（按出现次数倒序）
  @State selectedTags: Set<string> = new Set(); // 选中的标签（支持多选）
  @State selectedAuthors: Set<string> = new Set(); // 选中的作者（支持多选）
  @State showTagPopup: boolean = false; // 是否显示标签选择弹窗
  @State showAuthorPopup: boolean = false; // 是否显示作者选择弹窗
  @State discoveredMangaList: Manga[] = []; // 发现页面筛选后的漫画列表
  @State discoveredEBookList: EBook[] = []; // 发现页面筛选后的电子书列表
  @State discoveredNovelList: NovelBook[] = []; // 发现页面筛选后的小说列表
  @State discoverContentType: 'manga' | 'ebook' | 'novel' | 'all' = 'all'; // 发现页面内容类型筛选
  @State filteredMangaCount: number = 0; // 当前筛选条件下的漫画数量
  @State filteredEBookCount: number = 0; // 当前筛选条件下的电子书数量
  @State filteredNovelCount: number = 0; // 当前筛选条件下的小说数量
  @State isRefreshingDiscover: boolean = false; // 是否正在刷新发现页面

  // 图源相关状态
  @State sourceList: SourceInfo[] = []; // 图源列表
  @State filteredSourceList: SourceInfo[] = []; // 筛选后的图源列表
  @State sourceSearchKeyword: string = ''; // 图源搜索关键词
  @State showSourceSearchDialog: boolean = false; // 是否显示图源搜索对话框
  @State sourceSearchInput: string = ''; // 图源搜索输入框内容
  @State searchTargetSource: SourceInfo | null = null; // 搜索目标图源
  @State isLoadingSourceList: boolean = false; // 是否正在加载图源列表
  @State isRefreshingSourceList: boolean = false; // 是否正在下拉刷新图源列表
  @State hasSourceUpdate: boolean = false; // 是否有图源更新
  @State sourceViewMode: LibraryViewMode = LibraryViewMode.LIST; // 图源视图模式（LIST/GRID）
  @State sourceTypeFilter: 'all' | 'manga' | 'ebook' | 'novel' = 'all'; // 图源类型筛选
  @State showProxyDialog: boolean = false; // 是否显示代理配置对话框
  @State proxyConfig: ProxyConfig = DEFAULT_PROXY_CONFIG; // 代理配置
  @State proxyTestResults: string = ''; // 代理测试结果
  @State isTestingProxy: boolean = false; // 是否正在测试代理
  @State proxySourceList: SourceInfo[] = []; // 需要代理的图源列表
  private sourceManager: SourceManager = SourceManager.getInstance(); // 图源管理器
  private sourceUpdateManager: SourceUpdateManager = SourceUpdateManager.getInstance(); // 图源更新管理器
  // WebView容器引用
  private webViewContainerRef: WebViewContainer | null = null;

  // 响应式布局相关状态
  private deviceManager: DeviceAdaptationManager = DeviceAdaptationManager.getInstance();
  private deviceChangeListener: DeviceChangeListener | null = null;
  @State responsive_gridColumns: number = 3; // 响应式网格列数
  @State responsive_gridGap: number = 12; // 响应式网格间距
  @State responsive_contentPadding: number = 16; // 响应式内容边距
  @State responsive_isLandscape: boolean = false; // 是否横屏
  @State responsive_tabBarPosition: BarPosition = BarPosition.End; // 响应式标签栏位置
  @State responsive_tabBarVertical: boolean = false; // 响应式标签栏是否垂直
  @State responsive_homeGridColumns: number = 2; // 首页网格列数（横屏：SM=4, MD=6, LG=10）
  @State responsive_libraryGridColumns: number = 3; // 书库网格列数（横屏：SM=5, MD=7, LG=10）
  @State responsive_discoverGridColumns: number = 3; // 发现页网格列数（横屏：SM=5, MD=7, LG=10）
  @State barRenderKey: number = 0; // 顶栏/底栏重渲染触发器，屏幕方向或折叠状态变化时递增
  private readonly BOTTOM_BAR_HEIGHT: number = 56;
  private readonly BOTTOM_BAR_MARGIN_BOTTOM: number = 24;
  private readonly BOTTOM_BAR_MARGIN_LEFT: number = 12;
  private readonly BOTTOM_BAR_MARGIN_RIGHT: number = 12;


  @StorageProp('statusBarHeight') statusBarHeight: number = 0;
  @StorageProp('navigationBarHeight') navigationBarHeight: number = 0;

  /**
   * 计算顶部避让值：折叠屏设备不应用避让
   * 因为WindowManager已全局设置透明系统栏，无需额外避让
   */
  // private getTopPadding(): number {
  //   const deviceInfo = this.deviceManager.getDeviceInfo();
  //   // 折叠屏设备不应用避让（所有状态：折叠、展开、半折叠）
  //   if (deviceInfo.isFoldable) {
  //     logger.debug(TAG, `折叠屏设备（${this.getFoldStatusDescription(deviceInfo.foldStatus)}），禁用顶部避让`);
  //     return 0;
  //   }
  //   return this.statusBarHeight;
  // }

  /**
   * 计算底部避让值：折叠屏设备不应用避让
   * 因为WindowManager已全局设置透明系统栏，无需额外避让
   */
  // private getBottomPadding(): number {
  //   const deviceInfo = this.deviceManager.getDeviceInfo();
  //   // 折叠屏设备不应用避让（所有状态：折叠、展开、半折叠）
  //   if (deviceInfo.isFoldable) {
  //     logger.debug(TAG, `折叠屏设备（${this.getFoldStatusDescription(deviceInfo.foldStatus)}），禁用底部避让`);
  //     return 0;
  //   }
  //   return this.navigationBarHeight;
  // }

  /**
   * 获取折叠状态描述（用于日志）
   */
  private getFoldStatusDescription(status: FoldStatus): string {
    switch (status) {
      case FoldStatus.EXPANDED:
        return '展开';
      case FoldStatus.FOLDED:
        return '折叠';
      case FoldStatus.HALF_FOLDED:
        return '半折叠';
      default:
        return '未知';
    }
  }

  // 轮播内容数据 - 使用深色渐变背景，避免与主题蓝色融合
  private bannerData: Array<bannerData> = [
    {
      title: '欢迎使用漫匣',
      subtitle: '尽享精彩的漫画世界',
      image: $r('app.media.icon'),
      backgroundColor: '#1A1A2E'  // 深紫蓝色
    },
    {
      title: '管理您的漫画/电子书资源',
      subtitle: '热门连载，经典完结作品',
      image: $r('app.media.mangabook'),
      backgroundColor: '#16213E'  // 深海军蓝
    },
    {
      title: '个性化分析',
      subtitle: '根据您的阅读习惯分析阅读偏好',
      image: $r('app.media.ic_theme'),
      backgroundColor: '#0F3460'  // 深靛蓝色
    }
  ];

  // 系统初始化状态
  @State private isSystemInitialized: boolean = false;
  @State private initializationProgress: string = '正在初始化...';

  // 版本信息
  @State public appVersion: string = '0.0.5';
  @State public systemVersion: string = '';

  @StorageProp('enable_log_floating_window') private enableLogFloatingWindow: boolean = false;
  @StorageLink('advanced_mode_enabled') private advancedModeEnabled: boolean = true;
  @StorageProp('force_tablet_mode') private forceTabletMode: boolean = false;
  @StorageProp('force_landscape_mode') private forceLandscapeMode: boolean = false;

  // 导航标签配置
  private tabConfigs: TabConfig[] = [
    {
      title: '首页',
      icon: $r('app.media.ic_home_normal'),
      selectedIcon: $r('app.media.ic_home_selected'),
      systemIcon: $r('sys.symbol.house_fill'),
      useSystemIcon: true,
      hasMultiColor: true, // 首页图标支持多色效果
      index: TabIndex.HOME,
      required: false
    },
    {
      title: '书库',
      icon: $r('app.media.ic_library_normal'),
      selectedIcon: $r('app.media.ic_library_selected'),
      systemIcon: $r('sys.symbol.books_vertical_fill'),
      useSystemIcon: true,
      hasMultiColor: true, // 书库图标支持多色效果
      index: TabIndex.LIBRARY,
      required: true // 必须显示
    },
    {
      title: '发现',
      icon: $r('app.media.ic_discover_selected'),
      selectedIcon: $r('app.media.ic_discover_selected'),
      systemIcon: $r('sys.symbol.crown'),
      useSystemIcon: true,
      hasMultiColor: true, // 发现图标支持多色效果
      index: TabIndex.DISCOVER,
      required: false
    },
    {
      title: '图源',
      icon: $r('app.media.ic_source_normal'),
      selectedIcon: $r('app.media.ic_source_selected'),
      systemIcon: $r('sys.symbol.more'),
      useSystemIcon: true,
      hasMultiColor: false, // 图源图标单色
      index: TabIndex.SOURCE,
      required: false
    },
    // {
    //   title: '书源',
    //   icon: $r('app.media.ic_source_normal'),
    //   selectedIcon: $r('app.media.ic_source_selected'),
    //   index: TabIndex.BOOK_SOURCE,
    //   required: false
    // },
    {
      title: '设置',
      icon: $r('app.media.ic_settings'),
      selectedIcon: $r('app.media.ic_settings'),
      systemIcon: $r('sys.symbol.gearshape'),
      useSystemIcon: true,
      hasMultiColor: false, // 设置图标不支持多色，需要直接着色
      index: TabIndex.SETTINGS,
      required: true // 必须显示
    }
  ];

  // 可见标签索引列表（从设置加载）
  @State private visibleTabIndices: number[] = [];
  // 标签自定义对话框
  @State private showTabCustomDialog: boolean = false;
  @State private tempVisibleTabIndices: number[] = [];

  aboutToAppear() {
    logger.lifecycle(TAG, '🚀 漫画阅读应用启动');
    logger.info(TAG, `初始化时appFontFamily值: ${this.appFontFamily}`);

    // 使用 @StorageProp 自动响应设置变化，无需手动从 AppStorage 加载

    // 初始化代理管理器
    ProxyManager.getInstance().initialize().then(() => {
      this.proxyConfig = ProxyManager.getInstance().getConfig();
    });

    // 初始化分类书架管理器
    this.categoryManager.initialize().then(() => {
      this.bookshelfCategories = this.categoryManager.getCategories();
      logger.info(TAG, `分类书架初始化完成，共 ${this.bookshelfCategories.length} 个分类`);
    });

    // 加载可见标签配置
    this.loadVisibleTabs();

    // 处理路由参数
    this.handleRouteParams();

    // 请求通知权限（首次进入主页面时）
    this.requestNotificationPermission();

    // 初始化交互管理器
    InteractionManager.getInstance().initialize();

    // 初始化主题感知
    ThemeAwareHelper.initializeThemeAware(
      this.componentId,
      this.themeState,
      (newTheme: ThemeType) => {
        logger.info(TAG, `主题已切换到: ${newTheme}`);
      },
      (newState: ThemeAwareState) => {
        // 重新赋值整个themeState对象以触发UI更新
        this.themeState = newState;
      }
    );

    // 初始化字体感知
    FontAwareHelper.initializeFontAware(
      this.componentId,
      this.fontState,
      (newState: FontAwareState) => {
        this.fontState = newState;
        logger.info(TAG, `字体设置已更新: ${newState.appFontFamily}`);
      }
    );

    // 订阅漫画导入完成事件
    eventBus.subscribe(GameEvent.MANGA_IMPORT_COMPLETED, (payload: IEventPayload) => {
      const mangaPayload = payload as MangaImportCompletedPayload;
      logger.info(TAG, `收到漫画导入完成事件，成功导入 ${mangaPayload.importedCount} 个漫画`);
      // 刷新漫画列表
      this.loadMangaList();
    });

    // 订阅漫画删除事件
    eventBus.subscribe(GameEvent.MANGA_DELETED, (payload: IEventPayload) => {
      logger.info(TAG, `收到漫画删除事件，刷新书库列表`);
      // 刷新漫画列表并切换到书库标签
      this.loadMangaList();
      this.currentTabIndex = TabIndex.LIBRARY;
      this.tabsController.changeIndex(TabIndex.LIBRARY);
    });

    // 注册隐私模式监听器
    this.privacyModeListener = (isPrivacy: boolean) => {
      logger.info(TAG, `隐私模式状态变化: ${isPrivacy}`);
      this.isPrivacyMode = isPrivacy;
      // 隐私模式下自动切换到传统视图（不支持书架视图）
      if (isPrivacy && this.libraryViewMode === LibraryViewMode.CATEGORY) {
        this.libraryViewMode = LibraryViewMode.GRID;
      }
      // 刷新书库内容
      this.loadMangaList();
      this.loadEBookList();
      this.loadNovelList();
    };
    this.privacyModeManager.addListener(this.privacyModeListener);

    // 注册SFW模式监听器，实现实时刷新
    this.sfwModeListener = (enabled: boolean) => {
      logger.info(TAG, `SFW模式切换: ${enabled}, 立即刷新页面`);
      // 根据当前标签页刷新对应数据
      switch (this.currentTabIndex) {
        case TabIndex.LIBRARY:
          this.applyLibraryFilter(); // 重新应用筛选，包含NSFW过滤
          break;
        case TabIndex.DISCOVER:
          this.applyDiscoverFilter(); // 发现页也需要过滤
          break;
        case TabIndex.SOURCE:
          // 图源页面也需要刷新
          this.loadSources();
          break;
      }
    };
    this.contentFilterManager.addListener(this.sfwModeListener);
    
    this.initializeSystem();
    this.loadVersionInfo();
    this.initializeUserManualIfNeeded(); // 首次运行时添加使用手册
    this.checkAndShowChangelog(); // 新版本首次启动显示更新日志
    this.initializeContentData(); // 加载漫画、电子书并提取标签作者
    this.loadLibraryViewMode();
    this.loadRecentReadingList();
    this.initializeRepositoryManager(); // 初始化仓库管理器（会在完成后自动加载图源列表）
    this.checkSourceUpdates(); // 检查图源更新

    // 初始化响应式布局
    this.initializeResponsiveLayout();

    // 处理引导跳转
    if (this.fromGuide) {
      this.handleGuideNavigation();
    }
  }

  /**
   * 初始化响应式布局
   */
  private initializeResponsiveLayout(): void {
    try {
      // 更新响应式参数
      this.applyOrientationPreference();
      this.updateResponsiveParams();

      // 创建并注册设备变化监听器
      this.deviceChangeListener = (deviceInfo: DeviceInfo) => {
        logger.info(TAG, `设备状态变化: 断点=${deviceInfo.breakpoint}, 方向=${deviceInfo.orientation}, 折叠状态=${this.getFoldStatusDescription(deviceInfo.foldStatus)}`);
        this.applyOrientationPreference();
        this.updateResponsiveParams();
        // 触发顶栏和底栏重新渲染
        this.barRenderKey++;
        logger.info(TAG, `顶栏/底栏重渲染触发: barRenderKey=${this.barRenderKey}`);
      };

      this.deviceManager.addListener(this.deviceChangeListener);

      logger.info(TAG, '✅ 响应式布局初始化完成');
    } catch (error) {
      logger.error(TAG, '响应式布局初始化失败', String(error));
    }
  }

  private applyOrientationPreference(): void {
    try {
      const ui = this.getUIContext();
      if (this.forceLandscapeMode) {
        WindowManager.setPreferredOrientationLandscape(ui);
      } else {
        WindowManager.setPreferredOrientationAuto(ui);
      }
    } catch (error) {
      logger.error(TAG, '应用横屏偏好失败', String(error));
    }
  }

  /**
   * 更新响应式布局参数
   */
  private updateResponsiveParams(): void {
    const deviceInfo = this.deviceManager.getDeviceInfo();
    const layoutParams = this.forceTabletMode
      ? ResponsiveLayoutHelper.getLayoutParamsForBreakpoint(Breakpoint.MD)
      : ResponsiveLayoutHelper.getLayoutParams();

    this.responsive_gridColumns = layoutParams.gridColumns;
    this.responsive_gridGap = layoutParams.gridGap;
    this.responsive_contentPadding = layoutParams.contentPadding;
    this.responsive_isLandscape = deviceInfo.isLandscape;

    // 根据断点和横屏状态设置各页面的网格列数
    const breakpoint = this.forceTabletMode ? Breakpoint.MD : deviceInfo.breakpoint;
    if (deviceInfo.isLandscape || this.forceTabletMode) {
      // 横屏模式下的列数配置
      switch (breakpoint) {
        case Breakpoint.SM:
          this.responsive_homeGridColumns = 4;     // 首页：SM=4列
          this.responsive_libraryGridColumns = 5;  // 书库：SM=5列
          this.responsive_discoverGridColumns = 5; // 发现：SM=5列
          break;
        case Breakpoint.MD:
          this.responsive_homeGridColumns = 6;     // 首页：MD=6列
          this.responsive_libraryGridColumns = 7;  // 书库：MD=7列
          this.responsive_discoverGridColumns = 7; // 发现：MD=7列
          break;
        case Breakpoint.LG:
          this.responsive_homeGridColumns = 10;    // 首页：LG=10列
          this.responsive_libraryGridColumns = 10; // 书库：LG=10列
          this.responsive_discoverGridColumns = 10;// 发现：LG=10列
          break;
        default: // XS
          this.responsive_homeGridColumns = 4;
          this.responsive_libraryGridColumns = 5;
          this.responsive_discoverGridColumns = 5;
          break;
      }
    } else {
      // 竖屏模式下的列数配置
      this.responsive_homeGridColumns = 2;     // 首页：竖屏2列
      this.responsive_libraryGridColumns = 3;  // 书库：竖屏3列
      this.responsive_discoverGridColumns = 3; // 发现：竖屏3列
    }

    // 平板模式或横屏大屏设备：顶栏固定在顶部
    if (this.forceTabletMode) {
      this.responsive_tabBarPosition = BarPosition.Start;
      this.responsive_tabBarVertical = false;
    } else if (deviceInfo.isLandscape && (deviceInfo.breakpoint === Breakpoint.MD || deviceInfo.breakpoint === Breakpoint.LG)) {
      this.responsive_tabBarPosition = BarPosition.Start;
      this.responsive_tabBarVertical = false;
    } else {
      this.responsive_tabBarPosition = BarPosition.End;
      this.responsive_tabBarVertical = false;
    }

    logger.debug(TAG, `响应式参数更新: 列数=${this.responsive_gridColumns}, 首页列数=${this.responsive_homeGridColumns}, 书库列数=${this.responsive_libraryGridColumns}, 发现列数=${this.responsive_discoverGridColumns}, 间距=${this.responsive_gridGap}`);
  }

  private getGridColumnsTemplate(): string {
    const template: string[] = [];
    let i: number = 0;
    while (i < this.responsive_gridColumns) {
      template.push('1fr');
      i = i + 1;
    }
    return template.join(' ');
  }

  /**
   * 获取首页网格列模板
   */
  private getHomeGridColumnsTemplate(): string {
    const template: string[] = [];
    let i: number = 0;
    while (i < this.responsive_homeGridColumns) {
      template.push('1fr');
      i = i + 1;
    }
    return template.join(' ');
  }

  /**
   * 获取书库网格列模板
   */
  private getLibraryGridColumnsTemplate(): string {
    const template: string[] = [];
    let i: number = 0;
    while (i < this.responsive_libraryGridColumns) {
      template.push('1fr');
      i = i + 1;
    }
    return template.join(' ');
  }

  /**
   * 初始化动画控制器
   */

  /**
   * 获取发现页网格列模板
   */
  private getDiscoverGridColumnsTemplate(): string {
    const template: string[] = [];
    let i: number = 0;
    while (i < this.responsive_discoverGridColumns) {
      template.push('1fr');
      i = i + 1;
    }
    return template.join(' ');
  }


  private getBottomBarY(): number {
    const deviceInfo = this.deviceManager.getDeviceInfo();
    const y: number = deviceInfo.screenHeight - this.navigationBarHeight - this.BOTTOM_BAR_HEIGHT - this.BOTTOM_BAR_MARGIN_BOTTOM;
    return y > 0 ? y : 0;
  }

  private getBottomBarX(): number {
    return this.BOTTOM_BAR_MARGIN_LEFT;
  }

  private getBottomBarWidth(): number {
    const deviceInfo = this.deviceManager.getDeviceInfo();
    const w: number = deviceInfo.screenWidth - this.BOTTOM_BAR_MARGIN_LEFT - this.BOTTOM_BAR_MARGIN_RIGHT;
    return w > 0 ? w : 0;
  }

  // ==================== 动画控制器绑定方法 ====================


  // ==================== 图源相关方法 ====================

  /**
   * 加载图源列表
   */
  private async loadSources(): Promise<void> {
    try {
      this.isLoadingSourceList = true;
      logger.info(TAG, '开始加载图源列表...');

      this.sourceList = await this.sourceManager.getAllSources();
      this.applySourceFilters(); // 应用当前筛选条件

      logger.info(TAG, `加载了 ${this.sourceList.length} 个图源`);
    } catch (error) {
      logger.error(TAG, '加载图源列表失败', String(error));
      this.showToast('加载图源列表失败');
    } finally {
      this.isLoadingSourceList = false;
    }
  }

  /**
   * 搜索图源
   */
  private searchSources(keyword: string): void {
    this.sourceSearchKeyword = keyword;
    this.applySourceFilters();
  }

  /**
   * 应用图源筛选（关键词 + 类型）
   */
  private applySourceFilters(): void {
    let filtered = [...this.sourceList];
    
    // 先按类型筛选
    if (this.sourceTypeFilter !== 'all') {
      filtered = filtered.filter((source: SourceInfo) => {
        return source.type === this.sourceTypeFilter;
      });
    }
    
    // 再按关键词筛选
    const keyword = this.sourceSearchKeyword.trim();
    if (keyword) {
      const lowerKeyword = keyword.toLowerCase();
      filtered = filtered.filter((source: SourceInfo) => {
        return source.name.toLowerCase().includes(lowerKeyword) ||
               source.baseUrl.toLowerCase().includes(lowerKeyword) ||
               (source.description && source.description.toLowerCase().includes(lowerKeyword));
      });
    }
    
    // 应用NSFW过滤
    const nsfwFiltered = this.contentFilterManager.filterContentList(filtered);
    
    this.filteredSourceList = nsfwFiltered;
    logger.debug(TAG, `筛选图源: type=${this.sourceTypeFilter}, keyword="${keyword}", 结果=${nsfwFiltered.length}/${filtered.length}个, SFW模式: ${this.contentFilterManager.isSFWModeEnabled()}`);
    
    // 记录NSFW过滤统计
    if (this.contentFilterManager.isSFWModeEnabled()) {
      const stats = this.contentFilterManager.getFilterStats(filtered);
      logger.info(TAG, `图源NSFW过滤: 已过滤=${stats.filtered}个`);
    }
  }

  /**
   * 切换图源类型筛选
   */
  private cycleSourceTypeFilter(): void {
    const types: Array<'all' | 'manga' | 'ebook' | 'novel'> = ['all', 'manga', 'ebook', 'novel'];
    const currentIndex = types.indexOf(this.sourceTypeFilter);
    const nextIndex = (currentIndex + 1) % types.length;
    this.sourceTypeFilter = types[nextIndex];
    this.applySourceFilters();
    
    const typeNames: Record<string, string> = {
      'all': '全部',
      'manga': '漫画源',
      'ebook': '电子书源',
      'novel': '小说源'
    };
    this.showToast(`显示: ${typeNames[this.sourceTypeFilter]}`);
  }

  /**
   * 获取当前图源类型筛选的图标
   */
  private getSourceTypeFilterIcon(): Resource {
    switch (this.sourceTypeFilter) {
      case 'manga':
        return $r('app.media.ic_source_manga');
      case 'ebook':
        return $r('app.media.ic_source_ebook');
      case 'novel':
        return $r('app.media.ic_source_novel');
      default:
        return $r('app.media.ic_source_all');
    }
  }

  /**
   * 获取图源列表标题
   */
  private getSourceListTitle(): string {
    const typeNames: Record<string, string> = {
      'all': '全部图源',
      'manga': '漫画源',
      'ebook': '电子书源',
      'novel': '小说源'
    };
    const typeName = typeNames[this.sourceTypeFilter];
    return `${typeName} (${this.filteredSourceList.length}/${this.sourceList.length})`;
  }

  /**
   * 获取空状态标题
   */
  private getEmptySourceTitle(): string {
    if (this.sourceSearchKeyword) {
      return '未找到匹配的图源';
    }
    switch (this.sourceTypeFilter) {
      case 'manga':
        return '暂无漫画源';
      case 'ebook':
        return '暂无电子书源';
      case 'novel':
        return '暂无小说源';
      default:
        return '暂无图源';
    }
  }

  /**
   * 获取空状态描述
   */
  private getEmptySourceDescription(): string {
    switch (this.sourceTypeFilter) {
      case 'manga':
        return '漫画源用于获取在线漫画内容';
      case 'ebook':
        return '电子书源用于获取在线电子书内容';
      case 'novel':
        return '小说源用于获取在线小说内容';
      default:
        return '本应用不包含任何内置图源';
    }
  }

  /**
   * 获取空状态提示
   */
  private getEmptySourceHint(): string {
    switch (this.sourceTypeFilter) {
      case 'manga':
        return '可通过图源仓库同步漫画源，或切换到"全部"查看其他类型';
      case 'ebook':
        return '可通过图源仓库同步电子书源，或切换到"全部"查看其他类型';
      case 'novel':
        return '可通过图源仓库同步小说源，或切换到"全部"查看其他类型';
      default:
        return '推荐使用图源仓库方式同步在线仓库的图源';
    }
  }

  /**
   * 构建图源使用说明
   */
  @Builder
  buildSourceUsageGuide() {
    Column({ space: 8 }) {
      if (this.sourceTypeFilter === 'all') {
        // 全部模式下显示完整使用说明
        Text('使用说明')
          .fontSize(16)
          .fontWeight(FontWeight.Medium)
          .fontFamily(this.appFontFamily)
          .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_primary', this.themeState.currentTheme))
        
        Text('• 本应用不包含任何内置图源，需用户自行导入')
          .fontSize(14)
          .fontFamily(this.appFontFamily)
          .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_secondary', this.themeState.currentTheme))
        
        Text('• 图源是JSON格式的配置文件，定义了漫画数据的获取方式')
          .fontSize(14)
          .fontFamily(this.appFontFamily)
          .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_secondary', this.themeState.currentTheme))
        
        Text('• 点击“图源管理”按钮，可以导入本地图源或同步在线仓库')
          .fontSize(14)
          .fontFamily(this.appFontFamily)
          .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_secondary', this.themeState.currentTheme))
        
        Text('• 支持单个图源或图源数组格式的JSON文件')
          .fontSize(14)
          .fontFamily(this.appFontFamily)
          .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_secondary', this.themeState.currentTheme))
        
        Text('• 也可以输入仓库地址同步在线仓库的图源')
          .fontSize(14)
          .fontFamily(this.appFontFamily)
          .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_secondary', this.themeState.currentTheme))
        
        Text('• 用户需自行承担使用第三方图源的风险和责任')
          .fontSize(13)
          .fontFamily(this.appFontFamily)
          .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_muted', this.themeState.currentTheme))
          .opacity(0.8)
      } else if (this.sourceTypeFilter === 'manga') {
        // 漫画源模式
        Text('漫画源说明')
          .fontSize(16)
          .fontWeight(FontWeight.Medium)
          .fontFamily(this.appFontFamily)
          .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_primary', this.themeState.currentTheme))
        
        Text('• 漫画源用于获取在线漫画内容，支持搜索、浏览和阅读')
          .fontSize(14)
          .fontFamily(this.appFontFamily)
          .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_secondary', this.themeState.currentTheme))
        
        Text('• 点击漫画源卡片可进入该图源浏览漫画')
          .fontSize(14)
          .fontFamily(this.appFontFamily)
          .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_secondary', this.themeState.currentTheme))
        
        Text('• 漫画源需要在source.json中设置 "type": "manga"')
          .fontSize(13)
          .fontFamily(this.appFontFamily)
          .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_muted', this.themeState.currentTheme))
          .opacity(0.8)
      } else if (this.sourceTypeFilter === 'ebook') {
        // 电子书源模式
        Text('电子书源说明')
          .fontSize(16)
          .fontWeight(FontWeight.Medium)
          .fontFamily(this.appFontFamily)
          .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_primary', this.themeState.currentTheme))
        
        Text('• 电子书源用于获取在线电子书内容，支持EPUB、PDF等格式')
          .fontSize(14)
          .fontFamily(this.appFontFamily)
          .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_secondary', this.themeState.currentTheme))
        
        Text('• 点击电子书源卡片可进入该图源浏览电子书')
          .fontSize(14)
          .fontFamily(this.appFontFamily)
          .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_secondary', this.themeState.currentTheme))
        
        Text('• 电子书源需要在source.json中设置 "type": "ebook"')
          .fontSize(13)
          .fontFamily(this.appFontFamily)
          .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_muted', this.themeState.currentTheme))
          .opacity(0.8)
      } else if (this.sourceTypeFilter === 'novel') {
        // 小说源模式
        Text('小说源说明')
          .fontSize(16)
          .fontWeight(FontWeight.Medium)
          .fontFamily(this.appFontFamily)
          .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_primary', this.themeState.currentTheme))
        
        Text('• 小说源用于获取在线小说内容，支持章节阅读')
          .fontSize(14)
          .fontFamily(this.appFontFamily)
          .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_secondary', this.themeState.currentTheme))
        
        Text('• 点击小说源卡片可进入该图源浏览小说')
          .fontSize(14)
          .fontFamily(this.appFontFamily)
          .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_secondary', this.themeState.currentTheme))
        
        Text('• 小说源需要在source.json中设置 "type": "novel"')
          .fontSize(13)
          .fontFamily(this.appFontFamily)
          .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_muted', this.themeState.currentTheme))
          .opacity(0.8)
      }
    }
    .width('100%')
    .padding(16)
    .backgroundColor(Color.Transparent)
    .borderRadius(12)
    .margin({ left: 16, right: 16 })
  }

  /**
   * 刷新图源列表
   */
  private async refreshSources(): Promise<void> {
    this.sourceManager.clearCache();
    await this.loadSources();
    this.showToast('图源列表已刷新');
  }

  /**
   * 检查图源更新
   */
  private async checkSourceUpdates(): Promise<void> {
    try {
      // 检查是否启用了图源功能并导入了仓库
      const repoUrl = this.sourceUpdateManager.getRepoUrl();
      if (!repoUrl || repoUrl.length === 0) {
        logger.debug(TAG, '未设置图源仓库，跳过更新检查');
        return;
      }

      // 初始化更新管理器
      const context = this.getUIContext().getHostContext() as common.Context;
      if (context) {
        await this.sourceUpdateManager.initialize(context);
      }

      // 检查更新
      const result = await this.sourceUpdateManager.checkForUpdates();
      this.hasSourceUpdate = result.hasUpdate;
      
      if (result.hasUpdate) {
        logger.info(TAG, `发现图源更新: ${result.newSources.length}个新图源, ${result.updatedSources.length}个更新`);
      }
    } catch (error) {
      logger.error(TAG, `检查图源更新失败: ${String(error)}`);
    }
  }

  /**
   * 快速同步图源仓库（用于更新检查后的一键同步）
   */
  private async quickSyncSourceRepository(): Promise<void> {
    try {
      this.showToast('正在同步图源仓库...');
      const success = await this.sourceUpdateManager.syncRepository();
      
      if (success) {
        this.hasSourceUpdate = false;
        await this.refreshSources();
        this.showToast('图源仓库同步完成');
      } else {
        this.showToast('同步失败，请检查网络连接');
      }
    } catch (error) {
      logger.error(TAG, `同步图源仓库失败: ${String(error)}`);
      this.showToast('同步失败');
    }
  }

  /**
   * 解析并修复仓库URL
   * 自动处理空格、换行等情况，拼接完整的URL
   */
  private parseAndFixRepoUrl(input: string): string {
    if (!input) return '';
    
    // 移除所有空格、换行、制表符
    let cleaned = input.replace(/[\s\r\n\t]+/g, '');
    
    // 如果不是http或https开头，直接返回清理后的内容
    if (!cleaned.startsWith('http://') && !cleaned.startsWith('https://')) {
      return cleaned;
    }
    
    // 检查是否以index.min.json或index.main.json结尾
    if (cleaned.endsWith('index.min.json') || cleaned.endsWith('index.main.json')) {
      return cleaned;
    }
    
    // 尝试在清理后的字符串中查找index.min.json或index.main.json
    const minJsonIndex = cleaned.indexOf('index.min.json');
    const mainJsonIndex = cleaned.indexOf('index.main.json');
    
    if (minJsonIndex !== -1) {
      // 截取到index.min.json结束
      return cleaned.substring(0, minJsonIndex + 'index.min.json'.length);
    }
    
    if (mainJsonIndex !== -1) {
      // 截取到index.main.json结束
      return cleaned.substring(0, mainJsonIndex + 'index.main.json'.length);
    }
    
    // 如果没有找到特定结尾，返回清理后的URL
    return cleaned;
  }

  /**
   * 导入图源
   */
  private async importSource(): Promise<void> {
    try {
      // 获取UIAbilityContext
      const context = this.getUIContext().getHostContext() as common.UIAbilityContext;
      if (!context) {
        this.showToast('无法获取应用上下文');
        logger.error(TAG, '无法获取UIAbilityContext');
        return;
      }

      // 创建文档选择器
      const documentPicker = new picker.DocumentViewPicker(context);
      
      // 设置选择选项 - 只允许选择JSON文件
      const selectOptions: picker.DocumentSelectOptions = {
        maxSelectNumber: 1, // 一次只能选择一个图源文件
        fileSuffixFilters: ['.json'], // 只允许选择JSON文件
      };

      logger.info(TAG, '打开文件选择器，选择图源JSON文件');
      
      // 打开文件选择器
      const selectResult = await documentPicker.select(selectOptions);
      
      if (!selectResult || !selectResult.length || selectResult.length === 0) {
        logger.info(TAG, '用户取消了文件选择');
        return;
      }

      const fileUri = selectResult[0];
      logger.info(TAG, `用户选择了文件: ${fileUri}`);
      
      this.showToast('开始导入图源...');
      
      // 读取文件内容
      const file = fs.openSync(fileUri, fs.OpenMode.READ_ONLY);
      const buffer = new ArrayBuffer(1024 * 1024); // 1MB缓冲区
      const readLen = fs.readSync(file.fd, buffer);
      fs.closeSync(file);
      
      // 使用TextDecoder正确解码UTF-8
      const uint8Array = new Uint8Array(buffer, 0, readLen);
      const decoder = new util.TextDecoder('utf-8', { ignoreBOM: true });
      const jsonContent = decoder.decode(uint8Array);
      
      logger.debug(TAG, `读取到JSON内容，长度: ${jsonContent.length}`);
      
      // 导入图源
      const result = await this.sourceManager.importFromJSON(jsonContent);
      
      if (result.success) {
        this.showToast('图源导入成功！');
        logger.info(TAG, '图源导入成功');
        await this.loadSources();
      } else {
        this.showToast(`导入失败: ${result.error || '未知错误'}`);
        logger.error(TAG, `图源导入失败: ${result.error}`);
      }
    } catch (error) {
      logger.error(TAG, '导入图源失败', String(error));
      this.showToast('导入图源失败，请检查文件格式');
    }
  }

  /**
   * 初始化仓库管理器
   */
  private async initializeRepositoryManager(): Promise<void> {
    try {
      const context = this.getUIContext().getHostContext() as common.UIAbilityContext;
      await this.repositoryManager.initialize(context);
      await this.loadSavedRepositories();
      logger.info(TAG, '仓库管理器初始化完成');
      
      // 仓库管理器初始化完成后，重新加载图源列表以获取图标路径
      await this.loadSources();
    } catch (error) {
      logger.error(TAG, '初始化仓库管理器失败', String(error));
    }
  }

  /**
   * 加载已保存的仓库列表
   */
  private async loadSavedRepositories(): Promise<void> {
    try {
      this.savedRepositories = await this.repositoryManager.getSavedRepositories();
      logger.info(TAG, `加载了 ${this.savedRepositories.length} 个已保存的仓库`);
    } catch (error) {
      logger.error(TAG, '加载已保存仓库失败', String(error));
    }
  }

  /**
   * 打开图源仓库弹窗
   */
  private async openSourceRepoDialog(): Promise<void> {
    try {
      this.sourceRepoUrl = '';
      this.selectedRepositoryId = '';
      this.showRepositorySelector = false;
      await this.loadSavedRepositories();
      
      // 创建弹窗控制器
      this.sourceRepoDialogController = new CustomDialogController({
        builder: () => {
          this.buildSourceRepoDialog();
        },
        alignment: DialogAlignment.Center,
        autoCancel: true,
        cornerRadius: 16,
        customStyle: true
      });
      
      this.sourceRepoDialogController.open();
      logger.info(TAG, '图源仓库弹窗已打开');
    } catch (error) {
      logger.error(TAG, '打开图源仓库弹窗失败', String(error));
      this.showToast('打开弹窗失败，请重试');
    }
  }

  /**
   * 添加同步日志消息
   */
  private addSyncLog(level: 'info' | 'warn' | 'error', message: string): void {
    const timestamp = new Date().toLocaleTimeString();
    const prefix = level === 'info' ? '✓' : (level === 'warn' ? '⚠' : '✗');
    const logLine = `[${timestamp}] ${prefix} ${message}`;
    this.syncLogMessages = [...this.syncLogMessages, logLine];
    // 限制日志行数，保留最近100条
    if (this.syncLogMessages.length > 100) {
      this.syncLogMessages = this.syncLogMessages.slice(-100);
    }
  }

  /**
   * 同步图源仓库
   */
  private async syncSourceRepository(): Promise<void> {
    // 检查是否选择了已保存的仓库
    let urlToSync = this.sourceRepoUrl.trim();
    
    if (this.selectedRepositoryId) {
      const selectedRepo = this.savedRepositories.find(r => r.id === this.selectedRepositoryId);
      if (selectedRepo) {
        urlToSync = selectedRepo.url;
      }
    }
    
    if (!urlToSync) {
      this.showToast('请输入仓库地址或选择已保存的仓库');
      return;
    }

    try {
      this.isSyncingRepo = true;
      this.syncLogMessages = []; // 清空日志
      this.syncProgress = 0;
      this.syncProgressMessage = '正在连接仓库...';
      
      this.addSyncLog('info', `开始同步仓库: ${urlToSync}`);
      logger.info(TAG, `开始同步图源仓库: ${urlToSync}`);
      
      // 创建进度回调
      const progressCallback: SyncProgressCallback = {
        onProgress: (current: number, total: number, message: string) => {
          this.syncProgress = current;
          this.syncProgressMessage = message;
        },
        onLog: (level: 'info' | 'warn' | 'error', message: string) => {
          this.addSyncLog(level, message);
        }
      };
      
      // 使用仓库管理器同步（带进度回调）
      const result = await this.repositoryManager.syncRepositoryFromUrl(
        urlToSync,
        this.selectedRepositoryId ? undefined : '自定义仓库',
        progressCallback
      );
      
      if (result.success) {
        this.addSyncLog('info', result.message);
        this.syncProgress = 100;
        this.syncProgressMessage = '同步完成！';
        logger.info(TAG, `图源仓库同步成功: ${result.message}`);
        
        // 延迟2秒后关闭弹窗，让用户看到完成状态
        setTimeout(() => {
          this.sourceRepoDialogController?.close();
          this.showSourceRepoDialog = false;
          this.isSyncingRepo = false;
        }, 2000);
        
        // 刷新图源列表和已保存仓库
        await this.loadSources();
        await this.loadSavedRepositories();
      } else {
        this.addSyncLog('error', result.message);
        this.syncProgress = 0;
        this.syncProgressMessage = '同步失败 - 请查看上方日志了解详情';
        logger.error(TAG, `图源仓库同步失败: ${result.message}`);
        // 不关闭窗口，让用户能看到错误信息
        // isSyncingRepo 保持 true 以显示日志窗口
      }
      
    } catch (error) {
      // 提取有意义的错误信息
      let errMsg: string;
      if (error instanceof Error) {
        errMsg = error.message;
      } else if (typeof error === 'object' && error !== null) {
        const errObj = error as Record<string, string | number | boolean>;
        if (errObj.message && typeof errObj.message === 'string') {
          errMsg = errObj.message;
        } else if (errObj.code !== undefined) {
          errMsg = `错误代码: ${String(errObj.code)}`;
        } else {
          try {
            errMsg = JSON.stringify(error);
          } catch {
            errMsg = '未知错误';
          }
        }
      } else {
        errMsg = String(error);
      }
      
      this.addSyncLog('error', `同步异常: ${errMsg}`);
      this.syncProgress = 0;
      this.syncProgressMessage = '同步失败 - 请查看上方日志了解详情';
      logger.error(TAG, '同步图源仓库失败', errMsg);
      // 不关闭窗口，让用户能看到错误信息
      // isSyncingRepo 保持 true 以显示日志窗口
    }
  }

  /**
   * 打开图源详情页
   */
  private openSourceDetail(source: SourceInfo): void {
    try {
      logger.info(TAG, `打开图源详情页: ${source.name} (ID: ${source.id})`);
      const params: SourceDetailPageParams = { sourceId: source.id };
      this.pathStack.pushPathByName('SourceDetailPage', params);
    } catch (err) {
      logger.error(TAG, '打开图源详情页失败', String(err));
      this.showToast('打开图源详情页失败');
    }
  }

  /**
   * 打开图源详情页并指定初始标签
   */
  private openSourceDetailWithTab(source: SourceInfo, initialTab: string): void {
    try {
      logger.info(TAG, `打开图源详情页: ${source.name} (ID: ${source.id}), 初始标签: ${initialTab}`);
      const params: SourceDetailPageParams = { sourceId: source.id, initialTab: initialTab };
      this.pathStack.pushPathByName('SourceDetailPage', params);
    } catch (err) {
      logger.error(TAG, '打开图源详情页失败', String(err));
      this.showToast('打开图源详情页失败');
    }
  }

  /**
   * 打开图源详情页并显示搜索（弹出搜索对话框）
   */
  private openSourceDetailWithSearch(source: SourceInfo): void {
    logger.info(TAG, `显示图源搜索对话框: ${source.name} (ID: ${source.id})`);
    this.searchTargetSource = source;
    this.sourceSearchInput = '';
    this.showSourceSearchDialog = true;
  }

  /**
   * 打开图源设置页面
   */
  private openSourceSettings(source: SourceInfo): void {
    try {
      logger.info(TAG, `打开图源设置页: ${source.name} (ID: ${source.id})`);
      const params: SourceSettingsPageParams = { sourceName: source.name };
      this.pathStack.pushPathByName('SourceSettingsPage', params);
    } catch (err) {
      logger.error(TAG, '打开图源设置页失败', String(err));
      this.showToast('打开图源设置页失败');
    }
  }

  /**
   * 执行图源搜索（从对话框确认后调用）
   */
  private executeSourceSearch(): void {
    if (!this.searchTargetSource) {
      return;
    }
    const keyword = this.sourceSearchInput.trim();
    if (keyword.length === 0) {
      this.showToast('请输入搜索关键词');
      return;
    }
    try {
      logger.info(TAG, `执行图源搜索: ${this.searchTargetSource.name}, 关键词: ${keyword}`);
      const params: SourceDetailPageParams = {
        sourceId: this.searchTargetSource.id,
        initialTab: 'search',
        searchKeyword: keyword
      };
      this.pathStack.pushPathByName('SourceDetailPage', params);
      this.showSourceSearchDialog = false;
      this.searchTargetSource = null;
      this.sourceSearchInput = '';
    } catch (err) {
      logger.error(TAG, '打开图源详情页失败', String(err));
      this.showToast('打开图源详情页失败');
    }
  }

  /**
   * 删除图源
   */
  private async deleteSource(source: SourceInfo): Promise<void> {
    try {
      logger.info(TAG, `删除图源: ${source.name} (ID: ${source.id})`);
      
      // 显示确认对话框
      this.getUIContext().showAlertDialog({
        title: '删除图源',
        message: `确定要删除图源"${source.name}"吗？\n\n删除后将无法恢复，需要重新导入。`,
        autoCancel: true,
        alignment: DialogAlignment.Center,
        primaryButton: {
          value: '取消',
          action: () => {
            logger.info(TAG, '用户取消删除图源');
          }
        },
        secondaryButton: {
          value: '删除',
          fontColor: ThemeAwareHelper.getTestManagementThemedColor('button_danger', this.themeState.currentTheme),
          action: async () => {
            try {
              await this.sourceManager.deleteSource(source.id, source.pkg, source.name);
              this.showToast('图源已删除');
              logger.info(TAG, `图源删除成功: ${source.name}`);
              
              // 刷新图源列表
              await this.loadSources();
            } catch (error) {
              logger.error(TAG, '删除图源失败', String(error));
              this.showToast('删除图源失败');
            }
          }
        }
      });
    } catch (err) {
      logger.error(TAG, '删除图源失败', String(err));
      this.showToast('删除图源失败');
    }
  }

  /**
   * 删除已保存的仓库
   */
  private async deleteRepository(repository: SavedRepository): Promise<void> {
    try {
      logger.info(TAG, `删除仓库: ${repository.name} (ID: ${repository.id})`);
      
      const success = await this.repositoryManager.deleteRepository(repository.id);
      if (success) {
        this.showToast('仓库已删除');
        logger.info(TAG, `仓库删除成功: ${repository.name}`);
        
        // 刷新已保存仓库列表
        await this.loadSavedRepositories();
        
        // 如果删除的是当前选中的仓库，清除选中状态
        if (this.selectedRepositoryId === repository.id) {
          this.selectedRepositoryId = '';
          this.sourceRepoUrl = '';
        }
      } else {
        this.showToast('删除仓库失败');
        logger.error(TAG, `仓库删除失败: ${repository.name}`);
      }
    } catch (error) {
      logger.error(TAG, '删除仓库失败', String(error));
      this.showToast('删除仓库失败');
    }
  }

  /**
   * 处理图源列表下拉刷新
   */
  private async handleSourceRefresh(): Promise<void> {
    this.isRefreshingSourceList = true;
    try {
      await this.refreshSources();
    } finally {
      this.isRefreshingSourceList = false;
    }
  }

  // ==================== 图源相关方法结束 ====================

  /**
   * 加载书库视图模式设置
   */
  private async loadLibraryViewMode(): Promise<void> {
    try {
      const viewMode: string | null = await this.dataManager.getUserSetting('default_user', 'library_view_mode');
      if (viewMode === LibraryViewMode.GRID) {
        this.libraryViewMode = LibraryViewMode.GRID;
      } else {
        this.libraryViewMode = LibraryViewMode.LIST;
      }
      logger.info(TAG, `加载书库视图模式: ${this.libraryViewMode}`);
    } catch (error) {
      logger.warn(TAG, `加载书库视图模式失败，使用默认值: ${String(error)}`);
      this.libraryViewMode = LibraryViewMode.LIST;
    }
  }

  /**
   * 保存书库视图模式设置
   */
  private async saveLibraryViewMode(mode: LibraryViewMode): Promise<void> {
    try {
      await this.dataManager.saveUserSetting('default_user', 'library_view_mode', mode);
      logger.info(TAG, `保存书库视图模式: ${mode}`);
    } catch (error) {
      logger.error(TAG, `保存书库视图模式失败: ${String(error)}`);
    }
  }

  /**
   * 切换书库视图模式（在列表和网格之间切换）
   */
  private async toggleLibraryViewMode(): Promise<void> {
    const newMode: LibraryViewMode = this.libraryViewMode === LibraryViewMode.LIST 
      ? LibraryViewMode.GRID 
      : LibraryViewMode.LIST;
    this.libraryViewMode = newMode;
    this.saveLibraryViewMode(newMode).catch((error: Error) => {
      logger.error(TAG, `切换视图模式失败: ${error.message}`);
    });
    logger.info(TAG, `切换书库视图模式: ${newMode}`);
  }

  /**
   * 获取章节阅读进度文本
   */
  private getChapterProgressText(manga: Manga): string {
    if (!manga.readingProgress.currentChapterId) {
      return '';
    }

    const currentChapter = manga.chapters.find((ch: MangaChapter) => ch.id === manga.readingProgress.currentChapterId);
    if (currentChapter) {
      return `已读至 ${currentChapter.title}`;
    }

    return '继续阅读';
  }

  /**
   * 格式化阅读时间
   */
  private formatReadTime(timestamp: number): string {
    const date = new Date(timestamp);
    const year = date.getFullYear();
    const month = (date.getMonth() + 1).toString().padStart(2, '0');
    const day = date.getDate().toString().padStart(2, '0');
    const hours = date.getHours().toString().padStart(2, '0');
    const minutes = date.getMinutes().toString().padStart(2, '0');

    return `${year}-${month}-${day} ${hours}:${minutes}`;
  }

  /**
   * 加载最近阅读列表
   */
  private async loadRecentReadingList(): Promise<void> {
    if (this.isLoadingRecentReading) {
      return;
    }

    this.isLoadingRecentReading = true;
    try {
      logger.info(TAG, '开始加载首页最近内容（全部库项目）');

      // [修复] 同时加载本地和在线漫画
      const mangaList = await this.loadAllMangaFromDatabase();

      this.recentReadingList = mangaList;
      await this.updateRecentCoverAspectInfos(mangaList);
      logger.info(TAG, `首页最近内容：漫画加载完成，共 ${mangaList.length} 部`);

      // 加载所有电子书（用于最近区域展示）
      try {
        const ebooks: EBook[] = await this.ebookDataManager.getEBookList();
        this.recentEBookList = ebooks;
        logger.info(TAG, `首页最近内容：电子书加载完成，共 ${ebooks.length} 本`);
      } catch (ebookErr) {
        const eMsg: string = ebookErr instanceof Error ? ebookErr.message : String(ebookErr);
        logger.warn(TAG, `电子书列表加载失败: ${eMsg}`);
        this.recentEBookList = [];
      }
      
      // 加载最近阅读的小说
      try {
        if (!this.novelDataManager) {
          const context = this.getUIContext().getHostContext() as common.UIAbilityContext;
          this.novelDataManager = getNovelDataManager();
          await this.novelDataManager.initialize(context);
        }
        const novels = await this.novelDataManager.getRecentBooks(20);
        this.recentNovelList = novels;
        logger.info(TAG, `首页最近内容：小说加载完成，共 ${novels.length} 本`);
      } catch (novelErr) {
        const nMsg: string = novelErr instanceof Error ? novelErr.message : String(novelErr);
        logger.warn(TAG, `小说列表加载失败: ${nMsg}`);
        this.recentNovelList = [];
      }

    } catch (error) {
      logger.error(TAG, `加载最近阅读列表失败: ${String(error)}`);
      this.recentReadingList = [];
    } finally {
      this.isLoadingRecentReading = false;
    }
  }

  /**
   * 计算瀑布流条目宽度（百分比字符串）
   */
  private getWaterfallItemWidth(): string {
    return '48%';
  }

  /**
   * 计算瀑布流封面纵横比（为营造不规则高度效果）
   */
  private getWaterfallAspectRatio(index: number): number {
    const mod: number = index % 3;
    if (mod === 0) {
      return 0.65;
    } else if (mod === 1) {
      return 0.85;
    }
    return 1.05;
  }

  private clampAspect(aspect: number): number {
    if (aspect < 0.5) {
      return 0.5;
    }
    if (aspect > 2.0) {
      return 2.0;
    }
    return aspect;
  }

  private findCoverAspectInfo(id: string): CoverAspectInfo | null {
    for (let i: number = 0; i < this.recentCoverAspectInfos.length; i++) {
      const info: CoverAspectInfo = this.recentCoverAspectInfos[i] as CoverAspectInfo;
      if (info.id === id) {
        return info;
      }
    }
    return null;
  }

  private getAdaptiveCoverAspect(manga: Manga, idx: number): number {
    const info: CoverAspectInfo | null = this.findCoverAspectInfo(manga.id);
    if (info) {
      const a: number = this.clampAspect(info.aspect);
      if (info.orientation === CoverOrientation.PORTRAIT) {
        return a <= 0.9 ? a : 0.75;
      }
      if (info.orientation === CoverOrientation.LANDSCAPE) {
        return a >= 1.1 ? a : 1.5;
      }
      return 1.0;
    }
    return this.getWaterfallAspectRatio(idx);
  }

  private async getImageAspectRatioForCover(path: string, sourceType: ImageSourceType): Promise<number | null> {
    if (!path || path.length === 0) {
      return null;
    }
    
    if (sourceType === ImageSourceType.LOCAL) {
      let file: fs.File | null = null;
      try {
        const hasScheme: boolean = path.indexOf('file://') === 0;
        const actualPath: string = hasScheme ? path.substring(7) : path;
        file = fs.openSync(actualPath, fs.OpenMode.READ_ONLY);
        const src: image.ImageSource = image.createImageSource(file.fd);
        if (!src) {
          return null;
        }
        const info: image.ImageInfo = await src.getImageInfo();
        const w: number = info.size.width;
        const h: number = info.size.height;
        if (w > 0 && h > 0) {
          return w / h;
        }
      } catch (err) {
        // 静默处理，不输出警告日志
      } finally {
        if (file) {
          try {
            fs.closeSync(file);
          } catch (cerr) {
            // 静默处理
          }
        }
      }
      return null;
    }
    if (sourceType === ImageSourceType.RAWFILE || sourceType === ImageSourceType.NETWORK) {
      try {
        const src: image.ImageSource = image.createImageSource(path);
        if (!src) {
          return null;
        }
        const info: image.ImageInfo = await src.getImageInfo();
        const w: number = info.size.width;
        const h: number = info.size.height;
        if (w > 0 && h > 0) {
          return w / h;
        }
      } catch (err2) {
        // 静默处理，不输出警告日志
      }
    }
    return null;
  }

  private async updateRecentCoverAspectInfos(list: Manga[]): Promise<void> {
    const results: CoverAspectInfo[] = [];
    for (let i: number = 0; i < list.length; i++) {
      const mg: Manga = list[i] as Manga;
      const p: string = mg.coverImagePath;
      const st: ImageSourceType = mg.coverSourceType as ImageSourceType;
      let asp: number = 0.75;
      let ori: CoverOrientation = CoverOrientation.PORTRAIT;
      if (p && p.length > 0 && st !== undefined) {
        try {
          const a: number | null = await this.getImageAspectRatioForCover(p, st);
          if (a !== null) {
            asp = a;
            if (a > 1.05) {
              ori = CoverOrientation.LANDSCAPE;
            } else if (a < 0.95) {
              ori = CoverOrientation.PORTRAIT;
            } else {
              ori = CoverOrientation.SQUARE;
            }
          }
        } catch (e) {
          const em: string = e instanceof Error ? e.message : String(e);
          logger.warn(TAG, em);
        }
      }
      const info: CoverAspectInfo = { id: mg.id, aspect: asp, orientation: ori } as CoverAspectInfo;
      results.push(info);
    }
    this.recentCoverAspectInfos = results;
  }

  /**
   * 构建最近阅读统一瀑布流（漫画和电子书混合显示）
   */
  @Builder
  buildRecentReadingWaterfall() {
    Grid() {
      // 先显示漫画
      ForEach(this.recentReadingList, (manga: Manga) => {
        GridItem() {
          Column({ space: 8 }) {
            Stack() {
              Image(this.normalizeDisplayPathForManga(manga) || $r('app.media.mangabook'))
                .width('100%')
                .aspectRatio(0.7)
                .objectFit(ImageFit.Cover)
                .borderRadius(8)
                .backgroundColor(ThemeAwareHelper.getTestManagementThemedColor('background_secondary', this.themeState.currentTheme))
                .onError(() => {
                  logger.warn('MainMenuPage', `封面加载失败: ${manga.id}`);
                })
                .id(`cover_manga_home_${manga.id}`)
            }
            .shadow({ radius: 8, color: '#1F000000', offsetY: 4 })
            .borderRadius(8)
            .onClick(() => {
              // 点击封面直接开始阅读（带翻开动画）
              this.openMangaReaderWithAnimation(manga, `cover_manga_home_${manga.id}`);
            })

            Text(manga.title)
              .fontSize(14)
              .fontWeight(FontWeight.Medium)
              .fontFamily(this.appFontFamily)
              .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_primary', this.themeState.currentTheme))
              .maxLines(2)
              .textOverflow({ overflow: TextOverflow.Ellipsis })
              .width('100%')
              .onClick(() => { this.openMangaDetail(manga); })
          }
          .width('100%')
        }
      }, (manga: Manga) => `manga_${manga.id}`)

      // 再显示电子书
      ForEach(this.recentEBookList, (ebook: EBook) => {
        GridItem() {
          Column({ space: 8 }) {
            Stack() {
              Image(this.normalizeDisplayPathForEBook(ebook) || $r('app.media.mangabook'))
                .width('100%')
                .aspectRatio(0.7)
                .objectFit(ImageFit.Cover)
                .borderRadius(8)
                .backgroundColor(ThemeAwareHelper.getTestManagementThemedColor('background_secondary', this.themeState.currentTheme))
                .onError(() => {
                  logger.warn('MainMenuPage', `电子书封面加载失败: ${ebook.id}`);
                })
                .id(`cover_ebook_home_${ebook.id}`)
            }
            .shadow({ radius: 8, color: '#1F000000', offsetY: 4 })
            .borderRadius(8)
            .onClick(() => {
              // 点击封面直接开始阅读（带翻开动画）
              this.openEBookReaderFromHome(ebook);
            })

            Text(ebook.metadata.title)
              .fontSize(14)
              .fontWeight(FontWeight.Medium)
              .fontFamily(this.appFontFamily)
              .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_primary', this.themeState.currentTheme))
              .maxLines(2)
              .textOverflow({ overflow: TextOverflow.Ellipsis })
              .width('100%')
              .onClick(() => { this.openEBookDetail(ebook); })
          }
          .width('100%')
        }
      }, (ebook: EBook) => `ebook_${ebook.id}`)
      
      // 显示小说
      ForEach(this.recentNovelList, (novel: NovelBook) => {
        GridItem() {
          Column({ space: 8 }) {
            Stack() {
              Image(novel.coverLocalPath || novel.coverUrl || $r('app.media.mangabook'))
                .width('100%')
                .aspectRatio(0.7)
                .objectFit(ImageFit.Cover)
                .borderRadius(8)
                .backgroundColor(ThemeAwareHelper.getTestManagementThemedColor('background_secondary', this.themeState.currentTheme))
                .onError(() => {
                  logger.warn('MainMenuPage', `小说封面加载失败: ${novel.id}`);
                })
                .id(`cover_novel_home_${novel.id}`)
              
              // 小说标识
              Text('小说')
                .fontSize(10)
                .fontFamily(this.appFontFamily)
                .fontColor('#FFFFFF')
                .backgroundColor('#4CAF50')
                .padding({ left: 4, right: 4, top: 2, bottom: 2 })
                .borderRadius(4)
                .position({ x: 4, y: 4 })
            }
            .shadow({ radius: 8, color: '#1F000000', offsetY: 4 })
            .borderRadius(8)
            .onClick(() => {
              // 点击封面打开小说详情页
              this.openNovelDetail(novel);
            })

            Text(novel.name)
              .fontSize(14)
              .fontWeight(FontWeight.Medium)
              .fontFamily(this.appFontFamily)
              .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_primary', this.themeState.currentTheme))
              .maxLines(2)
              .textOverflow({ overflow: TextOverflow.Ellipsis })
              .width('100%')
              .onClick(() => { this.openNovelDetail(novel); })
          }
          .width('100%')
        }
      }, (novel: NovelBook) => `novel_${novel.id}`)
    }
    .columnsTemplate(this.getHomeGridColumnsTemplate())
    .columnsGap(this.responsive_gridGap)
    .rowsGap(this.responsive_gridGap)
    .width('100%')
  }

  /**
   * @deprecated 已合并到 buildRecentReadingWaterfall
   */
  @Builder
  buildRecentEBookWaterfall() {
    // 已合并到 buildRecentReadingWaterfall，此方法保留为空以兼容
  }

  /**
   * 加载电子书列表
   * 包括普通电子书和PDF电子书（contentType='ebook'的漫画）
   */
  private async loadEBookList(): Promise<void> {
    try {
      this.isLoadingEbookList = true;
      logger.info(TAG, '开始加载电子书列表...');

      // 根据隐私模式选择查询方法
      let ebookList: EBook[] = [];
      if (this.isPrivacyMode) {
        ebookList = await this.ebookDataManager.getPrivateEBooks();
        logger.info(TAG, `隐私模式：从数据库获取到 ${ebookList.length} 本隐私电子书`);
      } else {
        ebookList = await this.ebookDataManager.getNonPrivateEBooks();
        logger.info(TAG, `普通模式：从数据库获取到 ${ebookList.length} 本非隐私电子书`);
      }

      // 2. 加载PDF电子书（contentType='ebook'的漫画）
      const pdfEbooks = this.mangaList.filter((manga: Manga) => manga.contentType === 'ebook');
      logger.info(TAG, `从漫画列表获取到 ${pdfEbooks.length} 本PDF电子书`);

      this.ebookList = ebookList;
      this.pdfEbookList = pdfEbooks;
      this.applyEBookFilter(); // 应用筛选

    } catch (error) {
      logger.error(TAG, `加载电子书列表失败: ${String(error instanceof Error ? error.message : error)}`);
      this.ebookList = [];
      this.pdfEbookList = [];
      this.filteredEbookList = [];
      this.filteredPdfEbookList = [];
    } finally {
      this.isLoadingEbookList = false;
    }
  }

  /**
   * 应用电子书筛选
   * 同时筛选普通电子书和PDF电子书
   */
  private applyEBookFilter(): void {
    // 隐私筛选已在loadEBookList中通过数据库查询完成，这里直接使用
    let privacyFilteredEbook = this.ebookList;
    let privacyFilteredPdf = this.pdfEbookList;
    
    logger.debug(TAG, `电子书列表: 普通电子书${privacyFilteredEbook.length}, PDF${privacyFilteredPdf.length}`);

    let filtered: EBook[] = [];
    let filteredPdf: Manga[] = [];
    
    switch (this.libraryFilterType) {
      case LibraryFilterType.ALL:
        filtered = privacyFilteredEbook;
        filteredPdf = privacyFilteredPdf;
        break;
      case LibraryFilterType.UNREAD:
        // 未读：状态为未读，且没有阅读进度
        filtered = privacyFilteredEbook.filter((ebook: EBook) => {
          // 检查状态或阅读进度，两者都表明未读才算未读
          const hasNoProgress = ebook.readingProgress.progress === 0 && 
                                ebook.readingProgress.currentPosition === 0;
          return ebook.status === EBookStatus.UNREAD && hasNoProgress;
        });
        filteredPdf = privacyFilteredPdf.filter((manga: Manga) => {
          return manga.readingProgress.currentPageIndex === 0 && 
                 manga.readingProgress.currentChapterId === '' &&
                 manga.readingProgress.readingStatus !== ReadingStatus.READING;
        });
        break;
      case LibraryFilterType.READING:
        // 阅读中：状态为阅读中，或有实际阅读进度但未完成
        filtered = privacyFilteredEbook.filter((ebook: EBook) => {
          // 状态为阅读中，或者有实际阅读进度（不包括lastReadTime，因为它可能在添加时就被设置）
          const hasActualProgress = ebook.readingProgress.progress > 0 || 
                                    ebook.readingProgress.currentPosition > 0;
          const isNotCompleted = ebook.status !== EBookStatus.COMPLETED && 
                                 ebook.readingProgress.progress < 100;
          const isReading = ebook.status === EBookStatus.READING;
          const result = isReading || (hasActualProgress && isNotCompleted);
          logger.debug(TAG, `[READING筛选] "${ebook.metadata.title}": isReading=${isReading}, hasActualProgress=${hasActualProgress}, isNotCompleted=${isNotCompleted}, 结果=${result}`);
          return result;
        });
        filteredPdf = privacyFilteredPdf.filter((manga: Manga) => {
          // 有阅读进度且未完成
          const hasProgress = manga.readingProgress.currentPageIndex > 0 || 
                              manga.readingProgress.currentChapterId !== '' ||
                              manga.readingProgress.readingStatus === ReadingStatus.READING;
          return hasProgress && manga.readingProgress.readingStatus !== ReadingStatus.COMPLETED;
        });
        break;
      case LibraryFilterType.COMPLETED:
        filtered = privacyFilteredEbook.filter((ebook: EBook) => {
          return ebook.status === EBookStatus.COMPLETED;
        });
        filteredPdf = privacyFilteredPdf.filter((manga: Manga) => {
          return manga.status === MangaStatus.COMPLETED;
        });
        break;
      case LibraryFilterType.FAVORITE:
        filtered = privacyFilteredEbook.filter((ebook: EBook) => {
          return ebook.isFavorite;
        });
        filteredPdf = privacyFilteredPdf.filter((manga: Manga) => {
          return manga.isFavorite;
        });
        break;
      default:
        filtered = privacyFilteredEbook;
        filteredPdf = privacyFilteredPdf;
    }
    
    // 应用NSFW过滤
    const nsfwFilteredEbook = this.contentFilterManager.filterContentList(filtered);
    const nsfwFilteredPdf = this.contentFilterManager.filterContentList(filteredPdf);
    
    this.filteredEbookList = nsfwFilteredEbook;
    this.filteredPdfEbookList = nsfwFilteredPdf;
    
    // 详细日志：输出每本电子书的状态和进度信息（用于调试）
    if (this.libraryFilterType === LibraryFilterType.READING || this.libraryFilterType === LibraryFilterType.UNREAD) {
      for (const ebook of this.ebookList) {
        logger.debug(TAG, `电子书 "${ebook.metadata.title}": status=${ebook.status}, progress=${ebook.readingProgress.progress}%, position=${ebook.readingProgress.currentPosition}, lastRead=${ebook.readingProgress.lastReadTime}`);
      }
    }
    logger.info(TAG, `电子书筛选完成: 普通电子书=${nsfwFilteredEbook.length}/${this.ebookList.length}, PDF电子书=${nsfwFilteredPdf.length}/${this.pdfEbookList.length}, 筛选类型=${this.libraryFilterType}, SFW模式: ${this.contentFilterManager.isSFWModeEnabled()}`);
    
    // 记录NSFW过滤统计
    if (this.contentFilterManager.isSFWModeEnabled()) {
      const ebookStats = this.contentFilterManager.getFilterStats(filtered);
      const pdfStats = this.contentFilterManager.getFilterStats(filteredPdf);
      logger.info(TAG, `电子书NSFW过滤: 普通=${ebookStats.filtered}本, PDF=${pdfStats.filtered}本`);
    }
  }

  /**
   * 加载小说列表
   */
  private async loadNovelList(): Promise<void> {
    try {
      this.isLoadingNovelList = true;
      logger.info(TAG, '开始加载小说列表...');

      // 初始化小说数据管理器
      if (!this.novelDataManager) {
        const context = this.getUIContext().getHostContext() as common.UIAbilityContext;
        this.novelDataManager = getNovelDataManager();
        await this.novelDataManager.initialize(context);
      }

      // 根据隐私模式选择查询方法
      let novels: NovelBook[] = [];
      if (this.isPrivacyMode) {
        novels = await this.novelDataManager.getPrivateBooks();
        logger.info(TAG, `隐私模式：从数据库获取到 ${novels.length} 本隐私小说`);
      } else {
        novels = await this.novelDataManager.getNonPrivateBooks();
        logger.info(TAG, `普通模式：从数据库获取到 ${novels.length} 本非隐私小说`);
      }

      this.novelList = novels;
      this.applyNovelFilter(); // 应用筛选

    } catch (error) {
      logger.error(TAG, `加载小说列表失败: ${String(error instanceof Error ? error.message : error)}`);
      this.novelList = [];
      this.filteredNovelList = [];
    } finally {
      this.isLoadingNovelList = false;
    }
  }

  /**
   * 应用小说筛选
   */
  private applyNovelFilter(): void {
    // 隐私筛选已在loadNovelList中通过数据库查询完成，这里直接使用
    let privacyFiltered = this.novelList;
    logger.debug(TAG, `小说列表: ${privacyFiltered.length} 本`);

    let filtered: NovelBook[] = [];
    
    switch (this.libraryFilterType) {
      case LibraryFilterType.ALL:
        filtered = privacyFiltered;
        break;
      case LibraryFilterType.UNREAD:
        filtered = privacyFiltered.filter((novel: NovelBook) => {
          return novel.readStatus === NovelReadStatus.UNREAD;
        });
        break;
      case LibraryFilterType.READING:
        filtered = privacyFiltered.filter((novel: NovelBook) => {
          return novel.readStatus === NovelReadStatus.READING;
        });
        break;
      case LibraryFilterType.COMPLETED:
        filtered = privacyFiltered.filter((novel: NovelBook) => {
          return novel.readStatus === NovelReadStatus.FINISHED;
        });
        break;
      case LibraryFilterType.FAVORITE:
        // 小说列表本身就是收藏的，所以全部显示
        filtered = privacyFiltered;
        break;
      default:
        filtered = privacyFiltered;
    }
    
    // 应用NSFW过滤
    const nsfwFilteredNovel = this.contentFilterManager.filterContentList(filtered);
    
    this.filteredNovelList = nsfwFilteredNovel;
    logger.info(TAG, `小说筛选完成: ${nsfwFilteredNovel.length}/${this.novelList.length}, 筛选类型=${this.libraryFilterType}, SFW模式: ${this.contentFilterManager.isSFWModeEnabled()}`);
    
    // 记录NSFW过滤统计
    if (this.contentFilterManager.isSFWModeEnabled()) {
      const stats = this.contentFilterManager.getFilterStats(filtered);
      logger.info(TAG, `小说NSFW过滤: 已过滤=${stats.filtered}本`);
    }
  }

  /**
   * 切换书库内容类型
   */
  private toggleLibraryContentType(type: LibraryContentType): void {
    if (this.libraryContentType !== type) {
      this.libraryContentType = type;
      logger.info(TAG, `切换书库内容类型: ${type}`);
      
      // 重置筛选条件为"全部"
      this.libraryFilterType = LibraryFilterType.ALL;

      // 根据类型刷新列表
      if (type === LibraryContentType.EBOOK) {
        logger.info(TAG, '切换到电子书，刷新列表');
        this.loadEBookList();
      } else if (type === LibraryContentType.NOVEL) {
        logger.info(TAG, '切换到小说，刷新列表');
        this.loadNovelList();
      } else {
        // 漫画：只应用筛选
        this.applyLibraryFilter();
      }
    }
  }

  /**
   * 应用书库筛选
   * 注意：漫画标签只显示contentType为'manga'或未定义的内容
   * contentType为'ebook'的PDF会显示在电子书标签下
   */
  private async applyLibraryFilter(): Promise<void> {
    // 首先过滤掉电子书类PDF（contentType === 'ebook'）
    const mangaOnly = this.mangaList.filter((manga: Manga) => {
      return manga.contentType !== 'ebook';
    });

    // 隐私筛选已在loadAllMangaFromDatabase中通过数据库查询完成，这里直接使用
    let privacyFiltered = mangaOnly;
    logger.debug(TAG, `漫画列表: ${mangaOnly.length}个（已排除电子书类PDF）`);

    let filtered: Manga[] = [];

    switch (this.libraryFilterType) {
      case LibraryFilterType.ALL:
        filtered = privacyFiltered;
        break;
      case LibraryFilterType.UNREAD:
        filtered = privacyFiltered.filter((manga: Manga) => {
          return manga.readingProgress.currentPageIndex === 0 &&
            manga.readingProgress.currentChapterId === '';
        });
        break;
      case LibraryFilterType.READING:
        filtered = privacyFiltered.filter((manga: Manga) => {
          return manga.readingProgress.currentChapterId !== '' &&
            manga.readingProgress.readingStatus !== ReadingStatus.COMPLETED;
        });
        break;
      case LibraryFilterType.COMPLETED:
        filtered = privacyFiltered.filter((manga: Manga) => {
          return manga.status === MangaStatus.COMPLETED;
        });
        break;
      case LibraryFilterType.FAVORITE:
        filtered = privacyFiltered.filter((manga: Manga) => {
          return manga.isFavorite;
        });
        break;
      default:
        filtered = privacyFiltered;
        break;
    }

    // 应用NSFW过滤
    const nsfwFiltered = this.contentFilterManager.filterContentList(filtered);
    
    this.filteredMangaList = nsfwFiltered;
    logger.info(TAG, `应用筛选: ${this.libraryFilterType}, 结果数量: ${nsfwFiltered.length}/${filtered.length} (排除电子书类PDF, SFW模式: ${this.contentFilterManager.isSFWModeEnabled()})`);
    
    // 记录过滤统计
    if (this.contentFilterManager.isSFWModeEnabled()) {
      const stats = this.contentFilterManager.getFilterStats(filtered);
      logger.info(TAG, `NSFW过滤统计: 总数=${stats.total}, NSFW=${stats.nsfw}, SFW=${stats.sfw}, 已过滤=${stats.filtered}`);
    }

  }

  /**
   * 初始化内容数据（漫画、电子书、标签和作者）
   * 确保按正确顺序加载数据
   */
  private async initializeContentData(): Promise<void> {
    try {
      logger.info(TAG, '开始初始化内容数据...');

      // 先加载漫画、电子书和小说列表
      await this.loadMangaList();
      await this.loadEBookList();
      await this.loadNovelList();

      // 数据加载完成后提取标签和作者
      await this.extractTagsAndAuthors();

      logger.info(TAG, '内容数据初始化完成');
    } catch (error) {
      logger.error(TAG, `初始化内容数据失败: ${String(error)}`);
    }
  }

  /**
   * 从漫画数据中提取标签和作者信息
   */
  private async extractTagsAndAuthors(): Promise<void> {
    try {
      logger.info(TAG, '开始提取标签和作者信息...');

      // 统计标签和作者出现次数
      const tagCountMap: Map<string, number> = new Map();
      const authorCountMap: Map<string, number> = new Map();

      // 从漫画中提取标签和作者
      for (const manga of this.mangaList) {
        // 提取标签（genres和themes）
        const allTags: string[] = [
          ...manga.metadata.genres,
          ...manga.metadata.themes
        ];

        for (const tag of allTags) {
          if (tag && tag.trim() !== '') {
            const count = tagCountMap.get(tag) || 0;
            tagCountMap.set(tag, count + 1);
          }
        }

        // 提取作者
        for (const author of manga.metadata.authors) {
          if (author && author.trim() !== '') {
            const count = authorCountMap.get(author) || 0;
            authorCountMap.set(author, count + 1);
          }
        }
      }

      // 从电子书中提取标签和作者
      for (const ebook of this.ebookList) {
        // 提取标签（tags）
        const ebookTags: string[] = ebook.metadata.tags || [];

        for (const tag of ebookTags) {
          if (tag && tag.trim() !== '') {
            const count = tagCountMap.get(tag) || 0;
            tagCountMap.set(tag, count + 1);
          }
        }

        // 提取作者
        if (ebook.metadata.author && ebook.metadata.author.trim() !== '') {
          const count = authorCountMap.get(ebook.metadata.author) || 0;
          authorCountMap.set(ebook.metadata.author, count + 1);
        }
      }

      // 从小说中提取标签和作者
      for (const novel of this.novelList) {
        // 提取标签（kind字段，可能是逗号分隔的字符串）
        if (novel.kind) {
          const novelTags = novel.kind.split(/[,，、]/).map(t => t.trim()).filter(t => t !== '');
          for (const tag of novelTags) {
            const count = tagCountMap.get(tag) || 0;
            tagCountMap.set(tag, count + 1);
          }
        }

        // 提取作者
        if (novel.author && novel.author.trim() !== '') {
          const count = authorCountMap.get(novel.author) || 0;
          authorCountMap.set(novel.author, count + 1);
        }
      }

      // 转换为数组并按出现次数倒序排列
      const tagEntries = Array.from(tagCountMap.entries());
      tagEntries.sort((a, b) => b[1] - a[1]);
      this.allTags = tagEntries.map(entry => entry[0]);

      const authorEntries = Array.from(authorCountMap.entries());
      authorEntries.sort((a, b) => b[1] - a[1]);
      this.allAuthors = authorEntries.map(entry => entry[0]);

      // 初始化发现页面的漫画、电子书和小说列表
      this.discoveredMangaList = [...this.mangaList];
      this.discoveredEBookList = [...this.ebookList];
      this.discoveredNovelList = [...this.novelList];

      logger.info(TAG, `提取完成: ${this.allTags.length}个标签, ${this.allAuthors.length}个作者, ${this.mangaList.length}本漫画, ${this.ebookList.length}本电子书, ${this.novelList.length}本小说`);
    } catch (error) {
      logger.error(TAG, `提取标签和作者信息失败: ${String(error)}`);
      this.allTags = [];
      this.allAuthors = [];
      this.discoveredMangaList = [];
      this.discoveredEBookList = [];
      this.discoveredNovelList = [];
    }
  }

  /**
   * 应用发现页面筛选（支持多选标签和作者）
   */
  private applyDiscoverFilter(): void {
    try {
      // 筛选漫画
      let filteredManga = [...this.mangaList];

      // 多标签筛选：漫画需要包含所有选中的标签
      if (this.selectedTags.size > 0) {
        filteredManga = filteredManga.filter((manga: Manga) => {
          const allTags = [...manga.metadata.genres, ...manga.metadata.themes];
          for (const tag of this.selectedTags) {
            if (!allTags.includes(tag)) {
              return false;
            }
          }
          return true;
        });
      }

      // 多作者筛选：漫画作者在选中列表中即可
      if (this.selectedAuthors.size > 0) {
        filteredManga = filteredManga.filter((manga: Manga) => {
          for (const author of manga.metadata.authors) {
            if (this.selectedAuthors.has(author)) {
              return true;
            }
          }
          return false;
        });
      }

      // 筛选电子书
      let filteredEBook: EBook[] = [];
      for (const ebook of this.ebookList) {
        filteredEBook.push(ebook);
      }

      // 多标签筛选电子书
      if (this.selectedTags.size > 0) {
        filteredEBook = filteredEBook.filter((ebook: EBook) => {
          const allTags: string[] = ebook.metadata.tags || [];
          for (const tag of this.selectedTags) {
            if (!allTags.includes(tag)) {
              return false;
            }
          }
          return true;
        });
      }

      // 多作者筛选电子书
      if (this.selectedAuthors.size > 0) {
        filteredEBook = filteredEBook.filter((ebook: EBook) => {
          return this.selectedAuthors.has(ebook.metadata.author);
        });
      }

      // 筛选小说
      let filteredNovel = [...this.novelList];
      
      // 多标签筛选小说（使用kind字段）
      if (this.selectedTags.size > 0) {
        filteredNovel = filteredNovel.filter((novel: NovelBook) => {
          if (!novel.kind) return false;
          const novelTags = novel.kind.split(/[,，、]/).map(t => t.trim()).filter(t => t !== '');
          for (const tag of this.selectedTags) {
            if (!novelTags.includes(tag)) {
              return false;
            }
          }
          return true;
        });
      }
      
      // 多作者筛选小说
      if (this.selectedAuthors.size > 0) {
        filteredNovel = filteredNovel.filter((novel: NovelBook) => {
          return this.selectedAuthors.has(novel.author);
        });
      }

      // 应用NSFW过滤
      const nsfwFilteredManga = this.contentFilterManager.filterContentList(filteredManga);
      const nsfwFilteredEBook = this.contentFilterManager.filterContentList(filteredEBook);
      const nsfwFilteredNovel = this.contentFilterManager.filterContentList(filteredNovel);
      
      // 保存每种内容类型的筛选数量（用于双向筛选UI）
      this.filteredMangaCount = nsfwFilteredManga.length;
      this.filteredEBookCount = nsfwFilteredEBook.length;
      this.filteredNovelCount = nsfwFilteredNovel.length;
      
      // 根据内容类型筛选
      if (this.discoverContentType === 'manga') {
        this.discoveredMangaList = nsfwFilteredManga;
        this.discoveredEBookList = [];
        this.discoveredNovelList = [];
      } else if (this.discoverContentType === 'ebook') {
        this.discoveredMangaList = [];
        this.discoveredEBookList = nsfwFilteredEBook;
        this.discoveredNovelList = [];
      } else if (this.discoverContentType === 'novel') {
        this.discoveredMangaList = [];
        this.discoveredEBookList = [];
        this.discoveredNovelList = nsfwFilteredNovel;
      } else {
        this.discoveredMangaList = nsfwFilteredManga;
        this.discoveredEBookList = nsfwFilteredEBook;
        this.discoveredNovelList = nsfwFilteredNovel;
      }

      const selectedTagsStr = Array.from(this.selectedTags).join(',');
      const selectedAuthorsStr = Array.from(this.selectedAuthors).join(',');
      logger.info(TAG, `发现页面筛选: 标签=[${selectedTagsStr}], 作者=[${selectedAuthorsStr}], 类型=${this.discoverContentType}, 漫画=${this.discoveredMangaList.length}本, 电子书=${this.discoveredEBookList.length}本, 小说=${this.discoveredNovelList.length}本`);

    } catch (error) {
      logger.error(TAG, `应用发现页面筛选失败: ${String(error)}`);
      this.discoveredMangaList = [...this.mangaList];
      this.discoveredEBookList = [...this.ebookList];
      this.discoveredNovelList = [...this.novelList];
    }
  }

  /**
   * 切换标签选中状态
   */
  private toggleTagSelection(tag: string): void {
    if (this.selectedTags.has(tag)) {
      this.selectedTags.delete(tag);
    } else {
      this.selectedTags.add(tag);
    }
    this.selectedTags = new Set(this.selectedTags); // 触发UI更新
    this.applyDiscoverFilter();
  }

  /**
   * 切换作者选中状态
   */
  private toggleAuthorSelection(author: string): void {
    if (this.selectedAuthors.has(author)) {
      this.selectedAuthors.delete(author);
    } else {
      this.selectedAuthors.add(author);
    }
    this.selectedAuthors = new Set(this.selectedAuthors); // 触发UI更新
    this.applyDiscoverFilter();
  }

  /**
   * 清除所有标签选择
   */
  private clearTagSelection(): void {
    this.selectedTags.clear();
    this.selectedTags = new Set(this.selectedTags);
    this.applyDiscoverFilter();
  }

  /**
   * 清除所有作者选择
   */
  private clearAuthorSelection(): void {
    this.selectedAuthors.clear();
    this.selectedAuthors = new Set(this.selectedAuthors);
    this.applyDiscoverFilter();
  }

  /**
   * 刷新发现页面数据
   */
  private async refreshDiscoverData(): Promise<void> {
    try {
      logger.info(TAG, '开始刷新发现页面数据');

      // 重新加载漫画和电子书列表
      await this.loadMangaList();
      await this.loadEBookList();

      // 重新提取标签和作者
      await this.extractTagsAndAuthors();

      // 重新应用筛选
      this.applyDiscoverFilter();

      logger.info(TAG, '发现页面数据刷新完成');
      this.showToast('刷新完成');
    } catch (error) {
      logger.error(TAG, `刷新发现页面数据失败: ${String(error)}`);
      this.showToast('刷新失败');
    } finally {
      // 确保刷新状态被重置
      this.isRefreshingDiscover = false;
    }
  }

  /**
   * 静默刷新最近阅读列表（增量更新，避免闪屏）
   * 只更新有变化的数据，保持现有图片不重新加载
   */
  private async silentRefreshRecentReadingList(): Promise<void> {
    try {
      logger.debug(TAG, '静默刷新最近阅读列表（增量更新）');

      // 加载新的漫画列表
      const newMangaList = await this.loadAllMangaFromDatabase();

      // 增量更新漫画列表：只更新有变化的项目
      this.incrementalUpdateMangaList(this.recentReadingList, newMangaList);

      // 加载新的电子书列表
      try {
        const newEbooks: EBook[] = await this.ebookDataManager.getEBookList();
        // 增量更新电子书列表
        this.incrementalUpdateEBookList(this.recentEBookList, newEbooks);
      } catch (ebookErr) {
        logger.warn(TAG, `静默刷新电子书列表失败: ${ebookErr instanceof Error ? ebookErr.message : String(ebookErr)}`);
      }
      
      // 加载新的小说列表
      try {
        if (this.novelDataManager) {
          const newNovels = await this.novelDataManager.getRecentBooks(20);
          this.recentNovelList = newNovels;
        }
      } catch (novelErr) {
        logger.warn(TAG, `静默刷新小说列表失败: ${novelErr instanceof Error ? novelErr.message : String(novelErr)}`);
      }

      logger.debug(TAG, `静默刷新完成：漫画 ${this.recentReadingList.length} 部，电子书 ${this.recentEBookList.length} 本，小说 ${this.recentNovelList.length} 本`);

    } catch (error) {
      logger.warn(TAG, `静默刷新最近阅读列表失败: ${String(error)}`);
    }
  }

  /**
   * 增量更新漫画列表（避免闪屏）
   * 只添加新项目、删除已移除项目、更新已变化项目的属性
   */
  private incrementalUpdateMangaList(currentList: Manga[], newList: Manga[]): void {
    const currentIds = new Set(currentList.map(m => m.id));
    const newIds = new Set(newList.map(m => m.id));

    // 找出需要删除的项目（在当前列表中但不在新列表中）
    const toRemove: string[] = [];
    for (const id of currentIds) {
      if (!newIds.has(id)) {
        toRemove.push(id);
      }
    }

    // 删除已移除的项目
    for (const id of toRemove) {
      const index = currentList.findIndex(m => m.id === id);
      if (index !== -1) {
        currentList.splice(index, 1);
      }
    }

    // 更新现有项目的属性（不替换整个对象，保持图片引用）
    for (const newManga of newList) {
      const existingIndex = currentList.findIndex(m => m.id === newManga.id);
      if (existingIndex !== -1) {
        // 只更新阅读进度等属性，不替换整个对象
        const existing = currentList[existingIndex];
        existing.readingProgress = newManga.readingProgress;
        existing.status = newManga.status;
        existing.isFavorite = newManga.isFavorite;
        existing.chapters = newManga.chapters;
        // 只有封面路径变化时才更新（避免图片闪烁）
        if (existing.coverImagePath !== newManga.coverImagePath) {
          existing.coverImagePath = newManga.coverImagePath;
          existing.coverSourceType = newManga.coverSourceType;
        }
      } else {
        // 添加新项目
        currentList.push(newManga);
      }
    }
  }

  /**
   * 增量更新电子书列表（避免闪屏）
   */
  private incrementalUpdateEBookList(currentList: EBook[], newList: EBook[]): void {
    const currentIds = new Set(currentList.map(e => e.id));
    const newIds = new Set(newList.map(e => e.id));

    // 找出需要删除的项目
    const toRemove: string[] = [];
    for (const id of currentIds) {
      if (!newIds.has(id)) {
        toRemove.push(id);
      }
    }

    // 删除已移除的项目
    for (const id of toRemove) {
      const index = currentList.findIndex(e => e.id === id);
      if (index !== -1) {
        currentList.splice(index, 1);
      }
    }

    // 更新现有项目或添加新项目
    for (const newEbook of newList) {
      const existingIndex = currentList.findIndex(e => e.id === newEbook.id);
      if (existingIndex !== -1) {
        // 只更新阅读进度等属性
        const existing = currentList[existingIndex];
        existing.readingProgress = newEbook.readingProgress;
        existing.status = newEbook.status;
        existing.isFavorite = newEbook.isFavorite;
        existing.chapters = newEbook.chapters;
        // 只有封面路径变化时才更新
        if (existing.metadata.coverImagePath !== newEbook.metadata.coverImagePath) {
          existing.metadata.coverImagePath = newEbook.metadata.coverImagePath;
        }
      } else {
        // 添加新项目
        currentList.push(newEbook);
      }
    }
  }

  /**
   * 静默刷新书库（增量更新，避免闪屏）
   */
  private async silentRefreshLibrary(): Promise<void> {
    try {
      logger.debug(TAG, '静默刷新书库（增量更新）');

      // 加载新的漫画列表
      const newMangaList = await this.loadAllMangaFromDatabase();

      // 为每个漫画加载章节信息
      for (const manga of newMangaList) {
        try {
          const isOnlineManga = manga.sourceInfo?.sourceId && Number(manga.sourceInfo.sourceId) > 0;
          if (isOnlineManga) {
            const onlineChapters = await this.dataManager.getOnlineComicChapters(manga.id);
            if (onlineChapters && onlineChapters.length > 0) {
              manga.chapters = onlineChapters.map(chapterInfo => ({
                id: chapterInfo.id,
                title: chapterInfo.title,
                chapterNumber: chapterInfo.chapterNumber,
                pages: [],
                publishDate: chapterInfo.publishTime || Date.now(),
                language: 'zh-CN',
                scanlationGroup: '',
                isDownloaded: chapterInfo.isDownloaded || false,
                downloadStatus: chapterInfo.isDownloaded ? DownloadStatus.COMPLETED : DownloadStatus.PENDING,
                downloadProgress: chapterInfo.isDownloaded ? 100 : 0,
                localPath: chapterInfo.downloadPath,
                externalId: chapterInfo.externalId
              } as MangaChapter));
            } else {
              manga.chapters = [];
            }
          } else {
            const chapters = await this.dataManager.getComicChapters(manga.id);
            if (chapters && chapters.length > 0) {
              manga.chapters = chapters.map(chapterInfo => ({
                id: chapterInfo.id,
                title: chapterInfo.title,
                chapterNumber: chapterInfo.index,
                pages: [],
                publishDate: chapterInfo.publishTime || Date.now(),
                language: 'zh-CN',
                scanlationGroup: '',
                isDownloaded: chapterInfo.isDownloaded || false,
                downloadStatus: chapterInfo.isDownloaded ? DownloadStatus.COMPLETED : DownloadStatus.PENDING,
                downloadProgress: chapterInfo.isDownloaded ? 100 : 0,
                localPath: chapterInfo.downloadPath,
                externalId: chapterInfo.externalId
              } as MangaChapter));
            } else {
              manga.chapters = [];
            }
          }
        } catch (chapterError) {
          manga.chapters = [];
        }
      }

      // 增量更新漫画列表
      this.incrementalUpdateMangaList(this.mangaList, newMangaList);
      this.applyLibraryFilter();

      // 增量更新电子书列表
      try {
        const newEbookList = await this.ebookDataManager.getEBookList();
        const newPdfEbooks = newMangaList.filter((manga: Manga) => manga.contentType === 'ebook');

        this.incrementalUpdateEBookList(this.ebookList, newEbookList);
        this.incrementalUpdateMangaList(this.pdfEbookList, newPdfEbooks);
        this.applyEBookFilter();
      } catch (ebookErr) {
        logger.warn(TAG, `静默刷新电子书列表失败: ${ebookErr instanceof Error ? ebookErr.message : String(ebookErr)}`);
      }

      logger.debug(TAG, `静默刷新书库完成：漫画 ${this.mangaList.length} 部`);
    } catch (error) {
      logger.warn(TAG, `静默刷新书库失败: ${String(error)}`);
    }
  }

  /**
   * 静默刷新发现页数据（不显示加载状态和toast，避免闪屏）
   */
  private async silentRefreshDiscoverData(): Promise<void> {
    try {
      logger.debug(TAG, '静默刷新发现页数据');

      // 静默刷新书库数据
      await this.silentRefreshLibrary();

      // 重新提取标签和作者
      await this.extractTagsAndAuthors();

      // 重新应用筛选
      this.applyDiscoverFilter();

      logger.debug(TAG, '静默刷新发现页数据完成');
    } catch (error) {
      logger.warn(TAG, `静默刷新发现页数据失败: ${String(error)}`);
    }
  }

  /**
   * 处理路由参数
   */
  private handleRouteParams(): void {
    try {
      const router = this.uiContext?.getRouter();
      if (router) {
        const params = router.getParams() as Record<string, string | number | boolean>;
        if (params) {
          this.fromGuide = params['fromGuide'] as boolean ?? false;
          this.targetPage = params['targetPage'] as string ?? '';
          this.targetTab = params['targetTab'] as number ?? -1;

          logger.info(TAG, `路由参数: fromGuide=${this.fromGuide}, targetPage=${this.targetPage}, targetTab=${this.targetTab}`);
        }
      }

      // 检查是否有待导入的文件
      this.checkPendingFileImport();
    } catch (error) {
      logger.error(TAG, '处理路由参数失败', String(error));
    }
  }

  /**
   * 检查并处理待导入的文件
   */
  private checkPendingFileImport(): void {
    try {
      // 优先检查系统分享导入
      const pendingShareFiles = AppStorage.get<string[]>('pendingShareFiles');
      if (pendingShareFiles && Array.isArray(pendingShareFiles) && pendingShareFiles.length > 0) {
        logger.info(TAG, `📤 检测到系统分享文件: ${pendingShareFiles.length} 个`);
        this.checkPendingShareImport();
        return;
      }

      // 检查普通文件导入
      const pendingFileUri = AppStorage.get<string>('pendingFileUri');
      const pendingFileType = AppStorage.get<string>('pendingFileType');

      if (pendingFileUri) {
        logger.info(TAG, `📁 检测到待导入文件: ${pendingFileUri}, 类型: ${pendingFileType}`);

        // 不清除标记，让DataManagementPage读取
        // 使用新的key存储已经处理的标记
        AppStorage.setOrCreate('fileImportPending', true);

        // 直接导航到DataManagementPage
        setTimeout(() => {
          this.navigateToDataManagement();
        }, 500);
      }
    } catch (error) {
      logger.error(TAG, '检查待导入文件失败', String(error));
    }
  }

  /**
   * 检查并处理系统分享导入的文件
   */
  private checkPendingShareImport(): void {
    try {
      const pendingShareFiles = AppStorage.get<string[]>('pendingShareFiles');
      const pendingShareType = AppStorage.get<string>('pendingShareType');
      const pendingShareSource = AppStorage.get<string>('pendingShareSource');

      if (!pendingShareFiles || !Array.isArray(pendingShareFiles) || pendingShareFiles.length === 0) {
        return;
      }

      logger.info(TAG, `📤 处理系统分享导入: ${pendingShareFiles.length} 个文件, 类型: ${pendingShareType}, 来源: ${pendingShareSource}`);

      // 设置标记，让DataManagementPage读取
      AppStorage.setOrCreate('shareImportPending', true);

      // 直接导航到DataManagementPage
      setTimeout(() => {
        this.navigateToDataManagement();
      }, 500);

    } catch (error) {
      logger.error(TAG, '检查系统分享文件失败', String(error));
    }
  }

  /**
   * 导航到数据管理页面
   */
  private navigateToDataManagement(): void {
    try {
      logger.info(TAG, '导航到数据管理页面');

      // 切换到设置标签页
      this.currentTabIndex = TabIndex.SETTINGS;

      // 准备导航参数
      const navParam: NavigationPathParam = {
        fromPage: 'MainMenuPage',
        timestamp: Date.now()
      };

      // 导航到DataManagementPage
      this.pathStack.pushPath({ name: 'DataManagementPage', param: navParam });
      logger.info(TAG, '✅ 已导航到数据管理页面');
    } catch (error) {
      logger.error(TAG, '导航到数据管理页面失败', String(error));
    }
  }

  /**
   * 处理文件导入
   */
  private handleFileImport(fileUri: string, fileType: string): void {
    try {
      logger.info(TAG, `开始处理文件导入: ${fileUri}, 类型: ${fileType}`);

      // 从URI中提取文件扩展名（如果fileType为空）
      let actualFileType = fileType;
      if (!actualFileType || actualFileType.trim() === '') {
        // 解码URI并提取文件扩展名
        const decodedUri = decodeURIComponent(fileUri);
        logger.debug(TAG, `解码后的URI: ${decodedUri}`);

        const lastDotIndex = decodedUri.lastIndexOf('.');
        if (lastDotIndex > 0) {
          const extension = decodedUri.substring(lastDotIndex).toLowerCase();
          logger.info(TAG, `从URI提取到文件扩展名: ${extension}`);
          actualFileType = extension;
        }
      }

      logger.info(TAG, `实际文件类型: ${actualFileType}`);

      // 根据文件类型判断导入目标
      const lowerType = actualFileType.toLowerCase();
      if (lowerType.includes('cbz') || lowerType.includes('.cbz') ||
      lowerType.includes('zip') || lowerType.includes('.zip')) {
        // 漫画文件 - 导航到数据管理页面并传递文件URI
        logger.info(TAG, '准备导入漫画文件到数据管理页面');
        // 通过EventBus发送文件导入事件
        const payload = new FileImportRequestedPayload(fileUri, 'comic');
        eventBus.publish(GameEvent.FILE_IMPORT_REQUESTED, payload);
      } else if (lowerType.includes('epub') || lowerType.includes('.epub') ||
      lowerType.includes('pdf') || lowerType.includes('.pdf') ||
      lowerType.includes('txt') || lowerType.includes('.txt')) {
        // 电子书文件
        logger.info(TAG, '准备导入电子书文件到数据管理页面');
        const payload = new FileImportRequestedPayload(fileUri, 'ebook');
        eventBus.publish(GameEvent.FILE_IMPORT_REQUESTED, payload);
      } else {
        logger.warn(TAG, `不支持的文件类型: ${actualFileType}`);
        logger.warn(TAG, `完整URI: ${fileUri}`);
      }
    } catch (error) {
      logger.error(TAG, '处理文件导入失败', String(error));
    }
  }

  /**
   * 处理引导导航
   */
  private handleGuideNavigation(): void {
    setTimeout(() => {
      try {
        // 处理目标标签页
        if (this.targetTab >= 0 && this.targetTab <= TabIndex.SETTINGS) {
          this.currentTabIndex = this.targetTab;
          this.tabsController.changeIndex(this.targetTab);
          logger.info(TAG, `切换到标签页: ${this.targetTab}`);
        }

        // 处理目标页面
        if (this.targetPage.length > 0) {
          logger.info(TAG, `导航到目标页面: ${this.targetPage}`);
          this.pathStack.pushPath({ name: this.targetPage });

          // 监听页面返回事件，当用户从目标页面返回时，返回到引导页面
          this.setupGuideReturnListener();
        }
      } catch (error) {
        logger.error(TAG, '处理引导导航失败', String(error));
      }
    }, 500); // 延迟以确保页面完全加载
  }

  /**
   * 设置引导返回监听器
   * 当用户从引导目标页面返回时，自动返回到引导页面继续流程
   */
  private setupGuideReturnListener(): void {
    // 监听 pathStack 大小变化
    const checkInterval = setInterval(() => {
      try {
        const stackSize = this.pathStack.size();
        logger.debug(TAG, `Navigation栈大小: ${stackSize}, fromGuide: ${this.fromGuide}, targetPage: ${this.targetPage}`);

        // 如果栈大小为0（用户已从目标页面返回）且是从引导跳转的
        if (stackSize === 0 && this.fromGuide && this.targetPage.length > 0) {
          clearInterval(checkInterval);
          logger.info(TAG, '检测到用户从引导目标页面返回，准备返回引导页面');

          // 检查引导是否已完成
          if (!this.welcomeGuideManager.isGuideCompleted()) {
            logger.info(TAG, '引导未完成，返回引导页面继续流程');
            this.returnToGuide();
          } else {
            logger.info(TAG, '引导已完成，留在主页面');
            // 清理引导标记
            this.fromGuide = false;
            this.targetPage = '';
          }
        }
      } catch (error) {
        logger.error(TAG, '监听引导返回失败', String(error));
        clearInterval(checkInterval);
      }
    }, 300); // 每300ms检查一次

    // 设置超时清理，防止内存泄漏（30秒后自动清理）
    setTimeout(() => {
      clearInterval(checkInterval);
      logger.debug(TAG, '引导返回监听器已超时清理');
    }, 30000);
  }

  /**
   * 返回引导页面
   */
  private returnToGuide(): void {
    try {
      const router = this.uiContext?.getRouter();
      if (router) {
        router.replaceUrl({
          url: 'pages/WelcomeGuidePage'
        }).then(() => {
          logger.info(TAG, '成功返回引导页面');
          // 清理引导标记
          this.fromGuide = false;
          this.targetPage = '';
        }).catch((error: Error) => {
          logger.error(TAG, '返回引导页面失败', error.message);
        });
      }
    } catch (error) {
      logger.error(TAG, '返回引导页面异常', String(error));
    }
  }

  aboutToDisappear() {
    logger.lifecycle(TAG, '应用主页面即将销毁');

    // 移除隐私模式监听器
    if (this.privacyModeListener) {
      this.privacyModeManager.removeListener(this.privacyModeListener);
      this.privacyModeListener = null;
      logger.debug(TAG, '隐私模式监听器已清理');
    }

    // 移除SFW模式监听器
    if (this.sfwModeListener) {
      this.contentFilterManager.removeListener(this.sfwModeListener);
      this.sfwModeListener = null;
      logger.debug(TAG, 'SFW模式监听器已清理');
    }

    // 移除设备变化监听器
    if (this.deviceChangeListener) {
      this.deviceManager.removeListener(this.deviceChangeListener);
      this.deviceChangeListener = null;
    }

    ThemeAwareHelper.cleanupThemeAware(this.componentId);
    FontAwareHelper.cleanupFontAware(this.componentId);

    // 取消订阅漫画导入完成事件
    eventBus.unsubscribe(GameEvent.MANGA_IMPORT_COMPLETED, (payload: IEventPayload) => {
      const mangaPayload = payload as MangaImportCompletedPayload;
      logger.info(TAG, `收到漫画导入完成事件，成功导入 ${mangaPayload.importedCount} 个漫画`);
      // 刷新漫画列表
      this.loadMangaList();
    });
  }

  /**
   * 请求通知权限
   */
  private async requestNotificationPermission(): Promise<void> {
    try {
      const context = this.getUIContext().getHostContext() as common.UIAbilityContext;
      const notificationManager = AppNotificationManager.getInstance();
      const hasPermission = await notificationManager.requestPermission(context);

      if (hasPermission) {
        logger.info(TAG, '✅ 通知权限已授予');
      } else {
        logger.warn(TAG, '⚠️ 通知权限未授予，部分功能可能受限');
      }
    } catch (error) {
      logger.error(TAG, `请求通知权限失败: ${error}`);
    }
  }

  /**
   * 页面显示时静默刷新数据
   * 确保从任何页面返回时都能正确显示最新的阅读情况
   * 使用静默刷新避免闪屏
   */
  onPageShow(): void {
    logger.lifecycle(TAG, '📱 页面显示，静默刷新数据');

    // 根据当前标签页静默刷新对应数据（不显示加载状态，避免闪屏）
    switch (this.currentTabIndex) {
      case TabIndex.HOME:
        // 首页：静默刷新最近阅读列表
        this.silentRefreshRecentReadingList();
        break;
      case TabIndex.LIBRARY:
        // 书库：静默刷新漫画和电子书列表
        this.silentRefreshLibrary();
        break;
      case TabIndex.DISCOVER:
        // 发现页：静默刷新发现页数据
        this.silentRefreshDiscoverData();
        break;
      default:
        break;
    }
  }

  /**
   * 刷新指示器Builder
   */
  @Builder
  refreshBuilder() {
    Row({ space: 8 }) {
      LoadingProgress()
        .width(20)
        .height(20)
        .color(ThemeAwareHelper.getTestManagementThemedColor('accent_primary', this.themeState.currentTheme))

      Text('正在刷新...')
        .fontSize(14)
        .fontFamily(this.appFontFamily)
        .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_secondary', this.themeState.currentTheme))
    }
    .justifyContent(FlexAlign.Center)
    .width('100%')
    .height(60)
  }

  /**
   * 初始化系统
   */
  private async initializeSystem(): Promise<void> {
    try {
      logger.info(TAG, '开始系统初始化...');

      // 设置全局UIContext
      AppStorage.setOrCreate('uiContext', this.uiContext);
      AppStorage.setOrCreate('GlobalNavStack', this.pathStack);

      this.isSystemInitialized = true;
      logger.info(TAG, '✅ 系统初始化完成');

    } catch (error) {
      logger.error(TAG, '❌ 系统初始化失败', String(error));
      this.initializationProgress = '初始化失败';
    }
  }

  /**
   * 初始化使用手册（首次运行时添加）
   */
  private async initializeUserManualIfNeeded(): Promise<void> {
    try {
      await this.welcomeGuideManager.initializeUserManual();
    } catch (error) {
      logger.error(TAG, '初始化使用手册失败', String(error));
    }
  }

  /**
   * 检查并显示更新日志（新版本首次启动）
   */
  private async checkAndShowChangelog(): Promise<void> {
    try {
      const changelogManager = getChangelogManager();
      const shown = await changelogManager.checkAndShowChangelog();
      if (shown) {
        logger.info(TAG, '✅ 已显示新版本更新日志');
      }
    } catch (error) {
      logger.error(TAG, '检查更新日志失败', String(error));
    }
  }

  /**
   * 加载版本信息
   */
  private loadVersionInfo(): void {
    try {
      this.systemVersion = deviceInfo.displayVersion;
      logger.info(TAG, `系统版本信息已获取: ${this.systemVersion}`);
    } catch (error) {
      logger.error(TAG, '获取系统版本信息失败', String(error));
      this.systemVersion = 'Unknown';
    }
  }

  /**
   * 加载可见标签配置
   */
  /**
   * 字体变化回调
   */
  private onAppFontFamilyChange(): void {
    logger.info(TAG, `字体变化回调触发: ${this.appFontFamily}, fontRefreshKey=${this.fontRefreshKey}`);
    // 强制触发UI刷新
    this.fontRefreshKey = this.fontRefreshKey + 1;
    // 同步更新fontState
    this.fontState.appFontFamily = this.appFontFamily;
  }

  private loadVisibleTabs(): void {
    try {
      const savedTabs = AppStorage.get<number[]>('visible_tabs');
      if (savedTabs && savedTabs.length > 0) {
        this.visibleTabIndices = savedTabs;
        logger.info(TAG, `已加载自定义标签配置: ${JSON.stringify(savedTabs)}`);
      } else {
        // 默认显示所有标签
        this.visibleTabIndices = this.tabConfigs.map(cfg => cfg.index);
        logger.info(TAG, '使用默认标签配置');
      }
    } catch (error) {
      logger.error(TAG, '加载可见标签配置失败', String(error));
      this.visibleTabIndices = this.tabConfigs.map(cfg => cfg.index);
    }
  }

  /**
   * 保存可见标签配置
   */
  private async saveVisibleTabs(indices: number[]): Promise<void> {
    try {
      // 确保必须显示的标签（书库、设置）始终存在
      const requiredIndices = this.tabConfigs
        .filter(cfg => cfg.required)
        .map(cfg => cfg.index);
      
      // 合并索引并去重
      const combined: number[] = [];
      for (const idx of indices) {
        if (!combined.includes(idx)) {
          combined.push(idx);
        }
      }
      for (const idx of requiredIndices) {
        if (!combined.includes(idx)) {
          combined.push(idx);
        }
      }
      
      const finalIndices = combined;
      finalIndices.sort((a, b) => a - b);
      
      AppStorage.setOrCreate('visible_tabs', finalIndices);
      this.visibleTabIndices = finalIndices;
      
      logger.info(TAG, `已保存标签配置: ${JSON.stringify(finalIndices)}`);
    } catch (error) {
      logger.error(TAG, '保存可见标签配置失败', String(error));
    }
  }

  /**
   * 显示标签自定义对话框
   */
  private openTabCustomizationDialog(): void {
    this.tempVisibleTabIndices = [];
    for (const idx of this.visibleTabIndices) {
      this.tempVisibleTabIndices.push(idx);
    }
    this.showTabCustomDialog = true;
  }

  /**
   * 切换标签可见性
   */
  private toggleTabVisibility(index: number): void {
    // 使用数组重新赋值而不是splice/push，避免触发过多的UI更新
    const newIndices: number[] = [];
    const idx = this.tempVisibleTabIndices.indexOf(index);
    
    if (idx > -1) {
      // 移除该索引
      for (let i = 0; i < this.tempVisibleTabIndices.length; i++) {
        if (this.tempVisibleTabIndices[i] !== index) {
          newIndices.push(this.tempVisibleTabIndices[i]);
        }
      }
    } else {
      // 添加该索引
      for (let i = 0; i < this.tempVisibleTabIndices.length; i++) {
        newIndices.push(this.tempVisibleTabIndices[i]);
      }
      newIndices.push(index);
    }
    
    // 一次性赋值，只触发一次UI更新
    this.tempVisibleTabIndices = newIndices;
  }

  /**
   * 应用标签自定义配置
   */
  private async applyTabCustomization(): Promise<void> {
    await this.saveVisibleTabs(this.tempVisibleTabIndices);
    this.showTabCustomDialog = false;
    this.showToast('底栏配置已保存');
  }

  /**
   * [新增] 同时加载本地和在线漫画
   */
  private async loadAllMangaFromDatabase(): Promise<Manga[]> {
    const mangaList: Manga[] = [];

    try {
      // 根据隐私模式选择查询方法
      let localComics: ComicInfo[] = [];
      let onlineComics: OnlineComicInfo[] = [];

      if (this.isPrivacyMode) {
        // 隐私模式：直接查询隐私内容
        localComics = await this.dataManager.getPrivateComics();
        onlineComics = await this.dataManager.getPrivateOnlineComics();
        logger.info(TAG, `隐私模式：从comic_info表获取到 ${localComics.length} 条隐私本地漫画`);
        logger.info(TAG, `隐私模式：从online_comic_info表获取到 ${onlineComics.length} 条隐私在线漫画`);
      } else {
        // 普通模式：直接查询非隐私内容
        localComics = await this.dataManager.getNonPrivateComics();
        onlineComics = await this.dataManager.getNonPrivateOnlineComics();
        logger.info(TAG, `普通模式：从comic_info表获取到 ${localComics.length} 条非隐私本地漫画`);
        logger.info(TAG, `普通模式：从online_comic_info表获取到 ${onlineComics.length} 条非隐私在线漫画`);
      }

      // 转换本地漫画
      for (const comicInfo of localComics) {
        try {
          const manga = await ComicConverter.convertComicInfoToMangaAsync(comicInfo);
          mangaList.push(manga);
        } catch (convErr) {
          logger.warn(TAG, `转换本地漫画失败: ${String(convErr)}`);
          const fallback = ComicConverter.convertComicInfoToManga(comicInfo);
          mangaList.push(fallback);
        }
      }

      // 转换在线漫画
      for (const onlineComicInfo of onlineComics) {
        try {
          const manga = await ComicConverter.convertOnlineComicInfoToMangaAsync(onlineComicInfo);
          mangaList.push(manga);
        } catch (convErr) {
          logger.warn(TAG, `转换在线漫画失败: ${String(convErr)}`);
        }
      }

      logger.info(TAG, `总共加载 ${mangaList.length} 部漫画（本地: ${localComics.length}, 在线: ${onlineComics.length}）`);
    } catch (error) {
      logger.error(TAG, `加载漫画数据失败: ${String(error)}`);
    }

    return mangaList;
  }

  /**
   * 加载漫画列表
   */
  private async loadMangaList(): Promise<void> {
    try {
      this.isLoadingMangaList = true;
      logger.info(TAG, '开始加载漫画列表...');

      // [修复] 同时加载本地和在线漫画
      const mangaList = await this.loadAllMangaFromDatabase();
      logger.info(TAG, `从数据库获取到 ${mangaList.length} 条漫画记录`);

      // [修复] 已在loadAllMangaFromDatabase中完成转换

      // [重构] 为每个漫画加载章节信息（区分在线和本地）
      for (const manga of mangaList) {
        try {
          // 判断是否为在线漫画（有sourceId且不为0）
          const isOnlineManga = manga.sourceInfo?.sourceId && Number(manga.sourceInfo.sourceId) > 0;

          if (isOnlineManga) {
            // 在线漫画：从online_chapter表加载
            const onlineChapters = await this.dataManager.getOnlineComicChapters(manga.id);
            if (onlineChapters && onlineChapters.length > 0) {
              manga.chapters = onlineChapters.map(chapterInfo => ({
                id: chapterInfo.id,
                title: chapterInfo.title,
                chapterNumber: chapterInfo.chapterNumber, // OnlineChapterInfo使用chapterNumber
                pages: [],
                publishDate: chapterInfo.publishTime || Date.now(),
                language: 'zh-CN',
                scanlationGroup: '',
                isDownloaded: chapterInfo.isDownloaded || false,
                downloadStatus: chapterInfo.isDownloaded ? DownloadStatus.COMPLETED : DownloadStatus.PENDING,
                downloadProgress: chapterInfo.isDownloaded ? 100 : 0,
                localPath: chapterInfo.downloadPath,
                externalId: chapterInfo.externalId
              } as MangaChapter));
              logger.debug(TAG, `在线漫画 "${manga.title}" 从online_chapter表加载了 ${manga.chapters.length} 个章节`);
            } else {
              manga.chapters = [];
            }
          } else {
            // 本地漫画：从chapter表加载
            const chapters = await this.dataManager.getComicChapters(manga.id);
            if (chapters && chapters.length > 0) {
              manga.chapters = chapters.map(chapterInfo => ({
                id: chapterInfo.id,
                title: chapterInfo.title,
                chapterNumber: chapterInfo.index, // ChapterInfo使用index
                pages: [],
                publishDate: chapterInfo.publishTime || Date.now(),
                language: 'zh-CN',
                scanlationGroup: '',
                isDownloaded: chapterInfo.isDownloaded || false,
                downloadStatus: chapterInfo.isDownloaded ? DownloadStatus.COMPLETED : DownloadStatus.PENDING,
                downloadProgress: chapterInfo.isDownloaded ? 100 : 0,
                localPath: chapterInfo.downloadPath,
                externalId: chapterInfo.externalId
              } as MangaChapter));
              logger.debug(TAG, `本地漫画 "${manga.title}" 从chapter表加载了 ${manga.chapters.length} 个章节`);
            } else {
              manga.chapters = [];
            }
          }
        } catch (chapterError) {
          logger.warn(TAG, `加载漫画 "${manga.title}" 的章节信息失败: ${chapterError}`);
          manga.chapters = [];
        }
      }

      this.mangaList = mangaList;
      logger.info(TAG, `成功加载 ${this.mangaList.length} 部漫画`);

      // 应用筛选
      this.applyLibraryFilter();
    } catch (error) {
      logger.error(TAG, '加载漫画列表失败', String(error));
      this.mangaList = [];
      // 应用筛选
      this.applyLibraryFilter();
    } finally {
      this.isLoadingMangaList = false;
    }
  }


  /**
   * 刷新书库（漫画与电子书）列表
   */
  public async refreshMangaList(): Promise<void> {
    if (this.isRefreshing || this.isLoadingMangaList || this.isLoadingEbookList) {
      return;
    }

    this.isRefreshing = true;
    try {
      await Promise.all([
        this.loadMangaList(),
        this.loadEBookList()
      ]);
    } catch (error) {
      logger.error(TAG, `刷新书库失败: ${String(error instanceof Error ? error.message : error)}`);
      this.showToast('刷新失败，请稍后重试');
    } finally {
      this.isRefreshing = false;
    }
  }

  // ==================== 多选模式相关方法 ====================

  /**
   * 进入多选模式
   */
  private enterMultiSelectMode(): void {
    this.isMultiSelectMode = true;
    this.selectedMangaIds.clear();
    logger.info(TAG, '进入多选模式');
  }

  /**
   * 退出多选模式
   */
  private exitMultiSelectMode(): void {
    this.isMultiSelectMode = false;
    this.selectedMangaIds.clear();
    logger.info(TAG, '退出多选模式');
  }

  /**
   * 切换漫画选中状态
   */
  private toggleMangaSelection(mangaId: string): void {
    if (this.selectedMangaIds.has(mangaId)) {
      this.selectedMangaIds.delete(mangaId);
    } else {
      this.selectedMangaIds.add(mangaId);
    }
    // 触发UI更新
    this.selectedMangaIds = new Set(this.selectedMangaIds);
    logger.debug(TAG, `切换漫画选中状态: ${mangaId}, 当前选中数量: ${this.selectedMangaIds.size}`);
  }

  /**
   * 全选漫画
   */
  private selectAllManga(): void {
    for (const manga of this.filteredMangaList) {
      this.selectedMangaIds.add(manga.id);
    }
    this.selectedMangaIds = new Set(this.selectedMangaIds);
    logger.info(TAG, `全选漫画: ${this.selectedMangaIds.size}个`);
  }

  /**
   * 显示删除确认对话框
   */
  private showBatchDeleteConfirm(): void {
    if (this.selectedMangaIds.size === 0) {
      this.showToast('请选择要删除的漫画');
      return;
    }
    this.showBatchDeleteConfirmDialog();
  }

  /**
   * 批量删除漫画
   */
  private async batchDeleteManga(): Promise<void> {
    if (this.selectedMangaIds.size === 0) {
      return;
    }

    this.isDeletingManga = true;
    try {
      const mangaIds = Array.from(this.selectedMangaIds);
      logger.info(TAG, `开始批量删除漫画: ${mangaIds.length}个`);

      const result = await this.dataManager.deleteComics(mangaIds);

      logger.info(TAG, `批量删除完成: 成功=${result.successCount}, 失败=${result.failedCount}`);

      if (result.failedCount > 0) {
        this.showToast(`删除完成，成功${result.successCount}个，失败${result.failedCount}个`);
      } else {
        this.showToast(`成功删除${result.successCount}个漫画`);
      }

      // 退出多选模式
      this.exitMultiSelectMode();

      // 刷新漫画列表
      await this.loadMangaList();

    } catch (error) {
      const errorMessage = error instanceof Error ? error.message : String(error);
      logger.error(TAG, `批量删除漫画失败: ${errorMessage}`);
      this.showToast('删除失败，请稍后重试');
    } finally {
      this.isDeletingManga = false;
    }
  }

  // ==================== 电子书多选模式相关方法 ====================

  /**
   * 进入电子书多选模式
   */
  private enterEBookMultiSelectMode(): void {
    this.isEBookMultiSelectMode = true;
    this.selectedEBookIds.clear();
    logger.info(TAG, '进入电子书多选模式');
  }

  /**
   * 退出电子书多选模式
   */
  private exitEBookMultiSelectMode(): void {
    this.isEBookMultiSelectMode = false;
    this.selectedEBookIds.clear();
    logger.info(TAG, '退出电子书多选模式');
  }

  /**
   * 切换电子书选中状态
   */
  private toggleEBookSelection(ebookId: string): void {
    if (this.selectedEBookIds.has(ebookId)) {
      this.selectedEBookIds.delete(ebookId);
    } else {
      this.selectedEBookIds.add(ebookId);
    }
    // 触发UI更新
    this.selectedEBookIds = new Set(this.selectedEBookIds);
    logger.debug(TAG, `切换电子书选中状态: ${ebookId}, 当前选中数量: ${this.selectedEBookIds.size}`);
  }

  /**
   * 进入小说多选模式
   */
  private enterNovelMultiSelectMode(): void {
    this.isNovelMultiSelectMode = true;
    this.selectedNovelIds.clear();
    logger.info(TAG, '进入小说多选模式');
  }

  /**
   * 退出小说多选模式
   */
  private exitNovelMultiSelectMode(): void {
    this.isNovelMultiSelectMode = false;
    this.selectedNovelIds.clear();
    logger.info(TAG, '退出小说多选模式');
  }

  /**
   * 切换小说选中状态
   */
  private toggleNovelSelection(novelId: string): void {
    if (this.selectedNovelIds.has(novelId)) {
      this.selectedNovelIds.delete(novelId);
    } else {
      this.selectedNovelIds.add(novelId);
    }
    // 触发UI更新
    this.selectedNovelIds = new Set(this.selectedNovelIds);
    logger.debug(TAG, `切换小说选中状态: ${novelId}, 当前选中数量: ${this.selectedNovelIds.size}`);
  }

  /**
   * 显示删除小说确认对话框
   */
  private showDeleteNovelDialog(novelId: string): void {
    const novel = this.novelList.find(n => n.id === novelId);
    if (!novel) {
      logger.error(TAG, `未找到小说ID为 ${novelId} 的小说`);
      return;
    }

    logger.info(TAG, `显示删除小说确认对话框: ${novel.name} (ID: ${novelId})`);

    this.getUIContext().showAlertDialog({
      title: '删除小说',
      message: `确定要删除小说“${novel.name}”吗？\n\n此操作将删除该小说的所有数据，且不可恢复。`,
      autoCancel: true,
      alignment: DialogAlignment.Center,
      primaryButton: {
        value: '取消',
        action: () => {
          logger.info(TAG, '用户取消删除小说');
        }
      },
      secondaryButton: {
        value: '删除',
        fontColor: ThemeAwareHelper.getTestManagementThemedColor('button_danger', this.themeState.currentTheme),
        action: async () => {
          try {
            logger.info(TAG, `开始删除小说: ${novelId}`);
            
            // 直接从数据库删除小说
            const dbManager = DatabaseManager.getInstance();
            await dbManager.executeSql('DELETE FROM novel_book WHERE id = ?', [novelId]);
            await dbManager.executeSql('DELETE FROM novel_chapter WHERE bookId = ?', [novelId]);
            
            // 更新本地列表
            const newNovelList: NovelBook[] = [];
            for (let i: number = 0; i < this.novelList.length; i++) {
              const n: NovelBook = this.novelList[i];
              if (n.id !== novelId) { newNovelList.push(n); }
            }
            this.novelList = newNovelList;

            await this.applyNovelFilter();

            this.showToast('小说已删除');
            logger.info(TAG, `小说删除成功: ${novelId}`);
          } catch (error) {
            logger.error(TAG, '删除小说失败', String(error));
            this.showToast('删除失败');
          }
        }
      }
    });
  }

  /**
   * 全选电子书
   */
  private selectAllEBooks(): void {
    for (const ebook of this.filteredEbookList) {
      this.selectedEBookIds.add(ebook.id);
    }
    this.selectedEBookIds = new Set(this.selectedEBookIds);
    logger.info(TAG, `全选电子书: ${this.selectedEBookIds.size}个`);
  }

  /**
   * 显示电子书批量删除确认
   */
  private showEBookBatchDeleteConfirm(): void {
    if (this.selectedEBookIds.size === 0) {
      this.showToast('请选择要删除的电子书');
      return;
    }
    // 使用 AlertDialog 确认删除
    AlertDialog.show({
      title: '确认删除',
      message: `确定要删除选中的 ${this.selectedEBookIds.size} 本电子书吗？此操作不可恢复。`,
      autoCancel: true,
      alignment: DialogAlignment.Center,
      primaryButton: {
        value: '取消',
        action: () => {
          logger.info(TAG, '用户取消电子书批量删除');
        }
      },
      secondaryButton: {
        value: '删除',
        fontColor: Color.Red,
        action: () => {
          this.batchDeleteEBooks();
        }
      }
    });
  }

  /**
   * 批量删除电子书
   */
  private async batchDeleteEBooks(): Promise<void> {
    if (this.selectedEBookIds.size === 0) {
      return;
    }

    this.isDeletingEBook = true;
    try {
      const ebookIds = Array.from(this.selectedEBookIds);
      logger.info(TAG, `开始批量删除电子书: ${ebookIds.length}个`);

      let successCount = 0;
      let failedCount = 0;

      for (const ebookId of ebookIds) {
        try {
          await this.ebookDataManager.deleteEBook(ebookId);
          successCount++;
        } catch (error) {
          failedCount++;
          logger.error(TAG, `删除电子书失败: ${ebookId}, ${String(error)}`);
        }
      }

      logger.info(TAG, `批量删除完成: 成功=${successCount}, 失败=${failedCount}`);

      if (failedCount > 0) {
        this.showToast(`删除完成，成功${successCount}个，失败${failedCount}个`);
      } else {
        this.showToast(`成功删除${successCount}本电子书`);
      }

      // 退出多选模式
      this.exitEBookMultiSelectMode();

      // 刷新电子书列表
      await this.loadEBookList();

    } catch (error) {
      const errorMessage = error instanceof Error ? error.message : String(error);
      logger.error(TAG, `批量删除电子书失败: ${errorMessage}`);
      this.showToast('删除失败，请稍后重试');
    } finally {
      this.isDeletingEBook = false;
    }
  }

  /**
   * 处理隐私模式验证
   */
  private async handlePrivacyModeAuth(): Promise<void> {
    try {
      // 触发震动反馈
      this.triggerHapticFeedback();
      
      logger.info(TAG, '开始隐私模式验证');
      
      // 如果已经在隐私模式，则退出隐私模式
      if (this.isPrivacyMode) {
        this.privacyModeManager.exitPrivacyMode();
        this.showToast('已退出隐私书库');
        return;
      }
      
      // 尝试生物识别验证
      const success = await this.privacyModeManager.enterPrivacyMode();
      
      if (success) {
        this.showToast('已进入隐私书库');
      } else {
        // 生物识别失败，显示密码输入对话框
        this.showPrivacyPasswordDialog();
      }
    } catch (error) {
      logger.error(TAG, `隐私模式验证失败: ${JSON.stringify(error)}`);
      this.showToast('验证失败，请重试');
    }
  }
  
  /**
   * 显示隐私密码输入对话框
   */
  private showPrivacyPasswordDialog(): void {
    // TODO: 实现密码输入对话框
    // 由于需要使用CustomDialog，这里暂时使用Toast提示
    this.showToast('请再次验证');
  }

  /**
   * 显示Toast提示
   */
  private showToast(message: string, duration: number = 2000): void {
    try {
      const toastConfig: ToastConfig = {
        message: message,
        duration: duration,
        bottom: 100
      };
      this.getUIContext().getPromptAction().showToast(toastConfig);
    } catch (error) {
      logger.warn(TAG, `Toast显示失败: ${message}`);
    }
  }

  /**
   * 显示更多选项菜单
   */
  private showMoreOptions(): void {
    try {
      this.getUIContext().getPromptAction().showActionMenu({
        title: '更多选项',
        buttons: [
          { text: '首页', color: '#007DFF' },
          { text: '我的书库', color: '#007DFF' },
          { text: '发现', color: '#007DFF' },
          { text: '设置', color: '#007DFF' },
          { text: '关于应用', color: '#007DFF' }
        ]
      }, (err, data) => {
        const result = data as ActionMenuResult | undefined;
        if (!result || result.index < 0) {
          logger.info(TAG, '用户取消更多选项菜单');
          return;
        }
        const e = err as BusinessError | undefined;
        if (e && e.code !== 0) {
          logger.error(TAG, '显示更多选项菜单失败', e.message);
          return;
        }
        switch (result.index) {
          case 0:
            this.handleTabButtonClick(TabIndex.HOME);
            break;
          case 1:
            this.handleTabButtonClick(TabIndex.LIBRARY);
            break;
          case 2:
            this.handleTabButtonClick(TabIndex.DISCOVER);
            break;
          case 3:
            this.handleTabButtonClick(TabIndex.SETTINGS);
            break;
          case 4:
            try {
              const navigationPath: NavigationPath = {
                name: 'AboutPage',
                param: {
                  fromPage: 'MainMenuPage',
                  timestamp: Date.now()
                }
              };
              this.pathStack.pushPath(navigationPath);
              logger.info(TAG, '导航到关于应用页面');
            } catch (navErr) {
              logger.error(TAG, '导航到关于应用页面失败', String(navErr));
              this.showToast('打开关于应用页面失败');
            }
            break;
        }
      });
    } catch (error) {
      logger.error(TAG, '显示更多选项菜单失败', String(error));
    }
  }

  /**
   * 规范化封面显示路径：本地文件统一补充 file:// 前缀，便于 Image 组件正确解析
   */
  private normalizeDisplayPathForManga(mg: Manga): string {
    if (!mg || !mg.coverImagePath) {
      return '';
    }
    const raw: string = mg.coverImagePath;

    // [修复] 检查是否为资源引用字符串（如 'app.media.mangabook'），这种情况返回空字符串让调用方使用 $r() 资源引用
    if (raw.indexOf('app.media.') === 0 || raw.indexOf('$r(') === 0) {
      logger.debug('MainMenuPage', `检测到资源引用字符串，返回空字符串使用默认资源: raw='${raw}'`);
      return '';
    }

    const type: ImageSourceType = mg.coverSourceType !== undefined ? mg.coverSourceType as ImageSourceType : ImageSourceType.LOCAL;
    if (type === ImageSourceType.LOCAL) {
      const hasScheme: boolean = raw.indexOf('file://') === 0;
      const normalized: string = hasScheme ? raw : 'file://' + raw;
      logger.debug('MainMenuPage', `封面路径规范化: raw='${raw}', display='${normalized}', source=${type}`);
      return normalized;
    }
    return raw;
  }

  private normalizeDisplayPathForEBook(ebook: EBook): string {
    const raw: string = ebook && ebook.metadata && ebook.metadata.coverImagePath ? ebook.metadata.coverImagePath : '';
    if (raw.length === 0) {
      return '';
    }

    // [修复] 检查是否为资源引用字符串，返回空字符串让调用方使用默认资源
    if (raw.indexOf('app.media.') === 0 || raw.indexOf('$r(') === 0) {
      logger.debug('MainMenuPage', `检测到EBook资源引用字符串，返回空字符串使用默认资源: raw='${raw}'`);
      return '';
    }

    const hasScheme: boolean = raw.indexOf('file://') === 0 || raw.indexOf('http://') === 0 || raw.indexOf('https://') === 0;
    return hasScheme ? raw : 'file://' + raw;
  }

  /**
   * 检查电子书是否有有效封面
   */
  private hasValidEBookCover(ebook: EBook): boolean {
    const raw = ebook?.metadata?.coverImagePath || '';
    return raw.length > 0;
  }

  /**
   * 获取电子书封面图片源
   * 支持本地文件路径、网络URL和应用资源路径
   */
  private getEBookCoverSource(ebook: EBook): ResourceStr {
    const raw = ebook?.metadata?.coverImagePath || '';
    if (raw.length === 0) {
      return $r('app.media.ic_ebook');
    }

    // 检查是否为应用资源路径 (app.media.xxx)
    if (raw.startsWith('app.media.')) {
      // 根据资源名称返回对应的资源引用
      const resourceName = raw.substring('app.media.'.length);
      if (resourceName === 'mangabook') {
        return $r('app.media.mangabook');
      } else if (resourceName === 'ic_ebook') {
        return $r('app.media.ic_ebook');
      } else if (resourceName === 'icon') {
        return $r('app.media.icon');
      }
      // 默认返回电子书图标
      return $r('app.media.ic_ebook');
    }

    // 本地文件路径
    if (raw.startsWith('/')) {
      return `file://${raw}`;
    }

    // 已有协议前缀的路径直接返回
    return raw;
  }

  /**
   * 构建顶部标题栏
   * 悬浮玻璃卡片版，与底栏视觉统一
   */
  @Builder
  buildTopBar() {
    Column() {
      Row() {
        // 标题
        Text(`${this.getPageTitle()}`)
          .fontSize(20)
          .fontWeight(FontWeight.Bold)
          .fontFamily(this.appFontFamily)
          .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_primary', this.themeState.currentTheme))
          .layoutWeight(1)

        // 隐私模式按钮
        Button() {
          SymbolGlyph($r('sys.symbol.key_shield_fill'))
            .fontSize(24)
            .fontColor([this.isPrivacyMode ? 
              ThemeAwareHelper.getTestManagementThemedColor('accent_primary', this.themeState.currentTheme) :
              ThemeAwareHelper.getTestManagementThemedColor('text_primary', this.themeState.currentTheme)])
        }
        .type(ButtonType.Circle)
        .width(40)
        .height(40)
        .backgroundColor(Color.Transparent)
        .onClick(() => {
          this.handlePrivacyModeAuth();
        })
        .margin({ right: 8 })

        // 搜索按钮
        Button() {
          SymbolGlyph($r('sys.symbol.magnifyingglass'))
            .fontSize(24)
            .fontColor([ThemeAwareHelper.getTestManagementThemedColor('text_primary', this.themeState.currentTheme)])
        }
        .type(ButtonType.Circle)
        .width(40)
        .height(40)
        .backgroundColor(Color.Transparent)
        .onClick(() => {
          try {
            this.pathStack.pushPath({ name: 'GlobalSearchPage' });
            logger.info(TAG, '导航到全局搜索页面');
          } catch (error) {
            const message: string = error instanceof Error ? error.message : String(error);
            logger.error(TAG, '导航到搜索页面失败', message);
            this.showToast('打开搜索页面失败');
          }
        })
        .margin({ right: 8 })

        // 更多选项按钮
        Button() {
          SymbolGlyph($r('sys.symbol.ellipsis_circle'))
            .fontSize(24)
            .fontColor([ThemeAwareHelper.getTestManagementThemedColor('text_primary', this.themeState.currentTheme)])
        }
        .type(ButtonType.Circle)
        .width(40)
        .height(40)
        .backgroundColor(Color.Transparent)
        .onClick(() => {
          this.showMoreOptions();
        })

        // 常规模式不需要顶栏位置切换按钮
      }
      .width('100%')
      .height(56)
      .padding({ left: 16, right: 16 })
      .backgroundColor(this.getGlassBackground())
      .backgroundBlurStyle(this.getGlassBlur())
      .borderRadius(this.getGlassRadius())
      .shadow({ radius: this.getGlassRadius(), color: this.getGlassShadowColor() })
      .justifyContent(FlexAlign.SpaceBetween)
      .margin({ left: 12, right: 12 })
      .animation({ duration: 300, curve: Curve.Smooth })
    }
    .width('100%')
    .padding(16)
  }

  /**
   * 平板横屏专用顶栏：第一行为标题与操作，第二行为水平标签按钮
   */
  @Builder
  buildTabletTopBar() {
    Row({ space: 12 }) {
      Text(this.getPageTitle())
        .fontSize(20)
        .fontWeight(FontWeight.Bold)
        .fontFamily(this.appFontFamily)
        .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_primary', this.themeState.currentTheme))
        .layoutWeight(1)

      Row({ space: 8 }) {
        ForEach(this.getVisibleTabConfigs(), (cfg: TabConfig, _idx: number) => {
          this.buildTopBarInlineTabButton(cfg)
        })
      }

      Button() {
        SymbolGlyph($r('sys.symbol.magnifyingglass'))
          .fontSize(24)
          .fontColor([ThemeAwareHelper.getTestManagementThemedColor('text_primary', this.themeState.currentTheme)])
      }
      .type(ButtonType.Circle)
      .width(40)
      .height(40)
      .backgroundColor(Color.Transparent)
      .onClick(() => {
        try {
          this.pathStack.pushPath({ name: 'GlobalSearchPage' });
          logger.info(TAG, '导航到全局搜索页面');
        } catch (error) {
          const message: string = error instanceof Error ? error.message : String(error);
          logger.error(TAG, '导航到搜索页面失败', message);
          this.showToast('打开搜索页面失败');
        }
      })

      Button() {
        SymbolGlyph($r('sys.symbol.ellipsis_circle'))
          .fontSize(24)
          .fontColor([ThemeAwareHelper.getTestManagementThemedColor('text_primary', this.themeState.currentTheme)])
      }
      .type(ButtonType.Circle)
      .width(40)
      .height(40)
      .backgroundColor(Color.Transparent)
      .onClick(() => {
        this.showMoreOptions();
      })

    }
    .width('100%')
    .height(56)
    .padding({ left: 16, right: 16 })
    .backgroundColor(this.getGlassBackground())
    .backgroundBlurStyle(this.getGlassBlur())
    .borderRadius(this.getGlassRadius())
    .shadow({ radius: this.getGlassRadius(), color: this.getGlassShadowColor() })
    .margin({ left: 12, right: 12 })
    .animation({ duration: 300, curve: Curve.Smooth })
  }

  @Builder
  buildTopBarInlineTabButton(config: TabConfig) {
    Column({ space: 2 }) {
      Image(this.currentTabIndex === config.index ? config.selectedIcon : config.icon)
        .width(22)
        .height(22)
        .fillColor(this.currentTabIndex === config.index
          ? ThemeAwareHelper.getTestManagementThemedColor('accent_primary', this.themeState.currentTheme)
          : ThemeAwareHelper.getTestManagementThemedColor('text_secondary', this.themeState.currentTheme))

      Text(config.title)
        .fontSize(11)
        .fontColor(this.currentTabIndex === config.index
          ? ThemeAwareHelper.getTestManagementThemedColor('accent_primary', this.themeState.currentTheme)
          : ThemeAwareHelper.getTestManagementThemedColor('text_secondary', this.themeState.currentTheme))
        .fontWeight(this.currentTabIndex === config.index ? FontWeight.Medium : FontWeight.Normal)
        .maxLines(1)
        .textAlign(TextAlign.Center)
    }
    .width(72)
    .height(44)
    .justifyContent(FlexAlign.Center)
    .onClick(() => { this.handleTabButtonClick(config.index) })
  }

  /**
   * 获取当前页面标题
   */
  private getPageTitle(): string {
    // 如果在书库页面且处于隐私模式，显示"隐私书架"
    if (this.currentTabIndex === TabIndex.LIBRARY && this.isPrivacyMode) {
      return '隐私书架';
    }
    const titles = ['漫匣', '我的书库', '发现', '图源', '设置'];
    return titles[this.currentTabIndex] || '漫画阅读器';
  }


  /**
   * 构建轮播横幅
   */
  @Builder
  buildBannerSwiper() {
    Swiper(this.swiperController) {
      ForEach(this.bannerData, (item: GeneratedTypeLiteralInterface_1, index: number) => {
        Row() {
          Column({ space: this.responsive_isLandscape ? 4 : 8 }) {
            Text(item.title)
              .fontSize(this.responsive_isLandscape ? 18 : 24)
              .fontWeight(FontWeight.Bold)
              .fontFamily(this.appFontFamily)
              .fontColor(Color.White)

            Text(item.subtitle)
              .fontSize(this.responsive_isLandscape ? 13 : 16)
              .fontFamily(this.appFontFamily)
              .fontColor(Color.White)
              .opacity(0.9)
          }
          .alignItems(HorizontalAlign.Start)
          .layoutWeight(1)

          Image(item.image)
            .width(this.responsive_isLandscape ? 60 : 80)
            .height(this.responsive_isLandscape ? 60 : 80)
            .objectFit(ImageFit.Cover)
            .borderRadius(8)
        }
        .width('100%')
        .height(this.responsive_isLandscape ? 80 : 120)
        .padding(this.responsive_isLandscape ? 12 : 16)
        .backgroundColor(item.backgroundColor)
        .borderRadius(12)
      })
    }
    .width('100%')
    .height(this.responsive_isLandscape ? 80 : 120)
    .autoPlay(true)
    .interval(4000)
    .indicator(
      new DotIndicator()
        .itemWidth(8)
        .itemHeight(8)
        .selectedItemWidth(16)
        .selectedItemHeight(8)
        .color(Color.White)
        .selectedColor(Color.White)
    )
    .onChange((index: number) => {
      this.currentBannerIndex = index;
    })
  }

  /**
   * 构建小说入口卡片
   */
  @Builder
  buildNovelEntryCard() {
    Row() {
      Column() {
        Image($r('app.media.legado'))
          .width(50)
          .height(50)
      }
      .width(50)
      .height(50)
      .justifyContent(FlexAlign.Center)
      
      Column() {
        Text('小说阅读')
          .fontSize(16)
          .fontWeight(FontWeight.Medium)
          .fontFamily(this.appFontFamily)
          .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_primary', this.themeState.currentTheme))
        
        Text('支持Legado书源，海量小说资源')
          .fontSize(12)
          .fontFamily(this.appFontFamily)
          .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_secondary', this.themeState.currentTheme))
          .margin({ top: 4 })
      }
      .alignItems(HorizontalAlign.Start)
      .margin({ left: 12 })
      .layoutWeight(1)
      
      SymbolGlyph($r('sys.symbol.chevron_right'))
        .fontSize(20)
        .fontColor([ThemeAwareHelper.getTestManagementThemedColor('text_muted', this.themeState.currentTheme)])
    }
    .width('100%')
    .padding(16)
    .backgroundColor(this.getGlassBackground())
    .backgroundBlurStyle(this.getGlassBlur())
    .borderRadius(this.getGlassRadius())
    .shadow({ radius: this.getGlassRadius(), color: this.getGlassShadowColor(), offsetX: 0, offsetY: 4 })
    .onClick(() => {
      this.pathStack.pushPathByName('NovelBookshelfPage', null);
    })
  }

  /**
   * 构建首页内容
   */
  @Builder
  buildHomeContent() {
    Column({ space: 16 }) {
      // 轮播横幅
      this.buildBannerSwiper()

      // 小说入口卡片
      this.buildNovelEntryCard()

      // 最近阅读
      Column({ space: 12 }) {
        Row() {
          Text('最近阅读')
            .fontSize(18)
            .fontWeight(FontWeight.Medium)
            .fontFamily(this.appFontFamily)
            .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_primary', this.themeState.currentTheme))

          Blank()

          Text('查看全部 >')
            .fontSize(14)
            .fontWeight(FontWeight.Medium)
            .fontFamily(this.appFontFamily)
            .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_secondary', this.themeState.currentTheme))
            .onClick(() => {
              this.currentTabIndex = TabIndex.LIBRARY;
              this.tabsController.changeIndex(this.currentTabIndex);
            })
        }
        .width('100%')

        // 显示真实的阅读记录或空状态
        if (this.isLoadingRecentReading) {
          // 加载中状态
          Row() {
            LoadingProgress()
              .width(24)
              .height(24)
              .color(ThemeAwareHelper.getTestManagementThemedColor('accent_primary', this.themeState.currentTheme))

            Text('加载中...')
              .fontSize(14)
              .fontFamily(this.appFontFamily)
              .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_secondary', this.themeState.currentTheme))
              .margin({ left: 8 })
          }
          .width('100%')
          .height(120)
          .justifyContent(FlexAlign.Center)
          .backgroundColor(this.getGlassBackground())
          .backgroundBlurStyle(this.getGlassBlur())
          .borderRadius(this.getGlassRadius())
          .shadow({ radius: this.getGlassRadius(), color: this.getGlassShadowColor(), offsetX: 0, offsetY: 4 })
        } else if (this.recentReadingList.length === 0) {
          // 空状态
          Column({ space: 8 }) {
            Image($r('app.media.ic_library_empty'))
              .width(48)
              .height(48)
              .fillColor(ThemeAwareHelper.getTestManagementThemedColor('text_muted', this.themeState.currentTheme))

            Text('暂无阅读记录')
              .fontSize(14)
              .fontFamily(this.appFontFamily)
              .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_muted', this.themeState.currentTheme))

            Button('去书库看看')
              .fontSize(14)
              .height(32)
              .fontFamily(this.appFontFamily)
              .backgroundColor(ThemeAwareHelper.getTestManagementThemedColor('accent_primary', this.themeState.currentTheme))
              .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_white', this.themeState.currentTheme))
              .onClick(() => {
                this.currentTabIndex = TabIndex.LIBRARY;
                this.tabsController.changeIndex(this.currentTabIndex);
              })
          }
          .width('100%')
          .height(120)
          .justifyContent(FlexAlign.Center)
          .backgroundColor(this.getGlassBackground())
          .backgroundBlurStyle(this.getGlassBlur())
          .borderRadius(this.getGlassRadius())
          .shadow({ radius: this.getGlassRadius(), color: this.getGlassShadowColor(), offsetX: 0, offsetY: 4 })
        } else {
          // 统一的瀑布流（漫画和电子书混合显示）
          this.buildRecentReadingWaterfall()
        }
      }
      .width('100%')
    }
    .width('100%')
    .padding(16)
  }

  /**
   * 构建多选工具栏
   */
  @Builder
  buildMultiSelectToolbar() {
    Row({ space: 12 }) {
      // 退出多选模式按钮
      Button() {
        SymbolGlyph($r('sys.symbol.xmark'))
          .fontSize(20)
          .fontColor([ThemeAwareHelper.getTestManagementThemedColor('text_primary', this.themeState.currentTheme)])
      }
      .type(ButtonType.Circle)
      .width(40)
      .height(40)
      .backgroundColor(Color.Transparent)
      .onClick(() => {
        this.exitMultiSelectMode();
      })

      // 选中数量显示
      Text(`已选择 ${this.selectedMangaIds.size} 项`)
        .fontSize(16)
        .fontWeight(FontWeight.Medium)
        .fontFamily(this.appFontFamily)
        .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_primary', this.themeState.currentTheme))
        .layoutWeight(1)

      // 全选按钮
      Button('全选')
        .fontSize(14)
        .height(36)
        .fontFamily(this.appFontFamily)
        .backgroundColor(ThemeAwareHelper.getTestManagementThemedColor('button_secondary', this.themeState.currentTheme))
        .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_primary', this.themeState.currentTheme))
        .onClick(() => {
          this.selectAllManga();
        })

      // 删除按钮
      Button('删除')
        .fontSize(14)
        .height(36)
        .fontFamily(this.appFontFamily)
        .backgroundColor(ThemeAwareHelper.getTestManagementThemedColor('button_danger', this.themeState.currentTheme))
        .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_white', this.themeState.currentTheme))
        .onClick(() => {
          this.showBatchDeleteConfirm();
        })
        .enabled(this.selectedMangaIds.size > 0)
    }
    .width('100%')
    .padding({ left: 16, right: 16, top: 12, bottom: 12 })
    .backgroundColor(ThemeAwareHelper.getTestManagementThemedColor('background_secondary', this.themeState.currentTheme))
    .borderRadius(12)
  }

  /**
   * 构建电子书多选工具栏
   */
  @Builder
  buildEBookMultiSelectToolbar() {
    Row({ space: 12 }) {
      // 退出多选模式按钮
      Button() {
        SymbolGlyph($r('sys.symbol.xmark'))
          .fontSize(20)
          .fontColor([ThemeAwareHelper.getTestManagementThemedColor('text_primary', this.themeState.currentTheme)])
      }
      .type(ButtonType.Circle)
      .width(40)
      .height(40)
      .backgroundColor(Color.Transparent)
      .onClick(() => {
        this.exitEBookMultiSelectMode();
      })

      // 选中数量显示
      Text(`已选择 ${this.selectedEBookIds.size} 项`)
        .fontSize(16)
        .fontWeight(FontWeight.Medium)
        .fontFamily(this.appFontFamily)
        .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_primary', this.themeState.currentTheme))
        .layoutWeight(1)

      // 全选按钮
      Button('全选')
        .fontSize(14)
        .height(36)
        .fontFamily(this.appFontFamily)
        .backgroundColor(ThemeAwareHelper.getTestManagementThemedColor('button_secondary', this.themeState.currentTheme))
        .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_primary', this.themeState.currentTheme))
        .onClick(() => {
          this.selectAllEBooks();
        })

      // 删除按钮
      Button('删除')
        .fontSize(14)
        .height(36)
        .fontFamily(this.appFontFamily)
        .backgroundColor(ThemeAwareHelper.getTestManagementThemedColor('button_danger', this.themeState.currentTheme))
        .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_white', this.themeState.currentTheme))
        .onClick(() => {
          this.showEBookBatchDeleteConfirm();
        })
        .enabled(this.selectedEBookIds.size > 0)
    }
    .width('100%')
    .padding({ left: 16, right: 16, top: 12, bottom: 12 })
    .backgroundColor(ThemeAwareHelper.getTestManagementThemedColor('background_secondary', this.themeState.currentTheme))
    .borderRadius(12)
  }

  /**
   * 显示批量删除确认对话框
   */
  private showBatchDeleteConfirmDialog(): void {
    this.getUIContext().showAlertDialog({
      title: '确认删除',
      message: `您确定要删除选中的 ${this.selectedMangaIds.size} 部漫画吗？\n\n此操作将删除这些漫画的所有数据和文件，包括阅读进度、书签等，且不可恢复。`,
      autoCancel: true,
      alignment: DialogAlignment.Center,
      primaryButton: {
        value: '取消',
        action: () => {
          logger.info(TAG, '用户取消批量删除漫画');
        }
      },
      secondaryButton: {
        value: '确认删除',
        fontColor: ThemeAwareHelper.getTestManagementThemedColor('button_danger', this.themeState.currentTheme),
        action: async () => {
          try {
            await this.batchDeleteManga();
          } catch (error) {
            logger.error(TAG, '批量删除漫画失败', String(error));
            this.showToast('删除漫画失败');
          }
        }
      }
    });
  }

  /**
   * 构建书库内容
   */
  @Builder
  buildLibraryContent() {
    // 分类视图模式
    if (this.libraryViewMode === LibraryViewMode.CATEGORY) {
      Column() {
        // 顶部栏：返回按钮（详情模式）或切换按钮（卡片模式）
        Row() {
          if (this.showCategoryDetail) {
            // 详情模式：显示返回按钮和分类名称
            Button() {
              SymbolGlyph($r('sys.symbol.arrow_left'))
                .fontSize(24)
                .fontColor([ThemeAwareHelper.getTestManagementThemedColor('text_primary', this.themeState.currentTheme)])
            }
            .width(44)
            .height(44)
            .backgroundColor(Color.Transparent)
            .onClick(() => {
              // 用动画关闭详情
              animateTo({
                duration: 300,
                curve: Curve.EaseIn
              }, () => {
                this.categoryDetailAnimationProgress = 0;
                this.showCategoryDetail = false;
              });
              setTimeout(() => {
                this.selectedCategoryId = '';
              }, 300);
            })

            Text(this.categoryManager.getCategory(this.selectedCategoryId)?.name || '分类详情')
              .fontSize(18)
              .fontWeight(FontWeight.Bold)
              .fontFamily(this.appFontFamily)
              .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_primary', this.themeState.currentTheme))
              .layoutWeight(1)
          } else {
            // 卡片模式：显示标题
            Text('书架视图')
              .fontSize(18)
              .fontWeight(FontWeight.Bold)
              .fontFamily(this.appFontFamily)
              .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_primary', this.themeState.currentTheme))
              .layoutWeight(1)
          }

          Blank()

          // 切换回网格视图按钮
          Button() {
            SymbolGlyph($r('sys.symbol.book_pages_fill_1'))
              .fontSize(22)
              .fontColor([ThemeAwareHelper.getTestManagementThemedColor('accent_primary', this.themeState.currentTheme)])
          }
          .type(ButtonType.Circle)
          .width(40)
          .height(40)
          .backgroundColor(ThemeAwareHelper.getTestManagementThemedColor('accent_primary_dimmed', this.themeState.currentTheme))
          .onClick(() => {
            this.libraryViewMode = LibraryViewMode.GRID;
            this.showCategoryDetail = false;
            this.selectedCategoryId = '';
            this.saveLibraryViewMode(this.libraryViewMode);
          })
        }
        .width('100%')
        .padding({ top: 8, bottom: 8, left: 16, right: 16 })

        // 内容区域：卡片视图或详情视图
        if (this.showCategoryDetail) {
          // 分类详情视图（在同一Column内显示）
          this.buildCategoryDetailContent()
        } else {
          // 分类卡片视图
          this.buildCategoryView()
        }
      }
      .width('100%')
      .height('100%')
    } else {
    // 非分类视图模式：显示原有书库内容
    Column({ space: 16 }) {
      // 多选工具栏（漫画多选模式时显示）
      if (this.isMultiSelectMode && this.libraryContentType === LibraryContentType.MANGA) {
        this.buildMultiSelectToolbar()
      }

      // 电子书多选工具栏
      if (this.isEBookMultiSelectMode && this.libraryContentType === LibraryContentType.EBOOK) {
        this.buildEBookMultiSelectToolbar()
      }

      // 内容类型切换栏
      if (!this.isMultiSelectMode && !this.isEBookMultiSelectMode && !this.isNovelMultiSelectMode) {
        Row({ space: 12 }) {
            Button('漫画')
              .fontSize(16)
              .height(40)
              .fontFamily(this.appFontFamily)
              .backgroundColor(this.libraryContentType === LibraryContentType.MANGA
                ? ThemeAwareHelper.getTestManagementThemedColor('accent_primary', this.themeState.currentTheme)
                : Color.Transparent)
              .fontColor(this.libraryContentType === LibraryContentType.MANGA
                ? ThemeAwareHelper.getTestManagementThemedColor('text_white', this.themeState.currentTheme)
                : ThemeAwareHelper.getTestManagementThemedColor('text_secondary', this.themeState.currentTheme))
              .onClick(() => {
                this.toggleLibraryContentType(LibraryContentType.MANGA);
              })

            Button('电子书')
              .fontSize(16)
              .height(40)
              .fontFamily(this.appFontFamily)
              .backgroundColor(this.libraryContentType === LibraryContentType.EBOOK
                ? ThemeAwareHelper.getTestManagementThemedColor('accent_primary', this.themeState.currentTheme)
                : Color.Transparent)
              .fontColor(this.libraryContentType === LibraryContentType.EBOOK
                ? ThemeAwareHelper.getTestManagementThemedColor('text_white', this.themeState.currentTheme)
                : ThemeAwareHelper.getTestManagementThemedColor('text_secondary', this.themeState.currentTheme))
              .onClick(() => {
                this.toggleLibraryContentType(LibraryContentType.EBOOK);
              })

            Button('小说')
              .fontSize(16)
              .height(40)
              .fontFamily(this.appFontFamily)
              .backgroundColor(this.libraryContentType === LibraryContentType.NOVEL
                ? ThemeAwareHelper.getTestManagementThemedColor('accent_primary', this.themeState.currentTheme)
                : Color.Transparent)
              .fontColor(this.libraryContentType === LibraryContentType.NOVEL
                ? ThemeAwareHelper.getTestManagementThemedColor('text_white', this.themeState.currentTheme)
                : ThemeAwareHelper.getTestManagementThemedColor('text_secondary', this.themeState.currentTheme))
              .onClick(() => {
                this.toggleLibraryContentType(LibraryContentType.NOVEL);
              })

          Blank()

          // 分类视图切换按钮
          Button() {
            SymbolGlyph($r('sys.symbol.book_pages_fill_1'))
              .fontSize(22)
              .fontColor([ThemeAwareHelper.getTestManagementThemedColor('text_secondary', this.themeState.currentTheme)])
          }
          .type(ButtonType.Circle)
          .width(40)
          .height(40)
          .backgroundColor(Color.Transparent)
          .onClick(() => {
            this.libraryViewMode = LibraryViewMode.CATEGORY;
            this.saveLibraryViewMode(this.libraryViewMode);
          })
        }
        .width('100%')
        .padding({ top: 8, bottom: 8 })
      }

      // 筛选栏
      Row({ space: 12 }) {
        Button('全部')
          .fontSize(14)
          .height(36)
          .fontFamily(this.appFontFamily)
          .type(ButtonType.ROUNDED_RECTANGLE)
          .backgroundColor(this.libraryFilterType === LibraryFilterType.ALL
            ? ThemeAwareHelper.getTestManagementThemedColor('accent_primary', this.themeState.currentTheme)
            : Color.Transparent)
          .fontColor(this.libraryFilterType === LibraryFilterType.ALL
            ? ThemeAwareHelper.getTestManagementThemedColor('text_white', this.themeState.currentTheme)
            : ThemeAwareHelper.getTestManagementThemedColor('text_secondary', this.themeState.currentTheme))
          .onClick(() => {
            this.libraryFilterType = LibraryFilterType.ALL;
            if (this.libraryContentType === LibraryContentType.MANGA) {
              this.applyLibraryFilter();
            } else if (this.libraryContentType === LibraryContentType.NOVEL) {
              this.applyNovelFilter();
            } else {
              this.applyEBookFilter();
            }
          })

        Button('未读')
          .fontSize(14)
          .height(36)
          .fontFamily(this.appFontFamily)
          .type(ButtonType.ROUNDED_RECTANGLE)
          .backgroundColor(this.libraryFilterType === LibraryFilterType.UNREAD
            ? ThemeAwareHelper.getTestManagementThemedColor('accent_primary', this.themeState.currentTheme)
            : Color.Transparent)
          .fontColor(this.libraryFilterType === LibraryFilterType.UNREAD
            ? ThemeAwareHelper.getTestManagementThemedColor('text_white', this.themeState.currentTheme)
            : ThemeAwareHelper.getTestManagementThemedColor('text_secondary', this.themeState.currentTheme))
          .onClick(() => {
            this.libraryFilterType = LibraryFilterType.UNREAD;
            if (this.libraryContentType === LibraryContentType.MANGA) {
              this.applyLibraryFilter();
            } else if (this.libraryContentType === LibraryContentType.NOVEL) {
              this.applyNovelFilter();
            } else {
              this.applyEBookFilter();
            }
          })

        Button('阅读中')
          .fontSize(14)
          .height(36)
          .fontFamily(this.appFontFamily)
          .type(ButtonType.ROUNDED_RECTANGLE)
          .backgroundColor(this.libraryFilterType === LibraryFilterType.READING
            ? ThemeAwareHelper.getTestManagementThemedColor('accent_primary', this.themeState.currentTheme)
            : Color.Transparent)
          .fontColor(this.libraryFilterType === LibraryFilterType.READING
            ? ThemeAwareHelper.getTestManagementThemedColor('text_white', this.themeState.currentTheme)
            : ThemeAwareHelper.getTestManagementThemedColor('text_secondary', this.themeState.currentTheme))
          .onClick(() => {
            this.libraryFilterType = LibraryFilterType.READING;
            if (this.libraryContentType === LibraryContentType.MANGA) {
              this.applyLibraryFilter();
            } else if (this.libraryContentType === LibraryContentType.NOVEL) {
              this.applyNovelFilter();
            } else {
              this.applyEBookFilter();
            }
          })

        Blank()

        // 视图切换按钮（LIST/GRID切换）
        Button() {
          SymbolGlyph(this.libraryViewMode === LibraryViewMode.LIST
            ? $r('sys.symbol.list_bullet')
            : $r('sys.symbol.square_grid_2x2'))
            .fontSize(20)
            .fontColor([ThemeAwareHelper.getTestManagementThemedColor('text_primary', this.themeState.currentTheme)])
        }
        .type(ButtonType.Circle)
        .width(36)
        .height(36)
        .backgroundColor(Color.Transparent)
        .onClick(() => {
          this.toggleLibraryViewMode();
        })

        // 筛选按钮
        Button() {
          SymbolGlyph($r('sys.symbol.slider_vertical_3'))
            .fontSize(20)
            .fontColor([ThemeAwareHelper.getTestManagementThemedColor('text_primary', this.themeState.currentTheme)])
        }
        .type(ButtonType.Circle)
        .width(36)
        .height(36)
        .backgroundColor(Color.Transparent)
        .onClick(() => {
          this.showLibraryFilterPopup = true;
        })
        .bindPopup(this.showLibraryFilterPopup, {
          builder: this.buildLibraryFilterPopup(),
          placement: Placement.Bottom,
          width: '200vp',
          onStateChange: (e) => {
            if (!e.isVisible) {
              this.showLibraryFilterPopup = false;
            }
          }
        })
      }
      .width('100%')

      // 内容列表（根据类型显示漫画或电子书）
      if (this.libraryContentType === LibraryContentType.MANGA) {
        // 漫画列表
        if (this.isLoadingMangaList) {
          // 加载状态
          Column({ space: 16 }) {
            LoadingProgress()
              .width(40)
              .height(40)
              .color(ThemeAwareHelper.getTestManagementThemedColor('accent_primary', this.themeState.currentTheme))

            Text('正在加载漫画列表...')
              .fontSize(14)
              .fontFamily(this.appFontFamily)
              .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_secondary', this.themeState.currentTheme))
          }
          .width('100%')
          .height('100%')
          .justifyContent(FlexAlign.Center)
          .alignItems(HorizontalAlign.Center)
        } else if (this.filteredMangaList.length === 0) {
          // 空状态
          Column({ space: 16 }) {
            Image($r('app.media.ic_library_empty'))
              .width(80)
              .height(80)
              .fillColor(ThemeAwareHelper.getTestManagementThemedColor('text_muted', this.themeState.currentTheme))

            Text(this.mangaList.length === 0 ? '书库为空' : '没有符合条件的漫画')
              .fontSize(16)
              .fontWeight(FontWeight.Medium)
              .fontFamily(this.appFontFamily)
              .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_primary', this.themeState.currentTheme))

            Text(this.mangaList.length === 0 ? '导入一些漫画开始阅读吧' : '尝试更换筛选条件')
              .fontSize(14)
              .fontFamily(this.appFontFamily)
              .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_secondary', this.themeState.currentTheme))

            if (this.mangaList.length === 0) {
              Button('导入漫画')
                .fontSize(14)
                .height(36)
                .fontFamily(this.appFontFamily)
                .backgroundColor(ThemeAwareHelper.getTestManagementThemedColor('accent_primary', this.themeState.currentTheme))
                .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_white', this.themeState.currentTheme))
                .onClick(() => {
                  // 直接导航到数据管理页面
                  this.pathStack.pushPath({ name: 'DataManagementPage' });
                })
            }
          }
          .width('100%')
          .height('100%')
          .justifyContent(FlexAlign.Center)
          .alignItems(HorizontalAlign.Center)
        } else {
          // 漫画列表
          if (this.libraryViewMode === LibraryViewMode.LIST) {
            // 列表视图
            List({ space: 16 }) {
              ForEach(this.filteredMangaList, (manga: Manga, index: number) => {
                ListItem() {
                  this.buildMangaCard(manga)
                }
              })
            }
            .width('100%')
            .layoutWeight(1)
            .padding({ left: 16, right: 16, top: 16 })
            .scrollBar(BarState.Auto)
            .edgeEffect(EdgeEffect.Spring)
          } else {
            // 网格视图（响应式）
            List() {
              ListItem() {
                Column() {
                  this.buildLibraryMangaGridContent();
                }
                .width('100%')
              }
            }
            .width('100%')
            .layoutWeight(1)
            .scrollBar(BarState.Auto)
            .edgeEffect(EdgeEffect.Spring)
          }
        }
      } else if (this.libraryContentType === LibraryContentType.EBOOK) {
        // 电子书列表
        if (this.isLoadingEbookList) {
          // 加载状态
          Column({ space: 16 }) {
            LoadingProgress()
              .width(40)
              .height(40)
              .color(ThemeAwareHelper.getTestManagementThemedColor('accent_primary', this.themeState.currentTheme))

            Text('正在加载电子书列表...')
              .fontSize(14)
              .fontFamily(this.appFontFamily)
              .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_secondary', this.themeState.currentTheme))
          }
          .width('100%')
          .height('100%')
          .justifyContent(FlexAlign.Center)
          .alignItems(HorizontalAlign.Center)
        } else if (this.filteredEbookList.length === 0 && this.filteredPdfEbookList.length === 0) {
          // 空状态
          Column({ space: 16 }) {
            Image($r('app.media.ic_library_empty'))
              .width(80)
              .height(80)
              .fillColor(ThemeAwareHelper.getTestManagementThemedColor('text_muted', this.themeState.currentTheme))

            Text((this.ebookList.length === 0 && this.pdfEbookList.length === 0) ? '电子书库为空' : '没有符合条件的电子书')
              .fontSize(16)
              .fontWeight(FontWeight.Medium)
              .fontFamily(this.appFontFamily)
              .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_primary', this.themeState.currentTheme))

            Text((this.ebookList.length === 0 && this.pdfEbookList.length === 0) ? '导入一些电子书开始阅读吧' : '尝试更换筛选条件')
              .fontSize(14)
              .fontFamily(this.appFontFamily)
              .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_secondary', this.themeState.currentTheme))

            if (this.ebookList.length === 0 && this.pdfEbookList.length === 0) {
              Button('导入电子书')
                .fontSize(14)
                .height(36)
                .fontFamily(this.appFontFamily)
                .backgroundColor(ThemeAwareHelper.getTestManagementThemedColor('accent_primary', this.themeState.currentTheme))
                .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_white', this.themeState.currentTheme))
                .onClick(() => {
                  // 直接导航到数据管理页面
                  this.pathStack.pushPath({ name: 'DataManagementPage' });
                })
            }
          }
          .width('100%')
          .height('100%')
          .justifyContent(FlexAlign.Center)
          .alignItems(HorizontalAlign.Center)
        } else {
          // 电子书列表（包括普通电子书和PDF电子书）
          if (this.libraryViewMode === LibraryViewMode.LIST) {
            // 列表视图
            List({ space: 16 }) {
              // 普通电子书
              ForEach(this.filteredEbookList, (ebook: EBook, index: number) => {
                ListItem() {
                  this.buildEBookCard(ebook)
                }
              })
              // PDF电子书（使用漫画卡片样式，但点击时使用漫画阅读器）
              ForEach(this.filteredPdfEbookList, (manga: Manga, index: number) => {
                ListItem() {
                  this.buildPdfEBookCard(manga)
                }
              })
            }
            .width('100%')
            .layoutWeight(1)
            .scrollBar(BarState.Auto)
            .edgeEffect(EdgeEffect.Spring)
          } else {
            // 网格视图（响应式）
            Grid() {
              // 普通电子书
              ForEach(this.filteredEbookList, (ebook: EBook, index: number) => {
                GridItem() {
                  this.buildEBookGridCard(ebook)
                }
              })
              // PDF电子书（使用漫画卡片样式，但点击时使用漫画阅读器）
              ForEach(this.filteredPdfEbookList, (manga: Manga, index: number) => {
                GridItem() {
                  this.buildPdfEBookGridCard(manga)
                }
              })
            }
            .columnsTemplate(this.getLibraryGridColumnsTemplate())
            .columnsGap(this.responsive_gridGap)
            .rowsGap(this.responsive_gridGap)
            .width('100%')
            .layoutWeight(1)
            .scrollBar(BarState.Auto)
            .edgeEffect(EdgeEffect.Spring)
          }
        }
      } else if (this.libraryContentType === LibraryContentType.NOVEL) {
        // 小说列表
        if (this.isLoadingNovelList) {
          // 加载状态
          Column({ space: 16 }) {
            LoadingProgress()
              .width(40)
              .height(40)
              .color(ThemeAwareHelper.getTestManagementThemedColor('accent_primary', this.themeState.currentTheme))

            Text('正在加载小说列表...')
              .fontSize(14)
              .fontFamily(this.appFontFamily)
              .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_secondary', this.themeState.currentTheme))
          }
          .width('100%')
          .height('100%')
          .justifyContent(FlexAlign.Center)
          .alignItems(HorizontalAlign.Center)
        } else if (this.filteredNovelList.length === 0) {
          // 空状态
          Column({ space: 16 }) {
            Image($r('app.media.ic_library_empty'))
              .width(80)
              .height(80)
              .fillColor(ThemeAwareHelper.getTestManagementThemedColor('text_muted', this.themeState.currentTheme))

            Text(this.novelList.length === 0 ? '小说书架为空' : '没有符合条件的小说')
              .fontSize(16)
              .fontWeight(FontWeight.Medium)
              .fontFamily(this.appFontFamily)
              .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_primary', this.themeState.currentTheme))

            Text(this.novelList.length === 0 ? '去小说书架添加一些小说吧' : '尝试更换筛选条件')
              .fontSize(14)
              .fontFamily(this.appFontFamily)
              .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_secondary', this.themeState.currentTheme))

            if (this.novelList.length === 0) {
              Button('前往小说书架')
                .fontSize(14)
                .height(36)
                .fontFamily(this.appFontFamily)
                .backgroundColor(ThemeAwareHelper.getTestManagementThemedColor('accent_primary', this.themeState.currentTheme))
                .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_white', this.themeState.currentTheme))
                .onClick(() => {
                  this.pathStack.pushPathByName('NovelBookshelfPage', null);
                })
            }
          }
          .width('100%')
          .height('100%')
          .justifyContent(FlexAlign.Center)
          .alignItems(HorizontalAlign.Center)
        } else {
          // 小说列表
          if (this.libraryViewMode === LibraryViewMode.LIST) {
            // 列表视图
            List({ space: 16 }) {
              ForEach(this.filteredNovelList, (novel: NovelBook, index: number) => {
                ListItem() {
                  this.buildNovelCard(novel)
                }
              })
            }
            .width('100%')
            .layoutWeight(1)
            .scrollBar(BarState.Auto)
            .edgeEffect(EdgeEffect.Spring)
          } else {
            // 网格视图（响应式）
            Grid() {
              ForEach(this.filteredNovelList, (novel: NovelBook, index: number) => {
                GridItem() {
                  this.buildNovelGridCard(novel)
                }
              }, (novel: NovelBook) => novel.id)
            }
            .columnsTemplate(this.getLibraryGridColumnsTemplate())
            .columnsGap(this.responsive_gridGap)
            .rowsGap(this.responsive_gridGap)
            .width('100%')
            .layoutWeight(1)
            .scrollBar(BarState.Auto)
            .edgeEffect(EdgeEffect.Spring)
          }
        }
      }

    }
    .width('100%')
    .height('100%')
    .padding({ left: 16, right: 16, top: 16, bottom: 16 })
    }
  }

  /**
   * 构建漫画卡片
   */
  @Builder
  buildMangaCard(manga: Manga) {
    Stack() {
      // 右侧删除提示面板
      Column() {
        Text(this.getSwipeProgressText(manga.id))
          .fontSize(14)
          .fontWeight(FontWeight.Medium)
          .fontFamily(this.appFontFamily)
          .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_white', this.themeState.currentTheme))
        Text('松手删除')
          .fontSize(12)
          .fontFamily(this.appFontFamily)
          .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_white', this.themeState.currentTheme))
      }
      .width(96)
      .height('100%')
      .justifyContent(FlexAlign.Center)
      .alignItems(HorizontalAlign.Center)
      .backgroundColor(ThemeAwareHelper.getTestManagementThemedColor('button_danger', this.themeState.currentTheme))
      .borderRadius(this.getGlassRadius())
      .opacity(this.activeSwipeId === manga.id ? Math.min(1, this.getItemSwipeOffset(manga.id) / this.swipeThreshold) : 0.15)
      .position({ x: '100%', y: 0 })

      // 卡片内容层
      Row({ space: 12 }) {
        Image(this.normalizeDisplayPathForManga(manga) || $r('app.media.mangabook'))
          .width(80)
          .height(120)
          .objectFit(ImageFit.Contain)
          .backgroundColor(Color.Transparent)
          .borderRadius(8)
          .shadow({ radius: 8, color: '#1F000000', offsetY: 4 })
          .onError(() => {
            logger.warn('MainMenuPage', `书库列表封面加载失败: raw='${manga.coverImagePath}', display='${this.normalizeDisplayPathForManga(manga)}', source=${manga.coverSourceType}`);
          })
          .id(`cover_manga_lib_${manga.id}`)

        Column({ space: 8 }) {
          // 漫画标题
          Text(manga.title)
            .fontSize(16)
            .fontWeight(FontWeight.Medium)
            .fontFamily(this.appFontFamily)
            .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_primary', this.themeState.currentTheme))
            .maxLines(2)
            .textOverflow({ overflow: TextOverflow.Ellipsis })

          // 漫画章节数和状态
          Text(`${manga.chapters.length}话 · ${StatusConverter.mangaStatusToDisplayText(manga.status)}`)
            .fontSize(14)
            .fontFamily(this.appFontFamily)
            .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_secondary', this.themeState.currentTheme))

          // 阅读进度信息（仅显示章节名称和页数，不显示进度条）
          if (manga.readingProgress && (manga.readingProgress.currentChapterId || manga.readingProgress.currentPageIndex > 0)) {
            Text(this.getMangaReadingProgressText(manga))
              .fontSize(12)
              .fontFamily(this.appFontFamily)
              .fontColor(ThemeAwareHelper.getTestManagementThemedColor('accent_primary', this.themeState.currentTheme))
              .maxLines(1)
              .textOverflow({ overflow: TextOverflow.Ellipsis })
          }

          // 漫画描述
          Text(manga.description)
            .fontSize(12)
            .fontFamily(this.appFontFamily)
            .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_muted', this.themeState.currentTheme))
            .maxLines(2)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
        }
        .layoutWeight(1)
        .alignItems(HorizontalAlign.Start)
        .justifyContent(FlexAlign.SpaceBetween)
      }
      .translate({ x: -this.getItemSwipeOffset(manga.id), y: 0 })
      .onClick(() => { this.openMangaDetail(manga); })
      .width('100%')
      .height(140)
      .padding(12)
      .backgroundColor(this.getGlassBackground())
      .backgroundBlurStyle(this.getGlassBlur())
      .borderRadius(this.getGlassRadius())
      .shadow({ radius: this.getGlassRadius(), color: this.getGlassShadowColor(), offsetY: 2 })
      .gesture(
        GestureGroup(GestureMode.Parallel,
          LongPressGesture({ repeat: false })
            .onAction(() => { this.activateSwipeFor(manga.id); }),
          PanGesture({ fingers: 1, direction: PanDirection.Left, distance: 1 })
            .onActionUpdate((event: GestureEvent) => { this.updateSwipeOffset(manga.id, event); })
            .onActionEnd((event: GestureEvent) => { this.endSwipe(manga.id); })
        )
      )
    }
    .width('100%')
    .height(140)
  }

  /**
   * 构建分类视图（类似iOS App Library）
   */
  @Builder
  buildCategoryView() {
    Column({ space: 16 }) {
      // 编辑模式切换栏
      Row() {
        Text(this.isCategoryEditMode ? '拖动分类进行排序' : '分类书架')
          .fontSize(16)
          .fontWeight(FontWeight.Medium)
          .fontFamily(this.appFontFamily)
          .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_primary', this.themeState.currentTheme))
        
        Blank()
        
        Button(this.isCategoryEditMode ? '完成' : '编辑')
          .fontSize(14)
          .height(32)
          .fontFamily(this.appFontFamily)
          .backgroundColor(this.isCategoryEditMode
            ? ThemeAwareHelper.getTestManagementThemedColor('accent_primary', this.themeState.currentTheme)
            : Color.Transparent)
          .fontColor(this.isCategoryEditMode
            ? Color.White
            : ThemeAwareHelper.getTestManagementThemedColor('accent_primary', this.themeState.currentTheme))
          .onClick(() => {
            this.isCategoryEditMode = !this.isCategoryEditMode;
          })
      }
      .width('100%')
      .padding({ left: 16, right: 16, top: 8 })

      // 分类网格（使用Scroll包裹实现丝滑滚动和回弹）
      Scroll() {
        Grid() {
          ForEach(this.bookshelfCategories, (category: BookshelfCategory, index: number) => {
            GridItem() {
              this.buildCategoryCard(category)
            }
          }, (category: BookshelfCategory) => category.id)
          
          // 添加新分类按钮（非编辑模式时显示）
          if (!this.isCategoryEditMode) {
            GridItem() {
              this.buildAddCategoryCard()
            }
          }
        }
        .columnsTemplate('1fr 1fr')
        .rowsGap(16)
        .columnsGap(16)
        .width('100%')
        .padding({ left: 16, right: 16, top: 8, bottom: 16 })
        .editMode(this.isCategoryEditMode)
        .onItemDragStart((event: ItemDragInfo, itemIndex: number) => {
          if (itemIndex < this.bookshelfCategories.length) {
            this.draggingCategoryId = this.bookshelfCategories[itemIndex].id;
          }
          return this.buildDraggingCategoryCard();
        })
        .onItemDrop((event: ItemDragInfo, itemIndex: number, insertIndex: number, isSuccess: boolean) => {
          if (isSuccess && itemIndex !== insertIndex && itemIndex < this.bookshelfCategories.length) {
            // 直接在数组中移动元素
            const temp = this.bookshelfCategories.splice(itemIndex, 1);
            this.bookshelfCategories.splice(insertIndex, 0, temp[0]);
            // 更新所有分类的order属性
            this.bookshelfCategories.forEach((cat, idx) => {
              cat.order = idx;
            });
            // 保存到持久化存储
            this.categoryManager.reorderCategories(this.bookshelfCategories);
          }
          this.draggingCategoryId = '';
        })
      }
      .scrollBar(BarState.Off)
      .edgeEffect(EdgeEffect.Spring)
      .friction(0.6)
      .width('100%')
      .layoutWeight(1)
    }
    .width('100%')
    .layoutWeight(1)
  }

  /**
   * 构建拖动中的分类卡片预览
   */
  @Builder
  buildDraggingCategoryCard() {
    Column()
      .width(120)
      .height(120)
      .backgroundColor(ThemeAwareHelper.getTestManagementThemedColor('accent_primary', this.themeState.currentTheme))
      .borderRadius(20)
      .opacity(0.8)
  }

  /**
   * 构建分类卡片（书架样式）
   */
  @Builder
  buildCategoryCard(category: BookshelfCategory) {
    Column({ space: 4 }) {
      // 书架容器
      Stack({ alignContent: Alignment.Bottom }) {
        // 书架背景图片
        Image($r('app.media.bookshelf'))
          .width('100%')
          .height(40)
          .objectFit(ImageFit.Fill)
        
        // 书本封面排列（在书架上方，向上偏移）
        if (this.getCategoryItemCount(category) > 0 && this.getCategoryCoverImages(category).length > 0) {
          // 有内容：中间大两边小的布局
          Row({ space: 2 }) {
            ForEach(this.getCategoryCoverImages(category), (coverPath: string, index: number) => {
              Image(this.normalizeCoverPath(coverPath))
                .width(index === 0 ? 40 : 30)
                .height(index === 0 ? 56 : 42)
                .objectFit(ImageFit.Cover)
                .borderRadius(2)
                .shadow({ radius: 3, color: 'rgba(0, 0, 0, 0.4)', offsetX: 1, offsetY: 2 })
                .zIndex(index === 0 ? 10 : 5)
            }, (cover: string, index: number) => `${category.id}_cover_${index}`)
          }
          .justifyContent(FlexAlign.Center)
          .alignItems(VerticalAlign.Bottom)
          .width('100%')
          .offset({ y: -28 })
        } else {
          // 空状态：显示"空无一物"提示（向上偏移）
          Text('空无一物')
            .fontSize(24)
            .fontFamily(this.appFontFamily)
            .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_secondary', this.themeState.currentTheme))
            .offset({ y: -30 })
        }
      }
      .width('100%')
      .height(70)
      
      // 分类名称和数量
      Column({ space: 2 }) {
        Text(category.name)
          .fontSize(14)
          .fontWeight(FontWeight.Medium)
          .fontFamily(this.appFontFamily)
          .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_primary', this.themeState.currentTheme))
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
        
        Text(`${this.getCategoryItemCount(category)} 项`)
          .fontSize(12)
          .fontFamily(this.appFontFamily)
          .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_secondary', this.themeState.currentTheme))
      }
      .alignItems(HorizontalAlign.Center)
    }
    .width('100%')
    .onClick(() => {
      // 先设置选中的分类ID，然后用动画展开详情
      this.selectedCategoryId = category.id;
      animateTo({
        duration: 300,
        curve: Curve.EaseOut
      }, () => {
        this.showCategoryDetail = true;
        this.categoryDetailAnimationProgress = 1;
      });
    })
    .gesture(
      LongPressGesture({ repeat: false, duration: 500 })
        .onAction(() => {
          // 长按编辑分类
          if (!category.isDefault) {
            this.editingCategory = category;
            this.newCategoryName = category.name;
            animateTo({ duration: 200, curve: Curve.EaseOut }, () => {
              this.showEditCategoryDialog = true;
            });
          }
        })
    )
  }

  /**
   * 构建添加分类卡片
   */
  @Builder
  buildAddCategoryCard() {
    Column({ space: 4 }) {
      // 书架容器（与分类卡片保持一致）
      Stack({ alignContent: Alignment.Bottom }) {
        // 书架背景图片
        Image($r('app.media.bookshelf'))
          .width('100%')
          .height(40)
          .objectFit(ImageFit.Fill)
        
        // 添加图标和提示文字
        Column({ space: 4 }) {
          SymbolGlyph($r('sys.symbol.plus_square'))
            .fontSize(28)
            .fontColor([ThemeAwareHelper.getTestManagementThemedColor('text_secondary', this.themeState.currentTheme)])
          Text('新建分类')
            .fontSize(12)
            .fontFamily(this.appFontFamily)
            .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_secondary', this.themeState.currentTheme))
        }
        .offset({ y: -20 })
      }
      .width('100%')
      .height(70)
      
      // 占位（与分类卡片保持一致的高度）
      Column()
        .height(36)
    }
    .width('100%')
    .onClick(() => {
      this.newCategoryName = '';
      animateTo({ duration: 200, curve: Curve.EaseOut }, () => {
        this.showCreateCategoryDialog = true;
      });
    })
  }

  /**
   * 获取分类内容数量（默认分类显示所有未分类的内容）
   */
  private getCategoryItemCount(category: BookshelfCategory): number {
    if (category.isDefault) {
      // 默认分类：显示所有内容的数量（漫画+电子书+小说）
      return this.mangaList.length + this.ebookList.length + this.pdfEbookList.length + this.novelList.length;
    }
    // 其他分类：使用categoryManager中的映射计数
    return category.itemCount;
  }

  /**
   * 标准化封面路径（处理本地文件、网络URL、媒体资源等）
   */
  private normalizeCoverPath(coverPath: string): string {
    if (!coverPath) {
      return '';
    }
    // 网络URL直接返回
    if (coverPath.startsWith('http://') || coverPath.startsWith('https://')) {
      return coverPath;
    }
    // 已经是file://格式
    if (coverPath.startsWith('file://')) {
      return coverPath;
    }
    // 本地文件路径添加file://前缀
    return `file://${coverPath}`;
  }

  /**
   * 获取分类的封面图片列表（默认分类从实际内容获取）
   */
  private getCategoryCoverImages(category: BookshelfCategory): string[] {
    if (category.isDefault) {
      // 默认分类：从实际内容列表获取封面（使用已标准化的路径）
      const covers: string[] = [];
      // 从漫画获取封面
      for (const manga of this.mangaList) {
        if (covers.length >= 3) break;
        const normalizedPath = this.normalizeDisplayPathForManga(manga);
        if (normalizedPath) {
          covers.push(normalizedPath);
        }
      }
      // 从电子书获取封面
      for (const ebook of this.ebookList) {
        if (covers.length >= 3) break;
        const normalizedPath = this.normalizeDisplayPathForEBook(ebook);
        if (normalizedPath) {
          covers.push(normalizedPath);
        }
      }
      // 从小说获取封面（优先使用本地缓存路径）
      for (const novel of this.novelList) {
        if (covers.length >= 3) break;
        const coverPath = novel.coverLocalPath || novel.coverUrl;
        if (coverPath) {
          covers.push(coverPath);
        }
      }
      return covers;
    }
    // 其他分类：使用category中存储的封面
    return category.coverImages || [];
  }

  /**
   * 刷新分类列表
   */
  private async refreshCategories(): Promise<void> {
    this.bookshelfCategories = this.categoryManager.getCategories();
  }

  /**
   * 创建新分类
   */
  private async createNewCategory(): Promise<void> {
    if (this.newCategoryName.trim().length > 0) {
      await this.categoryManager.createCategory(this.newCategoryName.trim());
      await this.refreshCategories();
      this.showCreateCategoryDialog = false;
      this.newCategoryName = '';
    }
  }

  /**
   * 更新分类名称
   */
  private async updateCategoryName(): Promise<void> {
    if (this.editingCategory && this.newCategoryName.trim().length > 0) {
      await this.categoryManager.updateCategoryName(this.editingCategory.id, this.newCategoryName.trim());
      await this.refreshCategories();
      this.showEditCategoryDialog = false;
      this.editingCategory = null;
      this.newCategoryName = '';
    }
  }

  /**
   * 删除分类
   */
  private async deleteCategory(categoryId: string): Promise<void> {
    await this.categoryManager.deleteCategory(categoryId);
    await this.refreshCategories();
    this.showEditCategoryDialog = false;
    this.editingCategory = null;
  }

  /**
   * 构建创建分类对话框
   */
  @Builder
  buildCreateCategoryDialog() {
    Column() {
      Column({ space: 16 }) {
        Text('新建分类')
          .fontSize(18)
          .fontWeight(FontWeight.Bold)
          .fontFamily(this.appFontFamily)
          .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_primary', this.themeState.currentTheme))

        TextInput({ placeholder: '输入分类名称', text: this.newCategoryName })
          .width('100%')
          .height(44)
          .fontFamily(this.appFontFamily)
          .backgroundColor(ThemeAwareHelper.getTestManagementThemedColor('background_secondary', this.themeState.currentTheme))
          .borderRadius(8)
          .onChange((value: string) => {
            this.newCategoryName = value;
          })

        Row({ space: 12 }) {
          Button('取消')
            .layoutWeight(1)
            .height(44)
            .fontFamily(this.appFontFamily)
            .backgroundColor(ThemeAwareHelper.getTestManagementThemedColor('background_secondary', this.themeState.currentTheme))
            .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_primary', this.themeState.currentTheme))
            .onClick(() => {
              animateTo({ duration: 200, curve: Curve.EaseOut }, () => {
                this.showCreateCategoryDialog = false;
                this.newCategoryName = '';
              });
            })

          Button('创建')
            .layoutWeight(1)
            .height(44)
            .fontFamily(this.appFontFamily)
            .backgroundColor(ThemeAwareHelper.getTestManagementThemedColor('accent_primary', this.themeState.currentTheme))
            .fontColor(Color.White)
            .enabled(this.newCategoryName.trim().length > 0)
            .onClick(() => {
              this.createNewCategory();
            })
        }
        .width('100%')
      }
      .width('85%')
      .padding(20)
      .backgroundColor(ThemeAwareHelper.getTestManagementThemedColor('panel_background', this.themeState.currentTheme))
      .borderRadius(16)
      .shadow({ radius: 20, color: 'rgba(0, 0, 0, 0.3)', offsetY: 4 })
    }
    .width('100%')
    .height('100%')
    .justifyContent(FlexAlign.Center)
    .onClick(() => {
      animateTo({ duration: 200, curve: Curve.EaseOut }, () => {
        this.showCreateCategoryDialog = false;
        this.newCategoryName = '';
      });
    })
    .transition(TransitionEffect.OPACITY.animation({ duration: 200, curve: Curve.EaseOut }))
  }

  /**
   * 构建编辑分类对话框
   */
  @Builder
  buildEditCategoryDialog() {
    Column() {
      Column({ space: 16 }) {
        Text('编辑分类')
          .fontSize(18)
          .fontWeight(FontWeight.Bold)
          .fontFamily(this.appFontFamily)
          .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_primary', this.themeState.currentTheme))

        TextInput({ placeholder: '输入分类名称', text: this.newCategoryName })
          .width('100%')
          .height(44)
          .fontFamily(this.appFontFamily)
          .backgroundColor(ThemeAwareHelper.getTestManagementThemedColor('background_secondary', this.themeState.currentTheme))
          .borderRadius(8)
          .onChange((value: string) => {
            this.newCategoryName = value;
          })

        Row({ space: 12 }) {
          Button('删除')
            .layoutWeight(1)
            .height(44)
            .fontFamily(this.appFontFamily)
            .backgroundColor('#FF3B30')
            .fontColor(Color.White)
            .onClick(() => {
              if (this.editingCategory) {
                this.deleteCategory(this.editingCategory.id);
              }
            })

          Button('取消')
            .layoutWeight(1)
            .height(44)
            .fontFamily(this.appFontFamily)
            .backgroundColor(ThemeAwareHelper.getTestManagementThemedColor('background_secondary', this.themeState.currentTheme))
            .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_primary', this.themeState.currentTheme))
            .onClick(() => {
              animateTo({ duration: 200, curve: Curve.EaseOut }, () => {
                this.showEditCategoryDialog = false;
                this.editingCategory = null;
                this.newCategoryName = '';
              });
            })

          Button('保存')
            .layoutWeight(1)
            .height(44)
            .fontFamily(this.appFontFamily)
            .backgroundColor(ThemeAwareHelper.getTestManagementThemedColor('accent_primary', this.themeState.currentTheme))
            .fontColor(Color.White)
            .enabled(this.newCategoryName.trim().length > 0)
            .onClick(() => {
              this.updateCategoryName();
            })
        }
        .width('100%')
      }
      .width('85%')
      .padding(20)
      .backgroundColor(ThemeAwareHelper.getTestManagementThemedColor('panel_background', this.themeState.currentTheme))
      .borderRadius(16)
      .shadow({ radius: 20, color: 'rgba(0, 0, 0, 0.3)', offsetY: 4 })
    }
    .width('100%')
    .height('100%')
    .justifyContent(FlexAlign.Center)
    .transition(TransitionEffect.OPACITY.animation({ duration: 200, curve: Curve.EaseOut }))
  }

  /**
   * 构建分类详情内容（在同一Column内显示，不使用覆盖层）
   */
  @Builder
  buildCategoryDetailContent() {
    Column() {
      // 筛选栏（全部 + 内容类型切换）
      Row({ space: 8 }) {
        Button('全部')
          .fontSize(14)
          .height(32)
          .fontFamily(this.appFontFamily)
          .backgroundColor(this.libraryFilterType === LibraryFilterType.ALL
            ? ThemeAwareHelper.getTestManagementThemedColor('accent_primary', this.themeState.currentTheme)
            : Color.Transparent)
          .fontColor(this.libraryFilterType === LibraryFilterType.ALL
            ? Color.White
            : ThemeAwareHelper.getTestManagementThemedColor('text_secondary', this.themeState.currentTheme))
          .onClick(() => {
            this.libraryFilterType = LibraryFilterType.ALL;
          })

        Column()
          .width(1)
          .height(20)
          .backgroundColor(ThemeAwareHelper.getTestManagementThemedColor('panel_border', this.themeState.currentTheme))

        Button('漫画')
          .fontSize(14)
          .height(32)
          .fontFamily(this.appFontFamily)
          .backgroundColor(this.libraryContentType === LibraryContentType.MANGA
            ? ThemeAwareHelper.getTestManagementThemedColor('accent_primary', this.themeState.currentTheme)
            : Color.Transparent)
          .fontColor(this.libraryContentType === LibraryContentType.MANGA
            ? Color.White
            : ThemeAwareHelper.getTestManagementThemedColor('text_secondary', this.themeState.currentTheme))
          .onClick(() => {
            this.libraryContentType = LibraryContentType.MANGA;
          })

        Button('电子书')
          .fontSize(14)
          .height(32)
          .fontFamily(this.appFontFamily)
          .backgroundColor(this.libraryContentType === LibraryContentType.EBOOK
            ? ThemeAwareHelper.getTestManagementThemedColor('accent_primary', this.themeState.currentTheme)
            : Color.Transparent)
          .fontColor(this.libraryContentType === LibraryContentType.EBOOK
            ? Color.White
            : ThemeAwareHelper.getTestManagementThemedColor('text_secondary', this.themeState.currentTheme))
          .onClick(() => {
            this.libraryContentType = LibraryContentType.EBOOK;
          })

        Button('小说')
          .fontSize(14)
          .height(32)
          .backgroundColor(this.libraryContentType === LibraryContentType.NOVEL
            ? ThemeAwareHelper.getTestManagementThemedColor('accent_primary', this.themeState.currentTheme)
            : Color.Transparent)
          .fontColor(this.libraryContentType === LibraryContentType.NOVEL
            ? Color.White
            : ThemeAwareHelper.getTestManagementThemedColor('text_secondary', this.themeState.currentTheme))
          .onClick(() => {
            this.libraryContentType = LibraryContentType.NOVEL;
          })

        Blank()
      }
      .width('100%')
      .padding({ left: 16, right: 16, bottom: 8 })

      // 内容列表（使用Swiper实现横向滑动切换内容类型）
      Swiper() {
        // 漫画内容
        Scroll() {
          Column() {
            this.buildCategoryMangaList()
          }
          .width('100%')
        }
        .width('100%')
        .height('100%')
        .scrollBar(BarState.Off)
        .edgeEffect(EdgeEffect.Spring)
        .friction(0.6)

        // 电子书内容
        Scroll() {
          Column() {
            this.buildCategoryEBookList()
          }
          .width('100%')
        }
        .width('100%')
        .height('100%')
        .scrollBar(BarState.Off)
        .edgeEffect(EdgeEffect.Spring)
        .friction(0.6)

        // 小说内容
        Scroll() {
          Column() {
            this.buildCategoryNovelList()
          }
          .width('100%')
        }
        .width('100%')
        .height('100%')
        .scrollBar(BarState.Off)
        .edgeEffect(EdgeEffect.Spring)
        .friction(0.6)
      }
      .index(this.libraryContentType === LibraryContentType.MANGA ? 0 :
        (this.libraryContentType === LibraryContentType.EBOOK ? 1 : 2))
      .indicator(false)
      .loop(false)
      .layoutWeight(1)
      .onChange((index: number) => {
        // 滑动切换内容类型
        if (index === 0) {
          this.libraryContentType = LibraryContentType.MANGA;
        } else if (index === 1) {
          this.libraryContentType = LibraryContentType.EBOOK;
        } else {
          this.libraryContentType = LibraryContentType.NOVEL;
        }
      })
    }
    .width('100%')
    .layoutWeight(1)
  }

  /**
   * 构建分类漫画列表
   */
  @Builder
  buildCategoryMangaList() {
    Grid() {
      ForEach(this.filteredMangaList.filter((manga: Manga) => {
        return this.categoryManager.isItemInCategory(manga.id, ContentType.MANGA, this.selectedCategoryId) ||
          (this.selectedCategoryId === 'default' && this.categoryManager.getUncategorizedItemKey(manga.id, ContentType.MANGA));
      }), (manga: Manga) => {
        GridItem() {
          this.buildMangaGridCard(manga)
        }
      }, (manga: Manga) => manga.id)
    }
    .columnsTemplate(this.getLibraryGridColumnsTemplate())
    .rowsGap(this.responsive_gridGap)
    .columnsGap(this.responsive_gridGap)
    .width('100%')
    .padding(16)
  }

  /**
   * 构建分类电子书列表
   */
  @Builder
  buildCategoryEBookList() {
    Grid() {
      ForEach(this.filteredEbookList.filter((ebook: EBook) => {
        return this.categoryManager.isItemInCategory(ebook.id, ContentType.EBOOK, this.selectedCategoryId) ||
          (this.selectedCategoryId === 'default' && this.categoryManager.getUncategorizedItemKey(ebook.id, ContentType.EBOOK));
      }), (ebook: EBook) => {
        GridItem() {
          this.buildEBookGridCard(ebook)
        }
      }, (ebook: EBook) => ebook.id)
    }
    .columnsTemplate(this.getLibraryGridColumnsTemplate())
    .rowsGap(this.responsive_gridGap)
    .columnsGap(this.responsive_gridGap)
    .width('100%')
    .padding(16)
  }

  /**
   * 构建分类小说列表
   */
  @Builder
  buildCategoryNovelList() {
    Grid() {
      ForEach(this.filteredNovelList.filter((novel: NovelBook) => {
        return this.categoryManager.isItemInCategory(novel.id, ContentType.NOVEL, this.selectedCategoryId) ||
          (this.selectedCategoryId === 'default' && this.categoryManager.getUncategorizedItemKey(novel.id, ContentType.NOVEL));
      }), (novel: NovelBook) => {
        GridItem() {
          this.buildNovelGridCard(novel)
        }
      }, (novel: NovelBook) => novel.id)
    }
    .columnsTemplate(this.getLibraryGridColumnsTemplate())
    .rowsGap(this.responsive_gridGap)
    .columnsGap(this.responsive_gridGap)
    .width('100%')
    .padding(16)
  }

  /**
   * 构建分类详情覆盖层（展开动画效果）- 已废弃，保留兼容
   */
  @Builder
  buildCategoryDetailOverlay() {
    Column() {
      // 顶部导航栏（避让顶栏）
      Row() {
        Button() {
          SymbolGlyph($r('sys.symbol.arrow_left'))
            .fontSize(24)
            .fontColor([ThemeAwareHelper.getTestManagementThemedColor('text_primary', this.themeState.currentTheme)])
        }
        .width(44)
        .height(44)
        .backgroundColor(Color.Transparent)
        .onClick(() => {
          animateTo({
            duration: 300,
            curve: Curve.EaseIn
          }, () => {
            this.categoryDetailAnimationProgress = 0;
          });
          setTimeout(() => {
            this.showCategoryDetail = false;
            this.selectedCategoryId = '';
          }, 300);
        })

        Text(this.categoryManager.getCategory(this.selectedCategoryId)?.name || '分类详情')
          .fontSize(20)
          .fontWeight(FontWeight.Bold)
          .fontFamily(this.appFontFamily)
          .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_primary', this.themeState.currentTheme))
          .layoutWeight(1)
          .textAlign(TextAlign.Center)

        // 占位
        Column().width(44).height(44)
      }
      .width('100%')
      .height(56)
      .padding({ left: 8, right: 8 })

      // 筛选栏（全部 + 内容类型切换）
      Row({ space: 8 }) {
        // 全部筛选按钮
        Button('全部')
          .fontSize(14)
          .height(32)
          .fontFamily(this.appFontFamily)
          .backgroundColor(this.libraryFilterType === LibraryFilterType.ALL
            ? ThemeAwareHelper.getTestManagementThemedColor('accent_primary', this.themeState.currentTheme)
            : Color.Transparent)
          .fontColor(this.libraryFilterType === LibraryFilterType.ALL
            ? Color.White
            : ThemeAwareHelper.getTestManagementThemedColor('text_secondary', this.themeState.currentTheme))
          .onClick(() => {
            this.libraryFilterType = LibraryFilterType.ALL;
          })

        // 分隔线
        Column()
          .width(1)
          .height(20)
          .backgroundColor(ThemeAwareHelper.getTestManagementThemedColor('border_light', this.themeState.currentTheme))

        Button('漫画')
          .fontSize(14)
          .height(32)
          .fontFamily(this.appFontFamily)
          .backgroundColor(this.libraryContentType === LibraryContentType.MANGA
            ? ThemeAwareHelper.getTestManagementThemedColor('accent_primary', this.themeState.currentTheme)
            : Color.Transparent)
          .fontColor(this.libraryContentType === LibraryContentType.MANGA
            ? Color.White
            : ThemeAwareHelper.getTestManagementThemedColor('text_secondary', this.themeState.currentTheme))
          .onClick(() => {
            this.libraryContentType = LibraryContentType.MANGA;
          })

        Button('电子书')
          .fontSize(14)
          .height(32)
          .fontFamily(this.appFontFamily)
          .backgroundColor(this.libraryContentType === LibraryContentType.EBOOK
            ? ThemeAwareHelper.getTestManagementThemedColor('accent_primary', this.themeState.currentTheme)
            : Color.Transparent)
          .fontColor(this.libraryContentType === LibraryContentType.EBOOK
            ? Color.White
            : ThemeAwareHelper.getTestManagementThemedColor('text_secondary', this.themeState.currentTheme))
          .onClick(() => {
            this.libraryContentType = LibraryContentType.EBOOK;
          })

        Button('小说')
          .fontSize(14)
          .height(32)
          .fontFamily(this.appFontFamily)
          .backgroundColor(this.libraryContentType === LibraryContentType.NOVEL
            ? ThemeAwareHelper.getTestManagementThemedColor('accent_primary', this.themeState.currentTheme)
            : Color.Transparent)
          .fontColor(this.libraryContentType === LibraryContentType.NOVEL
            ? Color.White
            : ThemeAwareHelper.getTestManagementThemedColor('text_secondary', this.themeState.currentTheme))
          .onClick(() => {
            this.libraryContentType = LibraryContentType.NOVEL;
          })

        Blank()
      }
      .width('100%')
      .padding({ left: 16, right: 16, top: 4, bottom: 8 })

      // 内容列表（使用Swiper实现横向滑动切换内容类型）
      Swiper() {
        // 漫画内容
        Scroll() {
          Column() {
            this.buildCategoryMangaList()
          }
          .width('100%')
        }
        .width('100%')
        .height('100%')
        .scrollBar(BarState.Off)
        .edgeEffect(EdgeEffect.Spring)
        .friction(0.6)

        // 电子书内容
        Scroll() {
          Column() {
            this.buildCategoryEBookList()
          }
          .width('100%')
        }
        .width('100%')
        .height('100%')
        .scrollBar(BarState.Off)
        .edgeEffect(EdgeEffect.Spring)
        .friction(0.6)

        // 小说内容
        Scroll() {
          Column() {
            this.buildCategoryNovelList()
          }
          .width('100%')
        }
        .width('100%')
        .height('100%')
        .scrollBar(BarState.Off)
        .edgeEffect(EdgeEffect.Spring)
        .friction(0.6)
      }
      .index(this.libraryContentType === LibraryContentType.MANGA ? 0 :
        (this.libraryContentType === LibraryContentType.EBOOK ? 1 : 2))
      .indicator(false)
      .loop(false)
      .layoutWeight(1)
      .onChange((index: number) => {
        // 滑动切换内容类型
        if (index === 0) {
          this.libraryContentType = LibraryContentType.MANGA;
        } else if (index === 1) {
          this.libraryContentType = LibraryContentType.EBOOK;
        } else {
          this.libraryContentType = LibraryContentType.NOVEL;
        }
      })
    }
    .width('100%')
    .height('100%')
    .padding({ bottom: this.BOTTOM_BAR_HEIGHT }) // 避让底栏
    .backgroundColor(Color.Transparent) // 透明背景
    .scale({ x: this.categoryDetailAnimationProgress, y: this.categoryDetailAnimationProgress })
    .opacity(this.categoryDetailAnimationProgress)
  }

  /**
   * 构建移动到分类对话框（无背景压暗，带动画）
   */
  @Builder
  buildMoveToCategoryDialog() {
    Column() {
      Column({ space: 16 }) {
        Text('移动到分类')
          .fontSize(18)
          .fontWeight(FontWeight.Bold)
          .fontFamily(this.appFontFamily)
          .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_primary', this.themeState.currentTheme))

        // 分类列表
        Scroll() {
          Column({ space: 8 }) {
            ForEach(this.bookshelfCategories, (category: BookshelfCategory) => {
              Row({ space: 12 }) {
                SymbolGlyph($r('sys.symbol.folder'))
                  .fontSize(24)
                  .fontColor([ThemeAwareHelper.getTestManagementThemedColor('accent_primary', this.themeState.currentTheme)])

                Text(category.name)
                  .fontSize(16)
                  .fontFamily(this.appFontFamily)
                  .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_primary', this.themeState.currentTheme))
                  .layoutWeight(1)

                Text(`${category.itemCount} 项`)
                  .fontSize(14)
                  .fontFamily(this.appFontFamily)
                  .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_secondary', this.themeState.currentTheme))
              }
              .width('100%')
              .height(52)
              .padding({ left: 16, right: 16 })
              .backgroundColor(ThemeAwareHelper.getTestManagementThemedColor('background_secondary', this.themeState.currentTheme))
              .borderRadius(8)
              .onClick(() => {
                // 根据内容类型调用移动方法
                if (this.movingContentType === 'ebook') {
                  this.moveItemToCategory(this.movingEBookId, ContentType.EBOOK, category.id);
                } else if (this.movingContentType === 'novel') {
                  this.moveItemToCategory(this.movingNovelId, ContentType.NOVEL, category.id);
                } else {
                  this.moveItemToCategory(this.movingMangaId, ContentType.MANGA, category.id);
                }
              })
            }, (category: BookshelfCategory) => category.id)
          }
          .width('100%')
        }
        .width('100%')
        .constraintSize({ maxHeight: 300 })

        Button('取消')
          .width('100%')
          .height(44)
          .fontFamily(this.appFontFamily)
          .backgroundColor(ThemeAwareHelper.getTestManagementThemedColor('background_secondary', this.themeState.currentTheme))
          .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_primary', this.themeState.currentTheme))
          .onClick(() => {
            animateTo({ duration: 200, curve: Curve.EaseOut }, () => {
              this.showMoveToCategoryDialog = false;
            });
            this.movingMangaId = '';
            this.movingEBookId = '';
            this.movingNovelId = '';
            this.movingContentType = 'manga';
          })
      }
      .width('85%')
      .padding(20)
      .backgroundColor(ThemeAwareHelper.getTestManagementThemedColor('panel_background', this.themeState.currentTheme))
      .borderRadius(16)
    }
    .width('100%')
    .height('100%')
    .justifyContent(FlexAlign.Center)
    .backgroundColor(Color.Transparent) // 无背景压暗
    .zIndex(2000) // 确保在最顶层
  }

  /**
   * 移动内容到分类
   */
  private async moveItemToCategory(itemId: string, contentType: ContentType, categoryId: string): Promise<void> {
    await this.categoryManager.moveItemToCategory(itemId, contentType, categoryId);
    // 自动更新分类封面
    await this.updateCategoryCoversAuto(categoryId);
    await this.refreshCategories();
    
    // 强制刷新对应的内容列表以触发UI更新
    if (contentType === ContentType.MANGA) {
      this.filteredMangaList = [...this.filteredMangaList];
    } else if (contentType === ContentType.EBOOK) {
      this.filteredEbookList = [...this.filteredEbookList];
    } else if (contentType === ContentType.NOVEL) {
      this.filteredNovelList = [...this.filteredNovelList];
    }
    
    animateTo({ duration: 200, curve: Curve.EaseOut }, () => {
      this.showMoveToCategoryDialog = false;
    });
    // 清除所有移动状态
    this.movingMangaId = '';
    this.movingEBookId = '';
    this.movingNovelId = '';
    this.movingContentType = 'manga';
    logger.info(TAG, `已将 ${itemId} 移动到分类 ${categoryId}`);
  }

  /**
   * 自动更新分类封面（从分类中的内容获取封面）
   */
  private async updateCategoryCoversAuto(categoryId: string): Promise<void> {
    const items = this.categoryManager.getCategoryItemsSorted(categoryId);
    const coverPaths: string[] = [];

    for (const item of items) {
      if (coverPaths.length >= 4) break;

      if (item.contentType === ContentType.MANGA) {
        const manga = this.mangaList.find(m => m.id === item.itemId);
        if (manga && manga.coverImagePath) {
          coverPaths.push(manga.coverImagePath);
        }
      } else if (item.contentType === ContentType.EBOOK) {
        const ebook = this.ebookList.find(e => e.id === item.itemId);
        if (ebook && ebook.metadata && ebook.metadata.coverImagePath) {
          coverPaths.push(ebook.metadata.coverImagePath);
        }
      } else if (item.contentType === ContentType.NOVEL) {
        const novel = this.novelList.find(n => n.id === item.itemId);
        if (novel && novel.coverUrl) {
          coverPaths.push(novel.coverUrl);
        }
      }
    }

    await this.categoryManager.autoUpdateCategoryCovers(categoryId, coverPaths);
  }

  /**
   * 更新所有分类的封面
   */
  private async updateAllCategoryCovers(): Promise<void> {
    for (const category of this.bookshelfCategories) {
      await this.updateCategoryCoversAuto(category.id);
    }
    await this.refreshCategories();
  }

  /**
   * 构建分类内容列表
   */
  @Builder
  buildCategoryContentList() {
    if (this.libraryContentType === LibraryContentType.MANGA) {
      // 显示该分类下的漫画
      Grid() {
        ForEach(this.filteredMangaList.filter((manga: Manga) => {
          return this.categoryManager.isItemInCategory(manga.id, ContentType.MANGA, this.selectedCategoryId) ||
            (this.selectedCategoryId === 'default' && this.categoryManager.getUncategorizedItemKey(manga.id, ContentType.MANGA));
        }), (manga: Manga) => {
          GridItem() {
            this.buildMangaGridCard(manga)
          }
        }, (manga: Manga) => manga.id)
      }
      .columnsTemplate(this.getLibraryGridColumnsTemplate())
      .rowsGap(this.responsive_gridGap)
      .columnsGap(this.responsive_gridGap)
      .width('100%')
      .padding(16)
    } else if (this.libraryContentType === LibraryContentType.EBOOK) {
      // 显示该分类下的电子书
      Grid() {
        ForEach(this.filteredEbookList.filter((ebook: EBook) => {
          return this.categoryManager.isItemInCategory(ebook.id, ContentType.EBOOK, this.selectedCategoryId) ||
            (this.selectedCategoryId === 'default' && this.categoryManager.getUncategorizedItemKey(ebook.id, ContentType.EBOOK));
        }), (ebook: EBook) => {
          GridItem() {
            this.buildEBookGridCard(ebook)
          }
        }, (ebook: EBook) => ebook.id)
      }
      .columnsTemplate(this.getLibraryGridColumnsTemplate())
      .rowsGap(this.responsive_gridGap)
      .columnsGap(this.responsive_gridGap)
      .width('100%')
      .padding(16)
    } else {
      // 显示该分类下的小说
      Grid() {
        ForEach(this.filteredNovelList.filter((novel: NovelBook) => {
          return this.categoryManager.isItemInCategory(novel.id, ContentType.NOVEL, this.selectedCategoryId) ||
            (this.selectedCategoryId === 'default' && this.categoryManager.getUncategorizedItemKey(novel.id, ContentType.NOVEL));
        }), (novel: NovelBook) => {
          GridItem() {
            this.buildNovelGridCard(novel)
          }
        }, (novel: NovelBook) => novel.id)
      }
      .columnsTemplate(this.getLibraryGridColumnsTemplate())
      .rowsGap(this.responsive_gridGap)
      .columnsGap(this.responsive_gridGap)
      .width('100%')
      .padding(16)
    }
  }

  @Builder
  buildLibraryMangaGridContent() {
    Grid() {
      ForEach(this.filteredMangaList, (manga: Manga, index: number) => {
        GridItem() {
          this.buildMangaGridCard(manga)
        }
      }, (manga: Manga) => manga.id)
    }
    .columnsTemplate(this.getLibraryGridColumnsTemplate())
    .rowsGap(this.responsive_gridGap)
    .columnsGap(this.responsive_gridGap)
    .width('100%')
  }

  /**
   * 构建漫画网格卡片
   */
  @Builder
  buildMangaGridCard(manga: Manga) {
    Column({ space: 8 }) {
      // 封面图片
      Stack() {
        Image(this.normalizeDisplayPathForManga(manga) || $r('app.media.mangabook'))
          .width('100%')
          .aspectRatio(0.7)
          .objectFit(ImageFit.Cover)
          .borderRadius(8)
          .backgroundColor(ThemeAwareHelper.getTestManagementThemedColor('background_secondary', this.themeState.currentTheme))
          .shadow({
            radius: 8,
            color: '#1F000000',
            offsetY: 4
          })
          .onError(() => {
            logger.warn('MainMenuPage', `主页网格封面加载失败: raw='${manga.coverImagePath}', display='${this.normalizeDisplayPathForManga(manga)}', source=${manga.coverSourceType}`);
          })
          .id(`library_manga_${manga.id}`)

        // 选中状态遮罩
        if (this.isMultiSelectMode && this.selectedMangaIds.has(manga.id)) {
          Column()
            .width('100%')
            .height('100%')
            .backgroundColor('#80007DFF')
            .borderRadius(8)
        }

        // 选中图标
        if (this.isMultiSelectMode) {
          Column() {
            Image($r('app.media.ic_check'))
              .width(24)
              .height(24)
              .fillColor(this.selectedMangaIds.has(manga.id)
                ? ThemeAwareHelper.getTestManagementThemedColor('text_white', this.themeState.currentTheme)
                : '#80FFFFFF')
              .backgroundColor(this.selectedMangaIds.has(manga.id)
                ? ThemeAwareHelper.getTestManagementThemedColor('accent_blue', this.themeState.currentTheme)
                : '#40000000')
              .borderRadius(12)
              .padding(4)
          }
          .width('100%')
          .height('100%')
          .justifyContent(FlexAlign.End)
          .alignItems(HorizontalAlign.End)
          .padding(8)
        }
      }

      // 漫画标题
      Text(manga.title)
        .fontSize(14)
        .fontWeight(FontWeight.Medium)
        .fontFamily(this.appFontFamily)
        .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_primary', this.themeState.currentTheme))
        .maxLines(2)
        .textOverflow({ overflow: TextOverflow.Ellipsis })
        .width('100%')
        .textAlign(TextAlign.Center)

      // 阅读进度（GRID模式）- 显示当前阅读页数
      if (manga.readingProgress && (manga.readingProgress.currentChapterId || manga.readingProgress.currentPageIndex > 0)) {
        Text(`已读 ${manga.readingProgress.currentPageIndex + 1} 页`)
          .fontSize(10)
          .fontFamily(this.appFontFamily)
          .fontColor(ThemeAwareHelper.getTestManagementThemedColor('accent_primary', this.themeState.currentTheme))
      }
    }
    .width('100%')
    .padding(8)
    .backgroundColor(this.getGlassBackground())
    .backgroundBlurStyle(this.getGlassBlur())
    .borderRadius(this.getGlassRadius())
    .border({
      width: this.isMultiSelectMode && this.selectedMangaIds.has(manga.id) ? 2 : 0,
      color: ThemeAwareHelper.getTestManagementThemedColor('accent_blue', this.themeState.currentTheme)
    })
    .onClick(() => {
      if (this.isMultiSelectMode) {
        // 多选模式：切换选中状态
        this.toggleMangaSelection(manga.id);
      } else {
        // 普通模式：打开详情页
        this.openMangaDetail(manga);
      }
    })
    .bindContextMenu(this.buildMangaGridContextMenu(manga), ResponseType.LongPress)
  }

  /**
   * 构建漫画网格右键菜单
   */
  @Builder
  buildMangaGridContextMenu(manga: Manga) {
    Menu() {
      MenuItem({ content: '移动到分类' })
        .onClick(() => {
          this.movingMangaId = manga.id;
          this.showMoveToCategoryDialog = true;
        })
      if (!this.isPrivacyMode) {
        MenuItem({ content: '移动到隐私书库' })
          .onClick(() => {
            this.toggleMangaPrivacy(manga.id, true);
          })
      } else {
        MenuItem({ content: '移出隐私书库' })
          .onClick(() => {
            this.toggleMangaPrivacy(manga.id, false);
          })
      }
      MenuItem({ content: '进入多选模式' })
        .onClick(() => {
          if (!this.isMultiSelectMode) {
            this.enterMultiSelectMode();
            this.toggleMangaSelection(manga.id);
          }
        })
      MenuItem({ content: '删除' })
        .onClick(() => {
          this.showDeleteMangaDialog(manga.id);
        })
    }
  }

  /**
   * 构建电子书网格右键菜单
   */
  @Builder
  buildEBookGridContextMenu(ebook: EBook) {
    Menu() {
      MenuItem({ content: '移动到分类' })
        .onClick(() => {
          this.movingEBookId = ebook.id;
          this.movingContentType = 'ebook';
          animateTo({ duration: 200, curve: Curve.EaseOut }, () => {
            this.showMoveToCategoryDialog = true;
          });
        })
      if (!this.isPrivacyMode) {
        MenuItem({ content: '移动到隐私书库' })
          .onClick(() => {
            this.toggleEBookPrivacy(ebook.id, true);
          })
      } else {
        MenuItem({ content: '移出隐私书库' })
          .onClick(() => {
            this.toggleEBookPrivacy(ebook.id, false);
          })
      }
      MenuItem({ content: '进入多选模式' })
        .onClick(() => {
          if (!this.isEBookMultiSelectMode) {
            this.enterEBookMultiSelectMode();
            this.toggleEBookSelection(ebook.id);
          }
        })
      MenuItem({ content: '删除' })
        .onClick(() => {
          this.showDeleteEBookDialog(ebook.id);
        })
    }
  }

  /**
   * 构建小说右键菜单
   */
  @Builder
  buildNovelContextMenu(novel: NovelBook) {
    Menu() {
      MenuItem({ content: '移动到分类' })
        .onClick(() => {
          this.movingNovelId = novel.id;
          this.movingContentType = 'novel';
          animateTo({ duration: 200, curve: Curve.EaseOut }, () => {
            this.showMoveToCategoryDialog = true;
          });
        })
      if (!this.isPrivacyMode) {
        MenuItem({ content: '移动到隐私书库' })
          .onClick(() => {
            this.toggleNovelPrivacy(novel.id, true);
          })
      } else {
        MenuItem({ content: '移出隐私书库' })
          .onClick(() => {
            this.toggleNovelPrivacy(novel.id, false);
          })
      }
      MenuItem({ content: '进入多选模式' })
        .onClick(() => {
          if (!this.isNovelMultiSelectMode) {
            this.enterNovelMultiSelectMode();
            this.toggleNovelSelection(novel.id);
          }
        })
      MenuItem({ content: '删除' })
        .onClick(() => {
          this.showDeleteNovelDialog(novel.id);
        })
    }
  }

  /**
   * 切换漫画的隐私状态
   */
  private async toggleMangaPrivacy(mangaId: string, isPrivate: boolean): Promise<void> {
    try {
      logger.info(TAG, `切换漫画隐私状态: ${mangaId}, isPrivate=${isPrivate}`);
      
      // 使用通用方法更新隐私状态，自动检测内容类型
      const success = await this.dataManager.updateContentPrivacy(mangaId, isPrivate);
      
      if (!success) {
        logger.error(TAG, `更新隐私状态失败: ${mangaId}`);
        this.showToast('操作失败：未找到内容');
        return;
      }
      
      // 重新从数据库加载数据，确保隐私筛选正确
      await this.loadMangaList();
      
      // 显示提示
      this.showToast(isPrivate ? '已移动到隐私书库' : '已移出隐私书库');
      
    } catch (error) {
      logger.error(TAG, `切换漫画隐私状态失败: ${error}`);
      this.showToast('操作失败');
    }
  }

  /**
   * 切换电子书的隐私状态
   */
  private async toggleEBookPrivacy(bookId: string, isPrivate: boolean): Promise<void> {
    try {
      logger.info(TAG, `切换电子书隐私状态: ${bookId}, isPrivate=${isPrivate}`);
      
      // 更新数据库
      const dbManager = DatabaseManager.getInstance();
      const sql = 'UPDATE ebook_info SET isPrivate = ? WHERE id = ?';
      await dbManager.executeSql(sql, [isPrivate ? 1 : 0, bookId]);
      
      // 无感刷新：从当前列表中移除该书籍（因为隐私状态改变后它不应该出现在当前视图）
      const ebookIndex = this.ebookList.findIndex(e => e.id === bookId);
      if (ebookIndex !== -1) {
        this.ebookList.splice(ebookIndex, 1);
      }
      
      // 重新应用筛选
      this.applyEBookFilter();
      
      // 显示提示
      this.showToast(isPrivate ? '已移动到隐私书库' : '已移出隐私书库');
      
    } catch (error) {
      logger.error(TAG, `切换电子书隐私状态失败: ${error}`);
      this.showToast('操作失败');
    }
  }

  /**
   * 切换小说的隐私状态
   */
  private async toggleNovelPrivacy(bookId: string, isPrivate: boolean): Promise<void> {
    try {
      logger.info(TAG, `切换小说隐私状态: ${bookId}, isPrivate=${isPrivate}`);
      
      // 更新数据库
      const dbManager = DatabaseManager.getInstance();
      const sql = 'UPDATE novel_book SET isPrivate = ? WHERE id = ?';
      await dbManager.executeSql(sql, [isPrivate ? 1 : 0, bookId]);
      
      // 无感刷新：从当前列表中移除该书籍（因为隐私状态改变后它不应该出现在当前视图）
      const novelIndex = this.novelList.findIndex(n => n.id === bookId);
      if (novelIndex !== -1) {
        this.novelList.splice(novelIndex, 1);
      }
      
      // 重新应用筛选
      this.applyNovelFilter();
      
      // 显示提示
      this.showToast(isPrivate ? '已移动到隐私书库' : '已移出隐私书库');
      
    } catch (error) {
      logger.error(TAG, `切换小说隐私状态失败: ${error}`);
      this.showToast('操作失败');
    }
  }

  /**
   * 构建发现页漫画网格卡片（不支持多选）
   */
  @Builder
  buildDiscoverMangaGridCard(manga: Manga) {
    Column({ space: 8 }) {
      // 封面图片
      Image(this.normalizeDisplayPathForManga(manga) || $r('app.media.mangabook'))
        .width('100%')
        .aspectRatio(0.7)
        .objectFit(ImageFit.Cover)
        .borderRadius(8)
        .backgroundColor(ThemeAwareHelper.getTestManagementThemedColor('background_secondary', this.themeState.currentTheme))
        .shadow({
          radius: 8,
          color: '#1F000000',
          offsetY: 4
        })

      // 漫画标题
      Text(manga.title)
        .fontSize(14)
        .fontWeight(FontWeight.Medium)
        .fontFamily(this.appFontFamily)
        .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_primary', this.themeState.currentTheme))
        .maxLines(2)
        .textOverflow({ overflow: TextOverflow.Ellipsis })
        .width('100%')
        .textAlign(TextAlign.Center)
    }
    .width('100%')
    .padding(8)
    .backgroundColor(this.getGlassBackground())
    .backgroundBlurStyle(this.getGlassBlur())
    .borderRadius(this.getGlassRadius())
    .onClick(() => {
      this.openMangaDetail(manga);
    })
  }

  /**
   * 构建发现页小说网格卡片
   */
  @Builder
  buildDiscoverNovelGridCard(novel: NovelBook) {
    Column({ space: 8 }) {
      // 封面图片
      Stack() {
        Image(novel.coverLocalPath || novel.coverUrl || $r('app.media.mangabook'))
          .width('100%')
          .aspectRatio(0.7)
          .objectFit(ImageFit.Cover)
          .borderRadius(8)
          .backgroundColor(ThemeAwareHelper.getTestManagementThemedColor('background_secondary', this.themeState.currentTheme))
          .shadow({
            radius: 8,
            color: '#1F000000',
            offsetY: 4
          })
        
        // 小说标识
        Text('小说')
          .fontSize(10)
          .fontFamily(this.appFontFamily)
          .fontColor('#FFFFFF')
          .backgroundColor('#4CAF50')
          .padding({ left: 4, right: 4, top: 2, bottom: 2 })
          .borderRadius(4)
          .position({ x: 4, y: 4 })
      }

      // 小说标题
      Text(novel.name)
        .fontSize(14)
        .fontWeight(FontWeight.Medium)
        .fontFamily(this.appFontFamily)
        .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_primary', this.themeState.currentTheme))
        .maxLines(2)
        .textOverflow({ overflow: TextOverflow.Ellipsis })
        .width('100%')
        .textAlign(TextAlign.Center)
    }
    .width('100%')
    .padding(8)
    .backgroundColor(this.getGlassBackground())
    .backgroundBlurStyle(this.getGlassBlur())
    .borderRadius(this.getGlassRadius())
    .onClick(() => {
      this.openNovelDetail(novel);
    })
  }

  /**
   * 构建电子书List卡片（支持长按左滑删除）
   */
  @Builder
  buildEBookCard(ebook: EBook) {
    Stack() {
      // 右侧删除提示面板
      Column() {
        Text(this.getEBookSwipeProgressText(ebook.id))
          .fontSize(14)
          .fontWeight(FontWeight.Medium)
          .fontFamily(this.appFontFamily)
          .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_white', this.themeState.currentTheme))
        Text('松手删除')
          .fontSize(12)
          .fontFamily(this.appFontFamily)
          .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_white', this.themeState.currentTheme))
      }
      .width(96)
      .height('100%')
      .justifyContent(FlexAlign.Center)
      .alignItems(HorizontalAlign.Center)
      .backgroundColor(ThemeAwareHelper.getTestManagementThemedColor('button_danger', this.themeState.currentTheme))
      .borderRadius(this.getGlassRadius())
      .opacity(this.activeEBookSwipeId === ebook.id ? Math.min(1, this.getEBookSwipeOffset(ebook.id) / this.swipeThreshold) : 0.15)
      .position({ x: '100%', y: 0 })

      // 卡片内容层
      Row({ space: 12 }) {
        // 封面图片
        Column() {
          if (this.hasValidEBookCover(ebook)) {
            Image(this.getEBookCoverSource(ebook))
              .width('100%')
              .height('100%')
              .objectFit(ImageFit.Cover)
          } else {
            Image(this.getEBookCoverSource(ebook))
              .width(50)
              .height(50)
              .objectFit(ImageFit.Cover)
              .fillColor(ThemeAwareHelper.getTestManagementThemedColor('accent_primary', this.themeState.currentTheme))
          }
        }
        .width(80)
        .height(120)
        .backgroundColor(ThemeAwareHelper.getTestManagementThemedColor('comp_background_tertiary', this.themeState.currentTheme))
        .borderRadius(8)
        .justifyContent(FlexAlign.Center)
        .shadow({
          radius: 8,
          color: '#1F000000',
          offsetY: 4
        })
        .id(`cover_ebook_lib_${ebook.id}`)

        // 电子书信息
        Column({ space: 6 }) {
          Text(ebook.metadata.title)
            .fontSize(16)
            .fontWeight(FontWeight.Medium)
            .fontFamily(this.appFontFamily)
            .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_primary', this.themeState.currentTheme))
            .maxLines(2)
            .textOverflow({ overflow: TextOverflow.Ellipsis })

          Text(`${ebook.metadata.author} · ${ebook.format}`)
            .fontSize(14)
            .fontFamily(this.appFontFamily)
            .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_secondary', this.themeState.currentTheme))

          // 阅读进度条和百分比
          if (ebook.readingProgress && ebook.readingProgress.progress > 0) {
            Row({ space: 6 }) {
              Progress({
                value: ebook.readingProgress.progress,
                total: 100,
                type: ProgressType.Linear
              })
                .width(80)
                .height(4)
                .color(ThemeAwareHelper.getTestManagementThemedColor('accent_primary', this.themeState.currentTheme))

              Text(`${Math.floor(ebook.readingProgress.progress)}%`)
                .fontSize(12)
                .fontFamily(this.appFontFamily)
                .fontColor(ThemeAwareHelper.getTestManagementThemedColor('accent_primary', this.themeState.currentTheme))
            }
          }

          // 电子书简介
          Text(ebook.metadata.description || '暂无简介')
            .fontSize(12)
            .fontFamily(this.appFontFamily)
            .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_muted', this.themeState.currentTheme))
            .maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis })

          Blank()

          // 开始阅读按钮
          Row({ space: 12 }) {
            Blank()

            Button(this.hasEBookReadingProgress(ebook) ? '继续阅读' : '开始阅读')
              .fontSize(14)
              .height(32)
              .fontFamily(this.appFontFamily)
              .padding({ left: 16, right: 16 })
              .backgroundColor(ThemeAwareHelper.getTestManagementThemedColor('accent_primary', this.themeState.currentTheme))
              .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_white', this.themeState.currentTheme))
              .onClick(() => {
                // 使用电子书阅读器打开（带翻开动画）
                this.openEBookReader(ebook);
              })
          }
          .width('100%')
        }
        .layoutWeight(1)
        .alignItems(HorizontalAlign.Start)
        .justifyContent(FlexAlign.SpaceBetween)
      }
      .translate({ x: -this.getEBookSwipeOffset(ebook.id), y: 0 })
      .onClick(() => { this.openEBookDetail(ebook); })
      .width('100%')
      .height(140)
      .padding(12)
      .backgroundColor(this.getGlassBackground())
      .backgroundBlurStyle(this.getGlassBlur())
      .borderRadius(this.getGlassRadius())
      .shadow({ radius: this.getGlassRadius(), color: this.getGlassShadowColor(), offsetY: 2 })
      .gesture(
        GestureGroup(GestureMode.Parallel,
          LongPressGesture({ repeat: false })
            .onAction(() => { this.activateEBookSwipeFor(ebook.id); }),
          PanGesture({ fingers: 1, direction: PanDirection.Left, distance: 1 })
            .onActionUpdate((event: GestureEvent) => { this.updateEBookSwipeOffset(ebook.id, event); })
            .onActionEnd((event: GestureEvent) => { this.endEBookSwipe(ebook.id); })
        )
      )
    }
    .width('100%')
    .height(140)
  }

  /**
   * 获取电子书背景设置（用于翻开动画）
   */
  private getEBookBackgroundSettings(ebook: EBook): EBookBackgroundSettings | undefined {
    let bgSettings: EBookBackgroundSettings = {
      backgroundColor: '#FFFFFF'  // 默认白色背景
    };
    
    // 读取电子书保存的背景设置
    if (ebook.readingSettings) {
      bgSettings.backgroundColor = ebook.readingSettings.backgroundColor || '#FFFFFF';
      
      // 只有 TXT 格式支持背景图片
      if (ebook.format === EBookFormat.TXT) {
        if (ebook.readingSettings.backgroundType === 'IMAGE' && 
            ebook.readingSettings.backgroundImagePath && 
            ebook.readingSettings.backgroundImagePath.length > 0) {
          bgSettings.backgroundImagePath = ebook.readingSettings.backgroundImagePath;
          bgSettings.backgroundImageOpacity = ebook.readingSettings.backgroundImageOpacity ?? 0.3;
        }
      }
      
      logger.info(TAG, `电子书背景设置(${ebook.format}): color=${bgSettings.backgroundColor}, image=${bgSettings.backgroundImagePath || '无'}, opacity=${bgSettings.backgroundImageOpacity ?? 'N/A'}`);
    } else {
      logger.info(TAG, `电子书无阅读设置，使用默认白色背景`);
    }
    
    return bgSettings;
  }

  /**
   * 打开漫画阅读器（带翻开动画）
   * @param manga 漫画对象
   * @param componentId 封面组件ID（用于获取位置）
   */
  private async openMangaReaderWithAnimation(manga: Manga, componentId: string): Promise<void> {
    logger.info(TAG, `打开漫画阅读器（带翻开动画）: ${manga.title}`);
    
    try {
      // 获取漫画的sourceId和相关信息
      const comicInfo: ComicInfo | null = await this.dataManager.getComicById(manga.id);
      let sourceIdNum: number = -1;
      let hasWebSource: boolean = false;
      if (comicInfo && typeof comicInfo.sourceId === 'string' && comicInfo.sourceId.length > 0) {
        const parsed: number = Number(comicInfo.sourceId);
        if (!isNaN(parsed)) {
          sourceIdNum = parsed;
          hasWebSource = true;
        }
      }
      let sourceNameVal: string = 'LOCAL';
      if (hasWebSource) {
        const srcRecord: ComicSourceDatabaseRecord | null = await this.dataManager.getComicSourceById(sourceIdNum);
        if (srcRecord && typeof srcRecord.name === 'string' && srcRecord.name.length > 0) {
          sourceNameVal = srcRecord.name;
        } else {
          sourceNameVal = 'WEBVIEW';
        }
      }

      // 确定恢复目标
      const target = await this.determineResumeTarget(manga);
      
      // 准备阅读器参数
      let readerParams: MangaReaderPageParams;
      
      if (!target) {
        // 无阅读记录，从第一章开始
        if (hasWebSource) {
          const onlineChapterInfos = await this.dataManager.getOnlineComicChapters(manga.id);
          if (onlineChapterInfos && onlineChapterInfos.length > 0) {
            let firstChapterId: string = onlineChapterInfos[0].id;
            let minChapterNumber: number = onlineChapterInfos[0].chapterNumber;
            for (let i: number = 1; i < onlineChapterInfos.length; i++) {
              const info = onlineChapterInfos[i];
              if (info.chapterNumber < minChapterNumber) {
                minChapterNumber = info.chapterNumber;
                firstChapterId = info.id;
              }
            }
            const ct: MangaReaderContentType = onlineChapterInfos[0].isDownloaded
              ? MangaReaderContentType.OnlineDownloaded
              : MangaReaderContentType.OnlineUndownloaded;

            readerParams = {
              mangaId: manga.id,
              chapterId: firstChapterId,
              pageIndex: 0,
              fromPage: 'MainMenuPage',
              contentType: ct,
              sourceId: sourceIdNum,
              sourceName: sourceNameVal
            } as MangaReaderPageParams;
          } else {
            this.showToast('未找到章节，无法进入阅读器');
            return;
          }
        } else {
          const chapterInfos = await this.dataManager.getComicChapters(manga.id);
          if (chapterInfos && chapterInfos.length > 0) {
            let firstChapterId: string = chapterInfos[0].id;
            let minIndex: number = chapterInfos[0].index;
            for (let i: number = 1; i < chapterInfos.length; i++) {
              const info = chapterInfos[i];
              if (info.index < minIndex) {
                minIndex = info.index;
                firstChapterId = info.id;
              }
            }
            readerParams = {
              mangaId: manga.id,
              chapterId: firstChapterId,
              pageIndex: 0,
              fromPage: 'MainMenuPage',
              contentType: MangaReaderContentType.Local,
              sourceId: undefined,
              sourceName: sourceNameVal
            } as MangaReaderPageParams;
          } else {
            this.showToast('未找到章节，无法进入阅读器');
            return;
          }
        }
      } else {
        // 有阅读记录，恢复到上次位置
        let ct2: MangaReaderContentType = MangaReaderContentType.Local;
        if (hasWebSource) {
          const targetChapterInfo = await this.dataManager.getOnlineChapterById(target.chapterId);
          if (targetChapterInfo && targetChapterInfo.isDownloaded) {
            ct2 = MangaReaderContentType.OnlineDownloaded;
          } else {
            ct2 = MangaReaderContentType.OnlineUndownloaded;
          }
        }
        readerParams = {
          mangaId: manga.id,
          chapterId: target.chapterId,
          pageIndex: target.pageIndex,
          fromPage: 'MainMenuPage',
          contentType: ct2,
          sourceId: hasWebSource ? sourceIdNum : undefined,
          sourceName: sourceNameVal
        } as MangaReaderPageParams;
      }

      // 触发翻开过渡动画
      const coverPath: string = this.normalizeDisplayPathForManga(manga) || '';
      logger.info(TAG, `触发漫画翻开过渡动画: coverPath=${coverPath}, componentId=${componentId}`);
      
      startBookOpenTransitionWithComponentId(
        coverPath,
        componentId,
        manga.id,
        'manga',
        () => {
          // 动画完成时触发导航
          logger.info(TAG, '漫画翻开过渡动画触发导航');
          this.pathStack.pushPathByName('MangaReaderPage', readerParams);
        }
      );
    } catch (error) {
      const errMsg: string = error instanceof Error ? error.message : String(error);
      logger.error(TAG, '打开漫画阅读器（带动画）失败', errMsg);
      this.showToast('打开漫画阅读器失败');
    }
  }

  /**
   * 打开电子书阅读器（带翻开动画）- 从书库页面调用
   */
  private openEBookReader(ebook: EBook): void {
    this.openEBookReaderWithComponentId(ebook, `cover_ebook_lib_${ebook.id}`);
  }

  /**
   * 打开电子书阅读器（带翻开动画）- 从首页调用
   */
  private openEBookReaderFromHome(ebook: EBook): void {
    this.openEBookReaderWithComponentId(ebook, `cover_ebook_home_${ebook.id}`);
  }

  /**
   * 打开电子书阅读器（带翻开动画）- 通用方法
   * @param ebook 电子书对象
   * @param componentId 封面组件ID
   */
  private openEBookReaderWithComponentId(ebook: EBook, componentId: string): void {
    logger.info(TAG, `打开电子书阅读器: ${ebook.metadata.title}`);
    
    // 触发翻开过渡动画（使用组件ID获取实际位置）
    const coverPath: string = ebook.metadata.coverImagePath || '';
    const readerParams: EBookReaderParams = {
      bookId: ebook.id
    };
    
    // 获取电子书背景设置
    const ebookBackground = this.getEBookBackgroundSettings(ebook);
    
    logger.info(TAG, `触发翻开过渡动画: coverPath=${coverPath}, componentId=${componentId}`);
    startBookOpenTransitionWithComponentId(
      coverPath,
      componentId,
      ebook.id,
      'ebook',
      () => {
        // 动画完成时触发导航
        logger.info(TAG, '翻开过渡动画触发导航');
        this.pathStack.pushPath({ name: 'EBookReaderPage', param: readerParams });
      },
      ebookBackground
    );
  }

  /**
   * 打开电子书详情页
   */
  private openEBookDetail(ebook: EBook): void {
    logger.info(TAG, `打开电子书详情页: ${ebook.metadata.title}`);
    const detailParams: EBookDetailPageParams = {
      bookId: ebook.id
    };
    this.pathStack.pushPath({ name: 'EBookDetailPage', param: detailParams });
  }

  /**
   * 检查电子书是否有阅读进度
   * 判断条件：有 domPos 或 currentChapterIndex > 0 或 progress > 0
   */
  private hasEBookReadingProgress(ebook: EBook): boolean {
    if (!ebook.readingProgress) {
      return false;
    }
    const progress = ebook.readingProgress;
    // 有 domPos 表示有精确的阅读位置
    if (progress.domPos && progress.domPos.length > 0) {
      return true;
    }
    // 章节索引大于 0 表示已经翻过页
    if (progress.currentChapterIndex > 0) {
      return true;
    }
    // 进度大于 0 也表示有阅读记录
    if (progress.progress > 0) {
      return true;
    }
    return false;
  }

  /**
   * 检查漫画是否有阅读进度
   * 判断条件：有 currentChapterId 或 currentPageIndex > 0
   */
  private hasMangaReadingProgress(manga: Manga): boolean {
    if (!manga.readingProgress) {
      return false;
    }
    const progress = manga.readingProgress;
    // 有章节ID表示有阅读记录
    if (progress.currentChapterId && progress.currentChapterId.length > 0) {
      return true;
    }
    // 页码大于 0 表示已经翻过页
    if (progress.currentPageIndex > 0) {
      return true;
    }
    // 阅读百分比大于 0 也表示有阅读记录
    if (progress.readingPercentage > 0) {
      return true;
    }
    return false;
  }

  /**
   * 获取漫画阅读进度文本
   * 显示当前章节名称和页数
   */
  private getMangaReadingProgressText(manga: Manga): string {
    if (!manga.readingProgress) {
      return '';
    }
    const progress = manga.readingProgress;
    
    // 尝试获取当前章节名称
    let chapterName = '';
    if (progress.currentChapterId && manga.chapters && manga.chapters.length > 0) {
      const currentChapter = manga.chapters.find(ch => ch.id === progress.currentChapterId);
      if (currentChapter) {
        chapterName = currentChapter.title;
      }
    }
    
    // 构建进度文本
    const pageText = `第${progress.currentPageIndex + 1}页`;
    if (chapterName) {
      return `${chapterName} · ${pageText}`;
    } else if (progress.readingPercentage > 0) {
      return `${Math.floor(progress.readingPercentage)}% · ${pageText}`;
    } else {
      return pageText;
    }
  }

  private async deleteEBookItem(ebook: EBook): Promise<void> {
    try {
      logger.info(TAG, `开始删除电子书: ${ebook.id}`);
      await this.ebookDataManager.deleteEBook(ebook.id);
      const newList: EBook[] = [];
      for (let i: number = 0; i < this.ebookList.length; i++) {
        const b: EBook = this.ebookList[i];
        if (b.id !== ebook.id) { newList.push(b); }
      }
      this.ebookList = newList;
      this.applyEBookFilter();
      this.showToast('电子书已删除');
      logger.info(TAG, `电子书删除成功: ${ebook.metadata.title}`);
    } catch (error) {
      logger.error(TAG, '删除电子书失败', String(error));
      this.showToast('删除失败');
    }
  }

  // ==================== 左滑删除：辅助方法与确认弹窗 ====================
  private activateSwipeFor(mangaId: string): void {
    if (this.isMultiSelectMode) { return; }
    this.activeSwipeId = mangaId;
    this.isSwipeActive = true;
    this.swipeOffset = 0;
    logger.info(TAG, `长按激活左滑删除: ${mangaId}`);
  }

  private updateSwipeOffset(mangaId: string, event: GestureEvent): void {
    if (!this.isSwipeActive || this.activeSwipeId !== mangaId) { return; }
    const deltaX: number = -event.offsetX; // 左滑为负，取反为正进度
    const maxHintWidth: number = 120;
    const newOffset: number = Math.max(0, deltaX);
    this.swipeOffset = Math.min(newOffset, maxHintWidth);
  }

  private endSwipe(mangaId: string): void {
    if (!this.isSwipeActive || this.activeSwipeId !== mangaId) { return; }
    const reached: boolean = this.swipeOffset >= this.swipeThreshold;
    this.isSwipeActive = false;
    if (reached) {
      logger.info(TAG, `达到删除阈值，显示删除确认对话框: ${mangaId}`);
      this.showDeleteMangaDialog(mangaId);
    } else {
      this.resetSwipeState();
      logger.debug(TAG, `未达到删除阈值，复位: ${mangaId}`);
    }
  }

  private resetSwipeState(): void {
    this.activeSwipeId = '';
    this.isSwipeActive = false;
    this.swipeOffset = 0;
  }

  private getItemSwipeOffset(mangaId: string): number {
    return (this.activeSwipeId === mangaId && this.isSwipeActive) ? this.swipeOffset : 0;
  }

  private getSwipeProgressText(mangaId: string): string {
    const progress: number = this.activeSwipeId === mangaId ? Math.min(100, Math.floor((this.getItemSwipeOffset(mangaId) / this.swipeThreshold) * 100)) : 0;
    return progress >= 100 ? '释放删除' : `左滑 ${progress}%`;
  }

  private getMangaById(mangaId: string): Manga | null {
    for (let i: number = 0; i < this.filteredMangaList.length; i++) {
      const m: Manga = this.filteredMangaList[i];
      if (m.id === mangaId) { return m; }
    }
    return null;
  }

  /**
   * 显示删除漫画确认对话框
   */
  private showDeleteMangaDialog(mangaId: string): void {
    const manga = this.getMangaById(mangaId);
    if (!manga) {
      logger.error(TAG, `未找到漫画ID为 ${mangaId} 的漫画`);
      this.resetSwipeState();
      return;
    }

    logger.info(TAG, `显示删除漫画确认对话框: ${manga.title} (ID: ${mangaId})`);

    // 显示确认对话框
    this.getUIContext().showAlertDialog({
      title: '删除漫画',
      message: `确定要删除漫画"${manga.title}"吗？\n\n此操作将删除该漫画的所有数据和文件，且不可恢复。`,
      autoCancel: true,
      alignment: DialogAlignment.Center,
      primaryButton: {
        value: '取消',
        action: () => {
          logger.info(TAG, '用户取消删除漫画');
          this.resetSwipeState();
        }
      },
      secondaryButton: {
        value: '删除',
        fontColor: ThemeAwareHelper.getTestManagementThemedColor('button_danger', this.themeState.currentTheme),
        action: async () => {
          try {
            logger.info(TAG, `开始删除漫画: ${mangaId}`);
            await this.dataManager.deleteComic(mangaId);

            const newMangaList: Manga[] = [];
            for (let i: number = 0; i < this.mangaList.length; i++) {
              const mm: Manga = this.mangaList[i];
              if (mm.id !== mangaId) { newMangaList.push(mm); }
            }
            this.mangaList = newMangaList;

            eventBus.publish(GameEvent.MANGA_DELETED, new MangaDeletedPayload(mangaId));

            // 触发动画
            await this.applyLibraryFilter();

            this.showToast('漫画已删除');
            logger.info(TAG, `漫画删除成功: ${mangaId}`);
            this.resetSwipeState();
          } catch (error) {
            logger.error(TAG, '删除漫画失败', String(error));
            this.showToast('删除失败');
            this.resetSwipeState();
          }
        }
      }
    });
  }


  // ==================== 电子书左滑删除：辅助方法与确认弹窗 ====================
  private activateEBookSwipeFor(ebookId: string): void {
    if (this.isEBookMultiSelectMode) { return; }
    this.activeEBookSwipeId = ebookId;
    this.isEBookSwipeActive = true;
    this.ebookSwipeOffset = 0;
    logger.info(TAG, `长按激活电子书左滑删除: ${ebookId}`);
  }

  private updateEBookSwipeOffset(ebookId: string, event: GestureEvent): void {
    if (!this.isEBookSwipeActive || this.activeEBookSwipeId !== ebookId) { return; }
    const deltaX: number = -event.offsetX;
    const maxHintWidth: number = 120;
    const newOffset: number = Math.max(0, deltaX);
    this.ebookSwipeOffset = Math.min(newOffset, maxHintWidth);
  }

  private endEBookSwipe(ebookId: string): void {
    if (!this.isEBookSwipeActive || this.activeEBookSwipeId !== ebookId) { return; }
    const reached: boolean = this.ebookSwipeOffset >= this.swipeThreshold;
    this.isEBookSwipeActive = false;
    if (reached) {
      this.showDeleteEBookDialog(ebookId);
    } else {
      this.resetEBookSwipeState();
    }
  }

  private resetEBookSwipeState(): void {
    this.activeEBookSwipeId = '';
    this.isEBookSwipeActive = false;
    this.ebookSwipeOffset = 0;
  }

  private getEBookSwipeOffset(ebookId: string): number {
    return (this.activeEBookSwipeId === ebookId && this.isEBookSwipeActive) ? this.ebookSwipeOffset : 0;
  }

  private getEBookSwipeProgressText(ebookId: string): string {
    const progress: number = this.activeEBookSwipeId === ebookId ? Math.min(100, Math.floor((this.getEBookSwipeOffset(ebookId) / this.swipeThreshold) * 100)) : 0;
    return progress >= 100 ? '释放删除' : `左滑 ${progress}%`;
  }

  private getEBookById(ebookId: string): EBook | null {
    for (let i: number = 0; i < this.filteredEbookList.length; i++) {
      const e: EBook = this.filteredEbookList[i];
      if (e.id === ebookId) { return e; }
    }
    return null;
  }

  /**
   * 显示删除电子书确认对话框
   */
  private showDeleteEBookDialog(ebookId: string): void {
    const ebook = this.getEBookById(ebookId);
    if (!ebook) {
      logger.error(TAG, `未找到电子书ID为 ${ebookId} 的电子书`);
      this.resetEBookSwipeState();
      return;
    }

    logger.info(TAG, `显示删除电子书确认对话框: ${ebook.metadata.title} (ID: ${ebookId})`);

    this.getUIContext().showAlertDialog({
      title: '删除电子书',
      message: `确定要删除电子书"${ebook.metadata.title}"吗？\n\n此操作将删除该电子书的所有数据和文件，且不可恢复。`,
      autoCancel: true,
      alignment: DialogAlignment.Center,
      primaryButton: {
        value: '取消',
        action: () => {
          logger.info(TAG, '用户取消删除电子书');
          this.resetEBookSwipeState();
        }
      },
      secondaryButton: {
        value: '删除',
        fontColor: ThemeAwareHelper.getTestManagementThemedColor('button_danger', this.themeState.currentTheme),
        action: async () => {
          try {
            logger.info(TAG, `开始删除电子书: ${ebookId}`);
            await this.ebookDataManager.deleteEBook(ebookId);

            const newEbookList: EBook[] = [];
            for (let i: number = 0; i < this.ebookList.length; i++) {
              const eb: EBook = this.ebookList[i];
              if (eb.id !== ebookId) { newEbookList.push(eb); }
            }
            this.ebookList = newEbookList;

            // 触发动画
            await this.applyEBookFilter();

            this.showToast('电子书已删除');
            logger.info(TAG, `电子书删除成功: ${ebookId}`);
            this.resetEBookSwipeState();
          } catch (error) {
            logger.error(TAG, '删除电子书失败', String(error));
            this.showToast('删除失败');
            this.resetEBookSwipeState();
          }
        }
      }
    });
  }

  /**
   * 构建电子书Grid卡片
   */
  @Builder
  buildEBookGridCard(ebook: EBook) {
    Stack() {
      Column({ space: 8 }) {
        // 封面区域
        Stack() {
          Column() {
            if (this.hasValidEBookCover(ebook)) {
              Image(this.getEBookCoverSource(ebook))
                .width('100%')
                .height('100%')
                .objectFit(ImageFit.Cover)
            } else {
              Image(this.getEBookCoverSource(ebook))
                .width(60)
                .height(60)
                .objectFit(ImageFit.Cover)
                .fillColor(ThemeAwareHelper.getTestManagementThemedColor('accent_primary', this.themeState.currentTheme))
            }
          }
          .width('100%')
          .height(140)
          .backgroundColor(ThemeAwareHelper.getTestManagementThemedColor('comp_background_tertiary', this.themeState.currentTheme))
          .borderRadius(8)
          .justifyContent(FlexAlign.Center)
          .shadow({
            radius: 8,
            color: '#1F000000',
            offsetY: 4
          })

          // 选中状态遮罩
          if (this.isEBookMultiSelectMode && this.selectedEBookIds.has(ebook.id)) {
            Column()
              .width('100%')
              .height('100%')
              .backgroundColor('#80007DFF')
              .borderRadius(8)
          }

          // 选中图标
          if (this.isEBookMultiSelectMode) {
            Column() {
              Image($r('app.media.ic_check'))
                .width(24)
                .height(24)
                .fillColor(this.selectedEBookIds.has(ebook.id)
                  ? ThemeAwareHelper.getTestManagementThemedColor('text_white', this.themeState.currentTheme)
                  : '#80FFFFFF')
                .backgroundColor(this.selectedEBookIds.has(ebook.id)
                  ? ThemeAwareHelper.getTestManagementThemedColor('accent_blue', this.themeState.currentTheme)
                  : '#40000000')
                .borderRadius(12)
                .padding(4)
            }
            .width('100%')
            .height('100%')
            .justifyContent(FlexAlign.End)
            .alignItems(HorizontalAlign.End)
            .padding(8)
          }
        }

        // 书籍信息
        Column({ space: 4 }) {
          Text(ebook.metadata.title)
            .fontSize(14)
            .fontWeight(FontWeight.Medium)
            .fontFamily(this.appFontFamily)
            .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_primary', this.themeState.currentTheme))
            .maxLines(2)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
            .width('100%')
            .textAlign(TextAlign.Center)

          Text(ebook.metadata.author)
            .fontSize(12)
            .fontFamily(this.appFontFamily)
            .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_secondary', this.themeState.currentTheme))
            .maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
            .width('100%')
            .textAlign(TextAlign.Center)

          // 阅读进度
          if (ebook.readingProgress && ebook.readingProgress.progress > 0) {
            Row({ space: 4 }) {
              Progress({
                value: ebook.readingProgress.progress,
                total: 100,
                type: ProgressType.Linear
              })
                .width(60)
                .height(4)
                .color(ThemeAwareHelper.getTestManagementThemedColor('accent_primary', this.themeState.currentTheme))

              Text(`${Math.floor(ebook.readingProgress.progress)}%`)
                .fontSize(10)
                .fontFamily(this.appFontFamily)
                .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_muted', this.themeState.currentTheme))
            }
          }
        }
        .width('100%')
        .padding({ left: 8, right: 8 })
      }
      .width('100%')
      .padding(8)
      .backgroundColor(this.getGlassBackground())
      .backgroundBlurStyle(this.getGlassBlur())
      .borderRadius(this.getGlassRadius())
      .border({
        width: this.isEBookMultiSelectMode && this.selectedEBookIds.has(ebook.id) ? 2 : 0,
        color: ThemeAwareHelper.getTestManagementThemedColor('accent_blue', this.themeState.currentTheme)
      })
    }
    .onClick(() => {
      if (this.isEBookMultiSelectMode) {
        // 多选模式：切换选中状态
        this.toggleEBookSelection(ebook.id);
      } else {
        // 普通模式：打开详情页
        this.openEBookDetail(ebook);
      }
    })
    .bindContextMenu(this.buildEBookGridContextMenu(ebook), ResponseType.LongPress)
  }

  /**
   * 构建小说List卡片
   */
  @Builder
  buildNovelCard(novel: NovelBook) {
    Row({ space: 12 }) {
      // 封面图片
      Column() {
        if (novel.coverUrl || novel.coverLocalPath) {
          Image(novel.coverLocalPath || novel.coverUrl || '')
            .width('100%')
            .height('100%')
            .objectFit(ImageFit.Cover)
        } else {
          Image($r('app.media.ic_source_novel'))
            .width(50)
            .height(50)
            .fillColor(ThemeAwareHelper.getTestManagementThemedColor('accent_primary', this.themeState.currentTheme))
        }
      }
      .width(80)
      .height(120)
      .backgroundColor(ThemeAwareHelper.getTestManagementThemedColor('comp_background_tertiary', this.themeState.currentTheme))
      .borderRadius(8)
      .justifyContent(FlexAlign.Center)
      .shadow({ radius: 8, color: '#1F000000', offsetY: 4 })

      // 小说信息
      Column({ space: 6 }) {
        Text(novel.name)
          .fontSize(16)
          .fontWeight(FontWeight.Medium)
          .fontFamily(this.appFontFamily)
          .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_primary', this.themeState.currentTheme))
          .maxLines(2)
          .textOverflow({ overflow: TextOverflow.Ellipsis })

        Text(novel.author || '未知作者')
          .fontSize(13)
          .fontFamily(this.appFontFamily)
          .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_secondary', this.themeState.currentTheme))
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })

        Text(novel.sourceName || '未知来源')
          .fontSize(12)
          .fontFamily(this.appFontFamily)
          .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_muted', this.themeState.currentTheme))
          .maxLines(1)

        Blank()

        // 阅读状态和章节数
        Row({ space: 8 }) {
          Text(this.getNovelReadStatusText(novel.readStatus))
            .fontSize(11)
            .fontFamily(this.appFontFamily)
            .fontColor(ThemeAwareHelper.getTestManagementThemedColor('accent_primary', this.themeState.currentTheme))
            .padding({ left: 6, right: 6, top: 2, bottom: 2 })
            .backgroundColor(ThemeAwareHelper.getTestManagementThemedColor('accent_primary_dimmed', this.themeState.currentTheme))
            .borderRadius(4)

          Text(`${novel.chapterCount}章`)
            .fontSize(11)
            .fontFamily(this.appFontFamily)
            .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_muted', this.themeState.currentTheme))
        }
      }
      .layoutWeight(1)
      .alignItems(HorizontalAlign.Start)
      .height(120)
    }
    .width('100%')
    .padding(12)
    .backgroundColor(this.getGlassBackground())
    .backgroundBlurStyle(this.getGlassBlur())
    .borderRadius(this.getGlassRadius())
    .onClick(() => {
      this.openNovelDetail(novel);
    })
    .bindContextMenu(this.buildNovelContextMenu(novel), ResponseType.LongPress)
  }

  /**
   * 构建小说Grid卡片
   */
  @Builder
  buildNovelGridCard(novel: NovelBook) {
    Column({ space: 8 }) {
      // 封面区域
      Stack() {
        Column() {
          if (novel.coverUrl || novel.coverLocalPath) {
            Image(novel.coverLocalPath || novel.coverUrl || '')
              .width('100%')
              .height('100%')
              .objectFit(ImageFit.Cover)
          } else {
            Image($r('app.media.ic_source_novel'))
              .width(60)
              .height(60)
              .fillColor(ThemeAwareHelper.getTestManagementThemedColor('accent_primary', this.themeState.currentTheme))
          }
        }
        .width('100%')
        .height(140)
        .backgroundColor(ThemeAwareHelper.getTestManagementThemedColor('comp_background_tertiary', this.themeState.currentTheme))
        .borderRadius(8)
        .justifyContent(FlexAlign.Center)
        .shadow({ radius: 8, color: '#1F000000', offsetY: 4 })

        // 阅读状态标签
        Text(this.getNovelReadStatusText(novel.readStatus))
          .fontSize(10)
          .fontFamily(this.appFontFamily)
          .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_white', this.themeState.currentTheme))
          .padding({ left: 6, right: 6, top: 2, bottom: 2 })
          .backgroundColor(ThemeAwareHelper.getTestManagementThemedColor('accent_primary', this.themeState.currentTheme))
          .borderRadius(4)
          .position({ x: 4, y: 4 })
      }
      .width('100%')

      // 小说标题
      Text(novel.name)
        .fontSize(13)
        .fontWeight(FontWeight.Medium)
        .fontFamily(this.appFontFamily)
        .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_primary', this.themeState.currentTheme))
        .maxLines(2)
        .textOverflow({ overflow: TextOverflow.Ellipsis })
        .width('100%')

      // 作者
      Text(novel.author || '未知作者')
        .fontSize(11)
        .fontFamily(this.appFontFamily)
        .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_secondary', this.themeState.currentTheme))
        .maxLines(1)
        .textOverflow({ overflow: TextOverflow.Ellipsis })
        .width('100%')
    }
    .width('100%')
    .padding(8)
    .backgroundColor(this.getGlassBackground())
    .backgroundBlurStyle(this.getGlassBlur())
    .borderRadius(this.getGlassRadius())
    .onClick(() => {
      this.openNovelDetail(novel);
    })
    .bindContextMenu(this.buildNovelContextMenu(novel), ResponseType.LongPress)
  }

  /**
   * 获取小说阅读状态文本
   */
  private getNovelReadStatusText(status: NovelReadStatus): string {
    switch (status) {
      case NovelReadStatus.UNREAD:
        return '未读';
      case NovelReadStatus.READING:
        return '阅读中';
      case NovelReadStatus.FINISHED:
        return '已完成';
      default:
        return '未读';
    }
  }

  /**
   * 打开小说详情页
   */
  private openNovelDetail(novel: NovelBook): void {
    const params: NovelDetailPageParams = {
      sourceId: novel.sourceId,
      bookUrl: novel.bookUrl,
      bookName: novel.name,
      author: novel.author,
      coverUrl: novel.coverUrl
    };
    this.pathStack.pushPathByName('NovelDetailPage', params);
  }

  /**
   * 构建PDF电子书List卡片（显示在电子书列表中，但使用漫画阅读器）
   */
  @Builder
  buildPdfEBookCard(manga: Manga) {
    Row({ space: 12 }) {
      // 封面图片
      Column() {
        Image(this.normalizeDisplayPathForManga(manga) || $r('app.media.ic_ebook'))
          .width('100%')
          .height('100%')
          .objectFit(ImageFit.Cover)
      }
      .width(80)
      .height(120)
      .backgroundColor(ThemeAwareHelper.getTestManagementThemedColor('comp_background_tertiary', this.themeState.currentTheme))
      .borderRadius(8)
      .justifyContent(FlexAlign.Center)
      .shadow({
        radius: 8,
        color: '#1F000000',
        offsetY: 4
      })

      // 电子书信息
      Column({ space: 8 }) {
        Row({ space: 8 }) {
          Text(manga.title)
            .fontSize(16)
            .fontWeight(FontWeight.Medium)
            .fontFamily(this.appFontFamily)
            .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_primary', this.themeState.currentTheme))
            .maxLines(2)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
            .layoutWeight(1)

          // PDF标识
          Text('PDF')
            .fontSize(10)
            .fontFamily(this.appFontFamily)
            .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_white', this.themeState.currentTheme))
            .backgroundColor('#FF6B6B')
            .padding({ left: 6, right: 6, top: 2, bottom: 2 })
            .borderRadius(4)
        }
        .width('100%')

        Text(`${manga.metadata.authors.length > 0 ? manga.metadata.authors[0] : '未知作者'} · PDF电子书`)
          .fontSize(14)
          .fontFamily(this.appFontFamily)
          .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_secondary', this.themeState.currentTheme))

        Text(manga.description || '暂无简介')
          .fontSize(12)
          .fontFamily(this.appFontFamily)
          .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_muted', this.themeState.currentTheme))
          .maxLines(2)
          .textOverflow({ overflow: TextOverflow.Ellipsis })

        Blank()

        // 操作按钮
        Row({ space: 12 }) {
          if (manga.readingProgress && manga.readingProgress.currentPageIndex > 0) {
            Text(`已读 ${manga.readingProgress.currentPageIndex + 1} 页`)
              .fontSize(12)
              .fontFamily(this.appFontFamily)
              .fontColor(ThemeAwareHelper.getTestManagementThemedColor('accent_primary', this.themeState.currentTheme))
          }

          Blank()

          // 根据阅读进度显示不同的按钮文本
          Button(this.hasMangaReadingProgress(manga) ? '继续阅读' : '开始阅读')
            .fontSize(14)
            .height(32)
            .fontFamily(this.appFontFamily)
            .padding({ left: 16, right: 16 })
            .backgroundColor(ThemeAwareHelper.getTestManagementThemedColor('accent_primary', this.themeState.currentTheme))
            .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_white', this.themeState.currentTheme))
            .onClick(() => {
              // 使用漫画阅读器打开PDF电子书
              this.openMangaReader(manga);
            })
        }
        .width('100%')
      }
      .layoutWeight(1)
      .alignItems(HorizontalAlign.Start)
      .justifyContent(FlexAlign.SpaceBetween)
    }
    .width('100%')
    .height(140)
    .padding(12)
    .backgroundColor(this.getGlassBackground())
    .backgroundBlurStyle(this.getGlassBlur())
    .borderRadius(this.getGlassRadius())
    .shadow({
      radius: this.getGlassRadius(),
      color: this.getGlassShadowColor(),
      offsetY: 2
    })
    .onClick(() => {
      // 点击卡片打开漫画详情页
      this.openMangaDetail(manga);
    })
  }

  /**
   * 构建PDF电子书Grid卡片（显示在电子书列表中，但使用漫画阅读器）
   */
  @Builder
  buildPdfEBookGridCard(manga: Manga) {
    Stack() {
      Column({ space: 8 }) {
        // 封面区域
        Stack() {
          Column() {
            Image(this.normalizeDisplayPathForManga(manga) || $r('app.media.ic_ebook'))
              .width('100%')
              .height('100%')
              .objectFit(ImageFit.Cover)
          }
          .width('100%')
          .height(140)
          .backgroundColor(ThemeAwareHelper.getTestManagementThemedColor('comp_background_tertiary', this.themeState.currentTheme))
          .borderRadius(8)
          .justifyContent(FlexAlign.Center)
          .shadow({
            radius: 8,
            color: '#1F000000',
            offsetY: 4
          })

          // PDF标识
          Column() {
            Text('PDF')
              .fontSize(10)
              .fontFamily(this.appFontFamily)
              .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_white', this.themeState.currentTheme))
              .backgroundColor('#FF6B6B')
              .padding({ left: 6, right: 6, top: 2, bottom: 2 })
              .borderRadius(4)
          }
          .width('100%')
          .height('100%')
          .justifyContent(FlexAlign.Start)
          .alignItems(HorizontalAlign.End)
          .padding(8)
        }

        // 书籍信息
        Column({ space: 4 }) {
          Text(manga.title)
            .fontSize(14)
            .fontWeight(FontWeight.Medium)
            .fontFamily(this.appFontFamily)
            .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_primary', this.themeState.currentTheme))
            .maxLines(2)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
            .width('100%')
            .textAlign(TextAlign.Center)

          Text(manga.metadata.authors.length > 0 ? manga.metadata.authors[0] : '未知作者')
            .fontSize(12)
            .fontFamily(this.appFontFamily)
            .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_secondary', this.themeState.currentTheme))
            .maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
            .width('100%')
            .textAlign(TextAlign.Center)

          // 阅读进度（PDF电子书GRID模式）- 显示当前阅读页数
          if (manga.readingProgress && (manga.readingProgress.currentChapterId || manga.readingProgress.currentPageIndex > 0)) {
            Text(`已读 ${manga.readingProgress.currentPageIndex + 1} 页`)
              .fontSize(10)
              .fontFamily(this.appFontFamily)
              .fontColor(ThemeAwareHelper.getTestManagementThemedColor('accent_primary', this.themeState.currentTheme))
          }
        }
        .width('100%')
        .padding({ left: 8, right: 8 })
      }
      .width('100%')
      .padding(8)
      .backgroundColor(this.getGlassBackground())
      .backgroundBlurStyle(this.getGlassBlur())
      .borderRadius(this.getGlassRadius())
    }
    .onClick(() => {
      // 点击打开漫画详情页
      this.openMangaDetail(manga);
    })
  }

  /**
   * 构建书库筛选Popup
   */
  @Builder
  buildLibraryFilterPopup() {
    Column() {
      Text(this.libraryContentType === LibraryContentType.MANGA ? '筛选漫画' : '筛选电子书')
        .fontSize(16)
        .fontWeight(FontWeight.Medium)
        .fontFamily(this.appFontFamily)
        .margin({ bottom: 12 })

      Button('全部')
        .width('100%')
        .fontFamily(this.appFontFamily)
        .margin({ bottom: 8 })
        .onClick(() => {
          this.libraryFilterType = LibraryFilterType.ALL;
          if (this.libraryContentType === LibraryContentType.MANGA) {
            this.applyLibraryFilter();
          } else {
            this.applyEBookFilter();
          }
          this.showLibraryFilterPopup = false;
        })

      Button('未读')
        .width('100%')
        .fontFamily(this.appFontFamily)
        .margin({ bottom: 8 })
        .onClick(() => {
          this.libraryFilterType = LibraryFilterType.UNREAD;
          if (this.libraryContentType === LibraryContentType.MANGA) {
            this.applyLibraryFilter();
          } else {
            this.applyEBookFilter();
          }
          this.showLibraryFilterPopup = false;
        })

      Button('阅读中')
        .width('100%')
        .fontFamily(this.appFontFamily)
        .margin({ bottom: 8 })
        .onClick(() => {
          this.libraryFilterType = LibraryFilterType.READING;
          if (this.libraryContentType === LibraryContentType.MANGA) {
            this.applyLibraryFilter();
          } else {
            this.applyEBookFilter();
          }
          this.showLibraryFilterPopup = false;
        })
    }
    .padding(16)
  }

  /**
   * 构建书库筛选对话框
   */
  @Builder
  buildLibraryFilterDialog() {
    Stack({ alignContent: Alignment.Center }) {
      // 半透明遮罩
      Column()
        .width('100%')
        .height('100%')
        .backgroundColor('#80000000')
        .onClick(() => {
          this.showLibraryFilterDialog = false;
        })

      // 筛选弹窗
      Column({ space: 16 }) {
        // 标题
        Row() {
          Text(this.libraryContentType === LibraryContentType.MANGA ? '筛选漫画' : '筛选电子书')
            .fontSize(18)
            .fontWeight(FontWeight.Bold)
            .fontFamily(this.appFontFamily)
            .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_primary', this.themeState.currentTheme))
            .layoutWeight(1)

          Button('✕')
            .fontSize(20)
            .fontFamily(this.appFontFamily)
            .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_muted', this.themeState.currentTheme))
            .backgroundColor(Color.Transparent)
            .width(32)
            .height(32)
            .onClick(() => {
              this.showLibraryFilterDialog = false;
            })
        }
        .width('100%')

        // 筛选选项
        Column({ space: 12 }) {
          this.buildFilterOption('全部', LibraryFilterType.ALL)
          this.buildFilterOption('未读', LibraryFilterType.UNREAD)
          this.buildFilterOption('阅读中', LibraryFilterType.READING)
        }
        .width('100%')
      }
      .width('89%')
      .padding(20)
      .backgroundColor(this.getGlassBackground())
      .backgroundBlurStyle(this.getGlassBlur())
      .borderRadius(this.getGlassRadius())
      .shadow({ radius: this.getGlassRadius(), color: this.getGlassShadowColor(), offsetX: 0, offsetY: 4 })
    }
    .width('100%')
    .height('100%')
    .zIndex(1000)
  }

  /**
   * 构建筛选选项
   */
  @Builder
  buildFilterOption(label: string, filterType: LibraryFilterType) {
    Row() {
      Text(label)
        .fontSize(16)
        .fontFamily(this.appFontFamily)
        .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_primary', this.themeState.currentTheme))
        .layoutWeight(1)

      if (this.libraryFilterType === filterType) {
        SymbolGlyph($r('sys.symbol.checkmark'))
          .fontSize(20)
          .fontColor([ThemeAwareHelper.getTestManagementThemedColor('accent_blue', this.themeState.currentTheme)])
      }
    }
    .width('100%')
    .padding({ left: 12, right: 12, top: 12, bottom: 12 })
    .backgroundColor(this.libraryFilterType === filterType
      ? ThemeAwareHelper.getTestManagementThemedColor('accent_primary', this.themeState.currentTheme)
      : Color.Transparent)
    .borderRadius(8)
    .onClick(() => {
      this.libraryFilterType = filterType;
      if (this.libraryContentType === LibraryContentType.MANGA) {
        this.applyLibraryFilter();
      } else {
        this.applyEBookFilter();
      }
      this.showLibraryFilterDialog = false;
      logger.info(TAG, `筛选已更改为: ${filterType}`);
    })
  }

  /**
   * 打开漫画详情页
   */
  private async openMangaDetail(manga: Manga) {
    try {
      // [修复] 查询漫画的sourceId（同时查询本地和在线漫画）
      let sourceId: number | undefined = undefined;
      try {
        // 优先从manga.sourceInfo获取
        if (manga.sourceInfo?.sourceId) {
          sourceId = Number(manga.sourceInfo.sourceId);
          logger.info(TAG, `从manga.sourceInfo获取sourceId: ${sourceId}`);
        } else {
          // 回退：从数据库查询
          const comicInfo = await this.dataManager.getComicById(manga.id);
          if (comicInfo && comicInfo.sourceId) {
            sourceId = Number(comicInfo.sourceId);
            logger.info(TAG, `从comic_info表获取sourceId: ${sourceId}`);
          } else {
            // 尝试从online_comic_info表查询
            const onlineComicInfo = await this.dataManager.getOnlineComicInfoById(manga.id);
            if (onlineComicInfo && onlineComicInfo.sourceId) {
              sourceId = Number(onlineComicInfo.sourceId);
              logger.info(TAG, `从online_comic_info表获取sourceId: ${sourceId}`);
            }
          }
        }
      } catch (err) {
        logger.warn(TAG, `获取漫画sourceId失败: ${String(err)}`);
      }

      const params: MangaDetailPageParams = {
        mangaId: manga.id,
        sourceId: sourceId
      };

      this.pathStack.pushPathByName('MangaDetailPage', params);
      logger.info(TAG, `打开漫画详情页: ${manga.title}`);
    } catch (error) {
      logger.error(TAG, '打开漫画详情页失败', String(error));
      this.showToast('打开漫画详情页失败');
    }
  }

  /**
   * 打开漫画阅读器
   */

  /**
   * 打开漫画阅读器
   */
  private async openMangaReader(manga: Manga) {
    try {
      const comicInfo: ComicInfo | null = await this.dataManager.getComicById(manga.id);
      let sourceIdNum: number = -1;
      let hasWebSource: boolean = false;
      if (comicInfo && typeof comicInfo.sourceId === 'string' && comicInfo.sourceId.length > 0) {
        const parsed: number = Number(comicInfo.sourceId);
        if (!isNaN(parsed)) {
          sourceIdNum = parsed;
          hasWebSource = true;
          logger.info(TAG, `漫画 ${manga.title} 的sourceId: ${sourceIdNum}`);
        }
      }
      let sourceNameVal: string = 'LOCAL';
      if (hasWebSource) {
        const srcRecord: ComicSourceDatabaseRecord | null = await this.dataManager.getComicSourceById(sourceIdNum);
        if (srcRecord && typeof srcRecord.name === 'string' && srcRecord.name.length > 0) {
          sourceNameVal = srcRecord.name;
        } else {
          sourceNameVal = 'WEBVIEW';
        }
      }

      const target = await this.determineResumeTarget(manga);
      if (!target) {
        // [重构] 根据是否为在线漫画选择加载方法
        if (hasWebSource) {
          // 在线漫画：从online_chapter表加载
          const onlineChapterInfos = await this.dataManager.getOnlineComicChapters(manga.id);
          if (onlineChapterInfos && onlineChapterInfos.length > 0) {
            let firstChapterId: string = onlineChapterInfos[0].id;
            let minChapterNumber: number = onlineChapterInfos[0].chapterNumber;
            for (let i: number = 1; i < onlineChapterInfos.length; i++) {
              const info = onlineChapterInfos[i];
              if (info.chapterNumber < minChapterNumber) {
                minChapterNumber = info.chapterNumber;
                firstChapterId = info.id;
              }
            }
            const ct: MangaReaderContentType = onlineChapterInfos[0].isDownloaded
              ? MangaReaderContentType.OnlineDownloaded
              : MangaReaderContentType.OnlineUndownloaded;

            const paramsFallback: MangaReaderPageParams = {
              mangaId: manga.id,
              chapterId: firstChapterId,
              pageIndex: 0,
              fromPage: 'MainMenuPage',
              contentType: ct,
              sourceId: sourceIdNum,
              sourceName: sourceNameVal
            } as MangaReaderPageParams;
            this.pathStack.pushPathByName('MangaReaderPage', paramsFallback);
            logger.info(TAG, `无阅读记录，默认第一章（在线）：chapterId=${firstChapterId}, contentType=${String(ct)}`);
            return;
          } else {
            logger.warn(TAG, `在线漫画(${manga.title})未找到章节，无法进入阅读器`);
            this.showToast('未找到章节，无法进入阅读器');
            return;
          }
        } else {
          // 本地漫画：从chapter表加载
          const chapterInfos = await this.dataManager.getComicChapters(manga.id);
          if (chapterInfos && chapterInfos.length > 0) {
            let firstChapterId: string = chapterInfos[0].id;
            let minIndex: number = chapterInfos[0].index;
            for (let i: number = 1; i < chapterInfos.length; i++) {
              const info = chapterInfos[i];
              if (info.index < minIndex) {
                minIndex = info.index;
                firstChapterId = info.id;
              }
            }
            const ct: MangaReaderContentType = MangaReaderContentType.Local;
            const paramsFallback: MangaReaderPageParams = {
              mangaId: manga.id,
              chapterId: firstChapterId,
              pageIndex: 0,
              fromPage: 'MainMenuPage',
              contentType: ct,
              sourceId: undefined,
              sourceName: sourceNameVal
            } as MangaReaderPageParams;
            this.pathStack.pushPathByName('MangaReaderPage', paramsFallback);
            logger.info(TAG, `无阅读记录，默认第一章（本地）：chapterId=${firstChapterId}`);
            return;
          } else {
            logger.warn(TAG, `本地漫画(${manga.title})未找到章节，无法进入阅读器`);
            this.showToast('未找到章节，无法进入阅读器');
            return;
          }
        }
      }

      // [重构] 根据是否为在线漫画选择章节查询方法
      let ct2: MangaReaderContentType = MangaReaderContentType.Local;
      if (hasWebSource) {
        const targetChapterInfo = await this.dataManager.getOnlineChapterById(target.chapterId);
        if (targetChapterInfo && targetChapterInfo.isDownloaded) {
          ct2 = MangaReaderContentType.OnlineDownloaded;
        } else {
          ct2 = MangaReaderContentType.OnlineUndownloaded;
        }
      }
      const params: MangaReaderPageParams = {
        mangaId: manga.id,
        chapterId: target.chapterId,
        pageIndex: target.pageIndex,
        fromPage: 'MainMenuPage',
        contentType: ct2,
        sourceId: hasWebSource ? sourceIdNum : undefined,
        sourceName: sourceNameVal
      } as MangaReaderPageParams;

      this.pathStack.pushPathByName('MangaReaderPage', params);
      logger.info(TAG, `打开漫画阅读器: ${manga.title}, 恢复到章节 ${target.chapterId}, 页 ${String(target.pageIndex)}, contentType=${String(ct2)}, sourceId=${hasWebSource ? String(sourceIdNum) : '未指定'}`);
    } catch (error) {
      const errMsg: string = error instanceof Error ? error.message : String(error);
      logger.error(TAG, '打开漫画阅读器失败', errMsg);
      this.showToast('打开漫画阅读器失败');
    }
  }

  private async determineResumeTarget(manga: Manga): Promise<ResumeTarget | null> {
    try {
      const historyList: ReadHistory[] = await this.dataManager.getReadHistoryByComic(manga.id, 'default_user', 1000);
      let latest: ReadHistory | null = null;
      let latestTime: number = 0;
      for (let i: number = 0; i < historyList.length; i++) {
        const h: ReadHistory = historyList[i] as ReadHistory;
        if (h.readTime > latestTime) {
          latestTime = h.readTime;
          latest = h;
        }
      }

      if (latest) {
        const latestSafe: ReadHistory = latest as ReadHistory;
        const latestChapterId: string = latestSafe.chapterId;
        let resumeIndex: number = latestSafe.pageIndex >= 0 ? latestSafe.pageIndex : 0;
        if (manga.chapters && manga.chapters.length > 0) {
          const ch: MangaChapter | undefined = manga.chapters.find((c: MangaChapter) => c.id === latestChapterId);
          if (ch) {
            const total: number = ch.pages.length;
            if (total > 0 && resumeIndex >= total) {
              resumeIndex = total - 1;
            }
          } else {
            try {
              const pages: PageInfo[] = await this.dataManager.getPageInfoList(latestChapterId);
              const totalPages: number = pages.length;
              if (totalPages > 0 && resumeIndex >= totalPages) {
                resumeIndex = totalPages - 1;
              }
            } catch (pageErr) {
              logger.warn(TAG, String(pageErr));
            }
          }
        }
        return { chapterId: latestChapterId, pageIndex: resumeIndex } as ResumeTarget;
      }
    } catch (err) {
      logger.warn(TAG, String(err));
    }

    const rp: ReadingProgress = manga.readingProgress as ReadingProgress;
    if (rp && rp.currentChapterId && rp.currentChapterId.length > 0) {
      let idx: number = rp.currentPageIndex >= 0 ? rp.currentPageIndex : 0;
      if (manga.chapters && manga.chapters.length > 0) {
        const ch2: MangaChapter | undefined = manga.chapters.find((c: MangaChapter) => c.id === rp.currentChapterId);
        if (ch2) {
          const tp: number = ch2.pages.length;
          if (tp > 0 && idx >= tp) {
            idx = tp - 1;
          }
        }
      }
      return { chapterId: rp.currentChapterId, pageIndex: idx } as ResumeTarget;
    }

    if (manga.chapters && manga.chapters.length > 0) {
      let firstChapter: MangaChapter = manga.chapters[0];
      for (let i: number = 1; i < manga.chapters.length; i++) {
        const ch: MangaChapter = manga.chapters[i];
        if (ch.chapterNumber < firstChapter.chapterNumber) {
          firstChapter = ch;
        }
      }
      return { chapterId: firstChapter.id, pageIndex: 0 } as ResumeTarget;
    }

    try {
      const chapterInfos = await this.dataManager.getComicChapters(manga.id);
      if (chapterInfos && chapterInfos.length > 0) {
        let firstChapterId: string = chapterInfos[0].id;
        let minIndex: number = chapterInfos[0].index;
        for (let i: number = 1; i < chapterInfos.length; i++) {
          const info = chapterInfos[i];
          if (info.index < minIndex) {
            minIndex = info.index;
            firstChapterId = info.id;
          }
        }
        return { chapterId: firstChapterId, pageIndex: 0 } as ResumeTarget;
      }
    } catch (err2) {
      logger.warn(TAG, String(err2));
    }
    return null;
  }

  /**
   * 构建标签选择弹窗
   */
  @Builder
  buildTagPopup() {
    Column({ space: 0 }) {
      // 标题栏
      Row() {
        Text(`选择标签 (${this.allTags.length})`)
          .fontSize(16)
          .fontWeight(FontWeight.Medium)
          .fontFamily(this.appFontFamily)
          .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_primary', this.themeState.currentTheme))

        Blank()

        if (this.selectedTags.size > 0) {
          Text('清除全部')
            .fontSize(13)
            .fontFamily(this.appFontFamily)
            .fontColor(ThemeAwareHelper.getTestManagementThemedColor('accent_primary', this.themeState.currentTheme))
            .onClick(() => {
              this.clearTagSelection();
            })
        }
      }
      .width('100%')
      .padding({ left: 16, right: 16, top: 12, bottom: 8 })

      // 标签列表
      Scroll() {
        Flex({ wrap: FlexWrap.Wrap, justifyContent: FlexAlign.Start }) {
          ForEach(this.allTags, (tag: string) => {
            Text(tag)
              .fontSize(13)
              .fontFamily(this.appFontFamily)
              .padding({ left: 12, right: 12, top: 6, bottom: 6 })
              .margin({ right: 8, bottom: 8 })
              .backgroundColor(this.selectedTags.has(tag)
                ? ThemeAwareHelper.getTestManagementThemedColor('accent_primary', this.themeState.currentTheme)
                : ThemeAwareHelper.getTestManagementThemedColor('background_secondary', this.themeState.currentTheme))
              .fontColor(this.selectedTags.has(tag)
                ? ThemeAwareHelper.getTestManagementThemedColor('text_white', this.themeState.currentTheme)
                : ThemeAwareHelper.getTestManagementThemedColor('text_primary', this.themeState.currentTheme))
              .borderRadius(16)
              .onClick(() => {
                this.toggleTagSelection(tag);
              })
          }, (tag: string) => tag)
        }
        .width('100%')
        .padding({ left: 16, right: 16, bottom: 12 })
      }
      .constraintSize({ maxHeight: 300 })
      .scrollBar(BarState.Auto)
    }
    .width(320)
    .backgroundColor(ThemeAwareHelper.getTestManagementThemedColor('panel_background', this.themeState.currentTheme))
    .borderRadius(12)
  }

  /**
   * 构建作者选择弹窗
   */
  @Builder
  buildAuthorPopup() {
    Column({ space: 0 }) {
      // 标题栏
      Row() {
        Text(`选择作者 (${this.allAuthors.length})`)
          .fontSize(16)
          .fontWeight(FontWeight.Medium)
          .fontFamily(this.appFontFamily)
          .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_primary', this.themeState.currentTheme))

        Blank()

        if (this.selectedAuthors.size > 0) {
          Text('清除全部')
            .fontSize(13)
            .fontFamily(this.appFontFamily)
            .fontColor(ThemeAwareHelper.getTestManagementThemedColor('accent_primary', this.themeState.currentTheme))
            .onClick(() => {
              this.clearAuthorSelection();
            })
        }
      }
      .width('100%')
      .padding({ left: 16, right: 16, top: 12, bottom: 8 })

      // 作者列表
      Scroll() {
        Flex({ wrap: FlexWrap.Wrap, justifyContent: FlexAlign.Start }) {
          ForEach(this.allAuthors, (author: string) => {
            Text(author)
              .fontSize(13)
              .fontFamily(this.appFontFamily)
              .padding({ left: 12, right: 12, top: 6, bottom: 6 })
              .margin({ right: 8, bottom: 8 })
              .backgroundColor(this.selectedAuthors.has(author)
                ? ThemeAwareHelper.getTestManagementThemedColor('accent_primary', this.themeState.currentTheme)
                : ThemeAwareHelper.getTestManagementThemedColor('background_secondary', this.themeState.currentTheme))
              .fontColor(this.selectedAuthors.has(author)
                ? ThemeAwareHelper.getTestManagementThemedColor('text_white', this.themeState.currentTheme)
                : ThemeAwareHelper.getTestManagementThemedColor('text_primary', this.themeState.currentTheme))
              .borderRadius(16)
              .onClick(() => {
                this.toggleAuthorSelection(author);
              })
          }, (author: string) => author)
        }
        .width('100%')
        .padding({ left: 16, right: 16, bottom: 12 })
      }
      .constraintSize({ maxHeight: 300 })
      .scrollBar(BarState.Auto)
    }
    .width(320)
    .backgroundColor(ThemeAwareHelper.getTestManagementThemedColor('panel_background', this.themeState.currentTheme))
    .borderRadius(12)
  }

  /**
   * 构建发现内容
   */
  @Builder
  buildDiscoverContent() {
    Column({ space: 0 }) {
      // 搜索栏（横屏时减小高度和padding）
      // Row() {
      //   TextInput({ placeholder: '搜索漫画、作者...' })
      //     .layoutWeight(1)
      //     .height(this.responsive_isLandscape ? 36 : 40)
      //     .backgroundColor(ThemeAwareHelper.getTestManagementThemedColor('background_secondary', this.themeState.currentTheme))
      //     .placeholderColor(ThemeAwareHelper.getTestManagementThemedColor('text_muted', this.themeState.currentTheme))
      //     .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_primary', this.themeState.currentTheme))
      //
      //   Button() {
      //     Image($r('app.media.ic_search'))
      //       .width(20)
      //       .height(20)
      //
      //   }
      //   .width(this.responsive_isLandscape ? 36 : 40)
      //   .height(this.responsive_isLandscape ? 36 : 40)
      //   .backgroundColor(Color.Transparent)
      //   .margin({ left: 8 })
      // }
      // .width('100%')
      // .padding({
      //   left: 16,
      //   right: 16,
      //   top: this.responsive_isLandscape ? 8 : 16
      // })

      // 筛选按钮区域
      Row({ space: 12 }) {
        // 标签筛选按钮
        Row({ space: 6 }) {
          Text('🏷️')
            .fontSize(14)
            .fontFamily(this.appFontFamily)
          Text(this.selectedTags.size > 0 ? `标签 (${this.selectedTags.size})` : '标签')
            .fontSize(14)
            .fontFamily(this.appFontFamily)
            .fontColor(this.selectedTags.size > 0
              ? ThemeAwareHelper.getTestManagementThemedColor('accent_primary', this.themeState.currentTheme)
              : ThemeAwareHelper.getTestManagementThemedColor('text_primary', this.themeState.currentTheme))
          if (this.selectedTags.size > 0) {
            Text('×')
              .fontSize(14)
              .fontFamily(this.appFontFamily)
              .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_muted', this.themeState.currentTheme))
              .onClick(() => {
                this.clearTagSelection();
              })
          }
        }
        .padding({ left: 12, right: 12, top: 8, bottom: 8 })
        .backgroundColor(this.selectedTags.size > 0
          ? ThemeAwareHelper.getTestManagementThemedColor('accent_primary_dimmed', this.themeState.currentTheme)
          : ThemeAwareHelper.getTestManagementThemedColor('background_secondary', this.themeState.currentTheme))
        .borderRadius(20)
        .onClick(() => {
          this.showTagPopup = true;
        })
        .bindPopup(this.showTagPopup, {
          builder: this.buildTagPopup(),
          placement: Placement.Bottom,
          popupColor: ThemeAwareHelper.getTestManagementThemedColor('panel_background', this.themeState.currentTheme),
          enableArrow: true,
          onStateChange: (e) => {
            if (!e.isVisible) {
              this.showTagPopup = false;
            }
          }
        })

        // 作者筛选按钮
        Row({ space: 6 }) {
          Text('👤')
            .fontSize(14)
            .fontFamily(this.appFontFamily)
          Text(this.selectedAuthors.size > 0 ? `作者 (${this.selectedAuthors.size})` : '作者')
            .fontSize(14)
            .fontFamily(this.appFontFamily)
            .fontColor(this.selectedAuthors.size > 0
              ? ThemeAwareHelper.getTestManagementThemedColor('accent_primary', this.themeState.currentTheme)
              : ThemeAwareHelper.getTestManagementThemedColor('text_primary', this.themeState.currentTheme))
          if (this.selectedAuthors.size > 0) {
            Text('×')
              .fontSize(14)
              .fontFamily(this.appFontFamily)
              .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_muted', this.themeState.currentTheme))
              .onClick(() => {
                this.clearAuthorSelection();
              })
          }
        }
        .padding({ left: 12, right: 12, top: 8, bottom: 8 })
        .backgroundColor(this.selectedAuthors.size > 0
          ? ThemeAwareHelper.getTestManagementThemedColor('accent_primary_dimmed', this.themeState.currentTheme)
          : ThemeAwareHelper.getTestManagementThemedColor('background_secondary', this.themeState.currentTheme))
        .borderRadius(20)
        .onClick(() => {
          this.showAuthorPopup = true;
        })
        .bindPopup(this.showAuthorPopup, {
          builder: this.buildAuthorPopup(),
          placement: Placement.Bottom,
          popupColor: ThemeAwareHelper.getTestManagementThemedColor('panel_background', this.themeState.currentTheme),
          enableArrow: true,
          onStateChange: (e) => {
            if (!e.isVisible) {
              this.showAuthorPopup = false;
            }
          }
        })

        Blank()
      }
      .width('100%')
      .padding({ left: 16, right: 16, top: 12, bottom: 8 })

      // 内容类型切换
      Row({ space: 8 }) {
        Text('全部')
          .fontSize(13)
          .fontFamily(this.appFontFamily)
          .padding({ left: 16, right: 16, top: 6, bottom: 6 })
          .backgroundColor(this.discoverContentType === 'all' ?
            ThemeAwareHelper.getTestManagementThemedColor('accent_primary', this.themeState.currentTheme) :
            ThemeAwareHelper.getTestManagementThemedColor('background_secondary', this.themeState.currentTheme))
          .fontColor(this.discoverContentType === 'all' ?
            ThemeAwareHelper.getTestManagementThemedColor('text_white', this.themeState.currentTheme) :
            ThemeAwareHelper.getTestManagementThemedColor('text_primary', this.themeState.currentTheme))
          .borderRadius(16)
          .onClick(() => {
            this.discoverContentType = 'all';
            this.applyDiscoverFilter();
          })

        Text(`漫画 (${this.filteredMangaCount})`)
          .fontSize(13)
          .fontFamily(this.appFontFamily)
          .padding({ left: 16, right: 16, top: 6, bottom: 6 })
          .backgroundColor(this.discoverContentType === 'manga' ?
            ThemeAwareHelper.getTestManagementThemedColor('accent_primary', this.themeState.currentTheme) :
            ThemeAwareHelper.getTestManagementThemedColor('background_secondary', this.themeState.currentTheme))
          .fontColor(this.discoverContentType === 'manga' ?
            ThemeAwareHelper.getTestManagementThemedColor('text_white', this.themeState.currentTheme) :
            (this.filteredMangaCount === 0 ?
              ThemeAwareHelper.getTestManagementThemedColor('text_muted', this.themeState.currentTheme) :
              ThemeAwareHelper.getTestManagementThemedColor('text_primary', this.themeState.currentTheme)))
          .borderRadius(16)
          .opacity(this.filteredMangaCount === 0 && this.discoverContentType !== 'manga' ? 0.5 : 1)
          .onClick(() => {
            if (this.filteredMangaCount > 0 || this.discoverContentType === 'manga') {
              this.discoverContentType = 'manga';
              this.applyDiscoverFilter();
            }
          })

        Text(`电子书 (${this.filteredEBookCount})`)
          .fontSize(13)
          .fontFamily(this.appFontFamily)
          .padding({ left: 16, right: 16, top: 6, bottom: 6 })
          .backgroundColor(this.discoverContentType === 'ebook' ?
            ThemeAwareHelper.getTestManagementThemedColor('accent_primary', this.themeState.currentTheme) :
            ThemeAwareHelper.getTestManagementThemedColor('background_secondary', this.themeState.currentTheme))
          .fontColor(this.discoverContentType === 'ebook' ?
            ThemeAwareHelper.getTestManagementThemedColor('text_white', this.themeState.currentTheme) :
            (this.filteredEBookCount === 0 ?
              ThemeAwareHelper.getTestManagementThemedColor('text_muted', this.themeState.currentTheme) :
              ThemeAwareHelper.getTestManagementThemedColor('text_primary', this.themeState.currentTheme)))
          .borderRadius(16)
          .opacity(this.filteredEBookCount === 0 && this.discoverContentType !== 'ebook' ? 0.5 : 1)
          .onClick(() => {
            if (this.filteredEBookCount > 0 || this.discoverContentType === 'ebook') {
              this.discoverContentType = 'ebook';
              this.applyDiscoverFilter();
            }
          })

        Text(`小说 (${this.filteredNovelCount})`)
          .fontSize(13)
          .fontFamily(this.appFontFamily)
          .padding({ left: 16, right: 16, top: 6, bottom: 6 })
          .backgroundColor(this.discoverContentType === 'novel' ?
            ThemeAwareHelper.getTestManagementThemedColor('accent_primary', this.themeState.currentTheme) :
            ThemeAwareHelper.getTestManagementThemedColor('background_secondary', this.themeState.currentTheme))
          .fontColor(this.discoverContentType === 'novel' ?
            ThemeAwareHelper.getTestManagementThemedColor('text_white', this.themeState.currentTheme) :
            (this.filteredNovelCount === 0 ?
              ThemeAwareHelper.getTestManagementThemedColor('text_muted', this.themeState.currentTheme) :
              ThemeAwareHelper.getTestManagementThemedColor('text_primary', this.themeState.currentTheme)))
          .borderRadius(16)
          .opacity(this.filteredNovelCount === 0 && this.discoverContentType !== 'novel' ? 0.5 : 1)
          .onClick(() => {
            if (this.filteredNovelCount > 0 || this.discoverContentType === 'novel') {
              this.discoverContentType = 'novel';
              this.applyDiscoverFilter();
            }
          })
      }
      .width('100%')
      .padding({ left: 16, right: 16, top: 12, bottom: 8 })

      // 筛选结果提示
      if (this.selectedTags.size > 0 || this.selectedAuthors.size > 0 || this.discoverContentType !== 'all') {
        Row() {
          Text(`找到 ${this.discoveredMangaList.length} 本漫画, ${this.discoveredEBookList.length} 本电子书, ${this.discoveredNovelList.length} 本小说`)
            .fontSize(13)
            .fontFamily(this.appFontFamily)
            .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_secondary', this.themeState.currentTheme))
        }
        .width('100%')
        .padding({ left: 16, right: 16, top: 4 })
      }

      // 内容列表（响应式）
      if (this.discoveredMangaList.length > 0 || this.discoveredEBookList.length > 0 || this.discoveredNovelList.length > 0) {
        List() {
          // 漫画部分
          if (this.discoveredMangaList.length > 0) {
            ListItem() {
              Column() {
                if (this.discoverContentType === 'all' && (this.discoveredEBookList.length > 0 || this.discoveredNovelList.length > 0)) {
                  Text(`漫画 (${this.discoveredMangaList.length})`)
                    .fontSize(14)
                    .fontWeight(FontWeight.Medium)
                    .fontFamily(this.appFontFamily)
                    .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_primary', this.themeState.currentTheme))
                    .width('100%')
                    .margin({ bottom: 8 })
                }
                Grid() {
                  ForEach(this.discoveredMangaList, (manga: Manga) => {
                    GridItem() {
                      this.buildDiscoverMangaGridCard(manga)
                    }
                  }, (manga: Manga) => manga.id)
                }
                .columnsTemplate(this.getDiscoverGridColumnsTemplate())
                .columnsGap(this.responsive_gridGap)
                .rowsGap(this.responsive_gridGap)
                .width('100%')
              }
            }
          }

          // 电子书部分
          if (this.discoveredEBookList.length > 0) {
            ListItem() {
              Column() {
                if (this.discoverContentType === 'all' && (this.discoveredMangaList.length > 0 || this.discoveredNovelList.length > 0)) {
                  Text(`电子书 (${this.discoveredEBookList.length})`)
                    .fontSize(14)
                    .fontWeight(FontWeight.Medium)
                    .fontFamily(this.appFontFamily)
                    .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_primary', this.themeState.currentTheme))
                    .width('100%')
                    .margin({ top: 16, bottom: 8 })
                }
                Grid() {
                  ForEach(this.discoveredEBookList, (ebook: EBook) => {
                    GridItem() {
                      this.buildEBookGridCard(ebook)
                    }
                  }, (ebook: EBook) => ebook.id)
                }
                .columnsTemplate(this.getDiscoverGridColumnsTemplate())
                .columnsGap(this.responsive_gridGap)
                .rowsGap(this.responsive_gridGap)
                .width('100%')
              }
            }
          }
          
          // 小说部分
          if (this.discoveredNovelList.length > 0) {
            ListItem() {
              Column() {
                if (this.discoverContentType === 'all' && (this.discoveredMangaList.length > 0 || this.discoveredEBookList.length > 0)) {
                  Text(`小说 (${this.discoveredNovelList.length})`)
                    .fontSize(14)
                    .fontWeight(FontWeight.Medium)
                    .fontFamily(this.appFontFamily)
                    .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_primary', this.themeState.currentTheme))
                    .width('100%')
                    .margin({ top: 16, bottom: 8 })
                }
                Grid() {
                  ForEach(this.discoveredNovelList, (novel: NovelBook) => {
                    GridItem() {
                      this.buildDiscoverNovelGridCard(novel)
                    }
                  }, (novel: NovelBook) => novel.id)
                }
                .columnsTemplate(this.getDiscoverGridColumnsTemplate())
                .columnsGap(this.responsive_gridGap)
                .rowsGap(this.responsive_gridGap)
                .width('100%')
              }
            }
          }
        }
        .layoutWeight(1)
        .padding({ left: 16, right: 16, top: 12, bottom: 16 })
        .scrollBar(BarState.Auto)
        .edgeEffect(EdgeEffect.Spring)
      } else {
        Column() {
          Text(this.mangaList.length === 0 && this.ebookList.length === 0 && this.novelList.length === 0 ? '暂无数据' : '没有符合条件的内容')
            .fontSize(14)
            .fontFamily(this.appFontFamily)
            .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_muted', this.themeState.currentTheme))
        }
        .layoutWeight(1)
        .justifyContent(FlexAlign.Center)
      }
    }
    .width('100%')
    .height('100%')
  }

  /**
   * 构建图源管理弹窗
   */
  @Builder
  buildSourceRepoDialog() {
    Column({ space: 20 }) {
      Text('图源管理')
        .fontSize(20)
        .fontWeight(FontWeight.Medium)
        .fontFamily(this.appFontFamily)
        .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_primary', this.themeState.currentTheme))
      
      // 本地导入按钮
      if (!this.isSyncingRepo) {
        Button('导入本地图源文件')
          .width('100%')
          .fontSize(14)
          .fontFamily(this.appFontFamily)
          .backgroundColor(ThemeAwareHelper.getTestManagementThemedColor('button_primary', this.themeState.currentTheme))
          .onClick(async () => {
            this.sourceRepoDialogController?.close();
            await this.importSource();
          })
        
        Divider()
          .color(ThemeAwareHelper.getTestManagementThemedColor('divider', this.themeState.currentTheme))
          .margin({ top: 4, bottom: 4 })
        
        Text('或使用在线仓库同步')
          .fontSize(14)
          .fontFamily(this.appFontFamily)
          .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_secondary', this.themeState.currentTheme))
          .textAlign(TextAlign.Center)
      }
      
      // 已保存仓库选择器
      if (this.savedRepositories.length > 0) {
        Column({ space: 8 }) {
          Row({ space: 8 }) {
            Text('已保存的仓库')
              .fontSize(14)
              .fontFamily(this.appFontFamily)
              .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_secondary', this.themeState.currentTheme))
            
            Button(this.showRepositorySelector ? '收起' : '展开')
              .fontSize(12)
              .height(24)
              .fontFamily(this.appFontFamily)
              .padding({ left: 8, right: 8 })
              .backgroundColor(ThemeAwareHelper.getTestManagementThemedColor('button_background', this.themeState.currentTheme))
              .onClick(() => {
                this.showRepositorySelector = !this.showRepositorySelector;
              })
          }
          .width('100%')
          .justifyContent(FlexAlign.SpaceBetween)
          
          if (this.showRepositorySelector) {
            List({ space: 8 }) {
              ForEach(this.savedRepositories, (repo: SavedRepository) => {
                ListItem() {
                  Row({ space: 12 }) {
                    Radio({ value: repo.id, group: 'repoGroup' })
                      .checked(this.selectedRepositoryId === repo.id)
                      .onChange((isChecked: boolean) => {
                        if (isChecked) {
                          this.selectedRepositoryId = repo.id;
                          this.sourceRepoUrl = repo.url;
                        }
                      })
                    
                    Column({ space: 4 }) {
                      Text(repo.name)
                        .fontSize(14)
                        .fontFamily(this.appFontFamily)
                        .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_primary', this.themeState.currentTheme))
                        .maxLines(1)
                        .textOverflow({ overflow: TextOverflow.Ellipsis })
                      
                      Text(`${repo.sourceCount} 个图源 · ${new Date(repo.lastSync).toLocaleDateString()}`)
                        .fontSize(12)
                        .fontFamily(this.appFontFamily)
                        .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_muted', this.themeState.currentTheme))
                    }
                    .layoutWeight(1)
                    .alignItems(HorizontalAlign.Start)
                  }
                  .width('100%')
                  .padding(12)
                  .backgroundColor(this.selectedRepositoryId === repo.id ? 
                    ThemeAwareHelper.getTestManagementThemedColor('accent_blue', this.themeState.currentTheme) : 
                    ThemeAwareHelper.getTestManagementThemedColor('button_background', this.themeState.currentTheme))
                  .borderRadius(8)
                  .onClick(() => {
                    this.selectedRepositoryId = repo.id;
                    this.sourceRepoUrl = repo.url;
                  })
                  .gesture(
                    LongPressGesture({ repeat: false, duration: 500 })
                      .onAction(() => {
                        this.repositoryToDelete = repo;
                        this.showDeleteRepoPopup = true;
                      })
                  )
                  .bindPopup(this.showDeleteRepoPopup && this.repositoryToDelete?.id === repo.id, {
                    builder: this.buildDeleteRepoPopup,
                    placement: Placement.Top,
                    popupColor: ThemeAwareHelper.getTestManagementThemedColor('panel_background', this.themeState.currentTheme),
                    onStateChange: (e) => {
                      if (!e.isVisible) {
                        this.showDeleteRepoPopup = false;
                        this.repositoryToDelete = null;
                      }
                    }
                  })
                }
              }, (repo: SavedRepository) => repo.id)
            }
            .height(200)
            .width('100%')
          }
        }
        .width('100%')
      }
      
      // 自定义URL输入（同步时隐藏）
      if (!this.isSyncingRepo) {
        TextInput({ placeholder: '请输入仓库地址 (如: https://example.com/index.min.json)', text: this.sourceRepoUrl })
          .width('100%')
          .onChange((value: string) => {
            // 自动解析和拼接URL
            const parsedUrl = this.parseAndFixRepoUrl(value);
            this.sourceRepoUrl = parsedUrl;
            this.selectedRepositoryId = ''; // 清除选中的仓库
          })
          .backgroundColor(ThemeAwareHelper.getTestManagementThemedColor('button_background', this.themeState.currentTheme))
          .borderRadius(8)
      }
      
      // 同步进度和日志窗口（同步时显示）
      if (this.isSyncingRepo) {
        Column({ space: 12 }) {
          // 进度条
          Row({ space: 8 }) {
            Progress({
              value: this.syncProgress,
              total: 100,
              type: ProgressType.Linear
            })
              .layoutWeight(1)
              .height(8)
              .color(ThemeAwareHelper.getTestManagementThemedColor('accent_primary', this.themeState.currentTheme))
            
            Text(`${this.syncProgress}%`)
              .fontSize(14)
              .fontFamily(this.appFontFamily)
              .fontColor(ThemeAwareHelper.getTestManagementThemedColor('accent_primary', this.themeState.currentTheme))
              .width(50)
              .textAlign(TextAlign.End)
          }
          .width('100%')
          
          // 当前进度消息
          Text(this.syncProgressMessage)
            .fontSize(14)
            .fontFamily(this.appFontFamily)
            .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_primary', this.themeState.currentTheme))
            .width('100%')
            .textAlign(TextAlign.Start)
          
          // 命令行风格日志窗口
          Column() {
            Scroll() {
              Column({ space: 2 }) {
                ForEach(this.syncLogMessages, (logLine: string, index: number) => {
                  Text(logLine)
                    .fontSize(12)
                    .fontFamily('monospace')
                    .fontColor(logLine.includes('✗') ? '#FF6B6B' : 
                              (logLine.includes('⚠') ? '#FFB347' : '#98FB98'))
                    .width('100%')
                    .textAlign(TextAlign.Start)
                }, (logLine: string, index: number) => `log_${index}_${logLine.substring(0, 20)}`)
              }
              .width('100%')
              .padding(8)
            }
            .width('100%')
            .height(200)
            .scrollBar(BarState.Auto)
          }
          .width('100%')
          .backgroundColor('#1A1A2E')
          .borderRadius(8)
          .border({ width: 1, color: '#333' })
        }
        .width('100%')
      }
      
      Row({ space: 12 }) {
        Button(this.isSyncingRepo ? '关闭' : '取消')
          .layoutWeight(1)
          .fontFamily(this.appFontFamily)
          .backgroundColor(ThemeAwareHelper.getTestManagementThemedColor('button_background', this.themeState.currentTheme))
          .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_primary', this.themeState.currentTheme))
          .onClick(() => {
            this.sourceRepoDialogController?.close();
            this.showSourceRepoDialog = false;
            this.isSyncingRepo = false;
          })
        
        if (!this.isSyncingRepo) {
          Button('确认同步')
            .layoutWeight(1)
            .fontFamily(this.appFontFamily)
            .backgroundColor(ThemeAwareHelper.getTestManagementThemedColor('accent_blue', this.themeState.currentTheme))
            .fontColor(Color.White)
            .onClick(async () => {
              await this.syncSourceRepository();
            })
        }
      }
      .width('100%')
    }
    .width('90%')
    .padding(24)
    .backgroundColor(ThemeAwareHelper.getTestManagementThemedColor('panel_background', this.themeState.currentTheme))
    .borderRadius(16)
  }

  /**
   * 构建删除仓库弹窗
   */
  @Builder
  buildDeleteRepoPopup() {
    Column({ space: 12 }) {
      Text('删除仓库')
        .fontSize(16)
        .fontWeight(FontWeight.Medium)
        .fontFamily(this.appFontFamily)
        .margin({ bottom: 8 })
      Button(this.repositoryToDelete ? `删除 "${this.repositoryToDelete.name}"` : '确认删除')
        .width('100%')
        .fontFamily(this.appFontFamily)
        .backgroundColor(ThemeAwareHelper.getTestManagementThemedColor('button_danger', this.themeState.currentTheme))
        .fontColor(Color.White)
        .onClick(async () => {
          if (this.repositoryToDelete) {
            await this.deleteRepository(this.repositoryToDelete);
            this.showDeleteRepoPopup = false;
            this.repositoryToDelete = null;
          }
        })
    }
    .padding(16)
  }

  /**
   * 构建标签自定义对话框
   */
  @Builder
  buildTabCustomizationDialog() {
    Column({ space: 16 }) {
        Text('自定义底栏标签')
          .fontSize(18)
          .fontWeight(FontWeight.Medium)
          .fontFamily(this.appFontFamily)
          .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_primary', this.themeState.currentTheme))

        Text('选择要显示的标签页（书库和设置为必须显示）')
          .fontSize(14)
          .fontFamily(this.appFontFamily)
          .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_secondary', this.themeState.currentTheme))

        Column({ space: 12 }) {
          ForEach(this.tabConfigs, (cfg: TabConfig) => {
            Row({ space: 12 }) {
              Checkbox()
                .select(this.tempVisibleTabIndices.includes(cfg.index))
                .selectedColor(this.themeState.currentTheme === ThemeType.DARK ? '#FF6200EE' : '#FF6200EE')
                .onChange((isChecked: boolean) => {
                  if (!cfg.required) {
                    this.toggleTabVisibility(cfg.index);
                  }
                })
                .enabled(!cfg.required)

              Column({ space: 4 }) {
                Text(cfg.title)
                  .fontSize(16)
                  .fontFamily(this.appFontFamily)
                  .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_primary', this.themeState.currentTheme))

                if (cfg.required) {
                  Text('必须显示')
                    .fontSize(12)
                    .fontFamily(this.appFontFamily)
                    .fontColor(ThemeAwareHelper.getTestManagementThemedColor('accent_primary', this.themeState.currentTheme))
                }
              }
              .alignItems(HorizontalAlign.Start)
              .layoutWeight(1)
            }
            .width('100%')
            .padding(12)
            .backgroundColor(ThemeAwareHelper.getTestManagementThemedColor('panel_background', this.themeState.currentTheme))
            .borderRadius(8)
          })
        }
        .width('100%')

        Row({ space: 12 }) {
          Button('取消')
            .layoutWeight(1)
            .fontFamily(this.appFontFamily)
            .backgroundColor(ThemeAwareHelper.getTestManagementThemedColor('button_background', this.themeState.currentTheme))
            .onClick(() => {
              this.showTabCustomDialog = false;
            })

          Button('保存')
            .layoutWeight(1)
            .fontFamily(this.appFontFamily)
            .backgroundColor(ThemeAwareHelper.getTestManagementThemedColor('accent_primary', this.themeState.currentTheme))
            .onClick(async () => {
              await this.applyTabCustomization();
            })
        }
        .width('100%')
    }
    .width('100%')
    .padding(24)
    .backgroundColor(ThemeAwareHelper.getTestManagementThemedColor('background_primary', this.themeState.currentTheme))
    .borderRadius({ topLeft: 16, topRight: 16 })
    .shadow({ radius: 20, color: 'rgba(0, 0, 0, 0.3)', offsetX: 0, offsetY: -4 })
  }

  /**
   * 构建图源内容
   */
  @Builder
  buildSourceContent() {
    Column({ space: 0 }) {
      // 搜索栏
      Row({ space: 8 }) {
        Search({ placeholder: '搜索图源名称、URL或描述' })
          .searchButton('搜索')
          .layoutWeight(1)
          .onChange((value: string) => {
            this.searchSources(value);
          })
        
        // 代理设置按钮
        Button() {
          SymbolGlyph($r('sys.symbol.airplane_departure'))
            .fontSize(20)
            .fontColor([this.proxyConfig.enabled ? 
              ThemeAwareHelper.getTestManagementThemedColor('accent_green', this.themeState.currentTheme) :
              ThemeAwareHelper.getTestManagementThemedColor('text_secondary', this.themeState.currentTheme)])
        }
        .width(40)
        .height(40)
        .backgroundColor(ThemeAwareHelper.getTestManagementThemedColor('background_secondary', this.themeState.currentTheme))
        .borderRadius(8)
        .onClick(() => {
          // 加载需要代理的图源列表
          this.proxySourceList = this.sourceList.filter((s: SourceInfo) => s.requireProxy === true);
          this.showProxyDialog = true;
        })
      }
      .width('100%')
      .padding(16)
      .backgroundColor(Color.Transparent)

      // 功能按钮行
      Row({ space: 12 }) {
        // 图源管理按钮（带升级图标）
        Row({ space: 6 }) {
          Button('图源管理')
            .fontSize(14)
            .fontFamily(this.appFontFamily)
            .backgroundColor(ThemeAwareHelper.getTestManagementThemedColor('accent_blue', this.themeState.currentTheme))
            .onClick(() => {
              this.openSourceRepoDialog();
            })
          
          // 有更新时显示升级图标
          if (this.hasSourceUpdate) {
            Image($r('app.media.ic_upgrade'))
              .width(24)
              .height(24)
              .onClick(async () => {
                await this.quickSyncSourceRepository();
              })
          }
          
          // 类型筛选按钮
          Button() {
            Image(this.getSourceTypeFilterIcon())
              .width(24)
              .height(24)
              .fillColor(ThemeAwareHelper.getTestManagementThemedColor('text_primary', this.themeState.currentTheme))
          }
          .type(ButtonType.Circle)
          .width(36)
          .height(36)
          .backgroundColor(Color.Transparent)
          .onClick(() => {
            this.cycleSourceTypeFilter();
          })
          
          // 视图切换按钮
          Button() {
            SymbolGlyph(this.sourceViewMode === LibraryViewMode.LIST
              ? $r('sys.symbol.list_bullet')
              : $r('sys.symbol.square_grid_2x2'))
              .fontSize(20)
              .fontColor([ThemeAwareHelper.getTestManagementThemedColor('text_primary', this.themeState.currentTheme)])
          }
          .type(ButtonType.Circle)
          .width(36)
          .height(36)
          .backgroundColor(Color.Transparent)
          .onClick(() => {
            this.sourceViewMode = this.sourceViewMode === LibraryViewMode.LIST
              ? LibraryViewMode.GRID
              : LibraryViewMode.LIST;
          })
        }
        .layoutWeight(1)
        .justifyContent(FlexAlign.Center)
      }
      .width('100%')
      .padding({ left: 16, right: 16, bottom: 12 })

      // 图源列表区域（支持下拉刷新）
      Refresh({ refreshing: this.isRefreshingSourceList }) {
        Scroll() {
          Column({ space: 12 }) {

          // 图源列表
          Column({ space: 8 }) {
          Text(this.getSourceListTitle())
            .fontSize(16)
            .fontWeight(FontWeight.Medium)
            .fontFamily(this.appFontFamily)
            .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_primary', this.themeState.currentTheme))
            .padding({ left: 16, right: 16 })
          
          // 图源列表或空状态
          if (this.isLoadingSourceList) {
            // 加载状态
            Column({ space: 16 }) {
              LoadingProgress()
                .width(48)
                .height(48)
                .color(ThemeAwareHelper.getTestManagementThemedColor('accent_blue', this.themeState.currentTheme))
              
              Text('加载中...')
                .fontSize(14)
                .fontFamily(this.appFontFamily)
                .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_secondary', this.themeState.currentTheme))
            }
            .width('100%')
            .padding(40)
            .justifyContent(FlexAlign.Center)
          } else if (this.filteredSourceList.length === 0) {
            // 空状态提示
            Column({ space: 12 }) {
              Image(this.getSourceTypeFilterIcon())
                .width(64)
                .height(64)
                .opacity(0.3)
                .fillColor(ThemeAwareHelper.getTestManagementThemedColor('text_muted', this.themeState.currentTheme))
              
              Text(this.getEmptySourceTitle())
                .fontSize(16)
                .fontFamily(this.appFontFamily)
                .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_muted', this.themeState.currentTheme))
              
              if (!this.sourceSearchKeyword) {
                Column({ space: 8 }) {
                  Text(this.getEmptySourceDescription())
                    .fontSize(14)
                    .fontFamily(this.appFontFamily)
                    .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_muted', this.themeState.currentTheme))
                    .textAlign(TextAlign.Center)
                  
                  Text(this.getEmptySourceHint())
                    .fontSize(13)
                    .fontFamily(this.appFontFamily)
                    .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_muted', this.themeState.currentTheme))
                    .opacity(0.8)
                    .textAlign(TextAlign.Center)
                }
              }
            }
            .width('100%')
            .padding(40)
            .justifyContent(FlexAlign.Center)
          } else {
            // 根据视图模式显示列表或网格
            if (this.sourceViewMode === LibraryViewMode.LIST) {
              // 图源卡片列表
              Column({ space: 12 }) {
                ForEach(this.filteredSourceList, (source: SourceInfo) => {
                  this.buildSourceCard(source)
                })
              }
              .width('100%')
              .padding({ left: 16, right: 16 })
            } else {
              // 图源网格视图
              Grid() {
                ForEach(this.filteredSourceList, (source: SourceInfo) => {
                  GridItem() {
                    this.buildSourceGridCard(source)
                  }
                }, (source: SourceInfo) => String(source.id))
              }
              .columnsTemplate(this.getLibraryGridColumnsTemplate())
              .columnsGap(this.responsive_gridGap)
              .rowsGap(this.responsive_gridGap)
              .width('100%')
              .padding({ left: 16, right: 16 })
            }
          }
        }
        .width('100%')

        // 使用说明（根据筛选模式显示不同内容）
        this.buildSourceUsageGuide()
          }
          .width('100%')
        }
        .scrollBar(BarState.Off)
        .edgeEffect(EdgeEffect.Spring)
      }
      .onRefreshing(async () => {
        await this.handleSourceRefresh();
      })
      .layoutWeight(1)
    }
    .width('100%')
    .height('100%')
    
    // 代理配置对话框
    if (this.showProxyDialog) {
      this.buildProxyConfigDialog()
    }
    
    // 图源搜索对话框
    if (this.showSourceSearchDialog) {
      this.buildSourceSearchDialog()
    }
  }
  
  /**
   * 构建图源搜索对话框
   */
  @Builder
  buildSourceSearchDialog() {
    Column() {
      Column({ space: 16 }) {
        // 标题
        Row({ space: 8 }) {
          SymbolGlyph($r('sys.symbol.magnifyingglass'))
            .fontSize(20)
            .fontColor([ThemeAwareHelper.getTestManagementThemedColor('accent_primary', this.themeState.currentTheme)])
          Text(`在 ${this.searchTargetSource?.name || '图源'} 中搜索`)
            .fontSize(16)
            .fontWeight(FontWeight.Medium)
            .fontFamily(this.appFontFamily)
            .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_primary', this.themeState.currentTheme))
        }
        .width('100%')
        
        // 搜索输入框
        TextInput({ placeholder: '输入搜索关键词', text: this.sourceSearchInput })
          .width('100%')
          .height(44)
          .borderRadius(8)
          .fontFamily(this.appFontFamily)
          .backgroundColor(ThemeAwareHelper.getTestManagementThemedColor('comp_background_secondary', this.themeState.currentTheme))
          .onChange((value: string) => {
            this.sourceSearchInput = value;
          })
          .onSubmit(() => {
            this.executeSourceSearch();
          })
        
        // 按钮
        Row({ space: 12 }) {
          Button('取消')
            .fontSize(14)
            .fontFamily(this.appFontFamily)
            .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_secondary', this.themeState.currentTheme))
            .backgroundColor(ThemeAwareHelper.getTestManagementThemedColor('comp_background_secondary', this.themeState.currentTheme))
            .height(40)
            .borderRadius(8)
            .layoutWeight(1)
            .onClick(() => {
              this.showSourceSearchDialog = false;
              this.searchTargetSource = null;
              this.sourceSearchInput = '';
            })
          
          Button('搜索')
            .fontSize(14)
            .fontFamily(this.appFontFamily)
            .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_white', this.themeState.currentTheme))
            .backgroundColor(ThemeAwareHelper.getTestManagementThemedColor('accent_primary', this.themeState.currentTheme))
            .height(40)
            .borderRadius(8)
            .layoutWeight(1)
            .onClick(() => {
              this.executeSourceSearch();
            })
        }
        .width('100%')
      }
      .width('85%')
      .padding(20)
      .backgroundColor(ThemeAwareHelper.getTestManagementThemedColor('panel_background', this.themeState.currentTheme))
      .borderRadius(16)
      .shadow({ radius: 20, color: '#40000000', offsetY: 8 })
      .transition(TransitionEffect.OPACITY.animation({ duration: 200 }).combine(TransitionEffect.scale({ x: 0.9, y: 0.9 })))
    }
    .width('100%')
    .height('100%')
    .justifyContent(FlexAlign.Start)
    .padding({ top: 120 })
    .transition(TransitionEffect.OPACITY.animation({ duration: 150 }))
  }
  
  /**
   * 构建代理配置对话框
   */
  @Builder
  buildProxyConfigDialog() {
    Column() {
      Column() {
        // 标题
        Row() {
          SymbolGlyph($r('sys.symbol.airplane_departure'))
            .fontSize(24)
            .fontColor([ThemeAwareHelper.getTestManagementThemedColor('accent_blue', this.themeState.currentTheme)])
          
          Text('网络代理设置')
            .fontSize(18)
            .fontWeight(FontWeight.Bold)
            .fontFamily(this.appFontFamily)
            .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_primary', this.themeState.currentTheme))
            .margin({ left: 8 })
        }
        .width('100%')
        .justifyContent(FlexAlign.Center)
        .margin({ bottom: 16 })

        // 启用开关
        Row() {
          Text('启用代理')
            .fontSize(16)
            .fontFamily(this.appFontFamily)
            .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_primary', this.themeState.currentTheme))
          
          Blank()
          
          Toggle({ type: ToggleType.Switch, isOn: this.proxyConfig.enabled })
            .onChange((isOn: boolean) => {
              this.proxyConfig.enabled = isOn;
            })
        }
        .width('100%')
        .padding({ top: 8, bottom: 8 })

        Divider()
          .color(ThemeAwareHelper.getTestManagementThemedColor('divider', this.themeState.currentTheme))
          .margin({ top: 12, bottom: 12 })

        // HTTP代理配置
        Column({ space: 8 }) {
          Row() {
            Toggle({ type: ToggleType.Checkbox, isOn: this.proxyConfig.httpEnabled })
              .onChange((isOn: boolean) => {
                this.proxyConfig.httpEnabled = isOn;
              })
            
            Text('HTTP代理')
              .fontSize(15)
              .fontWeight(FontWeight.Medium)
              .fontFamily(this.appFontFamily)
              .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_primary', this.themeState.currentTheme))
              .margin({ left: 8 })
          }
          .width('100%')

          Row({ space: 8 }) {
            TextInput({ placeholder: '代理地址', text: this.proxyConfig.httpHost })
              .layoutWeight(2)
              .height(40)
              .borderRadius(8)
              .fontFamily(this.appFontFamily)
              .backgroundColor(ThemeAwareHelper.getTestManagementThemedColor('background_secondary', this.themeState.currentTheme))
              .onChange((value: string) => {
                this.proxyConfig.httpHost = value;
              })
              .enabled(this.proxyConfig.httpEnabled)

            TextInput({ placeholder: '端口', text: this.proxyConfig.httpPort.toString() })
              .layoutWeight(1)
              .height(40)
              .borderRadius(8)
              .fontFamily(this.appFontFamily)
              .type(InputType.Number)
              .backgroundColor(ThemeAwareHelper.getTestManagementThemedColor('background_secondary', this.themeState.currentTheme))
              .onChange((value: string) => {
                const port = parseInt(value);
                if (!isNaN(port) && port > 0 && port <= 65535) {
                  this.proxyConfig.httpPort = port;
                }
              })
              .enabled(this.proxyConfig.httpEnabled)
          }
          .width('100%')
        }
        .width('100%')
        .padding({ top: 8, bottom: 8 })
        
        // HTTPS代理配置
        Column({ space: 8 }) {
          Row() {
            Toggle({ type: ToggleType.Checkbox, isOn: this.proxyConfig.httpsEnabled })
              .onChange((isOn: boolean) => {
                this.proxyConfig.httpsEnabled = isOn;
              })
            
            Text('HTTPS代理')
              .fontSize(15)
              .fontWeight(FontWeight.Medium)
              .fontFamily(this.appFontFamily)
              .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_primary', this.themeState.currentTheme))
              .margin({ left: 8 })
          }
          .width('100%')

          Row({ space: 8 }) {
            TextInput({ placeholder: '代理地址', text: this.proxyConfig.httpsHost })
              .layoutWeight(2)
              .height(40)
              .borderRadius(8)
              .fontFamily(this.appFontFamily)
              .backgroundColor(ThemeAwareHelper.getTestManagementThemedColor('background_secondary', this.themeState.currentTheme))
              .onChange((value: string) => {
                this.proxyConfig.httpsHost = value;
              })
              .enabled(this.proxyConfig.httpsEnabled)

            TextInput({ placeholder: '端口', text: this.proxyConfig.httpsPort.toString() })
              .layoutWeight(1)
              .height(40)
              .borderRadius(8)
              .fontFamily(this.appFontFamily)
              .type(InputType.Number)
              .backgroundColor(ThemeAwareHelper.getTestManagementThemedColor('background_secondary', this.themeState.currentTheme))
              .onChange((value: string) => {
                const port = parseInt(value);
                if (!isNaN(port) && port > 0 && port <= 65535) {
                  this.proxyConfig.httpsPort = port;
                }
              })
              .enabled(this.proxyConfig.httpsEnabled)
          }
          .width('100%')
        }
        .width('100%')
        .padding({ top: 8, bottom: 8 })

        Divider()
          .color(ThemeAwareHelper.getTestManagementThemedColor('divider', this.themeState.currentTheme))
          .margin({ top: 12, bottom: 12 })
        
        // 需要代理的图源列表
        Row() {
          Text('需要代理的图源')
            .fontSize(15)
            .fontWeight(FontWeight.Medium)
            .fontFamily(this.appFontFamily)
            .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_primary', this.themeState.currentTheme))
          
          Blank()
          
          Text(`${this.proxySourceList.length} 个`)
            .fontSize(13)
            .fontFamily(this.appFontFamily)
            .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_secondary', this.themeState.currentTheme))
        }
        .width('100%')
        
        if (this.proxySourceList.length > 0) {
          Scroll() {
            Column({ space: 4 }) {
              ForEach(this.proxySourceList, (source: SourceInfo) => {
                Row({ space: 8 }) {
                  if (source.iconPath) {
                    Image('file://' + source.iconPath)
                      .width(24)
                      .height(24)
                      .borderRadius(4)
                  } else {
                    Image($r('app.media.ic_source_normal'))
                      .width(24)
                      .height(24)
                      .borderRadius(4)
                  }
                  
                  Text(source.name)
                    .fontSize(13)
                    .fontFamily(this.appFontFamily)
                    .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_primary', this.themeState.currentTheme))
                    .layoutWeight(1)
                  
                  Text(source.isEnabled ? '已启用' : '已禁用')
                    .fontSize(11)
                    .fontFamily(this.appFontFamily)
                    .fontColor(source.isEnabled ? 
                      ThemeAwareHelper.getTestManagementThemedColor('accent_green', this.themeState.currentTheme) :
                      ThemeAwareHelper.getTestManagementThemedColor('text_muted', this.themeState.currentTheme))
                }
                .width('100%')
                .padding(8)
                .backgroundColor(ThemeAwareHelper.getTestManagementThemedColor('background_secondary', this.themeState.currentTheme))
                .borderRadius(6)
              })
            }
            .width('100%')
          }
          .width('100%')
          .height(100)
          .margin({ top: 8 })
        } else {
          Text('暂无需要代理的图源')
            .fontSize(12)
            .fontFamily(this.appFontFamily)
            .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_muted', this.themeState.currentTheme))
            .margin({ top: 8 })
        }

        // 测试代理按钮
        Button(this.isTestingProxy ? '测试中...' : '测试代理连接')
          .fontSize(14)
          .fontColor('#FFFFFF')
          .fontFamily(this.appFontFamily)
          .backgroundColor(this.isTestingProxy ? 
            ThemeAwareHelper.getTestManagementThemedColor('text_muted', this.themeState.currentTheme) :
            ThemeAwareHelper.getTestManagementThemedColor('accent_green', this.themeState.currentTheme))
          .borderRadius(8)
          .width('100%')
          .margin({ top: 12 })
          .enabled(!this.isTestingProxy)
          .onClick(async () => {
            this.isTestingProxy = true;
            this.proxyTestResults = '正在测试...';
            
            // 先保存配置
            await ProxyManager.getInstance().saveConfig(this.proxyConfig);
            
            // 执行测试
            const results = await ProxyManager.getInstance().testProxyBatch();
            
            // 格式化结果
            let resultText = '';
            for (const r of results) {
              const status = r.success ? '✓' : '✗';
              const time = r.responseTime ? `${r.responseTime}ms` : '';
              const code = r.responseCode ? `(${r.responseCode})` : '';
              const err = r.error ? `: ${r.error.substring(0, 30)}` : '';
              resultText += `${status} ${r.url} ${code} ${time}${err}\n`;
            }
            
            this.proxyTestResults = resultText;
            this.isTestingProxy = false;
          })
        
        // 测试结果显示
        if (this.proxyTestResults) {
          Scroll() {
            Text(this.proxyTestResults)
              .fontSize(11)
              .fontFamily(this.appFontFamily)
              .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_secondary', this.themeState.currentTheme))
              .fontFamily('monospace')
          }
          .width('100%')
          .height(80)
          .backgroundColor(ThemeAwareHelper.getTestManagementThemedColor('background_secondary', this.themeState.currentTheme))
          .borderRadius(8)
          .padding(8)
          .margin({ top: 8 })
        }

        // 提示信息
        Text('提示：代理将应用于图源和图源仓库的网络请求')
          .fontSize(12)
          .fontFamily(this.appFontFamily)
          .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_muted', this.themeState.currentTheme))
          .margin({ top: 12 })

        // 按钮
        Row({ space: 16 }) {
          Button('取消')
            .fontSize(16)
            .fontFamily(this.appFontFamily)
            .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_primary', this.themeState.currentTheme))
            .backgroundColor(ThemeAwareHelper.getTestManagementThemedColor('background_secondary', this.themeState.currentTheme))
            .borderRadius(8)
            .layoutWeight(1)
            .onClick(() => {
              this.showProxyDialog = false;
              this.proxyTestResults = '';
            })

          Button('保存')
            .fontSize(16)
            .fontColor('#FFFFFF')
            .fontFamily(this.appFontFamily)
            .backgroundColor(ThemeAwareHelper.getTestManagementThemedColor('accent_blue', this.themeState.currentTheme))
            .borderRadius(8)
            .layoutWeight(1)
            .onClick(() => {
              ProxyManager.getInstance().saveConfig(this.proxyConfig);
              this.showProxyDialog = false;
              this.proxyTestResults = '';
            })
        }
        .width('100%')
        .margin({ top: 20 })
      }
      .width('85%')
      .backgroundColor(ThemeAwareHelper.getTestManagementThemedColor('panel_background', this.themeState.currentTheme))
      .borderRadius(16)
      .padding(20)
    }
    .width('100%')
    .height('100%')
    .justifyContent(FlexAlign.Center)
    .position({ x: 0, y: 0 })
    .transition(TransitionEffect.opacity(0.01).animation({ duration: 200, curve: Curve.EaseOut }))
  }

  /**
   * 构建图源卡片
   */
  @Builder
  buildSourceCard(source: SourceInfo) {
    Row({ space: 12 }) {
      // 图源图标
      if (source.iconPath) {
        Image('file://' + source.iconPath)
          .width(48)
          .height(48)
          .borderRadius(8)
          .objectFit(ImageFit.Cover)
          .backgroundColor(ThemeAwareHelper.getTestManagementThemedColor('panel_background', this.themeState.currentTheme))
      } else {
        Image($r('app.media.ic_source_normal'))
          .width(48)
          .height(48)
          .borderRadius(8)
          .backgroundColor(ThemeAwareHelper.getTestManagementThemedColor('panel_background', this.themeState.currentTheme))
      }

      // 图源信息
      Column({ space: 4 }) {
        Row({ space: 8 }) {
          Text(source.name)
            .fontSize(16)
            .fontWeight(FontWeight.Medium)
            .fontFamily(this.appFontFamily)
            .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_primary', this.themeState.currentTheme))
            .maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis })

          if (!source.isEnabled) {
            Text('已禁用')
              .fontSize(12)
              .fontFamily(this.appFontFamily)
              .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_muted', this.themeState.currentTheme))
              .padding({ left: 6, right: 6, top: 2, bottom: 2 })
              .backgroundColor(ThemeAwareHelper.getTestManagementThemedColor('background_secondary', this.themeState.currentTheme))
              .borderRadius(4)
          }
        }
        .width('100%')

        if (source.description) {
          Text(source.description)
            .fontSize(13)
            .fontFamily(this.appFontFamily)
            .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_secondary', this.themeState.currentTheme))
            .maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
        }

        Row({ space: 4 }) {
          Text(`${source.language} · v${source.version}`)
            .fontSize(12)
            .fontFamily(this.appFontFamily)
            .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_muted', this.themeState.currentTheme))
          
          if (source.requireProxy) {
            Row({ space: 2 }) {
              SymbolGlyph($r('sys.symbol.wifi'))
                .fontSize(11)
                .fontColor([ThemeAwareHelper.getTestManagementThemedColor('accent_orange', this.themeState.currentTheme)])
              Text('需要代理')
                .fontSize(11)
                .fontFamily(this.appFontFamily)
                .fontColor(ThemeAwareHelper.getTestManagementThemedColor('accent_orange', this.themeState.currentTheme))
            }
          }
        }
      }
      .layoutWeight(1)
      .alignItems(HorizontalAlign.Start)

      // 箭头图标
      SymbolGlyph($r('sys.symbol.arrow_right'))
        .fontSize(20)
        .fontColor([ThemeAwareHelper.getTestManagementThemedColor('text_muted', this.themeState.currentTheme)])
    }
    .width('100%')
    .padding(12)
    .backgroundColor(ThemeAwareHelper.getTestManagementThemedColor('panel_background', this.themeState.currentTheme))
    .borderRadius(12)
    .onClick(() => {
      this.openSourceDetail(source);
    })
    .gesture(
      LongPressGesture({ repeat: false, duration: 500 })
        .onAction(() => {
          logger.info(TAG, `长按图源卡片: ${source.name}`);
          this.deleteSource(source);
        })
    )
  }

  /**
   * 构建图源网格卡片
   */
  @Builder
  buildSourceGridCard(source: SourceInfo) {
    Column({ space: 8 }) {
      // 图源图标
      Stack() {
        if (source.iconPath) {
          Image('file://' + source.iconPath)
            .width('100%')
            .height(80)
            .borderRadius(12)
            .objectFit(ImageFit.Cover)
            .backgroundColor(ThemeAwareHelper.getTestManagementThemedColor('panel_background', this.themeState.currentTheme))
        } else {
          Column() {
            Image($r('app.media.ic_source_normal'))
              .width(48)
              .height(48)
              .fillColor(ThemeAwareHelper.getTestManagementThemedColor('accent_primary', this.themeState.currentTheme))
          }
          .width('100%')
          .height(80)
          .borderRadius(12)
          .backgroundColor(ThemeAwareHelper.getTestManagementThemedColor('panel_background', this.themeState.currentTheme))
          .justifyContent(FlexAlign.Center)
        }

        // 禁用状态遮罩
        if (!source.isEnabled) {
          Column() {
            Text('已禁用')
              .fontSize(10)
              .fontFamily(this.appFontFamily)
              .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_white', this.themeState.currentTheme))
          }
          .width('100%')
          .height('100%')
          .backgroundColor('#80000000')
          .borderRadius(12)
          .justifyContent(FlexAlign.Center)
        }

        // 需要代理标识（使用系统图标）
        if (source.requireProxy) {
          SymbolGlyph($r('sys.symbol.wifi'))
            .fontSize(14)
            .fontColor([ThemeAwareHelper.getTestManagementThemedColor('text_white', this.themeState.currentTheme)])
            .position({ x: 4, y: 4 })
        }
      }
      .width('100%')
      .shadow({ radius: 8, color: '#1F000000', offsetY: 4 })

      // 图源名称
      Text(source.name)
        .fontSize(13)
        .fontWeight(FontWeight.Medium)
        .fontFamily(this.appFontFamily)
        .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_primary', this.themeState.currentTheme))
        .maxLines(1)
        .textOverflow({ overflow: TextOverflow.Ellipsis })
        .width('100%')
        .textAlign(TextAlign.Center)

      // 版本和语言
      Text(`${source.language} · v${source.version}`)
        .fontSize(11)
        .fontFamily(this.appFontFamily)
        .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_muted', this.themeState.currentTheme))
        .maxLines(1)
        .textOverflow({ overflow: TextOverflow.Ellipsis })
        .width('100%')
        .textAlign(TextAlign.Center)

      // 网络标识（如果需要代理）
      if (source.requireProxy) {
        Row({ space: 4 }) {
          SymbolGlyph($r('sys.symbol.wifi'))
            .fontSize(12)
            .fontColor([ThemeAwareHelper.getTestManagementThemedColor('text_muted', this.themeState.currentTheme)])
          Text('需要代理')
            .fontSize(10)
            .fontFamily(this.appFontFamily)
            .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_muted', this.themeState.currentTheme))
        }
        .width('100%')
        .justifyContent(FlexAlign.Center)
        .margin({ top: 2 })
      }

      // 快捷操作按钮（三行显示）
      Column({ space: 4 }) {
        // 热门按钮
        Row({ space: 4 }) {
          SymbolGlyph($r('sys.symbol.star'))
            .fontSize(12)
            .fontColor([ThemeAwareHelper.getTestManagementThemedColor('accent_primary', this.themeState.currentTheme)])
          Text('热门')
            .fontSize(11)
            .fontFamily(this.appFontFamily)
            .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_primary', this.themeState.currentTheme))
        }
        .width('100%')
        .height(24)
        .justifyContent(FlexAlign.Center)
        .backgroundColor(ThemeAwareHelper.getTestManagementThemedColor('comp_background_tertiary', this.themeState.currentTheme))
        .borderRadius(6)
        .onClick(() => {
          this.openSourceDetailWithTab(source, 'popular');
        })

        // 最新按钮
        Row({ space: 4 }) {
          SymbolGlyph($r('sys.symbol.clock'))
            .fontSize(12)
            .fontColor([ThemeAwareHelper.getTestManagementThemedColor('accent_primary', this.themeState.currentTheme)])
          Text('最新')
            .fontSize(11)
            .fontFamily(this.appFontFamily)
            .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_primary', this.themeState.currentTheme))
        }
        .width('100%')
        .height(24)
        .justifyContent(FlexAlign.Center)
        .backgroundColor(ThemeAwareHelper.getTestManagementThemedColor('comp_background_tertiary', this.themeState.currentTheme))
        .borderRadius(6)
        .onClick(() => {
          this.openSourceDetailWithTab(source, 'latest');
        })

        // 搜索按钮
        Row({ space: 4 }) {
          SymbolGlyph($r('sys.symbol.magnifyingglass'))
            .fontSize(12)
            .fontColor([ThemeAwareHelper.getTestManagementThemedColor('accent_primary', this.themeState.currentTheme)])
          Text('搜索')
            .fontSize(11)
            .fontFamily(this.appFontFamily)
            .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_primary', this.themeState.currentTheme))
        }
        .width('100%')
        .height(24)
        .justifyContent(FlexAlign.Center)
        .backgroundColor(ThemeAwareHelper.getTestManagementThemedColor('comp_background_tertiary', this.themeState.currentTheme))
        .borderRadius(6)
        .onClick(() => {
          this.openSourceDetailWithSearch(source);
        })

        // 设置按钮
        Row({ space: 4 }) {
          SymbolGlyph($r('sys.symbol.gearshape'))
            .fontSize(12)
            .fontColor([ThemeAwareHelper.getTestManagementThemedColor('accent_primary', this.themeState.currentTheme)])
          Text('设置')
            .fontSize(11)
            .fontFamily(this.appFontFamily)
            .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_primary', this.themeState.currentTheme))
        }
        .width('100%')
        .height(24)
        .justifyContent(FlexAlign.Center)
        .backgroundColor(ThemeAwareHelper.getTestManagementThemedColor('comp_background_tertiary', this.themeState.currentTheme))
        .borderRadius(6)
        .onClick(() => {
          this.openSourceSettings(source);
        })
      }
      .width('100%')
      .margin({ top: 4 })
    }
    .width('100%')
    .padding(8)
    .backgroundColor(this.getGlassBackground())
    .backgroundBlurStyle(this.getGlassBlur())
    .borderRadius(this.getGlassRadius())
    .onClick(() => {
      this.openSourceDetail(source);
    })
    .gesture(
      LongPressGesture({ repeat: false, duration: 500 })
        .onAction(() => {
          logger.info(TAG, `长按图源卡片: ${source.name}`);
          this.deleteSource(source);
        })
    )
  }

  /**
   * 构建书源内容（已暂时注释）
   */
  // @Builder
  // buildBookSourceContent() {
  //   Column() {
  //     BookSourceManagementPage()
  //   }
  //   .width('100%')
  //   .height('100%')
  //   .backgroundColor(Color.Transparent)
  // }

  /**
   * 构建设置内容
   */
  @Builder
  buildSettingsContent() {
    Scroll() {
      Column({ space: 0 }) {
        // 用户信息区域
        Row() {
          Image($r('app.media.avatar_256'))
            .width(60)
            .height(60)
            .borderRadius(30)
            .backgroundColor(ThemeAwareHelper.getTestManagementThemedColor('background_secondary', this.themeState.currentTheme))

          Column({ space: 4 }) {
            Text('阅读报告')
              .fontSize(18)
              .fontWeight(FontWeight.Medium)
              .fontFamily(this.appFontFamily)
              .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_primary', this.themeState.currentTheme))

            Text('查看您的阅读统计和分析')
              .fontSize(14)
              .fontFamily(this.appFontFamily)
              .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_secondary', this.themeState.currentTheme))
          }
          .alignItems(HorizontalAlign.Start)
          .layoutWeight(1)
          .margin({ left: 16 })

          SymbolGlyph($r('sys.symbol.chevron_right'))
            .fontSize(20)
            .fontColor([ThemeAwareHelper.getTestManagementThemedColor('text_muted', this.themeState.currentTheme)])
        }
        .width('100%')
        .padding(16)
        .backgroundColor(this.getGlassBackground())
        .backgroundBlurStyle(this.getGlassBlur())
        .borderRadius(this.getGlassRadius())
        .shadow({ radius: this.getGlassRadius(), color: this.getGlassShadowColor(), offsetX: 0, offsetY: 4 })
        .margin({ bottom: 16 })
        .onClick(() => {
          try {
            const navigationPath: NavigationPath = {
              name: 'ReadingAnalyticsPage',
              param: {
                fromPage: 'MainMenuPage',
                timestamp: Date.now()
              }
            };
            this.pathStack.pushPath(navigationPath);
            logger.info(TAG, '导航到阅读报告页面');
          } catch (error) {
            logger.error(TAG, '导航到阅读报告页面失败', String(error));
            this.showToast('打开阅读报告页面失败');
          }
        })

        // 设置选项列表
        Column() {
          this.buildSettingItem('底栏自定义', '自定义显示的标签页', $r('sys.symbol.square_grid_2x2'), () => {
            this.showToast('仅保留入口，功能暂时移除')
            // this.openTabCustomizationDialog();
          })
          this.buildSettingItem('主题设置', '自定义背景、强调色', $r('sys.symbol.paintbrush'), () => {
            try {
              const navigationPath: NavigationPath = {
                name: 'ThemeSettingsPage',
                param: {
                  fromPage: 'MainMenuPage',
                  timestamp: Date.now()
                }
              };
              this.pathStack.pushPath(navigationPath);
              logger.info(TAG, '导航到主题设置页面');
            } catch (error) {
              logger.error(TAG, '导航到主题设置页面失败', String(error));
              this.showToast('打开主题设置页面失败');
            }
          })
          this.buildSettingItem('全局设置', '默认阅读模式、下载选项', $r('sys.symbol.gearshape'), () => {
            try {
              const navigationPath: NavigationPath = {
                name: 'GlobalSettingsPage',
                param: {
                  fromPage: 'MainMenuPage',
                  timestamp: Date.now()
                }
              };
              this.pathStack.pushPath(navigationPath);
              logger.info(TAG, '导航到全局设置页面');
            } catch (error) {
              logger.error(TAG, '导航到全局设置页面失败', String(error));
              this.showToast('打开全局设置页面失败');
            }
          })
          // 下载管理仅在高级模式下显示
          if (this.advancedModeEnabled) {
            this.buildSettingItem('下载管理', '离线下载管理', $r('sys.symbol.arrow_down_circle'), () => {
              try {
                const navigationPath: NavigationPath = {
                  name: 'DownloadManagerPage',
                  param: {
                    fromPage: 'MainMenuPage',
                    timestamp: Date.now()
                  }
                };
                this.pathStack.pushPath(navigationPath);
                logger.info(TAG, '导航到下载管理页面');
              } catch (error) {
                logger.error(TAG, '导航到下载管理页面失败', String(error));
                this.showToast('打开下载管理页面失败');
              }
            })
          }

          this.buildSettingItem('备份与恢复', '备份所有数据或从备份恢复', $r('sys.symbol.mobiledata_and_cloud'), () => {
            try {
              const navigationPath: NavigationPath = {
                name: 'BackupPage',
                param: {
                  fromPage: 'MainMenuPage',
                  timestamp: Date.now()
                }
              };
              this.pathStack.pushPath(navigationPath);
              logger.info(TAG, '导航到备份页面');
            } catch (error) {
              logger.error(TAG, '导航到备份页面失败', String(error));
              this.showToast('打开备份页面失败');
            }
          })
          
          // 存储管理仅在高级模式下显示
          if (this.advancedModeEnabled) {
            this.buildSettingItem('存储管理', '清理缓存、管理存储空间', $r('sys.symbol.externaldrive_fill'), () => {
              try {
                const navigationPath: NavigationPath = {
                  name: 'StorageManagementPage',
                  param: {
                    fromPage: 'MainMenuPage',
                    timestamp: Date.now()
                  }
                };
                this.pathStack.pushPath(navigationPath);
                logger.info(TAG, '导航到存储管理页面');
              } catch (error) {
                logger.error(TAG, '导航到存储管理页面失败', String(error));
                this.showToast('打开存储管理页面失败');
              }
            })
          }
          this.buildSettingItem('文件导入', '单独导入Mihon/Komikku本地漫画、电子书、小说', $r('sys.symbol.folder'), () => {
            try {
              const navigationPath: NavigationPath = {
                name: 'DataManagementPage',
                param: {
                  fromPage: 'MainMenuPage',
                  timestamp: Date.now()
                }
              };
              this.pathStack.pushPath(navigationPath);
              logger.info(TAG, '导航到数据管理页面');
            } catch (error) {
              logger.error(TAG, '导航到数据管理页面失败', String(error));
              this.showToast('打开数据管理页面失败');
            }
          })
          this.buildSettingItem('Download同步', '从Download目录扫描并导入文件', $r('sys.symbol.folder_fill'), () => {
            try {
              const navigationPath: NavigationPath = {
                name: 'DownloadSyncPage',
                param: {
                  fromPage: 'MainMenuPage',
                  timestamp: Date.now()
                }
              };
              this.pathStack.pushPath(navigationPath);
              logger.info(TAG, '导航到Download同步页面');
            } catch (error) {
              logger.error(TAG, '导航到Download同步页面失败', String(error));
              this.showToast('打开Download同步页面失败');
            }
          })
          // 文件编辑器仅在高级模式下显示
          if (this.advancedModeEnabled) {
            this.buildSettingItem('文件编辑器', '编辑代码、配置文件、Markdown', $r('sys.symbol.case_fill'), () => {
              try {
                const navigationPath: NavigationPath = {
                  name: 'FileEditorPage',
                  param: {
                    fromPage: 'MainMenuPage',
                    timestamp: Date.now()
                  }
                };
                this.pathStack.pushPath(navigationPath);
                logger.info(TAG, '导航到文件编辑器页面');
              } catch (error) {
                logger.error(TAG, '导航到文件编辑器页面失败', String(error));
                this.showToast('打开文件编辑器页面失败');
              }
            })
            this.buildSettingItem('系统资源预览', '浏览系统图标和颜色资源', $r('sys.symbol.paintpalette'), () => {
              try {
                const navigationPath: NavigationPath = {
                  name: 'SystemResourcePreviewPage',
                  param: {
                    fromPage: 'MainMenuPage',
                    timestamp: Date.now()
                  }
                };
                this.pathStack.pushPath(navigationPath);
                logger.info(TAG, '导航到系统资源预览页面');
              } catch (error) {
                logger.error(TAG, '导航到系统资源预览页面失败', String(error));
                this.showToast('打开系统资源预览页面失败');
              }
            })
          }
          // 日志管理仅在高级模式下显示
          if (this.advancedModeEnabled) {
            this.buildSettingItem('日志管理', '查看和导出应用日志', $r('sys.symbol.doc_text'), () => {
              try {
                const navigationPath: NavigationPath = {
                  name: 'LogManagerPage',
                  param: {
                    fromPage: 'MainMenuPage',
                    timestamp: Date.now()
                  }
                };
                this.pathStack.pushPath(navigationPath);
                logger.info(TAG, '导航到日志管理页面');
              } catch (error) {
                logger.error(TAG, '导航到日志管理页面失败', String(error));
                this.showToast('打开日志管理页面失败');
              }
            })
            this.buildSettingItem('生命周期监控', '实时监控页面任务和资源', $r('sys.symbol.checkmark_shield_fill'), () => {
              try {
                const navigationPath: NavigationPath = {
                  name: 'LifecycleMonitorPage',
                  param: {
                    fromPage: 'MainMenuPage',
                    timestamp: Date.now()
                  }
                };
                this.pathStack.pushPath(navigationPath);
                logger.info(TAG, '导航到生命周期监控页面');
              } catch (error) {
                logger.error(TAG, '导航到生命周期监控页面失败', String(error));
                this.showToast('打开生命周期监控页面失败');
              }
            })
          }
          this.buildSettingItem('关于应用', `版本 ${this.appVersion}`, $r('sys.symbol.info_circle'), () => {
            try {
              const navigationPath: NavigationPath = {
                name: 'AboutPage',
                param: {
                  fromPage: 'MainMenuPage',
                  timestamp: Date.now()
                }
              };
              this.pathStack.pushPath(navigationPath);
              logger.info(TAG, '导航到关于应用页面');
            } catch (error) {
              logger.error(TAG, '导航到关于应用页面失败', String(error));
              this.showToast('打开关于应用页面失败');
            }
          })
          // NGF测试入口已移除，测试页面仍保留在代码中但不再从主菜单导航
          // this.buildSettingItem('Reader Kit 测试', '测试 EPUB/MOBI 等格式解析', $r('app.media.ic_settings'), () => {
          //   // 导航到ReaderKitTestPage
          //   const navigationPath: NavigationPath = {
          //     name: 'ReaderKitTestPage',
          //     param: {
          //       fromPage: 'MainMenuPage',
          //       timestamp: Date.now()
          //     }
          //   };
          //   this.pathStack.pushPath(navigationPath);
          // })
          // this.buildSettingItem('PDF Kit 测试', '测试 PDF 文档预览和操作', $r('app.media.ic_settings'), () => {
          //   // 导航到PdfKitTestPage
          //   const navigationPath: NavigationPath = {
          //     name: 'PdfKitTestPage',
          //     param: {
          //       fromPage: 'MainMenuPage',
          //       timestamp: Date.now()
          //     }
          //   };
          //   this.pathStack.pushPath(navigationPath);
          // })
          
        }
        .backgroundColor(this.getGlassBackground())
        .backgroundBlurStyle(this.getGlassBlur())
        .borderRadius(this.getGlassRadius())
        .shadow({ radius: this.getGlassRadius(), color: this.getGlassShadowColor(), offsetX: 0, offsetY: 4 })
      }
      .width('100%')
      .padding(16)
    }
    .width('100%')
    .height('100%')
    .backgroundColor(Color.Transparent)
    .scrollBar(BarState.Off)
    .edgeEffect(EdgeEffect.Spring)
  }

  /**
   * 构建设置项
   */
  @Builder
  buildSettingItem(title: string, subtitle: string, icon: ResourceStr, onClick?: () => void) {
    Row() {
      // 使用SymbolGlyph系统图标
      SymbolGlyph(icon as Resource)
        .fontSize(24)
        .fontColor([ThemeAwareHelper.getTestManagementThemedColor('text_primary', this.themeState.currentTheme)])
        .renderingStrategy(SymbolRenderingStrategy.SINGLE)

      Column({ space: 2 }) {
        Text(title)
          .fontSize(16)
          .fontFamily(this.appFontFamily)
          .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_primary', this.themeState.currentTheme))
          .textAlign(TextAlign.Start)
          .width('100%')

        Text(subtitle)
          .fontSize(14)
          .fontFamily(this.appFontFamily)
          .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_secondary', this.themeState.currentTheme))
          .textAlign(TextAlign.Start)
          .width('100%')
      }
      .alignItems(HorizontalAlign.Start)
      .layoutWeight(1)
      .margin({ left: 16 })

      SymbolGlyph($r('sys.symbol.chevron_right'))
        .fontSize(20)
        .fontColor([ThemeAwareHelper.getTestManagementThemedColor('text_muted', this.themeState.currentTheme)])
    }
    .width('100%')
    .height(64)
    .padding({ left: 16, right: 16 })
    .onClick(() => {
      if (onClick) {
        onClick();
      } else {
        this.showToast(`${title}功能开发中...`);
      }
    })
  }

  /**
   * 构建导航目标页面
   */
  @Builder
  buildNavDestination(name: string, param: ESObject) {
    // 测试页面导航已移除
    // if (name === 'TestManagementPage') {
    //   TestManagementPage()
    // } else
    if (name === 'DataManagementPage') {
      DataManagementPage()
    } else if (name === 'DownloadSyncPage') {
      DownloadSyncPage()
    } else if (name === 'MangaReaderPage') {
      MangaReaderPage()
    } else if (name === 'MangaDetailPage') {
      MangaDetailPage()
    } else if (name === 'CoverSelectionPage') {
      CoverSelectionPage()
    } else if (name === 'MangaSettingsPage') {
      MangaSettingsPage()
    } else if (name === 'SearchPage') {
      SearchPage()
    } else if (name === 'GlobalSearchPage') {
      GlobalSearchPage()
    } else if (name === 'WebViewConfigurableSystemTestPage') {
      WebViewConfigurableSystemTestPage()
    } else if (name === 'MangaSourceTestPage') {
      MangaSourceTestPage()
    } else if (name === 'DummyPage') {
      DummyPage()
    } else if (name === 'SystemAnimationDemoPage') {
      SystemAnimationDemoPage()
    } else if (name === 'SystemResourceDemoPage') {
      SystemResourceDemoPage()
    } else if (name === 'HelloWorldPage') {
      HelloWorldPage()
    } else if (name === 'SystemStatusPage') {
      SystemStatusPage()
    } else if (name === 'GlobalSettingsPage') {
      GlobalSettingsPage()
    } else if (name === 'ReadingSettingsSubPage') {
      ReadingSettingsSubPage()
    } else if (name === 'NetworkSettingsSubPage') {
      NetworkSettingsSubPage()
    } else if (name === 'NotificationSettingsSubPage') {
      NotificationSettingsSubPage()
    } else if (name === 'AdvancedSettingsSubPage') {
      AdvancedSettingsSubPage()
    } else if (name === 'InteractionSettingsSubPage') {
      InteractionSettingsSubPage()
    } else if (name === 'DownloadManagerPage') {
      DownloadManagerPage()
    } else if (name === 'AboutPage') {
      AboutPage()
    } else if (name === 'ReadingAnalyticsPage') {
      ReadingAnalyticsPage()
    } else if (name === 'MangaFeedbackPage') {
      MangaFeedbackPage()
    } else if (name === 'LogManagerPage') {
      LogManagerPage()
    } else if (name === 'OpenSourceLicensePage') {
      OpenSourceLicensePage()
    } else if (name === 'UserAgreementPage') {
      UserAgreementPage()
    } else if (name === 'PrivacyPolicyPage') {
      PrivacyPolicyPage()
    } else if (name === 'EBookReaderPage') {
      EBookReaderPage()
    } else if (name === 'EBookDetailPage') {
      EBookDetailPage()
    } else if (name === 'EBookSettingsPage') {
      EBookSettingsPage()
    } else if (name === 'ThemeSettingsPage') {
      ThemeSettingsPage()
    } else if (name === 'StorageManagementPage') {
      StorageManagementPage()
    } else if (name === 'SourceDetailPage') {
      SourceDetailPage()
    } else if (name === 'SourceSettingsPage') {
      SourceSettingsPage()
    } else if (name === 'SourceLoginPage') {
      SourceLoginPage()
    } else if (name === 'OnlineEBookDetailPage') {
      OnlineEBookDetailPage()
    } else if (name === 'NovelBookshelfPage') {
      NovelBookshelfPage()
    } else if (name === 'NovelSearchPage') {
      NovelSearchPage()
    } else if (name === 'NovelDetailPage') {
      NovelDetailPage()
    } else if (name === 'NovelReaderPage') {
      NovelReaderPage()
    } else if (name === 'NovelSourceManagementPage') {
      NovelSourceManagementPage()
    } else if (name === 'NovelExplorePage') {
      NovelExplorePage()
    } else if (name === 'NovelSourceLoginPage') {
      NovelSourceLoginPage()
    } else if (name === 'NovelReplaceRulePage') {
      NovelReplaceRulePage()
    } else if (name === 'NovelSettingsPage') {
      NovelSettingsPage()
    } else if (name === 'NovelSourceDebugPage') {
      NovelSourceDebugPage()
    } else if (name === 'NovelTxtTocRulePage') {
      NovelTxtTocRulePage()
    } else if (name === 'NovelDictRulePage') {
      NovelDictRulePage()
    } else if (name === 'JsvmPlaygroundPage') {
      JsvmPlaygroundPage()
    } else if (name === 'LifecycleMonitorPage') {
      LifecycleMonitorPage()
    } else if (name === 'BackupPage') {
      BackupPage()
    } else if (name === 'FileEditorPage') {
      FileEditorPage()
    } else if (name === 'SystemResourcePreviewPage') {
      SystemResourcePreviewPage()
    } else if (name === 'HelpCenterPage') {
      HelpCenterPage()
    } else if (name === 'FontSettingsSubPage') {
      FontSettingsSubPage()
      // 测试页面导航已移除
      // } else if (name === 'ReaderKitTestPage') {
      //   ReaderKitTestPage()
      // } else if (name === 'PdfKitTestPage') {
      //   PdfKitTestPage()
      // } else if (name === 'ScraperTestPage') {  // 已移除，备份为 .bak
      //   ScraperTestPage()
    }
  }

  /**
   * 获取可见的标签配置（根据用户自定义配置和高级模式过滤）
   */
  private getVisibleTabConfigs(): TabConfig[] {
    return this.tabConfigs.filter((cfg: TabConfig) => {
      // 必须显示的标签（书库、设置）始终显示
      if (cfg.required) {
        return true;
      }
      
      // 图源标签仅在高级模式下显示
      if (cfg.index === TabIndex.SOURCE && !this.advancedModeEnabled) {
        return false;
      }
      
      // 检查是否在用户自定义的可见列表中
      return this.visibleTabIndices.includes(cfg.index);
    });
  }

  /**
   * 底栏
   * 根据高级模式动态显示标签
   */
  @Builder
  buildHorizontalTabBar() {
    Row({ space: 0 }) {
      ForEach(this.getVisibleTabConfigs(), (cfg: TabConfig, _idx: number) => {
        this.buildHorizontalTabButton(cfg)
      })
    }
    .width('100%')
    .height(this.BOTTOM_BAR_HEIGHT)
    .padding({ left: 16, right: 16 })
    .backgroundColor(this.getGlassBackground())
    .backgroundBlurStyle(this.getGlassBlur())
    .borderRadius(this.getGlassRadius())
    .shadow({ radius: this.getGlassRadius(), color: this.getGlassShadowColor(), offsetX: 0, offsetY: 4 })
  }

  /**
   * 触发轻微震动反馈
   */
  private triggerHapticFeedback(): void {
    InteractionManager.getInstance().vibrate(VibrationScene.BUTTON_CLICK);
  }

  /**
   * 底栏按钮与点击逻辑简化：通过索引内部获取配置并处理点击
   */
  private handleTabButtonClick(index: number): void {
    try {
      // 触发震动反馈
      this.triggerHapticFeedback();

      this.currentTabIndex = index;
      this.tabsController.changeIndex(index);
    } catch (error) {
      const message: string = error instanceof Error ? error.message : String(error);
      logger.error(TAG, '底栏按钮点击处理失败', message);
    }
  }

  @Builder
  buildHorizontalTabButton(config: TabConfig) {
    Column({ space: 4 }) {
      this.buildTabItem(config)
    }
    .width('100%')
    .height(56)
    .layoutWeight(1)
    .justifyContent(FlexAlign.Center)
    .padding(0)
    .margin({ left: 12, right: 12 })
    .onClick(() => { this.handleTabButtonClick(config.index) })
  }


  // 单个标签项 Builder：仅负责UI呈现，选中态由当前@State索引驱动
  @Builder
  buildTabItem(config: TabConfig) {
    Column({ space: 4 }) {
      // 图标容器（用于显示红点）
      Stack() {
        if (config.useSystemIcon && config.systemIcon) {
          // 使用系统图标（SymbolGlyph）
          if (config.hasMultiColor && this.currentTabIndex === config.index) {
            // 多色效果（仅在选中时）
            SymbolGlyph(config.systemIcon)
              .fontSize(24)
              .fontColor([ThemeAwareHelper.getTestManagementThemedColor('accent_primary', this.themeState.currentTheme)])
              .renderingStrategy(SymbolRenderingStrategy.MULTIPLE_COLOR)
              .symbolEffect(new BounceSymbolEffect(EffectScope.WHOLE, EffectDirection.UP), this.currentTabIndex === config.index)
          } else {
            // 单色效果或未选中
            SymbolGlyph(config.systemIcon)
              .fontSize(24)
              .fontColor([this.currentTabIndex === config.index
                ? ThemeAwareHelper.getTestManagementThemedColor('accent_primary', this.themeState.currentTheme)
                : ThemeAwareHelper.getTestManagementThemedColor('text_secondary', this.themeState.currentTheme)])
              .renderingStrategy(SymbolRenderingStrategy.SINGLE)
              .symbolEffect(new BounceSymbolEffect(EffectScope.WHOLE, EffectDirection.UP), this.currentTabIndex === config.index)
          }
        } else {
          // 使用传统图标
          Image(this.currentTabIndex === config.index ? config.selectedIcon : config.icon)
            .width(24)
            .height(24)
            .fillColor(this.currentTabIndex === config.index
              ? ThemeAwareHelper.getTestManagementThemedColor('accent_primary', this.themeState.currentTheme)
              : ThemeAwareHelper.getTestManagementThemedColor('text_secondary', this.themeState.currentTheme))
        }
        
        // 图源标签的红点提示
        if (config.index === TabIndex.SOURCE && this.hasSourceUpdate) {
          Circle()
            .width(8)
            .height(8)
            .fill('#FF4444')
            .position({ x: 16, y: 0 })
        }
      }
      .width(24)
      .height(24)

      Text(config.title)
        .fontSize(this.responsive_tabBarVertical ? 10 : 12)
        .fontFamily(this.appFontFamily)
        .fontColor(this.currentTabIndex === config.index
          ? ThemeAwareHelper.getTestManagementThemedColor('accent_primary', this.themeState.currentTheme)
          : ThemeAwareHelper.getTestManagementThemedColor('text_secondary', this.themeState.currentTheme))
        .fontWeight(this.currentTabIndex === config.index ? FontWeight.Medium : FontWeight.Normal)
        .maxLines(this.responsive_tabBarVertical ? 2 : 1)
        .textAlign(TextAlign.Center)
    }
    .width(this.responsive_tabBarVertical ? ResponsiveLayoutHelper.getSidebarWidth() : '100%')
    .height(this.responsive_tabBarVertical ? '100%' : 56)
    .justifyContent(FlexAlign.Center)
    .padding(this.responsive_tabBarVertical ? { left: 8, right: 8 } : 0)
  }

  // 悬浮 + 模糊玻璃背景（纯修饰符，不使用@Builder，不包含逻辑语句）
  private createBarGlassModifier(): CommonModifier {
    const modifier: CommonModifier = ThemeManager.getInstance().createGlassModifier();
    // 组件自身控制布局留白，主题方法仅提供视觉效果
    modifier
      .margin({ left: 12, right: 12, bottom: 8 })
      .padding({ left: 16, right: 16 });
    return modifier;
  }

  /**
   * 获取玻璃效果背景资源（根据当前主题返回不同的颜色）
   * 深色模式：半透明深色背景；浅色模式：半透明浅色背景
   */
  private getGlassBackground(): ResourceColor {
    if (this.themeState.currentTheme === ThemeType.LIGHT) {
      return 'rgba(255, 255, 255, 0.7)'; // 浅色模式：半透明白色
    } else {
      return 'rgba(30, 30, 30, 0.7)'; // 深色模式：半透明深灰色
    }
  }

  /**
   * 获取玻璃效果模糊样式（根据当前主题返回不同的模糊样式）
   */
  private getGlassBlur(): BlurStyle {
    if (this.themeState.currentTheme === ThemeType.LIGHT) {
      return BlurStyle.Thin; // 浅色模式使用较薄的模糊
    } else {
      return BlurStyle.Regular; // 深色模式使用常规模糊
    }
  }

  /**
   * 获取玻璃效果圆角（依赖 themeState 以触发 UI 更新）
   */
  private getGlassRadius(): number {
    const _theme = this.themeState.currentTheme;
    return this.themeManager.getGlassRadius();
  }

  /**
   * 获取玻璃效果阴影颜色（根据当前主题返回不同的阴影颜色）
   */
  private getGlassShadowColor(): string {
    if (this.themeState.currentTheme === ThemeType.LIGHT) {
      return 'rgba(0, 0, 0, 0.1)'; // 浅色模式：较浅的阴影
    } else {
      return 'rgba(0, 0, 0, 0.3)'; // 深色模式：较深的阴影
    }
  }

  build() {
    Stack() {
    Navigation(this.pathStack) {
      Stack() {
        // 背景层 - 自动显示自定义主题背景或默认背景色
        GlobalBackgroundLayer({
          defaultBackgroundColor: ThemeAwareHelper.getTestManagementThemedColor('background_primary', this.themeState.currentTheme)
        })

        // 主内容区域（透明背景以显示自定义主题）
        Column() {
          // 顶部标题栏：平板横屏显示专用顶栏，其他设备显示默认顶栏
          // 使用barRenderKey触发重新渲染（屏幕方向或折叠状态变化时）
          Column() {
            if (this.deviceManager.isTabletOrLarger()) {
              // 平板横屏专用顶栏
              this.buildTabletTopBar()
            } else {
              // 其他设备默认顶栏
              this.buildTopBar()
            }
          }
          .key(`topBar_${this.barRenderKey}`)

          // 主要内容区域包装器 - 包含底部导航栏避让
          Column() {
            // 主要内容区域 - 使用Tabs实现底部导航（响应式：横屏大屏设备时在左侧）
            Tabs({
              controller: this.tabsController
            }) {
              // 首页标签
              TabContent() {
                Scroll() { this.buildHomeContent() }
                .width('100%').height('100%').scrollBar(BarState.Off).edgeEffect(EdgeEffect.Spring).backgroundColor(Color.Transparent)
              }
              .backgroundColor(Color.Transparent)

              // 书库标签
              TabContent() {
                Refresh({ refreshing: this.isRefreshing }) {
                  Scroll() { this.buildLibraryContent() }
                  .width('100%').height('100%').scrollBar(BarState.Off).backgroundColor(Color.Transparent)
                }
                .onRefreshing(() => {
                  this.refreshMangaList();
                })
                .width('100%')
                .height('100%')
                .backgroundColor(Color.Transparent)
              }
              .backgroundColor(Color.Transparent)

              // 发现标签
              TabContent() {
                Refresh({ refreshing: $$this.isRefreshingDiscover }) {
                  Scroll() { this.buildDiscoverContent() }
                  .width('100%').height('100%').scrollBar(BarState.Off).edgeEffect(EdgeEffect.Spring).backgroundColor(Color.Transparent)
                }
                .onRefreshing(() => {
                  this.refreshDiscoverData();
                })
              }
              .backgroundColor(Color.Transparent)

              // 图源标签（高级模式）
              TabContent() {
                this.buildSourceContent()
              }
              .backgroundColor(Color.Transparent)

              // 书源标签（已暂时注释）
              // TabContent() {
              //   this.buildBookSourceContent()
              // }
              // .backgroundColor(Color.Transparent)

              // 设置标签
              TabContent() {
                Column() { this.buildSettingsContent() }
                .width('100%').height('100%').backgroundColor(Color.Transparent)
              }
              .backgroundColor(Color.Transparent)
            }
            .layoutWeight(1)
            .backgroundColor(Color.Transparent)
            .barBackgroundColor(Color.Transparent)
            .barHeight(0)
            .onChange((index: number) => {
              this.currentTabIndex = index;
              logger.info(TAG, `标签页切换到索引: ${index}`);

              // 切换标签时静默刷新对应数据（不显示加载状态，避免闪屏）
              switch (index) {
                case TabIndex.HOME:
                  // 首页：静默刷新最近阅读列表
                  this.silentRefreshRecentReadingList();
                  break;
                case TabIndex.LIBRARY:
                  // 书库：静默刷新漫画和电子书列表
                  this.silentRefreshLibrary();
                  break;
                case TabIndex.DISCOVER:
                  // 发现页：静默刷新发现页数据
                  this.silentRefreshDiscoverData();
                  break;
                default:
                  break;
              }
            })
          }
          .layoutWeight(1)
          .width('100%')

        }
        .width('100%')
        .height('100%')
        .backgroundColor(Color.Transparent) // 透明背景以显示全局背景层

        // 底栏：使用barRenderKey触发重新渲染（屏幕方向或折叠状态变化时）
        if (this.responsive_tabBarPosition === BarPosition.End) {
          Column() {
            this.buildHorizontalTabBar()
          }
          .width(this.getBottomBarWidth())
          .height(this.BOTTOM_BAR_HEIGHT)
          .backgroundColor(Color.Transparent)
          .position({ x: this.getBottomBarX(), y: this.getBottomBarY() })
          .key(`bottomBar_${this.barRenderKey}`)
        }


        // 筛选对话框
        if (this.showLibraryFilterDialog) {
          this.buildLibraryFilterDialog()
        }

        // 创建分类对话框
        if (this.showCreateCategoryDialog) {
          this.buildCreateCategoryDialog()
        }

        // 编辑分类对话框
        if (this.showEditCategoryDialog) {
          this.buildEditCategoryDialog()
        }

        // 移动到分类对话框
        if (this.showMoveToCategoryDialog) {
          Column() {
            this.buildMoveToCategoryDialog()
          }
          .width('100%')
          .height('100%')
          .zIndex(2000)
          .transition(TransitionEffect.OPACITY.animation({ duration: 200, curve: Curve.EaseOut }))
        }

        // 标签自定义对话框（从底部滑入）
        Column() {
          this.buildTabCustomizationDialog()
        }
        .width('100%')
        .position({ x: 0, y: '100%' })
        .translate({ y: this.showTabCustomDialog ? '-100%' : '0%' })
        .animation({ 
          duration: 300, 
          curve: Curve.EaseInOut 
        })
        .zIndex(1000)
        .visibility(this.showTabCustomDialog ? Visibility.Visible : Visibility.None)



        // 日志悬浮窗口
        if (this.enableLogFloatingWindow) {
          LogFloatingWindow()
        }

        // 后台任务悬浮球
        TaskFloatingBall()

        // 全局WebView容器（隐藏，用于后台WebView操作）
        WebViewContainer()
          .width(0)
          .height(0)
          .visibility(Visibility.None)
      }
    }
    .navDestination(this.buildNavDestination)
    .mode(NavigationMode.Stack)
    .width('100%')
    .height('100%')
    .hideTitleBar(true)
    .onAppear(() => {
      // 注册全局WebView容器
      // 注意：由于组件引用限制，这里暂时无法直接获取WebViewContainer实例
      // 需要通过GlobalWebViewContainer的静态方法来管理
      logger.info(TAG, '全局WebView容器已创建');
    })
      
    // 书籍翻开/关闭过渡动画覆盖层（放在Navigation外部的最顶层）
    BookTransitionOverlay()
    
    // 全局帮助面板覆盖层
    HelpPanelOverlayV2({ themeState: this.themeState })
    
    // 后台模糊遮罩层（当应用进入后台且启用了模糊遮罩时显示）
    BackgroundBlurOverlay({
      isVisible: this.isInBackground && this.backgroundBlurEnabled,
      bgType: this.backgroundBlurBgType,
      customBgImage: this.backgroundBlurBgImage,
      iconType: this.backgroundBlurIconType,
      currentTheme: this.themeState.currentTheme
    })
    }
    .width('100%')
    .height('100%')
  }
}

export { MainMenuPage };
