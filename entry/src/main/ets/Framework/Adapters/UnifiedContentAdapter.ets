// 文件路径: entry/src/main/ets/Framework/Adapters/UnifiedContentAdapter.ets
/**
 * 统一内容适配器
 * 将漫画、电子书、小说的原始数据转换为统一展示模型
 * 不修改原始数据结构，仅做展示层适配
 */

import {
  UnifiedContent,
  UnifiedChapter,
  UnifiedContentType,
  UnifiedReadStatus,
  UnifiedDetailPageParams,
  UnifiedReaderParams
} from '../../Models/UnifiedContentModels';
import { Manga, MangaChapter } from '../../Models/MangaModels';
import { EBook, EBookChapter, EBookStatus } from '../../Models/EBookModels';
import { LegadoBook, LegadoChapter } from '../Novel/LegadoSourceTypes';
import { logger } from '../../Utils/Logger';

const TAG = 'UnifiedContentAdapter';

/**
 * 漫画适配器
 */
export class MangaAdapter {
  /**
   * 将漫画数据转换为统一内容模型
   */
  static toUnifiedContent(
    manga: Manga,
    chapters: MangaChapter[],
    isFavorite: boolean = false,
    readChapterIds: Set<string> = new Set(),
    downloadedChapterIds: Set<string> = new Set(),
    bookmarkedChapterIds: Set<string> = new Set(),
    lastReadChapterIndex: number = -1,
    sourceId?: string,
    sourceName?: string
  ): UnifiedContent {
    const unifiedChapters = chapters.map((chapter, index) => 
      MangaAdapter.toUnifiedChapter(chapter, index, readChapterIds, downloadedChapterIds, bookmarkedChapterIds)
    );
    
    const readCount = unifiedChapters.filter(c => c.isRead).length;
    const totalCount = unifiedChapters.length;
    
    // 从metadata中提取作者信息
    const authorName = manga.metadata?.authors?.length > 0 ? manga.metadata.authors.join(', ') : '未知作者';
    
    return {
      id: manga.id,
      title: manga.title,
      coverUrl: manga.coverImagePath || '',
      author: authorName,
      description: manga.description || '',
      
      contentType: UnifiedContentType.MANGA,
      genres: manga.metadata?.genres || [],
      tags: manga.metadata?.themes || [],
      
      readStatus: MangaAdapter.getReadStatus(readCount, totalCount),
      isFavorite: isFavorite,
      isNSFW: manga.isNSFW || false,
      
      totalChapters: totalCount,
      readChapters: readCount,
      lastReadChapterIndex: lastReadChapterIndex,
      lastReadChapterTitle: lastReadChapterIndex >= 0 && lastReadChapterIndex < chapters.length 
        ? chapters[lastReadChapterIndex].title : '',
      lastReadTime: manga.lastUpdatedAt,
      readProgress: totalCount > 0 ? Math.round((readCount / totalCount) * 100) : 0,
      
      sourceId: sourceId,
      sourceName: sourceName || manga.sourceInfo?.sourceName,
      sourceUrl: manga.sourceInfo?.sourceUrl,
      isLocal: !sourceId,
      
      chapters: unifiedChapters,
      originalData: manga,
      originalType: UnifiedContentType.MANGA
    };
  }
  
  /**
   * 将漫画章节转换为统一章节模型
   */
  static toUnifiedChapter(
    chapter: MangaChapter,
    index: number,
    readChapterIds: Set<string>,
    downloadedChapterIds: Set<string>,
    bookmarkedChapterIds: Set<string>
  ): UnifiedChapter {
    return {
      id: chapter.id,
      title: chapter.title,
      index: index,
      isRead: readChapterIds.has(chapter.id),
      isDownloaded: downloadedChapterIds.has(chapter.id),
      isBookmarked: bookmarkedChapterIds.has(chapter.id),
      pageCount: chapter.pages?.length || chapter.totalPages,
      publishDate: typeof chapter.publishDate === 'number' ? new Date(chapter.publishDate).toISOString() : chapter.publishDate?.toString(),
      originalData: chapter,
      originalType: UnifiedContentType.MANGA
    };
  }
  
  /**
   * 从统一章节获取原始漫画章节
   */
  static getOriginalChapter(unifiedChapter: UnifiedChapter): MangaChapter | null {
    if (unifiedChapter.originalType !== UnifiedContentType.MANGA) {
      logger.warn(TAG, '尝试从非漫画章节获取漫画数据');
      return null;
    }
    return unifiedChapter.originalData as MangaChapter;
  }
  
  /**
   * 从统一内容获取原始漫画数据
   */
  static getOriginalManga(unifiedContent: UnifiedContent): Manga | null {
    if (unifiedContent.originalType !== UnifiedContentType.MANGA) {
      logger.warn(TAG, '尝试从非漫画内容获取漫画数据');
      return null;
    }
    return unifiedContent.originalData as Manga;
  }
  
  private static getReadStatus(readCount: number, totalCount: number): UnifiedReadStatus {
    if (readCount === 0) return UnifiedReadStatus.UNREAD;
    if (readCount >= totalCount) return UnifiedReadStatus.COMPLETED;
    return UnifiedReadStatus.READING;
  }
}

/**
 * 电子书适配器
 */
export class EBookAdapter {
  /**
   * 将电子书数据转换为统一内容模型
   */
  static toUnifiedContent(
    ebook: EBook,
    isFavorite: boolean = false
  ): UnifiedContent {
    const chapters = ebook.chapters || [];
    const currentChapterIndex = ebook.readingProgress?.currentChapterIndex || 0;
    const unifiedChapters = chapters.map((chapter, index) => 
      EBookAdapter.toUnifiedChapter(chapter, index, currentChapterIndex)
    );
    
    const readCount = unifiedChapters.filter(c => c.isRead).length;
    const totalCount = unifiedChapters.length;
    
    // 计算阅读进度
    const readProgress = ebook.readingProgress?.progress || 0;
    
    return {
      id: ebook.id,
      title: ebook.metadata?.title || '未知书名',
      coverUrl: ebook.metadata?.coverImagePath || '',
      author: ebook.metadata?.author || '未知作者',
      description: ebook.metadata?.description || '',
      
      contentType: UnifiedContentType.EBOOK,
      genres: [],
      tags: ebook.metadata?.tags || [],
      
      readStatus: EBookAdapter.getReadStatus(ebook),
      isFavorite: ebook.isFavorite || isFavorite,
      isNSFW: ebook.isNSFW || false,
      
      totalChapters: totalCount,
      readChapters: readCount,
      lastReadChapterIndex: currentChapterIndex,
      lastReadChapterTitle: currentChapterIndex < chapters.length 
        ? chapters[currentChapterIndex].title : '',
      lastReadTime: ebook.readingProgress?.lastReadTime,
      readProgress: readProgress,
      
      isLocal: true,
      
      publisher: ebook.metadata?.publisher,
      publishDate: ebook.metadata?.publishDate,
      isbn: ebook.metadata?.isbn,
      fileSize: ebook.fileSize,
      filePath: ebook.filePath,
      format: ebook.format,
      
      chapters: unifiedChapters,
      originalData: ebook,
      originalType: UnifiedContentType.EBOOK
    };
  }
  
  /**
   * 将电子书章节转换为统一章节模型
   */
  static toUnifiedChapter(
    chapter: EBookChapter,
    index: number,
    currentChapterIndex: number
  ): UnifiedChapter {
    // 判断章节是否已读（基于当前阅读位置）
    const isRead = index < currentChapterIndex;
    
    return {
      id: chapter.id,
      title: chapter.title,
      index: index,
      isRead: isRead,
      isDownloaded: true, // 本地电子书章节都是已下载的
      isBookmarked: false,
      wordCount: chapter.wordCount,
      originalData: chapter,
      originalType: UnifiedContentType.EBOOK
    };
  }
  
  /**
   * 从统一章节获取原始电子书章节
   */
  static getOriginalChapter(unifiedChapter: UnifiedChapter): EBookChapter | null {
    if (unifiedChapter.originalType !== UnifiedContentType.EBOOK) {
      logger.warn(TAG, '尝试从非电子书章节获取电子书数据');
      return null;
    }
    return unifiedChapter.originalData as EBookChapter;
  }
  
  /**
   * 从统一内容获取原始电子书数据
   */
  static getOriginalEBook(unifiedContent: UnifiedContent): EBook | null {
    if (unifiedContent.originalType !== UnifiedContentType.EBOOK) {
      logger.warn(TAG, '尝试从非电子书内容获取电子书数据');
      return null;
    }
    return unifiedContent.originalData as EBook;
  }
  
  private static getReadStatus(ebook: EBook): UnifiedReadStatus {
    if (ebook.status === EBookStatus.UNREAD) return UnifiedReadStatus.UNREAD;
    if (ebook.status === EBookStatus.COMPLETED) return UnifiedReadStatus.COMPLETED;
    return UnifiedReadStatus.READING;
  }
}

/**
 * 小说适配器
 */
export class NovelAdapter {
  /**
   * 将小说数据转换为统一内容模型
   */
  static toUnifiedContent(
    book: LegadoBook,
    chapters: LegadoChapter[],
    isFavorite: boolean = false,
    cachedChapterIndexes: Set<number> = new Set(),
    lastReadChapterIndex: number = -1,
    sourceId?: string
  ): UnifiedContent {
    const unifiedChapters = chapters.map((chapter, index) => 
      NovelAdapter.toUnifiedChapter(chapter, index, lastReadChapterIndex, cachedChapterIndexes)
    );
    
    const readCount = lastReadChapterIndex >= 0 ? lastReadChapterIndex + 1 : 0;
    const totalCount = unifiedChapters.length;
    
    return {
      id: book.bookUrl || '',
      title: book.name || '未知书名',
      coverUrl: book.coverUrl || '',
      author: book.author || '未知作者',
      description: book.intro || '',
      
      contentType: UnifiedContentType.NOVEL,
      genres: book.kind ? book.kind.split(',').map(s => s.trim()) : [],
      tags: [],
      
      readStatus: NovelAdapter.getReadStatus(readCount, totalCount),
      isFavorite: isFavorite,
      isNSFW: book.isNSFW || false,
      
      totalChapters: totalCount,
      readChapters: readCount,
      lastReadChapterIndex: lastReadChapterIndex,
      lastReadChapterTitle: lastReadChapterIndex >= 0 && lastReadChapterIndex < chapters.length 
        ? chapters[lastReadChapterIndex].title : '',
      lastReadTime: undefined,
      readProgress: totalCount > 0 ? Math.round((readCount / totalCount) * 100) : 0,
      
      sourceId: sourceId,
      sourceName: book.origin,
      sourceUrl: book.bookUrl,
      isLocal: !sourceId || sourceId === 'local',
      
      chapters: unifiedChapters,
      originalData: book,
      originalType: UnifiedContentType.NOVEL
    };
  }
  
  /**
   * 将小说章节转换为统一章节模型
   */
  static toUnifiedChapter(
    chapter: LegadoChapter,
    index: number,
    lastReadChapterIndex: number,
    cachedChapterIndexes: Set<number>
  ): UnifiedChapter {
    return {
      id: chapter.url || String(index),
      title: chapter.title,
      index: index,
      isRead: index <= lastReadChapterIndex,
      isDownloaded: cachedChapterIndexes.has(index),
      isBookmarked: false,
      wordCount: undefined,
      originalData: chapter,
      originalType: UnifiedContentType.NOVEL
    };
  }
  
  /**
   * 从统一章节获取原始小说章节
   */
  static getOriginalChapter(unifiedChapter: UnifiedChapter): LegadoChapter | null {
    if (unifiedChapter.originalType !== UnifiedContentType.NOVEL) {
      logger.warn(TAG, '尝试从非小说章节获取小说数据');
      return null;
    }
    return unifiedChapter.originalData as LegadoChapter;
  }
  
  /**
   * 从统一内容获取原始小说数据
   */
  static getOriginalNovel(unifiedContent: UnifiedContent): LegadoBook | null {
    if (unifiedContent.originalType !== UnifiedContentType.NOVEL) {
      logger.warn(TAG, '尝试从非小说内容获取小说数据');
      return null;
    }
    return unifiedContent.originalData as LegadoBook;
  }
  
  private static getReadStatus(readCount: number, totalCount: number): UnifiedReadStatus {
    if (readCount === 0) return UnifiedReadStatus.UNREAD;
    if (readCount >= totalCount) return UnifiedReadStatus.COMPLETED;
    return UnifiedReadStatus.READING;
  }
}

/**
 * 统一内容适配器工厂
 */
export class UnifiedContentAdapterFactory {
  /**
   * 根据内容类型获取适配后的统一内容
   */
  static adapt(
    contentType: UnifiedContentType,
    originalData: Object,
    chapters: Object[],
    options: AdapterOptions = {}
  ): UnifiedContent | null {
    try {
      switch (contentType) {
        case UnifiedContentType.MANGA:
          return MangaAdapter.toUnifiedContent(
            originalData as Manga,
            chapters as MangaChapter[],
            options.isFavorite,
            options.readChapterIds,
            options.downloadedChapterIds,
            options.bookmarkedChapterIds,
            options.lastReadChapterIndex,
            options.sourceId,
            options.sourceName
          );
          
        case UnifiedContentType.EBOOK:
          return EBookAdapter.toUnifiedContent(
            originalData as EBook,
            options.isFavorite
          );
          
        case UnifiedContentType.NOVEL:
          return NovelAdapter.toUnifiedContent(
            originalData as LegadoBook,
            chapters as LegadoChapter[],
            options.isFavorite,
            options.cachedChapterIndexes,
            options.lastReadChapterIndex,
            options.sourceId
          );
          
        default:
          logger.error(TAG, `未知的内容类型: ${contentType}`);
          return null;
      }
    } catch (error) {
      logger.error(TAG, `适配内容失败: ${String(error)}`);
      return null;
    }
  }
}

/**
 * 适配器选项
 */
export interface AdapterOptions {
  isFavorite?: boolean;
  readChapterIds?: Set<string>;
  downloadedChapterIds?: Set<string>;
  bookmarkedChapterIds?: Set<string>;
  cachedChapterIndexes?: Set<number>;
  lastReadChapterIndex?: number;
  sourceId?: string;
  sourceName?: string;
}
