// 职责: 管理漫画阅读器的条漫位置缓存与高度估算，不接触 UI 状态和加载器。

import { logger } from 'manxia_core/src/main/ets/Utils/Logger';
import { MangaPage } from '../Models/MangaModels';
import { ChapterBoundary, WebtoonDataItem } from './MangaWebtoonTypes';

const TAG = 'MangaWebtoonPositionManager';
const CHAPTER_DIVIDER_HEIGHT: number = 120;
const DEFAULT_SCREEN_WIDTH: number = 360;
const DEFAULT_PAGE_SPACING: number = 16;
const DEFAULT_FALLBACK_HEIGHT_RATIO: number = 1.66;

export class MangaWebtoonPositionContext {
  public screenWidth: number = DEFAULT_SCREEN_WIDTH;
  public pageSpacing: number = DEFAULT_PAGE_SPACING;
  public webtoonLeftMargin: number = 0;
  public webtoonRightMargin: number = 0;
  public isWebtoonMode: boolean = false;
  public zoomScale: number = 1.0;
}

export class MangaWebtoonPositionManager {
  private itemPositionCache: number[] = [];
  private positionCacheValid: boolean = false;

  public invalidatePositionCache(): void {
    this.positionCacheValid = false;
  }

  public rebuildPositionCache(items: WebtoonDataItem[], context: MangaWebtoonPositionContext): void {
    if (items.length === 0) {
      this.itemPositionCache = [];
      this.positionCacheValid = false;
      return;
    }

    const cache: number[] = [0];
    let position: number = 0;
    for (let i = 0; i < items.length; i++) {
      const item: WebtoonDataItem = items[i];
      position += this.getWebtoonItemEstimatedHeight(item, context);
      position += this.getPageSpacing(context);
      cache.push(position);
    }

    this.itemPositionCache = cache;
    this.positionCacheValid = true;
    logger.debug(TAG, `条漫位置缓存重建完成，共${cache.length}项`);
  }

  public ensurePositionCache(items: WebtoonDataItem[], context: MangaWebtoonPositionContext): void {
    if (!this.positionCacheValid || this.itemPositionCache.length !== items.length + 1) {
      this.rebuildPositionCache(items, context);
    }
  }

  public calculateItemScrollPosition(
    itemIndex: number,
    items: WebtoonDataItem[],
    context: MangaWebtoonPositionContext
  ): number {
    if (itemIndex <= 0) {
      return 0;
    }

    if (this.positionCacheValid && itemIndex < this.itemPositionCache.length) {
      return this.itemPositionCache[itemIndex];
    }

    const limit: number = Math.min(itemIndex, items.length);
    let position: number = 0;
    for (let i = 0; i < limit; i++) {
      const item: WebtoonDataItem = items[i];
      position += this.getWebtoonItemEstimatedHeight(item, context);
      position += this.getPageSpacing(context);
    }
    return position;
  }

  public getWebtoonItemEstimatedHeight(item: WebtoonDataItem, context: MangaWebtoonPositionContext): number {
    if (item.type === 'page' && item.page) {
      return this.getEstimatedImageHeight(item.page, context);
    }
    if (item.type === 'chapter_divider') {
      return CHAPTER_DIVIDER_HEIGHT;
    }
    return 0;
  }

  public findFirstVisibleCandidate(
    rangeStart: number,
    items: WebtoonDataItem[],
    context: MangaWebtoonPositionContext
  ): number {
    if (items.length === 0) {
      return -1;
    }
    this.ensurePositionCache(items, context);

    let low: number = 0;
    let high: number = items.length - 1;
    let result: number = -1;

    while (low <= high) {
      const mid: number = Math.floor((low + high) / 2);
      const itemEnd: number = (mid + 1 < this.itemPositionCache.length)
        ? this.itemPositionCache[mid + 1]
        : this.calculateItemScrollPosition(mid, items, context) + this.getWebtoonItemEstimatedHeight(items[mid], context);
      if (itemEnd >= rangeStart) {
        result = mid;
        high = mid - 1;
      } else {
        low = mid + 1;
      }
    }

    return result >= 0 ? result : Math.max(0, items.length - 1);
  }

  public getEstimatedImageHeight(page: MangaPage, context: MangaWebtoonPositionContext): number {
    const width: number = context.isWebtoonMode
      ? this.getWebtoonContentWidth(context)
      : this.getScreenWidth(context);
    if (page.height && page.width) {
      return (page.height / page.width) * width;
    }
    return Math.floor(width * DEFAULT_FALLBACK_HEIGHT_RATIO);
  }

  public calculatePageScrollPosition(
    pageIndex: number,
    pages: MangaPage[],
    currentScrollPosition: number,
    context: MangaWebtoonPositionContext
  ): number {
    if (pageIndex < 0 || pageIndex >= pages.length) {
      return currentScrollPosition;
    }

    let scrollPosition: number = 0;
    for (let i = 0; i < pageIndex; i++) {
      const page: MangaPage = pages[i];
      scrollPosition += this.getEstimatedImageHeight(page, context) + this.getPageSpacing(context);
    }

    if (context.zoomScale > 1.0) {
      return scrollPosition * context.zoomScale;
    }
    return scrollPosition;
  }

  public calculateMaxScrollPosition(
    pages: MangaPage[],
    containerHeight: number,
    context: MangaWebtoonPositionContext
  ): number {
    const totalHeight: number = this.calculatePageListHeight(pages, context);
    const scaledTotalHeight: number = context.zoomScale > 1.0 ? totalHeight * context.zoomScale : totalHeight;
    return Math.max(0, scaledTotalHeight - containerHeight);
  }

  public calculateTotalWebtoonHeight(
    items: WebtoonDataItem[],
    fallbackPages: MangaPage[],
    context: MangaWebtoonPositionContext
  ): number {
    if (items.length > 0) {
      return this.calculateWebtoonItemListHeight(items, context);
    }
    return this.calculatePageListHeight(fallbackPages, context);
  }

  public calculatePrependedHeight(
    items: WebtoonDataItem[],
    endExclusive: number,
    context: MangaWebtoonPositionContext
  ): number {
    const limit: number = Math.min(Math.max(0, endExclusive), items.length);
    let height: number = 0;
    for (let i = 0; i < limit; i++) {
      const item: WebtoonDataItem = items[i];
      height += this.getWebtoonItemEstimatedHeight(item, context);
      if (i < limit - 1) {
        height += this.getPageSpacing(context);
      }
    }
    if (limit > 0) {
      height += this.getPageSpacing(context);
    }
    return height;
  }

  public calculateCurrentPageInChapter(
    boundary: ChapterBoundary,
    items: WebtoonDataItem[],
    scrollY: number,
    containerHeight: number,
    context: MangaWebtoonPositionContext
  ): number {
    const viewCenter: number = scrollY + containerHeight / 2;
    let currentTop: number = this.calculateItemScrollPosition(boundary.startIndex, items, context);
    let pageIndex: number = 0;

    for (let i = boundary.startIndex; i <= boundary.endIndex && i < items.length; i++) {
      const item: WebtoonDataItem = items[i];
      if (item.type === 'page' && item.page) {
        const pageHeight: number = this.getEstimatedImageHeight(item.page, context);
        const pageBottom: number = currentTop + pageHeight;
        if (viewCenter >= currentTop && viewCenter < pageBottom) {
          return pageIndex;
        }
        currentTop = pageBottom + this.getPageSpacing(context);
        pageIndex++;
      } else if (item.type === 'chapter_divider') {
        currentTop += CHAPTER_DIVIDER_HEIGHT + this.getPageSpacing(context);
      }
    }

    return Math.max(0, pageIndex - 1);
  }

  private calculateWebtoonItemListHeight(items: WebtoonDataItem[], context: MangaWebtoonPositionContext): number {
    let totalHeight: number = 0;
    for (let i = 0; i < items.length; i++) {
      totalHeight += this.getWebtoonItemEstimatedHeight(items[i], context);
      if (i < items.length - 1) {
        totalHeight += this.getPageSpacing(context);
      }
    }
    return totalHeight;
  }

  private calculatePageListHeight(pages: MangaPage[], context: MangaWebtoonPositionContext): number {
    let totalHeight: number = 0;
    for (let i = 0; i < pages.length; i++) {
      totalHeight += this.getEstimatedImageHeight(pages[i], context);
      if (i < pages.length - 1) {
        totalHeight += this.getPageSpacing(context);
      }
    }
    return totalHeight;
  }

  private getWebtoonContentWidth(context: MangaWebtoonPositionContext): number {
    const screenWidth: number = this.getScreenWidth(context);
    if (context.webtoonLeftMargin > 0 || context.webtoonRightMargin > 0) {
      return screenWidth * (1 - context.webtoonLeftMargin / 100 - context.webtoonRightMargin / 100);
    }
    return screenWidth;
  }

  private getScreenWidth(context: MangaWebtoonPositionContext): number {
    return context.screenWidth > 0 ? context.screenWidth : DEFAULT_SCREEN_WIDTH;
  }

  private getPageSpacing(context: MangaWebtoonPositionContext): number {
    return context.pageSpacing > 0 ? context.pageSpacing : DEFAULT_PAGE_SPACING;
  }
}
