/**
 * 基于Canvas的3D卷页效果组件 V2
 * 
 * 核心特性：
 * 1. 可交互的拟真翻页 - 页面可以被"拎起"和"放下"
 * 2. 实时3D变形 - 拖拽开始时当前页立即变成立体的
 * 3. 可打断 - 随时松手，根据进度决定翻过去还是回弹
 * 4. 底层显示下一页 - 翻页时露出下面的下一页
 * 5. 使用PixelMap和5参数drawImage确保兼容性
 */

import { logger } from '../Utils/Logger';
import { image } from '@kit.ImageKit';

const TAG = 'PageCurlEffectV2';

/**
 * 翻页起始位置枚举
 */
export enum CurlStartPosition {
  RIGHT_EDGE = 'right_edge',       // 右边缘（整条边）- 向前翻页
  LEFT_EDGE = 'left_edge',         // 左边缘（整条边）- 向后翻页
  TOP_RIGHT = 'top_right',         // 右上角
  BOTTOM_RIGHT = 'bottom_right',   // 右下角
  TOP_LEFT = 'top_left',           // 左上角
  BOTTOM_LEFT = 'bottom_left'      // 左下角
}

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
  // 翻页起始位置
  @Prop curlStartPosition: CurlStartPosition = CurlStartPosition.RIGHT_EDGE;
  // 触摸起始坐标（相对于图片显示区域，用于自由点翻页）
  @Prop curlTouchX: number = 0;  // 触摸点X坐标
  @Prop curlTouchY: number = 0;  // 触摸点Y坐标
  
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
    
    // 判断翻页方向
    const isLeftSide: boolean = this.curlStartPosition === CurlStartPosition.LEFT_EDGE ||
                                this.curlStartPosition === CurlStartPosition.TOP_LEFT ||
                                this.curlStartPosition === CurlStartPosition.BOTTOM_LEFT;
    const isCorner: boolean = this.curlStartPosition !== CurlStartPosition.LEFT_EDGE &&
                              this.curlStartPosition !== CurlStartPosition.RIGHT_EDGE;

    logger.debug(TAG, `[renderCurlEffect] progress=${progress.toFixed(3)}, isForward=${this.isForward}, pos=${this.curlStartPosition}, isLeft=${isLeftSide}`);

    // 清空画布并重置透明度
    ctx.globalAlpha = 1.0;
    ctx.clearRect(0, 0, cw, ch);
    ctx.fillStyle = '#1a1a1a';
    ctx.fillRect(0, 0, cw, ch);

    // 进度为0时显示当前页
    if (progress < 0.01) {
      if (this.currentImageBitmap) {
        try {
          ctx.drawImage(this.currentImageBitmap, ix, iy, iw, ih);
          logger.debug(TAG, `[renderCurlEffect] 进度为0，当前页绘制成功`);
        } catch (e) {
          logger.error(TAG, `[renderCurlEffect] 绘制当前页失败: ${e}`);
        }
      }
      return;
    }

    // 使用统一的自由点翻页渲染
    this.renderFreeCurl(ctx, ix, iy, iw, ih, progress, isLeftSide);
  }
  
  /**
   * 自由点翻页渲染 - 支持从任意点开始翻页
   * 根据触摸起始点位置动态计算折叠效果
   */
  private renderFreeCurl(ctx: CanvasRenderingContext2D, ix: number, iy: number, iw: number, ih: number, progress: number, isLeftSide: boolean): void {
    const cw: number = this.componentWidth;
    const ch: number = this.componentHeight;
    
    // 计算触摸点在图片区域内的相对位置 (0-1)
    const touchRelX: number = Math.max(0, Math.min(1, (this.curlTouchX - ix) / iw));
    const touchRelY: number = Math.max(0, Math.min(1, (this.curlTouchY - iy) / ih));
    
    // 根据翻页方向确定起始边缘
    const startEdgeX: number = isLeftSide ? ix : ix + iw;
    
    // 计算折叠线的位置
    // 折叠线从触摸点的Y位置开始，X位置随进度移动
    const maxFoldDist: number = iw;  // 最大折叠距离
    const foldDist: number = maxFoldDist * progress;
    
    // 折叠线X位置
    const foldX: number = isLeftSide ? 
      ix + foldDist : 
      ix + iw - foldDist;
    
    // 触摸点Y位置决定折叠的"倾斜程度"
    // 如果触摸点在中间，折叠线垂直；如果在上下边缘，折叠线倾斜
    const touchYNorm: number = (touchRelY - 0.5) * 2;  // -1 到 1，0表示中间
    const tiltFactor: number = Math.abs(touchYNorm);   // 倾斜因子 0-1
    const tiltDirection: number = touchYNorm > 0 ? 1 : -1;  // 倾斜方向
    
    // 计算折叠线的倾斜（让折叠线通过触摸点）
    const tiltAmount: number = tiltFactor * foldDist * 0.5;  // 倾斜量
    
    // 折叠线的两个端点
    let foldTopY: number = iy;
    let foldBottomY: number = iy + ih;
    let foldTopX: number = foldX;
    let foldBottomX: number = foldX;
    
    if (tiltFactor > 0.1) {
      // 有明显倾斜时，调整折叠线端点
      if (tiltDirection > 0) {
        // 触摸点偏下，上端向外倾斜
        foldTopX = foldX + (isLeftSide ? -tiltAmount : tiltAmount);
      } else {
        // 触摸点偏上，下端向外倾斜
        foldBottomX = foldX + (isLeftSide ? -tiltAmount : tiltAmount);
      }
      // 限制在图片范围内
      foldTopX = Math.max(ix, Math.min(ix + iw, foldTopX));
      foldBottomX = Math.max(ix, Math.min(ix + iw, foldBottomX));
    }
    
    // 绘制下一页底层
    this.drawNextPageBase(ctx, cw, ch);
    
    // 绘制当前页（裁剪掉被折叠的部分）
    ctx.save();
    ctx.globalAlpha = 1.0;
    ctx.beginPath();
    if (isLeftSide) {
      // 左侧翻页：保留折叠线右侧的部分
      ctx.moveTo(foldTopX, foldTopY);
      ctx.lineTo(foldBottomX, foldBottomY);
      ctx.lineTo(ix + iw, iy + ih);
      ctx.lineTo(ix + iw, iy);
      ctx.closePath();
    } else {
      // 右侧翻页：保留折叠线左侧的部分
      ctx.moveTo(foldTopX, foldTopY);
      ctx.lineTo(foldBottomX, foldBottomY);
      ctx.lineTo(ix, iy + ih);
      ctx.lineTo(ix, iy);
      ctx.closePath();
    }
    ctx.clip();
    
    if (this.currentImageBitmap) {
      try {
        ctx.drawImage(this.currentImageBitmap, ix, iy, iw, ih);
      } catch (e) { /* ignore */ }
    }
    ctx.restore();
    
    // 绘制翻起的书页背面
    this.renderFreeFlip(ctx, ix, iy, iw, ih, progress, isLeftSide, foldTopX, foldTopY, foldBottomX, foldBottomY, tiltAmount, tiltDirection);
  }
  
  /**
   * 自由点翻页的书页背面渲染
   */
  private renderFreeFlip(
    ctx: CanvasRenderingContext2D,
    ix: number, iy: number, iw: number, ih: number,
    progress: number, isLeftSide: boolean,
    foldTopX: number, foldTopY: number,
    foldBottomX: number, foldBottomY: number,
    tiltAmount: number, tiltDirection: number
  ): void {
    if (progress < 0.01) return;
    
    // 计算翻起的宽度
    const flipWidth: number = isLeftSide ?
      Math.max(foldTopX, foldBottomX) - ix :
      ix + iw - Math.min(foldTopX, foldBottomX);
    
    if (flipWidth < 3) return;
    
    // 计算翻起区域的四个顶点
    const edgeX: number = isLeftSide ? ix : ix + iw;
    
    // 翻起后的位置（镜像）
    const flippedTopX: number = isLeftSide ?
      foldTopX + (foldTopX - edgeX) :
      foldTopX - (edgeX - foldTopX);
    const flippedBottomX: number = isLeftSide ?
      foldBottomX + (foldBottomX - edgeX) :
      foldBottomX - (edgeX - foldBottomX);
    
    // 限制在合理范围内
    const clampedFlipTopX: number = Math.max(ix, Math.min(ix + iw, flippedTopX));
    const clampedFlipBottomX: number = Math.max(ix, Math.min(ix + iw, flippedBottomX));
    
    // 绘制翻起的区域
    ctx.save();
    ctx.beginPath();
    ctx.moveTo(foldTopX, foldTopY);
    ctx.lineTo(foldBottomX, foldBottomY);
    ctx.lineTo(clampedFlipBottomX, foldBottomY);
    ctx.lineTo(clampedFlipTopX, foldTopY);
    ctx.closePath();
    ctx.clip();
    
    // 绘制镜像图片
    if (this.currentImageBitmap) {
      // 计算折叠线中点
      const foldMidX: number = (foldTopX + foldBottomX) / 2;
      const foldMidY: number = (foldTopY + foldBottomY) / 2;
      
      // 计算折叠线角度
      const foldDx: number = foldBottomX - foldTopX;
      const foldDy: number = foldBottomY - foldTopY;
      const foldAngle: number = Math.atan2(foldDy, foldDx);
      
      // 镜像变换：关于折叠线进行镜像
      // 1. 移动到折叠线中点
      // 2. 旋转使折叠线与X轴平行
      // 3. Y轴镜像（翻转到折叠线另一侧）
      // 4. 反向旋转
      // 5. 移回原位
      ctx.translate(foldMidX, foldMidY);
      ctx.rotate(foldAngle);
      ctx.scale(1, -1);  // 关于折叠线镜像（Y轴翻转）
      ctx.rotate(-foldAngle);
      ctx.translate(-foldMidX, -foldMidY);
      
      ctx.globalAlpha = 0.9;
      try {
        ctx.drawImage(this.currentImageBitmap, ix, iy, iw, ih);
      } catch (e) { /* ignore */ }
      
      // 添加纸张背面效果
      ctx.globalAlpha = 0.2;
      ctx.fillStyle = '#f0ebe3';
      ctx.fill();
    } else {
      ctx.fillStyle = '#e8e3db';
      ctx.fill();
    }
    
    ctx.restore();
    
    // 绘制折叠线高光
    ctx.save();
    ctx.beginPath();
    ctx.moveTo(foldTopX, foldTopY);
    ctx.lineTo(foldBottomX, foldBottomY);
    ctx.strokeStyle = 'rgba(255, 255, 255, 0.6)';
    ctx.lineWidth = 2;
    ctx.stroke();
    ctx.restore();
    
    // 绘制阴影
    if (this.config.enableShadow && progress > 0.1) {
      ctx.save();
      ctx.globalAlpha = 0.15 * progress;
      ctx.strokeStyle = '#000000';
      ctx.lineWidth = flipWidth * 0.15;
      ctx.lineCap = 'round';
      ctx.beginPath();
      ctx.moveTo(foldTopX, foldTopY);
      ctx.lineTo(foldBottomX, foldBottomY);
      ctx.stroke();
      ctx.restore();
    }
  }

  /**
   * 右边缘翻页（向前翻，从右向左）
   */
  private renderRightEdgeCurl(ctx: CanvasRenderingContext2D, ix: number, iy: number, iw: number, ih: number, progress: number): void {
    const cw: number = this.componentWidth;
    const ch: number = this.componentHeight;
    const foldX: number = ix + iw * (1 - progress);
    
    // 绘制下一页底层
    this.drawNextPageBase(ctx, cw, ch);
    // 绘制当前页（折叠线左侧）
    this.renderImageClipped(ctx, this.currentImageBitmap, ix, iy, iw, ih, foldX);
    // 绘制翻起的书页背面
    if (this.currentImageBitmap) {
      this.renderFlippedPageBack(ctx, ix, iy, iw, ih, progress, foldX);
    }
  }

  /**
   * 左边缘翻页（向后翻，从左向右）
   */
  private renderLeftEdgeCurl(ctx: CanvasRenderingContext2D, ix: number, iy: number, iw: number, ih: number, progress: number): void {
    const cw: number = this.componentWidth;
    const ch: number = this.componentHeight;
    const foldX: number = ix + iw * progress;
    
    // 绘制下一页底层
    this.drawNextPageBase(ctx, cw, ch);
    // 绘制当前页（折叠线右侧）
    this.renderImageClippedLeft(ctx, this.currentImageBitmap, ix, iy, iw, ih, foldX);
    // 绘制翻起的书页背面（向左翻）
    if (this.currentImageBitmap) {
      this.renderFlippedPageBackLeft(ctx, ix, iy, iw, ih, progress, foldX);
    }
  }

  /**
   * 角落翻页
   */
  private renderCornerCurl(ctx: CanvasRenderingContext2D, ix: number, iy: number, iw: number, ih: number, progress: number, isLeft: boolean): void {
    const cw: number = this.componentWidth;
    const ch: number = this.componentHeight;
    const isTop: boolean = this.curlStartPosition === CurlStartPosition.TOP_RIGHT || 
                           this.curlStartPosition === CurlStartPosition.TOP_LEFT;
    
    // 翻起的距离随进度增加 - 使用与边缘翻页一致的线性映射
    // 最大翻起距离设为图片宽度，与边缘翻页保持一致的响应速度
    const maxCurlDist: number = iw;
    const curlDist: number = maxCurlDist * progress;
    
    // 绘制下一页底层
    this.drawNextPageBase(ctx, cw, ch);
    
    // 计算折叠线的两个端点
    let foldP1X: number, foldP1Y: number, foldP2X: number, foldP2Y: number;
    let cornerX: number, cornerY: number;  // 被掀起的角落坐标
    
    if (isLeft) {
      cornerX = ix;
      if (isTop) {
        cornerY = iy;
        foldP1X = ix;
        foldP1Y = iy + curlDist;
        foldP2X = ix + curlDist;
        foldP2Y = iy;
      } else {
        cornerY = iy + ih;
        foldP1X = ix;
        foldP1Y = iy + ih - curlDist;
        foldP2X = ix + curlDist;
        foldP2Y = iy + ih;
      }
    } else {
      cornerX = ix + iw;
      if (isTop) {
        cornerY = iy;
        foldP1X = ix + iw - curlDist;
        foldP1Y = iy;
        foldP2X = ix + iw;
        foldP2Y = iy + curlDist;
      } else {
        cornerY = iy + ih;
        foldP1X = ix + iw;
        foldP1Y = iy + ih - curlDist;
        foldP2X = ix + iw - curlDist;
        foldP2Y = iy + ih;
      }
    }
    
    // 绘制当前页（裁剪掉被掀起的角落）
    ctx.save();
    ctx.beginPath();
    ctx.moveTo(foldP1X, foldP1Y);
    ctx.lineTo(foldP2X, foldP2Y);
    // 沿着边缘绘制剩余的矩形区域
    if (isLeft) {
      if (isTop) {
        ctx.lineTo(ix + iw, iy);
        ctx.lineTo(ix + iw, iy + ih);
        ctx.lineTo(ix, iy + ih);
        ctx.lineTo(ix, foldP1Y);
      } else {
        ctx.lineTo(ix + iw, iy + ih);
        ctx.lineTo(ix + iw, iy);
        ctx.lineTo(ix, iy);
        ctx.lineTo(ix, foldP1Y);
      }
    } else {
      if (isTop) {
        // 右上角：折叠线从 (ix+iw-curlDist, iy) 到 (ix+iw, iy+curlDist)
        ctx.lineTo(ix + iw, iy + ih);
        ctx.lineTo(ix, iy + ih);
        ctx.lineTo(ix, iy);
        ctx.lineTo(foldP1X, iy);
      } else {
        // 右下角：折叠线从 (ix+iw, iy+ih-curlDist) 到 (ix+iw-curlDist, iy+ih)
        // 正确顺序：先到左下角，再逆时针绕回
        ctx.lineTo(ix, iy + ih);
        ctx.lineTo(ix, iy);
        ctx.lineTo(ix + iw, iy);
        ctx.lineTo(ix + iw, foldP1Y);
      }
    }
    ctx.closePath();
    ctx.clip();
    
    // 确保当前页完全不透明，避免透视看到下一页
    ctx.globalAlpha = 1.0;
    if (this.currentImageBitmap) {
      try {
        ctx.drawImage(this.currentImageBitmap, ix, iy, iw, ih);
      } catch (e) { /* ignore */ }
    }
    ctx.restore();
    
    // 绘制翻起的角落（书页背面）
    this.renderCornerFlip(ctx, progress, isLeft, isTop, foldP1X, foldP1Y, foldP2X, foldP2Y, cornerX, cornerY, curlDist);
  }

  /**
   * 绘制角落翻起效果
   * 正确的角落翻页：沿对角线折叠，显示页面背面
   */
  private renderCornerFlip(
    ctx: CanvasRenderingContext2D, 
    progress: number, isLeft: boolean, isTop: boolean,
    foldP1X: number, foldP1Y: number, foldP2X: number, foldP2Y: number,
    cornerX: number, cornerY: number, curlDist: number
  ): void {
    if (curlDist < 3) return;
    
    // 计算翻起后角落的新位置（沿折叠线镜像）
    // 折叠线的中点
    const foldMidX: number = (foldP1X + foldP2X) / 2;
    const foldMidY: number = (foldP1Y + foldP2Y) / 2;
    
    // 折叠线的方向向量（单位化）
    const foldDx: number = foldP2X - foldP1X;
    const foldDy: number = foldP2Y - foldP1Y;
    const foldLen: number = Math.sqrt(foldDx * foldDx + foldDy * foldDy);
    if (foldLen < 1) return;
    
    const foldNx: number = foldDx / foldLen;  // 折叠线方向单位向量
    const foldNy: number = foldDy / foldLen;
    
    // 计算角落点关于折叠线的镜像位置
    const cornerToFoldX: number = cornerX - foldMidX;
    const cornerToFoldY: number = cornerY - foldMidY;
    // 投影到折叠线上
    const proj: number = cornerToFoldX * foldNx + cornerToFoldY * foldNy;
    const projX: number = proj * foldNx;
    const projY: number = proj * foldNy;
    // 垂直分量
    const perpX: number = cornerToFoldX - projX;
    const perpY: number = cornerToFoldY - projY;
    // 镜像后的角落位置（垂直分量取反）
    const flippedCornerX: number = foldMidX + projX - perpX;
    const flippedCornerY: number = foldMidY + projY - perpY;
    
    // 绘制翻起的三角形区域（书页背面 + 镜像图片）
    ctx.save();
    ctx.beginPath();
    ctx.moveTo(foldP1X, foldP1Y);
    ctx.lineTo(foldP2X, foldP2Y);
    ctx.lineTo(flippedCornerX, flippedCornerY);
    ctx.closePath();
    ctx.clip();
    
    // 绘制镜像图片
    if (this.currentImageBitmap) {
      // 计算折叠线的角度（预计算避免重复）
      const foldAngle: number = Math.atan2(foldDy, foldDx);
      
      // 镜像变换
      ctx.translate(foldMidX, foldMidY);
      ctx.rotate(foldAngle);
      ctx.scale(1, -1);
      ctx.rotate(-foldAngle);
      ctx.translate(-foldMidX, -foldMidY);
      
      // 绘制镜像后的当前页图片
      ctx.globalAlpha = 0.9;
      try {
        ctx.drawImage(this.currentImageBitmap, this.imageDisplayX, this.imageDisplayY, 
                      this.imageDisplayWidth, this.imageDisplayHeight);
      } catch (e) { /* ignore */ }
      
      // 添加纸张背面效果
      ctx.globalAlpha = 0.25;
      ctx.fillStyle = '#f0ebe3';
      ctx.fill();
    } else {
      // 没有图片时填充背景色
      ctx.fillStyle = '#e8e3db';
      ctx.fill();
    }
    
    // 添加折叠线高光效果
    ctx.beginPath();
    ctx.moveTo(foldP1X, foldP1Y);
    ctx.lineTo(foldP2X, foldP2Y);
    ctx.strokeStyle = 'rgba(255, 255, 255, 0.7)';
    ctx.lineWidth = 2;
    ctx.stroke();
    
    ctx.restore();
    
    // 简化阴影：只在折叠线处绘制一条阴影线
    if (this.config.enableShadow && progress > 0.1) {
      ctx.save();
      ctx.globalAlpha = 0.2 * progress;
      ctx.strokeStyle = '#000000';
      ctx.lineWidth = curlDist * 0.1;
      ctx.lineCap = 'round';
      ctx.beginPath();
      ctx.moveTo(foldP1X, foldP1Y);
      ctx.lineTo(foldP2X, foldP2Y);
      ctx.stroke();
      ctx.restore();
    }
  }

  /**
   * 绘制下一页作为底层
   */
  private drawNextPageBase(ctx: CanvasRenderingContext2D, cw: number, ch: number): void {
    if (!this.nextImageBitmap) return;
    ctx.save();
    ctx.globalAlpha = 1.0;  // 确保下一页完全不透明
    try {
      const nextW = this.nextImageBitmap.width;
      const nextH = this.nextImageBitmap.height;
      let dstX = 0, dstY = 0, dstW = cw, dstH = ch;
      if (nextW > 0 && nextH > 0) {
        const scale = Math.min(cw / nextW, ch / nextH);
        dstW = nextW * scale;
        dstH = nextH * scale;
        dstX = (cw - dstW) / 2;
        dstY = (ch - dstH) / 2;
      }
      ctx.drawImage(this.nextImageBitmap, dstX, dstY, dstW, dstH);
    } catch (e) {
      logger.error(TAG, `[drawNextPageBase] 失败: ${e}`);
    }
    ctx.restore();
  }

  /**
   * 左边缘翻页：裁剪到折叠线右侧
   */
  private renderImageClippedLeft(ctx: CanvasRenderingContext2D, bitmap: ImageBitmap | null, ix: number, iy: number, iw: number, ih: number, foldX: number): void {
    const clipWidth = ix + iw - foldX;
    if (clipWidth <= 0 || !bitmap) return;
    ctx.save();
    ctx.globalAlpha = 1.0;  // 确保当前页完全不透明
    ctx.beginPath();
    ctx.rect(foldX, iy, clipWidth, ih);
    ctx.clip();
    try {
      ctx.drawImage(bitmap, ix, iy, iw, ih);
    } catch (e) { /* ignore */ }
    ctx.restore();
  }

  /**
   * 左边缘翻页的书页背面
   */
  private renderFlippedPageBackLeft(ctx: CanvasRenderingContext2D, ix: number, iy: number, iw: number, ih: number, progress: number, foldX: number): void {
    const curlWidth: number = foldX - ix;
    const maxCurlH: number = this.config.maxCurlHeight;
    const curlH: number = maxCurlH * Math.sin(progress * Math.PI * 0.5);
    if (curlWidth <= 1) return;
    
    const flipW: number = Math.min(curlWidth, iw * 0.5);
    const flipEndX: number = foldX + flipW;
    
    ctx.save();
    ctx.beginPath();
    ctx.rect(foldX - 2, iy - curlH * 0.3, flipW + 4, ih + curlH * 0.6);
    ctx.clip();
    
    // 镜像（以折叠线为轴）
    ctx.translate(foldX, 0);
    ctx.scale(-1, 1);
    ctx.translate(-foldX, 0);
    
    const liftY: number = -curlH * 0.2 * (1 - flipW / (iw * 0.5));
    ctx.globalAlpha = 1.0;
    try {
      ctx.drawImage(this.currentImageBitmap!, ix, iy + liftY, iw, ih);
    } catch (e) { /* ignore */ }
    ctx.restore();
    
    // 阴影
    if (flipW > 5) {
      ctx.save();
      const grad = ctx.createLinearGradient(foldX, iy, flipEndX, iy);
      grad.addColorStop(0, 'rgba(0,0,0,0.15)');
      grad.addColorStop(0.3, 'rgba(0,0,0,0.05)');
      grad.addColorStop(1, 'rgba(0,0,0,0)');
      ctx.fillStyle = grad;
      ctx.fillRect(foldX, iy - curlH * 0.3, flipW, ih + curlH * 0.6);
      ctx.restore();
    }
    
    // 折叠线效果
    if (this.config.enableShadow && progress > 0.03) {
      this.renderFoldShadowLeft(ctx, foldX, iy, ih, progress);
    }
    if (this.config.enableHighlight && progress > 0.02) {
      this.renderFoldHighlightLeft(ctx, foldX, iy, ih, progress);
    }
  }

  /**
   * 左边缘翻页的折叠线阴影
   */
  private renderFoldShadowLeft(ctx: CanvasRenderingContext2D, foldX: number, imgY: number, imgH: number, progress: number): void {
    const shadowW: number = 40 * progress;
    const intensity: number = this.config.shadowIntensity * progress * 0.8;
    const grad = ctx.createLinearGradient(foldX, 0, foldX + shadowW, 0);
    grad.addColorStop(0, `rgba(0,0,0,${intensity})`);
    grad.addColorStop(0.5, `rgba(0,0,0,${intensity * 0.3})`);
    grad.addColorStop(1, 'rgba(0,0,0,0)');
    ctx.fillStyle = grad;
    ctx.fillRect(foldX, imgY, shadowW, imgH);
  }

  /**
   * 左边缘翻页的折叠线高光
   */
  private renderFoldHighlightLeft(ctx: CanvasRenderingContext2D, foldX: number, imgY: number, imgH: number, progress: number): void {
    const hlW: number = 3 + progress * 5;
    const hlI: number = 0.3 + progress * 0.2;
    const grad = ctx.createLinearGradient(foldX - hlW, 0, foldX + hlW, 0);
    grad.addColorStop(0, 'rgba(255,255,255,0)');
    grad.addColorStop(0.4, `rgba(255,255,255,${hlI})`);
    grad.addColorStop(0.6, `rgba(255,255,255,${hlI})`);
    grad.addColorStop(1, 'rgba(255,255,255,0)');
    ctx.fillStyle = grad;
    ctx.fillRect(foldX - hlW, imgY, hlW * 2, imgH);
  }

  /**
   * 绘制图片并裁剪到折叠线左侧
   */
  private renderImageClipped(
    ctx: CanvasRenderingContext2D,
    bitmap: ImageBitmap | null,
    ix: number, iy: number, iw: number, ih: number,
    foldX: number
  ): void {
    const clipWidth = foldX - ix;
    logger.debug(TAG, `[renderImageClipped] 开始: bitmap=${bitmap ? 'yes' : 'no'}, clipWidth=${clipWidth.toFixed(1)}`);
    
    if (clipWidth <= 0) {
      return;
    }
    
    if (bitmap) {
      ctx.save();
      ctx.globalAlpha = 1.0;  // 确保当前页完全不透明
      // 裁剪到折叠线左侧区域
      ctx.beginPath();
      ctx.rect(ix, iy, clipWidth, ih);
      ctx.clip();
      
      try {
        ctx.drawImage(bitmap, ix, iy, iw, ih);
      } catch (e) {
        logger.error(TAG, `[renderImageClipped] 绘制失败: ${e}`);
      }
      ctx.restore();
    }
  }

  /**
   * 绘制翻起的书页背面（镜像效果）
   */
  private renderFlippedPageBack(
    ctx: CanvasRenderingContext2D,
    ix: number, iy: number, iw: number, ih: number,
    progress: number,
    foldX: number
  ): void {
    const curlWidth: number = ix + iw - foldX;
    const maxCurlHeight: number = this.config.maxCurlHeight;
    const curlHeight: number = maxCurlHeight * Math.sin(progress * Math.PI * 0.5);
    
    if (curlWidth <= 1) {
      return;
    }
    
    // 计算翻起部分的宽度（在折叠线左侧显示的镜像宽度）
    const flipWidth: number = Math.min(curlWidth, iw * 0.5);
    const flipStartX: number = foldX - flipWidth;
    
    ctx.save();
    
    // 裁剪区域：折叠线左侧的翻起部分
    ctx.beginPath();
    ctx.rect(flipStartX, iy - curlHeight * 0.3, flipWidth + 2, ih + curlHeight * 0.6);
    ctx.clip();
    
    // 绘制书页背面（镜像效果）
    ctx.translate(foldX, 0);
    ctx.scale(-1, 1);
    ctx.translate(-foldX, 0);
    
    // 轻微的Y偏移模拟抬起效果
    const liftY: number = -curlHeight * 0.2 * (1 - flipWidth / (iw * 0.5));
    
    // 背面略暗，但不要透明，否则会透出底下的内容
    ctx.globalAlpha = 1.0;
    
    try {
      ctx.drawImage(this.currentImageBitmap!, ix, iy + liftY, iw, ih);
      logger.debug(TAG, `[renderFlippedPageBack] 书页背面绘制成功, flipWidth=${flipWidth.toFixed(1)}`);
    } catch (e) {
      logger.error(TAG, `[renderFlippedPageBack] 书页背面绘制失败: ${e}`);
    }
    
    ctx.restore();
    
    // 添加阴影效果
    if (flipWidth > 5) {
      ctx.save();
      const shadowGradient = ctx.createLinearGradient(flipStartX, iy, foldX, iy);
      shadowGradient.addColorStop(0, 'rgba(0,0,0,0)');
      shadowGradient.addColorStop(0.7, 'rgba(0,0,0,0.05)');
      shadowGradient.addColorStop(1, 'rgba(0,0,0,0.15)');
      ctx.fillStyle = shadowGradient;
      ctx.fillRect(flipStartX, iy - curlHeight * 0.3, flipWidth, ih + curlHeight * 0.6);
      ctx.restore();
    }
    
    // 绘制折叠线阴影
    if (this.config.enableShadow && progress > 0.03) {
      this.renderFoldShadow(ctx, foldX, iy, ih, progress);
    }
    
    // 绘制折叠线高光
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
