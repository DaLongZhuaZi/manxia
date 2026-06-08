// Responsibility: plan visible pages and progress for continuous horizontal reading.

export class MangaContinuousHorizontalPageRange {
  public pageIndex: number = 0;
  public left: number = 0;
  public right: number = 0;
}

export class MangaContinuousHorizontalViewportInput {
  public scrollLeft: number = 0;
  public containerWidth: number = 360;
  public pageRanges: MangaContinuousHorizontalPageRange[] = [];
}

export class MangaContinuousHorizontalViewportPlan {
  public visiblePageIndices: number[] = [];
}

export class MangaContinuousHorizontalProgressInput {
  public hasPages: boolean = false;
  public currentPageIndex: number = 0;
  public currentWebtoonPage: number = 0;
  public scrollPosition: number = 0;
  public maxScroll: number = 1;
  public isRtl: boolean = false;
}

export class MangaContinuousHorizontalProgressPlan {
  public shouldUpdatePage: boolean = false;
  public pageIndex: number = 0;
  public shouldNotifyPageChange: boolean = false;
  public shouldUpdateProgress: boolean = false;
  public progress: number = 0;
}

export class MangaContinuousHorizontalViewportPlanner {
  public buildViewportPlan(input: MangaContinuousHorizontalViewportInput): MangaContinuousHorizontalViewportPlan {
    const plan: MangaContinuousHorizontalViewportPlan = new MangaContinuousHorizontalViewportPlan();
    const scrollRight: number = input.scrollLeft + input.containerWidth;
    for (let i = 0; i < input.pageRanges.length; i++) {
      const range: MangaContinuousHorizontalPageRange = input.pageRanges[i];
      if (range.left > scrollRight + input.containerWidth) {
        break;
      }
      if (range.right >= input.scrollLeft - input.containerWidth && range.left <= scrollRight + input.containerWidth) {
        plan.visiblePageIndices.push(range.pageIndex);
      }
    }
    return plan;
  }

  public buildProgressPlan(input: MangaContinuousHorizontalProgressInput): MangaContinuousHorizontalProgressPlan {
    const plan: MangaContinuousHorizontalProgressPlan = new MangaContinuousHorizontalProgressPlan();
    if (!input.hasPages) {
      return plan;
    }

    if (input.currentPageIndex !== input.currentWebtoonPage) {
      plan.shouldUpdatePage = true;
      plan.pageIndex = input.currentPageIndex;
      plan.shouldNotifyPageChange = true;
    }

    const maxScrollable: number = Math.max(1, input.maxScroll);
    const rawProgress: number = this.clamp(input.scrollPosition / maxScrollable, 0, 1);
    plan.shouldUpdateProgress = true;
    plan.progress = input.isRtl ? 1 - rawProgress : rawProgress;
    return plan;
  }

  private clamp(value: number, minValue: number, maxValue: number): number {
    return Math.max(minValue, Math.min(maxValue, value));
  }
}
