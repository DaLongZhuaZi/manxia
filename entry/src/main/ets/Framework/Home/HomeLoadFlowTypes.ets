export enum HomeLoadFlowEntryReason {
  NORMAL = 'normal',
  ROUTE_PARAM = 'route_param',
  WIDGET = 'widget',
  DEEP_LINK = 'deep_link',
  GUIDE = 'guide'
}

export enum HomeLoadFlowPrimaryTab {
  HOME = 'home',
  LIBRARY = 'library',
  DISCOVER = 'discover',
  SOURCE = 'source',
  BOOK_SOURCE = 'book_source',
  SETTINGS = 'settings',
  UNKNOWN = 'unknown'
}

export enum HomeLoadFlowStage {
  SESSION = 'session',
  ENTRY = 'entry',
  CONFIG = 'config',
  LIBRARY_DB = 'library_db',
  FILTER_MERGE = 'filter_merge',
  COVER = 'cover',
  DATASOURCE = 'datasource',
  FIRST_SCREEN = 'first_screen',
  DEFERRED = 'deferred',
  DISCOVER = 'discover',
  SOURCE = 'source'
}

export enum HomeLoadFlowSeverity {
  DEBUG = 'debug',
  INFO = 'info',
  WARN = 'warn',
  ERROR = 'error'
}

export enum HomeLoadFlowEventType {
  SESSION_START = 'session_start',
  SESSION_END = 'session_end',
  ENTRY_RECEIVED = 'entry_received',
  ROUTE_PARAMS_PARSED = 'route_params_parsed',
  PRIMARY_TAB_SELECTED = 'primary_tab_selected',
  CONFIG_LOAD_STARTED = 'config_load_started',
  CONFIG_LOAD_COMPLETED = 'config_load_completed',
  CONFIG_LOAD_FAILED = 'config_load_failed',
  LIBRARY_DB_QUERY_STARTED = 'library_db_query_started',
  LIBRARY_DB_QUERY_COMPLETED = 'library_db_query_completed',
  LIBRARY_DB_QUERY_FAILED = 'library_db_query_failed',
  FILTER_MERGE_STARTED = 'filter_merge_started',
  FILTER_MERGE_COMPLETED = 'filter_merge_completed',
  FILTER_MERGE_FAILED = 'filter_merge_failed',
  COVER_RESOLVE_STARTED = 'cover_resolve_started',
  COVER_RESOLVE_COMPLETED = 'cover_resolve_completed',
  COVER_RESOLVE_FAILED = 'cover_resolve_failed',
  COVER_FAILURE_TTL_HIT = 'cover_failure_ttl_hit',
  COVER_FAILURE_TTL_RECORDED = 'cover_failure_ttl_recorded',
  DATASOURCE_UPDATE_STARTED = 'datasource_update_started',
  DATASOURCE_UPDATE_COMPLETED = 'datasource_update_completed',
  DATASOURCE_UPDATE_SKIPPED = 'datasource_update_skipped',
  FIRST_SCREEN_READY = 'first_screen_ready',
  DEFERRED_TASK_STARTED = 'deferred_task_started',
  DEFERRED_TASK_COMPLETED = 'deferred_task_completed',
  DEFERRED_TASK_FAILED = 'deferred_task_failed',
  DISCOVER_PREPARE_STARTED = 'discover_prepare_started',
  DISCOVER_PREPARE_COMPLETED = 'discover_prepare_completed',
  DISCOVER_PREPARE_FAILED = 'discover_prepare_failed',
  SOURCE_PREPARE_STARTED = 'source_prepare_started',
  SOURCE_PREPARE_COMPLETED = 'source_prepare_completed',
  SOURCE_PREPARE_FAILED = 'source_prepare_failed',
  ERROR = 'error'
}

export class HomeLoadFlowSessionInfo {
  public sessionId: string = '';
  public entryReason: HomeLoadFlowEntryReason = HomeLoadFlowEntryReason.NORMAL;
  public primaryTab: HomeLoadFlowPrimaryTab = HomeLoadFlowPrimaryTab.UNKNOWN;
  public routeTarget: string = '';
  public widgetTarget: string = '';
  public privacyMode: boolean = false;
  public sfwMode: boolean = false;
  public startedAt: number = 0;
  public endedAt: number = 0;
  public endReason: string = '';
}

export class HomeLoadFlowEvent {
  public eventType: HomeLoadFlowEventType = HomeLoadFlowEventType.SESSION_START;
  public stage: HomeLoadFlowStage = HomeLoadFlowStage.SESSION;
  public sessionId: string = '';
  public reason: string = '';
  public timestamp: number = 0;
  public elapsedMs: number = 0;
  public severity: HomeLoadFlowSeverity = HomeLoadFlowSeverity.INFO;
  public success: boolean = true;
  public entryReason: HomeLoadFlowEntryReason = HomeLoadFlowEntryReason.NORMAL;
  public primaryTab: HomeLoadFlowPrimaryTab = HomeLoadFlowPrimaryTab.UNKNOWN;
  public routeTarget: string = '';
  public widgetTarget: string = '';
  public privacyMode: boolean = false;
  public sfwMode: boolean = false;
  public itemCount: number = 0;
  public changedCount: number = 0;
  public skippedCount: number = 0;
  public reload: boolean = false;
  public taskName: string = '';
  public errorMessage: string = '';
  public detail: string = '';
  public metricName: string = '';
  public metricValue: number = 0;
  public metricUnit: string = '';
}

export class HomeLoadFlowSummary {
  public sessionId: string = '';
  public entryReason: HomeLoadFlowEntryReason = HomeLoadFlowEntryReason.NORMAL;
  public primaryTab: HomeLoadFlowPrimaryTab = HomeLoadFlowPrimaryTab.UNKNOWN;
  public routeTarget: string = '';
  public widgetTarget: string = '';
  public privacyMode: boolean = false;
  public sfwMode: boolean = false;
  public startedAt: number = 0;
  public endedAt: number = 0;
  public totalEvents: number = 0;
  public failedEvents: number = 0;
  public slowEvents: number = 0;
  public dataSourceUpdates: number = 0;
  public deferredTasks: number = 0;
  public firstScreenReadyAt: number = 0;
  public lastEventType: string = '';
  public endReason: string = '';
}

export class HomeLoadFlowSnapshot {
  public activeSessionCount: number = 0;
  public recentSessionCount: number = 0;
  public recentEventCount: number = 0;
  public failedEventCount: number = 0;
  public slowEventCount: number = 0;
  public recentSessions: HomeLoadFlowSummary[] = new Array<HomeLoadFlowSummary>();
  public recentEvents: HomeLoadFlowEvent[] = new Array<HomeLoadFlowEvent>();
  public failedEvents: HomeLoadFlowEvent[] = new Array<HomeLoadFlowEvent>();
  public slowEvents: HomeLoadFlowEvent[] = new Array<HomeLoadFlowEvent>();
}
