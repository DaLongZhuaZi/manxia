/**
 * Tab内容缓存管理器
 * 持久化缓存书源(BOOK_SOURCE)和Suwayomi两个Tab的完整内容数据
 * 冷启动时先显示缓存内容，再静默刷新增量更新
 *
 * 文件路径: entry/src/main/ets/Framework/Cache/TabContentCacheManager.ets
 */

import { logger } from '../../Utils/Logger';
import { preferences } from '@kit.ArkData';
import { NovelSearchResult, NovelSourceInfo } from '../../Models/NovelModels';
import { ComicInfo } from '../Source/SourceExecutor';
import { SuwayomiCategory } from '../Source/SuwayomiSource';

const TAG = 'TabContentCacheManager';

/**
 * 书源发现分类缓存
 */
interface CachedExploreKind {
  title: string;
  url: string;
}

/**
 * 书源Tab缓存数据
 */
export interface BookSourceCacheData {
  bookSourceList: NovelSourceInfo[];
  selectedBookSourceId: string;
  selectedBookSourceName: string;
  bookSourceExploreKinds: CachedExploreKind[];
  selectedBookSourceKindIndex: number;
  bookSourceBooks: NovelSearchResult[];
  timestamp: number;
}

/**
 * Suwayomi Tab缓存数据
 */
export interface SuwayomiCacheData {
  mangas: ComicInfo[];
  categories: SuwayomiCategory[];
  selectedCategoryId: number;
  selectedSortIndex: number;
  browseMode: string;
  totalCount: number;
  hasMore: boolean;
  currentOffset: number;
  timestamp: number;
}

/**
 * Tab内容缓存管理器单例
 */
export class TabContentCacheManager {
  private static instance: TabContentCacheManager | null = null;
  private bookSourceCache: BookSourceCacheData | null = null;
  private suwayomiCache: SuwayomiCacheData | null = null;
  private initialized: boolean = false;
  private readonly PREF_NAME = 'tab_content_cache';
  private readonly BOOK_SOURCE_KEY = 'book_source_cache';
  private readonly SUWAYOMI_KEY = 'suwayomi_cache';

  private constructor() {
    logger.info(TAG, 'Tab内容缓存管理器创建');
  }

  static getInstance(): TabContentCacheManager {
    if (!TabContentCacheManager.instance) {
      TabContentCacheManager.instance = new TabContentCacheManager();
    }
    return TabContentCacheManager.instance;
  }

  /**
   * 初始化（从持久化存储加载缓存）
   */
  async initialize(): Promise<void> {
    if (this.initialized) return;
    try {
      const dataPreferences = await preferences.getPreferences(getContext(), this.PREF_NAME);

      // 加载书源缓存
      const bookSourceJson = await dataPreferences.get(this.BOOK_SOURCE_KEY, '') as string;
      if (bookSourceJson) {
        this.bookSourceCache = JSON.parse(bookSourceJson) as BookSourceCacheData;
        logger.info(TAG, `加载书源缓存: ${this.bookSourceCache.bookSourceBooks.length} 本书, 书源: ${this.bookSourceCache.selectedBookSourceName}`);
      }

      // 加载Suwayomi缓存
      const suwayomiJson = await dataPreferences.get(this.SUWAYOMI_KEY, '') as string;
      if (suwayomiJson) {
        this.suwayomiCache = JSON.parse(suwayomiJson) as SuwayomiCacheData;
        logger.info(TAG, `加载Suwayomi缓存: ${this.suwayomiCache.mangas.length} 部漫画, ${this.suwayomiCache.categories.length} 个分类`);
      }

      this.initialized = true;
      logger.info(TAG, '缓存初始化完成');
    } catch (error) {
      logger.error(TAG, `缓存初始化失败: ${String(error)}`);
    }
  }

  // ==================== 书源缓存 ====================

  /**
   * 保存书源Tab缓存
   */
  async saveBookSourceCache(data: BookSourceCacheData): Promise<void> {
    try {
      this.bookSourceCache = data;
      const dataPreferences = await preferences.getPreferences(getContext(), this.PREF_NAME);
      await dataPreferences.put(this.BOOK_SOURCE_KEY, JSON.stringify(data));
      await dataPreferences.flush();
      logger.debug(TAG, `书源缓存已保存: ${data.bookSourceBooks.length} 本书`);
    } catch (error) {
      logger.error(TAG, `保存书源缓存失败: ${String(error)}`);
    }
  }

  /**
   * 获取书源Tab缓存
   */
  getBookSourceCache(): BookSourceCacheData | null {
    return this.bookSourceCache;
  }

  /**
   * 是否有书源缓存数据
   */
  hasBookSourceCache(): boolean {
    return this.bookSourceCache !== null && this.bookSourceCache.bookSourceBooks.length > 0;
  }

  // ==================== Suwayomi缓存 ====================

  /**
   * 保存Suwayomi Tab缓存
   */
  async saveSuwayomiCache(data: SuwayomiCacheData): Promise<void> {
    try {
      this.suwayomiCache = data;
      const dataPreferences = await preferences.getPreferences(getContext(), this.PREF_NAME);
      await dataPreferences.put(this.SUWAYOMI_KEY, JSON.stringify(data));
      await dataPreferences.flush();
      logger.debug(TAG, `Suwayomi缓存已保存: ${data.mangas.length} 部漫画`);
    } catch (error) {
      logger.error(TAG, `保存Suwayomi缓存失败: ${String(error)}`);
    }
  }

  /**
   * 获取Suwayomi Tab缓存
   */
  getSuwayomiCache(): SuwayomiCacheData | null {
    return this.suwayomiCache;
  }

  /**
   * 是否有Suwayomi缓存数据
   */
  hasSuwayomiCache(): boolean {
    return this.suwayomiCache !== null && this.suwayomiCache.mangas.length > 0;
  }

  // ==================== 通用方法 ====================

  /**
   * 清除所有缓存
   */
  async clearAll(): Promise<void> {
    try {
      this.bookSourceCache = null;
      this.suwayomiCache = null;
      const dataPreferences = await preferences.getPreferences(getContext(), this.PREF_NAME);
      await dataPreferences.delete(this.BOOK_SOURCE_KEY);
      await dataPreferences.delete(this.SUWAYOMI_KEY);
      await dataPreferences.flush();
      logger.info(TAG, '所有Tab内容缓存已清除');
    } catch (error) {
      logger.error(TAG, `清除缓存失败: ${String(error)}`);
    }
  }

  /**
   * 清除书源缓存
   */
  async clearBookSourceCache(): Promise<void> {
    try {
      this.bookSourceCache = null;
      const dataPreferences = await preferences.getPreferences(getContext(), this.PREF_NAME);
      await dataPreferences.delete(this.BOOK_SOURCE_KEY);
      await dataPreferences.flush();
      logger.info(TAG, '书源Tab缓存已清除');
    } catch (error) {
      logger.error(TAG, `清除书源缓存失败: ${String(error)}`);
    }
  }

  /**
   * 清除Suwayomi缓存
   */
  async clearSuwayomiCache(): Promise<void> {
    try {
      this.suwayomiCache = null;
      const dataPreferences = await preferences.getPreferences(getContext(), this.PREF_NAME);
      await dataPreferences.delete(this.SUWAYOMI_KEY);
      await dataPreferences.flush();
      logger.info(TAG, 'Suwayomi Tab缓存已清除');
    } catch (error) {
      logger.error(TAG, `清除Suwayomi缓存失败: ${String(error)}`);
    }
  }
}
