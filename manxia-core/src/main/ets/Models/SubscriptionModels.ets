/**
 * 统一内容跟踪模型定义
 * 第一阶段先支持作品级跟踪，并为后续书架级规则保留结构。
 */

export enum SubscriptionTargetType {
  ITEM = 'item',
  SHELF = 'shelf',
  DYNAMIC_SHELF = 'dynamic_shelf',
  PROVIDER_LIBRARY = 'provider_library'
}

export enum SubscriptionContentType {
  MANGA = 'manga',
  NOVEL = 'novel',
  EBOOK = 'ebook',
  MIXED = 'mixed'
}

export enum SubscriptionProviderType {
  NONE = 'none',
  WEBVIEW = 'webview',
  SUWAYOMI = 'suwayomi',
  KOMGA = 'komga',
  LEGADO = 'legado'
}

export enum SubscriptionConditionType {
  MATCH_MODE = 'match_mode',
  ONLY_IF_FAVORITE = 'only_if_favorite',
  MIN_NEW_ITEMS = 'min_new_items',
  EXCLUDE_NSFW = 'exclude_nsfw',
  TITLE_KEYWORD = 'title_keyword',
  TAG_KEYWORD = 'tag_keyword',
  SOURCE_KEYWORD = 'source_keyword'
}

export enum SubscriptionConditionMatchMode {
  ALL = 'all',
  ANY = 'any'
}

export enum SubscriptionActionType {
  CHECK_UPDATE = 'check_update',
  NOTIFY = 'notify',
  AUTO_DOWNLOAD_NEW = 'auto_download_new'
}

export enum SubscriptionExecutionStatus {
  SUCCESS = 'success',
  NO_UPDATE = 'no_update',
  SKIPPED = 'skipped',
  FAILED = 'failed',
  UNSUPPORTED = 'unsupported'
}

export interface SubscriptionCondition {
  type: SubscriptionConditionType;
  enabled: boolean;
  numericValue: number;
  booleanValue: boolean;
  textValue: string;
}

export interface SubscriptionAction {
  type: SubscriptionActionType;
  enabled: boolean;
  limitCount: number;
  notifyTitle: string;
  notifyText: string;
}

export interface SubscriptionRule {
  id: string;
  name: string;
  enabled: boolean;
  targetType: SubscriptionTargetType;
  contentType: SubscriptionContentType;
  targetId: string;
  targetTitle: string;
  sourceId: string;
  sourceName: string;
  providerType: SubscriptionProviderType;
  checkIntervalMin: number;
  conditions: SubscriptionCondition[];
  actions: SubscriptionAction[];
  lastCheckTime: number;
  lastSuccessTime: number;
  lastError: string;
  lastTriggeredScene: string;
  createTime: number;
  updateTime: number;
}

export interface SubscriptionCheckpoint {
  ruleId: string;
  targetId: string;
  contentId: string;
  contentType: SubscriptionContentType;
  remoteFingerprint: string;
  remoteCount: number;
  localCount: number;
  latestItemTitle: string;
  lastSeenTime: number;
  updateTime: number;
}

export interface SubscriptionExecutionRecord {
  id: string;
  ruleId: string;
  status: SubscriptionExecutionStatus;
  triggerScene: string;
  targetId: string;
  targetTitle: string;
  contentType: SubscriptionContentType;
  checkedAt: number;
  localCount: number;
  remoteCount: number;
  deltaCount: number;
  downloadedCount: number;
  message: string;
  actionSummary: string;
  createTime: number;
}

export interface SubscriptionRuleRunResult {
  rule: SubscriptionRule;
  status: SubscriptionExecutionStatus;
  hasUpdate: boolean;
  localCount: number;
  remoteCount: number;
  deltaCount: number;
  downloadedCount: number;
  message: string;
  actionSummary: string;
  latestItemTitle: string;
  checkpoint: SubscriptionCheckpoint | null;
  checkpoints?: SubscriptionCheckpoint[];
  processedTargetCount?: number;
  updatedTargetCount?: number;
  skippedTargetCount?: number;
  failedTargetCount?: number;
  unsupportedTargetCount?: number;
}

export interface SubscriptionTargetPreviewCounter {
  key: string;
  count: number;
}

export interface SubscriptionTargetPreviewCandidate {
  itemId: string;
  title: string;
  contentType: SubscriptionContentType;
  providerType: SubscriptionProviderType;
  sourceId: string;
  sourceName: string;
  isFavorite: boolean;
  supported: boolean;
  unsupportedReason: string;
  conditionMatched: boolean;
  conditionReason: string;
  localCount: number;
  latestItemTitle: string;
}

export interface SubscriptionTargetPreview {
  targetType: SubscriptionTargetType;
  targetId: string;
  targetTitle: string;
  contentType: SubscriptionContentType;
  totalCandidateCount: number;
  supportedCandidateCount: number;
  unsupportedCandidateCount: number;
  matchedCandidateCount: number;
  filteredCandidateCount: number;
  contentTypeBreakdown: SubscriptionTargetPreviewCounter[];
  providerTypeBreakdown: SubscriptionTargetPreviewCounter[];
  candidates: SubscriptionTargetPreviewCandidate[];
}

export interface SubscriptionRuleCreateOptions {
  ruleName: string;
  checkIntervalMin: number;
  enableNotify: boolean;
  autoDownloadCount: number;
  conditionMatchMode: SubscriptionConditionMatchMode;
  requireFavorite: boolean;
  minNewItems: number;
  excludeNSFW: boolean;
  titleKeyword: string;
  tagKeyword: string;
  sourceKeyword: string;
}

export const DEFAULT_SUBSCRIPTION_CREATE_OPTIONS: SubscriptionRuleCreateOptions = {
  ruleName: '',
  checkIntervalMin: 180,
  enableNotify: true,
  autoDownloadCount: 0,
  conditionMatchMode: SubscriptionConditionMatchMode.ALL,
  requireFavorite: false,
  minNewItems: 1,
  excludeNSFW: false,
  titleKeyword: '',
  tagKeyword: '',
  sourceKeyword: ''
};

export function createCheckAction(): SubscriptionAction {
  return {
    type: SubscriptionActionType.CHECK_UPDATE,
    enabled: true,
    limitCount: 0,
    notifyTitle: '',
    notifyText: ''
  };
}

export function createNotifyAction(): SubscriptionAction {
  return {
    type: SubscriptionActionType.NOTIFY,
    enabled: true,
    limitCount: 0,
    notifyTitle: '',
    notifyText: ''
  };
}

export function createAutoDownloadAction(limitCount: number): SubscriptionAction {
  return {
    type: SubscriptionActionType.AUTO_DOWNLOAD_NEW,
    enabled: limitCount > 0,
    limitCount: limitCount > 0 ? limitCount : 0,
    notifyTitle: '',
    notifyText: ''
  };
}

export function createOnlyFavoriteCondition(enabled: boolean): SubscriptionCondition {
  return {
    type: SubscriptionConditionType.ONLY_IF_FAVORITE,
    enabled,
    numericValue: 0,
    booleanValue: enabled,
    textValue: ''
  };
}

export function createConditionMatchModeCondition(matchMode: SubscriptionConditionMatchMode): SubscriptionCondition {
  return {
    type: SubscriptionConditionType.MATCH_MODE,
    enabled: true,
    numericValue: 0,
    booleanValue: false,
    textValue: matchMode === SubscriptionConditionMatchMode.ANY
      ? SubscriptionConditionMatchMode.ANY
      : SubscriptionConditionMatchMode.ALL
  };
}

export function createMinNewItemsCondition(minNewItems: number): SubscriptionCondition {
  const normalizedMin = minNewItems > 0 ? Math.floor(minNewItems) : 1;
  return {
    type: SubscriptionConditionType.MIN_NEW_ITEMS,
    enabled: true,
    numericValue: normalizedMin,
    booleanValue: false,
    textValue: ''
  };
}

export function createExcludeNsfwCondition(enabled: boolean): SubscriptionCondition {
  return {
    type: SubscriptionConditionType.EXCLUDE_NSFW,
    enabled: enabled,
    numericValue: 0,
    booleanValue: enabled,
    textValue: ''
  };
}

export function createTitleKeywordCondition(keyword: string): SubscriptionCondition {
  return {
    type: SubscriptionConditionType.TITLE_KEYWORD,
    enabled: keyword.trim().length > 0,
    numericValue: 0,
    booleanValue: false,
    textValue: keyword.trim()
  };
}

export function createTagKeywordCondition(keyword: string): SubscriptionCondition {
  return {
    type: SubscriptionConditionType.TAG_KEYWORD,
    enabled: keyword.trim().length > 0,
    numericValue: 0,
    booleanValue: false,
    textValue: keyword.trim()
  };
}

export function createSourceKeywordCondition(keyword: string): SubscriptionCondition {
  return {
    type: SubscriptionConditionType.SOURCE_KEYWORD,
    enabled: keyword.trim().length > 0,
    numericValue: 0,
    booleanValue: false,
    textValue: keyword.trim()
  };
}
