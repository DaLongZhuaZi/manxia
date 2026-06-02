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

/**
 * Markdown预览控制器接口
 */
export interface MarkdownViewerController {
  renderMarkdown: (markdown: string) => void;
  setTheme: (theme: MarkdownTheme) => void;
  setFontSize: (size: number) => void;
  scrollToHeading: (id: string) => void;
}

/**
 * 预览回调
 */
export interface MarkdownViewerCallbacks {
  onReady?: (controller: MarkdownViewerController) => void;
  onRenderComplete?: () => void;
  onLinkClick?: (url: string) => void;
  onTocGenerated?: (toc: TocItem[]) => void;
}

@Component
export struct MarkdownViewerComponent {
  @Prop content: string = '';
  @Prop theme: MarkdownTheme = MarkdownTheme.DARK;
  @Prop fontSize: number = 16;
  @Prop callbacks: MarkdownViewerCallbacks = {};
  
  @State private isReady: boolean = false;
  @State private isLoading: boolean = true;
  
  private webController: webview.WebviewController = new webview.WebviewController();
  private pendingContent: string = '';
  
  aboutToAppear(): void {
    logger.info(TAG, 'Markdown预览组件初始化');
    this.pendingContent = this.content;
  }
  
  aboutToDisappear(): void {
    logger.info(TAG, 'Markdown预览组件销毁');
  }
  
  /**
   * 渲染Markdown内容
   */
  public renderMarkdown(markdown: string): void {
    if (this.isReady) {
      const escapedContent = this.escapeForJs(markdown);
      this.webController.runJavaScript(`renderMarkdown("${escapedContent}")`);
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
   * 转义字符串用于JavaScript
   */
  private escapeForJs(str: string): string {
    return str
      .replace(/\\/g, '\\\\')
      .replace(/"/g, '\\"')
      .replace(/\n/g, '\\n')
      .replace(/\r/g, '\\r')
      .replace(/\t/g, '\\t');
  }
  
  /**
   * 处理页面就绪
   */
  private onPageReady(): void {
    logger.info(TAG, '预览页面就绪');
    this.isReady = true;
    this.isLoading = false;
    
    // 应用配置
    this.setTheme(this.theme);
    this.setFontSize(this.fontSize);
    
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
        scrollToHeading: (id: string) => this.scrollToHeading(id)
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
  
  build() {
    Stack() {
      Web({
        src: $rawfile('code_editor/markdown_preview.html'),
        controller: this.webController
      })
        .width('100%')
        .height('100%')
        .javaScriptAccess(true)
        .domStorageAccess(true)
        .fileAccess(true)
        .mixedMode(MixedMode.All)
        .onPageEnd(() => {
          logger.info(TAG, '页面加载完成');
        })
        .onErrorReceive((event) => {
          logger.error(TAG, `加载错误: ${event?.error?.getErrorInfo()}`);
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
            }
          },
          name: 'arkts',
          methodList: ['onPageReady', 'onRenderComplete', 'onLinkClick'],
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
        .backgroundColor(this.theme === MarkdownTheme.DARK ? '#0d1117' : '#ffffff')
      }
    }
    .width('100%')
    .height('100%')
  }
}
