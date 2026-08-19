/**
 * 图源独立维护页面
 */

import { common } from '@kit.AbilityKit';
import { HdsNavDestination } from '@kit.UIDesignKit';
import { logger } from 'manxia_core/src/main/ets/Utils/Logger';
import { ThemeAwareHelper, ThemeAwareState } from '../Framework/Components/ThemeAware';
import { ThemeType } from '../Framework/Managers/ThemeManager';
import { FontAwareHelper, FontAwareState } from '../Framework/Components/FontAware';
import { SharedPageBackgroundLayer } from '../Framework/Components/SharedPageBackgroundLayer';
import { GlobalBackgroundLayerMode } from '../Framework/Components/GlobalBackgroundLayer';
import { SettingsImmersiveTitleBar } from './settings/SettingsImmersiveTitleBar';
import { SettingsPageTitleBarManager } from './settings/SettingsPageTitleBarManager';
import { SettingsPanelSurfaceHelper } from './settings/SettingsPanelSurfaceHelper';
import {
  sourceMaintenanceManager,
  SourceMaintenanceBadge,
  SourceMaintenanceExportResult,
  SourceMaintenanceFileChangeState,
  SourceMaintenancePageParams,
  SourceMaintenancePullResult,
  SourceMaintenanceRepositoryTracking,
  SourceMaintenanceTrackingSnapshot
} from '../Framework/Source/SourceMaintenanceManager';
import { LegadoMangaSourceBridge } from '../Framework/Novel/LegadoMangaSourceBridge';

const TAG = 'SourceMaintenancePage';

type SourceMaintenanceColorKey =
  'background_dark' |
  'text_primary' |
  'text_secondary' |
  'text_muted' |
  'comp_background_tertiary' |
  'button_background' |
  'divider' |
  'accent_primary' |
  'accent_blue' |
  'accent_green' |
  'color_error';

@Component
export struct SourceMaintenancePage {
  @State pathStack: NavPathStack = new NavPathStack();
  @State themeState: ThemeAwareState = new ThemeAwareState();
  @State fontState: FontAwareState = new FontAwareState();
  @StorageLink('appFontFamily') appFontFamily: string = 'HarmonyOS Sans';
  @StorageProp('statusBarHeight') statusBarHeight: number = 0;
  @StorageProp('navigationBarHeight') navigationBarHeight: number = 0;

  @State sourceId: number = 0;
  @State sourcePkg: string = '';
  @State sourceName: string = '';
  @State modeLabel: string = '官方同步';
  @State syncLabel: string = '干净';
  @State statusDescription: string = '';
  @State repositoryUrl: string = '';
  @State branch: string = 'main';
  @State sourcePath: string = '';
  @State exportPath: string = '';
  @State pullRequestUrl: string = '';
  @State lastMessage: string = '';
  @State isBusy: boolean = false;
  @State needsAttention: boolean = false;
  @State activeTabIndex: number = 0;
  @State trackingSnapshot: SourceMaintenanceTrackingSnapshot = sourceMaintenanceManager.createEmptyTrackingSnapshot();

  private componentId: string = `SourceMaintenancePage_${Date.now()}`;

  aboutToAppear(): void {
    ThemeAwareHelper.initializeThemeAware(this.componentId, this.themeState, (theme: ThemeType) => {
      logger.info(TAG, `主题切换: ${theme}`);
    });
    FontAwareHelper.initializeFontAware(this.componentId, this.fontState, (newState: FontAwareState) => {
      this.fontState = newState;
    });
  }

  aboutToDisappear(): void {
    ThemeAwareHelper.cleanupThemeAware(this.componentId);
    FontAwareHelper.cleanupFontAware(this.componentId);
  }

  private loadParams(params: SourceMaintenancePageParams | null): void {
    if (params) {
      this.sourceId = params.sourceId || 0;
      this.sourcePkg = (params.sourcePkg || '').trim();
      this.sourceName = params.sourceName || '';
    }
    if (LegadoMangaSourceBridge.isLegadoMangaPkg(this.sourcePkg)) {
      logger.info(TAG, `已阻止 Legado 图源进入独立维护页面: ${this.sourcePkg}`);
      this.showToast('Legado 图源不支持独立维护');
      this.handleBack();
      return;
    }
    if (this.sourcePath.length <= 0 && this.sourcePkg.length > 0) {
      this.sourcePath = `${this.sourcePkg}/source.json`;
    }
    void this.refreshRecord();
  }

  private async refreshRecord(): Promise<void> {
    try {
      const snapshot: SourceMaintenanceTrackingSnapshot = await sourceMaintenanceManager.getTrackingSnapshot(this.sourcePkg, true);
      const badge: SourceMaintenanceBadge = snapshot.badge;
      this.trackingSnapshot = snapshot;
      this.modeLabel = badge.modeLabel;
      this.syncLabel = badge.syncLabel;
      this.statusDescription = badge.description;
      this.needsAttention = badge.needsAttention;
      this.sourceId = snapshot.sourceId > 0 ? snapshot.sourceId : this.sourceId;
      this.sourceName = snapshot.sourceName.length > 0 ? snapshot.sourceName : this.sourceName;
      this.exportPath = snapshot.exportPath;
      this.pullRequestUrl = snapshot.pullRequestUrl;
      if (snapshot.privateRepository.isBound) {
        this.repositoryUrl = snapshot.privateRepository.repositoryUrl;
        this.branch = snapshot.privateRepository.branch;
        this.sourcePath = snapshot.privateRepository.sourcePath;
      }
    } catch (error) {
      logger.warn(TAG, `刷新维护记录失败: ${String(error)}`);
    }
  }

  private async saveRepositoryBinding(): Promise<void> {
    if (this.sourcePkg.length <= 0) {
      this.showToast('缺少图源 pkg');
      return;
    }
    if (this.repositoryUrl.trim().length <= 0) {
      this.showToast('请填写仓库地址');
      return;
    }
    await this.runBusy(async (): Promise<void> => {
      await sourceMaintenanceManager.bindUserRepository(
        this.sourcePkg,
        this.sourceName,
        this.repositoryUrl,
        this.branch,
        this.sourcePath
      );
      this.lastMessage = '仓库绑定已保存';
      this.showToast(this.lastMessage);
      await this.refreshRecord();
    });
  }

  private async exportBundle(): Promise<void> {
    if (this.sourcePkg.length <= 0) {
      this.showToast('缺少图源 pkg');
      return;
    }
    await this.runBusy(async (): Promise<void> => {
      const result: SourceMaintenanceExportResult = await sourceMaintenanceManager.exportMaintenanceBundle(this.sourcePkg);
      this.lastMessage = result.message;
      if (result.success) {
        this.exportPath = result.exportDir;
      }
      this.showToast(result.message);
      await this.refreshRecord();
    });
  }

  private async pullFromRepository(): Promise<void> {
    if (this.sourcePkg.length <= 0) {
      this.showToast('缺少图源 pkg');
      return;
    }
    await this.runBusy(async (): Promise<void> => {
      const result: SourceMaintenancePullResult = await sourceMaintenanceManager.pullFromUserRepository(this.sourcePkg);
      this.lastMessage = result.message;
      this.showToast(result.message);
      await this.refreshRecord();
    });
  }

  private async pullFromOfficialRepository(): Promise<void> {
    if (this.sourcePkg.length <= 0) {
      this.showToast('缺少图源 pkg');
      return;
    }
    await this.runBusy(async (): Promise<void> => {
      const result: SourceMaintenancePullResult = await sourceMaintenanceManager.pullFromOfficialRepository(this.sourcePkg);
      this.lastMessage = result.message;
      this.showToast(result.message);
      await this.refreshRecord();
    });
  }

  private async refreshTracking(): Promise<void> {
    await this.runBusy(async (): Promise<void> => {
      await this.refreshRecord();
      this.lastMessage = '追踪状态已刷新';
      this.showToast(this.lastMessage);
    });
  }

  private async savePullRequestUrl(): Promise<void> {
    if (this.sourcePkg.length <= 0) {
      this.showToast('缺少图源 pkg');
      return;
    }
    await this.runBusy(async (): Promise<void> => {
      await sourceMaintenanceManager.markOfficialPullRequest(this.sourcePkg, this.sourceName, this.pullRequestUrl);
      this.lastMessage = this.pullRequestUrl.trim().length > 0 ? 'PR 链接已记录' : '已标记为官方 PR 候选';
      this.showToast(this.lastMessage);
      await this.refreshRecord();
    });
  }

  private async runBusy(task: () => Promise<void>): Promise<void> {
    if (this.isBusy) {
      return;
    }
    this.isBusy = true;
    try {
      await task();
    } catch (error) {
      const message: string = String(error);
      logger.error(TAG, '维护操作失败', message);
      this.lastMessage = message;
      this.showToast(message);
    } finally {
      this.isBusy = false;
    }
  }

  private showToast(message: string): void {
    this.getUIContext().getPromptAction().showToast({
      message: message,
      duration: 2200
    });
  }

  private color(key: SourceMaintenanceColorKey): ResourceColor {
    return ThemeAwareHelper.getTestManagementThemedColor(key, this.themeState.currentTheme);
  }

  private accentColor(): ResourceColor {
    return this.needsAttention ? this.color('color_error') : this.color('accent_primary');
  }

  private getTrackingAccentColor(state: SourceMaintenanceFileChangeState): ResourceColor {
    if (state === 'clean') {
      return this.color('accent_green');
    }
    if (state === 'remoteChanged') {
      return this.color('accent_blue');
    }
    if (state === 'modified' || state === 'conflicted') {
      return this.color('color_error');
    }
    return this.color('accent_primary');
  }

  private formatHash(hash: string): string {
    if (hash.length <= 0) {
      return '未发现';
    }
    if (hash.length <= 12) {
      return hash;
    }
    return hash.substring(0, 12);
  }

  private formatTime(timestamp: number): string {
    if (timestamp <= 0) {
      return '从未 pull';
    }
    const date = new Date(timestamp);
    return `${date.getFullYear()}-${this.pad2(date.getMonth() + 1)}-${this.pad2(date.getDate())} ` +
      `${this.pad2(date.getHours())}:${this.pad2(date.getMinutes())}`;
  }

  private pad2(value: number): string {
    return value < 10 ? `0${value}` : `${value}`;
  }

  private handleBack(): boolean {
    try {
      this.pathStack.pop();
      return true;
    } catch (error) {
      logger.warn(TAG, `返回失败: ${String(error)}`);
      return false;
    }
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

        Column() {
          Blank().height(SettingsPageTitleBarManager.getContentTopPadding(this.statusBarHeight))

          Scroll() {
            Column({ space: 14 }) {
              this.buildStatusCard()
              this.buildRepositoryTabs()
              Blank().height(24 + this.navigationBarHeight)
            }
            .width('100%')
            .padding({ left: 16, right: 16, bottom: 12 })
          }
          .layoutWeight(1)
          .scrollBar(BarState.Auto)
          .edgeEffect(EdgeEffect.Spring)
        }
        .width('100%')
        .height('100%')

        SettingsImmersiveTitleBar({
          themeState: this.themeState,
          title: '图源独立维护',
          appFontFamily: this.appFontFamily
        })
      }
      .width('100%')
      .height('100%')
    }
    .hideTitleBar(true)
    .ignoreLayoutSafeArea([LayoutSafeAreaType.SYSTEM], [LayoutSafeAreaEdge.TOP, LayoutSafeAreaEdge.BOTTOM])
    .backgroundColor(Color.Transparent)
    .onBackPressed(() => {
      return this.handleBack();
    })
    .onReady((context: NavDestinationContext) => {
      this.pathStack = context.pathStack;
      const hostContext = this.getUIContext().getHostContext() as common.UIAbilityContext;
      sourceMaintenanceManager.setAbilityContext(hostContext);
      const params = context.pathInfo.param as SourceMaintenancePageParams | null;
      this.loadParams(params);
    })
  }

  @Builder
  private buildStatusCard() {
    Column({ space: 12 }) {
      Row() {
        Column({ space: 4 }) {
          Text(this.sourceName.length > 0 ? this.sourceName : '未命名图源')
            .fontSize(18)
            .fontWeight(FontWeight.Medium)
            .fontFamily(this.appFontFamily)
            .fontColor(this.color('text_primary'))
            .maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis })

          Text(this.sourcePkg)
            .fontSize(12)
            .fontFamily(this.appFontFamily)
            .fontColor(this.color('text_muted'))
            .maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
        }
        .layoutWeight(1)

        SymbolGlyph(this.needsAttention ? $r('sys.symbol.exclamationmark_circle') : $r('sys.symbol.checkmark_circle'))
          .fontSize(28)
          .fontColor([this.accentColor()])
      }
      .width('100%')

      Row({ space: 8 }) {
        Text(this.modeLabel)
          .fontSize(12)
          .fontFamily(this.appFontFamily)
          .fontColor(this.accentColor())
          .padding({ left: 8, right: 8, top: 3, bottom: 3 })
          .borderRadius(6)
          .backgroundColor(this.accentColor() + '20')

        Text(this.syncLabel)
          .fontSize(12)
          .fontFamily(this.appFontFamily)
          .fontColor(this.accentColor())
          .padding({ left: 8, right: 8, top: 3, bottom: 3 })
          .borderRadius(6)
          .backgroundColor(this.accentColor() + '16')
      }
      .width('100%')

      Text(this.statusDescription)
        .fontSize(13)
        .fontFamily(this.appFontFamily)
        .fontColor(this.color('text_secondary'))
        .width('100%')
    }
    .width('100%')
    .padding(16)
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

  @Builder
  private buildRepositoryTabs() {
    Column({ space: 12 }) {
      Row({ space: 8 }) {
        this.buildTabButton(0, '私有图源仓库')
        this.buildTabButton(1, '漫匣图源仓库')
      }
      .width('100%')
      .padding(6)
      .backgroundColor(this.color('comp_background_tertiary'))
      .borderRadius(18)

      if (this.activeTabIndex === 0) {
        this.buildPrivateRepositoryTab()
      } else {
        this.buildOfficialRepositoryTab()
      }
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
    .shadow({ radius: SettingsPanelSurfaceHelper.getRadius(this.themeState.currentTheme) + 4, color: SettingsPanelSurfaceHelper.getShadowColor(this.themeState.currentTheme), offsetX: 0, offsetY: 8 })
  }

  @Builder
  private buildTabButton(index: number, label: string) {
    Text(label)
      .fontSize(13)
      .fontWeight(this.activeTabIndex === index ? FontWeight.Bold : FontWeight.Medium)
      .fontFamily(this.appFontFamily)
      .fontColor(this.activeTabIndex === index ? this.color('text_primary') : this.color('text_secondary'))
      .textAlign(TextAlign.Center)
      .layoutWeight(1)
      .padding({ top: 9, bottom: 9 })
      .borderRadius(13)
      .backgroundColor(this.activeTabIndex === index ? this.color('button_background') : Color.Transparent)
      .border({
        width: this.activeTabIndex === index ? 1 : 0,
        color: this.activeTabIndex === index ? this.color('divider') : Color.Transparent
      })
      .onClick(() => {
        this.activeTabIndex = index;
      })
  }

  @Builder
  private buildPrivateRepositoryTab() {
    Column({ space: 12 }) {
      this.buildRepositorySummary(this.trackingSnapshot.privateRepository)

      TextInput({ placeholder: '填写私有仓库地址', text: this.repositoryUrl })
        .height(44)
        .backgroundColor(this.color('comp_background_tertiary'))
        .fontColor(this.color('text_primary'))
        .fontFamily(this.appFontFamily)
        .onChange((value: string) => {
          this.repositoryUrl = value;
        })

      Row({ space: 10 }) {
        TextInput({ placeholder: '分支', text: this.branch })
          .height(44)
          .layoutWeight(1)
          .backgroundColor(this.color('comp_background_tertiary'))
          .fontColor(this.color('text_primary'))
          .fontFamily(this.appFontFamily)
          .onChange((value: string) => {
            this.branch = value;
          })

        TextInput({ placeholder: '图源文件路径', text: this.sourcePath })
          .height(44)
          .layoutWeight(2)
          .backgroundColor(this.color('comp_background_tertiary'))
          .fontColor(this.color('text_primary'))
          .fontFamily(this.appFontFamily)
          .onChange((value: string) => {
            this.sourcePath = value;
          })
      }
      .width('100%')

      Row({ space: 10 }) {
        this.buildActionButton('保存绑定', $r('sys.symbol.link'), this.color('accent_green'), () => {
          void this.saveRepositoryBinding();
        })
        this.buildActionButton('刷新追踪', $r('sys.symbol.arrow_clockwise'), this.color('accent_blue'), () => {
          void this.refreshTracking();
        })
      }
      .width('100%')

      Row({ space: 10 }) {
        this.buildActionButton('从私有仓库拉取', $r('sys.symbol.arrow_down_circle'), this.color('accent_primary'), () => {
          void this.pullFromRepository();
        })
        this.buildActionButton('导出维护包', $r('sys.symbol.square_and_arrow_down'), this.color('accent_green'), () => {
          void this.exportBundle();
        })
      }
      .width('100%')

      this.buildAgentKitHint()
      this.buildOperationMessage()
    }
    .width('100%')
  }

  @Builder
  private buildOfficialRepositoryTab() {
    Column({ space: 12 }) {
      this.buildRepositorySummary(this.trackingSnapshot.officialRepository)

      Row({ space: 10 }) {
        this.buildActionButton('刷新追踪', $r('sys.symbol.arrow_clockwise'), this.color('accent_blue'), () => {
          void this.refreshTracking();
        })
        this.buildActionButton('从漫匣仓库拉取', $r('sys.symbol.arrow_down_circle'), this.color('accent_primary'), () => {
          void this.pullFromOfficialRepository();
        })
      }
      .width('100%')

      Row({ space: 10 }) {
        this.buildActionButton('导出维护包', $r('sys.symbol.square_and_arrow_down'), this.color('accent_green'), () => {
          void this.exportBundle();
        })
        this.buildActionButton('记录官方 PR', $r('sys.symbol.arrowshape_turn_up_right'), this.color('accent_green'), () => {
          void this.savePullRequestUrl();
        })
      }
      .width('100%')

      TextInput({ placeholder: '粘贴已创建的 Pull Request 链接', text: this.pullRequestUrl })
        .height(44)
        .backgroundColor(this.color('comp_background_tertiary'))
        .fontColor(this.color('text_primary'))
        .fontFamily(this.appFontFamily)
        .onChange((value: string) => {
          this.pullRequestUrl = value;
        })

      this.buildAgentKitHint()
      this.buildOperationMessage()
    }
    .width('100%')
  }

  @Builder
  private buildRepositorySummary(tracking: SourceMaintenanceRepositoryTracking) {
    Column({ space: 8 }) {
      Row() {
        Column({ space: 3 }) {
          Text(tracking.title)
            .fontSize(16)
            .fontWeight(FontWeight.Medium)
            .fontFamily(this.appFontFamily)
            .fontColor(this.color('text_primary'))
            .alignSelf(ItemAlign.Start)

          Text(tracking.description)
            .fontSize(12)
            .fontFamily(this.appFontFamily)
            .fontColor(this.color('text_secondary'))
            .width('100%')
        }
        .layoutWeight(1)

        Text(tracking.stateLabel)
          .fontSize(12)
          .fontFamily(this.appFontFamily)
          .fontColor(this.getTrackingAccentColor(tracking.state))
          .padding({ left: 8, right: 8, top: 3, bottom: 3 })
          .borderRadius(6)
          .backgroundColor(this.getTrackingAccentColor(tracking.state) + '18')
      }
      .width('100%')

      this.buildTrackingRow('仓库', tracking.repositoryUrl.length > 0 ? tracking.repositoryUrl : '未绑定')
      this.buildTrackingRow('分支', tracking.branch.length > 0 ? tracking.branch : '未记录')
      this.buildTrackingRow('路径', tracking.sourcePath.length > 0 ? tracking.sourcePath : '未记录')
      this.buildTrackingRow('本地版本', tracking.localVersion.length > 0 ? tracking.localVersion : '未记录')
      this.buildTrackingRow('仓库版本', tracking.remoteVersion.length > 0 ? tracking.remoteVersion : '未发现')
      this.buildTrackingRow('本地 hash', this.formatHash(tracking.localHash))
      this.buildTrackingRow('仓库 hash', this.formatHash(tracking.remoteHash))
      this.buildTrackingRow('基线 hash', this.formatHash(tracking.baseHash))
      if (tracking.kind === 'official') {
        this.buildTrackingRow('仓库 code', tracking.remoteCode > 0 ? `${tracking.remoteCode}` : '未记录')
      }
      if (tracking.kind === 'private') {
        this.buildTrackingRow('上次 pull', this.formatTime(tracking.lastSyncTime))
      }
      if (tracking.lastError.length > 0) {
        this.buildTrackingRow('错误', tracking.lastError)
      }
      this.buildTrackingRow('工作区', this.trackingSnapshot.changeSummary)
    }
    .width('100%')
    .padding(12)
    .backgroundColor(this.color('comp_background_tertiary'))
    .borderRadius(10)
  }

  @Builder
  private buildTrackingRow(label: string, value: string) {
    Row({ space: 10 }) {
      Text(label)
        .fontSize(12)
        .fontFamily(this.appFontFamily)
        .fontColor(this.color('text_muted'))
        .width(78)

      Text(value)
        .fontSize(12)
        .fontFamily(this.appFontFamily)
        .fontColor(this.color('text_secondary'))
        .maxLines(2)
        .textOverflow({ overflow: TextOverflow.Ellipsis })
        .layoutWeight(1)
    }
    .width('100%')
  }

  @Builder
  private buildAgentKitHint() {
    Text('维护包会包含 source.json、manifest 和 AGENT_GUIDE.md，AgentKit 会据此同步私有仓库或整理官方 PR。')
      .fontSize(12)
      .fontFamily(this.appFontFamily)
      .fontColor(this.color('text_secondary'))
      .width('100%')
  }

  @Builder
  private buildOperationMessage() {
    Column({ space: 6 }) {
      if (this.exportPath.length > 0) {
        Text(`维护包: ${this.exportPath}`)
          .fontSize(12)
          .fontFamily(this.appFontFamily)
          .fontColor(this.color('text_muted'))
          .maxLines(2)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
          .width('100%')
      }

      if (this.lastMessage.length > 0) {
        Text(this.lastMessage)
          .fontSize(12)
          .fontFamily(this.appFontFamily)
          .fontColor(this.color('text_secondary'))
          .width('100%')
      }
    }
    .width('100%')
  }

  @Builder
  private buildRepositoryCard() {
    Column({ space: 12 }) {
      Text('我的图源仓库')
        .fontSize(16)
        .fontWeight(FontWeight.Medium)
        .fontFamily(this.appFontFamily)
        .fontColor(this.color('text_primary'))
        .alignSelf(ItemAlign.Start)

      TextInput({ placeholder: 'https://github.com/you/manxia-extensions-source', text: this.repositoryUrl })
        .height(44)
        .backgroundColor(this.color('comp_background_tertiary'))
        .fontColor(this.color('text_primary'))
        .fontFamily(this.appFontFamily)
        .onChange((value: string) => {
          this.repositoryUrl = value;
        })

      Row({ space: 10 }) {
        TextInput({ placeholder: 'main', text: this.branch })
          .height(44)
          .layoutWeight(1)
          .backgroundColor(this.color('comp_background_tertiary'))
          .fontColor(this.color('text_primary'))
          .fontFamily(this.appFontFamily)
          .onChange((value: string) => {
            this.branch = value;
          })

        TextInput({ placeholder: `${this.sourcePkg}/source.json`, text: this.sourcePath })
          .height(44)
          .layoutWeight(2)
          .backgroundColor(this.color('comp_background_tertiary'))
          .fontColor(this.color('text_primary'))
          .fontFamily(this.appFontFamily)
          .onChange((value: string) => {
            this.sourcePath = value;
          })
      }
      .width('100%')

      this.buildActionButton('保存绑定', $r('sys.symbol.link'), this.color('accent_green'), () => {
        void this.saveRepositoryBinding();
      })
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
    .shadow({ radius: SettingsPanelSurfaceHelper.getRadius(this.themeState.currentTheme) + 4, color: SettingsPanelSurfaceHelper.getShadowColor(this.themeState.currentTheme), offsetX: 0, offsetY: 8 })
  }

  @Builder
  private buildWorkflowCard() {
    Column({ space: 12 }) {
      Text('维护动作')
        .fontSize(16)
        .fontWeight(FontWeight.Medium)
        .fontFamily(this.appFontFamily)
        .fontColor(this.color('text_primary'))
        .alignSelf(ItemAlign.Start)

      Row({ space: 10 }) {
        this.buildActionButton('导出维护包', $r('sys.symbol.square_and_arrow_down'), this.color('accent_primary'), () => {
          void this.exportBundle();
        })
        this.buildActionButton('从仓库拉取', $r('sys.symbol.arrow_down_circle'), this.color('accent_blue'), () => {
          void this.pullFromRepository();
        })
      }
      .width('100%')

      TextInput({ placeholder: 'https://github.com/manxia-app/manxia-extensions-source/pull/123', text: this.pullRequestUrl })
        .height(44)
        .backgroundColor(this.color('comp_background_tertiary'))
        .fontColor(this.color('text_primary'))
        .fontFamily(this.appFontFamily)
        .onChange((value: string) => {
          this.pullRequestUrl = value;
        })

      this.buildActionButton('记录官方 PR', $r('sys.symbol.arrowshape_turn_up_right'), this.color('accent_green'), () => {
        void this.savePullRequestUrl();
      })

      if (this.exportPath.length > 0) {
        Text(`维护包: ${this.exportPath}`)
          .fontSize(12)
          .fontFamily(this.appFontFamily)
          .fontColor(this.color('text_muted'))
          .maxLines(2)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
          .width('100%')
      }

      if (this.lastMessage.length > 0) {
        Text(this.lastMessage)
          .fontSize(12)
          .fontFamily(this.appFontFamily)
          .fontColor(this.color('text_secondary'))
          .width('100%')
      }
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
    .shadow({ radius: SettingsPanelSurfaceHelper.getRadius(this.themeState.currentTheme) + 4, color: SettingsPanelSurfaceHelper.getShadowColor(this.themeState.currentTheme), offsetX: 0, offsetY: 8 })
  }

  @Builder
  private buildAgentKitCard() {
    Column({ space: 10 }) {
      Text('AgentKit 接力')
        .fontSize(16)
        .fontWeight(FontWeight.Medium)
        .fontFamily(this.appFontFamily)
        .fontColor(this.color('text_primary'))
        .alignSelf(ItemAlign.Start)

      Text('导出的维护包会包含 source.json、manifest 和 AGENT_GUIDE.md。Agent 可以据此同步你的仓库，或整理成提交给漫匣官方仓库的 PR。')
        .fontSize(13)
        .fontFamily(this.appFontFamily)
        .fontColor(this.color('text_secondary'))
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
    .shadow({ radius: SettingsPanelSurfaceHelper.getRadius(this.themeState.currentTheme) + 4, color: SettingsPanelSurfaceHelper.getShadowColor(this.themeState.currentTheme), offsetX: 0, offsetY: 8 })
  }

  @Builder
  private buildActionButton(label: string, symbol: Resource, accent: ResourceColor, action: () => void) {
    Button() {
      Row({ space: 6 }) {
        SymbolGlyph(symbol)
          .fontSize(16)
          .fontColor([accent])
        Text(this.isBusy ? '处理中' : label)
          .fontSize(13)
          .fontFamily(this.appFontFamily)
          .fontColor(this.color('text_primary'))
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
      }
      .justifyContent(FlexAlign.Center)
      .width('100%')
    }
    .enabled(!this.isBusy)
    .layoutWeight(1)
    .height(40)
    .borderRadius(8)
    .backgroundColor(this.color('button_background'))
    .border({ width: 1, color: this.color('divider') })
    .onClick(action)
  }
}
