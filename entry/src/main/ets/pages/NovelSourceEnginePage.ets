/**
 * 小说书源引擎页面
 * 管理用户自管 Legado 书源索引与 Legado WebView 运行时资产。
 */

import { HdsNavDestination } from '@kit.UIDesignKit';
import { common } from '@kit.AbilityKit';
import { logger } from 'manxia_core/src/main/ets/Utils/Logger';
import { PageLifecycleManager } from 'manxia_core/src/main/ets/Framework/Lifecycle/index';
import { ThemeAwareState, ThemeAwareHelper } from 'manxia_theme/src/main/ets/Framework/Components/ThemeAware';
import { FontAwareHelper, FontAwareState } from '../Framework/Components/FontAware';
import { ThemeManager, ThemeType } from 'manxia_theme/src/main/ets/Framework/Managers/ThemeManager';
import { GlobalBackgroundLayerMode } from 'manxia_theme/src/main/ets/Framework/Components/GlobalBackgroundLayer';
import { SharedPageBackgroundLayer } from '../Framework/Components/SharedPageBackgroundLayer';
import { SettingsImmersiveTitleBar } from './settings/SettingsImmersiveTitleBar';
import { SettingsPageTitleBarManager } from 'manxia_features_ui/src/main/ets/pages/settings/SettingsPageTitleBarManager';
import { SettingsPanelSurfaceHelper } from 'manxia_features_ui/src/main/ets/pages/settings/SettingsPanelSurfaceHelper';
import {
  DEFAULT_NOVEL_SOURCE_REPOSITORY_URL,
  getNovelSourceRepositoryManager,
  NovelSourceRepositoryEntry,
  NovelSourceRepositoryUpdateStatus,
  NovelSourceRepositorySyncProgressCallback,
  NovelSourceSavedRepository
} from '../Framework/Novel/NovelSourceRepositoryManager';
import {
  DEFAULT_LEGADO_RUNTIME_REPOSITORY_URL,
  getLegadoRuntimeAssetManager,
  LegadoRuntimeActiveStatus,
  LegadoRuntimeRepositoryUpdateStatus,
  LegadoRuntimeSyncProgressCallback
} from '../Framework/Novel/LegadoRuntimeAssetManager';
import {
  getVersionHistoryManager,
  MANXIA_LEGADO_RUNTIME_REPOSITORY_KEY,
  MANXIA_LEGADO_SOURCES_REPOSITORY_KEY,
  VersionRepositoryVersionMarker
} from '../Framework/Managers/VersionHistoryManager';

const TAG = 'NovelSourceEnginePage';

@Component
export struct NovelSourceEnginePage {
  @Consume('NavPathStack') pathStack: NavPathStack;
  @State themeState: ThemeAwareState = new ThemeAwareState();
  @State fontState: FontAwareState = new FontAwareState();
  @StorageLink('appFontFamily') appFontFamily: string = 'HarmonyOS Sans';
  @StorageLink('legadoSourceEngineSourceUpdateAvailable') sourceUpdateAvailable: boolean = false;
  @StorageLink('legadoSourceEngineRuntimeUpdateAvailable') runtimeUpdateAvailable: boolean = false;
  @StorageProp('statusBarHeight') statusBarHeight: number = 0;
  @StorageProp('navigationBarHeight') navigationBarHeight: number = 0;

  @State sourceRepositoryUrl: string = DEFAULT_NOVEL_SOURCE_REPOSITORY_URL;
  @State runtimeRepositoryUrl: string = DEFAULT_LEGADO_RUNTIME_REPOSITORY_URL;
  @State savedRepositories: NovelSourceSavedRepository[] = [];
  @State repositorySources: NovelSourceRepositoryEntry[] = [];
  @State runtimeStatusText: string = '未安装云端运行时';
  @State runtimeVersionText: string = '内置 rawfile';
  @State runtimeHealthText: string = '使用内置回退';
  @State runtimeActivatedAtText: string = '未安装云端运行时';
  @State runtimeLocalVersionText: string = '未记录';
  @State runtimeLatestVersionText: string = '未检查';
  @State runtimeVersionCheckText: string = '未检查';
  @State sourceLocalVersionText: string = '未记录';
  @State sourceLatestVersionText: string = '未检查';
  @State sourceVersionCheckText: string = '未检查';
  @State progress: number = 0;
  @State progressMessage: string = '等待操作';
  @State logs: string[] = [];
  @State isSyncing: boolean = false;
  @State isRefreshing: boolean = false;

  private themeManager: ThemeManager = ThemeManager.getInstance();
  private lifecycle = new PageLifecycleManager('NovelSourceEnginePage', { enableDebug: true });
  private componentId: string = `NovelSourceEnginePage_${Date.now()}`;

  aboutToAppear(): void {
    ThemeAwareHelper.initializeThemeAware(this.componentId, this.themeState, (theme: ThemeType) => {
      logger.info(TAG, `主题切换: ${theme}`);
    });
    FontAwareHelper.initializeFontAware(this.componentId, this.fontState, (newState: FontAwareState) => {
      this.fontState = newState;
    });
    void this.refreshState();
  }

  aboutToDisappear(): void {
    this.lifecycle.destroy();
    ThemeAwareHelper.cleanupThemeAware(this.componentId);
    FontAwareHelper.cleanupFontAware(this.componentId);
  }

  private async ensureManagers(): Promise<boolean> {
    try {
      const uiContext = this.getUIContext();
      if (uiContext === undefined || uiContext === null) {
        this.getUIContext().getPromptAction().showToast({ message: '无法获取页面上下文' });
        return false;
      }
      const hostContext = uiContext.getHostContext() as common.UIAbilityContext;
      if (hostContext === undefined || hostContext === null) {
        this.getUIContext().getPromptAction().showToast({ message: '无法获取应用上下文' });
        return false;
      }
      await getNovelSourceRepositoryManager().initialize(hostContext);
      getLegadoRuntimeAssetManager().initialize(hostContext);
      await getVersionHistoryManager().initialize(hostContext);
      return true;
    } catch (error) {
      const message = `书源引擎初始化失败: ${String(error)}`;
      logger.warn(TAG, message);
      this.getUIContext().getPromptAction().showToast({ message: message });
      return false;
    }
  }

  private async refreshState(): Promise<void> {
    if (this.isRefreshing) {
      return;
    }
    this.isRefreshing = true;
    const ready = await this.ensureManagers();
    if (!ready) {
      this.isRefreshing = false;
      return;
    }
    try {
      const sourceRepositoryManager = getNovelSourceRepositoryManager();
      const runtimeAssetManager = getLegadoRuntimeAssetManager();
      this.savedRepositories = sourceRepositoryManager.getSavedRepositories();
      this.repositorySources = sourceRepositoryManager.getRepositorySources();
      this.applyRuntimeStatus(runtimeAssetManager.getActiveRuntimeStatus());
      this.applyUpdateStatuses(
        sourceRepositoryManager.getRepositoryUpdateStatus(),
        runtimeAssetManager.getRuntimeUpdateStatus()
      );
      this.refreshVersionMarkers();
    } catch (error) {
      logger.warn(TAG, `刷新书源引擎状态失败: ${String(error)}`);
    }
    this.isRefreshing = false;
  }

  private applyRuntimeStatus(runtimeStatus: LegadoRuntimeActiveStatus): void {
    if (runtimeStatus.installed) {
      const versionText = this.normalizeVersionText(runtimeStatus.version);
      this.runtimeStatusText = `云端 active · ${runtimeStatus.healthOk ? '健康' : '异常'}`;
      this.runtimeVersionText = `${versionText} · code ${runtimeStatus.code} · API ${runtimeStatus.runtimeApi}`;
      this.runtimeHealthText = runtimeStatus.message.trim().length > 0
        ? `${runtimeStatus.healthOk ? '健康' : '异常'} · ${runtimeStatus.message}`
        : (runtimeStatus.healthOk ? '健康检查通过' : '健康检查异常');
      this.runtimeActivatedAtText = this.formatTime(runtimeStatus.updatedAt);
      return;
    }

    this.runtimeStatusText = '内置 rawfile 回退';
    this.runtimeVersionText = '内置 rawfile（未声明云端 manifest 版本）';
    this.runtimeHealthText = runtimeStatus.message.trim().length > 0 ? runtimeStatus.message : '未安装云端运行时';
    this.runtimeActivatedAtText = '未安装云端运行时';
  }

  private normalizeVersionText(version: string): string {
    const trimmed = version.trim();
    if (trimmed.length === 0) {
      return 'v未知';
    }
    if (trimmed.startsWith('v') || trimmed.startsWith('V')) {
      return trimmed;
    }
    return `v${trimmed}`;
  }

  private applyUpdateStatuses(
    sourceStatus: NovelSourceRepositoryUpdateStatus,
    runtimeStatus: LegadoRuntimeRepositoryUpdateStatus
  ): void {
    this.sourceUpdateAvailable = sourceStatus.hasUpdate;
    this.runtimeUpdateAvailable = runtimeStatus.hasUpdate;
    AppStorage.setOrCreate('legadoSourceEngineSourceUpdateAvailable', sourceStatus.hasUpdate);
    AppStorage.setOrCreate('legadoSourceEngineRuntimeUpdateAvailable', runtimeStatus.hasUpdate);

    this.sourceLatestVersionText = this.formatLatestCommitText(
      sourceStatus.latestCommitShortSha,
      sourceStatus.latestCommitDate
    );
    this.runtimeLatestVersionText = this.formatLatestCommitText(
      runtimeStatus.latestCommitShortSha,
      runtimeStatus.latestCommitDate
    );
    this.sourceVersionCheckText = this.formatSourceUpdateCheckText(sourceStatus);
    this.runtimeVersionCheckText = this.formatRuntimeUpdateCheckText(runtimeStatus);
  }

  private refreshVersionMarkers(): void {
    const versionManager = getVersionHistoryManager();
    const sourceMarker: VersionRepositoryVersionMarker | null =
      versionManager.getRepositoryVersionMarker(MANXIA_LEGADO_SOURCES_REPOSITORY_KEY);
    const runtimeMarker: VersionRepositoryVersionMarker | null =
      versionManager.getRepositoryVersionMarker(MANXIA_LEGADO_RUNTIME_REPOSITORY_KEY);
    this.sourceLocalVersionText = this.formatVersionMarkerText(sourceMarker);
    this.runtimeLocalVersionText = this.formatVersionMarkerText(runtimeMarker);
    this.sourceVersionCheckText = this.normalizeCheckTextForLocalMarker(this.sourceVersionCheckText, sourceMarker);
    this.runtimeVersionCheckText = this.normalizeCheckTextForLocalMarker(this.runtimeVersionCheckText, runtimeMarker);
  }

  private appendLog(level: string, message: string): void {
    const nextLogs = this.logs.slice();
    nextLogs.push(`[${level}] ${message}`);
    while (nextLogs.length > 100) {
      nextLogs.shift();
    }
    this.logs = nextLogs;
  }

  private buildSourceProgressCallback(): NovelSourceRepositorySyncProgressCallback {
    const callback: NovelSourceRepositorySyncProgressCallback = {
      onProgress: (current: number, total: number, message: string) => {
        this.progress = total > 0 ? Math.floor((current / total) * 100) : current;
        this.progressMessage = message;
      },
      onLog: (level: 'info' | 'warn' | 'error', message: string) => {
        this.appendLog(level, message);
      }
    };
    return callback;
  }

  private buildRuntimeProgressCallback(): LegadoRuntimeSyncProgressCallback {
    const callback: LegadoRuntimeSyncProgressCallback = {
      onProgress: (current: number, total: number, message: string) => {
        this.progress = total > 0 ? Math.floor((current / total) * 100) : current;
        this.progressMessage = message;
      },
      onLog: (level: 'info' | 'warn' | 'error', message: string) => {
        this.appendLog(level, message);
      }
    };
    return callback;
  }

  private getUpdateHintText(): string {
    if (this.sourceUpdateAvailable && this.runtimeUpdateAvailable) {
      return '默认书源索引和运行时仓库检测到更新';
    }
    if (this.sourceUpdateAvailable) {
      return '默认书源索引检测到更新';
    }
    if (this.runtimeUpdateAvailable) {
      return '官方运行时仓库检测到更新';
    }
    return '当前没有待处理的书源引擎更新提示';
  }

  private async checkVersionUpdates(): Promise<void> {
    if (this.isSyncing || this.isRefreshing) {
      return;
    }
    const ready = await this.ensureManagers();
    if (!ready) {
      return;
    }

    this.isRefreshing = true;
    this.progress = 0;
    this.progressMessage = '正在检查仓库版本...';
    this.appendLog('info', '开始检查默认书源索引与运行时仓库版本');
    try {
      const sourceStatus: NovelSourceRepositoryUpdateStatus =
        await getNovelSourceRepositoryManager().checkOfficialRepositoryUpdateIfNeeded(true);
      const runtimeStatus: LegadoRuntimeRepositoryUpdateStatus =
        await getLegadoRuntimeAssetManager().checkOfficialRepositoryUpdateIfNeeded(true);
      this.applyUpdateStatuses(sourceStatus, runtimeStatus);
      this.refreshVersionMarkers();
      this.progress = 100;
      this.progressMessage = '版本检查完成';
      this.appendLog('info', this.getUpdateHintText());
      this.getUIContext().getPromptAction().showToast({ message: this.getUpdateHintText() });
    } catch (error) {
      const message = `版本检查失败: ${String(error)}`;
      this.progressMessage = message;
      this.appendLog('error', message);
      this.getUIContext().getPromptAction().showToast({ message: message });
    }
    this.isRefreshing = false;
  }

  private async syncSourceRepository(): Promise<void> {
    if (this.isSyncing) {
      return;
    }
    if (this.sourceRepositoryUrl.trim().length === 0) {
      this.getUIContext().getPromptAction().showToast({ message: '请输入自管书源索引地址' });
      return;
    }
    const ready = await this.ensureManagers();
    if (!ready) {
      return;
    }

    this.isSyncing = true;
    this.progress = 0;
    this.progressMessage = '准备同步自管书源索引...';
    this.appendLog('info', '开始同步自管书源索引');
    try {
      const result = await getNovelSourceRepositoryManager().syncRepositoryFromUrl(
        this.sourceRepositoryUrl,
        undefined,
        this.buildSourceProgressCallback()
      );
      this.appendLog(result.success ? 'info' : 'warn', result.message);
      await this.refreshState();
      this.getUIContext().getPromptAction().showToast({ message: result.message });
    } catch (error) {
      const message = `自管书源索引同步失败: ${String(error)}`;
      this.appendLog('error', message);
      this.getUIContext().getPromptAction().showToast({ message: message });
    }
    this.isSyncing = false;
  }

  private async syncRuntimeRepository(): Promise<void> {
    if (this.isSyncing) {
      return;
    }
    if (this.runtimeRepositoryUrl.trim().length === 0) {
      this.getUIContext().getPromptAction().showToast({ message: '请输入运行时仓库地址' });
      return;
    }
    const ready = await this.ensureManagers();
    if (!ready) {
      return;
    }

    this.isSyncing = true;
    this.progress = 0;
    this.progressMessage = '准备同步运行时资产...';
    this.appendLog('info', '开始同步运行时资产');
    try {
      const result = await getLegadoRuntimeAssetManager().syncRuntimeFromUrl(
        this.runtimeRepositoryUrl,
        this.buildRuntimeProgressCallback()
      );
      this.appendLog(result.success ? 'info' : 'warn', result.message);
      await this.refreshState();
      this.getUIContext().getPromptAction().showToast({ message: result.message });
    } catch (error) {
      const message = `运行时同步失败: ${String(error)}`;
      this.appendLog('error', message);
      this.getUIContext().getPromptAction().showToast({ message: message });
    }
    this.isSyncing = false;
  }

  private deleteRepository(repoId: string): void {
    const deleted = getNovelSourceRepositoryManager().deleteRepository(repoId);
    if (deleted) {
      void this.refreshState();
      this.getUIContext().getPromptAction().showToast({ message: '已删除仓库记录' });
      return;
    }
    this.getUIContext().getPromptAction().showToast({ message: '删除仓库记录失败' });
  }

  private rollbackRuntime(): void {
    try {
      const ok = getLegadoRuntimeAssetManager().rollbackRuntime();
      void this.refreshState();
      this.getUIContext().getPromptAction().showToast({ message: ok ? '运行时已回滚' : '没有可回滚的运行时' });
    } catch (error) {
      this.getUIContext().getPromptAction().showToast({ message: `运行时回滚失败: ${String(error)}` });
    }
  }

  private formatTime(timestamp: number): string {
    if (timestamp <= 0) {
      return '未同步';
    }
    const date = new Date(timestamp);
    return `${date.getFullYear()}-${this.padTimePart(date.getMonth() + 1)}-${this.padTimePart(date.getDate())} ${this.padTimePart(date.getHours())}:${this.padTimePart(date.getMinutes())}`;
  }

  private formatVersionMarkerText(marker: VersionRepositoryVersionMarker | null): string {
    if (marker === null) {
      return '未记录同步版本';
    }
    const commitText = this.formatCommitText(marker.commitShortSha, marker.commitDate);
    const markedAtText = this.formatTime(marker.markedAt);
    return `${commitText} · 标记于 ${markedAtText}`;
  }

  private formatLatestCommitText(shortSha: string, date: string): string {
    const trimmedSha = shortSha.trim();
    if (trimmedSha.length === 0) {
      return '未检查';
    }
    return this.formatCommitText(trimmedSha, date);
  }

  private formatCommitText(shortSha: string, date: string): string {
    const trimmedSha = shortSha.trim();
    const dateText = this.formatRepositoryDateText(date);
    if (trimmedSha.length === 0) {
      return dateText.length > 0 ? dateText : '未记录';
    }
    if (dateText.length === 0) {
      return trimmedSha;
    }
    return `${trimmedSha} · ${dateText}`;
  }

  private formatRepositoryDateText(value: string): string {
    const trimmed = value.trim();
    if (trimmed.length === 0) {
      return '';
    }
    if (trimmed.length >= 16) {
      return trimmed.substring(0, 16).replace('T', ' ');
    }
    return trimmed;
  }

  private formatSourceUpdateCheckText(status: NovelSourceRepositoryUpdateStatus): string {
    return this.formatUpdateCheckText(
      status.lastCheckAt,
      status.hasUpdate,
      status.canCheck,
      status.errorMessage
    );
  }

  private formatRuntimeUpdateCheckText(status: LegadoRuntimeRepositoryUpdateStatus): string {
    return this.formatUpdateCheckText(
      status.lastCheckAt,
      status.hasUpdate,
      status.canCheck,
      status.errorMessage
    );
  }

  private formatUpdateCheckText(lastCheckAt: number, hasUpdate: boolean, canCheck: boolean, errorMessage: string): string {
    if (lastCheckAt <= 0) {
      return '尚未检查';
    }
    const checkTime = this.formatTime(lastCheckAt);
    const errorText = errorMessage.trim();
    if (!canCheck) {
      if (errorText.length > 0) {
        return `检查失败 · ${errorText}`;
      }
      return `检查失败 · ${checkTime}`;
    }
    return `${hasUpdate ? '有更新' : '已是最新'} · ${checkTime}`;
  }

  private normalizeCheckTextForLocalMarker(
    checkText: string,
    marker: VersionRepositoryVersionMarker | null
  ): string {
    if (marker !== null) {
      return checkText;
    }
    if (checkText.startsWith('已是最新')) {
      return '已检查 · 尚未记录本地版本';
    }
    return checkText;
  }

  private padTimePart(value: number): string {
    return value < 10 ? `0${value}` : String(value);
  }

  private getActionButtonBackground(): ResourceColor {
    return SettingsPanelSurfaceHelper.getBackground(this.themeState.currentTheme);
  }

  private getActionButtonBorderColor(): ResourceColor {
    return SettingsPanelSurfaceHelper.getBorderColor(this.themeState.currentTheme);
  }

  private getActionButtonTextColor(): ResourceColor {
    return ThemeAwareHelper.getTestManagementThemedColor('text_primary', this.themeState.currentTheme);
  }

  build() {
    HdsNavDestination() {
      Stack() {
        SharedPageBackgroundLayer({
          defaultBackgroundColor: ThemeAwareHelper.getTestManagementThemedColor('background', this.themeState.currentTheme),
          mode: GlobalBackgroundLayerMode.IMMERSIVE
        })
          .width('100%')
          .height('100%')
          .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.TOP, SafeAreaEdge.BOTTOM])
          .animation(ThemeAwareHelper.getThemeTransitionAnimation())

        Column() {
          Scroll() {
            Column({ space: 14 }) {
              Blank().height(SettingsPageTitleBarManager.getContentTopPadding(this.statusBarHeight))
              this.buildNoticeCard()
              this.buildSourceRepositoryCard()
              this.buildRuntimeCard()
              this.buildStatusCard()
            }
            .width('100%')
            .padding({ left: 16, right: 16, bottom: 24 + this.navigationBarHeight })
          }
          .width('100%')
          .height('100%')
          .scrollBar(BarState.Auto)
          .edgeEffect(EdgeEffect.Spring)
        }
        .width('100%')
        .height('100%')
        .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.TOP, SafeAreaEdge.BOTTOM])

        SettingsImmersiveTitleBar({
          themeState: this.themeState,
          title: '书源引擎',
          appFontFamily: this.appFontFamily
        })
      }
      .width('100%')
      .height('100%')
    }
    .hideTitleBar(true)
    .ignoreLayoutSafeArea([LayoutSafeAreaType.SYSTEM], [LayoutSafeAreaEdge.TOP, LayoutSafeAreaEdge.BOTTOM])
    .backgroundColor(Color.Transparent)
    .onReady(() => {
      logger.info(TAG, 'HdsNavDestination.onReady 已触发');
    })
  }

  @Builder
  private buildNoticeCard() {
    Column({ space: 8 }) {
      Row({ space: 10 }) {
        SymbolGlyph($r('sys.symbol.info_circle'))
          .fontSize(20)
          .fontColor([ThemeAwareHelper.getTestManagementThemedColor('accent_primary', this.themeState.currentTheme)])
        Text(this.getUpdateHintText())
          .fontSize(13)
          .fontFamily(this.appFontFamily)
          .fontColor(this.sourceUpdateAvailable || this.runtimeUpdateAvailable
            ? ThemeAwareHelper.getTestManagementThemedColor('color_warning', this.themeState.currentTheme)
            : ThemeAwareHelper.getTestManagementThemedColor('text_secondary', this.themeState.currentTheme))
          .maxLines(2)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
          .layoutWeight(1)

        Button(this.isRefreshing ? '检查中' : '检查版本')
          .height(30)
          .borderRadius(8)
          .fontSize(12)
          .fontFamily(this.appFontFamily)
          .fontColor(this.getActionButtonTextColor())
          .backgroundColor(this.getActionButtonBackground())
          .border({ width: 1, color: this.getActionButtonBorderColor() })
          .enabled(!this.isSyncing && !this.isRefreshing)
          .onClick(() => {
            void this.checkVersionUpdates();
          })
      }
      .width('100%')

      Text('漫匣不提供、不内置、不维护任何书源；这里只负责同步用户自行维护或导入的 Legado 兼容索引，以及更新 Legado 兼容层运行时资产。')
        .fontSize(12)
        .fontFamily(this.appFontFamily)
        .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_secondary', this.themeState.currentTheme))
        .lineHeight(18)
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
    .border({ width: SettingsPanelSurfaceHelper.getBorderWidth(this.themeState.currentTheme), color: SettingsPanelSurfaceHelper.getBorderColor(this.themeState.currentTheme) })
  }

  @Builder
  private buildSourceRepositoryCard() {
    Column({ space: 12 }) {
      this.buildSectionHeader('自管书源索引', `${this.repositorySources.length} 个索引书源`)
      this.buildVersionInfoRow('本地标记', this.sourceLocalVersionText)
      this.buildVersionInfoRow('远端最新', this.sourceLatestVersionText)
      this.buildVersionInfoRow('检查状态', this.sourceVersionCheckText)

      TextInput({ placeholder: '用户自管 index.main.json 地址', text: this.sourceRepositoryUrl })
        .width('100%')
        .height(44)
        .backgroundColor(this.getActionButtonBackground())
        .border({ width: 1, color: this.getActionButtonBorderColor() })
        .borderRadius(8)
        .padding({ left: 12, right: 12 })
        .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_primary', this.themeState.currentTheme))
        .placeholderColor(ThemeAwareHelper.getTestManagementThemedColor('text_muted', this.themeState.currentTheme))
        .onChange((value: string) => {
          this.sourceRepositoryUrl = value;
        })

      Button(this.isSyncing ? '同步中...' : '同步自管索引')
        .width('100%')
        .height(38)
        .borderRadius(8)
        .fontFamily(this.appFontFamily)
        .fontColor(this.getActionButtonTextColor())
        .backgroundColor(this.getActionButtonBackground())
        .border({ width: 1, color: this.getActionButtonBorderColor() })
        .enabled(!this.isSyncing)
        .onClick(() => {
          void this.syncSourceRepository();
        })

      if (this.savedRepositories.length > 0) {
        Column({ space: 8 }) {
          ForEach(this.savedRepositories, (repo: NovelSourceSavedRepository) => {
            this.buildSavedRepositoryRow(repo)
          }, (repo: NovelSourceSavedRepository): string => repo.id)
        }
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
  }

  @Builder
  private buildRuntimeCard() {
    Column({ space: 12 }) {
      this.buildSectionHeader('运行时资产', this.runtimeStatusText)
      this.buildVersionInfoRow('当前版本', this.runtimeVersionText)
      this.buildVersionInfoRow('运行状态', this.runtimeHealthText)
      this.buildVersionInfoRow('激活时间', this.runtimeActivatedAtText)
      this.buildVersionInfoRow('本地标记', this.runtimeLocalVersionText)
      this.buildVersionInfoRow('远端最新', this.runtimeLatestVersionText)
      this.buildVersionInfoRow('检查状态', this.runtimeVersionCheckText)

      TextInput({ placeholder: '运行时仓库 index.main.json 地址', text: this.runtimeRepositoryUrl })
        .width('100%')
        .height(44)
        .backgroundColor(this.getActionButtonBackground())
        .border({ width: 1, color: this.getActionButtonBorderColor() })
        .borderRadius(8)
        .padding({ left: 12, right: 12 })
        .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_primary', this.themeState.currentTheme))
        .placeholderColor(ThemeAwareHelper.getTestManagementThemedColor('text_muted', this.themeState.currentTheme))
        .onChange((value: string) => {
          this.runtimeRepositoryUrl = value;
        })

      Row({ space: 10 }) {
        Button(this.isSyncing ? '同步中...' : '同步运行时')
          .layoutWeight(1)
          .height(38)
          .borderRadius(8)
          .fontFamily(this.appFontFamily)
          .fontColor(this.getActionButtonTextColor())
          .backgroundColor(this.getActionButtonBackground())
          .border({ width: 1, color: this.getActionButtonBorderColor() })
          .enabled(!this.isSyncing)
          .onClick(() => {
            void this.syncRuntimeRepository();
          })
        Button('回滚')
          .layoutWeight(1)
          .height(38)
          .borderRadius(8)
          .fontFamily(this.appFontFamily)
          .fontColor(this.getActionButtonTextColor())
          .backgroundColor(this.getActionButtonBackground())
          .border({ width: 1, color: this.getActionButtonBorderColor() })
          .enabled(!this.isSyncing)
          .onClick(() => {
            this.rollbackRuntime();
          })
      }
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
  }

  @Builder
  private buildStatusCard() {
    Column({ space: 10 }) {
      this.buildSectionHeader('同步状态', this.progressMessage)
      Progress({ value: this.progress, total: 100, type: ProgressType.Linear })
        .width('100%')
        .height(6)
        .color(ThemeAwareHelper.getTestManagementThemedColor('accent_primary', this.themeState.currentTheme))

      Column({ space: 4 }) {
        if (this.logs.length === 0) {
          Text('暂无同步日志')
            .fontSize(12)
            .fontFamily(this.appFontFamily)
            .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_tertiary', this.themeState.currentTheme))
        } else {
          ForEach(this.logs, (item: string, index: number) => {
            Text(item)
              .fontSize(11)
              .fontFamily(this.appFontFamily)
              .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_tertiary', this.themeState.currentTheme))
              .maxLines(2)
              .textOverflow({ overflow: TextOverflow.Ellipsis })
          }, (item: string, index: number): string => `${index}_${item}`)
        }
      }
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
  }

  @Builder
  private buildSectionHeader(title: string, subtitle: string) {
    Row() {
      Column({ space: 3 }) {
        Text(title)
          .fontSize(16)
          .fontWeight(FontWeight.Medium)
          .fontFamily(this.appFontFamily)
          .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_primary', this.themeState.currentTheme))
        Text(subtitle)
          .fontSize(12)
          .fontFamily(this.appFontFamily)
          .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_secondary', this.themeState.currentTheme))
          .maxLines(2)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
      }
      .alignItems(HorizontalAlign.Start)
      .layoutWeight(1)

      Button('刷新')
        .height(30)
        .borderRadius(8)
        .fontSize(12)
        .fontFamily(this.appFontFamily)
        .fontColor(this.getActionButtonTextColor())
        .backgroundColor(this.getActionButtonBackground())
        .border({ width: 1, color: this.getActionButtonBorderColor() })
        .enabled(!this.isSyncing && !this.isRefreshing)
        .onClick(() => {
          void this.refreshState();
        })
    }
    .width('100%')
  }

  @Builder
  private buildVersionInfoRow(label: string, value: string) {
    Row({ space: 10 }) {
      Text(label)
        .width(72)
        .fontSize(12)
        .fontFamily(this.appFontFamily)
        .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_tertiary', this.themeState.currentTheme))
      Text(value)
        .fontSize(12)
        .fontFamily(this.appFontFamily)
        .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_secondary', this.themeState.currentTheme))
        .maxLines(2)
        .textOverflow({ overflow: TextOverflow.Ellipsis })
        .layoutWeight(1)
    }
    .width('100%')
  }

  @Builder
  private buildSavedRepositoryRow(repo: NovelSourceSavedRepository) {
    Row({ space: 8 }) {
      Column({ space: 2 }) {
        Text(repo.name)
          .fontSize(13)
          .fontFamily(this.appFontFamily)
          .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_primary', this.themeState.currentTheme))
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
        Text(`${repo.sourceCount} 个 · ${this.formatTime(repo.lastSync)}`)
          .fontSize(11)
          .fontFamily(this.appFontFamily)
          .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_tertiary', this.themeState.currentTheme))
      }
      .layoutWeight(1)

      Button('删除')
        .height(30)
        .borderRadius(8)
        .fontSize(12)
        .fontFamily(this.appFontFamily)
        .fontColor(this.getActionButtonTextColor())
        .backgroundColor(this.getActionButtonBackground())
        .border({ width: 1, color: this.getActionButtonBorderColor() })
        .enabled(!this.isSyncing)
        .onClick(() => {
          this.deleteRepository(repo.id);
        })
    }
    .width('100%')
  }
}
