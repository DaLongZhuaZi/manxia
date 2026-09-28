/**
 * 后台任务点击后的导航目标。
 */
export interface TaskNavigationTarget {
  routeName: string;
  sourceId?: number;
  sourceName?: string;
  sourcePkg?: string;
  initialUrl?: string;
  autoCheckTaskId?: string;
  openAutoCheckReport?: boolean;
}
