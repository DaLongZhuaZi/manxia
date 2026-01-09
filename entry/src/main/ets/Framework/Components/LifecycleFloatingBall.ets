/**
 * 生命周期监控悬浮球组件
 * 显示全局生命周期任务统计，支持拖拽移动
 * 
 * 文件路径: entry/src/main/ets/Framework/Components/LifecycleFloatingBall.ets
 */

import { GlobalTaskCoordinator, GlobalStats, PageStats } from '../Lifecycle';
import { logger } from '../../Utils/Logger';
import { promptAction } from '@kit.ArkUI';
import { SettingsManager } from '../Managers/SettingsManager';
import { AppColors, ColorRole } from '../Theme/AppColors';

const TAG = 'LifecycleFloatingBall';

/**
 * 悬浮球位置
 */
interface FloatingBallPosition {
  x: number;
  y: number;
}

/**
 * 生命周期监控悬浮球组件
 */
@Component
export struct LifecycleFloatingBall {
  @State private isVisible: boolean = false;
  @State private globalStats: GlobalStats = {
    totalPages: 0,
    totalTimers: 0,
    totalPromises: 0,
    totalResources: 0,
    totalListeners: 0
  };
  @State private ballPosition: FloatingBallPosition = { x: 20, y: 300 };
  @State private isDragging: boolean = false;
  @State private isExpanded: boolean = false;
  @State private pageStatsList: PageStats[] = [];
  
  private coordinator = GlobalTaskCoordinator.getInstance();
  private settingsManager = SettingsManager.getInstance();
  private dragStartX: number = 0;
  private dragStartY: number = 0;
  private ballStartX: number = 0;
  private ballStartY: number = 0;
  private refreshTimer: number = -1;

  aboutToAppear(): void {
    // 检查是否启用悬浮球
    this.checkVisibility();
    
    // 启动自动刷新
    this.startAutoRefresh();
  }

  aboutToDisappear(): void {
    this.stopAutoRefresh();
  }

  /**
   * 检查悬浮球可见性
   */
  private async checkVisibility(): Promise<void> {
    try {
      const enabled = await this.settingsManager.getLifecycleMonitorFloatingBallEnabled();
      this.isVisible = enabled;
      if (enabled) {
        this.refreshData();
      }
    } catch (error) {
      logger.error(TAG, `检查可见性失败: ${error}`);
    }
  }

  /**
   * 刷新数据
   */
  private refreshData(): void {
    try {
      this.globalStats = this.coordinator.getGlobalStats();
      const dump = this.coordinator.dumpActiveTasks();
      this.pageStatsList = dump.pages;
    } catch (error) {
      logger.error(TAG, `刷新数据失败: ${error}`);
    }
  }

  /**
   * 启动自动刷新
   */
  private startAutoRefresh(): void {
    if (this.refreshTimer !== -1) {
      return;
    }
    
    this.refreshTimer = setInterval(() => {
      if (this.isVisible) {
        this.refreshData();
      }
    }, 2000) as number;
  }

  /**
   * 停止自动刷新
   */
  private stopAutoRefresh(): void {
    if (this.refreshTimer !== -1) {
      clearInterval(this.refreshTimer);
      this.refreshTimer = -1;
    }
  }

  /**
   * 获取总任务数
   */
  private getTotalTasks(): number {
    return this.globalStats.totalTimers + 
           this.globalStats.totalPromises + 
           this.globalStats.totalResources;
  }

  /**
   * 获取状态颜色
   */
  private getStatusColor(): ResourceColor {
    const totalTasks = this.getTotalTasks();
    if (totalTasks === 0) return AppColors.success;
    if (totalTasks > 50) return AppColors.error;
    if (totalTasks > 20) return AppColors.warning;
    return AppColors.info;
  }

  build() {
    if (this.isVisible) {
      Stack() {
        Column() {
          if (this.isExpanded) {
            this.buildExpandedView()
          } else {
            this.buildCollapsedView()
          }
        }
        .width(this.isExpanded ? 220 : 56)
        .height(this.isExpanded ? 'auto' : 56)
        .backgroundColor(this.isExpanded ? AppColors.surfaceVariant : this.getStatusColor())
        .borderRadius(this.isExpanded ? AppColors.cornerRadius : 28)
        .opacity(AppColors.getTransparency('floatingBall'))
        .shadow(AppColors.shadowEnabled ? {
          radius: 8,
          color: AppColors.getShadowColor(4),
          offsetX: 2,
          offsetY: 2
        } : undefined)
        .animation({
          duration: 200,
          curve: Curve.EaseOut
        })
      }
      .position({
        x: this.ballPosition.x,
        y: this.ballPosition.y
      })
      .gesture(
        PanGesture()
          .onActionStart((event: GestureEvent) => {
            this.isDragging = true;
            this.dragStartX = event.offsetX;
            this.dragStartY = event.offsetY;
            this.ballStartX = this.ballPosition.x;
            this.ballStartY = this.ballPosition.y;
          })
          .onActionUpdate((event: GestureEvent) => {
            if (this.isDragging) {
              this.ballPosition = {
                x: this.ballStartX + event.offsetX - this.dragStartX,
                y: this.ballStartY + event.offsetY - this.dragStartY
              };
            }
          })
          .onActionEnd(() => {
            this.isDragging = false;
          })
      )
      .onClick(() => {
        if (!this.isDragging) {
          this.isExpanded = !this.isExpanded;
        }
      })
      .zIndex(9998)
    }
  }

  @Builder
  private buildCollapsedView() {
    Stack() {
      // 背景圆
      Circle()
        .width(48)
        .height(48)
        .fill(Color.Transparent)
        .stroke(AppColors.withAlpha(ColorRole.ON_PRIMARY, 0.25))
        .strokeWidth(2)

      // 任务数文字
      Column() {
        Text(this.getTotalTasks().toString())
          .fontSize(16)
          .fontWeight(FontWeight.Bold)
          .fontColor(AppColors.onPrimary)
        
        Text('任务')
          .fontSize(8)
          .fontColor(AppColors.withAlpha(ColorRole.ON_PRIMARY, 0.8))
      }
    }
    .width(56)
    .height(56)
    .alignContent(Alignment.Center)
  }

  @Builder
  private buildExpandedView() {
    Column({ space: 8 }) {
      // 标题栏
      Row() {
        Text('生命周期')
          .fontSize(14)
          .fontWeight(FontWeight.Bold)
          .fontColor(AppColors.textPrimary)
        
        Blank()
        
        Text('×')
          .fontSize(18)
          .fontColor(AppColors.textSecondary)
          .onClick(() => {
            this.isExpanded = false;
          })
      }
      .width('100%')
      .padding({ left: 12, right: 12, top: 8 })

      // 统计信息
      Column({ space: 6 }) {
        this.buildStatRow('活跃页面', this.globalStats.totalPages, AppColors.success)
        this.buildStatRow('定时器', this.globalStats.totalTimers, AppColors.info)
        this.buildStatRow('Promise', this.globalStats.totalPromises, AppColors.warning)
        this.buildStatRow('资源', this.globalStats.totalResources, AppColors.tertiary)
        this.buildStatRow('监听器', this.globalStats.totalListeners, AppColors.error)
      }
      .width('100%')
      .padding({ left: 12, right: 12 })
      .backgroundColor(AppColors.surface)
      .borderRadius(8)
      .margin({ left: 8, right: 8 })

      // 底部间距
      Row().height(8)
    }
    .width('100%')
  }

  @Builder
  private buildStatRow(label: string, value: number, color: string) {
    Row() {
      Text(label)
        .fontSize(11)
        .fontColor(AppColors.textSecondary)
        .layoutWeight(1)
      
      Text(value.toString())
        .fontSize(12)
        .fontWeight(FontWeight.Bold)
        .fontColor(color)
    }
    .width('100%')
    .padding({ top: 4, bottom: 4 })
  }
}
