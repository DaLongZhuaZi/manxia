export enum NovelReadFlowEventType {
  SESSION_START = 'session_start',
  PARAM_BOUND = 'param_bound',
  LOAD_STARTED = 'load_started',
  RULES_READY = 'rules_ready',
  CHAPTER_LIST_READY = 'chapter_list_ready',
  CHAPTER_CONTENT_READY = 'chapter_content_ready',
  CONTENT_PROCESSED = 'content_processed',
  PROGRESS_RESTORED = 'progress_restored',
  PAGINATION_STARTED = 'pagination_started',
  PAGINATION_CACHE_HIT = 'pagination_cache_hit',
  PAGINATION_COMPLETED = 'pagination_completed',
  PAGINATION_FAILED = 'pagination_failed',
  READER_READY = 'reader_ready',
  PAGE_CHANGED = 'page_changed',
  CHAPTER_SWITCH = 'chapter_switch',
  PROGRESS_SAVED = 'progress_saved',
  SESSION_END = 'session_end',
  ERROR = 'error'
}

export enum NovelReadFlowSeverity {
  DEBUG = 'debug',
  INFO = 'info',
  WARN = 'warn',
  ERROR = 'error'
}

export class NovelReadFlowSessionInfo {
  public sessionId: string = '';
  public readerOpenFlowId: string = '';
  public sourceId: string = '';
  public bookId: string = '';
  public bookTitle: string = '';
  public chapterId: string = '';
  public chapterTitle: string = '';
  public chapterIndex: number = -1;
  public totalChapters: number = 0;
  public readerInstanceId: string = '';
  public readerHostMode: string = '';
  public startedAt: number = 0;
  public endedAt: number = 0;
  public endReason: string = '';
}

export class NovelReadFlowEvent {
  public eventType: NovelReadFlowEventType = NovelReadFlowEventType.SESSION_START;
  public sessionId: string = '';
  public readerOpenFlowId: string = '';
  public timestamp: number = 0;
  public elapsedMs: number = 0;
  public severity: NovelReadFlowSeverity = NovelReadFlowSeverity.INFO;
  public reason: string = '';
  public sourceId: string = '';
  public bookId: string = '';
  public chapterId: string = '';
  public chapterTitle: string = '';
  public chapterIndex: number = -1;
  public pageIndex: number = -1;
  public pageCount: number = 0;
  public success: boolean = true;
  public errorMessage: string = '';
  public detail: string = '';
  public metricName: string = '';
  public metricValue: number = 0;
  public metricUnit: string = '';
}

export class NovelReadFlowSummary {
  public sessionId: string = '';
  public readerOpenFlowId: string = '';
  public sourceId: string = '';
  public bookId: string = '';
  public bookTitle: string = '';
  public chapterId: string = '';
  public chapterTitle: string = '';
  public chapterIndex: number = -1;
  public totalChapters: number = 0;
  public startedAt: number = 0;
  public endedAt: number = 0;
  public totalEvents: number = 0;
  public failedEvents: number = 0;
  public slowEvents: number = 0;
  public lastPageIndex: number = -1;
  public pageCount: number = 0;
  public endReason: string = '';
}

export class NovelReadFlowSnapshot {
  public activeSessionCount: number = 0;
  public recentSessionCount: number = 0;
  public recentEventCount: number = 0;
  public failedEventCount: number = 0;
  public slowEventCount: number = 0;
  public recentSessions: NovelReadFlowSummary[] = new Array<NovelReadFlowSummary>();
  public recentEvents: NovelReadFlowEvent[] = new Array<NovelReadFlowEvent>();
  public failedEvents: NovelReadFlowEvent[] = new Array<NovelReadFlowEvent>();
  public slowEvents: NovelReadFlowEvent[] = new Array<NovelReadFlowEvent>();
}
