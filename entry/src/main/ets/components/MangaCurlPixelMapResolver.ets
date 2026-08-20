// Responsibility: resolve curl PixelMap slots and readiness without owning PixelMap objects.

import { ReadingDirection } from 'manxia_core/src/main/ets/Models/MangaModels';

export enum MangaCurlPixelMapSlot {
  CURRENT = 'current',
  TARGET = 'target',
  CURRENT_LEFT = 'current_left',
  CURRENT_RIGHT = 'current_right',
  TARGET_LEFT = 'target_left',
  TARGET_RIGHT = 'target_right'
}

export class MangaCurlPixelMapSlotRequest {
  public slot: MangaCurlPixelMapSlot = MangaCurlPixelMapSlot.CURRENT;
  public pageIndex: number = -1;
  public requiredForAnimation: boolean = false;
}

export class MangaCurlSinglePixelMapInput {
  public currentPageIndex: number = 0;
  public targetPageIndex: number = -1;
  public pageCount: number = 0;
  public hasCurrentPixelMap: boolean = false;
  public hasTargetPixelMap: boolean = false;
}

export class MangaCurlSinglePixelMapPlan {
  public shouldRun: boolean = false;
  public currentRequest: MangaCurlPixelMapSlotRequest = new MangaCurlPixelMapSlotRequest();
  public targetRequest: MangaCurlPixelMapSlotRequest = new MangaCurlPixelMapSlotRequest();
  public currentReady: boolean = false;
  public targetReady: boolean = false;
  public canStartCurl: boolean = false;
  public shouldLoadCurrent: boolean = false;
  public shouldLoadTarget: boolean = false;
  public shouldFallback: boolean = false;
}

export class MangaCurlDualPixelMapInput {
  public currentPairStart: number = 0;
  public targetPairStart: number = -1;
  public pageCount: number = 0;
  public readingDirection: ReadingDirection = ReadingDirection.LEFT_TO_RIGHT;
  public isForward: boolean = true;
  public hasCurrentLeft: boolean = false;
  public hasCurrentRight: boolean = false;
  public hasTargetLeft: boolean = false;
  public hasTargetRight: boolean = false;
}

export class MangaCurlDualPixelMapPlan {
  public shouldRun: boolean = false;
  public requests: MangaCurlPixelMapSlotRequest[] = [];
  public currentLeftIndex: number = -1;
  public currentRightIndex: number = -1;
  public targetLeftIndex: number = -1;
  public targetRightIndex: number = -1;
  public turningSlot: MangaCurlPixelMapSlot = MangaCurlPixelMapSlot.CURRENT_RIGHT;
  public turningPageIndex: number = -1;
  public turningReady: boolean = false;
  public canStartCurl: boolean = false;
  public missingRequiredCount: number = 0;
}

export class MangaCurlPixelMapResolver {
  public buildSinglePlan(input: MangaCurlSinglePixelMapInput): MangaCurlSinglePixelMapPlan {
    const plan: MangaCurlSinglePixelMapPlan = new MangaCurlSinglePixelMapPlan();
    plan.shouldRun = input.pageCount > 0 &&
      input.currentPageIndex >= 0 &&
      input.currentPageIndex < input.pageCount &&
      input.targetPageIndex >= 0 &&
      input.targetPageIndex < input.pageCount;
    plan.currentRequest = this.createRequest(MangaCurlPixelMapSlot.CURRENT, input.currentPageIndex, true);
    plan.targetRequest = this.createRequest(MangaCurlPixelMapSlot.TARGET, input.targetPageIndex, false);
    plan.currentReady = input.hasCurrentPixelMap;
    plan.targetReady = input.hasTargetPixelMap;
    plan.canStartCurl = plan.shouldRun && plan.currentReady;
    plan.shouldLoadCurrent = plan.shouldRun && !plan.currentReady;
    plan.shouldLoadTarget = plan.shouldRun && !plan.targetReady;
    plan.shouldFallback = plan.shouldRun && !plan.currentReady;
    return plan;
  }

  public buildDualPlan(input: MangaCurlDualPixelMapInput): MangaCurlDualPixelMapPlan {
    const plan: MangaCurlDualPixelMapPlan = new MangaCurlDualPixelMapPlan();
    plan.shouldRun = input.pageCount > 0 &&
      input.currentPairStart >= 0 &&
      input.currentPairStart < input.pageCount &&
      input.targetPairStart >= 0 &&
      input.targetPairStart < input.pageCount;
    this.fillDualIndices(input, plan);
    plan.turningSlot = input.isForward
      ? MangaCurlPixelMapSlot.CURRENT_RIGHT
      : MangaCurlPixelMapSlot.CURRENT_LEFT;
    plan.turningPageIndex = input.isForward ? plan.currentRightIndex : plan.currentLeftIndex;
    plan.turningReady = this.isSlotReady(plan.turningSlot, input);
    plan.canStartCurl = plan.shouldRun && plan.turningReady;
    plan.missingRequiredCount = plan.canStartCurl ? 0 : 1;
    plan.requests = this.createDualRequests(plan);
    return plan;
  }

  private fillDualIndices(input: MangaCurlDualPixelMapInput, plan: MangaCurlDualPixelMapPlan): void {
    const total: number = input.pageCount;
    if (input.readingDirection === ReadingDirection.RIGHT_TO_LEFT) {
      plan.currentRightIndex = input.currentPairStart;
      plan.currentLeftIndex = input.currentPairStart + 1 < total ? input.currentPairStart + 1 : -1;
      plan.targetRightIndex = input.targetPairStart;
      plan.targetLeftIndex = input.targetPairStart + 1 < total ? input.targetPairStart + 1 : -1;
      return;
    }
    plan.currentLeftIndex = input.currentPairStart;
    plan.currentRightIndex = input.currentPairStart + 1 < total ? input.currentPairStart + 1 : -1;
    plan.targetLeftIndex = input.targetPairStart;
    plan.targetRightIndex = input.targetPairStart + 1 < total ? input.targetPairStart + 1 : -1;
  }

  private createDualRequests(plan: MangaCurlDualPixelMapPlan): MangaCurlPixelMapSlotRequest[] {
    const requests: MangaCurlPixelMapSlotRequest[] = new Array<MangaCurlPixelMapSlotRequest>();
    requests.push(this.createRequest(
      MangaCurlPixelMapSlot.CURRENT_LEFT,
      plan.currentLeftIndex,
      plan.turningSlot === MangaCurlPixelMapSlot.CURRENT_LEFT
    ));
    requests.push(this.createRequest(
      MangaCurlPixelMapSlot.CURRENT_RIGHT,
      plan.currentRightIndex,
      plan.turningSlot === MangaCurlPixelMapSlot.CURRENT_RIGHT
    ));
    requests.push(this.createRequest(MangaCurlPixelMapSlot.TARGET_LEFT, plan.targetLeftIndex, false));
    requests.push(this.createRequest(MangaCurlPixelMapSlot.TARGET_RIGHT, plan.targetRightIndex, false));
    return requests;
  }

  private createRequest(
    slot: MangaCurlPixelMapSlot,
    pageIndex: number,
    requiredForAnimation: boolean
  ): MangaCurlPixelMapSlotRequest {
    const request: MangaCurlPixelMapSlotRequest = new MangaCurlPixelMapSlotRequest();
    request.slot = slot;
    request.pageIndex = pageIndex;
    request.requiredForAnimation = requiredForAnimation;
    return request;
  }

  private isSlotReady(slot: MangaCurlPixelMapSlot, input: MangaCurlDualPixelMapInput): boolean {
    if (slot === MangaCurlPixelMapSlot.CURRENT_LEFT) {
      return input.hasCurrentLeft;
    }
    if (slot === MangaCurlPixelMapSlot.CURRENT_RIGHT) {
      return input.hasCurrentRight;
    }
    if (slot === MangaCurlPixelMapSlot.TARGET_LEFT) {
      return input.hasTargetLeft;
    }
    if (slot === MangaCurlPixelMapSlot.TARGET_RIGHT) {
      return input.hasTargetRight;
    }
    return false;
  }
}
