/**
 * 加载/刷新状态管理（@Observed）
 * 合并散落的 loading/refreshing 布尔变量
 */
@Observed
export class LoadingState {
  mangaList: boolean = false;
  ebookList: boolean = false;
  novelList: boolean = false;
  recentReading: boolean = false;
  sourceList: boolean = false;
  refreshing: boolean = false;
  refreshingHome: boolean = false;
  refreshingDiscover: boolean = false;
  refreshingSourceList: boolean = false;
  refreshingRemoteLibrary: boolean = false;
}
