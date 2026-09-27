import {
  ContinuationTransferFile,
  ContinuationTransferManifest,
  ContinuationTransferRequest
} from './ContinuationReadingTypes';

export function normalizeContinuationPackagePath(path: string): string {
  const normalized = path.replace(/\\/g, '/');
  if (normalized.length <= 0 || normalized.startsWith('/') || normalized.indexOf(':') >= 0 || normalized.indexOf('\0') >= 0) {
    throw new Error('接续包包含非法路径');
  }
  const segments = normalized.split('/');
  const safeSegments: string[] = [];
  for (const segment of segments) {
    if (segment.length <= 0 || segment === '.') {
      continue;
    }
    if (segment === '..') {
      throw new Error('接续包路径越界');
    }
    safeSegments.push(segment);
  }
  if (safeSegments.length <= 0) {
    throw new Error('接续包路径为空');
  }
  return safeSegments.join('/');
}

function isValidTransferFile(file: ContinuationTransferFile): boolean {
  if (file.name.trim().length <= 0 || file.size <= 0 || file.sha256.length !== 64) {
    return false;
  }
  try {
    return normalizeContinuationPackagePath(file.relativePath).length > 0;
  } catch (_error) {
    return false;
  }
}

function isManifestPathPresent(manifest: ContinuationTransferManifest, path: string): boolean {
  if (path.trim().length <= 0) {
    return true;
  }
  let normalizedPath = '';
  try {
    normalizedPath = normalizeContinuationPackagePath(path);
  } catch (_error) {
    return false;
  }
  for (const file of manifest.files) {
    try {
      const normalizedFilePath = normalizeContinuationPackagePath(file.relativePath);
      if (normalizedFilePath === normalizedPath || normalizedFilePath.startsWith(`${normalizedPath}/`)) {
        return true;
      }
    } catch (_error) {
      return false;
    }
  }
  return false;
}

export function isContinuationManifestCompatible(
  manifest: ContinuationTransferManifest,
  request: ContinuationTransferRequest
): boolean {
  if (manifest.schemaVersion !== request.schemaVersion || manifest.schemaVersion !== 1 ||
    manifest.sessionId !== request.sessionId || manifest.mode !== request.mode ||
    manifest.contentType !== request.contentType || manifest.sourceBookId !== request.sourceBookId ||
    manifest.isLocal !== request.isLocal || manifest.chapterIndex !== request.chapterIndex ||
    manifest.pageIndex !== request.pageIndex || manifest.offset !== request.offset ||
    manifest.chapterCount < 0 || !Array.isArray(manifest.chapterContents) ||
    !Array.isArray(manifest.files) || manifest.files.length <= 0) {
    return false;
  }
  if ((manifest.mode === 'import_to_library' || manifest.isLocal) && !manifest.isCompleteBook) {
    return false;
  }
  const seenPaths = new Set<string>();
  for (const file of manifest.files) {
    if (!isValidTransferFile(file)) {
      return false;
    }
    const normalizedPath = normalizeContinuationPackagePath(file.relativePath);
    if (seenPaths.has(normalizedPath)) {
      return false;
    }
    seenPaths.add(normalizedPath);
  }
  const seenChapterIndexes = new Set<number>();
  for (const content of manifest.chapterContents) {
    if (content.chapterIndex < 0 || content.chapterIndex >= manifest.chapterCount ||
      seenChapterIndexes.has(content.chapterIndex) ||
      !isManifestPathPresent(manifest, content.relativePath)) {
      return false;
    }
    seenChapterIndexes.add(content.chapterIndex);
  }
  if (manifest.contentType === 'ebook' && !manifest.ebook) {
    return false;
  }
  if (manifest.contentType === 'manga' && !manifest.manga) {
    return false;
  }
  if (manifest.contentType === 'novel' && (!manifest.novelBook || manifest.novelChapters.length <= 0)) {
    return false;
  }
  if (manifest.ebook) {
    if (!Array.isArray(manifest.ebook.chapters) || !isManifestPathPresent(manifest, manifest.ebook.filePath) ||
      !isManifestPathPresent(manifest, manifest.ebook.extractedRootPath) ||
      !isManifestPathPresent(manifest, manifest.ebook.metadata.coverImagePath)) {
      return false;
    }
    for (const chapter of manifest.ebook.chapters) {
      if (!isManifestPathPresent(manifest, chapter.resourceImagePath || '')) {
        return false;
      }
    }
  }
  if (manifest.manga) {
    if (!Array.isArray(manifest.manga.files) || !Array.isArray(manifest.manga.chapterPages) ||
      !Array.isArray(manifest.manga.chapters)) {
      return false;
    }
    for (const file of manifest.manga.files) {
      if (!isManifestPathPresent(manifest, file.relPath)) {
        return false;
      }
    }
    if (!isManifestPathPresent(manifest, manifest.manga.comic.coverLocalPath)) {
      return false;
    }
    for (const pageGroup of manifest.manga.chapterPages) {
      for (const page of pageGroup.pages) {
        if (!isManifestPathPresent(manifest, page.localPath)) {
          return false;
        }
      }
    }
  }
  if (manifest.contentType === 'novel' && !manifest.isLocal &&
    manifest.mode === 'read_only' && !seenChapterIndexes.has(manifest.chapterIndex)) {
    return false;
  }
  if (manifest.contentType === 'novel' && !manifest.isLocal &&
    manifest.mode === 'import_to_library') {
    const seenNovelChapterIndexes = new Set<number>();
    for (const chapter of manifest.novelChapters) {
      if (chapter.index < 0 || chapter.index >= manifest.chapterCount ||
        seenNovelChapterIndexes.has(chapter.index) || !seenChapterIndexes.has(chapter.index)) {
        return false;
      }
      seenNovelChapterIndexes.add(chapter.index);
    }
  }
  return true;
}
