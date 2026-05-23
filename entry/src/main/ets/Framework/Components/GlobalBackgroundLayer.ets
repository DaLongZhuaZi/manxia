/**
 * 全局背景层组件
 * 用于显示自定义主题背景，并在其上叠加统一的氛围层和可读性遮罩
 */
import { logger } from '../../Utils/Logger';
import { CUSTOM_THEME_KEYS, GlassLevel, ThemeManager, ThemeType } from '../Managers/ThemeManager';
import { BuiltInThemeResources } from '../Theme/BuiltInThemeResources';

const TAG = 'GlobalBackgroundLayer';

export enum GlobalBackgroundLayerMode {
  DEFAULT = 'default',
  IMMERSIVE = 'immersive',
  READER = 'reader'
}

@Component
export struct GlobalBackgroundLayer {
  @StorageProp(CUSTOM_THEME_KEYS.BACKGROUND_IMAGE) backgroundImagePath: string = '';
  @StorageProp(CUSTOM_THEME_KEYS.IS_CUSTOM_THEME_ACTIVE) isCustomThemeActive: boolean = false;
  @StorageProp(CUSTOM_THEME_KEYS.CURRENT_THEME_ID) currentCustomThemeId: string = '';

  @Prop defaultBackgroundColor: ResourceStr = $r('app.color.background');
  @Prop mode: GlobalBackgroundLayerMode = GlobalBackgroundLayerMode.DEFAULT;
  @Prop enableScrimLayer: boolean = true;
  @Prop enableAtmosphereLayer: boolean = true;

  private themeManager: ThemeManager = ThemeManager.getInstance();

  build() {
    Stack() {
      this.buildBaseLayer()

      if (this.enableScrimLayer) {
        Column()
          .width('100%')
          .height('100%')
          .linearGradient({
            direction: GradientDirection.Bottom,
            colors: this.getScrimGradientColors()
          })
          .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.TOP, SafeAreaEdge.BOTTOM])
      }

      if (this.enableAtmosphereLayer) {
        Column()
          .width('100%')
          .height('100%')
          .backgroundColor(this.getAtmosphereBackgroundColor())
          .backgroundBlurStyle(this.getAtmosphereBlurStyle(), this.getAtmosphereBlurOptions())
          .opacity(this.getAtmosphereOpacity())
          .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.TOP, SafeAreaEdge.BOTTOM])
      }
    }
    .width('100%')
    .height('100%')
  }

  @Builder
  buildBaseLayer() {
    if (this.isCustomThemeActive && this.backgroundImagePath) {
      Image('file://' + this.backgroundImagePath)
        .width('100%')
        .height('100%')
        .objectFit(ImageFit.Cover)
        .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.TOP, SafeAreaEdge.BOTTOM])
        .onError((error: ImageError) => {
          logger.error(TAG, `背景图片加载失败: ${JSON.stringify(error)}`);
        })
    } else if (this.isCustomThemeActive) {
      Image(this.getFallbackMediaResource())
        .width('100%')
        .height('100%')
        .objectFit(ImageFit.Cover)
        .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.TOP, SafeAreaEdge.BOTTOM])
    } else {
      Column()
        .width('100%')
        .height('100%')
        .backgroundColor(this.defaultBackgroundColor)
        .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.TOP, SafeAreaEdge.BOTTOM])
    }
  }

  private getCurrentTheme(): ThemeType {
    return this.themeManager.getActualThemeSync();
  }

  private isDarkLikeTheme(): boolean {
    const theme = this.getCurrentTheme();
    return theme === ThemeType.DARK || theme === ThemeType.PRIVACY;
  }

  private getAtmosphereGlassLevel(): GlassLevel {
    const hasMediaBackground: boolean = this.isCustomThemeActive;
    switch (this.mode) {
      case GlobalBackgroundLayerMode.IMMERSIVE:
        return hasMediaBackground ? GlassLevel.NAVIGATION : GlassLevel.HERO;
      case GlobalBackgroundLayerMode.READER:
        return GlassLevel.CARD;
      case GlobalBackgroundLayerMode.DEFAULT:
      default:
        return hasMediaBackground ? GlassLevel.CARD : GlassLevel.NAVIGATION;
    }
  }

  private getAtmosphereBackgroundColor(): string {
    return this.themeManager.getGlassToken(this.getAtmosphereGlassLevel()).backgroundColor;
  }

  private getAtmosphereBlurStyle(): BlurStyle {
    return this.themeManager.getGlassToken(this.getAtmosphereGlassLevel()).blurStyle;
  }

  private getAtmosphereBlurOptions(): BackgroundBlurStyleOptions {
    return this.themeManager.getGlassToken(this.getAtmosphereGlassLevel()).blurOptions;
  }

  private getAtmosphereOpacity(): number {
    const hasMediaBackground: boolean = this.isCustomThemeActive;
    switch (this.mode) {
      case GlobalBackgroundLayerMode.IMMERSIVE:
        if (hasMediaBackground) {
          return this.isDarkLikeTheme() ? 0.34 : 0.26;
        }
        return this.isDarkLikeTheme() ? 0.54 : 0.44;
      case GlobalBackgroundLayerMode.READER:
        return this.isDarkLikeTheme() ? 0.34 : 0.26;
      case GlobalBackgroundLayerMode.DEFAULT:
      default:
        if (hasMediaBackground) {
          return this.isDarkLikeTheme() ? 0.2 : 0.14;
        }
        return this.isDarkLikeTheme() ? 0.38 : 0.3;
    }
  }

  private getScrimGradientColors(): [ResourceColor, number][] {
    if (this.isDarkLikeTheme()) {
      if (this.isCustomThemeActive) {
        switch (this.mode) {
          case GlobalBackgroundLayerMode.IMMERSIVE:
            return [
              ['rgba(6, 10, 16, 0.03)', 0.0] as [ResourceColor, number],
              ['rgba(6, 10, 16, 0.16)', 0.52] as [ResourceColor, number],
              ['rgba(6, 10, 16, 0.28)', 1.0] as [ResourceColor, number]
            ];
          case GlobalBackgroundLayerMode.READER:
            return [
              ['rgba(6, 10, 16, 0.08)', 0.0] as [ResourceColor, number],
              ['rgba(6, 10, 16, 0.18)', 1.0] as [ResourceColor, number]
            ];
          case GlobalBackgroundLayerMode.DEFAULT:
          default:
            return [
              ['rgba(8, 12, 20, 0.01)', 0.0] as [ResourceColor, number],
              ['rgba(8, 12, 20, 0.08)', 0.56] as [ResourceColor, number],
              ['rgba(8, 12, 20, 0.16)', 1.0] as [ResourceColor, number]
            ];
        }
      }

      switch (this.mode) {
        case GlobalBackgroundLayerMode.IMMERSIVE:
          return [
            ['rgba(6, 10, 16, 0.08)', 0.0] as [ResourceColor, number],
            ['rgba(6, 10, 16, 0.28)', 0.52] as [ResourceColor, number],
            ['rgba(6, 10, 16, 0.56)', 1.0] as [ResourceColor, number]
          ];
        case GlobalBackgroundLayerMode.READER:
          return [
            ['rgba(6, 10, 16, 0.18)', 0.0] as [ResourceColor, number],
            ['rgba(6, 10, 16, 0.26)', 1.0] as [ResourceColor, number]
          ];
        case GlobalBackgroundLayerMode.DEFAULT:
        default:
          return [
            ['rgba(8, 12, 20, 0.04)', 0.0] as [ResourceColor, number],
            ['rgba(8, 12, 20, 0.18)', 0.56] as [ResourceColor, number],
            ['rgba(8, 12, 20, 0.34)', 1.0] as [ResourceColor, number]
          ];
      }
    }

    if (this.isCustomThemeActive) {
      switch (this.mode) {
        case GlobalBackgroundLayerMode.IMMERSIVE:
          return [
            ['rgba(255, 255, 255, 0.0)', 0.0] as [ResourceColor, number],
            ['rgba(242, 246, 252, 0.1)', 0.5] as [ResourceColor, number],
            ['rgba(235, 242, 250, 0.18)', 1.0] as [ResourceColor, number]
          ];
        case GlobalBackgroundLayerMode.READER:
          return [
            ['rgba(255, 255, 255, 0.05)', 0.0] as [ResourceColor, number],
            ['rgba(246, 249, 252, 0.12)', 1.0] as [ResourceColor, number]
          ];
        case GlobalBackgroundLayerMode.DEFAULT:
        default:
          return [
            ['rgba(255, 255, 255, 0.0)', 0.0] as [ResourceColor, number],
            ['rgba(245, 248, 252, 0.05)', 0.56] as [ResourceColor, number],
            ['rgba(239, 244, 250, 0.1)', 1.0] as [ResourceColor, number]
          ];
      }
    }

    switch (this.mode) {
      case GlobalBackgroundLayerMode.IMMERSIVE:
        return [
          ['rgba(255, 255, 255, 0.02)', 0.0] as [ResourceColor, number],
          ['rgba(242, 246, 252, 0.18)', 0.5] as [ResourceColor, number],
          ['rgba(235, 242, 250, 0.34)', 1.0] as [ResourceColor, number]
        ];
      case GlobalBackgroundLayerMode.READER:
        return [
          ['rgba(255, 255, 255, 0.12)', 0.0] as [ResourceColor, number],
          ['rgba(246, 249, 252, 0.2)', 1.0] as [ResourceColor, number]
        ];
      case GlobalBackgroundLayerMode.DEFAULT:
      default:
        return [
          ['rgba(255, 255, 255, 0.02)', 0.0] as [ResourceColor, number],
          ['rgba(245, 248, 252, 0.14)', 0.56] as [ResourceColor, number],
          ['rgba(239, 244, 250, 0.24)', 1.0] as [ResourceColor, number]
        ];
    }
  }

  private getFallbackMediaResource(): ResourceStr {
    return BuiltInThemeResources.resolveResource(this.currentCustomThemeId);
  }
}
