/**
 * 交互式图源编辑器类型
 */

export enum SourceEditorMode {
  SIMPLE = 'simple',
  ADVANCED = 'advanced'
}

export enum SourceEditorTaskType {
  SEARCH = 'search',
  DETAIL = 'getMangaDetail',
  CHAPTERS = 'getChapterList',
  PAGES = 'getPageList'
}

export enum SourceSaveMode {
  LOCAL_FORK = 'LOCAL_FORK',
  OVERWRITE_INSTALLED = 'OVERWRITE_INSTALLED',
  EXPORT_PACKAGE = 'EXPORT_PACKAGE'
}

export enum SourceEditorGuidePhase {
  PREVIEW = 'preview',
  NEED_SELECTION = 'needSelection',
  SELECTION_REVIEW = 'selectionReview',
  COMPLETE = 'complete'
}

export enum SourceEditorWorkflowPreviewStatus {
  WAITING = 'waiting',
  RUNNING = 'running',
  OK = 'ok',
  EMPTY = 'empty',
  ERROR = 'error'
}

export interface SourceInteractiveEditorPageParams {
  sourceId: number;
  sourceName: string;
  sourcePkg: string;
  initialUrl: string;
  createNew: boolean;
  autoRunDiagnostics?: boolean;
  autoCheckTaskId?: string;
  openAutoCheckReport?: boolean;
}

export interface SourceDiagnosticPageParams {
  sourceId: number;
  sourceName: string;
  traceId: string;
}

export interface GeneratedSelectorCandidate {
  type: string;
  value: string;
  score: number;
  matchedCount: number;
  note: string;
}

export interface DomSelectionSnapshot {
  tagName: string;
  text: string;
  htmlPreview: string;
  href: string;
  src: string;
  idValue: string;
  className: string;
  cssSelector: string;
  xpath: string;
  matchedCount: number;
  candidates: GeneratedSelectorCandidate[];
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

export interface RuleFieldMapping {
  fieldName: string;
  label: string;
  selector: string;
  attribute: string;
  sampleValue: string;
}

export interface SourceEditorDraft {
  draftId: string;
  sourceId: number;
  sourceName: string;
  sourcePkg: string;
  mode: SourceEditorMode;
  taskType: SourceEditorTaskType;
  testUrl: string;
  configJson: string;
  generatedWorkflowJson: string;
  lastSelection?: DomSelectionSnapshot;
  fieldMappings: RuleFieldMapping[];
  createTime: number;
  updateTime: number;
}

export interface SourceEditorVersionSnapshot {
  snapshotId: string;
  draftId: string;
  sourceId: number;
  sourcePkg: string;
  sourceName: string;
  configJson: string;
  createdAt: number;
  reason: string;
}

export interface SourceEditorSaveResult {
  success: boolean;
  message: string;
  sourceId: number;
  sourceName: string;
  sourcePkg: string;
  exportPath: string;
}

export interface SourceValidationResult {
  valid: boolean;
  message: string;
  warnings: string[];
}

export interface SourceEditorWorkflowPreview {
  status: SourceEditorWorkflowPreviewStatus;
  summary: string;
  detail: string;
  selectorCount: number;
  scriptCount: number;
  sampleTitle: string;
  sampleUrl: string;
  sampleCover: string;
  errorMessage: string;
}

export interface SourceEditorSelectionAssessment {
  score: number;
  title: string;
  message: string;
  detail: string;
  recommendedSelector: string;
  matchedCount: number;
  sampleTitle: string;
  sampleUrl: string;
  sampleCover: string;
}

export interface SourceEditorWorkflowGuideStep {
  taskType: SourceEditorTaskType;
  label: string;
  description: string;
  expectedDomLabel: string;
  selectionInstruction: string;
  targetUrl: string;
  workflowExists: boolean;
  actionCount: number;
  waitSelector: string;
  extractSelector: string;
  scriptCode: string;
  completed: boolean;
  preview: SourceEditorWorkflowPreview;
  selectionAssessment: SourceEditorSelectionAssessment;
}
