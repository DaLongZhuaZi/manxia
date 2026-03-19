// 文件路径: entry/src/main/ets/pages/settings/FontSettingsSubPage.ets
/**
 * 字体设置二级页面
 * 管理APP界面字体、小说字体、电子书字体
 */

import { HdsNavDestination, HdsNavDestinationAttribute, ScrollEffectType } from '@kit.UIDesignKit';
import { LengthMetrics, promptAction } from '@kit.ArkUI';
import { ThemeAwareState, ThemeAwareHelper } from '../../Framework/Components/ThemeAware';
import { FontAwareHelper, FontAwareState } from '../../Framework/Components/FontAware';
import { ThemeManager, ThemeType } from '../../Framework/Managers/ThemeManager';
import { FontManager, getFontManager, FontType, FontScene, SystemFont, CustomFont, FontSettings } from '../../Framework/Managers/FontManager';
import { logger } from '../../Utils/Logger';
import { picker } from '@kit.CoreFileKit';
import { common } from '@kit.AbilityKit';
import { DeviceAdaptationManager, DeviceInfo, DeviceChangeListener, Breakpoint } from '../../Framework/Managers/DeviceAdaptationManager';
import { ResponsiveLayoutHelper } from '../../Framework/Utils/ResponsiveLayout';
import { SettingsSearchSupport } from './SettingsSearchSupport';

const TAG = 'FontSettingsSubPage';
const TITLE_BAR_HEIGHT_MINI: number = 56;

@Component
export struct FontSettingsSubPage {
  @State pathStack: NavPathStack = new NavPathStack();
  private scroller: Scroller = new Scroller();
  @State private settingsTapEnabled: boolean = true;
  private settingsTapUnlockTimer: number = -1;
  private readonly scrollTapGuardDurationMs: number = 140;
  
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
      const context = this.getUIContext().getHostContext() as common.UIAbilityContext;
      const documentPicker = new picker.DocumentViewPicker(context);
      const options = new picker.DocumentSelectOptions();
      options.maxSelectNumber = 1;
      
      const result = await documentPicker.select(options);
      if (result && result.length > 0) {
        const filePath = result[0];
        
        // 传递空字符串，让FontManager自动解析字体文件内部的真实名称
        // 这样可以正确显示中文、日文等多语言字体名称
        const customFont = await this.fontManager.addCustomFont('', filePath);
        this.customFonts = this.fontManager.getCustomFonts();
        promptAction.showToast({ message: `字体 "${customFont.displayName}" 导入成功` });
      }
    } catch (error) {
      logger.error(TAG, `导入字体失败: ${String(error)}`);
      promptAction.showToast({ message: `导入失败: ${String(error)}` });
    }
  }

  private async deleteCustomFont(fontId: string): Promise<void> {
    try {
      await this.fontManager.removeCustomFont(fontId);
      this.customFonts = this.fontManager.getCustomFonts();
      promptAction.showToast({ message: '字体已删除' });
    } catch (error) {
      promptAction.showToast({ message: String(error) });
    }
  }

  private async setFont(scene: FontScene, fontType: FontType, fontId: string): Promise<void> {
    try {
      switch (scene) {
        case FontScene.APP_UI:
          await this.fontManager.setAppFont(fontType, fontId);
          break;
        case FontScene.NOVEL:
          await this.fontManager.setNovelFont(fontType, fontId);
          break;
        case FontScene.EBOOK:
          await this.fontManager.setEbookFont(fontType, fontId);
          break;
      }
      this.settings = this.fontManager.getSettings();
      promptAction.showToast({ message: '字体已更新' });
    } catch (error) {
      promptAction.showToast({ message: `设置失败: ${String(error)}` });
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
    .backgroundColor(ThemeAwareHelper.getTestManagementThemedColor('panel_background', this.themeState.currentTheme))
    .borderRadius(this.expandedSection === sectionId ? { topLeft: 12, topRight: 12 } : 12)
    .border({ width: 1, color: ThemeAwareHelper.getTestManagementThemedColor('panel_border', this.themeState.currentTheme) })
    .animation({ duration: 250, curve: Curve.EaseInOut })
    .onClick(() => {
      animateTo({
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
  buildFontSizeSlider(label: string, value: number, min: number, max: number, step: number, unit: string, onChange: (value: number) => void) {
    Column({ space: 8 }) {
      Row() {
        Text(label)
          .fontSize(14)
          .fontFamily(this.appFontFamily)
          .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_primary', this.themeState.currentTheme))
        Blank()
        Text(`${value.toFixed(1)}${unit}`)
          .fontSize(14)
          .fontFamily(this.appFontFamily)
          .fontColor(ThemeAwareHelper.getTestManagementThemedColor('accent_primary', this.themeState.currentTheme))
      }
      .width('100%')

      Slider({
        value: value,
        min: min,
        max: max,
        step: step,
        style: SliderStyle.InSet
      })
        .width('100%')
        .blockColor(ThemeAwareHelper.getTestManagementThemedColor('accent_primary', this.themeState.currentTheme))
        .trackColor(ThemeAwareHelper.getTestManagementThemedColor('comp_background_tertiary', this.themeState.currentTheme))
        .selectedColor(ThemeAwareHelper.getTestManagementThemedColor('accent_primary', this.themeState.currentTheme))
        .onChange((newValue: number) => {
          onChange(newValue);
        })
    }
    .width('100%')
    .padding({ left: 16, right: 16, bottom: 12 })
  }

  @Builder
  buildAppFontSection() {
    Column({ space: 0 }) {
      this.buildSectionHeader('界面字体', '设置APP界面的字体样式和大小', 'app')

      if (this.expandedSection === 'app' && this.settings) {
        Column({ space: 12 }) {
          this.buildFontSelector(FontScene.APP_UI, this.settings.appFontType, this.settings.appSystemFontId, this.settings.appCustomFontId)
          
          this.buildFontSizeSlider('字体大小倍率', this.settings.appFontSize, 0.8, 1.5, 0.1, 'x', async (value: number) => {
            await this.fontManager.setAppFontSize(value);
            this.settings = this.fontManager.getSettings();
          })
        }
        .backgroundColor(ThemeAwareHelper.getTestManagementThemedColor('panel_background', this.themeState.currentTheme))
        .borderRadius({ bottomLeft: 12, bottomRight: 12 })
        .border({ width: 1, color: ThemeAwareHelper.getTestManagementThemedColor('panel_border', this.themeState.currentTheme) })
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
          
          this.buildFontSizeSlider('字体大小', this.settings.novelFontSize, 12, 32, 1, 'px', async (value: number) => {
            await this.fontManager.setNovelFontSize(value);
            this.settings = this.fontManager.getSettings();
          })
          
          this.buildFontSizeSlider('行高倍率', this.settings.novelLineHeight, 1.0, 2.5, 0.1, 'x', async (value: number) => {
            await this.fontManager.setNovelLineHeight(value);
            this.settings = this.fontManager.getSettings();
          })
        }
        .backgroundColor(ThemeAwareHelper.getTestManagementThemedColor('panel_background', this.themeState.currentTheme))
        .borderRadius({ bottomLeft: 12, bottomRight: 12 })
        .border({ width: 1, color: ThemeAwareHelper.getTestManagementThemedColor('panel_border', this.themeState.currentTheme) })
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
          
          this.buildFontSizeSlider('字体大小', this.settings.ebookFontSize, 12, 32, 1, 'px', async (value: number) => {
            await this.fontManager.setEbookFontSize(value);
            this.settings = this.fontManager.getSettings();
          })
          
          this.buildFontSizeSlider('行高倍率', this.settings.ebookLineHeight, 1.0, 2.5, 0.1, 'x', async (value: number) => {
            await this.fontManager.setEbookLineHeight(value);
            this.settings = this.fontManager.getSettings();
          })
        }
        .backgroundColor(ThemeAwareHelper.getTestManagementThemedColor('panel_background', this.themeState.currentTheme))
        .borderRadius({ bottomLeft: 12, bottomRight: 12 })
        .border({ width: 1, color: ThemeAwareHelper.getTestManagementThemedColor('panel_border', this.themeState.currentTheme) })
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
      .backgroundColor(ThemeAwareHelper.getTestManagementThemedColor('panel_background', this.themeState.currentTheme))
      .borderRadius(12)
      .border({ width: 1, color: ThemeAwareHelper.getTestManagementThemedColor('panel_border', this.themeState.currentTheme) })

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
      .backgroundColor(ThemeAwareHelper.getTestManagementThemedColor('panel_background', this.themeState.currentTheme))
      .borderRadius(12)
      .border({ width: 1, color: ThemeAwareHelper.getTestManagementThemedColor('panel_border', this.themeState.currentTheme) })
      .onClick(async () => {
        await this.fontManager.resetToDefault();
        this.settings = this.fontManager.getSettings();
        promptAction.showToast({ message: '已重置为默认设置' });
      })
  }

  build() {
    HdsNavDestination() {
      Stack() {
        Column()
          .width('100%')
          .height('100%')
          .backgroundColor(ThemeAwareHelper.getTestManagementThemedColor('background_dark', this.themeState.currentTheme))
          .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.TOP, SafeAreaEdge.BOTTOM])

        Scroll(this.scroller) {
          Column({ space: 16 }) {
            Blank().height(TITLE_BAR_HEIGHT_MINI)
            Flex({
              wrap: FlexWrap.Wrap,
              justifyContent: this.responsive_isLandscape ? FlexAlign.SpaceBetween : FlexAlign.Start
            }) {
              // 自定义字体管理
              Column() {
                this.buildCustomFontManagement()
              }
              .width(this.responsive_isLandscape ? '48%' : '100%')
              .margin({ bottom: 16 })

              // 界面字体设置
              Column() {
                this.buildAppFontSection()
              }
              .width(this.responsive_isLandscape ? '48%' : '100%')
              .margin({ bottom: 16 })

              // 小说字体设置
              Column() {
                this.buildNovelFontSection()
              }
              .width(this.responsive_isLandscape ? '48%' : '100%')
              .margin({ bottom: 16 })

              // 电子书字体设置
              Column() {
                this.buildEbookFontSection()
              }
              .width(this.responsive_isLandscape ? '48%' : '100%')
              .margin({ bottom: 16 })

              // 重置按钮
              Column() {
                this.buildResetButton()
              }
              .width(this.responsive_isLandscape ? '48%' : '100%')
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
        .onScroll((_xOffset: number, _yOffset: number) => {
          this.markSettingsScrolling();
        })
        .edgeEffect(EdgeEffect.Spring)
        .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.TOP, SafeAreaEdge.BOTTOM])
      }
    }
    .titleBar({
      padding: {
        start: LengthMetrics.vp(16),
        end: LengthMetrics.vp(16)
      },
      style: {
        originalStyle: {
          backgroundStyle: { backgroundColor: ThemeAwareHelper.getTestManagementThemedColor('panel_background', this.themeState.currentTheme) },
          contentStyle: {
            titleStyle: { mainTitleColor: ThemeAwareHelper.getTestManagementThemedColor('text_primary', this.themeState.currentTheme) },
            backIconStyle: { backgroundColor: ThemeAwareHelper.getTestManagementThemedColor('comp_background_tertiary', this.themeState.currentTheme), iconColor: ThemeAwareHelper.getTestManagementThemedColor('icon_primary', this.themeState.currentTheme) }
          }
        }
      },
      content: {
        title: { mainTitle: '字体设置' }
      }
    })
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
