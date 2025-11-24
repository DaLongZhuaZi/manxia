// 文件路径: entry/src/main/ets/pages/EBookReaderPage.ets
/**
 * 电子书阅读器页面
 * 支持TXT、EPUB等格式的电子书阅读
 */

import { logger } from '../Utils/Logger';
import { ThemeAwareState, ThemeAwareHelper } from '../Framework/Components/ThemeAware';
import { ThemeType } from '../Framework/Managers/ThemeManager';
import { EBook, EBookChapter, EBookReadingProgress, EBookReadingSettings, EBookPageMode, EBookFormat } from '../Models/EBookModels';
import { EBookDataManager } from '../Framework/Data/EBookDataManager';
import { PdfViewerComponent } from '../Framework/Components/PdfViewerComponent';
import { ReaderKitViewerComponent } from '../Framework/Components/ReaderKitViewerComponent';
import { EBookReadingSettingsPanel } from '../Framework/Components/EBookReadingSettingsPanel';

const TAG = 'EBookReaderPage';

/**
 * 阅读器页面参数
 */
export interface EBookReaderParams {
  bookId: string;
}

@Component
struct EBookReaderPage {
  @State pathStack: NavPathStack = new NavPathStack();
  @State themeState: ThemeAwareState = new ThemeAwareState();
  private componentId: string = 'EBookReaderPage';

  // 沉浸式显示状态
  @StorageProp('statusBarHeight') statusBarHeight: number = 0;
  @StorageProp('navigationBarHeight') navigationBarHeight: number = 0;

  // 电子书数据
  @State ebook: EBook | null = null;
  @State currentChapter: EBookChapter | null = null;
  @State currentChapterIndex: number = 0;
  @State isLoading: boolean = true;
  @State errorMessage: string = '';

  // 阅读设置
  @State fontSize: number = 18;
  @State lineHeight: number = 1.8;
  @State bgColor: string = '#FFFFFF'; // 重命名避免与组件属性冲突
  @State textColor: string = '#333333';
  @State pageMargin: number = 20;
  @State showToolbar: boolean = false;
  @State showSettingsPanel: boolean = false;

  // 数据管理器
  private ebookDataManager: EBookDataManager = EBookDataManager.getInstance();

  aboutToAppear(): void {
    ThemeAwareHelper.initializeThemeAware(this.componentId, this.themeState, (theme: ThemeType) => {
      logger.info(TAG, `主题切换到: ${theme}`);
    });
  }

  aboutToDisappear(): void {
    ThemeAwareHelper.cleanupThemeAware(this.componentId);
    // 保存阅读进度
    this.saveReadingProgress();
  }

  /**
   * 加载电子书
   */
  private async loadEBook(bookId: string): Promise<void> {
    try {
      this.isLoading = true;
      this.errorMessage = '';

      logger.info(TAG, `开始加载电子书: ${bookId}`);
      
      // 从数据库加载电子书
      const ebook = await this.ebookDataManager.getEBookById(bookId);
      
      if (!ebook) {
        throw new Error('电子书不存在');
      }

      this.ebook = ebook;
      
      // 加载阅读设置
      if (ebook.readingSettings) {
        this.fontSize = ebook.readingSettings.fontSize;
        this.lineHeight = ebook.readingSettings.lineHeight;
        this.bgColor = ebook.readingSettings.backgroundColor;
        this.textColor = ebook.readingSettings.textColor;
        this.pageMargin = ebook.readingSettings.pageMargin;
      }

      // 定位到上次阅读位置
      if (ebook.readingProgress && ebook.readingProgress.currentChapterId) {
        const chapterIndex = ebook.chapters.findIndex(
          (ch: EBookChapter) => ch.id === ebook.readingProgress.currentChapterId
        );
        if (chapterIndex >= 0) {
          this.currentChapterIndex = chapterIndex;
        }
      }

      // 加载当前章节
      this.currentChapter = ebook.chapters[this.currentChapterIndex];

      this.isLoading = false;
      logger.info(TAG, `电子书加载完成: ${ebook.metadata.title}`);
      
    } catch (error) {
      this.errorMessage = `加载失败: ${String(error instanceof Error ? error.message : error)}`;
      this.isLoading = false;
      logger.error(TAG, '加载电子书失败', String(error instanceof Error ? error.message : error));
    }
  }

  /**
   * 切换到上一章
   */
  private previousChapter(): void {
    if (!this.ebook || this.currentChapterIndex <= 0) {
      logger.warn(TAG, '已经是第一章');
      return;
    }

    this.currentChapterIndex--;
    this.currentChapter = this.ebook.chapters[this.currentChapterIndex];
    this.saveReadingProgress();
    logger.info(TAG, `切换到上一章: ${this.currentChapter?.title}`);
  }

  /**
   * 切换到下一章
   */
  private nextChapter(): void {
    if (!this.ebook || this.currentChapterIndex >= this.ebook.chapters.length - 1) {
      logger.warn(TAG, '已经是最后一章');
      return;
    }

    this.currentChapterIndex++;
    this.currentChapter = this.ebook.chapters[this.currentChapterIndex];
    this.saveReadingProgress();
    logger.info(TAG, `切换到下一章: ${this.currentChapter?.title}`);
  }

  /**
   * 更新阅读设置
   */
  private async updateReadingSettings(settings: EBookReadingSettings): Promise<void> {
    if (!this.ebook) {
      return;
    }

    try {
      // 更新本地状态
      this.fontSize = settings.fontSize;
      this.lineHeight = settings.lineHeight;
      this.bgColor = settings.backgroundColor;
      this.textColor = settings.textColor;
      this.pageMargin = settings.pageMargin;

      // 更新电子书设置
      this.ebook.readingSettings = settings;

      // 保存到数据库
      await this.ebookDataManager.saveReadingSettings(this.ebook.id, settings);
      logger.info(TAG, '阅读设置已保存');
    } catch (error) {
      logger.error(TAG, `保存阅读设置失败: ${String(error)}`);
    }
  }

  /**
   * 保存阅读进度
   */
  private async saveReadingProgress(): Promise<void> {
    if (!this.ebook || !this.currentChapter) {
      return;
    }

    try {
      const progress: EBookReadingProgress = {
        bookId: this.ebook.id,
        currentChapterId: this.currentChapter.id,
        currentPosition: 0,
        progress: (this.currentChapterIndex / this.ebook.chapters.length) * 100,
        lastReadTime: Date.now(),
        totalReadingTime: 0
      };

      await this.ebookDataManager.saveReadingProgress(progress);
      logger.debug(TAG, '阅读进度已保存');
    } catch (error) {
      logger.error(TAG, '保存阅读进度失败', String(error instanceof Error ? error.message : error));
    }
  }

  /**
   * 调整字体大小
   */
  private adjustFontSize(delta: number): void {
    this.fontSize = Math.max(12, Math.min(32, this.fontSize + delta));
    logger.debug(TAG, `字体大小调整为: ${this.fontSize}`);
  }

  build() {
    NavDestination() {
      Stack() {
        // 背景层
        Column()
          .width('100%')
          .height('100%')
          .backgroundColor(this.bgColor)
          .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.TOP, SafeAreaEdge.BOTTOM])

        // 内容层
        if (this.isLoading) {
          this.buildLoadingView()
        } else if (this.errorMessage) {
          this.buildErrorView()
        } else if (this.ebook && this.currentChapter) {
          this.buildReaderView()
        }

        // 工具栏（覆盖在内容上）
        if (this.showToolbar) {
          this.buildToolbar()
        }

        // 阅读设置面板
        if (this.showSettingsPanel && this.ebook) {
          EBookReadingSettingsPanel({
            settings: this.ebook.readingSettings,
            onSettingsChange: (settings: EBookReadingSettings) => {
              this.updateReadingSettings(settings);
            },
            onClose: () => {
              this.showSettingsPanel = false;
            }
          })
        }
      }
      .width('100%')
      .height('100%')
      .onClick(() => {
        // 点击切换工具栏显示
        if (!this.showSettingsPanel) {
          this.showToolbar = !this.showToolbar;
        }
      })
    }
    .onReady((context: NavDestinationContext) => {
      logger.info(TAG, 'EBookReaderPage onReady');
      this.pathStack = context.pathStack;
      
      // 使用类型断言获取参数
      const params = context.pathInfo.param as EBookReaderParams | null;
      if (params && params.bookId) {
        this.loadEBook(params.bookId);
      } else {
        this.errorMessage = '缺少电子书ID参数';
        logger.error(TAG, '缺少电子书ID参数');
      }
    })
    .hideTitleBar(true)
    .backgroundColor(Color.Transparent)
  }

  /**
   * 构建加载视图
   */
  @Builder
  buildLoadingView() {
    Column() {
      LoadingProgress()
        .width(50)
        .height(50)
        .color(ThemeAwareHelper.getTestManagementThemedColor('accent_primary', this.themeState.currentTheme))

      Text('加载中...')
        .fontSize(16)
        .fontColor(this.textColor)
        .margin({ top: 16 })
    }
    .width('100%')
    .height('100%')
    .justifyContent(FlexAlign.Center)
    .alignItems(HorizontalAlign.Center)
    .padding({ top: this.statusBarHeight, bottom: this.navigationBarHeight })
  }

  /**
   * 构建错误视图
   */
  @Builder
  buildErrorView() {
    Column({ space: 16 }) {
      Text('❌')
        .fontSize(48)

      Text(this.errorMessage)
        .fontSize(16)
        .fontColor(this.textColor)
        .textAlign(TextAlign.Center)

      Button('返回')
        .fontSize(16)
        .onClick(() => {
          this.pathStack.pop();
        })
    }
    .width('100%')
    .height('100%')
    .justifyContent(FlexAlign.Center)
    .alignItems(HorizontalAlign.Center)
    .padding({ top: this.statusBarHeight, bottom: this.navigationBarHeight })
  }

  /**
   * 构建阅读器视图
   */
  @Builder
  buildReaderView() {
    if (this.ebook) {
      // 根据格式选择合适的阅读器
      if (this.ebook.format === EBookFormat.PDF) {
        // PDF格式：使用 Web 组件预览
        this.buildPdfReaderView();
      } else if (this.isReaderKitSupported(this.ebook.format)) {
        // EPUB/MOBI/AZW 格式：使用 Reader Kit 阅读器
        this.buildReaderKitView();
      } else {
        // TXT 等其他格式：使用文本阅读器
        this.buildTextReaderView();
      }
    }
  }

  /**
   * 检查格式是否支持 Reader Kit
   */
  private isReaderKitSupported(format: EBookFormat): boolean {
    const supportedFormats = [
      EBookFormat.EPUB,
      EBookFormat.MOBI,
      EBookFormat.AZW,
      EBookFormat.AZW3
    ];
    return supportedFormats.includes(format);
  }

  /**
   * 构建 Reader Kit 阅读器视图
   */
  @Builder
  buildReaderKitView() {
    if (this.ebook) {
      Stack() {
      // Reader Kit 阅读器组件
      ReaderKitViewerComponent({
        ebook: this.ebook,
        currentChapterIndex: this.currentChapterIndex,
        onChapterChange: (index: number) => {
          this.currentChapterIndex = index;
          this.currentChapter = this.ebook ? this.ebook.chapters[index] : null;
          this.saveReadingProgress();
        },
        onProgressChange: (progress: number) => {
          logger.debug(TAG, `阅读进度更新: ${progress}%`);
        }
      })

      // 顶部工具栏
      if (this.showToolbar) {
        Column() {
          Row({ space: 12 }) {
            Button('返回')
              .fontSize(16)
              .height(40)
              .backgroundColor(Color.White)
              .fontColor(Color.Black)
              .onClick(() => {
                this.pathStack.pop();
              })

            Blank()

            Text(this.ebook?.metadata.title || '')
              .fontSize(16)
              .fontColor(Color.White)
              .maxLines(1)
              .textOverflow({ overflow: TextOverflow.Ellipsis })
          }
          .width('100%')
          .padding(16)
          .backgroundColor('#CC000000')
        }
          .width('100%')
          .position({ x: 0, y: this.statusBarHeight })
        }
      }
      .width('100%')
      .height('100%')
    }
  }

  /**
   * 构建PDF阅读器视图
   */
  @Builder
  buildPdfReaderView() {
    Stack() {
      // PDF预览组件
      if (this.currentChapter && this.currentChapter.content) {
        PdfViewerComponent({
          filePath: this.currentChapter.content,
          onLoadFinished: () => {
            logger.info(TAG, 'PDF加载完成');
          },
          onLoadError: (errorMsg: string) => {
            logger.error(TAG, `PDF加载失败: ${errorMsg}`);
            this.errorMessage = errorMsg;
          }
        })
      }

      // 顶部工具栏（返回按钮等）
      if (this.showToolbar) {
        Column() {
          Row({ space: 12 }) {
            Button('返回')
              .fontSize(16)
              .height(40)
              .backgroundColor(Color.White)
              .fontColor(Color.Black)
              .onClick(() => {
                this.pathStack.pop();
              })

            Blank()

            Text(this.ebook?.metadata.title || '')
              .fontSize(16)
              .fontColor(Color.White)
              .maxLines(1)
              .textOverflow({ overflow: TextOverflow.Ellipsis })
          }
          .width('100%')
          .padding(16)
          .backgroundColor('#CC000000')
        }
        .width('100%')
        .position({ x: 0, y: this.statusBarHeight })
      }
    }
    .width('100%')
    .height('100%')
  }

  /**
   * 构建文本阅读器视图
   */
  @Builder
  buildTextReaderView() {
    Scroll() {
      Column({ space: 24 }) {
        // 章节标题
        Text(this.currentChapter?.title || '')
          .fontSize(this.fontSize + 4)
          .fontWeight(FontWeight.Bold)
          .fontColor(this.textColor)
          .width('100%')
          .textAlign(TextAlign.Center)
          .padding({ top: 20, bottom: 10 })

        // 章节内容
        Text(this.currentChapter?.content || '')
          .fontSize(this.fontSize)
          .lineHeight(this.fontSize * this.lineHeight)
          .fontColor(this.textColor)
          .width('100%')
          .textAlign(TextAlign.Start)

        // 底部导航
        Row({ space: 20 }) {
          Button('上一章')
            .fontSize(14)
            .height(40)
            .enabled(this.currentChapterIndex > 0)
            .onClick(() => {
              this.previousChapter();
            })

          Text(`${this.currentChapterIndex + 1} / ${this.ebook?.chapters.length || 0}`)
            .fontSize(14)
            .fontColor(this.textColor)

          Button('下一章')
            .fontSize(14)
            .height(40)
            .enabled(this.currentChapterIndex < (this.ebook?.chapters.length || 0) - 1)
            .onClick(() => {
              this.nextChapter();
            })
        }
        .width('100%')
        .justifyContent(FlexAlign.SpaceEvenly)
        .padding({ top: 40, bottom: 40 })
      }
      .width('100%')
      .padding({
        left: this.pageMargin,
        right: this.pageMargin,
        top: this.statusBarHeight + 20,
        bottom: this.navigationBarHeight + 20
      })
    }
    .width('100%')
    .height('100%')
    .scrollBar(BarState.Auto)
    .edgeEffect(EdgeEffect.Spring)
  }

  /**
   * 构建工具栏
   */
  @Builder
  buildToolbar() {
    Column({ space: 0 }) {
      // 顶部工具栏
      Row({ space: 16 }) {
        Button('返回')
          .fontSize(14)
          .height(40)
          .onClick(() => {
            this.pathStack.pop();
          })

        Text(this.ebook?.metadata.title || '')
          .fontSize(16)
          .fontWeight(FontWeight.Medium)
          .fontColor('#FFFFFF')
          .layoutWeight(1)
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
      }
      .width('100%')
      .padding({ left: 16, right: 16, top: this.statusBarHeight + 10, bottom: 10 })
      .backgroundColor('rgba(0, 0, 0, 0.8)')

      Blank().layoutWeight(1)

      // 底部工具栏
      Column({ space: 12 }) {
        // 字体大小调整
        Row({ space: 16 }) {
          Text('字体大小')
            .fontSize(14)
            .fontColor('#FFFFFF')

          Button('-')
            .fontSize(16)
            .width(40)
            .height(40)
            .onClick(() => {
              this.adjustFontSize(-2);
            })

          Text(`${this.fontSize}`)
            .fontSize(14)
            .fontColor('#FFFFFF')

          Button('+')
            .fontSize(16)
            .width(40)
            .height(40)
            .onClick(() => {
              this.adjustFontSize(2);
            })
        }
        .width('100%')
        .justifyContent(FlexAlign.Center)

        // 进度条
        Row({ space: 8 }) {
          Text(`${this.currentChapterIndex + 1}`)
            .fontSize(12)
            .fontColor('#FFFFFF')

          Slider({
            value: this.currentChapterIndex,
            min: 0,
            max: (this.ebook?.chapters.length || 1) - 1,
            step: 1,
            style: SliderStyle.OutSet
          })
            .layoutWeight(1)
            .trackColor('#444444')
            .selectedColor('#FFFFFF')
            .onChange((value: number) => {
              this.currentChapterIndex = Math.floor(value);
              this.currentChapter = this.ebook?.chapters[this.currentChapterIndex] || null;
            })

          Text(`${this.ebook?.chapters.length || 0}`)
            .fontSize(12)
            .fontColor('#FFFFFF')
        }
        .width('100%')
        .padding({ left: 16, right: 16 })
      }
      .width('100%')
      .padding({ left: 16, right: 16, top: 12, bottom: this.navigationBarHeight + 12 })
      .backgroundColor('rgba(0, 0, 0, 0.8)')
    }
    .width('100%')
    .height('100%')
  }
}

export { EBookReaderPage };

