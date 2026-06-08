import { FileEditorOpenParams } from './FileEditorService';

const TAG_PREFIX: string = 'file_editor';

export class FileEditorAbilityWindowPayload {
  public windowId: number = -1;
  public instanceId: string = '';
  public params: FileEditorOpenParams | null = null;
}

export class FileEditorAbilityParamStore {
  private static instance: FileEditorAbilityParamStore | null = null;
  private paramsMap: Map<string, FileEditorOpenParams> = new Map<string, FileEditorOpenParams>();
  private windowPayloadMap: Map<number, FileEditorAbilityWindowPayload> = new Map<number, FileEditorAbilityWindowPayload>();
  private pendingPayloads: FileEditorAbilityWindowPayload[] = [];
  private sequence: number = 0;

  private constructor() {}

  public static getInstance(): FileEditorAbilityParamStore {
    if (FileEditorAbilityParamStore.instance === null) {
      FileEditorAbilityParamStore.instance = new FileEditorAbilityParamStore();
    }
    return FileEditorAbilityParamStore.instance;
  }

  public register(params: FileEditorOpenParams): string {
    this.sequence = this.sequence + 1;
    const instanceId: string = params.instanceId && params.instanceId.length > 0
      ? params.instanceId
      : `${TAG_PREFIX}_${Date.now()}_${this.sequence}`;
    const storedParams: FileEditorOpenParams = {
      instanceId: instanceId,
      sessionId: params.sessionId ?? instanceId,
      hostMode: params.hostMode,
      filePath: params.filePath,
      content: params.content,
      language: params.language,
      readOnly: params.readOnly,
      title: params.title,
      origin: params.origin,
      saveTarget: params.saveTarget
    };
    this.paramsMap.set(instanceId, storedParams);
    return instanceId;
  }

  public getParams(instanceId: string): FileEditorOpenParams | null {
    if (instanceId.length <= 0) {
      return null;
    }
    const params = this.paramsMap.get(instanceId);
    return params ? params : null;
  }

  public bindWindowPayload(windowId: number, instanceId: string, params: FileEditorOpenParams | null): void {
    const payload = new FileEditorAbilityWindowPayload();
    payload.windowId = windowId;
    payload.instanceId = instanceId;
    payload.params = params;

    if (windowId >= 0) {
      this.windowPayloadMap.set(windowId, payload);
    }
    this.pendingPayloads.push(payload);
  }

  public resolveWindowPayload(windowId: number): FileEditorAbilityWindowPayload | null {
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

  public consumePendingPayload(): FileEditorAbilityWindowPayload | null {
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
    this.windowPayloadMap.forEach((payload: FileEditorAbilityWindowPayload, windowId: number): void => {
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
