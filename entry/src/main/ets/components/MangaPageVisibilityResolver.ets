// 职责: 统一判断页面在当前阅读窗口中的可见性，不触碰 UI 刷新和加载状态。

import { MangaChapter, MangaPage, ReadingMode } from 'manxia_core/src/main/ets/Models/MangaModels';
import { MangaPageLoadResolver } from './MangaPageLoadResolver';
import { WebtoonPageRef } from './MangaWebtoonTypes';

export class MangaPageVisibilityContext {
  public chapter: MangaChapter | undefined = undefined;
  public readingMode: ReadingMode = ReadingMode.SINGLE_PAGE;
  public isWebtoonMode: boolean = false;
  public leftPageIndex: number = -1;
  public rightPageIndex: number = -1;
  public viewCurrentPageIndex: number = 0;
  public visiblePageIndices: number[] = [];
  public webtoonVisibleItemIndices: number[] = [];
  public webtoonPageRefById: Map<string, WebtoonPageRef> = new Map();
}

export class MangaPageVisibilityResult {
  public pageIndex: number = -1;
  public webtoonItemIndex: number = -1;
  public displayIndex: number = -1;
  public isVisible: boolean = false;
}

export class MangaPageVisibilityResolver {
  private pageLoadResolver: MangaPageLoadResolver = new MangaPageLoadResolver();

  public resolve(page: MangaPage, context: MangaPageVisibilityContext): MangaPageVisibilityResult {
    const result: MangaPageVisibilityResult = new MangaPageVisibilityResult();
    result.pageIndex = this.pageLoadResolver.getPageIndexById(context.chapter, page.id);
    const ref: WebtoonPageRef | undefined = context.webtoonPageRefById.get(page.id);
    result.webtoonItemIndex = ref ? ref.itemIndex : -1;
    result.displayIndex = result.pageIndex >= 0 ? result.pageIndex : result.webtoonItemIndex;

    if (context.readingMode === ReadingMode.DOUBLE_PAGE) {
      result.isVisible = result.pageIndex >= 0 &&
        (result.pageIndex === context.leftPageIndex || result.pageIndex === context.rightPageIndex);
      return result;
    }

    if (context.isWebtoonMode) {
      if (result.webtoonItemIndex >= 0 &&
        this.containsIndex(context.webtoonVisibleItemIndices, result.webtoonItemIndex)) {
        result.isVisible = true;
        return result;
      }
      result.isVisible = result.pageIndex >= 0 && this.containsIndex(context.visiblePageIndices, result.pageIndex);
      return result;
    }

    result.isVisible = result.pageIndex >= 0 && result.pageIndex === context.viewCurrentPageIndex;
    return result;
  }

  public isPageVisible(page: MangaPage, context: MangaPageVisibilityContext): boolean {
    const result: MangaPageVisibilityResult = this.resolve(page, context);
    return result.isVisible;
  }

  private containsIndex(indices: number[], target: number): boolean {
    for (let i = 0; i < indices.length; i++) {
      if (indices[i] === target) {
        return true;
      }
    }
    return false;
  }
}
