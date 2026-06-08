// Responsibility: plan webtoon edge prewarm and adjacent chapter requests.

export enum MangaWebtoonAdjacentRequestDirection {
  NONE = 'NONE',
  PREV = 'PREV',
  NEXT = 'NEXT'
}

export class MangaWebtoonBoundaryInput {
  public isWebtoonMode: boolean = false;
  public hasChapter: boolean = false;
  public currentScrollY: number = 0;
  public containerHeight: number = 800;
  public totalHeight: number = 0;
  public isOnlineContent: boolean = false;
  public isFirstChapter: boolean = false;
  public isLastChapter: boolean = false;
  public hasPrevChapter: boolean = false;
  public hasNextChapter: boolean = false;
  public prevChapterInData: boolean = false;
  public nextChapterInData: boolean = false;
  public prevChapterRequested: boolean = false;
  public nextChapterRequested: boolean = false;
  public isPrevChapterLoading: boolean = false;
  public isNextChapterLoading: boolean = false;
  public prevConfirmPending: boolean = false;
  public prevConfirmTime: number = 0;
  public lastPrevRequestAt: number = 0;
  public lastNextRequestAt: number = 0;
  public adjacentRequestIntervalMs: number = 450;
  public now: number = 0;
}

export class MangaWebtoonBoundaryPlan {
  public shouldRun: boolean = false;
  public preloadThreshold: number = 0;
  public maxScrollY: number = 0;
  public nearTop: boolean = false;
  public nearBottom: boolean = false;
  public shouldProtectBoundaryCache: boolean = false;
  public shouldPrewarmCurrentChapter: boolean = false;
  public shouldPrewarmPrevChapter: boolean = false;
  public shouldPrewarmNextChapter: boolean = false;
  public shouldResetPrevLoading: boolean = false;
  public shouldResetNextLoading: boolean = false;
  public prevAlreadyInData: boolean = false;
  public nextAlreadyInData: boolean = false;
  public prevCanRequest: boolean = false;
  public nextCanRequest: boolean = false;
  public shouldStartPrevConfirm: boolean = false;
  public shouldKeepPrevConfirmWaiting: boolean = false;
  public shouldClearPrevConfirm: boolean = false;
  public shouldRequestPrev: boolean = false;
  public shouldRequestNext: boolean = false;
  public prevBlockedByCooldown: boolean = false;
  public nextBlockedByCooldown: boolean = false;
  public shouldUpdatePrevRequestTime: boolean = false;
  public shouldUpdateNextRequestTime: boolean = false;
}

export class MangaWebtoonBoundaryPlanner {
  public buildPlan(input: MangaWebtoonBoundaryInput): MangaWebtoonBoundaryPlan {
    const plan: MangaWebtoonBoundaryPlan = new MangaWebtoonBoundaryPlan();
    if (!input.isWebtoonMode || !input.hasChapter) {
      return plan;
    }

    plan.shouldRun = true;
    plan.preloadThreshold = input.containerHeight * (input.isOnlineContent ? 3 : 2);
    plan.maxScrollY = Math.max(0, input.totalHeight - input.containerHeight);
    plan.nearBottom = input.currentScrollY >= plan.maxScrollY - plan.preloadThreshold;
    plan.nearTop = input.currentScrollY <= plan.preloadThreshold;

    if (plan.nearTop || plan.nearBottom) {
      plan.shouldProtectBoundaryCache = true;
      plan.shouldPrewarmCurrentChapter = true;
      plan.shouldPrewarmPrevChapter = plan.nearTop;
      plan.shouldPrewarmNextChapter = plan.nearBottom;
    }

    this.planNextRequest(input, plan);
    this.planPrevRequest(input, plan);
    return plan;
  }

  private planNextRequest(input: MangaWebtoonBoundaryInput, plan: MangaWebtoonBoundaryPlan): void {
    if (!plan.nearBottom) {
      return;
    }
    if (input.isLastChapter) {
      plan.shouldResetNextLoading = true;
      return;
    }

    plan.nextAlreadyInData = input.hasNextChapter && input.nextChapterInData;
    plan.nextCanRequest = !input.nextChapterRequested && !input.isNextChapterLoading &&
      (!input.hasNextChapter || plan.nextAlreadyInData);
    if (!plan.nextCanRequest) {
      return;
    }

    if (!this.isRequestIntervalReady(input.now, input.lastNextRequestAt, input.adjacentRequestIntervalMs)) {
      plan.nextBlockedByCooldown = true;
      return;
    }

    plan.shouldRequestNext = true;
    plan.shouldUpdateNextRequestTime = true;
  }

  private planPrevRequest(input: MangaWebtoonBoundaryInput, plan: MangaWebtoonBoundaryPlan): void {
    if (!plan.nearTop) {
      return;
    }
    if (input.isFirstChapter) {
      plan.shouldResetPrevLoading = true;
      return;
    }

    plan.prevAlreadyInData = input.hasPrevChapter && input.prevChapterInData;
    plan.prevCanRequest = !input.prevChapterRequested && !input.isPrevChapterLoading &&
      (!input.hasPrevChapter || plan.prevAlreadyInData);
    if (!plan.prevCanRequest) {
      return;
    }

    const prevNotInData: boolean = !input.hasPrevChapter;
    if (prevNotInData && !input.prevConfirmPending) {
      plan.shouldStartPrevConfirm = true;
      return;
    }

    if (prevNotInData && input.prevConfirmPending) {
      const elapsed: number = input.now - input.prevConfirmTime;
      if (elapsed < 800) {
        plan.shouldKeepPrevConfirmWaiting = true;
        return;
      }
    }

    plan.shouldClearPrevConfirm = true;
    if (!this.isRequestIntervalReady(input.now, input.lastPrevRequestAt, input.adjacentRequestIntervalMs)) {
      plan.prevBlockedByCooldown = true;
      return;
    }

    plan.shouldRequestPrev = true;
    plan.shouldUpdatePrevRequestTime = true;
  }

  private isRequestIntervalReady(now: number, lastRequestAt: number, intervalMs: number): boolean {
    return now - lastRequestAt >= intervalMs;
  }
}
