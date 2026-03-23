import { UIContext } from '@kit.ArkUI';
import { GuideHighlightRect } from './AppGuideOverlay';

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
    if (rootAnchorId && rootAnchorId.length > 0) {
      const rootRectInfo = componentUtils.getRectangleById(rootAnchorId);
      if (rootRectInfo) {
        originX = Number(rootRectInfo.windowOffset.x);
        originY = Number(rootRectInfo.windowOffset.y);
      }
    }

    return {
      x: Math.max(0, px2vp(Number(rectInfo.windowOffset.x) - originX)),
      y: Math.max(0, px2vp(Number(rectInfo.windowOffset.y) - originY)),
      width: px2vp(Number(rectInfo.size.width)),
      height: px2vp(Number(rectInfo.size.height)),
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

    const viewportTop: number = px2vp(Number(viewportRect.windowOffset.y)) + topPaddingVp;
    const viewportBottom: number = px2vp(Number(viewportRect.windowOffset.y) + Number(viewportRect.size.height)) - bottomPaddingVp;
    const anchorTop: number = px2vp(Number(anchorRect.windowOffset.y));
    const anchorBottom: number = anchorTop + px2vp(Number(anchorRect.size.height));

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
