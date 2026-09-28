export enum DetailOpenFlowEventType {
  SESSION_START = 'session_start',
  ENTRY_REQUEST = 'entry_request',
  TRANSITION_START = 'transition_start',
  NAVIGATION_DISPATCHED = 'navigation_dispatched',
  READER_READY = 'reader_ready',
  READER_FAILED = 'reader_failed',
  SESSION_END = 'session_end',
  ERROR = 'error'
}

export enum DetailOpenFlowTargetKind {
  NOVEL = 'novel',
  TXT_NOVEL = 'txt_novel',
  EBOOK = 'ebook',
  EPUB_WEBVIEW = 'epub_webview',
  READ_ALOUD = 'read_aloud',
  UNSPECIFIED = 'unspecified'
}

export enum DetailOpenFlowSeverity {
  DEBUG = 'debug',
  INFO = 'info',
  WARN = 'warn',
  ERROR = 'error'
}

export class DetailOpenFlowSessionInfo {
  public sessionId: string = '';
  public targetKind: DetailOpenFlowTargetKind = DetailOpenFlowTargetKind.UNSPECIFIED;
  public contentId: string = '';
  public contentTitle: string = '';
  public chapterId: string = '';
  public chapterTitle: string = '';
  public chapterIndex: number = -1;
  public routeName: string = '';
  public sourcePage: string = '';
  public startedAt: number = 0;
  public endedAt: number = 0;
  public endReason: string = '';
}

export class DetailOpenFlowEvent {
  public eventType: DetailOpenFlowEventType = DetailOpenFlowEventType.SESSION_START;
  public sessionId: string = '';
  public targetKind: DetailOpenFlowTargetKind = DetailOpenFlowTargetKind.UNSPECIFIED;
  public timestamp: number = 0;
  public elapsedMs: number = 0;
  public severity: DetailOpenFlowSeverity = DetailOpenFlowSeverity.INFO;
  public reason: string = '';
  public contentId: string = '';
  public chapterId: string = '';
  public chapterTitle: string = '';
  public chapterIndex: number = -1;
  public routeName: string = '';
  public success: boolean = true;
  public errorMessage: string = '';
  public detail: string = '';
  public metricName: string = '';
  public metricValue: number = 0;
  public metricUnit: string = '';
}

export class DetailOpenFlowSummary {
  public sessionId: string = '';
  public targetKind: DetailOpenFlowTargetKind = DetailOpenFlowTargetKind.UNSPECIFIED;
  public contentId: string = '';
  public contentTitle: string = '';
  public chapterId: string = '';
  public chapterTitle: string = '';
  public chapterIndex: number = -1;
  public routeName: string = '';
  public sourcePage: string = '';
  public startedAt: number = 0;
  public endedAt: number = 0;
  public totalEvents: number = 0;
  public failedEvents: number = 0;
  public slowEvents: number = 0;
  public endReason: string = '';
}

export class DetailOpenFlowSnapshot {
  public activeSessionCount: number = 0;
  public recentSessionCount: number = 0;
  public recentEventCount: number = 0;
  public failedEventCount: number = 0;
  public slowEventCount: number = 0;
  public recentSessions: DetailOpenFlowSummary[] = new Array<DetailOpenFlowSummary>();
  public recentEvents: DetailOpenFlowEvent[] = new Array<DetailOpenFlowEvent>();
  public failedEvents: DetailOpenFlowEvent[] = new Array<DetailOpenFlowEvent>();
  public slowEvents: DetailOpenFlowEvent[] = new Array<DetailOpenFlowEvent>();
}
