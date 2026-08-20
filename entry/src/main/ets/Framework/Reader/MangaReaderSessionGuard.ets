import { MangaPage } from 'manxia_core/src/main/ets/Models/MangaModels';

export class MangaReaderSessionSnapshot {
  public version: number = 0;
  public chapterId: string = '';
  public reason: string = '';
  public timestamp: number = 0;
}

export class MangaReaderSessionGuard {
  private version: number = 0;
  private chapterId: string = '';
  private invalidationReason: string = '';
  private updatedAt: number = 0;

  public resetForChapter(chapterId: string, reason: string): MangaReaderSessionSnapshot {
    this.version++;
    this.chapterId = chapterId;
    this.invalidationReason = reason;
    this.updatedAt = Date.now();
    return this.capture();
  }

  public capture(): MangaReaderSessionSnapshot {
    const snapshot: MangaReaderSessionSnapshot = new MangaReaderSessionSnapshot();
    snapshot.version = this.version;
    snapshot.chapterId = this.chapterId;
    snapshot.reason = this.invalidationReason;
    snapshot.timestamp = this.updatedAt;
    return snapshot;
  }

  public isCurrent(snapshot: MangaReaderSessionSnapshot): boolean {
    return snapshot.version === this.version && snapshot.chapterId === this.chapterId;
  }

  public describePage(page: MangaPage): string {
    return `session=${this.version}, chapter=${this.chapterId}, page=${page.id}`;
  }
}
