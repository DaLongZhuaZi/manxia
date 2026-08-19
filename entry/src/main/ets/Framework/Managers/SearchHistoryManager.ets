// 文件路径: entry/src/main/ets/Framework/Managers/SearchHistoryManager.ets
// 职责: 提供搜索历史在应用内数据库的读取、保存、添加与清空方法，避免使用系统级存储

import { DataManager } from '../Data/DataManager';
import { logger } from 'manxia_core/src/main/ets/Utils/Logger';

const TAG: string = 'SearchHistoryManager';

// 明确的管理器接口，确保类型安全
export interface ISearchHistoryManager {
  load(userId: string): Promise<string[]>;
  save(userId: string, history: string[]): Promise<void>;
  add(userId: string, keyword: string, currentHistory: string[]): Promise<string[]>;
  clear(userId: string): Promise<void>;
}

// 具体实现，使用应用内数据库的 user_settings 表进行持久化
export class SearchHistoryManager implements ISearchHistoryManager {
  private dataManager: DataManager;

  constructor(dataManager: DataManager) {
    this.dataManager = dataManager;
  }

  public async load(userId: string): Promise<string[]> {
    try {
      const value: string | null = await this.dataManager.getUserSetting(userId, 'search_history');
      if (value && value.length > 0) {
        const parts: string[] = value.split('|');
        return parts;
      }
      return [];
    } catch (error) {
      logger.warn(TAG, `加载搜索历史失败: ${String(error)}`);
      return [];
    }
  }

  public async save(userId: string, history: string[]): Promise<void> {
    try {
      const value: string = history.join('|');
      await this.dataManager.saveUserSetting(userId, 'search_history', value);
    } catch (error) {
      logger.warn(TAG, `保存搜索历史失败: ${String(error)}`);
    }
  }

  public async add(userId: string, keyword: string, currentHistory: string[]): Promise<string[]> {
    const q: string = keyword.trim();
    if (q.length === 0) {
      return currentHistory;
    }
    const existingIndex: number = currentHistory.indexOf(q);
    let next: string[];
    if (existingIndex >= 0) {
      // 移到首位
      next = [q].concat(currentHistory.filter(item => item !== q));
    } else {
      // 新增到首位，限制最多50条
      const merged: string[] = [q].concat(currentHistory);
      next = merged.length > 50 ? merged.slice(0, 50) : merged;
    }
    await this.save(userId, next);
    return next;
  }

  public async clear(userId: string): Promise<void> {
    try {
      await this.dataManager.saveUserSetting(userId, 'search_history', '');
    } catch (error) {
      logger.warn(TAG, `清空搜索历史失败: ${String(error)}`);
    }
  }
}