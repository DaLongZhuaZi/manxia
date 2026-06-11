/**
 * 全局搜索本地摘要索引
 * 索引不可用时调用方必须回退旧查询，不能影响现有搜索语义。
 */

import { logger } from '../../Utils/Logger';
import { DatabaseManager } from '../Database/DatabaseManager';
import { CountQueryResult, DatabaseRecord, DatabaseValue, GenericQueryRecord } from '../Database/DatabaseTypes';

const TAG = 'GlobalSearchIndexManager';
const INDEX_BATCH_SIZE: number = 80;
const INDEX_BATCH_DELAY_MS: number = 25;
const MIN_TOKEN_LENGTH: number = 1;

export enum GlobalSearchLocalIndexContentType {
  MANGA = 'manga',
  EBOOK = 'ebook',
  NOVEL = 'novel'
}

export interface GlobalSearchIndexSummary {
  contentType: GlobalSearchLocalIndexContentType;
  contentId: string;
  title: string;
  author: string;
  description: string;
  coverUrl: string;
  sourceId: string;
  sourceName: string;
  updateTime: number;
}

export class GlobalSearchIndexManager {
  private static instance: GlobalSearchIndexManager | null = null;
  private dbManager: DatabaseManager = DatabaseManager.getInstance();
  private tablesReady: boolean = false;
  private reconcileRunning: boolean = false;

  private constructor() {}

  static getInstance(): GlobalSearchIndexManager {
    if (!GlobalSearchIndexManager.instance) {
      GlobalSearchIndexManager.instance = new GlobalSearchIndexManager();
    }
    return GlobalSearchIndexManager.instance;
  }

  async search(
    contentType: GlobalSearchLocalIndexContentType,
    keyword: string,
    limit: number
  ): Promise<GlobalSearchIndexSummary[] | null> {
    try {
      await this.ensureTables();
      const ready: boolean = await this.isReady();
      if (!ready) {
        this.requestBackgroundReconcile();
        return null;
      }

      const normalizedKeyword: string = keyword.trim().toLowerCase();
      if (normalizedKeyword.length === 0) {
        return [];
      }

      if (normalizedKeyword.length <= MIN_TOKEN_LENGTH) {
        return await this.searchByLike(contentType, normalizedKeyword, limit);
      }

      const tokens: string[] = this.tokenize(normalizedKeyword);
      if (tokens.length === 0) {
        return await this.searchByLike(contentType, normalizedKeyword, limit);
      }
      return await this.searchByTokens(contentType, tokens, limit);
    } catch (error) {
      logger.warn(TAG, `本地搜索索引查询失败，回退旧查询: ${String(error)}`);
      return null;
    }
  }

  requestBackgroundReconcile(): void {
    if (this.reconcileRunning) {
      return;
    }
    this.reconcileRunning = true;
    setTimeout(() => {
      void this.reconcileAll().then(() => {
        this.reconcileRunning = false;
      }).catch((error) => {
        this.reconcileRunning = false;
        logger.warn(TAG, `全局搜索索引后台回填失败: ${String(error)}`);
      });
    }, 0);
  }

  private async ensureTables(): Promise<void> {
    if (this.tablesReady) {
      return;
    }
    await this.dbManager.executeSql(`
      CREATE TABLE IF NOT EXISTS global_search_index (
        contentType TEXT NOT NULL,
        contentId TEXT NOT NULL,
        title TEXT NOT NULL,
        author TEXT DEFAULT '',
        tags TEXT DEFAULT '',
        coverUrl TEXT DEFAULT '',
        description TEXT DEFAULT '',
        sourceId TEXT DEFAULT '',
        sourceName TEXT DEFAULT '',
        sourcePkg TEXT DEFAULT '',
        updateTime INTEGER DEFAULT 0,
        isReady INTEGER DEFAULT 0,
        PRIMARY KEY(contentType, contentId)
      )
    `);
    await this.dbManager.executeSql(`
      CREATE TABLE IF NOT EXISTS global_search_token_index (
        token TEXT NOT NULL,
        contentType TEXT NOT NULL,
        contentId TEXT NOT NULL,
        weight INTEGER DEFAULT 1,
        PRIMARY KEY(token, contentType, contentId)
      )
    `);
    await this.dbManager.executeSql('CREATE INDEX IF NOT EXISTS idx_global_search_index_type_ready ON global_search_index (contentType, isReady, updateTime)');
    await this.dbManager.executeSql('CREATE INDEX IF NOT EXISTS idx_global_search_token_token ON global_search_token_index (token)');
    await this.dbManager.executeSql('CREATE INDEX IF NOT EXISTS idx_global_search_token_content ON global_search_token_index (contentType, contentId)');
    this.tablesReady = true;
  }

  private async isReady(): Promise<boolean> {
    const result: CountQueryResult | null = await this.dbManager.queryAggregation<CountQueryResult>(
      'SELECT COUNT(*) as count FROM global_search_index WHERE isReady = 1'
    );
    return result !== null && result.count > 0;
  }

  private async searchByLike(
    contentType: GlobalSearchLocalIndexContentType,
    keyword: string,
    limit: number
  ): Promise<GlobalSearchIndexSummary[]> {
    const pattern: string = `%${keyword}%`;
    const sql: string = `
      SELECT contentType, contentId, title, author, description, coverUrl, sourceId, updateTime
      FROM global_search_index
      WHERE isReady = 1
        AND contentType = ?
        AND (LOWER(title) LIKE ? OR LOWER(author) LIKE ? OR LOWER(tags) LIKE ? OR LOWER(description) LIKE ?)
      ORDER BY updateTime DESC
      LIMIT ?
    `;
    const records: DatabaseRecord[] = await this.dbManager.querySql(sql, [contentType, pattern, pattern, pattern, pattern, limit]);
    return this.convertRecords(records, contentType);
  }

  private async searchByTokens(
    contentType: GlobalSearchLocalIndexContentType,
    tokens: string[],
    limit: number
  ): Promise<GlobalSearchIndexSummary[]> {
    const bindArgs: DatabaseValue[] = [contentType];
    const placeholders: string[] = [];
    for (const token of tokens) {
      placeholders.push('?');
      bindArgs.push(token);
    }
    bindArgs.push(limit);

    const sql: string = `
      SELECT i.contentType, i.contentId, i.title, i.author, i.description, i.coverUrl, i.sourceId, i.updateTime
      FROM global_search_index i
      INNER JOIN global_search_token_index t
        ON i.contentType = t.contentType AND i.contentId = t.contentId
      WHERE i.isReady = 1
        AND i.contentType = ?
        AND t.token IN (${placeholders.join(',')})
      GROUP BY i.contentType, i.contentId
      ORDER BY SUM(t.weight) DESC, i.updateTime DESC
      LIMIT ?
    `;
    const records: DatabaseRecord[] = await this.dbManager.querySql(sql, bindArgs);
    return this.convertRecords(records, contentType);
  }

  private async reconcileAll(): Promise<void> {
    await this.ensureTables();
    logger.info(TAG, '开始后台回填全局搜索本地索引');
    await this.dbManager.executeSql('DELETE FROM global_search_token_index');
    await this.dbManager.executeSql('DELETE FROM global_search_index');
    await this.reconcileManga();
    await this.reconcileEBooks();
    await this.dbManager.executeSql('UPDATE global_search_index SET isReady = 1');
    logger.info(TAG, '全局搜索本地索引后台回填完成');
  }

  private async reconcileManga(): Promise<void> {
    let offset: number = 0;
    while (true) {
      const records: DatabaseRecord[] = await this.dbManager.querySql(
        `SELECT id, title, author, description, coverUrl, sourceId, tags, lastUpdateTime
         FROM comic_info
         ORDER BY lastUpdateTime DESC
         LIMIT ? OFFSET ?`,
        [INDEX_BATCH_SIZE, offset]
      );
      if (records.length === 0) {
        return;
      }
      for (const record of records) {
        const generic: GenericQueryRecord = record as GenericQueryRecord;
        const summary: GlobalSearchIndexSummary = {
          contentType: GlobalSearchLocalIndexContentType.MANGA,
          contentId: this.readString(generic.id),
          title: this.readString(generic.title),
          author: this.readString(generic.author),
          description: this.readString(generic.description),
          coverUrl: this.readString(generic.coverUrl),
          sourceId: this.readString(generic.sourceId),
          sourceName: '本地漫画',
          updateTime: this.readNumber(generic.lastUpdateTime)
        };
        await this.upsertSummary(summary, this.readString(generic.tags));
      }
      offset += records.length;
      await this.sleep(INDEX_BATCH_DELAY_MS);
    }
  }

  private async reconcileEBooks(): Promise<void> {
    let offset: number = 0;
    while (true) {
      const records: DatabaseRecord[] = await this.dbManager.querySql(
        `SELECT id, title, author, description, coverImagePath, tags, lastUpdateTime
         FROM ebook_info
         ORDER BY lastUpdateTime DESC
         LIMIT ? OFFSET ?`,
        [INDEX_BATCH_SIZE, offset]
      );
      if (records.length === 0) {
        return;
      }
      for (const record of records) {
        const generic: GenericQueryRecord = record as GenericQueryRecord;
        const summary: GlobalSearchIndexSummary = {
          contentType: GlobalSearchLocalIndexContentType.EBOOK,
          contentId: this.readString(generic.id),
          title: this.readString(generic.title),
          author: this.readString(generic.author),
          description: this.readString(generic.description),
          coverUrl: this.readString(generic.coverImagePath),
          sourceId: 'local-ebook',
          sourceName: '本地电子书',
          updateTime: this.readNumber(generic.lastUpdateTime)
        };
        await this.upsertSummary(summary, this.readString(generic.tags));
      }
      offset += records.length;
      await this.sleep(INDEX_BATCH_DELAY_MS);
    }
  }

  private async upsertSummary(summary: GlobalSearchIndexSummary, tags: string): Promise<void> {
    if (summary.contentId.length === 0 || summary.title.length === 0) {
      return;
    }
    await this.dbManager.executeSql(
      `INSERT OR REPLACE INTO global_search_index
       (contentType, contentId, title, author, tags, coverUrl, description, sourceId, sourceName, sourcePkg, updateTime, isReady)
       VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, '', ?, 0)`,
      [
        summary.contentType,
        summary.contentId,
        summary.title,
        summary.author,
        tags,
        summary.coverUrl,
        summary.description,
        summary.sourceId,
        summary.sourceName,
        summary.updateTime
      ]
    );

    const tokens: string[] = this.tokenize(`${summary.title} ${summary.author} ${tags}`);
    for (const token of tokens) {
      await this.dbManager.executeSql(
        `INSERT OR REPLACE INTO global_search_token_index
         (token, contentType, contentId, weight)
         VALUES (?, ?, ?, ?)`,
        [token, summary.contentType, summary.contentId, token.length > 1 ? 2 : 1]
      );
    }
  }

  private convertRecords(
    records: DatabaseRecord[],
    fallbackType: GlobalSearchLocalIndexContentType
  ): GlobalSearchIndexSummary[] {
    const summaries: GlobalSearchIndexSummary[] = [];
    for (const record of records) {
      const generic: GenericQueryRecord = record as GenericQueryRecord;
      const contentTypeValue: string = this.readString(generic.contentType);
      const contentType: GlobalSearchLocalIndexContentType =
        contentTypeValue === GlobalSearchLocalIndexContentType.EBOOK ?
          GlobalSearchLocalIndexContentType.EBOOK :
          contentTypeValue === GlobalSearchLocalIndexContentType.NOVEL ?
            GlobalSearchLocalIndexContentType.NOVEL :
            fallbackType;
      const sourceName: string = contentType === GlobalSearchLocalIndexContentType.EBOOK ? '本地电子书' : '本地漫画';
      const summary: GlobalSearchIndexSummary = {
        contentType: contentType,
        contentId: this.readString(generic.contentId),
        title: this.readString(generic.title),
        author: this.readString(generic.author),
        description: this.readString(generic.description),
        coverUrl: this.readString(generic.coverUrl),
        sourceId: this.readString(generic.sourceId),
        sourceName: sourceName,
        updateTime: this.readNumber(generic.updateTime)
      };
      summaries.push(summary);
    }
    return summaries;
  }

  private tokenize(text: string): string[] {
    const normalized: string = text.trim().toLowerCase();
    const tokens: string[] = [];
    let word: string = '';
    for (let i = 0; i < normalized.length; i++) {
      const code: number = normalized.charCodeAt(i);
      const char: string = normalized.charAt(i);
      if ((code >= 48 && code <= 57) || (code >= 97 && code <= 122)) {
        word += char;
      } else {
        if (word.length > 0 && tokens.indexOf(word) < 0) {
          tokens.push(word);
        }
        word = '';
        if (this.isCjkCode(code)) {
          const nextIndex: number = i + 1;
          if (nextIndex < normalized.length && this.isCjkCode(normalized.charCodeAt(nextIndex))) {
            const gram: string = normalized.substring(i, i + 2);
            if (tokens.indexOf(gram) < 0) {
              tokens.push(gram);
            }
          } else if (tokens.indexOf(char) < 0) {
            tokens.push(char);
          }
        }
      }
    }
    if (word.length > 0 && tokens.indexOf(word) < 0) {
      tokens.push(word);
    }
    return tokens;
  }

  private isCjkCode(code: number): boolean {
    return code >= 0x4E00 && code <= 0x9FFF;
  }

  private readString(value: DatabaseValue | undefined): string {
    if (value === null || value === undefined) {
      return '';
    }
    return String(value);
  }

  private readNumber(value: DatabaseValue | undefined): number {
    if (value === null || value === undefined) {
      return 0;
    }
    const numberValue: number = Number(value);
    return isNaN(numberValue) ? 0 : numberValue;
  }

  private async sleep(durationMs: number): Promise<void> {
    return new Promise<void>((resolve) => {
      setTimeout(resolve, durationMs);
    });
  }
}

export function getGlobalSearchIndexManager(): GlobalSearchIndexManager {
  return GlobalSearchIndexManager.getInstance();
}
