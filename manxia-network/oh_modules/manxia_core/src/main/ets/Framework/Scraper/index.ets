// 文件路径: entry/src/main/ets/Framework/Scraper/index.ets
/**
 * 刮削模块导出
 */

// 类型定义
export {
  ScraperSource,
  ScraperContentType,
  ScrapedMetadata,
  ScraperSearchResult,
  ScraperDetailResult,
  ScraperRequestConfig,
  BangumiSubject,
  BangumiImages,
  BangumiRating,
  BangumiSearchResult,
  AniListMedia,
  AniListTitle,
  AniListCoverImage,
  AniListResponse,
  BookOfMoeBook,
  BookOfMoeSearchResult
} from './ScraperTypes';

// Bangumi 刮削器
export {
  BangumiScraper,
  BangumiSubjectType,
  BangumiScraperConfig
} from './BangumiScraper';

// AniList 刮削器
export {
  AniListScraper,
  AniListMediaType,
  AniListScraperConfig
} from './AniListScraper';

// BookOf.Moe 刮削器
export {
  BookOfMoeScraper,
  BookOfMoeScraperConfig
} from './BookOfMoeScraper';

// 刮削管理器
export {
  ScraperManager,
  ScraperManagerConfig,
  MultiSourceSearchResult,
  getScraperManager
} from './ScraperManager';
