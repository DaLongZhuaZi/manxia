/**
 * 使用手册数据
 * 用于首次运行时添加到书库的内置电子书
 */

import { util } from '@kit.ArkTS';
import { getContext } from 'manxia_core/src/main/ets/GlobalContext';
import { EBook, EBookFormat, EBookStatus, EBookChapter, EBookMetadata, DEFAULT_EBOOK_READING_SETTINGS, EBookReaderEngine } from 'manxia_core/src/main/ets/Models/EBookModels';

const USER_MANUAL_ID = 'user_manual_006';
const USER_MANUAL_RAWFILE_PATH = 'user_manual.md';
const LEGACY_USER_MANUAL_IDS: string[] = [
  'user_manual_001',
  'user_manual_002',
  'user_manual_003',
  'user_manual_004',
  'user_manual_005'
];

function normalizeManualChapterTitle(title: string): string {
  const normalized = title.trim();
  if (normalized.length <= 0) {
    return '未命名章节';
  }
  return normalized;
}

function createManualChapter(chapterNumber: number, title: string, content: string, startPosition: number, endPosition: number): EBookChapter {
  const safeContent = content.trim();
  return {
    id: `${USER_MANUAL_ID}_chapter_${chapterNumber}`,
    bookId: USER_MANUAL_ID,
    chapterNumber: chapterNumber,
    title: normalizeManualChapterTitle(title),
    content: safeContent,
    startPosition: startPosition,
    endPosition: endPosition,
    wordCount: safeContent.length,
    createTime: Date.now()
  };
}

function extractManualSectionTitle(line: string): string {
  const trimmed = line.trim();
  if (!trimmed.startsWith('## ')) {
    return '';
  }
  return trimmed.substring(3).trim();
}

/**
 * 创建使用手册章节列表
 */
function createUserManualChapters(markdownContent: string): EBookChapter[] {
  const normalizedContent = markdownContent.replace(/\r\n/g, '\n');
  const lines = normalizedContent.split('\n');
  const chapters: EBookChapter[] = [];
  let currentTitle = '漫匣使用手册';
  let currentLines: string[] = [];
  let currentStartPosition = 0;
  let cursor = 0;
  let insideCodeFence = false;

  for (const line of lines) {
    const trimmedLine = line.trim();
    const isFenceLine = trimmedLine.startsWith('```') || trimmedLine.startsWith('~~~');
    const sectionTitle = insideCodeFence ? '' : extractManualSectionTitle(line);
    if (sectionTitle.length > 0 && currentLines.join('\n').trim().length > 0) {
      chapters.push(createManualChapter(
        chapters.length + 1,
        currentTitle,
        currentLines.join('\n'),
        currentStartPosition,
        cursor
      ));
      currentTitle = sectionTitle;
      currentLines = [line];
      currentStartPosition = cursor;
    } else {
      if (sectionTitle.length > 0) {
        currentTitle = sectionTitle;
      }
      currentLines.push(line);
    }
    if (isFenceLine) {
      insideCodeFence = !insideCodeFence;
    }
    cursor += line.length + 1;
  }

  if (currentLines.join('\n').trim().length > 0) {
    chapters.push(createManualChapter(
      chapters.length + 1,
      currentTitle,
      currentLines.join('\n'),
      currentStartPosition,
      normalizedContent.length
    ));
  }

  if (chapters.length > 0) {
    return chapters;
  }

  return [
    createManualChapter(1, '漫匣使用手册', normalizedContent, 0, normalizedContent.length)
  ];
}

/**
 * 创建使用手册元数据
 */
function createUserManualMetadata(): EBookMetadata {
  return {
    title: '漫匣使用手册',
    author: '漫匣项目组',
    publisher: '漫匣项目组',
    publishDate: '2026-03-25',
    isbn: '',
    language: 'zh-CN',
    description: '面向当前版本漫匣的内置使用说明，覆盖本地导入、书库整理、统一详情页、阅读器、缓存同步与常见问题。',
    coverImagePath: 'app.media.mangabook',
    tags: ['使用手册', '帮助', '教程', '内置指南'],
    rating: 5
  };
}

/**
 * 创建使用手册电子书对象
 */
export function createUserManualEBook(markdownContent: string): EBook {
  const chapters = createUserManualChapters(markdownContent);
  const metadata = createUserManualMetadata();

  let totalWordCount = 0;
  for (const chapter of chapters) {
    totalWordCount += chapter.wordCount;
  }

  const now = Date.now();

  const ebook = new EBook(
    USER_MANUAL_ID,
    EBookFormat.MD,
    '',
    0,
    metadata,
    chapters,
    EBookStatus.UNREAD,
    {
      bookId: USER_MANUAL_ID,
      currentChapterId: chapters[0].id,
      currentChapterIndex: 0,
      currentPosition: 0,
      domPos: '',
      progress: 0,
      lastReadTime: 0,
      totalReadingTime: 0
    },
    DEFAULT_EBOOK_READING_SETTINGS,
    now,
    now,
    true,
    totalWordCount
  );
  ebook.preferredReaderEngine = EBookReaderEngine.MARKDOWN;
  return ebook;
}

/**
 * 从 rawfile 加载当前内置使用手册
 */
export async function createUserManualEBookFromRawFile(): Promise<EBook> {
  const context = getContext();
  const rawFileBytes = await context.resourceManager.getRawFileContent(USER_MANUAL_RAWFILE_PATH);
  const decoder = util.TextDecoder.create('utf-8');
  const markdownContent = decoder.decodeToString(rawFileBytes);
  return createUserManualEBook(markdownContent);
}

/**
 * 判断是否为任一版本的内置使用手册ID
 */
export function isUserManualId(bookId: string): boolean {
  if (bookId === USER_MANUAL_ID) {
    return true;
  }
  return LEGACY_USER_MANUAL_IDS.includes(bookId);
}

/**
 * 获取旧版使用手册ID列表
 */
export function getLegacyUserManualIds(): string[] {
  const ids: string[] = [];
  for (const id of LEGACY_USER_MANUAL_IDS) {
    ids.push(id);
  }
  return ids;
}

/**
 * 获取使用手册ID
 */
export function getUserManualId(): string {
  return USER_MANUAL_ID;
}
