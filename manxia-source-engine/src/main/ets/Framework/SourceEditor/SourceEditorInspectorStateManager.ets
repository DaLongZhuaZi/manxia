/**
 * 交互式图源编辑器小窗状态与工作流向导
 */

import { SafeUtils } from 'manxia_core/src/main/ets/Utils/SafeUtils';
import { logger } from 'manxia_core/src/main/ets/Utils/Logger';
import {
  Action,
  ActionType,
  ExtractAction,
  NavigateAction,
  ScriptAction,
  WaitAction
} from '../WebView/MangaSourceTypes';
import {
  DomSelectionSnapshot,
  GeneratedSelectorCandidate,
  RuleFieldMapping,
  SourceEditorDraft,
  SourceEditorGuidePhase,
  SourceEditorMode,
  SourceEditorSelectionAssessment,
  SourceEditorTaskType,
  SourceEditorWorkflowGuideStep,
  SourceEditorWorkflowPreview,
  SourceEditorWorkflowPreviewStatus
} from './SourceEditorTypes';

const DEFAULT_SEARCH_KEYWORD: string = 'test';
const TAG: string = 'SourceEditorInspectorStateManager';

export const SOURCE_EDITOR_INSPECTOR_SNAPSHOT_JSON_KEY: string = 'source_editor_inspector_snapshot_json';
export const SOURCE_EDITOR_INSPECTOR_SNAPSHOT_SIGNAL_KEY: string = 'source_editor_inspector_snapshot_signal';

interface SourceEditorGuideRawMetadata {
  id?: string;
  name?: string;
  baseUrl?: string;
}

interface SourceEditorGuideRawWorkflowObject {
  description?: string;
  supportsPagination?: boolean;
  type?: string;
  actions?: Action[];
}

interface SourceEditorGuideRawWorkflows {
  search?: Object;
  getMangaDetail?: Object;
  getChapterList?: Object;
  getPageList?: Object;
}

interface SourceEditorGuideRawConfig {
  metadata?: SourceEditorGuideRawMetadata;
  workflows?: SourceEditorGuideRawWorkflows;
}

export interface SourceEditorInspectorSnapshot {
  renderVersion: number;
  hasDraft: boolean;
  sourceName: string;
  sourcePkg: string;
  testUrl: string;
  taskType: SourceEditorTaskType;
  taskTypeText: string;
  mode: SourceEditorMode;
  modeText: string;
  selectedSummary: string;
  saveMessage: string;
  generatedWorkflowJson: string;
  configPreview: string;
  fieldMappings: RuleFieldMapping[];
  selection: DomSelectionSnapshot | null;
  guidePhase: SourceEditorGuidePhase;
  guidePhaseText: string;
  guideIndex: number;
  workflowCount: number;
  selectionRequestVersion: number;
  currentStep: SourceEditorWorkflowGuideStep | null;
}

export function createEmptySourceEditorWorkflowPreview(): SourceEditorWorkflowPreview {
  const preview: SourceEditorWorkflowPreview = {
    status: SourceEditorWorkflowPreviewStatus.WAITING,
    summary: '等待页面加载',
    detail: '',
    selectorCount: 0,
    scriptCount: 0,
    sampleTitle: '',
    sampleUrl: '',
    sampleCover: '',
    errorMessage: ''
  };
  return preview;
}

export function createEmptySourceEditorSelectionAssessment(): SourceEditorSelectionAssessment {
  const assessment: SourceEditorSelectionAssessment = {
    score: 0,
    title: '等待选择',
    message: '点击“不正常”后，在页面上选择当前工作流需要的 DOM。',
    detail: '',
    recommendedSelector: '',
    matchedCount: 0,
    sampleTitle: '',
    sampleUrl: '',
    sampleCover: ''
  };
  return assessment;
}

export function createEmptySourceEditorInspectorSnapshot(): SourceEditorInspectorSnapshot {
  const fieldMappings: RuleFieldMapping[] = [];
  const snapshot: SourceEditorInspectorSnapshot = {
    renderVersion: 0,
    hasDraft: false,
    sourceName: '图源编辑器',
    sourcePkg: '',
    testUrl: '',
    taskType: SourceEditorTaskType.SEARCH,
    taskTypeText: '搜索',
    mode: SourceEditorMode.SIMPLE,
    modeText: '普通',
    selectedSummary: '未选择元素',
    saveMessage: '',
    generatedWorkflowJson: '',
    configPreview: '',
    fieldMappings: fieldMappings,
    selection: null,
    guidePhase: SourceEditorGuidePhase.PREVIEW,
    guidePhaseText: '检查当前工作流',
    guideIndex: 0,
    workflowCount: 0,
    selectionRequestVersion: 0,
    currentStep: null
  };
  return snapshot;
}

export class SourceEditorInspectorStateManager {
  private static instance: SourceEditorInspectorStateManager | null = null;

  private currentDraft: SourceEditorDraft | null = null;
  private currentDraftId: string = '';
  private selectedSummary: string = '未选择元素';
  private saveMessage: string = '';
  private renderVersion: number = 0;
  private guideSteps: SourceEditorWorkflowGuideStep[] = [];
  private currentGuideIndex: number = 0;
  private guidePhase: SourceEditorGuidePhase = SourceEditorGuidePhase.PREVIEW;
  private selectionRequestVersion: number = 0;

  private constructor() {}

  public static getInstance(): SourceEditorInspectorStateManager {
    if (!SourceEditorInspectorStateManager.instance) {
      SourceEditorInspectorStateManager.instance = new SourceEditorInspectorStateManager();
    }
    return SourceEditorInspectorStateManager.instance;
  }

  public updateDraft(draft: SourceEditorDraft | null, selectedSummary: string, saveMessage: string): void {
    const previousDraftId: string = this.currentDraftId;
    this.currentDraft = draft;
    this.currentDraftId = draft === null ? '' : draft.draftId;
    this.selectedSummary = selectedSummary;
    this.saveMessage = saveMessage;
    if (draft !== null && (previousDraftId !== draft.draftId || this.guideSteps.length <= 0)) {
      this.rebuildGuide(draft, draft.taskType);
    }
    this.bumpRenderVersion();
  }

  public startGuide(draft: SourceEditorDraft, preferredTaskType: SourceEditorTaskType): void {
    this.currentDraft = draft;
    this.currentDraftId = draft.draftId;
    this.rebuildGuide(draft, preferredTaskType);
    this.bumpRenderVersion();
  }

  public updateSaveMessage(message: string): void {
    this.saveMessage = message;
    this.bumpRenderVersion();
  }

  public resetGuide(reason: string): void {
    this.currentDraft = null;
    this.currentDraftId = '';
    this.selectedSummary = '未选择元素';
    this.saveMessage = '';
    this.guideSteps = [];
    this.currentGuideIndex = 0;
    this.guidePhase = SourceEditorGuidePhase.PREVIEW;
    this.selectionRequestVersion = 0;
    this.bumpRenderVersion();
    logger.debug(TAG, `图源检查器状态已重置: ${reason}`);
  }

  public getCurrentDraft(): SourceEditorDraft | null {
    return this.currentDraft;
  }

  public getCurrentStep(): SourceEditorWorkflowGuideStep | null {
    const step = this.getMutableCurrentStep();
    return step === null ? null : this.cloneGuideStep(step);
  }

  public selectWorkflow(taskType: SourceEditorTaskType): void {
    for (let i = 0; i < this.guideSteps.length; i++) {
      if (this.guideSteps[i].taskType === taskType) {
        this.currentGuideIndex = i;
        this.guidePhase = SourceEditorGuidePhase.PREVIEW;
        this.guideSteps[i].preview = createEmptySourceEditorWorkflowPreview();
        this.bumpRenderVersion();
        return;
      }
    }
  }

  public updateCurrentTargetUrl(url: string): void {
    const step = this.getMutableCurrentStep();
    if (step === null) {
      return;
    }
    step.targetUrl = url;
    this.bumpRenderVersion();
  }

  public updateWorkflowPreview(preview: SourceEditorWorkflowPreview): void {
    const step = this.getMutableCurrentStep();
    if (step === null) {
      return;
    }
    step.preview = this.clonePreview(preview);
    this.bumpRenderVersion();
  }

  public markCurrentWorkflowNormal(): void {
    const step = this.getMutableCurrentStep();
    if (step === null) {
      this.guidePhase = SourceEditorGuidePhase.COMPLETE;
      this.bumpRenderVersion();
      return;
    }
    step.completed = true;
    const nextIndex: number = this.currentGuideIndex + 1;
    if (nextIndex >= this.guideSteps.length) {
      this.guidePhase = SourceEditorGuidePhase.COMPLETE;
      this.bumpRenderVersion();
      return;
    }
    const nextStep = this.guideSteps[nextIndex];
    const nextUrl: string = step.preview.sampleUrl.length > 0 ? step.preview.sampleUrl : step.targetUrl;
    if (step.preview.sampleUrl.length > 0 && nextStep.taskType !== SourceEditorTaskType.SEARCH) {
      nextStep.targetUrl = step.preview.sampleUrl;
    } else if (nextUrl.length > 0 && (nextStep.targetUrl.length <= 0 || this.isPlaceholderUrl(nextStep.targetUrl))) {
      nextStep.targetUrl = nextUrl;
    }
    this.currentGuideIndex = nextIndex;
    this.guidePhase = SourceEditorGuidePhase.PREVIEW;
    this.bumpRenderVersion();
  }

  public moveToPreviousWorkflow(): void {
    if (this.currentGuideIndex > 0) {
      this.currentGuideIndex -= 1;
      this.guidePhase = SourceEditorGuidePhase.PREVIEW;
      this.bumpRenderVersion();
    }
  }

  public markCurrentWorkflowAbnormal(): void {
    const step = this.getMutableCurrentStep();
    if (step !== null) {
      step.selectionAssessment = createEmptySourceEditorSelectionAssessment();
    }
    this.guidePhase = SourceEditorGuidePhase.NEED_SELECTION;
    this.selectionRequestVersion += 1;
    this.bumpRenderVersion();
  }

  public updateSelectionAssessment(selection: DomSelectionSnapshot): void {
    const step = this.getMutableCurrentStep();
    if (step === null) {
      return;
    }
    step.selectionAssessment = this.buildSelectionAssessment(step.taskType, selection);
    this.guidePhase = SourceEditorGuidePhase.SELECTION_REVIEW;
    this.bumpRenderVersion();
  }

  public getSnapshot(): SourceEditorInspectorSnapshot {
    return this.buildSnapshot();
  }

  private bumpRenderVersion(): void {
    this.renderVersion += 1;
    this.publishSnapshot();
  }

  private publishSnapshot(): void {
    try {
      const snapshot: SourceEditorInspectorSnapshot = this.buildSnapshot();
      AppStorage.setOrCreate<string>(SOURCE_EDITOR_INSPECTOR_SNAPSHOT_JSON_KEY, JSON.stringify(snapshot));
      AppStorage.setOrCreate<number>(SOURCE_EDITOR_INSPECTOR_SNAPSHOT_SIGNAL_KEY, snapshot.renderVersion);
    } catch (error) {
      logger.warn(TAG, `发布图源检查器快照失败: ${String(error)}`);
    }
  }

  private buildSnapshot(): SourceEditorInspectorSnapshot {
    const draft = this.currentDraft;
    if (draft === null) {
      const emptySnapshot: SourceEditorInspectorSnapshot = createEmptySourceEditorInspectorSnapshot();
      emptySnapshot.renderVersion = this.renderVersion;
      emptySnapshot.saveMessage = this.saveMessage;
      emptySnapshot.guidePhase = this.guidePhase;
      emptySnapshot.guidePhaseText = this.getGuidePhaseText();
      emptySnapshot.selectionRequestVersion = this.selectionRequestVersion;
      return emptySnapshot;
    }

    const currentStep = this.getMutableCurrentStep();
    const snapshot: SourceEditorInspectorSnapshot = {
      renderVersion: this.renderVersion,
      hasDraft: true,
      sourceName: draft.sourceName,
      sourcePkg: draft.sourcePkg,
      testUrl: currentStep === null ? draft.testUrl : currentStep.targetUrl,
      taskType: currentStep === null ? draft.taskType : currentStep.taskType,
      taskTypeText: currentStep === null ? this.getTaskTypeText(draft.taskType) : currentStep.label,
      mode: draft.mode,
      modeText: draft.mode === SourceEditorMode.ADVANCED ? '高级' : '普通',
      selectedSummary: this.selectedSummary,
      saveMessage: this.saveMessage,
      generatedWorkflowJson: draft.generatedWorkflowJson,
      configPreview: draft.configJson,
      fieldMappings: this.cloneFieldMappings(draft.fieldMappings),
      selection: draft.lastSelection ? this.cloneSelection(draft.lastSelection) : null,
      guidePhase: this.guidePhase,
      guidePhaseText: this.getGuidePhaseText(),
      guideIndex: this.currentGuideIndex,
      workflowCount: this.guideSteps.length,
      selectionRequestVersion: this.selectionRequestVersion,
      currentStep: currentStep === null ? null : this.cloneGuideStep(currentStep)
    };
    return snapshot;
  }

  private rebuildGuide(draft: SourceEditorDraft, preferredTaskType: SourceEditorTaskType): void {
    const rawConfig: SourceEditorGuideRawConfig = this.parseRawConfig(draft.configJson);
    const baseUrl: string = this.resolveBaseUrl(rawConfig, draft.testUrl);
    const steps: SourceEditorWorkflowGuideStep[] = [];
    steps.push(this.buildGuideStep(SourceEditorTaskType.SEARCH, rawConfig, baseUrl, draft.testUrl));
    steps.push(this.buildGuideStep(SourceEditorTaskType.DETAIL, rawConfig, baseUrl, draft.testUrl));
    steps.push(this.buildGuideStep(SourceEditorTaskType.CHAPTERS, rawConfig, baseUrl, draft.testUrl));
    steps.push(this.buildGuideStep(SourceEditorTaskType.PAGES, rawConfig, baseUrl, draft.testUrl));
    this.guideSteps = steps;
    this.currentGuideIndex = this.findStepIndex(preferredTaskType);
    this.guidePhase = SourceEditorGuidePhase.PREVIEW;
    this.selectionRequestVersion = 0;
  }

  private parseRawConfig(configJson: string): SourceEditorGuideRawConfig {
    try {
      return SafeUtils.parseObj(configJson) as SourceEditorGuideRawConfig;
    } catch (_error) {
      const workflows: SourceEditorGuideRawWorkflows = {};
      const config: SourceEditorGuideRawConfig = {
        workflows: workflows
      };
      return config;
    }
  }

  private resolveBaseUrl(config: SourceEditorGuideRawConfig, fallbackUrl: string): string {
    if (config.metadata && config.metadata.baseUrl && config.metadata.baseUrl.length > 0) {
      return config.metadata.baseUrl;
    }
    return this.resolveUrlOrigin(fallbackUrl);
  }

  private resolveUrlOrigin(url: string): string {
    const trimmed: string = url.trim();
    if (trimmed.length <= 0) {
      return '';
    }
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

  private buildGuideStep(
    taskType: SourceEditorTaskType,
    config: SourceEditorGuideRawConfig,
    baseUrl: string,
    fallbackUrl: string
  ): SourceEditorWorkflowGuideStep {
    const workflow = this.getWorkflowByTaskType(config, taskType);
    const actions: Action[] = this.getWorkflowActions(workflow);
    const waitSelector: string = this.findWaitSelector(actions);
    const extractSelector: string = this.findExtractSelector(actions);
    const scriptCode: string = this.findPreviewScriptCode(actions);
    const targetUrl: string = this.resolveWorkflowTargetUrl(actions, baseUrl, fallbackUrl, taskType);
    const step: SourceEditorWorkflowGuideStep = {
      taskType: taskType,
      label: this.getTaskTypeText(taskType),
      description: this.getTaskDescription(taskType),
      expectedDomLabel: this.getExpectedDomLabel(taskType),
      selectionInstruction: this.getSelectionInstruction(taskType),
      targetUrl: targetUrl,
      workflowExists: actions.length > 0,
      actionCount: actions.length,
      waitSelector: waitSelector,
      extractSelector: extractSelector,
      scriptCode: scriptCode,
      completed: false,
      preview: createEmptySourceEditorWorkflowPreview(),
      selectionAssessment: createEmptySourceEditorSelectionAssessment()
    };
    return step;
  }

  private getWorkflowByTaskType(config: SourceEditorGuideRawConfig, taskType: SourceEditorTaskType): Object | undefined {
    if (!config.workflows) {
      return undefined;
    }
    if (taskType === SourceEditorTaskType.SEARCH) {
      return config.workflows.search;
    }
    if (taskType === SourceEditorTaskType.DETAIL) {
      return config.workflows.getMangaDetail;
    }
    if (taskType === SourceEditorTaskType.CHAPTERS) {
      return config.workflows.getChapterList;
    }
    return config.workflows.getPageList;
  }

  private getWorkflowActions(workflow: Object | undefined): Action[] {
    if (!workflow) {
      return [];
    }
    if (Array.isArray(workflow)) {
      return workflow as Action[];
    }
    const workflowObject: SourceEditorGuideRawWorkflowObject = workflow as SourceEditorGuideRawWorkflowObject;
    if (workflowObject.actions && Array.isArray(workflowObject.actions)) {
      return workflowObject.actions;
    }
    return [];
  }

  private findWaitSelector(actions: Action[]): string {
    for (let i = 0; i < actions.length; i++) {
      const action = actions[i];
      if (action.type === ActionType.WAIT) {
        const waitAction = action as WaitAction;
        return waitAction.selector ? waitAction.selector : '';
      }
    }
    return '';
  }

  private findExtractSelector(actions: Action[]): string {
    for (let i = 0; i < actions.length; i++) {
      const action = actions[i];
      if (action.type === ActionType.EXTRACT) {
        const extractAction = action as ExtractAction;
        return extractAction.selector ? extractAction.selector : '';
      }
    }
    return '';
  }

  private findPreviewScriptCode(actions: Action[]): string {
    for (let i = actions.length - 1; i >= 0; i--) {
      const action = actions[i];
      if (action.type === ActionType.SCRIPT) {
        const scriptAction = action as ScriptAction;
        return scriptAction.code;
      }
    }
    return '';
  }

  private resolveWorkflowTargetUrl(
    actions: Action[],
    baseUrl: string,
    fallbackUrl: string,
    taskType: SourceEditorTaskType
  ): string {
    for (let i = 0; i < actions.length; i++) {
      const action = actions[i];
      if (action.type === ActionType.NAVIGATE) {
        const navigateAction = action as NavigateAction;
        if (navigateAction.url === '{{scriptResult}}') {
          const derivedUrl: string = this.deriveUrlFromPreviousScript(actions, i, baseUrl, taskType);
          if (derivedUrl.length > 0) {
            return derivedUrl;
          }
        }
        return this.resolveTemplateUrl(navigateAction.url, baseUrl, fallbackUrl);
      }
    }
    if (taskType === SourceEditorTaskType.SEARCH && baseUrl.length > 0) {
      return baseUrl;
    }
    return fallbackUrl.length > 0 ? fallbackUrl : baseUrl;
  }

  private deriveUrlFromPreviousScript(actions: Action[], navigateIndex: number, baseUrl: string, taskType: SourceEditorTaskType): string {
    for (let i = navigateIndex - 1; i >= 0; i--) {
      const action = actions[i];
      if (action.type !== ActionType.SCRIPT) {
        continue;
      }
      const scriptAction = action as ScriptAction;
      const code = scriptAction.code;
      if (code.indexOf('?search=') >= 0) {
        return `${baseUrl}/?search=${DEFAULT_SEARCH_KEYWORD}&start=0`;
      }
      if (code.indexOf('/hot?start=') >= 0) {
        return `${baseUrl}/hot?start=0`;
      }
      if (code.indexOf('/?start=') >= 0) {
        return `${baseUrl}/?start=0`;
      }
      if (code.indexOf("{{baseUrl}}/' + chapterId") >= 0) {
        return '';
      }
    }
    if (taskType === SourceEditorTaskType.SEARCH && baseUrl.length > 0) {
      return baseUrl;
    }
    return '';
  }

  private resolveTemplateUrl(url: string, baseUrl: string, fallbackUrl: string): string {
    let output: string = url;
    output = output.split('{{baseUrl}}').join(baseUrl);
    output = output.split('{{page}}').join('1');
    output = output.split('{{searchKeyword}}').join(DEFAULT_SEARCH_KEYWORD);
    output = output.split('{{query}}').join(DEFAULT_SEARCH_KEYWORD);
    output = output.split('{{mangaId}}').join('');
    output = output.split('{{chapterId}}').join('');
    output = output.split('{{scriptResult}}').join('');
    if (output.indexOf('{{') >= 0 || output.length <= 0) {
      return fallbackUrl.length > 0 ? fallbackUrl : baseUrl;
    }
    return output;
  }

  private findStepIndex(taskType: SourceEditorTaskType): number {
    for (let i = 0; i < this.guideSteps.length; i++) {
      if (this.guideSteps[i].taskType === taskType) {
        return i;
      }
    }
    return 0;
  }

  private getMutableCurrentStep(): SourceEditorWorkflowGuideStep | null {
    if (this.currentGuideIndex < 0 || this.currentGuideIndex >= this.guideSteps.length) {
      return null;
    }
    return this.guideSteps[this.currentGuideIndex];
  }

  private getTaskTypeText(taskType: SourceEditorTaskType): string {
    if (taskType === SourceEditorTaskType.DETAIL) {
      return '详情';
    }
    if (taskType === SourceEditorTaskType.CHAPTERS) {
      return '章节';
    }
    if (taskType === SourceEditorTaskType.PAGES) {
      return '图片';
    }
    return '搜索';
  }

  private getTaskDescription(taskType: SourceEditorTaskType): string {
    if (taskType === SourceEditorTaskType.DETAIL) {
      return '确认详情页能提取标题、封面、简介等字段';
    }
    if (taskType === SourceEditorTaskType.CHAPTERS) {
      return '确认章节或分页列表能被识别';
    }
    if (taskType === SourceEditorTaskType.PAGES) {
      return '确认图片列表能被识别';
    }
    return '确认搜索结果列表能被识别';
  }

  private getExpectedDomLabel(taskType: SourceEditorTaskType): string {
    if (taskType === SourceEditorTaskType.DETAIL) {
      return '详情主体';
    }
    if (taskType === SourceEditorTaskType.CHAPTERS) {
      return '章节列表';
    }
    if (taskType === SourceEditorTaskType.PAGES) {
      return '图片节点';
    }
    return '搜索结果条目';
  }

  private getSelectionInstruction(taskType: SourceEditorTaskType): string {
    if (taskType === SourceEditorTaskType.DETAIL) {
      return '请点选包含标题、封面或简介的详情主体区域。';
    }
    if (taskType === SourceEditorTaskType.CHAPTERS) {
      return '请点选一个章节或分页链接，最好选择列表中的一项。';
    }
    if (taskType === SourceEditorTaskType.PAGES) {
      return '请点选正文中的一张漫画图片。';
    }
    return '请点选一个完整搜索结果条目，不要只点封面的一角。';
  }

  private getGuidePhaseText(): string {
    if (this.guidePhase === SourceEditorGuidePhase.NEED_SELECTION) {
      return '等待选择 DOM';
    }
    if (this.guidePhase === SourceEditorGuidePhase.SELECTION_REVIEW) {
      return '确认新规则';
    }
    if (this.guidePhase === SourceEditorGuidePhase.COMPLETE) {
      return '工作流检查完成';
    }
    return '检查当前工作流';
  }

  private isPlaceholderUrl(url: string): boolean {
    return url.indexOf('{{') >= 0 || url === '' || url === 'about:blank';
  }

  private buildSelectionAssessment(taskType: SourceEditorTaskType, selection: DomSelectionSnapshot): SourceEditorSelectionAssessment {
    const containerSelector: string = selection.containerSelector && selection.containerSelector.length > 0 ?
      selection.containerSelector : selection.cssSelector;
    const matchedCount: number = selection.containerMatchedCount && selection.containerMatchedCount > 0 ?
      selection.containerMatchedCount : selection.matchedCount;
    const title: string = selection.titleCandidate && selection.titleCandidate.length > 0 ?
      selection.titleCandidate : selection.text;
    const sampleUrl: string = selection.hrefCandidate && selection.hrefCandidate.length > 0 ?
      selection.hrefCandidate : selection.href;
    const sampleCover: string = selection.imageCandidate && selection.imageCandidate.length > 0 ?
      selection.imageCandidate : selection.src;
    const score: number = this.calculateSelectionScore(taskType, selection, matchedCount, title, sampleUrl, sampleCover);
    const assessment: SourceEditorSelectionAssessment = {
      score: score,
      title: score >= 70 ? '识别结果较可靠' : '需要再确认',
      message: this.buildSelectionMessage(taskType, score, matchedCount),
      detail: this.buildSelectionDetail(selection),
      recommendedSelector: containerSelector,
      matchedCount: matchedCount,
      sampleTitle: title,
      sampleUrl: sampleUrl,
      sampleCover: sampleCover
    };
    return assessment;
  }

  private calculateSelectionScore(
    taskType: SourceEditorTaskType,
    selection: DomSelectionSnapshot,
    matchedCount: number,
    title: string,
    sampleUrl: string,
    sampleCover: string
  ): number {
    let score: number = selection.itemScore ? selection.itemScore : 0;
    if (matchedCount > 1) {
      score += 18;
    }
    if (title.length > 0) {
      score += 16;
    }
    if (sampleUrl.length > 0) {
      score += 16;
    }
    if (sampleCover.length > 0) {
      score += 16;
    }
    if (selection.siblingSimilarCount && selection.siblingSimilarCount > 1) {
      score += 14;
    }
    if (taskType === SourceEditorTaskType.PAGES && sampleCover.length > 0) {
      score += 28;
    }
    if (taskType === SourceEditorTaskType.CHAPTERS && sampleUrl.length > 0) {
      score += 22;
    }
    if (taskType === SourceEditorTaskType.DETAIL && (title.length > 0 || sampleCover.length > 0)) {
      score += 18;
    }
    return Math.max(0, Math.min(100, score));
  }

  private buildSelectionMessage(taskType: SourceEditorTaskType, score: number, matchedCount: number): string {
    if (score >= 80) {
      return `${this.getTaskTypeText(taskType)}规则看起来可用，匹配 ${matchedCount} 个节点。`;
    }
    if (score >= 55) {
      return `已找到候选节点，但建议确认是否覆盖完整${this.getExpectedDomLabel(taskType)}。`;
    }
    return `当前选择可能太小或缺少关键信息，建议重新点选${this.getExpectedDomLabel(taskType)}。`;
  }

  private buildSelectionDetail(selection: DomSelectionSnapshot): string {
    const parts: string[] = [];
    const imageCount: number = selection.imageCount ? selection.imageCount : 0;
    const linkCount: number = selection.linkCount ? selection.linkCount : 0;
    const siblingCount: number = selection.siblingSimilarCount ? selection.siblingSimilarCount : 0;
    parts.push(`图片 ${imageCount}`);
    parts.push(`链接 ${linkCount}`);
    parts.push(`相邻同类 ${siblingCount}`);
    return parts.join(' · ');
  }

  private cloneFieldMappings(items: RuleFieldMapping[]): RuleFieldMapping[] {
    const mappings: RuleFieldMapping[] = [];
    for (let i = 0; i < items.length; i++) {
      const source = items[i];
      const mapping: RuleFieldMapping = {
        fieldName: source.fieldName,
        label: source.label,
        selector: source.selector,
        attribute: source.attribute,
        sampleValue: source.sampleValue
      };
      mappings.push(mapping);
    }
    return mappings;
  }

  private cloneGuideStep(step: SourceEditorWorkflowGuideStep): SourceEditorWorkflowGuideStep {
    const cloned: SourceEditorWorkflowGuideStep = {
      taskType: step.taskType,
      label: step.label,
      description: step.description,
      expectedDomLabel: step.expectedDomLabel,
      selectionInstruction: step.selectionInstruction,
      targetUrl: step.targetUrl,
      workflowExists: step.workflowExists,
      actionCount: step.actionCount,
      waitSelector: step.waitSelector,
      extractSelector: step.extractSelector,
      scriptCode: step.scriptCode,
      completed: step.completed,
      preview: this.clonePreview(step.preview),
      selectionAssessment: this.cloneAssessment(step.selectionAssessment)
    };
    return cloned;
  }

  private clonePreview(preview: SourceEditorWorkflowPreview): SourceEditorWorkflowPreview {
    const cloned: SourceEditorWorkflowPreview = {
      status: preview.status,
      summary: preview.summary,
      detail: preview.detail,
      selectorCount: preview.selectorCount,
      scriptCount: preview.scriptCount,
      sampleTitle: preview.sampleTitle,
      sampleUrl: preview.sampleUrl,
      sampleCover: preview.sampleCover,
      errorMessage: preview.errorMessage
    };
    return cloned;
  }

  private cloneAssessment(assessment: SourceEditorSelectionAssessment): SourceEditorSelectionAssessment {
    const cloned: SourceEditorSelectionAssessment = {
      score: assessment.score,
      title: assessment.title,
      message: assessment.message,
      detail: assessment.detail,
      recommendedSelector: assessment.recommendedSelector,
      matchedCount: assessment.matchedCount,
      sampleTitle: assessment.sampleTitle,
      sampleUrl: assessment.sampleUrl,
      sampleCover: assessment.sampleCover
    };
    return cloned;
  }

  private cloneSelection(selection: DomSelectionSnapshot): DomSelectionSnapshot {
    const clonedSelection: DomSelectionSnapshot = {
      tagName: selection.tagName,
      text: selection.text,
      htmlPreview: selection.htmlPreview,
      href: selection.href,
      src: selection.src,
      idValue: selection.idValue,
      className: selection.className,
      cssSelector: selection.cssSelector,
      xpath: selection.xpath,
      matchedCount: selection.matchedCount,
      candidates: this.cloneCandidates(selection.candidates),
      containerSelector: selection.containerSelector ? selection.containerSelector : '',
      containerMatchedCount: selection.containerMatchedCount ? selection.containerMatchedCount : 0,
      siblingSimilarCount: selection.siblingSimilarCount ? selection.siblingSimilarCount : 0,
      imageCount: selection.imageCount ? selection.imageCount : 0,
      linkCount: selection.linkCount ? selection.linkCount : 0,
      titleCandidate: selection.titleCandidate ? selection.titleCandidate : '',
      imageCandidate: selection.imageCandidate ? selection.imageCandidate : '',
      hrefCandidate: selection.hrefCandidate ? selection.hrefCandidate : '',
      itemScore: selection.itemScore ? selection.itemScore : 0
    };
    return clonedSelection;
  }

  private cloneCandidates(items: GeneratedSelectorCandidate[]): GeneratedSelectorCandidate[] {
    const candidates: GeneratedSelectorCandidate[] = [];
    for (let i = 0; i < items.length; i++) {
      const source = items[i];
      const candidate: GeneratedSelectorCandidate = {
        type: source.type,
        value: source.value,
        score: source.score,
        matchedCount: source.matchedCount,
        note: source.note
      };
      candidates.push(candidate);
    }
    return candidates;
  }
}

export const sourceEditorInspectorStateManager: SourceEditorInspectorStateManager =
  SourceEditorInspectorStateManager.getInstance();
