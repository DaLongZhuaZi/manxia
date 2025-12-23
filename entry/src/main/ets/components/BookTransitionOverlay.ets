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
import { 
  BookOpenTransition, 
  TransitionMode, 
  TransitionPhase,
  CoverPosition,
  BookTransitionConfig
} from './BookOpenTransition';

const TAG = 'BookTransitionOverlay';

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
  readerContentPixelMap: image.PixelMap | null = null;
  readerContentImagePath: string = '';  // 压缩后的临时截图路径
  isReaderReady: boolean = false;
  targetBookId: string = '';
  targetBookType: 'manga' | 'ebook' | 'novel' = 'manga';
  ebookBackground: EBookBackgroundSettings | null = null;  // 电子书背景设置
}

/**
 * 过渡动画控制器（单例）
 * 用于从任何地方触发过渡动画
 */
export class TransitionController {
  private static instance: TransitionController | null = null;
  
  // 状态变化回调
  private onStateChange: ((state: GlobalTransitionState) => void) | null = null;
  private onOpenComplete: (() => void) | null = null;
  private onCloseComplete: (() => void) | null = null;
  private onCancelCallback: (() => void) | null = null;
  
  // 当前状态
  private currentState: GlobalTransitionState = new GlobalTransitionState();
  
  // 保存翻开动画的封面位置，用于关闭动画复用
  private lastOpenCoverPosition: CoverPosition | null = null;
  
  // 取消相关
  private isCancelling: boolean = false;
  private pendingNavigationTimer: number = -1;
  
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
    ebookBackground?: EBookBackgroundSettings
  ): void {
    logger.info(TAG, `开始翻开过渡: bookId=${targetBookId}, type=${targetBookType}, 有背景设置=${ebookBackground ? '是' : '否'}`);
    
    // 只在位置有效时保存（避免默认位置覆盖正确位置）
    const isDefaultPosition = coverPosition.x === 16 && coverPosition.y === 120 && 
                              coverPosition.width === 140 && coverPosition.height === 200;
    if (!isDefaultPosition) {
      this.lastOpenCoverPosition = coverPosition;
      logger.info(TAG, `保存封面位置: pos=(${coverPosition.x}, ${coverPosition.y}), size=${coverPosition.width}x${coverPosition.height}`);
    } else {
      logger.warn(TAG, `跳过保存默认位置，保留已有位置: ${this.lastOpenCoverPosition ? `pos=(${this.lastOpenCoverPosition.x}, ${this.lastOpenCoverPosition.y})` : '无'}`);
    }
    
    this.currentState = {
      isActive: true,
      mode: TransitionMode.OPEN,
      coverImagePath: coverImagePath,
      coverPosition: coverPosition,
      readerContentPixelMap: null,
      readerContentImagePath: '',
      isReaderReady: false,
      targetBookId: targetBookId,
      targetBookType: targetBookType,
      ebookBackground: ebookBackground || null
    };
    
    this.onOpenComplete = onComplete || null;
    this.notifyStateChange();
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
    readerContentImagePath?: string
  ): void {
    logger.info(TAG, '开始关闭过渡');
    
    // 优先使用翻开动画保存的位置（因为关闭时封面组件可能不在屏幕上）
    let finalCoverPosition: CoverPosition;
    
    if (this.lastOpenCoverPosition && this.lastOpenCoverPosition.width > 0 && this.lastOpenCoverPosition.height > 0) {
      // 优先使用翻开动画保存的位置
      logger.info(TAG, `🎯 使用翻开动画保存的封面位置: pos=(${this.lastOpenCoverPosition.x}, ${this.lastOpenCoverPosition.y}), size=${this.lastOpenCoverPosition.width}x${this.lastOpenCoverPosition.height}`);
      finalCoverPosition = this.lastOpenCoverPosition;
    } else if (coverPosition.width > 0 && coverPosition.height > 0) {
      // 使用传入的位置
      logger.info(TAG, `使用传入的封面位置: pos=(${coverPosition.x}, ${coverPosition.y}), size=${coverPosition.width}x${coverPosition.height}`);
      finalCoverPosition = coverPosition;
    } else {
      // 都无效时使用默认位置
      logger.warn(TAG, '无法获取封面位置，使用默认位置');
      finalCoverPosition = { x: 16, y: 120, width: 140, height: 200 };
    }
    
    this.currentState.isActive = true;
    this.currentState.mode = TransitionMode.CLOSE;
    this.currentState.coverPosition = finalCoverPosition;
    this.currentState.readerContentPixelMap = readerContentPixelMap || null;
    this.currentState.readerContentImagePath = readerContentImagePath || '';
    this.currentState.isReaderReady = true;
    
    logger.info(TAG, `关闭过渡状态: imagePath=${readerContentImagePath ? '有' : '无'}, pixelMap=${readerContentPixelMap ? '有' : '无'}`);
    
    this.onCloseComplete = onComplete || null;
    this.notifyStateChange();
  }
  
  /**
   * 标记阅读器已就绪（翻开模式时调用）
   * 阅读器加载完成后调用此方法，覆盖层会淡出消失
   */
  public setReaderReady(): void {
    if (this.currentState.isActive && this.currentState.mode === TransitionMode.OPEN) {
      logger.info(TAG, '阅读器已就绪，开始淡出覆盖层');
      this.currentState.isReaderReady = true;
      this.notifyStateChange();
      
      // 延迟一小段时间后隐藏覆盖层，让淡出动画有时间播放
      setTimeout(() => {
        this.currentState = new GlobalTransitionState();
        this.notifyStateChange();
        logger.info(TAG, '覆盖层已隐藏');
      }, 300);  // 300ms淡出动画
    }
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
      // 关闭模式：直接完成
      this.currentState = new GlobalTransitionState();
      this.notifyStateChange();
      
      if (this.onCloseComplete) {
        this.onCloseComplete();
        this.onCloseComplete = null;
      }
    }
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
  @State private coverImagePath: string = '';
  @State private coverPosition: CoverPosition = { x: 0, y: 0, width: 100, height: 150 };
  @State private readerContentPixelMap: image.PixelMap | null = null;
  @State private readerContentImagePath: string = '';  // 压缩后的截图临时文件路径
  @State private isReaderReady: boolean = false;
  @State private ebookBackground: EBookBackgroundSettings | null = null;  // 电子书背景设置
  
  // 动画配置
  private config: BookTransitionConfig = {
    coverMoveDuration: 400,
    liftDuration: 500,
    transitionDuration: 300,
    shrinkDuration: 400,
    returnDuration: 350,
    fadeDuration: 200,
    maxLiftAngle: 90,  // 减小翻开角度，更自然
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
   * 更新状态
   */
  private updateState(state: GlobalTransitionState): void {
    this.isActive = state.isActive;
    this.mode = state.mode;
    this.coverImagePath = state.coverImagePath;
    this.coverPosition = state.coverPosition;
    this.readerContentPixelMap = state.readerContentPixelMap;
    this.readerContentImagePath = state.readerContentImagePath;
    this.isReaderReady = state.isReaderReady;
    this.ebookBackground = state.ebookBackground;
    
    logger.debug(TAG, `状态更新: isActive=${this.isActive}, mode=${this.mode}, isReaderReady=${this.isReaderReady}, imagePath=${this.readerContentImagePath ? '有' : '无'}, ebookBg=${this.ebookBackground ? '有' : '无'}`);
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
  
  build() {
    if (this.isActive) {
      Stack() {
        BookOpenTransition({
          mode: this.mode,
          coverImagePath: this.coverImagePath,
          coverPosition: this.coverPosition,
          readerContentPixelMap: this.readerContentPixelMap,
          readerContentImagePath: this.readerContentImagePath,
          config: this.config,
          isReaderReady: this.isReaderReady,
          ebookBackground: this.ebookBackground,
          onAnimationComplete: () => this.handleAnimationComplete(),
          onPhaseChange: (phase: TransitionPhase) => this.handlePhaseChange(phase)
        })
      }
      .width('100%')
      .height('100%')
      .position({ x: 0, y: 0 })
      .zIndex(9999)  // 确保在最顶层
      .hitTestBehavior(HitTestMode.Block)  // 阻止点击穿透
      .expandSafeArea([SafeAreaType.SYSTEM, SafeAreaType.CUTOUT], [SafeAreaEdge.TOP, SafeAreaEdge.BOTTOM, SafeAreaEdge.START, SafeAreaEdge.END])  // 扩展到所有安全区域
    }
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
  onComplete?: () => void
): void {
  TransitionController.getInstance().startOpenTransition(
    coverImagePath,
    coverPosition,
    targetBookId,
    targetBookType,
    onComplete
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

/**
 * 便捷函数：获取组件的屏幕位置
 * @param componentId 组件ID（需要在组件上设置 .id() 属性）
 * @returns 封面位置信息，如果获取失败返回默认值
 */
export function getCoverPositionById(componentId: string): CoverPosition {
  // 默认位置（当组件不存在或尺寸为0时使用）
  const defaultPosition: CoverPosition = {
    x: 16,
    y: 120,
    width: 140,
    height: 200
  };
  
  if (!componentId || componentId.length === 0) {
    logger.warn(TAG, '组件ID为空，使用默认位置');
    return defaultPosition;
  }
  
  try {
    const rectInfo = componentUtils.getRectangleById(componentId);
    if (rectInfo) {
      // 转换为vp单位
      const position: CoverPosition = {
        x: px2vp(rectInfo.windowOffset.x),
        y: px2vp(rectInfo.windowOffset.y),
        width: px2vp(rectInfo.size.width),
        height: px2vp(rectInfo.size.height)
      };
      
      // 检查尺寸是否有效（组件可能不在当前页面）
      if (position.width <= 0 || position.height <= 0) {
        logger.warn(TAG, `组件尺寸无效: id=${componentId}, size=${position.width}x${position.height}，使用默认位置`);
        return defaultPosition;
      }
      
      logger.info(TAG, `获取组件位置成功: id=${componentId}, pos=(${position.x}, ${position.y}), size=${position.width}x${position.height}`);
      return position;
    }
  } catch (error) {
    logger.warn(TAG, `获取组件位置失败: ${String(error)}`);
  }
  
  logger.warn(TAG, `未找到组件: id=${componentId}，使用默认位置`);
  return defaultPosition;
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
  ebookBackground?: EBookBackgroundSettings
): void {
  const coverPosition = getCoverPositionById(componentId);
  TransitionController.getInstance().startOpenTransition(
    coverImagePath,
    coverPosition,
    targetBookId,
    targetBookType,
    onComplete,
    ebookBackground
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
      
      // 保存为压缩的临时文件（用于Image组件显示）
      logger.info(TAG, `📷 [组件截图] 开始保存压缩文件...`);
      const imagePath = await saveCompressedScreenshot(pixelMap, componentId, imageInfo.size.width, imageInfo.size.height);
      logger.info(TAG, `📷 [组件截图] 保存完成: ${imagePath}`);
      
      return {
        pixelMap: pixelMap,
        imagePath: imagePath
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
    
    logger.info(TAG, `🔴 开始调用 captureComponent...`);
    const captureResult = await captureComponent(readerComponentId);
    logger.info(TAG, `🔴 captureComponent 返回: pixelMap=${captureResult?.pixelMap ? '有效' : '空'}, imagePath=${captureResult?.imagePath ? '有' : '无'}`);
    
    TransitionController.getInstance().startCloseTransition(
      coverPosition,
      captureResult?.pixelMap,
      onComplete,
      captureResult?.imagePath
    );
    logger.info(TAG, `🔴 startCloseTransition 调用完成`);
  } catch (error) {
    logger.error(TAG, `🔴 startBookCloseTransitionWithComponentId 错误: ${String(error)}`);
  }
}

export { CoverPosition };
