import { GlassEffectContext, GlassEffectOptions, ThemeManager, ThemeType } from '../Managers/ThemeManager';
import { ThemeAwareHelper, ThemeAwareState } from './ThemeAware';

export class DialogSurfaceStyleHelper {
  private static readonly themeManager: ThemeManager = ThemeManager.getInstance();

  private static getPopupEffectOptions(): GlassEffectOptions {
    return DialogSurfaceStyleHelper.themeManager.getGlassEffectOptions(GlassEffectContext.POPUP);
  }

  static getPopupCardBackground(themeState: ThemeAwareState): ResourceColor {
    const popupEffect: GlassEffectOptions = DialogSurfaceStyleHelper.getPopupEffectOptions();
    if (popupEffect.blurStyle === BlurStyle.NONE) {
      return ThemeAwareHelper.getTestManagementThemedColor('panel_background', themeState.currentTheme);
    }
    return themeState.currentTheme === ThemeType.DARK
      ? 'rgba(13, 17, 23, 0.88)'
      : 'rgba(255, 255, 255, 0.94)';
  }

  static getPopupCardBorderColor(themeState: ThemeAwareState): ResourceColor {
    const popupEffect: GlassEffectOptions = DialogSurfaceStyleHelper.getPopupEffectOptions();
    if (popupEffect.blurStyle === BlurStyle.NONE) {
      return ThemeAwareHelper.getTestManagementThemedColor('panel_border', themeState.currentTheme);
    }
    if (popupEffect.borderColor && popupEffect.borderColor.length > 0) {
      return popupEffect.borderColor;
    }
    return themeState.currentTheme === ThemeType.DARK
      ? 'rgba(255, 255, 255, 0.12)'
      : 'rgba(15, 23, 42, 0.08)';
  }

  static getPopupCardBlurStyle(): BlurStyle {
    return DialogSurfaceStyleHelper.getPopupEffectOptions().blurStyle;
  }

  static getPopupCardBlurOptions(): BackgroundBlurStyleOptions {
    const popupEffect: GlassEffectOptions = DialogSurfaceStyleHelper.getPopupEffectOptions();
    return popupEffect.blurOptions || {
      colorMode: ThemeColorMode.SYSTEM,
      adaptiveColor: AdaptiveColor.DEFAULT,
      scale: 0,
      policy: BlurStyleActivePolicy.ALWAYS_ACTIVE
    };
  }

  static getPopupCardShadowColor(themeState: ThemeAwareState): ResourceColor {
    const popupEffect: GlassEffectOptions = DialogSurfaceStyleHelper.getPopupEffectOptions();
    if (popupEffect.shadowColor && popupEffect.shadowColor.length > 0) {
      return popupEffect.shadowColor;
    }
    return ThemeAwareHelper.getTestManagementThemedColor('shadow_black', themeState.currentTheme);
  }
}
