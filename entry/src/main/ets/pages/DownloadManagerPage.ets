import { SafeFileUtils } from '../Utils/SafeFileUtils';
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
import { DownloadDirManager } from '../Framework/Storage/DownloadDirManager';
import { ManagedContentCacheClearRequest, UnifiedStorageCoordinator } from '../Framework/Storage/UnifiedStorageCoordinator';
import fs from '@ohos.file.fs';

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
  failedPages: number; // 失败页数 (非失败任务为 0)
  speed: string; // 下载速度，如 "2.5 MB/s"
  remainingTime: string; // 剩余时间，如 "3分钟"
}

type DownloadContentTypeTab = 'downloads' | 'manga_cache' | 'migration' | 'file_structure';

interface FileStructureNode {
  name: string;
  relativePath: string;
  isDirectory: boolean;
  size: number;
  fileCount: number;
  children: FileStructureNode[];
  expanded: boolean;
  depth: number;
}

interface FileStructureSection {
  title: string;
  symbolName: Resource;
  basePath: string;
  nodes: FileStructureNode[];
  totalSize: number;
  totalFiles: number;
}

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
  
  // 文件结构状态
  @State fileSections: FileStructureSection[] = [];
  @State isFileTreeLoading: boolean = false;
  @State fileTreeTotalSize: number = 0;
  @State downloadDirAvailable: boolean = false;
  
  // 下载管理器
  private downloadManager: MangaDownloadManager = MangaDownloadManager.getInstance();
  private unifiedDownloadManager: UnifiedDownloadManager = getUnifiedDownloadManager();
  private cacheStatusService: CacheStatusService = getCacheStatusService();
  private permanentCacheManager: PermanentImageCacheManager = PermanentImageCacheManager.getInstance();
  private onlineArchiveService: OnlineMangaArchiveService = OnlineMangaArchiveService.getInstance();
  private storageCoordinator: UnifiedStorageCoordinator = UnifiedStorageCoordinator.getInstance();
  private dataManager: DataManager = DataManager.getInstance();
  private hostContext: common.UIAbilityContext | null = null;
  private updateTimer: number = -1;
  private lastDownloadTaskSignature: string = '';
  private lastCacheListSignature: string = '';
  private isCacheListLoadPending: boolean = false;
  private readonly contentTypeTabOrder: DownloadContentTypeTab[] = ['downloads', 'manga_cache', 'migration', 'file_structure'];

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
    const hostContext = (this.getUIContext().getHostContext() as common.UIAbilityContext);
    if (hostContext) {
      this.hostContext = hostContext as common.UIAbilityContext;
      this.onlineArchiveService.setContext(this.hostContext);
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
      
      this.applyDownloadTasks(tasks);
      
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
    this.applyDownloadTasks(tasks);
  }

  private applyDownloadTasks(tasks: DownloadTaskInfo[]): void {
    const mappedTasks: DownloadTask[] = tasks.map((task: DownloadTaskInfo) => {
      return this.toDownloadTask(task);
    });
    const signature: string = this.buildDownloadTaskSignature(mappedTasks);
    if (signature === this.lastDownloadTaskSignature) {
      return;
    }
    this.lastDownloadTaskSignature = signature;
    this.downloadTasks = mappedTasks;
  }

  private toDownloadTask(task: DownloadTaskInfo): DownloadTask {
    return {
      id: task.id,
      mangaTitle: task.mangaTitle,
      chapterTitle: task.chapterTitle,
      progress: task.progress,
      status: this.convertTaskStatus(task.status),
      totalPages: task.totalCount,
      downloadedPages: task.downloadedCount,
      failedPages: task.failedPageIndexes?.length || 0,
      speed: this.calculateSpeed(task),
      remainingTime: this.calculateRemainingTime(task)
    } as DownloadTask;
  }

  private buildDownloadTaskSignature(tasks: DownloadTask[]): string {
    const parts: string[] = new Array<string>();
    for (let i = 0; i < tasks.length; i++) {
      const task = tasks[i];
      parts.push(`${task.id}:${task.status}:${task.progress}:${task.downloadedPages}:${task.failedPages}:${task.totalPages}`);
    }
    return parts.join('|');
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
    if (this.isCacheListLoadPending) {
      logger.debug(TAG, '缓存列表加载已在进行，跳过重复请求');
      return;
    }
    this.isCacheListLoadPending = true;
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
      const cacheListSignature: string = this.buildCacheListSignature(mangaCacheList);
      if (cacheListSignature !== this.lastCacheListSignature) {
        this.lastCacheListSignature = cacheListSignature;
        this.mangaCacheList = mangaCacheList;
      }
      
      logger.info(TAG, `加载了 ${this.mangaCacheList.length} 个漫画缓存`);
    } catch (error) {
      logger.error(TAG, `加载缓存列表失败: ${String(error)}`);
    } finally {
      this.isCacheListLoadPending = false;
      this.isCacheLoading = false;
    }
  }

  private buildCacheListSignature(items: ContentCacheStats[]): string {
    const parts: string[] = new Array<string>();
    for (let i = 0; i < items.length; i++) {
      const item = items[i];
      parts.push(
        `${item.contentType}:${item.sourceId}:${item.contentId}:${item.cachedChapterCount}:${item.totalChapterCount}:${item.cachedPageCount}:${item.totalPageCount}:${item.cacheSize}`
      );
    }
    return parts.join('|');
  }
  
  /**
   * 清理指定缓存
   */
  private async clearCacheItem(stats: ContentCacheStats): Promise<void> {
    try {
      if (!this.hostContext) {
        logger.error(TAG, '清理缓存失败: 缺少 Ability 上下文');
        return;
      }
      const request = new ManagedContentCacheClearRequest();
      request.contentType = stats.contentType;
      request.contentId = stats.contentId;
      request.sourceId = stats.sourceId;
      request.title = stats.title;
      request.estimatedSizeBytes = stats.cacheSize;
      const result = await this.storageCoordinator.clearContentCache(this.hostContext, request);
      if (!result.success) {
        const message = result.errors.length > 0 ? result.errors.join('; ') : '统一缓存清理失败';
        throw new Error(message);
      }
      // 重新加载缓存列表
      await this.loadCacheLists();
      logger.info(TAG, `已通过统一协调器清理缓存: ${stats.title}`);
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
      } else if (task.status === DownloadStatus.FAILED && task.failedPages > 0) {
        // 部分失败：选择性重试失败页面
        await this.downloadManager.retryFailedPages(taskId);
        logger.info(TAG, `重试失败页面: ${task.chapterTitle}, ${task.failedPages}页`);
      } else if (task.status === DownloadStatus.PAUSED || task.status === DownloadStatus.FAILED) {
        await this.downloadManager.resumeTask(taskId);
        logger.info(TAG, `继续任务: ${task.chapterTitle}`);
      }
      // 立即刷新
      this.refreshTasks();
    }
  }

  /**
   * 保存部分下载为归档
   */
  private async savePartialDownload(taskId: string): Promise<void> {
    const taskIndex = this.downloadTasks.findIndex((t: DownloadTask) => t.id === taskId);
    if (taskIndex >= 0) {
      const task = this.downloadTasks[taskIndex];
      const success = await this.downloadManager.savePartialDownload(taskId);
      if (success) {
        logger.info(TAG, `部分下载已保存: ${task.chapterTitle}`);
      } else {
        logger.warn(TAG, `部分下载保存失败: ${task.chapterTitle}`);
      }
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
      } else if (task.status === DownloadStatus.FAILED) {
        if (task.failedPages > 0 && task.failedPages < task.totalPages) {
          await this.downloadManager.retryFailedPages(task.id);
        } else {
          await this.downloadManager.resumeTask(task.id);
        }
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

  // ==================== 文件结构扫描方法 ====================

  private async loadFileStructure(): Promise<void> {
    this.isFileTreeLoading = true;
    try {
      const sections: FileStructureSection[] = [];
      let grandTotalSize = 0;

      const downloadDirMgr = DownloadDirManager.getInstance();
      this.downloadDirAvailable = downloadDirMgr.isReady();
      if (this.downloadDirAvailable) {
        const downloadPath = downloadDirMgr.getPath();
        const downloadNodes = this.scanDirectoryTree(downloadPath, '', 0);
        const downloadSize = this.sumTreeSize(downloadNodes);
        const downloadFiles = this.sumTreeFileCount(downloadNodes);
        sections.push({
          title: '公共 Download 目录',
          symbolName: $r('sys.symbol.arrow_down_circle'),
          basePath: downloadPath,
          nodes: downloadNodes,
          totalSize: downloadSize,
          totalFiles: downloadFiles
        });
        grandTotalSize += downloadSize;
      }

      if (this.hostContext) {
        const privatePath = `${this.hostContext.filesDir}/downloads`;
        try {
          SafeFileUtils.accessSync(privatePath);
          const privateNodes = this.scanDirectoryTree(privatePath, '', 0);
          const privateSize = this.sumTreeSize(privateNodes);
          const privateFiles = this.sumTreeFileCount(privateNodes);
          sections.push({
            title: '应用私有缓存',
            symbolName: $r('sys.symbol.lock_shield'),
            basePath: privatePath,
            nodes: privateNodes,
            totalSize: privateSize,
            totalFiles: privateFiles
          });
          grandTotalSize += privateSize;
        } catch (_err) {
          logger.debug(TAG, `私有downloads目录不存在: ${privatePath}`);
        }
      }

      this.fileSections = sections;
      this.fileTreeTotalSize = grandTotalSize;
      logger.info(TAG, `文件结构扫描完成: ${sections.length} 个区域, 总大小: ${this.formatTreeSize(grandTotalSize)}`);
    } catch (error) {
      logger.error(TAG, `加载文件结构失败: ${String(error)}`);
    } finally {
      this.isFileTreeLoading = false;
    }
  }

  private scanDirectoryTree(fullPath: string, relativePath: string, depth: number): FileStructureNode[] {
    const result: FileStructureNode[] = [];
    try {
      const entries: string[] = SafeFileUtils.listFileSync(fullPath);
      for (const entry of entries) {
        if (entry.startsWith('.')) {
          continue;
        }
        const entryRelative = relativePath !== '' ? `${relativePath}/${entry}` : entry;
        const entryFull = `${fullPath}/${entry}`;
        try {
          const stat = SafeFileUtils.statSync(entryFull);
          if (stat.isDirectory()) {
            const children = this.scanDirectoryTree(entryFull, entryRelative, depth + 1);
            const dirSize = this.sumTreeSize(children);
            const dirFileCount = this.sumTreeFileCount(children);
            result.push({
              name: entry,
              relativePath: entryRelative,
              isDirectory: true,
              size: dirSize,
              fileCount: dirFileCount,
              children: children,
              expanded: depth < 1,
              depth: depth
            });
          } else {
            result.push({
              name: entry,
              relativePath: entryRelative,
              isDirectory: false,
              size: stat.size,
              fileCount: 0,
              children: [],
              expanded: false,
              depth: depth
            });
          }
        } catch (_statErr) {
          logger.debug(TAG, `无法获取文件状态: ${entryFull}`);
        }
      }
    } catch (_listErr) {
      logger.warn(TAG, `扫描目录失败: ${fullPath}`);
    }
    result.sort((a: FileStructureNode, b: FileStructureNode) => {
      if (a.isDirectory && !b.isDirectory) {
        return -1;
      }
      if (!a.isDirectory && b.isDirectory) {
        return 1;
      }
      return a.name.localeCompare(b.name);
    });
    return result;
  }

  private sumTreeSize(nodes: FileStructureNode[]): number {
    let total = 0;
    for (const node of nodes) {
      total += node.size;
    }
    return total;
  }

  private sumTreeFileCount(nodes: FileStructureNode[]): number {
    let total = 0;
    for (const node of nodes) {
      if (node.isDirectory) {
        total += node.fileCount;
      } else {
        total++;
      }
    }
    return total;
  }

  private formatTreeSize(bytes: number): string {
    if (bytes === 0) {
      return '0 B';
    }
    const k = 1024;
    const sizes: string[] = ['B', 'KB', 'MB', 'GB', 'TB'];
    const i = Math.floor(Math.log(bytes) / Math.log(k));
    const clampedIndex = Math.min(i, sizes.length - 1);
    return `${(bytes / Math.pow(k, clampedIndex)).toFixed(2)} ${sizes[clampedIndex]}`;
  }

  private calcTreePercent(part: number, total: number): number {
    if (total <= 0) {
      return 0;
    }
    return Math.round((part / total) * 100);
  }

  private getFileTypeSymbolName(name: string): Resource {
    const dotIndex = name.lastIndexOf('.');
    const ext = dotIndex >= 0 ? name.substring(dotIndex + 1).toLowerCase() : '';
    if (['cbz', 'zip', 'rar', '7z', 'tar', 'gz'].includes(ext)) {
      return $r('sys.symbol.archivebox');
    }
    if (['jpg', 'jpeg', 'png', 'webp', 'gif', 'avif'].includes(ext)) {
      return $r('sys.symbol.picture');
    }
    if (['epub', 'mobi', 'pdf'].includes(ext)) {
      return $r('sys.symbol.book');
    }
    if (['txt', 'json', 'xml', 'html', 'css', 'js'].includes(ext)) {
      return $r('sys.symbol.doc_text');
    }
    return $r('sys.symbol.doc');
  }

  private getFolderSymbolName(node: FileStructureNode): Resource {
    if (node.expanded) {
      return $r('sys.symbol.folder_fill');
    }
    return $r('sys.symbol.folder_fill');
  }

  private toggleFileNode(sectionIndex: number, nodePath: string): void {
    const newSections: FileStructureSection[] = [];
    for (let si = 0; si < this.fileSections.length; si++) {
      const section = this.fileSections[si];
      if (si === sectionIndex) {
        const newNodes = this.toggleNodeInTree(section.nodes, nodePath);
        newSections.push({
          title: section.title,
          symbolName: section.symbolName,
          basePath: section.basePath,
          nodes: newNodes,
          totalSize: section.totalSize,
          totalFiles: section.totalFiles
        });
      } else {
        newSections.push(section);
      }
    }
    this.fileSections = newSections;
  }

  private toggleNodeInTree(nodes: FileStructureNode[], targetPath: string): FileStructureNode[] {
    const result: FileStructureNode[] = [];
    for (const node of nodes) {
      if (node.relativePath === targetPath && node.isDirectory) {
        result.push({
          name: node.name,
          relativePath: node.relativePath,
          isDirectory: node.isDirectory,
          size: node.size,
          fileCount: node.fileCount,
          children: node.children,
          expanded: !node.expanded,
          depth: node.depth
        });
      } else if (node.isDirectory && node.children.length > 0) {
        result.push({
          name: node.name,
          relativePath: node.relativePath,
          isDirectory: node.isDirectory,
          size: node.size,
          fileCount: node.fileCount,
          children: this.toggleNodeInTree(node.children, targetPath),
          expanded: node.expanded,
          depth: node.depth
        });
      } else {
        result.push(node);
      }
    }
    return result;
  }

  /**
   * 获取状态文本
   */
  private getStatusText(status: DownloadStatus, failedPages?: number, totalPages?: number): string {
    switch (status) {
      case DownloadStatus.DOWNLOADING:
        return '下载中';
      case DownloadStatus.PAUSED:
        return '已暂停';
      case DownloadStatus.COMPLETED:
        return '已完成';
      case DownloadStatus.FAILED:
        if (failedPages !== undefined && totalPages !== undefined && failedPages > 0 && failedPages < totalPages) {
          return '部分完成';
        }
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
  private getStatusColor(status: DownloadStatus, failedPages?: number, totalPages?: number): ResourceColor {
    switch (status) {
      case DownloadStatus.DOWNLOADING:
        return ThemeAwareHelper.getTestManagementThemedColor('accent_blue', this.themeState.currentTheme);
      case DownloadStatus.PAUSED:
        return ThemeAwareHelper.getTestManagementThemedColor('accent_orange', this.themeState.currentTheme);
      case DownloadStatus.COMPLETED:
        return ThemeAwareHelper.getTestManagementThemedColor('accent_green', this.themeState.currentTheme);
      case DownloadStatus.FAILED:
        if (failedPages !== undefined && totalPages !== undefined && failedPages > 0 && failedPages < totalPages) {
          return ThemeAwareHelper.getTestManagementThemedColor('accent_orange', this.themeState.currentTheme);
        }
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

      Column() {
        Text('文件结构')
          .fontSize(14)
          .fontWeight(this.contentTypeTab === 'file_structure' ? FontWeight.Bold : FontWeight.Normal)
          .fontFamily(this.appFontFamily)
          .fontColor(this.contentTypeTab === 'file_structure'
            ? ThemeAwareHelper.getTestManagementThemedColor('accent_primary', this.themeState.currentTheme)
            : ThemeAwareHelper.getTestManagementThemedColor('text_secondary', this.themeState.currentTheme))

        if (this.contentTypeTab === 'file_structure') {
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
      .onClick(() => { this.activateContentTypeTab('file_structure'); })
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
    } else if (tab === 'file_structure' && this.fileSections.length === 0 && !this.isFileTreeLoading) {
      this.loadFileStructure();
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
          SymbolGlyph($r('sys.symbol.picture'))
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

        Row() {
          SymbolGlyph($r('sys.symbol.folder'))
            .fontSize(12)
            .fontColor([this.contentTypeTab === 'file_structure'
              ? ThemeAwareHelper.getTestManagementThemedColor('text_primary', this.themeState.currentTheme)
              : ThemeAwareHelper.getTestManagementThemedColor('text_secondary', this.themeState.currentTheme)])
            .margin({ right: 4 })
          Text('文件结构')
            .fontSize(12)
            .fontFamily(this.appFontFamily)
            .fontColor(this.contentTypeTab === 'file_structure'
              ? ThemeAwareHelper.getTestManagementThemedColor('text_primary', this.themeState.currentTheme)
              : ThemeAwareHelper.getTestManagementThemedColor('text_secondary', this.themeState.currentTheme))
        }
        .padding({ left: 10, right: 10 })
        .height(30)
        .alignItems(VerticalAlign.Center)
        .backgroundColor(this.contentTypeTab === 'file_structure'
          ? ThemeAwareHelper.getTestManagementThemedColor('background', this.themeState.currentTheme)
          : Color.Transparent)
        .border({
          width: { top: this.contentTypeTab === 'file_structure' ? 2 : 0 },
          color: ThemeAwareHelper.getTestManagementThemedColor('accent_primary', this.themeState.currentTheme)
        })
        .onClick(() => {
          this.activateContentTypeTab('file_structure');
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

  // ==================== 文件结构 Builder 方法 ====================

  @Builder
  buildFileStructureLoading() {
    Column({ space: 20 }) {
      LoadingProgress()
        .width(48)
        .height(48)
        .color(ThemeAwareHelper.getTestManagementThemedColor('accent_blue', this.themeState.currentTheme))

      Text('正在扫描文件结构...')
        .fontSize(16)
        .fontFamily(this.appFontFamily)
        .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_muted', this.themeState.currentTheme))
    }
    .width('100%')
    .height(300)
    .justifyContent(FlexAlign.Center)
  }

  @Builder
  buildFileStructureEmpty() {
    Column({ space: 16 }) {
      SymbolGlyph($r('sys.symbol.questionmark_circle'))
        .fontSize(48)
        .fontColor([ThemeAwareHelper.getTestManagementThemedColor('text_muted', this.themeState.currentTheme)])

      Text(this.downloadDirAvailable
        ? '暂无缓存文件'
        : '公共 Download 目录未授权，请先在数据管理页面授权访问')
        .fontSize(14)
        .fontFamily(this.appFontFamily)
        .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_muted', this.themeState.currentTheme))
        .textAlign(TextAlign.Center)
        .padding({ left: 32, right: 32 })
    }
    .width('100%')
    .height(250)
    .justifyContent(FlexAlign.Center)
  }

  @Builder
  buildFileStructureView() {
    if (this.fileSections.length === 0) {
      this.buildFileStructureEmpty()
    } else {
      Column({ space: 12 }) {
        this.buildFileTreeOverview()

        ForEach(this.fileSections, (section: FileStructureSection, sectionIndex: number) => {
          this.buildFileTreeSection(section, sectionIndex)
        }, (section: FileStructureSection, sectionIndex: number) => `section_${sectionIndex}_${section.title}`)
      }
      .width('100%')
    }
  }

  @Builder
  buildFileTreeOverview() {
    Column({ space: 8 }) {
      Row() {
        SymbolGlyph($r('sys.symbol.externaldrive'))
          .fontSize(16)
          .fontColor([ThemeAwareHelper.getTestManagementThemedColor('accent_blue', this.themeState.currentTheme)])
          .margin({ right: 6 })

        Text('缓存文件总览')
          .fontSize(14)
          .fontWeight(FontWeight.Medium)
          .fontFamily(this.appFontFamily)
          .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_primary', this.themeState.currentTheme))

        Blank()

        Text(this.formatTreeSize(this.fileTreeTotalSize))
          .fontSize(14)
          .fontWeight(FontWeight.Medium)
          .fontFamily(this.appFontFamily)
          .fontColor(ThemeAwareHelper.getTestManagementThemedColor('accent_blue', this.themeState.currentTheme))
      }
      .width('100%')

      if (this.fileSections.length > 1) {
        Flex({ wrap: FlexWrap.Wrap }) {
          ForEach(this.fileSections, (section: FileStructureSection, sectionIndex: number) => {
            Row({ space: 4 }) {
              SymbolGlyph(section.symbolName)
                .fontSize(10)
                .fontColor([ThemeAwareHelper.getTestManagementThemedColor('text_secondary', this.themeState.currentTheme)])
              Text(`${section.title}: ${this.formatTreeSize(section.totalSize)}`)
                .fontSize(11)
                .fontFamily(this.appFontFamily)
                .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_secondary', this.themeState.currentTheme))
            }
            .padding({ left: 8, right: 8, top: 4, bottom: 4 })
            .margin({ right: 8, bottom: 8 })
            .backgroundColor(ThemeAwareHelper.getTestManagementThemedColor('panel_background', this.themeState.currentTheme))
            .borderRadius(6)
          }, (section: FileStructureSection, sectionIndex: number) => `overview_${sectionIndex}_${section.title}`)
        }
        .width('100%')
      }
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
      offsetY: 6
    })
    .margin({ left: 16, right: 16, bottom: 4 })
  }

  @Builder
  buildFileTreeSection(section: FileStructureSection, sectionIndex: number) {
    Column({ space: 0 }) {
      Row() {
        SymbolGlyph(section.symbolName)
          .fontSize(14)
          .fontColor([ThemeAwareHelper.getTestManagementThemedColor('accent_blue', this.themeState.currentTheme)])
          .margin({ right: 6 })

        Text(section.title)
          .fontSize(13)
          .fontWeight(FontWeight.Medium)
          .fontFamily(this.appFontFamily)
          .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_primary', this.themeState.currentTheme))

        Blank()

        Text(`${this.formatTreeSize(section.totalSize)} · ${section.totalFiles} 文件`)
          .fontSize(11)
          .fontFamily(this.appFontFamily)
          .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_muted', this.themeState.currentTheme))
      }
      .width('100%')
      .padding({ left: 16, right: 16, top: 12, bottom: 10 })

      Divider()
        .width('100%')
        .height(0.5)
        .color(ThemeAwareHelper.getTestManagementThemedColor('panel_border', this.themeState.currentTheme))

      if (section.nodes.length === 0) {
        Column({ space: 8 }) {
          Text('空目录')
            .fontSize(12)
            .fontFamily(this.appFontFamily)
            .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_muted', this.themeState.currentTheme))
        }
        .width('100%')
        .height(60)
        .justifyContent(FlexAlign.Center)
      } else {
        ForEach(section.nodes, (node: FileStructureNode, nodeIndex: number) => {
          this.buildFileNodeRow(sectionIndex, node, section.totalSize)
        }, (node: FileStructureNode, _nodeIndex: number) => `node_${sectionIndex}_${node.relativePath}_${node.expanded}`)
      }
    }
    .width('100%')
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
      offsetY: 6
    })
    .margin({ left: 16, right: 16, bottom: 4 })
  }

  @Builder
  buildFileNodeRow(sectionIndex: number, node: FileStructureNode, sectionTotalSize: number) {
    Column() {
      Row() {
        if (node.isDirectory) {
          SymbolGlyph(node.expanded ? $r('sys.symbol.chevron_down') : $r('sys.symbol.chevron_right'))
            .fontSize(10)
            .fontColor([ThemeAwareHelper.getTestManagementThemedColor('text_muted', this.themeState.currentTheme)])
            .margin({ right: 4 })
        } else {
          Blank().width(14).height(1)
        }

        SymbolGlyph(node.isDirectory ? this.getFolderSymbolName(node) : this.getFileTypeSymbolName(node.name))
          .fontSize(14)
          .fontColor([node.isDirectory
            ? ThemeAwareHelper.getTestManagementThemedColor('accent_orange', this.themeState.currentTheme)
            : ThemeAwareHelper.getTestManagementThemedColor('text_secondary', this.themeState.currentTheme)])
          .margin({ right: 6 })

        Text(node.name)
          .fontSize(12)
          .fontFamily(this.appFontFamily)
          .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_primary', this.themeState.currentTheme))
          .layoutWeight(1)
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })

        Text(this.formatTreeSize(node.size))
          .fontSize(11)
          .fontFamily(this.appFontFamily)
          .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_secondary', this.themeState.currentTheme))
          .margin({ left: 8 })

        Text(`${this.calcTreePercent(node.size, sectionTotalSize)}%`)
          .fontSize(10)
          .fontFamily(this.appFontFamily)
          .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_muted', this.themeState.currentTheme))
          .margin({ left: 6 })
          .width(40)
          .textAlign(TextAlign.End)
      }
      .width('100%')
      .padding({ left: 16 + node.depth * 16, right: 16, top: 10, bottom: 4 })
      .onClick(() => {
        if (node.isDirectory) {
          this.toggleFileNode(sectionIndex, node.relativePath);
        }
      })

      this.buildSizeRatioBar(
        this.calcTreePercent(node.size, sectionTotalSize),
        node.isDirectory
          ? ThemeAwareHelper.getTestManagementThemedColor('accent_orange', this.themeState.currentTheme)
          : ThemeAwareHelper.getTestManagementThemedColor('accent_blue', this.themeState.currentTheme)
      )

      if (node.isDirectory && node.expanded) {
        ForEach(node.children, (child: FileStructureNode, _childIndex: number) => {
          this.buildFileNodeRow(sectionIndex, child, sectionTotalSize)
        }, (child: FileStructureNode, _childIndex: number) => `child_${sectionIndex}_${child.relativePath}_${child.expanded}`)
      }
    }
    .width('100%')
  }

  @Builder
  buildSizeRatioBar(ratio: number, barColor: ResourceColor) {
    Stack({ alignContent: Alignment.Start }) {
      Row()
        .width('100%')
        .height(3)
        .backgroundColor(ThemeAwareHelper.getTestManagementThemedColor('panel_background', this.themeState.currentTheme))
        .borderRadius(1.5)

      Row()
        .width(`${Math.max(ratio, 1)}%`)
        .height(3)
        .backgroundColor(barColor)
        .opacity(0.6)
        .borderRadius(1.5)
    }
    .width('100%')
    .height(3)
    .margin({ left: 16, right: 16, bottom: 8 })
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
        Text(this.getStatusText(task.status, task.failedPages, task.totalPages))
          .fontSize(12)
          .fontFamily(this.appFontFamily)
          .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_white', this.themeState.currentTheme))
          .padding({ left: 8, right: 8, top: 4, bottom: 4 })
          .backgroundColor(this.getStatusColor(task.status, task.failedPages, task.totalPages))
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
        } else if (task.status === DownloadStatus.FAILED && task.failedPages > 0 && task.failedPages < task.totalPages) {
          // 部分失败：显示重试失败页和保存按钮
          Button({ stateEffect: true }) {
            Text('重试失败页')
              .fontSize(12)
              .fontFamily(this.appFontFamily)
              .fontColor(ThemeAwareHelper.getTestManagementThemedColor('button_text_secondary', this.themeState.currentTheme))
          }
          .width(80)
          .height(32)
          .backgroundColor(ThemeAwareHelper.getTestManagementThemedColor('accent_orange', this.themeState.currentTheme))
          .borderRadius(6)
          .onClick(() => { this.toggleTaskPause(task.id); })

          Button({ stateEffect: true }) {
            Text('保存')
              .fontSize(12)
              .fontFamily(this.appFontFamily)
              .fontColor(ThemeAwareHelper.getTestManagementThemedColor('button_text_secondary', this.themeState.currentTheme))
          }
          .width(60)
          .height(32)
          .backgroundColor(ThemeAwareHelper.getTestManagementThemedColor('accent_green', this.themeState.currentTheme))
          .borderRadius(6)
          .onClick(() => { this.savePartialDownload(task.id); })
        } else if (task.status === DownloadStatus.FAILED && task.downloadedPages > 0) {
          // 全部失败但有已下载页面：显示保存和重试按钮
          Button({ stateEffect: true }) {
            Text('保存')
              .fontSize(12)
              .fontFamily(this.appFontFamily)
              .fontColor(ThemeAwareHelper.getTestManagementThemedColor('button_text_secondary', this.themeState.currentTheme))
          }
          .width(60)
          .height(32)
          .backgroundColor(ThemeAwareHelper.getTestManagementThemedColor('accent_green', this.themeState.currentTheme))
          .borderRadius(6)
          .onClick(() => { this.savePartialDownload(task.id); })

          Button({ stateEffect: true }) {
            Text('重试')
              .fontSize(12)
              .fontFamily(this.appFontFamily)
              .fontColor(ThemeAwareHelper.getTestManagementThemedColor('button_text_secondary', this.themeState.currentTheme))
          }
          .width(60)
          .height(32)
          .backgroundColor(ThemeAwareHelper.getTestManagementThemedColor('accent_blue', this.themeState.currentTheme))
          .borderRadius(6)
          .onClick(() => { this.toggleTaskPause(task.id); })
        } else if (task.status === DownloadStatus.PAUSED || task.status === DownloadStatus.FAILED) {
          Button({ stateEffect: true }) {
            Text(task.status === DownloadStatus.FAILED ? '重试' : '继续')
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
              } else if (this.contentTypeTab === 'file_structure') {
                if (this.isFileTreeLoading) {
                  this.buildFileStructureLoading()
                } else {
                  Scroll(this.scroller) {
                    Column() {
                      this.buildFileStructureView()
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
