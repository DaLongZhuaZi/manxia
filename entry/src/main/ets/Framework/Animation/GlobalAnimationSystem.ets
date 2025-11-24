// 文件路径: src/main/ets/Framework/Animation/GlobalAnimationSystem.ets
/**
 * 全局动画系统
 * 提供独立可调用的各种动画组件和工具，支持传统动画系统
 */

import { logger } from '../../Utils/Logger';
import { UIContext } from '@kit.ArkUI';

const TAG = 'GlobalAnimationSystem';

/**
 * 动画统计信息接口
 */
export interface AnimationStats {
  activeAnimations: number;
  registeredAnimations: number;
}

/**
 * RGB颜色值接口
 */
export interface RGBColor {
  r: number;
  g: number;
  b: number;
}

/**
 * 2D向量接口
 */
export interface Vector2D {
  x: number;
  y: number;
}

/**
 * 3D向量接口
 */
export interface Vector3D {
  x: number;
  y: number;
  z: number;
}

/**
 * 动画类型枚举 - 保持向后兼容
 */
export enum AnimationType {
  FADE_IN = 'fadeIn',
  FADE_OUT = 'fadeOut',
  SLIDE_IN_LEFT = 'slideInLeft',
  SLIDE_IN_RIGHT = 'slideInRight',
  SLIDE_IN_UP = 'slideInUp',
  SLIDE_IN_DOWN = 'slideInDown',
  SLIDE_OUT_LEFT = 'slideOutLeft',
  SLIDE_OUT_RIGHT = 'slideOutRight',
  SLIDE_OUT_UP = 'slideOutUp',
  SLIDE_OUT_DOWN = 'slideOutDown',
  SCALE_IN = 'scaleIn',
  SCALE_OUT = 'scaleOut',
  BOUNCE_IN = 'bounceIn',
  BOUNCE_OUT = 'bounceOut',
  ROTATE_IN = 'rotateIn',
  ROTATE_OUT = 'rotateOut',
  FLIP_IN_X = 'flipInX',
  FLIP_IN_Y = 'flipInY',
  ZOOM_IN = 'zoomIn',
  ZOOM_OUT = 'zoomOut',
  // 新增动画类型
  PULSE = 'pulse',
  SHAKE = 'shake',
  HEART_BEAT = 'heartBeat',
  RUBBER_BAND = 'rubberBand',
  WOBBLE = 'wobble',
  JELLO = 'jello',
  FLASH = 'flash',
  SWING = 'swing'
}

/**
 * 动画缓动类型 - 保持向后兼容
 */
export enum AnimationEasing {
  LINEAR = 'linear',
  EASE = 'ease',
  EASE_IN = 'ease-in',
  EASE_OUT = 'ease-out',
  EASE_IN_OUT = 'ease-in-out',
  CUBIC_BEZIER = 'cubic-bezier',
  SPRING = 'spring',
  FRICTION = 'friction',
  // 新增缓动类型
  EASE_IN_SINE = 'ease-in-sine',
  EASE_OUT_SINE = 'ease-out-sine',
  EASE_IN_OUT_SINE = 'ease-in-out-sine',
  EASE_IN_QUAD = 'ease-in-quad',
  EASE_OUT_QUAD = 'ease-out-quad',
  EASE_IN_OUT_QUAD = 'ease-in-out-quad',
  EASE_IN_CUBIC = 'ease-in-cubic',
  EASE_OUT_CUBIC = 'ease-out-cubic',
  EASE_IN_OUT_CUBIC = 'ease-in-out-cubic',
  EASE_IN_BACK = 'ease-in-back',
  EASE_OUT_BACK = 'ease-out-back',
  EASE_IN_OUT_BACK = 'ease-in-out-back',
  EASE_IN_BOUNCE = 'ease-in-bounce',
  EASE_OUT_BOUNCE = 'ease-out-bounce',
  EASE_IN_OUT_BOUNCE = 'ease-in-out-bounce'
}

/**
 * 动画配置接口 - 保持向后兼容
 */
export interface AnimationConfig {
  type: AnimationType;
  duration?: number;
  delay?: number;
  easing?: AnimationEasing;
  iterations?: number;
  direction?: 'normal' | 'reverse' | 'alternate' | 'alternate-reverse';
  fillMode?: 'none' | 'forwards' | 'backwards' | 'both';
  playState?: 'running' | 'paused';
  // 新增属性
  autoPlay?: boolean;
  loop?: boolean;
  yoyo?: boolean;
  startValue?: number;
  endValue?: number;
}

/**
 * 动画状态接口 - 保持向后兼容
 */
export interface AnimationState {
  isPlaying: boolean;
  isCompleted: boolean;
  currentIteration: number;
  progress: number;
  // 新增状态
  isPaused?: boolean;
  startTime?: number;
  pausedTime?: number;
  totalDuration?: number;
  // AnimationManager兼容属性
  opacity?: number;
  translateX?: number;
  translateY?: number;
  scaleX?: number;
  scaleY?: number;
  rotate?: number;
}

/**
 * 动画回调接口 - 保持向后兼容
 */
export interface AnimationCallbacks {
  onStart?: () => void;
  onUpdate?: (progress: number) => void;
  onComplete?: () => void;
  onCancel?: () => void;
  // 新增回调
  onPause?: () => void;
  onResume?: () => void;
  onRepeat?: (iteration: number) => void;
}

/**
 * 全局动画管理器
 */
export class GlobalAnimationManager {
  private static instance: GlobalAnimationManager | undefined;
  private animationRegistry: Map<string, AnimationConfig> = new Map();
  private activeAnimations: Map<string, AnimationState> = new Map();
  private animationCallbacks: Map<string, AnimationCallbacks> = new Map();
  private isInitialized: boolean = false;
  private uiContext: UIContext | null = null;

  private constructor() {
    this.initializeDefaultAnimations();
    this.isInitialized = true;
    logger.info(TAG, '全局动画管理器初始化完成');
  }

  public static getInstance(): GlobalAnimationManager {
    if (!GlobalAnimationManager.instance) {
      GlobalAnimationManager.instance = new GlobalAnimationManager();
    }
    return GlobalAnimationManager.instance;
  }

  /**
   * 设置UI上下文
   */
  public setUIContext(uiContext: UIContext): void {
    this.uiContext = uiContext;
    logger.debug(TAG, 'UI上下文已设置');
  }

  /**
   * 检查是否已初始化
   */
  public isReady(): boolean {
    return this.isInitialized;
  }

  /**
   * 初始化默认动画配置
   */
  private initializeDefaultAnimations(): void {
    // 淡入淡出动画
    this.registerAnimation('fadeIn', {
      type: AnimationType.FADE_IN,
      duration: 300,
      easing: AnimationEasing.EASE_OUT
    });

    this.registerAnimation('fadeOut', {
      type: AnimationType.FADE_OUT,
      duration: 300,
      easing: AnimationEasing.EASE_IN
    });

    // 滑动动画
    this.registerAnimation('slideInLeft', {
      type: AnimationType.SLIDE_IN_LEFT,
      duration: 400,
      easing: AnimationEasing.EASE_OUT
    });

    this.registerAnimation('slideInRight', {
      type: AnimationType.SLIDE_IN_RIGHT,
      duration: 400,
      easing: AnimationEasing.EASE_OUT
    });

    this.registerAnimation('slideInUp', {
      type: AnimationType.SLIDE_IN_UP,
      duration: 400,
      easing: AnimationEasing.EASE_OUT
    });

    this.registerAnimation('slideInDown', {
      type: AnimationType.SLIDE_IN_DOWN,
      duration: 400,
      easing: AnimationEasing.EASE_OUT
    });

    // 缩放动画
    this.registerAnimation('scaleIn', {
      type: AnimationType.SCALE_IN,
      duration: 300,
      easing: AnimationEasing.EASE_OUT
    });

    this.registerAnimation('scaleOut', {
      type: AnimationType.SCALE_OUT,
      duration: 300,
      easing: AnimationEasing.EASE_IN
    });

    // 弹跳动画
    this.registerAnimation('bounceIn', {
      type: AnimationType.BOUNCE_IN,
      duration: 600,
      easing: AnimationEasing.EASE_OUT
    });

    // 旋转动画
    this.registerAnimation('rotateIn', {
      type: AnimationType.ROTATE_IN,
      duration: 500,
      easing: AnimationEasing.EASE_OUT
    });

    // 翻转动画
    this.registerAnimation('flipInX', {
      type: AnimationType.FLIP_IN_X,
      duration: 600,
      easing: AnimationEasing.EASE_OUT
    });

    this.registerAnimation('flipInY', {
      type: AnimationType.FLIP_IN_Y,
      duration: 600,
      easing: AnimationEasing.EASE_OUT
    });

    // 缩放动画
    this.registerAnimation('zoomIn', {
      type: AnimationType.ZOOM_IN,
      duration: 300,
      easing: AnimationEasing.EASE_OUT
    });

    // 新增动画类型
    this.registerAnimation('pulse', {
      type: AnimationType.PULSE,
      duration: 1000,
      easing: AnimationEasing.EASE_IN_OUT,
      iterations: -1,
      loop: true
    });

    this.registerAnimation('shake', {
      type: AnimationType.SHAKE,
      duration: 500,
      easing: AnimationEasing.EASE_IN_OUT
    });

    this.registerAnimation('heartBeat', {
      type: AnimationType.HEART_BEAT,
      duration: 1300,
      easing: AnimationEasing.EASE_IN_OUT,
      iterations: -1,
      loop: true
    });

    this.registerAnimation('rubberBand', {
      type: AnimationType.RUBBER_BAND,
      duration: 1000,
      easing: AnimationEasing.EASE_OUT
    });

    this.registerAnimation('wobble', {
      type: AnimationType.WOBBLE,
      duration: 1000,
      easing: AnimationEasing.EASE_IN_OUT
    });

    this.registerAnimation('jello', {
      type: AnimationType.JELLO,
      duration: 1000,
      easing: AnimationEasing.EASE_IN_OUT
    });

    this.registerAnimation('flash', {
      type: AnimationType.FLASH,
      duration: 1000,
      easing: AnimationEasing.EASE_IN_OUT,
      iterations: 3
    });

    this.registerAnimation('swing', {
      type: AnimationType.SWING,
      duration: 1000,
      easing: AnimationEasing.EASE_IN_OUT
    });

    logger.info(TAG, '✅ 默认动画配置初始化完成，包含新增动画类型');
  }

  /**
   * 播放动画（兼容AnimationManager接口）
   */
  public playAnimation(
    animationType: AnimationType,
    targetState: AnimationState,
    config: AnimationConfig = { type: AnimationType.FADE_IN },
    animationId?: string
  ): Promise<void> {
    return new Promise((resolve, reject) => {
      try {
        const finalConfig: AnimationConfig = {
          type: animationType,
          duration: config.duration !== undefined ? config.duration : 300,
          easing: config.easing !== undefined ? config.easing : AnimationEasing.EASE_OUT,
          delay: config.delay !== undefined ? config.delay : 0,
          iterations: config.iterations !== undefined ? config.iterations : 1
        };
        const id = animationId || `${animationType}_${Date.now()}`;

        // 创建动画状态
        this.createAnimationState(id);
        const state = this.activeAnimations.get(id);
        if (state) {
          state.isPlaying = true;
        }

        logger.debug(TAG, `开始播放动画: ${animationType}, ID: ${id}`);

        // 使用UI上下文执行动画
        if (this.uiContext) {
          const animateOptions: AnimateParam = {
            duration: finalConfig.duration,
            delay: finalConfig.delay,
            curve: this.convertEasingToCurve(finalConfig.easing),
            iterations: finalConfig.iterations,
            onFinish: () => {
              this.removeAnimationState(id);
              logger.debug(TAG, `动画完成: ${animationType}, ID: ${id}`);
              resolve();
            }
          };

          this.uiContext.animateTo(animateOptions, () => {
            logger.debug(TAG, `应用动画状态: ${JSON.stringify(targetState)}`);
          });
        } else {
          logger.warn(TAG, 'UI上下文未设置，无法执行动画');
          reject(new Error('UI上下文未设置，无法执行动画'));
        }
      } catch (error) {
        logger.error(TAG, `动画播放失败: ${animationType}`, error);
        reject(error);
      }
    });
  }

  /**
   * 简化的动画方法（兼容AnimationManager接口）
   */
  public animate(
    animationType: AnimationType,
    stateCallback: (state: AnimationState) => void,
    config: AnimationConfig = { type: AnimationType.FADE_IN },
    uiContext?: UIContext
  ): void {
    try {
      const targetState = this.getTargetStateForAnimationType(animationType);
      
      // 如果提供了UI上下文，使用它；否则使用实例的UI上下文
      const contextToUse = uiContext || this.uiContext;
      
      if (contextToUse) {
        const animateOptions: AnimateParam = {
          duration: config.duration || 300,
          curve: this.convertEasingToCurve(config.easing || AnimationEasing.EASE_OUT),
          delay: config.delay || 0
        };

        contextToUse.animateTo(animateOptions, () => {
          stateCallback(targetState);
        });
      } else {
        logger.warn(TAG, 'UI上下文未设置，直接执行状态回调');
        stateCallback(targetState);
      }
    } catch (error) {
      logger.error(TAG, `animate方法执行失败: ${animationType}`, error);
    }
  }

  /**
   * 根据动画类型获取目标状态
   */
  private getTargetStateForAnimationType(animationType: AnimationType): AnimationState {
    switch (animationType) {
      case AnimationType.FADE_IN:
        return this.createFadeInState();
      case AnimationType.FADE_OUT:
        return this.createFadeOutState();
      case AnimationType.SLIDE_IN_LEFT:
        return this.createSlideInState('left');
      case AnimationType.SLIDE_IN_RIGHT:
        return this.createSlideInState('right');
      case AnimationType.SLIDE_IN_UP:
        return this.createSlideInState('up');
      case AnimationType.SLIDE_IN_DOWN:
        return this.createSlideInState('down');
      case AnimationType.SLIDE_OUT_LEFT:
        return this.createSlideOutState('left');
      case AnimationType.SLIDE_OUT_RIGHT:
        return this.createSlideOutState('right');
      case AnimationType.SLIDE_OUT_UP:
        return this.createSlideOutState('up');
      case AnimationType.SLIDE_OUT_DOWN:
        return this.createSlideOutState('down');
      case AnimationType.SCALE_IN:
        return this.createScaleState(1);
      case AnimationType.SCALE_OUT:
        return this.createScaleState(0);
      case AnimationType.ROTATE_IN:
        return this.createRotateState(0);
      case AnimationType.ROTATE_OUT:
        return this.createRotateState(180);
      default:
        return {
          isPlaying: false,
          isCompleted: false,
          currentIteration: 0,
          progress: 0
        };
    }
  }

  /**
   * 创建淡入动画状态
   */
  public createFadeInState(): AnimationState {
    return {
      isPlaying: false,
      isCompleted: false,
      currentIteration: 0,
      progress: 0,
      opacity: 1
    };
  }

  /**
   * 创建淡出动画状态
   */
  public createFadeOutState(): AnimationState {
    return {
      isPlaying: false,
      isCompleted: false,
      currentIteration: 0,
      progress: 0,
      opacity: 0
    };
  }

  /**
   * 创建滑入动画状态
   */
  public createSlideInState(direction: 'left' | 'right' | 'up' | 'down'): AnimationState {
    switch (direction) {
      case 'left':
        return {
          isPlaying: false,
          isCompleted: false,
          currentIteration: 0,
          progress: 0,
          translateX: 0
        };
      case 'right':
        return {
          isPlaying: false,
          isCompleted: false,
          currentIteration: 0,
          progress: 0,
          translateX: 0
        };
      case 'up':
        return {
          isPlaying: false,
          isCompleted: false,
          currentIteration: 0,
          progress: 0,
          translateY: 0
        };
      case 'down':
        return {
          isPlaying: false,
          isCompleted: false,
          currentIteration: 0,
          progress: 0,
          translateY: 0
        };
      default:
        return {
          isPlaying: false,
          isCompleted: false,
          currentIteration: 0,
          progress: 0
        };
    }
  }

  /**
   * 创建滑出动画状态
   */
  public createSlideOutState(direction: 'left' | 'right' | 'up' | 'down'): AnimationState {
    switch (direction) {
      case 'left':
        return {
          isPlaying: false,
          isCompleted: false,
          currentIteration: 0,
          progress: 0,
          translateX: -100
        };
      case 'right':
        return {
          isPlaying: false,
          isCompleted: false,
          currentIteration: 0,
          progress: 0,
          translateX: 100
        };
      case 'up':
        return {
          isPlaying: false,
          isCompleted: false,
          currentIteration: 0,
          progress: 0,
          translateY: -100
        };
      case 'down':
        return {
          isPlaying: false,
          isCompleted: false,
          currentIteration: 0,
          progress: 0,
          translateY: 100
        };
      default:
        return {
          isPlaying: false,
          isCompleted: false,
          currentIteration: 0,
          progress: 0
        };
    }
  }

  /**
   * 创建缩放动画状态
   */
  public createScaleState(scale: number): AnimationState {
    return {
      isPlaying: false,
      isCompleted: false,
      currentIteration: 0,
      progress: 0,
      scaleX: scale,
      scaleY: scale
    };
  }

  /**
   * 创建旋转动画状态
   */
  public createRotateState(angle: number): AnimationState {
    return {
      isPlaying: false,
      isCompleted: false,
      currentIteration: 0,
      progress: 0,
      rotate: angle
    };
  }

  /**
   * 转换缓动类型到曲线
   */
  private convertEasingToCurve(easing?: AnimationEasing): Curve {
    if (!easing) return Curve.EaseOut;
    
    switch (easing) {
      case AnimationEasing.LINEAR:
        return Curve.Linear;
      case AnimationEasing.EASE:
        return Curve.Ease;
      case AnimationEasing.EASE_IN:
        return Curve.EaseIn;
      case AnimationEasing.EASE_OUT:
        return Curve.EaseOut;
      case AnimationEasing.EASE_IN_OUT:
        return Curve.EaseInOut;
      default:
        return Curve.EaseOut;
    }
  }

  /**
   * 获取活跃动画数量
   */
  public getActiveAnimationCount(): number {
    return this.activeAnimations.size;
  }

  /**
   * 检查动画是否正在播放
   */
  public isAnimationPlaying(animationId: string): boolean {
    const state = this.activeAnimations.get(animationId);
    return state ? state.isPlaying : false;
  }

  /**
   * 停止指定动画
   */
  public stopAnimation(animationId: string): void {
    const state = this.activeAnimations.get(animationId);
    if (state) {
      state.isPlaying = false;
      state.isCompleted = true;
      this.triggerCallback(animationId, 'cancel');
      this.removeAnimationState(animationId);

      logger.debug(TAG, `停止动画: ${animationId}`);
    }
  }

  /**
   * 停止所有动画
   */
  public stopAllAnimations(): void {
    this.activeAnimations.clear();
    this.animationCallbacks.clear();
    logger.debug(TAG, '停止所有动画');
  }

  /**
   * 获取预定义动画配置
   */
  public getPresetConfig(preset: 'fast' | 'normal' | 'slow' | 'bounce'): AnimationConfig {
    switch (preset) {
      case 'fast':
        return { type: AnimationType.FADE_IN, duration: 150, easing: AnimationEasing.EASE_OUT };
      case 'normal':
        return { type: AnimationType.FADE_IN, duration: 300, easing: AnimationEasing.EASE_IN_OUT };
      case 'slow':
        return { type: AnimationType.FADE_IN, duration: 600, easing: AnimationEasing.EASE_IN_OUT };
      case 'bounce':
        return { type: AnimationType.FADE_IN, duration: 400, easing: AnimationEasing.EASE_OUT_BOUNCE };
      default:
        return { type: AnimationType.FADE_IN, duration: 300, easing: AnimationEasing.EASE_OUT };
    }
  }

  /**
   * 清理资源
   */
  public destroy(): void {
    this.stopAllAnimations();
    this.uiContext = null;
    GlobalAnimationManager.instance = undefined;
    logger.info(TAG, '全局动画管理器已销毁');
  }
  public registerAnimation(name: string, config: AnimationConfig): void {
    this.animationRegistry.set(name, config);
    logger.debug(TAG, `注册动画: ${name}`);
  }

  /**
   * 获取动画配置
   */
  public getAnimationConfig(name: string): AnimationConfig | undefined {
    return this.animationRegistry.get(name);
  }



  /**
   * 注册动画回调
   */
  public registerCallbacks(animationId: string, callbacks: AnimationCallbacks): void {
    this.animationCallbacks.set(animationId, callbacks);
  }

  /**
   * 获取动画回调
   */
  public getCallbacks(animationId: string): AnimationCallbacks | undefined {
    return this.animationCallbacks.get(animationId);
  }

  /**
   * 触发动画回调
   */
  public triggerCallback(animationId: string, event: 'start' | 'update' | 'complete' | 'cancel' | 'pause' | 'resume' | 'repeat', data?: number | string | boolean): void {
    const callbacks = this.animationCallbacks.get(animationId);
    if (!callbacks) return;

    try {
      switch (event) {
        case 'start':
          callbacks.onStart?.();
          break;
        case 'update':
          callbacks.onUpdate?.(data as number);
          break;
        case 'complete':
          callbacks.onComplete?.();
          break;
        case 'cancel':
          callbacks.onCancel?.();
          break;
        case 'pause':
          callbacks.onPause?.();
          break;
        case 'resume':
          callbacks.onResume?.();
          break;
        case 'repeat':
          callbacks.onRepeat?.(data as number);
          break;
      }
    } catch (error) {
      logger.error(TAG, `动画回调执行失败: ${animationId}, 事件: ${event}`, error);
    }
  }

  /**
   * 创建动画状态
   */
  public createAnimationState(animationId: string): AnimationState {
    const state: AnimationState = {
      isPlaying: false,
      isCompleted: false,
      currentIteration: 0,
      progress: 0
    };
    this.activeAnimations.set(animationId, state);
    return state;
  }

  /**
   * 更新动画状态
   */
  public updateAnimationState(animationId: string, updates: Partial<AnimationState>): void {
    const state = this.activeAnimations.get(animationId);
    if (state) {
      // 手动复制更新对象的属性到状态对象
      if (updates.isPlaying !== undefined) {
        state.isPlaying = updates.isPlaying;
      }
      if (updates.isCompleted !== undefined) {
        state.isCompleted = updates.isCompleted;
      }
      if (updates.currentIteration !== undefined) {
        state.currentIteration = updates.currentIteration;
      }
      if (updates.progress !== undefined) {
        state.progress = updates.progress;
      }
    }
  }

  /**
   * 移除动画状态
   */
  public removeAnimationState(animationId: string): void {
    this.activeAnimations.delete(animationId);
  }

  /**
   * 获取所有活跃动画
   */
  public getActiveAnimations(): Map<string, AnimationState> {
    return new Map(this.activeAnimations);
  }

  /**
   * 暂停动画
   */
  public pauseAnimation(animationId: string): void {
    const state = this.activeAnimations.get(animationId);
    if (state && state.isPlaying) {
      state.isPaused = true;
      state.isPlaying = false;
      state.pausedTime = Date.now();
      this.triggerCallback(animationId, 'pause');
      logger.debug(TAG, `暂停动画: ${animationId}`);
    }
  }

  /**
   * 恢复动画
   */
  public resumeAnimation(animationId: string): void {
    const state = this.activeAnimations.get(animationId);
    if (state && state.isPaused) {
      state.isPaused = false;
      state.isPlaying = true;
      if (state.pausedTime && state.startTime) {
        state.startTime += Date.now() - state.pausedTime;
      }
      state.pausedTime = undefined;
      this.triggerCallback(animationId, 'resume');
      logger.debug(TAG, `恢复动画: ${animationId}`);
    }
  }

  /**
   * 清理所有动画状态
   */
  public clearAllAnimations(): void {
    this.activeAnimations.clear();
    this.animationCallbacks.clear();

    logger.info(TAG, '清理所有动画状态');
  }

  /**
   * 获取统计信息
   */
  public getStats(): AnimationStats {
    return {
      activeAnimations: this.activeAnimations.size,
      registeredAnimations: this.animationRegistry.size
    } as AnimationStats;
  }
}

/**
 * 动画工具函数
 */
export class AnimationUtils {
  /**
   * 生成唯一动画ID
   */
  public static generateAnimationId(): string {
    return `anim_${Date.now()}_${Math.random().toString(36).substring(2, 11)}`;
  }

  /**
   * 计算动画进度
   */
  public static calculateProgress(startTime: number, duration: number): number {
    const elapsed = Date.now() - startTime;
    return Math.min(elapsed / duration, 1);
  }

  /**
   * 应用缓动函数
   */
  public static applyEasing(progress: number, easing: AnimationEasing): number {
    switch (easing) {
      case AnimationEasing.LINEAR:
        return progress;
      case AnimationEasing.EASE:
        return AnimationUtils.easeInOut(progress);
      case AnimationEasing.EASE_IN:
        return progress * progress;
      case AnimationEasing.EASE_OUT:
        return 1 - Math.pow(1 - progress, 2);
      case AnimationEasing.EASE_IN_OUT:
        return progress < 0.5 
          ? 2 * progress * progress 
          : 1 - Math.pow(-2 * progress + 2, 2) / 2;
      case AnimationEasing.EASE_IN_SINE:
        return 1 - Math.cos((progress * Math.PI) / 2);
      case AnimationEasing.EASE_OUT_SINE:
        return Math.sin((progress * Math.PI) / 2);
      case AnimationEasing.EASE_IN_OUT_SINE:
        return -(Math.cos(Math.PI * progress) - 1) / 2;
      case AnimationEasing.EASE_IN_QUAD:
        return progress * progress;
      case AnimationEasing.EASE_OUT_QUAD:
        return 1 - (1 - progress) * (1 - progress);
      case AnimationEasing.EASE_IN_OUT_QUAD:
        return progress < 0.5 ? 2 * progress * progress : 1 - Math.pow(-2 * progress + 2, 2) / 2;
      case AnimationEasing.EASE_IN_CUBIC:
        return progress * progress * progress;
      case AnimationEasing.EASE_OUT_CUBIC:
        return 1 - Math.pow(1 - progress, 3);
      case AnimationEasing.EASE_IN_OUT_CUBIC:
        return progress < 0.5 ? 4 * progress * progress * progress : 1 - Math.pow(-2 * progress + 2, 3) / 2;
      case AnimationEasing.EASE_IN_BACK:
        return AnimationUtils.easeInBack(progress);
      case AnimationEasing.EASE_OUT_BACK:
        return AnimationUtils.easeOutBack(progress);
      case AnimationEasing.EASE_IN_OUT_BACK:
        return AnimationUtils.easeInOutBack(progress);
      case AnimationEasing.EASE_IN_BOUNCE:
        return 1 - AnimationUtils.easeOutBounce(1 - progress);
      case AnimationEasing.EASE_OUT_BOUNCE:
        return AnimationUtils.easeOutBounce(progress);
      case AnimationEasing.EASE_IN_OUT_BOUNCE:
        return progress < 0.5 ? (1 - AnimationUtils.easeOutBounce(1 - 2 * progress)) / 2 : (1 + AnimationUtils.easeOutBounce(2 * progress - 1)) / 2;
      case AnimationEasing.SPRING:
        return AnimationUtils.easeSpring(progress);
      case AnimationEasing.FRICTION:
        return AnimationUtils.easeFriction(progress);
      default:
        return progress;
    }
  }

  /**
   * 插值计算
   */
  public static interpolate(start: number, end: number, progress: number): number {
    return start + (end - start) * progress;
  }

  /**
   * 缓入缓出
   */
  private static easeInOut(t: number): number {
    return t < 0.5 ? 2 * t * t : -1 + (4 - 2 * t) * t;
  }

  /**
   * 回弹缓入
   */
  private static easeInBack(t: number): number {
    const c1 = 1.70158;
    const c3 = c1 + 1;
    return c3 * t * t * t - c1 * t * t;
  }

  /**
   * 回弹缓出
   */
  private static easeOutBack(t: number): number {
    const c1 = 1.70158;
    const c3 = c1 + 1;
    return 1 + c3 * Math.pow(t - 1, 3) + c1 * Math.pow(t - 1, 2);
  }

  /**
   * 回弹缓入缓出
   */
  private static easeInOutBack(t: number): number {
    const c1 = 1.70158;
    const c2 = c1 * 1.525;
    return t < 0.5
      ? (Math.pow(2 * t, 2) * ((c2 + 1) * 2 * t - c2)) / 2
      : (Math.pow(2 * t - 2, 2) * ((c2 + 1) * (t * 2 - 2) + c2) + 2) / 2;
  }

  /**
   * 弹跳缓出
   */
  private static easeOutBounce(t: number): number {
    const n1 = 7.5625;
    const d1 = 2.75;
    if (t < 1 / d1) {
      return n1 * t * t;
    } else if (t < 2 / d1) {
      return n1 * (t -= 1.5 / d1) * t + 0.75;
    } else if (t < 2.5 / d1) {
      return n1 * (t -= 2.25 / d1) * t + 0.9375;
    } else {
      return n1 * (t -= 2.625 / d1) * t + 0.984375;
    }
  }

  /**
   * 弹簧缓动
   */
  private static easeSpring(t: number): number {
    return 1 - Math.exp(-6 * t) * Math.cos(10 * t);
  }

  /**
   * 摩擦缓动
   */
  private static easeFriction(t: number): number {
    return 1 - Math.exp(-8 * t);
  }

  /**
   * 颜色插值
   */
  public static interpolateColor(startColor: string, endColor: string, progress: number): string {
    // 简化的颜色插值实现
    const start = AnimationUtils.hexToRgb(startColor);
    const end = AnimationUtils.hexToRgb(endColor);
    if (!start || !end) return startColor;
    
    const r = Math.round(AnimationUtils.interpolate(start.r, end.r, progress));
    const g = Math.round(AnimationUtils.interpolate(start.g, end.g, progress));
    const b = Math.round(AnimationUtils.interpolate(start.b, end.b, progress));
    
    return `rgb(${r}, ${g}, ${b})`;
  }

  /**
   * 十六进制颜色转RGB
   */
  private static hexToRgb(hex: string): RGBColor | null {
    const result = /^#?([a-f\d]{2})([a-f\d]{2})([a-f\d]{2})$/i.exec(hex);
    return result ? {
      r: parseInt(result[1], 16),
      g: parseInt(result[2], 16),
      b: parseInt(result[3], 16)
    } as RGBColor : null;
  }

  /**
   * 向量插值
   */
  public static interpolateVector2D(start: Vector2D, end: Vector2D, progress: number): Vector2D {
    return {
      x: AnimationUtils.interpolate(start.x, end.x, progress),
      y: AnimationUtils.interpolate(start.y, end.y, progress)
    } as Vector2D;
  }

  /**
   * 3D向量插值
   */
  public static interpolateVector3D(start: Vector3D, end: Vector3D, progress: number): Vector3D {
    return {
      x: AnimationUtils.interpolate(start.x, end.x, progress),
      y: AnimationUtils.interpolate(start.y, end.y, progress),
      z: AnimationUtils.interpolate(start.z, end.z, progress)
    } as Vector3D;
  }

  /**
   * 贝塞尔曲线插值
   */
  public static bezierInterpolate(t: number, p0: number, p1: number, p2: number, p3: number): number {
    const u = 1 - t;
    const tt = t * t;
    const uu = u * u;
    const uuu = uu * u;
    const ttt = tt * t;
    
    return uuu * p0 + 3 * uu * t * p1 + 3 * u * tt * p2 + ttt * p3;
  }
}

// 导出全局动画管理器实例
export const globalAnimationManager = GlobalAnimationManager.getInstance();

// 导出兼容的animationManager别名
export const animationManager = globalAnimationManager;