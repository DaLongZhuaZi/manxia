/**
 * 通用内容面板组件
 * 支持多种内容类型：帮助文档、更新日志、特效展示等
 * 支持多标签页、最小化悬浮球、自定义样式
 * 
 * 文件路径: entry/src/main/ets/Framework/Components/ContentPanel.ets
 */

import { logger } from 'manxia_core/src/main/ets/Utils/Logger';
import { ThemeAwareHelper } from './ThemeAware';
import { ThemeType } from '../Managers/ThemeManager';
import { AppColors, ColorRole } from '../Theme/AppColors';
import { MarkdownViewerComponent, MarkdownTheme, MarkdownReaderStyle } from '../../components/editor/MarkdownViewerComponent';
import { common } from '@kit.AbilityKit';
import { fileIo } from '@kit.CoreFileKit';
import { util } from '@kit.ArkTS';

const TAG = 'ContentPanel';

/**
 * 面板类型枚举
 */
export enum ContentPanelType {
  HELP = 'help',           // 帮助文档
  CHANGELOG = 'changelog', // 更新日志
  EFFECTS = 'effects',     // 特效展示
  INFO = 'info',           // 通用信息
  CUSTOM = 'custom'        // 自定义内容
}

/**
 * 内容来源类型
 */
export enum ContentSource {
  INLINE = 'inline',       // 内联Markdown字符串
  RAWFILE = 'rawfile',     // rawfile资源文件
  FILE = 'file'            // 沙箱文件路径
}

/**
 * 面板显示模式
 */
export enum PanelMode {
  HIDDEN = 'hidden',
  MINIMIZED = 'minimized',
  EXPANDED = 'expanded'
}

/**
 * 文字大小选项
 */
export enum PanelFontSize {
  SMALL = 13,
  MEDIUM = 15,
  LARGE = 18
}

/**
 * 悬浮球配置
 */
export interface FloatBallConfig {
  icon: Resource;
  color: ResourceColor;
  showBadge: boolean;
}

/**
 * 面板样式配置
 */
export interface PanelStyleConfig {
  width: string | number;
  height: string | number;
  borderRadius: number;
  showTabBar: boolean;
  showToolbar: boolean;
  showFloatBall: boolean;
  floatBallConfig?: FloatBallConfig;
}

/**
 * 标签页信息
 */
export interface ContentTab {
  id: string;
  title: string;
  type: ContentPanelType;
  source: ContentSource;
  content: string;
  markdownContent: string;
  isLoading: boolean;
  icon?: Resource;
}

/**
 * 面板配置
 */
export interface ContentPanelConfig {
  title: string;
  type: ContentPanelType;
  source: ContentSource;
  content: string;
  icon?: Resource;
}

/**
 * 默认样式配置
 */
const DEFAULT_STYLE_CONFIG: PanelStyleConfig = {
  width: '85%',
  height: '80%',
  borderRadius: 12,
  showTabBar: true,
  showToolbar: true,
  showFloatBall: true,
  floatBallConfig: {
    icon: $r('sys.symbol.doc_text_fill'),
    color: AppColors.primary,
    showBadge: true
  }
};

/**
 * 根据面板类型获取默认图标
 */
function getDefaultIconForType(type: ContentPanelType): Resource {
  switch (type) {
    case ContentPanelType.HELP:
      return $r('sys.symbol.questionmark_circle_fill');
    case ContentPanelType.CHANGELOG:
      return $r('sys.symbol.doc_text_fill');
    case ContentPanelType.EFFECTS:
      return $r('sys.symbol.star_fill');
    case ContentPanelType.INFO:
      return $r('sys.symbol.info_circle_fill');
    default:
      return $r('sys.symbol.doc_text_fill');
  }
}

/**
 * 根据面板类型获取默认标题
 */
function getDefaultTitleForType(type: ContentPanelType): string {
  switch (type) {
    case ContentPanelType.HELP:
      return '帮助';
    case ContentPanelType.CHANGELOG:
      return '更新日志';
    case ContentPanelType.EFFECTS:
      return '特效展示';
    case ContentPanelType.INFO:
      return '信息';
    default:
      return '内容';
  }
}

/**
 * 面板状态变化回调
 */
type PanelCallback = (mode: PanelMode, config: ContentPanelConfig | null) => void;

/**
 * 内容面板管理器 - 单例模式
 */
export class ContentPanelManager {
  private static instance: ContentPanelManager;
  private mode: PanelMode = PanelMode.HIDDEN;
  private tabs: ContentTab[] = [];
  private activeTabId: string = '';
  private fontSize: PanelFontSize = PanelFontSize.MEDIUM;
  private callback: PanelCallback | null = null;
  private globalStyleConfig: PanelStyleConfig = DEFAULT_STYLE_CONFIG;

  private constructor() {
    // 初始化时复制默认配置
    this.globalStyleConfig = this.copyStyleConfig(DEFAULT_STYLE_CONFIG);
  }

  /**
   * 复制样式配置（避免展开运算符）
   */
  private copyStyleConfig(source: PanelStyleConfig): PanelStyleConfig {
    const result: PanelStyleConfig = {
      width: source.width,
      height: source.height,
      borderRadius: source.borderRadius,
      showTabBar: source.showTabBar,
      showToolbar: source.showToolbar,
      showFloatBall: source.showFloatBall
    };
    if (source.floatBallConfig) {
      result.floatBallConfig = {
        icon: source.floatBallConfig.icon,
        color: source.floatBallConfig.color,
        showBadge: source.floatBallConfig.showBadge
      };
    }
    return result;
  }

  /**
   * 合并样式配置（避免展开运算符）
   */
  private mergeStyleConfig(base: PanelStyleConfig, override: Partial<PanelStyleConfig>): PanelStyleConfig {
    const result = this.copyStyleConfig(base);
    if (override.width !== undefined) result.width = override.width;
    if (override.height !== undefined) result.height = override.height;
    if (override.borderRadius !== undefined) result.borderRadius = override.borderRadius;
    if (override.showTabBar !== undefined) result.showTabBar = override.showTabBar;
    if (override.showToolbar !== undefined) result.showToolbar = override.showToolbar;
    if (override.showFloatBall !== undefined) result.showFloatBall = override.showFloatBall;
    if (override.floatBallConfig) {
      result.floatBallConfig = {
        icon: override.floatBallConfig.icon,
        color: override.floatBallConfig.color,
        showBadge: override.floatBallConfig.showBadge
      };
    }
    return result;
  }

  static getInstance(): ContentPanelManager {
    if (!ContentPanelManager.instance) {
      ContentPanelManager.instance = new ContentPanelManager();
    }
    return ContentPanelManager.instance;
  }

  /**
   * 设置全局样式配置
   */
  setGlobalStyleConfig(config: Partial<PanelStyleConfig>): void {
    this.globalStyleConfig = this.mergeStyleConfig(this.globalStyleConfig, config);
  }

  /**
   * 获取全局样式配置
   */
  getGlobalStyleConfig(): PanelStyleConfig {
    return this.copyStyleConfig(this.globalStyleConfig);
  }

  /**
   * 添加标签页
   */
  addTab(config: ContentPanelConfig): string {
    const id = `panel_${Date.now()}_${Math.random().toString(36).substr(2, 9)}`;
    const isInline = config.source === ContentSource.INLINE;
    
    const tab: ContentTab = {
      id,
      title: config.title,
      type: config.type,
      source: config.source,
      content: config.content,
      markdownContent: isInline ? config.content : '',
      isLoading: !isInline,
      icon: config.icon || getDefaultIconForType(config.type)
    };
    
    this.tabs.push(tab);
    this.activeTabId = id;
    
    if (this.mode === PanelMode.HIDDEN || this.mode === PanelMode.MINIMIZED) {
      this.mode = PanelMode.EXPANDED;
    }
    
    logger.info(TAG, `添加标签: ${config.title}, 类型: ${config.type}, ID: ${id}`);
    this.notifyCallback();
    return id;
  }

  /**
   * 关闭标签页
   */
  closeTab(tabId: string): void {
    const index = this.tabs.findIndex(t => t.id === tabId);
    if (index !== -1) {
      this.tabs.splice(index, 1);
      if (this.activeTabId === tabId) {
        this.activeTabId = this.tabs.length > 0 ? this.tabs[this.tabs.length - 1].id : '';
      }
      if (this.tabs.length === 0) {
        this.mode = PanelMode.HIDDEN;
      }
      logger.info(TAG, `关闭标签: ${tabId}`);
      this.notifyCallback();
    }
  }

  /**
   * 切换活动标签
   */
  setActiveTab(tabId: string): void {
    if (this.tabs.some(t => t.id === tabId)) {
      this.activeTabId = tabId;
      this.notifyCallback();
    }
  }

  /**
   * 更新标签内容
   */
  updateTabContent(tabId: string, markdownContent: string): void {
    const tab = this.tabs.find(t => t.id === tabId);
    if (tab) {
      tab.markdownContent = markdownContent;
      tab.isLoading = false;
      this.notifyCallback();
    }
  }

  /**
   * 展开面板
   */
  expand(): void {
    if (this.tabs.length > 0) {
      this.mode = PanelMode.EXPANDED;
      this.notifyCallback();
    }
  }

  /**
   * 最小化为悬浮球
   */
  minimize(): void {
    if (this.tabs.length > 0) {
      this.mode = PanelMode.MINIMIZED;
      this.notifyCallback();
    }
  }

  /**
   * 隐藏面板（关闭所有标签）
   */
  hide(): void {
    this.tabs = [];
    this.activeTabId = '';
    this.mode = PanelMode.HIDDEN;
    this.notifyCallback();
  }

  /**
   * 设置字体大小
   */
  setFontSize(size: PanelFontSize): void {
    this.fontSize = size;
    this.notifyCallback();
  }

  // Getters
  getMode(): PanelMode { return this.mode; }
  getTabs(): ContentTab[] { return this.tabs.slice(); }
  getActiveTabId(): string { return this.activeTabId; }
  getActiveTab(): ContentTab | null { return this.tabs.find(t => t.id === this.activeTabId) || null; }
  getFontSize(): PanelFontSize { return this.fontSize; }

  /**
   * 注册回调
   */
  registerCallback(callback: PanelCallback): void {
    this.callback = callback;
  }

  unregisterCallback(): void {
    this.callback = null;
  }

  private notifyCallback(): void {
    if (this.callback) {
      const activeTab = this.getActiveTab();
      const config: ContentPanelConfig | null = activeTab ? {
        title: activeTab.title,
        type: activeTab.type,
        source: activeTab.source,
        content: activeTab.content,
        icon: activeTab.icon
      } : null;
      this.callback(this.mode, config);
    }
  }

  // ==================== 快捷方法 ====================

  /**
   * 显示帮助文档
   */
  showHelp(title: string, content: string, source: ContentSource = ContentSource.INLINE): string {
    return this.addTab({
      title,
      type: ContentPanelType.HELP,
      source,
      content
    });
  }

  /**
   * 显示更新日志
   */
  showChangelog(title: string = '更新日志', content: string, source: ContentSource = ContentSource.INLINE): string {
    return this.addTab({
      title,
      type: ContentPanelType.CHANGELOG,
      source,
      content,
      icon: $r('sys.symbol.doc_text_fill')
    });
  }

  /**
   * 显示特效展示（使用Markdown内容）
   */
  showEffects(title: string, content: string, source: ContentSource = ContentSource.INLINE): string {
    return this.addTab({
      title,
      type: ContentPanelType.EFFECTS,
      source,
      content,
      icon: $r('sys.symbol.star_fill')
    });
  }

  /**
   * 显示通用信息
   */
  showInfo(title: string, content: string, source: ContentSource = ContentSource.INLINE): string {
    return this.addTab({
      title,
      type: ContentPanelType.INFO,
      source,
      content
    });
  }

  /**
   * 显示自定义内容（使用Markdown）
   */
  showCustom(title: string, content: string, source: ContentSource = ContentSource.INLINE, icon?: Resource): string {
    return this.addTab({
      title,
      type: ContentPanelType.CUSTOM,
      source,
      content,
      icon
    });
  }

  // ==================== 兼容旧API ====================

  /**
   * 兼容旧版API - 显示内联帮助
   */
  showInlineHelp(title: string, markdownContent: string): string {
    return this.showHelp(title, markdownContent, ContentSource.INLINE);
  }

  /**
   * 兼容旧版API - 显示rawfile帮助
   */
  showRawfileHelp(title: string, rawfilePath: string): string {
    return this.showHelp(title, rawfilePath, ContentSource.RAWFILE);
  }
}

export function getContentPanelManager(): ContentPanelManager {
  return ContentPanelManager.getInstance();
}

// ==================== 兼容旧版导出 ====================
export const getHelpPanelManagerV2 = getContentPanelManager;
export type HelpPanelManagerV2 = ContentPanelManager;
export type HelpTab = ContentTab;
export type HelpPanelConfig = ContentPanelConfig;
export { ContentSource as HelpContentSource };
export { PanelMode as HelpPanelMode };
export { PanelFontSize as HelpFontSize };

interface ContentPanelThemeState {
  currentTheme: ThemeType;
}

/**
 * 内容面板覆盖层组件
 */
@Component
export struct ContentPanelOverlay {
  @Prop themeState: ContentPanelThemeState = { currentTheme: ThemeType.DARK };
  // 帮助中心导航回调（由宿主页面提供）
  onNavigateToHelpCenter?: () => void;
  @State private mode: PanelMode = PanelMode.HIDDEN;
  @State private tabs: ContentTab[] = [];
  @State private activeTabId: string = '';
  @State private fontSize: PanelFontSize = PanelFontSize.MEDIUM;
  @State private panelScale: number = 0;
  @State private floatBallX: number = 20;
  @State private floatBallY: number = 200;
  @State private isDragging: boolean = false;
  @State private contentOpacity: number = 1;
  @State private styleConfig: PanelStyleConfig = DEFAULT_STYLE_CONFIG;

  // 横向滑动切换标签页相关状态
  @State private swipeStartX: number = 0;
  @State private swipeOffsetX: number = 0;

  @State private isFontSizePopupOpen: boolean = false;

  private panelManager: ContentPanelManager = getContentPanelManager();
  private dragStartX: number = 0;
  private dragStartY: number = 0;
  private ballStartX: number = 0;
  private ballStartY: number = 0;

  aboutToAppear(): void {
    logger.info(TAG, '内容面板初始化');
    this.styleConfig = this.panelManager.getGlobalStyleConfig();
    
    this.panelManager.registerCallback((mode: PanelMode) => {
      this.syncState();
      
      if (mode === PanelMode.EXPANDED && this.panelScale === 0) {
        this.getUIContext().animateTo({ duration: 250, curve: Curve.EaseOut }, () => { 
          this.panelScale = 1; 
        });
      }
    });
    
    this.syncState();
  }

  private syncState(): void {
    this.mode = this.panelManager.getMode();
    this.tabs = this.panelManager.getTabs();
    this.activeTabId = this.panelManager.getActiveTabId();
    this.fontSize = this.panelManager.getFontSize();
    this.styleConfig = this.panelManager.getGlobalStyleConfig();
    
    // 加载需要加载的标签内容
    for (const tab of this.tabs) {
      if (tab.isLoading && !tab.markdownContent) {
        this.loadTabContent(tab);
      }
    }
  }

  aboutToDisappear(): void {
    this.panelManager.unregisterCallback();
  }

  private async loadTabContent(tab: ContentTab): Promise<void> {
    await this.loadTabContentById(tab.id, tab.title, tab.source, tab.content);
  }

  private async loadTabContentById(tabId: string, title: string, source: ContentSource, rawContent: string): Promise<void> {
    logger.info(TAG, `加载标签内容: ${title}, source: ${source}, path: ${rawContent}`);
    try {
      let content = '';
      switch (source) {
        case ContentSource.INLINE:
          content = rawContent;
          break;
        case ContentSource.RAWFILE:
          content = await this.loadRawfileContent(rawContent);
          break;
        case ContentSource.FILE:
          content = await this.loadFileContent(rawContent);
          break;
      }
      logger.info(TAG, `标签内容加载成功: ${title}, 长度: ${content.length}`);
      this.panelManager.updateTabContent(tabId, content);
      this.tabs = this.panelManager.getTabs();
    } catch (error) {
      logger.error(TAG, `标签内容加载失败: ${title}, 错误: ${String(error)}`);
      this.panelManager.updateTabContent(tabId, `# 加载失败\n\n${String(error)}`);
      this.tabs = this.panelManager.getTabs();
    }
  }

  private async loadRawfileContent(path: string): Promise<string> {
    try {
      const context = (this.getUIContext().getHostContext() as common.UIAbilityContext) as common.UIAbilityContext;
      logger.info(TAG, `加载rawfile: ${path}`);
      const content = await context.resourceManager.getRawFileContent(path);
      const text = new util.TextDecoder('utf-8').decodeToString(content);
      logger.info(TAG, `rawfile加载成功: ${path}, 内容长度: ${text.length}`);
      return text;
    } catch (error) {
      logger.error(TAG, `rawfile加载失败: ${path}, 错误: ${String(error)}`);
      throw error as Error;
    }
  }

  private async loadFileContent(path: string): Promise<string> {
    const file = await fileIo.open(path, fileIo.OpenMode.READ_ONLY);
    const stat = await fileIo.stat(path);
    const buffer = new ArrayBuffer(stat.size);
    await fileIo.read(file.fd, buffer);
    await fileIo.close(file.fd);
    return new util.TextDecoder('utf-8').decodeToString(new Uint8Array(buffer));
  }

  private buildPanelMarkdownReaderStyle(): MarkdownReaderStyle {
    const theme = this.themeState.currentTheme;
    return {
      fontSize: this.fontSize as number,
      lineHeight: 1.62,
      fontFamily: 'HarmonyOS Sans',
      fontWeight: 400,
      textColor: AppColors.getColorForTheme(ColorRole.ON_SURFACE, theme),
      backgroundColor: AppColors.getColorForTheme(ColorRole.SURFACE, theme),
      pageMargin: 18,
      pageTopMargin: 18,
      pageBottomMargin: 24,
      letterSpacing: 0,
      paragraphSpacing: 8,
      firstLineIndent: 0,
      textAlignment: 'LEFT',
      pageMode: '0',
      pageTurnAnimation: 'NONE',
      tapToTurn: false
    };
  }

  /**
   * 切换到下一个标签页（支持循环）
   */
  private switchToNextTab(): void {
    if (this.tabs.length <= 1) return;
    const currentIndex = this.tabs.findIndex(t => t.id === this.activeTabId);
    const nextIndex = (currentIndex + 1) % this.tabs.length;
    this.panelManager.setActiveTab(this.tabs[nextIndex].id);
  }
  
  /**
   * 切换到上一个标签页（支持循环）
   */
  private switchToPrevTab(): void {
    if (this.tabs.length <= 1) return;
    const currentIndex = this.tabs.findIndex(t => t.id === this.activeTabId);
    const prevIndex = (currentIndex - 1 + this.tabs.length) % this.tabs.length;
    this.panelManager.setActiveTab(this.tabs[prevIndex].id);
  }

  private getActiveTabIcon(): Resource {
    const activeTab = this.tabs.find(t => t.id === this.activeTabId);
    return activeTab?.icon || $r('sys.symbol.doc_text_fill');
  }

  private getPanelTitle(): string {
    const activeTab = this.tabs.find(t => t.id === this.activeTabId);
    if (!activeTab) return '内容面板';
    return getDefaultTitleForType(activeTab.type);
  }

  @Builder
  buildFloatingBall() {
    Stack() {
      Column() {
        SymbolGlyph(this.getActiveTabIcon())
          .fontSize(28)
          .fontColor([ThemeAwareHelper.getTestManagementThemedColor('accent_primary', this.themeState.currentTheme)])
      }
      .width(48)
      .height(48)
      .borderRadius(24)
      .backgroundColor(ThemeAwareHelper.getTestManagementThemedColor('panel_background', this.themeState.currentTheme))
      .shadow({ radius: 8, color: AppColors.getShadowColor(4), offsetX: 2, offsetY: 2 })
      .justifyContent(FlexAlign.Center)
      
      if (this.tabs.length > 1 && this.styleConfig.floatBallConfig?.showBadge) {
        Text(`${this.tabs.length}`)
          .fontSize(10)
          .fontColor(Color.White)
          .backgroundColor(AppColors.error)
          .borderRadius(8)
          .padding({ left: 4, right: 4 })
          .position({ x: 32, y: 0 })
      }
    }
    .width(48)
    .height(48)
    .position({ x: this.floatBallX, y: this.floatBallY })
    .gesture(
      PanGesture()
        .onActionStart((event: GestureEvent) => {
          this.isDragging = true;
          this.dragStartX = event.offsetX;
          this.dragStartY = event.offsetY;
          this.ballStartX = this.floatBallX;
          this.ballStartY = this.floatBallY;
        })
        .onActionUpdate((event: GestureEvent) => {
          if (this.isDragging) {
            this.floatBallX = this.ballStartX + event.offsetX - this.dragStartX;
            this.floatBallY = this.ballStartY + event.offsetY - this.dragStartY;
          }
        })
        .onActionEnd(() => {
          this.isDragging = false;
        })
    )
    .onClick(() => { 
      if (!this.isDragging) {
        this.panelManager.expand(); 
      }
    })
  }

  @Builder
  buildTabBar() {
    if (this.styleConfig.showTabBar && this.tabs.length > 0) {
      Scroll() {
        Row({ space: 0 }) {
          ForEach(this.tabs, (tab: ContentTab) => {
            Row() {
              if (tab.icon) {
                SymbolGlyph(tab.icon)
                  .fontSize(12)
                  .fontColor([this.activeTabId === tab.id
                    ? ThemeAwareHelper.getTestManagementThemedColor('accent_primary', this.themeState.currentTheme)
                    : ThemeAwareHelper.getTestManagementThemedColor('text_secondary', this.themeState.currentTheme)])
                  .margin({ right: 4 })
              }
              
              Text(tab.title)
                .fontSize(12)
                .fontColor(this.activeTabId === tab.id
                  ? ThemeAwareHelper.getTestManagementThemedColor('text_primary', this.themeState.currentTheme)
                  : ThemeAwareHelper.getTestManagementThemedColor('text_secondary', this.themeState.currentTheme))
                .maxLines(1)
                .textOverflow({ overflow: TextOverflow.Ellipsis })
                .constraintSize({ maxWidth: 120 })
              
              Button({ type: ButtonType.Circle, stateEffect: true }) {
                SymbolGlyph($r('sys.symbol.xmark'))
                  .fontSize(10)
                  .fontColor([ThemeAwareHelper.getTestManagementThemedColor('text_muted', this.themeState.currentTheme)])
              }
              .width(18)
              .height(18)
              .backgroundColor(Color.Transparent)
              .margin({ left: 4 })
              .onClick(() => {
                this.panelManager.closeTab(tab.id);
              })
            }
            .padding({ left: 10, right: 8 })
            .height(32)
            .alignItems(VerticalAlign.Center)
            .backgroundColor(this.activeTabId === tab.id
              ? ThemeAwareHelper.getTestManagementThemedColor('background', this.themeState.currentTheme)
              : Color.Transparent)
            .border({
              width: { top: this.activeTabId === tab.id ? 2 : 0 },
              color: ThemeAwareHelper.getTestManagementThemedColor('accent_primary', this.themeState.currentTheme)
            })
            .onClick(() => { this.panelManager.setActiveTab(tab.id); })
          })
        }
      }
      .scrollable(ScrollDirection.Horizontal)
      .scrollBar(BarState.Off)
      .width('100%')
      .height(32)
      .backgroundColor(ThemeAwareHelper.getTestManagementThemedColor('comp_background_tertiary', this.themeState.currentTheme))
    }
  }

  private refreshCurrentTab(): void {
    const activeTab = this.tabs.find(t => t.id === this.activeTabId);
    if (activeTab) {
      activeTab.isLoading = true;
      activeTab.markdownContent = '';
      this.tabs = this.tabs.slice();
      this.loadTabContent(activeTab);
    }
  }

  private closeWithAnimation(): void {
    this.getUIContext().animateTo({ 
      duration: 200, 
      curve: Curve.EaseIn,
      onFinish: () => {
        this.panelManager.hide();
      }
    }, () => { 
      this.panelScale = 0; 
    });
  }

  private minimizeWithAnimation(): void {
    this.getUIContext().animateTo({ 
      duration: 200, 
      curve: Curve.EaseIn,
      onFinish: () => {
        this.panelManager.minimize();
      }
    }, () => { 
      this.panelScale = 0; 
    });
  }

  @Builder
  buildFontSizePopup() {
    Column() {
      Text('字体大小')
        .fontSize(14)
        .fontWeight(FontWeight.Medium)
        .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_primary', this.themeState.currentTheme))
        .margin({ bottom: 12 })

      Row({ space: 8 }) {
        Text('A').fontSize(12).fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_secondary', this.themeState.currentTheme))
        Slider({
          value: this.fontSize as number,
          min: 12,
          max: 24,
          step: 1,
          style: SliderStyle.OutSet
        })
          .width(120)
          .onChange((value: number) => {
            this.fontSize = value as PanelFontSize;
            this.panelManager.setFontSize(this.fontSize);
          })
        Text('A').fontSize(18).fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_secondary', this.themeState.currentTheme))
      }
    }
    .padding(16)
    .backgroundColor(ThemeAwareHelper.getTestManagementThemedColor('background', this.themeState.currentTheme))
    .borderRadius(12)
  }

  @Builder
  buildToolbar() {
    if (this.styleConfig.showToolbar) {
      Row({ space: 8 }) {
        Row({ space: 6 }) {
          SymbolGlyph(this.getActiveTabIcon())
            .fontSize(16)
            .fontColor([ThemeAwareHelper.getTestManagementThemedColor('accent_primary', this.themeState.currentTheme)])
          Text(this.getPanelTitle())
            .fontSize(14)
            .fontWeight(FontWeight.Medium)
            .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_primary', this.themeState.currentTheme))
        }

        Blank()

        // 帮助中心按钮
        Button({ type: ButtonType.Circle, stateEffect: true }) {
          SymbolGlyph($r('sys.symbol.questionmark_circle')).fontSize(14).fontColor([ThemeAwareHelper.getTestManagementThemedColor('text_secondary', this.themeState.currentTheme)])
        }
        .width(28).height(28)
        .backgroundColor(ThemeAwareHelper.getTestManagementThemedColor('comp_background_tertiary', this.themeState.currentTheme))
        .onClick(() => {
          if (this.onNavigateToHelpCenter) {
            this.minimizeWithAnimation();
            this.onNavigateToHelpCenter();
          }
        })

        // 字体大小按钮
        Button({ type: ButtonType.Circle, stateEffect: true }) {
          SymbolGlyph($r('sys.symbol.textformat')).fontSize(14).fontColor([ThemeAwareHelper.getTestManagementThemedColor('text_secondary', this.themeState.currentTheme)])
        }
        .width(28).height(28)
        .backgroundColor(ThemeAwareHelper.getTestManagementThemedColor('comp_background_tertiary', this.themeState.currentTheme))
        .bindPopup(this.isFontSizePopupOpen, {
          builder: this.buildFontSizePopup(),
          placement: Placement.Bottom,
          mask: false,
          onStateChange: (e) => {
            if (!e.isVisible) {
              this.isFontSizePopupOpen = false;
            }
          }
        })
        .onClick(() => { this.isFontSizePopupOpen = !this.isFontSizePopupOpen; })

        // 刷新按钮
        Button({ type: ButtonType.Circle, stateEffect: true }) {
          SymbolGlyph($r('sys.symbol.arrow_clockwise')).fontSize(14).fontColor([ThemeAwareHelper.getTestManagementThemedColor('text_secondary', this.themeState.currentTheme)])
        }
        .width(28).height(28)
        .backgroundColor(ThemeAwareHelper.getTestManagementThemedColor('comp_background_tertiary', this.themeState.currentTheme))
        .onClick(() => { this.refreshCurrentTab(); })

        // 最小化按钮
        if (this.styleConfig.showFloatBall) {
          Button({ type: ButtonType.Circle, stateEffect: true }) {
            SymbolGlyph($r('sys.symbol.minus')).fontSize(14).fontColor([ThemeAwareHelper.getTestManagementThemedColor('text_secondary', this.themeState.currentTheme)])
          }
          .width(28).height(28)
          .backgroundColor(ThemeAwareHelper.getTestManagementThemedColor('comp_background_tertiary', this.themeState.currentTheme))
          .onClick(() => { this.minimizeWithAnimation(); })
        }

        // 关闭按钮
        Button({ type: ButtonType.Circle, stateEffect: true }) {
          SymbolGlyph($r('sys.symbol.xmark')).fontSize(14).fontColor([ThemeAwareHelper.getTestManagementThemedColor('text_secondary', this.themeState.currentTheme)])
        }
        .width(28).height(28)
        .backgroundColor(ThemeAwareHelper.getTestManagementThemedColor('comp_background_tertiary', this.themeState.currentTheme))
        .onClick(() => { this.closeWithAnimation(); })
      }
      .width('100%')
      .padding({ left: 12, right: 12, top: 8, bottom: 8 })
    }
  }

  @Builder
  buildContent(tab: ContentTab) {
    if (tab.isLoading) {
      Column() {
        LoadingProgress()
          .width(32)
          .height(32)
          .color(ThemeAwareHelper.getTestManagementThemedColor('accent_primary', this.themeState.currentTheme))
        Text('加载中...')
          .fontSize(13)
          .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_secondary', this.themeState.currentTheme))
          .margin({ top: 8 })
      }
      .width('100%')
      .layoutWeight(1)
      .justifyContent(FlexAlign.Center)
    } else {
      // Markdown内容
      MarkdownViewerComponent({
        content: tab.markdownContent,
        theme: this.themeState.currentTheme === ThemeType.DARK ? MarkdownTheme.DARK : MarkdownTheme.LIGHT,
        fontSize: this.fontSize,
        readerStyle: this.buildPanelMarkdownReaderStyle()
      })
        .width('100%')
        .layoutWeight(1)
    }
  }

  build() {
    Stack() {
      // 最小化悬浮球
      if (this.mode === PanelMode.MINIMIZED && this.styleConfig.showFloatBall) {
        this.buildFloatingBall()
      }

      // 展开的面板
      if (this.mode === PanelMode.EXPANDED) {
        Column() {
          // 工具栏
          this.buildToolbar()
          
          // 标签栏
          this.buildTabBar()

          // 内容区域
          if (this.tabs.length > 0) {
            Column() {
              ForEach(this.tabs.filter(t => t.id === this.activeTabId), (tab: ContentTab) => {
                this.buildContent(tab)
              }, (tab: ContentTab) => `${tab.id}_${tab.isLoading}_${tab.markdownContent?.length || 0}`)
            }
            .width('100%')
            .layoutWeight(1)
            .gesture(
              PanGesture({ fingers: 1, direction: PanDirection.Horizontal, distance: 5 })
                .onActionStart((event: GestureEvent) => {
                  this.swipeStartX = event.offsetX;
                  this.swipeOffsetX = 0;
                })
                .onActionUpdate((event: GestureEvent) => {
                  this.swipeOffsetX = event.offsetX - this.swipeStartX;
                })
                .onActionEnd((event: GestureEvent) => {
                  const swipeThreshold = 80;
                  if (this.swipeOffsetX < -swipeThreshold) {
                    this.switchToNextTab();
                  } else if (this.swipeOffsetX > swipeThreshold) {
                    this.switchToPrevTab();
                  }
                  this.swipeOffsetX = 0;
                })
            )
          }
        }
        .width(this.styleConfig.width)
        .height(this.styleConfig.height)
        .backgroundColor(ThemeAwareHelper.getTestManagementThemedColor('background', this.themeState.currentTheme))
        .borderRadius(this.styleConfig.borderRadius)
        .clip(true)
        .shadow({ radius: 16, color: AppColors.getShadowColor(3), offsetX: 0, offsetY: 4 })
        .scale({ x: this.panelScale, y: this.panelScale })
        .opacity(this.contentOpacity)
        .position({ x: '7.5%', y: '10%' })
      }
    }
    .width('100%')
    .height('100%')
    .hitTestBehavior(this.mode === PanelMode.MINIMIZED ? HitTestMode.Transparent : 
                     (this.mode === PanelMode.HIDDEN ? HitTestMode.None : HitTestMode.Default))
  }
}

// 兼容旧版导出
export { ContentPanelOverlay as HelpPanelOverlayV2 };
