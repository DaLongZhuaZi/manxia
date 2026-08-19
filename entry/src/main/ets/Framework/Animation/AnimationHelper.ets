// 文件路径: entry/src/main/ets/Framework/Animation/AnimationHelper.ets
// 职责: 动画集成辅助工具，简化在现有页面中添加动画的过程

import { logger } from 'manxia_core/src/main/ets/Utils/Logger';
import { ItemPosition, AnimationType } from './ItemTransitionAnimator';
import { AnimatedItem, GridLayoutConfig } from './AnimatedGridState';
import { Manga } from '../../Models/MangaModels';
import { EBook } from '../../Models/EBookModels';
import { NovelBook } from '../../Models/NovelModels';

const TAG = 'AnimationHelper';

/**
 * 将Manga转换为AnimatedItem
 */
export function mangaToAnimatedItem(manga: Manga): AnimatedItem {
  return {
    id: manga.id
  } as AnimatedItem;
}

/**
 * 将EBook转换为AnimatedItem
 */
export function ebookToAnimatedItem(ebook: EBook): AnimatedItem {
  return {
    id: ebook.id
  } as AnimatedItem;
}

/**
 * 将NovelBook转换为AnimatedItem
 */
export function novelToAnimatedItem(novel: NovelBook): AnimatedItem {
  return {
    id: novel.bookUrl
  } as AnimatedItem;
}

/**
 * 批量转换Manga列表
 */
export function mangaListToAnimatedItems(mangaList: Manga[]): AnimatedItem[] {
  return mangaList.map(manga => mangaToAnimatedItem(manga));
}

/**
 * 批量转换EBook列表
 */
export function ebookListToAnimatedItems(ebookList: EBook[]): AnimatedItem[] {
  return ebookList.map(ebook => ebookToAnimatedItem(ebook));
}

/**
 * 批量转换NovelBook列表
 */
export function novelListToAnimatedItems(novelList: NovelBook[]): AnimatedItem[] {
  return novelList.map(novel => novelToAnimatedItem(novel));
}

/**
 * 根据屏幕宽度计算推荐的列数
 */
export function calculateRecommendedColumns(screenWidth: number): number {
  if (screenWidth >= 1200) return 6;
  if (screenWidth >= 900) return 5;
  if (screenWidth >= 600) return 4;
  if (screenWidth >= 400) return 3;
  return 2;
}

/**
 * 根据列数和间距计算条目宽度
 */
export function calculateItemWidth(
  containerWidth: number,
  columns: number,
  columnGap: number,
  paddingLeft: number = 16,
  paddingRight: number = 16
): number {
  const availableWidth = containerWidth - paddingLeft - paddingRight - (columns - 1) * columnGap;
  return Math.floor(availableWidth / columns);
}

/**
 * 根据宽度和纵横比计算条目高度
 */
export function calculateItemHeight(itemWidth: number, aspectRatio: number = 0.7): number {
  return Math.floor(itemWidth / aspectRatio);
}

/**
 * 创建标准的网格布局配置
 */
export function createStandardGridConfig(
  containerWidth: number,
  columns?: number,
  aspectRatio: number = 0.7
): GridLayoutConfig {
  const actualColumns = columns || calculateRecommendedColumns(containerWidth);
  const columnGap = 12;
  const rowGap = 12;
  const paddingLeft = 16;
  const paddingTop = 16;
  
  const itemWidth = calculateItemWidth(containerWidth, actualColumns, columnGap, paddingLeft, paddingLeft);
  const itemHeight = calculateItemHeight(itemWidth, aspectRatio);
  
  return {
    columns: actualColumns,
    itemWidth: itemWidth,
    itemHeight: itemHeight,
    columnGap: columnGap,
    rowGap: rowGap,
    paddingLeft: paddingLeft,
    paddingTop: paddingTop
  };
}

/**
 * 生成Grid的columnsTemplate字符串
 */
export function generateColumnsTemplate(columns: number): string {
  return '1fr '.repeat(columns).trim();
}

/**
 * 检测两个列表之间的变化类型
 */
export function detectChangeType<T extends AnimatedItem>(
  oldList: T[],
  newList: T[]
): AnimationType {
  if (oldList.length === 0) {
    return AnimationType.REFRESH;
  }
  
  const oldIds = new Set(oldList.map(item => item.id));
  const newIds = new Set(newList.map(item => item.id));
  
  let addedCount = 0;
  let removedCount = 0;
  
  newIds.forEach(id => {
    if (!oldIds.has(id)) addedCount++;
  });
  
  oldIds.forEach(id => {
    if (!newIds.has(id)) removedCount++;
  });
  
  if (addedCount > 0 && removedCount > 0) {
    return AnimationType.REFRESH;
  }
  
  if (addedCount > 0) {
    return AnimationType.ADD;
  }
  
  if (removedCount > 0) {
    return AnimationType.REMOVE;
  }
  
  // 检查顺序是否变化
  if (oldList.length === newList.length) {
    for (let i = 0; i < oldList.length; i++) {
      if (oldList[i].id !== newList[i].id) {
        return AnimationType.MOVE;
      }
    }
  }
  
  return AnimationType.REFRESH;
}

/**
 * 为条目列表生成组件ID列表
 */
export function generateItemComponentIds(items: AnimatedItem[], prefix: string = 'item'): string[] {
  return items.map(item => `${prefix}_${item.id}`);
}

/**
 * 延迟执行工具
 */
export function delay(ms: number): Promise<void> {
  return new Promise(resolve => setTimeout(resolve, ms));
}

/**
 * 防抖函数包装器
 */
export class Debouncer {
  private timerId: number = -1;
  
  public debounce(callback: () => void, delay: number): void {
    if (this.timerId !== -1) {
      clearTimeout(this.timerId);
    }
    this.timerId = setTimeout(() => {
      callback();
      this.timerId = -1;
    }, delay);
  }
  
  public cancel(): void {
    if (this.timerId !== -1) {
      clearTimeout(this.timerId);
      this.timerId = -1;
    }
  }
}

/**
 * 节流函数包装器
 */
export class Throttler {
  private lastTime: number = 0;
  private timerId: number = -1;
  
  public throttle(callback: () => void, interval: number): void {
    const now = Date.now();
    
    if (now - this.lastTime >= interval) {
      callback();
      this.lastTime = now;
    } else {
      if (this.timerId !== -1) {
        clearTimeout(this.timerId);
      }
      this.timerId = setTimeout(() => {
        callback();
        this.lastTime = Date.now();
        this.timerId = -1;
      }, interval - (now - this.lastTime));
    }
  }
  
  public cancel(): void {
    if (this.timerId !== -1) {
      clearTimeout(this.timerId);
      this.timerId = -1;
    }
  }
}

/**
 * 动画性能监控器
 */
export class AnimationPerformanceMonitor {
  private startTime: number = 0;
  private frameCount: number = 0;
  private fps: number = 0;
  
  public start(): void {
    this.startTime = Date.now();
    this.frameCount = 0;
    this.fps = 0;
  }
  
  public recordFrame(): void {
    this.frameCount++;
    const elapsed = Date.now() - this.startTime;
    if (elapsed > 0) {
      this.fps = Math.round((this.frameCount * 1000) / elapsed);
    }
  }
  
  public getFPS(): number {
    return this.fps;
  }
  
  public getFrameCount(): number {
    return this.frameCount;
  }
  
  public getElapsedTime(): number {
    return Date.now() - this.startTime;
  }
  
  public report(): string {
    return `动画性能: ${this.fps} FPS, ${this.frameCount} 帧, ${this.getElapsedTime()} ms`;
  }
}

/**
 * 快速集成辅助类
 * 封装常用操作，简化集成流程
 */
export class QuickAnimationHelper<T extends AnimatedItem> {
  private oldList: T[] = [];
  private debouncer: Debouncer = new Debouncer();
  
  constructor() {}
  
  /**
   * 更新列表并返回动画类型
   */
  public updateList(newList: T[]): AnimationType {
    const animationType = detectChangeType(this.oldList, newList);
    this.oldList = [...newList];
    return animationType;
  }
  
  /**
   * 带防抖的更新
   */
  public updateListDebounced(
    newList: T[],
    callback: (list: T[], type: AnimationType) => void,
    delayMs: number = 300
  ): void {
    this.debouncer.debounce(() => {
      const animationType = this.updateList(newList);
      callback(newList, animationType);
    }, delayMs);
  }
  
  /**
   * 重置状态
   */
  public reset(): void {
    this.oldList = [];
    this.debouncer.cancel();
  }
}

/**
 * 日志辅助函数
 */
export function logAnimationStart(tag: string, itemCount: number, animationType: AnimationType): void {
  logger.debug(tag, `开始动画: ${itemCount}个条目, 类型: ${animationType}`);
}

export function logAnimationComplete(tag: string, duration: number): void {
  logger.debug(tag, `动画完成: 耗时 ${duration}ms`);
}

export function logAnimationError(tag: string, error: Error | string): void {
  const msg = error instanceof Error ? error.message : String(error);
  logger.error(tag, `动画失败: ${msg}`);
}
