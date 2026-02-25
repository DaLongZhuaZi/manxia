/**
 * 双页模式专用卷页动画组件
 *
 * 核心特性：
 * 1. 横跨整个双页宽度的翻页动画——翻起的页面真正"盖"到另一页上
 * 2. 向前翻页：右页从右边缘掀起，越过中缝覆盖左页，露出下方新的一对页面
 * 3. 向后翻页：左页从左边缘掀起，越过中缝覆盖右页
 * 4. 支持拖拽交互 (externalProgress) 和自动动画 (animateToTarget) 两种模式
 * 5. 使用 4 张 PixelMap：当前左/右 + 底层左/右
 */

import { logger } from '../Utils/Logger';
import { image } from '@kit.ImageKit';
import { PageCurlConfigV2, CurlStartPosition } from './PageCurlEffectV2';

/** 图片绘制边界 */
interface ImageRect {
  x: number;
  y: number;
  w: number;
  h: number;
}

const TAG = 'DualPageCurlEffect';

const DUAL_DEFAULT_CONFIG: PageCurlConfigV2 = {
  stripCount: 24,
  maxCurlHeight: 120,
  shadowIntensity: 0.5,
  animationDuration: 380,
  enableShadow: true,
  enableHighlight: true,
  flipThreshold: 0.28
};

@Component
export struct DualPageCurlEffect {
  // ========== 页面 PixelMap（不可使用 @Prop，避免深拷贝导致 Native 数据丢失） ==========
  /** 当前左页 */
  currentLeftPixelMap: image.PixelMap | null = null;
  /** 当前右页（向前翻时被掀起） */
  currentRightPixelMap: image.PixelMap | null = null;
  /** 底层左页（翻页后露出的新左页） */
  nextLeftPixelMap: image.PixelMap | null = null;
  /** 底层右页（翻页后露出的新右页） */
  nextRightPixelMap: image.PixelMap | null = null;

  // ========== 尺寸 ==========
  @Prop componentWidth: number = 720;
  @Prop componentHeight: number = 640;

  // ========== 配置 ==========
  @Prop config: PageCurlConfigV2 = DUAL_DEFAULT_CONFIG;
  /** true = 向前翻（右页掀起） false = 向后翻（左页掀起） */
  @Prop isForward: boolean = true;
  @Prop curlTouchY: number = 0;
  @Prop curlBackOpacity: number = 100;

  // ========== 外部驱动进度 ==========
  @Prop @Watch('onExternalProgressChange') externalProgress: number = -1;

  // ========== 内部动画控制 ==========
  @Prop @Watch('onAnimateToTargetChange') animateToTarget: number = -1;
  @Prop animateFromProgress: number = 0;
  @Prop animateVelocity: number = 0;      // 脱手速度（progress/ms），用于速度延续动画；0 = 使用默认时长

  // ========== 回调 ==========
  onAnimationComplete: () => void = () => {};

  // ========== 内部状态 ==========
  @State private isReady: boolean = false;
  @State private curlProgress: number = 0;
  /** Bitmap 锁定标志：动画开始后锁定，防止外部 PixelMap 变化导致底层内容闪烁 */
  private bitmapsLocked: boolean = false;
  /** 初始 bitmap 是否已构建（确保至少构建一次） */
  private initialBitmapsBuilt: boolean = false;

  // ImageBitmap 缓存
  private curLeftBitmap: ImageBitmap | null = null;
  private curRightBitmap: ImageBitmap | null = null;
  private nxtLeftBitmap: ImageBitmap | null = null;
  private nxtRightBitmap: ImageBitmap | null = null;

  // 上次 PixelMap 引用（用于变化检测）
  private lastCurLeftPM: image.PixelMap | null = null;
  private lastCurRightPM: image.PixelMap | null = null;
  private lastNxtLeftPM: image.PixelMap | null = null;
  private lastNxtRightPM: image.PixelMap | null = null;

  // 弹簧平滑
  private smoothPeelX: number = -1;
  private smoothPeelY: number = -1;
  private springVelocityX: number = 0;
  private springVelocityY: number = 0;
  private anchorAY: number = -1;

  private animationTimer: number = -1;
  // 动画期间弹簧软化标记
  private isReleaseAnimating: boolean = false;

  private canvasSettings: RenderingContextSettings = new RenderingContextSettings(true);
  private canvasContext: CanvasRenderingContext2D = new CanvasRenderingContext2D(this.canvasSettings);

  // halfWidth getter 已移除 —— ArkTS getter 在某些场景下返回 NaN
  // 改为在 renderCurlEffect 中直接计算

  // ========== 生命周期 ==========
  aboutToAppear(): void {
    logger.info(TAG, `初始化: ${this.componentWidth}x${this.componentHeight}, ` +
      `curLPM=${this.currentLeftPixelMap !== null}, curRPM=${this.currentRightPixelMap !== null}, ` +
      `nxtLPM=${this.nextLeftPixelMap !== null}, nxtRPM=${this.nextRightPixelMap !== null}, ` +
      `extProgress=${this.externalProgress}, animTarget=${this.animateToTarget}`);
  }

  aboutToDisappear(): void {
    this.stopAnimation();
    this.releaseAllBitmaps();
    // 重置锁定状态
    this.bitmapsLocked = false;
    this.initialBitmapsBuilt = false;
  }

  // ========== PixelMap → ImageBitmap 管理 ==========

  private checkAndUpdateBitmaps(): void {
    // 动画开始后锁定 Bitmap，不再响应外部 PixelMap 变化
    // 这样确保底层、中层、上层内容在整个动画过程中保持稳定
    if (this.bitmapsLocked && this.initialBitmapsBuilt) {
      logger.debug(TAG, `checkAndUpdateBitmaps: Bitmaps 已锁定，跳过更新`);
      return;
    }
    
    const c1 = this.currentLeftPixelMap !== this.lastCurLeftPM;
    const c2 = this.currentRightPixelMap !== this.lastCurRightPM;
    const c3 = this.nextLeftPixelMap !== this.lastNxtLeftPM;
    const c4 = this.nextRightPixelMap !== this.lastNxtRightPM;

    if (c1 || c2 || c3 || c4) {
      this.lastCurLeftPM = this.currentLeftPixelMap;
      this.lastCurRightPM = this.currentRightPixelMap;
      this.lastNxtLeftPM = this.nextLeftPixelMap;
      this.lastNxtRightPM = this.nextRightPixelMap;
      this.rebuildBitmaps();
      this.initialBitmapsBuilt = true;
    }
  }

  private rebuildBitmaps(): void {
    this.releaseBitmap(this.curLeftBitmap);
    this.releaseBitmap(this.curRightBitmap);
    this.releaseBitmap(this.nxtLeftBitmap);
    this.releaseBitmap(this.nxtRightBitmap);

    this.curLeftBitmap = this.createBitmapSafe(this.currentLeftPixelMap, 'curLeft');
    this.curRightBitmap = this.createBitmapSafe(this.currentRightPixelMap, 'curRight');
    this.nxtLeftBitmap = this.createBitmapSafe(this.nextLeftPixelMap, 'nxtLeft');
    this.nxtRightBitmap = this.createBitmapSafe(this.nextRightPixelMap, 'nxtRight');
  }

  private createBitmapSafe(pm: image.PixelMap | null, label: string): ImageBitmap | null {
    if (!pm) return null;
    try {
      const info = pm.getImageInfoSync();
      if (!info || !info.size || info.size.width <= 0) {
        logger.warn(TAG, `${label} PixelMap 已失效`);
        return null;
      }
      logger.info(TAG, `${label} PixelMap: ${info.size.width}x${info.size.height}, format=${info.pixelFormat}`);
      const bm = new ImageBitmap(pm);
      logger.info(TAG, `${label} ImageBitmap: w=${bm.width}, h=${bm.height}`);
      if (bm.width <= 0 || bm.height <= 0) {
        logger.error(TAG, `${label} ImageBitmap 维度无效! 将使用 PixelMap 直接绘制`);
        try { bm.close(); } catch (_) {}
        return null;
      }
      return bm;
    } catch (e) {
      logger.error(TAG, `${label} ImageBitmap 创建失败: ${e}`);
      return null;
    }
  }

  /**
   * 安全绘制图像到 Canvas（等比缩放，不拉伸）
   *
   * 与 PageCurlEffectV2 完全一致：仅使用 ImageBitmap + 5参数 drawImage。
   * 图片将按比例缩放以适应目标区域，居中显示，不拉伸。
   * 
   * @param alignment 对齐方式：'center'居中, 'left'靠左, 'right'靠右
   */
  private drawImageSafe(ctx: CanvasRenderingContext2D,
    _pm: image.PixelMap | null, bm: ImageBitmap | null,
    dx: number, dy: number, dw: number, dh: number,
    alignment: string = 'center'): boolean {
    if (bm && bm.width > 0 && bm.height > 0) {
      try {
        // 计算等比缩放后的尺寸和位置
        const imgAspect: number = bm.width / bm.height;
        const areaAspect: number = dw / dh;
        let drawW: number, drawH: number, drawX: number, drawY: number;
        if (imgAspect > areaAspect) {
          // 图片更宽，以宽度为基准
          drawW = dw;
          drawH = dw / imgAspect;
          drawX = dx;
          drawY = dy + (dh - drawH) / 2;
        } else {
          // 图片更高，以高度为基准
          drawH = dh;
          drawW = dh * imgAspect;
          // 根据对齐方式计算X位置
          if (alignment === 'right') {
            // 靠右对齐（左页靠书脊）
            drawX = dx + dw - drawW;
          } else if (alignment === 'left') {
            // 靠左对齐（右页靠书脊）
            drawX = dx;
          } else {
            // 居中
            drawX = dx + (dw - drawW) / 2;
          }
          drawY = dy;
        }
        ctx.drawImage(bm, drawX, drawY, drawW, drawH);
        return true;
      } catch (e) {
        logger.warn(TAG, `drawImageSafe ImageBitmap 失败: ${e}`);
      }
    }
    return false;
  }

  /**
   * 计算图片等比缩放后的实际绘制边界
   * 返回 ImageRect 表示图片在 dx,dy,dw,dh 区域内的实际绘制位置和尺寸
   */
  private calcImageDrawRect(bm: ImageBitmap | null, dx: number, dy: number, dw: number, dh: number, alignment: string): ImageRect {
    // 默认返回整个区域（无图片时）
    if (!bm || bm.width <= 0 || bm.height <= 0) {
      const rect: ImageRect = { x: dx, y: dy, w: dw, h: dh };
      return rect;
    }
    const imgAspect: number = bm.width / bm.height;
    const areaAspect: number = dw / dh;
    let drawW: number, drawH: number, drawX: number, drawY: number;
    if (imgAspect > areaAspect) {
      // 图片更宽，以宽度为基准
      drawW = dw;
      drawH = dw / imgAspect;
      drawX = dx;
      drawY = dy + (dh - drawH) / 2;
    } else {
      // 图片更高，以高度为基准
      drawH = dh;
      drawW = dh * imgAspect;
      if (alignment === 'right') {
        drawX = dx + dw - drawW;
      } else if (alignment === 'left') {
        drawX = dx;
      } else {
        drawX = dx + (dw - drawW) / 2;
      }
      drawY = dy;
    }
    const rect: ImageRect = { x: drawX, y: drawY, w: drawW, h: drawH };
    return rect;
  }

  private releaseBitmap(bm: ImageBitmap | null): void {
    if (bm) {
      try { bm.close(); } catch (_) {}
    }
  }

  private releaseAllBitmaps(): void {
    this.releaseBitmap(this.curLeftBitmap);
    this.releaseBitmap(this.curRightBitmap);
    this.releaseBitmap(this.nxtLeftBitmap);
    this.releaseBitmap(this.nxtRightBitmap);
    this.curLeftBitmap = null;
    this.curRightBitmap = null;
    this.nxtLeftBitmap = null;
    this.nxtRightBitmap = null;
  }

  // ========== 进度驱动 ==========

  onExternalProgressChange(): void {
    if (this.externalProgress >= 0 && this.isReady) {
      this.checkAndUpdateBitmaps();
      this.curlProgress = this.externalProgress;
      this.renderCurlEffect();
    } else if (this.externalProgress >= 0 && !this.isReady) {
      // Canvas 未就绪时记录，帮助诊断 onReady 延迟问题
      logger.debug(TAG, `onExternalProgressChange 跳过: progress=${this.externalProgress.toFixed(3)}, isReady=${this.isReady}`);
    }
  }

  /**
   * 内部动画控制：当 animateToTarget 变化时触发
   *
   * 动画时长由脱手速度（animateVelocity）决定，使动画无缝延续用户的翻页力度：
   *  - 有速度时：duration = 3 * Δ / v（easeOutCubic 初始斜率=3 → 动画开始速度 ≈ 用户脱手速度）
   *  - 无速度时：使用基于进度的默认时长
   */
  onAnimateToTargetChange(): void {
    if (this.animateToTarget < 0 || !this.isReady) return;

    this.stopAnimation();
    this.checkAndUpdateBitmaps();

    const startProgress: number = this.curlProgress;
    const targetProgress: number = this.animateToTarget;
    const progressDelta: number = Math.abs(targetProgress - startProgress);

    if (progressDelta < 0.01) {
      this.curlProgress = targetProgress;
      this.renderCurlEffect();
      this.onAnimationComplete();
      return;
    }

    const isComplete: boolean = targetProgress > startProgress;
    const velocity: number = this.animateVelocity;  // progress/ms

    let duration: number;
    // 缓动类型: 0=重力落下(取消回弹), 1=速度延续+微过冲(完成有速度), 2=重力辅助(完成无速度)
    let easingType: number;

    if (!isComplete) {
      // ① 取消回弹 — 重力加速 + 微弹跳
      duration = Math.max(280, this.config.animationDuration * progressDelta * 1.8 * 1.2);
      easingType = 0;
    } else if (velocity > 0.0003) {
      // ② 完成翻页（有速度）— 速度延续 + 末尾微过冲
      const physDuration: number = 3.0 * progressDelta / velocity;
      duration = Math.min(500, Math.max(120, physDuration));
      easingType = 1;
    } else {
      // ③ 完成翻页（无速度）— 重力辅助 easeInOutCubic
      duration = Math.max(200, this.config.animationDuration * progressDelta * 1.5);
      easingType = 2;
    }

    // 释放后弹簧参数软化
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

    // 立即执行第一帧，避免 setTimeout 引入额外延迟
    animate();
  }

  private stopAnimation(): void {
    if (this.animationTimer !== -1) {
      clearTimeout(this.animationTimer);
      this.animationTimer = -1;
    }
  }

  // ========== 弹簧状态重置 ==========

  private resetSpringState(): void {
    this.smoothPeelX = -1;
    this.smoothPeelY = -1;
    this.springVelocityX = 0;
    this.springVelocityY = 0;
    this.anchorAY = -1;
  }

  // ========== 核心渲染 ==========

  /**
   * 核心渲染逻辑 - 基于 V2 垂直平分线折叠模型
   *
   * 将双页拆分为两组独立的“动画组件”：
   * - 未跨书脊：被翻页 + 其下方底层 → 在该侧做 V2 式卷曲
   * - 跨过书脊：背面 + 不动页 → 在另一侧做反向 V2 式卷曲
   */
  private renderCurlEffect(): void {
    const ctx = this.canvasContext;
    if (!ctx) return;

    const cw: number = this.componentWidth;
    const ch: number = this.componentHeight;
    const hw: number = Math.floor(cw / 2);
    const progress: number = this.curlProgress;

    ctx.globalAlpha = 1.0;
    ctx.clearRect(0, 0, cw, ch);

    if (progress < 0.01) {
      this.resetSpringState();
      this.drawSpreadSafe(ctx, this.currentLeftPixelMap, this.curLeftBitmap,
        this.currentRightPixelMap, this.curRightBitmap, hw, ch);
      return;
    }

    // 动画完成时（progress >= 0.99），绘制纯静态的新页面
    // 这样 Canvas 层的内容与底层 Image 完全一致，隐藏时不会闪烁
    if (progress >= 0.99) {
      this.resetSpringState();
      // 绘制新页面（next 页面）
      this.drawSpreadSafe(ctx, this.nextLeftPixelMap, this.nxtLeftBitmap,
        this.nextRightPixelMap, this.nxtRightBitmap, hw, ch);
      return;
    }

    const isLeftTurn: boolean = !this.isForward;
    
    // 折叠线 X 位置
    const foldX: number = isLeftTurn ? progress * cw : cw * (1 - progress);
    const crossedSpine: boolean = isLeftTurn ? (foldX > hw) : (foldX < hw);
    
    // 映射进度到单侧进度 (0~1 在被翻页侧内)
    let localProgress: number;
    if (isLeftTurn) {
      localProgress = Math.min(foldX / hw, 1);
    } else {
      localProgress = Math.min((cw - foldX) / hw, 1);
    }

    // === 1. 绘制底层 ===
    // 被翻页下方的底层页
    ctx.save();
    ctx.globalAlpha = 1.0;
    if (isLeftTurn) {
      // 左翻右：底层左页靠右对齐（紧贴书脊）
      if (!this.drawImageSafe(ctx, this.nextLeftPixelMap, this.nxtLeftBitmap, 0, 0, hw, ch, 'right')) {
        ctx.fillStyle = '#F5F0E1';
        ctx.fillRect(0, 0, hw, ch);
      }
    } else {
      // 右翻左：底层右页靠左对齐（紧贴书脊）
      if (!this.drawImageSafe(ctx, this.nextRightPixelMap, this.nxtRightBitmap, hw, 0, hw, ch, 'left')) {
        ctx.fillStyle = '#F5F0E1';
        ctx.fillRect(hw, 0, hw, ch);
      }
    }
    ctx.restore();

    // === 2. 不动页 ===
    const stayingBitmap: ImageBitmap | null = isLeftTurn ? this.curRightBitmap : this.curLeftBitmap;
    const stayingPM: image.PixelMap | null = isLeftTurn ? this.currentRightPixelMap : this.currentLeftPixelMap;
    const stayX: number = isLeftTurn ? hw : 0;
    // 不动页的对齐：左翻右时右页靠左，右翻左时左页靠右
    const stayAlign: string = isLeftTurn ? 'left' : 'right';
    ctx.save();
    ctx.globalAlpha = 1.0;
    if (!this.drawImageSafe(ctx, stayingPM, stayingBitmap, stayX, 0, hw, ch, stayAlign)) {
      ctx.fillStyle = '#F5F0E1';
      ctx.fillRect(stayX, 0, hw, ch);
    }
    ctx.restore();

    // === 3. 书脊阴影（绘制在底层页和不动页上方，卷曲动画下方） ===
    if (this.config.enableShadow) {
      ctx.save();
      const sg: CanvasGradient = ctx.createLinearGradient(hw - 8, 0, hw + 8, 0);
      sg.addColorStop(0, 'rgba(0,0,0,0)');
      sg.addColorStop(0.5, 'rgba(0,0,0,0.15)');
      sg.addColorStop(1, 'rgba(0,0,0,0)');
      ctx.fillStyle = sg;
      ctx.fillRect(hw - 8, 0, 16, ch);
      ctx.restore();
    }

    // === 4. V2式卷曲动画 / 着陆动画 ===
    if (!crossedSpine) {
      const turningBitmap: ImageBitmap | null = isLeftTurn ? this.curLeftBitmap : this.curRightBitmap;
      const turningPM: image.PixelMap | null = isLeftTurn ? this.currentLeftPixelMap : this.currentRightPixelMap;
      // 背面内容：正向翻页显示下一组左页，反向翻页显示下一组右页
      const backBitmap: ImageBitmap | null = isLeftTurn ? this.nxtRightBitmap : this.nxtLeftBitmap;
      const backPM: image.PixelMap | null = isLeftTurn ? this.nextRightPixelMap : this.nextLeftPixelMap;
      if (turningBitmap || turningPM) {
        const areaX: number = isLeftTurn ? 0 : hw;
        this.renderV2CurlInArea(ctx, turningBitmap, turningPM, backBitmap, backPM,
          areaX, 0, hw, ch, localProgress, isLeftTurn);
      }
    } else {
      // === 跨书脊后：页面从书脊“落下”到另一侧 ===
      // crossProgress: 0(刚跨过书脊) → 1(完全落下)
      const crossProgress: number = Math.min((progress - 0.5) / 0.5, 1.0);
      
      // 着陆页内容
      const landingBitmap: ImageBitmap | null = isLeftTurn ? this.nxtRightBitmap : this.nxtLeftBitmap;
      const landingPM: image.PixelMap | null = isLeftTurn ? this.nextRightPixelMap : this.nextLeftPixelMap;
      const landingX: number = isLeftTurn ? hw : 0;
      
      // 绘制着陆页（底层，始终完整显示）
      // 着陆页对齐：左翻右时右页靠左，右翻左时左页靠右
      const landingAlign: string = isLeftTurn ? 'left' : 'right';
      ctx.save();
      ctx.globalAlpha = 1.0;
      if (!this.drawImageSafe(ctx, landingPM, landingBitmap, landingX, 0, hw, ch, landingAlign)) {
        ctx.fillStyle = '#F5F0E1';
        ctx.fillRect(landingX, 0, hw, ch);
      }
      ctx.restore();
      
      // 绘制落下阴影：从书脊侧向外渐淡，模拟页面刚刚落下的效果
      if (this.config.enableShadow && crossProgress < 0.95) {
        // 阴影强度随进度减弱
        const shadowIntensity: number = 0.35 * Math.pow(1 - crossProgress, 1.2);
        // 阴影宽度随进度收窄
        const shadowWidth: number = Math.max(4, hw * 0.15 * (1 - crossProgress));
        
        ctx.save();
        ctx.beginPath();
        ctx.rect(landingX, 0, hw, ch);
        ctx.clip();
        
        if (isLeftTurn) {
          // 左翻右：阴影在右页左侧（书脊侧）
          const g: CanvasGradient = ctx.createLinearGradient(hw, 0, hw + shadowWidth, 0);
          g.addColorStop(0, `rgba(0,0,0,${shadowIntensity})`);
          g.addColorStop(0.4, `rgba(0,0,0,${shadowIntensity * 0.3})`);
          g.addColorStop(1, 'rgba(0,0,0,0)');
          ctx.fillStyle = g;
          ctx.fillRect(hw, 0, shadowWidth, ch);
        } else {
          // 右翻左：阴影在左页右侧（书脊侧）
          const g: CanvasGradient = ctx.createLinearGradient(hw, 0, hw - shadowWidth, 0);
          g.addColorStop(0, `rgba(0,0,0,${shadowIntensity})`);
          g.addColorStop(0.4, `rgba(0,0,0,${shadowIntensity * 0.3})`);
          g.addColorStop(1, 'rgba(0,0,0,0)');
          ctx.fillStyle = g;
          ctx.fillRect(hw - shadowWidth, 0, shadowWidth, ch);
        }
        ctx.restore();
      }
    }

    ctx.globalAlpha = 1.0;
  }
  
  /**
   * 在指定区域内执行 V2 式垂直平分线折叠卷曲
   * 
   * 核心算法（复用 V2 的模型）：
   * 1. 锚点 A = 页面边缘角落
   * 2. 拖拽点 P = 根据 localProgress 计算
   * 3. 折叠线 = A→P 的垂直平分线
   * 4. 多边形分割：平面侧显示当前页，翻起侧正向显示背面内容
   *
   * @param backBitmap 背面页 ImageBitmap（下一组页面）
   * @param backPM 背面页 PixelMap
   * @param isLeftSide 翻页方向 true=从左向右翻
   */
  private renderV2CurlInArea(
    ctx: CanvasRenderingContext2D,
    bitmap: ImageBitmap | null, pm: image.PixelMap | null,
    backBitmap: ImageBitmap | null, backPM: image.PixelMap | null,
    areaX: number, areaY: number, areaW: number, areaH: number,
    localProgress: number,
    isLeftSide: boolean
  ): void {
    // 确定当前区域的对齐方式：左侧区域靠右，右侧区域靠左
    const areaAlign: string = isLeftSide ? 'right' : 'left';
    
    // 计算图片实际绘制边界，用于限制折叠区域（避免空白区域被折叠）
    const imgRect: ImageRect = this.calcImageDrawRect(bitmap, areaX, areaY, areaW, areaH, areaAlign);
    
    if (localProgress < 0.005) {
      // 进度接近 0，原样显示
      ctx.save();
      ctx.beginPath();
      ctx.rect(areaX, areaY, areaW, areaH);
      ctx.clip();
      ctx.globalAlpha = 1.0;
      this.drawImageSafe(ctx, pm, bitmap, areaX, areaY, areaW, areaH, areaAlign);
      ctx.restore();
      return;
    }

    // === 1. 锚点角落 A （基于图片实际边界） ===
    const ax: number = isLeftSide ? imgRect.x : imgRect.x + imgRect.w;
    const touchRelY: number = Math.max(0, Math.min(1, (this.curlTouchY - imgRect.y) / imgRect.h));
    if (this.anchorAY < 0) {
      this.anchorAY = touchRelY >= 0.5 ? imgRect.y + imgRect.h : imgRect.y;
    }
    const ay: number = this.anchorAY;

    // === 2. 拖拽点 P （基于图片实际宽度） ===
    const dir: number = isLeftSide ? 1 : -1;
    let px: number = ax + dir * 2 * localProgress * imgRect.w;
    const yDisp: number = (this.curlTouchY - ay) * Math.min(localProgress * 2.5, 0.8);
    let py: number = ay + yDisp;

    // 弹性平滑
    if (this.smoothPeelX < 0) {
      this.smoothPeelX = px;
      this.smoothPeelY = py;
      this.springVelocityX = 0;
      this.springVelocityY = 0;
    } else {
      const stiffness: number = this.isReleaseAnimating ? 0.08 : 0.15;    // 释放动画期间软化
      const damping: number = 0.72;
      this.springVelocityX = this.springVelocityX * damping + (px - this.smoothPeelX) * stiffness;
      this.springVelocityY = this.springVelocityY * damping + (py - this.smoothPeelY) * stiffness;
      this.smoothPeelX += this.springVelocityX;
      this.smoothPeelY += this.springVelocityY;
    }
    px = this.smoothPeelX;
    py = this.smoothPeelY;

    // === 3. 折叠线 = A→P 垂直平分线 ===
    const fmx: number = (ax + px) / 2;
    const fmy: number = (ay + py) / 2;
    const fdx: number = px - ax;
    const fdy: number = py - ay;
    const flen: number = Math.sqrt(fdx * fdx + fdy * fdy);
    if (flen < 1) return;
    const nx: number = fdx / flen;
    const ny: number = fdy / flen;

    // === 4. 多边形分割（基于图片实际边界，避免空白区域被折叠） ===
    const rc: number[][] = [
      [imgRect.x, imgRect.y],
      [imgRect.x + imgRect.w, imgRect.y],
      [imgRect.x + imgRect.w, imgRect.y + imgRect.h],
      [imgRect.x, imgRect.y + imgRect.h]
    ];
    const sd: number[] = rc.map(c => nx * (c[0] - fmx) + ny * (c[1] - fmy));

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

    // === 5. 平面侧：显示当前页（完全不透明） ===
    if (flatPoly.length >= 3 && (bitmap || pm)) {
      ctx.save();
      ctx.beginPath();
      ctx.moveTo(flatPoly[0][0], flatPoly[0][1]);
      for (let k = 1; k < flatPoly.length; k++) {
        ctx.lineTo(flatPoly[k][0], flatPoly[k][1]);
      }
      ctx.closePath();
      ctx.clip();
      ctx.globalAlpha = 1.0;
      this.drawImageSafe(ctx, pm, bitmap, areaX, areaY, areaW, areaH, areaAlign);
      ctx.restore();
    }

    // === 6. 翻起侧：正向显示背面内容 ===
    // 背面对齐方式与当前区域相反（左翻右时背面是右页靠左，右翻左时背面是左页靠右）
    const backAlign: string = isLeftSide ? 'left' : 'right';
    if (curlPoly.length >= 3) {
      // 计算反射多边形（翻起部分在视觉上的位置）
      const reflCurl: number[][] = curlPoly.map(p => {
        const vx: number = p[0] - fmx;
        const vy: number = p[1] - fmy;
        const proj: number = vx * nx + vy * ny;
        return [p[0] - 2 * proj * nx, p[1] - 2 * proj * ny];
      });

      // 6a. 绘制背面页内容（正向显示）
      // HarmonyOS Canvas 的 drawImage 在多边形 clip 中无法直接渲染像素，
      // 必须先应用折叠镜像变换，再追加水平翻转抵消镜像效果。
      ctx.save();
      ctx.beginPath();
      ctx.moveTo(reflCurl[0][0], reflCurl[0][1]);
      for (let k = 1; k < reflCurl.length; k++) {
        ctx.lineTo(reflCurl[k][0], reflCurl[k][1]);
      }
      ctx.closePath();
      ctx.clip();
      // 填充纸张底色兆底（使用图片边界）
      ctx.globalAlpha = 1.0;
      ctx.fillStyle = '#F5F0E1';
      ctx.fillRect(imgRect.x - 50, imgRect.y - 50, imgRect.w + 100, imgRect.h + 100);
      // 使用折叠镜像 + 水平翻转的组合变换实现正向显示
      if (backBitmap || backPM) {
        const foldAngle: number = Math.atan2(nx, -ny);
        // 折叠镜像变换（让 drawImage 在 polygon clip 中正确渲染）
        ctx.translate(fmx, fmy);
        ctx.rotate(foldAngle);
        ctx.scale(1, -1);
        ctx.rotate(-foldAngle);
        ctx.translate(-fmx, -fmy);
        // 水平翻转抵消镜像，使背面内容正向显示（使用图片边界作为中心）
        ctx.translate(imgRect.x + imgRect.w / 2, imgRect.y + imgRect.h / 2);
        ctx.scale(-1, 1);
        ctx.translate(-(imgRect.x + imgRect.w / 2), -(imgRect.y + imgRect.h / 2));
        // 背面页使用与当前页相同的图片边界进行绘制，确保尺寸匹配
        this.drawImageSafe(ctx, backPM, backBitmap, imgRect.x, imgRect.y, imgRect.w, imgRect.h, backAlign);
      }
      ctx.restore();

      // 6b. 纸张背面覆盖色（轻微区分正反面）
      ctx.save();
      ctx.beginPath();
      ctx.moveTo(reflCurl[0][0], reflCurl[0][1]);
      for (let k = 1; k < reflCurl.length; k++) {
        ctx.lineTo(reflCurl[k][0], reflCurl[k][1]);
      }
      ctx.closePath();
      ctx.clip();
      ctx.globalAlpha = 0.06;
      ctx.fillStyle = '#f5f0e8';
      ctx.fill();
      ctx.restore();

      // 6c. 折叠处内侧阴影
      if (this.config.enableShadow) {
        ctx.save();
        ctx.beginPath();
        ctx.moveTo(reflCurl[0][0], reflCurl[0][1]);
        for (let k = 1; k < reflCurl.length; k++) {
          ctx.lineTo(reflCurl[k][0], reflCurl[k][1]);
        }
        ctx.closePath();
        ctx.clip();
        const innerSw: number = Math.min(35, imgRect.w * 0.05) * Math.sqrt(localProgress);
        const g2: CanvasGradient = ctx.createLinearGradient(
          fmx, fmy, fmx + nx * innerSw, fmy + ny * innerSw
        );
        g2.addColorStop(0, 'rgba(0,0,0,0.18)');
        g2.addColorStop(0.4, 'rgba(0,0,0,0.04)');
        g2.addColorStop(1, 'rgba(0,0,0,0)');
        ctx.fillStyle = g2;
        ctx.fillRect(imgRect.x - 50, imgRect.y - 50, imgRect.w + 100, imgRect.h + 100);
        ctx.restore();
      }

      // 6d. 翻起页外沿阴影（反射多边形远离折叠线的边缘薄阴影）
      if (this.config.enableShadow && localProgress > 0.08) {
        ctx.save();
        let maxDist: number = 0;
        let farIdx: number = 0;
        for (let i = 0; i < reflCurl.length; i++) {
          const d: number = Math.abs(nx * (reflCurl[i][0] - fmx) + ny * (reflCurl[i][1] - fmy));
          if (d > maxDist) { maxDist = d; farIdx = i; }
        }
        if (maxDist > 5) {
          const edgeSw: number = Math.min(12, 6 + localProgress * 8);
          const edgeAlpha: number = Math.min(0.12, 0.06 + localProgress * 0.06);
          const fp: number[] = reflCurl[farIdx];
          const outDirX: number = nx;
          const outDirY: number = ny;
          const gEdge: CanvasGradient = ctx.createLinearGradient(
            fp[0] - outDirX * 2, fp[1] - outDirY * 2,
            fp[0] + outDirX * edgeSw, fp[1] + outDirY * edgeSw
          );
          gEdge.addColorStop(0, `rgba(0,0,0,${edgeAlpha})`);
          gEdge.addColorStop(0.4, `rgba(0,0,0,${edgeAlpha * 0.4})`);
          gEdge.addColorStop(1, 'rgba(0,0,0,0)');
          ctx.fillStyle = gEdge;
          ctx.fillRect(imgRect.x - 50, imgRect.y - 50, imgRect.w + 100, imgRect.h + 100);
        }
        ctx.restore();
      }
    }

    // === 7. 折叠线阴影（投射到底层/curlPoly区域） ===
    if (this.config.enableShadow && localProgress > 0.02 && curlPoly.length >= 3) {
      // 7a. 页面悬浮投影 — 更宽更柔的阴影层（底层）
      if (localProgress > 0.06) {
        ctx.save();
        ctx.beginPath();
        ctx.moveTo(curlPoly[0][0], curlPoly[0][1]);
        for (let k = 1; k < curlPoly.length; k++) {
          ctx.lineTo(curlPoly[k][0], curlPoly[k][1]);
        }
        ctx.closePath();
        ctx.clip();
        const wideSw: number = Math.min(80, imgRect.w * 0.12) * localProgress;
        const wideAlpha: number = Math.min(0.15, 0.03 + localProgress * localProgress * 0.12);
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
        ctx.fillRect(imgRect.x - 50, imgRect.y - 50, imgRect.w + 100, imgRect.h + 100);
        ctx.restore();
      }

      // 7b. 主折叠阴影 — 动态宽度，6-stop高斯式衰减（上层）
      const sw: number = Math.min(50, imgRect.w * (0.04 + 0.04 * localProgress)) * Math.sqrt(localProgress);
      const sa: number = Math.min(0.35, 0.24 * Math.sqrt(localProgress));
      ctx.save();
      ctx.beginPath();
      ctx.moveTo(curlPoly[0][0], curlPoly[0][1]);
      for (let k = 1; k < curlPoly.length; k++) {
        ctx.lineTo(curlPoly[k][0], curlPoly[k][1]);
      }
      ctx.closePath();
      ctx.clip();
      // 极窄接触面阴影带(3px)
      const gContact: CanvasGradient = ctx.createLinearGradient(
        fmx + nx * 1, fmy + ny * 1,
        fmx - nx * 3, fmy - ny * 3
      );
      gContact.addColorStop(0, `rgba(0,0,0,${Math.min(0.4, sa * 1.3)})`);
      gContact.addColorStop(1, 'rgba(0,0,0,0)');
      ctx.fillStyle = gContact;
      ctx.fillRect(imgRect.x - 50, imgRect.y - 50, imgRect.w + 100, imgRect.h + 100);
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
      ctx.fillRect(imgRect.x - 50, imgRect.y - 50, imgRect.w + 100, imgRect.h + 100);
      ctx.restore();
    }

    // === 8. 折叠边缘线 + 高光 ===
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
    if (edgePts.length === 2 && localProgress > 0.015) {
      ctx.save();
      ctx.globalAlpha = 0.12 + 0.1 * localProgress;
      ctx.strokeStyle = '#999999';
      ctx.lineWidth = 0.8;
      ctx.beginPath();
      ctx.moveTo(edgePts[0][0], edgePts[0][1]);
      ctx.lineTo(edgePts[1][0], edgePts[1][1]);
      ctx.stroke();
      ctx.restore();

      if (this.config.enableHighlight) {
        ctx.save();
        ctx.globalAlpha = 0.2 + 0.15 * localProgress;
        ctx.strokeStyle = 'rgba(255,255,255,0.5)';
        ctx.lineWidth = 1.5;
        ctx.beginPath();
        ctx.moveTo(edgePts[0][0], edgePts[0][1]);
        ctx.lineTo(edgePts[1][0], edgePts[1][1]);
        ctx.stroke();
        ctx.restore();
      }
    }
  }

  /**
   * 绘制一对页面（左右各半）——使用 drawImageSafe 多重兗底
   * 左页靠右对齐（紧贴书脊），右页靠左对齐（紧贴书脊）
   */
  private drawSpreadSafe(ctx: CanvasRenderingContext2D,
    leftPM: image.PixelMap | null, leftBm: ImageBitmap | null,
    rightPM: image.PixelMap | null, rightBm: ImageBitmap | null,
    hw: number, ch: number): void {
    ctx.save();
    ctx.globalAlpha = 1.0;
    // 左页靠右对齐（紧贴书脊）
    if (!this.drawImageSafe(ctx, leftPM, leftBm, 0, 0, hw, ch, 'right')) {
      ctx.fillStyle = '#F5F0E1';
      ctx.fillRect(0, 0, hw, ch);
    }
    // 右页靠左对齐（紧贴书脊）
    if (!this.drawImageSafe(ctx, rightPM, rightBm, hw, 0, hw, ch, 'left')) {
      ctx.fillStyle = '#F5F0E1';
      ctx.fillRect(hw, 0, hw, ch);
    }
    ctx.restore();
  }

  // ========== 缓动函数 ==========

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
      const nt: number = t / 0.6;
      return 0.6 * nt * nt;
    } else if (t < 0.9) {
      const nt: number = (t - 0.6) / 0.3;
      const ease: number = nt * (2 - nt);
      return 0.6 + 0.43 * ease;
    } else {
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

  // ========== UI ==========

  build() {
    Stack() {
      Canvas(this.canvasContext)
        .width(this.componentWidth)
        .height(this.componentHeight)
        .backgroundColor('#1a1a1a') // 与 V2 保持一致
        .onReady(() => {
          logger.info(TAG, `onReady: canvasCtx=${this.canvasContext !== null}, size=${this.componentWidth}x${this.componentHeight}, extProgress=${this.externalProgress}`);
          this.isReady = true;
          this.lastCurLeftPM = this.currentLeftPixelMap;
          this.lastCurRightPM = this.currentRightPixelMap;
          this.lastNxtLeftPM = this.nextLeftPixelMap;
          this.lastNxtRightPM = this.nextRightPixelMap;
          this.rebuildBitmaps();
          // 标记初始 bitmap 已构建，并立即锁定，防止动画期间外部更新导致内容变化
          this.initialBitmapsBuilt = true;
          this.bitmapsLocked = true;
          logger.info(TAG, `onReady: 位图就绪并锁定, curL=${this.curLeftBitmap !== null}, curR=${this.curRightBitmap !== null}, nxtL=${this.nxtLeftBitmap !== null}, nxtR=${this.nxtRightBitmap !== null}`);
          this.renderCurlEffect();
          // 检查是否有待执行的动画（解决组件创建时 @Watch 在 onReady 之前触发导致 isReady=false 的竞态）
          if (this.animateToTarget >= 0) {
            logger.info(TAG, `onReady: 发现待执行动画 target=${this.animateToTarget}，启动动画`);
            this.onAnimateToTargetChange();
          }
          // 检查是否有外部拖拽进度
          if (this.externalProgress >= 0) {
            logger.info(TAG, `onReady: 应用外部进度 ${this.externalProgress.toFixed(3)}`);
            this.curlProgress = this.externalProgress;
            this.renderCurlEffect();
          }
        })
    }
    .width(this.componentWidth)
    .height(this.componentHeight)
  }
}
