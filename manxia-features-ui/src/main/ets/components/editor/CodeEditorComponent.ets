import { SafeUtils } from 'manxia_core/src/main/ets/Utils/SafeUtils';
/**
 * 代码编辑器组件
 * 基于WebView + Monaco Editor实现
 * 支持多种编程语言的语法高亮、代码补全等功能
 */

import { webview } from '@kit.ArkWeb';
import { logger } from 'manxia_core/src/main/ets/Utils/Logger';

const TAG = 'CodeEditorComponent';

/**
 * 编辑器主题
 */
export enum EditorTheme {
  DARK = 'dark',
  LIGHT = 'light',
  HIGH_CONTRAST = 'highContrast'
}

/**
 * 编辑器配置
 */
export interface CodeEditorConfig {
  theme?: EditorTheme;
  fontSize?: number;
  lineNumbers?: boolean;
  minimap?: boolean;
  wordWrap?: boolean;
  readOnly?: boolean;
  language?: string;
}

/**
 * 光标位置
 */
export interface CursorPosition {
  line: number;
  column: number;
}

/**
 * 编辑器控制器接口
 */
export interface CodeEditorController {
  setContent: (content: string, language?: string) => void;
  getContent: () => Promise<string>;
  undo: () => void;
  redo: () => void;
  findText: (text: string) => void;
  replaceText: (oldText: string, newText: string, replaceAll?: boolean) => void;
  insertText: (text: string) => void;
  formatCode: () => void;
  getSelectedText: () => Promise<string>;
  getCursorPosition: () => Promise<CursorPosition>;
  getLineCount: () => Promise<number>;
  goToLine: (line: number) => void;
  setTheme: (theme: EditorTheme) => void;
  setFontSize: (size: number) => void;
  setLineNumbers: (show: boolean) => void;
  setMinimap: (show: boolean) => void;
  setWordWrap: (wrap: boolean) => void;
}

/**
 * 编辑器回调
 */
export interface CodeEditorCallbacks {
  onReady?: (controller: CodeEditorController) => void;
  onContentChanged?: (content: string) => void;
  onSave?: (content: string) => void;
}

@Component
export struct CodeEditorComponent {
  @Prop content: string = '';
  @Prop language: string = 'plaintext';
  @Prop config: CodeEditorConfig = {};
  @Prop callbacks: CodeEditorCallbacks = {};
  
  @State private isReady: boolean = false;
  @State private isLoading: boolean = true;
  
  private webController: webview.WebviewController = new webview.WebviewController();
  private pendingContent: string = '';
  private pendingLanguage: string = '';
  
  aboutToAppear(): void {
    logger.info(TAG, '编辑器组件初始化');
    this.pendingContent = this.content;
    this.pendingLanguage = this.language;
  }
  
  aboutToDisappear(): void {
    logger.info(TAG, '编辑器组件销毁');
  }
  
  /**
   * 设置编辑器内容
   */
  public setContent(content: string, language?: string): void {
    if (this.isReady) {
      const lang = language || this.language;
      const escapedContent = this.escapeForJs(content);
      this.webController.runJavaScript(`setContent("${escapedContent}", "${lang}")`);
    } else {
      this.pendingContent = content;
      if (language) {
        this.pendingLanguage = language;
      }
    }
  }
  
  /**
   * 获取编辑器内容
   */
  public async getContent(): Promise<string> {
    if (!this.isReady) {
      return this.pendingContent;
    }
    try {
      const result = await this.webController.runJavaScript('getContent()');
      return result as string;
    } catch (e) {
      logger.error(TAG, `获取内容失败: ${e}`);
      return '';
    }
  }
  
  /**
   * 设置语言
   */
  public setLanguage(language: string): void {
    if (this.isReady) {
      this.webController.runJavaScript(`setLanguage("${language}")`);
    } else {
      this.pendingLanguage = language;
    }
  }
  
  /**
   * 设置主题
   */
  public setTheme(theme: EditorTheme): void {
    if (this.isReady) {
      this.webController.runJavaScript(`setTheme("${theme}")`);
    }
  }
  
  /**
   * 设置只读模式
   */
  public setReadOnly(readOnly: boolean): void {
    if (this.isReady) {
      this.webController.runJavaScript(`setReadOnly(${readOnly})`);
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
   * 设置行号显示
   */
  public setLineNumbers(show: boolean): void {
    if (this.isReady) {
      this.webController.runJavaScript(`setLineNumbers(${show})`);
    }
  }
  
  /**
   * 设置小地图显示
   */
  public setMinimap(show: boolean): void {
    if (this.isReady) {
      this.webController.runJavaScript(`setMinimap(${show})`);
    }
  }
  
  /**
   * 设置自动换行
   */
  public setWordWrap(wrap: boolean): void {
    if (this.isReady) {
      this.webController.runJavaScript(`setWordWrap(${wrap})`);
    }
  }
  
  /**
   * 跳转到指定行
   */
  public goToLine(lineNumber: number): void {
    if (this.isReady) {
      this.webController.runJavaScript(`goToLine(${lineNumber})`);
    }
  }
  
  /**
   * 查找文本
   */
  public findText(text: string): void {
    if (this.isReady) {
      const escapedText = this.escapeForJs(text);
      this.webController.runJavaScript(`findText("${escapedText}")`);
    }
  }
  
  /**
   * 替换文本
   */
  public replaceText(oldText: string, newText: string, replaceAll: boolean = false): void {
    if (this.isReady) {
      const escapedOld = this.escapeForJs(oldText);
      const escapedNew = this.escapeForJs(newText);
      this.webController.runJavaScript(`replaceText("${escapedOld}", "${escapedNew}", ${replaceAll})`);
    }
  }
  
  /**
   * 插入文本
   */
  public insertText(text: string): void {
    if (this.isReady) {
      const escapedText = this.escapeForJs(text);
      this.webController.runJavaScript(`insertText("${escapedText}")`);
    }
  }
  
  /**
   * 格式化代码
   */
  public formatCode(): void {
    if (this.isReady) {
      this.webController.runJavaScript('formatCode()');
    }
  }
  
  /**
   * 撤销
   */
  public undo(): void {
    if (this.isReady) {
      this.webController.runJavaScript('undo()');
    }
  }
  
  /**
   * 重做
   */
  public redo(): void {
    if (this.isReady) {
      this.webController.runJavaScript('redo()');
    }
  }
  
  /**
   * 获取选中的文本
   */
  public async getSelectedText(): Promise<string> {
    if (!this.isReady) return '';
    try {
      const result = await this.webController.runJavaScript('getSelectedText()');
      return result as string;
    } catch (e) {
      logger.error(TAG, `获取选中文本失败: ${e}`);
      return '';
    }
  }
  
  /**
   * 获取光标位置
   */
  public async getCursorPosition(): Promise<CursorPosition> {
    if (!this.isReady) return { line: 1, column: 1 };
    try {
      const result = await this.webController.runJavaScript('JSON.stringify(getCursorPosition())');
      return SafeUtils.parseObj<CursorPosition>(result as string);
    } catch (e) {
      logger.error(TAG, `获取光标位置失败: ${e}`);
      return { line: 1, column: 1 };
    }
  }
  
  /**
   * 获取总行数
   */
  public async getLineCount(): Promise<number> {
    if (!this.isReady) return 0;
    try {
      const result = await this.webController.runJavaScript('getLineCount()');
      return parseInt(result as string);
    } catch (e) {
      logger.error(TAG, `获取行数失败: ${e}`);
      return 0;
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
   * 处理编辑器就绪
   */
  private onEditorReady(): void {
    logger.info(TAG, '编辑器就绪');
    this.isReady = true;
    this.isLoading = false;
    
    // 应用配置
    if (this.config.theme) {
      this.setTheme(this.config.theme);
    }
    if (this.config.fontSize) {
      this.setFontSize(this.config.fontSize);
    }
    if (this.config.readOnly !== undefined) {
      this.setReadOnly(this.config.readOnly);
    }
    if (this.config.lineNumbers !== undefined) {
      this.webController.runJavaScript(`setLineNumbers(${this.config.lineNumbers})`);
    }
    if (this.config.minimap !== undefined) {
      this.webController.runJavaScript(`setMinimap(${this.config.minimap})`);
    }
    if (this.config.wordWrap !== undefined) {
      this.webController.runJavaScript(`setWordWrap(${this.config.wordWrap})`);
    }
    
    // 设置待处理的内容
    if (this.pendingContent || this.pendingLanguage) {
      this.setContent(this.pendingContent, this.pendingLanguage);
    }
    
    // 创建控制器并回调
    if (this.callbacks.onReady) {
      const controller: CodeEditorController = {
        setContent: (content: string, language?: string) => this.setContent(content, language),
        getContent: () => this.getContent(),
        undo: () => this.undo(),
        redo: () => this.redo(),
        findText: (text: string) => this.findText(text),
        replaceText: (oldText: string, newText: string, replaceAll?: boolean) => this.replaceText(oldText, newText, replaceAll),
        insertText: (text: string) => this.insertText(text),
        formatCode: () => this.formatCode(),
        getSelectedText: () => this.getSelectedText(),
        getCursorPosition: () => this.getCursorPosition(),
        getLineCount: () => this.getLineCount(),
        goToLine: (line: number) => this.goToLine(line),
        setTheme: (theme: EditorTheme) => this.setTheme(theme),
        setFontSize: (size: number) => this.setFontSize(size),
        setLineNumbers: (show: boolean) => this.setLineNumbers(show),
        setMinimap: (show: boolean) => this.setMinimap(show),
        setWordWrap: (wrap: boolean) => this.setWordWrap(wrap)
      };
      this.callbacks.onReady(controller);
    }
  }
  
  /**
   * 处理内容变化
   */
  private onContentChanged(content: string): void {
    if (this.callbacks.onContentChanged) {
      this.callbacks.onContentChanged(content);
    }
  }

  private onSaveRequested(content: string): void {
    if (this.callbacks.onSave) {
      this.callbacks.onSave(content);
    }
  }
  
  build() {
    Stack() {
      Web({
        src: $rawfile('code_editor/monaco_editor.html'),
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
            onEditorReady: () => {
              this.onEditorReady();
            },
            onContentChanged: (content: string) => {
              this.onContentChanged(content);
            },
            onSave: (content: string) => {
              this.onSaveRequested(content);
            }
          },
          name: 'arkts',
          methodList: ['onEditorReady', 'onContentChanged', 'onSave'],
          controller: this.webController
        })
      
      // 加载指示器
      if (this.isLoading) {
        Column() {
          LoadingProgress()
            .width(40)
            .height(40)
            .color('#888888')
          Text('加载编辑器...')
            .fontSize(14)
            .fontColor('#888888')
            .margin({ top: 8 })
        }
        .width('100%')
        .height('100%')
        .justifyContent(FlexAlign.Center)
        .backgroundColor('#1e1e1e')
      }
    }
    .width('100%')
    .height('100%')
  }
}
