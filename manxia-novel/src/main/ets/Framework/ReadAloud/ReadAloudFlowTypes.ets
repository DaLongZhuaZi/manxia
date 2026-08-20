export enum ReadAloudFlowEventType {
  SESSION_START = 'session_start',
  CONTEXT_UPDATED = 'context_updated',
  START_REQUESTED = 'start_requested',
  PAUSE_REQUESTED = 'pause_requested',
  STOP_REQUESTED = 'stop_requested',
  SEEK_REQUESTED = 'seek_requested',
  BACKEND_TASK_COMPLETED = 'backend_task_completed',
  BACKEND_TASK_FAILED = 'backend_task_failed',
  PLAYBACK_STATE_CHANGED = 'playback_state_changed',
  AUDIO_SESSION_STARTED = 'audio_session_started',
  AUDIO_CONTENT_READY = 'audio_content_ready',
  AUDIO_PLAYER_OPERATION = 'audio_player_operation',
  REMOTE_TTS_SEGMENT_READY = 'remote_tts_segment_ready',
  CACHE_HIT = 'cache_hit',
  CACHE_MISS = 'cache_miss',
  SESSION_END = 'session_end',
  ERROR = 'error'
}

export enum ReadAloudFlowMode {
  NORMAL_TTS = 'normal_tts',
  AUDIO_SOURCE = 'audio_source',
  UNSPECIFIED = 'unspecified'
}

export enum ReadAloudFlowSeverity {
  DEBUG = 'debug',
  INFO = 'info',
  WARN = 'warn',
  ERROR = 'error'
}

export class ReadAloudFlowSessionInfo {
  public sessionId: string = '';
  public readerOpenFlowId: string = '';
  public mode: ReadAloudFlowMode = ReadAloudFlowMode.UNSPECIFIED;
  public sourceId: string = '';
  public bookId: string = '';
  public bookTitle: string = '';
  public chapterId: string = '';
  public chapterTitle: string = '';
  public chapterIndex: number = -1;
  public totalChapters: number = 0;
  public pageIndex: number = -1;
  public engineType: string = '';
  public startedAt: number = 0;
  public endedAt: number = 0;
  public endReason: string = '';
}

export class ReadAloudFlowEvent {
  public eventType: ReadAloudFlowEventType = ReadAloudFlowEventType.SESSION_START;
  public sessionId: string = '';
  public readerOpenFlowId: string = '';
  public mode: ReadAloudFlowMode = ReadAloudFlowMode.UNSPECIFIED;
  public timestamp: number = 0;
  public elapsedMs: number = 0;
  public severity: ReadAloudFlowSeverity = ReadAloudFlowSeverity.INFO;
  public reason: string = '';
  public sourceId: string = '';
  public bookId: string = '';
  public chapterId: string = '';
  public chapterTitle: string = '';
  public chapterIndex: number = -1;
  public totalChapters: number = 0;
  public pageIndex: number = -1;
  public positionMs: number = -1;
  public durationMs: number = -1;
  public engineType: string = '';
  public backendTaskName: string = '';
  public playerOperation: string = '';
  public cacheKind: string = '';
  public success: boolean = true;
  public errorMessage: string = '';
  public detail: string = '';
  public metricName: string = '';
  public metricValue: number = 0;
  public metricUnit: string = '';
}

export class ReadAloudFlowSummary {
  public sessionId: string = '';
  public readerOpenFlowId: string = '';
  public mode: ReadAloudFlowMode = ReadAloudFlowMode.UNSPECIFIED;
  public sourceId: string = '';
  public bookId: string = '';
  public bookTitle: string = '';
  public chapterId: string = '';
  public chapterTitle: string = '';
  public chapterIndex: number = -1;
  public totalChapters: number = 0;
  public pageIndex: number = -1;
  public positionMs: number = -1;
  public durationMs: number = -1;
  public engineType: string = '';
  public startedAt: number = 0;
  public endedAt: number = 0;
  public totalEvents: number = 0;
  public failedEvents: number = 0;
  public slowEvents: number = 0;
  public endReason: string = '';
}

export class ReadAloudFlowSnapshot {
  public activeSessionCount: number = 0;
  public recentSessionCount: number = 0;
  public recentEventCount: number = 0;
  public failedEventCount: number = 0;
  public slowEventCount: number = 0;
  public recentSessions: ReadAloudFlowSummary[] = new Array<ReadAloudFlowSummary>();
  public recentEvents: ReadAloudFlowEvent[] = new Array<ReadAloudFlowEvent>();
  public failedEvents: ReadAloudFlowEvent[] = new Array<ReadAloudFlowEvent>();
  public slowEvents: ReadAloudFlowEvent[] = new Array<ReadAloudFlowEvent>();
}
