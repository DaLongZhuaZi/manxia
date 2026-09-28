import {
  DeviceAdaptationManager,
  DeviceInfo,
  DeviceType,
  FoldStatus,
  ScreenOrientation
} from '../Managers/DeviceAdaptationManager';

export enum BuiltInThemeResourceSet {
  DEFAULT = 'a',
  SECONDARY = 'b',
  CAT_DARK = 'cat_dark'
}

export enum BuiltInThemeDeviceShape {
  FOLDABLE_INNER = 1,
  COMPACT_PHONE = 2,
  LARGE_SCREEN = 3
}

export class BuiltInThemeResources {
  public static readonly DEFAULT_THEME_ID: string = 'default_custom_theme';
  public static readonly SECONDARY_THEME_ID: string = 'secondary_custom_theme';
  public static readonly CAT_DARK_THEME_ID: string = 'cat_dark_custom_theme';

  public static isBuiltInResourceTheme(themeId: string): boolean {
    return themeId === BuiltInThemeResources.DEFAULT_THEME_ID
      || themeId === BuiltInThemeResources.SECONDARY_THEME_ID
      || themeId === BuiltInThemeResources.CAT_DARK_THEME_ID;
  }

  public static isDarkBuiltInTheme(themeId: string): boolean {
    return themeId === BuiltInThemeResources.SECONDARY_THEME_ID
      || themeId === BuiltInThemeResources.CAT_DARK_THEME_ID;
  }

  public static resolveResource(themeId: string): ResourceStr {
    const setId: BuiltInThemeResourceSet = BuiltInThemeResources.resolveSet(themeId);
    const shape: BuiltInThemeDeviceShape = BuiltInThemeResources.resolveDeviceShape();
    return BuiltInThemeResources.resolveResourceBySetAndShape(setId, shape);
  }

  public static resolvePreviewResource(themeId: string): ResourceStr {
    const setId: BuiltInThemeResourceSet = BuiltInThemeResources.resolveSet(themeId);
    const shape: BuiltInThemeDeviceShape = BuiltInThemeResources.resolveDeviceShape();
    return BuiltInThemeResources.resolveResourceBySetAndShape(setId, shape);
  }

  private static resolveSet(themeId: string): BuiltInThemeResourceSet {
    if (themeId === BuiltInThemeResources.SECONDARY_THEME_ID) {
      return BuiltInThemeResourceSet.SECONDARY;
    }
    if (themeId === BuiltInThemeResources.CAT_DARK_THEME_ID) {
      return BuiltInThemeResourceSet.CAT_DARK;
    }
    return BuiltInThemeResourceSet.DEFAULT;
  }

  private static resolveDeviceShape(): BuiltInThemeDeviceShape {
    const deviceManager: DeviceAdaptationManager = DeviceAdaptationManager.getInstance();
    const info: DeviceInfo = deviceManager.getDeviceInfo();
    const shortSideVp: number = Math.min(info.screenWidth, info.screenHeight);
    const isLandscape: boolean = info.isLandscape || info.orientation === ScreenOrientation.LANDSCAPE;

    if (info.isFoldable) {
      if (info.foldStatus === FoldStatus.FOLDED) {
        return isLandscape ? BuiltInThemeDeviceShape.LARGE_SCREEN : BuiltInThemeDeviceShape.COMPACT_PHONE;
      }
      if (shortSideVp >= 600) {
        return BuiltInThemeDeviceShape.FOLDABLE_INNER;
      }
      return isLandscape ? BuiltInThemeDeviceShape.LARGE_SCREEN : BuiltInThemeDeviceShape.COMPACT_PHONE;
    }

    if (info.deviceType === DeviceType.TABLET || info.deviceType === DeviceType.TWO_IN_ONE) {
      return isLandscape ? BuiltInThemeDeviceShape.LARGE_SCREEN : BuiltInThemeDeviceShape.COMPACT_PHONE;
    }
    return isLandscape ? BuiltInThemeDeviceShape.LARGE_SCREEN : BuiltInThemeDeviceShape.COMPACT_PHONE;
  }

  private static resolveResourceBySetAndShape(
    setId: BuiltInThemeResourceSet,
    shape: BuiltInThemeDeviceShape
  ): ResourceStr {
    if (setId === BuiltInThemeResourceSet.CAT_DARK) {
      if (shape === BuiltInThemeDeviceShape.FOLDABLE_INNER) {
        return $r('app.media.cat_dark_1');
      }
      if (shape === BuiltInThemeDeviceShape.LARGE_SCREEN) {
        return $r('app.media.cat_dark_3');
      }
      return $r('app.media.cat_dark_2');
    }

    if (setId === BuiltInThemeResourceSet.SECONDARY) {
      if (shape === BuiltInThemeDeviceShape.FOLDABLE_INNER) {
        return $r('app.media.b_1');
      }
      if (shape === BuiltInThemeDeviceShape.LARGE_SCREEN) {
        return $r('app.media.b_3');
      }
      return $r('app.media.b_2');
    }

    if (shape === BuiltInThemeDeviceShape.FOLDABLE_INNER) {
      return $r('app.media.a_1');
    }
    if (shape === BuiltInThemeDeviceShape.LARGE_SCREEN) {
      return $r('app.media.a_3');
    }
    return $r('app.media.a_2');
  }
}
