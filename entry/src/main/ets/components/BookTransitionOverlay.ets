/**
 * 书籍过渡动画全局覆盖层组件
 * 
 * 功能：
 * 1. 作为全局覆盖层显示在所有页面之上
 * 2. 管理翻开/关闭过渡动画的显示状态
 * 3. 提供简洁的API供外部调用
 * 4. 支持与Navigation架构集成
 */

import { logger } from '../Utils/Logger';
import { image } from '@kit.ImageKit';
import { componentUtils, componentSnapshot } from '@kit.ArkUI';
import { fileIo } from '@kit.CoreFileKit';
import { SettingsManager, SettingKeys } from '../Framework/Managers/SettingsManager';
import { ThemeManager } from '../Framework/Managers/ThemeManager';
import { TextReaderSettings, DEFAULT_TEXT_READER_SETTINGS, BackgroundType } from '../Models/TextReaderModels';
import { 
  BookOpenTransition, 
  TransitionMode, 
  TransitionPhase,
  CoverPosition,
  BookTransitionConfig
} from './BookOpenTransition';
import { AnimationSettingsManager } from '../Framework/Animation/AnimationSettingsManager';

const TAG = 'BookTransitionOverlay';
const BOOK_TRANSITION_OVERLAY_ROOT_ID = 'book_transition_overlay_root';
const DEFAULT_COVER_POSITION: CoverPosition = {
  x: 16,
  y: 120,
  width: 140,
  height: 200
};

interface TransitionCoordinateOffset {
  x: number;
  y: number;
  useScreenOffset: boolean;
}

/**
 * 过渡动画请求参数
 */
export interface TransitionRequest {
  mode: TransitionMode;
  coverImagePath: string;
  coverPosition: CoverPosition;
  readerContentPixelMap?: image.PixelMap;
  targetBookId?: string;
  targetBookType?: 'manga' | 'ebook' | 'novel';
  bookTitle?: string;
  bookAuthor?: string;
  bookIntro?: string;
}

export interface BookTransitionMetaInfo {
  title?: string;
  author?: string;
  intro?: string;
}

/**
 * 电子书背景设置（用于翻开动画）
 */
export interface EBookBackgroundSettings {
  backgroundColor: string;           // 背景色
  backgroundImagePath?: string;      // 背景图片路径
  backgroundImageOpacity?: number;   // 背景图片不透明度 (0-1)
}

/**
 * 全局过渡状态（用于AppStorage共享）
 */
export class GlobalTransitionState {
  isActive: boolean = false;
  mode: TransitionMode = TransitionMode.OPEN;
  coverImagePath: string = '';
  coverPosition: CoverPosition = { x: 0, y: 0, width: 100, height: 150 };
  closeCoverComponentId: string = '';
  readerContentPixelMap: image.PixelMap | null = null;
  readerContentImagePath: string = '';  // 压缩后的临时截图路径
  isReaderReady: boolean = false;
  readerLoadProgress: number = 0;
  targetBookId: string = '';
  targetBookType: 'manga' | 'ebook' | 'novel' = 'manga';
  ebookBackground: EBookBackgroundSettings | null = null;  // 电子书背景设置
  bookTitle: string = '';
  bookAuthor: string = '';
  bookIntro: string = '';
}

/**
 * 过渡动画控制器（单例）
 * 用于从任何地方触发过渡动画
 */
export class TransitionController {
  private static instance: TransitionController | null = null;
  private static readonly OPEN_READER_READY_HIDE_DELAY_MS: number = 780;
  private static readonly MANGA_TRANSITION_BACKGROUND: string = '#000000';
  private static readonly NOVEL_TRANSITION_BACKGROUND: string = '#F5F0E1';
  private static readonly EBOOK_TRANSITION_BACKGROUND_LIGHT: string = '#FFFFFF';
  private static readonly EBOOK_TRANSITION_BACKGROUND_DARK: string = '#121214';
  
  // 状态变化回调
  private onStateChange: ((state: GlobalTransitionState) => void) | null = null;
  private onOpenComplete: (() => void) | null = null;
  private onCloseComplete: (() => void) | null = null;
  private onCancelCallback: (() => void) | null = null;
  
  // 当前状态
  private currentState: GlobalTransitionState = new GlobalTransitionState();
  private settingsManager: SettingsManager = SettingsManager.getInstance();
  
  // 保存翻开动画的封面位置，用于关闭动画复用
  private lastOpenCoverPosition: CoverPosition | null = null;
  // 保存翻开动画的封面图片路径，用于关闭动画复用（封面翻页盖住效果）
  private lastOpenCoverImagePath: string = '';
  
  // 取消相关
  private isCancelling: boolean = false;
  private pendingNavigationTimer: number = -1;
  private openReadyHideTimer: number = -1;

  private isDefaultCoverPosition(coverPosition: CoverPosition): boolean {
    return coverPosition.x === DEFAULT_COVER_POSITION.x
      && coverPosition.y === DEFAULT_COVER_POSITION.y
      && coverPosition.width === DEFAULT_COVER_POSITION.width
      && coverPosition.height === DEFAULT_COVER_POSITION.height;
  }

  private isValidCoverPosition(coverPosition: CoverPosition): boolean {
    return coverPosition.width > 0 && coverPosition.height > 0;
  }
  
  private constructor() {
    logger.info(TAG, 'TransitionController 初始化');
  }
  
  public static getInstance(): TransitionController {
    if (!TransitionController.instance) {
      TransitionController.instance = new TransitionController();
    }
    return TransitionController.instance;
  }
  
  /**
   * 设置状态变化回调（由覆盖层组件调用）
   */
  public setStateChangeCallback(callback: (state: GlobalTransitionState) => void): void {
    this.onStateChange = callback;
  }
  
  /**
   * 开始翻开过渡动画
   * @param coverImagePath 封面图片路径
   * @param coverPosition 封面在屏幕上的位置
   * @param targetBookId 目标书籍ID
   * @param targetBookType 目标书籍类型
   * @param onComplete 动画完成回调
   * @param ebookBackground 电子书背景设置（可选，仅电子书使用）
   */
  public startOpenTransition(
    coverImagePath: string,
    coverPosition: CoverPosition,
    targetBookId: string,
    targetBookType: 'manga' | 'ebook' | 'novel',
    onComplete?: () => void,
    ebookBackground?: EBookBackgroundSettings,
    metaInfo?: BookTransitionMetaInfo
  ): void {
    this.clearOpenReadyHideTimer();

    // 检查动画是否启用
    const animationSettingsManager = AnimationSettingsManager.getInstance();
    if (!animationSettingsManager.isBookOpenAnimationEnabled()) {
      logger.info(TAG, `书籍打开动画已禁用，直接执行回调: bookId=${targetBookId}`);
      // 保存封面位置（用于关闭动画）
      const isDefaultPosition = this.isDefaultCoverPosition(coverPosition);
      if (!isDefaultPosition) {
        this.lastOpenCoverPosition = coverPosition;
      }
      // 直接执行回调，跳过动画
      if (onComplete) {
        onComplete();
      }
      return;
    }
    
    logger.info(TAG, `开始翻开过渡: bookId=${targetBookId}, type=${targetBookType}, 有背景设置=${ebookBackground ? '是' : '否'}`);
    
    // [修复] 重置取消状态，防止上次残留的 isCancelling=true 导致 cancelTransition() 失效
    if (this.isCancelling) {
      logger.warn(TAG, '检测到残留的 isCancelling=true，在新的翻开过渡开始前强制重置');
      this.isCancelling = false;
      this.onCancelCallback = null;
    }
    
    // 只在位置有效时保存（避免默认位置覆盖正确位置）
    const isDefaultPosition = this.isDefaultCoverPosition(coverPosition);
    if (!isDefaultPosition) {
      this.lastOpenCoverPosition = coverPosition;
      logger.info(TAG, `保存封面位置: pos=(${coverPosition.x}, ${coverPosition.y}), size=${coverPosition.width}x${coverPosition.height}`);
    } else {
      logger.warn(TAG, `跳过保存默认位置，保留已有位置: ${this.lastOpenCoverPosition ? `pos=(${this.lastOpenCoverPosition.x}, ${this.lastOpenCoverPosition.y})` : '无'}`);
    }
    
    // 保存封面图片路径，用于关闭动画的封面翻页盖住效果
    if (coverImagePath && coverImagePath.length > 0) {
      this.lastOpenCoverImagePath = coverImagePath;
      logger.info(TAG, `保存封面图片路径: ${coverImagePath.substring(0, 60)}`);
    }

    const resolvedBackground = this.resolveOpenTransitionBackground(targetBookType, targetBookId, ebookBackground);
    
    this.currentState = {
      isActive: true,
      mode: TransitionMode.OPEN,
      coverImagePath: coverImagePath,
      coverPosition: coverPosition,
      closeCoverComponentId: '',
      readerContentPixelMap: null,
      readerContentImagePath: '',
      isReaderReady: false,
      readerLoadProgress: 0.06,
      targetBookId: targetBookId,
      targetBookType: targetBookType,
      ebookBackground: resolvedBackground,
      bookTitle: metaInfo?.title || '',
      bookAuthor: metaInfo?.author || '',
      bookIntro: metaInfo?.intro || ''
    };
    
    this.onOpenComplete = onComplete || null;
    this.notifyStateChange();
  }

  private resolveOpenTransitionBackground(
    targetBookType: 'manga' | 'ebook' | 'novel',
    targetBookId: string,
    providedBackground?: EBookBackgroundSettings
  ): EBookBackgroundSettings | null {
    if (targetBookType === 'manga') {
      return {
        backgroundColor: TransitionController.MANGA_TRANSITION_BACKGROUND
      };
    }

    if (this.hasUsableBackgroundSetting(providedBackground)) {
      const providedColor = providedBackground?.backgroundColor ?? '';
      const hasBackgroundColor = providedBackground !== undefined
        && providedColor.length > 0;
      const safeBackgroundColor = hasBackgroundColor
        ? providedColor
        : (targetBookType === 'novel'
          ? TransitionController.NOVEL_TRANSITION_BACKGROUND
          : this.getDefaultEBookTransitionBackground());
      return {
        backgroundColor: safeBackgroundColor,
        backgroundImagePath: providedBackground?.backgroundImagePath,
        backgroundImageOpacity: providedBackground?.backgroundImageOpacity
      };
    }

    if (targetBookType === 'novel') {
      const novelBackground = this.resolveNovelBackground(targetBookId);
      if (novelBackground) {
        return novelBackground;
      }
      return {
        backgroundColor: TransitionController.NOVEL_TRANSITION_BACKGROUND
      };
    }

    return {
      backgroundColor: this.getDefaultEBookTransitionBackground()
    };
  }

  private getDefaultEBookTransitionBackground(): string {
    return ThemeManager.getInstance().isDarkThemeSync()
      ? TransitionController.EBOOK_TRANSITION_BACKGROUND_DARK
      : TransitionController.EBOOK_TRANSITION_BACKGROUND_LIGHT;
  }

  private hasUsableBackgroundSetting(background?: EBookBackgroundSettings): boolean {
    if (!background) {
      return false;
    }
    const hasColor = typeof background.backgroundColor === 'string' && background.backgroundColor.length > 0;
    const hasImage = typeof background.backgroundImagePath === 'string' && background.backgroundImagePath.length > 0;
    return hasColor || hasImage;
  }

  private resolveNovelBackground(targetBookId: string): EBookBackgroundSettings | null {
    const settingsKeys: string[] = [];
    if (targetBookId.length > 0) {
      settingsKeys.push(`${SettingKeys.NOVEL_READER_SETTINGS}_${targetBookId}`);
    }
    settingsKeys.push(SettingKeys.NOVEL_READER_SETTINGS);

    for (let i = 0; i < settingsKeys.length; i++) {
      const settingsKey = settingsKeys[i];
      const storedValue = this.settingsManager.getString(settingsKey, '');
      if (storedValue.length === 0) {
        continue;
      }

      const settings = this.settingsManager.getJSON<TextReaderSettings>(settingsKey, DEFAULT_TEXT_READER_SETTINGS);
      const mapped = this.mapNovelTextBackground(settings);
      if (mapped) {
        logger.info(TAG, `小说过渡背景匹配成功: key=${settingsKey}, color=${mapped.backgroundColor}, image=${mapped.backgroundImagePath ? '有' : '无'}`);
        return mapped;
      }
    }

    return null;
  }

  private mapNovelTextBackground(settings: TextReaderSettings): EBookBackgroundSettings | null {
    if (!settings || !settings.background) {
      return null;
    }

    const background = settings.background;
    if (background.type === BackgroundType.IMAGE) {
      const hasImagePath = typeof background.imagePath === 'string' && background.imagePath.length > 0;
      if (hasImagePath) {
        return {
          backgroundColor: TransitionController.NOVEL_TRANSITION_BACKGROUND,
          backgroundImagePath: background.imagePath as string,
          backgroundImageOpacity: this.clampBackgroundOpacity(background.imageOpacity ?? 0.3)
        };
      }
      return {
        backgroundColor: TransitionController.NOVEL_TRANSITION_BACKGROUND
      };
    }

    if (background.type === BackgroundType.GRADIENT) {
      const hasGradientStart = typeof background.gradientStart === 'string' && background.gradientStart.length > 0;
      const hasFallbackColor = typeof background.color === 'string' && background.color.length > 0;
      const gradientColor = hasGradientStart
        ? (background.gradientStart as string)
        : (hasFallbackColor
          ? (background.color as string)
          : TransitionController.NOVEL_TRANSITION_BACKGROUND);
      return {
        backgroundColor: gradientColor
      };
    }

    const hasColor = typeof background.color === 'string' && background.color.length > 0;
    const color = hasColor
      ? (background.color as string)
      : TransitionController.NOVEL_TRANSITION_BACKGROUND;
    return {
      backgroundColor: color
    };
  }

  private clampBackgroundOpacity(value: number): number {
    return Math.max(0, Math.min(1, value));
  }
  
  /**
   * 开始关闭过渡动画
   * @param coverPosition 封面在屏幕上的目标位置
   * @param readerContentPixelMap 阅读器当前内容截图（可选，已弃用）
   * @param onComplete 动画完成回调
   * @param readerContentImagePath 压缩后的截图临时文件路径（推荐使用）
   */
  public startCloseTransition(
    coverPosition: CoverPosition,
    readerContentPixelMap?: image.PixelMap,
    onComplete?: () => void,
    readerContentImagePath?: string,
    closeCoverComponentId?: string
  ): void {
    this.clearOpenReadyHideTimer();

    // 检查动画是否启用
    const animationSettingsManager = AnimationSettingsManager.getInstance();
    if (!animationSettingsManager.isBookCloseAnimationEnabled()) {
      logger.info(TAG, '书籍关闭动画已禁用，直接执行回调');
      // 直接执行回调，跳过动画
      if (onComplete) {
        onComplete();
      }
      return;
    }
    
    logger.info(TAG, '开始关闭过渡');
    
    // [修复] 重置取消状态，防止上次残留的 isCancelling=true 导致 cancelTransition() 失效
    if (this.isCancelling) {
      logger.warn(TAG, '检测到残留的 isCancelling=true，在新的关闭过渡开始前强制重置');
      this.isCancelling = false;
      this.onCancelCallback = null;
    }
    
    // 关闭开始时先锁定一个稳定基础目标；淡出前只允许动画组件对明确的窗口坐标基准差做小幅补偿。
    let finalCoverPosition: CoverPosition;
    
    if (this.isValidCoverPosition(coverPosition) && !this.isDefaultCoverPosition(coverPosition)) {
      logger.info(TAG, `使用关闭时测量的封面位置: pos=(${coverPosition.x}, ${coverPosition.y}), size=${coverPosition.width}x${coverPosition.height}`);
      finalCoverPosition = coverPosition;
      this.lastOpenCoverPosition = coverPosition;
    } else if (this.lastOpenCoverPosition && this.isValidCoverPosition(this.lastOpenCoverPosition)) {
      logger.info(TAG, `当前封面位置不可用，回退到翻开动画保存的位置: pos=(${this.lastOpenCoverPosition.x}, ${this.lastOpenCoverPosition.y}), size=${this.lastOpenCoverPosition.width}x${this.lastOpenCoverPosition.height}`);
      finalCoverPosition = this.lastOpenCoverPosition;
    } else if (this.isValidCoverPosition(coverPosition)) {
      logger.warn(TAG, `只能使用默认封面位置: pos=(${coverPosition.x}, ${coverPosition.y}), size=${coverPosition.width}x${coverPosition.height}`);
      finalCoverPosition = coverPosition;
    } else {
      // 都无效时使用默认位置
      logger.warn(TAG, '无法获取封面位置，使用默认位置');
      finalCoverPosition = DEFAULT_COVER_POSITION;
    }
    
    this.currentState.isActive = true;
    this.currentState.mode = TransitionMode.CLOSE;
    this.currentState.coverPosition = finalCoverPosition;
    this.currentState.closeCoverComponentId = closeCoverComponentId || '';
    this.currentState.readerContentPixelMap = readerContentPixelMap || null;
    this.currentState.readerContentImagePath = readerContentImagePath || '';
    this.currentState.isReaderReady = true;
    
    // 恢复翻开动画保存的封面图片路径，用于关闭动画的封面翻页盖住效果
    if (this.lastOpenCoverImagePath && this.lastOpenCoverImagePath.length > 0) {
      this.currentState.coverImagePath = this.lastOpenCoverImagePath;
      logger.info(TAG, `恢复封面图片路径: ${this.lastOpenCoverImagePath.substring(0, 60)}`);
    }
    
    logger.info(TAG, `关闭过渡状态: imagePath=${readerContentImagePath ? '有' : '无'}, pixelMap=${readerContentPixelMap ? '有' : '无'}, coverImagePath=${this.currentState.coverImagePath ? '有' : '无'}`);
    
    this.onCloseComplete = onComplete || null;
    this.notifyStateChange();
  }
  
  /**
   * 准备关闭过渡（显示全屏遮罩层，用于截图前冻结画面）
   * @param coverPosition 封面目标位置
   */
  public prepareCloseTransition(coverPosition: CoverPosition): void {
    logger.info(TAG, '准备关闭过渡（显示遮罩层）');
    
    // 计算最终封面位置
    let finalCoverPosition: CoverPosition;
    if (this.isValidCoverPosition(coverPosition) && !this.isDefaultCoverPosition(coverPosition)) {
      finalCoverPosition = coverPosition;
      this.lastOpenCoverPosition = coverPosition;
    } else if (this.lastOpenCoverPosition && this.isValidCoverPosition(this.lastOpenCoverPosition)) {
      finalCoverPosition = this.lastOpenCoverPosition;
    } else if (this.isValidCoverPosition(coverPosition)) {
      finalCoverPosition = coverPosition;
    } else {
      finalCoverPosition = DEFAULT_COVER_POSITION;
    }
    
    // 设置准备状态（显示全屏遮罩但不开始动画）
    this.currentState.isActive = true;
    this.currentState.mode = TransitionMode.CLOSE;
    this.currentState.coverPosition = finalCoverPosition;
    this.currentState.closeCoverComponentId = '';
    this.currentState.readerContentPixelMap = null;
    this.currentState.readerContentImagePath = '';
    this.currentState.isReaderReady = false;  // 标记为未就绪，不开始动画
    
    this.notifyStateChange();
  }
  
  /**
   * 使用截图开始关闭过渡动画（在prepareCloseTransition之后调用）
   * @param readerContentPixelMap 阅读器截图
   * @param onComplete 完成回调
   * @param readerContentImagePath 截图文件路径
   */
  public startCloseTransitionWithCapture(
    readerContentPixelMap?: image.PixelMap,
    onComplete?: () => void,
    readerContentImagePath?: string
  ): void {
    logger.info(TAG, `开始关闭过渡动画（带截图）: imagePath=${readerContentImagePath ? '有' : '无'}`);
    
    // 更新截图数据
    this.currentState.readerContentPixelMap = readerContentPixelMap || null;
    this.currentState.readerContentImagePath = readerContentImagePath || '';
    this.currentState.isReaderReady = true;  // 标记为就绪，开始动画
    this.currentState.closeCoverComponentId = '';
    
    this.onCloseComplete = onComplete || null;
    this.notifyStateChange();
  }

  public setReaderLoadingProgress(progress: number): void {
    if (!this.currentState.isActive || this.currentState.mode !== TransitionMode.OPEN) {
      return;
    }
    if (this.currentState.isReaderReady) {
      return;
    }

    const normalized = this.clampBackgroundOpacity(progress > 1 ? progress / 100 : progress);
    if (normalized <= this.currentState.readerLoadProgress + 0.001) {
      return;
    }

    this.currentState.readerLoadProgress = normalized;
    this.notifyStateChange();
  }
  
  /**
   * 标记阅读器已就绪（翻开模式时调用）
   * 阅读器加载完成后调用此方法，覆盖层会淡出消失
   */
  public setReaderReady(): void {
    if (!this.currentState.isActive || this.currentState.mode !== TransitionMode.OPEN) {
      return;
    }
    if (this.currentState.isReaderReady) {
      logger.debug(TAG, '阅读器就绪信号重复，忽略本次触发');
      return;
    }

    logger.info(TAG, '阅读器已就绪，开始淡出覆盖层');
    this.currentState.isReaderReady = true;
    this.currentState.readerLoadProgress = 1;
    this.notifyStateChange();

    // 延迟一小段时间后隐藏覆盖层，让淡出动画有时间播放
    this.clearOpenReadyHideTimer();
    this.openReadyHideTimer = setTimeout(() => {
      this.openReadyHideTimer = -1;
      if (!this.currentState.isActive || this.currentState.mode !== TransitionMode.OPEN) {
        return;
      }
      this.currentState = new GlobalTransitionState();
      this.notifyStateChange();
      logger.info(TAG, '覆盖层已隐藏');
    }, TransitionController.OPEN_READER_READY_HIDE_DELAY_MS);
  }
  
  /**
   * 动画完成回调（由覆盖层组件调用）
   * 翻开模式：触发导航但保持覆盖层可见，等待setReaderReady
   * 关闭模式：直接完成并隐藏覆盖层
   */
  public onAnimationComplete(): void {
    logger.info(TAG, `动画完成: mode=${this.currentState.mode}`);
    
    const mode = this.currentState.mode;
    
    if (mode === TransitionMode.OPEN) {
      // 翻开模式：触发导航但保持覆盖层可见（黑色背景）
      // 等待阅读器加载完成后call setReaderReady()来隐藏覆盖层
      if (this.onOpenComplete) {
        this.onOpenComplete();
        this.onOpenComplete = null;
      }
      // 不重置状态，保持覆盖层可见
    } else if (mode === TransitionMode.CLOSE) {
      // 关闭模式：直接完成并确保状态重置
      logger.info(TAG, '关闭动画完成，重置状态');
      this.clearOpenReadyHideTimer();
      
      // 先保存回调引用
      const closeCallback = this.onCloseComplete;
      this.onCloseComplete = null;
      
      // 重置状态（确保isActive=false，组件会被移除）
      this.currentState = new GlobalTransitionState();
      this.notifyStateChange();
      
      // 延迟执行回调，确保UI状态已更新
      if (closeCallback) {
        setTimeout(() => {
          closeCallback();
        }, 50);
      }
    }
  }
  
  /**
   * 强制重置状态（用于异常情况恢复）
   */
  public forceReset(): void {
    logger.warn(TAG, '强制重置过渡动画状态');
    this.isCancelling = false;
    this.onOpenComplete = null;
    this.onCloseComplete = null;
    this.onCancelCallback = null;
    if (this.pendingNavigationTimer !== -1) {
      clearTimeout(this.pendingNavigationTimer);
      this.pendingNavigationTimer = -1;
    }
    this.clearOpenReadyHideTimer();
    this.currentState = new GlobalTransitionState();
    this.notifyStateChange();
  }
  
  /**
   * 取消过渡动画（带渐隐效果）
   * @param onCancel 取消完成后的回调
   */
  public cancelTransition(onCancel?: () => void): void {
    if (!this.currentState.isActive || this.isCancelling) {
      return;
    }
    
    logger.info(TAG, '取消过渡动画（带渐隐效果）');
    this.isCancelling = true;
    this.onCancelCallback = onCancel || null;
    
    // 清除待执行的导航
    if (this.pendingNavigationTimer !== -1) {
      clearTimeout(this.pendingNavigationTimer);
      this.pendingNavigationTimer = -1;
    }
    this.clearOpenReadyHideTimer();
    
    // 清除完成回调（不执行跳转）
    this.onOpenComplete = null;
    this.onCloseComplete = null;
    
    // 通知组件开始渐隐
    this.currentState.isActive = false;  // 触发渐隐动画
    this.notifyStateChange();
  }
  
  /**
   * 取消动画渐隐完成
   */
  public onCancelComplete(): void {
    logger.info(TAG, '取消动画渐隐完成');
    this.isCancelling = false;
    this.clearOpenReadyHideTimer();
    this.currentState = new GlobalTransitionState();
    
    if (this.onCancelCallback) {
      this.onCancelCallback();
      this.onCancelCallback = null;
    }
    
    this.notifyStateChange();
  }
  
  /**
   * 设置待执行的导航定时器（用于取消）
   */
  public setPendingNavigationTimer(timer: number): void {
    this.pendingNavigationTimer = timer;
  }
  
  /**
   * 是否正在取消动画
   */
  public isCancellingTransition(): boolean {
    return this.isCancelling;
  }
  
  /**
   * 获取当前状态
   */
  public getState(): GlobalTransitionState {
    return this.currentState;
  }
  
  /**
   * 是否正在过渡中
   */
  public isTransitioning(): boolean {
    return this.currentState.isActive;
  }
  
  /**
   * 通知状态变化
   */
  private notifyStateChange(): void {
    if (this.onStateChange) {
      this.onStateChange(this.currentState);
    }
  }

  private clearOpenReadyHideTimer(): void {
    if (this.openReadyHideTimer !== -1) {
      clearTimeout(this.openReadyHideTimer);
      this.openReadyHideTimer = -1;
    }
  }
}

/**
 * 全局过渡动画覆盖层组件
 * 应该放在应用根组件中，作为最顶层覆盖
 */
@Component
export struct BookTransitionOverlay {
  // 过渡状态
  @State private isActive: boolean = false;
  @State private mode: TransitionMode = TransitionMode.OPEN;
  @State private targetBookType: 'manga' | 'ebook' | 'novel' = 'manga';
  @State private coverImagePath: string = '';
  @State private coverPosition: CoverPosition = { x: 0, y: 0, width: 100, height: 150 };
  @State private closeCoverComponentId: string = '';
  @State private readerContentPixelMap: image.PixelMap | null = null;
  @State private readerContentImagePath: string = '';  // 压缩后的截图临时文件路径
  @State private isReaderReady: boolean = false;
  @State private readerLoadProgress: number = 0;
  @State private ebookBackground: EBookBackgroundSettings | null = null;  // 电子书背景设置
  @State private bookTitle: string = '';
  @State private bookAuthor: string = '';
  @State private bookIntro: string = '';
  
  // 动画配置
  private config: BookTransitionConfig = {
    coverMoveDuration: 520,
    liftDuration: 360,
    transitionDuration: 300,
    shrinkDuration: 400,
    returnDuration: 350,
    fadeDuration: 200,
    maxLiftAngle: 74,  // 柔和一些，避免翻盖过猛
    shadowIntensity: 0.6,
    enableShadow: true,
    enable3DEffect: true,
    centerScale: 0.7,
    minShrinkScale: 0.15
  };
  
  // 控制器引用
  private controller: TransitionController = TransitionController.getInstance();
  
  aboutToAppear(): void {
    logger.info(TAG, '覆盖层组件初始化');
    
    // 注册状态变化回调
    this.controller.setStateChangeCallback((state: GlobalTransitionState) => {
      this.updateState(state);
    });
    
    // 同步初始状态
    const initialState = this.controller.getState();
    this.updateState(initialState);
  }
  
  
  /**
   * 动画完成处理
   */
  private handleAnimationComplete(): void {
    this.controller.onAnimationComplete();
  }
  
  /**
   * 阶段变化处理
   */
  private handlePhaseChange(phase: TransitionPhase): void {
    logger.info(TAG, `阶段变化: ${phase}`);
  }

  private isUsableResolvedCoverPosition(position: CoverPosition): boolean {
    if (position.width <= 0 || position.height <= 0) {
      return false;
    }
    if (position.x === DEFAULT_COVER_POSITION.x
      && position.y === DEFAULT_COVER_POSITION.y
      && position.width === DEFAULT_COVER_POSITION.width
      && position.height === DEFAULT_COVER_POSITION.height) {
      return false;
    }
    return true;
  }

  private resolveCloseCoverPosition(): CoverPosition | null {
    if (!this.isActive || this.mode !== TransitionMode.CLOSE || this.closeCoverComponentId.length === 0) {
      return null;
    }

    const latestPosition: CoverPosition = getCoverPositionById(this.closeCoverComponentId);
    if (!this.isUsableResolvedCoverPosition(latestPosition)) {
      logger.warn(TAG, `关闭动画淡出前复测未获取到有效封面位置: id=${this.closeCoverComponentId}`);
      return null;
    }

    logger.info(TAG, `关闭动画淡出前复测封面位置: id=${this.closeCoverComponentId}, pos=(${latestPosition.x}, ${latestPosition.y}), size=${latestPosition.width}x${latestPosition.height}, delta=(${latestPosition.x - this.coverPosition.x}, ${latestPosition.y - this.coverPosition.y})`);
    return latestPosition;
  }
  
  // 超时保护定时器
  private safetyTimeoutTimer: number = -1;
  private static readonly ANIMATION_TIMEOUT_MS = 5000;  // 5秒超时保护
  
  /**
   * 启动超时保护
   */
  private startSafetyTimeout(): void {
    this.clearSafetyTimeout();
    this.safetyTimeoutTimer = setTimeout(() => {
      if (this.isActive) {
        logger.warn(TAG, '动画超时，强制重置状态');
        this.controller.forceReset();
      }
    }, BookTransitionOverlay.ANIMATION_TIMEOUT_MS);
  }
  
  /**
   * 清除超时保护
   */
  private clearSafetyTimeout(): void {
    if (this.safetyTimeoutTimer !== -1) {
      clearTimeout(this.safetyTimeoutTimer);
      this.safetyTimeoutTimer = -1;
    }
  }
  
  /**
   * 更新状态（增加超时保护）
   */
  private updateState(state: GlobalTransitionState): void {
    const wasActive = this.isActive;
    this.isActive = state.isActive;
    this.mode = state.mode;
    this.targetBookType = state.targetBookType;
    this.coverImagePath = state.coverImagePath;
    this.coverPosition = state.coverPosition;
    this.closeCoverComponentId = state.closeCoverComponentId;
    this.readerContentPixelMap = state.readerContentPixelMap;
    this.readerContentImagePath = state.readerContentImagePath;
    this.isReaderReady = state.isReaderReady;
    this.readerLoadProgress = state.readerLoadProgress;
    this.ebookBackground = state.ebookBackground;
    this.bookTitle = state.bookTitle;
    this.bookAuthor = state.bookAuthor;
    this.bookIntro = state.bookIntro;
    
    // 启动或清除超时保护
    if (this.isActive && !wasActive) {
      this.startSafetyTimeout();
    } else if (!this.isActive && wasActive) {
      this.clearSafetyTimeout();
      // [修复] 覆盖层已隐藏，若处于取消状态则通知控制器完成取消，重置 isCancelling
      // 若不重置，isCancelling 将永久为 true，导致后续 cancelTransition() 无法工作，
      // 从而使覆盖层在每次关闭时都锁死整个屏幕约 950ms
      if (this.controller.isCancellingTransition()) {
        this.controller.onCancelComplete();
      }
    }
    
    logger.debug(TAG, `状态更新: isActive=${this.isActive}, mode=${this.mode}, type=${this.targetBookType}, isReaderReady=${this.isReaderReady}, imagePath=${this.readerContentImagePath ? '有' : '无'}, ebookBg=${this.ebookBackground ? '有' : '无'}`);
  }
  
  build() {
    Stack() {
      if (this.isActive) {
        BookOpenTransition({
          mode: this.mode,
          contentType: this.targetBookType,
          coverImagePath: this.coverImagePath,
          coverPosition: this.coverPosition,
          readerContentPixelMap: this.readerContentPixelMap,
          readerContentImagePath: this.readerContentImagePath,
          config: this.config,
          isReaderReady: this.isReaderReady,
          readerLoadProgress: this.readerLoadProgress,
          ebookBackground: this.ebookBackground,
          bookTitle: this.bookTitle,
          bookAuthor: this.bookAuthor,
          bookIntro: this.bookIntro,
          resolveCloseCoverPosition: () => this.resolveCloseCoverPosition(),
          onAnimationComplete: () => {
            this.clearSafetyTimeout();
            this.handleAnimationComplete();
          },
          onPhaseChange: (phase: TransitionPhase) => this.handlePhaseChange(phase)
        })
      }
    }
    .width('100%')
    .height('100%')
    .id(BOOK_TRANSITION_OVERLAY_ROOT_ID)
    .position({ x: 0, y: 0 })
    .zIndex(9999)  // 确保在最顶层
    .hitTestBehavior(this.isActive ? HitTestMode.Block : HitTestMode.None)
    .expandSafeArea([SafeAreaType.SYSTEM, SafeAreaType.CUTOUT], [SafeAreaEdge.TOP, SafeAreaEdge.BOTTOM, SafeAreaEdge.START, SafeAreaEdge.END])  // 扩展到所有安全区域
  }
}

/**
 * 便捷函数：开始翻开过渡
 */
export function startBookOpenTransition(
  coverImagePath: string,
  coverPosition: CoverPosition,
  targetBookId: string,
  targetBookType: 'manga' | 'ebook' | 'novel',
  onComplete?: () => void,
  metaInfo?: BookTransitionMetaInfo
): void {
  TransitionController.getInstance().startOpenTransition(
    coverImagePath,
    coverPosition,
    targetBookId,
    targetBookType,
    onComplete,
    undefined,
    metaInfo
  );
}

/**
 * 便捷函数：开始关闭过渡
 */
export function startBookCloseTransition(
  coverPosition: CoverPosition,
  readerContentPixelMap?: image.PixelMap,
  onComplete?: () => void
): void {
  TransitionController.getInstance().startCloseTransition(
    coverPosition,
    readerContentPixelMap,
    onComplete
  );
}

/**
 * 便捷函数：标记阅读器就绪
 */
export function setReaderReady(): void {
  TransitionController.getInstance().setReaderReady();
}

export function setReaderLoadingProgress(progress: number): void {
  TransitionController.getInstance().setReaderLoadingProgress(progress);
}

/**
 * 便捷函数：取消过渡
 */
export function cancelTransition(): void {
  TransitionController.getInstance().cancelTransition();
}

/**
 * 便捷函数：检查是否正在过渡
 */
export function isTransitioning(): boolean {
  return TransitionController.getInstance().isTransitioning();
}

function getTransitionOverlayCoordinateOffset(): TransitionCoordinateOffset {
  try {
    const rootRectInfo = componentUtils.getRectangleById(BOOK_TRANSITION_OVERLAY_ROOT_ID);
    if (rootRectInfo) {
      return {
        x: Number(rootRectInfo.screenOffset.x),
        y: Number(rootRectInfo.screenOffset.y),
        useScreenOffset: true
      };
    }
  } catch (error) {
    logger.warn(TAG, `获取过渡覆盖层坐标原点失败，使用屏幕原点: ${String(error)}`);
  }
  return {
    x: 0,
    y: 0,
    useScreenOffset: false
  };
}

/**
 * 便捷函数：获取组件的屏幕位置
 * @param componentId 组件ID（需要在组件上设置 .id() 属性）
 * @returns 封面位置信息，如果获取失败返回默认值
 */
export function getCoverPositionById(componentId: string): CoverPosition {
  if (!componentId || componentId.length === 0) {
    logger.warn(TAG, '组件ID为空，使用默认位置');
    return DEFAULT_COVER_POSITION;
  }
  
  try {
    const rectInfo = componentUtils.getRectangleById(componentId);
    if (rectInfo) {
      const overlayOffset = getTransitionOverlayCoordinateOffset();
      const sourceOffset = overlayOffset.useScreenOffset ? rectInfo.screenOffset : rectInfo.windowOffset;
      const position: CoverPosition = {
        x: px2vp(Number(sourceOffset.x) - overlayOffset.x),
        y: px2vp(Number(sourceOffset.y) - overlayOffset.y),
        width: px2vp(rectInfo.size.width),
        height: px2vp(rectInfo.size.height)
      };
      
      // 检查尺寸是否有效（组件可能不在当前页面）
      if (position.width <= 0 || position.height <= 0) {
        logger.warn(TAG, `组件尺寸无效: id=${componentId}, size=${position.width}x${position.height}，使用默认位置`);
        return DEFAULT_COVER_POSITION;
      }
      
      logger.info(TAG, `获取组件位置成功: id=${componentId}, pos=(${position.x}, ${position.y}), size=${position.width}x${position.height}, source=${overlayOffset.useScreenOffset ? 'screenOffset' : 'windowOffset'}, overlayOffset=(${px2vp(overlayOffset.x)}, ${px2vp(overlayOffset.y)}), window=(${px2vp(Number(rectInfo.windowOffset.x))}, ${px2vp(Number(rectInfo.windowOffset.y))}), screen=(${px2vp(Number(rectInfo.screenOffset.x))}, ${px2vp(Number(rectInfo.screenOffset.y))})`);
      return position;
    }
  } catch (error) {
    logger.warn(TAG, `获取组件位置失败: ${String(error)}`);
  }
  
  logger.warn(TAG, `未找到组件: id=${componentId}，使用默认位置`);
  return DEFAULT_COVER_POSITION;
}

/**
 * 便捷函数：带位置获取的翻开过渡
 * @param coverImagePath 封面图片路径
 * @param componentId 封面组件ID
 * @param targetBookId 目标书籍ID
 * @param targetBookType 目标书籍类型
 * @param onComplete 完成回调
 * @param ebookBackground 电子书背景设置（可选，仅电子书使用）
 */
export function startBookOpenTransitionWithComponentId(
  coverImagePath: string,
  componentId: string,
  targetBookId: string,
  targetBookType: 'manga' | 'ebook' | 'novel',
  onComplete?: () => void,
  ebookBackground?: EBookBackgroundSettings,
  metaInfo?: BookTransitionMetaInfo
): void {
  const coverPosition = getCoverPositionById(componentId);
  TransitionController.getInstance().startOpenTransition(
    coverImagePath,
    coverPosition,
    targetBookId,
    targetBookType,
    onComplete,
    ebookBackground,
    metaInfo
  );
}

/**
 * 截图结果接口
 */
export interface CaptureResult {
  pixelMap?: image.PixelMap;
  imagePath: string;  // 压缩后的临时文件路径
}

/**
 * 便捷函数：截取指定组件内容并保存为压缩临时文件
 * 用于关闭动画获取阅读器最后一帧
 * @param componentId 组件ID（需要在阅读器根组件上设置 .id() 属性）
 * @returns Promise<CaptureResult | undefined>
 */
export async function captureComponent(componentId: string): Promise<CaptureResult | undefined> {
  logger.info(TAG, `📷 [组件截图] 开始截取: ${componentId}`);
  
  try {
    if (!componentId || componentId.length === 0) {
      logger.warn(TAG, '📷 [组件截图] 组件ID为空，无法截图');
      return undefined;
    }
    
    logger.info(TAG, `📷 [组件截图] 调用 componentSnapshot.get...`);
    const pixelMap = await componentSnapshot.get(componentId);
    
    if (pixelMap) {
      const imageInfo = await pixelMap.getImageInfo();
      logger.info(TAG, `📷 [组件截图] ✅ 成功! 尺寸=${imageInfo.size.width}x${imageInfo.size.height}`);
      
      // 直接返回原始PixelMap，不进行压缩
      // 这样可以避免压缩导致的质量损失和延迟（约77ms）
      // Image组件可以直接使用PixelMap，无需文件路径
      return {
        pixelMap: pixelMap,
        imagePath: ''  // 不再保存压缩文件
      };
    } else {
      logger.warn(TAG, `📷 [组件截图] ⚠️ 返回空: ${componentId}`);
      return undefined;
    }
  } catch (error) {
    logger.error(TAG, `📷 [组件截图] ❌ 失败: ${componentId}, 错误=${String(error)}`);
    return undefined;
  }
}

function sleepMs(ms: number): Promise<void> {
  return new Promise<void>((resolve) => {
    setTimeout(() => resolve(), ms);
  });
}

async function captureComponentWithRetry(
  componentId: string,
  maxAttempts: number = 6,
  retryDelayMs: number = 40
): Promise<CaptureResult | undefined> {
  for (let attempt = 1; attempt <= maxAttempts; attempt++) {
    const result = await captureComponent(componentId);
    if (result?.pixelMap || (result?.imagePath && result.imagePath.length > 0)) {
      if (attempt > 1) {
        logger.info(TAG, `📷 [组件截图] 第 ${attempt} 次重试成功: ${componentId}`);
      }
      return result;
    }

    if (attempt < maxAttempts) {
      logger.warn(TAG, `📷 [组件截图] 第 ${attempt} 次未获取到有效截图，${retryDelayMs}ms 后重试`);
      await sleepMs(retryDelayMs);
    }
  }

  logger.warn(TAG, `📷 [组件截图] 多次重试后仍未获取到有效截图: ${componentId}`);
  return undefined;
}

/**
 * 保存压缩后的截图临时文件
 * 使用JPEG格式（解码快）+ 较低质量 + 缩放以提高效率
 * @returns 保存的文件路径
 */
async function saveCompressedScreenshot(
  pixelMap: image.PixelMap, 
  componentId: string, 
  originalWidth: number, 
  originalHeight: number
): Promise<string> {
  logger.info(TAG, `📸 [压缩截图] 开始处理...`);
  
  try {
    // 使用应用缓存目录
    const context = getContext();
    if (!context || !context.cacheDir) {
      logger.error(TAG, `📸 [压缩截图] 无法获取应用上下文`);
      return '';
    }
    
    const tempDir = `${context.cacheDir}/transition_screenshots`;
    
    // 创建目录
    try {
      await fileIo.mkdir(tempDir);
    } catch {
      // 目录可能已存在
    }
    
    // 清理旧的临时文件（保留最近5个）
    try {
      const files = await fileIo.listFile(tempDir);
      if (files.length > 5) {
        // 按文件名排序（包含时间戳），删除旧的
        files.sort();
        for (let i = 0; i < files.length - 5; i++) {
          try {
            await fileIo.unlink(`${tempDir}/${files[i]}`);
          } catch {
            // 忽略删除失败
          }
        }
      }
    } catch {
      // 忽略清理错误
    }
    
    // 生成文件名
    const timestamp = Date.now();
    const fileName = `trans_${timestamp}.jpg`;  // 使用JPEG格式，解码更快
    const filePath = `${tempDir}/${fileName}`;
    
    // 计算目标尺寸（限制最大边为800px，减少文件大小和解码时间）
    const maxSize = 800;
    let targetWidth = originalWidth;
    let targetHeight = originalHeight;
    
    if (originalWidth > maxSize || originalHeight > maxSize) {
      const scale = Math.min(maxSize / originalWidth, maxSize / originalHeight);
      targetWidth = Math.round(originalWidth * scale);
      targetHeight = Math.round(originalHeight * scale);
      logger.info(TAG, `📸 [压缩截图] 缩放: ${originalWidth}x${originalHeight} -> ${targetWidth}x${targetHeight}`);
    }
    
    // 使用ImagePacker打包为JPEG（解码速度比WebP快）
    const imagePacker = image.createImagePacker();
    const packOptions: image.PackingOption = {
      format: 'image/jpeg',  // JPEG解码更快
      quality: 70  // 较低质量，减小文件大小
    };
    
    logger.info(TAG, `📸 [压缩截图] 开始打包...`);
    const arrayBuffer = await imagePacker.packing(pixelMap, packOptions);
    const sizeKB = Math.round(arrayBuffer.byteLength / 1024);
    logger.info(TAG, `📸 [压缩截图] 打包完成，大小: ${sizeKB}KB`);
    
    // 写入文件
    const file = await fileIo.open(filePath, fileIo.OpenMode.CREATE | fileIo.OpenMode.WRITE_ONLY | fileIo.OpenMode.TRUNC);
    await fileIo.write(file.fd, arrayBuffer);
    await fileIo.close(file.fd);
    
    imagePacker.release();
    
    logger.info(TAG, `📸 [压缩截图] ✅ 成功! 路径: ${filePath}, 大小: ${sizeKB}KB`);
    return filePath;
    
  } catch (error) {
    const errorMsg = error instanceof Error ? error.message : String(error);
    logger.error(TAG, `📸 [压缩截图] ❌ 失败: ${errorMsg}`);
    return '';
  }
}

/**
 * 便捷函数：带截图的关闭过渡
 * 截取指定组件内容作为关闭动画的初始画面
 * @param componentId 阅读器根组件ID
 * @param coverPosition 封面目标位置
 * @param onComplete 完成回调
 */
export async function startBookCloseTransitionWithCapture(
  componentId: string,
  coverPosition: CoverPosition,
  onComplete?: () => void
): Promise<void> {
  const captureResult = await captureComponent(componentId);
  TransitionController.getInstance().startCloseTransition(
    coverPosition,
    captureResult?.pixelMap,
    onComplete,
    captureResult?.imagePath
  );
}

/**
 * 便捷函数：使用组件ID获取位置并带截图的关闭过渡
 * 优化：先截图，然后直接显示截图并开始动画（无缝过渡）
 * @param readerComponentId 阅读器根组件ID（用于截图）
 * @param coverComponentId 封面组件ID（用于获取位置）
 * @param onComplete 完成回调
 */
export async function startBookCloseTransitionWithComponentId(
  readerComponentId: string,
  coverComponentId: string,
  onComplete?: () => void
): Promise<void> {
  logger.info(TAG, `🔴 startBookCloseTransitionWithComponentId 开始: reader=${readerComponentId}, cover=${coverComponentId}`);
  
  try {
    const coverPosition = getCoverPositionById(coverComponentId);
    logger.info(TAG, `🔴 获取封面位置完成: pos=(${coverPosition.x}, ${coverPosition.y}), size=${coverPosition.width}x${coverPosition.height}`);
    
    // 直接截图（不显示任何遮罩层）
    logger.info(TAG, `🔴 开始调用 captureComponent...`);
    const captureResult = await captureComponentWithRetry(readerComponentId);
    logger.info(TAG, `🔴 captureComponent 返回: pixelMap=${captureResult?.pixelMap ? '有效' : '空'}, imagePath=${captureResult?.imagePath ? '有' : '无'}`);
    
    // 截图完成后，直接启动关闭动画（带截图数据）
    // 动画组件会立即显示全屏截图，覆盖住底层阅读器
    TransitionController.getInstance().startCloseTransition(
      coverPosition,
      captureResult?.pixelMap,
      onComplete,
      captureResult?.imagePath,
      coverComponentId
    );
    logger.info(TAG, `🔴 startCloseTransition 调用完成`);
  } catch (error) {
    logger.error(TAG, `🔴 startBookCloseTransitionWithComponentId 错误: ${String(error)}`);
    // 即使截图失败也要确保能返回
    TransitionController.getInstance().forceReset();
    if (onComplete) {
      onComplete();
    }
  }
}

export { CoverPosition };
