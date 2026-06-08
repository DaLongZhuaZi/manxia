import { ContinuationTriggeredPayload } from '../EventBus';

const TAG_PREFIX: string = 'remote_control';

export class RemoteControlAbilityWindowPayload {
  public windowId: number = -1;
  public instanceId: string = '';
  public params: ContinuationTriggeredPayload | null = null;
}

export class RemoteControlAbilityParamStore {
  private static instance: RemoteControlAbilityParamStore | null = null;
  private paramsMap: Map<string, ContinuationTriggeredPayload> = new Map<string, ContinuationTriggeredPayload>();
  private windowPayloadMap: Map<number, RemoteControlAbilityWindowPayload> =
    new Map<number, RemoteControlAbilityWindowPayload>();
  private pendingPayloads: RemoteControlAbilityWindowPayload[] = [];
  private activeInstanceId: string = '';
  private sequence: number = 0;

  private constructor() {}

  public static getInstance(): RemoteControlAbilityParamStore {
    if (RemoteControlAbilityParamStore.instance === null) {
      RemoteControlAbilityParamStore.instance = new RemoteControlAbilityParamStore();
    }
    return RemoteControlAbilityParamStore.instance;
  }

  public register(params: ContinuationTriggeredPayload): string {
    this.sequence = this.sequence + 1;
    const instanceId: string = `${TAG_PREFIX}_${Date.now()}_${this.sequence}`;
    this.paramsMap.set(instanceId, this.cloneParams(params));
    this.activeInstanceId = instanceId;
    return instanceId;
  }

  public replaceParams(instanceId: string, params: ContinuationTriggeredPayload): void {
    if (instanceId.length <= 0) {
      return;
    }
    this.paramsMap.set(instanceId, this.cloneParams(params));
    this.activeInstanceId = instanceId;
  }

  public getActiveInstanceId(): string {
    return this.activeInstanceId;
  }

  public getParams(instanceId: string): ContinuationTriggeredPayload | null {
    if (instanceId.length <= 0) {
      return null;
    }
    const params = this.paramsMap.get(instanceId);
    return params ? this.cloneParams(params) : null;
  }

  public bindWindowPayload(windowId: number, instanceId: string, params: ContinuationTriggeredPayload | null): void {
    const payload = new RemoteControlAbilityWindowPayload();
    payload.windowId = windowId;
    payload.instanceId = instanceId;
    payload.params = params ? this.cloneParams(params) : null;

    if (windowId >= 0) {
      this.windowPayloadMap.set(windowId, payload);
    }
    this.pendingPayloads.push(payload);
  }

  public resolveWindowPayload(windowId: number): RemoteControlAbilityWindowPayload | null {
    if (windowId < 0) {
      return null;
    }
    const payload = this.windowPayloadMap.get(windowId);
    if (!payload) {
      return null;
    }
    this.removePendingPayload(windowId, payload.instanceId);
    return payload;
  }

  public consumePendingPayload(): RemoteControlAbilityWindowPayload | null {
    if (this.pendingPayloads.length <= 0) {
      return null;
    }
    const payload = this.pendingPayloads.shift();
    return payload ? payload : null;
  }

  public remove(instanceId: string): void {
    if (instanceId.length <= 0) {
      return;
    }
    this.paramsMap.delete(instanceId);
    this.removeWindowPayload(instanceId);
    if (this.activeInstanceId === instanceId) {
      this.activeInstanceId = '';
    }
  }

  private removeWindowPayload(instanceId: string): void {
    const keys: number[] = [];
    this.windowPayloadMap.forEach((payload: RemoteControlAbilityWindowPayload, windowId: number): void => {
      if (payload.instanceId === instanceId) {
        keys.push(windowId);
      }
    });
    for (let i = 0; i < keys.length; i++) {
      this.windowPayloadMap.delete(keys[i]);
    }

    for (let i = this.pendingPayloads.length - 1; i >= 0; i--) {
      if (this.pendingPayloads[i].instanceId === instanceId) {
        this.pendingPayloads.splice(i, 1);
      }
    }
  }

  private removePendingPayload(windowId: number, instanceId: string): void {
    for (let i = this.pendingPayloads.length - 1; i >= 0; i--) {
      const payload = this.pendingPayloads[i];
      if (payload.windowId === windowId || payload.instanceId === instanceId) {
        this.pendingPayloads.splice(i, 1);
      }
    }
  }

  private cloneParams(params: ContinuationTriggeredPayload): ContinuationTriggeredPayload {
    return new ContinuationTriggeredPayload(
      params.sessionId,
      params.bookId,
      params.chapterIndex,
      params.pageIndex,
      params.offset,
      params.sourceType,
      params.isLocal
    );
  }
}
