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
import {
  getTransferSignalClientService,
  TransferSignalClientService,
  TransferSignalServerMessageListener
} from '../Framework/Services/TransferSignalClientService';
import {
  getTransferNativeRtcService,
  TransferNativeRtcService
} from '../Framework/Services/TransferNativeRtcService';
import { getTransferUploadStoreService, TransferUploadStoreService } from '../Framework/Services/TransferUploadStoreService';
import {
  getTransferRtcFileReceiverService,
  TransferRtcFileReceiverResult,
  TransferRtcFileReceiverService
} from '../Framework/Services/TransferRtcFileReceiverService';
import {
  TransferConfig,
  TransferLocalAddress,
  TransferNativeRtcCandidate,
  TransferNativeRtcCandidateSignalPayload,
  TransferNativeRtcEvent,
  TransferNativeRtcEventList,
  TransferNativeRtcRuntime,
  TransferNativeRtcSdpResult,
  TransferNativeRtcSdpSignalPayload,
  TransferRuntimePhase,
  TransferRtcFileReceiverRuntime,
  TransferSignalConnectionStatus,
  TransferSignalOutboundMessageType,
  TransferSignalRole,
  TransferSignalRuntime,
  TransferSignalServerMessage,
  TransferServerStatus,
  TransferServerRuntime,
  TransferUploadProgressSnapshot,
  TransferUploadRecord,
  buildTransferLanAccessDataChannelMessage,
  buildTransferLanAccessSignalPayload,
  buildTransferNativeRtcCandidateSignalPayload,
  buildTransferNativeRtcSdpSignalPayload,
  cloneTransferConfig,
  cloneTransferLocalAddress,
  cloneTransferUploadProgressSnapshot,
  cloneTransferUploadRecords,
  createEmptyTransferNativeRtcRuntime,
  createEmptyTransferRtcFileReceiverRuntime,
  createEmptyTransferSignalRuntime,
  createEmptyTransferUploadProgressSnapshot,
  createDefaultTransferConfig,
  parseTransferNativeRtcCandidateSignalPayload,
  parseTransferNativeRtcSdpSignalPayload
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
  uploadProgress: TransferUploadProgressSnapshot;
  hasActiveUploadProgress: boolean;
  recentUploads: TransferUploadRecord[];
  hasRecentUploads: boolean;
  isBusy: boolean;
}

interface TransferPendingRtcSignalMessage {
  type: TransferSignalOutboundMessageType;
  payload: string;
  targetRole: TransferSignalRole;
  targetClientId: string;
}

type TransferSignalServerMessageHandler = (message: TransferSignalServerMessage) => void;

class TransferPageSignalMessageListener implements TransferSignalServerMessageListener {
  private readonly handler: TransferSignalServerMessageHandler;

  constructor(handler: TransferSignalServerMessageHandler) {
    this.handler = handler;
  }

  public onMessage(message: TransferSignalServerMessage): void {
    this.handler(message);
  }
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
    session: null,
    uploadProgress: createEmptyTransferUploadProgressSnapshot()
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
  const uploadProgress: TransferUploadProgressSnapshot = cloneTransferUploadProgressSnapshot(runtime.uploadProgress);
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
    uploadProgress: uploadProgress,
    hasActiveUploadProgress: uploadProgress.status === 'receiving',
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
  @StorageLink('appFontFamily') appFontFamily: string = 'HarmonyOS Sans';

  build() {
    Column({ space: 4 }) {
      Text(this.title)
        .fontSize(18)
        .fontWeight(FontWeight.Bold)
        .fontFamily(this.appFontFamily)
        .fontColor(getTransferColor('text_primary', this.themeState))
        .width('100%')
        .textAlign(TextAlign.Start)

      Text(this.subtitle)
        .fontSize(13)
        .fontFamily(this.appFontFamily)
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
  @StorageLink('appFontFamily') appFontFamily: string = 'HarmonyOS Sans';

  build() {
    Row() {
      Text(this.label)
        .fontSize(14)
        .fontFamily(this.appFontFamily)
        .fontColor(getTransferColor('text_secondary', this.themeState))

      Blank()

      Text(this.value)
        .fontSize(14)
        .fontWeight(FontWeight.Medium)
        .fontFamily(this.appFontFamily)
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
  @StorageLink('appFontFamily') appFontFamily: string = 'HarmonyOS Sans';

  build() {
    Column({ space: 8 }) {
      Text(this.title)
        .fontSize(13)
        .fontFamily(this.appFontFamily)
        .fontColor(getTransferColor('text_secondary', this.themeState))
        .width('100%')
        .textAlign(TextAlign.Start)

      Text(this.value)
        .fontSize(22)
        .fontWeight(FontWeight.Bold)
        .fontFamily(this.appFontFamily)
        .fontColor(getTransferColor('text_primary', this.themeState))
        .width('100%')
        .textAlign(TextAlign.Start)
        .maxLines(4)
        .textOverflow({ overflow: TextOverflow.Ellipsis })

      Text(this.hint)
        .fontSize(12)
        .lineHeight(18)
        .fontFamily(this.appFontFamily)
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
  private readonly signalService: TransferSignalClientService = getTransferSignalClientService();
  private readonly nativeRtcService: TransferNativeRtcService = getTransferNativeRtcService();
  private readonly configManager: TransferConfigManager = getTransferConfigManager();
  private readonly uploadStoreService: TransferUploadStoreService = getTransferUploadStoreService();
  private readonly rtcFileReceiverService: TransferRtcFileReceiverService = getTransferRtcFileReceiverService();
  private refreshTimer: number = -1;
  private isRefreshingUploads: boolean = false;
  private isDrainingNativeRtcEvents: boolean = false;
  private pendingNativeRtcSignalMessages: TransferPendingRtcSignalMessage[] = [];
  private signalMessageListener: TransferSignalServerMessageListener | null = null;
  private lastAutoSentLanAccessSignature: string = '';
  private lastDataChannelLanAccessSignature: string = '';
  private isSendingLanAccess: boolean = false;
  private autoStartAttempted: boolean = false;
  private autoSignalRoomAttempted: boolean = false;
  private isRunningPageAutomation: boolean = false;
  private hasLoadedInitialUploads: boolean = false;
  private lastCompletedUploadPromptId: string = '';

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
  @State private signalRuntime: TransferSignalRuntime = createEmptyTransferSignalRuntime();
  @State private heroSignalStatus: TransferSignalConnectionStatus = 'idle';
  @State private heroSignalRoomCode: string = '';
  @State private heroSignalPublicPageUrl: string = '';
  @State private heroSignalPeerCount: number = 0;
  @State private heroSignalExpiresAt: number = 0;
  @State private heroSignalUpdatedAt: number = 0;
  @State private nativeRtcRuntime: TransferNativeRtcRuntime = createEmptyTransferNativeRtcRuntime();
  @State private rtcFileReceiverRuntime: TransferRtcFileReceiverRuntime = createEmptyTransferRtcFileReceiverRuntime();
  @State private signalBusy: boolean = false;
  @State private nativeRtcBusy: boolean = false;
  @State private lanAccessBusy: boolean = false;
  @State private lanAccessStatusText: string = '等待公网房间和局域网服务就绪。';
  @State private lastLanAccessSentText: string = '尚未下发';

  aboutToAppear(): void {
    void ThemeAwareHelper.initializeThemeAware(this.componentId, this.themeState, undefined, (newState: ThemeAwareState) => {
      this.themeState = newState;
    });
    this.refreshSnapshot();
    this.attachSignalMessageListener();
    this.refreshSignalSnapshot();
    this.refreshNativeRtcSnapshot();
    this.refreshRtcFileReceiverSnapshot();
    void this.refreshUploads();
    void this.drainNativeRtcEvents();
    void this.tryAutoSendLanAccess(false);
    void this.ensurePageAutomationStarted();
    this.startRefreshTimer();
  }

  aboutToDisappear(): void {
    this.signalService.clearServerMessageListener();
    ThemeAwareHelper.cleanupThemeAware(this.componentId);
    this.stopRefreshTimer();
  }

  private color(type: TransferThemeColorType): Resource {
    return getTransferColor(type, this.themeState);
  }

  private attachSignalMessageListener(): void {
    if (this.signalMessageListener === null) {
      const listener: TransferSignalServerMessageListener =
        new TransferPageSignalMessageListener((message: TransferSignalServerMessage): void => {
          this.handleIncomingSignalMessage(message);
        });
      this.signalMessageListener = listener;
    }
    const activeListener = this.signalMessageListener;
    if (activeListener !== null) {
      this.signalService.setServerMessageListener(activeListener);
    }
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

  private applySignalRuntime(runtime: TransferSignalRuntime): void {
    this.signalRuntime = runtime;
    this.heroSignalStatus = runtime.status;
    this.heroSignalRoomCode = runtime.roomCode;
    this.heroSignalPublicPageUrl = runtime.publicPageUrl;
    this.heroSignalPeerCount = runtime.peerCount;
    this.heroSignalExpiresAt = runtime.expiresAt;
    this.heroSignalUpdatedAt = runtime.updatedAt;
  }

  private refreshSignalSnapshot(): void {
    this.applySignalRuntime(this.signalService.getRuntimeState());
  }

  private refreshNativeRtcSnapshot(): void {
    this.nativeRtcRuntime = this.nativeRtcService.getRuntimeState();
  }

  private refreshRtcFileReceiverSnapshot(): void {
    this.rtcFileReceiverRuntime = this.rtcFileReceiverService.getRuntimeState();
  }

  private async drainNativeRtcEvents(): Promise<void> {
    if (this.isDrainingNativeRtcEvents || this.nativeRtcRuntime.peerId.length <= 0) {
      this.refreshNativeRtcSnapshot();
      return;
    }
    this.isDrainingNativeRtcEvents = true;
    try {
      await this.flushPendingNativeRtcSignalMessages();
      const eventList: TransferNativeRtcEventList = this.nativeRtcService.pollEvents();
      await this.forwardNativeRtcEvents(eventList);
      this.refreshNativeRtcSnapshot();
      this.refreshRtcFileReceiverSnapshot();
    } catch (error) {
      logger.warn(TAG, `轮询Native RTC事件失败: ${this.stringifyError(error)}`);
      this.refreshNativeRtcSnapshot();
      this.refreshRtcFileReceiverSnapshot();
    } finally {
      this.isDrainingNativeRtcEvents = false;
    }
  }

  private async flushPendingNativeRtcSignalMessages(): Promise<void> {
    if (!this.canForwardNativeRtcSignals() || this.pendingNativeRtcSignalMessages.length <= 0) {
      return;
    }

    const pendingMessages = this.pendingNativeRtcSignalMessages;
    this.pendingNativeRtcSignalMessages = [];
    for (let index = 0; index < pendingMessages.length; index++) {
      const message = pendingMessages[index];
      try {
        await this.signalService.sendSignalMessage(
          message.type,
          message.payload,
          message.targetRole,
          message.targetClientId
        );
      } catch (error) {
        for (let remainingIndex = index; remainingIndex < pendingMessages.length; remainingIndex++) {
          this.pendingNativeRtcSignalMessages.push(pendingMessages[remainingIndex]);
        }
        throw new Error(this.stringifyError(error));
      }
    }
    this.refreshSignalSnapshot();
  }

  private enqueueNativeRtcSignalMessage(
    type: TransferSignalOutboundMessageType,
    payload: string,
    targetRole: TransferSignalRole,
    targetClientId: string
  ): void {
    const message: TransferPendingRtcSignalMessage = {
      type: type,
      payload: payload,
      targetRole: targetRole,
      targetClientId: targetClientId
    };
    this.pendingNativeRtcSignalMessages.push(message);
  }

  private getNativeRtcSignalTargetRole(): TransferSignalRole {
    return this.nativeRtcRuntime.role === 'host' ? 'peer' : 'host';
  }

  private canForwardNativeRtcSignals(): boolean {
    if (this.signalRuntime.status !== 'connected') {
      return false;
    }
    if (this.nativeRtcRuntime.role === 'host') {
      return this.signalRuntime.peerCount > 0;
    }
    return this.signalRuntime.hostConnected === true;
  }

  private buildLanAccessReadySignature(): string {
    const primaryAddress = this.getPrimaryAddress();
    if (this.signalRuntime.status !== 'connected') {
      return '';
    }
    if (this.signalRuntime.peerCount <= 0) {
      return '';
    }
    if (this.viewState.status !== 'running') {
      return '';
    }
    if (!this.viewState.hasSession || this.viewState.pairCode.length <= 0) {
      return '';
    }
    if (primaryAddress === null || primaryAddress.url.length <= 0) {
      return '';
    }
    return `${this.signalRuntime.roomCode}|${this.signalRuntime.peerCount}|${primaryAddress.url}|` +
      `${this.viewState.pairCode}`;
  }

  private buildLanAccessWaitingText(): string {
    if (this.signalRuntime.status !== 'connected') {
      return '等待公网信令通道连接。';
    }
    if (this.signalRuntime.peerCount <= 0) {
      return '等待 Worker 网页端输入房间码并连接。';
    }
    if (this.viewState.status !== 'running') {
      return '等待局域网传书服务启动。';
    }
    if (!this.viewState.hasSession || this.viewState.pairCode.length <= 0) {
      return '等待局域网传书会话和配对码生成。';
    }
    if (this.getPrimaryAddress() === null) {
      return '等待本机局域网访问地址生成。';
    }
    return '自动引导条件已满足，准备下发局域网地址。';
  }

  private setLanAccessStatusText(message: string): void {
    if (this.lanAccessStatusText !== message) {
      this.lanAccessStatusText = message;
    }
  }

  private isLanAccessReady(): boolean {
    return this.buildLanAccessReadySignature().length > 0;
  }

  private buildLanAccessPayloadText(): string {
    const primaryAddress = this.getPrimaryAddress();
    if (primaryAddress === null) {
      return '';
    }
    return buildTransferLanAccessSignalPayload(
      primaryAddress.url,
      this.viewState.pairCode,
      this.viewState.status,
      this.signalRuntime.roomCode
    );
  }

  private async tryAutoSendLanAccess(force: boolean): Promise<void> {
    const signature = this.buildLanAccessReadySignature();
    if (signature.length <= 0) {
      this.lastAutoSentLanAccessSignature = '';
      this.lastDataChannelLanAccessSignature = '';
      this.setLanAccessStatusText(this.buildLanAccessWaitingText());
      return;
    }

    if (!force && signature === this.lastAutoSentLanAccessSignature) {
      this.trySendLanAccessThroughDataChannel(signature);
      return;
    }

    await this.sendLanAccessToSignalPeer(signature, force);
  }

  private async sendLanAccessToSignalPeer(signature: string, force: boolean): Promise<void> {
    if (this.isSendingLanAccess) {
      return;
    }

    const payloadText = this.buildLanAccessPayloadText();
    const primaryAddress = this.getPrimaryAddress();
    if (payloadText.length <= 0 || primaryAddress === null) {
      this.setLanAccessStatusText(this.buildLanAccessWaitingText());
      return;
    }

    this.isSendingLanAccess = true;
    this.lanAccessBusy = true;
    this.setLanAccessStatusText(force ? '正在重新下发局域网地址。' : '检测到 Worker 网页端已连接，正在自动下发局域网地址。');
    try {
      await this.signalService.sendSignalMessage('lan_url', payloadText, 'peer', '');
      this.lastAutoSentLanAccessSignature = signature;
      this.lastLanAccessSentText = `${this.formatLanAccessTime(Date.now())} 已下发 ${primaryAddress.url}`;
      this.setLanAccessStatusText('已向 Worker 网页端下发局域网地址；网页端会显示倒计时并自动跳转。');
      this.trySendLanAccessThroughDataChannel(signature);
      this.refreshSignalSnapshot();
    } catch (error) {
      const errorMessage = this.stringifyError(error);
      logger.warn(TAG, `自动下发局域网地址失败: ${errorMessage}`);
      this.setLanAccessStatusText(`自动下发失败：${errorMessage}`);
    } finally {
      this.lanAccessBusy = false;
      this.isSendingLanAccess = false;
    }
  }

  private trySendLanAccessThroughDataChannel(signature: string): void {
    if (this.nativeRtcRuntime.status !== 'connected') {
      return;
    }
    if (signature !== this.lastAutoSentLanAccessSignature) {
      return;
    }
    if (signature === this.lastDataChannelLanAccessSignature) {
      return;
    }
    const payloadText = this.buildLanAccessPayloadText();
    if (payloadText.length <= 0) {
      return;
    }
    try {
      const dataChannelText = buildTransferLanAccessDataChannelMessage(payloadText);
      const runtime = this.nativeRtcService.sendText(dataChannelText);
      this.nativeRtcRuntime = runtime;
      if (runtime.lastError.length <= 0) {
        this.lastDataChannelLanAccessSignature = signature;
        logger.info(TAG, '已通过 Native RTC DataChannel 补发局域网地址。');
      } else {
        logger.warn(TAG, `Native RTC DataChannel 补发局域网地址失败: ${runtime.lastError}`);
      }
    } catch (error) {
      logger.warn(TAG, `通过 Native RTC DataChannel 补发局域网地址失败: ${this.stringifyError(error)}`);
      this.refreshNativeRtcSnapshot();
    }
  }

  private resetLanAccessState(message: string): void {
    this.lastAutoSentLanAccessSignature = '';
    this.lastDataChannelLanAccessSignature = '';
    this.lanAccessBusy = false;
    this.lastLanAccessSentText = '尚未下发';
    this.setLanAccessStatusText(message);
  }

  private async forwardNativeRtcEvents(eventList: TransferNativeRtcEventList): Promise<void> {
    if (!eventList.success || eventList.events.length <= 0) {
      return;
    }
    for (let index = 0; index < eventList.events.length; index++) {
      const event = eventList.events[index];
      await this.forwardNativeRtcEvent(event);
    }
  }

  private async forwardNativeRtcEvent(event: TransferNativeRtcEvent): Promise<void> {
    if (event.type === 'data_channel_open') {
      await this.tryAutoSendLanAccess(false);
      return;
    }
    if (event.type === 'message') {
      const messageText = event.message.length > 0 ? event.message : event.payload;
      if (messageText.length > 0) {
        await this.handleNativeRtcDataChannelText(messageText);
      }
      return;
    }
    if (event.type === 'local_description' && event.sdp.length > 0 && event.sdpType.length > 0) {
      const payload = buildTransferNativeRtcSdpSignalPayload(event.sdpType, event.sdp);
      const targetRole = this.getNativeRtcSignalTargetRole();
      if (event.sdpType === 'offer') {
        this.enqueueNativeRtcSignalMessage('offer', payload, targetRole, '');
        await this.flushPendingNativeRtcSignalMessages();
        return;
      }
      if (event.sdpType === 'answer') {
        this.enqueueNativeRtcSignalMessage('answer', payload, targetRole, '');
        await this.flushPendingNativeRtcSignalMessages();
        return;
      }
    }
    if (event.type === 'local_candidate' && event.candidate.length > 0 && event.sdpMid.length > 0) {
      const payload = buildTransferNativeRtcCandidateSignalPayload(
        event.candidate,
        event.sdpMid,
        event.sdpMLineIndex
      );
      this.enqueueNativeRtcSignalMessage('candidate', payload, this.getNativeRtcSignalTargetRole(), '');
      await this.flushPendingNativeRtcSignalMessages();
    }
  }

  private async handleNativeRtcDataChannelText(messageText: string): Promise<void> {
    const result: TransferRtcFileReceiverResult = await this.rtcFileReceiverService.handleDataChannelText(messageText);
    this.rtcFileReceiverRuntime = result.runtime;
    if (!result.handled) {
      logger.debug(TAG, '收到非文件协议 DataChannel 文本消息。');
      return;
    }
    if (result.ackText.length > 0) {
      const runtime = this.nativeRtcService.sendText(result.ackText);
      this.nativeRtcRuntime = runtime;
      if (runtime.lastError.length > 0) {
        logger.warn(TAG, `发送 DataChannel 文件协议 ACK 失败: ${runtime.lastError}`);
      }
    }
    if (result.shouldRefreshUploads) {
      await this.refreshUploads();
      this.showToast('RTC 文件已保存到收件箱');
    }
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
    const previousViewState = this.viewState;
    this.viewState = nextViewState;
    this.heroStatus = nextViewState.status;
    this.heroAddressCount = nextViewState.localAddresses.length;
    this.heroBusy = nextViewState.isBusy;
    this.handleUploadCompletionUiSignal(previousViewState, nextViewState);
  }

  private handleUploadCompletionUiSignal(
    previousViewState: TransferPageViewState,
    nextViewState: TransferPageViewState
  ): void {
    const progress = nextViewState.uploadProgress;
    if (previousViewState.uploadProgress.status === 'receiving' &&
      progress.status === 'completed' && progress.uploadId.length > 0 &&
      progress.uploadId !== this.lastCompletedUploadPromptId) {
      this.lastCompletedUploadPromptId = progress.uploadId;
      this.presentUploadCompleted();
      return;
    }

    if (!this.hasLoadedInitialUploads) {
      return;
    }

    const newestRecord = this.findNewestReceivedUpload(previousViewState.recentUploads, nextViewState.recentUploads);
    if (newestRecord !== null && newestRecord.id !== this.lastCompletedUploadPromptId) {
      this.lastCompletedUploadPromptId = newestRecord.id;
      this.presentUploadCompleted();
    }
  }

  private presentUploadCompleted(): void {
    this.activeTabIndex = 1;
    void this.refreshUploads();
    this.showToast('传书完成，已切到收件箱，请继续导入。');
  }

  private findNewestReceivedUpload(
    previousRecords: TransferUploadRecord[],
    nextRecords: TransferUploadRecord[]
  ): TransferUploadRecord | null {
    if (nextRecords.length <= 0) {
      return null;
    }
    for (const nextRecord of nextRecords) {
      if (nextRecord.status !== 'received') {
        continue;
      }
      if (this.findUploadRecordInList(previousRecords, nextRecord.id) === null) {
        return nextRecord;
      }
    }
    return null;
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
      this.hasLoadedInitialUploads = true;
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
      this.refreshSignalSnapshot();
      void this.drainNativeRtcEvents();
      void this.refreshUploads();
      void this.tryAutoSendLanAccess(false);
    }, 1500);
  }

  private async handlePageRefresh(): Promise<void> {
    if (this.isPageRefreshing) {
      return;
    }
    this.isPageRefreshing = true;
    try {
      this.refreshSnapshot();
      this.refreshSignalSnapshot();
      await this.drainNativeRtcEvents();
      await this.tryAutoSendLanAccess(false);
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
      const hostContext = (this.getUIContext().getHostContext() as common.UIAbilityContext);
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

  private async ensurePageAutomationStarted(): Promise<void> {
    if (this.isRunningPageAutomation) {
      return;
    }
    this.isRunningPageAutomation = true;
    try {
      const localReady = await this.ensureLocalTransferServiceStarted();
      if (localReady) {
        await this.ensureSignalRoomCreated();
      }
      await this.tryAutoSendLanAccess(false);
    } finally {
      this.isRunningPageAutomation = false;
    }
  }

  private async ensureLocalTransferServiceStarted(): Promise<boolean> {
    this.refreshSnapshot();
    if (this.viewState.status === 'running') {
      return true;
    }
    if (this.autoStartAttempted || this.viewState.isBusy) {
      return false;
    }
    this.autoStartAttempted = true;
    logger.info(TAG, '进入局域网传书页面，自动启动局域网传书服务。');
    return await this.startLocalTransferService(false, '自动启动失败');
  }

  private isSignalRoomReadyOrPending(): boolean {
    if (this.signalRuntime.roomCode.length <= 0) {
      return false;
    }
    return this.signalRuntime.status === 'creating' ||
      this.signalRuntime.status === 'created' ||
      this.signalRuntime.status === 'connecting' ||
      this.signalRuntime.status === 'connected';
  }

  private async ensureSignalRoomCreated(): Promise<void> {
    this.refreshSignalSnapshot();
    if (this.signalBusy || this.isSignalRoomReadyOrPending() || this.autoSignalRoomAttempted) {
      return;
    }
    this.autoSignalRoomAttempted = true;
    logger.info(TAG, '局域网传书服务已就绪，自动创建公网信令房间。');
    await this.createSignalRoomInternal(false, '自动创建公网房间失败');
  }

  private async startLocalTransferService(showSuccessToast: boolean, failurePrefix: string): Promise<boolean> {
    if (this.viewState.isBusy) {
      return false;
    }
    const abilityContext = this.resolveAbilityContext();
    if (abilityContext === null) {
      this.showToast('当前无法获取页面上下文，暂时不能启动服务');
      return false;
    }
    this.setBusyState(true);
    try {
      const runtime = await this.transferService.start(abilityContext);
      this.applyPageSnapshot(runtime, this.configManager.getConfig());
      if (runtime.status !== 'running') {
        const failureMessage = runtime.lastError.length > 0 ? runtime.lastError : runtime.infoMessage;
        logger.warn(TAG, `启动服务未进入运行态: ${failureMessage}`);
        this.showToast(`${failurePrefix}: ${failureMessage}`);
        return false;
      }
      logger.info(
        TAG,
        `页面收到启动成功快照: tick=${this.viewState.renderVersion}, port=${runtime.activePort}, ` +
          `addressCount=${runtime.localAddresses.length}`
      );
      await this.refreshUploads();
      await this.tryAutoSendLanAccess(false);
      if (showSuccessToast) {
        this.showToast('局域网传书服务已启动');
      }
      return true;
    } catch (error) {
      const errorMessage = this.stringifyError(error);
      logger.error(TAG, `启动服务失败: ${errorMessage}`);
      this.showToast(`${failurePrefix}: ${errorMessage}`);
      return false;
    } finally {
      this.setBusyState(false);
    }
  }

  private async handleStartService(): Promise<void> {
    const started = await this.startLocalTransferService(true, '启动失败');
    if (started) {
      await this.ensureSignalRoomCreated();
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
      `${viewState.pairCode}_${viewState.localAddresses.length}_${viewState.recentUploads.length}_` +
      `${this.signalRuntime.status}_${this.signalRuntime.roomCode}`;
  }

  private formatTransferByteSize(size: number): string {
    if (size < 1024) {
      return `${Math.max(0, Math.floor(size))} B`;
    }
    if (size < 1024 * 1024) {
      return `${(size / 1024).toFixed(1)} KB`;
    }
    if (size < 1024 * 1024 * 1024) {
      return `${(size / (1024 * 1024)).toFixed(1)} MB`;
    }
    return `${(size / (1024 * 1024 * 1024)).toFixed(2)} GB`;
  }

  private getUploadProgressTitle(): string {
    const progress = this.viewState.uploadProgress;
    if (progress.fileName.length <= 0) {
      return '正在接收文件';
    }
    return progress.fileName;
  }

  private getUploadProgressStatusText(): string {
    const progress = this.viewState.uploadProgress;
    if (progress.status === 'receiving') {
      return 'APP 正在接收并写入文件';
    }
    if (progress.status === 'completed') {
      return '文件已保存到设备收件箱';
    }
    if (progress.status === 'failed') {
      return '接收失败';
    }
    return '暂无正在接收的文件';
  }

  private getUploadProgressSizeText(): string {
    const progress = this.viewState.uploadProgress;
    if (progress.expectedBytes <= 0) {
      return this.formatTransferByteSize(progress.receivedBytes);
    }
    return `${this.formatTransferByteSize(progress.receivedBytes)} / ${this.formatTransferByteSize(progress.expectedBytes)}`;
  }

  private getUploadProgressPercentText(): string {
    return `${Math.round(this.viewState.uploadProgress.progressPercent)}%`;
  }

  private getUploadProgressClientText(): string {
    const progress = this.viewState.uploadProgress;
    if (progress.clientName.length > 0 && progress.clientIp.length > 0) {
      return `${progress.clientName} (${progress.clientIp})`;
    }
    if (progress.clientName.length > 0) {
      return progress.clientName;
    }
    return progress.clientIp;
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

  private formatLanAccessTime(timestamp: number): string {
    const date = new Date(timestamp);
    const hours = String(date.getHours()).padStart(2, '0');
    const minutes = String(date.getMinutes()).padStart(2, '0');
    const seconds = String(date.getSeconds()).padStart(2, '0');
    return `${hours}:${minutes}:${seconds}`;
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

  private getSignalRoomCodeText(): string {
    if (this.signalRuntime.roomCode.length <= 0) {
      return '尚未创建';
    }
    return this.signalRuntime.roomCode;
  }

  private getHeroSignalRoomCodeText(): string {
    if (this.heroSignalRoomCode.length <= 0) {
      return '尚未创建';
    }
    return this.heroSignalRoomCode;
  }

  private getSignalStatusLabel(status: TransferSignalConnectionStatus): string {
    if (status === 'creating') {
      return '创建中';
    }
    if (status === 'created') {
      return '已创建';
    }
    if (status === 'connecting') {
      return '连接中';
    }
    if (status === 'connected') {
      return '已连接';
    }
    if (status === 'closing') {
      return '关闭中';
    }
    if (status === 'closed') {
      return '已关闭';
    }
    if (status === 'error') {
      return '异常';
    }
    return '未创建';
  }

  private getSignalStatusText(): string {
    return this.getSignalStatusLabel(this.signalRuntime.status);
  }

  private getHeroSignalStatusText(): string {
    return this.getSignalStatusLabel(this.heroSignalStatus);
  }

  private formatSignalExpireText(expiresAt: number, roomCode: string): string {
    if (expiresAt <= 0 || roomCode.length <= 0) {
      return '未创建';
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

  private getSignalExpireText(): string {
    return this.formatSignalExpireText(this.signalRuntime.expiresAt, this.signalRuntime.roomCode);
  }

  private getHeroSignalExpireText(): string {
    return this.formatSignalExpireText(this.heroSignalExpiresAt, this.heroSignalRoomCode);
  }

  private buildSignalGuideText(): string {
    if (this.signalRuntime.roomCode.length <= 0 || this.signalRuntime.publicPageUrl.length <= 0) {
      return '请先在漫匣中创建公网信令房间，再复制房间指引。';
    }
    const guideLines: string[] = [
      '漫匣公网信令房间',
      `房间码：${this.signalRuntime.roomCode}`,
      `网页入口：${this.signalRuntime.publicPageUrl}`,
      '步骤：',
      '1. 在另一端打开网页入口并输入房间码。',
      '2. 等待房间连接成功后，APP 会自动下发局域网地址和配对码。',
      '3. 网页端收到地址后会自动倒计时跳转到 APP 的局域网直连页。',
      '说明：Worker 只转发连接控制消息，不中转文件数据。'
    ];
    return guideLines.join('\n');
  }

  private handleIncomingSignalMessage(message: TransferSignalServerMessage): void {
    if (message.type === 'offer' || message.type === 'answer') {
      this.applyIncomingSdpSignal(message);
      return;
    }
    if (message.type === 'candidate') {
      this.applyIncomingCandidateSignal(message);
      return;
    }
    if (message.type === 'bye') {
      void this.handleIncomingRtcBye();
    }
  }

  private async handleIncomingRtcBye(): Promise<void> {
    this.lastDataChannelLanAccessSignature = '';
    await this.rtcFileReceiverService.abortActiveReceive('远端已关闭 RTC 连接。');
    this.refreshRtcFileReceiverSnapshot();
    this.nativeRtcRuntime = this.nativeRtcService.closePeer();
    this.showToast('远端已关闭 RTC 连接');
  }

  private applyIncomingSdpSignal(message: TransferSignalServerMessage): void {
    const payload: TransferNativeRtcSdpSignalPayload | null = parseTransferNativeRtcSdpSignalPayload(message.payload);
    if (payload === null) {
      logger.warn(TAG, `远端 ${message.type} SDP 信令格式无效`);
      return;
    }

    const sdpType = this.resolveIncomingSdpType(message.type, payload.sdpType);
    if (sdpType.length <= 0) {
      logger.warn(TAG, `远端 SDP 类型无效: message=${message.type}, payload=${payload.sdpType}`);
      return;
    }

    this.nativeRtcRuntime = this.nativeRtcService.setRemoteDescription(sdpType, payload.sdp);
    if (sdpType === 'offer') {
      const result: TransferNativeRtcSdpResult = this.nativeRtcService.createAnswer();
      if (!result.success && result.errorCode !== 'SDP_PENDING') {
        logger.warn(TAG, `Native RTC Answer创建失败: ${result.message}`);
      }
    }
    this.refreshNativeRtcSnapshot();
    void this.drainNativeRtcEvents();
  }

  private applyIncomingCandidateSignal(message: TransferSignalServerMessage): void {
    const payload: TransferNativeRtcCandidateSignalPayload | null =
      parseTransferNativeRtcCandidateSignalPayload(message.payload);
    if (payload === null) {
      logger.warn(TAG, '远端 ICE Candidate 信令格式无效');
      return;
    }

    const runtime = this.nativeRtcService.getRuntimeState();
    if (runtime.peerId.length <= 0) {
      logger.warn(TAG, '收到远端 ICE Candidate 时 Native Peer 尚未创建');
      return;
    }

    const candidate: TransferNativeRtcCandidate = {
      peerId: runtime.peerId,
      candidate: payload.candidate,
      sdpMid: payload.sdpMid,
      sdpMLineIndex: payload.sdpMLineIndex
    };
    this.nativeRtcRuntime = this.nativeRtcService.addIceCandidate(candidate);
    void this.drainNativeRtcEvents();
  }

  private resolveIncomingSdpType(messageType: string, payloadType: string): string {
    if (payloadType === 'offer' || payloadType === 'answer') {
      return payloadType;
    }
    if (messageType === 'offer' || messageType === 'answer') {
      return messageType;
    }
    return '';
  }

  private async createSignalRoomInternal(showSuccessToast: boolean, failurePrefix: string): Promise<boolean> {
    if (this.signalBusy) {
      return false;
    }
    this.signalBusy = true;
    try {
      const runtime = await this.signalService.createHostRoom('漫匣局域网传书');
      this.applySignalRuntime(runtime);
      logger.info(
        TAG,
        `公网信令房间创建完成: status=${runtime.status}, roomCode=${runtime.roomCode}, publicPageUrl=${runtime.publicPageUrl}`
      );
      this.resetLanAccessState('等待 Worker 网页端输入房间码并连接。');
      await this.drainNativeRtcEvents();
      await this.tryAutoSendLanAccess(false);
      if (showSuccessToast) {
        this.showToast('公网信令房间已创建');
      }
      return true;
    } catch (error) {
      const errorMessage = this.stringifyError(error);
      logger.warn(TAG, `创建公网信令房间失败: ${errorMessage}`);
      this.refreshSignalSnapshot();
      if (failurePrefix.length > 0) {
        this.showToast(`${failurePrefix}: ${errorMessage}`);
      }
      return false;
    } finally {
      this.signalBusy = false;
      this.refreshSignalSnapshot();
    }
  }

  private async handleCreateSignalRoom(): Promise<void> {
    this.autoSignalRoomAttempted = false;
    await this.createSignalRoomInternal(true, '创建失败');
  }

  private async handleRefreshSignalRoomStatus(): Promise<void> {
    if (this.signalBusy) {
      return;
    }
    this.signalBusy = true;
    try {
      const runtime = await this.signalService.refreshRoomStatus();
      this.applySignalRuntime(runtime);
      await this.drainNativeRtcEvents();
      await this.tryAutoSendLanAccess(false);
      this.showToast('公网房间状态已刷新');
    } catch (error) {
      const errorMessage = this.stringifyError(error);
      logger.warn(TAG, `刷新公网信令房间失败: ${errorMessage}`);
      this.refreshSignalSnapshot();
      this.showToast(`刷新失败: ${errorMessage}`);
    } finally {
      this.signalBusy = false;
    }
  }

  private async handleReconnectSignalRoom(): Promise<void> {
    if (this.signalBusy) {
      return;
    }
    this.signalBusy = true;
    try {
      const runtime = await this.signalService.reconnectHostSocket();
      this.applySignalRuntime(runtime);
      await this.drainNativeRtcEvents();
      await this.tryAutoSendLanAccess(false);
      this.showToast('公网信令通道已重连');
    } catch (error) {
      const errorMessage = this.stringifyError(error);
      logger.warn(TAG, `重连公网信令通道失败: ${errorMessage}`);
      this.refreshSignalSnapshot();
      this.showToast(`重连失败: ${errorMessage}`);
    } finally {
      this.signalBusy = false;
    }
  }

  private async handleCloseSignalRoom(): Promise<void> {
    if (this.signalBusy) {
      return;
    }
    this.signalBusy = true;
    try {
      const runtime = await this.signalService.closeRoom();
      this.applySignalRuntime(runtime);
      this.resetLanAccessState('公网信令房间已关闭，自动引导已停止。');
      this.showToast('公网信令房间已关闭');
    } catch (error) {
      const errorMessage = this.stringifyError(error);
      logger.warn(TAG, `关闭公网信令房间失败: ${errorMessage}`);
      this.refreshSignalSnapshot();
      this.showToast(`关闭失败: ${errorMessage}`);
    } finally {
      this.signalBusy = false;
    }
  }

  private async handleSignalPing(): Promise<void> {
    if (this.signalBusy) {
      return;
    }
    this.signalBusy = true;
    try {
      const runtime = await this.signalService.sendPing();
      this.applySignalRuntime(runtime);
      this.showToast('已发送信令心跳');
    } catch (error) {
      const errorMessage = this.stringifyError(error);
      logger.warn(TAG, `发送公网信令心跳失败: ${errorMessage}`);
      this.refreshSignalSnapshot();
      this.showToast(`发送失败: ${errorMessage}`);
    } finally {
      this.signalBusy = false;
    }
  }

  private async handleSendLanAccessNow(): Promise<void> {
    if (!this.isLanAccessReady()) {
      this.setLanAccessStatusText(this.buildLanAccessWaitingText());
      this.showToast('自动引导条件尚未满足');
      return;
    }
    await this.tryAutoSendLanAccess(true);
  }

  private async handleCopySignalRoomCode(): Promise<void> {
    if (this.signalRuntime.roomCode.length <= 0) {
      this.showToast('请先创建公网信令房间');
      return;
    }
    await this.copyPlainText(this.signalRuntime.roomCode, '公网房间码已复制');
  }

  private async handleCopySignalPublicLink(): Promise<void> {
    if (this.signalRuntime.publicPageUrl.length <= 0) {
      this.showToast('请先创建公网信令房间');
      return;
    }
    await this.copyPlainText(this.signalRuntime.publicPageUrl, '公网网页链接已复制');
  }

  private async handleCopySignalGuide(): Promise<void> {
    if (this.signalRuntime.roomCode.length <= 0) {
      this.showToast('请先创建公网信令房间');
      return;
    }
    await this.copyPlainText(this.buildSignalGuideText(), '公网房间指引已复制');
  }

  private getNativeRtcStatusText(): string {
    if (this.nativeRtcRuntime.status === 'probing') {
      return '检测中';
    }
    if (this.nativeRtcRuntime.status === 'ready') {
      return '可用';
    }
    if (this.nativeRtcRuntime.status === 'creating_peer') {
      return '创建Peer中';
    }
    if (this.nativeRtcRuntime.status === 'signaling') {
      return '信令交换中';
    }
    if (this.nativeRtcRuntime.status === 'connected') {
      return '已连接';
    }
    if (this.nativeRtcRuntime.status === 'failed') {
      return '异常';
    }
    if (this.nativeRtcRuntime.status === 'closed') {
      return '已关闭';
    }
    if (this.nativeRtcRuntime.status === 'unavailable') {
      return '不可用';
    }
    return '未检测';
  }

  private getNativeRtcBackendText(): string {
    const backend = this.nativeRtcRuntime.capabilities.backend;
    if (backend === 'libdatachannel') {
      return 'libdatachannel';
    }
    if (backend === 'stub') {
      return 'stub 外壳';
    }
    return '未加载';
  }

  private getNativeRtcSupportText(): string {
    return this.nativeRtcRuntime.capabilities.dataChannelSupported ? '支持' : '未支持';
  }

  private getNativeRtcPeerText(): string {
    return this.nativeRtcRuntime.peerId.length > 0 ? this.nativeRtcRuntime.peerId : '未创建';
  }

  private getRtcFileReceiverStatusText(): string {
    if (this.rtcFileReceiverRuntime.status === 'receiving') {
      return '接收中';
    }
    if (this.rtcFileReceiverRuntime.status === 'completed') {
      return '已完成';
    }
    if (this.rtcFileReceiverRuntime.status === 'failed') {
      return '异常';
    }
    return '空闲';
  }

  private getRtcFileReceiverProgressText(): string {
    const runtime = this.rtcFileReceiverRuntime;
    if (runtime.expectedBytes <= 0) {
      return '暂无文件';
    }
    const percent = Math.floor((runtime.receivedBytes / runtime.expectedBytes) * 100);
    return `${runtime.receivedBytes} / ${runtime.expectedBytes} 字节 · ${percent}%`;
  }

  private handleProbeNativeRtcCapabilities(): void {
    if (this.nativeRtcBusy) {
      return;
    }
    this.nativeRtcBusy = true;
    try {
      const runtime = this.nativeRtcService.probeCapabilities();
      this.nativeRtcRuntime = runtime;
      this.showToast(runtime.capabilities.dataChannelSupported ? 'Native RTC 可用' : 'Native RTC 后端未就绪');
    } catch (error) {
      const errorMessage = this.stringifyError(error);
      logger.warn(TAG, `检测Native RTC能力失败: ${errorMessage}`);
      this.refreshNativeRtcSnapshot();
      this.showToast(`检测失败: ${errorMessage}`);
    } finally {
      this.nativeRtcBusy = false;
    }
  }

  private handleCreateNativeRtcHostPeer(): void {
    if (this.nativeRtcBusy) {
      return;
    }
    this.nativeRtcBusy = true;
    try {
      const runtime = this.nativeRtcService.createHostPeer(this.signalRuntime.roomCode);
      this.nativeRtcRuntime = runtime;
      if (runtime.peerId.length > 0 && runtime.lastError.length <= 0) {
        const result: TransferNativeRtcSdpResult = this.nativeRtcService.createOffer();
        if (!result.success && result.errorCode !== 'SDP_PENDING') {
          logger.warn(TAG, `Native RTC Offer创建失败: ${result.message}`);
        }
        void this.drainNativeRtcEvents();
      }
      this.showToast(runtime.lastError.length > 0 ? 'Native RTC 后端未就绪' : 'Native Host Peer 已创建');
    } catch (error) {
      const errorMessage = this.stringifyError(error);
      logger.warn(TAG, `创建Native RTC Host Peer失败: ${errorMessage}`);
      this.refreshNativeRtcSnapshot();
      this.showToast(`创建失败: ${errorMessage}`);
    } finally {
      this.nativeRtcBusy = false;
    }
  }

  private async handleCloseNativeRtcPeer(): Promise<void> {
    if (this.nativeRtcBusy) {
      return;
    }
    this.nativeRtcBusy = true;
    try {
      if (this.signalRuntime.status === 'connected') {
        await this.signalService.sendSignalMessage('bye', '', this.getNativeRtcSignalTargetRole(), '');
      }
      this.lastDataChannelLanAccessSignature = '';
      await this.rtcFileReceiverService.abortActiveReceive('Native Peer 已关闭。');
      this.refreshRtcFileReceiverSnapshot();
      this.nativeRtcRuntime = this.nativeRtcService.closePeer();
      this.showToast('Native Peer 已关闭');
    } catch (error) {
      const errorMessage = this.stringifyError(error);
      logger.warn(TAG, `关闭Native RTC Peer失败: ${errorMessage}`);
      this.refreshNativeRtcSnapshot();
      this.showToast(`关闭失败: ${errorMessage}`);
    } finally {
      this.nativeRtcBusy = false;
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

  private getHeroSignalMetaText(): string {
    return `Peer ${this.heroSignalPeerCount} · ${this.getHeroSignalExpireText()} · ${this.lastLanAccessSentText}`;
  }

  private getHeroSignalPublicPageText(): string {
    if (this.heroSignalPublicPageUrl.length > 0) {
      return this.heroSignalPublicPageUrl;
    }
    return '公网网页入口会在房间创建后显示';
  }

  private getHeroSignalCreateLabel(): string {
    if (this.heroSignalRoomCode.length > 0) {
      return '重建公网房间';
    }
    return '创建公网房间';
  }

  private isHeroSignalCopyRoomCodeEnabled(): boolean {
    return !this.signalBusy && this.heroSignalRoomCode.length > 0;
  }

  private isHeroSignalCopyPublicLinkEnabled(): boolean {
    return !this.signalBusy && this.heroSignalPublicPageUrl.length > 0;
  }

  private isHeroSignalSendLanAccessEnabled(): boolean {
    return !this.signalBusy && !this.lanAccessBusy && this.isLanAccessReady();
  }

  private getHeroSignalActionForegroundColor(styleKind: number, enabled: boolean): ResourceColor {
    if (!enabled) {
      return 'rgba(255, 255, 255, 0.48)';
    }
    return this.getActionForegroundColor(styleKind);
  }

  private getHeroSignalActionBackgroundColor(styleKind: number, enabled: boolean): ResourceColor {
    if (!enabled) {
      return 'rgba(255, 255, 255, 0.10)';
    }
    return this.getActionBackgroundColor(styleKind);
  }

  @Builder
  private buildHeroSignalCreateRoomButton() {
    Button() {
      Row({ space: 6 }) {
        SymbolGlyph($r('sys.symbol.play_fill'))
          .fontSize(14)
          .fontColor([this.getHeroSignalActionForegroundColor(ACTION_STYLE_PRIMARY, !this.signalBusy)])

        Text(this.getHeroSignalCreateLabel())
          .fontSize(12)
          .fontFamily(this.appFontFamily)
          .fontColor(this.getHeroSignalActionForegroundColor(ACTION_STYLE_PRIMARY, !this.signalBusy))
          .maxLines(1)
      }
      .justifyContent(FlexAlign.Center)
    }
    .height(36)
    .borderRadius(12)
    .enabled(!this.signalBusy)
    .layoutWeight(1)
    .backgroundColor(this.getHeroSignalActionBackgroundColor(ACTION_STYLE_PRIMARY, !this.signalBusy))
    .padding({ left: 12, right: 12 })
    .opacity(!this.signalBusy ? 1 : 0.62)
    .key(
      `transfer_hero_signal_create_${this.heroSignalStatus}_${this.heroSignalRoomCode}_` +
        `${this.heroSignalPublicPageUrl}_${this.heroSignalUpdatedAt}_${this.signalBusy ? 'busy' : 'idle'}`
    )
    .onClick(() => {
      void this.handleCreateSignalRoom();
    })
  }

  @Builder
  private buildHeroSignalCopyRoomCodeButton() {
    Button() {
      Row({ space: 6 }) {
        SymbolGlyph($r('sys.symbol.checkmark_circle_fill'))
          .fontSize(14)
          .fontColor([this.getHeroSignalActionForegroundColor(ACTION_STYLE_INFO, this.isHeroSignalCopyRoomCodeEnabled())])

        Text('复制房间码')
          .fontSize(12)
          .fontFamily(this.appFontFamily)
          .fontColor(this.getHeroSignalActionForegroundColor(ACTION_STYLE_INFO, this.isHeroSignalCopyRoomCodeEnabled()))
          .maxLines(1)
      }
      .justifyContent(FlexAlign.Center)
    }
    .height(36)
    .borderRadius(12)
    .enabled(this.isHeroSignalCopyRoomCodeEnabled())
    .layoutWeight(1)
    .backgroundColor(this.getHeroSignalActionBackgroundColor(ACTION_STYLE_INFO, this.isHeroSignalCopyRoomCodeEnabled()))
    .padding({ left: 12, right: 12 })
    .opacity(this.isHeroSignalCopyRoomCodeEnabled() ? 1 : 0.62)
    .key(
      `transfer_hero_signal_copy_code_${this.heroSignalRoomCode}_${this.heroSignalUpdatedAt}_` +
        `${this.signalBusy ? 'busy' : 'idle'}`
    )
    .onClick(() => {
      void this.handleCopySignalRoomCode();
    })
  }

  @Builder
  private buildHeroSignalCopyPublicLinkButton() {
    Button() {
      Row({ space: 6 }) {
        SymbolGlyph($r('sys.symbol.link'))
          .fontSize(14)
          .fontColor([this.getHeroSignalActionForegroundColor(ACTION_STYLE_NEUTRAL, this.isHeroSignalCopyPublicLinkEnabled())])

        Text('复制网页链接')
          .fontSize(12)
          .fontFamily(this.appFontFamily)
          .fontColor(this.getHeroSignalActionForegroundColor(ACTION_STYLE_NEUTRAL, this.isHeroSignalCopyPublicLinkEnabled()))
          .maxLines(1)
      }
      .justifyContent(FlexAlign.Center)
    }
    .height(36)
    .borderRadius(12)
    .enabled(this.isHeroSignalCopyPublicLinkEnabled())
    .layoutWeight(1)
    .backgroundColor(this.getHeroSignalActionBackgroundColor(ACTION_STYLE_NEUTRAL, this.isHeroSignalCopyPublicLinkEnabled()))
    .padding({ left: 12, right: 12 })
    .opacity(this.isHeroSignalCopyPublicLinkEnabled() ? 1 : 0.62)
    .key(
      `transfer_hero_signal_copy_link_${this.heroSignalPublicPageUrl}_${this.heroSignalUpdatedAt}_` +
        `${this.signalBusy ? 'busy' : 'idle'}`
    )
    .onClick(() => {
      void this.handleCopySignalPublicLink();
    })
  }

  @Builder
  private buildHeroSignalSendLanAccessButton() {
    Button() {
      Row({ space: 6 }) {
        SymbolGlyph($r('sys.symbol.link'))
          .fontSize(14)
          .fontColor([this.getHeroSignalActionForegroundColor(ACTION_STYLE_PRIMARY, this.isHeroSignalSendLanAccessEnabled())])

        Text('下发局域网地址')
          .fontSize(12)
          .fontFamily(this.appFontFamily)
          .fontColor(this.getHeroSignalActionForegroundColor(ACTION_STYLE_PRIMARY, this.isHeroSignalSendLanAccessEnabled()))
          .maxLines(1)
      }
      .justifyContent(FlexAlign.Center)
    }
    .height(36)
    .borderRadius(12)
    .enabled(this.isHeroSignalSendLanAccessEnabled())
    .layoutWeight(1)
    .backgroundColor(this.getHeroSignalActionBackgroundColor(ACTION_STYLE_PRIMARY, this.isHeroSignalSendLanAccessEnabled()))
    .padding({ left: 12, right: 12 })
    .opacity(this.isHeroSignalSendLanAccessEnabled() ? 1 : 0.62)
    .key(
      `transfer_hero_signal_send_lan_${this.heroSignalStatus}_${this.heroSignalRoomCode}_` +
        `${this.heroSignalPeerCount}_${this.lanAccessBusy ? 'lan_busy' : 'lan_idle'}_` +
        `${this.signalBusy ? 'signal_busy' : 'signal_idle'}_${this.heroSignalUpdatedAt}`
    )
    .onClick(() => {
      void this.handleSendLanAccessNow();
    })
  }

  @Builder
  private buildHeroSignalRoomPanel() {
    Column({ space: 10 }) {
      Row({ space: 12 }) {
        Column({ space: 5 }) {
          Text('公网房间码')
            .fontSize(12)
            .fontFamily(this.appFontFamily)
            .fontColor('rgba(255, 255, 255, 0.72)')
            .width('100%')
            .textAlign(TextAlign.Start)

          Text(this.getHeroSignalRoomCodeText())
            .fontSize(24)
            .fontWeight(FontWeight.Bold)
            .fontFamily(this.appFontFamily)
            .fontColor('#FFFFFF')
            .width('100%')
            .textAlign(TextAlign.Start)
            .maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
        }
        .layoutWeight(1)
        .alignItems(HorizontalAlign.Start)

        Text(this.getHeroSignalStatusText())
          .fontSize(12)
          .fontWeight(FontWeight.Medium)
          .fontFamily(this.appFontFamily)
          .fontColor('#FFFFFF')
          .padding({ left: 12, right: 12, top: 6, bottom: 6 })
          .backgroundColor('rgba(255, 255, 255, 0.14)')
          .borderRadius(999)
      }
      .width('100%')
      .alignItems(VerticalAlign.Top)

      Text(this.getHeroSignalMetaText())
        .fontSize(12)
        .lineHeight(18)
        .fontFamily(this.appFontFamily)
        .fontColor('rgba(255, 255, 255, 0.78)')
        .width('100%')
        .textAlign(TextAlign.Start)
        .maxLines(2)
        .textOverflow({ overflow: TextOverflow.Ellipsis })

      Text(this.getHeroSignalPublicPageText())
        .fontSize(12)
        .lineHeight(18)
        .fontFamily(this.appFontFamily)
        .fontColor('rgba(255, 255, 255, 0.72)')
        .width('100%')
        .textAlign(TextAlign.Start)
        .maxLines(2)
        .textOverflow({ overflow: TextOverflow.Ellipsis })

      Text(this.lanAccessStatusText)
        .fontSize(12)
        .lineHeight(18)
        .fontFamily(this.appFontFamily)
        .fontColor('rgba(255, 255, 255, 0.82)')
        .width('100%')
        .textAlign(TextAlign.Start)
        .maxLines(3)
        .textOverflow({ overflow: TextOverflow.Ellipsis })

      Row({ space: 10 }) {
        this.buildHeroSignalCreateRoomButton()
        this.buildHeroSignalCopyRoomCodeButton()
      }
      .width('100%')

      Row({ space: 10 }) {
        this.buildHeroSignalCopyPublicLinkButton()
        this.buildHeroSignalSendLanAccessButton()
      }
      .width('100%')
    }
    .width('100%')
    .padding(14)
    .backgroundColor('rgba(255, 255, 255, 0.12)')
    .borderRadius(18)
    .clip(true)
    .key(
      `transfer_hero_signal_${this.heroSignalStatus}_${this.heroSignalRoomCode}_` +
        `${this.heroSignalPublicPageUrl}_${this.heroSignalPeerCount}_${this.heroSignalUpdatedAt}_` +
        `${this.signalBusy ? 'signal_busy' : 'signal_idle'}_${this.lanAccessBusy ? 'lan_busy' : 'lan_idle'}_` +
        `${this.lastLanAccessSentText}_${this.lanAccessStatusText}`
    )
  }

  @Builder
  private buildHeroUploadProgressMetaRow(label: string, value: string) {
    Row({ space: 10 }) {
      Text(label)
        .fontSize(12)
        .fontFamily(this.appFontFamily)
        .fontColor('rgba(255, 255, 255, 0.68)')
        .width(64)
        .textAlign(TextAlign.Start)
        .maxLines(1)

      Text(value)
        .fontSize(12)
        .fontFamily(this.appFontFamily)
        .fontColor('rgba(255, 255, 255, 0.88)')
        .layoutWeight(1)
        .textAlign(TextAlign.End)
        .maxLines(2)
        .textOverflow({ overflow: TextOverflow.Ellipsis })
    }
    .width('100%')
    .alignItems(VerticalAlign.Center)
  }

  @Builder
  private buildHeroUploadProgressContent() {
    Column({ space: 18 }) {
      Row({ space: 12 }) {
        Column() {
          SymbolGlyph($r('sys.symbol.square_and_arrow_down'))
            .fontSize(30)
            .fontColor(['#FFFFFF'])
        }
        .width(56)
        .height(56)
        .justifyContent(FlexAlign.Center)
        .backgroundColor('rgba(255, 255, 255, 0.16)')
        .borderRadius(18)

        Column({ space: 6 }) {
          Text('正在接收文件')
            .fontSize(20)
            .fontWeight(FontWeight.Bold)
            .fontFamily(this.appFontFamily)
            .fontColor('#FFFFFF')
            .width('100%')
            .textAlign(TextAlign.Start)

          Text(this.getUploadProgressStatusText())
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

        Text(this.getUploadProgressPercentText())
          .fontSize(16)
          .fontWeight(FontWeight.Bold)
          .fontFamily(this.appFontFamily)
          .fontColor('#FFFFFF')
          .padding({ left: 12, right: 12, top: 6, bottom: 6 })
          .backgroundColor('rgba(255, 255, 255, 0.16)')
          .borderRadius(999)
      }
      .width('100%')
      .alignItems(VerticalAlign.Top)

      Column({ space: 12 }) {
        Text(this.getUploadProgressTitle())
          .fontSize(17)
          .fontWeight(FontWeight.Medium)
          .fontFamily(this.appFontFamily)
          .fontColor('#FFFFFF')
          .width('100%')
          .textAlign(TextAlign.Start)
          .maxLines(2)
          .textOverflow({ overflow: TextOverflow.Ellipsis })

        Progress({
          value: this.viewState.uploadProgress.progressPercent,
          total: 100,
          type: ProgressType.Linear
        })
          .width('100%')
          .height(8)
          .color('#FFFFFF')
          .backgroundColor('rgba(255, 255, 255, 0.18)')
          .animation({ duration: 180, curve: Curve.EaseOut })

        Row() {
          Text(this.getUploadProgressSizeText())
            .fontSize(12)
            .fontFamily(this.appFontFamily)
            .fontColor('rgba(255, 255, 255, 0.84)')
            .layoutWeight(1)
            .textAlign(TextAlign.Start)
            .maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis })

          Text(this.getUploadProgressPercentText())
            .fontSize(12)
            .fontWeight(FontWeight.Medium)
            .fontFamily(this.appFontFamily)
            .fontColor('#FFFFFF')
            .textAlign(TextAlign.End)
            .maxLines(1)
        }
        .width('100%')

        if (this.viewState.uploadProgress.clientName.length > 0 || this.viewState.uploadProgress.clientIp.length > 0) {
          Divider()
            .strokeWidth(1)
            .color('rgba(255, 255, 255, 0.16)')
            .width('100%')

          this.buildHeroUploadProgressMetaRow('来源设备', this.getUploadProgressClientText())
        }
      }
      .width('100%')
      .padding(14)
      .backgroundColor('rgba(255, 255, 255, 0.12)')
      .borderRadius(18)
      .clip(true)
    }
    .width('100%')
    .transition(TransitionEffect.asymmetric(
      TransitionEffect.OPACITY.animation({ duration: 240, curve: Curve.EaseOut }).combine(
        TransitionEffect.translate({ y: 10 }).animation({ duration: 240, curve: Curve.EaseOut })
      ),
      TransitionEffect.OPACITY.animation({ duration: 170, curve: Curve.EaseIn }).combine(
        TransitionEffect.translate({ y: -8 }).animation({ duration: 170, curve: Curve.EaseIn })
      )
    ))
    .key(`transfer_hero_upload_content_${this.viewState.uploadProgress.uploadId}_${this.viewState.uploadProgress.status}`)
  }

  private isHeroUploadProgressVisible(): boolean {
    return this.viewState.uploadProgress.status === 'receiving';
  }

  @Builder
  private buildHeroDefaultContent() {
    Column({ space: 18 }) {
      Row({ space: 12 }) {
        Column() {
          SymbolGlyph($r('sys.symbol.computer_share_fill'))
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

      this.buildHeroSignalRoomPanel()

      Row({ space: 10 }) {
        this.buildHeroServiceToggleButton()
        this.buildHeroCopyAddressButton()
        this.buildHeroRefreshButton()
      }
      .width('100%')
    }
    .width('100%')
    .transition(TransitionEffect.asymmetric(
      TransitionEffect.OPACITY.animation({ duration: 240, curve: Curve.EaseOut }).combine(
        TransitionEffect.translate({ y: 10 }).animation({ duration: 240, curve: Curve.EaseOut })
      ),
      TransitionEffect.OPACITY.animation({ duration: 170, curve: Curve.EaseIn }).combine(
        TransitionEffect.translate({ y: -8 }).animation({ duration: 170, curve: Curve.EaseIn })
      )
    ))
    .key('transfer_hero_default_content')
  }

  @Builder
  private buildHeroCard() {
    Stack({ alignContent: Alignment.TopEnd }) {
      Column() {
        if (this.isHeroUploadProgressVisible()) {
          this.buildHeroUploadProgressContent()
        } else {
          this.buildHeroDefaultContent()
        }
      }
      .width('100%')
      .animation({ duration: 260, curve: Curve.EaseInOut })

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
    .key('transfer_hero_card')
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
      if (this.viewState.hasActiveUploadProgress) {
        this.buildActiveUploadProgressCard()
      }
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
  private buildActiveUploadProgressCard() {
    Column({ space: 14 }) {
      TransferCardHeaderView({
        themeState: this.themeState,
        title: '正在接收',
        subtitle: '网页端与 APP 端均以设备实际接收并写入的进度为准。'
      })

      Column({ space: 10 }) {
        Row() {
          Text(this.getUploadProgressTitle())
            .fontSize(15)
            .fontWeight(FontWeight.Medium)
            .fontFamily(this.appFontFamily)
            .fontColor(this.color('text_primary'))
            .layoutWeight(1)
            .maxLines(2)
            .textOverflow({ overflow: TextOverflow.Ellipsis })

          Text(this.getUploadProgressPercentText())
            .fontSize(15)
            .fontWeight(FontWeight.Bold)
            .fontFamily(this.appFontFamily)
            .fontColor(this.color('accent_primary'))
        }
        .width('100%')

        Progress({
          value: this.viewState.uploadProgress.progressPercent,
          total: 100,
          type: ProgressType.Linear
        })
          .width('100%')
          .height(6)
          .color(this.color('accent_primary'))
          .backgroundColor(this.color('comp_background_tertiary'))
          .animation({ duration: 180, curve: Curve.EaseOut })

        TransferInfoRowView({
          themeState: this.themeState,
          label: '接收状态',
          value: this.getUploadProgressStatusText()
        })
        TransferInfoRowView({
          themeState: this.themeState,
          label: '已接收',
          value: this.getUploadProgressSizeText()
        })

        if (this.viewState.uploadProgress.clientName.length > 0 || this.viewState.uploadProgress.clientIp.length > 0) {
          TransferInfoRowView({
            themeState: this.themeState,
            label: '来源设备',
            value: this.getUploadProgressClientText()
          })
        }
      }
      .width('100%')
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
    .transition(TransitionEffect.asymmetric(
      TransitionEffect.OPACITY.animation({ duration: 220, curve: Curve.EaseOut }).combine(
        TransitionEffect.translate({ y: 10 }).animation({ duration: 220, curve: Curve.EaseOut })
      ),
      TransitionEffect.OPACITY.animation({ duration: 160, curve: Curve.EaseIn }).combine(
        TransitionEffect.translate({ y: -6 }).animation({ duration: 160, curve: Curve.EaseIn })
      )
    ))
    .key(
      `transfer_active_upload_${this.viewState.uploadProgress.uploadId}_` +
        `${this.viewState.uploadProgress.status}_${this.viewState.uploadProgress.progressPercent}_` +
        `${this.viewState.uploadProgress.updatedAt}`
    )
  }

  @Builder
  private buildSignalTabContent() {
    Column({ space: 16 }) {
      this.buildSignalRoomCard()
      this.buildNativeRtcCard()
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
  private buildSignalRoomCard() {
    Column({ space: 14 }) {
      TransferCardHeaderView({
        themeState: this.themeState,
        title: '公网房间码',
        subtitle: '通过 Worker 创建短时信令房间；Worker 只做控制消息转发，不中转文件数据。'
      })

      TransferEmphasisValueCardView({
        themeState: this.themeState,
        title: '房间码',
        value: this.getSignalRoomCodeText(),
        hint: '另一端可在公网传书入口输入该房间码，用于后续建立控制面连接。'
      })

      TransferInfoRowView({ themeState: this.themeState, label: '信令状态', value: this.getSignalStatusText() })
      TransferInfoRowView({ themeState: this.themeState, label: '有效期', value: this.getSignalExpireText() })
      TransferInfoRowView({
        themeState: this.themeState,
        label: 'Host连接',
        value: this.signalRuntime.hostConnected ? '已连接' : '未连接'
      })
      TransferInfoRowView({ themeState: this.themeState, label: 'Peer数量', value: String(this.signalRuntime.peerCount) })
      TransferInfoRowView({
        themeState: this.themeState,
        label: '网页入口',
        value: this.signalRuntime.publicPageUrl.length > 0 ? this.signalRuntime.publicPageUrl : '创建后显示'
      })
      TransferInfoRowView({ themeState: this.themeState, label: '地址下发', value: this.lastLanAccessSentText })

      Text(this.lanAccessStatusText)
        .fontSize(13)
        .lineHeight(21)
        .fontFamily(this.appFontFamily)
        .fontColor(this.color('text_primary'))
        .width('100%')
        .textAlign(TextAlign.Start)
        .padding(14)
        .backgroundColor(this.color('comp_background_tertiary'))
        .borderRadius(18)
        .clip(true)

      Text(this.signalRuntime.lastMessage)
        .fontSize(13)
        .lineHeight(21)
        .fontFamily(this.appFontFamily)
        .fontColor(this.color('text_primary'))
        .width('100%')
        .textAlign(TextAlign.Start)
        .padding(14)
        .backgroundColor(this.color('comp_background_tertiary'))
        .borderRadius(18)
        .clip(true)

      if (this.signalRuntime.lastError.length > 0) {
        Text(this.signalRuntime.lastError)
          .fontSize(13)
          .lineHeight(21)
          .fontFamily(this.appFontFamily)
          .fontColor(TRANSFER_DANGER_COLOR)
          .width('100%')
          .textAlign(TextAlign.Start)
          .padding(14)
          .backgroundColor(this.color('comp_background_tertiary'))
          .borderRadius(18)
          .clip(true)
      }

      Row({ space: 12 }) {
        this.buildTransferActionButton(
          this.signalRuntime.roomCode.length > 0 ? '重建房间' : '创建房间',
          $r('sys.symbol.play_fill'),
          ACTION_STYLE_PRIMARY,
          !this.signalBusy,
          true,
          'signal_create_room',
          () => {
            void this.handleCreateSignalRoom();
          }
        )

        this.buildTransferActionButton(
          '关闭房间',
          $r('sys.symbol.xmark'),
          ACTION_STYLE_DANGER,
          !this.signalBusy && this.signalRuntime.roomCode.length > 0 &&
            this.signalRuntime.status !== 'closed' && this.signalRuntime.status !== 'idle',
          true,
          'signal_close_room',
          () => {
            void this.handleCloseSignalRoom();
          }
        )
      }
      .width('100%')

      Row({ space: 12 }) {
        this.buildTransferActionButton(
          '刷新状态',
          $r('sys.symbol.arrow_clockwise'),
          ACTION_STYLE_NEUTRAL,
          !this.signalBusy && this.signalRuntime.roomCode.length > 0,
          true,
          'signal_refresh_room',
          () => {
            void this.handleRefreshSignalRoomStatus();
          }
        )

        this.buildTransferActionButton(
          '重连Host',
          $r('sys.symbol.link'),
          ACTION_STYLE_INFO,
          !this.signalBusy && this.signalRuntime.roomCode.length > 0 && this.signalRuntime.status !== 'connected',
          true,
          'signal_reconnect_host',
          () => {
            void this.handleReconnectSignalRoom();
          }
        )
      }
      .width('100%')

      Row({ space: 12 }) {
        this.buildTransferActionButton(
          '复制房间码',
          $r('sys.symbol.checkmark_circle_fill'),
          ACTION_STYLE_NEUTRAL,
          !this.signalBusy && this.signalRuntime.roomCode.length > 0,
          true,
          'signal_copy_room_code',
          () => {
            void this.handleCopySignalRoomCode();
          }
        )

        this.buildTransferActionButton(
          '复制网页链接',
          $r('sys.symbol.link'),
          ACTION_STYLE_INFO,
          !this.signalBusy && this.signalRuntime.publicPageUrl.length > 0,
          true,
          'signal_copy_public_link',
          () => {
            void this.handleCopySignalPublicLink();
          }
        )
      }
      .width('100%')

      Row({ space: 12 }) {
        this.buildTransferActionButton(
          '下发局域网地址',
          $r('sys.symbol.link'),
          ACTION_STYLE_PRIMARY,
          !this.signalBusy && !this.lanAccessBusy && this.isLanAccessReady(),
          true,
          'signal_send_lan_access',
          () => {
            void this.handleSendLanAccessNow();
          }
        )
      }
      .width('100%')

      Row({ space: 12 }) {
        this.buildTransferActionButton(
          '复制房间指引',
          $r('sys.symbol.doc_plaintext'),
          ACTION_STYLE_INFO,
          !this.signalBusy && this.signalRuntime.roomCode.length > 0,
          true,
          'signal_copy_guide',
          () => {
            void this.handleCopySignalGuide();
          }
        )

        this.buildTransferActionButton(
          '心跳测试',
          $r('sys.symbol.arrow_clockwise'),
          ACTION_STYLE_NEUTRAL,
          !this.signalBusy && this.signalRuntime.status === 'connected',
          true,
          'signal_ping',
          () => {
            void this.handleSignalPing();
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
      `transfer_signal_${this.signalRuntime.status}_${this.signalRuntime.roomCode}_` +
        `${this.signalRuntime.peerCount}_${this.signalBusy ? 'busy' : 'idle'}_${this.signalRuntime.updatedAt}_` +
        `${this.lastLanAccessSentText}_${this.lanAccessStatusText}_${this.lanAccessBusy ? 'lan_busy' : 'lan_idle'}`
    )
  }

  @Builder
  private buildNativeRtcCard() {
    Column({ space: 14 }) {
      TransferCardHeaderView({
        themeState: this.themeState,
        title: 'Native RTC 数据通道',
        subtitle: '信令继续复用 Worker 房间；Native 侧只负责后续 DataChannel 数据面。'
      })

      TransferInfoRowView({ themeState: this.themeState, label: '运行状态', value: this.getNativeRtcStatusText() })
      TransferInfoRowView({ themeState: this.themeState, label: '后端', value: this.getNativeRtcBackendText() })
      TransferInfoRowView({ themeState: this.themeState, label: 'DataChannel', value: this.getNativeRtcSupportText() })
      TransferInfoRowView({ themeState: this.themeState, label: 'Peer', value: this.getNativeRtcPeerText() })
      TransferInfoRowView({ themeState: this.themeState, label: '文件接收', value: this.getRtcFileReceiverStatusText() })
      TransferInfoRowView({ themeState: this.themeState, label: '接收进度', value: this.getRtcFileReceiverProgressText() })

      Text(this.nativeRtcRuntime.lastMessage)
        .fontSize(13)
        .lineHeight(21)
        .fontFamily(this.appFontFamily)
        .fontColor(this.color('text_primary'))
        .width('100%')
        .textAlign(TextAlign.Start)
        .padding(14)
        .backgroundColor(this.color('comp_background_tertiary'))
        .borderRadius(18)
        .clip(true)

      if (this.nativeRtcRuntime.lastError.length > 0) {
        Text(this.nativeRtcRuntime.lastError)
          .fontSize(13)
          .lineHeight(21)
          .fontFamily(this.appFontFamily)
          .fontColor(TRANSFER_DANGER_COLOR)
          .width('100%')
          .textAlign(TextAlign.Start)
          .padding(14)
          .backgroundColor(this.color('comp_background_tertiary'))
          .borderRadius(18)
          .clip(true)
      }

      Text(this.rtcFileReceiverRuntime.lastMessage)
        .fontSize(13)
        .lineHeight(21)
        .fontFamily(this.appFontFamily)
        .fontColor(this.color('text_primary'))
        .width('100%')
        .textAlign(TextAlign.Start)
        .padding(14)
        .backgroundColor(this.color('comp_background_tertiary'))
        .borderRadius(18)
        .clip(true)

      if (this.rtcFileReceiverRuntime.lastError.length > 0) {
        Text(this.rtcFileReceiverRuntime.lastError)
          .fontSize(13)
          .lineHeight(21)
          .fontFamily(this.appFontFamily)
          .fontColor(TRANSFER_DANGER_COLOR)
          .width('100%')
          .textAlign(TextAlign.Start)
          .padding(14)
          .backgroundColor(this.color('comp_background_tertiary'))
          .borderRadius(18)
          .clip(true)
      }

      Row({ space: 12 }) {
        this.buildTransferActionButton(
          '检测能力',
          $r('sys.symbol.checkmark_circle_fill'),
          ACTION_STYLE_NEUTRAL,
          !this.nativeRtcBusy,
          true,
          'native_rtc_probe',
          () => {
            this.handleProbeNativeRtcCapabilities();
          }
        )

        this.buildTransferActionButton(
          '创建Host Peer',
          $r('sys.symbol.link'),
          ACTION_STYLE_INFO,
          !this.nativeRtcBusy,
          true,
          'native_rtc_create_host_peer',
          () => {
            this.handleCreateNativeRtcHostPeer();
          }
        )
      }
      .width('100%')

      Row({ space: 12 }) {
        this.buildTransferActionButton(
          '关闭Peer',
          $r('sys.symbol.xmark'),
          ACTION_STYLE_DANGER,
          !this.nativeRtcBusy && this.nativeRtcRuntime.peerId.length > 0,
          true,
          'native_rtc_close_peer',
          () => {
            void this.handleCloseNativeRtcPeer();
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
      `transfer_native_rtc_${this.nativeRtcRuntime.status}_${this.nativeRtcRuntime.peerId}_` +
        `${this.nativeRtcRuntime.capabilities.backend}_${this.nativeRtcBusy ? 'busy' : 'idle'}_` +
        `${this.nativeRtcRuntime.updatedAt}_${this.rtcFileReceiverRuntime.status}_` +
        `${this.rtcFileReceiverRuntime.receivedBytes}_${this.rtcFileReceiverRuntime.updatedAt}`
    )
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
        this.buildTransferTabButton(2, '公网')
        this.buildTransferTabButton(3, '说明')
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
      } else if (this.activeTabIndex === 2) {
        this.buildSignalTabContent()
      } else {
        this.buildGuideTabContent()
      }
    }
    .width('100%')
    .key(
      `transfer_tabs_${this.viewState.recentUploads.length}_${this.selectedUploadRecordIds.length}_` +
        `${this.viewState.uploadProgress.status}_${this.signalRuntime.status}_${this.signalRuntime.roomCode}`
    )
  }

  @Builder
  private buildTransferTabButton(index: number, label: string) {
    Text(label)
      .fontSize(14)
      .fontWeight(this.activeTabIndex === index ? FontWeight.Bold : FontWeight.Medium)
      .fontFamily(this.appFontFamily)
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
          .fontFamily(this.appFontFamily)
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
        .fontFamily(this.appFontFamily)
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
        .fontFamily(this.appFontFamily)
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
              .fontFamily(this.appFontFamily)
              .fontColor(this.color('text_primary'))

            Text('启动后这里会生成当前主地址对应的二维码。')
              .fontSize(13)
              .lineHeight(20)
              .fontFamily(this.appFontFamily)
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
          .fontFamily(this.appFontFamily)
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
      TransferInfoRowView({
        themeState: this.themeState,
        label: '收件箱总量上限',
        value: `${this.viewState.config.maxTotalSizeMb} MB`
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
        `${this.viewState.config.maxTotalSizeMb}_${this.viewState.config.allowBackgroundTransfer ? 'bg1' : 'bg0'}_` +
        `${this.viewState.config.wsEnabled ? 'ws1' : 'ws0'}`
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
            .fontFamily(this.appFontFamily)
            .fontColor(this.color('text_primary'))
            .width('100%')
            .textAlign(TextAlign.Start)
            .maxLines(2)
            .textOverflow({ overflow: TextOverflow.Ellipsis })

          Text(this.isUploadRecordSelected(record.id) ? '已选中' : this.getUploadStatusText(record))
            .fontSize(12)
            .fontFamily(this.appFontFamily)
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
    .transition(TransitionEffect.asymmetric(
      TransitionEffect.OPACITY.animation({ duration: 220, curve: Curve.EaseOut }).combine(
        TransitionEffect.translate({ y: 10 }).animation({ duration: 220, curve: Curve.EaseOut })
      ),
      TransitionEffect.OPACITY.animation({ duration: 160, curve: Curve.EaseIn }).combine(
        TransitionEffect.translate({ y: -6 }).animation({ duration: 160, curve: Curve.EaseIn })
      )
    ))
    .animation({ duration: 200, curve: Curve.EaseInOut })
    .key(`transfer_upload_record_${record.id}_${this.isUploadRecordSelected(record.id) ? 'selected' : 'idle'}_${record.status}`)
  }

  @Builder
  private buildInboxSelectionToolbar() {
    Column({ space: 10 }) {
      Row({ space: 10 }) {
        Text(`已选 ${this.getSelectedUploadRecordCount()} / ${this.getSelectableUploadRecordCount()} 个`)
          .fontSize(13)
          .fontFamily(this.appFontFamily)
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
          .fontFamily(this.appFontFamily)
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
    .transition(TransitionEffect.OPACITY.animation({ duration: 180, curve: Curve.EaseOut }).combine(
      TransitionEffect.translate({ y: 6 }).animation({ duration: 180, curve: Curve.EaseOut })
    ))
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
        .transition(TransitionEffect.asymmetric(
          TransitionEffect.OPACITY.animation({ duration: 220, curve: Curve.EaseOut }).combine(
            TransitionEffect.scale({ x: 0.98, y: 0.98 }).animation({ duration: 220, curve: Curve.EaseOut })
          ),
          TransitionEffect.OPACITY.animation({ duration: 150, curve: Curve.EaseIn })
        ))
      } else {
        Column({ space: 12 }) {
          this.buildInboxSelectionToolbar()

          ForEach(this.viewState.recentUploads, (record: TransferUploadRecord) => {
            this.buildUploadRecord(record)
          }, (record: TransferUploadRecord) => record.id)
        }
        .width('100%')
        .transition(TransitionEffect.asymmetric(
          TransitionEffect.OPACITY.animation({ duration: 220, curve: Curve.EaseOut }).combine(
            TransitionEffect.translate({ y: 8 }).animation({ duration: 220, curve: Curve.EaseOut })
          ),
          TransitionEffect.OPACITY.animation({ duration: 150, curve: Curve.EaseIn }).combine(
            TransitionEffect.translate({ y: -6 }).animation({ duration: 150, curve: Curve.EaseIn })
          )
        ))
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
      `transfer_uploads_${this.viewState.recentUploads.length}_` +
        `${this.selectedUploadRecordIds.length}`
    )
  }

  @Builder
  private buildRefreshView() {
    Scroll() {
      Column({ space: 16 }) {
        Text(
          `${this.viewState.renderVersion}_${this.viewState.status}_${this.viewState.pairCode}_` +
            `${this.signalRuntime.status}_${this.signalRuntime.roomCode}`
        )
          .fontSize(1)
          .fontFamily(this.appFontFamily)
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
          `${this.viewState.pairCode}_${this.viewState.localAddresses.length}_${this.viewState.recentUploads.length}_` +
          `${this.signalRuntime.status}_${this.signalRuntime.roomCode}`
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
        .fontFamily(this.appFontFamily)
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
        .fontFamily(this.appFontFamily)
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
      Text(
      `transfer_state_${this.viewState.renderVersion}_${this.viewState.status}_${this.viewState.pairCode}_` +
          `${this.viewState.uploadProgress.status}_${this.viewState.uploadProgress.progressPercent}_` +
          `${this.viewState.uploadProgress.updatedAt}_` +
          `${this.signalRuntime.status}_${this.signalRuntime.roomCode}`
      )
        .fontSize(1)
        .fontFamily(this.appFontFamily)
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
        `${this.viewState.pairCode}_${this.viewState.localAddresses.length}_${this.viewState.recentUploads.length}_` +
        `${this.signalRuntime.status}_${this.signalRuntime.roomCode}`
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
