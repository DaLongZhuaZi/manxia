/**
 * Builds stable database identities for chapters imported from local files.
 * Extraction directories are deliberately excluded because they are recreated
 * for every picker run and therefore cannot identify the source content.
 */

import { sha256Hash } from './CryptoUtils';

function normalizeImportPath(value: string): string {
  let normalized: string = value.trim().replace(/\\/g, '/');
  try {
    normalized = decodeURIComponent(normalized);
  } catch (_error) {
    // Keep the original URI when it contains an incomplete escape sequence.
  }
  while (normalized.length > 1 && normalized.endsWith('/')) {
    normalized = normalized.substring(0, normalized.length - 1);
  }
  return normalized;
}

function resolveLogicalChapterPath(sourcePath: string, extractedRootPath: string): string {
  const normalizedSourcePath: string = normalizeImportPath(sourcePath);
  const normalizedRootPath: string = normalizeImportPath(extractedRootPath);
  if (normalizedRootPath.length > 0) {
    if (normalizedSourcePath === normalizedRootPath) {
      return '.';
    }
    const rootPrefix: string = `${normalizedRootPath}/`;
    if (normalizedSourcePath.startsWith(rootPrefix)) {
      return normalizedSourcePath.substring(rootPrefix.length);
    }
  }
  return normalizedSourcePath;
}

export async function createLocalMangaChapterExternalId(
  comicId: string,
  fileUri: string,
  sourcePath: string,
  extractedRootPath: string,
  chapterNumber: number
): Promise<string> {
  const normalizedFileUri: string = normalizeImportPath(fileUri);
  const logicalChapterPath: string = resolveLogicalChapterPath(sourcePath, extractedRootPath);
  const identitySource: string = [
    'local-manga-chapter-v1',
    comicId.trim(),
    normalizedFileUri,
    logicalChapterPath,
    // 标题和页数都可能在导入对话框中被用户编辑或因补页而变化，
    // 不能参与幂等身份；章节号仅作为同一来源下的稳定回退字段。
    chapterNumber > 0 ? String(chapterNumber) : ''
  ].join('\n');
  const digest: string = await sha256Hash(identitySource);
  return `local_chapter_v1_${digest}`;
}

export async function createPickedImageGroupUri(displayName: string, sourceUris: string[]): Promise<string> {
  const normalizedSources: string[] = sourceUris.map((sourceUri: string): string => {
    return normalizeImportPath(sourceUri);
  });
  normalizedSources.sort((left: string, right: string): number => left.localeCompare(right));
  const digest: string = await sha256Hash(normalizedSources.join('\n'));
  return `picked-images:v1_${digest}/${encodeURIComponent(displayName)}`;
}
