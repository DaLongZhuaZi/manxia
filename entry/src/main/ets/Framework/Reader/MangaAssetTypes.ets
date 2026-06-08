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

export enum MangaAssetLoadSource {
  LOCAL_FILE = 'local_file',
  NETWORK = 'network',
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
  return `${request.chapterId}|${request.pageId}|${request.sourceType}|${request.imageUrl}|${partition}`;
}
