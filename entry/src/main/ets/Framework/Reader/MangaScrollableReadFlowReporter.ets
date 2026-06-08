import { MangaReadFlowMonitor } from './MangaReadFlowMonitor';
import {
  MangaReadFlowEvent,
  MangaReadFlowEventType,
  MangaReadFlowModeKind,
  MangaReadFlowSeverity,
  MangaReadFlowSourceKind
} from './MangaReadFlowTypes';

export class MangaScrollableReadFlowContext {
  public sessionId: string = '';
  public sourceKind: MangaReadFlowSourceKind = MangaReadFlowSourceKind.LOCAL;
  public modeKind: MangaReadFlowModeKind = MangaReadFlowModeKind.UNKNOWN;
  public contentId: string = '';
  public chapterId: string = '';
  public chapterTitle: string = '';
  public pageIndex: number = -1;
  public pageCount: number = 0;
}

export class MangaScrollableReadFlowReporter {
  private monitor: MangaReadFlowMonitor = MangaReadFlowMonitor.getInstance();

  public record(
    context: MangaScrollableReadFlowContext,
    eventType: MangaReadFlowEventType,
    reason: string,
    detail: string,
    severity: MangaReadFlowSeverity
  ): void {
    if (context.sessionId.length <= 0) {
      return;
    }
    const event: MangaReadFlowEvent = this.monitor.createEvent(
      context.sessionId,
      eventType,
      context.contentId,
      context.chapterId,
      context.pageIndex,
      reason
    );
    event.sourceKind = context.sourceKind;
    event.modeKind = context.modeKind;
    event.chapterTitle = context.chapterTitle;
    event.pageCount = context.pageCount;
    event.detail = detail;
    event.severity = severity;
    if (severity === MangaReadFlowSeverity.ERROR) {
      event.success = false;
    }
    this.monitor.record(event);
  }
}
