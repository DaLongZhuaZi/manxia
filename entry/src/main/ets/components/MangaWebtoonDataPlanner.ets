// 职责: 规划条漫多章节数据，不接触 UI、LazyForEach 数据源和滚动器。

import { MangaChapter, MangaPage } from '../Models/MangaModels';
import { ChapterBoundary, WebtoonDataItem } from './MangaWebtoonTypes';

export enum MangaWebtoonDataPlanKind {
  NONE = 'NONE',
  FULL_REBUILD = 'FULL_REBUILD',
  APPEND_NEXT = 'APPEND_NEXT'
}

export class MangaWebtoonDataPlannerInput {
  public currentChapter: MangaChapter | undefined = undefined;
  public prevChapter: MangaChapter | undefined = undefined;
  public nextChapter: MangaChapter | undefined = undefined;
  public existingItems: WebtoonDataItem[] = [];
  public existingBoundaries: ChapterBoundary[] = [];
  public existingDataCount: number = 0;
}

export class MangaWebtoonDataPlan {
  public kind: MangaWebtoonDataPlanKind = MangaWebtoonDataPlanKind.NONE;
  public items: WebtoonDataItem[] = [];
  public appendItems: WebtoonDataItem[] = [];
  public boundaries: ChapterBoundary[] = [];
  public currentChapterId: string = '';
  public hadPrevChapterInData: boolean = false;
  public shouldRebuildPositionCache: boolean = false;
  public shouldRebuildPageRefs: boolean = false;
}

export class MangaWebtoonDataPlanner {
  public buildPlan(input: MangaWebtoonDataPlannerInput): MangaWebtoonDataPlan {
    if (this.canDoIncrementalUpdate(input)) {
      return this.buildIncrementalPlan(input);
    }
    return this.buildFullRebuildPlan(input);
  }

  public canDoIncrementalUpdate(input: MangaWebtoonDataPlannerInput): boolean {
    if (!input.currentChapter || input.existingDataCount === 0) {
      return false;
    }
    return this.hasBoundary(input.existingBoundaries, input.currentChapter.id);
  }

  private buildIncrementalPlan(input: MangaWebtoonDataPlannerInput): MangaWebtoonDataPlan {
    const plan: MangaWebtoonDataPlan = new MangaWebtoonDataPlan();
    plan.kind = MangaWebtoonDataPlanKind.NONE;
    plan.currentChapterId = input.currentChapter ? input.currentChapter.id : '';
    plan.shouldRebuildPageRefs = true;

    if (!input.currentChapter) {
      return plan;
    }

    if (this.shouldFallbackToFullRebuildForPrev(input)) {
      return this.buildFullRebuildPlan(input);
    }

    if (input.nextChapter && this.canAppendNextChapter(input)) {
      plan.kind = MangaWebtoonDataPlanKind.APPEND_NEXT;
      plan.items = this.copyItems(input.existingItems);
      plan.boundaries = this.copyBoundaries(input.existingBoundaries);
      plan.appendItems = this.buildNextChapterItems(input.nextChapter, input.existingItems.length, plan.boundaries);
      plan.shouldRebuildPositionCache = plan.appendItems.length > 0;
    }

    return plan;
  }

  private buildFullRebuildPlan(input: MangaWebtoonDataPlannerInput): MangaWebtoonDataPlan {
    const plan: MangaWebtoonDataPlan = new MangaWebtoonDataPlan();
    plan.kind = MangaWebtoonDataPlanKind.FULL_REBUILD;
    plan.currentChapterId = input.currentChapter ? input.currentChapter.id : '';
    plan.hadPrevChapterInData = input.currentChapter
      ? this.hasPrevContentBeforeChapter(input.existingBoundaries, input.currentChapter.id)
      : false;
    plan.shouldRebuildPositionCache = true;
    plan.shouldRebuildPageRefs = true;

    if (!input.currentChapter) {
      return plan;
    }

    let globalIndex: number = 0;
    if (input.prevChapter && input.prevChapter.pages && input.prevChapter.pages.length > 0 &&
      input.prevChapter.id !== input.currentChapter.id) {
      const prevStartIndex: number = globalIndex;
      globalIndex = this.appendChapterPages(plan.items, input.prevChapter, globalIndex);
      plan.boundaries.push(this.createBoundary(input.prevChapter.id, prevStartIndex, globalIndex - 1, input.prevChapter.pages.length));
      plan.items.push(this.createDivider(input.prevChapter, 'prev', globalIndex));
      globalIndex++;
    }

    const currentStartIndex: number = globalIndex;
    globalIndex = this.appendChapterPages(plan.items, input.currentChapter, globalIndex);
    plan.boundaries.push(this.createBoundary(input.currentChapter.id, currentStartIndex, globalIndex - 1, input.currentChapter.pages.length));

    if (input.nextChapter && input.nextChapter.pages && input.nextChapter.pages.length > 0 &&
      input.nextChapter.id !== input.currentChapter.id &&
      !(input.prevChapter && input.nextChapter.id === input.prevChapter.id)) {
      plan.items.push(this.createDivider(input.nextChapter, 'next', globalIndex));
      globalIndex++;
      const nextStartIndex: number = globalIndex;
      globalIndex = this.appendChapterPages(plan.items, input.nextChapter, globalIndex);
      plan.boundaries.push(this.createBoundary(input.nextChapter.id, nextStartIndex, globalIndex - 1, input.nextChapter.pages.length));
    }

    return plan;
  }

  private canAppendNextChapter(input: MangaWebtoonDataPlannerInput): boolean {
    if (!input.nextChapter || !input.nextChapter.pages || input.nextChapter.pages.length <= 0) {
      return false;
    }
    return !this.hasBoundary(input.existingBoundaries, input.nextChapter.id);
  }

  private shouldFallbackToFullRebuildForPrev(input: MangaWebtoonDataPlannerInput): boolean {
    if (!input.prevChapter || !input.prevChapter.pages || input.prevChapter.pages.length <= 0) {
      return false;
    }
    return !this.hasBoundary(input.existingBoundaries, input.prevChapter.id);
  }

  private buildNextChapterItems(
    nextChapter: MangaChapter,
    startGlobalIndex: number,
    boundaries: ChapterBoundary[]
  ): WebtoonDataItem[] {
    const newItems: WebtoonDataItem[] = [];
    let globalIndex: number = startGlobalIndex;
    newItems.push(this.createDivider(nextChapter, 'next', globalIndex));
    globalIndex++;

    const nextStartIndex: number = globalIndex;
    for (let i = 0; i < nextChapter.pages.length; i++) {
      const page: MangaPage = nextChapter.pages[i];
      newItems.push(this.createPageItem(page, nextChapter.id, i, globalIndex));
      globalIndex++;
    }
    boundaries.push(this.createBoundary(nextChapter.id, nextStartIndex, globalIndex - 1, nextChapter.pages.length));
    return newItems;
  }

  private appendChapterPages(items: WebtoonDataItem[], chapter: MangaChapter, globalIndex: number): number {
    let nextGlobalIndex: number = globalIndex;
    for (let i = 0; i < chapter.pages.length; i++) {
      const page: MangaPage = chapter.pages[i];
      items.push(this.createPageItem(page, chapter.id, i, nextGlobalIndex));
      nextGlobalIndex++;
    }
    return nextGlobalIndex;
  }

  private hasBoundary(boundaries: ChapterBoundary[], chapterId: string): boolean {
    for (let i = 0; i < boundaries.length; i++) {
      if (boundaries[i].chapterId === chapterId) {
        return true;
      }
    }
    return false;
  }

  private hasPrevContentBeforeChapter(boundaries: ChapterBoundary[], chapterId: string): boolean {
    for (let i = 0; i < boundaries.length; i++) {
      const boundary: ChapterBoundary = boundaries[i];
      if (boundary.chapterId === chapterId) {
        return boundary.startIndex > 0;
      }
    }
    return false;
  }

  private copyItems(source: WebtoonDataItem[]): WebtoonDataItem[] {
    const result: WebtoonDataItem[] = [];
    for (let i = 0; i < source.length; i++) {
      result.push(source[i]);
    }
    return result;
  }

  private copyBoundaries(source: ChapterBoundary[]): ChapterBoundary[] {
    const result: ChapterBoundary[] = [];
    for (let i = 0; i < source.length; i++) {
      const boundary: ChapterBoundary = source[i];
      result.push(this.createBoundary(boundary.chapterId, boundary.startIndex, boundary.endIndex, boundary.pageCount));
    }
    return result;
  }

  private createDivider(chapter: MangaChapter, direction: 'prev' | 'next', globalIndex: number): WebtoonDataItem {
    return {
      type: 'chapter_divider',
      chapterId: chapter.id,
      chapterTitle: chapter.title,
      direction: direction,
      globalIndex: globalIndex
    } as WebtoonDataItem;
  }

  private createPageItem(page: MangaPage, chapterId: string, pageIndex: number, globalIndex: number): WebtoonDataItem {
    return {
      type: 'page',
      page: page,
      chapterId: chapterId,
      pageIndex: pageIndex,
      globalIndex: globalIndex
    } as WebtoonDataItem;
  }

  private createBoundary(chapterId: string, startIndex: number, endIndex: number, pageCount: number): ChapterBoundary {
    return {
      chapterId: chapterId,
      startIndex: startIndex,
      endIndex: endIndex,
      pageCount: pageCount
    } as ChapterBoundary;
  }
}
