import { image } from '@kit.ImageKit';
import { http } from '@kit.NetworkKit';
import fs from '@ohos.file.fs';
import { logger } from '../Utils/Logger';
import KomgaCacheManager from '../Framework/Source/KomgaCacheManager';
import { getKomgaSourceExecutor } from '../Framework/Source/KomgaSourceExecutor';

const TAG = 'KomgaImage';

@Component
export struct KomgaImage {
  @Prop @Watch('onSrcChange') src: string = '';
  @Prop imageWidth: Length = '100%';
  @Prop imageHeight: Length = '100%';
  @Prop objectFit: ImageFit = ImageFit.Cover;
  @Prop imgBorderRadius: Length = 0;
  @Prop placeholderColor: ResourceColor = '#2A2A2A';
  @Prop requestHeaders: Record<string, string> = {};
  @Prop cacheKey: string = '';

  @State private pixelMap: image.PixelMap | null = null;
  @State private isLoading: boolean = false;
  @State private loadError: boolean = false;
  @State private useDirectImage: boolean = false;

  private currentSrc: string = '';
  private effectiveSrc: string = '';
  private loadingAborted: boolean = false;

  aboutToAppear(): void {
    if (this.src.length > 0) {
      void this.loadImage();
    }
  }

  aboutToDisappear(): void {
    this.loadingAborted = true;
    this.releasePixelMap();
    this.currentSrc = '';
    this.effectiveSrc = '';
    this.useDirectImage = false;
    this.loadError = false;
  }

  onSrcChange(): void {
    if (this.src.length > 0 && this.src !== this.currentSrc) {
      void this.loadImage();
    }
  }

  private previewUrl(url: string): string {
    if (url.length <= 96) {
      return url;
    }
    return `${url.substring(0, 96)}...`;
  }

  private getHeaders(): Record<string, string> {
    if (Object.keys(this.requestHeaders).length > 0) {
      return this.requestHeaders;
    }
    try {
      return getKomgaSourceExecutor().getImageHeaders();
    } catch (_error) {
      return {};
    }
  }

  private getNormalizedServerUrl(): string {
    try {
      const raw = (getKomgaSourceExecutor().getServerUrl() || '').trim();
      if (raw.length <= 0) {
        return '';
      }
      const hasScheme = /^[a-zA-Z][a-zA-Z0-9+\-.]*:\/\//.test(raw);
      const normalized = hasScheme ? raw : `http://${raw}`;
      return normalized.endsWith('/') ? normalized.substring(0, normalized.length - 1) : normalized;
    } catch (_error) {
      return '';
    }
  }

  private isHostLikeUrlWithoutScheme(url: string): boolean {
    const slashIndex = url.indexOf('/');
    const hostPart = slashIndex >= 0 ? url.substring(0, slashIndex) : url;
    const pathPart = slashIndex >= 0 ? url.substring(slashIndex) : '';
    if (!hostPart) {
      return false;
    }
    const isIpv4Host = /^\d{1,3}(?:\.\d{1,3}){3}(?::\d+)?$/.test(hostPart);
    const isNamedHost = /^(localhost|[a-zA-Z0-9-]+(?:\.[a-zA-Z0-9-]+)+)(?::\d+)?$/.test(hostPart);
    return (isIpv4Host || isNamedHost) && (hostPart.includes(':') || pathPart.startsWith('/'));
  }

  private resolveImageUrl(rawUrl: string): string {
    const url = rawUrl.trim();
    if (url.length <= 0) {
      return '';
    }
    if (url.includes('://') || url.startsWith('data:') || url.startsWith('file:')) {
      return url;
    }

    const serverUrl = this.getNormalizedServerUrl();
    const protocol = serverUrl.startsWith('https://') ? 'https:' : 'http:';
    if (url.startsWith('//')) {
      return `${protocol}${url}`;
    }
    if (this.isHostLikeUrlWithoutScheme(url)) {
      return `${protocol}//${url}`;
    }
    if (serverUrl.length <= 0) {
      return url;
    }
    if (url.startsWith('/')) {
      return `${serverUrl}${url}`;
    }
    return `${serverUrl}/${url}`;
  }

  private isHttpImageUrl(url: string): boolean {
    return url.startsWith('http://') || url.startsWith('https://');
  }

  private isLocalFileSource(url: string): boolean {
    return url.startsWith('file://') || url.startsWith('/');
  }

  private normalizeLocalFilePath(url: string): string {
    const trimmed = url.trim();
    if (trimmed.startsWith('file://')) {
      return trimmed.substring('file://'.length);
    }
    return trimmed;
  }

  private async decodeLocalFileToPixelMap(url: string): Promise<image.PixelMap | null> {
    if (!this.isLocalFileSource(url)) {
      return null;
    }

    const normalizedPath = this.normalizeLocalFilePath(url);
    if (!normalizedPath.startsWith('/')) {
      return null;
    }

    let file: fs.File | null = null;
    let imageSource: image.ImageSource | null = null;
    try {
      if (!fs.accessSync(normalizedPath)) {
        return null;
      }
      const stat = fs.statSync(normalizedPath);
      if (stat.isDirectory() || stat.size <= 0) {
        return null;
      }
      file = fs.openSync(normalizedPath, fs.OpenMode.READ_ONLY);
      imageSource = image.createImageSource(file.fd);
      return await imageSource.createPixelMap({
        desiredPixelFormat: image.PixelMapFormat.RGBA_8888
      });
    } catch (error) {
      logger.debug(TAG, `KomgaImage local decode skipped: path=${this.previewUrl(normalizedPath)}, error=${String(error)}`);
      return null;
    } finally {
      try {
        imageSource?.release();
      } catch (_error) {
      }
      try {
        if (file !== null) {
          fs.closeSync(file);
        }
      } catch (_error) {
      }
    }
  }

  private releasePixelMap(): void {
    if (!this.pixelMap) {
      return;
    }
    try {
      this.pixelMap.release();
    } catch (_error) {
    }
    this.pixelMap = null;
  }

  private async loadImage(): Promise<void> {
    if (this.src.length <= 0 || this.isLoading) {
      return;
    }
    if (this.src === this.currentSrc && (this.pixelMap !== null || this.useDirectImage)) {
      return;
    }

    this.currentSrc = this.src;
    const resolvedSrc = this.resolveImageUrl(this.src) || this.src;
    this.effectiveSrc = resolvedSrc;
    this.isLoading = true;
    this.loadError = false;
    this.useDirectImage = false;
    this.releasePixelMap();
    this.loadingAborted = false;

    try {
      if (!this.isHttpImageUrl(resolvedSrc)) {
        const localPixelMap = await this.decodeLocalFileToPixelMap(resolvedSrc);
        if (this.loadingAborted) {
          localPixelMap?.release();
          return;
        }
        if (localPixelMap !== null) {
          this.pixelMap = localPixelMap;
          logger.debug(TAG, `KomgaImage local cover decoded: ${this.previewUrl(resolvedSrc)}`);
          return;
        }
        logger.debug(TAG, `KomgaImage fallback to direct local source: ${this.previewUrl(resolvedSrc)}`);
        this.useDirectImage = true;
        return;
      }

      const headers = this.getHeaders();
      const cachedFileUrl = await this.resolveCachedFileUrl(resolvedSrc, headers);
      if (this.loadingAborted) {
        return;
      }
      if (cachedFileUrl.length > 0) {
        const cachedPixelMap = await this.decodeLocalFileToPixelMap(cachedFileUrl);
        if (this.loadingAborted) {
          cachedPixelMap?.release();
          return;
        }
        if (cachedPixelMap !== null) {
          this.pixelMap = cachedPixelMap;
          logger.debug(TAG, `KomgaImage cached cover decoded: ${this.previewUrl(cachedFileUrl)}`);
          return;
        }
        logger.debug(TAG, `KomgaImage cached file unavailable, retry remote source: ${this.previewUrl(cachedFileUrl)}`);
      }

      if (Object.keys(headers).length <= 0) {
        this.effectiveSrc = resolvedSrc;
        logger.debug(TAG, `KomgaImage fallback to direct remote source: ${this.previewUrl(resolvedSrc)}`);
        this.useDirectImage = true;
        return;
      }

      this.effectiveSrc = resolvedSrc;
      const buffer = await this.downloadImage(resolvedSrc, headers);
      if (!buffer) {
        throw new Error('Failed to download Komga image');
      }
      if (this.loadingAborted) {
        return;
      }

      const imageSource = image.createImageSource(buffer);
      const pixelMap = await imageSource.createPixelMap();
      imageSource.release();
      if (this.loadingAborted) {
        pixelMap.release();
        return;
      }
      this.pixelMap = pixelMap;
    } catch (error) {
      logger.error(TAG, `Failed to load Komga image: ${String(error)}`);
      this.loadError = true;
      this.useDirectImage = true;
    } finally {
      this.isLoading = false;
    }
  }

  private async resolveCachedFileUrl(url: string, headers: Record<string, string>): Promise<string> {
    if (this.cacheKey.length <= 0) {
      return '';
    }
    const cachedPath = KomgaCacheManager.getCachedCoverPath(this.cacheKey, url);
    if (cachedPath !== null && cachedPath.length > 0) {
      logger.debug(TAG, `KomgaImage cache hit: cacheKey=${this.cacheKey}`);
      return `file://${cachedPath}`;
    }
    logger.debug(TAG, `KomgaImage cache miss, downloading cover: cacheKey=${this.cacheKey}`);
    const downloadedPath = await KomgaCacheManager.cacheCover(this.cacheKey, url, headers);
    if (downloadedPath !== null && downloadedPath.length > 0) {
      logger.debug(TAG, `KomgaImage cache write complete: cacheKey=${this.cacheKey}`);
      return `file://${downloadedPath}`;
    }
    return '';
  }

  private async downloadImage(url: string, headers: Record<string, string>): Promise<ArrayBuffer | null> {
    const request = http.createHttp();
    try {
      const response = await request.request(url, {
        method: http.RequestMethod.GET,
        expectDataType: http.HttpDataType.ARRAY_BUFFER,
        connectTimeout: 30000,
        readTimeout: 60000,
        header: headers
      });
      if (response.responseCode >= 200 && response.responseCode < 300 && response.result) {
        return response.result as ArrayBuffer;
      }
      return null;
    } catch (_error) {
      return null;
    } finally {
      request.destroy();
    }
  }

  build() {
    Stack() {
      if (this.pixelMap) {
        Image(this.pixelMap)
          .width(this.imageWidth)
          .height(this.imageHeight)
          .objectFit(this.objectFit)
          .borderRadius(this.imgBorderRadius)
      } else if (this.useDirectImage && this.effectiveSrc.length > 0) {
        Image(this.effectiveSrc)
          .width(this.imageWidth)
          .height(this.imageHeight)
          .objectFit(this.objectFit)
          .borderRadius(this.imgBorderRadius)
          .onError(() => {
            logger.warn(TAG, `KomgaImage direct render failed: ${this.previewUrl(this.effectiveSrc)}`);
            this.useDirectImage = false;
            this.loadError = true;
          })
      } else {
        Column({ space: 8 }) {
          if (this.isLoading) {
            LoadingProgress()
              .width(28)
              .height(28)
          } else if (this.loadError) {
            Text('加载失败')
              .fontSize(12)
              .fontColor('#A0A0A0')
          }
        }
        .width(this.imageWidth)
        .height(this.imageHeight)
        .justifyContent(FlexAlign.Center)
        .backgroundColor(this.placeholderColor)
        .borderRadius(this.imgBorderRadius)
      }
    }
  }
}
