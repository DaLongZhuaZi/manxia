export class GlobalSearchCachedComicInfo {
  public id: string = '';
  public title: string = '';
  public author: string = '';
  public coverUrl: string = '';
  public description: string = '';
  public url: string = '';
  public status: string = '';
}

export class GlobalSearchCacheData {
  public keyword: string = '';
  public results: GlobalSearchCachedComicInfo[] = new Array<GlobalSearchCachedComicInfo>();
  public timestamp: number = 0;
  public globalSearchSessionId: string = '';
}

export function buildGlobalSearchCacheKey(sourceId: number, keyword: string): string {
  const normalizedKeyword: string = keyword.trim().toLowerCase();
  let hash: number = 0;
  for (let i = 0; i < normalizedKeyword.length; i++) {
    hash = ((hash << 5) - hash) + normalizedKeyword.charCodeAt(i);
    hash = hash & hash;
  }
  return `global_search_cache_${sourceId}_${Math.abs(hash).toString(36)}`;
}

export function buildLegacyGlobalSearchCacheKey(sourceId: number): string {
  return `global_search_cache_${sourceId}`;
}

export function createGlobalSearchCacheData(
  keyword: string,
  results: GlobalSearchCachedComicInfo[],
  globalSearchSessionId: string
): GlobalSearchCacheData {
  const data: GlobalSearchCacheData = new GlobalSearchCacheData();
  data.keyword = keyword;
  data.results = results;
  data.timestamp = Date.now();
  data.globalSearchSessionId = globalSearchSessionId;
  return data;
}
