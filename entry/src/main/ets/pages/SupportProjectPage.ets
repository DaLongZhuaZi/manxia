// 文件路径: entry/src/main/ets/pages/SupportProjectPage.ets
/**
 * 支持本项目页面
 * 展示赞赏二维码和赞助链接，支持保存二维码到相册
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
import { pasteboard } from '@kit.BasicServicesKit';
import { common } from '@kit.AbilityKit';
import { photoAccessHelper } from '@kit.MediaLibraryKit';
import { fileIo as fs, fileUri } from '@kit.CoreFileKit';
import { SettingsImmersiveTitleBar } from './settings/SettingsImmersiveTitleBar';
import { SettingsPageTitleBarManager } from 'manxia_features_ui/src/main/ets/pages/settings/SettingsPageTitleBarManager';
import { GlobalBackgroundLayerMode } from 'manxia_theme/src/main/ets/Framework/Components/GlobalBackgroundLayer';
import { SharedPageBackgroundLayer } from '../Framework/Components/SharedPageBackgroundLayer';
import { SettingsPanelSurfaceHelper } from 'manxia_features_ui/src/main/ets/pages/settings/SettingsPanelSurfaceHelper';

const TAG = 'SupportProjectPage';

@Component
struct SupportProjectPage {
  @State pathStack: NavPathStack = new NavPathStack();
  @StorageProp('statusBarHeight') statusBarHeight: number = 0;
  @StorageProp('navigationBarHeight') navigationBarHeight: number = 0;
  private scroller: Scroller = new Scroller();

  @State themeState: ThemeAwareState = new ThemeAwareState();
  private themeManager: ThemeManager = ThemeManager.getInstance();
  private componentId: string = 'SupportProjectPage';

  @State fontState: FontAwareState = new FontAwareState();
  @StorageLink('appFontFamily') appFontFamily: string = 'HarmonyOS Sans';

  private deviceManager: DeviceAdaptationManager = DeviceAdaptationManager.getInstance();
  private deviceChangeListener: DeviceChangeListener | null = null;
  @State responsive_contentPadding: number = 16;
  @State responsive_maxContentWidth: number = 1200;
  @State responsive_isLandscape: boolean = false;
  private pageInitialized: boolean = false;

  @State private isSavingQrcode: boolean = false;

  private readonly afdianUrl: string = 'https://afdian.com/a/dalongzz';

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

  private lifecycle = new PageLifecycleManager('SupportProjectPage', { enableDebug: true });

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

  // ==================== 保存二维码到相册 ====================

  private async saveQrcodeToAlbum(): Promise<void> {
    if (this.isSavingQrcode) {
      return;
    }
    this.isSavingQrcode = true;
    try {
      const context = (this.getUIContext().getHostContext() as common.UIAbilityContext) as common.UIAbilityContext;
      const resourceMgr = context.resourceManager;
      const qrcodeResource = $r('app.media.mm_reward_qrcode');
      const rawFile: Uint8Array = await resourceMgr.getMediaContent(qrcodeResource.id);

      // 写入临时文件
      const tempPath: string = `${context.cacheDir}/mm_reward_qrcode.webp`;
      const tempFile = await fs.open(tempPath, fs.OpenMode.CREATE | fs.OpenMode.WRITE_ONLY);
      await fs.write(tempFile.fd, rawFile.buffer);
      await fs.close(tempFile);

      // 转换为沙箱URI
      const sandboxUri: string = fileUri.getUriFromPath(tempPath);
      const phAccessHelper = photoAccessHelper.getPhotoAccessHelper(context);
      const srcFileUris: Array<string> = [sandboxUri];
      const photoCreationConfigs: Array<photoAccessHelper.PhotoCreationConfig> = [{
        title: 'mm_reward_qrcode',
        fileNameExtension: 'webp',
        photoType: photoAccessHelper.PhotoType.IMAGE,
        subtype: photoAccessHelper.PhotoSubtype.DEFAULT
      }];
      const desFileUris: Array<string> = await phAccessHelper.showAssetsCreationDialog(srcFileUris, photoCreationConfigs);
      if (desFileUris.length > 0) {
        const srcFile = await fs.open(sandboxUri, fs.OpenMode.READ_ONLY);
        const destFile = await fs.open(desFileUris[0], fs.OpenMode.WRITE_ONLY);
        await fs.copyFile(srcFile.fd, destFile.fd);
        await fs.close(srcFile);
        await fs.close(destFile);
        this.getUIContext().getPromptAction().showToast({ message: '二维码已保存到相册' });
        logger.info(TAG, '二维码已保存到相册');
      }
    } catch (error) {
      const e = error as Error;
      if (e.message && e.message.indexOf('cancel') >= 0) {
        logger.info(TAG, '用户取消保存');
      } else {
        logger.error(TAG, '保存二维码失败', String(error));
        this.getUIContext().getPromptAction().showToast({ message: '保存失败，请重试' });
      }
    } finally {
      this.isSavingQrcode = false;
    }
  }

  // ==================== 打开链接 ====================

  private async openAfdianPage(): Promise<void> {
    try {
      const context = (this.getUIContext().getHostContext() as common.UIAbilityContext) as common.UIAbilityContext;
      await context.openLink(this.afdianUrl, { appLinkingOnly: false });
    } catch (error) {
      logger.error(TAG, '打开爱发电页面失败', String(error));
      this.getUIContext().getPromptAction().showToast({ message: '无法打开浏览器，请手动访问 afdian.com/a/dalongzz', duration: 3000 });
    }
  }

  private async copyLink(): Promise<void> {
    try {
      const pasteboardData = pasteboard.createData(pasteboard.MIMETYPE_TEXT_PLAIN, this.afdianUrl);
      const systemPasteboard = pasteboard.getSystemPasteboard();
      await systemPasteboard.setData(pasteboardData);
      this.getUIContext().getPromptAction().showToast({ message: '链接已复制' });
    } catch (error) {
      logger.error(TAG, '复制链接失败', String(error));
    }
  }

  // ==================== UI ====================

  @Builder
  buildQrcodeSection() {
    Column({ space: 16 }) {
      Text('扫码赞赏（推荐）')
        .fontSize(18)
        .fontWeight(FontWeight.Bold)
        .fontFamily(this.appFontFamily)
        .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_primary', this.themeState.currentTheme))
        .width('100%')
        .textAlign(TextAlign.Center)

      Image($r('app.media.mm_reward_qrcode'))
        .width(220)
        .height(220)
        .borderRadius(12)
        .backgroundColor(Color.White)
        .padding(8)

      Button(this.isSavingQrcode ? '保存中...' : '保存到相册')
        .width(160)
        .height(40)
        .fontSize(14)
        .fontFamily(this.appFontFamily)
        .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_white', this.themeState.currentTheme))
        .backgroundColor(ThemeAwareHelper.getTestManagementThemedColor('accent_primary', this.themeState.currentTheme))
        .borderRadius(20)
        .enabled(!this.isSavingQrcode)
        .onClick(() => {
          void this.saveQrcodeToAlbum();
        })
    }
    .width('100%')
    .padding({ top: 32, bottom: 32, left: 24, right: 24 })
    .justifyContent(FlexAlign.Center)
    .alignItems(HorizontalAlign.Center)
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
  buildLinkSection() {
    Column({ space: 0 }) {
      Text('通过链接支持')
        .fontSize(18)
        .fontWeight(FontWeight.Bold)
        .fontFamily(this.appFontFamily)
        .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_primary', this.themeState.currentTheme))
        .width('100%')
        .padding({ left: 16, right: 16, top: 20, bottom: 12 })

      Text('通过爱发电平台支持开发者，您的支持是持续更新的动力。')
        .fontSize(14)
        .fontFamily(this.appFontFamily)
        .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_secondary', this.themeState.currentTheme))
        .width('100%')
        .padding({ left: 16, right: 16, bottom: 16 })

      // 链接地址（可复制）
      Row() {
        Text(this.afdianUrl)
          .fontSize(14)
          .fontFamily(this.appFontFamily)
          .fontColor(ThemeAwareHelper.getTestManagementThemedColor('accent_primary', this.themeState.currentTheme))
          .layoutWeight(1)
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })

        SymbolGlyph($r('sys.symbol.doc'))
          .fontSize(18)
          .fontColor([ThemeAwareHelper.getTestManagementThemedColor('text_muted', this.themeState.currentTheme)])
          .onClick(() => {
            void this.copyLink();
          })
      }
      .width('100%')
      .padding({ left: 16, right: 16, top: 8, bottom: 8 })
      .onClick(() => {
        void this.copyLink();
      })

      Divider()
        .strokeWidth(1)
        .color(ThemeAwareHelper.getTestManagementThemedColor('panel_border', this.themeState.currentTheme))
        .margin({ left: 16, right: 16 })

      // 打开按钮
      Row() {
        Text('打开爱发电')
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
        void this.openAfdianPage();
      })
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
  buildFooter() {
    Column({ space: 8 }) {
      Text('感谢每一位支持者的鼓励与陪伴')
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

            this.buildQrcodeSection()
            this.buildLinkSection()
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
          title: '支持本项目',
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

export { SupportProjectPage }
