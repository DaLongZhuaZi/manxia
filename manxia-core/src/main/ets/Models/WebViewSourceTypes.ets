// 文件路径: manxia-core/src/main/ets/Models/WebViewSourceTypes.ets
/**
 * WebView 图源数据类型（下沉至 core 的共享类型定义）
 *
 * 背景：manxia_network 的 WebViewDataCacheManager 原先直接 import
 * manxia_source_engine 的 MangaInfo/ChapterInfo，构成"未声明依赖"（HAR→HAR 传递引用）。
 * 为实现 HSP 迁移 P0 的依赖解耦（见 docs/HSP_MIGRATION_PLAN.md §5 P0-2），
 * 将这两个纯类型接口下沉到 core 统一维护：
 * - manxia_source_engine/MangaSourceTypes 改为从本文件导入并重导出（保持原导入路径兼容）
 * - manxia_network/WebViewDataCacheManager 直接依赖本文件
 *
 * 注意：本文件为纯类型定义，字段与原 source_engine 定义逐字段一致，不得随意改动。
 */

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
