/**
 * EPUB 翻页动画引擎
 * 从 EpubWebViewReaderComponent 提取的纯函数工具类
 * 负责构建视口动画矩阵和动画配置
 */

import { matrix4, curves } from '@kit.ArkUI';
import { ReadingDirection, PageTurnAnimationType } from '../../Models/MangaModels';
import { EpubPageLayoutKind } from './EpubCssBuilder';

export interface ViewportAnimationState {
  opacity: number;
  matrix: matrix4.Matrix4Transit;
}

export interface PageTurnAnimationProfile {
  outgoing: ViewportAnimationState;
  incoming: ViewportAnimationState;
  outDuration: number;
  inDuration: number;
  outCurve: Curve;
  inCurve: Curve;
}

export class EpubAnimationEngine {

  static buildMatrix(
    translateX: number,
    translateY: number,
    translateZ: number,
    scaleX: number,
    scaleY: number,
    rotateX: number,
    rotateY: number
  ): matrix4.Matrix4Transit {
    let matrix = matrix4.identity();
    matrix = matrix.translate({ x: translateX, y: translateY, z: translateZ });
    if (rotateX !== 0) {
      matrix = matrix.rotate({ x: 1, y: 0, z: 0, angle: rotateX });
    }
    if (rotateY !== 0) {
      matrix = matrix.rotate({ x: 0, y: 1, z: 0, angle: rotateY });
    }
    matrix = matrix.scale({ x: scaleX, y: scaleY, z: 1 });
    return matrix;
  }

  static getAnimationDirectionSign(layoutKind: EpubPageLayoutKind, forward: boolean, readingDirection: ReadingDirection): number {
    if (layoutKind === 'vertical_paged' || layoutKind === 'continuous_vertical') {
      return forward ? -1 : 1;
    }
    if (readingDirection === ReadingDirection.RIGHT_TO_LEFT) {
      return forward ? 1 : -1;
    }
    return forward ? -1 : 1;
  }

  static normalizeAnimationType(animationType: PageTurnAnimationType): PageTurnAnimationType {
    if (animationType === PageTurnAnimationType.FLIP) {
      return PageTurnAnimationType.CUBE;
    }
    if (animationType === PageTurnAnimationType.ZOOM) {
      return PageTurnAnimationType.DEPTH;
    }
    return animationType;
  }

  static normalizeViewportAnimationType(animationType: PageTurnAnimationType): PageTurnAnimationType {
    const normalized = EpubAnimationEngine.normalizeAnimationType(animationType);
    if (normalized === PageTurnAnimationType.CURL) {
      return PageTurnAnimationType.COVER;
    }
    return normalized;
  }

  static createTextSafeAnimationProfile(
    layoutKind: EpubPageLayoutKind,
    forward: boolean,
    animationType: PageTurnAnimationType,
    viewportW: number,
    viewportH: number,
    readingDirection: ReadingDirection
  ): PageTurnAnimationProfile {
    const isVertical = layoutKind === 'vertical_paged' || layoutKind === 'continuous_vertical';
    const extent = isVertical ? viewportH : viewportW;
    const sign = EpubAnimationEngine.getAnimationDirectionSign(layoutKind, forward, readingDirection);
    const axisX = isVertical ? 0 : extent * sign;
    const axisY = isVertical ? extent * sign : 0;
    const incomingX = -axisX;
    const incomingY = -axisY;

    switch (animationType) {
      case PageTurnAnimationType.SLIDE:
        return {
          outgoing: {
            opacity: 0.82,
            matrix: EpubAnimationEngine.buildMatrix(axisX * 0.08, axisY * 0.08, 0, 1, 1, 0, 0)
          },
          incoming: {
            opacity: 1,
            matrix: EpubAnimationEngine.buildMatrix(incomingX * 0.16, incomingY * 0.16, 0, 1, 1, 0, 0)
          },
          outDuration: 90,
          inDuration: 170,
          outCurve: Curve.EaseIn,
          inCurve: Curve.FastOutSlowIn
        };
      case PageTurnAnimationType.FADE:
        return {
          outgoing: {
            opacity: 0.06,
            matrix: EpubAnimationEngine.buildMatrix(0, 0, 0, 1, 1, 0, 0)
          },
          incoming: {
            opacity: 0.18,
            matrix: EpubAnimationEngine.buildMatrix(0, 0, 0, 1, 1, 0, 0)
          },
          outDuration: 100,
          inDuration: 160,
          outCurve: Curve.EaseOut,
          inCurve: Curve.EaseIn
        };
      case PageTurnAnimationType.COVER:
        return {
          outgoing: {
            opacity: 0.92,
            matrix: EpubAnimationEngine.buildMatrix(axisX * 0.03, axisY * 0.03, 0, 1, 1, 0, 0)
          },
          incoming: {
            opacity: 1,
            matrix: EpubAnimationEngine.buildMatrix(incomingX * 0.20, incomingY * 0.20, 0, 1, 1, 0, 0)
          },
          outDuration: 85,
          inDuration: 180,
          outCurve: Curve.EaseOut,
          inCurve: Curve.FastOutSlowIn
        };
      case PageTurnAnimationType.CUBE:
        return {
          outgoing: {
            opacity: 0.54,
            matrix: EpubAnimationEngine.buildMatrix(axisX * 0.05, axisY * 0.05, 0, 0.995, 0.995, 0, 0)
          },
          incoming: {
            opacity: 0.74,
            matrix: EpubAnimationEngine.buildMatrix(incomingX * 0.12, incomingY * 0.12, 0, 1, 1, 0, 0)
          },
          outDuration: 95,
          inDuration: 185,
          outCurve: Curve.EaseInOut,
          inCurve: Curve.FastOutSlowIn
        };
      case PageTurnAnimationType.DEPTH:
        return {
          outgoing: {
            opacity: 0.38,
            matrix: EpubAnimationEngine.buildMatrix(axisX * 0.02, axisY * 0.02, 0, 0.985, 0.985, 0, 0)
          },
          incoming: {
            opacity: 0.68,
            matrix: EpubAnimationEngine.buildMatrix(-axisX * 0.03, -axisY * 0.03, 0, 1.015, 1.015, 0, 0)
          },
          outDuration: 90,
          inDuration: 190,
          outCurve: Curve.EaseIn,
          inCurve: Curve.FastOutSlowIn
        };
      default:
        return {
          outgoing: {
            opacity: 0.12,
            matrix: EpubAnimationEngine.buildMatrix(0, 0, 0, 1, 1, 0, 0)
          },
          incoming: {
            opacity: 0.22,
            matrix: EpubAnimationEngine.buildMatrix(0, 0, 0, 1, 1, 0, 0)
          },
          outDuration: 90,
          inDuration: 160,
          outCurve: Curve.EaseOut,
          inCurve: Curve.EaseIn
        };
    }
  }

  static createAnimationProfile(
    layoutKind: EpubPageLayoutKind,
    forward: boolean,
    animationType: PageTurnAnimationType,
    viewportW: number,
    viewportH: number,
    readingDirection: ReadingDirection,
    isFixedLayout: boolean
  ): PageTurnAnimationProfile {
    const normalizedAnimation = EpubAnimationEngine.normalizeViewportAnimationType(animationType);
    if (!isFixedLayout) {
      return EpubAnimationEngine.createTextSafeAnimationProfile(layoutKind, forward, normalizedAnimation, viewportW, viewportH, readingDirection);
    }
    const isVertical = layoutKind === 'vertical_paged' || layoutKind === 'continuous_vertical';
    const extent = isVertical ? viewportH : viewportW;
    const sign = EpubAnimationEngine.getAnimationDirectionSign(layoutKind, forward, readingDirection);
    const axisX = isVertical ? 0 : extent * sign;
    const axisY = isVertical ? extent * sign : 0;
    const incomingX = -axisX;
    const incomingY = -axisY;

    switch (normalizedAnimation) {
      case PageTurnAnimationType.SLIDE:
        return {
          outgoing: {
            opacity: 0.18,
            matrix: EpubAnimationEngine.buildMatrix(axisX * 0.28, axisY * 0.28, 0, 0.96, 0.96, 0, 0)
          },
          incoming: {
            opacity: 0.32,
            matrix: EpubAnimationEngine.buildMatrix(incomingX * 0.72, incomingY * 0.72, -40, 0.96, 0.96, 0, 0)
          },
          outDuration: 120,
          inDuration: 190,
          outCurve: Curve.EaseIn,
          inCurve: Curve.FastOutSlowIn
        };
      case PageTurnAnimationType.FADE:
        return {
          outgoing: {
            opacity: 0.08,
            matrix: EpubAnimationEngine.buildMatrix(0, 0, 0, 0.97, 0.97, 0, 0)
          },
          incoming: {
            opacity: 0.14,
            matrix: EpubAnimationEngine.buildMatrix(0, 0, 0, 1.03, 1.03, 0, 0)
          },
          outDuration: 100,
          inDuration: 180,
          outCurve: Curve.EaseIn,
          inCurve: Curve.EaseOut
        };
      case PageTurnAnimationType.CUBE:
        return {
          outgoing: {
            opacity: 0.28,
            matrix: EpubAnimationEngine.buildMatrix(
              axisX * 0.22,
              axisY * 0.22,
              -viewportW * 0.2,
              0.92,
              0.92,
              isVertical ? -sign * 42 : 0,
              isVertical ? 0 : -sign * 54
            )
          },
          incoming: {
            opacity: 0.44,
            matrix: EpubAnimationEngine.buildMatrix(
              incomingX * 0.18,
              incomingY * 0.18,
              -viewportW * 0.2,
              0.92,
              0.92,
              isVertical ? sign * 54 : 0,
              isVertical ? 0 : sign * 54
            )
          },
          outDuration: 135,
          inDuration: 215,
          outCurve: Curve.EaseInOut,
          inCurve: Curve.EaseInOut
        };
      case PageTurnAnimationType.COVER:
        return {
          outgoing: {
            opacity: 0.9,
            matrix: EpubAnimationEngine.buildMatrix(axisX * 0.04, axisY * 0.04, 0, 0.985, 0.985, 0, 0)
          },
          incoming: {
            opacity: 1,
            matrix: EpubAnimationEngine.buildMatrix(
              incomingX * 0.98,
              incomingY * 0.98,
              40,
              1.02,
              1.02,
              isVertical ? sign * 4 : 0,
              isVertical ? 0 : sign * 4
            )
          },
          outDuration: 70,
          inDuration: 220,
          outCurve: Curve.EaseOut,
          inCurve: Curve.FastOutSlowIn
        };
      case PageTurnAnimationType.DEPTH:
        return {
          outgoing: {
            opacity: 0.16,
            matrix: EpubAnimationEngine.buildMatrix(axisX * 0.08, axisY * 0.08, -180, 0.84, 0.84, 0, 0)
          },
          incoming: {
            opacity: 0.38,
            matrix: EpubAnimationEngine.buildMatrix(
              -axisX * 0.06,
              -axisY * 0.06,
              -260,
              0.62,
              0.62,
              isVertical ? sign * 10 : -6,
              isVertical ? 0 : sign * 10
            )
          },
          outDuration: 110,
          inDuration: 240,
          outCurve: Curve.EaseIn,
          inCurve: Curve.FastOutSlowIn
        };
      default:
        return {
          outgoing: {
            opacity: 0.14,
            matrix: EpubAnimationEngine.buildMatrix(axisX * 0.24, axisY * 0.24, 0, 0.96, 0.96, 0, 0)
          },
          incoming: {
            opacity: 0.24,
            matrix: EpubAnimationEngine.buildMatrix(incomingX * 0.58, incomingY * 0.58, 0, 0.96, 0.96, 0, 0)
          },
          outDuration: 110,
          inDuration: 180,
          outCurve: Curve.EaseIn,
          inCurve: Curve.FastOutSlowIn
        };
    }
  }
}
