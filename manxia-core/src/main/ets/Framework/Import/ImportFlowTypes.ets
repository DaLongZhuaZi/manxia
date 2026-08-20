export enum ImportFlowEntrySource {
  UNKNOWN = 'unknown',
  FILE_PICKER = 'file_picker',
  DOWNLOAD_DIR = 'download_dir',
  LAN_TRANSFER = 'lan_transfer',
  NETWORK_FOLDER = 'network_folder',
  EXTERNAL_FILE_TASK = 'external_file_task',
  DOWNLOAD_SYNC = 'download_sync',
  MANUAL = 'manual'
}

export enum ImportFlowContentType {
  UNKNOWN = 'unknown',
  MANGA = 'manga',
  EBOOK = 'ebook',
  PDF = 'pdf',
  NOVEL = 'novel',
  BACKUP = 'backup',
  JSON = 'json',
  FONT = 'font',
  CODE = 'code',
  AVIF = 'avif',
  IMAGE = 'image'
}

export enum ImportFlowEventType {
  SESSION_START = 'session_start',
  ENTRY_RECEIVED = 'entry_received',
  PENDING_MARKERS_WRITTEN = 'pending_markers_written',
  PENDING_MARKERS_CONSUMED = 'pending_markers_consumed',
  DOWNLOAD_SCAN_STARTED = 'download_scan_started',
  DOWNLOAD_SCAN_COMPLETED = 'download_scan_completed',
  FILE_CLASSIFIED = 'file_classified',
  DIALOG_OPENED = 'dialog_opened',
  DIALOG_CONFIRMED = 'dialog_confirmed',
  DIALOG_CANCELLED = 'dialog_cancelled',
  ARCHIVE_PARSE_STARTED = 'archive_parse_started',
  ARCHIVE_PARSE_CACHE_HIT = 'archive_parse_cache_hit',
  ARCHIVE_PARSE_COMPLETED = 'archive_parse_completed',
  ARCHIVE_PARSE_FAILED = 'archive_parse_failed',
  PASSWORD_REQUIRED = 'password_required',
  PASSWORD_RETRY = 'password_retry',
  METADATA_DETECTED = 'metadata_detected',
  TXT_PREVIEW_STARTED = 'txt_preview_started',
  TXT_PREVIEW_COMPLETED = 'txt_preview_completed',
  TXT_RULE_PARSE_STARTED = 'txt_rule_parse_started',
  TXT_RULE_PARSE_COMPLETED = 'txt_rule_parse_completed',
  TXT_RULE_PARSE_FAILED = 'txt_rule_parse_failed',
  DUPLICATE_DETECT_STARTED = 'duplicate_detect_started',
  DUPLICATE_CACHE_HIT = 'duplicate_cache_hit',
  DUPLICATE_DETECT_COMPLETED = 'duplicate_detect_completed',
  COPY_STARTED = 'copy_started',
  COPY_PROGRESS = 'copy_progress',
  COPY_COMPLETED = 'copy_completed',
  PDF_TASK_CREATED = 'pdf_task_created',
  PDF_TASK_STARTED = 'pdf_task_started',
  PDF_TASK_COMPLETED = 'pdf_task_completed',
  PDF_TASK_FAILED = 'pdf_task_failed',
  PDF_CONVERT_STARTED = 'pdf_convert_started',
  PDF_CONVERT_COMPLETED = 'pdf_convert_completed',
  DB_WRITE_STARTED = 'db_write_started',
  DB_WRITE_COMPLETED = 'db_write_completed',
  COVER_HANDLED = 'cover_handled',
  BOOKSHELF_REFRESH_PUBLISHED = 'bookshelf_refresh_published',
  TRANSFER_RESULT_WRITTEN = 'transfer_result_written',
  SESSION_END = 'session_end',
  ERROR = 'error'
}

export enum ImportFlowSeverity {
  DEBUG = 'debug',
  INFO = 'info',
  WARN = 'warn',
  ERROR = 'error'
}

export class ImportFlowSessionInfo {
  public sessionId: string = '';
  public entrySource: ImportFlowEntrySource = ImportFlowEntrySource.UNKNOWN;
  public contentType: ImportFlowContentType = ImportFlowContentType.UNKNOWN;
  public sourceUri: string = '';
  public targetPath: string = '';
  public displayName: string = '';
  public fileCount: number = 0;
  public batchMode: boolean = false;
  public transferRecordId: string = '';
  public pageName: string = '';
  public startedAt: number = 0;
  public endedAt: number = 0;
  public endReason: string = '';
}

export class ImportFlowEvent {
  public eventType: ImportFlowEventType = ImportFlowEventType.SESSION_START;
  public sessionId: string = '';
  public timestamp: number = 0;
  public elapsedMs: number = 0;
  public severity: ImportFlowSeverity = ImportFlowSeverity.INFO;
  public reason: string = '';
  public success: boolean = true;
  public entrySource: ImportFlowEntrySource = ImportFlowEntrySource.UNKNOWN;
  public contentType: ImportFlowContentType = ImportFlowContentType.UNKNOWN;
  public sourceUri: string = '';
  public targetPath: string = '';
  public displayName: string = '';
  public fileName: string = '';
  public fileCount: number = 0;
  public batchMode: boolean = false;
  public currentIndex: number = 0;
  public totalCount: number = 0;
  public chapterCount: number = 0;
  public pageCount: number = 0;
  public byteCount: number = 0;
  public cacheKey: string = '';
  public cacheHit: boolean = false;
  public taskId: string = '';
  public transferRecordId: string = '';
  public errorMessage: string = '';
  public detail: string = '';
  public metricName: string = '';
  public metricValue: number = 0;
  public metricUnit: string = '';
}

export class ImportFlowSummary {
  public sessionId: string = '';
  public entrySource: ImportFlowEntrySource = ImportFlowEntrySource.UNKNOWN;
  public contentType: ImportFlowContentType = ImportFlowContentType.UNKNOWN;
  public sourceUri: string = '';
  public targetPath: string = '';
  public displayName: string = '';
  public fileCount: number = 0;
  public batchMode: boolean = false;
  public transferRecordId: string = '';
  public pageName: string = '';
  public startedAt: number = 0;
  public endedAt: number = 0;
  public totalEvents: number = 0;
  public failedEvents: number = 0;
  public slowEvents: number = 0;
  public cacheHits: number = 0;
  public cacheMisses: number = 0;
  public parsedFiles: number = 0;
  public copiedFiles: number = 0;
  public dbWrites: number = 0;
  public completedItems: number = 0;
  public totalItems: number = 0;
  public lastEventType: string = '';
  public endReason: string = '';
}

export class ImportFlowSnapshot {
  public activeSessionCount: number = 0;
  public recentSessionCount: number = 0;
  public recentEventCount: number = 0;
  public failedEventCount: number = 0;
  public slowEventCount: number = 0;
  public recentSessions: ImportFlowSummary[] = new Array<ImportFlowSummary>();
  public recentEvents: ImportFlowEvent[] = new Array<ImportFlowEvent>();
  public failedEvents: ImportFlowEvent[] = new Array<ImportFlowEvent>();
  public slowEvents: ImportFlowEvent[] = new Array<ImportFlowEvent>();
}
