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

const TAG = 'AboutPage';
const TITLE_BAR_HEIGHT_MINI: number = 56;

// 使用NavDestinationContext官方类型
// @kit.ArkUI提供的NavDestinationContext已包含必要的类型定义

@Component
struct AboutPage {
  @State pathStack: NavPathStack = new NavPathStack();
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
  @State responsive_contentPadding: number = 16;
  @State responsive_maxContentWidth: number = 1200;
  @State responsive_isLandscape: boolean = false;

  @State private appName: string = '';
  @State private appVersion: string = '';
  @State private buildNumber: string = '';
  private developer: string = 'DaLongZhuaZi';
  private description: string = '一款基于HarmonyOS Next的现代化漫画阅读应用';

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
  }

  async onReady(): Promise<void> {
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
    }
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
        .backgroundColor(ThemeAwareHelper.getTestManagementThemedColor('background_secondary', this.themeState.currentTheme))

      Text(this.appName)
        .fontSize(28)
        .fontWeight(FontWeight.Bold)
        .fontFamily(this.appFontFamily)
        .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_primary', this.themeState.currentTheme))

      Text(`版本 ${this.appVersion} (${this.buildNumber})`)
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
    .padding({ top: 40, bottom: 40 })
    .justifyContent(FlexAlign.Center)
    .alignItems(HorizontalAlign.Center)
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
      this.buildInfoItem('应用名称', this.appName)
      this.buildInfoItem('版本号', this.appVersion)
      this.buildInfoItem('构建号', this.buildNumber)
      this.buildInfoItem('开发者', this.developer, false)
    }
    .width('100%')
    .backgroundColor(ThemeAwareHelper.getTestManagementThemedColor('panel_background', this.themeState.currentTheme))
    .borderRadius(12)
    .border({ width: 1, color: ThemeAwareHelper.getTestManagementThemedColor('panel_border', this.themeState.currentTheme) })
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
    .backgroundColor(ThemeAwareHelper.getTestManagementThemedColor('panel_background', this.themeState.currentTheme))
    .borderRadius(12)
    .border({ width: 1, color: ThemeAwareHelper.getTestManagementThemedColor('panel_border', this.themeState.currentTheme) })
    .margin({ left: 16, right: 16, bottom: 12 })
    .onClick(onClick)
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
        const context = getContext(this) as common.UIAbilityContext;
        // 使用QQ群卡片scheme - 直接打开群资料页
        const qqGroupUrl = `mqqapi://card/show_pslcard?src_type=internal&version=1&card_type=group&uin=${qqGroupNumber}`;
        
        await context.openLink(qqGroupUrl, { appLinkingOnly: false });
        logger.info(TAG, '已尝试打开QQ群页面');
        
        promptAction.showToast({
          message: '正在打开QQ群页面...',
          duration: 2000
        });
      } catch (openError) {
        // 如果无法打开QQ，只显示复制成功的提示
        logger.warn(TAG, '无法打开QQ应用，仅复制群号', String(openError));
        promptAction.showToast({
          message: `QQ群号 ${qqGroupNumber} 已复制，请在QQ中搜索加群`,
          duration: 3000
        });
      }
      
    } catch (error) {
      logger.error(TAG, '复制QQ群号失败', String(error));
      promptAction.showToast({
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

      this.buildButtonItem('检查更新', () => {
        logger.info(TAG, '检查更新');
        // TODO: 实现检查更新功能
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

      Text('基于 HarmonyOS Next API 18 构建')
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
        Column()
          .width('100%')
          .height('100%')
          .backgroundColor(ThemeAwareHelper.getTestManagementThemedColor('background_dark', this.themeState.currentTheme))
          .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.TOP, SafeAreaEdge.BOTTOM])

        if (this.responsive_isLandscape) {
          // 横屏布局：左边40%显示应用信息，右边60%显示选项和版权
          Row() {
            // 左侧：应用图标、名称、版本等基础信息（添加滚动支持）
            Scroll() {
              Column() {
                Blank().height(TITLE_BAR_HEIGHT_MINI)
                this.buildAppHeader()
                this.buildAppInfo()
              }
              .width('100%')
            }
            .width('40%')
            .height('100%')
            .padding({ left: this.responsive_contentPadding, right: 8 })
            .edgeEffect(EdgeEffect.Spring)
            .scrollBar(BarState.Auto)
            
            // 右侧：操作按钮和版权信息
            Scroll(this.scroller) {
              Column() {
                Blank().height(TITLE_BAR_HEIGHT_MINI)
                this.buildActionButtons()
                this.buildCopyright()
              }
              .width('100%')
            }
            .width('60%')
            .height('100%')
            .padding({ left: 8, right: this.responsive_contentPadding })
            .edgeEffect(EdgeEffect.Spring)
            .scrollBar(BarState.Auto)
          }
          .width('100%')
          .height('100%')
        } else {
          // 竖屏布局：原有布局
          Scroll(this.scroller) {
            Column() {
              Blank().height(TITLE_BAR_HEIGHT_MINI)
              
              this.buildAppHeader()
              this.buildAppInfo()
              this.buildActionButtons()
              this.buildCopyright()
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
        }
      }
    }
    .titleBar({
      padding: {
        start: LengthMetrics.vp(16),
        end: LengthMetrics.vp(16)
      },
      style: {
        scrollEffectOpts: {
          enableScrollEffect: true,
          scrollEffectType: ScrollEffectType.COMMON_BLUR,
          blurEffectiveStartOffset: LengthMetrics.vp(0),
          blurEffectiveEndOffset: LengthMetrics.vp(TITLE_BAR_HEIGHT_MINI)
        },
        originalStyle: {
          backgroundStyle: { backgroundColor: Color.Transparent },
          contentStyle: {
            titleStyle: { mainTitleColor: ThemeAwareHelper.getTestManagementThemedColor('text_primary', this.themeState.currentTheme) },
            backIconStyle: { backgroundColor: ThemeAwareHelper.getTestManagementThemedColor('comp_background_tertiary', this.themeState.currentTheme), iconColor: ThemeAwareHelper.getTestManagementThemedColor('icon_primary', this.themeState.currentTheme) }
          }
        },
        scrollEffectStyle: {
          backgroundStyle: {
            backgroundColor: this.themeState.currentTheme === ThemeType.DARK ? '#E61A1A1A' : '#E6F5F5F5'
          },
          contentStyle: {
            titleStyle: { mainTitleColor: ThemeAwareHelper.getTestManagementThemedColor('text_primary', this.themeState.currentTheme) },
            backIconStyle: { backgroundColor: ThemeAwareHelper.getTestManagementThemedColor('comp_background_tertiary', this.themeState.currentTheme), iconColor: ThemeAwareHelper.getTestManagementThemedColor('icon_primary', this.themeState.currentTheme) }
          }
        }
      },
      content: {
        title: { mainTitle: '关于' }
      }
    })
    .onReady((context: NavDestinationContext) => {
      this.pathStack = context.pathStack;
      this.onPageShow();
      this.onReady();
    })
    .backgroundColor(Color.Transparent)
  }
}

export { AboutPage }
