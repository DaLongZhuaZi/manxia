import { image } from '@kit.ImageKit';
import { http } from '@kit.NetworkKit';
import { logger } from '../Utils/Logger';
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

  private getHeaders(): Record<string, string> {
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
    this.effectiveSrc = this.resolveImageUrl(this.src) || this.src;
    this.isLoading = true;
    this.loadError = false;
    this.useDirectImage = false;
    this.releasePixelMap();
    this.loadingAborted = false;

    try {
      if (!this.effectiveSrc.startsWith('http://') && !this.effectiveSrc.startsWith('https://')) {
        this.useDirectImage = true;
        return;
      }

      const headers = this.getHeaders();
      if (Object.keys(headers).length <= 0) {
        this.useDirectImage = true;
        return;
      }

      const buffer = await this.downloadImage(this.effectiveSrc, headers);
      if (!buffer) {
        throw new Error('下载图片失败');
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
      logger.error(TAG, `加载 Komga 图片失败: ${String(error)}`);
      this.loadError = true;
      this.useDirectImage = true;
    } finally {
      this.isLoading = false;
    }
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
