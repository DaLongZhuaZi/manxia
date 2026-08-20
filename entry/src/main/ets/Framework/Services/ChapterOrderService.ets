import {
  ChapterOrderCacheRemapResult,
  ChapterOrderContentKind,
  ChapterOrderIndexRemap,
  ChapterOrderItem,
  ChapterOrderPersistResult,
  ChapterOrderPlan,
  UnifiedChapter,
  UnifiedContent,
  UnifiedContentType
} from 'manxia_core/src/main/ets/Models/UnifiedContentModels';
import { MangaChapter } from 'manxia_core/src/main/ets/Models/MangaModels';
import { EBookChapter, EBookFormat } from 'manxia_core/src/main/ets/Models/EBookModels';
import { LegadoChapter } from 'manxia_novel/src/main/ets/Framework/Novel/LegadoSourceTypes';
import { MangaAdapter, EBookAdapter, NovelAdapter } from '../Adapters/UnifiedContentAdapter';
import { buildLocalTextNovelBookId } from '../Adapters/LocalTextNovelAdapter';
import { DatabaseManager } from 'manxia_core/src/main/ets/Framework/Database/DatabaseManager';
import { DatabaseValue, GenericQueryRecord } from 'manxia_core/src/main/ets/Framework/Database/DatabaseTypes';
import { getNovelChapterCacheManager } from '../Novel/NovelChapterCacheManager';
import { getRemoteReadAloudCacheService } from '../ReadAloud/RemoteReadAloudCacheService';
import { logger } from 'manxia_core/src/main/ets/Utils/Logger';

const TAG = 'ChapterOrderService';
const OVERRIDE_TABLE = 'chapter_order_override';

interface ChapterOrderIdentity {
  contentType: UnifiedContentType;
  contentKind: ChapterOrderContentKind;
  contentId: string;
  sourceId: string;
}

interface StoredChapterOrderRow {
  stableKey: string;
  orderIndex: number;
  originalOrderIndex: number;
  titleSnapshot: string;
}

interface StableChapterRef {
  stableKey: string;
  chapterId: string;
  title: string;
  sourceIndex: number;
  chapter: UnifiedChapter;
}

interface ChapterOrderValidationResult {
  ok: boolean;
  message: string;
}

interface EBookDomPosRemapResult {
  value: string;
  changed: boolean;
}

export class ChapterOrderService {
  private static instance: ChapterOrderService | null = null;
  private dbManager: DatabaseManager = DatabaseManager.getInstance();

  private constructor() {}

  static getInstance(): ChapterOrderService {
    if (!ChapterOrderService.instance) {
      ChapterOrderService.instance = new ChapterOrderService();
    }
    return ChapterOrderService.instance;
  }

  public buildPlan(content: UnifiedContent, orderedChapters: UnifiedChapter[]): ChapterOrderPlan {
    const identity = this.resolveIdentity(content);
    return this.buildPlanInternal(content, orderedChapters, identity, []);
  }

  public async applyStoredOrder(content: UnifiedContent): Promise<UnifiedContent> {
    const identity = this.resolveIdentity(content);
    const storedRows = await this.queryStoredRows(identity);
    if (storedRows.length === 0) {
      return this.rebuildContentWithOrder(content, content.chapters);
    }

    const currentRefs = this.buildStableRefs(content.chapters);
    const orderedRefs: StableChapterRef[] = [];
    const usedKeys: string[] = [];

    for (let i = 0; i < storedRows.length; i++) {
      const row = storedRows[i];
      const ref = this.findRefByStableKey(currentRefs, row.stableKey);
      if (ref !== null) {
        orderedRefs.push(ref);
        usedKeys.push(ref.stableKey);
      }
    }

    for (let i = 0; i < currentRefs.length; i++) {
      const ref = currentRefs[i];
      if (!this.stringArrayIncludes(usedKeys, ref.stableKey)) {
        orderedRefs.push(ref);
      }
    }

    const orderedChapters: UnifiedChapter[] = [];
    for (let i = 0; i < orderedRefs.length; i++) {
      orderedChapters.push(orderedRefs[i].chapter);
    }

    if (orderedRefs.length !== currentRefs.length) {
      logger.warn(
        TAG,
        `章节排序回放数量异常: contentType=${identity.contentType}, contentId=${identity.contentId}, ` +
          `sourceId=${identity.sourceId}, stored=${storedRows.length}, current=${currentRefs.length}, ordered=${orderedRefs.length}`
      );
      return this.rebuildContentWithOrder(content, content.chapters);
    }

    await this.syncStoredOrderProjection(content, orderedChapters, identity, storedRows);
    return this.rebuildContentWithOrder(content, orderedChapters);
  }

  public async persistOrder(content: UnifiedContent, orderedChapters: UnifiedChapter[]): Promise<ChapterOrderPersistResult> {
    return this.persistOrderInternal(content, orderedChapters, true);
  }

  public async resetOrder(content: UnifiedContent): Promise<ChapterOrderPersistResult> {
    const identity = this.resolveIdentity(content);
    const storedRows = await this.queryStoredRows(identity);
    if (storedRows.length === 0) {
      logger.info(
        TAG,
        `章节排序重置跳过: contentType=${identity.contentType}, kind=${identity.contentKind}, ` +
          `contentId=${identity.contentId}, sourceId=${identity.sourceId}, reason=noStoredOverride`
      );
      return {
        success: true,
        message: '当前没有自定义章节顺序',
        movedCount: 0,
        cacheResult: this.createEmptyCacheResult()
      };
    }

    const orderedChapters: UnifiedChapter[] = this.buildSourceOrderChapters(content, storedRows);
    logger.info(
      TAG,
      `开始重置章节排序为来源顺序: contentType=${identity.contentType}, kind=${identity.contentKind}, ` +
        `contentId=${identity.contentId}, sourceId=${identity.sourceId}, storedRows=${storedRows.length}, ` +
        `chapters=${orderedChapters.length}`
    );

    return this.persistOrderInternal(content, orderedChapters, false);
  }

  public async buildSourceOrderDraft(content: UnifiedContent): Promise<UnifiedChapter[]> {
    const identity = this.resolveIdentity(content);
    const storedRows = await this.queryStoredRows(identity);
    if (storedRows.length === 0) {
      logger.info(
        TAG,
        `生成来源顺序草稿: contentType=${identity.contentType}, kind=${identity.contentKind}, ` +
          `contentId=${identity.contentId}, sourceId=${identity.sourceId}, mode=currentOrder, chapters=${content.chapters.length}`
      );
      return this.cloneUnifiedChapterArray(content.chapters);
    }
    logger.info(
      TAG,
      `生成来源顺序草稿: contentType=${identity.contentType}, kind=${identity.contentKind}, ` +
        `contentId=${identity.contentId}, sourceId=${identity.sourceId}, mode=storedOriginalOrder, ` +
        `storedRows=${storedRows.length}, chapters=${content.chapters.length}`
    );
    return this.buildSourceOrderChapters(content, storedRows);
  }

  public rebuildContentWithOrder(content: UnifiedContent, orderedChapters: UnifiedChapter[]): UnifiedContent {
    const rebuiltChapters: UnifiedChapter[] = [];
    const mangaChapters: MangaChapter[] = [];
    const ebookChapters: EBookChapter[] = [];

    for (let i = 0; i < orderedChapters.length; i++) {
      const chapter = orderedChapters[i];
      this.updateOriginalChapterIndex(chapter, i);
      const rebuilt = this.cloneUnifiedChapter(chapter, i);
      rebuiltChapters.push(rebuilt);

      if (content.contentType === UnifiedContentType.MANGA) {
        const mangaChapter = MangaAdapter.getOriginalChapter(rebuilt);
        if (mangaChapter !== null) {
          mangaChapters.push(mangaChapter);
        }
      } else if (content.contentType === UnifiedContentType.EBOOK) {
        const ebookChapter = EBookAdapter.getOriginalChapter(rebuilt);
        if (ebookChapter !== null) {
          ebookChapters.push(ebookChapter);
        }
      }
    }

    if (content.contentType === UnifiedContentType.MANGA) {
      const manga = MangaAdapter.getOriginalManga(content);
      if (manga !== null && mangaChapters.length === rebuiltChapters.length) {
        manga.chapters = mangaChapters;
      }
    } else if (content.contentType === UnifiedContentType.EBOOK) {
      const ebook = EBookAdapter.getOriginalEBook(content);
      if (ebook !== null && ebookChapters.length === rebuiltChapters.length) {
        ebook.chapters = ebookChapters;
      }
    }

    const lastReadIndex = this.remapContentLastReadIndex(content, rebuiltChapters);
    let lastReadTitle = '';
    if (lastReadIndex >= 0 && lastReadIndex < rebuiltChapters.length) {
      lastReadTitle = rebuiltChapters[lastReadIndex].title;
    }

    const rebuiltContent: UnifiedContent = {
      id: content.id,
      title: content.title,
      coverUrl: content.coverUrl,
      author: content.author,
      description: content.description,
      contentType: content.contentType,
      genres: content.genres,
      tags: content.tags,
      readStatus: content.readStatus,
      isFavorite: content.isFavorite,
      isNSFW: content.isNSFW,
      totalChapters: rebuiltChapters.length,
      readChapters: content.readChapters,
      lastReadChapterIndex: lastReadIndex,
      lastReadChapterTitle: lastReadTitle,
      lastReadTime: content.lastReadTime,
      readProgress: content.readProgress,
      sourceId: content.sourceId,
      sourceName: content.sourceName,
      sourcePkg: content.sourcePkg,
      sourceUrl: content.sourceUrl,
      isLocal: content.isLocal,
      remoteVerificationInfo: content.remoteVerificationInfo,
      publisher: content.publisher,
      publishDate: content.publishDate,
      isbn: content.isbn,
      fileSize: content.fileSize,
      filePath: content.filePath,
      format: content.format,
      chapters: rebuiltChapters,
      originalData: content.originalData,
      originalType: content.originalType
    };

    return rebuiltContent;
  }

  private buildSourceOrderChapters(content: UnifiedContent, storedRows: StoredChapterOrderRow[]): UnifiedChapter[] {
    const currentRefs = this.buildStableRefs(content.chapters);
    const sourceRefs: StableChapterRef[] = [];
    const usedKeys: string[] = [];

    for (let order = 0; order < currentRefs.length + storedRows.length; order++) {
      for (let i = 0; i < storedRows.length; i++) {
        const row = storedRows[i];
        if (row.originalOrderIndex === order) {
          const ref = this.findRefByStableKey(currentRefs, row.stableKey);
          if (ref !== null && !this.stringArrayIncludes(usedKeys, ref.stableKey)) {
            sourceRefs.push(ref);
            usedKeys.push(ref.stableKey);
          }
        }
      }
    }

    for (let i = 0; i < currentRefs.length; i++) {
      const ref = currentRefs[i];
      if (!this.stringArrayIncludes(usedKeys, ref.stableKey)) {
        sourceRefs.push(ref);
      }
    }

    const orderedChapters: UnifiedChapter[] = [];
    for (let i = 0; i < sourceRefs.length; i++) {
      orderedChapters.push(sourceRefs[i].chapter);
    }
    return orderedChapters;
  }

  private cloneUnifiedChapterArray(chapters: UnifiedChapter[]): UnifiedChapter[] {
    const result: UnifiedChapter[] = [];
    for (let i = 0; i < chapters.length; i++) {
      result.push(this.cloneUnifiedChapter(chapters[i], chapters[i].index));
    }
    return result;
  }

  private async persistOrderInternal(
    content: UnifiedContent,
    orderedChapters: UnifiedChapter[],
    saveOverride: boolean
  ): Promise<ChapterOrderPersistResult> {
    const identity = this.resolveIdentity(content);
    const storedRows = await this.queryStoredRows(identity);
    const plan = this.buildPlanInternal(content, orderedChapters, identity, storedRows);
    const validation = this.validatePlan(content, plan);
    if (!validation.ok) {
      return {
        success: false,
        message: validation.message,
        movedCount: 0,
        cacheResult: this.createEmptyCacheResult()
      };
    }

    let dbCommitted = false;
    try {
      await this.dbManager.beginTransaction();
      await this.deleteStoredRows(identity);
      if (saveOverride) {
        await this.insertStoredRows(plan);
      }
      await this.projectPlanToDatabase(content, plan);
      await this.dbManager.commit();
      dbCommitted = true;
    } catch (error) {
      if (!dbCommitted) {
        try {
          await this.dbManager.rollBack();
        } catch (rollbackError) {
          logger.error(TAG, `章节排序事务回滚失败: ${String(rollbackError)}`);
        }
      }
      const message = `章节排序保存失败: ${String(error)}`;
      logger.error(TAG, message);
      return {
        success: false,
        message: message,
        movedCount: 0,
        cacheResult: this.createEmptyCacheResult()
      };
    }

    const cacheResult = await this.migrateCachesAfterCommit(content, plan);
    const cacheFailed = cacheResult.failedKeys.length > 0 || cacheResult.warnings.length > 0;
    const message = cacheFailed ? '排序已保存，部分缓存需要重新生成' : '章节排序已保存';

    logger.info(
      TAG,
      `章节排序保存完成: contentType=${identity.contentType}, kind=${identity.contentKind}, contentId=${identity.contentId}, ` +
        `sourceId=${identity.sourceId}, moved=${plan.movedCount}, cacheFailed=${cacheFailed}`
    );

    return {
      success: true,
      message: message,
      movedCount: plan.movedCount,
      cacheResult: cacheResult
    };
  }

  private async syncStoredOrderProjection(
    content: UnifiedContent,
    orderedChapters: UnifiedChapter[],
    identity: ChapterOrderIdentity,
    storedRows: StoredChapterOrderRow[]
  ): Promise<void> {
    const plan = this.buildPlanInternal(content, orderedChapters, identity, storedRows);
    const validation = this.validatePlan(content, plan);
    if (!validation.ok) {
      logger.warn(TAG, `跳过章节排序投影同步: ${validation.message}`);
      return;
    }
    if (plan.movedCount === 0 && plan.items.length === storedRows.length) {
      return;
    }

    let committed = false;
    try {
      await this.dbManager.beginTransaction();
      await this.deleteStoredRows(identity);
      await this.insertStoredRows(plan);
      await this.projectPlanToDatabase(content, plan);
      await this.dbManager.commit();
      committed = true;
      logger.info(
        TAG,
        `章节排序投影已同步: contentType=${identity.contentType}, contentId=${identity.contentId}, ` +
          `sourceId=${identity.sourceId}, moved=${plan.movedCount}, items=${plan.items.length}`
      );
    } catch (error) {
      if (!committed) {
        try {
          await this.dbManager.rollBack();
        } catch (rollbackError) {
          logger.error(TAG, `章节排序投影回滚失败: ${String(rollbackError)}`);
        }
      }
      logger.warn(TAG, `章节排序投影同步失败，仅应用UI顺序: ${String(error)}`);
    }
  }

  private buildPlanInternal(
    content: UnifiedContent,
    orderedChapters: UnifiedChapter[],
    identity: ChapterOrderIdentity,
    storedRows: StoredChapterOrderRow[]
  ): ChapterOrderPlan {
    const currentRefs = this.buildStableRefs(content.chapters);
    const orderedRefs = this.buildStableRefs(orderedChapters);
    const items: ChapterOrderItem[] = [];
    const remaps: ChapterOrderIndexRemap[] = [];
    let movedCount = 0;

    for (let newIndex = 0; newIndex < orderedRefs.length; newIndex++) {
      const orderedRef = orderedRefs[newIndex];
      const currentRef = this.findRefByStableKey(currentRefs, orderedRef.stableKey);
      const oldIndex = currentRef !== null ? currentRef.sourceIndex : orderedRef.sourceIndex;
      const storedRow = this.findStoredRowByStableKey(storedRows, orderedRef.stableKey);
      const originalOrderIndex = storedRow !== null ? storedRow.originalOrderIndex : oldIndex;
      const item: ChapterOrderItem = {
        stableKey: orderedRef.stableKey,
        chapterId: orderedRef.chapterId,
        title: orderedRef.title,
        oldIndex: oldIndex,
        newIndex: newIndex,
        originalOrderIndex: originalOrderIndex
      };
      items.push(item);
      if (oldIndex !== newIndex) {
        movedCount++;
        const remap: ChapterOrderIndexRemap = {
          stableKey: orderedRef.stableKey,
          title: orderedRef.title,
          oldIndex: oldIndex,
          newIndex: newIndex
        };
        remaps.push(remap);
      }
    }

    return {
      contentType: identity.contentType,
      contentKind: identity.contentKind,
      contentId: identity.contentId,
      sourceId: identity.sourceId,
      items: items,
      remaps: remaps,
      movedCount: movedCount
    };
  }

  private validatePlan(content: UnifiedContent, plan: ChapterOrderPlan): ChapterOrderValidationResult {
    if (content.chapters.length !== plan.items.length) {
      return { ok: false, message: '章节数量已变化，请刷新后重新排序' };
    }

    const seenKeys: string[] = [];
    for (let i = 0; i < plan.items.length; i++) {
      const item = plan.items[i];
      if (item.stableKey.length === 0) {
        return { ok: false, message: `第 ${i + 1} 章缺少稳定章节身份` };
      }
      if (this.stringArrayIncludes(seenKeys, item.stableKey)) {
        return { ok: false, message: `章节身份重复: ${item.title}` };
      }
      if (item.newIndex !== i) {
        return { ok: false, message: '目标章节索引不连续' };
      }
      seenKeys.push(item.stableKey);
    }

    const currentRefs = this.buildStableRefs(content.chapters);
    if (currentRefs.length !== plan.items.length) {
      return { ok: false, message: '章节稳定身份生成失败' };
    }

    for (let i = 0; i < currentRefs.length; i++) {
      const currentRef = currentRefs[i];
      if (this.findItemByStableKey(plan.items, currentRef.stableKey) === null) {
        return { ok: false, message: `章节缺失: ${currentRef.title}` };
      }
    }

    return { ok: true, message: '' };
  }

  private async queryStoredRows(identity: ChapterOrderIdentity): Promise<StoredChapterOrderRow[]> {
    const rows = await this.dbManager.querySql(
      `SELECT chapterStableKey, orderIndex, originalOrderIndex, titleSnapshot
       FROM ${OVERRIDE_TABLE}
       WHERE contentType = ? AND contentId = ? AND sourceId = ?
       ORDER BY orderIndex ASC`,
      [identity.contentType, identity.contentId, identity.sourceId]
    );
    const result: StoredChapterOrderRow[] = [];
    for (let i = 0; i < rows.length; i++) {
      const record = rows[i] as GenericQueryRecord;
      const stableKey = this.toSafeString(record.chapterStableKey);
      if (stableKey.length === 0) {
        continue;
      }
      const row: StoredChapterOrderRow = {
        stableKey: stableKey,
        orderIndex: this.toSafeNumber(record.orderIndex, i),
        originalOrderIndex: this.toSafeNumber(record.originalOrderIndex, i),
        titleSnapshot: this.toSafeString(record.titleSnapshot)
      };
      result.push(row);
    }
    return result;
  }

  private async deleteStoredRows(identity: ChapterOrderIdentity): Promise<void> {
    await this.dbManager.executeSql(
      `DELETE FROM ${OVERRIDE_TABLE} WHERE contentType = ? AND contentId = ? AND sourceId = ?`,
      [identity.contentType, identity.contentId, identity.sourceId]
    );
  }

  private async insertStoredRows(plan: ChapterOrderPlan): Promise<void> {
    const now = Date.now();
    for (let i = 0; i < plan.items.length; i++) {
      const item = plan.items[i];
      await this.dbManager.executeSql(
        `INSERT OR REPLACE INTO ${OVERRIDE_TABLE}
          (id, contentType, contentId, sourceId, chapterStableKey, orderIndex, originalOrderIndex, titleSnapshot, createTime, updateTime)
         VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?)`,
        [
          this.buildOverrideRowId(plan, item),
          plan.contentType,
          plan.contentId,
          plan.sourceId,
          item.stableKey,
          item.newIndex,
          item.originalOrderIndex,
          item.title,
          now,
          now
        ]
      );
    }
  }

  private buildOverrideRowId(plan: ChapterOrderPlan, item: ChapterOrderItem): string {
    return `${plan.contentType}:${plan.contentId}:${plan.sourceId}:${item.stableKey}`;
  }

  private async projectPlanToDatabase(content: UnifiedContent, plan: ChapterOrderPlan): Promise<void> {
    switch (plan.contentKind) {
      case ChapterOrderContentKind.LOCAL_MANGA:
        await this.projectMangaOrderToDatabase('chapter', plan, false);
        break;
      case ChapterOrderContentKind.ONLINE_MANGA:
        await this.projectMangaOrderToDatabase('online_chapter', plan, true);
        break;
      case ChapterOrderContentKind.EBOOK:
        await this.projectEBookOrderToDatabase(content, plan);
        break;
      case ChapterOrderContentKind.NOVEL:
        await this.projectNovelOrderToDatabase(content, plan);
        break;
    }
  }

  private async projectMangaOrderToDatabase(tableName: string, plan: ChapterOrderPlan, online: boolean): Promise<void> {
    const now = Date.now();
    for (let i = 0; i < plan.items.length; i++) {
      const item = plan.items[i];
      if (online) {
        await this.dbManager.executeSql(
          'UPDATE online_chapter SET chapterNumber = ?, `index` = ?, updateTime = ? WHERE id = ?',
          [item.newIndex, item.newIndex, now, item.chapterId]
        );
      } else {
        await this.dbManager.executeSql(
          `UPDATE ${tableName} SET chapterNumber = ?, updateTime = ? WHERE id = ?`,
          [item.newIndex, now, item.chapterId]
        );
      }
    }
  }

  private async projectEBookOrderToDatabase(content: UnifiedContent, plan: ChapterOrderPlan): Promise<void> {
    const now = Date.now();
    for (let i = 0; i < plan.items.length; i++) {
      const item = plan.items[i];
      await this.dbManager.executeSql(
        'UPDATE ebook_chapter SET chapterNumber = ? WHERE id = ? AND bookId = ?',
        [item.newIndex, item.chapterId, content.id]
      );
    }

    const progressRows = await this.dbManager.querySql(
      'SELECT id, currentChapterId, currentChapterIndex, domPos FROM ebook_reading_progress WHERE bookId = ?',
      [content.id]
    );
    for (let i = 0; i < progressRows.length; i++) {
      const row = progressRows[i] as GenericQueryRecord;
      const progressId = this.toSafeString(row.id);
      if (progressId.length === 0) {
        continue;
      }
      const currentChapterId = this.toSafeString(row.currentChapterId);
      let remap = this.findRemapByChapterId(plan, currentChapterId);
      if (remap === null) {
        remap = this.findRemapByOldIndex(plan.remaps, this.toSafeNumber(row.currentChapterIndex, -1));
      }
      if (remap === null) {
        continue;
      }
      const domPos = this.toSafeString(row.domPos);
      const domPosResult = this.remapEBookDomPos(domPos, remap.oldIndex, remap.newIndex);
      await this.dbManager.executeSql(
        'UPDATE ebook_reading_progress SET currentChapterIndex = ?, domPos = ?, updateTime = ? WHERE id = ?',
        [remap.newIndex, domPosResult.value, now, progressId]
      );
    }
  }

  private async projectNovelOrderToDatabase(content: UnifiedContent, plan: ChapterOrderPlan): Promise<void> {
    const now = Date.now();
    const bookIds = this.buildNovelBookIds(content);
    for (let i = 0; i < plan.items.length; i++) {
      const item = plan.items[i];
      const chapter = this.findChapterByStableKey(content.chapters, item.stableKey);
      const originalChapter = chapter !== null ? NovelAdapter.getOriginalChapter(chapter) : null;
      for (let b = 0; b < bookIds.length; b++) {
        const bookId = bookIds[b];
        if (originalChapter !== null && originalChapter.id.length > 0) {
          await this.dbManager.executeSql(
            'UPDATE novel_chapter SET chapterIndex = ?, updateTime = ? WHERE id = ?',
            [item.newIndex, now, originalChapter.id]
          );
        }
        if (originalChapter !== null && originalChapter.url.length > 0) {
          await this.dbManager.executeSql(
            'UPDATE novel_chapter SET chapterIndex = ?, updateTime = ? WHERE bookId = ? AND url = ?',
            [item.newIndex, now, bookId, originalChapter.url]
          );
        }
        if (item.chapterId.length > 0) {
          await this.dbManager.executeSql(
            'UPDATE novel_chapter SET chapterIndex = ?, updateTime = ? WHERE bookId = ? AND (id = ? OR url = ?)',
            [item.newIndex, now, bookId, item.chapterId, item.chapterId]
          );
        }
      }
    }

    await this.remapNovelProgressIndexes(content, plan, bookIds);
  }

  private async remapNovelProgressIndexes(
    content: UnifiedContent,
    plan: ChapterOrderPlan,
    bookIds: string[]
  ): Promise<void> {
    if (plan.remaps.length === 0) {
      return;
    }
    const now = Date.now();
    const progressCaseSql = this.buildIndexCaseSql('chapterIndex', plan.remaps);
    const bookCaseSql = this.buildIndexCaseSql('lastReadChapterIndex', plan.remaps);
    const caseArgs = this.buildIndexCaseArgs(plan.remaps);

    for (let i = 0; i < bookIds.length; i++) {
      const bookId = bookIds[i];
      const progressArgs: DatabaseValue[] = [];
      for (let a = 0; a < caseArgs.length; a++) {
        progressArgs.push(caseArgs[a]);
      }
      progressArgs.push(now);
      progressArgs.push(bookId);
      await this.dbManager.executeSql(
        `UPDATE novel_read_progress SET chapterIndex = ${progressCaseSql}, updateTime = ? WHERE bookId = ?`,
        progressArgs
      );

      const bookArgs: DatabaseValue[] = [];
      for (let a = 0; a < caseArgs.length; a++) {
        bookArgs.push(caseArgs[a]);
      }
      bookArgs.push(now);
      bookArgs.push(bookId);
      await this.dbManager.executeSql(
        `UPDATE novel_book SET lastReadChapterIndex = ${bookCaseSql}, updateTime = ? WHERE id = ?`,
        bookArgs
      );
    }

    const originalBook = NovelAdapter.getOriginalNovel(content);
    const sourceId = content.sourceId || '';
    const bookUrl = originalBook !== null && originalBook.bookUrl.length > 0 ? originalBook.bookUrl : content.id;
    if (sourceId.length > 0 && bookUrl.length > 0) {
      const bookArgs: DatabaseValue[] = [];
      for (let a = 0; a < caseArgs.length; a++) {
        bookArgs.push(caseArgs[a]);
      }
      bookArgs.push(now);
      bookArgs.push(sourceId);
      bookArgs.push(bookUrl);
      await this.dbManager.executeSql(
        `UPDATE novel_book SET lastReadChapterIndex = ${bookCaseSql}, updateTime = ? WHERE sourceId = ? AND bookUrl = ?`,
        bookArgs
      );
    }
  }

  private buildIndexCaseSql(columnName: string, remaps: ChapterOrderIndexRemap[]): string {
    let sql = `CASE ${columnName}`;
    for (let i = 0; i < remaps.length; i++) {
      sql += ' WHEN ? THEN ?';
    }
    sql += ` ELSE ${columnName} END`;
    return sql;
  }

  private buildIndexCaseArgs(remaps: ChapterOrderIndexRemap[]): DatabaseValue[] {
    const args: DatabaseValue[] = [];
    for (let i = 0; i < remaps.length; i++) {
      args.push(remaps[i].oldIndex);
      args.push(remaps[i].newIndex);
    }
    return args;
  }

  private async migrateCachesAfterCommit(
    content: UnifiedContent,
    plan: ChapterOrderPlan
  ): Promise<ChapterOrderCacheRemapResult> {
    const result = this.createEmptyCacheResult();
    if (plan.remaps.length === 0) {
      return result;
    }

    try {
      if (plan.contentKind === ChapterOrderContentKind.NOVEL) {
        const bookIds = this.buildNovelBookIds(content);
        const novelCacheResult = await getNovelChapterCacheManager().remapChapterIndexCaches(bookIds, plan.remaps);
        this.mergeCacheResult(result, novelCacheResult);
        await this.rewriteNovelChapterListCaches(content, bookIds, plan);

        const remoteResult = getRemoteReadAloudCacheService().remapChapterIndexCaches(bookIds, plan.remaps);
        this.mergeCacheResult(result, remoteResult);
      } else if (plan.contentKind === ChapterOrderContentKind.EBOOK && this.isTxtEBook(content)) {
        const localTextBookIds = this.buildLocalTextEBookCacheIds(content);
        const novelCacheResult = await getNovelChapterCacheManager().remapChapterIndexCaches(localTextBookIds, plan.remaps);
        this.mergeCacheResult(result, novelCacheResult);

        const remoteResult = getRemoteReadAloudCacheService().remapChapterIndexCaches(localTextBookIds, plan.remaps);
        this.mergeCacheResult(result, remoteResult);
      }
    } catch (error) {
      logger.error(TAG, `章节缓存迁移失败: ${String(error)}`);
      for (let i = 0; i < plan.remaps.length; i++) {
        this.appendUniqueString(result.failedKeys, plan.remaps[i].stableKey);
      }
      result.warnings.push(`缓存迁移异常: ${String(error)}`);
    }

    return result;
  }

  private async rewriteNovelChapterListCaches(
    content: UnifiedContent,
    bookIds: string[],
    plan: ChapterOrderPlan
  ): Promise<void> {
    const reorderedChapters = this.buildReorderedLegadoChapters(content, plan);
    if (reorderedChapters.length === 0) {
      return;
    }
    for (let i = 0; i < bookIds.length; i++) {
      await getNovelChapterCacheManager().saveChapterList(bookIds[i], reorderedChapters);
    }
  }

  private buildReorderedLegadoChapters(content: UnifiedContent, plan: ChapterOrderPlan): LegadoChapter[] {
    const chapters: LegadoChapter[] = [];
    for (let i = 0; i < plan.items.length; i++) {
      const item = plan.items[i];
      const chapter = this.findChapterByStableKey(content.chapters, item.stableKey);
      if (chapter === null) {
        continue;
      }
      const original = NovelAdapter.getOriginalChapter(chapter);
      const legadoChapter: LegadoChapter = {
        id: original !== null ? original.id : chapter.id,
        bookUrl: original !== null ? original.bookUrl : content.id,
        url: original !== null ? original.url : chapter.id,
        title: chapter.title,
        index: item.newIndex,
        isVolume: original !== null ? original.isVolume : false,
        isVip: original !== null ? original.isVip : false,
        isPay: original !== null ? original.isPay : false,
        updateTime: original !== null ? original.updateTime : undefined,
        variable: original !== null ? original.variable : undefined,
        tag: original !== null ? original.tag : undefined
      };
      chapters.push(legadoChapter);
    }
    return chapters;
  }

  private resolveIdentity(content: UnifiedContent): ChapterOrderIdentity {
    let kind = ChapterOrderContentKind.EBOOK;
    if (content.contentType === UnifiedContentType.MANGA) {
      kind = content.isLocal ? ChapterOrderContentKind.LOCAL_MANGA : ChapterOrderContentKind.ONLINE_MANGA;
    } else if (content.contentType === UnifiedContentType.NOVEL) {
      kind = ChapterOrderContentKind.NOVEL;
    } else {
      kind = ChapterOrderContentKind.EBOOK;
    }

    const sourceId = this.resolveSourceId(content);
    const identity: ChapterOrderIdentity = {
      contentType: content.contentType,
      contentKind: kind,
      contentId: content.id,
      sourceId: sourceId
    };
    return identity;
  }

  private resolveSourceId(content: UnifiedContent): string {
    if (content.sourcePkg && content.sourcePkg.length > 0) {
      return content.sourcePkg;
    }
    if (content.sourceId && content.sourceId.length > 0) {
      return content.sourceId;
    }
    return 'local';
  }

  private buildStableRefs(chapters: UnifiedChapter[]): StableChapterRef[] {
    const refs: StableChapterRef[] = [];
    for (let i = 0; i < chapters.length; i++) {
      const chapter = chapters[i];
      const sourceIndex = this.resolveSourceIndex(chapter, i);
      const stableKey = this.buildStableKey(chapter, sourceIndex);
      const ref: StableChapterRef = {
        stableKey: stableKey,
        chapterId: chapter.id,
        title: chapter.title,
        sourceIndex: sourceIndex,
        chapter: chapter
      };
      refs.push(ref);
    }
    return refs;
  }

  private resolveSourceIndex(chapter: UnifiedChapter, fallback: number): number {
    if (Number.isFinite(chapter.index) && chapter.index >= 0) {
      return Math.floor(chapter.index);
    }
    return fallback;
  }

  private buildStableKey(chapter: UnifiedChapter, oldIndex: number): string {
    if (chapter.originalType === UnifiedContentType.MANGA) {
      const mangaChapter = MangaAdapter.getOriginalChapter(chapter);
      if (chapter.id.length > 0) {
        return `manga:id:${chapter.id}`;
      }
      if (mangaChapter !== null && mangaChapter.externalId && mangaChapter.externalId.length > 0) {
        return `manga:external:${mangaChapter.externalId}`;
      }
      const publish = mangaChapter !== null ? String(mangaChapter.publishDate) : '';
      return `manga:title:${chapter.title}:publish:${publish}:old:${oldIndex}`;
    }

    if (chapter.originalType === UnifiedContentType.NOVEL) {
      const novelChapter = NovelAdapter.getOriginalChapter(chapter);
      if (novelChapter !== null && novelChapter.url.length > 0) {
        return `novel:url:${novelChapter.url}`;
      }
      if (novelChapter !== null && novelChapter.id.length > 0) {
        return `novel:id:${novelChapter.id}`;
      }
      if (chapter.id.length > 0) {
        return `novel:chapter:${chapter.id}`;
      }
      return `novel:title:${chapter.title}:old:${oldIndex}`;
    }

    const ebookChapter = EBookAdapter.getOriginalChapter(chapter);
    if (ebookChapter !== null && ebookChapter.id.length > 0) {
      return `ebook:id:${ebookChapter.id}`;
    }
    if (ebookChapter !== null && ebookChapter.resourceHref && ebookChapter.resourceHref.length > 0) {
      return `ebook:href:${ebookChapter.resourceHref}`;
    }
    if (ebookChapter !== null && ebookChapter.resourceFile && ebookChapter.resourceFile.length > 0) {
      return `ebook:file:${ebookChapter.resourceFile}`;
    }
    if (chapter.id.length > 0) {
      return `ebook:chapter:${chapter.id}`;
    }
    return `ebook:title:${chapter.title}:old:${oldIndex}`;
  }

  private updateOriginalChapterIndex(chapter: UnifiedChapter, index: number): void {
    if (chapter.originalType === UnifiedContentType.MANGA) {
      const mangaChapter = MangaAdapter.getOriginalChapter(chapter);
      if (mangaChapter !== null) {
        mangaChapter.chapterNumber = index;
      }
    } else if (chapter.originalType === UnifiedContentType.NOVEL) {
      const novelChapter = NovelAdapter.getOriginalChapter(chapter);
      if (novelChapter !== null) {
        novelChapter.index = index;
      }
    } else if (chapter.originalType === UnifiedContentType.EBOOK) {
      const ebookChapter = EBookAdapter.getOriginalChapter(chapter);
      if (ebookChapter !== null) {
        ebookChapter.chapterNumber = index;
      }
    }
  }

  private cloneUnifiedChapter(chapter: UnifiedChapter, index: number): UnifiedChapter {
    const cloned: UnifiedChapter = {
      id: chapter.id,
      title: chapter.title,
      index: index,
      isRead: chapter.isRead,
      isDownloaded: chapter.isDownloaded,
      isBookmarked: chapter.isBookmarked,
      originalData: chapter.originalData,
      originalType: chapter.originalType
    };
    if (chapter.pageCount !== undefined) {
      cloned.pageCount = chapter.pageCount;
    }
    if (chapter.wordCount !== undefined) {
      cloned.wordCount = chapter.wordCount;
    }
    if (chapter.publishDate !== undefined) {
      cloned.publishDate = chapter.publishDate;
    }
    return cloned;
  }

  private remapContentLastReadIndex(content: UnifiedContent, rebuiltChapters: UnifiedChapter[]): number {
    const oldIndex = content.lastReadChapterIndex;
    if (!Number.isFinite(oldIndex) || oldIndex < 0 || oldIndex >= content.chapters.length) {
      return -1;
    }
    const oldChapter = content.chapters[Math.floor(oldIndex)];
    for (let i = 0; i < rebuiltChapters.length; i++) {
      if (rebuiltChapters[i].originalData === oldChapter.originalData) {
        return i;
      }
    }
    const oldStableKey = this.buildStableKey(oldChapter, this.resolveSourceIndex(oldChapter, Math.floor(oldIndex)));
    for (let i = 0; i < rebuiltChapters.length; i++) {
      const chapter = rebuiltChapters[i];
      const stableKey = this.buildStableKey(chapter, this.resolveSourceIndex(chapter, i));
      if (stableKey === oldStableKey) {
        return i;
      }
    }
    return -1;
  }

  private remapEBookDomPos(domPos: string, oldIndex: number, newIndex: number): EBookDomPosRemapResult {
    if (domPos.length === 0) {
      return { value: domPos, changed: false };
    }
    let value = domPos;
    let changed = false;
    const resourcePattern = new RegExp(`("resourceIndex"\\s*:\\s*)${oldIndex}(\\s*[,}])`);
    if (resourcePattern.test(value)) {
      value = value.replace(resourcePattern, (_match: string, prefix: string, suffix: string): string => {
        return `${prefix}${newIndex}${suffix}`;
      });
      changed = true;
    }
    const chapterPattern = new RegExp(`("chapterIndex"\\s*:\\s*)${oldIndex}(\\s*[,}])`);
    if (chapterPattern.test(value)) {
      value = value.replace(chapterPattern, (_match: string, prefix: string, suffix: string): string => {
        return `${prefix}${newIndex}${suffix}`;
      });
      changed = true;
    }
    return { value: value, changed: changed };
  }

  private buildNovelBookIds(content: UnifiedContent): string[] {
    const ids: string[] = [];
    this.appendUniqueString(ids, content.id);
    const originalBook = NovelAdapter.getOriginalNovel(content);
    const sourceId = content.sourceId || '';
    const bookUrl = originalBook !== null && originalBook.bookUrl.length > 0 ? originalBook.bookUrl : content.id;
    this.appendUniqueString(ids, bookUrl);
    if (sourceId.length > 0 && bookUrl.length > 0) {
      this.appendUniqueString(ids, `${sourceId}_${encodeURIComponent(bookUrl)}`);
    }
    return ids;
  }

  private buildLocalTextEBookCacheIds(content: UnifiedContent): string[] {
    const ids: string[] = [];
    this.appendUniqueString(ids, buildLocalTextNovelBookId(content.id));
    this.appendUniqueString(ids, content.id);
    return ids;
  }

  private isTxtEBook(content: UnifiedContent): boolean {
    const ebook = EBookAdapter.getOriginalEBook(content);
    if (ebook !== null && ebook.format === EBookFormat.TXT) {
      return true;
    }
    return content.format === EBookFormat.TXT || content.format === 'TXT';
  }

  private findRefByStableKey(refs: StableChapterRef[], stableKey: string): StableChapterRef | null {
    for (let i = 0; i < refs.length; i++) {
      if (refs[i].stableKey === stableKey) {
        return refs[i];
      }
    }
    return null;
  }

  private findStoredRowByStableKey(rows: StoredChapterOrderRow[], stableKey: string): StoredChapterOrderRow | null {
    for (let i = 0; i < rows.length; i++) {
      if (rows[i].stableKey === stableKey) {
        return rows[i];
      }
    }
    return null;
  }

  private findItemByStableKey(items: ChapterOrderItem[], stableKey: string): ChapterOrderItem | null {
    for (let i = 0; i < items.length; i++) {
      if (items[i].stableKey === stableKey) {
        return items[i];
      }
    }
    return null;
  }

  private findChapterByStableKey(chapters: UnifiedChapter[], stableKey: string): UnifiedChapter | null {
    for (let i = 0; i < chapters.length; i++) {
      const chapter = chapters[i];
      const chapterStableKey = this.buildStableKey(chapter, this.resolveSourceIndex(chapter, i));
      if (chapterStableKey === stableKey) {
        return chapter;
      }
    }
    return null;
  }

  private findRemapByChapterId(plan: ChapterOrderPlan, chapterId: string): ChapterOrderIndexRemap | null {
    if (chapterId.length === 0) {
      return null;
    }
    for (let i = 0; i < plan.items.length; i++) {
      const item = plan.items[i];
      if (item.chapterId === chapterId) {
        return this.findRemapByStableKey(plan.remaps, item.stableKey);
      }
    }
    return null;
  }

  private findRemapByStableKey(remaps: ChapterOrderIndexRemap[], stableKey: string): ChapterOrderIndexRemap | null {
    for (let i = 0; i < remaps.length; i++) {
      if (remaps[i].stableKey === stableKey) {
        return remaps[i];
      }
    }
    return null;
  }

  private findRemapByOldIndex(remaps: ChapterOrderIndexRemap[], oldIndex: number): ChapterOrderIndexRemap | null {
    for (let i = 0; i < remaps.length; i++) {
      if (remaps[i].oldIndex === oldIndex) {
        return remaps[i];
      }
    }
    return null;
  }

  private mergeCacheResult(target: ChapterOrderCacheRemapResult, source: ChapterOrderCacheRemapResult): void {
    target.textCacheMoved += source.textCacheMoved;
    target.audioCacheMoved += source.audioCacheMoved;
    target.remoteReadAloudCacheMoved += source.remoteReadAloudCacheMoved;
    for (let i = 0; i < source.failedKeys.length; i++) {
      this.appendUniqueString(target.failedKeys, source.failedKeys[i]);
    }
    for (let i = 0; i < source.warnings.length; i++) {
      target.warnings.push(source.warnings[i]);
    }
  }

  private createEmptyCacheResult(): ChapterOrderCacheRemapResult {
    return {
      textCacheMoved: 0,
      audioCacheMoved: 0,
      remoteReadAloudCacheMoved: 0,
      failedKeys: [],
      warnings: []
    };
  }

  private toSafeString(value: DatabaseValue | undefined): string {
    if (value === undefined || value === null) {
      return '';
    }
    return String(value);
  }

  private toSafeNumber(value: DatabaseValue | undefined, fallback: number): number {
    if (typeof value === 'number' && Number.isFinite(value)) {
      return Math.floor(value);
    }
    if (typeof value === 'string') {
      const parsed = Number(value);
      if (Number.isFinite(parsed)) {
        return Math.floor(parsed);
      }
    }
    return fallback;
  }

  private appendUniqueString(values: string[], value: string): void {
    if (value.length === 0) {
      return;
    }
    if (!this.stringArrayIncludes(values, value)) {
      values.push(value);
    }
  }

  private stringArrayIncludes(values: string[], target: string): boolean {
    for (let i = 0; i < values.length; i++) {
      if (values[i] === target) {
        return true;
      }
    }
    return false;
  }
}

export function getChapterOrderService(): ChapterOrderService {
  return ChapterOrderService.getInstance();
}
