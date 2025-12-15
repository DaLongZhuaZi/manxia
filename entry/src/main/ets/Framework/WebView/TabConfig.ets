/**
 * 标签页配置数据模型
 * 支持自定义标签页、筛选结构、标题和提示词
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
  LEADERBOARD = 'leaderboard',  // 排行榜
  CUSTOM = 'custom',  // 自定义工作流标签
  SEARCH = 'search'  // 搜索结果标签
}

/**
 * 筛选选项配置
 */
export interface FilterOption {
  /** 选项值 */
  value: string;
  /** 显示标签 */
  label: string;
}

/**
 * 筛选组配置（单个筛选维度）
 */
export interface FilterGroup {
  /** 筛选组ID（对应变量名，如 sort, category, region） */
  id: string;
  /** 筛选组标题 */
  title: string;
  /** 提示文字 */
  placeholder?: string;
  /** 选项列表 */
  options: FilterOption[];
  /** 默认值 */
  defaultValue?: string;
  /** 是否必选 */
  required?: boolean;
  /** 排序顺序 */
  order?: number;
}

/**
 * 筛选配置（完整的筛选结构）
 */
export interface FilterConfig {
  /** 筛选组列表 */
  groups: FilterGroup[];
  /** 筛选页标题 */
  title?: string;
  /** 筛选页描述 */
  description?: string;
}

/**
 * 筛选参数（用于FILTER和CUSTOM类型）
 */
export interface FilterParams {
  ordering?: string;
  region?: string;
  theme?: string;
  sort?: string;
  category?: string;
  rank?: string;
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
  /** 筛选配置（完整的筛选结构定义） */
  filterConfig?: FilterConfig;
  /** 工作流名称（用于CUSTOM类型，指定要执行的工作流） */
  workflowName?: string;
  /** 图标名称（可选，用于显示标签图标） */
  icon?: string;
  /** 描述文字 */
  description?: string;
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

/**
 * 从图源JSON配置解析标签页配置
 * @param sourceId 图源ID
 * @param config 图源配置对象
 * @returns 标签页配置
 */
export function parseTabsFromSourceConfig(sourceId: number, config: Record<string, Object>): SourceTabsConfig {
  const result: SourceTabsConfig = {
    sourceId: sourceId,
    tabs: [],
    version: 1
  };

  // 检查是否有 tabs 配置
  const tabsConfig = config['tabs'] as Record<string, Object>[] | undefined;
  
  if (tabsConfig && Array.isArray(tabsConfig)) {
    // 从配置中解析标签
    let order = 0;
    for (let i = 0; i < tabsConfig.length; i++) {
      const tabDef: Record<string, Object> = tabsConfig[i];
      const tab = parseTabDefinition(tabDef, order);
      if (tab) {
        result.tabs.push(tab);
        order++;
      }
    }
  }
  
  // 如果没有配置标签，根据 workflows 自动生成
  if (result.tabs.length === 0) {
    result.tabs = generateTabsFromWorkflows(config);
  }
  
  return result;
}

/**
 * 解析单个标签定义
 */
function parseTabDefinition(tabDef: Record<string, Object>, defaultOrder: number): TabConfig | null {
  if (!tabDef || typeof tabDef !== 'object') {
    return null;
  }

  const id = String(tabDef['id'] || '');
  const typeStr = String(tabDef['type'] || 'custom');
  const name = String(tabDef['name'] || id);
  
  if (!id) {
    return null;
  }

  // 解析标签类型
  let type: TabType;
  switch (typeStr.toLowerCase()) {
    case 'popular': type = TabType.POPULAR; break;
    case 'latest': type = TabType.LATEST; break;
    case 'filter': type = TabType.FILTER; break;
    case 'favorites': type = TabType.FAVORITES; break;
    case 'history': type = TabType.HISTORY; break;
    case 'leaderboard': type = TabType.LEADERBOARD; break;
    default: type = TabType.CUSTOM; break;
  }

  const tab: TabConfig = {
    id: id,
    type: type,
    name: name,
    enabled: tabDef['enabled'] !== false,
    order: typeof tabDef['order'] === 'number' ? tabDef['order'] as number : defaultOrder,
    requiresLogin: tabDef['requiresLogin'] === true,
    workflowName: tabDef['workflowName'] as string | undefined,
    icon: tabDef['icon'] as string | undefined,
    description: tabDef['description'] as string | undefined
  };

  // 解析筛选参数
  if (tabDef['filterParams']) {
    tab.filterParams = tabDef['filterParams'] as FilterParams;
  }

  // 解析筛选配置
  if (tabDef['filterConfig']) {
    tab.filterConfig = parseFilterConfig(tabDef['filterConfig'] as Record<string, Object>);
  }

  return tab;
}

/**
 * 解析筛选配置
 */
function parseFilterConfig(configDef: Record<string, Object>): FilterConfig | undefined {
  if (!configDef || typeof configDef !== 'object') {
    return undefined;
  }

  const groups: FilterGroup[] = [];
  const groupsDef = configDef['groups'] as Record<string, Object>[] | undefined;
  
  if (groupsDef && Array.isArray(groupsDef)) {
    let order = 0;
    for (let i = 0; i < groupsDef.length; i++) {
      const groupDef: Record<string, Object> = groupsDef[i];
      const group = parseFilterGroup(groupDef, order);
      if (group) {
        groups.push(group);
        order++;
      }
    }
  }

  if (groups.length === 0) {
    return undefined;
  }

  return {
    groups: groups,
    title: configDef['title'] as string | undefined,
    description: configDef['description'] as string | undefined
  };
}

/**
 * 解析筛选组
 */
function parseFilterGroup(groupDef: Record<string, Object>, defaultOrder: number): FilterGroup | null {
  if (!groupDef || typeof groupDef !== 'object') {
    return null;
  }

  const id = String(groupDef['id'] || '');
  const title = String(groupDef['title'] || groupDef['name'] || id);
  
  if (!id) {
    return null;
  }

  const options: FilterOption[] = [];
  const optionsDef = groupDef['options'] as Record<string, Object>[] | undefined;
  
  if (optionsDef && Array.isArray(optionsDef)) {
    for (let i = 0; i < optionsDef.length; i++) {
      const optDef: Record<string, Object> = optionsDef[i];
      if (optDef && typeof optDef === 'object') {
        options.push({
          value: String(optDef['value'] || ''),
          label: String(optDef['label'] || optDef['value'] || '')
        });
      }
    }
  }

  return {
    id: id,
    title: title,
    placeholder: groupDef['placeholder'] as string | undefined,
    options: options,
    defaultValue: groupDef['defaultValue'] as string | undefined || groupDef['default'] as string | undefined,
    required: groupDef['required'] === true,
    order: typeof groupDef['order'] === 'number' ? groupDef['order'] as number : defaultOrder
  };
}

/**
 * 根据 workflows 自动生成标签配置
 */
function generateTabsFromWorkflows(config: Record<string, Object>): TabConfig[] {
  const tabs: TabConfig[] = [];
  const workflows = config['workflows'] as Record<string, Object> | undefined;
  
  if (!workflows) {
    return getDefaultTabsConfig(0).tabs;
  }

  let order = 0;

  // 检查 popular 工作流
  if (workflows['popular']) {
    tabs.push({
      id: 'popular',
      type: TabType.POPULAR,
      name: '热门',
      enabled: true,
      order: order++,
      requiresLogin: false
    });
  }

  // 检查 latest 工作流
  if (workflows['latest']) {
    tabs.push({
      id: 'latest',
      type: TabType.LATEST,
      name: '最新',
      enabled: true,
      order: order++,
      requiresLogin: false
    });
  }

  // 检查 filter 工作流
  if (workflows['filter']) {
    tabs.push({
      id: 'filter',
      type: TabType.FILTER,
      name: '筛选',
      enabled: true,
      order: order++,
      requiresLogin: false
    });
  }

  // 检查 favorites 工作流
  if (workflows['favorites']) {
    tabs.push({
      id: 'favorites',
      type: TabType.FAVORITES,
      name: '收藏',
      enabled: true,
      order: order++,
      requiresLogin: true
    });
  }

  // 检查 getLeaderboard 工作流
  if (workflows['getLeaderboard']) {
    tabs.push({
      id: 'leaderboard',
      type: TabType.LEADERBOARD,
      name: '排行榜',
      enabled: true,
      order: order++,
      requiresLogin: false
    });
  }

  // 如果没有找到任何工作流，返回默认配置
  if (tabs.length === 0) {
    return getDefaultTabsConfig(0).tabs;
  }

  return tabs;
}
