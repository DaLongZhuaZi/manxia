import { EBook } from 'manxia_core/src/main/ets/Models/EBookModels';
import { MangaTransferBundle } from './MangaTransferTypes';
import { NovelBook, NovelChapter } from 'manxia_core/src/main/ets/Models/NovelModels';

export enum ContinuationTransferMode {
  READ_ONLY = 'read_only',
  IMPORT_TO_LIBRARY = 'import_to_library',
  DISABLED = 'disabled'
}

export type ContinuationContentType = 'ebook' | 'manga' | 'novel';

export interface ContinuationReadingSettings {
  readOnlyEnabled: boolean;
  importToLibraryEnabled: boolean;
  defaultMode: ContinuationTransferMode;
}

export function resolveContinuationTransferMode(
  settings: ContinuationReadingSettings
): ContinuationTransferMode {
  if (settings.defaultMode === ContinuationTransferMode.READ_ONLY && settings.readOnlyEnabled) {
    return ContinuationTransferMode.READ_ONLY;
  }
  if (settings.defaultMode === ContinuationTransferMode.IMPORT_TO_LIBRARY && settings.importToLibraryEnabled) {
    return ContinuationTransferMode.IMPORT_TO_LIBRARY;
  }
  if (settings.readOnlyEnabled) {
    return ContinuationTransferMode.READ_ONLY;
  }
  if (settings.importToLibraryEnabled) {
    return ContinuationTransferMode.IMPORT_TO_LIBRARY;
  }
  return ContinuationTransferMode.DISABLED;
}

export function normalizeContinuationReadingSettings(
  settings: ContinuationReadingSettings
): ContinuationReadingSettings {
  let defaultMode = settings.defaultMode === ContinuationTransferMode.IMPORT_TO_LIBRARY
    ? ContinuationTransferMode.IMPORT_TO_LIBRARY
    : ContinuationTransferMode.READ_ONLY;
  if (defaultMode === ContinuationTransferMode.READ_ONLY && !settings.readOnlyEnabled && settings.importToLibraryEnabled) {
    defaultMode = ContinuationTransferMode.IMPORT_TO_LIBRARY;
  } else if (defaultMode === ContinuationTransferMode.IMPORT_TO_LIBRARY &&
    !settings.importToLibraryEnabled && settings.readOnlyEnabled) {
    defaultMode = ContinuationTransferMode.READ_ONLY;
  }
  return {
    readOnlyEnabled: settings.readOnlyEnabled,
    importToLibraryEnabled: settings.importToLibraryEnabled,
    defaultMode: defaultMode
  };
}

export interface ContinuationTransferFile {
  name: string;
  relativePath: string;
  sourcePath: string;
  size: number;
  sha256: string;
}

export interface ContinuationChapterContent {
  chapterIndex: number;
  relativePath: string;
  title: string;
}

export interface ContinuationTransferManifest {
  schemaVersion: number;
  sessionId: string;
  mode: ContinuationTransferMode;
  contentType: ContinuationContentType;
  sourceBookId: string;
  isLocal: boolean;
  title: string;
  author: string;
  coverPath: string;
  sourceId: string;
  sourceName: string;
  bookUrl: string;
  chapterIndex: number;
  pageIndex: number;
  offset: number;
  chapterTitle: string;
  chapterCount: number;
  isCompleteBook: boolean;
  ebook: EBook | null;
  manga: MangaTransferBundle | null;
  novelBook: NovelBook | null;
  novelChapters: NovelChapter[];
  chapterContents: ContinuationChapterContent[];
  files: ContinuationTransferFile[];
}

export interface ContinuationCacheRecord {
  cacheId: string;
  sourceBookId: string;
  contentType: ContinuationContentType;
  title: string;
  author: string;
  coverPath: string;
  sourceId: string;
  bookUrl: string;
  chapterIndex: number;
  pageIndex: number;
  offset: number;
  lastReadTime: number;
  byteSize: number;
  dataDirectory: string;
}

export interface ContinuationCacheProgress {
  chapterIndex: number;
  pageIndex: number;
  offset: number;
  lastReadTime: number;
}

export interface ContinuationTransferRequest {
  schemaVersion: number;
  sessionId: string;
  mode: ContinuationTransferMode;
  contentType: ContinuationContentType;
  sourceBookId: string;
  isLocal: boolean;
  chapterIndex: number;
  pageIndex: number;
  offset: number;
}

export interface ContinuationBundleReceiveResult {
  manifest: ContinuationTransferManifest;
  stagingDirectory: string;
}
