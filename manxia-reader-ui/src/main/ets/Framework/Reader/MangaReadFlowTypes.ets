import { ReadingMode } from 'manxia_core/src/main/ets/Models/MangaModels';

export enum MangaReadFlowEventType {
  SESSION_START = 'session_start',
  CHAPTER_RESOLVED = 'chapter_resolved',
  PAGES_RESOLVED = 'pages_resolved',
  ASSET_REQUEST = 'asset_request',
  ASSET_LOADED = 'asset_loaded',
  DISPLAY_COMMITTED = 'display_committed',
  PAGE_CHANGED = 'page_changed',
  PROGRESS_SAVED = 'progress_saved',
  CACHE_SNAPSHOT = 'cache_snapshot',
  FLOW_DEGRADED = 'flow_degraded',
  FLOW_GUARD_REJECTED = 'flow_guard_rejected',
  FLOW_RECOVERED = 'flow_recovered',
  CLEANUP = 'cleanup',
  SESSION_END = 'session_end',
  ERROR = 'error'
}

export enum MangaReadFlowSourceKind {
  LOCAL = 'local',
  ONLINE_UNDOWNLOADED = 'online_undownloaded',
  ONLINE_DOWNLOADED = 'online_downloaded',
  SUWAYOMI = 'suwayomi',
  KOMGA = 'komga',
  EBOOK_IMAGE = 'ebook_image',
  PDF = 'pdf',
  LEGACY_REMOTE = 'legacy_remote',
  IMPORT_PIPELINE = 'import_pipeline'
}

export enum MangaReadFlowModeKind {
  SINGLE_PAGE = 'single_page',
  SINGLE_PAGE_LTR = 'single_page_ltr',
  SINGLE_PAGE_RTL = 'single_page_rtl',
  SINGLE_PAGE_TTB = 'single_page_ttb',
  DOUBLE_PAGE = 'double_page',
  CONTINUOUS_SCROLL = 'continuous_scroll',
  CONTINUOUS_VERTICAL = 'continuous_vertical',
  WEBTOON = 'webtoon',
  WEBTOON_WITH_GAP = 'webtoon_with_gap',
  PDF_KIT = 'pdf_kit',
  LEGACY_SUWAYOMI = 'legacy_suwayomi',
  LEGACY_KOMGA = 'legacy_komga',
  UNKNOWN = 'unknown'
}

export enum MangaReadFlowSeverity {
  DEBUG = 'debug',
  INFO = 'info',
  WARN = 'warn',
  ERROR = 'error'
}

export class MangaReadFlowSessionInfo {
  public sessionId: string = '';
  public sourceKind: MangaReadFlowSourceKind = MangaReadFlowSourceKind.LOCAL;
  public modeKind: MangaReadFlowModeKind = MangaReadFlowModeKind.UNKNOWN;
  public contentId: string = '';
  public contentTitle: string = '';
  public chapterId: string = '';
  public chapterTitle: string = '';
  public pageIndex: number = 0;
  public pageCount: number = 0;
  public sourceId: number = -1;
  public readerInstanceId: string = '';
  public readerHostMode: string = '';
  public originImportId: string = '';
  public originImportKind: string = '';
  public startedAt: number = 0;
  public endedAt: number = 0;
  public endReason: string = '';
}

export class MangaReadFlowEvent {
  public eventType: MangaReadFlowEventType = MangaReadFlowEventType.SESSION_START;
  public sessionId: string = '';
  public sourceKind: MangaReadFlowSourceKind = MangaReadFlowSourceKind.LOCAL;
  public modeKind: MangaReadFlowModeKind = MangaReadFlowModeKind.UNKNOWN;
  public timestamp: number = 0;
  public elapsedMs: number = 0;
  public severity: MangaReadFlowSeverity = MangaReadFlowSeverity.INFO;
  public reason: string = '';
  public contentId: string = '';
  public chapterId: string = '';
  public chapterTitle: string = '';
  public pageId: string = '';
  public pageIndex: number = -1;
  public pageCount: number = 0;
  public assetSource: string = '';
  public success: boolean = true;
  public errorMessage: string = '';
  public detail: string = '';
  public metricName: string = '';
  public metricValue: number = 0;
  public metricUnit: string = '';
}

export class MangaReadFlowSummary {
  public sessionId: string = '';
  public sourceKind: MangaReadFlowSourceKind = MangaReadFlowSourceKind.LOCAL;
  public modeKind: MangaReadFlowModeKind = MangaReadFlowModeKind.UNKNOWN;
  public contentId: string = '';
  public contentTitle: string = '';
  public chapterId: string = '';
  public chapterTitle: string = '';
  public startedAt: number = 0;
  public endedAt: number = 0;
  public totalEvents: number = 0;
  public failedEvents: number = 0;
  public slowEvents: number = 0;
  public lastPageIndex: number = -1;
  public pageCount: number = 0;
  public sourceId: number = -1;
  public readerInstanceId: string = '';
  public readerHostMode: string = '';
  public originImportId: string = '';
  public originImportKind: string = '';
  public endReason: string = '';
}

export class MangaReadFlowSnapshot {
  public activeSessionCount: number = 0;
  public recentSessionCount: number = 0;
  public recentEventCount: number = 0;
  public failedEventCount: number = 0;
  public slowEventCount: number = 0;
  public recentSessions: MangaReadFlowSummary[] = new Array<MangaReadFlowSummary>();
  public recentEvents: MangaReadFlowEvent[] = new Array<MangaReadFlowEvent>();
  public failedEvents: MangaReadFlowEvent[] = new Array<MangaReadFlowEvent>();
  public slowEvents: MangaReadFlowEvent[] = new Array<MangaReadFlowEvent>();
}

export function mapReadingModeToFlowMode(mode: ReadingMode | undefined): MangaReadFlowModeKind {
  if (mode === ReadingMode.SINGLE_PAGE) {
    return MangaReadFlowModeKind.SINGLE_PAGE;
  }
  if (mode === ReadingMode.SINGLE_PAGE_LTR) {
    return MangaReadFlowModeKind.SINGLE_PAGE_LTR;
  }
  if (mode === ReadingMode.SINGLE_PAGE_RTL) {
    return MangaReadFlowModeKind.SINGLE_PAGE_RTL;
  }
  if (mode === ReadingMode.SINGLE_PAGE_TTB) {
    return MangaReadFlowModeKind.SINGLE_PAGE_TTB;
  }
  if (mode === ReadingMode.DOUBLE_PAGE) {
    return MangaReadFlowModeKind.DOUBLE_PAGE;
  }
  if (mode === ReadingMode.CONTINUOUS_SCROLL) {
    return MangaReadFlowModeKind.CONTINUOUS_SCROLL;
  }
  if (mode === ReadingMode.CONTINUOUS_VERTICAL) {
    return MangaReadFlowModeKind.CONTINUOUS_VERTICAL;
  }
  if (mode === ReadingMode.WEBTOON) {
    return MangaReadFlowModeKind.WEBTOON;
  }
  if (mode === ReadingMode.WEBTOON_WITH_GAP) {
    return MangaReadFlowModeKind.WEBTOON_WITH_GAP;
  }
  return MangaReadFlowModeKind.UNKNOWN;
}
