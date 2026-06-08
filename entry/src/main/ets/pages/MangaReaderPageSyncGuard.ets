// Responsibility: decide whether parent reader page should accept page callbacks during chapter switches.

export type MangaReaderChapterSwitchDirection = 'prev' | 'next';

export class ChapterSwitchPageGuard {
  public chapterId: string = '';
  public pageIndex: number = 0;
  public direction: MangaReaderChapterSwitchDirection = 'next';
  public expiresAt: number = 0;
}

export class MangaReaderPageGuardStatusInput {
  public guard: ChapterSwitchPageGuard | null = null;
  public currentChapterId: string = '';
  public now: number = 0;
}

export class MangaReaderPageGuardStatusPlan {
  public hasActiveGuard: boolean = false;
  public shouldExpireGuard: boolean = false;
  public shouldIgnoreForChapterMismatch: boolean = false;
  public guard: ChapterSwitchPageGuard | null = null;
}

export class MangaReaderPageChangeGuardInput {
  public guard: ChapterSwitchPageGuard | null = null;
  public normalizedPageIndex: number = 0;
}

export class MangaReaderPageChangeGuardPlan {
  public shouldAccept: boolean = true;
  public shouldClearGuard: boolean = false;
  public expectedPageIndex: number = -1;
  public direction: MangaReaderChapterSwitchDirection = 'next';
}

export class MangaReaderPageSyncGuard {
  public getGuardStatus(input: MangaReaderPageGuardStatusInput): MangaReaderPageGuardStatusPlan {
    const plan: MangaReaderPageGuardStatusPlan = new MangaReaderPageGuardStatusPlan();
    if (!input.guard) {
      return plan;
    }
    if (input.now > input.guard.expiresAt) {
      plan.shouldExpireGuard = true;
      plan.guard = input.guard;
      return plan;
    }
    if (input.currentChapterId.length > 0 && input.guard.chapterId !== input.currentChapterId) {
      plan.shouldIgnoreForChapterMismatch = true;
      plan.guard = input.guard;
      return plan;
    }
    plan.hasActiveGuard = true;
    plan.guard = input.guard;
    return plan;
  }

  public buildPageChangePlan(input: MangaReaderPageChangeGuardInput): MangaReaderPageChangeGuardPlan {
    const plan: MangaReaderPageChangeGuardPlan = new MangaReaderPageChangeGuardPlan();
    if (!input.guard) {
      return plan;
    }
    plan.expectedPageIndex = input.guard.pageIndex;
    plan.direction = input.guard.direction;
    if (input.normalizedPageIndex === input.guard.pageIndex) {
      plan.shouldAccept = true;
      plan.shouldClearGuard = true;
      return plan;
    }
    plan.shouldAccept = false;
    return plan;
  }
}
