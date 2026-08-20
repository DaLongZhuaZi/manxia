import { ThemeType } from 'manxia_theme/src/main/ets/Framework/Managers/ThemeManager';
import { ThemeAwareHelper } from 'manxia_theme/src/main/ets/Framework/Components/ThemeAware';
import { SettingsGlassStyleHelper } from './SettingsGlassStyleHelper';

export interface SettingsPageSurfaceStyle {
  backgroundColor: ResourceColor;
  blurStyle: BlurStyle | undefined;
  blurOptions: BackgroundBlurStyleOptions;
  backgroundEffect: BackgroundEffectOptions | undefined;
  radius: number;
  borderColor: ResourceColor;
  borderWidth: number;
  shadowColor: string;
  topEdgeColor: ResourceColor;
  bottomEdgeColor: ResourceColor;
  surfaceGradient: LinearGradient;
}

export interface SettingsPageRowVisualStyle {
  iconColor: ResourceColor;
  titleColor: ResourceColor;
  subtitleColor: ResourceColor;
  chevronColor: ResourceColor;
  chevronOpacity: number;
}

export interface SettingsPageFeaturedCardStyle {
  surface: SettingsPageSurfaceStyle;
  row: SettingsPageRowVisualStyle;
}

export class SettingsPageSurfaceManager {
  static getFeaturedCardStyle(theme: ThemeType): SettingsPageFeaturedCardStyle {
    return {
      surface: SettingsPageSurfaceManager.getFeaturedSurfaceStyle(theme),
      row: {
        iconColor: ThemeAwareHelper.getTestManagementThemedColor('accent_primary', theme),
        titleColor: theme === ThemeType.DARK
          ? 'rgba(248, 251, 255, 0.96)'
          : ThemeAwareHelper.getTestManagementThemedColor('text_primary', theme),
        subtitleColor: theme === ThemeType.DARK
          ? 'rgba(228, 236, 247, 0.88)'
          : ThemeAwareHelper.getTestManagementThemedColor('text_secondary', theme),
        chevronColor: theme === ThemeType.DARK
          ? 'rgba(236, 243, 252, 0.82)'
          : ThemeAwareHelper.getTestManagementThemedColor('text_muted', theme),
        chevronOpacity: theme === ThemeType.DARK ? 0.90 : 0.76
      }
    };
  }

  static getManagementContentSurfaceStyle(theme: ThemeType): SettingsPageSurfaceStyle {
    return SettingsPageSurfaceManager.getFeaturedSurfaceStyle(theme);
  }

  static getManagementListItemStyle(theme: ThemeType): SettingsPageRowVisualStyle {
    const featuredStyle: SettingsPageFeaturedCardStyle = SettingsPageSurfaceManager.getFeaturedCardStyle(theme);
    return {
      iconColor: ThemeAwareHelper.getTestManagementThemedColor('text_primary', theme),
      titleColor: featuredStyle.row.titleColor,
      subtitleColor: featuredStyle.row.subtitleColor,
      chevronColor: featuredStyle.row.chevronColor,
      chevronOpacity: theme === ThemeType.DARK ? 0.88 : 0.74
    };
  }

  private static getFeaturedSurfaceStyle(theme: ThemeType): SettingsPageSurfaceStyle {
    return {
      backgroundColor: SettingsGlassStyleHelper.getFeaturedBackground(),
      blurStyle: SettingsGlassStyleHelper.getFeaturedBlurStyle(),
      blurOptions: SettingsGlassStyleHelper.getFeaturedBlurOptions(),
      backgroundEffect: SettingsGlassStyleHelper.getFeaturedBackgroundEffect(),
      radius: SettingsGlassStyleHelper.getFeaturedRadius(),
      borderColor: SettingsGlassStyleHelper.getFeaturedBorderColor(),
      borderWidth: SettingsGlassStyleHelper.getFeaturedBorderWidth(),
      shadowColor: SettingsGlassStyleHelper.getFeaturedShadowColor(),
      topEdgeColor: theme === ThemeType.DARK
        ? 'rgba(255, 255, 255, 0.18)'
        : 'rgba(255, 255, 255, 0.62)',
      bottomEdgeColor: theme === ThemeType.DARK
        ? 'rgba(150, 190, 255, 0.07)'
        : 'rgba(126, 166, 220, 0.08)',
      surfaceGradient: theme === ThemeType.DARK
        ? {
            angle: 145,
            colors: [
              ['rgba(188, 224, 255, 0.10)', 0],
              ['rgba(30, 48, 76, 0.03)', 0.30],
              ['rgba(14, 22, 36, 0.02)', 0.72],
              ['rgba(154, 196, 255, 0.05)', 1]
            ]
          }
        : {
            angle: 145,
            colors: [
              ['rgba(255, 255, 255, 0.34)', 0],
              ['rgba(214, 231, 255, 0.08)', 0.28],
              ['rgba(186, 212, 248, 0.04)', 0.74],
              ['rgba(255, 255, 255, 0.16)', 1]
            ]
          }
    };
  }
}
