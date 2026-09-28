import { SafeUtils } from '../../Utils/SafeUtils';
/**
 * 漫画类型适配器
 * 将旧的数据库类型转换为新的类型系统
 */

import { logger } from '../../Utils/Logger';
import {
  Manga,
  LocalManga,
  OnlineManga,
  Chapter,
  LocalChapter,
  OnlineChapter,
  PageInfo,
  MangaSourceType,
  OnlineChapterDownloadStatus
} from '../Types/MangaTypes';

const TAG = 'MangaTypeAdapter';

/**
 * 旧的ComicInfo类型（从数据库返回）
 */
export interface LegacyComicInfo {
  id: string;
  sourceId?: number | string;
  externalId?: string;
  title: string;
  author?: string;
  description?: string;
  coverUrl?: string;
  coverLocalPath?: string;
  tags?: string;
  createTime?: number;
  updateTime?: number;
  localPath?: string;
  fileSize?: number;
  sourceUrl?: string;
  lastSyncTime?: number;
}

/**
 * 旧的ChapterInfo类型
 */
export interface LegacyChapterInfo {
  id: string;
  comicId: string;
  externalId?: string;
  title: string;
  chapterNumber?: number;
  index?: number;
  pageCount?: number;
  isDownloaded?: boolean;
  downloadPath?: string;
  publishTime?: number;
  createTime?: number;
  localPath?: string;
  url?: string;
}

/**
 * 旧的PageInfo类型
 */
export interface LegacyPageInfo {
  id: string;
  chapterId: string;
  pageNumber: number;
  imageUrl?: string;
  localPath?: string;
  width?: number;
  height?: number;
}

/**
 * 漫画类型适配器
 */
export class MangaTypeAdapter {
  /**
   * 将旧的ComicInfo转换为新的Manga类型
   */
  static convertToManga(legacy: LegacyComicInfo, sourceName?: string): Manga {
    // 判断是本地漫画还是在线漫画
    const isLocal = !legacy.sourceId && !legacy.externalId;

    if (isLocal) {
      // 本地漫画
      const localManga: LocalManga = {
        id: legacy.id,
        sourceType: MangaSourceType.LOCAL,
        title: legacy.title,
        author: legacy.author,
        description: legacy.description,
        coverUrl: legacy.coverUrl,
        coverLocalPath: legacy.coverLocalPath,
        tags: MangaTypeAdapter.parseTags(legacy.tags),
        createTime: legacy.createTime || Date.now(),
        updateTime: legacy.updateTime || Date.now(),
        localPath: legacy.localPath || '',
        fileSize: legacy.fileSize
      };
      return localManga;
    } else {
      // 在线漫画
      const sourceIdNum = typeof legacy.sourceId === 'string'
        ? parseInt(legacy.sourceId)
        : (legacy.sourceId || 0);

      const onlineManga: OnlineManga = {
        id: legacy.id,
        sourceType: MangaSourceType.ONLINE,
        title: legacy.title,
        author: legacy.author,
        description: legacy.description,
        coverUrl: legacy.coverUrl,
        coverLocalPath: legacy.coverLocalPath,
        tags: MangaTypeAdapter.parseTags(legacy.tags),
        createTime: legacy.createTime || Date.now(),
        updateTime: legacy.updateTime || Date.now(),
        sourceName: sourceName || 'unknown',
        sourceId: sourceIdNum,
        externalId: legacy.externalId || '',
        sourceUrl: legacy.sourceUrl,
        isInLibrary: true, // 如果在数据库中，说明已加入书库
        lastSyncTime: legacy.lastSyncTime || legacy.updateTime
      };
      return onlineManga;
    }
  }

  /**
   * 将旧的ChapterInfo转换为新的Chapter类型
   */
  static convertToChapter(legacy: LegacyChapterInfo): Chapter {
    // 判断是本地章节还是在线章节
    const isLocal = !legacy.externalId;

    if (isLocal) {
      // 本地章节
      const localChapter: LocalChapter = {
        id: legacy.id,
        mangaId: legacy.comicId,
        title: legacy.title,
        chapterNumber: legacy.chapterNumber || legacy.index || 0,
        pageCount: legacy.pageCount || 0,
        createTime: legacy.createTime || Date.now(),
        localPath: legacy.localPath || legacy.downloadPath || ''
      };
      return localChapter;
    } else {
      // 在线章节
      const downloadStatus = MangaTypeAdapter.getDownloadStatus(legacy.isDownloaded, legacy.downloadPath);

      const onlineChapter: OnlineChapter = {
        id: legacy.id,
        mangaId: legacy.comicId,
        title: legacy.title,
        chapterNumber: legacy.chapterNumber || legacy.index || 0,
        pageCount: legacy.pageCount || 0,
        createTime: legacy.createTime || Date.now(),
        externalId: legacy.externalId || '',
        sourceUrl: legacy.url,
        downloadStatus,
        downloadPath: legacy.downloadPath,
        publishTime: legacy.publishTime
      };
      return onlineChapter;
    }
  }

  /**
   * 将旧的PageInfo转换为新的PageInfo类型
   */
  static convertToPageInfo(legacy: LegacyPageInfo): PageInfo {
    return {
      id: legacy.id,
      chapterId: legacy.chapterId,
      pageNumber: legacy.pageNumber,
      imageUrl: legacy.imageUrl,
      localPath: legacy.localPath,
      width: legacy.width,
      height: legacy.height
    };
  }

  /**
   * 批量转换章节
   */
  static convertToChapters(legacyChapters: LegacyChapterInfo[]): Chapter[] {
    return legacyChapters.map(ch => MangaTypeAdapter.convertToChapter(ch));
  }

  /**
   * 批量转换页面
   */
  static convertToPages(legacyPages: LegacyPageInfo[]): PageInfo[] {
    return legacyPages.map(p => MangaTypeAdapter.convertToPageInfo(p));
  }

  /**
   * 解析标签字符串
   */
  private static parseTags(tagsStr?: string): string[] | undefined {
    if (!tagsStr) return undefined;

    try {
      // 尝试解析JSON数组
      const parsed = SafeUtils.parseObj<string[]>(tagsStr);
      if (Array.isArray(parsed)) {
        return parsed;
      }
    } catch (e) {
      // 如果不是JSON，尝试按逗号分割
      if (tagsStr.includes(',')) {
        return tagsStr.split(',').map(t => t.trim()).filter(t => t.length > 0);
      }
    }

    return [tagsStr];
  }

  /**
   * 获取下载状态
   */
  private static getDownloadStatus(
    isDownloaded?: boolean,
    downloadPath?: string
  ): OnlineChapterDownloadStatus {
    if (isDownloaded && downloadPath) {
      return OnlineChapterDownloadStatus.DOWNLOADED;
    }
    return OnlineChapterDownloadStatus.NOT_DOWNLOADED;
  }

  /**
   * 将新的Manga类型转换回旧的ComicInfo（用于数据库保存）
   */
  static convertFromManga(manga: Manga): LegacyComicInfo {
    const base: LegacyComicInfo = {
      id: manga.id,
      title: manga.title,
      author: manga.author,
      description: manga.description,
      coverUrl: manga.coverUrl,
      coverLocalPath: manga.coverLocalPath,
      tags: manga.tags ? JSON.stringify(manga.tags) : undefined,
      createTime: manga.createTime,
      updateTime: manga.updateTime
    };

    if (manga.sourceType === MangaSourceType.LOCAL) {
      const localManga = manga as LocalManga;
      base.localPath = localManga.localPath;
      base.fileSize = localManga.fileSize;
    } else {
      const onlineManga = manga as OnlineManga;
      base.sourceId = onlineManga.sourceId;
      base.externalId = onlineManga.externalId;
      base.sourceUrl = onlineManga.sourceUrl;
      base.lastSyncTime = onlineManga.lastSyncTime;
    }
    return base;
  }

  /**
   * 将新的Chapter类型转换回旧的ChapterInfo
   */
  static convertFromChapter(chapter: Chapter): LegacyChapterInfo {
    const base: LegacyChapterInfo = {
      id: chapter.id,
      comicId: chapter.mangaId,
      title: chapter.title,
      chapterNumber: chapter.chapterNumber,
      pageCount: chapter.pageCount,
      createTime: chapter.createTime
    };

    if (!((chapter as OnlineChapter).externalId !== undefined &&
      (chapter as OnlineChapter).downloadStatus !== undefined)) {
      // 本地章节
      const localChapter = chapter as LocalChapter;
      base.localPath = localChapter.localPath;
    } else {
      // 在线章节
      const onlineChapter = chapter as OnlineChapter;
      base.externalId = onlineChapter.externalId;
      base.url = onlineChapter.sourceUrl;
      base.isDownloaded = onlineChapter.downloadStatus === OnlineChapterDownloadStatus.DOWNLOADED;
      base.downloadPath = onlineChapter.downloadPath;
      base.publishTime = onlineChapter.publishTime;
    }
    return base;
  }
}
