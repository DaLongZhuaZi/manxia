// 职责: 规划 PixelMap 加载完成后的展示刷新动作，不直接执行 UI 操作。

import { ReadingMode } from '../Models/MangaModels';

export class MangaLoadedPagePresentationContext {
  public readingMode: ReadingMode = ReadingMode.SINGLE_PAGE;
  public isWebtoonMode: boolean = false;
  public isVisible: boolean = false;
  public pageIndex: number = -1;
  public currentPageIndex: number = 0;
  public previousPageIndex: number = -1;
  public nextPageIndex: number = -1;
  public useSmartDoublePageLayout: boolean = false;
  public useAlbumNoneTransition: boolean = false;
  public useSoftNoneCrossfade: boolean = false;
  public showSoftTransitionOverlay: boolean = false;
}

export class MangaLoadedPagePresentationPlan {
  public isVisible: boolean = false;
  public shouldRefreshWebtoonItem: boolean = false;
  public shouldUpdateDoublePageIndices: boolean = false;
  public shouldUpdateDoublePageDisplay: boolean = false;
  public shouldUpdateDoublePagePreview: boolean = false;
  public shouldUpdateSinglePageDisplay: boolean = false;
  public shouldUpdateSinglePagePreview: boolean = false;
  public shouldScheduleSoftTransitionOverlayOut: boolean = false;
}

export class MangaLoadedPagePresentationPlanner {
  public build(context: MangaLoadedPagePresentationContext): MangaLoadedPagePresentationPlan {
    const plan: MangaLoadedPagePresentationPlan = new MangaLoadedPagePresentationPlan();
    plan.isVisible = context.isVisible;

    if (!context.isVisible) {
      if (context.readingMode === ReadingMode.DOUBLE_PAGE && context.useSmartDoublePageLayout) {
        plan.shouldUpdateDoublePagePreview = true;
      }
      if (context.useAlbumNoneTransition &&
        (context.pageIndex === context.previousPageIndex || context.pageIndex === context.nextPageIndex)) {
        plan.shouldUpdateSinglePagePreview = true;
      }
      return plan;
    }

    if (context.isWebtoonMode) {
      plan.shouldRefreshWebtoonItem = true;
      return plan;
    }

    if (context.readingMode === ReadingMode.DOUBLE_PAGE) {
      if (context.useSmartDoublePageLayout) {
        plan.shouldUpdateDoublePageIndices = true;
        plan.shouldUpdateDoublePageDisplay = true;
        plan.shouldUpdateDoublePagePreview = true;
      } else {
        plan.shouldUpdateDoublePageDisplay = true;
      }
      return plan;
    }

    plan.shouldUpdateSinglePageDisplay = true;
    plan.shouldScheduleSoftTransitionOverlayOut = context.useSoftNoneCrossfade &&
      context.showSoftTransitionOverlay &&
      context.pageIndex === context.currentPageIndex;
    return plan;
  }
}
