import { SafeFileUtils } from '../../Utils/SafeFileUtils';
import fs from '@ohos.file.fs';
import { fileUri } from '@kit.CoreFileKit';
import { logger } from '../../Utils/Logger';
import {
  DataManager,
  ComicInfoInput,
  ChapterInfoInput,
  PageInfoInput,
  FavoriteInfoInput
} from '../Data/DataManager';
import { MangaStatus } from '../Types/StatusEnums';
import {
  PdfToMangaImporter,
  PdfImportResult,
  PdfContentType,
  PdfImportMode
} from '../Parsers/PdfToMangaImporter';
import {
  PdfImportDialogResult,
  PdfImportMode as DialogImportMode
} from '../Components/PdfImportDialog';
import { TaskCancelSignal } from '../Task/BackgroundTaskManager';
import { ImportFilenameIntelligenceService } from './ImportFilenameIntelligenceService';
import { MangaReadFlowImportReport, MangaReadFlowImportReporter } from '../Reader/MangaReadFlowImportReporter';
import { ImportFlowMonitor, getImportFlowMonitor } from '../Import/ImportFlowMonitor';
import {
  ImportFlowContentType,
  ImportFlowEntrySource,
  ImportFlowEvent,
  ImportFlowEventType,
  ImportFlowSessionInfo,
  ImportFlowSeverity
} from '../Import/ImportFlowTypes';

const TAG = 'PdfImportService';
const PDF_IMPORT_DIR_NAME = 'pdf_import';
const PDF_OUTPUT_DIR_NAME = 'manga';

export interface ExecutePdfImportOptions {
  fileUri: string;
  dialogResult: PdfImportDialogResult;
  filesDir: string;
  outputDir?: string;
  cancelSignal?: TaskCancelSignal;
  onProgress?: (current: number, total: number, message: string) => void;
  sourceId?: string;
  importFlowId?: string;
}

export class PdfImportService {
  private static instance: PdfImportService | null = null;
  private dataManager: DataManager = DataManager.getInstance();
  private filenameIntelligenceService: ImportFilenameIntelligenceService = ImportFilenameIntelligenceService.getInstance();
  private importFlowMonitor: ImportFlowMonitor = getImportFlowMonitor();

  public static getInstance(): PdfImportService {
    if (!PdfImportService.instance) {
      PdfImportService.instance = new PdfImportService();
    }
    return PdfImportService.instance;
  }

  public getDefaultTitle(fileUri: string): string {
    const fileName = this.resolveFileName(fileUri);
    const parseResult = this.filenameIntelligenceService.parseFileName(fileName);
    if (parseResult.bestCandidate.title.trim().length > 0) {
      return parseResult.bestCandidate.title;
    }
    return fileName.replace(/\.[^.]+$/i, '').replace(/^\d{13,}_/, '').replace(/_[a-f0-9]{6,}$/i, '');
  }

  public isSandboxPdfPath(fileUri: string, filesDir: string): boolean {
    return fileUri.startsWith(filesDir) || fileUri.startsWith('/data/storage');
  }

  public async copyPdfToSandbox(
    sourceUri: string,
    filesDir: string,
    cancelSignal?: TaskCancelSignal
  ): Promise<string> {
    this.throwIfCancelled(cancelSignal);

    if (this.isSandboxPdfPath(sourceUri, filesDir)) {
      return sourceUri;
    }

    const targetDir = `${filesDir}/${PDF_IMPORT_DIR_NAME}`;
    const safeFileName = this.buildSafePdfName(sourceUri);
    const targetPath = `${targetDir}/${safeFileName}`;

    try {
      SafeFileUtils.mkdirSync(targetDir, true);
    } catch (_error) {
    }

    const sourceFile = SafeFileUtils.openSync(sourceUri, fs.OpenMode.READ_ONLY);
    try {
      await fs.copyFile(sourceFile.fd, targetPath);
    } catch (error) {
      try {
        SafeFileUtils.unlinkSync(targetPath);
      } catch (_cleanupError) {
      }
      throw error as Error;
    } finally {
      try {
        SafeFileUtils.closeSync(sourceFile);
      } catch (_closeError) {
      }
    }

    const stat = SafeFileUtils.statSync(targetPath);
    if (stat.size <= 0) {
      try {
        SafeFileUtils.unlinkSync(targetPath);
      } catch (_cleanupError) {
      }
      throw new Error('PDF文件内容为空');
    }

    logger.info(TAG, `PDF已复制到沙箱: ${targetPath}, 大小=${stat.size} 字节`);
    return targetPath;
  }

  public async executeImport(options: ExecutePdfImportOptions): Promise<PdfImportResult> {
    const importFlowId: string = this.ensurePdfImportFlow(options);
    const emitProgress = (current: number, message: string): void => {
      if (options.onProgress) {
        options.onProgress(current, 100, message);
      }
    };

    try {
      this.throwIfCancelled(options.cancelSignal);
      emitProgress(2, '正在准备PDF文件...');
      const copyStartedAt: number = Date.now();
      this.recordImportFlowEvent(importFlowId, ImportFlowEventType.COPY_STARTED, 'pdf_copy_started', options.fileUri, '', options.dialogResult.title, true, '', 0, 0);
      const sandboxPath = await this.copyPdfToSandbox(options.fileUri, options.filesDir, options.cancelSignal);
      this.recordImportFlowEvent(importFlowId, ImportFlowEventType.COPY_COMPLETED, 'pdf_copy_completed', options.fileUri, sandboxPath, options.dialogResult.title, true, '', Date.now() - copyStartedAt, 0);

      this.throwIfCancelled(options.cancelSignal);
      const outputDir = this.resolveOutputDir(options.filesDir, options.outputDir);
      const importMode = options.dialogResult.importMode === DialogImportMode.SINGLE_CHAPTER
        ? PdfImportMode.SINGLE_CHAPTER
        : PdfImportMode.TANKOUBON;
      const isSingleChapter = importMode === PdfImportMode.SINGLE_CHAPTER;

      let existingMangaId: string | undefined = undefined;
      if (isSingleChapter) {
        emitProgress(8, '正在检查是否存在同名漫画...');
        const duplicateStartedAt: number = Date.now();
        this.recordImportFlowEvent(importFlowId, ImportFlowEventType.DUPLICATE_DETECT_STARTED, 'pdf_duplicate_detect_started', sandboxPath, outputDir, options.dialogResult.title, true, '', 0, 0);
        existingMangaId = await this.findExistingMangaByTitle(options.dialogResult.title);
        if (existingMangaId) {
          const hasChapter = await this.checkChapterExists(existingMangaId, options.dialogResult.chapterNumber || 1);
          if (hasChapter) {
            throw new Error(`漫画"${options.dialogResult.title}"已存在第${options.dialogResult.chapterNumber || 1}话，请修改章节编号`);
          }
        }
        this.recordImportFlowEvent(importFlowId, ImportFlowEventType.DUPLICATE_DETECT_COMPLETED, 'pdf_duplicate_detect_completed', sandboxPath, outputDir, options.dialogResult.title, true, existingMangaId || '', Date.now() - duplicateStartedAt, 0);
      }

      const importer = new PdfToMangaImporter({
        pdfPath: sandboxPath,
        outputDir: outputDir,
        contentType: options.dialogResult.contentType,
        importMode: importMode,
        chapterNumber: options.dialogResult.chapterNumber,
        chapterTitle: options.dialogResult.chapterTitle,
        existingMangaId: existingMangaId
      }, (current: number, total: number, message: string) => {
        this.throwIfCancelled(options.cancelSignal);
        const ratio = total > 0 ? current / total : 0;
        const mappedCurrent = 10 + Math.floor(ratio * 82);
        emitProgress(mappedCurrent, message);
      });

      emitProgress(10, '正在转换PDF...');
      const convertStartedAt: number = Date.now();
      this.recordImportFlowEvent(importFlowId, ImportFlowEventType.PDF_CONVERT_STARTED, 'pdf_convert_started', sandboxPath, outputDir, options.dialogResult.title, true, '', 0, 0);
      const result = await importer.import();
      if (!result.success) {
        throw new Error(result.errorMessage || 'PDF转换失败');
      }
      this.recordImportFlowEvent(importFlowId, ImportFlowEventType.PDF_CONVERT_COMPLETED, 'pdf_convert_completed', sandboxPath, outputDir, options.dialogResult.title, true, `pages=${result.totalPages || 0}`, Date.now() - convertStartedAt, result.totalPages || 0);

      if (result.comicInfo) {
        result.comicInfo.title = options.dialogResult.title;
        result.comicInfo.writer = options.dialogResult.author;
        result.comicInfo.summary = options.dialogResult.description || result.comicInfo.summary;
        result.comicInfo.tags = this.mergeTags(result.comicInfo.tags, options.dialogResult.tags);
      }

      emitProgress(95, '正在保存到数据库...');
      const dbStartedAt: number = Date.now();
      this.recordImportFlowEvent(importFlowId, ImportFlowEventType.DB_WRITE_STARTED, 'pdf_db_write_started', sandboxPath, outputDir, options.dialogResult.title, true, '', 0, result.totalPages || 0);
      await this.savePdfImportToDatabase(
        result,
        options.dialogResult.contentType,
        options.sourceId || 'local_pdf'
      );
      this.recordImportFlowEvent(importFlowId, ImportFlowEventType.DB_WRITE_COMPLETED, 'pdf_db_write_completed', sandboxPath, outputDir, options.dialogResult.title, true, `mangaId=${result.mangaId || ''}, chapterId=${result.chapterId || ''}`, Date.now() - dbStartedAt, result.totalPages || 0);
      result.originImportId = this.recordPdfImportFlow(options.fileUri, options.dialogResult, result, true, '', '');

      emitProgress(100, '导入完成');
      if (!options.importFlowId || options.importFlowId.length <= 0) {
        this.importFlowMonitor.endSession(importFlowId, 'pdf_service_import_completed');
      }
      return result;
    } catch (error) {
      const errorMessage = error instanceof Error ? error.message : String(error);
      logger.error(TAG, `PDF导入失败: ${errorMessage}`);
      const failedResult: PdfImportResult = {
        success: false,
        errorMessage: errorMessage,
        totalPages: 0
      };
      this.recordPdfImportFlow(options.fileUri, options.dialogResult, failedResult, false, errorMessage, 'execute_import_failed');
      this.recordImportFlowEvent(importFlowId, ImportFlowEventType.PDF_TASK_FAILED, 'pdf_execute_import_failed', options.fileUri, '', options.dialogResult.title, false, errorMessage, 0, 0);
      if (!options.importFlowId || options.importFlowId.length <= 0) {
        this.importFlowMonitor.endSession(importFlowId, 'pdf_service_import_failed');
      }
      throw error as Error;
    }
  }

  private ensurePdfImportFlow(options: ExecutePdfImportOptions): string {
    const info: ImportFlowSessionInfo = new ImportFlowSessionInfo();
    info.sessionId = options.importFlowId || '';
    info.entrySource = ImportFlowEntrySource.UNKNOWN;
    info.contentType = ImportFlowContentType.PDF;
    info.sourceUri = options.fileUri;
    info.targetPath = options.outputDir || '';
    info.displayName = options.dialogResult.title;
    info.fileCount = 1;
    info.batchMode = false;
    info.pageName = 'PdfImportService';
    info.startedAt = Date.now();
    return this.importFlowMonitor.ensureSession(info);
  }

  private recordImportFlowEvent(
    sessionId: string,
    eventType: ImportFlowEventType,
    reason: string,
    sourceUri: string,
    targetPath: string,
    displayName: string,
    success: boolean,
    detail: string,
    elapsedMs: number,
    pageCount: number
  ): void {
    const event: ImportFlowEvent = new ImportFlowEvent();
    event.sessionId = sessionId;
    event.eventType = eventType;
    event.reason = reason;
    event.contentType = ImportFlowContentType.PDF;
    event.sourceUri = sourceUri;
    event.targetPath = targetPath;
    event.displayName = displayName;
    event.success = success;
    event.severity = success ? ImportFlowSeverity.INFO : ImportFlowSeverity.ERROR;
    event.detail = detail;
    event.elapsedMs = elapsedMs;
    event.pageCount = pageCount;
    if (!success) {
      event.errorMessage = detail;
    }
    this.importFlowMonitor.record(event);
  }

  private recordPdfImportFlow(
    fileUri: string,
    dialogResult: PdfImportDialogResult,
    result: PdfImportResult,
    success: boolean,
    errorMessage: string,
    reason: string
  ): string {
    const report: MangaReadFlowImportReport = new MangaReadFlowImportReport();
    report.contentId = result.mangaId || '';
    report.contentTitle = dialogResult.title;
    report.chapterId = result.chapterId || '';
    report.chapterTitle = result.chapterTitle || dialogResult.chapterTitle || dialogResult.title;
    report.pageCount = result.totalPages || 0;
    report.chapterCount = 1;
    report.sourcePath = fileUri;
    report.targetPath = result.imageFiles && result.imageFiles.length > 0
      ? result.imageFiles[0].imagePath
      : '';
    report.sourceId = dialogResult.contentType === PdfContentType.MANGA ? 'local_pdf_manga' : 'local_pdf_ebook';
    report.success = success;
    report.reason = reason.length > 0 ? reason : 'pdf_import_completed';
    report.errorMessage = errorMessage;
    report.detail = `contentType=${dialogResult.contentType}, importMode=${dialogResult.importMode}`;
    return MangaReadFlowImportReporter.record(report);
  }

  private resolveOutputDir(filesDir: string, preferredOutputDir?: string): string {
    const outputDir = preferredOutputDir && preferredOutputDir.trim().length > 0
      ? preferredOutputDir.trim()
      : `${filesDir}/${PDF_OUTPUT_DIR_NAME}`;
    try {
      SafeFileUtils.mkdirSync(outputDir, true);
    } catch (_error) {
    }
    return outputDir;
  }

  private async findExistingMangaByTitle(title: string): Promise<string | undefined> {
    try {
      const comics = await this.dataManager.searchComics(title);
      for (const comic of comics) {
        if (comic.title === title) {
          return comic.id;
        }
      }
    } catch (error) {
      logger.warn(TAG, `查找同名漫画失败: ${String(error)}`);
    }
    return undefined;
  }

  private async checkChapterExists(mangaId: string, chapterNumber: number): Promise<boolean> {
    try {
      const chapters = await this.dataManager.getChaptersByMangaId(mangaId);
      const chapterIndex = chapterNumber - 1;
      for (const chapter of chapters) {
        if (chapter.index === chapterIndex) {
          return true;
        }
      }
    } catch (error) {
      logger.warn(TAG, `检查章节是否存在失败: ${String(error)}`);
    }
    return false;
  }

  private async savePdfImportToDatabase(
    result: PdfImportResult,
    contentType: PdfContentType,
    sourceId: string
  ): Promise<void> {
    if (!result.comicInfo || !result.mangaId || !result.chapterId) {
      throw new Error('PDF导入结果不完整');
    }

    const now = Date.now();
    const isSingleChapter = result.importMode === PdfImportMode.SINGLE_CHAPTER;
    const isNewManga = result.isNewManga !== false;

    let mangaId = result.mangaId;
    if (!isSingleChapter || isNewManga) {
      const comicInput: ComicInfoInput = {
        title: result.comicInfo.title || '未知标题',
        author: result.comicInfo.writer || '未知作者',
        description: result.comicInfo.summary || '',
        coverUrl: result.coverPath || '',
        sourceId: sourceId,
        externalId: result.mangaId,
        status: isSingleChapter ? MangaStatus.ONGOING : MangaStatus.COMPLETED,
        tags: this.mergeTags(result.comicInfo.tags, ['PDF导入']),
        rating: 0,
        chapterCount: 1,
        lastUpdateTime: now,
        contentType: contentType === PdfContentType.MANGA ? 'manga' : 'ebook'
      };
      mangaId = await this.dataManager.addComicInfo(comicInput);
    }

    const chapterTitle = isSingleChapter
      ? (result.chapterTitle || `第${result.chapterNumber || 1}话`)
      : (result.comicInfo.title || '全卷');
    const chapterInput: ChapterInfoInput = {
      comicId: mangaId,
      title: chapterTitle,
      index: isSingleChapter ? (result.chapterNumber || 1) - 1 : 0,
      pageCount: result.totalPages || 0,
      isDownloaded: true,
      downloadPath: result.imageFiles && result.imageFiles.length > 0
        ? result.imageFiles[0].imagePath.substring(0, result.imageFiles[0].imagePath.lastIndexOf('/'))
        : '',
      publishTime: now,
      externalId: result.chapterId
    };
    const chapterId = await this.dataManager.addChapterInfo(chapterInput);

    if (result.imageFiles) {
      for (const pageImage of result.imageFiles) {
        const pageInput: PageInfoInput = {
          chapterId: chapterId,
          index: pageImage.pageIndex,
          imageUrl: pageImage.imagePath,
          localPath: pageImage.imagePath,
          width: pageImage.width || 0,
          height: pageImage.height || 0,
          fileSize: pageImage.fileSize || 0
        };
        await this.dataManager.addPageInfo(pageInput);
      }
    }

    try {
      const favoriteInput: FavoriteInfoInput = {
        comicId: mangaId,
        userId: 'default_user',
        tags: this.mergeTags(result.comicInfo.tags, ['PDF导入'])
      };
      await this.dataManager.addFavorite(favoriteInput);
    } catch (error) {
      logger.warn(TAG, `收藏记录跳过: ${String(error)}`);
    }
  }

  private mergeTags(primary?: string[], secondary?: string[]): string[] {
    const merged: string[] = [];
    const appendTags = (source?: string[]): void => {
      if (!source) {
        return;
      }
      for (const tag of source) {
        const normalized = tag.trim();
        if (normalized.length <= 0) {
          continue;
        }
        if (merged.indexOf(normalized) < 0) {
          merged.push(normalized);
        }
      }
    };
    appendTags(primary);
    appendTags(secondary);
    return merged;
  }

  private resolveFileName(uri: string): string {
    try {
      return new fileUri.FileUri(uri).name;
    } catch (_error) {
      const rawName = uri.substring(uri.lastIndexOf('/') + 1) || 'unknown.pdf';
      try {
        return decodeURIComponent(rawName);
      } catch (_decodeError) {
        return rawName;
      }
    }
  }

  private buildSafePdfName(sourceUri: string): string {
    const originalName = this.resolveFileName(sourceUri).replace(/[<>:"/\\|?*]/g, '_');
    return `${Date.now()}_${originalName}`;
  }

  private throwIfCancelled(cancelSignal?: TaskCancelSignal): void {
    if (cancelSignal && cancelSignal.isCancelled) {
      throw new Error('任务已取消');
    }
  }
}
