import { HdsNavDestination } from '@kit.UIDesignKit';
import { ThemeAwareState, ThemeAwareHelper } from 'manxia_theme/src/main/ets/Framework/Components/ThemeAware';
import { SettingsImmersiveTitleBar } from './settings/SettingsImmersiveTitleBar';
import { GlobalBackgroundLayerMode } from 'manxia_theme/src/main/ets/Framework/Components/GlobalBackgroundLayer';
import { SharedPageBackgroundLayer } from '../Framework/Components/SharedPageBackgroundLayer';
import { SettingsPanelSurfaceHelper } from 'manxia_features_ui/src/main/ets/pages/settings/SettingsPanelSurfaceHelper';

@Component
struct SupporterAgreementPage {
  @State themeState: ThemeAwareState = new ThemeAwareState();
  @StorageProp('statusBarHeight') statusBarHeight: number = 0;
  @StorageProp('navigationBarHeight') navigationBarHeight: number = 0;
  @StorageLink('appFontFamily') appFontFamily: string = 'HarmonyOS Sans';
  @State pathStack: NavPathStack = new NavPathStack();

  aboutToAppear(): void {
    ThemeAwareHelper.initializeThemeAware('SupporterAgreementPage', this.themeState, () => {});
  }

  aboutToDisappear(): void {
    ThemeAwareHelper.cleanupThemeAware('SupporterAgreementPage');
  }

  build() {
    HdsNavDestination() {
      Stack() {
        SharedPageBackgroundLayer({
          defaultBackgroundColor: ThemeAwareHelper.getTestManagementThemedColor('background_dark', this.themeState.currentTheme),
          mode: GlobalBackgroundLayerMode.IMMERSIVE
        }).width('100%').height('100%').expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.TOP, SafeAreaEdge.BOTTOM]);
        Column() {
          Blank().height(this.statusBarHeight + 72);
          Scroll() {
            Column({ space: 16 }) {
              Text('感谢您愿意支持漫匣的持续开发。支持者计划是一项自愿的项目支持，不是应用内购买，也不会改变阅读内容的获取方式，仅涉及一些APP内的增强功能。')
                .fontSize(16).lineHeight(26).fontFamily(this.appFontFamily)
                .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_secondary', this.themeState.currentTheme));
              Text('更新日期：2026年7月17日')
                .fontSize(13).fontFamily(this.appFontFamily)
                .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_muted', this.themeState.currentTheme));
              Column({ space: 12 }) {
                Text('1. 支持方式').fontSize(18).fontWeight(FontWeight.Bold);
                Text('支持金额为人民币 18 元，建议在微信赞赏时备注您想留下的 ID，便于后续核验与感谢。')
                  .fontSize(15).lineHeight(24);
                Text('2. 权益说明').fontSize(18).fontWeight(FontWeight.Bold);
                Text('支持者可使用漫匣的专属能力。具体能力可能随版本更新调整，项目会尽量保持兼容与稳定。')
                  .fontSize(15).lineHeight(24);
                Text('3. 隐私与记录').fontSize(18).fontWeight(FontWeight.Bold);
                Text('漫匣不会在本地保存任何支付账号、密码或者个人信息。您可以选择诚信激活，激活状态仅用于本机功能展示，不会保存到云端。')
                  .fontSize(15).lineHeight(24);
                Text('4. 退款与争议').fontSize(18).fontWeight(FontWeight.Bold);
                Text('本计划属于对开源/独立开发项目的自愿赞赏，不对应具体商品交易，所以不支持退款；未成年人禁止赞赏；如有疑问，请通过项目渠道联系开发者。')
                  .fontSize(15).lineHeight(24);
              }
              .width('100%').padding(20).backgroundColor(SettingsPanelSurfaceHelper.getBackground(this.themeState.currentTheme))
                .backgroundBlurStyle(SettingsPanelSurfaceHelper.getBlurStyle(this.themeState.currentTheme), SettingsPanelSurfaceHelper.getBlurOptions(this.themeState.currentTheme))
                .backgroundEffect(SettingsPanelSurfaceHelper.getBackgroundEffect(this.themeState.currentTheme))
                .borderRadius(SettingsPanelSurfaceHelper.getRadius(this.themeState.currentTheme))
                .border({ width: SettingsPanelSurfaceHelper.getBorderWidth(this.themeState.currentTheme), color: SettingsPanelSurfaceHelper.getBorderColor(this.themeState.currentTheme) });
              Blank().height(this.navigationBarHeight + 24);
            }.width('100%').padding({ left: 20, right: 20, bottom: 24 });
          }.width('100%').layoutWeight(1).scrollBar(BarState.Off).edgeEffect(EdgeEffect.Spring);
        }.width('100%').height('100%');
        SettingsImmersiveTitleBar({ themeState: this.themeState, title: '支持者计划协议', appFontFamily: this.appFontFamily,
          contentPadding: 16, maxContentWidth: 1200, pathStack: this.pathStack });
      }
    }.hideTitleBar(true).ignoreLayoutSafeArea([LayoutSafeAreaType.SYSTEM], [LayoutSafeAreaEdge.TOP, LayoutSafeAreaEdge.BOTTOM]).onReady((context: NavDestinationContext) => { this.pathStack = context.pathStack; })
      .backgroundColor(Color.Transparent);
  }
}

export { SupporterAgreementPage };
