/**
 * 标签页配置数据模型
 */

/**
 * 标签页类型
 */
export enum TabType {
  POPULAR = 'popular',
  LATEST = 'latest',
  FILTER = 'filter',
  FAVORITES = 'favorites',
  HISTORY = 'history',
  CUSTOM = 'custom'  // 自定义筛选标签
}

/**
 * 筛选参数（用于FILTER和CUSTOM类型）
 */
export interface FilterParams {
  ordering?: string;
  region?: string;
  theme?: string;
}

/**
 * 标签页配置
 */
export interface TabConfig {
  /** 唯一标识 */
  id: string;
  /** 标签类型 */
  type: TabType;
  /** 显示名称 */
  name: string;
  /** 是否启用 */
  enabled: boolean;
  /** 排序顺序 */
  order: number;
  /** 是否需要登录 */
  requiresLogin?: boolean;
  /** 筛选参数（仅用于FILTER和CUSTOM类型） */
  filterParams?: FilterParams;
}

/**
 * 图源标签页配置
 */
export interface SourceTabsConfig {
  /** 图源ID */
  sourceId: number;
  /** 标签列表 */
  tabs: TabConfig[];
  /** 配置版本 */
  version?: number;
}

/**
 * 获取默认标签配置
 */
export function getDefaultTabsConfig(sourceId: number): SourceTabsConfig {
  return {
    sourceId: sourceId,
    tabs: [
      {
        id: 'popular',
        type: TabType.POPULAR,
        name: '热门',
        enabled: true,
        order: 0,
        requiresLogin: false
      },
      {
        id: 'latest',
        type: TabType.LATEST,
        name: '最新',
        enabled: true,
        order: 1,
        requiresLogin: false
      },
      {
        id: 'filter',
        type: TabType.FILTER,
        name: '筛选',
        enabled: true,
        order: 2,
        requiresLogin: false,
        filterParams: {
          ordering: '-datetime_updated',
          region: 'all',
          theme: 'all'
        }
      }
    ],
    version: 1
  };
}

/**
 * 可选标签类型信息
 */
export interface AvailableTabTypeInfo {
  type: TabType;
  name: string;
  requiresLogin: boolean;
}

/**
 * 获取可选标签列表（用于标签管理）
 */
export function getAvailableTabTypes(): AvailableTabTypeInfo[] {
  const result: AvailableTabTypeInfo[] = [
    { type: TabType.POPULAR, name: '热门', requiresLogin: false },
    { type: TabType.LATEST, name: '最新', requiresLogin: false },
    { type: TabType.FILTER, name: '筛选', requiresLogin: false },
    { type: TabType.FAVORITES, name: '收藏', requiresLogin: true },
    { type: TabType.HISTORY, name: '浏览记录', requiresLogin: true }
  ];
  return result;
}

/**
 * 检查标签是否为必选标签
 */
export function isRequiredTab(type: TabType): boolean {
  return type === TabType.POPULAR || type === TabType.LATEST || type === TabType.FILTER;
}

/**
 * 过滤掉需要登录但用户未登录的标签
 */
export function filterTabsByLoginStatus(tabs: TabConfig[], isLoggedIn: boolean): TabConfig[] {
  if (isLoggedIn) {
    return tabs;
  }
  return tabs.filter(tab => !tab.requiresLogin);
}

/**
 * 按order字段排序标签
 */
export function sortTabs(tabs: TabConfig[]): TabConfig[] {
  return tabs.sort((a, b) => a.order - b.order);
}
