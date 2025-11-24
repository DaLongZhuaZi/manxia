// 文件路径: entry/src/main/ets/pages/ReadingAnalyticsPage.ets
/**
 * 阅读数据分析报告页面
 * 根据用户的阅读记录，分析并展示阅读习惯、统计数据等
 */

import { HdsNavDestination, HdsNavDestinationAttribute, ScrollEffectType } from '@kit.UIDesignKit';
import { LengthMetrics } from '@kit.ArkUI';
import { ThemeAwareState, ThemeAwareHelper } from '../Framework/Components/ThemeAware';
import { ThemeManager, ThemeType } from '../Framework/Managers/ThemeManager';
import { logger } from '../Utils/Logger';
import { DataService } from '../Framework/Services/DataService';
import { ReadHistory, DataManager } from '../Framework/Data/DataManager';

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

@Component
struct ReadingAnalyticsPage {
  @State pathStack: NavPathStack = new NavPathStack();
  private scroller: Scroller = new Scroller();

  // 主题相关状态
  @State themeState: ThemeAwareState = new ThemeAwareState();
  private themeManager: ThemeManager = ThemeManager.getInstance();
  private componentId: string = 'ReadingAnalyticsPage';

  // 数据服务
  private dataService: DataService = DataService.getInstance();

  // 统计数据状态
  @State isLoading: boolean = true;
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

  // 时间范围选择
  @State selectedTimeRange: number = 7; // 默认最近7天

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

    // 加载阅读数据
    this.loadReadingData().catch((error: Error) => {
      logger.error(TAG, '加载阅读数据失败', error.message);
    });
  }

  aboutToDisappear(): void {
    ThemeAwareHelper.cleanupThemeAware(this.componentId);
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
      this.analyzeReadingData(readHistory);

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

  private goBack(): void {
    try {
      this.pathStack.pop();
    } catch (error) {
      logger.error(TAG, '返回失败', String(error));
    }
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

  build() {
    HdsNavDestination() {
      Stack() {
        Column()
          .width('100%')
          .height('100%')
          .backgroundColor(ThemeAwareHelper.getTestManagementThemedColor('background_dark', this.themeState.currentTheme))
          .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.TOP, SafeAreaEdge.BOTTOM])
        
        Column() {
          Blank().height(TITLE_BAR_HEIGHT_MINI)

          // 时间范围选择器
          this.buildTimeRangeSelector()

          Scroll(this.scroller) {
            Column({ space: 0 }) {
              if (this.isLoading) {
                this.buildLoadingState()
              } else if (this.statistics.totalReadingTime === 0) {
                this.buildEmptyState()
              } else {
                this.buildStatisticsOverview()
                this.buildReadingHabits()
                this.buildDailyTrend()
                
                Blank().height(40)
              }
            }
            .width('100%')
          }
          .edgeEffect(EdgeEffect.Spring)
          .scrollBar(BarState.Auto)
          .layoutWeight(1)
        }
        .width('100%')
        .height('100%')
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
              label: '切换主题',
              icon: $r('app.media.SculptureLargeAnimalistA'),
              isEnabled: true,
              action: () => { this.themeManager.toggleTheme(); }
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

