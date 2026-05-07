/**
 * 通用对话框动画状态管理
 * 将每个对话框的 3-4 个动画变量（opacity/scale/translateY）合并为一个 @State 对象
 */

import { curves } from '@kit.ArkUI';

/** DialogAnimationState 构造参数 */
export interface DialogAnimationStateParams {
  initialScale?: number;
  initialTranslateY?: number;
  closeScale?: number;
  closeTranslateY?: number;
  inDuration?: number;
  outDuration?: number;
  inCurve?: Curve | ICurve;
  outCurve?: Curve | ICurve;
}

@Observed
export class DialogAnimationState {
  opacity: number = 0;
  scale: number = 0.95;
  translateY: number = 0;

  private initialScale: number;
  private initialTranslateY: number;
  private inDuration: number;
  private outDuration: number;
  private inCurve: Curve | ICurve;
  private outCurve: Curve | ICurve;
  private closeScale: number;
  private closeTranslateY: number;

  constructor(params?: DialogAnimationStateParams) {
    this.initialScale = params?.initialScale ?? 0.8;
    this.initialTranslateY = params?.initialTranslateY ?? 30;
    this.closeScale = params?.closeScale ?? 0.96;
    this.closeTranslateY = params?.closeTranslateY ?? 12;
    this.inDuration = params?.inDuration ?? 260;
    this.outDuration = params?.outDuration ?? 180;
    this.inCurve = params?.inCurve ?? Curve.EaseOut;
    this.outCurve = params?.outCurve ?? Curve.EaseIn;

    this.opacity = 0;
    this.scale = this.initialScale;
    this.translateY = this.initialTranslateY;
  }

  /** 重置到初始隐藏状态（无动画） */
  reset(): void {
    this.opacity = 0;
    this.scale = this.initialScale;
    this.translateY = this.initialTranslateY;
  }

  /** 入场动画 */
  animateIn(uiContext: UIContext): void {
    uiContext.animateTo({
      duration: this.inDuration,
      curve: this.inCurve
    }, () => {
      this.opacity = 1;
      this.scale = 1;
      this.translateY = 0;
    });
  }

  /** 出场动画，完成后回调 */
  animateOut(uiContext: UIContext, onFinished?: () => void): void {
    uiContext.animateTo({
      duration: this.outDuration,
      curve: this.outCurve
    }, () => {
      this.opacity = 0;
      this.scale = this.closeScale;
      this.translateY = this.closeTranslateY;
    });
    if (onFinished) {
      setTimeout(onFinished, this.outDuration + 20);
    }
  }
}
