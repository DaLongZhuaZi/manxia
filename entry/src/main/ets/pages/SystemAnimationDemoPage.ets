/**
 * 系统动画展示页面
 * 展示系统动画效果，包括动画类型、曲线选择和参数控制
 */
// [核心修改] 1. 导入 HdsNavDestination 和相关类型
import { HdsNavDestination, HdsNavDestinationAttribute, ScrollEffectType } from '@kit.UIDesignKit';

import { AnimatedComponent } from '../Framework/Animation/AnimatedComponent';
import { AnimationType } from '../Framework/Animation/GlobalAnimationSystem';
import { logger } from 'manxia_core/src/main/ets/Utils/Logger';
import { PageLifecycleManager } from 'manxia_core/src/main/ets/Framework/Lifecycle/index';
import { uiContextManager } from '../Framework/Managers/UIContextManager';
import { LengthMetrics, window } from '@kit.ArkUI';
import { common } from '@kit.AbilityKit';
import { ThemeManager, ThemeType } from '../Framework/Managers/ThemeManager';
import { ThemeToggle } from '../Framework/Components/ThemeToggle';
import { ThemeAwareState, ThemeAwareHelper } from '../Framework/Components/ThemeAware';


interface GeneratedTypeLiteralInterface_1 {
  name: string;
  type: AnimationType;
}

interface GeneratedTypeLiteralInterface_2 {
  name: string;
  curve: Curve;
}

// 定义标题栏最小高度，用于内容占位
const TITLE_BAR_HEIGHT_MINI: number = 56;


@Component
struct SystemAnimationDemoPage {

  private scroller: Scroller = new Scroller();

  // [修复] 不再使用@Consume，创建一个本地状态变量
  @State pathStack: NavPathStack = new NavPathStack();
  @State titleAnimationDelay: number = 0;
  @State componentAnimationDelay: number = 200;
  @State buttonAnimationDelay: number = 400;
  
  // 主题状态
  @State themeState: ThemeAwareState = new ThemeAwareState();
  
  // 动画演示状态
  @State currentAnimationType: AnimationType = AnimationType.FADE_IN;
  @State isAnimationPlaying: boolean = false;
  @State animationDuration: number = 500;
  @State animationCurve: Curve = Curve.EaseInOut;
  @State selectedAnimationIndex: number = 0;
  
  // 动画类型列表
  private animationTypes: Array<GeneratedTypeLiteralInterface_1> = [
    { name: '淡入', type: AnimationType.FADE_IN },
    { name: '淡出', type: AnimationType.FADE_OUT },
    { name: '左滑入', type: AnimationType.SLIDE_IN_LEFT },
    { name: '右滑入', type: AnimationType.SLIDE_IN_RIGHT },
    { name: '上滑入', type: AnimationType.SLIDE_IN_UP },
    { name: '下滑入', type: AnimationType.SLIDE_IN_DOWN },
    { name: '缩放入', type: AnimationType.SCALE_IN },
    { name: '缩放出', type: AnimationType.SCALE_OUT },
    { name: '旋转入', type: AnimationType.ROTATE_IN },
    { name: '弹跳入', type: AnimationType.BOUNCE_IN },
    { name: '翻转X', type: AnimationType.FLIP_IN_X },
    { name: '翻转Y', type: AnimationType.FLIP_IN_Y }
  ];
  
  // 动画曲线列表
  private animationCurves: Array<GeneratedTypeLiteralInterface_2> = [
    { name: '线性', curve: Curve.Linear },
    { name: '缓入缓出', curve: Curve.EaseInOut },
    { name: '缓入', curve: Curve.EaseIn },
    { name: '缓出', curve: Curve.EaseOut },
    { name: '快速开始', curve: Curve.FastOutSlowIn },
    { name: '快速结束', curve: Curve.LinearOutSlowIn },
    { name: '弹性', curve: Curve.Smooth },
    { name: '摩擦', curve: Curve.Friction }
  ];

  private componentId: string = 'SystemAnimationDemoPage';

  onPageShow() {
    // [修复] 使用 onPageShow 替代 aboutToAppear
    try {
      const stack = AppStorage.get<NavPathStack>('GlobalNavStack');
      if (stack) {
        this.pathStack = stack;
      } else {
        logger.error('SystemAnimationDemoPage', '无法从 AppStorage 获取 GlobalNavStack!');
      }
    } catch (err) {
      logger.error('SystemAnimationDemoPage', 'AppStorage.get 异常', err);
    }
    
    // 初始化主题状态
    ThemeAwareHelper.initializeThemeAware(this.componentId, this.themeState, (newTheme: ThemeType) => {
      logger.info('SystemAnimationDemoPage', `主题已切换到: ${newTheme}`);
    });
  }

  onReady() {
    // 初始化主题状态
    ThemeAwareHelper.initializeThemeAware(this.componentId, this.themeState, (newTheme: ThemeType) => {
      logger.info('SystemAnimationDemoPage', `主题已切换到: ${newTheme}`);
    });
  }

  private lifecycle = new PageLifecycleManager('SystemAnimationDemoPage', { enableDebug: true });

  aboutToDisappear() {
    this.lifecycle.destroy();
    // 清理主题状态
    ThemeAwareHelper.cleanupThemeAware(this.componentId);
  }

  /**
   * 构建页面标题
   */
  @Builder
  buildTitle(): void {
    Column() {
      Text('系统动画展示')
        .fontSize(28)
        .fontWeight(FontWeight.Bold)
        .fontColor(ThemeAwareHelper.getTestManagementThemedColor('button_text_primary', this.themeState.currentTheme))
        .textAlign(TextAlign.Center)
        .margin({ bottom: 8 })
      
      Text('体验所有系统动画效果')
        .fontSize(16)
        .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_muted', this.themeState.currentTheme))
        .textAlign(TextAlign.Center)
    }
    .width('100%')
    .padding({ left: 20, right: 20 })
  }

  /**
   * 构建动画控制面板
   */
  @Builder
  buildAnimationControls(): void {
    Column({ space: 16 }) {
      // 动画类型选择
      Column({ space: 8 }) {
        Text('动画类型')
          .fontSize(18)
          .fontWeight(FontWeight.Medium)
          .fontColor(ThemeAwareHelper.getTestManagementThemedColor('button_text_primary', this.themeState.currentTheme))
          .alignSelf(ItemAlign.Start)
        
        Grid() {
          ForEach(this.animationTypes, (item: GeneratedTypeLiteralInterface_1, index: number) => {
            GridItem() {
              Button(item.name)
                .fontSize(14)
                .fontColor(this.selectedAnimationIndex === index ? ThemeAwareHelper.getTestManagementThemedColor('button_text_secondary', this.themeState.currentTheme) : ThemeAwareHelper.getTestManagementThemedColor('button_text_primary', this.themeState.currentTheme))
                .backgroundColor(this.selectedAnimationIndex === index ? ThemeAwareHelper.getTestManagementThemedColor('accent_green', this.themeState.currentTheme) : ThemeAwareHelper.getTestManagementThemedColor('button_inactive', this.themeState.currentTheme))
                .borderRadius(8)
                .width('100%')
                .height(40)
                .onClick(() => {
                  this.selectedAnimationIndex = index;
                  this.currentAnimationType = item.type;
                })
            }
          })
        }
        .columnsTemplate('1fr 1fr 1fr')
        .rowsGap(8)
        .columnsGap(8)
        .width('100%')
      }
      
      // 动画参数控制
      Column({ space: 12 }) {
        Text('动画参数')
          .fontSize(18)
          .fontWeight(FontWeight.Medium)
          .fontColor(ThemeAwareHelper.getTestManagementThemedColor('button_text_primary', this.themeState.currentTheme))
          .alignSelf(ItemAlign.Start)
        
        // 持续时间
        Row() {
          Text('持续时间: ')
            .fontSize(14)
            .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_muted', this.themeState.currentTheme))
          Text(`${this.animationDuration}ms`)
            .fontSize(14)
            .fontColor(ThemeAwareHelper.getTestManagementThemedColor('accent_green', this.themeState.currentTheme))
            .fontWeight(FontWeight.Medium)
        }
        .width('100%')
        .justifyContent(FlexAlign.SpaceBetween)
        
        Slider({
          value: this.animationDuration,
          min: 100,
          max: 2000,
          step: 100
        })
          .trackColor(ThemeAwareHelper.getTestManagementThemedColor('button_inactive', this.themeState.currentTheme))
          .selectedColor(ThemeAwareHelper.getTestManagementThemedColor('accent_green', this.themeState.currentTheme))
          .blockColor(ThemeAwareHelper.getTestManagementThemedColor('button_text_primary', this.themeState.currentTheme))
          .onChange((value: number) => {
            this.animationDuration = value;
          })
        
        // 动画曲线选择
        Row() {
          Text('动画曲线: ')
            .fontSize(14)
            .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_muted', this.themeState.currentTheme))
          Text(this.animationCurves.find(item => item.curve === this.animationCurve)?.name || '缓入缓出')
            .fontSize(14)
            .fontColor(ThemeAwareHelper.getTestManagementThemedColor('accent_green', this.themeState.currentTheme))
            .fontWeight(FontWeight.Medium)
        }
        .width('100%')
        .justifyContent(FlexAlign.SpaceBetween)
        
        Grid() {
          ForEach(this.animationCurves, (item: GeneratedTypeLiteralInterface_2, index: number) => {
            GridItem() {
              Button(item.name)
                .fontSize(12)
                .fontColor(this.animationCurve === item.curve ? ThemeAwareHelper.getTestManagementThemedColor('button_text_secondary', this.themeState.currentTheme) : ThemeAwareHelper.getTestManagementThemedColor('button_text_primary', this.themeState.currentTheme))
                .backgroundColor(this.animationCurve === item.curve ? ThemeAwareHelper.getTestManagementThemedColor('accent_green', this.themeState.currentTheme) : ThemeAwareHelper.getTestManagementThemedColor('button_inactive', this.themeState.currentTheme))
                .borderRadius(6)
                .width('100%')
                .height(32)
                .onClick(() => {
                  this.animationCurve = item.curve;
                })
            }
          })
        }
        .columnsTemplate('1fr 1fr 1fr 1fr')
        .rowsGap(6)
        .columnsGap(6)
        .width('100%')
      }
    }
    .width('100%')
    .padding(16)
    .backgroundColor(ThemeAwareHelper.getTestManagementThemedColor('panel_background', this.themeState.currentTheme))
    .borderRadius(12)
    .border({ width: 1, color: ThemeAwareHelper.getTestManagementThemedColor('panel_border', this.themeState.currentTheme) })
  }

  /**
   * 构建动画演示区域
   */
  @Builder
  buildAnimationDemo(): void {
    Column({ space: 16 }) {
      Text('动画演示区域')
        .fontSize(18)
        .fontWeight(FontWeight.Medium)
        .fontColor(ThemeAwareHelper.getTestManagementThemedColor('button_text_primary', this.themeState.currentTheme))
        .alignSelf(ItemAlign.Start)
      
      // 演示容器
      Column() {
        if (this.isAnimationPlaying) {
          AnimatedComponent({
            animationType: this.currentAnimationType,
            duration: this.animationDuration,
            delay: 0,
            curve: this.animationCurve,
            autoPlay: true,
            content: () => this.buildDemoElement()
          })
        } else {
          this.buildDemoElement()
        }
      }
      .width('100%')
      .height(200)
      .backgroundColor(ThemeAwareHelper.getTestManagementThemedColor('background_dark', this.themeState.currentTheme))
      .borderRadius(12)
      .border({ width: 1, color: ThemeAwareHelper.getTestManagementThemedColor('panel_border', this.themeState.currentTheme) })
      .justifyContent(FlexAlign.Center)
      .alignItems(HorizontalAlign.Center)
      
      // 播放控制按钮
      Row({ space: 12 }) {
        Button('播放动画')
          .fontSize(16)
          .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_black', this.themeState.currentTheme))
          .backgroundColor(ThemeAwareHelper.getTestManagementThemedColor('accent_green', this.themeState.currentTheme))
          .borderRadius(8)
          .width(120)
          .height(40)
          .onClick(() => this.playAnimation())
        
        Button('重置')
          .fontSize(16)
          .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_white', this.themeState.currentTheme))
          .backgroundColor(ThemeAwareHelper.getTestManagementThemedColor('button_inactive', this.themeState.currentTheme))
          .borderRadius(8)
          .width(80)
          .height(40)
          .onClick(() => this.resetAnimation())
      }
      .width('100%')
      .justifyContent(FlexAlign.Center)
    }
    .width('100%')
    .padding(20)
    .backgroundColor(ThemeAwareHelper.getTestManagementThemedColor('panel_background', this.themeState.currentTheme))
    .borderRadius(12)
    .border({ width: 1, color: ThemeAwareHelper.getTestManagementThemedColor('panel_border', this.themeState.currentTheme) })
  }

  /**
   * 构建演示元素
   */
  @Builder
  buildDemoElement(): void {
    Column({ space: 8 }) {
      Circle({ width: 60, height: 60 })
        .fill(ThemeAwareHelper.getTestManagementThemedColor('accent_green', this.themeState.currentTheme))
      
      Text('动画元素')
        .fontSize(16)
        .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_white', this.themeState.currentTheme))
        .fontWeight(FontWeight.Medium)
      
      Text(this.animationTypes[this.selectedAnimationIndex]?.name || '淡入')
        .fontSize(12)
        .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_muted', this.themeState.currentTheme))
    }
  }

  /**
   * 构建操作按钮
   */
  @Builder
  buildActionButtons(): void {
    Row({ space: 16 }) {
      Button('返回')
        .fontSize(16)
        .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_white', this.themeState.currentTheme))
        .backgroundColor(ThemeAwareHelper.getTestManagementThemedColor('button_inactive', this.themeState.currentTheme))
        .borderRadius(8)
        .width(100)
        .height(40)
        .onClick(() => this.goBack())
      
      Button('系统资源')
        .fontSize(16)
        .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_black', this.themeState.currentTheme))
        .backgroundColor(ThemeAwareHelper.getTestManagementThemedColor('accent_green', this.themeState.currentTheme))
        .borderRadius(8)
        .width(120)
        .height(40)
        .onClick(() => this.navigateToSystemResource())
    }
    .width('100%')
    .justifyContent(FlexAlign.SpaceEvenly)
    .padding({ left: 20, right: 20 })
  }

  /**
   * 播放动画
   */
  private playAnimation(): void {
    this.isAnimationPlaying = false;
    setTimeout(() => {
      this.isAnimationPlaying = true;
    }, 50);
  }

  /**
   * 重置动画
   */
  private resetAnimation(): void {
    this.isAnimationPlaying = false;
    this.selectedAnimationIndex = 0;
    this.currentAnimationType = AnimationType.FADE_IN;
    this.animationDuration = 500;
    this.animationCurve = Curve.EaseInOut;
  }

  /**
   * 返回上一页
   */
  private async goBack(): Promise<void> {
    logger.info('SystemAnimationDemoPage', '用户点击返回按钮');
    try {
      this.pathStack.pop();
    } catch (error) {
      logger.error('SystemAnimationDemoPage', `返回失败，尝试跳转到测试管理页面: ${error}`);
      try {
        this.pathStack.pushPath({
          name: 'TestManagementPage'
        });
      } catch (fallbackError) {
        logger.error('SystemAnimationDemoPage', `跳转到测试管理页面失败: ${fallbackError}`);
      }
    }
  }

  /**
   * 导航到系统资源页面
   */
  private async navigateToSystemResource(): Promise<void> {
    logger.info('SystemAnimationDemoPage', '导航到系统资源页面');
    try {
      this.pathStack.pushPath({
        name: 'SystemResourceDemoPage'
      });
    } catch (error) {
      logger.error('SystemAnimationDemoPage', `导航失败: ${error}`);
    }
  }

  build() {
    // [核心修改] 2. 使用 HdsNavDestination 作为根组件
    HdsNavDestination() {
      // [核心修改] 3. 使用 Stack 分离背景和内容
      Stack() {
        // 背景层
        Column()
          .width('100%')
          .height('100%')
          .backgroundColor(ThemeAwareHelper.getTestManagementThemedColor('background_dark', this.themeState.currentTheme))
          .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.TOP, SafeAreaEdge.BOTTOM])
        
        // 内容层
        Scroll(this.scroller) {
          Column({ space: 24 }) {
            // [核心修改] 4. 添加 Blank 占位符
            Blank().height(TITLE_BAR_HEIGHT_MINI)

            // 动画控制面板
            this.buildAnimationControls()

            // 动画演示区域
            this.buildAnimationDemo()
          }
          .width('100%')
          .padding({ left: 20, right: 20, bottom: 40 })
        }
        .edgeEffect(EdgeEffect.Spring)
        .scrollBar(BarState.Auto)
      }
    }
    // [核心修改] 5. 配置 titleBar，实现滚动模糊效果
    .titleBar({
      padding: {
        start: LengthMetrics.vp(2),
        end: LengthMetrics.vp(2)
      },
      style: {
        scrollEffectOpts: {
          enableScrollEffect: true,
          scrollEffectType: ScrollEffectType.COMMON_BLUR,
          blurEffectiveStartOffset: LengthMetrics.vp(0),
          blurEffectiveEndOffset: LengthMetrics.vp(20)
        },
        originalStyle: {
          backgroundStyle: {
            backgroundColor: ThemeAwareHelper.getTestManagementThemedColor('background', this.themeState.currentTheme),
          },
          contentStyle: {
            titleStyle: { 
              mainTitleColor: ThemeAwareHelper.getTestManagementThemedColor('text_primary', this.themeState.currentTheme),
              subTitleColor: ThemeAwareHelper.getTestManagementThemedColor('text_secondary', this.themeState.currentTheme)
            },
            menuStyle: { 
              backgroundColor: ThemeAwareHelper.getTestManagementThemedColor('comp_background_tertiary', this.themeState.currentTheme), 
              iconColor: ThemeAwareHelper.getTestManagementThemedColor('icon_primary', this.themeState.currentTheme) 
            },
            backIconStyle: { 
              backgroundColor: ThemeAwareHelper.getTestManagementThemedColor('comp_background_tertiary', this.themeState.currentTheme), 
              iconColor: ThemeAwareHelper.getTestManagementThemedColor('icon_primary', this.themeState.currentTheme) 
            }
          }
        },
        scrollEffectStyle: {
          backgroundStyle: {
            backgroundColor: this.themeState.currentTheme === ThemeType.LIGHT ? 
              '#E6FFFFFF' : '#E6000000',
          },
          contentStyle: {
            titleStyle: { 
              mainTitleColor: ThemeAwareHelper.getTestManagementThemedColor('text_primary', this.themeState.currentTheme),
              subTitleColor: ThemeAwareHelper.getTestManagementThemedColor('text_secondary', this.themeState.currentTheme)
            },
            menuStyle: { 
              backgroundColor: ThemeAwareHelper.getTestManagementThemedColor('comp_background_tertiary', this.themeState.currentTheme), 
              iconColor: ThemeAwareHelper.getTestManagementThemedColor('icon_primary', this.themeState.currentTheme) 
            },
            backIconStyle: { 
              backgroundColor: ThemeAwareHelper.getTestManagementThemedColor('comp_background_tertiary', this.themeState.currentTheme), 
              iconColor: ThemeAwareHelper.getTestManagementThemedColor('icon_primary', this.themeState.currentTheme) 
            }
          }
        }
      },
      content: {
        title: {
          mainTitle: "🎬 系统动画演示",
        }
      }
    })
    .onReady((context: NavDestinationContext) => {
      logger.info('SystemAnimationDemoPage', 'HdsNavDestination.onReady 已触发');
      this.pathStack = context.pathStack;
      this.onPageShow();
    })
    // [核心修改] 7. HdsNavDestination 自身背景设为透明
    .backgroundColor(Color.Transparent)
  }
}

export { SystemAnimationDemoPage };
