// 文件路径: entry/src/main/ets/pages/settings/FontSettingsSubPage.ets
/**
 * 字体设置二级页面
 * 管理APP界面字体、小说字体、电子书字体
 */

import { HdsNavDestination, HdsNavDestinationAttribute, ScrollEffectType } from '@kit.UIDesignKit';
import { LengthMetrics, promptAction } from '@kit.ArkUI';
import { ThemeAwareState, ThemeAwareHelper } from 'manxia_theme/src/main/ets/Framework/Components/ThemeAware';
import { FontAwareHelper, FontAwareState } from 'manxia_theme/src/main/ets/Framework/Components/FontAware';
import { ThemeManager, ThemeType } from 'manxia_theme/src/main/ets/Framework/Managers/ThemeManager';
import { FontManager, getFontManager, FontType, FontScene, SystemFont, CustomFont, FontSettings } from 'manxia_theme/src/main/ets/Framework/Managers/FontManager';
import { logger } from 'manxia_core/src/main/ets/Utils/Logger';
import { picker } from '@kit.CoreFileKit';
import { common } from '@kit.AbilityKit';
import { DeviceAdaptationManager, DeviceInfo, DeviceChangeListener, Breakpoint } from 'manxia_theme/src/main/ets/Framework/Managers/DeviceAdaptationManager';
import { ResponsiveLayoutHelper } from 'manxia_theme/src/main/ets/Framework/Utils/ResponsiveLayout';
import { SettingsSearchSupport } from 'manxia_features_ui/src/main/ets/pages/settings/SettingsSearchSupport';
import { SettingsPanelSurfaceHelper } from 'manxia_features_ui/src/main/ets/pages/settings/SettingsPanelSurfaceHelper';
import { GlobalBackgroundLayerMode } from 'manxia_theme/src/main/ets/Framework/Components/GlobalBackgroundLayer';
import { SharedPageBackgroundLayer } from '../../Framework/Components/SharedPageBackgroundLayer';
import { SettingsImmersiveTitleBar } from './SettingsImmersiveTitleBar';
import { SettingsPageTitleBarManager } from 'manxia_features_ui/src/main/ets/pages/settings/SettingsPageTitleBarManager';

const TAG = 'FontSettingsSubPage';
const TITLE_BAR_HEIGHT_MINI: number = 56;

@Component
export struct FontSettingsSubPage {
  @State pathStack: NavPathStack = new NavPathStack();
  @StorageProp('statusBarHeight') statusBarHeight: number = 0;
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
  private fontManager: FontManager = getFontManager();
  private componentId: string = 'FontSettingsSubPage';
  
  // 响应式布局相关状态
  private deviceManager: DeviceAdaptationManager = DeviceAdaptationManager.getInstance();
  private deviceChangeListener: DeviceChangeListener | null = null;
  @State responsive_contentPadding: number = 16;
  @State responsive_maxContentWidth: number = 1200;
  @State responsive_isLandscape: boolean = false;
  
  // 字体设置状态
  @State settings: FontSettings | null = null;
  @State systemFonts: SystemFont[] = [];
  @State customFonts: CustomFont[] = [];
  
  // 展开状态
  @State expandedSection: string = '';
  
  // 预览文本
  private previewText: string = '漫侠 - 您的漫画阅读伴侣\nThe quick brown fox jumps over the lazy dog.\n1234567890';

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
  aboutToAppear(): void {
    ThemeAwareHelper.initializeThemeAware(this.componentId, this.themeState, (theme: ThemeType) => {});
    FontAwareHelper.initializeFontAware(this.componentId, this.fontState, (newState: FontAwareState) => {
      this.fontState = newState;
    });
    this.initializeResponsiveLayout();
    this.loadFontData();
  }

  private initializeResponsiveLayout(): void {
    try {
      this.updateResponsiveParams();
      this.deviceChangeListener = (deviceInfo: DeviceInfo) => {
        logger.info(TAG, `设备状态变化: 断点=${deviceInfo.breakpoint}, 方向=${deviceInfo.orientation}`);
        this.updateResponsiveParams();
      };
      this.deviceManager.addListener(this.deviceChangeListener);
    } catch (e) {
      logger.error(TAG, '响应式布局初始化失败', String(e));
    }
  }

  private updateResponsiveParams(): void {
    const layoutParams = ResponsiveLayoutHelper.getLayoutParams();
    const deviceInfo = this.deviceManager.getDeviceInfo();
    this.responsive_contentPadding = layoutParams.contentPadding;
    this.responsive_isLandscape = deviceInfo.isLandscape;
    // 根据断点设置最大内容宽度
    switch (deviceInfo.breakpoint) {
      case Breakpoint.XS:
        this.responsive_maxContentWidth = 600;
        break;
      case Breakpoint.SM:
        this.responsive_maxContentWidth = 840;
        break;
      case Breakpoint.MD:
        this.responsive_maxContentWidth = 1024;
        break;
      case Breakpoint.LG:
        this.responsive_maxContentWidth = 1200;
        break;
    }
  }

  private loadFontData(): void {
    this.settings = this.fontManager.getSettings();
    this.systemFonts = this.fontManager.getSystemFonts();
    this.customFonts = this.fontManager.getCustomFonts();
  }

  aboutToDisappear(): void {
    this.cleanupSettingsTapGuard();
    SettingsSearchSupport.clearHighlight(this);
    ThemeAwareHelper.cleanupThemeAware(this.componentId);
    FontAwareHelper.cleanupFontAware(this.componentId);
    if (this.deviceChangeListener) {
      this.deviceManager.removeListener(this.deviceChangeListener);
      this.deviceChangeListener = null;
    }
  }

  private applyPendingSearchTarget(): void {
    const target = SettingsSearchSupport.consumePendingTarget('FontSettingsSubPage');
    if (!target) {
      return;
    }
    switch (target.anchorId) {
      case 'font_app':
        this.expandedSection = 'app';
        break;
      case 'font_novel':
        this.expandedSection = 'novel';
        break;
      case 'font_ebook':
        this.expandedSection = 'ebook';
        break;
      default:
        break;
    }
    SettingsSearchSupport.activateHighlight(this, target.anchorId);
    const offset = Math.max(0, target.scrollOffset);
    logger.info(TAG, `应用设置搜索定位: id=${target.id}, offset=${offset}`);
    setTimeout(() => {
      try {
        this.scroller.scrollTo({ xOffset: 0, yOffset: offset, animation: { duration: 360 } });
      } catch (error) {
        logger.warn(TAG, `滚动到设置搜索目标失败: ${String(error)}`);
      }
    }, 140);
  }

  private async importCustomFont(): Promise<void> {
    try {
      const context = (this.getUIContext().getHostContext() as common.UIAbilityContext) as common.UIAbilityContext;
      const documentPicker = new picker.DocumentViewPicker(context);
      const options = new picker.DocumentSelectOptions();
      options.maxSelectNumber = 1;
      
      const result = await documentPicker.select(options);
      if (result && result.length > 0) {
        const filePath = result[0];
        
        // 传递空字符串，让FontManager自动解析字体文件内部的真实名称
        // 这样可以正确显示中文、日文等多语言字体名称
        const customFont = await this.fontManager.addCustomFont('', filePath, this.getUIContext());
        this.customFonts = this.fontManager.getCustomFonts();
        this.getUIContext().getPromptAction().showToast({ message: `字体 "${customFont.displayName}" 导入成功` });
      }
    } catch (error) {
      logger.error(TAG, `导入字体失败: ${String(error)}`);
      this.getUIContext().getPromptAction().showToast({ message: `导入失败: ${String(error)}` });
    }
  }

  private async deleteCustomFont(fontId: string): Promise<void> {
    try {
      await this.fontManager.removeCustomFont(fontId);
      this.customFonts = this.fontManager.getCustomFonts();
      this.getUIContext().getPromptAction().showToast({ message: '字体已删除' });
    } catch (error) {
      this.getUIContext().getPromptAction().showToast({ message: String(error) });
    }
  }

  private async setFont(scene: FontScene, fontType: FontType, fontId: string): Promise<void> {
    try {
      switch (scene) {
        case FontScene.APP_UI:
          await this.fontManager.setAppFont(fontType, fontId, this.getUIContext());
          break;
        case FontScene.NOVEL:
          await this.fontManager.setNovelFont(fontType, fontId, this.getUIContext());
          break;
        case FontScene.EBOOK:
          await this.fontManager.setEbookFont(fontType, fontId, this.getUIContext());
          break;
      }
      this.settings = this.fontManager.getSettings();
      this.getUIContext().getPromptAction().showToast({ message: '字体已更新' });
    } catch (error) {
      this.getUIContext().getPromptAction().showToast({ message: `设置失败: ${String(error)}` });
    }
  }

  @Builder
  buildSectionHeader(title: string, subtitle: string, sectionId: string) {
    Row() {
      Column({ space: 4 }) {
        Text(title)
          .fontSize(16)
          .fontWeight(FontWeight.Medium)
          .fontFamily(this.appFontFamily)
          .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_primary', this.themeState.currentTheme))
        Text(subtitle)
          .fontSize(13)
          .fontFamily(this.appFontFamily)
          .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_secondary', this.themeState.currentTheme))
      }
      .alignItems(HorizontalAlign.Start)
      .layoutWeight(1)

      SymbolGlyph($r('sys.symbol.chevron_down'))
        .fontSize(16)
        .fontColor([ThemeAwareHelper.getTestManagementThemedColor('text_muted', this.themeState.currentTheme)])
        .rotate({ angle: this.expandedSection === sectionId ? 180 : 0 })
        .animation({ duration: 250, curve: Curve.EaseInOut })
    }
    .width('100%')
    .padding(16)
    .backgroundColor(SettingsPanelSurfaceHelper.getBackground(this.themeState.currentTheme))
    .linearGradient(SettingsPanelSurfaceHelper.getSurfaceGradient(this.themeState.currentTheme))
    .backgroundBlurStyle(SettingsPanelSurfaceHelper.getBlurStyle(this.themeState.currentTheme), SettingsPanelSurfaceHelper.getBlurOptions(this.themeState.currentTheme))
    .backgroundEffect(SettingsPanelSurfaceHelper.getBackgroundEffect(this.themeState.currentTheme))
    .borderRadius(this.expandedSection === sectionId ? { topLeft: 12, topRight: 12 } : 12)
    .clip(true)
    .border({ width: SettingsPanelSurfaceHelper.getBorderWidth(this.themeState.currentTheme), color: SettingsPanelSurfaceHelper.getBorderColor(this.themeState.currentTheme) })
    .shadow({
      radius: SettingsPanelSurfaceHelper.getRadius(this.themeState.currentTheme) + 4,
      color: SettingsPanelSurfaceHelper.getShadowColor(this.themeState.currentTheme),
      offsetX: 0,
      offsetY: 8
    })
    .animation({ duration: 250, curve: Curve.EaseInOut })
    .onClick(() => {
      this.getUIContext().animateTo({
        duration: 250,
        curve: Curve.EaseInOut
      }, () => {
        this.expandedSection = this.expandedSection === sectionId ? '' : sectionId;
      });
    })
  }

  @Builder
  buildFontSelector(scene: FontScene, currentFontType: FontType, currentSystemId: string, currentCustomId: string) {
    Column({ space: 12 }) {
      // 系统字体
      Text('系统字体')
        .fontSize(14)
        .fontWeight(FontWeight.Medium)
        .fontFamily(this.appFontFamily)
        .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_secondary', this.themeState.currentTheme))
        .width('100%')
        .padding({ left: 4 })

      ForEach(this.systemFonts, (font: SystemFont) => {
        Row({ space: 12 }) {
          Radio({ value: `system_${font.id}`, group: `font_${scene}` })
            .checked(currentFontType === FontType.SYSTEM && currentSystemId === font.id)
            .onChange((isChecked: boolean) => {
              if (isChecked) {
                this.setFont(scene, FontType.SYSTEM, font.id);
              }
            })

          Column({ space: 2 }) {
            Text(font.displayName)
              .fontSize(14)
              .fontFamily(font.name)
              .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_primary', this.themeState.currentTheme))
            Text('预览文字 Preview 123')
              .fontSize(12)
              .fontFamily(font.name)
              .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_muted', this.themeState.currentTheme))
          }
          .alignItems(HorizontalAlign.Start)
          .layoutWeight(1)
        }
        .width('100%')
        .padding(12)
        .backgroundColor(ThemeAwareHelper.getTestManagementThemedColor('comp_background_tertiary', this.themeState.currentTheme))
        .borderRadius(8)
      }, (font: SystemFont) => font.id)

      // 自定义字体
      if (this.customFonts.length > 0) {
        Text('自定义字体')
          .fontSize(14)
          .fontWeight(FontWeight.Medium)
          .fontFamily(this.appFontFamily)
          .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_secondary', this.themeState.currentTheme))
          .width('100%')
          .padding({ left: 4, top: 8 })

        ForEach(this.customFonts, (font: CustomFont) => {
          Row({ space: 12 }) {
            Radio({ value: `custom_${font.id}`, group: `font_${scene}` })
              .checked(currentFontType === FontType.CUSTOM && currentCustomId === font.id)
              .onChange((isChecked: boolean) => {
                if (isChecked) {
                  this.setFont(scene, FontType.CUSTOM, font.id);
                }
              })

            Column({ space: 2 }) {
              Text(font.displayName)
                .fontSize(14)
                .fontFamily(font.familyName)
                .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_primary', this.themeState.currentTheme))
              Text(font.isRegistered ? '已注册' : '未注册')
                .fontSize(12)
                .fontFamily(this.appFontFamily)
                .fontColor(font.isRegistered ? 
                  ThemeAwareHelper.getTestManagementThemedColor('accent_green', this.themeState.currentTheme) :
                  ThemeAwareHelper.getTestManagementThemedColor('button_danger', this.themeState.currentTheme))
            }
            .alignItems(HorizontalAlign.Start)
            .layoutWeight(1)

            Button({ type: ButtonType.Circle, stateEffect: true }) {
              SymbolGlyph($r('sys.symbol.trash')).fontSize(14).fontColor([ThemeAwareHelper.getTestManagementThemedColor('button_danger', this.themeState.currentTheme)])
            }
            .width(32).height(32)
            .backgroundColor(Color.Transparent)
            .onClick(() => {
              this.deleteCustomFont(font.id);
            })
          }
          .width('100%')
          .padding(12)
          .backgroundColor(ThemeAwareHelper.getTestManagementThemedColor('comp_background_tertiary', this.themeState.currentTheme))
          .borderRadius(8)
        }, (font: CustomFont) => font.id)
      }
    }
    .width('100%')
    .padding({ left: 16, right: 16, top: 8, bottom: 16 })
  }

  @Builder
  buildAppFontSection() {
    Column({ space: 0 }) {
      this.buildSectionHeader('界面字体', '设置APP界面的字体样式', 'app')

      if (this.expandedSection === 'app' && this.settings) {
        Column({ space: 12 }) {
          this.buildFontSelector(FontScene.APP_UI, this.settings.appFontType, this.settings.appSystemFontId, this.settings.appCustomFontId)
        }
        .backgroundColor(SettingsPanelSurfaceHelper.getBackground(this.themeState.currentTheme))
        .linearGradient(SettingsPanelSurfaceHelper.getSurfaceGradient(this.themeState.currentTheme))
        .backgroundBlurStyle(SettingsPanelSurfaceHelper.getBlurStyle(this.themeState.currentTheme), SettingsPanelSurfaceHelper.getBlurOptions(this.themeState.currentTheme))
        .backgroundEffect(SettingsPanelSurfaceHelper.getBackgroundEffect(this.themeState.currentTheme))
        .borderRadius({ bottomLeft: 12, bottomRight: 12 })
        .clip(true)
        .border({ width: SettingsPanelSurfaceHelper.getBorderWidth(this.themeState.currentTheme), color: SettingsPanelSurfaceHelper.getBorderColor(this.themeState.currentTheme) })
        .margin({ top: -12 })
        .transition(TransitionEffect.asymmetric(
          TransitionEffect.OPACITY.animation({ duration: 200, curve: Curve.EaseOut })
            .combine(TransitionEffect.translate({ y: -10 }).animation({ duration: 200, curve: Curve.EaseOut })),
          TransitionEffect.OPACITY.animation({ duration: 150, curve: Curve.EaseIn })
        ))
      }
    }
  }

  @Builder
  buildNovelFontSection() {
    Column({ space: 0 }) {
      this.buildSectionHeader('小说字体', '设置小说阅读器的字体样式', 'novel')

      if (this.expandedSection === 'novel' && this.settings) {
        Column({ space: 12 }) {
          this.buildFontSelector(FontScene.NOVEL, this.settings.novelFontType, this.settings.novelSystemFontId, this.settings.novelCustomFontId)
        }
        .backgroundColor(SettingsPanelSurfaceHelper.getBackground(this.themeState.currentTheme))
        .linearGradient(SettingsPanelSurfaceHelper.getSurfaceGradient(this.themeState.currentTheme))
        .backgroundBlurStyle(SettingsPanelSurfaceHelper.getBlurStyle(this.themeState.currentTheme), SettingsPanelSurfaceHelper.getBlurOptions(this.themeState.currentTheme))
        .backgroundEffect(SettingsPanelSurfaceHelper.getBackgroundEffect(this.themeState.currentTheme))
        .borderRadius({ bottomLeft: 12, bottomRight: 12 })
        .clip(true)
        .border({ width: SettingsPanelSurfaceHelper.getBorderWidth(this.themeState.currentTheme), color: SettingsPanelSurfaceHelper.getBorderColor(this.themeState.currentTheme) })
        .margin({ top: -12 })
        .transition(TransitionEffect.asymmetric(
          TransitionEffect.OPACITY.animation({ duration: 200, curve: Curve.EaseOut })
            .combine(TransitionEffect.translate({ y: -10 }).animation({ duration: 200, curve: Curve.EaseOut })),
          TransitionEffect.OPACITY.animation({ duration: 150, curve: Curve.EaseIn })
        ))
      }
    }
  }

  @Builder
  buildEbookFontSection() {
    Column({ space: 0 }) {
      this.buildSectionHeader('电子书字体', '设置电子书阅读器的字体样式', 'ebook')

      if (this.expandedSection === 'ebook' && this.settings) {
        Column({ space: 12 }) {
          this.buildFontSelector(FontScene.EBOOK, this.settings.ebookFontType, this.settings.ebookSystemFontId, this.settings.ebookCustomFontId)
        }
        .backgroundColor(SettingsPanelSurfaceHelper.getBackground(this.themeState.currentTheme))
        .linearGradient(SettingsPanelSurfaceHelper.getSurfaceGradient(this.themeState.currentTheme))
        .backgroundBlurStyle(SettingsPanelSurfaceHelper.getBlurStyle(this.themeState.currentTheme), SettingsPanelSurfaceHelper.getBlurOptions(this.themeState.currentTheme))
        .backgroundEffect(SettingsPanelSurfaceHelper.getBackgroundEffect(this.themeState.currentTheme))
        .borderRadius({ bottomLeft: 12, bottomRight: 12 })
        .clip(true)
        .border({ width: SettingsPanelSurfaceHelper.getBorderWidth(this.themeState.currentTheme), color: SettingsPanelSurfaceHelper.getBorderColor(this.themeState.currentTheme) })
        .margin({ top: -12 })
        .transition(TransitionEffect.asymmetric(
          TransitionEffect.OPACITY.animation({ duration: 200, curve: Curve.EaseOut })
            .combine(TransitionEffect.translate({ y: -10 }).animation({ duration: 200, curve: Curve.EaseOut })),
          TransitionEffect.OPACITY.animation({ duration: 150, curve: Curve.EaseIn })
        ))
      }
    }
  }

  @Builder
  buildCustomFontManagement() {
    Column({ space: 12 }) {
      Row() {
        Text('自定义字体管理')
          .fontSize(16)
          .fontFamily(this.appFontFamily)
          .fontWeight(FontWeight.Medium)
          .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_primary', this.themeState.currentTheme))
        Blank()
        Button('导入字体')
          .fontSize(13)
          .height(32)
          .fontFamily(this.appFontFamily)
          .backgroundColor(ThemeAwareHelper.getTestManagementThemedColor('accent_primary', this.themeState.currentTheme))
          .onClick(() => {
            this.importCustomFont();
          })
      }
      .width('100%')
      .padding(16)
      .backgroundColor(SettingsPanelSurfaceHelper.getBackground(this.themeState.currentTheme))
      .linearGradient(SettingsPanelSurfaceHelper.getSurfaceGradient(this.themeState.currentTheme))
      .backgroundBlurStyle(SettingsPanelSurfaceHelper.getBlurStyle(this.themeState.currentTheme), SettingsPanelSurfaceHelper.getBlurOptions(this.themeState.currentTheme))
      .backgroundEffect(SettingsPanelSurfaceHelper.getBackgroundEffect(this.themeState.currentTheme))
      .borderRadius(SettingsPanelSurfaceHelper.getRadius(this.themeState.currentTheme))
      .clip(true)
      .border({ width: SettingsPanelSurfaceHelper.getBorderWidth(this.themeState.currentTheme), color: SettingsPanelSurfaceHelper.getBorderColor(this.themeState.currentTheme) })
      .shadow({
        radius: SettingsPanelSurfaceHelper.getRadius(this.themeState.currentTheme) + 4,
        color: SettingsPanelSurfaceHelper.getShadowColor(this.themeState.currentTheme),
        offsetX: 0,
        offsetY: 8
      })

      if (this.customFonts.length === 0) {
        Text('暂无自定义字体，点击上方按钮导入')
          .fontSize(13)
          .fontFamily(this.appFontFamily)
          .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_muted', this.themeState.currentTheme))
          .width('100%')
          .textAlign(TextAlign.Center)
          .padding(16)
      } else {
        Text(`已导入 ${this.customFonts.length} 个自定义字体`)
          .fontSize(13)
          .fontFamily(this.appFontFamily)
          .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_secondary', this.themeState.currentTheme))
          .width('100%')
          .padding({ left: 16 })
      }
    }
  }

  @Builder
  buildResetButton() {
    Button('重置为默认设置')
      .width('100%')
      .fontSize(14)
      .fontFamily(this.appFontFamily)
      .fontColor(ThemeAwareHelper.getTestManagementThemedColor('button_danger', this.themeState.currentTheme))
      .backgroundColor(SettingsPanelSurfaceHelper.getBackground(this.themeState.currentTheme))
      .linearGradient(SettingsPanelSurfaceHelper.getSurfaceGradient(this.themeState.currentTheme))
      .backgroundBlurStyle(SettingsPanelSurfaceHelper.getBlurStyle(this.themeState.currentTheme), SettingsPanelSurfaceHelper.getBlurOptions(this.themeState.currentTheme))
      .backgroundEffect(SettingsPanelSurfaceHelper.getBackgroundEffect(this.themeState.currentTheme))
      .borderRadius(SettingsPanelSurfaceHelper.getRadius(this.themeState.currentTheme))
      .clip(true)
      .border({ width: SettingsPanelSurfaceHelper.getBorderWidth(this.themeState.currentTheme), color: SettingsPanelSurfaceHelper.getBorderColor(this.themeState.currentTheme) })
      .shadow({
        radius: SettingsPanelSurfaceHelper.getRadius(this.themeState.currentTheme) + 4,
        color: SettingsPanelSurfaceHelper.getShadowColor(this.themeState.currentTheme),
        offsetX: 0,
        offsetY: 8
      })
      .onClick(async () => {
        await this.fontManager.resetToDefault();
        this.settings = this.fontManager.getSettings();
        this.getUIContext().getPromptAction().showToast({ message: '已重置为默认设置' });
      })
  }

  build() {
    HdsNavDestination() {
      Stack() {
        SharedPageBackgroundLayer({
          defaultBackgroundColor: ThemeAwareHelper.getTestManagementThemedColor('background_dark', this.themeState.currentTheme),
          mode: GlobalBackgroundLayerMode.IMMERSIVE
        })
          .width('100%')
          .height('100%')
          .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.TOP, SafeAreaEdge.BOTTOM])

        Scroll(this.scroller) {
          Column({ space: 16 }) {
            Blank().height(SettingsPageTitleBarManager.getContentTopPadding(this.statusBarHeight))
            Flex({
              wrap: FlexWrap.Wrap,
              justifyContent: this.responsive_isLandscape ? FlexAlign.SpaceBetween : FlexAlign.Start
            }) {
              // 自定义字体管理
              Column() {
                this.buildCustomFontManagement()
              }
              .width(this.responsive_isLandscape ? '48%' : '100%')
              .padding(4)
              .backgroundColor(SettingsSearchSupport.getHighlightOverlayBackground(
                this.themeState.currentTheme,
                this.activeSearchAnchorId,
                'font_custom'
              ))
              .borderRadius(16)
              .border({
                width: SettingsSearchSupport.isHighlightActive(this.activeSearchAnchorId, 'font_custom') ? 1 : 0,
                color: SettingsSearchSupport.getHighlightOverlayBorder(
                  this.themeState.currentTheme,
                  this.activeSearchAnchorId,
                  'font_custom'
                )
              })
              .scale({
                x: SettingsSearchSupport.getHighlightScale(this.activeSearchAnchorId, 'font_custom', this.searchHighlightPulse),
                y: SettingsSearchSupport.getHighlightScale(this.activeSearchAnchorId, 'font_custom', this.searchHighlightPulse)
              })
              .shadow(SettingsSearchSupport.getHighlightOverlayShadow(
                this.themeState.currentTheme,
                this.activeSearchAnchorId,
                'font_custom',
                this.searchHighlightPulse
              ))
              .animation({ duration: 260, curve: Curve.EaseOut })
              .margin({ bottom: 16 })

              // 界面字体设置
              Column() {
                this.buildAppFontSection()
              }
              .width(this.responsive_isLandscape ? '48%' : '100%')
              .padding(4)
              .backgroundColor(SettingsSearchSupport.getHighlightOverlayBackground(
                this.themeState.currentTheme,
                this.activeSearchAnchorId,
                'font_app'
              ))
              .borderRadius(16)
              .border({
                width: SettingsSearchSupport.isHighlightActive(this.activeSearchAnchorId, 'font_app') ? 1 : 0,
                color: SettingsSearchSupport.getHighlightOverlayBorder(
                  this.themeState.currentTheme,
                  this.activeSearchAnchorId,
                  'font_app'
                )
              })
              .scale({
                x: SettingsSearchSupport.getHighlightScale(this.activeSearchAnchorId, 'font_app', this.searchHighlightPulse),
                y: SettingsSearchSupport.getHighlightScale(this.activeSearchAnchorId, 'font_app', this.searchHighlightPulse)
              })
              .shadow(SettingsSearchSupport.getHighlightOverlayShadow(
                this.themeState.currentTheme,
                this.activeSearchAnchorId,
                'font_app',
                this.searchHighlightPulse
              ))
              .animation({ duration: 260, curve: Curve.EaseOut })
              .margin({ bottom: 16 })

              // 小说字体设置
              Column() {
                this.buildNovelFontSection()
              }
              .width(this.responsive_isLandscape ? '48%' : '100%')
              .padding(4)
              .backgroundColor(SettingsSearchSupport.getHighlightOverlayBackground(
                this.themeState.currentTheme,
                this.activeSearchAnchorId,
                'font_novel'
              ))
              .borderRadius(16)
              .border({
                width: SettingsSearchSupport.isHighlightActive(this.activeSearchAnchorId, 'font_novel') ? 1 : 0,
                color: SettingsSearchSupport.getHighlightOverlayBorder(
                  this.themeState.currentTheme,
                  this.activeSearchAnchorId,
                  'font_novel'
                )
              })
              .scale({
                x: SettingsSearchSupport.getHighlightScale(this.activeSearchAnchorId, 'font_novel', this.searchHighlightPulse),
                y: SettingsSearchSupport.getHighlightScale(this.activeSearchAnchorId, 'font_novel', this.searchHighlightPulse)
              })
              .shadow(SettingsSearchSupport.getHighlightOverlayShadow(
                this.themeState.currentTheme,
                this.activeSearchAnchorId,
                'font_novel',
                this.searchHighlightPulse
              ))
              .animation({ duration: 260, curve: Curve.EaseOut })
              .margin({ bottom: 16 })

              // 电子书字体设置
              Column() {
                this.buildEbookFontSection()
              }
              .width(this.responsive_isLandscape ? '48%' : '100%')
              .padding(4)
              .backgroundColor(SettingsSearchSupport.getHighlightOverlayBackground(
                this.themeState.currentTheme,
                this.activeSearchAnchorId,
                'font_ebook'
              ))
              .borderRadius(16)
              .border({
                width: SettingsSearchSupport.isHighlightActive(this.activeSearchAnchorId, 'font_ebook') ? 1 : 0,
                color: SettingsSearchSupport.getHighlightOverlayBorder(
                  this.themeState.currentTheme,
                  this.activeSearchAnchorId,
                  'font_ebook'
                )
              })
              .scale({
                x: SettingsSearchSupport.getHighlightScale(this.activeSearchAnchorId, 'font_ebook', this.searchHighlightPulse),
                y: SettingsSearchSupport.getHighlightScale(this.activeSearchAnchorId, 'font_ebook', this.searchHighlightPulse)
              })
              .shadow(SettingsSearchSupport.getHighlightOverlayShadow(
                this.themeState.currentTheme,
                this.activeSearchAnchorId,
                'font_ebook',
                this.searchHighlightPulse
              ))
              .animation({ duration: 260, curve: Curve.EaseOut })
              .margin({ bottom: 16 })

              // 重置按钮
              Column() {
                this.buildResetButton()
              }
              .width(this.responsive_isLandscape ? '48%' : '100%')
              .padding(4)
              .backgroundColor(SettingsSearchSupport.getHighlightOverlayBackground(
                this.themeState.currentTheme,
                this.activeSearchAnchorId,
                'font_reset'
              ))
              .borderRadius(16)
              .border({
                width: SettingsSearchSupport.isHighlightActive(this.activeSearchAnchorId, 'font_reset') ? 1 : 0,
                color: SettingsSearchSupport.getHighlightOverlayBorder(
                  this.themeState.currentTheme,
                  this.activeSearchAnchorId,
                  'font_reset'
                )
              })
              .scale({
                x: SettingsSearchSupport.getHighlightScale(this.activeSearchAnchorId, 'font_reset', this.searchHighlightPulse),
                y: SettingsSearchSupport.getHighlightScale(this.activeSearchAnchorId, 'font_reset', this.searchHighlightPulse)
              })
              .shadow(SettingsSearchSupport.getHighlightOverlayShadow(
                this.themeState.currentTheme,
                this.activeSearchAnchorId,
                'font_reset',
                this.searchHighlightPulse
              ))
              .animation({ duration: 260, curve: Curve.EaseOut })
              .margin({ bottom: 16 })
            }
            .width('100%')

            Blank().height(40)
          }
          .enabled(this.settingsTapEnabled)
          .width('100%')
          .constraintSize({ maxWidth: this.responsive_maxContentWidth })
          .padding({ left: this.responsive_contentPadding, right: this.responsive_contentPadding, bottom: 40 })
        }
        .width('100%')
        .height('100%')
        .align(Alignment.TopStart)
        .scrollBar(BarState.Auto)
        .onDidScroll((_xOffset: number, _yOffset: number) => {
          this.markSettingsScrolling();
        })
        .edgeEffect(EdgeEffect.Spring)
        .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.TOP, SafeAreaEdge.BOTTOM])
        SettingsImmersiveTitleBar({
          themeState: this.themeState,
          title: '字体设置',
          appFontFamily: this.appFontFamily,
          contentPadding: this.responsive_contentPadding,
          maxContentWidth: this.responsive_maxContentWidth,
          pathStack: this.pathStack
        })
      }
    }
    .hideTitleBar(true)
    .ignoreLayoutSafeArea([LayoutSafeAreaType.SYSTEM], [LayoutSafeAreaEdge.TOP, LayoutSafeAreaEdge.BOTTOM])
    .onReady((context: NavDestinationContext) => {
      this.pathStack = context.pathStack;
      ThemeAwareHelper.initializeThemeAware(
        this.componentId,
        this.themeState,
        (newTheme: ThemeType) => {},
        (newState: ThemeAwareState) => { this.themeState = newState; }
      );
      this.applyPendingSearchTarget();
    })
    .backgroundColor(Color.Transparent)
  }
}

interface NavDestinationContext {
  pathStack: NavPathStack;
}
