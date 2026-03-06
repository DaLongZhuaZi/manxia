/**
 * Hello World页面 - 支持主题切换
 * 提供基础的测试功能和交互演示
 */

import { logger } from '../Utils/Logger';
import { HdsNavDestination, HdsNavDestinationAttribute, ScrollEffectType } from '@kit.UIDesignKit';
import { LengthMetrics } from '@kit.ArkUI';
import { ThemeManager, ThemeType } from '../Framework/Managers/ThemeManager';
import { ThemeToggle } from '../Framework/Components/ThemeToggle';
import { ThemeAwareState, ThemeAwareHelper } from '../Framework/Components/ThemeAware';

// 添加必要的类型导入
interface NavDestinationContext {
  pathStack: NavPathStack;
}


const TAG = 'HelloWorldPage';
const TITLE_BAR_HEIGHT_MINI = 56;

@Component
struct HelloWorldPage {
  // 创建一个 Scroller 实例，用于联动滚动效果
  private scroller: Scroller = new Scroller();

  // 状态变量
  @State pathStack: NavPathStack = new NavPathStack();

  // 主题相关状态
  @State themeState: ThemeAwareState = new ThemeAwareState();
  private themeManager: ThemeManager = ThemeManager.getInstance();
  private componentId: string = 'HelloWorldPage';

  @State message: string = 'Hello World!';
  @State counter: number = 0;

  onPageShow() {
    logger.lifecycle(TAG, 'Hello World页面显示');
    try {
      const globalNavStack = AppStorage.get<NavPathStack>('GlobalNavStack');
      if (globalNavStack) {
        this.pathStack = globalNavStack;
      }
    } catch (error) {
      logger.error(TAG, `获取全局导航栈失败: ${error}`);
    }
    // 启动入场动画
    this.startEntranceAnimations();
  }

  onReady() {
    // 初始化主题感知
    ThemeAwareHelper.initializeThemeAware(
      this.componentId,
      this.themeState,
      (newTheme: ThemeType) => {
        // 主题变化回调
        logger.info('HelloWorldPage', `主题已切换到: ${newTheme}`);
      }
    );
  }

  aboutToDisappear() {
    // 清理主题感知
    ThemeAwareHelper.cleanupThemeAware(this.componentId);
    logger.lifecycle(TAG, 'Hello World页面即将消失');
  }

  /**
   * 启动入场动画
   */
  private startEntranceAnimations(): void {
    logger.info(TAG, '启动入场动画');
    // 这里可以添加具体的动画逻辑
  }

  /**
   * 返回上一页
   */
  private goBack(): void {
    logger.info(TAG, '用户点击返回按钮');
    try {
      this.pathStack.pop();
      logger.info(TAG, '✅ 成功返回上一页');
    } catch (error) {
      logger.error(TAG, `返回失败: ${error}`);
      // 如果返回失败，尝试跳转到测试管理页面
      try {
        this.pathStack.pushPath({ name: 'TestManagementPage' });
        logger.info(TAG, '✅ 成功跳转到测试管理页面');
      } catch (fallbackError) {
        logger.error(TAG, `跳转到测试管理页面失败: ${fallbackError}`);
      }
    }
  }

  build() {
    HdsNavDestination() {
      Scroll(this.scroller) {
        Column() {
          // 欢迎信息面板
          this.buildWelcomePanel()

          // 交互测试面板
          this.buildInteractionPanel()

          // 功能演示面板
          this.buildDemoPanel()
        }
        .width('100%')
        .padding({ left: 16, right: 16, bottom: 16 })
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
        start: LengthMetrics.vp(16),
        end: LengthMetrics.vp(16)
      },
      style: {
        scrollEffectOpts: {
          enableScrollEffect: true,
          scrollEffectType: ScrollEffectType.COMMON_BLUR,
          blurEffectiveStartOffset: LengthMetrics.vp(0),
          blurEffectiveEndOffset: LengthMetrics.vp(TITLE_BAR_HEIGHT_MINI + 20)
        },
        originalStyle: {
          backgroundStyle: {
            backgroundColor: Color.Transparent,
          },
          contentStyle: {
            titleStyle: { 
              mainTitleColor: ThemeAwareHelper.getTestManagementThemedColor('text_white', this.themeState.currentTheme),
              subTitleColor: ThemeAwareHelper.getTestManagementThemedColor('text_muted', this.themeState.currentTheme)
            },
            menuStyle: { backgroundColor: $r('sys.color.comp_background_tertiary'), iconColor: $r('sys.color.icon_primary') },
            backIconStyle: { backgroundColor: $r('sys.color.comp_background_tertiary'), iconColor: $r('sys.color.icon_primary') }
          }
        },
        scrollEffectStyle: {
          backgroundStyle: {
            backgroundColor: ThemeAwareHelper.getTestManagementThemedColor('panel_background', this.themeState.currentTheme)
          },
          contentStyle: {
            titleStyle: { 
              mainTitleColor: ThemeAwareHelper.getTestManagementThemedColor('text_white', this.themeState.currentTheme),
              subTitleColor: ThemeAwareHelper.getTestManagementThemedColor('text_muted', this.themeState.currentTheme)
            },
            menuStyle: { backgroundColor: $r('sys.color.comp_background_tertiary'), iconColor: $r('sys.color.icon_primary') },
            backIconStyle: { backgroundColor: $r('sys.color.comp_background_tertiary'), iconColor: $r('sys.color.icon_primary') }
          }
        }
      },
      content: {
        title: {
          mainTitle: "Hello World",
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
      logger.info(TAG, 'HdsNavDestination.onReady 已触发');
      this.pathStack = context.pathStack;
      this.onPageShow();
    })
  }

  @Builder
  buildWelcomePanel() {
    Column() {
      Text('👋 欢迎使用')
        .fontSize(16)
        .fontWeight(FontWeight.Medium)
        .fontColor(ThemeAwareHelper.getTestManagementThemedColor('button_text_primary', this.themeState.currentTheme))
        .margin({ bottom: 12 })

      Text(this.message)
        .fontSize(18)
        .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_muted', this.themeState.currentTheme))
        .margin({ bottom: 16 })

      Text('这是一个基础的测试页面，用于演示导航和交互功能')
        .fontSize(14)
        .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_muted', this.themeState.currentTheme))
        .textAlign(TextAlign.Center)
        .lineHeight(20)
    }
    .width('100%')
    .padding(16)
    .backgroundColor(ThemeAwareHelper.getTestManagementThemedColor('panel_background', this.themeState.currentTheme))
    .borderRadius(12)
    .border({ width: 1, color: ThemeAwareHelper.getTestManagementThemedColor('panel_border', this.themeState.currentTheme) })
    .margin({ bottom: 12 })
  }

  @Builder
  buildInteractionPanel() {
    Column() {
      Text('🎯 交互测试')
        .fontSize(16)
        .fontWeight(FontWeight.Medium)
        .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_white', this.themeState.currentTheme))
        .margin({ bottom: 12 })

      // 计数器显示
      Row() {
        Column() {
          Text(`${this.counter}`)
            .fontSize(24)
            .fontWeight(FontWeight.Bold)
            .fontColor(ThemeAwareHelper.getTestManagementThemedColor('accent_blue', this.themeState.currentTheme))
          Text('点击次数')
            .fontSize(12)
            .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_muted', this.themeState.currentTheme))
        }
        .layoutWeight(1)

        Column() {
          Text(this.counter > 0 ? '活跃' : '待激活')
            .fontSize(16)
            .fontWeight(FontWeight.Bold)
            .fontColor(this.counter > 0 ? 
              ThemeAwareHelper.getTestManagementThemedColor('accent_green', this.themeState.currentTheme) : 
              ThemeAwareHelper.getTestManagementThemedColor('accent_orange', this.themeState.currentTheme))
          Text('状态')
            .fontSize(12)
            .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_muted', this.themeState.currentTheme))
        }
        .layoutWeight(1)
      }
      .width('100%')
      .margin({ bottom: 16 })

      // 操作按钮
      Row() {
        Button('点击我')
          .type(ButtonType.Normal)
          .backgroundColor(ThemeAwareHelper.getTestManagementThemedColor('button_primary', this.themeState.currentTheme))
          .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_white', this.themeState.currentTheme))
          .borderRadius(8)
          .layoutWeight(1)
          .onClick(() => {
            this.counter++;
            logger.info(TAG, `按钮点击，计数器: ${this.counter}`);
          })

        Button('重置')
          .type(ButtonType.Normal)
          .backgroundColor(ThemeAwareHelper.getTestManagementThemedColor('button_danger', this.themeState.currentTheme))
          .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_white', this.themeState.currentTheme))
          .borderRadius(8)
          .margin({ left: 12 })
          .layoutWeight(1)
          .onClick(() => {
            this.counter = 0;
            logger.info(TAG, '计数器已重置');
          })
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

  @Builder
  buildDemoPanel() {
    Column() {
      Text('🚀 功能演示')
        .fontSize(16)
        .fontWeight(FontWeight.Medium)
        .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_white', this.themeState.currentTheme))
        .margin({ bottom: 12 })

      Text('这个页面展示了以下功能：')
        .fontSize(14)
        .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_muted', this.themeState.currentTheme))
        .margin({ bottom: 8 })

      Column() {
        Text('• HdsNavDestination 导航模式')
          .fontSize(12)
          .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_muted', this.themeState.currentTheme))
          .alignSelf(ItemAlign.Start)
          .margin({ bottom: 4 })

        Text('• 滚动模糊标题栏效果')
          .fontSize(12)
          .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_muted', this.themeState.currentTheme))
          .alignSelf(ItemAlign.Start)
          .margin({ bottom: 4 })

        Text('• 统一的颜色资源管理')
          .fontSize(12)
          .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_muted', this.themeState.currentTheme))
          .alignSelf(ItemAlign.Start)
          .margin({ bottom: 4 })

        Text('• 响应式布局设计')
          .fontSize(12)
          .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_muted', this.themeState.currentTheme))
          .alignSelf(ItemAlign.Start)
      }
      .width('100%')
      .margin({ bottom: 16 })

      Button('返回上一页')
        .type(ButtonType.Normal)
        .backgroundColor(ThemeAwareHelper.getTestManagementThemedColor('button_secondary', this.themeState.currentTheme))
        .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_white', this.themeState.currentTheme))
        .borderRadius(8)
        .width('100%')
        .onClick(() => this.goBack())
    }
    .width('100%')
    .padding(16)
    .backgroundColor(ThemeAwareHelper.getTestManagementThemedColor('panel_background', this.themeState.currentTheme))
    .borderRadius(12)
    .border({ width: 1, color: ThemeAwareHelper.getTestManagementThemedColor('panel_border', this.themeState.currentTheme) })
  }
}

export { HelloWorldPage }