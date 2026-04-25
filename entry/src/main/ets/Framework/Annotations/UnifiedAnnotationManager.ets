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
  AnnotationAnchor,
  HighlightStyle
} from '../../Models/AnnotationModels';
import { DatabaseRecord, DatabaseValue } from '../Database/DatabaseTypes';

const TAG = 'UnifiedAnnotationManager';

interface NormalizedAnchorSnapshot {
  chapterId: string;
  chapterIndex: number;
  pageIndex: number;
  startOffset: number;
  endOffset: number;
  quoteText: string;
}

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
    await this.ensureSchema();
    const anchor = input.anchor || {};
    const existing = await this.findLatestByAnchor(
      input.contentType,
      input.contentId,
      UnifiedAnnotationType.BOOKMARK,
      anchor
    );
    if (existing) {
      const nextTitle = input.title ?? existing.title;
      const nextText = input.textContent ?? existing.textContent;
      if (nextTitle !== existing.title || nextText !== existing.textContent) {
        await this.updateAnnotationText(existing.id, nextTitle, nextText);
      }
      existing.title = nextTitle;
      existing.textContent = nextText;
      existing.updatedAt = Date.now();
      logger.info(TAG, `命中书签去重规则，复用已有书签: id=${existing.id}, contentId=${input.contentId}`);
      return existing;
    }

    const now = Date.now();
    const id = generateUUID();
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
   * Create a highlight annotation.
   */
  async createHighlight(input: CreateHighlightInput): Promise<UnifiedAnnotationRecord> {
    await this.ensureSchema();
    const anchor = input.anchor || {};
    const styleJson = JSON.stringify(input.style);
    const contentType = input.contentType ?? UnifiedContentType.NOVEL;
    const existing = await this.findLatestByAnchor(
      contentType,
      input.contentId,
      UnifiedAnnotationType.HIGHLIGHT,
      anchor
    );
    if (existing) {
      if (existing.styleJson !== styleJson) {
        await this.updateHighlightStyle(existing.id, input.style);
        existing.styleJson = styleJson;
        existing.updatedAt = Date.now();
      }
      logger.info(TAG, `命中划线去重规则，复用已有划线: id=${existing.id}, contentId=${input.contentId}`);
      return existing;
    }

    const now = Date.now();
    const id = generateUUID();
    const record: UnifiedAnnotationRecord = {
      id,
      contentType,
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
   * Create a thought annotation.
   */
  async createThought(input: CreateThoughtInput): Promise<UnifiedAnnotationRecord> {
    await this.ensureSchema();
    const anchor = input.anchor || {};
    const safeText = input.textContent ?? '';
    const linkedId = input.linkedAnnotationId ? input.linkedAnnotationId.trim() : '';
    const contentType = input.contentType ?? UnifiedContentType.NOVEL;

    if (linkedId.length > 0) {
      const linkedThought = await this.getLinkedThoughtByHighlightId(
        contentType,
        input.contentId,
        linkedId
      );
      if (linkedThought) {
        if (linkedThought.textContent !== safeText) {
          await this.updateAnnotationText(linkedThought.id, linkedThought.title || '', safeText);
          linkedThought.textContent = safeText;
          linkedThought.updatedAt = Date.now();
        }
        logger.info(TAG, `命中关联想法去重规则，复用已有想法: id=${linkedThought.id}, linked=${linkedId}`);
        return linkedThought;
      }
    } else {
      const existing = await this.findLatestByAnchor(
        contentType,
        input.contentId,
        UnifiedAnnotationType.THOUGHT,
        anchor
      );
      if (existing) {
        if (existing.textContent !== safeText && safeText.trim().length > 0) {
          await this.updateAnnotationText(existing.id, existing.title || '', safeText);
          existing.textContent = safeText;
          existing.updatedAt = Date.now();
        }
        logger.info(TAG, `命中想法去重规则，复用已有想法: id=${existing.id}, contentId=${input.contentId}`);
        return existing;
      }
    }

    const now = Date.now();
    const id = generateUUID();
    const record: UnifiedAnnotationRecord = {
      id,
      contentType,
      contentId: input.contentId,
      annotationType: UnifiedAnnotationType.THOUGHT,
      title: '',
      textContent: safeText,
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
      linkedAnnotationId: linkedId,
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
    annotationType?: UnifiedAnnotationType,
    chapterId?: string,
    chapterIndex?: number
  ): Promise<UnifiedAnnotationRecord[]> {
    await this.ensureSchema();

    const conditions: string[] = ['isDeleted = 0', 'contentType = ?', 'contentId = ?'];
    const args: DatabaseValue[] = [contentType, contentId];
    if (annotationType) {
      const variants = this.getAnnotationTypeVariants(annotationType);
      const placeholders = variants.map(() => '?').join(', ');
      conditions.push(`annotationType IN (${placeholders})`);
      for (let i = 0; i < variants.length; i++) {
        args.push(variants[i]);
      }
    }
    if (chapterId && chapterId.trim().length > 0) {
      conditions.push('chapterId = ?');
      args.push(chapterId.trim());
    } else if (typeof chapterIndex === 'number' && Number.isFinite(chapterIndex) && chapterIndex >= 0) {
      conditions.push('chapterIndex = ?');
      args.push(Math.floor(chapterIndex));
    }
    const sql = `
      SELECT * FROM unified_annotation
      WHERE ${conditions.join(' AND ')}
      ORDER BY createTime DESC
    `;
    const rows = await this.dbManager.querySql(sql, args);
    const parsed: UnifiedAnnotationRecord[] = [];
    for (let i = 0; i < rows.length; i++) {
      parsed.push(this.parseRecord(rows[i]));
    }
    return parsed;
  }

  /**
   * List annotations for all contents.
   */
  async getAllAnnotations(annotationType?: UnifiedAnnotationType): Promise<UnifiedAnnotationRecord[]> {
    await this.ensureSchema();

    const conditions: string[] = ['isDeleted = 0'];
    const args: DatabaseValue[] = [];
    if (annotationType) {
      const variants = this.getAnnotationTypeVariants(annotationType);
      const placeholders = variants.map(() => '?').join(', ');
      conditions.push(`annotationType IN (${placeholders})`);
      for (let i = 0; i < variants.length; i++) {
        args.push(variants[i]);
      }
    }
    const sql = `
      SELECT * FROM unified_annotation
      WHERE ${conditions.join(' AND ')}
      ORDER BY createTime DESC
    `;
    const rows = await this.dbManager.querySql(sql, args);
    const parsed: UnifiedAnnotationRecord[] = [];
    for (let i = 0; i < rows.length; i++) {
      parsed.push(this.parseRecord(rows[i]));
    }
    return parsed;
  }

  async getAnnotationById(annotationId: string): Promise<UnifiedAnnotationRecord | null> {
    await this.ensureSchema();
    if (!annotationId || annotationId.trim().length <= 0) {
      return null;
    }
    const rows = await this.dbManager.querySql(
      'SELECT * FROM unified_annotation WHERE id = ? AND isDeleted = 0 LIMIT 1',
      [annotationId.trim()]
    );
    if (rows.length <= 0) {
      return null;
    }
    return this.parseRecord(rows[0]);
  }

  async getLinkedThoughtByHighlightId(
    contentType: UnifiedContentType,
    contentId: string,
    highlightId: string
  ): Promise<UnifiedAnnotationRecord | null> {
    await this.ensureSchema();
    if (!highlightId || highlightId.trim().length <= 0) {
      return null;
    }
    const typeVariants = this.getAnnotationTypeVariants(UnifiedAnnotationType.THOUGHT);
    const placeholders = typeVariants.map(() => '?').join(', ');
    const sql = `
      SELECT * FROM unified_annotation
      WHERE isDeleted = 0
        AND contentType = ?
        AND contentId = ?
        AND linkedAnnotationId = ?
        AND annotationType IN (${placeholders})
      ORDER BY createTime DESC
      LIMIT 1
    `;
    const args: DatabaseValue[] = [contentType, contentId, highlightId.trim()];
    for (let i = 0; i < typeVariants.length; i++) {
      args.push(typeVariants[i]);
    }
    const rows = await this.dbManager.querySql(sql, args);
    if (rows.length <= 0) {
      return null;
    }
    return this.parseRecord(rows[0]);
  }

  async createHighlightWithThoughtTransaction(
    highlightInput: CreateHighlightInput,
    thoughtInput?: CreateThoughtInput
  ): Promise<UnifiedAnnotationRecord> {
    await this.ensureSchema();
    await this.dbManager.beginTransaction();
    try {
      const highlight = await this.createHighlight(highlightInput);
      if (thoughtInput) {
        const thoughtPayload: CreateThoughtInput = {
          contentType: thoughtInput.contentType ?? highlightInput.contentType,
          contentId: thoughtInput.contentId,
          anchor: thoughtInput.anchor,
          textContent: thoughtInput.textContent ?? '',
          linkedAnnotationId: highlight.id
        };
        await this.createThought(thoughtPayload);
      }
      await this.dbManager.commit();
      return highlight;
    } catch (error) {
      await this.dbManager.rollBack();
      throw error as Error;
    }
  }

  /**
   * Soft delete annotation by id.
   */
  async deleteAnnotation(annotationId: string): Promise<void> {
    await this.ensureSchema();
    const now = Date.now();
    await this.dbManager.executeSql(
      'UPDATE unified_annotation SET isDeleted = 1, updateTime = ? WHERE id = ?',
      [now, annotationId]
    );
    // 删除划线时，级联软删除其关联想法，避免出现孤儿想法记录。
    await this.dbManager.executeSql(
      'UPDATE unified_annotation SET isDeleted = 1, updateTime = ? WHERE linkedAnnotationId = ? AND isDeleted = 0',
      [now, annotationId]
    );
  }

  async deleteContentAnnotations(contentType: UnifiedContentType, contentId: string): Promise<void> {
    await this.ensureSchema();
    await this.dbManager.executeSql(
      'UPDATE unified_annotation SET isDeleted = 1, updateTime = ? WHERE contentType = ? AND contentId = ? AND isDeleted = 0',
      [Date.now(), contentType, contentId]
    );
  }

  async updateHighlightStyle(annotationId: string, style: HighlightStyle): Promise<void> {
    await this.ensureSchema();
    const styleJson = JSON.stringify(style);
    await this.dbManager.executeSql(
      'UPDATE unified_annotation SET styleJson = ?, updateTime = ? WHERE id = ? AND annotationType = ? AND isDeleted = 0',
      [styleJson, Date.now(), annotationId, UnifiedAnnotationType.HIGHLIGHT]
    );
  }

  async updateAnnotationText(annotationId: string, title: string, textContent: string): Promise<void> {
    await this.ensureSchema();
    await this.dbManager.executeSql(
      'UPDATE unified_annotation SET title = ?, textContent = ?, updateTime = ? WHERE id = ? AND isDeleted = 0',
      [title, textContent, Date.now(), annotationId]
    );
  }

  private getAnnotationTypeVariants(annotationType: UnifiedAnnotationType): string[] {
    if (annotationType === UnifiedAnnotationType.HIGHLIGHT) {
      return ['highlight', UnifiedAnnotationType.HIGHLIGHT, '1', '划线', 'underline'];
    }
    if (annotationType === UnifiedAnnotationType.THOUGHT) {
      return ['thought', UnifiedAnnotationType.THOUGHT, '2', '想法', 'note'];
    }
    return ['bookmark', UnifiedAnnotationType.BOOKMARK, '0', '书签'];
  }

  private normalizeAnchorSnapshot(anchor: AnnotationAnchor): NormalizedAnchorSnapshot {
    const chapterId = anchor.chapterId ? anchor.chapterId.trim() : '';
    const quoteText = anchor.quoteText ? anchor.quoteText.trim() : '';
    return {
      chapterId,
      chapterIndex: this.normalizeIndex(anchor.chapterIndex),
      pageIndex: this.normalizeIndex(anchor.pageIndex),
      startOffset: this.normalizeIndex(anchor.startOffset),
      endOffset: this.normalizeIndex(anchor.endOffset),
      quoteText
    };
  }

  private async findLatestByAnchor(
    contentType: UnifiedContentType,
    contentId: string,
    annotationType: UnifiedAnnotationType,
    anchor: AnnotationAnchor
  ): Promise<UnifiedAnnotationRecord | null> {
    await this.ensureSchema();
    const normalized = this.normalizeAnchorSnapshot(anchor);
    const variants = this.getAnnotationTypeVariants(annotationType);
    const conditions: string[] = ['isDeleted = 0', 'contentType = ?', 'contentId = ?'];
    const args: DatabaseValue[] = [contentType, contentId];
    const placeholders = variants.map(() => '?').join(', ');
    conditions.push(`annotationType IN (${placeholders})`);
    for (let i = 0; i < variants.length; i++) {
      args.push(variants[i]);
    }

    if (normalized.chapterId.length > 0) {
      conditions.push('chapterId = ?');
      args.push(normalized.chapterId);
    } else if (normalized.chapterIndex >= 0) {
      conditions.push('chapterIndex = ?');
      args.push(normalized.chapterIndex);
    }

    if (normalized.startOffset >= 0 && normalized.endOffset >= normalized.startOffset) {
      conditions.push('startOffset = ?');
      conditions.push('endOffset = ?');
      args.push(normalized.startOffset);
      args.push(normalized.endOffset);
    } else if (normalized.pageIndex >= 0) {
      conditions.push('pageIndex = ?');
      args.push(normalized.pageIndex);
    }

    if (normalized.quoteText.length > 0) {
      conditions.push('quoteText = ?');
      args.push(normalized.quoteText);
    }

    const sql = `
      SELECT * FROM unified_annotation
      WHERE ${conditions.join(' AND ')}
      ORDER BY createTime DESC
      LIMIT 1
    `;
    const rows = await this.dbManager.querySql(sql, args);
    if (rows.length <= 0) {
      return null;
    }
    return this.parseRecord(rows[0]);
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
    const normalized = value
      .trim()
      .toLowerCase()
      .replace(/\s+/g, '')
      .replace(/_/g, '')
      .replace(/-/g, '');
    if (
      normalized === UnifiedAnnotationType.HIGHLIGHT ||
      normalized === 'highlight' ||
      normalized === '1' ||
      normalized === '划线' ||
      normalized === 'underline'
    ) {
      return UnifiedAnnotationType.HIGHLIGHT;
    }
    if (
      normalized === UnifiedAnnotationType.THOUGHT ||
      normalized === 'thought' ||
      normalized === 'note' ||
      normalized === '2' ||
      normalized === '想法'
    ) {
      return UnifiedAnnotationType.THOUGHT;
    }
    if (
      normalized === UnifiedAnnotationType.BOOKMARK ||
      normalized === 'bookmark' ||
      normalized === '0' ||
      normalized === '书签'
    ) {
      return UnifiedAnnotationType.BOOKMARK;
    }
    logger.warn(TAG, `无法识别的 annotationType 值，已按书签处理: raw=${value}, normalized=${normalized}`);
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
