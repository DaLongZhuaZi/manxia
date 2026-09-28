// 文件路径: entry/src/main/ets/Framework/Animation/AnimatedGridState.ets
// 职责: 动画网格状态管理，跟踪条目变化并触发动画

import { logger } from 'manxia_core/src/main/ets/Utils/Logger';
import { ItemPosition, AnimationType } from './ItemTransitionAnimator';

const TAG = 'AnimatedGridState';

/**
 * 条目数据接口（泛型）
 */
export interface AnimatedItem {
  id: string;  // 必须有唯一ID
}

/**
 * 网格布局配置
 */
export interface GridLayoutConfig {
  columns: number;           // 列数
  itemWidth: number;         // 条目宽度
  itemHeight: number;        // 条目高度
  columnGap: number;         // 列间距
  rowGap: number;            // 行间距
  paddingLeft: number;       // 左内边距
  paddingTop: number;        // 上内边距
}

/**
 * 动画网格状态类
 */
export class AnimatedGridState<T extends AnimatedItem> {
  private currentItems: T[] = [];
  private previousItems: T[] = [];
  private currentPositions: Map<string, ItemPosition> = new Map();
  private previousPositions: Map<string, ItemPosition> = new Map();
  private layoutConfig: GridLayoutConfig;
  private pendingAnimationType: AnimationType | null = null;

  constructor(layoutConfig: GridLayoutConfig) {
    this.layoutConfig = layoutConfig;
  }

  /**
   * 更新布局配置
   */
  public updateLayoutConfig(config: Partial<GridLayoutConfig>): void {
    this.layoutConfig = {
      columns: config.columns ?? this.layoutConfig.columns,
      itemWidth: config.itemWidth ?? this.layoutConfig.itemWidth,
      itemHeight: config.itemHeight ?? this.layoutConfig.itemHeight,
      columnGap: config.columnGap ?? this.layoutConfig.columnGap,
      rowGap: config.rowGap ?? this.layoutConfig.rowGap,
      paddingLeft: config.paddingLeft ?? this.layoutConfig.paddingLeft,
      paddingTop: config.paddingTop ?? this.layoutConfig.paddingTop
    };
    logger.debug(TAG, `布局配置已更新: ${this.layoutConfig.columns}列`);
  }

  /**
   * 获取当前布局配置
   */
  public getLayoutConfig(): GridLayoutConfig {
    return {
      columns: this.layoutConfig.columns,
      itemWidth: this.layoutConfig.itemWidth,
      itemHeight: this.layoutConfig.itemHeight,
      columnGap: this.layoutConfig.columnGap,
      rowGap: this.layoutConfig.rowGap,
      paddingLeft: this.layoutConfig.paddingLeft,
      paddingTop: this.layoutConfig.paddingTop
    };
  }

  /**
   * 更新条目列表
   * @param newItems 新的条目列表
   * @param animationType 动画类型（如果不指定则自动检测）
   */
  public updateItems(newItems: T[], animationType?: AnimationType): void {
    // 保存旧状态
    this.previousItems = this.currentItems.slice();
    const newPrevPositions = new Map<string, ItemPosition>();
    this.currentPositions.forEach((value, key) => {
      newPrevPositions.set(key, value);
    });
    this.previousPositions = newPrevPositions;
    
    // 更新当前状态
    this.currentItems = newItems.slice();
    this.currentPositions = this.calculatePositions(newItems);
    
    // 确定动画类型
    if (animationType) {
      this.pendingAnimationType = animationType;
    } else {
      this.pendingAnimationType = this.detectAnimationType();
    }
    
    logger.debug(TAG, `条目已更新: ${this.previousItems.length} -> ${this.currentItems.length}, 动画类型: ${this.pendingAnimationType}`);
  }

  /**
   * 计算条目位置
   */
  private calculatePositions(items: T[]): Map<string, ItemPosition> {
    const positions = new Map<string, ItemPosition>();
    const columns = this.layoutConfig.columns;
    const itemWidth = this.layoutConfig.itemWidth;
    const itemHeight = this.layoutConfig.itemHeight;
    const columnGap = this.layoutConfig.columnGap;
    const rowGap = this.layoutConfig.rowGap;
    const paddingLeft = this.layoutConfig.paddingLeft;
    const paddingTop = this.layoutConfig.paddingTop;
    
    items.forEach((item, index) => {
      const row = Math.floor(index / columns);
      const col = index % columns;
      
      const x = paddingLeft + col * (itemWidth + columnGap);
      const y = paddingTop + row * (itemHeight + rowGap);
      
      positions.set(item.id, {
        id: item.id,
        x: x,
        y: y,
        width: itemWidth,
        height: itemHeight,
        index: index
      });
    });
    
    return positions;
  }

  /**
   * 自动检测动画类型
   */
  private detectAnimationType(): AnimationType {
    const prevCount = this.previousItems.length;
    const currCount = this.currentItems.length;
    
    if (prevCount === 0) {
      // 初始加载，不需要动画
      return AnimationType.REFRESH;
    }
    
    if (currCount > prevCount) {
      // 有新增条目
      return AnimationType.ADD;
    }
    
    if (currCount < prevCount) {
      // 有删除条目
      return AnimationType.REMOVE;
    }
    
    // 检查是否有条目ID变化
    const prevIds = new Set(this.previousItems.map(item => item.id));
    const currIds = new Set(this.currentItems.map(item => item.id));
    
    let hasNewId = false;
    let hasRemovedId = false;
    
    currIds.forEach(id => {
      if (!prevIds.has(id)) {
        hasNewId = true;
      }
    });
    
    prevIds.forEach(id => {
      if (!currIds.has(id)) {
        hasRemovedId = true;
      }
    });
    
    if (hasNewId && hasRemovedId) {
      // 既有新增又有删除
      return AnimationType.REFRESH;
    }
    
    if (hasNewId) {
      return AnimationType.ADD;
    }
    
    if (hasRemovedId) {
      return AnimationType.REMOVE;
    }
    
    // 只是位置变化
    return AnimationType.MOVE;
  }

  /**
   * 获取待处理的动画类型
   */
  public getPendingAnimationType(): AnimationType | null {
    return this.pendingAnimationType;
  }

  /**
   * 清除待处理的动画类型
   */
  public clearPendingAnimationType(): void {
    this.pendingAnimationType = null;
  }

  /**
   * 获取当前条目列表
   */
  public getCurrentItems(): T[] {
    return this.currentItems.slice();
  }

  /**
   * 获取之前的条目列表
   */
  public getPreviousItems(): T[] {
    return this.previousItems.slice();
  }

  /**
   * 获取当前位置列表
   */
  public getCurrentPositions(): ItemPosition[] {
    return Array.from(this.currentPositions.values());
  }

  /**
   * 获取之前的位置列表
   */
  public getPreviousPositions(): ItemPosition[] {
    return Array.from(this.previousPositions.values());
  }

  /**
   * 获取指定条目的当前位置
   */
  public getCurrentPosition(id: string): ItemPosition | null {
    return this.currentPositions.get(id) || null;
  }

  /**
   * 获取指定条目的之前位置
   */
  public getPreviousPosition(id: string): ItemPosition | null {
    return this.previousPositions.get(id) || null;
  }

  /**
   * 检查是否有待处理的动画
   */
  public hasPendingAnimation(): boolean {
    return this.pendingAnimationType !== null && this.previousItems.length > 0;
  }

  /**
   * 获取新增的条目ID列表
   */
  public getAddedItemIds(): string[] {
    const prevIds = new Set(this.previousItems.map(item => item.id));
    return this.currentItems
      .filter(item => !prevIds.has(item.id))
      .map(item => item.id);
  }

  /**
   * 获取删除的条目ID列表
   */
  public getRemovedItemIds(): string[] {
    const currIds = new Set(this.currentItems.map(item => item.id));
    return this.previousItems
      .filter(item => !currIds.has(item.id))
      .map(item => item.id);
  }

  /**
   * 获取移动的条目ID列表
   */
  public getMovedItemIds(): string[] {
    const movedIds: string[] = [];
    
    this.currentItems.forEach(item => {
      const currPos = this.currentPositions.get(item.id);
      const prevPos = this.previousPositions.get(item.id);
      
      if (currPos && prevPos) {
        // 检查位置是否变化
        if (currPos.x !== prevPos.x || currPos.y !== prevPos.y) {
          movedIds.push(item.id);
        }
      }
    });
    
    return movedIds;
  }

  /**
   * 重置状态
   */
  public reset(): void {
    this.currentItems = [];
    this.previousItems = [];
    this.currentPositions.clear();
    this.previousPositions.clear();
    this.pendingAnimationType = null;
    logger.debug(TAG, '状态已重置');
  }
}
