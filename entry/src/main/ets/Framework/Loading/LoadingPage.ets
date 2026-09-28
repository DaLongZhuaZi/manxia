// 文件路径: src/main/ets/Framework/Loading/LoadingPage.ets
/**
 * 加载状态页面组件
 * 负责显示应用启动和初始化过程中的详细加载进度和状态信息
 */

import { logger } from 'manxia_core/src/main/ets/Utils/Logger';
import { LoadingStateManager } from './LoadingStateManager';
import {
  LoadingPhase,
  LoadingState,
  ErrorSeverity,
  LoadingStateSnapshot,
  LoadingStateChangeEvent,
  ErrorDetails,
  PerformanceMetrics,
  PhaseDetails
} from './LoadingStateTypes';
import { AnimatedComponent } from '../Components/AnimatedComponent';
import { AnimatedButton } from '../Components/AnimatedButton';
import { SystemIntegrationManager } from '../Managers/SystemIntegrationManager';
import { curves, UIContext } from '@kit.ArkUI';

/**
 * 加载页面组件
 */
@Component
export struct LoadingPage {
  /** 加载状态管理器 */
  private loadingManager: LoadingStateManager = LoadingStateManager.getInstance();
  
  /** UI上下文 */
  private uiContext: UIContext | undefined = undefined;
  
  /** 当前状态快照 */
  @State currentSnapshot: LoadingStateSnapshot | null = null;
  
  /** 动画状态 */
  @State progressAnimation: number = 0;
  @State phaseAnimation: number = 0;
  @State errorAnimation: number = 0;
  @State detailsExpanded: boolean = false;
  @State performanceExpanded: boolean = false;
  
  /** 显示控制 */
  @State showRetryButton: boolean = false;
  @State showSkipButton: boolean = false;
  @State showErrorDetails: boolean = false;
  
  /** 性能监控 */
  @State performanceMetrics: PerformanceMetrics | null = null;
  
  /** 状态更新定时器 */
  private updateTimer: number | null = null;
  private readonly stateChangeListener = (event: LoadingStateChangeEvent): void => {
    this.onStateChange(event);
  };
  
  aboutToAppear(): void {
    this.uiContext = this.getUIContext();
    if (!this.uiContext) {
      logger.error('LoadingPage', '获取UIContext失败');
      return;
    }
    
    // 初始化状态
    this.updateSnapshot();
    
    // 添加状态变更监听器
    this.loadingManager.addStateChangeListener(this.stateChangeListener);
    
    // 启动定时更新
    this.startPeriodicUpdate();
    
    // 启动入场动画
    setTimeout(() => {
      this.startEntranceAnimation();
    }, 100);
    
    logger.lifecycle('LoadingPage', '加载页面初始化完成');
  }
  
  aboutToDisappear(): void {
    // 清理定时器
    if (this.updateTimer) {
      clearInterval(this.updateTimer);
      this.updateTimer = null;
    }
    
    // 移除监听器
    this.loadingManager.removeStateChangeListener(this.stateChangeListener);
    
    logger.lifecycle('LoadingPage', '加载页面已销毁');
  }
  
  /**
   * 状态变更回调
   */
  private onStateChange(event: LoadingStateChangeEvent): void {
    this.updateSnapshot();
    this.updateAnimations();
    this.updateControlButtons();
    
    logger.debug('LoadingPage', `状态变更: ${event.phase} -> ${event.currentState}`);
  }
  
  /**
   * 更新状态快照
   */
  private updateSnapshot(): void {
    this.currentSnapshot = this.loadingManager.getStateSnapshot();
    this.performanceMetrics = this.currentSnapshot?.systemMetrics || null;
  }
  
  /**
   * 更新动画
   */
  private updateAnimations(): void {
    if (!this.uiContext || !this.currentSnapshot) {
      return;
    }
    
    // 进度动画
    const targetProgress = this.currentSnapshot.overallProgress.percentage;
    this.uiContext.animateTo(
      { duration: 800, curve: curves.cubicBezierCurve(0.25, 0.1, 0.25, 1) },
      () => {
        this.progressAnimation = targetProgress;
      }
    );
    
    // 阶段切换动画
    this.uiContext.animateTo(
      { duration: 500, curve: curves.springMotion(0.6, 0.8) },
      () => {
        this.phaseAnimation = this.phaseAnimation === 0 ? 1 : 0;
      }
    );
    
    // 错误动画
    if (this.currentSnapshot.hasErrors) {
      this.uiContext.animateTo(
        { duration: 300, curve: curves.fastOutSlowIn },
        () => {
          this.errorAnimation = 1;
        }
      );
    }
  }
  
  /**
   * 更新控制按钮
   */
  private updateControlButtons(): void {
    if (!this.currentSnapshot) {
      return;
    }
    
    const currentPhase = this.currentSnapshot.phases.get(this.currentSnapshot.currentPhase);
    if (!currentPhase) {
      return;
    }
    
    this.showRetryButton = currentPhase.state === LoadingState.FAILED && 
                          currentPhase.retryCount < currentPhase.maxRetries;
    
    this.showSkipButton = currentPhase.state === LoadingState.FAILED && 
                         currentPhase.skippable;
    
    this.showErrorDetails = this.currentSnapshot.hasErrors;
  }
  
  /**
   * 启动定时更新
   */
  private startPeriodicUpdate(): void {
    this.updateTimer = setInterval(() => {
      this.updateSnapshot();
    }, 1000); // 每秒更新一次
  }
  
  /**
   * 启动入场动画
   */
  private startEntranceAnimation(): void {
    if (!this.uiContext) {
      return;
    }
    
    this.uiContext.animateTo(
      { duration: 1000, curve: curves.springMotion(0.6, 0.9) },
      () => {
        this.progressAnimation = this.currentSnapshot?.overallProgress.percentage || 0;
      }
    );
  }
  
  /**
   * 重试当前阶段
   */
  private retryCurrentPhase(): void {
    if (!this.currentSnapshot) {
      return;
    }
    
    const currentPhase = this.currentSnapshot.phases.get(this.currentSnapshot.currentPhase);
    if (currentPhase && currentPhase.retryCount < currentPhase.maxRetries) {
      // 这里应该调用C++的重试接口
      logger.info('LoadingPage', `用户请求重试阶段: ${this.currentSnapshot.currentPhase}`);
    }
  }
  
  /**
   * 跳过当前阶段
   */
  private skipCurrentPhase(): void {
    if (!this.currentSnapshot) {
      return;
    }
    
    const currentPhase = this.currentSnapshot.phases.get(this.currentSnapshot.currentPhase);
    if (currentPhase && currentPhase.skippable) {
      // 这里应该调用C++的跳过接口
      logger.info('LoadingPage', `用户请求跳过阶段: ${this.currentSnapshot.currentPhase}`);
    }
  }
  
  /**
   * 返回主菜单
   */
  private goBackToMenu(): void {
    SystemIntegrationManager.getInstance().navigateToPage('MainMenuPage');
  }
  
  /**
   * 获取阶段显示名称
   */
  private getPhaseDisplayName(phase: LoadingPhase): string {
    const phaseNames: Record<LoadingPhase, string> = {
      [LoadingPhase.UNINITIALIZED]: '未初始化',
      [LoadingPhase.PRE_INIT_CHECK]: '预初始化检查',
      [LoadingPhase.GLOBAL_CONTEXT_INIT]: '全局上下文初始化',
      [LoadingPhase.RESOURCE_MANAGER_INIT]: '资源管理器初始化',
      [LoadingPhase.SURFACE_CREATION]: 'Surface创建',
      [LoadingPhase.OPENGL_INIT]: 'OpenGL初始化',
      [LoadingPhase.TEXTURE_LOADING]: '纹理加载',
      [LoadingPhase.GAME_SYSTEMS_REGISTRATION]: '游戏系统注册',
      [LoadingPhase.RENDER_LOOP_START]: '渲染循环启动',
      [LoadingPhase.READY]: '系统就绪',
      [LoadingPhase.ERROR]: '错误状态',
      [LoadingPhase.RECOVERING]: '恢复中'
    };
    
    return phaseNames[phase] || phase;
  }
  
  /**
   * 获取状态显示名称
   */
  private getStateDisplayName(state: LoadingState): string {
    const stateNames: Record<LoadingState, string> = {
      [LoadingState.PENDING]: '等待中',
      [LoadingState.IN_PROGRESS]: '进行中',
      [LoadingState.COMPLETED]: '已完成',
      [LoadingState.FAILED]: '失败',
      [LoadingState.SKIPPED]: '已跳过',
      [LoadingState.RETRYING]: '重试中'
    };
    
    return stateNames[state] || state;
  }
  
  /**
   * 获取错误严重程度颜色
   */
  private getErrorSeverityColor(severity: ErrorSeverity): ResourceStr {
    switch (severity) {
      case ErrorSeverity.INFO:
        return $r('app.color.color_info');
      case ErrorSeverity.WARNING:
        return $r('app.color.color_warning');
      case ErrorSeverity.ERROR:
        return $r('app.color.color_error');
      case ErrorSeverity.CRITICAL:
        return $r('app.color.color_error');
      default:
        return $r('app.color.text_secondary');
    }
  }
  
  /**
   * 构建主要进度显示
   */
  @Builder
  buildMainProgress() {
    Column({ space: 20 }) {
      // 整体进度环
      Stack() {
        Circle()
          .width(120)
          .height(120)
          .fill(Color.Transparent)
          .stroke($r('app.color.divider_primary'))
          .strokeWidth(8)
        
        Circle()
          .width(120)
          .height(120)
          .fill(Color.Transparent)
          .stroke($r('app.color.brand_primary'))
          .strokeWidth(8)
          .strokeDashArray([1, 0])
          .strokeDashOffset(0)
          .transform({
            rotate: {
              angle: -90,
              centerX: '50%',
              centerY: '50%'
            }
          })
          .animation({
            duration: 1000,
            curve: curves.cubicBezierCurve(0.25, 0.1, 0.25, 1)
          })
        
        Column({ space: 4 }) {
          Text(`${Math.round(this.progressAnimation)}%`)
            .fontSize(24)
            .fontWeight(FontWeight.Bold)
            .fontColor($r('app.color.text_primary'))
          
          Text('整体进度')
            .fontSize(12)
            .fontColor($r('app.color.text_secondary'))
        }
      }
      .width(120)
      .height(120)
      
      // 当前阶段信息
      if (this.currentSnapshot) {
        Column({ space: 8 }) {
          Text(this.getPhaseDisplayName(this.currentSnapshot.currentPhase))
            .fontSize(18)
            .fontWeight(FontWeight.Medium)
            .fontColor($r('app.color.text_primary'))
            .textAlign(TextAlign.Center)
          
          const currentPhase = this.currentSnapshot.phases.get(this.currentSnapshot.currentPhase);
          if (currentPhase) {
            Text(this.getStateDisplayName(currentPhase.state))
              .fontSize(14)
              .fontColor(this.getStateColor(currentPhase.state))
              .textAlign(TextAlign.Center)
          }
        }
        .width('100%')
      }
    }
    .width('100%')
    .padding(20)
  }
  
  /**
   * 获取状态颜色
   */
  private getStateColor(state: LoadingState): ResourceStr {
    switch (state) {
      case LoadingState.PENDING:
        return $r('app.color.text_secondary');
      case LoadingState.IN_PROGRESS:
        return $r('app.color.brand_primary');
      case LoadingState.COMPLETED:
        return $r('app.color.color_success');
      case LoadingState.FAILED:
        return $r('app.color.color_error');
      case LoadingState.SKIPPED:
        return $r('app.color.color_warning');
      case LoadingState.RETRYING:
        return $r('app.color.color_info');
      default:
        return $r('app.color.text_secondary');
    }
  }
  
  /**
   * 构建阶段列表
   */
  @Builder
  buildPhaseList() {
    Column({ space: 12 }) {
      Row() {
        Text('加载阶段详情')
          .fontSize(16)
          .fontWeight(FontWeight.Medium)
          .fontColor($r('app.color.text_primary'))
        
        Spacer()
        
        Button(this.detailsExpanded ? '收起' : '展开')
          .type(ButtonType.Normal)
          .fontSize(12)
          .backgroundColor(Color.Transparent)
          .fontColor($r('app.color.brand_primary'))
          .onClick(() => {
            if (this.uiContext) {
              this.uiContext.animateTo(
                { duration: 300, curve: curves.fastOutSlowIn },
                () => {
                  this.detailsExpanded = !this.detailsExpanded;
                }
              );
            }
          })
      }
      .width('100%')
      
      if (this.detailsExpanded && this.currentSnapshot) {
        List({ space: 8 }) {
          ForEach(Array.from(this.currentSnapshot.phases.entries()), (item: [LoadingPhase, PhaseDetails]) => {
            const [phase, detail] = item;
            ListItem() {
              this.buildPhaseItem(phase, detail);
            }
          })
        }
        .width('100%')
        .height(200)
        .scrollBar(BarState.Auto)
      }
    }
    .width('100%')
    .padding({ left: 20, right: 20 })
  }
  
  /**
   * 构建阶段项目
   */
  @Builder
  buildPhaseItem(phase: LoadingPhase, detail: PhaseDetails) {
    Row({ space: 12 }) {
      // 状态指示器
      Circle()
        .width(12)
        .height(12)
        .fill(this.getStateColor(detail.state))
      
      Column({ space: 4 }) {
        Row() {
          Text(this.getPhaseDisplayName(phase))
            .fontSize(14)
            .fontWeight(FontWeight.Medium)
            .fontColor($r('app.color.text_primary'))
          
          Spacer()
          
          Text(this.getStateDisplayName(detail.state))
            .fontSize(12)
            .fontColor(this.getStateColor(detail.state))
        }
        .width('100%')
        
        if (detail.state === LoadingState.IN_PROGRESS) {
          Progress({ value: detail.progress.current, total: detail.progress.total })
            .width('100%')
            .height(4)
            .color($r('app.color.brand_primary'))
            .backgroundColor($r('app.color.divider_primary'))
        }
        
        if (detail.duration) {
          Text(`耗时: ${detail.duration}ms`)
            .fontSize(10)
            .fontColor($r('app.color.text_secondary'))
        }
        
        if (detail.retryCount > 0) {
          Text(`重试次数: ${detail.retryCount}/${detail.maxRetries}`)
            .fontSize(10)
            .fontColor($r('app.color.color_warning'))
        }
      }
      .layoutWeight(1)
    }
    .width('100%')
    .padding(12)
    .backgroundColor($r('app.color.background_secondary'))
    .borderRadius(8)
  }
  
  /**
   * 构建错误信息
   */
  @Builder
  buildErrorInfo() {
    if (!this.showErrorDetails || !this.currentSnapshot || !this.currentSnapshot.hasErrors) {
      return;
    }
    
    Column({ space: 12 }) {
      Text('错误信息')
        .fontSize(16)
        .fontWeight(FontWeight.Medium)
        .fontColor($r('app.color.color_error'))
      
      List({ space: 8 }) {
        ForEach(this.currentSnapshot.globalErrors, (error: ErrorDetails, index: number) => {
          ListItem() {
            this.buildErrorItem(error, index);
          }
        })
      }
      .width('100%')
      .height(150)
      .scrollBar(BarState.Auto)
    }
    .width('100%')
    .padding({ left: 20, right: 20 })
    .opacity(this.errorAnimation)
  }
  
  /**
   * 构建错误项目
   */
  @Builder
  buildErrorItem(error: ErrorDetails, index: number) {
    Column({ space: 8 }) {
      Row() {
        Text(`[${error.severity}] ${error.code}`)
          .fontSize(12)
          .fontWeight(FontWeight.Medium)
          .fontColor(this.getErrorSeverityColor(error.severity))
        
        Spacer()
        
        Text(new Date(error.timestamp).toLocaleTimeString())
          .fontSize(10)
          .fontColor($r('app.color.text_secondary'))
      }
      .width('100%')
      
      Text(error.message)
        .fontSize(12)
        .fontColor($r('app.color.text_primary'))
        .maxLines(2)
        .textOverflow({ overflow: TextOverflow.Ellipsis })
    }
    .width('100%')
    .padding(12)
    .backgroundColor($r('app.color.background_secondary'))
    .borderRadius(8)
    .border({
      width: 1,
      color: this.getErrorSeverityColor(error.severity)
    })
  }
  
  /**
   * 构建性能监控
   */
  @Builder
  buildPerformanceMonitor() {
    if (!this.performanceMetrics) {
      return;
    }
    
    Column({ space: 12 }) {
      Row() {
        Text('性能监控')
          .fontSize(16)
          .fontWeight(FontWeight.Medium)
          .fontColor($r('app.color.text_primary'))
        
        Spacer()
        
        Button(this.performanceExpanded ? '收起' : '展开')
          .type(ButtonType.Normal)
          .fontSize(12)
          .backgroundColor(Color.Transparent)
          .fontColor($r('app.color.brand_primary'))
          .onClick(() => {
            if (this.uiContext) {
              this.uiContext.animateTo(
                { duration: 300, curve: curves.fastOutSlowIn },
                () => {
                  this.performanceExpanded = !this.performanceExpanded;
                }
              );
            }
          })
      }
      .width('100%')
      
      if (this.performanceExpanded) {
        Column({ space: 8 }) {
          this.buildMetricItem('内存使用', 
            `${Math.round((this.performanceMetrics.memoryUsage || 0) / 1024 / 1024)}MB`,
            (this.performanceMetrics.memoryUsage || 0) / (200 * 1024 * 1024) * 100);
          
          this.buildMetricItem('CPU使用率', 
            `${Math.round(this.performanceMetrics.cpuUsage || 0)}%`,
            this.performanceMetrics.cpuUsage || 0);
          
          this.buildMetricItem('帧率', 
            `${Math.round(this.performanceMetrics.fps || 0)}fps`,
            (this.performanceMetrics.fps || 0) / 60 * 100);
          
          this.buildMetricItem('渲染时间', 
            `${Math.round(this.performanceMetrics.renderTime || 0)}ms`,
            Math.min((this.performanceMetrics.renderTime || 0) / 50 * 100, 100));
        }
        .width('100%')
      }
    }
    .width('100%')
    .padding({ left: 20, right: 20 })
  }
  
  /**
   * 构建指标项目
   */
  @Builder
  buildMetricItem(name: string, value: string, percentage: number) {
    Row({ space: 12 }) {
      Text(name)
        .fontSize(12)
        .fontColor($r('app.color.text_secondary'))
        .width(60)
      
      Progress({ value: percentage, total: 100 })
        .width(80)
        .height(6)
        .color(percentage > 80 ? $r('app.color.color_error') : 
               percentage > 60 ? $r('app.color.color_warning') : 
               $r('app.color.color_success'))
        .backgroundColor($r('app.color.divider_primary'))
      
      Text(value)
        .fontSize(12)
        .fontColor($r('app.color.text_primary'))
        .width(50)
        .textAlign(TextAlign.End)
    }
    .width('100%')
  }
  
  /**
   * 构建控制按钮
   */
  @Builder
  buildControlButtons() {
    Row({ space: 16 }) {
      if (this.showRetryButton) {
        AnimatedButton({
          text: '重试',
          type: 'primary',
          size: 'medium',
          onClick: () => this.retryCurrentPhase()
        })
      }
      
      if (this.showSkipButton) {
        AnimatedButton({
          text: '跳过',
          type: 'secondary',
          size: 'medium',
          onClick: () => this.skipCurrentPhase()
        })
      }
      
      AnimatedButton({
        text: '返回菜单',
        type: 'outline',
        size: 'medium',
        onClick: () => this.goBackToMenu()
      })
    }
    .width('100%')
    .justifyContent(FlexAlign.Center)
    .padding({ left: 20, right: 20, bottom: 20 })
  }
  
  build() {
    Stack() {
      // 背景层
      Column()
        .width('100%')
        .height('100%')
        .backgroundColor($r('app.color.background_primary'))
      
      // 内容层 - 预留安全区域
      Column() {
        Scroll() {
          Column({ space: 24 }) {
            // 主要进度显示
            this.buildMainProgress();
            
            // 阶段列表
            this.buildPhaseList();
            
            // 错误信息
            this.buildErrorInfo();
            
            // 性能监控
            this.buildPerformanceMonitor();
          }
          .width('100%')
        }
        .width('100%')
        .layoutWeight(1)
        .scrollBar(BarState.Auto)
        
        // 控制按钮
        this.buildControlButtons();
      }
      .width('100%')
      .height('100%')
      .padding({
        top: this.statusBarHeight,
        bottom: this.navigationBarHeight
      })
    }
    .width('100%')
    .height('100%')
  }
}
