/**
 * 漫匣交互式图源编辑器
 */

import { common } from '@kit.AbilityKit';
import { BusinessError } from '@kit.BasicServicesKit';
import { webview } from '@kit.ArkWeb';
import { HdsNavDestination } from '@kit.UIDesignKit';
import { logger } from '../Utils/Logger';
import { SafeUtils } from '../Utils/SafeUtils';
import { AppFloatingWindowConfig, WindowManager } from '../Utils/WindowManager';
import { ThemeAwareHelper, ThemeAwareState } from '../Framework/Components/ThemeAware';
import { ThemeManager, ThemeType } from '../Framework/Managers/ThemeManager';
import { FontAwareHelper, FontAwareState } from '../Framework/Components/FontAware';
import { SharedPageBackgroundLayer } from '../Framework/Components/SharedPageBackgroundLayer';
import { GlobalBackgroundLayerMode } from '../Framework/Components/GlobalBackgroundLayer';
import { SettingsImmersiveTitleBar } from './settings/SettingsImmersiveTitleBar';
import { SettingsImmersiveTitleActionItem, SettingsPageTitleBarManager } from './settings/SettingsPageTitleBarManager';
import { SettingsPanelSurfaceHelper } from './settings/SettingsPanelSurfaceHelper';
import { interactiveSourceEditorService } from '../Framework/SourceEditor/InteractiveSourceEditorService';
import {
  SourceEditorInspectorSnapshot,
  sourceEditorInspectorStateManager
} from '../Framework/SourceEditor/SourceEditorInspectorStateManager';
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
} from '../Framework/SourceEditor/SourceEditorTypes';

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

interface SourceEditorTaskOption {
  taskType: SourceEditorTaskType;
  label: string;
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
  @State isLoading: boolean = true;
  @State pickerInjected: boolean = false;
  @State inspectorActive: boolean = false;
  @State editorMode: SourceEditorMode = SourceEditorMode.SIMPLE;
  @State taskType: SourceEditorTaskType = SourceEditorTaskType.SEARCH;

  private componentId: string = `SourceInteractiveEditorPage_${Date.now()}`;
  private themeManager: ThemeManager = ThemeManager.getInstance();
  private webController: webview.WebviewController = new webview.WebviewController();
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
        createNew: true
      };
      const draft: SourceEditorDraft = await interactiveSourceEditorService.createDraft(pageParams);
      this.draft = draft;
      sourceEditorInspectorStateManager.startGuide(draft, draft.taskType);
      this.syncDraftState(draft);
      this.applyGuideSnapshot(true);
      this.ensureInitialTargetLoaded();
      void this.openFloatingInspector();
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
    if (draft.lastSelection) {
      this.selectedSummary = `${draft.lastSelection.tagName} · ${draft.lastSelection.cssSelector} · ${draft.lastSelection.matchedCount}`;
    }
    this.refreshFloatingInspectorState();
  }

  private refreshFloatingInspectorState(): void {
    sourceEditorInspectorStateManager.updateDraft(this.draft, this.selectedSummary, this.saveMessage);
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
    this.mainFrameLoaded = false;
    this.workflowPreviewRetryCount = 0;
    this.lastCommittedLoadUrl = url;
    this.lastLoadedGuideUrl = url;
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
    if (this.isInspectableUrl(url)) {
      this.mainFrameLoaded = true;
      this.lastCommittedLoadUrl = url;
      this.lastLoadedGuideUrl = url;
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
        TextInput({ text: this.testUrl, placeholder: 'https://example.com' })
          .layoutWeight(1)
          .height(38)
          .fontSize(13)
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
        .onClick(() => {
          this.loadTestUrl();
        })
      }
      .width('100%')

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
