// 文件路径: entry/src/main/ets/pages/AboutPage.ets
/**
 * 关于应用页面
 * 显示应用版本、开发者信息、开源许可等内容
 */

import { HdsNavDestination, HdsNavDestinationAttribute, ScrollEffectType } from '@kit.UIDesignKit';
import { LengthMetrics } from '@kit.ArkUI';
import { ThemeAwareState, ThemeAwareHelper } from '../Framework/Components/ThemeAware';
import { ThemeManager, ThemeType } from '../Framework/Managers/ThemeManager';
import { FontAwareHelper, FontAwareState } from '../Framework/Components/FontAware';
import { logger } from '../Utils/Logger';
import { PageLifecycleManager } from '../Framework/Lifecycle';
import { DeviceAdaptationManager, DeviceInfo, DeviceChangeListener, Breakpoint } from '../Framework/Managers/DeviceAdaptationManager';
import { ResponsiveLayoutHelper } from '../Framework/Utils/ResponsiveLayout';
import { AppInfoManager } from '../Framework/Managers/AppInfoManager';
import { pasteboard } from '@kit.BasicServicesKit';
import { promptAction } from '@kit.ArkUI';
import { common } from '@kit.AbilityKit';
import { getChangelogManager } from '../Framework/Managers/ChangelogManager';
import { SettingsImmersiveTitleBar } from './settings/SettingsImmersiveTitleBar';
import { SettingsPageTitleBarManager } from './settings/SettingsPageTitleBarManager';
import { GlobalBackgroundLayerMode } from '../Framework/Components/GlobalBackgroundLayer';
import { SharedPageBackgroundLayer } from '../Framework/Components/SharedPageBackgroundLayer';
import { SettingsPanelSurfaceHelper } from './settings/SettingsPanelSurfaceHelper';

const TAG = 'AboutPage';
const TITLE_BAR_HEIGHT_MINI: number = 56;
const APP_TEST_INVITE_URL = 'https://appgallery.huawei.com/apptest/4PlqU4ygat3';
const APP_GALLERY_INVITE_URL = 'https://appgallery.huawei.com/apptest/join/47992ff53f9dcf81a861afea3fcb827c?invitationCode=8vTXct0EstJ';

interface InviteTestLinkOption {
  label: string;
  url: string;
}

@CustomDialog
struct InviteTestEntryDialog {
  controller?: CustomDialogController;
  @Prop themeState: ThemeAwareState;
  @StorageLink('appFontFamily') appFontFamily: string = 'HarmonyOS Sans';
  onSelectAppTest: () => void = () => {};
  onSelectAppGallery: () => void = () => {};
  onRequestClose: () => void = () => {};
  onCancel: () => void = () => {};

  private handleSelect(action: () => void): void {
    this.onRequestClose();
    action();
  }

  build() {
    Column({ space: 14 }) {
      Text('选择邀测入口')
        .fontSize(18)
        .fontWeight(FontWeight.Bold)
        .fontFamily(this.appFontFamily)
        .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_primary', this.themeState.currentTheme))
        .width('100%')
        .textAlign(TextAlign.Start)

      Text('请选择要打开的邀测版本入口')
        .fontSize(13)
        .fontFamily(this.appFontFamily)
        .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_secondary', this.themeState.currentTheme))
        .width('100%')
        .textAlign(TextAlign.Start)

      Column({ space: 10 }) {
        Row({ space: 12 }) {
          Image($r('app.media.ic_sync_normal'))
            .width(22)
            .height(22)

          Column({ space: 2 }) {
            Text('AppTest邀请')
              .fontSize(15)
              .fontWeight(FontWeight.Medium)
              .fontFamily(this.appFontFamily)
              .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_primary', this.themeState.currentTheme))

            Text('需要先安装 AppTest')
              .fontSize(12)
              .fontFamily(this.appFontFamily)
              .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_muted', this.themeState.currentTheme))
          }
          .layoutWeight(1)
          .alignItems(HorizontalAlign.Start)

          SymbolGlyph($r('sys.symbol.arrow_right'))
            .fontSize(16)
            .fontColor([ThemeAwareHelper.getTestManagementThemedColor('text_muted', this.themeState.currentTheme)])
        }
        .width('100%')
        .padding({ left: 14, right: 14, top: 14, bottom: 14 })
        .backgroundColor(ThemeAwareHelper.getTestManagementThemedColor('comp_background_secondary', this.themeState.currentTheme))
        .borderRadius(14)
        .border({
          width: 1,
          color: ThemeAwareHelper.getTestManagementThemedColor('panel_border', this.themeState.currentTheme)
        })
        .onClick(() => {
          this.handleSelect(this.onSelectAppTest);
        })

        Row({ space: 12 }) {
          Image($r('app.media.ic_system_normal'))
            .width(22)
            .height(22)

          Column({ space: 2 }) {
            Text('应用市场邀请')
              .fontSize(15)
              .fontWeight(FontWeight.Medium)
              .fontFamily(this.appFontFamily)
              .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_primary', this.themeState.currentTheme))

            Text('跳转到应用市场邀测页')
              .fontSize(12)
              .fontFamily(this.appFontFamily)
              .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_muted', this.themeState.currentTheme))
          }
          .layoutWeight(1)
          .alignItems(HorizontalAlign.Start)

          SymbolGlyph($r('sys.symbol.arrow_right'))
            .fontSize(16)
            .fontColor([ThemeAwareHelper.getTestManagementThemedColor('text_muted', this.themeState.currentTheme)])
        }
        .width('100%')
        .padding({ left: 14, right: 14, top: 14, bottom: 14 })
        .backgroundColor(ThemeAwareHelper.getTestManagementThemedColor('comp_background_tertiary', this.themeState.currentTheme))
        .borderRadius(14)
        .border({
          width: 1,
          color: ThemeAwareHelper.getTestManagementThemedColor('panel_border', this.themeState.currentTheme)
        })
        .onClick(() => {
          this.handleSelect(this.onSelectAppGallery);
        })
      }
      .width('100%')

      Button('取消')
        .width('100%')
        .height(42)
        .fontSize(14)
        .fontWeight(FontWeight.Medium)
        .fontFamily(this.appFontFamily)
        .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_primary', this.themeState.currentTheme))
        .backgroundColor(ThemeAwareHelper.getTestManagementThemedColor('button_inactive', this.themeState.currentTheme))
        .borderRadius(12)
        .onClick(() => {
          this.onRequestClose();
          this.onCancel();
        })
    }
    .width('86%')
    .constraintSize({ maxWidth: 420 })
    .padding({ left: 18, right: 18, top: 18, bottom: 18 })
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
  }
}

// 使用NavDestinationContext官方类型
// @kit.ArkUI提供的NavDestinationContext已包含必要的类型定义

@Component
struct AboutPage {
  @State pathStack: NavPathStack = new NavPathStack();
  @StorageProp('statusBarHeight') statusBarHeight: number = 0;
  @StorageProp('navigationBarHeight') navigationBarHeight: number = 0;
  private scroller: Scroller = new Scroller();

  // 主题相关状态
  @State themeState: ThemeAwareState = new ThemeAwareState();
  private themeManager: ThemeManager = ThemeManager.getInstance();
  private componentId: string = 'AboutPage';
  
  // 字体相关状态
  @State fontState: FontAwareState = new FontAwareState();
  @StorageLink('appFontFamily') appFontFamily: string = 'HarmonyOS Sans';
  private appInfoManager: AppInfoManager = AppInfoManager.getInstance();

  // 响应式布局相关状态
  private deviceManager: DeviceAdaptationManager = DeviceAdaptationManager.getInstance();
  private deviceChangeListener: DeviceChangeListener | null = null;
  private inviteTestDialogController: CustomDialogController | null = null;
  @State responsive_contentPadding: number = 16;
  @State responsive_maxContentWidth: number = 1200;
  @State responsive_isLandscape: boolean = false;
  private pageInitialized: boolean = false;
  private appInfoLoading: boolean = false;

  @State private appName: string = '漫匣';
  @State private appVersion: string = '';
  @State private buildNumber: string = '';
  private developer: string = '周龙溢';
  private description: string = '一款基于HarmonyOS Next的现代化漫画阅读应用';

  aboutToAppear(): void {
    void this.initializePage();
  }

  onPageShow(): void {
    try {
      const stack = AppStorage.get<NavPathStack>('GlobalNavStack');
      if (stack) {
        this.pathStack = stack;
        logger.debug(TAG, '✅ 成功获取GlobalNavStack');
      }
    } catch (err) {
      logger.error(TAG, 'AppStorage.get 异常', String(err));
    }
    if (this.appVersion.length === 0 || this.buildNumber.length === 0) {
      void this.loadAppInfo();
    }
  }

  private async initializePage(): Promise<void> {
    if (!this.pageInitialized) {
      ThemeAwareHelper.initializeThemeAware(this.componentId, this.themeState, (newTheme: ThemeType) => {
        logger.info(TAG, `主题切换到: ${newTheme}`);
      });

      // 初始化字体感知
      FontAwareHelper.initializeFontAware(
        this.componentId,
        this.fontState,
        (newState: FontAwareState) => {
          this.fontState = newState;
        }
      );

      // 初始化响应式布局
      this.initializeResponsiveLayout();
      this.pageInitialized = true;
    }
    await this.loadAppInfo();
  }

  private lifecycle = new PageLifecycleManager('AboutPage', { enableDebug: true });

  aboutToDisappear(): void {
    this.lifecycle.destroy();
    ThemeAwareHelper.cleanupThemeAware(this.componentId);
    FontAwareHelper.cleanupFontAware(this.componentId);
    
    // 移除设备变化监听器
    if (this.deviceChangeListener) {
      this.deviceManager.removeListener(this.deviceChangeListener);
      this.deviceChangeListener = null;
    }
    if (this.inviteTestDialogController) {
      try {
        this.inviteTestDialogController.close();
      } catch (error) {
        logger.warn(TAG, `关闭邀测弹窗失败: ${String(error)}`);
      }
      this.inviteTestDialogController = null;
    }
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
    const layoutParams = ResponsiveLayoutHelper.getLayoutParams();
    const deviceInfo = this.deviceManager.getDeviceInfo();
    
    this.responsive_contentPadding = layoutParams.contentPadding;
    this.responsive_isLandscape = deviceInfo.isLandscape;
    
    // 根据断点设置内容最大宽度
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
    
    logger.debug(TAG, `响应式参数更新: 内边距=${this.responsive_contentPadding}, 最大宽度=${this.responsive_maxContentWidth}`);
  }

  private async loadAppInfo(): Promise<void> {
    if (this.appInfoLoading) {
      return;
    }
    this.appInfoLoading = true;
    try {
      const label: string = await this.appInfoManager.getLabel();
      const bundleName: string = await this.appInfoManager.getBundleName();
      const versionName: string = await this.appInfoManager.getVersionName();
      const versionCode: number = await this.appInfoManager.getVersionCode();
      this.appName = (label && label.length > 0) ? label : bundleName;
      this.appVersion = versionName;
      this.buildNumber = String(versionCode);
      logger.info(TAG, '应用信息已加载');
    } catch (error) {
      const e = error as Error;
      logger.error(TAG, '加载应用信息失败', e.message);
    } finally {
      this.appInfoLoading = false;
    }
  }

  private getDisplayAppName(): string {
    return this.appName.length > 0 ? this.appName : '漫匣';
  }

  private getDisplayAppVersion(): string {
    return this.appVersion.length > 0 ? this.appVersion : '--';
  }

  private getDisplayBuildNumber(): string {
    return this.buildNumber.length > 0 ? this.buildNumber : '--';
  }

  private goBack(): void {
    try {
      this.pathStack.pop();
    } catch (error) {
      logger.error(TAG, '返回失败', String(error));
    }
  }

  /**
   * 构建应用Logo和标题
   */
  @Builder
  buildAppHeader() {
    Column({ space: 16 }) {
      Image($r('app.media.icon'))
        .width(100)
        .height(100)
        .borderRadius(20)

      Text('漫匣')
        .fontSize(28)
        .fontWeight(FontWeight.Bold)
        .fontFamily(this.appFontFamily)
        .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_primary', this.themeState.currentTheme))

      Text(`版本 ${this.getDisplayAppVersion()} (${this.getDisplayBuildNumber()})`)
        .fontSize(14)
        .fontFamily(this.appFontFamily)
        .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_secondary', this.themeState.currentTheme))

      Text(this.description)
        .fontSize(14)
        .fontFamily(this.appFontFamily)
        .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_muted', this.themeState.currentTheme))
        .textAlign(TextAlign.Center)
        .maxLines(2)
        .width('80%')
    }
    .width('100%')
    .padding({ left: 24, right: 24, top: 32, bottom: 32 })
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

  /**
   * 构建信息项
   */
  @Builder
  buildInfoItem(label: string, value: string, showDivider: boolean = true) {
    Column() {
      Row() {
        Text(label)
          .fontSize(16)
          .fontFamily(this.appFontFamily)
          .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_secondary', this.themeState.currentTheme))
          .layoutWeight(1)

        Text(value)
          .fontSize(16)
          .fontFamily(this.appFontFamily)
          .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_primary', this.themeState.currentTheme))
          .textAlign(TextAlign.End)
      }
      .width('100%')
      .padding({ left: 16, right: 16, top: 16, bottom: 16 })

      if (showDivider) {
        Divider()
          .strokeWidth(1)
          .color(ThemeAwareHelper.getTestManagementThemedColor('panel_border', this.themeState.currentTheme))
      }
    }
  }

  /**
   * 构建应用信息区域
   */
  @Builder
  buildAppInfo() {
    Column() {
      this.buildInfoItem('应用包名', this.getDisplayAppName())
      this.buildInfoItem('版本号', this.getDisplayAppVersion())
      this.buildInfoItem('构建号', this.getDisplayBuildNumber())
      this.buildInfoItem('开发者', this.developer, false)
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

  /**
   * 构建按钮项
   */
  @Builder
  buildButtonItem(title: string, onClick: () => void) {
    Row() {
      Text(title)
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
    .margin({ left: 16, right: 16, bottom: 12 })
    .onClick(onClick)
  }

  /**
   * 打开邀测链接
   */
  private async openInviteTestLink(option: InviteTestLinkOption): Promise<void> {
    try {
      const hostContext = this.getUIContext()?.getHostContext();
      const context = hostContext as common.UIAbilityContext | null;
      if (!context) {
        throw new Error('无法获取页面上下文');
      }
      await context.openLink(option.url, { appLinkingOnly: false });
      logger.info(TAG, `已打开邀测链接: ${option.label}`);
    } catch (error) {
      logger.error(TAG, `打开邀测链接失败: ${option.label}`, String(error));
      this.getUIContext().getPromptAction().showToast({
        message: `无法打开浏览器，请手动访问${option.label}`,
        duration: 3000
      });
    }
  }

  /**
   * 关闭邀测版本入口选择框
   */
  private closeInviteTestDialog(): void {
    if (this.inviteTestDialogController) {
      try {
        this.inviteTestDialogController.close();
      } catch (error) {
        logger.warn(TAG, `关闭邀测弹窗失败: ${String(error)}`);
      }
      this.inviteTestDialogController = null;
    }
  }

  /**
   * 显示邀测版本入口选择框
   */
  private showInviteTestActionMenu(): void {
    this.closeInviteTestDialog();

    const controller = new CustomDialogController({
      builder: InviteTestEntryDialog({
        themeState: this.themeState,
        onSelectAppTest: () => {
          void this.openInviteTestLink({
            label: 'AppTest邀请',
            url: APP_TEST_INVITE_URL
          });
        },
        onSelectAppGallery: () => {
          void this.openInviteTestLink({
            label: '应用市场邀请',
            url: APP_GALLERY_INVITE_URL
          });
        },
        onRequestClose: () => {
          this.closeInviteTestDialog();
        },
        onCancel: () => {
          logger.debug(TAG, '邀测入口选择已取消或关闭');
        }
      }),
      alignment: DialogAlignment.Center,
      autoCancel: true,
      cancel: () => {
        logger.debug(TAG, '邀测入口选择已取消或关闭');
        this.inviteTestDialogController = null;
      },
      customStyle: true
    });
    this.inviteTestDialogController = controller;
    controller.open();
  }

  /**
   * 复制QQ群号并尝试打开QQ
   */
  private async copyQQGroupAndOpen(): Promise<void> {
    const qqGroupNumber = '1067738499';
    
    try {
      // 复制群号到剪贴板
      const pasteboardData = pasteboard.createData(pasteboard.MIMETYPE_TEXT_PLAIN, qqGroupNumber);
      const systemPasteboard = pasteboard.getSystemPasteboard();
      await systemPasteboard.setData(pasteboardData);
      
      logger.info(TAG, `QQ群号已复制: ${qqGroupNumber}`);
      
      // 尝试打开QQ群页面
      try {
        const hostContext = this.getUIContext()?.getHostContext();
        const context = hostContext as common.UIAbilityContext | null;
        if (!context) {
          throw new Error('无法获取页面上下文');
        }
        // 使用QQ群卡片scheme - 直接打开群资料页
        const qqGroupUrl = `mqqapi://card/show_pslcard?src_type=internal&version=1&card_type=group&uin=${qqGroupNumber}`;
        
        await context.openLink(qqGroupUrl, { appLinkingOnly: false });
        logger.info(TAG, '已尝试打开QQ群页面');
        
        this.getUIContext().getPromptAction().showToast({
          message: '正在打开QQ群页面...',
          duration: 2000
        });
      } catch (openError) {
        // 如果无法打开QQ，只显示复制成功的提示
        logger.warn(TAG, '无法打开QQ应用，仅复制群号', String(openError));
        this.getUIContext().getPromptAction().showToast({
          message: `QQ群号 ${qqGroupNumber} 已复制，请在QQ中搜索加群`,
          duration: 3000
        });
      }
      
    } catch (error) {
      logger.error(TAG, '复制QQ群号失败', String(error));
      this.getUIContext().getPromptAction().showToast({
        message: '复制失败，请手动添加QQ群：1067738499',
        duration: 3000
      });
    }
  }

  /**
   * 构建功能按钮组
   */
  @Builder
  buildActionButtons() {
    Column({ space: 0 }) {
      this.buildButtonItem('更新日志', () => {
        logger.info(TAG, '查看更新日志');
        getChangelogManager().forceShowChangelog();
      })

      this.buildButtonItem('邀测版本', () => {
        logger.info(TAG, '显示邀测版本入口选择框');
        this.showInviteTestActionMenu();
      })

      this.buildButtonItem('版本记录', () => {
        try {
          logger.info(TAG, '导航到版本记录页面');
          this.pathStack.pushPath({ name: 'VersionHistoryPage' });
        } catch (error) {
          logger.error(TAG, '导航到版本记录页面失败', String(error));
        }
      })

      this.buildButtonItem('问题反馈', () => {
        logger.info(TAG, '问题反馈');
        this.copyQQGroupAndOpen();
      })

      this.buildButtonItem('用户协议', () => {
        try {
          logger.info(TAG, '导航到用户协议页面');
          this.pathStack.pushPath({ name: 'UserAgreementPage' });
        } catch (error) {
          logger.error(TAG, '导航到用户协议页面失败', String(error));
        }
      })

      this.buildButtonItem('隐私政策', () => {
        try {
          logger.info(TAG, '导航到隐私政策页面');
          this.pathStack.pushPath({ name: 'PrivacyPolicyPage' });
        } catch (error) {
          logger.error(TAG, '导航到隐私政策页面失败', String(error));
        }
      })

      this.buildButtonItem('开源许可', () => {
        try {
          logger.info(TAG, '导航到开源许可页面');
          this.pathStack.pushPath({ name: 'OpenSourceLicensePage' });
        } catch (error) {
          logger.error(TAG, '导航到开源许可页面失败', String(error));
        }
      })

      this.buildButtonItem('支持本项目', () => {
        try {
          logger.info(TAG, '导航到支持本项目页面');
          this.pathStack.pushPath({ name: 'SupportProjectPage' });
        } catch (error) {
          logger.error(TAG, '导航到支持本项目页面失败', String(error));
        }
      })

      this.buildButtonItem('支持者鸣谢', () => {
        try {
          logger.info(TAG, '导航到支持者鸣谢页面');
          this.pathStack.pushPath({ name: 'SupportersPage' });
        } catch (error) {
          logger.error(TAG, '导航到支持者鸣谢页面失败', String(error));
        }
      })

      this.buildButtonItem('同开发者APP', () => {
        try {
          logger.info(TAG, '导航到同开发者页面');
          this.pathStack.pushPath({ name: 'DeveloperAppsPage' });
        } catch (error) {
          logger.error(TAG, '导航到同开发者页面失败', String(error));
        }
      })
    }
    .width('100%')
  }

  /**
   * 构建版权声明
   */
  @Builder
  buildCopyright() {
    Column({ space: 8 }) {
      Text('© 2025 DaLongZhuaZi')
        .fontSize(12)
        .fontFamily(this.appFontFamily)
        .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_muted', this.themeState.currentTheme))
        .opacity(0.6)

      Text('基于 HarmonyOS Next API 23 构建')
        .fontSize(12)
        .fontFamily(this.appFontFamily)
        .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_muted', this.themeState.currentTheme))
        .opacity(0.6)

      Text('Made with ❤️ in China')
        .fontSize(12)
        .fontFamily(this.appFontFamily)
        .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_muted', this.themeState.currentTheme))
        .opacity(0.6)
    }
    .width('100%')
    .padding({ top: 32, bottom: 32 })
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

        if (this.responsive_isLandscape) {
          // 横屏布局：左边40%显示应用信息，右边60%显示选项和版权
          Row() {
            // 左侧：应用图标、名称、版本等基础信息（添加滚动支持）
            Scroll() {
              Column() {
                Blank().height(SettingsPageTitleBarManager.getContentTopPadding(this.statusBarHeight))
                this.buildAppHeader()
                this.buildAppInfo()
                Blank().height(24 + this.navigationBarHeight)
              }
              .width('100%')
            }
            .width('40%')
            .height('100%')
            .padding({ left: this.responsive_contentPadding, right: 8 })
            .edgeEffect(EdgeEffect.Spring)
            .scrollBar(BarState.Auto)
            .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.TOP, SafeAreaEdge.BOTTOM])
            
            // 右侧：操作按钮和版权信息
            Scroll(this.scroller) {
              Column() {
                Blank().height(SettingsPageTitleBarManager.getContentTopPadding(this.statusBarHeight))
                this.buildActionButtons()
                this.buildCopyright()
                Blank().height(24 + this.navigationBarHeight)
              }
              .width('100%')
            }
            .width('60%')
            .height('100%')
            .padding({ left: 8, right: this.responsive_contentPadding })
            .edgeEffect(EdgeEffect.Spring)
            .scrollBar(BarState.Auto)
            .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.TOP, SafeAreaEdge.BOTTOM])
          }
          .width('100%')
          .height('100%')
          .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.TOP, SafeAreaEdge.BOTTOM])
        } else {
          // 竖屏布局：原有布局
          Scroll(this.scroller) {
            Column() {
              Blank().height(SettingsPageTitleBarManager.getContentTopPadding(this.statusBarHeight))
              
              this.buildAppHeader()
              this.buildAppInfo()
              this.buildActionButtons()
              this.buildCopyright()
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
        }
        SettingsImmersiveTitleBar({
          themeState: this.themeState,
          title: '关于',
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

export { AboutPage }
