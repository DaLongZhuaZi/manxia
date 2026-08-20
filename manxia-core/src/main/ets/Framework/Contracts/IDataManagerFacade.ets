/**
 * IDataManagerFacade —— DataManager 契约（稳妥增量：仅新增文件，未接线）。
 * 说明：当前仅暴露 3 个只读方法（签名与 entry DataManager 实现逐字核验一致）。
 * 后续接线：DataManager implements 本接口，并在启动初始化后 DataManagerHolder.register(this)。
 */
import { SourceConfigResult, CachedMangaInfo, ComicInfo, ChapterInfo, PageInfo } from './DataContracts';
import { UserSettingsDatabaseRecord, ComicSourceDatabaseRecord, DatabaseRecord } from '../Database/DatabaseTypes';

export interface IDataManagerFacade {
  getSourceConfigByName(sourceName: string): Promise<SourceConfigResult | null>;
  getCachedMangasBySource(sourceId: number): Promise<CachedMangaInfo[]>;
  getAllCachedMangas(): Promise<CachedMangaInfo[]>;
  getSourceUserSetting(sourceId: number, keyName: string): Promise<UserSettingsDatabaseRecord | null>;
  getComicSourceById(sourceId: number): Promise<ComicSourceDatabaseRecord | null>;
  updateComicSourceCookies(sourceId: number, cookiesJson: string): Promise<void>;
  clearComicSourceCookies(sourceId: number): Promise<void>;
  getUserSetting(userId: string, key: string): Promise<string | null>;
  saveUserSetting(userId: string, key: string, value: string): Promise<void>;
  getAllSettings(): Promise<UserSettingsDatabaseRecord[]>;
  saveSetting(key: string, value: string, type: string): Promise<void>;
  deleteSetting(key: string): Promise<void>;
  clearAllSettings(): Promise<void>;
  getComicById(comicId: string): Promise<ComicInfo | null>;
  getChapterById(chapterId: string): Promise<ChapterInfo | null>;
  getChaptersByMangaId(mangaId: string): Promise<ChapterInfo[]>;
  getPagesByChapterId(chapterId: string): Promise<PageInfo[]>;
  getAllComicSources(): Promise<DatabaseRecord[]>;
}

export class DataManagerHolder {
  private static impl: IDataManagerFacade | null = null;

  static register(facade: IDataManagerFacade): void {
    DataManagerHolder.impl = facade;
  }

  static get(): IDataManagerFacade {
    if (!DataManagerHolder.impl) {
      throw new Error('DataManager not registered');
    }
    return DataManagerHolder.impl;
  }
}
