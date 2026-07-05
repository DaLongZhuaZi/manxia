import { logger } from '../../Utils/Logger';
import {
  ChapterInfo,
  ComicInfo,
  DataManager,
  OnlineChapterInfo,
  OnlineComicInfo
} from '../Data/DataManager';
import { DatabaseManager } from '../Database/DatabaseManager';
import { DatabaseValue, GenericQueryRecord } from '../Database/DatabaseTypes';
import { MangaStatus } from '../Types/StatusEnums';

const TAG = 'MangaIdentityResolver';

export enum MangaIdentityContentHint {
  UNKNOWN = 'unknown',
  LOCAL = 'local',
  ONLINE = 'online'
}

export class MangaIdentityResolveInput {
  public mangaId: string = '';
  public chapterId: string = '';
  public sourceId: number = -1;
  public contentType: string = '';
  public sourceName: string = '';
  public sourcePkg: string = '';
  public caller: string = '';
}

export class MangaIdentityResolveResult {
  public success: boolean = false;
  public inputMangaId: string = '';
  public inputChapterId: string = '';
  public canonicalMangaId: string = '';
  public canonicalChapterId: string = '';
  public externalMangaId: string = '';
  public externalChapterId: string = '';
  public sourceId: number = -1;
  public sourceName: string = '';
  public sourcePkg: string = '';
  public contentHint: MangaIdentityContentHint = MangaIdentityContentHint.UNKNOWN;
  public reason: string = '';
  public detail: string = '';
  public comicInfo: ComicInfo | null = null;
  public onlineComicInfo: OnlineComicInfo | null = null;
  public chapterInfo: ChapterInfo | null = null;
  public onlineChapterInfo: OnlineChapterInfo | null = null;
}

class ResolvedLocalChapterRow {
  public id: string = '';
  public comicId: string = '';
  public externalId: string = '';
  public title: string = '';
  public chapterNumber: number = 0;
  public pageCount: number = 0;
  public isDownloaded: boolean = false;
  public downloadPath: string = '';
  public publishTime: number = 0;
  public addTime: number = 0;
}

class ResolvedOnlineChapterRow {
  public id: string = '';
  public comicId: string = '';
  public externalId: string = '';
  public title: string = '';
  public chapterNumber: number = 0;
  public url: string = '';
  public pageCount: number = 0;
  public publishTime: number = 0;
  public addTime: number = 0;
  public createTime: number = 0;
  public updateTime: number = 0;
  public isDownloaded: boolean = false;
  public downloadPath: string = '';
}

export class MangaIdentityResolver {
  private static instance: MangaIdentityResolver | null = null;

  private dataManager: DataManager = DataManager.getInstance();
  private databaseManager: DatabaseManager = DatabaseManager.getInstance();

  private constructor() {}

  public static getInstance(): MangaIdentityResolver {
    if (MangaIdentityResolver.instance === null) {
      MangaIdentityResolver.instance = new MangaIdentityResolver();
    }
    return MangaIdentityResolver.instance;
  }

  public async resolve(input: MangaIdentityResolveInput): Promise<MangaIdentityResolveResult> {
    const result: MangaIdentityResolveResult = new MangaIdentityResolveResult();
    result.inputMangaId = this.normalizeId(input.mangaId);
    result.inputChapterId = this.normalizeId(input.chapterId);
    result.sourceId = input.sourceId;
    result.sourceName = input.sourceName;
    result.sourcePkg = input.sourcePkg;
    result.contentHint = this.resolveContentHint(input);

    try {
      await this.resolveByChapterId(result);
      await this.resolveByMangaId(result);
      await this.resolveChapterWithinResolvedManga(result);

      if (result.canonicalMangaId.length > 0) {
        result.success = true;
        if (result.reason.length === 0) {
          result.reason = 'resolved';
        }
        result.detail = this.buildDetail(result);
        logger.info(TAG, `漫画身份解析成功: caller=${input.caller}, ${result.detail}`);
        return result;
      }

      result.success = false;
      result.reason = 'not_found';
      result.detail = this.buildDetail(result);
      logger.warn(TAG, `漫画身份解析失败: caller=${input.caller}, ${result.detail}`);
      return result;
    } catch (error) {
      result.success = false;
      result.reason = 'error';
      result.detail = `inputMangaId=${result.inputMangaId}, inputChapterId=${result.inputChapterId}, error=${String(error)}`;
      logger.error(TAG, `漫画身份解析异常: caller=${input.caller}`, String(error));
      return result;
    }
  }

  public buildInput(
    mangaId: string,
    chapterId: string,
    sourceId: number,
    contentType: string,
    caller: string
  ): MangaIdentityResolveInput {
    const input: MangaIdentityResolveInput = new MangaIdentityResolveInput();
    input.mangaId = mangaId;
    input.chapterId = chapterId;
    input.sourceId = sourceId;
    input.contentType = contentType;
    input.caller = caller;
    return input;
  }

  private async resolveByChapterId(result: MangaIdentityResolveResult): Promise<void> {
    if (result.inputChapterId.length <= 0) {
      return;
    }

    if (this.shouldPreferOnline(result)) {
      const onlineResolved = await this.tryResolveOnlineChapter(result, result.inputChapterId);
      if (onlineResolved) {
        return;
      }
      const localResolved = await this.tryResolveLocalChapter(result, result.inputChapterId);
      if (localResolved) {
        return;
      }
      return;
    }

    const localResolved = await this.tryResolveLocalChapter(result, result.inputChapterId);
    if (localResolved) {
      return;
    }
    await this.tryResolveOnlineChapter(result, result.inputChapterId);
  }

  private async resolveByMangaId(result: MangaIdentityResolveResult): Promise<void> {
    if (result.canonicalMangaId.length > 0 || result.inputMangaId.length <= 0) {
      return;
    }

    if (this.shouldPreferOnline(result)) {
      const onlineResolved = await this.tryResolveOnlineManga(result, result.inputMangaId);
      if (onlineResolved) {
        return;
      }
      const localResolved = await this.tryResolveLocalManga(result, result.inputMangaId);
      if (localResolved) {
        return;
      }
      return;
    }

    const localResolved = await this.tryResolveLocalManga(result, result.inputMangaId);
    if (localResolved) {
      return;
    }
    await this.tryResolveOnlineManga(result, result.inputMangaId);
  }

  private async resolveChapterWithinResolvedManga(result: MangaIdentityResolveResult): Promise<void> {
    if (result.inputChapterId.length <= 0 || result.canonicalMangaId.length <= 0) {
      return;
    }
    if (result.canonicalChapterId.length > 0) {
      return;
    }

    if (result.contentHint === MangaIdentityContentHint.ONLINE) {
      const byId = await this.dataManager.getOnlineChapterById(result.inputChapterId);
      if (byId && byId.comicId === result.canonicalMangaId) {
        this.applyOnlineChapter(result, byId, 'online_chapter_by_id');
        return;
      }
      const byExternal = await this.dataManager.getOnlineChapterByExternalId(result.canonicalMangaId, result.inputChapterId);
      if (byExternal) {
        this.applyOnlineChapter(result, byExternal, 'online_chapter_by_external');
      }
      return;
    }

    const localById = await this.dataManager.getChapterById(result.inputChapterId);
    if (localById && localById.comicId === result.canonicalMangaId) {
      this.applyLocalChapter(result, localById, 'local_chapter_by_id');
      return;
    }
    const localByExternal = await this.dataManager.getChapterByExternalId(result.canonicalMangaId, result.inputChapterId);
    if (localByExternal) {
      this.applyLocalChapter(result, localByExternal, 'local_chapter_by_external');
    }
  }

  private async tryResolveLocalManga(result: MangaIdentityResolveResult, mangaId: string): Promise<boolean> {
    const directComic = await this.dataManager.getComicById(mangaId);
    const directOnline = await this.dataManager.getOnlineComicInfoById(mangaId);
    if (directComic && !directOnline) {
      this.applyLocalComic(result, directComic, 'local_manga_by_id');
      return true;
    }

    const externalRecord = await this.dataManager.getComicByExternalId(mangaId);
    if (externalRecord) {
      const row = externalRecord as GenericQueryRecord;
      const resolvedId = this.databaseValueToString(row.id);
      if (resolvedId.length > 0) {
        const comic = await this.dataManager.getComicById(resolvedId);
        if (comic) {
          this.applyLocalComic(result, comic, 'local_manga_by_external');
          return true;
        }
      }
    }
    return false;
  }

  private async tryResolveOnlineManga(result: MangaIdentityResolveResult, mangaId: string): Promise<boolean> {
    const directOnline = await this.dataManager.getOnlineComicInfoById(mangaId);
    if (directOnline) {
      this.applyOnlineComic(result, directOnline, 'online_manga_by_id');
      return true;
    }

    let externalOnline: OnlineComicInfo | null = await this.queryOnlineComicByExternalId(
      mangaId,
      result.sourceId,
      result.sourcePkg,
      result.sourceName
    );
    if (!externalOnline && !this.hasSourceIdentityHint(result)) {
      externalOnline = await this.dataManager.getOnlineComicByExternalId(mangaId);
    }
    if (externalOnline) {
      this.applyOnlineComic(result, externalOnline, 'online_manga_by_external');
      return true;
    }
    return false;
  }

  private hasSourceIdentityHint(result: MangaIdentityResolveResult): boolean {
    return result.sourceId > 0 || result.sourcePkg.length > 0 || result.sourceName.length > 0;
  }

  private async tryResolveLocalChapter(result: MangaIdentityResolveResult, chapterId: string): Promise<boolean> {
    const directChapter = await this.dataManager.getChapterById(chapterId);
    if (directChapter) {
      this.applyLocalChapter(result, directChapter, 'local_chapter_by_id');
      const comic = await this.dataManager.getComicById(directChapter.comicId);
      if (comic) {
        this.applyLocalComic(result, comic, 'local_manga_by_chapter');
        return true;
      }
      if (directChapter.comicId.length > 0) {
        this.applyRecoveredLocalMangaId(result, directChapter.comicId, 'local_manga_missing_by_chapter');
        return true;
      }
    }

    const externalChapter = await this.queryLocalChapterByExternalId(chapterId);
    if (externalChapter) {
      this.applyLocalChapter(result, externalChapter, 'local_chapter_by_external_global');
      const comic = await this.dataManager.getComicById(externalChapter.comicId);
      if (comic) {
        this.applyLocalComic(result, comic, 'local_manga_by_external_chapter');
        return true;
      }
      if (externalChapter.comicId.length > 0) {
        this.applyRecoveredLocalMangaId(result, externalChapter.comicId, 'local_manga_missing_by_external_chapter');
        return true;
      }
    }
    return false;
  }

  private async tryResolveOnlineChapter(result: MangaIdentityResolveResult, chapterId: string): Promise<boolean> {
    const directChapter = await this.dataManager.getOnlineChapterById(chapterId);
    if (directChapter) {
      this.applyOnlineChapter(result, directChapter, 'online_chapter_by_id');
      const comic = await this.dataManager.getOnlineComicInfoById(directChapter.comicId);
      if (comic) {
        this.applyOnlineComic(result, comic, 'online_manga_by_chapter');
        return true;
      }
    }

    const externalChapter = await this.queryOnlineChapterByExternalId(
      chapterId,
      result.sourceId,
      result.sourcePkg,
      result.sourceName
    );
    if (externalChapter) {
      this.applyOnlineChapter(result, externalChapter, 'online_chapter_by_external_global');
      const comic = await this.dataManager.getOnlineComicInfoById(externalChapter.comicId);
      if (comic) {
        this.applyOnlineComic(result, comic, 'online_manga_by_external_chapter');
        return true;
      }
    }
    return false;
  }

  private async queryLocalChapterByExternalId(externalChapterId: string): Promise<ChapterInfo | null> {
    if (externalChapterId.length <= 0) {
      return null;
    }
    const sql = `SELECT id, comicId, externalId, title, chapterNumber AS chapterIndex, pageCount, isDownloaded,
                        downloadPath, publishTime, addTime
                 FROM chapter WHERE externalId = ?
                 ORDER BY updateTime DESC LIMIT 1`;
    const records = await this.databaseManager.querySql(sql, [externalChapterId]);
    if (!records || records.length <= 0) {
      return null;
    }
    const row = this.buildLocalChapterRow(records[0] as GenericQueryRecord);
    const chapter: ChapterInfo = {
      id: row.id,
      comicId: row.comicId,
      title: row.title,
      index: row.chapterNumber,
      pageCount: row.pageCount,
      isDownloaded: row.isDownloaded,
      downloadPath: row.downloadPath.length > 0 ? row.downloadPath : undefined,
      publishTime: row.publishTime,
      addTime: row.addTime,
      externalId: row.externalId
    };
    return chapter;
  }

  private async queryOnlineComicByExternalId(
    externalMangaId: string,
    sourceId: number,
    sourcePkg: string,
    sourceName: string
  ): Promise<OnlineComicInfo | null> {
    if (externalMangaId.length <= 0) {
      return null;
    }
    const byIdentity = await this.dataManager.getOnlineComicByStableIdentity(
      sourcePkg,
      sourceId,
      sourceName,
      externalMangaId
    );
    if (byIdentity) {
      return byIdentity;
    }
    if (sourceId <= 0) {
      return null;
    }
    const sql = `SELECT id FROM online_comic_info
                 WHERE externalId = ? AND sourceId = ?
                 ORDER BY updateTime DESC LIMIT 1`;
    const records = await this.databaseManager.querySql(sql, [externalMangaId, String(sourceId)]);
    if (!records || records.length <= 0) {
      return null;
    }
    const row = records[0] as GenericQueryRecord;
    const comicId = this.databaseValueToString(row.id);
    if (comicId.length <= 0) {
      return null;
    }
    return await this.dataManager.getOnlineComicInfoById(comicId);
  }

  private async queryOnlineChapterByExternalId(
    externalChapterId: string,
    sourceId: number,
    sourcePkg: string,
    sourceName: string
  ): Promise<OnlineChapterInfo | null> {
    if (externalChapterId.length <= 0) {
      return null;
    }
    let sql: string = `SELECT oc.id, oc.comicId, oc.externalId, oc.title, oc.chapterNumber AS chapterIndex, oc.url,
                              oc.pageCount, oc.publishTime, oc.addTime, oc.createTime, oc.updateTime,
                              oc.isDownloaded, oc.downloadPath
                       FROM online_chapter oc`;
    const args: string[] = [];
    if (sourcePkg.length > 0) {
      sql = `${sql} INNER JOIN online_comic_info oci ON oci.id = oc.comicId
             WHERE oc.externalId = ? AND oci.sourcePkg = ?`;
      args.push(externalChapterId);
      args.push(sourcePkg);
    } else if (sourceId > 0) {
      sql = `${sql} INNER JOIN online_comic_info oci ON oci.id = oc.comicId
             WHERE oc.externalId = ? AND oci.sourceId = ?`;
      args.push(externalChapterId);
      args.push(String(sourceId));
    } else if (sourceName.length > 0) {
      sql = `${sql} INNER JOIN online_comic_info oci ON oci.id = oc.comicId
             WHERE oc.externalId = ? AND oci.sourceName = ? AND (oci.sourcePkg IS NULL OR oci.sourcePkg = '')`;
      args.push(externalChapterId);
      args.push(sourceName);
    } else {
      sql = `${sql} WHERE oc.externalId = ?`;
      args.push(externalChapterId);
    }
    sql = `${sql} ORDER BY oc.updateTime DESC LIMIT 1`;
    const records = await this.databaseManager.querySql(sql, args);
    if (!records || records.length <= 0) {
      return null;
    }
    const row = this.buildOnlineChapterRow(records[0] as GenericQueryRecord);
    const chapter: OnlineChapterInfo = {
      id: row.id,
      comicId: row.comicId,
      externalId: row.externalId,
      title: row.title,
      chapterNumber: row.chapterNumber,
      url: row.url,
      pageCount: row.pageCount,
      publishTime: row.publishTime,
      addTime: row.addTime,
      createTime: row.createTime,
      updateTime: row.updateTime,
      isDownloaded: row.isDownloaded,
      downloadPath: row.downloadPath.length > 0 ? row.downloadPath : undefined,
      index: row.chapterNumber
    };
    return chapter;
  }

  private applyLocalComic(result: MangaIdentityResolveResult, comic: ComicInfo, reason: string): void {
    result.canonicalMangaId = comic.id;
    result.externalMangaId = comic.externalId || result.externalMangaId;
    result.comicInfo = comic;
    result.onlineComicInfo = null;
    result.contentHint = MangaIdentityContentHint.LOCAL;
    this.appendReason(result, reason);
  }

  private applyRecoveredLocalMangaId(result: MangaIdentityResolveResult, mangaId: string, reason: string): void {
    result.canonicalMangaId = mangaId;
    result.comicInfo = null;
    result.onlineComicInfo = null;
    result.contentHint = MangaIdentityContentHint.LOCAL;
    this.appendReason(result, reason);
  }

  private applyOnlineComic(result: MangaIdentityResolveResult, comic: OnlineComicInfo, reason: string): void {
    result.canonicalMangaId = comic.id;
    result.externalMangaId = comic.externalId;
    result.onlineComicInfo = comic;
    result.comicInfo = this.convertOnlineComicToComicInfo(comic);
    result.contentHint = MangaIdentityContentHint.ONLINE;
    const parsedSourceId = Number(comic.sourceId);
    if (!Number.isNaN(parsedSourceId) && parsedSourceId > 0) {
      result.sourceId = parsedSourceId;
    }
    result.sourceName = comic.sourceName;
    result.sourcePkg = comic.sourcePkg;
    this.appendReason(result, reason);
  }

  private applyLocalChapter(result: MangaIdentityResolveResult, chapter: ChapterInfo, reason: string): void {
    result.canonicalChapterId = chapter.id;
    result.externalChapterId = chapter.externalId || result.externalChapterId;
    result.chapterInfo = chapter;
    result.onlineChapterInfo = null;
    this.appendReason(result, reason);
  }

  private applyOnlineChapter(result: MangaIdentityResolveResult, chapter: OnlineChapterInfo, reason: string): void {
    result.canonicalChapterId = chapter.id;
    result.externalChapterId = chapter.externalId;
    result.onlineChapterInfo = chapter;
    result.chapterInfo = null;
    result.contentHint = MangaIdentityContentHint.ONLINE;
    this.appendReason(result, reason);
  }

  private convertOnlineComicToComicInfo(onlineComic: OnlineComicInfo): ComicInfo {
    const comic: ComicInfo = {
      id: onlineComic.id,
      title: onlineComic.title,
      author: onlineComic.author,
      description: onlineComic.description,
      coverUrl: onlineComic.coverUrl,
      sourceId: onlineComic.sourceId,
      status: MangaStatus.UNKNOWN,
      tags: onlineComic.tags,
      rating: onlineComic.rating,
      chapterCount: 0,
      lastUpdateTime: onlineComic.lastUpdateTime,
      addTime: onlineComic.addTime,
      externalId: onlineComic.externalId,
      contentType: 'online',
      isNSFW: onlineComic.isNSFW,
      isPrivate: onlineComic.isPrivate
    };
    return comic;
  }

  private buildLocalChapterRow(record: GenericQueryRecord): ResolvedLocalChapterRow {
    const row: ResolvedLocalChapterRow = new ResolvedLocalChapterRow();
    row.id = this.databaseValueToString(record.id);
    row.comicId = this.databaseValueToString(record.comicId);
    row.externalId = this.databaseValueToString(record.externalId);
    row.title = this.databaseValueToString(record.title);
    row.chapterNumber = this.databaseValueToNumber(record.chapterIndex);
    row.pageCount = this.databaseValueToNumber(record.pageCount);
    row.isDownloaded = this.databaseValueToNumber(record.isDownloaded) === 1;
    row.downloadPath = this.databaseValueToString(record.downloadPath);
    row.publishTime = this.databaseValueToNumber(record.publishTime);
    row.addTime = this.databaseValueToNumber(record.addTime);
    return row;
  }

  private buildOnlineChapterRow(record: GenericQueryRecord): ResolvedOnlineChapterRow {
    const row: ResolvedOnlineChapterRow = new ResolvedOnlineChapterRow();
    row.id = this.databaseValueToString(record.id);
    row.comicId = this.databaseValueToString(record.comicId);
    row.externalId = this.databaseValueToString(record.externalId);
    row.title = this.databaseValueToString(record.title);
    row.chapterNumber = this.databaseValueToNumber(record.chapterIndex);
    row.url = this.databaseValueToString(record.url);
    row.pageCount = this.databaseValueToNumber(record.pageCount);
    row.publishTime = this.databaseValueToNumber(record.publishTime);
    row.addTime = this.databaseValueToNumber(record.addTime);
    row.createTime = this.databaseValueToNumber(record.createTime);
    row.updateTime = this.databaseValueToNumber(record.updateTime);
    row.isDownloaded = this.databaseValueToNumber(record.isDownloaded) === 1;
    row.downloadPath = this.databaseValueToString(record.downloadPath);
    return row;
  }

  private resolveContentHint(input: MangaIdentityResolveInput): MangaIdentityContentHint {
    const contentType = input.contentType;
    if (contentType === 'OnlineUndownloaded' || contentType === 'OnlineDownloaded') {
      return MangaIdentityContentHint.ONLINE;
    }
    if (contentType === 'Local') {
      return MangaIdentityContentHint.LOCAL;
    }
    if (input.sourceId > 0) {
      return MangaIdentityContentHint.ONLINE;
    }
    return MangaIdentityContentHint.UNKNOWN;
  }

  private shouldPreferOnline(result: MangaIdentityResolveResult): boolean {
    return result.contentHint === MangaIdentityContentHint.ONLINE || result.sourceId > 0;
  }

  private appendReason(result: MangaIdentityResolveResult, reason: string): void {
    if (reason.length <= 0) {
      return;
    }
    if (result.reason.length <= 0) {
      result.reason = reason;
      return;
    }
    if (result.reason.indexOf(reason) < 0) {
      result.reason = `${result.reason}+${reason}`;
    }
  }

  private buildDetail(result: MangaIdentityResolveResult): string {
    return `inputManga=${result.inputMangaId}, inputChapter=${result.inputChapterId}, canonicalManga=${result.canonicalMangaId}, canonicalChapter=${result.canonicalChapterId}, externalManga=${result.externalMangaId}, externalChapter=${result.externalChapterId}, hint=${result.contentHint}, reason=${result.reason}`;
  }

  private normalizeId(value: string | undefined | null): string {
    if (value === undefined || value === null) {
      return '';
    }
    return String(value).trim();
  }

  private databaseValueToString(value: DatabaseValue | undefined): string {
    if (value === undefined || value === null) {
      return '';
    }
    return String(value);
  }

  private databaseValueToNumber(value: DatabaseValue | undefined): number {
    if (typeof value === 'number') {
      return Number.isFinite(value) ? value : 0;
    }
    if (typeof value === 'boolean') {
      return value ? 1 : 0;
    }
    if (typeof value === 'string') {
      const parsed = Number(value);
      return Number.isFinite(parsed) ? parsed : 0;
    }
    return 0;
  }
}
