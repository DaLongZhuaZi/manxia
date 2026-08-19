import { logger } from 'manxia_core/src/main/ets/Utils/Logger';
import { EBookReaderPage } from './EBookReaderPage';
import { EBookImageReaderPage } from './EBookImageReaderPage';
import { EpubWebViewReaderPage } from './EpubWebViewReaderPage';
import { EBookReaderParams } from './EBookReaderRouteTypes';
import { EBookDataManager } from '../Framework/Data/EBookDataManager';
import { resolveEBookReaderRouteName } from '../Framework/Adapters/EBookImageReaderAdapter';
import { EBookParserFactory } from '../Framework/Parsers/EBookParser';
import {
  EBook,
  EBookChapter,
  EBookFormat,
  EBookReaderEngine
} from '../Models/EBookModels';

const TAG = 'EBookReaderRoutePage';

@Entry
@Component
struct EBookReaderRoutePage {
  build() {
    Column() {
      EBookReaderRoutePageContent()
    }
    .width('100%')
    .height('100%')
  }
}

@Component
export struct EBookReaderRoutePageContent {
  @State private pathStack: NavPathStack = new NavPathStack();
  private hasOpenedReader: boolean = false;
  private ebookDataManager: EBookDataManager = EBookDataManager.getInstance();

  aboutToAppear(): void {
    void this.openInitialReader();
  }

  private resolveRouteParams(): EBookReaderParams | null {
    try {
      const stack = AppStorage.get<NavPathStack>('GlobalNavStack');
      if (stack) {
        const paramArray = stack.getParamByName('EBookReaderRoutePage') as EBookReaderParams[];
        if (paramArray && paramArray.length > 0) {
          const navParams = paramArray[paramArray.length - 1];
          if (navParams && navParams.bookId) {
            return {
              bookId: navParams.bookId,
              coverComponentId: navParams.coverComponentId || '',
              routerBackOnClose: false,
              forceReaderKit: navParams.forceReaderKit === true,
              autoStartReadAloud: navParams.autoStartReadAloud === true,
              autoOpenReadAloudPlayer: navParams.autoOpenReadAloudPlayer === true,
              readerTitle: navParams.readerTitle
            };
          }
        }
      }
    } catch (error) {
      logger.warn(TAG, `读取电子书阅读器 NavPathStack 参数失败: ${String(error)}`);
    }

    const router = this.getUIContext()?.getRouter();
    if (!router) {
      logger.error(TAG, '无法获取 Router 参数：Router 不可用');
      return null;
    }
    const rawParams = router.getParams() as EBookReaderParams | null;
    if (!rawParams || !rawParams.bookId) {
      logger.error(TAG, '电子书阅读器路由参数无效');
      return null;
    }
    return {
      bookId: rawParams.bookId,
      coverComponentId: rawParams.coverComponentId || '',
      routerBackOnClose: true,
      forceReaderKit: rawParams.forceReaderKit === true,
      autoStartReadAloud: rawParams.autoStartReadAloud === true,
      autoOpenReadAloudPlayer: rawParams.autoOpenReadAloudPlayer === true,
      readerTitle: rawParams.readerTitle
    };
  }

  private async openInitialReader(): Promise<void> {
    if (this.hasOpenedReader) {
      return;
    }
    this.hasOpenedReader = true;
    const params = this.resolveRouteParams();
    if (!params) {
      return;
    }
    const routeName = await this.resolveInitialRouteName(params);
    this.pathStack.pushPathByName(routeName, params);
  }

  private async resolveInitialRouteName(params: EBookReaderParams): Promise<string> {
    if (params.forceReaderKit === true) {
      return 'EBookReaderPage';
    }
    try {
      const ebook = await this.ebookDataManager.getEBookById(params.bookId);
      if (!ebook) {
        logger.warn(TAG, `无法解析电子书阅读路由：未找到书籍 bookId=${params.bookId}`);
        return 'EBookReaderPage';
      }
      const repairedEBook = await this.repairKindleWebViewRouteIfNeeded(ebook);
      const routeName = resolveEBookReaderRouteName(repairedEBook);
      logger.info(
        TAG,
        `电子书阅读路由判定: bookId=${repairedEBook.id}, format=${repairedEBook.format}, engine=${repairedEBook.preferredReaderEngine}, extractedRootPath=${repairedEBook.extractedRootPath || ''}, route=${routeName}`
      );
      return routeName;
    } catch (error) {
      logger.warn(TAG, `解析电子书阅读路由失败，回退普通阅读页: ${String(error)}`);
      return 'EBookReaderPage';
    }
  }

  private isKindleFormat(format: EBookFormat): boolean {
    return format === EBookFormat.MOBI || format === EBookFormat.AZW || format === EBookFormat.AZW3;
  }

  private async repairKindleWebViewRouteIfNeeded(ebook: EBook): Promise<EBook> {
    if (!this.isKindleFormat(ebook.format)) {
      return ebook;
    }
    if (ebook.preferredReaderEngine === EBookReaderEngine.WEBVIEW &&
      (ebook.extractedRootPath || '').length > 0) {
      return ebook;
    }

    try {
      const parser = EBookParserFactory.createParser(ebook.filePath);
      if (!parser) {
        return ebook;
      }
      const reparsed = await parser.parse();
      if (reparsed.preferredReaderEngine !== EBookReaderEngine.WEBVIEW ||
        (reparsed.extractedRootPath || '').length <= 0) {
        return ebook;
      }

      ebook.metadata = reparsed.metadata;
      ebook.fileSize = reparsed.fileSize;
      ebook.chapters = this.rebindChapterBookId(reparsed.chapters, ebook.id);
      ebook.totalWordCount = reparsed.totalWordCount;
      ebook.contentMode = reparsed.contentMode;
      ebook.preferredReaderEngine = reparsed.preferredReaderEngine;
      ebook.extractedRootPath = reparsed.extractedRootPath;
      if (ebook.chapters.length > 0) {
        const safeIndex = Math.max(0, Math.min(ebook.readingProgress.currentChapterIndex, ebook.chapters.length - 1));
        ebook.readingProgress.currentChapterIndex = safeIndex;
        ebook.readingProgress.currentChapterId = ebook.chapters[safeIndex].id;
      }
      ebook.lastUpdateTime = Date.now();
      await this.ebookDataManager.saveEBook(ebook, { skipReadingSettings: true });
      logger.info(TAG, `Kindle 电子书已修复为 WebView 路由: bookId=${ebook.id}, chapters=${ebook.chapters.length}`);
      return ebook;
    } catch (error) {
      logger.warn(TAG, `Kindle 电子书 WebView 路由修复失败: ${String(error)}`);
      return ebook;
    }
  }

  private rebindChapterBookId(chapters: EBookChapter[], bookId: string): EBookChapter[] {
    const result: EBookChapter[] = [];
    const now = Date.now();
    for (let index = 0; index < chapters.length; index++) {
      const source = chapters[index];
      const chapter: EBookChapter = {
        id: source.id || `kindle_${bookId}_${index}`,
        bookId: bookId,
        chapterNumber: source.chapterNumber || index + 1,
        title: source.title || `第${index + 1}章`,
        content: source.content || '',
        startPosition: source.startPosition || 0,
        endPosition: source.endPosition || 0,
        wordCount: source.wordCount || 0,
        resourceHref: source.resourceHref || '',
        resourceFile: source.resourceFile || '',
        resourceMediaType: source.resourceMediaType || '',
        resourceLayoutType: source.resourceLayoutType || '',
        resourceImagePath: source.resourceImagePath || '',
        resourceImageRelativePath: source.resourceImageRelativePath || '',
        createTime: source.createTime || now
      };
      result.push(chapter);
    }
    return result;
  }

  @Builder
  private buildDestination(name: string, _param: Object) {
    if (name === 'EBookReaderPage') {
      EBookReaderPage()
    } else if (name === 'EBookImageReaderPage') {
      EBookImageReaderPage()
    } else if (name === 'EpubWebViewReaderPage') {
      EpubWebViewReaderPage()
    }
  }

  build() {
    Navigation(this.pathStack) {
      Column() {
        Blank()
      }
      .width('100%')
      .height('100%')
    }
    .hideNavBar(true)
    .navDestination(this.buildDestination)
    .mode(NavigationMode.Stack)
    .width('100%')
    .height('100%')
  }
}
