/**
 * 图源结构化诊断类型
 */

export enum SourceDiagnosticLevel {
  INFO = 'info',
  WARN = 'warn',
  ERROR = 'error'
}

export enum SourceDiagnosticEventKind {
  WORKFLOW = 'workflow',
  ACTION = 'action',
  WEBVIEW = 'webview',
  SELECTOR = 'selector',
  SCRIPT = 'script',
  NETWORK = 'network'
}

export interface SourceDiagnosticEvent {
  id: string;
  traceId: string;
  timestamp: number;
  level: SourceDiagnosticLevel;
  kind: SourceDiagnosticEventKind;
  sourceId: number;
  sourcePkg: string;
  sourceName: string;
  workflowName: string;
  actionIndex: number;
  actionType: string;
  currentUrl: string;
  message: string;
  details: string;
}

export interface SelectorTrace {
  selector: string;
  matchedCount: number;
  sampleText: string;
  sampleHtml: string;
}

export interface ScriptTrace {
  codePreview: string;
  resultPreview: string;
  errorMessage: string;
}

export interface ActionExecutionTrace {
  traceId: string;
  actionIndex: number;
  actionType: string;
  actionDescription: string;
  startTime: number;
  endTime: number;
  duration: number;
  success: boolean;
  currentUrl: string;
  errorMessage: string;
  dataPreview: string;
  variablesPreview: string;
  selectorTrace?: SelectorTrace;
  scriptTrace?: ScriptTrace;
}

export interface WorkflowExecutionTrace {
  traceId: string;
  workflowName: string;
  startTime: number;
  endTime: number;
  duration: number;
  success: boolean;
  actionCount: number;
  errorMessage: string;
  actions: ActionExecutionTrace[];
}

export interface SourceExecutionTrace {
  traceId: string;
  sourceId: number;
  sourcePkg: string;
  sourceName: string;
  workflowName: string;
  paramsPreview: string;
  startTime: number;
  endTime: number;
  duration: number;
  success: boolean;
  errorMessage: string;
  workflows: WorkflowExecutionTrace[];
  events: SourceDiagnosticEvent[];
}

