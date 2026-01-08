/**
 * 全局帮助信息面板组件
 * 支持多标签页、最小化悬浮球、文字大小调整
 * 使用Markdown渲染帮助内容
 * 
 * 文件路径: entry/src/main/ets/Framework/Components/HelpPanel.ets
 */

import { logger } from '../../Utils/Logger';
import { ThemeAwareHelper } from './ThemeAware';
import { ThemeType } from '../Managers/ThemeManager';
import { MarkdownViewerComponent, MarkdownTheme } from '../../components/editor/MarkdownViewerComponent';
import { common } from '@kit.AbilityKit';
import { fileIo } from '@kit.CoreFileKit';
import { util } from '@kit.ArkTS';

const TAG = 'HelpPanel';

/**
 * 帮助标签页信息
 */
export interface HelpTab {
  id: string;
  title: string;
  source: HelpContentSource;
  content: string;
  markdownContent: string;
  isLoading: boolean;
}

/**
 * 文字大小选项
 */
export enum HelpFontSize {
  SMALL = 13,
  MEDIUM = 15,
  LARGE = 18
}

/**
 * 面板显示模式
 */
export enum HelpPanelMode {
  HIDDEN = 'hidden',
  MINIMIZED = 'minimized',
  EXPANDED = 'expanded'
}

/**
 * 帮助内容来源类型
 */
export enum HelpContentSource {
  INLINE = 'inline',      // 内联Markdown字符串
  RAWFILE = 'rawfile',    // rawfile资源文件
  FILE = 'file'           // 沙箱文件路径
}

/**
 * 帮助面板配置
 */
export interface HelpPanelConfig {
  title: string;
  source: HelpContentSource;
  content: string;  // 根据source类型：内联内容、rawfile路径或文件路径
}

/**
 * 帮助面板管理器 - 单例模式
 */
export class HelpPanelManager {
  private static instance: HelpPanelManager;
  private isVisible: boolean = false;
  private currentConfig: HelpPanelConfig | null = null;
  private onVisibilityChange: ((visible: boolean, config: HelpPanelConfig | null) => void) | null = null;

  private constructor() {}

  static getInstance(): HelpPanelManager {
    if (!HelpPanelManager.instance) {
      HelpPanelManager.instance = new HelpPanelManager();
    }
    return HelpPanelManager.instance;
  }

  /**
   * 显示帮助面板
   */
  show(config: HelpPanelConfig): void {
    logger.info(TAG, `显示帮助面板: ${config.title}`);
    this.currentConfig = config;
    this.isVisible = true;
    if (this.onVisibilityChange) {
      this.onVisibilityChange(true, config);
    }
  }

  /**
   * 隐藏帮助面板
   */
  hide(): void {
    logger.info(TAG, '隐藏帮助面板');
    this.isVisible = false;
    if (this.onVisibilityChange) {
      this.onVisibilityChange(false, null);
    }
  }

  /**
   * 切换帮助面板显示状态
   */
  toggle(config: HelpPanelConfig): void {
    if (this.isVisible) {
      this.hide();
    } else {
      this.show(config);
    }
  }

  /**
   * 获取当前显示状态
   */
  getIsVisible(): boolean {
    return this.isVisible;
  }

  /**
   * 获取当前配置
   */
  getCurrentConfig(): HelpPanelConfig | null {
    return this.currentConfig;
  }

  /**
   * 注册可见性变化回调
   */
  registerCallback(callback: (visible: boolean, config: HelpPanelConfig | null) => void): void {
    this.onVisibilityChange = callback;
  }

  /**
   * 取消注册回调
   */
  unregisterCallback(): void {
    this.onVisibilityChange = null;
  }

  /**
   * 快捷方法：显示内联Markdown帮助
   */
  showInlineHelp(title: string, markdownContent: string): void {
    this.show({
      title,
      source: HelpContentSource.INLINE,
      content: markdownContent
    });
  }

  /**
   * 快捷方法：显示rawfile帮助文件
   */
  showRawfileHelp(title: string, rawfilePath: string): void {
    this.show({
      title,
      source: HelpContentSource.RAWFILE,
      content: rawfilePath
    });
  }
}

/**
 * 获取帮助面板管理器实例
 */
export function getHelpPanelManager(): HelpPanelManager {
  return HelpPanelManager.getInstance();
}

/**
 * 帮助面板主题状态接口
 */
interface HelpPanelThemeState {
  currentTheme: ThemeType;
}

/**
 * 帮助面板组件
 * 全局使用，放置在页面根部
 */
@Component
export struct HelpPanelOverlay {
  @Prop themeState: HelpPanelThemeState = { currentTheme: ThemeType.DARK };
  @State private isVisible: boolean = false;
  @State private config: HelpPanelConfig | null = null;
  @State private markdownContent: string = '';
  @State private isLoading: boolean = false;
  @State private panelOffset: number = 1000;  // 初始在屏幕外
  
  private helpManager: HelpPanelManager = getHelpPanelManager();

  aboutToAppear(): void {
    logger.info(TAG, '帮助面板覆盖层初始化');
    this.helpManager.registerCallback((visible: boolean, config: HelpPanelConfig | null) => {
      if (visible && config) {
        this.config = config;
        this.loadContent(config);
        this.showPanel();
      } else {
        this.hidePanel();
      }
    });
  }

  aboutToDisappear(): void {
    this.helpManager.unregisterCallback();
  }

  private showPanel(): void {
    this.isVisible = true;
    // 动画滑入
    animateTo({
      duration: 300,
      curve: Curve.EaseOut
    }, () => {
      this.panelOffset = 0;
    });
  }

  private hidePanel(): void {
    // 动画滑出
    animateTo({
      duration: 250,
      curve: Curve.EaseIn,
      onFinish: () => {
        this.isVisible = false;
        this.config = null;
        this.markdownContent = '';
      }
    }, () => {
      this.panelOffset = 1000;
    });
  }

  private async loadContent(config: HelpPanelConfig): Promise<void> {
    this.isLoading = true;
    try {
      switch (config.source) {
        case HelpContentSource.INLINE:
          this.markdownContent = config.content;
          break;
        case HelpContentSource.RAWFILE:
          this.markdownContent = await this.loadRawfileContent(config.content);
          break;
        case HelpContentSource.FILE:
          this.markdownContent = await this.loadFileContent(config.content);
          break;
      }
    } catch (error) {
      logger.error(TAG, `加载帮助内容失败: ${String(error)}`);
      this.markdownContent = `# 加载失败\n\n无法加载帮助内容: ${String(error)}`;
    } finally {
      this.isLoading = false;
    }
  }

  private async loadRawfileContent(path: string): Promise<string> {
    try {
      const context = getContext(this) as common.UIAbilityContext;
      const resourceManager = context.resourceManager;
      const content = await resourceManager.getRawFileContent(path);
      const decoder = new util.TextDecoder('utf-8');
      return decoder.decodeToString(content);
    } catch (error) {
      throw new Error(`读取rawfile失败: ${path}`);
    }
  }

  private async loadFileContent(path: string): Promise<string> {
    try {
      const file = await fileIo.open(path, fileIo.OpenMode.READ_ONLY);
      const stat = await fileIo.stat(path);
      const buffer = new ArrayBuffer(stat.size);
      await fileIo.read(file.fd, buffer);
      await fileIo.close(file.fd);
      const decoder = new util.TextDecoder('utf-8');
      return decoder.decodeToString(new Uint8Array(buffer));
    } catch (error) {
      throw new Error(`读取文件失败: ${path}`);
    }
  }

  build() {
    if (this.isVisible) {
      Stack() {
        // 半透明背景遮罩
        Column()
          .width('100%')
          .height('100%')
          .backgroundColor('#80000000')
          .onClick(() => {
            this.helpManager.hide();
          })

        // 帮助面板
        Column() {
          // 标题栏
          Row() {
            SymbolGlyph($r('sys.symbol.questionmark_circle'))
              .fontSize(22)
              .fontColor([ThemeAwareHelper.getTestManagementThemedColor('accent_primary', this.themeState.currentTheme)])
            
            Text(this.config?.title || '帮助')
              .fontSize(18)
              .fontWeight(FontWeight.Bold)
              .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_primary', this.themeState.currentTheme))
              .margin({ left: 10 })
              .layoutWeight(1)
            
            Button({ type: ButtonType.Circle, stateEffect: true }) {
              SymbolGlyph($r('sys.symbol.xmark'))
                .fontSize(16)
                .fontColor([ThemeAwareHelper.getTestManagementThemedColor('text_secondary', this.themeState.currentTheme)])
            }
            .width(32)
            .height(32)
            .backgroundColor(ThemeAwareHelper.getTestManagementThemedColor('comp_background_tertiary', this.themeState.currentTheme))
            .onClick(() => {
              this.helpManager.hide();
            })
          }
          .width('100%')
          .padding({ left: 20, right: 16, top: 16, bottom: 12 })
          .backgroundColor(ThemeAwareHelper.getTestManagementThemedColor('panel_background', this.themeState.currentTheme))

          Divider()
            .color(ThemeAwareHelper.getTestManagementThemedColor('divider', this.themeState.currentTheme))

          // 内容区域
          if (this.isLoading) {
            Column() {
              LoadingProgress()
                .width(40)
                .height(40)
                .color(ThemeAwareHelper.getTestManagementThemedColor('accent_primary', this.themeState.currentTheme))
              Text('加载中...')
                .fontSize(14)
                .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_secondary', this.themeState.currentTheme))
                .margin({ top: 12 })
            }
            .width('100%')
            .layoutWeight(1)
            .justifyContent(FlexAlign.Center)
          } else {
            MarkdownViewerComponent({
              content: this.markdownContent,
              theme: this.themeState.currentTheme === ThemeType.DARK ? MarkdownTheme.DARK : MarkdownTheme.LIGHT,
              fontSize: 15
            })
              .width('100%')
              .layoutWeight(1)
          }
        }
        .width('90%')
        .height('80%')
        .backgroundColor(ThemeAwareHelper.getTestManagementThemedColor('background', this.themeState.currentTheme))
        .borderRadius(16)
        .clip(true)
        .shadow({
          radius: 20,
          color: '#40000000',
          offsetX: 0,
          offsetY: 4
        })
        .translate({ y: this.panelOffset })
      }
      .width('100%')
      .height('100%')
    }
  }
}
