// 文件路径: entry/src/main/ets/pages/DownloadManagerPage.ets
/**
 * 下载管理页面
 * 管理漫画章节的下载任务，显示下载进度和状态
 */

import { HdsNavDestination, HdsNavDestinationAttribute, ScrollEffectType } from '@kit.UIDesignKit';
import { LengthMetrics } from '@kit.ArkUI';
import { common } from '@kit.AbilityKit';
import { ThemeAwareState, ThemeAwareHelper } from '../Framework/Components/ThemeAware';
import { ThemeManager, ThemeType } from '../Framework/Managers/ThemeManager';
import { FontAwareHelper, FontAwareState } from '../Framework/Components/FontAware';
import { logger } from '../Utils/Logger';
import { PageLifecycleManager } from '../Framework/Lifecycle';
import { DownloadStatus } from '../Framework/Types/StatusEnums';
import { MangaDownloadManager, DownloadTaskInfo, TaskStatus } from '../Framework/Download/DownloadManager';
import { getCacheStatusService, CacheStatusService, ContentCacheStats, CacheContentType } from '../Framework/Services/CacheStatusService';
import { getUnifiedDownloadManager, UnifiedDownloadManager, UnifiedDownloadTask, UnifiedTaskStatus, UnifiedDownloadType } from '../Framework/Download/UnifiedDownloadManager';
import { OnlineArchiveMigrationItem, OnlineArchiveMigrationStatus, OnlineArchiveMigrationSummary, OnlineMangaArchiveService } from '../Framework/Download/OnlineMangaArchiveService';
import { PermanentImageCacheManager } from '../Framework/Cache/PermanentImageCacheManager';
import { DataManager } from '../Framework/Data/DataManager';
import { eventBus, GameEvent, IEventPayload, MangaCacheUpdatedPayload } from '../Framework/EventBus';
import { SettingsImmersiveTitleBar } from './settings/SettingsImmersiveTitleBar';
import { SettingsPageTitleBarManager } from './settings/SettingsPageTitleBarManager';
import { GlobalBackgroundLayerMode } from '../Framework/Components/GlobalBackgroundLayer';
import { SharedPageBackgroundLayer } from '../Framework/Components/SharedPageBackgroundLayer';
import { SettingsPanelSurfaceHelper } from './settings/SettingsPanelSurfaceHelper';

const TAG = 'DownloadManagerPage';
const TITLE_BAR_HEIGHT_MINI: number = 56;

// 下载任务接口
interface DownloadTask {
  id: string;
  mangaTitle: string;
  chapterTitle: string;
  progress: number;
  status: DownloadStatus;
  totalPages: number;
  downloadedPages: number;
  speed: string; // 下载速度，如 "2.5 MB/s"
  remainingTime: string; // 剩余时间，如 "3分钟"
}

type DownloadContentTypeTab = 'downloads' | 'manga_cache' | 'migration';

// 使用NavDestinationContext官方类型
// @kit.ArkUI提供的NavDestinationContext已包含必要的类型定义

@Component
struct DownloadManagerPage {
  @State pathStack: NavPathStack = new NavPathStack();
  private scroller: Scroller = new Scroller();

  // 主题相关状态
  @State themeState: ThemeAwareState = new ThemeAwareState();
  @State fontState: FontAwareState = new FontAwareState();
  @StorageLink('appFontFamily') appFontFamily: string = 'HarmonyOS Sans';
  @StorageProp('statusBarHeight') statusBarHeight: number = 0;
  @StorageProp('navigationBarHeight') navigationBarHeight: number = 0;
  private themeManager: ThemeManager = ThemeManager.getInstance();
  private componentId: string = 'DownloadManagerPage';

  // 下载任务列表
  @State downloadTasks: DownloadTask[] = [];
  @State isLoading: boolean = true;
  @State selectedTasks: Set<string> = new Set();
  @State isSelectionMode: boolean = false;

  // 过滤选项
  @State filterStatus: string = 'all'; // 'all' | 'downloading' | 'paused' | 'completed' | 'failed'
  
  // 内容类型分类
  @State contentTypeTab: DownloadContentTypeTab = 'downloads';
  @State private swipeStartX: number = 0;
  @State private swipeOffsetX: number = 0;
  
  // 缓存状态
  @State mangaCacheList: ContentCacheStats[] = [];
  @State novelCacheList: ContentCacheStats[] = [];
  @State isCacheLoading: boolean = false;

  // 在线漫画CBZ迁移状态
  @State migrationRunning: boolean = false;
  @State migrationHasRun: boolean = false;
  @State migrationSummary: OnlineArchiveMigrationSummary | null = null;
  @State migrationResults: OnlineArchiveMigrationItem[] = [];
  
  // 下载管理器
  private downloadManager: MangaDownloadManager = MangaDownloadManager.getInstance();
  private unifiedDownloadManager: UnifiedDownloadManager = getUnifiedDownloadManager();
  private cacheStatusService: CacheStatusService = getCacheStatusService();
  private permanentCacheManager: PermanentImageCacheManager = PermanentImageCacheManager.getInstance();
  private onlineArchiveService: OnlineMangaArchiveService = OnlineMangaArchiveService.getInstance();
  private dataManager: DataManager = DataManager.getInstance();
  private updateTimer: number = -1;
  private readonly contentTypeTabOrder: DownloadContentTypeTab[] = ['downloads', 'manga_cache', 'migration'];

  private onMangaCacheUpdated: (payload: IEventPayload) => void = (payload: IEventPayload): void => {
    const cachePayload = payload as MangaCacheUpdatedPayload;
    this.refreshTasks();
    void this.loadCacheLists();
    logger.info(TAG, `收到漫画缓存更新事件，刷新下载管理缓存列表: mangaId=${cachePayload.mangaId}, reason=${cachePayload.reason}`);
  };

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
    const hostContext = this.getUIContext().getHostContext();
    if (hostContext) {
      this.onlineArchiveService.setContext(hostContext as common.UIAbilityContext);
    }
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
    eventBus.subscribe(GameEvent.MANGA_CACHE_UPDATED, this.onMangaCacheUpdated);

    // 加载下载任务
    this.loadDownloadTasks();
  }

  private lifecycle = new PageLifecycleManager('DownloadManagerPage', { enableDebug: true });

  aboutToDisappear(): void {
    this.lifecycle.destroy();
    ThemeAwareHelper.cleanupThemeAware(this.componentId);
    FontAwareHelper.cleanupFontAware(this.componentId);
    eventBus.unsubscribe(GameEvent.MANGA_CACHE_UPDATED, this.onMangaCacheUpdated);
    
    // 清除定时器
    if (this.updateTimer !== -1) {
      clearInterval(this.updateTimer);
      this.updateTimer = -1;
    }
  }

  /**
   * 加载下载任务
   */
  private async loadDownloadTasks(): Promise<void> {
    this.isLoading = true;
    try {
      // 从下载管理器获取所有任务
      const tasks = this.downloadManager.getAllTasks();
      
      // 同时加载缓存列表
      this.loadCacheLists();
      
      // 转换为页面使用的格式
      this.downloadTasks = tasks.map((task: DownloadTaskInfo) => {
        return {
          id: task.id,
          mangaTitle: task.mangaTitle,
          chapterTitle: task.chapterTitle,
          progress: task.progress,
          status: this.convertTaskStatus(task.status),
          totalPages: task.totalCount,
          downloadedPages: task.downloadedCount,
          speed: this.calculateSpeed(task),
          remainingTime: this.calculateRemainingTime(task)
        } as DownloadTask;
      });
      
      this.isLoading = false;
      logger.info(TAG, `加载了 ${this.downloadTasks.length} 个下载任务`);
      
      // 启动定时器，每秒更新一次任务状态
      this.startUpdateTimer();
    } catch (error) {
      logger.error(TAG, '加载下载任务失败', String(error));
      this.isLoading = false;
    }
  }
  
  /**
   * 启动更新定时器
   */
  private startUpdateTimer(): void {
    if (this.updateTimer !== -1) {
      clearInterval(this.updateTimer);
    }
    
    this.updateTimer = setInterval(() => {
      this.refreshTasks();
    }, 1000);
  }
  
  /**
   * 刷新任务列表
   */
  private refreshTasks(): void {
    const tasks = this.downloadManager.getAllTasks();
    this.downloadTasks = tasks.map((task: DownloadTaskInfo) => {
      return {
        id: task.id,
        mangaTitle: task.mangaTitle,
        chapterTitle: task.chapterTitle,
        progress: task.progress,
        status: this.convertTaskStatus(task.status),
        totalPages: task.totalCount,
        downloadedPages: task.downloadedCount,
        speed: this.calculateSpeed(task),
        remainingTime: this.calculateRemainingTime(task)
      } as DownloadTask;
    });
  }
  
  /**
   * 转换任务状态
   */
  private convertTaskStatus(status: TaskStatus): DownloadStatus {
    switch (status) {
      case TaskStatus.PENDING:
        return DownloadStatus.PENDING;
      case TaskStatus.DOWNLOADING:
        return DownloadStatus.DOWNLOADING;
      case TaskStatus.PAUSED:
        return DownloadStatus.PAUSED;
      case TaskStatus.COMPLETED:
        return DownloadStatus.COMPLETED;
      case TaskStatus.FAILED:
        return DownloadStatus.FAILED;
      default:
        return DownloadStatus.PENDING;
    }
  }
  
  /**
   * 计算下载速度
   */
  private calculateSpeed(task: DownloadTaskInfo): string {
    if (task.status !== TaskStatus.DOWNLOADING) {
      return '-';
    }
    // 简单估算：假设每张图片平均2MB
    const avgImageSize = 2;
    const speed = avgImageSize * 0.5; // 假设每秒下载0.5张图片
    return `${speed.toFixed(1)} MB/s`;
  }
  
  /**
   * 计算剩余时间
   */
  private calculateRemainingTime(task: DownloadTaskInfo): string {
    if (task.status !== TaskStatus.DOWNLOADING) {
      return '-';
    }
    const remaining = task.totalCount - task.downloadedCount;
    if (remaining <= 0) {
      return '即将完成';
    }
    // 假设每张图片需要2秒
    const seconds = remaining * 2;
    if (seconds < 60) {
      return `${seconds}秒`;
    } else {
      const minutes = Math.floor(seconds / 60);
      return `${minutes}分钟`;
    }
  }
  
  /**
   * 加载缓存列表
   * [改进] 直接从数据库查询所有有缓存的漫画，不再依赖文件系统扫描
   */
  private async loadCacheLists(): Promise<void> {
    this.isCacheLoading = true;
    try {
      // [改进] 直接从数据库获取所有有缓存的漫画
      const cachedMangas = await this.dataManager.getAllCachedMangas();
      const mangaCacheList: ContentCacheStats[] = [];
      
      logger.info(TAG, `数据库返回 ${cachedMangas.length} 部漫画，开始获取详细缓存状态...`);
      
      // 为每部漫画获取详细的缓存状态
      for (const manga of cachedMangas) {
        logger.info(TAG, `检查漫画: id=${manga.mangaId}, title=${manga.mangaTitle}, sourceId=${manga.sourceId}`);
        
        if (manga.mangaId) {
          // 移除 sourceId > 0 的限制，因为某些漫画的sourceId可能为0或未设置
          const cacheStatus = await this.cacheStatusService.getMangaCacheStatus(
            manga.sourceId || 0,
            manga.mangaId,
            manga.mangaTitle
          );
          
          logger.info(TAG, `漫画 [${manga.mangaTitle}] 缓存状态: cachedPages=${cacheStatus.cachedPageCount}, totalPages=${cacheStatus.totalPageCount}`);
          
          // 只添加有实际缓存的漫画
          if (cacheStatus.cachedPageCount > 0) {
            mangaCacheList.push(cacheStatus);
          }
        }
      }
      this.mangaCacheList = mangaCacheList;
      
      logger.info(TAG, `加载了 ${this.mangaCacheList.length} 个漫画缓存`);
    } catch (error) {
      logger.error(TAG, `加载缓存列表失败: ${String(error)}`);
    } finally {
      this.isCacheLoading = false;
    }
  }
  
  /**
   * 清理指定缓存
   */
  private async clearCacheItem(stats: ContentCacheStats): Promise<void> {
    try {
      await this.cacheStatusService.clearContentCache(
        stats.contentType,
        stats.contentId,
        stats.sourceId
      );
      // 重新加载缓存列表
      await this.loadCacheLists();
      logger.info(TAG, `已清理缓存: ${stats.title}`);
    } catch (error) {
      logger.error(TAG, `清理缓存失败: ${String(error)}`);
    }
  }

  private async startArchiveMigration(): Promise<void> {
    if (this.migrationRunning) {
      return;
    }

    this.migrationRunning = true;
    this.migrationHasRun = true;
    try {
      const summary = await this.onlineArchiveService.runLegacyCacheMigration();
      this.migrationSummary = summary;
      this.migrationResults = summary.items;
      await this.loadCacheLists();
      logger.info(TAG, `CBZ迁移完成: migrated=${summary.migratedCount}, skipped=${summary.skippedCount}, failed=${summary.failedCount}`);
    } catch (error) {
      logger.error(TAG, `CBZ迁移执行失败: ${String(error)}`);
      const failedSummary: OnlineArchiveMigrationSummary = {
        totalCandidates: 0,
        migratedCount: 0,
        skippedCount: 0,
        failedCount: 1,
        totalArchiveSize: 0,
        startedAt: Date.now(),
        completedAt: Date.now(),
        items: []
      };
      this.migrationSummary = failedSummary;
      this.migrationResults = [];
    } finally {
      this.migrationRunning = false;
    }
  }

  private getMigrationStatusText(status: OnlineArchiveMigrationStatus): string {
    switch (status) {
      case OnlineArchiveMigrationStatus.MIGRATED:
        return '已迁移';
      case OnlineArchiveMigrationStatus.SKIPPED:
        return '已跳过';
      case OnlineArchiveMigrationStatus.FAILED:
        return '失败';
      default:
        return '未知';
    }
  }

  private getMigrationStatusColor(status: OnlineArchiveMigrationStatus): ResourceColor {
    switch (status) {
      case OnlineArchiveMigrationStatus.MIGRATED:
        return ThemeAwareHelper.getTestManagementThemedColor('accent_green', this.themeState.currentTheme);
      case OnlineArchiveMigrationStatus.SKIPPED:
        return ThemeAwareHelper.getTestManagementThemedColor('text_muted', this.themeState.currentTheme);
      case OnlineArchiveMigrationStatus.FAILED:
        return ThemeAwareHelper.getTestManagementThemedColor('button_danger', this.themeState.currentTheme);
      default:
        return ThemeAwareHelper.getTestManagementThemedColor('text_secondary', this.themeState.currentTheme);
    }
  }

  /**
   * 获取过滤后的任务列表
   */
  private getFilteredTasks(): DownloadTask[] {
    if (this.filterStatus === 'all') {
      return this.downloadTasks;
    }

    return this.downloadTasks.filter((task: DownloadTask) => {
      switch (this.filterStatus) {
        case 'downloading':
          return task.status === DownloadStatus.DOWNLOADING;
        case 'paused':
          return task.status === DownloadStatus.PAUSED;
        case 'completed':
          return task.status === DownloadStatus.COMPLETED;
        case 'failed':
          return task.status === DownloadStatus.FAILED;
        default:
          return true;
      }
    });
  }

  /**
   * 暂停/继续任务
   */
  private async toggleTaskPause(taskId: string): Promise<void> {
    const taskIndex = this.downloadTasks.findIndex((t: DownloadTask) => t.id === taskId);
    if (taskIndex >= 0) {
      const task = this.downloadTasks[taskIndex];
      if (task.status === DownloadStatus.DOWNLOADING) {
        await this.downloadManager.pauseTask(taskId);
        logger.info(TAG, `暂停任务: ${task.chapterTitle}`);
      } else if (task.status === DownloadStatus.PAUSED) {
        await this.downloadManager.resumeTask(taskId);
        logger.info(TAG, `继续任务: ${task.chapterTitle}`);
      }
      // 立即刷新
      this.refreshTasks();
    }
  }

  /**
   * 删除任务
   */
  private async deleteTask(taskId: string): Promise<void> {
    const taskIndex = this.downloadTasks.findIndex((t: DownloadTask) => t.id === taskId);
    if (taskIndex >= 0) {
      const task = this.downloadTasks[taskIndex];
      await this.downloadManager.deleteTask(taskId);
      logger.info(TAG, `删除任务: ${task.chapterTitle}`);
      // 立即刷新
      this.refreshTasks();
    }
  }

  /**
   * 批量删除选中的任务
   */
  private async deleteSelectedTasks(): Promise<void> {
    const selectedIds = Array.from(this.selectedTasks);
    for (const taskId of selectedIds) {
      await this.downloadManager.deleteTask(taskId);
    }
    this.selectedTasks.clear();
    this.isSelectionMode = false;
    logger.info(TAG, `批量删除了 ${selectedIds.length} 个任务`);
    // 立即刷新
    this.refreshTasks();
  }

  /**
   * 暂停所有任务
   */
  private async pauseAllTasks(): Promise<void> {
    for (const task of this.downloadTasks) {
      if (task.status === DownloadStatus.DOWNLOADING) {
        await this.downloadManager.pauseTask(task.id);
      }
    }
    logger.info(TAG, '暂停所有下载任务');
    // 立即刷新
    this.refreshTasks();
  }

  /**
   * 继续所有任务
   */
  private async resumeAllTasks(): Promise<void> {
    for (const task of this.downloadTasks) {
      if (task.status === DownloadStatus.PAUSED) {
        await this.downloadManager.resumeTask(task.id);
      }
    }
    logger.info(TAG, '继续所有下载任务');
    // 立即刷新
    this.refreshTasks();
  }

  private goBack(): void {
    try {
      this.pathStack.pop();
    } catch (error) {
      logger.error(TAG, '返回失败', String(error));
    }
  }

  /**
   * 获取状态文本
   */
  private getStatusText(status: DownloadStatus): string {
    switch (status) {
      case DownloadStatus.DOWNLOADING:
        return '下载中';
      case DownloadStatus.PAUSED:
        return '已暂停';
      case DownloadStatus.COMPLETED:
        return '已完成';
      case DownloadStatus.FAILED:
        return '失败';
      case DownloadStatus.PENDING:
        return '等待中';
      default:
        return '未知';
    }
  }

  /**
   * 获取状态颜色
   */
  private getStatusColor(status: DownloadStatus): ResourceColor {
    switch (status) {
      case DownloadStatus.DOWNLOADING:
        return ThemeAwareHelper.getTestManagementThemedColor('accent_blue', this.themeState.currentTheme);
      case DownloadStatus.PAUSED:
        return ThemeAwareHelper.getTestManagementThemedColor('accent_orange', this.themeState.currentTheme);
      case DownloadStatus.COMPLETED:
        return ThemeAwareHelper.getTestManagementThemedColor('accent_green', this.themeState.currentTheme);
      case DownloadStatus.FAILED:
        return ThemeAwareHelper.getTestManagementThemedColor('button_danger', this.themeState.currentTheme);
      default:
        return ThemeAwareHelper.getTestManagementThemedColor('text_muted', this.themeState.currentTheme);
    }
  }

  /**
   * 构建内容类型标签栏
   */
  @Builder
  buildContentTypeTabBar() {
    Row({ space: 0 }) {
      // 下载任务标签
      Column() {
        Text('下载任务')
          .fontSize(14)
          .fontWeight(this.contentTypeTab === 'downloads' ? FontWeight.Bold : FontWeight.Normal)
          .fontFamily(this.appFontFamily)
          .fontColor(this.contentTypeTab === 'downloads'
            ? ThemeAwareHelper.getTestManagementThemedColor('accent_primary', this.themeState.currentTheme)
            : ThemeAwareHelper.getTestManagementThemedColor('text_secondary', this.themeState.currentTheme))
        
        if (this.contentTypeTab === 'downloads') {
          Divider()
            .width(40)
            .height(3)
            .color(ThemeAwareHelper.getTestManagementThemedColor('accent_primary', this.themeState.currentTheme))
            .margin({ top: 6 })
        } else {
          Blank().height(9)
        }
      }
      .layoutWeight(1)
      .alignItems(HorizontalAlign.Center)
      .onClick(() => { this.activateContentTypeTab('downloads'); })
      
      // 漫画缓存标签
      Column() {
        Row({ space: 4 }) {
          Text('漫画缓存')
            .fontSize(14)
            .fontWeight(this.contentTypeTab === 'manga_cache' ? FontWeight.Bold : FontWeight.Normal)
            .fontFamily(this.appFontFamily)
            .fontColor(this.contentTypeTab === 'manga_cache'
              ? ThemeAwareHelper.getTestManagementThemedColor('accent_primary', this.themeState.currentTheme)
              : ThemeAwareHelper.getTestManagementThemedColor('text_secondary', this.themeState.currentTheme))
          
          if (this.mangaCacheList.length > 0) {
            Text(`${this.mangaCacheList.length}`)
              .fontSize(10)
              .fontFamily(this.appFontFamily)
              .fontColor(Color.White)
              .backgroundColor(ThemeAwareHelper.getTestManagementThemedColor('accent_green', this.themeState.currentTheme))
              .borderRadius(8)
              .padding({ left: 6, right: 6, top: 2, bottom: 2 })
          }
        }
        
        if (this.contentTypeTab === 'manga_cache') {
          Divider()
            .width(40)
            .height(3)
            .color(ThemeAwareHelper.getTestManagementThemedColor('accent_primary', this.themeState.currentTheme))
            .margin({ top: 6 })
        } else {
          Blank().height(9)
        }
      }
      .layoutWeight(1)
      .alignItems(HorizontalAlign.Center)
      .onClick(() => { this.activateContentTypeTab('manga_cache'); })

      Column() {
        Text('缓存迁移')
          .fontSize(14)
          .fontWeight(this.contentTypeTab === 'migration' ? FontWeight.Bold : FontWeight.Normal)
          .fontFamily(this.appFontFamily)
          .fontColor(this.contentTypeTab === 'migration'
            ? ThemeAwareHelper.getTestManagementThemedColor('accent_primary', this.themeState.currentTheme)
            : ThemeAwareHelper.getTestManagementThemedColor('text_secondary', this.themeState.currentTheme))

        if (this.contentTypeTab === 'migration') {
          Divider()
            .width(40)
            .height(3)
            .color(ThemeAwareHelper.getTestManagementThemedColor('accent_primary', this.themeState.currentTheme))
            .margin({ top: 6 })
        } else {
          Blank().height(9)
        }
      }
      .layoutWeight(1)
      .alignItems(HorizontalAlign.Center)
      .onClick(() => { this.activateContentTypeTab('migration'); })
    }
    .width('100%')
    .padding({ left: 16, right: 16, top: 12, bottom: 4 })
    .backgroundColor(SettingsPanelSurfaceHelper.getBackground(this.themeState.currentTheme))
    .linearGradient(SettingsPanelSurfaceHelper.getSurfaceGradient(this.themeState.currentTheme))
    .backgroundBlurStyle(
      SettingsPanelSurfaceHelper.getBlurStyle(this.themeState.currentTheme),
      SettingsPanelSurfaceHelper.getBlurOptions(this.themeState.currentTheme)
    )
    .backgroundEffect(SettingsPanelSurfaceHelper.getBackgroundEffect(this.themeState.currentTheme))
    .borderRadius(18)
    .clip(true)
    .border({
      width: SettingsPanelSurfaceHelper.getBorderWidth(this.themeState.currentTheme),
      color: SettingsPanelSurfaceHelper.getBorderColor(this.themeState.currentTheme)
    })
    .shadow({
      radius: 18,
      color: SettingsPanelSurfaceHelper.getShadowColor(this.themeState.currentTheme),
      offsetX: 0,
      offsetY: 8
    })
    .margin({ left: 16, right: 16, top: 8, bottom: 4 })
  }

  private activateContentTypeTab(tab: DownloadContentTypeTab): void {
    this.contentTypeTab = tab;
    if (tab === 'manga_cache' && this.mangaCacheList.length === 0) {
      this.loadCacheLists();
    } else if (tab === 'migration' && !this.migrationHasRun && !this.migrationRunning) {
      this.startArchiveMigration();
    }
  }

  private switchToNextContentTypeTab(): void {
    const currentIndex = this.contentTypeTabOrder.indexOf(this.contentTypeTab);
    const nextIndex = (currentIndex + 1) % this.contentTypeTabOrder.length;
    this.activateContentTypeTab(this.contentTypeTabOrder[nextIndex]);
  }

  private switchToPrevContentTypeTab(): void {
    const currentIndex = this.contentTypeTabOrder.indexOf(this.contentTypeTab);
    const prevIndex = (currentIndex - 1 + this.contentTypeTabOrder.length) % this.contentTypeTabOrder.length;
    this.activateContentTypeTab(this.contentTypeTabOrder[prevIndex]);
  }

  private handleTabSwipeStart(event: GestureEvent): void {
    this.swipeStartX = event.offsetX;
    this.swipeOffsetX = 0;
  }

  private handleTabSwipeUpdate(event: GestureEvent): void {
    this.swipeOffsetX = event.offsetX - this.swipeStartX;
  }

  private handleTabSwipeEnd(): void {
    const swipeThreshold = 80;
    if (this.swipeOffsetX < -swipeThreshold) {
      this.switchToNextContentTypeTab();
    } else if (this.swipeOffsetX > swipeThreshold) {
      this.switchToPrevContentTypeTab();
    }
    this.swipeOffsetX = 0;
  }
  
  /**
   * 构建缓存列表项
   */
  @Builder
  buildImportStyleContentTypeTabBar() {
    Scroll() {
      Row({ space: 0 }) {
        Row() {
          SymbolGlyph($r('sys.symbol.arrow_down_circle'))
            .fontSize(12)
            .fontColor([this.contentTypeTab === 'downloads'
              ? ThemeAwareHelper.getTestManagementThemedColor('text_primary', this.themeState.currentTheme)
              : ThemeAwareHelper.getTestManagementThemedColor('text_secondary', this.themeState.currentTheme)])
            .margin({ right: 4 })
          Text('下载任务')
            .fontSize(12)
            .fontFamily(this.appFontFamily)
            .fontColor(this.contentTypeTab === 'downloads'
              ? ThemeAwareHelper.getTestManagementThemedColor('text_primary', this.themeState.currentTheme)
              : ThemeAwareHelper.getTestManagementThemedColor('text_secondary', this.themeState.currentTheme))
        }
        .padding({ left: 10, right: 10 })
        .height(30)
        .alignItems(VerticalAlign.Center)
        .backgroundColor(this.contentTypeTab === 'downloads'
          ? ThemeAwareHelper.getTestManagementThemedColor('background', this.themeState.currentTheme)
          : Color.Transparent)
        .border({
          width: { top: this.contentTypeTab === 'downloads' ? 2 : 0 },
          color: ThemeAwareHelper.getTestManagementThemedColor('accent_primary', this.themeState.currentTheme)
        })
        .onClick(() => {
          this.activateContentTypeTab('downloads');
        })
        .animation({ duration: 150 })

        Row() {
          SymbolGlyph($r('sys.symbol.rectangle_stack'))
            .fontSize(12)
            .fontColor([this.contentTypeTab === 'manga_cache'
              ? ThemeAwareHelper.getTestManagementThemedColor('text_primary', this.themeState.currentTheme)
              : ThemeAwareHelper.getTestManagementThemedColor('text_secondary', this.themeState.currentTheme)])
            .margin({ right: 4 })
          Text('漫画缓存')
            .fontSize(12)
            .fontFamily(this.appFontFamily)
            .fontColor(this.contentTypeTab === 'manga_cache'
              ? ThemeAwareHelper.getTestManagementThemedColor('text_primary', this.themeState.currentTheme)
              : ThemeAwareHelper.getTestManagementThemedColor('text_secondary', this.themeState.currentTheme))
        }
        .padding({ left: 10, right: 10 })
        .height(30)
        .alignItems(VerticalAlign.Center)
        .backgroundColor(this.contentTypeTab === 'manga_cache'
          ? ThemeAwareHelper.getTestManagementThemedColor('background', this.themeState.currentTheme)
          : Color.Transparent)
        .border({
          width: { top: this.contentTypeTab === 'manga_cache' ? 2 : 0 },
          color: ThemeAwareHelper.getTestManagementThemedColor('accent_primary', this.themeState.currentTheme)
        })
        .onClick(() => {
          this.activateContentTypeTab('manga_cache');
        })
        .animation({ duration: 150 })

        Row() {
          SymbolGlyph($r('sys.symbol.archivebox'))
            .fontSize(12)
            .fontColor([this.contentTypeTab === 'migration'
              ? ThemeAwareHelper.getTestManagementThemedColor('text_primary', this.themeState.currentTheme)
              : ThemeAwareHelper.getTestManagementThemedColor('text_secondary', this.themeState.currentTheme)])
            .margin({ right: 4 })
          Text('缓存迁移')
            .fontSize(12)
            .fontFamily(this.appFontFamily)
            .fontColor(this.contentTypeTab === 'migration'
              ? ThemeAwareHelper.getTestManagementThemedColor('text_primary', this.themeState.currentTheme)
              : ThemeAwareHelper.getTestManagementThemedColor('text_secondary', this.themeState.currentTheme))
        }
        .padding({ left: 10, right: 10 })
        .height(30)
        .alignItems(VerticalAlign.Center)
        .backgroundColor(this.contentTypeTab === 'migration'
          ? ThemeAwareHelper.getTestManagementThemedColor('background', this.themeState.currentTheme)
          : Color.Transparent)
        .border({
          width: { top: this.contentTypeTab === 'migration' ? 2 : 0 },
          color: ThemeAwareHelper.getTestManagementThemedColor('accent_primary', this.themeState.currentTheme)
        })
        .onClick(() => {
          this.activateContentTypeTab('migration');
        })
        .animation({ duration: 150 })
      }
    }
    .scrollable(ScrollDirection.Horizontal)
    .scrollBar(BarState.Off)
    .width('100%')
    .height(32)
    .backgroundColor(SettingsPanelSurfaceHelper.getBackground(this.themeState.currentTheme))
    .linearGradient(SettingsPanelSurfaceHelper.getSurfaceGradient(this.themeState.currentTheme))
    .backgroundBlurStyle(
      SettingsPanelSurfaceHelper.getBlurStyle(this.themeState.currentTheme),
      SettingsPanelSurfaceHelper.getBlurOptions(this.themeState.currentTheme)
    )
    .backgroundEffect(SettingsPanelSurfaceHelper.getBackgroundEffect(this.themeState.currentTheme))
    .borderRadius(18)
    .clip(true)
    .margin({ left: 16, right: 16, top: 8, bottom: 4 })
  }

  @Builder
  buildCacheItem(stats: ContentCacheStats) {
    Column({ space: 10 }) {
      // 标题和缓存大小
      Row() {
        Column({ space: 4 }) {
          Text(stats.title)
            .fontSize(15)
            .fontWeight(FontWeight.Medium)
            .fontFamily(this.appFontFamily)
            .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_primary', this.themeState.currentTheme))
            .maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
          
          Text(`${stats.cachedChapterCount}/${stats.totalChapterCount} 章节已缓存`)
            .fontSize(12)
            .fontFamily(this.appFontFamily)
            .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_secondary', this.themeState.currentTheme))
        }
        .alignItems(HorizontalAlign.Start)
        .layoutWeight(1)
        
        // 缓存大小标签
        Text(this.cacheStatusService.formatSize(stats.cacheSize))
          .fontSize(13)
          .fontWeight(FontWeight.Bold)
          .fontFamily(this.appFontFamily)
          .fontColor(ThemeAwareHelper.getTestManagementThemedColor('accent_orange', this.themeState.currentTheme))
          .padding({ left: 10, right: 10, top: 4, bottom: 4 })
          .backgroundColor(ThemeAwareHelper.getTestManagementThemedColor('accent_orange', this.themeState.currentTheme) + '20')
          .borderRadius(12)
      }
      .width('100%')
      
      // 进度条
      Row({ space: 8 }) {
        Progress({ value: this.cacheStatusService.calculateProgress(stats), total: 100, type: ProgressType.Linear })
          .layoutWeight(1)
          .height(4)
          .color(ThemeAwareHelper.getTestManagementThemedColor('accent_green', this.themeState.currentTheme))
          .backgroundColor(ThemeAwareHelper.getTestManagementThemedColor('panel_border', this.themeState.currentTheme))
        
        Text(`${this.cacheStatusService.calculateProgress(stats)}%`)
          .fontSize(12)
          .fontFamily(this.appFontFamily)
          .fontColor(ThemeAwareHelper.getTestManagementThemedColor('accent_green', this.themeState.currentTheme))
      }
      .width('100%')
      
      // 详细信息和操作按钮
      Row() {
        if (stats.contentType === CacheContentType.MANGA) {
          Text(`${stats.cachedPageCount} 页已缓存`)
            .fontSize(11)
            .fontFamily(this.appFontFamily)
            .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_muted', this.themeState.currentTheme))
        }
        
        Blank()
        
        Button({ stateEffect: true }) {
          Text('清理')
            .fontSize(12)
            .fontFamily(this.appFontFamily)
            .fontColor(Color.White)
        }
        .width(60)
        .height(28)
        .backgroundColor(ThemeAwareHelper.getTestManagementThemedColor('button_danger', this.themeState.currentTheme))
        .borderRadius(6)
        .onClick(() => { this.clearCacheItem(stats); })
      }
      .width('100%')
    }
    .width('100%')
    .padding(14)
    .backgroundColor(SettingsPanelSurfaceHelper.getBackground(this.themeState.currentTheme))
    .linearGradient(SettingsPanelSurfaceHelper.getSurfaceGradient(this.themeState.currentTheme))
    .backgroundBlurStyle(
      SettingsPanelSurfaceHelper.getBlurStyle(this.themeState.currentTheme),
      SettingsPanelSurfaceHelper.getBlurOptions(this.themeState.currentTheme)
    )
    .backgroundEffect(SettingsPanelSurfaceHelper.getBackgroundEffect(this.themeState.currentTheme))
    .borderRadius(10)
    .clip(true)
    .border({
      width: SettingsPanelSurfaceHelper.getBorderWidth(this.themeState.currentTheme),
      color: SettingsPanelSurfaceHelper.getBorderColor(this.themeState.currentTheme)
    })
    .shadow({
      radius: 14,
      color: SettingsPanelSurfaceHelper.getShadowColor(this.themeState.currentTheme),
      offsetX: 0,
      offsetY: 8
    })
    .margin({ left: 16, right: 16, bottom: 10 })
  }
  
  /**
   * 构建缓存列表
   */
  @Builder
  buildCacheList() {
    if (this.isCacheLoading) {
      Column({ space: 16 }) {
        LoadingProgress()
          .width(36)
          .height(36)
          .color(ThemeAwareHelper.getTestManagementThemedColor('accent_blue', this.themeState.currentTheme))
        Text('加载缓存信息...')
          .fontSize(14)
          .fontFamily(this.appFontFamily)
          .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_muted', this.themeState.currentTheme))
      }
      .width('100%')
      .height(200)
      .justifyContent(FlexAlign.Center)
    } else if (this.mangaCacheList.length === 0) {
      Column({ space: 16 }) {
        SymbolGlyph($r('sys.symbol.archivebox'))
          .fontSize(48)
          .fontColor([ThemeAwareHelper.getTestManagementThemedColor('text_muted', this.themeState.currentTheme)])
        Text('暂无缓存数据')
          .fontSize(14)
          .fontFamily(this.appFontFamily)
          .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_muted', this.themeState.currentTheme))
        Text('开启"边看边下载"后阅读的漫画将在此显示')
          .fontSize(12)
          .fontFamily(this.appFontFamily)
          .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_muted', this.themeState.currentTheme))
      }
      .width('100%')
      .height(200)
      .justifyContent(FlexAlign.Center)
    } else {
      // 缓存统计概览
      Row({ space: 16 }) {
        Column({ space: 4 }) {
          Text(`${this.mangaCacheList.length}`)
            .fontSize(24)
            .fontWeight(FontWeight.Bold)
            .fontFamily(this.appFontFamily)
            .fontColor(ThemeAwareHelper.getTestManagementThemedColor('accent_primary', this.themeState.currentTheme))
          Text('已缓存漫画')
            .fontSize(11)
            .fontFamily(this.appFontFamily)
            .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_muted', this.themeState.currentTheme))
        }
        .layoutWeight(1)
        .alignItems(HorizontalAlign.Center)
        
        Column({ space: 4 }) {
          Text(this.cacheStatusService.formatSize(
            this.mangaCacheList.reduce((sum, s) => sum + s.cacheSize, 0)
          ))
            .fontSize(24)
            .fontWeight(FontWeight.Bold)
            .fontFamily(this.appFontFamily)
            .fontColor(ThemeAwareHelper.getTestManagementThemedColor('accent_orange', this.themeState.currentTheme))
          Text('总缓存大小')
            .fontSize(11)
            .fontFamily(this.appFontFamily)
            .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_muted', this.themeState.currentTheme))
        }
        .layoutWeight(1)
        .alignItems(HorizontalAlign.Center)
      }
      .width('100%')
      .padding({ left: 16, right: 16, top: 12, bottom: 12 })
      .backgroundColor(SettingsPanelSurfaceHelper.getBackground(this.themeState.currentTheme))
      .linearGradient(SettingsPanelSurfaceHelper.getSurfaceGradient(this.themeState.currentTheme))
      .backgroundBlurStyle(
        SettingsPanelSurfaceHelper.getBlurStyle(this.themeState.currentTheme),
        SettingsPanelSurfaceHelper.getBlurOptions(this.themeState.currentTheme)
      )
      .backgroundEffect(SettingsPanelSurfaceHelper.getBackgroundEffect(this.themeState.currentTheme))
      .borderRadius(10)
      .clip(true)
      .border({
        width: SettingsPanelSurfaceHelper.getBorderWidth(this.themeState.currentTheme),
        color: SettingsPanelSurfaceHelper.getBorderColor(this.themeState.currentTheme)
      })
      .shadow({
        radius: 14,
        color: SettingsPanelSurfaceHelper.getShadowColor(this.themeState.currentTheme),
        offsetX: 0,
        offsetY: 8
      })
      .margin({ left: 16, right: 16, bottom: 12 })
      
      // 缓存列表
      ForEach(this.mangaCacheList, (stats: ContentCacheStats) => {
        this.buildCacheItem(stats)
      }, (stats: ContentCacheStats) => stats.contentId)
    }
  }

  @Builder
  buildMigrationItem(item: OnlineArchiveMigrationItem) {
    Column({ space: 8 }) {
      Row() {
        Column({ space: 4 }) {
          Text(item.mangaTitle.length > 0 ? item.mangaTitle : '未知漫画')
            .fontSize(15)
            .fontWeight(FontWeight.Medium)
            .fontFamily(this.appFontFamily)
            .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_primary', this.themeState.currentTheme))
            .maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis })

          Text(item.chapterTitle.length > 0 ? item.chapterTitle : item.chapterId)
            .fontSize(12)
            .fontFamily(this.appFontFamily)
            .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_secondary', this.themeState.currentTheme))
            .maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
        }
        .layoutWeight(1)
        .alignItems(HorizontalAlign.Start)

        Text(this.getMigrationStatusText(item.status))
          .fontSize(12)
          .fontWeight(FontWeight.Bold)
          .fontFamily(this.appFontFamily)
          .fontColor(this.getMigrationStatusColor(item.status))
          .padding({ left: 10, right: 10, top: 4, bottom: 4 })
          .backgroundColor(this.getMigrationStatusColor(item.status) + '20')
          .borderRadius(12)
      }
      .width('100%')

      Text(item.message)
        .fontSize(12)
        .fontFamily(this.appFontFamily)
        .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_muted', this.themeState.currentTheme))
        .maxLines(2)
        .textOverflow({ overflow: TextOverflow.Ellipsis })

      if (item.archivePath.length > 0) {
        Text(`${item.pageCount} 页 · ${this.cacheStatusService.formatSize(item.archiveSize)}`)
          .fontSize(12)
          .fontFamily(this.appFontFamily)
          .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_secondary', this.themeState.currentTheme))
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
      }
    }
    .width('100%')
    .padding({ left: 16, right: 16, top: 12, bottom: 12 })
    .backgroundColor(SettingsPanelSurfaceHelper.getBackground(this.themeState.currentTheme))
    .linearGradient(SettingsPanelSurfaceHelper.getSurfaceGradient(this.themeState.currentTheme))
    .backgroundBlurStyle(
      SettingsPanelSurfaceHelper.getBlurStyle(this.themeState.currentTheme),
      SettingsPanelSurfaceHelper.getBlurOptions(this.themeState.currentTheme)
    )
    .backgroundEffect(SettingsPanelSurfaceHelper.getBackgroundEffect(this.themeState.currentTheme))
    .borderRadius(10)
    .clip(true)
    .border({
      width: SettingsPanelSurfaceHelper.getBorderWidth(this.themeState.currentTheme),
      color: SettingsPanelSurfaceHelper.getBorderColor(this.themeState.currentTheme)
    })
    .shadow({
      radius: 14,
      color: SettingsPanelSurfaceHelper.getShadowColor(this.themeState.currentTheme),
      offsetX: 0,
      offsetY: 8
    })
    .margin({ left: 16, right: 16, bottom: 10 })
  }

  @Builder
  buildMigrationList() {
    if (this.migrationRunning) {
      Column({ space: 16 }) {
        LoadingProgress()
          .width(36)
          .height(36)
          .color(ThemeAwareHelper.getTestManagementThemedColor('accent_blue', this.themeState.currentTheme))
        Text('正在迁移旧缓存...')
          .fontSize(14)
          .fontFamily(this.appFontFamily)
          .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_muted', this.themeState.currentTheme))
      }
      .width('100%')
      .height(200)
      .justifyContent(FlexAlign.Center)
    } else {
      Row({ space: 12 }) {
        Column({ space: 4 }) {
          Text(`${this.migrationSummary?.migratedCount || 0}`)
            .fontSize(24)
            .fontWeight(FontWeight.Bold)
            .fontFamily(this.appFontFamily)
            .fontColor(ThemeAwareHelper.getTestManagementThemedColor('accent_green', this.themeState.currentTheme))
          Text('已迁移')
            .fontSize(11)
            .fontFamily(this.appFontFamily)
            .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_muted', this.themeState.currentTheme))
        }
        .layoutWeight(1)
        .alignItems(HorizontalAlign.Center)

        Column({ space: 4 }) {
          Text(`${this.migrationSummary?.skippedCount || 0}`)
            .fontSize(24)
            .fontWeight(FontWeight.Bold)
            .fontFamily(this.appFontFamily)
            .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_secondary', this.themeState.currentTheme))
          Text('已跳过')
            .fontSize(11)
            .fontFamily(this.appFontFamily)
            .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_muted', this.themeState.currentTheme))
        }
        .layoutWeight(1)
        .alignItems(HorizontalAlign.Center)

        Column({ space: 4 }) {
          Text(`${this.migrationSummary?.failedCount || 0}`)
            .fontSize(24)
            .fontWeight(FontWeight.Bold)
            .fontFamily(this.appFontFamily)
            .fontColor(ThemeAwareHelper.getTestManagementThemedColor('button_danger', this.themeState.currentTheme))
          Text('失败')
            .fontSize(11)
            .fontFamily(this.appFontFamily)
            .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_muted', this.themeState.currentTheme))
        }
        .layoutWeight(1)
        .alignItems(HorizontalAlign.Center)
      }
      .width('100%')
      .padding({ left: 16, right: 16, top: 12, bottom: 12 })
      .backgroundColor(SettingsPanelSurfaceHelper.getBackground(this.themeState.currentTheme))
      .linearGradient(SettingsPanelSurfaceHelper.getSurfaceGradient(this.themeState.currentTheme))
      .backgroundBlurStyle(
        SettingsPanelSurfaceHelper.getBlurStyle(this.themeState.currentTheme),
        SettingsPanelSurfaceHelper.getBlurOptions(this.themeState.currentTheme)
      )
      .backgroundEffect(SettingsPanelSurfaceHelper.getBackgroundEffect(this.themeState.currentTheme))
      .borderRadius(10)
      .clip(true)
      .border({
        width: SettingsPanelSurfaceHelper.getBorderWidth(this.themeState.currentTheme),
        color: SettingsPanelSurfaceHelper.getBorderColor(this.themeState.currentTheme)
      })
      .margin({ left: 16, right: 16, bottom: 12 })

      Button({ stateEffect: true }) {
        Text('重新扫描并迁移')
          .fontSize(14)
          .fontFamily(this.appFontFamily)
          .fontColor(ThemeAwareHelper.getTestManagementThemedColor('button_text_secondary', this.themeState.currentTheme))
      }
      .height(40)
      .width('90%')
      .margin({ left: 16, right: 16, bottom: 12 })
      .backgroundColor(ThemeAwareHelper.getTestManagementThemedColor('accent_blue', this.themeState.currentTheme))
      .borderRadius(8)
      .onClick(() => {
        this.startArchiveMigration();
      })

      if (this.migrationResults.length === 0) {
        Column({ space: 12 }) {
          SymbolGlyph($r('sys.symbol.archivebox'))
            .fontSize(44)
            .fontColor([ThemeAwareHelper.getTestManagementThemedColor('text_muted', this.themeState.currentTheme)])
          Text(this.migrationHasRun ? '没有需要迁移的旧缓存' : '进入后会自动迁移旧缓存')
            .fontSize(14)
            .fontFamily(this.appFontFamily)
            .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_muted', this.themeState.currentTheme))
        }
        .width('100%')
        .height(180)
        .justifyContent(FlexAlign.Center)
      } else {
        ForEach(this.migrationResults, (item: OnlineArchiveMigrationItem) => {
          this.buildMigrationItem(item)
        }, (item: OnlineArchiveMigrationItem) => `${item.chapterId}_${item.status}`)
      }
    }
  }

  /**
   * 构建过滤选项栏
   */
  @Builder
  buildFilterBar() {
    Row({ space: 8 }) {
      Button({ stateEffect: true }) {
        Text('全部')
          .fontSize(12)
          .fontFamily(this.appFontFamily)
          .fontColor(ThemeAwareHelper.getTestManagementThemedColor('button_text_secondary', this.themeState.currentTheme))
      }
      .width(60)
      .height(32)
      .backgroundColor(
        (this.filterStatus === 'all'
          ? ThemeAwareHelper.getTestManagementThemedColor('accent_blue', this.themeState.currentTheme)
          : ThemeAwareHelper.getTestManagementThemedColor('button_inactive', this.themeState.currentTheme)) as ResourceColor
      )
      .borderRadius(6)
      .onClick(() => { this.filterStatus = 'all'; })

      Button({ stateEffect: true }) {
        Text('下载中')
          .fontSize(12)
          .fontFamily(this.appFontFamily)
          .fontColor(ThemeAwareHelper.getTestManagementThemedColor('button_text_secondary', this.themeState.currentTheme))
      }
      .width(70)
      .height(32)
      .backgroundColor(
        (this.filterStatus === 'downloading'
          ? ThemeAwareHelper.getTestManagementThemedColor('accent_blue', this.themeState.currentTheme)
          : ThemeAwareHelper.getTestManagementThemedColor('button_inactive', this.themeState.currentTheme)) as ResourceColor
      )
      .borderRadius(6)
      .onClick(() => { this.filterStatus = 'downloading'; })

      Button({ stateEffect: true }) {
        Text('已完成')
          .fontSize(12)
          .fontFamily(this.appFontFamily)
          .fontColor(ThemeAwareHelper.getTestManagementThemedColor('button_text_secondary', this.themeState.currentTheme))
      }
      .width(70)
      .height(32)
      .backgroundColor(
        (this.filterStatus === 'completed'
          ? ThemeAwareHelper.getTestManagementThemedColor('accent_blue', this.themeState.currentTheme)
          : ThemeAwareHelper.getTestManagementThemedColor('button_inactive', this.themeState.currentTheme)) as ResourceColor
      )
      .borderRadius(6)
      .onClick(() => { this.filterStatus = 'completed'; })
    }
    .width('100%')
    .padding({ left: 16, right: 16, top: 12, bottom: 12 })
  }

  /**
   * 构建下载任务列表项
   */
  @Builder
  buildTaskItem(task: DownloadTask) {
    Column({ space: 12 }) {
      Row() {
        Column({ space: 4 }) {
          Text(task.mangaTitle)
            .fontSize(16)
            .fontWeight(FontWeight.Medium)
            .fontFamily(this.appFontFamily)
            .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_primary', this.themeState.currentTheme))
          
          Text(task.chapterTitle)
            .fontSize(14)
            .fontFamily(this.appFontFamily)
            .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_secondary', this.themeState.currentTheme))
        }
        .alignItems(HorizontalAlign.Start)
        .layoutWeight(1)

        // 状态标签
        Text(this.getStatusText(task.status))
          .fontSize(12)
          .fontFamily(this.appFontFamily)
          .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_white', this.themeState.currentTheme))
          .padding({ left: 8, right: 8, top: 4, bottom: 4 })
          .backgroundColor(this.getStatusColor(task.status))
          .borderRadius(4)
      }
      .width('100%')

      // 进度条
      if (task.status !== DownloadStatus.COMPLETED) {
        Column({ space: 6 }) {
          Row() {
            Text(`${task.downloadedPages}/${task.totalPages} 页`)
              .fontSize(12)
              .fontFamily(this.appFontFamily)
              .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_secondary', this.themeState.currentTheme))
            
            Blank()
            
            Text(`${task.progress}%`)
              .fontSize(12)
              .fontWeight(FontWeight.Bold)
              .fontFamily(this.appFontFamily)
              .fontColor(ThemeAwareHelper.getTestManagementThemedColor('accent_blue', this.themeState.currentTheme))
          }
          .width('100%')

          Progress({ value: task.progress, total: 100, type: ProgressType.Linear })
            .width('100%')
            .height(4)
            .color(ThemeAwareHelper.getTestManagementThemedColor('accent_blue', this.themeState.currentTheme))
            .backgroundColor(ThemeAwareHelper.getTestManagementThemedColor('panel_border', this.themeState.currentTheme))

          if (task.status === DownloadStatus.DOWNLOADING) {
            Row() {
              Text(`速度: ${task.speed}`)
                .fontSize(11)
                .fontFamily(this.appFontFamily)
                .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_muted', this.themeState.currentTheme))
              
              Blank()
              
              Text(`剩余: ${task.remainingTime}`)
                .fontSize(11)
                .fontFamily(this.appFontFamily)
                .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_muted', this.themeState.currentTheme))
            }
            .width('100%')
          }
        }
      }

      // 操作按钮
      Row({ space: 8 }) {
        if (task.status === DownloadStatus.DOWNLOADING) {
          Button({ stateEffect: true }) {
            Text('暂停')
              .fontSize(12)
              .fontFamily(this.appFontFamily)
              .fontColor(ThemeAwareHelper.getTestManagementThemedColor('button_text_secondary', this.themeState.currentTheme))
          }
          .width(60)
          .height(32)
          .backgroundColor(ThemeAwareHelper.getTestManagementThemedColor('accent_orange', this.themeState.currentTheme))
          .borderRadius(6)
          .onClick(() => { this.toggleTaskPause(task.id); })
        } else if (task.status === DownloadStatus.PAUSED || task.status === DownloadStatus.FAILED) {
          Button({ stateEffect: true }) {
            Text('继续')
              .fontSize(12)
              .fontFamily(this.appFontFamily)
              .fontColor(ThemeAwareHelper.getTestManagementThemedColor('button_text_secondary', this.themeState.currentTheme))
          }
          .width(60)
          .height(32)
          .backgroundColor(ThemeAwareHelper.getTestManagementThemedColor('accent_blue', this.themeState.currentTheme))
          .borderRadius(6)
          .onClick(() => { this.toggleTaskPause(task.id); })
        }

        Button({ stateEffect: true }) {
          Text('删除')
            .fontSize(12)
            .fontFamily(this.appFontFamily)
            .fontColor(ThemeAwareHelper.getTestManagementThemedColor('button_text_secondary', this.themeState.currentTheme))
        }
        .width(60)
        .height(32)
        .backgroundColor(ThemeAwareHelper.getTestManagementThemedColor('button_danger', this.themeState.currentTheme))
        .borderRadius(6)
        .onClick(() => { this.deleteTask(task.id); })
      }
      .justifyContent(FlexAlign.End)
    }
    .width('100%')
    .padding(16)
    .backgroundColor(SettingsPanelSurfaceHelper.getBackground(this.themeState.currentTheme))
    .linearGradient(SettingsPanelSurfaceHelper.getSurfaceGradient(this.themeState.currentTheme))
    .backgroundBlurStyle(
      SettingsPanelSurfaceHelper.getBlurStyle(this.themeState.currentTheme),
      SettingsPanelSurfaceHelper.getBlurOptions(this.themeState.currentTheme)
    )
    .backgroundEffect(SettingsPanelSurfaceHelper.getBackgroundEffect(this.themeState.currentTheme))
    .borderRadius(12)
    .clip(true)
    .border({
      width: SettingsPanelSurfaceHelper.getBorderWidth(this.themeState.currentTheme),
      color: SettingsPanelSurfaceHelper.getBorderColor(this.themeState.currentTheme)
    })
    .shadow({
      radius: 16,
      color: SettingsPanelSurfaceHelper.getShadowColor(this.themeState.currentTheme),
      offsetX: 0,
      offsetY: 8
    })
    .margin({ left: 16, right: 16, bottom: 12 })
  }

  /**
   * 构建批量操作栏
   */
  @Builder
  buildBatchActionsBar() {
    Row({ space: 12 }) {
      Button({ stateEffect: true }) {
        Text('全部暂停')
          .fontSize(14)
          .fontFamily(this.appFontFamily)
          .fontColor(ThemeAwareHelper.getTestManagementThemedColor('button_text_secondary', this.themeState.currentTheme))
      }
      .width('48%')
      .height(40)
      .backgroundColor(ThemeAwareHelper.getTestManagementThemedColor('accent_orange', this.themeState.currentTheme))
      .borderRadius(8)
      .onClick(() => { this.pauseAllTasks(); })

      Button({ stateEffect: true }) {
        Text('全部继续')
          .fontSize(14)
          .fontFamily(this.appFontFamily)
          .fontColor(ThemeAwareHelper.getTestManagementThemedColor('button_text_secondary', this.themeState.currentTheme))
      }
      .width('48%')
      .height(40)
      .backgroundColor(ThemeAwareHelper.getTestManagementThemedColor('accent_blue', this.themeState.currentTheme))
      .borderRadius(8)
      .onClick(() => { this.resumeAllTasks(); })
    }
    .width('100%')
    .padding({ left: 16, right: 16, top: 12, bottom: 12 })
    .justifyContent(FlexAlign.SpaceBetween)
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

        Column() {
          Blank().height(SettingsPageTitleBarManager.getContentTopPadding(this.statusBarHeight))

          if (this.isLoading) {
            Column({ space: 20 }) {
              LoadingProgress()
                .width(48)
                .height(48)
                .color(ThemeAwareHelper.getTestManagementThemedColor('accent_blue', this.themeState.currentTheme))
              
              Text('加载中...')
                .fontSize(16)
                .fontFamily(this.appFontFamily)
                .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_muted', this.themeState.currentTheme))
            }
            .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.TOP, SafeAreaEdge.BOTTOM])
            .width('100%')
            .layoutWeight(1)
            .justifyContent(FlexAlign.Center)
          } else {
            // 内容类型标签栏
            this.buildImportStyleContentTypeTabBar()

            Column() {
              if (this.contentTypeTab === 'downloads') {
                // 下载任务列表
                this.buildFilterBar()
                this.buildBatchActionsBar()

                if (this.getFilteredTasks().length === 0) {
                  Column({ space: 20 }) {
                    Text('暂无下载任务')
                      .fontSize(16)
                      .fontFamily(this.appFontFamily)
                      .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_muted', this.themeState.currentTheme))
                  }
                  .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.TOP, SafeAreaEdge.BOTTOM])
                  .width('100%')
                  .layoutWeight(1)
                  .justifyContent(FlexAlign.Center)
                } else {
                  Scroll(this.scroller) {
                    Column() {
                      ForEach(this.getFilteredTasks(), (task: DownloadTask) => {
                        this.buildTaskItem(task)
                      }, (task: DownloadTask) => task.id)
                      Blank().height(24 + this.navigationBarHeight)
                    }
                    .width('100%')
                  }
                  .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.TOP, SafeAreaEdge.BOTTOM])
                  .layoutWeight(1)
                  .edgeEffect(EdgeEffect.Spring)
                  .scrollBar(BarState.Auto)
                }
              } else if (this.contentTypeTab === 'manga_cache') {
                // 漫画缓存列表
                Scroll(this.scroller) {
                  Column() {
                    this.buildCacheList()
                    Blank().height(24 + this.navigationBarHeight)
                  }
                  .width('100%')
                  .padding({ top: 8 })
                }
                .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.TOP, SafeAreaEdge.BOTTOM])
                .layoutWeight(1)
                .edgeEffect(EdgeEffect.Spring)
                .scrollBar(BarState.Auto)
              } else if (this.contentTypeTab === 'migration') {
                Scroll(this.scroller) {
                  Column() {
                    this.buildMigrationList()
                    Blank().height(24 + this.navigationBarHeight)
                  }
                  .width('100%')
                  .padding({ top: 8 })
                }
                .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.TOP, SafeAreaEdge.BOTTOM])
                .layoutWeight(1)
                .edgeEffect(EdgeEffect.Spring)
                .scrollBar(BarState.Auto)
              }
            }
            .width('100%')
            .layoutWeight(1)
            .gesture(
              PanGesture({ fingers: 1, direction: PanDirection.Horizontal, distance: 5 })
                .onActionStart((event: GestureEvent) => {
                  this.handleTabSwipeStart(event);
                })
                .onActionUpdate((event: GestureEvent) => {
                  this.handleTabSwipeUpdate(event);
                })
                .onActionEnd((_event: GestureEvent) => {
                  this.handleTabSwipeEnd();
                })
            )
          }
        }
        .width('100%')
        .height('100%')
        .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.TOP, SafeAreaEdge.BOTTOM])

        SettingsImmersiveTitleBar({
          themeState: this.themeState,
          title: '下载管理',
          appFontFamily: this.appFontFamily
        })
      }
    }
    .hideTitleBar(true)
    .ignoreLayoutSafeArea([LayoutSafeAreaType.SYSTEM], [LayoutSafeAreaEdge.TOP, LayoutSafeAreaEdge.BOTTOM])
    /*
    .titleBar({
      padding: {
        start: LengthMetrics.vp(16),
        end: LengthMetrics.vp(16)
      },
      style: {
        originalStyle: {
          backgroundStyle: { backgroundColor: ThemeAwareHelper.getTestManagementThemedColor('panel_background', this.themeState.currentTheme) },
          contentStyle: {
            titleStyle: { mainTitleColor: ThemeAwareHelper.getTestManagementThemedColor('text_primary', this.themeState.currentTheme) },
            backIconStyle: { backgroundColor: ThemeAwareHelper.getTestManagementThemedColor('comp_background_tertiary', this.themeState.currentTheme), iconColor: ThemeAwareHelper.getTestManagementThemedColor('icon_primary', this.themeState.currentTheme) }
          }
        }
      },
      content: {
        title: { mainTitle: '下载管理' }
      }
    })
    */
    .onReady((context: NavDestinationContext) => {
      this.pathStack = context.pathStack;
      this.onPageShow();
      this.onReady();
    })
    .backgroundColor(Color.Transparent)
  }
}

export { DownloadManagerPage }
