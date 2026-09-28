/** 图片请求头契约（M34：从 entry ImageCacheManager 下沉）。CookieManager 与缓存层共用。 */

export interface RequestHeaderEntry {
  name: string;
  value: string;
}

export interface RequestHeaders {
  userAgent?: string;
  accept?: string;
  referer?: string;
  origin?: string;
  cookie?: string;
  authorization?: string;
  acceptLanguage?: string;
  cacheControl?: string;
  pragma?: string;
  secFetchDest?: string;
  secFetchMode?: string;
  secFetchSite?: string;
  cachePartition?: string;
  extraHeaders?: RequestHeaderEntry[];
}
