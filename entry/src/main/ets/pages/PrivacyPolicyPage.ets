// 文件路径: entry/src/main/ets/pages/PrivacyPolicyPage.ets
// 职责: 隐私政策页面
// 最后编辑: 2025-11-29

import { HdsNavDestination, HdsNavDestinationAttribute, ScrollEffectType } from '@kit.UIDesignKit';
import { ThemeAwareState, ThemeAwareHelper } from 'manxia_theme/src/main/ets/Framework/Components/ThemeAware';
import { ThemeManager, ThemeType } from 'manxia_theme/src/main/ets/Framework/Managers/ThemeManager';
import { logger } from 'manxia_core/src/main/ets/Utils/Logger';
import { DisplayMode } from 'manxia_theme/src/main/ets/Utils/WindowManager';
import { PageWindowCoordinator } from 'manxia_theme/src/main/ets/Utils/PageWindowCoordinator';
import { SettingsImmersiveTitleBar } from './settings/SettingsImmersiveTitleBar';
import { SettingsPageTitleBarManager } from './settings/SettingsPageTitleBarManager';
import { SettingsPanelSurfaceHelper } from './settings/SettingsPanelSurfaceHelper';

const TAG = 'PrivacyPolicyPage';
/**
 * 隐私政策页面
 */
@Component
export struct PrivacyPolicyPage {
  @Consume('NavPathStack') pathStack: NavPathStack;
  @StorageProp('statusBarHeight') statusBarHeight: number = 0;
  @StorageProp('navigationBarHeight') navigationBarHeight: number = 0;
  
  // 主题状态
  @State themeState: ThemeAwareState = new ThemeAwareState();
  private themeManager: ThemeManager = ThemeManager.getInstance();
  private componentId: string = `PrivacyPolicyPage_${Date.now()}`;
  private previousDisplayMode: DisplayMode = DisplayMode.DEFAULT;

  // 滚动控制器
  private scroller: Scroller = new Scroller();

  aboutToAppear(): void {
    logger.lifecycle(TAG, 'aboutToAppear');
    this.previousDisplayMode = PageWindowCoordinator.captureCurrentDisplayMode();
    PageWindowCoordinator.applyPagePolicy('PrivacyPolicyPage', this.getUIContext());
    
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

            Text('隐私政策')
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
                Text('漫匣隐私政策')
                  .fontSize(24)
                  .fontWeight(FontWeight.Bold)
                  .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_primary', this.themeState.currentTheme))
                  .width('100%')

                Text('这里说明漫匣如何处理设备信息、阅读数据与本地文件，以及我们不会收集和上传哪些隐私数据。')
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
                this.buildSectionTitle('一、引言')
                this.buildParagraph('漫匣（以下简称"我们"）非常重视用户的隐私保护。本隐私政策旨在向您说明我们如何收集、使用、存储和保护您的个人信息。')
                this.buildParagraph('请您在使用本应用前仔细阅读本隐私政策。使用本应用即表示您同意本隐私政策的内容。')

                this.buildSectionTitle('二、信息收集')
                this.buildParagraph('我们可能收集以下类型的信息：')
                this.buildParagraph('1. 设备信息：设备型号、操作系统版本等基本设备信息，用于优化应用兼容性。')
                this.buildParagraph('2. 使用数据：阅读偏好、阅读进度等应用使用数据，用于提供个性化服务。')
                this.buildParagraph('3. 本地文件：您主动导入的漫画和电子书文件，仅存储在本地设备。')
                this.buildParagraph('我们不会收集您的姓名、电话号码、身份证号等敏感个人信息。')

                this.buildSectionTitle('三、信息使用')
                this.buildParagraph('我们收集的信息将用于以下目的：')
                this.buildParagraph('• 提供和改进应用功能\n• 保存您的阅读进度和偏好设置\n• 优化应用性能和用户体验\n• 修复bug和技术问题')

                this.buildSectionTitle('四、信息存储')
                this.buildParagraph('您的所有数据均存储在本地设备上，我们不会将您的数据上传到任何服务器。')
                this.buildParagraph('您可以随时通过应用设置清除本地数据，或通过卸载应用删除所有相关数据。')

                this.buildSectionTitle('五、信息共享')
                this.buildParagraph('我们不会与任何第三方共享您的个人信息，除非：')
                this.buildParagraph('• 获得您的明确同意\n• 法律法规要求\n• 保护我们或他人的合法权益')

                this.buildSectionTitle('六、第三方服务')
                this.buildParagraph('本应用可能包含指向第三方网站或服务的链接。这些第三方服务有其独立的隐私政策，我们对其隐私实践不承担责任。')
                this.buildParagraph('当您使用第三方刮削源/图源时，请注意该刮削源/图源可能会收集您的访问信息，如cookie。')

                this.buildSectionTitle('七、儿童隐私')
                this.buildParagraph('本应用不面向18岁以下的未成年群体。如果我们发现收集了儿童的个人信息，将立即删除相关数据。')

                this.buildSectionTitle('八、隐私政策更新')
                this.buildParagraph('我们可能会不时更新本隐私政策。更新后的政策将在应用内公布，请定期查阅。')

                this.buildSectionTitle('九、您的权利')
                this.buildParagraph('您有权：')
                this.buildParagraph('• 访问您的个人数据\n• 更正不准确的数据\n• 删除您的数据\n• 撤回同意')

                this.buildSectionTitle('十、联系我们')
                this.buildParagraph('如果您对本隐私政策有任何疑问或建议，请通过以下方式联系我们：')
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
          title: '隐私政策',
          contentPadding: 20,
          maxContentWidth: 1200
        })
      }
    }
    .backgroundColor(Color.Transparent)
    .hideTitleBar(true)
    .ignoreLayoutSafeArea([LayoutSafeAreaType.SYSTEM], [LayoutSafeAreaEdge.TOP, LayoutSafeAreaEdge.BOTTOM])
    .onWillAppear(() => {
      PageWindowCoordinator.applyPagePolicy('PrivacyPolicyPage', this.getUIContext());
    })
    .onWillShow(() => {
      PageWindowCoordinator.reapplyPagePolicy('PrivacyPolicyPage', this.getUIContext());
    })
  }

  private getPageBackgroundResource(): ResourceStr {
    return $r('app.media.bg2');
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
