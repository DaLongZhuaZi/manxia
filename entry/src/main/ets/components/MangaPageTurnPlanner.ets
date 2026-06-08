// Responsibility: plan normal single-page and double-page turn decisions from release gestures.

import {
  ReadingDirection,
  ReadingMode
} from '../Models/MangaModels';

export type MangaPlannedPageTurnDirection = 'left' | 'right' | 'up' | 'down';
export type MangaPlannedChapterDirection = 'prev' | 'next' | '';

export class MangaPageTurnInput {
  public readingMode: ReadingMode = ReadingMode.SINGLE_PAGE;
  public readingDirection: ReadingDirection = ReadingDirection.LEFT_TO_RIGHT;
  public pageCount: number = 0;
  public currentPageIndex: number = 0;
  public translateX: number = 0;
  public translateY: number = 0;
  public thresholdX: number = 20;
  public thresholdY: number = 20;
  public isSinglePageVerticalPagingMode: boolean = false;
  public isDoublePageVerticalPortraitMode: boolean = false;
  public isDoublePageVerticalNextAtTop: boolean = false;
  public doubleCurrentStartIndex: number = -1;
  public doublePreviousStartIndex: number = -1;
  public doubleNextStartIndex: number = -1;
  public doublePreviousModeLabel: string = '';
  public doubleNextModeLabel: string = '';
}

export class MangaPageTurnPlan {
  public pageChanged: boolean = false;
  public shouldSwitchChapter: boolean = false;
  public chapterDirection: MangaPlannedChapterDirection = '';
  public targetPageIndex: number = -1;
  public pageTurnDirection: MangaPlannedPageTurnDirection | null = null;
  public shouldUpdateDoublePageIndices: boolean = false;
  public isSinglePageTurn: boolean = false;
  public logMessage: string = '';
}

export class MangaPageTurnPlanner {
  public buildPlan(input: MangaPageTurnInput): MangaPageTurnPlan {
    const plan: MangaPageTurnPlan = new MangaPageTurnPlan();
    if (input.pageCount <= 0) {
      return plan;
    }

    if (input.readingMode === ReadingMode.DOUBLE_PAGE) {
      return this.buildDoublePagePlan(input);
    }
    if (input.isSinglePageVerticalPagingMode) {
      return this.buildSinglePageVerticalPlan(input);
    }
    return this.buildSinglePageHorizontalPlan(input);
  }

  private buildDoublePagePlan(input: MangaPageTurnInput): MangaPageTurnPlan {
    if (input.isDoublePageVerticalPortraitMode) {
      return this.buildDoublePageVerticalPlan(input);
    }
    if (Math.abs(input.translateX) <= input.thresholdX) {
      return new MangaPageTurnPlan();
    }

    const isRtl: boolean = input.readingDirection === ReadingDirection.RIGHT_TO_LEFT;
    if (isRtl) {
      if (input.translateX > input.thresholdX) {
        return this.buildDoublePageTargetPlan(
          input,
          input.doubleNextStartIndex,
          input.doubleCurrentStartIndex,
          'right',
          'next',
          `双页RTL：向右拖拽，下一组显示（${input.doubleNextModeLabel}）`,
          true
        );
      }
      return this.buildDoublePageTargetPlan(
        input,
        input.doublePreviousStartIndex,
        input.doubleCurrentStartIndex,
        'left',
        'prev',
        `双页RTL：向左拖拽，上一组显示（${input.doublePreviousModeLabel}）`,
        false
      );
    }

    if (input.translateX > input.thresholdX) {
      return this.buildDoublePageTargetPlan(
        input,
        input.doublePreviousStartIndex,
        input.doubleCurrentStartIndex,
        'right',
        'prev',
        `双页LTR：向右拖拽，上一组显示（${input.doublePreviousModeLabel}）`,
        false
      );
    }
    return this.buildDoublePageTargetPlan(
      input,
      input.doubleNextStartIndex,
      input.doubleCurrentStartIndex,
      'left',
      'next',
      `双页LTR：向左拖拽，下一组显示（${input.doubleNextModeLabel}）`,
      true
    );
  }

  private buildDoublePageVerticalPlan(input: MangaPageTurnInput): MangaPageTurnPlan {
    if (Math.abs(input.translateY) <= input.thresholdY) {
      return new MangaPageTurnPlan();
    }

    const maxIndex: number = input.pageCount - 1;
    const pairStart: number = input.currentPageIndex - (input.currentPageIndex % 2);
    const nextPairStart: number = Math.min(pairStart + 2, maxIndex - (maxIndex % 2));
    const prevPairStart: number = Math.max(pairStart - 2, 0);
    const draggedUp: boolean = input.translateY < -input.thresholdY;
    const draggedDown: boolean = input.translateY > input.thresholdY;
    const dragForward: boolean = input.isDoublePageVerticalNextAtTop ? draggedDown : draggedUp;
    const direction: MangaPlannedPageTurnDirection = draggedDown ? 'down' : 'up';

    if (dragForward) {
      if (nextPairStart > pairStart) {
        return this.buildPagePlan(nextPairStart, direction, false, true,
          `双页竖向：${draggedDown ? '向下' : '向上'}拖拽，下一对页`);
      }
      return this.buildChapterPlan('next');
    }

    if (prevPairStart < pairStart) {
      return this.buildPagePlan(prevPairStart, direction, false, true,
        `双页竖向：${draggedDown ? '向下' : '向上'}拖拽，上一对页`);
    }
    return this.buildChapterPlan('prev');
  }

  private buildDoublePageTargetPlan(
    input: MangaPageTurnInput,
    targetStartIndex: number,
    currentStartIndex: number,
    pageTurnDirection: MangaPlannedPageTurnDirection,
    chapterDirection: 'prev' | 'next',
    logMessage: string,
    targetShouldBeAfterCurrent: boolean
  ): MangaPageTurnPlan {
    const hasValidTarget: boolean = targetStartIndex >= 0 &&
      (targetShouldBeAfterCurrent ? targetStartIndex > currentStartIndex : targetStartIndex < currentStartIndex);
    if (hasValidTarget) {
      return this.buildPagePlan(targetStartIndex, pageTurnDirection, false, true, logMessage);
    }
    return this.buildChapterPlan(chapterDirection);
  }

  private buildSinglePageVerticalPlan(input: MangaPageTurnInput): MangaPageTurnPlan {
    if (Math.abs(input.translateY) <= input.thresholdY) {
      return new MangaPageTurnPlan();
    }

    if (input.translateY > 0) {
      if (input.currentPageIndex > 0) {
        return this.buildPagePlan(input.currentPageIndex - 1, 'down', true, false, '单页TTB模式：向下拖拽，上一页');
      }
      return this.buildChapterPlan('prev');
    }

    if (input.currentPageIndex < input.pageCount - 1) {
      return this.buildPagePlan(input.currentPageIndex + 1, 'up', true, false, '单页TTB模式：向上拖拽，下一页');
    }
    return this.buildChapterPlan('next');
  }

  private buildSinglePageHorizontalPlan(input: MangaPageTurnInput): MangaPageTurnPlan {
    if (!this.isHorizontalSinglePageMode(input)) {
      return new MangaPageTurnPlan();
    }
    if (Math.abs(input.translateX) <= input.thresholdX) {
      return new MangaPageTurnPlan();
    }

    const isRtl: boolean = input.readingMode === ReadingMode.SINGLE_PAGE_RTL ||
      (input.readingMode === ReadingMode.SINGLE_PAGE && input.readingDirection === ReadingDirection.RIGHT_TO_LEFT);
    if (isRtl) {
      if (input.translateX > 0) {
        if (input.currentPageIndex < input.pageCount - 1) {
          return this.buildPagePlan(input.currentPageIndex + 1, 'right', true, false, '单页RTL模式：向右拖拽，下一页');
        }
        return this.buildChapterPlan('next');
      }
      if (input.currentPageIndex > 0) {
        return this.buildPagePlan(input.currentPageIndex - 1, 'left', true, false, '单页RTL模式：向左拖拽，上一页');
      }
      return this.buildChapterPlan('prev');
    }

    if (input.translateX > 0) {
      if (input.currentPageIndex > 0) {
        return this.buildPagePlan(input.currentPageIndex - 1, 'right', true, false, '单页水平模式：向右拖拽，上一页');
      }
      return this.buildChapterPlan('prev');
    }
    if (input.currentPageIndex < input.pageCount - 1) {
      return this.buildPagePlan(input.currentPageIndex + 1, 'left', true, false, '单页水平模式：向左拖拽，下一页');
    }
    return this.buildChapterPlan('next');
  }

  private isHorizontalSinglePageMode(input: MangaPageTurnInput): boolean {
    return input.readingMode === ReadingMode.SINGLE_PAGE ||
      input.readingMode === ReadingMode.SINGLE_PAGE_LTR ||
      input.readingMode === ReadingMode.SINGLE_PAGE_RTL;
  }

  private buildPagePlan(
    targetPageIndex: number,
    pageTurnDirection: MangaPlannedPageTurnDirection,
    isSinglePageTurn: boolean,
    shouldUpdateDoublePageIndices: boolean,
    logMessage: string
  ): MangaPageTurnPlan {
    const plan: MangaPageTurnPlan = new MangaPageTurnPlan();
    plan.pageChanged = true;
    plan.targetPageIndex = targetPageIndex;
    plan.pageTurnDirection = pageTurnDirection;
    plan.isSinglePageTurn = isSinglePageTurn;
    plan.shouldUpdateDoublePageIndices = shouldUpdateDoublePageIndices;
    plan.logMessage = logMessage;
    return plan;
  }

  private buildChapterPlan(chapterDirection: 'prev' | 'next'): MangaPageTurnPlan {
    const plan: MangaPageTurnPlan = new MangaPageTurnPlan();
    plan.shouldSwitchChapter = true;
    plan.chapterDirection = chapterDirection;
    return plan;
  }
}
