import { HdsNavDestination } from '@kit.UIDesignKit';
import { ThemeAwareState, ThemeAwareHelper } from 'manxia_theme/src/main/ets/Framework/Components/ThemeAware';
import { SettingsImmersiveTitleBar } from './settings/SettingsImmersiveTitleBar';
import { SettingsManager } from '../Framework/Managers/SettingsManager';
import { common } from '@kit.AbilityKit';
import { photoAccessHelper } from '@kit.MediaLibraryKit';
import { fileIo as fs, fileUri } from '@kit.CoreFileKit';
import { GlobalBackgroundLayerMode } from 'manxia_theme/src/main/ets/Framework/Components/GlobalBackgroundLayer';
import { SharedPageBackgroundLayer } from '../Framework/Components/SharedPageBackgroundLayer';
import { SettingsPanelSurfaceHelper } from 'manxia_features_ui/src/main/ets/pages/settings/SettingsPanelSurfaceHelper';
import { SettingsPageTitleBarManager } from 'manxia_features_ui/src/main/ets/pages/settings/SettingsPageTitleBarManager';
import { SettingsSearchResult, SettingsSearchSupport } from 'manxia_features_ui/src/main/ets/pages/settings/SettingsSearchSupport';

class SupporterFeature {
  readonly icon: Resource;
  readonly title: string;
  readonly summary: string;
  readonly detail: string;
  readonly targetPage: string;
  readonly searchQuery: string;
  readonly operation: string;
  constructor(icon: Resource, title: string, summary: string, detail: string, targetPage: string, searchQuery: string, operation: string = '') {
    this.icon = icon;
    this.title = title;
    this.summary = summary;
    this.detail = detail;
    this.targetPage = targetPage;
    this.searchQuery = searchQuery;
    this.operation = operation;
  }
}

const SUPPORTER_FEATURES: SupporterFeature[] = [
  new SupporterFeature($r('sys.symbol.paintpalette'), '自定义主题设置', '打造专属漫匣外观', '自由组合主题色、背景和玻璃材质效果。', 'ThemeSettingsPage', '自定义主题'),
  new SupporterFeature($r('sys.symbol.picture'), '全局自定义背景', '让每个页面更有氛围', '设置全局背景图片、模糊与亮度，让书架和设置页保持统一风格。', 'PageSettingsSubPage', '全局自定义背景'),
  new SupporterFeature($r('sys.symbol.lock_fill'), '后台隐私遮罩', '切后台自动保护内容', '应用进入后台时自动覆盖隐私遮罩，避免最近任务预览泄露正在阅读的内容。', 'PageSettingsSubPage', '后台模糊遮罩'),
  new SupporterFeature($r('sys.symbol.eye'), 'SFW 模式', '更安心的内容过滤', '隐藏被标记为 NSFW 的内容，适合在公开场景下使用漫匣。', '', '', '长按主页面底栏的“管理”按钮开启'),
  new SupporterFeature($r('sys.symbol.bookshelf'), '隐私书架', '保护您的私人收藏', '将指定书籍放入独立的隐私区域，进入时需要进行身份验证。', '', '', '长按主页面底栏的“书库”按钮开启'),
  new SupporterFeature($r('sys.symbol.link'), 'Suwayomi & Komga 支持', '连接您的远程书库', '通过远程书库服务访问和管理漫画内容。', 'TrackingSettingsSubPage', '进度记录与服务器'),
  new SupporterFeature($r('sys.symbol.textstyle'), '全局自定义字体', '统一阅读与界面字体', '为应用界面与阅读内容选择更适合您的字体。', 'FontSettingsSubPage', '界面字体设置'),
  new SupporterFeature($r('sys.symbol.doc_plaintext'), 'MD & HTML 渲染能力', '更丰富的内容表达', '通过 EPUB WebView 渲染引擎获得更完整的 HTML 与富文本排版能力。', 'AdvancedSettingsSubPage', 'EPUB WebView 渲染引擎')
  ,new SupporterFeature($r('sys.symbol.rectangle_stack'), '阅读器多开', '独立管理多个阅读任务', '为漫画、小说和电子书阅读器启用独立页面实例，减少返回和切换时的状态互相影响。', 'PageSettingsSubPage', '阅读器页面多开')
  ,new SupporterFeature($r('sys.symbol.text_book_closed'), '小说设置', '自定义小说阅读体验', '集中调整小说字体、排版、背景、翻页和阅读显示选项。', 'NovelSettingsPage', '')
];

@Component
struct SupporterPlanPage {
  @State themeState: ThemeAwareState = new ThemeAwareState();
  @State pathStack: NavPathStack = new NavPathStack();
  @State activated: boolean = false;
  @State selectedFeature: SupporterFeature | null = null;
  @State isSaving: boolean = false;
  @State contentOpacity: number = 1;
  @State contentScale: number = 1;
  @State popupOpacity: number = 0;
  @State popupScale: number = 0.92;
  @State actionDialogType: string = '';
  @State actionDialogOpacity: number = 0;
  @State actionDialogScale: number = 0.92;
  @StorageProp('statusBarHeight') statusBarHeight: number = 0;
  @StorageProp('navigationBarHeight') navigationBarHeight: number = 0;
  @StorageLink('appFontFamily') appFontFamily: string = 'HarmonyOS Sans';
  private settingsManager: SettingsManager = SettingsManager.getInstance();

  aboutToAppear(): void {
    ThemeAwareHelper.initializeThemeAware('SupporterPlanPage', this.themeState, () => {});
    this.activated = this.settingsManager.getBoolean('manxia_supporter_activated', false);
  }
  aboutToDisappear(): void { ThemeAwareHelper.cleanupThemeAware('SupporterPlanPage'); }

  private async activate(): Promise<void> {
    await this.settingsManager.setBoolean('manxia_supporter_activated', true);
    this.animateSupporterStateChange(true);
  }

  private animateSupporterStateChange(nextActivated: boolean): void {
    this.getUIContext().animateTo({ duration: 170, curve: Curve.EaseIn }, () => {
      this.contentOpacity = 0;
      this.contentScale = 0.97;
    });
    setTimeout(() => {
      this.activated = nextActivated;
      this.contentScale = 1.02;
      this.getUIContext().animateTo({ duration: 260, curve: Curve.EaseOut }, () => {
        this.contentOpacity = 1;
        this.contentScale = 1;
      });
    }, 180);
  }

  private async cancelSupporterPlan(): Promise<void> {
    await this.settingsManager.setBoolean('manxia_supporter_activated', false);
    this.closeActionDialog();
    this.animateSupporterStateChange(false);
  }

  private openActionDialog(type: string): void {
    this.actionDialogType = type;
    this.actionDialogOpacity = 0;
    this.actionDialogScale = 0.92;
    this.getUIContext().animateTo({ duration: 220, curve: Curve.EaseOut }, () => {
      this.actionDialogOpacity = 1;
      this.actionDialogScale = 1;
    });
  }

  private closeActionDialog(): void {
    this.getUIContext().animateTo({ duration: 160, curve: Curve.EaseIn }, () => {
      this.actionDialogOpacity = 0;
      this.actionDialogScale = 0.92;
    });
    setTimeout(() => { this.actionDialogType = ''; }, 170);
  }

  private async continueOpenWechat(): Promise<void> {
    this.closeActionDialog();
    const context = this.getUIContext().getHostContext() as common.UIAbilityContext;
    try { await context.openLink('weixin://', { appLinkingOnly: false }); } catch (error) { String(error); }
  }

  private async saveQrcodeAndOpenWechat(): Promise<void> {
    if (this.isSaving) return;
    this.isSaving = true;
    try {
      const context = this.getUIContext().getHostContext() as common.UIAbilityContext;
      const raw: Uint8Array = await context.resourceManager.getMediaContent($r('app.media.mm_reward_qrcode').id);
      const tempPath: string = `${context.cacheDir}/manxia_supporter_qrcode.webp`;
      const tempFile = await fs.open(tempPath, fs.OpenMode.CREATE | fs.OpenMode.WRITE_ONLY);
      await fs.write(tempFile.fd, raw.buffer); await fs.close(tempFile);
      const sandboxUri: string = fileUri.getUriFromPath(tempPath);
      const helper = photoAccessHelper.getPhotoAccessHelper(context);
      const photoConfig: photoAccessHelper.PhotoCreationConfig = {
        title: 'manxia_supporter_qrcode',
        fileNameExtension: 'webp',
        photoType: photoAccessHelper.PhotoType.IMAGE,
        subtype: photoAccessHelper.PhotoSubtype.DEFAULT
      };
      const destinations: Array<string> = await helper.showAssetsCreationDialog([sandboxUri], [photoConfig]);
      if (destinations.length > 0) {
        const source = await fs.open(sandboxUri, fs.OpenMode.READ_ONLY); const target = await fs.open(destinations[0], fs.OpenMode.WRITE_ONLY);
        await fs.copyFile(source.fd, target.fd); await fs.close(source); await fs.close(target);
        this.getUIContext().getPromptAction().showToast({ message: '已保存赞赏码，正在跳转到微信' });
        try { await context.openLink('weixin://', { appLinkingOnly: false }); } catch (error) { String(error); }
        await this.activate();
      } else {
        this.openActionDialog('save_failure');
      }
    } catch (error) { String(error); this.openActionDialog('save_failure'); }
    finally { this.isSaving = false; }
  }

  private openAgreement(): void { this.pathStack.pushPathByName('SupporterAgreementPage', null); }
  private openFeature(feature: SupporterFeature): void {
    this.selectedFeature = feature;
    this.popupOpacity = 0;
    this.popupScale = 0.92;
    this.getUIContext().animateTo({ duration: 220, curve: Curve.EaseOut }, () => {
      this.popupOpacity = 1;
      this.popupScale = 1;
    });
  }
  private closeFeature(): void {
    this.getUIContext().animateTo({ duration: 160, curve: Curve.EaseIn }, () => {
      this.popupOpacity = 0;
      this.popupScale = 0.92;
    });
    setTimeout(() => { this.selectedFeature = null; }, 170);
  }
  private jumpToFeature(): void {
    if (this.selectedFeature !== null && this.selectedFeature.targetPage.length > 0) {
      const results: SettingsSearchResult[] = SettingsSearchSupport.search(this.selectedFeature.searchQuery, 1);
      if (results.length > 0) {
        SettingsSearchSupport.setPendingTarget(SettingsSearchSupport.createTargetFromResult(results[0], this.selectedFeature.searchQuery));
      }
      this.pathStack.pushPathByName(this.selectedFeature.targetPage, null);
    }
    this.closeFeature();
  }

  @Builder buildFeatureCard(feature: SupporterFeature) {
    Row({ space: 12 }) { SymbolGlyph(feature.icon).fontSize(28).fontColor([ThemeAwareHelper.getTestManagementThemedColor('accent_primary', this.themeState.currentTheme)]); Column({ space: 4 }) { Text(feature.title).fontSize(16).fontWeight(FontWeight.Medium).fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_primary', this.themeState.currentTheme)); Text(feature.summary).fontSize(13).fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_secondary', this.themeState.currentTheme)); }.alignItems(HorizontalAlign.Start).layoutWeight(1); }
      .width('100%').padding(18).backgroundColor(SettingsPanelSurfaceHelper.getBackground(this.themeState.currentTheme)).backgroundBlurStyle(SettingsPanelSurfaceHelper.getBlurStyle(this.themeState.currentTheme), SettingsPanelSurfaceHelper.getBlurOptions(this.themeState.currentTheme)).backgroundEffect(SettingsPanelSurfaceHelper.getBackgroundEffect(this.themeState.currentTheme)).borderRadius(SettingsPanelSurfaceHelper.getRadius(this.themeState.currentTheme)).border({ width: SettingsPanelSurfaceHelper.getBorderWidth(this.themeState.currentTheme), color: SettingsPanelSurfaceHelper.getBorderColor(this.themeState.currentTheme) }).shadow({ radius: 12, color: SettingsPanelSurfaceHelper.getShadowColor(this.themeState.currentTheme), offsetY: 5 }).onClick(() => this.openFeature(feature));
  }

  @Builder buildFeatureGrid() {
    GridRow({ columns: { sm: 1, md: 2, lg: 2 }, gutter: 12 }) { ForEach(SUPPORTER_FEATURES, (feature: SupporterFeature) => { GridCol({ span: { sm: 1, md: 1, lg: 1 } }) { this.buildFeatureCard(feature); } }); }.width('100%');
  }

  @Builder buildInactive() {
    Column({ space: 16 }) {
      Row({ space: 16 }) { SymbolGlyph($r('sys.symbol.star_fill')).fontSize(48).fontColor([ThemeAwareHelper.getTestManagementThemedColor('accent_primary', this.themeState.currentTheme)]); Column({ space: 8 }) { Text('漫匣支持者计划').fontSize(24).fontWeight(FontWeight.Bold).fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_primary', this.themeState.currentTheme)); Text('￥18 · 一次性的项目支持').fontSize(18).fontWeight(FontWeight.Medium).fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_primary', this.themeState.currentTheme)); Text('支持者计划不是内购，而是对开发项目的自愿支持。支持后可以解锁漫匣独有能力，并帮助项目持续维护。').fontSize(14).lineHeight(22).fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_secondary', this.themeState.currentTheme)); }.layoutWeight(1); }.width('100%').padding(24).backgroundColor(SettingsPanelSurfaceHelper.getBackground(this.themeState.currentTheme)).backgroundBlurStyle(SettingsPanelSurfaceHelper.getBlurStyle(this.themeState.currentTheme), SettingsPanelSurfaceHelper.getBlurOptions(this.themeState.currentTheme)).backgroundEffect(SettingsPanelSurfaceHelper.getBackgroundEffect(this.themeState.currentTheme)).borderRadius(24).border({ width: SettingsPanelSurfaceHelper.getBorderWidth(this.themeState.currentTheme), color: SettingsPanelSurfaceHelper.getBorderColor(this.themeState.currentTheme) }).shadow({ radius: 16, color: SettingsPanelSurfaceHelper.getShadowColor(this.themeState.currentTheme), offsetY: 8 });
      this.buildFeatureGrid();
      Column({ space: 10 }) { Text('支持计划说明').fontSize(18).fontWeight(FontWeight.Bold); Text('点击付费按钮后会保存微信赞赏码，建议备注您的漫匣 ID。完成支持后可返回此页面，或点击下方按钮直接诚信激活。').fontSize(14).lineHeight(22).fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_secondary', this.themeState.currentTheme)); Row() { Text('支持者计划协议').fontSize(16).fontColor(ThemeAwareHelper.getTestManagementThemedColor('accent_primary', this.themeState.currentTheme)).layoutWeight(1); SymbolGlyph($r('sys.symbol.chevron_right')).fontSize(18).fontColor([ThemeAwareHelper.getTestManagementThemedColor('accent_primary', this.themeState.currentTheme)]); }.width('100%').height(46).onClick(() => this.openAgreement()); }.width('100%').padding(20).backgroundColor(SettingsPanelSurfaceHelper.getBackground(this.themeState.currentTheme)).backgroundBlurStyle(SettingsPanelSurfaceHelper.getBlurStyle(this.themeState.currentTheme), SettingsPanelSurfaceHelper.getBlurOptions(this.themeState.currentTheme)).backgroundEffect(SettingsPanelSurfaceHelper.getBackgroundEffect(this.themeState.currentTheme)).borderRadius(SettingsPanelSurfaceHelper.getRadius(this.themeState.currentTheme)).border({ width: SettingsPanelSurfaceHelper.getBorderWidth(this.themeState.currentTheme), color: SettingsPanelSurfaceHelper.getBorderColor(this.themeState.currentTheme) });
      Button(this.isSaving ? '保存中…' : '记得备注 ID · 微信赞赏 ￥18').width('100%').height(54).fontSize(17).backgroundColor(ThemeAwareHelper.getTestManagementThemedColor('accent_primary', this.themeState.currentTheme)).enabled(!this.isSaving).onClick(() => { void this.saveQrcodeAndOpenWechat(); });
      Button('我已诚信支持').width('100%').height(48).fontSize(15).backgroundColor(Color.Transparent).fontColor(ThemeAwareHelper.getTestManagementThemedColor('accent_primary', this.themeState.currentTheme)).onClick(() => { this.openActionDialog('honest'); });
    }.width('100%');
  }

  @Builder buildActive() {
    Column({ space: 16 }) { Column({ space: 8 }) { Text('漫匣支持者').fontSize(26).fontWeight(FontWeight.Bold).fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_primary', this.themeState.currentTheme)); Text('感谢您的支持，专属能力已启用').fontSize(14).fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_secondary', this.themeState.currentTheme)); }.width('100%').padding(20).backgroundColor(SettingsPanelSurfaceHelper.getBackground(this.themeState.currentTheme)).backgroundBlurStyle(SettingsPanelSurfaceHelper.getBlurStyle(this.themeState.currentTheme), SettingsPanelSurfaceHelper.getBlurOptions(this.themeState.currentTheme)).backgroundEffect(SettingsPanelSurfaceHelper.getBackgroundEffect(this.themeState.currentTheme)).borderRadius(24).border({ width: SettingsPanelSurfaceHelper.getBorderWidth(this.themeState.currentTheme), color: SettingsPanelSurfaceHelper.getBorderColor(this.themeState.currentTheme) }); this.buildFeatureGrid(); Button('取消支持者计划').width('100%').height(46).fontSize(14).backgroundColor(Color.Transparent).fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_muted', this.themeState.currentTheme)).onClick(() => { this.openActionDialog('cancel'); }); }.width('100%');
  }

  @Builder buildFeaturePopup() {
    if (this.selectedFeature !== null) { Stack() { Column({ space: 14 }) { SymbolGlyph(this.selectedFeature.icon).fontSize(36).fontColor([ThemeAwareHelper.getTestManagementThemedColor('accent_primary', this.themeState.currentTheme)]); Text(this.selectedFeature.title).fontSize(22).fontWeight(FontWeight.Bold); Text('功能说明').fontSize(14).fontWeight(FontWeight.Medium).fontColor(ThemeAwareHelper.getTestManagementThemedColor('accent_primary', this.themeState.currentTheme)); Text(this.selectedFeature.detail).fontSize(15).lineHeight(24).fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_secondary', this.themeState.currentTheme)); if (this.selectedFeature.operation.length > 0) { Text('操作方式').fontSize(14).fontWeight(FontWeight.Medium).fontColor(ThemeAwareHelper.getTestManagementThemedColor('accent_primary', this.themeState.currentTheme)); Text(this.selectedFeature.operation).fontSize(15).lineHeight(24).fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_secondary', this.themeState.currentTheme)); } Row({ space: 12 }) { if (this.selectedFeature.targetPage.length > 0) { Button('前往设置').layoutWeight(1).backgroundColor(ThemeAwareHelper.getTestManagementThemedColor('accent_primary', this.themeState.currentTheme)).onClick(() => this.jumpToFeature()); } Button('关闭').layoutWeight(1).backgroundColor(Color.Transparent).onClick(() => this.closeFeature()); }.width('100%'); }.width('88%').padding(28).backgroundColor(SettingsPanelSurfaceHelper.getBackground(this.themeState.currentTheme)).backgroundBlurStyle(SettingsPanelSurfaceHelper.getBlurStyle(this.themeState.currentTheme), SettingsPanelSurfaceHelper.getBlurOptions(this.themeState.currentTheme)).backgroundEffect(SettingsPanelSurfaceHelper.getBackgroundEffect(this.themeState.currentTheme)).borderRadius(28).border({ width: SettingsPanelSurfaceHelper.getBorderWidth(this.themeState.currentTheme), color: SettingsPanelSurfaceHelper.getBorderColor(this.themeState.currentTheme) }).shadow({ radius: 24, color: SettingsPanelSurfaceHelper.getShadowColor(this.themeState.currentTheme), offsetY: 10 }).opacity(this.popupOpacity).scale({ x: this.popupScale, y: this.popupScale }); }.width('100%').height('100%').backgroundColor('#99000000').align(Alignment.Center).onClick(() => this.closeFeature()).zIndex(20); }
    if (this.actionDialogType.length > 0) { Stack() { Column({ space: 14 }) { SymbolGlyph(this.actionDialogType === 'honest' ? $r('sys.symbol.star_fill') : $r('sys.symbol.exclamationmark_circle')).fontSize(34).fontColor([ThemeAwareHelper.getTestManagementThemedColor('accent_primary', this.themeState.currentTheme)]); Text(this.actionDialogType === 'cancel' ? '取消支持者计划？' : this.actionDialogType === 'honest' ? '谢谢您愿意支持漫匣' : '赞赏码保存失败').fontSize(21).fontWeight(FontWeight.Bold).fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_primary', this.themeState.currentTheme)); Text(this.actionDialogType === 'cancel' ? '取消后本机将回到未激活状态，之后仍可重新进行诚信激活。' : this.actionDialogType === 'honest' ? '您的认可和鼓励会帮助漫匣继续成长。如果您已经完成支持，点击下方按钮即可启用支持者状态，再次感谢您的陪伴。' : '赞赏码未能保存到相册，是否仍然继续跳转到微信？').fontSize(15).lineHeight(24).fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_secondary', this.themeState.currentTheme)); Row({ space: 12 }) { Button(this.actionDialogType === 'cancel' ? '确认取消' : this.actionDialogType === 'honest' ? '感谢支持' : '继续跳转').layoutWeight(1).backgroundColor(ThemeAwareHelper.getTestManagementThemedColor('accent_primary', this.themeState.currentTheme)).onClick(() => { if (this.actionDialogType === 'cancel') { void this.cancelSupporterPlan(); } else if (this.actionDialogType === 'honest') { this.closeActionDialog(); void this.activate(); } else { void this.continueOpenWechat(); } }); Button('返回').layoutWeight(1).backgroundColor(Color.Transparent).onClick(() => this.closeActionDialog()); }.width('100%'); }.width('88%').padding(28).backgroundColor(SettingsPanelSurfaceHelper.getBackground(this.themeState.currentTheme)).backgroundBlurStyle(SettingsPanelSurfaceHelper.getBlurStyle(this.themeState.currentTheme), SettingsPanelSurfaceHelper.getBlurOptions(this.themeState.currentTheme)).backgroundEffect(SettingsPanelSurfaceHelper.getBackgroundEffect(this.themeState.currentTheme)).borderRadius(28).border({ width: SettingsPanelSurfaceHelper.getBorderWidth(this.themeState.currentTheme), color: SettingsPanelSurfaceHelper.getBorderColor(this.themeState.currentTheme) }).shadow({ radius: 24, color: SettingsPanelSurfaceHelper.getShadowColor(this.themeState.currentTheme), offsetY: 10 }).opacity(this.actionDialogOpacity).scale({ x: this.actionDialogScale, y: this.actionDialogScale }); }.width('100%').height('100%').backgroundColor('#99000000').align(Alignment.Center).zIndex(21); }
  }

  build() {
    HdsNavDestination() { Stack() { SharedPageBackgroundLayer({ defaultBackgroundColor: ThemeAwareHelper.getTestManagementThemedColor('background_dark', this.themeState.currentTheme), mode: GlobalBackgroundLayerMode.IMMERSIVE }).width('100%').height('100%').expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.TOP, SafeAreaEdge.BOTTOM]); Scroll() { Column() { Blank().height(SettingsPageTitleBarManager.getContentTopPadding(this.statusBarHeight)); Column() { if (this.activated) { this.buildActive(); } else { this.buildInactive(); } }.width('100%').opacity(this.contentOpacity).scale({ x: this.contentScale, y: this.contentScale }); Blank().height(this.navigationBarHeight + 24); }.width('100%').padding({ left: 16, right: 16 }); }.width('100%').height('100%').scrollBar(BarState.Off).edgeEffect(EdgeEffect.Spring).expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.TOP, SafeAreaEdge.BOTTOM]); SettingsImmersiveTitleBar({ themeState: this.themeState, title: '漫匣支持者计划', appFontFamily: this.appFontFamily, contentPadding: 16, maxContentWidth: 1200, pathStack: this.pathStack }); this.buildFeaturePopup(); }.width('100%').height('100%') }.hideTitleBar(true).ignoreLayoutSafeArea([LayoutSafeAreaType.SYSTEM], [LayoutSafeAreaEdge.TOP, LayoutSafeAreaEdge.BOTTOM]).onReady((context: NavDestinationContext) => { this.pathStack = context.pathStack; }).backgroundColor(Color.Transparent);
  }
}

export { SupporterPlanPage };
