/**
 * 图片查看器
 * 支持普通图片预览，AVIF 图片继续使用专用解码器并支持导出转换。
 */

import { HdsNavDestination, HdsNavDestinationAttribute, ScrollEffectType } from '@kit.UIDesignKit';
import { LengthMetrics, promptAction } from '@kit.ArkUI';
import { picker } from '@kit.CoreFileKit';
import { common } from '@kit.AbilityKit';
import { fileIo } from '@kit.CoreFileKit';
import { fileUri } from '@kit.CoreFileKit';
import { image } from '@kit.ImageKit';
import { photoAccessHelper } from '@kit.MediaLibraryKit';
import { logger } from '../Utils/Logger';
import { AvifDecoder, isAvifFormat, isAvifSupported } from '../Framework/Image/AvifDecoder';
import { ThemeAwareState, ThemeAwareHelper } from '../Framework/Components/ThemeAware';
import { ThemeManager, ThemeType } from '../Framework/Managers/ThemeManager';
import { FontAwareHelper, FontAwareState } from '../Framework/Components/FontAware';
import { DeviceAdaptationManager, DeviceInfo, DeviceChangeListener, Breakpoint } from '../Framework/Managers/DeviceAdaptationManager';
import { ResponsiveLayoutHelper } from '../Framework/Utils/ResponsiveLayout';
import { SettingsImmersiveTitleBar } from './settings/SettingsImmersiveTitleBar';
import { SettingsPageTitleBarManager } from './settings/SettingsPageTitleBarManager';

const TAG = 'AvifTestPage';
const TITLE_BAR_HEIGHT_MINI: number = 56;
const IMAGE_FILE_SUFFIX_FILTERS: string[] = [
  '.avif', '.AVIF',
  '.jpg', '.JPG',
  '.jpeg', '.JPEG',
  '.png', '.PNG',
  '.gif', '.GIF',
  '.webp', '.WEBP',
  '.bmp', '.BMP',
  '.heic', '.HEIC',
  '.heif', '.HEIF',
  '.svg', '.SVG'
];

// NavDestinationContext接口定义
interface NavDestinationPathInfo {
  param?: Object;
}

interface NavDestinationContext {
  pathStack: NavPathStack;
  pathInfo?: NavDestinationPathInfo;
}

// 导出格式
type ExportFormat = 'png' | 'webp';

// 图片信息
interface ImageInfo {
  width: number;
  height: number;
  fileSize: number;
  format: string;
  decodeTime: number;
}

// 页面参数
export interface AvifTestPageParams {
  fileUri?: string;
}

@Component
export struct AvifTestPage {
  @StorageProp('statusBarHeight') statusBarHeight: number = 0;
  @State isLoading: boolean = false;
  @State loadingText: string = '';
  @State selectedFilePath: string = '';
  @State selectedFileName: string = '';
  @State avifStatus: string = '检测中...';
  @State decodedImage: image.PixelMap | null = null;
  @State imageInfo: ImageInfo | null = null;
  @State showExportMenu: boolean = false;
  @State exportProgress: number = 0;
  
  // 主题相关
  @State themeState: ThemeAwareState = new ThemeAwareState();
  @State fontState: FontAwareState = new FontAwareState();
  @StorageLink('appFontFamily') appFontFamily: string = 'HarmonyOS Sans';
  private themeManager: ThemeManager = ThemeManager.getInstance();
  
  // 响应式布局
  @State responsive_isLandscape: boolean = false;
  @State responsive_breakpoint: Breakpoint = Breakpoint.SM;
  private deviceManager: DeviceAdaptationManager = DeviceAdaptationManager.getInstance();
  private deviceChangeListener: DeviceChangeListener = (info: DeviceInfo) => {
    this.responsive_isLandscape = info.isLandscape;
    this.responsive_breakpoint = info.breakpoint;
  };
  
  private pathStack: NavPathStack = new NavPathStack();
  private context: common.UIAbilityContext | null = null;
  private avifDecoder: AvifDecoder = AvifDecoder.getInstance();
  private imageBuffer: ArrayBuffer | null = null;

  aboutToAppear(): void {
    this.context = (this.getUIContext().getHostContext() as common.UIAbilityContext) as common.UIAbilityContext;
    this.initTheme();
    this.initResponsive();
    this.checkAvifSupport();
  }

  aboutToDisappear(): void {
    if (this.decodedImage) {
      this.decodedImage.release();
      this.decodedImage = null;
    }
    this.imageBuffer = null;
    
    // 移除设备监听
    this.deviceManager.removeListener(this.deviceChangeListener);
  }

  private initTheme(): void {
    ThemeAwareHelper.initializeThemeAware(TAG, this.themeState, (theme: ThemeType) => {
      logger.info(TAG, `主题切换: ${theme}`);
    });
    FontAwareHelper.initializeFontAware(TAG, this.fontState, (newState: FontAwareState) => {
      this.fontState = newState;
    });
  }

  private initResponsive(): void {
    const deviceInfo = this.deviceManager.getDeviceInfo();
    this.responsive_isLandscape = deviceInfo.isLandscape;
    this.responsive_breakpoint = deviceInfo.breakpoint;
    this.deviceManager.addListener(this.deviceChangeListener);
  }

  private checkAvifSupport(): void {
    try {
      const supported = isAvifSupported();
      const nativeSupported = this.avifDecoder.isSupported();
      
      if (supported && nativeSupported) {
        this.avifStatus = '✅ AVIF解码器可用';
      } else if (supported) {
        this.avifStatus = '⚠️ libavif不可用';
      } else {
        this.avifStatus = '❌ 解码器不可用';
      }
    } catch (error) {
      this.avifStatus = `❌ 检测失败`;
      logger.error(TAG, `检测AVIF支持时出错: ${error}`);
    }
  }

  private showToast(message: string): void {
    this.getUIContext().getPromptAction().showToast({ message, duration: 2000 });
  }

  private clearImage(): void {
    if (this.decodedImage) {
      this.decodedImage.release();
      this.decodedImage = null;
    }
    this.imageBuffer = null;
    this.imageInfo = null;
    this.selectedFilePath = '';
    this.selectedFileName = '';
  }

  /**
   * 选择图片文件
   */
  private async selectFile(): Promise<void> {
    try {
      this.isLoading = true;
      this.loadingText = '正在选择文件...';
      
      const documentPicker = new picker.DocumentViewPicker(this.context!);
      const selectOptions: picker.DocumentSelectOptions = {
        maxSelectNumber: 1,
        fileSuffixFilters: IMAGE_FILE_SUFFIX_FILTERS,
      };

      const result = await documentPicker.select(selectOptions);
      
      if (!result || result.length === 0) {
        this.showToast('未选择任何文件');
        this.isLoading = false;
        return;
      }

      const uri = result[0];
      
      // 获取文件名
      try {
        const uriObj = new fileUri.FileUri(uri);
        this.selectedFileName = uriObj.name;
      } catch {
        this.selectedFileName = decodeURIComponent(uri.split('/').pop() || 'unknown.image');
      }
      
      this.selectedFilePath = uri;
      await this.decodeImageFile(uri);
    } catch (error) {
      this.showToast(`选择文件失败: ${error}`);
      logger.error(TAG, `选择文件失败: ${error}`);
    } finally {
      this.isLoading = false;
    }
  }

  /**
   * 解码图片文件。AVIF 走专用解码器，普通图片走系统 ImageSource。
   */
  private async decodeImageFile(uri: string): Promise<void> {
    this.loadingText = '正在读取文件...';
    
    try {
      // 清除旧图片
      if (this.decodedImage) {
        this.decodedImage.release();
        this.decodedImage = null;
      }
      
      // 读取文件内容
      const file = await fileIo.open(uri, fileIo.OpenMode.READ_ONLY);
      const stat = await fileIo.stat(file.fd);
      const fileSize = stat.size;
      
      const buffer = new ArrayBuffer(fileSize);
      await fileIo.read(file.fd, buffer);
      await fileIo.close(file);
      
      // 保存buffer用于后续导出
      this.imageBuffer = buffer;
      
      // 检查是否为AVIF格式
      const isAvif = isAvifFormat(buffer);
      this.loadingText = isAvif ? '正在解码AVIF...' : '正在解码图片...';
      const startTime = Date.now();
      const pixelMap = isAvif ? await this.decodeAvifBuffer(buffer) : await this.decodeSystemImage(buffer);
      const decodeTime = Date.now() - startTime;
      
      if (pixelMap) {
        const imgInfo = await pixelMap.getImageInfo();
        const formatLabel = this.resolveImageFormatLabel(this.selectedFileName, isAvif);
        this.decodedImage = pixelMap;
        this.imageInfo = {
          width: imgInfo.size.width,
          height: imgInfo.size.height,
          fileSize: fileSize,
          format: formatLabel,
          decodeTime: decodeTime
        };
        
        logger.info(TAG, `图片解码成功: format=${formatLabel}, ${imgInfo.size.width}x${imgInfo.size.height}, 耗时${decodeTime}ms`);
      } else {
        this.showToast(isAvif ? 'AVIF解码失败' : '图片解码失败');
      }
    } catch (error) {
      this.showToast(`解码错误: ${error}`);
      logger.error(TAG, `解码错误: ${error}`);
    }
  }

  private async decodeAvifBuffer(buffer: ArrayBuffer): Promise<image.PixelMap | null> {
    const pixelMap = await this.avifDecoder.decode(buffer);
    if (pixelMap) {
      return pixelMap;
    }
    logger.warn(TAG, 'AVIF专用解码器返回空，尝试系统图片解码');
    return await this.decodeSystemImage(buffer);
  }

  private async decodeSystemImage(buffer: ArrayBuffer): Promise<image.PixelMap | null> {
    let imageSource: image.ImageSource | null = null;
    try {
      imageSource = image.createImageSource(buffer);
      return await imageSource.createPixelMap();
    } catch (error) {
      logger.error(TAG, `系统图片解码失败: ${String(error)}`);
      return null;
    } finally {
      if (imageSource) {
        try {
          await imageSource.release();
        } catch (releaseError) {
          logger.warn(TAG, `释放图片解码资源失败: ${String(releaseError)}`);
        }
      }
    }
  }

  private resolveImageFormatLabel(fileName: string, isAvif: boolean): string {
    if (isAvif) {
      return 'AVIF';
    }
    const lowerName = fileName.trim().toLowerCase();
    const dotIndex = lowerName.lastIndexOf('.');
    if (dotIndex >= 0 && dotIndex < lowerName.length - 1) {
      return lowerName.substring(dotIndex + 1).toUpperCase();
    }
    return 'IMAGE';
  }

  /**
   * 导出图片为PNG格式
   */
  private async exportAsPng(): Promise<void> {
    await this.exportImage('png');
  }

  /**
   * 导出图片为WebP格式
   */
  private async exportAsWebp(): Promise<void> {
    await this.exportImage('webp');
  }

  /**
   * 导出图片
   */
  private async exportImage(format: ExportFormat): Promise<void> {
    if (!this.decodedImage) {
      this.showToast('请先导入图片');
      return;
    }
    
    this.isLoading = true;
    this.loadingText = `正在导出为${format.toUpperCase()}...`;
    
    try {
      // 创建ImagePacker
      const imagePacker = image.createImagePacker();
      
      // 设置打包选项
      const packingOptions: image.PackingOption = {
        format: format === 'png' ? 'image/png' : 'image/webp',
        quality: format === 'webp' ? 90 : 100
      };
      
      // 打包图片
      const packedData = await imagePacker.packToData(this.decodedImage, packingOptions);
      imagePacker.release();
      
      // 生成文件名
      const baseName = this.selectedFileName.replace(/\.[^.]+$/, '');
      const exportFileName = `${baseName}_exported.${format}`;
      
      // 使用DocumentViewPicker保存文件
      const documentPicker = new picker.DocumentViewPicker(this.context!);
      const saveOptions: picker.DocumentSaveOptions = {
        newFileNames: [exportFileName],
        fileSuffixChoices: [`.${format}`]
      };
      
      const saveResult = await documentPicker.save(saveOptions);
      
      if (saveResult && saveResult.length > 0) {
        const saveUri = saveResult[0];
        
        // 写入文件
        const file = await fileIo.open(saveUri, fileIo.OpenMode.READ_WRITE | fileIo.OpenMode.CREATE);
        await fileIo.write(file.fd, packedData);
        await fileIo.close(file);
        
        this.showToast(`已导出为${format.toUpperCase()}: ${exportFileName}`);
        logger.info(TAG, `图片导出成功: ${saveUri}`);
      } else {
        this.showToast('导出已取消');
      }
    } catch (error) {
      this.showToast(`导出失败: ${error}`);
      logger.error(TAG, `导出失败: ${error}`);
    } finally {
      this.isLoading = false;
    }
  }

  /**
   * 保存到相册（使用受限API showAssetsCreationDialog）
   */
  private async saveToGallery(): Promise<void> {
    if (!this.decodedImage) {
      this.showToast('请先导入图片');
      return;
    }
    
    this.isLoading = true;
    this.loadingText = '正在准备保存...';
    
    try {
      // 创建ImagePacker，转换为PNG格式
      const imagePacker = image.createImagePacker();
      const packingOptions: image.PackingOption = {
        format: 'image/png',
        quality: 100
      };
      
      const packedData = await imagePacker.packToData(this.decodedImage, packingOptions);
      imagePacker.release();
      
      // 先保存到临时文件
      const baseName = this.selectedFileName.replace(/\.[^.]+$/, '');
      const tempFileName = `${baseName}_converted.png`;
      const tempDir = this.context!.tempDir;
      const tempFilePath = `${tempDir}/${tempFileName}`;
      
      // 写入临时文件
      const tempFile = await fileIo.open(tempFilePath, fileIo.OpenMode.CREATE | fileIo.OpenMode.READ_WRITE);
      await fileIo.write(tempFile.fd, packedData);
      await fileIo.close(tempFile);
      
      // 转换为URI
      const sandboxUri = fileUri.getUriFromPath(tempFilePath);
      
      // 创建photoAccessHelper
      const phAccessHelper = photoAccessHelper.getPhotoAccessHelper(this.context!);
      
      // 准备保存配置
      const srcFileUris: Array<string> = [sandboxUri];
      const photoCreationConfigs: Array<photoAccessHelper.PhotoCreationConfig> = [{
        title: baseName,
        fileNameExtension: 'png',
        photoType: photoAccessHelper.PhotoType.IMAGE,
        subtype: photoAccessHelper.PhotoSubtype.DEFAULT
      }];
      
      this.isLoading = false;
      
      // 显示保存对话框让用户确认
      const desFileUris: Array<string> = await phAccessHelper.showAssetsCreationDialog(srcFileUris, photoCreationConfigs);
      
      if (desFileUris.length > 0) {
        // 打开目标文件和源文件
        const destFile = await fileIo.open(desFileUris[0], fileIo.OpenMode.WRITE_ONLY);
        const srcFile = await fileIo.open(sandboxUri, fileIo.OpenMode.READ_ONLY);
        
        // 复制文件内容
        await fileIo.copyFile(srcFile.fd, destFile.fd);
        
        // 关闭文件
        await fileIo.close(destFile);
        await fileIo.close(srcFile);
        
        // 删除临时文件
        try {
          await fileIo.unlink(tempFilePath);
        } catch (e) {
          logger.warn(TAG, `删除临时文件失败: ${e}`);
        }
        
        this.showToast('图片已保存到图库');
        logger.info(TAG, `图片保存成功: ${desFileUris[0]}`);
      } else {
        logger.info(TAG, '用户取消保存');
        // 删除临时文件
        try {
          await fileIo.unlink(tempFilePath);
        } catch (e) {
          logger.warn(TAG, `删除临时文件失败: ${e}`);
        }
      }
    } catch (error) {
      this.showToast(`保存失败: ${error}`);
      logger.error(TAG, `保存到相册失败: ${error}`);
    } finally {
      this.isLoading = false;
    }
  }

  /**
   * 格式化文件大小
   */
  private formatFileSize(bytes: number): string {
    if (bytes < 1024) return `${bytes} B`;
    if (bytes < 1024 * 1024) return `${(bytes / 1024).toFixed(2)} KB`;
    return `${(bytes / (1024 * 1024)).toFixed(2)} MB`;
  }

  @Builder
  buildToolbar() {
    Row({ space: 12 }) {
      // 导入按钮
      Button({ type: ButtonType.Normal }) {
        Row({ space: 6 }) {
          SymbolGlyph($r('sys.symbol.folder'))
            .fontSize(18)
            .fontColor([Color.White])
          Text('导入')
            .fontSize(14)
            .fontColor(Color.White)
            .fontFamily(this.appFontFamily)
        }
      }
      .height(40)
      .padding({ left: 10, right: 10 })
      .backgroundColor(ThemeAwareHelper.getTestManagementThemedColor('button_primary', this.themeState.currentTheme))
      .borderRadius(20)
      .onClick(() => this.selectFile())
      .enabled(!this.isLoading)
      .fontFamily(this.appFontFamily)
      
      // 导出PNG按钮
      Button({ type: ButtonType.Normal }) {
        Row({ space: 6 }) {
          SymbolGlyph($r('sys.symbol.upload'))
            .fontSize(18)
            .fontColor([this.decodedImage ? Color.White : Color.Gray])
          Text('PNG')
            .fontSize(14)
            .fontColor(this.decodedImage ? Color.White : Color.Gray)
            .fontFamily(this.appFontFamily)
        }
      }
      .height(40)
      .padding({ left: 10, right: 10 })
      .backgroundColor(this.decodedImage ? '#4CAF50' : '#CCCCCC')
      .borderRadius(20)
      .onClick(() => this.exportAsPng())
      .enabled(!this.isLoading && this.decodedImage !== null)
      .fontFamily(this.appFontFamily)
      
      // 导出WebP按钮
      Button({ type: ButtonType.Normal }) {
        Row({ space: 6 }) {
          SymbolGlyph($r('sys.symbol.upload'))
            .fontSize(18)
            .fontColor([this.decodedImage ? Color.White : Color.Gray])
          Text('WebP')
            .fontSize(14)
            .fontColor(this.decodedImage ? Color.White : Color.Gray)
            .fontFamily(this.appFontFamily)
        }
      }
      .height(40)
      .padding({ left: 10, right: 10 })
      .backgroundColor(this.decodedImage ? '#2196F3' : '#CCCCCC')
      .borderRadius(20)
      .onClick(() => this.exportAsWebp())
      .enabled(!this.isLoading && this.decodedImage !== null)
      .fontFamily(this.appFontFamily)
      
      // 保存到相册按钮
      Button({ type: ButtonType.Normal }) {
        Row({ space: 6 }) {
          SymbolGlyph($r('sys.symbol.picture_on_square'))
            .fontSize(18)
            .fontColor([this.decodedImage ? Color.White : Color.Gray])
          Text('相册')
            .fontSize(14)
            .fontColor(this.decodedImage ? Color.White : Color.Gray)
            .fontFamily(this.appFontFamily)
        }
      }
      .height(40)
      .padding({ left: 10, right: 10 })
      .backgroundColor(this.decodedImage ? '#FF9800' : '#CCCCCC')
      .borderRadius(20)
      .onClick(() => this.saveToGallery())
      .enabled(!this.isLoading && this.decodedImage !== null)
      .fontFamily(this.appFontFamily)
    }
    .width('100%')
    .padding(16)
    .justifyContent(FlexAlign.Center)
  }

  @Builder
  buildImagePreview() {
    Column() {
      if (this.decodedImage) {
        // 图片预览
        Stack() {
          Image(this.decodedImage)
            .width('100%')
            .height('100%')
            .objectFit(ImageFit.Contain)
            .backgroundColor(ThemeAwareHelper.getTestManagementThemedColor('background_secondary', this.themeState.currentTheme))
        }
        .width('100%')
        .layoutWeight(1)
        .borderRadius(12)
        .clip(true)
        
        // 图片信息
        if (this.imageInfo) {
          Column({ space: 8 }) {
            Row({ space: 16 }) {
              Text(`尺寸: ${this.imageInfo.width} × ${this.imageInfo.height}`)
                .fontSize(13)
                .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_secondary', this.themeState.currentTheme))
                .fontFamily(this.appFontFamily)

              Text(`大小: ${this.formatFileSize(this.imageInfo.fileSize)}`)
                .fontSize(13)
                .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_secondary', this.themeState.currentTheme))
                .fontFamily(this.appFontFamily)

              Text(`解码: ${this.imageInfo.decodeTime}ms`)
                .fontSize(13)
                .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_secondary', this.themeState.currentTheme))
                .fontFamily(this.appFontFamily)
            }
            .justifyContent(FlexAlign.Center)
            
            if (this.selectedFileName) {
              Text(this.selectedFileName)
                .fontSize(12)
                .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_muted', this.themeState.currentTheme))
                .maxLines(1)
                .textOverflow({ overflow: TextOverflow.Ellipsis })
                .fontFamily(this.appFontFamily)
            }
          }
          .width('100%')
          .padding({ top: 12, bottom: 8 })
        }
      } else {
        // 空状态
        Column({ space: 16 }) {
          SymbolGlyph($r('sys.symbol.ohos_photo'))
            .fontSize(64)
            .fontColor([ThemeAwareHelper.getTestManagementThemedColor('text_muted', this.themeState.currentTheme)])
          
          Text('点击"导入"按钮选择图片')
            .fontSize(16)
            .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_secondary', this.themeState.currentTheme))
            .fontFamily(this.appFontFamily)
          
          Text('支持 AVIF、JPG、PNG、WebP 等图片格式')
            .fontSize(13)
            .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_muted', this.themeState.currentTheme))
            .fontFamily(this.appFontFamily)
        }
        .width('100%')
        .layoutWeight(1)
        .justifyContent(FlexAlign.Center)
      }
    }
    .width('100%')
    .layoutWeight(1)
    .padding(16)
  }

  build() {
    HdsNavDestination() {
      Stack() {
        Column() {
          Blank().height(SettingsPageTitleBarManager.getContentTopPadding(this.statusBarHeight))
          // 状态栏
          Row({ space: 8 }) {
            Text(this.avifStatus)
              .fontSize(13)
              .fontColor(this.avifStatus.startsWith('✅') ? '#4CAF50' : 
                         this.avifStatus.startsWith('⚠️') ? '#FF9800' : '#F44336')
              .fontFamily(this.appFontFamily)
          }
          .width('100%')
          .padding({ left: 16, right: 16, top: 8, bottom: 8 })
          .backgroundColor(ThemeAwareHelper.getTestManagementThemedColor('comp_background_tertiary', this.themeState.currentTheme))
          .justifyContent(FlexAlign.Center)
          
          // 工具栏
          this.buildToolbar()
          
          // 图片预览区域
          this.buildImagePreview()
        }
        .width('100%')
        .height('100%')
        .backgroundColor(ThemeAwareHelper.getTestManagementThemedColor('background', this.themeState.currentTheme))
        .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.TOP, SafeAreaEdge.BOTTOM])
        
        // 加载遮罩
        if (this.isLoading) {
          Column() {
            LoadingProgress()
              .width(48)
              .height(48)
              .color(Color.White)
            
            Text(this.loadingText)
              .fontSize(14)
              .fontColor(Color.White)
              .margin({ top: 12 })
              .fontFamily(this.appFontFamily)
          }
          .width('100%')
          .height('100%')
          .backgroundColor('rgba(0,0,0,0.5)')
          .justifyContent(FlexAlign.Center)
          .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.TOP, SafeAreaEdge.BOTTOM])
        }
        SettingsImmersiveTitleBar({
          themeState: this.themeState,
          title: '图片查看器',
          appFontFamily: this.appFontFamily,
          contentPadding: 16,
          maxContentWidth: 1200,
          pathStack: this.pathStack
        })
      }
    }
    .onReady((context: NavDestinationContext) => {
      this.pathStack = context.pathStack;
      // 检查是否有传入的文件URI参数
      const rawParams: AvifTestPageParams[] = this.pathStack.getParamByName('AvifTestPage') as AvifTestPageParams[];
      logger.info(TAG, `📋 原始参数: ${JSON.stringify(rawParams)}`);
      
      let inputFileUri: string | undefined;
      const directParams = context.pathInfo?.param as AvifTestPageParams | undefined;
      if (directParams && directParams.fileUri) {
        inputFileUri = directParams.fileUri;
      }
      
      // 尝试多种参数格式
      if (!inputFileUri && rawParams) {
        if (Array.isArray(rawParams) && rawParams.length > 0) {
          // 数组格式
          const firstParam = rawParams[0] as AvifTestPageParams;
          if (firstParam && firstParam.fileUri) {
            inputFileUri = firstParam.fileUri;
          }
        } else if (typeof rawParams === 'object' && (rawParams as AvifTestPageParams).fileUri) {
          // 单个对象格式
          inputFileUri = (rawParams as AvifTestPageParams).fileUri;
        }
      }
      
      if (inputFileUri) {
        logger.info(TAG, `从文件管理器打开图片文件: ${inputFileUri}`);
        this.selectedFilePath = inputFileUri;
        // 获取文件名
        try {
          const uriObj = new fileUri.FileUri(inputFileUri);
          this.selectedFileName = uriObj.name;
        } catch {
          this.selectedFileName = decodeURIComponent(inputFileUri.split('/').pop() || 'unknown.image');
        }
        // 自动解码
        void this.decodeImageFile(inputFileUri);
      }
    })
    .onBackPressed(() => {
      this.pathStack.pop();
      return true;
    })
    .hideTitleBar(true)
    .ignoreLayoutSafeArea([LayoutSafeAreaType.SYSTEM], [LayoutSafeAreaEdge.TOP, LayoutSafeAreaEdge.BOTTOM])
  }
}
