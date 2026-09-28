export enum EpubReadFlowEventType {
  SESSION_START = 'session_start',
  PARAM_BOUND = 'param_bound',
  BOOK_LOADED = 'book_loaded',
  SPINE_REQUESTED = 'spine_requested',
  WEBVIEW_LOAD_START = 'webview_load_start',
  WEBVIEW_LOAD_END = 'webview_load_end',
  WEBVIEW_ERROR = 'webview_error',
  JS_EXECUTED = 'js_executed',
  JS_FAILED = 'js_failed',
  PAGINATION_CHANGED = 'pagination_changed',
  PROGRESS_SAVED = 'progress_saved',
  READER_READY = 'reader_ready',
  SESSION_END = 'session_end',
  ERROR = 'error'
}

export enum EpubReadFlowSeverity {
  DEBUG = 'debug',
  INFO = 'info',
  WARN = 'warn',
  ERROR = 'error'
}

export class EpubReadFlowSessionInfo {
  public sessionId: string = '';
  public readerOpenFlowId: string = '';
  public bookId: string = '';
  public bookTitle: string = '';
  public format: string = '';
  public spineIndex: number = -1;
  public spinePath: string = '';
  public readerInstanceId: string = '';
  public readerHostMode: string = '';
  public startedAt: number = 0;
  public endedAt: number = 0;
  public endReason: string = '';
}

export class EpubReadFlowEvent {
  public eventType: EpubReadFlowEventType = EpubReadFlowEventType.SESSION_START;
  public sessionId: string = '';
  public readerOpenFlowId: string = '';
  public timestamp: number = 0;
  public elapsedMs: number = 0;
  public severity: EpubReadFlowSeverity = EpubReadFlowSeverity.INFO;
  public reason: string = '';
  public bookId: string = '';
  public spineIndex: number = -1;
  public spinePath: string = '';
  public pageIndex: number = -1;
  public pageCount: number = 0;
  public success: boolean = true;
  public errorMessage: string = '';
  public detail: string = '';
  public metricName: string = '';
  public metricValue: number = 0;
  public metricUnit: string = '';
}

export class EpubReadFlowSummary {
  public sessionId: string = '';
  public readerOpenFlowId: string = '';
  public bookId: string = '';
  public bookTitle: string = '';
  public format: string = '';
  public spineIndex: number = -1;
  public spinePath: string = '';
  public startedAt: number = 0;
  public endedAt: number = 0;
  public totalEvents: number = 0;
  public failedEvents: number = 0;
  public slowEvents: number = 0;
  public lastPageIndex: number = -1;
  public pageCount: number = 0;
  public endReason: string = '';
}

export class EpubReadFlowSnapshot {
  public activeSessionCount: number = 0;
  public recentSessionCount: number = 0;
  public recentEventCount: number = 0;
  public failedEventCount: number = 0;
  public slowEventCount: number = 0;
  public recentSessions: EpubReadFlowSummary[] = new Array<EpubReadFlowSummary>();
  public recentEvents: EpubReadFlowEvent[] = new Array<EpubReadFlowEvent>();
  public failedEvents: EpubReadFlowEvent[] = new Array<EpubReadFlowEvent>();
  public slowEvents: EpubReadFlowEvent[] = new Array<EpubReadFlowEvent>();
}
