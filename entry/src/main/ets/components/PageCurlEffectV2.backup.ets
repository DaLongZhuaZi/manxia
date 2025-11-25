/**
 * 基于Canvas的3D卷页效果组件 V2
 * 
 * 核心特性：
 * 1. 可交互的拟真翻页 - 页面可以被"拎起"和"放下"
 * 2. 实时3D变形 - 拖拽开始时当前页立即变成立体的
 * 3. 可打断 - 随时松手，根据进度决定翻过去还是回弹
 * 4. 底层显示下一页 - 翻页时露出下面的下一页
 */

import { logger } from '../Utils/Logger';
import { image } from '@kit.ImageKit';

const TAG = 'PageCurlEffectV2';

/**
 * 卷页配置接口
 */
export interface PageCurlConfigV2 {
  stripCount: number;        // 条带数量（用于平滑卷曲）
  maxCurlHeight: number;     // 最大卷曲高度（像素）
  shadowIntensity: number;   // 阴影强度 (0-1)
  animationDuration: number; // 回弹/完成动画时长（毫秒）
  enableShadow: boolean;     // 是否启用阴影
  enableHighlight: boolean;  // 是否启用高光
  flipThreshold: number;     // 翻页阈值 (0-1)，超过此值松手会翻过去
}

const DEFAULT_CONFIG: PageCurlConfigV2 = {
  stripCount: 24,
  maxCurlHeight: 100,
  shadowIntensity: 0.6,
  animationDuration: 300,
  enableShadow: true,
  enableHighlight: true,
  flipThreshold: 0.35
};

/**
 * 翻页完成回调
 */
export type OnPageFlipCallback = (completed: boolean) => void;

@Component
export struct PageCurlEffectV2 {
  // ========== 外部传入的数据 ==========
  // 当前页PixelMap（正在被翻的页面）
  // 注意：不能使用@Prop，因为@Prop会对PixelMap进行深拷贝，导致Native侧数据丢失
  // 使用普通属性直接传递引用
  currentPixelMap: image.PixelMap | null = null;
  // 下一页PixelMap（底下露出的页面）
  nextPixelMap: image.PixelMap | null = null;
  // 组件尺寸
  @Prop componentWidth: number = 360;
  @Prop componentHeight: number = 640;
  // 图片实际显示区域
  @Prop imageDisplayX: number = 0;
  @Prop imageDisplayY: number = 0;
  @Prop imageDisplayWidth: number = 360;
  @Prop imageDisplayHeight: number = 640;
  // 配置
  @Prop config: PageCurlConfigV2 = DEFAULT_CONFIG;
  // 翻页方向：true=向前翻（下一页），false=向后翻（上一页）
  @Prop isForward: boolean = true;
  
  // ========== 外部控制的进度（用于外部动画驱动） ==========
  @Prop @Watch('onExternalProgressChange') externalProgress: number = -1; // -1表示不使用外部进度
  
  // ========== 回调 ==========
  // 翻页完成回调
  onPageFlip: OnPageFlipCallback = (_completed: boolean) => {};
  
  // ========== 内部状态 ==========
  @State private isReady: boolean = false;
  @State private isDragging: boolean = false;
  @State private curlProgress: number = 0; // 当前卷曲进度 (0-1)
  
  // 触摸起始位置
  private touchStartX: number = 0;
  private touchStartY: number = 0;
  // 当前触摸位置
  private touchCurrentX: number = 0;
  private touchCurrentY: number = 0;
  
  // 动画相关
  private animationTimer: number = -1;
  
  // ImageBitmap缓存（用于Canvas绘制）
  private currentImageBitmap: ImageBitmap | null = null;
  private nextImageBitmap: ImageBitmap | null = null;
  
  private canvasSettings: RenderingContextSettings = new RenderingContextSettings(true);
  private canvasContext: CanvasRenderingContext2D = new CanvasRenderingContext2D(this.canvasSettings);

  aboutToAppear(): void {
    logger.info(TAG, `初始化: canvas=${this.componentWidth}x${this.componentHeight}, img=${this.imageDisplayWidth}x${this.imageDisplayHeight}`);
  }
  
  aboutToDisappear(): void {
    this.stopAnimation();
    // 释放ImageBitmap资源
    if (this.currentImageBitmap) {
      try {
        this.currentImageBitmap.close();
      } catch (e) {
        // 忽略关闭错误
      }
      this.currentImageBitmap = null;
    }
    if (this.nextImageBitmap) {
      try {
        this.nextImageBitmap.close();
      } catch (e) {
        // 忽略关闭错误
      }
      this.nextImageBitmap = null;
    }
  }

  /**
   * 检查PixelMap是否变化，如果变化则更新ImageBitmap
   * 由于不能使用@Prop和@Watch（会导致PixelMap深拷贝丢失Native数据），
   * 需要在每次渲染前检查PixelMap是否需要更新
   */
  private lastCurrentPixelMap: image.PixelMap | null = null;
  private lastNextPixelMap: image.PixelMap | null = null;
  
  private checkAndUpdateBitmaps(): void {
    // 检查PixelMap是否变化（通过引用比较）
    const currentChanged = this.currentPixelMap !== this.lastCurrentPixelMap;
    const nextChanged = this.nextPixelMap !== this.lastNextPixelMap;
    
    if (currentChanged || nextChanged) {
      logger.info(TAG, `[checkAndUpdateBitmaps] PixelMap变化: currentChanged=${currentChanged}, nextChanged=${nextChanged}`);
      this.lastCurrentPixelMap = this.currentPixelMap;
      this.lastNextPixelMap = this.nextPixelMap;
      this.updateImageBitmaps();
    }
  }
  
  /**
   * 将PixelMap转换为ImageBitmap
   * 根据官方文档，Canvas的drawImage使用ImageBitmap效果更好
   */
  private updateImageBitmaps(): void {
    // 释放旧的ImageBitmap
    if (this.currentImageBitmap) {
      try {
        this.currentImageBitmap.close();
      } catch (e) {
        // 忽略关闭错误
      }
      this.currentImageBitmap = null;
    }
    if (this.nextImageBitmap) {
      try {
        this.nextImageBitmap.close();
      } catch (e) {
        // 忽略关闭错误
      }
      this.nextImageBitmap = null;
    }
    
    // 从PixelMap创建新的ImageBitmap
    if (this.currentPixelMap) {
      try {
        // 先检查PixelMap的信息
        const pmInfo = this.currentPixelMap.getImageInfoSync();
        logger.info(TAG, `[updateImageBitmaps] 当前页PixelMap信息: ${pmInfo.size.width}x${pmInfo.size.height}, format=${pmInfo.pixelFormat}`);
        
        // 创建ImageBitmap
        const bitmap = new ImageBitmap(this.currentPixelMap);
        logger.info(TAG, `[updateImageBitmaps] 当前页ImageBitmap创建完成, typeof=${typeof bitmap}, bitmap=${bitmap}`);
        
        // 检查bitmap是否有效
        if (bitmap) {
          this.currentImageBitmap = bitmap;
          // 安全访问width/height
          const w = this.currentImageBitmap?.width;
          const h = this.currentImageBitmap?.height;
          logger.info(TAG, `[updateImageBitmaps] 当前页ImageBitmap尺寸: w=${w}, h=${h}`);
        } else {
          logger.error(TAG, `[updateImageBitmaps] 当前页ImageBitmap创建返回null/undefined`);
        }
      } catch (e) {
        logger.error(TAG, `[updateImageBitmaps] 当前页ImageBitmap创建失败: ${e}`);
        this.currentImageBitmap = null;
      }
    } else {
      logger.warn(TAG, `[updateImageBitmaps] 当前页PixelMap为空，跳过创建`);
    }
    
    if (this.nextPixelMap) {
      try {
        // 先检查PixelMap的信息
        const pmInfo = this.nextPixelMap.getImageInfoSync();
        logger.info(TAG, `[updateImageBitmaps] 下一页PixelMap信息: ${pmInfo.size.width}x${pmInfo.size.height}, format=${pmInfo.pixelFormat}`);
        
        // 创建ImageBitmap
        const bitmap = new ImageBitmap(this.nextPixelMap);
        logger.info(TAG, `[updateImageBitmaps] 下一页ImageBitmap创建完成, typeof=${typeof bitmap}, bitmap=${bitmap}`);
        
        // 检查bitmap是否有效
        if (bitmap) {
          this.nextImageBitmap = bitmap;
          // 安全访问width/height
          const w = this.nextImageBitmap?.width;
          const h = this.nextImageBitmap?.height;
          logger.info(TAG, `[updateImageBitmaps] 下一页ImageBitmap尺寸: w=${w}, h=${h}`);
        } else {
          logger.error(TAG, `[updateImageBitmaps] 下一页ImageBitmap创建返回null/undefined`);
        }
      } catch (e) {
        logger.error(TAG, `[updateImageBitmaps] 下一页ImageBitmap创建失败: ${e}`);
        this.nextImageBitmap = null;
      }
    } else {
      logger.warn(TAG, `[updateImageBitmaps] 下一页PixelMap为空，跳过创建`);
    }
    
    logger.info(TAG, `[updateImageBitmaps] 完成: currentBitmap=${this.currentImageBitmap ? 'yes' : 'no'}, nextBitmap=${this.nextImageBitmap ? 'yes' : 'no'}`);
  }
  
  /**
   * 外部进度变化时更新渲染
   */
  onExternalProgressChange(): void {
    logger.debug(TAG, `[onExternalProgressChange] 触发: externalProgress=${this.externalProgress.toFixed(3)}, isReady=${this.isReady}, curlProgress=${this.curlProgress.toFixed(3)}`);
    if (this.externalProgress >= 0 && this.isReady) {
      // 每次渲染前检查PixelMap是否变化
      this.checkAndUpdateBitmaps();
      this.curlProgress = this.externalProgress;
      this.renderCurlEffect();
    }
  }
  
  /**
   * 停止动画
   */
  private stopAnimation(): void {
    if (this.animationTimer !== -1) {
      clearTimeout(this.animationTimer);
      this.animationTimer = -1;
    }
  }

  /**
   * 渲染卷页效果
   * 
   * 核心理念：当前页图片本身在卷曲变形，不是覆盖一个新的3D组件
   * 
   * 渲染顺序（从底到顶）：
   * 1. 背景色（画布外围）
   * 2. 下一页图片（完整显示，作为底层）
   * 3. 当前页图片（通过条带变形实现卷曲效果）
   *    - 左侧未卷起部分：正常显示
   *    - 右侧卷起部分：条带变形 + 透视收缩
   * 4. 阴影和高光（增强立体感）
   */
  private renderCurlEffect(): void {
    const ctx = this.canvasContext;
    if (!ctx) {
      logger.error(TAG, `[renderCurlEffect] ctx为空，无法渲染`);
      return;
    }

    const cw: number = this.componentWidth;
    const ch: number = this.componentHeight;
    const progress: number = this.curlProgress;
    
    // 图片区域
    const ix: number = this.imageDisplayX;
    const iy: number = this.imageDisplayY;
    const iw: number = this.imageDisplayWidth;
    const ih: number = this.imageDisplayHeight;

    logger.debug(TAG, `[renderCurlEffect] 开始渲染: progress=${progress.toFixed(3)}, canvas=${cw.toFixed(0)}x${ch.toFixed(0)}, img区域=(${ix.toFixed(0)},${iy.toFixed(0)},${iw.toFixed(0)},${ih.toFixed(0)}), currentPm=${this.currentPixelMap ? 'yes' : 'no'}, nextPm=${this.nextPixelMap ? 'yes' : 'no'}`);

    // 清空画布
    ctx.clearRect(0, 0, cw, ch);

    // 1. 绘制背景（图片区域外）
    ctx.fillStyle = '#1a1a1a';
    ctx.fillRect(0, 0, cw, ch);

    // 如果进度为0，直接显示当前页
    if (progress < 0.01) {
      logger.debug(TAG, `[renderCurlEffect] 进度<0.01，直接显示当前页`);
      if (this.currentImageBitmap) {
        try {
          // 使用ImageBitmap绘制（比直接使用PixelMap更稳定）
          ctx.drawImage(this.currentImageBitmap, ix, iy, iw, ih);
          logger.debug(TAG, `[renderCurlEffect] 进度为0，当前页绘制成功: dst=${iw.toFixed(0)}x${ih.toFixed(0)}, bitmap=${this.currentImageBitmap.width}x${this.currentImageBitmap.height}`);
        } catch (e) {
          logger.error(TAG, `[renderCurlEffect] 进度为0，绘制当前页失败: ${e}`);
        }
      } else {
        logger.warn(TAG, '[renderCurlEffect] 进度为0但当前页ImageBitmap为空');
      }
      return;
    }

    // 2. 先绘制下一页作为底层（完整显示）
    logger.debug(TAG, `[renderCurlEffect] 步骤2: 绘制下一页底层`);
    this.renderNextPage(ctx, ix, iy, iw, ih);

    // 3. 绘制当前页（带卷曲变形）
    logger.debug(TAG, `[renderCurlEffect] 步骤3: 绘制当前页卷曲效果, currentBitmap=${this.currentImageBitmap ? 'yes' : 'no'}`);
    if (this.currentImageBitmap) {
      this.renderCurrentPageWithCurl(ctx, ix, iy, iw, ih, progress);
    } else {
      logger.warn(TAG, `[renderCurlEffect] 当前页ImageBitmap为空，无法绘制卷曲效果，progress=${progress.toFixed(2)}`);
    }
  }

  /**
   * 绘制下一页（底层）
   */
  private renderNextPage(
    ctx: CanvasRenderingContext2D,
    ix: number, iy: number, iw: number, ih: number
  ): void {
    logger.debug(TAG, `[renderNextPage] 开始: nextBitmap=${this.nextImageBitmap ? 'yes' : 'no'}, 目标=(${ix.toFixed(0)},${iy.toFixed(0)},${iw.toFixed(0)},${ih.toFixed(0)})`);
    
    if (this.nextImageBitmap) {
      try {
        // 使用ImageBitmap绘制（比直接使用PixelMap更稳定）
        ctx.drawImage(this.nextImageBitmap, ix, iy, iw, ih);
        logger.debug(TAG, `[renderNextPage] 下一页绘制成功: dst=${iw.toFixed(0)}x${ih.toFixed(0)}, bitmap=${this.nextImageBitmap.width}x${this.nextImageBitmap.height}`);
      } catch (e) {
        logger.error(TAG, `[renderNextPage] 下一页绘制失败: ${e}`);
        ctx.fillStyle = '#2a2a2a';
        ctx.fillRect(ix, iy, iw, ih);
      }
    } else {
      // 没有下一页，用深灰色背景
      ctx.fillStyle = '#2a2a2a';
      ctx.fillRect(ix, iy, iw, ih);
      logger.debug(TAG, '[renderNextPage] 下一页ImageBitmap为空，使用灰色背景');
    }
  }

  /**
   * 绘制当前页（带卷曲变形）
   * 
   * 核心思路：
   * 1. 先绘制未卷起的部分（折叠线左侧）- 正常显示
   * 2. 再绘制卷起的部分（折叠线右侧）- 带3D变形效果
   */
  private renderCurrentPageWithCurl(
    ctx: CanvasRenderingContext2D,
    ix: number, iy: number, iw: number, ih: number,
    progress: number
  ): void {
    logger.debug(TAG, `[renderCurrentPageWithCurl] 开始: progress=${progress.toFixed(3)}, currentBitmap=${this.currentImageBitmap ? 'yes' : 'no'}`);
    
    if (!this.currentImageBitmap) {
      logger.warn(TAG, '[renderCurrentPageWithCurl] 当前页ImageBitmap为空，无法绘制');
      return;
    }

    // 折叠线位置（从右向左移动）
    const foldX: number = ix + iw * (1 - progress);
    
    // 卷曲参数
    const maxCurlHeight: number = this.config.maxCurlHeight;
    const curlHeight: number = maxCurlHeight * Math.sin(progress * Math.PI * 0.5);

    logger.debug(TAG, `[renderCurrentPageWithCurl] 参数: foldX=${foldX.toFixed(1)}, curlHeight=${curlHeight.toFixed(1)}, maxCurlHeight=${maxCurlHeight}`);

    // ===== 1. 绘制未卷起的部分（折叠线左侧）=====
    // 这部分图片正常显示，不需要变形
    const leftWidth: number = foldX - ix;
    logger.debug(TAG, `[renderCurrentPageWithCurl] 未卷起部分: leftWidth=${leftWidth.toFixed(1)}`);
    
    if (leftWidth > 0) {
      ctx.save();
      ctx.beginPath();
      ctx.rect(ix, iy, leftWidth, ih);
      ctx.clip();
      try {
        // 使用ImageBitmap绘制（比直接使用PixelMap更稳定）
        ctx.drawImage(this.currentImageBitmap, ix, iy, iw, ih);
        logger.debug(TAG, `[renderCurrentPageWithCurl] 未卷起部分绘制成功: clip=(${ix.toFixed(0)},${iy.toFixed(0)},${leftWidth.toFixed(0)},${ih.toFixed(0)})`);
      } catch (e) {
        logger.error(TAG, `[renderCurrentPageWithCurl] 绘制未卷起部分失败: ${e}`);
      }
      ctx.restore();
    } else {
      logger.debug(TAG, `[renderCurrentPageWithCurl] 跳过未卷起部分: leftWidth=${leftWidth.toFixed(1)} <= 0`);
    }

    // ===== 2. 绘制卷起的部分（折叠线右侧）=====
    // 使用垂直条带实现卷曲效果
    const curlWidth: number = ix + iw - foldX;
    logger.debug(TAG, `[renderCurrentPageWithCurl] 卷起部分: curlWidth=${curlWidth.toFixed(1)}`);
    
    if (curlWidth > 1) {
      const stripCount: number = Math.max(12, Math.floor(curlWidth / 10)); // 根据宽度动态调整条带数
      const stripW: number = curlWidth / stripCount;
      
      logger.debug(TAG, `[renderCurrentPageWithCurl] 条带参数: stripCount=${stripCount}, stripW=${stripW.toFixed(2)}`);
      
      let successCount = 0;
      let failCount = 0;
      
      for (let i = 0; i < stripCount; i++) {
        // 该条带在屏幕上的X位置
        const dstStripX: number = foldX + i * stripW;
        // 该条带在卷起区域中的相对位置 (0=折叠线, 1=最右边)
        const t: number = (i + 0.5) / stripCount;
        
        // Y方向偏移（越靠右偏移越大，模拟卷起抬升）
        const yOff: number = -curlHeight * Math.pow(t, 1.3);
        
        // X方向收缩（透视效果）
        const xShrink: number = stripW * t * 0.1;
        
        // 光照效果（卷起部分略暗）
        const alpha: number = 1.0 - t * 0.2;
        
        // 绘制该条带
        ctx.save();
        ctx.globalAlpha = alpha;
        
        // 裁剪区域：该条带在屏幕上的目标位置（带Y偏移）
        const dstY: number = iy + yOff;
        const dstW: number = stripW - xShrink + 1;
        ctx.beginPath();
        ctx.rect(dstStripX, dstY, dstW, ih);
        ctx.clip();
        
        // 绘制完整图片，裁剪区域只显示该条带
        try {
          ctx.drawImage(this.currentImageBitmap, ix, dstY, iw, ih);
          successCount++;
        } catch (e) {
          failCount++;
        }
        
        ctx.restore();
      }
      
      logger.debug(TAG, `[renderCurrentPageWithCurl] 条带绘制完成: 成功=${successCount}, 失败=${failCount}`);
    } else {
      logger.debug(TAG, `[renderCurrentPageWithCurl] 跳过卷起部分: curlWidth=${curlWidth.toFixed(1)} <= 1`);
    }

    // 3. 绘制阴影（在折叠线处，投射到下一页上）
    if (this.config.enableShadow && progress > 0.03) {
      this.renderFoldShadow(ctx, foldX, iy, ih, progress);
    }

    // 4. 绘制折叠线高光
    if (this.config.enableHighlight && progress > 0.02) {
      this.renderFoldHighlight(ctx, foldX, iy, ih, progress);
    }
  }

  /**
   * 绘制折叠线阴影（投射到下一页上）
   */
  private renderFoldShadow(
    ctx: CanvasRenderingContext2D,
    foldX: number, imgY: number, imgH: number,
    progress: number
  ): void {
    const shadowWidth: number = 40 * progress;
    const intensity: number = this.config.shadowIntensity * progress * 0.8;

    // 折叠线左侧的阴影（投射到下一页上）
    const grad: CanvasGradient = ctx.createLinearGradient(foldX - shadowWidth, 0, foldX, 0);
    grad.addColorStop(0, 'rgba(0,0,0,0)');
    grad.addColorStop(0.5, `rgba(0,0,0,${intensity * 0.3})`);
    grad.addColorStop(1, `rgba(0,0,0,${intensity})`);

    ctx.fillStyle = grad;
    ctx.fillRect(foldX - shadowWidth, imgY, shadowWidth, imgH);
  }

  /**
   * 绘制折叠线高光
   */
  private renderFoldHighlight(
    ctx: CanvasRenderingContext2D,
    foldX: number, imgY: number, imgH: number,
    progress: number
  ): void {
    const hlWidth: number = 3 + progress * 5;
    const hlIntensity: number = 0.3 + progress * 0.2;

    // 折叠线处的高光（模拟纸张边缘反光）
    const grad: CanvasGradient = ctx.createLinearGradient(foldX - hlWidth, 0, foldX + hlWidth, 0);
    grad.addColorStop(0, 'rgba(255,255,255,0)');
    grad.addColorStop(0.4, `rgba(255,255,255,${hlIntensity})`);
    grad.addColorStop(0.6, `rgba(255,255,255,${hlIntensity})`);
    grad.addColorStop(1, 'rgba(255,255,255,0)');

    ctx.fillStyle = grad;
    ctx.fillRect(foldX - hlWidth, imgY, hlWidth * 2, imgH);
  }

  // ========== 触摸交互处理（保留供将来独立使用） ==========
  
  /**
   * 处理触摸开始
   */
  private handleTouchStart(x: number, y: number): void {
    this.stopAnimation();
    this.isDragging = true;
    this.touchStartX = x;
    this.touchStartY = y;
    this.touchCurrentX = x;
    this.touchCurrentY = y;
    
    // 触摸开始时，如果在右侧区域，立即开始轻微的卷曲效果
    const rightEdge: number = this.imageDisplayX + this.imageDisplayWidth;
    if (x > rightEdge - this.imageDisplayWidth * 0.3) {
      // 在右侧30%区域开始拖拽，给一个初始的微小卷曲
      this.curlProgress = 0.02;
      this.renderCurlEffect();
    }
    
    logger.debug(TAG, `触摸开始: x=${x.toFixed(0)}, y=${y.toFixed(0)}`);
  }
  
  /**
   * 处理触摸移动
   */
  private handleTouchMove(x: number, y: number): void {
    if (!this.isDragging) return;
    
    this.touchCurrentX = x;
    this.touchCurrentY = y;
    
    // 计算拖拽距离（从右向左拖拽为正向翻页）
    const dragX: number = this.touchStartX - x;
    const imgWidth: number = this.imageDisplayWidth;
    
    // 将拖拽距离转换为进度 (0-1)
    // 拖拽整个图片宽度 = 100%进度
    let progress: number = dragX / imgWidth;
    
    // 限制进度范围
    progress = Math.max(0, Math.min(1, progress));
    
    // 添加一点阻尼效果，使拖拽感觉更自然
    if (progress > 0.8) {
      progress = 0.8 + (progress - 0.8) * 0.5;
    }
    
    this.curlProgress = progress;
    this.renderCurlEffect();
  }
  
  /**
   * 处理触摸结束
   */
  private handleTouchEnd(): void {
    if (!this.isDragging) return;
    this.isDragging = false;
    
    const threshold: number = this.config.flipThreshold;
    
    if (this.curlProgress >= threshold) {
      // 超过阈值，完成翻页
      this.animateToProgress(1.0, true);
    } else {
      // 未超过阈值，回弹
      this.animateToProgress(0, false);
    }
    
    logger.debug(TAG, `触摸结束: progress=${this.curlProgress.toFixed(2)}, threshold=${threshold}`);
  }
  
  /**
   * 动画到目标进度
   */
  private animateToProgress(targetProgress: number, isComplete: boolean): void {
    this.stopAnimation();
    
    const startProgress: number = this.curlProgress;
    const duration: number = this.config.animationDuration;
    const startTime: number = Date.now();
    
    const animate = (): void => {
      const elapsed: number = Date.now() - startTime;
      const t: number = Math.min(elapsed / duration, 1.0);
      
      // 使用缓动函数
      const eased: number = this.easeOutCubic(t);
      this.curlProgress = startProgress + (targetProgress - startProgress) * eased;
      
      this.renderCurlEffect();
      
      if (t < 1.0) {
        const timerId: number = setTimeout(animate, 16);
        this.animationTimer = timerId;
      } else {
        this.curlProgress = targetProgress;
        this.animationTimer = -1;
        
        // 触发回调
        if (targetProgress >= 0.99) {
          this.onPageFlip(true); // 翻页完成
        } else if (targetProgress <= 0.01) {
          this.onPageFlip(false); // 翻页取消
        }
      }
    };
    
    const timerId: number = setTimeout(animate, 16);
    this.animationTimer = timerId;
  }
  
  /**
   * 缓动函数 - 缓出
   */
  private easeOutCubic(t: number): number {
    return 1 - Math.pow(1 - t, 3);
  }
  
  /**
   * 外部调用：设置进度（用于外部动画驱动）
   */
  public setProgress(progress: number): void {
    this.curlProgress = Math.max(0, Math.min(1, progress));
    if (this.isReady) {
      this.renderCurlEffect();
    }
  }
  
  /**
   * 外部调用：完成翻页动画
   */
  public completeFlip(): void {
    this.animateToProgress(1.0, true);
  }
  
  /**
   * 外部调用：取消翻页（回弹）
   */
  public cancelFlip(): void {
    this.animateToProgress(0, false);
  }

  build() {
    Stack() {
      Canvas(this.canvasContext)
        .width(this.componentWidth)
        .height(this.componentHeight)
        .backgroundColor('#1a1a1a')
        .onReady(() => {
          logger.info(TAG, `[Canvas.onReady] Canvas就绪, currentPm=${this.currentPixelMap ? 'yes' : 'no'}, nextPm=${this.nextPixelMap ? 'yes' : 'no'}, externalProgress=${this.externalProgress.toFixed(3)}, curlProgress=${this.curlProgress.toFixed(3)}`);
          this.isReady = true;
          // 初始化时记录当前PixelMap引用并转换为ImageBitmap
          this.lastCurrentPixelMap = this.currentPixelMap;
          this.lastNextPixelMap = this.nextPixelMap;
          this.updateImageBitmaps();
          logger.info(TAG, `[Canvas.onReady] 调用renderCurlEffect`);
          this.renderCurlEffect();
        })
    }
    .width(this.componentWidth)
    .height(this.componentHeight)
    // 注意：触摸事件由外部MangaViewer处理
    // 本组件只负责渲染，进度由externalProgress控制
  }
}
