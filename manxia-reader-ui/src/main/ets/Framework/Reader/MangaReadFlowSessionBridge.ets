import { MangaReadFlowMonitor } from './MangaReadFlowMonitor';
import {
  MangaReadFlowEvent,
  MangaReadFlowEventType,
  MangaReadFlowModeKind,
  MangaReadFlowSessionInfo,
  MangaReadFlowSeverity,
  MangaReadFlowSourceKind
} from './MangaReadFlowTypes';

export class MangaReadFlowSessionBridgeContext {
  public sourceKind: MangaReadFlowSourceKind = MangaReadFlowSourceKind.LOCAL;
  public modeKind: MangaReadFlowModeKind = MangaReadFlowModeKind.UNKNOWN;
  public contentId: string = '';
  public contentTitle: string = '';
  public chapterId: string = '';
  public chapterTitle: string = '';
  public pageIndex: number = -1;
  public pageCount: number = 0;
  public readerHostMode: string = '';
  public readerInstanceId: string = '';
  public detail: string = '';
}

export class MangaReadFlowSessionBridgeResult {
  public sessionId: string = '';
  public valid: boolean = false;
}

export class MangaReadFlowSessionBridge {
  private monitor: MangaReadFlowMonitor = MangaReadFlowMonitor.getInstance();
  private missingSessionReported: boolean = false;
  private diagnosticSessionId: string = '';

  public resolve(sessionId: string, context: MangaReadFlowSessionBridgeContext): MangaReadFlowSessionBridgeResult {
    const result: MangaReadFlowSessionBridgeResult = new MangaReadFlowSessionBridgeResult();
    if (sessionId && sessionId.length > 0) {
      result.sessionId = sessionId;
      result.valid = true;
      return result;
    }

    result.sessionId = this.ensureDiagnosticSession(context);
    result.valid = false;
    if (!this.missingSessionReported) {
      this.missingSessionReported = true;
      this.recordMissingSession(context, result.sessionId);
    }
    return result;
  }

  public resetMissingSessionReport(): void {
    this.missingSessionReported = false;
    if (this.diagnosticSessionId.length > 0) {
      this.monitor.endSession(this.diagnosticSessionId, 'viewer_missing_session_reset');
      this.diagnosticSessionId = '';
    }
  }

  private ensureDiagnosticSession(context: MangaReadFlowSessionBridgeContext): string {
    if (this.diagnosticSessionId.length > 0) {
      return this.diagnosticSessionId;
    }
    const info: MangaReadFlowSessionInfo = new MangaReadFlowSessionInfo();
    info.sessionId = this.monitor.createSessionId('viewer_missing');
    info.sourceKind = context.sourceKind;
    info.modeKind = context.modeKind;
    info.contentId = context.contentId;
    info.contentTitle = context.contentTitle;
    info.chapterId = context.chapterId;
    info.chapterTitle = context.chapterTitle;
    info.pageIndex = context.pageIndex;
    info.pageCount = context.pageCount;
    info.readerHostMode = context.readerHostMode;
    info.readerInstanceId = context.readerInstanceId;
    this.diagnosticSessionId = this.monitor.startSession(info);
    return this.diagnosticSessionId;
  }

  private recordMissingSession(context: MangaReadFlowSessionBridgeContext, sessionId: string): void {
    const event: MangaReadFlowEvent = this.monitor.createEvent(
      sessionId,
      MangaReadFlowEventType.ERROR,
      context.contentId,
      context.chapterId,
      context.pageIndex,
      'viewer_missing_session'
    );
    event.sourceKind = context.sourceKind;
    event.modeKind = context.modeKind;
    event.chapterTitle = context.chapterTitle;
    event.pageCount = context.pageCount;
    event.success = false;
    event.severity = MangaReadFlowSeverity.ERROR;
    event.errorMessage = 'MangaViewer received empty readFlowSessionId';
    event.detail = context.detail;
    this.monitor.record(event);
  }
}
