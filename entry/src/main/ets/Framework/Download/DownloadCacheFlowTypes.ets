export enum DownloadCacheEntrySource {
  UNKNOWN = 'unknown',
  UNIFIED_DETAIL = 'unified_detail',
  DOWNLOAD_MANAGER_PAGE = 'download_manager_page',
  UNIFIED_DOWNLOAD_MANAGER = 'unified_download_manager',
  MANGA_DOWNLOAD_MANAGER = 'manga_download_manager',
  ONLINE_IMAGE_LOADER = 'online_image_loader',
  CACHE_STATUS_SERVICE = 'cache_status_service',
  PERMANENT_IMAGE_CACHE = 'permanent_image_cache',
  MANGA_READER = 'manga_reader'
}

export enum DownloadCacheContentType {
  UNKNOWN = 'unknown',
  MANGA = 'manga',
  NOVEL = 'novel',
  EBOOK = 'ebook',
  IMAGE = 'image',
  CACHE_STATUS = 'cache_status'
}

export enum DownloadCacheFlowSeverity {
  DEBUG = 'debug',
  INFO = 'info',
  WARN = 'warn',
  ERROR = 'error'
}

export enum DownloadCacheFlowStage {
  SESSION = 'session',
  TASK = 'task',
  QUEUE = 'queue',
  PAGE_LIST = 'page_list',
  NETWORK = 'network',
  IMAGE_PROCESS = 'image_process',
  DISK_CACHE = 'disk_cache',
  DATABASE = 'database',
  ARCHIVE = 'archive',
  CACHE_STATUS = 'cache_status',
  VISIBILITY = 'visibility'
}

export enum DownloadCacheFlowEventType {
  SESSION_START = 'session_start',
  SESSION_END = 'session_end',
  TASK_CREATE_REQUEST = 'task_create_request',
  TASK_CREATED = 'task_created',
  TASK_DEDUP_HIT = 'task_dedup_hit',
  BATCH_TASK_CREATE_COMPLETED = 'batch_task_create_completed',
  QUEUE_ENQUEUED = 'queue_enqueued',
  QUEUE_DISPATCHED = 'queue_dispatched',
  STATUS_CHANGED = 'status_changed',
  CALLBACK_NOTIFIED = 'callback_notified',
  PAGE_LIST_FETCH_STARTED = 'page_list_fetch_started',
  PAGE_LIST_FETCH_COMPLETED = 'page_list_fetch_completed',
  PAGE_LIST_FETCH_FAILED = 'page_list_fetch_failed',
  IMAGE_DOWNLOAD_STARTED = 'image_download_started',
  IMAGE_DOWNLOAD_RETRY = 'image_download_retry',
  IMAGE_DOWNLOAD_COMPLETED = 'image_download_completed',
  IMAGE_DOWNLOAD_FAILED = 'image_download_failed',
  CACHE_MEMORY_HIT = 'cache_memory_hit',
  CACHE_DISK_HIT = 'cache_disk_hit',
  CACHE_DEDUP_WAIT = 'cache_dedup_wait',
  CACHE_QUEUE_ENQUEUED = 'cache_queue_enqueued',
  SOURCE_LIMIT_WAIT_STARTED = 'source_limit_wait_started',
  SOURCE_LIMIT_WAIT_COMPLETED = 'source_limit_wait_completed',
  HTTP_STARTED = 'http_started',
  HTTP_COMPLETED = 'http_completed',
  HTTP_FAILED = 'http_failed',
  WEBVIEW_FALLBACK_STARTED = 'webview_fallback_started',
  WEBVIEW_FALLBACK_COMPLETED = 'webview_fallback_completed',
  WEBVIEW_FALLBACK_FAILED = 'webview_fallback_failed',
  IMAGE_PROCESS_STARTED = 'image_process_started',
  IMAGE_PROCESS_COMPLETED = 'image_process_completed',
  IMAGE_PROCESS_FAILED = 'image_process_failed',
  DISK_WRITE_STARTED = 'disk_write_started',
  DISK_WRITE_COMPLETED = 'disk_write_completed',
  DISK_WRITE_FAILED = 'disk_write_failed',
  DB_FLUSH_STARTED = 'db_flush_started',
  DB_FLUSH_COMPLETED = 'db_flush_completed',
  DB_FLUSH_FAILED = 'db_flush_failed',
  PAGE_DB_UPDATE_COMPLETED = 'page_db_update_completed',
  PAGE_DB_UPDATE_FAILED = 'page_db_update_failed',
  TASK_DB_UPDATE_COMPLETED = 'task_db_update_completed',
  TASK_DB_UPDATE_FAILED = 'task_db_update_failed',
  CHAPTER_STATUS_UPDATE_COMPLETED = 'chapter_status_update_completed',
  CHAPTER_STATUS_UPDATE_FAILED = 'chapter_status_update_failed',
  ARCHIVE_STARTED = 'archive_started',
  ARCHIVE_COMPLETED = 'archive_completed',
  ARCHIVE_FAILED = 'archive_failed',
  CACHE_STATUS_STARTED = 'cache_status_started',
  CACHE_STATUS_COMPLETED = 'cache_status_completed',
  CACHE_STATUS_FAILED = 'cache_status_failed',
  CACHE_STATUS_HIT = 'cache_status_hit',
  CACHE_STATUS_MISS = 'cache_status_miss',
  CACHE_STATUS_INVALIDATED = 'cache_status_invalidated',
  PERMANENT_STATS_HIT = 'permanent_stats_hit',
  PERMANENT_STATS_MISS = 'permanent_stats_miss',
  PERMANENT_STATS_INVALIDATED = 'permanent_stats_invalidated',
  MANGA_CACHE_EVENT_PUBLISHED = 'manga_cache_event_published',
  READER_VISIBLE_CHECK = 'reader_visible_check',
  FAILURE_TTL_RECORDED = 'failure_ttl_recorded',
  FAILURE_TTL_HIT = 'failure_ttl_hit',
  ERROR = 'error'
}

export class DownloadCacheFlowSessionInfo {
  public sessionId: string = '';
  public entrySource: DownloadCacheEntrySource = DownloadCacheEntrySource.UNKNOWN;
  public contentType: DownloadCacheContentType = DownloadCacheContentType.UNKNOWN;
  public contentId: string = '';
  public contentTitle: string = '';
  public chapterId: string = '';
  public chapterTitle: string = '';
  public taskId: string = '';
  public sourceId: number = 0;
  public sourceKey: string = '';
  public url: string = '';
  public cacheKey: string = '';
  public batchMode: boolean = false;
  public totalCount: number = 0;
  public pageName: string = '';
  public startedAt: number = 0;
  public endedAt: number = 0;
  public endReason: string = '';
}

export class DownloadCacheFlowEvent {
  public eventType: DownloadCacheFlowEventType = DownloadCacheFlowEventType.SESSION_START;
  public stage: DownloadCacheFlowStage = DownloadCacheFlowStage.SESSION;
  public sessionId: string = '';
  public timestamp: number = 0;
  public elapsedMs: number = 0;
  public severity: DownloadCacheFlowSeverity = DownloadCacheFlowSeverity.INFO;
  public success: boolean = true;
  public reason: string = '';
  public entrySource: DownloadCacheEntrySource = DownloadCacheEntrySource.UNKNOWN;
  public contentType: DownloadCacheContentType = DownloadCacheContentType.UNKNOWN;
  public contentId: string = '';
  public contentTitle: string = '';
  public chapterId: string = '';
  public chapterTitle: string = '';
  public taskId: string = '';
  public sourceId: number = 0;
  public sourceKey: string = '';
  public url: string = '';
  public cacheKey: string = '';
  public filePath: string = '';
  public archivePath: string = '';
  public currentIndex: number = 0;
  public totalCount: number = 0;
  public downloadedCount: number = 0;
  public failedCount: number = 0;
  public byteCount: number = 0;
  public retryCount: number = 0;
  public queueSize: number = 0;
  public activeCount: number = 0;
  public cacheHit: boolean = false;
  public visibleLoad: boolean = false;
  public errorMessage: string = '';
  public detail: string = '';
  public metricName: string = '';
  public metricValue: number = 0;
  public metricUnit: string = '';
}

export class DownloadCacheFlowSummary {
  public sessionId: string = '';
  public entrySource: DownloadCacheEntrySource = DownloadCacheEntrySource.UNKNOWN;
  public contentType: DownloadCacheContentType = DownloadCacheContentType.UNKNOWN;
  public contentId: string = '';
  public contentTitle: string = '';
  public chapterId: string = '';
  public chapterTitle: string = '';
  public taskId: string = '';
  public sourceId: number = 0;
  public sourceKey: string = '';
  public startedAt: number = 0;
  public endedAt: number = 0;
  public totalEvents: number = 0;
  public failedEvents: number = 0;
  public slowEvents: number = 0;
  public cacheHits: number = 0;
  public networkRequests: number = 0;
  public dbFlushes: number = 0;
  public archives: number = 0;
  public completedItems: number = 0;
  public totalItems: number = 0;
  public lastEventType: string = '';
  public endReason: string = '';
}

export class DownloadCacheFlowSnapshot {
  public activeSessionCount: number = 0;
  public recentSessionCount: number = 0;
  public recentEventCount: number = 0;
  public failedEventCount: number = 0;
  public slowEventCount: number = 0;
  public recentSessions: DownloadCacheFlowSummary[] = new Array<DownloadCacheFlowSummary>();
  public recentEvents: DownloadCacheFlowEvent[] = new Array<DownloadCacheFlowEvent>();
  public failedEvents: DownloadCacheFlowEvent[] = new Array<DownloadCacheFlowEvent>();
  public slowEvents: DownloadCacheFlowEvent[] = new Array<DownloadCacheFlowEvent>();
}
