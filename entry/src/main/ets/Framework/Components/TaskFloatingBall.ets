/**
 * 后台任务悬浮球组件
 * 显示后台任务进度，支持拖拽移动
 */
import { BackgroundTaskManager, BackgroundTask, TaskStatus, TaskProgress, TaskStatusListener } from '../Task/BackgroundTaskManager';
import { logger } from '../../Utils/Logger';
import { promptAction } from '@kit.ArkUI';
import { AppColors, ColorRole } from '../Theme/AppColors';

const TAG = 'TaskFloatingBall';

/**
 * 悬浮球位置
 */
interface FloatingBallPosition {
  x: number;
  y: number;
}

/**
 * 后台任务悬浮球组件
 */
@Component
export struct TaskFloatingBall {
  @State private isVisible: boolean = false;
  @State private tasks: BackgroundTask[] = [];
  @State private mainProgress: TaskProgress | null = null;
  @State private ballPosition: FloatingBallPosition = { x: 20, y: 200 };
  @State private isDragging: boolean = false;
  @State private isExpanded: boolean = false;
  
  private taskManager: BackgroundTaskManager = BackgroundTaskManager.getInstance();
  private dragStartX: number = 0;
  private dragStartY: number = 0;
  private ballStartX: number = 0;
  private ballStartY: number = 0;
  private taskStatusListener: TaskStatusListener = (_task: BackgroundTask): void => {
    const wasVisible = this.isVisible;
    this.refreshTaskState(wasVisible);
  };

  aboutToAppear(): void {
    this.taskManager.addListener(this.taskStatusListener);
    this.refreshTaskState(false);
  }

  aboutToDisappear(): void {
    this.taskManager.removeListener(this.taskStatusListener);
  }

  private showCompletionToast(): void {
    try {
      this.getUIContext().getPromptAction().showToast({
        message: '后台任务已完成',
        duration: 2000
      });
    } catch (e) {
      logger.warn(TAG, `显示Toast失败: ${e}`);
    }
  }

  /**
   * 从任务管理器重新同步悬浮球状态
   */
  private refreshTaskState(wasVisible: boolean): void {
    const activeTasks = this.taskManager.getActiveTasks();
    this.tasks = activeTasks;
    this.mainProgress = this.taskManager.getMainTaskProgress();
    this.isVisible = activeTasks.length > 0;

    if (wasVisible && activeTasks.length === 0) {
      this.showCompletionToast();
    }
  }

  /**
   * 获取进度颜色
   */
  private getProgressColor(): ResourceColor {
    if (!this.mainProgress) return AppColors.success;
    if (this.mainProgress.percentage >= 100) return AppColors.success;
    if (this.mainProgress.percentage >= 50) return AppColors.info;
    return AppColors.warning;
  }

  /**
   * 获取状态图标
   */
  private getStatusIcon(): string {
    const runningTask = this.tasks.find(t => t.status === TaskStatus.RUNNING);
    if (runningTask) return '⏳';
    const pendingTask = this.tasks.find(t => t.status === TaskStatus.PENDING);
    if (pendingTask) return '⏸️';
    return '✅';
  }

  build() {
    if (this.isVisible) {
      Stack() {
        // 悬浮球主体
        Column() {
          if (this.isExpanded) {
            // 展开状态 - 显示任务列表
            this.buildExpandedView()
          } else {
            // 收起状态 - 只显示进度
            this.buildCollapsedView()
          }
        }
        .width(this.isExpanded ? 200 : 56)
        .height(this.isExpanded ? 'auto' : 56)
        .backgroundColor(this.isExpanded ? AppColors.surfaceVariant : this.getProgressColor())
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
      .zIndex(9999)
    }
  }

  @Builder
  private buildCollapsedView() {
    Stack() {
      // 进度环背景
      Circle()
        .width(48)
        .height(48)
        .fill(Color.Transparent)
        .stroke(AppColors.withAlpha(ColorRole.ON_PRIMARY, 0.25))
        .strokeWidth(4)

      // 进度环
      if (this.mainProgress) {
        Progress({
          value: this.mainProgress.percentage,
          total: 100,
          type: ProgressType.Ring
        })
          .width(48)
          .height(48)
          .color(AppColors.onPrimary)
          .backgroundColor(Color.Transparent)
          .style({ strokeWidth: 4 })
      }

      // 百分比文字
      Text(this.mainProgress ? `${this.mainProgress.percentage}%` : '0%')
        .fontSize(12)
        .fontWeight(FontWeight.Bold)
        .fontColor(AppColors.onPrimary)
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
        Text('后台任务')
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

      // 任务列表
      ForEach(this.tasks, (task: BackgroundTask) => {
        this.buildTaskItem(task)
      }, (task: BackgroundTask) => task.id)

      // 底部间距
      Row().height(8)
    }
    .width('100%')
  }

  @Builder
  private buildTaskItem(task: BackgroundTask) {
    Column({ space: 4 }) {
      Row() {
        Text(task.name)
          .fontSize(12)
          .fontColor(AppColors.textPrimary)
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
          .layoutWeight(1)
        
        Text(this.getTaskStatusText(task.status))
          .fontSize(10)
          .fontColor(this.getTaskStatusColor(task.status))
      }
      .width('100%')

      // 进度条
      Progress({
        value: task.progress.percentage,
        total: 100,
        type: ProgressType.Linear
      })
        .width('100%')
        .height(4)
        .color(this.getTaskStatusColor(task.status))

      // 进度信息
      Text(task.progress.message)
        .fontSize(10)
        .fontColor(AppColors.textSecondary)
        .maxLines(1)
        .textOverflow({ overflow: TextOverflow.Ellipsis })
        .width('100%')
    }
    .width('100%')
    .padding({ left: 12, right: 12, top: 4, bottom: 4 })
    .backgroundColor(AppColors.surface)
    .borderRadius(8)
    .margin({ left: 8, right: 8 })
  }

  private getTaskStatusText(status: TaskStatus): string {
    switch (status) {
      case TaskStatus.PENDING: return '等待中';
      case TaskStatus.RUNNING: return '进行中';
      case TaskStatus.COMPLETED: return '已完成';
      case TaskStatus.FAILED: return '失败';
      case TaskStatus.CANCELLED: return '已取消';
      default: return '未知';
    }
  }

  private getTaskStatusColor(status: TaskStatus): ResourceColor {
    switch (status) {
      case TaskStatus.PENDING: return AppColors.warning;
      case TaskStatus.RUNNING: return AppColors.info;
      case TaskStatus.COMPLETED: return AppColors.success;
      case TaskStatus.FAILED: return AppColors.error;
      case TaskStatus.CANCELLED: return AppColors.textTertiary;
      default: return AppColors.textTertiary;
    }
  }
}
