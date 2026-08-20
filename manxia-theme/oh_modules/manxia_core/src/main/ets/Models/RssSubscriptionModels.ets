/**
 * RSS subscription models.
 * Independent from novel source models.
 */

export enum RssFeedFormat {
  RSS = 'rss',
  ATOM = 'atom',
  UNKNOWN = 'unknown'
}

export interface RssSubscriptionSource {
  id: string;
  name: string;
  url: string;
  sourceComment?: string;
  enabled: boolean;
  autoUpdate: boolean;
  updateIntervalMin: number;
  variableComment?: string;
  jsLib?: string;
  enabledCookieJar: boolean;
  concurrentRate?: string;
  header?: string;
  loginUrl?: string;
  loginUi?: string;
  loginCheckJs?: string;
  coverDecodeJs?: string;
  sortUrl?: string;
  singleUrl: boolean;
  articleStyle: number;
  ruleArticles?: string;
  ruleNextPage?: string;
  ruleTitle?: string;
  rulePubDate?: string;
  ruleDescription?: string;
  ruleImage?: string;
  ruleLink?: string;
  ruleContent?: string;
  contentWhitelist?: string;
  contentBlacklist?: string;
  shouldOverrideUrlLoading?: string;
  style?: string;
  enableJs: boolean;
  loadWithBaseUrl: boolean;
  injectJs?: string;
  lastUpdateTime: number;
  customOrder: number;
  etag?: string;
  lastModified?: string;
  lastCheckTime: number;
  lastSuccessTime: number;
  lastError?: string;
  iconUrl?: string;
  groupName?: string;
  createTime: number;
  updateTime: number;
}

export interface RssFeedItem {
  id: string;
  sourceId: string;
  sourceName: string;
  title: string;
  link: string;
  description: string;
  content?: string;
  author?: string;
  category?: string;
  guid?: string;
  pubDate: number;
  isRead: boolean;
  isStarred: boolean;
  createTime: number;
  updateTime: number;
}

export interface RssFetchResult {
  success: boolean;
  sourceId: string;
  sourceName: string;
  format: RssFeedFormat;
  itemCount: number;
  insertedCount: number;
  statusCode: number;
  error?: string;
  durationMs: number;
}

export interface RssRefreshProgress {
  current: number;
  total: number;
  sourceName: string;
  success: boolean;
  itemCount?: number;
  insertedCount?: number;
  durationMs?: number;
  error?: string;
}
