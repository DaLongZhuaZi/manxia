// 文件路径: entry/src/main/ets/components/AnimatedGrid.ets
// 职责: 通用的动画网格组件，支持平滑的条目过渡动画

import { logger } from '../Utils/Logger';
import { ItemTransitionAnimator, AnimationType, AnimationConfig, DEFAULT_ANIMATION_CONFIG, ItemPosition } from '../Framework/Animation/ItemTransitionAnimator';
import { AnimatedGridState, AnimatedItem, GridLayoutConfig } from '../Framework/Animation/AnimatedGridState';
import { SnapshotCapture, getSnapshotCapture } from '../Framework/Animation/SnapshotCapture';

const TAG = 'AnimatedGrid';

/**
 * 动画网格组件
 * 使用方法：
 * 1. 用AnimatedGrid包裹你的Grid组件
 * 2. 为每个GridItem设置唯一的id属性
 * 3. 调用triggerAnimation()方法触发动画
 */
@Component
export struct AnimatedGrid {
  @State private showCanvas: boolean = false;
  @State private canvasWidth: number = 0;
  @State private canvasHeight: number = 0;
  
  private canvasContext: CanvasRenderingContext2D | null = null;
  private animator: ItemTransitionAnimator = new ItemTransitionAnimator();
  private snapshotCapture: SnapshotCapture = getSnapshotCapture();
  private componentId: string = `animated_grid_${Date.now()}_${Math.random()}`;
  
  // 布局配置
  @Prop columns: number = 3;
  @Prop itemWidth: number = 100;
  @Prop itemHeight: number = 150;
  @Prop columnGap: number = 12;
  @Prop rowGap: number = 12;
  @Prop paddingLeft: number = 16;
  @Prop paddingTop: number = 16;
  
  // 动画配置
  @Prop animationDuration: number = 400;
  @Prop enableFadeIn: boolean = true;
  @Prop enableFadeOut: boolean = true;
  @Prop enableScale: boolean = true;
  @Prop staggerDelay: number = 30;
  
  // 子组件构建器
  @BuilderParam gridContent: () => void;
  
  // 控制器绑定回调
  onComponentReady?: (component: AnimatedGrid) => void;
  
  aboutToAppear(): void {
    this.snapshotCapture.init(this.getUIContext());
    
    // 更新动画配置
    this.animator.updateConfig({
      duration: this.animationDuration,
      enableFadeIn: this.enableFadeIn,
      enableFadeOut: this.enableFadeOut,
      enableScale: this.enableScale,
      staggerDelay: this.staggerDelay
    });
    
    // 通知控制器组件已准备好
    if (this.onComponentReady) {
      this.onComponentReady(this);
      logger.debug(TAG, `AnimatedGrid已通知控制器: ${this.componentId}`);
    }
    
    logger.debug(TAG, `AnimatedGrid初始化: ${this.componentId}`);
  }

  aboutToDisappear(): void {
    this.animator.stopAnimation();
  }

  build() {
    Stack() {
      // 底层：实际的Grid内容
      Column() {
        this.gridContent();
      }
      .width('100%')
      .height('100%')
      .id(`${this.componentId}_content`)

      // 顶层：Canvas动画层
      if (this.showCanvas) {
        Canvas(this.canvasContext)
          .width('100%')
          .height('100%')
          .backgroundColor(Color.Transparent)
          .onReady(() => {
            if (this.canvasContext) {
              this.animator.initCanvas(
                this.canvasContext,
                this.canvasWidth,
                this.canvasHeight
              );
            }
          })
          .onAreaChange((oldArea, newArea) => {
            this.canvasWidth = newArea.width as number;
            this.canvasHeight = newArea.height as number;
            this.animator.updateCanvasSize(this.canvasWidth, this.canvasHeight);
          })
      }
    }
    .width('100%')
    .height('100%')
  }

  /**
   * 触发动画
   * @param itemIds 需要动画的条目ID列表
   * @param oldPositions 旧位置列表
   * @param newPositions 新位置列表
   * @param animationType 动画类型
   */
  public async triggerAnimation(
    itemIds: string[],
    oldPositions: ItemPosition[],
    newPositions: ItemPosition[],
    animationType: AnimationType
  ): Promise<void> {
    if (itemIds.length === 0) {
      logger.warn(TAG, '没有需要动画的条目');
      return;
    }

    logger.debug(TAG, `触发动画: ${itemIds.length}个条目, 类型: ${animationType}`);

    try {
      // 1. 捕获快照
      const pixelMaps = await this.snapshotCapture.captureComponents(itemIds, {
        scale: 1.0,
        waitTime: 50
      });

      if (pixelMaps.size === 0) {
        logger.warn(TAG, '没有成功捕获任何快照');
        return;
      }

      // 2. 准备动画
      this.animator.prepareAnimation(
        oldPositions,
        newPositions,
        pixelMaps,
        animationType
      );

      // 3. 显示Canvas层
      this.showCanvas = true;

      // 4. 等待Canvas准备好
      await this.delay(50);

      // 5. 开始动画
      await new Promise<void>((resolve) => {
        this.animator.startAnimation(() => {
          // 动画完成
          this.showCanvas = false;
          
          // 释放PixelMap资源
          this.snapshotCapture.releasePixelMaps(pixelMaps);
          
          logger.debug(TAG, '动画完成');
          resolve();
        });
      });
    } catch (err) {
      const msg = err instanceof Error ? err.message : String(err);
      logger.error(TAG, `动画执行失败: ${msg}`);
      this.showCanvas = false;
    }
  }

  /**
   * 延迟工具方法
   */
  private delay(ms: number): Promise<void> {
    return new Promise(resolve => setTimeout(resolve, ms));
  }
}

/**
 * 动画组件接口
 */
interface IAnimatedComponent {
  triggerAnimation(
    itemIds: string[],
    oldPositions: ItemPosition[],
    newPositions: ItemPosition[],
    animationType: AnimationType
  ): Promise<void>;
}

/**
 * 简化版动画网格控制器
 * 用于管理动画状态和触发动画
 */
export class AnimatedGridController<T extends AnimatedItem> {
  private gridState: AnimatedGridState<T>;
  private animatedGridRef: IAnimatedComponent | null = null;

  constructor(layoutConfig: GridLayoutConfig) {
    this.gridState = new AnimatedGridState<T>(layoutConfig);
  }

  /**
   * 绑定AnimatedGrid或AnimatedList组件引用
   */
  public bindComponent(component: IAnimatedComponent): void {
    this.animatedGridRef = component;
  }

  /**
   * 更新布局配置
   */
  public updateLayoutConfig(config: Partial<GridLayoutConfig>): void {
    this.gridState.updateLayoutConfig(config);
  }

  /**
   * 更新条目列表（自动触发动画）
   * @param newItems 新的条目列表
   * @param animationType 动画类型（可选，不指定则自动检测）
   */
  public async updateItems(newItems: T[], animationType?: AnimationType): Promise<void> {
    logger.debug(TAG, `🎬 updateItems调用: 新条目数=${newItems.length}, 动画类型=${animationType}, 组件已绑定=${!!this.animatedGridRef}`);
    
    // 更新状态
    this.gridState.updateItems(newItems, animationType);

    // 检查是否需要动画
    if (!this.gridState.hasPendingAnimation()) {
      logger.debug(TAG, '⏭️ 无需动画');
      return;
    }

    // 获取动画信息
    const pendingType = this.gridState.getPendingAnimationType();
    if (!pendingType) {
      logger.warn(TAG, '⚠️ 待处理动画类型为空');
      return;
    }

    const oldPositions = this.gridState.getPreviousPositions();
    const newPositions = this.gridState.getCurrentPositions();

    // 收集需要动画的条目ID
    const itemIds = this.collectAnimatingItemIds(pendingType);
    
    logger.debug(TAG, `🎯 准备触发动画: 类型=${pendingType}, 条目数=${itemIds.length}, 旧位置=${oldPositions.length}, 新位置=${newPositions.length}`);

    // 触发动画
    if (this.animatedGridRef && itemIds.length > 0) {
      logger.debug(TAG, `✨ 开始执行动画...`);
      await this.animatedGridRef.triggerAnimation(
        itemIds,
        oldPositions,
        newPositions,
        pendingType
      );
      logger.debug(TAG, `✅ 动画执行完成`);
    } else {
      logger.warn(TAG, `❌ 无法触发动画: 组件引用=${!!this.animatedGridRef}, 条目数=${itemIds.length}`);
    }

    // 清除待处理状态
    this.gridState.clearPendingAnimationType();
  }

  /**
   * 收集需要动画的条目ID
   */
  private collectAnimatingItemIds(animationType: AnimationType): string[] {
    const allIds = new Set<string>();

    switch (animationType) {
      case AnimationType.ADD:
        // 新增的条目 + 移动的条目
        this.gridState.getAddedItemIds().forEach(id => allIds.add(id));
        this.gridState.getMovedItemIds().forEach(id => allIds.add(id));
        break;

      case AnimationType.REMOVE:
        // 删除的条目 + 移动的条目
        this.gridState.getRemovedItemIds().forEach(id => allIds.add(id));
        this.gridState.getMovedItemIds().forEach(id => allIds.add(id));
        break;

      case AnimationType.MOVE:
      case AnimationType.REFRESH:
        // 所有当前条目
        this.gridState.getCurrentItems().forEach(item => allIds.add(item.id));
        break;
    }

    return Array.from(allIds);
  }

  /**
   * 获取当前条目列表
   */
  public getCurrentItems(): T[] {
    return this.gridState.getCurrentItems();
  }

  /**
   * 重置状态
   */
  public reset(): void {
    this.gridState.reset();
  }
}
