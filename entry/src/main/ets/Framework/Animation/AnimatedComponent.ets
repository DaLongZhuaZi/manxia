// 文件路径: src/main/ets/Framework/Animation/AnimatedComponent.ets
/**
 * 传统动画组件
 * 提供统一的动画接口和状态管理，支持传统动画系统
 */

import { logger } from '../../Utils/Logger';
import { UIContext } from '@kit.ArkUI';
import { 
  AnimationType, 
  AnimationConfig, 
  AnimationCallbacks,
  globalAnimationManager,
  AnimationUtils
} from './GlobalAnimationSystem';

const TAG = 'AnimatedComponent';

/**
 * 动画状态接口
 */
export interface AnimationStatus {
  isActive: boolean;
  animationId: string;
  currentType: string;
}

/**
 * 动画组件属性接口
 */
export interface AnimatedComponentProps {
  enableAnimation?: boolean;
  initialAnimation?: AnimationType;
  initialAnimationDelay?: number;
  animationDuration?: number;
  isEnabled?: boolean;
  content: () => void;
  onAnimationStart?: () => void;
  onAnimationComplete?: () => void;
}

/**
 * 传统动画组件
 */
@Component
export struct AnimatedComponent {
  @Prop animationType: AnimationType = AnimationType.FADE_IN;
  @Prop duration: number = 300;
  @Prop delay: number = 0;
  @Prop curve: Curve = Curve.EaseInOut;
  @Prop autoPlay: boolean = true;
  @Prop loop: boolean = false;
  @Prop isEnabled: boolean = true;
  
  // 回调函数不能使用@Prop装饰器，改为普通属性
  onAnimationStart?: () => void;
  onAnimationComplete?: () => void;
  
  @BuilderParam content: () => void;

  // 动画状态
  @State private isVisible: boolean = false;
  @State private componentOpacity: number = 0;
  @State private scaleX: number = 1;
  @State private scaleY: number = 1;
  @State private translateX: number = 0;
  @State private translateY: number = 0;
  @State private rotateAngle: number = 0;

  private animationId: string = '';
  private uiContext: UIContext | undefined = undefined;

  aboutToAppear() {
    this.animationId = AnimationUtils.generateAnimationId();
    
    // 获取UIContext
    this.uiContext = this.getUIContext();
    if (!this.uiContext) {
      logger.error(TAG, '获取UIContext失败');
      return;
    }
    
    if (this.autoPlay) {
      this.setInitialState();
      this.playAnimation();
    } else {
      this.setTargetState();
    }
  }

  aboutToDisappear() {
    // 清理动画系统
    globalAnimationManager.removeAnimationState(this.animationId);
    
    logger.debug(TAG, `组件销毁，清理动画: ${this.animationId}`);
  }



  /**
   * 播放动画
   */
  private playAnimation(): void {
    if (!this.autoPlay || !this.uiContext) return;

    this.onAnimationStart?.();

    // 设置初始状态
    this.setInitialState();

    // 延迟播放动画
    setTimeout(() => {
      this.uiContext!.animateTo({
        duration: this.duration,
        curve: this.curve,
        onFinish: () => {
          this.onAnimationComplete?.();
          
          if (this.loop) {
            // 如果需要循环，重置状态并重新播放
            setTimeout(() => {
              this.playAnimation();
            }, 100);
          }
        }
      }, () => {
        this.setTargetState();
      });
    }, this.delay);

    logger.debug(TAG, `播放动画: ${this.animationType}, 持续时间: ${this.duration}ms`);
  }

  /**
   * 设置初始状态
   */
  private setInitialState(): void {
    switch (this.animationType) {
      case AnimationType.FADE_IN:
        this.componentOpacity = 0;
        break;
      case AnimationType.FADE_OUT:
        this.componentOpacity = 1;
        break;
      case AnimationType.SLIDE_IN_LEFT:
        this.translateX = -100;
        this.componentOpacity = 0;
        break;
      case AnimationType.SLIDE_IN_RIGHT:
        this.translateX = 100;
        this.componentOpacity = 0;
        break;
      case AnimationType.SLIDE_IN_UP:
        this.translateY = -100;
        this.componentOpacity = 0;
        break;
      case AnimationType.SLIDE_IN_DOWN:
        this.translateY = 100;
        this.componentOpacity = 0;
        break;
      case AnimationType.SCALE_IN:
        this.scaleX = 0;
        this.scaleY = 0;
        this.componentOpacity = 0;
        break;
      case AnimationType.SCALE_OUT:
        this.scaleX = 1;
        this.scaleY = 1;
        this.componentOpacity = 1;
        break;
      case AnimationType.ROTATE_IN:
        this.rotateAngle = -180;
        this.componentOpacity = 0;
        break;
      case AnimationType.ROTATE_OUT:
        this.rotateAngle = 0;
        this.componentOpacity = 1;
        break;
    }
  }

  /**
   * 设置目标状态
   */
  private setTargetState(): void {
    switch (this.animationType) {
      case AnimationType.FADE_IN:
        this.componentOpacity = 1;
        break;
      case AnimationType.FADE_OUT:
        this.componentOpacity = 0;
        break;
      case AnimationType.SLIDE_IN_LEFT:
      case AnimationType.SLIDE_IN_RIGHT:
        this.translateX = 0;
        this.componentOpacity = 1;
        break;
      case AnimationType.SLIDE_IN_UP:
      case AnimationType.SLIDE_IN_DOWN:
        this.translateY = 0;
        this.componentOpacity = 1;
        break;
      case AnimationType.SCALE_IN:
        this.scaleX = 1;
        this.scaleY = 1;
        this.componentOpacity = 1;
        break;
      case AnimationType.SCALE_OUT:
        this.scaleX = 0;
        this.scaleY = 0;
        this.componentOpacity = 0;
        break;
      case AnimationType.ROTATE_IN:
        this.rotateAngle = 0;
        this.componentOpacity = 1;
        break;
      case AnimationType.ROTATE_OUT:
        this.rotateAngle = 180;
        this.componentOpacity = 0;
        break;
    }
  }

  /**
   * 从缓动类型获取曲线
   */
  private getCurveFromEasing(easing?: string): Curve {
    switch (easing) {
      case 'ease-in':
        return Curve.EaseIn;
      case 'ease-out':
        return Curve.EaseOut;
      case 'ease-in-out':
        return Curve.EaseInOut;
      case 'linear':
        return Curve.Linear;
      case 'fast-out-slow-in':
        return Curve.FastOutSlowIn;
      case 'fast-out-linear-in':
        return Curve.FastOutLinearIn;
      case 'linear-out-slow-in':
        return Curve.LinearOutSlowIn;
      case 'friction':
        return Curve.Friction;
      case 'extreme-deceleration':
        return Curve.ExtremeDeceleration;
      case 'sharp':
        return Curve.Sharp;
      case 'rhythm':
        return Curve.Rhythm;
      case 'smooth':
        return Curve.Smooth;
      default:
        return Curve.EaseInOut;
    }
  }

  /**
   * 将方向转换为ArkUI播放模式
   */
  private getPlayModeFromDirection(direction?: string): PlayMode {
    switch (direction) {
      case 'reverse':
        return PlayMode.Reverse;
      case 'alternate':
        return PlayMode.Alternate;
      case 'alternate-reverse':
        return PlayMode.AlternateReverse;
      default:
        return PlayMode.Normal;
    }
  }

  /**
   * 公共方法：播放动画
   */
  public playAnimationManually(): void {
    this.setInitialState();
    this.playAnimation();
  }
  
  /**
   * 公共方法：暂停动画
   */
  public pauseAnimation(): void {
    globalAnimationManager.pauseAnimation(this.animationId);
  }
  
  /**
   * 公共方法：恢复动画
   */
  public resumeAnimation(): void {
    globalAnimationManager.resumeAnimation(this.animationId);
  }
  
  /**
   * 公共方法：停止动画
   */
  public stopAnimation(): void {
    globalAnimationManager.stopAnimation(this.animationId);
  }
  
  /**
   * 公共方法：获取动画状态
   */
  public getAnimationStatus(): AnimationStatus {
    const status: AnimationStatus = {
      isActive: globalAnimationManager.getActiveAnimations().get(this.animationId)?.isPlaying || false,
      animationId: this.animationId,
      currentType: this.animationType.toString()
    };
    return status;
  }

  /**
   * 公共方法：重置动画
   */
  public resetAnimation(): void {
    this.stopAnimation();
    this.setInitialState();
    if (this.autoPlay) {
      this.playAnimation();
    }
    
    logger.debug(TAG, '动画已重置');
  }

  build() {
    Column() {
      this.content();
    }
    .opacity(this.componentOpacity)
    .translate({ x: this.translateX, y: this.translateY })
    .scale({ x: this.scaleX, y: this.scaleY })
    .rotate({ angle: this.rotateAngle })
    .enabled(this.isEnabled)
  }
}

// 导出动画类型，方便外部使用
export { AnimationType };