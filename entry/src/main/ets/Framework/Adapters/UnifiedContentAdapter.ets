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
    logger.debug(TAG, `[toUnifiedContent-1] 开始, chapters.length=${chapters?.length}, lastReadChapterIndex=${lastReadChapterIndex}`);
    
    // [修复] 先验证 chapters 数组
    if (!chapters || !Array.isArray(chapters)) {
      logger.error(TAG, `[toUnifiedContent] chapters 不是有效数组`);
      chapters = [];
    }
    
    logger.debug(TAG, `[toUnifiedContent-2] 开始转换章节`);
    const unifiedChapters: UnifiedChapter[] = [];
    for (let i = 0; i < chapters.length; i++) {
      try {
        const chapter = chapters[i];
        const unified = MangaAdapter.toUnifiedChapter(chapter, i, readChapterIds, downloadedChapterIds, bookmarkedChapterIds);
        unifiedChapters.push(unified);
      } catch (err) {
        logger.error(TAG, `[toUnifiedContent] 转换章节${i}失败: ${String(err)}`);
      }
    }
    logger.debug(TAG, `[toUnifiedContent-3] 章节转换完成, unifiedChapters.length=${unifiedChapters.length}`);
    
    logger.debug(TAG, `[toUnifiedContent-4] 计算已读数量`);
    let readCount = 0;
    for (let i = 0; i < unifiedChapters.length; i++) {
      if (unifiedChapters[i].isRead) {
        readCount++;
      }
    }
    const totalCount = unifiedChapters.length;
    logger.debug(TAG, `[toUnifiedContent-5] readCount=${readCount}, totalCount=${totalCount}`);
    
    // 从 metadata中提取作者信息
    logger.debug(TAG, `[toUnifiedContent-6] 提取作者信息`);
    let authorName = '未知作者';
    try {
      if (manga && manga.metadata && manga.metadata.authors && manga.metadata.authors.length > 0) {
        authorName = manga.metadata.authors.join(', ');
      }
    } catch (err) {
      logger.error(TAG, `[toUnifiedContent] 提取作者失败: ${String(err)}`);
    }
    logger.debug(TAG, `[toUnifiedContent-7] authorName=${authorName}`);
    
    // [修复] 显式验证 lastReadChapterIndex，避免 ArkTS 短路求值问题
    logger.debug(TAG, `[toUnifiedContent-8] 验证 lastReadChapterIndex`);
    let safeLastReadIndex = lastReadChapterIndex;
    if (typeof safeLastReadIndex !== 'number' || isNaN(safeLastReadIndex) || safeLastReadIndex < 0 || safeLastReadIndex >= chapters.length) {
      safeLastReadIndex = -1;
    }
    logger.debug(TAG, `[toUnifiedContent-9] safeLastReadIndex=${safeLastReadIndex}`);
    
    // [修复] 先计算 lastReadChapterTitle，避免在对象字面量中使用复杂条件表达式
    logger.debug(TAG, `[toUnifiedContent-10] 计算 lastReadChapterTitle`);
    let lastReadChapterTitle = '';
    if (safeLastReadIndex >= 0 && safeLastReadIndex < chapters.length) {
      lastReadChapterTitle = chapters[safeLastReadIndex].title;
    }
    logger.debug(TAG, `[toUnifiedContent-11] lastReadChapterTitle=${lastReadChapterTitle}`);
    
    // [修复] 逐个字段安全构建，避免 ArkTS 对象字面量中的潜在问题
    logger.debug(TAG, `[toUnifiedContent-12] 开始构建返回对象`);
    
    // 安全提取各个字段
    const safeId = manga.id || '';
    const safeTitle = manga.title || '';
    const safeCoverUrl = manga.coverImagePath || '';
    const safeDescription = manga.description || '';
    
    logger.debug(TAG, `[toUnifiedContent-13] 基本字段提取完成`);
    
    // 安全提取 metadata 字段
    let safeGenres: string[] = [];
    let safeTags: string[] = [];
    try {
      if (manga && manga.metadata) {
        if (manga.metadata.genres && Array.isArray(manga.metadata.genres)) {
          safeGenres = manga.metadata.genres;
        }
        if (manga.metadata.themes && Array.isArray(manga.metadata.themes)) {
          safeTags = manga.metadata.themes;
        }
      }
    } catch (err) {
      logger.error(TAG, `[toUnifiedContent] 提取 metadata 字段失败: ${String(err)}`);
    }
    logger.debug(TAG, `[toUnifiedContent-14] metadata 字段提取完成, genres=${safeGenres.length}, tags=${safeTags.length}`);
    
    // 安全获取阅读状态
    logger.debug(TAG, `[toUnifiedContent-15] 计算阅读状态`);
    const safeReadStatus = MangaAdapter.getReadStatus(readCount, totalCount);
    logger.debug(TAG, `[toUnifiedContent-16] safeReadStatus=${safeReadStatus}`);
    
    // 安全计算进度
    let safeReadProgress = 0;
    if (totalCount > 0) {
      safeReadProgress = Math.round((readCount / totalCount) * 100);
    }
    logger.debug(TAG, `[toUnifiedContent-17] safeReadProgress=${safeReadProgress}`);
    
    // 安全提取图源信息
    let safeSourceName = sourceName || '';
    let safeSourceUrl = '';
    try {
      if (!safeSourceName && manga && manga.sourceInfo && manga.sourceInfo.sourceName) {
        safeSourceName = manga.sourceInfo.sourceName;
      }
      if (manga && manga.sourceInfo && manga.sourceInfo.sourceUrl) {
        safeSourceUrl = manga.sourceInfo.sourceUrl;
      }
    } catch (err) {
      logger.error(TAG, `[toUnifiedContent] 提取图源信息失败: ${String(err)}`);
    }
    logger.debug(TAG, `[toUnifiedContent-18] 图源信息提取完成`);
    
    // 构建最终对象
    logger.debug(TAG, `[toUnifiedContent-19] 构建最终对象`);
    const result: UnifiedContent = {
      id: safeId,
      title: safeTitle,
      coverUrl: safeCoverUrl,
      author: authorName,
      description: safeDescription,
      
      contentType: UnifiedContentType.MANGA,
      genres: safeGenres,
      tags: safeTags,
      
      readStatus: safeReadStatus,
      isFavorite: isFavorite,
      isNSFW: manga.isNSFW || false,
      
      totalChapters: totalCount,
      readChapters: readCount,
      lastReadChapterIndex: safeLastReadIndex,
      lastReadChapterTitle: lastReadChapterTitle,
      lastReadTime: manga.lastUpdatedAt,
      readProgress: safeReadProgress,
      
      sourceId: sourceId,
      sourceName: safeSourceName,
      sourceUrl: safeSourceUrl,
      isLocal: !sourceId,
      
      chapters: unifiedChapters,
      originalData: manga,
      originalType: UnifiedContentType.MANGA
    };
    
    logger.debug(TAG, `[toUnifiedContent-20] 对象构建完成，准备返回`);
    return result;
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
    // [修复] 安全提取各个字段，避免 ArkTS 的潜在问题
    const safeId = chapter.id || '';
    const safeTitle = chapter.title || '';
    
    // 安全检查已读/已下载/书签状态
    let isRead = false;
    let isDownloaded = false;
    let isBookmarked = false;
    try {
      if (readChapterIds && safeId) {
        isRead = readChapterIds.has(safeId);
      }
      if (downloadedChapterIds && safeId) {
        isDownloaded = downloadedChapterIds.has(safeId);
      }
      if (bookmarkedChapterIds && safeId) {
        isBookmarked = bookmarkedChapterIds.has(safeId);
      }
    } catch (err) {
      logger.warn(TAG, `[toUnifiedChapter] 检查状态失败: ${String(err)}`);
    }
    
    // 安全获取页面数
    let safePageCount = 0;
    try {
      if (chapter.pages && Array.isArray(chapter.pages) && chapter.pages.length > 0) {
        safePageCount = chapter.pages.length;
      } else if (typeof chapter.totalPages === 'number' && chapter.totalPages > 0) {
        safePageCount = chapter.totalPages;
      }
    } catch (err) {
      logger.warn(TAG, `[toUnifiedChapter] 获取页面数失败: ${String(err)}`);
    }
    
    // 安全获取发布日期
    let safePublishDate: string | undefined = undefined;
    try {
      if (typeof chapter.publishDate === 'number') {
        safePublishDate = new Date(chapter.publishDate).toISOString();
      } else if (chapter.publishDate) {
        safePublishDate = String(chapter.publishDate);
      }
    } catch (err) {
      logger.warn(TAG, `[toUnifiedChapter] 获取发布日期失败: ${String(err)}`);
    }
    
    return {
      id: safeId,
      title: safeTitle,
      index: index,
      isRead: isRead,
      isDownloaded: isDownloaded,
      isBookmarked: isBookmarked,
      pageCount: safePageCount,
      publishDate: safePublishDate,
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
    
    // [修复] 显式验证 currentChapterIndex，避免 ArkTS 短路求值问题
    let safeCurrentChapterIndex = currentChapterIndex;
    if (typeof safeCurrentChapterIndex !== 'number' || isNaN(safeCurrentChapterIndex) || safeCurrentChapterIndex < 0 || safeCurrentChapterIndex >= chapters.length) {
      safeCurrentChapterIndex = 0;  // 电子书默认从第0章开始
    }
    
    // [修复] 先计算 lastReadChapterTitle，避免在对象字面量中使用复杂条件表达式
    let lastReadChapterTitle = '';
    if (safeCurrentChapterIndex >= 0 && safeCurrentChapterIndex < chapters.length) {
      lastReadChapterTitle = chapters[safeCurrentChapterIndex].title;
    }
    
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
      lastReadChapterIndex: safeCurrentChapterIndex,
      lastReadChapterTitle: lastReadChapterTitle,
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
    
    // [修复] 显式验证 lastReadChapterIndex，避免 ArkTS 短路求值问题
    let safeLastReadIndex = lastReadChapterIndex;
    if (typeof safeLastReadIndex !== 'number' || isNaN(safeLastReadIndex) || safeLastReadIndex < 0 || safeLastReadIndex >= chapters.length) {
      safeLastReadIndex = -1;
    }
    
    // [修复] 先计算 lastReadChapterTitle，避免在对象字面量中使用复杂条件表达式
    let lastReadChapterTitle = '';
    if (safeLastReadIndex >= 0 && safeLastReadIndex < chapters.length) {
      lastReadChapterTitle = chapters[safeLastReadIndex].title;
    }
    
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
      lastReadChapterIndex: safeLastReadIndex,
      lastReadChapterTitle: lastReadChapterTitle,
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
