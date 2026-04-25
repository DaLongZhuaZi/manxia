import { EBook, EBookChapter, EBookContentMode, EBookFormat, EBookReaderEngine } from '../../Models/EBookModels';
import { DownloadStatus } from '../Types/StatusEnums';
import { ImageSourceType, MangaChapter, MangaPage, ReadingSettings } from '../../Models/MangaModels';
import { logger } from '../../Utils/Logger';
import { isEpubWebViewEnabled } from '../Initialization/ReaderKitFeatureGate';

const TAG = 'EBookImageReaderAdapter';

export interface EBookImagePageEntry {
  absolutePageIndex: number;
  runtimePageIndex: number;
  visualChapterIndex: number;
  visualPageIndex: number;
  ebookChapterIndex: number;
  ebookChapter: EBookChapter;
  imagePath: string;
  title: string;
}

export interface EBookImageReaderRuntime {
  runtimeChapter: MangaChapter;
  runtimeChapters: MangaChapter[];
  chapterListChapters: MangaChapter[];
  imageEntries: EBookImagePageEntry[];
  initialPageIndex: number;
}

export interface EBookImagePageSignalStats {
  totalChapters: number;
  imagePathChapters: number;
  imageLayoutChapters: number;
  imageMediaChapters: number;
  imageResourceChapters: number;
  sparsePageLikeChapters: number;
  strongSignalChapters: number;
}

const IMAGE_FILE_PATH_PATTERN: RegExp = /\.(apng|avif|bmp|gif|heic|heif|jpe?g|png|svg|webp)$/i;
const PAGE_LIKE_TITLE_PATTERN: RegExp = /^(?:\u7B2C\s*)?\d+\s*[\u9875\u9801]$|^page\s*\d+$/i;

function normalizePath(path: string): string {
  return path.replace(/\\/g, '/').replace(/\/+/g, '/');
}

function isImagePageChapter(chapter: EBookChapter): boolean {
  return (chapter.resourceImagePath || '').trim().length > 0 ||
    (chapter.resourceImageRelativePath || '').trim().length > 0;
}

function isImageLayoutChapter(chapter: EBookChapter): boolean {
  return (chapter.resourceLayoutType || '').trim().toUpperCase() === 'IMAGE_PAGE';
}

function isImageMediaChapter(chapter: EBookChapter): boolean {
  return (chapter.resourceMediaType || '').trim().toLowerCase().startsWith('image/');
}

function isImageResourceChapter(chapter: EBookChapter): boolean {
  const resourceFile = (chapter.resourceFile || '').trim().replace(/[#?].*$/, '');
  const resourceHref = (chapter.resourceHref || '').trim().replace(/[#?].*$/, '');
  return IMAGE_FILE_PATH_PATTERN.test(resourceFile) || IMAGE_FILE_PATH_PATTERN.test(resourceHref);
}

function getNormalizedChapterTextLength(chapter: EBookChapter): number {
  const normalizedContent = (chapter.content || '')
    .replace(/<[^>]+>/g, ' ')
    .replace(/&nbsp;/gi, ' ')
    .replace(/\s+/g, ' ')
    .trim();
  return normalizedContent.length;
}

function isSparsePageLikeChapter(chapter: EBookChapter): boolean {
  const title = (chapter.title || '').trim();
  if (title.length <= 0 || !PAGE_LIKE_TITLE_PATTERN.test(title)) {
    return false;
  }
  return getNormalizedChapterTextLength(chapter) <= 80;
}

export function inspectEBookImagePageSignals(ebook: EBook | null): EBookImagePageSignalStats {
  const stats: EBookImagePageSignalStats = {
    totalChapters: 0,
    imagePathChapters: 0,
    imageLayoutChapters: 0,
    imageMediaChapters: 0,
    imageResourceChapters: 0,
    sparsePageLikeChapters: 0,
    strongSignalChapters: 0
  };

  const chapters = ebook?.chapters || [];
  stats.totalChapters = chapters.length;
  for (const chapter of chapters) {
    const hasImagePath = isImagePageChapter(chapter);
    const hasImageLayout = isImageLayoutChapter(chapter);
    const hasImageMedia = isImageMediaChapter(chapter);
    const hasImageResource = isImageResourceChapter(chapter);
    const hasSparsePageLikeSignal = isSparsePageLikeChapter(chapter);

    if (hasImagePath) {
      stats.imagePathChapters++;
    }
    if (hasImageLayout) {
      stats.imageLayoutChapters++;
    }
    if (hasImageMedia) {
      stats.imageMediaChapters++;
    }
    if (hasImageResource) {
      stats.imageResourceChapters++;
    }
    if (hasSparsePageLikeSignal) {
      stats.sparsePageLikeChapters++;
    }
    if (hasImagePath || hasImageLayout || hasImageMedia || hasImageResource) {
      stats.strongSignalChapters++;
    }
  }

  return stats;
}

export function hasImagePageChapterSignals(ebook: EBook | null): boolean {
  if (!ebook || ebook.format !== EBookFormat.EPUB) {
    return false;
  }

  const stats = inspectEBookImagePageSignals(ebook);
  if (stats.totalChapters <= 0) {
    return false;
  }

  if (stats.totalChapters <= 2) {
    return stats.strongSignalChapters === stats.totalChapters;
  }

  const strongSignalRatio = stats.strongSignalChapters / stats.totalChapters;
  if (stats.strongSignalChapters >= 3 && strongSignalRatio >= 0.5) {
    return true;
  }

  const combinedSignalCount = stats.strongSignalChapters + stats.sparsePageLikeChapters;
  if (stats.totalChapters >= 8 && stats.sparsePageLikeChapters >= 6) {
    return (combinedSignalCount / stats.totalChapters) >= 0.9;
  }

  return false;
}

export function resolveImagePagePath(ebook: EBook, chapter: EBookChapter): string {
  const absolutePath = (chapter.resourceImagePath || '').trim();
  if (absolutePath.length > 0) {
    return normalizePath(absolutePath);
  }

  const relativePath = (chapter.resourceImageRelativePath || '').trim();
  const rootPath = (ebook.extractedRootPath || '').trim();
  if (relativePath.length <= 0 || rootPath.length <= 0) {
    return '';
  }

  if (relativePath.startsWith('/')) {
    return normalizePath(relativePath);
  }

  return normalizePath(`${rootPath}/${relativePath}`);
}

export function collectImageEntries(ebook: EBook): EBookImagePageEntry[] {
  const result: EBookImagePageEntry[] = [];
  const chapters = ebook.chapters || [];
  for (let index = 0; index < chapters.length; index++) {
    const chapter = chapters[index];
    if (!isImagePageChapter(chapter)) {
      continue;
    }

    const imagePath = resolveImagePagePath(ebook, chapter);
    if (imagePath.length <= 0) {
      continue;
    }

    const runtimePageIndex = result.length;
    result.push({
      absolutePageIndex: runtimePageIndex,
      runtimePageIndex,
      visualChapterIndex: 0,
      visualPageIndex: runtimePageIndex,
      ebookChapterIndex: index,
      ebookChapter: chapter,
      imagePath,
      title: (chapter.title || '').trim() || `Page ${index + 1}`
    });
  }
  return result;
}

export function isImagePageEBook(ebook: EBook | null): boolean {
  if (!ebook) {
    return false;
  }
  const imageEntries = collectImageEntries(ebook);
  if (imageEntries.length <= 0) {
    return false;
  }
  return ebook.contentMode === EBookContentMode.IMAGE_PAGE ||
    ebook.preferredReaderEngine === EBookReaderEngine.MANGA ||
    hasImagePageChapterSignals(ebook);
}

export function shouldUseEBookImageReaderRoute(ebook: EBook | null): boolean {
  if (!ebook) {
    return false;
  }
  if (ebook.format !== EBookFormat.EPUB) {
    return false;
  }
  return ebook.contentMode === EBookContentMode.IMAGE_PAGE ||
    ebook.preferredReaderEngine === EBookReaderEngine.MANGA ||
    hasImagePageChapterSignals(ebook);
}

export function resolveEBookReaderRouteName(ebook: EBook | null): string {
  if (shouldUseEBookImageReaderRoute(ebook)) {
    return 'EBookImageReaderPage';
  }
  if (shouldUseEpubWebViewReaderRoute(ebook)) {
    return 'EpubWebViewReaderPage';
  }
  if (shouldUseMobiWebViewReaderRoute(ebook)) {
    return 'EpubWebViewReaderPage';
  }
  return 'EBookReaderPage';
}

function shouldUseEpubWebViewReaderRoute(ebook: EBook | null): boolean {
  if (!ebook || ebook.format !== EBookFormat.EPUB) {
    return false;
  }
  if (ebook.contentMode === EBookContentMode.FIXED_LAYOUT_HTML ||
    ebook.preferredReaderEngine === EBookReaderEngine.WEBVIEW) {
    return true;
  }
  return isEpubWebViewEnabled();
}

function shouldUseMobiWebViewReaderRoute(ebook: EBook | null): boolean {
  if (!ebook) {
    return false;
  }
  if (ebook.format !== EBookFormat.MOBI &&
    ebook.format !== EBookFormat.AZW &&
    ebook.format !== EBookFormat.AZW3) {
    return false;
  }
  logger.info(
    TAG,
    `Kindle 电子书默认使用 WebView 阅读器: format=${ebook.format}, engine=${ebook.preferredReaderEngine}, extractedRootPath=${ebook.extractedRootPath || ''}`
  );
  return true;
}

export function parseImageReaderDomPos(domPos: string): number {
  if (!domPos || !domPos.startsWith('image-page:')) {
    return -1;
  }
  const pageIndex = Number(domPos.substring('image-page:'.length));
  if (!Number.isFinite(pageIndex) || pageIndex < 0) {
    return -1;
  }
  return Math.floor(pageIndex);
}

function clampPageIndex(pageIndex: number, total: number): number {
  if (total <= 0) {
    return 0;
  }
  const safeIndex = Math.floor(pageIndex);
  return Math.max(0, Math.min(safeIndex, total - 1));
}

export function resolveRuntimePageIndexByChapterIndex(ebook: EBook, chapterIndex: number): number {
  if (!Number.isFinite(chapterIndex) || chapterIndex < 0) {
    return -1;
  }
  const targetChapterIndex = Math.floor(chapterIndex);
  const imageEntries = collectImageEntries(ebook);
  for (let index = 0; index < imageEntries.length; index++) {
    if (imageEntries[index].ebookChapterIndex === targetChapterIndex) {
      return index;
    }
  }
  return -1;
}

export function resolveRuntimePageIndexByChapterId(ebook: EBook, chapterId: string): number {
  const safeChapterId = (chapterId || '').trim();
  if (safeChapterId.length <= 0) {
    return -1;
  }
  const imageEntries = collectImageEntries(ebook);
  for (let index = 0; index < imageEntries.length; index++) {
    if ((imageEntries[index].ebookChapter.id || '') === safeChapterId) {
      return index;
    }
  }
  return -1;
}

export function resolveRuntimePageIndexFromLegacyAnchor(
  ebook: EBook,
  chapterId: string,
  chapterIndex: number,
  pageIndex: number
): number {
  const imageEntries = collectImageEntries(ebook);
  if (imageEntries.length <= 0) {
    return 0;
  }

  if (Number.isFinite(pageIndex) && pageIndex > 0) {
    return clampPageIndex(pageIndex, imageEntries.length);
  }

  const chapterIdMappedPage = resolveRuntimePageIndexByChapterId(ebook, chapterId);
  if (chapterIdMappedPage >= 0) {
    return chapterIdMappedPage;
  }

  const chapterIndexMappedPage = resolveRuntimePageIndexByChapterIndex(ebook, chapterIndex);
  if (chapterIndexMappedPage >= 0) {
    return chapterIndexMappedPage;
  }

  if (Number.isFinite(pageIndex) && pageIndex >= 0) {
    return clampPageIndex(pageIndex, imageEntries.length);
  }

  return 0;
}

export function resolveInitialImageReaderPageIndex(ebook: EBook): number {
  const imageEntries = collectImageEntries(ebook);
  if (imageEntries.length <= 0) {
    return 0;
  }

  const domPosPageIndex = parseImageReaderDomPos(ebook.readingProgress?.domPos || '');
  if (domPosPageIndex >= 0 && domPosPageIndex < imageEntries.length) {
    return domPosPageIndex;
  }

  const chapterIdPageIndex = resolveRuntimePageIndexByChapterId(
    ebook,
    ebook.readingProgress?.currentChapterId || ''
  );
  if (chapterIdPageIndex >= 0) {
    return chapterIdPageIndex;
  }

  const chapterIndexPageIndex = resolveRuntimePageIndexByChapterIndex(
    ebook,
    ebook.readingProgress?.currentChapterIndex ?? -1
  );
  if (chapterIndexPageIndex >= 0) {
    return chapterIndexPageIndex;
  }

  const progressPosition = ebook.readingProgress?.currentPosition ?? -1;
  if (Number.isFinite(progressPosition) && progressPosition > 0) {
    return clampPageIndex(progressPosition, imageEntries.length);
  }

  return 0;
}

function buildRuntimePages(ebook: EBook, imageEntries: EBookImagePageEntry[]): MangaPage[] {
  return imageEntries.map((entry: EBookImagePageEntry) => {
    const page: MangaPage = {
      id: `${ebook.id}_image_page_${entry.runtimePageIndex}`,
      index: entry.runtimePageIndex,
      sourceType: ImageSourceType.LOCAL,
      imagePath: entry.imagePath,
      imageUrl: '',
      localPath: entry.imagePath,
      isLoaded: false,
      priority: 10
    };
    return page;
  });
}

function buildChapterListChapters(ebook: EBook, imageEntries: EBookImagePageEntry[]): MangaChapter[] {
  return imageEntries.map((entry: EBookImagePageEntry, index: number) => {
    const chapter: MangaChapter = {
      id: entry.ebookChapter.id || `${ebook.id}_toc_${index}`,
      title: entry.title,
      chapterNumber: index + 1,
      pages: [],
      totalPages: 1,
      publishDate: ebook.addTime || Date.now(),
      language: ebook.metadata.language || 'zh-CN',
      scanlationGroup: '',
      isDownloaded: true,
      downloadStatus: DownloadStatus.COMPLETED,
      downloadProgress: 100,
      localPath: entry.imagePath
    };
    return chapter;
  });
}

export function buildEBookImageReaderRuntime(
  ebook: EBook,
  readingSettings: ReadingSettings
): EBookImageReaderRuntime {
  const imageEntries = collectImageEntries(ebook);
  const pages = buildRuntimePages(ebook, imageEntries);
  const runtimeChapter: MangaChapter = {
    id: `${ebook.id}_image_runtime`,
    title: ebook.metadata.title || 'Image Ebook',
    chapterNumber: 1,
    pages,
    totalPages: pages.length,
    publishDate: ebook.addTime || Date.now(),
    language: ebook.metadata.language || 'zh-CN',
    scanlationGroup: '',
    isDownloaded: true,
    downloadStatus: DownloadStatus.COMPLETED,
    downloadProgress: 100,
    localPath: ebook.extractedRootPath || ebook.filePath
  };

  logger.info(
    TAG,
    `构建图片电子书运行时：书籍ID=${ebook.id}，图片页数=${imageEntries.length}，初始页=${resolveInitialImageReaderPageIndex(ebook)}，阅读模式=${readingSettings.readingMode}，翻页动画=${readingSettings.pageTurnAnimation}`
  );

  return {
    runtimeChapter,
    runtimeChapters: [runtimeChapter],
    chapterListChapters: buildChapterListChapters(ebook, imageEntries),
    imageEntries,
    initialPageIndex: resolveInitialImageReaderPageIndex(ebook)
  };
}
