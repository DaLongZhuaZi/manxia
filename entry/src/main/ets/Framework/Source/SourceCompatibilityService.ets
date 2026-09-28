import { logger } from 'manxia_core/src/main/ets/Utils/Logger';
import { DatabaseManager } from 'manxia_core/src/main/ets/Framework/Database/DatabaseManager';
import { DatabaseValue, GenericQueryRecord } from 'manxia_core/src/main/ets/Framework/Database/DatabaseTypes';
import { ChapterPreloadManager } from '../Preload/ChapterPreloadManager';
import { WebViewSourceManager } from '../WebView/WebViewSourceManager';
import { SourceIdentity } from 'manxia_source_engine/src/main/ets/Framework/Source/SourceIdentity';

const TAG = 'SourceCompatibilityService';

class DuplicateComicRow {
  id: string = '';
  sourceId: string = '';
  externalId: string = '';
  sourcePkg: string = '';
  sourceName: string = '';
  updateTime: number = 0;
  createTime: number = 0;
}

class DuplicateChapterRow {
  id: string = '';
  externalId: string = '';
}

export class SourceCompatibilityResult {
  updatedComics: number = 0;
  mergedComics: number = 0;
  fixedCacheStates: number = 0;
  errors: number = 0;
}

export class SourceCompatibilityService {
  private static instance: SourceCompatibilityService | null = null;
  private readonly databaseManager: DatabaseManager = DatabaseManager.getInstance();

  private constructor() {}

  static getInstance(): SourceCompatibilityService {
    if (SourceCompatibilityService.instance === null) {
      SourceCompatibilityService.instance = new SourceCompatibilityService();
    }
    return SourceCompatibilityService.instance;
  }

  async reconcileAfterSourceUpsert(identity: SourceIdentity): Promise<SourceCompatibilityResult> {
    const result = new SourceCompatibilityResult();
    if (!identity.isValid()) {
      logger.warn(TAG, `跳过图源兼容修复：identity无效, sourceId=${identity.sourceId}, pkg=${identity.pkg}`);
      return result;
    }

    await this.ensureCompatibilitySchema();

    try {
      await this.databaseManager.beginTransaction();
      await this.backfillOnlineComicIdentity(identity);
      result.mergedComics = await this.mergeDuplicateOnlineComics(identity);
      result.updatedComics = await this.finalizeOnlineComicIdentity(identity);
      result.fixedCacheStates = await this.repairChapterCacheState(identity);
      await this.databaseManager.commit();
    } catch (error) {
      await this.databaseManager.rollBack();
      result.errors++;
      logger.error(TAG, `图源兼容修复失败: pkg=${identity.pkg}`, String(error));
      return result;
    }

    this.invalidateRuntime(identity);
    logger.info(
      TAG,
      `图源兼容修复完成: pkg=${identity.pkg}, updated=${result.updatedComics}, merged=${result.mergedComics}, cache=${result.fixedCacheStates}`
    );
    return result;
  }

  async ensureCompatibilitySchema(): Promise<void> {
    try {
      await this.databaseManager.executeSql(
        'CREATE INDEX IF NOT EXISTS idx_online_comic_pkg_external ON online_comic_info (sourcePkg, externalId)'
      );
      await this.databaseManager.executeSql(
        'CREATE INDEX IF NOT EXISTS idx_online_chapter_cache_pkg ON online_chapter_cache_state (sourcePkg, cacheStatus)'
      );
      await this.databaseManager.executeSql("UPDATE online_comic_info SET sourcePkg = '' WHERE sourcePkg IS NULL");
      await this.databaseManager.executeSql("UPDATE online_comic_info SET sourceName = '' WHERE sourceName IS NULL");
    } catch (error) {
      logger.warn(TAG, `确保兼容索引失败: ${String(error)}`);
    }
  }

  private async backfillOnlineComicIdentity(identity: SourceIdentity): Promise<number> {
    const now = Date.now();
    const selectSql = `
      SELECT id FROM online_comic_info
      WHERE sourcePkg = ?
         OR sourceId = ?
         OR (sourcePkg = '' AND sourceName = ?)
    `;
    const rows = await this.databaseManager.querySql(selectSql, [
      identity.pkg,
      String(identity.sourceId),
      identity.name
    ]);
    if (!rows || rows.length <= 0) {
      return 0;
    }

    const updateSql = `
      UPDATE online_comic_info
      SET sourcePkg = ?, sourceName = ?, updateTime = ?
      WHERE id = ?
    `;
    for (let index = 0; index < rows.length; index++) {
      const row = rows[index] as GenericQueryRecord;
      const comicId = this.toStringValue(row.id);
      if (comicId.length > 0) {
        await this.databaseManager.executeSql(updateSql, [
          identity.pkg,
          identity.name,
          now,
          comicId
        ]);
      }
    }
    return rows.length;
  }

  private async finalizeOnlineComicIdentity(identity: SourceIdentity): Promise<number> {
    const rows = await this.databaseManager.querySql(
      'SELECT id, externalId FROM online_comic_info WHERE sourcePkg = ?',
      [identity.pkg]
    );
    if (!rows || rows.length <= 0) {
      return 0;
    }
    let updatedCount = 0;
    const sourceIdText = String(identity.sourceId);
    const now = Date.now();
    for (let index = 0; index < rows.length; index++) {
      const row = rows[index] as GenericQueryRecord;
      const comicId = this.toStringValue(row.id);
      const externalId = this.toStringValue(row.externalId);
      if (comicId.length <= 0) {
        continue;
      }
      const conflictRows = await this.databaseManager.querySql(
        'SELECT id FROM online_comic_info WHERE sourceId = ? AND externalId = ? AND id != ? LIMIT 1',
        [sourceIdText, externalId, comicId]
      );
      if (conflictRows && conflictRows.length > 0) {
        logger.warn(
          TAG,
          `跳过异常重复在线漫画sourceId刷新: pkg=${identity.pkg}, externalId=${externalId}, comicId=${comicId}`
        );
        continue;
      }
      await this.databaseManager.executeSql(
        `UPDATE online_comic_info
         SET sourceId = ?, sourceName = ?, updateTime = ?
         WHERE id = ?`,
        [sourceIdText, identity.name, now, comicId]
      );
      updatedCount++;
    }
    return updatedCount;
  }

  private async mergeDuplicateOnlineComics(identity: SourceIdentity): Promise<number> {
    const duplicateSql = `
      SELECT externalId FROM online_comic_info
      WHERE sourcePkg = ? AND externalId IS NOT NULL AND externalId != ''
      GROUP BY externalId HAVING COUNT(*) > 1
    `;
    const duplicateRows = await this.databaseManager.querySql(duplicateSql, [identity.pkg]);
    let mergedCount = 0;

    for (let index = 0; index < duplicateRows.length; index++) {
      const duplicate = duplicateRows[index] as GenericQueryRecord;
      const externalId = this.toStringValue(duplicate.externalId);
      if (externalId.length <= 0) {
        continue;
      }
      mergedCount += await this.mergeDuplicateGroup(identity, externalId);
    }

    return mergedCount;
  }

  private async mergeDuplicateGroup(identity: SourceIdentity, externalId: string): Promise<number> {
    const rows = await this.databaseManager.querySql(
      `SELECT id, sourceId, externalId, sourcePkg, sourceName, updateTime, createTime
       FROM online_comic_info
       WHERE sourcePkg = ? AND externalId = ?
       ORDER BY updateTime DESC`,
      [identity.pkg, externalId]
    );
    if (rows.length <= 1) {
      return 0;
    }

    const comics: DuplicateComicRow[] = [];
    for (let index = 0; index < rows.length; index++) {
      comics.push(this.toDuplicateComicRow(rows[index] as GenericQueryRecord));
    }

    const survivor = this.chooseSurvivor(comics, identity);
    let merged = 0;
    for (let index = 0; index < comics.length; index++) {
      const loser = comics[index];
      if (loser.id.length <= 0 || loser.id === survivor.id) {
        continue;
      }
      await this.mergeOnlineComicRecord(survivor.id, loser.id);
      merged++;
      logger.info(TAG, `合并重复在线漫画: loser=${loser.id} -> survivor=${survivor.id}, externalId=${externalId}`);
    }
    return merged;
  }

  private chooseSurvivor(rows: DuplicateComicRow[], identity: SourceIdentity): DuplicateComicRow {
    let survivor = rows[0];
    let bestScore = this.scoreDuplicateComic(survivor, identity);
    for (let index = 1; index < rows.length; index++) {
      const score = this.scoreDuplicateComic(rows[index], identity);
      if (score > bestScore) {
        survivor = rows[index];
        bestScore = score;
      }
    }
    return survivor;
  }

  private scoreDuplicateComic(row: DuplicateComicRow, identity: SourceIdentity): number {
    let score = 0;
    if (row.sourceId === String(identity.sourceId)) {
      score += 1000000000;
    }
    if (row.sourcePkg === identity.pkg) {
      score += 1000000;
    }
    score += row.updateTime > 0 ? row.updateTime : row.createTime;
    return score;
  }

  private async mergeOnlineComicRecord(survivorId: string, loserId: string): Promise<void> {
    await this.mergeComicMetadata(survivorId, loserId);
    await this.mergeFavorites(survivorId, loserId);
    await this.mergeChapters(survivorId, loserId);
    await this.databaseManager.executeSql(
      'UPDATE online_read_history SET comicId = ? WHERE comicId = ?',
      [survivorId, loserId]
    );
    await this.databaseManager.executeSql(
      'UPDATE online_chapter_cache_state SET comicId = ? WHERE comicId = ?',
      [survivorId, loserId]
    );
    await this.databaseManager.executeSql(
      "UPDATE unified_annotation SET contentId = ? WHERE contentId = ? AND contentType = 'manga'",
      [survivorId, loserId]
    );
    await this.databaseManager.executeSql(
      `DELETE FROM track_record
       WHERE contentId = ? AND contentType = 'manga'
         AND trackerId IN (SELECT trackerId FROM track_record WHERE contentId = ? AND contentType = 'manga')`,
      [loserId, survivorId]
    );
    await this.databaseManager.executeSql(
      "UPDATE track_record SET contentId = ? WHERE contentId = ? AND contentType = 'manga'",
      [survivorId, loserId]
    );
    await this.databaseManager.executeSql('DELETE FROM online_comic_info WHERE id = ?', [loserId]);
  }

  private async mergeComicMetadata(survivorId: string, loserId: string): Promise<void> {
    const survivorRows = await this.databaseManager.querySql(
      `SELECT title, author, description, coverUrl, tags, rating, lastUpdateTime, updateTime, isNSFW, isPrivate
       FROM online_comic_info WHERE id = ? LIMIT 1`,
      [survivorId]
    );
    const loserRows = await this.databaseManager.querySql(
      `SELECT title, author, description, coverUrl, tags, rating, lastUpdateTime, updateTime, isNSFW, isPrivate
       FROM online_comic_info WHERE id = ? LIMIT 1`,
      [loserId]
    );
    if (!survivorRows || survivorRows.length <= 0 || !loserRows || loserRows.length <= 0) {
      return;
    }

    const survivor = survivorRows[0] as GenericQueryRecord;
    const loser = loserRows[0] as GenericQueryRecord;
    const survivorUpdateTime = this.toNumberValue(survivor.updateTime);
    const loserUpdateTime = this.toNumberValue(loser.updateTime);
    const useLoserPrimary = loserUpdateTime > survivorUpdateTime;
    const title = this.chooseTextValue(survivor.title, loser.title, useLoserPrimary);
    const author = this.chooseTextValue(survivor.author, loser.author, false);
    const description = this.chooseTextValue(survivor.description, loser.description, false);
    const coverUrl = this.chooseTextValue(survivor.coverUrl, loser.coverUrl, false);
    const tags = this.chooseTextValue(survivor.tags, loser.tags, false);
    const survivorRating = this.toNumberValue(survivor.rating);
    const loserRating = this.toNumberValue(loser.rating);
    const rating = survivorRating > 0 ? survivorRating : loserRating;
    const lastUpdateTime = Math.max(this.toNumberValue(survivor.lastUpdateTime), this.toNumberValue(loser.lastUpdateTime));
    const isNSFW = Math.max(this.toNumberValue(survivor.isNSFW), this.toNumberValue(loser.isNSFW));
    const isPrivate = Math.max(this.toNumberValue(survivor.isPrivate), this.toNumberValue(loser.isPrivate));

    await this.databaseManager.executeSql(
      `UPDATE online_comic_info
       SET title = ?, author = ?, description = ?, coverUrl = ?, tags = ?,
           rating = ?, lastUpdateTime = ?, updateTime = ?, isNSFW = ?, isPrivate = ?
       WHERE id = ?`,
      [
        title,
        author,
        description,
        coverUrl,
        tags,
        rating,
        lastUpdateTime,
        Math.max(survivorUpdateTime, loserUpdateTime),
        isNSFW,
        isPrivate,
        survivorId
      ]
    );
  }

  private async mergeFavorites(survivorId: string, loserId: string): Promise<void> {
    await this.databaseManager.executeSql(
      `DELETE FROM favorite
       WHERE comicId = ? AND userId IN (SELECT userId FROM favorite WHERE comicId = ?)`,
      [loserId, survivorId]
    );
    await this.databaseManager.executeSql(
      'UPDATE favorite SET comicId = ? WHERE comicId = ?',
      [survivorId, loserId]
    );
  }

  private async mergeChapters(survivorId: string, loserId: string): Promise<void> {
    const rows = await this.databaseManager.querySql(
      'SELECT id, externalId FROM online_chapter WHERE comicId = ?',
      [loserId]
    );
    for (let index = 0; index < rows.length; index++) {
      const chapter = this.toDuplicateChapterRow(rows[index] as GenericQueryRecord);
      if (chapter.id.length <= 0) {
        continue;
      }
      const survivorChapterId = await this.findSurvivorChapter(survivorId, chapter.externalId);
      if (survivorChapterId.length > 0) {
        await this.mergeChapterRecord(survivorId, survivorChapterId, chapter.id);
      } else {
        await this.databaseManager.executeSql(
          'UPDATE online_chapter SET comicId = ? WHERE id = ?',
          [survivorId, chapter.id]
        );
      }
    }
  }

  private async findSurvivorChapter(survivorId: string, externalId: string): Promise<string> {
    if (externalId.length <= 0) {
      return '';
    }
    const rows = await this.databaseManager.querySql(
      'SELECT id FROM online_chapter WHERE comicId = ? AND externalId = ? LIMIT 1',
      [survivorId, externalId]
    );
    if (!rows || rows.length <= 0) {
      return '';
    }
    return this.toStringValue((rows[0] as GenericQueryRecord).id);
  }

  private async mergeChapterRecord(survivorComicId: string, survivorChapterId: string, loserChapterId: string): Promise<void> {
    await this.mergeChapterMetadata(survivorChapterId, loserChapterId);
    await this.databaseManager.executeSql(
      'UPDATE online_page SET chapterId = ? WHERE chapterId = ?',
      [survivorChapterId, loserChapterId]
    );
    await this.databaseManager.executeSql(
      'DELETE FROM online_chapter_cache_state WHERE chapterId = ? AND EXISTS (SELECT 1 FROM online_chapter_cache_state WHERE chapterId = ?)',
      [loserChapterId, survivorChapterId]
    );
    await this.databaseManager.executeSql(
      'UPDATE online_chapter_cache_state SET chapterId = ?, comicId = ? WHERE chapterId = ?',
      [survivorChapterId, survivorComicId, loserChapterId]
    );
    await this.databaseManager.executeSql(
      'UPDATE online_read_history SET chapterId = ?, comicId = ? WHERE chapterId = ?',
      [survivorChapterId, survivorComicId, loserChapterId]
    );
    await this.databaseManager.executeSql(
      'UPDATE favorite SET lastReadChapterId = ? WHERE lastReadChapterId = ?',
      [survivorChapterId, loserChapterId]
    );
    await this.databaseManager.executeSql('DELETE FROM online_chapter WHERE id = ?', [loserChapterId]);
  }

  private async mergeChapterMetadata(survivorChapterId: string, loserChapterId: string): Promise<void> {
    const survivorRows = await this.databaseManager.querySql(
      `SELECT title, url, pageCount, publishTime, addTime, updateTime, isDownloaded, downloadPath
       FROM online_chapter WHERE id = ? LIMIT 1`,
      [survivorChapterId]
    );
    const loserRows = await this.databaseManager.querySql(
      `SELECT title, url, pageCount, publishTime, addTime, updateTime, isDownloaded, downloadPath
       FROM online_chapter WHERE id = ? LIMIT 1`,
      [loserChapterId]
    );
    if (!survivorRows || survivorRows.length <= 0 || !loserRows || loserRows.length <= 0) {
      return;
    }

    const survivor = survivorRows[0] as GenericQueryRecord;
    const loser = loserRows[0] as GenericQueryRecord;
    const survivorUpdateTime = this.toNumberValue(survivor.updateTime);
    const loserUpdateTime = this.toNumberValue(loser.updateTime);
    const title = this.chooseTextValue(survivor.title, loser.title, loserUpdateTime > survivorUpdateTime);
    const url = this.chooseTextValue(survivor.url, loser.url, false);
    const pageCount = Math.max(this.toNumberValue(survivor.pageCount), this.toNumberValue(loser.pageCount));
    const publishTime = Math.max(this.toNumberValue(survivor.publishTime), this.toNumberValue(loser.publishTime));
    const addTime = Math.min(this.toNumberValue(survivor.addTime), this.toNumberValue(loser.addTime));
    const isDownloaded = Math.max(this.toNumberValue(survivor.isDownloaded), this.toNumberValue(loser.isDownloaded));
    const downloadPath = this.chooseTextValue(survivor.downloadPath, loser.downloadPath, false);

    await this.databaseManager.executeSql(
      `UPDATE online_chapter
       SET title = ?, url = ?, pageCount = ?, publishTime = ?, addTime = ?,
           updateTime = ?, isDownloaded = ?, downloadPath = ?
       WHERE id = ?`,
      [
        title,
        url,
        pageCount,
        publishTime,
        addTime,
        Math.max(survivorUpdateTime, loserUpdateTime),
        isDownloaded,
        downloadPath,
        survivorChapterId
      ]
    );
  }

  private async repairChapterCacheState(identity: SourceIdentity): Promise<number> {
    const rows = await this.databaseManager.querySql(
      `SELECT occs.chapterId FROM online_chapter_cache_state occs
       INNER JOIN online_comic_info oci ON oci.id = occs.comicId
       WHERE oci.sourcePkg = ?`,
      [identity.pkg]
    );
    if (rows.length <= 0) {
      return 0;
    }

    await this.databaseManager.executeSql(
      `UPDATE online_chapter_cache_state
       SET sourceId = ?, sourceName = ?, sourcePkg = ?, updateTime = ?
       WHERE comicId IN (SELECT id FROM online_comic_info WHERE sourcePkg = ?)`,
      [String(identity.sourceId), identity.name, identity.pkg, Date.now(), identity.pkg]
    );
    return rows.length;
  }

  private invalidateRuntime(identity: SourceIdentity): void {
    try {
      WebViewSourceManager.getInstance().invalidateSourceRuntime(identity.sourceId, identity.name, identity.pkg);
      ChapterPreloadManager.getInstance().stopPreload();
    } catch (error) {
      logger.warn(TAG, `图源运行缓存失效失败: pkg=${identity.pkg}, error=${String(error)}`);
    }
  }

  private toDuplicateComicRow(record: GenericQueryRecord): DuplicateComicRow {
    const row = new DuplicateComicRow();
    row.id = this.toStringValue(record.id);
    row.sourceId = this.toStringValue(record.sourceId);
    row.externalId = this.toStringValue(record.externalId);
    row.sourcePkg = this.toStringValue(record.sourcePkg);
    row.sourceName = this.toStringValue(record.sourceName);
    row.updateTime = this.toNumberValue(record.updateTime);
    row.createTime = this.toNumberValue(record.createTime);
    return row;
  }

  private toDuplicateChapterRow(record: GenericQueryRecord): DuplicateChapterRow {
    const row = new DuplicateChapterRow();
    row.id = this.toStringValue(record.id);
    row.externalId = this.toStringValue(record.externalId);
    return row;
  }

  private toStringValue(value: DatabaseValue | undefined): string {
    if (value === undefined || value === null) {
      return '';
    }
    return String(value);
  }

  private toNumberValue(value: DatabaseValue | undefined): number {
    if (typeof value === 'number') {
      return value;
    }
    if (typeof value === 'string') {
      const parsed = Number(value);
      return Number.isNaN(parsed) ? 0 : parsed;
    }
    return 0;
  }

  private chooseTextValue(
    survivorValue: DatabaseValue | undefined,
    loserValue: DatabaseValue | undefined,
    preferLoser: boolean
  ): string {
    const survivorText = this.toStringValue(survivorValue);
    const loserText = this.toStringValue(loserValue);
    if (preferLoser && loserText.length > 0) {
      return loserText;
    }
    return survivorText.length > 0 ? survivorText : loserText;
  }
}
