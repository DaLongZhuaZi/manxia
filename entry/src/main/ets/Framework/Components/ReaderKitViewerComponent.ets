// 文件路径: entry/src/main/ets/Framework/Components/ReaderKitViewerComponent.ets
/**
 * Reader Kit 阅读器组件
 * 使用 HarmonyOS 官方 Reader Kit 的 readerCore 提供阅读功能
 * 支持格式：TXT、EPUB、MOBI、AZW、AZW3
 */

import { logger } from '../../Utils/Logger';
import { EBook, EBookChapter } from '../../Models/EBookModels';
import { fileIo } from '@kit.CoreFileKit';
import { bookParser, readerCore, ReadPageComponent } from '@kit.ReaderKit';
import { common } from '@kit.AbilityKit';
import { BusinessError } from '@kit.BasicServicesKit';

const TAG = 'ReaderKitViewerComponent';

/**
 * Reader Kit 阅读器参数接口
 */
export interface ReaderKitViewerParams {
  ebook: EBook; // 电子书对象
  currentChapterIndex: number; // 当前章节索引
  onChapterChange?: (index: number) => void; // 章节切换回调
  onProgressChange?: (progress: number) => void; // 阅读进度回调
}

/**
 * Reader Kit 阅读器组件
 */
@Component
export struct ReaderKitViewerComponent {
  @Prop ebook: EBook;
  @Prop currentChapterIndex: number = 0;
  onChapterChange?: (index: number) => void;
  onProgressChange?: (progress: number) => void;
  
  @State isLoading: boolean = true;
  @State errorMessage: string = '';
  private readerController: readerCore.ReaderComponentController = new readerCore.ReaderComponentController();
  @State private controllerReady: boolean = false;
  private sandboxPath: string = '';

  // 阅读设置
  @State fontSize: number = 18;
  @State lineHeight: number = 1.8;
  @State bgColor: string = '#FFFFFF';
  @State textColor: string = '#333333';
  @State pageMargin: number = 20;

  aboutToAppear(): void {
    logger.info(TAG, `Reader Kit 阅读器组件初始化: ${this.ebook.metadata.title}`);
    this.initializeReaderSession();
  }

  aboutToDisappear(): void {
    logger.info(TAG, 'Reader Kit 阅读器组件销毁');
    try {
      this.readerController.releaseBook();
    } catch {}
  }

  /**
   * 初始化 Reader Kit 会话
   * 
   * 注意：这是框架代码，实际的 Reader Kit API 需要根据官方文档调整
   */
  private async initializeReaderSession(): Promise<void> {
    try {
      this.isLoading = true;
      this.errorMessage = '';

      logger.info(TAG, `初始化 Reader Kit 会话，格式: ${this.ebook.format}`);

      // 读取电子书文件
      const fileBuffer = await this.readFileBuffer(this.ebook.filePath);
      this.sandboxPath = await this.copyToSandbox(this.ebook.filePath, fileBuffer);

      await this.tryStartReading();

    } catch (error) {
      const errorMsg = error instanceof Error ? error.message : String(error);
      logger.error(TAG, `Reader Kit 会话初始化失败: ${errorMsg}`);
      this.errorMessage = errorMsg;
      this.isLoading = false;
    }
  }

  /**
   * 关闭 Reader Kit 会话
   */
  

  /**
   * 读取文件二进制数据
   */
  private async readFileBuffer(filePath: string): Promise<ArrayBuffer> {
    try {
      let openTarget: string = filePath;
      if (!filePath.startsWith('file://') && !filePath.startsWith('/')) {
        openTarget = `/${filePath}`;
      }

      let file = fileIo.openSync(openTarget, fileIo.OpenMode.READ_ONLY);
      let stat = fileIo.statSync(file.fd);
      let buffer = new ArrayBuffer(stat.size);
      let readLen = fileIo.readSync(file.fd, buffer);
      fileIo.closeSync(file);

      if (readLen !== stat.size) {
        throw new Error(`读取长度不一致: 期望 ${stat.size} 实际 ${readLen}`);
      }

      logger.debug(TAG, `文件读取成功，大小: ${stat.size} 字节`);
      return buffer;
    } catch (firstError) {
      const firstMsg = firstError instanceof Error ? firstError.message : String(firstError);

      try {
        if (filePath.startsWith('file://')) {
          const stripped = filePath.substring(7);
          const candidate = stripped.startsWith('/') ? stripped : `/${stripped}`;
          const file = fileIo.openSync(candidate, fileIo.OpenMode.READ_ONLY);
          const stat = fileIo.statSync(file.fd);
          const buffer = new ArrayBuffer(stat.size);
          const readLen = fileIo.readSync(file.fd, buffer);
          fileIo.closeSync(file);

          if (readLen !== stat.size) {
            throw new Error(`读取长度不一致: 期望 ${stat.size} 实际 ${readLen}`);
          }
          logger.debug(TAG, `文件读取成功（备用路径），大小: ${stat.size} 字节`);
          return buffer;
        }
        throw new Error(firstMsg);
      } catch (error) {
        const errorMsg = error instanceof Error ? error.message : String(error);
        throw new Error(`文件读取失败: ${errorMsg}`);
      }
    }
  }

  private async copyToSandbox(filePath: string, fileBuffer: ArrayBuffer): Promise<string> {
    const context = this.getUIContext()?.getHostContext() as common.UIAbilityContext;
    const fileName = this.getFileName(filePath);
    const target = `${context.filesDir}/${fileName}`;
    const file = fileIo.openSync(target, fileIo.OpenMode.READ_WRITE | fileIo.OpenMode.CREATE);
    fileIo.writeSync(file.fd, fileBuffer);
    fileIo.closeSync(file.fd);
    return target;
  }

  private getFileName(path: string): string {
    const parts = path.split('/');
    const name = parts[parts.length - 1] || 'unknown_file';
    try { return decodeURIComponent(name); } catch { return name; }
  }

  /**
   * 获取 Reader Kit 文件类型
   */
  private getReaderKitFileType(): string {
    // TODO: 根据实际 Reader Kit API 返回正确的文件类型枚举
    return this.ebook.format;
  }

  /**
   * 跳转到指定章节
   */
  private async jumpToChapter(chapterIndex: number): Promise<void> {
    try {
      if (!this.controllerReady) {
        logger.warn(TAG, 'Reader Kit 控制器未就绪');
        return;
      }
      await this.readerController.startPlay(chapterIndex, '');

      if (this.onChapterChange) {
        this.onChapterChange(chapterIndex);
      }

      logger.info(TAG, `已跳转到章节: ${chapterIndex}`);
    } catch (error) {
      logger.error(TAG, `跳转章节失败: ${String(error)}`);
    }
  }

  /**
   * 调整字体大小
   */
  private async adjustFontSize(delta: number): Promise<void> {
    this.fontSize = Math.max(12, Math.min(32, this.fontSize + delta));

    logger.debug(TAG, `字体大小调整为: ${this.fontSize}`);
  }

  /**
   * 尝试启动 Reader Kit 阅读器
   */
  private async tryStartReading(): Promise<void> {
    if (!this.controllerReady || this.sandboxPath.length === 0) {
      return;
    }
    try {
      const context = this.getUIContext()?.getHostContext() as common.UIAbilityContext;
      await this.readerController.init(context);
      const parserHandler: bookParser.BookParserHandler = await bookParser.getDefaultHandler(this.sandboxPath);
      this.readerController.registerBookParser(parserHandler);
      await this.readerController.startPlay(0, '');
      logger.info(TAG, 'Reader Kit 阅读器已初始化');
      this.isLoading = false;
    } catch (error) {
      const errorMsg = error instanceof Error ? error.message : String(error);
      logger.error(TAG, `Reader Kit 阅读器初始化失败: ${errorMsg}`);
      this.errorMessage = errorMsg;
      this.isLoading = false;
    }
  }

  build() {
    Stack() {
      if (this.isLoading) {
        // 加载状态
        Column({ space: 16 }) {
          LoadingProgress()
            .width(60)
            .height(60)
            .color(Color.Blue)
          
          Text('正在加载电子书...')
            .fontSize(14)
            .fontColor(Color.Gray)
        }
        .width('100%')
        .height('100%')
        .justifyContent(FlexAlign.Center)
        .alignItems(HorizontalAlign.Center)
        .backgroundColor('#F5F5F5')
      } else if (this.errorMessage.length > 0) {
        // 错误状态
        Column({ space: 16 }) {
          Image($r('app.media.ic_error'))
            .width(80)
            .height(80)
            .fillColor(Color.Red)
          
          Text('加载失败')
            .fontSize(18)
            .fontWeight(FontWeight.Bold)
            .fontColor(Color.Red)
          
          Text(this.errorMessage)
            .fontSize(14)
            .fontColor(Color.Gray)
            .maxLines(3)
            .textAlign(TextAlign.Center)
            .width('80%')
          
          Button('重试')
            .fontSize(14)
            .onClick(() => {
              this.initializeReaderSession();
            })
        }
        .width('100%')
        .height('100%')
        .justifyContent(FlexAlign.Center)
        .alignItems(HorizontalAlign.Center)
        .backgroundColor(Color.White)
        .padding(20)
      } else {
        // 阅读器视图
        Column() {
        ReadPageComponent({
          controller: this.readerController,
          readerCallback: (err: BusinessError, data: readerCore.ReaderComponentController) => {
            this.readerController = data;
            this.controllerReady = true;
            this.tryStartReading();
          }
        })
      }
      .width('100%')
      .height('100%')
    }
  }
    .width('100%')
    .height('100%')
  }

  /**
   * 构建降级阅读器视图（当 Reader Kit 不可用时）
   */
  @Builder
  buildFallbackReaderView() {
    Scroll() {
      Column({ space: 16 }) {
        Text('Reader Kit 阅读器（待集成）')
          .fontSize(16)
          .fontColor(Color.Gray)
          .textAlign(TextAlign.Center)
          .padding(20)
        
        Text(`当前正在阅读：${this.ebook.metadata.title}`)
          .fontSize(14)
          .fontColor(Color.Gray)
          .textAlign(TextAlign.Center)
        
        // 章节内容区域
        this.buildChapterContent()
        
        // 章节导航
        Row({ space: 20 }) {
          Button('上一章')
            .fontSize(14)
            .height(40)
            .enabled(this.currentChapterIndex > 0)
            .onClick(() => {
              if (this.currentChapterIndex > 0) {
                this.jumpToChapter(this.currentChapterIndex - 1);
              }
            })
          
          Text(`${this.currentChapterIndex + 1} / ${this.ebook.chapters.length}`)
            .fontSize(14)
            .fontColor(this.textColor)
          
          Button('下一章')
            .fontSize(14)
            .height(40)
            .enabled(this.currentChapterIndex < this.ebook.chapters.length - 1)
            .onClick(() => {
              if (this.currentChapterIndex < this.ebook.chapters.length - 1) {
                this.jumpToChapter(this.currentChapterIndex + 1);
              }
            })
        }
        .width('100%')
        .justifyContent(FlexAlign.SpaceEvenly)
        .padding({ top: 40, bottom: 40 })
      }
      .width('100%')
      .padding({ left: this.pageMargin, right: this.pageMargin })
    }
    .width('100%')
    .height('100%')
    .scrollBar(BarState.Auto)
    .edgeEffect(EdgeEffect.Spring)
  }

  /**
   * 构建章节内容
   */
  @Builder
  buildChapterContent() {
    if (this.ebook.chapters && this.ebook.chapters.length > 0 && 
        this.currentChapterIndex < this.ebook.chapters.length) {
      Column() {
        Text(this.ebook.chapters[this.currentChapterIndex].title)
          .fontSize(this.fontSize + 2)
          .fontWeight(FontWeight.Bold)
          .fontColor(this.textColor)
          .width('100%')
          .textAlign(TextAlign.Center)
          .padding({ top: 20, bottom: 10 })
        
        Text(this.ebook.chapters[this.currentChapterIndex].content)
          .fontSize(this.fontSize)
          .lineHeight(this.fontSize * this.lineHeight)
          .fontColor(this.textColor)
          .width('100%')
          .textAlign(TextAlign.Start)
      }
    }
  }
}



