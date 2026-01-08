// 文件路径: entry/src/main/ets/pages/DownloadManagerPage.ets
/**
 * 下载管理页面
 * 管理漫画章节的下载任务，显示下载进度和状态
 */

import { HdsNavDestination, HdsNavDestinationAttribute, ScrollEffectType } from '@kit.UIDesignKit';
import { LengthMetrics } from '@kit.ArkUI';
import { ThemeAwareState, ThemeAwareHelper } from '../Framework/Components/ThemeAware';
import { ThemeManager, ThemeType } from '../Framework/Managers/ThemeManager';
import { FontAwareHelper, FontAwareState } from '../Framework/Components/FontAware';
import { logger } from '../Utils/Logger';
import { PageLifecycleManager } from '../Framework/Lifecycle';
import { DownloadStatus } from '../Framework/Types/StatusEnums';
import { MangaDownloadManager, DownloadTaskInfo, TaskStatus } from '../Framework/Download/DownloadManager';

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
  private themeManager: ThemeManager = ThemeManager.getInstance();
  private componentId: string = 'DownloadManagerPage';

  // 下载任务列表
  @State downloadTasks: DownloadTask[] = [];
  @State isLoading: boolean = true;
  @State selectedTasks: Set<string> = new Set();
  @State isSelectionMode: boolean = false;

  // 过滤选项
  @State filterStatus: string = 'all'; // 'all' | 'downloading' | 'paused' | 'completed' | 'failed'
  
  // 下载管理器
  private downloadManager: MangaDownloadManager = MangaDownloadManager.getInstance();
  private updateTimer: number = -1;

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

    // 加载下载任务
    this.loadDownloadTasks();
  }

  private lifecycle = new PageLifecycleManager('DownloadManagerPage', { enableDebug: true });

  aboutToDisappear(): void {
    this.lifecycle.destroy();
    ThemeAwareHelper.cleanupThemeAware(this.componentId);
    FontAwareHelper.cleanupFontAware(this.componentId);
    
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
    .backgroundColor(ThemeAwareHelper.getTestManagementThemedColor('panel_background', this.themeState.currentTheme))
    .borderRadius(12)
    .border({ width: 1, color: ThemeAwareHelper.getTestManagementThemedColor('panel_border', this.themeState.currentTheme) })
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
        Column()
          .width('100%')
          .height('100%')
          .backgroundColor(ThemeAwareHelper.getTestManagementThemedColor('background_dark', this.themeState.currentTheme))
          .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.TOP, SafeAreaEdge.BOTTOM])

        Column() {
          Blank().height(TITLE_BAR_HEIGHT_MINI)

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
            .width('100%')
            .layoutWeight(1)
            .justifyContent(FlexAlign.Center)
          } else {
            this.buildFilterBar()
            this.buildBatchActionsBar()

            if (this.getFilteredTasks().length === 0) {
              Column({ space: 20 }) {
                Text('暂无下载任务')
                  .fontSize(16)
                  .fontFamily(this.appFontFamily)
                  .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_muted', this.themeState.currentTheme))
              }
              .width('100%')
              .layoutWeight(1)
              .justifyContent(FlexAlign.Center)
            } else {
              Scroll(this.scroller) {
                Column() {
                  ForEach(this.getFilteredTasks(), (task: DownloadTask) => {
                    this.buildTaskItem(task)
                  }, (task: DownloadTask) => task.id)
                }
                .width('100%')
              }
              .layoutWeight(1)
              .edgeEffect(EdgeEffect.Spring)
              .scrollBar(BarState.Auto)
            }
          }
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
            backIconStyle: { backgroundColor: ThemeAwareHelper.getTestManagementThemedColor('comp_background_tertiary', this.themeState.currentTheme), iconColor: ThemeAwareHelper.getTestManagementThemedColor('icon_primary', this.themeState.currentTheme) }
          }
        },
        scrollEffectStyle: {
          backgroundStyle: {
            backgroundColor: this.themeState.currentTheme === ThemeType.DARK ? '#E61A1A1A' : '#E6F5F5F5'
          },
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
    .onReady((context: NavDestinationContext) => {
      this.pathStack = context.pathStack;
      this.onPageShow();
      this.onReady();
    })
    .backgroundColor(Color.Transparent)
  }
}

export { DownloadManagerPage }
