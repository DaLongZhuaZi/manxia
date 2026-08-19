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

import { logger } from 'manxia_core/src/main/ets/Utils/Logger';
import { image } from '@kit.ImageKit';
import { curves } from '@kit.ArkUI';
import { ThemeManager } from '../Framework/Managers/ThemeManager';
import { getCoverImageManager } from '../Framework/Image/CoverImageManager';
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
  maxLiftAngle: 68,  // 提升翻开角度，增强3D书本效果
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
  resolveCloseCoverPosition?: () => CoverPosition | null;  // 关闭动画回封面前复测位置，用于修正窗口模式切换后的坐标基准
}

@Component
export struct BookOpenTransition {
  // ========== 外部参数 ==========
  @Prop mode: TransitionMode = TransitionMode.OPEN;
  @Prop contentType: 'manga' | 'ebook' | 'novel' = 'manga';
  @Prop coverImagePath: string = '';
  @Prop @Watch('onCoverPositionChange') coverPosition: CoverPosition = { x: 0, y: 0, width: 100, height: 150 };
  @Prop @Watch('onReaderPixelMapChange') readerContentPixelMap: image.PixelMap | null = null;
  @Prop readerContentImagePath: string = '';  // 压缩后的截图临时文件路径（推荐使用）
  @Prop config: BookTransitionConfig = DEFAULT_CONFIG;
  @Prop @Watch('onReaderReadyChange') isReaderReady: boolean = false;  // 阅读器是否就绪（外部控制）
  @Prop @Watch('onReaderLoadProgressChange') readerLoadProgress: number = 0;
  @Prop ebookBackground: EBookBackgroundSettings | null = null;  // 电子书背景设置
  @Prop bookTitle: string = '';
  @Prop bookAuthor: string = '';
  @Prop bookIntro: string = '';
  
  // 回调函数
  onAnimationComplete: () => void = () => {};
  onPhaseChange: (phase: TransitionPhase) => void = () => {};
  resolveCloseCoverPosition: () => CoverPosition | null = () => null;
  
  // ========== 内部状态 ==========
  @State private currentPhase: TransitionPhase = TransitionPhase.IDLE;
  @State private animationProgress: number = 0;  // 当前阶段动画进度 0-1
  @State private loadingProgress: number = 0.06; // 打开等待阶段加载进度 0-1
  
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
  private coverPixelMapOwned: boolean = false;
  private backgroundImagePixelMap: image.PixelMap | null = null;  // 背景图片（用于Canvas绘制）
  
  // 存储截图的本地副本（防止引用丢失）
  @State private localReaderPixelMap: image.PixelMap | null = null;
  
  // 动画控制
  private animationTimer: number = -1;
  private loadingProgressTimer: number = -1;
  private loadingProgressFinishTimer: number = -1;
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
  @State private closeReaderOpacity: number = 1;
  @State private closeBookOpacity: number = 0;
  @State private closeBookScale: number = 0.88;
  
  // 封面图片原始尺寸（用于保持宽高比）
  private coverOriginalWidth: number = 0;
  private coverOriginalHeight: number = 0;
  @State private isSystemResource: boolean = false;  // 是否为系统资源图片（网络图片或app.media资源）
  
  // ========== 生命周期 ==========
  aboutToAppear(): void {
    logger.info(TAG, `组件初始化，模式: ${this.mode}, type=${this.contentType}, ebookBackground=${this.ebookBackground ? `有(色=${this.ebookBackground.backgroundColor}, 图=${this.ebookBackground.backgroundImagePath || '无'})` : '无'}`);
    this.resetLoadingProgress();
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
    if (!this.hasOpenBackgroundImage()) {
      this.backgroundImagePixelMap = null;
      return;
    }
    
    const imagePath = this.getOpenBackgroundImagePath();
    if (imagePath.length === 0) {
      return;
    }
    if (imagePath.startsWith('app.media.')) {
      logger.info(TAG, `背景图片为应用资源，跳过 PixelMap 预加载: ${imagePath}`);
      this.backgroundImagePixelMap = null;
      return;
    }
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
    this.stopLoadingProgressTimers();
    this.clearReaderReadyTimers();
    this.releaseCoverPixelMap();
    this.animationCompleted = true;  // 标记完成，防止任何残留计时器继续
  }
  
  // ========== 图片加载 ==========
  private async loadCoverImage(): Promise<void> {
    if (!this.coverImagePath || this.coverImagePath.length === 0) {
      logger.warn(TAG, '封面图片路径为空');
      if (this.mode === TransitionMode.OPEN) {
        this.coverOriginalWidth = 210;
        this.coverOriginalHeight = 300;
        this.isSystemResource = true;
        if (this.componentWidth > 0 && this.componentHeight > 0) {
          this.startTransition();
        } else {
          this.pendingAnimationStart = true;
          logger.info(TAG, '等待组件尺寸就绪后启动无封面翻开动画');
        }
        return;
      }
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
      logger.info(TAG, `检测到网络图片: ${this.coverImagePath}`);
      const cachedCoverPixelMap = getCoverImageManager().getCachedPixelMap(this.coverImagePath);
      if (cachedCoverPixelMap) {
        this.coverPixelMap = cachedCoverPixelMap;
        this.coverPixelMapOwned = false;
        const cachedInfo = cachedCoverPixelMap.getImageInfoSync();
        this.coverOriginalWidth = cachedInfo.size.width;
        this.coverOriginalHeight = cachedInfo.size.height;
        this.isSystemResource = false;
        logger.info(TAG, `复用预加载封面PixelMap: ${this.coverOriginalWidth}x${this.coverOriginalHeight}`);
      } else {
        logger.info(TAG, '网络封面未命中PixelMap缓存，使用Image覆盖层兜底');
        // 网络图片无法直接通过createImageSource加载，设置默认封面尺寸比例
        this.coverOriginalWidth = 210;  // 默认封面宽度
        this.coverOriginalHeight = 300; // 默认封面高度（0.7比例）
        this.isSystemResource = true;   // 标记为特殊资源，使用Image覆盖层兜底
      }
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
      this.coverPixelMapOwned = true;
      
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
    if (this.coverPixelMap && this.coverPixelMapOwned) {
      this.coverPixelMap.release();
    }
    this.coverPixelMap = null;
    this.coverPixelMapOwned = false;
  }

  private resolveAppMediaImageSource(raw: string): Resource {
    const resourceName = raw.substring('app.media.'.length);
    if (resourceName === 'mangabook') {
      return $r('app.media.mangabook');
    }
    if (resourceName === 'ebook') {
      return $r('app.media.ebook');
    }
    if (resourceName === 'ic_ebook') {
      return $r('app.media.ic_ebook');
    }
    if (resourceName === 'icon') {
      return $r('app.media.icon');
    }
    if (resourceName === 'ic_source_novel' || resourceName === 'ic_novel') {
      return $r('app.media.ic_source_novel');
    }
    return $r('app.media.ebook');
  }

  private toRenderableImageSource(raw: string): string | Resource {
    if (raw.startsWith('app.media.')) {
      return this.resolveAppMediaImageSource(raw);
    }
    if (raw.startsWith('/') && !raw.startsWith('file://')) {
      return `file://${raw}`;
    }
    return raw;
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
      this.completeLoadingProgress(() => {
        this.startLiftAnimation();
      });
    }
  }
  
  // ========== 清除阅读器就绪检查计时器 ==========
  private onReaderLoadProgressChange(): void {
    if (this.mode !== TransitionMode.OPEN || this.animationCompleted) {
      return;
    }
    this.applyReaderLoadProgress(this.currentPhase);
  }

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
    this.resetLoadingProgress();
    
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
    // Align close stage-1 target with the same 3D book rect used by open animation.
    this.calculateCenterPosition();
    const closeBookRect = this.getOpenTargetRect();
    this.centerX = closeBookRect.x;
    this.centerY = closeBookRect.y;
    this.centerWidth = closeBookRect.width;
    this.centerHeight = closeBookRect.height;

    logger.info(TAG, `close start: readerPixelMap=${this.readerContentPixelMap ? 'yes' : 'no'}, localPixelMap=${this.localReaderPixelMap ? 'yes' : 'no'}`);
    if (!this.localReaderPixelMap && this.readerContentPixelMap) {
      this.localReaderPixelMap = this.readerContentPixelMap;
      logger.warn(TAG, 'close start: restore local pixelMap from prop');
    }

    this.currentX = this.centerX;
    this.currentY = this.centerY;
    this.currentWidth = this.centerWidth;
    this.currentHeight = this.centerHeight;
    this.currentScale = 1;
    this.currentOpacity = 1;
    this.closeReaderOpacity = 1;
    this.closeBookOpacity = 0;
    this.closeBookScale = 0.88;
    this.liftAngle = 8;
    this.coverFlipProgress = 0;
    this.shadowOpacity = this.config.shadowIntensity * 0.16;

    logger.info(TAG, `close start rect: center=${this.currentWidth}x${this.currentHeight}, reader=${this.componentWidth}x${this.componentHeight}`);

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
      if (this.mode === TransitionMode.OPEN) {
        if (phase === TransitionPhase.WAITING_READY) {
          this.startWaitingProgressLoop();
        } else if (phase === TransitionPhase.COVER_LIFTING || phase === TransitionPhase.COMPLETED || phase === TransitionPhase.IDLE) {
          this.applyReaderLoadProgress(phase);
        }
      }
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

  private resetLoadingProgress(): void {
    this.stopLoadingProgressTimers();
    if (this.mode === TransitionMode.OPEN) {
      const readerProgress = this.normalizeReaderLoadProgress(this.readerLoadProgress);
      this.loadingProgress = Math.max(0.06, Math.min(0.45, readerProgress));
    } else {
      this.loadingProgress = 0;
    }
  }

  private stopLoadingProgressTimers(): void {
    if (this.loadingProgressTimer !== -1) {
      clearInterval(this.loadingProgressTimer);
      this.loadingProgressTimer = -1;
    }
    if (this.loadingProgressFinishTimer !== -1) {
      clearInterval(this.loadingProgressFinishTimer);
      this.loadingProgressFinishTimer = -1;
    }
  }

  private startWaitingProgressLoop(): void {
    if (this.mode !== TransitionMode.OPEN) {
      return;
    }
    if (this.loadingProgress < 0.42) {
      this.loadingProgress = 0.42;
    }
    this.applyReaderLoadProgress(TransitionPhase.WAITING_READY);
  }

  private completeLoadingProgress(onDone?: () => void): void {
    this.stopLoadingProgressTimers();
    this.loadingProgress = 1;
    if (onDone) {
      onDone();
    }
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
    this.stopLoadingProgressTimers();
    
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
   * 阶段1：封面移动到中心并放大，形成“书本就位”状态。
   * 完成后先触发导航，再进入 WAITING_READY 等待阅读器完成加载。
   */
  private animateCoverMove(): void {
    this.isAnimating = true;
    this.animationStartTime = Date.now();
    this.hasTriggeredTransition = false;
    this.showLoading = false;

    const totalDuration = this.config.coverMoveDuration + 260;

    const startX = this.coverPosition.x;
    const startY = this.coverPosition.y;
    const startWidth = this.coverPosition.width;
    const startHeight = this.coverPosition.height;

    const targetRect = this.getOpenTargetRect();
    const settleStartY = targetRect.y - Math.min(32, this.componentHeight * 0.04);
    const settleStartWidth = targetRect.width * 1.04;
    const settleStartHeight = targetRect.height * 1.04;
    const stageSplit = 0.74;

    const animate = () => {
      const elapsed = Date.now() - this.animationStartTime;
      const progress = this.clamp01(elapsed / totalDuration);

      if (progress <= stageSplit) {
        const t = this.clamp01(progress / stageSplit);
        const eased = this.easeOutQuart(t);
        this.currentX = startX + (targetRect.x - startX) * eased;
        this.currentY = startY + (settleStartY - startY) * eased;
        this.currentWidth = startWidth + (settleStartWidth - startWidth) * eased;
        this.currentHeight = startHeight + (settleStartHeight - startHeight) * eased;
        this.liftAngle = 6 * this.easeInOutSine(t);
      } else {
        const t = this.clamp01((progress - stageSplit) / (1 - stageSplit));
        const eased = this.clamp01(this.easeOutBack(t));
        this.currentX = targetRect.x;
        this.currentY = settleStartY + (targetRect.y - settleStartY) * this.easeInOutSine(t);
        this.currentWidth = settleStartWidth + (targetRect.width - settleStartWidth) * eased;
        this.currentHeight = settleStartHeight + (targetRect.height - settleStartHeight) * eased;
        this.liftAngle = 6 * (1 - this.easeInOutSine(t));
      }

      const movingProgress = 0.08 + 0.34 * this.easeInOutSine(progress);
      const readerDriven = Math.max(0.08, Math.min(0.62, 0.08 + this.normalizeReaderLoadProgress(this.readerLoadProgress) * 0.54));
      const mergedProgress = Math.max(movingProgress, readerDriven);
      const clampedMovingProgress = Math.max(0.08, Math.min(0.62, mergedProgress));
      if (clampedMovingProgress > this.loadingProgress) {
        this.loadingProgress = clampedMovingProgress;
      }

      this.currentOpacity = 1;
      this.shadowOpacity = (0.12 + 0.88 * Math.sin(progress * Math.PI)) * this.config.shadowIntensity;
      this.animationProgress = progress;
      this.renderFrame();

      if (progress >= 1) {
        this.stopAnimation();
        this.currentX = targetRect.x;
        this.currentY = targetRect.y;
        this.currentWidth = targetRect.width;
        this.currentHeight = targetRect.height;
        this.liftAngle = 0;
        this.shadowOpacity = this.config.shadowIntensity * 0.18;
        this.showLoading = false;
        this.setPhase(TransitionPhase.WAITING_READY);
        this.renderFrame();

        if (!this.hasTriggeredTransition) {
          this.hasTriggeredTransition = true;
          logger.info(TAG, '封面就位，触发页面导航');
          this.onAnimationComplete();
        }

        if (this.isReaderReady) {
          this.completeLoadingProgress(() => {
            this.startLiftAnimation();
          });
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
   * 阶段2：阅读器就绪后执行封面掀起，模拟真实翻书。
   */
  private startLiftAnimation(): void {
    if (this.mode !== TransitionMode.OPEN) {
      return;
    }
    if (this.animationCompleted || this.currentPhase === TransitionPhase.COVER_LIFTING) {
      return;
    }
    if (!this.isReaderReady) {
      return;
    }

    this.stopAnimation();
    this.setPhase(TransitionPhase.COVER_LIFTING);
    this.isAnimating = true;
    this.animationStartTime = Date.now();

    const duration = this.config.liftDuration + Math.floor(this.config.transitionDuration * 0.85);
    const startAngle = this.liftAngle;
    const maxAngle = Math.max(this.config.maxLiftAngle, 62);

    const animate = () => {
      const elapsed = Date.now() - this.animationStartTime;
      const progress = this.clamp01(elapsed / duration);
      const liftProgress = this.easeInOutSine(progress);

      const bounce = progress > 0.72
        ? Math.sin(((progress - 0.72) / 0.28) * Math.PI) * (1 - progress) * 3.2
        : 0;
      this.liftAngle = startAngle + (maxAngle - startAngle) * this.easeOutQuart(liftProgress) + bounce;

      const fadeStart = 0.34;
      if (progress <= fadeStart) {
        this.currentOpacity = 1;
      } else {
        const fadeProgress = this.clamp01((progress - fadeStart) / (1 - fadeStart));
        this.currentOpacity = 1 - this.easeInOutSine(fadeProgress);
      }

      this.shadowOpacity = (1 - progress) * this.config.shadowIntensity;
      this.animationProgress = progress;
      this.renderFrame();

      if (progress >= 1) {
        this.stopAnimation();
        this.currentOpacity = 0;
        this.shadowOpacity = 0;
        this.liftAngle = maxAngle;
        this.loadingProgress = 1;
        this.animationCompleted = true;
        this.setPhase(TransitionPhase.COMPLETED);
        this.renderFrame();
      }
    };

    this.animationTimer = setInterval(animate, 16);
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
    const duration = Math.max(320, this.config.shrinkDuration + 20);

    const fixedX = this.centerX;
    const fixedY = this.centerY;
    const fixedWidth = this.centerWidth;
    const fixedHeight = this.centerHeight;

    const animate = () => {
      const elapsed = Date.now() - this.animationStartTime;
      const progress = this.clamp01(elapsed / duration);
      const easedFade = this.easeOutCubic(progress);
      const easedBook = this.easeInOutSine(progress);

      // Keep the reader snapshot full-screen and fade it out while a centered 3D book appears.
      this.currentX = fixedX;
      this.currentY = fixedY;
      this.currentWidth = fixedWidth;
      this.currentHeight = fixedHeight;
      this.currentOpacity = 1;
      this.closeReaderOpacity = 1 - easedFade;
      this.closeBookOpacity = easedBook;
      this.closeBookScale = 0.9 + 0.1 * this.easeOutCubic(progress);
      this.coverFlipProgress = 0;
      this.liftAngle = (1 - easedBook) * 8;
      this.shadowOpacity = this.config.shadowIntensity * (0.12 + 0.24 * easedBook);

      this.animationProgress = progress;
      this.renderFrame();

      if (progress >= 1) {
        this.stopAnimation();
        this.currentX = fixedX;
        this.currentY = fixedY;
        this.currentWidth = fixedWidth;
        this.currentHeight = fixedHeight;
        this.currentOpacity = 1;
        this.closeReaderOpacity = 0;
        this.closeBookOpacity = 1;
        this.closeBookScale = 1;
        this.liftAngle = 0;
        this.shadowOpacity = this.config.shadowIntensity * 0.3;
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
    const duration = Math.max(260, Math.floor(this.config.returnDuration * 0.9));

    const fixedX = this.currentX;
    const fixedY = this.currentY;
    const fixedWidth = this.currentWidth;
    const fixedHeight = this.currentHeight;

    this.coverFlipProgress = 0;

    const animate = () => {
      const elapsed = Date.now() - this.animationStartTime;
      const progress = this.clamp01(elapsed / duration);
      const eased = this.easeInOutSine(progress);

      // Stage-2 only closes the cover, keeps the 3D book fixed at center.
      this.currentX = fixedX;
      this.currentY = fixedY;
      this.currentWidth = fixedWidth;
      this.currentHeight = fixedHeight;
      this.currentOpacity = 1;
      this.closeReaderOpacity = 0;
      this.closeBookOpacity = 1;
      this.closeBookScale = 1;
      this.coverFlipProgress = eased;
      this.liftAngle = (1 - eased) * 4;
      this.shadowOpacity = this.config.shadowIntensity * (0.34 - 0.1 * eased);

      this.animationProgress = progress;
      this.renderFrame();

      if (progress >= 1) {
        this.stopAnimation();
        this.coverFlipProgress = 1;
        this.liftAngle = 0;
        this.currentOpacity = 1;
        this.closeReaderOpacity = 0;
        this.closeBookOpacity = 1;
        this.closeBookScale = 1;
        this.shadowOpacity = this.config.shadowIntensity * 0.24;
        this.animateFade();
      }
    };

    this.animationTimer = setInterval(animate, 16);
  }

  private getCloseFadeTargetCoverPosition(): CoverPosition {
    const targetCoverPosition: CoverPosition = {
      x: this.coverPosition.x,
      y: this.coverPosition.y,
      width: this.coverPosition.width,
      height: this.coverPosition.height
    };
    const resolvedCloseCoverPosition = this.resolveCloseCoverPosition();
    if (resolvedCloseCoverPosition === null) {
      return targetCoverPosition;
    }

    const deltaX = resolvedCloseCoverPosition.x - this.coverPosition.x;
    const deltaY = resolvedCloseCoverPosition.y - this.coverPosition.y;
    const statusBarHeight = AppStorage.get<number>('statusBarHeight') ?? 0;
    const halfStatusBarHeight = statusBarHeight / 2;
    const isSystemBarRebaseDelta = halfStatusBarHeight > 0
      && Math.abs(deltaX) <= 1
      && Math.abs(Math.abs(deltaY) - halfStatusBarHeight) <= 2.5;

    if (isSystemBarRebaseDelta) {
      targetCoverPosition.x = this.coverPosition.x - deltaX;
      targetCoverPosition.y = this.coverPosition.y - deltaY;
      logger.info(
        TAG,
        `close fade: 检测到系统栏坐标基准差，反向补偿目标位置, initial=(${this.coverPosition.x}, ${this.coverPosition.y}, ${this.coverPosition.width}x${this.coverPosition.height}), resolved=(${resolvedCloseCoverPosition.x}, ${resolvedCloseCoverPosition.y}, ${resolvedCloseCoverPosition.width}x${resolvedCloseCoverPosition.height}), delta=(${deltaX}, ${deltaY}), statusBar=${statusBarHeight}, target=(${targetCoverPosition.x}, ${targetCoverPosition.y}, ${targetCoverPosition.width}x${targetCoverPosition.height})`
      );
      return targetCoverPosition;
    }

    logger.info(
      TAG,
      `close fade: 保持初始目标位置，复测位置仅诊断, initial=(${targetCoverPosition.x}, ${targetCoverPosition.y}, ${targetCoverPosition.width}x${targetCoverPosition.height}), resolved=(${resolvedCloseCoverPosition.x}, ${resolvedCloseCoverPosition.y}, ${resolvedCloseCoverPosition.width}x${resolvedCloseCoverPosition.height}), delta=(${deltaX}, ${deltaY})`
    );
    return targetCoverPosition;
  }

  
  /**
   * 阶段3：淡出消失
   */
  private animateFade(): void {
    this.isAnimating = true;
    this.setPhase(TransitionPhase.FADING);
    this.animationStartTime = Date.now();
    const duration = Math.max(this.config.fadeDuration + 120, 320);

    const targetCoverPosition: CoverPosition = this.getCloseFadeTargetCoverPosition();

    const startX = this.currentX;
    const startY = this.currentY;
    const startWidth = this.currentWidth;
    const startHeight = this.currentHeight;
    const startShadow = this.shadowOpacity;
    const targetShadow = this.config.shadowIntensity * 0.08;

    const animate = () => {
      const elapsed = Date.now() - this.animationStartTime;
      const progress = this.clamp01(elapsed / duration);
      const easedMove = this.easeInOutCubic(progress);
      const easedShadow = this.easeOutCubic(progress);

      // Stage-3 moves the closed 3D book back to detail-page cover slot.
      this.currentX = startX + (targetCoverPosition.x - startX) * easedMove;
      this.currentY = startY + (targetCoverPosition.y - startY) * easedMove;
      this.currentWidth = startWidth + (targetCoverPosition.width - startWidth) * easedMove;
      this.currentHeight = startHeight + (targetCoverPosition.height - startHeight) * easedMove;
      this.currentOpacity = 1;
      this.closeReaderOpacity = 0;
      this.closeBookOpacity = 1;
      this.closeBookScale = 1;
      this.coverFlipProgress = 1;
      this.shadowOpacity = startShadow + (targetShadow - startShadow) * easedShadow;

      this.animationProgress = progress;
      this.renderFrame();

      if (progress >= 1) {
        this.stopAnimation();
        this.currentX = targetCoverPosition.x;
        this.currentY = targetCoverPosition.y;
        this.currentWidth = targetCoverPosition.width;
        this.currentHeight = targetCoverPosition.height;
        this.currentOpacity = 1;
        this.closeReaderOpacity = 0;
        this.closeBookOpacity = 1;
        this.closeBookScale = 1;
        this.coverFlipProgress = 1;
        this.shadowOpacity = targetShadow;
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

  private easeInOutSine(t: number): number {
    return -(Math.cos(Math.PI * t) - 1) / 2;
  }

  private easeOutQuart(t: number): number {
    return 1 - Math.pow(1 - t, 4);
  }

  private easeOutBack(t: number): number {
    const c1 = 1.70158;
    const c3 = c1 + 1;
    return 1 + c3 * Math.pow(t - 1, 3) + c1 * Math.pow(t - 1, 2);
  }

  private clamp01(value: number): number {
    return Math.max(0, Math.min(1, value));
  }

  private normalizeReaderLoadProgress(value: number): number {
    if (!isFinite(value)) {
      return 0;
    }
    const normalized = value > 1 ? value / 100 : value;
    return this.clamp01(normalized);
  }

  private applyReaderLoadProgress(phase: TransitionPhase): void {
    if (this.mode !== TransitionMode.OPEN || this.animationCompleted) {
      return;
    }

    const actualProgress = this.normalizeReaderLoadProgress(this.readerLoadProgress);
    let target = actualProgress;
    if (phase === TransitionPhase.COVER_MOVING) {
      target = Math.max(0.08, Math.min(0.62, 0.08 + actualProgress * 0.54));
    } else if (phase === TransitionPhase.WAITING_READY) {
      target = Math.min(0.98, actualProgress);
    } else if (phase === TransitionPhase.COVER_LIFTING || phase === TransitionPhase.COMPLETED) {
      target = 1;
    }

    if (target > this.loadingProgress) {
      this.loadingProgress = target;
    }
  }

  private getOpenCoverAspectRatio(): number {
    const width = this.coverPosition.width > 0
      ? this.coverPosition.width
      : (this.coverOriginalWidth > 0 ? this.coverOriginalWidth : 140);
    const height = this.coverPosition.height > 0
      ? this.coverPosition.height
      : (this.coverOriginalHeight > 0 ? this.coverOriginalHeight : 200);
    return Math.max(0.42, Math.min(1.25, width / Math.max(1, height)));
  }

  private getOpenTargetRect(): CoverPosition {
    const aspect = this.getOpenCoverAspectRatio();
    let width = this.componentWidth * 0.72;
    let height = width / aspect;
    const maxHeight = this.componentHeight * 0.82;

    if (height > maxHeight) {
      height = maxHeight;
      width = height * aspect;
    }

    return {
      x: (this.componentWidth - width) / 2,
      y: (this.componentHeight - height) / 2,
      width: width,
      height: height
    };
  }

  private getOpenBackdropColor(): string {
    if (this.contentType === 'manga') {
      return '#000000';
    }
    if (this.ebookBackground && this.ebookBackground.backgroundColor.length > 0) {
      return this.ebookBackground.backgroundColor;
    }
    if (this.contentType === 'novel') {
      return '#F5F0E1';
    }
    if (this.contentType === 'ebook') {
      return this.getDefaultEBookBackdropColor();
    }
    return '#10161E';
  }

  private getOpenInnerPageColor(): string {
    const fallbackColor = this.contentType === 'ebook'
      ? this.getDefaultEBookInnerPageColor()
      : '#F6F1E5';
    if (!this.ebookBackground || this.ebookBackground.backgroundColor.length === 0) {
      return fallbackColor;
    }

    const normalized = this.ebookBackground.backgroundColor.replace(/\s+/g, '').toLowerCase();
    if (normalized === 'transparent'
      || normalized === 'rgba(0,0,0,0)'
      || normalized === '#0000'
      || normalized === '#00000000') {
      return fallbackColor;
    }

    return this.ebookBackground.backgroundColor;
  }

  private getDefaultEBookBackdropColor(): string {
    return ThemeManager.getInstance().isDarkThemeSync() ? '#121214' : '#FFFFFF';
  }

  private getDefaultEBookInnerPageColor(): string {
    return ThemeManager.getInstance().isDarkThemeSync() ? '#1C1C1E' : '#F6F1E5';
  }

  private getOpenBackdropOpacity(): number {
    return this.mode === TransitionMode.OPEN ? 1 : 0;
  }

  private hasOpenBackgroundImage(): boolean {
    if (this.contentType === 'manga') {
      return false;
    }
    return this.mode === TransitionMode.OPEN
      && this.ebookBackground !== null
      && this.ebookBackground.backgroundImagePath !== undefined
      && this.ebookBackground.backgroundImagePath.length > 0;
  }

  private getOpenBackgroundImagePath(): string {
    if (this.ebookBackground !== null
      && this.ebookBackground.backgroundImagePath !== undefined
      && this.ebookBackground.backgroundImagePath.length > 0) {
      return this.ebookBackground.backgroundImagePath;
    }
    return '';
  }

  private getOpenBackgroundImageOpacity(): number {
    if (this.contentType === 'manga') {
      return 0;
    }
    if (!this.ebookBackground) {
      return 0;
    }
    const base = this.ebookBackground.backgroundImageOpacity ?? 0.22;
    return Math.max(0, Math.min(0.55, base));
  }

  private getDisplayBookTitle(): string {
    if (this.bookTitle.length > 0) {
      return this.bookTitle;
    }
    return '正在打开作品';
  }

  private getDisplayBookAuthor(): string {
    if (this.bookAuthor.length > 0) {
      return this.bookAuthor;
    }
    return '作者信息加载中';
  }

  private getDisplayBookIntro(): string {
    if (this.bookIntro.length > 0) {
      return this.bookIntro;
    }
    return '阅读器正在准备章节内容，请稍候。';
  }

  private getDisplayLoadingPercentText(): string {
    const percent = Math.max(1, Math.min(100, Math.round(this.loadingProgress * 100)));
    return `${percent}%`;
  }

  private getDisplayLoadingBarWidth(): string {
    const percent = Math.max(2, Math.min(100, Math.round(this.loadingProgress * 100)));
    return `${percent}%`;
  }

  private shouldShowWaitingInfoPanel(): boolean {
    if (this.mode !== TransitionMode.OPEN) {
      return false;
    }
    if (this.currentPhase === TransitionPhase.COVER_LIFTING || this.currentPhase === TransitionPhase.COMPLETED) {
      return false;
    }
    return this.currentOpacity > 0.01;
  }

  private getWaitingInfoPanelWidth(): number {
    const coverBound = Math.max(260, this.currentWidth + 30);
    return Math.min(this.componentWidth * 0.82, coverBound);
  }

  private getWaitingInfoPanelX(): number {
    return (this.componentWidth - this.getWaitingInfoPanelWidth()) / 2;
  }

  private getWaitingInfoPanelY(): number {
    const suggestedTop = this.currentY + this.currentHeight + 16;
    const maxTop = Math.max(24, this.componentHeight - 176);
    return Math.max(16, Math.min(maxTop, suggestedTop));
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
   * 通过封面+内页+书脊阴影组合出 3D 翻书效果。
   */
  private renderOpenFrame(ctx: CanvasRenderingContext2D, w: number, h: number): void {
    // 透明画布，底色由 build 中的全屏背景层负责
    ctx.clearRect(0, 0, w, h);

    ctx.save();

    const spineX = this.currentX;
    const spineCenterY = this.currentY + this.currentHeight / 2;
    ctx.translate(spineX, spineCenterY);

    const maxAngle = Math.max(1, this.config.maxLiftAngle);
    const liftRatio = this.clamp01(this.liftAngle / maxAngle);
    const pageReveal = this.easeOutCubic(liftRatio);

    // 内页：在封面掀起时逐渐出现，作为“阅读器预览”
    if (pageReveal > 0.001) {
      ctx.save();
      const pageTop = -this.currentHeight / 2;
      const pageHeight = this.currentHeight;
      const pageWidth = this.currentWidth;
      const pageColor = this.getOpenInnerPageColor();
      ctx.globalAlpha = Math.min(1, 0.84 + pageReveal * 0.16);
      ctx.fillStyle = pageColor;
      ctx.fillRect(0, pageTop, pageWidth, pageHeight);

      const paperTone = ctx.createLinearGradient(0, pageTop, 0, pageTop + pageHeight);
      paperTone.addColorStop(0, `rgba(255, 255, 255, ${0.14 + pageReveal * 0.08})`);
      paperTone.addColorStop(0.52, 'rgba(255, 255, 255, 0.02)');
      paperTone.addColorStop(1, `rgba(0, 0, 0, ${0.06 + pageReveal * 0.05})`);
      ctx.fillStyle = paperTone;
      ctx.fillRect(0, pageTop, pageWidth, pageHeight);

      if (this.backgroundImagePixelMap && this.hasOpenBackgroundImage()) {
        ctx.save();
        ctx.globalAlpha = this.getOpenBackgroundImageOpacity() * (0.45 + pageReveal * 0.55);
        const imgInfo = this.backgroundImagePixelMap.getImageInfoSync();
        const imgWidth = imgInfo.size.width;
        const imgHeight = imgInfo.size.height;
        const destX = 0;
        const destY = pageTop;
        const destWidth = pageWidth;
        const destHeight = pageHeight;
        const scaleX = destWidth / imgWidth;
        const scaleY = destHeight / imgHeight;
        const scale = Math.max(scaleX, scaleY);
        const scaledWidth = imgWidth * scale;
        const scaledHeight = imgHeight * scale;
        const offsetX = destX + (destWidth - scaledWidth) / 2;
        const offsetY = destY + (destHeight - scaledHeight) / 2;
        ctx.beginPath();
        ctx.rect(destX, destY, destWidth, destHeight);
        ctx.clip();
        ctx.drawImage(this.backgroundImagePixelMap, offsetX, offsetY, scaledWidth, scaledHeight);
        ctx.restore();
      }

      // 内页边缘线，增强“纸张层叠”质感
      const foreEdgeWidth = Math.max(10, pageWidth * 0.09);
      const foreEdgeX = pageWidth - foreEdgeWidth;
      const foreEdge = ctx.createLinearGradient(foreEdgeX, 0, pageWidth, 0);
      foreEdge.addColorStop(0, `rgba(170, 137, 98, ${0.14 + pageReveal * 0.08})`);
      foreEdge.addColorStop(0.56, `rgba(246, 236, 220, ${0.58 + pageReveal * 0.18})`);
      foreEdge.addColorStop(1, `rgba(142, 111, 77, ${0.24 + pageReveal * 0.08})`);
      ctx.fillStyle = foreEdge;
      ctx.fillRect(foreEdgeX, pageTop, foreEdgeWidth, pageHeight);

      const foreEdgeCreaseWidth = Math.max(6, pageWidth * 0.03);
      const foreEdgeCrease = ctx.createLinearGradient(foreEdgeX - foreEdgeCreaseWidth, 0, foreEdgeX + 1, 0);
      foreEdgeCrease.addColorStop(0, 'rgba(0, 0, 0, 0)');
      foreEdgeCrease.addColorStop(1, `rgba(0, 0, 0, ${0.12 + pageReveal * 0.08})`);
      ctx.fillStyle = foreEdgeCrease;
      ctx.fillRect(foreEdgeX - foreEdgeCreaseWidth, pageTop, foreEdgeCreaseWidth + 1, pageHeight);

      ctx.strokeStyle = `rgba(96, 70, 42, ${0.14 + pageReveal * 0.1})`;
      ctx.lineWidth = 1;
      ctx.strokeRect(0.5, pageTop + 0.5, pageWidth - 1, pageHeight - 1);

      ctx.strokeStyle = `rgba(255, 255, 255, ${0.1 + pageReveal * 0.08})`;
      ctx.beginPath();
      ctx.moveTo(foreEdgeX + 0.5, pageTop + 2);
      ctx.lineTo(foreEdgeX + 0.5, pageTop + pageHeight - 2);
      ctx.stroke();

      // 书脊暗部
      const spineShadow = ctx.createLinearGradient(0, 0, pageWidth * 0.26, 0);
      spineShadow.addColorStop(0, `rgba(0, 0, 0, ${0.36 + pageReveal * 0.12})`);
      spineShadow.addColorStop(1, 'rgba(0, 0, 0, 0)');
      ctx.fillStyle = spineShadow;
      ctx.fillRect(0, pageTop, pageWidth * 0.26, pageHeight);

      // 封面投射到内页上的阴影
      const castWidth = Math.max(22, pageWidth * 0.24);
      const cast = ctx.createLinearGradient(0, 0, castWidth, 0);
      cast.addColorStop(0, `rgba(0, 0, 0, ${(1 - pageReveal) * 0.28})`);
      cast.addColorStop(1, 'rgba(0, 0, 0, 0)');
      ctx.fillStyle = cast;
      ctx.fillRect(0, pageTop, castWidth, pageHeight);

      ctx.restore();
    }

    // 封面变换
    if (this.config.enable3DEffect && this.liftAngle > 0.01) {
      const angleRad = this.liftAngle * Math.PI / 180;
      const scaleX = Math.max(0.04, Math.cos(angleRad));
      const skew = -Math.sin(angleRad) * 0.08;
      ctx.transform(scaleX, 0, skew, 1, 0, 0);
    }

    if (this.config.enableShadow && this.shadowOpacity > 0) {
      const shadowStrength = this.shadowOpacity * (0.5 + liftRatio * 0.4);
      ctx.shadowColor = `rgba(0, 0, 0, ${shadowStrength})`;
      ctx.shadowBlur = 14 + this.liftAngle * 0.45;
      ctx.shadowOffsetX = Math.sin(this.liftAngle * Math.PI / 180) * 18;
      ctx.shadowOffsetY = 6;
    }

    ctx.globalAlpha = this.currentOpacity;

    if (this.coverPixelMap) {
      let drawWidth = this.currentWidth;
      let drawHeight = this.currentHeight;
      let drawX = 0;
      let drawY = -this.currentHeight / 2;

      if (this.coverOriginalWidth > 0 && this.coverOriginalHeight > 0) {
        const originalAspect = this.coverOriginalWidth / this.coverOriginalHeight;
        const targetAspect = this.currentWidth / this.currentHeight;

        if (originalAspect > targetAspect) {
          drawHeight = this.currentHeight;
          drawWidth = this.currentHeight * originalAspect;
          drawX = (this.currentWidth - drawWidth) / 2;
          drawY = -this.currentHeight / 2;
        } else {
          drawWidth = this.currentWidth;
          drawHeight = this.currentWidth / originalAspect;
          drawX = 0;
          drawY = -drawHeight / 2;
        }
      }

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
      ctx.fillStyle = '#E0E0E0';
      ctx.fillRect(0, -this.currentHeight / 2, this.currentWidth, this.currentHeight);
    }

    // 书脊高光
    ctx.save();
    ctx.globalAlpha = this.currentOpacity * 0.9;
    const spineHighlight = ctx.createLinearGradient(0, 0, Math.max(4, this.currentWidth * 0.03), 0);
    spineHighlight.addColorStop(0, 'rgba(255, 255, 255, 0.28)');
    spineHighlight.addColorStop(1, 'rgba(255, 255, 255, 0)');
    ctx.fillStyle = spineHighlight;
    ctx.fillRect(0, -this.currentHeight / 2, Math.max(4, this.currentWidth * 0.03), this.currentHeight);
    ctx.restore();

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
      if (this.mode === TransitionMode.CLOSE && (this.localReaderPixelMap !== null || this.readerContentImagePath.length > 0)) {
        // ========== 底层：阅读器截图（全屏，仅渐隐） ==========
        if (this.localReaderPixelMap) {
          Image(this.localReaderPixelMap)
            .width('100%')
            .height('100%')
            .position({ x: 0, y: 0 })
            .objectFit(ImageFit.Fill)
            .opacity(this.closeReaderOpacity)
            .backgroundColor(Color.Transparent)
        } else if (this.readerContentImagePath.length > 0) {
          Image(`file://${this.readerContentImagePath}`)
            .width('100%')
            .height('100%')
            .position({ x: 0, y: 0 })
            .objectFit(ImageFit.Fill)
            .opacity(this.closeReaderOpacity)
            .backgroundColor(Color.Transparent)
            .onComplete(() => {
              logger.info(TAG, `📷 关闭动画截图加载完成: ${this.readerContentImagePath}`);
            })
            .onError((error) => {
              logger.error(TAG, `📷 关闭动画截图加载失败: ${JSON.stringify(error)}`);
            })
        }
        
        // ========== 上层：3D书本（显现 -> 合上 -> 移回封面） ==========
        if (this.closeBookOpacity > 0.001) {
          Stack() {
            // 书页主体
            Column()
              .width('100%')
              .height('100%')
              .backgroundColor('#F6F1E5')
              .borderRadius(6)

            // 书脊阴影
            Row()
              .width(7)
              .height('100%')
              .position({ x: 0, y: 0 })
              .backgroundColor('rgba(42, 28, 16, 0.16)')

            // 封面从打开角度逐步合上
            if (this.coverImagePath.length > 0) {
              Image(this.coverImagePath.startsWith('/') ? `file://${this.coverImagePath}` : this.coverImagePath)
                .width('100%')
                .height('100%')
                .objectFit(ImageFit.Cover)
                .borderRadius(6)
                .opacity(0.1 + 0.9 * this.coverFlipProgress)
                .rotate({
                  x: 0,
                  y: 1,
                  z: 0,
                  angle: -90 * (1 - this.coverFlipProgress),
                  centerX: '0%',
                  centerY: '50%',
                  perspective: 900
                })
            }
          }
          .width(this.currentWidth)
          .height(this.currentHeight)
          .position({ x: this.currentX, y: this.currentY })
          .scale({ x: this.closeBookScale, y: this.closeBookScale })
          .opacity(this.closeBookOpacity)
          .shadow({
            radius: 14 + 8 * this.coverFlipProgress,
            color: `rgba(0, 0, 0, ${this.shadowOpacity})`,
            offsetX: -8 * this.coverFlipProgress,
            offsetY: 6
          })
        }
      } else {
        // 翻开模式或无截图
        if (this.mode === TransitionMode.OPEN) {
          Stack() {
            Column()
              .width('100%')
              .height('100%')
              .backgroundColor(this.getOpenBackdropColor())

            if (this.hasOpenBackgroundImage()) {
              Image(this.toRenderableImageSource(this.getOpenBackgroundImagePath()))
                .width('100%')
                .height('100%')
                .objectFit(ImageFit.Cover)
                .opacity(this.getOpenBackgroundImageOpacity())
            }
          }
          .width('100%')
          .height('100%')
          .expandSafeArea([SafeAreaType.SYSTEM, SafeAreaType.CUTOUT], [SafeAreaEdge.TOP, SafeAreaEdge.BOTTOM, SafeAreaEdge.START, SafeAreaEdge.END])
          .opacity(this.getOpenBackdropOpacity())
        }

        Stack() {
          Canvas(this.canvasContext)
            .width('100%')
            .height('100%')
            .onReady(() => {
              logger.info(TAG, `Canvas已就绪, mode=${this.mode}, imagePath=${this.readerContentImagePath.length > 0 ? '有' : '无'}`);
              this.renderFrame();
            })

          // 网络图片封面覆盖层：用于无法生成 coverPixelMap 的网络图
          if (this.mode === TransitionMode.OPEN && this.isSystemResource && this.coverImagePath.length > 0 &&
              (this.coverImagePath.startsWith('http://')
                || this.coverImagePath.startsWith('https://')
                || this.coverImagePath.startsWith('app.media.'))) {
            Image(this.toRenderableImageSource(this.coverImagePath))
              .width(this.currentWidth)
              .height(this.currentHeight)
              .position({ x: this.currentX, y: this.currentY })
              .objectFit(ImageFit.Cover)
              .opacity(this.currentOpacity)
              .borderRadius(4)
              .rotate({
                x: 0,
                y: 1,
                z: 0,
                angle: -this.liftAngle,
                centerX: '0%',
                centerY: '50%',
                perspective: 1200
              })
              .shadow({
                radius: 12,
                color: `rgba(0, 0, 0, ${0.2 + this.shadowOpacity * 0.35})`,
                offsetX: Math.sin(this.liftAngle * Math.PI / 180) * 10,
                offsetY: 4
              })
          }
        }
        .width('100%')
        .height('100%')
        .expandSafeArea([SafeAreaType.SYSTEM, SafeAreaType.CUTOUT], [SafeAreaEdge.TOP, SafeAreaEdge.BOTTOM, SafeAreaEdge.START, SafeAreaEdge.END])
        .opacity(this.mode === TransitionMode.OPEN
          ? (this.currentPhase === TransitionPhase.COMPLETED ? 0 : 1)
          : (this.animationCompleted ? 0 : 1))
        .animation({ duration: 120, curve: Curve.EaseOut })

        if (this.shouldShowWaitingInfoPanel()) {
          Column({ space: 6 }) {
            Text(this.getDisplayBookTitle())
              .fontSize(18)
              .fontWeight(FontWeight.Medium)
              .fontColor('#F5F7FB')
              .maxLines(1)
              .textOverflow({ overflow: TextOverflow.Ellipsis })

            Text(this.getDisplayBookAuthor())
              .fontSize(13)
              .fontColor('rgba(236, 240, 246, 0.92)')
              .maxLines(1)
              .textOverflow({ overflow: TextOverflow.Ellipsis })

            Column({ space: 4 }) {
              Stack() {
                Row()
                  .width('100%')
                  .height(4)
                  .backgroundColor('rgba(255, 255, 255, 0.2)')
                  .borderRadius(999)

                Row()
                  .width(this.getDisplayLoadingBarWidth())
                  .height(4)
                  .backgroundColor('#8ACFFF')
                  .borderRadius(999)
                  .animation({ duration: 140, curve: Curve.EaseOut })
              }
              .width('100%')
              .height(4)

              Text(`加载进度 ${this.getDisplayLoadingPercentText()}`)
                .fontSize(11)
                .fontColor('rgba(214, 223, 238, 0.85)')
            }
            .width('100%')
            .padding({ top: 2, bottom: 2 })

            Text(this.getDisplayBookIntro())
              .fontSize(12)
              .lineHeight(18)
              .fontColor('rgba(223, 228, 238, 0.82)')
              .maxLines(3)
              .textOverflow({ overflow: TextOverflow.Ellipsis })
          }
          .width(this.getWaitingInfoPanelWidth())
          .position({ x: this.getWaitingInfoPanelX(), y: this.getWaitingInfoPanelY() })
          .padding({ left: 14, right: 14, top: 12, bottom: 12 })
          .backgroundColor('rgba(8, 12, 18, 0.58)')
          .borderRadius(12)
          .opacity(this.currentOpacity)
          .animation({ duration: 180, curve: Curve.EaseOut })
        }
      }
    }
    .width('100%')
    .height('100%')
    .backgroundColor(this.mode === TransitionMode.OPEN ? this.getOpenBackdropColor() : Color.Transparent)
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
