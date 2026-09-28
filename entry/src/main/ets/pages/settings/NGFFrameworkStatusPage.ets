import { HdsNavDestination } from '@kit.UIDesignKit';
import { promptAction } from '@kit.ArkUI';
import { ThemeAwareHelper, ThemeAwareState } from 'manxia_theme/src/main/ets/Framework/Components/ThemeAware';
import { FontAwareHelper, FontAwareState } from 'manxia_theme/src/main/ets/Framework/Components/FontAware';
import { ThemeType } from 'manxia_theme/src/main/ets/Framework/Managers/ThemeManager';
import { logger } from 'manxia_core/src/main/ets/Utils/Logger';
import { SharedPageBackgroundLayer } from 'manxia_theme/src/main/ets/Framework/Components/SharedPageBackgroundLayer';
import { GlobalBackgroundLayerMode } from 'manxia_theme/src/main/ets/Framework/Components/GlobalBackgroundLayer';
import { SettingsImmersiveTitleBar } from './SettingsImmersiveTitleBar';
import { SettingsPageTitleBarManager } from 'manxia_features_ui/src/main/ets/pages/settings/SettingsPageTitleBarManager';
import { SettingsPanelSurfaceHelper } from 'manxia_features_ui/src/main/ets/pages/settings/SettingsPanelSurfaceHelper';
import { getAppInitializationManager, InitPhase, InitializationState } from 'manxia_core/src/main/ets/Framework/Managers/AppInitializationManager';
import {
  NGFDisplayMode,
  NGFEventPayload,
  NGFInitializationEventName,
  ngfContentSourceIntegrationFacade,
  ngfContentWorkflowIntegrationFacade,
  ngfCoreIntegrationFacade,
  ngfDataIntegrationFacade,
  ngfErrorHandlerFacade,
  ngfEventBusFacade,
  ngfLifecycleOrchestratorFacade
} from '../../Framework/NGF';
import { DependencyContainer } from '../../Framework/DependencyContainer';

const TAG = 'NGFFrameworkStatusPage';
const NGF_RUNTIME_PROBE_EVENT_NAME = 'ngf.framework.status.probe';

class NGFModuleStatusCard {
  moduleId: string;
  layer: string;
  rootPath: string;
  contractStatus: string;
  runtimeStatus: string;
  detectionChannel: string;
  isHealthy: boolean;

  constructor(
    moduleId: string,
    layer: string,
    rootPath: string,
    contractStatus: string,
    runtimeStatus: string,
    detectionChannel: string,
    isHealthy: boolean
  ) {
    this.moduleId = moduleId;
    this.layer = layer;
    this.rootPath = rootPath;
    this.contractStatus = contractStatus;
    this.runtimeStatus = runtimeStatus;
    this.detectionChannel = detectionChannel;
    this.isHealthy = isHealthy;
  }
}

@Component
export struct NGFFrameworkStatusPage {
  @StorageProp('statusBarHeight') statusBarHeight: number = 0;
  @State themeState: ThemeAwareState = new ThemeAwareState();
  @State fontState: FontAwareState = new FontAwareState();
  @StorageLink('appFontFamily') appFontFamily: string = 'HarmonyOS Sans';
  @State pathStack: NavPathStack = new NavPathStack();

  @State private moduleCards: Array<NGFModuleStatusCard> = [];
  @State private currentInitPhase: string = InitPhase.NOT_STARTED;
  @State private currentInitText: string = '未开始';
  @State private currentInitProgress: number = 0;
  @State private initCompleted: boolean = false;
  @State private initFailed: boolean = false;
  @State private initFailedMessage: string = '';
  @State private completedPhaseCount: number = 0;

  @State private ngfCoreIntegrated: boolean = false;
  @State private ngfCoreIntegratedAt: number = 0;
  @State private coreServiceRegisteredCount: number = 0;
  @State private ngfPlatformIntegrated: boolean = false;
  @State private ngfPlatformIntegratedAt: number = 0;
  @State private platformServiceRegisteredCount: number = 0;
  @State private ngfUiShellIntegrated: boolean = false;
  @State private ngfUiShellIntegratedAt: number = 0;
  @State private uiShellServiceRegisteredCount: number = 0;
  @State private ngfDataIntegrated: boolean = false;
  @State private ngfDataIntegratedAt: number = 0;
  @State private dataServiceRegisteredCount: number = 0;
  @State private ngfContentWorkflowIntegrated: boolean = false;
  @State private ngfContentWorkflowIntegratedAt: number = 0;
  @State private contentWorkflowServiceRegisteredCount: number = 0;
  @State private ngfContentSourceIntegrated: boolean = false;
  @State private ngfContentSourceIntegratedAt: number = 0;
  @State private contentSourceServiceRegisteredCount: number = 0;
  @State private recentErrorCount: number = 0;

  @State private eventProbeCount: number = 0;
  @State private eventProbeLastAt: number = 0;
  @State private eventProbeLastPayload: string = '';
  @State private eventProbeHealthy: boolean = false;

  @State private lastInitEventName: string = '';
  @State private lastInitEventPayload: string = '';
  @State private lastInitEventAt: number = 0;

  private readonly componentId: string = 'NGFFrameworkStatusPage';
  private readonly ngfInitListenerId: string = 'NGFFrameworkStatusPage_InitBridge';
  private readonly ngfProbeListenerId: string = 'NGFFrameworkStatusPage_Probe';
  private ngfInitListenerAttached: boolean = false;
  private ngfProbeListenerAttached: boolean = false;

  private readonly coreRuntimeTokens: Array<string> = [
    'ngf.core.logger',
    'ngf.core.event_bus',
    'ngf.core.error_handler',
    'ngf.core.lifecycle',
    'ngf.core.service_container'
  ];
  private readonly platformRuntimeTokens: Array<string> = [
    'ngf.platform.window_controller',
    'ngf.platform.page_policy_resolver',
    'ngf.platform.context_bridge'
  ];
  private readonly uiShellRuntimeTokens: Array<string> = [
    'ngf.ui.navigation_shell',
    'ngf.ui.page_policy_host'
  ];
  private readonly dataRuntimeTokens: Array<string> = [
    'ngf.data.data_facade',
    'ngf.data.settings_store',
    'ngf.data.cache_store',
    'ngf.data.storage_provider',
    'ngf.data.db_migrator'
  ];
  private readonly contentWorkflowRuntimeTokens: Array<string> = [
    'ngf.workflow.engine',
    'ngf.workflow.action_executor',
    'ngf.workflow.retry_policy',
    'ngf.workflow.rate_limit_policy'
  ];
  private readonly contentSourceRuntimeTokens: Array<string> = [
    'ngf.source.repository',
    'ngf.source.loader',
    'ngf.source.registry'
  ];

  aboutToAppear(): void {
    ThemeAwareHelper.initializeThemeAware(this.componentId, this.themeState, (_newTheme: ThemeType) => {});
    FontAwareHelper.initializeFontAware(this.componentId, this.fontState, (newState: FontAwareState) => {
      this.fontState = newState;
    });
    this.attachNGFListeners();
    this.refreshRuntimeSnapshot(false);
  }

  aboutToDisappear(): void {
    this.detachNGFListeners();
    ThemeAwareHelper.cleanupThemeAware(this.componentId);
    FontAwareHelper.cleanupFontAware(this.componentId);
  }

  private attachNGFListeners(): void {
    if (!this.ngfInitListenerAttached) {
      const stateSubscribed = ngfEventBusFacade.subscribe(
        NGFInitializationEventName.INIT_STATE_CHANGED,
        this.ngfInitListenerId,
        (payload: NGFEventPayload): void => {
          this.recordInitEvent(NGFInitializationEventName.INIT_STATE_CHANGED, payload);
        }
      );
      const failedSubscribed = ngfEventBusFacade.subscribe(
        NGFInitializationEventName.INIT_FAILED,
        this.ngfInitListenerId,
        (payload: NGFEventPayload): void => {
          this.recordInitEvent(NGFInitializationEventName.INIT_FAILED, payload);
        }
      );
      const completedSubscribed = ngfEventBusFacade.subscribe(
        NGFInitializationEventName.INIT_COMPLETED,
        this.ngfInitListenerId,
        (payload: NGFEventPayload): void => {
          this.recordInitEvent(NGFInitializationEventName.INIT_COMPLETED, payload);
        }
      );
      this.ngfInitListenerAttached = stateSubscribed || failedSubscribed || completedSubscribed;
    }

    if (!this.ngfProbeListenerAttached) {
      this.ngfProbeListenerAttached = ngfEventBusFacade.subscribe(
        NGF_RUNTIME_PROBE_EVENT_NAME,
        this.ngfProbeListenerId,
        (payload: NGFEventPayload): void => {
          this.eventProbeCount = this.eventProbeCount + 1;
          this.eventProbeLastAt = payload.createdAt;
          this.eventProbeLastPayload = payload.payloadJson;
          this.eventProbeHealthy = true;
        }
      );
    }
  }

  private detachNGFListeners(): void {
    if (this.ngfInitListenerAttached) {
      ngfEventBusFacade.unsubscribe(NGFInitializationEventName.INIT_STATE_CHANGED, this.ngfInitListenerId);
      ngfEventBusFacade.unsubscribe(NGFInitializationEventName.INIT_FAILED, this.ngfInitListenerId);
      ngfEventBusFacade.unsubscribe(NGFInitializationEventName.INIT_COMPLETED, this.ngfInitListenerId);
      this.ngfInitListenerAttached = false;
    }

    if (this.ngfProbeListenerAttached) {
      ngfEventBusFacade.unsubscribe(NGF_RUNTIME_PROBE_EVENT_NAME, this.ngfProbeListenerId);
      this.ngfProbeListenerAttached = false;
    }
  }

  private recordInitEvent(eventName: string, payload: NGFEventPayload): void {
    this.lastInitEventName = eventName;
    this.lastInitEventPayload = payload.payloadJson;
    this.lastInitEventAt = payload.createdAt;
    this.refreshRuntimeSnapshot(false);
  }

  private refreshRuntimeSnapshot(showToast: boolean): void {
    this.updateInitRuntimeState(getAppInitializationManager().getState());
    this.ngfCoreIntegrated = this.readCoreIntegratedState();
    this.ngfCoreIntegratedAt = this.readIntegratedTimestamp();
    this.coreServiceRegisteredCount = this.countRegisteredCoreServices();
    this.ngfPlatformIntegrated = this.readPlatformIntegratedState();
    this.ngfPlatformIntegratedAt = this.readPlatformIntegratedTimestamp();
    this.platformServiceRegisteredCount = this.countRegisteredTokens(this.platformRuntimeTokens);
    this.ngfUiShellIntegrated = this.readUiShellIntegratedState();
    this.ngfUiShellIntegratedAt = this.readUiShellIntegratedTimestamp();
    this.uiShellServiceRegisteredCount = this.countRegisteredTokens(this.uiShellRuntimeTokens);
    this.ngfDataIntegrated = this.readDataIntegratedState();
    this.ngfDataIntegratedAt = this.readDataIntegratedTimestamp();
    this.dataServiceRegisteredCount = this.countRegisteredTokens(this.dataRuntimeTokens);
    this.ngfContentWorkflowIntegrated = this.readContentWorkflowIntegratedState();
    this.ngfContentWorkflowIntegratedAt = this.readContentWorkflowIntegratedTimestamp();
    this.contentWorkflowServiceRegisteredCount = this.countRegisteredTokens(this.contentWorkflowRuntimeTokens);
    this.ngfContentSourceIntegrated = this.readContentSourceIntegratedState();
    this.ngfContentSourceIntegratedAt = this.readContentSourceIntegratedTimestamp();
    this.contentSourceServiceRegisteredCount = this.countRegisteredTokens(this.contentSourceRuntimeTokens);
    this.recentErrorCount = ngfErrorHandlerFacade.getRecentErrorCount();
    this.moduleCards = this.buildModuleCards();

    if (showToast) {
      this.getUIContext().getPromptAction().showToast({
        message: 'NGF状态已刷新',
        duration: 1300
      });
    }
  }

  private updateInitRuntimeState(state: InitializationState): void {
    this.currentInitPhase = state.currentPhase;
    this.currentInitText = state.displayText;
    this.currentInitProgress = state.progress;
    this.initCompleted = state.isCompleted;
    this.initFailed = state.isFailed;
    this.completedPhaseCount = state.completedPhases.length;
    this.initFailedMessage = state.errorMessage ? state.errorMessage : '';
  }

  private readCoreIntegratedState(): boolean {
    const appStorageFlag = AppStorage.get<boolean>('ngf_core_integrated');
    if (appStorageFlag === true) {
      return true;
    }
    return ngfCoreIntegrationFacade.isBootstrapped();
  }

  private readIntegratedTimestamp(): number {
    const integratedAt = AppStorage.get<number>('ngf_core_integrated_at');
    if (integratedAt) {
      return integratedAt;
    }
    return 0;
  }

  private countRegisteredCoreServices(): number {
    return this.countRegisteredTokens(this.coreRuntimeTokens);
  }

  private countRegisteredTokens(tokens: Array<string>): number {
    const container = DependencyContainer.getInstance();
    let count = 0;
    for (let index = 0; index < tokens.length; index++) {
      if (container.isRegistered(tokens[index])) {
        count = count + 1;
      }
    }
    return count;
  }

  private readPlatformIntegratedState(): boolean {
    const appStorageFlag = AppStorage.get<boolean>('ngf_platform_integrated');
    return appStorageFlag === true;
  }

  private readPlatformIntegratedTimestamp(): number {
    const integratedAt = AppStorage.get<number>('ngf_platform_integrated_at');
    if (integratedAt) {
      return integratedAt;
    }
    return 0;
  }

  private readUiShellIntegratedState(): boolean {
    const appStorageFlag = AppStorage.get<boolean>('ngf_ui_shell_integrated');
    return appStorageFlag === true;
  }

  private readUiShellIntegratedTimestamp(): number {
    const integratedAt = AppStorage.get<number>('ngf_ui_shell_integrated_at');
    if (integratedAt) {
      return integratedAt;
    }
    return 0;
  }

  private readDataIntegratedState(): boolean {
    const appStorageFlag = AppStorage.get<boolean>('ngf_data_integrated');
    if (appStorageFlag === true) {
      return true;
    }
    return ngfDataIntegrationFacade.isBootstrapped();
  }

  private readDataIntegratedTimestamp(): number {
    const integratedAt = AppStorage.get<number>('ngf_data_integrated_at');
    if (integratedAt) {
      return integratedAt;
    }
    return 0;
  }

  private readContentWorkflowIntegratedState(): boolean {
    const appStorageFlag = AppStorage.get<boolean>('ngf_content_workflow_integrated');
    if (appStorageFlag === true) {
      return true;
    }
    return ngfContentWorkflowIntegrationFacade.isBootstrapped();
  }

  private readContentWorkflowIntegratedTimestamp(): number {
    const integratedAt = AppStorage.get<number>('ngf_content_workflow_integrated_at');
    if (integratedAt) {
      return integratedAt;
    }
    return 0;
  }

  private readContentSourceIntegratedState(): boolean {
    const appStorageFlag = AppStorage.get<boolean>('ngf_content_source_integrated');
    if (appStorageFlag === true) {
      return true;
    }
    return ngfContentSourceIntegrationFacade.isBootstrapped();
  }

  private readContentSourceIntegratedTimestamp(): number {
    const integratedAt = AppStorage.get<number>('ngf_content_source_integrated_at');
    if (integratedAt) {
      return integratedAt;
    }
    return 0;
  }

  private buildModuleCards(): Array<NGFModuleStatusCard> {
    const cards: Array<NGFModuleStatusCard> = [];

    const currentState = ngfLifecycleOrchestratorFacade.getCurrentState();
    const coreRuntimeHealthy = this.ngfCoreIntegrated && this.coreServiceRegisteredCount >= 4 && currentState.progress > 0;
    cards.push(
      new NGFModuleStatusCard(
        'ngf-core',
        'core',
        'entry/src/main/ets/Framework/NGF/core',
        'contracts + facades + runtime bridge 已接入',
        coreRuntimeHealthy ? '运行中（核心桥接与生命周期可用）' : '已接入但运行态未完全就绪',
        'DependencyContainer + AppStorage + LifecycleFacade',
        coreRuntimeHealthy
      )
    );

    const platformAnchor = NGFDisplayMode.STATUS_SAFE_BOTTOM_IMMERSIVE.length > 0
      && this.ngfPlatformIntegrated
      && this.platformServiceRegisteredCount >= 2;
    cards.push(
      new NGFModuleStatusCard(
        'ngf-platform-ohos',
        'platform',
        'entry/src/main/ets/Framework/NGF/platformOhos',
        '平台契约 + façade 已导出（window/context/policy）',
        platformAnchor
          ? `运行中（${this.platformServiceRegisteredCount}/${this.platformRuntimeTokens.length} 服务已注册）`
          : '已接入但运行态未完全就绪',
        `AppStorage + DependencyContainer（接入时间：${this.formatTime(this.ngfPlatformIntegratedAt)}）`,
        platformAnchor
      )
    );

    const dataRuntimeHealthy = this.ngfDataIntegrated && this.dataServiceRegisteredCount >= this.dataRuntimeTokens.length;
    cards.push(
      new NGFModuleStatusCard(
        'ngf-data',
        'data',
        'entry/src/main/ets/Framework/NGF/data',
        '数据契约 + façade 已导出（data/settings/cache/storage/migrator）',
        dataRuntimeHealthy
          ? `运行中（${this.dataServiceRegisteredCount}/${this.dataRuntimeTokens.length} 服务已注册）`
          : '已接入但运行态未完全就绪',
        `AppStorage + DependencyContainer（接入时间：${this.formatTime(this.ngfDataIntegratedAt)}）`,
        dataRuntimeHealthy
      )
    );

    const workflowRuntimeHealthy = this.ngfContentWorkflowIntegrated
      && this.contentWorkflowServiceRegisteredCount >= this.contentWorkflowRuntimeTokens.length;
    cards.push(
      new NGFModuleStatusCard(
        'ngf-content-workflow',
        'content',
        'entry/src/main/ets/Framework/NGF/contentWorkflow',
        '工作流契约 + façade 已导出（engine/action/retry/rateLimit）',
        workflowRuntimeHealthy
          ? `运行中（${this.contentWorkflowServiceRegisteredCount}/${this.contentWorkflowRuntimeTokens.length} 服务已注册）`
          : '已接入但运行态未完全就绪',
        `AppStorage + DependencyContainer（接入时间：${this.formatTime(this.ngfContentWorkflowIntegratedAt)}）`,
        workflowRuntimeHealthy
      )
    );

    const contentSourceRuntimeHealthy = this.ngfContentSourceIntegrated
      && this.contentSourceServiceRegisteredCount >= this.contentSourceRuntimeTokens.length;
    cards.push(
      new NGFModuleStatusCard(
        'ngf-content-source',
        'content',
        'entry/src/main/ets/Framework/NGF/contentSource',
        '图源契约 + façade 已导出（repository/loader/registry）',
        contentSourceRuntimeHealthy
          ? `运行中（${this.contentSourceServiceRegisteredCount}/${this.contentSourceRuntimeTokens.length} 服务已注册）`
          : '已接入但运行态未完全就绪',
        `AppStorage + DependencyContainer（接入时间：${this.formatTime(this.ngfContentSourceIntegratedAt)}）`,
        contentSourceRuntimeHealthy
      )
    );

    cards.push(
      new NGFModuleStatusCard(
        'ngf-ui-shell',
        'ui',
        'entry/src/main/ets/Framework/NGF/uiShell',
        'UI 壳层契约 + façade 已导出（navigation/pagePolicy）',
        this.ngfUiShellIntegrated
          ? `运行中（${this.uiShellServiceRegisteredCount}/${this.uiShellRuntimeTokens.length} 服务已注册）`
          : '已接入但运行态未完全就绪',
        `AppStorage + DependencyContainer（接入时间：${this.formatTime(this.ngfUiShellIntegratedAt)}）`,
        this.ngfUiShellIntegrated && this.uiShellServiceRegisteredCount >= 2
      )
    );

    return cards;
  }

  private triggerEventProbe(): void {
    const now = Date.now();
    this.eventProbeHealthy = false;
    const probePayload = new NGFEventPayload(
      'ngf_runtime_probe',
      `{"source":"NGFFrameworkStatusPage","timestamp":${now}}`,
      now
    );
    ngfEventBusFacade.publish(NGF_RUNTIME_PROBE_EVENT_NAME, probePayload);

    setTimeout(() => {
      if (!this.eventProbeHealthy) {
        logger.warn(TAG, 'NGF事件总线探针未在预期时间内收到回调');
      }
    }, 200);
  }

  private formatTime(timestamp: number): string {
    if (timestamp <= 0) {
      return '未记录';
    }
    const date = new Date(timestamp);
    const year = date.getFullYear();
    const month = `${date.getMonth() + 1}`.padStart(2, '0');
    const day = `${date.getDate()}`.padStart(2, '0');
    const hour = `${date.getHours()}`.padStart(2, '0');
    const minute = `${date.getMinutes()}`.padStart(2, '0');
    const second = `${date.getSeconds()}`.padStart(2, '0');
    return `${year}-${month}-${day} ${hour}:${minute}:${second}`;
  }

  private statusColor(isHealthy: boolean): ResourceColor {
    return isHealthy
      ? ThemeAwareHelper.getTestManagementThemedColor('accent_primary', this.themeState.currentTheme)
      : ThemeAwareHelper.getTestManagementThemedColor('color_warning', this.themeState.currentTheme);
  }

  @Builder
  buildStatusChip(label: string, value: string, healthy: boolean): void {
    Column({ space: 4 }) {
      Text(label)
        .fontSize(11)
        .fontFamily(this.appFontFamily)
        .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_secondary', this.themeState.currentTheme))
        .maxLines(1)

      Text(value)
        .fontSize(13)
        .fontWeight(FontWeight.Medium)
        .fontFamily(this.appFontFamily)
        .fontColor(this.statusColor(healthy))
        .maxLines(1)
    }
    .alignItems(HorizontalAlign.Start)
    .padding({ left: 12, right: 12, top: 10, bottom: 10 })
    .backgroundColor(SettingsPanelSurfaceHelper.getBackground(this.themeState.currentTheme))
    .linearGradient(SettingsPanelSurfaceHelper.getSurfaceGradient(this.themeState.currentTheme))
    .backgroundBlurStyle(SettingsPanelSurfaceHelper.getBlurStyle(this.themeState.currentTheme), SettingsPanelSurfaceHelper.getBlurOptions(this.themeState.currentTheme))
    .backgroundEffect(SettingsPanelSurfaceHelper.getBackgroundEffect(this.themeState.currentTheme))
    .borderRadius(12)
    .clip(true)
    .border({
      width: 1,
      color: SettingsPanelSurfaceHelper.getBorderColor(this.themeState.currentTheme)
    })
    .margin({ right: 8, bottom: 8 })
  }

  @Builder
  buildInfoRow(label: string, value: string, emphasize: boolean = false): void {
    Row() {
      Text(label)
        .fontSize(13)
        .fontFamily(this.appFontFamily)
        .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_secondary', this.themeState.currentTheme))
        .layoutWeight(1)

      Text(value)
        .fontSize(13)
        .fontFamily(this.appFontFamily)
        .fontWeight(emphasize ? FontWeight.Medium : FontWeight.Regular)
        .fontColor(
          emphasize
            ? ThemeAwareHelper.getTestManagementThemedColor('accent_primary', this.themeState.currentTheme)
            : ThemeAwareHelper.getTestManagementThemedColor('text_primary', this.themeState.currentTheme)
        )
        .textAlign(TextAlign.End)
    }
    .width('100%')
  }

  @Builder
  buildOverviewCard(): void {
    Column({ space: 12 }) {
      Text('NGF 框架总览')
        .fontSize(20)
        .fontWeight(FontWeight.Bold)
        .fontFamily(this.appFontFamily)
        .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_primary', this.themeState.currentTheme))
        .alignSelf(ItemAlign.Start)

      Text('该页面用于统一观测 NGF 六大模块的可检测状态、核心运行时桥接状态和初始化过程健康度。')
        .fontSize(13)
        .fontFamily(this.appFontFamily)
        .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_secondary', this.themeState.currentTheme))
        .alignSelf(ItemAlign.Start)

      Flex({ wrap: FlexWrap.Wrap, justifyContent: FlexAlign.Start }) {
        this.buildStatusChip('模块数量', `${this.moduleCards.length}`, true);
        this.buildStatusChip('核心服务注册', `${this.coreServiceRegisteredCount}/${this.coreRuntimeTokens.length}`, this.coreServiceRegisteredCount > 0);
        this.buildStatusChip('平台服务注册', `${this.platformServiceRegisteredCount}/${this.platformRuntimeTokens.length}`, this.platformServiceRegisteredCount > 0);
        this.buildStatusChip('UI壳层服务注册', `${this.uiShellServiceRegisteredCount}/${this.uiShellRuntimeTokens.length}`, this.uiShellServiceRegisteredCount > 0);
        this.buildStatusChip('数据服务注册', `${this.dataServiceRegisteredCount}/${this.dataRuntimeTokens.length}`, this.dataServiceRegisteredCount > 0);
        this.buildStatusChip(
          '工作流服务注册',
          `${this.contentWorkflowServiceRegisteredCount}/${this.contentWorkflowRuntimeTokens.length}`,
          this.contentWorkflowServiceRegisteredCount > 0
        );
        this.buildStatusChip(
          '图源服务注册',
          `${this.contentSourceServiceRegisteredCount}/${this.contentSourceRuntimeTokens.length}`,
          this.contentSourceServiceRegisteredCount > 0
        );
        this.buildStatusChip('初始化进度', `${this.currentInitProgress}%`, this.currentInitProgress > 0);
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
  buildRuntimeCard(): void {
    Column({ space: 10 }) {
      Text('核心运行时状态')
        .fontSize(18)
        .fontWeight(FontWeight.Bold)
        .fontFamily(this.appFontFamily)
        .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_primary', this.themeState.currentTheme))
        .alignSelf(ItemAlign.Start)

      this.buildInfoRow('核心桥接', this.ngfCoreIntegrated ? '已激活' : '未激活', this.ngfCoreIntegrated);
      this.buildInfoRow('平台桥接', this.ngfPlatformIntegrated ? '已激活' : '未激活', this.ngfPlatformIntegrated);
      this.buildInfoRow('UI壳层桥接', this.ngfUiShellIntegrated ? '已激活' : '未激活', this.ngfUiShellIntegrated);
      this.buildInfoRow('数据桥接', this.ngfDataIntegrated ? '已激活' : '未激活', this.ngfDataIntegrated);
      this.buildInfoRow(
        '工作流桥接',
        this.ngfContentWorkflowIntegrated ? '已激活' : '未激活',
        this.ngfContentWorkflowIntegrated
      );
      this.buildInfoRow(
        '图源桥接',
        this.ngfContentSourceIntegrated ? '已激活' : '未激活',
        this.ngfContentSourceIntegrated
      );
      this.buildInfoRow('最近接入时间', this.formatTime(this.ngfCoreIntegratedAt));
      this.buildInfoRow('平台接入时间', this.formatTime(this.ngfPlatformIntegratedAt));
      this.buildInfoRow('UI壳层接入时间', this.formatTime(this.ngfUiShellIntegratedAt));
      this.buildInfoRow('数据接入时间', this.formatTime(this.ngfDataIntegratedAt));
      this.buildInfoRow('数据服务注册', `${this.dataServiceRegisteredCount}/${this.dataRuntimeTokens.length}`, this.dataServiceRegisteredCount > 0);
      this.buildInfoRow(
        '工作流接入时间',
        this.formatTime(this.ngfContentWorkflowIntegratedAt)
      );
      this.buildInfoRow(
        '工作流服务注册',
        `${this.contentWorkflowServiceRegisteredCount}/${this.contentWorkflowRuntimeTokens.length}`,
        this.contentWorkflowServiceRegisteredCount > 0
      );
      this.buildInfoRow(
        '图源接入时间',
        this.formatTime(this.ngfContentSourceIntegratedAt)
      );
      this.buildInfoRow(
        '图源服务注册',
        `${this.contentSourceServiceRegisteredCount}/${this.contentSourceRuntimeTokens.length}`,
        this.contentSourceServiceRegisteredCount > 0
      );
      this.buildInfoRow('初始化阶段', `${this.currentInitPhase}（${this.currentInitText}）`, true);
      this.buildInfoRow('完成阶段数', `${this.completedPhaseCount}`);
      this.buildInfoRow('初始化完成', this.initCompleted ? '是' : '否', this.initCompleted);
      this.buildInfoRow('初始化失败', this.initFailed ? '是' : '否', !this.initFailed);
      this.buildInfoRow('最近错误数', `${this.recentErrorCount}`, this.recentErrorCount <= 0);
      if (this.initFailedMessage.length > 0) {
        Divider()
          .color(ThemeAwareHelper.getTestManagementThemedColor('panel_border', this.themeState.currentTheme));
        Text(`失败原因：${this.initFailedMessage}`)
          .fontSize(12)
          .fontFamily(this.appFontFamily)
          .fontColor(ThemeAwareHelper.getTestManagementThemedColor('color_warning', this.themeState.currentTheme))
          .alignSelf(ItemAlign.Start);
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
  buildModuleCard(card: NGFModuleStatusCard): void {
    Column({ space: 10 }) {
      Row() {
        Text(card.moduleId)
          .fontSize(16)
          .fontWeight(FontWeight.Bold)
          .fontFamily(this.appFontFamily)
          .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_primary', this.themeState.currentTheme))
          .layoutWeight(1)
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis });

        Text(card.isHealthy ? '已检测' : '异常')
          .fontSize(12)
          .fontWeight(FontWeight.Medium)
          .fontFamily(this.appFontFamily)
          .fontColor(this.statusColor(card.isHealthy));
      }
      .width('100%')
      .alignItems(VerticalAlign.Center);

      this.buildInfoRow('层级', card.layer);
      this.buildInfoRow('路径', card.rootPath);
      this.buildInfoRow('契约状态', card.contractStatus, true);
      this.buildInfoRow('运行状态', card.runtimeStatus, card.isHealthy);
      this.buildInfoRow('检测通道', card.detectionChannel);
    }
    .width('100%')
    .padding(14)
    .backgroundColor(SettingsPanelSurfaceHelper.getBackground(this.themeState.currentTheme))
    .linearGradient(SettingsPanelSurfaceHelper.getSurfaceGradient(this.themeState.currentTheme))
    .backgroundBlurStyle(SettingsPanelSurfaceHelper.getBlurStyle(this.themeState.currentTheme), SettingsPanelSurfaceHelper.getBlurOptions(this.themeState.currentTheme))
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
    .margin({ bottom: 12 })
  }

  @Builder
  buildModuleSection(): void {
    Column({ space: 10 }) {
      Text('NGF 模块检测')
        .fontSize(18)
        .fontWeight(FontWeight.Bold)
        .fontFamily(this.appFontFamily)
        .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_primary', this.themeState.currentTheme))
        .alignSelf(ItemAlign.Start)

      ForEach(this.moduleCards, (card: NGFModuleStatusCard) => {
        this.buildModuleCard(card);
      }, (card: NGFModuleStatusCard): string => card.moduleId)
    }
    .width('100%')
  }

  @Builder
  buildEventsCard(): void {
    Column({ space: 10 }) {
      Text('事件桥接与探针')
        .fontSize(18)
        .fontWeight(FontWeight.Bold)
        .fontFamily(this.appFontFamily)
        .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_primary', this.themeState.currentTheme))
        .alignSelf(ItemAlign.Start)

      this.buildInfoRow('最近初始化事件', this.lastInitEventName.length > 0 ? this.lastInitEventName : '未收到');
      this.buildInfoRow('最近事件时间', this.formatTime(this.lastInitEventAt));
      this.buildInfoRow('探针回调次数', `${this.eventProbeCount}`, this.eventProbeCount > 0);
      this.buildInfoRow('探针最近时间', this.formatTime(this.eventProbeLastAt));
      this.buildInfoRow('探针健康状态', this.eventProbeHealthy ? '通过' : '未通过', this.eventProbeHealthy);

      if (this.lastInitEventPayload.length > 0) {
        Divider()
          .color(ThemeAwareHelper.getTestManagementThemedColor('panel_border', this.themeState.currentTheme));
        Text('最近初始化事件载荷')
          .fontSize(12)
          .fontWeight(FontWeight.Medium)
          .fontFamily(this.appFontFamily)
          .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_secondary', this.themeState.currentTheme))
          .alignSelf(ItemAlign.Start);
        Text(this.lastInitEventPayload)
          .fontSize(12)
          .fontFamily(this.appFontFamily)
          .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_muted', this.themeState.currentTheme))
          .maxLines(6)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
          .alignSelf(ItemAlign.Start);
      }

      if (this.eventProbeLastPayload.length > 0) {
        Text(`探针载荷：${this.eventProbeLastPayload}`)
          .fontSize(12)
          .fontFamily(this.appFontFamily)
          .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_muted', this.themeState.currentTheme))
          .maxLines(2)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
          .alignSelf(ItemAlign.Start);
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
  buildActionCard(): void {
    Column({ space: 12 }) {
      Text('执行动作')
        .fontSize(18)
        .fontWeight(FontWeight.Bold)
        .fontFamily(this.appFontFamily)
        .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_primary', this.themeState.currentTheme))
        .alignSelf(ItemAlign.Start)

      Button('刷新 NGF 状态')
        .width('100%')
        .height(44)
        .fontSize(15)
        .fontWeight(FontWeight.Medium)
        .fontFamily(this.appFontFamily)
        .fontColor(ThemeAwareHelper.getTestManagementThemedColor('accent_primary', this.themeState.currentTheme))
        .backgroundColor(SettingsPanelSurfaceHelper.getBackground(this.themeState.currentTheme))
        .linearGradient(SettingsPanelSurfaceHelper.getSurfaceGradient(this.themeState.currentTheme))
        .backgroundBlurStyle(SettingsPanelSurfaceHelper.getBlurStyle(this.themeState.currentTheme), SettingsPanelSurfaceHelper.getBlurOptions(this.themeState.currentTheme))
        .backgroundEffect(SettingsPanelSurfaceHelper.getBackgroundEffect(this.themeState.currentTheme))
        .borderRadius(SettingsPanelSurfaceHelper.getRadius(this.themeState.currentTheme))
        .clip(true)
        .border({
          width: 1,
          color: ThemeAwareHelper.getTestManagementThemedColor('accent_primary', this.themeState.currentTheme)
        })
        .onClick(() => {
          this.refreshRuntimeSnapshot(true);
        })

      Button('执行事件总线探针')
        .width('100%')
        .height(44)
        .fontSize(15)
        .fontFamily(this.appFontFamily)
        .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_primary', this.themeState.currentTheme))
        .backgroundColor(SettingsPanelSurfaceHelper.getBackground(this.themeState.currentTheme))
        .linearGradient(SettingsPanelSurfaceHelper.getSurfaceGradient(this.themeState.currentTheme))
        .backgroundBlurStyle(SettingsPanelSurfaceHelper.getBlurStyle(this.themeState.currentTheme), SettingsPanelSurfaceHelper.getBlurOptions(this.themeState.currentTheme))
        .backgroundEffect(SettingsPanelSurfaceHelper.getBackgroundEffect(this.themeState.currentTheme))
        .borderRadius(SettingsPanelSurfaceHelper.getRadius(this.themeState.currentTheme))
        .clip(true)
        .border({
          width: SettingsPanelSurfaceHelper.getBorderWidth(this.themeState.currentTheme),
          color: SettingsPanelSurfaceHelper.getBorderColor(this.themeState.currentTheme)
        })
        .onClick(() => {
          this.triggerEventProbe();
          this.getUIContext().getPromptAction().showToast({
            message: '已发送事件总线探针',
            duration: 1200
          });
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

  build() {
    HdsNavDestination() {
      Stack() {
        SharedPageBackgroundLayer({
          defaultBackgroundColor: ThemeAwareHelper.getTestManagementThemedColor('background_dark', this.themeState.currentTheme),
          mode: GlobalBackgroundLayerMode.IMMERSIVE
        })
          .width('100%')
          .height('100%')
          .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.TOP, SafeAreaEdge.BOTTOM]);

        Scroll() {
          Column({ space: 16 }) {
            Blank().height(SettingsPageTitleBarManager.getContentTopPadding(this.statusBarHeight));
            this.buildOverviewCard();
            this.buildRuntimeCard();
            this.buildModuleSection();
            this.buildEventsCard();
            this.buildActionCard();
            Blank().height(40);
          }
          .width('100%')
          .padding({ left: 16, right: 16, bottom: 40 });
        }
        .width('100%')
        .height('100%')
        .edgeEffect(EdgeEffect.Spring)
        .scrollBar(BarState.Auto)
        .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.TOP, SafeAreaEdge.BOTTOM]);

        SettingsImmersiveTitleBar({
          themeState: this.themeState,
          title: 'NGF框架状态',
          appFontFamily: this.appFontFamily,
          pathStack: this.pathStack
        });
      }
    }
    .hideTitleBar(true)
    .ignoreLayoutSafeArea([LayoutSafeAreaType.SYSTEM], [LayoutSafeAreaEdge.TOP, LayoutSafeAreaEdge.BOTTOM])
    .onReady((context: NavDestinationContext) => {
      this.pathStack = context.pathStack;
      this.refreshRuntimeSnapshot(false);
    })
    .backgroundColor(Color.Transparent);
  }
}
