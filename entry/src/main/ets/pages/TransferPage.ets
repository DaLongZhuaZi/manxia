import { HdsNavDestination } from '@kit.UIDesignKit';
import { common } from '@kit.AbilityKit';
import { pasteboard } from '@kit.BasicServicesKit';
import { uniformTypeDescriptor as utd } from '@kit.ArkData';
import { systemShare } from '@kit.ShareKit';
import { logger } from '../Utils/Logger';
import { ThemeAwareHelper, ThemeAwareState } from '../Framework/Components/ThemeAware';
import { SettingsImmersiveTitleBar } from './settings/SettingsImmersiveTitleBar';
import { SettingsPageTitleBarManager } from './settings/SettingsPageTitleBarManager';
import { SettingsPanelSurfaceHelper } from './settings/SettingsPanelSurfaceHelper';
import { GlobalBackgroundLayerMode } from '../Framework/Components/GlobalBackgroundLayer';
import { SharedPageBackgroundLayer } from '../Framework/Components/SharedPageBackgroundLayer';
import { getTransferConfigManager, TransferConfigManager } from '../Framework/Managers/TransferConfigManager';
import { getLocalTransferServerService, LocalTransferServerService } from '../Framework/Services/LocalTransferServerService';
import { getTransferUploadStoreService, TransferUploadStoreService } from '../Framework/Services/TransferUploadStoreService';
import {
  TransferConfig,
  TransferLocalAddress,
  TransferRuntimePhase,
  TransferServerStatus,
  TransferServerRuntime,
  TransferUploadRecord,
  cloneTransferConfig,
  cloneTransferLocalAddress,
  cloneTransferUploadRecords,
  createDefaultTransferConfig
} from '../Models/TransferModels';
import type { NetworkFolderImportCategory } from '../Models/NetworkFolderModels';

const TAG = 'TransferPage';
const TRANSFER_ACCENT_COLOR: string = '#0F8A6C';
const TRANSFER_INFO_COLOR: string = '#1F7AE0';
const TRANSFER_DANGER_COLOR: string = '#C74848';
const ACTION_STYLE_NEUTRAL: number = 0;
const ACTION_STYLE_PRIMARY: number = 1;
const ACTION_STYLE_INFO: number = 2;
const ACTION_STYLE_DANGER: number = 3;

type TransferThemeColorType = 'background' | 'panel_background' | 'comp_background_tertiary' |
  'comp_background_secondary' | 'text_primary' | 'text_secondary' | 'text_muted' | 'text_white' |
  'text_black' | 'button_secondary' | 'button_text_secondary' | 'icon_primary' | 'accent_primary';

interface TransferNavigationPathParam {
  fromPage: string;
  timestamp: number;
}

interface TransferPageViewState {
  renderVersion: number;
  status: TransferServerStatus;
  phase: TransferRuntimePhase;
  infoMessage: string;
  lastError: string;
  backgroundRunning: boolean;
  activePort: number;
  webSocketPort: number;
  localAddresses: TransferLocalAddress[];
  hasSession: boolean;
  pairCode: string;
  clientName: string;
  clientIp: string;
  expiresAt: number;
  primaryAddressText: string;
  pairCodeText: string;
  pairedClientText: string;
  sessionExpireText: string;
  connectionGuideText: string;
  qrCodeReady: boolean;
  qrCodeValue: string;
  quickAssistReady: boolean;
  config: TransferConfig;
  backgroundTransferText: string;
  wsEnabledText: string;
  recentUploads: TransferUploadRecord[];
  hasRecentUploads: boolean;
  isBusy: boolean;
}

function createInitialTransferPageViewState(): TransferPageViewState {
  const runtime: TransferServerRuntime = {
    status: 'stopped',
    phase: 'scaffold',
    activePort: 0,
    webSocketPort: 0,
    startedAt: 0,
    lastError: '',
    infoMessage: '服务未启动。',
    backgroundRunning: false,
    localAddresses: [],
    session: null
  };
  const uploads: TransferUploadRecord[] = [];
  return createTransferPageViewState(0, runtime, createDefaultTransferConfig(), uploads, false);
}

function createTransferPageViewState(
  renderVersion: number,
  runtime: TransferServerRuntime,
  config: TransferConfig,
  uploads: TransferUploadRecord[],
  isBusy: boolean
): TransferPageViewState {
  const localAddresses: TransferLocalAddress[] = cloneTransferLocalAddresses(runtime.localAddresses);
  const pairCode: string = runtime.session !== null ? runtime.session.pairCode : '';
  const clientName: string = runtime.session !== null ? runtime.session.clientName : '';
  const clientIp: string = runtime.session !== null ? runtime.session.clientIp : '';
  const expiresAt: number = runtime.session !== null ? runtime.session.expiresAt : 0;
  const hasSession: boolean = runtime.session !== null;
  const primaryAddress = getPrimaryTransferAddress(localAddresses);
  const primaryAddressText: string = primaryAddress === null ? '服务启动后会显示局域网访问地址' : primaryAddress.url;
  const pairCodeText: string = buildTransferPairCodeText(hasSession, pairCode);
  const qrCodeReady: boolean = runtime.status === 'running' && primaryAddress !== null;
  const quickAssistReady: boolean = runtime.status === 'running' && primaryAddress !== null && hasSession;
  const clonedConfig: TransferConfig = cloneTransferConfig(config);
  const recentUploads: TransferUploadRecord[] = cloneTransferUploadRecords(uploads);
  const viewState: TransferPageViewState = {
    renderVersion: renderVersion,
    status: runtime.status,
    phase: runtime.phase,
    infoMessage: runtime.infoMessage,
    lastError: runtime.lastError,
    backgroundRunning: runtime.backgroundRunning,
    activePort: runtime.activePort,
    webSocketPort: runtime.webSocketPort,
    localAddresses: localAddresses,
    hasSession: hasSession,
    pairCode: pairCode,
    clientName: clientName,
    clientIp: clientIp,
    expiresAt: expiresAt,
    primaryAddressText: primaryAddressText,
    pairCodeText: pairCodeText,
    pairedClientText: buildTransferPairedClientText(clientName, clientIp),
    sessionExpireText: buildTransferSessionExpireText(hasSession, runtime.status, expiresAt),
    connectionGuideText: buildTransferConnectionGuideText(runtime.status, primaryAddress, hasSession, pairCode),
    qrCodeReady: qrCodeReady,
    qrCodeValue: qrCodeReady && primaryAddress !== null ? primaryAddress.url : 'manxia://page/TransferPage',
    quickAssistReady: quickAssistReady,
    config: clonedConfig,
    backgroundTransferText: clonedConfig.allowBackgroundTransfer ? '允许' : '关闭',
    wsEnabledText: clonedConfig.wsEnabled ? '开启' : '关闭',
    recentUploads: recentUploads,
    hasRecentUploads: recentUploads.length > 0,
    isBusy: isBusy
  };
  return viewState;
}

function cloneTransferLocalAddresses(addresses: TransferLocalAddress[]): TransferLocalAddress[] {
  const result: TransferLocalAddress[] = [];
  for (const address of addresses) {
    result.push(cloneTransferLocalAddress(address));
  }
  return result;
}

function getPrimaryTransferAddress(addresses: TransferLocalAddress[]): TransferLocalAddress | null {
  if (addresses.length <= 0) {
    return null;
  }
  return addresses[0];
}

function buildTransferPairCodeText(hasSession: boolean, pairCode: string): string {
  if (!hasSession || pairCode.length <= 0) {
    return '------';
  }
  return pairCode;
}

function buildTransferConnectionGuideText(
  status: TransferServerStatus,
  primaryAddress: TransferLocalAddress | null,
  hasSession: boolean,
  pairCode: string
): string {
  if (status !== 'running' || primaryAddress === null || !hasSession) {
    return '请先在漫匣中启动局域网传书服务，再复制连接指引。';
  }
  const guideLines: string[] = [
    '漫匣局域网传书连接指引',
    `1. 在同一局域网浏览器打开：${primaryAddress.url}`,
    `2. 输入配对码：${pairCode}`,
    '3. 选择文件并开始上传',
    '4. 回到漫匣收件箱，确认文件已在设备上，再点击“继续导入”'
  ];
  return guideLines.join('\n');
}

function buildTransferPairedClientText(clientName: string, clientIp: string): string {
  if (clientName.length <= 0) {
    return '尚未配对';
  }
  if (clientIp.length > 0) {
    return `${clientName} (${clientIp})`;
  }
  return clientName;
}

function buildTransferSessionExpireText(
  hasSession: boolean,
  status: TransferServerStatus,
  expiresAt: number
): string {
  if (!hasSession || status !== 'running') {
    return '未启动';
  }
  const remainingMs = expiresAt - Date.now();
  if (remainingMs <= 0) {
    return '已过期';
  }
  const remainingSeconds = Math.floor(remainingMs / 1000);
  const minutes = Math.floor(remainingSeconds / 60);
  const seconds = remainingSeconds % 60;
  if (minutes > 0) {
    return `${minutes} 分 ${seconds} 秒后过期`;
  }
  return `${seconds} 秒后过期`;
}

function getTransferColor(type: TransferThemeColorType, themeState: ThemeAwareState): Resource {
  return ThemeAwareHelper.getTestManagementThemedColor(type, themeState.currentTheme);
}

@Component
struct TransferCardHeaderView {
  @Prop themeState: ThemeAwareState;
  @Prop title: string = '';
  @Prop subtitle: string = '';

  build() {
    Column({ space: 4 }) {
      Text(this.title)
        .fontSize(18)
        .fontWeight(FontWeight.Bold)
        .fontColor(getTransferColor('text_primary', this.themeState))
        .width('100%')
        .textAlign(TextAlign.Start)

      Text(this.subtitle)
        .fontSize(13)
        .fontColor(getTransferColor('text_secondary', this.themeState))
        .width('100%')
        .textAlign(TextAlign.Start)
    }
    .alignItems(HorizontalAlign.Start)
    .width('100%')
  }
}

@Component
struct TransferInfoRowView {
  @Prop themeState: ThemeAwareState;
  @Prop label: string = '';
  @Prop value: string = '';

  build() {
    Row() {
      Text(this.label)
        .fontSize(14)
        .fontColor(getTransferColor('text_secondary', this.themeState))

      Blank()

      Text(this.value)
        .fontSize(14)
        .fontWeight(FontWeight.Medium)
        .fontColor(getTransferColor('text_primary', this.themeState))
        .maxLines(3)
        .textOverflow({ overflow: TextOverflow.Ellipsis })
        .textAlign(TextAlign.End)
    }
    .width('100%')
    .padding({ left: 12, right: 12, top: 10, bottom: 10 })
    .backgroundColor(getTransferColor('comp_background_tertiary', this.themeState))
    .borderRadius(14)
    .clip(true)
  }
}

@Component
struct TransferEmphasisValueCardView {
  @Prop themeState: ThemeAwareState;
  @Prop title: string = '';
  @Prop value: string = '';
  @Prop hint: string = '';

  build() {
    Column({ space: 8 }) {
      Text(this.title)
        .fontSize(13)
        .fontColor(getTransferColor('text_secondary', this.themeState))
        .width('100%')
        .textAlign(TextAlign.Start)

      Text(this.value)
        .fontSize(22)
        .fontWeight(FontWeight.Bold)
        .fontColor(getTransferColor('text_primary', this.themeState))
        .width('100%')
        .textAlign(TextAlign.Start)
        .maxLines(4)
        .textOverflow({ overflow: TextOverflow.Ellipsis })

      Text(this.hint)
        .fontSize(12)
        .lineHeight(18)
        .fontColor(getTransferColor('text_secondary', this.themeState))
        .width('100%')
        .textAlign(TextAlign.Start)
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
    .borderRadius(20)
    .clip(true)
    .border({
      width: SettingsPanelSurfaceHelper.getBorderWidth(this.themeState.currentTheme),
      color: SettingsPanelSurfaceHelper.getBorderColor(this.themeState.currentTheme)
    })
    .shadow({
      radius: 18,
      color: SettingsPanelSurfaceHelper.getShadowColor(this.themeState.currentTheme),
      offsetX: 0,
      offsetY: 8
    })
  }
}

@Component
struct TransferPageContent {
  private readonly componentId: string = TAG;
  private readonly transferService: LocalTransferServerService = getLocalTransferServerService();
  private readonly configManager: TransferConfigManager = getTransferConfigManager();
  private readonly uploadStoreService: TransferUploadStoreService = getTransferUploadStoreService();
  private refreshTimer: number = -1;
  private isRefreshingUploads: boolean = false;

  @State themeState: ThemeAwareState = new ThemeAwareState();
  @StorageLink('appFontFamily') appFontFamily: string = 'HarmonyOS Sans';
  @StorageProp('statusBarHeight') statusBarHeight: number = 0;
  @StorageProp('navigationBarHeight') navigationBarHeight: number = 0;
  @State private isPageRefreshing: boolean = false;
  @State private pathStack: NavPathStack = new NavPathStack();
  @State private viewState: TransferPageViewState = createInitialTransferPageViewState();
  @State private heroStatus: TransferServerStatus = 'stopped';
  @State private heroAddressCount: number = 0;
  @State private heroBusy: boolean = false;
  @State private activeTabIndex: number = 0;
  @State private selectedUploadRecordIds: string[] = [];

  aboutToAppear(): void {
    void ThemeAwareHelper.initializeThemeAware(this.componentId, this.themeState, undefined, (newState: ThemeAwareState) => {
      this.themeState = newState;
    });
    this.refreshSnapshot();
    void this.refreshUploads();
    this.startRefreshTimer();
  }

  aboutToDisappear(): void {
    ThemeAwareHelper.cleanupThemeAware(this.componentId);
    this.stopRefreshTimer();
  }

  private color(type: TransferThemeColorType): Resource {
    return getTransferColor(type, this.themeState);
  }

  private getActionBackgroundColor(styleKind: number): ResourceColor {
    if (styleKind === ACTION_STYLE_PRIMARY) {
      return TRANSFER_ACCENT_COLOR;
    }
    if (styleKind === ACTION_STYLE_INFO) {
      return TRANSFER_INFO_COLOR;
    }
    if (styleKind === ACTION_STYLE_DANGER) {
      return TRANSFER_DANGER_COLOR;
    }
    return this.color('comp_background_tertiary');
  }

  private getActionForegroundColor(styleKind: number): ResourceColor {
    if (styleKind === ACTION_STYLE_NEUTRAL) {
      return this.color('text_primary');
    }
    return this.color('text_white');
  }

  private refreshSnapshot(): void {
    const runtime = this.transferService.getRuntimeState();
    const config = this.configManager.getConfig();
    this.applyPageSnapshot(runtime, config);
  }

  private applyPageSnapshot(runtime: TransferServerRuntime, config: TransferConfig): void {
    const nextViewState = createTransferPageViewState(
      this.viewState.renderVersion + 1,
      runtime,
      config,
      this.viewState.recentUploads,
      this.viewState.isBusy
    );
    this.commitViewState(nextViewState);
  }

  private commitViewState(nextViewState: TransferPageViewState): void {
    this.viewState = nextViewState;
    this.heroStatus = nextViewState.status;
    this.heroAddressCount = nextViewState.localAddresses.length;
    this.heroBusy = nextViewState.isBusy;
  }

  private setBusyState(isBusy: boolean): void {
    const runtime = this.transferService.getRuntimeState();
    const config = this.configManager.getConfig();
    const nextViewState = createTransferPageViewState(
      this.viewState.renderVersion + 1,
      runtime,
      config,
      this.viewState.recentUploads,
      isBusy
    );
    this.commitViewState(nextViewState);
  }

  private async refreshUploads(): Promise<void> {
    if (this.isRefreshingUploads) {
      return;
    }
    this.isRefreshingUploads = true;
    try {
      await this.uploadStoreService.consumePendingImportResult();
      const uploads = await this.uploadStoreService.getRecentUploads(8);
      const runtime = this.transferService.getRuntimeState();
      const config = this.configManager.getConfig();
      this.pruneSelectedUploadRecordIds(uploads);
      const nextViewState = createTransferPageViewState(
        this.viewState.renderVersion + 1,
        runtime,
        config,
        uploads,
        this.viewState.isBusy
      );
      this.commitViewState(nextViewState);
    } catch (error) {
      logger.warn(TAG, `刷新最近上传列表失败: ${this.stringifyError(error)}`);
    } finally {
      this.isRefreshingUploads = false;
    }
  }

  private startRefreshTimer(): void {
    this.stopRefreshTimer();
    this.refreshTimer = setInterval(() => {
      this.refreshSnapshot();
      void this.refreshUploads();
    }, 1500);
  }

  private async handlePageRefresh(): Promise<void> {
    if (this.isPageRefreshing) {
      return;
    }
    this.isPageRefreshing = true;
    try {
      this.refreshSnapshot();
      await this.refreshUploads();
    } finally {
      this.isPageRefreshing = false;
    }
  }

  private stopRefreshTimer(): void {
    if (this.refreshTimer >= 0) {
      clearInterval(this.refreshTimer);
      this.refreshTimer = -1;
    }
  }

  private showToast(message: string): void {
    try {
      this.getUIContext().getPromptAction().showToast({ message: message, duration: 1800 });
    } catch (error) {
      logger.warn(TAG, `Toast显示失败: ${message}, ${String(error)}`);
    }
  }

  private resolveAbilityContext(): common.UIAbilityContext | null {
    try {
      const hostContext = this.getUIContext().getHostContext();
      if (hostContext) {
        return hostContext as common.UIAbilityContext;
      }
    } catch (error) {
      logger.warn(TAG, `获取UIAbilityContext失败: ${String(error)}`);
    }
    return null;
  }

  private resolveNavigationStack(): NavPathStack | null {
    try {
      const globalStack = AppStorage.get<NavPathStack>('GlobalNavStack');
      if (globalStack) {
        return globalStack;
      }
    } catch (error) {
      logger.warn(TAG, `获取全局导航栈失败: ${String(error)}`);
    }
    return this.pathStack;
  }

  private navigateToDataManagement(): boolean {
    const stack = this.resolveNavigationStack();
    if (stack === null) {
      return false;
    }
    const navParam: TransferNavigationPathParam = {
      fromPage: 'TransferPage',
      timestamp: Date.now()
    };
    stack.pushPathByName('DataManagementPage', navParam);
    return true;
  }

  private navigateToMainMenu(): boolean {
    const stack = this.resolveNavigationStack();
    if (stack === null) {
      return false;
    }
    this.notifyMainMenuPendingFileImport();
    try {
      if (stack.size() > 0) {
        stack.pop();
        return true;
      }
      stack.pushPathByName('MainMenuPage', undefined);
      return true;
    } catch (error) {
      logger.warn(TAG, `返回首页处理上传文件失败: ${String(error)}`);
      return false;
    }
  }

  private notifyMainMenuPendingFileImport(): void {
    const currentTrigger = AppStorage.get<number>('fileOpenNewWantTrigger');
    const nextTrigger = (currentTrigger !== null && currentTrigger !== undefined ? currentTrigger : 0) + 1;
    AppStorage.setOrCreate('fileOpenNewWantTrigger', nextTrigger);
    logger.info(TAG, `已通知首页处理局域网传书文件: trigger=${nextTrigger}`);
  }

  private shouldRouteRecordToDataManagement(category: NetworkFolderImportCategory): boolean {
    return category === 'comic' || category === 'ebook' || category === 'pdf';
  }

  private getImportDestinationName(category: NetworkFolderImportCategory): string {
    if (this.shouldRouteRecordToDataManagement(category)) {
      return '导入页面';
    }
    return '应用入口';
  }

  private navigateToImportDestination(record: TransferUploadRecord): boolean {
    if (this.shouldRouteRecordToDataManagement(record.importCategory)) {
      return this.navigateToDataManagement();
    }
    return this.navigateToMainMenu();
  }

  private async handleStartService(): Promise<void> {
    if (this.viewState.isBusy) {
      return;
    }
    const abilityContext = this.resolveAbilityContext();
    if (abilityContext === null) {
      this.showToast('当前无法获取页面上下文，暂时不能启动服务');
      return;
    }
    this.setBusyState(true);
    try {
      const runtime = await this.transferService.start(abilityContext);
      this.applyPageSnapshot(runtime, this.configManager.getConfig());
      if (runtime.status !== 'running') {
        const failureMessage = runtime.lastError.length > 0 ? runtime.lastError : runtime.infoMessage;
        logger.warn(TAG, `启动服务未进入运行态: ${failureMessage}`);
        this.showToast(`启动失败: ${failureMessage}`);
        return;
      }
      logger.info(
        TAG,
        `页面收到启动成功快照: tick=${this.viewState.renderVersion}, port=${runtime.activePort}, ` +
          `addressCount=${runtime.localAddresses.length}`
      );
      await this.refreshUploads();
      this.showToast('局域网传书服务已启动');
    } catch (error) {
      const errorMessage = this.stringifyError(error);
      logger.error(TAG, `启动服务失败: ${errorMessage}`);
      this.showToast(`启动失败: ${errorMessage}`);
    } finally {
      this.setBusyState(false);
    }
  }

  private async handleStopService(): Promise<void> {
    if (this.viewState.isBusy) {
      return;
    }
    this.setBusyState(true);
    try {
      await this.transferService.stop('服务已手动停止。');
      this.refreshSnapshot();
      await this.refreshUploads();
      this.showToast('局域网传书服务已停止');
    } catch (error) {
      const errorMessage = this.stringifyError(error);
      logger.error(TAG, `停止服务失败: ${errorMessage}`);
      this.showToast(`停止失败: ${errorMessage}`);
    } finally {
      this.setBusyState(false);
    }
  }

  private handleRefreshSession(): void {
    const runtime = this.transferService.refreshSession();
    this.applyPageSnapshot(runtime, this.configManager.getConfig());
    this.showToast('已生成新的配对码');
  }

  private async handleContinueImport(recordId: string): Promise<void> {
    if (this.viewState.isBusy) {
      return;
    }
    this.setBusyState(true);
    try {
      const record = await this.uploadStoreService.prepareRecordForDataManagement(recordId);
      if (record === null) {
        this.showToast('未找到可导入的上传记录');
        return;
      }
      await this.refreshUploads();
      this.refreshSnapshot();
      const navigated = this.navigateToImportDestination(record);
      if (!navigated) {
        this.showToast('已准备导入，但当前无法自动跳转');
        return;
      }
      this.showToast(`已准备导入到${this.getImportDestinationName(record.importCategory)}：${record.fileName}`);
    } catch (error) {
      logger.error(TAG, `准备导入上传记录失败: ${String(error)}`);
      this.showToast(`准备导入失败: ${String(error)}`);
    } finally {
      this.setBusyState(false);
    }
  }

  private async handleDeleteRecord(recordId: string): Promise<void> {
    if (this.viewState.isBusy) {
      return;
    }
    this.setBusyState(true);
    try {
      const deleted = await this.uploadStoreService.deleteRecord(recordId);
      if (!deleted) {
        this.showToast('未找到要删除的收件箱记录');
        return;
      }
      await this.refreshUploads();
      this.refreshSnapshot();
      this.showToast('已删除记录及文件');
    } catch (error) {
      logger.warn(TAG, `删除传书记录失败: ${String(error)}`);
      this.showToast(`删除失败: ${String(error)}`);
    } finally {
      this.setBusyState(false);
    }
  }

  private async handleDeleteSelectedRecords(): Promise<void> {
    if (this.viewState.isBusy) {
      return;
    }
    const recordIds = this.collectSelectedDeletableRecordIds();
    if (recordIds.length <= 0) {
      this.showToast('请选择可删除的收件箱文件');
      return;
    }

    this.setBusyState(true);
    try {
      const deletedCount = await this.uploadStoreService.deleteRecords(recordIds);
      this.clearUploadSelection();
      await this.refreshUploads();
      this.refreshSnapshot();
      if (deletedCount <= 0) {
        this.showToast('未找到要删除的收件箱文件');
        return;
      }
      this.showToast(`已删除 ${deletedCount} 个记录及文件`);
    } catch (error) {
      logger.warn(TAG, `批量删除传书记录失败: ${String(error)}`);
      this.showToast(`删除失败: ${String(error)}`);
    } finally {
      this.setBusyState(false);
    }
  }

  private getPrimaryAddressText(): string {
    return this.viewState.primaryAddressText;
  }

  private getPrimaryAddress(): TransferLocalAddress | null {
    return getPrimaryTransferAddress(this.viewState.localAddresses);
  }

  private getPairCodeText(): string {
    return this.viewState.pairCodeText;
  }

  private buildConnectionGuideText(): string {
    return this.viewState.connectionGuideText;
  }

  private getQrCodeValue(): string {
    return this.viewState.qrCodeValue;
  }

  private getPairedClientText(): string {
    return this.viewState.pairedClientText;
  }

  private getSessionExpireText(): string {
    return this.viewState.sessionExpireText;
  }

  private isQuickAssistReady(): boolean {
    return this.viewState.quickAssistReady;
  }

  private isQrCodeReady(): boolean {
    return this.viewState.qrCodeReady;
  }

  private getBackgroundTransferText(): string {
    return this.viewState.backgroundTransferText;
  }

  private getWsEnabledText(): string {
    return this.viewState.wsEnabledText;
  }

  private getRefreshRootRenderKey(viewState: TransferPageViewState): string {
    return `transfer_refresh_root_${viewState.status}_${viewState.phase}_` +
      `${viewState.pairCode}_${viewState.localAddresses.length}_${viewState.recentUploads.length}`;
  }

  private isUploadRecordDeleteBlocked(recordId: string): boolean {
    return this.uploadStoreService.isRecordTrackingActive(recordId);
  }

  private pruneSelectedUploadRecordIds(uploads: TransferUploadRecord[]): void {
    if (this.selectedUploadRecordIds.length <= 0) {
      return;
    }
    const prunedIds: string[] = [];
    for (const selectedId of this.selectedUploadRecordIds) {
      const record = this.findUploadRecordInList(uploads, selectedId);
      if (record !== null && !this.isUploadRecordDeleteBlocked(record.id)) {
        prunedIds.push(record.id);
      }
    }
    if (prunedIds.length !== this.selectedUploadRecordIds.length) {
      this.selectedUploadRecordIds = prunedIds;
    }
  }

  private findUploadRecordInList(records: TransferUploadRecord[], recordId: string): TransferUploadRecord | null {
    for (const record of records) {
      if (record.id === recordId) {
        return record;
      }
    }
    return null;
  }

  private findUploadRecordById(recordId: string): TransferUploadRecord | null {
    return this.findUploadRecordInList(this.viewState.recentUploads, recordId);
  }

  private containsSelectedUploadRecordId(recordId: string): boolean {
    for (const selectedId of this.selectedUploadRecordIds) {
      if (selectedId === recordId) {
        return true;
      }
    }
    return false;
  }

  private isUploadRecordSelected(recordId: string): boolean {
    return this.containsSelectedUploadRecordId(recordId);
  }

  private isUploadRecordSelectable(record: TransferUploadRecord): boolean {
    return !this.isUploadRecordDeleteBlocked(record.id);
  }

  private setUploadRecordSelected(recordId: string, selected: boolean): void {
    const record = this.findUploadRecordById(recordId);
    if (record === null || !this.isUploadRecordSelectable(record)) {
      return;
    }

    if (selected) {
      if (this.containsSelectedUploadRecordId(recordId)) {
        return;
      }
      const nextIds: string[] = [];
      for (const selectedId of this.selectedUploadRecordIds) {
        nextIds.push(selectedId);
      }
      nextIds.push(recordId);
      this.selectedUploadRecordIds = nextIds;
      return;
    }

    const nextIds: string[] = [];
    for (const selectedId of this.selectedUploadRecordIds) {
      if (selectedId !== recordId) {
        nextIds.push(selectedId);
      }
    }
    this.selectedUploadRecordIds = nextIds;
  }

  private toggleUploadRecordSelection(recordId: string): void {
    this.setUploadRecordSelected(recordId, !this.isUploadRecordSelected(recordId));
  }

  private clearUploadSelection(): void {
    if (this.selectedUploadRecordIds.length > 0) {
      this.selectedUploadRecordIds = [];
    }
  }

  private getSelectableUploadRecordCount(): number {
    let count = 0;
    for (const record of this.viewState.recentUploads) {
      if (this.isUploadRecordSelectable(record)) {
        count += 1;
      }
    }
    return count;
  }

  private getSelectedUploadRecordCount(): number {
    let count = 0;
    for (const record of this.viewState.recentUploads) {
      if (this.isUploadRecordSelectable(record) && this.containsSelectedUploadRecordId(record.id)) {
        count += 1;
      }
    }
    return count;
  }

  private areAllSelectableUploadsSelected(): boolean {
    let selectableCount = 0;
    for (const record of this.viewState.recentUploads) {
      if (this.isUploadRecordSelectable(record)) {
        selectableCount += 1;
        if (!this.containsSelectedUploadRecordId(record.id)) {
          return false;
        }
      }
    }
    return selectableCount > 0;
  }

  private toggleSelectAllUploadRecords(): void {
    if (this.areAllSelectableUploadsSelected()) {
      this.clearUploadSelection();
      return;
    }

    const nextIds: string[] = [];
    for (const record of this.viewState.recentUploads) {
      if (this.isUploadRecordSelectable(record)) {
        nextIds.push(record.id);
      }
    }
    this.selectedUploadRecordIds = nextIds;
  }

  private collectSelectedDeletableRecordIds(): string[] {
    const recordIds: string[] = [];
    for (const record of this.viewState.recentUploads) {
      if (this.isUploadRecordSelectable(record) && this.containsSelectedUploadRecordId(record.id)) {
        recordIds.push(record.id);
      }
    }
    return recordIds;
  }

  private getUploadStatusText(record: TransferUploadRecord): string {
    if (record.status === 'handoff_sent') {
      return '正在导入';
    }
    if (record.status === 'imported') {
      return '已导入';
    }
    if (record.status === 'import_failed') {
      return '导入失败';
    }
    if (record.status === 'import_cancelled') {
      return '已取消';
    }
    return '已在设备上，待导入';
  }

  private getImportActionText(record: TransferUploadRecord): string {
    if (this.isUploadRecordDeleteBlocked(record.id)) {
      return '导入中';
    }
    if (record.status === 'imported') {
      return '重新导入';
    }
    return '继续导入';
  }

  private formatUploadTime(timestamp: number): string {
    const date = new Date(timestamp);
    const year = String(date.getFullYear());
    const month = String(date.getMonth() + 1).padStart(2, '0');
    const day = String(date.getDate()).padStart(2, '0');
    const hours = String(date.getHours()).padStart(2, '0');
    const minutes = String(date.getMinutes()).padStart(2, '0');
    return `${year}-${month}-${day} ${hours}:${minutes}`;
  }

  private stringifyError(error: Object): string {
    if (error instanceof Error) {
      return error.message;
    }
    try {
      return JSON.stringify(error);
    } catch (_jsonError) {
      return String(error);
    }
  }

  private async copyPlainText(text: string, successMessage: string): Promise<void> {
    if (text.trim().length <= 0) {
      this.showToast('当前没有可复制的内容');
      return;
    }
    try {
      const pasteData = pasteboard.createData(pasteboard.MIMETYPE_TEXT_PLAIN, text);
      const systemPasteboard = pasteboard.getSystemPasteboard();
      await systemPasteboard.setData(pasteData);
      this.showToast(successMessage);
    } catch (error) {
      logger.warn(TAG, `复制文本失败: ${String(error)}`);
      this.showToast('复制失败，请稍后重试');
    }
  }

  private async handleCopyPrimaryAddress(): Promise<void> {
    const primaryAddress = this.getPrimaryAddress();
    if (this.viewState.status !== 'running' || primaryAddress === null) {
      this.showToast('请先启动服务，再复制访问地址');
      return;
    }
    await this.copyPlainText(primaryAddress.url, '主地址已复制');
  }

  private async handleCopyAddress(address: TransferLocalAddress): Promise<void> {
    if (this.viewState.status !== 'running') {
      this.showToast('请先启动服务，再复制访问地址');
      return;
    }
    await this.copyPlainText(address.url, `${address.label}已复制`);
  }

  private async handleCopyPairCode(): Promise<void> {
    if (this.viewState.status !== 'running' || !this.viewState.hasSession) {
      this.showToast('请先启动服务，再复制配对码');
      return;
    }
    await this.copyPlainText(this.viewState.pairCode, '配对码已复制');
  }

  private async handleCopyConnectionGuide(): Promise<void> {
    const primaryAddress = this.getPrimaryAddress();
    if (this.viewState.status !== 'running' || primaryAddress === null || !this.viewState.hasSession) {
      this.showToast('请先启动服务，再复制连接指引');
      return;
    }
    await this.copyPlainText(this.buildConnectionGuideText(), '连接指引已复制');
  }

  private async handleShareConnectionGuide(): Promise<void> {
    const primaryAddress = this.getPrimaryAddress();
    const abilityContext = this.resolveAbilityContext();
    if (this.viewState.status !== 'running' || primaryAddress === null || !this.viewState.hasSession) {
      this.showToast('请先启动服务，再分享连接指引');
      return;
    }
    if (abilityContext === null) {
      this.showToast('当前无法打开系统分享');
      return;
    }
    try {
      const shareData: systemShare.SharedData = new systemShare.SharedData({
        utd: utd.UniformDataType.PLAIN_TEXT,
        content: this.buildConnectionGuideText(),
        title: '漫匣局域网传书连接指引',
        description: primaryAddress.url
      });
      const controller: systemShare.ShareController = new systemShare.ShareController(shareData);
      await controller.show(abilityContext, {
        previewMode: systemShare.SharePreviewMode.DETAIL,
        selectionMode: systemShare.SelectionMode.SINGLE
      });
    } catch (error) {
      logger.warn(TAG, `分享连接指引失败: ${String(error)}`);
      this.showToast('分享失败，请稍后重试');
    }
  }

  @Builder
  private buildTransferActionButton(
    label: string,
    icon: Resource,
    styleKind: number,
    enabled: boolean,
    expand: boolean,
    keySeed: string,
    onClick: () => void
  ) {
    Button() {
      Row({ space: 6 }) {
        SymbolGlyph(icon)
          .fontSize(14)
          .fontColor([enabled ? this.getActionForegroundColor(styleKind) : this.color('text_muted')])

        Text(label)
          .fontSize(12)
          .fontFamily(this.appFontFamily)
          .fontColor(enabled ? this.getActionForegroundColor(styleKind) : this.color('text_muted'))
          .maxLines(1)
      }
      .justifyContent(FlexAlign.Center)
    }
    .height(36)
    .borderRadius(12)
    .enabled(enabled)
    .layoutWeight(expand ? 1 : 0)
    .backgroundColor(enabled ? this.getActionBackgroundColor(styleKind) : this.color('comp_background_secondary'))
    .padding({ left: 12, right: 12 })
    .opacity(enabled ? 1 : 0.62)
    .key(`transfer_action_${keySeed}_${label}_${styleKind}_${enabled ? 'enabled' : 'disabled'}`)
    .onClick(() => {
      onClick();
    })
  }

  @Builder
  private buildHeroServiceToggleButton() {
    if (this.heroStatus === 'running') {
      Button() {
        Row({ space: 6 }) {
          SymbolGlyph($r('sys.symbol.xmark'))
            .fontSize(14)
            .fontColor([this.heroBusy ? this.color('text_muted') : this.color('text_white')])

          Text('停止服务')
            .fontSize(12)
            .fontFamily(this.appFontFamily)
            .fontColor(this.heroBusy ? this.color('text_muted') : this.color('text_white'))
            .maxLines(1)
        }
        .justifyContent(FlexAlign.Center)
      }
      .height(36)
      .borderRadius(12)
      .enabled(!this.heroBusy)
      .layoutWeight(1)
      .backgroundColor(this.heroBusy ? this.color('comp_background_secondary') : TRANSFER_DANGER_COLOR)
      .padding({ left: 12, right: 12 })
      .opacity(this.heroBusy ? 0.62 : 1)
      .key(`transfer_hero_stop_${this.heroBusy ? 'busy' : 'idle'}`)
      .onClick(() => {
        void this.handleStopService();
      })
    } else {
      Button() {
        Row({ space: 6 }) {
          SymbolGlyph($r('sys.symbol.play_fill'))
            .fontSize(14)
            .fontColor([this.heroBusy ? this.color('text_muted') : this.color('text_white')])

          Text('启动服务')
            .fontSize(12)
            .fontFamily(this.appFontFamily)
            .fontColor(this.heroBusy ? this.color('text_muted') : this.color('text_white'))
            .maxLines(1)
        }
        .justifyContent(FlexAlign.Center)
      }
      .height(36)
      .borderRadius(12)
      .enabled(!this.heroBusy)
      .layoutWeight(1)
      .backgroundColor(this.heroBusy ? this.color('comp_background_secondary') : TRANSFER_ACCENT_COLOR)
      .padding({ left: 12, right: 12 })
      .opacity(this.heroBusy ? 0.62 : 1)
      .key(`transfer_hero_start_${this.heroBusy ? 'busy' : 'idle'}`)
      .onClick(() => {
        void this.handleStartService();
      })
    }
  }

  @Builder
  private buildHeroCopyAddressButton() {
    Button() {
      Row({ space: 6 }) {
        SymbolGlyph($r('sys.symbol.link'))
          .fontSize(14)
          .fontColor([
            this.heroStatus === 'running' && this.heroAddressCount > 0 && !this.heroBusy ? this.color('text_white') :
            this.color('text_muted')
          ])

        Text('复制地址')
          .fontSize(12)
          .fontFamily(this.appFontFamily)
          .fontColor(
            this.heroStatus === 'running' && this.heroAddressCount > 0 && !this.heroBusy ? this.color('text_white') :
            this.color('text_muted')
          )
          .maxLines(1)
      }
      .justifyContent(FlexAlign.Center)
    }
    .height(36)
    .borderRadius(12)
    .enabled(this.heroStatus === 'running' && this.heroAddressCount > 0 && !this.heroBusy)
    .layoutWeight(1)
    .backgroundColor(
      this.heroStatus === 'running' && this.heroAddressCount > 0 && !this.heroBusy ? TRANSFER_INFO_COLOR :
      this.color('comp_background_secondary')
    )
    .padding({ left: 12, right: 12 })
    .opacity(this.heroStatus === 'running' && this.heroAddressCount > 0 && !this.heroBusy ? 1 : 0.62)
    .key(`transfer_hero_copy_${this.heroStatus}_${this.heroAddressCount}_${this.heroBusy ? 'busy' : 'idle'}`)
    .onClick(() => {
      void this.handleCopyPrimaryAddress();
    })
  }

  @Builder
  private buildHeroRefreshButton() {
    Button() {
      Row({ space: 6 }) {
        SymbolGlyph($r('sys.symbol.arrow_clockwise'))
          .fontSize(14)
          .fontColor([
            this.heroStatus === 'running' && !this.heroBusy ? this.color('text_primary') : this.color('text_muted')
          ])

        Text('刷新码')
          .fontSize(12)
          .fontFamily(this.appFontFamily)
          .fontColor(this.heroStatus === 'running' && !this.heroBusy ? this.color('text_primary') : this.color('text_muted'))
          .maxLines(1)
      }
      .justifyContent(FlexAlign.Center)
    }
    .height(36)
    .borderRadius(12)
    .enabled(this.heroStatus === 'running' && !this.heroBusy)
    .layoutWeight(1)
    .backgroundColor(
      this.heroStatus === 'running' && !this.heroBusy ? this.color('comp_background_tertiary') :
      this.color('comp_background_secondary')
    )
    .padding({ left: 12, right: 12 })
    .opacity(this.heroStatus === 'running' && !this.heroBusy ? 1 : 0.62)
    .key(`transfer_hero_refresh_${this.heroStatus}_${this.heroBusy ? 'busy' : 'idle'}`)
    .onClick(() => {
      this.handleRefreshSession();
    })
  }

  @Builder
  private buildHeroCard() {
    Stack({ alignContent: Alignment.TopEnd }) {
      Column({ space: 18 }) {
        Row({ space: 12 }) {
          Column() {
            SymbolGlyph($r('sys.symbol.wifi'))
              .fontSize(30)
              .fontColor(['#FFFFFF'])
          }
          .width(56)
          .height(56)
          .justifyContent(FlexAlign.Center)
          .backgroundColor('rgba(255, 255, 255, 0.16)')
          .borderRadius(18)

          Column({ space: 6 }) {
            Text('局域网传书')
              .fontSize(20)
              .fontWeight(FontWeight.Bold)
              .fontFamily(this.appFontFamily)
              .fontColor('#FFFFFF')
              .width('100%')
              .textAlign(TextAlign.Start)

            Text(this.viewState.infoMessage)
              .fontSize(12)
              .fontFamily(this.appFontFamily)
              .lineHeight(19)
              .fontColor('rgba(255, 255, 255, 0.78)')
              .width('100%')
              .textAlign(TextAlign.Start)
              .maxLines(2)
              .textOverflow({ overflow: TextOverflow.Ellipsis })
          }
          .layoutWeight(1)
          .alignItems(HorizontalAlign.Start)

          Text(this.heroStatus === 'running' ? '运行中' : '未启动')
            .fontSize(12)
            .fontWeight(FontWeight.Medium)
            .fontFamily(this.appFontFamily)
            .fontColor('#FFFFFF')
            .padding({ left: 12, right: 12, top: 6, bottom: 6 })
            .backgroundColor('rgba(255, 255, 255, 0.16)')
            .borderRadius(999)
        }
        .width('100%')
        .alignItems(VerticalAlign.Top)

        Column({ space: 6 }) {
          Text('浏览器主地址')
            .fontSize(12)
            .fontFamily(this.appFontFamily)
            .fontColor('rgba(255, 255, 255, 0.72)')
            .width('100%')
            .textAlign(TextAlign.Start)

          Text(this.viewState.primaryAddressText)
            .fontSize(16)
            .fontWeight(FontWeight.Medium)
            .fontFamily(this.appFontFamily)
            .fontColor('#FFFFFF')
            .width('100%')
            .textAlign(TextAlign.Start)
            .maxLines(2)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
        }
        .width('100%')
        .padding(14)
        .backgroundColor('rgba(255, 255, 255, 0.12)')
        .borderRadius(18)

        Row({ space: 12 }) {
          Column({ space: 5 }) {
            Text('配对码')
              .fontSize(12)
              .fontFamily(this.appFontFamily)
              .fontColor('rgba(255, 255, 255, 0.72)')
            Text(this.viewState.pairCodeText)
              .fontSize(24)
              .fontWeight(FontWeight.Bold)
              .fontFamily(this.appFontFamily)
              .fontColor('#FFFFFF')
          }
          .layoutWeight(1)
          .alignItems(HorizontalAlign.Start)
          .padding(14)
          .backgroundColor('rgba(255, 255, 255, 0.12)')
          .borderRadius(18)

          Column({ space: 5 }) {
            Text('已配对')
              .fontSize(12)
              .fontFamily(this.appFontFamily)
              .fontColor('rgba(255, 255, 255, 0.72)')
            Text(this.viewState.pairedClientText)
              .fontSize(14)
              .fontWeight(FontWeight.Medium)
              .fontFamily(this.appFontFamily)
              .fontColor('#FFFFFF')
              .maxLines(2)
              .textOverflow({ overflow: TextOverflow.Ellipsis })
          }
          .layoutWeight(1)
          .alignItems(HorizontalAlign.Start)
          .padding(14)
          .backgroundColor('rgba(255, 255, 255, 0.12)')
          .borderRadius(18)
        }
        .width('100%')

        Row({ space: 10 }) {
          this.buildHeroServiceToggleButton()
          this.buildHeroCopyAddressButton()
          this.buildHeroRefreshButton()
        }
        .width('100%')
      }
      .width('100%')

      SymbolGlyph($r('sys.symbol.externaldrive_fill'))
        .fontSize(86)
        .fontColor(['rgba(255, 255, 255, 0.10)'])
        .margin({ top: 12, right: 4 })
    }
    .width('100%')
    .padding(20)
    .backgroundColor('#174E45')
    .borderRadius(26)
    .clip(true)
    .key(
      `transfer_hero_${this.heroStatus}_${this.heroAddressCount}_${this.heroBusy ? 'busy' : 'idle'}_` +
        `${this.viewState.renderVersion}_${this.viewState.pairCode}_${this.viewState.clientName}`
    )
  }

  @Builder
  private buildConnectionTabContent() {
    Column({ space: 16 }) {
      this.buildAddressCard()
      this.buildQuickAssistCard()
      this.buildQrCodeCard()
    }
    .width('100%')
    .padding({ top: 16 })
    .transition(TransitionEffect.asymmetric(
      TransitionEffect.OPACITY.animation({ duration: 220, curve: Curve.EaseOut }).combine(
        TransitionEffect.translate({ y: 10 }).animation({ duration: 220, curve: Curve.EaseOut })
      ),
      TransitionEffect.OPACITY.animation({ duration: 160, curve: Curve.EaseIn }).combine(
        TransitionEffect.translate({ y: -6 }).animation({ duration: 160, curve: Curve.EaseIn })
      )
    ))
  }

  @Builder
  private buildInboxTabContent() {
    Column({ space: 16 }) {
      this.buildRecentUploadsCard()
    }
    .width('100%')
    .padding({ top: 16 })
    .transition(TransitionEffect.asymmetric(
      TransitionEffect.OPACITY.animation({ duration: 220, curve: Curve.EaseOut }).combine(
        TransitionEffect.translate({ y: 10 }).animation({ duration: 220, curve: Curve.EaseOut })
      ),
      TransitionEffect.OPACITY.animation({ duration: 160, curve: Curve.EaseIn }).combine(
        TransitionEffect.translate({ y: -6 }).animation({ duration: 160, curve: Curve.EaseIn })
      )
    ))
  }

  @Builder
  private buildGuideTabContent() {
    Column({ space: 16 }) {
      this.buildWorkflowCard()
      this.buildConfigCard()
      this.buildScopeCard()
    }
    .width('100%')
    .padding({ top: 16 })
    .transition(TransitionEffect.asymmetric(
      TransitionEffect.OPACITY.animation({ duration: 220, curve: Curve.EaseOut }).combine(
        TransitionEffect.translate({ y: 10 }).animation({ duration: 220, curve: Curve.EaseOut })
      ),
      TransitionEffect.OPACITY.animation({ duration: 160, curve: Curve.EaseIn }).combine(
        TransitionEffect.translate({ y: -6 }).animation({ duration: 160, curve: Curve.EaseIn })
      )
    ))
  }

  @Builder
  private buildTransferTabs() {
    Column({ space: 14 }) {
      Row({ space: 8 }) {
        this.buildTransferTabButton(0, '连接')
        this.buildTransferTabButton(
          1,
          this.viewState.recentUploads.length > 0 ? `收件箱 ${this.viewState.recentUploads.length}` : '收件箱'
        )
        this.buildTransferTabButton(2, '说明')
      }
      .width('100%')
      .padding(6)
      .backgroundColor(SettingsPanelSurfaceHelper.getBackground(this.themeState.currentTheme))
      .linearGradient(SettingsPanelSurfaceHelper.getSurfaceGradient(this.themeState.currentTheme))
      .backgroundBlurStyle(
        SettingsPanelSurfaceHelper.getBlurStyle(this.themeState.currentTheme),
        SettingsPanelSurfaceHelper.getBlurOptions(this.themeState.currentTheme)
      )
      .backgroundEffect(SettingsPanelSurfaceHelper.getBackgroundEffect(this.themeState.currentTheme))
      .borderRadius(22)
      .clip(true)
      .border({
        width: SettingsPanelSurfaceHelper.getBorderWidth(this.themeState.currentTheme),
        color: SettingsPanelSurfaceHelper.getBorderColor(this.themeState.currentTheme)
      })
      .shadow({
        radius: 18,
        color: SettingsPanelSurfaceHelper.getShadowColor(this.themeState.currentTheme),
        offsetX: 0,
        offsetY: 8
      })

      if (this.activeTabIndex === 0) {
        this.buildConnectionTabContent()
      } else if (this.activeTabIndex === 1) {
        this.buildInboxTabContent()
      } else {
        this.buildGuideTabContent()
      }
    }
    .width('100%')
    .key(
      `transfer_tabs_${this.viewState.recentUploads.length}_` +
        `${this.selectedUploadRecordIds.length}`
    )
  }

  @Builder
  private buildTransferTabButton(index: number, label: string) {
    Text(label)
      .fontSize(14)
      .fontWeight(this.activeTabIndex === index ? FontWeight.Bold : FontWeight.Medium)
      .fontColor(this.activeTabIndex === index ? this.color('text_white') : this.color('text_secondary'))
      .textAlign(TextAlign.Center)
      .layoutWeight(1)
      .padding({ top: 10, bottom: 10 })
      .backgroundColor(this.activeTabIndex === index ? TRANSFER_ACCENT_COLOR : this.color('comp_background_tertiary'))
      .borderRadius(16)
      .opacity(this.activeTabIndex === index ? 1 : 0.82)
      .scale({ x: this.activeTabIndex === index ? 1 : 0.96, y: this.activeTabIndex === index ? 1 : 0.96 })
      .animation({ duration: 200, curve: Curve.EaseInOut })
      .onClick(() => {
        if (this.activeTabIndex === index) {
          return;
        }
        this.activeTabIndex = index;
      })
  }

  @Builder
  private buildWorkflowCard() {
    Column({ space: 12 }) {
      TransferCardHeaderView({
        themeState: this.themeState,
        title: '使用步骤',
        subtitle: '先启动服务，再让另一台设备打开主地址并验证配对，最后回到漫匣继续导入。'
      })

      TransferEmphasisValueCardView({
        themeState: this.themeState,
        title: '步骤 1：启动服务',
        value: this.viewState.status === 'running' ? '当前已启动' : '先点击“启动服务”',
        hint: '服务启动后，页面会显示局域网主地址、配对码和二维码。'
      })

      TransferEmphasisValueCardView({
        themeState: this.themeState,
        title: '步骤 2：浏览器打开主地址并输入配对码',
        value: this.viewState.primaryAddressText,
        hint: `浏览器输入主地址后，先验证配对码 ${this.viewState.pairCodeText}，再选择文件上传。`
      })

      TransferEmphasisValueCardView({
        themeState: this.themeState,
        title: '步骤 3：回到漫匣继续导入',
        value: this.viewState.hasRecentUploads ? '收件箱已有文件，可继续导入' : '上传完成后这里会出现收件箱记录',
        hint: '浏览器上传成功后，文件已经在设备上，可在收件箱里点击“继续导入”。'
      })
    }
    .width('100%')
    .padding(20)
    .backgroundColor(SettingsPanelSurfaceHelper.getBackground(this.themeState.currentTheme))
    .linearGradient(SettingsPanelSurfaceHelper.getSurfaceGradient(this.themeState.currentTheme))
    .backgroundBlurStyle(
      SettingsPanelSurfaceHelper.getBlurStyle(this.themeState.currentTheme),
      SettingsPanelSurfaceHelper.getBlurOptions(this.themeState.currentTheme)
    )
    .backgroundEffect(SettingsPanelSurfaceHelper.getBackgroundEffect(this.themeState.currentTheme))
    .borderRadius(24)
    .clip(true)
    .border({
      width: SettingsPanelSurfaceHelper.getBorderWidth(this.themeState.currentTheme),
      color: SettingsPanelSurfaceHelper.getBorderColor(this.themeState.currentTheme)
    })
    .shadow({
      radius: 22,
      color: SettingsPanelSurfaceHelper.getShadowColor(this.themeState.currentTheme),
      offsetX: 0,
      offsetY: 8
    })
    .key(
      `transfer_workflow_${this.viewState.renderVersion}_${this.viewState.status}_${this.viewState.pairCode}_` +
        `${this.viewState.hasRecentUploads ? 'uploads1' : 'uploads0'}`
    )
  }

  @Builder
  private buildStatusCard() {
    Column({ space: 16 }) {
      TransferCardHeaderView({
        themeState: this.themeState,
        title: '服务状态',
        subtitle: '查看服务监听、后台运行和最近一次状态说明。'
      })

      TransferInfoRowView({ themeState: this.themeState, label: '当前状态', value: this.viewState.status })
      TransferInfoRowView({ themeState: this.themeState, label: '运行阶段', value: this.viewState.phase })
      TransferInfoRowView({ themeState: this.themeState, label: '状态说明', value: this.viewState.infoMessage })
      TransferInfoRowView({
        themeState: this.themeState,
        label: '后台运行',
        value: this.viewState.backgroundRunning ? '已申请' : '未申请'
      })

      if (this.viewState.lastError.length > 0) {
        TransferInfoRowView({ themeState: this.themeState, label: '最近错误', value: this.viewState.lastError })
      }

      Row({ space: 12 }) {
        this.buildTransferActionButton(
          this.viewState.status === 'running' ? '停止服务' : '启动服务',
          this.viewState.status === 'running' ? $r('sys.symbol.xmark') : $r('sys.symbol.play_fill'),
          this.viewState.status === 'running' ? ACTION_STYLE_DANGER : ACTION_STYLE_PRIMARY,
          !this.viewState.isBusy,
          true,
          'status_service_toggle',
          () => {
            if (this.viewState.status === 'running') {
              void this.handleStopService();
            } else {
              void this.handleStartService();
            }
          }
        )

        this.buildTransferActionButton(
          '刷新配对码',
          $r('sys.symbol.arrow_clockwise'),
          ACTION_STYLE_NEUTRAL,
          !this.viewState.isBusy && this.viewState.status === 'running',
          true,
          'status_refresh_session',
          () => {
            this.handleRefreshSession();
          }
        )
      }
      .width('100%')
    }
    .width('100%')
    .padding(20)
    .backgroundColor(SettingsPanelSurfaceHelper.getBackground(this.themeState.currentTheme))
    .linearGradient(SettingsPanelSurfaceHelper.getSurfaceGradient(this.themeState.currentTheme))
    .backgroundBlurStyle(
      SettingsPanelSurfaceHelper.getBlurStyle(this.themeState.currentTheme),
      SettingsPanelSurfaceHelper.getBlurOptions(this.themeState.currentTheme)
    )
    .backgroundEffect(SettingsPanelSurfaceHelper.getBackgroundEffect(this.themeState.currentTheme))
    .borderRadius(24)
    .clip(true)
    .border({
      width: SettingsPanelSurfaceHelper.getBorderWidth(this.themeState.currentTheme),
      color: SettingsPanelSurfaceHelper.getBorderColor(this.themeState.currentTheme)
    })
    .shadow({
      radius: 22,
      color: SettingsPanelSurfaceHelper.getShadowColor(this.themeState.currentTheme),
      offsetX: 0,
      offsetY: 8
    })
    .key(
      `transfer_status_${this.viewState.renderVersion}_${this.viewState.status}_${this.viewState.phase}_` +
        `${this.viewState.lastError.length}_${this.viewState.backgroundRunning ? 'bg1' : 'bg0'}`
    )
  }

  @Builder
  private buildAddressItem(address: TransferLocalAddress) {
    Column({ space: 6 }) {
      Row() {
        Text(address.label)
          .fontSize(13)
          .fontColor(this.color('text_secondary'))

        Blank()

        this.buildTransferActionButton(
          '复制',
          $r('sys.symbol.link'),
          ACTION_STYLE_NEUTRAL,
          this.viewState.status === 'running' && !this.viewState.isBusy,
          false,
          `address_copy_${address.url}`,
          () => {
            void this.handleCopyAddress(address);
          }
        )
      }
      .width('100%')

      Text(address.url)
        .fontSize(15)
        .fontWeight(FontWeight.Medium)
        .fontColor(this.color('text_primary'))
        .width('100%')
        .textAlign(TextAlign.Start)
    }
    .width('100%')
    .padding(14)
    .backgroundColor(this.color('comp_background_tertiary'))
    .borderRadius(18)
    .clip(true)
  }

  @Builder
  private buildAddressCard() {
    Column({ space: 14 }) {
      TransferCardHeaderView({
        themeState: this.themeState,
        title: '连接凭证',
        subtitle: '先让另一台设备打开局域网主地址，再在网页中输入配对码完成配对。'
      })

      TransferEmphasisValueCardView({
        themeState: this.themeState,
        title: '步骤 1：打开这个主地址',
        value: this.viewState.primaryAddressText,
        hint: '优先使用这个地址；如果浏览器打不开，请确认两台设备在同一 Wi-Fi 下。'
      })

      TransferEmphasisValueCardView({
        themeState: this.themeState,
        title: '步骤 2：输入这个配对码',
        value: this.viewState.pairCodeText,
        hint: '如果浏览器提示配对失效，回到漫匣点“刷新配对码”后再重试。'
      })

      TransferInfoRowView({ themeState: this.themeState, label: '已配对设备', value: this.viewState.pairedClientText })
      TransferInfoRowView({ themeState: this.themeState, label: '会话有效期', value: this.viewState.sessionExpireText })
      TransferInfoRowView({
        themeState: this.themeState,
        label: 'HTTP端口',
        value: this.viewState.activePort > 0 ? String(this.viewState.activePort) : '未启动'
      })
      TransferInfoRowView({
        themeState: this.themeState,
        label: 'WebSocket端口',
        value: this.viewState.webSocketPort > 0 ? String(this.viewState.webSocketPort) : '未启用'
      })

      if (this.viewState.localAddresses.length > 0) {
        Column({ space: 10 }) {
          ForEach(this.viewState.localAddresses, (address: TransferLocalAddress) => {
            this.buildAddressItem(address)
          }, (address: TransferLocalAddress) => address.url)
        }
        .width('100%')
      }
    }
    .width('100%')
    .padding(20)
    .backgroundColor(SettingsPanelSurfaceHelper.getBackground(this.themeState.currentTheme))
    .linearGradient(SettingsPanelSurfaceHelper.getSurfaceGradient(this.themeState.currentTheme))
    .backgroundBlurStyle(
      SettingsPanelSurfaceHelper.getBlurStyle(this.themeState.currentTheme),
      SettingsPanelSurfaceHelper.getBlurOptions(this.themeState.currentTheme)
    )
    .backgroundEffect(SettingsPanelSurfaceHelper.getBackgroundEffect(this.themeState.currentTheme))
    .borderRadius(24)
    .clip(true)
    .border({
      width: SettingsPanelSurfaceHelper.getBorderWidth(this.themeState.currentTheme),
      color: SettingsPanelSurfaceHelper.getBorderColor(this.themeState.currentTheme)
    })
    .shadow({
      radius: 22,
      color: SettingsPanelSurfaceHelper.getShadowColor(this.themeState.currentTheme),
      offsetX: 0,
      offsetY: 8
    })
    .key(
      `transfer_address_${this.viewState.renderVersion}_${this.viewState.pairCode}_${this.viewState.activePort}_` +
        `${this.viewState.webSocketPort}_${this.viewState.localAddresses.length}`
    )
  }

  @Builder
  private buildQuickAssistCard() {
    Column({ space: 14 }) {
      TransferCardHeaderView({
        themeState: this.themeState,
        title: '快速连接辅助',
        subtitle: '把访问地址、配对码和完整连接指引快速复制或分享给另一台设备。'
      })

      Text(this.viewState.connectionGuideText)
        .fontSize(13)
        .lineHeight(21)
        .fontColor(this.color('text_primary'))
        .width('100%')
        .textAlign(TextAlign.Start)
        .padding(14)
        .backgroundColor(this.color('comp_background_tertiary'))
        .borderRadius(18)
        .clip(true)

      Row({ space: 12 }) {
        this.buildTransferActionButton(
          '复制主地址',
          $r('sys.symbol.link'),
          ACTION_STYLE_INFO,
          this.viewState.quickAssistReady && !this.viewState.isBusy,
          true,
          'assist_copy_primary_address',
          () => {
            void this.handleCopyPrimaryAddress();
          }
        )

        this.buildTransferActionButton(
          '复制配对码',
          $r('sys.symbol.checkmark_circle_fill'),
          ACTION_STYLE_NEUTRAL,
          this.viewState.quickAssistReady && !this.viewState.isBusy,
          true,
          'assist_copy_pair_code',
          () => {
            void this.handleCopyPairCode();
          }
        )
      }
      .width('100%')

      Row({ space: 12 }) {
        this.buildTransferActionButton(
          '复制连接指引',
          $r('sys.symbol.doc_plaintext'),
          ACTION_STYLE_INFO,
          this.viewState.quickAssistReady && !this.viewState.isBusy,
          true,
          'assist_copy_guide',
          () => {
            void this.handleCopyConnectionGuide();
          }
        )

        this.buildTransferActionButton(
          '系统分享',
          $r('sys.symbol.arrowshape_turn_up_right'),
          ACTION_STYLE_NEUTRAL,
          this.viewState.quickAssistReady && !this.viewState.isBusy,
          true,
          'assist_system_share',
          () => {
            void this.handleShareConnectionGuide();
          }
        )
      }
      .width('100%')
    }
    .width('100%')
    .padding(20)
    .backgroundColor(SettingsPanelSurfaceHelper.getBackground(this.themeState.currentTheme))
    .linearGradient(SettingsPanelSurfaceHelper.getSurfaceGradient(this.themeState.currentTheme))
    .backgroundBlurStyle(
      SettingsPanelSurfaceHelper.getBlurStyle(this.themeState.currentTheme),
      SettingsPanelSurfaceHelper.getBlurOptions(this.themeState.currentTheme)
    )
    .backgroundEffect(SettingsPanelSurfaceHelper.getBackgroundEffect(this.themeState.currentTheme))
    .borderRadius(24)
    .clip(true)
    .border({
      width: SettingsPanelSurfaceHelper.getBorderWidth(this.themeState.currentTheme),
      color: SettingsPanelSurfaceHelper.getBorderColor(this.themeState.currentTheme)
    })
    .shadow({
      radius: 22,
      color: SettingsPanelSurfaceHelper.getShadowColor(this.themeState.currentTheme),
      offsetX: 0,
      offsetY: 8
    })
    .key(
      `transfer_assist_${this.viewState.renderVersion}_${this.viewState.status}_${this.viewState.pairCode}_` +
        `${this.viewState.localAddresses.length}`
    )
  }

  @Builder
  private buildQrCodeCard() {
    Column({ space: 14 }) {
      TransferCardHeaderView({
        themeState: this.themeState,
        title: '扫码连接',
        subtitle: '二维码内容就是局域网上传页地址；另一台设备扫码后可直接在浏览器打开。'
      })

      Column({ space: 10 }) {
        if (this.viewState.qrCodeReady) {
          Column() {
            QRCode(this.getQrCodeValue())
              .width(220)
              .height(220)
              .color(Color.Black)
              .backgroundColor(Color.White)
              .key(`transfer_qr_value_${this.viewState.qrCodeValue}`)
          }
          .padding(12)
          .backgroundColor(Color.White)
          .borderRadius(22)
          .clip(true)
        } else {
          Column({ space: 8 }) {
            Text('服务尚未启动')
              .fontSize(16)
              .fontWeight(FontWeight.Bold)
              .fontColor(this.color('text_primary'))

            Text('启动后这里会生成当前主地址对应的二维码。')
              .fontSize(13)
              .lineHeight(20)
              .fontColor(this.color('text_secondary'))
              .textAlign(TextAlign.Center)
          }
          .width(220)
          .height(220)
          .justifyContent(FlexAlign.Center)
          .alignItems(HorizontalAlign.Center)
          .backgroundColor(this.color('comp_background_tertiary'))
          .borderRadius(22)
          .clip(true)
        }

        Text(this.viewState.qrCodeReady ? this.viewState.primaryAddressText : '请先启动服务')
          .fontSize(12)
          .fontColor(this.color('text_secondary'))
          .width('100%')
          .textAlign(TextAlign.Center)
      }
      .width('100%')
      .alignItems(HorizontalAlign.Center)
      .padding(12)
      .backgroundColor(this.color('comp_background_tertiary'))
      .borderRadius(22)
      .clip(true)
    }
    .width('100%')
    .padding(20)
    .backgroundColor(SettingsPanelSurfaceHelper.getBackground(this.themeState.currentTheme))
    .linearGradient(SettingsPanelSurfaceHelper.getSurfaceGradient(this.themeState.currentTheme))
    .backgroundBlurStyle(
      SettingsPanelSurfaceHelper.getBlurStyle(this.themeState.currentTheme),
      SettingsPanelSurfaceHelper.getBlurOptions(this.themeState.currentTheme)
    )
    .backgroundEffect(SettingsPanelSurfaceHelper.getBackgroundEffect(this.themeState.currentTheme))
    .borderRadius(24)
    .clip(true)
    .border({
      width: SettingsPanelSurfaceHelper.getBorderWidth(this.themeState.currentTheme),
      color: SettingsPanelSurfaceHelper.getBorderColor(this.themeState.currentTheme)
    })
    .shadow({
      radius: 22,
      color: SettingsPanelSurfaceHelper.getShadowColor(this.themeState.currentTheme),
      offsetX: 0,
      offsetY: 8
    })
    .key(
      `transfer_qrcode_${this.viewState.status}_${this.viewState.pairCode}_${this.viewState.qrCodeValue}_` +
        `${this.viewState.localAddresses.length}`
    )
  }

  @Builder
  private buildConfigCard() {
    Column({ space: 14 }) {
      TransferCardHeaderView({
        themeState: this.themeState,
        title: '配置摘要',
        subtitle: '当前局域网传书服务使用的基础配置。'
      })

      TransferInfoRowView({ themeState: this.themeState, label: '监听端口', value: String(this.viewState.config.port) })
      TransferInfoRowView({
        themeState: this.themeState,
        label: '自动停服',
        value: `${this.viewState.config.autoStopMinutes} 分钟`
      })
      TransferInfoRowView({
        themeState: this.themeState,
        label: '单文件上限',
        value: `${this.viewState.config.maxFileSizeMb} MB`
      })
      TransferInfoRowView({ themeState: this.themeState, label: '后台运行', value: this.viewState.backgroundTransferText })
      TransferInfoRowView({ themeState: this.themeState, label: '状态通道', value: this.viewState.wsEnabledText })
    }
    .width('100%')
    .padding(20)
    .backgroundColor(SettingsPanelSurfaceHelper.getBackground(this.themeState.currentTheme))
    .linearGradient(SettingsPanelSurfaceHelper.getSurfaceGradient(this.themeState.currentTheme))
    .backgroundBlurStyle(
      SettingsPanelSurfaceHelper.getBlurStyle(this.themeState.currentTheme),
      SettingsPanelSurfaceHelper.getBlurOptions(this.themeState.currentTheme)
    )
    .backgroundEffect(SettingsPanelSurfaceHelper.getBackgroundEffect(this.themeState.currentTheme))
    .borderRadius(24)
    .clip(true)
    .border({
      width: SettingsPanelSurfaceHelper.getBorderWidth(this.themeState.currentTheme),
      color: SettingsPanelSurfaceHelper.getBorderColor(this.themeState.currentTheme)
    })
    .shadow({
      radius: 22,
      color: SettingsPanelSurfaceHelper.getShadowColor(this.themeState.currentTheme),
      offsetX: 0,
      offsetY: 8
    })
    .key(
      `transfer_config_${this.viewState.renderVersion}_${this.viewState.config.port}_` +
        `${this.viewState.config.autoStopMinutes}_${this.viewState.config.maxFileSizeMb}_` +
        `${this.viewState.config.allowBackgroundTransfer ? 'bg1' : 'bg0'}_${this.viewState.config.wsEnabled ? 'ws1' : 'ws0'}`
    )
  }

  @Builder
  private buildUploadRecord(record: TransferUploadRecord) {
    Column({ space: 10 }) {
      Row({ space: 10 }) {
        Checkbox()
          .select(this.isUploadRecordSelected(record.id))
          .selectedColor(this.color('accent_primary'))
          .enabled(!this.viewState.isBusy && !this.isUploadRecordDeleteBlocked(record.id))
          .onChange((checked: boolean) => {
            this.setUploadRecordSelected(record.id, checked);
          })

        Column({ space: 5 }) {
          Text(record.fileName)
            .fontSize(16)
            .fontWeight(FontWeight.Bold)
            .fontColor(this.color('text_primary'))
            .width('100%')
            .textAlign(TextAlign.Start)
            .maxLines(2)
            .textOverflow({ overflow: TextOverflow.Ellipsis })

          Text(this.isUploadRecordSelected(record.id) ? '已选中' : this.getUploadStatusText(record))
            .fontSize(12)
            .fontColor(this.isUploadRecordSelected(record.id) ? this.color('accent_primary') : this.color('text_secondary'))
            .width('100%')
            .textAlign(TextAlign.Start)
        }
        .layoutWeight(1)
        .alignItems(HorizontalAlign.Start)
      }
      .width('100%')

      TransferInfoRowView({
        themeState: this.themeState,
        label: '分类',
        value: this.uploadStoreService.getImportCategoryLabel(record.importCategory)
      })
      TransferInfoRowView({
        themeState: this.themeState,
        label: '来源设备',
        value: record.clientName.length > 0 ? record.clientName : '未命名设备'
      })
      TransferInfoRowView({ themeState: this.themeState, label: '文件大小', value: `${record.fileSizeBytes} 字节` })
      TransferInfoRowView({ themeState: this.themeState, label: '接收时间', value: this.formatUploadTime(record.receivedAt) })
      TransferInfoRowView({ themeState: this.themeState, label: '保存状态', value: '文件已在设备上' })
      TransferInfoRowView({ themeState: this.themeState, label: '导入状态', value: this.getUploadStatusText(record) })

      Row({ space: 12 }) {
        this.buildTransferActionButton(
          this.getImportActionText(record),
          $r('sys.symbol.square_and_arrow_down'),
          ACTION_STYLE_INFO,
          !this.viewState.isBusy && !this.isUploadRecordDeleteBlocked(record.id),
          true,
          `upload_import_${record.id}`,
          () => {
            void this.handleContinueImport(record.id);
          }
        )

        this.buildTransferActionButton(
          this.isUploadRecordDeleteBlocked(record.id) ? '导入中' : '删除记录及文件',
          $r('sys.symbol.trash'),
          ACTION_STYLE_DANGER,
          !this.viewState.isBusy && !this.isUploadRecordDeleteBlocked(record.id),
          true,
          `upload_delete_${record.id}`,
          () => {
            void this.handleDeleteRecord(record.id);
          }
        )
      }
      .width('100%')
    }
    .width('100%')
    .padding(18)
    .backgroundColor(SettingsPanelSurfaceHelper.getBackground(this.themeState.currentTheme))
    .linearGradient(SettingsPanelSurfaceHelper.getSurfaceGradient(this.themeState.currentTheme))
    .backgroundBlurStyle(
      SettingsPanelSurfaceHelper.getBlurStyle(this.themeState.currentTheme),
      SettingsPanelSurfaceHelper.getBlurOptions(this.themeState.currentTheme)
    )
    .backgroundEffect(SettingsPanelSurfaceHelper.getBackgroundEffect(this.themeState.currentTheme))
    .borderRadius(20)
    .clip(true)
    .border({
      width: this.isUploadRecordSelected(record.id) ? 1.5 : SettingsPanelSurfaceHelper.getBorderWidth(this.themeState.currentTheme),
      color: this.isUploadRecordSelected(record.id) ? TRANSFER_ACCENT_COLOR : SettingsPanelSurfaceHelper.getBorderColor(this.themeState.currentTheme)
    })
    .shadow({
      radius: 18,
      color: SettingsPanelSurfaceHelper.getShadowColor(this.themeState.currentTheme),
      offsetX: 0,
      offsetY: 8
    })
    .key(`transfer_upload_record_${record.id}_${this.isUploadRecordSelected(record.id) ? 'selected' : 'idle'}_${record.status}`)
  }

  @Builder
  private buildInboxSelectionToolbar() {
    Column({ space: 10 }) {
      Row({ space: 10 }) {
        Text(`已选 ${this.getSelectedUploadRecordCount()} / ${this.getSelectableUploadRecordCount()} 个`)
          .fontSize(13)
          .fontColor(this.getSelectedUploadRecordCount() > 0 ? this.color('accent_primary') : this.color('text_secondary'))
          .layoutWeight(1)
          .textAlign(TextAlign.Start)

        this.buildTransferActionButton(
          this.areAllSelectableUploadsSelected() ? '全不选' : '全选',
          this.areAllSelectableUploadsSelected() ? $r('sys.symbol.xmark') : $r('sys.symbol.checkmark_circle_fill'),
          ACTION_STYLE_NEUTRAL,
          !this.viewState.isBusy && this.getSelectableUploadRecordCount() > 0,
          false,
          'inbox_toggle_select_all',
          () => {
            this.toggleSelectAllUploadRecords();
          }
        )

        this.buildTransferActionButton(
          '删除记录及文件',
          $r('sys.symbol.trash'),
          ACTION_STYLE_DANGER,
          !this.viewState.isBusy && this.getSelectedUploadRecordCount() > 0,
          false,
          'inbox_delete_selected',
          () => {
            void this.handleDeleteSelectedRecords();
          }
        )
      }
      .width('100%')

      if (this.getSelectableUploadRecordCount() < this.viewState.recentUploads.length) {
        Text('正在导入的文件会暂时锁定，导入结束后才能选择或删除。')
          .fontSize(12)
          .lineHeight(18)
          .fontColor(this.color('text_secondary'))
          .width('100%')
          .textAlign(TextAlign.Start)
      }
    }
    .width('100%')
    .padding(12)
    .backgroundColor(SettingsPanelSurfaceHelper.getBackground(this.themeState.currentTheme))
    .linearGradient(SettingsPanelSurfaceHelper.getSurfaceGradient(this.themeState.currentTheme))
    .backgroundBlurStyle(
      SettingsPanelSurfaceHelper.getBlurStyle(this.themeState.currentTheme),
      SettingsPanelSurfaceHelper.getBlurOptions(this.themeState.currentTheme)
    )
    .backgroundEffect(SettingsPanelSurfaceHelper.getBackgroundEffect(this.themeState.currentTheme))
    .borderRadius(18)
    .clip(true)
    .border({
      width: SettingsPanelSurfaceHelper.getBorderWidth(this.themeState.currentTheme),
      color: SettingsPanelSurfaceHelper.getBorderColor(this.themeState.currentTheme)
    })
    .shadow({
      radius: 16,
      color: SettingsPanelSurfaceHelper.getShadowColor(this.themeState.currentTheme),
      offsetX: 0,
      offsetY: 6
    })
    .key(
      `transfer_inbox_selection_${this.getSelectedUploadRecordCount()}_` +
        `${this.getSelectableUploadRecordCount()}_${this.viewState.recentUploads.length}`
    )
  }

  @Builder
  private buildRecentUploadsCard() {
    Column({ space: 14 }) {
      TransferCardHeaderView({
        themeState: this.themeState,
        title: '最近上传',
        subtitle: '上传成功的文件已经保存在当前设备上，可继续导入，也可删除记录及文件。'
      })

      if (this.viewState.recentUploads.length <= 0) {
        Column({ space: 12 }) {
          Column() {
            SymbolGlyph($r('sys.symbol.inbox_fill'))
              .fontSize(42)
              .fontColor([this.color('accent_primary')])
          }
          .width(82)
          .height(82)
          .justifyContent(FlexAlign.Center)
          .backgroundColor(this.color('comp_background_tertiary'))
          .borderRadius(26)

          Text('当前还没有收到文件')
            .fontSize(18)
            .fontWeight(FontWeight.Medium)
            .fontFamily(this.appFontFamily)
            .fontColor(this.color('text_primary'))
            .width('100%')
            .textAlign(TextAlign.Center)

          Text('启动服务后，在电脑或手机浏览器打开局域网地址即可上传。')
            .fontSize(13)
            .lineHeight(20)
            .fontFamily(this.appFontFamily)
            .fontColor(this.color('text_secondary'))
            .width('100%')
            .textAlign(TextAlign.Center)
            .maxLines(2)
        }
        .width('100%')
        .padding({ top: 40, bottom: 40, left: 18, right: 18 })
        .alignItems(HorizontalAlign.Center)
        .backgroundColor(this.color('comp_background_tertiary'))
        .borderRadius(20)
        .clip(true)
      } else {
        Column({ space: 12 }) {
          this.buildInboxSelectionToolbar()

          ForEach(this.viewState.recentUploads, (record: TransferUploadRecord) => {
            this.buildUploadRecord(record)
          }, (record: TransferUploadRecord) => record.id)
        }
        .width('100%')
      }
    }
    .width('100%')
    .padding(20)
    .backgroundColor(SettingsPanelSurfaceHelper.getBackground(this.themeState.currentTheme))
    .linearGradient(SettingsPanelSurfaceHelper.getSurfaceGradient(this.themeState.currentTheme))
    .backgroundBlurStyle(
      SettingsPanelSurfaceHelper.getBlurStyle(this.themeState.currentTheme),
      SettingsPanelSurfaceHelper.getBlurOptions(this.themeState.currentTheme)
    )
    .backgroundEffect(SettingsPanelSurfaceHelper.getBackgroundEffect(this.themeState.currentTheme))
    .borderRadius(24)
    .clip(true)
    .border({
      width: SettingsPanelSurfaceHelper.getBorderWidth(this.themeState.currentTheme),
      color: SettingsPanelSurfaceHelper.getBorderColor(this.themeState.currentTheme)
    })
    .shadow({
      radius: 22,
      color: SettingsPanelSurfaceHelper.getShadowColor(this.themeState.currentTheme),
      offsetX: 0,
      offsetY: 8
    })
    .key(
      `transfer_uploads_${this.viewState.renderVersion}_${this.viewState.recentUploads.length}_` +
        `${this.selectedUploadRecordIds.length}`
    )
  }

  @Builder
  private buildRefreshView() {
    Scroll() {
      Column({ space: 16 }) {
        Text(`${this.viewState.renderVersion}_${this.viewState.status}_${this.viewState.pairCode}`)
          .fontSize(1)
          .opacity(0)
          .width(1)
          .height(1)

        this.buildHeroCard()
        this.buildTransferTabs()
        Blank().height(this.navigationBarHeight + 32)
      }
      .width('100%')
      .padding({ left: 16, right: 16, top: 8, bottom: 0 })
      .key(
        `transfer_refresh_content_${this.viewState.status}_${this.viewState.phase}_` +
          `${this.viewState.pairCode}_${this.viewState.localAddresses.length}_${this.viewState.recentUploads.length}`
      )
    }
    .scrollBar(BarState.Off)
    .width('100%')
    .height('100%')
    .edgeEffect(EdgeEffect.Spring)
    .layoutWeight(1)
    .key(this.getRefreshRootRenderKey(this.viewState))
  }

  @Builder
  private buildScopeCard() {
    Column({ space: 10 }) {
      TransferCardHeaderView({
        themeState: this.themeState,
        title: '收件箱说明',
        subtitle: '上传完成后，文件会先保存在当前设备，再由你决定是否导入。'
      })

      Text('收件箱里的每个文件都已经在设备上。继续导入只是把该文件交给对应功能处理，不会影响浏览器端上传结果。')
        .fontSize(14)
        .lineHeight(22)
        .fontColor(this.color('text_primary'))
        .width('100%')
        .textAlign(TextAlign.Start)
        .padding(14)
        .backgroundColor(this.color('comp_background_tertiary'))
        .borderRadius(16)
        .clip(true)

      Text('如果不再需要某个文件，可以单独删除，也可以多选后批量执行“删除记录及文件”。')
        .fontSize(14)
        .lineHeight(22)
        .fontColor(this.color('text_secondary'))
        .width('100%')
        .textAlign(TextAlign.Start)
        .padding(14)
        .backgroundColor(this.color('comp_background_tertiary'))
        .borderRadius(16)
        .clip(true)
    }
    .width('100%')
    .padding(20)
    .backgroundColor(SettingsPanelSurfaceHelper.getBackground(this.themeState.currentTheme))
    .linearGradient(SettingsPanelSurfaceHelper.getSurfaceGradient(this.themeState.currentTheme))
    .backgroundBlurStyle(
      SettingsPanelSurfaceHelper.getBlurStyle(this.themeState.currentTheme),
      SettingsPanelSurfaceHelper.getBlurOptions(this.themeState.currentTheme)
    )
    .backgroundEffect(SettingsPanelSurfaceHelper.getBackgroundEffect(this.themeState.currentTheme))
    .borderRadius(24)
    .clip(true)
    .border({
      width: SettingsPanelSurfaceHelper.getBorderWidth(this.themeState.currentTheme),
      color: SettingsPanelSurfaceHelper.getBorderColor(this.themeState.currentTheme)
    })
    .shadow({
      radius: 22,
      color: SettingsPanelSurfaceHelper.getShadowColor(this.themeState.currentTheme),
      offsetX: 0,
      offsetY: 8
    })
  }

  build() {
    Column({ space: 0 }) {
      Text(`transfer_state_${this.viewState.renderVersion}_${this.viewState.status}_${this.viewState.pairCode}`)
        .fontSize(1)
        .opacity(0)
        .width(1)
        .height(1)

      this.buildRefreshView()
    }
    .width('100%')
    .height('100%')
    .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.TOP, SafeAreaEdge.BOTTOM])
    .key(
      `transfer_page_content_shell_${this.viewState.status}_${this.viewState.phase}_` +
        `${this.viewState.pairCode}_${this.viewState.localAddresses.length}_${this.viewState.recentUploads.length}`
    )
  }
}

@Component
export struct TransferPage {
  private readonly componentId: string = `${TAG}Shell`;

  @State themeState: ThemeAwareState = new ThemeAwareState();
  @StorageLink('appFontFamily') appFontFamily: string = 'HarmonyOS Sans';
  @StorageProp('statusBarHeight') statusBarHeight: number = 0;
  @StorageProp('navigationBarHeight') navigationBarHeight: number = 0;
  @State private pathStack: NavPathStack = new NavPathStack();

  aboutToAppear(): void {
    void ThemeAwareHelper.initializeThemeAware(this.componentId, this.themeState, undefined, (newState: ThemeAwareState) => {
      this.themeState = newState;
    });
  }

  aboutToDisappear(): void {
    ThemeAwareHelper.cleanupThemeAware(this.componentId);
  }

  private color(type: 'background' | 'panel_background' | 'comp_background_tertiary' | 'comp_background_secondary' |
    'text_primary' | 'text_secondary' | 'text_muted' | 'text_white' | 'text_black' | 'button_secondary' |
    'button_text_secondary' | 'icon_primary' | 'accent_primary'): Resource {
    return ThemeAwareHelper.getTestManagementThemedColor(type, this.themeState.currentTheme);
  }

  build() {
    HdsNavDestination() {
      Stack() {
        SharedPageBackgroundLayer({
          defaultBackgroundColor: this.color('background'),
          mode: GlobalBackgroundLayerMode.IMMERSIVE
        })
          .width('100%')
          .height('100%')
          .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.TOP, SafeAreaEdge.BOTTOM])

        Column({ space: 0 }) {
          Blank().height(SettingsPageTitleBarManager.getContentTopPadding(this.statusBarHeight))

          TransferPageContent()
            .width('100%')
            .layoutWeight(1)
        }
        .width('100%')
        .height('100%')
        .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.TOP, SafeAreaEdge.BOTTOM])

        SettingsImmersiveTitleBar({
          themeState: this.themeState,
          title: '局域网传书',
          appFontFamily: this.appFontFamily,
          pathStack: this.pathStack,
          backAction: (): boolean => false
        })
      }
    }
      .hideTitleBar(true)
      .ignoreLayoutSafeArea([LayoutSafeAreaType.SYSTEM], [LayoutSafeAreaEdge.TOP, LayoutSafeAreaEdge.BOTTOM])
      .onReady((context: NavDestinationContext) => {
        this.pathStack = context.pathStack;
      })
      .backgroundColor(Color.Transparent)
  }
}
