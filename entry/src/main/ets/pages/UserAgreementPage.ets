// 文件路径: entry/src/main/ets/pages/UserAgreementPage.ets
// 职责: 用户协议页面
// 最后编辑: 2025-11-29

import { HdsNavDestination, HdsNavDestinationAttribute, ScrollEffectType } from '@kit.UIDesignKit';
import { ThemeAwareState, ThemeAwareHelper } from 'manxia_theme/src/main/ets/Framework/Components/ThemeAware';
import { ThemeManager, ThemeType } from 'manxia_theme/src/main/ets/Framework/Managers/ThemeManager';
import { logger } from 'manxia_core/src/main/ets/Utils/Logger';
import { DisplayMode } from 'manxia_theme/src/main/ets/Utils/WindowManager';
import { PageWindowCoordinator } from 'manxia_theme/src/main/ets/Utils/PageWindowCoordinator';
import { ngfPagePolicyHostFacade } from '../Framework/NGF/uiShell/index';
import { SettingsImmersiveTitleBar } from './settings/SettingsImmersiveTitleBar';
import { SettingsPageTitleBarManager } from 'manxia_features_ui/src/main/ets/pages/settings/SettingsPageTitleBarManager';
import { SettingsPanelSurfaceHelper } from 'manxia_features_ui/src/main/ets/pages/settings/SettingsPanelSurfaceHelper';

const TAG = 'UserAgreementPage';
/**
 * 用户协议页面
 */
@Component
export struct UserAgreementPage {
  @Consume('NavPathStack') pathStack: NavPathStack;
  @StorageProp('statusBarHeight') statusBarHeight: number = 0;
  @StorageProp('navigationBarHeight') navigationBarHeight: number = 0;
  
  // 主题状态
  @State themeState: ThemeAwareState = new ThemeAwareState();
  private themeManager: ThemeManager = ThemeManager.getInstance();
  private componentId: string = `UserAgreementPage_${Date.now()}`;
  private previousDisplayMode: DisplayMode = DisplayMode.DEFAULT;

  // 滚动控制器
  private scroller: Scroller = new Scroller();

  private isNgfUiShellIntegrated(): boolean {
    try {
      return AppStorage.get<boolean>('ngf_ui_shell_integrated') === true;
    } catch (_error) {
      return false;
    }
  }

  private applyPagePolicyWithNgf(pageName: string): void {
    if (this.isNgfUiShellIntegrated()) {
      try {
        ngfPagePolicyHostFacade.applyPolicy(pageName);
        return;
      } catch (error) {
        logger.warn(TAG, `NGF 页面策略应用失败，回退旧链路: ${String(error)}`);
      }
    }
    PageWindowCoordinator.applyPagePolicy(pageName, this.getUIContext());
  }

  private reapplyPagePolicyWithNgf(pageName: string): void {
    if (this.isNgfUiShellIntegrated()) {
      try {
        ngfPagePolicyHostFacade.reapplyPolicy(pageName);
        return;
      } catch (error) {
        logger.warn(TAG, `NGF 页面策略重放失败，回退旧链路: ${String(error)}`);
      }
    }
    PageWindowCoordinator.reapplyPagePolicy(pageName, this.getUIContext());
  }

  aboutToAppear(): void {
    logger.lifecycle(TAG, 'aboutToAppear');
    this.previousDisplayMode = PageWindowCoordinator.captureCurrentDisplayMode();
    this.applyPagePolicyWithNgf('UserAgreementPage');
    
    ThemeAwareHelper.initializeThemeAware(
      this.componentId,
      this.themeState,
      (newTheme: ThemeType) => {
        logger.info(TAG, `主题已切换到: ${newTheme}`);
      },
      (newState: ThemeAwareState) => {
        this.themeState = newState;
      }
    );
  }

  aboutToDisappear(): void {
    logger.lifecycle(TAG, 'aboutToDisappear');
    PageWindowCoordinator.restoreDisplayMode(this.previousDisplayMode, this.getUIContext());
    ThemeAwareHelper.cleanupThemeAware(this.componentId);
  }

  private goBack(): void {
    try {
      this.pathStack.pop();
      logger.info(TAG, '返回上一页');
    } catch (error) {
      logger.error(TAG, `返回失败: ${String(error)}`);
    }
  }

  @Builder
  buildSectionTitle(title: string) {
    Text(title)
      .fontSize(18)
      .fontWeight(FontWeight.Bold)
      .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_primary', this.themeState.currentTheme))
      .width('100%')
      .margin({ top: 20, bottom: 12 })
  }

  @Builder
  buildParagraph(text: string) {
    Text(text)
      .fontSize(15)
      .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_secondary', this.themeState.currentTheme))
      .lineHeight(24)
      .width('100%')
      .margin({ bottom: 12 })
  }

  build() {
    HdsNavDestination() {
      Stack() {
        this.buildPageBackground()
        
        Column() {
          /*
          Row() {
            Button() {
              SymbolGlyph($r('sys.symbol.arrow_left'))
                .fontSize(24)
                .fontColor([ThemeAwareHelper.getTestManagementThemedColor('text_primary', this.themeState.currentTheme)])
            }
            .width(40)
            .height(40)
            .backgroundColor(Color.Transparent)
            .onClick(() => {
              this.goBack();
            })

            Text('用户协议')
              .fontSize(20)
              .fontWeight(FontWeight.Bold)
              .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_primary', this.themeState.currentTheme))
              .layoutWeight(1)
              .textAlign(TextAlign.Center)

            Column()
              .width(40)
              .height(40)
          }
          .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.TOP, SafeAreaEdge.BOTTOM])
          .width('100%')
          .height(56)
          .padding({ left: 16, right: 16 })
          */

          Scroll(this.scroller) {
            Column({ space: 16 }) {
              Blank().height(SettingsPageTitleBarManager.getContentTopPadding(this.statusBarHeight))

              Column({ space: 8 }) {
                Text('漫匣用户服务协议')
                  .fontSize(24)
                  .fontWeight(FontWeight.Bold)
                  .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_primary', this.themeState.currentTheme))
                  .width('100%')

                Text('在使用漫匣前，请先了解本协议中关于服务边界、版权责任与使用规范的约定。')
                  .fontSize(14)
                  .lineHeight(22)
                  .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_secondary', this.themeState.currentTheme))
                  .width('100%')

                Text('更新日期：2025年11月29日')
                  .fontSize(13)
                  .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_muted', this.themeState.currentTheme))
                  .width('100%')
              }
              .width('100%')
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

              Column() {
                this.buildSectionTitle('一、协议的接受')
                this.buildParagraph('欢迎使用漫匣（以下简称"本应用"）。在使用本应用之前，请您仔细阅读本用户服务协议（以下简称"本协议"）。当您下载、安装或使用本应用时，即表示您已阅读、理解并同意接受本协议的全部条款。')
                this.buildParagraph('如果您不同意本协议的任何条款，请勿下载、安装或使用本应用。')

                this.buildSectionTitle('二、服务说明')
                this.buildParagraph('本应用是一款漫画阅读工具，提供以下功能：')
                this.buildParagraph('• 漫画浏览和阅读功能\n• 本地漫画导入和管理\n• 电子书阅读功能\n• 图源管理和配置\n• 阅读进度同步和记录')
                this.buildParagraph('本应用本身不提供任何漫画内容，所有内容均来自用户配置的第三方图源或用户本地导入。')

                this.buildSectionTitle('三、用户行为规范')
                this.buildParagraph('在使用本应用时，您同意：')
                this.buildParagraph('• 遵守中华人民共和国相关法律法规\n• 不使用本应用从事任何违法活动\n• 不侵犯他人的知识产权和其他合法权益\n• 尊重漫画作者和版权方的劳动成果\n• 支持正版漫画，合理使用本应用')

                this.buildSectionTitle('四、知识产权声明')
                this.buildParagraph('本应用的软件代码、界面设计、图标等知识产权归开发者所有。')
                this.buildParagraph('用户通过本应用访问的漫画内容版权归原作者和版权方所有。本应用不对任何第三方内容的版权负责。')
                this.buildParagraph('如果您发现本应用存在侵权内容，请及时与我们联系。')

                this.buildSectionTitle('五、免责声明')
                this.buildParagraph('• 本应用仅作为阅读工具提供服务，不对第三方图源的内容负责\n• 用户使用本应用访问的任何内容均由用户自行承担风险\n• 本应用不保证服务的连续性和稳定性\n• 因不可抗力导致的服务中断，本应用不承担责任')

                this.buildSectionTitle('六、协议修改')
                this.buildParagraph('我们保留随时修改本协议的权利。协议修改后，我们会在应用内通知您。如果您继续使用本应用，即表示您接受修改后的协议。')

                this.buildSectionTitle('七、联系方式')
                this.buildParagraph('如果您对本协议有任何疑问，可以通过以下方式联系我们：')
                this.buildParagraph('• QQ群：1067738499\n• GitHub：github.com/DaLongZhuaZi/manxia')
              }
              .width('100%')
              .padding({ left: 24, right: 24, top: 8, bottom: 24 })
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

              Blank().height(24 + this.navigationBarHeight)
            }
            .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.TOP, SafeAreaEdge.BOTTOM])
            .width('100%')
            .constraintSize({ maxWidth: 960 })
            .padding({ left: 20, right: 20, top: 16, bottom: 20 })
          }
          .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.TOP, SafeAreaEdge.BOTTOM])
          .layoutWeight(1)
          .scrollBar(BarState.Auto)
          .edgeEffect(EdgeEffect.Spring)
        }
        .width('100%')
        .height('100%')
        .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.TOP, SafeAreaEdge.BOTTOM])
        SettingsImmersiveTitleBar({
          themeState: this.themeState,
          title: '用户协议',
          contentPadding: 20,
          maxContentWidth: 1200
        })
      }
    }
    .backgroundColor(Color.Transparent)
    .hideTitleBar(true)
    .ignoreLayoutSafeArea([LayoutSafeAreaType.SYSTEM], [LayoutSafeAreaEdge.TOP, LayoutSafeAreaEdge.BOTTOM])
    .onWillAppear(() => {
      this.applyPagePolicyWithNgf('UserAgreementPage');
    })
    .onWillShow(() => {
      this.reapplyPagePolicyWithNgf('UserAgreementPage');
    })
  }

  private getPageBackgroundResource(): ResourceStr {
    return $r('app.media.bookshelf');
  }

  private getPageBackgroundTint(): string {
    return this.themeState.currentTheme === ThemeType.DARK
      ? 'rgba(7, 10, 16, 0.34)'
      : 'rgba(246, 249, 252, 0.18)';
  }

  private getPageBackgroundScrimColors(): [ResourceColor, number][] {
    if (this.themeState.currentTheme === ThemeType.DARK) {
      return [
        ['rgba(7, 10, 16, 0.08)', 0.0] as [ResourceColor, number],
        ['rgba(7, 10, 16, 0.22)', 0.52] as [ResourceColor, number],
        ['rgba(7, 10, 16, 0.5)', 1.0] as [ResourceColor, number]
      ];
    }
    return [
      ['rgba(255, 255, 255, 0.02)', 0.0] as [ResourceColor, number],
      ['rgba(246, 249, 252, 0.08)', 0.52] as [ResourceColor, number],
      ['rgba(238, 244, 250, 0.22)', 1.0] as [ResourceColor, number]
    ];
  }

  @Builder
  private buildPageBackground() {
    Stack() {
      Image(this.getPageBackgroundResource())
        .width('100%')
        .height('100%')
        .objectFit(ImageFit.Cover)
        .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.TOP, SafeAreaEdge.BOTTOM])

      Column()
        .width('100%')
        .height('100%')
        .backgroundColor(this.getPageBackgroundTint())
        .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.TOP, SafeAreaEdge.BOTTOM])

      Column()
        .width('100%')
        .height('100%')
        .linearGradient({
          direction: GradientDirection.Bottom,
          colors: this.getPageBackgroundScrimColors()
        })
        .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.TOP, SafeAreaEdge.BOTTOM])
    }
    .width('100%')
    .height('100%')
  }
}
