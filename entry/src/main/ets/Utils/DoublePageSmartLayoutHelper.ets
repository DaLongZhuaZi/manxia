import { MangaPage } from 'manxia_core/src/main/ets/Models/MangaModels';

export interface PageDimensionsInfo {
  width: number;
  height: number;
}

export interface DoublePageSmartDisplayPlan {
  startIndex: number;
  endIndex: number;
  leftPageIndex: number;
  rightPageIndex: number;
  pageCount: number;
  mode: DoublePageSmartDisplayMode;
  reason: DoublePageSmartDisplayReason;
}

export enum DoublePageSmartDisplayMode {
  DUAL = 'DUAL',
  SINGLE = 'SINGLE'
}

export enum DoublePageSmartDisplayReason {
  NORMAL_PAIR = 'NORMAL_PAIR',
  LANDSCAPE_SPREAD = 'LANDSCAPE_SPREAD',
  ADJACENT_LANDSCAPE = 'ADJACENT_LANDSCAPE',
  LARGE_SINGLE_PAGE = 'LARGE_SINGLE_PAGE',
  ASPECT_MISMATCH = 'ASPECT_MISMATCH',
  TAIL_PAGE = 'TAIL_PAGE'
}

export type PageDimensionsResolver = (pageIndex: number) => PageDimensionsInfo | null;

export class DoublePageSmartLayoutHelper {
  private static readonly WIDE_PAGE_RATIO_THRESHOLD: number = 1.02;
  private static readonly NEAR_SQUARE_RATIO_THRESHOLD: number = 0.92;
  private static readonly PORTRAIT_PAGE_RATIO_THRESHOLD: number = 0.78;
  private static readonly ASPECT_MISMATCH_DELTA_THRESHOLD: number = 0.42;

  static resolvePageDimensionsFromMetadata(page: MangaPage): PageDimensionsInfo | null {
    if (!page.width || !page.height || page.width <= 0 || page.height <= 0) {
      return null;
    }
    return {
      width: page.width,
      height: page.height
    } as PageDimensionsInfo;
  }

  static resolvePlanAtIndex(
    pages: MangaPage[],
    currentIndex: number,
    isRtl: boolean,
    dimensionsResolver: PageDimensionsResolver
  ): DoublePageSmartDisplayPlan {
    if (!pages || pages.length === 0) {
      return DoublePageSmartLayoutHelper.createInvalidPlan();
    }

    const safeTarget: number = Math.max(0, Math.min(currentIndex, pages.length - 1));
    let cursor: number = 0;
    let lastPlan: DoublePageSmartDisplayPlan = DoublePageSmartLayoutHelper.createInvalidPlan();

    while (cursor < pages.length) {
      const plan: DoublePageSmartDisplayPlan = DoublePageSmartLayoutHelper.resolvePlanFromStart(pages, cursor, isRtl, dimensionsResolver);
      lastPlan = plan;
      if (safeTarget <= plan.endIndex) {
        return plan;
      }
      cursor = plan.endIndex + 1;
    }

    return lastPlan;
  }

  static resolvePreviousPlan(
    pages: MangaPage[],
    currentIndex: number,
    isRtl: boolean,
    dimensionsResolver: PageDimensionsResolver
  ): DoublePageSmartDisplayPlan {
    if (!pages || pages.length === 0) {
      return DoublePageSmartLayoutHelper.createInvalidPlan();
    }

    const currentPlan: DoublePageSmartDisplayPlan = DoublePageSmartLayoutHelper.resolvePlanAtIndex(pages, currentIndex, isRtl, dimensionsResolver);
    if (currentPlan.startIndex <= 0) {
      return DoublePageSmartLayoutHelper.createInvalidPlan();
    }

    let cursor: number = 0;
    let previousPlan: DoublePageSmartDisplayPlan = DoublePageSmartLayoutHelper.createInvalidPlan();
    while (cursor < currentPlan.startIndex) {
      const plan: DoublePageSmartDisplayPlan = DoublePageSmartLayoutHelper.resolvePlanFromStart(pages, cursor, isRtl, dimensionsResolver);
      if (plan.endIndex >= currentPlan.startIndex) {
        break;
      }
      previousPlan = plan;
      cursor = plan.endIndex + 1;
    }

    return previousPlan;
  }

  static resolveNextPlan(
    pages: MangaPage[],
    currentIndex: number,
    isRtl: boolean,
    dimensionsResolver: PageDimensionsResolver
  ): DoublePageSmartDisplayPlan {
    if (!pages || pages.length === 0) {
      return DoublePageSmartLayoutHelper.createInvalidPlan();
    }

    const currentPlan: DoublePageSmartDisplayPlan = DoublePageSmartLayoutHelper.resolvePlanAtIndex(pages, currentIndex, isRtl, dimensionsResolver);
    const nextStart: number = currentPlan.endIndex + 1;
    if (nextStart >= pages.length) {
      return DoublePageSmartLayoutHelper.createInvalidPlan();
    }

    return DoublePageSmartLayoutHelper.resolvePlanFromStart(pages, nextStart, isRtl, dimensionsResolver);
  }

  private static resolvePlanFromStart(
    pages: MangaPage[],
    startIndex: number,
    isRtl: boolean,
    dimensionsResolver: PageDimensionsResolver
  ): DoublePageSmartDisplayPlan {
    if (!pages || startIndex < 0 || startIndex >= pages.length) {
      return DoublePageSmartLayoutHelper.createInvalidPlan();
    }

    const nextIndex: number = startIndex + 1;
    if (nextIndex >= pages.length) {
      return DoublePageSmartLayoutHelper.createSinglePlan(startIndex, DoublePageSmartDisplayReason.TAIL_PAGE);
    }

    const currentDimensions: PageDimensionsInfo | null = DoublePageSmartLayoutHelper.resolveDimensionsForPage(pages[startIndex], startIndex, dimensionsResolver);
    if (DoublePageSmartLayoutHelper.isLandscapeSpread(currentDimensions)) {
      return DoublePageSmartLayoutHelper.createSinglePlan(startIndex, DoublePageSmartDisplayReason.LANDSCAPE_SPREAD);
    }
    if (DoublePageSmartLayoutHelper.isLargeSinglePage(currentDimensions)) {
      return DoublePageSmartLayoutHelper.createSinglePlan(startIndex, DoublePageSmartDisplayReason.LARGE_SINGLE_PAGE);
    }

    const nextDimensions: PageDimensionsInfo | null = DoublePageSmartLayoutHelper.resolveDimensionsForPage(pages[nextIndex], nextIndex, dimensionsResolver);
    if (DoublePageSmartLayoutHelper.isLandscapeSpread(nextDimensions)) {
      return DoublePageSmartLayoutHelper.createSinglePlan(startIndex, DoublePageSmartDisplayReason.ADJACENT_LANDSCAPE);
    }
    if (DoublePageSmartLayoutHelper.isLargeSinglePage(nextDimensions)) {
      return DoublePageSmartLayoutHelper.createSinglePlan(startIndex, DoublePageSmartDisplayReason.ADJACENT_LANDSCAPE);
    }

    if (DoublePageSmartLayoutHelper.isAspectMismatchPair(currentDimensions, nextDimensions)) {
      return DoublePageSmartLayoutHelper.createSinglePlan(startIndex, DoublePageSmartDisplayReason.ASPECT_MISMATCH);
    }

    return DoublePageSmartLayoutHelper.createDualPlan(startIndex, isRtl, pages.length);
  }

  private static resolveDimensionsForPage(
    page: MangaPage,
    pageIndex: number,
    dimensionsResolver: PageDimensionsResolver
  ): PageDimensionsInfo | null {
    const resolvedDimensions: PageDimensionsInfo | null = dimensionsResolver(pageIndex);
    if (resolvedDimensions) {
      return resolvedDimensions;
    }
    return DoublePageSmartLayoutHelper.resolvePageDimensionsFromMetadata(page);
  }

  private static isLandscapeSpread(dimensions: PageDimensionsInfo | null): boolean {
    if (!dimensions || dimensions.width <= 0 || dimensions.height <= 0) {
      return false;
    }
    return (dimensions.width / dimensions.height) >= DoublePageSmartLayoutHelper.WIDE_PAGE_RATIO_THRESHOLD;
  }

  private static isLargeSinglePage(dimensions: PageDimensionsInfo | null): boolean {
    if (!dimensions || dimensions.width <= 0 || dimensions.height <= 0) {
      return false;
    }
    return (dimensions.width / dimensions.height) >= DoublePageSmartLayoutHelper.NEAR_SQUARE_RATIO_THRESHOLD;
  }

  private static isAspectMismatchPair(
    currentDimensions: PageDimensionsInfo | null,
    nextDimensions: PageDimensionsInfo | null
  ): boolean {
    if (!currentDimensions || !nextDimensions) {
      return false;
    }

    const currentRatio: number = currentDimensions.width / Math.max(1, currentDimensions.height);
    const nextRatio: number = nextDimensions.width / Math.max(1, nextDimensions.height);
    const ratioDelta: number = Math.abs(currentRatio - nextRatio);
    const hasNearSquareOrWidePage: boolean = currentRatio >= DoublePageSmartLayoutHelper.NEAR_SQUARE_RATIO_THRESHOLD ||
      nextRatio >= DoublePageSmartLayoutHelper.NEAR_SQUARE_RATIO_THRESHOLD;
    const hasPortraitCompanion: boolean = currentRatio <= DoublePageSmartLayoutHelper.PORTRAIT_PAGE_RATIO_THRESHOLD ||
      nextRatio <= DoublePageSmartLayoutHelper.PORTRAIT_PAGE_RATIO_THRESHOLD;

    return ratioDelta >= DoublePageSmartLayoutHelper.ASPECT_MISMATCH_DELTA_THRESHOLD &&
      hasNearSquareOrWidePage &&
      hasPortraitCompanion;
  }

  private static createSinglePlan(
    startIndex: number,
    reason: DoublePageSmartDisplayReason
  ): DoublePageSmartDisplayPlan {
    return {
      startIndex: startIndex,
      endIndex: startIndex,
      leftPageIndex: startIndex,
      rightPageIndex: -1,
      pageCount: 1,
      mode: DoublePageSmartDisplayMode.SINGLE,
      reason: reason
    } as DoublePageSmartDisplayPlan;
  }

  private static createDualPlan(
    startIndex: number,
    isRtl: boolean,
    totalPages: number
  ): DoublePageSmartDisplayPlan {
    const secondIndex: number = startIndex + 1 < totalPages ? startIndex + 1 : -1;
    const leftPageIndex: number = isRtl && secondIndex >= 0 ? secondIndex : startIndex;
    const rightPageIndex: number = isRtl && secondIndex >= 0 ? startIndex : secondIndex;

    return {
      startIndex: startIndex,
      endIndex: secondIndex >= 0 ? secondIndex : startIndex,
      leftPageIndex: leftPageIndex,
      rightPageIndex: rightPageIndex,
      pageCount: secondIndex >= 0 ? 2 : 1,
      mode: secondIndex >= 0 ? DoublePageSmartDisplayMode.DUAL : DoublePageSmartDisplayMode.SINGLE,
      reason: secondIndex >= 0 ? DoublePageSmartDisplayReason.NORMAL_PAIR : DoublePageSmartDisplayReason.TAIL_PAGE
    } as DoublePageSmartDisplayPlan;
  }

  private static createInvalidPlan(): DoublePageSmartDisplayPlan {
    return {
      startIndex: -1,
      endIndex: -1,
      leftPageIndex: -1,
      rightPageIndex: -1,
      pageCount: 0,
      mode: DoublePageSmartDisplayMode.DUAL,
      reason: DoublePageSmartDisplayReason.NORMAL_PAIR
    } as DoublePageSmartDisplayPlan;
  }
}
