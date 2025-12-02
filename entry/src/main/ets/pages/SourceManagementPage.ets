/**
 * 图源管理页面
 * 提供图源的导入、搜索、启用/禁用、测试等功能
 */

import { logger } from '../Utils/Logger';
import { ThemeAwareHelper, ThemeAwareState } from '../Framework/Components/ThemeAware';
import { ThemeManager } from '../Framework/Managers/ThemeManager';
import { WebViewSourceManager } from '../Framework/WebView/WebViewSourceManager';
import { DataManager } from '../Framework/Data/DataManager';
import { SourceRepositoryManager } from '../Framework/Source/SourceRepositoryManager';

const TAG = 'SourceManagementPage';

/**
 * 图源信息接口
 */
interface SourceInfo {
  id: number;
  name: string;
  pkg: string;
  baseUrl: string;
  version: string;
  description: string;
  language: string;
  isEnabled: boolean;
  priority: number;
  lastUpdateTime: number;
  createTime: number;
  iconPath?: string;
}

@Component
export struct SourceManagementPage {
  @State themeState: ThemeAwareState = new ThemeAwareState();
  @State sourceList: SourceInfo[] = [];
  @State filteredSourceList: SourceInfo[] = [];
  @State searchText: string = '';
  @State isLoading: boolean = false;
  @State showImportDialog: boolean = false;
  
  private themeManager: ThemeManager = ThemeManager.getInstance();
  private sourceManager: WebViewSourceManager = WebViewSourceManager.getInstance();
  private dataManager: DataManager = DataManager.getInstance();
  private scroller: Scroller = new Scroller();

  aboutToAppear() {
    // 初始化主题
    ThemeAwareHelper.initThemeAware(this.themeState, this.themeManager, 'SourceManagementPage');
    
    // 加载图源列表
    this.loadSourceList();
  }

  aboutToDisappear() {
    ThemeAwareHelper.cleanupThemeAware(this.themeState, this.themeManager, 'SourceManagementPage');
  }

  /**
   * 加载图源列表
   */
  private async loadSourceList(): Promise<void> {
    try {
      this.isLoading = true;
      
      // 从数据库加载图源
      const sources = await this.dataManager.getAllComicSources();
      const repoManager = SourceRepositoryManager.getInstance();
      
      this.sourceList = sources.map((source: ESObject) => {
        const pkg = source.pkg as string || '';
        // 尝试获取图源图标路径
        let iconPath: string | undefined = undefined;
        if (pkg) {
          const iconFile = repoManager.getSourceIconPath(pkg);
          if (iconFile) {
            iconPath = iconFile;
          }
        }
        
        return {
          id: source.id as number,
          name: source.name as string,
          pkg: pkg,
          baseUrl: source.baseUrl as string,
          version: source.version as string,
          description: source.description as string || '',
          language: source.language as string || 'zh-CN',
          isEnabled: Boolean(source.isEnabled),
          priority: source.priority as number || 0,
          lastUpdateTime: source.lastUpdateTime as number || 0,
          createTime: source.createTime as number,
          iconPath: iconPath
        };
      });
      
      this.filteredSourceList = [...this.sourceList];
      
      logger.info(TAG, `✅ 加载了${this.sourceList.length}个图源`);
    } catch (error) {
      logger.error(TAG, '加载图源列表失败', String(error));
    } finally {
      this.isLoading = false;
    }
  }

  /**
   * 搜索图源
   */
  private searchSources(keyword: string): void {
    this.searchText = keyword;
    
    if (!keyword.trim()) {
      this.filteredSourceList = [...this.sourceList];
      return;
    }
    
    const lowerKeyword = keyword.toLowerCase();
    this.filteredSourceList = this.sourceList.filter((source: SourceInfo) => {
      return source.name.toLowerCase().includes(lowerKeyword) ||
             source.baseUrl.toLowerCase().includes(lowerKeyword) ||
             source.description.toLowerCase().includes(lowerKeyword);
    });
    
    logger.debug(TAG, `搜索"${keyword}"，找到${this.filteredSourceList.length}个结果`);
  }

  /**
   * 切换图源启用状态
   */
  private async toggleSourceEnabled(source: SourceInfo): Promise<void> {
    try {
      const newState = !source.isEnabled;
      await this.dataManager.updateComicSource(source.id, { isEnabled: newState });
      
      // 更新本地状态
      source.isEnabled = newState;
      
      logger.info(TAG, `图源"${source.name}"已${newState ? '启用' : '禁用'}`);
    } catch (error) {
      logger.error(TAG, `切换图源状态失败: ${source.name}`, String(error));
    }
  }

  /**
   * 删除图源
   */
  private async deleteSource(source: SourceInfo): Promise<void> {
    try {
      await this.dataManager.deleteComicSource(source.id);
      
      // 从列表中移除
      const index = this.sourceList.findIndex((s: SourceInfo) => s.id === source.id);
      if (index !== -1) {
        this.sourceList.splice(index, 1);
      }
      
      this.searchSources(this.searchText);
      
      logger.info(TAG, `图源"${source.name}"已删除`);
    } catch (error) {
      logger.error(TAG, `删除图源失败: ${source.name}`, String(error));
    }
  }

  build() {
    Column() {
      // 搜索栏
      this.buildSearchBar()
      
      // 图源列表
      if (this.isLoading) {
        this.buildLoadingView()
      } else if (this.filteredSourceList.length === 0) {
        this.buildEmptyView()
      } else {
        this.buildSourceList()
      }
    }
    .width('100%')
    .height('100%')
    .backgroundColor(ThemeAwareHelper.getTestManagementThemedColor('background_dark', this.themeState.currentTheme))
  }

  /**
   * 构建搜索栏
   */
  @Builder
  buildSearchBar() {
    Column({ space: 12 }) {
      // 搜索框
      Row({ space: 8 }) {
        Search({ placeholder: '搜索图源名称、URL或描述' })
          .searchButton('搜索')
          .layoutWeight(1)
          .onChange((value: string) => {
            this.searchSources(value);
          })
        
        Button('导入')
          .fontSize(14)
          .backgroundColor(ThemeAwareHelper.getTestManagementThemedColor('accent_blue', this.themeState.currentTheme))
          .onClick(() => {
            this.showImportDialog = true;
          })
      }
      .width('100%')
      
      // 统计信息
      Row() {
        Text(`共${this.sourceList.length}个图源`)
          .fontSize(14)
          .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_secondary', this.themeState.currentTheme))
        
        Text(`已启用${this.sourceList.filter((s: SourceInfo) => s.isEnabled).length}个`)
          .fontSize(14)
          .fontColor(ThemeAwareHelper.getTestManagementThemedColor('accent_green', this.themeState.currentTheme))
          .margin({ left: 16 })
      }
      .width('100%')
    }
    .width('100%')
    .padding(16)
  }

  /**
   * 构建加载视图
   */
  @Builder
  buildLoadingView() {
    Column({ space: 16 }) {
      LoadingProgress()
        .width(48)
        .height(48)
        .color(ThemeAwareHelper.getTestManagementThemedColor('accent_blue', this.themeState.currentTheme))
      
      Text('加载中...')
        .fontSize(14)
        .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_secondary', this.themeState.currentTheme))
    }
    .width('100%')
    .layoutWeight(1)
    .justifyContent(FlexAlign.Center)
  }

  /**
   * 构建空状态视图
   */
  @Builder
  buildEmptyView() {
    Column({ space: 16 }) {
      Image($r('app.media.ic_source_normal'))
        .width(80)
        .height(80)
        .opacity(0.3)
      
      Text(this.searchText ? '未找到匹配的图源' : '暂无图源')
        .fontSize(16)
        .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_muted', this.themeState.currentTheme))
      
      if (!this.searchText) {
        Button('导入图源')
          .fontSize(14)
          .backgroundColor(ThemeAwareHelper.getTestManagementThemedColor('accent_blue', this.themeState.currentTheme))
          .onClick(() => {
            this.showImportDialog = true;
          })
      }
    }
    .width('100%')
    .layoutWeight(1)
    .justifyContent(FlexAlign.Center)
  }

  /**
   * 构建图源列表
   */
  @Builder
  buildSourceList() {
    Scroll(this.scroller) {
      Column({ space: 12 }) {
        ForEach(this.filteredSourceList, (source: SourceInfo) => {
          this.buildSourceCard(source)
        })
      }
      .width('100%')
      .padding({ left: 16, right: 16, bottom: 16 })
    }
    .width('100%')
    .layoutWeight(1)
    .scrollBar(BarState.Auto)
    .edgeEffect(EdgeEffect.Spring)
  }

  /**
   * 构建图源卡片
   */
  @Builder
  buildSourceCard(source: SourceInfo) {
    Column({ space: 12 }) {
      // 标题行
      Row({ space: 12 }) {
        // 图源图标
        if (source.iconPath) {
          Image('file://' + source.iconPath)
            .width(48)
            .height(48)
            .borderRadius(8)
            .objectFit(ImageFit.Cover)
            .backgroundColor(ThemeAwareHelper.getTestManagementThemedColor('panel_background', this.themeState.currentTheme))
        } else {
          // 默认图标
          Column() {
            Text(source.name.charAt(0).toUpperCase())
              .fontSize(20)
              .fontWeight(FontWeight.Bold)
              .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_white', this.themeState.currentTheme))
          }
          .width(48)
          .height(48)
          .borderRadius(8)
          .backgroundColor(ThemeAwareHelper.getTestManagementThemedColor('accent_blue', this.themeState.currentTheme))
          .justifyContent(FlexAlign.Center)
          .alignItems(HorizontalAlign.Center)
        }
        
        Column({ space: 4 }) {
          Text(source.name)
            .fontSize(16)
            .fontWeight(FontWeight.Medium)
            .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_primary', this.themeState.currentTheme))
          
          Text(source.baseUrl)
            .fontSize(12)
            .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_muted', this.themeState.currentTheme))
            .maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
        }
        .alignItems(HorizontalAlign.Start)
        .layoutWeight(1)
        
        Toggle({ type: ToggleType.Switch, isOn: source.isEnabled })
          .selectedColor(ThemeAwareHelper.getTestManagementThemedColor('accent_green', this.themeState.currentTheme))
          .onChange(async (isOn: boolean) => {
            await this.toggleSourceEnabled(source);
          })
      }
      .width('100%')
      
      // 描述
      if (source.description) {
        Text(source.description)
          .fontSize(14)
          .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_secondary', this.themeState.currentTheme))
          .maxLines(2)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
      }
      
      // 信息行
      Row({ space: 16 }) {
        Text(`版本: ${source.version}`)
          .fontSize(12)
          .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_muted', this.themeState.currentTheme))
        
        Text(`语言: ${source.language}`)
          .fontSize(12)
          .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_muted', this.themeState.currentTheme))
        
        Text(`优先级: ${source.priority}`)
          .fontSize(12)
          .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_muted', this.themeState.currentTheme))
      }
      .width('100%')
      
      // 操作按钮
      Row({ space: 8 }) {
        Button('测试')
          .fontSize(12)
          .layoutWeight(1)
          .backgroundColor(ThemeAwareHelper.getTestManagementThemedColor('button_background', this.themeState.currentTheme))
          .onClick(() => {
            logger.info(TAG, `测试图源: ${source.name}`);
          })
        
        Button('编辑')
          .fontSize(12)
          .layoutWeight(1)
          .backgroundColor(ThemeAwareHelper.getTestManagementThemedColor('button_background', this.themeState.currentTheme))
          .onClick(() => {
            logger.info(TAG, `编辑图源: ${source.name}`);
          })
        
        Button('删除')
          .fontSize(12)
          .layoutWeight(1)
          .backgroundColor(ThemeAwareHelper.getTestManagementThemedColor('accent_red', this.themeState.currentTheme))
          .onClick(async () => {
            await this.deleteSource(source);
          })
      }
      .width('100%')
    }
    .width('100%')
    .padding(16)
    .backgroundColor(ThemeAwareHelper.getTestManagementThemedColor('panel_background', this.themeState.currentTheme))
    .borderRadius(12)
    .border({
      width: 1,
      color: ThemeAwareHelper.getTestManagementThemedColor('panel_border', this.themeState.currentTheme)
    })
  }
}
