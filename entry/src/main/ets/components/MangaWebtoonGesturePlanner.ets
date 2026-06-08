// Responsibility: calculate webtoon zoom and pan state transitions.

export class MangaWebtoonPanInput {
  public zoomScale: number = 1;
  public minZoomScale: number = 1;
  public offsetX: number = 0;
  public offsetY: number = 0;
  public deltaX: number = 0;
  public deltaY: number = 0;
  public screenWidth: number = 360;
  public screenHeight: number = 800;
}

export class MangaWebtoonPanPlan {
  public shouldApply: boolean = false;
  public offsetX: number = 0;
  public offsetY: number = 0;
}

export class MangaWebtoonPinchInput {
  public pinchStartScale: number = 1;
  public gestureScale: number = 1;
  public minZoomScale: number = 1;
  public maxZoomScale: number = 3;
}

export class MangaWebtoonPinchPlan {
  public zoomScale: number = 1;
  public shouldResetOffset: boolean = false;
}

export class MangaWebtoonPinchEndInput {
  public zoomScale: number = 1;
  public minZoomScale: number = 1;
}

export class MangaWebtoonPinchEndPlan {
  public shouldSnapToMin: boolean = false;
  public zoomScale: number = 1;
  public offsetX: number = 0;
  public offsetY: number = 0;
}

export class MangaWebtoonGesturePlanner {
  public buildPanPlan(input: MangaWebtoonPanInput): MangaWebtoonPanPlan {
    const plan: MangaWebtoonPanPlan = new MangaWebtoonPanPlan();
    if (input.zoomScale <= input.minZoomScale) {
      return plan;
    }

    const maxOffsetX: number = input.zoomScale * input.screenWidth;
    const maxOffsetY: number = input.zoomScale * input.screenHeight;
    plan.shouldApply = true;
    plan.offsetX = this.clamp(input.offsetX + input.deltaX, -maxOffsetX, maxOffsetX);
    plan.offsetY = this.clamp(input.offsetY + input.deltaY, -maxOffsetY, maxOffsetY);
    return plan;
  }

  public buildPinchPlan(input: MangaWebtoonPinchInput): MangaWebtoonPinchPlan {
    const plan: MangaWebtoonPinchPlan = new MangaWebtoonPinchPlan();
    plan.zoomScale = this.clamp(input.pinchStartScale * input.gestureScale, input.minZoomScale, input.maxZoomScale);
    plan.shouldResetOffset = plan.zoomScale === input.minZoomScale;
    return plan;
  }

  public buildPinchEndPlan(input: MangaWebtoonPinchEndInput): MangaWebtoonPinchEndPlan {
    const plan: MangaWebtoonPinchEndPlan = new MangaWebtoonPinchEndPlan();
    plan.zoomScale = input.zoomScale;
    if (input.zoomScale < input.minZoomScale + 0.1) {
      plan.shouldSnapToMin = true;
      plan.zoomScale = input.minZoomScale;
      plan.offsetX = 0;
      plan.offsetY = 0;
    }
    return plan;
  }

  private clamp(value: number, minValue: number, maxValue: number): number {
    return Math.max(minValue, Math.min(maxValue, value));
  }
}
