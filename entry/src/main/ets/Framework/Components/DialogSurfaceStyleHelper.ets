import { GlassLevel, GlassStyleToken, ThemeManager, ThemeType } from '../Managers/ThemeManager';
import { ThemeAwareHelper, ThemeAwareState } from './ThemeAware';

export class DialogSurfaceStyleHelper {
  private static readonly themeManager: ThemeManager = ThemeManager.getInstance();

  private static getPopupCardToken(): GlassStyleToken {
    // Keep the same glass level as MainMenuPage's import-source dialog card.
    return DialogSurfaceStyleHelper.themeManager.getGlassToken(GlassLevel.FEATURED);
  }

  private static getPopupMaskToken(): GlassStyleToken {
    return DialogSurfaceStyleHelper.themeManager.getGlassToken(GlassLevel.SHEET);
  }

  static getPopupCardBackground(themeState: ThemeAwareState): ResourceColor {
    const token: GlassStyleToken = DialogSurfaceStyleHelper.getPopupCardToken();
    if (token.blurStyle === BlurStyle.NONE) {
      return ThemeAwareHelper.getTestManagementThemedColor('panel_background', themeState.currentTheme);
    }
    if (token.backgroundColor && token.backgroundColor.length > 0) {
      return token.backgroundColor;
    }
    return themeState.currentTheme === ThemeType.DARK ? 'rgba(13, 17, 23, 0.88)' : 'rgba(255, 255, 255, 0.94)';
  }

  static getPopupCardBorderColor(themeState: ThemeAwareState): ResourceColor {
    const token: GlassStyleToken = DialogSurfaceStyleHelper.getPopupCardToken();
    if (token.blurStyle === BlurStyle.NONE) {
      return ThemeAwareHelper.getTestManagementThemedColor('panel_border', themeState.currentTheme);
    }
    if (token.borderColor && token.borderColor.length > 0) {
      return token.borderColor;
    }
    return themeState.currentTheme === ThemeType.DARK
      ? 'rgba(255, 255, 255, 0.12)'
      : 'rgba(15, 23, 42, 0.08)';
  }

  static getPopupCardBlurStyle(): BlurStyle {
    return DialogSurfaceStyleHelper.getPopupCardToken().blurStyle;
  }

  static getPopupCardBlurOptions(): BackgroundBlurStyleOptions {
    const token: GlassStyleToken = DialogSurfaceStyleHelper.getPopupCardToken();
    return token.blurOptions || {
      colorMode: ThemeColorMode.SYSTEM,
      adaptiveColor: AdaptiveColor.DEFAULT,
      scale: 0,
      policy: BlurStyleActivePolicy.ALWAYS_ACTIVE
    };
  }

  static getPopupCardBackgroundEffect(): BackgroundEffectOptions | undefined {
    return DialogSurfaceStyleHelper.getPopupCardToken().backgroundEffect;
  }

  static getPopupCardRadius(): number {
    return DialogSurfaceStyleHelper.getPopupCardToken().radius;
  }

  static getPopupCardShadowColor(themeState: ThemeAwareState): ResourceColor {
    const token: GlassStyleToken = DialogSurfaceStyleHelper.getPopupCardToken();
    if (token.shadowColor && token.shadowColor.length > 0) {
      return token.shadowColor;
    }
    return ThemeAwareHelper.getTestManagementThemedColor('shadow_black', themeState.currentTheme);
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
