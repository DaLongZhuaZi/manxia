// 职责: 解析漫画阅读流中的页面、条漫索引和预加载任务，不触碰 UI 状态和加载器。

import { MangaChapter, MangaPage } from '../Models/MangaModels';
import { PreloadTaskItem } from './PreloadManager';
import { WebtoonDataItem, WebtoonPageRef } from './MangaWebtoonTypes';

export class MangaPageResolveContext {
  public chapter: MangaChapter | undefined = undefined;
  public isWebtoonMode: boolean = false;
  public webtoonDataItems: WebtoonDataItem[] = [];
  public webtoonPageRefById: Map<string, WebtoonPageRef> = new Map();
  public webtoonVisibleItemIndices: number[] = [];
  public currentPageIndex: number = 0;
}

export class MangaPreloadPageResolveResult {
  public page: MangaPage | null = null;
  public loadQueueIndex: number = -1;
  public found: boolean = false;
}

export class MangaPageLoadResolver {
  public getPageIndexById(chapter: MangaChapter | undefined, pageId: string): number {
    if (!chapter || !chapter.pages) {
      return -1;
    }
    const total: number = chapter.pages.length;
    for (let i = 0; i < total; i++) {
      const page: MangaPage = chapter.pages[i];
      if (page && page.id === pageId) {
        return i;
      }
    }
    return -1;
  }

  public resolvePageById(pageId: string, context: MangaPageResolveContext): MangaPage | undefined {
    if (context.isWebtoonMode) {
      const webtoonRef: WebtoonPageRef | undefined = context.webtoonPageRefById.get(pageId);
      if (webtoonRef && webtoonRef.page) {
        return webtoonRef.page;
      }
    }
    if (!context.chapter || !context.chapter.pages) {
      return undefined;
    }
    const pageIndex: number = this.getPageIndexById(context.chapter, pageId);
    if (pageIndex >= 0 && pageIndex < context.chapter.pages.length) {
      return context.chapter.pages[pageIndex];
    }
    return undefined;
  }

  public resolvePreloadTask(
    task: PreloadTaskItem,
    context: MangaPageResolveContext
  ): MangaPreloadPageResolveResult {
    const result: MangaPreloadPageResolveResult = new MangaPreloadPageResolveResult();
    result.loadQueueIndex = task.pageIndex;

    let page: MangaPage | undefined = undefined;
    if (context.isWebtoonMode) {
      page = this.resolveWebtoonTaskPage(task, context);
    } else {
      page = this.resolveNormalTaskPage(task, context);
    }

    if (page) {
      result.page = page;
      result.found = true;
    }
    return result;
  }

  public resolveManagedPageIndex(
    page: MangaPage,
    fallbackIndex: number,
    context: MangaPageResolveContext
  ): number {
    let pageIndex: number = -1;
    if (context.isWebtoonMode) {
      const ref: WebtoonPageRef | undefined = context.webtoonPageRefById.get(page.id);
      pageIndex = ref ? ref.itemIndex : -1;
    }
    if (pageIndex < 0) {
      pageIndex = this.getPageIndexById(context.chapter, page.id);
    }
    if (pageIndex < 0) {
      pageIndex = page.index !== undefined ? page.index : fallbackIndex;
    }
    return pageIndex >= 0 ? pageIndex : 0;
  }

  public resolvePreloadIndexForPage(page: MangaPage, context: MangaPageResolveContext): number {
    if (context.isWebtoonMode) {
      const ref: WebtoonPageRef | undefined = context.webtoonPageRefById.get(page.id);
      if (ref) {
        return ref.itemIndex;
      }
    }
    if (page.index !== undefined) {
      return page.index;
    }
    return this.getPageIndexById(context.chapter, page.id);
  }

  public resolveWebtoonQueueIndex(
    page: MangaPage,
    pageIndexHint: number,
    context: MangaPageResolveContext
  ): number {
    const ref: WebtoonPageRef | undefined = context.webtoonPageRefById.get(page.id);
    if (ref) {
      return ref.itemIndex;
    }
    if (pageIndexHint >= 0) {
      return pageIndexHint;
    }
    return this.resolvePreloadIndexForPage(page, context);
  }

  public getCurrentWebtoonItemIndexForPreload(context: MangaPageResolveContext): number {
    if (context.webtoonVisibleItemIndices.length > 0) {
      const middle: number = Math.floor(context.webtoonVisibleItemIndices.length / 2);
      return context.webtoonVisibleItemIndices[middle];
    }
    const currentPage: MangaPage | undefined = (context.chapter && context.chapter.pages &&
      context.currentPageIndex >= 0 && context.currentPageIndex < context.chapter.pages.length)
      ? context.chapter.pages[context.currentPageIndex]
      : undefined;
    if (currentPage) {
      const ref: WebtoonPageRef | undefined = context.webtoonPageRefById.get(currentPage.id);
      if (ref) {
        return ref.itemIndex;
      }
    }
    return 0;
  }

  public isPageResolvable(page: MangaPage, context: MangaPageResolveContext): boolean {
    if (context.isWebtoonMode && context.webtoonPageRefById.has(page.id)) {
      return true;
    }
    return this.resolvePageById(page.id, context) !== undefined;
  }

  private resolveNormalTaskPage(
    task: PreloadTaskItem,
    context: MangaPageResolveContext
  ): MangaPage | undefined {
    const pageById: MangaPage | undefined = this.resolvePageById(task.pageId, context);
    if (pageById) {
      return pageById;
    }
    if (!context.chapter || !context.chapter.pages) {
      return undefined;
    }
    if (task.pageIndex >= 0 && task.pageIndex < context.chapter.pages.length) {
      return context.chapter.pages[task.pageIndex];
    }
    return undefined;
  }

  private resolveWebtoonTaskPage(
    task: PreloadTaskItem,
    context: MangaPageResolveContext
  ): MangaPage | undefined {
    const ref: WebtoonPageRef | undefined = context.webtoonPageRefById.get(task.pageId);
    if (ref && ref.page) {
      return ref.page;
    }

    const pageById: MangaPage | undefined = this.resolvePageById(task.pageId, context);
    if (pageById) {
      return pageById;
    }

    if (task.pageIndex >= 0 && task.pageIndex < context.webtoonDataItems.length) {
      const item: WebtoonDataItem = context.webtoonDataItems[task.pageIndex];
      if (item && item.type === 'page' && item.page) {
        return item.page;
      }
    }
    return undefined;
  }
}
