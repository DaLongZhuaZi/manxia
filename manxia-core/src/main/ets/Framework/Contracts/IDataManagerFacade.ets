/**
 * IDataManagerFacade —— DataManager 契约（稳妥增量：仅新增文件，未接线）。
 * 说明：当前仅暴露 3 个只读方法（签名与 entry DataManager 实现逐字核验一致）。
 * 后续接线：DataManager implements 本接口，并在启动初始化后 DataManagerHolder.register(this)。
 */
import { SourceConfigResult, CachedMangaInfo } from './DataContracts';
import { UserSettingsDatabaseRecord, ComicSourceDatabaseRecord } from '../Database/DatabaseTypes';

export interface IDataManagerFacade {
  getSourceConfigByName(sourceName: string): Promise<SourceConfigResult | null>;
  getCachedMangasBySource(sourceId: number): Promise<CachedMangaInfo[]>;
  getAllCachedMangas(): Promise<CachedMangaInfo[]>;
  getSourceUserSetting(sourceId: number, keyName: string): Promise<UserSettingsDatabaseRecord | null>;
  getComicSourceById(sourceId: number): Promise<ComicSourceDatabaseRecord | null>;
  updateComicSourceCookies(sourceId: number, cookiesJson: string): Promise<void>;
  clearComicSourceCookies(sourceId: number): Promise<void>;
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
