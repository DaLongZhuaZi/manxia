// 职责: 统一提交 MangaViewer 的图片加载状态，不负责加载和 UI 渲染刷新

import { image } from '@kit.ImageKit';
import { ImageLoadStateManager } from './ImageLoadStateManager';
import { PreloadManager } from './PreloadManager';

export interface MangaViewerImageDimensions {
  width: number;
  height: number;
}

export interface ImageLoadState {
  isLoading: boolean;
  isLoaded: boolean;
  error?: string;
  dimensions?: MangaViewerImageDimensions;
}

export class MangaLoadStateCommitter {
  public markLoading(
    pageId: string,
    pageIndex: number,
    imageLoadStates: Map<string, ImageLoadState>,
    imageLoadStateManager: ImageLoadStateManager,
    preloadManager: PreloadManager
  ): Map<string, ImageLoadState> {
    imageLoadStateManager.initPage(pageId, pageIndex);
    const previousState: ImageLoadState | undefined = imageLoadStates.get(pageId);
    imageLoadStates.set(pageId, {
      isLoading: true,
      isLoaded: false,
      dimensions: previousState && previousState.dimensions ? previousState.dimensions : undefined,
      error: undefined
    } as ImageLoadState);
    preloadManager.startLoad(pageIndex);
    imageLoadStateManager.startLoading(pageId);
    return new Map(imageLoadStates);
  }

  public markLoaded(
    pageId: string,
    pixelMap: image.PixelMap,
    imageLoadStates: Map<string, ImageLoadState>,
    imageLoadStateManager: ImageLoadStateManager
  ): Map<string, ImageLoadState> {
    imageLoadStateManager.onLoadComplete(pageId, pixelMap);
    const previousState: ImageLoadState | undefined = imageLoadStates.get(pageId);
    imageLoadStates.set(pageId, {
      isLoading: false,
      isLoaded: true,
      dimensions: previousState && previousState.dimensions ? previousState.dimensions : undefined,
      error: undefined
    } as ImageLoadState);
    return new Map(imageLoadStates);
  }

  public markMemCacheHit(
    pageId: string,
    pageIndex: number,
    pixelMap: image.PixelMap,
    imageLoadStates: Map<string, ImageLoadState>,
    imageLoadStateManager: ImageLoadStateManager,
    preloadManager: PreloadManager
  ): Map<string, ImageLoadState> {
    preloadManager.markMemCacheHit(pageIndex);
    return this.markLoaded(pageId, pixelMap, imageLoadStates, imageLoadStateManager);
  }

  public markPreloadLoaded(
    pageId: string,
    pageIndex: number,
    pixelMap: image.PixelMap,
    imageLoadStates: Map<string, ImageLoadState>,
    imageLoadStateManager: ImageLoadStateManager,
    preloadManager: PreloadManager
  ): Map<string, ImageLoadState> {
    preloadManager.onLoadComplete(pageIndex, true);
    return this.markLoaded(pageId, pixelMap, imageLoadStates, imageLoadStateManager);
  }

  public markFailed(
    pageId: string,
    pageIndex: number,
    errorMessage: string,
    imageLoadStates: Map<string, ImageLoadState>,
    imageLoadStateManager: ImageLoadStateManager,
    preloadManager: PreloadManager
  ): Map<string, ImageLoadState> {
    imageLoadStateManager.initPage(pageId, pageIndex);
    imageLoadStateManager.onLoadError(pageId, errorMessage);
    preloadManager.onLoadComplete(pageIndex, false, errorMessage);
    const previousState: ImageLoadState | undefined = imageLoadStates.get(pageId);
    imageLoadStates.set(pageId, {
      isLoading: false,
      isLoaded: false,
      dimensions: previousState && previousState.dimensions ? previousState.dimensions : undefined,
      error: errorMessage
    } as ImageLoadState);
    return new Map(imageLoadStates);
  }

  public markDelegated(
    pageId: string,
    pageIndex: number,
    imageLoadStates: Map<string, ImageLoadState>,
    preloadManager: PreloadManager
  ): Map<string, ImageLoadState> {
    const previousState: ImageLoadState | undefined = imageLoadStates.get(pageId);
    imageLoadStates.set(pageId, {
      isLoading: false,
      isLoaded: previousState ? previousState.isLoaded : false,
      dimensions: previousState && previousState.dimensions ? previousState.dimensions : undefined,
      error: undefined
    } as ImageLoadState);
    preloadManager.onLoadComplete(pageIndex, true);
    return new Map(imageLoadStates);
  }
}
