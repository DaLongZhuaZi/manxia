import { MangaPage } from '../../Models/MangaModels';
import { LoadOptions, RequestHeaders } from '../Cache/ImageCacheManager';
import { MangaAssetLoadReason, MangaAssetLoadRequest } from './MangaAssetTypes';

export class MangaAssetRequestContext {
  public chapterId: string = '';
  public chapterPageIndex: number = -1;
  public imageUrl: string = '';
  public sourceId: number | undefined = undefined;
  public mangaId: string | undefined = undefined;
  public contentType: string | undefined = undefined;
  public headers: RequestHeaders | undefined = undefined;
  public localMaxWidth: number = 1080;
  public reason: MangaAssetLoadReason = MangaAssetLoadReason.PRELOAD;
  public isWebtoonMode: boolean = false;
}

export class MangaAssetRequestFactory {
  public build(page: MangaPage, pageIndex: number, context: MangaAssetRequestContext): MangaAssetLoadRequest {
    const request: MangaAssetLoadRequest = new MangaAssetLoadRequest();
    const priority: number = page.priority || 1;

    request.pageId = page.id;
    request.chapterId = context.chapterId;
    request.pageIndex = pageIndex;
    request.imageUrl = context.imageUrl;
    request.sourceType = page.sourceType;
    request.localMaxWidth = context.localMaxWidth;
    request.priority = priority;
    request.reason = context.reason;
    request.isWebtoonMode = context.isWebtoonMode;
    request.loadOptions = {
      width: page.width,
      height: page.height,
      headers: context.headers,
      sourceId: context.sourceId,
      mangaId: context.mangaId,
      chapterId: context.chapterId,
      pageIndex: context.chapterPageIndex >= 0 ? context.chapterPageIndex : undefined,
      priority: priority,
      contentType: context.contentType,
      partitionKey: context.headers?.cachePartition
    } as LoadOptions;

    return request;
  }
}
