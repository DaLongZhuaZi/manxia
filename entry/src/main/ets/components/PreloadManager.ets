// 文件路径: entry/src/main/ets/components/PreloadManager.ets
// 职责: 统一管理漫画阅读器的图片预加载逻辑

import { logger } from 'manxia_core/src/main/ets/Utils/Logger';
import { PreloadItemInfo, PreloadItemStatus, PreloadDebugInfo } from './PreloadDebugOverlay';
import { MangaPage } from 'manxia_core/src/main/ets/Models/MangaModels';

const TAG = 'PreloadManager';

/**
 * 批量添加任务项接口
 */
export interface PreloadTaskItem {
  pageIndex: number;
  pageId: string;
  url: string;
  priority: number;
}

/**
 * 预加载项内部数据
 */
interface PreloadItem {
  pageIndex: number;
  pageId: string;
  url: string;
  priority: number;
  status: PreloadItemStatus;
  startTime?: number;
  endTime?: number;
  error?: string;
  retryCount: number;
}

/**
 * 预加载统计数据
 */
interface PreloadStats {
  memCacheHits: number;
  diskCacheHits: number;
  networkLoads: number;
  totalLoads: number;
  successLoads: number;
  failedLoads: number;
}

/**
 * 条漫预加载结果
 */
export interface WebtoonPreloadResult {
  tasks: PreloadTaskItem[];
  cleanup: number[];
}

/**
 * 预加载配置参数
 */
export interface PreloadConfig {
  maxConcurrentOnline: number;    // 在线漫画最大并发加载数
  maxConcurrentLocal: number;     // 本地漫画最大并发加载数
  webtoonVisibleBuffer: number;   // 条漫模式可见区域缓冲（屏幕高度倍数）
  webtoonPreloadRange: number;    // 条漫模式预加载范围（页数）
  normalPreloadRange: number;     // 普通模式预加载范围（页数）
}

/**
 * 预加载管理器
 * 负责管理图片预加载队列、优先级、统计等
 */
export class PreloadManager {
  // 预加载队列
  private queue: Map<number, PreloadItem> = new Map();
  
  // 正在加载的页面索引集合
  private loading: Set<number> = new Set();
  
  // 已完成的页面索引集合
  private completed: Set<number> = new Set();
  
  // 失败的页面索引集合
  private failed: Set<number> = new Set();
  
  // 页面状态映射（记录每个页面的具体加载状态）
  private pageStatusMap: Map<number, PreloadItemStatus> = new Map();
  
  // 统计数据
  private stats: PreloadStats = {
    memCacheHits: 0,
    diskCacheHits: 0,
    networkLoads: 0,
    totalLoads: 0,
    successLoads: 0,
    failedLoads: 0
  };
  
  // 当前页码
  private currentPage: number = 0;
  
  // 总页数
  private totalPages: number = 0;
  
  // 预加载范围
  private preloadRange: number = 2;
  
  // 最大队列长度
  private readonly MAX_QUEUE_SIZE: number = 20;
  
  // 最大重试次数
  private readonly MAX_RETRY_COUNT: number = 2;
  
  // 调试信息更新回调
  private onDebugInfoUpdate?: (info: PreloadDebugInfo) => void;
  
  // 预加载配置
  private config: PreloadConfig = {
    maxConcurrentOnline: 3,
    maxConcurrentLocal: 5,
    webtoonVisibleBuffer: 1.5,
    webtoonPreloadRange: 8,
    normalPreloadRange: 3
  };
  
  // 可见页面索引（用于条漫模式）
  private visiblePages: Set<number> = new Set();

  /**
   * 设置调试信息更新回调
   */
  setDebugInfoUpdateCallback(callback: (info: PreloadDebugInfo) => void): void {
    this.onDebugInfoUpdate = callback;
  }

  /**
   * 更新预加载配置
   */
  updateConfig(config: Partial<PreloadConfig>): void {
    this.config = {
      maxConcurrentOnline: config.maxConcurrentOnline ?? this.config.maxConcurrentOnline,
      maxConcurrentLocal: config.maxConcurrentLocal ?? this.config.maxConcurrentLocal,
      webtoonVisibleBuffer: config.webtoonVisibleBuffer ?? this.config.webtoonVisibleBuffer,
      webtoonPreloadRange: config.webtoonPreloadRange ?? this.config.webtoonPreloadRange,
      normalPreloadRange: config.normalPreloadRange ?? this.config.normalPreloadRange
    };
    logger.info(TAG, `预加载配置已更新: ${JSON.stringify(this.config)}`);
  }

  /**
   * 获取当前配置
   */
  getConfig(): PreloadConfig {
    return {
      maxConcurrentOnline: this.config.maxConcurrentOnline,
      maxConcurrentLocal: this.config.maxConcurrentLocal,
      webtoonVisibleBuffer: this.config.webtoonVisibleBuffer,
      webtoonPreloadRange: this.config.webtoonPreloadRange,
      normalPreloadRange: this.config.normalPreloadRange
    };
  }

  /**
   * 更新可见页面（条漫模式使用）
   */
  updateVisiblePages(visibleIndices: number[]): void {
    this.visiblePages = new Set(visibleIndices);
  }

  /**
   * 获取最大并发数
   */
  getMaxConcurrent(isOnline: boolean): number {
    return isOnline ? this.config.maxConcurrentOnline : this.config.maxConcurrentLocal;
  }

  /**
   * 设置当前页码和总页数
   */
  setPageInfo(currentPage: number, totalPages: number): void {
    this.currentPage = currentPage;
    this.totalPages = totalPages;
    this.updateDebugInfo();
  }

  /**
   * 设置预加载范围
   */
  setPreloadRange(range: number): void {
    this.preloadRange = range;
    this.updateDebugInfo();
  }

  /**
   * 添加到预加载队列
   */
  addToQueue(pageIndex: number, pageId: string, url: string, priority: number = 1): void {
    // 检查是否已经完成或正在加载
    if (this.completed.has(pageIndex) || this.loading.has(pageIndex)) {
      return;
    }

    // 检查是否已在队列中
    if (this.queue.has(pageIndex)) {
      // 更新优先级（取较高值）
      const existing = this.queue.get(pageIndex)!;
      if (priority > existing.priority) {
        existing.priority = priority;
      }
      return;
    }

    // 添加新项
    const item: PreloadItem = {
      pageIndex,
      pageId,
      url,
      priority,
      status: PreloadItemStatus.PENDING,
      retryCount: 0
    };

    this.queue.set(pageIndex, item);

    // 限制队列长度
    this.trimQueue();
    
    this.updateDebugInfo();
  }

  /**
   * 批量添加预加载任务
   */
  addBatch(items: PreloadTaskItem[]): void {
    for (let i = 0; i < items.length; i++) {
      const item = items[i];
      this.addToQueue(item.pageIndex, item.pageId, item.url, item.priority);
    }
  }

  /**
   * 开始加载某个页面
   */
  startLoad(pageIndex: number): void {
    const item = this.queue.get(pageIndex);
    
    // 【修复】即使队列中没有，也要标记为loading状态
    this.loading.add(pageIndex);
    this.pageStatusMap.set(pageIndex, PreloadItemStatus.LOADING);
    
    if (item) {
      item.status = PreloadItemStatus.LOADING;
      item.startTime = Date.now();
      this.queue.delete(pageIndex); // 从队列移除
    }
    
    this.stats.totalLoads++;
    
    this.updateDebugInfo();
  }

  /**
   * 加载完成
   */
  onLoadComplete(pageIndex: number, success: boolean, error?: string): void {
    this.loading.delete(pageIndex);
    
    if (success) {
      this.completed.add(pageIndex);
      this.stats.successLoads++;
      // 如果没有设置具体状态，默认为网络加载完成
      if (!this.pageStatusMap.has(pageIndex)) {
        this.pageStatusMap.set(pageIndex, PreloadItemStatus.COMPLETED);
      }
    } else {
      this.failed.add(pageIndex);
      this.pageStatusMap.set(pageIndex, PreloadItemStatus.FAILED);
      this.stats.failedLoads++;
      
      // 注意：重试逻辑由外部控制，这里只记录失败
    }

    this.updateDebugInfo();
  }

  /**
   * 标记内存缓存命中
   */
  markMemCacheHit(pageIndex: number): void {
    // 【修复】从loading中移除
    this.loading.delete(pageIndex);
    this.completed.add(pageIndex);
    this.pageStatusMap.set(pageIndex, PreloadItemStatus.MEM_CACHE_HIT);
    this.stats.memCacheHits++;
    this.updateDebugInfo();
  }

  /**
   * 标记磁盘缓存命中
   */
  markDiskCacheHit(pageIndex: number): void {
    // 【修复】从loading中移除
    this.loading.delete(pageIndex);
    this.completed.add(pageIndex);
    this.pageStatusMap.set(pageIndex, PreloadItemStatus.DISK_CACHE_HIT);
    this.stats.diskCacheHits++;
    this.updateDebugInfo();
  }

  /**
   * 标记网络加载
   */
  markNetworkLoad(pageIndex: number): void {
    // 【修复】从loading中移除，添加到completed
    this.loading.delete(pageIndex);
    this.completed.add(pageIndex);
    this.pageStatusMap.set(pageIndex, PreloadItemStatus.COMPLETED);
    this.stats.networkLoads++;
    this.updateDebugInfo();
  }

  /**
   * 从队列中移除指定页面
   */
  private removeFromQueue(pageIndex: number): void {
    this.queue.delete(pageIndex);
  }

  /**
   * 清除指定页面的状态
   */
  clearPage(pageIndex: number): void {
    this.removeFromQueue(pageIndex);
    this.loading.delete(pageIndex);
    this.completed.delete(pageIndex);
    this.failed.delete(pageIndex);
    this.pageStatusMap.delete(pageIndex);
    this.updateDebugInfo();
  }

  /**
   * 清除所有状态
   */
  clearAll(): void {
    this.queue = new Map();
    this.loading.clear();
    this.completed.clear();
    this.failed.clear();
    this.pageStatusMap.clear();
    this.updateDebugInfo();
  }

  /**
   * 检查页面是否已完成加载
   */
  isCompleted(pageIndex: number): boolean {
    return this.completed.has(pageIndex);
  }

  /**
   * 检查页面是否正在加载
   */
  isLoading(pageIndex: number): boolean {
    return this.loading.has(pageIndex);
  }

  /**
   * 检查页面是否加载失败
   */
  isFailed(pageIndex: number): boolean {
    return this.failed.has(pageIndex);
  }

  /**
   * 获取下一个应该加载的页面（按优先级）
   */
  getNextToLoad(): PreloadItem | null {
    if (this.queue.size === 0) {
      return null;
    }

    // 按优先级排序（优先级高的在前，相同优先级按页码接近当前页排序）
    const sorted = Array.from(this.queue.values()).sort((a, b) => {
      if (a.priority !== b.priority) {
        return b.priority - a.priority; // 优先级降序
      }
      // 优先级相同，按距离当前页的距离排序
      const distA = Math.abs(a.pageIndex - this.currentPage);
      const distB = Math.abs(b.pageIndex - this.currentPage);
      return distA - distB;
    });

    return sorted[0] || null;
  }

  /**
   * 条漫模式：构建预加载任务列表
   * @param visibleIndices 当前可见的页面索引列表
   * @param pages 所有页面数据
   * @param range 预加载范围（可见页面前后各加载多少页）
   * @returns 预加载任务列表
   */
  buildWebtoonPreloadTasks(visibleIndices: number[], pages: MangaPage[], range: number = 8): PreloadTaskItem[] {
    const tasks: PreloadTaskItem[] = [];
    const preloadIndices = new Set<number>();
    
    this.updateVisiblePages(visibleIndices);

    // 为每个可见页面添加前后范围内的页面
    for (let i = 0; i < visibleIndices.length; i++) {
      const visibleIndex = visibleIndices[i];
      const startIdx = Math.max(0, visibleIndex - range);
      const endIdx = Math.min(pages.length - 1, visibleIndex + range);
      
      for (let j = startIdx; j <= endIdx; j++) {
        preloadIndices.add(j);
      }
    }

    // 生成任务，优先级基于距离可见区域的距离
    preloadIndices.forEach(pageIndex => {
      const page = pages[pageIndex];
      if (!page || !page.imageUrl) return;

      // 计算优先级：可见页面最高，距离越近优先级越高
      let priority = 1;
      if (this.visiblePages.has(pageIndex)) {
        priority = 10; // 可见页面最高优先级
      } else {
        // 计算到最近可见页面的距离
        let minDist = Infinity;
        visibleIndices.forEach(visibleIdx => {
          const dist = Math.abs(pageIndex - visibleIdx);
          if (dist < minDist) {
            minDist = dist;
          }
        });
        priority = Math.max(1, 10 - minDist);
      }

      tasks.push({
        pageIndex,
        pageId: page.id,
        url: page.imageUrl,
        priority
      });
    });

    return tasks;
  }

  /**
   * 获取需要继续加载的任务数量
   * @param isOnline 是否为在线漫画
   * @param currentLoadingCount 当前正在加载的数量
   * @returns 还可以加载的数量
   */
  getAvailableLoadSlots(isOnline: boolean, currentLoadingCount: number): number {
    const maxConcurrent = this.getMaxConcurrent(isOnline);
    return Math.max(0, maxConcurrent - currentLoadingCount);
  }

  /**
   * 批量获取下一批要加载的任务
   * @param count 需要获取的任务数量
   * @returns 任务列表
   */
  getNextBatchToLoad(count: number): PreloadTaskItem[] {
    if (this.queue.size === 0 || count <= 0) {
      return [];
    }

    // 按优先级排序
    const sorted: PreloadItem[] = Array.from(this.queue.values()).sort((a: PreloadItem, b: PreloadItem): number => {
      if (a.priority !== b.priority) {
        return b.priority - a.priority;
      }
      const distA: number = Math.abs(a.pageIndex - this.currentPage);
      const distB: number = Math.abs(b.pageIndex - this.currentPage);
      return distA - distB;
    });

    const tasks: PreloadTaskItem[] = [];
    const limit: number = Math.min(count, sorted.length);
    for (let i = 0; i < limit; i++) {
      const item: PreloadItem = sorted[i];
      const task: PreloadTaskItem = {
        pageIndex: item.pageIndex,
        pageId: item.pageId,
        url: item.url,
        priority: item.priority
      } as PreloadTaskItem;
      tasks.push(task);
    }
    return tasks;
  }

  /**
   * 获取队列中的所有项（用于显示）
   */
  getQueueItems(): PreloadItemInfo[] {
    const items: PreloadItemInfo[] = [];

    // 队列中的项
    this.queue.forEach(item => {
      items.push({
        pageIndex: item.pageIndex,
        pageId: item.pageId,
        status: item.status,
        url: item.url,
        startTime: item.startTime,
        endTime: item.endTime,
        error: item.error
      });
    });

    // 正在加载的项
    this.loading.forEach(pageIndex => {
      // 【修复】检查是否已在队列中，避免重复
      const queueArray = Array.from(this.queue.values());
      const existsInQueue = queueArray.some((item: PreloadItem) => item.pageIndex === pageIndex);
      
      if (!existsInQueue) {
        const status = this.pageStatusMap.get(pageIndex) || PreloadItemStatus.LOADING;
        items.push({
          pageIndex,
          pageId: `loading_${pageIndex}`,
          status: status,
          startTime: Date.now()
        });
      }
    });
    
    // 已完成的项（从pageStatusMap获取详细状态）
    this.completed.forEach(pageIndex => {
      // 如果不在队列和加载中，添加到列表
      const queueArray = Array.from(this.queue.values());
      const existsInQueue = queueArray.some((item: PreloadItem) => item.pageIndex === pageIndex);
      const isLoading = this.loading.has(pageIndex);
      
      if (!existsInQueue && !isLoading) {
        const status = this.pageStatusMap.get(pageIndex) || PreloadItemStatus.COMPLETED;
        items.push({
          pageIndex,
          pageId: `completed_${pageIndex}`,
          status: status
        });
      }
    });
    
    // 失败的项
    this.failed.forEach(pageIndex => {
      const queueArray = Array.from(this.queue.values());
      const existsInQueue = queueArray.some((item: PreloadItem) => item.pageIndex === pageIndex);
      const isLoading = this.loading.has(pageIndex);
      
      if (!existsInQueue && !isLoading) {
        items.push({
          pageIndex,
          pageId: `failed_${pageIndex}`,
          status: PreloadItemStatus.FAILED
        });
      }
    });

    // 按页码排序
    items.sort((a, b) => a.pageIndex - b.pageIndex);

    return items;
  }

  /**
   * 获取调试信息
   */
  getDebugInfo(): PreloadDebugInfo {
    return {
      currentPage: this.currentPage,
      totalPages: this.totalPages,
      preloadRange: this.preloadRange,
      queueItems: this.getQueueItems(),
      completedCount: this.completed.size,
      failedCount: this.failed.size,
      memCacheHits: this.stats.memCacheHits,
      diskCacheHits: this.stats.diskCacheHits,
      networkLoads: this.stats.networkLoads
    };
  }

  /**
   * 获取统计信息
   */
  getStats(): PreloadStats {
    return {
      memCacheHits: this.stats.memCacheHits,
      diskCacheHits: this.stats.diskCacheHits,
      networkLoads: this.stats.networkLoads,
      totalLoads: this.stats.totalLoads,
      successLoads: this.stats.successLoads,
      failedLoads: this.stats.failedLoads
    };
  }

  /**
   * 重置统计信息
   */
  resetStats(): void {
    this.stats = {
      memCacheHits: 0,
      diskCacheHits: 0,
      networkLoads: 0,
      totalLoads: 0,
      successLoads: 0,
      failedLoads: 0
    };
    this.updateDebugInfo();
  }

  /**
   * 修剪队列，保持在最大长度内
   */
  private trimQueue(): void {
    if (this.queue.size <= this.MAX_QUEUE_SIZE) {
      return;
    }

    // 移除优先级最低且距离当前页最远的项
    const entries: Array<[number, PreloadItem]> = [];
    this.queue.forEach((item, index) => {
      entries.push([index, item]);
    });
    
    entries.sort((a, b) => {
      const indexA = a[0];
      const itemA = a[1];
      const indexB = b[0];
      const itemB = b[1];
      
      if (itemA.priority !== itemB.priority) {
        return itemA.priority - itemB.priority; // 优先级升序
      }
      
      const distA = Math.abs(indexA - this.currentPage);
      const distB = Math.abs(indexB - this.currentPage);
      return distB - distA; // 距离降序
    });

    // 移除多余的项
    const removeCount = this.queue.size - this.MAX_QUEUE_SIZE;
    for (let i = 0; i < removeCount; i++) {
      const entry = entries[i];
      this.queue.delete(entry[0]);
    }
  }

  /**
   * 更新调试信息
   */
  private updateDebugInfo(): void {
    if (this.onDebugInfoUpdate) {
      this.onDebugInfoUpdate(this.getDebugInfo());
    }
  }

  /**
   * 清理远离当前页的已完成项（节省内存）
   */
  cleanupDistantCompleted(keepRange: number = 10): void {
    const toRemove: number[] = [];
    
    this.completed.forEach(pageIndex => {
      if (Math.abs(pageIndex - this.currentPage) > keepRange) {
        toRemove.push(pageIndex);
      }
    });

    toRemove.forEach(index => {
      this.completed.delete(index);
    });

    // 同样清理失败记录
    const failedToRemove: number[] = [];
    this.failed.forEach(pageIndex => {
      if (Math.abs(pageIndex - this.currentPage) > keepRange) {
        failedToRemove.push(pageIndex);
      }
    });

    failedToRemove.forEach(index => {
      this.failed.delete(index);
    });

    if (toRemove.length > 0 || failedToRemove.length > 0) {
      this.updateDebugInfo();
    }
  }

  /**
   * 条漫模式：清理远离可见区域的已完成项
   */
  cleanupDistantCompletedForWebtoon(): void {
    if (this.visiblePages.size === 0) {
      return;
    }

    const keepRange = this.config.webtoonPreloadRange + 5;
    const toRemove: number[] = [];

    this.completed.forEach(pageIndex => {
      // 检查是否在任何可见页面的范围内
      let isInRange = false;
      this.visiblePages.forEach(visibleIdx => {
        if (Math.abs(pageIndex - visibleIdx) <= keepRange) {
          isInRange = true;
        }
      });

      if (!isInRange) {
        toRemove.push(pageIndex);
      }
    });

    toRemove.forEach(index => {
      this.completed.delete(index);
      this.pageStatusMap.delete(index);
    });

    if (toRemove.length > 0) {
      logger.debug(TAG, `条漫模式清理了 ${toRemove.length} 个远离可见区域的已完成项`);
      this.updateDebugInfo();
    }
  }
}
