/**
 * 后台任务悬浮球组件
 * 显示后台任务进度，支持拖拽移动
 */
import { BackgroundTaskManager, BackgroundTask, TaskStatus, TaskProgress } from '../Task/BackgroundTaskManager';
import { logger } from '../../Utils/Logger';
import { promptAction } from '@kit.ArkUI';

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

  aboutToAppear(): void {
    // 注册悬浮球更新回调
    this.taskManager.setFloatingBallCallback((activeTasks: BackgroundTask[]) => {
      this.tasks = activeTasks;
      this.isVisible = activeTasks.length > 0;
      this.mainProgress = this.taskManager.getMainTaskProgress();
      
      // 如果所有任务完成，显示toast
      if (activeTasks.length === 0 && this.isVisible) {
        this.showCompletionToast();
      }
    });
    
    // 初始化状态
    this.tasks = this.taskManager.getActiveTasks();
    this.isVisible = this.tasks.length > 0;
    this.mainProgress = this.taskManager.getMainTaskProgress();
  }

  aboutToDisappear(): void {
    // 移除回调
    this.taskManager.setFloatingBallCallback(null);
  }

  private showCompletionToast(): void {
    try {
      promptAction.showToast({
        message: '后台任务已完成',
        duration: 2000
      });
    } catch (e) {
      logger.warn(TAG, `显示Toast失败: ${e}`);
    }
  }

  /**
   * 获取进度颜色
   */
  private getProgressColor(): ResourceColor {
    if (!this.mainProgress) return '#4CAF50';
    if (this.mainProgress.percentage >= 100) return '#4CAF50';
    if (this.mainProgress.percentage >= 50) return '#2196F3';
    return '#FF9800';
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
        .backgroundColor(this.isExpanded ? '#F5F5F5' : this.getProgressColor())
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
        .stroke('#FFFFFF40')
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
          .color('#FFFFFF')
          .backgroundColor(Color.Transparent)
          .style({ strokeWidth: 4 })
      }

      // 百分比文字
      Text(this.mainProgress ? `${this.mainProgress.percentage}%` : '0%')
        .fontSize(12)
        .fontWeight(FontWeight.Bold)
        .fontColor('#FFFFFF')
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
          .fontColor('#333333')
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
        .fontColor('#666666')
        .maxLines(1)
        .textOverflow({ overflow: TextOverflow.Ellipsis })
        .width('100%')
    }
    .width('100%')
    .padding({ left: 12, right: 12, top: 4, bottom: 4 })
    .backgroundColor('#FFFFFF')
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
      case TaskStatus.PENDING: return '#FF9800';
      case TaskStatus.RUNNING: return '#2196F3';
      case TaskStatus.COMPLETED: return '#4CAF50';
      case TaskStatus.FAILED: return '#F44336';
      case TaskStatus.CANCELLED: return '#9E9E9E';
      default: return '#9E9E9E';
    }
  }
}
