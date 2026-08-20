// 职责: 将页面与阅读上下文转换为 MangaAssetRequestContext，不执行加载和 UI 提交。

import {
  ImageSourceType,
  MangaChapter,
  MangaImageRequestHeader,
  MangaPage
} from 'manxia_core/src/main/ets/Models/MangaModels';
import { RequestHeaders } from '../Framework/Cache/ImageCacheManager';
import { MangaAssetRequestContext } from '../Framework/Reader/MangaAssetRequestFactory';
import { MangaAssetLoadReason } from '../Framework/Reader/MangaAssetTypes';
import { MangaRequestHeaderContract } from '../Framework/Reader/MangaRequestHeaderContract';
import { MangaPagePathResolver } from './MangaPagePathResolver';
import { WebtoonPageRef } from './MangaWebtoonTypes';

export class MangaAssetLoadContextInput {
  public chapter: MangaChapter | undefined = undefined;
  public webtoonPageRefById: Map<string, WebtoonPageRef> = new Map();
  public networkHeaders: RequestHeaders | undefined = undefined;
  public sourceId: number | undefined = undefined;
  public mangaId: string | undefined = undefined;
  public contentType: string | undefined = undefined;
  public useLegadoV2ImageTransport: boolean = false;
  public legadoSourceRawSha256: string = '';
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
    requestContext.useLegadoV2ImageTransport = input.useLegadoV2ImageTransport;
    requestContext.legadoSourceRawSha256 = input.legadoSourceRawSha256;
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

    const headers: RequestHeaders = MangaRequestHeaderContract.clone(baseHeaders);
    if (pageHeaders && pageHeaders.length > 0) {
      let index: number = 0;
      while (index < pageHeaders.length) {
        const pageHeader: MangaImageRequestHeader = pageHeaders[index];
        if (pageHeader && pageHeader.name && pageHeader.value) {
          MangaRequestHeaderContract.apply(headers, String(pageHeader.name), String(pageHeader.value));
        }
        index = index + 1;
      }
    }
    return headers;
  }

}
