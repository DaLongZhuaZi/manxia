/**
 * 书源管理页面（新版）
 * 采用图源页面的现代化设计风格
 * 提供书源的导入、搜索、启用/禁用、测试等功能
 */

import { logger } from 'manxia_core/src/main/ets/Utils/Logger';
import { PageLifecycleManager } from 'manxia_core/src/main/ets/Framework/Lifecycle/index';
import { ThemeAwareHelper, ThemeAwareState } from 'manxia_theme/src/main/ets/Framework/Components/ThemeAware';
import { SourceDialogScaffold } from '../Framework/Components/SourceDialogScaffold';
import { ThemeManager } from 'manxia_theme/src/main/ets/Framework/Managers/ThemeManager';
import { getNovelSourceManager, NovelSourceManager } from '../Framework/Novel/NovelSourceManager';
import { getNovelDataManager } from '../Framework/Novel/NovelDataManager';
import { NovelSourceInfo } from '../Models/NovelModels';
import { promptAction } from '@kit.ArkUI';
import { picker } from '@kit.CoreFileKit';
import { pasteboard } from '@kit.BasicServicesKit';
import { GlobalBackgroundLayerMode } from 'manxia_theme/src/main/ets/Framework/Components/GlobalBackgroundLayer';
import { SharedPageBackgroundLayer } from '../Framework/Components/SharedPageBackgroundLayer';
import { SettingsPanelSurfaceHelper } from './settings/SettingsPanelSurfaceHelper';

const TAG = 'BookSourceManagementPage';

// 分页加载常量
const PAGE_SIZE = 100;  // 每次加载数量
const PRELOAD_THRESHOLD = 60;  // 预加载触发阈值

/**
 * 书源信息接口（与图源保持一致的结构）
 */
interface BookSourceInfo {
  id: string;
  name: string;
  url: string;
  version: string;
  description: string;
  language: string;
  isEnabled: boolean;
  priority: number;
  lastUpdateTime: number;
  createTime: number;
  group?: string;
  iconPath?: string;
  isNSFW?: boolean;  // 是否为NSFW书源
}

@Component
export struct BookSourceManagementPage {
  @State themeState: ThemeAwareState = new ThemeAwareState();
  @StorageProp('navigationBarHeight') navigationBarHeight: number = 0;
  
  // 所有书源（内存中完整列表）
  private allSources: BookSourceInfo[] = [];
  // 当前显示的书源（分页加载）
  @State displayedSources: BookSourceInfo[] = [];
  // 筛选后的书源（用于搜索）
  @State filteredSources: BookSourceInfo[] = [];
  @State searchText: string = '';
  @State isLoading: boolean = false;
  @State showImportDialog: boolean = false;
  @State importText: string = '';
  @State isImporting: boolean = false;
  
  // 大文件导入进度状态
  @State importProgress: number = 0;           // 导入进度百分比 0-100
  @State importStage: string = '';             // 当前阶段描述
  @State importDetail: string = '';            // 详细进度信息
  @State importCurrentCount: number = 0;
  @State importTotalCount: number = 0;
  @State showProgressDialog: boolean = false;  // 是否显示进度对话框
  
  // 多选模式状态
  @State isMultiSelectMode: boolean = false;
  @State selectedSourceIds: Set<string> = new Set<string>();
  
  // 分页加载状态
  private currentPage: number = 0;
  private hasMoreData: boolean = true;
  private isLoadingMore: boolean = false;
  
  private themeManager: ThemeManager = ThemeManager.getInstance();
  private sourceManager: NovelSourceManager = getNovelSourceManager();
  private scroller: Scroller = new Scroller();

  aboutToAppear() {
    ThemeAwareHelper.initializeThemeAware(
      'BookSourceManagementPage',
      this.themeState,
      () => {}
    );
    this.loadSourceList();
  }

  private lifecycle = new PageLifecycleManager('BookSourceManagementPage', { enableDebug: true });

  aboutToDisappear() {
    this.lifecycle.destroy();
    ThemeAwareHelper.cleanupThemeAware('BookSourceManagementPage');
  }

  /**
   * 加载书源列表
   */
  private async loadSourceList(): Promise<void> {
    try {
      this.isLoading = true;
      
      const sources = this.sourceManager.getAllSources();
      
      this.allSources = sources.map((source: NovelSourceInfo): BookSourceInfo => {
        return {
          id: source.id,
          name: source.name,
          url: source.url,
          version: '1.0',
          description: source.group || '',
          language: 'zh-CN',
          isEnabled: source.enabled,
          priority: source.weight || 0,
          lastUpdateTime: source.lastUpdateTime || 0,
          createTime: Date.now(),
          group: source.group,
          iconPath: undefined,
          isNSFW: source.isNSFW || false
        };
      });
      
      // 应用筛选并重置分页
      this.applyFilter();
      
      logger.info(TAG, `加载了 ${this.allSources.length} 个书源`);
    } catch (error) {
      logger.error(TAG, '加载书源列表失败', String(error));
      this.getUIContext().getPromptAction().showToast({ message: '加载书源失败' });
    } finally {
      this.isLoading = false;
    }
  }

  /**
   * 应用筛选
   */
  private applyFilter(): void {
    let result = this.allSources;
    
    // 搜索筛选
    if (this.searchText.trim()) {
      const keyword = this.searchText.toLowerCase();
      result = result.filter(s => 
        s.name.toLowerCase().includes(keyword) || 
        (s.group && s.group.toLowerCase().includes(keyword)) ||
        s.url.toLowerCase().includes(keyword)
      );
    }
    
    this.filteredSources = result;
    // 重置分页状态
    this.currentPage = 0;
    this.hasMoreData = true;
    // 加载第一页
    this.loadMoreSources(true);
  }

  /**
   * 加载更多书源（分页）
   */
  private loadMoreSources(reset: boolean = false): void {
    if (this.isLoadingMore && !reset) return;
    if (!this.hasMoreData && !reset) return;
    
    this.isLoadingMore = true;
    
    const startIndex = reset ? 0 : this.currentPage * PAGE_SIZE;
    const endIndex = startIndex + PAGE_SIZE;
    const newSources = this.filteredSources.slice(startIndex, endIndex);
    
    if (reset) {
      this.displayedSources = newSources;
      this.currentPage = 1;
    } else {
      // 追加新数据
      for (const source of newSources) {
        this.displayedSources.push(source);
      }
      this.currentPage++;
    }
    
    this.hasMoreData = endIndex < this.filteredSources.length;
    this.isLoadingMore = false;
    
    logger.debug(TAG, `加载书源: 显示${this.displayedSources.length}/${this.filteredSources.length}`);
  }

  /**
   * 检查是否需要预加载
   */
  private checkPreload(index: number): void {
    const threshold = (this.currentPage - 1) * PAGE_SIZE + PRELOAD_THRESHOLD;
    if (index >= threshold && this.hasMoreData && !this.isLoadingMore) {
      logger.debug(TAG, `触发预加载: index=${index}, threshold=${threshold}`);
      this.loadMoreSources();
    }
  }

  /**
   * 搜索书源
   */
  private searchSources(keyword: string): void {
    this.searchText = keyword;
    this.applyFilter();
  }

  /**
   * 切换书源启用状态
   */
  private async toggleSourceEnabled(source: BookSourceInfo): Promise<void> {
    try {
      const newState = !source.isEnabled;
      await this.sourceManager.setSourceEnabled(source.id, newState);
      
      source.isEnabled = newState;
      
      logger.info(TAG, `书源"${source.name}"已${newState ? '启用' : '禁用'}`);
    } catch (error) {
      logger.error(TAG, `切换书源状态失败: ${source.name}`, String(error));
    }
  }

  /**
   * 切换书源NSFW状态
   */
  private async toggleSourceNSFW(source: BookSourceInfo): Promise<void> {
    try {
      const newState = !source.isNSFW;
      await this.sourceManager.setSourceNSFW(source.id, newState);
      
      source.isNSFW = newState;
      // 触发UI刷新
      this.applyFilter();
      
      logger.info(TAG, `书源"${source.name}"已${newState ? '标记' : '取消'}NSFW`);
      this.getUIContext().getPromptAction().showToast({ message: `已${newState ? '标记为NSFW' : '取消NSFW标记'}` });
    } catch (error) {
      logger.error(TAG, `切换书源NSFW状态失败: ${source.name}`, String(error));
      this.getUIContext().getPromptAction().showToast({ message: '操作失败' });
    }
  }

  private showSourceHealthCheck(source: BookSourceInfo): void {
    const checks: string[] = [];
    checks.push(source.isEnabled ? '已启用' : '已停用');
    checks.push(source.url.length > 0 ? '书源地址有效' : '缺少书源地址');
    checks.push(source.group && source.group.length > 0 ? `分组: ${source.group}` : '未设置分组');
    checks.push(source.description.length > 0 ? '包含说明' : '未填写说明');
    checks.push(source.language.length > 0 ? `语言: ${source.language}` : '未标记语言');
    const message = `${source.name}\n${checks.join(' · ')}`;
    logger.info(TAG, `书源本地健康检查: id=${source.id}, ${checks.join(', ')}`);
    this.getUIContext().getPromptAction().showDialog({
      title: '书源检查',
      message,
      buttons: [
        { text: '确定', color: $r('sys.color.ohos_id_color_text_primary') }
      ]
    });
  }

  private showSourceEditHelp(source: BookSourceInfo): void {
    const message = '当前页面支持通过文件导入或剪贴板导入同 ID 书源来覆盖更新；内联规则编辑需要完整规则表单，暂不在列表卡片内直接展开。';
    logger.info(TAG, `显示书源更新说明: ${source.name}`);
    this.getUIContext().getPromptAction().showActionMenu({
      title: `更新 ${source.name}`,
      buttons: [
        { text: '从文件导入覆盖', color: $r('sys.color.ohos_id_color_text_primary') },
        { text: '从剪贴板导入覆盖', color: $r('sys.color.ohos_id_color_text_primary') },
        { text: '查看说明', color: $r('sys.color.ohos_id_color_text_primary') }
      ]
    }).then(async (result: promptAction.ActionMenuSuccessResponse) => {
      if (result.index === 0) {
        await this.importFromFile();
      } else if (result.index === 1) {
        await this.importFromClipboard();
      } else if (result.index === 2) {
        this.getUIContext().getPromptAction().showToast({ message, duration: 3000 });
      }
    }).catch(() => {});
  }

  /**
   * 切换多选模式
   */
  private toggleMultiSelectMode(): void {
    this.isMultiSelectMode = !this.isMultiSelectMode;
    if (!this.isMultiSelectMode) {
      this.selectedSourceIds = new Set<string>();
    }
  }

  /**
   * 切换单个书源的选中状态
   */
  private toggleSourceSelection(sourceId: string): void {
    const newSet = new Set<string>(this.selectedSourceIds);
    if (newSet.has(sourceId)) {
      newSet.delete(sourceId);
    } else {
      newSet.add(sourceId);
    }
    this.selectedSourceIds = newSet;
  }

  /**
   * 全选/反选
   */
  private toggleSelectAll(): void {
    if (this.selectedSourceIds.size === this.filteredSources.length) {
      // 已全选，取消全选
      this.selectedSourceIds = new Set<string>();
    } else {
      // 全选
      const newSet = new Set<string>();
      for (const source of this.filteredSources) {
        newSet.add(source.id);
      }
      this.selectedSourceIds = newSet;
    }
  }

  /**
   * 批量NSFW标记
   */
  private async batchSetNSFW(isNSFW: boolean): Promise<void> {
    try {
      const ids = Array.from(this.selectedSourceIds);
      if (ids.length === 0) {
        this.getUIContext().getPromptAction().showToast({ message: '请先选择书源' });
        return;
      }

      for (const id of ids) {
        await this.sourceManager.setSourceNSFW(id, isNSFW);
        const source = this.allSources.find((s: BookSourceInfo) => s.id === id);
        if (source) {
          source.isNSFW = isNSFW;
        }
      }

      this.applyFilter();
      this.getUIContext().getPromptAction().showToast({ message: `已${isNSFW ? '标记' : '取消'}${ids.length}个书源的NSFW` });
      logger.info(TAG, `批量${isNSFW ? '标记' : '取消'}NSFW: ${ids.length}个书源`);
    } catch (error) {
      logger.error(TAG, '批量NSFW操作失败', String(error));
      this.getUIContext().getPromptAction().showToast({ message: '操作失败' });
    }
  }

  /**
   * 删除书源
   */
  private async deleteSource(source: BookSourceInfo): Promise<void> {
    try {
      await this.sourceManager.deleteSource(source.id);
      
      const index = this.allSources.findIndex((s: BookSourceInfo) => s.id === source.id);
      if (index !== -1) {
        this.allSources.splice(index, 1);
      }
      
      this.applyFilter();
      
      logger.info(TAG, `书源"${source.name}"已删除`);
      this.getUIContext().getPromptAction().showToast({ message: '书源已删除' });
    } catch (error) {
      logger.error(TAG, `删除书源失败: ${source.name}`, String(error));
      this.getUIContext().getPromptAction().showToast({ message: '删除失败' });
    }
  }

  /** Every local file enters the same lossless V2 streaming import pipeline. */
  private async importFromFile(): Promise<void> {
    try {
      const documentPicker = new picker.DocumentViewPicker();
      const result = await documentPicker.select({
        maxSelectNumber: 1
      });
      
      if (result && result.length > 0) {
        const filePath = result[0];
        const fileSize = NovelSourceManager.getFileSize(filePath);
        const fileSizeStr = NovelSourceManager.formatFileSize(fileSize);
        logger.info(TAG, `选择的文件: ${filePath}, 大小: ${fileSizeStr}`);
        await this.importFileThroughV2Pipeline(filePath, fileSize);
      }
    } catch (error) {
      logger.error(TAG, '从文件导入失败', String(error));
      this.getUIContext().getPromptAction().showToast({ message: '导入失败: ' + String(error) });
      this.hideProgressDialog();
    }
  }
  
  /**
   * Does not use a size threshold: a small file must retain exactly the same
   * UTF-8/raw-document semantics as a large file.
   */
  private async importFileThroughV2Pipeline(filePath: string, fileSize: number): Promise<void> {
    try {
      this.isImporting = true;
      this.showProgressDialog = true;
      this.importStage = '准备无损导入...';
      this.importDetail = `文件大小: ${NovelSourceManager.formatFileSize(fileSize)}`;
      this.importProgress = 0;
      this.importCurrentCount = 0;
      this.importTotalCount = 0;
      
      const result = await this.sourceManager.importFromLargeFile(filePath, {
        onFileReadProgress: (percent, bytesRead, totalBytes) => {
          this.importStage = '读取文件...';
          this.importProgress = Math.min(95, percent);
          this.importDetail = `${NovelSourceManager.formatFileSize(bytesRead)} / ${NovelSourceManager.formatFileSize(totalBytes)}`;
        },
        onParseProgress: (parsedCount, currentSourceName) => {
          this.importStage = '解析并编译书源...';
          this.importDetail = `已解析 ${parsedCount} 个 - ${currentSourceName}`;
          this.importCurrentCount = parsedCount;
          this.importTotalCount = 0;
        },
        onImportProgress: (importedCount, totalCount, currentSourceName) => {
          this.importStage = '无损写入 V2 记录...';
          this.importDetail = totalCount > 0
            ? `${importedCount} / ${totalCount} - ${currentSourceName}`
            : `已无损写入 ${importedCount} 个，仍在扫描文件 - ${currentSourceName}`;
          this.importCurrentCount = importedCount;
          this.importTotalCount = totalCount;
        },
        onStageChange: (stage) => {
          switch (stage) {
            case 'reading':
              this.importStage = '读取文件中...';
              break;
            case 'parsing':
              this.importStage = '解析并编译书源中...';
              break;
            case 'importing':
              this.importStage = '无损写入 V2 记录中...';
              break;
            case 'complete':
              this.importStage = '导入完成！';
              this.importProgress = 100;
              if (this.importTotalCount > 0) {
                this.importCurrentCount = this.importTotalCount;
              }
              break;
          }
        },
        onError: (error, sourceName) => {
          logger.warn(TAG, `导入警告: ${error}${sourceName ? ` (${sourceName})` : ''}`);
        }
      });
      
      // 显示结果
      if (result.success) {
        const message = `成功导入 ${result.successCount} 个书源` +
          (result.failedCount > 0 ? `，失败 ${result.failedCount} 个` : '') +
          (result.skippedCount > 0 ? `，跳过 ${result.skippedCount} 个` : '') +
          `\n耗时: ${(result.elapsedMs / 1000).toFixed(1)}秒`;
        this.getUIContext().getPromptAction().showToast({ message, duration: 3000 });
        await this.loadSourceList();
      } else {
        this.getUIContext().getPromptAction().showToast({ message: '导入失败: ' + (result.errors[0] || '未知错误') });
      }
      
    } finally {
      this.hideProgressDialog();
    }
  }
  
  /**
   * 隐藏进度对话框并重置状态
   */
  private hideProgressDialog(): void {
    this.showProgressDialog = false;
    this.isImporting = false;
    this.importProgress = 0;
    this.importStage = '';
    this.importDetail = '';
    this.importCurrentCount = 0;
    this.importTotalCount = 0;
  }

  /**
   * 从剪贴板导入书源
   */
  private async importFromClipboard(): Promise<void> {
    try {
      const pasteData = await pasteboard.getSystemPasteboard().getData();
      const text = pasteData.getPrimaryText();
      
      if (text) {
        this.importText = text;
        this.showImportDialog = true;
      } else {
        this.getUIContext().getPromptAction().showToast({ message: '剪贴板为空' });
      }
    } catch (error) {
      logger.error(TAG, '从剪贴板导入失败', String(error));
      this.getUIContext().getPromptAction().showToast({ message: '读取剪贴板失败' });
    }
  }

  /**
   * 导入书源JSON
   */
  private async importSourcesFromJson(jsonStr: string): Promise<void> {
    try {
      this.isImporting = true;

      const results = await this.sourceManager.importFromJSONWithProgress(
        jsonStr,
        (current: number, total: number, sourceName: string) => {
          this.importStage = '导入书源...';
          this.importProgress = 50 + Math.round((current / Math.max(total, 1)) * 50);
          this.importDetail = `${current} / ${total} - ${sourceName}`;
          this.importCurrentCount = current;
          this.importTotalCount = total;
        }
      );
      
      const successCount = results.filter(r => r.success).length;
      const failedCount = results.filter(r => !r.success).length;
      
      if (successCount > 0) {
        this.getUIContext().getPromptAction().showToast({ 
          message: `成功导入${successCount}个书源${failedCount > 0 ? `，失败${failedCount}个` : ''}` 
        });
        await this.loadSourceList();
      } else {
        this.getUIContext().getPromptAction().showToast({ message: '导入失败' });
      }
      
      this.showImportDialog = false;
      this.importText = '';
    } catch (error) {
      logger.error(TAG, '导入书源失败', String(error));
      this.getUIContext().getPromptAction().showToast({ message: '导入失败' });
    } finally {
      this.isImporting = false;
    }
  }

  build() {
    Stack() {
      SharedPageBackgroundLayer({
        defaultBackgroundColor: ThemeAwareHelper.getTestManagementThemedColor('background_dark', this.themeState.currentTheme),
        mode: GlobalBackgroundLayerMode.IMMERSIVE
      })
        .width('100%')
        .height('100%')
        .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.TOP, SafeAreaEdge.BOTTOM])

      Column() {
        this.buildSearchBar()

        if (this.isLoading) {
          this.buildLoadingView()
        } else if (this.displayedSources.length === 0) {
          this.buildEmptyView()
        } else {
          this.buildSourceList()
        }

        if (this.isMultiSelectMode) {
          this.buildMultiSelectToolbar()
        }

        if (this.showImportDialog) {
          this.buildImportDialog()
        }

        if (this.showProgressDialog) {
          this.buildProgressDialog()
        }
      }
      .width('100%')
      .height('100%')
      .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.TOP, SafeAreaEdge.BOTTOM])
    }
    .width('100%')
    .height('100%')
  }

  @Builder
  buildSearchBar() {
    Column({ space: 12 }) {
      Row({ space: 8 }) {
        Search({ placeholder: '搜索书源名称、URL或描述', value: this.searchText })
          .searchButton('搜索')
          .layoutWeight(1)
          .onChange((value: string) => {
            this.searchSources(value);
          })
          .onSubmit((value: string) => {
            this.searchSources(value);
          })
        
        Button(this.isMultiSelectMode ? '取消' : '多选')
          .fontSize(14)
          .backgroundColor(this.isMultiSelectMode
            ? ThemeAwareHelper.getTestManagementThemedColor('color_error', this.themeState.currentTheme)
            : ThemeAwareHelper.getTestManagementThemedColor('button_background', this.themeState.currentTheme))
          .onClick(() => {
            this.toggleMultiSelectMode();
          })
        
        Button('导入')
          .fontSize(14)
          .backgroundColor(ThemeAwareHelper.getTestManagementThemedColor('accent_blue', this.themeState.currentTheme))
          .onClick(() => {
            this.showImportOptions();
          })
      }
      .width('100%')
      
      Row() {
        Text(`共${this.allSources.length}个书源`)
          .fontSize(14)
          .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_secondary', this.themeState.currentTheme))
        
        Text(`已启用${this.allSources.filter((s: BookSourceInfo) => s.isEnabled).length}个`)
          .fontSize(14)
          .fontColor(ThemeAwareHelper.getTestManagementThemedColor('accent_green', this.themeState.currentTheme))
          .margin({ left: 16 })
        
        if (this.isMultiSelectMode) {
          Text(`已选${this.selectedSourceIds.size}个`)
            .fontSize(14)
            .fontColor('#FF4444')
            .margin({ left: 16 })
        }
      }
      .width('100%')
    }
    .width('100%')
    .padding(16)
    .backgroundColor(SettingsPanelSurfaceHelper.getBackground(this.themeState.currentTheme))
    .linearGradient(SettingsPanelSurfaceHelper.getSurfaceGradient(this.themeState.currentTheme))
    .backgroundBlurStyle(
      SettingsPanelSurfaceHelper.getBlurStyle(this.themeState.currentTheme),
      SettingsPanelSurfaceHelper.getBlurOptions(this.themeState.currentTheme)
    )
    .backgroundEffect(SettingsPanelSurfaceHelper.getBackgroundEffect(this.themeState.currentTheme))
    .borderRadius(SettingsPanelSurfaceHelper.getRadius(this.themeState.currentTheme))
    .clip(true)
    .border({
      width: SettingsPanelSurfaceHelper.getBorderWidth(this.themeState.currentTheme),
      color: SettingsPanelSurfaceHelper.getBorderColor(this.themeState.currentTheme)
    })
    .shadow({
      radius: SettingsPanelSurfaceHelper.getRadius(this.themeState.currentTheme) + 4,
      color: SettingsPanelSurfaceHelper.getShadowColor(this.themeState.currentTheme),
      offsetX: 0,
      offsetY: 8
    })
  }

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

  @Builder
  buildEmptyView() {
    Column({ space: 16 }) {
      Image($r('app.media.ic_source_normal'))
        .width(80)
        .height(80)
        .opacity(0.3)
      
      Text(this.searchText ? '未找到匹配的书源' : '暂无书源')
        .fontSize(16)
        .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_muted', this.themeState.currentTheme))
      
      if (!this.searchText) {
        Button('导入书源')
          .fontSize(14)
          .backgroundColor(ThemeAwareHelper.getTestManagementThemedColor('accent_blue', this.themeState.currentTheme))
          .onClick(() => {
            this.showImportOptions();
          })
      }
    }
    .width('100%')
    .layoutWeight(1)
    .justifyContent(FlexAlign.Center)
  }

  @Builder
  buildSourceList() {
    Scroll(this.scroller) {
      Column({ space: 12 }) {
        ForEach(this.displayedSources, (source: BookSourceInfo, index: number) => {
          Column() {
            this.buildSourceCard(source)
          }
          .width('100%')
          .onAppear(() => {
            // 预加载检查
            this.checkPreload(index);
          })
        }, (source: BookSourceInfo) => source.id)
        Blank().height(24 + this.navigationBarHeight)
      }
      .width('100%')
      .padding({ left: 16, right: 16, bottom: 8 })
    }
    .width('100%')
    .layoutWeight(1)
    .scrollBar(BarState.Auto)
    .edgeEffect(EdgeEffect.Spring)
  }

  @Builder
  buildSourceCard(source: BookSourceInfo) {
    Column({ space: 12 }) {
      Row({ space: 12 }) {
        if (this.isMultiSelectMode) {
          Checkbox()
            .select(this.selectedSourceIds.has(source.id))
            .selectedColor(ThemeAwareHelper.getTestManagementThemedColor('accent_blue', this.themeState.currentTheme))
            .onChange((isChecked: boolean) => {
              this.toggleSourceSelection(source.id);
            })
        }
        
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
        
        Column({ space: 4 }) {
          Row({ space: 6 }) {
            Text(source.name)
              .fontSize(16)
              .fontWeight(FontWeight.Medium)
              .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_primary', this.themeState.currentTheme))
            
            if (source.isNSFW) {
              Text('NSFW')
                .fontSize(10)
                .fontColor('#FF4444')
                .padding({ left: 4, right: 4, top: 1, bottom: 1 })
                .borderRadius(4)
                .backgroundColor('#FF444420')
            }
          }
          
          Text(source.url)
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
      
      if (source.description) {
        Text(source.description)
          .fontSize(14)
          .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_secondary', this.themeState.currentTheme))
          .maxLines(2)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
      }
      
      Row({ space: 16 }) {
        if (source.group) {
          Text(`分组: ${source.group}`)
            .fontSize(12)
            .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_muted', this.themeState.currentTheme))
        }
        
        Text(`优先级: ${source.priority}`)
          .fontSize(12)
          .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_muted', this.themeState.currentTheme))
      }
      .width('100%')
      
      Row({ space: 8 }) {
        Button('测试')
          .fontSize(12)
          .layoutWeight(1)
          .backgroundColor(ThemeAwareHelper.getTestManagementThemedColor('button_background', this.themeState.currentTheme))
          .onClick(() => {
            this.showSourceHealthCheck(source);
          })
        
        Button(source.isNSFW ? '取消NSFW' : 'NSFW')
          .fontSize(12)
          .layoutWeight(1)
          .fontColor(source.isNSFW ? '#FF4444' : ThemeAwareHelper.getTestManagementThemedColor('text_primary', this.themeState.currentTheme))
          .backgroundColor(source.isNSFW ? '#FF444420' : ThemeAwareHelper.getTestManagementThemedColor('button_background', this.themeState.currentTheme))
          .onClick(async () => {
            await this.toggleSourceNSFW(source);
          })
        
        Button('编辑')
          .fontSize(12)
          .layoutWeight(1)
          .backgroundColor(ThemeAwareHelper.getTestManagementThemedColor('button_background', this.themeState.currentTheme))
          .onClick(() => {
            this.showSourceEditHelp(source);
          })
        
        Button('删除')
          .fontSize(12)
          .layoutWeight(1)
          .backgroundColor(ThemeAwareHelper.getTestManagementThemedColor('color_error', this.themeState.currentTheme))
          .onClick(async () => {
            await this.deleteSource(source);
          })
      }
      .width('100%')
    }
    .width('100%')
    .padding(16)
    .backgroundColor(SettingsPanelSurfaceHelper.getBackground(this.themeState.currentTheme))
    .linearGradient(SettingsPanelSurfaceHelper.getSurfaceGradient(this.themeState.currentTheme))
    .backgroundBlurStyle(
      SettingsPanelSurfaceHelper.getBlurStyle(this.themeState.currentTheme),
      SettingsPanelSurfaceHelper.getBlurOptions(this.themeState.currentTheme)
    )
    .backgroundEffect(SettingsPanelSurfaceHelper.getBackgroundEffect(this.themeState.currentTheme))
    .borderRadius(SettingsPanelSurfaceHelper.getRadius(this.themeState.currentTheme))
    .clip(true)
    .border({
      width: SettingsPanelSurfaceHelper.getBorderWidth(this.themeState.currentTheme),
      color: SettingsPanelSurfaceHelper.getBorderColor(this.themeState.currentTheme)
    })
    .shadow({
      radius: SettingsPanelSurfaceHelper.getRadius(this.themeState.currentTheme) + 4,
      color: SettingsPanelSurfaceHelper.getShadowColor(this.themeState.currentTheme),
      offsetX: 0,
      offsetY: 8
    })
  }

  @Builder
  buildMultiSelectToolbar() {
    Row({ space: 8 }) {
      Button(this.selectedSourceIds.size === this.filteredSources.length ? '取消全选' : '全选')
        .fontSize(13)
        .layoutWeight(1)
        .backgroundColor(ThemeAwareHelper.getTestManagementThemedColor('button_background', this.themeState.currentTheme))
        .onClick(() => {
          this.toggleSelectAll();
        })
      
      Button('标记NSFW')
        .fontSize(13)
        .layoutWeight(1)
        .fontColor('#FF4444')
        .backgroundColor('#FF444420')
        .onClick(async () => {
          await this.batchSetNSFW(true);
        })
      
      Button('取消NSFW')
        .fontSize(13)
        .layoutWeight(1)
        .backgroundColor(ThemeAwareHelper.getTestManagementThemedColor('button_background', this.themeState.currentTheme))
        .onClick(async () => {
          await this.batchSetNSFW(false);
        })
    }
    .width('100%')
    .padding({ left: 16, right: 16, top: 12, bottom: 16 + this.navigationBarHeight })
    .backgroundColor(SettingsPanelSurfaceHelper.getBackground(this.themeState.currentTheme))
    .linearGradient(SettingsPanelSurfaceHelper.getSurfaceGradient(this.themeState.currentTheme))
    .backgroundBlurStyle(
      SettingsPanelSurfaceHelper.getBlurStyle(this.themeState.currentTheme),
      SettingsPanelSurfaceHelper.getBlurOptions(this.themeState.currentTheme)
    )
    .backgroundEffect(SettingsPanelSurfaceHelper.getBackgroundEffect(this.themeState.currentTheme))
    .borderRadius(SettingsPanelSurfaceHelper.getRadius(this.themeState.currentTheme))
    .clip(true)
    .border({
      width: SettingsPanelSurfaceHelper.getBorderWidth(this.themeState.currentTheme),
      color: SettingsPanelSurfaceHelper.getBorderColor(this.themeState.currentTheme)
    })
    .shadow({
      radius: SettingsPanelSurfaceHelper.getRadius(this.themeState.currentTheme) + 4,
      color: SettingsPanelSurfaceHelper.getShadowColor(this.themeState.currentTheme),
      offsetX: 0,
      offsetY: -4
    })
  }

  @Builder
  buildImportDialog() {
    SourceDialogScaffold({
      themeState: this.themeState,
      onMaskTap: () => {
        this.showImportDialog = false;
        this.importText = '';
      }
    }) {
      Column({ space: 16 }) {
        Text('导入书源')
          .fontSize(18)
          .fontWeight(FontWeight.Medium)
          .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_primary', this.themeState.currentTheme))

        TextArea({ placeholder: '粘贴书源JSON...', text: this.importText })
          .height(200)
          .backgroundColor(ThemeAwareHelper.getTestManagementThemedColor('background_secondary', this.themeState.currentTheme))
          .borderRadius(8)
          .onChange((value: string) => {
            this.importText = value;
          })

        Row({ space: 12 }) {
          Button('取消')
            .layoutWeight(1)
            .height(34)
            .borderRadius(8)
            .backgroundColor(ThemeAwareHelper.getTestManagementThemedColor('button_inactive', this.themeState.currentTheme))
            .onClick(() => {
              this.showImportDialog = false;
              this.importText = '';
            })

          Button(this.isImporting ? '导入中...' : '确定')
            .layoutWeight(1)
            .height(34)
            .borderRadius(8)
            .backgroundColor(ThemeAwareHelper.getTestManagementThemedColor('accent_primary', this.themeState.currentTheme))
            .enabled(!this.isImporting)
            .onClick(async () => {
              await this.importSourcesFromJson(this.importText);
            })
        }
        .width('100%')
      }
      .width('100%')
    }
  }

  @Builder
  buildProgressDialog() {
    SourceDialogScaffold({
      themeState: this.themeState,
      closeOnMaskTap: false
    }) {
      Column({ space: 20 }) {
        Text('导入书源')
          .fontSize(20)
          .fontWeight(FontWeight.Bold)
          .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_primary', this.themeState.currentTheme))

        Text(this.importStage)
          .fontSize(16)
          .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_primary', this.themeState.currentTheme))

        Progress({ value: this.importProgress, total: 100, type: ProgressType.Linear })
          .width('100%')
          .height(8)
          .color(ThemeAwareHelper.getTestManagementThemedColor('accent_primary', this.themeState.currentTheme))
          .backgroundColor(ThemeAwareHelper.getTestManagementThemedColor('button_background', this.themeState.currentTheme))

        Text(`${this.importProgress}%`)
          .fontSize(24)
          .fontWeight(FontWeight.Bold)
          .fontColor(ThemeAwareHelper.getTestManagementThemedColor('accent_primary', this.themeState.currentTheme))

        if (this.importTotalCount > 0) {
          Text(`书源进度: ${this.importCurrentCount} / ${this.importTotalCount}`)
            .fontSize(13)
            .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_secondary', this.themeState.currentTheme))
        } else if (this.importCurrentCount > 0) {
          Text(`已处理: ${this.importCurrentCount}`)
            .fontSize(13)
            .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_secondary', this.themeState.currentTheme))
        }

        if (this.importDetail) {
          Text(this.importDetail)
            .fontSize(14)
            .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_secondary', this.themeState.currentTheme))
            .maxLines(2)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
            .textAlign(TextAlign.Center)
        }

        Text('正在处理大文件，请耐心等待...')
          .fontSize(12)
          .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_muted', this.themeState.currentTheme))
          .margin({ top: 8 })
      }
      .width('100%')
      .alignItems(HorizontalAlign.Center)
    }
  }

  private showImportOptions(): void {
    this.getUIContext().getPromptAction().showActionMenu({
      title: '导入书源',
      buttons: [
        { text: '从文件导入', color: $r('sys.color.ohos_id_color_text_primary') },
        { text: '从剪贴板导入', color: $r('sys.color.ohos_id_color_text_primary') }
      ]
    }).then((result: promptAction.ActionMenuSuccessResponse) => {
      if (result.index === 0) {
        this.importFromFile();
      } else if (result.index === 1) {
        this.importFromClipboard();
      }
    }).catch(() => {});
  }
}
