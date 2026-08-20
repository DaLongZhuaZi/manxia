// 文件路径: entry/src/main/ets/Framework/Scraper/ScraperTypes.ets
/**
 * 刮削管理器类型定义
 */

/**
 * 刮削源类型
 */
export enum ScraperSource {
  BANGUMI = 'bangumi',
  ANILIST = 'anilist',
  BOOKOF_MOE = 'bookof_moe',
  GOOGLE_BOOKS = 'google_books'
}

/**
 * 内容类型
 */
export enum ScraperContentType {
  MANGA = 'manga',
  ANIME = 'anime',
  BOOK = 'book',
  GAME = 'game'
}

/**
 * 刮削请求配置
 */
export interface ScraperRequestConfig {
  source: ScraperSource;
  contentType?: ScraperContentType;
  accessToken?: string;
  timeout?: number;
  headers?: Record<string, string>;
}

/**
 * 统一的刮削结果 - 标准化格式
 */
export interface ScrapedMetadata {
  // 基础信息
  id: string;
  source: ScraperSource;
  externalId: string;
  title: string;
  titleNative?: string;
  titleRomaji?: string;
  titleEnglish?: string;
  alternativeTitles?: string[];
  
  // 描述
  description?: string;
  summary?: string;
  
  // 封面图
  coverUrl?: string;
  coverUrlLarge?: string;
  coverUrlMedium?: string;
  coverUrlSmall?: string;
  
  // 创作者信息
  author?: string;
  authors?: string[];
  artist?: string;
  artists?: string[];
  publisher?: string;
  
  // 分类信息
  genres?: string[];
  tags?: string[];
  themes?: string[];
  
  // 评分信息
  score?: number;
  scoreMax?: number;
  ratingCount?: number;
  rank?: number;
  popularity?: number;
  
  // 状态信息
  status?: string;
  releaseDate?: string;
  endDate?: string;
  volumes?: number;
  chapters?: number;
  
  // 原始数据（用于调试或扩展）
  rawData?: Object;
}

/**
 * 搜索结果
 */
export interface ScraperSearchResult {
  success: boolean;
  source: ScraperSource;
  results: ScrapedMetadata[];
  totalCount?: number;
  errorMessage?: string;
}

/**
 * 详情结果
 */
export interface ScraperDetailResult {
  success: boolean;
  source: ScraperSource;
  data?: ScrapedMetadata;
  errorMessage?: string;
}

/**
 * Bangumi API 响应类型
 */
export interface BangumiSubject {
  id: number;
  type: number;
  name: string;
  name_cn?: string;
  summary?: string;
  nsfw?: boolean;
  locked?: boolean;
  date?: string;
  platform?: string;
  images?: BangumiImages;
  infobox?: BangumiInfoboxItem[];
  volumes?: number;
  eps?: number;
  total_episodes?: number;
  rating?: BangumiRating;
  collection?: BangumiCollection;
  tags?: BangumiTag[];
  rank?: number;
}

export interface BangumiImages {
  large?: string;
  common?: string;
  medium?: string;
  small?: string;
  grid?: string;
}

export interface BangumiRating {
  rank?: number;
  total?: number;
  count?: Record<string, number>;
  score?: number;
}

export interface BangumiCollection {
  wish?: number;
  collect?: number;
  doing?: number;
  on_hold?: number;
  dropped?: number;
}

export interface BangumiTag {
  name: string;
  count: number;
}

export interface BangumiInfoboxItem {
  key: string;
  value: string | BangumiInfoboxValue[];
}

export interface BangumiInfoboxValue {
  k?: string;
  v: string;
}

export interface BangumiSearchResult {
  total: number;
  limit: number;
  offset: number;
  data: BangumiSubject[];
}

/**
 * AniList API 响应类型
 */
export interface AniListMedia {
  id: number;
  idMal?: number;
  title?: AniListTitle;
  type?: string;
  format?: string;
  status?: string;
  description?: string;
  startDate?: AniListDate;
  endDate?: AniListDate;
  chapters?: number;
  volumes?: number;
  countryOfOrigin?: string;
  isLicensed?: boolean;
  source?: string;
  coverImage?: AniListCoverImage;
  bannerImage?: string;
  genres?: string[];
  synonyms?: string[];
  averageScore?: number;
  meanScore?: number;
  popularity?: number;
  trending?: number;
  favourites?: number;
  tags?: AniListTag[];
  staff?: AniListStaffConnection;
  siteUrl?: string;
}

export interface AniListTitle {
  romaji?: string;
  english?: string;
  native?: string;
  userPreferred?: string;
}

export interface AniListDate {
  year?: number;
  month?: number;
  day?: number;
}

export interface AniListCoverImage {
  extraLarge?: string;
  large?: string;
  medium?: string;
  color?: string;
}

export interface AniListTag {
  id: number;
  name: string;
  description?: string;
  category?: string;
  rank?: number;
  isGeneralSpoiler?: boolean;
  isMediaSpoiler?: boolean;
  isAdult?: boolean;
}

export interface AniListStaffConnection {
  edges?: AniListStaffEdge[];
}

export interface AniListStaffEdge {
  role?: string;
  node?: AniListStaff;
}

export interface AniListStaff {
  id: number;
  name?: AniListStaffName;
}

export interface AniListStaffName {
  first?: string;
  middle?: string;
  last?: string;
  full?: string;
  native?: string;
}

export interface AniListPageInfo {
  total?: number;
  currentPage?: number;
  lastPage?: number;
  hasNextPage?: boolean;
  perPage?: number;
}

export interface AniListPageData {
  pageInfo?: AniListPageInfo;
  media?: AniListMedia[];
}

export interface AniListResponseData {
  Media?: AniListMedia;
  Page?: AniListPageData;
}

export interface AniListResponse {
  data?: AniListResponseData;
  errors?: AniListError[];
}

export interface AniListErrorLocation {
  line: number;
  column: number;
}

export interface AniListError {
  message: string;
  status?: number;
  locations?: AniListErrorLocation[];
}

/**
 * BookOf.Moe API 响应类型
 */
export interface BookOfMoeBook {
  id?: string;
  title?: string;
  author?: string;
  publisher?: string;
  description?: string;
  cover?: string;
  isbn?: string;
  tags?: string[];
  rating?: number;
  publishDate?: string;
}

export interface BookOfMoeSearchResult {
  success: boolean;
  data?: BookOfMoeBook[];
  error?: string;
}

/**
 * Google Books API 响应类型
 */
export interface GoogleBooksSearchResponse {
  kind: string;
  totalItems: number;
  items?: GoogleBooksVolume[];
}

export interface GoogleBooksVolume {
  kind: string;
  id: string;
  etag: string;
  selfLink: string;
  volumeInfo: GoogleBooksVolumeInfo;
  saleInfo?: GoogleBooksSaleInfo;
  accessInfo?: GoogleBooksAccessInfo;
}

export interface GoogleBooksVolumeInfo {
  title: string;
  subtitle?: string;
  authors?: string[];
  publisher?: string;
  publishedDate?: string;
  description?: string;
  industryIdentifiers?: GoogleBooksIdentifier[];
  pageCount?: number;
  categories?: string[];
  averageRating?: number;
  ratingsCount?: number;
  imageLinks?: GoogleBooksImageLinks;
  language?: string;
  previewLink?: string;
  infoLink?: string;
}

export interface GoogleBooksIdentifier {
  type: string;
  identifier: string;
}

export interface GoogleBooksImageLinks {
  smallThumbnail?: string;
  thumbnail?: string;
  small?: string;
  medium?: string;
  large?: string;
  extraLarge?: string;
}

export interface GoogleBooksSaleInfo {
  country?: string;
  saleability?: string;
  isEbook?: boolean;
}

export interface GoogleBooksAccessInfo {
  country?: string;
  viewability?: string;
  embeddable?: boolean;
  publicDomain?: boolean;
}
