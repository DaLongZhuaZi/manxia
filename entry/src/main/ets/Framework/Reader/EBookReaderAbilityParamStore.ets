import type { EBookReaderParams } from '../../pages/EBookReaderRouteTypes';

const TAG_PREFIX: string = 'ebook_reader';

export class EBookReaderAbilityWindowPayload {
  public windowId: number = -1;
  public instanceId: string = '';
  public params: EBookReaderParams | null = null;
}

export class EBookReaderAbilityParamStore {
  private static instance: EBookReaderAbilityParamStore | null = null;
  private paramsMap: Map<string, EBookReaderParams> = new Map<string, EBookReaderParams>();
  private windowPayloadMap: Map<number, EBookReaderAbilityWindowPayload> =
    new Map<number, EBookReaderAbilityWindowPayload>();
  private pendingPayloads: EBookReaderAbilityWindowPayload[] = [];
  private sequence: number = 0;

  private constructor() {}

  public static getInstance(): EBookReaderAbilityParamStore {
    if (EBookReaderAbilityParamStore.instance === null) {
      EBookReaderAbilityParamStore.instance = new EBookReaderAbilityParamStore();
    }
    return EBookReaderAbilityParamStore.instance;
  }

  public register(params: EBookReaderParams): string {
    this.sequence = this.sequence + 1;
    const instanceId: string = `${TAG_PREFIX}_${Date.now()}_${this.sequence}`;
    this.paramsMap.set(instanceId, params);
    return instanceId;
  }

  public getParams(instanceId: string): EBookReaderParams | null {
    if (instanceId.length <= 0) {
      return null;
    }
    const params = this.paramsMap.get(instanceId);
    return params ? params : null;
  }

  public bindWindowPayload(windowId: number, instanceId: string, params: EBookReaderParams | null): void {
    const payload = new EBookReaderAbilityWindowPayload();
    payload.windowId = windowId;
    payload.instanceId = instanceId;
    payload.params = params;

    if (windowId >= 0) {
      this.windowPayloadMap.set(windowId, payload);
    }
    this.pendingPayloads.push(payload);
  }

  public resolveWindowPayload(windowId: number): EBookReaderAbilityWindowPayload | null {
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

  public consumePendingPayload(): EBookReaderAbilityWindowPayload | null {
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
    this.windowPayloadMap.forEach((payload: EBookReaderAbilityWindowPayload, windowId: number): void => {
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
