import { image } from '@kit.ImageKit';
import { ImageSourceType } from '../../Models/MangaModels';
import { LoadOptions } from '../Cache/ImageCacheManager';

export enum MangaAssetLoadReason {
  VISIBLE = 'visible',
  NEIGHBOR = 'neighbor',
  PRELOAD = 'preload',
  RETRY = 'retry',
  WEBTOON = 'webtoon'
}

export enum MangaAssetRetryMode {
  NONE = 'none',
  CACHE_FIRST = 'cache_first',
  FORCE_REFRESH = 'force_refresh'
}

export enum MangaAssetLoadSource {
  LOCAL_FILE = 'local_file',
  NETWORK = 'network',
  LEGADO_V2_TRANSPORT = 'legado_v2_transport',
  PIXIV_WEBVIEW = 'pixiv_webview',
  CACHE = 'cache',
  UNSUPPORTED = 'unsupported'
}

export class MangaAssetLoadRequest {
  public requestKey: string = '';
  public pageId: string = '';
  public chapterId: string = '';
  public pageIndex: number = -1;
  public imageUrl: string = '';
  public sourceType: ImageSourceType = ImageSourceType.NETWORK;
  public loadOptions: LoadOptions = {} as LoadOptions;
  public localMaxWidth: number = 1080;
  public priority: number = 1;
  public reason: MangaAssetLoadReason = MangaAssetLoadReason.PRELOAD;
  public retryMode: MangaAssetRetryMode = MangaAssetRetryMode.NONE;
  /**
   * Legado IMAGE sources must use the V2 image transport rather than the
   * generic image-cache network branch, whose error contract is lossy.
   */
  public useLegadoV2ImageTransport: boolean = false;
  /** Raw V2 source document identity used only by redacted conformance traces. */
  public legadoSourceRawSha256: string = '';
  public isWebtoonMode: boolean = false;
}

export class MangaAssetLoadResult {
  public requestKey: string = '';
  public pageId: string = '';
  public chapterId: string = '';
  public pageIndex: number = -1;
  public success: boolean = false;
  public source: MangaAssetLoadSource = MangaAssetLoadSource.UNSUPPORTED;
  public pixelMap: image.PixelMap | null = null;
  public errorMessage: string = '';
  public elapsedMs: number = 0;
}

export type MangaPixivImageLoader = (imageUrl: string) => Promise<ArrayBuffer | null>;

export function buildMangaAssetRequestKey(request: MangaAssetLoadRequest): string {
  const partition: string = request.loadOptions.partitionKey ? request.loadOptions.partitionKey : '';
  return `${request.chapterId}|${request.pageId}|${request.sourceType}|${request.imageUrl}|${partition}|${request.retryMode}`;
}
