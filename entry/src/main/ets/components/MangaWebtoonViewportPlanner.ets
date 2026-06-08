// Responsibility: plan webtoon viewport visibility and progress state.

export class MangaWebtoonViewportItemRange {
  public itemIndex: number = -1;
  public isPage: boolean = false;
  public chapterId: string = '';
  public pageIndex: number = 0;
  public top: number = 0;
  public bottom: number = 0;
}

export class MangaWebtoonViewportInput {
  public activeChapterId: string = '';
  public rangeStart: number = 0;
  public rangeEnd: number = 0;
  public items: MangaWebtoonViewportItemRange[] = [];
}

export class MangaWebtoonViewportPlan {
  public visiblePageIndices: number[] = [];
  public visibleItemIndices: number[] = [];
}

export class MangaWebtoonFallbackPageRange {
  public pageIndex: number = 0;
  public top: number = 0;
  public bottom: number = 0;
}

export class MangaWebtoonFallbackViewportInput {
  public rangeStart: number = 0;
  public rangeEnd: number = 0;
  public pages: MangaWebtoonFallbackPageRange[] = [];
}

export class MangaWebtoonProgressInput {
  public useMultiChapter: boolean = false;
  public currentChapterId: string = '';
  public primaryChapterId: string = '';
  public currentBoundaryPageCount: number = 0;
  public currentBoundaryPageIndex: number = 0;
  public visiblePageIndices: number[] = [];
  public currentWebtoonPage: number = 0;
  public fallbackTotalPages: number = 0;
  public fallbackTotalHeight: number = 0;
  public scrollPosition: number = 0;
  public containerHeight: number = 800;
}

export class MangaWebtoonProgressPlan {
  public shouldUpdatePage: boolean = false;
  public shouldSyncExternalPage: boolean = false;
  public shouldNotifyPageChange: boolean = false;
  public pageIndex: number = 0;
  public shouldUpdateProgress: boolean = false;
  public progress: number = 0;
}

export class MangaWebtoonViewportPlanner {
  public buildMultiChapterPlan(input: MangaWebtoonViewportInput): MangaWebtoonViewportPlan {
    const plan: MangaWebtoonViewportPlan = new MangaWebtoonViewportPlan();
    for (let i = 0; i < input.items.length; i++) {
      const item: MangaWebtoonViewportItemRange = input.items[i];
      if (item.bottom < input.rangeStart || item.top > input.rangeEnd) {
        continue;
      }
      plan.visibleItemIndices.push(item.itemIndex);
      if (item.isPage && item.chapterId === input.activeChapterId) {
        plan.visiblePageIndices.push(item.pageIndex);
      }
    }

    if (plan.visiblePageIndices.length === 0 && plan.visibleItemIndices.length > 0) {
      this.appendFirstVisiblePageFallback(input, plan);
    }
    return plan;
  }

  public buildFallbackPlan(input: MangaWebtoonFallbackViewportInput): MangaWebtoonViewportPlan {
    const plan: MangaWebtoonViewportPlan = new MangaWebtoonViewportPlan();
    for (let i = 0; i < input.pages.length; i++) {
      const page: MangaWebtoonFallbackPageRange = input.pages[i];
      if (page.bottom >= input.rangeStart && page.top <= input.rangeEnd) {
        plan.visiblePageIndices.push(page.pageIndex);
        plan.visibleItemIndices.push(page.pageIndex);
      }
    }
    return plan;
  }

  public buildProgressPlan(input: MangaWebtoonProgressInput): MangaWebtoonProgressPlan {
    const plan: MangaWebtoonProgressPlan = new MangaWebtoonProgressPlan();
    if (input.useMultiChapter) {
      this.buildMultiChapterProgressPlan(input, plan);
      return plan;
    }
    this.buildFallbackProgressPlan(input, plan);
    return plan;
  }

  private appendFirstVisiblePageFallback(input: MangaWebtoonViewportInput, plan: MangaWebtoonViewportPlan): void {
    for (let i = 0; i < plan.visibleItemIndices.length; i++) {
      const itemIndex: number = plan.visibleItemIndices[i];
      const item: MangaWebtoonViewportItemRange | undefined = this.findItemByIndex(input.items, itemIndex);
      if (item && item.isPage) {
        plan.visiblePageIndices.push(item.pageIndex);
        return;
      }
    }
  }

  private findItemByIndex(
    items: MangaWebtoonViewportItemRange[],
    itemIndex: number
  ): MangaWebtoonViewportItemRange | undefined {
    for (let i = 0; i < items.length; i++) {
      const item: MangaWebtoonViewportItemRange = items[i];
      if (item.itemIndex === itemIndex) {
        return item;
      }
    }
    return undefined;
  }

  private buildMultiChapterProgressPlan(input: MangaWebtoonProgressInput, plan: MangaWebtoonProgressPlan): void {
    const pageIndex: number = input.currentBoundaryPageIndex;
    if (pageIndex !== input.currentWebtoonPage) {
      plan.shouldUpdatePage = true;
      plan.pageIndex = pageIndex;
      plan.shouldSyncExternalPage = input.currentChapterId === input.primaryChapterId;
      plan.shouldNotifyPageChange = plan.shouldSyncExternalPage;
    }
    plan.shouldUpdateProgress = true;
    plan.progress = this.clamp(pageIndex / Math.max(1, input.currentBoundaryPageCount - 1), 0, 1);
  }

  private buildFallbackProgressPlan(input: MangaWebtoonProgressInput, plan: MangaWebtoonProgressPlan): void {
    if (input.visiblePageIndices.length > 0) {
      const middleIndex: number = Math.floor(input.visiblePageIndices.length / 2);
      const newPage: number = input.visiblePageIndices[middleIndex];
      if (newPage !== input.currentWebtoonPage) {
        plan.shouldUpdatePage = true;
        plan.pageIndex = newPage;
        plan.shouldSyncExternalPage = true;
        plan.shouldNotifyPageChange = true;
      }
    }

    if (input.fallbackTotalPages > 0) {
      const maxScrollable: number = Math.max(1, input.fallbackTotalHeight - input.containerHeight);
      plan.shouldUpdateProgress = true;
      plan.progress = this.clamp(input.scrollPosition / maxScrollable, 0, 1);
    }
  }

  private clamp(value: number, minValue: number, maxValue: number): number {
    return Math.max(minValue, Math.min(maxValue, value));
  }
}
