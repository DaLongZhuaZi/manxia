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
  animationDuration: 200,  // 减少动画时长，使翻页更流畅
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
  // 卷页背面透明度（0-100，100为完全不透明）
  @Prop curlBackOpacity: number = 90;
  
  // ========== 外部控制的进度（用于外部动画驱动） ==========
  @Prop @Watch('onExternalProgressChange') externalProgress: number = -1; // -1表示不使用外部进度
  
  // ========== 内部动画控制（高性能模式） ==========
  // 当设置为 true 时，组件内部控制动画循环，避免每帧更新 @Prop 的开销
  @Prop @Watch('onAnimateToTargetChange') animateToTarget: number = -1;  // 目标进度，-1 表示不使用内部动画
  @Prop animateFromProgress: number = 0;  // 动画起始进度
  @Prop animateVelocity: number = 0;      // 脱手速度（progress/ms），用于速度延续动画；0 = 使用默认时长
  
  // ========== 回调 ==========
  // 翻页完成回调
  onPageFlip: OnPageFlipCallback = (_completed: boolean) => {};
  // 动画完成回调（内部动画模式）
  onAnimationComplete: () => void = () => {};
  
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
  
  // 弹簧平滑状态（掀角位置 + 速度）
  private smoothPeelX: number = -1;
  private smoothPeelY: number = -1;
  private springVelocityX: number = 0;
  private springVelocityY: number = 0;
  // 锚点角落缓存（拖拽期间固定，避免手指移动时角落突变）
  private anchorAY: number = -1;
  
  // 动画相关
  private animationTimer: number = -1;
  // 动画期间弹簧软化标记
  private isReleaseAnimating: boolean = false;
  // 当动画目标在 Canvas 未就绪时先缓存，待 onReady 后补触发。
  private pendingAnimateAfterReady: boolean = false;
  
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
        // 【修复】先验证 PixelMap 是否仍然有效（可能已被外部释放）
        const pmInfo = this.currentPixelMap.getImageInfoSync();
        if (!pmInfo || !pmInfo.size || pmInfo.size.width <= 0) {
          logger.error(TAG, `[updateImageBitmaps] 当前页PixelMap已失效（getImageInfoSync返回无效信息）`);
          this.currentImageBitmap = null;
        } else {
          logger.info(TAG, `[updateImageBitmaps] 当前页PixelMap信息: ${pmInfo.size.width}x${pmInfo.size.height}, format=${pmInfo.pixelFormat}`);
          const bitmap = new ImageBitmap(this.currentPixelMap);
          if (bitmap) {
            this.currentImageBitmap = bitmap;
            logger.info(TAG, `[updateImageBitmaps] 当前页ImageBitmap创建完成: w=${bitmap.width}, h=${bitmap.height}`);
          } else {
            logger.error(TAG, `[updateImageBitmaps] 当前页ImageBitmap创建返回null/undefined`);
            this.currentImageBitmap = null;
          }
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
        // 【修复】先验证 PixelMap 是否仍然有效
        const pmInfo = this.nextPixelMap.getImageInfoSync();
        if (!pmInfo || !pmInfo.size || pmInfo.size.width <= 0) {
          logger.error(TAG, `[updateImageBitmaps] 下一页PixelMap已失效（getImageInfoSync返回无效信息）`);
          this.nextImageBitmap = null;
        } else {
          logger.info(TAG, `[updateImageBitmaps] 下一页PixelMap信息: ${pmInfo.size.width}x${pmInfo.size.height}, format=${pmInfo.pixelFormat}`);
          const bitmap = new ImageBitmap(this.nextPixelMap);
          if (bitmap) {
            this.nextImageBitmap = bitmap;
            logger.info(TAG, `[updateImageBitmaps] 下一页ImageBitmap创建完成: w=${bitmap.width}, h=${bitmap.height}`);
          } else {
            logger.error(TAG, `[updateImageBitmaps] 下一页ImageBitmap创建返回null/undefined`);
            this.nextImageBitmap = null;
          }
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
   * 注意：这是热路径，避免任何不必要的开销
   */
  onExternalProgressChange(): void {
    // 热路径：移除日志输出以提高性能
    if (this.externalProgress >= 0 && this.isReady) {
      // 只在首次或 PixelMap 真正变化时更新 Bitmap（移到外部控制）
      this.curlProgress = this.externalProgress;
      this.renderCurlEffect();
    }
  }
  
  /**
   * 内部动画控制：当 animateToTarget 变化时触发
   * 高性能模式：动画循环完全在组件内部执行，避免每帧更新 @Prop
   *
   * 动画时长由脱手速度（animateVelocity）决定，使动画无缝延续用户的翻页力度：
   *  - 有速度时：duration = 3 * Δ / v（easeOutCubic 初始斜率=3 → 动画开始速度 = 用户脱手速度）
   *  - 无速度时：使用基于进度的默认时长
   */
  onAnimateToTargetChange(): void {
    if (this.animateToTarget < 0) {
      this.pendingAnimateAfterReady = false;
      return;
    }
    if (!this.isReady) {
      this.pendingAnimateAfterReady = true;
      return;
    }
    this.pendingAnimateAfterReady = false;
    
    // 停止之前的动画
    this.stopAnimation();
    
    // 使用组件内部的 curlProgress 作为起始进度（上一帧拖拽的最终位置）
    const startProgress: number = this.curlProgress;
    const targetProgress: number = this.animateToTarget;
    const progressDelta: number = Math.abs(targetProgress - startProgress);
    
    // 进度已接近目标，直接完成
    if (progressDelta < 0.01) {
      this.curlProgress = targetProgress;
      this.renderCurlEffect();
      this.onAnimationComplete();
      return;
    }
    
    const isComplete: boolean = targetProgress > startProgress;
    const velocity: number = this.animateVelocity;  // progress/ms，由 MangaViewer 传入
    
    let duration: number;
    // 缓动类型: 0=重力落下(取消回弹), 1=速度延续+微过冲(完成有速度), 2=重力辅助(完成无速度)
    let easingType: number;
    
    if (!isComplete) {
      // ① 取消回弹 — 重力加速 + 微弹跳
      // 时长增加至 max(280, ...) 使物理感更充分
      duration = Math.max(280, this.config.animationDuration * progressDelta * 1.8 * 1.2);
      easingType = 0;
    } else if (velocity > 0.0003) {
      // ② 完成翻页（有速度）— 速度延续 + 末尾微过冲
      // easeOutCubic 的归一化初始斜率 = 3
      // 令 3 * Δ / T = v  →  T = 3 * Δ / v
      // 这样动画第一帧的实际速度恰好等于用户脱手时的速度，实现无缝衔接
      const physDuration: number = 3.0 * progressDelta / velocity;
      duration = Math.min(420, Math.max(100, physDuration));
      easingType = 1;
    } else {
      // ③ 完成翻页（无速度）— 重力辅助 easeInOutCubic
      // 先加速再减速，感觉更像页面在重力下翻过去
      duration = Math.max(160, this.config.animationDuration * progressDelta * 1.2);
      easingType = 2;
    }
    
    // 2d. 释放后弹簧参数软化：stiffness 从 0.15 临时降低到 0.08
    this.isReleaseAnimating = true;
    
    const startTime: number = Date.now();
    
    const animate = (): void => {
      const now: number = Date.now();
      const elapsed: number = now - startTime;
      const t: number = Math.min(elapsed / Math.max(duration, 50), 1.0);
      
      // 根据场景选择缓动函数
      let eased: number;
      if (easingType === 0) {
        eased = this.easeGravityDrop(t);
      } else if (easingType === 1) {
        eased = this.easeOutCubicWithOvershoot(t);
      } else {
        eased = this.easeInOutCubic(t);
      }
      
      this.curlProgress = startProgress + (targetProgress - startProgress) * eased;
      this.renderCurlEffect();
      
      if (t < 1.0) {
        // 动态补偿帧处理时间，维持接近 60fps
        const frameTime: number = Date.now() - now;
        const nextDelay: number = Math.max(1, 16 - frameTime);
        this.animationTimer = setTimeout(animate, nextDelay);
      } else {
        this.curlProgress = targetProgress;
        this.renderCurlEffect();
        this.animationTimer = -1;
        this.isReleaseAnimating = false;  // 恢复弹簧参数
        this.onAnimationComplete();
      }
    };
    
    // 立即执行第一帧（同步），避免 setTimeout 引入额外延迟
    animate();
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
   * 渲染翻页效果
   * 
   * 核心理念：垂直平分线折叠模型——沿锚点角落到拖拽位置的垂直平分线折叠
   * 页面被分为平面侧（显示当前页）和翻起侧（镜像显示背面）
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

    // 清空画布（保持透明背景）
    ctx.globalAlpha = 1.0;
    ctx.clearRect(0, 0, cw, ch);

    // 检查 ImageBitmap 是否可用，如果不可用则跳过渲染
    // 这样可以避免空白画布遮挡底层内容
    if (!this.currentImageBitmap) {
      return;
    }

    // 进度为0时显示当前页，并重置阻尼状态
    if (progress < 0.01) {
      this.smoothPeelX = -1;
      this.smoothPeelY = -1;
      this.springVelocityX = 0;
      this.springVelocityY = 0;
      this.anchorAY = -1;
      try {
        ctx.drawImage(this.currentImageBitmap, ix, iy, iw, ih);
      } catch (e) { /* ignore */ }
      return;
    }

    // 使用统一的自由点翻页渲染
    this.renderFreeCurl(ctx, ix, iy, iw, ih, progress, isLeftSide);
  }
  
  /**
   * 真实翻页效果（垂直平分线折叠模型）
   *
   * 核心算法：
   * 1. 确定被掀起的角落 A（锚点）
   * 2. 根据 progress 计算角落被拖拽到的位置 P
   * 3. 折叠线 = A→P 的垂直平分线
   * 4. 页面矩形沿折叠线分为 “平面” 和 “翻起” 两个多边形
   * 5. 平面侧显示当前页，翻起侧沿折叠线镜像显示背面
   */
  private renderFreeCurl(ctx: CanvasRenderingContext2D, ix: number, iy: number, iw: number, ih: number, progress: number, isLeftSide: boolean): void {
    if (progress < 0.005) return;
    const cw: number = this.componentWidth;
    const ch: number = this.componentHeight;

    // === 1. 确定锚点角落 ===
    const touchRelY: number = Math.max(0, Math.min(1, (this.curlTouchY - iy) / ih));
    const ax: number = isLeftSide ? ix : ix + iw;
    // 锚点Y在拖拽开始时固定，避免手指上下移动时角落突变
    if (this.anchorAY < 0) {
      this.anchorAY = touchRelY >= 0.5 ? iy + ih : iy;
    }
    const ay: number = this.anchorAY;

    // === 2. 计算角落被拖拽到的位置 ===
    const dir: number = isLeftSide ? 1 : -1;
    let px: number = ax + dir * 2 * progress * iw;
    // Y方向：跟随当前手指Y位置，动态改变折叠角度
    const currentY: number = this.curlTouchY;
    const yDisp: number = (currentY - ay) * Math.min(progress * 2.5, 0.8);
    let py: number = ay + yDisp;

    // 弹性平滑：带阻尼弹簧的惯性跟随，产生Q弹拖拽手感
    if (this.smoothPeelX < 0) {
      this.smoothPeelX = px;
      this.smoothPeelY = py;
      this.springVelocityX = 0;
      this.springVelocityY = 0;
    } else {
      // 弹簧参数
      const stiffness: number = this.isReleaseAnimating ? 0.08 : 0.15;    // 释放动画期间软化，拖拽时紧跟
      const damping: number = 0.72;      // 阻尼 — 值越小振荡越多
      // 弹力 = 目标差值 * 刚度
      const forceX: number = (px - this.smoothPeelX) * stiffness;
      const forceY: number = (py - this.smoothPeelY) * stiffness;
      // 速度 = 旧速度 * 阻尼 + 弹力
      this.springVelocityX = this.springVelocityX * damping + forceX;
      this.springVelocityY = this.springVelocityY * damping + forceY;
      this.smoothPeelX += this.springVelocityX;
      this.smoothPeelY += this.springVelocityY;
    }
    px = this.smoothPeelX;
    py = this.smoothPeelY;

    // === 3. 折叠线 = A→P 的垂直平分线 ===
    const fmx: number = (ax + px) / 2;
    const fmy: number = (ay + py) / 2;
    const fdx: number = px - ax;
    const fdy: number = py - ay;
    const flen: number = Math.sqrt(fdx * fdx + fdy * fdy);
    if (flen < 1) return;
    // 法线方向（A→P）
    const nx: number = fdx / flen;
    const ny: number = fdy / flen;

    // === 4. 矩形角点分类 & 多边形分割 ===
    const rc: number[][] = [
      [ix, iy], [ix + iw, iy], [ix + iw, iy + ih], [ix, iy + ih]
    ];
    // 各角点到折叠线的有符号距离 (>0 = P侧/平面, <0 = A侧/翻起)
    const sd: number[] = rc.map(c => nx * (c[0] - fmx) + ny * (c[1] - fmy));

    // 构建两侧有序多边形
    const flatPoly: number[][] = [];
    const curlPoly: number[][] = [];
    for (let i = 0; i < 4; i++) {
      const j: number = (i + 1) % 4;
      if (sd[i] >= 0) flatPoly.push(rc[i]);
      if (sd[i] < 0) curlPoly.push(rc[i]);
      if (sd[i] * sd[j] < 0) {
        const t: number = sd[i] / (sd[i] - sd[j]);
        const ip: number[] = [
          rc[i][0] + t * (rc[j][0] - rc[i][0]),
          rc[i][1] + t * (rc[j][1] - rc[i][1])
        ];
        flatPoly.push(ip);
        curlPoly.push(ip);
      }
    }

    // === 5. 绘制下一页底层 ===
    this.drawNextPageBase(ctx, cw, ch);

    // === 6. 当前页（平面侧） ===
    if (flatPoly.length >= 3 && this.currentImageBitmap) {
      ctx.save();
      ctx.beginPath();
      ctx.moveTo(flatPoly[0][0], flatPoly[0][1]);
      for (let i = 1; i < flatPoly.length; i++) {
        ctx.lineTo(flatPoly[i][0], flatPoly[i][1]);
      }
      ctx.closePath();
      ctx.clip();
      ctx.globalAlpha = 1.0;
      try { ctx.drawImage(this.currentImageBitmap, ix, iy, iw, ih); } catch (e) {}
      ctx.restore();
    }

    // === 7. 翻起背面（反射到折叠线另一侧） ===
    // 将 curlPoly 各顶点沿折叠线镜像反射，得到翻起后的真实位置
    if (curlPoly.length >= 3 && this.currentImageBitmap) {
      const foldAngle: number = Math.atan2(nx, -ny);

      // 计算反射多边形：每个顶点沿折叠线镜像
      const reflCurl: number[][] = curlPoly.map(p => {
        const vx: number = p[0] - fmx;
        const vy: number = p[1] - fmy;
        const proj: number = vx * nx + vy * ny;
        return [p[0] - 2 * proj * nx, p[1] - 2 * proj * ny];
      });

      // 7a. 在反射位置绘制镜像图片（书页背面）
      ctx.save();
      ctx.beginPath();
      ctx.moveTo(reflCurl[0][0], reflCurl[0][1]);
      for (let i = 1; i < reflCurl.length; i++) {
        ctx.lineTo(reflCurl[i][0], reflCurl[i][1]);
      }
      ctx.closePath();
      ctx.clip();
      // 反射变换：平移到折叠中点 → 旋转对齐 → 翻转 → 旋转回 → 平移回
      ctx.translate(fmx, fmy);
      ctx.rotate(foldAngle);
      ctx.scale(1, -1);
      ctx.rotate(-foldAngle);
      ctx.translate(-fmx, -fmy);
      ctx.globalAlpha = this.curlBackOpacity / 100;
      try { ctx.drawImage(this.currentImageBitmap, ix, iy, iw, ih); } catch (e) {}
      ctx.restore();

      // 7b. 纸张背面覆盖色
      ctx.save();
      ctx.beginPath();
      ctx.moveTo(reflCurl[0][0], reflCurl[0][1]);
      for (let i = 1; i < reflCurl.length; i++) {
        ctx.lineTo(reflCurl[i][0], reflCurl[i][1]);
      }
      ctx.closePath();
      ctx.clip();
      ctx.globalAlpha = 0.08 * (this.curlBackOpacity / 100);
      ctx.fillStyle = '#f5f0e8';
      ctx.fill();
      ctx.restore();

      // 7c. 折叠处内侧阴影（模拟纸张弯曲，在反射区域内靠近折叠线处）
      if (this.config.enableShadow) {
        ctx.save();
        ctx.beginPath();
        ctx.moveTo(reflCurl[0][0], reflCurl[0][1]);
        for (let i = 1; i < reflCurl.length; i++) {
          ctx.lineTo(reflCurl[i][0], reflCurl[i][1]);
        }
        ctx.closePath();
        ctx.clip();
        const innerSw: number = Math.min(35, iw * 0.05) * Math.sqrt(progress);
        // 阴影从折叠线向P侧（反射区域内部）扩散
        const g2: CanvasGradient = ctx.createLinearGradient(
          fmx, fmy, fmx + nx * innerSw, fmy + ny * innerSw
        );
        g2.addColorStop(0, 'rgba(0,0,0,0.18)');
        g2.addColorStop(0.4, 'rgba(0,0,0,0.04)');
        g2.addColorStop(1, 'rgba(0,0,0,0)');
        ctx.fillStyle = g2;
        ctx.fillRect(ix - 50, iy - 50, iw + 100, ih + 100);
        ctx.restore();
      }

      // 7d. 翻起页外沿阴影（反射多边形远离折叠线的边缘薄阴影）
      if (this.config.enableShadow && progress > 0.08) {
        ctx.save();
        // 找到反射多边形中离折叠线最远的点，沿其外侧绘制细窄阴影
        let maxDist: number = 0;
        let farIdx: number = 0;
        for (let i = 0; i < reflCurl.length; i++) {
          const d: number = Math.abs(nx * (reflCurl[i][0] - fmx) + ny * (reflCurl[i][1] - fmy));
          if (d > maxDist) { maxDist = d; farIdx = i; }
        }
        if (maxDist > 5) {
          // 外沿阴影：沿反射多边形远端绘制一条渐变阴影
          const edgeSw: number = Math.min(12, 6 + progress * 8);
          const edgeAlpha: number = Math.min(0.12, 0.06 + progress * 0.06);
          const fp: number[] = reflCurl[farIdx];
          // 阴影方向：从反射区域向外扩散
          const outDirX: number = nx;  // 法线方向即为远离折叠线的方向
          const outDirY: number = ny;
          const gEdge: CanvasGradient = ctx.createLinearGradient(
            fp[0] - outDirX * 2, fp[1] - outDirY * 2,
            fp[0] + outDirX * edgeSw, fp[1] + outDirY * edgeSw
          );
          gEdge.addColorStop(0, `rgba(0,0,0,${edgeAlpha})`);
          gEdge.addColorStop(0.4, `rgba(0,0,0,${edgeAlpha * 0.4})`);
          gEdge.addColorStop(1, 'rgba(0,0,0,0)');
          ctx.fillStyle = gEdge;
          ctx.fillRect(ix - 50, iy - 50, iw + 100, ih + 100);
        }
        ctx.restore();
      }
    }

    // === 8. 折叠线阴影（仅投射到揭开区域，不影响平面侧） ===
    if (this.config.enableShadow && progress > 0.02 && curlPoly.length >= 3) {
      // 8a. 页面悬浮投影 — 更宽更柔的阴影层（底层），模拟翻起页在下方的整体投影
      if (progress > 0.06) {
        ctx.save();
        ctx.beginPath();
        ctx.moveTo(curlPoly[0][0], curlPoly[0][1]);
        for (let i = 1; i < curlPoly.length; i++) {
          ctx.lineTo(curlPoly[i][0], curlPoly[i][1]);
        }
        ctx.closePath();
        ctx.clip();
        const wideSw: number = Math.min(80, iw * 0.12) * progress;
        const wideAlpha: number = Math.min(0.15, 0.03 + progress * progress * 0.12);
        // 从折叠线向锚点侧扩散的宽幅柔和投影
        const gWide: CanvasGradient = ctx.createLinearGradient(
          fmx, fmy,
          fmx - nx * wideSw, fmy - ny * wideSw
        );
        gWide.addColorStop(0, `rgba(0,0,0,${wideAlpha})`);
        gWide.addColorStop(0.15, `rgba(0,0,0,${wideAlpha * 0.7})`);
        gWide.addColorStop(0.35, `rgba(0,0,0,${wideAlpha * 0.4})`);
        gWide.addColorStop(0.6, `rgba(0,0,0,${wideAlpha * 0.15})`);
        gWide.addColorStop(1, 'rgba(0,0,0,0)');
        ctx.fillStyle = gWide;
        ctx.fillRect(ix - 50, iy - 50, iw + 100, ih + 100);
        ctx.restore();
      }

      // 8b. 主折叠阴影 — 动态宽度，6-stop高斯式衰减（上层，覆盖在悬浮投影之上）
      const sw: number = Math.min(50, iw * (0.04 + 0.04 * progress)) * Math.sqrt(progress);
      const sa: number = Math.min(0.35, 0.24 * Math.sqrt(progress));
      ctx.save();
      ctx.beginPath();
      ctx.moveTo(curlPoly[0][0], curlPoly[0][1]);
      for (let i = 1; i < curlPoly.length; i++) {
        ctx.lineTo(curlPoly[i][0], curlPoly[i][1]);
      }
      ctx.closePath();
      ctx.clip();
      // 极窄接触面阴影带(3px)：模拟纸张贴合面
      const gContact: CanvasGradient = ctx.createLinearGradient(
        fmx + nx * 1, fmy + ny * 1,
        fmx - nx * 3, fmy - ny * 3
      );
      gContact.addColorStop(0, `rgba(0,0,0,${Math.min(0.4, sa * 1.3)})`);
      gContact.addColorStop(1, 'rgba(0,0,0,0)');
      ctx.fillStyle = gContact;
      ctx.fillRect(ix - 50, iy - 50, iw + 100, ih + 100);
      // 主阴影：6-stop平滑衰减
      const g1: CanvasGradient = ctx.createLinearGradient(
        fmx + nx * 2, fmy + ny * 2,
        fmx - nx * sw, fmy - ny * sw
      );
      g1.addColorStop(0, `rgba(0,0,0,${sa})`);
      g1.addColorStop(0.1, `rgba(0,0,0,${sa * 0.6})`);
      g1.addColorStop(0.25, `rgba(0,0,0,${sa * 0.3})`);
      g1.addColorStop(0.45, `rgba(0,0,0,${sa * 0.12})`);
      g1.addColorStop(0.7, `rgba(0,0,0,${sa * 0.03})`);
      g1.addColorStop(1, 'rgba(0,0,0,0)');
      ctx.fillStyle = g1;
      ctx.fillRect(ix - 50, iy - 50, iw + 100, ih + 100);
      ctx.restore();
    }

    // === 9. 折叠边缘线 ===
    const edgePts: number[][] = [];
    for (let i = 0; i < 4; i++) {
      const j: number = (i + 1) % 4;
      if (sd[i] * sd[j] < 0) {
        const t: number = sd[i] / (sd[i] - sd[j]);
        edgePts.push([
          rc[i][0] + t * (rc[j][0] - rc[i][0]),
          rc[i][1] + t * (rc[j][1] - rc[i][1])
        ]);
      }
    }
    if (edgePts.length === 2 && progress > 0.015) {
      ctx.save();
      ctx.globalAlpha = 0.12 + 0.1 * progress;
      ctx.strokeStyle = '#999999';
      ctx.lineWidth = 0.8;
      ctx.beginPath();
      ctx.moveTo(edgePts[0][0], edgePts[0][1]);
      ctx.lineTo(edgePts[1][0], edgePts[1][1]);
      ctx.stroke();
      ctx.restore();

      // 折叠线高光（纸张边缘反光）
      if (this.config.enableHighlight) {
        ctx.save();
        ctx.globalAlpha = 0.2 + 0.15 * progress;
        ctx.strokeStyle = 'rgba(255,255,255,0.5)';
        ctx.lineWidth = 1.2;
        ctx.beginPath();
        ctx.moveTo(edgePts[0][0] - nx * 1, edgePts[0][1] - ny * 1);
        ctx.lineTo(edgePts[1][0] - nx * 1, edgePts[1][1] - ny * 1);
        ctx.stroke();
        ctx.restore();
      }
    }
    ctx.globalAlpha = 1.0;
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
   * 重力落下缓动：模拟页面在重力下落回 + 微弹跳
   * 前60%: 加速相 easeInQuad（模拟重力加速）
   * 60%-90%: 减速相，略微过冲(~3%)（模拟落地微弹）
   * 90%-100%: 平滑回归安定
   */
  private easeGravityDrop(t: number): number {
    if (t < 0.6) {
      // 加速相：easeInQuad
      const nt: number = t / 0.6;
      return 0.6 * nt * nt;
    } else if (t < 0.9) {
      // 减速 + 过冲：从 0.6 到 1.03
      const nt: number = (t - 0.6) / 0.3;
      const ease: number = nt * (2 - nt);  // easeOutQuad on this segment
      return 0.6 + 0.43 * ease;
    } else {
      // 回归安定：从 1.03 到 1.0
      const nt: number = (t - 0.9) / 0.1;
      return 1.03 - 0.03 * nt * nt;
    }
  }
  
  /**
   * easeOutCubic + 末尾微过冲：速度延续翻页用
   * t > 0.95 时混入 ~1.5% overshoot，模拟惯性超调
   */
  private easeOutCubicWithOvershoot(t: number): number {
    const base: number = 1 - Math.pow(1 - t, 3);
    if (t > 0.95) {
      const ot: number = (t - 0.95) / 0.05;
      const overshoot: number = Math.sin(ot * Math.PI) * 0.015;
      return base + overshoot;
    }
    return base;
  }
  
  /**
   * easeInOutCubic：先加速再减速，模拟重力辅助翻页
   */
  private easeInOutCubic(t: number): number {
    return t < 0.5
      ? 4 * t * t * t
      : 1 - Math.pow(-2 * t + 2, 3) / 2;
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
          if (this.pendingAnimateAfterReady || this.animateToTarget >= 0) {
            this.onAnimateToTargetChange();
          }
        })
    }
    .width(this.componentWidth)
    .height(this.componentHeight)
    // 注意：触摸事件由外部MangaViewer处理
    // 本组件只负责渲染，进度由externalProgress控制
  }
}
