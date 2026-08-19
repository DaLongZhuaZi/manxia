/**
 * 系统状态页面 - 支持主题切换
 * 显示系统运行状态和性能监控
 */
import { HdsNavDestination, HdsNavDestinationAttribute, ScrollEffectType } from '@kit.UIDesignKit';
import { LengthMetrics } from '@kit.ArkUI';
import { ThemeManager, ThemeType } from '../Framework/Managers/ThemeManager';
import { ThemeToggle } from '../Framework/Components/ThemeToggle';
import { ThemeAwareState, ThemeAwareHelper } from '../Framework/Components/ThemeAware';

import { logger } from 'manxia_core/src/main/ets/Utils/Logger';
import { PageLifecycleManager } from 'manxia_core/src/main/ets/Framework/Lifecycle/index';

import { promptAction } from '@kit.ArkUI';

const TAG = 'SystemStatusPage';

// 定义标题栏最小高度，用于内容占位
const TITLE_BAR_HEIGHT_MINI: number = 56;

// [FIXED] 明确定义所有统计数据的接口，确保类型安全

/**
 * 导航统计接口
 */
interface NavigationStats {
  totalOperations: number;
  successfulOperations: number;
  failedOperations: number;
  averageExecutionTime: number;
}

/**
 * 动画统计接口
 */
interface AnimationStats {
  totalAnimations: number;
  successfulAnimations: number;
  failedAnimations: number;
  averageExecutionTime: number;
}

/**
 * 兼容性统计接口
 */
interface CompatibilityStats {
  totalOperations: number;
  successfulOperations: number;
  failedOperations: number;
  migrationCount: number;
}

/**
 * 系统状态信息接口
 */
interface SystemStatusInfo {
  integrationMode: string;
  lockStatus: string;
  navigationStats: NavigationStats;
  animationStats: AnimationStats;
  compatibilityStats: CompatibilityStats;
  migrationProgress: number;
  healthStatus: string;
}

/**
 * 系统性能指标接口（本地定义，包含导航和动画指标）
 */
interface SystemPerformanceMetrics {
  totalNavigations: number;
  successfulNavigations: number;
  failedNavigations: number;
  averageNavigationTime: number;
  totalAnimations: number;
  successfulAnimations: number;
  failedAnimations: number;
  averageAnimationTime: number;
}

@Component
struct SystemStatusPage {
  // [核心修改] 2. 创建一个 Scroller 实例，用于联动滚动效果
  private scroller: Scroller = new Scroller();

  // 状态变量
  @State pathStack: NavPathStack = new NavPathStack();

  // 主题相关状态
  @State themeState: ThemeAwareState = new ThemeAwareState();
  private themeManager: ThemeManager = ThemeManager.getInstance();
  private componentId: string = 'SystemStatusPage';

  // [FIXED] 初始化状态对象，确保所有属性都存在，避免 'missing properties' 错误
  @State private systemStatus: SystemStatusInfo = {
    integrationMode: '加载中...',
    lockStatus: '加载中...',
    navigationStats: { totalOperations: 0, successfulOperations: 0, failedOperations: 0, averageExecutionTime: 0 },
    animationStats: { totalAnimations: 0, successfulAnimations: 0, failedAnimations: 0, averageExecutionTime: 0 },
    compatibilityStats: { totalOperations: 0, successfulOperations: 0, failedOperations: 0, migrationCount: 0 },
    migrationProgress: 0,
    healthStatus: '检查中...'
  };

  @State private performanceMetrics: SystemPerformanceMetrics = {
    totalNavigations: 0,
    successfulNavigations: 0,
    failedNavigations: 0,
    averageNavigationTime: 0,
    totalAnimations: 0,
    successfulAnimations: 0,
    failedAnimations: 0,
    averageAnimationTime: 0
  };

  @State private refreshing: boolean = false;
  @State private autoRefresh: boolean = true;
  private refreshTimer: number = -1;

  onPageShow() {
    try {
      const stack = AppStorage.get<NavPathStack>('GlobalNavStack');
      if (stack) {
        this.pathStack = stack;
      } else {
        logger.error(TAG, '无法从 AppStorage 获取 GlobalNavStack!');
      }
    } catch (err) {
      logger.error(TAG, 'AppStorage.get 异常', err);
    }
    
    logger.lifecycle(TAG, '系统状态页面即将显示');

    // 立即刷新状态
    this.refreshSystemStatus();

    // 启动自动刷新
    if (this.autoRefresh) {
      this.startAutoRefresh();
    }
  }

  onReady() {
    // 初始化主题感知
    ThemeAwareHelper.initializeThemeAware(this.componentId, this.themeState, (newTheme: ThemeType) => {
      logger.info('SystemStatusPage', `主题已切换到: ${newTheme}`);
    });
  }

  private lifecycle = new PageLifecycleManager('SystemStatusPage', { enableDebug: true });

  aboutToDisappear() {
    this.lifecycle.destroy();
    this.stopAutoRefresh();
    // 清理主题感知
    ThemeAwareHelper.cleanupThemeAware(this.componentId);
    logger.lifecycle(TAG, '系统状态页面即将消失');
  }

  /**
   * 刷新系统状态
   */
  private async refreshSystemStatus(): Promise<void> {
    if (this.refreshing) {
      return;
    }

    this.refreshing = true;
    logger.info(TAG, '🔄 刷新系统状态');

    try {
      // 创建默认的系统状态数据，因为SystemIntegrationManager已移除
      const navStats: NavigationStats = this.createDefaultNavigationStats();
      const animStats: AnimationStats = this.createDefaultAnimationStats();
      const compatStats: CompatibilityStats = this.createDefaultCompatibilityStats();

      // 创建一个符合 SystemStatusInfo 接口的完整对象
      const newStatus: SystemStatusInfo = {
        integrationMode: 'LEGACY', // 默认模式
        lockStatus: '未锁定',
        navigationStats: navStats,
        animationStats: animStats,
        compatibilityStats: compatStats,
        migrationProgress: 0, // 默认进度
        healthStatus: this.calculateHealthStatus(navStats, animStats, compatStats)
      };
      this.systemStatus = newStatus;

      this.performanceMetrics = this.calculatePerformanceMetrics(navStats, animStats);

      logger.info(TAG, '✅ 系统状态刷新完成');
    } catch (error) {
      const errorMessage = error instanceof Error ? error.message : String(error);
      logger.error(TAG, '❌ 刷新系统状态失败', errorMessage);
      this.systemStatus.healthStatus = '状态获取失败';
    } finally {
      this.refreshing = false;
    }
  }

  /**
   * 创建默认的导航统计数据
   */
  private createDefaultNavigationStats(): NavigationStats {
    // 创建默认的导航统计数据
    return {
      totalOperations: 0,
      successfulOperations: 0,
      failedOperations: 0,
      averageExecutionTime: 0
    };
  }

  /**
   * 创建默认的动画统计数据
   */
  private createDefaultAnimationStats(): AnimationStats {
    return {
      totalAnimations: 0,
      successfulAnimations: 0,
      failedAnimations: 0,
      averageExecutionTime: 0
    };
  }

  /**
   * 创建默认的兼容性统计数据
   */
  private createDefaultCompatibilityStats(): CompatibilityStats {
    return {
      totalOperations: 0,
      successfulOperations: 0,
      failedOperations: 0,
      migrationCount: 0
    };
  }

  /**
   * 计算健康状态
   */
  private calculateHealthStatus(navStats: NavigationStats, animStats: AnimationStats, compatStats: CompatibilityStats): string {
    try {
      const navSuccessRate = navStats.totalOperations > 0 ?
        (navStats.successfulOperations / navStats.totalOperations) * 100 : 100;
      const animSuccessRate = animStats.totalAnimations > 0 ?
        (animStats.successfulAnimations / animStats.totalAnimations) * 100 : 100;

      if (navSuccessRate >= 95 && animSuccessRate >= 95) {
        return '🟢 优秀';
      } else if (navSuccessRate >= 85 && animSuccessRate >= 85) {
        return '🟡 良好';
      } else if (navSuccessRate >= 70 && animSuccessRate >= 70) {
        return '🟠 一般';
      } else {
        return '🔴 需要关注';
      }
    } catch (error) {
      return '❓ 无法计算';
    }
  }

  /**
   * 计算性能指标
   */
  private calculatePerformanceMetrics(navStats: NavigationStats, animStats: AnimationStats): SystemPerformanceMetrics {
    // [FIXED] 确保返回的对象符合 SystemPerformanceMetrics 接口
    const metrics: SystemPerformanceMetrics = {
      totalNavigations: navStats.totalOperations || 0,
      successfulNavigations: navStats.successfulOperations || 0,
      failedNavigations: navStats.failedOperations || 0,
      averageNavigationTime: navStats.averageExecutionTime || 0,
      totalAnimations: animStats.totalAnimations || 0,
      successfulAnimations: animStats.successfulAnimations || 0,
      failedAnimations: animStats.failedAnimations || 0,
      averageAnimationTime: animStats.averageExecutionTime || 0
    };
    return metrics;
  }

  /**
   * 启动自动刷新
   */
  private startAutoRefresh(): void {
    this.stopAutoRefresh();
    this.refreshTimer = setInterval(() => {
      this.refreshSystemStatus();
    }, 5000); // 每5秒刷新一次
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
   * 切换自动刷新
   */
  private toggleAutoRefresh(): void {
    this.autoRefresh = !this.autoRefresh;
    if (this.autoRefresh) {
      this.startAutoRefresh();
    } else {
      this.stopAutoRefresh();
    }
    logger.info(TAG, `自动刷新已${this.autoRefresh ? '启用' : '禁用'}`);
  }

  /**
   * 返回上一页
   */
  private async goBack(): Promise<void> {
    logger.info(TAG, '用户点击返回按钮');
    try {
      this.pathStack.pop();
    } catch (error) {
      logger.warn(TAG, '返回失败，尝试跳转到测试管理页面');
      try {
        this.pathStack.pushPath({ name: 'TestManagementPage' });
      } catch (fallbackError) {
        logger.error(TAG, '导航失败', fallbackError);
      }
    }
  }

  /**
   * 构建状态卡片
   */
  @Builder
  buildStatusCard(title: string, content: string, icon: string = '📋') {
    Column() {
      Row() {
        Text(icon)
          .fontSize(20)
          .margin({ right: 8 })

        Text(title)
          .fontSize(16)
          .fontWeight(FontWeight.Medium)
          .fontColor(ThemeAwareHelper.getTestManagementThemedColor('button_text_primary', this.themeState.currentTheme))
          .layoutWeight(1)
      }
      .width('100%')
      .margin({ bottom: 8 })

      Text(content)
        .fontSize(14)
        .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_muted', this.themeState.currentTheme))
        .width('100%')
        .textAlign(TextAlign.Start)
    }
    .width('100%')
    .padding(16)
    .backgroundColor(ThemeAwareHelper.getTestManagementThemedColor('panel_background', this.themeState.currentTheme))
    .borderRadius(12)
    .border({ width: 1, color: ThemeAwareHelper.getTestManagementThemedColor('panel_border', this.themeState.currentTheme) })
    .margin({ bottom: 12 })
  }

  /**
   * 构建性能指标卡片
   */
  @Builder
  buildMetricsCard() {
    Column() {
      Text('📈 性能指标')
        .fontSize(16)
        .fontWeight(FontWeight.Medium)
        .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_white', this.themeState.currentTheme))
        .margin({ bottom: 12 })

      // 导航指标
      Row() {
        Column() {
          Text(`${this.performanceMetrics.totalNavigations}`)
            .fontSize(20)
            .fontWeight(FontWeight.Bold)
            .fontColor(ThemeAwareHelper.getTestManagementThemedColor('accent_blue', this.themeState.currentTheme))
          Text('总导航次数')
            .fontSize(12)
            .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_muted', this.themeState.currentTheme))
        }
        .layoutWeight(1)

        Column() {
          Text(`${this.performanceMetrics.successfulNavigations}`)
            .fontSize(20)
            .fontWeight(FontWeight.Bold)
            .fontColor(ThemeAwareHelper.getTestManagementThemedColor('accent_green', this.themeState.currentTheme))
          Text('成功次数')
            .fontSize(12)
            .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_muted', this.themeState.currentTheme))
        }
        .layoutWeight(1)

        Column() {
          Text(`${this.performanceMetrics.averageNavigationTime.toFixed(1)}ms`)
            .fontSize(20)
            .fontWeight(FontWeight.Bold)
            .fontColor(ThemeAwareHelper.getTestManagementThemedColor('accent_orange', this.themeState.currentTheme))
          Text('平均耗时')
            .fontSize(12)
            .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_muted', this.themeState.currentTheme))
        }
        .layoutWeight(1)
      }
      .width('100%')
      .margin({ bottom: 16 })

      // 动画指标
      Row() {
        Column() {
          Text(`${this.performanceMetrics.totalAnimations}`)
            .fontSize(20)
            .fontWeight(FontWeight.Bold)
            .fontColor(ThemeAwareHelper.getTestManagementThemedColor('accent_blue', this.themeState.currentTheme))
          Text('总动画次数')
            .fontSize(12)
            .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_muted', this.themeState.currentTheme))
        }
        .layoutWeight(1)

        Column() {
          Text(`${this.performanceMetrics.successfulAnimations}`)
            .fontSize(20)
            .fontWeight(FontWeight.Bold)
            .fontColor(ThemeAwareHelper.getTestManagementThemedColor('accent_green', this.themeState.currentTheme))
          Text('成功次数')
            .fontSize(12)
            .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_muted', this.themeState.currentTheme))
        }
        .layoutWeight(1)

        Column() {
          Text(`${this.performanceMetrics.averageAnimationTime.toFixed(1)}ms`)
            .fontSize(20)
            .fontWeight(FontWeight.Bold)
            .fontColor(ThemeAwareHelper.getTestManagementThemedColor('accent_orange', this.themeState.currentTheme))
          Text('平均耗时')
            .fontSize(12)
            .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_muted', this.themeState.currentTheme))
        }
        .layoutWeight(1)
      }
      .width('100%')
    }
    .width('100%')
    .padding(16)
    .backgroundColor(ThemeAwareHelper.getTestManagementThemedColor('panel_background', this.themeState.currentTheme))
    .borderRadius(12)
    .border({ width: 1, color: ThemeAwareHelper.getTestManagementThemedColor('panel_border', this.themeState.currentTheme) })
    .margin({ bottom: 12 })
  }

  /**
   * 构建控制面板
   */
  @Builder
  buildControlPanel() {
    Column() {
      Text('⚙️ 控制面板')
        .fontSize(16)
        .fontWeight(FontWeight.Medium)
        .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_white', this.themeState.currentTheme))
        .margin({ bottom: 12 })

      Row() {
        Button(this.autoRefresh ? '停止自动刷新' : '启动自动刷新')
          .type(ButtonType.Normal)
          .backgroundColor(this.autoRefresh ? 
            ThemeAwareHelper.getTestManagementThemedColor('button_danger', this.themeState.currentTheme) : 
            ThemeAwareHelper.getTestManagementThemedColor('button_primary', this.themeState.currentTheme))
          .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_white', this.themeState.currentTheme))
          .borderRadius(8)
          .layoutWeight(1)
          .onClick(() => this.toggleAutoRefresh())

        Button('返回')
          .type(ButtonType.Normal)
          .backgroundColor(ThemeAwareHelper.getTestManagementThemedColor('button_secondary', this.themeState.currentTheme))
          .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_white', this.themeState.currentTheme))
          .borderRadius(8)
          .margin({ left: 12 })
          .onClick(() => this.goBack())
      }
      .width('100%')
    }
    .width('100%')
    .padding(16)
    .backgroundColor(ThemeAwareHelper.getTestManagementThemedColor('panel_background', this.themeState.currentTheme))
    .borderRadius(12)
    .border({ width: 1, color: ThemeAwareHelper.getTestManagementThemedColor('panel_border', this.themeState.currentTheme) })
  }

  build() {
    HdsNavDestination() {
      Scroll(this.scroller) {
        Column() {
          // 系统状态
          this.buildStatusCard('集成模式', this.systemStatus.integrationMode, '🔧')
          this.buildStatusCard('锁状态', this.systemStatus.lockStatus, '🔒')
          this.buildStatusCard('健康状态', this.systemStatus.healthStatus, '💚')
          this.buildStatusCard('迁移进度', `${this.systemStatus.migrationProgress.toFixed(1)}%`, '📊')

          // 性能指标
          this.buildMetricsCard()

          // 控制面板
          this.buildControlPanel()

          // 底部间距
          Text('')
            .height(20)
        }
        .width('100%')
        .padding({ left: 16, right: 16, top: 16 })
      }
      .width('100%')
      .height('100%')
      .scrollBar(BarState.Auto)
      .edgeEffect(EdgeEffect.Spring)
      .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.TOP, SafeAreaEdge.BOTTOM])
    }
    .backgroundColor(ThemeAwareHelper.getTestManagementThemedColor('background', this.themeState.currentTheme))
    .animation({ duration: 300, curve: Curve.EaseInOut })
    .titleBar({
      padding: {
        start: LengthMetrics.vp(2),
        end: LengthMetrics.vp(2)
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
        title: {
          mainTitle: "系统状态",
        },
        menu: {
          value: [{
            content: {
              label: '主题',
              icon: $r('app.media.SculptureLargeAnimalistA'),
              isEnabled: true,
              action: () => {
                this.themeManager.toggleTheme();
              }
            }
          }, {
            content: {
              label: '返回',
              icon: $r('app.media.SculptureLargeAnimalistA'),
              isEnabled: true,
              action: () => {
                this.goBack();
              }
            }
          }]
        },
      }
    })
    .onReady((context: NavDestinationContext) => {
      this.pathStack = context.pathStack;
      this.onPageShow();
    })
  }
}


export { SystemStatusPage }