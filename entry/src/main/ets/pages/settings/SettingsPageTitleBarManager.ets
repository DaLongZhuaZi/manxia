import { ThemeType } from '../../Framework/Managers/ThemeManager';

export interface SettingsImmersiveTitleActionItem {
  id: string;
  symbol: Resource;
  onClick: () => void;
  label?: string;
  enabled?: boolean;
  visible?: boolean;
}

export class SettingsPageTitleBarManager {
  static readonly TITLE_BAR_ROW_HEIGHT: number = 56;
  static readonly TITLE_BAR_EXTRA_HEIGHT: number = 10;
  static readonly TITLE_BAR_TOP_OFFSET: number = 4;
  static readonly DEFAULT_STATUS_BAR_INSET: number = 24;
  static readonly TITLE_FONT_SIZE: number = 26;
  static readonly BUTTON_SIZE: number = 40;
  static readonly BUTTON_ICON_SIZE: number = 22;
  static readonly ACTION_BUTTON_SPACE: number = 10;

  static getStatusBarInset(statusBarHeight: number): number {
    return statusBarHeight > 0 ? statusBarHeight : SettingsPageTitleBarManager.DEFAULT_STATUS_BAR_INSET;
  }

  static getTitleBarHeight(statusBarHeight: number): number {
    return SettingsPageTitleBarManager.getStatusBarInset(statusBarHeight) +
      SettingsPageTitleBarManager.TITLE_BAR_ROW_HEIGHT +
      SettingsPageTitleBarManager.TITLE_BAR_EXTRA_HEIGHT;
  }

  static getTitleBarTopPadding(statusBarHeight: number): number {
    return SettingsPageTitleBarManager.getStatusBarInset(statusBarHeight) +
      SettingsPageTitleBarManager.TITLE_BAR_TOP_OFFSET;
  }

  static getContentTopPadding(statusBarHeight: number): number {
    return SettingsPageTitleBarManager.getTitleBarHeight(statusBarHeight) - 8;
  }

  static getBackdropColor(theme: ThemeType): ResourceColor {
    return theme === ThemeType.DARK
      ? 'rgba(8, 14, 24, 0.014)'
      : 'rgba(255, 255, 255, 0.010)';
  }

  static getBackdropBlurRadius(theme: ThemeType): number {
    return theme === ThemeType.DARK ? 15 : 10;
  }

  static getSurfaceGradient(theme: ThemeType): LinearGradient {
    if (theme === ThemeType.DARK) {
      return {
        angle: 180,
        colors: [
          ['rgba(204, 230, 255, 0.050)', 0],
          ['rgba(88, 118, 158, 0.020)', 0.28],
          ['rgba(16, 24, 36, 0.006)', 0.68],
          ['rgba(12, 20, 30, 0)', 1]
        ]
      };
    }
    return {
      angle: 180,
      colors: [
        ['rgba(255, 255, 255, 0.040)', 0],
        ['rgba(240, 246, 255, 0.016)', 0.26],
        ['rgba(255, 255, 255, 0.005)', 0.62],
        ['rgba(255, 255, 255, 0)', 1]
      ]
    };
  }

  static getReflectionGradient(theme: ThemeType): LinearGradient {
    if (theme === ThemeType.DARK) {
      return {
        angle: 24,
        colors: [
          ['rgba(255, 255, 255, 0)', 0],
          ['rgba(236, 245, 255, 0.032)', 0.18],
          ['rgba(255, 255, 255, 0.056)', 0.38],
          ['rgba(255, 255, 255, 0.016)', 0.58],
          ['rgba(255, 255, 255, 0)', 1]
        ]
      };
    }
    return {
      angle: 24,
      colors: [
        ['rgba(255, 255, 255, 0)', 0],
        ['rgba(255, 255, 255, 0.026)', 0.18],
        ['rgba(255, 255, 255, 0.060)', 0.38],
        ['rgba(255, 255, 255, 0.015)', 0.58],
        ['rgba(255, 255, 255, 0)', 1]
      ]
    };
  }

  static getReflectionOpacity(theme: ThemeType): number {
    return theme === ThemeType.DARK ? 0.70 : 0.82;
  }

  static getTitleColor(theme: ThemeType): ResourceColor {
    return theme === ThemeType.DARK
      ? 'rgba(244, 248, 255, 0.96)'
      : 'rgba(24, 30, 40, 0.96)';
  }

  static getButtonFillColor(theme: ThemeType): ResourceColor {
    return theme === ThemeType.DARK
      ? 'rgba(66, 78, 98, 0.92)'
      : 'rgba(252, 253, 255, 0.94)';
  }

  static getButtonBackdropBlurRadius(theme: ThemeType): number {
    return theme === ThemeType.DARK ? 12 : 14;
  }

  static getButtonBorderColor(theme: ThemeType): ResourceColor {
    return theme === ThemeType.DARK
      ? 'rgba(255, 255, 255, 0.20)'
      : 'rgba(255, 255, 255, 0.82)';
  }

  static getButtonInnerBorderColor(theme: ThemeType): ResourceColor {
    return theme === ThemeType.DARK
      ? 'rgba(255, 255, 255, 0.08)'
      : 'rgba(255, 255, 255, 0.42)';
  }

  static getButtonShadowColor(theme: ThemeType, pressed: boolean = false): ResourceColor {
    if (theme === ThemeType.DARK) {
      return pressed ? 'rgba(0, 0, 0, 0.18)' : 'rgba(0, 0, 0, 0.28)';
    }
    return pressed ? 'rgba(154, 166, 184, 0.10)' : 'rgba(154, 166, 184, 0.16)';
  }

  static getButtonShadowRadius(pressed: boolean = false): number {
    return pressed ? 8 : 12;
  }

  static getButtonShadowOffsetY(pressed: boolean = false): number {
    return pressed ? 1 : 4;
  }

  static getButtonIconColor(theme: ThemeType): ResourceColor {
    return SettingsPageTitleBarManager.getTitleColor(theme);
  }

  static getButtonGlassTintGradient(theme: ThemeType): LinearGradient {
    if (theme === ThemeType.DARK) {
      return {
        angle: 180,
        colors: [
          ['rgba(255, 255, 255, 0.14)', 0],
          ['rgba(162, 188, 220, 0.08)', 0.34],
          ['rgba(0, 0, 0, 0.08)', 1]
        ]
      };
    }
    return {
      angle: 180,
      colors: [
        ['rgba(255, 255, 255, 0.32)', 0],
        ['rgba(255, 255, 255, 0.14)', 0.34],
        ['rgba(204, 213, 228, 0.12)', 1]
      ]
    };
  }

  static getButtonDepthGradient(theme: ThemeType): LinearGradient {
    if (theme === ThemeType.DARK) {
      return {
        angle: 180,
        colors: [
          ['rgba(255, 255, 255, 0)', 0],
          ['rgba(255, 255, 255, 0)', 0.48],
          ['rgba(0, 0, 0, 0.10)', 0.78],
          ['rgba(0, 0, 0, 0.20)', 1]
        ]
      };
    }
    return {
      angle: 180,
      colors: [
          ['rgba(255, 255, 255, 0)', 0],
          ['rgba(255, 255, 255, 0)', 0.52],
          ['rgba(200, 206, 216, 0.08)', 0.82],
          ['rgba(184, 191, 202, 0.18)', 1]
      ]
    };
  }

  static getButtonSpecularGradient(theme: ThemeType): LinearGradient {
    if (theme === ThemeType.DARK) {
      return {
        angle: 145,
        colors: [
          ['rgba(255, 255, 255, 0.30)', 0],
          ['rgba(255, 255, 255, 0.12)', 0.36],
          ['rgba(255, 255, 255, 0)', 1]
        ]
      };
    }
    return {
      angle: 145,
      colors: [
        ['rgba(255, 255, 255, 0.78)', 0],
        ['rgba(255, 255, 255, 0.36)', 0.36],
        ['rgba(255, 255, 255, 0)', 1]
      ]
    };
  }

  static getButtonBottomShadeGradient(theme: ThemeType): LinearGradient {
    if (theme === ThemeType.DARK) {
      return {
        angle: 180,
        colors: [
          ['rgba(255, 255, 255, 0)', 0],
          ['rgba(0, 0, 0, 0.10)', 0.62],
          ['rgba(0, 0, 0, 0.20)', 1]
        ]
      };
    }
    return {
      angle: 180,
      colors: [
        ['rgba(255, 255, 255, 0)', 0],
        ['rgba(188, 194, 204, 0.10)', 0.60],
        ['rgba(176, 183, 194, 0.18)', 1]
      ]
    };
  }

  static getButtonPressedOverlayColor(theme: ThemeType): ResourceColor {
    return theme === ThemeType.DARK
      ? 'rgba(0, 0, 0, 0.14)'
      : 'rgba(108, 118, 132, 0.08)';
  }

  static getButtonHighlightGradient(theme: ThemeType): LinearGradient {
    if (theme === ThemeType.DARK) {
      return {
        angle: 180,
        colors: [
          ['rgba(255, 255, 255, 0.12)', 0],
          ['rgba(255, 255, 255, 0.04)', 0.40],
          ['rgba(255, 255, 255, 0)', 1]
        ]
      };
    }
    return {
      angle: 180,
      colors: [
        ['rgba(255, 255, 255, 0.18)', 0],
        ['rgba(255, 255, 255, 0.05)', 0.42],
        ['rgba(255, 255, 255, 0)', 1]
      ]
    };
  }

  static getButtonEdgeHighlightGradient(theme: ThemeType): LinearGradient {
    if (theme === ThemeType.DARK) {
      return {
        angle: 180,
        colors: [
          ['rgba(255, 255, 255, 0.34)', 0],
          ['rgba(255, 255, 255, 0.10)', 0.34],
          ['rgba(255, 255, 255, 0)', 1]
        ]
      };
    }
    return {
      angle: 180,
      colors: [
        ['rgba(255, 255, 255, 0.72)', 0],
        ['rgba(255, 255, 255, 0.18)', 0.34],
        ['rgba(255, 255, 255, 0)', 1]
      ]
    };
  }
}
