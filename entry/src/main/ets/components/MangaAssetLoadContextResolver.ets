// 职责: 将页面与阅读上下文转换为 MangaAssetRequestContext，不执行加载和 UI 提交。

import {
  ImageSourceType,
  MangaChapter,
  MangaImageRequestHeader,
  MangaPage
} from '../Models/MangaModels';
import { RequestHeaderEntry, RequestHeaders } from '../Framework/Cache/ImageCacheManager';
import { MangaAssetRequestContext } from '../Framework/Reader/MangaAssetRequestFactory';
import { MangaAssetLoadReason } from '../Framework/Reader/MangaAssetTypes';
import { MangaPagePathResolver } from './MangaPagePathResolver';
import { WebtoonPageRef } from './MangaWebtoonTypes';

export class MangaAssetLoadContextInput {
  public chapter: MangaChapter | undefined = undefined;
  public webtoonPageRefById: Map<string, WebtoonPageRef> = new Map();
  public networkHeaders: RequestHeaders | undefined = undefined;
  public sourceId: number | undefined = undefined;
  public mangaId: string | undefined = undefined;
  public contentType: string | undefined = undefined;
  public screenWidth: number = 1080;
  public isWebtoonMode: boolean = false;
}

export class MangaAssetLoadContextResolver {
  private pagePathResolver: MangaPagePathResolver = new MangaPagePathResolver();

  public build(
    page: MangaPage,
    pageIndex: number,
    reason: MangaAssetLoadReason,
    input: MangaAssetLoadContextInput
  ): MangaAssetRequestContext {
    const pageRef: WebtoonPageRef | undefined = input.webtoonPageRefById.get(page.id);
    const chapterId: string = pageRef ? pageRef.chapterId : (input.chapter ? input.chapter.id : '');
    const chapterPageIndex: number = pageRef
      ? pageRef.chapterPageIndex
      : (page.index !== undefined ? page.index : pageIndex);

    const requestContext: MangaAssetRequestContext = new MangaAssetRequestContext();
    requestContext.chapterId = chapterId;
    requestContext.chapterPageIndex = chapterPageIndex;
    requestContext.imageUrl = this.resolveRequestImageUrl(page);
    requestContext.sourceId = input.sourceId;
    requestContext.mangaId = input.mangaId;
    requestContext.contentType = input.contentType;
    requestContext.headers = this.buildPageNetworkHeaders(page, input.networkHeaders);
    requestContext.localMaxWidth = input.screenWidth > 0 ? input.screenWidth : 1080;
    requestContext.reason = reason;
    requestContext.isWebtoonMode = input.isWebtoonMode;
    return requestContext;
  }

  private resolveRequestImageUrl(page: MangaPage): string {
    if (page.sourceType === ImageSourceType.LOCAL) {
      return this.pagePathResolver.getLocalFilePath(page) || page.imageUrl || '';
    }
    return page.imageUrl || '';
  }

  private buildPageNetworkHeaders(page: MangaPage, baseHeaders: RequestHeaders | undefined): RequestHeaders | undefined {
    const pageHeaders: MangaImageRequestHeader[] | undefined = page.requestHeaders;
    if (!baseHeaders && (!pageHeaders || pageHeaders.length === 0)) {
      return undefined;
    }

    const headers: RequestHeaders = this.cloneRequestHeaders(baseHeaders);
    if (pageHeaders && pageHeaders.length > 0) {
      let index: number = 0;
      while (index < pageHeaders.length) {
        const pageHeader: MangaImageRequestHeader = pageHeaders[index];
        if (pageHeader && pageHeader.name && pageHeader.value) {
          this.upsertExtraRequestHeader(headers, String(pageHeader.name), String(pageHeader.value));
        }
        index = index + 1;
      }
    }
    return headers;
  }

  private cloneRequestHeaders(headers: RequestHeaders | undefined): RequestHeaders {
    const cloned: RequestHeaders = {} as RequestHeaders;
    if (!headers) {
      return cloned;
    }
    cloned.userAgent = headers.userAgent;
    cloned.accept = headers.accept;
    cloned.referer = headers.referer;
    cloned.origin = headers.origin;
    cloned.cookie = headers.cookie;
    cloned.authorization = headers.authorization;
    cloned.acceptLanguage = headers.acceptLanguage;
    cloned.cacheControl = headers.cacheControl;
    cloned.pragma = headers.pragma;
    cloned.secFetchDest = headers.secFetchDest;
    cloned.secFetchMode = headers.secFetchMode;
    cloned.secFetchSite = headers.secFetchSite;
    cloned.cachePartition = headers.cachePartition;
    if (headers.extraHeaders && headers.extraHeaders.length > 0) {
      cloned.extraHeaders = [];
      for (let i = 0; i < headers.extraHeaders.length; i++) {
        const entry: RequestHeaderEntry = headers.extraHeaders[i];
        if (entry && entry.name && entry.value) {
          cloned.extraHeaders.push({
            name: entry.name,
            value: entry.value
          } as RequestHeaderEntry);
        }
      }
    }
    return cloned;
  }

  private upsertExtraRequestHeader(headers: RequestHeaders, headerName: string, headerValue: string): void {
    const normalizedName: string = headerName.trim();
    const normalizedValue: string = headerValue.trim();
    if (normalizedName.length === 0 || normalizedValue.length === 0) {
      return;
    }
    if (!headers.extraHeaders) {
      headers.extraHeaders = [];
    }
    let index: number = 0;
    while (index < headers.extraHeaders.length) {
      const entry: RequestHeaderEntry = headers.extraHeaders[index];
      if (entry.name.toLowerCase() === normalizedName.toLowerCase()) {
        entry.value = normalizedValue;
        return;
      }
      index = index + 1;
    }
    headers.extraHeaders.push({
      name: normalizedName,
      value: normalizedValue
    } as RequestHeaderEntry);
  }
}
