/** 搜索历史契约（R3 接口下沉）。entry SearchHistoryManager 实现（构造需 DataManager）；SearchPage 持有实例。 */

export interface ISearchHistoryManager {
  load(userId: string): Promise<string[]>;
  save(userId: string, history: string[]): Promise<void>;
  add(userId: string, keyword: string, currentHistory: string[]): Promise<string[]>;
  clear(userId: string): Promise<void>;
}
