/**
 * 文件编辑器页面
 * 支持多种编程语言和文件格式的编辑
 * 包含Markdown预览功能
 * 
 * 文件路径: entry/src/main/ets/pages/FileEditorPage.ets
 */

import { promptAction } from '@kit.ArkUI';
import { picker, fileIo } from '@kit.CoreFileKit';
import { util } from '@kit.ArkTS';
import { logger } from '../Utils/Logger';
import { CodeEditorComponent, EditorTheme, CodeEditorConfig, CodeEditorCallbacks, CodeEditorController } from '../components/editor/CodeEditorComponent';
import { MarkdownViewerComponent, MarkdownTheme, TocItem, MarkdownViewerCallbacks, MarkdownViewerController } from '../components/editor/MarkdownViewerComponent';
import { fileEditorService, FileInfo, SearchResult } from '../Framework/Editor/FileEditorService';
import { ThemeAwareHelper } from '../Framework/Components/ThemeAware';
import { ThemeManager, ThemeType } from '../Framework/Managers/ThemeManager';

const TAG = 'FileEditorPage';
const TITLE_BAR_HEIGHT_MINI: number = 56;

/**
 * 页面参数
 */
export interface FileEditorParams {
  filePath?: string;
  content?: string;
  language?: string;
  readOnly?: boolean;
  title?: string;
}

/**
 * 编辑模式
 */
enum EditMode {
  EDIT = 'edit',
  PREVIEW = 'preview',
  SPLIT = 'split'
}

/**
 * 标签页信息
 */
interface TabInfo {
  id: string;
  filePath: string;
  fileName: string;
  content: string;
  originalContent: string;
  language: string;
  isDirty: boolean;
  isReadOnly: boolean;
}

interface ThemeState {
  currentTheme: ThemeType;
}

@ComponentV2
export struct FileEditorPage {
  @Local themeState: ThemeState = { currentTheme: ThemeType.DARK };
  private themeManager: ThemeManager = ThemeManager.getInstance();
  pathStack: NavPathStack = new NavPathStack();
  
  @Local private filePath: string = '';
  @Local private fileName: string = '文件编辑器';
  @Local private content: string = '';
  @Local private originalContent: string = '';
  @Local private language: string = 'plaintext';
  @Local private isReadOnly: boolean = false;
  @Local private isDirty: boolean = false;
  @Local private isLoading: boolean = false;
  @Local private isSaving: boolean = false;
  @Local private editMode: EditMode = EditMode.EDIT;
  @Local private editorTheme: EditorTheme = EditorTheme.DARK;
  @Local private fontSize: number = 14;
  @Local private showLineNumbers: boolean = true;
  @Local private showMinimap: boolean = true;
  @Local private wordWrap: boolean = false;
  @Local private tabSize: number = 4;
  @Local private insertSpaces: boolean = true;
  @Local private autoIndent: boolean = true;
  @Local private bracketPairColorization: boolean = true;
  @Local private renderWhitespace: string = 'none';
  @Local private cursorStyle: string = 'line';
  @Local private cursorBlinking: string = 'blink';
  @Local private smoothScrolling: boolean = true;
  @Local private folding: boolean = true;
  @Local private autoClosingBrackets: boolean = true;
  @Local private autoClosingQuotes: boolean = true;
  @Local private formatOnPaste: boolean = false;
  @Local private formatOnType: boolean = false;
  @Local private showSearchBar: boolean = false;
  @Local private searchText: string = '';
  @Local private replaceText: string = '';
  @Local private searchResults: SearchResult[] = [];
  @Local private currentSearchIndex: number = 0;
  @Local private showSettings: boolean = false;
  @Local private tocItems: TocItem[] = [];
  @Local private showToc: boolean = false;
  @Local private showHelp: boolean = false;
  @Local private tabs: TabInfo[] = [];
  @Local private activeTabId: string = '';
  @Local private showNewFileDialog: boolean = false;
  @Local private newFileName: string = '';
  @Local private settingsPanelOpacity: number = 0;
  @Local private helpPanelOpacity: number = 0;
  @Local private newFileDialogOpacity: number = 0;
  
  private editorController: CodeEditorController | null = null;
  private previewController: MarkdownViewerController | null = null;
  private pendingTabContent: string | null = null;
  private pendingTabLanguage: string | null = null;
  private themeChangeCallback: ((theme: ThemeType) => void) | null = null;
  
  aboutToAppear(): void {
    logger.info(TAG, '文件编辑器页面初始化');
    
    // 加载编辑器设置
    this.loadEditorSettings();
    
    // 初始化主题并监听变化
    this.themeManager.getCurrentTheme().then((theme: ThemeType) => {
      this.themeState = { currentTheme: theme };
      this.editorTheme = theme === ThemeType.LIGHT ? EditorTheme.LIGHT : EditorTheme.DARK;
    });
    this.themeChangeCallback = (newTheme: ThemeType) => {
      logger.info(TAG, `主题切换到: ${newTheme}`);
      this.themeState = { currentTheme: newTheme };
      this.editorTheme = newTheme === ThemeType.LIGHT ? EditorTheme.LIGHT : EditorTheme.DARK;
    };
    this.themeManager.onThemeChange(this.themeChangeCallback);
    
    // 如果是Markdown文件，默认显示分屏模式
    if (this.language === 'markdown' || this.fileName.endsWith('.md')) {
      this.editMode = EditMode.SPLIT;
    }
  }
  
  aboutToDisappear(): void {
    // 移除主题监听器
    if (this.themeChangeCallback) {
      this.themeManager.offThemeChange(this.themeChangeCallback);
    }
  }
  
  /**
   * 加载编辑器设置
   */
  private loadEditorSettings(): void {
    try {
      const settings = AppStorage.get<string>('editorSettings');
      if (settings) {
        const parsed = JSON.parse(settings) as Record<string, boolean | number | string>;
        this.showLineNumbers = parsed['showLineNumbers'] as boolean ?? true;
        this.showMinimap = parsed['showMinimap'] as boolean ?? true;
        this.wordWrap = parsed['wordWrap'] as boolean ?? false;
        this.fontSize = parsed['fontSize'] as number ?? 14;
        this.tabSize = parsed['tabSize'] as number ?? 4;
        this.insertSpaces = parsed['insertSpaces'] as boolean ?? true;
        this.autoIndent = parsed['autoIndent'] as boolean ?? true;
        this.bracketPairColorization = parsed['bracketPairColorization'] as boolean ?? true;
        this.renderWhitespace = parsed['renderWhitespace'] as string ?? 'none';
        this.cursorStyle = parsed['cursorStyle'] as string ?? 'line';
        this.cursorBlinking = parsed['cursorBlinking'] as string ?? 'blink';
        this.smoothScrolling = parsed['smoothScrolling'] as boolean ?? true;
        this.folding = parsed['folding'] as boolean ?? true;
        this.autoClosingBrackets = parsed['autoClosingBrackets'] as boolean ?? true;
        this.autoClosingQuotes = parsed['autoClosingQuotes'] as boolean ?? true;
        this.formatOnPaste = parsed['formatOnPaste'] as boolean ?? false;
        this.formatOnType = parsed['formatOnType'] as boolean ?? false;
      }
    } catch (e) {
      logger.error(TAG, `加载编辑器设置失败: ${e}`);
    }
  }
  
  /**
   * 保存编辑器设置
   */
  private saveEditorSettings(): void {
    try {
      const settings = JSON.stringify({
        showLineNumbers: this.showLineNumbers,
        showMinimap: this.showMinimap,
        wordWrap: this.wordWrap,
        fontSize: this.fontSize,
        tabSize: this.tabSize,
        insertSpaces: this.insertSpaces,
        autoIndent: this.autoIndent,
        bracketPairColorization: this.bracketPairColorization,
        renderWhitespace: this.renderWhitespace,
        cursorStyle: this.cursorStyle,
        cursorBlinking: this.cursorBlinking,
        smoothScrolling: this.smoothScrolling,
        folding: this.folding,
        autoClosingBrackets: this.autoClosingBrackets,
        autoClosingQuotes: this.autoClosingQuotes,
        formatOnPaste: this.formatOnPaste,
        formatOnType: this.formatOnType
      });
      AppStorage.setOrCreate('editorSettings', settings);
    } catch (e) {
      logger.error(TAG, `保存编辑器设置失败: ${e}`);
    }
  }
  
  /**
   * 打开设置面板
   */
  private openSettingsPanel(): void {
    this.settingsPanelOpacity = 0;
    this.showSettings = true;
  }
  
  /**
   * 关闭设置面板
   */
  private closeSettingsPanel(): void {
    animateTo({ duration: 200 }, () => {
      this.settingsPanelOpacity = 0;
    });
    setTimeout(() => {
      this.showSettings = false;
    }, 200);
  }
  
  /**
   * 加载文件
   */
  private async loadFile(): Promise<void> {
    if (!this.filePath) return;
    
    this.isLoading = true;
    try {
      const fileInfo = await fileEditorService.getFileInfo(this.filePath);
      this.fileName = fileInfo.name;
      this.language = fileEditorService.getLanguageByExtension(fileInfo.extension);
      
      this.content = await fileEditorService.readFile(this.filePath);
      this.originalContent = this.content;
      this.isDirty = false;
      
      logger.info(TAG, `文件加载成功: ${this.fileName}, 语言: ${this.language}`);
    } catch (e) {
      logger.error(TAG, `加载文件失败: ${e}`);
      promptAction.showToast({ message: `加载失败: ${e}` });
    } finally {
      this.isLoading = false;
    }
  }
  
  /**
   * 保存文件
   */
  private async saveFile(): Promise<void> {
    if (!this.filePath || this.isReadOnly) {
      // 如果没有文件路径，提示另存为
      this.showSaveAsDialog();
      return;
    }
    
    this.isSaving = true;
    try {
      await fileEditorService.writeFile(this.filePath, this.content);
      this.originalContent = this.content;
      this.isDirty = false;
      promptAction.showToast({ message: '保存成功' });
      logger.info(TAG, '文件保存成功');
    } catch (e) {
      logger.error(TAG, `保存文件失败: ${e}`);
      promptAction.showToast({ message: `保存失败: ${e}` });
    } finally {
      this.isSaving = false;
    }
  }
  
  /**
   * 显示另存为对话框
   */
  private showSaveAsDialog(): void {
    // TODO: 实现文件选择器
    promptAction.showToast({ message: '请先指定文件路径' });
  }
  
  /**
   * 处理内容变化
   */
  private onContentChanged(newContent: string): void {
    this.content = newContent;
    this.isDirty = newContent !== this.originalContent;
    
    // 如果是Markdown，更新预览
    if (this.language === 'markdown' && this.previewController) {
      this.previewController.renderMarkdown(newContent);
    }
  }
  
  /**
   * 执行搜索
   */
  private doSearch(): void {
    if (!this.searchText) {
      this.searchResults = [];
      return;
    }
    
    this.searchResults = fileEditorService.searchInContent(this.content, this.searchText);
    this.currentSearchIndex = 0;
    
    if (this.searchResults.length > 0 && this.editorController) {
      this.editorController.goToLine(this.searchResults[0].line);
    }
    
    promptAction.showToast({ message: `找到 ${this.searchResults.length} 个结果` });
  }
  
  /**
   * 跳转到下一个搜索结果
   */
  private goToNextResult(): void {
    if (this.searchResults.length === 0) return;
    
    this.currentSearchIndex = (this.currentSearchIndex + 1) % this.searchResults.length;
    if (this.editorController) {
      this.editorController.goToLine(this.searchResults[this.currentSearchIndex].line);
    }
  }
  
  /**
   * 跳转到上一个搜索结果
   */
  private goToPrevResult(): void {
    if (this.searchResults.length === 0) return;
    
    this.currentSearchIndex = (this.currentSearchIndex - 1 + this.searchResults.length) % this.searchResults.length;
    if (this.editorController) {
      this.editorController.goToLine(this.searchResults[this.currentSearchIndex].line);
    }
  }
  
  /**
   * 执行替换
   */
  private doReplace(replaceAll: boolean): void {
    if (!this.searchText || this.isReadOnly) return;
    
    const result = fileEditorService.replaceInContent(this.content, this.searchText, this.replaceText, false, false, replaceAll);
    if (result.success) {
      this.content = result.newContent;
      if (this.editorController) {
        this.editorController.setContent(this.content, this.language);
      }
      this.isDirty = true;
      this.syncCurrentTabState();
      promptAction.showToast({ message: `替换了 ${result.replacedCount} 处` });
    }
  }
  
  /**
   * 生成唯一ID
   */
  private generateTabId(): string {
    return `tab_${Date.now()}_${Math.random().toString(36).substring(2, 9)}`;
  }
  
  /**
   * 添加新标签页
   */
  private addTab(filePath: string, fileName: string, content: string, language: string, isReadOnly: boolean = false): string {
    const tabId = this.generateTabId();
    const newTab: TabInfo = {
      id: tabId,
      filePath: filePath,
      fileName: fileName,
      content: content,
      originalContent: content,
      language: language,
      isDirty: false,
      isReadOnly: isReadOnly
    };
    this.tabs = [...this.tabs, newTab];
    this.switchToTab(tabId);
    return tabId;
  }
  
  /**
   * 切换到指定标签页
   */
  private switchToTab(tabId: string): void {
    // 保存当前标签页状态
    this.syncCurrentTabState();
    
    const tab = this.tabs.find(t => t.id === tabId);
    if (tab) {
      this.activeTabId = tabId;
      this.filePath = tab.filePath;
      this.fileName = tab.fileName;
      this.content = tab.content;
      this.originalContent = tab.originalContent;
      this.language = tab.language;
      this.isDirty = tab.isDirty;
      this.isReadOnly = tab.isReadOnly;
      
      // 设置编辑模式
      if (this.language === 'markdown') {
        this.editMode = EditMode.SPLIT;
      } else {
        this.editMode = EditMode.EDIT;
      }
      
      // 保存待处理内容，等待编辑器就绪后设置
      this.pendingTabContent = this.content;
      this.pendingTabLanguage = this.language;
      
      // 注意：不要在这里直接调用editorController.setContent
      // 因为编辑模式切换会导致组件重建，editorController会在onReady中处理pendingTabContent
    }
  }
  
  /**
   * 同步当前标签页状态
   */
  private syncCurrentTabState(): void {
    if (!this.activeTabId) return;
    
    const tabIndex = this.tabs.findIndex(t => t.id === this.activeTabId);
    if (tabIndex >= 0) {
      const oldTab = this.tabs[tabIndex];
      const updatedTab: TabInfo = {
        id: oldTab.id,
        filePath: oldTab.filePath,
        fileName: oldTab.fileName,
        content: this.content,
        originalContent: oldTab.originalContent,
        language: oldTab.language,
        isDirty: this.isDirty,
        isReadOnly: oldTab.isReadOnly
      };
      const updatedTabs: TabInfo[] = [];
      for (let i = 0; i < this.tabs.length; i++) {
        if (i === tabIndex) {
          updatedTabs.push(updatedTab);
        } else {
          updatedTabs.push(this.tabs[i]);
        }
      }
      this.tabs = updatedTabs;
    }
  }
  
  /**
   * 关闭标签页
   */
  private closeTab(tabId: string): void {
    const tab = this.tabs.find(t => t.id === tabId);
    if (!tab) return;
    
    if (tab.isDirty) {
      this.showCloseTabConfirmDialog(tabId);
    } else {
      this.removeTab(tabId);
    }
  }
  
  /**
   * 显示关闭标签页确认对话框
   */
  private showCloseTabConfirmDialog(tabId: string): void {
    const tab = this.tabs.find(t => t.id === tabId);
    if (!tab) return;
    
    AlertDialog.show({
      title: '未保存的更改',
      message: `文件 "${tab.fileName}" 有未保存的更改，是否保存？`,
      primaryButton: {
        value: '保存并关闭',
        action: async () => {
          if (tabId === this.activeTabId) {
            await this.saveFile();
          }
          this.removeTab(tabId);
        }
      },
      secondaryButton: {
        value: '不保存',
        action: () => {
          this.removeTab(tabId);
        }
      },
      cancel: () => {}
    });
  }
  
  /**
   * 移除标签页
   */
  private removeTab(tabId: string): void {
    const tabIndex = this.tabs.findIndex(t => t.id === tabId);
    if (tabIndex < 0) return;
    
    const newTabs = this.tabs.filter(t => t.id !== tabId);
    this.tabs = newTabs;
    
    if (tabId === this.activeTabId) {
      if (newTabs.length > 0) {
        const newActiveIndex = Math.min(tabIndex, newTabs.length - 1);
        this.switchToTab(newTabs[newActiveIndex].id);
      } else {
        this.activeTabId = '';
        this.filePath = '';
        this.fileName = '文件编辑器';
        this.content = '';
        this.originalContent = '';
        this.isDirty = false;
      }
    }
  }
  
  /**
   * 检查是否有未保存的更改
   */
  private hasUnsavedChanges(): boolean {
    return this.tabs.some(t => t.isDirty);
  }
  
  /**
   * 处理返回操作
   */
  private handleBack(): void {
    if (this.hasUnsavedChanges()) {
      AlertDialog.show({
        title: '未保存的更改',
        message: '有文件尚未保存，是否保存后退出？',
        primaryButton: {
          value: '保存并退出',
          action: async () => {
            await this.saveAllFiles();
            this.pathStack.pop();
          }
        },
        secondaryButton: {
          value: '直接退出',
          action: () => {
            this.pathStack.pop();
          }
        },
        cancel: () => {}
      });
    } else {
      this.pathStack.pop();
    }
  }
  
  /**
   * 保存所有文件
   */
  private async saveAllFiles(): Promise<void> {
    for (const tab of this.tabs) {
      if (tab.isDirty && tab.filePath) {
        try {
          await fileEditorService.writeFile(tab.filePath, tab.content);
          const tabIndex = this.tabs.findIndex(t => t.id === tab.id);
          if (tabIndex >= 0) {
            const oldTab = this.tabs[tabIndex];
            const updatedTab: TabInfo = {
              id: oldTab.id,
              filePath: oldTab.filePath,
              fileName: oldTab.fileName,
              content: oldTab.content,
              originalContent: tab.content,
              language: oldTab.language,
              isDirty: false,
              isReadOnly: oldTab.isReadOnly
            };
            const updatedTabs: TabInfo[] = [];
            for (let i = 0; i < this.tabs.length; i++) {
              if (i === tabIndex) {
                updatedTabs.push(updatedTab);
              } else {
                updatedTabs.push(this.tabs[i]);
              }
            }
            this.tabs = updatedTabs;
          }
        } catch (error) {
          logger.error(TAG, `保存文件失败: ${tab.fileName}, ${error}`);
        }
      }
    }
    this.isDirty = false;
  }
  
  /**
   * 构建搜索栏
   */
  @Builder
  buildSearchBar() {
    Column() {
      Row({ space: 8 }) {
        TextInput({ placeholder: '搜索...', text: this.searchText })
          .layoutWeight(1)
          .height(36)
          .backgroundColor(ThemeAwareHelper.getTestManagementThemedColor('comp_background_tertiary', this.themeState.currentTheme))
          .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_primary', this.themeState.currentTheme))
          .placeholderColor(ThemeAwareHelper.getTestManagementThemedColor('text_secondary', this.themeState.currentTheme))
          .onChange((value) => {
            this.searchText = value;
          })
          .onSubmit(() => this.doSearch())
        
        Button('搜索')
          .height(36)
          .fontSize(14)
          .onClick(() => this.doSearch())
        
        if (this.searchResults.length > 0) {
          Text(`${this.currentSearchIndex + 1}/${this.searchResults.length}`)
            .fontSize(12)
            .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_secondary', this.themeState.currentTheme))
          
          Button({ type: ButtonType.Normal }) {
            Text('↑').fontSize(16).fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_primary', this.themeState.currentTheme))
          }
          .width(32)
          .height(32)
          .backgroundColor(ThemeAwareHelper.getTestManagementThemedColor('comp_background_tertiary', this.themeState.currentTheme))
          .onClick(() => this.goToPrevResult())
          
          Button({ type: ButtonType.Normal }) {
            Text('↓').fontSize(16).fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_primary', this.themeState.currentTheme))
          }
          .width(32)
          .height(32)
          .backgroundColor(ThemeAwareHelper.getTestManagementThemedColor('comp_background_tertiary', this.themeState.currentTheme))
          .onClick(() => this.goToNextResult())
        }
      }
      .width('100%')
      
      if (!this.isReadOnly) {
        Row({ space: 8 }) {
          TextInput({ placeholder: '替换为...', text: this.replaceText })
            .layoutWeight(1)
            .height(36)
            .backgroundColor(ThemeAwareHelper.getTestManagementThemedColor('comp_background_tertiary', this.themeState.currentTheme))
            .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_primary', this.themeState.currentTheme))
            .placeholderColor(ThemeAwareHelper.getTestManagementThemedColor('text_secondary', this.themeState.currentTheme))
            .onChange((value) => {
              this.replaceText = value;
            })
          
          Button('替换')
            .height(36)
            .fontSize(14)
            .onClick(() => this.doReplace(false))
          
          Button('全部替换')
            .height(36)
            .fontSize(14)
            .onClick(() => this.doReplace(true))
        }
        .width('100%')
        .margin({ top: 8 })
      }
    }
    .width('100%')
    .padding(12)
    .backgroundColor(ThemeAwareHelper.getTestManagementThemedColor('comp_background_secondary', this.themeState.currentTheme))
  }
  
  /**
   * 构建设置面板
   */
  @Builder
  buildSettingsPanel() {
    Column({ space: 16 }) {
      Text('编辑器设置')
        .fontSize(18)
        .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_primary', this.themeState.currentTheme))
        .fontWeight(FontWeight.Bold)
      
      // 主题
      Row() {
        Text('主题')
          .fontSize(14)
          .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_primary', this.themeState.currentTheme))
          .layoutWeight(1)
        
        Select([
          { value: '深色' },
          { value: '浅色' },
          { value: '高对比度' }
        ])
          .selected(this.editorTheme === EditorTheme.DARK ? 0 : this.editorTheme === EditorTheme.LIGHT ? 1 : 2)
          .value(this.editorTheme === EditorTheme.DARK ? '深色' : this.editorTheme === EditorTheme.LIGHT ? '浅色' : '高对比度')
          .onSelect((index) => {
            const themes = [EditorTheme.DARK, EditorTheme.LIGHT, EditorTheme.HIGH_CONTRAST];
            this.editorTheme = themes[index];
            if (this.editorController) {
              this.editorController.setTheme(this.editorTheme);
            }
          })
      }
      .width('100%')
      
      // 字体大小
      Row() {
        Text('字体大小')
          .fontSize(14)
          .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_primary', this.themeState.currentTheme))
          .layoutWeight(1)
        
        Row({ space: 8 }) {
          Button('-')
            .width(32)
            .height(32)
            .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_primary', this.themeState.currentTheme))
            .onClick(() => {
              if (this.fontSize > 10) {
                this.fontSize--;
                if (this.editorController) {
                  this.editorController.setFontSize(this.fontSize);
                }
              }
            })
          
          Text(`${this.fontSize}`)
            .fontSize(14)
            .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_primary', this.themeState.currentTheme))
            .width(40)
            .textAlign(TextAlign.Center)
          
          Button('+')
            .width(32)
            .height(32)
            .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_primary', this.themeState.currentTheme))
            .onClick(() => {
              if (this.fontSize < 30) {
                this.fontSize++;
                if (this.editorController) {
                  this.editorController.setFontSize(this.fontSize);
                }
              }
            })
        }
      }
      .width('100%')
      
      // 行号
      Row() {
        Text('显示行号')
          .fontSize(14)
          .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_primary', this.themeState.currentTheme))
          .layoutWeight(1)
        
        Toggle({ type: ToggleType.Switch, isOn: this.showLineNumbers })
          .onChange((isOn) => {
            this.showLineNumbers = isOn;
            if (this.editorController) {
              this.editorController.setLineNumbers(isOn);
            }
            this.saveEditorSettings();
          })
      }
      .width('100%')
      
      // 小地图
      Row() {
        Text('显示小地图')
          .fontSize(14)
          .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_primary', this.themeState.currentTheme))
          .layoutWeight(1)
        
        Toggle({ type: ToggleType.Switch, isOn: this.showMinimap })
          .onChange((isOn) => {
            this.showMinimap = isOn;
            if (this.editorController) {
              this.editorController.setMinimap(isOn);
            }
            this.saveEditorSettings();
          })
      }
      .width('100%')
      
      // 自动换行
      Row() {
        Text('自动换行')
          .fontSize(14)
          .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_primary', this.themeState.currentTheme))
          .layoutWeight(1)
        
        Toggle({ type: ToggleType.Switch, isOn: this.wordWrap })
          .onChange((isOn) => {
            this.wordWrap = isOn;
            if (this.editorController) {
              this.editorController.setWordWrap(isOn);
            }
            this.saveEditorSettings();
          })
      }
      .width('100%')
    }
    .width('100%')
    .padding(16)
    .backgroundColor(ThemeAwareHelper.getTestManagementThemedColor('comp_background_primary', this.themeState.currentTheme))
    .borderRadius(8)
  }
  
  /**
   * 构建目录面板
   */
  @Builder
  buildTocPanel() {
    Column() {
      Text('目录')
        .fontSize(16)
        .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_primary', this.themeState.currentTheme))
        .fontWeight(FontWeight.Bold)
        .margin({ bottom: 12 })
      
      if (this.tocItems.length === 0) {
        Text('暂无目录')
          .fontSize(14)
          .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_secondary', this.themeState.currentTheme))
      } else {
        List() {
          ForEach(this.tocItems, (item: TocItem) => {
            ListItem() {
              Text(item.text)
                .fontSize(14)
                .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_primary', this.themeState.currentTheme))
                .padding({ left: (item.level - 1) * 16, top: 8, bottom: 8 })
                .width('100%')
            }
            .onClick(() => {
              if (this.previewController) {
                this.previewController.scrollToHeading(item.id);
              }
              this.showToc = false;
            })
          })
        }
        .width('100%')
        .layoutWeight(1)
      }
    }
    .width(250)
    .height('100%')
    .padding(16)
    .backgroundColor(ThemeAwareHelper.getTestManagementThemedColor('comp_background_secondary', this.themeState.currentTheme))
  }
  
  /**
   * 构建编辑器区域
   */
  @Builder
  buildEditorArea() {
    if (this.editMode === EditMode.EDIT || this.editMode === EditMode.SPLIT) {
      CodeEditorComponent({
        content: this.content,
        language: this.language,
        config: {
          theme: this.editorTheme,
          fontSize: this.fontSize,
          lineNumbers: this.showLineNumbers,
          minimap: this.showMinimap,
          wordWrap: this.wordWrap,
          readOnly: this.isReadOnly
        },
        callbacks: {
          onReady: (controller: CodeEditorController) => {
            logger.info(TAG, '编辑器就绪');
            this.editorController = controller;
            // 处理待处理的内容
            if (this.pendingTabContent !== null) {
              controller.setContent(this.pendingTabContent, this.pendingTabLanguage || 'plaintext');
              this.pendingTabContent = null;
              this.pendingTabLanguage = null;
            }
          },
          onContentChanged: (content: string) => {
            this.onContentChanged(content);
          }
        }
      })
        .layoutWeight(1)
    }
  }
  
  /**
   * 构建预览区域
   */
  @Builder
  buildPreviewArea() {
    if ((this.editMode === EditMode.PREVIEW || this.editMode === EditMode.SPLIT) && this.language === 'markdown') {
      MarkdownViewerComponent({
        content: this.content,
        theme: this.editorTheme === EditorTheme.LIGHT ? MarkdownTheme.LIGHT : MarkdownTheme.DARK,
        fontSize: this.fontSize,
        callbacks: {
          onReady: (controller: MarkdownViewerController) => {
            logger.info(TAG, '预览就绪');
            this.previewController = controller;
          },
          onTocGenerated: (toc: TocItem[]) => {
            this.tocItems = toc;
          },
          onLinkClick: (url: string) => {
            logger.info(TAG, `链接点击: ${url}`);
          }
        }
      })
        .layoutWeight(1)
    }
  }
  
  build() {
    NavDestination() {
      Stack() {
        Column() {
          // 工具栏
          this.buildToolbar()
          
          // 标签栏
          if (this.tabs.length > 0) {
            this.buildTabBar()
          }
          
          // 搜索栏
          if (this.showSearchBar) {
            this.buildSearchBar()
          }
          
          // 主内容区
          Stack() {
            if (this.isLoading) {
              Column() {
                LoadingProgress()
                  .width(48)
                  .height(48)
                  .color(ThemeAwareHelper.getTestManagementThemedColor('text_secondary', this.themeState.currentTheme))
                Text('加载中...')
                  .fontSize(14)
                  .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_secondary', this.themeState.currentTheme))
                  .margin({ top: 12 })
              }
              .width('100%')
              .height('100%')
              .justifyContent(FlexAlign.Center)
            } else if (this.tabs.length === 0) {
              // 空状态 - 没有打开任何文件时显示导入提示
              this.buildEmptyState()
            } else {
              Row() {
                // 目录面板
                if (this.showToc && this.language === 'markdown') {
                  this.buildTocPanel()
                }
                
                // 编辑器/预览区域
                if (this.editMode === EditMode.SPLIT) {
                  Row() {
                    this.buildEditorArea()
                    Divider()
                      .vertical(true)
                      .width(1)
                      .color(ThemeAwareHelper.getTestManagementThemedColor('divider', this.themeState.currentTheme))
                    this.buildPreviewArea()
                  }
                  .layoutWeight(1)
                } else {
                  Column() {
                    this.buildEditorArea()
                    this.buildPreviewArea()
                  }
                  .layoutWeight(1)
                }
              }
              .width('100%')
              .height('100%')
            }
            
            // 设置面板
            if (this.showSettings) {
              Column() {
                this.buildSettingsPanel()
              }
              .width('100%')
              .height('100%')
              .backgroundColor('rgba(0, 0, 0, 0.5)')
              .justifyContent(FlexAlign.Center)
              .padding(32)
              .opacity(this.settingsPanelOpacity)
              .onClick(() => {
                this.closeSettingsPanel();
              })
              .onAppear(() => {
                animateTo({ duration: 200 }, () => {
                  this.settingsPanelOpacity = 1;
                });
              })
            }
            
            // 使用说明面板
            if (this.showHelp) {
              this.buildHelpPanel()
            }
            
            // 新建文件对话框
            if (this.showNewFileDialog) {
              this.buildNewFileDialog()
            }
          }
          .layoutWeight(1)
        }
        .width('100%')
        .height('100%')
      }
      .width('100%')
      .height('100%')
      .backgroundColor(ThemeAwareHelper.getTestManagementThemedColor('background', this.themeState.currentTheme))
      .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.TOP, SafeAreaEdge.BOTTOM])
    }
    .hideTitleBar(true)
    .mode(NavDestinationMode.STANDARD)
    .onReady((context: NavDestinationContext) => {
      this.pathStack = context.pathStack;
    })
    .onBackPressed(() => {
      this.handleBack();
      return true;
    })
  }
  
  /**
   * 构建标签栏 - VSCode风格
   */
  @Builder
  buildTabBar() {
    Scroll() {
      Row({ space: 0 }) {
        ForEach(this.tabs, (tab: TabInfo, index: number) => {
          // 标签项
          Row() {
            // 文件图标
            SymbolGlyph(this.getFileIcon(tab.language))
              .fontSize(14)
              .fontColor([tab.id === this.activeTabId 
                ? ThemeAwareHelper.getTestManagementThemedColor('text_primary', this.themeState.currentTheme)
                : ThemeAwareHelper.getTestManagementThemedColor('text_secondary', this.themeState.currentTheme)])
              .margin({ right: 6 })
            
            // 文件名
            Text(tab.fileName)
              .fontSize(13)
              .fontColor(tab.id === this.activeTabId 
                ? ThemeAwareHelper.getTestManagementThemedColor('text_primary', this.themeState.currentTheme)
                : ThemeAwareHelper.getTestManagementThemedColor('text_secondary', this.themeState.currentTheme))
              .maxLines(1)
              .textOverflow({ overflow: TextOverflow.Ellipsis })
              .constraintSize({ maxWidth: 140 })
            
            // 修改标记或关闭按钮
            Stack() {
              if (tab.isDirty) {
                // 未保存标记 - 圆点
                Circle()
                  .width(8)
                  .height(8)
                  .fill(ThemeAwareHelper.getTestManagementThemedColor('accent_primary', this.themeState.currentTheme))
              }
              // 关闭按钮（悬停时显示，这里简化为始终显示）
              Button({ type: ButtonType.Normal }) {
                SymbolGlyph($r('sys.symbol.xmark'))
                  .fontSize(12)
                  .fontColor([ThemeAwareHelper.getTestManagementThemedColor('text_secondary', this.themeState.currentTheme)])
              }
              .width(18)
              .height(18)
              .backgroundColor(Color.Transparent)
              .borderRadius(4)
              .visibility(tab.isDirty ? Visibility.Hidden : Visibility.Visible)
              .onClick(() => {
                this.closeTab(tab.id);
              })
            }
            .width(18)
            .height(18)
            .margin({ left: 6 })
          }
          .padding({ left: 12, right: 8, top: 0, bottom: 0 })
          .height(35)
          .alignItems(VerticalAlign.Center)
          .backgroundColor(tab.id === this.activeTabId 
            ? ThemeAwareHelper.getTestManagementThemedColor('background', this.themeState.currentTheme)
            : Color.Transparent)
          .border({
            width: { top: tab.id === this.activeTabId ? 2 : 0, bottom: 0, left: 0, right: 0 },
            color: ThemeAwareHelper.getTestManagementThemedColor('accent_primary', this.themeState.currentTheme)
          })
          .onClick(() => {
            this.switchToTab(tab.id);
          })
          .gesture(
            LongPressGesture({ repeat: false })
              .onAction(() => {
                // 长按显示关闭选项
                this.closeTab(tab.id);
              })
          )
          .animation({ duration: 150 })
        })
      }
    }
    .scrollable(ScrollDirection.Horizontal)
    .scrollBar(BarState.Off)
    .height(35)
    .width('100%')
    .backgroundColor(ThemeAwareHelper.getTestManagementThemedColor('comp_background_secondary', this.themeState.currentTheme))
  }
  
  /**
   * 获取文件图标
   */
  private getFileIcon(language: string): Resource {
    switch (language) {
      case 'markdown':
        return $r('sys.symbol.doc_text');
      case 'javascript':
      case 'typescript':
        return $r('sys.symbol.doc_plaintext');
      case 'json':
        return $r('sys.symbol.doc_plaintext');
      case 'html':
      case 'xml':
        return $r('sys.symbol.doc_plaintext');
      case 'css':
        return $r('sys.symbol.doc_plaintext');
      default:
        return $r('sys.symbol.doc');
    }
  }
  
  /**
   * 构建空状态
   */
  @Builder
  buildEmptyState() {
    Column({ space: 24 }) {
      SymbolGlyph($r('sys.symbol.doc_text'))
        .fontSize(64)
        .fontColor([ThemeAwareHelper.getTestManagementThemedColor('text_secondary', this.themeState.currentTheme)])
      
      Text('文件编辑器')
        .fontSize(24)
        .fontWeight(FontWeight.Bold)
        .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_primary', this.themeState.currentTheme))
      
      Text('支持多种编程语言和文件格式的编辑\n包含Markdown实时预览功能')
        .fontSize(14)
        .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_secondary', this.themeState.currentTheme))
        .textAlign(TextAlign.Center)
      
      Button('导入文件')
        .width(160)
        .height(44)
        .fontSize(16)
        .onClick(() => this.importFile())
      
      Button('查看使用说明')
        .width(160)
        .height(44)
        .fontSize(16)
        .type(ButtonType.Normal)
        .backgroundColor(Color.Transparent)
        .fontColor(ThemeAwareHelper.getTestManagementThemedColor('accent_primary', this.themeState.currentTheme))
        .border({ width: 1, color: ThemeAwareHelper.getTestManagementThemedColor('accent_primary', this.themeState.currentTheme) })
        .borderRadius(22)
        .onClick(() => {
          this.showHelp = true;
        })
    }
    .width('100%')
    .height('100%')
    .justifyContent(FlexAlign.Center)
  }
  
  /**
   * 构建新建文件对话框
   */
  @Builder
  buildNewFileDialog() {
    Column() {
      Column({ space: 16 }) {
        Text('新建文件')
          .fontSize(18)
          .fontWeight(FontWeight.Bold)
          .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_primary', this.themeState.currentTheme))
        
        TextInput({ placeholder: '输入文件名（如：example.md）', text: this.newFileName })
          .width('100%')
          .height(44)
          .backgroundColor(ThemeAwareHelper.getTestManagementThemedColor('comp_background_tertiary', this.themeState.currentTheme))
          .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_primary', this.themeState.currentTheme))
          .placeholderColor(ThemeAwareHelper.getTestManagementThemedColor('text_secondary', this.themeState.currentTheme))
          .onChange((value) => {
            this.newFileName = value;
          })
          .onSubmit(() => this.createNewFile())
        
        Row({ space: 12 }) {
          Button('取消')
            .layoutWeight(1)
            .height(40)
            .type(ButtonType.Normal)
            .backgroundColor(Color.Transparent)
            .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_secondary', this.themeState.currentTheme))
            .border({ width: 1, color: ThemeAwareHelper.getTestManagementThemedColor('divider', this.themeState.currentTheme) })
            .borderRadius(8)
            .onClick(() => {
              animateTo({ duration: 200 }, () => {
                this.newFileDialogOpacity = 0;
              });
              setTimeout(() => {
                this.showNewFileDialog = false;
              }, 200);
            })
          
          Button('创建')
            .layoutWeight(1)
            .height(40)
            .borderRadius(8)
            .onClick(() => this.createNewFile())
        }
        .width('100%')
      }
      .width(320)
      .padding(20)
      .backgroundColor(ThemeAwareHelper.getTestManagementThemedColor('panel_background', this.themeState.currentTheme))
      .borderRadius(16)
    }
    .width('100%')
    .height('100%')
    .backgroundColor('rgba(0, 0, 0, 0.5)')
    .justifyContent(FlexAlign.Center)
    .opacity(this.newFileDialogOpacity)
    .onClick(() => {
      animateTo({ duration: 200 }, () => {
        this.newFileDialogOpacity = 0;
      });
      setTimeout(() => {
        this.showNewFileDialog = false;
      }, 200);
    })
  }
  
  /**
   * 新建文件
   */
  private createNewFile(): void {
    if (!this.newFileName.trim()) {
      promptAction.showToast({ message: '请输入文件名' });
      return;
    }
    
    const fileName = this.newFileName.trim();
    const ext = fileName.split('.').pop() || 'txt';
    const language = fileEditorService.getLanguageByExtension(ext);
    
    // 添加新标签页
    this.addTab('', fileName, '', language, false);
    
    // 关闭对话框
    animateTo({ duration: 200 }, () => {
      this.newFileDialogOpacity = 0;
    });
    setTimeout(() => {
      this.showNewFileDialog = false;
      this.newFileName = '';
    }, 200);
    
    promptAction.showToast({ message: '新建文件成功' });
  }
  
  /**
   * 显示新建文件对话框
   */
  private showCreateFileDialog(): void {
    this.showNewFileDialog = true;
    this.newFileName = '';
    setTimeout(() => {
      animateTo({ duration: 200 }, () => {
        this.newFileDialogOpacity = 1;
      });
    }, 10);
  }
  
  /**
   * 导出文件
   */
  private async exportFile(): Promise<void> {
    if (!this.content) {
      promptAction.showToast({ message: '没有内容可导出' });
      return;
    }
    
    try {
      const documentSaveOptions = new picker.DocumentSaveOptions();
      documentSaveOptions.newFileNames = [this.fileName || 'untitled.txt'];
      const documentViewPicker = new picker.DocumentViewPicker();
      const uris = await documentViewPicker.save(documentSaveOptions);
      
      if (uris && uris.length > 0) {
        const encoder = new util.TextEncoder();
        const buffer = encoder.encodeInto(this.content);
        
        const destFile = await fileIo.open(uris[0], fileIo.OpenMode.CREATE | fileIo.OpenMode.WRITE_ONLY | fileIo.OpenMode.TRUNC);
        await fileIo.write(destFile.fd, buffer.buffer);
        await fileIo.close(destFile);
        
        promptAction.showToast({ message: '文件导出成功' });
        logger.info(TAG, `文件导出成功: ${uris[0]}`);
      }
    } catch (error) {
      logger.error(TAG, `导出文件失败: ${error}`);
      promptAction.showToast({ message: `导出文件失败: ${error}` });
    }
  }
  
  /**
   * 导入文件
   */
  private async importFile(): Promise<void> {
    try {
      const documentSelectOptions = new picker.DocumentSelectOptions();
      documentSelectOptions.maxSelectNumber = 1;
      const documentViewPicker = new picker.DocumentViewPicker();
      const uris = await documentViewPicker.select(documentSelectOptions);
      
      if (uris && uris.length > 0) {
        const uri = uris[0];
        
        // 检查是否已经打开
        const existingTab = this.tabs.find(t => t.filePath === uri);
        if (existingTab) {
          this.switchToTab(existingTab.id);
          promptAction.showToast({ message: '文件已打开' });
          return;
        }
        
        // 从URI中提取文件名
        const uriParts = uri.split('/');
        const fileName = decodeURIComponent(uriParts[uriParts.length - 1]) || '未命名文件';
        const ext = fileName.split('.').pop() || '';
        const language = fileEditorService.getLanguageByExtension(ext);
        
        // 直接从URI读取文件内容
        this.isLoading = true;
        const sourceFile = await fileIo.open(uri, fileIo.OpenMode.READ_ONLY);
        const stat = await fileIo.stat(sourceFile.fd);
        const buffer = new ArrayBuffer(stat.size);
        await fileIo.read(sourceFile.fd, buffer);
        await fileIo.close(sourceFile);
        
        const decoder = new util.TextDecoder('utf-8');
        const content = decoder.decodeWithStream(new Uint8Array(buffer));
        this.isLoading = false;
        
        // 添加到标签页
        this.addTab(uri, fileName, content, language, false);
        
        logger.info(TAG, `文件导入成功: ${fileName}, 大小: ${stat.size} bytes`);
        promptAction.showToast({ message: '文件导入成功' });
      }
    } catch (error) {
      this.isLoading = false;
      logger.error(TAG, `导入文件失败: ${error}`);
      promptAction.showToast({ message: `导入文件失败: ${error}` });
    }
  }
  
  /**
   * 构建使用说明面板
   */
  @Builder
  buildHelpPanel() {
    Column() {
      // 顶部栏
      Row() {
        Text('使用说明')
          .fontSize(18)
          .fontWeight(FontWeight.Bold)
          .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_primary', this.themeState.currentTheme))
        
        Blank()
        
        Button({ type: ButtonType.Normal }) {
          SymbolGlyph($r('sys.symbol.xmark'))
            .fontSize(20)
            .fontColor([ThemeAwareHelper.getTestManagementThemedColor('icon_primary', this.themeState.currentTheme)])
        }
        .width(36)
        .height(36)
        .backgroundColor(Color.Transparent)
        .onClick(() => {
          this.showHelp = false;
        })
      }
      .width('100%')
      .padding({ left: 16, right: 16, top: 16, bottom: 8 })
      
      // Markdown预览
      MarkdownViewerComponent({
        content: this.getHelpContent(),
        theme: this.editorTheme === EditorTheme.LIGHT ? MarkdownTheme.LIGHT : MarkdownTheme.DARK,
        fontSize: 14,
        callbacks: {}
      })
        .layoutWeight(1)
    }
    .width('100%')
    .height('100%')
    .backgroundColor(ThemeAwareHelper.getTestManagementThemedColor('background', this.themeState.currentTheme))
  }
  
  /**
   * 获取使用说明内容
   */
  private getHelpContent(): string {
    return `# 文件编辑器使用说明

## 功能概述

文件编辑器是一个内置的代码编辑工具，支持多种编程语言和文件格式的编辑，并提供Markdown实时预览功能。

## 支持的文件格式

### 编程语言
- **JavaScript/TypeScript** - .js, .ts, .jsx, .tsx
- **Python** - .py
- **Java/Kotlin** - .java, .kt
- **C/C++** - .c, .cpp, .h, .hpp
- **Go** - .go
- **Rust** - .rs
- **Swift** - .swift

### 标记语言
- **Markdown** - .md（支持实时预览）
- **HTML** - .html, .htm
- **XML** - .xml
- **JSON** - .json
- **YAML** - .yaml, .yml

### 其他格式
- **CSS/SCSS/LESS** - .css, .scss, .less
- **SQL** - .sql
- **Shell** - .sh, .bash
- **配置文件** - .ini, .conf, .properties

## 工具栏功能

| 图标 | 功能 | 说明 |
|------|------|------|
| 🔍 | 搜索 | 打开搜索栏，支持搜索和替换 |
| ↩️ | 撤销 | 撤销上一步操作 |
| ↪️ | 重做 | 重做已撤销的操作 |
| 📄 | 预览切换 | 切换编辑/预览/分屏模式（仅Markdown） |
| 💾 | 保存 | 保存文件（绿色表示有未保存更改） |
| ⚙️ | 设置 | 打开编辑器设置面板 |
| 📁 | 导入 | 导入本地文件 |
| ❓ | 帮助 | 显示本使用说明 |

## 编辑器设置

- **主题** - 深色/浅色/高对比度
- **字体大小** - 10-30px可调
- **显示行号** - 开启/关闭行号显示
- **显示小地图** - 开启/关闭代码缩略图
- **自动换行** - 开启/关闭自动换行

## Markdown预览

编辑Markdown文件时，支持三种显示模式：
1. **编辑模式** - 仅显示编辑器
2. **预览模式** - 仅显示渲染后的预览
3. **分屏模式** - 左侧编辑，右侧实时预览

### 支持的Markdown语法

- 标题（# ~ ######）
- **粗体**、*斜体*、~~删除线~~
- 有序/无序列表
- 代码块（支持语法高亮）
- 表格
- 链接和图片
- 引用块
- 任务列表
- 数学公式（LaTeX）

## 快捷操作

- **搜索** - 输入关键词后按回车或点击搜索按钮
- **替换** - 在搜索栏下方输入替换文本
- **全部替换** - 一键替换所有匹配项
- **导航** - 使用上下箭头在搜索结果间跳转

## 注意事项

1. 编辑大文件时可能会有性能影响
2. 建议定期保存文件，避免数据丢失
3. 部分系统文件可能为只读模式
4. Markdown预览需要网络加载渲染库

---

*文件编辑器 v1.0*
`;
  }
  
  /**
   * 构建工具栏
   */
  @Builder
  buildToolbar() {
    Scroll() {
      Row({ space: 4 }) {
        // 搜索
        Button({ type: ButtonType.Normal }) {
          SymbolGlyph($r('sys.symbol.magnifyingglass'))
            .fontSize(20)
            .fontColor([ThemeAwareHelper.getTestManagementThemedColor('icon_primary', this.themeState.currentTheme)])
        }
        .width(36)
        .height(36)
        .backgroundColor(this.showSearchBar ? ThemeAwareHelper.getTestManagementThemedColor('comp_background_tertiary', this.themeState.currentTheme) : Color.Transparent)
        .borderRadius(18)
        .onClick(() => {
          this.showSearchBar = !this.showSearchBar;
        })
        
        // 撤销
        if (!this.isReadOnly) {
          Button({ type: ButtonType.Normal }) {
            SymbolGlyph($r('sys.symbol.arrow_counterclockwise'))
              .fontSize(20)
              .fontColor([ThemeAwareHelper.getTestManagementThemedColor('icon_primary', this.themeState.currentTheme)])
          }
          .width(36)
          .height(36)
          .backgroundColor(Color.Transparent)
          .borderRadius(18)
          .onClick(() => {
            if (this.editorController) {
              this.editorController.undo();
            }
          })
          
          // 重做
          Button({ type: ButtonType.Normal }) {
            SymbolGlyph($r('sys.symbol.arrow_clockwise'))
              .fontSize(20)
              .fontColor([ThemeAwareHelper.getTestManagementThemedColor('icon_primary', this.themeState.currentTheme)])
          }
          .width(36)
          .height(36)
          .backgroundColor(Color.Transparent)
          .borderRadius(18)
          .onClick(() => {
            if (this.editorController) {
              this.editorController.redo();
            }
          })
        }
        
        // Markdown预览切换
        if (this.language === 'markdown') {
          Button({ type: ButtonType.Normal }) {
            SymbolGlyph($r('sys.symbol.rectangle_split_2x1'))
              .fontSize(20)
              .fontColor([ThemeAwareHelper.getTestManagementThemedColor('icon_primary', this.themeState.currentTheme)])
          }
          .width(36)
          .height(36)
          .backgroundColor(Color.Transparent)
          .borderRadius(18)
          .onClick(() => {
            if (this.editMode === EditMode.EDIT) {
              this.editMode = EditMode.PREVIEW;
            } else if (this.editMode === EditMode.PREVIEW) {
              this.editMode = EditMode.SPLIT;
            } else {
              this.editMode = EditMode.EDIT;
            }
          })
        }
        
        // 保存
        if (!this.isReadOnly) {
          Button({ type: ButtonType.Normal }) {
            if (this.isSaving) {
              LoadingProgress()
                .width(20)
                .height(20)
                .color(ThemeAwareHelper.getTestManagementThemedColor('icon_primary', this.themeState.currentTheme))
            } else {
              SymbolGlyph($r('sys.symbol.square_and_arrow_down'))
                .fontSize(20)
                .fontColor([this.isDirty ? '#4CAF50' : ThemeAwareHelper.getTestManagementThemedColor('icon_primary', this.themeState.currentTheme)])
            }
          }
          .width(36)
          .height(36)
          .backgroundColor(Color.Transparent)
          .borderRadius(18)
          .enabled(!this.isSaving)
          .onClick(() => this.saveFile())
        }
        
        // 设置
        Button({ type: ButtonType.Normal }) {
          SymbolGlyph($r('sys.symbol.gearshape'))
            .fontSize(20)
            .fontColor([ThemeAwareHelper.getTestManagementThemedColor('icon_primary', this.themeState.currentTheme)])
        }
        .width(36)
        .height(36)
        .backgroundColor(Color.Transparent)
        .borderRadius(18)
        .onClick(() => {
          this.openSettingsPanel();
        })
        
        // 新建文件
        Button({ type: ButtonType.Normal }) {
          SymbolGlyph($r('sys.symbol.doc_plaintext_and_pencil'))
            .fontSize(20)
            .fontColor([ThemeAwareHelper.getTestManagementThemedColor('icon_primary', this.themeState.currentTheme)])
        }
        .width(36)
        .height(36)
        .backgroundColor(Color.Transparent)
        .borderRadius(18)
        .onClick(() => this.showCreateFileDialog())
        
        // 导入文件
        Button({ type: ButtonType.Normal }) {
          SymbolGlyph($r('sys.symbol.folder_badge_eye'))
            .fontSize(20)
            .fontColor([ThemeAwareHelper.getTestManagementThemedColor('icon_primary', this.themeState.currentTheme)])
        }
        .width(36)
        .height(36)
        .backgroundColor(Color.Transparent)
        .borderRadius(18)
        .onClick(() => this.importFile())
        
        // 导出文件
        Button({ type: ButtonType.Normal }) {
          SymbolGlyph($r('sys.symbol.arrow_right_folder_circle'))
            .fontSize(20)
            .fontColor([ThemeAwareHelper.getTestManagementThemedColor('icon_primary', this.themeState.currentTheme)])
        }
        .width(36)
        .height(36)
        .backgroundColor(Color.Transparent)
        .borderRadius(18)
        .onClick(() => this.exportFile())
        
        // 帮助
        Button({ type: ButtonType.Normal }) {
          SymbolGlyph($r('sys.symbol.questionmark_circle'))
            .fontSize(20)
            .fontColor([ThemeAwareHelper.getTestManagementThemedColor('icon_primary', this.themeState.currentTheme)])
        }
        .width(36)
        .height(36)
        .backgroundColor(Color.Transparent)
        .borderRadius(18)
        .onClick(() => {
          this.showHelp = true;
        })
      }
      .padding({ left: 8, right: 8 })
    }
    .scrollable(ScrollDirection.Horizontal)
    .scrollBar(BarState.Off)
    .height(TITLE_BAR_HEIGHT_MINI)
    .width('100%')
    .padding({ top: 8 })
  }
}
