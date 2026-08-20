import { HdsNavDestination } from '@kit.UIDesignKit';
import { LengthMetrics } from '@kit.ArkUI';
import { ThemeAwareHelper, ThemeAwareState } from 'manxia_theme/src/main/ets/Framework/Components/ThemeAware';
import { ThemeManager, ThemeType } from 'manxia_theme/src/main/ets/Framework/Managers/ThemeManager';
import { FontAwareHelper, FontAwareState } from '../../Framework/Components/FontAware';
import { SettingsManager, SettingKeys } from '../../Framework/Managers/SettingsManager';
import { GuideStep, WelcomeGuideManager } from '../../Framework/Managers/WelcomeGuideManager';
import { logger } from 'manxia_core/src/main/ets/Utils/Logger';
import { GlobalBackgroundLayerMode } from 'manxia_theme/src/main/ets/Framework/Components/GlobalBackgroundLayer';
import { SharedPageBackgroundLayer } from '../../Framework/Components/SharedPageBackgroundLayer';
import { SettingsImmersiveTitleBar } from './SettingsImmersiveTitleBar';
import { SettingsPageTitleBarManager } from './SettingsPageTitleBarManager';
import { SettingsPanelSurfaceHelper } from './SettingsPanelSurfaceHelper';

const TAG = 'SourceFeatureSettingsSubPage';
const TITLE_BAR_HEIGHT_MINI: number = 56;

interface SingleGuideRouteParams {
  singleGuidePreview: boolean;
  singleGuideStep: GuideStep;
}

@Component
export struct SourceFeatureSettingsSubPage {
  @StorageProp('statusBarHeight') statusBarHeight: number = 0;
  @State themeState: ThemeAwareState = new ThemeAwareState();
  @State fontState: FontAwareState = new FontAwareState();
  @StorageLink('appFontFamily') appFontFamily: string = 'HarmonyOS Sans';
  @StorageLink('source_features_enabled') sourceFeaturesEnabled: boolean = false;
  @StorageLink('source_detail_translation_tag_enabled') sourceDetailTranslationTagEnabled: boolean = true;
  @StorageLink('source_detail_multi_window_enabled') sourceDetailMultiWindowEnabled: boolean = false;

  private readonly componentId: string = 'SourceFeatureSettingsSubPage';
  private readonly settingsManager: SettingsManager = SettingsManager.getInstance();
  private readonly welcomeGuideManager: WelcomeGuideManager = WelcomeGuideManager.getInstance();

  aboutToAppear(): void {
    ThemeAwareHelper.initializeThemeAware(this.componentId, this.themeState, (newTheme: ThemeType) => {
      logger.info(TAG, `主题切换: ${newTheme}`);
    });
    FontAwareHelper.initializeFontAware(
      this.componentId,
      this.fontState,
      (newState: FontAwareState) => {
        this.fontState = newState;
      }
    );
  }

  aboutToDisappear(): void {
    ThemeAwareHelper.cleanupThemeAware(this.componentId);
    FontAwareHelper.cleanupFontAware(this.componentId);
  }

  private async maybeLaunchSourceFeatureGuide(previousValue: boolean, nextValue: boolean): Promise<void> {
    if (previousValue || !nextValue) {
      return;
    }

    try {
      await this.welcomeGuideManager.initialize();
      if (this.welcomeGuideManager.isSourceFeatureGuideShown()) {
        return;
      }

      await this.welcomeGuideManager.startSourceFeatureGuide();
      const router = this.getUIContext()?.getRouter();
      if (!router) {
        logger.warn(TAG, 'Router不可用，无法打开源功能引导页');
        return;
      }

      await router.pushUrl({
        url: 'pages/WelcomeGuidePage'
      });
      logger.info(TAG, '首次开启显示源功能，已打开源功能引导页');
    } catch (error) {
      logger.error(TAG, `首次开启源功能后打开引导失败: ${String(error)}`);
    }
  }

  private showToast(message: string): void {
    try {
      this.getUIContext().getPromptAction().showToast({
        message,
        duration: 1600
      });
    } catch (error) {
      logger.warn(TAG, `显示提示失败: ${String(error)}`);
    }
  }

  private async saveBooleanSetting(key: string, storageKey: string, value: boolean): Promise<void> {
    await this.settingsManager.setBoolean(key, value);
    this.settingsManager.syncToAppStorage();
    AppStorage.setOrCreate(storageKey, value);
  }

  private async openSingleGuidePage(step: GuideStep): Promise<void> {
    try {
      const router = this.getUIContext()?.getRouter();
      if (!router) {
        logger.warn(TAG, `Router不可用，无法打开单页引导: step=${step}`);
        this.showToast('暂时无法打开引导');
        return;
      }

      const params: SingleGuideRouteParams = {
        singleGuidePreview: true,
        singleGuideStep: step
      };

      await router.pushUrl({
        url: 'pages/WelcomeGuidePage',
        params
      });
      logger.info(TAG, `已打开单页引导: step=${step}`);
    } catch (error) {
      logger.error(TAG, `打开单页引导失败: ${String(error)}`);
      this.showToast('打开引导失败');
    }
  }

  @Builder
  buildToggleCard() {
    Column({ space: 14 }) {
      Row() {
        Column({ space: 4 }) {
          Text('显示源功能')
            .fontSize(16)
            .fontWeight(FontWeight.Medium)
            .fontFamily(this.appFontFamily)
            .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_primary', this.themeState.currentTheme))

          Text('控制主页面、全局搜索、帮助中心等位置中与图源/书源相关的入口、标签、按钮与信息展示。')
            .fontSize(13)
            .fontFamily(this.appFontFamily)
            .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_secondary', this.themeState.currentTheme))
            .maxLines(3)
        }
        .alignItems(HorizontalAlign.Start)
        .layoutWeight(1)

        Toggle({ type: ToggleType.Switch, isOn: this.sourceFeaturesEnabled })
          .selectedColor(ThemeAwareHelper.getTestManagementThemedColor('accent_blue', this.themeState.currentTheme))
          .onChange(async (isOn: boolean) => {
            const previousValue = this.sourceFeaturesEnabled;
            this.sourceFeaturesEnabled = isOn;
            await this.settingsManager.setBoolean(SettingKeys.SOURCE_FEATURES_ENABLED, isOn);
            this.settingsManager.syncToAppStorage();
            AppStorage.setOrCreate('source_features_enabled', isOn);
            await this.maybeLaunchSourceFeatureGuide(previousValue, isOn);
          })
      }
      .width('100%')

      Text('默认关闭。关闭后不会删除已有源配置，只会隐藏本次纳入治理范围内的展示入口。')
        .fontSize(12)
        .fontFamily(this.appFontFamily)
        .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_muted', this.themeState.currentTheme))
        .width('100%')
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
  }

  @Builder
  buildGuideButton(label: string, symbol: Resource, step: GuideStep) {
    Button() {
      Row({ space: 8 }) {
        SymbolGlyph(symbol)
          .fontSize(16)
          .fontColor([ThemeAwareHelper.getTestManagementThemedColor('text_white', this.themeState.currentTheme)])

        Text(label)
          .fontSize(14)
          .fontWeight(FontWeight.Medium)
          .fontFamily(this.appFontFamily)
          .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_white', this.themeState.currentTheme))
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
      }
      .justifyContent(FlexAlign.Center)
      .width('100%')
    }
    .width('100%')
    .height(44)
    .padding({ left: 12, right: 12 })
    .backgroundColor(ThemeAwareHelper.getTestManagementThemedColor('accent_blue', this.themeState.currentTheme))
    .borderRadius(22)
    .onClick(() => {
      void this.openSingleGuidePage(step);
    })
  }

  @Builder
  buildMangaSourceCommonSettingsCard() {
    Column({ space: 14 }) {
      Column({ space: 4 }) {
        Text('漫画图源共通设置')
          .fontSize(16)
          .fontWeight(FontWeight.Medium)
          .fontFamily(this.appFontFamily)
          .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_primary', this.themeState.currentTheme))
          .width('100%')

        Text('这些选项作用于漫画图源详情页，不会修改单个图源的独立配置。')
          .fontSize(13)
          .fontFamily(this.appFontFamily)
          .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_secondary', this.themeState.currentTheme))
          .maxLines(2)
          .width('100%')
      }
      .alignItems(HorizontalAlign.Start)
      .width('100%')

      Column({ space: 0 }) {
        Row() {
          Column({ space: 4 }) {
            Text('显示“汉化/翻译”标签')
              .fontSize(15)
              .fontWeight(FontWeight.Medium)
              .fontFamily(this.appFontFamily)
              .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_primary', this.themeState.currentTheme))

            Text('在图源详情页的漫画封面上标记标题中带汉化、翻译、中文等关键词的内容。')
              .fontSize(12)
              .fontFamily(this.appFontFamily)
              .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_muted', this.themeState.currentTheme))
              .maxLines(2)
              .textOverflow({ overflow: TextOverflow.Ellipsis })
          }
          .alignItems(HorizontalAlign.Start)
          .layoutWeight(1)

          Toggle({ type: ToggleType.Switch, isOn: this.sourceDetailTranslationTagEnabled })
            .selectedColor(ThemeAwareHelper.getTestManagementThemedColor('accent_blue', this.themeState.currentTheme))
            .onChange((isOn: boolean) => {
              this.sourceDetailTranslationTagEnabled = isOn;
              void this.saveBooleanSetting(
                SettingKeys.SOURCE_DETAIL_TRANSLATION_TAG_ENABLED,
                'source_detail_translation_tag_enabled',
                isOn
              );
            })
        }
        .width('100%')
        .padding({ top: 2, bottom: 14 })

        Row()
          .width('100%')
          .height(1)
          .backgroundColor(SettingsPanelSurfaceHelper.getBorderColor(this.themeState.currentTheme))
          .opacity(0.55)

        Row() {
          Column({ space: 4 }) {
            Text('图源详情页多窗口')
              .fontSize(15)
              .fontWeight(FontWeight.Medium)
              .fontFamily(this.appFontFamily)
              .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_primary', this.themeState.currentTheme))

            Text('开启后，可以同时保留多个漫画图源详情页；关闭后沿用单窗口图源详情模式。')
              .fontSize(12)
              .fontFamily(this.appFontFamily)
              .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_muted', this.themeState.currentTheme))
              .maxLines(2)
              .textOverflow({ overflow: TextOverflow.Ellipsis })
          }
          .alignItems(HorizontalAlign.Start)
          .layoutWeight(1)

          Toggle({ type: ToggleType.Switch, isOn: this.sourceDetailMultiWindowEnabled })
            .selectedColor(ThemeAwareHelper.getTestManagementThemedColor('accent_blue', this.themeState.currentTheme))
            .onChange((isOn: boolean) => {
              this.sourceDetailMultiWindowEnabled = isOn;
              void this.saveBooleanSetting(
                SettingKeys.SOURCE_DETAIL_MULTI_WINDOW_ENABLED,
                'source_detail_multi_window_enabled',
                isOn
              );
            })
        }
        .width('100%')
        .padding({ top: 14, bottom: 2 })
      }
      .width('100%')
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
  }

  @Builder
  buildGuideEntryCard() {
    Column({ space: 14 }) {
      Column({ space: 4 }) {
        Text('引导页面')
          .fontSize(16)
          .fontWeight(FontWeight.Medium)
          .fontFamily(this.appFontFamily)
          .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_primary', this.themeState.currentTheme))
          .width('100%')

        Text('查看图源或书源说明')
          .fontSize(13)
          .fontFamily(this.appFontFamily)
          .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_secondary', this.themeState.currentTheme))
          .maxLines(2)
          .width('100%')
      }
      .alignItems(HorizontalAlign.Start)
      .width('100%')

      Column({ space: 10 }) {
        this.buildGuideButton('图源引导', $r('sys.symbol.picture'), GuideStep.IMAGE_SOURCE_GUIDE)
        this.buildGuideButton('书源引导', $r('sys.symbol.list_book'), GuideStep.BOOK_SOURCE_GUIDE)
      }
      .width('100%')
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

        Scroll() {
          Column({ space: 16 }) {
            Blank().height(SettingsPageTitleBarManager.getContentTopPadding(this.statusBarHeight))
            this.buildToggleCard()
            this.buildMangaSourceCommonSettingsCard()
            this.buildGuideEntryCard()
            Blank().height(40)
          }
          .width('100%')
          .padding({ left: 16, right: 16, bottom: 40 })
        }
        .width('100%')
        .height('100%')
        .scrollBar(BarState.Auto)
        .edgeEffect(EdgeEffect.Spring)
        .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.TOP, SafeAreaEdge.BOTTOM])
        SettingsImmersiveTitleBar({
          themeState: this.themeState,
          title: '源功能设置',
          appFontFamily: this.appFontFamily
        })
      }
    }
    .hideTitleBar(true)
    .ignoreLayoutSafeArea([LayoutSafeAreaType.SYSTEM], [LayoutSafeAreaEdge.TOP, LayoutSafeAreaEdge.BOTTOM])
    .backgroundColor(Color.Transparent)
  }
}
