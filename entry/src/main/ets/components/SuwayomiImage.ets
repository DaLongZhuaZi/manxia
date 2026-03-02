/**
 * Suwayomi 图片组件
 * 支持 AVIF 格式和认证头的图片加载组件
 * 可在所有 Suwayomi 相关页面中复用
 */

import { image } from '@kit.ImageKit';
import { http } from '@kit.NetworkKit';
import { logger } from '../Utils/Logger';
import { AvifDecoder, isAvifFormat } from '../Framework/Image/AvifDecoder';
import { getSuwayomiSourceExecutor } from '../Framework/Source/SuwayomiSourceExecutor';

const TAG = 'SuwayomiImage';

@Component
export struct SuwayomiImage {
  @Prop @Watch('onSrcChange') src: string = '';
  @Prop imageWidth: Length = '100%';
  @Prop imageHeight: Length = '100%';
  @Prop imgAspectRatio: number = 0; // 0 表示不使用宽高比
  @Prop objectFit: ImageFit = ImageFit.Cover;
  @Prop imgBorderRadius: Length = 0;
  @Prop placeholderColor: ResourceColor = '#333333';

  @State private pixelMap: image.PixelMap | null = null;
  @State private isLoading: boolean = false;
  @State private loadError: boolean = false;
  @State private useDirectImage: boolean = false;

  private currentSrc: string = '';
  private effectiveSrc: string = '';
  private loadingAborted: boolean = false;

  private resolveErrorText(error: Object | string | number | boolean | null | undefined): string {
    if (error === undefined || error === null) {
      return '未知错误';
    }
    if (typeof error === 'string' || typeof error === 'number' || typeof error === 'boolean') {
      return String(error);
    }
    if (error instanceof Error) {
      const message = error.message ? error.message.trim() : '';
      if (message.length > 0) {
        return message;
      }
    }
    const objectError = error as Object;
    const messageValue = (objectError as Record<string, Object>)['message'];
    if (messageValue !== undefined && messageValue !== null) {
      const messageText = String(messageValue).trim();
      if (messageText.length > 0 && messageText !== '[object Object]') {
        return messageText;
      }
    }
    const codeValue = (objectError as Record<string, Object>)['code'];
    if (codeValue !== undefined && codeValue !== null) {
      return `错误码 ${String(codeValue)}`;
    }
    try {
      const jsonText = JSON.stringify(objectError);
      if (jsonText && jsonText.length > 0 && jsonText !== '{}') {
        return jsonText;
      }
    } catch (_error) {
    }
    return String(error);
  }

  private previewUrl(url: string): string {
    if (!url) {
      return '';
    }
    return url.length > 120 ? `${url.substring(0, 120)}...` : url;
  }

  private getAuthorizationHeader(): string {
    try {
      const executor = getSuwayomiSourceExecutor();
      const authHeaders = executor.getImageHeaders();
      return authHeaders['Authorization'] || '';
    } catch (_error) {
      return '';
    }
  }

  private getNormalizedServerUrl(): string {
    try {
      const executor = getSuwayomiSourceExecutor();
      const serverUrlRaw = (executor.getServerUrl() || '').trim();
      if (!serverUrlRaw) {
        return '';
      }
      const hasScheme = /^[a-zA-Z][a-zA-Z0-9+\-.]*:\/\//.test(serverUrlRaw);
      const normalized = hasScheme ? serverUrlRaw : `http://${serverUrlRaw}`;
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
    if (!isIpv4Host && !isNamedHost) {
      return false;
    }

    return hostPart.includes(':') || pathPart.startsWith('/');
  }

  private resolveImageUrl(rawUrl: string): string {
    const url = (rawUrl || '').trim();
    if (!url) {
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

    if (!serverUrl) {
      return url;
    }

    if (url.startsWith('/')) {
      return `${serverUrl}${url}`;
    }
    if (url.startsWith('api/')) {
      return `${serverUrl}/${url}`;
    }
    return url;
  }

  aboutToAppear() {
    if (this.src) {
      this.loadImage();
    }
  }

  aboutToDisappear() {
    this.loadingAborted = true;
    this.releasePixelMap();
    // 组件销毁后重置状态，避免复用时跳过加载
    this.currentSrc = '';
    this.effectiveSrc = '';
    this.useDirectImage = false;
    this.loadError = false;
  }

  /**
   * 当 src 属性变化时重新加载图片
   * 例如：封面缓存完成后，src 从 HTTP URL 变为 file:// 路径
   */
  onSrcChange(): void {
    if (this.src && this.src !== this.currentSrc) {
      this.loadImage();
    }
  }

  private releasePixelMap(): void {
    if (this.pixelMap) {
      try {
        this.pixelMap.release();
      } catch (_error) {
      }
      this.pixelMap = null;
    }
  }

  private async loadImage(): Promise<void> {
    if (!this.src || this.isLoading) {
      return;
    }
    // 如果 src 未变但 pixelMap 已被释放（组件回收后重新出现），允许重新加载
    if (this.src === this.currentSrc && this.pixelMap !== null) {
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
      const requestUrl = this.effectiveSrc;
      if (requestUrl !== this.src) {
        logger.debug(TAG, `规范化图片URL: ${this.previewUrl(this.src)} -> ${this.previewUrl(requestUrl)}`);
      }

      // 非 HTTP URL 直接使用 Image 组件（file:// 等本地路径无需认证头）
      if (!requestUrl.startsWith('http://') && !requestUrl.startsWith('https://')) {
        this.useDirectImage = true;
        this.isLoading = false;
        return;
      }

      const authorizationHeader = this.getAuthorizationHeader();
      const canFallbackToDirectImage = !authorizationHeader;

      // HTTP URL 下载图片数据（带认证头）
      const buffer = await this.downloadImage(requestUrl, authorizationHeader);

      if (this.loadingAborted) {
        return;
      }

      if (!buffer) {
        if (canFallbackToDirectImage) {
          logger.warn(TAG, `下载图片失败，回退 Image 组件: ${this.previewUrl(requestUrl)}`);
          this.useDirectImage = true;
          this.loadError = false;
        } else {
          logger.warn(TAG, `下载图片失败（需要认证，不可回退）: ${this.previewUrl(requestUrl)}`);
          this.loadError = true;
        }
        this.isLoading = false;
        return;
      }

      let pixelMap: image.PixelMap | null = null;

      // 检查是否为 AVIF 格式
      if (isAvifFormat(buffer)) {
        logger.debug(TAG, `检测到 AVIF 格式: ${requestUrl.substring(0, 60)}...`);
        const avifDecoder = AvifDecoder.getInstance();
        if (avifDecoder.isSupported()) {
          pixelMap = await avifDecoder.decode(buffer);
          if (pixelMap) {
            logger.debug(TAG, 'AVIF 解码成功');
          }
        }
      }

      // 如果 AVIF 解码失败或不是 AVIF，尝试系统解码
      if (!pixelMap) {
        try {
          const imageSource = image.createImageSource(buffer);
          pixelMap = await imageSource.createPixelMap();
          imageSource.release();
        } catch (decodeError) {
          logger.warn(TAG, `系统解码失败: ${this.resolveErrorText(decodeError as Object | string | number | boolean | null | undefined)}, url=${this.previewUrl(requestUrl)}`);
          if (canFallbackToDirectImage) {
            logger.warn(TAG, `系统解码失败，回退 Image 组件: ${this.previewUrl(requestUrl)}`);
            this.useDirectImage = true;
            this.loadError = false;
          } else {
            this.loadError = true;
          }
          this.isLoading = false;
          return;
        }
      }

      if (this.loadingAborted) {
        if (pixelMap) {
          pixelMap.release();
        }
        return;
      }

      if (pixelMap) {
        this.pixelMap = pixelMap;
      } else {
        logger.warn(TAG, `图片解码结果为空: ${this.previewUrl(requestUrl)}`);
        if (canFallbackToDirectImage) {
          logger.warn(TAG, `图片解码结果为空，回退 Image 组件: ${this.previewUrl(requestUrl)}`);
          this.useDirectImage = true;
          this.loadError = false;
        } else {
          this.loadError = true;
        }
      }
    } catch (e) {
      logger.warn(TAG, `加载图片失败: ${this.resolveErrorText(e as Object | string | number | boolean | null | undefined)}, url=${this.previewUrl(this.effectiveSrc || this.src)}`);
      this.loadError = true;
    } finally {
      if (!this.loadingAborted) {
        this.isLoading = false;
      }
    }
  }

  private async downloadImage(url: string, authorizationHeader?: string): Promise<ArrayBuffer | null> {
    try {
      const httpRequest = http.createHttp();
      const headers: Record<string, string> = {
        'User-Agent': 'Mozilla/5.0 (Linux; Android 10) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Mobile Safari/537.36',
        'Accept': 'image/avif,image/webp,image/apng,image/*,*/*;q=0.8'
      };

      if (authorizationHeader) {
        headers['Authorization'] = authorizationHeader;
      }

      const response = await httpRequest.request(url, {
        method: http.RequestMethod.GET,
        expectDataType: http.HttpDataType.ARRAY_BUFFER,
        connectTimeout: 30000,
        readTimeout: 60000,
        header: headers
      });

      httpRequest.destroy();

      if (response.responseCode === 200 && response.result) {
        return response.result as ArrayBuffer;
      }

      logger.warn(TAG, `下载图片HTTP失败: code=${response.responseCode}, url=${this.previewUrl(url)}`);
      return null;
    } catch (e) {
      logger.warn(TAG, `下载图片异常: ${this.resolveErrorText(e as Object | string | number | boolean | null | undefined)}, url=${this.previewUrl(url)}`);
      return null;
    }
  }

  build() {
    Stack() {
      // 加载中或占位
      if (this.isLoading || (!this.pixelMap && !this.useDirectImage && !this.loadError)) {
        Column()
          .width('100%')
          .height('100%')
          .backgroundColor(this.placeholderColor)
      }

      // 使用 PixelMap 显示（AVIF 或手动解码的图片）
      if (this.pixelMap) {
        Image(this.pixelMap)
          .width(this.imageWidth)
          .height(this.imgAspectRatio > 0 ? undefined : this.imageHeight)
          .aspectRatio(this.imgAspectRatio > 0 ? this.imgAspectRatio : undefined)
          .objectFit(this.objectFit)
          .borderRadius(this.imgBorderRadius)
      }

      // 直接使用 Image 组件加载（非 AVIF 或回退模式）
      if (this.useDirectImage && (this.effectiveSrc || this.src)) {
        Image(this.effectiveSrc || this.src)
          .width(this.imageWidth)
          .height(this.imgAspectRatio > 0 ? undefined : this.imageHeight)
          .aspectRatio(this.imgAspectRatio > 0 ? this.imgAspectRatio : undefined)
          .objectFit(this.objectFit)
          .borderRadius(this.imgBorderRadius)
          .onError(() => {
            logger.warn(TAG, `Image组件加载失败: ${this.previewUrl(this.effectiveSrc || this.src)}`);
            this.loadError = true;
          })
      }

      // 加载失败占位
      if (this.loadError) {
        Column()
          .width('100%')
          .height('100%')
          .backgroundColor(this.placeholderColor)
      }
    }
    .width(this.imageWidth)
    .height(this.imgAspectRatio > 0 ? undefined : this.imageHeight)
    .aspectRatio(this.imgAspectRatio > 0 ? this.imgAspectRatio : undefined)
    .borderRadius(this.imgBorderRadius)
    .clip(true)
  }
}
