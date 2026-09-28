import {
  SourceEditorDraft,
  SourceEditorVersionSnapshot
} from './SourceEditorTypes';

const MAX_SNAPSHOT_COUNT: number = 30;

export class SourceDraftStore {
  private static instance: SourceDraftStore | null = null;
  private drafts: Map<string, SourceEditorDraft> = new Map<string, SourceEditorDraft>();
  private snapshots: Map<string, SourceEditorVersionSnapshot[]> = new Map<string, SourceEditorVersionSnapshot[]>();

  private constructor() {}

  public static getInstance(): SourceDraftStore {
    if (!SourceDraftStore.instance) {
      SourceDraftStore.instance = new SourceDraftStore();
    }
    return SourceDraftStore.instance;
  }

  public saveDraft(draft: SourceEditorDraft): void {
    draft.updateTime = Date.now();
    this.drafts.set(draft.draftId, draft);
  }

  public getDraft(draftId: string): SourceEditorDraft | null {
    const draft = this.drafts.get(draftId);
    return draft ? draft : null;
  }

  public createSnapshot(draft: SourceEditorDraft, reason: string): SourceEditorVersionSnapshot {
    const snapshot: SourceEditorVersionSnapshot = {
      snapshotId: `snapshot_${Date.now()}_${Math.floor(Math.random() * 1000000)}`,
      draftId: draft.draftId,
      sourceId: draft.sourceId,
      sourcePkg: draft.sourcePkg,
      sourceName: draft.sourceName,
      configJson: draft.configJson,
      createdAt: Date.now(),
      reason: reason
    };
    let list = this.snapshots.get(draft.draftId);
    if (!list) {
      list = [];
      this.snapshots.set(draft.draftId, list);
    }
    list.unshift(snapshot);
    while (list.length > MAX_SNAPSHOT_COUNT) {
      list.pop();
    }
    return snapshot;
  }

  public listSnapshots(draftId: string): SourceEditorVersionSnapshot[] {
    const list = this.snapshots.get(draftId);
    return list ? list.slice() : [];
  }

  public rollbackSnapshot(draftId: string, snapshotId: string): SourceEditorDraft | null {
    const draft = this.getDraft(draftId);
    const list = this.snapshots.get(draftId);
    if (!draft || !list) {
      return null;
    }
    for (let i = 0; i < list.length; i++) {
      const snapshot = list[i];
      if (snapshot.snapshotId === snapshotId) {
        draft.configJson = snapshot.configJson;
        draft.updateTime = Date.now();
        this.saveDraft(draft);
        return draft;
      }
    }
    return null;
  }
}

export const sourceDraftStore = SourceDraftStore.getInstance();
