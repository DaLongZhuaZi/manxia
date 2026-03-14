// 文件路径: entry/src/main/ets/pages/SupportersPage.ets
/**
 * 支持者鸣谢页面
 * 展示支持本项目的用户列表，带有流星背景动画效果
 */

import { HdsNavDestination, HdsNavDestinationAttribute, ScrollEffectType } from '@kit.UIDesignKit';
import { ThemeAwareState, ThemeAwareHelper } from '../Framework/Components/ThemeAware';
import { ThemeManager, ThemeType } from '../Framework/Managers/ThemeManager';
import { FontAwareHelper, FontAwareState } from '../Framework/Components/FontAware';
import { logger } from '../Utils/Logger';
import { PageLifecycleManager } from '../Framework/Lifecycle';
import { WindowManager, DisplayMode } from '../Utils/WindowManager';

const TAG = 'SupportersPage';
const TITLE_BAR_HEIGHT_MINI: number = 56;

/**
 * 流星粒子数据
 */
interface MeteorParticle {
  x: number;
  y: number;
  length: number;
  speed: number;
  opacity: number;
  angle: number;
  width: number;
}

/**
 * 支持者信息
 */
interface SupporterInfo {
  name: string;
  level?: string;  // 支持等级（可选）
}

@Component
export struct SupportersPage {
  @State pathStack: NavPathStack = new NavPathStack();

  // 主题相关状态
  @State themeState: ThemeAwareState = new ThemeAwareState();
  private themeManager: ThemeManager = ThemeManager.getInstance();
  private componentId: string = 'SupportersPage';

  // 字体相关状态
  @State fontState: FontAwareState = new FontAwareState();
  @StorageLink('appFontFamily') appFontFamily: string = 'HarmonyOS Sans';
  @StorageProp('statusBarHeight') statusBarHeight: number = 0;
  @StorageProp('navigationBarHeight') navigationBarHeight: number = 0;

  // 流星动画相关
  private canvasSettings: RenderingContextSettings = new RenderingContextSettings(true);
  private canvasRenderingContext: CanvasRenderingContext2D = new CanvasRenderingContext2D(this.canvasSettings);
  @State private canvasWidth: number = 400;
  @State private canvasHeight: number = 800;
  private meteors: MeteorParticle[] = [];
  private timerId: number = 0;  // 使用 setInterval 的定时器 ID
  private isAnimating: boolean = false;
  private readonly FRAME_INTERVAL: number = 16;  // 约60fps (1000ms / 60 ≈ 16ms)

  // ==================== 支持者名单 ====================
  // 在此处添加支持者，格式：{ name: '用户名', level: '等级（可选）' }
  private supporters: SupporterInfo[] = [
    { name: '爱发电用户_Xvtc' },
    { name: 'Ring' },
    { name: '据我所知' },
    { name: 'kironal' }
    // 示例：
    // { name: '张三', level: '金牌支持者' },
    // { name: '李四', level: '银牌支持者' },
    // { name: '王五' },
  ];
  // ==================================================

  aboutToAppear(): void {
    logger.lifecycle(TAG, 'aboutToAppear');
    WindowManager.setDisplayMode(DisplayMode.DEFAULT, this.getUIContext());

    // 初始化主题状态
    ThemeAwareHelper.initializeThemeAware(
      this.componentId,
      this.themeState,
      (newTheme: ThemeType) => {
        logger.info(TAG, `主题已切换到: ${newTheme}`);
      },
      (newState: ThemeAwareState) => {
        this.themeState = newState;
      }
    );

    // 初始化字体感知
    FontAwareHelper.initializeFontAware(
      this.componentId,
      this.fontState,
      (newState: FontAwareState) => {
        this.fontState = newState;
      }
    );
  }

  private lifecycle = new PageLifecycleManager('SupportersPage', { enableDebug: true });

  aboutToDisappear(): void {
    logger.lifecycle(TAG, 'aboutToDisappear');
    WindowManager.setDisplayMode(DisplayMode.DEFAULT, this.getUIContext());
    this.lifecycle.destroy();
    this.stopAnimation();
    ThemeAwareHelper.cleanupThemeAware(this.componentId);
    FontAwareHelper.cleanupFontAware(this.componentId);
  }

  /**
   * 初始化流星粒子
   */
  private initMeteors(): void {
    this.meteors = [];
    const meteorCount = 15;

    for (let i = 0; i < meteorCount; i++) {
      this.meteors.push(this.createMeteor());
    }
  }

  /**
   * 创建单个流星粒子
   */
  private createMeteor(): MeteorParticle {
    return {
      x: Math.random() * this.canvasWidth * 1.5,
      y: Math.random() * this.canvasHeight * 0.3 - this.canvasHeight * 0.3,
      length: 80 + Math.random() * 120,
      speed: 3 + Math.random() * 5,
      opacity: 0.3 + Math.random() * 0.7,
      angle: Math.PI / 4 + (Math.random() - 0.5) * 0.2,  // 约45度角，带少量随机偏移
      width: 1 + Math.random() * 2
    };
  }

  /**
   * 重置流星到初始位置
   */
  private resetMeteor(meteor: MeteorParticle): void {
    meteor.x = Math.random() * this.canvasWidth * 1.5;
    meteor.y = -meteor.length - Math.random() * 100;
    meteor.opacity = 0.3 + Math.random() * 0.7;
    meteor.speed = 3 + Math.random() * 5;
  }

  /**
   * 开始流星动画
   */
  private startAnimation(): void {
    if (this.isAnimating || !this.canvasRenderingContext) {
      return;
    }

    this.isAnimating = true;
    this.initMeteors();
    
    // 使用 setInterval 实现动画循环
    this.timerId = setInterval(() => {
      this.drawFrame();
    }, this.FRAME_INTERVAL);
  }

  /**
   * 停止流星动画
   */
  private stopAnimation(): void {
    this.isAnimating = false;
    if (this.timerId) {
      clearInterval(this.timerId);
      this.timerId = 0;
    }
  }

  /**
   * 动画帧绘制
   */
  private drawFrame(): void {
    if (!this.isAnimating || !this.canvasRenderingContext) {
      return;
    }

    const ctx = this.canvasRenderingContext;

    // 清空画布（使用半透明黑色实现拖尾效果）
    ctx.fillStyle = 'rgba(10, 10, 20, 0.15)';
    ctx.fillRect(0, 0, this.canvasWidth, this.canvasHeight);

    // 绘制每颗流星
    for (const meteor of this.meteors) {
      this.drawMeteor(ctx, meteor);
      this.updateMeteor(meteor);
    }
  }

  /**
   * 绘制单颗流星
   */
  private drawMeteor(ctx: CanvasRenderingContext2D, meteor: MeteorParticle): void {
    const endX = meteor.x - Math.cos(meteor.angle) * meteor.length;
    const endY = meteor.y + Math.sin(meteor.angle) * meteor.length;

    // 创建渐变效果
    const gradient = ctx.createLinearGradient(meteor.x, meteor.y, endX, endY);
    gradient.addColorStop(0, `rgba(255, 255, 255, ${meteor.opacity})`);
    gradient.addColorStop(0.3, `rgba(200, 220, 255, ${meteor.opacity * 0.6})`);
    gradient.addColorStop(1, 'rgba(100, 150, 255, 0)');

    ctx.beginPath();
    ctx.moveTo(meteor.x, meteor.y);
    ctx.lineTo(endX, endY);
    ctx.strokeStyle = gradient;
    ctx.lineWidth = meteor.width;
    ctx.lineCap = 'round';
    ctx.stroke();

    // 绘制流星头部光晕
    const glowGradient = ctx.createRadialGradient(
      meteor.x, meteor.y, 0,
      meteor.x, meteor.y, 4
    );
    glowGradient.addColorStop(0, `rgba(255, 255, 255, ${meteor.opacity})`);
    glowGradient.addColorStop(1, 'rgba(255, 255, 255, 0)');

    ctx.beginPath();
    ctx.arc(meteor.x, meteor.y, 4, 0, Math.PI * 2);
    ctx.fillStyle = glowGradient;
    ctx.fill();
  }

  /**
   * 更新流星位置
   */
  private updateMeteor(meteor: MeteorParticle): void {
    meteor.x -= Math.cos(meteor.angle) * meteor.speed;
    meteor.y += Math.sin(meteor.angle) * meteor.speed;

    // 如果流星飞出屏幕，重置位置
    if (meteor.y > this.canvasHeight + meteor.length || meteor.x < -meteor.length) {
      this.resetMeteor(meteor);
    }
  }

  /**
   * 返回上一页
   */
  private goBack(): void {
    try {
      this.pathStack.pop();
    } catch (error) {
      logger.error(TAG, `返回失败: ${String(error)}`);
    }
  }

  /**
   * 构建支持者卡片
   */
  @Builder
  buildSupporterCard(supporter: SupporterInfo, index: number) {
    Row({ space: 12 }) {
      // 头像占位（使用首字母）
      Column() {
        Text(supporter.name.substring(0, 1))
          .fontSize(18)
          .fontWeight(FontWeight.Bold)
          .fontFamily(this.appFontFamily)
          .fontColor(Color.White)
      }
      .width(44)
      .height(44)
      .borderRadius(22)
      .backgroundColor(`rgba(${100 + (index * 30) % 155}, ${80 + (index * 50) % 175}, 255, 0.8)`)
      .justifyContent(FlexAlign.Center)

      // 名称和等级
      Column({ space: 4 }) {
        Text(supporter.name)
          .fontSize(16)
          .fontWeight(FontWeight.Medium)
          .fontFamily(this.appFontFamily)
          .fontColor(Color.White)

        if (supporter.level) {
          Text(supporter.level)
            .fontSize(12)
            .fontFamily(this.appFontFamily)
            .fontColor('rgba(255, 255, 255, 0.7)')
        }
      }
      .alignItems(HorizontalAlign.Start)
      .layoutWeight(1)

      // 感谢图标
      SymbolGlyph($r('sys.symbol.heart_fill'))
        .fontSize(20)
        .fontColor(['#FF6B9D'])
    }
    .width('100%')
    .padding({ left: 16, right: 16, top: 12, bottom: 12 })
    .backgroundColor('rgba(255, 255, 255, 0.1)')
    .borderRadius(12)
    .backdropBlur(20)
  }

  /**
   * 构建空状态
   */
  @Builder
  buildEmptyState() {
    Column({ space: 16 }) {
      SymbolGlyph($r('sys.symbol.heart'))
        .fontSize(64)
        .fontColor(['rgba(255, 255, 255, 0.5)'])

      Text('暂无支持者')
        .fontSize(18)
        .fontWeight(FontWeight.Medium)
        .fontFamily(this.appFontFamily)
        .fontColor('rgba(255, 255, 255, 0.7)')

      Text('成为第一个支持者吧！')
        .fontSize(14)
        .fontFamily(this.appFontFamily)
        .fontColor('rgba(255, 255, 255, 0.5)')
    }
    .width('100%')
    .padding(40)
    .justifyContent(FlexAlign.Center)
  }

  build() {
    HdsNavDestination() {
      Stack() {
        // 背景层 - 深色渐变
        Column()
          .width('100%')
          .height('100%')
          .linearGradient({
            angle: 135,
            colors: [
              ['#0a0a14', 0],
              ['#1a1a2e', 0.5],
              ['#16213e', 1]
            ]
          })
          .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.TOP, SafeAreaEdge.BOTTOM])

        // 流星动画层
        Canvas(this.canvasRenderingContext)
          .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.TOP, SafeAreaEdge.BOTTOM])
          .width('100%')
          .height('100%')
          .onReady(() => {
            // 初始填充背景
            if (this.canvasRenderingContext) {
              this.canvasRenderingContext.fillStyle = 'rgba(10, 10, 20, 1)';
              this.canvasRenderingContext.fillRect(0, 0, this.canvasWidth, this.canvasHeight);
            }
            this.startAnimation();
          })
          .onAreaChange((oldArea: Area, newArea: Area) => {
            this.canvasWidth = newArea.width as number;
            this.canvasHeight = newArea.height as number;
          })

        // 内容层
        Column() {
          // 顶部区域 - 返回按钮和标题
          /*
          Row() {
            Button() {
              SymbolGlyph($r('sys.symbol.arrow_left'))
                .fontSize(24)
                .fontColor([Color.White])
            }
            .width(44)
            .height(44)
            .backgroundColor('rgba(255, 255, 255, 0.1)')
            .borderRadius(22)
            .onClick(() => {
              this.goBack();
            })

            Blank()
          }
          .width('100%')
          .padding({ left: 16, right: 16, top: 16 })
          */

          Blank().height(TITLE_BAR_HEIGHT_MINI)

          // 标题区域
          Column({ space: 8 }) {
            Text('支持者鸣谢')
              .fontSize(32)
              .fontWeight(FontWeight.Bold)
              .fontFamily(this.appFontFamily)
              .fontColor(Color.White)

            Text('感谢每一位支持漫匣的朋友')
              .fontSize(14)
              .fontFamily(this.appFontFamily)
              .fontColor('rgba(255, 255, 255, 0.6)')
          }
          .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.TOP, SafeAreaEdge.BOTTOM])
          .width('100%')
          .padding({ left: 20, right: 20, top: 20, bottom: 32 })
          .alignItems(HorizontalAlign.Start)

          // 支持者列表
          Scroll() {
            Column({ space: 12 }) {
              if (this.supporters.length > 0) {
                ForEach(this.supporters, (supporter: SupporterInfo, index: number) => {
                  this.buildSupporterCard(supporter, index)
                }, (supporter: SupporterInfo, index: number) => `${supporter.name}-${index}`)
              } else {
                this.buildEmptyState()
              }

              // 底部间距
              Blank().height(40)
            }
            .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.TOP, SafeAreaEdge.BOTTOM])
            .width('100%')
            .padding({ left: 20, right: 20 })
          }
          .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.TOP, SafeAreaEdge.BOTTOM])
          .layoutWeight(1)
          .scrollBar(BarState.Off)
          .edgeEffect(EdgeEffect.Spring)

          // 底部提示
          Column({ space: 8 }) {
            Row({ space: 8 }) {
              SymbolGlyph($r('sys.symbol.star_fill'))
                .fontSize(16)
                .fontColor(['rgba(255, 200, 100, 0.8)'])

              Text('支持我们')
                .fontSize(14)
                .fontFamily(this.appFontFamily)
                .fontColor('rgba(255, 255, 255, 0.7)')

              SymbolGlyph($r('sys.symbol.star_fill'))
                .fontSize(16)
                .fontColor(['rgba(255, 200, 100, 0.8)'])
            }
            .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.TOP, SafeAreaEdge.BOTTOM])

            Text('afdian.com/a/dalongzz')
              .fontSize(12)
              .fontFamily(this.appFontFamily)
              .fontColor('rgba(255, 255, 255, 0.5)')
          }
          .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.TOP, SafeAreaEdge.BOTTOM])
          .width('100%')
          .padding({ bottom: 24 })
          .alignItems(HorizontalAlign.Center)
        }
        .width('100%')
        .height('100%')
        .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.TOP, SafeAreaEdge.BOTTOM])
        .padding({ top: this.statusBarHeight })
      }
    }
    .hideTitleBar(true)
    /* .titleBar({
      style: {
        originalStyle: {
          backgroundStyle: {
            backgroundColor: ThemeAwareHelper.getTestManagementThemedColor('panel_background', this.themeState.currentTheme)
          },
          contentStyle: {
            titleStyle: {
              mainTitleColor: ThemeAwareHelper.getTestManagementThemedColor('text_primary', this.themeState.currentTheme)
            },
            backIconStyle: {
              backgroundColor: ThemeAwareHelper.getTestManagementThemedColor('comp_background_tertiary', this.themeState.currentTheme),
              iconColor: ThemeAwareHelper.getTestManagementThemedColor('icon_primary', this.themeState.currentTheme)
            }
          }
        }
      },
      content: {
        title: { mainTitle: '支持者鸣谢' }
      }
    }) */
    .backgroundColor(Color.Transparent)
    .onReady((context: NavDestinationContext) => {
      this.pathStack = context.pathStack;
    })
  }
}
