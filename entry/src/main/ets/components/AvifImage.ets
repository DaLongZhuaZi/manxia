/**
 * AVIF图片组件
 * 支持显示AVIF格式图片，自动检测格式并使用Native解码器
 */

import { image } from '@kit.ImageKit';
import { http } from '@kit.NetworkKit';
import { logger } from '../Utils/Logger';
import { AvifDecoder, isAvifFormat } from '../Framework/Image/AvifDecoder';

const TAG = 'AvifImage';

@Component
export struct AvifImage {
  @Prop src: string = '';
  @Prop imageWidth: Length = '100%';
  @Prop imageHeight: Length = '100%';
  @Prop objectFit: ImageFit = ImageFit.Cover;
  @Prop imageBorderRadius: Length = 0;
  @Prop placeholder: Resource | undefined = undefined;
  @Prop errorHolder: Resource | undefined = undefined;
  
  @State private pixelMap: image.PixelMap | null = null;
  @State private isLoading: boolean = false;
  @State private loadError: boolean = false;
  @State private isAvif: boolean = false;
  
  private currentSrc: string = '';
  
  aboutToAppear() {
    this.loadImage();
  }
  
  aboutToDisappear() {
    // 释放PixelMap资源
    if (this.pixelMap) {
      this.pixelMap.release();
      this.pixelMap = null;
    }
  }
  
  onDidBuild() {
    // 检测src变化
    if (this.src !== this.currentSrc) {
      this.loadImage();
    }
  }
  
  private async loadImage() {
    if (!this.src || this.src === this.currentSrc) {
      return;
    }
    
    this.currentSrc = this.src;
    this.isLoading = true;
    this.loadError = false;
    this.isAvif = false;
    
    // 释放旧的PixelMap
    if (this.pixelMap) {
      this.pixelMap.release();
      this.pixelMap = null;
    }
    
    try {
      // 如果是本地文件或非HTTP URL，直接使用Image组件
      if (!this.src.startsWith('http://') && !this.src.startsWith('https://')) {
        this.isLoading = false;
        return;
      }
      
      // 下载图片数据
      const buffer = await this.downloadImage(this.src);
      if (!buffer) {
        this.loadError = true;
        this.isLoading = false;
        return;
      }
      
      // 检查是否为AVIF格式
      if (isAvifFormat(buffer)) {
        logger.info(TAG, `检测到AVIF格式: ${this.src.substring(0, 50)}...`);
        this.isAvif = true;
        
        // 使用AVIF解码器
        const avifDecoder = AvifDecoder.getInstance();
        if (avifDecoder.isSupported()) {
          this.pixelMap = await avifDecoder.decode(buffer);
          if (this.pixelMap) {
            logger.info(TAG, `AVIF解码成功`);
          } else {
            logger.warn(TAG, `AVIF解码返回null，尝试系统解码`);
            this.pixelMap = await this.decodeWithSystem(buffer);
          }
        } else {
          logger.warn(TAG, `AVIF解码器不可用，尝试系统解码`);
          this.pixelMap = await this.decodeWithSystem(buffer);
        }
      } else {
        // 非AVIF格式，使用系统解码
        this.pixelMap = await this.decodeWithSystem(buffer);
      }
      
      if (!this.pixelMap) {
        this.loadError = true;
      }
    } catch (e) {
      logger.error(TAG, `加载图片失败: ${e}`);
      this.loadError = true;
    } finally {
      this.isLoading = false;
    }
  }
  
  private async downloadImage(url: string): Promise<ArrayBuffer | null> {
    try {
      const httpRequest = http.createHttp();
      const response = await httpRequest.request(url, {
        method: http.RequestMethod.GET,
        expectDataType: http.HttpDataType.ARRAY_BUFFER,
        connectTimeout: 30000,
        readTimeout: 30000,
        header: {
          'User-Agent': 'Mozilla/5.0 (Linux; Android 10) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Mobile Safari/537.36',
          'Accept': 'image/avif,image/webp,image/apng,image/*,*/*;q=0.8',
          'Referer': url
        }
      });
      
      httpRequest.destroy();
      
      if (response.responseCode === 200 && response.result) {
        return response.result as ArrayBuffer;
      }
      
      logger.warn(TAG, `下载图片失败: HTTP ${response.responseCode}`);
      return null;
    } catch (e) {
      logger.error(TAG, `下载图片异常: ${e}`);
      return null;
    }
  }
  
  private async decodeWithSystem(buffer: ArrayBuffer): Promise<image.PixelMap | null> {
    try {
      const imageSource = image.createImageSource(buffer);
      const pixelMap = await imageSource.createPixelMap();
      imageSource.release();
      return pixelMap;
    } catch (e) {
      logger.error(TAG, `系统解码失败: ${e}`);
      return null;
    }
  }
  
  /**
   * 判断是否为本地文件路径（非网络URL）
   */
  private isLocalFile(): boolean {
    return this.src.length > 0 && !this.src.startsWith('http://') && !this.src.startsWith('https://');
  }

  build() {
    Stack() {
      if (this.isLocalFile()) {
        // 本地文件：直接使用Image组件，不设置会永久隐藏的onError
        Image(this.src)
          .width(this.imageWidth)
          .height(this.imageHeight)
          .objectFit(this.objectFit)
          .borderRadius(this.imageBorderRadius)
      } else {
        // 网络图片路径
        // 显示加载中占位符
        if (this.isLoading && this.placeholder) {
          Image(this.placeholder)
            .width(this.imageWidth)
            .height(this.imageHeight)
            .objectFit(this.objectFit)
            .borderRadius(this.imageBorderRadius)
        }

        // 显示错误占位符
        if (this.loadError && this.errorHolder) {
          Image(this.errorHolder)
            .width(this.imageWidth)
            .height(this.imageHeight)
            .objectFit(this.objectFit)
            .borderRadius(this.imageBorderRadius)
        }

        // 显示解码后的PixelMap（AVIF或其他需要手动解码的格式）
        if (this.pixelMap) {
          Image(this.pixelMap)
            .width(this.imageWidth)
            .height(this.imageHeight)
            .objectFit(this.objectFit)
            .borderRadius(this.imageBorderRadius)
        }

        // 非AVIF格式且非加载中/错误状态，直接使用Image组件加载
        if (!this.isAvif && !this.isLoading && !this.loadError && !this.pixelMap && this.src) {
          Image(this.src)
            .width(this.imageWidth)
            .height(this.imageHeight)
            .objectFit(this.objectFit)
            .borderRadius(this.imageBorderRadius)
            .onError(() => {
              logger.warn(TAG, `Image组件加载失败: ${this.src.substring(0, 50)}...`);
              this.loadError = true;
            })
        }
      }
    }
    .width(this.imageWidth)
    .height(this.imageHeight)
  }
}
