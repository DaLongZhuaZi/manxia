// 文件路径: entry/src/main/ets/Framework/Animation/ItemTransitionAnimator.ets
// 职责: 通用的条目过渡动画引擎，使用Canvas绘制平滑的位置变换动画

import { logger } from 'manxia_core/src/main/ets/Utils/Logger';
import { curves } from '@kit.ArkUI';

const TAG = 'ItemTransitionAnimator';

/**
 * 条目位置信息
 */
export interface ItemPosition {
  id: string;           // 条目唯一标识
  x: number;            // X坐标
  y: number;            // Y坐标
  width: number;        // 宽度
  height: number;       // 高度
  index: number;        // 在列表中的索引
}

/**
 * 条目快照信息（用于Canvas绘制）
 */
export interface ItemSnapshot {
  id: string;
  pixelMap: PixelMap | null;  // 条目的像素图快照
  fromPos: ItemPosition;       // 起始位置
  toPos: ItemPosition;         // 目标位置
  currentX: number;            // 当前X坐标
  currentY: number;            // 当前Y坐标
  opacity: number;             // 不透明度
  scale: number;               // 缩放比例
}

/**
 * 动画操作类型
 */
export enum AnimationType {
  ADD = 'add',           // 添加条目
  REMOVE = 'remove',     // 删除条目
  MOVE = 'move',         // 移动条目
  REFRESH = 'refresh'    // 刷新（重新排列）
}

/**
 * 动画配置
 */
export interface AnimationConfig {
  duration: number;              // 动画时长（毫秒）
  curve: Curve | ICurve;        // 缓动曲线
  enableFadeIn: boolean;        // 是否启用淡入效果
  enableFadeOut: boolean;       // 是否启用淡出效果
  enableScale: boolean;         // 是否启用缩放效果
  staggerDelay: number;         // 交错延迟（毫秒）
}

/**
 * 默认动画配置
 */
export const DEFAULT_ANIMATION_CONFIG: AnimationConfig = {
  duration: 400,
  curve: curves.springMotion(0.6, 0.8),
  enableFadeIn: true,
  enableFadeOut: true,
  enableScale: true,
  staggerDelay: 30
};

/**
 * 条目过渡动画器核心类
 */
export class ItemTransitionAnimator {
  private canvasWidth: number = 0;
  private canvasHeight: number = 0;
  private animatingSnapshots: ItemSnapshot[] = [];
  private isAnimating: boolean = false;
  private animationStartTime: number = 0;
  private animationFrameId: number = -1;
  private config: AnimationConfig;
  private renderingContext: CanvasRenderingContext2D | null = null;

  constructor(config?: Partial<AnimationConfig>) {
    this.config = {
      duration: config?.duration ?? DEFAULT_ANIMATION_CONFIG.duration,
      curve: config?.curve ?? DEFAULT_ANIMATION_CONFIG.curve,
      enableFadeIn: config?.enableFadeIn ?? DEFAULT_ANIMATION_CONFIG.enableFadeIn,
      enableFadeOut: config?.enableFadeOut ?? DEFAULT_ANIMATION_CONFIG.enableFadeOut,
      enableScale: config?.enableScale ?? DEFAULT_ANIMATION_CONFIG.enableScale,
      staggerDelay: config?.staggerDelay ?? DEFAULT_ANIMATION_CONFIG.staggerDelay
    };
  }

  /**
   * 初始化Canvas上下文
   */
  public initCanvas(context: CanvasRenderingContext2D, width: number, height: number): void {
    this.renderingContext = context;
    this.canvasWidth = width;
    this.canvasHeight = height;
    logger.debug(TAG, `Canvas初始化: ${width}x${height}`);
  }

  /**
   * 更新Canvas尺寸
   */
  public updateCanvasSize(width: number, height: number): void {
    this.canvasWidth = width;
    this.canvasHeight = height;
  }

  /**
   * 计算网格布局的条目位置
   * @param itemCount 条目总数
   * @param columns 列数
   * @param itemWidth 条目宽度
   * @param itemHeight 条目高度
   * @param columnGap 列间距
   * @param rowGap 行间距
   * @param paddingLeft 左内边距
   * @param paddingTop 上内边距
   */
  public calculateGridPositions(
    itemCount: number,
    columns: number,
    itemWidth: number,
    itemHeight: number,
    columnGap: number,
    rowGap: number,
    paddingLeft: number = 0,
    paddingTop: number = 0
  ): ItemPosition[] {
    const positions: ItemPosition[] = [];
    
    for (let i = 0; i < itemCount; i++) {
      const row = Math.floor(i / columns);
      const col = i % columns;
      
      const x = paddingLeft + col * (itemWidth + columnGap);
      const y = paddingTop + row * (itemHeight + rowGap);
      
      positions.push({
        id: `item_${i}`,
        x: x,
        y: y,
        width: itemWidth,
        height: itemHeight,
        index: i
      });
    }
    
    return positions;
  }

  /**
   * 准备动画快照
   * @param oldPositions 旧位置列表
   * @param newPositions 新位置列表
   * @param pixelMaps 条目的PixelMap快照（key为条目ID）
   * @param animationType 动画类型
   */
  public prepareAnimation(
    oldPositions: ItemPosition[],
    newPositions: ItemPosition[],
    pixelMaps: Map<string, PixelMap>,
    animationType: AnimationType
  ): void {
    this.animatingSnapshots = [];
    
    // 创建ID到位置的映射
    const oldPosMap = new Map<string, ItemPosition>();
    const newPosMap = new Map<string, ItemPosition>();
    
    for (let i = 0; i < oldPositions.length; i++) {
      const pos = oldPositions[i];
      oldPosMap.set(pos.id, pos);
    }
    for (let i = 0; i < newPositions.length; i++) {
      const pos = newPositions[i];
      newPosMap.set(pos.id, pos);
    }
    
    // 处理不同的动画类型
    switch (animationType) {
      case AnimationType.REMOVE:
        this.prepareRemoveAnimation(oldPosMap, newPosMap, pixelMaps);
        break;
      case AnimationType.ADD:
        this.prepareAddAnimation(oldPosMap, newPosMap, pixelMaps);
        break;
      case AnimationType.MOVE:
      case AnimationType.REFRESH:
        this.prepareMoveAnimation(oldPosMap, newPosMap, pixelMaps);
        break;
    }
    
    logger.debug(TAG, `准备动画快照: ${this.animatingSnapshots.length}个条目`);
  }

  /**
   * 准备删除动画
   */
  private prepareRemoveAnimation(
    oldPosMap: Map<string, ItemPosition>,
    newPosMap: Map<string, ItemPosition>,
    pixelMaps: Map<string, PixelMap>
  ): void {
    // 被删除的条目：淡出并缩小
    oldPosMap.forEach((oldPos, id) => {
      if (!newPosMap.has(id)) {
        const pixelMap = pixelMaps.get(id) || null;
        const toPos: ItemPosition = {
          id: oldPos.id,
          x: oldPos.x,
          y: oldPos.y,
          width: oldPos.width * 0.8,
          height: oldPos.height * 0.8,
          index: oldPos.index
        };
        const snapshot: ItemSnapshot = {
          id: id,
          pixelMap: pixelMap,
          fromPos: oldPos,
          toPos: toPos,
          currentX: oldPos.x,
          currentY: oldPos.y,
          opacity: 1.0,
          scale: 1.0
        };
        this.animatingSnapshots.push(snapshot);
      }
    });
    
    // 保留的条目：移动到新位置
    newPosMap.forEach((newPos, id) => {
      const oldPos = oldPosMap.get(id);
      if (oldPos) {
        const pixelMap = pixelMaps.get(id) || null;
        const snapshot: ItemSnapshot = {
          id: id,
          pixelMap: pixelMap,
          fromPos: oldPos,
          toPos: newPos,
          currentX: oldPos.x,
          currentY: oldPos.y,
          opacity: 1.0,
          scale: 1.0
        };
        this.animatingSnapshots.push(snapshot);
      }
    });
  }

  /**
   * 准备添加动画
   */
  private prepareAddAnimation(
    oldPosMap: Map<string, ItemPosition>,
    newPosMap: Map<string, ItemPosition>,
    pixelMaps: Map<string, PixelMap>
  ): void {
    // 新增的条目：淡入并放大
    newPosMap.forEach((newPos, id) => {
      const pixelMap = pixelMaps.get(id) || null;
      if (!oldPosMap.has(id)) {
        const fromPos: ItemPosition = {
          id: newPos.id,
          x: newPos.x,
          y: newPos.y,
          width: newPos.width * 0.8,
          height: newPos.height * 0.8,
          index: newPos.index
        };
        const snapshot: ItemSnapshot = {
          id: id,
          pixelMap: pixelMap,
          fromPos: fromPos,
          toPos: newPos,
          currentX: newPos.x,
          currentY: newPos.y,
          opacity: 0.0,
          scale: 0.8
        };
        this.animatingSnapshots.push(snapshot);
      } else {
        // 已存在的条目：移动到新位置
        const oldPos = oldPosMap.get(id)!;
        this.animatingSnapshots.push({
          id: id,
          pixelMap: pixelMap,
          fromPos: oldPos,
          toPos: newPos,
          currentX: oldPos.x,
          currentY: oldPos.y,
          opacity: 1.0,
          scale: 1.0
        });
      }
    });
  }

  /**
   * 准备移动动画
   */
  private prepareMoveAnimation(
    oldPosMap: Map<string, ItemPosition>,
    newPosMap: Map<string, ItemPosition>,
    pixelMaps: Map<string, PixelMap>
  ): void {
    // 所有条目都移动到新位置
    newPosMap.forEach((newPos, id) => {
      const oldPos = oldPosMap.get(id);
      const pixelMap = pixelMaps.get(id) || null;
      
      if (oldPos) {
        this.animatingSnapshots.push({
          id: id,
          pixelMap: pixelMap,
          fromPos: oldPos,
          toPos: newPos,
          currentX: oldPos.x,
          currentY: oldPos.y,
          opacity: 1.0,
          scale: 1.0
        });
      } else {
        // 新条目
        this.animatingSnapshots.push({
          id: id,
          pixelMap: pixelMap,
          fromPos: newPos,
          toPos: newPos,
          currentX: newPos.x,
          currentY: newPos.y,
          opacity: 0.0,
          scale: 0.8
        });
      }
    });
  }

  /**
   * 开始动画
   * @param onComplete 动画完成回调
   */
  public startAnimation(onComplete?: () => void): void {
    if (this.isAnimating) {
      logger.warn(TAG, '动画已在进行中');
      return;
    }
    
    if (this.animatingSnapshots.length === 0) {
      logger.warn(TAG, '没有需要动画的条目');
      onComplete?.();
      return;
    }
    
    this.isAnimating = true;
    this.animationStartTime = Date.now();
    
    logger.debug(TAG, `开始动画: ${this.animatingSnapshots.length}个条目`);
    
    // 启动动画循环
    this.animateFrame(onComplete);
  }

  /**
   * 动画帧更新
   */
  private animateFrame(onComplete?: () => void): void {
    if (!this.isAnimating) {
      return;
    }
    
    const elapsed = Date.now() - this.animationStartTime;
    const progress = Math.min(elapsed / this.config.duration, 1.0);
    
    // 使用缓动曲线计算进度
    const easedProgress = this.applyCurve(progress);
    
    // 更新所有快照的位置和属性
    this.animatingSnapshots.forEach((snapshot, index) => {
      // 计算交错延迟
      const staggerProgress = Math.max(0, Math.min(1, 
        (elapsed - index * this.config.staggerDelay) / this.config.duration
      ));
      const staggeredEasedProgress = this.applyCurve(staggerProgress);
      
      // 更新位置
      snapshot.currentX = this.lerp(snapshot.fromPos.x, snapshot.toPos.x, staggeredEasedProgress);
      snapshot.currentY = this.lerp(snapshot.fromPos.y, snapshot.toPos.y, staggeredEasedProgress);
      
      // 更新不透明度
      if (this.config.enableFadeIn && snapshot.fromPos === snapshot.toPos) {
        snapshot.opacity = staggeredEasedProgress;
      } else if (this.config.enableFadeOut && !this.hasNewPosition(snapshot.id)) {
        snapshot.opacity = 1.0 - staggeredEasedProgress;
      }
      
      // 更新缩放
      if (this.config.enableScale) {
        const fromScale = snapshot.fromPos.width / snapshot.toPos.width;
        const toScale = 1.0;
        snapshot.scale = this.lerp(fromScale, toScale, staggeredEasedProgress);
      }
    });
    
    // 绘制当前帧
    this.drawFrame();
    
    // 检查动画是否完成
    if (progress >= 1.0) {
      this.stopAnimation();
      onComplete?.();
    } else {
      // 继续下一帧（使用setTimeout模拟requestAnimationFrame）
      this.animationFrameId = setTimeout(() => this.animateFrame(onComplete), 16) as number;
    }
  }

  /**
   * 绘制当前帧
   */
  private drawFrame(): void {
    if (!this.renderingContext) {
      return;
    }
    
    const ctx = this.renderingContext;
    
    // 清空画布
    ctx.clearRect(0, 0, this.canvasWidth, this.canvasHeight);
    
    // 绘制所有快照
    this.animatingSnapshots.forEach(snapshot => {
      if (!snapshot.pixelMap) {
        return;
      }
      
      ctx.save();
      
      // 设置不透明度
      ctx.globalAlpha = snapshot.opacity;
      
      // 计算绘制位置和尺寸
      const drawWidth = snapshot.toPos.width * snapshot.scale;
      const drawHeight = snapshot.toPos.height * snapshot.scale;
      const drawX = snapshot.currentX + (snapshot.toPos.width - drawWidth) / 2;
      const drawY = snapshot.currentY + (snapshot.toPos.height - drawHeight) / 2;
      
      // 绘制PixelMap
      try {
        ctx.drawImage(snapshot.pixelMap, drawX, drawY, drawWidth, drawHeight);
      } catch (err) {
        logger.warn(TAG, `绘制快照失败: ${err}`);
      }
      
      ctx.restore();
    });
  }

  /**
   * 停止动画
   */
  public stopAnimation(): void {
    if (this.animationFrameId !== -1) {
      clearTimeout(this.animationFrameId);
      this.animationFrameId = -1;
    }
    
    this.isAnimating = false;
    this.animatingSnapshots = [];
    
    // 清空画布
    if (this.renderingContext) {
      this.renderingContext.clearRect(0, 0, this.canvasWidth, this.canvasHeight);
    }
    
    logger.debug(TAG, '动画已停止');
  }

  /**
   * 检查条目是否有新位置
   */
  private hasNewPosition(id: string): boolean {
    const snapshot = this.animatingSnapshots.find(s => s.id === id);
    return snapshot ? snapshot.fromPos !== snapshot.toPos : false;
  }

  /**
   * 线性插值
   */
  private lerp(start: number, end: number, t: number): number {
    return start + (end - start) * t;
  }

  /**
   * 应用缓动曲线
   */
  private applyCurve(t: number): number {
    // 如果是ICurve对象，使用interpolate方法
    if (typeof this.config.curve === 'object') {
      const curve = this.config.curve as ICurve;
      if (curve.interpolate) {
        return curve.interpolate(t);
      }
    }
    // 否则直接返回线性进度
    return t;
  }

  /**
   * 获取动画状态
   */
  public isRunning(): boolean {
    return this.isAnimating;
  }

  /**
   * 更新动画配置
   */
  public updateConfig(config: Partial<AnimationConfig>): void {
    this.config = {
      duration: config.duration ?? this.config.duration,
      curve: config.curve ?? this.config.curve,
      enableFadeIn: config.enableFadeIn ?? this.config.enableFadeIn,
      enableFadeOut: config.enableFadeOut ?? this.config.enableFadeOut,
      enableScale: config.enableScale ?? this.config.enableScale,
      staggerDelay: config.staggerDelay ?? this.config.staggerDelay
    };
  }
}
