import { MangaReadFlowMonitor } from './MangaReadFlowMonitor';
import {
  MangaReadFlowEvent,
  MangaReadFlowEventType,
  MangaReadFlowModeKind,
  MangaReadFlowSessionInfo,
  MangaReadFlowSeverity,
  MangaReadFlowSourceKind
} from './MangaReadFlowTypes';

export class MangaReadFlowImportReport {
  public originImportId: string = '';
  public contentId: string = '';
  public contentTitle: string = '';
  public chapterId: string = '';
  public chapterTitle: string = '';
  public pageCount: number = 0;
  public chapterCount: number = 0;
  public sourcePath: string = '';
  public targetPath: string = '';
  public sourceId: string = '';
  public elapsedMs: number = 0;
  public success: boolean = true;
  public reason: string = 'import_completed';
  public errorMessage: string = '';
  public detail: string = '';
}

export class MangaReadFlowImportReporter {
  public static record(report: MangaReadFlowImportReport): string {
    const monitor: MangaReadFlowMonitor = MangaReadFlowMonitor.getInstance();
    const sessionId: string = report.originImportId.length > 0
      ? report.originImportId
      : monitor.createSessionId('import');

    const info: MangaReadFlowSessionInfo = new MangaReadFlowSessionInfo();
    info.sessionId = sessionId;
    info.sourceKind = MangaReadFlowSourceKind.IMPORT_PIPELINE;
    info.modeKind = MangaReadFlowModeKind.UNKNOWN;
    info.contentId = report.contentId;
    info.contentTitle = report.contentTitle;
    info.chapterId = report.chapterId;
    info.chapterTitle = report.chapterTitle;
    info.pageIndex = 0;
    info.pageCount = report.pageCount;
    info.originImportId = sessionId;
    info.readerHostMode = 'import_pipeline';
    monitor.startSession(info);

    const eventType: MangaReadFlowEventType = report.success
      ? MangaReadFlowEventType.PAGES_RESOLVED
      : MangaReadFlowEventType.ERROR;
    const event: MangaReadFlowEvent = monitor.createEvent(
      sessionId,
      eventType,
      report.contentId,
      report.chapterId,
      0,
      report.reason
    );
    event.sourceKind = MangaReadFlowSourceKind.IMPORT_PIPELINE;
    event.modeKind = MangaReadFlowModeKind.UNKNOWN;
    event.chapterTitle = report.chapterTitle;
    event.pageCount = report.pageCount;
    event.elapsedMs = report.elapsedMs;
    event.success = report.success;
    event.errorMessage = report.errorMessage;
    event.severity = report.success ? MangaReadFlowSeverity.INFO : MangaReadFlowSeverity.ERROR;
    event.metricName = report.success ? 'import_pages_resolved' : 'import_failed';
    event.metricValue = report.success ? report.pageCount : 1;
    event.metricUnit = report.success ? 'pages' : 'count';
    event.detail = MangaReadFlowImportReporter.buildDetail(report);
    monitor.record(event);

    monitor.endSession(sessionId, report.success ? 'import_completed' : 'import_failed');
    return sessionId;
  }

  private static buildDetail(report: MangaReadFlowImportReport): string {
    return `title=${report.contentTitle}, chapters=${report.chapterCount}, sourceId=${report.sourceId}, source=${report.sourcePath}, target=${report.targetPath}, detail=${report.detail}`;
  }
}
