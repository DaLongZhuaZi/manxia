import { logger } from 'manxia_core/src/main/ets/Utils/Logger';
import {
  ActionExecutionTrace,
  SourceDiagnosticEvent,
  SourceDiagnosticEventKind,
  SourceDiagnosticLevel,
  SourceExecutionTrace,
  WorkflowExecutionTrace
} from './SourceDiagnosticTypes';

const TAG = 'SourceDiagnosticManager';
const MAX_TRACE_COUNT: number = 100;
const PREVIEW_LIMIT: number = 600;

export class SourceDiagnosticManager {
  private static instance: SourceDiagnosticManager | null = null;
  private traces: SourceExecutionTrace[] = [];
  private activeTraceIds: string[] = [];

  private constructor() {}

  public static getInstance(): SourceDiagnosticManager {
    if (!SourceDiagnosticManager.instance) {
      SourceDiagnosticManager.instance = new SourceDiagnosticManager();
    }
    return SourceDiagnosticManager.instance;
  }

  public startTrace(sourceId: number, sourcePkg: string, sourceName: string, workflowName: string, paramsPreview: string): SourceExecutionTrace {
    const now = Date.now();
    const traceId = this.buildId('trace');
    const workflow: WorkflowExecutionTrace = {
      traceId: traceId,
      workflowName: workflowName,
      startTime: now,
      endTime: 0,
      duration: 0,
      success: false,
      actionCount: 0,
      errorMessage: '',
      actions: []
    };
    const trace: SourceExecutionTrace = {
      traceId: traceId,
      sourceId: sourceId,
      sourcePkg: sourcePkg,
      sourceName: sourceName,
      workflowName: workflowName,
      paramsPreview: this.sanitize(paramsPreview),
      startTime: now,
      endTime: 0,
      duration: 0,
      success: false,
      errorMessage: '',
      workflows: [workflow],
      events: []
    };
    this.traces.unshift(trace);
    this.activeTraceIds.push(traceId);
    this.trimTraces();
    this.recordEvent(traceId, SourceDiagnosticLevel.INFO, SourceDiagnosticEventKind.WORKFLOW, -1, '', '工作流开始', workflowName, '');
    logger.info(TAG, `图源诊断开始: traceId=${traceId}, source=${sourceName}, workflow=${workflowName}`);
    return trace;
  }

  public finishTrace(traceId: string, success: boolean, errorMessage: string = ''): void {
    const trace = this.getTraceById(traceId);
    if (!trace) {
      return;
    }
    const now = Date.now();
    trace.endTime = now;
    trace.duration = Math.max(0, now - trace.startTime);
    trace.success = success;
    trace.errorMessage = this.sanitize(errorMessage);
    const workflow = this.getPrimaryWorkflow(trace);
    workflow.endTime = now;
    workflow.duration = trace.duration;
    workflow.success = success;
    workflow.errorMessage = trace.errorMessage;
    workflow.actionCount = workflow.actions.length;
    this.recordEvent(
      traceId,
      success ? SourceDiagnosticLevel.INFO : SourceDiagnosticLevel.ERROR,
      SourceDiagnosticEventKind.WORKFLOW,
      -1,
      '',
      success ? '工作流完成' : '工作流失败',
      trace.errorMessage,
      ''
    );
    this.activeTraceIds = this.activeTraceIds.filter((id: string) => id !== traceId);
  }

  public beginAction(
    traceId: string,
    actionIndex: number,
    actionType: string,
    actionDescription: string,
    currentUrl: string,
    variablesPreview: string
  ): void {
    const trace = this.getTraceById(traceId);
    if (!trace) {
      return;
    }
    const actionTrace: ActionExecutionTrace = {
      traceId: traceId,
      actionIndex: actionIndex,
      actionType: actionType,
      actionDescription: actionDescription,
      startTime: Date.now(),
      endTime: 0,
      duration: 0,
      success: false,
      currentUrl: this.sanitize(currentUrl),
      errorMessage: '',
      dataPreview: '',
      variablesPreview: this.sanitize(variablesPreview)
    };
    const workflow = this.getPrimaryWorkflow(trace);
    workflow.actions.push(actionTrace);
    this.recordEvent(traceId, SourceDiagnosticLevel.INFO, SourceDiagnosticEventKind.ACTION, actionIndex, actionType, '操作开始', actionDescription, currentUrl);
  }

  public finishAction(
    traceId: string,
    actionIndex: number,
    actionType: string,
    success: boolean,
    currentUrl: string,
    errorMessage: string,
    dataPreview: string
  ): void {
    const trace = this.getTraceById(traceId);
    if (!trace) {
      return;
    }
    const actionTrace = this.findActionTrace(trace, actionIndex, actionType);
    if (!actionTrace) {
      return;
    }
    const now = Date.now();
    actionTrace.endTime = now;
    actionTrace.duration = Math.max(0, now - actionTrace.startTime);
    actionTrace.success = success;
    actionTrace.currentUrl = this.sanitize(currentUrl);
    actionTrace.errorMessage = this.sanitize(errorMessage);
    actionTrace.dataPreview = this.sanitize(dataPreview);
    this.recordEvent(
      traceId,
      success ? SourceDiagnosticLevel.INFO : SourceDiagnosticLevel.ERROR,
      SourceDiagnosticEventKind.ACTION,
      actionIndex,
      actionType,
      success ? '操作完成' : '操作失败',
      success ? actionTrace.dataPreview : actionTrace.errorMessage,
      currentUrl
    );
  }

  public recordEvent(
    traceId: string,
    level: SourceDiagnosticLevel,
    kind: SourceDiagnosticEventKind,
    actionIndex: number,
    actionType: string,
    message: string,
    details: string,
    currentUrl: string
  ): void {
    const trace = this.getTraceById(traceId);
    if (!trace) {
      return;
    }
    const event: SourceDiagnosticEvent = {
      id: this.buildId('event'),
      traceId: traceId,
      timestamp: Date.now(),
      level: level,
      kind: kind,
      sourceId: trace.sourceId,
      sourcePkg: trace.sourcePkg,
      sourceName: trace.sourceName,
      workflowName: trace.workflowName,
      actionIndex: actionIndex,
      actionType: actionType,
      currentUrl: this.sanitize(currentUrl),
      message: message,
      details: this.sanitize(details)
    };
    trace.events.push(event);
  }

  public getRecentTraces(): SourceExecutionTrace[] {
    return this.traces.slice();
  }

  public getTraceById(traceId: string): SourceExecutionTrace | null {
    for (let i = 0; i < this.traces.length; i++) {
      if (this.traces[i].traceId === traceId) {
        return this.traces[i];
      }
    }
    return null;
  }

  public getLatestTraceForSource(sourceId: number): SourceExecutionTrace | null {
    for (let i = 0; i < this.traces.length; i++) {
      if (this.traces[i].sourceId === sourceId) {
        return this.traces[i];
      }
    }
    return null;
  }

  public exportTraceText(traceId: string): string {
    const trace = this.getTraceById(traceId);
    if (!trace) {
      return '未找到诊断记录';
    }
    let content = '';
    content += `图源诊断记录\n`;
    content += `Trace: ${trace.traceId}\n`;
    content += `图源: ${trace.sourceName} (${trace.sourceId})\n`;
    content += `包名: ${trace.sourcePkg}\n`;
    content += `工作流: ${trace.workflowName}\n`;
    content += `结果: ${trace.success ? '成功' : '失败'}\n`;
    content += `耗时: ${trace.duration}ms\n`;
    if (trace.errorMessage.length > 0) {
      content += `错误: ${trace.errorMessage}\n`;
    }
    content += `\n操作链路\n`;
    const workflow = this.getPrimaryWorkflow(trace);
    for (let i = 0; i < workflow.actions.length; i++) {
      const action = workflow.actions[i];
      content += `#${action.actionIndex + 1} ${action.actionType} ${action.success ? 'OK' : 'FAIL'} ${action.duration}ms\n`;
      if (action.actionDescription.length > 0) {
        content += `  描述: ${action.actionDescription}\n`;
      }
      if (action.errorMessage.length > 0) {
        content += `  错误: ${action.errorMessage}\n`;
      }
      if (action.currentUrl.length > 0) {
        content += `  URL: ${action.currentUrl}\n`;
      }
    }
    content += `\n事件\n`;
    for (let i = 0; i < trace.events.length; i++) {
      const event = trace.events[i];
      content += `[${event.level}] ${event.kind} ${event.message}`;
      if (event.actionIndex >= 0) {
        content += ` action=${event.actionIndex + 1}`;
      }
      if (event.details.length > 0) {
        content += ` ${event.details}`;
      }
      content += `\n`;
    }
    return content;
  }

  public sanitize(raw: string): string {
    let value = raw || '';
    if (value.length > PREVIEW_LIMIT) {
      value = value.substring(0, PREVIEW_LIMIT) + '...';
    }
    value = value.replace(/(cookie|authorization|token|password|passwd|secret)(["'\s:=]+)([^"',;\s]+)/ig, '$1$2[REDACTED]');
    return value;
  }

  public previewData(data: Object | string | boolean | number | undefined | null): string {
    if (data === undefined || data === null) {
      return '';
    }
    try {
      return this.sanitize(JSON.stringify(data));
    } catch (_error) {
      return this.sanitize(String(data));
    }
  }

  private getPrimaryWorkflow(trace: SourceExecutionTrace): WorkflowExecutionTrace {
    if (trace.workflows.length <= 0) {
      const workflow: WorkflowExecutionTrace = {
        traceId: trace.traceId,
        workflowName: trace.workflowName,
        startTime: trace.startTime,
        endTime: 0,
        duration: 0,
        success: false,
        actionCount: 0,
        errorMessage: '',
        actions: []
      };
      trace.workflows.push(workflow);
    }
    return trace.workflows[0];
  }

  private findActionTrace(trace: SourceExecutionTrace, actionIndex: number, actionType: string): ActionExecutionTrace | null {
    const workflow = this.getPrimaryWorkflow(trace);
    for (let i = workflow.actions.length - 1; i >= 0; i--) {
      const action = workflow.actions[i];
      if (action.actionIndex === actionIndex && action.actionType === actionType) {
        return action;
      }
    }
    return null;
  }

  private trimTraces(): void {
    while (this.traces.length > MAX_TRACE_COUNT) {
      this.traces.pop();
    }
  }

  private buildId(prefix: string): string {
    return `${prefix}_${Date.now()}_${Math.floor(Math.random() * 1000000)}`;
  }
}

export const sourceDiagnosticManager = SourceDiagnosticManager.getInstance();
