import { logger } from '../../Utils/Logger';
import { DatabaseManager } from '../Database/DatabaseManager';
import { generateUUID } from '../Utils/UUIDGenerator';
import { UnifiedContentType } from '../../Models/UnifiedContentModels';
import {
  UnifiedAnnotationType,
  UnifiedAnnotationRecord,
  CreateBookmarkInput,
  CreateHighlightInput,
  CreateThoughtInput,
  AnnotationAnchor
} from '../../Models/AnnotationModels';
import { DatabaseRecord, DatabaseValue } from '../Database/DatabaseTypes';

const TAG = 'UnifiedAnnotationManager';

const CREATE_UNIFIED_ANNOTATION_TABLE_SQL = `
  CREATE TABLE IF NOT EXISTS unified_annotation (
    id TEXT PRIMARY KEY,
    contentType TEXT NOT NULL,
    contentId TEXT NOT NULL,
    annotationType TEXT NOT NULL,
    title TEXT DEFAULT '',
    textContent TEXT DEFAULT '',
    quoteText TEXT DEFAULT '',
    chapterId TEXT DEFAULT '',
    chapterTitle TEXT DEFAULT '',
    chapterIndex INTEGER DEFAULT -1,
    pageIndex INTEGER DEFAULT -1,
    pageProgress REAL DEFAULT -1,
    startOffset INTEGER DEFAULT -1,
    endOffset INTEGER DEFAULT -1,
    anchorJson TEXT DEFAULT '',
    styleJson TEXT DEFAULT '',
    linkedAnnotationId TEXT DEFAULT '',
    createTime INTEGER NOT NULL,
    updateTime INTEGER NOT NULL,
    isDeleted INTEGER DEFAULT 0
  )
`;

const CREATE_UNIFIED_ANNOTATION_INDEX_SQL: string[] = [
  'CREATE INDEX IF NOT EXISTS idx_unified_annotation_content ON unified_annotation (contentType, contentId, createTime DESC)',
  'CREATE INDEX IF NOT EXISTS idx_unified_annotation_type ON unified_annotation (annotationType, createTime DESC)',
  'CREATE INDEX IF NOT EXISTS idx_unified_annotation_linked ON unified_annotation (linkedAnnotationId)'
];

/**
 * Unified annotation manager (bookmark/highlight/thought).
 */
export class UnifiedAnnotationManager {
  private static instance: UnifiedAnnotationManager | null = null;
  private dbManager: DatabaseManager;
  private schemaReady: boolean = false;

  private constructor() {
    this.dbManager = DatabaseManager.getInstance();
  }

  static getInstance(): UnifiedAnnotationManager {
    if (!UnifiedAnnotationManager.instance) {
      UnifiedAnnotationManager.instance = new UnifiedAnnotationManager();
    }
    return UnifiedAnnotationManager.instance;
  }

  /**
   * Create a bookmark for manga/ebook/novel.
   */
  async createBookmark(input: CreateBookmarkInput): Promise<UnifiedAnnotationRecord> {
    const now = Date.now();
    const id = generateUUID();
    const anchor = input.anchor || {};
    const record: UnifiedAnnotationRecord = {
      id,
      contentType: input.contentType,
      contentId: input.contentId,
      annotationType: UnifiedAnnotationType.BOOKMARK,
      title: input.title ?? '',
      textContent: input.textContent ?? '',
      quoteText: anchor.quoteText ?? '',
      chapterId: anchor.chapterId ?? '',
      chapterTitle: anchor.chapterTitle ?? '',
      chapterIndex: this.normalizeIndex(anchor.chapterIndex),
      pageIndex: this.normalizeIndex(anchor.pageIndex),
      pageProgress: this.normalizeProgress(anchor.progress),
      startOffset: this.normalizeIndex(anchor.startOffset),
      endOffset: this.normalizeIndex(anchor.endOffset),
      anchor,
      styleJson: '',
      linkedAnnotationId: '',
      createdAt: now,
      updatedAt: now
    };

    await this.insertRecord(record);
    return record;
  }

  /**
   * Create a novel highlight annotation.
   */
  async createHighlight(input: CreateHighlightInput): Promise<UnifiedAnnotationRecord> {
    const now = Date.now();
    const id = generateUUID();
    const anchor = input.anchor || {};
    const styleJson = JSON.stringify(input.style);
    const record: UnifiedAnnotationRecord = {
      id,
      contentType: UnifiedContentType.NOVEL,
      contentId: input.contentId,
      annotationType: UnifiedAnnotationType.HIGHLIGHT,
      title: '',
      textContent: '',
      quoteText: anchor.quoteText ?? '',
      chapterId: anchor.chapterId ?? '',
      chapterTitle: anchor.chapterTitle ?? '',
      chapterIndex: this.normalizeIndex(anchor.chapterIndex),
      pageIndex: this.normalizeIndex(anchor.pageIndex),
      pageProgress: this.normalizeProgress(anchor.progress),
      startOffset: this.normalizeIndex(anchor.startOffset),
      endOffset: this.normalizeIndex(anchor.endOffset),
      anchor,
      styleJson,
      linkedAnnotationId: '',
      createdAt: now,
      updatedAt: now
    };

    await this.insertRecord(record);
    return record;
  }

  /**
   * Create a novel thought annotation.
   */
  async createThought(input: CreateThoughtInput): Promise<UnifiedAnnotationRecord> {
    const now = Date.now();
    const id = generateUUID();
    const anchor = input.anchor || {};
    const record: UnifiedAnnotationRecord = {
      id,
      contentType: UnifiedContentType.NOVEL,
      contentId: input.contentId,
      annotationType: UnifiedAnnotationType.THOUGHT,
      title: '',
      textContent: input.textContent ?? '',
      quoteText: anchor.quoteText ?? '',
      chapterId: anchor.chapterId ?? '',
      chapterTitle: anchor.chapterTitle ?? '',
      chapterIndex: this.normalizeIndex(anchor.chapterIndex),
      pageIndex: this.normalizeIndex(anchor.pageIndex),
      pageProgress: this.normalizeProgress(anchor.progress),
      startOffset: this.normalizeIndex(anchor.startOffset),
      endOffset: this.normalizeIndex(anchor.endOffset),
      anchor,
      styleJson: '',
      linkedAnnotationId: input.linkedAnnotationId ?? '',
      createdAt: now,
      updatedAt: now
    };

    await this.insertRecord(record);
    return record;
  }

  /**
   * List annotations for one content item.
   */
  async getContentAnnotations(
    contentType: UnifiedContentType,
    contentId: string,
    annotationType?: UnifiedAnnotationType
  ): Promise<UnifiedAnnotationRecord[]> {
    await this.ensureSchema();

    const conditions: string[] = ['isDeleted = 0', 'contentType = ?', 'contentId = ?'];
    const args: DatabaseValue[] = [contentType, contentId];
    if (annotationType) {
      conditions.push('annotationType = ?');
      args.push(annotationType);
    }
    const sql = `
      SELECT * FROM unified_annotation
      WHERE ${conditions.join(' AND ')}
      ORDER BY createTime DESC
    `;
    const rows = await this.dbManager.querySql(sql, args);
    return rows.map((row: DatabaseRecord) => this.parseRecord(row));
  }

  /**
   * Soft delete annotation by id.
   */
  async deleteAnnotation(annotationId: string): Promise<void> {
    await this.ensureSchema();
    await this.dbManager.executeSql(
      'UPDATE unified_annotation SET isDeleted = 1, updateTime = ? WHERE id = ?',
      [Date.now(), annotationId]
    );
  }

  private async insertRecord(record: UnifiedAnnotationRecord): Promise<void> {
    await this.ensureSchema();
    const sql = `
      INSERT INTO unified_annotation (
        id, contentType, contentId, annotationType, title, textContent, quoteText,
        chapterId, chapterTitle, chapterIndex, pageIndex, pageProgress,
        startOffset, endOffset, anchorJson, styleJson, linkedAnnotationId,
        createTime, updateTime, isDeleted
      ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, 0)
    `;
    await this.dbManager.executeSql(sql, [
      record.id,
      record.contentType,
      record.contentId,
      record.annotationType,
      record.title,
      record.textContent,
      record.quoteText,
      record.chapterId,
      record.chapterTitle,
      record.chapterIndex,
      record.pageIndex,
      record.pageProgress,
      record.startOffset,
      record.endOffset,
      JSON.stringify(record.anchor),
      record.styleJson,
      record.linkedAnnotationId,
      record.createdAt,
      record.updatedAt
    ]);
  }

  private async ensureSchema(): Promise<void> {
    if (this.schemaReady) {
      return;
    }
    await this.dbManager.executeSql(CREATE_UNIFIED_ANNOTATION_TABLE_SQL);
    for (const sql of CREATE_UNIFIED_ANNOTATION_INDEX_SQL) {
      try {
        await this.dbManager.executeSql(sql);
      } catch (_error) {
        // no-op: index maybe already exists
      }
    }
    this.schemaReady = true;
  }

  private parseRecord(row: DatabaseRecord): UnifiedAnnotationRecord {
    const rawAnchor = this.getStringValue(row, 'anchorJson', '{}');
    const anchor = this.parseAnchor(rawAnchor);
    const anchorChapterIndex = this.normalizeIndex(anchor.chapterIndex);
    const anchorPageIndex = this.normalizeIndex(anchor.pageIndex);
    const anchorProgress = this.normalizeProgress(anchor.progress);
    const anchorStartOffset = this.normalizeIndex(anchor.startOffset);
    const anchorEndOffset = this.normalizeIndex(anchor.endOffset);
    return {
      id: this.getStringValue(row, 'id', ''),
      contentType: this.getContentTypeValue(this.getStringValue(row, 'contentType', UnifiedContentType.MANGA)),
      contentId: this.getStringValue(row, 'contentId', ''),
      annotationType: this.getAnnotationTypeValue(this.getStringValue(row, 'annotationType', UnifiedAnnotationType.BOOKMARK)),
      title: this.getStringValue(row, 'title', ''),
      textContent: this.getStringValue(row, 'textContent', ''),
      quoteText: this.getStringValue(row, 'quoteText', ''),
      chapterId: this.getStringValue(row, 'chapterId', ''),
      chapterTitle: this.getStringValue(row, 'chapterTitle', ''),
      chapterIndex: this.getNumberValue(row, 'chapterIndex', anchorChapterIndex),
      pageIndex: this.getNumberValue(row, 'pageIndex', anchorPageIndex),
      pageProgress: this.getNumberValue(row, 'pageProgress', anchorProgress),
      startOffset: this.getNumberValue(row, 'startOffset', anchorStartOffset),
      endOffset: this.getNumberValue(row, 'endOffset', anchorEndOffset),
      anchor,
      styleJson: this.getStringValue(row, 'styleJson', ''),
      linkedAnnotationId: this.getStringValue(row, 'linkedAnnotationId', ''),
      createdAt: this.getNumberValue(row, 'createTime', 0),
      updatedAt: this.getNumberValue(row, 'updateTime', 0)
    };
  }

  private parseAnchor(raw: string): AnnotationAnchor {
    try {
      const parsed = JSON.parse(raw) as AnnotationAnchor;
      return parsed || {};
    } catch (_error) {
      return {};
    }
  }

  private getContentTypeValue(value: string): UnifiedContentType {
    if (value === UnifiedContentType.NOVEL) {
      return UnifiedContentType.NOVEL;
    }
    if (value === UnifiedContentType.EBOOK) {
      return UnifiedContentType.EBOOK;
    }
    return UnifiedContentType.MANGA;
  }

  private getAnnotationTypeValue(value: string): UnifiedAnnotationType {
    if (value === UnifiedAnnotationType.HIGHLIGHT) {
      return UnifiedAnnotationType.HIGHLIGHT;
    }
    if (value === UnifiedAnnotationType.THOUGHT) {
      return UnifiedAnnotationType.THOUGHT;
    }
    return UnifiedAnnotationType.BOOKMARK;
  }

  private getStringValue(record: DatabaseRecord, field: string, fallback: string): string {
    const raw = Reflect.get(record, field) as string | number | boolean | null | undefined;
    if (typeof raw === 'string') {
      return raw;
    }
    if (typeof raw === 'number' || typeof raw === 'boolean') {
      return String(raw);
    }
    return fallback;
  }

  private getNumberValue(record: DatabaseRecord, field: string, fallback: number): number {
    const raw = Reflect.get(record, field) as string | number | boolean | null | undefined;
    if (typeof raw === 'number') {
      return raw;
    }
    if (typeof raw === 'string') {
      const num = Number(raw);
      return Number.isFinite(num) ? num : fallback;
    }
    if (typeof raw === 'boolean') {
      return raw ? 1 : 0;
    }
    return fallback;
  }

  private normalizeIndex(value?: number): number {
    if (typeof value !== 'number' || !Number.isFinite(value)) {
      return -1;
    }
    return Math.max(-1, Math.floor(value));
  }

  private normalizeProgress(value?: number): number {
    if (typeof value !== 'number' || !Number.isFinite(value)) {
      return -1;
    }
    return Math.max(-1, Math.min(1, value));
  }
}

export function getUnifiedAnnotationManager(): UnifiedAnnotationManager {
  return UnifiedAnnotationManager.getInstance();
}
