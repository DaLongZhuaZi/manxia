import { image } from '@kit.ImageKit';
import { logger } from '../../Utils/Logger';
import { ImageSourceType } from '../../Models/MangaModels';
import { ImageCacheManager } from '../Cache/ImageCacheManager';
import { LocalImageCacheManager } from '../Cache/LocalImageCacheManager';
import {
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
      logger.error(TAG, `漫画资产加载异常: page=${request.pageId}, error=${result.errorMessage}`);
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
      pixelMap = await this.imageCacheManager.loadImage(request.imageUrl, request.loadOptions);
      result.source = MangaAssetLoadSource.NETWORK;
    }

    if (pixelMap) {
      result.pixelMap = pixelMap;
      result.success = true;
      return;
    }

    result.errorMessage = '网络图片加载返回空';
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
