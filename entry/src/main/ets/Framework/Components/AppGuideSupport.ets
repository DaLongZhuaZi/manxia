import { UIContext } from '@kit.ArkUI';
import { GuideHighlightRect } from 'manxia_theme/src/main/ets/Framework/Components/AppGuideOverlay';

export interface GuideAnchorVisibilityResult {
  available: boolean;
  scrolled: boolean;
}

export function resolveGuideHighlightRectInRoot(
  uiContext: UIContext,
  anchorId?: string,
  borderRadius: number = 18,
  rootAnchorId?: string
): GuideHighlightRect | null {
  if (!anchorId || anchorId.length <= 0) {
    return null;
  }

  try {
    const componentUtils = uiContext.getComponentUtils();
    const rectInfo = componentUtils.getRectangleById(anchorId);
    if (!rectInfo || Number(rectInfo.size.width) <= 0 || Number(rectInfo.size.height) <= 0) {
      return null;
    }

    let originX = 0;
    let originY = 0;
    let rootWidth = 0;
    let rootHeight = 0;
    if (rootAnchorId && rootAnchorId.length > 0) {
      const rootRectInfo = componentUtils.getRectangleById(rootAnchorId);
      if (rootRectInfo) {
        originX = Number(rootRectInfo.windowOffset.x);
        originY = Number(rootRectInfo.windowOffset.y);
        rootWidth = uiContext.px2vp(Number(rootRectInfo.size.width));
        rootHeight = uiContext.px2vp(Number(rootRectInfo.size.height));
      }
    }

    const rawX = uiContext.px2vp(Number(rectInfo.windowOffset.x) - originX);
    const rawY = uiContext.px2vp(Number(rectInfo.windowOffset.y) - originY);
    const rawWidth = uiContext.px2vp(Number(rectInfo.size.width));
    const rawHeight = uiContext.px2vp(Number(rectInfo.size.height));
    const visibleRight = rootWidth > 0 ? Math.min(rootWidth, rawX + rawWidth) : rawX + rawWidth;
    const visibleBottom = rootHeight > 0 ? Math.min(rootHeight, rawY + rawHeight) : rawY + rawHeight;
    const clippedX = Math.max(0, rawX);
    const clippedY = Math.max(0, rawY);
    const clippedWidth = Math.max(0, visibleRight - clippedX);
    const clippedHeight = Math.max(0, visibleBottom - clippedY);
    if (clippedWidth <= 0 || clippedHeight <= 0) {
      return null;
    }

    return {
      x: clippedX,
      y: clippedY,
      width: clippedWidth,
      height: clippedHeight,
      borderRadius: borderRadius
    };
  } catch (_error) {
    return null;
  }
}

export function ensureGuideAnchorVisibleInScroller(
  uiContext: UIContext,
  scroller: Scroller,
  anchorId?: string,
  viewportAnchorId?: string,
  topPaddingVp: number = 12,
  bottomPaddingVp: number = 24,
  animationDuration: number = 260
): GuideAnchorVisibilityResult {
  if (!anchorId || anchorId.length <= 0 || !viewportAnchorId || viewportAnchorId.length <= 0) {
    return { available: false, scrolled: false };
  }

  try {
    const componentUtils = uiContext.getComponentUtils();
    const anchorRect = componentUtils.getRectangleById(anchorId);
    const viewportRect = componentUtils.getRectangleById(viewportAnchorId);
    if (!anchorRect || !viewportRect ||
      Number(anchorRect.size.width) <= 0 || Number(anchorRect.size.height) <= 0 ||
      Number(viewportRect.size.width) <= 0 || Number(viewportRect.size.height) <= 0) {
      return { available: false, scrolled: false };
    }

    if (Number(anchorRect.size.height) >= Number(viewportRect.size.height)) {
      return { available: true, scrolled: false };
    }

    const viewportTop: number = uiContext.px2vp(Number(viewportRect.windowOffset.y)) + topPaddingVp;
    const viewportBottom: number = uiContext.px2vp(Number(viewportRect.windowOffset.y) + Number(viewportRect.size.height)) - bottomPaddingVp;
    const anchorTop: number = uiContext.px2vp(Number(anchorRect.windowOffset.y));
    const anchorBottom: number = anchorTop + uiContext.px2vp(Number(anchorRect.size.height));

    let deltaY: number = 0;
    if (anchorTop < viewportTop) {
      deltaY = anchorTop - viewportTop;
    } else if (anchorBottom > viewportBottom) {
      deltaY = anchorBottom - viewportBottom;
    } else {
      return { available: true, scrolled: false };
    }

    const currentOffset = scroller.currentOffset();
    const currentOffsetY: number = Number(currentOffset?.yOffset ?? 0);
    const nextOffsetY: number = Math.max(0, currentOffsetY + deltaY);
    scroller.scrollTo({
      xOffset: 0,
      yOffset: nextOffsetY,
      animation: { duration: animationDuration }
    });
    return { available: true, scrolled: true };
  } catch (_error) {
    return { available: false, scrolled: false };
  }
}
