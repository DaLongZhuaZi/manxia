// 职责: 计算漫画预加载计划，不接触 UI、加载器和状态管理器。

import { ImageSourceType, MangaPage } from '../Models/MangaModels';
import { PreloadTaskItem } from './PreloadManager';
import { WebtoonDataItem } from './MangaWebtoonTypes';

export class MangaPreloadInitTarget {
  public pageId: string = '';
  public pageIndex: number = 0;
}

export class MangaPreloadPlan {
  public tasks: PreloadTaskItem[] = [];
  public initTargets: MangaPreloadInitTarget[] = [];
  public visibleIndicesForManager: number[] = [];
  public currentIndex: number = 0;
  public totalCount: number = 0;
  public range: number = 0;
  public shouldApplyPageInfo: boolean = false;
  public shouldProcessQueue: boolean = false;
  public shouldScheduleQueue: boolean = false;
  public scheduleDelay: number = 0;
  public shouldCleanupWebtoonCompleted: boolean = false;
}

export class MangaNormalPreloadInput {
  public pages: MangaPage[] = [];
  public currentIndex: number = 0;
  public range: number = 0;
}

export class MangaWebtoonPreloadInput {
  public chapterPages: MangaPage[] = [];
  public webtoonDataItems: WebtoonDataItem[] = [];
  public visibleItemIndices: number[] = [];
  public visiblePageIndices: number[] = [];
  public currentItemIndex: number = 0;
  public range: number = 8;
}

export class MangaSinglePagePreloadInput {
  public page: MangaPage | undefined = undefined;
  public pageIndex: number = -1;
  public currentIndex: number = 0;
}

export class MangaPreloadPlanner {
  public buildNormalPlan(input: MangaNormalPreloadInput): MangaPreloadPlan {
    const plan: MangaPreloadPlan = new MangaPreloadPlan();
    plan.currentIndex = input.currentIndex;
    plan.totalCount = input.pages.length;
    plan.range = input.range;
    plan.shouldApplyPageInfo = true;
    plan.shouldProcessQueue = true;

    if (input.pages.length <= 0) {
      return plan;
    }

    const startIndex: number = Math.max(0, input.currentIndex - input.range);
    const endIndex: number = Math.min(input.pages.length - 1, input.currentIndex + input.range);
    for (let i = startIndex; i <= endIndex; i++) {
      const page: MangaPage = input.pages[i];
      if (!page) {
        continue;
      }
      const distance: number = Math.abs(i - input.currentIndex);
      const priority: number = input.range - distance + 1;
      plan.tasks.push(this.createTask(i, page, page.imageUrl ? page.imageUrl : '', priority));
    }

    return plan;
  }

  public buildWebtoonPlan(input: MangaWebtoonPreloadInput): MangaPreloadPlan {
    if (input.webtoonDataItems.length > 0) {
      return this.buildWebtoonDataPlan(input);
    }
    return this.buildWebtoonChapterFallbackPlan(input);
  }

  public buildSingleNetworkPagePlan(input: MangaSinglePagePreloadInput): MangaPreloadPlan {
    const plan: MangaPreloadPlan = new MangaPreloadPlan();
    plan.currentIndex = input.currentIndex;
    plan.range = 0;
    plan.shouldScheduleQueue = true;
    plan.scheduleDelay = 0;

    const page: MangaPage | undefined = input.page;
    if (!page || page.sourceType !== ImageSourceType.NETWORK || input.pageIndex < 0) {
      return plan;
    }

    const url: string = page.imageUrl ? page.imageUrl : '';
    if (url.length <= 0) {
      return plan;
    }

    const distance: number = Math.abs(input.pageIndex - input.currentIndex);
    const priority: number = distance === 0 ? 10 : Math.max(1, 10 - distance);
    plan.tasks.push(this.createTask(input.pageIndex, page, url, priority));
    plan.initTargets.push(this.createInitTarget(page.id, input.pageIndex));
    return plan;
  }

  private buildWebtoonDataPlan(input: MangaWebtoonPreloadInput): MangaPreloadPlan {
    const plan: MangaPreloadPlan = new MangaPreloadPlan();
    plan.currentIndex = input.currentItemIndex;
    plan.totalCount = input.webtoonDataItems.length;
    plan.range = input.range;
    plan.visibleIndicesForManager = this.copyNumberArray(input.visibleItemIndices);

    if (input.visibleItemIndices.length <= 0) {
      return plan;
    }

    const preloadItemIndices: number[] = this.collectWebtoonItemIndices(input);
    const taskByIndex: Map<number, PreloadTaskItem> = new Map();

    for (let i = 0; i < preloadItemIndices.length; i++) {
      const itemIndex: number = preloadItemIndices[i];
      const item: WebtoonDataItem = input.webtoonDataItems[itemIndex];
      if (!item || item.type !== 'page' || !item.page) {
        continue;
      }

      const page: MangaPage = item.page;
      const url: string = page.imageUrl ? page.imageUrl : '';
      if (url.length <= 0) {
        continue;
      }

      const minDistance: number = this.getMinDistance(itemIndex, input.visibleItemIndices);
      const priority: number = minDistance === 0 ? 10 : Math.max(1, 10 - minDistance);
      taskByIndex.set(itemIndex, this.createTask(itemIndex, page, url, priority));
      plan.initTargets.push(this.createInitTarget(page.id, itemIndex));
    }

    plan.tasks = this.mapTasksToArray(taskByIndex);
    if (plan.tasks.length > 0) {
      plan.shouldApplyPageInfo = true;
      plan.shouldScheduleQueue = true;
      plan.scheduleDelay = 0;
      plan.shouldCleanupWebtoonCompleted = true;
    }
    return plan;
  }

  private buildWebtoonChapterFallbackPlan(input: MangaWebtoonPreloadInput): MangaPreloadPlan {
    const plan: MangaPreloadPlan = new MangaPreloadPlan();
    plan.currentIndex = this.resolveCurrentVisibleIndex(input.visiblePageIndices, input.currentItemIndex);
    plan.totalCount = input.chapterPages.length;
    plan.range = input.range;
    plan.visibleIndicesForManager = this.copyNumberArray(input.visiblePageIndices);

    if (input.chapterPages.length <= 0 || input.visiblePageIndices.length <= 0) {
      return plan;
    }

    const taskByIndex: Map<number, PreloadTaskItem> = new Map();
    for (let i = 0; i < input.visiblePageIndices.length; i++) {
      const visibleIndex: number = input.visiblePageIndices[i];
      const startIndex: number = Math.max(0, visibleIndex - input.range);
      const endIndex: number = Math.min(input.chapterPages.length - 1, visibleIndex + input.range);

      for (let j = startIndex; j <= endIndex; j++) {
        const page: MangaPage = input.chapterPages[j];
        if (!page || page.sourceType !== ImageSourceType.NETWORK) {
          continue;
        }

        const url: string = page.imageUrl ? page.imageUrl : '';
        if (url.length <= 0) {
          continue;
        }

        const priority: number = Math.max(1, 10 - Math.abs(j - visibleIndex));
        this.addOrUpgradeTask(taskByIndex, j, this.createTask(j, page, url, priority));
      }
    }

    plan.tasks = this.mapTasksToArray(taskByIndex);
    if (plan.tasks.length > 0) {
      plan.shouldApplyPageInfo = true;
      plan.shouldScheduleQueue = true;
      plan.scheduleDelay = 0;
      plan.shouldCleanupWebtoonCompleted = true;
    }
    return plan;
  }

  private collectWebtoonItemIndices(input: MangaWebtoonPreloadInput): number[] {
    const result: number[] = [];
    const added: Set<number> = new Set();

    for (let i = 0; i < input.visibleItemIndices.length; i++) {
      const visibleItemIndex: number = input.visibleItemIndices[i];
      const startIndex: number = Math.max(0, visibleItemIndex - input.range);
      const endIndex: number = Math.min(input.webtoonDataItems.length - 1, visibleItemIndex + input.range);

      for (let j = startIndex; j <= endIndex; j++) {
        if (added.has(j)) {
          continue;
        }
        const item: WebtoonDataItem = input.webtoonDataItems[j];
        if (item && item.type === 'page' && item.page && item.page.sourceType === ImageSourceType.NETWORK) {
          added.add(j);
          result.push(j);
        }
      }
    }

    return result;
  }

  private addOrUpgradeTask(taskByIndex: Map<number, PreloadTaskItem>, index: number, task: PreloadTaskItem): void {
    const existing: PreloadTaskItem | undefined = taskByIndex.get(index);
    if (!existing || task.priority > existing.priority) {
      taskByIndex.set(index, task);
    }
  }

  private mapTasksToArray(taskByIndex: Map<number, PreloadTaskItem>): PreloadTaskItem[] {
    const tasks: PreloadTaskItem[] = [];
    const values: PreloadTaskItem[] = Array.from(taskByIndex.values());
    for (let i = 0; i < values.length; i++) {
      tasks.push(values[i]);
    }
    return tasks;
  }

  private getMinDistance(index: number, visibleIndices: number[]): number {
    let minDistance: number = Number.MAX_SAFE_INTEGER;
    for (let i = 0; i < visibleIndices.length; i++) {
      const distance: number = Math.abs(index - visibleIndices[i]);
      if (distance < minDistance) {
        minDistance = distance;
      }
    }
    return minDistance;
  }

  private resolveCurrentVisibleIndex(visibleIndices: number[], fallbackIndex: number): number {
    if (visibleIndices.length <= 0) {
      return fallbackIndex;
    }
    const middle: number = Math.floor(visibleIndices.length / 2);
    return visibleIndices[middle];
  }

  private copyNumberArray(source: number[]): number[] {
    const copy: number[] = [];
    for (let i = 0; i < source.length; i++) {
      copy.push(source[i]);
    }
    return copy;
  }

  private createInitTarget(pageId: string, pageIndex: number): MangaPreloadInitTarget {
    const target: MangaPreloadInitTarget = new MangaPreloadInitTarget();
    target.pageId = pageId;
    target.pageIndex = pageIndex;
    return target;
  }

  private createTask(pageIndex: number, page: MangaPage, url: string, priority: number): PreloadTaskItem {
    const task: PreloadTaskItem = {
      pageIndex: pageIndex,
      pageId: page.id,
      url: url,
      priority: priority
    } as PreloadTaskItem;
    return task;
  }
}
