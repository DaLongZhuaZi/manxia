// Responsibility: plan page-curl support, target pages, progress, and release decisions.

import {
  ReadingDirection,
  ReadingMode
} from 'manxia_core/src/main/ets/Models/MangaModels';
import { CurlStartPosition } from './PageCurlEffectV2';

export type MangaCurlPageTurnDirection = 'left' | 'right' | 'up' | 'down';
export type MangaCurlReleaseAction = 'complete' | 'cancel' | '';

export class MangaCurlSupportInput {
  public readingMode: ReadingMode = ReadingMode.SINGLE_PAGE;
  public readingDirection: ReadingDirection = ReadingDirection.LEFT_TO_RIGHT;
  public isLandscapeScreen: boolean = false;
  public useSmartDoublePageLayout: boolean = false;
}

export class MangaCurlStartInput {
  public touchX: number = 0;
  public screenWidth: number = 360;
}

export class MangaCurlStartPlan {
  public startPosition: CurlStartPosition = CurlStartPosition.RIGHT_EDGE;
}

export class MangaCurlProgressInput {
  public readingMode: ReadingMode = ReadingMode.SINGLE_PAGE;
  public readingDirection: ReadingDirection = ReadingDirection.LEFT_TO_RIGHT;
  public currentPageIndex: number = 0;
  public pageCount: number = 0;
  public deltaX: number = 0;
  public imageWidth: number = 360;
  public screenWidth: number = 360;
  public showThreshold: number = 10;
}

export class MangaCurlProgressPlan {
  public canFlip: boolean = false;
  public targetPageIndex: number = -1;
  public isForward: boolean = false;
  public dragForward: boolean = false;
  public dragDistance: number = 0;
  public progress: number = 0;
  public shouldShowCurl: boolean = false;
  public startPosition: CurlStartPosition = CurlStartPosition.RIGHT_EDGE;
  public pageTurnDirection: MangaCurlPageTurnDirection | null = null;
}

export class MangaCurlReleaseInput {
  public progress: number = 0;
  public flipThreshold: number = 0.33;
  public elapsedMs: number = 1;
  public deltaDistance: number = 0;
  public widthBasis: number = 360;
  public quickVelocityThreshold: number = 0.4;
  public quickDistanceThreshold: number = 30;
  public quickProgressThreshold: number = 0.03;
}

export class MangaCurlReleasePlan {
  public action: MangaCurlReleaseAction = '';
  public velocity: number = 0;
  public progressVelocity: number = 0;
  public isQuickFlip: boolean = false;
}

export class MangaCurlFallbackInput {
  public readingMode: ReadingMode = ReadingMode.SINGLE_PAGE;
  public readingDirection: ReadingDirection = ReadingDirection.LEFT_TO_RIGHT;
  public currentPageIndex: number = 0;
  public pageCount: number = 0;
  public translateX: number = 0;
  public thresholdX: number = 20;
}

export class MangaCurlFallbackPlan {
  public shouldRun: boolean = false;
  public targetPageIndex: number = -1;
  public shouldSwitchChapter: boolean = false;
  public chapterDirection: 'prev' | 'next' | '' = '';
}

export class MangaCurlTurnPlanner {
  public isSupported(input: MangaCurlSupportInput): boolean {
    if (input.readingMode === ReadingMode.SINGLE_PAGE_RTL) {
      return true;
    }
    if (input.readingMode === ReadingMode.SINGLE_PAGE) {
      return input.readingDirection === ReadingDirection.LEFT_TO_RIGHT ||
        input.readingDirection === ReadingDirection.RIGHT_TO_LEFT;
    }
    if (input.readingMode === ReadingMode.DOUBLE_PAGE && input.isLandscapeScreen) {
      return !input.useSmartDoublePageLayout;
    }
    return false;
  }

  public buildStartPlan(input: MangaCurlStartInput): MangaCurlStartPlan {
    const plan: MangaCurlStartPlan = new MangaCurlStartPlan();
    plan.startPosition = input.touchX < input.screenWidth / 2
      ? CurlStartPosition.LEFT_EDGE
      : CurlStartPosition.RIGHT_EDGE;
    return plan;
  }

  public buildProgressPlan(input: MangaCurlProgressInput): MangaCurlProgressPlan {
    const plan: MangaCurlProgressPlan = new MangaCurlProgressPlan();
    plan.dragDistance = Math.abs(input.deltaX);
    plan.dragForward = this.isRtl(input.readingMode, input.readingDirection)
      ? input.deltaX > 0
      : input.deltaX < 0;

    if (input.readingMode === ReadingMode.DOUBLE_PAGE) {
      this.fillDoublePageProgressPlan(input, plan);
    } else {
      this.fillSinglePageProgressPlan(input, plan);
    }

    if (!plan.canFlip) {
      return plan;
    }
    const safeWidth: number = input.imageWidth > 0 ? input.imageWidth : input.screenWidth;
    const widthBasis: number = safeWidth > 0 ? safeWidth : 360;
    let progress: number = plan.dragDistance / widthBasis;
    progress = Math.max(0, Math.min(1, progress));
    if (progress > 0.85) {
      progress = 0.85 + (progress - 0.85) * 0.3;
    }
    plan.progress = progress;
    plan.shouldShowCurl = plan.dragDistance > input.showThreshold;
    return plan;
  }

  public buildReleasePlan(input: MangaCurlReleaseInput): MangaCurlReleasePlan {
    const plan: MangaCurlReleasePlan = new MangaCurlReleasePlan();
    const elapsed: number = Math.max(input.elapsedMs, 1);
    const widthBasis: number = input.widthBasis > 0 ? input.widthBasis : 360;
    plan.velocity = input.deltaDistance / elapsed;
    plan.progressVelocity = plan.velocity / widthBasis;
    plan.isQuickFlip = plan.velocity > input.quickVelocityThreshold &&
      input.deltaDistance > input.quickDistanceThreshold &&
      input.progress > input.quickProgressThreshold;
    plan.action = input.progress >= input.flipThreshold || plan.isQuickFlip ? 'complete' : 'cancel';
    return plan;
  }

  public buildFallbackPlan(input: MangaCurlFallbackInput): MangaCurlFallbackPlan {
    const plan: MangaCurlFallbackPlan = new MangaCurlFallbackPlan();
    if (Math.abs(input.translateX) <= input.thresholdX) {
      return plan;
    }
    const isRtl: boolean = this.isRtl(input.readingMode, input.readingDirection);
    const dragForward: boolean = isRtl ? input.translateX < 0 : input.translateX > 0;
    const targetIndex: number = dragForward ? input.currentPageIndex + 1 : input.currentPageIndex - 1;
    if (targetIndex >= 0 && targetIndex < input.pageCount) {
      plan.shouldRun = true;
      plan.targetPageIndex = targetIndex;
      return plan;
    }
    plan.shouldSwitchChapter = true;
    plan.chapterDirection = dragForward ? 'next' : 'prev';
    return plan;
  }

  public resolveStartPositionForDirection(isRightSide: boolean): CurlStartPosition {
    return isRightSide ? CurlStartPosition.RIGHT_EDGE : CurlStartPosition.LEFT_EDGE;
  }

  private fillDoublePageProgressPlan(input: MangaCurlProgressInput, plan: MangaCurlProgressPlan): void {
    const maxIndex: number = input.pageCount - 1;
    const pairStart: number = input.currentPageIndex - (input.currentPageIndex % 2);
    const nextPairStart: number = Math.min(pairStart + 2, maxIndex - (maxIndex % 2));
    const prevPairStart: number = Math.max(pairStart - 2, 0);
    if (plan.dragForward) {
      plan.targetPageIndex = nextPairStart;
      plan.canFlip = nextPairStart > pairStart;
      plan.isForward = true;
      plan.startPosition = this.resolveStartPositionForDirection(true);
      plan.pageTurnDirection = 'left';
      return;
    }
    plan.targetPageIndex = prevPairStart;
    plan.canFlip = prevPairStart < pairStart;
    plan.isForward = false;
    plan.startPosition = this.resolveStartPositionForDirection(false);
    plan.pageTurnDirection = 'right';
  }

  private fillSinglePageProgressPlan(input: MangaCurlProgressInput, plan: MangaCurlProgressPlan): void {
    const isRtl: boolean = this.isRtl(input.readingMode, input.readingDirection);
    if (plan.dragForward) {
      plan.targetPageIndex = input.currentPageIndex + 1;
      plan.canFlip = plan.targetPageIndex < input.pageCount;
      plan.isForward = true;
      plan.startPosition = this.resolveStartPositionForDirection(!isRtl);
      plan.pageTurnDirection = isRtl ? 'right' : 'left';
      return;
    }
    plan.targetPageIndex = input.currentPageIndex - 1;
    plan.canFlip = plan.targetPageIndex >= 0;
    plan.isForward = false;
    plan.startPosition = this.resolveStartPositionForDirection(isRtl);
    plan.pageTurnDirection = isRtl ? 'left' : 'right';
  }

  private isRtl(readingMode: ReadingMode, readingDirection: ReadingDirection): boolean {
    return readingMode === ReadingMode.SINGLE_PAGE_RTL ||
      (readingMode === ReadingMode.DOUBLE_PAGE && readingDirection === ReadingDirection.RIGHT_TO_LEFT) ||
      (readingMode === ReadingMode.SINGLE_PAGE && readingDirection === ReadingDirection.RIGHT_TO_LEFT);
  }
}
