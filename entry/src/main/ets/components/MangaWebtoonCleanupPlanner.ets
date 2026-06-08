// 职责: 规划条漫资源清理范围，不释放 PixelMap，也不操作缓存实例。

import { MangaPage } from '../Models/MangaModels';
import { ChapterBoundary, WebtoonDataItem } from './MangaWebtoonTypes';

export class MangaWebtoonChapterCleanupRange {
  public chapterId: string = '';
  public startY: number = 0;
  public endY: number = 0;
}

export class MangaWebtoonLocalCacheCleanupPlan {
  public shouldCleanup: boolean = false;
  public visiblePageIds: string[] = [];
  public allPageIds: string[] = [];
}

export class MangaWebtoonCleanupInput {
  public isWebtoonMode: boolean = false;
  public isScrolling: boolean = false;
  public isBoundaryProtected: boolean = false;
  public primaryChapterId: string = '';
  public currentChapterId: string = '';
  public scrollPosition: number = 0;
  public containerHeight: number = 800;
  public scrollDirection: string = '';
  public chapterRanges: MangaWebtoonChapterCleanupRange[] = [];
  public chapterBoundaries: ChapterBoundary[] = [];
  public webtoonDataItems: WebtoonDataItem[] = [];
  public fallbackPages: MangaPage[] = [];
  public visiblePageIndices: number[] = [];
  public currentWebtoonPage: number = 0;
}

export class MangaWebtoonCleanupPlan {
  public chapterIdsToCleanup: string[] = [];
  public localCachePlan: MangaWebtoonLocalCacheCleanupPlan = new MangaWebtoonLocalCacheCleanupPlan();
}

export class MangaWebtoonCleanupPlanner {
  public buildPlan(input: MangaWebtoonCleanupInput): MangaWebtoonCleanupPlan {
    const plan: MangaWebtoonCleanupPlan = new MangaWebtoonCleanupPlan();
    if (!input.isWebtoonMode || input.chapterRanges.length <= 0 || input.isScrolling || input.isBoundaryProtected) {
      return plan;
    }

    this.collectChapterCleanupTargets(input, plan);
    plan.localCachePlan = this.buildLocalCacheCleanupPlan(input);
    return plan;
  }

  private collectChapterCleanupTargets(input: MangaWebtoonCleanupInput, plan: MangaWebtoonCleanupPlan): void {
    const cleanupThreshold: number = input.containerHeight * 10;
    const directionBonus: number = input.containerHeight * 3;
    const visibleBottom: number = input.scrollPosition + input.containerHeight;

    for (let i = 0; i < input.chapterRanges.length; i++) {
      const range: MangaWebtoonChapterCleanupRange = input.chapterRanges[i];
      if (range.chapterId === input.primaryChapterId || range.chapterId === input.currentChapterId) {
        continue;
      }

      const isAbove: boolean = range.endY < input.scrollPosition;
      const isBelow: boolean = range.startY > visibleBottom;
      let distanceToVisible: number = 0;
      if (isAbove) {
        distanceToVisible = input.scrollPosition - range.endY;
      } else if (isBelow) {
        distanceToVisible = range.startY - visibleBottom;
      } else {
        continue;
      }

      let effectiveThreshold: number = cleanupThreshold;
      if ((input.scrollDirection === 'down' && isBelow) || (input.scrollDirection === 'up' && isAbove)) {
        effectiveThreshold += directionBonus;
      }

      if (distanceToVisible > effectiveThreshold) {
        plan.chapterIdsToCleanup.push(range.chapterId);
      }
    }
  }

  private buildLocalCacheCleanupPlan(input: MangaWebtoonCleanupInput): MangaWebtoonLocalCacheCleanupPlan {
    const plan: MangaWebtoonLocalCacheCleanupPlan = new MangaWebtoonLocalCacheCleanupPlan();
    if (input.isScrolling || input.fallbackPages.length <= 0) {
      return plan;
    }

    const currentBoundary: ChapterBoundary | undefined = this.resolveCurrentBoundary(input);
    if (input.isWebtoonMode && currentBoundary && input.webtoonDataItems.length > 0) {
      this.collectCurrentBoundaryPageIds(input, currentBoundary, plan);
    }

    if (plan.allPageIds.length === 0) {
      this.collectFallbackPageIds(input, plan);
    }

    plan.shouldCleanup = plan.allPageIds.length > 0;
    return plan;
  }

  private collectCurrentBoundaryPageIds(
    input: MangaWebtoonCleanupInput,
    currentBoundary: ChapterBoundary,
    plan: MangaWebtoonLocalCacheCleanupPlan
  ): void {
    let pageIndexInChapter: number = 0;
    for (let i = currentBoundary.startIndex; i <= currentBoundary.endIndex && i < input.webtoonDataItems.length; i++) {
      const item: WebtoonDataItem = input.webtoonDataItems[i];
      if (item && item.type === 'page' && item.page) {
        const pageId: string = item.page.id;
        plan.allPageIds.push(pageId);
        if (this.numberArrayContains(input.visiblePageIndices, pageIndexInChapter)) {
          plan.visiblePageIds.push(pageId);
        }
        pageIndexInChapter++;
      }
    }

    if (plan.visiblePageIds.length === 0 && pageIndexInChapter > 0) {
      const fallbackIndex: number = Math.max(0, Math.min(input.currentWebtoonPage, pageIndexInChapter - 1));
      let seenPageIndex: number = 0;
      for (let i = currentBoundary.startIndex; i <= currentBoundary.endIndex && i < input.webtoonDataItems.length; i++) {
        const fallbackItem: WebtoonDataItem = input.webtoonDataItems[i];
        if (fallbackItem && fallbackItem.type === 'page' && fallbackItem.page) {
          if (seenPageIndex === fallbackIndex) {
            plan.visiblePageIds.push(fallbackItem.page.id);
            break;
          }
          seenPageIndex++;
        }
      }
    }
  }

  private collectFallbackPageIds(input: MangaWebtoonCleanupInput, plan: MangaWebtoonLocalCacheCleanupPlan): void {
    for (let i = 0; i < input.fallbackPages.length; i++) {
      const page: MangaPage = input.fallbackPages[i];
      plan.allPageIds.push(page.id);
      if (this.numberArrayContains(input.visiblePageIndices, i)) {
        plan.visiblePageIds.push(page.id);
      }
    }
  }

  private resolveCurrentBoundary(input: MangaWebtoonCleanupInput): ChapterBoundary | undefined {
    if (input.currentChapterId.length > 0) {
      const currentBoundary: ChapterBoundary | undefined = this.findBoundary(input.chapterBoundaries, input.currentChapterId);
      if (currentBoundary) {
        return currentBoundary;
      }
    }
    return this.findBoundary(input.chapterBoundaries, input.primaryChapterId);
  }

  private findBoundary(boundaries: ChapterBoundary[], chapterId: string): ChapterBoundary | undefined {
    for (let i = 0; i < boundaries.length; i++) {
      const boundary: ChapterBoundary = boundaries[i];
      if (boundary.chapterId === chapterId) {
        return boundary;
      }
    }
    return undefined;
  }

  private numberArrayContains(values: number[], target: number): boolean {
    for (let i = 0; i < values.length; i++) {
      if (values[i] === target) {
        return true;
      }
    }
    return false;
  }
}
