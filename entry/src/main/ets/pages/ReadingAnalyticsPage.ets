// 文件路径: entry/src/main/ets/pages/ReadingAnalyticsPage.ets
/**
 * 阅读数据分析报告页面
 * 根据用户的阅读记录，分析并展示阅读习惯、统计数据等
 */

import { HdsNavDestination, HdsNavDestinationAttribute, ScrollEffectType } from '@kit.UIDesignKit';
import { LengthMetrics } from '@kit.ArkUI';
import { ThemeAwareState, ThemeAwareHelper } from '../Framework/Components/ThemeAware';
import { ThemeManager, ThemeType } from '../Framework/Managers/ThemeManager';
import { GlobalBackgroundLayer } from '../Framework/Components/GlobalBackgroundLayer';
import { DeviceAdaptationManager, DeviceInfo, DeviceChangeListener, Breakpoint } from '../Framework/Managers/DeviceAdaptationManager';
import { ResponsiveLayoutHelper } from '../Framework/Utils/ResponsiveLayout';
import { logger } from '../Utils/Logger';
import { DataService } from '../Framework/Services/DataService';
import { ReadHistory, DataManager, ComicInfo } from '../Framework/Data/DataManager';
import { ReadingAnalyticsManager, RETENTION_DAYS_OPTIONS } from '../Framework/Managers/ReadingAnalyticsManager';
import { EBookDataManager } from '../Framework/Data/EBookDataManager';
import { EBook } from '../Models/EBookModels';

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
  totalReadingTime: number;      // 总阅读时长（分钟）
  totalComicsRead: number;        // 阅读过的漫画总数
  totalChaptersRead: number;      // 阅读过的章节总数
  totalPagesRead: number;         // 阅读的总页数
  averageReadingTime: number;     // 平均每天阅读时长（分钟）
  favoriteReadingHour: number;    // 最喜欢的阅读时段（小时）
  mostReadComicId: string;        // 阅读最多的漫画ID
  mostReadComicTitle: string;     // 阅读最多的漫画标题
  continuousReadingDays: number;  // 连续阅读天数
  lastReadTime: number;           // 最后阅读时间
}

/**
 * 每日阅读数据
 */
interface DailyReadingData {
  date: string;                   // 日期字符串（YYYY-MM-DD）
  readingTime: number;            // 阅读时长（分钟）
  chaptersRead: number;           // 阅读章节数
  pagesRead: number;              // 阅读页数
}

/**
 * 阅读时段分布数据
 */
interface HourlyDistribution {
  hour: number;                   // 小时（0-23）
  readingCount: number;           // 阅读次数
  readingTime: number;            // 阅读时长（分钟）
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
  ebookId: string;
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
    favoriteReadingHour: 0,
    mostReadComicId: '',
    mostReadComicTitle: '暂无数据',
    continuousReadingDays: 0,
    lastReadTime: 0
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
      // 标记已询问过权限，下次不再显示权限请求界面
      await this.analyticsManager.markAskedPermission();
      this.analyticsEnabled = false;
      this.hasAskedPermission = true;
      logger.info(TAG, '用户拒绝阅读报告权限，功能保持关闭');
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
   * 清除阅读分析数据
   */
  private async clearReadingAnalyticsData(): Promise<void> {
    try {
      logger.info(TAG, '开始清除阅读分析数据');

      // 清除阅读历史
      await this.dataService.clearReadingHistory();

      // 重置统计数据
      this.statistics = {
        totalReadingTime: 0,
        totalComicsRead: 0,
        totalChaptersRead: 0,
        totalPagesRead: 0,
        averageReadingTime: 0,
        favoriteReadingHour: 0,
        mostReadComicId: '',
        mostReadComicTitle: '暂无数据',
        continuousReadingDays: 0,
        lastReadTime: 0
      };
      this.dailyData = [];
      this.hourlyDistribution = [];
      this.readingRankList = [];
      this.interestItems = [];

      this.showClearDataDialog = false;
      logger.info(TAG, '阅读分析数据已清除');
    } catch (error) {
      logger.error(TAG, `清除阅读分析数据失败: ${String(error)}`);
    }
  }

  /**
   * 清除数据并关闭阅读报告功能，然后返回
   */
  private async clearDataAndDisableAnalytics(): Promise<void> {
    try {
      logger.info(TAG, '开始清除阅读分析数据并关闭功能');

      // 清除阅读历史
      await this.dataService.clearReadingHistory();

      // 关闭阅读报告功能
      await this.analyticsManager.setEnabled(false);
      this.analyticsEnabled = false;

      // 重置权限询问状态，下次进入需要重新询问
      await this.analyticsManager.resetAskedPermission();
      this.hasAskedPermission = false;

      // 重置统计数据
      this.statistics = {
        totalReadingTime: 0,
        totalComicsRead: 0,
        totalChaptersRead: 0,
        totalPagesRead: 0,
        averageReadingTime: 0,
        favoriteReadingHour: 0,
        mostReadComicId: '',
        mostReadComicTitle: '暂无数据',
        continuousReadingDays: 0,
        lastReadTime: 0
      };
      this.dailyData = [];
      this.hourlyDistribution = [];
      this.readingRankList = [];
      this.interestItems = [];

      this.showClearDataDialog = false;
      logger.info(TAG, '阅读分析数据已清除，功能已关闭，权限状态已重置，准备返回');

      // 返回上一页
      this.pathStack.pop();
    } catch (error) {
      logger.error(TAG, `清除数据并关闭功能失败: ${String(error)}`);
    }
  }

  /**
   * 加载阅读数据
   */
  private async loadReadingData(): Promise<void> {
    this.isLoading = true;
    try {
      logger.info(TAG, '开始加载阅读数据');

      // 获取阅读历史记录
      const readHistory: ReadHistory[] = await this.dataService.getReadingHistory(1000);
      logger.debug(TAG, `获取到 ${readHistory.length} 条阅读记录`);

      if (readHistory.length === 0) {
        logger.info(TAG, '暂无阅读记录');
        this.isLoading = false;
        return;
      }

      // 分析数据
      await this.analyzeReadingData(readHistory);

      // 加载阅读时长排行
      await this.loadReadingRank(readHistory);

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
   * 分析阅读数据
   */
  private async analyzeReadingData(readHistory: ReadHistory[]): Promise<void> {
    try {
      const now = Date.now();
      const timeRangeMs = this.selectedTimeRange * 24 * 60 * 60 * 1000;
      const startTime = now - timeRangeMs;

      // 过滤时间范围内的记录
      const filteredHistory = readHistory.filter(record => record.readTime >= startTime);

      // 统计总阅读时长
      const totalReadingTimeSeconds = filteredHistory.reduce((sum: number, record: ReadHistory): number => {
        return sum + record.readDuration;
      }, 0);
      this.statistics.totalReadingTime = Math.round(totalReadingTimeSeconds / 60);

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

      // 计算平均每天阅读时长
      this.statistics.averageReadingTime = this.selectedTimeRange > 0
        ? Math.round(this.statistics.totalReadingTime / this.selectedTimeRange)
        : 0;

      // 分析阅读时段分布
      this.analyzeHourlyDistribution(filteredHistory);

      // 分析每日阅读数据
      this.analyzeDailyData(filteredHistory);

      // 查找阅读最多的漫画
      await this.findMostReadComic(filteredHistory);

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
        existing.time += Math.round(record.readDuration / 60);
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
    let favoriteHour = 0;
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
        existing.time += Math.round(record.readDuration / 60);
        existing.chapters.add(record.chapterId);
        existing.pages += 1;
        dailyMap.set(dateKey, existing);
      } else {
        const chapters = new Set<string>();
        chapters.add(record.chapterId);
        const newData: DailyStatData = {
          time: Math.round(record.readDuration / 60),
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
   * 加载阅读时长排行
   */
  private async loadReadingRank(readHistory: ReadHistory[]): Promise<void> {
    try {
      // 按漫画ID统计阅读时长
      const readingTimeMap = new Map<string, number>();
      readHistory.forEach(record => {
        const currentTime = readingTimeMap.get(record.comicId) || 0;
        readingTimeMap.set(record.comicId, currentTime + Math.round(record.readDuration / 60));
      });

      // 转换为数组并排序
      const rankEntries = Array.from(readingTimeMap.entries());
      rankEntries.sort((a, b) => b[1] - a[1]);

      // 获取前10名的详细信息
      const rankList: ReadingRankItem[] = [];
      for (let i = 0; i < Math.min(10, rankEntries.length); i++) {
        const comicId: string = rankEntries[i][0];
        const readingTime: number = rankEntries[i][1];

        try {
          const comic: ComicInfo | null = await this.dataManager.getComicById(comicId);
          if (comic) {
            // 优先使用本地封面路径，其次使用网络URL
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
          // 可能是电子书，尝试从电子书数据库查询
          try {
            const ebook: EBook | null = await this.ebookDataManager.getEBookById(comicId);
            if (ebook) {
              const rankItem: ReadingRankItem = {
                id: comicId,
                title: ebook.metadata.title,
                coverPath: ebook.metadata.coverImagePath || '',
                readingTime: readingTime,
                type: 'ebook'
              };
              rankList.push(rankItem);
            }
          } catch (e2) {
            logger.warn(TAG, `无法找到作品信息: ${comicId}`);
          }
        }
      }

      this.readingRankList = rankList;
      logger.info(TAG, `阅读时长排行加载完成，共 ${rankList.length} 项`);
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
        const params: EBookDetailParams = { ebookId: item.id };
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
   * 规范化封面路径：本地文件添加 file:// 前缀
   */
  private normalizeCoverPath(path: string): string {
    if (!path || path.length === 0) {
      return '';
    }
    // 如果是本地路径（以 / 开头），添加 file:// 前缀
    if (path.startsWith('/')) {
      return `file://${path}`;
    }
    return path;
  }

  /**
   * 格式化时长
   */
  private formatDuration(minutes: number): string {
    if (minutes < 60) {
      return `${minutes}分钟`;
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
   * 构建时间范围选择器
   */
  @Builder
  buildTimeRangeSelector() {
    Row({ space: 8 }) {
      Button({ stateEffect: true }) {
        Text('7天')
          .fontSize(12)
          .fontColor(ThemeAwareHelper.getTestManagementThemedColor('button_text_secondary', this.themeState.currentTheme))
      }
      .width('25%')
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
      .width('25%')
      .height(32)
      .backgroundColor(
        (this.selectedTimeRange === 30
          ? ThemeAwareHelper.getTestManagementThemedColor('accent_blue', this.themeState.currentTheme)
          : ThemeAwareHelper.getTestManagementThemedColor('button_inactive', this.themeState.currentTheme)) as ResourceColor
      )
      .borderRadius(8)
      .onClick(() => this.changeTimeRange(30))

      Button({ stateEffect: true }) {
        Text('90天')
          .fontSize(12)
          .fontColor(ThemeAwareHelper.getTestManagementThemedColor('button_text_secondary', this.themeState.currentTheme))
      }
      .width('25%')
      .height(32)
      .backgroundColor(
        (this.selectedTimeRange === 90
          ? ThemeAwareHelper.getTestManagementThemedColor('accent_blue', this.themeState.currentTheme)
          : ThemeAwareHelper.getTestManagementThemedColor('button_inactive', this.themeState.currentTheme)) as ResourceColor
      )
      .borderRadius(8)
      .onClick(() => this.changeTimeRange(90))

      Button({ stateEffect: true }) {
        Text('全部')
          .fontSize(12)
          .fontColor(ThemeAwareHelper.getTestManagementThemedColor('button_text_secondary', this.themeState.currentTheme))
      }
      .width('25%')
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
   * 构建统计卡片
   */
  @Builder
  buildStatCard(title: string, value: string, icon: string, subtitle?: string) {
    Column({ space: 8 }) {
      Row({ space: 8 }) {
        Text(icon)
          .fontSize(24)

        Column({ space: 4 }) {
          Text(title)
            .fontSize(12)
            .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_secondary', this.themeState.currentTheme))

          Text(value)
            .fontSize(20)
            .fontWeight(FontWeight.Bold)
            .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_primary', this.themeState.currentTheme))

          if (subtitle) {
            Text(subtitle)
              .fontSize(10)
              .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_muted', this.themeState.currentTheme))
          }
        }
        .alignItems(HorizontalAlign.Start)
        .layoutWeight(1)
      }
      .width('100%')
    }
    .width('100%')
    .padding(16)
    .backgroundColor(ThemeAwareHelper.getTestManagementThemedColor('panel_background', this.themeState.currentTheme))
    .borderRadius(12)
    .border({
      width: 1,
      color: ThemeAwareHelper.getTestManagementThemedColor('panel_border', this.themeState.currentTheme)
    })
  }

  /**
   * 构建统计概览区域
   */
  @Builder
  buildStatisticsOverview() {
    Column({ space: 12 }) {
      Text('📊 阅读统计')
        .fontSize(18)
        .fontWeight(FontWeight.Bold)
        .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_primary', this.themeState.currentTheme))
        .alignSelf(ItemAlign.Start)

      // 第一行：总阅读时长和平均时长
      Row({ space: 12 }) {
        this.buildStatCard(
          '总阅读时长',
          this.formatDuration(this.statistics.totalReadingTime),
          '⏱️'
        )

        this.buildStatCard(
          '日均阅读',
          this.formatDuration(this.statistics.averageReadingTime),
          '📅'
        )
      }
      .width('100%')

      // 第二行：漫画数和章节数
      Row({ space: 12 }) {
        this.buildStatCard(
          '阅读漫画',
          `${this.statistics.totalComicsRead}`,
          '📚',
          '本'
        )

        this.buildStatCard(
          '阅读章节',
          `${this.statistics.totalChaptersRead}`,
          '📖',
          '章'
        )
      }
      .width('100%')

      // 第三行：总页数和连续天数
      Row({ space: 12 }) {
        this.buildStatCard(
          '阅读页数',
          `${this.statistics.totalPagesRead}`,
          '📄',
          '页'
        )

        this.buildStatCard(
          '连续阅读',
          `${this.statistics.continuousReadingDays}`,
          '🔥',
          '天'
        )
      }
      .width('100%')
    }
    .width('100%')
    .padding(16)
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

          Text(`${this.statistics.favoriteReadingHour}:00 - ${this.statistics.favoriteReadingHour + 1}:00`)
            .fontSize(16)
            .fontWeight(FontWeight.Bold)
            .fontColor(ThemeAwareHelper.getTestManagementThemedColor('accent_blue', this.themeState.currentTheme))
        }
        .width('100%')
      }
      .width('100%')
      .padding(16)
      .backgroundColor(ThemeAwareHelper.getTestManagementThemedColor('panel_background', this.themeState.currentTheme))
      .borderRadius(12)
      .border({
        width: 1,
        color: ThemeAwareHelper.getTestManagementThemedColor('panel_border', this.themeState.currentTheme)
      })

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
        .backgroundColor(ThemeAwareHelper.getTestManagementThemedColor('panel_background', this.themeState.currentTheme))
        .borderRadius(12)
        .border({
          width: 1,
          color: ThemeAwareHelper.getTestManagementThemedColor('panel_border', this.themeState.currentTheme)
        })
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
        .backgroundColor(ThemeAwareHelper.getTestManagementThemedColor('panel_background', this.themeState.currentTheme))
        .borderRadius(12)
        .border({
          width: 1,
          color: ThemeAwareHelper.getTestManagementThemedColor('panel_border', this.themeState.currentTheme)
        })
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
                  Text(`${data.readingTime}分钟`)
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
            .backgroundColor(ThemeAwareHelper.getTestManagementThemedColor('panel_background', this.themeState.currentTheme))
            .borderRadius(8)
            .border({
              width: 1,
              color: ThemeAwareHelper.getTestManagementThemedColor('panel_border', this.themeState.currentTheme)
            })
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

        // 兴趣标签云
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
            .backgroundColor(ThemeAwareHelper.getTestManagementThemedColor('background_secondary', this.themeState.currentTheme))
            .borderRadius(16)
            .margin({ right: 8, bottom: 8 })
          }, (item: InterestItem, index: number) => `${item.keyword}-${index}`)
        }
        .width('100%')
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
                    Image(this.normalizeCoverPath(item.coverPath))
                      .width('100%')
                      .height(120)
                      .objectFit(ImageFit.Cover)
                      .borderRadius(8)
                  } else {
                    Column() {
                      Text(item.type === 'manga' ? '📚' : '📖')
                        .fontSize(32)
                    }
                    .width('100%')
                    .height(120)
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
      .backgroundColor(ThemeAwareHelper.getTestManagementThemedColor('panel_background', this.themeState.currentTheme))
      .borderRadius(12)
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
      .backgroundColor(ThemeAwareHelper.getTestManagementThemedColor('panel_background', this.themeState.currentTheme))
      .borderRadius(12)

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

      Text('暂无阅读记录')
        .fontSize(18)
        .fontWeight(FontWeight.Medium)
        .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_primary', this.themeState.currentTheme))

      Text('开始阅读漫画后，这里将显示您的阅读统计和分析数据')
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
        // 背景层
        GlobalBackgroundLayer({
          defaultBackgroundColor: ThemeAwareHelper.getTestManagementThemedColor('background_primary', this.themeState.currentTheme)
        })

        // 内容层
        Column() {
          Blank().height(TITLE_BAR_HEIGHT_MINI)

          // 如果未询问过权限，显示权限请求界面
          if (!this.hasAskedPermission && !this.isLoading) {
            this.buildPermissionRequest()
          } else {
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

