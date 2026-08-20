import { SafeUtils } from 'manxia_core/src/main/ets/Utils/SafeUtils';
/**
 * 卡片数据同步工具
 * 用于从应用主进程向桌面卡片同步阅读目标和最近阅读数据
 */
import { preferences } from '@kit.ArkData';
import { common } from '@kit.AbilityKit';
import { formProvider, formBindingData } from '@kit.FormKit';
import { ReadingAnalyticsManager, ReadingGoalsSettings } from 'manxia_core/src/main/ets/Framework/Managers/ReadingAnalyticsManager';
import { DataService } from '../Framework/Services/DataService';
import { EBookDataManager } from 'manxia_core/src/main/ets/Framework/Data/EBookDataManager';
import { EBook } from 'manxia_core/src/main/ets/Models/EBookModels';
import { getNovelDataManager } from '../Framework/Novel/NovelDataManager';
import { NovelBook } from 'manxia_core/src/main/ets/Models/NovelModels';
import { logger } from 'manxia_core/src/main/ets/Utils/Logger';
import { DataManager } from '../Framework/Data/DataManager';
import { DataInitializer } from '../Framework/Initialization/DataInitializer';

const TAG = 'WidgetDataSync';
const WIDGET_DATA_STORE = 'widget_reading_data';
const FORM_STORAGE = 'form_storage';
const RECENT_READ_LIMIT = 6;
const SYNC_MIN_INTERVAL_MS = 45 * 1000;
const DATA_READY_RETRY_DELAY_MS = 1500;

/**
 * 阅读目标数据
 */
export interface ReadingGoalData {
  mangaGoalMinutes: number;      // 漫画目标（分钟）
  mangaReadMinutes: number;      // 今日漫画阅读时间
  ebookGoalMinutes: number;      // 电子书目标
  ebookReadMinutes: number;      // 今日电子书阅读时间
  novelGoalMinutes: number;      // 小说目标
  novelReadMinutes: number;      // 今日小说阅读时间
}

/**
 * 最近阅读项
 */
export interface RecentReadItem {
  id: string;
  title: string;
  cover: string;           // 封面路径或URL
  type: string;            // 'manga' | 'ebook' | 'novel'
  progress: number;        // 阅读进度百分比 0-100
  lastReadTime: number;    // 最后阅读时间戳
}

/**
 * 卡片完整数据
 */
export interface WidgetData {
  goals: ReadingGoalData;
  recentReads: RecentReadItem[];
  lastUpdateTime: number;
}

/**
 * 今日阅读时间结果
 */
interface TodayReadingTimeResult {
  manga: number;
  ebook: number;
  novel: number;
}

/**
 * 漫画阅读记录信息
 */
interface MangaReadInfo {
  readTime: number;
  pageIndex: number;
}

/**
 * 卡片更新数据结构
 */
interface FormUpdateData {
  formId: string;
  dimension: number;
  // 阅读目标
  mangaGoal: number;
  mangaRead: number;
  mangaProgress: number;
  ebookGoal: number;
  ebookRead: number;
  ebookProgress: number;
  novelGoal: number;
  novelRead: number;
  novelProgress: number;
  // 是否设置了目标
  hasMangaGoal: boolean;
  hasEbookGoal: boolean;
  hasNovelGoal: boolean;
  hasAnyGoal: boolean;
  // 最近阅读（最多6本）
  recentCount: number;
  recent1Id: string;
  recent1Title: string;
  recent1Cover: string;
  recent1Progress: number;
  recent1Type: string;
  recent2Id: string;
  recent2Title: string;
  recent2Cover: string;
  recent2Progress: number;
  recent2Type: string;
  recent3Id: string;
  recent3Title: string;
  recent3Cover: string;
  recent3Progress: number;
  recent3Type: string;
  recent4Id: string;
  recent4Title: string;
  recent4Cover: string;
  recent4Progress: number;
  recent4Type: string;
  recent5Id: string;
  recent5Title: string;
  recent5Cover: string;
  recent5Progress: number;
  recent5Type: string;
  recent6Id: string;
  recent6Title: string;
  recent6Cover: string;
  recent6Progress: number;
  recent6Type: string;
}

/**
 * 卡片数据同步管理器
 */
export class WidgetDataSync {
  private static instance: WidgetDataSync | null = null;
  private context: common.UIAbilityContext | null = null;
  private lastSyncTimestamp: number = 0;
  private syncInFlight: Promise<void> | null = null;
  private pendingSyncAfterDataReady: boolean = false;
  private dataReadyRetryTimer: number = -1;

  private constructor() {}

  public static getInstance(): WidgetDataSync {
    if (!WidgetDataSync.instance) {
      WidgetDataSync.instance = new WidgetDataSync();
    }
    return WidgetDataSync.instance;
  }

  public init(context: common.UIAbilityContext): void {
    this.context = context;
  }

  /**
   * 从数据源加载并同步所有卡片数据
   */
  public async syncAllData(): Promise<boolean> {
    if (!this.context) {
      logger.warn(TAG, 'syncAllData: context not initialized');
      return false;
    }

    // 启动早期可能触发前后台切换，此时数据系统尚未就绪，直接跳过避免访问未初始化数据库
    const initStatus = DataInitializer.getInstance().getInitializationStatus();
    if (!initStatus.isInitialized) {
      if (initStatus.isInitializing) {
        logger.debug(TAG, 'syncAllData: data system initializing, defer widget sync');
        this.scheduleSyncAfterDataReady('data_initializing');
      } else {
        logger.debug(TAG, 'syncAllData: data system not ready, defer widget sync');
        this.scheduleSyncAfterDataReady('data_not_ready');
      }
      return false;
    }

    try {
      logger.info(TAG, '开始同步卡片数据...');
      
      // 1. 获取阅读目标设置（确保先初始化）
      const analyticsManager = ReadingAnalyticsManager.getInstance();
      await analyticsManager.initialize();
      const goalSettings: ReadingGoalsSettings = analyticsManager.getReadingGoals();
      
      // 2. 计算今日各类型阅读时间
      const todayReadingTime = await this.calculateTodayReadingTime();
      
      // 3. 构建目标数据
      const goals: ReadingGoalData = {
        mangaGoalMinutes: goalSettings.mangaGoalMinutes,
        mangaReadMinutes: todayReadingTime.manga,
        ebookGoalMinutes: goalSettings.ebookGoalMinutes,
        ebookReadMinutes: todayReadingTime.ebook,
        novelGoalMinutes: goalSettings.novelGoalMinutes,
        novelReadMinutes: todayReadingTime.novel
      };
      
      // 4. 获取最近阅读列表
      const recentReads = await this.loadRecentReads();
      
      // 5. 更新卡片数据
      await this.updateAll(goals, recentReads);
      
      logger.info(TAG, `卡片数据同步完成: 漫画目标=${goals.mangaGoalMinutes}分钟/已读=${goals.mangaReadMinutes}分钟, ` +
        `电子书目标=${goals.ebookGoalMinutes}分钟/已读=${goals.ebookReadMinutes}分钟, ` +
        `小说目标=${goals.novelGoalMinutes}分钟/已读=${goals.novelReadMinutes}分钟, ` +
        `最近阅读=${recentReads.length}本`);
      this.pendingSyncAfterDataReady = false;
      return true;
    } catch (e) {
      logger.error(TAG, `syncAllData error: ${JSON.stringify(e)}`);
      return false;
    }
  }

  /**
   * 节流同步，避免短时间重复触发高开销计算
   */
  public async syncAllDataThrottled(force: boolean = false): Promise<void> {
    const now = Date.now();
    if (!force && now - this.lastSyncTimestamp < SYNC_MIN_INTERVAL_MS) {
      logger.debug(TAG, `skip throttled sync, interval=${now - this.lastSyncTimestamp}ms`);
      return;
    }

    if (this.syncInFlight) {
      logger.debug(TAG, 'reuse in-flight widget sync task');
      return this.syncInFlight;
    }

    this.syncInFlight = this.syncAllData()
      .then((synced: boolean) => {
        if (synced) {
          this.lastSyncTimestamp = Date.now();
        }
      })
      .finally(() => {
        this.syncInFlight = null;
      });

    return this.syncInFlight;
  }

  private scheduleSyncAfterDataReady(reason: string): void {
    this.pendingSyncAfterDataReady = true;
    if (this.dataReadyRetryTimer >= 0) {
      return;
    }

    this.dataReadyRetryTimer = setTimeout(() => {
      this.dataReadyRetryTimer = -1;
      const initStatus = DataInitializer.getInstance().getInitializationStatus();
      if (initStatus.isInitialized) {
        logger.info(TAG, `数据系统已就绪，补执行卡片同步: reason=${reason}`);
        void this.syncAllDataThrottled(true);
        return;
      }
      if (initStatus.isInitializing) {
        this.scheduleSyncAfterDataReady('still_initializing');
        return;
      }
      this.pendingSyncAfterDataReady = false;
      logger.warn(TAG, `数据系统仍未就绪，取消本次卡片同步补偿: reason=${reason}`);
    }, DATA_READY_RETRY_DELAY_MS);
  }

  /**
   * 计算今日各类型阅读时间（分钟）
   */
  private async calculateTodayReadingTime(): Promise<TodayReadingTimeResult> {
    const result: TodayReadingTimeResult = { manga: 0, ebook: 0, novel: 0 };
    
    const today = new Date();
    const startOfDay = new Date(today.getFullYear(), today.getMonth(), today.getDate(), 0, 0, 0).getTime();
    const endOfDay = new Date(today.getFullYear(), today.getMonth(), today.getDate(), 23, 59, 59, 999).getTime();
    const todayKey = `${today.getFullYear()}-${String(today.getMonth() + 1).padStart(2, '0')}-${String(today.getDate()).padStart(2, '0')}`;
    
    try {
      // 1. 计算漫画阅读时间
      const dataService = DataService.getInstance();
      const readHistory = await dataService.getReadingHistory(1000);
      
      let mangaTimeMs = 0;
      for (const record of readHistory) {
        if (record.readTime >= startOfDay && record.readTime <= endOfDay) {
          mangaTimeMs += record.readDuration || 0;
        }
      }
      result.manga = Math.round(mangaTimeMs / 60000); // 毫秒转分钟
      
      // 2. 计算电子书阅读时间
      const ebookManager: EBookDataManager = EBookDataManager.getInstance();
      const ebooksWithProgress: EBook[] = await ebookManager.getEBooksWithReadingProgress();
      
      for (const ebook of ebooksWithProgress) {
        if (ebook.readingProgress && ebook.readingProgress.lastReadTime) {
          const lastReadDate = new Date(ebook.readingProgress.lastReadTime);
          const lastReadKey = `${lastReadDate.getFullYear()}-${String(lastReadDate.getMonth() + 1).padStart(2, '0')}-${String(lastReadDate.getDate()).padStart(2, '0')}`;
          
          if (lastReadKey === todayKey) {
            // 电子书的 totalReadingTime 单位是分钟
            result.ebook += Math.round(ebook.readingProgress.totalReadingTime || 0);
          }
        }
      }
      
      // 3. 计算小说阅读时间
      const novelManager = getNovelDataManager();
      const novelsWithTime: NovelBook[] = await novelManager.getBooksWithReadingTime();
      
      for (const novel of novelsWithTime) {
        if (novel.lastReadTime && novel.lastReadTime > 0) {
          const lastReadDate = new Date(novel.lastReadTime);
          const lastReadKey = `${lastReadDate.getFullYear()}-${String(lastReadDate.getMonth() + 1).padStart(2, '0')}-${String(lastReadDate.getDate()).padStart(2, '0')}`;
          
          if (lastReadKey === todayKey) {
            // 小说的 totalReadingTime 单位是秒
            result.novel += Math.round((novel.totalReadingTime || 0) / 60);
          }
        }
      }
      
      logger.debug(TAG, `今日阅读时间: 漫画=${result.manga}分钟, 电子书=${result.ebook}分钟, 小说=${result.novel}分钟`);
    } catch (e) {
      logger.error(TAG, `calculateTodayReadingTime error: ${JSON.stringify(e)}`);
    }
    
    return result;
  }

  /**
   * 加载最近阅读列表（合并漫画、电子书、小说，按最后阅读时间排序）
   */
  private async loadRecentReads(): Promise<RecentReadItem[]> {
    const items: RecentReadItem[] = [];
    
    try {
      // 1. 加载最近阅读的漫画
      const dataService: DataService = DataService.getInstance();
      const readHistory = await dataService.getReadingHistory(50);
      
      // 按漫画ID去重，取最新记录
      const mangaMap = new Map<string, MangaReadInfo>(); 
      for (const record of readHistory) {
        const existing = mangaMap.get(record.comicId);
        if (!existing || existing.readTime < record.readTime) {
          const info: MangaReadInfo = { readTime: record.readTime, pageIndex: record.pageIndex };
          mangaMap.set(record.comicId, info);
        }
      }
      
      // 获取漫画详情
      const dataManager: DataManager = DataManager.getInstance();
      const mangaEntries = Array.from(mangaMap.entries());
      for (let i = 0; i < mangaEntries.length; i++) {
        const entry = mangaEntries[i];
        const comicId = entry[0];
        const info = entry[1];
        try {
          const comic = await dataManager.getComicById(comicId);
          if (comic && comic.title !== '漫匣使用手册') {
            items.push({
              id: comicId,
              title: comic.title,
              cover: comic.coverLocalPath || comic.coverUrl || '',
              type: 'manga',
              progress: 0,
              lastReadTime: info.readTime
            });
          }
        } catch (e) {
          // ignore
        }
      }
      
      // 2. 加载最近阅读的电子书
      const ebookManager: EBookDataManager = EBookDataManager.getInstance();
      const ebooks: EBook[] = await ebookManager.getEBookList();
      
      for (const ebook of ebooks) {
        if (ebook.readingProgress.lastReadTime > 0 && ebook.metadata.title !== '漫匣使用手册') {
          items.push({
            id: ebook.id,
            title: ebook.metadata.title,
            cover: ebook.metadata.coverImagePath || '',
            type: 'ebook',
            progress: Math.round(ebook.readingProgress.progress || 0),
            lastReadTime: ebook.readingProgress.lastReadTime
          });
        }
      }
      
      // 3. 加载最近阅读的小说
      const novelManager = getNovelDataManager();
      const novels: NovelBook[] = await novelManager.getRecentBooks(20);
      
      for (const novel of novels) {
        if (novel.name !== '漫匣使用手册') {
          items.push({
            id: novel.id,
            title: novel.name,
            cover: novel.coverUrl || '',
            type: 'novel',
            progress: 0, // 小说进度计算较复杂，暂用0
            lastReadTime: novel.lastReadTime || 0
          });
        }
      }
      
      // 按最后阅读时间倒序排序
      items.sort((a, b) => b.lastReadTime - a.lastReadTime);
      
      logger.debug(TAG, `加载最近阅读: 共${items.length}项`);
    } catch (e) {
      logger.error(TAG, `loadRecentReads error: ${JSON.stringify(e)}`);
    }
    
    // 只返回前6项
    return items.slice(0, RECENT_READ_LIMIT);
  }

  /**
   * 更新阅读目标数据
   */
  public async updateGoals(goals: ReadingGoalData): Promise<void> {
    if (!this.context) return;

    try {
      const pref = await preferences.getPreferences(this.context, WIDGET_DATA_STORE);
      const existingStr = (await pref.get('widgetData', '')) as string;
      
      let data: WidgetData = {
        goals: goals,
        recentReads: [],
        lastUpdateTime: Date.now()
      };

      if (existingStr) {
        const existing = SafeUtils.parseObj(existingStr) as WidgetData;
        data.recentReads = existing.recentReads || [];
      }

      data.goals = goals;
      data.lastUpdateTime = Date.now();

      await pref.put('widgetData', JSON.stringify(data));
      await pref.flush();

      await this.refreshAllForms();
    } catch (e) {
      console.error('WidgetDataSync: updateGoals error', JSON.stringify(e));
    }
  }

  /**
   * 更新最近阅读列表
   */
  public async updateRecentReads(recentReads: RecentReadItem[]): Promise<void> {
    if (!this.context) return;

    try {
      const pref = await preferences.getPreferences(this.context, WIDGET_DATA_STORE);
      const existingStr = (await pref.get('widgetData', '')) as string;
      
      let data: WidgetData = {
        goals: {
          mangaGoalMinutes: 0, mangaReadMinutes: 0,
          ebookGoalMinutes: 0, ebookReadMinutes: 0,
          novelGoalMinutes: 0, novelReadMinutes: 0
        },
        recentReads: recentReads.slice(0, RECENT_READ_LIMIT),
        lastUpdateTime: Date.now()
      };

      if (existingStr) {
        const existing = SafeUtils.parseObj(existingStr) as WidgetData;
        data.goals = existing.goals || data.goals;
      }

      await pref.put('widgetData', JSON.stringify(data));
      await pref.flush();

      await this.refreshAllForms();
    } catch (e) {
      console.error('WidgetDataSync: updateRecentReads error', JSON.stringify(e));
    }
  }

  /**
   * 完整更新卡片数据
   */
  public async updateAll(goals: ReadingGoalData, recentReads: RecentReadItem[]): Promise<void> {
    if (!this.context) return;

    try {
      const pref = await preferences.getPreferences(this.context, WIDGET_DATA_STORE);
      
      const data: WidgetData = {
        goals: goals,
        recentReads: recentReads.slice(0, RECENT_READ_LIMIT),
        lastUpdateTime: Date.now()
      };

      await pref.put('widgetData', JSON.stringify(data));
      await pref.flush();

      await this.refreshAllForms();
    } catch (e) {
      console.error('WidgetDataSync: updateAll error', JSON.stringify(e));
    }
  }

  /**
   * 刷新所有卡片
   */
  private async refreshAllForms(): Promise<void> {
    if (!this.context) return;

    try {
      const pref = await preferences.getPreferences(this.context, FORM_STORAGE);
      const formIdsStr = (await pref.get('formIds', '[]')) as string;
      const formIds: string[] = SafeUtils.parseObj(formIdsStr);
      
      const widgetPref = await preferences.getPreferences(this.context, WIDGET_DATA_STORE);
      const dataStr = (await widgetPref.get('widgetData', '')) as string;

      for (const formId of formIds) {
        try {
          const dimension = (await pref.get(`dimension_${formId}`, 1)) as number;
          const updateData = this.buildFormData(formId, dimension, dataStr);
          const formData = formBindingData.createFormBindingData(updateData);
          await formProvider.updateForm(formId, formData);
        } catch (e) {
          console.warn(`WidgetDataSync: Failed to refresh form ${formId}`);
        }
      }
    } catch (e) {
      console.error('WidgetDataSync: refreshAllForms error', JSON.stringify(e));
    }
  }

  /**
   * 构建卡片数据
   */
  private buildFormData(formId: string, dimension: number, dataStr: string): FormUpdateData {
    let goals: ReadingGoalData = {
      mangaGoalMinutes: 0, mangaReadMinutes: 0,
      ebookGoalMinutes: 0, ebookReadMinutes: 0,
      novelGoalMinutes: 0, novelReadMinutes: 0
    };
    let recentReads: RecentReadItem[] = [];

    if (dataStr) {
      try {
        const data = SafeUtils.parseObj(dataStr) as WidgetData;
        goals = data.goals || goals;
        recentReads = data.recentReads || [];
      } catch (e) {
        // ignore
      }
    }

    // 计算进度百分比
    const mangaProgress = goals.mangaGoalMinutes > 0 
      ? Math.min(100, Math.round(goals.mangaReadMinutes / goals.mangaGoalMinutes * 100)) 
      : 0;
    const ebookProgress = goals.ebookGoalMinutes > 0 
      ? Math.min(100, Math.round(goals.ebookReadMinutes / goals.ebookGoalMinutes * 100)) 
      : 0;
    const novelProgress = goals.novelGoalMinutes > 0 
      ? Math.min(100, Math.round(goals.novelReadMinutes / goals.novelGoalMinutes * 100)) 
      : 0;

    const result: FormUpdateData = {
      formId: formId,
      dimension: dimension,
      mangaGoal: goals.mangaGoalMinutes,
      mangaRead: goals.mangaReadMinutes,
      mangaProgress: mangaProgress,
      ebookGoal: goals.ebookGoalMinutes,
      ebookRead: goals.ebookReadMinutes,
      ebookProgress: ebookProgress,
      novelGoal: goals.novelGoalMinutes,
      novelRead: goals.novelReadMinutes,
      novelProgress: novelProgress,
      hasMangaGoal: goals.mangaGoalMinutes > 0,
      hasEbookGoal: goals.ebookGoalMinutes > 0,
      hasNovelGoal: goals.novelGoalMinutes > 0,
      hasAnyGoal: goals.mangaGoalMinutes > 0 || goals.ebookGoalMinutes > 0 || goals.novelGoalMinutes > 0,
      recentCount: recentReads.length,
      recent1Id: recentReads.length > 0 ? recentReads[0].id : '',
      recent1Title: recentReads.length > 0 ? recentReads[0].title : '',
      recent1Cover: recentReads.length > 0 ? recentReads[0].cover : '',
      recent1Progress: recentReads.length > 0 ? recentReads[0].progress : 0,
      recent1Type: recentReads.length > 0 ? recentReads[0].type : '',
      recent2Id: recentReads.length > 1 ? recentReads[1].id : '',
      recent2Title: recentReads.length > 1 ? recentReads[1].title : '',
      recent2Cover: recentReads.length > 1 ? recentReads[1].cover : '',
      recent2Progress: recentReads.length > 1 ? recentReads[1].progress : 0,
      recent2Type: recentReads.length > 1 ? recentReads[1].type : '',
      recent3Id: recentReads.length > 2 ? recentReads[2].id : '',
      recent3Title: recentReads.length > 2 ? recentReads[2].title : '',
      recent3Cover: recentReads.length > 2 ? recentReads[2].cover : '',
      recent3Progress: recentReads.length > 2 ? recentReads[2].progress : 0,
      recent3Type: recentReads.length > 2 ? recentReads[2].type : '',
      recent4Id: recentReads.length > 3 ? recentReads[3].id : '',
      recent4Title: recentReads.length > 3 ? recentReads[3].title : '',
      recent4Cover: recentReads.length > 3 ? recentReads[3].cover : '',
      recent4Progress: recentReads.length > 3 ? recentReads[3].progress : 0,
      recent4Type: recentReads.length > 3 ? recentReads[3].type : '',
      recent5Id: recentReads.length > 4 ? recentReads[4].id : '',
      recent5Title: recentReads.length > 4 ? recentReads[4].title : '',
      recent5Cover: recentReads.length > 4 ? recentReads[4].cover : '',
      recent5Progress: recentReads.length > 4 ? recentReads[4].progress : 0,
      recent5Type: recentReads.length > 4 ? recentReads[4].type : '',
      recent6Id: recentReads.length > 5 ? recentReads[5].id : '',
      recent6Title: recentReads.length > 5 ? recentReads[5].title : '',
      recent6Cover: recentReads.length > 5 ? recentReads[5].cover : '',
      recent6Progress: recentReads.length > 5 ? recentReads[5].progress : 0,
      recent6Type: recentReads.length > 5 ? recentReads[5].type : ''
    };

    return result;
  }
}

export const widgetDataSync = WidgetDataSync.getInstance();
