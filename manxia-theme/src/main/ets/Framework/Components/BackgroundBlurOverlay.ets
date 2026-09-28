// 文件路径: entry/src/main/ets/Framework/Components/BackgroundBlurOverlay.ets
/**
 * 后台模糊遮罩组件
 * 当应用进入后台时显示，保护用户隐私
 * 支持自定义背景（纯色/图片）和图标（盾牌/应用logo）
 */

import { ThemeAwareHelper } from './ThemeAware';
import { ThemeManager, ThemeType } from '../Managers/ThemeManager';

// 背景类型枚举
export enum BackgroundBlurBgType {
  SOLID = 'solid',    // 纯色背景
  CUSTOM = 'custom'   // 自定义图片背景
}

// 图标类型枚举
export enum BackgroundBlurIconType {
  SHIELD = 'shield',  // 安全盾牌图标
  LOGO = 'logo'       // 应用Logo
}

@Component
export struct BackgroundBlurOverlay {
  // 是否显示遮罩
  @Prop @Watch('onVisibleChange') isVisible: boolean = false;
  // 背景类型
  @Prop bgType: string = BackgroundBlurBgType.SOLID;
  // 自定义背景图片路径
  @Prop customBgImage: string = '';
  // 图标类型
  @Prop iconType: string = BackgroundBlurIconType.SHIELD;
  // 当前主题
  @Prop currentTheme: ThemeType = ThemeType.LIGHT;
  
  // 动画状态
  @State private animatedOpacity: number = 0;
  @State private iconScale: number = 0.8;
  @State private shouldRender: boolean = false;

  // 获取背景颜色（根据主题）
  private getBackgroundColor(): ResourceColor {
    return ThemeAwareHelper.getTestManagementThemedColor('background_primary', this.currentTheme);
  }

  // 获取图标颜色（根据主题）
  private getIconColor(): ResourceColor {
    return ThemeAwareHelper.getTestManagementThemedColor('accent_blue', this.currentTheme);
  }

  // 监听isVisible变化，触发动画
  onVisibleChange(): void {
    if (this.isVisible) {
      // 后台快照抓取很快，进入后台时遮罩必须立即成为可见状态。
      this.shouldRender = true;
      this.animatedOpacity = 1;
      this.iconScale = 1.0;
    } else {
      // 退出动画：先播放淡出，再隐藏组件
      this.getUIContext().animateTo({
        duration: 200,
        curve: Curve.EaseIn,
        onFinish: () => {
          this.shouldRender = false;
        }
      }, () => {
        this.animatedOpacity = 0;
        this.iconScale = 0.8;
      });
    }
  }

  aboutToAppear(): void {
    // 初始化时如果已可见，直接显示
    if (this.isVisible) {
      this.shouldRender = true;
      this.animatedOpacity = 1;
      this.iconScale = 1.0;
    }
  }

  build() {
    if (this.shouldRender || this.isVisible) {
      Stack() {
        // 背景层 - 扩展到系统栏区域实现完全沉浸式
        Column()
          .width('100%')
          .height('100%')
          .backgroundColor(this.getBackgroundColor())
          .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.TOP, SafeAreaEdge.BOTTOM])

        // 高度模糊效果层 - 使用backgroundBlurStyle实现更强的模糊
        Column()
          .width('100%')
          .height('100%')
          .backgroundBlurStyle(BlurStyle.BACKGROUND_ULTRA_THICK, {
            colorMode: this.currentTheme === ThemeType.DARK ? ThemeColorMode.DARK : ThemeColorMode.LIGHT,
            adaptiveColor: AdaptiveColor.DEFAULT,
            scale: 1.0
          })
          .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.TOP, SafeAreaEdge.BOTTOM])

        // 中央图标（带缩放动画）
        Column() {
          if (this.iconType === BackgroundBlurIconType.LOGO) {
            // 应用Logo
            Image($r('app.media.foreground'))
              .width(120)
              .height(120)
              .objectFit(ImageFit.Contain)
              .scale({ x: this.iconScale, y: this.iconScale })
          } else {
            // 安全盾牌图标 - 使用lock图标代替shield
            SymbolGlyph($r('sys.symbol.lock_fill'))
              .fontSize(120)
              .fontColor([this.getIconColor()])
              .effectStrategy(SymbolEffectStrategy.NONE)
              .symbolEffect(new ScaleSymbolEffect(EffectScope.WHOLE, EffectDirection.UP), this.iconScale)
          }
        }
        .width('100%')
        .height('100%')
        .justifyContent(FlexAlign.Center)
        .alignItems(HorizontalAlign.Center)
        .scale({ x: this.iconScale, y: this.iconScale })
        .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.TOP, SafeAreaEdge.BOTTOM])
      }
      .width('100%')
      .height('100%')
      .opacity(this.animatedOpacity)
      .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.TOP, SafeAreaEdge.BOTTOM])
    }
  }
}
