// 文件路径: entry/src/main/ets/pages/ReadingAnalyticsPage.ets
/**
 * 阅读数据分析报告页面
 * 根据用户的阅读记录，分析并展示阅读习惯、统计数据等
 */

import { HdsNavDestination, HdsNavDestinationAttribute, ScrollEffectType } from '@kit.UIDesignKit';
import { LengthMetrics } from '@kit.ArkUI';
import { ThemeAwareState, ThemeAwareHelper } from '../Framework/Components/ThemeAware';
import { ThemeManager, ThemeType } from '../Framework/Managers/ThemeManager';
import { DeviceAdaptationManager, DeviceInfo, DeviceChangeListener, Breakpoint } from '../Framework/Managers/DeviceAdaptationManager';
import { ResponsiveLayoutHelper } from '../Framework/Utils/ResponsiveLayout';
import { logger } from '../Utils/Logger';
import { DataService } from '../Framework/Services/DataService';
import { ReadHistory, DataManager, ComicInfo } from '../Framework/Data/DataManager';
import { ReadingAnalyticsManager, RETENTION_DAYS_OPTIONS } from '../Framework/Managers/ReadingAnalyticsManager';
import { EBookDataManager } from '../Framework/Data/EBookDataManager';
import { EBook } from '../Models/EBookModels';
import { getNovelDataManager } from '../Framework/Novel/NovelDataManager';
import { NovelBook } from '../Models/NovelModels';

const TAG = 'ReadingAnalyticsPage';
const TITLE_BAR_HEIGHT_MINI: number = 56;

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
type ReadingRankType = 'manga' | 'ebook';

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

/**
 * 漫画详情页导航参数
 */
interface MangaDetailParams {
  mangaId: string;
}

/**
 * 电子书详情页导航参数
 */
interface EBookDetailParams {
  bookId: string;
}

@Component
struct ReadingAnalyticsPage {
  @State pathStack: NavPathStack = new NavPathStack();
  private scroller: Scroller = new Scroller();

  // 主题相关状态
  @State themeState: ThemeAwareState = new ThemeAwareState();
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
  @State isDailyLoading: boolean = false; // 日视图加载状态
  
  // 缓存原始阅读历史数据（用于日视图查询）
  private cachedReadHistory: ReadHistory[] = [];
  
  // 缓存所有日期的阅读数据（用于日历视图，不受时间范围限制）
  @State allDailyData: DailyReadingData[] = [];

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

    // 初始化响应式布局
    this.initResponsiveLayout();

    // 初始化阅读报告管理器并加载数据
    this.initializeAndLoad().catch((error: Error) => {
      logger.error(TAG, '初始化失败', error.message);
    });
  }

  aboutToDisappear(): void {
    ThemeAwareHelper.cleanupThemeAware(this.componentId);
    
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
      
      logger.info(TAG, `初始化完成: analyticsEnabled=${this.analyticsEnabled}, hasAskedPermission=${this.hasAskedPermission}`);
      
      // 如果已询问过权限，才加载数据
      if (this.hasAskedPermission) {
        await this.loadReadingData();
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
      
      this.showClearDataDialog = false;
      logger.info(TAG, '阅读报告功能已关闭，权限状态已重置（阅读记录保留），准备返回');
      
      // 返回上一页
      this.pathStack.pop();
    } catch (error) {
      logger.error(TAG, `关闭阅读报告功能失败: ${String(error)}`);
    }
  }

  /**
   * 切换视图模式（长期视图 / 日视图）
   */
  private toggleViewMode(): void {
    this.isLongTermView = !this.isLongTermView;
    logger.info(TAG, `切换到${this.isLongTermView ? '长期视图' : '日视图'}`);
    
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
    
    // 更新日视图数据，使用从列表计算的数据
    this.dailyViewData = {
      date: dateKey,
      readingTime: mangaReadingTime + ebookReadingTime,
      chaptersRead: mangaChaptersRead + ebookChapters,
      pagesRead: mangaPagesRead
    };
    
    logger.debug(TAG, `日视图数据: ${dateKey}, 时长: ${this.dailyViewData?.readingTime || 0}秒, 漫画数: ${this.dailyMangaList.length}, 电子书数: ${this.dailyEBookList.length}`);
    
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
    
    for (const entry of entries) {
      const comicId = entry[0];
      const stats = entry[1];
      
      try {
        const comic = await this.dataManager.getComicById(comicId);
        if (comic) {
          mangaList.push({
            comicId: comicId,
            title: comic.title,
            coverPath: comic.coverLocalPath || comic.coverUrl || '',
            readingTime: Math.round(stats.time / 1000), // 毫秒转秒
            chaptersRead: stats.chapters.size,
            pagesRead: stats.pages
          });
        }
      } catch (e) {
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

      // 如果漫画和电子书都没有阅读记录
      if (readHistory.length === 0 && ebooksWithProgress.length === 0) {
        logger.info(TAG, '暂无阅读记录');
        this.isLoading = false;
        return;
      }

      // 分析漫画数据
      await this.analyzeReadingData(readHistory);
      
      // 分析电子书数据（传入时间范围进行过滤）
      const now = Date.now();
      const timeRangeMs = this.selectedTimeRange * 24 * 60 * 60 * 1000;
      const startTime = now - timeRangeMs;
      this.analyzeEBookData(ebooksWithProgress, startTime);
      
      // 分析小说数据
      await this.analyzeNovelData(startTime);
      
      // 重新计算日均阅读时长（合并漫画和电子书的阅读天数）
      this.recalculateAverageReadingTime(readHistory, ebooksWithProgress, startTime);
      
      // 重新计算连续阅读天数（合并漫画和电子书的阅读日期）
      this.recalculateContinuousReadingDays(readHistory, ebooksWithProgress);
      
      // 重新计算最喜欢的阅读时段（合并漫画和电子书的阅读时间）
      this.recalculateFavoriteReadingHour(readHistory, ebooksWithProgress, startTime);
      
      // 加载阅读时长排行（包含漫画和电子书）
      await this.loadReadingRank(readHistory, ebooksWithProgress);
      
      // 分析用户兴趣
      await this.analyzeUserInterests();

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
      // 过滤时间范围内有阅读记录的电子书
      const filteredEbooks = ebooks.filter((ebook: EBook) => {
        if (!ebook.readingProgress || !ebook.readingProgress.lastReadTime) {
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
  private async analyzeNovelData(startTime: number): Promise<void> {
    try {
      const novelDataManager = getNovelDataManager();
      const novels = await novelDataManager.getBooksWithReadingTime();
      
      // 过滤时间范围内有阅读记录的小说
      const filteredNovels = novels.filter((novel: NovelBook) => {
        if (!novel.lastReadTime) {
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
    } catch (error) {
      logger.error(TAG, `分析小说数据失败: ${String(error)}`);
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
    comicCountMap.forEach((count, comicId) => {
      if (count > maxCount) {
        maxCount = count;
        mostReadComicId = comicId;
      }
    });

    this.statistics.mostReadComicId = mostReadComicId;
    
    // 从数据库查询漫画标题
    if (mostReadComicId) {
      try {
        const dataManager = DataManager.getInstance();
        const comic = await dataManager.getComicById(mostReadComicId);
        this.statistics.mostReadComicTitle = comic ? comic.title : `漫画ID: ${mostReadComicId}`;
      } catch (error) {
        logger.warn(TAG, `查询漫画标题失败: ${String(error)}`);
        this.statistics.mostReadComicTitle = `漫画ID: ${mostReadComicId}`;
      }
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
      
      // 根据阅读时长找出阅读最多的电子书
      let maxReadingTime = 0;
      let mostReadEBook: EBook | null = null;
      
      for (const ebook of allEBooks) {
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
   * 重新计算日均阅读时长（合并漫画和电子书的阅读天数）
   */
  private recalculateAverageReadingTime(readHistory: ReadHistory[], ebooks: EBook[], startTime: number): void {
    const uniqueReadDates = new Set<string>();
    
    // 添加漫画阅读日期
    readHistory.forEach(record => {
      if (record.readTime >= startTime) {
        const date = new Date(record.readTime);
        const dateKey = `${date.getFullYear()}-${String(date.getMonth() + 1).padStart(2, '0')}-${String(date.getDate()).padStart(2, '0')}`;
        uniqueReadDates.add(dateKey);
      }
    });
    
    // 添加电子书阅读日期
    ebooks.forEach((ebook: EBook) => {
      if (ebook.readingProgress && ebook.readingProgress.lastReadTime && ebook.readingProgress.lastReadTime >= startTime) {
        const date = new Date(ebook.readingProgress.lastReadTime);
        const dateKey = `${date.getFullYear()}-${String(date.getMonth() + 1).padStart(2, '0')}-${String(date.getDate()).padStart(2, '0')}`;
        uniqueReadDates.add(dateKey);
      }
    });
    
    const actualReadingDays = uniqueReadDates.size;
    this.statistics.averageReadingTime = actualReadingDays > 0
      ? Math.round(this.statistics.totalReadingTime / actualReadingDays)
      : 0;
    
    logger.debug(TAG, `日均阅读时长重新计算: 总时长=${this.statistics.totalReadingTime}秒, 阅读天数=${actualReadingDays}, 日均=${this.statistics.averageReadingTime}秒`);
  }

  /**
   * 重新计算连续阅读天数（合并漫画和电子书的阅读日期）
   */
  private recalculateContinuousReadingDays(readHistory: ReadHistory[], ebooks: EBook[]): void {
    const readDates = new Set<string>();
    
    // 添加漫画阅读日期
    readHistory.forEach(record => {
      const date = new Date(record.readTime);
      const dateKey = `${date.getFullYear()}-${String(date.getMonth() + 1).padStart(2, '0')}-${String(date.getDate()).padStart(2, '0')}`;
      readDates.add(dateKey);
    });
    
    // 添加电子书阅读日期
    ebooks.forEach((ebook: EBook) => {
      if (ebook.readingProgress && ebook.readingProgress.lastReadTime) {
        const date = new Date(ebook.readingProgress.lastReadTime);
        const dateKey = `${date.getFullYear()}-${String(date.getMonth() + 1).padStart(2, '0')}-${String(date.getDate()).padStart(2, '0')}`;
        readDates.add(dateKey);
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
   * 重新计算最喜欢的阅读时段（合并漫画和电子书的阅读时间）
   */
  private recalculateFavoriteReadingHour(readHistory: ReadHistory[], ebooks: EBook[], startTime: number): void {
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
      for (const entry of mangaEntries) {
        const comicId: string = entry[0];
        const readingTime: number = entry[1];
        
        try {
          const comic: ComicInfo | null = await this.dataManager.getComicById(comicId);
          if (comic) {
            const coverPath: string = comic.coverLocalPath || comic.coverUrl || '';
            const rankItem: ReadingRankItem = {
              id: comicId,
              title: comic.title,
              coverPath: coverPath,
              readingTime: readingTime,
              type: 'manga'
            };
            rankList.push(rankItem);
          }
        } catch (e) {
          logger.warn(TAG, `无法找到漫画信息: ${comicId}`);
        }
      }

      // 添加电子书到排行（电子书的 totalReadingTime 是分钟，需要转换为秒）
      for (const ebook of ebooks) {
        if (ebook.readingProgress && ebook.readingProgress.totalReadingTime > 0) {
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
   * 导航到作品详情页
   */
  private navigateToDetail(item: ReadingRankItem): void {
    try {
      if (item.type === 'manga') {
        const params: MangaDetailParams = { mangaId: item.id };
        this.pathStack.pushPathByName('MangaDetailPage', params);
      } else {
        const params: EBookDetailParams = { bookId: item.id };
        this.pathStack.pushPathByName('EBookDetailPage', params);
      }
    } catch (error) {
      logger.error(TAG, `导航到详情页失败: ${String(error)}`);
    }
  }

  private goBack(): void {
    try {
      this.pathStack.pop();
    } catch (error) {
      logger.error(TAG, '返回失败', String(error));
    }
  }

  /**
   * 规范化封面路径：本地文件添加 file:// 前缀，资源文件返回 Resource 类型
   * @param path 封面路径
   * @param isEBook 是否为电子书（电子书无封面时使用默认电子书图标）
   */
  private normalizeCoverPath(path: string, isEBook: boolean = false): string | Resource {
    if (!path || path.length === 0) {
      // 电子书无封面时使用默认电子书图标
      if (isEBook) {
        return $r('app.media.ebook');
      }
      return '';
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

  /**
   * 构建时间范围选择器（长期视图）
   */
  @Builder
  buildTimeRangeSelector() {
    Row({ space: 8 }) {
      Button({ stateEffect: true }) {
        Text('7天')
          .fontSize(12)
          .fontColor(ThemeAwareHelper.getTestManagementThemedColor('button_text_secondary', this.themeState.currentTheme))
      }
      .width('33%')
      .height(32)
      .backgroundColor(
        (this.selectedTimeRange === 7
          ? ThemeAwareHelper.getTestManagementThemedColor('accent_blue', this.themeState.currentTheme)
          : ThemeAwareHelper.getTestManagementThemedColor('button_inactive', this.themeState.currentTheme)) as ResourceColor
      )
      .borderRadius(8)
      .onClick(() => this.changeTimeRange(7))

      Button({ stateEffect: true }) {
        Text('30天')
          .fontSize(12)
          .fontColor(ThemeAwareHelper.getTestManagementThemedColor('button_text_secondary', this.themeState.currentTheme))
      }
      .width('33%')
      .height(32)
      .backgroundColor(
        (this.selectedTimeRange === 30
          ? ThemeAwareHelper.getTestManagementThemedColor('accent_blue', this.themeState.currentTheme)
          : ThemeAwareHelper.getTestManagementThemedColor('button_inactive', this.themeState.currentTheme)) as ResourceColor
      )
      .borderRadius(8)
      .onClick(() => this.changeTimeRange(30))

      Button({ stateEffect: true }) {
        Text('全部')
          .fontSize(12)
          .fontColor(ThemeAwareHelper.getTestManagementThemedColor('button_text_secondary', this.themeState.currentTheme))
      }
      .width('33%')
      .height(32)
      .backgroundColor(
        (this.selectedTimeRange === 365
          ? ThemeAwareHelper.getTestManagementThemedColor('accent_blue', this.themeState.currentTheme)
          : ThemeAwareHelper.getTestManagementThemedColor('button_inactive', this.themeState.currentTheme)) as ResourceColor
      )
      .borderRadius(8)
      .onClick(() => this.changeTimeRange(365))
    }
    .width('100%')
    .padding({ left: 16, right: 16, top: 12, bottom: 12 })
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
          Text('◀')
            .fontSize(16)
            .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_primary', this.themeState.currentTheme))
        }
        .width(40)
        .height(40)
        .backgroundColor(Color.Transparent)
        .onClick(() => this.previousMonth())

        Text(`${this.currentMonth.getFullYear()}年${this.currentMonth.getMonth() + 1}月`)
          .fontSize(16)
          .fontWeight(FontWeight.Medium)
          .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_primary', this.themeState.currentTheme))
          .layoutWeight(1)
          .textAlign(TextAlign.Center)

        Button({ stateEffect: true }) {
          Text('▶')
            .fontSize(16)
            .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_primary', this.themeState.currentTheme))
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
    .borderRadius(12)
    .backdropBlur(this.themeState.currentTheme === ThemeType.DARK ? BlurStyle.BACKGROUND_THICK : BlurStyle.BACKGROUND_THIN)
    .shadow({ radius: 12, color: this.getBlurPanelShadowColor(), offsetX: 0, offsetY: 4 })
    .border({ width: 1, color: this.getBlurPanelBorder() })
    .margin({ left: 16, right: 16 })
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
      return '#FFFFFF';
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
    Column({ space: 16 }) {
      // 月历选择器
      this.buildMonthCalendar()
      
      // 当天阅读统计
      Column({ space: 12 }) {
        Text(`${this.selectedDate.getMonth() + 1}月${this.selectedDate.getDate()}日 阅读情况`)
          .fontSize(16)
          .fontWeight(FontWeight.Medium)
          .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_primary', this.themeState.currentTheme))
          .alignSelf(ItemAlign.Start)
        
        if (this.isDailyLoading) {
          // 加载中效果
          Column({ space: 8 }) {
            LoadingProgress()
              .width(40)
              .height(40)
              .color(ThemeAwareHelper.getTestManagementThemedColor('accent_primary', this.themeState.currentTheme))
            Text('加载中...')
              .fontSize(14)
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
              Text('⏱️')
                .fontSize(24)
              Text(this.formatDuration(this.dailyViewData.readingTime))
                .fontSize(18)
                .fontWeight(FontWeight.Bold)
                .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_primary', this.themeState.currentTheme))
              Text('阅读时长')
                .fontSize(12)
                .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_secondary', this.themeState.currentTheme))
            }
            .layoutWeight(1)
            .alignItems(HorizontalAlign.Center)
            
            // 阅读章节
            Column({ space: 4 }) {
              Text('📖')
                .fontSize(24)
              Text(`${this.dailyViewData.chaptersRead}`)
                .fontSize(18)
                .fontWeight(FontWeight.Bold)
                .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_primary', this.themeState.currentTheme))
              Text('阅读章节')
                .fontSize(12)
                .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_secondary', this.themeState.currentTheme))
            }
            .layoutWeight(1)
            .alignItems(HorizontalAlign.Center)
            
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
            Text('📚')
              .fontSize(48)
            Text('当天没有阅读记录')
              .fontSize(14)
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
      .borderRadius(12)
      .backdropBlur(this.themeState.currentTheme === ThemeType.DARK ? BlurStyle.BACKGROUND_THICK : BlurStyle.BACKGROUND_THIN)
      .shadow({ radius: 12, color: this.getBlurPanelShadowColor(), offsetX: 0, offsetY: 4 })
      .border({ width: 1, color: this.getBlurPanelBorder() })
      .margin({ left: 16, right: 16 })
      
      // 当天阅读的漫画列表
      if (this.dailyMangaList.length > 0) {
        Column({ space: 12 }) {
          Text('阅读的漫画')
            .fontSize(16)
            .fontWeight(FontWeight.Medium)
            .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_primary', this.themeState.currentTheme))
            .alignSelf(ItemAlign.Start)
          
          ForEach(this.dailyMangaList, (item: DailyMangaItem) => {
            this.buildDailyMangaCard(item)
          })
        }
        .width('100%')
        .padding(16)
        .backgroundColor(this.getBlurPanelBackground())
        .borderRadius(12)
        .backdropBlur(this.themeState.currentTheme === ThemeType.DARK ? BlurStyle.BACKGROUND_THICK : BlurStyle.BACKGROUND_THIN)
        .shadow({ radius: 12, color: this.getBlurPanelShadowColor(), offsetX: 0, offsetY: 4 })
        .border({ width: 1, color: this.getBlurPanelBorder() })
        .margin({ left: 16, right: 16 })
      }
      
      // 当天阅读的电子书列表
      if (this.dailyEBookList.length > 0) {
        Column({ space: 12 }) {
          Text('阅读的电子书')
            .fontSize(16)
            .fontWeight(FontWeight.Medium)
            .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_primary', this.themeState.currentTheme))
            .alignSelf(ItemAlign.Start)
          
          ForEach(this.dailyEBookList, (item: DailyEBookItem) => {
            this.buildDailyEBookCard(item)
          })
        }
        .width('100%')
        .padding(16)
        .backgroundColor(this.getBlurPanelBackground())
        .borderRadius(12)
        .backdropBlur(this.themeState.currentTheme === ThemeType.DARK ? BlurStyle.BACKGROUND_THICK : BlurStyle.BACKGROUND_THIN)
        .shadow({ radius: 12, color: this.getBlurPanelShadowColor(), offsetX: 0, offsetY: 4 })
        .border({ width: 1, color: this.getBlurPanelBorder() })
        .margin({ left: 16, right: 16 })
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
        .backgroundColor(ThemeAwareHelper.getTestManagementThemedColor('comp_background_tertiary', this.themeState.currentTheme))
      
      // 漫画信息
      Column({ space: 4 }) {
        Text(item.title)
          .fontSize(14)
          .fontWeight(FontWeight.Medium)
          .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_primary', this.themeState.currentTheme))
          .maxLines(2)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
          .width('100%')
        
        Row({ space: 8 }) {
          Text(`⏱️ ${this.formatDuration(item.readingTime)}`)
            .fontSize(12)
            .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_secondary', this.themeState.currentTheme))
          
          Text(`📖 ${item.chaptersRead}章`)
            .fontSize(12)
            .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_secondary', this.themeState.currentTheme))
          
          Text(`📄 ${item.pagesRead}页`)
            .fontSize(12)
            .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_secondary', this.themeState.currentTheme))
        }
      }
      .layoutWeight(1)
      .alignItems(HorizontalAlign.Start)
    }
    .width('100%')
    .padding(12)
    .backgroundColor(ThemeAwareHelper.getTestManagementThemedColor('comp_background_secondary', this.themeState.currentTheme))
    .borderRadius(8)
    .onClick(() => {
      // 点击跳转到漫画详情页
      const params: MangaDetailParams = { mangaId: item.comicId };
      this.pathStack.pushPathByName('MangaDetailPage', params);
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
        .backgroundColor(ThemeAwareHelper.getTestManagementThemedColor('comp_background_tertiary', this.themeState.currentTheme))
      
      // 电子书信息
      Column({ space: 4 }) {
        Text(item.title)
          .fontSize(14)
          .fontWeight(FontWeight.Medium)
          .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_primary', this.themeState.currentTheme))
          .maxLines(2)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
          .width('100%')
        
        Row({ space: 8 }) {
          Text(`⏱️ ${this.formatDuration(item.readingTime)}`)
            .fontSize(12)
            .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_secondary', this.themeState.currentTheme))
          
          Text(`📊 ${item.progress.toFixed(1)}%`)
            .fontSize(12)
            .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_secondary', this.themeState.currentTheme))
        }
      }
      .layoutWeight(1)
      .alignItems(HorizontalAlign.Start)
    }
    .width('100%')
    .padding(12)
    .backgroundColor(ThemeAwareHelper.getTestManagementThemedColor('comp_background_secondary', this.themeState.currentTheme))
    .borderRadius(8)
    .onClick(() => {
      // 点击跳转到电子书详情页
      const params: EBookDetailParams = { bookId: item.ebookId };
      this.pathStack.pushPathByName('EBookDetailPage', params);
    })
  }

  /**
   * 获取统计卡片渐变背景色
   */
  private getStatCardGradient(index: number): LinearGradient {
    const isDark = this.themeState.currentTheme === ThemeType.DARK;
    const gradients: LinearGradient[] = isDark ? [
      // 深色主题渐变
      { angle: 135, colors: [['#1A3A5C', 0], ['#0D1F33', 1]] },  // 深蓝
      { angle: 135, colors: [['#2D1B4E', 0], ['#1A0F2E', 1]] },  // 深紫
      { angle: 135, colors: [['#1B3D3D', 0], ['#0F2424', 1]] },  // 深青
      { angle: 135, colors: [['#3D2B1B', 0], ['#241A0F', 1]] },  // 深橙
      { angle: 135, colors: [['#3D1B2B', 0], ['#240F1A', 1]] },  // 深红
      { angle: 135, colors: [['#1B3D2B', 0], ['#0F241A', 1]] },  // 深绿
    ] : [
      // 浅色主题渐变
      { angle: 135, colors: [['#E8F4FD', 0], ['#D1E9FA', 1]] },  // 浅蓝
      { angle: 135, colors: [['#F3E8FD', 0], ['#E6D1FA', 1]] },  // 浅紫
      { angle: 135, colors: [['#E8FDF4', 0], ['#D1FAE9', 1]] },  // 浅青
      { angle: 135, colors: [['#FDF4E8', 0], ['#FAE9D1', 1]] },  // 浅橙
      { angle: 135, colors: [['#FDE8F0', 0], ['#FAD1E0', 1]] },  // 浅红
      { angle: 135, colors: [['#E8FDE8', 0], ['#D1FAD1', 1]] },  // 浅绿
    ];
    return gradients[index % gradients.length];
  }

  /**
   * 构建统计卡片（带模糊效果磁贴设计）
   */
  @Builder
  buildStatCard(title: string, value: string, icon: string, unit?: string) {
    Column({ space: 6 }) {
      // 图标
      Text(icon)
        .fontSize(32)
        .alignSelf(ItemAlign.Start)
      
      Blank().layoutWeight(1)
      
      // 数值和单位（同一行显示）
      Row({ space: 2 }) {
        Text(value)
          .fontSize(24)
          .fontWeight(FontWeight.Bold)
          .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_primary', this.themeState.currentTheme))
        
        if (unit) {
          Text(unit)
            .fontSize(14)
            .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_secondary', this.themeState.currentTheme))
            .alignSelf(ItemAlign.End)
            .margin({ bottom: 2 })
        }
      }
      .alignSelf(ItemAlign.Start)
      
      // 标题
      Text(title)
        .fontSize(12)
        .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_secondary', this.themeState.currentTheme))
        .alignSelf(ItemAlign.Start)
    }
    .width('100%')
    .height(120)
    .padding(16)
    .borderRadius(16)
    .backgroundColor(this.themeState.currentTheme === ThemeType.DARK 
      ? 'rgba(30, 30, 35, 0.85)'   // 深色模式：深色半透明背景
      : 'rgba(255, 255, 255, 0.85)') // 浅色模式：白色半透明背景
    .backdropBlur(this.themeState.currentTheme === ThemeType.DARK 
      ? BlurStyle.BACKGROUND_THICK   // 深色模式：厚模糊
      : BlurStyle.BACKGROUND_THIN)   // 浅色模式：薄模糊
    .shadow({
      radius: 16,
      color: this.themeState.currentTheme === ThemeType.DARK 
        ? 'rgba(0, 0, 0, 0.4)'      // 深色模式：深色阴影
        : 'rgba(0, 0, 0, 0.06)',    // 浅色模式：浅色阴影
      offsetX: 0,
      offsetY: 4
    })
    .border({
      width: 1,
      color: this.themeState.currentTheme === ThemeType.DARK 
        ? 'rgba(255, 255, 255, 0.08)' // 深色模式：微弱白色边框
        : 'rgba(0, 0, 0, 0.04)'       // 浅色模式：微弱黑色边框
    })
  }

  /**
   * 构建统计概览区域
   */
  @Builder
  buildStatisticsOverview() {
    Column({ space: 16 }) {
      Text('📊 阅读统计')
        .fontSize(18)
        .fontWeight(FontWeight.Bold)
        .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_primary', this.themeState.currentTheme))
        .alignSelf(ItemAlign.Start)

      // 使用Grid布局实现2列磁贴效果
      Grid() {
        GridItem() {
          this.buildStatCard(
            '总阅读时长',
            this.formatDuration(this.statistics.totalReadingTime),
            '⏱️'
          )
        }

        GridItem() {
          this.buildStatCard(
            '日均阅读',
            this.formatDuration(this.statistics.averageReadingTime),
            '📅'
          )
        }

        GridItem() {
          this.buildStatCard(
            '阅读漫画',
            `${this.statistics.totalComicsRead}`,
            '📚',
            '本'
          )
        }

        GridItem() {
          this.buildStatCard(
            '阅读章节',
            `${this.statistics.totalChaptersRead}`,
            '📖',
            '章'
          )
        }

        GridItem() {
          this.buildStatCard(
            '阅读电子书',
            `${this.statistics.totalEBooksRead}`,
            '📕',
            '本'
          )
        }

        GridItem() {
          this.buildStatCard(
            '电子书时长',
            this.formatDuration(this.statistics.totalEBookReadingTime),
            '📖'
          )
        }

        GridItem() {
          this.buildStatCard(
            '阅读页数',
            `${this.statistics.totalPagesRead}`,
            '📄',
            '页'
          )
        }

        GridItem() {
          this.buildStatCard(
            '连续阅读',
            `${this.statistics.continuousReadingDays}`,
            '🔥',
            '天'
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
  }

  /**
   * 获取模糊面板背景色
   */
  private getBlurPanelBackground(): ResourceColor {
    return this.themeState.currentTheme === ThemeType.DARK 
      ? 'rgba(30, 30, 35, 0.85)' 
      : 'rgba(255, 255, 255, 0.85)';
  }

  /**
   * 获取模糊面板边框色
   */
  private getBlurPanelBorder(): ResourceColor {
    return this.themeState.currentTheme === ThemeType.DARK 
      ? 'rgba(255, 255, 255, 0.08)' 
      : 'rgba(0, 0, 0, 0.04)';
  }

  /**
   * 获取模糊面板阴影色
   */
  private getBlurPanelShadowColor(): ResourceColor {
    return this.themeState.currentTheme === ThemeType.DARK 
      ? 'rgba(0, 0, 0, 0.4)' 
      : 'rgba(0, 0, 0, 0.06)';
  }

  /**
   * 构建阅读习惯分析
   */
  @Builder
  buildReadingHabits() {
    Column({ space: 12 }) {
      Text('📈 阅读习惯')
        .fontSize(18)
        .fontWeight(FontWeight.Bold)
        .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_primary', this.themeState.currentTheme))
        .alignSelf(ItemAlign.Start)

      // 最喜欢的阅读时段
      Column({ space: 8 }) {
        Row({ space: 8 }) {
          Text('⏰')
            .fontSize(20)
          
          Text('最喜欢的阅读时段')
            .fontSize(14)
            .fontWeight(FontWeight.Medium)
            .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_primary', this.themeState.currentTheme))
            .layoutWeight(1)
          
          Text(this.statistics.favoriteReadingHour >= 0 
            ? `${this.statistics.favoriteReadingHour}:00 - ${this.statistics.favoriteReadingHour + 1}:00` 
            : '暂无数据')
            .fontSize(16)
            .fontWeight(FontWeight.Bold)
            .fontColor(ThemeAwareHelper.getTestManagementThemedColor('accent_blue', this.themeState.currentTheme))
        }
        .width('100%')
      }
      .width('100%')
      .padding(16)
      .backgroundColor(this.getBlurPanelBackground())
      .borderRadius(12)
      .backdropBlur(this.themeState.currentTheme === ThemeType.DARK ? BlurStyle.BACKGROUND_THICK : BlurStyle.BACKGROUND_THIN)
      .shadow({ radius: 12, color: this.getBlurPanelShadowColor(), offsetX: 0, offsetY: 4 })
      .border({ width: 1, color: this.getBlurPanelBorder() })

      // 最后阅读时间
      if (this.statistics.lastReadTime > 0) {
        Column({ space: 8 }) {
          Row({ space: 8 }) {
            Text('🕐')
              .fontSize(20)
            
            Text('最后阅读时间')
              .fontSize(14)
              .fontWeight(FontWeight.Medium)
              .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_primary', this.themeState.currentTheme))
              .layoutWeight(1)
            
            Text(this.formatDate(this.statistics.lastReadTime))
              .fontSize(16)
              .fontWeight(FontWeight.Bold)
              .fontColor(ThemeAwareHelper.getTestManagementThemedColor('accent_blue', this.themeState.currentTheme))
          }
          .width('100%')
        }
        .width('100%')
        .padding(16)
        .backgroundColor(this.getBlurPanelBackground())
        .borderRadius(12)
        .backdropBlur(this.themeState.currentTheme === ThemeType.DARK ? BlurStyle.BACKGROUND_THICK : BlurStyle.BACKGROUND_THIN)
        .shadow({ radius: 12, color: this.getBlurPanelShadowColor(), offsetX: 0, offsetY: 4 })
        .border({ width: 1, color: this.getBlurPanelBorder() })
      }

      // 阅读最多的漫画
      if (this.statistics.mostReadComicId.length > 0) {
        Column({ space: 8 }) {
          Row({ space: 8 }) {
            Text('⭐')
              .fontSize(20)
            
            Text('阅读最多的漫画')
              .fontSize(14)
              .fontWeight(FontWeight.Medium)
              .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_primary', this.themeState.currentTheme))
              .layoutWeight(1)
          }
          .width('100%')
          
          Text(this.statistics.mostReadComicTitle)
            .fontSize(14)
            .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_secondary', this.themeState.currentTheme))
            .maxLines(2)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
            .width('100%')
        }
        .width('100%')
        .padding(16)
        .backgroundColor(this.getBlurPanelBackground())
        .borderRadius(12)
        .backdropBlur(this.themeState.currentTheme === ThemeType.DARK ? BlurStyle.BACKGROUND_THICK : BlurStyle.BACKGROUND_THIN)
        .shadow({ radius: 12, color: this.getBlurPanelShadowColor(), offsetX: 0, offsetY: 4 })
        .border({ width: 1, color: this.getBlurPanelBorder() })
        .alignItems(HorizontalAlign.Start)
      }

      // 阅读最多的电子书
      if (this.statistics.mostReadEBookId.length > 0) {
        Column({ space: 8 }) {
          Row({ space: 8 }) {
            Text('📚')
              .fontSize(20)
            
            Text('阅读最多的电子书')
              .fontSize(14)
              .fontWeight(FontWeight.Medium)
              .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_primary', this.themeState.currentTheme))
              .layoutWeight(1)
          }
          .width('100%')
          
          Text(this.statistics.mostReadEBookTitle)
            .fontSize(14)
            .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_secondary', this.themeState.currentTheme))
            .maxLines(2)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
            .width('100%')
        }
        .width('100%')
        .padding(16)
        .backgroundColor(this.getBlurPanelBackground())
        .borderRadius(12)
        .backdropBlur(this.themeState.currentTheme === ThemeType.DARK ? BlurStyle.BACKGROUND_THICK : BlurStyle.BACKGROUND_THIN)
        .shadow({ radius: 12, color: this.getBlurPanelShadowColor(), offsetX: 0, offsetY: 4 })
        .border({ width: 1, color: this.getBlurPanelBorder() })
        .alignItems(HorizontalAlign.Start)
      }
    }
    .width('100%')
    .padding(16)
  }

  /**
   * 构建每日阅读趋势
   */
  @Builder
  buildDailyTrend() {
    if (this.dailyData.length > 0) {
      Column({ space: 12 }) {
        Text('📆 每日阅读趋势')
          .fontSize(18)
          .fontWeight(FontWeight.Bold)
          .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_primary', this.themeState.currentTheme))
          .alignSelf(ItemAlign.Start)

        Column({ space: 8 }) {
          ForEach(this.dailyData.slice(0, 7), (data: DailyReadingData, index: number) => {
            Row({ space: 12 }) {
              Text(data.date)
                .fontSize(12)
                .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_secondary', this.themeState.currentTheme))
                .width(90)
              
              Column({ space: 4 }) {
                Row({ space: 4 }) {
                  Text('⏱️')
                    .fontSize(12)
                  Text(this.formatDuration(data.readingTime))
                    .fontSize(12)
                    .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_primary', this.themeState.currentTheme))
                }
                
                Row({ space: 4 }) {
                  Text('📖')
                    .fontSize(12)
                  Text(`${data.chaptersRead}章 / ${data.pagesRead}页`)
                    .fontSize(12)
                    .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_secondary', this.themeState.currentTheme))
                }
              }
              .alignItems(HorizontalAlign.Start)
              .layoutWeight(1)
            }
            .width('100%')
            .padding(12)
            .backgroundColor(this.getBlurPanelBackground())
            .borderRadius(8)
            .backdropBlur(this.themeState.currentTheme === ThemeType.DARK ? BlurStyle.BACKGROUND_THICK : BlurStyle.BACKGROUND_THIN)
            .shadow({ radius: 8, color: this.getBlurPanelShadowColor(), offsetX: 0, offsetY: 2 })
            .border({ width: 1, color: this.getBlurPanelBorder() })
          }, (data: DailyReadingData, index: number) => `${data.date}-${index}`)
        }
        .width('100%')
      }
      .width('100%')
      .padding(16)
    }
  }

  /**
   * 构建兴趣分析
   */
  @Builder
  buildInterestAnalysis() {
    if (this.interestItems.length > 0) {
      Column({ space: 12 }) {
        Text('💡 您可能感兴趣的')
          .fontSize(18)
          .fontWeight(FontWeight.Bold)
          .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_primary', this.themeState.currentTheme))
          .alignSelf(ItemAlign.Start)

        // 兴趣标签云 - 带模糊效果容器
        Column() {
          Flex({ wrap: FlexWrap.Wrap, justifyContent: FlexAlign.Start }) {
            ForEach(this.interestItems, (item: InterestItem, index: number) => {
              Row({ space: 4 }) {
                Text(item.type === 'tag' ? '🏷️' : (item.type === 'author' ? '✍️' : '📝'))
                  .fontSize(12)
                Text(item.keyword)
                  .fontSize(13)
                  .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_primary', this.themeState.currentTheme))
                Text(`(${item.count})`)
                  .fontSize(11)
                  .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_muted', this.themeState.currentTheme))
              }
              .padding({ left: 10, right: 10, top: 6, bottom: 6 })
              .backgroundColor(this.themeState.currentTheme === ThemeType.DARK 
                ? 'rgba(255, 255, 255, 0.1)' 
                : 'rgba(0, 0, 0, 0.05)')
              .borderRadius(16)
              .margin({ right: 8, bottom: 8 })
            }, (item: InterestItem, index: number) => `${item.keyword}-${index}`)
          }
          .width('100%')
        }
        .width('100%')
        .padding(16)
        .backgroundColor(this.getBlurPanelBackground())
        .borderRadius(12)
        .backdropBlur(this.themeState.currentTheme === ThemeType.DARK ? BlurStyle.BACKGROUND_THICK : BlurStyle.BACKGROUND_THIN)
        .shadow({ radius: 12, color: this.getBlurPanelShadowColor(), offsetX: 0, offsetY: 4 })
        .border({ width: 1, color: this.getBlurPanelBorder() })
      }
      .width('100%')
      .padding(16)
    }
  }

  /**
   * 构建阅读时长排行
   */
  @Builder
  buildReadingRank() {
    if (this.readingRankList.length > 0) {
      Column({ space: 12 }) {
        Text('🏆 阅读时长排行')
          .fontSize(18)
          .fontWeight(FontWeight.Bold)
          .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_primary', this.themeState.currentTheme))
          .alignSelf(ItemAlign.Start)

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
                      Text('📚')
                        .fontSize(32)
                    }
                    .width('100%')
                    .aspectRatio(0.7)
                    .backgroundColor(ThemeAwareHelper.getTestManagementThemedColor('background_secondary', this.themeState.currentTheme))
                    .borderRadius(8)
                    .justifyContent(FlexAlign.Center)
                  }
                  
                  // 排名标签
                  Text(`${index + 1}`)
                    .fontSize(12)
                    .fontWeight(FontWeight.Bold)
                    .fontColor('#FFFFFF')
                    .padding({ left: 8, right: 8, top: 4, bottom: 4 })
                    .backgroundColor(index < 3 ? '#FF6B6B' : '#666666')
                    .borderRadius(4)
                    .position({ x: 4, y: 4 })
                }
                .width('100%')

                // 标题
                Text(item.title)
                  .fontSize(12)
                  .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_primary', this.themeState.currentTheme))
                  .maxLines(2)
                  .textOverflow({ overflow: TextOverflow.Ellipsis })
                  .width('100%')

                // 阅读时长
                Text(this.formatDuration(item.readingTime))
                  .fontSize(11)
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
    }
  }

  /**
   * 构建设置区域
   */
  @Builder
  buildSettingsSection() {
    Column({ space: 12 }) {
      Text('⚙️ 设置')
        .fontSize(18)
        .fontWeight(FontWeight.Bold)
        .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_primary', this.themeState.currentTheme))
        .alignSelf(ItemAlign.Start)

      // 数据保留天数设置
      Row() {
        Text('数据保留天数')
          .fontSize(14)
          .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_primary', this.themeState.currentTheme))
          .layoutWeight(1)
        
        Text(`${RETENTION_DAYS_OPTIONS[this.retentionDaysIndex]}天`)
          .fontSize(14)
          .fontColor(ThemeAwareHelper.getTestManagementThemedColor('accent_blue', this.themeState.currentTheme))
        
        Image($r('app.media.ic_arrow_right'))
          .width(16)
          .height(16)
          .fillColor(ThemeAwareHelper.getTestManagementThemedColor('text_muted', this.themeState.currentTheme))
          .margin({ left: 4 })
      }
      .width('100%')
      .padding(16)
      .backgroundColor(this.getBlurPanelBackground())
      .borderRadius(12)
      .backdropBlur(this.themeState.currentTheme === ThemeType.DARK ? BlurStyle.BACKGROUND_THICK : BlurStyle.BACKGROUND_THIN)
      .shadow({ radius: 12, color: this.getBlurPanelShadowColor(), offsetX: 0, offsetY: 4 })
      .border({ width: 1, color: this.getBlurPanelBorder() })
      .onClick(() => {
        this.showRetentionDaysPicker();
      })

      // 阅读报告开关
      Row() {
        Text('启用阅读数据收集')
          .fontSize(14)
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
      .backgroundColor(this.getBlurPanelBackground())
      .borderRadius(12)
      .backdropBlur(this.themeState.currentTheme === ThemeType.DARK ? BlurStyle.BACKGROUND_THICK : BlurStyle.BACKGROUND_THIN)
      .shadow({ radius: 12, color: this.getBlurPanelShadowColor(), offsetX: 0, offsetY: 4 })
      .border({ width: 1, color: this.getBlurPanelBorder() })

      Text('关闭后将停止收集阅读数据，但不会删除已有数据')
        .fontSize(12)
        .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_muted', this.themeState.currentTheme))
        .width('100%')
    }
    .width('100%')
    .padding(16)
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
        .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_secondary', this.themeState.currentTheme))
    }
    .width('100%')
    .height('80%')
    .justifyContent(FlexAlign.Center)
  }

  /**
   * 构建空状态
   */
  @Builder
  buildEmptyState() {
    Column({ space: 16 }) {
      Text('📚')
        .fontSize(64)
      
      Text('暂未收集到有效的阅读数据')
        .fontSize(18)
        .fontWeight(FontWeight.Medium)
        .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_primary', this.themeState.currentTheme))
      
      Text('开始阅读漫画/电子书后，这里将显示您的阅读统计和分析数据\n请在阅读更长时间后查看')
        .fontSize(14)
        .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_secondary', this.themeState.currentTheme))
        .textAlign(TextAlign.Center)
        .width('80%')
    }
    .width('100%')
    .height('80%')
    .justifyContent(FlexAlign.Center)
  }

  /**
   * 构建权限请求界面
   */
  @Builder
  buildPermissionRequest() {
    Column({ space: 24 }) {
      // 图标
      Text('📊')
        .fontSize(80)
      
      // 标题
      Text('阅读报告')
        .fontSize(24)
        .fontWeight(FontWeight.Bold)
        .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_primary', this.themeState.currentTheme))
      
      // 副标题
      Text('了解您的阅读习惯')
        .fontSize(16)
        .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_secondary', this.themeState.currentTheme))
      
      // 说明文字
      Column({ space: 12 }) {
        Text('开启阅读报告功能后，应用将收集以下数据：')
          .fontSize(14)
          .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_primary', this.themeState.currentTheme))
          .width('100%')
        
        Column({ space: 8 }) {
          this.buildPermissionItem('⏱️', '阅读时长', '记录您每次阅读的时长')
          this.buildPermissionItem('📖', '阅读进度', '记录您阅读的章节和页数')
          this.buildPermissionItem('📅', '阅读习惯', '分析您的阅读时段偏好')
          this.buildPermissionItem('🏷️', '兴趣分析', '根据阅读内容分析您的兴趣')
        }
        .width('100%')
        .padding(16)
        .backgroundColor(ThemeAwareHelper.getTestManagementThemedColor('panel_background', this.themeState.currentTheme))
        .borderRadius(12)
        
        Text('这些数据仅存储在本地，不会上传到任何服务器。您可以随时在设置中关闭此功能或清除数据。')
          .fontSize(12)
          .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_muted', this.themeState.currentTheme))
          .width('100%')
          .textAlign(TextAlign.Center)
      }
      .width('85%')
      .margin({ top: 16 })
      
      // 按钮区域
      Row({ space: 16 }) {
        // 拒绝按钮
        Button('拒绝')
          .fontSize(16)
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
          .fontColor('#FFFFFF')
          .backgroundColor(ThemeAwareHelper.getTestManagementThemedColor('accent_blue', this.themeState.currentTheme))
          .borderRadius(24)
          .height(48)
          .layoutWeight(1)
          .onClick(() => {
            this.handleAcceptPermission();
          })
      }
      .width('85%')
      .margin({ top: 32 })
    }
    .width('100%')
    .height('100%')
    .justifyContent(FlexAlign.Center)
    .padding({ bottom: 60 })
  }
  
  /**
   * 构建权限项
   */
  @Builder
  buildPermissionItem(icon: string, title: string, description: string) {
    Row({ space: 12 }) {
      Text(icon)
        .fontSize(20)
      
      Column({ space: 2 }) {
        Text(title)
          .fontSize(14)
          .fontWeight(FontWeight.Medium)
          .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_primary', this.themeState.currentTheme))
        
        Text(description)
          .fontSize(12)
          .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_muted', this.themeState.currentTheme))
      }
      .alignItems(HorizontalAlign.Start)
      .layoutWeight(1)
    }
    .width('100%')
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
      Text('⚠️')
        .fontSize(48)
      
      // 标题
      Text('清除阅读分析数据')
        .fontSize(18)
        .fontWeight(FontWeight.Bold)
        .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_primary', this.themeState.currentTheme))
      
      // 说明
      Text('此操作将清除所有统计和分析数据，不影响您书库当中的阅读记录，包括：')
        .fontSize(14)
        .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_secondary', this.themeState.currentTheme))
        .width('100%')
        .textAlign(TextAlign.Center)
      
      Column({ space: 6 }) {
        Text('• 阅读时长排行数据')
          .fontSize(13)
          .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_muted', this.themeState.currentTheme))
        Text('• 阅读进度分析数据')
          .fontSize(13)
          .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_muted', this.themeState.currentTheme))
        Text('• 阅读习惯分析数据')
          .fontSize(13)
          .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_muted', this.themeState.currentTheme))
        Text('• 兴趣分析数据')
          .fontSize(13)
          .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_muted', this.themeState.currentTheme))
      }
      .width('100%')
      .alignItems(HorizontalAlign.Start)
      .padding({ left: 24, right: 24 })
      
      Text('此操作不可撤销！')
        .fontSize(14)
        .fontWeight(FontWeight.Medium)
        .fontColor('#F44336')
        .margin({ top: 8 })
      
      // 按钮区域
      Column({ space: 12 }) {
        Row({ space: 16 }) {
          // 取消按钮
          Button('取消')
            .fontSize(15)
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
            .fontColor('#FFFFFF')
            .backgroundColor('#F44336')
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
    .backgroundColor(ThemeAwareHelper.getTestManagementThemedColor('panel_background', this.themeState.currentTheme))
    .borderRadius(16)
    .position({ x: '50%', y: '50%' })
    .translate({ x: '-50%', y: '-50%' })
  }

  /**
   * 构建横屏模式下的内容
   */
  @Builder
  buildLandscapeContent() {
    Column({ space: 0 }) {
      if (this.isLoading) {
        this.buildLoadingState()
      } else if (this.statistics.totalReadingTime === 0) {
        this.buildEmptyState()
      } else {
        // 横屏模式：使用两列布局
        Column({ space: 16 }) {
          // 第一行：统计概览（使用网格布局）
          Column({ space: 12 }) {
            Text('📊 阅读统计')
              .fontSize(18)
              .fontWeight(FontWeight.Bold)
              .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_primary', this.themeState.currentTheme))
              .alignSelf(ItemAlign.Start)

            Grid() {
              GridItem() {
                this.buildStatCard('总阅读时长', this.formatDuration(this.statistics.totalReadingTime), '⏱️')
              }
              GridItem() {
                this.buildStatCard('日均阅读', this.formatDuration(this.statistics.averageReadingTime), '📅')
              }
              GridItem() {
                this.buildStatCard('阅读漫画', `${this.statistics.totalComicsRead}`, '📚', '本')
              }
              GridItem() {
                this.buildStatCard('阅读章节', `${this.statistics.totalChaptersRead}`, '📖', '章')
              }
              GridItem() {
                this.buildStatCard('阅读电子书', `${this.statistics.totalEBooksRead}`, '📕', '本')
              }
              GridItem() {
                this.buildStatCard('电子书时长', this.formatDuration(this.statistics.totalEBookReadingTime), '📖')
              }
              GridItem() {
                this.buildStatCard('阅读小说', `${this.statistics.totalNovelsRead}`, '📗', '本')
              }
              GridItem() {
                this.buildStatCard('小说时长', this.formatDuration(this.statistics.totalNovelReadingTime), '📗')
              }
              GridItem() {
                this.buildStatCard('阅读页数', `${this.statistics.totalPagesRead}`, '📄', '页')
              }
              GridItem() {
                this.buildStatCard('连续阅读', `${this.statistics.continuousReadingDays}`, '🔥', '天')
              }
            }
            .columnsTemplate(`repeat(${this.responsive_statCardColumns}, 1fr)`)
            .columnsGap(12)
            .rowsGap(12)
            .width('100%')
          }
          .width('100%')
          .padding(this.responsive_contentPadding)

          // 第二行：阅读习惯和兴趣分析（左右布局）
          Row({ space: 16 }) {
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
          Row({ space: 16 }) {
            Column() {
              this.buildReadingRank()
            }
            .layoutWeight(1)

            Column() {
              this.buildDailyTrend()
            }
            .layoutWeight(1)
          }
          .width('100%')

          // 设置区域
          this.buildSettingsSection()
          
          Blank().height(40)
        }
        .width('100%')
        .constraintSize({ maxWidth: this.responsive_maxContentWidth })
      }
    }
    .width('100%')
  }

  build() {
    HdsNavDestination() {
      Stack() {
        // 背景层（纯色，响应全局主题）
        Column()
          .width('100%')
          .height('100%')
          .backgroundColor(ThemeAwareHelper.getTestManagementThemedColor('background_dark', this.themeState.currentTheme))
          .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.TOP, SafeAreaEdge.BOTTOM])
        
        // 内容层
        Column() {
          Blank().height(TITLE_BAR_HEIGHT_MINI)

          // 如果未询问过权限或功能未启用，显示权限请求界面
          if ((!this.hasAskedPermission || !this.analyticsEnabled) && !this.isLoading) {
            this.buildPermissionRequest()
          } else if (this.isLongTermView) {
            // 长期视图
            // 时间范围选择器
            Row() {
              this.buildTimeRangeSelector()
            }
            .width('100%')
            .constraintSize({ maxWidth: this.responsive_isLandscape ? this.responsive_maxContentWidth : '100%' })

            Scroll(this.scroller) {
              if (this.responsive_isLandscape) {
                // 横屏模式：使用更紧凑的布局
                this.buildLandscapeContent()
              } else {
                // 竖屏模式：使用原有布局
                Column({ space: 0 }) {
                  if (this.isLoading) {
                    this.buildLoadingState()
                  } else if (this.statistics.totalReadingTime === 0) {
                    this.buildEmptyState()
                  } else {
                    this.buildStatisticsOverview()
                    this.buildReadingHabits()
                    this.buildInterestAnalysis()
                    this.buildReadingRank()
                    this.buildDailyTrend()
                    this.buildSettingsSection()
                    
                    Blank().height(40)
                  }
                }
                .width('100%')
              }
            }
            .edgeEffect(EdgeEffect.Spring)
            .scrollBar(BarState.Auto)
            .layoutWeight(1)
          } else {
            // 日视图
            Scroll(this.scroller) {
              Column({ space: 0 }) {
                if (this.isLoading) {
                  this.buildLoadingState()
                } else {
                  this.buildDailyViewContent()
                  Blank().height(40)
                }
              }
              .width('100%')
            }
            .edgeEffect(EdgeEffect.Spring)
            .scrollBar(BarState.Auto)
            .layoutWeight(1)
          }
        }
        .width('100%')
        .height('100%')
        .alignItems(this.responsive_isLandscape ? HorizontalAlign.Center : HorizontalAlign.Start)

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
          .position({ x: 0, y: 0 })

          // 选择器面板
          Column() {
            // 标题栏
            Row() {
              Text('取消')
                .fontSize(16)
                .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_secondary', this.themeState.currentTheme))
                .onClick(() => {
                  this.showRetentionPicker = false;
                })
              
              Text('选择数据保留天数')
                .fontSize(16)
                .fontWeight(FontWeight.Medium)
                .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_primary', this.themeState.currentTheme))
                .layoutWeight(1)
                .textAlign(TextAlign.Center)
              
              Text('确定')
                .fontSize(16)
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
          .backgroundColor(ThemeAwareHelper.getTestManagementThemedColor('panel_background', this.themeState.currentTheme))
          .borderRadius({ topLeft: 16, topRight: 16 })
          .position({ x: 0, y: '100%' })
          .translate({ y: -280 })
        }
        
        // 清除数据确认对话框
        if (this.showClearDataDialog) {
          this.buildClearDataDialog()
        }
      }
    }
    .titleBar({
      padding: {
        start: LengthMetrics.vp(16),
        end: LengthMetrics.vp(16)
      },
      style: {
        scrollEffectOpts: {
          enableScrollEffect: true,
          scrollEffectType: ScrollEffectType.COMMON_BLUR,
          blurEffectiveStartOffset: LengthMetrics.vp(0),
          blurEffectiveEndOffset: LengthMetrics.vp(TITLE_BAR_HEIGHT_MINI)
        },
        originalStyle: {
          backgroundStyle: { backgroundColor: Color.Transparent },
          contentStyle: {
            titleStyle: { mainTitleColor: ThemeAwareHelper.getTestManagementThemedColor('text_primary', this.themeState.currentTheme) },
            backIconStyle: {
              backgroundColor: ThemeAwareHelper.getTestManagementThemedColor('comp_background_tertiary', this.themeState.currentTheme),
              iconColor: ThemeAwareHelper.getTestManagementThemedColor('icon_primary', this.themeState.currentTheme)
            }
          }
        },
        scrollEffectStyle: {
          backgroundStyle: {
            backgroundColor: this.themeState.currentTheme === ThemeType.DARK ? '#E61A1A1A' : '#E6F5F5F5'
          },
          contentStyle: {
            titleStyle: { mainTitleColor: ThemeAwareHelper.getTestManagementThemedColor('text_primary', this.themeState.currentTheme) },
            backIconStyle: {
              backgroundColor: ThemeAwareHelper.getTestManagementThemedColor('comp_background_tertiary', this.themeState.currentTheme),
              iconColor: ThemeAwareHelper.getTestManagementThemedColor('icon_primary', this.themeState.currentTheme)
            }
          }
        }
      },
      content: {
        title: { mainTitle: '阅读报告' },
        menu: {
          value: [{
            content: {
              label: this.isLongTermView ? '日视图' : '长期视图',
              icon: this.isLongTermView ? $r('app.media.ic_calendar_day') : $r('app.media.ic_calendar_range'),
              isEnabled: this.hasAskedPermission && !this.isLoading,
              action: () => {
                this.toggleViewMode();
              }
            }
          }, {
            content: {
              label: '清除数据',
              icon: $r('app.media.ic_delete'),
              isEnabled: this.hasAskedPermission && !this.isLoading,
              action: () => {
                this.showClearDataConfirmDialog();
              }
            }
          }]
        }
      }
    })
    .onReady((context: NavDestinationContext) => {
      this.pathStack = context.pathStack;
      this.onPageShow();
      this.onReady();
    })
    .backgroundColor(Color.Transparent)
  }
}

export { ReadingAnalyticsPage }

