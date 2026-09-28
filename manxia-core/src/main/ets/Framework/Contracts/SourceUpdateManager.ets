/** 图源更新契约（R3 批4 接口下沉）。entry SourceUpdateManager 本地导入并再导出。 */

export interface SourceIndexItem {
  name: string;
  version: string;
  file: string;
  description?: string;
  author?: string;
  updateTime?: string;
}

export interface SourceRepoIndex {
  version: string;
  updateTime: string;
  sources: SourceIndexItem[];
}

export interface UpdateCheckResult {
  hasUpdate: boolean;
  remoteIndex: SourceRepoIndex | null;
  localIndex: SourceRepoIndex | null;
  updatedSources: SourceIndexItem[];
  newSources: SourceIndexItem[];
}
