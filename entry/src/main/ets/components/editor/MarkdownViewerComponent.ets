import { SafeUtils } from '../../Utils/SafeUtils';
/**
 * Markdown预览组件
 * 基于WebView + marked.js实现
 * 支持完整的Markdown语法，包括GFM扩展
 */

import { webview } from '@kit.ArkWeb';
import { logger } from '../../Utils/Logger';

const TAG = 'MarkdownViewerComponent';

/**
 * 预览主题
 */
export enum MarkdownTheme {
  DARK = 'dark',
  LIGHT = 'light'
}

/**
 * 目录项
 */
export interface TocItem {
  level: number;
  text: string;
  id: string;
}

export interface MarkdownReaderStyle {
  fontSize: number;
  lineHeight: number;
  fontFamily: string;
  fontWeight: number;
  textColor: string;
  backgroundColor: string;
  pageMargin: number;
  pageTopMargin: number;
  pageBottomMargin: number;
  letterSpacing: number;
  paragraphSpacing: number;
  firstLineIndent: number;
  textAlignment: string;
  pageMode: string;
  pageTurnAnimation: string;
  tapToTurn: boolean;
}

export interface MarkdownPageTurnResult {
  moved: boolean;
  boundary: string;
  progress: number;
  scrollTop: number;
  maxScrollTop: number;
}

export interface MarkdownProgressSnapshot {
  progress: number;
  scrollTop: number;
  maxScrollTop: number;
  currentPage: number;
  pageCount: number;
}

export const DEFAULT_MARKDOWN_READER_STYLE: MarkdownReaderStyle = {
  fontSize: 16,
  lineHeight: 1.6,
  fontFamily: 'HarmonyOS Sans',
  fontWeight: 400,
  textColor: '#24292F',
  backgroundColor: '#FFFFFF',
  pageMargin: 16,
  pageTopMargin: 24,
  pageBottomMargin: 24,
  letterSpacing: 0,
  paragraphSpacing: 8,
  firstLineIndent: 0,
  textAlignment: 'LEFT',
  pageMode: '0',
  pageTurnAnimation: 'SLIDE',
  tapToTurn: true
};

/**
 * Markdown预览控制器接口
 */
export interface MarkdownViewerController {
  renderMarkdown: (markdown: string) => void;
  setTheme: (theme: MarkdownTheme) => void;
  setFontSize: (size: number) => void;
  applyReaderStyle: (style: MarkdownReaderStyle) => void;
  scrollToProgress: (progress: number) => void;
  getScrollSnapshot: () => Promise<MarkdownProgressSnapshot>;
  turnPage: (forward: boolean) => Promise<MarkdownPageTurnResult>;
  scrollToHeading: (id: string) => void;
  isControllerReady: () => boolean;
}

/**
 * 预览回调
 */
export interface MarkdownViewerCallbacks {
  onReady?: (controller: MarkdownViewerController) => void;
  onRenderComplete?: () => void;
  onLinkClick?: (url: string) => void;
  onReaderTap?: (zone: string) => void;
  onProgressChange?: (progress: number) => void;
  onTocGenerated?: (toc: TocItem[]) => void;
}

@Component
export struct MarkdownViewerComponent {
  @Prop @Watch('onContentChange') content: string = '';
  @Prop @Watch('onThemeChange') theme: MarkdownTheme = MarkdownTheme.DARK;
  @Prop @Watch('onFontSizeChange') fontSize: number = 16;
  @Prop @Watch('onReaderStyleChange') readerStyle: MarkdownReaderStyle = DEFAULT_MARKDOWN_READER_STYLE;
  @Prop callbacks: MarkdownViewerCallbacks = {};
  
  @State private isReady: boolean = false;
  @State private isLoading: boolean = true;
  
  private webController: webview.WebviewController = new webview.WebviewController();
  private pendingContent: string = '';

  private onContentChange(): void {
    logger.info(TAG, `Markdown内容已更新，长度: ${this.content?.length || 0}`);
    if (this.isReady) {
      this.renderMarkdown(this.content);
    } else {
      this.pendingContent = this.content;
    }
  }

  private onThemeChange(): void {
    if (this.isReady) {
      this.setTheme(this.theme);
    }
  }
  
  aboutToAppear(): void {
    logger.info(TAG, 'Markdown预览组件初始化');
    this.pendingContent = this.content;
  }
  
  aboutToDisappear(): void {
    logger.info(TAG, 'Markdown预览组件销毁');
  }
  
  /**
   * 字号变化回调
   */
  private onFontSizeChange(): void {
    if (this.isReady) {
      this.setFontSize(this.fontSize);
    }
  }

  private onReaderStyleChange(): void {
    if (this.isReady) {
      this.applyReaderStyle(this.readerStyle);
    }
  }

  /**
   * 渲染Markdown内容
   */
  public renderMarkdown(markdown: string): void {
    if (this.isReady) {
      try {
        const escapedContent = JSON.stringify(markdown || '');
        this.webController.runJavaScript(`renderMarkdown(${escapedContent})`);
      } catch (e) {
        logger.error(TAG, `执行renderMarkdown失败: ${e}`);
      }
    } else {
      this.pendingContent = markdown;
    }
  }
  
  /**
   * 设置主题
   */
  public setTheme(theme: MarkdownTheme): void {
    if (this.isReady) {
      this.webController.runJavaScript(`setTheme("${theme}")`);
    }
  }
  
  /**
   * 设置字体大小
   */
  public setFontSize(size: number): void {
    if (this.isReady) {
      this.webController.runJavaScript(`setFontSize(${size})`);
    }
  }

  public applyReaderStyle(style: MarkdownReaderStyle): void {
    if (this.isReady) {
      try {
        const styleJson = JSON.stringify(style);
        this.webController.runJavaScript(`applyReaderStyle(${styleJson})`);
      } catch (e) {
        logger.error(TAG, `应用Markdown阅读样式失败: ${String(e)}`);
      }
    }
  }

  public scrollToProgress(progress: number): void {
    if (this.isReady) {
      const safeProgress = Number.isFinite(progress) ? Math.max(0, Math.min(100, progress)) : 0;
      this.webController.runJavaScript(`scrollToReaderProgress(${safeProgress})`);
    }
  }

  public async getScrollSnapshot(): Promise<MarkdownProgressSnapshot> {
    if (!this.isReady) {
      return this.createDefaultProgressSnapshot();
    }
    try {
      const rawResult = await this.webController.runJavaScript('getReaderScrollSnapshot()');
      return this.parseProgressSnapshot(rawResult);
    } catch (e) {
      logger.error(TAG, `获取Markdown滚动快照失败: ${String(e)}`);
      return this.createDefaultProgressSnapshot();
    }
  }

  public async turnPage(forward: boolean): Promise<MarkdownPageTurnResult> {
    if (!this.isReady) {
      return this.createDefaultPageTurnResult('not_ready');
    }
    try {
      const rawResult = await this.webController.runJavaScript(`turnReaderPage(${forward ? 'true' : 'false'})`);
      return this.parsePageTurnResult(rawResult);
    } catch (e) {
      logger.error(TAG, `Markdown翻页失败: ${String(e)}`);
      return this.createDefaultPageTurnResult('error');
    }
  }
  
  /**
   * 滚动到指定位置
   */
  public scrollTo(position: number): void {
    if (this.isReady) {
      this.webController.runJavaScript(`scrollTo(${position})`);
    }
  }
  
  /**
   * 滚动到指定标题
   */
  public scrollToHeading(id: string): void {
    if (this.isReady) {
      this.webController.runJavaScript(`scrollToHeading("${id}")`);
    }
  }
  
  /**
   * 获取目录
   */
  public async getTableOfContents(): Promise<TocItem[]> {
    if (!this.isReady) return [];
    try {
      const result = await this.webController.runJavaScript('getTableOfContents()');
      return SafeUtils.parseArr(result as string) as TocItem[];
    } catch (e) {
      logger.error(TAG, `获取目录失败: ${e}`);
      return [];
    }
  }
  
  /**
   * 转义字符串用于JavaScript (已废弃，改用JSON.stringify)
   */
  private escapeForJs(str: string): string {
    return str;
  }

  private parseWebViewJson(raw: string): string {
    if (raw.startsWith('"') && raw.endsWith('"')) {
      try {
        return SafeUtils.parseStr(raw) as string;
      } catch (_error) {
        return raw;
      }
    }
    return raw;
  }

  private createDefaultPageTurnResult(boundary: string): MarkdownPageTurnResult {
    return {
      moved: false,
      boundary: boundary,
      progress: 0,
      scrollTop: 0,
      maxScrollTop: 0
    };
  }

  private parsePageTurnResult(raw: string): MarkdownPageTurnResult {
    try {
      const clean = this.parseWebViewJson(raw);
      const parsed = SafeUtils.parseObj(clean) as MarkdownPageTurnResult;
      const progress = Number(parsed.progress);
      const scrollTop = Number(parsed.scrollTop);
      const maxScrollTop = Number(parsed.maxScrollTop);
      return {
        moved: parsed.moved === true,
        boundary: parsed.boundary ? String(parsed.boundary) : '',
        progress: Number.isFinite(progress) ? Math.max(0, Math.min(100, progress)) : 0,
        scrollTop: Number.isFinite(scrollTop) ? Math.max(0, scrollTop) : 0,
        maxScrollTop: Number.isFinite(maxScrollTop) ? Math.max(0, maxScrollTop) : 0
      };
    } catch (_error) {
      return this.createDefaultPageTurnResult('parse_error');
    }
  }

  private createDefaultProgressSnapshot(): MarkdownProgressSnapshot {
    return {
      progress: 0,
      scrollTop: 0,
      maxScrollTop: 0,
      currentPage: 1,
      pageCount: 1
    };
  }

  private parseProgressSnapshot(raw: string): MarkdownProgressSnapshot {
    try {
      const clean = this.parseWebViewJson(raw);
      const parsed = SafeUtils.parseObj(clean) as MarkdownProgressSnapshot;
      const progress = Number(parsed.progress);
      const scrollTop = Number(parsed.scrollTop);
      const maxScrollTop = Number(parsed.maxScrollTop);
      const currentPage = Number(parsed.currentPage);
      const pageCount = Number(parsed.pageCount);
      return {
        progress: Number.isFinite(progress) ? Math.max(0, Math.min(100, progress)) : 0,
        scrollTop: Number.isFinite(scrollTop) ? Math.max(0, scrollTop) : 0,
        maxScrollTop: Number.isFinite(maxScrollTop) ? Math.max(0, maxScrollTop) : 0,
        currentPage: Number.isFinite(currentPage) ? Math.max(1, Math.floor(currentPage)) : 1,
        pageCount: Number.isFinite(pageCount) ? Math.max(1, Math.floor(pageCount)) : 1
      };
    } catch (_error) {
      return this.createDefaultProgressSnapshot();
    }
  }
  
  /**
   * 处理页面就绪
   */
  private onPageReady(): void {
    if (this.isReady) return; // 防止重复触发
    logger.info(TAG, '预览页面就绪');
    this.isReady = true;
    this.isLoading = false;
    
    // 应用配置
    this.setTheme(this.theme);
    this.setFontSize(this.fontSize);
    this.applyReaderStyle(this.readerStyle);
    
    // 渲染待处理的内容
    if (this.pendingContent) {
      this.renderMarkdown(this.pendingContent);
    }
    
    // 创建控制器并回调
    if (this.callbacks.onReady) {
      const controller: MarkdownViewerController = {
        renderMarkdown: (markdown: string) => this.renderMarkdown(markdown),
        setTheme: (theme: MarkdownTheme) => this.setTheme(theme),
        setFontSize: (size: number) => this.setFontSize(size),
        applyReaderStyle: (style: MarkdownReaderStyle) => this.applyReaderStyle(style),
        scrollToProgress: (progress: number) => this.scrollToProgress(progress),
        getScrollSnapshot: (): Promise<MarkdownProgressSnapshot> => this.getScrollSnapshot(),
        turnPage: (forward: boolean): Promise<MarkdownPageTurnResult> => this.turnPage(forward),
        scrollToHeading: (id: string) => this.scrollToHeading(id),
        isControllerReady: (): boolean => this.isReady
      };
      this.callbacks.onReady(controller);
    }
  }
  
  /**
   * 处理渲染完成
   */
  private async onRenderComplete(): Promise<void> {
    logger.info(TAG, '渲染完成');
    
    // 获取目录
    if (this.callbacks.onTocGenerated) {
      const toc = await this.getTableOfContents();
      this.callbacks.onTocGenerated(toc);
    }
    
    // 回调
    if (this.callbacks.onRenderComplete) {
      this.callbacks.onRenderComplete();
    }
  }
  
  /**
   * 处理链接点击
   */
  private onLinkClick(url: string): void {
    logger.info(TAG, `链接点击: ${url}`);
    if (this.callbacks.onLinkClick) {
      this.callbacks.onLinkClick(url);
    }
  }

  private onReaderTap(zone: string): void {
    logger.debug(TAG, `阅读区点击: ${zone}`);
    if (this.callbacks.onReaderTap) {
      this.callbacks.onReaderTap(zone);
    }
  }

  private onProgressChange(progress: number): void {
    if (this.callbacks.onProgressChange) {
      const safeProgress = Number.isFinite(progress) ? Math.max(0, Math.min(100, progress)) : 0;
      this.callbacks.onProgressChange(safeProgress);
    }
  }
  
  build() {
    Stack() {
      Web({
        src: $rawfile('code_editor/markdown_preview.html'),
        controller: this.webController
      })
        .backgroundColor(Color.Transparent)
        .width('100%')
        .height('100%')
        .javaScriptAccess(true)
        .domStorageAccess(true)
        .fileAccess(true)
        .mixedMode(MixedMode.All)
        .onPageEnd(() => {
          logger.info(TAG, '页面加载完成，尝试触发onPageReady');
          this.onPageReady();
        })
        .onErrorReceive((event) => {
          logger.error(TAG, `加载错误: ${event?.error?.getErrorInfo()}`);
        })
        .onConsole((event) => {
          if (event && event.message) {
            logger.info(TAG, `Web Console [${event.message.getMessageLevel()}]: ${event.message.getMessage()}`);
          }
          return false;
        })
        .javaScriptProxy({
          object: {
            onPageReady: () => {
              this.onPageReady();
            },
            onRenderComplete: () => {
              this.onRenderComplete();
            },
            onLinkClick: (url: string) => {
              this.onLinkClick(url);
            },
            onReaderTap: (zone: string) => {
              this.onReaderTap(zone);
            },
            onProgressChange: (progress: number) => {
              this.onProgressChange(progress);
            }
          },
          name: 'arkts',
          methodList: ['onPageReady', 'onRenderComplete', 'onLinkClick', 'onReaderTap', 'onProgressChange'],
          controller: this.webController
        })
      
      // 加载指示器
      if (this.isLoading) {
        Column() {
          LoadingProgress()
            .width(40)
            .height(40)
            .color('#888888')
          Text('加载预览...')
            .fontSize(14)
            .fontColor('#888888')
            .margin({ top: 8 })
        }
        .width('100%')
        .height('100%')
        .justifyContent(FlexAlign.Center)
        .backgroundColor(Color.Transparent)
      }
    }
    .width('100%')
    .height('100%')
  }
}
