import { ExternalFileTaskFactory, ExternalFileTaskParams } from './ExternalFileTaskTypes';

const TAG_PREFIX: string = 'external_file_task';

export class ExternalFileTaskWindowPayload {
  public windowId: number = -1;
  public instanceId: string = '';
  public params: ExternalFileTaskParams | null = null;
}

export class ExternalFileTaskParamStore {
  private static instance: ExternalFileTaskParamStore | null = null;
  private paramsMap: Map<string, ExternalFileTaskParams> = new Map<string, ExternalFileTaskParams>();
  private windowPayloadMap: Map<number, ExternalFileTaskWindowPayload> =
    new Map<number, ExternalFileTaskWindowPayload>();
  private pendingPayloads: ExternalFileTaskWindowPayload[] = [];
  private activeInstanceId: string = '';
  private backupRestoreLockInstanceId: string = '';
  private sequence: number = 0;

  private constructor() {}

  public static getInstance(): ExternalFileTaskParamStore {
    if (ExternalFileTaskParamStore.instance === null) {
      ExternalFileTaskParamStore.instance = new ExternalFileTaskParamStore();
    }
    return ExternalFileTaskParamStore.instance;
  }

  public register(params: ExternalFileTaskParams): string {
    this.sequence = this.sequence + 1;
    const instanceId: string = `${TAG_PREFIX}_${Date.now()}_${this.sequence}`;
    const storedParams = ExternalFileTaskFactory.withInstanceId(params, instanceId);
    this.paramsMap.set(instanceId, storedParams);
    this.activeInstanceId = instanceId;
    return instanceId;
  }

  public replaceParams(instanceId: string, params: ExternalFileTaskParams): void {
    if (instanceId.length <= 0) {
      return;
    }
    const storedParams = ExternalFileTaskFactory.withInstanceId(params, instanceId);
    this.paramsMap.set(instanceId, storedParams);
    this.activeInstanceId = instanceId;
  }

  public getActiveInstanceId(): string {
    return this.activeInstanceId;
  }

  public getParams(instanceId: string): ExternalFileTaskParams | null {
    if (instanceId.length <= 0) {
      return null;
    }
    const params = this.paramsMap.get(instanceId);
    return params ? ExternalFileTaskFactory.clone(params) : null;
  }

  public bindWindowPayload(windowId: number, instanceId: string, params: ExternalFileTaskParams | null): void {
    const payload = new ExternalFileTaskWindowPayload();
    payload.windowId = windowId;
    payload.instanceId = instanceId;
    payload.params = params ? ExternalFileTaskFactory.clone(params) : null;

    if (windowId >= 0) {
      this.windowPayloadMap.set(windowId, payload);
    }
    this.pendingPayloads.push(payload);
  }

  public resolveWindowPayload(windowId: number): ExternalFileTaskWindowPayload | null {
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

  public consumePendingPayload(): ExternalFileTaskWindowPayload | null {
    if (this.pendingPayloads.length <= 0) {
      return null;
    }
    const payload = this.pendingPayloads.shift();
    return payload ? payload : null;
  }

  public acquireBackupRestoreLock(instanceId: string): boolean {
    if (instanceId.length <= 0) {
      return false;
    }
    if (this.backupRestoreLockInstanceId.length > 0 && this.backupRestoreLockInstanceId !== instanceId) {
      return false;
    }
    this.backupRestoreLockInstanceId = instanceId;
    return true;
  }

  public releaseBackupRestoreLock(instanceId: string): void {
    if (this.backupRestoreLockInstanceId === instanceId) {
      this.backupRestoreLockInstanceId = '';
    }
  }

  public getBackupRestoreLockInstanceId(): string {
    return this.backupRestoreLockInstanceId;
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
    this.releaseBackupRestoreLock(instanceId);
  }

  private removeWindowPayload(instanceId: string): void {
    const keys: number[] = [];
    this.windowPayloadMap.forEach((payload: ExternalFileTaskWindowPayload, windowId: number): void => {
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
