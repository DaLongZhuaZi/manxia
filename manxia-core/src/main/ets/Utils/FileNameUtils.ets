/**
 * 文件名处理工具类
 * 提供安全的文件名清理功能，避免产生无意义的下划线序列
 * 
 * 文件路径: entry/src/main/ets/Utils/FileNameUtils.ets
 */

import { logger } from './Logger';

const TAG = 'FileNameUtils';

export interface SanitizedMangaPath {
  source: string;
  comic: string;
}

/**
 * 清理文件名中的非法字符
 * 
 * 改进点：
 * 1. **完全保留**中文、日文、韩文等所有Unicode字符
 * 2. 只替换文件系统真正不允许的字符：< > : " / \ | ? *
 * 3. 替换控制字符（0x00-0x1F）
 * 4. 避免产生连续的下划线
 * 5. 如果清理后为空，使用fallback名称
 * 
 * @param fileName 原始文件名
 * @param fallbackName 如果清理后为空，使用的fallback名称，默认为'untitled'
 * @param maxLength 最大长度，默认100字符
 * @returns 清理后的安全文件名
 */
export function sanitizeFileName(fileName: string, fallbackName: string = 'untitled', maxLength: number = 100): string {
  if (!fileName || fileName.trim().length === 0) {
    return fallbackName;
  }
  
  let cleaned = fileName
    // 只替换Windows/Unix文件系统真正不允许的字符
    // 保留所有其他字符，包括中文、日文、韩文、emoji等
    .replace(/[<>:"/\\|?*]/g, '_')
    // 替换控制字符（0x00-0x1F, 0x7F）
    .replace(/[\x00-\x1f\x7f]/g, '')
    // 合并多个下划线为一个
    .replace(/_{2,}/g, '_')
    // 移除首尾的下划线和空格
    .replace(/^[\s_]+|[\s_]+$/g, '');
  
  // 如果清理后为空或只剩下下划线，使用fallback
  if (!cleaned || /^_+$/.test(cleaned)) {
    logger.warn(TAG, `File name "${fileName}" cleaned to empty, using fallback: ${fallbackName}`);
    return fallbackName;
  }
  
  // 限制长度（按字符数，不是字节数）
  if (cleaned.length > maxLength) {
    cleaned = cleaned.substring(0, maxLength);
    // 移除可能被截断的尾部下划线和空格
    cleaned = cleaned.replace(/[\s_]+$/, '');
  }
  
  return cleaned;
}

/**
 * 为漫画生成安全的目录名
 * 格式: sourceId/comicTitle
 * 
 * @param sourceId 图源ID
 * @param comicTitle 漫画标题
 * @returns 清理后的目录路径
 */
export function sanitizeMangaPath(sourceId: string, comicTitle: string): SanitizedMangaPath {
  const safeSource = sanitizeFileName(sourceId, 'unknown_source', 50);
  const safeComic = sanitizeFileName(comicTitle, `comic_${Date.now()}`, 100);

  const sanitizedPath: SanitizedMangaPath = {
    source: safeSource,
    comic: safeComic
  };

  return sanitizedPath;
}

/**
 * 为章节生成安全的目录名
 * 
 * @param chapterTitle 章节标题
 * @param chapterIndex 章节索引（用作fallback）
 * @returns 清理后的章节目录名
 */
export function sanitizeChapterName(chapterTitle: string, chapterIndex: number = 0): string {
  return sanitizeFileName(chapterTitle, `chapter_${chapterIndex}`, 100);
}

/**
 * 为小说生成安全的目录名
 * 
 * @param bookTitle 小说标题
 * @param bookId 小说ID（用作fallback）
 * @returns 清理后的目录名
 */
export function sanitizeNovelPath(bookTitle: string, bookId: string): string {
  return sanitizeFileName(bookTitle, `novel_${bookId.substring(0, 8)}`, 100);
}

/**
 * 为电子书生成安全的目录名
 * 
 * @param ebookTitle 电子书标题
 * @param ebookId 电子书ID（用作fallback）
 * @returns 清理后的目录名
 */
export function sanitizeEBookPath(ebookTitle: string, ebookId: string): string {
  return sanitizeFileName(ebookTitle, `ebook_${ebookId.substring(0, 8)}`, 100);
}

/**
 * 检查文件名是否安全
 * 
 * @param fileName 文件名
 * @returns 是否安全
 */
export function isFileNameSafe(fileName: string): boolean {
  if (!fileName || fileName.trim().length === 0) {
    return false;
  }
  
  // 检查是否包含非法字符
  if (/[<>:"/\\|?*\x00-\x1f\x7f]/.test(fileName)) {
    return false;
  }
  
  // 检查是否只有下划线
  if (/^_+$/.test(fileName)) {
    return false;
  }
  
  return true;
}

/**
 * 生成唯一的文件名（添加时间戳）
 * 
 * @param baseName 基础名称
 * @param extension 扩展名（可选）
 * @returns 唯一文件名
 */
export function generateUniqueFileName(baseName: string, extension?: string): string {
  const safeName = sanitizeFileName(baseName, 'file', 80);
  const timestamp = Date.now();

  if (extension) {
    return `${safeName}_${timestamp}.${extension}`;
  }

  return `${safeName}_${timestamp}`;
}

/**
 * 获取文件扩展名（不含点号，小写）
 * @param path 文件路径或文件名
 * @returns 扩展名（不含点号），无扩展名时返回空字符串
 */
export function getFileExtension(path: string): string {
  const lastDot = path.lastIndexOf('.');
  if (lastDot < 0 || lastDot >= path.length - 1) {
    return '';
  }
  return path.substring(lastDot + 1).toLowerCase();
}

/**
 * 获取文件扩展名（含点号，小写）
 * @param path 文件路径或文件名
 * @returns 扩展名（含点号，如 ".jpg"），无扩展名时返回空字符串
 */
export function getFileExtensionWithDot(path: string): string {
  const lastDot = path.lastIndexOf('.');
  if (lastDot < 0 || lastDot >= path.length - 1) {
    return '';
  }
  return path.substring(lastDot).toLowerCase();
}

/**
 * 从 URL 中提取文件扩展名（自动去除查询参数和片段）
 * @param url URL 字符串
 * @returns 扩展名（不含点号，小写），无扩展名时返回空字符串
 */
export function getFileExtensionFromUrl(url: string): string {
  let pathPart: string = url;
  const queryIndex = pathPart.indexOf('?');
  if (queryIndex >= 0) {
    pathPart = pathPart.substring(0, queryIndex);
  }
  const fragmentIndex = pathPart.indexOf('#');
  if (fragmentIndex >= 0) {
    pathPart = pathPart.substring(0, fragmentIndex);
  }
  return getFileExtension(pathPart);
}

/**
 * 移除文件扩展名
 * @param fileName 文件名
 * @returns 不含扩展名的文件名
 */
export function removeFileExtension(fileName: string): string {
  const lastDotIndex = fileName.lastIndexOf('.');
  if (lastDotIndex > 0) {
    return fileName.substring(0, lastDotIndex);
  }
  return fileName;
}

/**
 * 根据扩展名获取 MIME 类型
 * @param extension 扩展名（不含点号，小写）
 * @returns MIME 类型字符串，未知类型返回 'application/octet-stream'
 */
export function getMimeTypeFromExtension(extension: string): string {
  const mimeMap: Record<string, string> = {
    'jpg': 'image/jpeg',
    'jpeg': 'image/jpeg',
    'png': 'image/png',
    'webp': 'image/webp',
    'gif': 'image/gif',
    'bmp': 'image/bmp',
    'heic': 'image/heic',
    'heif': 'image/heif',
    'svg': 'image/svg+xml',
    'avif': 'image/avif',
    'xml': 'application/xml',
    'json': 'application/json',
    'txt': 'text/plain',
    'html': 'text/html',
    'htm': 'text/html',
    'css': 'text/css',
    'js': 'application/javascript',
    'pdf': 'application/pdf',
    'zip': 'application/zip',
    'cbz': 'application/zip',
    'rar': 'application/vnd.rar',
    'cbr': 'application/vnd.rar',
    '7z': 'application/x-7z-compressed',
    'tar': 'application/x-tar',
    'gz': 'application/gzip',
    'epub': 'application/epub+zip',
    'woff': 'font/woff',
    'woff2': 'font/woff2',
    'ttf': 'font/ttf',
    'otf': 'font/otf'
  };
  return mimeMap[extension] || 'application/octet-stream';
}
