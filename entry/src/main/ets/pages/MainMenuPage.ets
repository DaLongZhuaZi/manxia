// 文件路径: src/main/ets/pages/MainMenuPage.ets
// 职责: 漫画阅读应用主入口页面，采用底部导航栏设计，参考Mihon、komikku等现代漫画阅读软件

import { logger } from '../Utils/Logger';
import { common } from '@kit.AbilityKit';
import { deviceInfo, BusinessError } from '@kit.BasicServicesKit';
import { CommonModifier, LengthMetrics, router } from '@kit.ArkUI';
import { image } from '@kit.ImageKit';
import fs from '@ohos.file.fs';
import { picker } from '@kit.CoreFileKit';
import { vibrator } from '@kit.SensorServiceKit';

// 主题相关导入
import { ComicConverter } from '../Framework/Utils/ComicConverter';
import { ThemeAwareState, ThemeAwareHelper } from '../Framework/Components/ThemeAware';
import { GlobalBackgroundLayer } from '../Framework/Components/GlobalBackgroundLayer';
import { AppNotificationManager } from '../Framework/Managers/NotificationManager';

// 导入页面组件
// 测试页面导入已移除，测试功能仍保留在代码中但不再从主菜单导航
// import { TestManagementPage } from './TestManagementPage';
import { DataManagementPage } from './DataManagementPage';
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
import { GlobalSettingsPage } from './GlobalSettingsPage';
import { DownloadManagerPage } from './DownloadManagerPage';
import { AboutPage } from './AboutPage';
import { ReadingAnalyticsPage } from './ReadingAnalyticsPage';
import { MangaFeedbackPage } from './MangaFeedbackPage';
import { LogManagerPage } from './LogManagerPage';
import { SourceGuidePage } from './SourceGuidePage';
import { OpenSourceLicensePage } from './OpenSourceLicensePage';
import { UserAgreementPage } from './UserAgreementPage';
import { PrivacyPolicyPage } from './PrivacyPolicyPage';
import { SourceDetailPage } from './SourceDetailPage';
import { WebViewContainer, GlobalWebViewContainer } from '../Framework/WebView/WebViewContainerPage';
import { EBookReaderPage, EBookReaderParams } from './EBookReaderPage';
import { ThemeSettingsPage } from './ThemeSettingsPage';
import { CoverSelectionPage } from './CoverSelectionPage';
import { LogFloatingWindow } from '../Utils/LogFloatingWindow';
import { WindowManager } from '../Utils/WindowManager';
import { SourceSettingsPage } from './SourceSettingsPage';
import { SourceLoginPage } from './SourceLoginPage';
import { StorageManagementPage } from './StorageManagementPage';
import { TaskFloatingBall } from '../Framework/Components/TaskFloatingBall';
// 测试页面导入已移除
// import { ReaderKitTestPage } from './ReaderKitTestPage';
// import { PdfKitTestPage } from './PdfKitTestPage';
import { ScraperTestPage } from './ScraperTestPage';

// 导入示例数据
import { SAMPLE_MANGA, createSampleMangaList, getDefaultTestManga } from '../Data/SampleMangaData';
import { MangaReaderPageParams, MangaReaderContentType } from './MangaReaderPage';
import { Manga, MangaChapter, MangaMetadata, ReadingProgress, ReadingSettings, FilterSettings, ImageSourceType,
  ReadingMode,
  ReadingDirection,
  DEFAULT_READING_SETTINGS} from '../Models/MangaModels';
import { MangaStatus, ReadingStatus, StatusConverter, DownloadStatus } from '../Framework/Types/StatusEnums';

// 导入图源相关
import { SourceManager, SourceInfo } from '../Framework/Source/SourceManager';
import { SourceRepositoryManager, SavedRepository, SourceRepositoryEntry, SyncResult } from '../Framework/Source/SourceRepositoryManager';

// 导入数据管理器
import { DataManager, ComicInfo, ReadHistory, PageInfo, ChapterInfo } from '../Framework/Data/DataManager';
import { ComicSourceDatabaseRecord } from '../Framework/Database/DatabaseTypes';

import { ThemeManager, ThemeType, GlassEffectContext } from '../Framework/Managers/ThemeManager';
import { DataService } from '../Framework/Services/DataService';
import { EBookDataManager } from '../Framework/Data/EBookDataManager';

// 导入电子书相关模型
import { EBook, EBookStatus } from '../Models/EBookModels';
import { EBookDetailPage, EBookDetailPageParams, EBookSettingsPageParams } from './EBookDetailPage';
import { EBookSettingsPage } from './EBookSettingsPage';

// 导入事件总线
import { eventBus, GameEvent, IEventPayload, MangaImportCompletedPayload, FileImportRequestedPayload, MangaDeletedPayload } from '../Framework/EventBus';
import { WelcomeGuideManager } from '../Framework/Managers/WelcomeGuideManager';
import { SourceUpdateManager } from '../Framework/Managers/SourceUpdateManager';

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
}

/**
 * 底部导航标签页枚举
 */
enum TabIndex {
  HOME = 0,
  LIBRARY = 1,
  DISCOVER = 2,
  SOURCE = 3,      // 图源（高级模式）
  SETTINGS = 4
}

/**
 * 书库内容类型枚举
 */
enum LibraryContentType {
  MANGA = 'manga',     // 漫画
  EBOOK = 'ebook'      // 电子书
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
  GRID = 'grid'      // 网格视图
}

/**
 * 导航标签配置接口
 */
interface TabConfig {
  title: string;
  icon: ResourceStr;
  selectedIcon: ResourceStr;
  index: TabIndex;
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
  private welcomeGuideManager: WelcomeGuideManager = WelcomeGuideManager.getInstance();
  private componentId: string = 'MainMenuPage';

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
  @State libraryFilterType: LibraryFilterType = LibraryFilterType.FAVORITE;
  @State libraryViewMode: LibraryViewMode = LibraryViewMode.GRID;
  @State showLibraryFilterDialog: boolean = false;
  @State showLibraryFilterPopup: boolean = false;
  @State filteredMangaList: Manga[] = [];
  
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
  
  // 电子书多选模式相关状态
  @State isEBookMultiSelectMode: boolean = false;
  @State selectedEBookIds: Set<string> = new Set();
  @State isDeletingEBook: boolean = false;

  // 图源仓库相关状态
  @State showSourceRepoDialog: boolean = false;
  @State sourceRepoUrl: string = '';
  @State isSyncingRepo: boolean = false;
  @State savedRepositories: SavedRepository[] = [];
  @State selectedRepositoryId: string = '';
  @State showRepositorySelector: boolean = false;
  @State showDeleteRepoPopup: boolean = false;
  @State repositoryToDelete: SavedRepository | null = null;
  private sourceRepoDialogController: CustomDialogController | undefined = undefined;
  private repositoryManager: SourceRepositoryManager = SourceRepositoryManager.getInstance();

  // 最近阅读相关状态
  @State recentReadingList: Manga[] = [];
  @State recentEBookList: EBook[] = [];
  @State isLoadingRecentReading: boolean = false;
  private readonly RECENT_HISTORY_LIMIT: number = 100;

  // 发现页面相关状态
  @State allTags: string[] = []; // 所有标签（按出现次数倒序）
  @State allAuthors: string[] = []; // 所有作者（按出现次数倒序）
  @State selectedTag: string = ''; // 选中的标签
  @State selectedAuthor: string = ''; // 选中的作者
  @State discoveredMangaList: Manga[] = []; // 发现页面筛选后的漫画列表
  @State discoveredEBookList: EBook[] = []; // 发现页面筛选后的电子书列表
  @State discoverContentType: 'manga' | 'ebook' | 'all' = 'all'; // 发现页面内容类型筛选
  @State isRefreshingDiscover: boolean = false; // 是否正在刷新发现页面

  // 图源相关状态
  @State sourceList: SourceInfo[] = []; // 图源列表
  @State filteredSourceList: SourceInfo[] = []; // 筛选后的图源列表
  @State sourceSearchKeyword: string = ''; // 图源搜索关键词
  @State isLoadingSourceList: boolean = false; // 是否正在加载图源列表
  @State isRefreshingSourceList: boolean = false; // 是否正在下拉刷新图源列表
  @State hasSourceUpdate: boolean = false; // 是否有图源更新
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
  @State private hasUserDockPreference: boolean = false;
  @State private userDockPosition: BarPosition = BarPosition.Start;
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

  // 轮播内容数据
  private bannerData: Array<bannerData> = [
    {
      title: '欢迎使用漫匣',
      subtitle: '发现精彩的漫画世界',
      image: $r('app.media.foreground'),
      backgroundColor: '#FF6B6B'
    },
    {
      title: '海量漫画资源',
      subtitle: '热门连载，经典完结作品',
      image: $r('app.media.mangabook'),
      backgroundColor: '#4ECDC4'
    },
    {
      title: '个性化推荐',
      subtitle: '根据你的喜好推荐精彩内容',
      image: $r('app.media.ic_theme'),
      backgroundColor: '#45B7D1'
    }
  ];

  // 系统初始化状态
  @State private isSystemInitialized: boolean = false;
  @State private initializationProgress: string = '正在初始化...';

  // 版本信息
  @State public appVersion: string = '0.0.4';
  @State public systemVersion: string = '';

  @StorageProp('enable_log_floating_window') private enableLogFloatingWindow: boolean = false;
  @StorageLink('advanced_mode_enabled') private advancedModeEnabled: boolean = false;
  @StorageProp('force_tablet_mode') private forceTabletMode: boolean = false;
  @StorageProp('force_landscape_mode') private forceLandscapeMode: boolean = false;

  // 导航标签配置
  private tabConfigs: TabConfig[] = [
    {
      title: '首页',
      icon: $r('app.media.ic_home_normal'),
      selectedIcon: $r('app.media.ic_home_selected'),
      index: TabIndex.HOME
    },
    {
      title: '书库',
      icon: $r('app.media.ic_library_normal'),
      selectedIcon: $r('app.media.ic_library_selected'),
      index: TabIndex.LIBRARY
    },
    {
      title: '发现',
      icon: $r('app.media.ic_discover_selected'),
      selectedIcon: $r('app.media.ic_discover_selected'),
      index: TabIndex.DISCOVER
    },
    {
      title: '图源',
      icon: $r('app.media.ic_source_normal'),
      selectedIcon: $r('app.media.ic_source_selected'),
      index: TabIndex.SOURCE
    },
    {
      title: '设置',
      icon: $r('app.media.ic_settings'),
      selectedIcon: $r('app.media.ic_settings'),
      index: TabIndex.SETTINGS
    }
  ];

  aboutToAppear() {
    logger.lifecycle(TAG, '🚀 漫画阅读应用启动');

    // 使用 @StorageProp 自动响应设置变化，无需手动从 AppStorage 加载

    // 处理路由参数
    this.handleRouteParams();
    
    // 请求通知权限（首次进入主页面时）
    this.requestNotificationPermission();

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

    this.initializeSystem();
    this.loadVersionInfo();
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
        logger.info(TAG, `设备状态变化: 断点=${deviceInfo.breakpoint}, 方向=${deviceInfo.orientation}`);
        this.applyOrientationPreference();
        this.updateResponsiveParams();
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
    
    if (this.hasUserDockPreference) {
      this.responsive_tabBarPosition = this.userDockPosition;
      this.responsive_tabBarVertical = false;
    } else {
      if (this.forceTabletMode) {
        this.responsive_tabBarPosition = BarPosition.Start;
        this.responsive_tabBarVertical = false;
      } else {
        if (deviceInfo.isLandscape && (deviceInfo.breakpoint === Breakpoint.MD || deviceInfo.breakpoint === Breakpoint.LG)) {
          this.responsive_tabBarPosition = BarPosition.Start;
          this.responsive_tabBarVertical = false;
        } else {
          this.responsive_tabBarPosition = BarPosition.End;
          this.responsive_tabBarVertical = false;
        }
      }
    }
    
    logger.debug(TAG, `响应式参数更新: 列数=${this.responsive_gridColumns}, 间距=${this.responsive_gridGap}, 标签栏位置=${this.responsive_tabBarPosition}, 垂直=${this.responsive_tabBarVertical}`);
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
   * 切换顶栏停靠位置
   */
  private toggleTabBarDock(): void {
    const next: BarPosition = this.responsive_tabBarPosition === BarPosition.End ? BarPosition.Start : BarPosition.End;
    this.userDockPosition = next;
    this.hasUserDockPreference = true;
    this.responsive_tabBarPosition = next;
    this.responsive_tabBarVertical = false;
    logger.info(TAG, `顶栏位置切换到${next === BarPosition.Start ? '顶部' : '底部'}`);
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
   * 切换书库视图模式
   */
  private toggleLibraryViewMode(): void {
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
    if (sourceType === ImageSourceType.LOCAL) {
      let file: fs.File | null = null;
      try {
        const hasScheme: boolean = path.indexOf('file://') === 0;
        const actualPath: string = hasScheme ? path.substring(7) : path;
        file = fs.openSync(actualPath, fs.OpenMode.READ_ONLY);
        const src: image.ImageSource = image.createImageSource(file.fd);
        const info: image.ImageInfo = await src.getImageInfo();
        const w: number = info.size.width;
        const h: number = info.size.height;
        if (w > 0 && h > 0) {
          return w / h;
        }
      } catch (err) {
        const msg: string = err instanceof Error ? err.message : String(err);
        logger.warn(TAG, msg);
      } finally {
        if (file) {
          try {
            fs.closeSync(file);
          } catch (cerr) {
            const cm: string = cerr instanceof Error ? cerr.message : String(cerr);
            logger.warn(TAG, cm);
          }
        }
      }
      return null;
    }
    if (sourceType === ImageSourceType.RAWFILE || sourceType === ImageSourceType.NETWORK) {
      try {
        const src: image.ImageSource = image.createImageSource(path);
        const info: image.ImageInfo = await src.getImageInfo();
        const w: number = info.size.width;
        const h: number = info.size.height;
        if (w > 0 && h > 0) {
          return w / h;
        }
      } catch (err2) {
        const m2: string = err2 instanceof Error ? err2.message : String(err2);
        logger.warn(TAG, m2);
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
   * 构建最近阅读瀑布流
   */
  @Builder
  buildRecentReadingWaterfall() {
    Flex({ wrap: FlexWrap.Wrap, space: { main: LengthMetrics.vp(12), cross: LengthMetrics.vp(12) } }) {
      ForEach(this.recentReadingList, (manga: Manga, idx: number) => {
        Column({ space: 8 }) {
          Image(this.normalizeDisplayPathForManga(manga) || $r('app.media.mangabook'))
            .width('100%')
            .aspectRatio(this.getAdaptiveCoverAspect(manga, idx))
            .objectFit(ImageFit.Cover)
            .borderRadius(8)
            .backgroundColor(ThemeAwareHelper.getTestManagementThemedColor('background_secondary', this.themeState.currentTheme))
            .shadow({ radius: 8, color: '#1F000000', offsetY: 4 })
            .onError(() => {
              logger.warn('MainMenuPage', `最近阅读封面加载失败: raw='${manga.coverImagePath}', display='${this.normalizeDisplayPathForManga(manga)}', source=${manga.coverSourceType}`);
            })

          Text(manga.title)
            .fontSize(14)
            .fontWeight(FontWeight.Medium)
            .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_primary', this.themeState.currentTheme))
            .maxLines(2)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
        }
        .width(this.getWaterfallItemWidth())
        .onClick(() => { this.openMangaDetail(manga); })
      }, (manga: Manga) => manga.id)
    }
    .width('100%')
  }

  @Builder
  buildRecentEBookWaterfall() {
    Flex({ wrap: FlexWrap.Wrap, space: { main: LengthMetrics.vp(12), cross: LengthMetrics.vp(12) } }) {
      ForEach(this.recentEBookList, (ebook: EBook, idx: number) => {
        Column({ space: 8 }) {
          Image(this.normalizeDisplayPathForEBook(ebook) || $r('app.media.mangabook'))
            .width('100%')
            .aspectRatio(this.getWaterfallAspectRatio(idx))
            .objectFit(ImageFit.Cover)
            .borderRadius(8)
            .backgroundColor(ThemeAwareHelper.getTestManagementThemedColor('background_secondary', this.themeState.currentTheme))
            .shadow({ radius: 8, color: '#1F000000', offsetY: 4 })
            .onError(() => {
              logger.warn('MainMenuPage', `电子书封面加载失败: '${this.normalizeDisplayPathForEBook(ebook)}'`);
            })

          Text(ebook.metadata.title)
            .fontSize(14)
            .fontWeight(FontWeight.Medium)
            .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_primary', this.themeState.currentTheme))
            .maxLines(2)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
        }
        .width(this.getWaterfallItemWidth())
        .onClick(() => { this.openEBookDetail(ebook); })
      }, (ebook: EBook) => ebook.id)
    }
    .width('100%')
  }

  /**
   * 加载电子书列表
   */
  private async loadEBookList(): Promise<void> {
    try {
      this.isLoadingEbookList = true;
      logger.info(TAG, '开始加载电子书列表...');
      
      const ebookList = await this.ebookDataManager.getEBookList();
      logger.info(TAG, `从数据库获取到 ${ebookList.length} 本电子书`);
      
      this.ebookList = ebookList;
      this.applyEBookFilter(); // 应用筛选
      
    } catch (error) {
      logger.error(TAG, `加载电子书列表失败: ${String(error instanceof Error ? error.message : error)}`);
      this.ebookList = [];
      this.filteredEbookList = [];
    } finally {
      this.isLoadingEbookList = false;
    }
  }

  /**
   * 应用电子书筛选
   */
  private applyEBookFilter(): void {
    let filtered: EBook[] = [];
    
    switch (this.libraryFilterType) {
      case LibraryFilterType.ALL:
        filtered = this.ebookList;
        break;
      case LibraryFilterType.UNREAD:
        filtered = this.ebookList.filter((ebook: EBook) => {
          return ebook.status === EBookStatus.UNREAD;
        });
        break;
      case LibraryFilterType.READING:
        filtered = this.ebookList.filter((ebook: EBook) => {
          return ebook.status === EBookStatus.READING;
        });
        break;
      case LibraryFilterType.COMPLETED:
        filtered = this.ebookList.filter((ebook: EBook) => {
          return ebook.status === EBookStatus.COMPLETED;
        });
        break;
      case LibraryFilterType.FAVORITE:
        filtered = this.ebookList.filter((ebook: EBook) => {
          return ebook.isFavorite;
        });
        break;
      default:
        filtered = this.ebookList;
    }
    
    this.filteredEbookList = filtered;
    logger.debug(TAG, `电子书筛选完成: 总数=${this.ebookList.length}, 筛选后=${filtered.length}, 类型=${this.libraryFilterType}`);
  }

  /**
   * 切换书库内容类型
   */
  private toggleLibraryContentType(type: LibraryContentType): void {
    if (this.libraryContentType !== type) {
      this.libraryContentType = type;
      logger.info(TAG, `切换书库内容类型: ${type}`);
      
      // 重置筛选条件
      this.libraryFilterType = LibraryFilterType.FAVORITE;
      
      // 切换到电子书时，刷新列表（可能有新导入的书）
      if (type === LibraryContentType.EBOOK) {
        logger.info(TAG, '切换到电子书，刷新列表');
        this.loadEBookList();
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
  private applyLibraryFilter(): void {
    // 首先过滤掉电子书类PDF（contentType === 'ebook'）
    const mangaOnly = this.mangaList.filter((manga: Manga) => {
      return manga.contentType !== 'ebook';
    });
    
    let filtered: Manga[] = [];
    
    switch (this.libraryFilterType) {
      case LibraryFilterType.ALL:
        filtered = mangaOnly;
        break;
      case LibraryFilterType.UNREAD:
        filtered = mangaOnly.filter((manga: Manga) => {
          return manga.readingProgress.currentPageIndex === 0 && 
                 manga.readingProgress.currentChapterId === '';
        });
        break;
      case LibraryFilterType.READING:
        filtered = mangaOnly.filter((manga: Manga) => {
          return manga.readingProgress.currentChapterId !== '' && 
                 manga.readingProgress.readingStatus !== ReadingStatus.COMPLETED;
        });
        break;
      case LibraryFilterType.COMPLETED:
        filtered = mangaOnly.filter((manga: Manga) => {
          return manga.status === MangaStatus.COMPLETED;
        });
        break;
      case LibraryFilterType.FAVORITE:
        filtered = mangaOnly.filter((manga: Manga) => {
          return manga.isFavorite;
        });
        break;
      default:
        filtered = mangaOnly;
        break;
    }
    
    this.filteredMangaList = filtered;
    logger.info(TAG, `应用筛选: ${this.libraryFilterType}, 结果数量: ${filtered.length} (排除电子书类PDF)`);
  }

  /**
   * 初始化内容数据（漫画、电子书、标签和作者）
   * 确保按正确顺序加载数据
   */
  private async initializeContentData(): Promise<void> {
    try {
      logger.info(TAG, '开始初始化内容数据...');
      
      // 先加载漫画和电子书列表
      await this.loadMangaList();
      await this.loadEBookList();
      
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
      
      // 转换为数组并按出现次数倒序排列
      const tagEntries = Array.from(tagCountMap.entries());
      tagEntries.sort((a, b) => b[1] - a[1]);
      this.allTags = tagEntries.map(entry => entry[0]);
      
      const authorEntries = Array.from(authorCountMap.entries());
      authorEntries.sort((a, b) => b[1] - a[1]);
      this.allAuthors = authorEntries.map(entry => entry[0]);
      
      // 初始化发现页面的漫画和电子书列表
      this.discoveredMangaList = [...this.mangaList];
      this.discoveredEBookList = [...this.ebookList];
      
      logger.info(TAG, `提取完成: ${this.allTags.length}个标签, ${this.allAuthors.length}个作者, ${this.mangaList.length}本漫画, ${this.ebookList.length}本电子书`);
    } catch (error) {
      logger.error(TAG, `提取标签和作者信息失败: ${String(error)}`);
      this.allTags = [];
      this.allAuthors = [];
      this.discoveredMangaList = [];
      this.discoveredEBookList = [];
    }
  }

  /**
   * 应用发现页面筛选
   */
  private applyDiscoverFilter(): void {
    try {
      // 筛选漫画
      let filteredManga = [...this.mangaList];
      if (this.selectedTag && this.selectedTag !== '') {
        filteredManga = filteredManga.filter((manga: Manga) => {
          const allTags = [...manga.metadata.genres, ...manga.metadata.themes];
          return allTags.includes(this.selectedTag);
        });
      }
      if (this.selectedAuthor && this.selectedAuthor !== '') {
        filteredManga = filteredManga.filter((manga: Manga) => {
          return manga.metadata.authors.includes(this.selectedAuthor);
        });
      }
      
      // 筛选电子书
      let filteredEBook: EBook[] = [];
      for (const ebook of this.ebookList) {
        filteredEBook.push(ebook);
      }
      if (this.selectedTag && this.selectedTag !== '') {
        filteredEBook = filteredEBook.filter((ebook: EBook) => {
          const allTags: string[] = ebook.metadata.tags || [];
          return allTags.includes(this.selectedTag);
        });
      }
      if (this.selectedAuthor && this.selectedAuthor !== '') {
        filteredEBook = filteredEBook.filter((ebook: EBook) => {
          return ebook.metadata.author === this.selectedAuthor;
        });
      }
      
      // 根据内容类型筛选
      if (this.discoverContentType === 'manga') {
        this.discoveredMangaList = filteredManga;
        this.discoveredEBookList = [];
      } else if (this.discoverContentType === 'ebook') {
        this.discoveredMangaList = [];
        this.discoveredEBookList = filteredEBook;
      } else {
        this.discoveredMangaList = filteredManga;
        this.discoveredEBookList = filteredEBook;
      }
      
      logger.info(TAG, `发现页面筛选: 标签=${this.selectedTag}, 作者=${this.selectedAuthor}, 类型=${this.discoverContentType}, 漫画=${this.discoveredMangaList.length}本, 电子书=${this.discoveredEBookList.length}本`);
    } catch (error) {
      logger.error(TAG, `应用发现页面筛选失败: ${String(error)}`);
      this.discoveredMangaList = [...this.mangaList];
      this.discoveredEBookList = [...this.ebookList];
    }
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
    
    // 移除设备变化监听器
    if (this.deviceChangeListener) {
      this.deviceManager.removeListener(this.deviceChangeListener);
      this.deviceChangeListener = null;
    }
    
    ThemeAwareHelper.cleanupThemeAware(this.componentId);
    
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
   * 页面显示时刷新数据
   */
  onPageShow(): void {
    logger.lifecycle(TAG, '📱 页面显示，检查是否需要刷新数据');
    
    // 刷新电子书列表（可能在其他页面导入了新书）
    if (this.libraryContentType === LibraryContentType.EBOOK) {
      logger.info(TAG, '当前在电子书标签，刷新电子书列表');
      this.loadEBookList();
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
   * 加载图源列表
   */
  private async loadSources(): Promise<void> {
    if (this.isLoadingSourceList) {
      return;
    }

    try {
      this.isLoadingSourceList = true;
      logger.info(TAG, '开始加载图源列表...');

      this.sourceList = await this.sourceManager.getAllSources();
      this.filteredSourceList = [...this.sourceList];

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

    if (!keyword.trim()) {
      this.filteredSourceList = [...this.sourceList];
      return;
    }

    const lowerKeyword = keyword.toLowerCase();
    this.filteredSourceList = this.sourceList.filter((source: SourceInfo) => {
      return source.name.toLowerCase().includes(lowerKeyword) ||
             source.baseUrl.toLowerCase().includes(lowerKeyword) ||
             (source.description && source.description.toLowerCase().includes(lowerKeyword));
    });

    logger.debug(TAG, `搜索"${keyword}"，找到${this.filteredSourceList.length}个结果`);
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
      logger.info(TAG, `开始同步图源仓库: ${urlToSync}`);
      
      // 使用仓库管理器同步
      const result = await this.repositoryManager.syncRepositoryFromUrl(
        urlToSync,
        this.selectedRepositoryId ? undefined : '自定义仓库'
      );
      
      if (result.success) {
        this.showToast(result.message);
        logger.info(TAG, `图源仓库同步成功: ${result.message}`);
        
        // 关闭弹窗
        this.sourceRepoDialogController?.close();
        this.showSourceRepoDialog = false;
        
        // 刷新图源列表和已保存仓库
        await this.loadSources();
        await this.loadSavedRepositories();
      } else {
        this.showToast(result.message);
        logger.error(TAG, `图源仓库同步失败: ${result.message}`);
      }
      
    } catch (error) {
      logger.error(TAG, '同步图源仓库失败', String(error));
      this.showToast(`同步失败: ${String(error)}`);
    } finally {
      this.isSyncingRepo = false;
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
   * [新增] 同时加载本地和在线漫画
   */
  private async loadAllMangaFromDatabase(): Promise<Manga[]> {
    const mangaList: Manga[] = [];
    
    try {
      // 1. 加载本地漫画
      const localComics = await this.dataManager.getAllComics();
      logger.info(TAG, `从comic_info表获取到 ${localComics.length} 条本地漫画记录`);
      
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
      
      // 2. 加载在线漫画
      const onlineComics = await this.dataManager.getAllOnlineComics();
      logger.info(TAG, `从online_comic_info表获取到 ${onlineComics.length} 条在线漫画记录`);
      
      for (const onlineComicInfo of onlineComics) {
        try {
          const manga = await ComicConverter.convertOnlineComicInfoToMangaAsync(onlineComicInfo);
          mangaList.push(manga);
        } catch (convErr) {
          logger.warn(TAG, `转换在线漫画失败: ${String(convErr)}`);
          // 在线漫画没有同步转换方法，跳过
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
      
      // 如果数据库为空，添加一些示例数据用于测试
      if (this.mangaList.length === 0) {
        logger.info(TAG, '数据库为空，使用示例数据');
        this.mangaList = createSampleMangaList();
      }

      // 应用筛选
      this.applyLibraryFilter();
    } catch (error) {
      logger.error(TAG, '加载漫画列表失败', String(error));
      // 如果加载失败，使用示例数据作为后备
      this.mangaList = createSampleMangaList();
      logger.info(TAG, '使用示例数据作为后备');
      // 应用筛选
      this.applyLibraryFilter();
    } finally {
      this.isLoadingMangaList = false;
    }
  }

  /**
    * 获取EVA漫画示例对象
    */
   private getEvaMangaExample(): Manga {
     const defaultMetadata: MangaMetadata = {
       authors: ['庵野秀明'],
       publisher: '角川书店',
       publicationYear: 1995,
       genres: ['科幻', '机甲', '心理'],
       artists: ['贞本义行'],
       themes: ['成长', '心理', '末世'],
       demographics: ['青年']
     };

     const defaultReadingProgress: ReadingProgress = {
       currentChapterId: 'eva-chapter-12',
       currentPageIndex: 0,
       lastReadAt: Date.now(),   
       readingStatus: ReadingStatus.READING,
       totalReadingTime: 3600000, // 1小时
       readingPercentage: 75
     };

    const filterSettings: FilterSettings = {
       enabled: false,
       brightness: 0,
       contrast: 0,
       saturation: 0,
       hue: 0,
       invert: false,
       grayscale: false,
       blur: 0,
       gamma: 0,
       sepia: 0
    };

    const defaultReadingSettings: ReadingSettings = {
      readingDirection: ReadingDirection.LEFT_TO_RIGHT,
      keepScreenOn: true,
      readingMode: ReadingMode.SINGLE_PAGE,
      brightness: 0,
      pageSpacing: 0,
      showPageInfo: false,
      showPageIndicator: false,
      fitMode: '',
      autoPageTurnInterval: 0,
      skipIntroPages: 0,
      pageTurnAnimation: DEFAULT_READING_SETTINGS.pageTurnAnimation,
      doublePagePortraitLayout: DEFAULT_READING_SETTINGS.doublePagePortraitLayout,
      filterSettings: filterSettings,
      volumeKeyNavigation: false,
      curlBackOpacity: 0
    };

     return {
       id: 'eva-manga-001',
       title: '新世纪福音战士',
       alternativeTitles: ['Neon Genesis Evangelion', 'エヴァンゲリオン'],
       description: '在第三次冲击后的世界，14岁的碇真嗣被父亲召唤到第三新东京市，驾驶巨大的人造人EVA与神秘的使徒战斗。',
       coverImagePath: '',
       coverSourceType: ImageSourceType.RESOURCE,
       status: MangaStatus.COMPLETED,
       metadata: defaultMetadata,
       chapters: [], // 章节信息需要单独加载
       readingProgress: defaultReadingProgress,
       bookmarks: [],
       readingSettings: defaultReadingSettings,
       isFavorite: true,
       addedToLibraryAt: Date.now() - 86400000, // 1天前
       lastUpdatedAt: Date.now(),
       sourceInfo: {
         sourceId: 'local-eva',
         sourceName: '本地导入',
         sourceUrl: '',
         sourceLanguage: 'zh-CN',
         requiresLogin: false
       }
     };
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
          { text: '主题切换', color: '#007DFF' },
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
            this.themeManager.toggleTheme();
            this.showToast('主题已切换');
            break;
          case 1:
            this.currentTabIndex = TabIndex.SETTINGS;
            this.tabsController.changeIndex(this.currentTabIndex);
            break;
          case 2:
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
   * 构建顶部标题栏
   * 悬浮玻璃卡片版，与底栏视觉统一
   */
  @Builder
  buildTopBar() {
    Column() {
      Row() {
        // 标题
        Text(this.getPageTitle())
          .fontSize(20)
          .fontWeight(FontWeight.Bold)
          .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_primary', this.themeState.currentTheme))
          .layoutWeight(1)

        // 搜索按钮
        Button() {
          Image($r('app.media.ic_search'))
            .width(24)
            .height(24)
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
          Image($r('app.media.ic_more'))
            .width(24)
            .height(24)
            .fillColor(ThemeAwareHelper.getTestManagementThemedColor('text_primary', this.themeState.currentTheme))
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
      .backgroundColor(ThemeManager.getInstance().getGlassBackgroundResource())
      .backgroundBlurStyle(ThemeManager.getInstance().getGlassBlurStyle())
      .borderRadius(ThemeManager.getInstance().getGlassRadius())
      .shadow({ radius: ThemeManager.getInstance().getGlassRadius(), color: ThemeManager.getInstance().getGlassShadowColor() })
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
        .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_primary', this.themeState.currentTheme))
        .layoutWeight(1)

      Row({ space: 8 }) {
        ForEach(this.getVisibleTabConfigs(), (cfg: TabConfig, _idx: number) => {
          this.buildTopBarInlineTabButton(cfg)
        })
      }

      Button() {
        Image($r('app.media.ic_search'))
          .width(24)
          .height(24)
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
        Image($r('app.media.ic_more'))
          .width(24)
          .height(24)
          .fillColor(ThemeAwareHelper.getTestManagementThemedColor('text_primary', this.themeState.currentTheme))
      }
      .type(ButtonType.Circle)
      .width(40)
      .height(40)
      .backgroundColor(Color.Transparent)
      .onClick(() => {
        this.showMoreOptions();
      })

      // 切换顶栏停靠位置按钮，暂时屏蔽
      // Button() {
      //   Image($r('app.media.ic_sync_normal'))
      //     .width(24)
      //     .height(24)
      // }
      // .type(ButtonType.Circle)
      // .width(40)
      // .height(40)
      // .backgroundColor(Color.Transparent)
      // .onClick(() => {
      //   this.toggleTabBarDock();
      // })
    }
    .width('100%')
    .height(56)
    .padding({ left: 16, right: 16 })
    .backgroundColor(ThemeManager.getInstance().getGlassBackgroundResource())
    .backgroundBlurStyle(ThemeManager.getInstance().getGlassBlurStyle())
    .borderRadius(ThemeManager.getInstance().getGlassRadius())
    .shadow({ radius: ThemeManager.getInstance().getGlassRadius(), color: ThemeManager.getInstance().getGlassShadowColor() })
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
              .fontColor(Color.White)

            Text(item.subtitle)
              .fontSize(this.responsive_isLandscape ? 13 : 16)
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
   * 构建首页内容
   */
  @Builder
  buildHomeContent() {
    Column({ space: 16 }) {
      // 轮播横幅
      this.buildBannerSwiper()

      // 最近阅读
      Column({ space: 12 }) {
        Row() {
          Text('最近阅读')
            .fontSize(18)
            .fontWeight(FontWeight.Medium)
            .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_primary', this.themeState.currentTheme))
        
          Blank()
        
          Text('查看全部')
            .fontSize(14)
            .fontColor(ThemeAwareHelper.getTestManagementThemedColor('accent_primary', this.themeState.currentTheme))
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
              .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_secondary', this.themeState.currentTheme))
              .margin({ left: 8 })
          }
          .width('100%')
          .height(120)
          .justifyContent(FlexAlign.Center)
          .backgroundColor(ThemeManager.getInstance().getGlassBackgroundResource())
          .backgroundBlurStyle(ThemeManager.getInstance().getGlassBlurStyle())
          .borderRadius(ThemeManager.getInstance().getGlassRadius())
          .shadow({ radius: ThemeManager.getInstance().getGlassRadius(), color: ThemeManager.getInstance().getGlassShadowColor(), offsetX: 0, offsetY: 4 })
        } else if (this.recentReadingList.length === 0) {
          // 空状态
          Column({ space: 8 }) {
            Image($r('app.media.ic_library_empty'))
              .width(48)
              .height(48)
              .fillColor(ThemeAwareHelper.getTestManagementThemedColor('text_muted', this.themeState.currentTheme))
            
            Text('暂无阅读记录')
              .fontSize(14)
              .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_muted', this.themeState.currentTheme))
            
            Button('去书库看看')
              .fontSize(14)
              .height(32)
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
          .backgroundColor(ThemeManager.getInstance().getGlassBackgroundResource())
          .backgroundBlurStyle(ThemeManager.getInstance().getGlassBlurStyle())
          .borderRadius(ThemeManager.getInstance().getGlassRadius())
          .shadow({ radius: ThemeManager.getInstance().getGlassRadius(), color: ThemeManager.getInstance().getGlassShadowColor(), offsetX: 0, offsetY: 4 })
        } else {
          this.buildRecentReadingWaterfall()
          this.buildRecentEBookWaterfall()
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
        Image($r('app.media.ic_close'))
          .width(20)
          .height(20)
          .fillColor(ThemeAwareHelper.getTestManagementThemedColor('text_primary', this.themeState.currentTheme))
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
        .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_primary', this.themeState.currentTheme))
        .layoutWeight(1)

      // 全选按钮
      Button('全选')
        .fontSize(14)
        .height(36)
        .backgroundColor(ThemeAwareHelper.getTestManagementThemedColor('button_secondary', this.themeState.currentTheme))
        .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_primary', this.themeState.currentTheme))
        .onClick(() => {
          this.selectAllManga();
        })

      // 删除按钮
      Button('删除')
        .fontSize(14)
        .height(36)
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
        Image($r('app.media.ic_close'))
          .width(20)
          .height(20)
          .fillColor(ThemeAwareHelper.getTestManagementThemedColor('text_primary', this.themeState.currentTheme))
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
        .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_primary', this.themeState.currentTheme))
        .layoutWeight(1)

      // 全选按钮
      Button('全选')
        .fontSize(14)
        .height(36)
        .backgroundColor(ThemeAwareHelper.getTestManagementThemedColor('button_secondary', this.themeState.currentTheme))
        .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_primary', this.themeState.currentTheme))
        .onClick(() => {
          this.selectAllEBooks();
        })

      // 删除按钮
      Button('删除')
        .fontSize(14)
        .height(36)
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
      if (!this.isMultiSelectMode && !this.isEBookMultiSelectMode) {
        Row({ space: 12 }) {
          Button('漫画')
            .fontSize(16)
            .height(40)
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
            .backgroundColor(this.libraryContentType === LibraryContentType.EBOOK
              ? ThemeAwareHelper.getTestManagementThemedColor('accent_primary', this.themeState.currentTheme)
              : Color.Transparent)
            .fontColor(this.libraryContentType === LibraryContentType.EBOOK
              ? ThemeAwareHelper.getTestManagementThemedColor('text_white', this.themeState.currentTheme)
              : ThemeAwareHelper.getTestManagementThemedColor('text_secondary', this.themeState.currentTheme))
            .onClick(() => {
              this.toggleLibraryContentType(LibraryContentType.EBOOK);
            })
          
          Blank()
        }
        .width('100%')
        .padding({ top: 8, bottom: 8 })
      }

      // 筛选栏
      Row({ space: 12 }) {
        Button('全部')
          .fontSize(14)
          .height(36)
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
            } else {
              this.applyEBookFilter();
            }
          })

        Button('未读')
          .fontSize(14)
          .height(36)
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
            } else {
              this.applyEBookFilter();
            }
          })

        Button('阅读中')
          .fontSize(14)
          .height(36)
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
            } else {
              this.applyEBookFilter();
            }
          })

        Blank()

        // 视图切换按钮
        Button() {
          Image(this.libraryViewMode === LibraryViewMode.LIST 
            ? $r('app.media.ic_view_list_selected')
            : $r('app.media.ic_view_grid_selected'))
            .width(24)
            .height(24)
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
          Image($r('app.media.ic_filter'))
            .width(20)
            .height(20)
            .fillColor(ThemeAwareHelper.getTestManagementThemedColor('text_primary', this.themeState.currentTheme))
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
            .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_primary', this.themeState.currentTheme))
          
          Text(this.mangaList.length === 0 ? '导入一些漫画开始阅读吧' : '尝试更换筛选条件')
            .fontSize(14)
            .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_secondary', this.themeState.currentTheme))
          
          if (this.mangaList.length === 0) {
            Button('导入漫画')
              .fontSize(14)
              .height(36)
              .backgroundColor(ThemeAwareHelper.getTestManagementThemedColor('accent_primary', this.themeState.currentTheme))
              .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_white', this.themeState.currentTheme))
              .onClick(() => {
                this.currentTabIndex = TabIndex.SETTINGS;
                this.tabsController.changeIndex(TabIndex.SETTINGS);
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
          .scrollBar(BarState.Auto)
          .edgeEffect(EdgeEffect.Spring)
        } else {
          // 网格视图（响应式）
          List() {
            ListItem() {
              Grid() {
                ForEach(this.filteredMangaList, (manga: Manga, index: number) => {
                  GridItem() {
                    this.buildMangaGridCard(manga)
                  }
                })
              }
              .columnsTemplate(this.getGridColumnsTemplate())
              .rowsGap(this.responsive_gridGap)
              .columnsGap(this.responsive_gridGap)
              .width('100%')
            }
          }
          .width('100%')
          .layoutWeight(1)
          .scrollBar(BarState.Auto)
          .edgeEffect(EdgeEffect.Spring)
        }
        }
      } else {
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
              .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_secondary', this.themeState.currentTheme))
          }
          .width('100%')
          .height('100%')
          .justifyContent(FlexAlign.Center)
          .alignItems(HorizontalAlign.Center)
        } else if (this.filteredEbookList.length === 0) {
          // 空状态
          Column({ space: 16 }) {
            Image($r('app.media.ic_library_empty'))
              .width(80)
              .height(80)
              .fillColor(ThemeAwareHelper.getTestManagementThemedColor('text_muted', this.themeState.currentTheme))
            
            Text(this.ebookList.length === 0 ? '电子书库为空' : '没有符合条件的电子书')
              .fontSize(16)
              .fontWeight(FontWeight.Medium)
              .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_primary', this.themeState.currentTheme))
            
            Text(this.ebookList.length === 0 ? '导入一些电子书开始阅读吧' : '尝试更换筛选条件')
              .fontSize(14)
              .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_secondary', this.themeState.currentTheme))
            
            if (this.ebookList.length === 0) {
              Button('导入电子书')
                .fontSize(14)
                .height(36)
                .backgroundColor(ThemeAwareHelper.getTestManagementThemedColor('accent_primary', this.themeState.currentTheme))
                .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_white', this.themeState.currentTheme))
                .onClick(() => {
                  this.currentTabIndex = TabIndex.SETTINGS;
                  this.tabsController.changeIndex(TabIndex.SETTINGS);
                })
            }
          }
          .width('100%')
          .height('100%')
          .justifyContent(FlexAlign.Center)
          .alignItems(HorizontalAlign.Center)
        } else {
          // 电子书列表
          if (this.libraryViewMode === LibraryViewMode.LIST) {
            // 列表视图
            List({ space: 16 }) {
              ForEach(this.filteredEbookList, (ebook: EBook, index: number) => {
                ListItem() {
                  this.buildEBookCard(ebook)
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
              ForEach(this.filteredEbookList, (ebook: EBook, index: number) => {
                GridItem() {
                  this.buildEBookGridCard(ebook)
                }
              })
            }
            .columnsTemplate(this.getGridColumnsTemplate())
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
          .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_white', this.themeState.currentTheme))
        Text('松手删除')
          .fontSize(12)
          .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_white', this.themeState.currentTheme))
      }
      .width(96)
      .height('100%')
      .justifyContent(FlexAlign.Center)
      .alignItems(HorizontalAlign.Center)
      .backgroundColor(ThemeAwareHelper.getTestManagementThemedColor('button_danger', this.themeState.currentTheme))
      .borderRadius(ThemeManager.getInstance().getGlassRadius())
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

        Column({ space: 8 }) {
          // 漫画标题
          Text(manga.title)
            .fontSize(16)
            .fontWeight(FontWeight.Medium)
            .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_primary', this.themeState.currentTheme))
            .maxLines(2)
            .textOverflow({ overflow: TextOverflow.Ellipsis })

          // 漫画章节数和状态
          Text(`${manga.chapters.length}话 · ${StatusConverter.mangaStatusToDisplayText(manga.status)}`)
            .fontSize(14)
            .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_secondary', this.themeState.currentTheme))
          
          // 空白
          Blank(2)

          // 漫画描述
          Text(manga.description)
            .fontSize(12)
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
      .backgroundColor(ThemeManager.getInstance().getGlassBackgroundResource())
      .backgroundBlurStyle(ThemeManager.getInstance().getGlassBlurStyle())
      .borderRadius(ThemeManager.getInstance().getGlassRadius())
      .shadow({ radius: ThemeManager.getInstance().getGlassRadius(), color: ThemeManager.getInstance().getGlassShadowColor(), offsetY: 2 })
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
   * 构建漫画网格卡片
   */
  @Builder
  buildMangaGridCard(manga: Manga) {
    Stack() {
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
          .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_primary', this.themeState.currentTheme))
          .maxLines(2)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
          .width('100%')
          .textAlign(TextAlign.Center)
      }
      .width('100%')
      .padding(8)
      .backgroundColor(ThemeManager.getInstance().getGlassBackgroundResource())
      .backgroundBlurStyle(ThemeManager.getInstance().getGlassBlurStyle())
      .borderRadius(ThemeManager.getInstance().getGlassRadius())
      .border({
        width: this.isMultiSelectMode && this.selectedMangaIds.has(manga.id) ? 2 : 0,
        color: ThemeAwareHelper.getTestManagementThemedColor('accent_blue', this.themeState.currentTheme)
      })
    }
    .onClick(() => {
      if (this.isMultiSelectMode) {
        // 多选模式：切换选中状态
        this.toggleMangaSelection(manga.id);
      } else {
        // 普通模式：打开详情页
        this.openMangaDetail(manga);
      }
    })
    .gesture(
      LongPressGesture({ repeat: false })
        .onAction(() => {
          if (!this.isMultiSelectMode) {
            // 长按进入多选模式并选中当前项
            this.enterMultiSelectMode();
            this.toggleMangaSelection(manga.id);
          }
        })
    )
  }

  /**
   * 构建电子书List卡片
   */
  @Builder
  buildEBookCard(ebook: EBook) {
    Row({ space: 12 }) {
      // 封面图片
      Column() {
        Image(ebook.metadata.coverImagePath && ebook.metadata.coverImagePath.length > 0 
          ? (ebook.metadata.coverImagePath.startsWith('/') ? `file://${ebook.metadata.coverImagePath}` : ebook.metadata.coverImagePath)
          : $r('app.media.ic_ebook'))
          .width(ebook.metadata.coverImagePath && ebook.metadata.coverImagePath.length > 0 ? '100%' : 50)
          .height(ebook.metadata.coverImagePath && ebook.metadata.coverImagePath.length > 0 ? '100%' : 50)
          .objectFit(ImageFit.Cover)
          .fillColor(ebook.metadata.coverImagePath && ebook.metadata.coverImagePath.length > 0 ? undefined : ThemeAwareHelper.getTestManagementThemedColor('accent_primary', this.themeState.currentTheme))
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
        Text(ebook.metadata.title)
          .fontSize(16)
          .fontWeight(FontWeight.Medium)
          .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_primary', this.themeState.currentTheme))
          .maxLines(2)
          .textOverflow({ overflow: TextOverflow.Ellipsis })

        Text(`${ebook.metadata.author} · ${ebook.format}`)
          .fontSize(14)
          .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_secondary', this.themeState.currentTheme))

        Text(ebook.metadata.description || '暂无简介')
          .fontSize(12)
          .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_muted', this.themeState.currentTheme))
          .maxLines(2)
          .textOverflow({ overflow: TextOverflow.Ellipsis })

        Blank()

        // 操作按钮
        Row({ space: 12 }) {
          if (ebook.readingProgress && ebook.readingProgress.progress > 0) {
            Text(`已读 ${Math.floor(ebook.readingProgress.progress)}%`)
              .fontSize(12)
              .fontColor(ThemeAwareHelper.getTestManagementThemedColor('accent_primary', this.themeState.currentTheme))
          }
          
          Blank()

          // 根据阅读进度显示不同的按钮文本
          Button(this.hasEBookReadingProgress(ebook) ? '继续阅读' : '开始阅读')
            .fontSize(14)
            .height(32)
            .padding({ left: 16, right: 16 })
            .backgroundColor(ThemeAwareHelper.getTestManagementThemedColor('accent_primary', this.themeState.currentTheme))
            .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_white', this.themeState.currentTheme))
            .onClick(() => {
              this.openEBookReader(ebook);
            })

          Button('删除')
            .fontSize(12)
            .height(32)
            .padding({ left: 12, right: 12 })
            .backgroundColor(ThemeAwareHelper.getTestManagementThemedColor('button_danger', this.themeState.currentTheme))
            .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_white', this.themeState.currentTheme))
            .onClick(() => {
              this.deleteEBookItem(ebook);
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
    .backgroundColor(ThemeManager.getInstance().getGlassBackgroundResource())
    .backgroundBlurStyle(ThemeManager.getInstance().getGlassBlurStyle())
    .borderRadius(ThemeManager.getInstance().getGlassRadius())
    .shadow({
      radius: ThemeManager.getInstance().getGlassRadius(),
      color: ThemeManager.getInstance().getGlassShadowColor(),
      offsetY: 2
    })
    .onClick(() => {
      // 点击卡片打开详情页
      this.openEBookDetail(ebook);
    })
  }

  /**
   * 打开电子书阅读器
   */
  private openEBookReader(ebook: EBook): void {
    logger.info(TAG, `打开电子书阅读器: ${ebook.metadata.title}`);
    // 定义明确的参数对象
    const readerParams: EBookReaderParams = {
      bookId: ebook.id
    };
    this.pathStack.pushPath({ name: 'EBookReaderPage', param: readerParams });
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

            const newFilteredList: Manga[] = [];
            for (let j: number = 0; j < this.filteredMangaList.length; j++) {
              const fm: Manga = this.filteredMangaList[j];
              if (fm.id !== mangaId) { newFilteredList.push(fm); }
            }
            this.filteredMangaList = newFilteredList;

            eventBus.publish(GameEvent.MANGA_DELETED, new MangaDeletedPayload(mangaId));

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
            Image(ebook.metadata.coverImagePath && ebook.metadata.coverImagePath.length > 0 
              ? (ebook.metadata.coverImagePath.startsWith('/') ? `file://${ebook.metadata.coverImagePath}` : ebook.metadata.coverImagePath)
              : $r('app.media.ic_ebook'))
              .width(ebook.metadata.coverImagePath && ebook.metadata.coverImagePath.length > 0 ? '100%' : 60)
              .height(ebook.metadata.coverImagePath && ebook.metadata.coverImagePath.length > 0 ? '100%' : 60)
              .objectFit(ImageFit.Cover)
              .fillColor(ebook.metadata.coverImagePath && ebook.metadata.coverImagePath.length > 0 ? undefined : ThemeAwareHelper.getTestManagementThemedColor('accent_primary', this.themeState.currentTheme))
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
            .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_primary', this.themeState.currentTheme))
            .maxLines(2)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
            .width('100%')
            .textAlign(TextAlign.Center)

          Text(ebook.metadata.author)
            .fontSize(12)
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
                .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_muted', this.themeState.currentTheme))
            }
          }
        }
        .width('100%')
        .padding({ left: 8, right: 8 })
      }
      .width('100%')
      .padding(8)
      .backgroundColor(ThemeManager.getInstance().getGlassBackgroundResource())
      .backgroundBlurStyle(ThemeManager.getInstance().getGlassBlurStyle())
      .borderRadius(ThemeManager.getInstance().getGlassRadius())
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
    .gesture(
      LongPressGesture({ repeat: false })
        .onAction(() => {
          if (!this.isEBookMultiSelectMode) {
            // 长按进入多选模式并选中当前项
            this.enterEBookMultiSelectMode();
            this.toggleEBookSelection(ebook.id);
          }
        })
    )
  }

  /**
   * 构建图源仓库弹窗
   */
  @Builder
  buildSourceRepoDialog() {
    Column({ space: 20 }) {
      Text('图源仓库')
        .fontSize(20)
        .fontWeight(FontWeight.Medium)
        .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_primary', this.themeState.currentTheme))
      
      Text('输入图源仓库地址以同步在线图源配置')
        .fontSize(14)
        .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_secondary', this.themeState.currentTheme))
        .textAlign(TextAlign.Center)
      
      // 已保存仓库选择器
      if (this.savedRepositories.length > 0) {
        Column({ space: 8 }) {
          Row({ space: 8 }) {
            Text('已保存的仓库')
              .fontSize(14)
              .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_secondary', this.themeState.currentTheme))
            
            Button(this.showRepositorySelector ? '收起' : '展开')
              .fontSize(12)
              .height(24)
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
                        .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_primary', this.themeState.currentTheme))
                        .maxLines(1)
                        .textOverflow({ overflow: TextOverflow.Ellipsis })
                      
                      Text(`${repo.sourceCount} 个图源 · ${new Date(repo.lastSync).toLocaleDateString()}`)
                        .fontSize(12)
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
                    LongPressGesture({ repeat: false })
                      .onAction(() => {
                        this.showDeleteRepoPopup = true;
                        this.repositoryToDelete = repo;
                      })
                  )
                  .bindPopup(this.showDeleteRepoPopup, {
                    builder: this.buildDeleteRepoPopup(),
                    placement: Placement.Bottom,
                    width: '220vp',
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
      
      // 自定义URL输入
      TextInput({ placeholder: '请输入仓库地址 (如: https://example.com/sources.json)', text: this.sourceRepoUrl })
        .width('100%')
        .onChange((value: string) => {
          this.sourceRepoUrl = value;
          this.selectedRepositoryId = ''; // 清除选中的仓库
        })
        .backgroundColor(ThemeAwareHelper.getTestManagementThemedColor('button_background', this.themeState.currentTheme))
        .borderRadius(8)
      
      Row({ space: 12 }) {
        Button('取消')
          .layoutWeight(1)
          .backgroundColor(ThemeAwareHelper.getTestManagementThemedColor('button_background', this.themeState.currentTheme))
          .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_primary', this.themeState.currentTheme))
          .onClick(() => {
            this.sourceRepoDialogController?.close();
            this.showSourceRepoDialog = false;
          })
        
        Button(this.isSyncingRepo ? '同步中...' : '确认同步')
          .layoutWeight(1)
          .backgroundColor(ThemeAwareHelper.getTestManagementThemedColor('accent_blue', this.themeState.currentTheme))
          .fontColor(Color.White)
          .enabled(!this.isSyncingRepo)
          .onClick(async () => {
            await this.syncSourceRepository();
          })
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
        .margin({ bottom: 8 })
      Button(this.repositoryToDelete ? `删除 "${this.repositoryToDelete.name}"` : '确认删除')
        .width('100%')
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
   * 构建书库筛选Popup
   */
  @Builder
  buildLibraryFilterPopup() {
    Column() {
      Text('筛选漫画')
        .fontSize(16)
        .fontWeight(FontWeight.Medium)
        .margin({ bottom: 12 })
      
      Button('全部')
        .width('100%')
        .margin({ bottom: 8 })
        .onClick(() => {
          this.libraryFilterType = LibraryFilterType.ALL;
          this.applyLibraryFilter();
          this.showLibraryFilterPopup = false;
        })
      
      Button('未读')
        .width('100%')
        .margin({ bottom: 8 })
        .onClick(() => {
          this.libraryFilterType = LibraryFilterType.UNREAD;
          this.applyLibraryFilter();
          this.showLibraryFilterPopup = false;
        })
      
      Button('阅读中')
        .width('100%')
        .margin({ bottom: 8 })
        .onClick(() => {
          this.libraryFilterType = LibraryFilterType.READING;
          this.applyLibraryFilter();
          this.showLibraryFilterPopup = false;
        })
      
      Button('已完结')
        .width('100%')
        .margin({ bottom: 8 })
        .onClick(() => {
          this.libraryFilterType = LibraryFilterType.COMPLETED;
          this.applyLibraryFilter();
          this.showLibraryFilterPopup = false;
        })
      
      Button('收藏')
        .width('100%')
        .onClick(() => {
          this.libraryFilterType = LibraryFilterType.FAVORITE;
          this.applyLibraryFilter();
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
          Text('筛选漫画')
            .fontSize(18)
            .fontWeight(FontWeight.Bold)
            .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_primary', this.themeState.currentTheme))
            .layoutWeight(1)

          Button('✕')
            .fontSize(20)
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
          this.buildFilterOption('已完结', LibraryFilterType.COMPLETED)
          this.buildFilterOption('收藏', LibraryFilterType.FAVORITE)
        }
        .width('100%')
      }
      .width('89%')
      .padding(20)
      .backgroundColor(ThemeManager.getInstance().getGlassEffectOptions(GlassEffectContext.POPUP).backgroundColorResource)
      .backgroundBlurStyle(ThemeManager.getInstance().getGlassEffectOptions(GlassEffectContext.POPUP).blurStyle)
      .borderRadius(ThemeManager.getInstance().getGlassEffectOptions(GlassEffectContext.POPUP).radius)
      .shadow({ radius: ThemeManager.getInstance().getGlassEffectOptions(GlassEffectContext.POPUP).radius, color: ThemeManager.getInstance().getGlassEffectOptions(GlassEffectContext.POPUP).shadowColor, offsetX: 0, offsetY: 4 })
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
        .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_primary', this.themeState.currentTheme))
        .layoutWeight(1)

      if (this.libraryFilterType === filterType) {
        Image($r('app.media.ic_check'))
          .width(20)
          .height(20)
          .fillColor(ThemeAwareHelper.getTestManagementThemedColor('accent_blue', this.themeState.currentTheme))
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
      this.applyLibraryFilter();
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
   * 构建发现内容
   */
  @Builder
  buildDiscoverContent() {
    Column({ space: 0 }) {
      // 搜索栏（横屏时减小高度和padding）
      Row() {
        TextInput({ placeholder: '搜索漫画、作者...' })
          .layoutWeight(1)
          .height(this.responsive_isLandscape ? 36 : 40)
          .backgroundColor(ThemeAwareHelper.getTestManagementThemedColor('background_secondary', this.themeState.currentTheme))
          .placeholderColor(ThemeAwareHelper.getTestManagementThemedColor('text_muted', this.themeState.currentTheme))
          .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_primary', this.themeState.currentTheme))

        Button() {
          Image($r('app.media.ic_search'))
            .width(20)
            .height(20)

        }
        .width(this.responsive_isLandscape ? 36 : 40)
        .height(this.responsive_isLandscape ? 36 : 40)
        .backgroundColor(Color.Transparent)
        .margin({ left: 8 })
      }
      .width('100%')
      .padding({ 
        left: 16, 
        right: 16, 
        top: this.responsive_isLandscape ? 8 : 16 
      })

      // 标签栏标题
      Row() {
        Text('标签')
          .fontSize(14)
          .fontWeight(FontWeight.Medium)
          .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_primary', this.themeState.currentTheme))
        
        if (this.selectedTag !== '') {
          Text('清除')
            .fontSize(12)
            .fontColor(ThemeAwareHelper.getTestManagementThemedColor('accent_primary', this.themeState.currentTheme))
            .onClick(() => {
              this.selectedTag = '';
              this.applyDiscoverFilter();
            })
        }
      }
      .width('100%')
      .justifyContent(FlexAlign.SpaceBetween)
      .padding({ left: 16, right: 16, top: 12, bottom: 8 })

      // 标签滚动列表（横屏时减小高度）
      Scroll(new Scroller()) {
        Row({ space: 8 }) {
          ForEach(this.allTags, (tag: string) => {
            Text(tag)
              .fontSize(this.responsive_isLandscape ? 12 : 13)
              .padding({ 
                left: this.responsive_isLandscape ? 10 : 12, 
                right: this.responsive_isLandscape ? 10 : 12, 
                top: this.responsive_isLandscape ? 4 : 6, 
                bottom: this.responsive_isLandscape ? 4 : 6 
              })
              .backgroundColor(this.selectedTag === tag ? 
                ThemeAwareHelper.getTestManagementThemedColor('accent_primary', this.themeState.currentTheme) :
                ThemeAwareHelper.getTestManagementThemedColor('background_secondary', this.themeState.currentTheme))
              .fontColor(this.selectedTag === tag ?
                ThemeAwareHelper.getTestManagementThemedColor('text_white', this.themeState.currentTheme) :
                ThemeAwareHelper.getTestManagementThemedColor('text_primary', this.themeState.currentTheme))
              .borderRadius(12)
              .onClick(() => {
                this.selectedTag = tag;
                this.applyDiscoverFilter();
              })
          }, (tag: string) => tag)
        }
        .padding({ left: 16, right: 16 })
      }
      .scrollable(ScrollDirection.Horizontal)
      .scrollBar(BarState.Off)
      .height(this.responsive_isLandscape ? 32 : 40)

      // 作者栏标题
      Row() {
        Text('作者')
          .fontSize(14)
          .fontWeight(FontWeight.Medium)
          .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_primary', this.themeState.currentTheme))
        
        if (this.selectedAuthor !== '') {
          Text('清除')
            .fontSize(12)
            .fontColor(ThemeAwareHelper.getTestManagementThemedColor('accent_primary', this.themeState.currentTheme))
            .onClick(() => {
              this.selectedAuthor = '';
              this.applyDiscoverFilter();
            })
        }
      }
      .width('100%')
      .justifyContent(FlexAlign.SpaceBetween)
      .padding({ left: 16, right: 16, top: 12, bottom: 8 })

      // 作者滚动列表
      Scroll(new Scroller()) {
        Row({ space: 8 }) {
          ForEach(this.allAuthors, (author: string) => {
            Text(author)
              .fontSize(13)
              .padding({ left: 12, right: 12, top: 6, bottom: 6 })
              .backgroundColor(this.selectedAuthor === author ? 
                ThemeAwareHelper.getTestManagementThemedColor('accent_primary', this.themeState.currentTheme) :
                ThemeAwareHelper.getTestManagementThemedColor('background_secondary', this.themeState.currentTheme))
              .fontColor(this.selectedAuthor === author ?
                ThemeAwareHelper.getTestManagementThemedColor('text_white', this.themeState.currentTheme) :
                ThemeAwareHelper.getTestManagementThemedColor('text_primary', this.themeState.currentTheme))
              .borderRadius(12)
              .onClick(() => {
                this.selectedAuthor = author;
                this.applyDiscoverFilter();
              })
          }, (author: string) => author)
        }
        .padding({ left: 16, right: 16 })
      }
      .scrollable(ScrollDirection.Horizontal)
      .scrollBar(BarState.Off)
      .height(40)

      // 内容类型切换
      Row({ space: 8 }) {
        Text('全部')
          .fontSize(13)
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
        
        Text('漫画')
          .fontSize(13)
          .padding({ left: 16, right: 16, top: 6, bottom: 6 })
          .backgroundColor(this.discoverContentType === 'manga' ? 
            ThemeAwareHelper.getTestManagementThemedColor('accent_primary', this.themeState.currentTheme) :
            ThemeAwareHelper.getTestManagementThemedColor('background_secondary', this.themeState.currentTheme))
          .fontColor(this.discoverContentType === 'manga' ?
            ThemeAwareHelper.getTestManagementThemedColor('text_white', this.themeState.currentTheme) :
            ThemeAwareHelper.getTestManagementThemedColor('text_primary', this.themeState.currentTheme))
          .borderRadius(16)
          .onClick(() => {
            this.discoverContentType = 'manga';
            this.applyDiscoverFilter();
          })
        
        Text('电子书')
          .fontSize(13)
          .padding({ left: 16, right: 16, top: 6, bottom: 6 })
          .backgroundColor(this.discoverContentType === 'ebook' ? 
            ThemeAwareHelper.getTestManagementThemedColor('accent_primary', this.themeState.currentTheme) :
            ThemeAwareHelper.getTestManagementThemedColor('background_secondary', this.themeState.currentTheme))
          .fontColor(this.discoverContentType === 'ebook' ?
            ThemeAwareHelper.getTestManagementThemedColor('text_white', this.themeState.currentTheme) :
            ThemeAwareHelper.getTestManagementThemedColor('text_primary', this.themeState.currentTheme))
          .borderRadius(16)
          .onClick(() => {
            this.discoverContentType = 'ebook';
            this.applyDiscoverFilter();
          })
      }
      .width('100%')
      .padding({ left: 16, right: 16, top: 12, bottom: 8 })

      // 筛选结果提示
      if (this.selectedTag !== '' || this.selectedAuthor !== '' || this.discoverContentType !== 'all') {
        Row() {
          Text(`找到 ${this.discoveredMangaList.length} 本漫画, ${this.discoveredEBookList.length} 本电子书`)
            .fontSize(13)
            .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_secondary', this.themeState.currentTheme))
        }
        .width('100%')
        .padding({ left: 16, right: 16, top: 4 })
      }

      // 内容列表（响应式）
      if (this.discoveredMangaList.length > 0 || this.discoveredEBookList.length > 0) {
        List() {
          // 漫画部分
          if (this.discoveredMangaList.length > 0) {
            ListItem() {
              Column() {
                if (this.discoverContentType === 'all' && this.discoveredEBookList.length > 0) {
                  Text(`漫画 (${this.discoveredMangaList.length})`)
                    .fontSize(14)
                    .fontWeight(FontWeight.Medium)
                    .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_primary', this.themeState.currentTheme))
                    .width('100%')
                    .margin({ bottom: 8 })
                }
                Grid() {
                  ForEach(this.discoveredMangaList, (manga: Manga) => {
                    GridItem() {
                      this.buildMangaGridCard(manga)
                    }
                  }, (manga: Manga) => manga.id)
                }
                .columnsTemplate(this.getGridColumnsTemplate())
                .rowsGap(this.responsive_gridGap)
                .columnsGap(this.responsive_gridGap)
                .width('100%')
              }
            }
          }
          
          // 电子书部分
          if (this.discoveredEBookList.length > 0) {
            ListItem() {
              Column() {
                if (this.discoverContentType === 'all' && this.discoveredMangaList.length > 0) {
                  Text(`电子书 (${this.discoveredEBookList.length})`)
                    .fontSize(14)
                    .fontWeight(FontWeight.Medium)
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
                .columnsTemplate(this.getGridColumnsTemplate())
                .rowsGap(this.responsive_gridGap)
                .columnsGap(this.responsive_gridGap)
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
          Text(this.mangaList.length === 0 && this.ebookList.length === 0 ? '暂无数据' : '没有符合条件的内容')
            .fontSize(14)
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
        
      }
      .width('100%')
      .padding(16)
      .backgroundColor(Color.Transparent)

      // 功能按钮行
      Row({ space: 12 }) {
        Button('导入图源')
          .fontSize(14)
          .backgroundColor(ThemeAwareHelper.getTestManagementThemedColor('button_primary', this.themeState.currentTheme))
          .layoutWeight(1)
          .onClick(async () => {
            await this.importSource();
          })
        
        // 图源仓库按钮（带升级图标）
        Row({ space: 6 }) {
          Button('图源仓库')
            .fontSize(14)
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
        }
        .layoutWeight(1)
        .justifyContent(FlexAlign.Center)
      }
      .width('100%')
      .padding({ left: 16, right: 16, bottom: 12 })

      // 图源列表区域（支持下拉刷新）
      Refresh({ refreshing: this.isRefreshingSourceList }) {
        Column({ space: 12 }) {

        // 图源列表
        Column({ space: 8 }) {
          Text(`已安装图源 (${this.sourceList.length})`)
            .fontSize(16)
            .fontWeight(FontWeight.Medium)
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
                .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_secondary', this.themeState.currentTheme))
            }
            .width('100%')
            .padding(40)
            .justifyContent(FlexAlign.Center)
          } else if (this.filteredSourceList.length === 0) {
            // 空状态提示
            Column({ space: 12 }) {
              Image($r('app.media.ic_source_normal'))
                .width(64)
                .height(64)
                .opacity(0.3)
              
              Text(this.sourceSearchKeyword ? '未找到匹配的图源' : '暂无图源')
                .fontSize(16)
                .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_muted', this.themeState.currentTheme))
              
              if (!this.sourceSearchKeyword) {
                Column({ space: 8 }) {
                  Text('本应用不包含任何内置图源')
                    .fontSize(14)
                    .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_muted', this.themeState.currentTheme))
                  
                  Text('请点击"导入图源"按钮选择JSON格式的图源文件')
                    .fontSize(13)
                    .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_muted', this.themeState.currentTheme))
                    .opacity(0.8)
                }
              }
            }
            .width('100%')
            .padding(40)
            .justifyContent(FlexAlign.Center)
          } else {
            // 图源卡片列表
            Column({ space: 12 }) {
              ForEach(this.filteredSourceList, (source: SourceInfo) => {
                this.buildSourceCard(source)
              })
            }
            .width('100%')
            .padding({ left: 16, right: 16 })
          }
        }
        .width('100%')

        // 使用说明
        Column({ space: 8 }) {
          Text('使用说明')
            .fontSize(16)
            .fontWeight(FontWeight.Medium)
            .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_primary', this.themeState.currentTheme))
          
          Text('• 本应用不包含任何内置图源，需用户自行导入')
            .fontSize(14)
            .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_secondary', this.themeState.currentTheme))
          
          Text('• 图源是JSON格式的配置文件，定义了漫画数据的获取方式')
            .fontSize(14)
            .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_secondary', this.themeState.currentTheme))
          
          Text('• 点击"导入图源"按钮，选择.json文件进行导入')
            .fontSize(14)
            .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_secondary', this.themeState.currentTheme))
          
          Text('• 点击图源卡片可查看详情，长按可删除图源')
            .fontSize(14)
            .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_secondary', this.themeState.currentTheme))
          
          Text('• 导入后可以启用/禁用图源，测试图源可用性')
            .fontSize(14)
            .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_secondary', this.themeState.currentTheme))
          
          Text('• 用户需自行承担使用第三方图源的风险和责任')
            .fontSize(13)
            .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_muted', this.themeState.currentTheme))
            .opacity(0.8)
        }
        .width('100%')
        .padding(16)
        .backgroundColor(Color.Transparent)
        .borderRadius(12)
        .margin({ left: 16, right: 16 })
        }
        .width('100%')
      }
      .onRefreshing(async () => {
        await this.handleSourceRefresh();
      })
      .layoutWeight(1)
    }
    .width('100%')
    .height('100%')
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
            .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_primary', this.themeState.currentTheme))
            .maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis })

          if (!source.isEnabled) {
            Text('已禁用')
              .fontSize(12)
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
            .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_secondary', this.themeState.currentTheme))
            .maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
        }

        Text(`${source.language} • v${source.version}`)
          .fontSize(12)
          .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_muted', this.themeState.currentTheme))
      }
      .layoutWeight(1)
      .alignItems(HorizontalAlign.Start)

      // 箭头图标
      Image($r('app.media.ic_arrow_right'))
        .width(20)
        .height(20)
        .fillColor(ThemeAwareHelper.getTestManagementThemedColor('text_muted', this.themeState.currentTheme))
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
              .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_primary', this.themeState.currentTheme))

            Text('查看您的阅读统计和分析')
              .fontSize(14)
              .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_secondary', this.themeState.currentTheme))
          }
          .alignItems(HorizontalAlign.Start)
          .layoutWeight(1)
          .margin({ left: 16 })

          Image($r('app.media.ic_arrow_right'))
            .width(20)
            .height(20)
            .fillColor(ThemeAwareHelper.getTestManagementThemedColor('text_muted', this.themeState.currentTheme))
        }
        .width('100%')
        .padding(16)
        .backgroundColor(ThemeManager.getInstance().getGlassBackgroundResource())
        .backgroundBlurStyle(ThemeManager.getInstance().getGlassBlurStyle())
        .borderRadius(ThemeManager.getInstance().getGlassRadius())
        .shadow({ radius: ThemeManager.getInstance().getGlassRadius(), color: ThemeManager.getInstance().getGlassShadowColor(), offsetX: 0, offsetY: 4 })
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
        this.buildSettingItem('主题设置', '自定义背景、强调色', $r('app.media.ic_theme'), () => {
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
        this.buildSettingItem('全局设置', '默认阅读模式、下载选项', $r('app.media.ic_reading_settings'), () => {
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
        this.buildSettingItem('下载管理', '离线下载、存储管理', $r('app.media.ic_download'), () => {
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
        this.buildSettingItem('日志管理', '查看和导出应用日志', $r('app.media.ic_log'), () => {
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
        this.buildSettingItem('刮削测试', '测试元数据刮削功能', $r('app.media.ic_search'), () => {
          try {
            const navigationPath: NavigationPath = {
              name: 'ScraperTestPage',
              param: {
                fromPage: 'MainMenuPage',
                timestamp: Date.now()
              }
            };
            this.pathStack.pushPath(navigationPath);
            logger.info(TAG, '导航到刮削测试页面');
          } catch (error) {
            logger.error(TAG, '导航到刮削测试页面失败', String(error));
            this.showToast('打开刮削测试页面失败');
          }
        })
        this.buildSettingItem('关于应用', `版本 ${this.appVersion}`, $r('app.media.ic_info'), () => {
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
        this.buildSettingItem('数据管理', '导入/导出配置及Mihon本地漫画', $r('app.media.ic_data_management'), () => {
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
        }
        .backgroundColor(ThemeManager.getInstance().getGlassBackgroundResource())
        .backgroundBlurStyle(ThemeManager.getInstance().getGlassBlurStyle())
        .borderRadius(ThemeManager.getInstance().getGlassRadius())
        .shadow({ radius: ThemeManager.getInstance().getGlassRadius(), color: ThemeManager.getInstance().getGlassShadowColor(), offsetX: 0, offsetY: 4 })
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
      Image(icon)
        .width(24)
        .height(24)
        .fillColor(ThemeAwareHelper.getTestManagementThemedColor('text_primary', this.themeState.currentTheme))

      Column({ space: 2 }) {
        Text(title)
          .fontSize(16)
          .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_primary', this.themeState.currentTheme))
          .textAlign(TextAlign.Start)
          .width('100%')

        Text(subtitle)
          .fontSize(14)
          .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_secondary', this.themeState.currentTheme))
          .textAlign(TextAlign.Start)
          .width('100%')
      }
      .alignItems(HorizontalAlign.Start)
      .layoutWeight(1)
      .margin({ left: 16 })

      Image($r('app.media.ic_arrow_right'))
        .width(20)
        .height(20)
        .fillColor(ThemeAwareHelper.getTestManagementThemedColor('text_muted', this.themeState.currentTheme))
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
    } else if (name === 'SourceGuidePage') {
      SourceGuidePage()
    } else if (name === 'OpenSourceLicensePage') {
      OpenSourceLicensePage()
    } else if (name === 'UserAgreementPage') {
      UserAgreementPage()
    } else if (name === 'PrivacyPolicyPage') {
      PrivacyPolicyPage()
    } else if (name === 'SourceDetailPage') {
      SourceDetailPage()
    } else if (name === 'SourceSettingsPage') {
      SourceSettingsPage()
    } else if (name === 'SourceLoginPage') {
      SourceLoginPage()
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
    // 测试页面导航已移除
    // } else if (name === 'ReaderKitTestPage') {
    //   ReaderKitTestPage()
    // } else if (name === 'PdfKitTestPage') {
    //   PdfKitTestPage()
    } else if (name === 'ScraperTestPage') {
      ScraperTestPage()
    }
  }

  /**
   * 获取可见的标签配置（根据高级模式过滤）
   */
  private getVisibleTabConfigs(): TabConfig[] {
    return this.tabConfigs.filter((cfg: TabConfig) => {
      // 图源标签仅在高级模式下显示
      if (cfg.index === TabIndex.SOURCE) {
        return this.advancedModeEnabled;
      }
      return true;
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
    .backgroundColor(ThemeManager.getInstance().getGlassBackgroundResource())
    .backgroundBlurStyle(ThemeManager.getInstance().getGlassBlurStyle())
    .borderRadius(ThemeManager.getInstance().getGlassRadius())
    .shadow({ radius: ThemeManager.getInstance().getGlassRadius(), color: ThemeManager.getInstance().getGlassShadowColor(), offsetX: 0, offsetY: 4 })
  }

  /**
   * 触发轻微震动反馈
   */
  private triggerHapticFeedback(): void {
    try {
      vibrator.startVibration({
        type: 'time',
        duration: 50
      }, {
        id: 0,
        usage: 'touch'
      }).then(() => {
        logger.debug(TAG, '震动反馈执行成功');
      }).catch((error: BusinessError) => {
        logger.warn(TAG, `震动反馈失败: ${error.message}`);
      });
    } catch (error) {
      logger.warn(TAG, `震动反馈异常: ${error}`);
    }
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
        Image(this.currentTabIndex === config.index ? config.selectedIcon : config.icon)
          .width(24)
          .height(24)
          .fillColor(this.currentTabIndex === config.index
            ? ThemeAwareHelper.getTestManagementThemedColor('accent_primary', this.themeState.currentTheme)
            : ThemeAwareHelper.getTestManagementThemedColor('text_secondary', this.themeState.currentTheme))
        
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

  build() {
    Navigation(this.pathStack) {
      Stack() {
        // 背景层 - 自动显示自定义主题背景或默认背景色
        GlobalBackgroundLayer({
          defaultBackgroundColor: ThemeAwareHelper.getTestManagementThemedColor('background_primary', this.themeState.currentTheme)
        })

        // 主内容区域（透明背景以显示自定义主题）
        Column() {
          // 顶部标题栏：平板横屏显示专用顶栏，其他设备显示默认顶栏
          if (this.deviceManager.isTabletOrLarger()) {
            // 平板横屏专用顶栏
            this.buildTabletTopBar()
          } else {
            // 其他设备默认顶栏
            this.buildTopBar()
          }

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
                Scroll() { this.buildSourceContent() }
                .width('100%').height('100%').scrollBar(BarState.Off).edgeEffect(EdgeEffect.Spring).backgroundColor(Color.Transparent)
              }
              .backgroundColor(Color.Transparent)

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
            })
          }
          .layoutWeight(1)
          .width('100%')
          
        }
        .width('100%')
        .height('100%')
        .backgroundColor(Color.Transparent) // 透明背景以显示全局背景层

        if (this.responsive_tabBarPosition === BarPosition.End) {
          Column() {
            this.buildHorizontalTabBar()
          }
          .width(this.getBottomBarWidth())
          .height(this.BOTTOM_BAR_HEIGHT)
          .backgroundColor(Color.Transparent)
          .position({ x: this.getBottomBarX(), y: this.getBottomBarY() })
        }


        // 筛选对话框
        if (this.showLibraryFilterDialog) {
          this.buildLibraryFilterDialog()
        }

        

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
  }
}

export { MainMenuPage };
