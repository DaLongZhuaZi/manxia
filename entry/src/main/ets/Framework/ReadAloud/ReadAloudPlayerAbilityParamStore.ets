import type { NovelReaderPageParams } from '../../pages/NovelBookshelfPage';
import type { DisplayMode } from 'manxia_theme/src/main/ets/Utils/WindowManager';

const TAG_PREFIX: string = 'read_aloud_player';

export class ReadAloudPlayerAbilityParams {
  public returnHostPage: string = '';
  public returnDisplayMode: DisplayMode | null = null;
  public launchParams: NovelReaderPageParams | null = null;
}

export class ReadAloudPlayerAbilityWindowPayload {
  public windowId: number = -1;
  public instanceId: string = '';
  public params: ReadAloudPlayerAbilityParams | null = null;
}

export class ReadAloudPlayerAbilityParamStore {
  private static instance: ReadAloudPlayerAbilityParamStore | null = null;
  private paramsMap: Map<string, ReadAloudPlayerAbilityParams> = new Map<string, ReadAloudPlayerAbilityParams>();
  private windowPayloadMap: Map<number, ReadAloudPlayerAbilityWindowPayload> =
    new Map<number, ReadAloudPlayerAbilityWindowPayload>();
  private pendingPayloads: ReadAloudPlayerAbilityWindowPayload[] = [];
  private activeInstanceId: string = '';
  private sequence: number = 0;

  private constructor() {}

  public static getInstance(): ReadAloudPlayerAbilityParamStore {
    if (ReadAloudPlayerAbilityParamStore.instance === null) {
      ReadAloudPlayerAbilityParamStore.instance = new ReadAloudPlayerAbilityParamStore();
    }
    return ReadAloudPlayerAbilityParamStore.instance;
  }

  public register(params: ReadAloudPlayerAbilityParams): string {
    this.sequence = this.sequence + 1;
    const instanceId: string = `${TAG_PREFIX}_${Date.now()}_${this.sequence}`;
    this.paramsMap.set(instanceId, params);
    this.activeInstanceId = instanceId;
    return instanceId;
  }

  public getActiveInstanceId(): string {
    return this.activeInstanceId;
  }

  public getParams(instanceId: string): ReadAloudPlayerAbilityParams | null {
    if (instanceId.length <= 0) {
      return null;
    }
    const params = this.paramsMap.get(instanceId);
    return params ? params : null;
  }

  public bindWindowPayload(windowId: number, instanceId: string, params: ReadAloudPlayerAbilityParams | null): void {
    const payload = new ReadAloudPlayerAbilityWindowPayload();
    payload.windowId = windowId;
    payload.instanceId = instanceId;
    payload.params = params;

    if (windowId >= 0) {
      this.windowPayloadMap.set(windowId, payload);
    }
    this.pendingPayloads.push(payload);
  }

  public resolveWindowPayload(windowId: number): ReadAloudPlayerAbilityWindowPayload | null {
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

  public consumePendingPayload(): ReadAloudPlayerAbilityWindowPayload | null {
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
    this.windowPayloadMap.forEach((payload: ReadAloudPlayerAbilityWindowPayload, windowId: number): void => {
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
