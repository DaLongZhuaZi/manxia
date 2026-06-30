import type { SourceDetailParams } from '../../pages/SourceDetailPage';
import { window } from '@kit.ArkUI';

const TAG_PREFIX: string = 'source_detail';

export class SourceDetailAbilityWindowPayload {
  public windowId: number = -1;
  public instanceId: string = '';
  public params: SourceDetailParams | null = null;
  public windowHandle: window.Window | null = null;
}

export class SourceDetailAbilityParamStore {
  private static instance: SourceDetailAbilityParamStore | null = null;
  private paramsMap: Map<string, SourceDetailParams> = new Map<string, SourceDetailParams>();
  private windowPayloadMap: Map<number, SourceDetailAbilityWindowPayload> =
    new Map<number, SourceDetailAbilityWindowPayload>();
  private windowHandleMap: Map<string, window.Window> = new Map<string, window.Window>();
  private pendingPayloads: SourceDetailAbilityWindowPayload[] = [];
  private sequence: number = 0;

  private constructor() {}

  public static getInstance(): SourceDetailAbilityParamStore {
    if (SourceDetailAbilityParamStore.instance === null) {
      SourceDetailAbilityParamStore.instance = new SourceDetailAbilityParamStore();
    }
    return SourceDetailAbilityParamStore.instance;
  }

  public register(params: SourceDetailParams): string {
    this.sequence = this.sequence + 1;
    const instanceId: string = `${TAG_PREFIX}_${Date.now()}_${this.sequence}`;
    this.paramsMap.set(instanceId, params);
    return instanceId;
  }

  public getParams(instanceId: string): SourceDetailParams | null {
    if (instanceId.length <= 0) {
      return null;
    }
    const params = this.paramsMap.get(instanceId);
    return params ? params : null;
  }

  public bindWindowPayload(
    windowId: number,
    instanceId: string,
    params: SourceDetailParams | null,
    windowHandle: window.Window | null = null
  ): void {
    const payload = new SourceDetailAbilityWindowPayload();
    payload.windowId = windowId;
    payload.instanceId = instanceId;
    payload.params = params;
    payload.windowHandle = windowHandle;

    if (windowId >= 0) {
      this.windowPayloadMap.set(windowId, payload);
    }
    if (instanceId.length > 0 && windowHandle) {
      this.windowHandleMap.set(instanceId, windowHandle);
    }
    this.pendingPayloads.push(payload);
  }

  public getWindowHandle(instanceId: string): window.Window | null {
    if (instanceId.length <= 0) {
      return null;
    }
    const windowHandle = this.windowHandleMap.get(instanceId);
    return windowHandle ? windowHandle : null;
  }

  public resolveWindowPayload(windowId: number): SourceDetailAbilityWindowPayload | null {
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

  public consumePendingPayload(): SourceDetailAbilityWindowPayload | null {
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
    this.windowHandleMap.delete(instanceId);
  }

  private removeWindowPayload(instanceId: string): void {
    const keys: number[] = [];
    this.windowPayloadMap.forEach((payload: SourceDetailAbilityWindowPayload, windowId: number): void => {
      if (payload.instanceId === instanceId) {
        keys.push(windowId);
      }
    });

    for (let index = 0; index < keys.length; index++) {
      this.windowPayloadMap.delete(keys[index]);
    }

    for (let index = this.pendingPayloads.length - 1; index >= 0; index--) {
      if (this.pendingPayloads[index].instanceId === instanceId) {
        this.pendingPayloads.splice(index, 1);
      }
    }
  }

  private removePendingPayload(windowId: number, instanceId: string): void {
    for (let index = this.pendingPayloads.length - 1; index >= 0; index--) {
      const payload = this.pendingPayloads[index];
      if (payload.windowId === windowId || payload.instanceId === instanceId) {
        this.pendingPayloads.splice(index, 1);
      }
    }
  }
}
