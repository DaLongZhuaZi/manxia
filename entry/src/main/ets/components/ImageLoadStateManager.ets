// 文件路径: entry/src/main/ets/components/ImageLoadStateManager.ets
// 职责: 管理图片加载状态，确保UI与加载状态完全同步

import image from '@ohos.multimedia.image';
import { logger } from '../Utils/Logger';

const TAG = 'ImageLoadStateManager';

/**
 * 统计信息接口
 */
export interface LoadStatsInfo {
  total: number;
  idle: number;
  loading: number;
  completed: number;
  error: number;
}

/**
 * 图片加载状态枚举
 */
export enum ImageLoadState {
  IDLE = 'idle',           // 空闲，未开始加载
  LOADING = 'loading',     // 加载中
  COMPLETED = 'completed', // 加载完成
  ERROR = 'error'          // 加载失败
}

/**
 * 页面状态信息
 */
export interface PageState {
  pageId: string;
  pageIndex: number;
  loadState: ImageLoadState;
  pixelMap: image.PixelMap | null;
  error?: string;
  loadStartTime?: number;
  loadEndTime?: number;
}

/**
 * 图片加载状态管理器
 * 统一管理所有页面的加载状态和PixelMap
 */
export class ImageLoadStateManager {
  // 页面状态映射
  private pageStates: Map<string, PageState> = new Map();
  
  // PixelMap映射（用于快速访问）
  private pixelMaps: Map<string, image.PixelMap> = new Map();
  
  // 加载状态映射（用于快速查询）
  private loadStates: Map<string, ImageLoadState> = new Map();
  
  // 状态变化回调
  private onStateChange?: (pageId: string, state: PageState) => void;

  /**
   * 设置状态变化回调
   */
  setStateChangeCallback(callback: (pageId: string, state: PageState) => void): void {
    this.onStateChange = callback;
  }

  /**
   * 初始化页面状态
   */
  initPage(pageId: string, pageIndex: number): void {
    if (!this.pageStates.has(pageId)) {
      const state: PageState = {
        pageId,
        pageIndex,
        loadState: ImageLoadState.IDLE,
        pixelMap: null
      };
      this.pageStates.set(pageId, state);
      this.loadStates.set(pageId, ImageLoadState.IDLE);
    }
  }

  /**
   * 开始加载
   */
  startLoading(pageId: string): void {
    const state = this.pageStates.get(pageId);
    if (!state) {
      logger.warn(TAG, `页面状态不存在: ${pageId}`);
      return;
    }

    state.loadState = ImageLoadState.LOADING;
    state.loadStartTime = Date.now();
    state.error = undefined;
    
    this.loadStates.set(pageId, ImageLoadState.LOADING);
    
    this.notifyStateChange(pageId, state);
  }

  /**
   * 加载完成
   */
  onLoadComplete(pageId: string, pixelMap: image.PixelMap): void {
    const state = this.pageStates.get(pageId);
    if (!state) {
      logger.warn(TAG, `页面状态不存在: ${pageId}`);
      return;
    }

    state.loadState = ImageLoadState.COMPLETED;
    state.pixelMap = pixelMap;
    state.loadEndTime = Date.now();
    state.error = undefined;
    
    this.pixelMaps.set(pageId, pixelMap);
    this.loadStates.set(pageId, ImageLoadState.COMPLETED);
    
    this.notifyStateChange(pageId, state);
  }

  /**
   * 加载失败
   */
  onLoadError(pageId: string, error: string): void {
    const state = this.pageStates.get(pageId);
    if (!state) {
      logger.warn(TAG, `页面状态不存在: ${pageId}`);
      return;
    }

    // 仅清理引用，不释放对象，避免释放共享 PixelMap 导致其他缓存引用失效
    state.pixelMap = null;

    state.loadState = ImageLoadState.ERROR;
    state.error = error;
    state.loadEndTime = Date.now();
    
    this.pixelMaps.delete(pageId);
    this.loadStates.set(pageId, ImageLoadState.ERROR);
    
    this.notifyStateChange(pageId, state);
  }

  /**
   * 获取页面状态
   */
  getPageState(pageId: string): PageState | null {
    return this.pageStates.get(pageId) || null;
  }

  /**
   * 获取加载状态
   */
  getLoadState(pageId: string): ImageLoadState {
    return this.loadStates.get(pageId) || ImageLoadState.IDLE;
  }

  /**
   * 获取PixelMap
   */
  getPixelMap(pageId: string): image.PixelMap | null {
    return this.pixelMaps.get(pageId) || null;
  }

  /**
   * 检查是否正在加载
   */
  isLoading(pageId: string): boolean {
    return this.loadStates.get(pageId) === ImageLoadState.LOADING;
  }

  /**
   * 检查是否已完成
   */
  isCompleted(pageId: string): boolean {
    return this.loadStates.get(pageId) === ImageLoadState.COMPLETED;
  }

  /**
   * 检查是否失败
   */
  isError(pageId: string): boolean {
    return this.loadStates.get(pageId) === ImageLoadState.ERROR;
  }

  /**
   * 获取当前正在加载的数量（O(1)复杂度）
   * 避免每次调用时遍历所有页面
   */
  getLoadingCount(): number {
    let count = 0;
    this.loadStates.forEach(state => {
      if (state === ImageLoadState.LOADING) {
        count++;
      }
    });
    return count;
  }

  /**
   * 清除页面状态
   */
  clearPage(pageId: string): void {
    this.pageStates.delete(pageId);
    this.pixelMaps.delete(pageId);
    this.loadStates.delete(pageId);
  }

  /**
   * 清除所有状态
   */
  clearAll(): void {
    this.pageStates.clear();
    this.pixelMaps.clear();
    this.loadStates.clear();
  }

  /**
   * 清理远离当前页的PixelMap（节省内存）
   */
  cleanupDistantPages(currentPageIndex: number, keepRange: number = 5): number {
    let cleanedCount = 0;
    const toRemove: string[] = [];

    this.pageStates.forEach((state, pageId) => {
      const distance = Math.abs(state.pageIndex - currentPageIndex);
      if (distance > keepRange && state.pixelMap) {
        toRemove.push(pageId);
      }
    });

    toRemove.forEach(pageId => {
      const state = this.pageStates.get(pageId);
      if (state && state.pixelMap) {
        cleanedCount++;
        state.pixelMap = null;
        this.pixelMaps.delete(pageId);
      }
    });

    return cleanedCount;
  }

  /**
   * 获取所有页面状态（用于调试）
   */
  getAllStates(): Map<string, PageState> {
    return new Map(this.pageStates);
  }

  /**
   * 获取统计信息
   */
  getStats(): LoadStatsInfo {
    let idle = 0;
    let loading = 0;
    let completed = 0;
    let error = 0;

    this.loadStates.forEach(state => {
      switch (state) {
        case ImageLoadState.IDLE:
          idle++;
          break;
        case ImageLoadState.LOADING:
          loading++;
          break;
        case ImageLoadState.COMPLETED:
          completed++;
          break;
        case ImageLoadState.ERROR:
          error++;
          break;
      }
    });

    const result: LoadStatsInfo = {
      total: this.pageStates.size,
      idle: idle,
      loading: loading,
      completed: completed,
      error: error
    };
    return result;
  }

  /**
   * 通知状态变化
   */
  private notifyStateChange(pageId: string, state: PageState): void {
    if (this.onStateChange) {
      this.onStateChange(pageId, state);
    }
  }
}
