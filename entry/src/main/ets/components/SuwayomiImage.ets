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
  private loadingAborted: boolean = false;

  aboutToAppear() {
    if (this.src) {
      this.loadImage();
    }
  }

  aboutToDisappear() {
    this.loadingAborted = true;
    this.releasePixelMap();
    // 重置 currentSrc，确保组件被回收后重新出现时能重新加载图片
    this.currentSrc = '';
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
      } catch (e) {
        // 忽略释放错误
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
    this.isLoading = true;
    this.loadError = false;
    this.useDirectImage = false;
    this.releasePixelMap();
    this.loadingAborted = false;

    try {
      // 非 HTTP URL 直接使用 Image 组件（file:// 等本地路径无需认证头）
      if (!this.src.startsWith('http://') && !this.src.startsWith('https://')) {
        this.useDirectImage = true;
        this.isLoading = false;
        return;
      }

      // HTTP URL 下载图片数据（带认证头）
      const buffer = await this.downloadImage(this.src);
      
      if (this.loadingAborted) {
        return;
      }

      if (!buffer) {
        // 下载失败，标记为错误（不回退到 Image(url) —— 它无法发送认证头）
        logger.warn(TAG, `下载图片失败: ${this.src.substring(0, 80)}`);
        this.loadError = true;
        this.isLoading = false;
        return;
      }

      let pixelMap: image.PixelMap | null = null;

      // 检查是否为 AVIF 格式
      if (isAvifFormat(buffer)) {
        logger.debug(TAG, `检测到 AVIF 格式: ${this.src.substring(0, 60)}...`);
        const avifDecoder = AvifDecoder.getInstance();
        if (avifDecoder.isSupported()) {
          pixelMap = await avifDecoder.decode(buffer);
          if (pixelMap) {
            logger.debug(TAG, `AVIF 解码成功`);
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
          logger.warn(TAG, `系统解码失败: ${decodeError}`);
          this.loadError = true;
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
        this.loadError = true;
      }
    } catch (e) {
      logger.warn(TAG, `加载图片失败: ${e}`);
      this.loadError = true;
    } finally {
      if (!this.loadingAborted) {
        this.isLoading = false;
      }
    }
  }

  private async downloadImage(url: string): Promise<ArrayBuffer | null> {
    try {
      const httpRequest = http.createHttp();
      const headers: Record<string, string> = {
        'User-Agent': 'Mozilla/5.0 (Linux; Android 10) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Mobile Safari/537.36',
        'Accept': 'image/avif,image/webp,image/apng,image/*,*/*;q=0.8'
      };

      // 添加 Suwayomi 认证头
      try {
        const executor = getSuwayomiSourceExecutor();
        const authHeaders = executor.getImageHeaders();
        if (authHeaders['Authorization']) {
          headers['Authorization'] = authHeaders['Authorization'];
        }
      } catch (e) {
        // 忽略获取认证头失败
      }

      const response = await httpRequest.request(url, {
        method: http.RequestMethod.GET,
        expectDataType: http.HttpDataType.ARRAY_BUFFER,
        connectTimeout: 15000,
        readTimeout: 30000,
        header: headers
      });

      httpRequest.destroy();

      if (response.responseCode === 200 && response.result) {
        return response.result as ArrayBuffer;
      }

      return null;
    } catch (e) {
      logger.debug(TAG, `下载图片失败: ${e}`);
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
      if (this.useDirectImage && this.src) {
        Image(this.src)
          .width(this.imageWidth)
          .height(this.imgAspectRatio > 0 ? undefined : this.imageHeight)
          .aspectRatio(this.imgAspectRatio > 0 ? this.imgAspectRatio : undefined)
          .objectFit(this.objectFit)
          .borderRadius(this.imgBorderRadius)
          .onError(() => {
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
