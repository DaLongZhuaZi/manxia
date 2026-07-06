import { SourceDiagnosticEvent } from '../SourceEditor/SourceDiagnosticTypes';

/**
 * 漫画图源引擎类型定义
 * 定义JSON驱动的WebView自动化系统的所有类型接口
 */

// ==================== 基础类型定义 ====================

/**
 * 图源元数据
 */
export interface MangaSourceMetadata {
  /** 图源唯一包名 */
  id?: string;
  /** 图源名称 */
  name: string;
  /** 版本号 */
  version: string;
  /** 作者 */
  author: string;
  /** 描述 */
  description: string;
  /** 基础URL */
  baseUrl: string;
  /** 语言 */
  language: string;
  /** 图源类型 (manga/ebook/novel) */
  type?: string;
  /** 创建时间 */
  created: string;
  /** 更新时间 */
  updated: string;
}

/**
 * 图源设置
 */
export interface MangaSourceSettings {
  /** 自定义User-Agent */
  userAgent?: string;
  /** 超时时间(毫秒) */
  timeout: number;
  /** 重试次数 */
  retryCount: number;
  /** 启用JavaScript */
  enableJavaScript: boolean;
  /** 启用图片加载 */
  enableImages: boolean;
  /** 启用Cookie */
  enableCookies: boolean;
  /** 绕过Cloudflare */
  bypassCloudflare: boolean;
}

/**
 * 搜索类型定义（用于图源JSON配置）
 */
export interface SearchTypeOption {
  /** 搜索类型ID，对应工作流名称 */
  id: string;
  /** 显示名称 */
  label: string;
  /** 占位符提示文本 */
  placeholder?: string;
  /** 是否为默认选项 */
  isDefault?: boolean;
  /** 直达URL模板，使用 {{query}} 作为占位符，如 "https://pixiv.net/artworks/{{query}}" */
  urlTemplate?: string;
  /** 直达类型：'detail'跳转详情页, 'webview'在WebView中打开 */
  directType?: 'detail' | 'webview';
}

/**
 * 搜索配置
 */
export interface SearchConfig {
  /** 支持的搜索类型列表 */
  types?: SearchTypeOption[];
}

/**
 * 直达搜索结果类型
 */
export type DirectSearchResultType = 'detail' | 'list' | 'redirect';

/**
 * 直达搜索结果
 */
export interface DirectSearchResult {
  /** 结果类型：detail=单个作品详情, list=作品列表, redirect=重定向URL */
  type: DirectSearchResultType;
  /** 单个作品详情（当type=detail时） */
  manga?: MangaInfo;
  /** 作品列表（当type=list时） */
  mangas?: MangaInfo[];
  /** 重定向URL（当type=redirect时） */
  redirectUrl?: string;
  /** 是否有更多结果 */
  hasNext?: boolean;
  /** 总数 */
  total?: number;
}

// ==================== 选择器系统 ====================

/**
 * 选择器类型
 */
export enum SelectorType {
  CSS = 'css',
  XPATH = 'xpath',
  TEXT = 'text',
  ATTRIBUTE = 'attribute',
  REGEX = 'regex',
  COMPOSITE = 'composite'
}

/**
 * 文本匹配类型
 */
export enum TextMatchType {
  EXACT = 'exact',
  CONTAINS = 'contains',
  STARTS_WITH = 'starts_with',
  ENDS_WITH = 'ends_with',
  REGEX = 'regex'
}

/**
 * CSS选择器
 */
export interface CSSSelector {
  type: SelectorType.CSS;
  value: string;
  textMatch?: TextMatchType;
  attribute?: string;
}

/**
 * XPath选择器
 */
export interface XPathSelector {
  type: SelectorType.XPATH;
  value: string;
  textMatch?: TextMatchType;
  attribute?: string;
}

/**
 * 文本匹配选择器
 */
export interface TextSelector {
  type: SelectorType.TEXT;
  value: string;
  exact: boolean;
  textMatch?: TextMatchType;
}

/**
 * 属性匹配选择器
 */
export interface AttributeSelector {
  type: SelectorType.ATTRIBUTE;
  attribute: string;
  value: string;
  textMatch?: TextMatchType;
}

/**
 * 正则表达式选择器
 */
export interface RegexSelector {
  type: SelectorType.REGEX;
  /** 正则表达式模式 */
  pattern: string;
  /** 正则标志 */
  flags?: string;
  /** 捕获组索引 */
  group?: number;
}

/**
 * 组合选择器
 */
export interface CompositeSelector {
  type: SelectorType.COMPOSITE;
  /** 组合操作符 */
  operator: 'AND' | 'OR' | 'NOT';
  /** 子选择器列表 */
  selectors: Selector[];
}

/**
 * 选择器联合类型
 */
export type Selector = CSSSelector | XPathSelector | TextSelector | AttributeSelector | 
                       RegexSelector | CompositeSelector;

// ==================== 操作类型定义 ====================

/**
 * 操作类型枚举
 */
export enum ActionType {
  NAVIGATE = 'navigate',
  WAIT = 'wait',
  CLICK = 'click',
  INPUT = 'input',
  EXTRACT = 'extract',
  CONDITION = 'condition',
  SCRIPT = 'script',
  CLOUDFLARE_BYPASS = 'cloudflareBypass',
  CAPTCHA = 'captcha',
  IP_BLOCK = 'ipBlock',
  // 新增操作类型
  LOOP = 'loop',
  PARALLEL = 'parallel',
  SCROLL = 'scroll',
  HOVER = 'hover',
  SELECT = 'select',
  VARIABLE_SET = 'variableSet',
  VARIABLE_GET = 'variableGet',
  COOKIE_SET = 'cookieSet',
  // API相关操作类型
  API_REQUEST = 'api',
  HTTP_REQUEST = 'http',
  COOKIE_GET = 'cookieGet',
  STORAGE_SET = 'storageSet',
  STORAGE_GET = 'storageGet',
  SCREENSHOT = 'screenshot'
}

/**
 * 等待条件类型
 */
export enum WaitCondition {
  ELEMENT = 'element',
  TIME = 'time',
  NETWORK_IDLE = 'networkidle',
  LOAD = 'load'
}

/**
 * 错误恢复策略
 */
export interface ErrorRecovery {
  /** 最大重试次数 */
  maxRetries: number;
  /** 重试延迟(毫秒) */
  retryDelay: number;
  /** 降级操作 */
  fallbackActions?: Action[];
  /** 出错时跳过 */
  skipOnError?: boolean;
}

/**
 * 基础操作接口
 */
export interface BaseAction {
  type: ActionType;
  /** 操作描述 */
  description?: string;
  /** 是否可选操作 */
  optional?: boolean;
  /** 操作后等待时间 */
  waitAfter?: number;
  /** 错误恢复策略 */
  errorRecovery?: ErrorRecovery;
}

/**
 * 导航操作
 */
export interface NavigateAction extends BaseAction {
  type: ActionType.NAVIGATE;
  url: string;
  waitFor?: WaitCondition;
  timeout?: number;
  waitAfterLoad?: number;
}

/**
 * 等待操作
 */
export interface WaitAction extends BaseAction {
  type: ActionType.WAIT;
  condition: WaitCondition;
  selector?: string;
  duration?: number;
  timeout?: number;
}

/**
 * 点击操作
 */
export interface ClickAction extends BaseAction {
  type: ActionType.CLICK;
  selector: string;
}

/**
 * 输入操作
 */
export interface InputAction extends BaseAction {
  type: ActionType.INPUT;
  selector: string;
  value: string;
  clear?: boolean;
}

/**
 * 数据提取字段定义
 */
export interface ExtractField {
  /** 字段名 */
  field: string;
  /** 选择器 */
  selector: string;
  /** 提取属性 */
  attribute: string;
  /** 数据转换 */
  transform?: string;
  /** 正则表达式 */
  regex?: string;
  /** 正则分组 */
  group?: number;
}

/**
 * 提取操作
 */
export interface ExtractAction extends BaseAction {
  type: ActionType.EXTRACT;
  /** 选择器（从DOM提取时使用） */
  selector?: string;
  /** 数据源类型：selector(默认), variable, script */
  source?: 'selector' | 'variable' | 'script';
  /** 变量名（source为variable时使用） */
  variable?: string;
  /** 是否提取多个结果 */
  multiple?: boolean;
  /** 字段映射 */
  fields: Record<string, string> | ExtractField[];
  /** 数据验证规则 */
  validation?: ValidationRule[];
}

/**
 * 条件判断操作
 */
export interface ConditionAction extends BaseAction {
  type: ActionType.CONDITION;
  selector: string;
  exists?: boolean;
  text?: string;
  then: Action[];
  else?: Action[];
}

/**
 * 脚本执行操作
 */
export interface ScriptAction extends BaseAction {
  type: ActionType.SCRIPT;
  code: string;
  timeout?: number;
  saveAs?: string;
}

/**
 * Cloudflare绕过操作
 */
export interface CloudflareBypassAction extends BaseAction {
  type: ActionType.CLOUDFLARE_BYPASS;
  method: 'wait' | 'solve' | 'click' | 'refresh' | 'interactive';
  maxWaitTime?: number;
  indicators?: string[];
}

/**
 * 验证码处理操作
 */
export interface CaptchaAction extends BaseAction {
  type: ActionType.CAPTCHA;
  selector: string;
  method: 'manual' | 'auto';
  timeout?: number;
}

/**
 * IP限制处理操作
 */
export interface IPBlockAction extends BaseAction {
  type: ActionType.IP_BLOCK;
  indicators: string[];
  action: 'retry' | 'abort';
  delay?: number;
}

/**
 * 循环跳出条件
 */
export interface LoopBreakCondition {
  /** 选择器（用于检查元素是否存在） */
  selector?: string;
  /** 元素是否存在 */
  exists?: boolean;
  /** 变量名（用于检查变量值） */
  variable?: string;
  /** 期望的值 */
  value?: string;
  /** 比较操作符 */
  operator?: 'equals' | 'notEquals' | 'empty' | 'notEmpty';
}

/**
 * 循环操作
 */
export interface LoopAction extends BaseAction {
  type: ActionType.LOOP;
  /** 循环的元素选择器（可选，用于遍历元素） */
  selector?: string;
  /** 最大循环次数 */
  maxIterations?: number;
  /** 每次循环执行的操作 */
  actions: Action[];
  /** 跳出条件 */
  breakCondition?: LoopBreakCondition;
}

/**
 * 并行操作
 */
export interface ParallelAction extends BaseAction {
  type: ActionType.PARALLEL;
  /** 并行执行的操作组 */
  actions: Action[][];
  /** 是否等待所有完成 */
  waitAll: boolean;
  /** 最大并发数 */
  maxConcurrent?: number;
}

/**
 * 滚动操作
 */
export interface ScrollAction extends BaseAction {
  type: ActionType.SCROLL;
  /** 滚动方向 */
  direction: 'up' | 'down' | 'left' | 'right' | 'top' | 'bottom';
  /** 滚动距离（像素） */
  distance?: number;
  /** 滚动到元素 */
  toElement?: string;
  /** 平滑滚动 */
  smooth?: boolean;
}

/**
 * 悬停操作
 */
export interface HoverAction extends BaseAction {
  type: ActionType.HOVER;
  selector: string;
  /** 悬停持续时间 */
  duration?: number;
}

/**
 * 下拉选择操作
 */
export interface SelectAction extends BaseAction {
  type: ActionType.SELECT;
  selector: string;
  /** 选择的值 */
  value: string;
  /** 选择方式 */
  by: 'value' | 'text' | 'index';
}

/**
 * 变量设置操作
 */
export interface VariableSetAction extends BaseAction {
  type: ActionType.VARIABLE_SET;
  /** 变量名 */
  name: string;
  /** 变量值 */
  value: string;
  /** 值来源 */
  source?: 'constant' | 'selector' | 'script';
  /** 如果source是selector，指定选择器 */
  selector?: string;
  /** 如果source是selector，指定属性 */
  attribute?: string;
}

/**
 * 变量获取操作
 */
export interface VariableGetAction extends BaseAction {
  type: ActionType.VARIABLE_GET;
  /** 变量名 */
  name: string;
}

/**
 * Cookie设置操作
 */
export interface CookieSetAction extends BaseAction {
  type: ActionType.COOKIE_SET;
  name: string;
  value: string;
  domain?: string;
  path?: string;
  expires?: number;
  httpOnly?: boolean;
  secure?: boolean;
}

/**
 * Cookie获取操作
 */
export interface CookieGetAction extends BaseAction {
  type: ActionType.COOKIE_GET;
  /** Cookie名称，不指定则获取所有 */
  name?: string;
  /** 存储到变量 */
  variable: string;
}

/**
 * Storage设置操作
 */
export interface StorageSetAction extends BaseAction {
  type: ActionType.STORAGE_SET;
  storageType: 'localStorage' | 'sessionStorage';
  key: string;
  value: string;
}

/**
 * Storage获取操作
 */
export interface StorageGetAction extends BaseAction {
  type: ActionType.STORAGE_GET;
  storageType: 'localStorage' | 'sessionStorage';
  key: string;
  /** 存储到变量 */
  variable: string;
}

/**
 * 截图操作
 */
export interface ScreenshotAction extends BaseAction {
  type: ActionType.SCREENSHOT;
  /** 截取特定元素 */
  selector?: string;
  /** 全页截图 */
  fullPage?: boolean;
  /** 保存路径 */
  savePath: string;
}

/**
 * 操作联合类型
 */
export type Action = NavigateAction | WaitAction | ClickAction | InputAction | 
                    ExtractAction | ConditionAction | ScriptAction | 
                    CloudflareBypassAction | CaptchaAction | IPBlockAction |
                    LoopAction | ParallelAction | ScrollAction | HoverAction | SelectAction |
                    VariableSetAction | VariableGetAction | 
                    CookieSetAction | CookieGetAction |
                    StorageSetAction | StorageGetAction | ScreenshotAction |
                    APIRequestAction | HTTPRequestAction;

// ==================== 工作流程定义 ====================

/**
 * 工作流程类型
 */
export enum WorkflowType {
  INITIALIZE = 'initialize',
  LOGIN = 'login',
  SEARCH = 'search',
  SEARCH_BY_ID = 'searchById',
  SEARCH_BY_AUTHOR = 'searchByAuthor',
  SEARCH_BY_SERIES = 'searchBySeries',
  SEARCH_BY_TAG = 'searchByTag',
  RESOLVE_URL = 'resolveUrl',
  FILTER = 'filter',
  GET_MANGA_LIST = 'getMangaList',
  GET_MANGA_DETAIL = 'getMangaDetail',
  GET_MANGA_DETAIL_WITH_CHAPTERS = 'getMangaDetailWithChapters',
  GET_CHAPTER_LIST = 'getChapterList',
  GET_PAGE_LIST = 'getPageList',
  LOAD_MORE_PAGES = 'loadMorePages',
  GET_IMAGE_URL = 'getImageUrl',
  POPULAR = 'popular',
  LATEST = 'latest',
  FAVORITES = 'favorites',
  HISTORY = 'history',
  GET_USER_AVATAR = 'getUserAvatar',
  GET_LEADERBOARD = 'getLeaderboard',
  // 电子书相关工作流
  GET_CATEGORY = 'getCategory',
  GET_BOOK_DETAIL = 'getBookDetail',
  GET_DOWNLOAD_URL = 'getDownloadUrl',
  // 电子书下载流程工作流
  CLICK_SEARCH_BUTTON = 'clickSearchButton',
  WAIT_FOR_DOWNLOAD_SOURCES = 'waitForDownloadSources',
  SELECT_DOWNLOAD_SOURCE = 'selectDownloadSource',
  EXTRACT_FILE_LIST = 'extractFileList',
  // 直达搜索工作流（不进行URL规范化，直接使用原始输入）
  DIRECT_SEARCH = 'directSearch'
}

/**
 * 工作流程定义
 */
export interface Workflow {
  [WorkflowType.INITIALIZE]?: Action[];
  [WorkflowType.LOGIN]?: Action[];
  [WorkflowType.SEARCH]?: Action[];
  [WorkflowType.SEARCH_BY_ID]?: Action[];
  [WorkflowType.SEARCH_BY_AUTHOR]?: Action[];
  [WorkflowType.SEARCH_BY_SERIES]?: Action[];
  [WorkflowType.SEARCH_BY_TAG]?: Action[];
  [WorkflowType.RESOLVE_URL]?: Action[];
  [WorkflowType.FILTER]?: Action[];
  [WorkflowType.GET_MANGA_LIST]?: Action[];
  [WorkflowType.GET_MANGA_DETAIL]?: Action[];
  [WorkflowType.GET_MANGA_DETAIL_WITH_CHAPTERS]?: Action[];
  [WorkflowType.GET_CHAPTER_LIST]?: Action[];
  [WorkflowType.GET_PAGE_LIST]?: Action[];
  [WorkflowType.LOAD_MORE_PAGES]?: Action[];
  [WorkflowType.GET_IMAGE_URL]?: Action[];
  [WorkflowType.POPULAR]?: Action[];
  [WorkflowType.LATEST]?: Action[];
  [WorkflowType.FAVORITES]?: Action[];
  [WorkflowType.HISTORY]?: Action[];
  [WorkflowType.GET_USER_AVATAR]?: Action[];
  [WorkflowType.GET_LEADERBOARD]?: Action[];
  // 电子书相关工作流
  [WorkflowType.GET_CATEGORY]?: Action[];
  [WorkflowType.GET_BOOK_DETAIL]?: Action[];
  [WorkflowType.GET_DOWNLOAD_URL]?: Action[];
  // 电子书下载流程工作流
  [WorkflowType.CLICK_SEARCH_BUTTON]?: Action[];
  [WorkflowType.WAIT_FOR_DOWNLOAD_SOURCES]?: Action[];
  [WorkflowType.SELECT_DOWNLOAD_SOURCE]?: Action[];
  [WorkflowType.EXTRACT_FILE_LIST]?: Action[];
  // 直达搜索工作流
  [WorkflowType.DIRECT_SEARCH]?: Action[];
}

// ==================== 错误处理和重试 ====================

/**
 * 重试策略
 */
export interface RetryStrategy {
  /** 最大重试次数 */
  maxAttempts: number;
  /** 延迟时间 */
  delay: number;
  /** 退避策略 */
  backoff: 'linear' | 'exponential';
  /** 重试条件 */
  conditions: string[];
}

/**
 * 降级策略
 */
export interface FallbackStrategy {
  /** 备用选择器 */
  selector?: string;
  /** 备用工作流程 */
  workflow?: string;
}

// ==================== 性能和缓存 ====================

/**
 * 缓存配置
 */
export interface CacheConfig {
  /** 启用缓存 */
  enabled: boolean;
  /** 生存时间(毫秒) */
  ttl: number;
  /** 缓存键 */
  keys: string[];
  /** 缓存策略 */
  strategy?: 'LRU' | 'FIFO' | 'LFU';
  /** 最大缓存大小(字节) */
  maxSize?: number;
  /** 最大缓存条目数 */
  maxEntries?: number;
}

/**
 * 并发控制
 */
export interface ConcurrencyConfig {
  /** 最大并发数 */
  maxConcurrent: number;
  /** 延迟时间 */
  delay: number;
}

/**
 * 性能阈值配置
 */
export interface PerformanceThresholds {
  loadTime?: number;
  memoryUsage?: number;
  networkLatency?: number;
}

/**
 * 性能监控配置
 */
export interface PerformanceConfig {
  /** 启用性能监控 */
  enabled: boolean;
  /** 监控指标 */
  metrics: ('timing' | 'memory' | 'network' | 'fps')[];
  /** 报告间隔(毫秒) */
  reportInterval?: number;
  /** 性能阈值警告 */
  thresholds?: PerformanceThresholds;
}

/**
 * 数据验证规则
 */
export interface ValidationRule {
  /** 字段名 */
  field: string;
  /** 验证类型 */
  type: 'required' | 'format' | 'range' | 'custom';
  /** 格式模式(正则) */
  pattern?: string;
  /** 最小值 */
  min?: number;
  /** 最大值 */
  max?: number;
  /** 自定义验证函数 */
  validator?: string;
  /** 错误消息 */
  message?: string;
}

// ==================== 调试和日志 ====================

/**
 * 调试配置
 */
export interface DebugConfig {
  /** 启用调试 */
  enabled: boolean;
  /** 日志级别 */
  level: 'debug' | 'info' | 'warn' | 'error';
  /** 记录操作 */
  logActions: boolean;
  /** 记录选择器 */
  logSelectors: boolean;
}

/**
 * 截图配置
 */
export interface ScreenshotConfig {
  /** 错误时截图 */
  onError: boolean;
  /** 成功时截图 */
  onSuccess: boolean;
  /** 截图路径 */
  path: string;
}

// ==================== 扩展系统 ====================

/**
 * 自定义操作
 */
export interface CustomAction {
  type: string;
  code: string;
}

/**
 * 插件配置
 */
export interface PluginConfig {
  name: string;
  enabled: boolean;
  config: Record<string, Object>;
}

// ==================== 主配置接口 ====================

/**
 * Token提取配置
 */
export interface TokenExtractionConfig {
  type: 'json' | 'header' | 'cookie';
  path: string;
}

/**
 * 认证配置
 */
export interface AuthenticationConfig {
  /** 认证类型 */
  type: 'jwt' | 'cookie' | 'basic';
  /** 登录URL */
  loginUrl: string;
  /** 登录方法 */
  loginMethod: 'POST' | 'GET';
  /** Token存储键 */
  tokenStorageKey?: string;
  /** Token有效期余量(秒) */
  tokenLeeway?: number;
  /** 登录载荷 */
  loginPayload?: Record<string, string>;
  /** Token提取配置 */
  tokenExtraction?: TokenExtractionConfig;
  /** 是否需要登录 */
  requiresLogin: boolean;
}

/**
 * 漫画图源配置
 */
export interface MangaSourceConfig {
  /** 元数据 */
  metadata: MangaSourceMetadata;
  /** 设置 */
  settings: MangaSourceSettings;
  /** 认证配置 */
  authentication?: AuthenticationConfig;
  /** 工作流程 */
  workflows: Workflow;
  /** 搜索配置 */
  searchConfig?: SearchConfig;
  /** 变量定义 */
  variables?: Record<string, string>;
  /** 重试策略 */
  retry?: RetryStrategy;
  /** 降级策略 */
  fallback?: FallbackStrategy;
  /** 缓存配置 */
  cache?: CacheConfig;
  /** 并发控制 */
  concurrency?: ConcurrencyConfig;
  /** 调试配置 */
  debug?: DebugConfig;
  /** 截图配置 */
  screenshot?: ScreenshotConfig;
  /** 性能监控配置 */
  performance?: PerformanceConfig;
  /** 数据验证规则 */
  validation?: ValidationRule[];
  /** 自定义操作 */
  customActions?: Record<string, CustomAction>;
  /** 插件配置 */
  plugins?: PluginConfig[];
  /** 反爬虫配置 */
  antiCrawler?: AntiCrawlerConfig;
}

// ==================== 执行结果类型 ====================

/**
 * 操作执行结果
 */
export interface ActionResult {
  /** 是否成功 */
  success: boolean;
  /** 结果数据 */
  data?: Object;
  /** 错误信息 */
  error?: string;
  /** 执行时间 */
  duration: number;
  /** 诊断Trace ID */
  traceId?: string;
  /** 工作流名称 */
  workflowName?: string;
  /** 操作序号 */
  actionIndex?: number;
  /** 操作描述 */
  actionDescription?: string;
  /** 当前页面URL */
  currentUrl?: string;
  /** 诊断事件 */
  diagnosticEvents?: SourceDiagnosticEvent[];
}

/**
 * 工作流程执行结果
 */
export interface WorkflowResult {
  /** 工作流程类型 */
  type: WorkflowType;
  /** 是否成功 */
  success: boolean;
  /** 结果数据 */
  data?: Object;
  /** 错误信息 */
  error?: string;
  /** 执行时间 */
  duration: number;
  /** 操作结果列表 */
  actions: ActionResult[];
}

// ==================== 漫画数据类型 ====================

/**
 * 漫画信息
 */
export interface MangaInfo {
  /** 漫画ID */
  id?: string;
  /** 标题 */
  title: string;
  /** URL */
  url: string;
  /** 封面图 */
  cover: string;
  /** 作者 */
  author?: string;
  /** 状态 */
  status?: string;
  /** 描述 */
  description?: string;
  /** 类型标签 */
  genres?: string[];
  /** 更新时间 */
  updated?: string;
}

/**
 * 章节信息
 */
export interface ChapterInfo {
  /** 章节ID */
  id?: string;
  /** 外部章节ID（从API获取的原始ID，用于构造请求URL和Referer） */
  externalId?: string;
  /** 标题 */
  title: string;
  /** URL */
  url: string;
  /** 章节号 */
  number?: number;
  /** 发布时间 */
  publishTime?: string;
  /** 页数 */
  pageCount?: number;
}

/**
 * 页面信息
 */
export interface PageRequestHeader {
  /** 请求头名称 */
  name: string;
  /** 请求头值 */
  value: string;
}

export interface PageInfo {
  /** 页码 */
  page: number;
  /** 图片URL */
  imageUrl: string;
  /** 图片宽度 */
  width?: number;
  /** 图片高度 */
  height?: number;
  /** 页面级图片请求头 */
  requestHeaders?: PageRequestHeader[];
}

// ==================== 错误类型定义 ====================

/**
 * 反爬虫配置类型定义
 */

/**
 * Cloudflare配置
 */
export interface CloudflareConfig {
  enabled?: boolean;
  indicators?: string[];
  bypassMethod?: 'wait' | 'click' | 'refresh' | 'interactive';
  maxWaitTime?: number;
  maxRetries?: number;
  retryCount?: number;
  timeout?: number;
}

/**
 * 验证码配置
 */
export interface CaptchaConfig {
  enabled?: boolean;
  indicators?: string[];
  autoSolve?: boolean;
  solverType?: 'manual' | 'api' | 'ai';
  apiKey?: string;
  timeout?: number;
}

/**
 * IP封禁配置
 */
export interface IpBlockConfig {
  enabled?: boolean;
  indicators?: string[];
  delay?: number;
  maxRetries?: number;
  retryDelay?: number;
}

/**
 * User-Agent轮换配置
 */
export interface UserAgentRotationConfig {
  enabled: boolean;
  agents: string[];
  rotateInterval?: number;
}

/**
 * 反爬虫配置
 */
export interface AntiCrawlerConfig {
  cloudflare?: CloudflareConfig;
  captcha?: CaptchaConfig;
  ipBlock?: IpBlockConfig;
  userAgentRotation?: UserAgentRotationConfig;
}

/**
 * 图源引擎错误码
 */
export enum MangaSourceErrorCode {
  INVALID_CONFIG = 'INVALID_CONFIG',
  CONFIG_NOT_LOADED = 'CONFIG_NOT_LOADED',
  ACTION_FAILED = 'ACTION_FAILED',
  DATA_NOT_FOUND = 'DATA_NOT_FOUND',
  NETWORK_ERROR = 'NETWORK_ERROR',
  TIMEOUT_ERROR = 'TIMEOUT_ERROR',
  ELEMENT_NOT_FOUND = 'ELEMENT_NOT_FOUND',
  EXTRACTION_FAILED = 'EXTRACTION_FAILED',
  SELECTOR_ERROR = 'SELECTOR_ERROR',
  INVALID_SELECTOR = 'INVALID_SELECTOR',
  VARIABLE_NOT_FOUND = 'VARIABLE_NOT_FOUND',
  WORKFLOW_NOT_FOUND = 'WORKFLOW_NOT_FOUND',
  CLOUDFLARE_BLOCKED = 'CLOUDFLARE_BLOCKED',
  CAPTCHA_REQUIRED = 'CAPTCHA_REQUIRED',
  CAPTCHA_FAILED = 'CAPTCHA_FAILED',
  IP_BLOCKED = 'IP_BLOCKED',
  SCRIPT_ERROR = 'SCRIPT_ERROR',
  UNKNOWN_ERROR = 'UNKNOWN_ERROR'
}

/**
 * 图源引擎错误
 */
// ==================== API操作类型 ====================

/**
 * 数据提取配置
 */
export interface ExtractConfig {
  /** 数据路径（JSONPath格式） */
  path?: string;
  /** 字段映射 */
  fields?: Record<string, string>;
}

/**
 * API分页配置
 */
export interface APIPaginationConfig {
  /** 是否启用分页 */
  enabled: boolean;
  /** 分页类型 */
  type?: string;
  /** 页码参数名 */
  pageParam?: string;
  /** 判断是否有更多页的路径表达式 */
  hasMorePath?: string;
}

/**
 * API请求操作
 */
export interface APIRequestAction extends BaseAction {
  type: ActionType.API_REQUEST;
  /** 请求方法 */
  method: 'GET' | 'POST' | 'PUT' | 'DELETE';
  /** 请求URL */
  url: string;
  /** 查询参数 */
  params?: Record<string, string>;
  /** 请求头 */
  headers?: Record<string, string>;
  /** 请求体 */
  body?: Record<string, Object | undefined>;
  /** 响应数据提取配置 */
  extract?: ExtractConfig;
  /** API分页配置 */
  pagination?: APIPaginationConfig;
}

/**
 * HTTP请求操作（通用）
 */
export interface HTTPRequestAction extends BaseAction {
  type: ActionType.HTTP_REQUEST;
  method: 'GET' | 'POST' | 'PUT' | 'DELETE';
  url: string;
  headers?: Record<string, string>;
  body?: string | Record<string, Object | undefined>;
  timeout?: number;
}

// ==================== 任务系统类型定义 ====================

/**
 * 任务执行模式
 */
export enum TaskExecutionMode {
  /** 顺序执行 */
  SEQUENTIAL = 'sequential',
  /** 并行执行 */
  PARALLEL = 'parallel',
  /** 条件执行 */
  CONDITIONAL = 'conditional'
}

/**
 * 任务状态
 */
export enum TaskStatus {
  PENDING = 'pending',
  RUNNING = 'running',
  COMPLETED = 'completed',
  FAILED = 'failed',
  CANCELLED = 'cancelled',
  WAITING = 'waiting'
}

/**
 * 任务步骤定义
 * 每个步骤可以是一个工作流引用或内联操作
 */
export interface TaskStep {
  /** 步骤ID */
  id: string;
  /** 步骤名称 */
  name?: string;
  /** 步骤描述 */
  description?: string;
  /** 引用的工作流名称（使用已定义的工作流） */
  workflow?: string;
  /** 内联操作（不使用工作流时） */
  actions?: Action[];
  /** 输入参数映射：{ 目标参数名: 来源表达式 } */
  inputMapping?: Record<string, string>;
  /** 输出参数映射：{ 输出变量名: 提取表达式 } */
  outputMapping?: Record<string, string>;
  /** 条件表达式（返回true才执行此步骤） */
  condition?: string;
  /** 超时时间(毫秒) */
  timeout?: number;
  /** 重试配置 */
  retry?: TaskRetryConfig;
  /** 失败时是否继续执行后续步骤 */
  continueOnError?: boolean;
  /** 等待用户交互 */
  waitForUserInteraction?: boolean;
  /** 用户交互提示 */
  userInteractionPrompt?: string;
}

/**
 * 任务重试配置
 */
export interface TaskRetryConfig {
  /** 最大重试次数 */
  maxRetries: number;
  /** 重试延迟(毫秒) */
  delay: number;
  /** 退避策略 */
  backoff?: 'linear' | 'exponential';
  /** 重试条件表达式 */
  retryCondition?: string;
}

/**
 * 任务定义
 * 一个任务由多个步骤组成，可以顺序或并行执行
 */
export interface TaskDefinition {
  /** 任务ID */
  id: string;
  /** 任务名称 */
  name: string;
  /** 任务描述 */
  description?: string;
  /** 执行模式 */
  mode: TaskExecutionMode;
  /** 任务步骤 */
  steps: TaskStep[];
  /** 初始参数 */
  initialParams?: Record<string, string>;
  /** 全局超时(毫秒) */
  timeout?: number;
  /** 失败时的回退任务ID */
  fallbackTask?: string;
  /** 成功后的回调任务ID */
  onSuccess?: string;
  /** 失败后的回调任务ID */
  onFailure?: string;
}

/**
 * 任务执行上下文
 * 用于在步骤之间传递数据
 */
export interface TaskContext {
  /** 任务ID */
  taskId: string;
  /** 当前步骤索引 */
  currentStepIndex: number;
  /** 任务状态 */
  status: TaskStatus;
  /** 变量存储 */
  variables: Record<string, Object | undefined>;
  /** 步骤结果 */
  stepResults: Record<string, Object | undefined>;
  /** 错误信息 */
  errors: TaskError[];
  /** 开始时间 */
  startTime: number;
  /** 结束时间 */
  endTime?: number;
}

/**
 * 任务错误
 */
export interface TaskError {
  stepId: string;
  message: string;
  code?: string;
  timestamp: number;
  recoverable: boolean;
}

/**
 * 任务结果
 */
export interface TaskResult {
  /** 任务ID */
  taskId: string;
  /** 是否成功 */
  success: boolean;
  /** 最终数据 */
  data?: Object;
  /** 错误信息 */
  error?: string;
  /** 执行耗时(毫秒) */
  duration: number;
  /** 各步骤结果 */
  stepResults: Record<string, Object | undefined>;
}

/**
 * 任务配置（在source.json中使用）
 */
export interface TasksConfig {
  /** 任务定义列表 */
  tasks: Record<string, TaskDefinition>;
}

/**
 * 电子书下载任务专用配置
 */
export interface EbookDownloadTaskConfig {
  /** 获取下载源列表的任务 */
  getDownloadSources: TaskDefinition;
  /** 获取文件列表的任务 */
  getFileList: TaskDefinition;
  /** 下载文件的任务 */
  downloadFile: TaskDefinition;
}

// ==================== 错误处理 ====================

export class MangaSourceError extends Error {
  code: MangaSourceErrorCode;
  details?: Object;

  constructor(
    code: MangaSourceErrorCode,
    message: string,
    details?: Object
  ) {
    super(message);
    this.name = 'MangaSourceError';
    this.code = code;
    this.details = details;
  }
}
