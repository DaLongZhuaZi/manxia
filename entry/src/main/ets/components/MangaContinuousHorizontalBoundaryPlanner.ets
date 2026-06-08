// Responsibility: plan chapter requests for continuous horizontal manga reading.

export class MangaContinuousHorizontalBoundaryInput {
  public isContinuousScrollMode: boolean = false;
  public hasChapter: boolean = false;
  public hasChapterChangeCallback: boolean = false;
  public suppressedUntil: number = 0;
  public now: number = 0;
  public viewportWidth: number = 360;
  public maxScrollX: number = 0;
  public scrollPosition: number = 0;
  public isOnlineContent: boolean = false;
  public isRtl: boolean = false;
  public atFirstPage: boolean = false;
  public atLastPage: boolean = false;
  public isFirstChapter: boolean = false;
  public isLastChapter: boolean = false;
  public lastScrollDirection: string = 'down';
  public lastPrevRequestAt: number = 0;
  public lastNextRequestAt: number = 0;
  public adjacentRequestIntervalMs: number = 450;
}

export class MangaContinuousHorizontalBoundaryPlan {
  public shouldRun: boolean = false;
  public threshold: number = 0;
  public nearLeftEdge: boolean = false;
  public nearRightEdge: boolean = false;
  public shouldRequestPrev: boolean = false;
  public shouldRequestNext: boolean = false;
  public prevBlockedByBoundary: boolean = false;
  public nextBlockedByBoundary: boolean = false;
  public prevBlockedByCooldown: boolean = false;
  public nextBlockedByCooldown: boolean = false;
  public shouldUpdatePrevRequestTime: boolean = false;
  public shouldUpdateNextRequestTime: boolean = false;
}

export class MangaContinuousHorizontalBoundaryPlanner {
  public buildPlan(input: MangaContinuousHorizontalBoundaryInput): MangaContinuousHorizontalBoundaryPlan {
    const plan: MangaContinuousHorizontalBoundaryPlan = new MangaContinuousHorizontalBoundaryPlan();
    if (!input.isContinuousScrollMode || !input.hasChapter || !input.hasChapterChangeCallback) {
      return plan;
    }
    if (input.now < input.suppressedUntil) {
      return plan;
    }

    plan.shouldRun = true;
    plan.threshold = input.viewportWidth * (input.isOnlineContent ? 1.5 : 1.0);
    plan.nearLeftEdge = input.scrollPosition <= plan.threshold;
    plan.nearRightEdge = input.scrollPosition >= input.maxScrollX - plan.threshold;

    const scrollingTowardLargerOffset: boolean = input.lastScrollDirection === 'down';
    const scrollingTowardSmallerOffset: boolean = input.lastScrollDirection === 'up';
    const shouldGoNext: boolean = input.isRtl
      ? plan.nearLeftEdge && scrollingTowardSmallerOffset && input.atLastPage
      : plan.nearRightEdge && scrollingTowardLargerOffset && input.atLastPage;
    const shouldGoPrev: boolean = input.isRtl
      ? plan.nearRightEdge && scrollingTowardLargerOffset && input.atFirstPage
      : plan.nearLeftEdge && scrollingTowardSmallerOffset && input.atFirstPage;

    if (shouldGoNext) {
      this.planNextRequest(input, plan);
      return plan;
    }
    if (shouldGoPrev) {
      this.planPrevRequest(input, plan);
    }
    return plan;
  }

  private planNextRequest(input: MangaContinuousHorizontalBoundaryInput, plan: MangaContinuousHorizontalBoundaryPlan): void {
    if (input.isLastChapter) {
      plan.nextBlockedByBoundary = true;
      return;
    }
    if (!this.isRequestIntervalReady(input.now, input.lastNextRequestAt, input.adjacentRequestIntervalMs)) {
      plan.nextBlockedByCooldown = true;
      return;
    }
    plan.shouldRequestNext = true;
    plan.shouldUpdateNextRequestTime = true;
  }

  private planPrevRequest(input: MangaContinuousHorizontalBoundaryInput, plan: MangaContinuousHorizontalBoundaryPlan): void {
    if (input.isFirstChapter) {
      plan.prevBlockedByBoundary = true;
      return;
    }
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
