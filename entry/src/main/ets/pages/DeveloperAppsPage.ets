// 文件路径: entry/src/main/ets/pages/DeveloperAppsPage.ets
/**
 * 同开发者页面
 * 展示当前开发者的其他APP，提供跳转应用商店的链接
 */

import { HdsNavDestination, HdsNavDestinationAttribute } from '@kit.UIDesignKit';
import { ThemeAwareState, ThemeAwareHelper } from 'manxia_theme/src/main/ets/Framework/Components/ThemeAware';
import { ThemeManager, ThemeType } from 'manxia_theme/src/main/ets/Framework/Managers/ThemeManager';
import { FontAwareHelper, FontAwareState } from 'manxia_theme/src/main/ets/Framework/Components/FontAware';
import { logger } from 'manxia_core/src/main/ets/Utils/Logger';
import { PageLifecycleManager } from 'manxia_core/src/main/ets/Framework/Lifecycle/index';
import { DeviceAdaptationManager, DeviceInfo, DeviceChangeListener, Breakpoint } from 'manxia_theme/src/main/ets/Framework/Managers/DeviceAdaptationManager';
import { ResponsiveLayoutHelper } from 'manxia_theme/src/main/ets/Framework/Utils/ResponsiveLayout';
import { promptAction } from '@kit.ArkUI';
import { common } from '@kit.AbilityKit';
import { SettingsImmersiveTitleBar } from './settings/SettingsImmersiveTitleBar';
import { SettingsPageTitleBarManager } from 'manxia_features_ui/src/main/ets/pages/settings/SettingsPageTitleBarManager';
import { GlobalBackgroundLayerMode } from 'manxia_theme/src/main/ets/Framework/Components/GlobalBackgroundLayer';
import { SharedPageBackgroundLayer } from '../Framework/Components/SharedPageBackgroundLayer';
import { SettingsPanelSurfaceHelper } from 'manxia_features_ui/src/main/ets/pages/settings/SettingsPanelSurfaceHelper';

const TAG = 'DeveloperAppsPage';

interface DeveloperApp {
  name: string;
  icon?: Resource;
  description: string;
  appGalleryUrl?: string;
}

@Component
struct DeveloperAppsPage {
  @State pathStack: NavPathStack = new NavPathStack();
  @StorageProp('statusBarHeight') statusBarHeight: number = 0;
  @StorageProp('navigationBarHeight') navigationBarHeight: number = 0;
  private scroller: Scroller = new Scroller();

  @State themeState: ThemeAwareState = new ThemeAwareState();
  private themeManager: ThemeManager = ThemeManager.getInstance();
  private componentId: string = 'DeveloperAppsPage';

  @State fontState: FontAwareState = new FontAwareState();
  @StorageLink('appFontFamily') appFontFamily: string = 'HarmonyOS Sans';

  private deviceManager: DeviceAdaptationManager = DeviceAdaptationManager.getInstance();
  private deviceChangeListener: DeviceChangeListener | null = null;
  @State responsive_contentPadding: number = 16;
  @State responsive_maxContentWidth: number = 1200;
  @State responsive_isLandscape: boolean = false;
  private pageInitialized: boolean = false;

  private readonly developerApps: DeveloperApp[] = [
    {
      name: '漫匣',
      icon: $r('app.media.icon'),
      description: '一款基于HarmonyOS Next的现代化漫画阅读应用',
      appGalleryUrl: 'https://appgallery.huawei.com/app/detail?id=com.dlzz.manxia&channelId=SHARE&source=appshare'
    },
    {
      name: '花漾字影',
      icon: $r('app.media.lumabloom_icon'),
      description: '帮您轻松创作更亮眼的手持弹幕内容',
      appGalleryUrl: 'https://appgallery.huawei.com/app/detail?id=com.dlzz.lumabloom&channelId=SHARE&source=appshare'
    },
    {
      name: '书脉',
      icon: $r('app.media.shumai_icon'),
      description: '支持多种格式的元数据编辑与封面管理',
      appGalleryUrl: 'https://appgallery.huawei.com/app/detail?id=com.dlzz.ebookparser&channelId=SHARE&source=appshare'
    },
    {
      name: 'NGF Coder',
      icon: $r('app.media.ngfcoder_icon'),
      description: '移动端AI编程协作工具',
      appGalleryUrl: 'https://appgallery.huawei.com/app/detail?id=com.dlzz.coder&channelId=SHARE&source=appshare'
    },
    {
      name: '神秘APP',
      description: '敬请期待'
    }
  ];

  aboutToAppear(): void {
    void this.initializePage();
  }

  onPageShow(): void {
    try {
      const stack = AppStorage.get<NavPathStack>('GlobalNavStack');
      if (stack) {
        this.pathStack = stack;
      }
    } catch (err) {
      logger.error(TAG, 'AppStorage.get 异常', String(err));
    }
  }

  private async initializePage(): Promise<void> {
    if (!this.pageInitialized) {
      ThemeAwareHelper.initializeThemeAware(this.componentId, this.themeState, (newTheme: ThemeType) => {
        logger.info(TAG, `主题切换到: ${newTheme}`);
      });
      FontAwareHelper.initializeFontAware(this.componentId, this.fontState, (newState: FontAwareState) => {
        this.fontState = newState;
      });
      this.initializeResponsiveLayout();
      this.pageInitialized = true;
    }
  }

  private lifecycle = new PageLifecycleManager('DeveloperAppsPage', { enableDebug: true });

  aboutToDisappear(): void {
    this.lifecycle.destroy();
    ThemeAwareHelper.cleanupThemeAware(this.componentId);
    FontAwareHelper.cleanupFontAware(this.componentId);
    if (this.deviceChangeListener) {
      this.deviceManager.removeListener(this.deviceChangeListener);
      this.deviceChangeListener = null;
    }
  }

  private initializeResponsiveLayout(): void {
    try {
      this.updateResponsiveParams();
      this.deviceChangeListener = (deviceInfo: DeviceInfo) => {
        this.updateResponsiveParams();
      };
      this.deviceManager.addListener(this.deviceChangeListener);
    } catch (error) {
      logger.error(TAG, '响应式布局初始化失败', String(error));
    }
  }

  private updateResponsiveParams(): void {
    const layoutParams = ResponsiveLayoutHelper.getLayoutParams();
    const deviceInfo = this.deviceManager.getDeviceInfo();
    this.responsive_contentPadding = layoutParams.contentPadding;
    this.responsive_isLandscape = deviceInfo.isLandscape;
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

  // ==================== 打开应用商店 ====================

  private async openAppGallery(app: DeveloperApp): Promise<void> {
    try {
      const context = (this.getUIContext().getHostContext() as common.UIAbilityContext) as common.UIAbilityContext;
      await context.openLink(app.appGalleryUrl, { appLinkingOnly: false });
    } catch (error) {
      logger.error(TAG, '打开应用商店失败', String(error));
      this.getUIContext().getPromptAction().showToast({ message: '无法打开应用商店，请重试' });
    }
  }

  // ==================== UI ====================

  @Builder
  buildAppCard(app: DeveloperApp) {
    Column({ space: 0 }) {
      Row({ space: 16 }) {
        if (app.icon) {
          Image(app.icon)
            .width(64)
            .height(64)
            .borderRadius(14)
        }

        Column({ space: 6 }) {
          Text(app.name)
            .fontSize(18)
            .fontWeight(FontWeight.Bold)
            .fontFamily(this.appFontFamily)
            .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_primary', this.themeState.currentTheme))

          Text(app.description)
            .fontSize(13)
            .fontFamily(this.appFontFamily)
            .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_secondary', this.themeState.currentTheme))
            .maxLines(2)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
        }
        .layoutWeight(1)
        .alignItems(HorizontalAlign.Start)
      }
      .width('100%')
      .padding({ left: 16, right: 16, top: 20, bottom: 16 })

      if (app.appGalleryUrl) {
        Divider()
          .strokeWidth(1)
          .color(ThemeAwareHelper.getTestManagementThemedColor('panel_border', this.themeState.currentTheme))
          .margin({ left: 16, right: 16 })

        Row() {
          Text('在应用市场查看')
            .fontSize(16)
            .fontFamily(this.appFontFamily)
            .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_primary', this.themeState.currentTheme))
            .layoutWeight(1)

          SymbolGlyph($r('sys.symbol.arrow_right'))
            .fontSize(20)
            .fontColor([ThemeAwareHelper.getTestManagementThemedColor('text_muted', this.themeState.currentTheme)])
        }
        .width('100%')
        .height(56)
        .padding({ left: 16, right: 16 })
        .onClick(() => {
          void this.openAppGallery(app);
        })
      }
    }
    .width('100%')
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
    .margin({ left: 16, right: 16, bottom: 16 })
  }

  @Builder
  buildAppList() {
    Column({ space: 0 }) {
      ForEach(this.developerApps, (app: DeveloperApp) => {
        this.buildAppCard(app)
      })
    }
    .width('100%')
  }

  @Builder
  buildFooter() {
    Column({ space: 8 }) {
      Text('更多应用正在开发中，敬请期待')
        .fontSize(13)
        .fontFamily(this.appFontFamily)
        .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_muted', this.themeState.currentTheme))
        .opacity(0.6)
    }
    .width('100%')
    .padding({ top: 24, bottom: 32 })
    .justifyContent(FlexAlign.Center)
    .alignItems(HorizontalAlign.Center)
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
          Column() {
            Blank().height(SettingsPageTitleBarManager.getContentTopPadding(this.statusBarHeight))

            this.buildAppList()
            this.buildFooter()

            Blank().height(24 + this.navigationBarHeight)
          }
          .width('100%')
          .constraintSize({ maxWidth: this.responsive_maxContentWidth })
        }
        .width('100%')
        .height('100%')
        .align(Alignment.TopStart)
        .padding({
          left: this.responsive_contentPadding,
          right: this.responsive_contentPadding
        })
        .edgeEffect(EdgeEffect.Spring)
        .scrollBar(BarState.Auto)
        .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.TOP, SafeAreaEdge.BOTTOM])

        SettingsImmersiveTitleBar({
          themeState: this.themeState,
          title: '同开发者APP',
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
      this.onPageShow();
      void this.initializePage();
    })
    .backgroundColor(Color.Transparent)
  }
}

export { DeveloperAppsPage }
