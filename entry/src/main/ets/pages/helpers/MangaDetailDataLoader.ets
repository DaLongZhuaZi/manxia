/**
 * MangaDetailPage 数据加载辅助类
 * 使用新的类型系统和数据加载策略
 */

import { logger } from '../../Utils/Logger';
import { MangaDataLoader, MangaDetailLoadResult } from '../../Framework/Managers/MangaDataLoader';
import { 
  Manga, 
  Chapter,
  isOnlineManga,
  MangaSourceType 
} from '../../Framework/Types/MangaTypes';
import { ComicConverter } from '../../Framework/Utils/ComicConverter';
import { MangaTypeAdapter } from '../../Framework/Adapters/MangaTypeAdapter';
import { DataManager } from '../../Framework/Data/DataManager';
import { Manga as LegacyManga, MangaChapter as LegacyChapter } from '../../Models/MangaModels';
import { DownloadStatus } from '../../Framework/Types/StatusEnums';

const TAG = 'MangaDetailDataLoader';

/**
 * 加载结果
 */
export interface DetailPageLoadResult {
  /** 漫画信息（旧格式，用于UI显示） */
  manga: LegacyManga;
  
  /** 章节列表（旧格式，用于UI显示） */
  chapters: LegacyChapter[];
  
  /** 数据来源 */
  dataSource: 'cache' | 'network';
  
  /** 是否需要刷新 */
  needsRefresh: boolean;
  
  /** 图源名称 */
  sourceName?: string;
}

/**
 * MangaDetailPage 数据加载器
 */
export class MangaDetailDataLoader {
  private dataLoader: MangaDataLoader;
  private dataManager: DataManager;
  
  constructor() {
    this.dataLoader = MangaDataLoader.getInstance();
    this.dataManager = DataManager.getInstance();
  }
  
  /**
   * 加载漫画详情数据
   * @param mangaId 漫画ID
   * @param forceRefresh 是否强制刷新
   * @returns 加载结果
   */
  async loadMangaDetail(
    mangaId: string,
    forceRefresh: boolean = false
  ): Promise<DetailPageLoadResult> {
    logger.info(TAG, `开始加载漫画详情: mangaId=${mangaId}, forceRefresh=${forceRefresh}`);
    
    try {
      // 使用新的数据加载器
      const result = await this.dataLoader.loadMangaDetail(mangaId, forceRefresh);
      
      logger.info(TAG, `数据加载完成: dataSource=${result.dataSource}, needsRefresh=${result.needsRefresh}`);
      logger.info(TAG, `漫画类型: ${result.manga.sourceType}, 章节数: ${result.chapters.length}`);
      
      // 转换为旧格式用于UI显示
      const legacyManga = await this.convertToLegacyManga(result.manga, result.chapters);
      const legacyChapters = this.convertToLegacyChapters(result.chapters);
      
      return {
        manga: legacyManga,
        chapters: legacyChapters,
        dataSource: result.dataSource,
        needsRefresh: result.needsRefresh,
        sourceName: isOnlineManga(result.manga) ? result.manga.sourceName : undefined
      };
    } catch (error) {
      logger.error(TAG, `加载漫画详情失败: ${error}`);
      throw error;
    }
  }
  
  /**
   * 将新的Manga类型转换为旧的Manga类型（用于UI显示）
   */
  private async convertToLegacyManga(manga: Manga, chapters: Chapter[]): Promise<LegacyManga> {
    // 先转换为数据库格式
    const legacyComicInfo = MangaTypeAdapter.convertFromManga(manga);
    
    // 再转换为UI格式
    const uiManga = await ComicConverter.convertComicInfoToMangaAsync(legacyComicInfo as any);
    
    // 设置章节列表
    uiManga.chapters = this.convertToLegacyChapters(chapters);
    
    return uiManga;
  }
  
  /**
   * 将新的Chapter数组转换为旧的MangaChapter数组
   */
  private convertToLegacyChapters(chapters: Chapter[]): LegacyChapter[] {
    return chapters.map((chapter, index) => {
      // 转换为数据库格式
      const dbChapter = MangaTypeAdapter.convertFromChapter(chapter);
      
      // 获取发布时间
      const publishTime = 'publishTime' in dbChapter ? dbChapter.publishTime : undefined;
      
      // 转换为UI格式
      const legacyChapter: LegacyChapter = {
        id: chapter.id,
        title: chapter.title,
        chapterNumber: chapter.chapterNumber,
        pages: [], // 页面数据按需加载
        publishDate: publishTime ? new Date(publishTime) : new Date(),
        language: 'zh-CN', // 默认中文
        scanlationGroup: '', // 扫描组信息暂不支持
        isDownloaded: 'isDownloaded' in dbChapter ? dbChapter.isDownloaded || false : false,
        downloadStatus: 'isDownloaded' in dbChapter && dbChapter.isDownloaded 
          ? DownloadStatus.COMPLETED
          : DownloadStatus.PENDING,
        downloadProgress: 'isDownloaded' in dbChapter && dbChapter.isDownloaded ? 100 : 0,
        localPath: 'downloadPath' in dbChapter ? dbChapter.downloadPath : undefined
      };
      
      return legacyChapter;
    });
  }
  
  /**
   * 判断漫画是否为本地漫画
   */
  async isLocalManga(mangaId: string): Promise<boolean> {
    try {
      const comicInfo = await this.dataManager.getComicById(mangaId);
      if (!comicInfo) {
        return false;
      }
      
      // 判断逻辑：没有sourceId或sourceId为'local_import'
      const hasNoSource = !comicInfo.sourceId || comicInfo.sourceId === 'local_import';
      logger.info(TAG, `漫画来源检测: sourceId=${comicInfo.sourceId}, isLocal=${hasNoSource}`);
      return hasNoSource;
    } catch (error) {
      logger.error(TAG, `判断漫画类型失败: ${error}`);
      return false;
    }
  }
  
  /**
   * 获取图源名称
   */
  async getSourceName(sourceId: number): Promise<string | null> {
    return await this.dataLoader.getSourceNameById(sourceId);
  }
  
  /**
   * 获取图源ID
   */
  async getSourceId(sourceName: string): Promise<number | null> {
    return await this.dataLoader.getSourceIdByName(sourceName);
  }
}
