/**
 * 小说模块导出索引
 * 
 * 文件路径: entry/src/main/ets/Framework/Novel/index.ets
 */

// 类型定义
export {
  LegadoBookSourceType,
  LegadoRuleMode,
  LegadoBookSource,
  LegadoSearchRule,
  LegadoBookInfoRule,
  LegadoTocRule,
  LegadoContentRule,
  LegadoExploreRule,
  LegadoBook,
  LegadoChapter,
  LegadoSearchBook,
  LegadoParsedRule,
  LegadoUrlOption,
  LegadoExploreKind,
  LegadoSourceImportResult,
  LegadoSourceTestResult
} from 'manxia_novel/src/main/ets/Framework/Novel/LegadoSourceTypes';

// 规则解析器
export { LegadoRuleAnalyzer } from './LegadoRuleAnalyzer';

// URL解析器
export { LegadoUrlAnalyzer, ParsedUrlRequest, RequestMethod } from './LegadoUrlAnalyzer';

// 书源解析器
export { LegadoSourceParser } from 'manxia_novel/src/main/ets/Framework/Novel/LegadoSourceParser';

// 执行器
export { NovelSourceExecutor } from './NovelSourceExecutor';

// 管理器
export { NovelSourceManager, getNovelSourceManager } from './NovelSourceManager';
export {
  DEFAULT_NOVEL_SOURCE_REPOSITORY_URL,
  NovelSourceRepositoryManager,
  getNovelSourceRepositoryManager,
  NovelSourceRepositoryEntry,
  NovelSourceRepositoryIndex,
  NovelSourceSavedRepository,
  NovelSourceRepositorySyncResult,
  NovelSourceRepositoryUpdateStatus
} from './NovelSourceRepositoryManager';
export {
  DEFAULT_LEGADO_RUNTIME_REPOSITORY_URL,
  LegadoRuntimeAssetManager,
  getLegadoRuntimeAssetManager,
  LegadoRuntimeAssetFile,
  LegadoRuntimeAssetIndex,
  LegadoRuntimeActiveStatus,
  LegadoRuntimeSyncResult,
  LegadoRuntimeRepositoryUpdateStatus
} from './LegadoRuntimeAssetManager';

// 数据库
export { NOVEL_CREATE_TABLE_SQL, NOVEL_CREATE_INDEX_SQL } from 'manxia_novel/src/main/ets/Framework/Novel/NovelDatabaseSchema';
export { NovelDataManager, getNovelDataManager } from './NovelDataManager';

// 初始化器
export {
  NovelInitializer,
  getNovelInitializer,
  initializeNovelModule,
  initializeNovelModuleForStartup,
  NovelInitResult
} from './NovelInitializer';

// JS引擎
export { LegadoJsEngine, getLegadoJsEngine, JsExecuteResult, JsContext } from './LegadoJsEngine';

// 登录管理器
export { NovelLoginManager, getNovelLoginManager, LoginUiItem, LoginResult, SourceLoginStatus } from './NovelLoginManager';

// 替换规则管理器
export { NovelReplaceRuleManager, getNovelReplaceRuleManager, ReplaceRule, ReplaceScope, ReplaceRuleImportResult } from './NovelReplaceRuleManager';

// 书源校验器
export { NovelSourceValidator, getNovelSourceValidator, SourceValidationResult, BatchValidationResult, ValidationProgressCallback } from './NovelSourceValidator';

// Legado漫画桥接
export {
  LegadoMangaSourceBridge,
  getLegadoMangaSourceBridge,
  LegadoMangaVirtualSource,
  LegadoMangaDetailResult,
  LegadoMangaChapterResult,
  LegadoMangaPageResult,
  LegadoImageRequestContext
} from './LegadoMangaSourceBridge';
export { LegadoMangaImageExtractor } from 'manxia_novel/src/main/ets/Framework/Novel/LegadoMangaImageExtractor';
