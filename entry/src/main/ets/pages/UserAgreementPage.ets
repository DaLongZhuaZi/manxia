// 文件路径: entry/src/main/ets/pages/UserAgreementPage.ets
// 职责: 用户协议页面
// 最后编辑: 2025-11-29

import { HdsNavDestination, HdsNavDestinationAttribute, ScrollEffectType } from '@kit.UIDesignKit';
import { ThemeAwareState, ThemeAwareHelper } from '../Framework/Components/ThemeAware';
import { ThemeManager, ThemeType } from '../Framework/Managers/ThemeManager';
import { logger } from '../Utils/Logger';

const TAG = 'UserAgreementPage';

/**
 * 用户协议页面
 */
@Component
export struct UserAgreementPage {
  @Consume('NavPathStack') pathStack: NavPathStack;
  
  // 主题状态
  @State themeState: ThemeAwareState = new ThemeAwareState();
  private themeManager: ThemeManager = ThemeManager.getInstance();
  private componentId: string = `UserAgreementPage_${Date.now()}`;

  // 滚动控制器
  private scroller: Scroller = new Scroller();

  aboutToAppear(): void {
    logger.lifecycle(TAG, 'aboutToAppear');
    
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
        Column()
          .width('100%')
          .height('100%')
          .backgroundColor(ThemeAwareHelper.getTestManagementThemedColor('background_primary', this.themeState.currentTheme))
          .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.TOP, SafeAreaEdge.BOTTOM])
        
        Column() {
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
          .width('100%')
          .height(56)
          .padding({ left: 16, right: 16 })

          Scroll(this.scroller) {
            Column() {
              Text('漫匣用户服务协议')
                .fontSize(22)
                .fontWeight(FontWeight.Bold)
                .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_primary', this.themeState.currentTheme))
                .width('100%')
                .margin({ bottom: 8 })

              Text('更新日期：2025年11月29日')
                .fontSize(13)
                .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_muted', this.themeState.currentTheme))
                .width('100%')
                .margin({ bottom: 20 })

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

              Column()
                .height(40)
            }
            .width('100%')
            .padding({ left: 20, right: 20, top: 16, bottom: 20 })
          }
          .layoutWeight(1)
          .scrollBar(BarState.Auto)
          .edgeEffect(EdgeEffect.Spring)
        }
        .width('100%')
        .height('100%')
      }
    }
    .backgroundColor(Color.Transparent)
    .hideTitleBar(true)
  }
}
