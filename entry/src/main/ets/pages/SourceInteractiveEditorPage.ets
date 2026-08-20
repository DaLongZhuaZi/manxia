/**
 * 漫匣交互式图源编辑器
 */

import { common } from '@kit.AbilityKit';
import { BusinessError } from '@kit.BasicServicesKit';
import { webview } from '@kit.ArkWeb';
import { HdsNavDestination } from '@kit.UIDesignKit';
import { logger } from 'manxia_core/src/main/ets/Utils/Logger';
import { SafeUtils } from 'manxia_core/src/main/ets/Utils/SafeUtils';
import { AppFloatingWindowConfig, WindowManager } from '../Utils/WindowManager';
import { ThemeAwareHelper, ThemeAwareState } from '../Framework/Components/ThemeAware';
import { ThemeManager, ThemeType } from '../Framework/Managers/ThemeManager';
import { AppColors } from '../Framework/Theme/AppColors';
import { FontAwareHelper, FontAwareState } from '../Framework/Components/FontAware';
import { SharedPageBackgroundLayer } from '../Framework/Components/SharedPageBackgroundLayer';
import { GlobalBackgroundLayerMode } from '../Framework/Components/GlobalBackgroundLayer';
import { SettingsImmersiveTitleBar } from './settings/SettingsImmersiveTitleBar';
import { SettingsImmersiveTitleActionItem, SettingsPageTitleBarManager } from './settings/SettingsPageTitleBarManager';
import { SettingsPanelSurfaceHelper } from './settings/SettingsPanelSurfaceHelper';
import {
  BackgroundTaskManager,
  BackgroundTask,
  TaskCancelSignal,
  TaskNotificationScene,
  TaskStatus,
  TaskType
} from '../Framework/Task/BackgroundTaskManager';
import { TaskNavigationTarget } from '../Framework/Task/TaskNavigationTypes';
import {
  sourceAutoCheckHistoryService,
  SourceAutoCheckRecord,
  SourceAutoCheckRecordStatus
} from 'manxia_source_engine/src/main/ets/Framework/SourceEditor/SourceAutoCheckHistoryService';
import { interactiveSourceEditorService } from '../Framework/SourceEditor/InteractiveSourceEditorService';
import {
  createEmptySourceEditorSelectionAssessment,
  createEmptySourceEditorWorkflowPreview,
  SourceEditorInspectorSnapshot,
  sourceEditorInspectorStateManager
} from 'manxia_source_engine/src/main/ets/Framework/SourceEditor/SourceEditorInspectorStateManager';
import {
  DomSelectionSnapshot,
  GeneratedSelectorCandidate,
  SourceEditorDraft,
  SourceEditorGuidePhase,
  SourceEditorMode,
  SourceEditorSaveResult,
  SourceEditorTaskType,
  SourceEditorWorkflowGuideStep,
  SourceEditorWorkflowPreview,
  SourceEditorWorkflowPreviewStatus,
  SourceInteractiveEditorPageParams,
  SourceSaveMode
} from 'manxia_source_engine/src/main/ets/Framework/SourceEditor/SourceEditorTypes';

const TAG = 'SourceInteractiveEditorPage';
const SOURCE_EDITOR_FLOATING_INSPECTOR_CONFIG: AppFloatingWindowConfig = {
  routeName: 'SourceEditorFloatingInspectorPage',
  title: '图源检查器',
  widthVp: 340,
  heightVp: 380,
  xVp: 18,
  yVp: 112,
  zLevel: 9
};
const GUIDE_POLL_INTERVAL_MS: number = 450;
const PREVIEW_RETRY_DELAY_MS: number = 900;
const AUTO_CHECK_PAGE_SETTLE_MS: number = 2200;
const AUTO_CHECK_SCRIPT_TIMEOUT_MS: number = 3600;
const AUTO_CHECK_MAX_RETRIES: number = 2;
const AUTO_CHECK_PROGRESS_TICK_MS: number = 350;
const AUTO_CHECK_WORKFLOW_PROGRESS_ESTIMATE_MS: number = 8200;
const AUTO_CHECK_EXTERNAL_WORKFLOW_KEYS: string[] = ['popular', 'latest', 'search'];
const AUTO_CHECK_HISTORY_PREVIEW_LIMIT: number = 6;

interface SourceEditorTaskOption {
  taskType: SourceEditorTaskType;
  label: string;
}

interface SourceAutoCheckTaskOption {
  workflowKey: string;
  taskType: SourceEditorTaskType;
  label: string;
  useInspectorStep: boolean;
}

interface DomSelectionRawCandidate {
  type?: string;
  value?: string;
  score?: number;
  matchedCount?: number;
  note?: string;
}

interface DomSelectionRaw {
  tagName?: string;
  text?: string;
  htmlPreview?: string;
  href?: string;
  src?: string;
  idValue?: string;
  className?: string;
  cssSelector?: string;
  xpath?: string;
  matchedCount?: number;
  candidates?: DomSelectionRawCandidate[];
  containerSelector?: string;
  containerMatchedCount?: number;
  siblingSimilarCount?: number;
  imageCount?: number;
  linkCount?: number;
  titleCandidate?: string;
  imageCandidate?: string;
  hrefCandidate?: string;
  itemScore?: number;
}

interface WorkflowPreviewRaw {
  selectorCount?: number;
  scriptCount?: number;
  sampleTitle?: string;
  sampleUrl?: string;
  sampleCover?: string;
  summary?: string;
  detail?: string;
  error?: string;
  pending?: boolean;
}

interface SourceEditorSiteOption {
  id: string;
  label: string;
  baseUrl: string;
}

type SourceEditorStringMap = Record<string, string>;
type SourceEditorWorkflowMap = Record<string, Object>;

interface SourceEditorSiteMetadata {
  baseUrl?: string;
  alternativeUrls?: Object;
}

interface SourceEditorSiteSettingOption {
  value?: string;
  label?: string;
}

interface SourceEditorSiteSetting {
  name?: string;
  default?: string;
  options?: SourceEditorSiteSettingOption[];
}

interface SourceEditorSiteSettings {
  domain?: SourceEditorSiteSetting;
  apiDomain?: SourceEditorSiteSetting;
  baseUrl?: SourceEditorSiteSetting;
  siteUrl?: SourceEditorSiteSetting;
}

interface SourceEditorSiteRawConfig {
  metadata?: SourceEditorSiteMetadata;
  settings?: SourceEditorSiteSettings;
  mirrors?: string[];
  workflows?: Object;
}

interface SourceEditorAutoRawAction {
  type?: string;
  selector?: string;
  code?: string;
  url?: string;
}

interface SourceEditorAutoRawWorkflowObject {
  actions?: SourceEditorAutoRawAction[];
}

interface SourceAutoCheckWorkflowResult {
  siteId: string;
  siteLabel: string;
  siteBaseUrl: string;
  workflowKey: string;
  taskLabel: string;
  status: SourceEditorWorkflowPreviewStatus;
  score: number;
  attemptCount: number;
  durationMs: number;
  targetUrl: string;
  summary: string;
  detail: string;
  errorMessage: string;
  selectorCount: number;
  scriptCount: number;
  sampleTitle: string;
  sampleUrl: string;
}

interface SourceAutoCheckSiteReport {
  siteId: string;
  siteLabel: string;
  siteBaseUrl: string;
  score: number;
  successCount: number;
  totalCount: number;
  durationMs: number;
  summary: string;
  recommended: boolean;
  workflowResults: SourceAutoCheckWorkflowResult[];
}

interface SourceAutoCheckTaskResult {
  sourceName: string;
  recommendedSiteBaseUrl: string;
  summary: string;
  reportJson: string;
}

@Component
export struct SourceInteractiveEditorPage {
  @State pathStack: NavPathStack = new NavPathStack();
  @State themeState: ThemeAwareState = new ThemeAwareState();
  @State fontState: FontAwareState = new FontAwareState();
  @StorageLink('appFontFamily') appFontFamily: string = 'HarmonyOS Sans';
  @StorageProp('statusBarHeight') statusBarHeight: number = 0;
  @StorageProp('navigationBarHeight') navigationBarHeight: number = 0;

  @State sourceName: string = '';
  @State sourcePkg: string = '';
  @State testUrl: string = '';
  @State selectedSummary: string = '未选择元素';
  @State generatedWorkflowJson: string = '';
  @State configPreview: string = '';
  @State saveMessage: string = '';
  @State siteOptions: SourceEditorSiteOption[] = [];
  @State selectedSiteBaseUrl: string = '';
  @State autoCheckRunning: boolean = false;
  @State autoCheckReportReady: boolean = false;
  @State autoCheckProgressText: string = '';
  @State autoCheckSiteReports: SourceAutoCheckSiteReport[] = [];
  @State autoCheckRecommendedSiteBaseUrl: string = '';
  @State autoCheckActiveSiteId: string = '';
  @State autoCheckActiveSiteBaseUrl: string = '';
  @State autoCheckActiveTargetUrl: string = '';
  @State autoCheckProgressTick: number = 0;
  @State showAutoCheckScopePicker: boolean = false;
  @State autoCheckScopeOptions: SourceAutoCheckTaskOption[] = [];
  @State selectedAutoCheckWorkflowKeys: string[] = [];
  @State autoCheckHistoryRecords: SourceAutoCheckRecord[] = [];
  @State expandedAutoCheckHistoryTaskId: string = '';
  @State isLoading: boolean = true;
  @State pickerInjected: boolean = false;
  @State inspectorActive: boolean = false;
  @State editorMode: SourceEditorMode = SourceEditorMode.SIMPLE;
  @State taskType: SourceEditorTaskType = SourceEditorTaskType.SEARCH;

  private componentId: string = `SourceInteractiveEditorPage_${Date.now()}`;
  private themeManager: ThemeManager = ThemeManager.getInstance();
  private webController: webview.WebviewController = new webview.WebviewController();
  private backgroundTaskManager: BackgroundTaskManager = BackgroundTaskManager.getInstance();
  private draft: SourceEditorDraft | null = null;
  private guidePollTimerId: number = -1;
  private pendingLoadTimerId: number = -1;
  private previewTimerId: number = -1;
  private previewTimerDueAt: number = 0;
  private loadRequestVersion: number = 0;
  private lastPreviewAttemptAt: number = 0;
  private workflowPreviewRetryCount: number = 0;
  private lastGuideRenderVersion: number = -1;
  private lastSelectionRequestVersion: number = -1;
  private lastLoadedGuideUrl: string = '';
  private lastCommittedLoadUrl: string = '';
  private mainFrameLoaded: boolean = false;
  private autoCheckRequestToken: number = 0;
  private autoCheckCancelRequested: boolean = false;
  private autoCheckBackgroundTaskId: string = '';
  private autoCheckRunStartTime: number = 0;
  private autoCheckCurrentSiteCount: number = 0;
  private autoCheckRecordRefreshTimerId: number = -1;
  private autoCheckProgressTimerId: number = -1;
  private autoCheckActiveWorkflowStartedAt: number = 0;

  aboutToAppear() {
    ThemeAwareHelper.initializeThemeAware(this.componentId, this.themeState, (theme: ThemeType) => {
      logger.info(TAG, `主题切换: ${theme}`);
    });
    FontAwareHelper.initializeFontAware(this.componentId, this.fontState, (newState: FontAwareState) => {
      this.fontState = newState;
    });
    this.startGuidePolling();
  }

  aboutToDisappear() {
    ThemeAwareHelper.cleanupThemeAware(this.componentId);
    FontAwareHelper.cleanupFontAware(this.componentId);
    this.stopGuidePolling();
    this.clearPendingLoadTimer();
    this.clearPreviewTimer();
    this.stopAutoCheckRecordRefresh();
    this.stopAutoCheckProgressTimer();
    void this.closeFloatingInspectorOnLeave();
    sourceEditorInspectorStateManager.resetGuide('SourceInteractiveEditorPage aboutToDisappear');
  }

  private startGuidePolling(): void {
    this.stopGuidePolling();
    this.guidePollTimerId = setInterval((): void => {
      this.applyGuideSnapshot(false);
      this.maybeRunWorkflowPreviewWatchdog();
    }, GUIDE_POLL_INTERVAL_MS);
  }

  private stopGuidePolling(): void {
    if (this.guidePollTimerId >= 0) {
      clearInterval(this.guidePollTimerId);
      this.guidePollTimerId = -1;
    }
  }

  private clearPendingLoadTimer(): void {
    if (this.pendingLoadTimerId >= 0) {
      clearTimeout(this.pendingLoadTimerId);
      this.pendingLoadTimerId = -1;
    }
  }

  private clearPreviewTimer(): void {
    if (this.previewTimerId >= 0) {
      clearTimeout(this.previewTimerId);
      this.previewTimerId = -1;
    }
    this.previewTimerDueAt = 0;
  }

  private async initialize(params: SourceInteractiveEditorPageParams | null): Promise<void> {
    try {
      this.isLoading = true;
      const pageParams: SourceInteractiveEditorPageParams = params ? params : {
        sourceId: 0,
        sourceName: '新建图源',
        sourcePkg: '',
        initialUrl: '',
        createNew: true,
        autoRunDiagnostics: false
      };
      const draft: SourceEditorDraft = await interactiveSourceEditorService.createDraft(pageParams);
      this.draft = draft;
      sourceEditorInspectorStateManager.startGuide(draft, draft.taskType);
      this.syncDraftState(draft);
      this.applyGuideSnapshot(true);
      this.ensureInitialTargetLoaded();
      const hostContext = this.getUIContext().getHostContext() as common.UIAbilityContext;
      await sourceAutoCheckHistoryService.initialize(hostContext);
      if (pageParams.autoCheckTaskId !== undefined && pageParams.autoCheckTaskId.length > 0) {
        await this.restoreAutoCheckRecord(pageParams.autoCheckTaskId);
      } else if (pageParams.openAutoCheckReport === true) {
        await this.restoreLatestAutoCheckRecord();
      } else if (pageParams.autoRunDiagnostics === true) {
        setTimeout((): void => {
          void this.startAutoCheckForExternalEntry();
        }, 450);
      } else {
        void this.openFloatingInspector();
      }
    } catch (error) {
      logger.error(TAG, `初始化交互式编辑器失败: ${String(error)}`);
      this.saveMessage = `初始化失败: ${String(error)}`;
    } finally {
      this.isLoading = false;
    }
  }

  private syncDraftState(draft: SourceEditorDraft): void {
    this.sourceName = draft.sourceName;
    this.sourcePkg = draft.sourcePkg;
    this.testUrl = draft.testUrl;
    this.taskType = draft.taskType;
    this.editorMode = draft.mode;
    this.generatedWorkflowJson = draft.generatedWorkflowJson;
    this.configPreview = draft.configJson;
    this.refreshSiteOptions(draft.configJson, draft.testUrl);
    if (draft.lastSelection) {
      this.selectedSummary = `${draft.lastSelection.tagName} · ${draft.lastSelection.cssSelector} · ${draft.lastSelection.matchedCount}`;
    }
    this.refreshFloatingInspectorState();
  }

  private refreshFloatingInspectorState(): void {
    sourceEditorInspectorStateManager.updateDraft(this.draft, this.selectedSummary, this.saveMessage);
  }

  private refreshSiteOptions(configJson: string, currentUrl: string): void {
    const options: SourceEditorSiteOption[] = this.buildSiteOptions(configJson);
    this.siteOptions = options;
    this.selectedSiteBaseUrl = this.resolveSelectedSiteBaseUrl(options, currentUrl);
  }

  private buildSiteOptions(configJson: string): SourceEditorSiteOption[] {
    const options: SourceEditorSiteOption[] = [];
    const rawConfig: SourceEditorSiteRawConfig = SafeUtils.parseObj<SourceEditorSiteRawConfig>(configJson);
    const metadata: SourceEditorSiteMetadata | undefined = rawConfig.metadata;
    if (metadata) {
      this.addSiteOption(options, 'default', '默认', metadata.baseUrl);
    }

    const settings: SourceEditorSiteSettings | undefined = rawConfig.settings;
    if (settings) {
      this.collectSettingSiteOptions(options, settings.domain, '域名');
      this.collectSettingSiteOptions(options, settings.apiDomain, 'API');
      this.collectSettingSiteOptions(options, settings.baseUrl, '站点');
      this.collectSettingSiteOptions(options, settings.siteUrl, '站点');
    }
    if (metadata) {
      this.collectAlternativeUrlOptions(options, metadata.alternativeUrls);
    }

    const mirrors: string[] | undefined = rawConfig.mirrors;
    if (mirrors) {
      for (let index = 0; index < mirrors.length; index += 1) {
        this.addSiteOption(options, `mirror_${index}`, `镜像${index + 1}`, mirrors[index]);
      }
    }
    return options;
  }

  private collectAlternativeUrlOptions(options: SourceEditorSiteOption[], alternativeUrls: Object | undefined): void {
    if (!alternativeUrls) {
      return;
    }
    const keys: string[] = Object.keys(alternativeUrls);
    const urlMap: SourceEditorStringMap = alternativeUrls as SourceEditorStringMap;
    for (let index = 0; index < keys.length; index += 1) {
      const key: string = keys[index];
      const value: string | undefined = urlMap[key];
      if (value !== undefined && typeof value === 'string') {
        this.addSiteOption(options, `alt_${key}`, key, value);
      }
    }
  }

  private collectSettingSiteOptions(
    options: SourceEditorSiteOption[],
    setting: SourceEditorSiteSetting | undefined,
    labelPrefix: string
  ): void {
    if (!setting) {
      return;
    }
    const settingName: string = setting.name && setting.name.length > 0 ? setting.name : labelPrefix;
    this.addSiteOption(options, `${labelPrefix}_default`, settingName, setting.default);
    const settingOptions: SourceEditorSiteSettingOption[] | undefined = setting.options;
    if (!settingOptions) {
      return;
    }
    for (let index = 0; index < settingOptions.length; index += 1) {
      const option: SourceEditorSiteSettingOption = settingOptions[index];
      const label: string = option.label && option.label.length > 0 ? option.label : `${settingName}${index + 1}`;
      this.addSiteOption(options, `${labelPrefix}_${index}`, label, option.value);
    }
  }

  private addSiteOption(options: SourceEditorSiteOption[], id: string, label: string, url: string | undefined): void {
    const baseUrl: string = this.normalizeSiteBaseUrl(url);
    if (baseUrl.length <= 0) {
      return;
    }
    for (let index = 0; index < options.length; index += 1) {
      if (this.normalizeSiteBaseUrl(options[index].baseUrl) === baseUrl) {
        return;
      }
    }
    const option: SourceEditorSiteOption = {
      id: `${id}_${options.length}`,
      label: this.resolveSiteLabel(label, baseUrl),
      baseUrl: baseUrl
    };
    options.push(option);
  }

  private resolveSiteLabel(label: string, baseUrl: string): string {
    const trimmedLabel: string = label.trim();
    if (trimmedLabel.length > 0 && trimmedLabel.length <= 20) {
      return trimmedLabel;
    }
    const host: string = this.resolveHostFromUrl(baseUrl);
    if (host.length > 0) {
      return host;
    }
    return baseUrl;
  }

  private normalizeSiteBaseUrl(url: string | undefined): string {
    if (!url) {
      return '';
    }
    let trimmed: string = url.trim();
    if (trimmed.startsWith('//')) {
      trimmed = `https:${trimmed}`;
    }
    if (!trimmed.startsWith('http://') && !trimmed.startsWith('https://')) {
      return '';
    }
    while (trimmed.length > 1 && trimmed.endsWith('/')) {
      trimmed = trimmed.substring(0, trimmed.length - 1);
    }
    return trimmed;
  }

  private resolveHostFromUrl(url: string): string {
    const baseUrl: string = this.normalizeSiteBaseUrl(url);
    const schemeIndex: number = baseUrl.indexOf('://');
    if (schemeIndex < 0) {
      return '';
    }
    const hostStart: number = schemeIndex + 3;
    const pathIndex: number = baseUrl.indexOf('/', hostStart);
    if (pathIndex < 0) {
      return baseUrl.substring(hostStart);
    }
    return baseUrl.substring(hostStart, pathIndex);
  }

  private resolveSelectedSiteBaseUrl(options: SourceEditorSiteOption[], currentUrl: string): string {
    const currentBaseUrl: string = this.normalizeSiteBaseUrl(this.resolveBaseUrlFromTestUrl(currentUrl));
    for (let index = 0; index < options.length; index += 1) {
      const optionBaseUrl: string = this.normalizeSiteBaseUrl(options[index].baseUrl);
      if (optionBaseUrl.length > 0 && optionBaseUrl === currentBaseUrl) {
        return optionBaseUrl;
      }
    }
    if (options.length > 0) {
      return options[0].baseUrl;
    }
    return '';
  }

  private switchTestSite(option: SourceEditorSiteOption): void {
    const nextUrl: string = this.buildSwitchedTestUrl(option.baseUrl);
    this.selectedSiteBaseUrl = option.baseUrl;
    if (this.draft) {
      this.draft.testUrl = nextUrl;
      this.draft.updateTime = Date.now();
      this.refreshFloatingInspectorState();
    }
    sourceEditorInspectorStateManager.updateCurrentTargetUrl(nextUrl);
    this.requestWorkflowTargetLoad(nextUrl, true);
  }

  private buildSwitchedTestUrl(nextBaseUrl: string): string {
    const normalizedNextBaseUrl: string = this.normalizeSiteBaseUrl(nextBaseUrl);
    if (normalizedNextBaseUrl.length <= 0) {
      return this.testUrl;
    }
    const currentUrl: string = this.testUrl.trim();
    const currentBaseUrl: string = this.normalizeSiteBaseUrl(this.resolveBaseUrlFromTestUrl(currentUrl));
    if (currentBaseUrl.length <= 0) {
      return normalizedNextBaseUrl;
    }
    if (!this.isKnownSiteBaseUrl(currentBaseUrl)) {
      return normalizedNextBaseUrl;
    }
    if (currentUrl.length <= currentBaseUrl.length) {
      return normalizedNextBaseUrl;
    }
    return `${normalizedNextBaseUrl}${currentUrl.substring(currentBaseUrl.length)}`;
  }

  private isKnownSiteBaseUrl(baseUrl: string): boolean {
    const normalizedBaseUrl: string = this.normalizeSiteBaseUrl(baseUrl);
    for (let index = 0; index < this.siteOptions.length; index += 1) {
      if (this.normalizeSiteBaseUrl(this.siteOptions[index].baseUrl) === normalizedBaseUrl) {
        return true;
      }
    }
    return false;
  }

  private cancelAutoCheck(reason: string): void {
    if (!this.autoCheckRunning) {
      return;
    }
    if (this.autoCheckBackgroundTaskId.length > 0) {
      this.backgroundTaskManager.cancelTask(this.autoCheckBackgroundTaskId);
    }
    this.autoCheckCancelRequested = true;
    this.autoCheckRequestToken += 1;
    this.autoCheckRunning = false;
    this.autoCheckActiveSiteId = '';
    this.autoCheckActiveSiteBaseUrl = '';
    this.autoCheckActiveTargetUrl = '';
    this.autoCheckActiveWorkflowStartedAt = 0;
    this.stopAutoCheckProgressTimer();
    this.autoCheckProgressText = reason;
  }

  private startAutoCheckMode(): void {
    this.openAutoCheckScopePicker();
  }

  private async startAutoCheckForExternalEntry(): Promise<void> {
    const supportedTasks: SourceAutoCheckTaskOption[] = this.getAutoCheckTasksByWorkflowKeys(AUTO_CHECK_EXTERNAL_WORKFLOW_KEYS);
    await this.startAutoCheckWithTasks(supportedTasks, '当前图源未配置热门、最新或搜索巡检流程');
  }

  private openAutoCheckScopePicker(): void {
    if (this.draft === null) {
      this.getUIContext().getPromptAction().showToast({ message: '草稿未就绪' });
      return;
    }
    if (this.autoCheckRunning) {
      this.getUIContext().getPromptAction().showToast({ message: '自动检查正在运行' });
      return;
    }
    const supportedTasks: SourceAutoCheckTaskOption[] = this.getConfigAutoCheckTasks();
    if (supportedTasks.length <= 0) {
      this.getUIContext().getPromptAction().showToast({ message: '当前图源没有可自动检查的工作流' });
      return;
    }
    this.autoCheckScopeOptions = supportedTasks;
    this.selectedAutoCheckWorkflowKeys = this.resolveDefaultAutoCheckSelection(supportedTasks);
    this.autoCheckHistoryRecords = [];
    this.expandedAutoCheckHistoryTaskId = '';
    this.showAutoCheckScopePicker = true;
    void this.loadAutoCheckHistoryRecords();
  }

  private async loadAutoCheckHistoryRecords(): Promise<void> {
    if (this.draft === null) {
      return;
    }
    try {
      const hostContext = this.getUIContext().getHostContext() as common.UIAbilityContext;
      await sourceAutoCheckHistoryService.initialize(hostContext);
      const records: SourceAutoCheckRecord[] = await sourceAutoCheckHistoryService.getRecordsForSource(
        this.draft.sourceId,
        this.sourcePkg,
        AUTO_CHECK_HISTORY_PREVIEW_LIMIT
      );
      this.autoCheckHistoryRecords = records;
    } catch (error) {
      logger.warn(TAG, `加载巡检历史失败: ${String(error)}`);
      this.autoCheckHistoryRecords = [];
    }
  }

  private async startAutoCheckWithTasks(supportedTasks: SourceAutoCheckTaskOption[], emptyMessage: string): Promise<void> {
    if (this.draft === null) {
      this.getUIContext().getPromptAction().showToast({ message: '草稿未就绪' });
      return;
    }
    if (this.autoCheckRunning) {
      this.getUIContext().getPromptAction().showToast({ message: '自动检查正在运行' });
      return;
    }
    if (supportedTasks.length <= 0) {
      this.getUIContext().getPromptAction().showToast({ message: emptyMessage });
      return;
    }
    const sites: SourceEditorSiteOption[] = this.getAutoCheckSites();
    if (sites.length <= 0) {
      this.getUIContext().getPromptAction().showToast({ message: '没有可测试的源站点' });
      return;
    }

    const hostContext = this.getUIContext().getHostContext() as common.UIAbilityContext;
    await sourceAutoCheckHistoryService.initialize(hostContext);
    const token: number = this.prepareAutoCheckRun();
    this.autoCheckCurrentSiteCount = sites.length;
    const taskId: string = this.backgroundTaskManager.createTask(
      TaskType.SOURCE_AUTO_CHECK,
      `图源巡检: ${this.sourceName}`,
      async (
        onProgress: (current: number, total: number, message: string) => void,
        cancelSignal: TaskCancelSignal
      ): Promise<Object | undefined> => {
        return await this.executeAutoCheckTask(token, sites, supportedTasks, onProgress, cancelSignal);
      },
      {
        context: hostContext,
        enableBackgroundRunning: true,
        notification: {
          scene: TaskNotificationScene.SOURCE_AUTO_CHECK,
          targetName: this.sourceName.length > 0 ? this.sourceName : '图源'
        }
      }
    );
    const navigationTarget: TaskNavigationTarget = this.createAutoCheckNavigationTarget(taskId);
    this.backgroundTaskManager.updateTaskNavigation(taskId, navigationTarget);
    this.autoCheckBackgroundTaskId = taskId;
    await this.persistAutoCheckRecord(taskId, 'RUNNING', supportedTasks, [], '准备自动检查', '');
    void this.backgroundTaskManager.startTask(taskId).catch((error: Error): void => {
      if (this.autoCheckCancelRequested) {
        logger.info(TAG, `图源自动巡检已取消: ${String(error)}`);
        return;
      }
      this.autoCheckRunning = false;
      this.autoCheckActiveSiteId = '';
      this.autoCheckActiveSiteBaseUrl = '';
      this.autoCheckActiveTargetUrl = '';
      this.autoCheckActiveWorkflowStartedAt = 0;
      this.stopAutoCheckProgressTimer();
      const errorMessage: string = error.message.length > 0 ? error.message : String(error);
      this.autoCheckProgressText = `自动检查失败: ${errorMessage}`;
      void this.persistAutoCheckRecord(taskId, 'FAILED', supportedTasks, this.autoCheckSiteReports, this.autoCheckProgressText, errorMessage);
      logger.warn(TAG, `图源自动巡检后台任务失败: ${String(error)}`);
    });
  }

  private prepareAutoCheckRun(): number {
    this.stopAutoCheckRecordRefresh();
    this.autoCheckRequestToken += 1;
    const token: number = this.autoCheckRequestToken;
    this.autoCheckRunStartTime = Date.now();
    this.autoCheckCancelRequested = false;
    this.autoCheckRunning = true;
    this.autoCheckReportReady = false;
    this.autoCheckProgressText = '准备自动检查';
    this.autoCheckSiteReports = [];
    this.autoCheckRecommendedSiteBaseUrl = '';
    this.autoCheckActiveSiteId = '';
    this.autoCheckActiveSiteBaseUrl = '';
    this.autoCheckActiveTargetUrl = '';
    this.autoCheckActiveWorkflowStartedAt = 0;
    this.autoCheckProgressTick = Date.now();
    this.autoCheckBackgroundTaskId = '';
    this.autoCheckCurrentSiteCount = 0;
    this.clearPreviewTimer();
    void this.closeFloatingInspectorOnLeave();
    this.startAutoCheckProgressTimer();
    return token;
  }

  private async executeAutoCheckTask(
    token: number,
    sites: SourceEditorSiteOption[],
    supportedTasks: SourceAutoCheckTaskOption[],
    onProgress: (current: number, total: number, message: string) => void,
    cancelSignal: TaskCancelSignal
  ): Promise<Object | undefined> {
    const totalWork: number = sites.length * supportedTasks.length;
    let completedWork: number = 0;
    onProgress(0, totalWork, '准备自动检查');

    const reports: SourceAutoCheckSiteReport[] = [];
    const runStartedAt: number = Date.now();
    for (let siteIndex = 0; siteIndex < sites.length; siteIndex += 1) {
      if (!this.isAutoCheckActive(token, cancelSignal)) {
        break;
      }
      const site: SourceEditorSiteOption = sites[siteIndex];
      const report: SourceAutoCheckSiteReport = this.createAutoCheckSiteReport(site, supportedTasks.length);
      reports.push(report);
      this.autoCheckActiveSiteId = site.id;
      this.autoCheckActiveSiteBaseUrl = site.baseUrl;
      this.autoCheckSiteReports = this.cloneAutoCheckSiteReports(reports);
      let chainedSampleUrl: string = '';
      const siteStartedAt: number = Date.now();
      for (let taskIndex = 0; taskIndex < supportedTasks.length; taskIndex += 1) {
        if (!this.isAutoCheckActive(token, cancelSignal)) {
          break;
        }
        const task: SourceAutoCheckTaskOption = supportedTasks[taskIndex];
        this.beginAutoCheckWorkflowProgress(site, reports);
        this.autoCheckProgressText = `${site.label} · ${task.label} (${siteIndex + 1}/${sites.length})`;
        onProgress(completedWork, totalWork, this.autoCheckProgressText);
        const result: SourceAutoCheckWorkflowResult = await this.runAutoCheckWorkflow(
          token,
          site,
          task,
          chainedSampleUrl,
          cancelSignal
        );
        report.workflowResults.push(result);
        if (result.status === SourceEditorWorkflowPreviewStatus.OK && result.sampleUrl.length > 0) {
          chainedSampleUrl = result.sampleUrl;
        }
        this.updateAutoCheckSiteReport(report, Date.now() - siteStartedAt);
        this.autoCheckSiteReports = this.cloneAutoCheckSiteReports(reports);
        await this.persistAutoCheckRecord(this.autoCheckBackgroundTaskId, 'RUNNING', supportedTasks, reports,
          this.autoCheckProgressText, '');
        completedWork += 1;
        onProgress(completedWork, totalWork, `${site.label} · ${task.label}: ${this.getAutoCheckStatusText(result.status)}`);
      }
    }

    if (!this.isAutoCheckActive(token, cancelSignal)) {
      this.handleAutoCheckCancelled('自动检查已取消');
      await this.persistAutoCheckRecord(this.autoCheckBackgroundTaskId, 'CANCELLED', supportedTasks, reports, '自动检查已取消', '');
      throw new Error('自动检查已取消');
    }
    const summary: string = this.finishAutoCheckReports(reports, Date.now() - runStartedAt);
    await this.persistAutoCheckRecord(this.autoCheckBackgroundTaskId, 'COMPLETED', supportedTasks, reports, summary, '');
    onProgress(totalWork, totalWork, summary);
    const taskResult: SourceAutoCheckTaskResult = {
      sourceName: this.sourceName,
      recommendedSiteBaseUrl: this.autoCheckRecommendedSiteBaseUrl,
      summary: summary,
      reportJson: JSON.stringify(reports)
    };
    return taskResult as Object;
  }

  private isAutoCheckActive(token: number, cancelSignal?: TaskCancelSignal): boolean {
    const taskCancelled: boolean = cancelSignal !== undefined && cancelSignal.isCancelled;
    return this.autoCheckRunning && !this.autoCheckCancelRequested && !taskCancelled && token === this.autoCheckRequestToken;
  }

  private handleAutoCheckCancelled(reason: string): void {
    this.autoCheckCancelRequested = true;
    this.autoCheckRunning = false;
    this.autoCheckActiveSiteId = '';
    this.autoCheckActiveSiteBaseUrl = '';
    this.autoCheckActiveTargetUrl = '';
    this.autoCheckActiveWorkflowStartedAt = 0;
    this.stopAutoCheckProgressTimer();
    this.autoCheckProgressText = reason;
  }

  private beginAutoCheckWorkflowProgress(site: SourceEditorSiteOption, reports: SourceAutoCheckSiteReport[]): void {
    this.autoCheckActiveSiteId = site.id;
    this.autoCheckActiveSiteBaseUrl = site.baseUrl;
    this.autoCheckActiveWorkflowStartedAt = Date.now();
    this.autoCheckProgressTick = this.autoCheckActiveWorkflowStartedAt;
    this.autoCheckSiteReports = this.cloneAutoCheckSiteReports(reports);
    this.startAutoCheckProgressTimer();
  }

  private startAutoCheckProgressTimer(): void {
    if (this.autoCheckProgressTimerId >= 0) {
      return;
    }
    this.autoCheckProgressTimerId = setInterval((): void => {
      if (!this.autoCheckRunning) {
        this.stopAutoCheckProgressTimer();
        return;
      }
      this.autoCheckProgressTick = Date.now();
    }, AUTO_CHECK_PROGRESS_TICK_MS);
  }

  private stopAutoCheckProgressTimer(): void {
    if (this.autoCheckProgressTimerId >= 0) {
      clearInterval(this.autoCheckProgressTimerId);
      this.autoCheckProgressTimerId = -1;
    }
  }

  private createAutoCheckNavigationTarget(taskId: string): TaskNavigationTarget {
    const target: TaskNavigationTarget = {
      routeName: 'SourceInteractiveEditorPage',
      sourceId: this.draft !== null ? this.draft.sourceId : 0,
      sourceName: this.sourceName,
      sourcePkg: this.sourcePkg,
      initialUrl: this.testUrl,
      autoCheckTaskId: taskId,
      openAutoCheckReport: true
    };
    return target;
  }

  private async persistAutoCheckRecord(
    taskId: string,
    status: SourceAutoCheckRecordStatus,
    tasks: SourceAutoCheckTaskOption[],
    reports: SourceAutoCheckSiteReport[],
    summary: string,
    errorMessage: string
  ): Promise<void> {
    if (taskId.length <= 0 || this.draft === null) {
      return;
    }
    const now: number = Date.now();
    const endTime: number = status === 'RUNNING' ? 0 : now;
    const startTime: number = this.autoCheckRunStartTime > 0 ? this.autoCheckRunStartTime : now;
    const record: SourceAutoCheckRecord = {
      taskId: taskId,
      sourceId: this.draft.sourceId,
      sourcePkg: this.sourcePkg,
      sourceName: this.sourceName,
      initialUrl: this.testUrl,
      status: status,
      startTime: startTime,
      endTime: endTime,
      durationMs: status === 'RUNNING' ? now - startTime : endTime - startTime,
      workflowKeysJson: this.stringifyAutoCheckWorkflowKeys(tasks),
      workflowLabelsJson: this.stringifyAutoCheckWorkflowLabels(tasks),
      siteCount: this.autoCheckCurrentSiteCount > 0 ? this.autoCheckCurrentSiteCount : reports.length,
      recommendedSiteBaseUrl: this.autoCheckRecommendedSiteBaseUrl,
      summary: summary,
      errorMessage: errorMessage,
      reportJson: JSON.stringify(reports),
      updateTime: now
    };
    await sourceAutoCheckHistoryService.saveRecord(record);
  }

  private stringifyAutoCheckWorkflowKeys(tasks: SourceAutoCheckTaskOption[]): string {
    const keys: string[] = [];
    for (let index = 0; index < tasks.length; index += 1) {
      keys.push(tasks[index].workflowKey);
    }
    return JSON.stringify(keys);
  }

  private stringifyAutoCheckWorkflowLabels(tasks: SourceAutoCheckTaskOption[]): string {
    const labels: string[] = [];
    for (let index = 0; index < tasks.length; index += 1) {
      labels.push(tasks[index].label);
    }
    return JSON.stringify(labels);
  }

  private async restoreLatestAutoCheckRecord(): Promise<void> {
    if (this.draft === null) {
      return;
    }
    const record: SourceAutoCheckRecord | null =
      await sourceAutoCheckHistoryService.getLatestRecordForSource(this.draft.sourceId, this.sourcePkg);
    if (record === null) {
      this.getUIContext().getPromptAction().showToast({ message: '暂无该图源的巡检记录' });
      return;
    }
    this.applyAutoCheckRecord(record);
  }

  private async restoreAutoCheckRecord(taskId: string): Promise<void> {
    const record: SourceAutoCheckRecord | null = await sourceAutoCheckHistoryService.getRecord(taskId);
    if (record === null) {
      this.autoCheckBackgroundTaskId = taskId;
      const task: BackgroundTask | undefined = this.backgroundTaskManager.getTask(taskId);
      if (task !== undefined) {
        this.applyAutoCheckTaskSnapshot(task);
        this.startAutoCheckRecordRefresh(taskId);
        return;
      }
      this.getUIContext().getPromptAction().showToast({ message: '未找到巡检记录' });
      return;
    }
    this.applyAutoCheckRecord(record);
  }

  private applyAutoCheckRecord(record: SourceAutoCheckRecord): void {
    this.autoCheckBackgroundTaskId = record.taskId;
    this.autoCheckRunStartTime = record.startTime;
    this.autoCheckCurrentSiteCount = record.siteCount;
    this.autoCheckRecommendedSiteBaseUrl = record.recommendedSiteBaseUrl;
    this.autoCheckSiteReports = this.cloneAutoCheckSiteReports(SafeUtils.parseArr<SourceAutoCheckSiteReport[]>(record.reportJson));
    this.autoCheckProgressText = record.summary.length > 0 ? record.summary : this.getAutoCheckRecordStatusText(record.status);
    const task: BackgroundTask | undefined = this.backgroundTaskManager.getTask(record.taskId);
    if (task !== undefined && (task.status === TaskStatus.PENDING || task.status === TaskStatus.RUNNING)) {
      this.applyAutoCheckTaskSnapshot(task);
      this.startAutoCheckRecordRefresh(record.taskId);
      return;
    }
    this.autoCheckRunning = false;
    this.autoCheckReportReady = true;
    this.stopAutoCheckRecordRefresh();
    this.stopAutoCheckProgressTimer();
  }

  private applyAutoCheckTaskSnapshot(task: BackgroundTask): void {
    this.autoCheckBackgroundTaskId = task.id;
    this.autoCheckRunning = task.status === TaskStatus.PENDING || task.status === TaskStatus.RUNNING;
    this.autoCheckReportReady = !this.autoCheckRunning;
    this.autoCheckProgressText = task.progress.message.length > 0 ? task.progress.message : this.autoCheckProgressText;
    if (this.autoCheckRunning) {
      this.startAutoCheckProgressTimer();
    } else {
      this.stopAutoCheckProgressTimer();
    }
  }

  private startAutoCheckRecordRefresh(taskId: string): void {
    this.stopAutoCheckRecordRefresh();
    this.autoCheckRecordRefreshTimerId = setInterval((): void => {
      void this.refreshAutoCheckRecord(taskId);
    }, 1000);
  }

  private stopAutoCheckRecordRefresh(): void {
    if (this.autoCheckRecordRefreshTimerId >= 0) {
      clearInterval(this.autoCheckRecordRefreshTimerId);
      this.autoCheckRecordRefreshTimerId = -1;
    }
  }

  private async refreshAutoCheckRecord(taskId: string): Promise<void> {
    const record: SourceAutoCheckRecord | null = await sourceAutoCheckHistoryService.getRecord(taskId);
    if (record !== null) {
      this.autoCheckSiteReports = this.cloneAutoCheckSiteReports(SafeUtils.parseArr<SourceAutoCheckSiteReport[]>(record.reportJson));
      this.autoCheckRecommendedSiteBaseUrl = record.recommendedSiteBaseUrl;
      if (record.summary.length > 0) {
        this.autoCheckProgressText = record.summary;
      }
      if (record.status !== 'RUNNING') {
        this.applyAutoCheckRecord(record);
        return;
      }
    }
    const task: BackgroundTask | undefined = this.backgroundTaskManager.getTask(taskId);
    if (task !== undefined) {
      this.applyAutoCheckTaskSnapshot(task);
    } else if (record !== null) {
      this.autoCheckRunning = false;
      this.autoCheckReportReady = true;
      this.stopAutoCheckRecordRefresh();
    }
  }

  private getAutoCheckRecordStatusText(status: SourceAutoCheckRecordStatus): string {
    if (status === 'COMPLETED') {
      return '巡检已完成';
    }
    if (status === 'FAILED') {
      return '巡检失败';
    }
    if (status === 'CANCELLED') {
      return '巡检已取消';
    }
    return '巡检进行中';
  }

  private getConfigAutoCheckTasks(): SourceAutoCheckTaskOption[] {
    const tasks: SourceAutoCheckTaskOption[] = [];
    if (this.draft === null) {
      return tasks;
    }
    const rawConfig: SourceEditorSiteRawConfig = SafeUtils.parseObj<SourceEditorSiteRawConfig>(this.draft.configJson);
    const workflows: Object | undefined = rawConfig.workflows;
    if (workflows === undefined) {
      return tasks;
    }
    const keys: string[] = Object.keys(workflows);
    for (let index = 0; index < keys.length; index += 1) {
      const workflowKey: string = keys[index];
      const actions: SourceEditorAutoRawAction[] = this.getAutoRawWorkflowActions(workflows, workflowKey);
      if (actions.length <= 0) {
        continue;
      }
      const task: SourceAutoCheckTaskOption = {
        workflowKey: workflowKey,
        taskType: this.inferAutoCheckTaskType(workflowKey),
        label: this.getAutoCheckWorkflowLabel(workflowKey),
        useInspectorStep: false
      };
      tasks.push(task);
    }
    return tasks;
  }

  private getAutoCheckTasksByWorkflowKeys(workflowKeys: string[]): SourceAutoCheckTaskOption[] {
    const allTasks: SourceAutoCheckTaskOption[] = this.getConfigAutoCheckTasks();
    const selectedTasks: SourceAutoCheckTaskOption[] = [];
    for (let keyIndex = 0; keyIndex < workflowKeys.length; keyIndex += 1) {
      const workflowKey: string = workflowKeys[keyIndex];
      for (let taskIndex = 0; taskIndex < allTasks.length; taskIndex += 1) {
        const task: SourceAutoCheckTaskOption = allTasks[taskIndex];
        if (task.workflowKey === workflowKey) {
          selectedTasks.push(task);
          break;
        }
      }
    }
    return selectedTasks;
  }

  private resolveDefaultAutoCheckSelection(tasks: SourceAutoCheckTaskOption[]): string[] {
    const selectedKeys: string[] = [];
    for (let index = 0; index < AUTO_CHECK_EXTERNAL_WORKFLOW_KEYS.length; index += 1) {
      const workflowKey: string = AUTO_CHECK_EXTERNAL_WORKFLOW_KEYS[index];
      if (this.hasAutoCheckWorkflowTask(tasks, workflowKey)) {
        selectedKeys.push(workflowKey);
      }
    }
    if (selectedKeys.length > 0) {
      return selectedKeys;
    }
    for (let index = 0; index < tasks.length; index += 1) {
      selectedKeys.push(tasks[index].workflowKey);
    }
    return selectedKeys;
  }

  private hasAutoCheckWorkflowTask(tasks: SourceAutoCheckTaskOption[], workflowKey: string): boolean {
    for (let index = 0; index < tasks.length; index += 1) {
      if (tasks[index].workflowKey === workflowKey) {
        return true;
      }
    }
    return false;
  }

  private isAutoCheckWorkflowSelected(workflowKey: string): boolean {
    for (let index = 0; index < this.selectedAutoCheckWorkflowKeys.length; index += 1) {
      if (this.selectedAutoCheckWorkflowKeys[index] === workflowKey) {
        return true;
      }
    }
    return false;
  }

  private toggleAutoCheckWorkflowSelection(workflowKey: string): void {
    const nextKeys: string[] = [];
    let removed: boolean = false;
    for (let index = 0; index < this.selectedAutoCheckWorkflowKeys.length; index += 1) {
      const selectedKey: string = this.selectedAutoCheckWorkflowKeys[index];
      if (selectedKey === workflowKey) {
        removed = true;
        continue;
      }
      nextKeys.push(selectedKey);
    }
    if (!removed) {
      nextKeys.push(workflowKey);
    }
    this.selectedAutoCheckWorkflowKeys = nextKeys;
  }

  private selectAllAutoCheckWorkflows(): void {
    const selectedKeys: string[] = [];
    for (let index = 0; index < this.autoCheckScopeOptions.length; index += 1) {
      selectedKeys.push(this.autoCheckScopeOptions[index].workflowKey);
    }
    this.selectedAutoCheckWorkflowKeys = selectedKeys;
  }

  private clearAutoCheckWorkflowSelection(): void {
    this.selectedAutoCheckWorkflowKeys = [];
  }

  private getSelectedAutoCheckTasks(): SourceAutoCheckTaskOption[] {
    const selectedTasks: SourceAutoCheckTaskOption[] = [];
    for (let optionIndex = 0; optionIndex < this.autoCheckScopeOptions.length; optionIndex += 1) {
      const option: SourceAutoCheckTaskOption = this.autoCheckScopeOptions[optionIndex];
      if (this.isAutoCheckWorkflowSelected(option.workflowKey)) {
        selectedTasks.push(option);
      }
    }
    return selectedTasks;
  }

  private getAutoRawWorkflowActions(workflows: Object, workflowKey: string): SourceEditorAutoRawAction[] {
    const workflowMap: SourceEditorWorkflowMap = workflows as SourceEditorWorkflowMap;
    const workflow: Object | undefined = workflowMap[workflowKey];
    if (workflow === undefined) {
      return [];
    }
    if (Array.isArray(workflow)) {
      return workflow as SourceEditorAutoRawAction[];
    }
    const workflowObject: SourceEditorAutoRawWorkflowObject = workflow as SourceEditorAutoRawWorkflowObject;
    if (workflowObject.actions !== undefined && Array.isArray(workflowObject.actions)) {
      return workflowObject.actions;
    }
    return [];
  }

  private inferAutoCheckTaskType(workflowKey: string): SourceEditorTaskType {
    if (workflowKey === 'getMangaDetail' || workflowKey === 'getBookDetail' || workflowKey.indexOf('Detail') >= 0) {
      return SourceEditorTaskType.DETAIL;
    }
    if (workflowKey === 'getChapterList' || workflowKey.indexOf('Chapter') >= 0) {
      return SourceEditorTaskType.CHAPTERS;
    }
    if (workflowKey === 'getPageList' || workflowKey.indexOf('Page') >= 0) {
      return SourceEditorTaskType.PAGES;
    }
    return SourceEditorTaskType.SEARCH;
  }

  private getAutoCheckWorkflowLabel(workflowKey: string): string {
    if (workflowKey === 'popular') {
      return '热门';
    }
    if (workflowKey === 'latest') {
      return '最新';
    }
    if (workflowKey === 'search') {
      return '搜索';
    }
    if (workflowKey === 'filter') {
      return '筛选';
    }
    if (workflowKey === 'getMangaDetail' || workflowKey === 'getBookDetail') {
      return '详情';
    }
    if (workflowKey === 'getChapterList') {
      return '章节';
    }
    if (workflowKey === 'getPageList') {
      return '图片';
    }
    if (workflowKey === 'directSearch') {
      return '直达';
    }
    if (workflowKey === 'initialize') {
      return '初始化';
    }
    if (workflowKey === 'login') {
      return '登录';
    }
    return workflowKey;
  }

  private getAutoCheckSites(): SourceEditorSiteOption[] {
    if (this.siteOptions.length > 0) {
      return this.siteOptions.slice();
    }
    const fallbackUrl: string = this.draft !== null && this.draft.testUrl.length > 0 ? this.draft.testUrl : this.testUrl;
    const baseUrl: string = this.normalizeSiteBaseUrl(this.resolveBaseUrlFromTestUrl(fallbackUrl));
    if (baseUrl.length <= 0) {
      return [];
    }
    const option: SourceEditorSiteOption = {
      id: 'fallback_0',
      label: this.resolveSiteLabel('当前站点', baseUrl),
      baseUrl: baseUrl
    };
    const options: SourceEditorSiteOption[] = [];
    options.push(option);
    return options;
  }

  private createAutoCheckSiteReport(site: SourceEditorSiteOption, totalCount: number): SourceAutoCheckSiteReport {
    const workflowResults: SourceAutoCheckWorkflowResult[] = [];
    const report: SourceAutoCheckSiteReport = {
      siteId: site.id,
      siteLabel: site.label,
      siteBaseUrl: site.baseUrl,
      score: 0,
      successCount: 0,
      totalCount: totalCount,
      durationMs: 0,
      summary: '等待检查',
      recommended: false,
      workflowResults: workflowResults
    };
    return report;
  }

  private cloneAutoCheckWorkflowResult(result: SourceAutoCheckWorkflowResult): SourceAutoCheckWorkflowResult {
    const clonedResult: SourceAutoCheckWorkflowResult = {
      siteId: result.siteId,
      siteLabel: result.siteLabel,
      siteBaseUrl: result.siteBaseUrl,
      workflowKey: result.workflowKey,
      taskLabel: result.taskLabel,
      status: result.status,
      score: result.score,
      attemptCount: result.attemptCount,
      durationMs: result.durationMs,
      targetUrl: result.targetUrl,
      summary: result.summary,
      detail: result.detail,
      errorMessage: result.errorMessage,
      selectorCount: result.selectorCount,
      scriptCount: result.scriptCount,
      sampleTitle: result.sampleTitle,
      sampleUrl: result.sampleUrl
    };
    return clonedResult;
  }

  private cloneAutoCheckSiteReport(report: SourceAutoCheckSiteReport): SourceAutoCheckSiteReport {
    const workflowResults: SourceAutoCheckWorkflowResult[] = [];
    for (let index = 0; index < report.workflowResults.length; index += 1) {
      workflowResults.push(this.cloneAutoCheckWorkflowResult(report.workflowResults[index]));
    }
    const clonedReport: SourceAutoCheckSiteReport = {
      siteId: report.siteId,
      siteLabel: report.siteLabel,
      siteBaseUrl: report.siteBaseUrl,
      score: report.score,
      successCount: report.successCount,
      totalCount: report.totalCount,
      durationMs: report.durationMs,
      summary: report.summary,
      recommended: report.recommended,
      workflowResults: workflowResults
    };
    return clonedReport;
  }

  private cloneAutoCheckSiteReports(reports: SourceAutoCheckSiteReport[]): SourceAutoCheckSiteReport[] {
    const clonedReports: SourceAutoCheckSiteReport[] = [];
    for (let index = 0; index < reports.length; index += 1) {
      clonedReports.push(this.cloneAutoCheckSiteReport(reports[index]));
    }
    return clonedReports;
  }

  private async runAutoCheckWorkflow(
    token: number,
    site: SourceEditorSiteOption,
    task: SourceAutoCheckTaskOption,
    chainedSampleUrl: string,
    cancelSignal: TaskCancelSignal
  ): Promise<SourceAutoCheckWorkflowResult> {
    const startedAt: number = Date.now();
    let step: SourceEditorWorkflowGuideStep | null = this.resolveAutoCheckWorkflowStep(site, task);
    if (step === null || !step.workflowExists) {
      return this.createAutoCheckWorkflowResult(site, task, SourceEditorWorkflowPreviewStatus.ERROR, 0, 0,
        Date.now() - startedAt, site.baseUrl, '工作流不可用', '', '当前图源未配置该工作流');
    }

    let bestPreview: SourceEditorWorkflowPreview = this.createAutoCheckPreview(SourceEditorWorkflowPreviewStatus.EMPTY, '未识别到目标内容', '', '');
    let targetUrl: string = '';
    let attemptCount: number = 0;
    for (let attempt = 0; attempt <= AUTO_CHECK_MAX_RETRIES; attempt += 1) {
      if (!this.isAutoCheckActive(token, cancelSignal)) {
        break;
      }
      attemptCount = attempt + 1;
      targetUrl = this.resolveAutoWorkflowTargetUrl(site, step, chainedSampleUrl);
      if (task.useInspectorStep) {
        sourceEditorInspectorStateManager.updateCurrentTargetUrl(targetUrl);
      }
      this.loadAutoCheckTarget(targetUrl, site);
      await this.waitAutoCheck(AUTO_CHECK_PAGE_SETTLE_MS + attempt * 700, cancelSignal);
      if (!this.isAutoCheckActive(token, cancelSignal)) {
        break;
      }
      step = task.useInspectorStep ? sourceEditorInspectorStateManager.getSnapshot().currentStep :
        this.resolveAutoCheckWorkflowStep(site, task);
      if (step === null) {
        break;
      }
      const preview: SourceEditorWorkflowPreview = await this.runAutoCheckPreviewScript(
        step,
        AUTO_CHECK_SCRIPT_TIMEOUT_MS,
        cancelSignal
      );
      bestPreview = this.pickBetterAutoCheckPreview(bestPreview, preview);
      if (preview.status === SourceEditorWorkflowPreviewStatus.OK) {
        break;
      }
    }

    const score: number = this.scoreAutoCheckPreview(bestPreview);
    return this.createAutoCheckWorkflowResult(site, task, bestPreview.status, score, attemptCount,
      Date.now() - startedAt, targetUrl, bestPreview.summary, bestPreview.detail, bestPreview.errorMessage,
      bestPreview.selectorCount, bestPreview.scriptCount, bestPreview.sampleTitle, bestPreview.sampleUrl);
  }

  private resolveAutoCheckWorkflowStep(
    site: SourceEditorSiteOption,
    task: SourceAutoCheckTaskOption
  ): SourceEditorWorkflowGuideStep | null {
    if (task.useInspectorStep) {
      sourceEditorInspectorStateManager.selectWorkflow(task.taskType);
      this.taskType = task.taskType;
      return sourceEditorInspectorStateManager.getSnapshot().currentStep;
    }
    return this.buildAutoCheckRawWorkflowStep(site, task);
  }

  private buildAutoCheckRawWorkflowStep(
    site: SourceEditorSiteOption,
    task: SourceAutoCheckTaskOption
  ): SourceEditorWorkflowGuideStep | null {
    if (this.draft === null) {
      return null;
    }
    const rawConfig: SourceEditorSiteRawConfig = SafeUtils.parseObj<SourceEditorSiteRawConfig>(this.draft.configJson);
    if (rawConfig.workflows === undefined) {
      return null;
    }
    const actions: SourceEditorAutoRawAction[] = this.getAutoRawWorkflowActions(rawConfig.workflows, task.workflowKey);
    if (actions.length <= 0) {
      return null;
    }
    const step: SourceEditorWorkflowGuideStep = {
      taskType: task.taskType,
      label: task.label,
      description: task.label,
      expectedDomLabel: task.label,
      selectionInstruction: '',
      targetUrl: this.resolveAutoRawWorkflowTargetUrl(actions, site.baseUrl),
      workflowExists: true,
      actionCount: actions.length,
      waitSelector: this.findAutoRawSelector(actions, 'wait'),
      extractSelector: this.findAutoRawSelector(actions, 'extract'),
      scriptCode: this.findAutoRawScriptCode(actions),
      completed: false,
      preview: createEmptySourceEditorWorkflowPreview(),
      selectionAssessment: createEmptySourceEditorSelectionAssessment()
    };
    return step;
  }

  private findAutoRawSelector(actions: SourceEditorAutoRawAction[], actionType: string): string {
    for (let index = 0; index < actions.length; index += 1) {
      const action: SourceEditorAutoRawAction = actions[index];
      if (action.type === actionType && action.selector !== undefined) {
        return action.selector;
      }
    }
    return '';
  }

  private findAutoRawScriptCode(actions: SourceEditorAutoRawAction[]): string {
    for (let index = actions.length - 1; index >= 0; index -= 1) {
      const action: SourceEditorAutoRawAction = actions[index];
      if (action.type === 'script' && action.code !== undefined) {
        return action.code;
      }
    }
    return '';
  }

  private resolveAutoRawWorkflowTargetUrl(actions: SourceEditorAutoRawAction[], baseUrl: string): string {
    for (let index = 0; index < actions.length; index += 1) {
      const action: SourceEditorAutoRawAction = actions[index];
      if (action.type === 'navigate' && action.url !== undefined) {
        return this.resolveAutoTemplateUrl(action.url, baseUrl);
      }
    }
    return baseUrl;
  }

  private resolveAutoTemplateUrl(url: string, baseUrl: string): string {
    let output: string = url;
    output = output.split('{{baseUrl}}').join(baseUrl);
    output = output.split('{{page}}').join('1');
    output = output.split('{{searchKeyword}}').join('test');
    output = output.split('{{query}}').join('test');
    output = output.split('{{mangaId}}').join('');
    output = output.split('{{chapterId}}').join('');
    output = output.split('{{scriptResult}}').join('');
    if (output.length <= 0 || output.indexOf('{{') >= 0) {
      return baseUrl;
    }
    if (output.startsWith('/')) {
      return `${baseUrl}${output}`;
    }
    return output;
  }

  private loadAutoCheckTarget(targetUrl: string, site: SourceEditorSiteOption): void {
    this.clearPendingLoadTimer();
    this.clearPreviewTimer();
    this.autoCheckActiveTargetUrl = targetUrl;
    this.autoCheckActiveSiteId = site.id;
    this.autoCheckActiveSiteBaseUrl = site.baseUrl;
    this.lastLoadedGuideUrl = targetUrl;
    this.lastCommittedLoadUrl = targetUrl;
    this.mainFrameLoaded = false;
    try {
      this.webController.loadUrl(targetUrl);
    } catch (error) {
      logger.warn(TAG, `自动检查加载目标失败: ${String(error)}`);
    }
  }

  private resolveAutoWorkflowTargetUrl(
    site: SourceEditorSiteOption,
    step: SourceEditorWorkflowGuideStep,
    chainedSampleUrl: string
  ): string {
    if (step.taskType !== SourceEditorTaskType.SEARCH && chainedSampleUrl.length > 0) {
      return this.replaceKnownSiteBaseUrl(chainedSampleUrl, site.baseUrl);
    }
    const stepUrl: string = step.targetUrl.trim();
    if (stepUrl.length <= 0 || stepUrl.indexOf('{{') >= 0 || stepUrl === 'about:blank') {
      return site.baseUrl;
    }
    return this.replaceKnownSiteBaseUrl(stepUrl, site.baseUrl);
  }

  private replaceKnownSiteBaseUrl(url: string, nextBaseUrl: string): string {
    const normalizedNextBaseUrl: string = this.normalizeSiteBaseUrl(nextBaseUrl);
    if (normalizedNextBaseUrl.length <= 0) {
      return url;
    }
    const trimmedUrl: string = url.trim();
    const currentBaseUrl: string = this.normalizeSiteBaseUrl(this.resolveBaseUrlFromTestUrl(trimmedUrl));
    if (currentBaseUrl.length <= 0) {
      return normalizedNextBaseUrl;
    }
    if (!this.isKnownSiteBaseUrl(currentBaseUrl)) {
      return trimmedUrl;
    }
    if (trimmedUrl.length <= currentBaseUrl.length) {
      return normalizedNextBaseUrl;
    }
    return `${normalizedNextBaseUrl}${trimmedUrl.substring(currentBaseUrl.length)}`;
  }

  private runAutoCheckPreviewScript(
    step: SourceEditorWorkflowGuideStep,
    timeoutMs: number,
    cancelSignal: TaskCancelSignal
  ): Promise<SourceEditorWorkflowPreview> {
    return new Promise<SourceEditorWorkflowPreview>((resolve: (value: SourceEditorWorkflowPreview) => void): void => {
      let settled: boolean = false;
      let timeoutTimerId: number = -1;
      let cancelTimerId: number = -1;
      const clearTimers = (): void => {
        if (timeoutTimerId >= 0) {
          clearTimeout(timeoutTimerId);
          timeoutTimerId = -1;
        }
        if (cancelTimerId >= 0) {
          clearInterval(cancelTimerId);
          cancelTimerId = -1;
        }
      };
      timeoutTimerId = setTimeout((): void => {
        if (settled) {
          return;
        }
        settled = true;
        clearTimers();
        resolve(this.createAutoCheckPreview(SourceEditorWorkflowPreviewStatus.ERROR, '检查超时', '', '脚本执行超时'));
      }, timeoutMs);
      cancelTimerId = setInterval((): void => {
        if (settled || !cancelSignal.isCancelled) {
          return;
        }
        settled = true;
        clearTimers();
        resolve(this.createAutoCheckPreview(SourceEditorWorkflowPreviewStatus.ERROR, '检查已停止', '', '自动检查已取消'));
      }, 160);
      try {
        this.webController.runJavaScript(this.buildWorkflowPreviewScript(step), (error: BusinessError | null, result: string): void => {
          if (settled) {
            return;
          }
          settled = true;
          clearTimers();
          if (error) {
            resolve(this.createAutoCheckPreview(SourceEditorWorkflowPreviewStatus.ERROR, '脚本运行失败', '', error.message));
            return;
          }
          resolve(this.parseWorkflowPreview(result));
        });
      } catch (error) {
        if (settled) {
          return;
        }
        settled = true;
        clearTimers();
        resolve(this.createAutoCheckPreview(SourceEditorWorkflowPreviewStatus.ERROR, '脚本异常', '', String(error)));
      }
    });
  }

  private waitAutoCheck(durationMs: number, cancelSignal: TaskCancelSignal): Promise<void> {
    return new Promise<void>((resolve: () => void): void => {
      let settled: boolean = false;
      let waitTimerId: number = -1;
      let cancelTimerId: number = -1;
      const finish = (): void => {
        if (settled) {
          return;
        }
        settled = true;
        if (waitTimerId >= 0) {
          clearTimeout(waitTimerId);
          waitTimerId = -1;
        }
        if (cancelTimerId >= 0) {
          clearInterval(cancelTimerId);
          cancelTimerId = -1;
        }
        resolve();
      };
      waitTimerId = setTimeout((): void => {
        finish();
      }, durationMs);
      cancelTimerId = setInterval((): void => {
        if (cancelSignal.isCancelled) {
          finish();
        }
      }, 160);
    });
  }

  private createAutoCheckPreview(
    status: SourceEditorWorkflowPreviewStatus,
    summary: string,
    detail: string,
    errorMessage: string
  ): SourceEditorWorkflowPreview {
    const preview: SourceEditorWorkflowPreview = {
      status: status,
      summary: summary,
      detail: detail,
      selectorCount: 0,
      scriptCount: 0,
      sampleTitle: '',
      sampleUrl: '',
      sampleCover: '',
      errorMessage: errorMessage
    };
    return preview;
  }

  private pickBetterAutoCheckPreview(
    current: SourceEditorWorkflowPreview,
    candidate: SourceEditorWorkflowPreview
  ): SourceEditorWorkflowPreview {
    const currentScore: number = this.scoreAutoCheckPreview(current);
    const candidateScore: number = this.scoreAutoCheckPreview(candidate);
    return candidateScore >= currentScore ? candidate : current;
  }

  private scoreAutoCheckPreview(preview: SourceEditorWorkflowPreview): number {
    if (preview.status === SourceEditorWorkflowPreviewStatus.OK) {
      const evidenceScore: number = Math.min(30, preview.selectorCount * 4 + preview.scriptCount * 6);
      return Math.min(100, 70 + evidenceScore);
    }
    if (preview.status === SourceEditorWorkflowPreviewStatus.EMPTY) {
      return 25;
    }
    if (preview.status === SourceEditorWorkflowPreviewStatus.WAITING) {
      return 18;
    }
    return 0;
  }

  private createAutoCheckWorkflowResult(
    site: SourceEditorSiteOption,
    task: SourceAutoCheckTaskOption,
    status: SourceEditorWorkflowPreviewStatus,
    score: number,
    attemptCount: number,
    durationMs: number,
    targetUrl: string,
    summary: string,
    detail: string,
    errorMessage: string,
    selectorCount: number = 0,
    scriptCount: number = 0,
    sampleTitle: string = '',
    sampleUrl: string = ''
  ): SourceAutoCheckWorkflowResult {
    const result: SourceAutoCheckWorkflowResult = {
      siteId: site.id,
      siteLabel: site.label,
      siteBaseUrl: site.baseUrl,
      workflowKey: task.workflowKey,
      taskLabel: task.label,
      status: status,
      score: score,
      attemptCount: attemptCount,
      durationMs: durationMs,
      targetUrl: targetUrl,
      summary: summary,
      detail: detail,
      errorMessage: errorMessage,
      selectorCount: selectorCount,
      scriptCount: scriptCount,
      sampleTitle: sampleTitle,
      sampleUrl: sampleUrl
    };
    return result;
  }

  private updateAutoCheckSiteReport(report: SourceAutoCheckSiteReport, durationMs: number): void {
    let scoreTotal: number = 0;
    let successCount: number = 0;
    for (let index = 0; index < report.workflowResults.length; index += 1) {
      const result: SourceAutoCheckWorkflowResult = report.workflowResults[index];
      scoreTotal += result.score;
      if (result.status === SourceEditorWorkflowPreviewStatus.OK) {
        successCount += 1;
      }
    }
    report.successCount = successCount;
    report.durationMs = durationMs;
    report.score = report.workflowResults.length > 0 ? Math.round(scoreTotal / report.workflowResults.length) : 0;
    report.summary = `${successCount}/${report.totalCount} 通过 · ${report.score}分`;
  }

  private getAutoCheckSiteProgressPercent(report: SourceAutoCheckSiteReport): number {
    if (report.totalCount <= 0) {
      return 0;
    }
    let progressCount: number = report.workflowResults.length;
    if (this.autoCheckRunning && this.autoCheckActiveSiteId === report.siteId && progressCount < report.totalCount) {
      const currentTick: number = this.autoCheckProgressTick > 0 ? this.autoCheckProgressTick : Date.now();
      const startedAt: number = this.autoCheckActiveWorkflowStartedAt > 0 ? this.autoCheckActiveWorkflowStartedAt : currentTick;
      const elapsedMs: number = Math.max(0, currentTick - startedAt);
      const activeWorkflowProgress: number = Math.min(0.92, elapsedMs / AUTO_CHECK_WORKFLOW_PROGRESS_ESTIMATE_MS);
      progressCount += Math.max(0.08, activeWorkflowProgress);
    }
    const percent: number = Math.floor((progressCount / report.totalCount) * 100);
    return Math.max(0, Math.min(100, percent));
  }

  private getAutoCheckSiteReportHeight(report: SourceAutoCheckSiteReport): number {
    if (report.workflowResults.length <= 0) {
      return 54;
    }
    const contentHeight: number = 42 + report.workflowResults.length * 24;
    return Math.max(72, contentHeight);
  }

  private getAutoCheckSiteToneColor(report: SourceAutoCheckSiteReport): ResourceColor {
    if (report.workflowResults.length <= 0) {
      if (this.autoCheckRunning && this.autoCheckActiveSiteId === report.siteId) {
        return ThemeAwareHelper.getTestManagementThemedColor('accent_primary', this.themeState.currentTheme);
      }
      return ThemeAwareHelper.getTestManagementThemedColor('text_secondary', this.themeState.currentTheme);
    }
    if (report.workflowResults.length < report.totalCount) {
      return ThemeAwareHelper.getTestManagementThemedColor('accent_primary', this.themeState.currentTheme);
    }
    if (report.successCount === report.totalCount && report.totalCount > 0) {
      return AppColors.success;
    }
    if (report.successCount <= 0) {
      return AppColors.error;
    }
    return AppColors.warning;
  }

  private getAutoCheckWorkflowToneColor(result: SourceAutoCheckWorkflowResult): ResourceColor {
    if (result.status === SourceEditorWorkflowPreviewStatus.OK) {
      return AppColors.success;
    }
    if (result.status === SourceEditorWorkflowPreviewStatus.ERROR) {
      return AppColors.error;
    }
    if (result.status === SourceEditorWorkflowPreviewStatus.EMPTY) {
      return AppColors.warning;
    }
    if (result.status === SourceEditorWorkflowPreviewStatus.RUNNING) {
      return ThemeAwareHelper.getTestManagementThemedColor('accent_primary', this.themeState.currentTheme);
    }
    return ThemeAwareHelper.getTestManagementThemedColor('text_secondary', this.themeState.currentTheme);
  }

  private getAutoCheckSiteSummaryText(report: SourceAutoCheckSiteReport): string {
    if (report.workflowResults.length > 0) {
      return report.summary;
    }
    if (this.autoCheckRunning && this.autoCheckActiveSiteId === report.siteId) {
      return '检查中';
    }
    return '等待检查';
  }

  private getAutoCheckSelectedSiteBaseUrl(): string {
    if (this.autoCheckRunning && this.autoCheckActiveSiteBaseUrl.length > 0) {
      return this.autoCheckActiveSiteBaseUrl;
    }
    return this.selectedSiteBaseUrl;
  }

  private getToolbarUrlText(): string {
    if (this.autoCheckRunning && this.autoCheckActiveTargetUrl.length > 0) {
      return this.autoCheckActiveTargetUrl;
    }
    return this.testUrl;
  }

  private getAutoCheckPanelReports(): SourceAutoCheckSiteReport[] {
    if (!this.autoCheckReportReady || this.autoCheckRunning || this.autoCheckRecommendedSiteBaseUrl.length <= 0) {
      return this.autoCheckSiteReports;
    }
    const reports: SourceAutoCheckSiteReport[] = [];
    const recommendedBaseUrl: string = this.normalizeSiteBaseUrl(this.autoCheckRecommendedSiteBaseUrl);
    for (let index = 0; index < this.autoCheckSiteReports.length; index += 1) {
      const report: SourceAutoCheckSiteReport = this.autoCheckSiteReports[index];
      if (report.recommended ||
        this.normalizeSiteBaseUrl(report.siteBaseUrl) === recommendedBaseUrl) {
        continue;
      }
      reports.push(report);
    }
    return reports;
  }

  private shouldShowAutoCheckRecommendationPreview(): boolean {
    return this.autoCheckReportReady && !this.autoCheckRunning && this.autoCheckRecommendedSiteBaseUrl.length > 0;
  }

  private getRecommendedAutoCheckSiteReport(): SourceAutoCheckSiteReport | null {
    const recommendedBaseUrl: string = this.normalizeSiteBaseUrl(this.autoCheckRecommendedSiteBaseUrl);
    for (let index = 0; index < this.autoCheckSiteReports.length; index += 1) {
      const report: SourceAutoCheckSiteReport = this.autoCheckSiteReports[index];
      if (report.recommended || this.normalizeSiteBaseUrl(report.siteBaseUrl) === recommendedBaseUrl) {
        return report;
      }
    }
    return null;
  }

  private getRecommendedAutoCheckSiteReportOrEmpty(): SourceAutoCheckSiteReport {
    const report: SourceAutoCheckSiteReport | null = this.getRecommendedAutoCheckSiteReport();
    if (report !== null) {
      return report;
    }
    const workflowResults: SourceAutoCheckWorkflowResult[] = [];
    const emptyReport: SourceAutoCheckSiteReport = {
      siteId: 'recommended_empty',
      siteLabel: this.resolveSiteLabel('推荐站点', this.autoCheckRecommendedSiteBaseUrl),
      siteBaseUrl: this.autoCheckRecommendedSiteBaseUrl,
      score: 0,
      successCount: 0,
      totalCount: 0,
      durationMs: 0,
      summary: '暂无详细结果',
      recommended: true,
      workflowResults: workflowResults
    };
    return emptyReport;
  }

  private finishAutoCheckReports(reports: SourceAutoCheckSiteReport[], durationMs: number): string {
    const recommendedIndex: number = this.findRecommendedSiteReportIndex(reports);
    for (let index = 0; index < reports.length; index += 1) {
      reports[index].recommended = index === recommendedIndex;
    }
    this.autoCheckRunning = false;
    this.autoCheckReportReady = true;
    this.autoCheckSiteReports = this.cloneAutoCheckSiteReports(reports);
    this.autoCheckRecommendedSiteBaseUrl = recommendedIndex >= 0 ? reports[recommendedIndex].siteBaseUrl : '';
    this.autoCheckActiveSiteId = '';
    this.autoCheckActiveSiteBaseUrl = '';
    this.autoCheckActiveTargetUrl = '';
    this.autoCheckActiveWorkflowStartedAt = 0;
    this.stopAutoCheckProgressTimer();
    this.autoCheckProgressText = recommendedIndex >= 0 ?
      `检查完成，用时 ${Math.ceil(durationMs / 1000)} 秒，推荐 ${reports[recommendedIndex].siteLabel}` :
      `检查完成，用时 ${Math.ceil(durationMs / 1000)} 秒`;
    if (this.autoCheckRecommendedSiteBaseUrl.length > 0) {
      this.selectedSiteBaseUrl = this.autoCheckRecommendedSiteBaseUrl;
    }
    return this.autoCheckProgressText;
  }

  private findRecommendedSiteReportIndex(reports: SourceAutoCheckSiteReport[]): number {
    let bestIndex: number = -1;
    for (let index = 0; index < reports.length; index += 1) {
      const report: SourceAutoCheckSiteReport = reports[index];
      if (bestIndex < 0) {
        bestIndex = index;
        continue;
      }
      const bestReport: SourceAutoCheckSiteReport = reports[bestIndex];
      if (report.score > bestReport.score ||
        (report.score === bestReport.score && report.successCount > bestReport.successCount) ||
        (report.score === bestReport.score && report.successCount === bestReport.successCount &&
          report.durationMs < bestReport.durationMs)) {
        bestIndex = index;
      }
    }
    return bestIndex;
  }

  private applyAutoCheckRecommendation(): void {
    if (this.draft === null || this.autoCheckRecommendedSiteBaseUrl.length <= 0) {
      this.getUIContext().getPromptAction().showToast({ message: '暂无推荐站点' });
      return;
    }
    const rawConfig: SourceEditorSiteRawConfig = SafeUtils.parseObj<SourceEditorSiteRawConfig>(this.draft.configJson);
    if (rawConfig.metadata === undefined) {
      const metadata: SourceEditorSiteMetadata = {
        baseUrl: this.autoCheckRecommendedSiteBaseUrl
      };
      rawConfig.metadata = metadata;
    }
    if (rawConfig.settings !== undefined && rawConfig.settings.domain !== undefined &&
      this.isSiteSettingOption(rawConfig.settings.domain, this.autoCheckRecommendedSiteBaseUrl)) {
      rawConfig.settings.domain.default = this.autoCheckRecommendedSiteBaseUrl;
    } else if (rawConfig.metadata !== undefined) {
      rawConfig.metadata.baseUrl = this.autoCheckRecommendedSiteBaseUrl;
    }
    const nextConfigJson: string = JSON.stringify(rawConfig, null, 2);
    this.draft.configJson = nextConfigJson;
    this.draft.testUrl = this.autoCheckRecommendedSiteBaseUrl;
    this.draft.updateTime = Date.now();
    this.configPreview = nextConfigJson;
    this.testUrl = this.autoCheckRecommendedSiteBaseUrl;
    this.selectedSiteBaseUrl = this.autoCheckRecommendedSiteBaseUrl;
    this.refreshSiteOptions(nextConfigJson, this.autoCheckRecommendedSiteBaseUrl);
    this.saveMessage = '已把推荐站点应用到当前草稿，请保存后生效';
    this.refreshFloatingInspectorState();
    this.getUIContext().getPromptAction().showToast({ message: '已应用推荐站点到草稿' });
  }

  private isSiteSettingOption(setting: SourceEditorSiteSetting, baseUrl: string): boolean {
    const normalizedBaseUrl: string = this.normalizeSiteBaseUrl(baseUrl);
    if (setting.default !== undefined && this.normalizeSiteBaseUrl(setting.default) === normalizedBaseUrl) {
      return true;
    }
    const options: SourceEditorSiteSettingOption[] | undefined = setting.options;
    if (options === undefined) {
      return false;
    }
    for (let index = 0; index < options.length; index += 1) {
      const option: SourceEditorSiteSettingOption = options[index];
      if (option.value !== undefined && this.normalizeSiteBaseUrl(option.value) === normalizedBaseUrl) {
        return true;
      }
    }
    return false;
  }

  private getTaskOptions(): SourceEditorTaskOption[] {
    const options: SourceEditorTaskOption[] = [];
    options.push({ taskType: SourceEditorTaskType.SEARCH, label: '搜索' });
    options.push({ taskType: SourceEditorTaskType.DETAIL, label: '详情' });
    options.push({ taskType: SourceEditorTaskType.CHAPTERS, label: '章节' });
    options.push({ taskType: SourceEditorTaskType.PAGES, label: '图片' });
    return options;
  }

  private getTitleBarActions(): SettingsImmersiveTitleActionItem[] {
    return [
      {
        id: 'auto_check',
        symbol: $r('sys.symbol.waveform_path_ecg_magnifyingglass'),
        label: '自动检查',
        onClick: () => {
          void this.startAutoCheckMode();
        },
        enabled: !this.autoCheckRunning
      },
      {
        id: 'inspector',
        symbol: $r('sys.symbol.arrow_up_left_and_arrow_down_right'),
        label: '检查器',
        onClick: () => {
          void this.toggleFloatingInspector();
        },
        enabled: true
      }
    ];
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

  private loadTestUrl(): void {
    const url: string = this.testUrl.trim();
    if (url.length <= 0) {
      this.getUIContext().getPromptAction().showToast({ message: '请输入测试URL' });
      return;
    }
    this.selectedSiteBaseUrl = this.resolveSelectedSiteBaseUrl(this.siteOptions, url);
    if (this.draft) {
      this.draft.testUrl = url;
      this.draft.updateTime = Date.now();
      this.refreshFloatingInspectorState();
    }
    sourceEditorInspectorStateManager.updateCurrentTargetUrl(url);
    this.requestWorkflowTargetLoad(url, true);
  }

  private async openFloatingInspector(): Promise<void> {
    this.refreshFloatingInspectorState();
    if (WindowManager.isFloatingWindowVisible('SourceEditorFloatingInspectorPage')) {
      return;
    }
    const opened = await WindowManager.openAppFloatingWindow(SOURCE_EDITOR_FLOATING_INSPECTOR_CONFIG);
    if (!opened) {
      this.getUIContext().getPromptAction().showToast({ message: '检查器打开失败' });
    }
  }

  private async toggleFloatingInspector(): Promise<void> {
    this.refreshFloatingInspectorState();
    const visibleBefore = WindowManager.isFloatingWindowVisible('SourceEditorFloatingInspectorPage');
    const success = await WindowManager.toggleAppFloatingWindow(SOURCE_EDITOR_FLOATING_INSPECTOR_CONFIG);
    if (!success) {
      this.getUIContext().getPromptAction().showToast({ message: '检查器操作失败' });
      return;
    }
    this.getUIContext().getPromptAction().showToast({ message: visibleBefore ? '检查器已关闭' : '检查器已打开' });
  }

  private async closeFloatingInspectorOnLeave(): Promise<void> {
    if (WindowManager.isFloatingWindowVisible('SourceEditorFloatingInspectorPage')) {
      await WindowManager.closeAppFloatingWindow('离开图源编辑器页面');
    }
  }

  private applyGuideSnapshot(force: boolean): void {
    const snapshot: SourceEditorInspectorSnapshot = sourceEditorInspectorStateManager.getSnapshot();
    if (!force && snapshot.renderVersion === this.lastGuideRenderVersion) {
      return;
    }
    this.lastGuideRenderVersion = snapshot.renderVersion;
    const step: SourceEditorWorkflowGuideStep | null = snapshot.currentStep;
    if (step === null) {
      return;
    }

    this.taskType = step.taskType;
    if (step.targetUrl.length > 0) {
      this.testUrl = step.targetUrl;
      this.selectedSiteBaseUrl = this.resolveSelectedSiteBaseUrl(this.siteOptions, step.targetUrl);
      if (this.draft) {
        this.draft.taskType = step.taskType;
        this.draft.testUrl = step.targetUrl;
        this.draft.updateTime = Date.now();
      }
    }

    if (snapshot.guidePhase === SourceEditorGuidePhase.PREVIEW && step.targetUrl.length > 0 &&
      (force || step.targetUrl !== this.lastLoadedGuideUrl)) {
      this.loadWorkflowTarget(step.targetUrl, force);
    }

    if (snapshot.guidePhase === SourceEditorGuidePhase.NEED_SELECTION &&
      snapshot.selectionRequestVersion !== this.lastSelectionRequestVersion) {
      this.lastSelectionRequestVersion = snapshot.selectionRequestVersion;
      this.injectDomPicker();
    }
  }

  private ensureInitialTargetLoaded(): void {
    const snapshot: SourceEditorInspectorSnapshot = sourceEditorInspectorStateManager.getSnapshot();
    const step: SourceEditorWorkflowGuideStep | null = snapshot.currentStep;
    if (step !== null && step.targetUrl.length > 0) {
      this.requestWorkflowTargetLoad(step.targetUrl, true);
      return;
    }
    if (this.draft !== null && this.draft.testUrl.length > 0) {
      this.requestWorkflowTargetLoad(this.draft.testUrl, true);
    }
  }

  private loadWorkflowTarget(url: string, force: boolean): void {
    this.requestWorkflowTargetLoad(url, force);
  }

  private requestWorkflowTargetLoad(url: string, force: boolean): void {
    const trimmedUrl: string = url.trim();
    if (trimmedUrl.length <= 0) {
      return;
    }
    if (!force && trimmedUrl === this.lastLoadedGuideUrl) {
      return;
    }
    this.lastLoadedGuideUrl = trimmedUrl;
    this.testUrl = trimmedUrl;
    this.selectedSiteBaseUrl = this.resolveSelectedSiteBaseUrl(this.siteOptions, trimmedUrl);
    this.mainFrameLoaded = false;
    this.workflowPreviewRetryCount = 0;
    this.loadRequestVersion += 1;
    const requestVersion: number = this.loadRequestVersion;
    this.clearPendingLoadTimer();
    this.pendingLoadTimerId = setTimeout((): void => {
      if (requestVersion !== this.loadRequestVersion) {
        return;
      }
      this.pendingLoadTimerId = -1;
      try {
        this.lastCommittedLoadUrl = trimmedUrl;
        this.webController.loadUrl(trimmedUrl);
        this.scheduleWorkflowPreview(1800);
      } catch (error) {
        logger.warn(TAG, `编辑WebView自动加载失败: ${String(error)}`);
      }
    }, 120);
  }

  private scheduleWorkflowPreview(delayMs: number = PREVIEW_RETRY_DELAY_MS): void {
    const dueAt: number = Date.now() + Math.max(0, delayMs);
    if (this.previewTimerId >= 0 && this.previewTimerDueAt > 0 && dueAt >= this.previewTimerDueAt) {
      return;
    }
    this.clearPreviewTimer();
    this.previewTimerDueAt = dueAt;
    this.previewTimerId = setTimeout((): void => {
      this.previewTimerId = -1;
      this.previewTimerDueAt = 0;
      this.runWorkflowPreview();
    }, Math.max(0, delayMs));
  }

  private maybeRunWorkflowPreviewWatchdog(): void {
    if (this.autoCheckRunning) {
      return;
    }
    const snapshot: SourceEditorInspectorSnapshot = sourceEditorInspectorStateManager.getSnapshot();
    const step: SourceEditorWorkflowGuideStep | null = snapshot.currentStep;
    if (step === null || snapshot.guidePhase !== SourceEditorGuidePhase.PREVIEW) {
      return;
    }
    if (!this.isInspectableUrl(this.testUrl) && !this.isInspectableUrl(step.targetUrl)) {
      return;
    }
    const now: number = Date.now();
    if (step.preview.status === SourceEditorWorkflowPreviewStatus.WAITING) {
      if (this.previewTimerId < 0 && now - this.lastPreviewAttemptAt >= 1500) {
        logger.debug(TAG, '工作流预览等待超时，触发兜底识别');
        this.scheduleWorkflowPreview(0);
      }
      return;
    }
    if (step.preview.status === SourceEditorWorkflowPreviewStatus.RUNNING && now - this.lastPreviewAttemptAt >= 4500) {
      logger.debug(TAG, '工作流预览运行超时，重新触发识别');
      this.scheduleWorkflowPreview(0);
      return;
    }
    if (step.preview.status === SourceEditorWorkflowPreviewStatus.EMPTY &&
      this.workflowPreviewRetryCount < 3 && now - this.lastPreviewAttemptAt >= 1800) {
      this.workflowPreviewRetryCount += 1;
      logger.debug(TAG, `工作流预览暂未识别到结果，自动重试: ${this.workflowPreviewRetryCount}`);
      this.scheduleWorkflowPreview(0);
    }
  }

  private runWorkflowPreview(): void {
    if (this.autoCheckRunning) {
      return;
    }
    const snapshot: SourceEditorInspectorSnapshot = sourceEditorInspectorStateManager.getSnapshot();
    const step: SourceEditorWorkflowGuideStep | null = snapshot.currentStep;
    if (step === null || snapshot.guidePhase !== SourceEditorGuidePhase.PREVIEW) {
      return;
    }
    const now: number = Date.now();
    if (now - this.lastPreviewAttemptAt < 700) {
      return;
    }
    this.lastPreviewAttemptAt = now;
    logger.debug(
      TAG,
      `开始工作流预览识别: task=${step.taskType}, url=${this.testUrl}, selector=${step.extractSelector}, ` +
        `wait=${step.waitSelector}, scriptLength=${step.scriptCode.length}`
    );

    const runningPreview: SourceEditorWorkflowPreview = {
      status: SourceEditorWorkflowPreviewStatus.RUNNING,
      summary: '正在识别页面内容',
      detail: '',
      selectorCount: 0,
      scriptCount: 0,
      sampleTitle: '',
      sampleUrl: '',
      sampleCover: '',
      errorMessage: ''
    };
    sourceEditorInspectorStateManager.updateWorkflowPreview(runningPreview);

    try {
      this.webController.runJavaScript(this.buildWorkflowPreviewScript(step), (error: BusinessError | null, result: string) => {
        if (error) {
          const failedPreview: SourceEditorWorkflowPreview = {
            status: SourceEditorWorkflowPreviewStatus.ERROR,
            summary: '预览脚本运行失败',
            detail: '',
            selectorCount: 0,
            scriptCount: 0,
            sampleTitle: '',
            sampleUrl: '',
            sampleCover: '',
            errorMessage: error.message
          };
          sourceEditorInspectorStateManager.updateWorkflowPreview(failedPreview);
          logger.warn(TAG, `工作流预览脚本运行失败: ${error.message}`);
          return;
        }
        const preview: SourceEditorWorkflowPreview = this.parseWorkflowPreview(result);
        sourceEditorInspectorStateManager.updateWorkflowPreview(preview);
        if (preview.status === SourceEditorWorkflowPreviewStatus.OK || preview.status === SourceEditorWorkflowPreviewStatus.ERROR) {
          this.workflowPreviewRetryCount = 3;
        }
        logger.debug(
          TAG,
          `工作流预览识别完成: status=${preview.status}, selector=${preview.selectorCount}, script=${preview.scriptCount}`
        );
      });
    } catch (error) {
      const failedPreview: SourceEditorWorkflowPreview = {
        status: SourceEditorWorkflowPreviewStatus.ERROR,
        summary: '预览脚本异常',
        detail: '',
        selectorCount: 0,
        scriptCount: 0,
        sampleTitle: '',
        sampleUrl: '',
        sampleCover: '',
        errorMessage: String(error)
      };
      sourceEditorInspectorStateManager.updateWorkflowPreview(failedPreview);
      logger.warn(TAG, `工作流预览脚本异常: ${String(error)}`);
    }
  }

  private parseWorkflowPreview(payloadJson: string): SourceEditorWorkflowPreview {
    const raw: WorkflowPreviewRaw = this.parseWorkflowPreviewRaw(payloadJson);
    const selectorCount: number = raw.selectorCount ? raw.selectorCount : 0;
    const scriptCount: number = raw.scriptCount ? raw.scriptCount : 0;
    const errorMessage: string = raw.error ? raw.error : '';
    const pending: boolean = raw.pending ? raw.pending : false;
    const status: SourceEditorWorkflowPreviewStatus = errorMessage.length > 0
      ? SourceEditorWorkflowPreviewStatus.ERROR
      : (pending ? SourceEditorWorkflowPreviewStatus.WAITING
        : (selectorCount > 0 || scriptCount > 0 ? SourceEditorWorkflowPreviewStatus.OK : SourceEditorWorkflowPreviewStatus.EMPTY));
    const preview: SourceEditorWorkflowPreview = {
      status: status,
      summary: raw.summary ? raw.summary : (status === SourceEditorWorkflowPreviewStatus.OK ? '已识别到内容' :
        (status === SourceEditorWorkflowPreviewStatus.WAITING ? '等待页面渲染完成' : '未识别到目标内容')),
      detail: raw.detail ? raw.detail : '',
      selectorCount: selectorCount,
      scriptCount: scriptCount,
      sampleTitle: raw.sampleTitle ? raw.sampleTitle : '',
      sampleUrl: raw.sampleUrl ? raw.sampleUrl : '',
      sampleCover: raw.sampleCover ? raw.sampleCover : '',
      errorMessage: errorMessage
    };
    return preview;
  }

  private parseWorkflowPreviewRaw(payloadJson: string): WorkflowPreviewRaw {
    const parsed: WorkflowPreviewRaw | string = SafeUtils.parseObj<WorkflowPreviewRaw | string>(payloadJson);
    if (typeof parsed === 'string') {
      return SafeUtils.parseObj<WorkflowPreviewRaw>(parsed);
    }
    return parsed;
  }

  private buildWorkflowPreviewScript(step: SourceEditorWorkflowGuideStep): string {
    const waitSelector: string = step.waitSelector.length > 0 ? step.waitSelector : step.extractSelector;
    const extractSelector: string = step.extractSelector.length > 0 ? step.extractSelector : waitSelector;
    const scriptCode: string = this.resolvePreviewScriptPlaceholders(step.scriptCode);
    return `
(function(){
  function clean(value) {
    return String(value || '').replace(/\\s+/g, ' ').trim();
  }
  function safeQueryAll(selector) {
    if (!selector) {
      return [];
    }
    try {
      return Array.from(document.querySelectorAll(selector));
    } catch (e) {
      return [];
    }
  }
  function absoluteUrl(value) {
    if (!value) {
      return '';
    }
    try {
      return new URL(value, location.href).href;
    } catch (e) {
      return value;
    }
  }
  function pickSample(element) {
    if (!element) {
      return { title: '', url: '', cover: '' };
    }
    var link = element.matches && element.matches('a[href]') ? element : element.querySelector('a[href]');
    var img = element.matches && element.matches('img') ? element : element.querySelector('img');
    var heading = element.querySelector('h1,h2,h3,.title,[class*="title"],[class*="name"]');
    var title = clean(heading ? heading.textContent : '') || clean(img ? img.getAttribute('alt') : '') || clean(element.textContent).substring(0, 80);
    var href = link ? absoluteUrl(link.getAttribute('href') || link.href || '') : '';
    var src = img ? absoluteUrl(img.getAttribute('data-src') || img.getAttribute('src') || img.currentSrc || '') : '';
    return { title: title, url: href, cover: src };
  }
  function parseScriptResult(value) {
    var count = 0;
    var sample = { title: '', url: '', cover: '' };
    var detail = '';
    try {
      var parsed = value;
      if (typeof value === 'string') {
        parsed = JSON.parse(value);
      }
      if (Array.isArray(parsed)) {
        count = parsed.length;
        if (parsed.length > 0) {
          var first = parsed[0] || {};
          sample.title = clean(first.title || first.name || '');
          sample.url = absoluteUrl(first.url || first.href || first.id || '');
          sample.cover = absoluteUrl(first.cover || first.imageUrl || first.src || '');
        }
      } else if (parsed && typeof parsed === 'object') {
        if (Array.isArray(parsed.pages)) {
          count = parsed.pages.length;
          if (parsed.pages.length > 0) {
            var firstPage = parsed.pages[0] || {};
            sample.cover = absoluteUrl(firstPage.imageUrl || firstPage.url || '');
          }
        } else if (Array.isArray(parsed.mangas)) {
          count = parsed.mangas.length;
          if (parsed.mangas.length > 0) {
            var firstManga = parsed.mangas[0] || {};
            sample.title = clean(firstManga.title || firstManga.name || '');
            sample.url = absoluteUrl(firstManga.url || firstManga.id || '');
            sample.cover = absoluteUrl(firstManga.cover || firstManga.imageUrl || '');
          }
        } else {
          count = 1;
          sample.title = clean(parsed.title || parsed.name || '');
          sample.url = absoluteUrl(parsed.url || parsed.id || '');
          sample.cover = absoluteUrl(parsed.cover || parsed.imageUrl || '');
        }
      }
      detail = '脚本返回 ' + count + ' 条';
    } catch (e) {
      detail = '脚本返回无法解析';
    }
    return { count: count, sample: sample, detail: detail };
  }
  var waitSelector = ${JSON.stringify(waitSelector)};
  var extractSelector = ${JSON.stringify(extractSelector)};
  var scriptCode = ${JSON.stringify(scriptCode)};
  if (document.readyState === 'loading') {
    return JSON.stringify({
      selectorCount: 0,
      scriptCount: 0,
      sampleTitle: '',
      sampleUrl: '',
      sampleCover: '',
      summary: '等待页面渲染完成',
      detail: 'document.readyState=' + document.readyState,
      error: '',
      pending: true
    });
  }
  var nodes = safeQueryAll(extractSelector || waitSelector);
  var selectorCount = nodes.length;
  var sample = selectorCount > 0 ? pickSample(nodes[0]) : { title: '', url: '', cover: '' };
  var scriptCount = 0;
  var scriptDetail = '';
  var error = '';
  if (scriptCode && scriptCode.length > 0) {
    try {
      var scriptValue = eval(scriptCode);
      var parsedResult = parseScriptResult(scriptValue);
      scriptCount = parsedResult.count;
      scriptDetail = parsedResult.detail;
      if (!sample.title) sample.title = parsedResult.sample.title;
      if (!sample.url) sample.url = parsedResult.sample.url;
      if (!sample.cover) sample.cover = parsedResult.sample.cover;
    } catch (e) {
      error = String(e && e.message ? e.message : e);
    }
  }
  var summary = selectorCount > 0 || scriptCount > 0 ? '识别到 ' + Math.max(selectorCount, scriptCount) + ' 个结果' : '未识别到目标内容';
  var detail = '选择器 ' + selectorCount + ' 个' + (scriptDetail ? ' · ' + scriptDetail : '');
  return JSON.stringify({
    selectorCount: selectorCount,
    scriptCount: scriptCount,
    sampleTitle: sample.title,
    sampleUrl: sample.url,
    sampleCover: sample.cover,
    summary: summary,
    detail: detail,
    error: error,
    pending: false
  });
})();`;
  }

  private resolvePreviewScriptPlaceholders(code: string): string {
    let output: string = code;
    const baseUrl: string = this.resolveBaseUrlFromTestUrl(this.testUrl);
    output = output.split('{{baseUrl}}').join(baseUrl);
    output = output.split('{{page}}').join('1');
    output = output.split('{{searchKeyword}}').join('test');
    output = output.split('{{query}}').join('test');
    output = output.split('{{mangaId}}').join('');
    output = output.split('{{chapterId}}').join('');
    return output;
  }

  private resolveBaseUrlFromTestUrl(url: string): string {
    const trimmed: string = url.trim();
    const schemeIndex: number = trimmed.indexOf('://');
    if (schemeIndex < 0) {
      return trimmed;
    }
    const pathIndex: number = trimmed.indexOf('/', schemeIndex + 3);
    if (pathIndex < 0) {
      return trimmed;
    }
    return trimmed.substring(0, pathIndex);
  }

  private injectDomPicker(): void {
    try {
      this.webController.runJavaScript(this.buildDomPickerScript(), (error: BusinessError | null, result: string) => {
        if (error) {
          logger.warn(TAG, `DOM点选脚本注入失败: ${error.message}`);
          this.getUIContext().getPromptAction().showToast({ message: '点选脚本注入失败' });
          return;
        }
        logger.info(TAG, `DOM点选脚本注入结果: ${result}`);
        this.pickerInjected = true;
        this.inspectorActive = true;
        void this.openFloatingInspector();
        this.getUIContext().getPromptAction().showToast({ message: '检查器已启用' });
      });
    } catch (error) {
      logger.error(TAG, `注入DOM点选脚本异常: ${String(error)}`);
      this.getUIContext().getPromptAction().showToast({ message: '点选脚本异常' });
    }
  }

  private onDomSelected(payloadJson: string): void {
    try {
      const rawSelection: DomSelectionSnapshot = this.parseSelection(payloadJson);
      const selection: DomSelectionSnapshot = this.prepareSelectionForCurrentWorkflow(rawSelection);
      if (!this.draft) {
        return;
      }
      const updatedDraft: SourceEditorDraft = interactiveSourceEditorService.applySelectionToDraft(
        this.draft,
        selection,
        this.taskType,
        this.testUrl
      );
      this.draft = updatedDraft;
      this.syncDraftState(updatedDraft);
      this.selectedSummary = `${selection.tagName} · ${selection.cssSelector} · 匹配 ${selection.matchedCount}`;
      this.inspectorActive = false;
      sourceEditorInspectorStateManager.updateSelectionAssessment(selection);
      this.refreshFloatingInspectorState();
      void this.openFloatingInspector();
      this.getUIContext().getPromptAction().showToast({ message: '已生成提取规则' });
    } catch (error) {
      logger.error(TAG, `解析DOM点选结果失败: ${String(error)}`);
      this.getUIContext().getPromptAction().showToast({ message: '点选结果解析失败' });
    }
  }

  private parseSelection(payloadJson: string): DomSelectionSnapshot {
    const raw: DomSelectionRaw = SafeUtils.parseObj(payloadJson) as DomSelectionRaw;
    const candidates: GeneratedSelectorCandidate[] = [];
    const rawCandidates: DomSelectionRawCandidate[] = raw.candidates ? raw.candidates : [];
    for (let i = 0; i < rawCandidates.length; i++) {
      const item = rawCandidates[i];
      const candidate: GeneratedSelectorCandidate = {
        type: item.type || '',
        value: item.value || '',
        score: item.score || 0,
        matchedCount: item.matchedCount || 0,
        note: item.note || ''
      };
      candidates.push(candidate);
    }
    const snapshot: DomSelectionSnapshot = {
      tagName: raw.tagName || '',
      text: raw.text || '',
      htmlPreview: raw.htmlPreview || '',
      href: raw.href || '',
      src: raw.src || '',
      idValue: raw.idValue || '',
      className: raw.className || '',
      cssSelector: raw.cssSelector || '',
      xpath: raw.xpath || '',
      matchedCount: raw.matchedCount || 0,
      candidates: candidates,
      containerSelector: raw.containerSelector || '',
      containerMatchedCount: raw.containerMatchedCount || 0,
      siblingSimilarCount: raw.siblingSimilarCount || 0,
      imageCount: raw.imageCount || 0,
      linkCount: raw.linkCount || 0,
      titleCandidate: raw.titleCandidate || '',
      imageCandidate: raw.imageCandidate || '',
      hrefCandidate: raw.hrefCandidate || '',
      itemScore: raw.itemScore || 0
    };
    return snapshot;
  }

  private prepareSelectionForCurrentWorkflow(selection: DomSelectionSnapshot): DomSelectionSnapshot {
    const currentStep: SourceEditorWorkflowGuideStep | null = sourceEditorInspectorStateManager.getCurrentStep();
    if (currentStep === null) {
      return selection;
    }
    const shouldUseContainer: boolean = currentStep.taskType === SourceEditorTaskType.SEARCH ||
      currentStep.taskType === SourceEditorTaskType.CHAPTERS ||
      currentStep.taskType === SourceEditorTaskType.PAGES;
    if (shouldUseContainer && selection.containerSelector && selection.containerSelector.length > 0) {
      selection.cssSelector = selection.containerSelector;
      selection.matchedCount = selection.containerMatchedCount ? selection.containerMatchedCount : selection.matchedCount;
    }
    if (selection.href.length <= 0 && selection.hrefCandidate && selection.hrefCandidate.length > 0) {
      selection.href = selection.hrefCandidate;
    }
    if (selection.src.length <= 0 && selection.imageCandidate && selection.imageCandidate.length > 0) {
      selection.src = selection.imageCandidate;
    }
    if (selection.text.length <= 0 && selection.titleCandidate && selection.titleCandidate.length > 0) {
      selection.text = selection.titleCandidate;
    }
    return selection;
  }

  private async saveDraft(mode: SourceSaveMode): Promise<void> {
    if (!this.draft) {
      this.getUIContext().getPromptAction().showToast({ message: '草稿未就绪' });
      return;
    }
    const result: SourceEditorSaveResult = await interactiveSourceEditorService.saveDraft(this.draft, mode);
    this.saveMessage = result.message;
    this.refreshFloatingInspectorState();
    this.getUIContext().getPromptAction().showToast({ message: result.message });
  }

  private isInspectableUrl(url: string): boolean {
    const trimmedUrl: string = url.trim();
    return trimmedUrl.length > 0 && trimmedUrl !== 'about:blank' && trimmedUrl.indexOf('data:') !== 0;
  }

  private handleWebPageBegin(url: string): void {
    if (!this.isInspectableUrl(url)) {
      return;
    }
    if (this.autoCheckRunning) {
      return;
    }
    this.mainFrameLoaded = false;
    this.workflowPreviewRetryCount = 0;
    this.lastCommittedLoadUrl = url;
    this.lastLoadedGuideUrl = url;
    this.selectedSiteBaseUrl = this.resolveSelectedSiteBaseUrl(this.siteOptions, url);
    sourceEditorInspectorStateManager.updateCurrentTargetUrl(url);
    const preview: SourceEditorWorkflowPreview = {
      status: SourceEditorWorkflowPreviewStatus.RUNNING,
      summary: '页面加载中',
      detail: url,
      selectorCount: 0,
      scriptCount: 0,
      sampleTitle: '',
      sampleUrl: '',
      sampleCover: '',
      errorMessage: ''
    };
    sourceEditorInspectorStateManager.updateWorkflowPreview(preview);
  }

  private handleWebPageEnd(url: string): void {
    if (this.autoCheckRunning) {
      return;
    }
    if (this.isInspectableUrl(url)) {
      this.mainFrameLoaded = true;
      this.lastCommittedLoadUrl = url;
      this.lastLoadedGuideUrl = url;
      this.selectedSiteBaseUrl = this.resolveSelectedSiteBaseUrl(this.siteOptions, url);
      sourceEditorInspectorStateManager.updateCurrentTargetUrl(url);
    }
    const snapshot: SourceEditorInspectorSnapshot = sourceEditorInspectorStateManager.getSnapshot();
    if (snapshot.guidePhase === SourceEditorGuidePhase.NEED_SELECTION) {
      this.injectDomPicker();
      return;
    }
    this.scheduleWorkflowPreview(160);
  }

  private handleWebProgress(progress: number): void {
    const snapshot: SourceEditorInspectorSnapshot = sourceEditorInspectorStateManager.getSnapshot();
    if (snapshot.guidePhase !== SourceEditorGuidePhase.PREVIEW) {
      return;
    }
    if (progress >= 85) {
      this.scheduleWorkflowPreview(220);
      return;
    }
    if (progress >= 60) {
      this.scheduleWorkflowPreview(650);
    }
  }

  private handleWebResourceError(
    errorCode: number,
    errorInfo: string,
    requestUrl: string,
    isMainFrame: boolean
  ): void {
    if (!isMainFrame || this.mainFrameLoaded) {
      logger.debug(
        TAG,
        `编辑WebView子资源加载跳过: code=${errorCode}, error=${errorInfo}, url=${requestUrl}`
      );
      return;
    }

    logger.warn(TAG, `编辑WebView主页面加载错误: code=${errorCode}, error=${errorInfo}, url=${requestUrl}`);
    const preview: SourceEditorWorkflowPreview = {
      status: SourceEditorWorkflowPreviewStatus.ERROR,
      summary: '页面加载失败',
      detail: requestUrl,
      selectorCount: 0,
      scriptCount: 0,
      sampleTitle: '',
      sampleUrl: '',
      sampleCover: '',
      errorMessage: errorInfo
    };
    sourceEditorInspectorStateManager.updateWorkflowPreview(preview);
  }

  private buildDomPickerScript(): string {
    return `
(function(){
  var state = window.__manxiaSourceEditorPickerState || {};
  window.__manxiaSourceEditorPickerState = state;
  var root = document.body || document.documentElement;
  if (!state.highlight) {
    state.highlight = document.createElement('div');
    state.highlight.style.position = 'fixed';
    state.highlight.style.pointerEvents = 'none';
    state.highlight.style.zIndex = '2147483647';
    state.highlight.style.border = '2px solid #00AEEF';
    state.highlight.style.background = 'rgba(0,174,239,0.14)';
    state.highlight.style.boxShadow = '0 0 0 9999px rgba(0,0,0,0.08)';
    state.highlight.style.display = 'none';
    root.appendChild(state.highlight);
  }
  if (!state.hitLayer) {
    state.hitLayer = document.createElement('div');
    state.hitLayer.style.position = 'fixed';
    state.hitLayer.style.left = '0';
    state.hitLayer.style.top = '0';
    state.hitLayer.style.width = '100vw';
    state.hitLayer.style.height = '100vh';
    state.hitLayer.style.zIndex = '2147483646';
    state.hitLayer.style.background = 'rgba(0,0,0,0.001)';
    state.hitLayer.style.cursor = 'crosshair';
    state.hitLayer.style.touchAction = 'none';
    root.appendChild(state.hitLayer);
  }
  var overlay = state.highlight;
  var hitLayer = state.hitLayer;
  state.active = true;
  hitLayer.style.display = 'block';
  hitLayer.style.pointerEvents = 'auto';
  overlay.style.display = 'none';
  function esc(value) {
    return String(value || '').replace(/([ #.;?+*~\\':"!^$[\\]()=>|\\/@])/g, '\\\\$1');
  }
  function consume(event) {
    if (!event) {
      return false;
    }
    event.preventDefault();
    event.stopPropagation();
    if (event.stopImmediatePropagation) {
      event.stopImmediatePropagation();
    }
    return false;
  }
  function pointFromEvent(event) {
    if (event && event.touches && event.touches.length > 0) {
      return { x: event.touches[0].clientX, y: event.touches[0].clientY };
    }
    if (event && event.changedTouches && event.changedTouches.length > 0) {
      return { x: event.changedTouches[0].clientX, y: event.changedTouches[0].clientY };
    }
    return { x: event.clientX || 0, y: event.clientY || 0 };
  }
  function elementFromPointSafe(x, y) {
    var previousHitDisplay = hitLayer.style.display;
    var previousOverlayDisplay = overlay.style.display;
    hitLayer.style.display = 'none';
    overlay.style.display = 'none';
    var element = document.elementFromPoint(x, y);
    hitLayer.style.display = previousHitDisplay || 'block';
    overlay.style.display = previousOverlayDisplay;
    if (element === document.documentElement && document.body) {
      return document.body;
    }
    return element;
  }
  function showHighlight(element) {
    if (!element || element.nodeType !== 1) {
      overlay.style.display = 'none';
      return;
    }
    var rect = element.getBoundingClientRect();
    overlay.style.display = 'block';
    overlay.style.left = rect.left + 'px';
    overlay.style.top = rect.top + 'px';
    overlay.style.width = rect.width + 'px';
    overlay.style.height = rect.height + 'px';
  }
  function deactivatePicker() {
    state.active = false;
    hitLayer.style.display = 'none';
    overlay.style.display = 'none';
  }
  function deactivatePickerAfterClick() {
    state.active = false;
    overlay.style.display = 'none';
    setTimeout(function(){
      hitLayer.style.display = 'none';
    }, 420);
  }
  function cssPath(element) {
    if (!element || element.nodeType !== 1) {
      return '';
    }
    if (element.id) {
      return '#' + esc(element.id);
    }
    var path = [];
    var el = element;
    while (el && el.nodeType === 1 && el !== document.body && el !== document.documentElement) {
      var selector = el.nodeName.toLowerCase();
      if (el.className && typeof el.className === 'string') {
        var classes = el.className.trim().split(/\\s+/).filter(function(cls){ return cls.length > 0; }).slice(0, 3);
        if (classes.length > 0) {
          selector += '.' + classes.map(esc).join('.');
        }
      }
      var parent = el.parentElement;
      if (parent) {
        var sameTag = Array.prototype.filter.call(parent.children, function(child){
          return child.nodeName === el.nodeName;
        });
        if (sameTag.length > 1) {
          selector += ':nth-of-type(' + (sameTag.indexOf(el) + 1) + ')';
        }
      }
      path.unshift(selector);
      el = parent;
      if (path.length >= 6) {
        break;
      }
    }
    return path.join(' > ');
  }
  function xPath(element) {
    if (!element || element.nodeType !== 1) {
      return '';
    }
    if (element.id) {
      return '//*[@id="' + element.id.replace(/"/g, '\\\\"') + '"]';
    }
    var parts = [];
    var el = element;
    while (el && el.nodeType === 1) {
      var index = 1;
      var sibling = el.previousElementSibling;
      while (sibling) {
        if (sibling.nodeName === el.nodeName) {
          index++;
        }
        sibling = sibling.previousElementSibling;
      }
      parts.unshift(el.nodeName.toLowerCase() + '[' + index + ']');
      el = el.parentElement;
    }
    return '/' + parts.join('/');
  }
  function selectorCount(selector) {
    try {
      return document.querySelectorAll(selector).length;
    } catch (e) {
      return 0;
    }
  }
  function addAttributeCandidates(element, candidates) {
    var attrs = ['data-id', 'data-key', 'data-src', 'data-original', 'data-testid', 'aria-label', 'title'];
    for (var i = 0; i < attrs.length; i++) {
      var attr = attrs[i];
      var value = element.getAttribute(attr);
      if (value && value.length > 0) {
        var candidate = element.tagName.toLowerCase() + '[' + attr + '="' + value.replace(/"/g, '\\\\"') + '"]';
        candidates.push({ type: 'css', value: candidate, score: 88 - i, matchedCount: selectorCount(candidate), note: attr });
      }
    }
  }
  function cleanText(value) {
    return String(value || '').replace(/\\s+/g, ' ').trim();
  }
  function absoluteUrl(value) {
    if (!value) {
      return '';
    }
    try {
      return new URL(value, location.href).href;
    } catch (e) {
      return value;
    }
  }
  function similarSiblingCount(element) {
    if (!element || !element.parentElement) {
      return 0;
    }
    var tagName = element.tagName;
    var className = typeof element.className === 'string' ? element.className.trim().split(/\\s+/).slice(0, 2).join(' ') : '';
    var count = 0;
    Array.prototype.forEach.call(element.parentElement.children, function(child) {
      if (child.tagName !== tagName) {
        return;
      }
      var childClassName = typeof child.className === 'string' ? child.className.trim().split(/\\s+/).slice(0, 2).join(' ') : '';
      if (!className || childClassName === className) {
        count++;
      }
    });
    return count;
  }
  function analyzeContainer(element) {
    var best = element;
    var bestScore = -1;
    var current = element;
    var depth = 0;
    while (current && current.nodeType === 1 && depth < 6) {
      var images = current.querySelectorAll ? current.querySelectorAll('img').length : 0;
      var links = current.querySelectorAll ? current.querySelectorAll('a[href]').length : 0;
      var headings = current.querySelectorAll ? current.querySelectorAll('h1,h2,h3,.title,[class*="title"],[class*="name"]').length : 0;
      var textLength = cleanText(current.textContent).length;
      var siblings = similarSiblingCount(current);
      var score = images * 20 + links * 18 + headings * 18 + Math.min(textLength, 140) / 12 + Math.min(siblings, 8) * 8 - depth * 4;
      if (current === element && current.tagName && current.tagName.toLowerCase() === 'img') {
        score -= 24;
      }
      if (score > bestScore) {
        bestScore = score;
        best = current;
      }
      current = current.parentElement;
      depth++;
    }
    var selector = cssPath(best);
    var link = best && best.matches && best.matches('a[href]') ? best : (best && best.querySelector ? best.querySelector('a[href]') : null);
    var img = best && best.matches && best.matches('img') ? best : (best && best.querySelector ? best.querySelector('img') : null);
    var titleEl = best && best.querySelector ? best.querySelector('h1,h2,h3,.title,[class*="title"],[class*="name"]') : null;
    var title = cleanText(titleEl ? titleEl.textContent : '') || cleanText(img ? img.getAttribute('alt') : '') || cleanText(best ? best.textContent : '').substring(0, 120);
    var image = img ? absoluteUrl(img.getAttribute('data-src') || img.getAttribute('src') || img.currentSrc || '') : '';
    var href = link ? absoluteUrl(link.getAttribute('href') || link.href || '') : '';
    return {
      selector: selector,
      matchedCount: selectorCount(selector),
      siblingSimilarCount: similarSiblingCount(best),
      imageCount: best && best.querySelectorAll ? best.querySelectorAll('img').length : 0,
      linkCount: best && best.querySelectorAll ? best.querySelectorAll('a[href]').length : 0,
      titleCandidate: title,
      imageCandidate: image,
      hrefCandidate: href,
      itemScore: Math.max(0, Math.min(100, Math.round(bestScore)))
    };
  }
  function sendSelection(element) {
    if (!element || element.nodeType !== 1) {
      return;
    }
    var selector = cssPath(element);
    var xp = xPath(element);
    var rect = element.getBoundingClientRect();
    var href = element.href || element.getAttribute('href') || '';
    var src = element.currentSrc || element.src || element.getAttribute('data-src') || element.getAttribute('src') || '';
    var text = (element.innerText || element.textContent || '').trim();
    var html = (element.outerHTML || '').substring(0, 500);
    var candidates = [];
    if (element.id) {
      candidates.push({ type: 'css', value: '#' + esc(element.id), score: 100, matchedCount: selectorCount('#' + esc(element.id)), note: 'id' });
    }
    addAttributeCandidates(element, candidates);
    if (selector) {
      candidates.push({ type: 'css', value: selector, score: 70, matchedCount: selectorCount(selector), note: 'css' });
    }
    if (xp) {
      candidates.push({ type: 'xpath', value: xp, score: 55, matchedCount: 1, note: 'xpath' });
    }
    var container = analyzeContainer(element);
    var payload = {
      tagName: element.tagName ? element.tagName.toLowerCase() : '',
      text: text.substring(0, 300),
      htmlPreview: html,
      href: href,
      src: src,
      idValue: element.id || '',
      className: typeof element.className === 'string' ? element.className : '',
      cssSelector: selector,
      xpath: xp,
      matchedCount: selectorCount(selector),
      candidates: candidates,
      rectLeft: rect.left,
      rectTop: rect.top,
      containerSelector: container.selector,
      containerMatchedCount: container.matchedCount,
      siblingSimilarCount: container.siblingSimilarCount,
      imageCount: container.imageCount,
      linkCount: container.linkCount,
      titleCandidate: container.titleCandidate,
      imageCandidate: container.imageCandidate,
      hrefCandidate: container.hrefCandidate,
      itemScore: container.itemScore
    };
    if (window.sourceEditorBridge && window.sourceEditorBridge.onDomSelected) {
      window.sourceEditorBridge.onDomSelected(JSON.stringify(payload));
    }
  }
  function previewAtEvent(event) {
    if (!state.active) {
      return consume(event);
    }
    var point = pointFromEvent(event);
    var target = elementFromPointSafe(point.x, point.y);
    state.lastTarget = target;
    showHighlight(target);
    return consume(event);
  }
  function selectAtEvent(event) {
    if (!state.active) {
      return consume(event);
    }
    var now = Date.now();
    if (state.lastSelectionTime && now - state.lastSelectionTime < 350) {
      return consume(event);
    }
    var point = pointFromEvent(event);
    var target = state.lastTarget || elementFromPointSafe(point.x, point.y);
    if (target) {
      state.lastSelectionTime = now;
      sendSelection(target);
      deactivatePickerAfterClick();
    }
    return consume(event);
  }
  if (!state.listenersInstalled) {
    state.listenersInstalled = true;
    var eventOptions = { capture: true, passive: false };
    hitLayer.addEventListener('touchstart', previewAtEvent, eventOptions);
    hitLayer.addEventListener('touchmove', previewAtEvent, eventOptions);
    hitLayer.addEventListener('touchend', selectAtEvent, eventOptions);
    hitLayer.addEventListener('touchcancel', consume, eventOptions);
    hitLayer.addEventListener('pointerdown', previewAtEvent, eventOptions);
    hitLayer.addEventListener('pointermove', previewAtEvent, eventOptions);
    hitLayer.addEventListener('pointerup', selectAtEvent, eventOptions);
    hitLayer.addEventListener('pointercancel', consume, eventOptions);
    hitLayer.addEventListener('mousedown', previewAtEvent, eventOptions);
    hitLayer.addEventListener('mousemove', previewAtEvent, eventOptions);
    hitLayer.addEventListener('mouseup', selectAtEvent, eventOptions);
    hitLayer.addEventListener('click', consume, eventOptions);
  }
  return 'picker-enabled';
})();`;
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

        Column({ space: 10 }) {
          Blank().height(SettingsPageTitleBarManager.getContentTopPadding(this.statusBarHeight))
          this.buildToolbar()
          this.buildAutoCheckPanel()
          this.buildWebPanel()
          Blank().height(this.navigationBarHeight)
        }
        .width('100%')
        .height('100%')
        .padding({ left: 12, right: 12, bottom: 8 })

        SettingsImmersiveTitleBar({
          themeState: this.themeState,
          title: '图源编辑器',
          appFontFamily: this.appFontFamily,
          actions: this.getTitleBarActions()
        })
      }
      .width('100%')
      .height('100%')
      .bindSheet($$this.showAutoCheckScopePicker, this.buildAutoCheckScopePicker(), {
        height: '100%',
        showClose: false,
        dragBar: true
      })
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
      interactiveSourceEditorService.setAbilityContext(hostContext);
      const params = context.pathInfo.param as SourceInteractiveEditorPageParams | null;
      void this.initialize(params);
    })
  }

  private handleTestUrlChange(value: string): void {
    this.testUrl = value;
    this.selectedSiteBaseUrl = this.resolveSelectedSiteBaseUrl(this.siteOptions, value);
    if (this.draft) {
      this.draft.testUrl = value;
      this.draft.updateTime = Date.now();
      this.refreshFloatingInspectorState();
    }
  }

  private handleTaskTypeChange(taskType: SourceEditorTaskType): void {
    this.taskType = taskType;
    sourceEditorInspectorStateManager.selectWorkflow(taskType);
    if (this.draft) {
      this.draft.taskType = taskType;
      this.draft.updateTime = Date.now();
      this.refreshFloatingInspectorState();
    }
    this.applyGuideSnapshot(true);
  }

  private getAutoCheckHistoryStatusText(status: SourceAutoCheckRecordStatus): string {
    if (status === 'RUNNING') {
      return '进行中';
    }
    if (status === 'COMPLETED') {
      return '已完成';
    }
    if (status === 'FAILED') {
      return '失败';
    }
    return '已取消';
  }

  private getAutoCheckRecordToneColor(status: SourceAutoCheckRecordStatus): ResourceColor {
    if (status === 'COMPLETED') {
      return AppColors.success;
    }
    if (status === 'FAILED') {
      return AppColors.error;
    }
    if (status === 'CANCELLED') {
      return AppColors.warning;
    }
    return ThemeAwareHelper.getTestManagementThemedColor('accent_primary', this.themeState.currentTheme);
  }

  private formatTwoDigit(value: number): string {
    if (value < 10) {
      return `0${value}`;
    }
    return `${value}`;
  }

  private formatAutoCheckRecordTime(time: number): string {
    if (time <= 0) {
      return '未知时间';
    }
    const date: Date = new Date(time);
    const month: number = date.getMonth() + 1;
    const day: number = date.getDate();
    const hour: number = date.getHours();
    const minute: number = date.getMinutes();
    return `${month}-${this.formatTwoDigit(day)} ${this.formatTwoDigit(hour)}:${this.formatTwoDigit(minute)}`;
  }

  private formatAutoCheckDuration(record: SourceAutoCheckRecord): string {
    let durationMs: number = record.durationMs;
    if (record.status === 'RUNNING' && record.startTime > 0) {
      durationMs = Date.now() - record.startTime;
    }
    if (durationMs <= 0) {
      return '未记录耗时';
    }
    const seconds: number = Math.max(1, Math.ceil(durationMs / 1000));
    if (seconds < 60) {
      return `${seconds}秒`;
    }
    const minutes: number = Math.floor(seconds / 60);
    const restSeconds: number = seconds - minutes * 60;
    if (restSeconds <= 0) {
      return `${minutes}分`;
    }
    return `${minutes}分${restSeconds}秒`;
  }

  private getAutoCheckHistoryReports(record: SourceAutoCheckRecord): SourceAutoCheckSiteReport[] {
    return this.cloneAutoCheckSiteReports(SafeUtils.parseArr<SourceAutoCheckSiteReport[]>(record.reportJson));
  }

  private getAutoCheckHistoryWorkflowText(record: SourceAutoCheckRecord): string {
    const labels: string[] = SafeUtils.parseArr<string[]>(record.workflowLabelsJson);
    if (labels.length <= 0) {
      return '未记录范围';
    }
    let text: string = '';
    for (let index = 0; index < labels.length; index += 1) {
      if (text.length > 0) {
        text += '、';
      }
      text += labels[index];
    }
    return text;
  }

  private getAutoCheckHistoryProgressText(record: SourceAutoCheckRecord): string {
    const reports: SourceAutoCheckSiteReport[] = this.getAutoCheckHistoryReports(record);
    let totalWorkflowCount: number = 0;
    let checkedWorkflowCount: number = 0;
    for (let index = 0; index < reports.length; index += 1) {
      const report: SourceAutoCheckSiteReport = reports[index];
      totalWorkflowCount += report.totalCount;
      checkedWorkflowCount += Math.min(report.workflowResults.length, report.totalCount);
    }
    if (totalWorkflowCount > 0) {
      return `${checkedWorkflowCount}/${totalWorkflowCount} 步`;
    }
    if (record.siteCount > 0) {
      return `${record.siteCount}个站点`;
    }
    return '暂无进度';
  }

  private getAutoCheckHistoryRecommendationText(record: SourceAutoCheckRecord): string {
    if (record.recommendedSiteBaseUrl.length <= 0) {
      return '未生成推荐';
    }
    const reports: SourceAutoCheckSiteReport[] = this.getAutoCheckHistoryReports(record);
    for (let index = 0; index < reports.length; index += 1) {
      const report: SourceAutoCheckSiteReport = reports[index];
      if (report.siteBaseUrl === record.recommendedSiteBaseUrl || report.recommended) {
        return `推荐 ${report.siteLabel}`;
      }
    }
    return `推荐 ${record.recommendedSiteBaseUrl}`;
  }

  private getAutoCheckStatusText(status: SourceEditorWorkflowPreviewStatus): string {
    if (status === SourceEditorWorkflowPreviewStatus.OK) {
      return '通过';
    }
    if (status === SourceEditorWorkflowPreviewStatus.EMPTY) {
      return '空结果';
    }
    if (status === SourceEditorWorkflowPreviewStatus.WAITING) {
      return '等待';
    }
    if (status === SourceEditorWorkflowPreviewStatus.RUNNING) {
      return '运行中';
    }
    return '失败';
  }

  @Builder
  private buildAutoCheckWorkflowResult(result: SourceAutoCheckWorkflowResult) {
    Row({ space: 8 }) {
      Text(result.taskLabel)
        .width(48)
        .fontSize(12)
        .fontFamily(this.appFontFamily)
        .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_primary', this.themeState.currentTheme))
        .maxLines(1)
      Text(this.getAutoCheckStatusText(result.status))
        .width(54)
        .fontSize(12)
        .fontFamily(this.appFontFamily)
        .fontColor(this.getAutoCheckWorkflowToneColor(result))
        .maxLines(1)
      Text(`${result.score}分`)
        .width(44)
        .fontSize(12)
        .fontFamily(this.appFontFamily)
        .fontColor(this.getAutoCheckWorkflowToneColor(result))
        .maxLines(1)
      Text(result.summary.length > 0 ? result.summary : result.errorMessage)
        .layoutWeight(1)
        .fontSize(12)
        .fontFamily(this.appFontFamily)
        .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_secondary', this.themeState.currentTheme))
        .maxLines(1)
        .textOverflow({ overflow: TextOverflow.Ellipsis })
    }
    .width('100%')
    .height(24)
  }

  @Builder
  private buildAutoCheckSiteReport(report: SourceAutoCheckSiteReport) {
    Stack({ alignContent: Alignment.Start }) {
      Column() {
      }
        .width(`${this.getAutoCheckSiteProgressPercent(report)}%`)
        .height('100%')
        .backgroundColor(this.getAutoCheckSiteToneColor(report))
        .opacity(0.18)

      Column({ space: 6 }) {
        Row({ space: 8 }) {
          Text(report.siteLabel)
            .fontSize(13)
            .fontWeight(FontWeight.Medium)
            .fontFamily(this.appFontFamily)
            .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_primary', this.themeState.currentTheme))
            .layoutWeight(1)
            .maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
          if (report.recommended) {
            Text('推荐')
              .fontSize(11)
              .fontFamily(this.appFontFamily)
              .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_white', this.themeState.currentTheme))
              .padding({ left: 8, right: 8, top: 3, bottom: 3 })
              .borderRadius(8)
              .backgroundColor(ThemeAwareHelper.getTestManagementThemedColor('accent_primary', this.themeState.currentTheme))
          }
          Text(this.getAutoCheckSiteSummaryText(report))
            .fontSize(12)
            .fontFamily(this.appFontFamily)
            .fontColor(this.getAutoCheckSiteToneColor(report))
            .maxLines(1)
        }
        .width('100%')

        ForEach(report.workflowResults, (result: SourceAutoCheckWorkflowResult) => {
          this.buildAutoCheckWorkflowResult(result)
        }, (result: SourceAutoCheckWorkflowResult) => `${result.siteId}_${result.workflowKey}_${result.status}_${result.score}`)
      }
      .width('100%')
      .padding(8)
    }
    .width('100%')
    .height(this.getAutoCheckSiteReportHeight(report))
    .borderRadius(8)
    .backgroundColor(ThemeAwareHelper.getTestManagementThemedColor('background_secondary', this.themeState.currentTheme))
    .border({
      width: report.workflowResults.length > 0 ? 1 : 0,
      color: this.getAutoCheckSiteToneColor(report)
    })
    .clip(true)
  }

  @Builder
  private buildAutoCheckHistoryDetail(record: SourceAutoCheckRecord) {
    Column({ space: 8 }) {
      Row({ space: 8 }) {
        Text(`范围：${this.getAutoCheckHistoryWorkflowText(record)}`)
          .fontSize(12)
          .fontFamily(this.appFontFamily)
          .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_secondary', this.themeState.currentTheme))
          .layoutWeight(1)
          .maxLines(2)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
        Text(this.getAutoCheckHistoryRecommendationText(record))
          .fontSize(12)
          .fontFamily(this.appFontFamily)
          .fontColor(ThemeAwareHelper.getTestManagementThemedColor('accent_primary', this.themeState.currentTheme))
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
      }
      .width('100%')

      if (this.getAutoCheckHistoryReports(record).length > 0) {
        ForEach(this.getAutoCheckHistoryReports(record), (report: SourceAutoCheckSiteReport) => {
          this.buildAutoCheckSiteReport(report)
        }, (report: SourceAutoCheckSiteReport) => `${record.taskId}_${report.siteId}_${report.workflowResults.length}_${report.score}`)
      } else {
        Text(record.summary.length > 0 ? record.summary : '暂无详细站点结果')
          .fontSize(12)
          .fontFamily(this.appFontFamily)
          .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_secondary', this.themeState.currentTheme))
          .width('100%')
          .padding({ top: 4, bottom: 4 })
      }
    }
    .width('100%')
  }

  @Builder
  private buildAutoCheckHistoryRecord(record: SourceAutoCheckRecord) {
    Column({ space: 8 }) {
      Row({ space: 8 }) {
        Text(this.getAutoCheckHistoryStatusText(record.status))
          .fontSize(11)
          .fontFamily(this.appFontFamily)
          .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_white', this.themeState.currentTheme))
          .padding({ left: 8, right: 8, top: 3, bottom: 3 })
          .borderRadius(8)
          .backgroundColor(this.getAutoCheckRecordToneColor(record.status))
        Text(this.formatAutoCheckRecordTime(record.startTime))
          .fontSize(12)
          .fontFamily(this.appFontFamily)
          .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_primary', this.themeState.currentTheme))
          .layoutWeight(1)
          .maxLines(1)
        Text(this.getAutoCheckHistoryProgressText(record))
          .fontSize(12)
          .fontFamily(this.appFontFamily)
          .fontColor(this.getAutoCheckRecordToneColor(record.status))
          .maxLines(1)
        SymbolGlyph(this.expandedAutoCheckHistoryTaskId === record.taskId ?
          $r('sys.symbol.chevron_up') : $r('sys.symbol.chevron_down'))
          .fontSize(14)
          .fontColor([ThemeAwareHelper.getTestManagementThemedColor('text_secondary', this.themeState.currentTheme)])
      }
      .width('100%')

      Text(record.summary.length > 0 ? record.summary : this.getAutoCheckHistoryRecommendationText(record))
        .fontSize(12)
        .fontFamily(this.appFontFamily)
        .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_secondary', this.themeState.currentTheme))
        .width('100%')
        .maxLines(2)
        .textOverflow({ overflow: TextOverflow.Ellipsis })

      Row({ space: 8 }) {
        Text(this.getAutoCheckHistoryWorkflowText(record))
          .fontSize(11)
          .fontFamily(this.appFontFamily)
          .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_secondary', this.themeState.currentTheme))
          .layoutWeight(1)
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
        Text(this.formatAutoCheckDuration(record))
          .fontSize(11)
          .fontFamily(this.appFontFamily)
          .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_secondary', this.themeState.currentTheme))
          .maxLines(1)
      }
      .width('100%')

      if (this.expandedAutoCheckHistoryTaskId === record.taskId) {
        this.buildAutoCheckHistoryDetail(record)
      }
    }
    .width('100%')
    .padding(10)
    .borderRadius(8)
    .backgroundColor(ThemeAwareHelper.getTestManagementThemedColor('background_secondary', this.themeState.currentTheme))
    .border({
      width: 1,
      color: this.getAutoCheckRecordToneColor(record.status)
    })
    .onClick(() => {
      this.expandedAutoCheckHistoryTaskId =
        this.expandedAutoCheckHistoryTaskId === record.taskId ? '' : record.taskId;
    })
  }

  @Builder
  private buildAutoCheckHistorySection() {
    Column({ space: 8 }) {
      Row({ space: 8 }) {
        SymbolGlyph($r('sys.symbol.clock_arrow_2_circlepath'))
          .fontSize(15)
          .fontColor([ThemeAwareHelper.getTestManagementThemedColor('accent_primary', this.themeState.currentTheme)])
        Text('历史巡检')
          .fontSize(14)
          .fontWeight(FontWeight.Medium)
          .fontFamily(this.appFontFamily)
          .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_primary', this.themeState.currentTheme))
        Blank()
        Text(`${this.autoCheckHistoryRecords.length}条`)
          .fontSize(12)
          .fontFamily(this.appFontFamily)
          .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_secondary', this.themeState.currentTheme))
      }
      .width('100%')

      if (this.autoCheckHistoryRecords.length > 0) {
        ForEach(this.autoCheckHistoryRecords, (record: SourceAutoCheckRecord) => {
          this.buildAutoCheckHistoryRecord(record)
        }, (record: SourceAutoCheckRecord) => record.taskId)
      } else {
        Text('暂无该图源的巡检记录')
          .fontSize(12)
          .fontFamily(this.appFontFamily)
          .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_secondary', this.themeState.currentTheme))
          .width('100%')
          .padding({ left: 12, right: 12, top: 10, bottom: 10 })
          .borderRadius(8)
          .backgroundColor(ThemeAwareHelper.getTestManagementThemedColor('background_secondary', this.themeState.currentTheme))
      }
    }
    .width('100%')
  }

  @Builder
  private buildAutoCheckScopeOption(option: SourceAutoCheckTaskOption) {
    Row({ space: 10 }) {
      Column({ space: 3 }) {
        Text(option.label)
          .fontSize(14)
          .fontWeight(FontWeight.Medium)
          .fontFamily(this.appFontFamily)
          .fontColor(this.isAutoCheckWorkflowSelected(option.workflowKey) ?
            ThemeAwareHelper.getTestManagementThemedColor('accent_primary', this.themeState.currentTheme) :
            ThemeAwareHelper.getTestManagementThemedColor('text_primary', this.themeState.currentTheme))
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
        Text(option.workflowKey)
          .fontSize(11)
          .fontFamily(this.appFontFamily)
          .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_secondary', this.themeState.currentTheme))
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
      }
      .layoutWeight(1)
      .alignItems(HorizontalAlign.Start)

      if (this.isAutoCheckWorkflowSelected(option.workflowKey)) {
        SymbolGlyph($r('sys.symbol.checkmark'))
          .fontSize(18)
          .fontColor([ThemeAwareHelper.getTestManagementThemedColor('accent_primary', this.themeState.currentTheme)])
      }
    }
    .width('100%')
    .height(54)
    .padding({ left: 14, right: 14 })
    .borderRadius(8)
    .backgroundColor(this.isAutoCheckWorkflowSelected(option.workflowKey) ?
      ThemeAwareHelper.getTestManagementThemedColor('accent_primary_dimmed', this.themeState.currentTheme) :
      ThemeAwareHelper.getTestManagementThemedColor('background_secondary', this.themeState.currentTheme))
    .onClick(() => {
      this.toggleAutoCheckWorkflowSelection(option.workflowKey);
    })
  }

  @Builder
  private buildAutoCheckScopePicker() {
    Column({ space: 12 }) {
      Row({ space: 8 }) {
        SymbolGlyph($r('sys.symbol.waveform_path_ecg_magnifyingglass'))
          .fontSize(18)
          .fontColor([ThemeAwareHelper.getTestManagementThemedColor('accent_primary', this.themeState.currentTheme)])
        Text('选择巡检范围')
          .fontSize(16)
          .fontWeight(FontWeight.Medium)
          .fontFamily(this.appFontFamily)
          .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_primary', this.themeState.currentTheme))
        Blank()
        Text(`${this.selectedAutoCheckWorkflowKeys.length}/${this.autoCheckScopeOptions.length}`)
          .fontSize(12)
          .fontFamily(this.appFontFamily)
          .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_secondary', this.themeState.currentTheme))
      }
      .width('100%')

      Scroll() {
        Column({ space: 12 }) {
          this.buildAutoCheckHistorySection()

          Column({ space: 8 }) {
            Row({ space: 8 }) {
              Text('本次巡检范围')
                .fontSize(14)
                .fontWeight(FontWeight.Medium)
                .fontFamily(this.appFontFamily)
                .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_primary', this.themeState.currentTheme))
              Blank()
              this.buildActionTextButton('全选', 68, () => {
                this.selectAllAutoCheckWorkflows();
              })
              this.buildActionTextButton('清空', 68, () => {
                this.clearAutoCheckWorkflowSelection();
              })
            }
            .width('100%')

            ForEach(this.autoCheckScopeOptions, (option: SourceAutoCheckTaskOption) => {
              this.buildAutoCheckScopeOption(option)
            }, (option: SourceAutoCheckTaskOption) => option.workflowKey)
          }
          .width('100%')
        }
        .width('100%')
        .padding({ bottom: 4 })
      }
      .width('100%')
      .layoutWeight(1)
      .scrollBar(BarState.Auto)

      Row({ space: 10 }) {
        Button('取消')
          .layoutWeight(1)
          .height(40)
          .fontSize(13)
          .fontFamily(this.appFontFamily)
          .backgroundColor(ThemeAwareHelper.getTestManagementThemedColor('background_secondary', this.themeState.currentTheme))
          .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_secondary', this.themeState.currentTheme))
          .onClick(() => {
            this.showAutoCheckScopePicker = false;
          })
        Button('开始巡检')
          .layoutWeight(1)
          .height(40)
          .fontSize(13)
          .fontFamily(this.appFontFamily)
          .backgroundColor(ThemeAwareHelper.getTestManagementThemedColor('accent_primary', this.themeState.currentTheme))
          .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_white', this.themeState.currentTheme))
          .enabled(this.selectedAutoCheckWorkflowKeys.length > 0)
          .onClick(() => {
            const selectedTasks: SourceAutoCheckTaskOption[] = this.getSelectedAutoCheckTasks();
            this.showAutoCheckScopePicker = false;
            void this.startAutoCheckWithTasks(selectedTasks, '请选择至少一个巡检范围');
          })
      }
      .width('100%')
    }
    .width('100%')
    .height('100%')
    .padding(16)
  }

  @Builder
  private buildAutoCheckPanel() {
    if (this.autoCheckRunning || this.autoCheckReportReady) {
      Column({ space: 8 }) {
        Row({ space: 8 }) {
          SymbolGlyph($r('sys.symbol.waveform_path_ecg_magnifyingglass'))
            .fontSize(16)
            .fontColor([ThemeAwareHelper.getTestManagementThemedColor('accent_primary', this.themeState.currentTheme)])
          Text(this.autoCheckRunning ? '自动检查中' : '自动检查报告')
            .fontSize(14)
            .fontWeight(FontWeight.Medium)
            .fontFamily(this.appFontFamily)
            .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_primary', this.themeState.currentTheme))
          Blank()
          if (this.autoCheckRunning) {
            Button('停止')
              .height(28)
              .fontSize(12)
              .fontFamily(this.appFontFamily)
              .backgroundColor(ThemeAwareHelper.getTestManagementThemedColor('background_secondary', this.themeState.currentTheme))
              .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_secondary', this.themeState.currentTheme))
              .onClick(() => {
                this.cancelAutoCheck('自动检查已停止');
              })
          }
        }
        .width('100%')

        Text(this.autoCheckProgressText.length > 0 ? this.autoCheckProgressText : '等待自动检查')
          .fontSize(12)
          .fontFamily(this.appFontFamily)
          .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_secondary', this.themeState.currentTheme))
          .maxLines(2)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
          .width('100%')

        Scroll() {
          Column({ space: 8 }) {
            ForEach(this.getAutoCheckPanelReports(), (report: SourceAutoCheckSiteReport) => {
              this.buildAutoCheckSiteReport(report)
            }, (report: SourceAutoCheckSiteReport) => `${report.siteId}_${report.workflowResults.length}_${report.score}_${report.successCount}`)
          }
          .width('100%')
        }
        .width('100%')
        .height(this.getAutoCheckPanelReports().length > 0 ? 210 : 40)
        .scrollBar(BarState.Auto)
      }
      .width('100%')
      .padding(10)
      .backgroundColor(SettingsPanelSurfaceHelper.getBackground(this.themeState.currentTheme))
      .borderRadius(SettingsPanelSurfaceHelper.getRadius(this.themeState.currentTheme))
    }
  }

  @Builder
  private buildSiteOptionButton(option: SourceEditorSiteOption) {
    Button() {
      Row({ space: 4 }) {
        if (this.normalizeSiteBaseUrl(option.baseUrl) === this.normalizeSiteBaseUrl(this.getAutoCheckSelectedSiteBaseUrl())) {
          SymbolGlyph($r('sys.symbol.circle_fill'))
            .fontSize(12)
            .fontColor([ThemeAwareHelper.getTestManagementThemedColor('text_white', this.themeState.currentTheme)])
        }
        Text(option.label)
          .fontSize(12)
          .fontFamily(this.appFontFamily)
          .fontColor(this.normalizeSiteBaseUrl(option.baseUrl) === this.normalizeSiteBaseUrl(this.getAutoCheckSelectedSiteBaseUrl()) ? ThemeAwareHelper.getTestManagementThemedColor('text_white', this.themeState.currentTheme) : ThemeAwareHelper.getTestManagementThemedColor('text_secondary', this.themeState.currentTheme))
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
      }
      .height(30)
      .constraintSize({ maxWidth: 156 })
    }
    .height(30)
    .padding({ left: 10, right: 10 })
    .borderRadius(8)
    .backgroundColor(this.normalizeSiteBaseUrl(option.baseUrl) === this.normalizeSiteBaseUrl(this.getAutoCheckSelectedSiteBaseUrl()) ? ThemeAwareHelper.getTestManagementThemedColor('accent_primary', this.themeState.currentTheme) : ThemeAwareHelper.getTestManagementThemedColor('background_secondary', this.themeState.currentTheme))
    .enabled(!this.autoCheckRunning)
    .onClick(() => {
      this.switchTestSite(option);
    })
  }

  @Builder
  private buildSiteSwitcher() {
    if (this.siteOptions.length > 1) {
      Scroll() {
        Row({ space: 8 }) {
          SymbolGlyph($r('sys.symbol.swap'))
            .fontSize(14)
            .fontColor([ThemeAwareHelper.getTestManagementThemedColor('text_secondary', this.themeState.currentTheme)])
          ForEach(this.siteOptions, (option: SourceEditorSiteOption) => {
            this.buildSiteOptionButton(option)
          }, (option: SourceEditorSiteOption) => option.id)
        }
        .height(30)
      }
      .width('100%')
      .height(30)
      .scrollable(ScrollDirection.Horizontal)
      .scrollBar(BarState.Off)
    }
  }

  @Builder
  private buildTaskButton(option: SourceEditorTaskOption) {
    Button() {
      Text(option.label)
        .fontSize(12)
        .fontFamily(this.appFontFamily)
        .fontColor(this.taskType === option.taskType ? ThemeAwareHelper.getTestManagementThemedColor('text_white', this.themeState.currentTheme) : ThemeAwareHelper.getTestManagementThemedColor('text_secondary', this.themeState.currentTheme))
        .maxLines(1)
        .textAlign(TextAlign.Center)
    }
    .width(58)
    .height(32)
    .borderRadius(8)
    .backgroundColor(this.taskType === option.taskType ? ThemeAwareHelper.getTestManagementThemedColor('accent_primary', this.themeState.currentTheme) : ThemeAwareHelper.getTestManagementThemedColor('background_secondary', this.themeState.currentTheme))
    .onClick(() => {
      this.handleTaskTypeChange(option.taskType);
    })
  }

  @Builder
  private buildActionTextButton(label: string, width: number, onClick: () => void) {
    Button() {
      Text(label)
        .fontSize(12)
        .fontFamily(this.appFontFamily)
        .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_secondary', this.themeState.currentTheme))
        .maxLines(1)
        .textAlign(TextAlign.Center)
    }
    .width(width)
    .height(32)
    .borderRadius(8)
    .backgroundColor(ThemeAwareHelper.getTestManagementThemedColor('background_secondary', this.themeState.currentTheme))
    .onClick(() => {
      onClick();
    })
  }

  @Builder
  private buildToolbar() {
    Column({ space: 8 }) {
      Row({ space: 8 }) {
        TextInput({ text: this.getToolbarUrlText(), placeholder: 'https://example.com' })
          .layoutWeight(1)
          .height(38)
          .fontSize(13)
          .enabled(!this.autoCheckRunning)
          .onChange((value: string) => {
            this.handleTestUrlChange(value);
          })
        Button() {
          SymbolGlyph($r('sys.symbol.arrow_clockwise'))
            .fontSize(16)
            .fontColor([ThemeAwareHelper.getTestManagementThemedColor('text_white', this.themeState.currentTheme)])
        }
        .width(38)
        .height(38)
        .borderRadius(8)
        .backgroundColor(ThemeAwareHelper.getTestManagementThemedColor('accent_primary', this.themeState.currentTheme))
        .enabled(!this.autoCheckRunning)
        .onClick(() => {
          this.loadTestUrl();
        })
      }
      .width('100%')

      this.buildSiteSwitcher()

      Scroll() {
        Row({ space: 8 }) {
          ForEach(this.getTaskOptions(), (option: SourceEditorTaskOption) => {
            this.buildTaskButton(option)
          }, (option: SourceEditorTaskOption) => option.label)

          this.buildActionTextButton('修复DOM', 78, (): void => {
            sourceEditorInspectorStateManager.markCurrentWorkflowAbnormal();
            this.applyGuideSnapshot(true);
          })
          this.buildActionTextButton('检查器', 74, (): void => {
            void this.toggleFloatingInspector();
          })
        }
        .height(32)
      }
      .width('100%')
      .height(32)
      .scrollable(ScrollDirection.Horizontal)
      .scrollBar(BarState.Off)
    }
    .width('100%')
    .padding(10)
    .backgroundColor(SettingsPanelSurfaceHelper.getBackground(this.themeState.currentTheme))
    .borderRadius(SettingsPanelSurfaceHelper.getRadius(this.themeState.currentTheme))
  }

  @Builder
  private buildAutoCheckRecommendationPreview(report: SourceAutoCheckSiteReport) {
    Column({ space: 12 }) {
      Row({ space: 8 }) {
        SymbolGlyph($r('sys.symbol.checkmark_circle'))
          .fontSize(18)
          .fontColor([ThemeAwareHelper.getTestManagementThemedColor('accent_primary', this.themeState.currentTheme)])
        Text('推荐源站')
          .fontSize(16)
          .fontWeight(FontWeight.Medium)
          .fontFamily(this.appFontFamily)
          .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_primary', this.themeState.currentTheme))
        Blank()
        Button('应用推荐')
          .height(30)
          .fontSize(12)
          .fontFamily(this.appFontFamily)
          .backgroundColor(ThemeAwareHelper.getTestManagementThemedColor('accent_primary', this.themeState.currentTheme))
          .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_white', this.themeState.currentTheme))
          .onClick(() => {
            this.applyAutoCheckRecommendation();
          })
      }
      .width('100%')

      Column({ space: 6 }) {
        Text(report.siteLabel)
          .fontSize(18)
          .fontWeight(FontWeight.Medium)
          .fontFamily(this.appFontFamily)
          .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_primary', this.themeState.currentTheme))
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
        Text(report.siteBaseUrl)
          .fontSize(12)
          .fontFamily(this.appFontFamily)
          .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_secondary', this.themeState.currentTheme))
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
      }
      .width('100%')
      .alignItems(HorizontalAlign.Start)

      Row({ space: 8 }) {
        Text(`${report.successCount}/${report.totalCount} 通过`)
          .fontSize(13)
          .fontFamily(this.appFontFamily)
          .fontColor(this.getAutoCheckSiteToneColor(report))
          .layoutWeight(1)
        Text(`${report.score}分`)
          .fontSize(13)
          .fontFamily(this.appFontFamily)
          .fontColor(this.getAutoCheckSiteToneColor(report))
        Text(`${Math.ceil(report.durationMs / 1000)}秒`)
          .fontSize(13)
          .fontFamily(this.appFontFamily)
          .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_secondary', this.themeState.currentTheme))
      }
      .width('100%')

      Scroll() {
        Column({ space: 8 }) {
          ForEach(report.workflowResults, (result: SourceAutoCheckWorkflowResult) => {
            this.buildAutoCheckWorkflowResult(result)
          }, (result: SourceAutoCheckWorkflowResult) => `recommended_${result.siteId}_${result.workflowKey}`)
        }
        .width('100%')
      }
      .width('100%')
      .layoutWeight(1)
      .scrollBar(BarState.Auto)
    }
    .width('100%')
    .height('100%')
    .padding(16)
    .backgroundColor(ThemeAwareHelper.getTestManagementThemedColor('background_secondary', this.themeState.currentTheme))
  }

  @Builder
  private buildWebPanel() {
    Stack() {
      Web({ src: 'about:blank', controller: this.webController })
        .width('100%')
        .height('100%')
        .javaScriptAccess(true)
        .domStorageAccess(true)
        .mixedMode(MixedMode.All)
        .onPageBegin((event) => {
          this.handleWebPageBegin(event.url);
        })
        .onPageEnd((event) => {
          this.handleWebPageEnd(event.url);
        })
        .onProgressChange((event) => {
          this.handleWebProgress(event.newProgress);
        })
        .onConsole((event) => {
          if (event && event.message) {
            logger.debug(TAG, `Web Console: ${event.message.getMessage()}`);
          }
          return false;
        })
        .onErrorReceive((event) => {
          const errorInfo: string = event.error.getErrorInfo();
          const errorCode: number = event.error.getErrorCode();
          const requestUrl: string = event.request.getRequestUrl();
          const isMainFrame: boolean = event.request.isMainFrame();
          this.handleWebResourceError(errorCode, errorInfo, requestUrl, isMainFrame);
        })
        .javaScriptProxy({
          object: {
            onDomSelected: (payload: string) => {
              this.onDomSelected(payload);
            }
          },
          name: 'sourceEditorBridge',
          methodList: ['onDomSelected'],
          controller: this.webController
        })

      if (this.isLoading) {
        Column({ space: 8 }) {
          LoadingProgress()
            .width(32)
            .height(32)
          Text('加载中')
            .fontSize(12)
            .fontFamily(this.appFontFamily)
            .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_secondary', this.themeState.currentTheme))
        }
        .width('100%')
        .height('100%')
        .justifyContent(FlexAlign.Center)
        .alignItems(HorizontalAlign.Center)
        .backgroundColor(ThemeAwareHelper.getTestManagementThemedColor('background_secondary', this.themeState.currentTheme))
      }

      if (this.shouldShowAutoCheckRecommendationPreview()) {
        this.buildAutoCheckRecommendationPreview(this.getRecommendedAutoCheckSiteReportOrEmpty())
      }
    }
    .width('100%')
    .layoutWeight(1)
    .clip(true)
    .borderRadius(8)
    .border({
      width: 1,
      color: ThemeAwareHelper.getTestManagementThemedColor('divider', this.themeState.currentTheme)
    })
  }

}
