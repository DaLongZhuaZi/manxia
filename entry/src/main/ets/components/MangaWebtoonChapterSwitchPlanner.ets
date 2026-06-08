// Responsibility: plan current chapter switch from webtoon scroll position.

import { ChapterBoundary } from './MangaWebtoonTypes';

export class MangaWebtoonChapterSwitchBoundaryRange {
  public boundary: ChapterBoundary | undefined = undefined;
  public boundaryIndex: number = -1;
  public startY: number = 0;
  public endY: number = 0;
  public pageIndexInChapter: number = 0;
}

export class MangaWebtoonChapterSwitchInput {
  public isWebtoonMode: boolean = false;
  public ranges: MangaWebtoonChapterSwitchBoundaryRange[] = [];
  public currentScrollY: number = 0;
  public containerHeight: number = 800;
  public currentChapterId: string = '';
  public pendingCandidateId: string = '';
  public pendingCandidateSince: number = 0;
  public pendingCandidatePageIndex: number = 0;
  public lastCommittedSwitchAt: number = 0;
  public hysteresisPx: number = 120;
  public stableMs: number = 90;
  public cooldownMs: number = 180;
  public now: number = 0;
}

export class MangaWebtoonChapterSwitchPlan {
  public shouldRun: boolean = false;
  public matchedBoundary: ChapterBoundary | undefined = undefined;
  public matchedBoundaryIndex: number = -1;
  public matchedStartY: number = 0;
  public matchedEndY: number = 0;
  public nearStart: boolean = false;
  public nearEnd: boolean = false;
  public shouldProtectBoundaryCache: boolean = false;
  public shouldPrewarmBoundaryContext: boolean = false;
  public shouldClearPendingCandidate: boolean = false;
  public shouldSetPendingCandidate: boolean = false;
  public pendingCandidateId: string = '';
  public pendingCandidateSince: number = 0;
  public pendingCandidatePageIndex: number = 0;
  public shouldCommitSwitch: boolean = false;
  public committedChapterId: string = '';
  public committedPageIndex: number = 0;
  public oldChapterId: string = '';
  public blockedByHysteresis: boolean = false;
  public waitingForStability: boolean = false;
  public blockedByCooldown: boolean = false;
}

export class MangaWebtoonChapterSwitchPlanner {
  public buildPlan(input: MangaWebtoonChapterSwitchInput): MangaWebtoonChapterSwitchPlan {
    const plan: MangaWebtoonChapterSwitchPlan = new MangaWebtoonChapterSwitchPlan();
    if (!input.isWebtoonMode || input.ranges.length <= 0) {
      return plan;
    }

    const matchedRange: MangaWebtoonChapterSwitchBoundaryRange | undefined = this.findMatchedRange(input);
    if (!matchedRange || !matchedRange.boundary) {
      return plan;
    }

    plan.shouldRun = true;
    plan.matchedBoundary = matchedRange.boundary;
    plan.matchedBoundaryIndex = matchedRange.boundaryIndex;
    plan.matchedStartY = matchedRange.startY;
    plan.matchedEndY = matchedRange.endY;

    const viewCenter: number = input.currentScrollY + input.containerHeight / 2;
    plan.nearStart = Math.abs(viewCenter - matchedRange.startY) <= input.hysteresisPx;
    plan.nearEnd = Math.abs(matchedRange.endY - viewCenter) <= input.hysteresisPx;
    if (plan.nearStart || plan.nearEnd) {
      plan.shouldProtectBoundaryCache = true;
      plan.shouldPrewarmBoundaryContext = true;
    }

    if (input.currentChapterId === matchedRange.boundary.chapterId) {
      plan.shouldClearPendingCandidate = true;
      return plan;
    }

    const inwardDistance: number = Math.min(viewCenter - matchedRange.startY, matchedRange.endY - viewCenter);
    if (inwardDistance < input.hysteresisPx) {
      plan.blockedByHysteresis = true;
      this.setPendingCandidate(plan, matchedRange.boundary.chapterId, input.now, matchedRange.pageIndexInChapter);
      if (input.pendingCandidateId === matchedRange.boundary.chapterId) {
        plan.pendingCandidateSince = input.pendingCandidateSince;
      }
      return plan;
    }

    if (input.pendingCandidateId !== matchedRange.boundary.chapterId) {
      this.setPendingCandidate(plan, matchedRange.boundary.chapterId, input.now, matchedRange.pageIndexInChapter);
      return plan;
    }

    if (input.now - input.pendingCandidateSince < input.stableMs) {
      plan.waitingForStability = true;
      this.setPendingCandidate(plan, matchedRange.boundary.chapterId, input.pendingCandidateSince, matchedRange.pageIndexInChapter);
      return plan;
    }

    if (input.now - input.lastCommittedSwitchAt < input.cooldownMs) {
      plan.blockedByCooldown = true;
      return plan;
    }

    plan.shouldCommitSwitch = true;
    plan.committedChapterId = matchedRange.boundary.chapterId;
    plan.committedPageIndex = input.pendingCandidatePageIndex;
    plan.oldChapterId = input.currentChapterId;
    plan.shouldClearPendingCandidate = true;
    plan.shouldProtectBoundaryCache = true;
    plan.shouldPrewarmBoundaryContext = true;
    return plan;
  }

  private findMatchedRange(input: MangaWebtoonChapterSwitchInput): MangaWebtoonChapterSwitchBoundaryRange | undefined {
    const viewCenter: number = input.currentScrollY + input.containerHeight / 2;
    for (let i = 0; i < input.ranges.length; i++) {
      const range: MangaWebtoonChapterSwitchBoundaryRange = input.ranges[i];
      if (viewCenter >= range.startY && viewCenter < range.endY) {
        return range;
      }
    }
    return undefined;
  }

  private setPendingCandidate(
    plan: MangaWebtoonChapterSwitchPlan,
    chapterId: string,
    since: number,
    pageIndex: number
  ): void {
    plan.shouldSetPendingCandidate = true;
    plan.pendingCandidateId = chapterId;
    plan.pendingCandidateSince = since;
    plan.pendingCandidatePageIndex = pageIndex;
  }
}
