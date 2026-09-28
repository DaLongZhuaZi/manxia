import { pdfService } from '@kit.PDFKit';
import { common } from '@kit.AbilityKit';
import { util } from '@kit.ArkTS';
import { logger } from 'manxia_core/src/main/ets/Utils/Logger';
import { SafeFileUtils } from 'manxia_core/src/main/ets/Utils/SafeFileUtils';
import { SafeUtils } from 'manxia_core/src/main/ets/Utils/SafeUtils';
import fs from '@ohos.file.fs';

const TAG: string = 'PdfTextIndexService';
const INDEX_DIR_NAME: string = 'pdf_text_index';
const EMPTY_PAGE_PROBE_LIMIT: number = 5;
const MAX_STORED_CHARS: number = 20000000;
const MAX_HITS: number = 300;
const SNIPPET_RADIUS: number = 28;

export interface PdfTextIndexDocument {
  bookId: string;
  pageCount: number;
  hasTextLayer: boolean;
  buildTime: number;
  totalChars: number;
  pages: string[];
}

export interface PdfTextSearchHit {
  pageIndex: number;
  snippet: string;
}

export class PdfTextIndexService {
  private static instance: PdfTextIndexService | null = null;

  public static getInstance(): PdfTextIndexService {
    if (!PdfTextIndexService.instance) {
      PdfTextIndexService.instance = new PdfTextIndexService();
    }
    return PdfTextIndexService.instance;
  }

  private resolveIndexDir(ctx: common.UIAbilityContext): string {
    return ctx.filesDir + '/' + INDEX_DIR_NAME;
  }

  private resolveIndexPath(ctx: common.UIAbilityContext, bookId: string): string {
    return this.resolveIndexDir(ctx) + '/' + bookId + '.json';
  }

  public hasIndex(ctx: common.UIAbilityContext, bookId: string): boolean {
    try {
      return SafeFileUtils.accessSync(this.resolveIndexPath(ctx, bookId));
    } catch (_error) {
      return false;
    }
  }

  /**
   * 抽取 PDF 每页文本并落盘为索引。图片型（无文本层）PDF 只记录 hasTextLayer=false。
   */
  public async buildIndex(
    ctx: common.UIAbilityContext,
    bookId: string,
    filePath: string,
    onProgress?: (pageIndex: number, pageCount: number) => void
  ): Promise<boolean> {
    if (bookId.length <= 0 || filePath.length <= 0) {
      return false;
    }
    const pageTexts: string[] = [];
    let pageCount: number = 0;
    let emptyProbe: number = 0;
    let hasTextLayer: boolean = false;
    let totalChars: number = 0;
    const doc: pdfService.PdfDocument = new pdfService.PdfDocument();
    try {
      const loadResult: pdfService.ParseResult = doc.loadDocument(filePath);
      if (loadResult !== pdfService.ParseResult.PARSE_SUCCESS) {
        logger.warn(TAG, 'buildIndex load failed: bookId=' + bookId + ', result=' + String(loadResult));
        return false;
      }
      pageCount = doc.getPageCount();
      for (let i = 0; i < pageCount; i++) {
        let pageText: string = '';
        try {
          pageText = doc.getPage(i).getTextContent() ?? '';
        } catch (_pageError) {
          pageText = '';
        }
        const normalized: string = pageText.replace(/\s+/g, ' ').trim();
        if (normalized.length > 0) {
          hasTextLayer = true;
        } else if (!hasTextLayer) {
          emptyProbe = emptyProbe + 1;
          if (emptyProbe >= EMPTY_PAGE_PROBE_LIMIT) {
            logger.info(TAG, 'buildIndex detected image-only pdf: bookId=' + bookId + ', probedPages=' + emptyProbe);
            break;
          }
        }
        if (totalChars < MAX_STORED_CHARS) {
          pageTexts.push(normalized);
          totalChars = totalChars + normalized.length;
        } else {
          pageTexts.push('');
        }
        if (onProgress && (i % 16 === 0)) {
          onProgress(i, pageCount);
        }
      }
    } catch (error) {
      logger.warn(TAG, 'buildIndex exception: bookId=' + bookId + ', error=' + String(error));
      try {
        doc.releaseDocument();
      } catch (_releaseError) {
      }
      return false;
    }
    try {
      doc.releaseDocument();
    } catch (_releaseError) {
    }

    const indexDoc: PdfTextIndexDocument = {
      bookId: bookId,
      pageCount: pageCount,
      hasTextLayer: hasTextLayer,
      buildTime: Date.now(),
      totalChars: totalChars,
      pages: pageTexts
    };
    try {
      const dir: string = this.resolveIndexDir(ctx);
      try {
        SafeFileUtils.mkdirSync(dir, true);
      } catch (_mkdirError) {
      }
      const target: string = this.resolveIndexPath(ctx, bookId);
      try {
        SafeFileUtils.unlinkSync(target);
      } catch (_unlinkError) {
      }
      const file = fs.openSync(target, fs.OpenMode.READ_WRITE | fs.OpenMode.CREATE);
      fs.writeSync(file.fd, JSON.stringify(indexDoc));
      fs.closeSync(file);
      logger.info(TAG, 'buildIndex done: bookId=' + bookId + ', pages=' + pageCount + ', hasTextLayer=' + hasTextLayer + ', chars=' + totalChars);
      return true;
    } catch (error) {
      logger.warn(TAG, 'buildIndex write failed: bookId=' + bookId + ', error=' + String(error));
      return false;
    }
  }

  private loadIndex(ctx: common.UIAbilityContext, bookId: string): PdfTextIndexDocument | null {
    try {
      const path: string = this.resolveIndexPath(ctx, bookId);
      if (!SafeFileUtils.accessSync(path)) {
        return null;
      }
      const file = SafeFileUtils.openSync(path, fs.OpenMode.READ_ONLY);
      const stat = SafeFileUtils.statSync(path);
      const buffer = new ArrayBuffer(stat.size);
      SafeFileUtils.readSync(file.fd, buffer, { offset: 0 });
      SafeFileUtils.closeSync(file);
      const decoder = util.TextDecoder.create('utf-8');
      const text: string = decoder.decodeToString(new Uint8Array(buffer));
      return SafeUtils.parseObj<PdfTextIndexDocument>(text);
    } catch (error) {
      logger.warn(TAG, 'loadIndex failed: bookId=' + bookId + ', error=' + String(error));
      return null;
    }
  }

  public async search(
    ctx: common.UIAbilityContext,
    bookId: string,
    keyword: string,
    limit: number = MAX_HITS
  ): Promise<PdfTextSearchHit[]> {
    const hits: PdfTextSearchHit[] = [];
    const trimmed: string = keyword.trim();
    if (trimmed.length <= 0) {
      return hits;
    }
    const doc: PdfTextIndexDocument | null = this.loadIndex(ctx, bookId);
    if (doc === null || !doc.hasTextLayer) {
      return hits;
    }
    const needle: string = trimmed.toLowerCase();
    const pages: string[] = doc.pages ?? [];
    for (let i = 0; i < pages.length; i++) {
      const raw: string = pages[i] ?? '';
      if (raw.length <= 0) {
        continue;
      }
      const hay: string = raw.toLowerCase();
      let from: number = 0;
      while (hits.length < limit) {
        const at: number = hay.indexOf(needle, from);
        if (at < 0) {
          break;
        }
        const start: number = Math.max(0, at - SNIPPET_RADIUS);
        const end: number = Math.min(raw.length, at + needle.length + SNIPPET_RADIUS);
        hits.push({ pageIndex: i, snippet: raw.substring(start, end) } as PdfTextSearchHit);
        from = at + needle.length;
      }
      if (hits.length >= limit) {
        break;
      }
    }
    return hits;
  }

  public async removeIndex(ctx: common.UIAbilityContext, bookId: string): Promise<void> {
    try {
      const path: string = this.resolveIndexPath(ctx, bookId);
      if (SafeFileUtils.accessSync(path)) {
        SafeFileUtils.unlinkSync(path);
      }
    } catch (_error) {
    }
  }
}
