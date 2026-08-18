import { GlassLevel, GlassStyleToken, ThemeManager, ThemeType } from '../Managers/ThemeManager';
import { ThemeAwareState } from './ThemeAware';
import { SettingsPageSurfaceManager, SettingsPageSurfaceStyle } from '../../pages/settings/SettingsPageSurfaceManager';

export class DialogSurfaceStyleHelper {
  private static readonly themeManager: ThemeManager = ThemeManager.getInstance();

  private static getPopupCardSurface(theme: ThemeType): SettingsPageSurfaceStyle {
    return SettingsPageSurfaceManager.getFeaturedCardStyle(theme).surface;
  }

  private static getActualTheme(): ThemeType {
    return DialogSurfaceStyleHelper.themeManager.getActualThemeSync();
  }

  private static getPopupMaskToken(): GlassStyleToken {
    return DialogSurfaceStyleHelper.themeManager.getGlassToken(GlassLevel.SHEET);
  }

  static getPopupCardBackground(themeState: ThemeAwareState): ResourceColor {
    return DialogSurfaceStyleHelper.getPopupCardSurface(themeState.currentTheme).backgroundColor;
  }

  static getPopupCardGradient(themeState: ThemeAwareState): LinearGradient {
    return DialogSurfaceStyleHelper.getPopupCardSurface(themeState.currentTheme).surfaceGradient;
  }

  static getPopupCardBorderColor(themeState: ThemeAwareState): ResourceColor {
    return DialogSurfaceStyleHelper.getPopupCardSurface(themeState.currentTheme).borderColor;
  }

  static getPopupCardBorderWidth(themeState: ThemeAwareState): number {
    return DialogSurfaceStyleHelper.getPopupCardSurface(themeState.currentTheme).borderWidth;
  }

  static getPopupCardBlurStyle(): BlurStyle {
    return DialogSurfaceStyleHelper.getPopupCardSurface(DialogSurfaceStyleHelper.getActualTheme()).blurStyle || BlurStyle.NONE;
  }

  static getPopupCardBlurOptions(): BackgroundBlurStyleOptions {
    return DialogSurfaceStyleHelper.getPopupCardSurface(DialogSurfaceStyleHelper.getActualTheme()).blurOptions;
  }

  static getPopupCardBackgroundEffect(): BackgroundEffectOptions | undefined {
    return DialogSurfaceStyleHelper.getPopupCardSurface(DialogSurfaceStyleHelper.getActualTheme()).backgroundEffect;
  }

  static getPopupCardRadius(): number {
    return DialogSurfaceStyleHelper.getPopupCardSurface(DialogSurfaceStyleHelper.getActualTheme()).radius;
  }

  static getPopupCardShadowColor(themeState: ThemeAwareState): string {
    return DialogSurfaceStyleHelper.getPopupCardSurface(themeState.currentTheme).shadowColor;
  }

  static getPopupMaskColor(): ResourceColor {
    return DialogSurfaceStyleHelper.getPopupMaskToken().backgroundColorResource;
  }

  static getPopupMaskBlurStyle(): BlurStyle {
    return DialogSurfaceStyleHelper.getPopupMaskToken().blurStyle;
  }

  static getPopupMaskBlurOptions(): BackgroundBlurStyleOptions {
    const token: GlassStyleToken = DialogSurfaceStyleHelper.getPopupMaskToken();
    return token.blurOptions || {
      colorMode: ThemeColorMode.SYSTEM,
      adaptiveColor: AdaptiveColor.DEFAULT,
      scale: 0,
      policy: BlurStyleActivePolicy.ALWAYS_ACTIVE
    };
  }

  static getPopupMaskBackgroundEffect(): BackgroundEffectOptions | undefined {
    return DialogSurfaceStyleHelper.getPopupMaskToken().backgroundEffect;
  }
}
