import { image } from '@kit.ImageKit';
import { logger } from '../../Utils/Logger';
import { ImageSourceType } from '../../Models/MangaModels';
import {
  ImageCacheManager,
  RequestHeaderEntry as ImageRequestHeaderEntry,
  RequestHeaders as ImageRequestHeaders
} from '../Cache/ImageCacheManager';
import {
  OnlineImageLoader,
  OnlineLoadOptions,
  RequestHeaderEntry as OnlineRequestHeaderEntry,
  RequestHeaders as OnlineRequestHeaders
} from '../Cache/OnlineImageLoader';
import { LocalImageCacheManager } from '../Cache/LocalImageCacheManager';
import {
  LegadoImageTransportTrace,
  LegadoImageTransportTraceContext
} from '../Network/LegadoImageTransportTrace';
import {
  getNetworkTransportFailureCoordinator,
  NetworkTransportFailureCoordinator
} from '../Network/NetworkTransportFailureCoordinator';
import {
  MangaAssetLoadReason,
  MangaAssetLoadRequest,
  MangaAssetLoadResult,
  MangaAssetLoadSource,
  MangaPixivImageLoader
} from './MangaAssetTypes';

const TAG = 'MangaAssetLoader';

export class MangaAssetLoader {
  private imageCacheManager: ImageCacheManager = ImageCacheManager.getInstance();
  private localImageCacheManager: LocalImageCacheManager = LocalImageCacheManager.getInstance();
  private pixivImageLoader: MangaPixivImageLoader | null = null;
  private transportFailureCoordinator: NetworkTransportFailureCoordinator =
    getNetworkTransportFailureCoordinator();

  public setPixivImageLoader(loader: MangaPixivImageLoader | null): void {
    this.pixivImageLoader = loader;
  }

  public async load(request: MangaAssetLoadRequest): Promise<MangaAssetLoadResult> {
    const startedAt: number = Date.now();
    const result: MangaAssetLoadResult = new MangaAssetLoadResult();
    result.requestKey = request.requestKey;
    result.pageId = request.pageId;
    result.chapterId = request.chapterId;
    result.pageIndex = request.pageIndex;

    try {
      if (!request.imageUrl || request.imageUrl.length <= 0) {
        result.errorMessage = '图片地址为空';
        return result;
      }

      if (request.sourceType === ImageSourceType.LOCAL) {
        await this.loadLocal(request, result);
        return result;
      }

      if (request.sourceType === ImageSourceType.NETWORK) {
        await this.loadNetwork(request, result);
        return result;
      }

      result.errorMessage = `暂不支持的图片源: ${request.sourceType}`;
      result.source = MangaAssetLoadSource.UNSUPPORTED;
      return result;
    } catch (error) {
      const message: string = error instanceof Error ? error.message : String(error);
      result.errorMessage = message;
      if (this.transportFailureCoordinator.isRecognizedFailureMessage(message)) {
        logger.warn(TAG, `漫画资产传输失败（已聚合）: page=${request.pageId}, error=${result.errorMessage}`);
      } else {
        logger.error(TAG, `漫画资产加载异常: page=${request.pageId}, error=${result.errorMessage}`);
      }
      return result;
    } finally {
      result.elapsedMs = Date.now() - startedAt;
    }
  }

  private async loadLocal(request: MangaAssetLoadRequest, result: MangaAssetLoadResult): Promise<void> {
    let pixelMap: image.PixelMap | null = await this.imageCacheManager.loadImage(
      request.imageUrl,
      request.loadOptions
    );

    if (!pixelMap) {
      logger.warn(TAG, `本地统一缓存未命中，回退本地降采样缓存: page=${request.pageId}`);
      pixelMap = await this.localImageCacheManager.loadImage(request.pageId, request.imageUrl, {
        maxWidth: request.localMaxWidth
      });
      if (pixelMap) {
        pixelMap = this.clonePixelMapIfPossible(pixelMap);
      }
    }

    if (pixelMap) {
      result.pixelMap = pixelMap;
      result.success = true;
      result.source = MangaAssetLoadSource.LOCAL_FILE;
      return;
    }

    result.errorMessage = '本地图片加载返回空';
    result.source = MangaAssetLoadSource.LOCAL_FILE;
  }

  private async loadNetwork(request: MangaAssetLoadRequest, result: MangaAssetLoadResult): Promise<void> {
    let pixelMap: image.PixelMap | null = null;
    if (this.isPixivCdn(request.imageUrl) && this.pixivImageLoader !== null) {
      pixelMap = await this.loadPixivThroughWebView(request);
      if (pixelMap) {
        result.source = MangaAssetLoadSource.PIXIV_WEBVIEW;
      }
    }

    if (!pixelMap) {
      if (request.useLegadoV2ImageTransport) {
        logger.info(
          TAG,
          `Legado V2 图片统一传输: page=${request.pageIndex}, reason=${request.reason}, headers=${this.describeHeaderNames(request.loadOptions.headers)}`
        );
        const v2Options: OnlineLoadOptions = await this.buildLegadoV2OnlineLoadOptions(request);
        const traceContext: LegadoImageTransportTraceContext | undefined = v2Options.legadoImageTrace;
        try {
          pixelMap = await OnlineImageLoader.getInstance().load(request.imageUrl, v2Options);
        } finally {
          if (traceContext !== undefined) {
            LegadoImageTransportTrace.recordPipelineResult(traceContext, pixelMap !== null);
          }
        }
        result.source = MangaAssetLoadSource.LEGADO_V2_TRANSPORT;
      } else {
        pixelMap = await this.imageCacheManager.loadImage(request.imageUrl, request.loadOptions);
        result.source = MangaAssetLoadSource.NETWORK;
      }
    }

    if (pixelMap) {
      result.pixelMap = pixelMap;
      result.success = true;
      return;
    }

    result.errorMessage = request.useLegadoV2ImageTransport
      ? 'V2 图片传输未产生可解码图像'
      : '网络图片加载返回空';
  }

  private async buildLegadoV2OnlineLoadOptions(request: MangaAssetLoadRequest): Promise<OnlineLoadOptions> {
    const options: OnlineLoadOptions = {} as OnlineLoadOptions;
    options.width = request.loadOptions.width;
    options.height = request.loadOptions.height;
    options.sourceId = request.loadOptions.sourceId;
    options.priority = request.priority;
    options.partitionKey = request.loadOptions.partitionKey;
    options.forceRefresh = request.loadOptions.forceRefresh;
    options.skipFailureTtl = request.loadOptions.skipFailureTtl;
    options.visibleLoad = request.reason === MangaAssetLoadReason.VISIBLE ||
      request.reason === MangaAssetLoadReason.WEBTOON ||
      request.reason === MangaAssetLoadReason.RETRY;
    options.prefetch = request.reason === MangaAssetLoadReason.PRELOAD ||
      request.reason === MangaAssetLoadReason.NEIGHBOR;
    const headers: OnlineRequestHeaders | undefined = this.convertToOnlineHeaders(request.loadOptions.headers);
    if (headers !== undefined) {
      options.headers = headers;
    }
    options.legadoImageTrace = await LegadoImageTransportTrace.createContext(
      request.legadoSourceRawSha256,
      request.loadOptions.sourceId || 0,
      request.pageIndex,
      request.imageUrl
    );
    return options;
  }

  private convertToOnlineHeaders(headers: ImageRequestHeaders | undefined): OnlineRequestHeaders | undefined {
    if (!headers) {
      return undefined;
    }
    const target: OnlineRequestHeaders = {} as OnlineRequestHeaders;
    target.userAgent = headers.userAgent;
    target.accept = headers.accept;
    target.referer = headers.referer;
    target.origin = headers.origin;
    target.cookie = headers.cookie;
    target.authorization = headers.authorization;
    target.acceptLanguage = headers.acceptLanguage;
    target.cacheControl = headers.cacheControl;
    target.pragma = headers.pragma;
    target.secFetchDest = headers.secFetchDest;
    target.secFetchMode = headers.secFetchMode;
    target.secFetchSite = headers.secFetchSite;
    target.cachePartition = headers.cachePartition;
    if (headers.extraHeaders && headers.extraHeaders.length > 0) {
      const extraHeaders: OnlineRequestHeaderEntry[] = [];
      for (let index = 0; index < headers.extraHeaders.length; index++) {
        const entry: ImageRequestHeaderEntry = headers.extraHeaders[index];
        if (entry && entry.name && entry.value) {
          extraHeaders.push({
            name: entry.name,
            value: entry.value
          } as OnlineRequestHeaderEntry);
        }
      }
      if (extraHeaders.length > 0) {
        target.extraHeaders = extraHeaders;
      }
    }
    return target;
  }

  private describeHeaderNames(headers: ImageRequestHeaders | undefined): string {
    if (!headers) {
      return 'none';
    }
    const names: string[] = [];
    if (headers.userAgent) {
      names.push('ua');
    }
    if (headers.referer) {
      names.push('referer');
    }
    if (headers.origin) {
      names.push('origin');
    }
    if (headers.cookie) {
      names.push('cookie');
    }
    if (headers.extraHeaders && headers.extraHeaders.length > 0) {
      names.push(`extra:${headers.extraHeaders.length}`);
    }
    return names.length > 0 ? names.join('|') : 'none';
  }

  private async loadPixivThroughWebView(request: MangaAssetLoadRequest): Promise<image.PixelMap | null> {
    if (this.pixivImageLoader === null) {
      return null;
    }

    const buffer: ArrayBuffer | null = await this.pixivImageLoader(request.imageUrl);
    if (!buffer || buffer.byteLength <= 0) {
      return null;
    }

    const imageSource: image.ImageSource = image.createImageSource(buffer);
    const decodingOptions: image.DecodingOptions = {
      desiredSize: request.loadOptions.width && request.loadOptions.height
        ? { width: request.loadOptions.width, height: request.loadOptions.height }
        : undefined,
      desiredPixelFormat: image.PixelMapFormat.RGBA_8888
    };
    return await imageSource.createPixelMap(decodingOptions);
  }

  private isPixivCdn(url: string): boolean {
    return url.includes('i.pximg.net') || url.includes('.pximg.net');
  }

  private clonePixelMapIfPossible(pixelMap: image.PixelMap): image.PixelMap {
    try {
      return pixelMap.cloneSync();
    } catch (error) {
      const message: string = error instanceof Error ? error.message : String(error);
      logger.warn(TAG, `PixelMap克隆失败，沿用原对象: ${message}`);
      return pixelMap;
    }
  }
}
