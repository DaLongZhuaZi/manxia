// Responsibility: plan side effects when adjacent webtoon chapters arrive.

import { MangaChapter } from '../Models/MangaModels';
import { ChapterBoundary } from './MangaWebtoonTypes';

export class MangaWebtoonAdjacentChapterInput {
  public isWebtoonMode: boolean = false;
  public currentChapter: MangaChapter | undefined = undefined;
  public prevChapter: MangaChapter | undefined = undefined;
  public nextChapter: MangaChapter | undefined = undefined;
  public currentChapterId: string = '';
  public chapterBoundaries: ChapterBoundary[] = [];
}

export class MangaWebtoonAdjacentChapterPlan {
  public shouldRun: boolean = false;
  public currentInBoundaries: boolean = false;
  public prevInBoundaries: boolean = false;
  public nextInBoundaries: boolean = false;
  public prevIsNew: boolean = false;
  public nextIsNew: boolean = false;
  public shouldSyncCurrentChapterId: boolean = false;
  public syncedCurrentChapterId: string = '';
  public shouldSkipDataRebuild: boolean = false;
  public shouldInitWebtoonData: boolean = false;
  public shouldCheckBoundaryAfterData: boolean = false;
  public shouldResetPrevLoading: boolean = false;
  public shouldResetNextLoading: boolean = false;
  public shouldResetPrevRequest: boolean = false;
  public shouldResetNextRequest: boolean = false;
}

export class MangaWebtoonAdjacentChapterPlanner {
  public buildPlan(input: MangaWebtoonAdjacentChapterInput): MangaWebtoonAdjacentChapterPlan {
    const plan: MangaWebtoonAdjacentChapterPlan = new MangaWebtoonAdjacentChapterPlan();
    if (!input.isWebtoonMode) {
      return plan;
    }

    plan.shouldRun = true;
    plan.currentInBoundaries = this.hasBoundary(input.chapterBoundaries, input.currentChapterId);
    plan.prevInBoundaries = input.prevChapter ? this.hasBoundary(input.chapterBoundaries, input.prevChapter.id) : false;
    plan.nextInBoundaries = input.nextChapter ? this.hasBoundary(input.chapterBoundaries, input.nextChapter.id) : false;

    if (input.currentChapter && input.currentChapter.id !== input.currentChapterId && !plan.currentInBoundaries) {
      plan.shouldSyncCurrentChapterId = true;
      plan.syncedCurrentChapterId = input.currentChapter.id;
    }

    plan.prevIsNew = this.hasPages(input.prevChapter) && !plan.prevInBoundaries;
    plan.nextIsNew = this.hasPages(input.nextChapter) && !plan.nextInBoundaries;

    if (!plan.prevIsNew && !plan.nextIsNew) {
      plan.shouldSkipDataRebuild = true;
      plan.shouldResetPrevLoading = true;
      plan.shouldResetNextLoading = true;
      plan.shouldResetPrevRequest = plan.prevInBoundaries;
      plan.shouldResetNextRequest = plan.nextInBoundaries;
      return plan;
    }

    if (plan.prevIsNew) {
      plan.shouldResetPrevLoading = true;
      plan.shouldResetPrevRequest = true;
    }
    if (plan.nextIsNew) {
      plan.shouldResetNextLoading = true;
      plan.shouldResetNextRequest = true;
    }
    plan.shouldInitWebtoonData = true;
    plan.shouldCheckBoundaryAfterData = true;
    return plan;
  }

  private hasPages(chapter: MangaChapter | undefined): boolean {
    return !!(chapter && chapter.pages && chapter.pages.length > 0);
  }

  private hasBoundary(boundaries: ChapterBoundary[], chapterId: string): boolean {
    if (!chapterId) {
      return false;
    }
    for (let i = 0; i < boundaries.length; i++) {
      const boundary: ChapterBoundary = boundaries[i];
      if (boundary.chapterId === chapterId) {
        return true;
      }
    }
    return false;
  }
}
