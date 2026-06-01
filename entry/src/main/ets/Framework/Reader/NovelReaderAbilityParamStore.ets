import type { NovelReaderPageParams } from '../../pages/NovelBookshelfPage';

const TAG_PREFIX: string = 'novel_reader';

export class NovelReaderAbilityWindowPayload {
  public windowId: number = -1;
  public instanceId: string = '';
  public params: NovelReaderPageParams | null = null;
}

export class NovelReaderAbilityParamStore {
  private static instance: NovelReaderAbilityParamStore | null = null;
  private paramsMap: Map<string, NovelReaderPageParams> = new Map<string, NovelReaderPageParams>();
  private windowPayloadMap: Map<number, NovelReaderAbilityWindowPayload> =
    new Map<number, NovelReaderAbilityWindowPayload>();
  private pendingPayloads: NovelReaderAbilityWindowPayload[] = [];
  private sequence: number = 0;

  private constructor() {}

  public static getInstance(): NovelReaderAbilityParamStore {
    if (NovelReaderAbilityParamStore.instance === null) {
      NovelReaderAbilityParamStore.instance = new NovelReaderAbilityParamStore();
    }
    return NovelReaderAbilityParamStore.instance;
  }

  public register(params: NovelReaderPageParams): string {
    this.sequence = this.sequence + 1;
    const instanceId: string = `${TAG_PREFIX}_${Date.now()}_${this.sequence}`;
    this.paramsMap.set(instanceId, params);
    return instanceId;
  }

  public getParams(instanceId: string): NovelReaderPageParams | null {
    if (instanceId.length <= 0) {
      return null;
    }
    const params = this.paramsMap.get(instanceId);
    return params ? params : null;
  }

  public bindWindowPayload(windowId: number, instanceId: string, params: NovelReaderPageParams | null): void {
    const payload = new NovelReaderAbilityWindowPayload();
    payload.windowId = windowId;
    payload.instanceId = instanceId;
    payload.params = params;

    if (windowId >= 0) {
      this.windowPayloadMap.set(windowId, payload);
    }
    this.pendingPayloads.push(payload);
  }

  public resolveWindowPayload(windowId: number): NovelReaderAbilityWindowPayload | null {
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

  public consumePendingPayload(): NovelReaderAbilityWindowPayload | null {
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
  }

  private removeWindowPayload(instanceId: string): void {
    const keys: number[] = [];
    this.windowPayloadMap.forEach((payload: NovelReaderAbilityWindowPayload, windowId: number): void => {
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
}
