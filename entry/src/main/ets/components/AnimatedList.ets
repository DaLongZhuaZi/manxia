import { AnimatedItem } from '../Framework/Animation/AnimatedGridState';
import { AnimationType, ItemPosition } from '../Framework/Animation/ItemTransitionAnimator';
import { AnimatedGridController } from './AnimatedGrid';
import { logger } from '../Utils/Logger';

const TAG = 'AnimatedList';

interface PositionInfo {
  x: number;
  y: number;
  width: number;
  height: number;
}

@Component
export struct AnimatedList {
  @Prop itemHeight: number = 150;
  @Prop itemGap: number = 12;
  @Prop paddingLeft: number = 16;
  @Prop paddingRight: number = 16;
  @Prop paddingTop: number = 16;
  @Prop animationDuration: number = 400;
  @Prop enableFadeIn: boolean = true;
  @Prop enableFadeOut: boolean = true;
  @Prop enableScale: boolean = true;
  @Prop staggerDelay: number = 30;
  
  @BuilderParam listContent: () => void;
  
  onComponentReady?: (component: AnimatedList) => void;
  
  private componentId: string = `animated_list_${Date.now()}_${Math.random()}`;
  @State private showCanvas: boolean = false;
  
  aboutToAppear(): void {
    if (this.onComponentReady) {
      this.onComponentReady(this);
      logger.debug(TAG, `AnimatedList已通知控制器: ${this.componentId}`);
    }
    
    logger.debug(TAG, `AnimatedList初始化: ${this.componentId}`);
  }

  build() {
    List({ space: this.itemGap }) {
      this.listContent();
    }
    .width('100%')
    .height('100%')
    .padding({
      left: this.paddingLeft,
      right: this.paddingRight,
      top: this.paddingTop
    })
    .scrollBar(BarState.Auto)
    .edgeEffect(EdgeEffect.Spring)
  }

  public async triggerAnimation(
    itemIds: string[],
    oldPositions: ItemPosition[],
    newPositions: ItemPosition[],
    animationType: AnimationType
  ): Promise<void> {
    logger.debug(TAG, `🎬 触发动画: 类型=${animationType}, 条目数=${itemIds.length}`);
    
    if (itemIds.length === 0) {
      logger.debug(TAG, '⏭️ 无需动画的条目');
      return;
    }

    await this.delay(this.animationDuration);
    logger.debug(TAG, '✅ 动画完成');
  }

  private delay(ms: number): Promise<void> {
    return new Promise<void>((resolve: () => void) => {
      setTimeout(resolve, ms);
    });
  }
}
