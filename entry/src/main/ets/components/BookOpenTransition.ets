/**
 * 书籍翻开/关闭过渡动画组件
 * 
 * 核心特性：
 * 1. 翻开模式 - 封面从原位置移动到中央，等待阅读器就绪后执行掀开动画
 * 2. 关闭模式 - 阅读器内容缩小并缩回到封面位置，自然淡出消失
 * 3. 基于Canvas的3D渲染效果
 * 4. 支持漫画阅读器和电子书阅读器
 * 5. 平滑的状态过渡和回调机制
 */

import { logger } from '../Utils/Logger';
import { image } from '@kit.ImageKit';
import { curves } from '@kit.ArkUI';
import { EBookBackgroundSettings } from './BookTransitionOverlay';

const TAG = 'BookOpenTransition';

/**
 * 过渡动画模式
 */
export enum TransitionMode {
  OPEN = 'open',   // 翻开模式
  CLOSE = 'close'  // 关闭模式
}

/**
 * 动画阶段枚举
 */
export enum TransitionPhase {
  IDLE = 'idle',                     // 空闲状态
  // 翻开模式阶段
  COVER_MOVING = 'cover_moving',     // 封面移动到中央
  WAITING_READY = 'waiting_ready',   // 等待阅读器就绪
  COVER_LIFTING = 'cover_lifting',   // 封面掀起
  TRANSITIONING = 'transitioning',   // 过渡到阅读器
  // 关闭模式阶段
  FADE_IN = 'fade_in',               // 截图淡入（无缝过渡）
  SHRINKING = 'shrinking',           // 阅读器内容缩小
  RETURNING = 'returning',           // 缩回到封面位置
  FADING = 'fading',                 // 淡出消失
  COMPLETED = 'completed'            // 动画完成
}

/**
 * 封面位置信息
 */
export interface CoverPosition {
  x: number;           // 左上角X坐标
  y: number;           // 左上角Y坐标
  width: number;       // 宽度
  height: number;      // 高度
}

/**
 * 过渡动画配置
 */
export interface BookTransitionConfig {
  // 动画时长配置（毫秒）
  coverMoveDuration: number;      // 封面移动到中央的时长
  liftDuration: number;           // 掀开动画时长
  transitionDuration: number;     // 过渡到阅读器时长
  shrinkDuration: number;         // 缩小动画时长
  returnDuration: number;         // 缩回封面时长
  fadeDuration: number;           // 淡出时长
  
  // 效果配置
  maxLiftAngle: number;           // 最大掀起角度（度）
  shadowIntensity: number;        // 阴影强度 (0-1)
  enableShadow: boolean;          // 是否启用阴影
  enable3DEffect: boolean;        // 是否启用3D效果
  
  // 缩放配置
  centerScale: number;            // 封面在中央时的缩放比例
  minShrinkScale: number;         // 关闭时最小缩放比例
}

/**
 * 默认配置
 */
const DEFAULT_CONFIG: BookTransitionConfig = {
  coverMoveDuration: 400,
  liftDuration: 400,
  transitionDuration: 300,
  shrinkDuration: 400,
  returnDuration: 350,
  fadeDuration: 200,
  maxLiftAngle: 45,  // 减少翻开角度，更自然
  shadowIntensity: 0.6,
  enableShadow: true,
  enable3DEffect: true,
  centerScale: 0.7,
  minShrinkScale: 0.15
};

/**
 * 过渡动画参数接口
 */
export interface BookTransitionParams {
  mode: TransitionMode;                    // 动画模式
  coverImagePath: string;                  // 封面图片路径
  coverPosition: CoverPosition;            // 封面原始位置
  readerContentPixelMap?: image.PixelMap;  // 阅读器内容截图（关闭模式用）
  config?: Partial<BookTransitionConfig>;  // 可选配置覆盖
  
  // 回调函数
  onReaderReady?: () => void;              // 阅读器就绪回调
  onAnimationComplete?: () => void;        // 动画完成回调
  onPhaseChange?: (phase: TransitionPhase) => void;  // 阶段变化回调
}

@Component
export struct BookOpenTransition {
  // ========== 外部参数 ==========
  @Prop mode: TransitionMode = TransitionMode.OPEN;
  @Prop coverImagePath: string = '';
  @Prop @Watch('onCoverPositionChange') coverPosition: CoverPosition = { x: 0, y: 0, width: 100, height: 150 };
  @Prop @Watch('onReaderPixelMapChange') readerContentPixelMap: image.PixelMap | null = null;
  @Prop readerContentImagePath: string = '';  // 压缩后的截图临时文件路径（推荐使用）
  @Prop config: BookTransitionConfig = DEFAULT_CONFIG;
  @Prop @Watch('onReaderReadyChange') isReaderReady: boolean = false;  // 阅读器是否就绪（外部控制）
  @Prop ebookBackground: EBookBackgroundSettings | null = null;  // 电子书背景设置
  
  // 回调函数
  onAnimationComplete: () => void = () => {};
  onPhaseChange: (phase: TransitionPhase) => void = () => {};
  
  // ========== 内部状态 ==========
  @State private currentPhase: TransitionPhase = TransitionPhase.IDLE;
  @State private animationProgress: number = 0;  // 当前阶段动画进度 0-1
  
  // 当前动画状态
  @State private currentX: number = 0;
  @State private currentY: number = 0;
  @State private currentWidth: number = 0;
  @State private currentHeight: number = 0;
  @State private currentScale: number = 1;
  @State private currentOpacity: number = 1;
  @State private liftAngle: number = 0;  // 掀起角度
  @State private shadowOpacity: number = 0;
  
  // 组件尺寸
  @State private componentWidth: number = 0;
  @State private componentHeight: number = 0;
  
  // 目标位置（中央）
  private centerX: number = 0;
  private centerY: number = 0;
  private centerWidth: number = 0;
  private centerHeight: number = 0;
  
  // Canvas渲染相关
  private canvasSettings: RenderingContextSettings = new RenderingContextSettings(true);
  private canvasContext: CanvasRenderingContext2D = new CanvasRenderingContext2D(this.canvasSettings);
  private coverPixelMap: image.PixelMap | null = null;
  private backgroundImagePixelMap: image.PixelMap | null = null;  // 背景图片（用于Canvas绘制）
  
  // 存储截图的本地副本（防止引用丢失）
  @State private localReaderPixelMap: image.PixelMap | null = null;
  
  // 动画控制
  private animationTimer: number = -1;
  @State private isAnimating: boolean = false;  // 改为@State以触发UI重新渲染
  private pendingAnimationStart: boolean = false;  // 等待尺寸后启动动画
  private animationStartTime: number = 0;
  private readerReadyCheckTimer: number = -1;  // 等待阅读器就绪的计时器
  private readerReadyTimeoutTimer: number = -1;  // 超时计时器
  @State private animationCompleted: boolean = false;  // 动画是否已完成
  
  // 取消动画控制
  @State private isCancelling: boolean = false;
  private cancelFadeStartTime: number = 0;
  private cancelFadeDuration: number = 200;  // 取消渐隐时长
  private cancelFadeTimer: number = -1;
  
  // 封面翻页效果状态（用于关闭动画的封面盖住效果）
  @State private coverFlipProgress: number = 0;  // 封面翻页进度 0-1（0=完全打开, 1=完全盖住）
  
  // 封面图片原始尺寸（用于保持宽高比）
  private coverOriginalWidth: number = 0;
  private coverOriginalHeight: number = 0;
  @State private isSystemResource: boolean = false;  // 是否为系统资源图片（网络图片或app.media资源）
  
  // ========== 生命周期 ==========
  aboutToAppear(): void {
    logger.info(TAG, `组件初始化，模式: ${this.mode}, ebookBackground=${this.ebookBackground ? `有(色=${this.ebookBackground.backgroundColor}, 图=${this.ebookBackground.backgroundImagePath || '无'})` : '无'}`);
    // 初始化当前位置为封面位置
    this.currentX = this.coverPosition.x;
    this.currentY = this.coverPosition.y;
    this.currentWidth = this.coverPosition.width;
    this.currentHeight = this.coverPosition.height;
    
    // 如果是关闭模式，保存PixelMap的本地引用
    if (this.mode === TransitionMode.CLOSE) {
      logger.info(TAG, `📷 关闭模式初始化: readerContentPixelMap=${this.readerContentPixelMap ? '有效' : '空'}`);
      if (this.readerContentPixelMap) {
        this.localReaderPixelMap = this.readerContentPixelMap;
        logger.info(TAG, `📷 已保存截图引用到本地状态 (aboutToAppear)`);
      } else {
        logger.warn(TAG, `📷 警告: 关闭模式但截图为空，等待@Watch更新`);
      }
    }
    
    // 加载封面图片
    this.loadCoverImage();
    
    // 加载背景图片（如果有）
    this.loadBackgroundImage();
  }
  
  /**
   * 加载背景图片（用于Canvas绘制）
   */
  private loadBackgroundImage(): void {
    if (!this.ebookBackground || !this.ebookBackground.backgroundImagePath || this.ebookBackground.backgroundImagePath.length === 0) {
      return;
    }
    
    const imagePath = this.ebookBackground.backgroundImagePath;
    logger.info(TAG, `加载背景图片: ${imagePath}`);
    
    try {
      const imageSource = image.createImageSource(imagePath);
      imageSource.createPixelMap().then((pixelMap: image.PixelMap) => {
        this.backgroundImagePixelMap = pixelMap;
        logger.info(TAG, '背景图片加载成功');
        // 重新渲染以显示背景图片
        this.renderFrame();
      }).catch((err: Error) => {
        logger.error(TAG, `背景图片加载失败: ${err.message}`);
      });
    } catch (error) {
      logger.error(TAG, `背景图片加载异常: ${error instanceof Error ? error.message : String(error)}`);
    }
  }
  
  aboutToDisappear(): void {
    logger.info(TAG, '组件销毁');
    this.stopAnimation();
    this.clearReaderReadyTimers();
    this.releaseCoverPixelMap();
    this.animationCompleted = true;  // 标记完成，防止任何残留计时器继续
  }
  
  // ========== 图片加载 ==========
  private async loadCoverImage(): Promise<void> {
    if (!this.coverImagePath || this.coverImagePath.length === 0) {
      logger.warn(TAG, '封面图片路径为空');
      // 关闭模式：需要等待isReaderReady为true（截图完成）后才能开始动画
      if (this.mode === TransitionMode.CLOSE) {
        if (this.isReaderReady && this.componentWidth > 0 && this.componentHeight > 0) {
          this.startTransition();
        } else {
          this.pendingAnimationStart = true;
          logger.info(TAG, `等待关闭动画条件就绪: isReaderReady=${this.isReaderReady}, size=${this.componentWidth}x${this.componentHeight}`);
        }
      }
      return;
    }
    
    // 检查是否为系统资源路径（app.media.xxx）
    if (this.coverImagePath.startsWith('app.media.')) {
      logger.info(TAG, `检测到系统资源路径: ${this.coverImagePath}，跳过PixelMap加载，使用默认封面尺寸`);
      // 系统资源无法通过createImageSource加载，设置默认封面尺寸比例
      this.coverOriginalWidth = 210;  // 默认封面宽度
      this.coverOriginalHeight = 300; // 默认封面高度（0.7比例）
      this.isSystemResource = true;
      // 直接开始动画，使用默认渐变效果
      if (this.componentWidth > 0 && this.componentHeight > 0) {
        this.startTransition();
      } else {
        this.pendingAnimationStart = true;
        logger.info(TAG, '等待组件尺寸就绪后启动动画');
      }
      return;
    }
    
    // 检查是否为网络图片（HTTP/HTTPS URL）
    if (this.coverImagePath.startsWith('http://') || this.coverImagePath.startsWith('https://')) {
      logger.info(TAG, `检测到网络图片: ${this.coverImagePath}，跳过PixelMap加载，使用默认封面尺寸`);
      // 网络图片无法直接通过createImageSource加载，设置默认封面尺寸比例
      this.coverOriginalWidth = 210;  // 默认封面宽度
      this.coverOriginalHeight = 300; // 默认封面高度（0.7比例）
      this.isSystemResource = true;   // 标记为特殊资源，使用渐变效果
      // 直接开始动画，使用默认渐变效果
      if (this.componentWidth > 0 && this.componentHeight > 0) {
        this.startTransition();
      } else {
        this.pendingAnimationStart = true;
        logger.info(TAG, '等待组件尺寸就绪后启动动画');
      }
      return;
    }
    
    try {
      // 处理不同类型的路径
      let imagePath = this.coverImagePath;
      if (imagePath.startsWith('/') && !imagePath.startsWith('file://')) {
        imagePath = 'file://' + imagePath;
      }
      
      const imageSource = image.createImageSource(imagePath);
      this.coverPixelMap = await imageSource.createPixelMap();
      
      // 获取图片原始尺寸
      const imageInfo = await imageSource.getImageInfo();
      this.coverOriginalWidth = imageInfo.size.width;
      this.coverOriginalHeight = imageInfo.size.height;
      logger.info(TAG, `封面图片原始尺寸: ${this.coverOriginalWidth}x${this.coverOriginalHeight}`);
      
      imageSource.release();
      
      logger.info(TAG, '封面图片加载成功');
      
      // 图片加载完成后开始动画
      this.startTransition();
    } catch (error) {
      logger.error(TAG, `加载封面图片失败: ${String(error)}`);
      // 即使加载失败，也应该开始动画（检查尺寸）
      if (this.componentWidth > 0 && this.componentHeight > 0) {
        this.startTransition();
      } else {
        this.pendingAnimationStart = true;
        logger.info(TAG, '等待组件尺寸就绪后启动动画');
      }
    }
  }
  
  private releaseCoverPixelMap(): void {
    if (this.coverPixelMap) {
      this.coverPixelMap.release();
      this.coverPixelMap = null;
    }
  }
  
  // ========== 位置变化监听 ==========
  private onCoverPositionChange(): void {
    if (this.currentPhase === TransitionPhase.IDLE) {
      this.currentX = this.coverPosition.x;
      this.currentY = this.coverPosition.y;
      this.currentWidth = this.coverPosition.width;
      this.currentHeight = this.coverPosition.height;
    }
  }
  
  // ========== PixelMap变化监听 ==========
  private onReaderPixelMapChange(): void {
    logger.info(TAG, `📷 onReaderPixelMapChange触发: mode=${this.mode}, hasPixelMap=${this.readerContentPixelMap ? '有' : '无'}`);
    // 当readerContentPixelMap通过@Prop设置时，更新本地副本
    if (this.mode === TransitionMode.CLOSE && this.readerContentPixelMap) {
      this.localReaderPixelMap = this.readerContentPixelMap;
      logger.info(TAG, `📷 PixelMap已更新到本地状态 (通过@Watch)`);
    }
  }
  
  // ========== 阅读器就绪状态变化监听 ==========
  private onReaderReadyChange(): void {
    logger.info(TAG, `onReaderReadyChange: isReaderReady=${this.isReaderReady}, mode=${this.mode}, phase=${this.currentPhase}, pendingStart=${this.pendingAnimationStart}`);
    
    // 关闭模式：截图完成后启动动画
    if (this.isReaderReady && this.mode === TransitionMode.CLOSE && this.pendingAnimationStart && !this.isAnimating) {
      if (this.componentWidth > 0 && this.componentHeight > 0) {
        logger.info(TAG, '关闭模式：截图完成，启动动画');
        this.pendingAnimationStart = false;
        this.startTransition();
      }
      return;
    }
    
    // 翻开模式：只有在等待阶段且动画未完成时才响应
    if (this.isReaderReady && this.currentPhase === TransitionPhase.WAITING_READY && !this.animationCompleted) {
      logger.info(TAG, '检测到阅读器就绪，开始掀开动画');
      this.clearReaderReadyTimers();  // 清除等待计时器
      this.startLiftAnimation();
    }
  }
  
  // ========== 清除阅读器就绪检查计时器 ==========
  private clearReaderReadyTimers(): void {
    if (this.readerReadyCheckTimer !== -1) {
      clearInterval(this.readerReadyCheckTimer);
      this.readerReadyCheckTimer = -1;
    }
    if (this.readerReadyTimeoutTimer !== -1) {
      clearTimeout(this.readerReadyTimeoutTimer);
      this.readerReadyTimeoutTimer = -1;
    }
  }
  
  // ========== 动画控制 ==========
  
  /**
   * 开始过渡动画
   */
  public startTransition(): void {
    if (this.isAnimating) {
      logger.warn(TAG, '动画已在进行中');
      return;
    }
    
    // 重置完成标志
    this.animationCompleted = false;
    this.clearReaderReadyTimers();
    
    logger.info(TAG, `开始过渡动画，模式: ${this.mode}`);
    
    if (this.mode === TransitionMode.OPEN) {
      this.startOpenAnimation();
    } else {
      this.startCloseAnimation();
    }
  }
  
  /**
   * 开始翻开动画
   */
  private startOpenAnimation(): void {
    // 计算中央目标位置
    this.calculateCenterPosition();
    
    // 设置初始状态
    this.currentX = this.coverPosition.x;
    this.currentY = this.coverPosition.y;
    this.currentWidth = this.coverPosition.width;
    this.currentHeight = this.coverPosition.height;
    this.currentScale = 1;
    this.currentOpacity = 1;
    this.liftAngle = 0;
    
    // 开始第一阶段：封面移动到中央
    this.setPhase(TransitionPhase.COVER_MOVING);
    this.animateCoverMove();
  }
  
  /**
   * 开始关闭动画
   */
  private startCloseAnimation(): void {
    // 计算中央位置（关闭动画从中央开始）
    this.calculateCenterPosition();
    
    // 调试：检查截图是否可用
    logger.info(TAG, `📷 关闭动画开始: readerContentPixelMap=${this.readerContentPixelMap ? '有效' : '空'}, localReaderPixelMap=${this.localReaderPixelMap ? '有效' : '空'}`);
    if (this.localReaderPixelMap) {
      logger.info(TAG, `📷 关闭动画：本地截图可用，将使用Image组件显示`);
    } else if (this.readerContentPixelMap) {
      logger.warn(TAG, `📷 关闭动画：原始截图可用但本地副本为空，尝试复制`);
      this.localReaderPixelMap = this.readerContentPixelMap;
    } else {
      logger.warn(TAG, `📷 关闭动画：截图不可用，将使用Canvas备用效果`);
    }
    
    // 设置初始状态（从全屏开始，透明度为1）
    // 关键：截图内容和阅读器内容完全一样，所以直接显示不会有视觉差异
    this.currentX = 0;
    this.currentY = 0;
    this.currentWidth = this.componentWidth;
    this.currentHeight = this.componentHeight;
    this.currentScale = 1;
    this.currentOpacity = 1;  // 直接显示，因为截图和阅读器内容一样
    this.liftAngle = 0;
    
    logger.info(TAG, `关闭动画初始状态: pos=(${this.currentX}, ${this.currentY}), size=${this.currentWidth}x${this.currentHeight}`);
    
    // 直接开始缩小阶段（跳过淡入，因为截图和阅读器内容一样）
    this.setPhase(TransitionPhase.SHRINKING);
    this.animateShrink();
  }
  
  /**
   * 淡入动画（关闭模式第一阶段）
   * 让截图从透明渐变到不透明，实现无缝过渡
   */
  private animateFadeIn(): void {
    const duration = 100;  // 100ms快速淡入
    const startTime = Date.now();
    
    const animate = () => {
      if (this.animationCompleted) {
        clearInterval(this.animationTimer);
        return;
      }
      
      const elapsed = Date.now() - startTime;
      const progress = Math.min(elapsed / duration, 1);
      
      // 使用ease-out曲线让淡入更自然
      const easedProgress = 1 - Math.pow(1 - progress, 2);
      
      // 更新透明度
      this.currentOpacity = easedProgress;
      
      if (progress >= 1) {
        // 淡入完成，停止计时器并进入缩小阶段
        clearInterval(this.animationTimer);
        this.currentOpacity = 1;
        this.setPhase(TransitionPhase.SHRINKING);
        this.animateShrink();
      }
    };
    
    this.animationTimer = setInterval(animate, 16);
  }
  
  /**
   * 计算中央目标位置
   */
  private calculateCenterPosition(): void {
    // 防护检查：确保封面尺寸有效
    const coverWidth = this.coverPosition.width > 0 ? this.coverPosition.width : 140;
    const coverHeight = this.coverPosition.height > 0 ? this.coverPosition.height : 200;
    
    // 保持封面宽高比
    const coverAspectRatio = coverWidth / coverHeight;
    
    // 中央展示时的最大尺寸
    const maxWidth = this.componentWidth * this.config.centerScale;
    const maxHeight = this.componentHeight * this.config.centerScale;
    
    // 根据宽高比计算实际尺寸
    if (maxHeight > 0 && maxWidth / maxHeight > coverAspectRatio) {
      // 高度限制
      this.centerHeight = maxHeight;
      this.centerWidth = maxHeight * coverAspectRatio;
    } else {
      // 宽度限制
      this.centerWidth = maxWidth;
      this.centerHeight = coverAspectRatio > 0 ? maxWidth / coverAspectRatio : maxHeight;
    }
    
    // 计算中央位置
    this.centerX = (this.componentWidth - this.centerWidth) / 2;
    this.centerY = (this.componentHeight - this.centerHeight) / 2;
    
    // 最终防护：确保没有NaN
    if (isNaN(this.centerX)) this.centerX = 0;
    if (isNaN(this.centerY)) this.centerY = 0;
    if (isNaN(this.centerWidth)) this.centerWidth = this.componentWidth * 0.7;
    if (isNaN(this.centerHeight)) this.centerHeight = this.componentHeight * 0.5;
    
    logger.debug(TAG, `中央位置: (${this.centerX}, ${this.centerY}), 尺寸: ${this.centerWidth}x${this.centerHeight}`);
  }
  
  /**
   * 设置动画阶段
   */
  private setPhase(phase: TransitionPhase): void {
    if (this.currentPhase !== phase) {
      logger.info(TAG, `阶段变化: ${this.currentPhase} -> ${phase}`);
      this.currentPhase = phase;
      this.animationProgress = 0;
      this.onPhaseChange(phase);
    }
  }
  
  /**
   * 停止动画
   */
  private stopAnimation(): void {
    if (this.animationTimer !== -1) {
      clearInterval(this.animationTimer);
      this.animationTimer = -1;
    }
    this.isAnimating = false;
  }
  
  /**
   * 取消动画（带渐隐效果）
   */
  public cancelWithFadeOut(onComplete?: () => void): void {
    if (this.isCancelling) {
      return;
    }
    
    logger.info(TAG, '开始取消动画渐隐');
    this.isCancelling = true;
    this.stopAnimation();
    
    this.cancelFadeStartTime = Date.now();
    const startOpacity = this.currentOpacity;
    
    const animateFadeOut = () => {
      const elapsed = Date.now() - this.cancelFadeStartTime;
      const progress = Math.min(1, elapsed / this.cancelFadeDuration);
      
      // 渐隐
      this.currentOpacity = startOpacity * (1 - progress);
      this.shadowOpacity = this.shadowOpacity * (1 - progress);
      
      this.renderFrame();
      
      if (progress >= 1) {
        if (this.cancelFadeTimer !== -1) {
          clearInterval(this.cancelFadeTimer);
          this.cancelFadeTimer = -1;
        }
        this.isCancelling = false;
        logger.info(TAG, '取消动画渐隐完成');
        if (onComplete) {
          onComplete();
        }
      }
    };
    
    this.cancelFadeTimer = setInterval(animateFadeOut, 16);
  }
  
  // ========== 翻开模式动画 ==========
  
  // 是否已触发页面过渡
  private hasTriggeredTransition: boolean = false;
  // 是否显示加载中
  @State private showLoading: boolean = false;
  
  /**
   * 连续的翻开动画：
   * 阶段1 (0%-80%): 封面上浮、放大、翻开，底层黑页同步展开
   * 阶段2 (80%): 黑页全屏，触发页面过渡到阅读器
   * 阶段3 (80%-100%): 封面渐隐消失，露出下方阅读器
   */
  private animateCoverMove(): void {
    this.isAnimating = true;
    this.animationStartTime = Date.now();
    this.hasTriggeredTransition = false;
    
    // 总动画时长
    const totalDuration = this.config.coverMoveDuration + this.config.liftDuration;
    
    const startX = this.coverPosition.x;
    const startY = this.coverPosition.y;
    const startWidth = this.coverPosition.width;
    const startHeight = this.coverPosition.height;
    
    // 最终目标：全屏
    const endWidth = this.componentWidth;
    const endHeight = this.componentHeight;
    
    const animate = () => {
      const elapsed = Date.now() - this.animationStartTime;
      const progress = Math.min(1, elapsed / totalDuration);
      
      // 使用缓动函数
      const easedProgress = this.easeInOutCubic(progress);
      
      // 连续放大：从封面尺寸到全屏
      this.currentWidth = startWidth + (endWidth - startWidth) * easedProgress;
      this.currentHeight = startHeight + (endHeight - startHeight) * easedProgress;
      
      // 位置：保持左边缘为轴心移动
      const leftEdgeX = startX * (1 - easedProgress);
      this.currentX = leftEdgeX;
      // Y从封面位置移动到顶部
      this.currentY = startY * (1 - easedProgress);
      
      // 翻开角度：从10%进度开始翻开，到60%完成（更早完成翻开）
      if (progress > 0.1 && progress < 0.6) {
        const liftProgress = (progress - 0.1) / 0.5;
        this.liftAngle = this.easeOutCubic(liftProgress) * this.config.maxLiftAngle;
      } else if (progress >= 0.6) {
        this.liftAngle = this.config.maxLiftAngle;
      }
      
      // 动画完成后才触发页面过渡（在progress >= 1的处理中）
      // 不再在这里提前触发
      
      // 封面保持不透明，直到动画完成
      // 不再渐隐，由动画完成时统一处理
      
      // 阴影效果
      this.shadowOpacity = Math.sin(progress * Math.PI * 0.8) * this.config.shadowIntensity;
      
      this.animationProgress = progress;
      this.renderFrame();
      
      if (progress >= 1) {
        this.stopAnimation();
        this.clearReaderReadyTimers();
        this.animationCompleted = true;
        this.showLoading = false;
        this.setPhase(TransitionPhase.COMPLETED);
        
        // 动画100%完成后才触发页面导航
        if (!this.hasTriggeredTransition) {
          this.hasTriggeredTransition = true;
          logger.info(TAG, '动画完成，触发页面过渡');
          this.onAnimationComplete();
        }
      }
    };
    
    this.animationTimer = setInterval(animate, 16);
  }
  
  /**
   * 检查阅读器是否就绪
   */
  private checkReaderReady(): void {
    // 阅读器就绪时隐藏加载动画
    if (this.isReaderReady) {
      this.showLoading = false;
    }
  }
  
  /**
   * 阶段2：封面掀起动画（保留用于兼容）
   */
  private startLiftAnimation(): void {
    // 已合并到连续动画中
  }
  
  /**
   * 阶段3：过渡到阅读器（保留用于兼容）
   */
  private startTransitionToReader(): void {
    // 已合并到连续动画中
  }
  
  // ========== 关闭模式动画阶段 ==========
  
  /**
   * 阶段1：阅读器内容缩小
   */
  private animateShrink(): void {
    this.isAnimating = true;
    this.animationStartTime = Date.now();
    const duration = this.config.shrinkDuration;
    
    const startWidth = this.componentWidth;
    const startHeight = this.componentHeight;
    
    const animate = () => {
      const elapsed = Date.now() - this.animationStartTime;
      const progress = Math.min(1, elapsed / duration);
      
      // 使用缓动函数
      const easedProgress = this.easeInCubic(progress);
      
      // 缩小到中央位置
      this.currentWidth = startWidth - (startWidth - this.centerWidth) * easedProgress;
      this.currentHeight = startHeight - (startHeight - this.centerHeight) * easedProgress;
      this.currentX = (this.componentWidth - this.currentWidth) / 2;
      this.currentY = (this.componentHeight - this.currentHeight) / 2;
      
      // 圆角逐渐增加
      this.animationProgress = progress;
      this.renderFrame();
      
      if (progress >= 1) {
        this.stopAnimation();
        // 缩小完成，开始返回封面位置
        this.animateReturn();
      }
    };
    
    this.animationTimer = setInterval(animate, 16);
  }
  
  /**
   * 阶段2：缩回到封面位置（同时封面翻页盖住）
   */
  private animateReturn(): void {
    this.isAnimating = true;
    this.setPhase(TransitionPhase.RETURNING);
    this.animationStartTime = Date.now();
    const duration = this.config.returnDuration;
    
    const startX = this.currentX;
    const startY = this.currentY;
    const startWidth = this.currentWidth;
    const startHeight = this.currentHeight;
    
    const targetX = this.coverPosition.x;
    const targetY = this.coverPosition.y;
    const targetWidth = this.coverPosition.width;
    const targetHeight = this.coverPosition.height;
    
    // 初始封面翻页进度为0（完全打开状态）
    this.coverFlipProgress = 0;
    
    const animate = () => {
      const elapsed = Date.now() - this.animationStartTime;
      const progress = Math.min(1, elapsed / duration);
      
      // 使用缓动函数
      const easedProgress = this.easeInOutCubic(progress);
      
      // 移动到封面位置
      this.currentX = startX + (targetX - startX) * easedProgress;
      this.currentY = startY + (targetY - startY) * easedProgress;
      this.currentWidth = startWidth + (targetWidth - startWidth) * easedProgress;
      this.currentHeight = startHeight + (targetHeight - startHeight) * easedProgress;
      
      // 封面翻页盖住效果：从30%进度开始，到100%完成
      if (progress > 0.3) {
        const flipProgress = (progress - 0.3) / 0.7;  // 归一化到0-1
        this.coverFlipProgress = this.easeOutCubic(flipProgress);
      }
      
      // 开始淡出（在后半段）
      if (progress > 0.7) {
        const fadeProgress = (progress - 0.7) / 0.3;
        this.currentOpacity = 1 - fadeProgress * 0.2;  // 淡出20%
      }
      
      this.animationProgress = progress;
      this.renderFrame();
      
      if (progress >= 1) {
        this.stopAnimation();
        // 返回完成，开始淡出
        this.animateFade();
      }
    };
    
    this.animationTimer = setInterval(animate, 16);
  }
  
  /**
   * 阶段3：淡出消失
   */
  private animateFade(): void {
    this.isAnimating = true;
    this.setPhase(TransitionPhase.FADING);
    this.animationStartTime = Date.now();
    const duration = this.config.fadeDuration;
    
    const startOpacity = this.currentOpacity;
    
    const animate = () => {
      const elapsed = Date.now() - this.animationStartTime;
      const progress = Math.min(1, elapsed / duration);
      
      // 使用缓动函数
      const easedProgress = this.easeOutCubic(progress);
      
      // 淡出
      this.currentOpacity = startOpacity * (1 - easedProgress);
      
      // 同时继续轻微缩小
      const shrinkFactor = 1 - easedProgress * 0.1;
      this.currentWidth = this.coverPosition.width * shrinkFactor;
      this.currentHeight = this.coverPosition.height * shrinkFactor;
      // 保持中心位置
      this.currentX = this.coverPosition.x + (this.coverPosition.width - this.currentWidth) / 2;
      this.currentY = this.coverPosition.y + (this.coverPosition.height - this.currentHeight) / 2;
      
      this.animationProgress = progress;
      this.renderFrame();
      
      if (progress >= 1) {
        this.stopAnimation();
        this.clearReaderReadyTimers();
        this.animationCompleted = true;
        this.setPhase(TransitionPhase.COMPLETED);
        this.onAnimationComplete();
      }
    };
    
    this.animationTimer = setInterval(animate, 16);
  }
  
  // ========== 缓动函数 ==========
  
  private easeOutCubic(t: number): number {
    return 1 - Math.pow(1 - t, 3);
  }
  
  private easeInCubic(t: number): number {
    return t * t * t;
  }
  
  private easeInOutCubic(t: number): number {
    return t < 0.5 ? 4 * t * t * t : 1 - Math.pow(-2 * t + 2, 3) / 2;
  }
  
  // ========== Canvas渲染 ==========
  
  /**
   * 渲染当前帧
   */
  private renderFrame(): void {
    if (!this.canvasContext) return;
    
    const ctx = this.canvasContext;
    const w = this.componentWidth;
    const h = this.componentHeight;
    
    // 清空画布
    ctx.clearRect(0, 0, w, h);
    
    // 根据模式选择渲染方法
    if (this.mode === TransitionMode.OPEN) {
      this.renderOpenFrame(ctx, w, h);
    } else {
      this.renderCloseFrame(ctx, w, h);
    }
  }
  
  /**
   * 渲染翻开模式帧
   * 特点：无背景遮罩、无白色边框、轴心在左侧书脊
   */
  private renderOpenFrame(ctx: CanvasRenderingContext2D, w: number, h: number): void {
    // 清空画布（透明背景，不绘制遮罩）
    ctx.clearRect(0, 0, w, h);
    
    // 保存状态
    ctx.save();
    
    // ========== 轴心在左边缘（书脊位置） ==========
    // 移动到封面左边缘中点作为变换原点
    const spineX = this.currentX;  // 左边缘X坐标
    const spineCenterY = this.currentY + this.currentHeight / 2;  // 垂直中心
    ctx.translate(spineX, spineCenterY);
    
    // ========== 绘制底层页面（书籍内页） ==========
    // 电子书使用读取的背景设置，漫画使用黑色
    if (this.liftAngle > 0) {
      ctx.save();
      ctx.globalAlpha = this.currentOpacity;
      
      // 内页内容区域（模拟阅读器背景）
      // 先绘制背景色作为底色
      ctx.fillStyle = this.ebookBackground ? this.ebookBackground.backgroundColor : '#000000';
      ctx.fillRect(0, -this.currentHeight / 2, this.currentWidth, this.currentHeight);
      
      // 如果有背景图片，绘制背景图片（覆盖背景色）
      // 使用 Cover 效果：保持宽高比填充区域，裁剪超出部分
      if (this.backgroundImagePixelMap && this.ebookBackground) {
        ctx.save();
        ctx.globalAlpha = this.currentOpacity * (this.ebookBackground.backgroundImageOpacity ?? 0.3);
        
        // 获取背景图片原始尺寸
        const imgInfo = this.backgroundImagePixelMap.getImageInfoSync();
        const imgWidth = imgInfo.size.width;
        const imgHeight = imgInfo.size.height;
        
        // 目标区域
        const destX = 0;
        const destY = -this.currentHeight / 2;
        const destWidth = this.currentWidth;
        const destHeight = this.currentHeight;
        
        // 计算 Cover 效果的缩放比例
        const scaleX = destWidth / imgWidth;
        const scaleY = destHeight / imgHeight;
        const scale = Math.max(scaleX, scaleY);  // Cover 使用较大的缩放比
        
        // 计算缩放后的图片尺寸
        const scaledWidth = imgWidth * scale;
        const scaledHeight = imgHeight * scale;
        
        // 计算居中偏移（裁剪超出部分）
        const offsetX = destX + (destWidth - scaledWidth) / 2;
        const offsetY = destY + (destHeight - scaledHeight) / 2;
        
        // 设置裁剪区域
        ctx.beginPath();
        ctx.rect(destX, destY, destWidth, destHeight);
        ctx.clip();
        
        // 绘制背景图片
        ctx.drawImage(this.backgroundImagePixelMap, offsetX, offsetY, scaledWidth, scaledHeight);
        ctx.restore();
      }
      
      // 如果需要显示加载中动画
      if (this.showLoading) {
        this.renderBlackPageLoading(ctx);
      }
      
      ctx.restore();
    }
    
    // ========== 应用3D掀起变换（封面从左侧书脊翻开） ==========
    if (this.config.enable3DEffect && this.liftAngle > 0) {
      // 模拟3D透视效果 - 从左侧书脊掀起，轴心已在左边缘
      const angleRad = this.liftAngle * Math.PI / 180;
      const scaleX = Math.cos(angleRad);
      // 修复：保持宽高比，Y轴不再应用透视缩放，只缩放X轴模拟翻开效果
      // 之前的 perspective 应用到Y轴导致图片被拉伸
      
      // 应用变换：只缩放X轴，Y轴保持不变
      ctx.transform(scaleX, 0, 0, 1, 0, 0);
    }
    
    // 绘制阴影
    if (this.config.enableShadow && this.shadowOpacity > 0 && this.liftAngle > 0) {
      ctx.shadowColor = `rgba(0, 0, 0, ${this.shadowOpacity * 0.6})`;
      ctx.shadowBlur = 15 + this.liftAngle * 0.5;
      ctx.shadowOffsetX = Math.sin(this.liftAngle * Math.PI / 180) * 15;
      ctx.shadowOffsetY = 5;
    }
    
    // 绘制封面（无白色边框）
    ctx.globalAlpha = this.currentOpacity;
    
    // 绘制封面图片（坐标系：原点在左边缘中点，向右为正X，向下为正Y）
    // 封面区域：从(0, -height/2)到(width, height/2)
    if (this.coverPixelMap) {
      // 计算保持宽高比的绘制区域
      let drawWidth = this.currentWidth;
      let drawHeight = this.currentHeight;
      let drawX = 0;
      let drawY = -this.currentHeight / 2;
      
      if (this.coverOriginalWidth > 0 && this.coverOriginalHeight > 0) {
        const originalAspect = this.coverOriginalWidth / this.coverOriginalHeight;
        const targetAspect = this.currentWidth / this.currentHeight;
        
        if (originalAspect > targetAspect) {
          // 图片更宽，以高度为基准
          drawHeight = this.currentHeight;
          drawWidth = this.currentHeight * originalAspect;
          drawX = (this.currentWidth - drawWidth) / 2;  // 水平居中
          drawY = -this.currentHeight / 2;
        } else {
          // 图片更高，以宽度为基准
          drawWidth = this.currentWidth;
          drawHeight = this.currentWidth / originalAspect;
          drawX = 0;
          drawY = -drawHeight / 2;  // 垂直居中
        }
      }
      
      // 裁剪到封面区域
      ctx.save();
      ctx.beginPath();
      ctx.rect(0, -this.currentHeight / 2, this.currentWidth, this.currentHeight);
      ctx.clip();
      
      ctx.drawImage(
        this.coverPixelMap,
        drawX,
        drawY,
        drawWidth,
        drawHeight
      );
      
      ctx.restore();
    } else {
      // 占位符（灰色）
      ctx.fillStyle = '#E0E0E0';
      ctx.fillRect(0, -this.currentHeight / 2, this.currentWidth, this.currentHeight);
    }
    
    ctx.restore();
  }
  
  /**
   * 渲染黑页上的加载动画
   */
  private renderBlackPageLoading(ctx: CanvasRenderingContext2D): void {
    const centerX = this.currentWidth / 2;
    const centerY = 0;  // 垂直中心（因为坐标系原点在左边缘中点）
    
    // 旋转的加载圆环
    const time = Date.now() / 1000;
    const rotation = (time * 3) % (Math.PI * 2);
    
    ctx.save();
    ctx.translate(centerX, centerY);
    ctx.rotate(rotation);
    
    // 绘制加载圆环
    ctx.strokeStyle = 'rgba(255, 255, 255, 0.8)';
    ctx.lineWidth = 3;
    ctx.lineCap = 'round';
    
    const radius = 25;
    ctx.beginPath();
    ctx.arc(0, 0, radius, 0, Math.PI * 1.5);
    ctx.stroke();
    
    ctx.restore();
    
    // 加载文字
    ctx.fillStyle = 'rgba(255, 255, 255, 0.7)';
    ctx.font = '14px sans-serif';
    ctx.textAlign = 'center';
    ctx.fillText('加载中...', centerX, centerY + 50);
    
    // 持续刷新以显示动画
    setTimeout(() => this.renderFrame(), 50);
  }
  
  /**
   * 渲染书脊阴影
   */
  private renderBookSpineShadow(ctx: CanvasRenderingContext2D): void {
    const shadowWidth = 30 + this.liftAngle * 0.5;
    const shadowGradient = ctx.createLinearGradient(
      -this.currentWidth / 2 - shadowWidth,
      0,
      -this.currentWidth / 2,
      0
    );
    shadowGradient.addColorStop(0, 'rgba(0, 0, 0, 0)');
    shadowGradient.addColorStop(0.5, `rgba(0, 0, 0, ${0.1 + this.liftAngle * 0.003})`);
    shadowGradient.addColorStop(1, `rgba(0, 0, 0, ${0.3 + this.liftAngle * 0.004})`);
    
    ctx.fillStyle = shadowGradient;
    ctx.fillRect(
      -this.currentWidth / 2 - shadowWidth,
      -this.currentHeight / 2 - 10,
      shadowWidth,
      this.currentHeight + 20
    );
  }
  
  /**
   * 渲染封面光泽效果
   */
  private renderCoverGloss(ctx: CanvasRenderingContext2D): void {
    // 对角线光泽
    const glossGradient = ctx.createLinearGradient(
      -this.currentWidth / 2,
      -this.currentHeight / 2,
      this.currentWidth / 2,
      this.currentHeight / 2
    );
    glossGradient.addColorStop(0, 'rgba(255, 255, 255, 0.15)');
    glossGradient.addColorStop(0.3, 'rgba(255, 255, 255, 0.05)');
    glossGradient.addColorStop(0.5, 'rgba(255, 255, 255, 0)');
    glossGradient.addColorStop(0.7, 'rgba(255, 255, 255, 0.02)');
    glossGradient.addColorStop(1, 'rgba(255, 255, 255, 0.1)');
    
    ctx.fillStyle = glossGradient;
    ctx.fillRect(
      -this.currentWidth / 2,
      -this.currentHeight / 2,
      this.currentWidth,
      this.currentHeight
    );
  }
  
  /**
   * 渲染关闭模式帧 - 简化版，用于调试
   */
  private renderCloseFrame(ctx: CanvasRenderingContext2D, w: number, h: number): void {
    // 绘制半透明背景遮罩（逐渐变淡）
    const bgOpacity = Math.max(0, this.currentOpacity * 0.6);
    ctx.fillStyle = `rgba(0, 0, 0, ${bgOpacity})`;
    ctx.fillRect(0, 0, w, h);
    
    // 🔴 调试：先绘制一个红色矩形框，确认Canvas渲染正常
    ctx.strokeStyle = '#FF0000';
    ctx.lineWidth = 5;
    ctx.strokeRect(this.currentX, this.currentY, this.currentWidth, this.currentHeight);
    
    // 绘制阅读器内容
    const pixelMapToUse = this.localReaderPixelMap || this.readerContentPixelMap;
    logger.info(TAG, `📷 renderCloseFrame: localPixelMap=${this.localReaderPixelMap ? '有' : '无'}, propPixelMap=${this.readerContentPixelMap ? '有' : '无'}, 使用=${pixelMapToUse ? '有效' : '无'}`);
    logger.info(TAG, `📷 Canvas尺寸: ${w}x${h}, 绘制位置: (${this.currentX}, ${this.currentY}), 尺寸: ${this.currentWidth}x${this.currentHeight}`);
    
    if (pixelMapToUse) {
      try {
        logger.info(TAG, `📷 开始drawImage...`);
        // 简化：直接绘制，不使用clip
        ctx.drawImage(
          pixelMapToUse,
          this.currentX,
          this.currentY,
          this.currentWidth,
          this.currentHeight
        );
        logger.info(TAG, `📷 drawImage完成`);
        
        // 🔴 调试：在PixelMap上方绘制绿色边框，确认drawImage被调用
        ctx.strokeStyle = '#00FF00';
        ctx.lineWidth = 3;
        ctx.strokeRect(this.currentX + 5, this.currentY + 5, this.currentWidth - 10, this.currentHeight - 10);
      } catch (e) {
        logger.error(TAG, `📷 绘制截图失败: ${String(e)}`);
        // 失败时绘制错误提示
        ctx.fillStyle = '#FF0000';
        ctx.fillRect(this.currentX, this.currentY, this.currentWidth, this.currentHeight);
        ctx.fillStyle = '#FFFFFF';
        ctx.font = '20px sans-serif';
        ctx.fillText('绘制失败', this.currentX + 20, this.currentY + 50);
      }
    } else {
      // 没有PixelMap时绘制蓝色占位符
      logger.warn(TAG, `📷 没有可用的PixelMap，绘制蓝色占位符`);
      ctx.fillStyle = '#0000FF';
      ctx.fillRect(this.currentX, this.currentY, this.currentWidth, this.currentHeight);
      ctx.fillStyle = '#FFFFFF';
      ctx.font = '20px sans-serif';
      ctx.fillText('无截图', this.currentX + 20, this.currentY + 50);
    }
  }
  
  /**
   * 绘制备用内容（当截图不可用时）
   */
  private drawFallbackContent(ctx: CanvasRenderingContext2D): void {
    const gradient = ctx.createLinearGradient(
      this.currentX,
      this.currentY,
      this.currentX,
      this.currentY + this.currentHeight
    );
    gradient.addColorStop(0, '#2A2A2A');
    gradient.addColorStop(0.5, '#1A1A1A');
    gradient.addColorStop(1, '#0A0A0A');
    ctx.fillStyle = gradient;
    ctx.fillRect(this.currentX, this.currentY, this.currentWidth, this.currentHeight);
  }
  
  /**
   * 绘制圆角矩形路径
   */
  private roundRect(ctx: CanvasRenderingContext2D, x: number, y: number, w: number, h: number, r: number): void {
    ctx.moveTo(x + r, y);
    ctx.lineTo(x + w - r, y);
    ctx.quadraticCurveTo(x + w, y, x + w, y + r);
    ctx.lineTo(x + w, y + h - r);
    ctx.quadraticCurveTo(x + w, y + h, x + w - r, y + h);
    ctx.lineTo(x + r, y + h);
    ctx.quadraticCurveTo(x, y + h, x, y + h - r);
    ctx.lineTo(x, y + r);
    ctx.quadraticCurveTo(x, y, x + r, y);
    ctx.closePath();
  }
  
  /**
   * 渲染加载指示器
   */
  private renderLoadingIndicator(ctx: CanvasRenderingContext2D): void {
    // 绘制旋转的加载圆环
    const time = Date.now() / 1000;
    const rotation = (time * 2) % (Math.PI * 2);
    
    ctx.save();
    ctx.strokeStyle = 'rgba(255, 255, 255, 0.9)';
    ctx.lineWidth = 3;
    ctx.lineCap = 'round';
    
    const radius = 20;
    const arcLength = Math.PI * 1.5;
    
    ctx.beginPath();
    ctx.arc(0, this.currentHeight / 2 + 40, radius, rotation, rotation + arcLength);
    ctx.stroke();
    
    ctx.restore();
    
    // 加载文字
    ctx.fillStyle = 'rgba(255, 255, 255, 0.8)';
    ctx.font = '14px sans-serif';
    ctx.textAlign = 'center';
    ctx.fillText('加载中...', 0, this.currentHeight / 2 + 75);
    
    // 持续刷新加载指示器
    if (this.currentPhase === TransitionPhase.WAITING_READY) {
      setTimeout(() => this.renderFrame(), 50);
    }
  }
  
  // ========== UI构建 ==========
  build() {
    Stack() {
      // 关闭模式：优先使用原始PixelMap（无损），备用压缩文件
      // 使用原始PixelMap可以避免压缩导致的质量损失和延迟
      if (this.mode === TransitionMode.CLOSE && (this.localReaderPixelMap || (this.readerContentImagePath && this.readerContentImagePath.length > 0))) {
        // ========== 底层：阅读器截图 ==========
        // 优先使用原始PixelMap（无损质量），备用压缩文件
        if (this.localReaderPixelMap) {
          // 使用原始PixelMap - 无损质量，与阅读器完全一致
          Image(this.localReaderPixelMap)
            .width(this.currentWidth)
            .height(this.currentHeight)
            .position({ x: this.currentX, y: this.currentY })
            .objectFit(ImageFit.Fill)
            .opacity(this.currentOpacity)
            .borderRadius(this.currentPhase === TransitionPhase.SHRINKING || this.currentPhase === TransitionPhase.FADE_IN ? 0 : 8)
            .backgroundColor(Color.Transparent)
        } else if (this.readerContentImagePath && this.readerContentImagePath.length > 0) {
          // 备用：使用压缩文件
          Image(`file://${this.readerContentImagePath}`)
            .width(this.currentWidth)
            .height(this.currentHeight)
            .position({ x: this.currentX, y: this.currentY })
            .objectFit(ImageFit.Fill)
            .opacity(this.currentOpacity)
            .borderRadius(this.currentPhase === TransitionPhase.SHRINKING || this.currentPhase === TransitionPhase.FADE_IN ? 0 : 8)
            .backgroundColor(Color.Transparent)
            .onComplete(() => {
              logger.info(TAG, `📷 关闭动画截图加载完成: ${this.readerContentImagePath}`);
            })
            .onError((error) => {
              logger.error(TAG, `📷 关闭动画截图加载失败: ${JSON.stringify(error)}`);
            })
        }
        
        // ========== 上层：封面图片（带翻页盖住效果） ==========
        if (this.coverImagePath && this.coverImagePath.length > 0 && this.coverFlipProgress > 0) {
          Stack() {
            // 封面图片
            Image(this.coverImagePath.startsWith('/') ? `file://${this.coverImagePath}` : this.coverImagePath)
              .width('100%')
              .height('100%')
              .objectFit(ImageFit.Cover)
              .borderRadius(6)
          }
          .width(this.currentWidth)
          .height(this.currentHeight)
          .position({ x: this.currentX, y: this.currentY })
          .opacity(this.currentOpacity * this.coverFlipProgress)
          // 3D翻页变换效果：从右向左盖住
          .rotate({
            x: 0,
            y: 1,
            z: 0,
            angle: -90 * (1 - this.coverFlipProgress),  // 从-90度（打开）到0度（盖住）
            centerX: '0%',  // 左侧为轴心
            centerY: '50%',
            perspective: 800
          })
          .shadow({
            radius: 15 * this.coverFlipProgress,
            color: `rgba(0, 0, 0, ${0.3 * this.coverFlipProgress})`,
            offsetX: -10 * this.coverFlipProgress,
            offsetY: 5
          })
        }
      } else {
        // 翻开模式或无截图
        
        // 背景图片层（仅当纯文本使用背景图片时显示）
        // 这一层始终可见，作为最底层背景，Canvas在其上方
        // 阅读器就绪后淡出
        if (this.ebookBackground && this.ebookBackground.backgroundImagePath && this.ebookBackground.backgroundImagePath.length > 0) {
          Stack() {
            // 背景色层（作为图片底色）
            Column()
              .width('100%')
              .height('100%')
              .backgroundColor(this.ebookBackground.backgroundColor)
            
            // 背景图片层
            Image(this.ebookBackground.backgroundImagePath.startsWith('/') ? 
              `file://${this.ebookBackground.backgroundImagePath}` : this.ebookBackground.backgroundImagePath)
              .width('100%')
              .height('100%')
              .objectFit(ImageFit.Cover)
              .opacity(this.ebookBackground.backgroundImageOpacity ?? 0.3)
          }
          .width('100%')
          .height('100%')
          .expandSafeArea([SafeAreaType.SYSTEM, SafeAreaType.CUTOUT], [SafeAreaEdge.TOP, SafeAreaEdge.BOTTOM, SafeAreaEdge.START, SafeAreaEdge.END])
          // 动画完成后显示（封面扩展到全屏后），阅读器就绪后淡出
          .opacity(this.animationCompleted ? (this.isReaderReady ? 0 : 1) : 0)
          .animation({ duration: 150, curve: Curve.EaseOut })
        }
        
        // Canvas绘制封面动画
        // 动画未完成时显示，完成后淡出
        // 如果有背景图片，淡出后会显示上面的背景图片层
        // 注意：Canvas需要包装在Stack中才能正确扩展到安全区域
        Stack() {
          Canvas(this.canvasContext)
            .width('100%')
            .height('100%')
            .onReady(() => {
              logger.info(TAG, `Canvas已就绪, mode=${this.mode}, imagePath=${this.readerContentImagePath ? '有' : '无'}`);
              this.renderFrame();
            })
          
          // 网络图片封面覆盖层（当coverPixelMap为空且是网络图片时显示）
          if (this.isSystemResource && this.coverImagePath && 
              (this.coverImagePath.startsWith('http://') || this.coverImagePath.startsWith('https://'))) {
            Image(this.coverImagePath)
              .width(this.currentWidth)
              .height(this.currentHeight)
              .position({ x: this.currentX, y: this.currentY })
              .objectFit(ImageFit.Cover)
              .opacity(this.currentOpacity)
              .borderRadius(4)
          }
        }
        .width('100%')
        .height('100%')
        .expandSafeArea([SafeAreaType.SYSTEM, SafeAreaType.CUTOUT], [SafeAreaEdge.TOP, SafeAreaEdge.BOTTOM, SafeAreaEdge.START, SafeAreaEdge.END])
        .opacity(this.animationCompleted ? 0 : 1)
        .animation({ duration: 100, curve: Curve.Linear })
      }
    }
    .width('100%')
    .height('100%')
    .backgroundColor(Color.Transparent)  // 根容器透明背景，让原页面可见
    .expandSafeArea([SafeAreaType.SYSTEM, SafeAreaType.CUTOUT], [SafeAreaEdge.TOP, SafeAreaEdge.BOTTOM, SafeAreaEdge.START, SafeAreaEdge.END])  // 扩展到所有安全区域
    .onAreaChange((_, newArea) => {
      this.componentWidth = newArea.width as number;
      this.componentHeight = newArea.height as number;
      logger.debug(TAG, `组件尺寸: ${this.componentWidth}x${this.componentHeight}`);
      
      // 重新计算中央位置
      if (this.componentWidth > 0 && this.componentHeight > 0) {
        this.calculateCenterPosition();
        
        // 如果有等待启动的动画，现在启动它
        // 关闭模式需要额外检查isReaderReady（等待截图完成）
        if (this.pendingAnimationStart && !this.isAnimating) {
          if (this.mode === TransitionMode.CLOSE && !this.isReaderReady) {
            // 关闭模式但截图未完成，继续等待
            logger.info(TAG, `尺寸就绪但截图未完成，继续等待: isReaderReady=${this.isReaderReady}`);
          } else {
            this.pendingAnimationStart = false;
            logger.info(TAG, '条件就绪，启动等待中的动画');
            this.startTransition();
          }
        }
      }
    })
    .hitTestBehavior(HitTestMode.Transparent)  // 允许点击穿透
  }
}

/**
 * 过渡动画管理器（单例）
 * 用于全局控制过渡动画的显示和隐藏
 */
export class BookTransitionManager {
  private static instance: BookTransitionManager | null = null;
  
  // 当前过渡状态
  private isTransitioning: boolean = false;
  private currentMode: TransitionMode = TransitionMode.OPEN;
  private pendingReaderReady: boolean = false;
  
  // 回调
  private onTransitionStart: (() => void) | null = null;
  private onTransitionComplete: (() => void) | null = null;
  
  private constructor() {}
  
  public static getInstance(): BookTransitionManager {
    if (!BookTransitionManager.instance) {
      BookTransitionManager.instance = new BookTransitionManager();
    }
    return BookTransitionManager.instance;
  }
  
  /**
   * 开始翻开过渡
   */
  public startOpenTransition(
    coverImagePath: string,
    coverPosition: CoverPosition,
    onComplete?: () => void
  ): void {
    if (this.isTransitioning) {
      logger.warn(TAG, '已有过渡动画在进行中');
      return;
    }
    
    this.isTransitioning = true;
    this.currentMode = TransitionMode.OPEN;
    this.pendingReaderReady = false;
    this.onTransitionComplete = onComplete || null;
    
    logger.info(TAG, `开始翻开过渡: ${coverImagePath}`);
  }
  
  /**
   * 开始关闭过渡
   */
  public startCloseTransition(
    coverPosition: CoverPosition,
    readerContentPixelMap?: image.PixelMap,
    onComplete?: () => void
  ): void {
    if (this.isTransitioning) {
      logger.warn(TAG, '已有过渡动画在进行中');
      return;
    }
    
    this.isTransitioning = true;
    this.currentMode = TransitionMode.CLOSE;
    this.onTransitionComplete = onComplete || null;
    
    logger.info(TAG, '开始关闭过渡');
  }
  
  /**
   * 标记阅读器已就绪
   */
  public setReaderReady(): void {
    this.pendingReaderReady = true;
    logger.info(TAG, '阅读器已就绪');
  }
  
  /**
   * 完成过渡
   */
  public completeTransition(): void {
    this.isTransitioning = false;
    if (this.onTransitionComplete) {
      this.onTransitionComplete();
      this.onTransitionComplete = null;
    }
    logger.info(TAG, '过渡动画完成');
  }
  
  /**
   * 取消过渡
   */
  public cancelTransition(): void {
    this.isTransitioning = false;
    this.onTransitionComplete = null;
    logger.info(TAG, '过渡动画已取消');
  }
  
  /**
   * 获取当前是否正在过渡
   */
  public isInTransition(): boolean {
    return this.isTransitioning;
  }
  
  /**
   * 获取当前过渡模式
   */
  public getCurrentMode(): TransitionMode {
    return this.currentMode;
  }
  
  /**
   * 获取阅读器是否就绪
   */
  public isReaderReady(): boolean {
    return this.pendingReaderReady;
  }
}
