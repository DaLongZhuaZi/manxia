// 文件路径: entry/src/main/ets/pages/ReadingAnalyticsPage.ets
/**
 * 阅读数据分析报告页面
 * 根据用户的阅读记录，分析并展示阅读习惯、统计数据等
 */

import { HdsNavDestination } from '@kit.UIDesignKit';
import { ThemeAwareState, ThemeAwareHelper } from 'manxia_theme/src/main/ets/Framework/Components/ThemeAware';
import { ThemeManager, ThemeType } from 'manxia_theme/src/main/ets/Framework/Managers/ThemeManager';
import { FontAwareHelper, FontAwareState } from 'manxia_theme/src/main/ets/Framework/Components/FontAware';
import { DeviceAdaptationManager, DeviceInfo, DeviceChangeListener, Breakpoint } from 'manxia_theme/src/main/ets/Framework/Managers/DeviceAdaptationManager';
import { ResponsiveLayoutHelper } from 'manxia_theme/src/main/ets/Framework/Utils/ResponsiveLayout';
import { logger } from 'manxia_core/src/main/ets/Utils/Logger';
import { PageLifecycleManager } from 'manxia_core/src/main/ets/Framework/Lifecycle/index';
import { DataService } from '../Framework/Services/DataService';
import { ReadHistory, DataManager, ComicInfo } from '../Framework/Data/DataManager';
import { ReadingAnalyticsManager, RETENTION_DAYS_OPTIONS, ReadingGoalsSettings } from 'manxia_core/src/main/ets/Framework/Managers/ReadingAnalyticsManager';
import { EBookDataManager } from 'manxia_core/src/main/ets/Framework/Data/EBookDataManager';
import { EBook } from 'manxia_core/src/main/ets/Models/EBookModels';
import { getNovelDataManager } from '../Framework/Novel/NovelDataManager';
import { NovelBook } from 'manxia_core/src/main/ets/Models/NovelModels';
import { getCoverImageManager } from '../Framework/Image/CoverImageManager';
import { image } from '@kit.ImageKit';
import { PageSettingsHelper, DetailPageType } from './settings/PageSettingsSubPage';
import { UnifiedDetailPageParams, UnifiedContentType } from 'manxia_core/src/main/ets/Models/UnifiedContentModels';
import { MangaDetailPageParams } from './MangaDetailPage';
import { EBookDetailPageParams } from './EBookDetailPage';
import { NovelDetailPageParams } from './NovelBookshelfPage';
import { widgetDataSync } from '../Utils/WidgetDataSync';
import { getUnifiedAnnotationManager, UnifiedAnnotationManager } from 'manxia_core/src/main/ets/Framework/Annotations/UnifiedAnnotationManager';
import { UnifiedAnnotationRecord, UnifiedAnnotationType } from 'manxia_core/src/main/ets/Models/AnnotationModels';
import { AnnotationCenterPageParams } from './AnnotationCenterPage';
import { SettingsImmersiveTitleBar } from './settings/SettingsImmersiveTitleBar';
import { SettingsImmersiveTitleActionItem, SettingsPageTitleBarManager } from 'manxia_features_ui/src/main/ets/pages/settings/SettingsPageTitleBarManager';
import { SettingsPageSurfaceManager } from 'manxia_features_ui/src/main/ets/pages/settings/SettingsPageSurfaceManager';
import { SharedPageBackgroundLayer } from 'manxia_theme/src/main/ets/Framework/Components/SharedPageBackgroundLayer';
import { GlobalBackgroundLayerMode } from 'manxia_theme/src/main/ets/Framework/Components/GlobalBackgroundLayer';

const TAG = 'ReadingAnalyticsPage';
const USER_MANUAL_TITLE = '漫匣使用手册'; // 需要过滤掉的使用手册标题

// NavDestinationContext接口定义
interface NavDestinationContext {
  pathStack: NavPathStack;
}

/**
 * 阅读统计数据接口
 */
interface ReadingStatistics {
  totalReadingTime: number;      // 总阅读时长（秒）
  totalComicsRead: number;        // 阅读过的漫画总数
  totalChaptersRead: number;      // 阅读过的章节总数
  totalPagesRead: number;         // 阅读的总页数
  averageReadingTime: number;     // 平均每天阅读时长（秒）
  favoriteReadingHour: number;    // 最喜欢的阅读时段（小时）
  mostReadComicId: string;        // 阅读最多的漫画ID
  mostReadComicTitle: string;     // 阅读最多的漫画标题
  mostReadEBookId: string;        // 阅读最多的电子书ID
  mostReadEBookTitle: string;     // 阅读最多的电子书标题
  continuousReadingDays: number;  // 连续阅读天数
  lastReadTime: number;           // 最后阅读时间
  // 电子书统计
  totalEBooksRead: number;        // 阅读过的电子书总数
  totalEBookReadingTime: number;  // 电子书总阅读时长（秒）
  // 小说统计
  totalNovelsRead: number;        // 阅读过的小说总数
  totalNovelReadingTime: number;  // 小说总阅读时长（秒）
}

/**
 * 每日阅读数据
 */
interface DailyReadingData {
  date: string;                   // 日期字符串（YYYY-MM-DD）
  readingTime: number;            // 阅读时长（秒）
  chaptersRead: number;           // 阅读章节数
  pagesRead: number;              // 阅读页数
}

/**
 * 日视图漫画阅读项
 */
interface DailyMangaItem {
  comicId: string;
  title: string;
  coverPath: string;
  readingTime: number;            // 阅读时长（秒）
  chaptersRead: number;
  pagesRead: number;
}

/**
 * 日视图电子书阅读项
 */
interface DailyEBookItem {
  ebookId: string;
  title: string;
  coverPath: string;
  readingTime: number;            // 阅读时长（秒）
  progress: number;               // 阅读进度百分比
}

/**
 * 日视图小说阅读项
 */
interface DailyNovelItem {
  novelId: string;                // 小说ID（格式: sourceId_bookUrl）
  bookUrl: string;                // 小说URL（用于导航到详情页）
  sourceId: string;
  title: string;
  author: string;
  coverPath: string;
  readingTime: number;            // 阅读时长（秒）
  chaptersRead: number;           // 阅读章节数
  isOnline: boolean;              // 是否在线小说
}

/**
 * 阅读目标设置
 */
interface ReadingGoals {
  mangaGoalMinutes: number;       // 漫画阅读目标（分钟），0表示未设置
  ebookGoalMinutes: number;       // 电子书阅读目标（分钟），0表示未设置
  novelGoalMinutes: number;       // 小说阅读目标（分钟），0表示未设置
}

/**
 * 阅读时段分布数据
 */
interface HourlyDistribution {
  hour: number;                   // 小时（0-23）
  readingCount: number;           // 阅读次数
  readingTime: number;            // 阅读时长（秒）
}

/**
 * 小时统计数据（用于Map存储）
 */
interface HourlyStatData {
  count: number;
  time: number;
}

/**
 * 每日统计数据（用于Map存储）
 */
interface DailyStatData {
  time: number;
  chapters: Set<string>;
  pages: number;
}

/**
 * 漫画阅读统计数据（用于Map存储）
 */
interface MangaReadingStatData {
  time: number;
  chapters: Set<string>;
  pages: number;
}

/**
 * 阅读时长排行项类型
 */
type ReadingRankType = 'manga' | 'ebook' | 'novel';

/**
 * 阅读时长排行项
 */
interface ReadingRankItem {
  id: string;
  title: string;
  coverPath: string;
  readingTime: number;      // 阅读时长（分钟）
  type: ReadingRankType;    // 类型
}

/**
 * 兴趣分析项类型
 */
type InterestType = 'tag' | 'author' | 'title';

/**
 * 兴趣分析项
 */
interface InterestItem {
  keyword: string;
  count: number;
  type: InterestType;
}

/**
 * 关键词统计数据
 */
interface KeywordStatData {
  count: number;
  type: InterestType;
}

interface InspirationStatistics {
  totalCount: number;
  bookmarkCount: number;
  highlightCount: number;
  thoughtCount: number;
}

enum StatCardStyle {
  FEATURED,
  STANDARD,
  COMPACT
}

enum ContentMixKind {
  MANGA,
  EBOOK,
  NOVEL
}

interface ContentMixSegment {
  kind: ContentMixKind;
  label: string;
  valueSeconds: number;
  itemCount: number;
  percent: number;
  symbol: Resource;
  accentColor: ResourceColor;
}

interface ReadingInsightItem {
  title: string;
  value: string;
  detail: string;
  symbol: Resource;
  accentColor: ResourceColor;
}

interface ReadingTrendBar {
  date: string;
  label: string;
  readingTime: number;
  chaptersRead: number;
  pagesRead: number;
  percent: number;
}

interface NovelAnalysisData {
  filteredNovels: NovelBook[];
  allNovels: NovelBook[];
}

@Component
struct ReadingAnalyticsPage {
  @State pathStack: NavPathStack = new NavPathStack();
  @StorageProp('statusBarHeight') statusBarHeight: number = 0;
  private scroller: Scroller = new Scroller();

  // 主题相关状态
  @State themeState: ThemeAwareState = new ThemeAwareState();
  @State fontState: FontAwareState = new FontAwareState();
  @StorageLink('appFontFamily') appFontFamily: string = 'HarmonyOS Sans';
  private themeManager: ThemeManager = ThemeManager.getInstance();
  private componentId: string = 'ReadingAnalyticsPage';

  // 响应式布局相关状态
  private deviceManager: DeviceAdaptationManager = DeviceAdaptationManager.getInstance();
  private deviceChangeListener: DeviceChangeListener | null = null;
  @State responsive_contentPadding: number = 16;
  @State responsive_maxContentWidth: number = 1200;
  @State responsive_isLandscape: boolean = false;
  @State responsive_statCardColumns: number = 2; // 统计卡片列数

  // 数据服务
  private dataService: DataService = DataService.getInstance();
  private dataManager: DataManager = DataManager.getInstance();
  private ebookDataManager: EBookDataManager = EBookDataManager.getInstance();
  private analyticsManager: ReadingAnalyticsManager = ReadingAnalyticsManager.getInstance();
  private annotationManager: UnifiedAnnotationManager = getUnifiedAnnotationManager();

  // 统计数据状态
  @State isLoading: boolean = true;
  @State analyticsEnabled: boolean = false;
  @State hasAskedPermission: boolean = false; // 是否已询问过用户权限
  @State statistics: ReadingStatistics = {
    totalReadingTime: 0,
    totalComicsRead: 0,
    totalChaptersRead: 0,
    totalPagesRead: 0,
    averageReadingTime: 0,
    favoriteReadingHour: -1,  // -1 表示没有数据
    mostReadComicId: '',
    mostReadComicTitle: '暂无数据',
    mostReadEBookId: '',
    mostReadEBookTitle: '暂无数据',
    continuousReadingDays: 0,
    lastReadTime: 0,
    totalEBooksRead: 0,
    totalEBookReadingTime: 0,
    totalNovelsRead: 0,
    totalNovelReadingTime: 0
  };

  @State dailyData: DailyReadingData[] = [];
  @State hourlyDistribution: HourlyDistribution[] = [];
  @State inspirationStats: InspirationStatistics = {
    totalCount: 0,
    bookmarkCount: 0,
    highlightCount: 0,
    thoughtCount: 0
  };
  @State dailyInspirationStats: InspirationStatistics = {
    totalCount: 0,
    bookmarkCount: 0,
    highlightCount: 0,
    thoughtCount: 0
  };
  
  // 阅读时长排行
  @State readingRankList: ReadingRankItem[] = [];
  
  // 兴趣分析
  @State interestItems: InterestItem[] = [];

  // 时间范围选择
  @State selectedTimeRange: number = 30; // 默认最近30天
  @State showRetentionPicker: boolean = false; // 是否显示保留天数选择器
  @State retentionDaysIndex: number = 2; // 保留天数索引（默认30天）
  @State showClearDataDialog: boolean = false; // 是否显示清除数据对话框
  
  // 视图切换：长期视图 / 日视图
  @State isLongTermView: boolean = true; // true: 长期视图, false: 日视图
  @State selectedDate: Date = new Date(); // 日视图选中的日期
  @State currentMonth: Date = new Date(); // 日视图当前显示的月份
  @State dailyViewData: DailyReadingData | null = null; // 日视图当天的阅读数据
  @State dailyMangaList: DailyMangaItem[] = []; // 日视图当天阅读的漫画列表
  @State dailyEBookList: DailyEBookItem[] = []; // 日视图当天阅读的电子书列表
  @State dailyNovelList: DailyNovelItem[] = []; // 日视图当天阅读的小说列表
  @State isDailyLoading: boolean = false; // 日视图加载状态
  
  // 阅读目标
  @State readingGoals: ReadingGoals = {
    mangaGoalMinutes: 0,
    ebookGoalMinutes: 0,
    novelGoalMinutes: 0
  };
  @State showGoalSettingDialog: boolean = false; // 显示目标设置对话框
  @State goalDialogVisible: boolean = false; // 目标对话框实际可见性（用于动画）
  @State mangaGoalValue: number = 0; // 漫画目标值
  @State ebookGoalValue: number = 0; // 电子书目标值
  @State novelGoalValue: number = 0; // 小说目标值
  
  // 当日阅读分钟数（用于阅读目标进度显示）
  @State dailyMangaReadingMinutes: number = 0;
  @State dailyEbookReadingMinutes: number = 0;
  @State dailyNovelReadingMinutes: number = 0;
  
  // 缓存原始阅读历史数据（用于日视图查询）
  private cachedReadHistory: ReadHistory[] = [];
  
  // 缓存所有日期的阅读数据（用于日历视图，不受时间范围限制）
  @State allDailyData: DailyReadingData[] = [];
  
  // 标记是否从卡片强制进入日视图
  private forceShowDailyView: boolean = false;

  onPageShow(): void {
    try {
      const stack = AppStorage.get<NavPathStack>('GlobalNavStack');
      if (stack) {
        this.pathStack = stack;
        logger.debug(TAG, '✅ 成功获取GlobalNavStack');
      }
    } catch (err) {
      logger.error(TAG, 'AppStorage.get 异常', String(err));
    }
  }

  onReady(): void {
    ThemeAwareHelper.initializeThemeAware(this.componentId, this.themeState, (newTheme: ThemeType) => {
      logger.info(TAG, `主题切换到: ${newTheme}`);
    });
    FontAwareHelper.initializeFontAware(
      this.componentId,
      this.fontState,
      (newState: FontAwareState) => {
        this.fontState = newState;
      }
    );

    // 初始化响应式布局
    this.initResponsiveLayout();

    // 初始化阅读报告管理器并加载数据
    this.initializeAndLoad().catch((error: Error) => {
      logger.error(TAG, '初始化失败', error.message);
    });
  }

  private lifecycle = new PageLifecycleManager('ReadingAnalyticsPage', { enableDebug: true });

  aboutToDisappear(): void {
    this.lifecycle.destroy();
    ThemeAwareHelper.cleanupThemeAware(this.componentId);
    FontAwareHelper.cleanupFontAware(this.componentId);
    
    // 移除设备变化监听器
    if (this.deviceChangeListener) {
      this.deviceManager.removeListener(this.deviceChangeListener);
      this.deviceChangeListener = null;
    }
  }

  /**
   * 初始化响应式布局
   */
  private initResponsiveLayout(): void {
    try {
      this.updateResponsiveParams();
      this.deviceChangeListener = (deviceInfo: DeviceInfo) => {
        logger.info(TAG, `设备状态变化: 断点=${deviceInfo.breakpoint}, 横屏=${deviceInfo.isLandscape}`);
        this.updateResponsiveParams();
      };
      this.deviceManager.addListener(this.deviceChangeListener);
      logger.info(TAG, '✅ 响应式布局初始化完成');
    } catch (error) {
      logger.error(TAG, '响应式布局初始化失败', String(error));
    }
  }

  /**
   * 更新响应式布局参数
   */
  private updateResponsiveParams(): void {
    const layoutParams = ResponsiveLayoutHelper.getLayoutParams();
    const deviceInfo = this.deviceManager.getDeviceInfo();
    
    this.responsive_contentPadding = layoutParams.contentPadding;
    this.responsive_isLandscape = deviceInfo.isLandscape;
    
    switch (deviceInfo.breakpoint) {
      case Breakpoint.XS:
        this.responsive_maxContentWidth = 600;
        this.responsive_statCardColumns = 2;
        break;
      case Breakpoint.SM:
        this.responsive_maxContentWidth = 840;
        this.responsive_statCardColumns = 2;
        break;
      case Breakpoint.MD:
        this.responsive_maxContentWidth = 1024;
        this.responsive_statCardColumns = 3;
        break;
      case Breakpoint.LG:
        this.responsive_maxContentWidth = 1200;
        this.responsive_statCardColumns = 4;
        break;
    }
  }

  /**
   * 初始化并加载数据
   */
  private async initializeAndLoad(): Promise<void> {
    try {
      await this.analyticsManager.initialize();
      this.analyticsEnabled = this.analyticsManager.isEnabled();
      this.hasAskedPermission = this.analyticsManager.hasAskedPermission();
      this.retentionDaysIndex = this.analyticsManager.getRetentionDaysIndex();
      this.selectedTimeRange = this.analyticsManager.getRetentionDays();
      
      // 加载视图模式（如果是从卡片进入，则强制显示日视图）
      if (this.forceShowDailyView) {
        this.isLongTermView = false;
      } else {
        this.isLongTermView = this.analyticsManager.isLongTermView();
      }
      
      // 加载阅读目标
      const goals = this.analyticsManager.getReadingGoals();
      this.readingGoals = {
        mangaGoalMinutes: goals.mangaGoalMinutes,
        ebookGoalMinutes: goals.ebookGoalMinutes,
        novelGoalMinutes: goals.novelGoalMinutes
      };
      // 同步到独立状态变量
      this.mangaGoalValue = goals.mangaGoalMinutes;
      this.ebookGoalValue = goals.ebookGoalMinutes;
      this.novelGoalValue = goals.novelGoalMinutes;
      
      logger.info(TAG, `初始化完成: analyticsEnabled=${this.analyticsEnabled}, hasAskedPermission=${this.hasAskedPermission}, isLongTermView=${this.isLongTermView}`);
      
      // 如果已询问过权限，才加载数据
      if (this.hasAskedPermission) {
        await this.loadReadingData();
        
        // 如果是日视图模式，需要加载日视图数据
        if (!this.isLongTermView) {
          await this.loadDailyViewData(this.selectedDate);
        }
      } else {
        this.isLoading = false;
        logger.info(TAG, '用户尚未同意阅读报告权限，显示权限请求界面');
      }
    } catch (error) {
      logger.error(TAG, `初始化失败: ${String(error)}`);
      this.isLoading = false;
    }
  }
  
  /**
   * 处理用户同意权限
   */
  private async handleAcceptPermission(): Promise<void> {
    try {
      await this.analyticsManager.setEnabled(true);
      await this.analyticsManager.markAskedPermission();
      this.analyticsEnabled = true;
      this.hasAskedPermission = true;
      logger.info(TAG, '用户同意阅读报告权限，开始加载数据');
      
      // 加载数据
      this.isLoading = true;
      await this.loadReadingData();
    } catch (error) {
      logger.error(TAG, `处理同意权限失败: ${String(error)}`);
    }
  }
  
  /**
   * 处理用户拒绝权限
   */
  private async handleRejectPermission(): Promise<void> {
    try {
      // 确保功能保持关闭状态
      await this.analyticsManager.setEnabled(false);
      // 不标记已询问过权限，下次进入时继续显示权限请求界面
      this.analyticsEnabled = false;
      logger.info(TAG, '用户拒绝阅读报告权限，功能保持关闭，下次进入将继续询问');
      // 返回上一页
      this.pathStack.pop();
    } catch (error) {
      logger.error(TAG, `处理拒绝权限失败: ${String(error)}`);
      this.pathStack.pop();
    }
  }
  
  /**
   * 显示清除数据对话框
   */
  private showClearDataConfirmDialog(): void {
    this.showClearDataDialog = true;
  }
  
  /**
   * 清除阅读统计数据（仅重置页面显示的统计数据，不删除阅读记录）
   */
  private async clearReadingAnalyticsData(): Promise<void> {
    try {
      logger.info(TAG, '开始清除阅读统计数据（不删除阅读记录）');
      
      // 仅重置页面显示的统计数据，不删除实际的阅读记录
      this.statistics = {
        totalReadingTime: 0,
        totalComicsRead: 0,
        totalChaptersRead: 0,
        totalPagesRead: 0,
        averageReadingTime: 0,
        favoriteReadingHour: -1,  // -1 表示没有数据
        mostReadComicId: '',
        mostReadComicTitle: '暂无数据',
        mostReadEBookId: '',
        mostReadEBookTitle: '暂无数据',
        continuousReadingDays: 0,
        lastReadTime: 0,
        totalEBooksRead: 0,
        totalEBookReadingTime: 0,
        totalNovelsRead: 0,
        totalNovelReadingTime: 0
      };
      this.dailyData = [];
      this.allDailyData = [];
      this.hourlyDistribution = [];
      this.readingRankList = [];
      this.interestItems = [];
      this.inspirationStats = {
        totalCount: 0,
        bookmarkCount: 0,
        highlightCount: 0,
        thoughtCount: 0
      };
      this.dailyInspirationStats = {
        totalCount: 0,
        bookmarkCount: 0,
        highlightCount: 0,
        thoughtCount: 0
      };
      
      this.showClearDataDialog = false;
      logger.info(TAG, '阅读统计数据已清除（阅读记录保留）');
    } catch (error) {
      logger.error(TAG, `清除阅读统计数据失败: ${String(error)}`);
    }
  }
  
  /**
   * 关闭阅读报告功能并返回（不删除阅读记录）
   */
  private async clearDataAndDisableAnalytics(): Promise<void> {
    try {
      logger.info(TAG, '开始关闭阅读报告功能（不删除阅读记录）');
      
      // 关闭阅读报告功能
      await this.analyticsManager.setEnabled(false);
      this.analyticsEnabled = false;
      
      // 重置权限询问状态，下次进入需要重新询问
      await this.analyticsManager.resetAskedPermission();
      this.hasAskedPermission = false;
      
      // 仅重置页面显示的统计数据，不删除实际的阅读记录
      this.statistics = {
        totalReadingTime: 0,
        totalComicsRead: 0,
        totalChaptersRead: 0,
        totalPagesRead: 0,
        averageReadingTime: 0,
        favoriteReadingHour: -1,  // -1 表示没有数据
        mostReadComicId: '',
        mostReadComicTitle: '暂无数据',
        mostReadEBookId: '',
        mostReadEBookTitle: '暂无数据',
        continuousReadingDays: 0,
        lastReadTime: 0,
        totalEBooksRead: 0,
        totalEBookReadingTime: 0,
        totalNovelsRead: 0,
        totalNovelReadingTime: 0
      };
      this.dailyData = [];
      this.allDailyData = [];
      this.hourlyDistribution = [];
      this.readingRankList = [];
      this.interestItems = [];
      this.inspirationStats = {
        totalCount: 0,
        bookmarkCount: 0,
        highlightCount: 0,
        thoughtCount: 0
      };
      this.dailyInspirationStats = {
        totalCount: 0,
        bookmarkCount: 0,
        highlightCount: 0,
        thoughtCount: 0
      };
      
      this.showClearDataDialog = false;
      logger.info(TAG, '阅读报告功能已关闭，权限状态已重置（阅读记录保留），准备返回');
      
      // 返回上一页
      this.pathStack.pop();
    } catch (error) {
      logger.error(TAG, `关闭阅读报告功能失败: ${String(error)}`);
    }
  }

  private normalizeInspirationType(type: UnifiedAnnotationType): UnifiedAnnotationType {
    const raw = String(type);
    if (raw === UnifiedAnnotationType.BOOKMARK || raw === 'bookmark' || raw === '0' || raw === '书签') {
      return UnifiedAnnotationType.BOOKMARK;
    }
    if (raw === UnifiedAnnotationType.HIGHLIGHT || raw === 'highlight' || raw === '1' || raw === '划线') {
      return UnifiedAnnotationType.HIGHLIGHT;
    }
    return UnifiedAnnotationType.THOUGHT;
  }

  private buildInspirationStatistics(records: UnifiedAnnotationRecord[]): InspirationStatistics {
    let bookmarkCount = 0;
    let highlightCount = 0;
    let thoughtCount = 0;
    for (let i = 0; i < records.length; i++) {
      const type = this.normalizeInspirationType(records[i].annotationType);
      if (type === UnifiedAnnotationType.BOOKMARK) {
        bookmarkCount += 1;
      } else if (type === UnifiedAnnotationType.HIGHLIGHT) {
        highlightCount += 1;
      } else {
        thoughtCount += 1;
      }
    }
    return {
      totalCount: records.length,
      bookmarkCount,
      highlightCount,
      thoughtCount
    };
  }

  private async loadInspirationStats(startTime: number): Promise<void> {
    try {
      const allRecords = await this.annotationManager.getAllAnnotations();
      const filteredRecords = allRecords.filter((record: UnifiedAnnotationRecord) => record.createdAt >= startTime);
      this.inspirationStats = this.buildInspirationStatistics(filteredRecords);
      logger.info(
        TAG,
        `加载灵感统计成功: total=${this.inspirationStats.totalCount}, bookmark=${this.inspirationStats.bookmarkCount}, highlight=${this.inspirationStats.highlightCount}, thought=${this.inspirationStats.thoughtCount}`
      );
    } catch (error) {
      logger.warn(TAG, `加载灵感统计失败: ${String(error)}`);
      this.inspirationStats = {
        totalCount: 0,
        bookmarkCount: 0,
        highlightCount: 0,
        thoughtCount: 0
      };
    }
  }

  private async loadDailyInspirationStats(date: Date): Promise<void> {
    const startOfDay = new Date(date.getFullYear(), date.getMonth(), date.getDate(), 0, 0, 0, 0).getTime();
    const endOfDay = new Date(date.getFullYear(), date.getMonth(), date.getDate(), 23, 59, 59, 999).getTime();
    try {
      const allRecords = await this.annotationManager.getAllAnnotations();
      const filteredRecords = allRecords.filter((record: UnifiedAnnotationRecord) =>
        record.createdAt >= startOfDay && record.createdAt <= endOfDay
      );
      this.dailyInspirationStats = this.buildInspirationStatistics(filteredRecords);
      logger.debug(
        TAG,
        `加载当日灵感统计成功: date=${date.getFullYear()}-${String(date.getMonth() + 1).padStart(2, '0')}-${String(date.getDate()).padStart(2, '0')}, total=${this.dailyInspirationStats.totalCount}`
      );
    } catch (error) {
      logger.warn(TAG, `加载当日灵感统计失败: ${String(error)}`);
      this.dailyInspirationStats = {
        totalCount: 0,
        bookmarkCount: 0,
        highlightCount: 0,
        thoughtCount: 0
      };
    }
  }

  private openInspirationCenter(trigger: string): void {
    try {
      const params: AnnotationCenterPageParams = {
        contentTitle: '全部内容'
      };
      this.pathStack.pushPathByName('AnnotationCenterPage', params);
      logger.info(TAG, `从阅读报告跳转灵感页: trigger=${trigger}`);
    } catch (error) {
      logger.error(TAG, `跳转灵感页失败: trigger=${trigger}, error=${String(error)}`);
    }
  }

  /**
   * 切换视图模式（长期视图 / 日视图）
   */
  private toggleViewMode(): void {
    this.isLongTermView = !this.isLongTermView;
    logger.info(TAG, `切换到${this.isLongTermView ? '长期视图' : '日视图'}`);
    
    // 持久化保存视图模式
    this.analyticsManager.setLongTermView(this.isLongTermView);
    
    if (!this.isLongTermView) {
      // 切换到日视图时，加载当天数据
      this.loadDailyViewData(this.selectedDate);
    }
  }

  /**
   * 加载日视图数据
   */
  private async loadDailyViewData(date: Date): Promise<void> {
    this.isDailyLoading = true;
    
    const dateKey = `${date.getFullYear()}-${String(date.getMonth() + 1).padStart(2, '0')}-${String(date.getDate()).padStart(2, '0')}`;
    
    // 从所有历史数据中查找（使用 allDailyData 而不是 dailyData）
    const dayData = this.allDailyData.find(d => d.date === dateKey);
    
    if (dayData) {
      this.dailyViewData = dayData;
    } else {
      // 没有数据时创建空数据
      this.dailyViewData = {
        date: dateKey,
        readingTime: 0,
        chaptersRead: 0,
        pagesRead: 0
      };
    }
    
    // 加载当天阅读的漫画列表
    await this.loadDailyMangaList(date);
    
    // 加载当天阅读的电子书列表
    await this.loadDailyEBookList(date);
    
    // 加载当天阅读的小说列表（包括在线小说）
    await this.loadDailyNovelList(date);
    
    // 从漫画列表计算阅读页数
    let mangaPagesRead = 0;
    let mangaChaptersRead = 0;
    let mangaReadingTime = 0;
    this.dailyMangaList.forEach(manga => {
      mangaPagesRead += manga.pagesRead;
      mangaChaptersRead += manga.chaptersRead;
      mangaReadingTime += manga.readingTime;
    });
    
    // 从电子书列表计算阅读时长和章节数
    let ebookReadingTime = 0;
    let ebookChapters = 0;
    this.dailyEBookList.forEach(ebook => {
      ebookReadingTime += ebook.readingTime;
      ebookChapters += 1;  // 每本电子书算作一个阅读项
    });
    
    // 从小说列表计算阅读时长和章节数
    let novelReadingTime = 0;
    let novelChapters = 0;
    this.dailyNovelList.forEach(novel => {
      novelReadingTime += novel.readingTime;
      novelChapters += novel.chaptersRead;
    });
    
    // 更新日视图数据，使用从列表计算的数据
    this.dailyViewData = {
      date: dateKey,
      readingTime: mangaReadingTime + ebookReadingTime + novelReadingTime,
      chaptersRead: mangaChaptersRead + ebookChapters + novelChapters,
      pagesRead: mangaPagesRead
    };
    
    // 更新当日阅读分钟数状态变量（用于阅读目标进度显示）
    this.dailyMangaReadingMinutes = Math.round(mangaReadingTime / 60);
    this.dailyEbookReadingMinutes = Math.round(ebookReadingTime / 60);
    this.dailyNovelReadingMinutes = Math.round(novelReadingTime / 60);
    
    logger.debug(TAG, `日视图数据: ${dateKey}, 时长: ${this.dailyViewData?.readingTime || 0}秒, 漫画数: ${this.dailyMangaList.length}, 电子书数: ${this.dailyEBookList.length}, 小说数: ${this.dailyNovelList.length}`);
    logger.debug(TAG, `阅读目标进度: 漫画=${this.dailyMangaReadingMinutes}分钟, 电子书=${this.dailyEbookReadingMinutes}分钟, 小说=${this.dailyNovelReadingMinutes}分钟`);

    await this.loadDailyInspirationStats(date);
    
    this.isDailyLoading = false;
  }

  /**
   * 加载当天阅读的漫画列表
   */
  private async loadDailyMangaList(date: Date): Promise<void> {
    const startOfDay = new Date(date.getFullYear(), date.getMonth(), date.getDate(), 0, 0, 0).getTime();
    const endOfDay = new Date(date.getFullYear(), date.getMonth(), date.getDate(), 23, 59, 59, 999).getTime();
    
    // 过滤当天的阅读记录
    const dayRecords = this.cachedReadHistory.filter(record => 
      record.readTime >= startOfDay && record.readTime <= endOfDay
    );
    
    // 按漫画ID分组统计
    const mangaMap = new Map<string, MangaReadingStatData>();
    
    dayRecords.forEach(record => {
      const existing = mangaMap.get(record.comicId);
      if (existing) {
        existing.time += record.readDuration;
        existing.chapters.add(record.chapterId);
        existing.pages += 1;
      } else {
        const chapters = new Set<string>();
        chapters.add(record.chapterId);
        const newStat: MangaReadingStatData = {
          time: record.readDuration,
          chapters: chapters,
          pages: 1
        };
        mangaMap.set(record.comicId, newStat);
      }
    });
    
    // 获取漫画详细信息并构建列表
    const mangaList: DailyMangaItem[] = [];
    const entries = Array.from(mangaMap.entries());
    const comicIds: string[] = [];
    for (const entry of entries) {
      comicIds.push(entry[0]);
    }
    const comicInfoMap: Map<string, ComicInfo> = await this.dataManager.getComicsByIds(comicIds);
    
    for (const entry of entries) {
      const comicId = entry[0];
      const stats = entry[1];
      const comic = comicInfoMap.get(comicId);
      if (comic) {
        // 过滤使用手册
        if (comic.title === USER_MANUAL_TITLE) {
          continue;
        }
        mangaList.push({
          comicId: comicId,
          title: comic.title,
          coverPath: comic.coverLocalPath || comic.coverUrl || '',
          readingTime: Math.round(stats.time / 1000), // 毫秒转秒
          chaptersRead: stats.chapters.size,
          pagesRead: stats.pages
        });
      } else {
        logger.warn(TAG, `无法获取漫画信息: ${comicId}`);
      }
    }
    
    // 按阅读时长排序
    mangaList.sort((a, b) => b.readingTime - a.readingTime);
    this.dailyMangaList = mangaList;
  }

  /**
   * 加载当天阅读的电子书列表
   */
  private async loadDailyEBookList(date: Date): Promise<void> {
    const dateKey = `${date.getFullYear()}-${String(date.getMonth() + 1).padStart(2, '0')}-${String(date.getDate()).padStart(2, '0')}`;
    
    try {
      // 获取所有有阅读记录的电子书
      const ebooksWithProgress = await this.ebookDataManager.getEBooksWithReadingProgress();
      
      // 筛选当天有阅读记录的电子书（通过检查 lastReadTime）
      const ebookList: DailyEBookItem[] = [];
      
      for (const ebook of ebooksWithProgress) {
        if (ebook.readingProgress && ebook.readingProgress.lastReadTime) {
          const lastReadDate = new Date(ebook.readingProgress.lastReadTime);
          const lastReadDateKey = `${lastReadDate.getFullYear()}-${String(lastReadDate.getMonth() + 1).padStart(2, '0')}-${String(lastReadDate.getDate()).padStart(2, '0')}`;
          
          // 检查是否是当天阅读的
          if (lastReadDateKey === dateKey) {
            // 过滤使用手册
            if (ebook.metadata.title === USER_MANUAL_TITLE) {
              continue;
            }
            const progressValue = ebook.readingProgress.progress || 0;
            logger.debug(TAG, `电子书 ${ebook.metadata.title} 进度: ${progressValue}%`);
            ebookList.push({
              ebookId: ebook.id,
              title: ebook.metadata.title,
              coverPath: ebook.metadata.coverImagePath || '',
              readingTime: Math.round((ebook.readingProgress.totalReadingTime || 0) * 60), // 分钟转秒
              progress: progressValue
            });
          }
        }
      }
      
      // 按阅读时长排序
      ebookList.sort((a, b) => b.readingTime - a.readingTime);
      this.dailyEBookList = ebookList;
    } catch (error) {
      logger.warn(TAG, `加载当天电子书列表失败: ${String(error)}`);
      this.dailyEBookList = [];
    }
  }

  /**
   * 加载当天阅读的小说列表（包括本地和在线小说）
   */
  private async loadDailyNovelList(date: Date): Promise<void> {
    const dateKey = `${date.getFullYear()}-${String(date.getMonth() + 1).padStart(2, '0')}-${String(date.getDate()).padStart(2, '0')}`;
    
    try {
      const novelDataManager = getNovelDataManager();
      // 获取所有有阅读时长的小说
      const novelsWithTime = await novelDataManager.getBooksWithReadingTime();
      
      // 筛选当天有阅读记录的小说
      const novelList: DailyNovelItem[] = [];
      
      for (const novel of novelsWithTime) {
        if (novel.lastReadTime && novel.lastReadTime > 0) {
          const lastReadDate = new Date(novel.lastReadTime);
          const lastReadDateKey = `${lastReadDate.getFullYear()}-${String(lastReadDate.getMonth() + 1).padStart(2, '0')}-${String(lastReadDate.getDate()).padStart(2, '0')}`;
          
          // 检查是否是当天阅读的
          if (lastReadDateKey === dateKey) {
            // 过滤使用手册
            if (novel.name === USER_MANUAL_TITLE) {
              continue;
            }
            // 判断是否是在线小说（有sourceId且非local）
            const isOnline = novel.sourceId !== undefined && novel.sourceId !== '' && novel.sourceId !== 'local';
            
            // 添加调试日志，确认 bookUrl 和 id 的实际值
            logger.debug(TAG, `小说数据: id=${novel.id}, bookUrl=${novel.bookUrl}, sourceId=${novel.sourceId}`);
            
            novelList.push({
              novelId: novel.id,
              bookUrl: novel.bookUrl,  // 用于导航到详情页
              sourceId: novel.sourceId || '',
              title: novel.name,
              author: novel.author || '未知作者',
              coverPath: novel.coverUrl || '',
              readingTime: novel.totalReadingTime || 0,  // 小说的totalReadingTime是秒
              chaptersRead: (novel.lastReadChapterIndex || 0) + 1,
              isOnline: isOnline
            });
            
            logger.debug(TAG, `小说 ${novel.name} (在线: ${isOnline}), 时长: ${novel.totalReadingTime}秒`);
          }
        }
      }
      
      // 按阅读时长排序
      novelList.sort((a, b) => b.readingTime - a.readingTime);
      this.dailyNovelList = novelList;
    } catch (error) {
      logger.warn(TAG, `加载当天小说列表失败: ${String(error)}`);
      this.dailyNovelList = [];
    }
  }

  /**
   * 选择日期（日视图）
   */
  private selectDate(date: Date): void {
    this.selectedDate = date;
    this.loadDailyViewData(date);
  }

  /**
   * 切换到上一个月
   */
  private previousMonth(): void {
    const newMonth = new Date(this.currentMonth);
    newMonth.setMonth(newMonth.getMonth() - 1);
    this.currentMonth = newMonth;
  }

  /**
   * 切换到下一个月
   */
  private nextMonth(): void {
    const newMonth = new Date(this.currentMonth);
    newMonth.setMonth(newMonth.getMonth() + 1);
    this.currentMonth = newMonth;
  }

  /**
   * 获取指定月份的天数
   */
  private getDaysInMonth(year: number, month: number): number {
    return new Date(year, month + 1, 0).getDate();
  }

  /**
   * 获取指定月份第一天是星期几（0-6，0为周日）
   */
  private getFirstDayOfMonth(year: number, month: number): number {
    return new Date(year, month, 1).getDay();
  }

  /**
   * 检查某天是否有阅读记录
   */
  private hasReadingDataOnDate(date: Date): boolean {
    const dateKey = `${date.getFullYear()}-${String(date.getMonth() + 1).padStart(2, '0')}-${String(date.getDate()).padStart(2, '0')}`;
    return this.allDailyData.some(d => d.date === dateKey && d.readingTime > 0);
  }

  /**
   * 检查是否是选中的日期
   */
  private isSelectedDate(date: Date): boolean {
    return date.getFullYear() === this.selectedDate.getFullYear() &&
           date.getMonth() === this.selectedDate.getMonth() &&
           date.getDate() === this.selectedDate.getDate();
  }

  /**
   * 检查是否是今天
   */
  private isToday(date: Date): boolean {
    const today = new Date();
    return date.getFullYear() === today.getFullYear() &&
           date.getMonth() === today.getMonth() &&
           date.getDate() === today.getDate();
  }

  /**
   * 加载阅读数据
   */
  private async loadReadingData(): Promise<void> {
    this.isLoading = true;
    try {
      logger.info(TAG, '开始加载阅读数据');

      // 获取漫画阅读历史记录
      const readHistory: ReadHistory[] = await this.dataService.getReadingHistory(1000);
      this.cachedReadHistory = readHistory; // 缓存用于日视图
      logger.debug(TAG, `获取到 ${readHistory.length} 条漫画阅读记录`);

      // 获取电子书阅读数据
      const ebooksWithProgress: EBook[] = await this.ebookDataManager.getEBooksWithReadingProgress();
      logger.debug(TAG, `获取到 ${ebooksWithProgress.length} 本有阅读记录的电子书`);

      const now = Date.now();
      const timeRangeMs = this.selectedTimeRange * 24 * 60 * 60 * 1000;
      const startTime = now - timeRangeMs;

      // 分析漫画数据
      await this.analyzeReadingData(readHistory);
      
      // 分析电子书数据（传入时间范围进行过滤）
      this.analyzeEBookData(ebooksWithProgress, startTime);
      
      // 分析小说数据
      const novelAnalysisData = await this.analyzeNovelData(startTime);
      
      // 重新计算日均阅读时长（合并漫画、电子书和小说的阅读天数）
      this.recalculateAverageReadingTime(readHistory, ebooksWithProgress, novelAnalysisData.filteredNovels, startTime);
      
      // 重新计算连续阅读天数（合并漫画、电子书和小说的阅读日期）
      this.recalculateContinuousReadingDays(readHistory, ebooksWithProgress, novelAnalysisData.allNovels);
      
      // 重新计算最喜欢的阅读时段（合并漫画、电子书和小说的阅读时间）
      this.recalculateFavoriteReadingHour(readHistory, ebooksWithProgress, novelAnalysisData.filteredNovels, startTime);

      // 重新计算最后阅读时间（合并漫画、电子书和小说）
      this.recalculateLastReadTime(readHistory, ebooksWithProgress, novelAnalysisData.allNovels);

      // 合并电子书和小说的按日数据
      this.rebuildUnifiedDailyData(readHistory, ebooksWithProgress, novelAnalysisData.allNovels, startTime);
      
      // 加载阅读时长排行（包含漫画和电子书）
      await this.loadReadingRank(readHistory, ebooksWithProgress);
      
      // 分析用户兴趣
      await this.analyzeUserInterests();

      // 加载灵感统计（按当前时间范围）
      await this.loadInspirationStats(startTime);

      logger.info(TAG, '阅读数据加载完成');
    } catch (error) {
      logger.error(TAG, '加载阅读数据失败', String(error));
    } finally {
      this.isLoading = false;
    }
  }

  /**
   * 分析电子书数据
   * @param ebooks 电子书列表
   * @param startTime 时间范围开始时间（用于过滤）
   */
  private analyzeEBookData(ebooks: EBook[], startTime: number): void {
    try {
      // 过滤时间范围内有阅读记录的电子书（排除使用手册）
      const filteredEbooks = ebooks.filter((ebook: EBook) => {
        if (!ebook.readingProgress || !ebook.readingProgress.lastReadTime) {
          return false;
        }
        // 过滤使用手册
        if (ebook.metadata.title === USER_MANUAL_TITLE) {
          return false;
        }
        return ebook.readingProgress.lastReadTime >= startTime;
      });
      
      this.statistics.totalEBooksRead = filteredEbooks.length;
      
      // 计算电子书总阅读时长（电子书的 totalReadingTime 是分钟，需要转换为秒）
      let totalEBookTimeMinutes = 0;
      let totalEBookChapters = 0;
      let totalEBookPages = 0;
      
      filteredEbooks.forEach((ebook: EBook) => {
        if (ebook.readingProgress) {
          // 累加阅读时长
          if (ebook.readingProgress.totalReadingTime > 0) {
            totalEBookTimeMinutes += ebook.readingProgress.totalReadingTime;
          }
          // 累加已读章节数（当前章节索引+1表示已读到第几章）
          if (ebook.readingProgress.currentChapterIndex >= 0) {
            totalEBookChapters += ebook.readingProgress.currentChapterIndex + 1;
          }
          // 估算阅读页数：基于阅读进度和电子书总章节数
          // 每本电子书按平均每章10页估算，乘以阅读进度百分比
          const estimatedTotalPages = ebook.chapters.length * 10;
          const readPages = Math.round(estimatedTotalPages * (ebook.readingProgress.progress / 100));
          totalEBookPages += Math.max(1, readPages); // 至少1页
        }
      });
      
      // 分钟转秒
      this.statistics.totalEBookReadingTime = Math.round(totalEBookTimeMinutes * 60);
      
      // 将电子书阅读时长加入总阅读时长（都是秒）
      this.statistics.totalReadingTime += this.statistics.totalEBookReadingTime;
      
      // 将电子书章节数和页数加入总统计
      this.statistics.totalChaptersRead += totalEBookChapters;
      this.statistics.totalPagesRead += totalEBookPages;
      
      logger.debug(TAG, `电子书统计: ${this.statistics.totalEBooksRead} 本, 时长 ${this.statistics.totalEBookReadingTime} 秒, 章节 ${totalEBookChapters}, 页数 ${totalEBookPages}`);
    } catch (error) {
      logger.error(TAG, `分析电子书数据失败: ${String(error)}`);
    }
  }

  /**
   * 分析小说数据
   * @param startTime 时间范围开始时间（用于过滤）
   */
  private async analyzeNovelData(startTime: number): Promise<NovelAnalysisData> {
    try {
      const novelDataManager = getNovelDataManager();
      const novels = await novelDataManager.getBooksWithReadingTime();
      
      // 过滤时间范围内有阅读记录的小说（排除使用手册）
      const filteredNovels = novels.filter((novel: NovelBook) => {
        if (!novel.lastReadTime) {
          return false;
        }
        // 过滤使用手册
        if (novel.name === USER_MANUAL_TITLE) {
          return false;
        }
        return novel.lastReadTime >= startTime;
      });
      
      this.statistics.totalNovelsRead = filteredNovels.length;
      
      // 计算小说总阅读时长（小说的 totalReadingTime 是秒）
      let totalNovelTime = 0;
      let totalNovelChapters = 0;
      
      filteredNovels.forEach((novel: NovelBook) => {
        // 累加阅读时长
        if (novel.totalReadingTime > 0) {
          totalNovelTime += novel.totalReadingTime;
        }
        // 累加已读章节数
        if (novel.lastReadChapterIndex !== undefined && novel.lastReadChapterIndex >= 0) {
          totalNovelChapters += novel.lastReadChapterIndex + 1;
        }
      });
      
      this.statistics.totalNovelReadingTime = totalNovelTime;
      
      // 将小说阅读时长加入总阅读时长
      this.statistics.totalReadingTime += this.statistics.totalNovelReadingTime;
      
      // 将小说章节数加入总统计
      this.statistics.totalChaptersRead += totalNovelChapters;
      
      logger.debug(TAG, `小说统计: ${this.statistics.totalNovelsRead} 本, 时长 ${this.statistics.totalNovelReadingTime} 秒, 章节 ${totalNovelChapters}`);
      const result: NovelAnalysisData = {
        filteredNovels: filteredNovels,
        allNovels: novels
      };
      return result;
    } catch (error) {
      logger.error(TAG, `分析小说数据失败: ${String(error)}`);
      const emptyResult: NovelAnalysisData = {
        filteredNovels: [],
        allNovels: []
      };
      return emptyResult;
    }
  }

  /**
   * 分析阅读数据
   */
  private async analyzeReadingData(readHistory: ReadHistory[]): Promise<void> {
    try {
      const now = Date.now();
      const timeRangeMs = this.selectedTimeRange * 24 * 60 * 60 * 1000;
      const startTime = now - timeRangeMs;

      // 过滤时间范围内的记录
      const filteredHistory = readHistory.filter(record => record.readTime >= startTime);

      // 统计总阅读时长（readDuration 是毫秒，转换为秒以保留精度）
      const totalReadingTimeMs = filteredHistory.reduce((sum: number, record: ReadHistory): number => {
        return sum + record.readDuration;
      }, 0);
      this.statistics.totalReadingTime = Math.round(totalReadingTimeMs / 1000);  // 毫秒转秒

      // 统计阅读过的漫画数量
      const comicIds = new Set<string>();
      const chapterIds = new Set<string>();
      let totalPages = 0;

      filteredHistory.forEach(record => {
        comicIds.add(record.comicId);
        chapterIds.add(record.chapterId);
        totalPages += 1; // 每条记录代表一页
      });

      this.statistics.totalComicsRead = comicIds.size;
      this.statistics.totalChaptersRead = chapterIds.size;
      this.statistics.totalPagesRead = totalPages;

      // 计算平均每天阅读时长（基于有阅读记录的实际天数）
      const uniqueReadDates = new Set<string>();
      filteredHistory.forEach(record => {
        const date = new Date(record.readTime);
        const dateKey = `${date.getFullYear()}-${String(date.getMonth() + 1).padStart(2, '0')}-${String(date.getDate()).padStart(2, '0')}`;
        uniqueReadDates.add(dateKey);
      });
      const actualReadingDays = uniqueReadDates.size;
      this.statistics.averageReadingTime = actualReadingDays > 0
        ? Math.round(this.statistics.totalReadingTime / actualReadingDays)
        : 0;

      // 分析阅读时段分布
      this.analyzeHourlyDistribution(filteredHistory);

      // 分析每日阅读数据（用于统计展示）
      this.analyzeDailyData(filteredHistory);
      
      // 分析所有历史的每日数据（用于日历视图，不受时间范围限制）
      this.analyzeAllDailyData(readHistory);

      // 查找阅读最多的漫画
      await this.findMostReadComic(filteredHistory);

      // 查找阅读最多的电子书
      await this.findMostReadEBook();

      // 计算连续阅读天数
      this.calculateContinuousReadingDays(filteredHistory);

      // 获取最后阅读时间
      if (readHistory.length > 0) {
        this.statistics.lastReadTime = readHistory[0].readTime;
      }

      logger.debug(TAG, `分析完成: 总时长${this.statistics.totalReadingTime}分钟, 漫画${this.statistics.totalComicsRead}本`);
    } catch (error) {
      logger.error(TAG, '分析阅读数据失败', String(error));
    }
  }

  /**
   * 分析阅读时段分布
   */
  private analyzeHourlyDistribution(readHistory: ReadHistory[]): void {
    const hourlyMap = new Map<number, HourlyStatData>();

    // 初始化24小时数据
    for (let hour = 0; hour < 24; hour++) {
      const statData: HourlyStatData = { count: 0, time: 0 };
      hourlyMap.set(hour, statData);
    }

    // 统计每个小时的阅读次数和时长
    readHistory.forEach(record => {
      const date = new Date(record.readTime);
      const hour = date.getHours();
      const existing = hourlyMap.get(hour);
      if (existing) {
        existing.count += 1;
        existing.time += Math.round(record.readDuration / 1000);  // 毫秒转秒
        hourlyMap.set(hour, existing);
      }
    });

    // 转换为数组
    this.hourlyDistribution = [];
    hourlyMap.forEach((value, hour) => {
      this.hourlyDistribution.push({
        hour: hour,
        readingCount: value.count,
        readingTime: value.time
      });
    });

    // 找出最喜欢的阅读时段
    let maxCount = 0;
    let favoriteHour = -1;  // 使用 -1 表示没有数据
    hourlyMap.forEach((value, hour) => {
      if (value.count > maxCount) {
        maxCount = value.count;
        favoriteHour = hour;
      }
    });
    this.statistics.favoriteReadingHour = favoriteHour;
  }

  /**
   * 分析每日阅读数据
   */
  private analyzeDailyData(readHistory: ReadHistory[]): void {
    const dailyMap = new Map<string, DailyStatData>();

    readHistory.forEach(record => {
      const date = new Date(record.readTime);
      const dateKey = `${date.getFullYear()}-${String(date.getMonth() + 1).padStart(2, '0')}-${String(date.getDate()).padStart(2, '0')}`;

      const existing = dailyMap.get(dateKey);
      if (existing) {
        existing.time += Math.round(record.readDuration / 1000);  // 毫秒转秒
        existing.chapters.add(record.chapterId);
        existing.pages += 1;
        dailyMap.set(dateKey, existing);
      } else {
        const chapters = new Set<string>();
        chapters.add(record.chapterId);
        const newData: DailyStatData = {
          time: Math.round(record.readDuration / 1000),  // 毫秒转秒
          chapters: chapters,
          pages: 1
        };
        dailyMap.set(dateKey, newData);
      }
    });

    // 转换为数组并排序
    this.dailyData = [];
    dailyMap.forEach((value, dateKey) => {
      this.dailyData.push({
        date: dateKey,
        readingTime: value.time,
        chaptersRead: value.chapters.size,
        pagesRead: value.pages
      });
    });

    this.dailyData.sort((a, b) => b.date.localeCompare(a.date));
  }

  /**
   * 分析所有历史的每日阅读数据（用于日历视图，不受时间范围限制）
   */
  private analyzeAllDailyData(readHistory: ReadHistory[]): void {
    const dailyMap = new Map<string, DailyStatData>();

    readHistory.forEach(record => {
      const date = new Date(record.readTime);
      const dateKey = `${date.getFullYear()}-${String(date.getMonth() + 1).padStart(2, '0')}-${String(date.getDate()).padStart(2, '0')}`;

      const existing = dailyMap.get(dateKey);
      if (existing) {
        existing.time += Math.round(record.readDuration / 1000);  // 毫秒转秒
        existing.chapters.add(record.chapterId);
        existing.pages += 1;
        dailyMap.set(dateKey, existing);
      } else {
        const chapters = new Set<string>();
        chapters.add(record.chapterId);
        const newData: DailyStatData = {
          time: Math.round(record.readDuration / 1000),  // 毫秒转秒
          chapters: chapters,
          pages: 1
        };
        dailyMap.set(dateKey, newData);
      }
    });

    // 转换为数组并排序
    this.allDailyData = [];
    dailyMap.forEach((value, dateKey) => {
      this.allDailyData.push({
        date: dateKey,
        readingTime: value.time,
        chaptersRead: value.chapters.size,
        pagesRead: value.pages
      });
    });

    this.allDailyData.sort((a, b) => b.date.localeCompare(a.date));
    logger.debug(TAG, `分析完成所有历史每日数据: ${this.allDailyData.length} 天`);
  }

  /**
   * 查找阅读最多的漫画
   */
  private async findMostReadComic(readHistory: ReadHistory[]): Promise<void> {
    const comicCountMap = new Map<string, number>();

    readHistory.forEach(record => {
      const count = comicCountMap.get(record.comicId) || 0;
      comicCountMap.set(record.comicId, count + 1);
    });

    let maxCount = 0;
    let mostReadComicId = '';
    const comicIds: string[] = Array.from(comicCountMap.keys());
    const comicInfoMap: Map<string, ComicInfo> = await this.dataManager.getComicsByIds(comicIds);
    
    // 遍历找出阅读最多的漫画，排除使用手册
    for (const entry of comicCountMap.entries()) {
      const comicId = entry[0];
      const count = entry[1];
      
      if (count > maxCount) {
        const comic = comicInfoMap.get(comicId);
        if (comic && comic.title !== USER_MANUAL_TITLE) {
          maxCount = count;
          mostReadComicId = comicId;
        }
      }
    }

    this.statistics.mostReadComicId = mostReadComicId;
    
    // 从数据库查询漫画标题
    if (mostReadComicId) {
      const comic = comicInfoMap.get(mostReadComicId);
      this.statistics.mostReadComicTitle = comic ? comic.title : `漫画ID: ${mostReadComicId}`;
    } else {
      this.statistics.mostReadComicTitle = '暂无数据';
    }
  }

  /**
   * 查找阅读最多的电子书
   */
  private async findMostReadEBook(): Promise<void> {
    try {
      const ebookDataManager = EBookDataManager.getInstance();
      const allEBooks: EBook[] = await ebookDataManager.getEBooksWithReadingProgress();
      
      if (allEBooks.length === 0) {
        this.statistics.mostReadEBookId = '';
        this.statistics.mostReadEBookTitle = '暂无数据';
        return;
      }
      
      // 根据阅读时长找出阅读最多的电子书（排除使用手册）
      let maxReadingTime = 0;
      let mostReadEBook: EBook | null = null;
      
      for (const ebook of allEBooks) {
        // 过滤使用手册
        if (ebook.metadata.title === USER_MANUAL_TITLE) {
          continue;
        }
        const readingTime: number = ebook.readingProgress?.totalReadingTime || 0;
        if (readingTime > maxReadingTime) {
          maxReadingTime = readingTime;
          mostReadEBook = ebook;
        }
      }
      
      if (mostReadEBook && maxReadingTime > 0) {
        this.statistics.mostReadEBookId = mostReadEBook.id;
        this.statistics.mostReadEBookTitle = mostReadEBook.metadata.title;
      } else {
        this.statistics.mostReadEBookId = '';
        this.statistics.mostReadEBookTitle = '暂无数据';
      }
    } catch (error) {
      logger.warn(TAG, `查找阅读最多的电子书失败: ${String(error)}`);
      this.statistics.mostReadEBookId = '';
      this.statistics.mostReadEBookTitle = '暂无数据';
    }
  }

  /**
   * 计算连续阅读天数
   */
  private calculateContinuousReadingDays(readHistory: ReadHistory[]): void {
    if (readHistory.length === 0) {
      this.statistics.continuousReadingDays = 0;
      return;
    }

    // 提取所有阅读日期（去重）
    const readDates = new Set<string>();
    readHistory.forEach(record => {
      const date = new Date(record.readTime);
      const dateKey = `${date.getFullYear()}-${String(date.getMonth() + 1).padStart(2, '0')}-${String(date.getDate()).padStart(2, '0')}`;
      readDates.add(dateKey);
    });

    // 将日期转换为数组并排序
    const sortedDates = Array.from(readDates).sort((a, b) => b.localeCompare(a));

    // 从今天开始倒推计算连续天数
    const today = new Date();
    const todayKey = `${today.getFullYear()}-${String(today.getMonth() + 1).padStart(2, '0')}-${String(today.getDate()).padStart(2, '0')}`;

    let continuousDays = 0;
    let currentDate = new Date(today);

    // 检查是否包含今天或昨天（给予1天容差）
    const yesterdayDate = new Date(today.getTime() - 24 * 60 * 60 * 1000);
    const yesterdayKey = `${yesterdayDate.getFullYear()}-${String(yesterdayDate.getMonth() + 1).padStart(2, '0')}-${String(yesterdayDate.getDate()).padStart(2, '0')}`;

    if (!readDates.has(todayKey) && !readDates.has(yesterdayKey)) {
      this.statistics.continuousReadingDays = 0;
      return;
    }

    // 从今天开始倒推
    while (true) {
      const dateKey = `${currentDate.getFullYear()}-${String(currentDate.getMonth() + 1).padStart(2, '0')}-${String(currentDate.getDate()).padStart(2, '0')}`;
      if (readDates.has(dateKey)) {
        continuousDays++;
        currentDate = new Date(currentDate.getTime() - 24 * 60 * 60 * 1000);
      } else {
        break;
      }
    }

    this.statistics.continuousReadingDays = continuousDays;
  }

  /**
   * 重新计算日均阅读时长（合并漫画、电子书和小说的阅读天数）
   */
  private recalculateAverageReadingTime(readHistory: ReadHistory[], ebooks: EBook[], novels: NovelBook[], startTime: number): void {
    const uniqueReadDates = new Set<string>();
    
    // 添加漫画阅读日期
    readHistory.forEach(record => {
      if (record.readTime >= startTime) {
        uniqueReadDates.add(this.formatDateKey(record.readTime));
      }
    });
    
    // 添加电子书阅读日期
    ebooks.forEach((ebook: EBook) => {
      if (ebook.readingProgress && ebook.readingProgress.lastReadTime && ebook.readingProgress.lastReadTime >= startTime) {
        uniqueReadDates.add(this.formatDateKey(ebook.readingProgress.lastReadTime));
      }
    });

    // 添加小说阅读日期
    novels.forEach((novel: NovelBook) => {
      if (novel.lastReadTime && novel.lastReadTime >= startTime) {
        uniqueReadDates.add(this.formatDateKey(novel.lastReadTime));
      }
    });
    
    const actualReadingDays = uniqueReadDates.size;
    this.statistics.averageReadingTime = actualReadingDays > 0
      ? Math.round(this.statistics.totalReadingTime / actualReadingDays)
      : 0;
    
    logger.debug(TAG, `日均阅读时长重新计算: 总时长=${this.statistics.totalReadingTime}秒, 阅读天数=${actualReadingDays}, 日均=${this.statistics.averageReadingTime}秒`);
  }

  /**
   * 重新计算连续阅读天数（合并漫画、电子书和小说的阅读日期）
   */
  private recalculateContinuousReadingDays(readHistory: ReadHistory[], ebooks: EBook[], novels: NovelBook[]): void {
    const readDates = new Set<string>();
    
    // 添加漫画阅读日期
    readHistory.forEach(record => {
      readDates.add(this.formatDateKey(record.readTime));
    });
    
    // 添加电子书阅读日期
    ebooks.forEach((ebook: EBook) => {
      if (ebook.metadata.title !== USER_MANUAL_TITLE && ebook.readingProgress && ebook.readingProgress.lastReadTime) {
        readDates.add(this.formatDateKey(ebook.readingProgress.lastReadTime));
      }
    });

    // 添加小说阅读日期
    novels.forEach((novel: NovelBook) => {
      if (novel.name !== USER_MANUAL_TITLE && novel.lastReadTime && novel.lastReadTime > 0) {
        readDates.add(this.formatDateKey(novel.lastReadTime));
      }
    });
    
    if (readDates.size === 0) {
      this.statistics.continuousReadingDays = 0;
      return;
    }
    
    // 从今天开始倒推计算连续天数
    const today = new Date();
    const todayKey = `${today.getFullYear()}-${String(today.getMonth() + 1).padStart(2, '0')}-${String(today.getDate()).padStart(2, '0')}`;
    const yesterdayDate = new Date(today.getTime() - 24 * 60 * 60 * 1000);
    const yesterdayKey = `${yesterdayDate.getFullYear()}-${String(yesterdayDate.getMonth() + 1).padStart(2, '0')}-${String(yesterdayDate.getDate()).padStart(2, '0')}`;
    
    if (!readDates.has(todayKey) && !readDates.has(yesterdayKey)) {
      this.statistics.continuousReadingDays = 0;
      return;
    }
    
    let continuousDays = 0;
    let currentDate = new Date(today);
    
    while (true) {
      const dateKey = `${currentDate.getFullYear()}-${String(currentDate.getMonth() + 1).padStart(2, '0')}-${String(currentDate.getDate()).padStart(2, '0')}`;
      if (readDates.has(dateKey)) {
        continuousDays++;
        currentDate = new Date(currentDate.getTime() - 24 * 60 * 60 * 1000);
      } else {
        break;
      }
    }
    
    this.statistics.continuousReadingDays = continuousDays;
    logger.debug(TAG, `连续阅读天数重新计算: ${continuousDays}天`);
  }

  /**
   * 重新计算最喜欢的阅读时段（合并漫画、电子书和小说的阅读时间）
   */
  private recalculateFavoriteReadingHour(readHistory: ReadHistory[], ebooks: EBook[], novels: NovelBook[], startTime: number): void {
    const hourlyMap = new Map<number, number>();
    
    // 初始化24小时数据
    for (let hour = 0; hour < 24; hour++) {
      hourlyMap.set(hour, 0);
    }
    
    // 统计漫画阅读时段
    readHistory.forEach(record => {
      if (record.readTime >= startTime) {
        const date = new Date(record.readTime);
        const hour = date.getHours();
        hourlyMap.set(hour, (hourlyMap.get(hour) || 0) + 1);
      }
    });
    
    // 统计电子书阅读时段
    ebooks.forEach((ebook: EBook) => {
      if (ebook.readingProgress && ebook.readingProgress.lastReadTime && ebook.readingProgress.lastReadTime >= startTime) {
        const date = new Date(ebook.readingProgress.lastReadTime);
        const hour = date.getHours();
        hourlyMap.set(hour, (hourlyMap.get(hour) || 0) + 1);
      }
    });

    // 统计小说阅读时段
    novels.forEach((novel: NovelBook) => {
      if (novel.lastReadTime && novel.lastReadTime >= startTime) {
        const date = new Date(novel.lastReadTime);
        const hour = date.getHours();
        hourlyMap.set(hour, (hourlyMap.get(hour) || 0) + 1);
      }
    });
    
    // 找出最喜欢的阅读时段
    let maxCount = 0;
    let favoriteHour = -1;
    hourlyMap.forEach((count, hour) => {
      if (count > maxCount) {
        maxCount = count;
        favoriteHour = hour;
      }
    });
    
    this.statistics.favoriteReadingHour = favoriteHour;
    logger.debug(TAG, `最喜欢的阅读时段重新计算: ${favoriteHour}点`);
  }

  private recalculateLastReadTime(readHistory: ReadHistory[], ebooks: EBook[], novels: NovelBook[]): void {
    let latestTime = 0;

    readHistory.forEach((record: ReadHistory): void => {
      if (record.readTime > latestTime) {
        latestTime = record.readTime;
      }
    });

    ebooks.forEach((ebook: EBook): void => {
      if (ebook.metadata.title !== USER_MANUAL_TITLE &&
        ebook.readingProgress &&
        ebook.readingProgress.lastReadTime &&
        ebook.readingProgress.lastReadTime > latestTime) {
        latestTime = ebook.readingProgress.lastReadTime;
      }
    });

    novels.forEach((novel: NovelBook): void => {
      if (novel.name !== USER_MANUAL_TITLE &&
        novel.lastReadTime &&
        novel.lastReadTime > latestTime) {
        latestTime = novel.lastReadTime;
      }
    });

    this.statistics.lastReadTime = latestTime;
  }

  private rebuildUnifiedDailyData(readHistory: ReadHistory[], ebooks: EBook[], novels: NovelBook[], startTime: number): void {
    const rangeDailyMap = new Map<string, DailyStatData>();
    const allDailyMap = new Map<string, DailyStatData>();

    readHistory.forEach((record: ReadHistory): void => {
      this.addDailyStatRecord(allDailyMap, this.formatDateKey(record.readTime), Math.round(record.readDuration / 1000), record.chapterId, 1);
      if (record.readTime >= startTime) {
        this.addDailyStatRecord(rangeDailyMap, this.formatDateKey(record.readTime), Math.round(record.readDuration / 1000), record.chapterId, 1);
      }
    });

    for (const ebook of ebooks) {
      if (!ebook.readingProgress || !ebook.readingProgress.lastReadTime || ebook.metadata.title === USER_MANUAL_TITLE) {
        continue;
      }
      const readingSeconds = Math.round((ebook.readingProgress.totalReadingTime || 0) * 60);
      const chapterKey = `ebook-${ebook.id}`;
      const pages = this.getEstimatedEBookReadPages(ebook);
      const dateKey = this.formatDateKey(ebook.readingProgress.lastReadTime);
      this.addDailyStatRecord(allDailyMap, dateKey, readingSeconds, chapterKey, pages);
      if (ebook.readingProgress.lastReadTime >= startTime) {
        this.addDailyStatRecord(rangeDailyMap, dateKey, readingSeconds, chapterKey, pages);
      }
    }

    for (const novel of novels) {
      if (!novel.lastReadTime || novel.lastReadTime <= 0 || novel.name === USER_MANUAL_TITLE) {
        continue;
      }
      const readingSeconds = novel.totalReadingTime || 0;
      const chapterKey = `novel-${novel.id}`;
      const chapterCount = (novel.lastReadChapterIndex !== undefined && novel.lastReadChapterIndex >= 0)
        ? novel.lastReadChapterIndex + 1
        : 1;
      const dateKey = this.formatDateKey(novel.lastReadTime);
      this.addDailyStatRecord(allDailyMap, dateKey, readingSeconds, chapterKey, 0);
      if (chapterCount > 1) {
        for (let index = 1; index < chapterCount; index++) {
          const extraChapterKey = `novel-${novel.id}-${index}`;
          this.addDailyChapterOnly(allDailyMap, dateKey, extraChapterKey);
        }
      }
      if (novel.lastReadTime >= startTime) {
        this.addDailyStatRecord(rangeDailyMap, dateKey, readingSeconds, chapterKey, 0);
        if (chapterCount > 1) {
          for (let index = 1; index < chapterCount; index++) {
            const extraChapterKey = `novel-${novel.id}-${index}`;
            this.addDailyChapterOnly(rangeDailyMap, dateKey, extraChapterKey);
          }
        }
      }
    }

    this.dailyData = this.convertDailyMapToList(rangeDailyMap);
    this.allDailyData = this.convertDailyMapToList(allDailyMap);
    logger.debug(TAG, `统一每日趋势已重建: range=${this.dailyData.length}, all=${this.allDailyData.length}`);
  }

  private addDailyStatRecord(
    targetMap: Map<string, DailyStatData>,
    dateKey: string,
    readingSeconds: number,
    chapterKey: string,
    pages: number
  ): void {
    const existing = targetMap.get(dateKey);
    if (existing) {
      existing.time += Math.max(0, readingSeconds);
      existing.chapters.add(chapterKey);
      existing.pages += Math.max(0, pages);
      targetMap.set(dateKey, existing);
    } else {
      const chapters = new Set<string>();
      chapters.add(chapterKey);
      const statData: DailyStatData = {
        time: Math.max(0, readingSeconds),
        chapters: chapters,
        pages: Math.max(0, pages)
      };
      targetMap.set(dateKey, statData);
    }
  }

  private addDailyChapterOnly(targetMap: Map<string, DailyStatData>, dateKey: string, chapterKey: string): void {
    const existing = targetMap.get(dateKey);
    if (existing) {
      existing.chapters.add(chapterKey);
      targetMap.set(dateKey, existing);
    }
  }

  private convertDailyMapToList(sourceMap: Map<string, DailyStatData>): DailyReadingData[] {
    const result: DailyReadingData[] = [];
    sourceMap.forEach((value: DailyStatData, dateKey: string): void => {
      const item: DailyReadingData = {
        date: dateKey,
        readingTime: value.time,
        chaptersRead: value.chapters.size,
        pagesRead: value.pages
      };
      result.push(item);
    });
    result.sort((a: DailyReadingData, b: DailyReadingData): number => b.date.localeCompare(a.date));
    return result;
  }

  private getEstimatedEBookReadPages(ebook: EBook): number {
    if (!ebook.readingProgress) {
      return 0;
    }
    const estimatedTotalPages = ebook.chapters.length * 10;
    const readPages = Math.round(estimatedTotalPages * (ebook.readingProgress.progress / 100));
    return Math.max(1, readPages);
  }

  /**
   * 加载阅读时长排行
   */
  private async loadReadingRank(readHistory: ReadHistory[], ebooks: EBook[] = []): Promise<void> {
    try {
      const rankList: ReadingRankItem[] = [];
      
      // 按漫画ID统计阅读时长（readDuration 是毫秒）
      const readingTimeMap = new Map<string, number>();
      readHistory.forEach(record => {
        const currentTime = readingTimeMap.get(record.comicId) || 0;
        readingTimeMap.set(record.comicId, currentTime + Math.round(record.readDuration / 1000));  // 毫秒转秒
      });

      // 获取漫画详细信息
      const mangaEntries = Array.from(readingTimeMap.entries());
      const mangaComicIds: string[] = [];
      for (const entry of mangaEntries) {
        mangaComicIds.push(entry[0]);
      }
      const comicInfoMap: Map<string, ComicInfo> = await this.dataManager.getComicsByIds(mangaComicIds);
      for (const entry of mangaEntries) {
        const comicId: string = entry[0];
        const readingTime: number = entry[1];

        const comic: ComicInfo | undefined = comicInfoMap.get(comicId);
        if (comic) {
          // 过滤使用手册
          if (comic.title === USER_MANUAL_TITLE) {
            continue;
          }
          const coverPath: string = comic.coverLocalPath || comic.coverUrl || '';
          const rankItem: ReadingRankItem = {
            id: comicId,
            title: comic.title,
            coverPath: coverPath,
            readingTime: readingTime,
            type: 'manga'
          };
          rankList.push(rankItem);
        } else {
          logger.warn(TAG, `无法找到漫画信息: ${comicId}`);
        }
      }

      // 添加电子书到排行（电子书的 totalReadingTime 是分钟，需要转换为秒）
      for (const ebook of ebooks) {
        if (ebook.readingProgress && ebook.readingProgress.totalReadingTime > 0) {
          // 过滤使用手册
          if (ebook.metadata.title === USER_MANUAL_TITLE) {
            continue;
          }
          const rankItem: ReadingRankItem = {
            id: ebook.id,
            title: ebook.metadata.title,
            coverPath: ebook.metadata.coverImagePath || '',
            readingTime: Math.round(ebook.readingProgress.totalReadingTime * 60),  // 分钟转秒
            type: 'ebook'
          };
          rankList.push(rankItem);
        }
      }
      
      // 添加小说到排行（包括在线小说）
      try {
        const novelDataManager = getNovelDataManager();
        const novelsWithTime = await novelDataManager.getBooksWithReadingTime();
        
        for (const novel of novelsWithTime) {
          if (novel.totalReadingTime && novel.totalReadingTime > 0) {
            // 过滤使用手册
            if (novel.name === USER_MANUAL_TITLE) {
              continue;
            }
            const rankItem: ReadingRankItem = {
              id: novel.id,
              title: novel.name,
              coverPath: novel.coverUrl || '',
              readingTime: novel.totalReadingTime,  // 小说的totalReadingTime是秒
              type: 'novel'
            };
            rankList.push(rankItem);
          }
        }
      } catch (e) {
        logger.warn(TAG, `加载小说排行数据失败: ${String(e)}`);
      }

      // 按阅读时长排序并取前10名
      rankList.sort((a, b) => b.readingTime - a.readingTime);
      this.readingRankList = rankList.slice(0, 10);
      
      logger.info(TAG, `阅读时长排行加载完成，共 ${this.readingRankList.length} 项`);
    } catch (error) {
      logger.error(TAG, `加载阅读时长排行失败: ${String(error)}`);
    }
  }

  /**
   * 分析用户兴趣
   */
  private async analyzeUserInterests(): Promise<void> {
    try {
      const keywordMap = new Map<string, KeywordStatData>();

      // 获取所有漫画
      const comics: ComicInfo[] = await this.dataManager.getAllComics();
      for (const comic of comics) {
        // 分析标签 - ComicInfo.tags 是 string[]
        if (comic.tags && comic.tags.length > 0) {
          for (const tag of comic.tags) {
            const trimmedTag: string = tag.trim();
            if (trimmedTag.length > 0) {
              const existing: KeywordStatData | undefined = keywordMap.get(trimmedTag);
              if (existing) {
                existing.count++;
              } else {
                const newData: KeywordStatData = { count: 1, type: 'tag' };
                keywordMap.set(trimmedTag, newData);
              }
            }
          }
        }
        
        // 分析作者
        if (comic.author && comic.author.trim().length > 0) {
          const existing: KeywordStatData | undefined = keywordMap.get(comic.author);
          if (existing) {
            existing.count++;
          } else {
            const newData: KeywordStatData = { count: 1, type: 'author' };
            keywordMap.set(comic.author, newData);
          }
        }

        // 分析标题关键词（简单分词）
        const titleWords: string[] = this.extractKeywords(comic.title);
        for (const word of titleWords) {
          const existing: KeywordStatData | undefined = keywordMap.get(word);
          if (existing) {
            existing.count++;
          } else {
            const newData: KeywordStatData = { count: 1, type: 'title' };
            keywordMap.set(word, newData);
          }
        }
      }

      // 注意：EBookDataManager 没有 getAllEBooks 方法，跳过电子书分析
      // 如果需要，可以后续添加该方法

      // 转换为数组并排序
      const interestEntries = Array.from(keywordMap.entries());
      interestEntries.sort((a, b) => b[1].count - a[1].count);

      // 取前15个
      const resultItems: InterestItem[] = [];
      const slicedEntries = interestEntries.slice(0, 15);
      for (const entry of slicedEntries) {
        const item: InterestItem = {
          keyword: entry[0],
          count: entry[1].count,
          type: entry[1].type
        };
        resultItems.push(item);
      }
      this.interestItems = resultItems;

      logger.info(TAG, `兴趣分析完成，共 ${this.interestItems.length} 个关键词`);
    } catch (error) {
      logger.error(TAG, `分析用户兴趣失败: ${String(error)}`);
    }
  }

  /**
   * 从标题中提取关键词
   */
  private extractKeywords(title: string): string[] {
    // 简单分词：按空格、标点符号分割，过滤短词
    const words = title.split(/[\s,，。、！？·\-_\[\]【】()（）]+/);
    return words.filter(word => word.length >= 2 && word.length <= 10);
  }

  /**
   * 切换时间范围
   */
  private changeTimeRange(days: number): void {
    if (this.selectedTimeRange === days) {
      return;
    }
    this.selectedTimeRange = days;
    logger.info(TAG, `切换时间范围到: ${days}天`);
    this.loadReadingData().catch((error: Error) => {
      logger.error(TAG, '重新加载数据失败', error.message);
    });
  }

  /**
   * 循环切换时间范围（7天 -> 30天 -> 全部 -> 7天）
   */
  private cycleTimeRange(): void {
    if (this.selectedTimeRange === 7) {
      this.changeTimeRange(30);
    } else if (this.selectedTimeRange === 30) {
      this.changeTimeRange(365);
    } else {
      this.changeTimeRange(7);
    }
  }

  /**
   * 获取当前时间范围对应的图标
   */
  private getTimeRangeIcon(): Resource {
    if (this.selectedTimeRange === 7) {
      return $r('sys.symbol.calendar_07_a');
    } else if (this.selectedTimeRange === 30) {
      return $r('sys.symbol.calendar_30_a');
    } else {
      return $r('sys.symbol.calendar_1');
    }
  }

  /**
   * 获取当前时间范围对应的标题
   */
  private getTimeRangeTitle(): string {
    if (this.selectedTimeRange === 7) {
      return '最近7天阅读统计';
    } else if (this.selectedTimeRange === 30) {
      return '最近30天阅读统计';
    } else {
      return '全部阅读统计';
    }
  }

  /**
   * 获取时间范围切换按钮的文本
   */
  private getTimeRangeButtonText(): string {
    if (this.selectedTimeRange === 7) {
      return '7天';
    } else if (this.selectedTimeRange === 30) {
      return '30天';
    } else {
      return '全部';
    }
  }

  /**
   * 显示保留天数选择器
   */
  private showRetentionDaysPicker(): void {
    this.showRetentionPicker = true;
  }

  /**
   * 处理保留天数选择
   */
  private async handleRetentionDaysChange(index: number): Promise<void> {
    this.retentionDaysIndex = index;
    await this.analyticsManager.setRetentionDaysByIndex(index);
    this.selectedTimeRange = RETENTION_DAYS_OPTIONS[index];
    this.showRetentionPicker = false;
    
    // 重新加载数据
    await this.loadReadingData();
  }

  /**
   * 导航到作品详情页（根据设置选择详情页类型）
   */
  private navigateToDetail(item: ReadingRankItem): void {
    try {
      if (item.type === 'manga') {
        this.openMangaDetail(item.id, item.title, item.coverPath);
      } else if (item.type === 'ebook') {
        this.openEBookDetail(item.id, item.title, item.coverPath);
      } else if (item.type === 'novel') {
        // 小说需要sourceId，但排行榜中没有，使用空字符串
        this.openNovelDetail(item.id, '', item.title, '', item.coverPath);
      }
    } catch (error) {
      logger.error(TAG, `导航到详情页失败: ${String(error)}`);
    }
  }

  /**
   * 打开漫画详情页（根据设置选择详情页类型）
   */
  private openMangaDetail(mangaId: string, title: string, coverPath: string): void {
    const pageType = PageSettingsHelper.getMangaDetailPageType();
    
    if (pageType === DetailPageType.UNIFIED) {
      // 使用统一详情页
      const unifiedParams: UnifiedDetailPageParams = {
        contentType: UnifiedContentType.MANGA,
        contentId: mangaId,
        cachedTitle: title,
        cachedCoverPath: this.getUnifiedDetailCachedCoverPath(coverPath),
        cachedCover: coverPath
      };
      this.pathStack.pushPathByName('UnifiedDetailPage', unifiedParams);
      logger.info(TAG, `打开统一详情页(漫画): ${title}`);
    } else {
      // 使用原有漫画详情页
      const params: MangaDetailPageParams = { mangaId: mangaId };
      this.pathStack.pushPathByName('MangaDetailPage', params);
      logger.info(TAG, `打开漫画详情页: ${title}`);
    }
  }

  /**
   * 打开电子书详情页（根据设置选择详情页类型）
   */
  private openEBookDetail(ebookId: string, title: string, coverPath: string): void {
    const pageType = PageSettingsHelper.getEBookDetailPageType();
    
    if (pageType === DetailPageType.UNIFIED) {
      // 使用统一详情页
      const unifiedParams: UnifiedDetailPageParams = {
        contentType: UnifiedContentType.EBOOK,
        contentId: ebookId,
        cachedTitle: title,
        cachedCoverPath: this.getUnifiedDetailCachedCoverPath(coverPath),
        cachedCover: coverPath
      };
      this.pathStack.pushPathByName('UnifiedDetailPage', unifiedParams);
      logger.info(TAG, `打开统一详情页(电子书): ${title}`);
    } else {
      // 使用原有电子书详情页
      const params: EBookDetailPageParams = { bookId: ebookId };
      this.pathStack.pushPathByName('EBookDetailPage', params);
      logger.info(TAG, `打开电子书详情页: ${title}`);
    }
  }

  /**
   * 打开小说详情页（根据设置选择详情页类型）
   * @param bookUrl 小说URL（用于 contentId）
   * @param sourceId 书源ID
   * @param title 小说标题
   * @param author 作者
   * @param coverPath 封面路径
   */
  private openNovelDetail(bookUrl: string, sourceId: string, title: string, author: string, coverPath: string): void {
    // 添加调试日志
    logger.debug(TAG, `openNovelDetail: bookUrl=${bookUrl}, sourceId=${sourceId}`);
    
    const pageType = PageSettingsHelper.getNovelDetailPageType();
    
    if (pageType === DetailPageType.UNIFIED) {
      // 使用统一详情页
      const unifiedParams: UnifiedDetailPageParams = {
        contentType: UnifiedContentType.NOVEL,
        contentId: bookUrl,
        sourceId: sourceId,
        cachedTitle: title,
        cachedCoverPath: this.getUnifiedDetailCachedCoverPath(coverPath),
        cachedCover: coverPath,
        cachedAuthor: author
      };
      this.pathStack.pushPathByName('UnifiedDetailPage', unifiedParams);
      logger.info(TAG, `打开统一详情页(小说): ${title}`);
    } else {
      // 使用原有小说详情页
      const params: NovelDetailPageParams = {
        sourceId: sourceId,
        bookUrl: bookUrl,
        bookName: title,
        author: author,
        coverUrl: coverPath
      };
      this.pathStack.pushPathByName('NovelDetailPage', params);
      logger.info(TAG, `打开小说详情页: ${title}`);
    }
  }

  private goBack(): void {
    try {
      this.pathStack.pop();
    } catch (error) {
      logger.error(TAG, '返回失败', String(error));
    }
  }

  private getUnifiedDetailCachedCoverPath(coverPath: string): string | undefined {
    const normalizedPath: string = coverPath.trim();
    if (normalizedPath.length <= 0) {
      return undefined;
    }
    if (normalizedPath.startsWith('http://') || normalizedPath.startsWith('https://')) {
      return undefined;
    }
    if (normalizedPath.startsWith('app.media.') || normalizedPath.startsWith('$r(')) {
      return undefined;
    }
    if (normalizedPath.startsWith('/') || normalizedPath.startsWith('file://')) {
      return normalizedPath;
    }
    return undefined;
  }

  /**
   * 规范化封面路径：本地文件添加 file:// 前缀，资源文件返回 Resource 类型
   * @param path 封面路径
   * @param isEBook 是否为电子书（电子书无封面时使用默认电子书图标）
   */
  private normalizeCoverPath(path: string, isEBook: boolean = false): string | Resource | image.PixelMap {
    if (!path || path.length === 0) {
      // 电子书无封面时使用默认电子书图标
      if (isEBook) {
        return $r('app.media.ebook');
      }
      return '';
    }
    
    // 检查是否有预加载的PixelMap（用于AVIF等特殊格式）
    if (path.startsWith('http://') || path.startsWith('https://')) {
      const coverManager = getCoverImageManager();
      const cachedPixelMap = coverManager.getCachedPixelMap(path);
      if (cachedPixelMap) {
        return cachedPixelMap;
      }
    }
    
    // 如果是资源路径（app.media.xxx 格式），转换为 $r() 格式
    if (path.startsWith('app.media.')) {
      return $r(path);
    }
    // 如果是本地路径（以 / 开头），添加 file:// 前缀
    if (path.startsWith('/')) {
      return `file://${path}`;
    }
    return path;
  }

  /**
   * 格式化时长（输入为秒）
   */
  private formatDuration(seconds: number): string {
    if (seconds < 60) {
      return `${seconds}秒`;
    }
    const minutes = Math.floor(seconds / 60);
    const remainingSeconds = seconds % 60;
    if (minutes < 60) {
      if (remainingSeconds === 0) {
        return `${minutes}分钟`;
      }
      return `${minutes}分${remainingSeconds}秒`;
    }
    const hours = Math.floor(minutes / 60);
    const remainingMinutes = minutes % 60;
    if (remainingMinutes === 0) {
      return `${hours}小时`;
    }
    return `${hours}小时${remainingMinutes}分钟`;
  }

  /**
   * 格式化日期
   */
  private formatDate(timestamp: number): string {
    const date = new Date(timestamp);
    const now = new Date();
    const diffMs = now.getTime() - date.getTime();
    const diffDays = Math.floor(diffMs / (24 * 60 * 60 * 1000));

    if (diffDays === 0) {
      return '今天';
    } else if (diffDays === 1) {
      return '昨天';
    } else if (diffDays < 7) {
      return `${diffDays}天前`;
    } else {
      return `${date.getFullYear()}-${String(date.getMonth() + 1).padStart(2, '0')}-${String(date.getDate()).padStart(2, '0')}`;
    }
  }

  private formatDateKey(timestamp: number): string {
    const date = new Date(timestamp);
    return `${date.getFullYear()}-${String(date.getMonth() + 1).padStart(2, '0')}-${String(date.getDate()).padStart(2, '0')}`;
  }

  private formatPercent(value: number): string {
    if (value <= 0) {
      return '0%';
    }
    const percent = Math.round(value * 100);
    if (percent < 1) {
      return '<1%';
    }
    return `${percent}%`;
  }

  private getSafePercentWidth(value: number): string {
    if (value <= 0) {
      return '0%';
    }
    const percent = Math.max(4, Math.round(value * 100));
    return `${Math.min(percent, 100)}%`;
  }

  private getLongTermMangaReadingTime(): number {
    return Math.max(
      0,
      this.statistics.totalReadingTime -
        this.statistics.totalEBookReadingTime -
        this.statistics.totalNovelReadingTime
    );
  }

  private getContentMixSymbol(kind: ContentMixKind): Resource {
    switch (kind) {
      case ContentMixKind.MANGA:
        return $r('sys.symbol.picture');
      case ContentMixKind.EBOOK:
        return $r('sys.symbol.book');
      case ContentMixKind.NOVEL:
        return $r('sys.symbol.doc_text');
      default:
        return $r('sys.symbol.circle');
    }
  }

  private getContentMixAccentColor(kind: ContentMixKind): ResourceColor {
    switch (kind) {
      case ContentMixKind.MANGA:
        return ThemeAwareHelper.getTestManagementThemedColor('accent_blue', this.themeState.currentTheme);
      case ContentMixKind.EBOOK:
        return ThemeAwareHelper.getTestManagementThemedColor('accent_orange', this.themeState.currentTheme);
      case ContentMixKind.NOVEL:
        return ThemeAwareHelper.getTestManagementThemedColor('accent_green', this.themeState.currentTheme);
      default:
        return ThemeAwareHelper.getTestManagementThemedColor('accent_primary', this.themeState.currentTheme);
    }
  }

  private createContentMixSegment(
    kind: ContentMixKind,
    label: string,
    valueSeconds: number,
    itemCount: number,
    totalSeconds: number
  ): ContentMixSegment {
    const safeValue = Math.max(0, valueSeconds);
    const percent = totalSeconds > 0 ? safeValue / totalSeconds : 0;
    const segment: ContentMixSegment = {
      kind: kind,
      label: label,
      valueSeconds: safeValue,
      itemCount: Math.max(0, itemCount),
      percent: percent,
      symbol: this.getContentMixSymbol(kind),
      accentColor: this.getContentMixAccentColor(kind)
    };
    return segment;
  }

  private getLongTermContentMixSegments(): ContentMixSegment[] {
    const mangaSeconds = this.getLongTermMangaReadingTime();
    const totalSeconds = mangaSeconds + this.statistics.totalEBookReadingTime + this.statistics.totalNovelReadingTime;
    const segments: ContentMixSegment[] = [];
    segments.push(this.createContentMixSegment(
      ContentMixKind.MANGA,
      '漫画',
      mangaSeconds,
      this.statistics.totalComicsRead,
      totalSeconds
    ));
    segments.push(this.createContentMixSegment(
      ContentMixKind.EBOOK,
      '电子书',
      this.statistics.totalEBookReadingTime,
      this.statistics.totalEBooksRead,
      totalSeconds
    ));
    segments.push(this.createContentMixSegment(
      ContentMixKind.NOVEL,
      '小说',
      this.statistics.totalNovelReadingTime,
      this.statistics.totalNovelsRead,
      totalSeconds
    ));
    return segments.filter((segment: ContentMixSegment): boolean => {
      return segment.valueSeconds > 0 || segment.itemCount > 0;
    });
  }

  private getDailyContentMixSegments(): ContentMixSegment[] {
    let mangaSeconds = 0;
    let ebookSeconds = 0;
    let novelSeconds = 0;
    this.dailyMangaList.forEach((item: DailyMangaItem): void => {
      mangaSeconds += item.readingTime;
    });
    this.dailyEBookList.forEach((item: DailyEBookItem): void => {
      ebookSeconds += item.readingTime;
    });
    this.dailyNovelList.forEach((item: DailyNovelItem): void => {
      novelSeconds += item.readingTime;
    });

    const totalSeconds = mangaSeconds + ebookSeconds + novelSeconds;
    const segments: ContentMixSegment[] = [];
    segments.push(this.createContentMixSegment(
      ContentMixKind.MANGA,
      '漫画',
      mangaSeconds,
      this.dailyMangaList.length,
      totalSeconds
    ));
    segments.push(this.createContentMixSegment(
      ContentMixKind.EBOOK,
      '电子书',
      ebookSeconds,
      this.dailyEBookList.length,
      totalSeconds
    ));
    segments.push(this.createContentMixSegment(
      ContentMixKind.NOVEL,
      '小说',
      novelSeconds,
      this.dailyNovelList.length,
      totalSeconds
    ));
    return segments.filter((segment: ContentMixSegment): boolean => {
      return segment.valueSeconds > 0 || segment.itemCount > 0;
    });
  }

  private getDominantContentSegment(segments: ContentMixSegment[]): ContentMixSegment | null {
    let dominant: ContentMixSegment | null = null;
    for (const segment of segments) {
      if (dominant === null || segment.valueSeconds > dominant.valueSeconds) {
        dominant = segment;
      }
    }
    return dominant;
  }

  private getTopReadingRankItem(): ReadingRankItem | null {
    for (const item of this.readingRankList) {
      return item;
    }
    return null;
  }

  private getPeakReadingHourText(): string {
    if (this.statistics.favoriteReadingHour < 0) {
      return '暂无';
    }
    return `${this.statistics.favoriteReadingHour}:00`;
  }

  private getInspirationDensityText(): string {
    if (this.statistics.totalReadingTime <= 0 || this.inspirationStats.totalCount <= 0) {
      return '暂无';
    }
    const hours = this.statistics.totalReadingTime / 3600;
    if (hours <= 0) {
      return '暂无';
    }
    const density = Math.round((this.inspirationStats.totalCount / hours) * 10) / 10;
    return `${density}条/小时`;
  }

  private getReadingInsights(): ReadingInsightItem[] {
    const insights: ReadingInsightItem[] = [];
    const dominant = this.getDominantContentSegment(this.getLongTermContentMixSegments());
    if (dominant) {
      const dominantInsight: ReadingInsightItem = {
        title: '主阅读类型',
        value: dominant.label,
        detail: `${this.formatPercent(dominant.percent)}时长来自${dominant.label}`,
        symbol: dominant.symbol,
        accentColor: dominant.accentColor
      };
      insights.push(dominantInsight);
    }

    const cadenceInsight: ReadingInsightItem = {
      title: '当前节奏',
      value: this.formatDuration(this.statistics.averageReadingTime),
      detail: `${this.getTimeRangeButtonText()}日均阅读时长`,
      symbol: $r('sys.symbol.calendar_badge_clock'),
      accentColor: ThemeAwareHelper.getTestManagementThemedColor('accent_primary', this.themeState.currentTheme)
    };
    insights.push(cadenceInsight);

    const streakInsight: ReadingInsightItem = {
      title: '连续阅读',
      value: `${this.statistics.continuousReadingDays}天`,
      detail: this.statistics.lastReadTime > 0 ? `最近一次 ${this.formatDate(this.statistics.lastReadTime)}` : '还没有最近阅读记录',
      symbol: $r('sys.symbol.star'),
      accentColor: ThemeAwareHelper.getTestManagementThemedColor('accent_orange', this.themeState.currentTheme)
    };
    insights.push(streakInsight);

    const densityInsight: ReadingInsightItem = {
      title: '灵感密度',
      value: this.getInspirationDensityText(),
      detail: `共记录${this.inspirationStats.totalCount}条灵感`,
      symbol: $r('sys.symbol.lightbulb'),
      accentColor: ThemeAwareHelper.getTestManagementThemedColor('accent_green', this.themeState.currentTheme)
    };
    insights.push(densityInsight);

    const topItem = this.getTopReadingRankItem();
    if (topItem) {
      const topInsight: ReadingInsightItem = {
        title: '最投入作品',
        value: topItem.title,
        detail: `累计${this.formatDuration(topItem.readingTime)}`,
        symbol: this.getContentMixSymbol(topItem.type === 'manga' ? ContentMixKind.MANGA :
          (topItem.type === 'ebook' ? ContentMixKind.EBOOK : ContentMixKind.NOVEL)),
        accentColor: ThemeAwareHelper.getTestManagementThemedColor('accent_blue', this.themeState.currentTheme)
      };
      insights.push(topInsight);
    }

    const peakInsight: ReadingInsightItem = {
      title: '高峰时段',
      value: this.getPeakReadingHourText(),
      detail: this.statistics.favoriteReadingHour >= 0 ? '最常开始阅读的时间' : '积累更多记录后显示',
      symbol: $r('sys.symbol.clock'),
      accentColor: ThemeAwareHelper.getTestManagementThemedColor('accent_secondary', this.themeState.currentTheme)
    };
    insights.push(peakInsight);

    return insights.slice(0, 6);
  }

  private getTrendDateLabel(date: string): string {
    if (date.length >= 10) {
      return `${date.substring(5, 7)}/${date.substring(8, 10)}`;
    }
    return date;
  }

  private getRecentTrendBars(limit: number): ReadingTrendBar[] {
    const source = this.dailyData.slice(0, limit);
    let maxReadingTime = 0;
    source.forEach((data: DailyReadingData): void => {
      if (data.readingTime > maxReadingTime) {
        maxReadingTime = data.readingTime;
      }
    });

    const result: ReadingTrendBar[] = [];
    source.reverse();
    for (const data of source) {
      const percent = maxReadingTime > 0 ? data.readingTime / maxReadingTime : 0;
      const bar: ReadingTrendBar = {
        date: data.date,
        label: this.getTrendDateLabel(data.date),
        readingTime: data.readingTime,
        chaptersRead: data.chaptersRead,
        pagesRead: data.pagesRead,
        percent: percent
      };
      result.push(bar);
    }
    return result;
  }

  /**
   * 构建日视图月历选择器
   */
  @Builder
  buildMonthCalendar() {
    Column({ space: 12 }) {
      // 月份导航
      Row() {
        Button({ stateEffect: true }) {
          SymbolGlyph($r('sys.symbol.chevron_left'))
            .fontSize(18)
            .fontColor([ThemeAwareHelper.getTestManagementThemedColor('text_primary', this.themeState.currentTheme)])
        }
        .width(40)
        .height(40)
        .backgroundColor(Color.Transparent)
        .onClick(() => this.previousMonth())

        Text(`${this.currentMonth.getFullYear()}年${this.currentMonth.getMonth() + 1}月`)
          .fontSize(16)
          .fontWeight(FontWeight.Medium)
          .fontFamily(this.appFontFamily)
          .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_primary', this.themeState.currentTheme))
          .layoutWeight(1)
          .textAlign(TextAlign.Center)

        Button({ stateEffect: true }) {
          SymbolGlyph($r('sys.symbol.chevron_right'))
            .fontSize(18)
            .fontColor([ThemeAwareHelper.getTestManagementThemedColor('text_primary', this.themeState.currentTheme)])
        }
        .width(40)
        .height(40)
        .backgroundColor(Color.Transparent)
        .onClick(() => this.nextMonth())
      }
      .width('100%')
      .padding({ left: 8, right: 8 })

      // 星期标题
      Row() {
        ForEach(['日', '一', '二', '三', '四', '五', '六'], (day: string) => {
          Text(day)
            .fontSize(12)
            .fontFamily(this.appFontFamily)
            .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_secondary', this.themeState.currentTheme))
            .width('14.28%')
            .textAlign(TextAlign.Center)
        })
      }
      .width('100%')

      // 日期网格
      this.buildCalendarGrid()
    }
    .width('100%')
    .padding(16)
    .backgroundColor(this.getBlurPanelBackground())
    .linearGradient(this.getBlurPanelSurfaceGradient())
    .backgroundBlurStyle(this.getBlurPanelBlurStyle(), this.getBlurPanelBlurOptions())
    .backgroundEffect(this.getBlurPanelBackgroundEffect())
    .borderRadius(this.getBlurPanelRadius())
    .clip(true)
    .shadow({ radius: this.getBlurPanelRadius() + 2, color: this.getBlurPanelShadowColor(), offsetX: 0, offsetY: 4 })
    .border({ width: this.getBlurPanelBorderWidth(), color: this.getBlurPanelBorder() })
    .margin({ left: this.getAnalyticsSectionHorizontalMargin(), right: this.getAnalyticsSectionHorizontalMargin() })
  }

  /**
   * 获取日历网格数据
   */
  private getCalendarGridData(): number[][] {
    const year = this.currentMonth.getFullYear();
    const month = this.currentMonth.getMonth();
    const daysInMonth = this.getDaysInMonth(year, month);
    const firstDayOfWeek = this.getFirstDayOfMonth(year, month);
    
    const totalCells = firstDayOfWeek + daysInMonth;
    const rows = Math.ceil(totalCells / 7);
    
    const gridData: number[][] = [];
    for (let row = 0; row < rows; row++) {
      const rowData: number[] = [];
      for (let col = 0; col < 7; col++) {
        const cellIndex = row * 7 + col;
        const dayNumber = cellIndex - firstDayOfWeek + 1;
        if (dayNumber >= 1 && dayNumber <= daysInMonth) {
          rowData.push(dayNumber);
        } else {
          rowData.push(0); // 0 表示空白
        }
      }
      gridData.push(rowData);
    }
    return gridData;
  }

  /**
   * 构建日历网格
   */
  @Builder
  buildCalendarGrid() {
    Column({ space: 4 }) {
      ForEach(this.getCalendarGridData(), (rowData: number[], rowIndex: number) => {
        Row() {
          ForEach(rowData, (dayNumber: number, colIndex: number) => {
            if (dayNumber > 0) {
              this.buildCalendarCell(dayNumber)
            } else {
              // 空白单元格
              Column()
                .width('14.28%')
                .height(38)
            }
          })
        }
        .width('100%')
      })
    }
    .width('100%')
  }

  /**
   * 构建日历单元格
   */
  @Builder
  buildCalendarCell(dayNumber: number) {
    Column() {
      // 日期圆点
      Stack() {
        // 背景圆
        if (this.isSelectedDay(dayNumber)) {
          Circle()
            .width(32)
            .height(32)
            .fill(ThemeAwareHelper.getTestManagementThemedColor('accent_blue', this.themeState.currentTheme))
        }
        
        // 日期数字
        Text(`${dayNumber}`)
          .fontSize(12)
          .fontFamily(this.appFontFamily)
          .fontColor(this.getDayTextColor(dayNumber))
          .fontWeight(this.isTodayDay(dayNumber) ? FontWeight.Bold : FontWeight.Normal)
      }
      .width(32)
      .height(32)
      .alignContent(Alignment.Center)
      
      // 有数据指示点
      if (this.hasDayData(dayNumber) && !this.isSelectedDay(dayNumber)) {
        Circle()
          .width(4)
          .height(4)
          .fill(ThemeAwareHelper.getTestManagementThemedColor('accent_blue', this.themeState.currentTheme))
          .margin({ top: 2 })
      } else {
        Blank().height(6)
      }
    }
    .width('14.28%')
    .alignItems(HorizontalAlign.Center)
    .onClick(() => {
      const year = this.currentMonth.getFullYear();
      const month = this.currentMonth.getMonth();
      this.selectDate(new Date(year, month, dayNumber));
    })
  }

  /**
   * 检查是否是选中的日期（基于日期数字）
   */
  private isSelectedDay(dayNumber: number): boolean {
    const year = this.currentMonth.getFullYear();
    const month = this.currentMonth.getMonth();
    return this.selectedDate.getFullYear() === year &&
           this.selectedDate.getMonth() === month &&
           this.selectedDate.getDate() === dayNumber;
  }

  /**
   * 检查是否是今天（基于日期数字）
   */
  private isTodayDay(dayNumber: number): boolean {
    const today = new Date();
    const year = this.currentMonth.getFullYear();
    const month = this.currentMonth.getMonth();
    return today.getFullYear() === year &&
           today.getMonth() === month &&
           today.getDate() === dayNumber;
  }

  /**
   * 检查某天是否有阅读数据（基于日期数字）
   */
  private hasDayData(dayNumber: number): boolean {
    const year = this.currentMonth.getFullYear();
    const month = this.currentMonth.getMonth();
    const dateKey = `${year}-${String(month + 1).padStart(2, '0')}-${String(dayNumber).padStart(2, '0')}`;
    return this.allDailyData.some(d => d.date === dateKey && d.readingTime > 0);
  }

  /**
   * 获取日期文字颜色
   */
  private getDayTextColor(dayNumber: number): ResourceColor {
    if (this.isSelectedDay(dayNumber)) {
      return ThemeAwareHelper.getTestManagementThemedColor('text_white', this.themeState.currentTheme);
    } else if (this.isTodayDay(dayNumber)) {
      return ThemeAwareHelper.getTestManagementThemedColor('accent_blue', this.themeState.currentTheme);
    } else {
      return ThemeAwareHelper.getTestManagementThemedColor('text_primary', this.themeState.currentTheme);
    }
  }

  /**
   * 构建日视图内容
   */
  @Builder
  buildDailyViewContent() {
    Column({ space: this.getAnalyticsSectionGap() }) {
      // 月历选择器
      this.buildMonthCalendar()
      
      // 阅读目标进度
      this.buildReadingGoalsProgress()
      
      // 当天阅读统计
      Column({ space: 12 }) {
        this.buildAnalyticsSectionHeader($r('sys.symbol.calendar_badge_clock'), `${this.selectedDate.getMonth() + 1}月${this.selectedDate.getDate()}日 阅读情况`)
        
        if (this.isDailyLoading) {
          // 加载中效果
          Column({ space: 8 }) {
            LoadingProgress()
              .width(40)
              .height(40)
              .color(ThemeAwareHelper.getTestManagementThemedColor('accent_primary', this.themeState.currentTheme))
            Text('加载中...')
              .fontSize(14)
              .fontFamily(this.appFontFamily)
              .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_secondary', this.themeState.currentTheme))
          }
          .width('100%')
          .padding(32)
          .alignItems(HorizontalAlign.Center)
        } else if (this.dailyViewData && this.dailyViewData.readingTime > 0) {
          // 有阅读数据
          Row({ space: 16 }) {
            // 阅读时长
            Column({ space: 4 }) {
              SymbolGlyph($r('sys.symbol.clock'))
                .fontSize(24)
                .fontColor([ThemeAwareHelper.getTestManagementThemedColor('accent_primary', this.themeState.currentTheme)])
              Text(this.formatDuration(this.dailyViewData.readingTime))
                .fontSize(18)
                .fontWeight(FontWeight.Bold)
                .fontFamily(this.appFontFamily)
                .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_primary', this.themeState.currentTheme))
              Text('阅读时长')
                .fontSize(12)
                .fontFamily(this.appFontFamily)
                .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_secondary', this.themeState.currentTheme))
            }
            .layoutWeight(1)
            .alignItems(HorizontalAlign.Center)
            .padding(12)
            .backgroundColor(this.getAnalyticsSubPanelBackground())
            .borderRadius(this.getAnalyticsInnerRadius())
            .border({ width: this.getBlurPanelBorderWidth(), color: this.getBlurPanelBorder() })
            
            // 阅读章节
            Column({ space: 4 }) {
              SymbolGlyph($r('sys.symbol.book'))
                .fontSize(24)
                .fontColor([ThemeAwareHelper.getTestManagementThemedColor('accent_primary', this.themeState.currentTheme)])
              Text(`${this.dailyViewData.chaptersRead}`)
                .fontSize(18)
                .fontWeight(FontWeight.Bold)
                .fontFamily(this.appFontFamily)
                .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_primary', this.themeState.currentTheme))
              Text('阅读章节')
                .fontSize(12)
                .fontFamily(this.appFontFamily)
                .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_secondary', this.themeState.currentTheme))
            }
            .layoutWeight(1)
            .alignItems(HorizontalAlign.Center)
            .padding(12)
            .backgroundColor(this.getAnalyticsSubPanelBackground())
            .borderRadius(this.getAnalyticsInnerRadius())
            .border({ width: this.getBlurPanelBorderWidth(), color: this.getBlurPanelBorder() })
            
            // 阅读页数
            // Column({ space: 4 }) {
            //   Text('📄')
            //     .fontSize(24)
            //   Text(`${this.dailyViewData.pagesRead}`)
            //     .fontSize(18)
            //     .fontWeight(FontWeight.Bold)
            //     .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_primary', this.themeState.currentTheme))
            //   Text('阅读页数')
            //     .fontSize(12)
            //     .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_secondary', this.themeState.currentTheme))
            // }
            // .layoutWeight(1)
            // .alignItems(HorizontalAlign.Center)
          }
          .width('100%')
          .padding(16)
        } else {
          // 无阅读数据
          Column({ space: 8 }) {
            SymbolGlyph($r('sys.symbol.book'))
              .fontSize(48)
              .fontColor([ThemeAwareHelper.getTestManagementThemedColor('text_tertiary', this.themeState.currentTheme)])
            Text('当天没有阅读记录')
              .fontSize(14)
              .fontFamily(this.appFontFamily)
              .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_secondary', this.themeState.currentTheme))
          }
          .width('100%')
          .padding(32)
          .alignItems(HorizontalAlign.Center)
        }
      }
      .width('100%')
      .padding(16)
      .backgroundColor(this.getBlurPanelBackground())
      .linearGradient(this.getBlurPanelSurfaceGradient())
      .backgroundBlurStyle(this.getBlurPanelBlurStyle(), this.getBlurPanelBlurOptions())
      .backgroundEffect(this.getBlurPanelBackgroundEffect())
      .borderRadius(this.getBlurPanelRadius())
      .clip(true)
      .shadow({ radius: this.getBlurPanelRadius() + 2, color: this.getBlurPanelShadowColor(), offsetX: 0, offsetY: 4 })
      .border({ width: this.getBlurPanelBorderWidth(), color: this.getBlurPanelBorder() })
      .margin({ left: this.getAnalyticsSectionHorizontalMargin(), right: this.getAnalyticsSectionHorizontalMargin() })

      this.buildContentMixSection(this.getDailyContentMixSegments(), '当天内容构成')

      this.buildDailyInspirationSection()
      
      // 当天阅读的漫画列表
      if (this.dailyMangaList.length > 0) {
        Column({ space: 12 }) {
          this.buildAnalyticsSectionHeader($r('sys.symbol.picture'), '阅读的漫画')
          
          ForEach(this.dailyMangaList, (item: DailyMangaItem) => {
            this.buildDailyMangaCard(item)
          })
        }
        .width('100%')
        .padding(16)
        .backgroundColor(this.getBlurPanelBackground())
        .linearGradient(this.getBlurPanelSurfaceGradient())
        .backgroundBlurStyle(this.getBlurPanelBlurStyle(), this.getBlurPanelBlurOptions())
        .backgroundEffect(this.getBlurPanelBackgroundEffect())
        .borderRadius(this.getBlurPanelRadius())
        .clip(true)
        .shadow({ radius: this.getBlurPanelRadius() + 2, color: this.getBlurPanelShadowColor(), offsetX: 0, offsetY: 4 })
        .border({ width: this.getBlurPanelBorderWidth(), color: this.getBlurPanelBorder() })
        .margin({ left: this.getAnalyticsSectionHorizontalMargin(), right: this.getAnalyticsSectionHorizontalMargin() })
      }
      
      // 当天阅读的电子书列表
      if (this.dailyEBookList.length > 0) {
        Column({ space: 12 }) {
          this.buildAnalyticsSectionHeader($r('sys.symbol.book'), '阅读的电子书')
          
          ForEach(this.dailyEBookList, (item: DailyEBookItem) => {
            this.buildDailyEBookCard(item)
          })
        }
        .width('100%')
        .padding(16)
        .backgroundColor(this.getBlurPanelBackground())
        .linearGradient(this.getBlurPanelSurfaceGradient())
        .backgroundBlurStyle(this.getBlurPanelBlurStyle(), this.getBlurPanelBlurOptions())
        .backgroundEffect(this.getBlurPanelBackgroundEffect())
        .borderRadius(this.getBlurPanelRadius())
        .clip(true)
        .shadow({ radius: this.getBlurPanelRadius() + 2, color: this.getBlurPanelShadowColor(), offsetX: 0, offsetY: 4 })
        .border({ width: this.getBlurPanelBorderWidth(), color: this.getBlurPanelBorder() })
        .margin({ left: this.getAnalyticsSectionHorizontalMargin(), right: this.getAnalyticsSectionHorizontalMargin() })
      }
      
      // 当天阅读的小说列表（包括在线小说）
      if (this.dailyNovelList.length > 0) {
        Column({ space: 12 }) {
          this.buildAnalyticsSectionHeader($r('sys.symbol.doc_text'), '阅读的小说')
          
          ForEach(this.dailyNovelList, (item: DailyNovelItem) => {
            this.buildDailyNovelCard(item)
          })
        }
        .width('100%')
        .padding(16)
        .backgroundColor(this.getBlurPanelBackground())
        .linearGradient(this.getBlurPanelSurfaceGradient())
        .backgroundBlurStyle(this.getBlurPanelBlurStyle(), this.getBlurPanelBlurOptions())
        .backgroundEffect(this.getBlurPanelBackgroundEffect())
        .borderRadius(this.getBlurPanelRadius())
        .clip(true)
        .shadow({ radius: this.getBlurPanelRadius() + 2, color: this.getBlurPanelShadowColor(), offsetX: 0, offsetY: 4 })
        .border({ width: this.getBlurPanelBorderWidth(), color: this.getBlurPanelBorder() })
        .margin({ left: this.getAnalyticsSectionHorizontalMargin(), right: this.getAnalyticsSectionHorizontalMargin() })
      }
    }
    .width('100%')
  }

  /**
   * 构建日视图漫画卡片
   */
  @Builder
  buildDailyMangaCard(item: DailyMangaItem) {
    Row({ space: 12 }) {
      // 封面图片
      Image(this.normalizeCoverPath(item.coverPath))
        .width(60)
        .height(80)
        .borderRadius(6)
        .objectFit(ImageFit.Cover)
        .backgroundColor(this.getBlurPanelBackground())
      
      // 漫画信息
      Column({ space: 4 }) {
        Text(item.title)
          .fontSize(14)
          .fontWeight(FontWeight.Medium)
          .fontFamily(this.appFontFamily)
          .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_primary', this.themeState.currentTheme))
          .maxLines(2)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
          .width('100%')
        
        Row({ space: 8 }) {
          Row({ space: 2 }) {
            SymbolGlyph($r('sys.symbol.clock')).fontSize(12).fontColor([ThemeAwareHelper.getTestManagementThemedColor('text_secondary', this.themeState.currentTheme)])
            Text(this.formatDuration(item.readingTime)).fontSize(12).fontFamily(this.appFontFamily).fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_secondary', this.themeState.currentTheme))
          }
          Row({ space: 2 }) {
            SymbolGlyph($r('sys.symbol.book')).fontSize(12).fontColor([ThemeAwareHelper.getTestManagementThemedColor('text_secondary', this.themeState.currentTheme)])
            Text(`${item.chaptersRead}章`).fontSize(12).fontFamily(this.appFontFamily).fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_secondary', this.themeState.currentTheme))
          }
          Row({ space: 2 }) {
            SymbolGlyph($r('sys.symbol.doc')).fontSize(12).fontColor([ThemeAwareHelper.getTestManagementThemedColor('text_secondary', this.themeState.currentTheme)])
            Text(`${item.pagesRead}页`).fontSize(12).fontFamily(this.appFontFamily).fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_secondary', this.themeState.currentTheme))
          }
        }
      }
      .layoutWeight(1)
      .alignItems(HorizontalAlign.Start)
    }
    .width('100%')
    .padding(12)
    .backgroundColor(this.getAnalyticsSubPanelBackground())
    .linearGradient(this.getBlurPanelSurfaceGradient())
    .backgroundBlurStyle(this.getBlurPanelBlurStyle(), this.getBlurPanelBlurOptions())
    .backgroundEffect(this.getBlurPanelBackgroundEffect())
    .borderRadius(this.getAnalyticsInnerRadius())
    .clip(true)
    .shadow({ radius: this.getAnalyticsItemShadowRadius(), color: this.getBlurPanelShadowColor(), offsetX: 0, offsetY: 3 })
    .border({ width: this.getBlurPanelBorderWidth(), color: this.getBlurPanelBorder() })
    .onClick(() => {
      // 点击跳转到漫画详情页（根据设置选择详情页类型）
      this.openMangaDetail(item.comicId, item.title, item.coverPath);
    })
  }

  /**
   * 构建日视图电子书卡片
   */
  @Builder
  buildDailyEBookCard(item: DailyEBookItem) {
    Row({ space: 12 }) {
      // 封面图片
      Image(this.normalizeCoverPath(item.coverPath, true))
        .width(60)
        .height(80)
        .borderRadius(6)
        .objectFit(ImageFit.Cover)
        .backgroundColor(this.getBlurPanelBackground())
      
      // 电子书信息
      Column({ space: 4 }) {
        Text(item.title)
          .fontSize(14)
          .fontWeight(FontWeight.Medium)
          .fontFamily(this.appFontFamily)
          .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_primary', this.themeState.currentTheme))
          .maxLines(2)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
          .width('100%')
        
        Row({ space: 8 }) {
          Row({ space: 2 }) {
            SymbolGlyph($r('sys.symbol.clock')).fontSize(12).fontColor([ThemeAwareHelper.getTestManagementThemedColor('text_secondary', this.themeState.currentTheme)])
            Text(this.formatDuration(item.readingTime)).fontSize(12).fontFamily(this.appFontFamily).fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_secondary', this.themeState.currentTheme))
          }
          Text(`${item.progress.toFixed(1)}%`)
            .fontSize(12)
            .fontFamily(this.appFontFamily)
            .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_secondary', this.themeState.currentTheme))
        }
      }
      .layoutWeight(1)
      .alignItems(HorizontalAlign.Start)
    }
    .width('100%')
    .padding(12)
    .backgroundColor(this.getAnalyticsSubPanelBackground())
    .linearGradient(this.getBlurPanelSurfaceGradient())
    .backgroundBlurStyle(this.getBlurPanelBlurStyle(), this.getBlurPanelBlurOptions())
    .backgroundEffect(this.getBlurPanelBackgroundEffect())
    .borderRadius(this.getAnalyticsInnerRadius())
    .clip(true)
    .shadow({ radius: this.getAnalyticsItemShadowRadius(), color: this.getBlurPanelShadowColor(), offsetX: 0, offsetY: 3 })
    .border({ width: this.getBlurPanelBorderWidth(), color: this.getBlurPanelBorder() })
    .onClick(() => {
      // 点击跳转到电子书详情页（根据设置选择详情页类型）
      this.openEBookDetail(item.ebookId, item.title, item.coverPath);
    })
  }

  /**
   * 检查是否有设置任何阅读目标
   */
  private hasAnyReadingGoal(): boolean {
    return this.readingGoals.mangaGoalMinutes > 0 || 
           this.readingGoals.ebookGoalMinutes > 0 || 
           this.readingGoals.novelGoalMinutes > 0;
  }

  /**
   * 构建阅读目标进度卡片
   */
  @Builder
  buildReadingGoalsProgress() {
    Column({ space: 12 }) {
      Row({ space: 6 }) {
        SymbolGlyph($r('sys.symbol.flag'))
          .fontSize(18)
          .fontColor([ThemeAwareHelper.getTestManagementThemedColor('accent_primary', this.themeState.currentTheme)])
        Text('今日阅读目标')
          .fontSize(16)
          .fontWeight(FontWeight.Medium)
          .fontFamily(this.appFontFamily)
          .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_primary', this.themeState.currentTheme))
        
        Blank()
        
        // 设置按钮
        Button({ stateEffect: true }) {
          Row({ space: 4 }) {
            SymbolGlyph($r('sys.symbol.gearshape'))
              .fontSize(14)
              .fontColor([ThemeAwareHelper.getTestManagementThemedColor('accent_primary', this.themeState.currentTheme)])
            Text('设置')
              .fontSize(12)
              .fontFamily(this.appFontFamily)
              .fontColor(ThemeAwareHelper.getTestManagementThemedColor('accent_primary', this.themeState.currentTheme))
          }
        }
        .height(28)
        .padding({ left: 10, right: 10 })
        .backgroundColor(ThemeAwareHelper.getTestManagementThemedColor('accent_primary_dimmed', this.themeState.currentTheme))
        .borderRadius(14)
        .onClick(() => {
          this.openGoalSettingDialog();
        })
      }
      .width('100%')
      
      if (this.hasAnyReadingGoal()) {
        // 有目标时显示进度
        Column({ space: 12 }) {
          // 漫画目标
          if (this.readingGoals.mangaGoalMinutes > 0) {
            this.buildMangaGoalProgress()
          }
          
          // 电子书目标
          if (this.readingGoals.ebookGoalMinutes > 0) {
            this.buildEbookGoalProgress()
          }
          
          // 小说目标
          if (this.readingGoals.novelGoalMinutes > 0) {
            this.buildNovelGoalProgress()
          }
        }
        .width('100%')
      } else {
        // 无目标时显示提示
        Column({ space: 8 }) {
          SymbolGlyph($r('sys.symbol.plus_circle'))
            .fontSize(32)
            .fontColor([ThemeAwareHelper.getTestManagementThemedColor('text_tertiary', this.themeState.currentTheme)])
          Text('点击"设置"添加阅读目标')
            .fontSize(13)
            .fontFamily(this.appFontFamily)
            .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_secondary', this.themeState.currentTheme))
        }
        .width('100%')
        .padding(24)
        .alignItems(HorizontalAlign.Center)
      }
    }
    .width('100%')
    .padding(16)
    .backgroundColor(this.getBlurPanelBackground())
    .linearGradient(this.getBlurPanelSurfaceGradient())
    .backgroundBlurStyle(this.getBlurPanelBlurStyle(), this.getBlurPanelBlurOptions())
    .backgroundEffect(this.getBlurPanelBackgroundEffect())
    .borderRadius(this.getBlurPanelRadius())
    .clip(true)
    .shadow({ radius: this.getBlurPanelRadius() + 2, color: this.getBlurPanelShadowColor(), offsetX: 0, offsetY: 4 })
    .border({ width: this.getBlurPanelBorderWidth(), color: this.getBlurPanelBorder() })
    .margin({ left: this.getAnalyticsSectionHorizontalMargin(), right: this.getAnalyticsSectionHorizontalMargin() })
  }
  
  /**
   * 计算目标进度百分比
   */
  private calculateGoalProgress(currentMinutes: number, goalMinutes: number): number {
    if (goalMinutes <= 0) {
      return 0;
    }
    return Math.min(currentMinutes / goalMinutes, 1);
  }
  
  /**
   * 检查目标是否已完成
   */
  private isGoalCompleted(currentMinutes: number, goalMinutes: number): boolean {
    if (goalMinutes <= 0) {
      return false;
    }
    return currentMinutes >= goalMinutes;
  }

  /**
   * 构建漫画目标进度项（直接访问 @State 变量以支持响应式更新）
   */
  @Builder
  buildMangaGoalProgress() {
    Column({ space: 8 }) {
      Row({ space: 8 }) {
        SymbolGlyph($r('sys.symbol.picture'))
          .fontSize(16)
          .fontColor([this.isGoalCompleted(this.dailyMangaReadingMinutes, this.readingGoals.mangaGoalMinutes) 
            ? ThemeAwareHelper.getTestManagementThemedColor('accent_green', this.themeState.currentTheme)
            : ThemeAwareHelper.getTestManagementThemedColor('accent_primary', this.themeState.currentTheme)])
        
        Text('漫画')
          .fontSize(14)
          .fontFamily(this.appFontFamily)
          .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_primary', this.themeState.currentTheme))
        
        Blank()
        
        if (this.isGoalCompleted(this.dailyMangaReadingMinutes, this.readingGoals.mangaGoalMinutes)) {
          Row({ space: 4 }) {
            SymbolGlyph($r('sys.symbol.checkmark_circle_fill'))
              .fontSize(14)
              .fontColor([ThemeAwareHelper.getTestManagementThemedColor('accent_green', this.themeState.currentTheme)])
            Text('已完成')
              .fontSize(12)
              .fontFamily(this.appFontFamily)
              .fontColor(ThemeAwareHelper.getTestManagementThemedColor('accent_green', this.themeState.currentTheme))
          }
        } else {
          Text(`${this.dailyMangaReadingMinutes}/${this.readingGoals.mangaGoalMinutes}分钟`)
            .fontSize(12)
            .fontFamily(this.appFontFamily)
            .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_secondary', this.themeState.currentTheme))
        }
      }
      .width('100%')
      
      // 进度条
      Row() {
        Row()
          .width(`${this.calculateGoalProgress(this.dailyMangaReadingMinutes, this.readingGoals.mangaGoalMinutes) * 100}%`)
          .height('100%')
          .borderRadius(3)
          .backgroundColor(this.isGoalCompleted(this.dailyMangaReadingMinutes, this.readingGoals.mangaGoalMinutes) 
            ? ThemeAwareHelper.getTestManagementThemedColor('accent_green', this.themeState.currentTheme)
            : ThemeAwareHelper.getTestManagementThemedColor('accent_primary', this.themeState.currentTheme))
      }
      .width('100%')
      .height(6)
      .borderRadius(3)
      .backgroundColor(this.getAnalyticsTrackBackground())
    }
    .width('100%')
    .padding(12)
    .backgroundColor(this.getAnalyticsSubPanelBackground())
    .linearGradient(this.getBlurPanelSurfaceGradient())
    .backgroundBlurStyle(this.getBlurPanelBlurStyle(), this.getBlurPanelBlurOptions())
    .backgroundEffect(this.getBlurPanelBackgroundEffect())
    .borderRadius(this.getAnalyticsInnerRadius())
    .clip(true)
    .shadow({ radius: this.getAnalyticsItemShadowRadius(), color: this.getBlurPanelShadowColor(), offsetX: 0, offsetY: 3 })
    .border({ width: this.getBlurPanelBorderWidth(), color: this.getBlurPanelBorder() })
  }
  
  /**
   * 构建电子书目标进度项（直接访问 @State 变量以支持响应式更新）
   */
  @Builder
  buildEbookGoalProgress() {
    Column({ space: 8 }) {
      Row({ space: 8 }) {
        SymbolGlyph($r('sys.symbol.book'))
          .fontSize(16)
          .fontColor([this.isGoalCompleted(this.dailyEbookReadingMinutes, this.readingGoals.ebookGoalMinutes) 
            ? ThemeAwareHelper.getTestManagementThemedColor('accent_green', this.themeState.currentTheme)
            : ThemeAwareHelper.getTestManagementThemedColor('accent_primary', this.themeState.currentTheme)])
        
        Text('电子书')
          .fontSize(14)
          .fontFamily(this.appFontFamily)
          .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_primary', this.themeState.currentTheme))
        
        Blank()
        
        if (this.isGoalCompleted(this.dailyEbookReadingMinutes, this.readingGoals.ebookGoalMinutes)) {
          Row({ space: 4 }) {
            SymbolGlyph($r('sys.symbol.checkmark_circle_fill'))
              .fontSize(14)
              .fontColor([ThemeAwareHelper.getTestManagementThemedColor('accent_green', this.themeState.currentTheme)])
            Text('已完成')
              .fontSize(12)
              .fontFamily(this.appFontFamily)
              .fontColor(ThemeAwareHelper.getTestManagementThemedColor('accent_green', this.themeState.currentTheme))
          }
        } else {
          Text(`${this.dailyEbookReadingMinutes}/${this.readingGoals.ebookGoalMinutes}分钟`)
            .fontSize(12)
            .fontFamily(this.appFontFamily)
            .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_secondary', this.themeState.currentTheme))
        }
      }
      .width('100%')
      
      // 进度条
      Row() {
        Row()
          .width(`${this.calculateGoalProgress(this.dailyEbookReadingMinutes, this.readingGoals.ebookGoalMinutes) * 100}%`)
          .height('100%')
          .borderRadius(3)
          .backgroundColor(this.isGoalCompleted(this.dailyEbookReadingMinutes, this.readingGoals.ebookGoalMinutes) 
            ? ThemeAwareHelper.getTestManagementThemedColor('accent_green', this.themeState.currentTheme)
            : ThemeAwareHelper.getTestManagementThemedColor('accent_primary', this.themeState.currentTheme))
      }
      .width('100%')
      .height(6)
      .borderRadius(3)
      .backgroundColor(this.getAnalyticsTrackBackground())
    }
    .width('100%')
    .padding(12)
    .backgroundColor(this.getAnalyticsSubPanelBackground())
    .linearGradient(this.getBlurPanelSurfaceGradient())
    .backgroundBlurStyle(this.getBlurPanelBlurStyle(), this.getBlurPanelBlurOptions())
    .backgroundEffect(this.getBlurPanelBackgroundEffect())
    .borderRadius(this.getAnalyticsInnerRadius())
    .clip(true)
    .shadow({ radius: this.getAnalyticsItemShadowRadius(), color: this.getBlurPanelShadowColor(), offsetX: 0, offsetY: 3 })
    .border({ width: this.getBlurPanelBorderWidth(), color: this.getBlurPanelBorder() })
  }
  
  /**
   * 构建小说目标进度项（直接访问 @State 变量以支持响应式更新）
   */
  @Builder
  buildNovelGoalProgress() {
    Column({ space: 8 }) {
      Row({ space: 8 }) {
        SymbolGlyph($r('sys.symbol.doc_text'))
          .fontSize(16)
          .fontColor([this.isGoalCompleted(this.dailyNovelReadingMinutes, this.readingGoals.novelGoalMinutes) 
            ? ThemeAwareHelper.getTestManagementThemedColor('accent_green', this.themeState.currentTheme)
            : ThemeAwareHelper.getTestManagementThemedColor('accent_primary', this.themeState.currentTheme)])
        
        Text('小说')
          .fontSize(14)
          .fontFamily(this.appFontFamily)
          .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_primary', this.themeState.currentTheme))
        
        Blank()
        
        if (this.isGoalCompleted(this.dailyNovelReadingMinutes, this.readingGoals.novelGoalMinutes)) {
          Row({ space: 4 }) {
            SymbolGlyph($r('sys.symbol.checkmark_circle_fill'))
              .fontSize(14)
              .fontColor([ThemeAwareHelper.getTestManagementThemedColor('accent_green', this.themeState.currentTheme)])
            Text('已完成')
              .fontSize(12)
              .fontFamily(this.appFontFamily)
              .fontColor(ThemeAwareHelper.getTestManagementThemedColor('accent_green', this.themeState.currentTheme))
          }
        } else {
          Text(`${this.dailyNovelReadingMinutes}/${this.readingGoals.novelGoalMinutes}分钟`)
            .fontSize(12)
            .fontFamily(this.appFontFamily)
            .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_secondary', this.themeState.currentTheme))
        }
      }
      .width('100%')
      
      // 进度条
      Row() {
        Row()
          .width(`${this.calculateGoalProgress(this.dailyNovelReadingMinutes, this.readingGoals.novelGoalMinutes) * 100}%`)
          .height('100%')
          .borderRadius(3)
          .backgroundColor(this.isGoalCompleted(this.dailyNovelReadingMinutes, this.readingGoals.novelGoalMinutes) 
            ? ThemeAwareHelper.getTestManagementThemedColor('accent_green', this.themeState.currentTheme)
            : ThemeAwareHelper.getTestManagementThemedColor('accent_primary', this.themeState.currentTheme))
      }
      .width('100%')
      .height(6)
      .borderRadius(3)
      .backgroundColor(this.getAnalyticsTrackBackground())
    }
    .width('100%')
    .padding(12)
    .backgroundColor(this.getAnalyticsSubPanelBackground())
    .linearGradient(this.getBlurPanelSurfaceGradient())
    .backgroundBlurStyle(this.getBlurPanelBlurStyle(), this.getBlurPanelBlurOptions())
    .backgroundEffect(this.getBlurPanelBackgroundEffect())
    .borderRadius(this.getAnalyticsInnerRadius())
    .clip(true)
    .shadow({ radius: this.getAnalyticsItemShadowRadius(), color: this.getBlurPanelShadowColor(), offsetX: 0, offsetY: 3 })
    .border({ width: this.getBlurPanelBorderWidth(), color: this.getBlurPanelBorder() })
  }
  
  /**
   * 计算当天漫画阅读分钟数
   */
  private calculateMangaReadingMinutes(): number {
    let totalSeconds = 0;
    this.dailyMangaList.forEach(item => {
      totalSeconds += item.readingTime;
    });
    return Math.round(totalSeconds / 60);
  }
  
  /**
   * 计算当天电子书阅读分钟数
   */
  private calculateEbookReadingMinutes(): number {
    let totalSeconds = 0;
    this.dailyEBookList.forEach(item => {
      totalSeconds += item.readingTime;
    });
    return Math.round(totalSeconds / 60);
  }
  
  /**
   * 计算当天小说阅读分钟数
   */
  private calculateNovelReadingMinutes(): number {
    let totalSeconds = 0;
    this.dailyNovelList.forEach(item => {
      totalSeconds += item.readingTime;
    });
    return Math.round(totalSeconds / 60);
  }

  /**
   * 构建日视图小说卡片
   */
  @Builder
  buildDailyNovelCard(item: DailyNovelItem) {
    Row({ space: 12 }) {
      // 封面图片
      if (item.coverPath && item.coverPath.length > 0) {
        Image(this.normalizeCoverPath(item.coverPath))
          .width(60)
          .height(80)
          .borderRadius(6)
          .objectFit(ImageFit.Cover)
          .backgroundColor(this.getBlurPanelBackground())
      } else {
        // 无封面时显示默认图标
        Column() {
          SymbolGlyph($r('sys.symbol.doc_text'))
            .fontSize(32)
            .fontColor([ThemeAwareHelper.getTestManagementThemedColor('text_tertiary', this.themeState.currentTheme)])
        }
        .width(60)
        .height(80)
        .borderRadius(6)
        .backgroundColor(this.getBlurPanelBackground())
        .justifyContent(FlexAlign.Center)
      }
      
      // 小说信息
      Column({ space: 4 }) {
        Row({ space: 6 }) {
          Text(item.title)
            .fontSize(14)
            .fontWeight(FontWeight.Medium)
            .fontFamily(this.appFontFamily)
            .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_primary', this.themeState.currentTheme))
            .maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
            .layoutWeight(1)
          
          // 在线小说标记
          if (item.isOnline) {
            Text('在线')
              .fontSize(10)
              .fontFamily(this.appFontFamily)
              .fontColor(ThemeAwareHelper.getTestManagementThemedColor('accent_blue', this.themeState.currentTheme))
              .padding({ left: 6, right: 6, top: 2, bottom: 2 })
              .backgroundColor(this.getAnalyticsChipBackground())
              .borderRadius(4)
          }
        }
        .width('100%')
        
        Text(item.author)
          .fontSize(12)
          .fontFamily(this.appFontFamily)
          .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_muted', this.themeState.currentTheme))
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
        
        Row({ space: 8 }) {
          Row({ space: 2 }) {
            SymbolGlyph($r('sys.symbol.clock')).fontSize(12).fontColor([ThemeAwareHelper.getTestManagementThemedColor('text_secondary', this.themeState.currentTheme)])
            Text(this.formatDuration(item.readingTime)).fontSize(12).fontFamily(this.appFontFamily).fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_secondary', this.themeState.currentTheme))
          }
          Row({ space: 2 }) {
            SymbolGlyph($r('sys.symbol.book')).fontSize(12).fontColor([ThemeAwareHelper.getTestManagementThemedColor('text_secondary', this.themeState.currentTheme)])
            Text(`${item.chaptersRead}章`).fontSize(12).fontFamily(this.appFontFamily).fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_secondary', this.themeState.currentTheme))
          }
        }
      }
      .layoutWeight(1)
      .alignItems(HorizontalAlign.Start)
    }
    .width('100%')
    .padding(12)
    .backgroundColor(this.getAnalyticsSubPanelBackground())
    .linearGradient(this.getBlurPanelSurfaceGradient())
    .backgroundBlurStyle(this.getBlurPanelBlurStyle(), this.getBlurPanelBlurOptions())
    .backgroundEffect(this.getBlurPanelBackgroundEffect())
    .borderRadius(this.getAnalyticsInnerRadius())
    .clip(true)
    .shadow({ radius: this.getAnalyticsItemShadowRadius(), color: this.getBlurPanelShadowColor(), offsetX: 0, offsetY: 3 })
    .border({ width: this.getBlurPanelBorderWidth(), color: this.getBlurPanelBorder() })
    .onClick(() => {
      // 点击跳转到小说详情页（根据设置选择详情页类型）
      // 使用 bookUrl 作为 contentId，而不是 novelId
      this.openNovelDetail(item.bookUrl, item.sourceId, item.title, item.author, item.coverPath);
    })
  }

  /**
   * 获取统计卡片图标资源
   */
  private getStatCardIconResource(icon: string): Resource {
    switch (icon) {
      case '⏱️':
      case '⏰':
        return $r('sys.symbol.clock');
      case '📅':
        return $r('sys.symbol.calendar');
      case '📚':
        return $r('sys.symbol.picture');
      case '📖':
      case '📕':
        return $r('sys.symbol.book');
      case '📗':
        return $r('sys.symbol.doc_text');
      case '📄':
        return $r('sys.symbol.doc');
      case '🔥':
        return $r('sys.symbol.star');
      default:
        return $r('sys.symbol.circle');
    }
  }

  private getStatCardIconSize(style: StatCardStyle): number {
    switch (style) {
      case StatCardStyle.FEATURED:
        return 34;
      case StatCardStyle.COMPACT:
        return 22;
      default:
        return 28;
    }
  }

  private getStatCardValueFontSize(style: StatCardStyle): number {
    switch (style) {
      case StatCardStyle.FEATURED:
        return 28;
      case StatCardStyle.COMPACT:
        return 18;
      default:
        return 22;
    }
  }

  private getStatCardPadding(style: StatCardStyle): number {
    switch (style) {
      case StatCardStyle.FEATURED:
        return 18;
      case StatCardStyle.COMPACT:
        return 12;
      default:
        return 14;
    }
  }

  /**
   * 构建统计卡片（带模糊效果磁贴设计）
   */
  @Builder
  buildStatCard(title: string, value: string, icon: string, unit: string = '', style: StatCardStyle = StatCardStyle.STANDARD) {
    Column({ space: style === StatCardStyle.COMPACT ? 4 : 6 }) {
      // 图标
      SymbolGlyph(this.getStatCardIconResource(icon))
        .fontSize(this.getStatCardIconSize(style))
        .fontColor([ThemeAwareHelper.getTestManagementThemedColor('accent_primary', this.themeState.currentTheme)])
        .alignSelf(ItemAlign.Start)

      // 数值和单位（同一行显示）
      Row({ space: 2 }) {
        Text(value)
          .fontSize(this.getStatCardValueFontSize(style))
          .fontWeight(FontWeight.Bold)
          .fontFamily(this.appFontFamily)
          .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_primary', this.themeState.currentTheme))
          .constraintSize({ maxWidth: '100%' })
          .textOverflow({ overflow: TextOverflow.Ellipsis })

        if (unit.length > 0) {
          Text(unit)
            .fontSize(13)
            .fontFamily(this.appFontFamily)
            .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_secondary', this.themeState.currentTheme))
            .alignSelf(ItemAlign.End)
            .margin({ bottom: 2 })
        }
      }
      .alignSelf(ItemAlign.Start)
      .constraintSize({ maxWidth: '100%' })

      // 标题
      Text(title)
        .fontSize(12)
        .fontFamily(this.appFontFamily)
        .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_secondary', this.themeState.currentTheme))
        .width('100%')
        .maxLines(2)
        .lineHeight(16)
        .textOverflow({ overflow: TextOverflow.Ellipsis })
        .alignSelf(ItemAlign.Start)
    }
    .width('100%')
    .padding(this.getStatCardPadding(style))
    .backgroundColor(this.getBlurPanelBackground())
    .linearGradient(this.getBlurPanelSurfaceGradient())
    .backgroundBlurStyle(this.getBlurPanelBlurStyle(), this.getBlurPanelBlurOptions())
    .backgroundEffect(this.getBlurPanelBackgroundEffect())
    .borderRadius(this.getBlurPanelRadius())
    .clip(true)
    .shadow({
      radius: this.getBlurPanelRadius() + 2,
      color: this.getBlurPanelShadowColor(),
      offsetX: 0,
      offsetY: 4
    })
    .border({
      width: this.getBlurPanelBorderWidth(),
      color: this.getBlurPanelBorder()
    })
  }

  @Builder
  private buildReadingInsightCard(item: ReadingInsightItem) {
    Column({ space: 8 }) {
      Row({ space: 8 }) {
        SymbolGlyph(item.symbol)
          .fontSize(20)
          .fontColor([item.accentColor])
        Text(item.title)
          .fontSize(12)
          .fontFamily(this.appFontFamily)
          .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_secondary', this.themeState.currentTheme))
          .layoutWeight(1)
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
      }
      .width('100%')

      Text(item.value)
        .fontSize(20)
        .fontWeight(FontWeight.Bold)
        .fontFamily(this.appFontFamily)
        .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_primary', this.themeState.currentTheme))
        .width('100%')
        .maxLines(1)
        .textOverflow({ overflow: TextOverflow.Ellipsis })

      Text(item.detail)
        .fontSize(12)
        .fontFamily(this.appFontFamily)
        .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_muted', this.themeState.currentTheme))
        .width('100%')
        .maxLines(2)
        .lineHeight(16)
        .textOverflow({ overflow: TextOverflow.Ellipsis })
    }
    .width('100%')
    .padding(14)
    .backgroundColor(this.getAnalyticsSubPanelBackground())
    .borderRadius(this.getAnalyticsInnerRadius())
    .border({ width: this.getBlurPanelBorderWidth(), color: this.getBlurPanelBorder() })
  }

  @Builder
  buildReadingInsightSummary() {
    Column({ space: 14 }) {
      this.buildAnalyticsSectionHeader($r('sys.symbol.lightbulb'), '阅读洞察', this.getTimeRangeButtonText())

      Grid() {
        ForEach(this.getReadingInsights(), (item: ReadingInsightItem, index: number) => {
          GridItem() {
            this.buildReadingInsightCard(item)
          }
        }, (item: ReadingInsightItem, index: number) => `${item.title}-${index}`)
      }
      .columnsTemplate(this.responsive_isLandscape ? '1fr 1fr 1fr' : '1fr 1fr')
      .rowsGap(10)
      .columnsGap(10)
      .width('100%')
    }
    .width('100%')
    .padding(16)
    .backgroundColor(this.getBlurPanelBackground())
    .linearGradient(this.getBlurPanelSurfaceGradient())
    .backgroundBlurStyle(this.getBlurPanelBlurStyle(), this.getBlurPanelBlurOptions())
    .backgroundEffect(this.getBlurPanelBackgroundEffect())
    .borderRadius(this.getBlurPanelRadius())
    .clip(true)
    .shadow({ radius: this.getBlurPanelRadius() + 2, color: this.getBlurPanelShadowColor(), offsetX: 0, offsetY: 4 })
    .border({ width: this.getBlurPanelBorderWidth(), color: this.getBlurPanelBorder() })
    .margin({ left: this.getAnalyticsSectionHorizontalMargin(), right: this.getAnalyticsSectionHorizontalMargin() })
  }

  @Builder
  private buildContentMixSegment(segment: ContentMixSegment) {
    Column({ space: 8 }) {
      Row({ space: 8 }) {
        SymbolGlyph(segment.symbol)
          .fontSize(18)
          .fontColor([segment.accentColor])
        Text(segment.label)
          .fontSize(14)
          .fontWeight(FontWeight.Medium)
          .fontFamily(this.appFontFamily)
          .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_primary', this.themeState.currentTheme))
        Blank()
        Text(this.formatPercent(segment.percent))
          .fontSize(14)
          .fontWeight(FontWeight.Bold)
          .fontFamily(this.appFontFamily)
          .fontColor(segment.accentColor)
      }
      .width('100%')

      Row() {
        Row()
          .width(this.getSafePercentWidth(segment.percent))
          .height('100%')
          .borderRadius(4)
          .backgroundColor(segment.accentColor)
      }
      .width('100%')
      .height(8)
      .borderRadius(4)
      .backgroundColor(this.getAnalyticsTrackBackground())

      Row() {
        Text(this.formatDuration(segment.valueSeconds))
          .fontSize(12)
          .fontFamily(this.appFontFamily)
          .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_secondary', this.themeState.currentTheme))
        Blank()
        Text(`${segment.itemCount}项`)
          .fontSize(12)
          .fontFamily(this.appFontFamily)
          .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_muted', this.themeState.currentTheme))
      }
      .width('100%')
    }
    .width('100%')
  }

  @Builder
  buildContentMixSection(segments: ContentMixSegment[], title: string = '内容构成') {
    if (segments.length > 0) {
      Column({ space: 14 }) {
        this.buildAnalyticsSectionHeader($r('sys.symbol.histogram'), title)

        ForEach(segments, (segment: ContentMixSegment, index: number) => {
          this.buildContentMixSegment(segment)
        }, (segment: ContentMixSegment, index: number) => `${segment.kind}-${index}`)
      }
      .width('100%')
      .padding(16)
      .backgroundColor(this.getBlurPanelBackground())
      .linearGradient(this.getBlurPanelSurfaceGradient())
      .backgroundBlurStyle(this.getBlurPanelBlurStyle(), this.getBlurPanelBlurOptions())
      .backgroundEffect(this.getBlurPanelBackgroundEffect())
      .borderRadius(this.getBlurPanelRadius())
      .clip(true)
      .shadow({ radius: this.getBlurPanelRadius() + 2, color: this.getBlurPanelShadowColor(), offsetX: 0, offsetY: 4 })
      .border({ width: this.getBlurPanelBorderWidth(), color: this.getBlurPanelBorder() })
      .margin({ left: this.getAnalyticsSectionHorizontalMargin(), right: this.getAnalyticsSectionHorizontalMargin() })
    }
  }

  @Builder
  private buildTrendBarItem(item: ReadingTrendBar) {
    Column({ space: 6 }) {
      Row() {
        Text(item.label)
          .fontSize(12)
          .fontFamily(this.appFontFamily)
          .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_secondary', this.themeState.currentTheme))
          .width(48)
        Row() {
          Row()
            .width(this.getSafePercentWidth(item.percent))
            .height('100%')
            .borderRadius(5)
            .backgroundColor(ThemeAwareHelper.getTestManagementThemedColor('accent_blue', this.themeState.currentTheme))
        }
        .layoutWeight(1)
        .height(10)
        .borderRadius(5)
        .backgroundColor(this.getAnalyticsTrackBackground())
        .margin({ left: 8, right: 8 })
        Text(this.formatDuration(item.readingTime))
          .fontSize(12)
          .fontFamily(this.appFontFamily)
          .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_primary', this.themeState.currentTheme))
          .width(76)
          .textAlign(TextAlign.End)
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
      }
      .width('100%')
      .alignItems(VerticalAlign.Center)

      Row({ space: 8 }) {
        Text(item.date)
          .fontSize(11)
          .fontFamily(this.appFontFamily)
          .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_muted', this.themeState.currentTheme))
        Blank()
        Text(`${item.chaptersRead}章 / ${item.pagesRead}页`)
          .fontSize(11)
          .fontFamily(this.appFontFamily)
          .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_muted', this.themeState.currentTheme))
      }
      .width('100%')
      .padding({ left: 48 })
    }
    .width('100%')
    .padding({ top: 8, bottom: 8 })
  }

  @Builder
  buildTrendVisualization() {
    if (this.getRecentTrendBars(10).length > 0) {
      Column({ space: 12 }) {
        this.buildAnalyticsSectionHeader($r('sys.symbol.histogram'), '阅读波动', '最近记录')

        ForEach(this.getRecentTrendBars(10), (item: ReadingTrendBar, index: number) => {
          this.buildTrendBarItem(item)
        }, (item: ReadingTrendBar, index: number) => `${item.date}-${index}`)
      }
      .width('100%')
      .padding(16)
      .backgroundColor(this.getBlurPanelBackground())
      .linearGradient(this.getBlurPanelSurfaceGradient())
      .backgroundBlurStyle(this.getBlurPanelBlurStyle(), this.getBlurPanelBlurOptions())
      .backgroundEffect(this.getBlurPanelBackgroundEffect())
      .borderRadius(this.getBlurPanelRadius())
      .clip(true)
      .shadow({ radius: this.getBlurPanelRadius() + 2, color: this.getBlurPanelShadowColor(), offsetX: 0, offsetY: 4 })
      .border({ width: this.getBlurPanelBorderWidth(), color: this.getBlurPanelBorder() })
      .margin({ left: this.getAnalyticsSectionHorizontalMargin(), right: this.getAnalyticsSectionHorizontalMargin() })
    }
  }

  /**
   * 构建统计概览区域
   */
  @Builder
  buildStatisticsOverview() {
    Column({ space: 16 }) {
      Row() {
        Row({ space: 6 }) {
          SymbolGlyph(this.getTimeRangeIcon()).fontSize(18).fontColor([ThemeAwareHelper.getTestManagementThemedColor('accent_primary', this.themeState.currentTheme)])
          Text(this.getTimeRangeTitle())
            .fontSize(18)
            .fontWeight(FontWeight.Bold)
            .fontFamily(this.appFontFamily)
            .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_primary', this.themeState.currentTheme))
        }

        Blank()

        // 时间范围切换按钮
        Button({ stateEffect: true }) {
          Row({ space: 4 }) {
            SymbolGlyph(this.getTimeRangeIcon())
              .fontSize(14)
              .fontColor([ThemeAwareHelper.getTestManagementThemedColor('accent_primary', this.themeState.currentTheme)])
            Text(this.getTimeRangeButtonText())
              .fontSize(12)
              .fontFamily(this.appFontFamily)
              .fontColor(ThemeAwareHelper.getTestManagementThemedColor('accent_primary', this.themeState.currentTheme))
          }
        }
        .height(28)
        .padding({ left: 10, right: 10 })
        .backgroundColor(ThemeAwareHelper.getTestManagementThemedColor('accent_primary_dimmed', this.themeState.currentTheme))
        .borderRadius(14)
        .onClick(() => this.cycleTimeRange())
      }
      .width('100%')
      .alignItems(VerticalAlign.Center)

      // 使用Grid布局实现2列磁贴效果
      Grid() {
        GridItem() {
          this.buildStatCard(
            '总阅读时长',
            this.formatDuration(this.statistics.totalReadingTime),
            '⏱️',
            '',
            StatCardStyle.FEATURED
          )
        }

        GridItem() {
          this.buildStatCard(
            '日均阅读',
            this.formatDuration(this.statistics.averageReadingTime),
            '📅',
            '',
            StatCardStyle.FEATURED
          )
        }

        GridItem() {
          this.buildStatCard(
            '阅读漫画',
            `${this.statistics.totalComicsRead}`,
            '📚',
            '本',
            StatCardStyle.COMPACT
          )
        }

        GridItem() {
          this.buildStatCard(
            '阅读章节',
            `${this.statistics.totalChaptersRead}`,
            '📖',
            '章',
            StatCardStyle.COMPACT
          )
        }

        GridItem() {
          this.buildStatCard(
            '阅读电子书',
            `${this.statistics.totalEBooksRead}`,
            '📕',
            '本',
            StatCardStyle.COMPACT
          )
        }

        GridItem() {
          this.buildStatCard(
            '电子书时长',
            this.formatDuration(this.statistics.totalEBookReadingTime),
            '📖',
            '',
            StatCardStyle.COMPACT
          )
        }

        GridItem() {
          this.buildStatCard(
            '阅读页数',
            `${this.statistics.totalPagesRead}`,
            '📄',
            '页',
            StatCardStyle.COMPACT
          )
        }

        GridItem() {
          this.buildStatCard(
            '连续阅读',
            `${this.statistics.continuousReadingDays}`,
            '🔥',
            '天',
            StatCardStyle.COMPACT
          )
        }
      }
      .columnsTemplate('1fr 1fr')
      .rowsGap(12)
      .columnsGap(12)
      .width('100%')
    }
    .width('100%')
    .padding(16)
    .backgroundColor(this.getBlurPanelBackground())
    .linearGradient(this.getBlurPanelSurfaceGradient())
    .backgroundBlurStyle(this.getBlurPanelBlurStyle(), this.getBlurPanelBlurOptions())
    .backgroundEffect(this.getBlurPanelBackgroundEffect())
    .borderRadius(this.getBlurPanelRadius())
    .clip(true)
    .shadow({ radius: this.getAnalyticsSectionShadowRadius(), color: this.getBlurPanelShadowColor(), offsetX: 0, offsetY: 4 })
    .border({ width: this.getBlurPanelBorderWidth(), color: this.getBlurPanelBorder() })
    .margin({ left: this.getAnalyticsSectionHorizontalMargin(), right: this.getAnalyticsSectionHorizontalMargin() })
  }

  @Builder
  private buildInspirationMetricItem(label: string, value: number) {
    Column({ space: 4 }) {
      Text(`${value}`)
        .fontSize(18)
        .fontWeight(FontWeight.Bold)
        .fontFamily(this.appFontFamily)
        .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_primary', this.themeState.currentTheme))
      Text(label)
        .fontSize(12)
        .fontFamily(this.appFontFamily)
        .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_secondary', this.themeState.currentTheme))
    }
    .layoutWeight(1)
    .alignItems(HorizontalAlign.Center)
    .padding({ top: 8, bottom: 8 })
  }

  @Builder
  buildInspirationOverviewSection() {
    Column({ space: this.getAnalyticsInnerGap() }) {
      Row({ space: 6 }) {
        SymbolGlyph($r('sys.symbol.highlighter_line'))
          .fontSize(18)
          .fontColor([ThemeAwareHelper.getTestManagementThemedColor('accent_primary', this.themeState.currentTheme)])
        Text('灵感总览')
          .fontSize(18)
          .fontWeight(FontWeight.Bold)
          .fontFamily(this.appFontFamily)
          .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_primary', this.themeState.currentTheme))
        Blank()
        Button() {
          Row({ space: 4 }) {
            SymbolGlyph($r('sys.symbol.share'))
              .fontSize(12)
              .fontColor([ThemeAwareHelper.getTestManagementThemedColor('accent_primary', this.themeState.currentTheme)])
            Text('查看')
              .fontSize(12)
              .fontFamily(this.appFontFamily)
              .fontColor(ThemeAwareHelper.getTestManagementThemedColor('accent_primary', this.themeState.currentTheme))
          }
        }
        .height(28)
        .padding({ left: 10, right: 10 })
        .backgroundColor(ThemeAwareHelper.getTestManagementThemedColor('accent_primary_dimmed', this.themeState.currentTheme))
        .borderRadius(14)
        .onClick(() => {
          this.openInspirationCenter('long_term');
        })
      }
      .width('100%')
      .alignItems(VerticalAlign.Center)

      Column() {
        Row({ space: 8 }) {
          this.buildInspirationMetricItem('总数', this.inspirationStats.totalCount)
          this.buildInspirationMetricItem('书签', this.inspirationStats.bookmarkCount)
          this.buildInspirationMetricItem('划线', this.inspirationStats.highlightCount)
          this.buildInspirationMetricItem('想法', this.inspirationStats.thoughtCount)
        }
        .width('100%')
      }
      .width('100%')
      .padding(16)
      .backgroundColor(this.getAnalyticsSubPanelBackground())
      .linearGradient(this.getBlurPanelSurfaceGradient())
      .backgroundBlurStyle(this.getBlurPanelBlurStyle(), this.getBlurPanelBlurOptions())
      .backgroundEffect(this.getBlurPanelBackgroundEffect())
      .borderRadius(this.getAnalyticsInnerRadius())
      .clip(true)
      .shadow({ radius: this.getAnalyticsItemShadowRadius(), color: this.getBlurPanelShadowColor(), offsetX: 0, offsetY: 3 })
      .border({ width: this.getBlurPanelBorderWidth(), color: this.getBlurPanelBorder() })
    }
    .width('100%')
    .padding(this.getAnalyticsSectionPadding())
    .backgroundColor(this.getBlurPanelBackground())
    .linearGradient(this.getBlurPanelSurfaceGradient())
    .backgroundBlurStyle(this.getBlurPanelBlurStyle(), this.getBlurPanelBlurOptions())
    .backgroundEffect(this.getBlurPanelBackgroundEffect())
    .borderRadius(this.getBlurPanelRadius())
    .clip(true)
    .shadow({ radius: this.getAnalyticsSectionShadowRadius(), color: this.getBlurPanelShadowColor(), offsetX: 0, offsetY: 4 })
    .border({ width: this.getBlurPanelBorderWidth(), color: this.getBlurPanelBorder() })
    .margin({ left: this.getAnalyticsSectionHorizontalMargin(), right: this.getAnalyticsSectionHorizontalMargin() })
  }

  @Builder
  buildDailyInspirationSection() {
    Column({ space: this.getAnalyticsInnerGap() }) {
      Row({ space: 6 }) {
        SymbolGlyph($r('sys.symbol.highlighter_line'))
          .fontSize(18)
          .fontColor([ThemeAwareHelper.getTestManagementThemedColor('accent_primary', this.themeState.currentTheme)])
        Text('当日灵感')
          .fontSize(16)
          .fontWeight(FontWeight.Medium)
          .fontFamily(this.appFontFamily)
          .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_primary', this.themeState.currentTheme))
        Blank()
        Button() {
          Row({ space: 4 }) {
            SymbolGlyph($r('sys.symbol.share'))
              .fontSize(12)
              .fontColor([ThemeAwareHelper.getTestManagementThemedColor('accent_primary', this.themeState.currentTheme)])
            Text('查看')
              .fontSize(12)
              .fontFamily(this.appFontFamily)
              .fontColor(ThemeAwareHelper.getTestManagementThemedColor('accent_primary', this.themeState.currentTheme))
          }
        }
        .height(28)
        .padding({ left: 10, right: 10 })
        .backgroundColor(ThemeAwareHelper.getTestManagementThemedColor('accent_primary_dimmed', this.themeState.currentTheme))
        .borderRadius(14)
        .onClick(() => {
          this.openInspirationCenter('daily_view');
        })
      }
      .width('100%')
      .alignItems(VerticalAlign.Center)

      Text(`${this.selectedDate.getMonth() + 1}月${this.selectedDate.getDate()}日创建`)
        .fontSize(12)
        .fontFamily(this.appFontFamily)
        .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_secondary', this.themeState.currentTheme))
        .alignSelf(ItemAlign.Start)

      Column() {
        Row({ space: 8 }) {
          this.buildInspirationMetricItem('总数', this.dailyInspirationStats.totalCount)
          this.buildInspirationMetricItem('书签', this.dailyInspirationStats.bookmarkCount)
          this.buildInspirationMetricItem('划线', this.dailyInspirationStats.highlightCount)
          this.buildInspirationMetricItem('想法', this.dailyInspirationStats.thoughtCount)
        }
        .width('100%')
      }
      .width('100%')
      .padding(16)
      .backgroundColor(this.getAnalyticsSubPanelBackground())
      .linearGradient(this.getBlurPanelSurfaceGradient())
      .backgroundBlurStyle(this.getBlurPanelBlurStyle(), this.getBlurPanelBlurOptions())
      .backgroundEffect(this.getBlurPanelBackgroundEffect())
      .borderRadius(this.getAnalyticsInnerRadius())
      .clip(true)
      .shadow({ radius: this.getAnalyticsItemShadowRadius(), color: this.getBlurPanelShadowColor(), offsetX: 0, offsetY: 3 })
      .border({ width: this.getBlurPanelBorderWidth(), color: this.getBlurPanelBorder() })
    }
    .width('100%')
    .padding(this.getAnalyticsSectionPadding())
    .backgroundColor(this.getBlurPanelBackground())
    .linearGradient(this.getBlurPanelSurfaceGradient())
    .backgroundBlurStyle(this.getBlurPanelBlurStyle(), this.getBlurPanelBlurOptions())
    .backgroundEffect(this.getBlurPanelBackgroundEffect())
    .borderRadius(this.getBlurPanelRadius())
    .clip(true)
    .shadow({ radius: this.getAnalyticsSectionShadowRadius(), color: this.getBlurPanelShadowColor(), offsetX: 0, offsetY: 4 })
    .border({ width: this.getBlurPanelBorderWidth(), color: this.getBlurPanelBorder() })
    .margin({ left: this.getAnalyticsSectionHorizontalMargin(), right: this.getAnalyticsSectionHorizontalMargin() })
  }

  /**
   * 获取模糊面板背景色
   */
  private getBlurPanelBackground(): ResourceColor {
    return SettingsPageSurfaceManager.getManagementContentSurfaceStyle(this.themeState.currentTheme).backgroundColor;
  }

  private getBlurPanelBlurStyle(): BlurStyle | undefined {
    return SettingsPageSurfaceManager.getManagementContentSurfaceStyle(this.themeState.currentTheme).blurStyle;
  }

  private getBlurPanelBlurOptions(): BackgroundBlurStyleOptions {
    return SettingsPageSurfaceManager.getManagementContentSurfaceStyle(this.themeState.currentTheme).blurOptions;
  }

  private getBlurPanelBackgroundEffect(): BackgroundEffectOptions | undefined {
    return SettingsPageSurfaceManager.getManagementContentSurfaceStyle(this.themeState.currentTheme).backgroundEffect;
  }

  private getBlurPanelRadius(): number {
    return SettingsPageSurfaceManager.getManagementContentSurfaceStyle(this.themeState.currentTheme).radius;
  }

  private getBlurPanelBorderWidth(): number {
    return SettingsPageSurfaceManager.getManagementContentSurfaceStyle(this.themeState.currentTheme).borderWidth;
  }

  private getBlurPanelSurfaceGradient(): LinearGradient {
    return SettingsPageSurfaceManager.getManagementContentSurfaceStyle(this.themeState.currentTheme).surfaceGradient;
  }

  /**
   * 获取模糊面板边框色
   */
  private getBlurPanelBorder(): ResourceColor {
    return SettingsPageSurfaceManager.getManagementContentSurfaceStyle(this.themeState.currentTheme).borderColor;
  }

  /**
   * 获取模糊面板阴影色
   */
  private getBlurPanelShadowColor(): string {
    return SettingsPageSurfaceManager.getManagementContentSurfaceStyle(this.themeState.currentTheme).shadowColor;
  }

  private getAnalyticsInnerRadius(): number {
    return Math.max(10, this.getBlurPanelRadius() - 4);
  }

  private getAnalyticsSubPanelBackground(): ResourceColor {
    return ThemeAwareHelper.getTestManagementThemedColor('comp_background_secondary', this.themeState.currentTheme);
  }

  private getAnalyticsTrackBackground(): ResourceColor {
    return ThemeAwareHelper.getTestManagementThemedColor('comp_background_tertiary', this.themeState.currentTheme);
  }

  private getAnalyticsChipBackground(): ResourceColor {
    return ThemeAwareHelper.getTestManagementThemedColor('accent_primary_dimmed', this.themeState.currentTheme);
  }

  private getAnalyticsNeutralBadgeBackground(): ResourceColor {
    return ThemeAwareHelper.getTestManagementThemedColor('comp_background_tertiary', this.themeState.currentTheme);
  }

  private getAnalyticsSectionShadowRadius(): number {
    return this.getBlurPanelRadius() + 2;
  }

  private getAnalyticsItemShadowRadius(): number {
    return Math.max(8, this.getBlurPanelRadius() - 2);
  }

  private getAnalyticsSectionGap(): number {
    if (this.responsive_isLandscape) {
      return 18;
    }
    return 16;
  }

  private getAnalyticsColumnGap(): number {
    if (this.responsive_isLandscape) {
      return 18;
    }
    return 16;
  }

  private getAnalyticsSectionPadding(): number {
    if (this.responsive_isLandscape) {
      return 18;
    }
    return 16;
  }

  private getAnalyticsInnerGap(): number {
    return 12;
  }

  private getAnalyticsSectionHorizontalMargin(): number {
    if (this.responsive_isLandscape) {
      return 0;
    }
    return this.responsive_contentPadding;
  }

  private getAnalyticsOuterHorizontalPadding(): number {
    if (this.responsive_isLandscape) {
      return this.responsive_contentPadding;
    }
    return 0;
  }

  private getAnalyticsStateHorizontalPadding(): number {
    if (this.responsive_isLandscape) {
      return this.responsive_contentPadding;
    }
    return this.getAnalyticsSectionHorizontalMargin();
  }

  private getRankBadgeBackground(index: number): ResourceColor {
    if (index < 3) {
      return ThemeAwareHelper.getTestManagementThemedColor('accent_primary', this.themeState.currentTheme);
    }
    return this.getAnalyticsNeutralBadgeBackground();
  }

  private getRankBadgeTextColor(index: number): ResourceColor {
    if (index < 3) {
      return ThemeAwareHelper.getTestManagementThemedColor('text_white', this.themeState.currentTheme);
    }
    return ThemeAwareHelper.getTestManagementThemedColor('text_secondary', this.themeState.currentTheme);
  }

  @Builder
  private buildAnalyticsSectionHeader(symbol: Resource, title: string, meta: string = '') {
    Row({ space: 6 }) {
      SymbolGlyph(symbol)
        .fontSize(18)
        .fontColor([ThemeAwareHelper.getTestManagementThemedColor('accent_primary', this.themeState.currentTheme)])
      Text(title)
        .fontSize(18)
        .fontWeight(FontWeight.Bold)
        .fontFamily(this.appFontFamily)
        .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_primary', this.themeState.currentTheme))
        .layoutWeight(1)
        .maxLines(1)
        .textOverflow({ overflow: TextOverflow.Ellipsis })

      if (meta.length > 0) {
        Text(meta)
          .fontSize(12)
          .fontFamily(this.appFontFamily)
          .fontColor(ThemeAwareHelper.getTestManagementThemedColor('accent_primary', this.themeState.currentTheme))
          .padding({ left: 10, right: 10, top: 4, bottom: 4 })
          .backgroundColor(this.getAnalyticsChipBackground())
          .borderRadius(12)
      }
    }
    .width('100%')
    .alignItems(VerticalAlign.Center)
  }

  /**
   * 构建阅读习惯分析
   */
  @Builder
  buildReadingHabits() {
    Column({ space: 12 }) {
      this.buildAnalyticsSectionHeader($r('sys.symbol.arrow_up_right'), '阅读习惯')

      // 最喜欢的阅读时段
      Column({ space: 8 }) {
        Row({ space: 8 }) {
          SymbolGlyph($r('sys.symbol.clock'))
            .fontSize(20)
            .fontColor([ThemeAwareHelper.getTestManagementThemedColor('accent_primary', this.themeState.currentTheme)])
          
          Text('最喜欢的阅读时段')
            .fontSize(14)
            .fontWeight(FontWeight.Medium)
            .fontFamily(this.appFontFamily)
            .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_primary', this.themeState.currentTheme))
            .layoutWeight(1)
          
          Text(this.statistics.favoriteReadingHour >= 0 
            ? `${this.statistics.favoriteReadingHour}:00 - ${this.statistics.favoriteReadingHour + 1}:00` 
            : '暂无数据')
            .fontSize(16)
            .fontWeight(FontWeight.Bold)
            .fontFamily(this.appFontFamily)
            .fontColor(ThemeAwareHelper.getTestManagementThemedColor('accent_blue', this.themeState.currentTheme))
        }
        .width('100%')
      }
      .width('100%')
      .padding(16)
      .backgroundColor(this.getAnalyticsSubPanelBackground())
      .linearGradient(this.getBlurPanelSurfaceGradient())
      .backgroundBlurStyle(this.getBlurPanelBlurStyle(), this.getBlurPanelBlurOptions())
      .backgroundEffect(this.getBlurPanelBackgroundEffect())
      .borderRadius(this.getAnalyticsInnerRadius())
      .clip(true)
      .shadow({ radius: this.getAnalyticsItemShadowRadius(), color: this.getBlurPanelShadowColor(), offsetX: 0, offsetY: 3 })
      .border({ width: this.getBlurPanelBorderWidth(), color: this.getBlurPanelBorder() })

      // 最后阅读时间
      if (this.statistics.lastReadTime > 0) {
        Column({ space: 8 }) {
          Row({ space: 8 }) {
            SymbolGlyph($r('sys.symbol.clock'))
              .fontSize(20)
              .fontColor([ThemeAwareHelper.getTestManagementThemedColor('accent_primary', this.themeState.currentTheme)])
            
            Text('最后阅读时间')
              .fontSize(14)
              .fontWeight(FontWeight.Medium)
              .fontFamily(this.appFontFamily)
              .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_primary', this.themeState.currentTheme))
              .layoutWeight(1)
            
            Text(this.formatDate(this.statistics.lastReadTime))
              .fontSize(16)
              .fontWeight(FontWeight.Bold)
              .fontFamily(this.appFontFamily)
              .fontColor(ThemeAwareHelper.getTestManagementThemedColor('accent_blue', this.themeState.currentTheme))
          }
          .width('100%')
        }
        .width('100%')
        .padding(16)
        .backgroundColor(this.getAnalyticsSubPanelBackground())
        .linearGradient(this.getBlurPanelSurfaceGradient())
        .backgroundBlurStyle(this.getBlurPanelBlurStyle(), this.getBlurPanelBlurOptions())
        .backgroundEffect(this.getBlurPanelBackgroundEffect())
        .borderRadius(this.getAnalyticsInnerRadius())
        .clip(true)
        .shadow({ radius: this.getAnalyticsItemShadowRadius(), color: this.getBlurPanelShadowColor(), offsetX: 0, offsetY: 3 })
        .border({ width: this.getBlurPanelBorderWidth(), color: this.getBlurPanelBorder() })
      }

      // 阅读最多的漫画
      if (this.statistics.mostReadComicId.length > 0) {
        Column({ space: 8 }) {
          Row({ space: 8 }) {
            SymbolGlyph($r('sys.symbol.star'))
              .fontSize(20)
              .fontColor([ThemeAwareHelper.getTestManagementThemedColor('accent_primary', this.themeState.currentTheme)])
            
            Text('阅读最多的漫画')
              .fontSize(14)
              .fontWeight(FontWeight.Medium)
              .fontFamily(this.appFontFamily)
              .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_primary', this.themeState.currentTheme))
              .layoutWeight(1)
          }
          .width('100%')
          
          Text(this.statistics.mostReadComicTitle)
            .fontSize(14)
            .fontFamily(this.appFontFamily)
            .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_secondary', this.themeState.currentTheme))
            .maxLines(2)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
            .width('100%')
        }
        .width('100%')
        .padding(16)
        .backgroundColor(this.getAnalyticsSubPanelBackground())
        .linearGradient(this.getBlurPanelSurfaceGradient())
        .backgroundBlurStyle(this.getBlurPanelBlurStyle(), this.getBlurPanelBlurOptions())
        .backgroundEffect(this.getBlurPanelBackgroundEffect())
        .borderRadius(this.getAnalyticsInnerRadius())
        .clip(true)
        .shadow({ radius: this.getAnalyticsItemShadowRadius(), color: this.getBlurPanelShadowColor(), offsetX: 0, offsetY: 3 })
        .border({ width: this.getBlurPanelBorderWidth(), color: this.getBlurPanelBorder() })
        .alignItems(HorizontalAlign.Start)
      }

      // 阅读最多的电子书
      if (this.statistics.mostReadEBookId.length > 0) {
        Column({ space: 8 }) {
          Row({ space: 8 }) {
            SymbolGlyph($r('sys.symbol.book'))
              .fontSize(20)
              .fontColor([ThemeAwareHelper.getTestManagementThemedColor('accent_primary', this.themeState.currentTheme)])
            
            Text('阅读最多的电子书')
              .fontSize(14)
              .fontWeight(FontWeight.Medium)
              .fontFamily(this.appFontFamily)
              .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_primary', this.themeState.currentTheme))
              .layoutWeight(1)
          }
          .width('100%')
          
          Text(this.statistics.mostReadEBookTitle)
            .fontSize(14)
            .fontFamily(this.appFontFamily)
            .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_secondary', this.themeState.currentTheme))
            .maxLines(2)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
            .width('100%')
        }
        .width('100%')
        .padding(16)
        .backgroundColor(this.getAnalyticsSubPanelBackground())
        .linearGradient(this.getBlurPanelSurfaceGradient())
        .backgroundBlurStyle(this.getBlurPanelBlurStyle(), this.getBlurPanelBlurOptions())
        .backgroundEffect(this.getBlurPanelBackgroundEffect())
        .borderRadius(this.getAnalyticsInnerRadius())
        .clip(true)
        .shadow({ radius: this.getAnalyticsItemShadowRadius(), color: this.getBlurPanelShadowColor(), offsetX: 0, offsetY: 3 })
        .border({ width: this.getBlurPanelBorderWidth(), color: this.getBlurPanelBorder() })
        .alignItems(HorizontalAlign.Start)
      }
    }
    .width('100%')
    .padding(16)
    .backgroundColor(this.getBlurPanelBackground())
    .linearGradient(this.getBlurPanelSurfaceGradient())
    .backgroundBlurStyle(this.getBlurPanelBlurStyle(), this.getBlurPanelBlurOptions())
    .backgroundEffect(this.getBlurPanelBackgroundEffect())
    .borderRadius(this.getBlurPanelRadius())
    .clip(true)
    .shadow({ radius: this.getAnalyticsSectionShadowRadius(), color: this.getBlurPanelShadowColor(), offsetX: 0, offsetY: 4 })
    .border({ width: this.getBlurPanelBorderWidth(), color: this.getBlurPanelBorder() })
    .margin({ left: this.getAnalyticsSectionHorizontalMargin(), right: this.getAnalyticsSectionHorizontalMargin() })
  }

  /**
   * 构建每日阅读趋势
   */
  @Builder
  buildDailyTrend() {
    if (this.dailyData.length > 0) {
      Column({ space: 12 }) {
        this.buildAnalyticsSectionHeader($r('sys.symbol.calendar'), '每日阅读趋势')

        Column({ space: 8 }) {
          ForEach(this.dailyData.slice(0, 7), (data: DailyReadingData, index: number) => {
            Row({ space: 12 }) {
              Text(data.date)
                .fontSize(12)
                .fontFamily(this.appFontFamily)
                .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_secondary', this.themeState.currentTheme))
                .width(90)
              
              Column({ space: 4 }) {
                Row({ space: 4 }) {
                  SymbolGlyph($r('sys.symbol.clock')).fontSize(12).fontColor([ThemeAwareHelper.getTestManagementThemedColor('text_secondary', this.themeState.currentTheme)])
                  Text(this.formatDuration(data.readingTime))
                    .fontSize(12)
                    .fontFamily(this.appFontFamily)
                    .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_primary', this.themeState.currentTheme))
                }
                
                Row({ space: 4 }) {
                  SymbolGlyph($r('sys.symbol.book')).fontSize(12).fontColor([ThemeAwareHelper.getTestManagementThemedColor('text_secondary', this.themeState.currentTheme)])
                  Text(`${data.chaptersRead}章 / ${data.pagesRead}页`)
                    .fontSize(12)
                    .fontFamily(this.appFontFamily)
                    .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_secondary', this.themeState.currentTheme))
                }
              }
              .alignItems(HorizontalAlign.Start)
              .layoutWeight(1)
            }
            .width('100%')
            .padding(12)
            .backgroundColor(this.getAnalyticsSubPanelBackground())
            .linearGradient(this.getBlurPanelSurfaceGradient())
            .backgroundBlurStyle(this.getBlurPanelBlurStyle(), this.getBlurPanelBlurOptions())
            .backgroundEffect(this.getBlurPanelBackgroundEffect())
            .borderRadius(this.getAnalyticsInnerRadius())
            .clip(true)
            .shadow({ radius: this.getAnalyticsItemShadowRadius(), color: this.getBlurPanelShadowColor(), offsetX: 0, offsetY: 2 })
            .border({ width: this.getBlurPanelBorderWidth(), color: this.getBlurPanelBorder() })
          }, (data: DailyReadingData, index: number) => `${data.date}-${index}`)
        }
        .width('100%')
      }
      .width('100%')
      .padding(16)
      .backgroundColor(this.getBlurPanelBackground())
      .linearGradient(this.getBlurPanelSurfaceGradient())
      .backgroundBlurStyle(this.getBlurPanelBlurStyle(), this.getBlurPanelBlurOptions())
      .backgroundEffect(this.getBlurPanelBackgroundEffect())
      .borderRadius(this.getBlurPanelRadius())
      .clip(true)
      .shadow({ radius: this.getAnalyticsSectionShadowRadius(), color: this.getBlurPanelShadowColor(), offsetX: 0, offsetY: 4 })
      .border({ width: this.getBlurPanelBorderWidth(), color: this.getBlurPanelBorder() })
      .margin({ left: this.getAnalyticsSectionHorizontalMargin(), right: this.getAnalyticsSectionHorizontalMargin() })
    }
  }

  /**
   * 构建兴趣分析
   */
  @Builder
  buildInterestAnalysis() {
    if (this.interestItems.length > 0) {
      Column({ space: 12 }) {
        this.buildAnalyticsSectionHeader($r('sys.symbol.lightbulb'), '您可能感兴趣的')

        // 兴趣标签云 - 带模糊效果容器
        Column() {
          Flex({ wrap: FlexWrap.Wrap, justifyContent: FlexAlign.Start }) {
            ForEach(this.interestItems, (item: InterestItem, index: number) => {
              Row({ space: 4 }) {
                SymbolGlyph($r(item.type === 'tag' ? 'sys.symbol.bookmark' : (item.type === 'author' ? 'sys.symbol.person' : 'sys.symbol.doc_text'))).fontSize(12).fontColor([ThemeAwareHelper.getTestManagementThemedColor('text_secondary', this.themeState.currentTheme)])
                Text(item.keyword)
                  .fontSize(13)
                  .fontFamily(this.appFontFamily)
                  .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_primary', this.themeState.currentTheme))
                Text(`(${item.count})`)
                  .fontSize(11)
                  .fontFamily(this.appFontFamily)
                  .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_muted', this.themeState.currentTheme))
              }
              .padding({ left: 10, right: 10, top: 6, bottom: 6 })
              .backgroundColor(this.getAnalyticsNeutralBadgeBackground())
              .borderRadius(16)
              .margin({ right: 8, bottom: 8 })
            }, (item: InterestItem, index: number) => `${item.keyword}-${index}`)
          }
          .width('100%')
        }
        .width('100%')
        .padding(16)
        .backgroundColor(this.getAnalyticsSubPanelBackground())
        .linearGradient(this.getBlurPanelSurfaceGradient())
        .backgroundBlurStyle(this.getBlurPanelBlurStyle(), this.getBlurPanelBlurOptions())
        .backgroundEffect(this.getBlurPanelBackgroundEffect())
        .borderRadius(this.getAnalyticsInnerRadius())
        .clip(true)
        .shadow({ radius: this.getAnalyticsItemShadowRadius(), color: this.getBlurPanelShadowColor(), offsetX: 0, offsetY: 3 })
        .border({ width: this.getBlurPanelBorderWidth(), color: this.getBlurPanelBorder() })
      }
      .width('100%')
      .padding(16)
      .backgroundColor(this.getBlurPanelBackground())
      .linearGradient(this.getBlurPanelSurfaceGradient())
      .backgroundBlurStyle(this.getBlurPanelBlurStyle(), this.getBlurPanelBlurOptions())
      .backgroundEffect(this.getBlurPanelBackgroundEffect())
      .borderRadius(this.getBlurPanelRadius())
      .clip(true)
      .shadow({ radius: this.getAnalyticsSectionShadowRadius(), color: this.getBlurPanelShadowColor(), offsetX: 0, offsetY: 4 })
      .border({ width: this.getBlurPanelBorderWidth(), color: this.getBlurPanelBorder() })
      .margin({ left: this.getAnalyticsSectionHorizontalMargin(), right: this.getAnalyticsSectionHorizontalMargin() })
    }
  }

  /**
   * 构建阅读时长排行
   */
  @Builder
  buildReadingRank() {
    if (this.readingRankList.length > 0) {
      Column({ space: 12 }) {
        this.buildAnalyticsSectionHeader($r('sys.symbol.histogram'), '阅读时长排行')

        // 排行列表 - 网格展示
        Grid() {
          ForEach(this.readingRankList, (item: ReadingRankItem, index: number) => {
            GridItem() {
              Column({ space: 8 }) {
                // 封面图片
                Stack() {
                  if (item.coverPath && item.coverPath.length > 0) {
                    Image(this.normalizeCoverPath(item.coverPath, item.type === 'ebook'))
                      .width('100%')
                      .aspectRatio(0.7)
                      .objectFit(ImageFit.Cover)
                      .borderRadius(8)
                  } else if (item.type === 'ebook') {
                    // 电子书无封面时使用默认电子书图标
                    Image($r('app.media.ebook'))
                      .width('100%')
                      .aspectRatio(0.7)
                      .objectFit(ImageFit.Cover)
                      .borderRadius(8)
                  } else {
                    Column() {
                      SymbolGlyph($r('sys.symbol.book'))
                        .fontSize(32)
                        .fontColor([ThemeAwareHelper.getTestManagementThemedColor('text_tertiary', this.themeState.currentTheme)])
                  }
                  .width('100%')
                  .aspectRatio(0.7)
                  .backgroundColor(this.getBlurPanelBackground())
                  .borderRadius(8)
                  .justifyContent(FlexAlign.Center)
                }
                  
                  // 排名标签
                  Text(`${index + 1}`)
                    .fontSize(12)
                    .fontFamily(this.appFontFamily)
                    .fontWeight(FontWeight.Bold)
                    .fontColor(this.getRankBadgeTextColor(index))
                    .padding({ left: 8, right: 8, top: 4, bottom: 4 })
                    .backgroundColor(this.getRankBadgeBackground(index))
                    .borderRadius(4)
                    .position({ x: 4, y: 4 })
                }
                .width('100%')

                // 标题
                Text(item.title)
                  .fontSize(12)
                  .fontFamily(this.appFontFamily)
                  .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_primary', this.themeState.currentTheme))
                  .maxLines(2)
                  .textOverflow({ overflow: TextOverflow.Ellipsis })
                  .width('100%')

                // 阅读时长
                Text(this.formatDuration(item.readingTime))
                  .fontSize(11)
                  .fontFamily(this.appFontFamily)
                  .fontColor(ThemeAwareHelper.getTestManagementThemedColor('accent_blue', this.themeState.currentTheme))
              }
              .width('100%')
              .onClick(() => {
                this.navigateToDetail(item);
              })
            }
          }, (item: ReadingRankItem, index: number) => `${item.id}-${index}`)
        }
        .columnsTemplate('1fr 1fr 1fr')
        .rowsGap(12)
        .columnsGap(12)
        .width('100%')
      }
      .width('100%')
      .padding(16)
      .backgroundColor(this.getBlurPanelBackground())
      .linearGradient(this.getBlurPanelSurfaceGradient())
      .backgroundBlurStyle(this.getBlurPanelBlurStyle(), this.getBlurPanelBlurOptions())
      .backgroundEffect(this.getBlurPanelBackgroundEffect())
      .borderRadius(this.getBlurPanelRadius())
      .clip(true)
      .shadow({ radius: this.getAnalyticsSectionShadowRadius(), color: this.getBlurPanelShadowColor(), offsetX: 0, offsetY: 4 })
      .border({ width: this.getBlurPanelBorderWidth(), color: this.getBlurPanelBorder() })
      .margin({ left: this.getAnalyticsSectionHorizontalMargin(), right: this.getAnalyticsSectionHorizontalMargin() })
    }
  }

  /**
   * 构建设置区域
   */
  @Builder
  buildSettingsSection() {
    Column({ space: 12 }) {
      this.buildAnalyticsSectionHeader($r('sys.symbol.gearshape'), '设置')

      // 数据保留天数设置
      Row() {
        Text('数据保留天数')
          .fontSize(14)
          .fontFamily(this.appFontFamily)
          .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_primary', this.themeState.currentTheme))
          .layoutWeight(1)
        
        Text(`${RETENTION_DAYS_OPTIONS[this.retentionDaysIndex]}天`)
          .fontSize(14)
          .fontFamily(this.appFontFamily)
          .fontColor(ThemeAwareHelper.getTestManagementThemedColor('accent_blue', this.themeState.currentTheme))
        
        SymbolGlyph($r('sys.symbol.arrow_right'))
          .fontSize(16)
          .fontColor([ThemeAwareHelper.getTestManagementThemedColor('text_muted', this.themeState.currentTheme)])
          .margin({ left: 4 })
      }
      .width('100%')
      .padding(16)
      .backgroundColor(this.getAnalyticsSubPanelBackground())
      .linearGradient(this.getBlurPanelSurfaceGradient())
      .backgroundBlurStyle(this.getBlurPanelBlurStyle(), this.getBlurPanelBlurOptions())
      .backgroundEffect(this.getBlurPanelBackgroundEffect())
      .borderRadius(this.getAnalyticsInnerRadius())
      .clip(true)
      .shadow({ radius: this.getAnalyticsItemShadowRadius(), color: this.getBlurPanelShadowColor(), offsetX: 0, offsetY: 3 })
      .border({ width: this.getBlurPanelBorderWidth(), color: this.getBlurPanelBorder() })
      .onClick(() => {
        this.showRetentionDaysPicker();
      })

      // 阅读报告开关
      Row() {
        Text('启用阅读数据收集')
          .fontSize(14)
          .fontFamily(this.appFontFamily)
          .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_primary', this.themeState.currentTheme))
          .layoutWeight(1)
        
        // 使用条件渲染确保 Toggle 在数据加载后正确显示状态
        if (this.analyticsEnabled) {
          Toggle({ type: ToggleType.Switch, isOn: true })
            .selectedColor(ThemeAwareHelper.getTestManagementThemedColor('accent_blue', this.themeState.currentTheme))
            .onChange(async (isOn: boolean) => {
              logger.info(TAG, `开关切换: ${isOn}`);
              this.analyticsEnabled = isOn;
              await this.analyticsManager.setEnabled(isOn);
            })
        } else {
          Toggle({ type: ToggleType.Switch, isOn: false })
            .selectedColor(ThemeAwareHelper.getTestManagementThemedColor('accent_blue', this.themeState.currentTheme))
            .onChange(async (isOn: boolean) => {
              logger.info(TAG, `开关切换: ${isOn}`);
              this.analyticsEnabled = isOn;
              await this.analyticsManager.setEnabled(isOn);
            })
        }
      }
      .width('100%')
      .padding(16)
      .backgroundColor(this.getAnalyticsSubPanelBackground())
      .linearGradient(this.getBlurPanelSurfaceGradient())
      .backgroundBlurStyle(this.getBlurPanelBlurStyle(), this.getBlurPanelBlurOptions())
      .backgroundEffect(this.getBlurPanelBackgroundEffect())
      .borderRadius(this.getAnalyticsInnerRadius())
      .clip(true)
      .shadow({ radius: this.getAnalyticsItemShadowRadius(), color: this.getBlurPanelShadowColor(), offsetX: 0, offsetY: 3 })
      .border({ width: this.getBlurPanelBorderWidth(), color: this.getBlurPanelBorder() })

      Text('关闭后将停止收集阅读数据，但不会删除已有数据')
        .fontSize(12)
        .fontFamily(this.appFontFamily)
        .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_muted', this.themeState.currentTheme))
        .width('100%')
    }
    .width('100%')
    .padding(16)
    .backgroundColor(this.getBlurPanelBackground())
    .linearGradient(this.getBlurPanelSurfaceGradient())
    .backgroundBlurStyle(this.getBlurPanelBlurStyle(), this.getBlurPanelBlurOptions())
    .backgroundEffect(this.getBlurPanelBackgroundEffect())
    .borderRadius(this.getBlurPanelRadius())
    .clip(true)
    .shadow({ radius: this.getAnalyticsSectionShadowRadius(), color: this.getBlurPanelShadowColor(), offsetX: 0, offsetY: 4 })
    .border({ width: this.getBlurPanelBorderWidth(), color: this.getBlurPanelBorder() })
    .margin({ left: this.getAnalyticsSectionHorizontalMargin(), right: this.getAnalyticsSectionHorizontalMargin() })
  }

  /**
   * 构建加载状态
   */
  @Builder
  buildLoadingState() {
    Column({ space: 16 }) {
      LoadingProgress()
        .width(48)
        .height(48)
        .color(ThemeAwareHelper.getTestManagementThemedColor('accent_blue', this.themeState.currentTheme))
      
      Text('正在加载阅读数据...')
        .fontSize(14)
        .fontFamily(this.appFontFamily)
        .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_secondary', this.themeState.currentTheme))
    }
    .width('100%')
    .height('80%')
    .padding({ left: this.getAnalyticsStateHorizontalPadding(), right: this.getAnalyticsStateHorizontalPadding() })
    .alignItems(HorizontalAlign.Center)
    .justifyContent(FlexAlign.Center)
  }

  /**
   * 构建空状态
   */
  @Builder
  buildEmptyState() {
    Column({ space: 16 }) {
      SymbolGlyph($r('sys.symbol.book'))
        .fontSize(64)
        .fontColor([ThemeAwareHelper.getTestManagementThemedColor('text_tertiary', this.themeState.currentTheme)])
      
      Text('暂未收集到有效的阅读数据')
        .fontSize(18)
        .fontWeight(FontWeight.Medium)
        .fontFamily(this.appFontFamily)
        .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_primary', this.themeState.currentTheme))
      
      Text('开始阅读漫画/电子书后，这里将显示您的阅读统计和分析数据\n请在阅读更长时间后查看')
        .fontSize(14)
        .fontFamily(this.appFontFamily)
        .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_secondary', this.themeState.currentTheme))
        .textAlign(TextAlign.Center)
        .width('80%')
    }
    .width('100%')
    .height('80%')
    .padding({ left: this.getAnalyticsStateHorizontalPadding(), right: this.getAnalyticsStateHorizontalPadding() })
    .alignItems(HorizontalAlign.Center)
    .justifyContent(FlexAlign.Center)
  }

  /**
   * 构建权限请求界面
   */
  @Builder
  buildPermissionRequest() {
    Column({ space: 24 }) {
      // 图标
      SymbolGlyph($r('sys.symbol.doc_plaintext'))
        .fontSize(80)
        .fontColor([ThemeAwareHelper.getTestManagementThemedColor('accent_primary', this.themeState.currentTheme)])
      
      // 标题
      Text('阅读报告')
        .fontSize(24)
        .fontWeight(FontWeight.Bold)
        .fontFamily(this.appFontFamily)
        .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_primary', this.themeState.currentTheme))
      
      // 副标题
      Text('了解您的阅读习惯')
        .fontSize(16)
        .fontFamily(this.appFontFamily)
        .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_secondary', this.themeState.currentTheme))
      
      // 说明文字
      Column({ space: 12 }) {
        Text('开启阅读报告功能后，应用将收集以下数据：')
          .fontSize(14)
          .fontFamily(this.appFontFamily)
          .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_primary', this.themeState.currentTheme))
          .width('100%')
        
        Column({ space: 8 }) {
          this.buildPermissionItemWithSymbol($r('sys.symbol.clock'), '阅读时长', '记录您每次阅读的时长')
          this.buildPermissionItemWithSymbol($r('sys.symbol.book'), '阅读进度', '记录您阅读的章节和页数')
          this.buildPermissionItemWithSymbol($r('sys.symbol.calendar'), '阅读习惯', '分析您的阅读时段偏好')
          this.buildPermissionItemWithSymbol($r('sys.symbol.bookmark'), '兴趣分析', '根据阅读内容分析您的兴趣')
        }
        .width('100%')
        .padding(16)
        .backgroundColor(this.getBlurPanelBackground())
        .linearGradient(this.getBlurPanelSurfaceGradient())
        .backgroundBlurStyle(this.getBlurPanelBlurStyle(), this.getBlurPanelBlurOptions())
        .backgroundEffect(this.getBlurPanelBackgroundEffect())
        .borderRadius(this.getBlurPanelRadius())
        .clip(true)
        .shadow({ radius: this.getBlurPanelRadius() + 2, color: this.getBlurPanelShadowColor(), offsetX: 0, offsetY: 4 })
        .border({ width: this.getBlurPanelBorderWidth(), color: this.getBlurPanelBorder() })
        
        Text('这些数据仅存储在本地，不会上传到任何服务器。您可以随时在设置中关闭此功能或清除数据。')
          .fontSize(12)
          .fontFamily(this.appFontFamily)
          .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_muted', this.themeState.currentTheme))
          .width('100%')
          .textAlign(TextAlign.Center)
      }
      .width('100%')
      .margin({ top: 16 })
      
      // 按钮区域
      Row({ space: 16 }) {
        // 拒绝按钮
        Button('拒绝')
          .fontSize(16)
          .fontFamily(this.appFontFamily)
          .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_primary', this.themeState.currentTheme))
          .backgroundColor(ThemeAwareHelper.getTestManagementThemedColor('button_background', this.themeState.currentTheme))
          .borderRadius(24)
          .height(48)
          .layoutWeight(1)
          .onClick(() => {
            this.handleRejectPermission();
          })
        
        // 同意按钮
        Button('同意并开启')
          .fontSize(16)
          .fontFamily(this.appFontFamily)
          .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_white', this.themeState.currentTheme))
          .backgroundColor(ThemeAwareHelper.getTestManagementThemedColor('accent_blue', this.themeState.currentTheme))
          .borderRadius(24)
          .height(48)
          .layoutWeight(1)
          .onClick(() => {
            this.handleAcceptPermission();
          })
      }
      .width('100%')
      .margin({ top: 32 })
    }
    .width('100%')
    .constraintSize({ maxWidth: this.responsive_maxContentWidth })
    .height('100%')
    .padding({ left: this.getAnalyticsStateHorizontalPadding(), right: this.getAnalyticsStateHorizontalPadding(), bottom: 60 })
    .alignItems(HorizontalAlign.Center)
    .justifyContent(FlexAlign.Center)
  }
  
  /**
   * 构建权限项（使用Symbol图标）
   */
  @Builder
  buildPermissionItemWithSymbol(iconRes: Resource, title: string, description: string) {
    Row({ space: 12 }) {
      SymbolGlyph(iconRes)
        .fontSize(20)
        .fontColor([ThemeAwareHelper.getTestManagementThemedColor('accent_primary', this.themeState.currentTheme)])
      
      Column({ space: 2 }) {
        Text(title)
          .fontSize(14)
          .fontWeight(FontWeight.Medium)
          .fontFamily(this.appFontFamily)
          .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_primary', this.themeState.currentTheme))
        
        Text(description)
          .fontSize(12)
          .fontFamily(this.appFontFamily)
          .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_muted', this.themeState.currentTheme))
      }
      .alignItems(HorizontalAlign.Start)
      .layoutWeight(1)
    }
    .width('100%')
  }

  /**
   * 构建权限项
   */
  @Builder
  buildPermissionItem(icon: string, title: string, description: string) {
    Row({ space: 12 }) {
      Text(icon)
        .fontSize(20)
        .fontFamily(this.appFontFamily)
      
      Column({ space: 2 }) {
        Text(title)
          .fontSize(14)
          .fontWeight(FontWeight.Medium)
          .fontFamily(this.appFontFamily)
          .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_primary', this.themeState.currentTheme))
        
        Text(description)
          .fontSize(12)
          .fontFamily(this.appFontFamily)
          .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_muted', this.themeState.currentTheme))
      }
      .alignItems(HorizontalAlign.Start)
      .layoutWeight(1)
    }
    .width('100%')
  }
  
  /**
   * 关闭目标设置对话框（带动画）
   */
  private closeGoalSettingDialog(): void {
    this.goalDialogVisible = false;
    setTimeout(() => {
      this.showGoalSettingDialog = false;
      // 刷新日视图数据以更新目标完成情况
      if (!this.isLongTermView) {
        this.loadDailyViewData(this.selectedDate);
      }
      // 同步更新桌面卡片数据
      widgetDataSync.syncAllData().catch((e: Error) => {
        logger.warn(TAG, `同步卡片数据失败: ${e.message}`);
      });
    }, 250);
  }
  
  /**
   * 打开目标设置对话框（带动画）
   */
  private openGoalSettingDialog(): void {
    // 同步状态变量
    this.mangaGoalValue = this.readingGoals.mangaGoalMinutes;
    this.ebookGoalValue = this.readingGoals.ebookGoalMinutes;
    this.novelGoalValue = this.readingGoals.novelGoalMinutes;
    this.showGoalSettingDialog = true;
    setTimeout(() => {
      this.goalDialogVisible = true;
    }, 16);
  }

  /**
   * 构建阅读目标设置对话框
   */
  @Builder
  buildGoalSettingDialog() {
    Column() {
      // 遮罩层
      Column()
        .width('100%')
        .height('100%')
        .backgroundColor(this.goalDialogVisible ? '#80000000' : '#00000000')
        .animation({ duration: 250, curve: Curve.EaseOut })
        .onClick(() => {
          this.closeGoalSettingDialog();
        })
    }
    .width('100%')
    .height('100%')
    .position({ x: 0, y: 0 })
    
    // 对话框内容
    Column({ space: 16 }) {
      // 标题
      Text('设置阅读目标')
        .fontSize(18)
        .fontWeight(FontWeight.Bold)
        .fontFamily(this.appFontFamily)
        .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_primary', this.themeState.currentTheme))
      
      Text('拖动滑块设置每日阅读时间目标')
        .fontSize(13)
        .fontFamily(this.appFontFamily)
        .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_secondary', this.themeState.currentTheme))
      
      // 漫画目标设置
      this.buildMangaGoalSlider()
      
      // 电子书目标设置
      this.buildEbookGoalSlider()
      
      // 小说目标设置
      this.buildNovelGoalSlider()
      
      // 关闭按钮
      Button('完成')
        .fontSize(15)
        .fontFamily(this.appFontFamily)
        .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_white', this.themeState.currentTheme))
        .backgroundColor(ThemeAwareHelper.getTestManagementThemedColor('accent_primary', this.themeState.currentTheme))
        .borderRadius(20)
        .height(44)
        .width('100%')
        .margin({ top: 8 })
        .onClick(() => {
          this.closeGoalSettingDialog();
        })
    }
    .width('85%')
    .constraintSize({ maxWidth: 400 })
    .padding(24)
    .backgroundColor(this.getBlurPanelBackground())
    .linearGradient(this.getBlurPanelSurfaceGradient())
    .backgroundBlurStyle(this.getBlurPanelBlurStyle(), this.getBlurPanelBlurOptions())
    .backgroundEffect(this.getBlurPanelBackgroundEffect())
    .borderRadius(this.getBlurPanelRadius())
    .clip(true)
    .shadow({ radius: this.getBlurPanelRadius() + 4, color: this.getBlurPanelShadowColor(), offsetX: 0, offsetY: 6 })
    .border({ width: this.getBlurPanelBorderWidth(), color: this.getBlurPanelBorder() })
    .position({ x: '50%', y: '50%' })
    .translate({ x: '-50%', y: '-50%' })
    .scale({ x: this.goalDialogVisible ? 1 : 0.9, y: this.goalDialogVisible ? 1 : 0.9 })
    .opacity(this.goalDialogVisible ? 1 : 0)
    .animation({ duration: 250, curve: Curve.EaseOut })
  }
  
  /**
   * 构建漫画目标滑动条
   */
  @Builder
  buildMangaGoalSlider() {
    Column({ space: 8 }) {
      Row({ space: 8 }) {
        SymbolGlyph($r('sys.symbol.picture'))
          .fontSize(18)
          .fontColor([ThemeAwareHelper.getTestManagementThemedColor('accent_primary', this.themeState.currentTheme)])
        
        Text('漫画')
          .fontSize(14)
          .fontWeight(FontWeight.Medium)
          .fontFamily(this.appFontFamily)
          .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_primary', this.themeState.currentTheme))
        
        Blank()
        
        Text(this.mangaGoalValue > 0 ? `${this.mangaGoalValue}分钟/天` : '未设置')
          .fontSize(13)
          .fontFamily(this.appFontFamily)
          .fontColor(this.mangaGoalValue > 0 
            ? ThemeAwareHelper.getTestManagementThemedColor('accent_blue', this.themeState.currentTheme)
            : ThemeAwareHelper.getTestManagementThemedColor('text_muted', this.themeState.currentTheme))
      }
      .width('100%')
      
      Row({ space: 8 }) {
        Text('0')
          .fontSize(11)
          .fontFamily(this.appFontFamily)
          .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_muted', this.themeState.currentTheme))
        
        Slider({
          value: this.mangaGoalValue,
          min: 0,
          max: 180,
          step: 5
        })
          .layoutWeight(1)
          .blockColor(ThemeAwareHelper.getTestManagementThemedColor('accent_blue', this.themeState.currentTheme))
          .trackColor(this.getAnalyticsTrackBackground())
          .selectedColor(ThemeAwareHelper.getTestManagementThemedColor('accent_blue', this.themeState.currentTheme))
          .showSteps(false)
          .showTips(false)
          .onChange((value: number) => {
            this.mangaGoalValue = Math.round(value);
            this.readingGoals.mangaGoalMinutes = this.mangaGoalValue;
            this.analyticsManager.setMangaGoal(this.mangaGoalValue);
          })
        
        Text('180')
          .fontSize(11)
          .fontFamily(this.appFontFamily)
          .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_muted', this.themeState.currentTheme))
      }
      .width('100%')
    }
    .width('100%')
    .padding(12)
    .backgroundColor(this.getAnalyticsSubPanelBackground())
    .linearGradient(this.getBlurPanelSurfaceGradient())
    .backgroundBlurStyle(this.getBlurPanelBlurStyle(), this.getBlurPanelBlurOptions())
    .backgroundEffect(this.getBlurPanelBackgroundEffect())
    .borderRadius(this.getAnalyticsInnerRadius())
    .clip(true)
    .shadow({ radius: this.getAnalyticsItemShadowRadius(), color: this.getBlurPanelShadowColor(), offsetX: 0, offsetY: 3 })
    .border({ width: this.getBlurPanelBorderWidth(), color: this.getBlurPanelBorder() })
  }
  
  /**
   * 构建电子书目标滑动条
   */
  @Builder
  buildEbookGoalSlider() {
    Column({ space: 8 }) {
      Row({ space: 8 }) {
        SymbolGlyph($r('sys.symbol.book'))
          .fontSize(18)
          .fontColor([ThemeAwareHelper.getTestManagementThemedColor('accent_primary', this.themeState.currentTheme)])
        
        Text('电子书')
          .fontSize(14)
          .fontWeight(FontWeight.Medium)
          .fontFamily(this.appFontFamily)
          .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_primary', this.themeState.currentTheme))
        
        Blank()
        
        Text(this.ebookGoalValue > 0 ? `${this.ebookGoalValue}分钟/天` : '未设置')
          .fontSize(13)
          .fontFamily(this.appFontFamily)
          .fontColor(this.ebookGoalValue > 0 
            ? ThemeAwareHelper.getTestManagementThemedColor('accent_blue', this.themeState.currentTheme)
            : ThemeAwareHelper.getTestManagementThemedColor('text_muted', this.themeState.currentTheme))
      }
      .width('100%')
      
      Row({ space: 8 }) {
        Text('0')
          .fontSize(11)
          .fontFamily(this.appFontFamily)
          .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_muted', this.themeState.currentTheme))
        
        Slider({
          value: this.ebookGoalValue,
          min: 0,
          max: 180,
          step: 5
        })
          .layoutWeight(1)
          .blockColor(ThemeAwareHelper.getTestManagementThemedColor('accent_blue', this.themeState.currentTheme))
          .trackColor(this.getAnalyticsTrackBackground())
          .selectedColor(ThemeAwareHelper.getTestManagementThemedColor('accent_blue', this.themeState.currentTheme))
          .showSteps(false)
          .showTips(false)
          .onChange((value: number) => {
            this.ebookGoalValue = Math.round(value);
            this.readingGoals.ebookGoalMinutes = this.ebookGoalValue;
            this.analyticsManager.setEbookGoal(this.ebookGoalValue);
          })
        
        Text('180')
          .fontSize(11)
          .fontFamily(this.appFontFamily)
          .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_muted', this.themeState.currentTheme))
      }
      .width('100%')
    }
    .width('100%')
    .padding(12)
    .backgroundColor(this.getAnalyticsSubPanelBackground())
    .linearGradient(this.getBlurPanelSurfaceGradient())
    .backgroundBlurStyle(this.getBlurPanelBlurStyle(), this.getBlurPanelBlurOptions())
    .backgroundEffect(this.getBlurPanelBackgroundEffect())
    .borderRadius(this.getAnalyticsInnerRadius())
    .clip(true)
    .shadow({ radius: this.getAnalyticsItemShadowRadius(), color: this.getBlurPanelShadowColor(), offsetX: 0, offsetY: 3 })
    .border({ width: this.getBlurPanelBorderWidth(), color: this.getBlurPanelBorder() })
  }
  
  /**
   * 构建小说目标滑动条
   */
  @Builder
  buildNovelGoalSlider() {
    Column({ space: 8 }) {
      Row({ space: 8 }) {
        SymbolGlyph($r('sys.symbol.doc_text'))
          .fontSize(18)
          .fontColor([ThemeAwareHelper.getTestManagementThemedColor('accent_primary', this.themeState.currentTheme)])
        
        Text('小说')
          .fontSize(14)
          .fontWeight(FontWeight.Medium)
          .fontFamily(this.appFontFamily)
          .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_primary', this.themeState.currentTheme))
        
        Blank()
        
        Text(this.novelGoalValue > 0 ? `${this.novelGoalValue}分钟/天` : '未设置')
          .fontSize(13)
          .fontFamily(this.appFontFamily)
          .fontColor(this.novelGoalValue > 0 
            ? ThemeAwareHelper.getTestManagementThemedColor('accent_blue', this.themeState.currentTheme)
            : ThemeAwareHelper.getTestManagementThemedColor('text_muted', this.themeState.currentTheme))
      }
      .width('100%')
      
      Row({ space: 8 }) {
        Text('0')
          .fontSize(11)
          .fontFamily(this.appFontFamily)
          .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_muted', this.themeState.currentTheme))
        
        Slider({
          value: this.novelGoalValue,
          min: 0,
          max: 180,
          step: 5
        })
          .layoutWeight(1)
          .blockColor(ThemeAwareHelper.getTestManagementThemedColor('accent_blue', this.themeState.currentTheme))
          .trackColor(this.getAnalyticsTrackBackground())
          .selectedColor(ThemeAwareHelper.getTestManagementThemedColor('accent_blue', this.themeState.currentTheme))
          .showSteps(false)
          .showTips(false)
          .onChange((value: number) => {
            this.novelGoalValue = Math.round(value);
            this.readingGoals.novelGoalMinutes = this.novelGoalValue;
            this.analyticsManager.setNovelGoal(this.novelGoalValue);
          })
        
        Text('180')
          .fontSize(11)
          .fontFamily(this.appFontFamily)
          .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_muted', this.themeState.currentTheme))
      }
      .width('100%')
    }
    .width('100%')
    .padding(12)
    .backgroundColor(this.getAnalyticsSubPanelBackground())
    .linearGradient(this.getBlurPanelSurfaceGradient())
    .backgroundBlurStyle(this.getBlurPanelBlurStyle(), this.getBlurPanelBlurOptions())
    .backgroundEffect(this.getBlurPanelBackgroundEffect())
    .borderRadius(this.getAnalyticsInnerRadius())
    .clip(true)
    .shadow({ radius: this.getAnalyticsItemShadowRadius(), color: this.getBlurPanelShadowColor(), offsetX: 0, offsetY: 3 })
    .border({ width: this.getBlurPanelBorderWidth(), color: this.getBlurPanelBorder() })
  }

  /**
   * 构建清除数据确认对话框
   */
  @Builder
  buildClearDataDialog() {
    Column() {
      // 遮罩层
      Column()
        .width('100%')
        .height('100%')
        .backgroundColor('#80000000')
        .onClick(() => {
          this.showClearDataDialog = false;
        })
    }
    .width('100%')
    .height('100%')
    .position({ x: 0, y: 0 })
    
    // 对话框内容
    Column({ space: 20 }) {
      // 图标
      SymbolGlyph($r('sys.symbol.exclamationmark_triangle'))
        .fontSize(48)
        .fontColor(['#FF9800'])
      
      // 标题
      Text('清除阅读分析数据')
        .fontSize(18)
        .fontWeight(FontWeight.Bold)
        .fontFamily(this.appFontFamily)
        .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_primary', this.themeState.currentTheme))
      
      // 说明
      Text('此操作将清除所有统计和分析数据，不影响您书库当中的阅读记录，包括：')
        .fontSize(14)
        .fontFamily(this.appFontFamily)
        .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_secondary', this.themeState.currentTheme))
        .width('100%')
        .textAlign(TextAlign.Center)
      
      Column({ space: 6 }) {
        Text('• 阅读时长排行数据')
          .fontSize(13)
          .fontFamily(this.appFontFamily)
          .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_muted', this.themeState.currentTheme))
        Text('• 阅读进度分析数据')
          .fontSize(13)
          .fontFamily(this.appFontFamily)
          .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_muted', this.themeState.currentTheme))
        Text('• 阅读习惯分析数据')
          .fontSize(13)
          .fontFamily(this.appFontFamily)
          .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_muted', this.themeState.currentTheme))
        Text('• 兴趣分析数据')
          .fontSize(13)
          .fontFamily(this.appFontFamily)
          .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_muted', this.themeState.currentTheme))
      }
      .width('100%')
      .alignItems(HorizontalAlign.Start)
      .padding({ left: 24, right: 24 })
      
      Text('此操作不可撤销！')
        .fontSize(14)
        .fontWeight(FontWeight.Medium)
        .fontFamily(this.appFontFamily)
        .fontColor('#F44336')
        .margin({ top: 8 })
      
      // 按钮区域
      Column({ space: 12 }) {
        Row({ space: 16 }) {
          // 取消按钮
          Button('取消')
            .fontSize(15)
            .fontFamily(this.appFontFamily)
            .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_primary', this.themeState.currentTheme))
            .backgroundColor(ThemeAwareHelper.getTestManagementThemedColor('button_background', this.themeState.currentTheme))
            .borderRadius(20)
            .height(44)
            .layoutWeight(1)
            .onClick(() => {
              this.showClearDataDialog = false;
            })
          
          // 确认清除按钮
          Button('确认清除')
            .fontSize(15)
            .fontFamily(this.appFontFamily)
            .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_white', this.themeState.currentTheme))
            .backgroundColor(ThemeAwareHelper.getTestManagementThemedColor('button_danger', this.themeState.currentTheme))
            .borderRadius(20)
            .height(44)
            .layoutWeight(1)
            .onClick(() => {
              this.clearReadingAnalyticsData();
            })
        }
        .width('100%')
        
        // 清除数据并关闭功能按钮
        Button('清除数据并关闭阅读报告')
          .fontSize(14)
          .fontFamily(this.appFontFamily)
          .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_muted', this.themeState.currentTheme))
          .backgroundColor('transparent')
          .border({
            width: 1,
            color: ThemeAwareHelper.getTestManagementThemedColor('text_muted', this.themeState.currentTheme)
          })
          .borderRadius(20)
          .height(40)
          .width('100%')
          .onClick(() => {
            this.clearDataAndDisableAnalytics();
          })
      }
      .width('100%')
      .margin({ top: 16 })
    }
    .width('85%')
    .constraintSize({ maxWidth: 400 })
    .padding(24)
    .backgroundColor(this.getBlurPanelBackground())
    .linearGradient(this.getBlurPanelSurfaceGradient())
    .backgroundBlurStyle(this.getBlurPanelBlurStyle(), this.getBlurPanelBlurOptions())
    .backgroundEffect(this.getBlurPanelBackgroundEffect())
    .borderRadius(this.getBlurPanelRadius())
    .clip(true)
    .shadow({ radius: this.getBlurPanelRadius() + 4, color: this.getBlurPanelShadowColor(), offsetX: 0, offsetY: 6 })
    .border({ width: this.getBlurPanelBorderWidth(), color: this.getBlurPanelBorder() })
    .position({ x: '50%', y: '50%' })
    .translate({ x: '-50%', y: '-50%' })
  }

  /**
   * 构建横屏模式下的内容
   */
  @Builder
  buildLandscapeContent() {
    Column({ space: this.getAnalyticsSectionGap() }) {
      if (this.isLoading) {
        this.buildLoadingState()
      } else if (this.statistics.totalReadingTime === 0) {
        this.buildEmptyState()
      } else {
        // 横屏模式：使用两列布局
        Column({ space: this.getAnalyticsSectionGap() }) {
          this.buildReadingInsightSummary()

          // 第一行：统计概览（使用网格布局）
          this.buildStatisticsOverview()

          Row({ space: this.getAnalyticsColumnGap() }) {
            Column() {
              this.buildContentMixSection(this.getLongTermContentMixSegments())
            }
            .layoutWeight(1)

            Column() {
              this.buildInspirationOverviewSection()
            }
            .layoutWeight(1)
          }
          .width('100%')

          // 第二行：阅读习惯和兴趣分析（左右布局）
          Row({ space: this.getAnalyticsColumnGap() }) {
            Column() {
              this.buildReadingHabits()
            }
            .layoutWeight(1)

            Column() {
              this.buildInterestAnalysis()
            }
            .layoutWeight(1)
          }
          .width('100%')

          // 第三行：阅读排行和趋势
          Row({ space: this.getAnalyticsColumnGap() }) {
            Column() {
              this.buildReadingRank()
            }
            .layoutWeight(1)

            Column() {
              this.buildTrendVisualization()
            }
            .layoutWeight(1)
          }
          .width('100%')

          // 设置区域
          this.buildSettingsSection()
          
          Blank().height(40)
        }
        .width('100%')
        .padding({ left: this.getAnalyticsOuterHorizontalPadding(), right: this.getAnalyticsOuterHorizontalPadding() })
        .constraintSize({ maxWidth: this.responsive_maxContentWidth })
      }
    }
    .width('100%')
  }

  private getTitleBarActions(): SettingsImmersiveTitleActionItem[] {
    return [
      {
        id: 'viewMode',
        label: this.isLongTermView ? '日视图' : '长期视图',
        symbol: this.isLongTermView ? $r('sys.symbol.calendar_01_a') : $r('sys.symbol.calendar_badge_clock'),
        enabled: true,
        onClick: () => {
          this.toggleViewMode();
        }
      },
      {
        id: 'clearData',
        label: '清除数据',
        symbol: $r('sys.symbol.trash'),
        enabled: true,
        onClick: () => {
          this.showClearDataConfirmDialog();
        }
      }
    ];
  }

  build() {
    HdsNavDestination() {
      Stack() {
        SharedPageBackgroundLayer({
          defaultBackgroundColor: ThemeAwareHelper.getTestManagementThemedColor('background_dark', this.themeState.currentTheme),
          mode: GlobalBackgroundLayerMode.IMMERSIVE
        })
          .width('100%')
          .height('100%')
          .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.TOP, SafeAreaEdge.BOTTOM])
        
        // 如果未询问过权限或功能未启用，显示权限请求界面
        if ((!this.hasAskedPermission || !this.analyticsEnabled) && !this.isLoading) {
          Column() {
            Blank().height(SettingsPageTitleBarManager.getContentTopPadding(this.statusBarHeight))
            this.buildPermissionRequest()
          }
          .width('100%')
          .height('100%')
          .alignItems(HorizontalAlign.Center)
        } else if (this.isLongTermView) {
          // 长期视图
          Scroll(this.scroller) {
            Column({ space: this.getAnalyticsSectionGap() }) {
              Blank().height(SettingsPageTitleBarManager.getContentTopPadding(this.statusBarHeight))
              if (this.responsive_isLandscape) {
                // 横屏模式：使用更紧凑的布局
                this.buildLandscapeContent()
              } else {
                // 竖屏模式：使用原有布局
                if (this.isLoading) {
                  this.buildLoadingState()
                } else if (this.statistics.totalReadingTime === 0) {
                  this.buildEmptyState()
                } else {
                  this.buildReadingInsightSummary()
                  this.buildStatisticsOverview()
                  this.buildContentMixSection(this.getLongTermContentMixSegments())
                  this.buildInspirationOverviewSection()
                  this.buildReadingHabits()
                  this.buildInterestAnalysis()
                  this.buildReadingRank()
                  this.buildTrendVisualization()
                  this.buildSettingsSection()
                  
                  Blank().height(40)
                }
              }
            }
            .width('100%')
            .constraintSize({ maxWidth: this.responsive_isLandscape ? this.responsive_maxContentWidth : '100%' })
            .alignSelf(ItemAlign.Center)
          }
          .width('100%')
          .height('100%')
          .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.TOP, SafeAreaEdge.BOTTOM])
          .align(Alignment.TopStart)
          .edgeEffect(EdgeEffect.Spring)
          .scrollBar(BarState.Auto)
        } else {
          // 日视图
          Scroll(this.scroller) {
            Column({ space: this.getAnalyticsSectionGap() }) {
              Blank().height(SettingsPageTitleBarManager.getContentTopPadding(this.statusBarHeight))
              if (this.isLoading) {
                this.buildLoadingState()
              } else {
                this.buildDailyViewContent()
                Blank().height(40)
              }
            }
            .width('100%')
            .constraintSize({ maxWidth: this.responsive_isLandscape ? this.responsive_maxContentWidth : '100%' })
            .alignSelf(ItemAlign.Center)
            .padding({ left: this.getAnalyticsOuterHorizontalPadding(), right: this.getAnalyticsOuterHorizontalPadding() })
          }
          .width('100%')
          .height('100%')
          .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.TOP, SafeAreaEdge.BOTTOM])
          .align(Alignment.TopStart)
          .edgeEffect(EdgeEffect.Spring)
          .scrollBar(BarState.Auto)
        }

        // 保留天数选择器弹窗
        if (this.showRetentionPicker) {
          Column() {
            // 遮罩层
            Column()
              .width('100%')
              .height('100%')
              .backgroundColor('#80000000')
              .onClick(() => {
                this.showRetentionPicker = false;
              })
          }
          .width('100%')
          .height('100%')
          .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.TOP, SafeAreaEdge.BOTTOM])
          .position({ x: 0, y: 0 })

          // 选择器面板
          Column() {
            // 标题栏
            Row() {
              Text('取消')
                .fontSize(16)
                .fontFamily(this.appFontFamily)
                .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_secondary', this.themeState.currentTheme))
                .onClick(() => {
                  this.showRetentionPicker = false;
                })
              
              Text('选择数据保留天数')
                .fontSize(16)
                .fontWeight(FontWeight.Medium)
                .fontFamily(this.appFontFamily)
                .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_primary', this.themeState.currentTheme))
                .layoutWeight(1)
                .textAlign(TextAlign.Center)
              
              Text('确定')
                .fontSize(16)
                .fontFamily(this.appFontFamily)
                .fontColor(ThemeAwareHelper.getTestManagementThemedColor('accent_blue', this.themeState.currentTheme))
                .onClick(() => {
                  this.handleRetentionDaysChange(this.retentionDaysIndex);
                })
            }
            .width('100%')
            .padding(16)

            // TextPicker
            TextPicker({ range: this.analyticsManager.getRetentionDaysOptions(), selected: this.retentionDaysIndex })
              .onChange((value: string | string[], index: number | number[]) => {
                if (typeof index === 'number') {
                  this.retentionDaysIndex = index;
                }
              })
              .width('100%')
              .height(200)
          }
          .width('100%')
          .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.TOP, SafeAreaEdge.BOTTOM])
          .backgroundColor(this.getBlurPanelBackground())
          .linearGradient(this.getBlurPanelSurfaceGradient())
          .backgroundBlurStyle(this.getBlurPanelBlurStyle(), this.getBlurPanelBlurOptions())
          .backgroundEffect(this.getBlurPanelBackgroundEffect())
          .borderRadius({ topLeft: this.getBlurPanelRadius(), topRight: this.getBlurPanelRadius() })
          .clip(true)
          .shadow({ radius: this.getBlurPanelRadius() + 4, color: this.getBlurPanelShadowColor(), offsetX: 0, offsetY: -2 })
          .border({ width: this.getBlurPanelBorderWidth(), color: this.getBlurPanelBorder() })
          .position({ x: 0, y: '100%' })
          .translate({ y: -280 })
        }
        
        // 清除数据确认对话框
        if (this.showClearDataDialog) {
          this.buildClearDataDialog()
        }
        
        // 阅读目标设置对话框
        if (this.showGoalSettingDialog) {
          this.buildGoalSettingDialog()
        }

        SettingsImmersiveTitleBar({
          themeState: this.themeState,
          title: '阅读报告',
          appFontFamily: this.appFontFamily,
          contentPadding: this.responsive_contentPadding,
          maxContentWidth: this.responsive_maxContentWidth,
          pathStack: this.pathStack,
          actions: this.getTitleBarActions()
        })
      }
    }
    .hideTitleBar(true)
    .ignoreLayoutSafeArea([LayoutSafeAreaType.SYSTEM], [LayoutSafeAreaEdge.TOP, LayoutSafeAreaEdge.BOTTOM])
    .onReady((context: NavDestinationContext) => {
      this.pathStack = context.pathStack;
      
      // 检查是否有从卡片传入的 viewMode 参数（通过 AppStorage 传递）
      try {
        const viewMode = AppStorage.get<string>('analyticsViewMode');
        if (viewMode === 'daily') {
          // 标记从卡片强制进入日视图
          this.forceShowDailyView = true;
          // 清除标记
          AppStorage.setOrCreate('analyticsViewMode', '');
          logger.info(TAG, '📱 从卡片进入，将切换到日视图');
        }
      } catch (e) {
        logger.debug(TAG, '获取导航参数异常');
      }
      
      this.onPageShow();
      this.onReady();
    })
    .backgroundColor(Color.Transparent)
  }
}

export { ReadingAnalyticsPage }

