/**
 * 全局搜索会话类型
 * 将取消、进度 patch 与指标统一沉到服务层，页面只持有当前 session handle。
 */

export enum GlobalSearchTaskKind {
  LOCAL = 'local',
  MANGA_HTTP = 'mangaHttp',
  MANGA_WEBVIEW = 'mangaWebView',
  NOVEL = 'novel',
  SUWAYOMI = 'suwayomi'
}

export enum GlobalSearchPatchType {
  GROUP_START = 'groupStart',
  GROUP_ITEMS = 'groupItems',
  GROUP_ERROR = 'groupError',
  GROUP_DONE = 'groupDone',
  SESSION_DONE = 'sessionDone'
}

export class GlobalSearchCancelSignal {
  private cancelled: boolean = false;
  private reason: string = '';
  private cancelTime: number = 0;

  cancel(reason: string): void {
    if (this.cancelled) {
      return;
    }
    this.cancelled = true;
    this.reason = reason;
    this.cancelTime = Date.now();
  }

  isCancelled(): boolean {
    return this.cancelled;
  }

  getReason(): string {
    return this.reason;
  }

  getCancelledAt(): number {
    return this.cancelTime;
  }
}

export class GlobalSearchMetrics {
  sessionId: string = '';
  keyword: string = '';
  startTime: number = 0;
  endTime: number = 0;
  totalGroups: number = 0;
  completedGroups: number = 0;
  cancelledGroups: number = 0;
  timeoutGroups: number = 0;
  failedGroups: number = 0;
  resultCount: number = 0;
  uiPatchCount: number = 0;

  begin(sessionId: string, keyword: string, totalGroups: number): void {
    this.sessionId = sessionId;
    this.keyword = keyword;
    this.totalGroups = totalGroups;
    this.startTime = Date.now();
    this.endTime = 0;
    this.completedGroups = 0;
    this.cancelledGroups = 0;
    this.timeoutGroups = 0;
    this.failedGroups = 0;
    this.resultCount = 0;
    this.uiPatchCount = 0;
  }

  finish(resultCount: number): void {
    this.endTime = Date.now();
    this.resultCount = resultCount;
  }

  getDurationMs(): number {
    const finishTime = this.endTime > 0 ? this.endTime : Date.now();
    return this.startTime > 0 ? finishTime - this.startTime : 0;
  }
}

export interface GlobalSearchProgressPatch {
  sessionId: string;
  patchType: GlobalSearchPatchType;
  completedGroups: number;
  totalGroups: number;
  groupId?: string;
  groupName?: string;
  itemCount?: number;
  errorMessage?: string;
}

export type GlobalSearchPatchCallback = (patch: GlobalSearchProgressPatch) => void;

export interface GlobalSearchTimeoutResult<T> {
  completed: boolean;
  timedOut: boolean;
  value?: T;
  errorMessage: string;
}

export class GlobalSearchSessionHandle<T> {
  readonly sessionId: string;
  readonly signal: GlobalSearchCancelSignal;
  readonly completion: Promise<T>;
  private cancelCallback: (reason: string) => void;

  constructor(
    sessionId: string,
    signal: GlobalSearchCancelSignal,
    completion: Promise<T>,
    cancelCallback: (reason: string) => void
  ) {
    this.sessionId = sessionId;
    this.signal = signal;
    this.completion = completion;
    this.cancelCallback = cancelCallback;
  }

  cancel(reason: string): void {
    this.cancelCallback(reason);
  }

  isCancelled(): boolean {
    return this.signal.isCancelled();
  }
}
