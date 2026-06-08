// Responsibility: choose webtoon boundary edge pages to prewarm.

import { MangaPage } from '../Models/MangaModels';

export class MangaWebtoonPrewarmInput {
  public chapterId: string = '';
  public pages: MangaPage[] = [];
  public isOnlineContent: boolean = false;
  public now: number = 0;
  public lastPrewarmAt: number = 0;
}

export class MangaWebtoonPrewarmPlan {
  public shouldPrewarm: boolean = false;
  public chapterId: string = '';
  public shouldUpdatePrewarmTime: boolean = false;
  public pages: MangaPage[] = [];
}

export class MangaWebtoonPrewarmPlanner {
  public buildPlan(input: MangaWebtoonPrewarmInput): MangaWebtoonPrewarmPlan {
    const plan: MangaWebtoonPrewarmPlan = new MangaWebtoonPrewarmPlan();
    if (!input.chapterId || input.pages.length === 0) {
      return plan;
    }

    const minInterval: number = input.isOnlineContent ? 1200 : 500;
    if (input.now - input.lastPrewarmAt < minInterval) {
      return plan;
    }

    plan.shouldPrewarm = true;
    plan.chapterId = input.chapterId;
    plan.shouldUpdatePrewarmTime = true;
    plan.pages = this.collectEdgePages(input.pages, input.isOnlineContent ? 5 : 3);
    return plan;
  }

  private collectEdgePages(pages: MangaPage[], edgeWindow: number): MangaPage[] {
    const targets: MangaPage[] = [];
    const seen: Set<string> = new Set<string>();
    const total: number = pages.length;

    for (let i = 0; i < edgeWindow && i < total; i++) {
      this.pushIfNeeded(targets, seen, pages[i]);
    }
    for (let i = 0; i < edgeWindow && i < total; i++) {
      this.pushIfNeeded(targets, seen, pages[total - 1 - i]);
    }
    return targets;
  }

  private pushIfNeeded(targets: MangaPage[], seen: Set<string>, page: MangaPage | undefined): void {
    if (!page || seen.has(page.id)) {
      return;
    }
    seen.add(page.id);
    targets.push(page);
  }
}
