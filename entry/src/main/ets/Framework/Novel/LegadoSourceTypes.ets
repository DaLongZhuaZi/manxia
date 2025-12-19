/**
 * Legado书源类型定义
 * 兼容Legado阅读APP的书源格式
 * 
 * 文件路径: entry/src/main/ets/Framework/Novel/LegadoSourceTypes.ets
 * 职责: 定义Legado书源的数据结构和类型
 */

/**
 * 书源类型枚举
 * 0: 文本小说
 * 1: 音频
 * 2: 图片（漫画）
 * 3: 文件（下载类）
 */
export enum LegadoBookSourceType {
  TEXT = 0,
  AUDIO = 1,
  IMAGE = 2,
  FILE = 3
}

/**
 * 搜索规则
 */
export interface LegadoSearchRule {
  /** 校验关键字 */
  checkKeyWord?: string;
  /** 书籍列表规则 */
  bookList?: string;
  /** 书名规则 */
  name?: string;
  /** 作者规则 */
  author?: string;
  /** 简介规则 */
  intro?: string;
  /** 分类规则 */
  kind?: string;
  /** 最新章节规则 */
  lastChapter?: string;
  /** 更新时间规则 */
  updateTime?: string;
  /** 详情页URL规则 */
  bookUrl?: string;
  /** 封面URL规则 */
  coverUrl?: string;
  /** 字数规则 */
  wordCount?: string;
}

/**
 * 发现规则
 */
export interface LegadoExploreRule {
  /** 书籍列表规则 */
  bookList?: string;
  /** 书名规则 */
  name?: string;
  /** 作者规则 */
  author?: string;
  /** 简介规则 */
  intro?: string;
  /** 分类规则 */
  kind?: string;
  /** 最新章节规则 */
  lastChapter?: string;
  /** 更新时间规则 */
  updateTime?: string;
  /** 详情页URL规则 */
  bookUrl?: string;
  /** 封面URL规则 */
  coverUrl?: string;
  /** 字数规则 */
  wordCount?: string;
}

/**
 * 书籍详情规则
 */
export interface LegadoBookInfoRule {
  /** 初始化规则（预处理） */
  init?: string;
  /** 书名规则 */
  name?: string;
  /** 作者规则 */
  author?: string;
  /** 简介规则 */
  intro?: string;
  /** 分类规则 */
  kind?: string;
  /** 最新章节规则 */
  lastChapter?: string;
  /** 更新时间规则 */
  updateTime?: string;
  /** 封面URL规则 */
  coverUrl?: string;
  /** 目录URL规则 */
  tocUrl?: string;
  /** 字数规则 */
  wordCount?: string;
  /** 是否允许重命名 */
  canReName?: string;
  /** 下载URL规则（文件类书源） */
  downloadUrls?: string;
}

/**
 * 目录规则
 */
export interface LegadoTocRule {
  /** 预处理JS */
  preUpdateJs?: string;
  /** 章节列表规则 */
  chapterList?: string;
  /** 章节名称规则 */
  chapterName?: string;
  /** 章节URL规则 */
  chapterUrl?: string;
  /** 格式化JS */
  formatJs?: string;
  /** 是否卷标识 */
  isVolume?: string;
  /** 是否VIP */
  isVip?: string;
  /** 是否付费 */
  isPay?: string;
  /** 更新时间规则 */
  updateTime?: string;
  /** 下一页目录URL */
  nextTocUrl?: string;
}

/**
 * 正文规则
 */
export interface LegadoContentRule {
  /** 正文内容规则 */
  content?: string;
  /** 标题规则（有些网站只能在正文中获取标题） */
  title?: string;
  /** 下一页正文URL */
  nextContentUrl?: string;
  /** WebView执行的JS */
  webJs?: string;
  /** 源正则 */
  sourceRegex?: string;
  /** 替换规则 */
  replaceRegex?: string;
  /** 图片样式 */
  imageStyle?: string;
  /** 图片解密JS */
  imageDecode?: string;
  /** 购买操作 */
  payAction?: string;
}

/**
 * 段评规则（可选）
 */
export interface LegadoReviewRule {
  /** 段评列表规则 */
  reviewList?: string;
  /** 段评内容规则 */
  content?: string;
  /** 段评作者规则 */
  author?: string;
  /** 段评时间规则 */
  time?: string;
}

/**
 * 登录UI配置
 */
export interface LegadoLoginUiItem {
  /** 类型：text, password, button */
  type: string;
  /** 名称 */
  name: string;
  /** 提示文本 */
  hint?: string;
}

/**
 * Legado书源配置
 * 完整兼容Legado阅读APP的书源JSON格式
 */
export interface LegadoBookSource {
  /** 书源URL（唯一标识） */
  bookSourceUrl: string;
  /** 书源名称 */
  bookSourceName: string;
  /** 书源分组 */
  bookSourceGroup?: string;
  /** 书源类型 */
  bookSourceType: LegadoBookSourceType;
  /** 详情页URL正则 */
  bookUrlPattern?: string;
  /** 手动排序编号 */
  customOrder?: number;
  /** 是否启用 */
  enabled?: boolean;
  /** 启用发现 */
  enabledExplore?: boolean;
  /** JS库 */
  jsLib?: string;
  /** 启用CookieJar */
  enabledCookieJar?: boolean;
  /** 并发率 */
  concurrentRate?: string;
  /** 请求头 */
  header?: string;
  /** 登录地址/JS */
  loginUrl?: string;
  /** 登录UI配置 */
  loginUi?: string;
  /** 登录检测JS */
  loginCheckJs?: string;
  /** 封面解密JS */
  coverDecodeJs?: string;
  /** 注释 */
  bookSourceComment?: string;
  /** 自定义变量说明 */
  variableComment?: string;
  /** 最后更新时间 */
  lastUpdateTime?: number;
  /** 响应时间 */
  respondTime?: number;
  /** 权重 */
  weight?: number;
  /** 发现URL */
  exploreUrl?: string;
  /** 发现筛选规则 */
  exploreScreen?: string;
  /** 发现规则 */
  ruleExplore?: LegadoExploreRule;
  /** 搜索URL */
  searchUrl?: string;
  /** 搜索规则 */
  ruleSearch?: LegadoSearchRule;
  /** 书籍信息规则 */
  ruleBookInfo?: LegadoBookInfoRule;
  /** 目录规则 */
  ruleToc?: LegadoTocRule;
  /** 正文规则 */
  ruleContent?: LegadoContentRule;
  /** 段评规则 */
  ruleReview?: LegadoReviewRule;
}

/**
 * 书籍信息
 */
export interface LegadoBook {
  /** 书籍ID（内部生成） */
  id: string;
  /** 书源URL */
  origin: string;
  /** 书源名称 */
  originName: string;
  /** 书籍URL */
  bookUrl: string;
  /** 书名 */
  name: string;
  /** 作者 */
  author: string;
  /** 分类 */
  kind?: string;
  /** 简介 */
  intro?: string;
  /** 封面URL */
  coverUrl?: string;
  /** 目录URL */
  tocUrl?: string;
  /** 最新章节 */
  latestChapterTitle?: string;
  /** 字数 */
  wordCount?: string;
  /** 更新时间 */
  updateTime?: number;
  /** 书源类型 */
  type: LegadoBookSourceType;
  /** 自定义变量 */
  variable?: string;
  /** 目录HTML（缓存） */
  tocHtml?: string;
  /** 详情HTML（缓存） */
  infoHtml?: string;
}

/**
 * 章节信息
 */
export interface LegadoChapter {
  /** 章节ID（内部生成） */
  id: string;
  /** 书籍URL */
  bookUrl: string;
  /** 章节URL */
  url: string;
  /** 章节标题 */
  title: string;
  /** 章节索引 */
  index: number;
  /** 是否卷标题 */
  isVolume?: boolean;
  /** 是否VIP */
  isVip?: boolean;
  /** 是否付费 */
  isPay?: boolean;
  /** 更新时间 */
  updateTime?: number;
  /** 自定义变量 */
  variable?: string;
  /** 标签 */
  tag?: string;
}

/**
 * 搜索结果
 */
export interface LegadoSearchBook {
  /** 书源URL */
  origin: string;
  /** 书源名称 */
  originName: string;
  /** 书籍URL */
  bookUrl: string;
  /** 书名 */
  name: string;
  /** 作者 */
  author: string;
  /** 分类 */
  kind?: string;
  /** 简介 */
  intro?: string;
  /** 封面URL */
  coverUrl?: string;
  /** 最新章节 */
  latestChapterTitle?: string;
  /** 字数 */
  wordCount?: string;
  /** 书源类型 */
  type: LegadoBookSourceType;
  /** 详情HTML（缓存） */
  infoHtml?: string;
  /** 自定义变量 */
  variable?: string;
}

/**
 * 规则解析模式
 */
export enum LegadoRuleMode {
  /** 默认模式（JSOUP CSS选择器） */
  Default = 'default',
  /** XPath模式 */
  XPath = 'xpath',
  /** JSONPath模式 */
  Json = 'json',
  /** JavaScript模式 */
  Js = 'js',
  /** 正则表达式模式 */
  Regex = 'regex'
}

/**
 * 解析后的规则
 */
export interface LegadoParsedRule {
  /** 规则模式 */
  mode: LegadoRuleMode;
  /** 规则内容 */
  rule: string;
  /** 替换正则 */
  replaceRegex?: string;
  /** 替换内容 */
  replacement?: string;
  /** 是否只替换第一个 */
  replaceFirst?: boolean;
  /** put变量映射 */
  putMap?: Record<string, string>;
}

/**
 * URL选项
 */
export interface LegadoUrlOption {
  /** 请求方法 */
  method?: string;
  /** 字符集 */
  charset?: string;
  /** 请求头 */
  headers?: Record<string, string>;
  /** 请求体 */
  body?: string;
  /** 重试次数 */
  retry?: number;
  /** 类型 */
  type?: string;
  /** 是否使用WebView */
  webView?: boolean;
  /** WebView执行的JS */
  webJs?: string;
  /** URL解析后执行的JS */
  js?: string;
  /** 服务器ID */
  serverID?: number;
  /** WebView延迟时间 */
  webViewDelayTime?: number;
}

/**
 * 发现分类
 */
export interface LegadoExploreKind {
  /** 分类标题 */
  title: string;
  /** 分类URL */
  url: string;
  /** 样式 */
  style?: LegadoExploreKindStyle;
}

/**
 * 发现分类样式
 */
export interface LegadoExploreKindStyle {
  /** 布局方式 */
  layout_flexGrow?: number;
  layout_flexShrink?: number;
  layout_alignSelf?: string;
  layout_flexBasisPercent?: number;
  layout_wrapBefore?: boolean;
}

/**
 * 书源导入结果
 */
export interface LegadoSourceImportResult {
  /** 是否成功 */
  success: boolean;
  /** 书源ID */
  sourceId?: string;
  /** 书源名称 */
  sourceName?: string;
  /** 错误信息 */
  error?: string;
}

/**
 * 书源测试结果
 */
export interface LegadoSourceTestResult {
  /** 是否成功 */
  success: boolean;
  /** 测试项 */
  testItem: string;
  /** 耗时（毫秒） */
  duration: number;
  /** 结果数据 */
  data?: ESObject;
  /** 错误信息 */
  error?: string;
}
