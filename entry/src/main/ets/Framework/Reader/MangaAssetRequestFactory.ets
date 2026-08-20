import { ImageSourceType, MangaPage } from 'manxia_core/src/main/ets/Models/MangaModels';
import { LoadOptions, RequestHeaders } from '../Cache/ImageCacheManager';
import {
  MangaAssetLoadReason,
  MangaAssetLoadRequest,
  MangaAssetRetryMode
} from './MangaAssetTypes';

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
  public retryMode: MangaAssetRetryMode = MangaAssetRetryMode.NONE;
  public priority: number | undefined = undefined;
  public sourceTypeOverride: ImageSourceType | undefined = undefined;
  public useLegadoV2ImageTransport: boolean = false;
  public legadoSourceRawSha256: string = '';
  public isWebtoonMode: boolean = false;
}

export class MangaAssetRequestFactory {
  public build(page: MangaPage, pageIndex: number, context: MangaAssetRequestContext): MangaAssetLoadRequest {
    const request: MangaAssetLoadRequest = new MangaAssetLoadRequest();
    const priority: number = context.priority !== undefined ? context.priority : (page.priority || 1);

    request.pageId = page.id;
    request.chapterId = context.chapterId;
    request.pageIndex = pageIndex;
    request.imageUrl = context.imageUrl;
    request.sourceType = context.sourceTypeOverride !== undefined ? context.sourceTypeOverride : page.sourceType;
    request.localMaxWidth = context.localMaxWidth;
    request.priority = priority;
    request.reason = context.reason;
    request.retryMode = context.retryMode;
    request.useLegadoV2ImageTransport = context.useLegadoV2ImageTransport;
    request.legadoSourceRawSha256 = context.legadoSourceRawSha256;
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

    if (context.retryMode === MangaAssetRetryMode.FORCE_REFRESH) {
      request.loadOptions.forceRefresh = true;
      request.loadOptions.skipFailureTtl = true;
    }

    return request;
  }
}
