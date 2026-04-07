import { ThemeType } from '../../Framework/Managers/ThemeManager';
import { SettingsPageSurfaceManager, SettingsPageSurfaceStyle } from './SettingsPageSurfaceManager';

export class SettingsPanelSurfaceHelper {
  private static getSurfaceStyle(theme: ThemeType): SettingsPageSurfaceStyle {
    return SettingsPageSurfaceManager.getManagementContentSurfaceStyle(theme);
  }

  static getBackground(theme: ThemeType): ResourceColor {
    return SettingsPanelSurfaceHelper.getSurfaceStyle(theme).backgroundColor;
  }

  static getBlurStyle(theme: ThemeType): BlurStyle | undefined {
    return SettingsPanelSurfaceHelper.getSurfaceStyle(theme).blurStyle;
  }

  static getBlurOptions(theme: ThemeType): BackgroundBlurStyleOptions {
    return SettingsPanelSurfaceHelper.getSurfaceStyle(theme).blurOptions;
  }

  static getBackgroundEffect(theme: ThemeType): BackgroundEffectOptions | undefined {
    return SettingsPanelSurfaceHelper.getSurfaceStyle(theme).backgroundEffect;
  }

  static getRadius(theme: ThemeType): number {
    return SettingsPanelSurfaceHelper.getSurfaceStyle(theme).radius;
  }

  static getBorderColor(theme: ThemeType): ResourceColor {
    return SettingsPanelSurfaceHelper.getSurfaceStyle(theme).borderColor;
  }

  static getBorderWidth(theme: ThemeType): number {
    return SettingsPanelSurfaceHelper.getSurfaceStyle(theme).borderWidth;
  }

  static getShadowColor(theme: ThemeType): string {
    return SettingsPanelSurfaceHelper.getSurfaceStyle(theme).shadowColor;
  }

  static getSurfaceGradient(theme: ThemeType): LinearGradient {
    return SettingsPanelSurfaceHelper.getSurfaceStyle(theme).surfaceGradient;
  }
}
