/**
 * 主题设置页面
 * 提供自定义主题功能：图片选择、裁剪、模糊效果、主色调提取、深色模式适配
 */
import { logger } from '../Utils/Logger';
import { ThemeManager, ThemeType, CustomThemeData, CUSTOM_THEME_KEYS, THEME_CONFIGS, SplashRotationRule, CustomThemeMode } from '../Framework/Managers/ThemeManager';
import { ThemeAwareState, ThemeAwareHelper } from '../Framework/Components/ThemeAware';
import { FontAwareHelper, FontAwareState } from '../Framework/Components/FontAware';
import { PageLifecycleManager } from '../Framework/Lifecycle';
import { UserThemeConfigManager, TransparencyConfig, EffectsConfig, HdsTabEffectsConfig } from '../Framework/Theme/UserThemeConfig';
import { photoAccessHelper } from '@kit.MediaLibraryKit';
import { common } from '@kit.AbilityKit';
import { image } from '@kit.ImageKit';
import { fileIo } from '@kit.CoreFileKit';
import { UIContext, LengthMetrics, promptAction } from '@kit.ArkUI';
import { CropAlignment } from '../Framework/Utils/ImageCropper';
import { preferences } from '@kit.ArkData';
import fs from '@ohos.file.fs';
import effectKit from '@ohos.effectKit';
import { DeviceAdaptationManager, DeviceInfo, DeviceChangeListener, Breakpoint } from '../Framework/Managers/DeviceAdaptationManager';
import { ResponsiveLayoutHelper } from '../Framework/Utils/ResponsiveLayout';
import { hdsMaterial, HdsNavDestination, HdsNavDestinationAttribute, ScrollEffectType } from '@kit.UIDesignKit';
import { SettingsSearchSupport } from './settings/SettingsSearchSupport';
import { GlobalBackgroundLayerMode } from '../Framework/Components/GlobalBackgroundLayer';
import { SharedPageBackgroundLayer } from '../Framework/Components/SharedPageBackgroundLayer';
import { SettingsImmersiveTitleBar } from './settings/SettingsImmersiveTitleBar';
import { SettingsImmersiveTitleActionItem, SettingsPageTitleBarManager } from './settings/SettingsPageTitleBarManager';
import { SettingsPanelSurfaceHelper } from './settings/SettingsPanelSurfaceHelper';
import { BuiltInThemeResources } from '../Framework/Theme/BuiltInThemeResources';

const TAG = 'ThemeSettingsPage';
const HDS_TAB_MATERIAL_FOLLOW_GLOBAL: number = -1;
const DEFAULT_HDS_TAB_MATERIAL_LEVEL: number = hdsMaterial.MaterialLevel.EXQUISITE;
const DEFAULT_HDS_TAB_OPACITY_RATIO: number = 0.82;
const DEFAULT_HDS_TAB_MIN_OPACITY: number = 0.68;
const DEFAULT_HDS_TAB_MAX_OPACITY: number = 0.90;
const DEFAULT_HDS_TAB_LIGHT_HIGHLIGHT_OPACITY: number = 0.50;
const DEFAULT_HDS_TAB_DARK_HIGHLIGHT_OPACITY: number = 0.34;

/**
 * 自定义主题数据接口（本地定义，与ThemeManager中的CustomThemeData保持一致）
 */
interface CustomTheme {
  id: string;
  name: string;
  backgroundImagePath: string; // 浅色模式图片路径
  backgroundImagePathDark?: string; // 深色模式图片路径（可选，用于兼容旧版本）
  splashBackgroundImagePath?: string; // 开屏图片路径（可选）
  splashBackgroundImagePaths?: string[]; // 多开屏图片路径
  splashRotationRule?: SplashRotationRule; // 开屏轮换规则
  splashRotationCursor?: number; // 轮换游标
  splashRotationLastDateKey?: string; // 轮换日期键
  hideSplashLogo?: boolean; // 启动页不显示应用logo
  hideSplashProgress?: boolean; // 不显示启动进度
  blurLevel: number;
  brightness: number; // 亮度调整（0-100），50为原始亮度
  primaryColor: string;
  themeMode?: CustomThemeMode;
  isDark: boolean;
  createTime: number;
  lastModified: number;
}

interface SplashRotationOption {
  label: string;
  description: string;
  value: SplashRotationRule;
}

interface ThemeModeOption {
  label: string;
  description: string;
  value: CustomThemeMode;
}

/**
 * 图片处理配置接口
 */
interface ImageProcessConfig {
  targetWidth: number;
  targetHeight: number;
  blurRadius: number; // 模糊半径
  darkenAmount: number; // 压暗程度 (0-1)
  quality: number; // 输出质量 (0-100)
}

/**
 * 目标尺寸接口
 */
interface TargetSize {
  targetWidth: number;
  targetHeight: number;
}

/**
 * RGB颜色接口
 */
interface RGBColor {
  r: number;
  g: number;
  b: number;
}

interface ViewfinderImageMetrics {
  frameWidth: number;
  frameHeight: number;
  imageWidth: number;
  imageHeight: number;
  coverScale: number;
  baseDisplayWidth: number;
  baseDisplayHeight: number;
  displayWidth: number;
  displayHeight: number;
  maxOffsetX: number;
  maxOffsetY: number;
}

interface ViewfinderCropRect {
  x: number;
  y: number;
  width: number;
  height: number;
}

interface BackgroundDraftSelection {
  originalPath: string;
  appliedPath: string;
}

enum ThemeMediaTabType {
  BACKGROUND = 0,
  SPLASH = 1
}


@Component
export struct ThemeSettingsPage {
  @State pathStack: NavPathStack = new NavPathStack();
  private scroller: Scroller = new Scroller();
  @State private settingsTapEnabled: boolean = true;
  private settingsTapUnlockTimer: number = -1;
  private readonly scrollTapGuardDurationMs: number = 140;
  @State private activeSearchAnchorId: string = '';
  @State private searchHighlightPulse: boolean = false;
  private searchHighlightPulseTimer: number = -1;
  private searchHighlightClearTimer: number = -1;
  @State themeState: ThemeAwareState = new ThemeAwareState();
  @State fontState: FontAwareState = new FontAwareState();
  @StorageLink('appFontFamily') appFontFamily: string = 'HarmonyOS Sans';
  private themeManager: ThemeManager = ThemeManager.getInstance();
  private uiContext: UIContext | undefined = undefined;

  // 状态栏和导航栏高度
  @StorageProp('statusBarHeight') statusBarHeight: number = 0;
  @StorageProp('navigationBarHeight') navigationBarHeight: number = 0;

  // 响应式布局相关状态
  private deviceManager: DeviceAdaptationManager = DeviceAdaptationManager.getInstance();
  private deviceChangeListener: DeviceChangeListener | null = null;
  @State responsive_contentPadding: number = 16;
  @State responsive_maxContentWidth: number = 1200;
  @State responsive_isLandscape: boolean = false;
  @State previewFrameAspectRatio: number = 9 / 16;
  @State previewFrameWidthVp: number = 210;
  @State previewFrameHeightVp: number = 373;
  @State mediaEditorTab: ThemeMediaTabType = ThemeMediaTabType.BACKGROUND;
  @State isEditingCustomTheme: boolean = false;
  @State editingThemeId: string = '';
  @State editingThemeCreateTime: number = 0;

  // 当前选择的图片
  @State selectedImagePath: string = '';
  @State backgroundDraftImagePaths: string[] = [];
  @State activeBackgroundDraftPath: string = '';
  @State selectedImagePixelMap: image.PixelMap | null = null;
  // 开屏图片选择
  @State selectedSplashImagePath: string = '';
  @State selectedSplashImagePixelMap: image.PixelMap | null = null;
  @State processedSplashImagePixelMap: image.PixelMap | null = null;
  @State processedSplashImagePath: string = '';
  @State splashDraftImagePaths: string[] = [];
  @State splashSourceImagePaths: string[] = [];
  @State activeSplashSourcePath: string = '';
  @State splashCropAlignment: CropAlignment = CropAlignment.CENTER;
  @State splashCropZoom: number = 1.0;
  @State splashRotateQuarterTurns: number = 0;
  @State splashRotationRule: SplashRotationRule = SplashRotationRule.EVERY_LAUNCH;
  @State hideSplashLogo: boolean = false;
  @State hideSplashProgress: boolean = false;
  @State splashViewfinderScale: number = 1.0;
  @State splashViewfinderOffsetX: number = 0;
  @State splashViewfinderOffsetY: number = 0;
  @State selectedSplashPixelWidth: number = 0;
  @State selectedSplashPixelHeight: number = 0;
  
  // 主题商店展示与创建模式
  @State isCreatingCustomTheme: boolean = false;
  @State isCropping: boolean = false;
  @State cropAlignment: CropAlignment = CropAlignment.CENTER;
  @State cropZoom: number = 1.0;
  @State backgroundRotateQuarterTurns: number = 0;
  @State backgroundViewfinderScale: number = 1.0;
  @State backgroundViewfinderOffsetX: number = 0;
  @State backgroundViewfinderOffsetY: number = 0;
  @State selectedImagePixelWidth: number = 0;
  @State selectedImagePixelHeight: number = 0;
  @State newThemeName: string = '';
  @State selectedPrimaryColor: string = '';
  @State selectedThemeMode: CustomThemeMode = CustomThemeMode.AUTO;
  @State availablePrimaryColors: string[] = [];
  @State customPrimaryColorHex: string = '#007DFF';
  @State customPrimaryColorR: number = 0;
  @State customPrimaryColorG: number = 125;
  @State customPrimaryColorB: number = 255;
  // 多选删除：选择模式与已选主题ID列表
  @State selectionModeEnabled: boolean = false;
  @State selectedThemeIds: string[] = [];
  
  // 当前激活的主题ID（用于在列表中标识）
  @StorageProp(CUSTOM_THEME_KEYS.CURRENT_THEME_ID) currentCustomThemeId: string = '';
  
  // 处理后的图片
  @State processedImagePixelMap: image.PixelMap | null = null;
  @State processedImagePath: string = '';
  
  // 调节参数
  @State blurLevel: number = 0; // 模糊程度 0-100，默认无模糊
  @State brightnessLevel: number = 50; // 亮度 0-100，50为原始亮度，小于50变暗，大于50变亮
  
  // 提取的主色调
  @State extractedColor: string = '#6200EE';
  @State extractedColorRGB: string = 'RGB(98, 0, 238)';
  
  // 加载状态
  @State isProcessing: boolean = false;
  @State processingMessage: string = '';
  @State processingProgress: number = 0;
  
  // 预设主题列表
  @State customThemes: CustomTheme[] = [];
  
  // 滑块调节防抖定时器
  private effectDebounceTimer: number = -1;
  private readonly previewFrameMinWidthVp: number = 180;
  private readonly previewFrameMaxWidthVp: number = 420;
  private readonly previewFrameLandscapeMaxHeightVp: number = 520;
  private readonly previewFramePortraitMaxHeightVp: number = 680;
  private readonly viewfinderMinScale: number = 1.0;
  private readonly viewfinderMaxScale: number = 4.0;
  private viewfinderPinchStartScale: number = 1.0;
  private viewfinderPinchStartOffsetX: number = 0;
  private viewfinderPinchStartOffsetY: number = 0;
  private viewfinderPanStartOffsetX: number = 0;
  private viewfinderPanStartOffsetY: number = 0;
  private backgroundDraftSelections: Map<string, BackgroundDraftSelection> = new Map<string, BackgroundDraftSelection>();
  private splashViewfinderPinchStartScale: number = 1.0;
  private splashViewfinderPinchStartOffsetX: number = 0;
  private splashViewfinderPinchStartOffsetY: number = 0;
  private splashViewfinderPanStartOffsetX: number = 0;
  private splashViewfinderPanStartOffsetY: number = 0;
  private splashDraftSelections: Map<string, BackgroundDraftSelection> = new Map<string, BackgroundDraftSelection>();
  
  // 用户主题配置管理器
  private userThemeConfigManager: UserThemeConfigManager = UserThemeConfigManager.getInstance();
  
  // 透明度设置状态（使用StorageLink实现声明式绑定和实时预览）
  @StorageLink('userTheme_navBarOpacity') navBarOpacity: number = 1.0;
  @StorageLink('userTheme_cardOpacity') cardOpacity: number = 1.0;
  @StorageLink('userTheme_dialogOpacity') dialogOpacity: number = 0.95;
  @StorageLink('userTheme_floatingBallOpacity') floatingBallOpacity: number = 0.9;
  
  // 特效设置状态（使用StorageLink实现声明式绑定）
  @StorageLink('userTheme_blurEnabled') blurEnabled: boolean = true;
  @StorageLink('userTheme_shadowEnabled') shadowEnabled: boolean = true;
  @StorageLink('userTheme_animationEnabled') animationEnabled: boolean = true;
  @StorageLink('userTheme_glassmorphismEnabled') glassmorphismEnabled: boolean = true;
  @StorageLink('userTheme_componentCornerRadius') componentCornerRadius: number = 12;
  @StorageLink('userTheme_coverCornerRadius') coverCornerRadius: number = 12;

  // HdsTab 特效设置状态（使用StorageLink实现声明式绑定）
  @StorageLink('userTheme_hdsTabOpacityRatio') hdsTabOpacityRatio: number = DEFAULT_HDS_TAB_OPACITY_RATIO;
  @StorageLink('userTheme_hdsTabMinOpacity') hdsTabMinOpacity: number = DEFAULT_HDS_TAB_MIN_OPACITY;
  @StorageLink('userTheme_hdsTabMaxOpacity') hdsTabMaxOpacity: number = DEFAULT_HDS_TAB_MAX_OPACITY;
  @StorageLink('userTheme_hdsTabLightHighlightOpacity') hdsTabLightHighlightOpacity: number = DEFAULT_HDS_TAB_LIGHT_HIGHLIGHT_OPACITY;
  @StorageLink('userTheme_hdsTabDarkHighlightOpacity') hdsTabDarkHighlightOpacity: number = DEFAULT_HDS_TAB_DARK_HIGHLIGHT_OPACITY;
  @StorageLink('userTheme_hdsTabMaterialLevel') hdsTabMaterialLevel: number = DEFAULT_HDS_TAB_MATERIAL_LEVEL;
  @StorageLink('userTheme_hdsTabBlurEnabled') hdsTabBlurEnabled: boolean = true;
  @StorageLink('userTheme_hdsTabSideMargin') hdsTabSideMargin: number = 8;
  @StorageLink('userTheme_hdsTabBottomMargin') hdsTabBottomMargin: number = 0;
  
  // 本地状态（用于滑块显示，百分比形式）
  @State navBarTransparency: number = 100;
  @State cardTransparency: number = 100;
  @State dialogTransparency: number = 95;
  @State floatingBallTransparency: number = 90;
  @State effectBlurIntensity: number = 50;
  @State effectAnimationSpeed: number = 100;
  @State effectComponentCornerRadius: number = 12;
  @State effectCoverCornerRadius: number = 12;
  @State hdsTabOpacityRatioPercent: number = 72;
  @State hdsTabMinOpacityPercent: number = 56;
  @State hdsTabMaxOpacityPercent: number = 82;
  @State hdsTabLightHighlightPercent: number = 42;
  @State hdsTabDarkHighlightPercent: number = 22;
  @State hdsTabSideMarginValue: number = 8;
  @State hdsTabBottomMarginValue: number = 0;

  // 默认自定义主题常量
  private DEFAULT_THEME_ID: string = BuiltInThemeResources.DEFAULT_THEME_ID;
  private DEFAULT_THEME_NAME: string = '自定义';
  private SECONDARY_THEME_ID: string = BuiltInThemeResources.SECONDARY_THEME_ID;
  private SECONDARY_THEME_NAME: string = '第二自定义主题';
  private CAT_DARK_THEME_ID: string = BuiltInThemeResources.CAT_DARK_THEME_ID;
  private CAT_DARK_THEME_NAME: string = '猫猫深色主题';
  // 原始背景图片所在 rawfile 目录（如需调整实际目录，请修改此常量）
  private RAW_BACKGROUND_DIR: string = 'backgrounds';
  private themeModeOptions: ThemeModeOption[] = [
    {
      label: '浅色',
      description: '固定使用浅色组件、文字与背景适配',
      value: CustomThemeMode.LIGHT
    },
    {
      label: '深色',
      description: '固定使用深色组件、文字与背景适配',
      value: CustomThemeMode.DARK
    },
    {
      label: '自适应',
      description: '跟随系统浅色或深色设置自动切换配色',
      value: CustomThemeMode.AUTO
    }
  ];
  private splashRotationOptions: SplashRotationOption[] = [
    {
      label: '每次启动轮换',
      description: '每次启动应用时切到下一张开屏图',
      value: SplashRotationRule.EVERY_LAUNCH
    },
    {
      label: '每天轮换',
      description: '每天只切换一次，全天保持同一张开屏图',
      value: SplashRotationRule.DAILY
    },
    {
      label: '固定第一张',
      description: '始终使用列表第一张开屏图',
      value: SplashRotationRule.FIXED_FIRST
    }
  ];
  
  aboutToAppear(): void {
    logger.lifecycle(TAG, 'aboutToAppear');
    this.uiContext = this.getUIContext();
    
    ThemeAwareHelper.initializeThemeAware(TAG, this.themeState, (theme: ThemeType) => {
      logger.info(TAG, `主题已切换: ${theme}`);
    });
    FontAwareHelper.initializeFontAware(TAG, this.fontState, (newState: FontAwareState) => {
      this.fontState = newState;
    });
    
    // 初始化响应式布局
    this.initializeResponsiveLayout();
    
    this.loadCustomThemes();

    // 首次进入时初始化默认自定义主题（若不存在则创建）
    setTimeout(async () => {
      await this.ensureDefaultCustomThemeInitialized();
    }, 0);

    // 初始化可选主题色（从系统主题配置，后续加入提取主色）
    const colorsInit: string[] = [];
    colorsInit.push(THEME_CONFIGS[ThemeType.LIGHT].primaryColor);
    colorsInit.push(THEME_CONFIGS[ThemeType.DARK].primaryColor);
    this.availablePrimaryColors = colorsInit;
    this.selectedPrimaryColor = colorsInit[0];
    this.syncCustomColorEditor(this.selectedPrimaryColor);
    
    // 初始化用户主题配置并加载当前设置
    this.initializeUserThemeConfig();
  }

  private markSettingsScrolling(): void {
    if (this.settingsTapEnabled) {
      this.settingsTapEnabled = false;
    }
    if (this.settingsTapUnlockTimer >= 0) {
      clearTimeout(this.settingsTapUnlockTimer);
    }
    this.settingsTapUnlockTimer = setTimeout(() => {
      this.settingsTapEnabled = true;
      this.settingsTapUnlockTimer = -1;
    }, this.scrollTapGuardDurationMs);
  }

  private cleanupSettingsTapGuard(): void {
    if (this.settingsTapUnlockTimer >= 0) {
      clearTimeout(this.settingsTapUnlockTimer);
      this.settingsTapUnlockTimer = -1;
    }
    this.settingsTapEnabled = true;
  }

  private applyPendingSearchTarget(): void {
    const target = SettingsSearchSupport.consumePendingTarget('ThemeSettingsPage');
    if (!target) {
      return;
    }
    switch (target.anchorId) {
      case 'theme_create_background':
      case 'theme_create_colors':
      case 'theme_create_save':
        this.isCreatingCustomTheme = true;
        break;
      default:
        this.isCreatingCustomTheme = false;
        break;
    }
    this.exitSelectionMode();
    SettingsSearchSupport.activateHighlight(this, target.anchorId);
    const offset = Math.max(0, target.scrollOffset);
    logger.info(TAG, `应用设置搜索定位: id=${target.id}, anchor=${target.anchorId}, offset=${offset}`);
    setTimeout(() => {
      try {
        this.scroller.scrollTo({ xOffset: 0, yOffset: offset, animation: { duration: 360 } });
      } catch (error) {
        logger.warn(TAG, `滚动到设置搜索目标失败: ${String(error)}`);
      }
    }, 180);
  }
  
  /**
   * 初始化用户主题配置
   */
  private clampColorChannel(value: number): number {
    if (value < 0) {
      return 0;
    }
    if (value > 255) {
      return 255;
    }
    return Math.round(value);
  }

  private ensureColorInPalette(color: string): void {
    if (!this.availablePrimaryColors.includes(color)) {
      const nextColors: string[] = [];
      let idx: number = 0;
      while (idx < this.availablePrimaryColors.length) {
        nextColors.push(this.availablePrimaryColors[idx]);
        idx = idx + 1;
      }
      nextColors.push(color);
      this.availablePrimaryColors = nextColors;
    }
  }

  private normalizeHexColor(color: string): string {
    if (!color || color.length === 0) {
      return '#007DFF';
    }
    let normalized: string = color.trim().toUpperCase();
    if (!normalized.startsWith('#')) {
      normalized = `#${normalized}`;
    }
    if (normalized.length === 4) {
      const r: string = normalized.substring(1, 2);
      const g: string = normalized.substring(2, 3);
      const b: string = normalized.substring(3, 4);
      normalized = `#${r}${r}${g}${g}${b}${b}`;
    }
    const hexRegex: RegExp = /^#[0-9A-F]{6}$/;
    if (!hexRegex.test(normalized)) {
      return '#007DFF';
    }
    return normalized;
  }

  private syncCustomColorEditor(color: string): void {
    const normalized: string = this.normalizeHexColor(color);
    const rgb: RGBColor = this.parseHexColorToRGB(normalized);
    this.customPrimaryColorHex = normalized;
    this.customPrimaryColorR = this.clampColorChannel(rgb.r);
    this.customPrimaryColorG = this.clampColorChannel(rgb.g);
    this.customPrimaryColorB = this.clampColorChannel(rgb.b);
  }

  private updateCustomColorFromChannels(): void {
    const r: number = this.clampColorChannel(this.customPrimaryColorR);
    const g: number = this.clampColorChannel(this.customPrimaryColorG);
    const b: number = this.clampColorChannel(this.customPrimaryColorB);
    this.customPrimaryColorR = r;
    this.customPrimaryColorG = g;
    this.customPrimaryColorB = b;
    this.customPrimaryColorHex = `#${this.toHex(r)}${this.toHex(g)}${this.toHex(b)}`;
  }

  private applyCustomPrimaryColorFromEditor(): void {
    const normalized: string = this.normalizeHexColor(this.customPrimaryColorHex);
    this.customPrimaryColorHex = normalized;
    const rgb: RGBColor = this.parseHexColorToRGB(normalized);
    this.customPrimaryColorR = this.clampColorChannel(rgb.r);
    this.customPrimaryColorG = this.clampColorChannel(rgb.g);
    this.customPrimaryColorB = this.clampColorChannel(rgb.b);
    this.ensureColorInPalette(normalized);
    this.selectedPrimaryColor = normalized;
  }

  private getSplashPathsFromTheme(theme: CustomTheme): string[] {
    const normalized: string[] = [];
    if (theme.splashBackgroundImagePaths && theme.splashBackgroundImagePaths.length > 0) {
      let idx: number = 0;
      while (idx < theme.splashBackgroundImagePaths.length) {
        const candidate: string = theme.splashBackgroundImagePaths[idx];
        if (candidate && candidate.length > 0) {
          normalized.push(candidate);
        }
        idx = idx + 1;
      }
    }
    if (normalized.length === 0 && theme.splashBackgroundImagePath && theme.splashBackgroundImagePath.length > 0) {
      normalized.push(theme.splashBackgroundImagePath);
    }
    return normalized;
  }

  private getSplashRotationRuleFromTheme(theme: CustomTheme): SplashRotationRule {
    if (theme.splashRotationRule === SplashRotationRule.DAILY) {
      return SplashRotationRule.DAILY;
    }
    if (theme.splashRotationRule === SplashRotationRule.FIXED_FIRST) {
      return SplashRotationRule.FIXED_FIRST;
    }
    return SplashRotationRule.EVERY_LAUNCH;
  }

  private getHideSplashLogoFromTheme(theme: CustomTheme): boolean {
    return theme.hideSplashLogo === true;
  }

  private getHideSplashProgressFromTheme(theme: CustomTheme): boolean {
    return theme.hideSplashProgress === true;
  }

  private getThemeModeFromTheme(theme: CustomTheme): CustomThemeMode {
    if (theme.themeMode === CustomThemeMode.LIGHT) {
      return CustomThemeMode.LIGHT;
    }
    if (theme.themeMode === CustomThemeMode.DARK) {
      return CustomThemeMode.DARK;
    }
    if (theme.themeMode === CustomThemeMode.AUTO) {
      return CustomThemeMode.AUTO;
    }
    if (theme.id === this.SECONDARY_THEME_ID || theme.id === this.CAT_DARK_THEME_ID) {
      return CustomThemeMode.DARK;
    }
    return CustomThemeMode.AUTO;
  }

  private getThemeModeLabel(mode: CustomThemeMode): string {
    if (mode === CustomThemeMode.LIGHT) {
      return '浅色';
    }
    if (mode === CustomThemeMode.DARK) {
      return '深色';
    }
    return '自适应';
  }

  private getThemeModeDescription(mode: CustomThemeMode): string {
    if (mode === CustomThemeMode.LIGHT) {
      return '固定浅色配色';
    }
    if (mode === CustomThemeMode.DARK) {
      return '固定深色配色';
    }
    return '跟随系统配色';
  }

  private isDarkPreviewTheme(theme: CustomTheme): boolean {
    return this.getThemeModeFromTheme(theme) === CustomThemeMode.DARK;
  }

  private normalizeStoredThemeName(theme: CustomTheme): string {
    const rawName: string = theme.name ? theme.name : '';
    if (
      theme.id === this.DEFAULT_THEME_ID &&
      (rawName.length === 0 || rawName === '第一自定义主题' || rawName === '默认自定义主题')
    ) {
      return this.DEFAULT_THEME_NAME;
    }
    if (rawName.length > 0) {
      return rawName;
    }
    return this.DEFAULT_THEME_NAME;
  }

  private isBuiltInResourceThemeId(themeId: string): boolean {
    return BuiltInThemeResources.isBuiltInResourceTheme(themeId);
  }

  private getEditingSourceTheme(): CustomTheme | null {
    if (!this.isEditingCustomTheme || this.editingThemeId.length === 0) {
      return null;
    }
    let idx: number = 0;
    while (idx < this.customThemes.length) {
      const theme: CustomTheme = this.customThemes[idx];
      if (theme.id === this.editingThemeId) {
        return theme;
      }
      idx = idx + 1;
    }
    return null;
  }

  private canSaveCurrentTheme(): boolean {
    if (this.isProcessing) {
      return false;
    }
    if (this.isEditingCustomTheme) {
      return this.getEditingSourceTheme() !== null;
    }
    return this.processedImagePixelMap !== null;
  }

  private getSplashRotationRuleLabel(rule: SplashRotationRule): string {
    let idx: number = 0;
    while (idx < this.splashRotationOptions.length) {
      const option: SplashRotationOption = this.splashRotationOptions[idx];
      if (option.value === rule) {
        return option.label;
      }
      idx = idx + 1;
    }
    return '每次启动轮换';
  }

  private isMediaTabActive(tab: ThemeMediaTabType): boolean {
    return this.mediaEditorTab === tab;
  }

  private getMediaTabLabel(tab: ThemeMediaTabType): string {
    if (tab === ThemeMediaTabType.SPLASH) {
      return '开屏图片';
    }
    return '背景图片';
  }

  private normalizeQuarterTurns(turns: number): number {
    let normalized: number = turns % 4;
    if (normalized < 0) {
      normalized = normalized + 4;
    }
    return normalized;
  }

  private getQuarterTurnsLabel(turns: number): string {
    const normalized: number = this.normalizeQuarterTurns(turns);
    if (normalized === 1) {
      return '90°';
    }
    if (normalized === 2) {
      return '180°';
    }
    if (normalized === 3) {
      return '270°';
    }
    return '0°';
  }

  private async readPixelMapToRGBA(pixelMap: image.PixelMap): Promise<ArrayBuffer> {
    const info = await pixelMap.getImageInfo();
    const width: number = info.size.width;
    const height: number = info.size.height;
    const buffer = new ArrayBuffer(width * height * 4);
    await pixelMap.readPixelsToBuffer(buffer);
    const pixels = new Uint8Array(buffer);
    for (let idx = 0; idx < pixels.length; idx += 4) {
      const b: number = pixels[idx];
      const r: number = pixels[idx + 2];
      pixels[idx] = r;
      pixels[idx + 2] = b;
    }
    return buffer;
  }

  private async createPixelMapFromRGBA(buffer: ArrayBuffer, width: number, height: number): Promise<image.PixelMap> {
    const createOptions: image.InitializationOptions = {
      size: { width: width, height: height },
      pixelFormat: 3,
      alphaType: 0,
      editable: true
    };
    return await image.createPixelMap(buffer, createOptions);
  }

  private async rotatePixelMapByQuarterTurns(pixelMap: image.PixelMap, quarterTurns: number): Promise<image.PixelMap> {
    const turns: number = this.normalizeQuarterTurns(quarterTurns);
    const srcInfo = await pixelMap.getImageInfo();
    const srcWidth: number = srcInfo.size.width;
    const srcHeight: number = srcInfo.size.height;
    const srcBuffer: ArrayBuffer = await this.readPixelMapToRGBA(pixelMap);

    if (turns === 0) {
      return await this.createPixelMapFromRGBA(srcBuffer, srcWidth, srcHeight);
    }

    const dstWidth: number = turns % 2 === 0 ? srcWidth : srcHeight;
    const dstHeight: number = turns % 2 === 0 ? srcHeight : srcWidth;
    const dstBuffer = new ArrayBuffer(dstWidth * dstHeight * 4);
    const srcPixels = new Uint8Array(srcBuffer);
    const dstPixels = new Uint8Array(dstBuffer);

    let srcY: number = 0;
    while (srcY < srcHeight) {
      let srcX: number = 0;
      while (srcX < srcWidth) {
        let dstX: number = srcX;
        let dstY: number = srcY;
        if (turns === 1) {
          dstX = srcHeight - 1 - srcY;
          dstY = srcX;
        } else if (turns === 2) {
          dstX = srcWidth - 1 - srcX;
          dstY = srcHeight - 1 - srcY;
        } else {
          dstX = srcY;
          dstY = srcWidth - 1 - srcX;
        }
        const srcIndex: number = (srcY * srcWidth + srcX) * 4;
        const dstIndex: number = (dstY * dstWidth + dstX) * 4;
        dstPixels[dstIndex] = srcPixels[srcIndex];
        dstPixels[dstIndex + 1] = srcPixels[srcIndex + 1];
        dstPixels[dstIndex + 2] = srcPixels[srcIndex + 2];
        dstPixels[dstIndex + 3] = srcPixels[srcIndex + 3];
        srcX = srcX + 1;
      }
      srcY = srcY + 1;
    }

    return await this.createPixelMapFromRGBA(dstBuffer, dstWidth, dstHeight);
  }

  private resetBackgroundViewfinder(): void {
    this.backgroundViewfinderScale = 1.0;
    this.backgroundViewfinderOffsetX = 0;
    this.backgroundViewfinderOffsetY = 0;
    this.viewfinderPinchStartScale = 1.0;
    this.viewfinderPinchStartOffsetX = 0;
    this.viewfinderPinchStartOffsetY = 0;
  }

  private async syncSelectedImagePixelSize(pixelMap: image.PixelMap | null): Promise<void> {
    if (!pixelMap) {
      this.selectedImagePixelWidth = 0;
      this.selectedImagePixelHeight = 0;
      return;
    }
    const info = await pixelMap.getImageInfo();
    this.selectedImagePixelWidth = info.size.width;
    this.selectedImagePixelHeight = info.size.height;
  }

  private getRotatedSelectedImageSize(): TargetSize {
    const rawWidth: number = this.selectedImagePixelWidth > 0 ? this.selectedImagePixelWidth : 1;
    const rawHeight: number = this.selectedImagePixelHeight > 0 ? this.selectedImagePixelHeight : 1;
    const turns: number = this.normalizeQuarterTurns(this.backgroundRotateQuarterTurns);
    const rotatedSize: TargetSize = {
      targetWidth: turns % 2 === 0 ? rawWidth : rawHeight,
      targetHeight: turns % 2 === 0 ? rawHeight : rawWidth
    };
    return rotatedSize;
  }

  private buildViewfinderMetricsForImage(imageWidth: number, imageHeight: number, scale: number): ViewfinderImageMetrics {
    const frameWidth: number = this.previewFrameWidthVp > 0 ? this.previewFrameWidthVp : 220;
    const frameHeight: number = this.previewFrameHeightVp > 0 ? this.previewFrameHeightVp : (220 / (9 / 16));
    const safeImageWidth: number = imageWidth > 0 ? imageWidth : 1;
    const safeImageHeight: number = imageHeight > 0 ? imageHeight : 1;
    const coverScale: number = Math.max(frameWidth / safeImageWidth, frameHeight / safeImageHeight);
    const baseDisplayWidth: number = safeImageWidth * coverScale;
    const baseDisplayHeight: number = safeImageHeight * coverScale;
    const currentScale: number = this.clampNumber(scale, this.viewfinderMinScale, this.viewfinderMaxScale);
    const displayWidth: number = baseDisplayWidth * currentScale;
    const displayHeight: number = baseDisplayHeight * currentScale;
    const maxOffsetX: number = Math.max((displayWidth - frameWidth) / 2, 0);
    const maxOffsetY: number = Math.max((displayHeight - frameHeight) / 2, 0);
    const metrics: ViewfinderImageMetrics = {
      frameWidth: frameWidth,
      frameHeight: frameHeight,
      imageWidth: safeImageWidth,
      imageHeight: safeImageHeight,
      coverScale: coverScale,
      baseDisplayWidth: baseDisplayWidth,
      baseDisplayHeight: baseDisplayHeight,
      displayWidth: displayWidth,
      displayHeight: displayHeight,
      maxOffsetX: maxOffsetX,
      maxOffsetY: maxOffsetY
    } as ViewfinderImageMetrics;
    return metrics;
  }

  private getCurrentViewfinderMetrics(): ViewfinderImageMetrics {
    const rotatedSize: TargetSize = this.getRotatedSelectedImageSize();
    return this.buildViewfinderMetricsForImage(rotatedSize.targetWidth, rotatedSize.targetHeight, this.backgroundViewfinderScale);
  }

  private getCurrentViewfinderBaseImageWidth(): number {
    const metrics: ViewfinderImageMetrics = this.getCurrentViewfinderMetrics();
    const turns: number = this.normalizeQuarterTurns(this.backgroundRotateQuarterTurns);
    if (turns % 2 === 1) {
      return metrics.baseDisplayHeight;
    }
    return metrics.baseDisplayWidth;
  }

  private getCurrentViewfinderBaseImageHeight(): number {
    const metrics: ViewfinderImageMetrics = this.getCurrentViewfinderMetrics();
    const turns: number = this.normalizeQuarterTurns(this.backgroundRotateQuarterTurns);
    if (turns % 2 === 1) {
      return metrics.baseDisplayWidth;
    }
    return metrics.baseDisplayHeight;
  }

  private clampNumber(value: number, min: number, max: number): number {
    return Math.max(min, Math.min(max, value));
  }

  private clampViewfinderToBounds(): void {
    if (this.selectedImagePixelWidth <= 0 || this.selectedImagePixelHeight <= 0) {
      this.backgroundViewfinderScale = this.viewfinderMinScale;
      this.backgroundViewfinderOffsetX = 0;
      this.backgroundViewfinderOffsetY = 0;
      return;
    }
    const clampedScale: number = this.clampNumber(this.backgroundViewfinderScale, this.viewfinderMinScale, this.viewfinderMaxScale);
    const rotatedSize: TargetSize = this.getRotatedSelectedImageSize();
    const metrics: ViewfinderImageMetrics = this.buildViewfinderMetricsForImage(
      rotatedSize.targetWidth,
      rotatedSize.targetHeight,
      clampedScale
    );
    this.backgroundViewfinderScale = clampedScale;
    this.backgroundViewfinderOffsetX = this.clampNumber(this.backgroundViewfinderOffsetX, -metrics.maxOffsetX, metrics.maxOffsetX);
    this.backgroundViewfinderOffsetY = this.clampNumber(this.backgroundViewfinderOffsetY, -metrics.maxOffsetY, metrics.maxOffsetY);
  }

  private handleBackgroundViewfinderPan(event: GestureEvent): void {
    if (this.selectedImagePixelWidth <= 0 || this.selectedImagePixelHeight <= 0) {
      return;
    }
    const metrics: ViewfinderImageMetrics = this.getCurrentViewfinderMetrics();
    const nextOffsetX: number = this.viewfinderPanStartOffsetX + event.offsetX;
    const nextOffsetY: number = this.viewfinderPanStartOffsetY + event.offsetY;
    this.backgroundViewfinderOffsetX = this.clampNumber(nextOffsetX, -metrics.maxOffsetX, metrics.maxOffsetX);
    this.backgroundViewfinderOffsetY = this.clampNumber(nextOffsetY, -metrics.maxOffsetY, metrics.maxOffsetY);
  }

  private handleBackgroundViewfinderPanStart(): void {
    this.viewfinderPanStartOffsetX = this.backgroundViewfinderOffsetX;
    this.viewfinderPanStartOffsetY = this.backgroundViewfinderOffsetY;
  }

  private handleBackgroundViewfinderPinchStart(): void {
    this.viewfinderPinchStartScale = this.backgroundViewfinderScale;
    this.viewfinderPinchStartOffsetX = this.backgroundViewfinderOffsetX;
    this.viewfinderPinchStartOffsetY = this.backgroundViewfinderOffsetY;
  }

  private handleBackgroundViewfinderPinch(event: GestureEvent): void {
    if (this.selectedImagePixelWidth <= 0 || this.selectedImagePixelHeight <= 0) {
      return;
    }
    const rawScale: number = this.viewfinderPinchStartScale * event.scale;
    const nextScale: number = this.clampNumber(rawScale, this.viewfinderMinScale, this.viewfinderMaxScale);
    const scaleRatio: number = this.viewfinderPinchStartScale > 0 ? (nextScale / this.viewfinderPinchStartScale) : 1.0;
    this.backgroundViewfinderScale = nextScale;
    this.backgroundViewfinderOffsetX = this.viewfinderPinchStartOffsetX * scaleRatio;
    this.backgroundViewfinderOffsetY = this.viewfinderPinchStartOffsetY * scaleRatio;
    this.clampViewfinderToBounds();
  }

  private handleBackgroundViewfinderPinchEnd(): void {
    const shouldReboundToBase: boolean = this.backgroundViewfinderScale < this.viewfinderMinScale + 0.03;
    const targetScale: number = shouldReboundToBase ? this.viewfinderMinScale : this.clampNumber(this.backgroundViewfinderScale, this.viewfinderMinScale, this.viewfinderMaxScale);
    if (this.uiContext) {
      this.uiContext.animateTo({
        duration: 180,
        curve: Curve.EaseOut
      }, () => {
        this.backgroundViewfinderScale = targetScale;
        this.clampViewfinderToBounds();
      });
      return;
    }
    this.backgroundViewfinderScale = targetScale;
    this.clampViewfinderToBounds();
  }

  private computeViewfinderCropRectByOffset(metrics: ViewfinderImageMetrics, offsetX: number, offsetY: number): ViewfinderCropRect {
    const left: number = (metrics.frameWidth - metrics.displayWidth) / 2 + offsetX;
    const top: number = (metrics.frameHeight - metrics.displayHeight) / 2 + offsetY;
    const scaleX: number = metrics.displayWidth / metrics.imageWidth;
    const scaleY: number = metrics.displayHeight / metrics.imageHeight;
    let cropX: number = Math.round((0 - left) / scaleX);
    let cropY: number = Math.round((0 - top) / scaleY);
    let cropWidth: number = Math.round(metrics.frameWidth / scaleX);
    let cropHeight: number = Math.round(metrics.frameHeight / scaleY);

    cropWidth = Math.max(1, Math.min(cropWidth, metrics.imageWidth));
    cropHeight = Math.max(1, Math.min(cropHeight, metrics.imageHeight));
    cropX = this.clampNumber(cropX, 0, Math.max(0, metrics.imageWidth - cropWidth));
    cropY = this.clampNumber(cropY, 0, Math.max(0, metrics.imageHeight - cropHeight));

    const cropRect: ViewfinderCropRect = {
      x: cropX,
      y: cropY,
      width: cropWidth,
      height: cropHeight
    } as ViewfinderCropRect;
    return cropRect;
  }

  private computeViewfinderCropRect(metrics: ViewfinderImageMetrics): ViewfinderCropRect {
    return this.computeViewfinderCropRectByOffset(metrics, this.backgroundViewfinderOffsetX, this.backgroundViewfinderOffsetY);
  }

  private async cropPixelMapByRect(pixelMap: image.PixelMap, cropRect: ViewfinderCropRect): Promise<image.PixelMap> {
    const bufferSize: number = cropRect.width * cropRect.height * 4;
    const buffer = new ArrayBuffer(bufferSize);
    const readArea: image.PositionArea = {
      pixels: buffer,
      offset: 0,
      stride: cropRect.width * 4,
      region: {
        size: {
          width: cropRect.width,
          height: cropRect.height
        },
        x: cropRect.x,
        y: cropRect.y
      }
    };
    await pixelMap.readPixels(readArea);
    const initOptions: image.InitializationOptions = {
      size: {
        width: cropRect.width,
        height: cropRect.height
      },
      pixelFormat: 3,
      alphaType: 0,
      editable: true
    };
    return await image.createPixelMap(buffer, initOptions);
  }

  private async buildBackgroundPreviewPixelMap(sourcePixelMap: image.PixelMap): Promise<image.PixelMap> {
    const rotatedPixelMap = await this.rotatePixelMapByQuarterTurns(sourcePixelMap, this.backgroundRotateQuarterTurns);
    try {
      const rotatedInfo = await rotatedPixelMap.getImageInfo();
      const metrics: ViewfinderImageMetrics = this.buildViewfinderMetricsForImage(
        rotatedInfo.size.width,
        rotatedInfo.size.height,
        this.backgroundViewfinderScale
      );
      const cropRect: ViewfinderCropRect = this.computeViewfinderCropRect(metrics);
      return await this.cropPixelMapByRect(rotatedPixelMap, cropRect);
    } finally {
      rotatedPixelMap.release();
    }
  }

  private resetSplashViewfinder(): void {
    this.splashViewfinderScale = 1.0;
    this.splashViewfinderOffsetX = 0;
    this.splashViewfinderOffsetY = 0;
    this.splashViewfinderPanStartOffsetX = 0;
    this.splashViewfinderPanStartOffsetY = 0;
    this.splashViewfinderPinchStartScale = 1.0;
    this.splashViewfinderPinchStartOffsetX = 0;
    this.splashViewfinderPinchStartOffsetY = 0;
  }

  private async syncSelectedSplashPixelSize(pixelMap: image.PixelMap | null): Promise<void> {
    if (!pixelMap) {
      this.selectedSplashPixelWidth = 0;
      this.selectedSplashPixelHeight = 0;
      return;
    }
    const info = await pixelMap.getImageInfo();
    this.selectedSplashPixelWidth = info.size.width;
    this.selectedSplashPixelHeight = info.size.height;
  }

  private getRotatedSelectedSplashSize(): TargetSize {
    const rawWidth: number = this.selectedSplashPixelWidth > 0 ? this.selectedSplashPixelWidth : 1;
    const rawHeight: number = this.selectedSplashPixelHeight > 0 ? this.selectedSplashPixelHeight : 1;
    const turns: number = this.normalizeQuarterTurns(this.splashRotateQuarterTurns);
    const rotatedSize: TargetSize = {
      targetWidth: turns % 2 === 0 ? rawWidth : rawHeight,
      targetHeight: turns % 2 === 0 ? rawHeight : rawWidth
    };
    return rotatedSize;
  }

  private getCurrentSplashViewfinderMetrics(): ViewfinderImageMetrics {
    const rotatedSize: TargetSize = this.getRotatedSelectedSplashSize();
    return this.buildViewfinderMetricsForImage(rotatedSize.targetWidth, rotatedSize.targetHeight, this.splashViewfinderScale);
  }

  private getCurrentSplashViewfinderBaseImageWidth(): number {
    const metrics: ViewfinderImageMetrics = this.getCurrentSplashViewfinderMetrics();
    const turns: number = this.normalizeQuarterTurns(this.splashRotateQuarterTurns);
    if (turns % 2 === 1) {
      return metrics.baseDisplayHeight;
    }
    return metrics.baseDisplayWidth;
  }

  private getCurrentSplashViewfinderBaseImageHeight(): number {
    const metrics: ViewfinderImageMetrics = this.getCurrentSplashViewfinderMetrics();
    const turns: number = this.normalizeQuarterTurns(this.splashRotateQuarterTurns);
    if (turns % 2 === 1) {
      return metrics.baseDisplayWidth;
    }
    return metrics.baseDisplayHeight;
  }

  private clampSplashViewfinderToBounds(): void {
    if (this.selectedSplashPixelWidth <= 0 || this.selectedSplashPixelHeight <= 0) {
      this.splashViewfinderScale = this.viewfinderMinScale;
      this.splashViewfinderOffsetX = 0;
      this.splashViewfinderOffsetY = 0;
      return;
    }
    const clampedScale: number = this.clampNumber(this.splashViewfinderScale, this.viewfinderMinScale, this.viewfinderMaxScale);
    const rotatedSize: TargetSize = this.getRotatedSelectedSplashSize();
    const metrics: ViewfinderImageMetrics = this.buildViewfinderMetricsForImage(
      rotatedSize.targetWidth,
      rotatedSize.targetHeight,
      clampedScale
    );
    this.splashViewfinderScale = clampedScale;
    this.splashViewfinderOffsetX = this.clampNumber(this.splashViewfinderOffsetX, -metrics.maxOffsetX, metrics.maxOffsetX);
    this.splashViewfinderOffsetY = this.clampNumber(this.splashViewfinderOffsetY, -metrics.maxOffsetY, metrics.maxOffsetY);
  }

  private handleSplashViewfinderPanStart(): void {
    this.splashViewfinderPanStartOffsetX = this.splashViewfinderOffsetX;
    this.splashViewfinderPanStartOffsetY = this.splashViewfinderOffsetY;
  }

  private handleSplashViewfinderPan(event: GestureEvent): void {
    if (this.selectedSplashPixelWidth <= 0 || this.selectedSplashPixelHeight <= 0) {
      return;
    }
    const metrics: ViewfinderImageMetrics = this.getCurrentSplashViewfinderMetrics();
    const nextOffsetX: number = this.splashViewfinderPanStartOffsetX + event.offsetX;
    const nextOffsetY: number = this.splashViewfinderPanStartOffsetY + event.offsetY;
    this.splashViewfinderOffsetX = this.clampNumber(nextOffsetX, -metrics.maxOffsetX, metrics.maxOffsetX);
    this.splashViewfinderOffsetY = this.clampNumber(nextOffsetY, -metrics.maxOffsetY, metrics.maxOffsetY);
  }

  private handleSplashViewfinderPinchStart(): void {
    this.splashViewfinderPinchStartScale = this.splashViewfinderScale;
    this.splashViewfinderPinchStartOffsetX = this.splashViewfinderOffsetX;
    this.splashViewfinderPinchStartOffsetY = this.splashViewfinderOffsetY;
  }

  private handleSplashViewfinderPinch(event: GestureEvent): void {
    if (this.selectedSplashPixelWidth <= 0 || this.selectedSplashPixelHeight <= 0) {
      return;
    }
    const rawScale: number = this.splashViewfinderPinchStartScale * event.scale;
    const nextScale: number = this.clampNumber(rawScale, this.viewfinderMinScale, this.viewfinderMaxScale);
    const scaleRatio: number = this.splashViewfinderPinchStartScale > 0 ? (nextScale / this.splashViewfinderPinchStartScale) : 1.0;
    this.splashViewfinderScale = nextScale;
    this.splashViewfinderOffsetX = this.splashViewfinderPinchStartOffsetX * scaleRatio;
    this.splashViewfinderOffsetY = this.splashViewfinderPinchStartOffsetY * scaleRatio;
    this.clampSplashViewfinderToBounds();
  }

  private handleSplashViewfinderPinchEnd(): void {
    const shouldReboundToBase: boolean = this.splashViewfinderScale < this.viewfinderMinScale + 0.03;
    const targetScale: number = shouldReboundToBase ? this.viewfinderMinScale : this.clampNumber(this.splashViewfinderScale, this.viewfinderMinScale, this.viewfinderMaxScale);
    if (this.uiContext) {
      this.uiContext.animateTo({
        duration: 180,
        curve: Curve.EaseOut
      }, () => {
        this.splashViewfinderScale = targetScale;
        this.clampSplashViewfinderToBounds();
      });
      return;
    }
    this.splashViewfinderScale = targetScale;
    this.clampSplashViewfinderToBounds();
  }

  private async buildSplashPreviewPixelMap(sourcePixelMap: image.PixelMap): Promise<image.PixelMap> {
    const rotatedPixelMap = await this.rotatePixelMapByQuarterTurns(sourcePixelMap, this.splashRotateQuarterTurns);
    try {
      const rotatedInfo = await rotatedPixelMap.getImageInfo();
      const metrics: ViewfinderImageMetrics = this.buildViewfinderMetricsForImage(
        rotatedInfo.size.width,
        rotatedInfo.size.height,
        this.splashViewfinderScale
      );
      const cropRect: ViewfinderCropRect = this.computeViewfinderCropRectByOffset(
        metrics,
        this.splashViewfinderOffsetX,
        this.splashViewfinderOffsetY
      );
      return await this.cropPixelMapByRect(rotatedPixelMap, cropRect);
    } finally {
      rotatedPixelMap.release();
    }
  }

  private async refreshSplashPreviewFromSelection(): Promise<void> {
    if (!this.selectedSplashImagePixelMap) {
      return;
    }
    const nextPreview: image.PixelMap = await this.buildSplashPreviewPixelMap(this.selectedSplashImagePixelMap);
    if (this.processedSplashImagePixelMap) {
      this.processedSplashImagePixelMap.release();
    }
    this.processedSplashImagePixelMap = nextPreview;
    this.processedSplashImagePath = this.selectedSplashImagePath;
  }

  private clearCurrentSplashSelection(): void {
    if (this.selectedSplashImagePixelMap) {
      this.selectedSplashImagePixelMap.release();
      this.selectedSplashImagePixelMap = null;
    }
    if (this.processedSplashImagePixelMap) {
      this.processedSplashImagePixelMap.release();
      this.processedSplashImagePixelMap = null;
    }
    this.selectedSplashImagePath = '';
    this.processedSplashImagePath = '';
    this.selectedSplashPixelWidth = 0;
    this.selectedSplashPixelHeight = 0;
    this.resetSplashViewfinder();
  }

  private clearCurrentBackgroundSelection(): void {
    if (this.selectedImagePixelMap) {
      this.selectedImagePixelMap.release();
      this.selectedImagePixelMap = null;
    }
    if (this.processedImagePixelMap) {
      this.processedImagePixelMap.release();
      this.processedImagePixelMap = null;
    }
    this.selectedImagePath = '';
    this.processedImagePath = '';
    this.activeBackgroundDraftPath = '';
    this.selectedImagePixelWidth = 0;
    this.selectedImagePixelHeight = 0;
    this.resetBackgroundViewfinder();
  }

  private removeSplashDraftAt(index: number): void {
    if (index < 0 || index >= this.splashDraftImagePaths.length) {
      return;
    }
    const pathToDelete: string = this.splashDraftImagePaths[index];
    if (pathToDelete.length > 0 && fs.accessSync(pathToDelete)) {
      fs.unlinkSync(pathToDelete);
    }
    const nextPaths: string[] = [];
    let idx: number = 0;
    while (idx < this.splashDraftImagePaths.length) {
      if (idx !== index) {
        nextPaths.push(this.splashDraftImagePaths[idx]);
      }
      idx = idx + 1;
    }
    this.splashDraftImagePaths = nextPaths;
  }

  private async addCurrentSplashToDraftList(): Promise<void> {
    if (!this.processedSplashImagePixelMap) {
      logger.warn(TAG, '当前没有可加入列表的开屏图');
      return;
    }
    const context = this.uiContext?.getHostContext() as common.UIAbilityContext;
    if (!context) {
      throw new Error('无法获取UIAbilityContext');
    }
    const themesDir: string = `${context.filesDir}/custom_themes`;
    if (!fs.accessSync(themesDir)) {
      fs.mkdirSync(themesDir);
    }
    const draftDir: string = `${themesDir}/splash_drafts`;
    if (!fs.accessSync(draftDir)) {
      fs.mkdirSync(draftDir);
    }
    const timestamp: number = Date.now();
    const draftPath: string = `${draftDir}/draft_${timestamp}_${this.splashDraftImagePaths.length + 1}.webp`;
    const packOpts: image.PackingOption = {
      format: 'image/webp',
      quality: 85
    };
    const imagePacker = image.createImagePacker();
    const file = fs.openSync(draftPath, fs.OpenMode.CREATE | fs.OpenMode.WRITE_ONLY | fs.OpenMode.TRUNC);
    try {
      await imagePacker.packToFile(this.processedSplashImagePixelMap, file.fd, packOpts);
    } finally {
      fs.closeSync(file);
      imagePacker.release();
    }
    const nextDrafts: string[] = [];
    let idx: number = 0;
    while (idx < this.splashDraftImagePaths.length) {
      nextDrafts.push(this.splashDraftImagePaths[idx]);
      idx = idx + 1;
    }
    nextDrafts.push(draftPath);
    this.splashDraftImagePaths = nextDrafts;
  }

  private async persistCurrentSplashAsThemeImage(path: string): Promise<void> {
    if (!this.processedSplashImagePixelMap) {
      throw new Error('processedSplashImagePixelMap为空');
    }
    const packOpts: image.PackingOption = {
      format: 'image/webp',
      quality: 85
    };
    const imagePacker = image.createImagePacker();
    const file = fs.openSync(path, fs.OpenMode.CREATE | fs.OpenMode.WRITE_ONLY | fs.OpenMode.TRUNC);
    try {
      await imagePacker.packToFile(this.processedSplashImagePixelMap, file.fd, packOpts);
    } finally {
      fs.closeSync(file);
      imagePacker.release();
    }
  }

  private async generateSplashImages(themeId: string): Promise<string[]> {
    const context = this.uiContext?.getHostContext() as common.UIAbilityContext;
    if (!context) {
      throw new Error('无法获取UIAbilityContext');
    }
    const themesDir: string = `${context.filesDir}/custom_themes`;
    const generatedPaths: string[] = [];
    const sourcePaths: string[] = this.splashSourceImagePaths.length > 0 ? this.splashSourceImagePaths : this.splashDraftImagePaths;
    let index: number = 0;
    while (index < sourcePaths.length) {
      const sourcePath: string = sourcePaths[index];
      let resolvedPath: string = this.resolveSplashSourcePath(sourcePath);
      if (!(resolvedPath.length > 0 && fs.accessSync(resolvedPath))) {
        try {
          await this.importSplashSourceToDraftIfNeeded(sourcePath);
          resolvedPath = this.resolveSplashSourcePath(sourcePath);
        } catch (error) {
          const message: string = error instanceof Error ? error.message : String(error);
          logger.warn(TAG, `导入开屏原图用于保存失败: ${message}`);
        }
      }
      if (resolvedPath.length > 0 && fs.accessSync(resolvedPath)) {
        const targetPath: string = `${themesDir}/${themeId}_splash_${index + 1}.webp`;
        if (resolvedPath !== targetPath) {
          fs.copyFileSync(resolvedPath, targetPath);
        }
        generatedPaths.push(targetPath);
      } else {
        logger.warn(TAG, `跳过不可访问的开屏图: ${sourcePath}`);
      }
      index = index + 1;
    }
    if (generatedPaths.length === 0 && this.processedSplashImagePixelMap) {
      const fallbackPath: string = `${themesDir}/${themeId}_splash_1.webp`;
      await this.persistCurrentSplashAsThemeImage(fallbackPath);
      generatedPaths.push(fallbackPath);
    }
    return generatedPaths;
  }

  private cleanupSplashDraftFiles(): void {
    let idx: number = 0;
    while (idx < this.splashDraftImagePaths.length) {
      const path: string = this.splashDraftImagePaths[idx];
      if (path && path.length > 0 && fs.accessSync(path)) {
        fs.unlinkSync(path);
      }
      idx = idx + 1;
    }
    this.splashDraftSelections.forEach((selection: BackgroundDraftSelection) => {
      if (selection.appliedPath.length > 0 && fs.accessSync(selection.appliedPath)) {
        fs.unlinkSync(selection.appliedPath);
      }
    });
    this.splashDraftSelections.clear();
    this.splashDraftImagePaths = [];
    this.splashSourceImagePaths = [];
    this.activeSplashSourcePath = '';
  }

  private normalizeBackgroundImageUris(imageUris: string[]): string[] {
    const normalized: string[] = [];
    let idx: number = 0;
    while (idx < imageUris.length) {
      const uri: string = imageUris[idx];
      if (uri && uri.length > 0 && !normalized.includes(uri)) {
        normalized.push(uri);
      }
      idx = idx + 1;
    }
    return normalized;
  }

  private mergeBackgroundDraftPaths(newUris: string[]): string[] {
    const merged: string[] = [];
    let oldIdx: number = 0;
    while (oldIdx < this.backgroundDraftImagePaths.length) {
      const oldPath: string = this.backgroundDraftImagePaths[oldIdx];
      if (oldPath.length > 0 && !merged.includes(oldPath)) {
        merged.push(oldPath);
      }
      oldIdx = oldIdx + 1;
    }
    let newIdx: number = 0;
    while (newIdx < newUris.length) {
      const newPath: string = newUris[newIdx];
      if (newPath.length > 0 && !merged.includes(newPath)) {
        merged.push(newPath);
      }
      newIdx = newIdx + 1;
    }
    return merged;
  }

  private resolveBackgroundDraftSourcePath(originalPath: string): string {
    const selection: BackgroundDraftSelection | undefined = this.backgroundDraftSelections.get(originalPath);
    if (selection && selection.appliedPath.length > 0 && fs.accessSync(selection.appliedPath)) {
      return selection.appliedPath;
    }
    return originalPath;
  }

  private registerBackgroundDraftIfNeeded(originalPath: string): void {
    if (originalPath.length === 0) {
      return;
    }
    if (!this.backgroundDraftSelections.has(originalPath)) {
      const draft: BackgroundDraftSelection = {
        originalPath: originalPath,
        appliedPath: ''
      };
      this.backgroundDraftSelections.set(originalPath, draft);
    }
  }

  private async packPixelMapToWebp(pixelMap: image.PixelMap, path: string, quality: number): Promise<void> {
    const packOpts: image.PackingOption = {
      format: 'image/webp',
      quality: quality
    };
    const imagePacker = image.createImagePacker();
    const file = fs.openSync(path, fs.OpenMode.CREATE | fs.OpenMode.WRITE_ONLY | fs.OpenMode.TRUNC);
    try {
      await imagePacker.packToFile(pixelMap, file.fd, packOpts);
    } finally {
      fs.closeSync(file);
      imagePacker.release();
    }
  }

  private async persistActiveBackgroundDraftCrop(): Promise<void> {
    if (!this.selectedImagePixelMap) {
      return;
    }
    const activePath: string = this.activeBackgroundDraftPath.length > 0 ? this.activeBackgroundDraftPath : this.selectedImagePath;
    if (activePath.length === 0) {
      return;
    }
    this.registerBackgroundDraftIfNeeded(activePath);
    const context = this.uiContext?.getHostContext() as common.UIAbilityContext;
    if (!context) {
      throw new Error('无法获取UIAbilityContext');
    }
    const themesDir: string = `${context.filesDir}/custom_themes`;
    if (!fs.accessSync(themesDir)) {
      fs.mkdirSync(themesDir);
    }
    const draftDir: string = `${themesDir}/background_drafts`;
    if (!fs.accessSync(draftDir)) {
      fs.mkdirSync(draftDir);
    }
    const oldSelection: BackgroundDraftSelection | undefined = this.backgroundDraftSelections.get(activePath);
    if (oldSelection && oldSelection.appliedPath.length > 0 && fs.accessSync(oldSelection.appliedPath)) {
      fs.unlinkSync(oldSelection.appliedPath);
    }
    const targetPath: string = `${draftDir}/draft_${Date.now()}_${this.backgroundDraftImagePaths.indexOf(activePath) + 1}.webp`;
    await this.packPixelMapToWebp(this.selectedImagePixelMap, targetPath, 88);
    const nextSelection: BackgroundDraftSelection = {
      originalPath: activePath,
      appliedPath: targetPath
    };
    this.backgroundDraftSelections.set(activePath, nextSelection);
  }

  private async switchBackgroundDraftImage(targetOriginalPath: string): Promise<void> {
    if (targetOriginalPath.length === 0) {
      return;
    }
    try {
      if (this.activeBackgroundDraftPath === targetOriginalPath && this.selectedImagePixelMap) {
        return;
      }
      const resolvedPath: string = this.resolveBackgroundDraftSourcePath(targetOriginalPath);
      await this.loadAndProcessImage(resolvedPath, targetOriginalPath);
    } catch (error) {
      const message: string = error instanceof Error ? error.message : String(error);
      logger.error(TAG, `切换背景草稿失败: ${message}`);
    }
  }

  private async setBackgroundDraftImages(imageUris: string[]): Promise<void> {
    const normalizedUris: string[] = this.normalizeBackgroundImageUris(imageUris);
    if (normalizedUris.length === 0) {
      return;
    }
    const mergedDraftPaths: string[] = this.mergeBackgroundDraftPaths(normalizedUris);
    this.backgroundDraftImagePaths = mergedDraftPaths;
    let idx: number = 0;
    while (idx < normalizedUris.length) {
      this.registerBackgroundDraftIfNeeded(normalizedUris[idx]);
      idx = idx + 1;
    }
    await this.switchBackgroundDraftImage(normalizedUris[0]);
  }

  private cleanupBackgroundDraftFiles(): void {
    this.backgroundDraftSelections.forEach((selection: BackgroundDraftSelection) => {
      if (selection.appliedPath.length > 0 && fs.accessSync(selection.appliedPath)) {
        fs.unlinkSync(selection.appliedPath);
      }
    });
    this.backgroundDraftSelections.clear();
    this.backgroundDraftImagePaths = [];
    this.activeBackgroundDraftPath = '';
  }

  private normalizeSplashImageUris(imageUris: string[]): string[] {
    const normalized: string[] = [];
    let idx: number = 0;
    while (idx < imageUris.length) {
      const uri: string = imageUris[idx];
      if (uri && uri.length > 0 && !normalized.includes(uri)) {
        normalized.push(uri);
      }
      idx = idx + 1;
    }
    return normalized;
  }

  private mergeSplashSourcePaths(newUris: string[]): string[] {
    const merged: string[] = [];
    let oldIdx: number = 0;
    while (oldIdx < this.splashSourceImagePaths.length) {
      const oldPath: string = this.splashSourceImagePaths[oldIdx];
      if (oldPath.length > 0 && !merged.includes(oldPath)) {
        merged.push(oldPath);
      }
      oldIdx = oldIdx + 1;
    }
    let newIdx: number = 0;
    while (newIdx < newUris.length) {
      const newPath: string = newUris[newIdx];
      if (newPath.length > 0 && !merged.includes(newPath)) {
        merged.push(newPath);
      }
      newIdx = newIdx + 1;
    }
    return merged;
  }

  private registerSplashSourceIfNeeded(originalPath: string): void {
    if (originalPath.length === 0) {
      return;
    }
    if (!this.splashDraftSelections.has(originalPath)) {
      const draft: BackgroundDraftSelection = {
        originalPath: originalPath,
        appliedPath: ''
      };
      this.splashDraftSelections.set(originalPath, draft);
    }
  }

  private resolveSplashSourcePath(originalPath: string): string {
    const selection: BackgroundDraftSelection | undefined = this.splashDraftSelections.get(originalPath);
    if (selection && selection.appliedPath.length > 0 && fs.accessSync(selection.appliedPath)) {
      return selection.appliedPath;
    }
    return originalPath;
  }

  private async importSplashSourceToDraftIfNeeded(originalPath: string): Promise<void> {
    if (originalPath.length === 0) {
      return;
    }
    this.registerSplashSourceIfNeeded(originalPath);
    const existingSelection: BackgroundDraftSelection | undefined = this.splashDraftSelections.get(originalPath);
    if (existingSelection && existingSelection.appliedPath.length > 0 && fs.accessSync(existingSelection.appliedPath)) {
      return;
    }
    const context = this.uiContext?.getHostContext() as common.UIAbilityContext;
    if (!context) {
      throw new Error('无法获取UIAbilityContext');
    }
    const themesDir: string = `${context.filesDir}/custom_themes`;
    if (!fs.accessSync(themesDir)) {
      fs.mkdirSync(themesDir);
    }
    const draftDir: string = `${themesDir}/splash_drafts`;
    if (!fs.accessSync(draftDir)) {
      fs.mkdirSync(draftDir);
    }
    const targetPath: string = `${draftDir}/source_${Date.now()}_${this.splashSourceImagePaths.indexOf(originalPath) + 1}.webp`;
    let copied: boolean = false;
    if (fs.accessSync(originalPath)) {
      try {
        fs.copyFileSync(originalPath, targetPath);
        copied = true;
      } catch (error) {
        const message: string = error instanceof Error ? error.message : String(error);
        logger.warn(TAG, `复制开屏原图失败，尝试重编码: ${message}`);
      }
    }
    if (!copied) {
      const file = fs.openSync(originalPath, fs.OpenMode.READ_ONLY);
      const imageSource = image.createImageSource(file.fd);
      try {
        const decodingOptions: image.DecodingOptions = {
          desiredPixelFormat: 3
        };
        const sourcePixelMap: image.PixelMap = await imageSource.createPixelMap(decodingOptions);
        try {
          await this.packPixelMapToWebp(sourcePixelMap, targetPath, 88);
        } finally {
          sourcePixelMap.release();
        }
      } finally {
        fs.closeSync(file);
        imageSource.release();
      }
    }
    const nextSelection: BackgroundDraftSelection = {
      originalPath: originalPath,
      appliedPath: targetPath
    };
    this.splashDraftSelections.set(originalPath, nextSelection);
  }

  private async persistActiveSplashDraftCrop(): Promise<void> {
    if (!this.selectedSplashImagePixelMap) {
      return;
    }
    const activePath: string = this.activeSplashSourcePath.length > 0 ? this.activeSplashSourcePath : this.selectedSplashImagePath;
    if (activePath.length === 0) {
      return;
    }
    this.registerSplashSourceIfNeeded(activePath);
    const context = this.uiContext?.getHostContext() as common.UIAbilityContext;
    if (!context) {
      throw new Error('无法获取UIAbilityContext');
    }
    const themesDir: string = `${context.filesDir}/custom_themes`;
    if (!fs.accessSync(themesDir)) {
      fs.mkdirSync(themesDir);
    }
    const draftDir: string = `${themesDir}/splash_drafts`;
    if (!fs.accessSync(draftDir)) {
      fs.mkdirSync(draftDir);
    }
    const oldSelection: BackgroundDraftSelection | undefined = this.splashDraftSelections.get(activePath);
    if (oldSelection && oldSelection.appliedPath.length > 0 && fs.accessSync(oldSelection.appliedPath)) {
      fs.unlinkSync(oldSelection.appliedPath);
    }
    const targetPath: string = `${draftDir}/draft_${Date.now()}_${this.splashSourceImagePaths.indexOf(activePath) + 1}.webp`;
    await this.packPixelMapToWebp(this.selectedSplashImagePixelMap, targetPath, 88);
    const nextSelection: BackgroundDraftSelection = {
      originalPath: activePath,
      appliedPath: targetPath
    };
    this.splashDraftSelections.set(activePath, nextSelection);
  }

  private async switchSplashSourceImage(targetOriginalPath: string): Promise<void> {
    if (targetOriginalPath.length === 0) {
      return;
    }
    try {
      if (this.activeSplashSourcePath === targetOriginalPath && this.selectedSplashImagePixelMap) {
        return;
      }
      const resolvedPath: string = this.resolveSplashSourcePath(targetOriginalPath);
      await this.loadAndProcessSplashImage(resolvedPath, targetOriginalPath);
    } catch (error) {
      const message: string = error instanceof Error ? error.message : String(error);
      logger.error(TAG, `切换开屏草稿失败: ${message}`);
    }
  }

  private async setSplashSourceImages(imageUris: string[]): Promise<void> {
    const normalizedUris: string[] = this.normalizeSplashImageUris(imageUris);
    if (normalizedUris.length === 0) {
      return;
    }
    const mergedSourcePaths: string[] = this.mergeSplashSourcePaths(normalizedUris);
    this.splashSourceImagePaths = mergedSourcePaths;
    let idx: number = 0;
    while (idx < normalizedUris.length) {
      const uri: string = normalizedUris[idx];
      this.registerSplashSourceIfNeeded(uri);
      try {
        await this.importSplashSourceToDraftIfNeeded(uri);
      } catch (error) {
        const message: string = error instanceof Error ? error.message : String(error);
        logger.warn(TAG, `导入开屏原图到草稿失败: ${message}`);
      }
      idx = idx + 1;
    }
    await this.switchSplashSourceImage(normalizedUris[0]);
  }
  private async initializeUserThemeConfig(): Promise<void> {
    try {
      await this.userThemeConfigManager.initialize();
      const profile = this.userThemeConfigManager.getCurrentProfile();
      
      // 同步本地滑块状态（百分比形式）
      this.navBarTransparency = Math.round(profile.transparency.navigationBar * 100);
      this.cardTransparency = Math.round(profile.transparency.card * 100);
      this.dialogTransparency = Math.round(profile.transparency.dialog * 100);
      this.floatingBallTransparency = Math.round(profile.transparency.floatingBall * 100);
      this.effectBlurIntensity = profile.effects.blurIntensity;
      this.effectAnimationSpeed = Math.round(profile.effects.animationSpeed * 100);
      this.effectComponentCornerRadius = profile.effects.componentCornerRadius;
      this.effectCoverCornerRadius = profile.effects.coverCornerRadius;
      this.hdsTabOpacityRatioPercent = Math.round(profile.hdsTabEffects.opacityRatio * 100);
      this.hdsTabMinOpacityPercent = Math.round(profile.hdsTabEffects.minOpacity * 100);
      this.hdsTabMaxOpacityPercent = Math.round(profile.hdsTabEffects.maxOpacity * 100);
      this.hdsTabLightHighlightPercent = Math.round(profile.hdsTabEffects.lightHighlightOpacity * 100);
      this.hdsTabDarkHighlightPercent = Math.round(profile.hdsTabEffects.darkHighlightOpacity * 100);
      this.hdsTabSideMarginValue = profile.hdsTabEffects.sideMargin;
      this.hdsTabBottomMarginValue = profile.hdsTabEffects.bottomMargin;
      
      // StorageLink绑定的值会自动从AppStorage同步，无需手动设置
      logger.info(TAG, '用户主题配置加载完成');
    } catch (error) {
      logger.error(TAG, '初始化用户主题配置失败', error);
    }
  }

  private lifecycle = new PageLifecycleManager('ThemeSettingsPage', { enableDebug: true });

  aboutToDisappear(): void {
    logger.lifecycle(TAG, 'aboutToDisappear');
    this.cleanupSettingsTapGuard();
    SettingsSearchSupport.clearHighlight(this);
    this.lifecycle.destroy();
    ThemeAwareHelper.cleanupThemeAware(TAG);
    FontAwareHelper.cleanupFontAware(TAG);
    
    // 移除设备变化监听器
    if (this.deviceChangeListener) {
      this.deviceManager.removeListener(this.deviceChangeListener);
      this.deviceChangeListener = null;
    }
    
    // 清理防抖定时器
    if (this.effectDebounceTimer !== -1) {
      clearTimeout(this.effectDebounceTimer);
      this.effectDebounceTimer = -1;
    }
    
    // 释放PixelMap资源
    if (this.selectedImagePixelMap) {
      this.selectedImagePixelMap.release();
    }
    if (this.processedImagePixelMap) {
      this.processedImagePixelMap.release();
    }
    if (this.selectedSplashImagePixelMap) {
      this.selectedSplashImagePixelMap.release();
    }
    if (this.processedSplashImagePixelMap) {
      this.processedSplashImagePixelMap.release();
    }
    this.cleanupSplashDraftFiles();
    this.cleanupBackgroundDraftFiles();
    this.selectedImagePixelMap = null;
    this.processedImagePixelMap = null;
    this.selectedSplashImagePixelMap = null;
    this.processedSplashImagePixelMap = null;
    this.selectedImagePixelWidth = 0;
    this.selectedImagePixelHeight = 0;
  }

  /**
   * 初始化响应式布局
   */
  private initializeResponsiveLayout(): void {
    try {
      // 更新响应式参数
      this.updateResponsiveParams();

      // 创建并注册设备变化监听器
      this.deviceChangeListener = (deviceInfo: DeviceInfo) => {
        logger.info(TAG, `设备状态变化: 断点=${deviceInfo.breakpoint}, 方向=${deviceInfo.orientation}`);
        this.updateResponsiveParams();
      };
      
      this.deviceManager.addListener(this.deviceChangeListener);
      
      logger.info(TAG, '✅ 响应式布局初始化完成');
    } catch (error) {
      logger.error(TAG, '响应式布局初始化失败', String(error));
    }
  }

  /**
   * 更新响应式布局参数
   */
  private updateResponsiveParams(): void {
    // 避免结构类型对象在页面中传播：改为使用名义方法返回基础值
    const deviceInfo: DeviceInfo = this.deviceManager.getDeviceInfo() as DeviceInfo;

    // 使用工具类的显式方法，避免依赖 ResponsiveLayoutParams 结构类型
    this.responsive_contentPadding = ResponsiveLayoutHelper.getContentPadding();
    this.responsive_isLandscape = deviceInfo.isLandscape;

    // 最大内容宽度改为直接使用工具类计算结果，保持与断点逻辑一致
    this.responsive_maxContentWidth = ResponsiveLayoutHelper.getMaxContentWidth();
    this.refreshPreviewFrameMetrics(deviceInfo);
    this.clampViewfinderToBounds();
    
    logger.debug(TAG, `响应式参数更新: 内边距=${this.responsive_contentPadding}, 最大宽度=${this.responsive_maxContentWidth}, 预览框=${this.previewFrameWidthVp.toFixed(1)}x${this.previewFrameHeightVp.toFixed(1)}`);
  }

  private normalizeAspectRatio(width: number, height: number): number {
    if (width <= 0 || height <= 0) {
      return 9 / 16;
    }
    const ratio: number = width / height;
    if (!Number.isFinite(ratio) || ratio <= 0) {
      return 9 / 16;
    }
    return ratio;
  }

  private refreshPreviewFrameMetrics(deviceInfo: DeviceInfo): void {
    const ratio: number = this.normalizeAspectRatio(deviceInfo.screenWidthPx, deviceInfo.screenHeightPx);
    this.previewFrameAspectRatio = ratio;

    const safeScreenWidthVp: number = deviceInfo.screenWidth > 0 ? deviceInfo.screenWidth : 360;
    const horizontalPadding: number = this.responsive_contentPadding * 2;
    const availableWidthVp: number = Math.max(220, Math.min(this.responsive_maxContentWidth, safeScreenWidthVp - horizontalPadding));
    const cardRatio: number = this.responsive_isLandscape ? 0.48 : 1.0;
    const cardInnerWidthVp: number = availableWidthVp * cardRatio - 32;
    let frameWidthVp: number = Math.max(this.previewFrameMinWidthVp, Math.min(this.previewFrameMaxWidthVp, cardInnerWidthVp));
    if (!Number.isFinite(frameWidthVp) || frameWidthVp <= 0) {
      frameWidthVp = 220;
    }

    let frameHeightVp: number = frameWidthVp / ratio;
    const maxHeightVp: number = this.responsive_isLandscape ? this.previewFrameLandscapeMaxHeightVp : this.previewFramePortraitMaxHeightVp;
    if (frameHeightVp > maxHeightVp) {
      frameHeightVp = maxHeightVp;
      frameWidthVp = frameHeightVp * ratio;
    }

    this.previewFrameWidthVp = frameWidthVp;
    this.previewFrameHeightVp = frameHeightVp;
  }

  /**
   * 加载已保存的自定义主题
   */
  private async loadCustomThemes(): Promise<void> {
    try {
      const context = this.uiContext?.getHostContext() as common.UIAbilityContext;
      if (!context) {
        logger.error(TAG, '无法获取UIAbilityContext');
        return;
      }
      
      const themesDir = `${context.filesDir}/custom_themes`;
      const themesFile = `${themesDir}/themes.json`;
      
      if (fs.accessSync(themesFile)) {
        const content = fs.readTextSync(themesFile);
        this.customThemes = JSON.parse(content) as CustomTheme[];
        // 媒体资源模式清理：默认/第二自定义主题不保留本地图片路径
        const sanitized: CustomTheme[] = [];
        let j: number = 0;
        while (j < this.customThemes.length) {
          const t: CustomTheme = this.customThemes[j];
          const isBuiltInResourceTheme: boolean = this.isBuiltInResourceThemeId(t.id);
          const splashPaths: string[] = this.getSplashPathsFromTheme(t);
          const splashRule: SplashRotationRule = this.getSplashRotationRuleFromTheme(t);
          const splashCursor: number = t.splashRotationCursor !== undefined ? t.splashRotationCursor : -1;
          const splashDate: string = t.splashRotationLastDateKey ? t.splashRotationLastDateKey : '';
          const hideSplashLogo: boolean = this.getHideSplashLogoFromTheme(t);
          const hideSplashProgress: boolean = this.getHideSplashProgressFromTheme(t);
          const themeMode: CustomThemeMode = this.getThemeModeFromTheme(t);
          const blurLevel: number = t.blurLevel !== undefined ? t.blurLevel : 0;
          const brightness: number = t.brightness !== undefined ? t.brightness : 50;
          const createTime: number = t.createTime !== undefined ? t.createTime : Date.now();
          const lastModified: number = t.lastModified !== undefined ? t.lastModified : createTime;
          const newTheme: CustomTheme = {
            id: t.id,
            name: this.normalizeStoredThemeName(t),
            backgroundImagePath: isBuiltInResourceTheme ? '' : (t.backgroundImagePath ? t.backgroundImagePath : ''),
            backgroundImagePathDark: isBuiltInResourceTheme ? '' : (t.backgroundImagePathDark ? t.backgroundImagePathDark : ''),
            splashBackgroundImagePath: splashPaths.length > 0 ? splashPaths[0] : '',
            splashBackgroundImagePaths: splashPaths,
            splashRotationRule: splashRule,
            splashRotationCursor: splashCursor,
            splashRotationLastDateKey: splashDate,
            hideSplashLogo: hideSplashLogo,
            hideSplashProgress: hideSplashProgress,
            blurLevel: blurLevel,
            brightness: brightness,
            primaryColor: t.primaryColor,
            themeMode: themeMode,
            isDark: themeMode === CustomThemeMode.DARK,
            createTime: createTime,
            lastModified: lastModified
          };
          sanitized.push(newTheme);
          j = j + 1;
        }
        this.customThemes = sanitized;
        logger.info(TAG, `已加载并清理 ${this.customThemes.length} 个自定义主题（媒体资源模式）`);
      }
    } catch (error) {
      logger.error(TAG, `加载自定义主题失败: ${error instanceof Error ? error.message : String(error)}`);
    }
  }

  /**
   * 保存自定义主题
   */
  private async saveCustomTheme(theme: CustomTheme): Promise<void> {
    try {
      const context = this.uiContext?.getHostContext() as common.UIAbilityContext;
      if (!context) {
        throw new Error('无法获取UIAbilityContext');
      }
      
      const themesDir = `${context.filesDir}/custom_themes`;
      const themesFile = `${themesDir}/themes.json`;
      
      // 确保目录存在
      if (!fs.accessSync(themesDir)) {
        fs.mkdirSync(themesDir);
      }
      
      // 添加或更新主题
      const normalizedSplashPaths: string[] = this.getSplashPathsFromTheme(theme);
      const normalizedRule: SplashRotationRule = this.getSplashRotationRuleFromTheme(theme);
      const normalizedThemeMode: CustomThemeMode = this.getThemeModeFromTheme(theme);
      const normalizedTheme: CustomTheme = {
        id: theme.id,
        name: this.normalizeStoredThemeName(theme),
        backgroundImagePath: theme.backgroundImagePath ? theme.backgroundImagePath : '',
        backgroundImagePathDark: theme.backgroundImagePathDark ? theme.backgroundImagePathDark : '',
        splashBackgroundImagePath: normalizedSplashPaths.length > 0 ? normalizedSplashPaths[0] : '',
        splashBackgroundImagePaths: normalizedSplashPaths,
        splashRotationRule: normalizedRule,
        splashRotationCursor: theme.splashRotationCursor !== undefined ? theme.splashRotationCursor : -1,
        splashRotationLastDateKey: theme.splashRotationLastDateKey ? theme.splashRotationLastDateKey : '',
        hideSplashLogo: this.getHideSplashLogoFromTheme(theme),
        hideSplashProgress: this.getHideSplashProgressFromTheme(theme),
        blurLevel: theme.blurLevel,
        brightness: theme.brightness,
        primaryColor: theme.primaryColor,
        themeMode: normalizedThemeMode,
        isDark: normalizedThemeMode === CustomThemeMode.DARK,
        createTime: theme.createTime,
        lastModified: theme.lastModified
      };
      if (this.isBuiltInResourceThemeId(normalizedTheme.id)) {
        normalizedTheme.backgroundImagePath = '';
        normalizedTheme.backgroundImagePathDark = '';
      }
      const existingIndex = this.customThemes.findIndex(t => t.id === theme.id);
      if (existingIndex >= 0) {
        this.customThemes[existingIndex] = normalizedTheme;
      } else {
        this.customThemes.push(normalizedTheme);
      }
      
      // 保存到文件
      const file = fs.openSync(themesFile, fs.OpenMode.CREATE | fs.OpenMode.WRITE_ONLY | fs.OpenMode.TRUNC);
      fs.writeSync(file.fd, JSON.stringify(this.customThemes));
      fs.closeSync(file);
      logger.info(TAG, `已保存自定义主题: ${normalizedTheme.name}`);
    } catch (error) {
      const errorMsg = error instanceof Error ? error.message : String(error);
      logger.error(TAG, `保存自定义主题失败: ${errorMsg}`);
      throw new Error(`保存自定义主题失败: ${errorMsg}`);
    }
  }

  private normalizeThemePreviewPath(rawPath: string): string {
    if (rawPath.startsWith('file://')) {
      return rawPath;
    }
    if (rawPath.startsWith('/')) {
      return `file://${rawPath}`;
    }
    return rawPath;
  }

  private resolveThemePreviewSource(theme: CustomTheme): string | ResourceStr {
    const preferredPath: string = this.themeState.currentTheme === ThemeType.DARK
      && theme.backgroundImagePathDark
      && theme.backgroundImagePathDark.length > 0
      ? theme.backgroundImagePathDark
      : theme.backgroundImagePath;
    if (preferredPath && preferredPath.length > 0) {
      return this.normalizeThemePreviewPath(preferredPath);
    }
    if (theme.id === this.DEFAULT_THEME_ID) {
      return BuiltInThemeResources.resolvePreviewResource(theme.id);
    }
    if (theme.id === this.SECONDARY_THEME_ID) {
      return BuiltInThemeResources.resolvePreviewResource(theme.id);
    }
    if (theme.id === this.CAT_DARK_THEME_ID) {
      return BuiltInThemeResources.resolvePreviewResource(theme.id);
    }
    return '';
  }

  /**
   * 持久化当前自定义主题列表到文件
   */
  private async persistCustomThemesList(): Promise<void> {
    try {
      const context = this.uiContext?.getHostContext() as common.UIAbilityContext;
      if (!context) {
        throw new Error('无法获取UIAbilityContext');
      }
      const themesDir: string = `${context.filesDir}/custom_themes`;
      const themesFile: string = `${themesDir}/themes.json`;
      if (!fs.accessSync(themesDir)) {
        fs.mkdirSync(themesDir);
      }
      const sanitizedThemes: CustomTheme[] = [];
      let idx: number = 0;
      while (idx < this.customThemes.length) {
        const sourceTheme: CustomTheme = this.customThemes[idx];
        const splashPaths: string[] = this.getSplashPathsFromTheme(sourceTheme);
        const sanitizedThemeMode: CustomThemeMode = this.getThemeModeFromTheme(sourceTheme);
        const sanitizedTheme: CustomTheme = {
          id: sourceTheme.id,
          name: this.normalizeStoredThemeName(sourceTheme),
          backgroundImagePath: sourceTheme.backgroundImagePath ? sourceTheme.backgroundImagePath : '',
          backgroundImagePathDark: sourceTheme.backgroundImagePathDark ? sourceTheme.backgroundImagePathDark : '',
          splashBackgroundImagePath: splashPaths.length > 0 ? splashPaths[0] : '',
          splashBackgroundImagePaths: splashPaths,
          splashRotationRule: this.getSplashRotationRuleFromTheme(sourceTheme),
          splashRotationCursor: sourceTheme.splashRotationCursor !== undefined ? sourceTheme.splashRotationCursor : -1,
          splashRotationLastDateKey: sourceTheme.splashRotationLastDateKey ? sourceTheme.splashRotationLastDateKey : '',
          hideSplashLogo: this.getHideSplashLogoFromTheme(sourceTheme),
          hideSplashProgress: this.getHideSplashProgressFromTheme(sourceTheme),
          blurLevel: sourceTheme.blurLevel,
          brightness: sourceTheme.brightness,
          primaryColor: sourceTheme.primaryColor,
          themeMode: sanitizedThemeMode,
          isDark: sanitizedThemeMode === CustomThemeMode.DARK,
          createTime: sourceTheme.createTime,
          lastModified: sourceTheme.lastModified
        };
        if (this.isBuiltInResourceThemeId(sanitizedTheme.id)) {
          sanitizedTheme.backgroundImagePath = '';
          sanitizedTheme.backgroundImagePathDark = '';
        }
        sanitizedThemes.push(sanitizedTheme);
        idx = idx + 1;
      }
      this.customThemes = sanitizedThemes;
      const file = fs.openSync(themesFile, fs.OpenMode.CREATE | fs.OpenMode.WRITE_ONLY | fs.OpenMode.TRUNC);
      fs.writeSync(file.fd, JSON.stringify(this.customThemes));
      fs.closeSync(file);
      logger.info(TAG, '✅ 自定义主题列表已持久化');
    } catch (error) {
      const errorMsg = error instanceof Error ? error.message : String(error);
      logger.error(TAG, `持久化主题列表失败: ${errorMsg}`);
      throw new Error(`持久化主题列表失败: ${errorMsg}`);
    }
  }

  /**
   * 判断主题是否被选中
   */
  private isThemeSelected(themeId: string): boolean {
    const index: number = this.selectedThemeIds.indexOf(themeId);
    return index >= 0;
  }

  /**
   * 切换主题选择状态（长按/点击）
   */
  private toggleThemeSelection(themeId: string): void {
    if (!this.selectionModeEnabled) {
      this.selectionModeEnabled = true;
    }
    const index: number = this.selectedThemeIds.indexOf(themeId);
    if (index >= 0) {
      // 取消选择
      const newSelected: string[] = [];
      let i: number = 0;
      while (i < this.selectedThemeIds.length) {
        const id: string = this.selectedThemeIds[i];
        if (id !== themeId) {
          newSelected.push(id);
        }
        i = i + 1;
      }
      this.selectedThemeIds = newSelected;
    } else {
      // 添加选择
      const newSelected: string[] = [];
      let j: number = 0;
      while (j < this.selectedThemeIds.length) {
        newSelected.push(this.selectedThemeIds[j]);
        j = j + 1;
      }
      newSelected.push(themeId);
      this.selectedThemeIds = newSelected;
    }
  }

  /**
   * 退出选择模式并清空选择
   */
  private exitSelectionMode(): void {
    this.selectionModeEnabled = false;
    const emptyList: string[] = [];
    this.selectedThemeIds = emptyList;
  }

  /**
   * 删除已选中的自定义主题（含图片文件与列表项）
   */
  private async deleteSelectedThemes(): Promise<void> {
    try {
      if (this.selectedThemeIds.length === 0) {
        logger.warn(TAG, '没有选中的主题可删除');
        return;
      }
      const context = this.uiContext?.getHostContext() as common.UIAbilityContext;
      if (!context) {
        throw new Error('无法获取UIAbilityContext');
      }
      const themesDir: string = `${context.filesDir}/custom_themes`;

      // 构建保留列表
      const remainThemes: CustomTheme[] = [];
      let idx: number = 0;
      while (idx < this.customThemes.length) {
        const theme: CustomTheme = this.customThemes[idx];
        const selected: boolean = this.isThemeSelected(theme.id);
        if (selected) {
          // 删除关联文件
          if (theme.backgroundImagePath && theme.backgroundImagePath.length > 0 && fs.accessSync(theme.backgroundImagePath)) {
            fs.unlinkSync(theme.backgroundImagePath);
            logger.info(TAG, `已删除浅色背景: ${theme.backgroundImagePath}`);
          }
          if (theme.backgroundImagePathDark && theme.backgroundImagePathDark.length > 0 && fs.accessSync(theme.backgroundImagePathDark)) {
            fs.unlinkSync(theme.backgroundImagePathDark);
            logger.info(TAG, `已删除深色背景: ${theme.backgroundImagePathDark}`);
          } else {
            // 兼容旧版本可能使用文件名约定
            const darkCandidate: string = `${themesDir}/${theme.id}_dark.webp`;
            if (fs.accessSync(darkCandidate)) {
              fs.unlinkSync(darkCandidate);
              logger.info(TAG, `已删除深色背景(兼容路径): ${darkCandidate}`);
            }
          }
          if (theme.splashBackgroundImagePath && theme.splashBackgroundImagePath.length > 0 && fs.accessSync(theme.splashBackgroundImagePath)) {
            fs.unlinkSync(theme.splashBackgroundImagePath);
            logger.info(TAG, `已删除开屏背景: ${theme.splashBackgroundImagePath}`);
          }
          const splashPathsToDelete: string[] = this.getSplashPathsFromTheme(theme);
          let splashIdx: number = 0;
          while (splashIdx < splashPathsToDelete.length) {
            const splashPath: string = splashPathsToDelete[splashIdx];
            if (splashPath.length > 0 && splashPath !== theme.splashBackgroundImagePath && fs.accessSync(splashPath)) {
              fs.unlinkSync(splashPath);
              logger.info(TAG, `已删除开屏背景(列表): ${splashPath}`);
            }
            splashIdx = splashIdx + 1;
          }

          // 若当前激活主题被删除，则清除自定义主题状态
          if (this.currentCustomThemeId === theme.id) {
            await this.themeManager.clearCustomTheme();
            this.currentCustomThemeId = '';
            logger.info(TAG, `当前激活主题已删除，已清除自定义主题状态`);
          }
        } else {
          remainThemes.push(theme);
        }
        idx = idx + 1;
      }

      // 更新内存并持久化
      this.customThemes = remainThemes;
      await this.persistCustomThemesList();
      // 退出选择模式
      this.exitSelectionMode();
      logger.info(TAG, '✅ 已删除选中的自定义主题');
    } catch (error) {
      const errorMsg = error instanceof Error ? error.message : String(error);
      logger.error(TAG, `删除自定义主题失败: ${errorMsg}`);
    }
  }

  /**
   * 确保默认自定义主题已初始化（首次缺失则创建并写入列表）
   */
  private async ensureDefaultCustomThemeInitialized(): Promise<void> {
    try {
      const context = this.uiContext?.getHostContext() as common.UIAbilityContext;
      if (!context) {
        logger.error(TAG, '无法获取UIAbilityContext');
        return;
      }
      const themesDir: string = `${context.filesDir}/custom_themes`;
      const themesFile: string = `${themesDir}/themes.json`;

      if (!fs.accessSync(themesDir)) {
        fs.mkdirSync(themesDir);
      }

      // 检查默认主题是否已存在
      let exists: boolean = false;
      let idx: number = 0;
      while (idx < this.customThemes.length) {
        const themeItem: CustomTheme = this.customThemes[idx];
        if (themeItem.id === this.DEFAULT_THEME_ID) {
          exists = true;
          break;
        }
        idx = idx + 1;
      }

      if (exists) {
        logger.debug(TAG, '默认自定义主题已存在，跳过初始化');
      } else {
        // 创建默认自定义主题（按设备类型选择 a_* 背景，失败则回退透明）
        const created: CustomTheme = await this.createDefaultCustomTheme();
        await this.saveCustomTheme(created);
        logger.info(TAG, '✅ 默认自定义主题已初始化并写入列表');
      }

      // [修复] 移除自动应用逻辑，避免强制用户使用自定义主题
      // 用户应该主动选择是否使用自定义主题，而不是被动强制应用

      // （移除分支内的第二主题初始化，改为在方法末统一执行）
    } catch (error) {
      logger.error(TAG, `默认主题初始化失败: ${error instanceof Error ? error.message : String(error)}`);
    }
    // 在默认主题流程结束后，确保第二自定义主题也初始化
    await this.ensureSecondaryCustomThemeInitialized();
    await this.ensureCatDarkCustomThemeInitialized();
  }

  /**
   * 生成透明的 WebP 图片，确保图片加载不出错
   */
  private async generateTransparentWebP(imagePath: string, width: number, height: number): Promise<void> {
    const w: number = width > 0 ? width : 16;
    const h: number = height > 0 ? height : 16;
    const bufferSize: number = w * h * 4;
    const rgba: ArrayBuffer = new ArrayBuffer(bufferSize);
    const rgbaView: Uint8Array = new Uint8Array(rgba);
    // 全透明：RGBA = (0,0,0,0)
    let i: number = 0;
    while (i < bufferSize) {
      rgbaView[i] = 0;      // R
      rgbaView[i + 1] = 0;  // G
      rgbaView[i + 2] = 0;  // B
      rgbaView[i + 3] = 0;  // A
      i = i + 4;
    }

    const initOpts: image.InitializationOptions = {
      size: { width: w, height: h },
      pixelFormat: 3, // RGBA_8888
      alphaType: 0,
      editable: false
    };

    const pixelMap: image.PixelMap = await image.createPixelMap(rgba, initOpts);
    const packOpts: image.PackingOption = {
      format: 'image/webp',
      quality: 85
    };

    const imagePacker = image.createImagePacker();
    const file = fs.openSync(imagePath, fs.OpenMode.CREATE | fs.OpenMode.WRITE_ONLY | fs.OpenMode.TRUNC);
    await imagePacker.packToFile(pixelMap, file.fd, packOpts);
    fs.closeSync(file);
    imagePacker.release();
    pixelMap.release();
  }

  /**
   * 创建默认自定义主题（透明背景），并返回主题对象
   */
  private async createDefaultCustomTheme(): Promise<CustomTheme> {
    const context = this.uiContext?.getHostContext() as common.UIAbilityContext;
    if (!context) {
      throw new Error('无法获取UIAbilityContext');
    }
    // 改为使用媒体资源（app.media.a_*）进行显示，不再复制rawfile到文件目录
    // 为保持现有存储结构与类型安全，路径字段置为空字符串，显示层通过资源回退逻辑加载媒体资源
    const now: number = Date.now();
    const primaryColor: string = THEME_CONFIGS[ThemeType.LIGHT].primaryColor;
    const created: CustomTheme = {
      id: this.DEFAULT_THEME_ID,
      name: this.DEFAULT_THEME_NAME,
      backgroundImagePath: '',
      backgroundImagePathDark: '',
      splashBackgroundImagePath: '',
      splashBackgroundImagePaths: [],
      splashRotationRule: SplashRotationRule.FIXED_FIRST,
      splashRotationCursor: -1,
      splashRotationLastDateKey: '',
      hideSplashLogo: false,
      hideSplashProgress: false,
      blurLevel: 0,
      brightness: 50,
      primaryColor: primaryColor,
      themeMode: CustomThemeMode.AUTO,
      isDark: false,
      createTime: now,
      lastModified: now
    };
    return created;
  }

  /**
   * 确保第二自定义主题已存在；不存在则按设备类型创建（b_* 背景）
   */
  private async ensureSecondaryCustomThemeInitialized(): Promise<void> {
    const context = this.uiContext?.getHostContext() as common.UIAbilityContext;
    if (!context) {
      logger.error(TAG, '无法获取UIAbilityContext');
      return;
    }
    const themesDir: string = `${context.filesDir}/custom_themes`;
    if (!fs.accessSync(themesDir)) {
      fs.mkdirSync(themesDir);
    }

    // 检查是否已存在
    let exists: boolean = false;
    let i: number = 0;
    while (i < this.customThemes.length) {
      const t: CustomTheme = this.customThemes[i];
      if (t.id === this.SECONDARY_THEME_ID) {
        exists = true;
        break;
      }
      i = i + 1;
    }
    if (exists) {
      logger.debug(TAG, '第二自定义主题已存在，跳过创建');
      return;
    }

    // 改为使用媒体资源（app.media.b_*）进行显示，不再复制rawfile到文件目录
    const now: number = Date.now();
    const primaryColor: string = THEME_CONFIGS[ThemeType.DARK].primaryColor;
    const created: CustomTheme = {
      id: this.SECONDARY_THEME_ID,
      name: this.SECONDARY_THEME_NAME,
      backgroundImagePath: '',
      backgroundImagePathDark: '',
      splashBackgroundImagePath: '',
      splashBackgroundImagePaths: [],
      splashRotationRule: SplashRotationRule.FIXED_FIRST,
      splashRotationCursor: -1,
      splashRotationLastDateKey: '',
      hideSplashLogo: false,
      hideSplashProgress: false,
      blurLevel: 0,
      brightness: 50,
      primaryColor: primaryColor,
      themeMode: CustomThemeMode.DARK,
      isDark: true,
      createTime: now,
      lastModified: now
    };
    await this.saveCustomTheme(created);
    logger.info(TAG, '✅ 已创建第二自定义主题（媒体资源 b_*）并写入列表');
  }

  private async ensureCatDarkCustomThemeInitialized(): Promise<void> {
    const context = this.uiContext?.getHostContext() as common.UIAbilityContext;
    if (!context) {
      logger.error(TAG, '无法获取UIAbilityContext');
      return;
    }
    const themesDir: string = `${context.filesDir}/custom_themes`;
    if (!fs.accessSync(themesDir)) {
      fs.mkdirSync(themesDir);
    }

    let exists: boolean = false;
    let i: number = 0;
    while (i < this.customThemes.length) {
      const t: CustomTheme = this.customThemes[i];
      if (t.id === this.CAT_DARK_THEME_ID) {
        exists = true;
        break;
      }
      i = i + 1;
    }
    if (exists) {
      logger.debug(TAG, '猫猫深色主题已存在，跳过创建');
      return;
    }

    const now: number = Date.now();
    const primaryColor: string = THEME_CONFIGS[ThemeType.DARK].primaryColor;
    const created: CustomTheme = {
      id: this.CAT_DARK_THEME_ID,
      name: this.CAT_DARK_THEME_NAME,
      backgroundImagePath: '',
      backgroundImagePathDark: '',
      splashBackgroundImagePath: '',
      splashBackgroundImagePaths: [],
      splashRotationRule: SplashRotationRule.FIXED_FIRST,
      splashRotationCursor: -1,
      splashRotationLastDateKey: '',
      hideSplashLogo: false,
      hideSplashProgress: false,
      blurLevel: 0,
      brightness: 50,
      primaryColor: primaryColor,
      themeMode: CustomThemeMode.DARK,
      isDark: true,
      createTime: now,
      lastModified: now
    };
    await this.saveCustomTheme(created);
    logger.info(TAG, '✅ 已创建猫猫深色主题（媒体资源 cat_dark_*）并写入列表');
  }

  /**
   * 恢复默认自定义主题：若被删除则重新创建并自动应用
   */
  private async restoreDefaultCustomTheme(): Promise<void> {
    try {
      const context = this.uiContext?.getHostContext() as common.UIAbilityContext;
      if (!context) {
        throw new Error('无法获取UIAbilityContext');
      }
      const themesDir: string = `${context.filesDir}/custom_themes`;
      const themesFile: string = `${themesDir}/themes.json`;
      if (!fs.accessSync(themesDir)) {
        fs.mkdirSync(themesDir);
      }

      // 查找默认主题
      let index: number = -1;
      let i: number = 0;
      while (i < this.customThemes.length) {
        if (this.customThemes[i].id === this.DEFAULT_THEME_ID) {
          index = i;
          break;
        }
        i = i + 1;
      }

      let targetTheme: CustomTheme | null = null;
      if (index >= 0) {
        // 已存在，直接应用（背景路径可能为空，由显示层采用媒体资源回退）
        targetTheme = this.customThemes[index];
        targetTheme.name = this.normalizeStoredThemeName(targetTheme);
      } else {
        // 不存在则创建（媒体资源模式）
        const created: CustomTheme = await this.createDefaultCustomTheme();
        await this.saveCustomTheme(created);
        targetTheme = created;
      }

      if (targetTheme) {
        await this.applyCustomThemeToManager(targetTheme);
        logger.info(TAG, '✅ 已恢复并应用默认自定义主题（媒体资源模式）');
      }
    } catch (error) {
      const errorMsg: string = error instanceof Error ? error.message : String(error);
      logger.error(TAG, `恢复默认主题失败: ${errorMsg}`);
    }
  }

  /**
   * 选择图片
   */
  private async selectImage(): Promise<void> {
    try {
      logger.info(TAG, '开始选择图片');
      
      const context = this.uiContext?.getHostContext() as common.UIAbilityContext;
      if (!context) {
        throw new Error('无法获取UIAbilityContext');
      }
      
      const photoSelectOptions: photoAccessHelper.PhotoSelectOptions = {
        MIMEType: photoAccessHelper.PhotoViewMIMETypes.IMAGE_TYPE,
        maxSelectNumber: 12
      };
      
      const photoPicker = new photoAccessHelper.PhotoViewPicker();
      const result = await photoPicker.select(photoSelectOptions);
      
      if (result && result.photoUris && result.photoUris.length > 0) {
        logger.info(TAG, `已选择背景图片数量: ${result.photoUris.length}`);
        await this.setBackgroundDraftImages(result.photoUris);
      }
    } catch (error) {
      logger.error(TAG, `选择图片失败: ${error instanceof Error ? error.message : String(error)}`);
    }
  }

  /**
   * 加载并处理图片
   */
  private async loadAndProcessImage(imageUri: string, draftOriginalPath?: string): Promise<void> {
    this.isProcessing = true;
    this.processingMessage = '正在加载图片...';
    this.processingProgress = 10;
    
    try {
      // 打开图片文件
      const file = fs.openSync(imageUri, fs.OpenMode.READ_ONLY);
      const imageSource = image.createImageSource(file.fd);
      try {
        // 获取图片信息
        const imageInfo = await imageSource.getImageInfo();
        logger.info(TAG, `图片尺寸: ${imageInfo.size.width}x${imageInfo.size.height}`);
        
        this.processingProgress = 30;
        this.processingMessage = '正在准备裁剪...';
        
        // 计算目标尺寸（使用720p分辨率，足够用于背景且文件小）
        // 使用较小的分辨率可以显著减小文件大小，提升性能
        const maxWidth = 720;
        const maxHeight = 1280;
        const targetSize = this.calculateTargetSize(
          imageInfo.size.width,
          imageInfo.size.height,
          maxWidth,
          maxHeight
        );
        const targetWidth = targetSize.targetWidth;
        const targetHeight = targetSize.targetHeight;
        
        logger.info(TAG, `目标尺寸: ${targetWidth}x${targetHeight}`);
        
        // 解码并缩放图片（不立即裁剪，进入裁剪阶段）
        const decodingOptions: image.DecodingOptions = {
          desiredSize: { width: targetWidth, height: targetHeight },
          desiredPixelFormat: 3 // RGBA_8888
        };
        
        const decodedPixelMap = await imageSource.createPixelMap(decodingOptions);
        if (this.selectedImagePixelMap) {
          this.selectedImagePixelMap.release();
        }
        if (this.processedImagePixelMap) {
          this.processedImagePixelMap.release();
        }
        const activeDraftPath: string = draftOriginalPath && draftOriginalPath.length > 0 ? draftOriginalPath : imageUri;
        this.activeBackgroundDraftPath = activeDraftPath;
        if (!this.backgroundDraftImagePaths.includes(activeDraftPath)) {
          const nextDraftPaths: string[] = [];
          let pathIdx: number = 0;
          while (pathIdx < this.backgroundDraftImagePaths.length) {
            nextDraftPaths.push(this.backgroundDraftImagePaths[pathIdx]);
            pathIdx = pathIdx + 1;
          }
          nextDraftPaths.push(activeDraftPath);
          this.backgroundDraftImagePaths = nextDraftPaths;
        }
        this.registerBackgroundDraftIfNeeded(activeDraftPath);
        this.selectedImagePixelMap = decodedPixelMap;
        this.selectedImagePath = activeDraftPath;
        this.cropAlignment = CropAlignment.CENTER;
        this.cropZoom = 1.0;
        this.backgroundRotateQuarterTurns = 0;
        await this.syncSelectedImagePixelSize(this.selectedImagePixelMap);
        this.resetBackgroundViewfinder();
      } finally {
        fs.closeSync(file);
        imageSource.release();
      }
      
      // 直接进行主色调提取（不进入自定义裁剪阶段）
      this.processingProgress = 60;
      this.processingMessage = '正在提取主色调...';
      await this.extractDominantColor(this.selectedImagePixelMap);
      
      // 复制原图作为处理结果（默认无效果）
      this.processingProgress = 80;
      this.processingMessage = '正在准备预览...';
      await this.copyOriginalToProcessed();
      
      this.isCropping = false;
      this.processingProgress = 100;
      this.processingMessage = '图片已准备就绪';
      
      setTimeout(() => {
        this.isProcessing = false;
      }, 300);
      
    } catch (error) {
      logger.error(TAG, `处理图片失败: ${error instanceof Error ? error.message : String(error)}`);
      this.isProcessing = false;
      this.processingMessage = '处理失败';
    }
  }

  /**
   * 应用裁剪（用户确认裁剪后执行），随后进行主色提取与效果预处理
   */
  private async applyCrop(): Promise<void> {
    if (!this.selectedImagePixelMap) {
      logger.error(TAG, 'applyCrop: selectedImagePixelMap为空');
      return;
    }
    try {
      this.isProcessing = true;
      this.processingMessage = '正在裁剪图片...';
      this.processingProgress = 40;

      const nextPixelMap: image.PixelMap = await this.buildBackgroundPreviewPixelMap(this.selectedImagePixelMap);
      this.selectedImagePixelMap.release();
      this.selectedImagePixelMap = nextPixelMap;
      await this.syncSelectedImagePixelSize(this.selectedImagePixelMap);
      this.resetBackgroundViewfinder();
      await this.persistActiveBackgroundDraftCrop();

      this.processingProgress = 70;
      this.processingMessage = '正在提取主色调...';
      await this.extractDominantColor(this.selectedImagePixelMap);

      this.processingProgress = 90;
      this.processingMessage = '正在应用预览效果...';
      await this.applyImageEffects();

      this.isCropping = false;
      this.processingProgress = 100;
      this.processingMessage = '裁剪完成';

      setTimeout(() => { this.isProcessing = false; }, 300);
    } catch (error) {
      const msg = error instanceof Error ? error.message : String(error);
      logger.error(TAG, `应用裁剪失败: ${msg}`);
      this.isProcessing = false;
    }
  }

  private async applySplashCrop(): Promise<void> {
    if (!this.selectedSplashImagePixelMap) {
      logger.error(TAG, 'applySplashCrop: selectedSplashImagePixelMap为空');
      return;
    }
    try {
      this.isProcessing = true;
      this.processingMessage = '正在裁剪开屏图片...';
      this.processingProgress = 40;
      const nextPixelMap: image.PixelMap = await this.buildSplashPreviewPixelMap(this.selectedSplashImagePixelMap);
      this.selectedSplashImagePixelMap.release();
      this.selectedSplashImagePixelMap = nextPixelMap;
      await this.syncSelectedSplashPixelSize(this.selectedSplashImagePixelMap);
      this.resetSplashViewfinder();
      if (this.processedSplashImagePixelMap) {
        this.processedSplashImagePixelMap.release();
      }
      const previewCopy: image.PixelMap = await this.rotatePixelMapByQuarterTurns(this.selectedSplashImagePixelMap, 0);
      this.processedSplashImagePixelMap = previewCopy;
      this.processedSplashImagePath = this.selectedSplashImagePath;
      await this.persistActiveSplashDraftCrop();
      this.processingProgress = 100;
      this.processingMessage = '开屏裁剪完成';
      setTimeout(() => { this.isProcessing = false; }, 220);
    } catch (error) {
      const msg: string = error instanceof Error ? error.message : String(error);
      logger.error(TAG, `应用开屏裁剪失败: ${msg}`);
      this.isProcessing = false;
    }
  }

  /**
   * 预览裁剪效果（不修改原图，仅生成预览处理结果）
   */
  private async previewCrop(): Promise<void> {
    if (!this.selectedImagePixelMap) {
      logger.error(TAG, 'previewCrop: selectedImagePixelMap为空');
      return;
    }
    try {
      this.isProcessing = true;
      this.processingMessage = '正在预览裁剪效果...';
      this.processingProgress = 30;
      const previewPixelMap: image.PixelMap = await this.buildBackgroundPreviewPixelMap(this.selectedImagePixelMap);
      try {
        this.processingProgress = 70;
        await this.applyImageEffects(previewPixelMap);
      } finally {
        previewPixelMap.release();
      }
      this.processingProgress = 100;
      this.processingMessage = '裁剪预览完成';
      setTimeout(() => { this.isProcessing = false; }, 200);
    } catch (error) {
      const msg = error instanceof Error ? error.message : String(error);
      logger.error(TAG, `预览裁剪失败: ${msg}`);
      this.isProcessing = false;
    }
  }

  /**
   * 选择开屏图片
   */
  private async selectSplashImage(): Promise<void> {
    try {
      logger.info(TAG, '开始选择开屏图片');
      const context = this.uiContext?.getHostContext() as common.UIAbilityContext;
      if (!context) {
        throw new Error('无法获取UIAbilityContext');
      }

      const photoSelectOptions: photoAccessHelper.PhotoSelectOptions = {
        MIMEType: photoAccessHelper.PhotoViewMIMETypes.IMAGE_TYPE,
        maxSelectNumber: 12
      };

      const photoPicker = new photoAccessHelper.PhotoViewPicker();
      const result = await photoPicker.select(photoSelectOptions);

      if (result && result.photoUris && result.photoUris.length > 0) {
        logger.info(TAG, `已选择开屏图片数量: ${result.photoUris.length}`);
        await this.setSplashSourceImages(result.photoUris);
      }
    } catch (error) {
      logger.error(TAG, `选择开屏图片失败: ${error instanceof Error ? error.message : String(error)}`);
    }
  }

  /**
   * 加载并处理开屏图片（仅裁剪到设备比例）
   */
  private async loadAndProcessSplashImage(imageUri: string, sourceOriginalPath?: string): Promise<void> {
    this.isProcessing = true;
    this.processingMessage = '正在加载开屏图片...';
    this.processingProgress = 10;

    try {
      const file = fs.openSync(imageUri, fs.OpenMode.READ_ONLY);
      const imageSource = image.createImageSource(file.fd);
      try {
        const imageInfo = await imageSource.getImageInfo();
        logger.info(TAG, `开屏图片尺寸: ${imageInfo.size.width}x${imageInfo.size.height}`);

        this.processingProgress = 40;
        this.processingMessage = '正在裁剪开屏图片...';

        const maxWidth = 1080; // 开屏图片保存更高分辨率以保证品质
        const maxHeight = 1920;
        const targetSize = this.calculateTargetSize(imageInfo.size.width, imageInfo.size.height, maxWidth, maxHeight);
        const decodingOptions: image.DecodingOptions = {
          desiredSize: { width: targetSize.targetWidth, height: targetSize.targetHeight },
          desiredPixelFormat: 3
        };

        const decodedPixelMap = await imageSource.createPixelMap(decodingOptions);
        this.clearCurrentSplashSelection();
        const activeSourcePath: string = sourceOriginalPath && sourceOriginalPath.length > 0 ? sourceOriginalPath : imageUri;
        this.activeSplashSourcePath = activeSourcePath;
        if (!this.splashSourceImagePaths.includes(activeSourcePath)) {
          const nextSourcePaths: string[] = [];
          let pathIdx: number = 0;
          while (pathIdx < this.splashSourceImagePaths.length) {
            nextSourcePaths.push(this.splashSourceImagePaths[pathIdx]);
            pathIdx = pathIdx + 1;
          }
          nextSourcePaths.push(activeSourcePath);
          this.splashSourceImagePaths = nextSourcePaths;
        }
        this.registerSplashSourceIfNeeded(activeSourcePath);
        this.selectedSplashImagePixelMap = decodedPixelMap;
        this.selectedSplashImagePath = activeSourcePath;
        await this.syncSelectedSplashPixelSize(this.selectedSplashImagePixelMap);
        this.resetSplashViewfinder();
        await this.refreshSplashPreviewFromSelection();

        this.processingProgress = 100;
        this.processingMessage = '开屏图片处理完成';
      } finally {
        fs.closeSync(file);
        imageSource.release();
      }
      setTimeout(() => { this.isProcessing = false; }, 300);
    } catch (error) {
      logger.error(TAG, `处理开屏图片失败: ${error instanceof Error ? error.message : String(error)}`);
      this.isProcessing = false;
      this.processingMessage = '开屏图片处理失败';
    }
  }

  /**
   * 计算目标尺寸（保持宽高比，适配到最大尺寸内）
   */
  private calculateTargetSize(
    srcWidth: number,
    srcHeight: number,
    maxWidth: number,
    maxHeight: number
  ): TargetSize {
    // 计算缩放比例，确保图片完全适配到最大尺寸内
    const widthScale = maxWidth / srcWidth;
    const heightScale = maxHeight / srcHeight;
    
    // 取较小的缩放比例，确保图片不超出边界
    const scale = Math.min(widthScale, heightScale, 1.0); // 最大1.0，避免放大
    
    const resultWidth = Math.round(srcWidth * scale);
    const resultHeight = Math.round(srcHeight * scale);
    
    const result: TargetSize = {
      targetWidth: resultWidth,
      targetHeight: resultHeight
    };
    return result;
  }

  /**
   * 提取主色调
   * 使用effectKit的ColorPicker硬件加速，避免手动像素处理导致ANR
   */
  private async extractDominantColor(pixelMap: image.PixelMap): Promise<void> {
    try {
      logger.info(TAG, '开始提取主色调（使用effectKit）');
      
      // 使用effectKit的ColorPicker提取主色调
      // createColorPicker返回Promise<ColorPicker>
      const colorPicker = await effectKit.createColorPicker(pixelMap);
      
      // getMainColorSync 返回一个Promise<Color>
      const mainColor = await colorPicker.getMainColorSync();
      
      // Color对象包含red, green, blue, alpha属性（0-255）
      const r = mainColor.red;
      const g = mainColor.green;
      const b = mainColor.blue;
      
      logger.info(TAG, `提取的原始颜色: RGB(${r}, ${g}, ${b})`);
      
      // 增强饱和度
      const enhancedColor = this.enhanceSaturation(r, g, b, 1.3);
      const enhancedR = enhancedColor.r;
      const enhancedG = enhancedColor.g;
      const enhancedB = enhancedColor.b;
      
      this.extractedColor = `#${this.toHex(enhancedR)}${this.toHex(enhancedG)}${this.toHex(enhancedB)}`;
      this.extractedColorRGB = `RGB(${enhancedR}, ${enhancedG}, ${enhancedB})`;
      
      logger.info(TAG, `提取的主色调（增强后）: ${this.extractedColor}`);

      // 将提取色加入可选主题色并默认选中（避免重复添加）
      const hasColor: boolean = this.availablePrimaryColors.includes(this.extractedColor);
      if (!hasColor) {
        const updatedColors: string[] = [];
        let idx: number = 0;
        while (idx < this.availablePrimaryColors.length) {
          updatedColors.push(this.availablePrimaryColors[idx]);
          idx = idx + 1;
        }
        updatedColors.push(this.extractedColor);
        this.availablePrimaryColors = updatedColors;
      }
      this.selectedPrimaryColor = this.extractedColor;
      this.syncCustomColorEditor(this.selectedPrimaryColor);
    } catch (error) {
      const errorMsg = error instanceof Error ? error.message : String(error);
      logger.error(TAG, `提取主色调失败: ${errorMsg}`);
      
      // 失败时使用默认颜色
      this.extractedColor = '#6200EE';
      this.extractedColorRGB = 'RGB(98, 0, 238)';
      
      // 不再抛出错误，避免中断流程
      logger.warn(TAG, '已使用默认主色调继续处理');
    }
  }

  /**
   * 增强饱和度
   */
  private enhanceSaturation(r: number, g: number, b: number, factor: number): RGBColor {
    // 转换到HSV
    const max = Math.max(r, g, b);
    const min = Math.min(r, g, b);
    const delta = max - min;
    
    if (delta === 0) {
      const result: RGBColor = { r, g, b }; // 灰色，无需增强
      return result;
    }
    
    const saturation = delta / max;
    const newSaturation = Math.min(1, saturation * factor);
    
    const scale = newSaturation / saturation;
    const gray = (r + g + b) / 3;
    
    const result: RGBColor = {
      r: Math.round(Math.max(0, Math.min(255, gray + (r - gray) * scale))),
      g: Math.round(Math.max(0, Math.min(255, gray + (g - gray) * scale))),
      b: Math.round(Math.max(0, Math.min(255, gray + (b - gray) * scale)))
    };
    return result;
  }

  /**
   * 转换为十六进制
   */
  private toHex(value: number): string {
    const hex = value.toString(16);
    return hex.length === 1 ? '0' + hex : hex;
  }

  /**
   * 解析十六进制颜色字符串为RGB
   */
  private parseHexColorToRGB(hexColor: string): RGBColor {
    let clean: string = hexColor;
    if (hexColor.startsWith('#')) {
      clean = hexColor.substring(1);
    }
    if (clean.length !== 6) {
      // 默认返回系统强调色近似值
      return { r: 98, g: 0, b: 238 } as RGBColor;
    }
    const rHex: string = clean.substring(0, 2);
    const gHex: string = clean.substring(2, 4);
    const bHex: string = clean.substring(4, 6);
    const rVal: number = parseInt(rHex, 16);
    const gVal: number = parseInt(gHex, 16);
    const bVal: number = parseInt(bHex, 16);
    const result: RGBColor = { r: rVal, g: gVal, b: bVal } as RGBColor;
    return result;
  }

  /**
   * 获取裁剪对齐方式的显示标签
   */
  private getCropAlignmentLabelFor(alignment: CropAlignment): string {
    switch (alignment) {
      case CropAlignment.TOP_LEFT:
        return '左上';
      case CropAlignment.TOP:
        return '顶部居中';
      case CropAlignment.TOP_RIGHT:
        return '右上';
      case CropAlignment.CENTER_LEFT:
        return '左侧居中';
      case CropAlignment.CENTER:
        return '居中';
      case CropAlignment.CENTER_RIGHT:
        return '右侧居中';
      case CropAlignment.BOTTOM_LEFT:
        return '左下';
      case CropAlignment.BOTTOM:
        return '底部居中';
      case CropAlignment.BOTTOM_RIGHT:
        return '右下';
      default:
        return '居中';
    }
  }

  private getCropAlignmentLabel(): string {
    return this.getCropAlignmentLabelFor(this.cropAlignment);
  }

  private getSplashCropAlignmentLabel(): string {
    return this.getCropAlignmentLabelFor(this.splashCropAlignment);
  }

  private nextCropAlignment(current: CropAlignment): CropAlignment {
    if (current === CropAlignment.CENTER) {
      return CropAlignment.TOP;
    }
    if (current === CropAlignment.TOP) {
      return CropAlignment.BOTTOM;
    }
    if (current === CropAlignment.BOTTOM) {
      return CropAlignment.LEFT;
    }
    if (current === CropAlignment.LEFT) {
      return CropAlignment.RIGHT;
    }
    if (current === CropAlignment.RIGHT) {
      return CropAlignment.TOP_LEFT;
    }
    if (current === CropAlignment.TOP_LEFT) {
      return CropAlignment.TOP_RIGHT;
    }
    if (current === CropAlignment.TOP_RIGHT) {
      return CropAlignment.CENTER_LEFT;
    }
    if (current === CropAlignment.CENTER_LEFT) {
      return CropAlignment.CENTER_RIGHT;
    }
    if (current === CropAlignment.CENTER_RIGHT) {
      return CropAlignment.BOTTOM_LEFT;
    }
    if (current === CropAlignment.BOTTOM_LEFT) {
      return CropAlignment.BOTTOM_RIGHT;
    }
    return CropAlignment.CENTER;
  }

  /**
   * 复制原图到处理结果（用于默认无效果模式）
   */
  private async copyOriginalToProcessed(): Promise<void> {
    if (!this.selectedImagePixelMap) {
      return;
    }
    
    try {
      // 释放旧的处理结果
      if (this.processedImagePixelMap) {
        this.processedImagePixelMap.release();
        this.processedImagePixelMap = null;
      }
      
      // 获取原图信息
      const imageInfo = await this.selectedImagePixelMap.getImageInfo();
      const width = imageInfo.size.width;
      const height = imageInfo.size.height;
      
      // 复制原图像素数据
      // readPixelsToBuffer 返回 BGRA 格式，需要转换为 RGBA
      const buffer = new ArrayBuffer(width * height * 4);
      await this.selectedImagePixelMap.readPixelsToBuffer(buffer);
      
      // BGRA -> RGBA：交换 R 和 B 通道
      const pixels = new Uint8Array(buffer);
      for (let i = 0; i < pixels.length; i += 4) {
        const b = pixels[i];     // BGRA 中第一个是 B
        const r = pixels[i + 2]; // BGRA 中第三个是 R
        pixels[i] = r;           // 设为 R
        pixels[i + 2] = b;       // 设为 B
      }
      
      // 创建新的 PixelMap（RGBA 格式）
      const createOptions: image.InitializationOptions = {
        size: { width: width, height: height },
        pixelFormat: 3, // RGBA_8888
        alphaType: 0,
        editable: true
      };
      
      this.processedImagePixelMap = await image.createPixelMap(buffer, createOptions);
      logger.info(TAG, `✅ 原图已复制到预览 (size=${width}x${height})`);
    } catch (error) {
      logger.error(TAG, `复制原图失败: ${error instanceof Error ? error.message : String(error)}`);
    }
  }

  /**
   * 防抖应用图片效果
   * 用于滑块调节时避免频繁触发
   */
  private applyImageEffectsDebounced(): void {
    // 清除之前的定时器
    if (this.effectDebounceTimer !== -1) {
      clearTimeout(this.effectDebounceTimer);
    }
    
    // 设置新的定时器，300ms后执行
    this.effectDebounceTimer = setTimeout(() => {
      this.applyImageEffects();
      this.effectDebounceTimer = -1;
    }, 300);
  }

  /**
   * 应用图片效果（模糊和压暗）
   * 使用effectKit硬件加速的模糊效果，避免CPU密集型处理导致ANR
   */
  private async applyImageEffects(sourcePixelMap?: image.PixelMap): Promise<void> {
    const basePixelMap: image.PixelMap | null = sourcePixelMap ? sourcePixelMap : this.selectedImagePixelMap;
    if (!basePixelMap) {
      return;
    }
    
    try {
      logger.info(TAG, `开始应用图片效果: 模糊=${this.blurLevel}, 亮度=${this.brightnessLevel}`);
      
      // 如果没有需要应用的效果（模糊为0且亮度为50），直接复制原图
      if (this.blurLevel === 0 && this.brightnessLevel === 50) {
        if (!sourcePixelMap) {
          await this.copyOriginalToProcessed();
        } else {
          const directCopy: image.PixelMap = await this.rotatePixelMapByQuarterTurns(basePixelMap, 0);
          if (this.processedImagePixelMap) {
            this.processedImagePixelMap.release();
          }
          this.processedImagePixelMap = directCopy;
        }
        logger.info(TAG, '✅ 无需应用效果，使用原图');
        return;
      }
      
      // 获取原图信息
      const imageInfo = await basePixelMap.getImageInfo();
      const width = imageInfo.size.width;
      const height = imageInfo.size.height;
      
      // 1. 复制原图作为工作副本（避免修改原图）
      const buffer = new ArrayBuffer(width * height * 4);
      await basePixelMap.readPixelsToBuffer(buffer);
      
      // BGRA -> RGBA：交换 R 和 B 通道（readPixelsToBuffer 返回 BGRA 格式）
      const pixelsBgra = new Uint8Array(buffer);
      for (let swapIdx = 0; swapIdx < pixelsBgra.length; swapIdx += 4) {
        const bChannel = pixelsBgra[swapIdx];
        const rChannel = pixelsBgra[swapIdx + 2];
        pixelsBgra[swapIdx] = rChannel;
        pixelsBgra[swapIdx + 2] = bChannel;
      }
      
      // 2. 创建可编辑的PixelMap用于应用效果（RGBA 格式）
      const createOptions: image.InitializationOptions = {
        size: { width: width, height: height },
        pixelFormat: 3, // RGBA_8888
        alphaType: 0,
        editable: true // 必须设置为可编辑，才能使用effectKit
      };
      
      let workingPixelMap = await image.createPixelMap(buffer, createOptions);
      
      // 3. 应用亮度变暗（在 effectKit 处理之前，避免格式问题）
      // 此时 workingPixelMap 是我们自己创建的 RGBA 格式，可以安全操作
      if (this.brightnessLevel < 50) {
        // 0-49%: 手动像素处理变暗（在原始 buffer 上操作）
        // 映射: 0% → 0.0, 49% → 0.98, 50% → 1.0
        const darknessFactor = this.brightnessLevel / 50;
        logger.info(TAG, `应用亮度降低，因子=${darknessFactor}`);
        
        // 直接在已转换为 RGBA 的 buffer 上操作
        const pixels = new Uint8Array(buffer);
        for (let i = 0; i < pixels.length; i += 4) {
          pixels[i] = Math.round(pixels[i] * darknessFactor);
          pixels[i + 1] = Math.round(pixels[i + 1] * darknessFactor);
          pixels[i + 2] = Math.round(pixels[i + 2] * darknessFactor);
        }
        
        // 重新创建 PixelMap
        workingPixelMap.release();
        workingPixelMap = await image.createPixelMap(buffer, createOptions);
        logger.info(TAG, '✅ 亮度降低完成');
      }
      
      // 4. 应用模糊效果（使用effectKit硬件加速）
      if (this.blurLevel > 0) {
        const filter = effectKit.createEffect(workingPixelMap);
        if (filter) {
          const blurRadius = Math.round(this.blurLevel * 0.3);
          logger.info(TAG, `应用模糊效果，半径=${blurRadius}`);
          filter.blur(blurRadius);
          const blurredPixelMap = await filter.getPixelMap();
          workingPixelMap.release();
          workingPixelMap = blurredPixelMap;
          logger.info(TAG, '✅ 模糊效果应用完成');
        }
      }
      
      // 5. 应用亮度增加（使用 effectKit）
      if (this.brightnessLevel > 50) {
        // 51-100%: 使用 effectKit.brightness 增亮
        // effectKit.brightness: 0=原始, 1=最亮
        // 映射: 51% → 0.02, 100% → 1.0
        const brightnessFactor = (this.brightnessLevel - 50) / 50;
        logger.info(TAG, `应用亮度增加，因子=${brightnessFactor}`);
        const filter = effectKit.createEffect(workingPixelMap);
        if (filter) {
          filter.brightness(brightnessFactor);
          const brighterPixelMap = await filter.getPixelMap();
          workingPixelMap.release();
          workingPixelMap = brighterPixelMap;
          logger.info(TAG, '✅ 亮度增加完成');
        }
      }
      
      // 5. 释放旧的处理结果，保存新的处理结果
      if (this.processedImagePixelMap) {
        this.processedImagePixelMap.release();
      }
      
      this.processedImagePixelMap = workingPixelMap;
      
      logger.info(TAG, '✅ 图片效果应用完成');
    } catch (error) {
      const errorMsg = error instanceof Error ? error.message : String(error);
      logger.error(TAG, `应用图片效果失败: ${errorMsg}`);
      
      // 失败时直接复制原图
      if (basePixelMap && !this.processedImagePixelMap) {
        try {
          const imageInfo = await basePixelMap.getImageInfo();
          const buffer = new ArrayBuffer(imageInfo.size.width * imageInfo.size.height * 4);
          await basePixelMap.readPixelsToBuffer(buffer);
          
          // BGRA -> RGBA 转换
          const fallbackPixels = new Uint8Array(buffer);
          for (let fi = 0; fi < fallbackPixels.length; fi += 4) {
            const fb = fallbackPixels[fi];
            const fr = fallbackPixels[fi + 2];
            fallbackPixels[fi] = fr;
            fallbackPixels[fi + 2] = fb;
          }
          
          const createOptions: image.InitializationOptions = {
            size: imageInfo.size,
            pixelFormat: 3, // RGBA_8888
            alphaType: 0
          };
          
          this.processedImagePixelMap = await image.createPixelMap(buffer, createOptions);
          logger.info(TAG, '已使用原图作为备用处理结果');
        } catch (fallbackError) {
          logger.error(TAG, `备用处理也失败: ${fallbackError instanceof Error ? fallbackError.message : String(fallbackError)}`);
        }
      }
    }
  }

  /**
   * 计算亮度调整比例（保持色相）
   * @param currentLuminance 当前像素的感知亮度
   * @param brightnessFactor 亮度调整因子
   * @returns 调整比例
   */
  private calculateBrightnessAdjustment(currentLuminance: number, brightnessFactor: number): number {
    // 对于暗部和亮部采用不同的调整策略
    if (brightnessFactor < 1.0) {
      // 变暗：使用线性调整，但对暗部保留更多细节
      return brightnessFactor * (0.5 + 0.5 * (currentLuminance / 255));
    } else {
      // 变亮：使用非线性调整，避免过度曝光
      const delta = brightnessFactor - 1.0;
      const headroom = (255 - currentLuminance) / 255;
      return 1.0 + delta * headroom * 0.8;
    }
  }

  /**
   * 保存并应用当前主题
   * 保存两张图片：浅色模式（原亮度）和深色模式（降低亮度）
   */
  private async saveAndApplyTheme(): Promise<void> {
    const sourceTheme: CustomTheme | null = this.getEditingSourceTheme();
    if (!this.selectedImagePixelMap && sourceTheme === null) {
      logger.error(TAG, '没有可保存的主题');
      promptAction.showToast({
        message: '请先选择背景图片',
        duration: 1600
      });
      return;
    }
    
    try {
      const context = this.uiContext?.getHostContext() as common.UIAbilityContext;
      if (!context) {
        throw new Error('无法获取UIAbilityContext');
      }
      
      this.isProcessing = true;
      this.processingMessage = '正在保存主题...';
      this.processingProgress = 0;
      
      // 创建主题目录
      const themesDir = `${context.filesDir}/custom_themes`;
      if (!fs.accessSync(themesDir)) {
        fs.mkdirSync(themesDir);
      }
      
      const themeId: string = this.isEditingCustomTheme && this.editingThemeId.length > 0
        ? this.editingThemeId
        : `theme_${Date.now()}`;
      
      let lightImagePath: string = '';
      let darkImagePath: string = '';
      if (this.selectedImagePixelMap) {
        // 1. 生成浅色模式图片（使用用户设置的亮度+模糊）
        this.processingMessage = '正在生成浅色模式图片...';
        this.processingProgress = 20;
        lightImagePath = await this.generateThemeImage(themeId, 'light', this.blurLevel, this.brightnessLevel);

        // 2. 生成深色模式图片（在用户设置基础上降低亮度）
        this.processingMessage = '正在生成深色模式图片...';
        this.processingProgress = 60;
        const darkBrightness = Math.max(10, Math.min(40, this.brightnessLevel - 20)); // 比当前亮度低20%，范围10-40
        darkImagePath = await this.generateThemeImage(themeId, 'dark', this.blurLevel, darkBrightness);
      } else if (sourceTheme !== null) {
        // 编辑默认/内置资源主题时允许只保存颜色与启动页显示选项，继续复用原媒体配置。
        lightImagePath = sourceTheme.backgroundImagePath ? sourceTheme.backgroundImagePath : '';
        darkImagePath = sourceTheme.backgroundImagePathDark ? sourceTheme.backgroundImagePathDark : '';
        this.processingMessage = '正在复用原主题素材...';
        this.processingProgress = 60;
      }

      // 生成开屏图片列表（如果已选择或已加入草稿）
      let splashImagePaths: string[] = [];
      if (this.splashSourceImagePaths.length > 0 || this.splashDraftImagePaths.length > 0 || this.processedSplashImagePixelMap) {
        this.processingMessage = '正在生成开屏图片...';
        this.processingProgress = 80;
        splashImagePaths = await this.generateSplashImages(themeId);
      } else if (sourceTheme !== null) {
        splashImagePaths = this.getSplashPathsFromTheme(sourceTheme);
      }
      const splashPrimaryPath: string = splashImagePaths.length > 0 ? splashImagePaths[0] : '';
      
      // 3. 创建主题对象
      this.processingMessage = '正在保存主题信息...';
      this.processingProgress = 90;
      const themeName: string = this.normalizeThemeName();
      const primaryColorToUse: string = this.selectedPrimaryColor && this.selectedPrimaryColor.length > 0 ? this.selectedPrimaryColor : this.extractedColor;
      const createTimeValue: number = this.isEditingCustomTheme && this.editingThemeCreateTime > 0
        ? this.editingThemeCreateTime
        : Date.now();
      const selectedMode: CustomThemeMode = this.selectedThemeMode;
      const customTheme: CustomTheme = {
        id: themeId,
        name: themeName,
        backgroundImagePath: lightImagePath,
        backgroundImagePathDark: darkImagePath,
        splashBackgroundImagePath: splashPrimaryPath,
        splashBackgroundImagePaths: splashImagePaths,
        splashRotationRule: this.splashRotationRule,
        splashRotationCursor: -1,
        splashRotationLastDateKey: '',
        hideSplashLogo: this.hideSplashLogo,
        hideSplashProgress: this.hideSplashProgress,
        blurLevel: this.blurLevel,
        brightness: this.brightnessLevel,
        primaryColor: primaryColorToUse,
        themeMode: selectedMode,
        isDark: selectedMode === CustomThemeMode.DARK,
        createTime: createTimeValue,
        lastModified: Date.now()
      };
      
      await this.saveCustomTheme(customTheme);
      
      logger.info(TAG, `主题已保存: ${customTheme.name}`);
      logger.info(TAG, `  浅色模式图片: ${lightImagePath}`);
      logger.info(TAG, `  深色模式图片: ${darkImagePath}`);
      logger.info(TAG, `  开屏图片数量: ${splashImagePaths.length}`);
      
      // 应用主题到应用
      await this.applyCustomThemeToManager(customTheme);
      
      this.processingMessage = this.isEditingCustomTheme ? '主题修改成功！' : '主题保存成功！';
      this.processingProgress = 100;
      logger.info(TAG, `✅ 自定义主题已应用，将在所有页面生效`);
      this.cleanupSplashDraftFiles();
      this.cleanupBackgroundDraftFiles();
      this.clearCurrentSplashSelection();
      
      // 显示Toast并自动返回
      setTimeout(() => {
        this.isProcessing = false;
        // 显示成功提示
        promptAction.showToast({
          message: this.isEditingCustomTheme ? '主题修改已保存并应用' : '主题已保存并应用',
          duration: 2000
        });
        // 延迟返回上一页
        setTimeout(() => {
          this.goBack();
        }, 500);
      }, 800);
      
    } catch (error) {
      this.isProcessing = false;
      logger.error(TAG, `保存主题失败: ${error instanceof Error ? error.message : String(error)}`);
    }
  }

  /**
   * 标准化主题名称：若未输入则生成“自定义主题N”且避免重名
   */
  private normalizeThemeName(): string {
    const inputName: string = this.newThemeName ? this.newThemeName.trim() : '';
    if (inputName.length > 0) {
      return inputName;
    }
    let index: number = 1;
    while (true) {
      const candidate: string = '自定义主题 ' + index.toString();
      let exists: boolean = false;
      let i: number = 0;
      while (i < this.customThemes.length) {
        if (this.customThemes[i].name === candidate) {
          exists = true;
          break;
        }
        i = i + 1;
      }
      if (!exists) {
        return candidate;
      }
      index = index + 1;
    }
  }

  /**
   * 生成主题图片（模糊+亮度调整）
   * @param themeId 主题ID
   * @param mode 模式（light/dark）
   * @param blurLevel 模糊程度
   * @param brightness 亮度（0-100）
   * @returns 生成的图片路径
   */
  private async generateThemeImage(themeId: string, mode: string, blurLevel: number, brightness: number): Promise<string> {
    const context = this.uiContext?.getHostContext() as common.UIAbilityContext;
    if (!context) {
      throw new Error('无法获取UIAbilityContext');
    }
    if (!this.selectedImagePixelMap) {
      throw new Error('selectedImagePixelMap为null');
    }
    
    const themesDir = `${context.filesDir}/custom_themes`;
    const imagePath = `${themesDir}/${themeId}_${mode}.webp`;
    
    // 获取原图信息
    const imageInfo = await this.selectedImagePixelMap.getImageInfo();
    const width = imageInfo.size.width;
    const height = imageInfo.size.height;
    
    // 1. 复制原图并转换格式
    const buffer = new ArrayBuffer(width * height * 4);
    await this.selectedImagePixelMap.readPixelsToBuffer(buffer);
    
    // BGRA -> RGBA：交换 R 和 B 通道（readPixelsToBuffer 返回 BGRA 格式）
    const pixelsConvert = new Uint8Array(buffer);
    for (let idx = 0; idx < pixelsConvert.length; idx += 4) {
      const bVal = pixelsConvert[idx];
      const rVal = pixelsConvert[idx + 2];
      pixelsConvert[idx] = rVal;
      pixelsConvert[idx + 2] = bVal;
    }
    
    // 使用 RGBA_8888 格式创建 PixelMap
    const createOptions: image.InitializationOptions = {
      size: { width: width, height: height },
      pixelFormat: 3, // RGBA_8888
      alphaType: 0,
      editable: true
    };
    
    let workingPixelMap = await image.createPixelMap(buffer, createOptions);
    
    // 2. 应用亮度变暗（在 effectKit 处理之前）
    if (brightness < 50) {
      const darknessFactor = brightness / 50;
      const pixels = new Uint8Array(buffer);
      for (let i = 0; i < pixels.length; i += 4) {
        pixels[i] = Math.round(pixels[i] * darknessFactor);
        pixels[i + 1] = Math.round(pixels[i + 1] * darknessFactor);
        pixels[i + 2] = Math.round(pixels[i + 2] * darknessFactor);
      }
      workingPixelMap.release();
      workingPixelMap = await image.createPixelMap(buffer, createOptions);
    }
    
    // 3. 应用模糊效果
    if (blurLevel > 0) {
      const filter = effectKit.createEffect(workingPixelMap);
      if (filter) {
        const blurRadius = Math.round(blurLevel * 0.3);
        filter.blur(blurRadius);
        const blurredPixelMap = await filter.getPixelMap();
        workingPixelMap.release();
        workingPixelMap = blurredPixelMap;
      }
    }
    
    // 4. 应用亮度增加
    if (brightness > 50) {
      const brightnessFactor = (brightness - 50) / 50;
      const filter = effectKit.createEffect(workingPixelMap);
      if (filter) {
        filter.brightness(brightnessFactor);
        const brighterPixelMap = await filter.getPixelMap();
        workingPixelMap.release();
        workingPixelMap = brighterPixelMap;
      }
    }
    
    // 4. 保存为WebP格式（最优压缩和质量）
    const packOpts: image.PackingOption = {
      format: 'image/webp',
      quality: 85 // WebP质量85可以获得极小的文件体积和优秀的视觉质量
    };
    
    try {
      const imagePacker = image.createImagePacker();
      const file = fs.openSync(imagePath, fs.OpenMode.CREATE | fs.OpenMode.WRITE_ONLY | fs.OpenMode.TRUNC);
      await imagePacker.packToFile(workingPixelMap, file.fd, packOpts);
      fs.closeSync(file);
      imagePacker.release();
    } catch (error) {
      const errorMsg = error instanceof Error ? error.message : String(error);
      logger.error(TAG, `保存图片失败: ${errorMsg}`);
      throw new Error(`保存图片失败: ${errorMsg}`);
    } finally {
      workingPixelMap.release();
    }
    
    logger.info(TAG, `✅ 生成${mode}模式图片: ${imagePath}`);
    
    return imagePath;
  }

  /**
   * 应用自定义主题到ThemeManager
   * 辅助方法，用于调用ThemeManager的applyCustomTheme方法
   */
  private async applyCustomThemeToManager(theme: CustomTheme): Promise<void> {
    try {
      logger.info(TAG, `开始应用自定义主题: ${theme.name}`);
      // 不强制切换应用主题；保持当前主题设置（含AUTO），由ThemeManager按系统深浅切换背景
      const splashPaths: string[] = this.getSplashPathsFromTheme(theme);
      const splashRule: SplashRotationRule = this.getSplashRotationRuleFromTheme(theme);
      const themeMode: CustomThemeMode = this.getThemeModeFromTheme(theme);
      
      // 调用ThemeManager统一应用（包含开屏背景路径）
      const themeData: CustomThemeData = {
        id: theme.id,
        name: theme.name,
        backgroundImagePath: theme.backgroundImagePath,
        backgroundImagePathDark: theme.backgroundImagePathDark,
        splashBackgroundImagePath: splashPaths.length > 0 ? splashPaths[0] : '',
        splashBackgroundImagePaths: splashPaths,
        splashRotationRule: splashRule,
        splashRotationCursor: theme.splashRotationCursor !== undefined ? theme.splashRotationCursor : -1,
        splashRotationLastDateKey: theme.splashRotationLastDateKey ? theme.splashRotationLastDateKey : '',
        hideSplashLogo: this.getHideSplashLogoFromTheme(theme),
        hideSplashProgress: this.getHideSplashProgressFromTheme(theme),
        blurLevel: theme.blurLevel,
        primaryColor: theme.primaryColor,
        themeMode: themeMode,
        isDark: themeMode === CustomThemeMode.DARK,
        createTime: theme.createTime,
        lastModified: theme.lastModified
      };
      await this.themeManager.applyCustomTheme(themeData);
      
      logger.info(TAG, `✅ 自定义主题应用成功（含开屏图）: ${theme.name}`);
      logger.info(TAG, `   背景图片: ${theme.backgroundImagePath}`);
      logger.info(TAG, `   深色背景: ${theme.backgroundImagePathDark}`);
      if (splashPaths.length > 0) {
        logger.info(TAG, `   开屏图片数量: ${splashPaths.length}`);
      }
      logger.info(TAG, `   开屏轮换规则: ${splashRule}`);
      logger.info(TAG, `   主色调: ${theme.primaryColor}`);
      logger.info(TAG, `   主题类型: ${this.getThemeModeLabel(themeMode)}`);
      logger.info(TAG, `   当前显示主题: ${this.themeManager.getActualThemeSync()}`);
    } catch (error) {
      const errorMsg = error instanceof Error ? error.message : String(error);
      logger.error(TAG, `应用自定义主题失败: ${errorMsg}`);
      throw new Error(`应用自定义主题失败: ${errorMsg}`);
    }
  }

  /**
   * 返回上一页
   */
  private goBack(): void {
    this.pathStack.pop();
  }
  
  // ==================== 透明度和特效设置方法 ====================
  
  /**
   * 更新透明度设置
   */
  private async updateTransparency(key: keyof TransparencyConfig, value: number): Promise<void> {
    try {
      let update: Partial<TransparencyConfig> = {};
      if (key === 'navigationBar') { update = { navigationBar: value }; }
      else if (key === 'tabBar') { update = { tabBar: value }; }
      else if (key === 'card') { update = { card: value }; }
      else if (key === 'dialog') { update = { dialog: value }; }
      else if (key === 'floatingBall') { update = { floatingBall: value }; }
      else if (key === 'menu') { update = { menu: value }; }
      else if (key === 'sidebar') { update = { sidebar: value }; }
      await this.userThemeConfigManager.setTransparency(update);
      logger.debug(TAG, `透明度更新: ${key} = ${value}`);
    } catch (error) {
      logger.error(TAG, '更新透明度失败', error);
    }
  }
  
  /**
   * 更新特效设置
   */
  private async updateEffect(key: keyof EffectsConfig, value: boolean | number): Promise<void> {
    try {
      let update: Partial<EffectsConfig> = {};
      if (key === 'enableBlur') { update = { enableBlur: value as boolean }; }
      else if (key === 'blurIntensity') { update = { blurIntensity: value as number }; }
      else if (key === 'enableShadow') { update = { enableShadow: value as boolean }; }
      else if (key === 'shadowIntensity') { update = { shadowIntensity: value as number }; }
      else if (key === 'enableAnimation') { update = { enableAnimation: value as boolean }; }
      else if (key === 'animationSpeed') { update = { animationSpeed: value as number }; }
      else if (key === 'enableRoundedCorners') { update = { enableRoundedCorners: value as boolean }; }
      else if (key === 'componentCornerRadius') { update = { componentCornerRadius: value as number }; }
      else if (key === 'coverCornerRadius') { update = { coverCornerRadius: value as number }; }
      else if (key === 'enableGlassmorphism') { update = { enableGlassmorphism: value as boolean }; }
      await this.userThemeConfigManager.setEffects(update);
      logger.debug(TAG, `特效更新: ${key} = ${value}`);
    } catch (error) {
      logger.error(TAG, '更新特效设置失败', error);
    }
  }

  /**
   * 更新 HdsTab 特效设置
   */
  private async updateHdsTabEffect(key: keyof HdsTabEffectsConfig, value: boolean | number): Promise<void> {
    try {
      let update: Partial<HdsTabEffectsConfig> = {};
      if (key === 'opacityRatio') {
        update = { opacityRatio: value as number };
      } else if (key === 'minOpacity') {
        update = { minOpacity: value as number };
      } else if (key === 'maxOpacity') {
        update = { maxOpacity: value as number };
      } else if (key === 'lightHighlightOpacity') {
        update = { lightHighlightOpacity: value as number };
      } else if (key === 'darkHighlightOpacity') {
        update = { darkHighlightOpacity: value as number };
      } else if (key === 'materialLevel') {
        update = { materialLevel: value as number };
      } else if (key === 'blurEnabled') {
        update = { blurEnabled: value as boolean };
      } else if (key === 'sideMargin') {
        update = { sideMargin: value as number };
      } else if (key === 'bottomMargin') {
        update = { bottomMargin: value as number };
      }
      await this.userThemeConfigManager.setHdsTabEffects(update);
      logger.debug(TAG, `HdsTab特效更新: ${key} = ${value}`);
    } catch (error) {
      logger.error(TAG, '更新HdsTab特效失败', error);
    }
  }

  private async updateHdsTabOpacityRange(minPercent: number, maxPercent: number): Promise<void> {
    try {
      const safeMinPercent: number = this.clampPercent(minPercent);
      const safeMaxPercent: number = Math.max(safeMinPercent, this.clampPercent(maxPercent));
      this.hdsTabMinOpacityPercent = safeMinPercent;
      this.hdsTabMaxOpacityPercent = safeMaxPercent;
      this.hdsTabMinOpacity = safeMinPercent / 100;
      this.hdsTabMaxOpacity = safeMaxPercent / 100;
      const update: Partial<HdsTabEffectsConfig> = {
        minOpacity: safeMinPercent / 100,
        maxOpacity: safeMaxPercent / 100
      };
      await this.userThemeConfigManager.setHdsTabEffects(update);
      logger.debug(TAG, `HdsTab可见度范围更新: min=${safeMinPercent}, max=${safeMaxPercent}`);
    } catch (error) {
      logger.error(TAG, '更新HdsTab可见度范围失败', error);
    }
  }

  /**
   * 重置 HdsTab 特效为默认值
   */
  private async resetHdsTabEffectsToDefault(): Promise<void> {
    try {
      const defaults: HdsTabEffectsConfig = {
        opacityRatio: DEFAULT_HDS_TAB_OPACITY_RATIO,
        minOpacity: DEFAULT_HDS_TAB_MIN_OPACITY,
        maxOpacity: DEFAULT_HDS_TAB_MAX_OPACITY,
        lightHighlightOpacity: DEFAULT_HDS_TAB_LIGHT_HIGHLIGHT_OPACITY,
        darkHighlightOpacity: DEFAULT_HDS_TAB_DARK_HIGHLIGHT_OPACITY,
        materialLevel: DEFAULT_HDS_TAB_MATERIAL_LEVEL,
        blurEnabled: true,
        sideMargin: 8,
        bottomMargin: 0
      };
      await this.userThemeConfigManager.setHdsTabEffects(defaults);
      this.hdsTabOpacityRatioPercent = Math.round(defaults.opacityRatio * 100);
      this.hdsTabMinOpacityPercent = Math.round(defaults.minOpacity * 100);
      this.hdsTabMaxOpacityPercent = Math.round(defaults.maxOpacity * 100);
      this.hdsTabLightHighlightPercent = Math.round(defaults.lightHighlightOpacity * 100);
      this.hdsTabDarkHighlightPercent = Math.round(defaults.darkHighlightOpacity * 100);
      this.hdsTabSideMarginValue = defaults.sideMargin;
      this.hdsTabBottomMarginValue = defaults.bottomMargin;
      this.hdsTabOpacityRatio = defaults.opacityRatio;
      this.hdsTabMinOpacity = defaults.minOpacity;
      this.hdsTabMaxOpacity = defaults.maxOpacity;
      this.hdsTabLightHighlightOpacity = defaults.lightHighlightOpacity;
      this.hdsTabDarkHighlightOpacity = defaults.darkHighlightOpacity;
      this.hdsTabMaterialLevel = defaults.materialLevel;
      this.hdsTabBlurEnabled = defaults.blurEnabled;
      this.hdsTabSideMargin = defaults.sideMargin;
      this.hdsTabBottomMargin = defaults.bottomMargin;
      logger.info(TAG, '已重置HdsTab特效设置为默认值');
    } catch (error) {
      logger.error(TAG, '重置HdsTab特效失败', error);
    }
  }
  
  /**
   * 重置透明度和特效为默认值
   */
  private async resetEffectsToDefault(): Promise<void> {
    try {
      await this.userThemeConfigManager.resetToDefault();
      await this.initializeUserThemeConfig();
      logger.info(TAG, '已重置透明度和特效设置为默认值');
    } catch (error) {
      logger.error(TAG, '重置设置失败', error);
    }
  }

  /**
   * 显示删除确认对话框（使用系统组件）
   */
  private showDeleteConfirmDialogSystem(): void {
    if (!this.uiContext) {
      logger.warn(TAG, 'UIContext 未初始化，无法显示删除确认对话框');
      return;
    }
    
    this.uiContext.getPromptAction().showDialog({
      title: '确认删除',
      message: `确定要删除选中的 ${this.selectedThemeIds.length} 个主题吗？\n此操作不可撤销，相关的背景图片文件也将被删除。`,
      buttons: [
        { text: '取消', color: '#999999' },
        { text: '删除', color: '#FF3B30' }
      ]
    }).then((result) => {
      if (result.index === 1) {
        this.deleteSelectedThemes();
      }
    }).catch((err: Error) => {
      logger.error(TAG, `显示删除确认对话框失败: ${err.message}`);
    });
  }

  private getTitleBarActions(): SettingsImmersiveTitleActionItem[] {
    if (this.selectionModeEnabled) {
      return [
        {
          id: 'delete_selected',
          symbol: $r('sys.symbol.trash'),
          onClick: () => { this.showDeleteConfirmDialogSystem(); },
          enabled: this.selectedThemeIds.length > 0
        },
        {
          id: 'cancel_selection',
          symbol: $r('sys.symbol.xmark'),
          onClick: () => { this.exitSelectionMode(); },
          enabled: true
        }
      ];
    }

    return [
      {
        id: 'restore_default_theme',
        symbol: $r('sys.symbol.arrow_counterclockwise'),
        onClick: () => { void this.restoreDefaultCustomTheme(); },
        enabled: true
      }
    ];
  }

  /**
   * 显示“关闭自定义主题”确认对话框
   * 仅关闭当前应用，不删除已保存的自定义主题
   */
  private showDisableCustomThemeConfirmDialog(): void {
    if (!this.uiContext) {
      logger.warn(TAG, 'UIContext 未初始化，无法显示关闭自定义主题确认对话框');
      return;
    }

    this.uiContext.getPromptAction().showDialog({
      title: '关闭自定义主题',
      message: '关闭后将不再使用任何自定义主题，并恢复到纯色主题。已保存的自定义主题不会被删除。是否继续？',
      buttons: [
        { text: '取消', color: '#999999' },
        { text: '确认关闭', color: '#FF3B30' }
      ]
    }).then(async (result) => {
      if (result.index !== 1) {
        return;
      }

      try {
        await this.themeManager.clearCustomTheme();
        this.currentCustomThemeId = '';
        promptAction.showToast({ message: '已关闭自定义主题，已恢复纯色主题' });
        logger.info(TAG, '已关闭自定义主题，保留已保存主题列表');
      } catch (error) {
        const errorMsg: string = error instanceof Error ? error.message : String(error);
        logger.error(TAG, `关闭自定义主题失败: ${errorMsg}`);
        promptAction.showToast({ message: '关闭失败，请稍后重试' });
      }
    }).catch((err: Error) => {
      logger.error(TAG, `显示关闭自定义主题确认对话框失败: ${err.message}`);
    });
  }

  private scrollThemeEditorToTop(): void {
    setTimeout(() => {
      try {
        this.scroller.scrollTo({
          xOffset: 0,
          yOffset: 0,
          animation: {
            duration: 220
          }
        });
      } catch (error) {
        const message: string = error instanceof Error ? error.message : String(error);
        logger.warn(TAG, `滚动到主题编辑区顶部失败: ${message}`);
      }
    }, 0);
  }

  private beginCreateCustomTheme(): void {
    this.isCreatingCustomTheme = true;
    this.isEditingCustomTheme = false;
    this.editingThemeId = '';
    this.editingThemeCreateTime = 0;
    this.mediaEditorTab = ThemeMediaTabType.BACKGROUND;
    this.newThemeName = '';
    this.cropAlignment = CropAlignment.CENTER;
    this.cropZoom = 1.0;
    this.backgroundRotateQuarterTurns = 0;
    this.clearCurrentBackgroundSelection();
    this.splashCropAlignment = CropAlignment.CENTER;
    this.splashCropZoom = 1.0;
    this.splashRotateQuarterTurns = 0;
      this.splashRotationRule = SplashRotationRule.EVERY_LAUNCH;
      this.hideSplashLogo = false;
      this.hideSplashProgress = false;
      this.selectedThemeMode = CustomThemeMode.AUTO;
      this.resetSplashViewfinder();
    this.cleanupSplashDraftFiles();
    this.cleanupBackgroundDraftFiles();
    this.clearCurrentSplashSelection();
    if (this.selectedPrimaryColor.length > 0) {
      this.syncCustomColorEditor(this.selectedPrimaryColor);
    }
    this.scrollThemeEditorToTop();
  }

  private async editExistingTheme(theme: CustomTheme): Promise<void> {
    try {
      this.beginCreateCustomTheme();
      this.isEditingCustomTheme = true;
      this.editingThemeId = theme.id;
      this.editingThemeCreateTime = theme.createTime;
      this.newThemeName = theme.name;
      this.blurLevel = theme.blurLevel;
      this.brightnessLevel = theme.brightness;
      this.splashRotationRule = this.getSplashRotationRuleFromTheme(theme);
      this.hideSplashLogo = this.getHideSplashLogoFromTheme(theme);
      this.hideSplashProgress = this.getHideSplashProgressFromTheme(theme);
      this.selectedThemeMode = this.getThemeModeFromTheme(theme);
      if (theme.primaryColor && theme.primaryColor.length > 0) {
        this.ensureColorInPalette(theme.primaryColor);
        this.selectedPrimaryColor = theme.primaryColor;
        this.syncCustomColorEditor(theme.primaryColor);
      }
      if (theme.backgroundImagePath && theme.backgroundImagePath.length > 0) {
        await this.setBackgroundDraftImages([theme.backgroundImagePath]);
      }
      const splashPaths: string[] = this.getSplashPathsFromTheme(theme);
      if (splashPaths.length > 0) {
        await this.setSplashSourceImages(splashPaths);
      }
      this.processingMessage = '';
      this.processingProgress = 0;
      this.isProcessing = false;
      this.scrollThemeEditorToTop();
    } catch (error) {
      const message: string = error instanceof Error ? error.message : String(error);
      logger.error(TAG, `加载主题编辑信息失败: ${message}`);
      promptAction.showToast({
        message: '加载主题失败，请重试',
        duration: 1600
      });
    }
  }

  @Builder
  private buildMediaCapsuleTabButton(tab: ThemeMediaTabType) {
    Row() {
      Text(this.getMediaTabLabel(tab))
        .fontSize(12)
        .fontFamily(this.appFontFamily)
        .fontWeight(this.isMediaTabActive(tab) ? FontWeight.Medium : FontWeight.Normal)
        .fontColor(this.isMediaTabActive(tab)
          ? ThemeAwareHelper.getTestManagementThemedColor('text_white', this.themeState.currentTheme)
          : ThemeAwareHelper.getTestManagementThemedColor('text_secondary', this.themeState.currentTheme))
    }
    .layoutWeight(1)
    .height(34)
    .justifyContent(FlexAlign.Center)
    .padding({ left: 10, right: 10 })
    .backgroundColor(this.isMediaTabActive(tab)
      ? ThemeAwareHelper.getTestManagementThemedColor('accent_blue', this.themeState.currentTheme)
      : Color.Transparent)
    .borderRadius(999)
    .onClick(() => {
      this.mediaEditorTab = tab;
    })
    .animation({ duration: 180, curve: Curve.EaseOut })
  }

  @Builder
  private buildMediaCapsuleTabBar() {
    Row({ space: 6 }) {
      this.buildMediaCapsuleTabButton(ThemeMediaTabType.BACKGROUND)
      this.buildMediaCapsuleTabButton(ThemeMediaTabType.SPLASH)
    }
    .width('100%')
    .padding(4)
    .backgroundColor(ThemeAwareHelper.getTestManagementThemedColor('background_secondary', this.themeState.currentTheme))
    .border({
      width: 1,
      color: ThemeAwareHelper.getTestManagementThemedColor('divider', this.themeState.currentTheme)
    })
    .borderRadius(999)
    .clip(true)
  }

  @Builder
  private buildThemeModeOptions() {
    Column({ space: 8 }) {
      Row() {
        Column({ space: 2 }) {
          Text('主题类型')
            .fontSize(13)
            .fontFamily(this.appFontFamily)
            .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_primary', this.themeState.currentTheme))
          Text(`当前：${this.getThemeModeLabel(this.selectedThemeMode)}，${this.getThemeModeDescription(this.selectedThemeMode)}`)
            .fontSize(11)
            .fontFamily(this.appFontFamily)
            .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_secondary', this.themeState.currentTheme))
            .opacity(0.8)
        }
        .layoutWeight(1)
      }
      .width('100%')

      Row({ space: 8 }) {
        ForEach(this.themeModeOptions, (option: ThemeModeOption) => {
          Column({ space: 4 }) {
            Text(option.label)
              .fontSize(13)
              .fontFamily(this.appFontFamily)
              .fontWeight(this.selectedThemeMode === option.value ? FontWeight.Medium : FontWeight.Normal)
              .fontColor(this.selectedThemeMode === option.value
                ? ThemeAwareHelper.getTestManagementThemedColor('text_primary', this.themeState.currentTheme)
                : ThemeAwareHelper.getTestManagementThemedColor('text_secondary', this.themeState.currentTheme))
            Text(option.description)
              .fontSize(10)
              .fontFamily(this.appFontFamily)
              .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_secondary', this.themeState.currentTheme))
              .maxLines(2)
              .textAlign(TextAlign.Center)
              .opacity(0.78)
          }
          .layoutWeight(1)
          .height(70)
          .justifyContent(FlexAlign.Center)
          .padding({ left: 8, right: 8 })
          .backgroundColor(this.selectedThemeMode === option.value
            ? ThemeAwareHelper.getTestManagementThemedColor('comp_background_tertiary', this.themeState.currentTheme)
            : 'rgba(0, 0, 0, 0)')
          .borderRadius(10)
          .border({
            width: this.selectedThemeMode === option.value ? 1 : 0,
            color: $r('app.color.accent_primary')
          })
          .onClick(() => {
            this.selectedThemeMode = option.value;
          })
        }, (option: ThemeModeOption) => option.value)
      }
      .width('100%')
    }
    .width('100%')
    .padding({ left: 10, right: 10, top: 8, bottom: 8 })
    .backgroundColor(ThemeAwareHelper.getTestManagementThemedColor('comp_background_tertiary', this.themeState.currentTheme))
    .borderRadius(8)
  }

  @Builder
  private buildSplashVisibilityOptions() {
    Column({ space: 8 }) {
      Row() {
        Column({ space: 2 }) {
          Text('启动页不显示应用logo')
            .fontSize(13)
            .fontFamily(this.appFontFamily)
            .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_primary', this.themeState.currentTheme))
          Text('开启后，当前主题在启动页仅显示背景与进度，不显示应用图标')
            .fontSize(11)
            .fontFamily(this.appFontFamily)
            .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_secondary', this.themeState.currentTheme))
            .opacity(0.8)
        }
        .layoutWeight(1)
        Toggle({ type: ToggleType.Switch, isOn: this.hideSplashLogo })
          .selectedColor($r('app.color.accent_primary'))
          .onChange((isOn: boolean) => {
            this.hideSplashLogo = isOn;
          })
      }
      .width('100%')
      .padding({ left: 10, right: 10, top: 8, bottom: 8 })
      .backgroundColor(ThemeAwareHelper.getTestManagementThemedColor('comp_background_tertiary', this.themeState.currentTheme))
      .borderRadius(8)

      Row() {
        Column({ space: 2 }) {
          Text('不显示启动进度')
            .fontSize(13)
            .fontFamily(this.appFontFamily)
            .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_primary', this.themeState.currentTheme))
          Text('开启后，当前主题在启动页不显示进度文本、进度条与百分比')
            .fontSize(11)
            .fontFamily(this.appFontFamily)
            .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_secondary', this.themeState.currentTheme))
            .opacity(0.8)
        }
        .layoutWeight(1)
        Toggle({ type: ToggleType.Switch, isOn: this.hideSplashProgress })
          .selectedColor($r('app.color.accent_primary'))
          .onChange((isOn: boolean) => {
            this.hideSplashProgress = isOn;
          })
      }
      .width('100%')
      .padding({ left: 10, right: 10, top: 8, bottom: 8 })
      .backgroundColor(ThemeAwareHelper.getTestManagementThemedColor('comp_background_tertiary', this.themeState.currentTheme))
      .borderRadius(8)
    }
    .width('100%')
  }

  private clampPercent(value: number): number {
    return Math.max(0, Math.min(100, value));
  }

  private getHdsTabPreviewOpacity(): number {
    const ratio: number = Math.max(0, Math.min(1, this.hdsTabOpacityRatio));
    const minOpacity: number = Math.max(0, Math.min(1, this.hdsTabMinOpacity));
    const maxOpacity: number = Math.max(minOpacity, Math.min(1, this.hdsTabMaxOpacity));
    return Math.min(maxOpacity, Math.max(minOpacity, ratio));
  }

  private getHdsTabPreviewHighlightOpacity(): number {
    const rawOpacity: number = this.themeState.currentTheme === ThemeType.DARK
      ? this.hdsTabDarkHighlightOpacity
      : this.hdsTabLightHighlightOpacity;
    return Math.max(0, Math.min(1, rawOpacity));
  }

  private getHdsTabPreviewHighlightColor(): ResourceColor {
    return `rgba(255, 255, 255, ${this.getHdsTabPreviewHighlightOpacity()})`;
  }

  private getHdsTabPreviewBlurStyle(): BlurStyle {
    if (!this.hdsTabBlurEnabled) {
      return BlurStyle.NONE;
    }
    const style: BlurStyle | undefined = SettingsPanelSurfaceHelper.getBlurStyle(this.themeState.currentTheme);
    if (style === undefined) {
      return BlurStyle.NONE;
    }
    return style;
  }

  private isHdsTabMaterialSelected(level: number): boolean {
    return this.hdsTabMaterialLevel === level;
  }

  private getHdsTabMaterialLabel(): string {
    if (this.hdsTabMaterialLevel === HDS_TAB_MATERIAL_FOLLOW_GLOBAL) {
      return '跟随全局';
    }
    if (this.hdsTabMaterialLevel === hdsMaterial.MaterialLevel.EXQUISITE) {
      return '精致';
    }
    if (this.hdsTabMaterialLevel === hdsMaterial.MaterialLevel.GENTLE) {
      return '柔和';
    }
    if (this.hdsTabMaterialLevel === hdsMaterial.MaterialLevel.SMOOTH) {
      return '平滑';
    }
    return '精致';
  }

  @Builder
  private buildHdsTabMaterialButton(label: string, level: number) {
    Button(label)
      .height(34)
      .fontSize(12)
      .fontFamily(this.appFontFamily)
      .fontColor(this.isHdsTabMaterialSelected(level)
        ? ThemeAwareHelper.getTestManagementThemedColor('text_white', this.themeState.currentTheme)
        : ThemeAwareHelper.getTestManagementThemedColor('text_secondary', this.themeState.currentTheme))
      .backgroundColor(this.isHdsTabMaterialSelected(level)
        ? ThemeAwareHelper.getTestManagementThemedColor('accent_blue', this.themeState.currentTheme)
        : ThemeAwareHelper.getTestManagementThemedColor('comp_background_tertiary', this.themeState.currentTheme))
      .borderRadius(17)
      .onClick(() => {
        this.hdsTabMaterialLevel = level;
        this.updateHdsTabEffect('materialLevel', level);
      })
      .margin({ right: 8, bottom: 8 })
  }

  @Builder
  private buildHdsTabOpacityRatioSlider() {
    Column({ space: 4 }) {
      Row() {
        Text('透明度倍率')
          .fontSize(14)
          .fontFamily(this.appFontFamily)
          .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_secondary', this.themeState.currentTheme))
        Blank()
        Text(`${this.hdsTabOpacityRatioPercent}%`)
          .fontSize(14)
          .fontFamily(this.appFontFamily)
          .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_muted', this.themeState.currentTheme))
      }
      .width('100%')
      Slider({ value: $$this.hdsTabOpacityRatioPercent, min: 0, max: 100, step: 1 })
        .width('100%')
        .selectedColor($r('app.color.accent_primary'))
        .trackColor($r('app.color.divider_primary'))
        .onChange((sliderValue: number) => {
          const normalizedValue: number = this.clampPercent(Math.round(sliderValue));
          this.hdsTabOpacityRatioPercent = normalizedValue;
          this.hdsTabOpacityRatio = normalizedValue / 100;
          this.updateHdsTabEffect('opacityRatio', normalizedValue / 100);
        })
    }
    .width('100%')
  }

  @Builder
  private buildHdsTabMinOpacitySlider() {
    Column({ space: 4 }) {
      Row() {
        Text('最小可见度')
          .fontSize(14)
          .fontFamily(this.appFontFamily)
          .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_secondary', this.themeState.currentTheme))
        Blank()
        Text(`${this.hdsTabMinOpacityPercent}%`)
          .fontSize(14)
          .fontFamily(this.appFontFamily)
          .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_muted', this.themeState.currentTheme))
      }
      .width('100%')
      Slider({ value: $$this.hdsTabMinOpacityPercent, min: 0, max: 100, step: 1 })
        .width('100%')
        .selectedColor($r('app.color.accent_primary'))
        .trackColor($r('app.color.divider_primary'))
        .onChange((sliderValue: number) => {
          const normalizedValue: number = this.clampPercent(Math.round(sliderValue));
          this.updateHdsTabOpacityRange(normalizedValue, this.hdsTabMaxOpacityPercent);
        })
    }
    .width('100%')
  }

  @Builder
  private buildHdsTabMaxOpacitySlider() {
    Column({ space: 4 }) {
      Row() {
        Text('最大可见度')
          .fontSize(14)
          .fontFamily(this.appFontFamily)
          .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_secondary', this.themeState.currentTheme))
        Blank()
        Text(`${this.hdsTabMaxOpacityPercent}%`)
          .fontSize(14)
          .fontFamily(this.appFontFamily)
          .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_muted', this.themeState.currentTheme))
      }
      .width('100%')
      Slider({ value: $$this.hdsTabMaxOpacityPercent, min: 0, max: 100, step: 1 })
        .width('100%')
        .selectedColor($r('app.color.accent_primary'))
        .trackColor($r('app.color.divider_primary'))
        .onChange((sliderValue: number) => {
          const normalizedValue: number = this.clampPercent(Math.round(sliderValue));
          this.updateHdsTabOpacityRange(this.hdsTabMinOpacityPercent, normalizedValue);
        })
    }
    .width('100%')
  }

  @Builder
  private buildHdsTabLightHighlightSlider() {
    Column({ space: 4 }) {
      Row() {
        Text('浅色高光')
          .fontSize(14)
          .fontFamily(this.appFontFamily)
          .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_secondary', this.themeState.currentTheme))
        Blank()
        Text(`${this.hdsTabLightHighlightPercent}%`)
          .fontSize(14)
          .fontFamily(this.appFontFamily)
          .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_muted', this.themeState.currentTheme))
      }
      .width('100%')
      Slider({ value: $$this.hdsTabLightHighlightPercent, min: 0, max: 100, step: 1 })
        .width('100%')
        .selectedColor($r('app.color.accent_primary'))
        .trackColor($r('app.color.divider_primary'))
        .onChange((sliderValue: number) => {
          const normalizedValue: number = this.clampPercent(Math.round(sliderValue));
          this.hdsTabLightHighlightPercent = normalizedValue;
          this.hdsTabLightHighlightOpacity = normalizedValue / 100;
          this.updateHdsTabEffect('lightHighlightOpacity', normalizedValue / 100);
        })
    }
    .width('100%')
  }

  @Builder
  private buildHdsTabDarkHighlightSlider() {
    Column({ space: 4 }) {
      Row() {
        Text('深色高光')
          .fontSize(14)
          .fontFamily(this.appFontFamily)
          .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_secondary', this.themeState.currentTheme))
        Blank()
        Text(`${this.hdsTabDarkHighlightPercent}%`)
          .fontSize(14)
          .fontFamily(this.appFontFamily)
          .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_muted', this.themeState.currentTheme))
      }
      .width('100%')
      Slider({ value: $$this.hdsTabDarkHighlightPercent, min: 0, max: 100, step: 1 })
        .width('100%')
        .selectedColor($r('app.color.accent_primary'))
        .trackColor($r('app.color.divider_primary'))
        .onChange((sliderValue: number) => {
          const normalizedValue: number = this.clampPercent(Math.round(sliderValue));
          this.hdsTabDarkHighlightPercent = normalizedValue;
          this.hdsTabDarkHighlightOpacity = normalizedValue / 100;
          this.updateHdsTabEffect('darkHighlightOpacity', normalizedValue / 100);
        })
    }
    .width('100%')
  }

  @Builder
  private buildHdsTabSideMarginSlider() {
    Column({ space: 4 }) {
      Row() {
        Text('侧边留白')
          .fontSize(14)
          .fontFamily(this.appFontFamily)
          .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_secondary', this.themeState.currentTheme))
        Blank()
        Text(`${this.hdsTabSideMarginValue}vp`)
          .fontSize(14)
          .fontFamily(this.appFontFamily)
          .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_muted', this.themeState.currentTheme))
      }
      .width('100%')
      Slider({ value: $$this.hdsTabSideMarginValue, min: 0, max: 24, step: 1 })
        .width('100%')
        .selectedColor($r('app.color.accent_primary'))
        .trackColor($r('app.color.divider_primary'))
        .onChange((sliderValue: number) => {
          const normalizedValue: number = Math.round(sliderValue);
          this.hdsTabSideMarginValue = normalizedValue;
          this.hdsTabSideMargin = normalizedValue;
          this.updateHdsTabEffect('sideMargin', normalizedValue);
        })
    }
    .width('100%')
  }

  @Builder
  private buildHdsTabBottomMarginSlider() {
    Column({ space: 4 }) {
      Row() {
        Text('底部偏移')
          .fontSize(14)
          .fontFamily(this.appFontFamily)
          .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_secondary', this.themeState.currentTheme))
        Blank()
        Text(`${this.hdsTabBottomMarginValue}vp`)
          .fontSize(14)
          .fontFamily(this.appFontFamily)
          .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_muted', this.themeState.currentTheme))
      }
      .width('100%')
      Slider({ value: $$this.hdsTabBottomMarginValue, min: -8, max: 16, step: 1 })
        .width('100%')
        .selectedColor($r('app.color.accent_primary'))
        .trackColor($r('app.color.divider_primary'))
        .onChange((sliderValue: number) => {
          const normalizedValue: number = Math.round(sliderValue);
          this.hdsTabBottomMarginValue = normalizedValue;
          this.hdsTabBottomMargin = normalizedValue;
          this.updateHdsTabEffect('bottomMargin', normalizedValue);
        })
    }
    .width('100%')
  }

  @Builder
  private buildHdsTabEffectsPanel() {
    Column({ space: 12 }) {
      Row() {
        Text('HdsTab特效')
          .fontSize(16)
          .fontFamily(this.appFontFamily)
          .fontWeight(FontWeight.Bold)
          .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_primary', this.themeState.currentTheme))
        Blank()
        Text(this.getHdsTabMaterialLabel())
          .fontSize(12)
          .fontFamily(this.appFontFamily)
          .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_secondary', this.themeState.currentTheme))
      }
      .width('100%')
      .id('theme_hds_tab_effects')

      Row({ space: 8 }) {
        Column() {
          Text('首页')
            .fontSize(11)
            .fontFamily(this.appFontFamily)
            .fontWeight(FontWeight.Medium)
            .fontColor($r('app.color.accent_primary'))
        }
        .layoutWeight(1)
        .height(38)
        .justifyContent(FlexAlign.Center)
        .backgroundColor(this.getHdsTabPreviewHighlightColor())
        .borderRadius(19)

        Column() {
          Text('书库')
            .fontSize(11)
            .fontFamily(this.appFontFamily)
            .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_secondary', this.themeState.currentTheme))
        }
        .layoutWeight(1)
        .height(38)
        .justifyContent(FlexAlign.Center)

        Column() {
          Text('设置')
            .fontSize(11)
            .fontFamily(this.appFontFamily)
            .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_secondary', this.themeState.currentTheme))
        }
        .layoutWeight(1)
        .height(38)
        .justifyContent(FlexAlign.Center)
      }
      .width('100%')
      .height(52)
      .padding({ left: 8, right: 8, top: 7, bottom: 7 })
      .backgroundColor(SettingsPanelSurfaceHelper.getBackground(this.themeState.currentTheme))
      .backgroundBlurStyle(
        this.getHdsTabPreviewBlurStyle(),
        SettingsPanelSurfaceHelper.getBlurOptions(this.themeState.currentTheme)
      )
      .borderRadius(26)
      .opacity(this.getHdsTabPreviewOpacity())
      .border({
        width: 1,
        color: SettingsPanelSurfaceHelper.getBorderColor(this.themeState.currentTheme)
      })

      this.buildHdsTabOpacityRatioSlider()
      this.buildHdsTabMinOpacitySlider()
      this.buildHdsTabMaxOpacitySlider()
      this.buildHdsTabLightHighlightSlider()
      this.buildHdsTabDarkHighlightSlider()
      this.buildHdsTabSideMarginSlider()
      this.buildHdsTabBottomMarginSlider()

      Row() {
        Text('HDS模糊策略')
          .fontSize(14)
          .fontFamily(this.appFontFamily)
          .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_secondary', this.themeState.currentTheme))
        Blank()
        Toggle({ type: ToggleType.Switch, isOn: this.hdsTabBlurEnabled })
          .selectedColor($r('app.color.accent_primary'))
          .onChange((isOn: boolean) => {
            this.hdsTabBlurEnabled = isOn;
            this.updateHdsTabEffect('blurEnabled', isOn);
          })
      }
      .width('100%')
      .height(48)

      Column({ space: 8 }) {
        Row() {
          Text('材质档位')
            .fontSize(14)
            .fontFamily(this.appFontFamily)
            .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_secondary', this.themeState.currentTheme))
          Blank()
          Text(this.getHdsTabMaterialLabel())
            .fontSize(14)
            .fontFamily(this.appFontFamily)
            .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_muted', this.themeState.currentTheme))
        }
        .width('100%')

        Flex({ wrap: FlexWrap.Wrap, justifyContent: FlexAlign.Start }) {
          this.buildHdsTabMaterialButton('跟随全局', HDS_TAB_MATERIAL_FOLLOW_GLOBAL)
          this.buildHdsTabMaterialButton('精致', hdsMaterial.MaterialLevel.EXQUISITE)
          this.buildHdsTabMaterialButton('柔和', hdsMaterial.MaterialLevel.GENTLE)
          this.buildHdsTabMaterialButton('平滑', hdsMaterial.MaterialLevel.SMOOTH)
        }
        .width('100%')
      }
      .width('100%')

      Button('重置 HdsTab 特效')
        .width('100%')
        .height(40)
        .fontSize(14)
        .fontFamily(this.appFontFamily)
        .fontColor($r('app.color.color_error'))
        .backgroundColor(ThemeAwareHelper.getTestManagementThemedColor('comp_background_tertiary', this.themeState.currentTheme))
        .onClick(() => {
          this.resetHdsTabEffectsToDefault();
        })
    }
    .width(this.responsive_isLandscape ? '48%' : '100%')
    .padding(16)
    .backgroundColor(SettingsPanelSurfaceHelper.getBackground(this.themeState.currentTheme))
    .linearGradient(SettingsPanelSurfaceHelper.getSurfaceGradient(this.themeState.currentTheme))
    .backgroundBlurStyle(
      SettingsPanelSurfaceHelper.getBlurStyle(this.themeState.currentTheme),
      SettingsPanelSurfaceHelper.getBlurOptions(this.themeState.currentTheme)
    )
    .backgroundEffect(SettingsPanelSurfaceHelper.getBackgroundEffect(this.themeState.currentTheme))
    .borderRadius(SettingsPanelSurfaceHelper.getRadius(this.themeState.currentTheme))
    .clip(true)
    .border({
      width: SettingsSearchSupport.isHighlightActive(this.activeSearchAnchorId, 'theme_hds_tab_effects')
        ? 2
        : SettingsPanelSurfaceHelper.getBorderWidth(this.themeState.currentTheme),
      color: SettingsSearchSupport.isHighlightActive(this.activeSearchAnchorId, 'theme_hds_tab_effects')
        ? SettingsSearchSupport.getHighlightOverlayBorder(
          this.themeState.currentTheme,
          this.activeSearchAnchorId,
          'theme_hds_tab_effects'
        )
        : SettingsPanelSurfaceHelper.getBorderColor(this.themeState.currentTheme)
    })
    .scale({
      x: SettingsSearchSupport.getHighlightScale(this.activeSearchAnchorId, 'theme_hds_tab_effects', this.searchHighlightPulse),
      y: SettingsSearchSupport.getHighlightScale(this.activeSearchAnchorId, 'theme_hds_tab_effects', this.searchHighlightPulse)
    })
    .shadow(
      SettingsSearchSupport.isHighlightActive(this.activeSearchAnchorId, 'theme_hds_tab_effects')
        ? SettingsSearchSupport.getHighlightOverlayShadow(
          this.themeState.currentTheme,
          this.activeSearchAnchorId,
          'theme_hds_tab_effects',
          this.searchHighlightPulse
        )
        : {
          radius: SettingsPanelSurfaceHelper.getRadius(this.themeState.currentTheme) + 4,
          color: SettingsPanelSurfaceHelper.getShadowColor(this.themeState.currentTheme),
          offsetX: 0,
          offsetY: 8
        }
    )
    .animation({ duration: 260, curve: Curve.EaseOut })
    .margin({ bottom: 16 })
  }

  build() {
    HdsNavDestination() {
      Stack({ alignContent: Alignment.TopStart }) {
        // 背景层
        SharedPageBackgroundLayer({
          defaultBackgroundColor: ThemeAwareHelper.getTestManagementThemedColor('background_dark', this.themeState.currentTheme),
          mode: GlobalBackgroundLayerMode.IMMERSIVE
        })
          .width('100%')
          .height('100%')
          .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.TOP, SafeAreaEdge.BOTTOM])

        // 内容层
        Column() {
          // 预留标题栏占位（与 HdsNavDestination 标题栏高度一致）
          // Blank().height(56)

          // 内容区域
          Scroll(this.scroller) {
            Flex({
              wrap: FlexWrap.Wrap,
              justifyContent: this.responsive_isLandscape ? FlexAlign.SpaceBetween : FlexAlign.Start
            }) {
              Blank()
                .height(SettingsPageTitleBarManager.getContentTopPadding(this.statusBarHeight))
                .width('100%')
              // 主题商店（列表 + 创建入口）
              if (!this.isCreatingCustomTheme) {
                Column({ space: 12 }) {
                  Row() {
                    Text('自定义主题')
                      .fontSize(16)
                      .fontFamily(this.appFontFamily)
                      .fontWeight(FontWeight.Bold)
                      .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_primary', this.themeState.currentTheme))
                    Blank()
                    Text(`${this.customThemes.length} 个`)
                      .fontSize(12)
                      .fontFamily(this.appFontFamily)
                      .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_secondary', this.themeState.currentTheme))
                  }
                  .width('100%')
                  .id('theme_custom')

                  if (this.customThemes.length > 0) {
                    Grid() {
                      ForEach(this.customThemes, (theme: CustomTheme) => {
                        GridItem() {
                          Column() {
                            // 主题背景图片预览 - 显示缩略图或占位符
                            Stack() {
                              if (this.resolveThemePreviewSource(theme)) {
                                Column()
                                  .width('100%')
                                  .height(120)
                                  .backgroundImage(this.resolveThemePreviewSource(theme), {
                                    repeat: ImageRepeat.NoRepeat,
                                    syncLoad: true
                                  })
                                  .backgroundImageSize(ImageSize.Cover)
                                  .backgroundImagePosition(Alignment.Top)
                                  .borderRadius(12)
                                  .clip(true)
                              } else {
                                // 无背景图片时显示主题色渐变占位符
                                Column()
                                  .width('100%')
                                  .height(120)
                                  .borderRadius(12)
                                  .linearGradient({
                                    angle: 135,
                                    colors: [[theme.primaryColor, 0.0], [this.isDarkPreviewTheme(theme) ? '#1A1A1A' : '#F5F5F5', 1.0]]
                                  })

                                Text('默认主题')
                                  .fontSize(14)
                                  .fontFamily(this.appFontFamily)
                                  .fontColor(this.isDarkPreviewTheme(theme) ? '#FFFFFF' : '#333333')
                                  .opacity(0.7)
                              }

                              // 当前激活指示器
                              if (this.currentCustomThemeId === theme.id) {
                                Column()
                                  .width('100%')
                                  .height(120)
                                  .borderRadius(12)
                                  .border({ width: 3, color: $r('app.color.accent_primary') })
                              }

                              // 多选模式下的选中指示器
                              if (this.selectionModeEnabled) {
                                Column()
                                  .width(28)
                                  .height(28)
                                  .backgroundColor(this.isThemeSelected(theme.id) ? $r('app.color.accent_primary') : 'rgba(255,255,255,0.8)')
                                  .borderRadius(14)
                                  .border({ width: 2, color: $r('app.color.accent_primary') })
                                  .align(Alignment.TopStart)
                                  .margin({ left: 8, top: 8 })
                              }
                            }
                            .width('100%')
                            .height(120)

                            Row({ space: 8 }) {
                              // 主题色块
                              Column()
                                .width(24)
                                .height(24)
                                .backgroundColor(theme.primaryColor)
                                .borderRadius(4)

                              Column({ space: 4 }) {
                                Text(theme.name)
                                  .fontSize(14)
                                  .fontFamily(this.appFontFamily)
                                  .fontWeight(FontWeight.Medium)
                                  .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_primary', this.themeState.currentTheme))
                                  .maxLines(1)
                                  .textOverflow({ overflow: TextOverflow.Ellipsis })
                                Text(`${this.getThemeModeLabel(this.getThemeModeFromTheme(theme))}主题`)
                                  .fontSize(12)
                                  .fontFamily(this.appFontFamily)
                                  .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_secondary', this.themeState.currentTheme))
                              }
                              .layoutWeight(1)
                              .alignItems(HorizontalAlign.Start)

                              Row({ space: 6 }) {
                                Button('编辑')
                                  .fontSize(12)
                                  .height(32)
                                  .fontFamily(this.appFontFamily)
                                  .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_primary', this.themeState.currentTheme))
                                  .backgroundColor(ThemeAwareHelper.getTestManagementThemedColor('comp_background_tertiary', this.themeState.currentTheme))
                                  .enabled(!this.selectionModeEnabled)
                                  .onClick(async () => {
                                    await this.editExistingTheme(theme);
                                  })
                                Button(this.currentCustomThemeId === theme.id ? '已激活' : '应用')
                                  .fontSize(12)
                                  .height(32)
                                  .fontFamily(this.appFontFamily)
                                  .backgroundColor(this.currentCustomThemeId === theme.id ? $r('app.color.text_secondary') : $r('app.color.accent_primary'))
                                  .enabled(this.currentCustomThemeId !== theme.id && !this.selectionModeEnabled)
                                  .onClick(async () => {
                                    try {
                                      await this.applyCustomThemeToManager(theme);
                                      logger.info(TAG, `已应用保存的主题: ${theme.name}`);
                                    } catch (error) {
                                      logger.error(TAG, `应用主题失败: ${error instanceof Error ? error.message : String(error)}`);
                                    }
                                  })
                              }
                            }
                            .width('100%')
                            .padding({ top: 8 })
                          }
                          .width('100%')
                          .padding(12)
                          .backgroundColor(SettingsPanelSurfaceHelper.getBackground(this.themeState.currentTheme))
                          .linearGradient(SettingsPanelSurfaceHelper.getSurfaceGradient(this.themeState.currentTheme))
                          .backgroundBlurStyle(
                            SettingsPanelSurfaceHelper.getBlurStyle(this.themeState.currentTheme),
                            SettingsPanelSurfaceHelper.getBlurOptions(this.themeState.currentTheme)
                          )
                          .backgroundEffect(SettingsPanelSurfaceHelper.getBackgroundEffect(this.themeState.currentTheme))
                          .borderRadius(SettingsPanelSurfaceHelper.getRadius(this.themeState.currentTheme))
                          .clip(true)
                          .border({
                            width: SettingsPanelSurfaceHelper.getBorderWidth(this.themeState.currentTheme),
                            color: SettingsPanelSurfaceHelper.getBorderColor(this.themeState.currentTheme)
                          })
                          .shadow({
                            radius: SettingsPanelSurfaceHelper.getRadius(this.themeState.currentTheme) + 4,
                            color: SettingsPanelSurfaceHelper.getShadowColor(this.themeState.currentTheme),
                            offsetX: 0,
                            offsetY: 8
                          })
                          // 长按进入/切换选择，点击在选择模式下也切换选中
                          .gesture(LongPressGesture().onAction(() => { this.toggleThemeSelection(theme.id); }))
                          .onClick(() => {
                            if (this.selectionModeEnabled) {
                              this.toggleThemeSelection(theme.id);
                            }
                          })
                        }
                      }, (theme: CustomTheme) => theme.id)
                    }
                    .columnsTemplate(this.responsive_isLandscape ? '1fr 1fr' : '1fr')
                    .columnsGap(12)
                    .rowsGap(12)
                    .width('100%')
                  }

                  Button('创建自定义主题')
                    .width('100%')
                    .height(48)
                    .fontSize(16)
                    .fontFamily(this.appFontFamily)
                    .backgroundColor($r('app.color.accent_primary'))
                    .onClick(() => {
                      this.beginCreateCustomTheme();
                    })

                  Button('关闭自定义主题')
                    .width('100%')
                    .height(48)
                    .fontSize(16)
                    .fontFamily(this.appFontFamily)
                    .fontColor('#FFFFFF')
                    .backgroundColor($r('app.color.color_error'))
                    .enabled(this.currentCustomThemeId.length > 0)
                    .opacity(this.currentCustomThemeId.length > 0 ? 1 : 0.55)
                    .onClick(() => { this.showDisableCustomThemeConfirmDialog(); })
                }
                .width(this.responsive_isLandscape ? '48%' : '100%')
                .padding(16)
                .backgroundColor(SettingsPanelSurfaceHelper.getBackground(this.themeState.currentTheme))
                .linearGradient(SettingsPanelSurfaceHelper.getSurfaceGradient(this.themeState.currentTheme))
                .backgroundBlurStyle(
                  SettingsPanelSurfaceHelper.getBlurStyle(this.themeState.currentTheme),
                  SettingsPanelSurfaceHelper.getBlurOptions(this.themeState.currentTheme)
                )
                .backgroundEffect(SettingsPanelSurfaceHelper.getBackgroundEffect(this.themeState.currentTheme))
                .borderRadius(SettingsPanelSurfaceHelper.getRadius(this.themeState.currentTheme))
                .clip(true)
                .border({
                  width: SettingsSearchSupport.isHighlightActive(this.activeSearchAnchorId, 'theme_custom')
                    ? 2
                    : SettingsPanelSurfaceHelper.getBorderWidth(this.themeState.currentTheme),
                  color: SettingsSearchSupport.isHighlightActive(this.activeSearchAnchorId, 'theme_custom')
                    ? SettingsSearchSupport.getHighlightOverlayBorder(this.themeState.currentTheme, this.activeSearchAnchorId, 'theme_custom')
                    : SettingsPanelSurfaceHelper.getBorderColor(this.themeState.currentTheme)
                })
                .scale({
                  x: SettingsSearchSupport.getHighlightScale(this.activeSearchAnchorId, 'theme_custom', this.searchHighlightPulse),
                  y: SettingsSearchSupport.getHighlightScale(this.activeSearchAnchorId, 'theme_custom', this.searchHighlightPulse)
                })
                .shadow(
                  SettingsSearchSupport.isHighlightActive(this.activeSearchAnchorId, 'theme_custom')
                    ? SettingsSearchSupport.getHighlightOverlayShadow(
                        this.themeState.currentTheme,
                        this.activeSearchAnchorId,
                        'theme_custom',
                        this.searchHighlightPulse
                      )
                    : {
                        radius: SettingsPanelSurfaceHelper.getRadius(this.themeState.currentTheme) + 4,
                        color: SettingsPanelSurfaceHelper.getShadowColor(this.themeState.currentTheme),
                        offsetX: 0,
                        offsetY: 8
                      }
                )
                .animation({ duration: 260, curve: Curve.EaseOut })
                .margin({ bottom: 16 })
                
                // 透明度设置面板（应用实时预览）
                Column({ space: 12 }) {
                  Row() {
                    Text('透明度设置')
                      .fontSize(16)
                      .fontFamily(this.appFontFamily)
                      .fontWeight(FontWeight.Bold)
                      .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_primary', this.themeState.currentTheme))
                    Blank()
                    Text('实时预览')
                      .fontSize(12)
                      .fontFamily(this.appFontFamily)
                      .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_secondary', this.themeState.currentTheme))
                  }
                  .width('100%')
                  .id('theme_transparency')
                  
                  // 预览卡片
                  Column({ space: 8 }) {
                    Text('预览效果')
                      .fontSize(12)
                      .fontFamily(this.appFontFamily)
                      .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_secondary', this.themeState.currentTheme))
                    Flex({
                      wrap: FlexWrap.Wrap,
                      justifyContent: FlexAlign.SpaceAround
                    }) {
                      // 卡片预览（使用StorageLink绑定的值实现实时预览）
                      Column() {
                        Text('卡片')
                          .fontSize(10)
                          .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_primary', this.themeState.currentTheme))
                      }
                      .width(60)
                      .height(40)
                      .justifyContent(FlexAlign.Center)
                      .backgroundColor(SettingsPanelSurfaceHelper.getBackground(this.themeState.currentTheme))
                      .linearGradient(SettingsPanelSurfaceHelper.getSurfaceGradient(this.themeState.currentTheme))
                      .backgroundBlurStyle(
                        SettingsPanelSurfaceHelper.getBlurStyle(this.themeState.currentTheme),
                        SettingsPanelSurfaceHelper.getBlurOptions(this.themeState.currentTheme)
                      )
                      .backgroundEffect(SettingsPanelSurfaceHelper.getBackgroundEffect(this.themeState.currentTheme))
                      .borderRadius(this.componentCornerRadius)
                      .clip(true)
                      .border({
                        width: SettingsPanelSurfaceHelper.getBorderWidth(this.themeState.currentTheme),
                        color: SettingsPanelSurfaceHelper.getBorderColor(this.themeState.currentTheme)
                      })
                      .opacity(this.cardOpacity)
                      .shadow(this.shadowEnabled ? { radius: 4, color: 'rgba(0,0,0,0.2)', offsetY: 2 } : undefined)
                      
                      // 悬浮球预览
                      Column() {
                        Text('悬浮球')
                          .fontSize(8)
                          .fontColor(Color.White)
                      }
                      .width(50)
                      .height(50)
                      .justifyContent(FlexAlign.Center)
                      .backgroundColor($r('app.color.accent_primary'))
                      .borderRadius(25)
                      .opacity(this.floatingBallOpacity)
                      .shadow(this.shadowEnabled ? { radius: 6, color: 'rgba(0,0,0,0.3)', offsetY: 2 } : undefined)

                      // 封面图片预览
                      Stack({ alignContent: Alignment.Bottom }) {
                        Column()
                          .width(50)
                          .height(68)
                          .backgroundColor($r('app.color.accent_primary'))
                          .opacity(0.9)
                          .borderRadius(this.coverCornerRadius)

                        Text('封面')
                          .fontSize(10)
                          .fontFamily(this.appFontFamily)
                          .fontWeight(FontWeight.Medium)
                          .fontColor(Color.White)
                          .margin({ bottom: 6 })
                      }
                      .width(50)
                      .height(68)
                      .shadow(this.shadowEnabled ? { radius: 6, color: 'rgba(0,0,0,0.25)', offsetY: 3 } : undefined)
                      
                      // 对话框预览
                      Column() {
                        Text('对话框')
                          .fontSize(10)
                          .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_primary', this.themeState.currentTheme))
                      }
                      .width(60)
                      .height(40)
                      .justifyContent(FlexAlign.Center)
                      .backgroundColor(ThemeAwareHelper.getTestManagementThemedColor('comp_background_tertiary', this.themeState.currentTheme))
                      .borderRadius(this.componentCornerRadius)
                      .opacity(this.dialogOpacity)
                      .shadow(this.shadowEnabled ? { radius: 4, color: 'rgba(0,0,0,0.2)', offsetY: 2 } : undefined)
                    }
                    .width('100%')
                  }
                  .width('100%')
                  .padding(12)
                  .backgroundColor(ThemeAwareHelper.getTestManagementThemedColor('comp_background_tertiary', this.themeState.currentTheme))
                  .borderRadius(8)
                  
                  // 导航栏透明度
                  Column({ space: 4 }) {
                    Row() {
                      Text('导航栏')
                        .fontSize(14)
                        .fontFamily(this.appFontFamily)
                        .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_secondary', this.themeState.currentTheme))
                      Blank()
                      Text(`${this.navBarTransparency}%`)
                        .fontSize(14)
                        .fontFamily(this.appFontFamily)
                        .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_muted', this.themeState.currentTheme))
                    }
                    .width('100%')
                    Slider({ value: $$this.navBarTransparency, min: 0, max: 100, step: 5 })
                      .width('100%')
                      .selectedColor($r('app.color.accent_primary'))
                      .trackColor($r('app.color.divider_primary'))
                      .onChange((value: number) => {
                        this.updateTransparency('navigationBar', value / 100);
                      })
                  }
                  
                  // 卡片透明度
                  Column({ space: 4 }) {
                    Row() {
                      Text('卡片')
                        .fontSize(14)
                        .fontFamily(this.appFontFamily)
                        .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_secondary', this.themeState.currentTheme))
                      Blank()
                      Text(`${this.cardTransparency}%`)
                        .fontSize(14)
                        .fontFamily(this.appFontFamily)
                        .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_muted', this.themeState.currentTheme))
                    }
                    .width('100%')
                    Slider({ value: $$this.cardTransparency, min: 0, max: 100, step: 5 })
                      .width('100%')
                      .selectedColor($r('app.color.accent_primary'))
                      .trackColor($r('app.color.divider_primary'))
                      .onChange((value: number) => {
                        this.updateTransparency('card', value / 100);
                      })
                  }
                  
                  // 对话框透明度
                  Column({ space: 4 }) {
                    Row() {
                      Text('对话框')
                        .fontSize(14)
                        .fontFamily(this.appFontFamily)
                        .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_secondary', this.themeState.currentTheme))
                      Blank()
                      Text(`${this.dialogTransparency}%`)
                        .fontSize(14)
                        .fontFamily(this.appFontFamily)
                        .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_muted', this.themeState.currentTheme))
                    }
                    .width('100%')
                    Slider({ value: $$this.dialogTransparency, min: 0, max: 100, step: 5 })
                      .width('100%')
                      .selectedColor($r('app.color.accent_primary'))
                      .trackColor($r('app.color.divider_primary'))
                      .onChange((value: number) => {
                        this.updateTransparency('dialog', value / 100);
                      })
                  }
                  
                  // 悬浮球透明度
                  Column({ space: 4 }) {
                    Row() {
                      Text('悬浮球')
                        .fontSize(14)
                        .fontFamily(this.appFontFamily)
                        .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_secondary', this.themeState.currentTheme))
                      Blank()
                      Text(`${this.floatingBallTransparency}%`)
                        .fontSize(14)
                        .fontFamily(this.appFontFamily)
                        .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_muted', this.themeState.currentTheme))
                    }
                    .width('100%')
                    Slider({ value: $$this.floatingBallTransparency, min: 0, max: 100, step: 5 })
                      .width('100%')
                      .selectedColor($r('app.color.accent_primary'))
                      .trackColor($r('app.color.divider_primary'))
                      .onChange((value: number) => {
                        this.updateTransparency('floatingBall', value / 100);
                      })
                  }
                }
                .width(this.responsive_isLandscape ? '48%' : '100%')
                .padding(16)
                .backgroundColor(SettingsPanelSurfaceHelper.getBackground(this.themeState.currentTheme))
                .linearGradient(SettingsPanelSurfaceHelper.getSurfaceGradient(this.themeState.currentTheme))
                .backgroundBlurStyle(
                  SettingsPanelSurfaceHelper.getBlurStyle(this.themeState.currentTheme),
                  SettingsPanelSurfaceHelper.getBlurOptions(this.themeState.currentTheme)
                )
                .backgroundEffect(SettingsPanelSurfaceHelper.getBackgroundEffect(this.themeState.currentTheme))
                .borderRadius(SettingsPanelSurfaceHelper.getRadius(this.themeState.currentTheme))
                .clip(true)
                .border({
                  width: SettingsSearchSupport.isHighlightActive(this.activeSearchAnchorId, 'theme_transparency')
                    ? 2
                    : SettingsPanelSurfaceHelper.getBorderWidth(this.themeState.currentTheme),
                  color: SettingsSearchSupport.isHighlightActive(this.activeSearchAnchorId, 'theme_transparency')
                    ? SettingsSearchSupport.getHighlightOverlayBorder(
                      this.themeState.currentTheme,
                      this.activeSearchAnchorId,
                      'theme_transparency'
                    )
                    : SettingsPanelSurfaceHelper.getBorderColor(this.themeState.currentTheme)
                })
                .scale({
                  x: SettingsSearchSupport.getHighlightScale(this.activeSearchAnchorId, 'theme_transparency', this.searchHighlightPulse),
                  y: SettingsSearchSupport.getHighlightScale(this.activeSearchAnchorId, 'theme_transparency', this.searchHighlightPulse)
                })
                .shadow(
                  SettingsSearchSupport.isHighlightActive(this.activeSearchAnchorId, 'theme_transparency')
                    ? SettingsSearchSupport.getHighlightOverlayShadow(
                        this.themeState.currentTheme,
                        this.activeSearchAnchorId,
                        'theme_transparency',
                        this.searchHighlightPulse
                      )
                    : {
                        radius: SettingsPanelSurfaceHelper.getRadius(this.themeState.currentTheme) + 4,
                        color: SettingsPanelSurfaceHelper.getShadowColor(this.themeState.currentTheme),
                        offsetX: 0,
                        offsetY: 8
                      }
                )
                .animation({ duration: 260, curve: Curve.EaseOut })
                .margin({ bottom: 16 })
                
                // 特效设置面板
                Column({ space: 12 }) {
                  Row() {
                    Text('特效设置')
                      .fontSize(16)
                      .fontFamily(this.appFontFamily)
                      .fontWeight(FontWeight.Bold)
                      .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_primary', this.themeState.currentTheme))
                    Blank()
                    Text('视觉层次')
                      .fontSize(12)
                      .fontFamily(this.appFontFamily)
                      .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_secondary', this.themeState.currentTheme))
                  }
                  .width('100%')
                  .id('theme_effects')
                  
                  // 模糊效果开关
                  Row() {
                    Text('模糊效果')
                      .fontSize(14)
                      .fontFamily(this.appFontFamily)
                      .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_secondary', this.themeState.currentTheme))
                    Blank()
                    Toggle({ type: ToggleType.Switch, isOn: this.blurEnabled })
                      .selectedColor($r('app.color.accent_primary'))
                      .onChange((isOn: boolean) => {
                        this.updateEffect('enableBlur', isOn);
                      })
                  }
                  .width('100%')
                  .height(48)
                  
                  // 模糊强度（仅在启用时显示）
                  if (this.blurEnabled) {
                    Column({ space: 4 }) {
                      Row() {
                        Text('模糊强度')
                          .fontSize(14)
                          .fontFamily(this.appFontFamily)
                          .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_secondary', this.themeState.currentTheme))
                        Blank()
                        Text(`${this.effectBlurIntensity}`)
                          .fontSize(14)
                          .fontFamily(this.appFontFamily)
                          .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_muted', this.themeState.currentTheme))
                      }
                      .width('100%')
                      Slider({ value: $$this.effectBlurIntensity, min: 0, max: 100, step: 5 })
                        .width('100%')
                        .selectedColor($r('app.color.accent_primary'))
                        .trackColor($r('app.color.divider_primary'))
                        .onChange((value: number) => {
                          this.updateEffect('blurIntensity', value);
                        })
                    }
                  }
                  
                  // 阴影效果开关
                  Row() {
                    Text('阴影效果')
                      .fontSize(14)
                      .fontFamily(this.appFontFamily)
                      .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_secondary', this.themeState.currentTheme))
                    Blank()
                    Toggle({ type: ToggleType.Switch, isOn: this.shadowEnabled })
                      .selectedColor($r('app.color.accent_primary'))
                      .onChange((isOn: boolean) => {
                        this.updateEffect('enableShadow', isOn);
                      })
                  }
                  .width('100%')
                  .height(48)
                  
                  // 动画效果开关
                  Row() {
                    Text('动画效果')
                      .fontSize(14)
                      .fontFamily(this.appFontFamily)
                      .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_secondary', this.themeState.currentTheme))
                    Blank()
                    Toggle({ type: ToggleType.Switch, isOn: this.animationEnabled })
                      .selectedColor($r('app.color.accent_primary'))
                      .onChange((isOn: boolean) => {
                        this.updateEffect('enableAnimation', isOn);
                      })
                  }
                  .width('100%')
                  .height(48)
                  
                  // 动画速度（仅在启用时显示）
                  if (this.animationEnabled) {
                    Column({ space: 4 }) {
                      Row() {
                        Text('动画速度')
                          .fontSize(14)
                          .fontFamily(this.appFontFamily)
                          .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_secondary', this.themeState.currentTheme))
                        Blank()
                        Text(`${this.effectAnimationSpeed}%`)
                          .fontSize(14)
                          .fontFamily(this.appFontFamily)
                          .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_muted', this.themeState.currentTheme))
                      }
                      .width('100%')
                      Slider({ value: $$this.effectAnimationSpeed, min: 50, max: 200, step: 10 })
                        .width('100%')
                        .selectedColor($r('app.color.accent_primary'))
                        .trackColor($r('app.color.divider_primary'))
                        .onChange((value: number) => {
                          this.updateEffect('animationSpeed', value / 100);
                        })
                    }
                  }
                  
                  // 组件圆角
                  Column({ space: 4 }) {
                    Row() {
                      Text('组件圆角')
                        .fontSize(14)
                        .fontFamily(this.appFontFamily)
                        .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_secondary', this.themeState.currentTheme))
                      Blank()
                      Text(`${this.effectComponentCornerRadius}`)
                        .fontSize(14)
                        .fontFamily(this.appFontFamily)
                        .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_muted', this.themeState.currentTheme))
                    }
                    .width('100%')
                    Slider({ value: $$this.effectComponentCornerRadius, min: 0, max: 32, step: 2 })
                      .width('100%')
                      .selectedColor($r('app.color.accent_primary'))
                      .trackColor($r('app.color.divider_primary'))
                      .onChange((value: number) => {
                        this.updateEffect('componentCornerRadius', value);
                      })
                  }

                  // 封面图片圆角
                  Column({ space: 4 }) {
                    Row() {
                      Text('封面图片圆角')
                        .fontSize(14)
                        .fontFamily(this.appFontFamily)
                        .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_secondary', this.themeState.currentTheme))
                      Blank()
                      Text(`${this.effectCoverCornerRadius}`)
                        .fontSize(14)
                        .fontFamily(this.appFontFamily)
                        .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_muted', this.themeState.currentTheme))
                    }
                    .width('100%')
                    Slider({ value: $$this.effectCoverCornerRadius, min: 0, max: 32, step: 2 })
                      .width('100%')
                      .selectedColor($r('app.color.accent_primary'))
                      .trackColor($r('app.color.divider_primary'))
                      .onChange((value: number) => {
                        this.updateEffect('coverCornerRadius', value);
                      })
                  }
                  
                  // 玻璃拟态效果开关
                  Row() {
                    Text('玻璃拟态效果')
                      .fontSize(14)
                      .fontFamily(this.appFontFamily)
                      .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_secondary', this.themeState.currentTheme))
                    Blank()
                    Toggle({ type: ToggleType.Switch, isOn: this.glassmorphismEnabled })
                      .selectedColor($r('app.color.accent_primary'))
                      .onChange((isOn: boolean) => {
                        this.updateEffect('enableGlassmorphism', isOn);
                      })
                  }
                  .width('100%')
                  .height(48)
                  
                  // 重置按钮
                  Button('重置为默认')
                    .width('100%')
                    .height(40)
                    .fontSize(14)
                    .fontFamily(this.appFontFamily)
                    .fontColor($r('app.color.color_error'))
                    .backgroundColor(ThemeAwareHelper.getTestManagementThemedColor('comp_background_tertiary', this.themeState.currentTheme))
                    .onClick(() => { this.resetEffectsToDefault(); })
                }
                .width(this.responsive_isLandscape ? '48%' : '100%')
                .padding(16)
                .backgroundColor(SettingsPanelSurfaceHelper.getBackground(this.themeState.currentTheme))
                .linearGradient(SettingsPanelSurfaceHelper.getSurfaceGradient(this.themeState.currentTheme))
                .backgroundBlurStyle(
                  SettingsPanelSurfaceHelper.getBlurStyle(this.themeState.currentTheme),
                  SettingsPanelSurfaceHelper.getBlurOptions(this.themeState.currentTheme)
                )
                .backgroundEffect(SettingsPanelSurfaceHelper.getBackgroundEffect(this.themeState.currentTheme))
                .borderRadius(SettingsPanelSurfaceHelper.getRadius(this.themeState.currentTheme))
                .clip(true)
                .border({
                  width: SettingsSearchSupport.isHighlightActive(this.activeSearchAnchorId, 'theme_effects')
                    ? 2
                    : SettingsPanelSurfaceHelper.getBorderWidth(this.themeState.currentTheme),
                  color: SettingsSearchSupport.isHighlightActive(this.activeSearchAnchorId, 'theme_effects')
                    ? SettingsSearchSupport.getHighlightOverlayBorder(this.themeState.currentTheme, this.activeSearchAnchorId, 'theme_effects')
                    : SettingsPanelSurfaceHelper.getBorderColor(this.themeState.currentTheme)
                })
                .scale({
                  x: SettingsSearchSupport.getHighlightScale(this.activeSearchAnchorId, 'theme_effects', this.searchHighlightPulse),
                  y: SettingsSearchSupport.getHighlightScale(this.activeSearchAnchorId, 'theme_effects', this.searchHighlightPulse)
                })
                .shadow(
                  SettingsSearchSupport.isHighlightActive(this.activeSearchAnchorId, 'theme_effects')
                    ? SettingsSearchSupport.getHighlightOverlayShadow(
                        this.themeState.currentTheme,
                        this.activeSearchAnchorId,
                        'theme_effects',
                        this.searchHighlightPulse
                      )
                    : {
                        radius: SettingsPanelSurfaceHelper.getRadius(this.themeState.currentTheme) + 4,
                        color: SettingsPanelSurfaceHelper.getShadowColor(this.themeState.currentTheme),
                        offsetX: 0,
                        offsetY: 8
                      }
                )
                .animation({ duration: 260, curve: Curve.EaseOut })
                .margin({ bottom: 16 })

              }

              // 选择图片按钮（背景）仅创建模式
              if (this.isCreatingCustomTheme) {
                Column({ space: 12 }) {
                  Text(this.isEditingCustomTheme ? '编辑主题素材' : '创建主题素材')
                    .fontSize(16)
                    .fontFamily(this.appFontFamily)
                    .fontWeight(FontWeight.Bold)
                    .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_primary', this.themeState.currentTheme))
                    .width('100%')

                  this.buildSplashVisibilityOptions()

                  this.buildThemeModeOptions()

                  Text('使用胶囊标签页分别配置背景图与开屏图，二者都支持取景框裁剪和旋转')
                    .fontSize(12)
                    .fontFamily(this.appFontFamily)
                    .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_secondary', this.themeState.currentTheme))
                    .width('100%')
                    .opacity(0.82)

                  this.buildMediaCapsuleTabBar()

                  if (this.mediaEditorTab === ThemeMediaTabType.BACKGROUND) {
                    Column({ space: 10 }) {
                      Text('背景图片将用于阅读器与页面背景展示')
                        .fontSize(12)
                        .fontFamily(this.appFontFamily)
                        .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_secondary', this.themeState.currentTheme))
                        .width('100%')
                        .opacity(0.82)

                      Button('选择背景图片')
                        .width('100%')
                        .height(44)
                        .fontSize(15)
                        .fontFamily(this.appFontFamily)
                        .backgroundColor($r('app.color.accent_primary'))
                        .onClick(() => this.selectImage())

                      if (this.backgroundDraftImagePaths.length > 0) {
                        Text(`已导入 ${this.backgroundDraftImagePaths.length} 张背景图`)
                          .fontSize(12)
                          .fontFamily(this.appFontFamily)
                          .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_secondary', this.themeState.currentTheme))
                          .width('100%')
                      }
                    }
                    .width('100%')
                  } else {
                    Column({ space: 10 }) {
                      Text('开屏图支持多图轮换，可为每一张独立保存裁剪结果')
                        .fontSize(12)
                        .fontFamily(this.appFontFamily)
                        .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_secondary', this.themeState.currentTheme))
                        .width('100%')
                        .opacity(0.82)

                      Button('选择开屏图片')
                        .width('100%')
                        .height(44)
                        .fontSize(15)
                        .fontFamily(this.appFontFamily)
                        .backgroundColor($r('app.color.accent_primary'))
                        .onClick(() => this.selectSplashImage())

                      Row({ space: 8 }) {
                        Text(`已导入 ${this.splashSourceImagePaths.length} 张开屏图`)
                          .fontSize(12)
                          .fontFamily(this.appFontFamily)
                          .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_secondary', this.themeState.currentTheme))
                          .layoutWeight(1)
                        Button('清空列表')
                          .height(32)
                          .fontSize(12)
                          .fontFamily(this.appFontFamily)
                          .backgroundColor(ThemeAwareHelper.getTestManagementThemedColor('comp_background_tertiary', this.themeState.currentTheme))
                          .enabled(this.splashSourceImagePaths.length > 0)
                          .onClick(() => {
                            this.clearCurrentSplashSelection();
                            this.cleanupSplashDraftFiles();
                          })
                      }
                      .width('100%')

                      Text(`轮换规则：${this.getSplashRotationRuleLabel(this.splashRotationRule)}`)
                        .fontSize(12)
                        .fontFamily(this.appFontFamily)
                        .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_secondary', this.themeState.currentTheme))
                        .width('100%')

                      Column({ space: 6 }) {
                        ForEach(this.splashRotationOptions, (option: SplashRotationOption) => {
                          Row({ space: 8 }) {
                            Text(option.label)
                              .fontSize(13)
                              .fontFamily(this.appFontFamily)
                              .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_primary', this.themeState.currentTheme))
                              .layoutWeight(1)
                            if (this.splashRotationRule === option.value) {
                              Text('当前')
                                .fontSize(12)
                                .fontFamily(this.appFontFamily)
                                .fontColor($r('app.color.accent_primary'))
                            }
                          }
                          .width('100%')
                          .padding({ left: 10, right: 10, top: 8, bottom: 8 })
                          .backgroundColor(
                            this.splashRotationRule === option.value
                              ? ThemeAwareHelper.getTestManagementThemedColor('comp_background_tertiary', this.themeState.currentTheme)
                              : 'rgba(0, 0, 0, 0)'
                          )
                          .borderRadius(8)
                          .border({
                            width: this.splashRotationRule === option.value ? 1 : 0,
                            color: $r('app.color.accent_primary')
                          })
                          .onClick(() => {
                            this.splashRotationRule = option.value;
                          })
                        }, (option: SplashRotationOption) => option.value)
                      }
                      .width('100%')
                    }
                    .width('100%')
                  }
                }
                .id('theme_create_background')
                .width(this.responsive_isLandscape ? '48%' : '100%')
                .padding(16)
                .backgroundColor(SettingsPanelSurfaceHelper.getBackground(this.themeState.currentTheme))
                .linearGradient(SettingsPanelSurfaceHelper.getSurfaceGradient(this.themeState.currentTheme))
                .backgroundBlurStyle(
                  SettingsPanelSurfaceHelper.getBlurStyle(this.themeState.currentTheme),
                  SettingsPanelSurfaceHelper.getBlurOptions(this.themeState.currentTheme)
                )
                .backgroundEffect(SettingsPanelSurfaceHelper.getBackgroundEffect(this.themeState.currentTheme))
                .borderRadius(SettingsPanelSurfaceHelper.getRadius(this.themeState.currentTheme))
                .clip(true)
                .border({
                  width: SettingsSearchSupport.isHighlightActive(this.activeSearchAnchorId, 'theme_create_background')
                    ? 2
                    : SettingsPanelSurfaceHelper.getBorderWidth(this.themeState.currentTheme),
                  color: SettingsSearchSupport.isHighlightActive(this.activeSearchAnchorId, 'theme_create_background')
                    ? SettingsSearchSupport.getHighlightOverlayBorder(
                      this.themeState.currentTheme,
                      this.activeSearchAnchorId,
                      'theme_create_background'
                    )
                    : SettingsPanelSurfaceHelper.getBorderColor(this.themeState.currentTheme)
                })
                .scale({
                  x: SettingsSearchSupport.getHighlightScale(
                    this.activeSearchAnchorId,
                    'theme_create_background',
                    this.searchHighlightPulse
                  ),
                  y: SettingsSearchSupport.getHighlightScale(
                    this.activeSearchAnchorId,
                    'theme_create_background',
                    this.searchHighlightPulse
                  )
                })
                .shadow(
                  SettingsSearchSupport.isHighlightActive(this.activeSearchAnchorId, 'theme_create_background')
                    ? SettingsSearchSupport.getHighlightOverlayShadow(
                        this.themeState.currentTheme,
                        this.activeSearchAnchorId,
                        'theme_create_background',
                        this.searchHighlightPulse
                      )
                    : {
                        radius: SettingsPanelSurfaceHelper.getRadius(this.themeState.currentTheme) + 4,
                        color: SettingsPanelSurfaceHelper.getShadowColor(this.themeState.currentTheme),
                        offsetX: 0,
                        offsetY: 8
                      }
                )
                .animation({ duration: 260, curve: Curve.EaseOut })
                .margin({ bottom: 16 })
              }

              // 参数调节区域（选择图片后显示）
              if (this.isCreatingCustomTheme
                && this.mediaEditorTab === ThemeMediaTabType.BACKGROUND
                && this.selectedImagePixelMap) {
                Column({ space: 16 }) {
                  Column({ space: 8 }) {
                    Text('背景裁剪与旋转')
                      .fontSize(14)
                      .fontFamily(this.appFontFamily)
                      .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_primary', this.themeState.currentTheme))
                      .width('100%')

                    Text('直接在取景框内拖动和双指缩放，所见即所得')
                      .fontSize(12)
                      .fontFamily(this.appFontFamily)
                      .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_secondary', this.themeState.currentTheme))
                      .width('100%')

                    Row() {
                      Stack() {
                        Image(this.processedImagePixelMap ? this.processedImagePixelMap : this.selectedImagePixelMap)
                          .width(this.getCurrentViewfinderBaseImageWidth())
                          .height(this.getCurrentViewfinderBaseImageHeight())
                          .objectFit(ImageFit.Fill)
                          .rotate({
                            x: 0,
                            y: 0,
                            z: 1,
                            angle: this.normalizeQuarterTurns(this.backgroundRotateQuarterTurns) * 90
                          })
                          .scale({
                            x: this.backgroundViewfinderScale,
                            y: this.backgroundViewfinderScale
                          })
                          .translate({
                            x: this.backgroundViewfinderOffsetX,
                            y: this.backgroundViewfinderOffsetY
                          })

                        Column() {
                          Row()
                            .width('100%')
                            .height(1)
                            .backgroundColor($r('app.color.divider_primary'))
                            .opacity(0.35)
                          Blank()
                          Row()
                            .width('100%')
                            .height(1)
                            .backgroundColor($r('app.color.divider_primary'))
                            .opacity(0.35)
                        }
                        .width('100%')
                        .height('100%')

                        Row() {
                          Column()
                            .width(1)
                            .height('100%')
                            .backgroundColor($r('app.color.divider_primary'))
                            .opacity(0.35)
                          Blank()
                          Column()
                            .width(1)
                            .height('100%')
                            .backgroundColor($r('app.color.divider_primary'))
                            .opacity(0.35)
                        }
                        .width('100%')
                        .height('100%')

                        Column()
                          .width('100%')
                          .height('100%')
                          .border({
                            width: 2,
                            color: $r('app.color.accent_primary')
                          })
                          .borderRadius(12)
                      }
                      .width(this.previewFrameWidthVp)
                      .height(this.previewFrameHeightVp)
                      .clip(true)
                      .backgroundColor(ThemeAwareHelper.getTestManagementThemedColor('comp_background_tertiary', this.themeState.currentTheme))
                      .borderRadius(12)
                      .gesture(
                        GestureGroup(GestureMode.Parallel,
                          PanGesture({ fingers: 1, direction: PanDirection.All, distance: 1 })
                            .onActionStart(() => {
                              this.handleBackgroundViewfinderPanStart();
                            })
                            .onActionUpdate((event: GestureEvent) => {
                              this.handleBackgroundViewfinderPan(event);
                            }),
                          PinchGesture({ fingers: 2, distance: 2 })
                            .onActionStart(() => {
                              this.handleBackgroundViewfinderPinchStart();
                            })
                            .onActionUpdate((event: GestureEvent) => {
                              this.handleBackgroundViewfinderPinch(event);
                            })
                            .onActionEnd(() => {
                              this.handleBackgroundViewfinderPinchEnd();
                            })
                        )
                      )
                    }
                    .width('100%')
                    .justifyContent(FlexAlign.Center)

                    Row({ space: 8 }) {
                      Text(`当前缩放 ${this.backgroundViewfinderScale.toFixed(2)}x`)
                        .fontSize(12)
                        .fontFamily(this.appFontFamily)
                        .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_secondary', this.themeState.currentTheme))
                      Blank()
                      Text(`比例 ${this.previewFrameAspectRatio.toFixed(3)}`)
                        .fontSize(12)
                        .fontFamily(this.appFontFamily)
                        .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_secondary', this.themeState.currentTheme))
                    }
                    .width('100%')

                    Row({ space: 8 }) {
                      Button(`旋转：${this.getQuarterTurnsLabel(this.backgroundRotateQuarterTurns)}`)
                        .layoutWeight(1)
                        .height(36)
                        .fontSize(12)
                        .fontFamily(this.appFontFamily)
                        .backgroundColor(ThemeAwareHelper.getTestManagementThemedColor('comp_background_tertiary', this.themeState.currentTheme))
                        .onClick(() => {
                          this.backgroundRotateQuarterTurns = this.normalizeQuarterTurns(this.backgroundRotateQuarterTurns + 1);
                          this.clampViewfinderToBounds();
                        })
                      Button('重置取景')
                        .layoutWeight(1)
                        .height(36)
                        .fontSize(12)
                        .fontFamily(this.appFontFamily)
                        .backgroundColor(ThemeAwareHelper.getTestManagementThemedColor('comp_background_tertiary', this.themeState.currentTheme))
                        .onClick(() => {
                          this.resetBackgroundViewfinder();
                        })
                    }
                    .width('100%')

                    Button('应用取景裁剪')
                      .width('100%')
                      .height(36)
                      .fontSize(12)
                      .fontFamily(this.appFontFamily)
                      .backgroundColor($r('app.color.color_success'))
                      .onClick(async () => {
                        await this.applyCrop();
                      })

                    if (this.backgroundDraftImagePaths.length > 1) {
                      Column({ space: 8 }) {
                        Text('已导入背景（点击缩略图切换，已应用裁剪会自动保存）')
                          .fontSize(12)
                          .fontFamily(this.appFontFamily)
                          .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_secondary', this.themeState.currentTheme))
                          .width('100%')

                        Flex({
                          wrap: FlexWrap.Wrap,
                          justifyContent: FlexAlign.Start
                        }) {
                          ForEach(this.backgroundDraftImagePaths, (draftOriginalPath: string) => {
                            if (draftOriginalPath !== this.activeBackgroundDraftPath) {
                              Column({ space: 4 }) {
                                Image(this.normalizeThemePreviewPath(this.resolveBackgroundDraftSourcePath(draftOriginalPath)))
                                  .width(72)
                                  .height(Math.round(72 / this.previewFrameAspectRatio))
                                  .objectFit(ImageFit.Cover)
                                  .borderRadius(8)
                                  .border({
                                    width: 1,
                                    color: $r('app.color.divider_primary')
                                  })
                                  .onClick(async () => {
                                    await this.switchBackgroundDraftImage(draftOriginalPath);
                                  })
                                Text('切换')
                                  .fontSize(11)
                                  .fontFamily(this.appFontFamily)
                                  .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_secondary', this.themeState.currentTheme))
                              }
                              .margin({ right: 8, bottom: 8 })
                            }
                          }, (draftOriginalPath: string) => draftOriginalPath)
                        }
                        .width('100%')
                      }
                      .width('100%')
                    }
                  }

                  // 模糊程度
                  Column({ space: 8 }) {
                    Row() {
                      Text('模糊程度')
                        .fontSize(14)
                        .fontFamily(this.appFontFamily)
                        .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_primary', this.themeState.currentTheme))
                      Blank()
                      Text(`${this.blurLevel}%`)
                        .fontSize(14)
                        .fontFamily(this.appFontFamily)
                        .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_secondary', this.themeState.currentTheme))
                    }
                    .width('100%')

                    Slider({
                      value: this.blurLevel,
                      min: 0,
                      max: 100,
                      step: 10
                    })
                      .width('100%')
                      .trackColor($r('app.color.divider_primary'))
                      .selectedColor($r('app.color.accent_primary'))
                      .showSteps(true)
                      .onChange((value: number) => {
                        // 确保值是10的倍数
                        this.blurLevel = Math.round(value / 10) * 10;
                        this.applyImageEffectsDebounced();
                      })
                  }

                  // 亮度调整（所有模式）
                  Column({ space: 8 }) {
                    Row() {
                      Text('亮度')
                        .fontSize(14)
                        .fontFamily(this.appFontFamily)
                        .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_primary', this.themeState.currentTheme))
                      Blank()
                      Text(`${this.brightnessLevel}%`)
                        .fontSize(14)
                        .fontFamily(this.appFontFamily)
                        .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_secondary', this.themeState.currentTheme))
                      Text(this.brightnessLevel < 50 ? ' (变暗)' : this.brightnessLevel > 50 ? ' (变亮)' : ' (原始)')
                        .fontSize(12)
                        .fontFamily(this.appFontFamily)
                        .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_secondary', this.themeState.currentTheme))
                        .opacity(0.7)
                        .margin({ left: 4 })
                    }
                    .width('100%')

                    Slider({
                      value: this.brightnessLevel,
                      min: 0,
                      max: 100,
                      step: 10
                    })
                      .width('100%')
                      .trackColor($r('app.color.divider_primary'))
                      .selectedColor($r('app.color.accent_primary'))
                      .showSteps(true)
                      .onChange((value: number) => {
                        // 确保值是10的倍数
                        this.brightnessLevel = Math.round(value / 10) * 10;
                        this.applyImageEffectsDebounced();
                      })
                  }

                }
                .width(this.responsive_isLandscape ? '48%' : '100%')
                .padding(16)
                .backgroundColor(SettingsPanelSurfaceHelper.getBackground(this.themeState.currentTheme))
                .linearGradient(SettingsPanelSurfaceHelper.getSurfaceGradient(this.themeState.currentTheme))
                .backgroundBlurStyle(
                  SettingsPanelSurfaceHelper.getBlurStyle(this.themeState.currentTheme),
                  SettingsPanelSurfaceHelper.getBlurOptions(this.themeState.currentTheme)
                )
                .backgroundEffect(SettingsPanelSurfaceHelper.getBackgroundEffect(this.themeState.currentTheme))
                .borderRadius(SettingsPanelSurfaceHelper.getRadius(this.themeState.currentTheme))
                .clip(true)
                .border({
                  width: SettingsPanelSurfaceHelper.getBorderWidth(this.themeState.currentTheme),
                  color: SettingsPanelSurfaceHelper.getBorderColor(this.themeState.currentTheme)
                })
                .shadow({
                  radius: SettingsPanelSurfaceHelper.getRadius(this.themeState.currentTheme) + 4,
                  color: SettingsPanelSurfaceHelper.getShadowColor(this.themeState.currentTheme),
                  offsetX: 0,
                  offsetY: 8
                })
                .margin({ bottom: 16 })
              }

              // 开屏图片预览区域（仅创建模式）
              if (this.isCreatingCustomTheme
                && this.mediaEditorTab === ThemeMediaTabType.SPLASH
                && this.selectedSplashImagePixelMap) {
                Column({ space: 16 }) {
                  Column({ space: 8 }) {
                    Text('开屏裁剪与旋转')
                      .fontSize(14)
                      .fontFamily(this.appFontFamily)
                      .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_primary', this.themeState.currentTheme))
                      .width('100%')

                    Text('直接在取景框内拖动和双指缩放，完成后点击“应用取景裁剪”保存当前图片')
                      .fontSize(12)
                      .fontFamily(this.appFontFamily)
                      .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_secondary', this.themeState.currentTheme))
                      .width('100%')

                    Row() {
                      Stack() {
                        Image(this.selectedSplashImagePixelMap)
                          .width(this.getCurrentSplashViewfinderBaseImageWidth())
                          .height(this.getCurrentSplashViewfinderBaseImageHeight())
                          .objectFit(ImageFit.Fill)
                          .rotate({
                            x: 0,
                            y: 0,
                            z: 1,
                            angle: this.normalizeQuarterTurns(this.splashRotateQuarterTurns) * 90
                          })
                          .scale({
                            x: this.splashViewfinderScale,
                            y: this.splashViewfinderScale
                          })
                          .translate({
                            x: this.splashViewfinderOffsetX,
                            y: this.splashViewfinderOffsetY
                          })

                        Column() {
                          Row()
                            .width('100%')
                            .height(1)
                            .backgroundColor($r('app.color.divider_primary'))
                            .opacity(0.35)
                          Blank()
                          Row()
                            .width('100%')
                            .height(1)
                            .backgroundColor($r('app.color.divider_primary'))
                            .opacity(0.35)
                        }
                        .width('100%')
                        .height('100%')

                        Row() {
                          Column()
                            .width(1)
                            .height('100%')
                            .backgroundColor($r('app.color.divider_primary'))
                            .opacity(0.35)
                          Blank()
                          Column()
                            .width(1)
                            .height('100%')
                            .backgroundColor($r('app.color.divider_primary'))
                            .opacity(0.35)
                        }
                        .width('100%')
                        .height('100%')

                        Column()
                          .width('100%')
                          .height('100%')
                          .border({
                            width: 2,
                            color: $r('app.color.accent_primary')
                          })
                          .borderRadius(12)
                      }
                      .width(this.previewFrameWidthVp)
                      .height(this.previewFrameHeightVp)
                      .clip(true)
                      .backgroundColor(ThemeAwareHelper.getTestManagementThemedColor('comp_background_tertiary', this.themeState.currentTheme))
                      .borderRadius(12)
                      .gesture(
                        GestureGroup(GestureMode.Parallel,
                          PanGesture({ fingers: 1, direction: PanDirection.All, distance: 1 })
                            .onActionStart(() => {
                              this.handleSplashViewfinderPanStart();
                            })
                            .onActionUpdate((event: GestureEvent) => {
                              this.handleSplashViewfinderPan(event);
                            }),
                          PinchGesture({ fingers: 2, distance: 2 })
                            .onActionStart(() => {
                              this.handleSplashViewfinderPinchStart();
                            })
                            .onActionUpdate((event: GestureEvent) => {
                              this.handleSplashViewfinderPinch(event);
                            })
                            .onActionEnd(() => {
                              this.handleSplashViewfinderPinchEnd();
                            })
                        )
                      )
                    }
                    .width('100%')
                    .justifyContent(FlexAlign.Center)

                    Row({ space: 8 }) {
                      Text(`当前缩放 ${this.splashViewfinderScale.toFixed(2)}x`)
                        .fontSize(12)
                        .fontFamily(this.appFontFamily)
                        .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_secondary', this.themeState.currentTheme))
                      Blank()
                      Text(`比例 ${this.previewFrameAspectRatio.toFixed(3)}`)
                        .fontSize(12)
                        .fontFamily(this.appFontFamily)
                        .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_secondary', this.themeState.currentTheme))
                    }
                    .width('100%')

                    Row({ space: 8 }) {
                      Button(`旋转：${this.getQuarterTurnsLabel(this.splashRotateQuarterTurns)}`)
                        .layoutWeight(1)
                        .height(36)
                        .fontSize(12)
                        .fontFamily(this.appFontFamily)
                        .backgroundColor(ThemeAwareHelper.getTestManagementThemedColor('comp_background_tertiary', this.themeState.currentTheme))
                        .onClick(() => {
                          this.splashRotateQuarterTurns = this.normalizeQuarterTurns(this.splashRotateQuarterTurns + 1);
                          this.clampSplashViewfinderToBounds();
                        })
                      Button('重置取景')
                        .layoutWeight(1)
                        .height(36)
                        .fontSize(12)
                        .fontFamily(this.appFontFamily)
                        .backgroundColor(ThemeAwareHelper.getTestManagementThemedColor('comp_background_tertiary', this.themeState.currentTheme))
                        .onClick(() => {
                          this.resetSplashViewfinder();
                        })
                    }
                    .width('100%')

                    Row({ space: 8 }) {
                      Button('应用取景裁剪')
                        .layoutWeight(1)
                        .height(36)
                        .fontSize(12)
                        .fontFamily(this.appFontFamily)
                        .backgroundColor($r('app.color.color_success'))
                        .onClick(async () => {
                          await this.applySplashCrop();
                        })
                      Button('清除当前')
                        .layoutWeight(1)
                        .height(36)
                        .fontSize(12)
                        .fontFamily(this.appFontFamily)
                        .backgroundColor($r('app.color.color_error'))
                        .onClick(() => {
                          this.clearCurrentSplashSelection();
                        })
                    }
                    .width('100%')

                    if (this.splashSourceImagePaths.length > 1) {
                      Column({ space: 8 }) {
                        Text('已导入开屏（点击缩略图切换，已应用裁剪会自动保存）')
                          .fontSize(12)
                          .fontFamily(this.appFontFamily)
                          .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_secondary', this.themeState.currentTheme))
                          .width('100%')

                        Flex({
                          wrap: FlexWrap.Wrap,
                          justifyContent: FlexAlign.Start
                        }) {
                          ForEach(this.splashSourceImagePaths, (sourcePath: string) => {
                            Column({ space: 4 }) {
                              Image(this.normalizeThemePreviewPath(this.resolveSplashSourcePath(sourcePath)))
                                .width(72)
                                .height(Math.round(72 / this.previewFrameAspectRatio))
                                .objectFit(ImageFit.Cover)
                                .borderRadius(8)
                                .border({
                                  width: sourcePath === this.activeSplashSourcePath ? 2 : 1,
                                  color: sourcePath === this.activeSplashSourcePath
                                    ? $r('app.color.accent_primary')
                                    : $r('app.color.divider_primary')
                                })
                                .onClick(async () => {
                                  await this.switchSplashSourceImage(sourcePath);
                                })
                              Text(sourcePath === this.activeSplashSourcePath ? '当前' : '切换')
                                .fontSize(11)
                                .fontFamily(this.appFontFamily)
                                .fontColor(
                                  sourcePath === this.activeSplashSourcePath
                                    ? $r('app.color.accent_primary')
                                    : ThemeAwareHelper.getTestManagementThemedColor('text_secondary', this.themeState.currentTheme)
                                )
                            }
                            .margin({ right: 8, bottom: 8 })
                          }, (sourcePath: string) => sourcePath)
                        }
                        .width('100%')
                      }
                      .width('100%')
                    }
                  }
                  .width('100%')
                }
                .width(this.responsive_isLandscape ? '48%' : '100%')
                .padding(16)
                .backgroundColor(SettingsPanelSurfaceHelper.getBackground(this.themeState.currentTheme))
                .linearGradient(SettingsPanelSurfaceHelper.getSurfaceGradient(this.themeState.currentTheme))
                .backgroundBlurStyle(
                  SettingsPanelSurfaceHelper.getBlurStyle(this.themeState.currentTheme),
                  SettingsPanelSurfaceHelper.getBlurOptions(this.themeState.currentTheme)
                )
                .backgroundEffect(SettingsPanelSurfaceHelper.getBackgroundEffect(this.themeState.currentTheme))
                .borderRadius(SettingsPanelSurfaceHelper.getRadius(this.themeState.currentTheme))
                .clip(true)
                .border({
                  width: SettingsPanelSurfaceHelper.getBorderWidth(this.themeState.currentTheme),
                  color: SettingsPanelSurfaceHelper.getBorderColor(this.themeState.currentTheme)
                })
                .shadow({
                  radius: SettingsPanelSurfaceHelper.getRadius(this.themeState.currentTheme) + 4,
                  color: SettingsPanelSurfaceHelper.getShadowColor(this.themeState.currentTheme),
                  offsetX: 0,
                  offsetY: 8
                })
                .margin({ bottom: 16 })
              }

              // 主题色选择（仅创建模式）
              if (this.isCreatingCustomTheme) {
                Column({ space: 12 }) {
                  Text('选择主题色')
                    .fontSize(16)
                    .fontFamily(this.appFontFamily)
                    .fontWeight(FontWeight.Bold)
                    .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_primary', this.themeState.currentTheme))
                    .width('100%')

                  // 提取的主色调显示
                  if (this.extractedColor && this.extractedColor.length > 0) {
                    Row({ space: 12 }) {
                      Column()
                        .width(48)
                        .height(48)
                        .backgroundColor(this.extractedColor)
                        .borderRadius(8)
                        .border({ width: this.selectedPrimaryColor === this.extractedColor ? 3 : 0, color: $r('app.color.accent_primary') })
                        .onClick(() => {
                          this.selectedPrimaryColor = this.extractedColor;
                          this.syncCustomColorEditor(this.selectedPrimaryColor);
                        })

                      Column({ space: 4 }) {
                        Text('从图片提取')
                          .fontSize(12)
                          .fontFamily(this.appFontFamily)
                          .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_secondary', this.themeState.currentTheme))
                        Text(this.extractedColor)
                          .fontSize(14)
                          .fontFamily(this.appFontFamily)
                          .fontWeight(FontWeight.Medium)
                          .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_primary', this.themeState.currentTheme))
                        Text(this.extractedColorRGB)
                          .fontSize(11)
                          .fontFamily(this.appFontFamily)
                          .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_secondary', this.themeState.currentTheme))
                      }
                      .alignItems(HorizontalAlign.Start)
                    }
                    .width('100%')
                    .padding(8)
                    .backgroundColor(ThemeAwareHelper.getTestManagementThemedColor('comp_background_tertiary', this.themeState.currentTheme))
                    .borderRadius(8)
                  }

                  Text('可选主题色')
                    .fontSize(14)
                    .fontFamily(this.appFontFamily)
                    .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_secondary', this.themeState.currentTheme))
                    .width('100%')

                  Row({ space: 12 }) {
                    ForEach(this.availablePrimaryColors, (colorStr: string) => {
                      Stack() {
                        Column()
                          .width(40)
                          .height(40)
                          .backgroundColor(colorStr)
                          .borderRadius(8)
                          .border({ width: this.selectedPrimaryColor === colorStr ? 3 : 1, color: this.selectedPrimaryColor === colorStr ? $r('app.color.accent_primary') : $r('app.color.divider_primary') })

                        if (this.selectedPrimaryColor === colorStr) {
                          Image($r('app.media.ic_check'))
                            .width(16)
                            .height(16)
                            .fillColor(Color.White)
                        }
                      }
                      .width(40)
                      .height(40)
                      .onClick(() => {
                        this.selectedPrimaryColor = colorStr;
                        this.syncCustomColorEditor(this.selectedPrimaryColor);
                      })
                    }, (colorStr: string) => colorStr)
                  }
                  .width('100%')

                  Column({ space: 8 }) {
                    Text('自定义色盘')
                      .fontSize(14)
                      .fontFamily(this.appFontFamily)
                      .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_secondary', this.themeState.currentTheme))
                      .width('100%')

                    Row({ space: 8 }) {
                      TextInput({ text: this.customPrimaryColorHex, placeholder: '#RRGGBB' })
                        .layoutWeight(1)
                        .height(38)
                        .fontSize(14)
                        .fontFamily(this.appFontFamily)
                        .backgroundColor(ThemeAwareHelper.getTestManagementThemedColor('comp_background_tertiary', this.themeState.currentTheme))
                        .borderRadius(8)
                        .onChange((value: string) => {
                          this.customPrimaryColorHex = value;
                        })
                      Button('解析')
                        .height(38)
                        .fontSize(12)
                        .fontFamily(this.appFontFamily)
                        .backgroundColor($r('app.color.accent_primary'))
                        .onClick(() => {
                          const normalized: string = this.normalizeHexColor(this.customPrimaryColorHex);
                          this.syncCustomColorEditor(normalized);
                        })
                    }
                    .width('100%')

                    Row({ space: 8 }) {
                      Text('R')
                        .width(16)
                        .fontSize(12)
                        .fontFamily(this.appFontFamily)
                        .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_secondary', this.themeState.currentTheme))
                      Slider({ value: this.customPrimaryColorR, min: 0, max: 255, step: 1 })
                        .layoutWeight(1)
                        .trackColor($r('app.color.divider_primary'))
                        .selectedColor($r('app.color.accent_primary'))
                        .onChange((value: number) => {
                          this.customPrimaryColorR = Math.round(value);
                          this.updateCustomColorFromChannels();
                        })
                      Text(this.customPrimaryColorR.toString())
                        .width(36)
                        .textAlign(TextAlign.End)
                        .fontSize(12)
                        .fontFamily(this.appFontFamily)
                        .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_secondary', this.themeState.currentTheme))
                    }
                    .width('100%')

                    Row({ space: 8 }) {
                      Text('G')
                        .width(16)
                        .fontSize(12)
                        .fontFamily(this.appFontFamily)
                        .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_secondary', this.themeState.currentTheme))
                      Slider({ value: this.customPrimaryColorG, min: 0, max: 255, step: 1 })
                        .layoutWeight(1)
                        .trackColor($r('app.color.divider_primary'))
                        .selectedColor($r('app.color.accent_primary'))
                        .onChange((value: number) => {
                          this.customPrimaryColorG = Math.round(value);
                          this.updateCustomColorFromChannels();
                        })
                      Text(this.customPrimaryColorG.toString())
                        .width(36)
                        .textAlign(TextAlign.End)
                        .fontSize(12)
                        .fontFamily(this.appFontFamily)
                        .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_secondary', this.themeState.currentTheme))
                    }
                    .width('100%')

                    Row({ space: 8 }) {
                      Text('B')
                        .width(16)
                        .fontSize(12)
                        .fontFamily(this.appFontFamily)
                        .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_secondary', this.themeState.currentTheme))
                      Slider({ value: this.customPrimaryColorB, min: 0, max: 255, step: 1 })
                        .layoutWeight(1)
                        .trackColor($r('app.color.divider_primary'))
                        .selectedColor($r('app.color.accent_primary'))
                        .onChange((value: number) => {
                          this.customPrimaryColorB = Math.round(value);
                          this.updateCustomColorFromChannels();
                        })
                      Text(this.customPrimaryColorB.toString())
                        .width(36)
                        .textAlign(TextAlign.End)
                        .fontSize(12)
                        .fontFamily(this.appFontFamily)
                        .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_secondary', this.themeState.currentTheme))
                    }
                    .width('100%')

                    Row({ space: 8 }) {
                      Column()
                        .width(34)
                        .height(34)
                        .backgroundColor(this.customPrimaryColorHex)
                        .borderRadius(8)
                        .border({ width: 1, color: $r('app.color.divider_primary') })
                      Text(this.customPrimaryColorHex)
                        .layoutWeight(1)
                        .fontSize(13)
                        .fontFamily(this.appFontFamily)
                        .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_primary', this.themeState.currentTheme))
                      Button('加入色盘并选中')
                        .height(34)
                        .fontSize(12)
                        .fontFamily(this.appFontFamily)
                        .backgroundColor($r('app.color.color_success'))
                        .onClick(() => {
                          this.applyCustomPrimaryColorFromEditor();
                        })
                    }
                    .width('100%')
                  }
                  .width('100%')
                  .padding(10)
                  .backgroundColor(ThemeAwareHelper.getTestManagementThemedColor('comp_background_tertiary', this.themeState.currentTheme))
                  .borderRadius(8)

                  Column({ space: 16 }) {
                    Column({ space: 8 }) {
                      Text('主题名称（可选）')
                        .fontSize(14)
                        .fontFamily(this.appFontFamily)
                        .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_primary', this.themeState.currentTheme))
                      TextInput({ text: this.newThemeName })
                        .width('100%')
                        .height(40)
                        .backgroundColor(ThemeAwareHelper.getTestManagementThemedColor('comp_background_tertiary', this.themeState.currentTheme))
                        .borderRadius(10)
                        .onChange((value: string) => { this.newThemeName = value; })
                    }

                    Button(this.isEditingCustomTheme ? '保存修改并应用主题' : '保存并应用主题')
                      .width('100%')
                      .height(48)
                      .fontSize(16)
                      .fontFamily(this.appFontFamily)
                      .backgroundColor($r('app.color.color_success'))
                      .borderRadius(10)
                      .enabled(this.canSaveCurrentTheme())
                      .onClick(() => this.saveAndApplyTheme())
                  }
                  .id('theme_create_save')
                  .width('100%')
                  .padding({ top: 16 })
                  .margin({ top: 4 })
                  .border({
                    width: SettingsSearchSupport.isHighlightActive(this.activeSearchAnchorId, 'theme_create_save') ? 2 : 0,
                    color: SettingsSearchSupport.getHighlightOverlayBorder(
                      this.themeState.currentTheme,
                      this.activeSearchAnchorId,
                      'theme_create_save'
                    )
                  })
                  .borderRadius(10)
                  .backgroundColor(SettingsSearchSupport.getHighlightOverlayBackground(
                    this.themeState.currentTheme,
                    this.activeSearchAnchorId,
                    'theme_create_save'
                  ))
                  .scale({
                    x: SettingsSearchSupport.getHighlightScale(this.activeSearchAnchorId, 'theme_create_save', this.searchHighlightPulse),
                    y: SettingsSearchSupport.getHighlightScale(this.activeSearchAnchorId, 'theme_create_save', this.searchHighlightPulse)
                  })
                  .shadow(SettingsSearchSupport.getHighlightOverlayShadow(
                    this.themeState.currentTheme,
                    this.activeSearchAnchorId,
                    'theme_create_save',
                    this.searchHighlightPulse
                  ))
                  .animation({ duration: 260, curve: Curve.EaseOut })
                }
                .id('theme_create_colors')
                .width(this.responsive_isLandscape ? '48%' : '100%')
                .padding(16)
                .backgroundColor(SettingsPanelSurfaceHelper.getBackground(this.themeState.currentTheme))
                .linearGradient(SettingsPanelSurfaceHelper.getSurfaceGradient(this.themeState.currentTheme))
                .backgroundBlurStyle(
                  SettingsPanelSurfaceHelper.getBlurStyle(this.themeState.currentTheme),
                  SettingsPanelSurfaceHelper.getBlurOptions(this.themeState.currentTheme)
                )
                .backgroundEffect(SettingsPanelSurfaceHelper.getBackgroundEffect(this.themeState.currentTheme))
                .borderRadius(SettingsPanelSurfaceHelper.getRadius(this.themeState.currentTheme))
                .clip(true)
                .border({
                  width: SettingsSearchSupport.isHighlightActive(this.activeSearchAnchorId, 'theme_create_colors')
                    ? 2
                    : SettingsPanelSurfaceHelper.getBorderWidth(this.themeState.currentTheme),
                  color: SettingsSearchSupport.isHighlightActive(this.activeSearchAnchorId, 'theme_create_colors')
                    ? SettingsSearchSupport.getHighlightOverlayBorder(
                      this.themeState.currentTheme,
                      this.activeSearchAnchorId,
                      'theme_create_colors'
                    )
                    : SettingsPanelSurfaceHelper.getBorderColor(this.themeState.currentTheme)
                })
                .scale({
                  x: SettingsSearchSupport.getHighlightScale(this.activeSearchAnchorId, 'theme_create_colors', this.searchHighlightPulse),
                  y: SettingsSearchSupport.getHighlightScale(this.activeSearchAnchorId, 'theme_create_colors', this.searchHighlightPulse)
                })
                .shadow(
                  SettingsSearchSupport.isHighlightActive(this.activeSearchAnchorId, 'theme_create_colors')
                    ? SettingsSearchSupport.getHighlightOverlayShadow(
                        this.themeState.currentTheme,
                        this.activeSearchAnchorId,
                        'theme_create_colors',
                        this.searchHighlightPulse
                      )
                    : {
                        radius: SettingsPanelSurfaceHelper.getRadius(this.themeState.currentTheme) + 4,
                        color: SettingsPanelSurfaceHelper.getShadowColor(this.themeState.currentTheme),
                        offsetX: 0,
                        offsetY: 8
                      }
                )
                .animation({ duration: 260, curve: Curve.EaseOut })
                .margin({ bottom: 16 })
              }

              // 主题名称输入（仅创建模式）
              if (this.isCreatingCustomTheme) {
                Column({ space: 16 }) {
                  Column({ space: 8 }) {
                    Text('主题名称（可选）')
                      .fontSize(14)
                      .fontFamily(this.appFontFamily)
                      .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_primary', this.themeState.currentTheme))
                    TextInput({ text: this.newThemeName })
                      .width('100%')
                      .height(40)
                      .backgroundColor(ThemeAwareHelper.getTestManagementThemedColor('comp_background_tertiary', this.themeState.currentTheme))
                      .borderRadius(10)
                      .onChange((value: string) => { this.newThemeName = value; })
                  }

                  Button(this.isEditingCustomTheme ? '保存修改并应用主题' : '保存并应用主题')
                    .width('100%')
                    .height(48)
                    .fontSize(16)
                    .fontFamily(this.appFontFamily)
                    .backgroundColor($r('app.color.color_success'))
                    .borderRadius(12)
                    .enabled(this.canSaveCurrentTheme())
                    .onClick(() => this.saveAndApplyTheme())
                }
                .id('theme_create_save_legacy')
                .width(0)
                .height(0)
                .padding(0)
                .clip(true)
                .opacity(0)
                .backgroundColor('rgba(0, 0, 0, 0)')
                .borderRadius(0)
                .border({
                  width: SettingsSearchSupport.isHighlightActive(this.activeSearchAnchorId, 'theme_create_save_legacy') ? 2 : 0,
                  color: SettingsSearchSupport.isHighlightActive(this.activeSearchAnchorId, 'theme_create_save_legacy')
                    ? SettingsSearchSupport.getHighlightOverlayBorder(
                      this.themeState.currentTheme,
                      this.activeSearchAnchorId,
                      'theme_create_save_legacy'
                    )
                    : 'rgba(0, 0, 0, 0)'
                })
                .scale({
                  x: SettingsSearchSupport.getHighlightScale(this.activeSearchAnchorId, 'theme_create_save_legacy', this.searchHighlightPulse),
                  y: SettingsSearchSupport.getHighlightScale(this.activeSearchAnchorId, 'theme_create_save_legacy', this.searchHighlightPulse)
                })
                .shadow(SettingsSearchSupport.getHighlightOverlayShadow(
                  this.themeState.currentTheme,
                  this.activeSearchAnchorId,
                  'theme_create_save_legacy',
                  this.searchHighlightPulse
                ))
                .animation({ duration: 260, curve: Curve.EaseOut })
                .margin(0)
              }

              // 处理进度提示
              if (this.isProcessing) {
                Column({ space: 12 }) {
                  LoadingProgress()
                    .width(48)
                    .height(48)
                    .color($r('app.color.accent_primary'))

                  Text(this.processingMessage)
                    .fontSize(14)
                    .fontFamily(this.appFontFamily)
                    .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_secondary', this.themeState.currentTheme))

                  Progress({
                    value: this.processingProgress,
                    total: 100,
                    type: ProgressType.Linear
                  })
                    .width('100%')
                    .color($r('app.color.accent_primary'))
                }
                .width(this.responsive_isLandscape ? '48%' : '100%')
                .padding(24)
                .backgroundColor(SettingsPanelSurfaceHelper.getBackground(this.themeState.currentTheme))
                .linearGradient(SettingsPanelSurfaceHelper.getSurfaceGradient(this.themeState.currentTheme))
                .backgroundBlurStyle(
                  SettingsPanelSurfaceHelper.getBlurStyle(this.themeState.currentTheme),
                  SettingsPanelSurfaceHelper.getBlurOptions(this.themeState.currentTheme)
                )
                .backgroundEffect(SettingsPanelSurfaceHelper.getBackgroundEffect(this.themeState.currentTheme))
                .borderRadius(SettingsPanelSurfaceHelper.getRadius(this.themeState.currentTheme))
                .clip(true)
                .border({
                  width: SettingsPanelSurfaceHelper.getBorderWidth(this.themeState.currentTheme),
                  color: SettingsPanelSurfaceHelper.getBorderColor(this.themeState.currentTheme)
                })
                .shadow({
                  radius: SettingsPanelSurfaceHelper.getRadius(this.themeState.currentTheme) + 4,
                  color: SettingsPanelSurfaceHelper.getShadowColor(this.themeState.currentTheme),
                  offsetX: 0,
                  offsetY: 8
                })
                .justifyContent(FlexAlign.Center)
                .alignItems(HorizontalAlign.Center)
                .margin({ bottom: 16 })
              }

              if (!this.isCreatingCustomTheme) {
                this.buildHdsTabEffectsPanel()
              }
            }
            .enabled(this.settingsTapEnabled)
            .width('100%')
            .constraintSize({ maxWidth: this.responsive_isLandscape ? 100000 : this.responsive_maxContentWidth }) // 横屏放开最大宽度限制，避免右侧留白
            .padding({
              left: this.responsive_contentPadding,
              right: this.responsive_contentPadding,
              top: this.responsive_contentPadding,
              bottom: this.responsive_contentPadding + this.navigationBarHeight
            })
          }
          .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.TOP, SafeAreaEdge.BOTTOM])
          .width('100%')
          .height('100%')
          .id('guide_theme_settings_scroll')
          .align(Alignment.TopStart) // 响应式：大屏居中对齐
          .layoutWeight(1)
          .scrollBar(BarState.Auto)
          .onScroll((_xOffset: number, _yOffset: number) => {
            this.markSettingsScrolling();
          })
          .edgeEffect(EdgeEffect.Spring)
        }
        .width('100%')
        .height('100%')
        .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.TOP, SafeAreaEdge.BOTTOM])
        SettingsImmersiveTitleBar({
          themeState: this.themeState,
          title: '主题设置',
          appFontFamily: this.appFontFamily,
          contentPadding: this.responsive_contentPadding,
          maxContentWidth: this.responsive_maxContentWidth,
          pathStack: this.pathStack,
          actions: this.getTitleBarActions()
        })
        }
        .width('100%')
        .height('100%')
        .id('guide_theme_settings_root')
      }
      .hideTitleBar(true)
      .ignoreLayoutSafeArea([LayoutSafeAreaType.SYSTEM], [LayoutSafeAreaEdge.TOP, LayoutSafeAreaEdge.BOTTOM])
    .onReady((context: NavDestinationContext) => {
      this.pathStack = context.pathStack;
      this.applyPendingSearchTarget();
    })
    .backgroundColor(Color.Transparent)
  }
}
