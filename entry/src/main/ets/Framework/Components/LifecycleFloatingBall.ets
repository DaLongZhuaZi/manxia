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
    if (totalTasks === 0) return '#4CAF50';
    if (totalTasks > 50) return '#F44336';
    if (totalTasks > 20) return '#FF9800';
    return '#2196F3';
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
        .backgroundColor(this.isExpanded ? '#F5F5F5' : this.getStatusColor())
        .borderRadius(this.isExpanded ? 12 : 28)
        .shadow({
          radius: 8,
          color: '#00000040',
          offsetX: 2,
          offsetY: 2
        })
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
        .stroke('#FFFFFF40')
        .strokeWidth(2)

      // 任务数文字
      Column() {
        Text(this.getTotalTasks().toString())
          .fontSize(16)
          .fontWeight(FontWeight.Bold)
          .fontColor('#FFFFFF')
        
        Text('任务')
          .fontSize(8)
          .fontColor('#FFFFFFCC')
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
          .fontColor('#333333')
        
        Blank()
        
        Text('×')
          .fontSize(18)
          .fontColor('#666666')
          .onClick(() => {
            this.isExpanded = false;
          })
      }
      .width('100%')
      .padding({ left: 12, right: 12, top: 8 })

      // 统计信息
      Column({ space: 6 }) {
        this.buildStatRow('活跃页面', this.globalStats.totalPages, '#4CAF50')
        this.buildStatRow('定时器', this.globalStats.totalTimers, '#2196F3')
        this.buildStatRow('Promise', this.globalStats.totalPromises, '#FF9800')
        this.buildStatRow('资源', this.globalStats.totalResources, '#9C27B0')
        this.buildStatRow('监听器', this.globalStats.totalListeners, '#F44336')
      }
      .width('100%')
      .padding({ left: 12, right: 12 })
      .backgroundColor('#FFFFFF')
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
        .fontColor('#666666')
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
