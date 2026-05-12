/**
 * 图源Tab内容组件
 * 从 MainMenuPage 提取的图源管理页逻辑
 */

import { logger } from '../Utils/Logger';
import { ThemeAwareState, ThemeAwareHelper } from '../Framework/Components/ThemeAware';
import { ThemeType } from '../Framework/Managers/ThemeManager';
import { LoadingState } from '../Utils/LoadingState';
import { ContextMenuState } from '../Utils/ContextMenuState';
import { BasicDataSource } from '../Utils/BasicDataSource';
import { LibraryViewMode } from '../Framework/Components/BookSourceTabContent';
import { AppColors } from '../Framework/Theme/AppColors';
import { SourceManager, SourceInfo } from '../Framework/Source/SourceManager';

const TAG = 'SourceTabContent';

export interface SearchTypeOption {
  id: string;
  label: string;
}

@Component
export struct SourceTabContent {
  @Consume('NavPathStack') pathStack: NavPathStack;
  @Prop topSpacerHeight: number = 0;
  @Prop bottomSpacerHeight: number = 125;
  @Prop @Watch('onRefreshSignalChanged') refreshSignal: number = 0;
  @StorageLink('appFontFamily') appFontFamily: string = 'HarmonyOS Sans';

  @Prop isLandscape: boolean = false;
  @Prop gridColumns: number = 3;
  @Prop gridGap: number = 8;

  @State private themeState: ThemeAwareState = new ThemeAwareState();
  @State sourceList: SourceInfo[] = [];
  @State filteredSourceList: SourceInfo[] = [];
  @State sourceSearchKeyword: string = '';
  @State showSourceSearchDialog: boolean = false;
  @State sourceSearchInput: string = '';
  @State searchTargetSource: SourceInfo | null = null;
  @State sourceSearchTypes: SearchTypeOption[] = [];
  @State selectedSourceSearchType: string = 'search';
  @State sourceSearchPlaceholder: string = '输入关键词搜索';
  @State hasSourceUpdate: boolean = false;
  @State sourceViewMode: LibraryViewMode = LibraryViewMode.LIST;
  @State sourceTypeFilter: 'all' | 'manga' | 'ebook' | 'novel' = 'all';

  @State loadingState: LoadingState = new LoadingState();
  @State sourceContextMenu: ContextMenuState<SourceInfo> = new ContextMenuState<SourceInfo>();

  @StorageLink('userThemeBlurEnabled') private userThemeBlurEnabled: boolean = true;
  @StorageLink('userThemeCornerRadius') private userThemeCornerRadius: number = 12;
  @StorageLink('userThemeShadowEnabled') private userThemeShadowEnabled: boolean = true;

  private sourceListDS: BasicDataSource<SourceInfo> = new BasicDataSource<SourceInfo>();

  aboutToAppear(): void {
    ThemeAwareHelper.initializeThemeAware(TAG, this.themeState,
      (theme: ThemeType) => {
        const newState = new ThemeAwareState();
        newState.updateTheme(theme);
        this.themeState = newState;
      },
      (newState: ThemeAwareState) => {
        this.themeState = newState;
      }
    );
  }

  aboutToDisappear(): void {
    ThemeAwareHelper.cleanupThemeAware(TAG);
  }

  onRefreshSignalChanged(): void {
    // 图源页刷新逻辑由 MainMenuPage 通过数据绑定驱动
  }

  // ── 工具方法 ──

  private getInitialTopOverlaySpacerHeight(): number {
    return this.topSpacerHeight + 8;
  }

  private getMainTabBottomSpacerHeight(): number {
    return this.bottomSpacerHeight + 16;
  }

  private getSettingsAnalyticsCardBackground(): string {
    if (this.themeState.currentTheme === ThemeType.LIGHT) {
      return 'rgba(255, 255, 255, 0.68)';
    } else {
      return 'rgba(16, 22, 32, 0.78)';
    }
  }

  private getSettingsAnalyticsCardBlurStyle(): BlurStyle | undefined {
    if (!this.userThemeBlurEnabled) {
      return undefined;
    }
    return BlurStyle.Thin;
  }

  private getSettingsAnalyticsCardBlurOptions(): BackgroundBlurStyleOptions | undefined {
    return undefined;
  }

  private getSettingsAnalyticsCardBackgroundEffect(): BackgroundEffectOptions | undefined {
    return undefined;
  }

  private getSettingsAnalyticsCardBorderWidth(): Dimension {
    return 0.5;
  }

  private getSettingsAnalyticsCardBorderColor(): ResourceColor {
    if (this.themeState.currentTheme === ThemeType.LIGHT) {
      return 'rgba(0, 0, 0, 0.05)';
    } else {
      return 'rgba(255, 255, 255, 0.08)';
    }
  }

  private getSettingsAnalyticsCardRadius(): number {
    return 8;
  }

  private getSettingsAnalyticsCardShadowColor(): string {
    if (!this.userThemeShadowEnabled) {
      return 'rgba(0, 0, 0, 0)';
    }
    if (this.themeState.currentTheme === ThemeType.LIGHT) {
      return 'rgba(0, 0, 0, 0.1)';
    } else {
      return 'rgba(0, 0, 0, 0.3)';
    }
  }

  private getLibraryGridColumnsTemplate(): string {
    let template = '';
    for (let i = 0; i < this.gridColumns; i++) {
      template += '1fr ';
    }
    return template.trim();
  }

  private getSourceListTitle(): string {
    if (this.sourceSearchKeyword) {
      return `搜索结果 (${this.filteredSourceList.length})`;
    }
    switch (this.sourceTypeFilter) {
      case 'manga':
        return `漫画图源 (${this.filteredSourceList.length})`;
      case 'ebook':
        return `电子书源 (${this.filteredSourceList.length})`;
      case 'novel':
        return `小说源 (${this.filteredSourceList.length})`;
      default:
        return `全部图源 (${this.filteredSourceList.length})`;
    }
  }

  private getSourceTypeFilterIcon(): Resource {
    switch (this.sourceTypeFilter) {
      case 'manga':
        return $r('app.media.ic_library_normal');
      case 'ebook':
        return $r('app.media.ic_library_normal');
      case 'novel':
        return $r('app.media.ic_library_normal');
      default:
        return $r('app.media.ic_source_normal');
    }
  }

  private getEmptySourceTitle(): string {
    if (this.sourceSearchKeyword) {
      return '没有找到匹配的图源';
    }
    switch (this.sourceTypeFilter) {
      case 'manga':
        return '没有漫画图源';
      case 'ebook':
        return '没有电子书源';
      case 'novel':
        return '没有小说源';
      default:
        return '暂无图源';
    }
  }

  private getEmptySourceDescription(): string {
    if (this.sourceSearchKeyword) {
      return '尝试使用不同的关键词搜索';
    }
    return '点击下方按钮导入图源或同步图源仓库';
  }

  private getEmptySourceHint(): string {
    return '支持从本地文件或网络URL导入图源配置';
  }

  private searchSources(keyword: string): void {
    this.sourceSearchKeyword = keyword;
    this.applySourceFilters();
  }

  private applySourceFilters(): void {
    let filtered = [...this.sourceList];

    // 按类型筛选
    if (this.sourceTypeFilter !== 'all') {
      filtered = filtered.filter(source => source.type === this.sourceTypeFilter);
    }

    // 按关键词搜索
    if (this.sourceSearchKeyword) {
      const keyword = this.sourceSearchKeyword.toLowerCase();
      filtered = filtered.filter(source =>
        source.name.toLowerCase().includes(keyword) ||
        source.baseUrl.toLowerCase().includes(keyword)
      );
    }

    this.filteredSourceList = filtered;
    this.sourceListDS.setData(filtered);
  }

  private cycleSourceTypeFilter(): void {
    const filters: Array<'all' | 'manga' | 'ebook' | 'novel'> = ['all', 'manga', 'ebook', 'novel'];
    const currentIndex = filters.indexOf(this.sourceTypeFilter);
    this.sourceTypeFilter = filters[(currentIndex + 1) % filters.length];
    this.applySourceFilters();
  }

  private async handleSourceRefresh(): Promise<void> {
    this.loadingState.refreshingSourceList = true;
    try {
      // 刷新逻辑由父组件处理
      await new Promise<void>(resolve => setTimeout(resolve, 1000));
    } finally {
      this.loadingState.refreshingSourceList = false;
    }
  }

  private openSourceSearchDialog(source: SourceInfo): void {
    this.searchTargetSource = source;
    this.showSourceSearchDialog = true;
  }

  private closeSourceSearchDialog(): void {
    this.showSourceSearchDialog = false;
    this.searchTargetSource = null;
    this.sourceSearchInput = '';
  }

  // ── UI 构建方法 ──

  build() {
    Stack({ alignContent: Alignment.TopStart }) {
      Column({ space: 0 }) {
        // 顶部避让空间
        Blank().height(this.getInitialTopOverlaySpacerHeight())

        // 搜索栏
        this.buildSearchBar()

        // 功能按钮行
        this.buildActionButtons()

        // 图源列表区域
        Refresh({ refreshing: this.loadingState.refreshingSourceList }) {
          Scroll() {
            Column({ space: 12 }) {
              // 图源列表
              this.buildSourceList()

              // 使用说明
              this.buildSourceUsageGuide()

              Blank().height(this.getMainTabBottomSpacerHeight())
            }
            .width('100%')
          }
          .scrollBar(BarState.Off)
          .edgeEffect(EdgeEffect.Spring)
        }
        .onRefreshing(async () => {
          await this.handleSourceRefresh();
        })
        .layoutWeight(1)
      }
      .width('100%')
      .height('100%')

      // 图源搜索对话框
      if (this.showSourceSearchDialog) {
        this.buildSourceSearchDialog()
      }
    }
    .width('100%')
    .height('100%')
  }

  @Builder
  buildSearchBar() {
    Row({ space: 8 }) {
      Search({ value: this.sourceSearchKeyword, placeholder: '可使用前缀格式 pixiv//id//作品ID' })
        .searchButton('搜索')
        .layoutWeight(1)
        .onChange((value: string) => {
          this.searchSources(value);
        })
        .onSubmit(async (value: string) => {
          // 检查是否是全局前缀格式
          if (value.includes('//')) {
            // 前缀搜索逻辑由父组件处理
          }
        })

      // 快捷前缀选择按钮
      Button() {
        SymbolGlyph($r('sys.symbol.capture_smiles'))
          .fontSize(20)
          .fontColor([ThemeAwareHelper.getTestManagementThemedColor('text_primary', this.themeState.currentTheme)])
      }
      .width(40)
      .height(40)
      .backgroundColor(this.getSettingsAnalyticsCardBackground())
      .backgroundBlurStyle(this.getSettingsAnalyticsCardBlurStyle(), this.getSettingsAnalyticsCardBlurOptions())
      .backgroundEffect(this.getSettingsAnalyticsCardBackgroundEffect())
      .border({
        width: this.getSettingsAnalyticsCardBorderWidth(),
        color: this.getSettingsAnalyticsCardBorderColor()
      })
      .borderRadius(12)
      .shadow({
        radius: this.getSettingsAnalyticsCardRadius(),
        color: this.getSettingsAnalyticsCardShadowColor(),
        offsetX: 0,
        offsetY: 2
      })
      .clip(true)
      .bindMenu([
        {
          value: 'Pixiv - 作品ID',
          action: () => {
            this.sourceSearchKeyword = 'pixiv//id//';
            this.applySourceFilters();
          }
        },
        {
          value: 'Pixiv - 用户ID',
          action: () => {
            this.sourceSearchKeyword = 'pixiv//user//';
            this.applySourceFilters();
          }
        },
        {
          value: '禁漫天堂 - 作品ID',
          action: () => {
            this.sourceSearchKeyword = 'jm//id//';
            this.applySourceFilters();
          }
        },
        {
          value: '哔咔漫画 - 作品ID',
          action: () => {
            this.sourceSearchKeyword = 'pica//id//';
            this.applySourceFilters();
          }
        }
      ])
    }
    .width('100%')
    .padding(16)
    .backgroundColor(Color.Transparent)
  }

  @Builder
  buildActionButtons() {
    Row({ space: 12 }) {
      // 图源管理按钮
      Button('图源管理')
        .fontSize(14)
        .fontFamily(this.appFontFamily)
        .fontColor(ThemeAwareHelper.getTestManagementThemedColor('accent_primary', this.themeState.currentTheme))
        .backgroundColor(this.getSettingsAnalyticsCardBackground())
        .backgroundBlurStyle(this.getSettingsAnalyticsCardBlurStyle(), this.getSettingsAnalyticsCardBlurOptions())
        .backgroundEffect(this.getSettingsAnalyticsCardBackgroundEffect())
        .border({
          width: this.getSettingsAnalyticsCardBorderWidth(),
          color: this.getSettingsAnalyticsCardBorderColor()
        })
        .borderRadius(16)
        .shadow({
          radius: this.getSettingsAnalyticsCardRadius(),
          color: this.getSettingsAnalyticsCardShadowColor(),
          offsetX: 0,
          offsetY: 2
        })
        .clip(true)
        .onClick(() => {
          this.pathStack.pushPathByName('SourceManagementPage', null);
        })

      Button('图源导入')
        .fontSize(14)
        .fontFamily(this.appFontFamily)
        .fontColor(ThemeAwareHelper.getTestManagementThemedColor('accent_blue', this.themeState.currentTheme))
        .backgroundColor(this.getSettingsAnalyticsCardBackground())
        .backgroundBlurStyle(this.getSettingsAnalyticsCardBlurStyle(), this.getSettingsAnalyticsCardBlurOptions())
        .backgroundEffect(this.getSettingsAnalyticsCardBackgroundEffect())
        .border({
          width: this.getSettingsAnalyticsCardBorderWidth(),
          color: this.getSettingsAnalyticsCardBorderColor()
        })
        .borderRadius(16)
        .shadow({
          radius: this.getSettingsAnalyticsCardRadius(),
          color: this.getSettingsAnalyticsCardShadowColor(),
          offsetX: 0,
          offsetY: 2
        })
        .clip(true)
        .onClick(() => {
          // 导入逻辑由父组件处理
        })

      Button('链接跳转')
        .fontSize(14)
        .fontFamily(this.appFontFamily)
        .fontColor(ThemeAwareHelper.getTestManagementThemedColor('accent_blue', this.themeState.currentTheme))
        .backgroundColor(this.getSettingsAnalyticsCardBackground())
        .backgroundBlurStyle(this.getSettingsAnalyticsCardBlurStyle(), this.getSettingsAnalyticsCardBlurOptions())
        .backgroundEffect(this.getSettingsAnalyticsCardBackgroundEffect())
        .border({
          width: this.getSettingsAnalyticsCardBorderWidth(),
          color: this.getSettingsAnalyticsCardBorderColor()
        })
        .borderRadius(16)
        .shadow({
          radius: this.getSettingsAnalyticsCardRadius(),
          color: this.getSettingsAnalyticsCardShadowColor(),
          offsetX: 0,
          offsetY: 2
        })
        .clip(true)
        .onClick(() => {
          // 链接跳转逻辑由父组件处理
        })

      // 有更新时显示升级图标
      if (this.hasSourceUpdate) {
        Image($r('app.media.ic_upgrade'))
          .width(24)
          .height(24)
          .onClick(async () => {
            // 同步逻辑由父组件处理
          })
      }

      // 类型筛选按钮
      Button() {
        Image(this.getSourceTypeFilterIcon())
          .width(24)
          .height(24)
          .fillColor(ThemeAwareHelper.getTestManagementThemedColor('text_primary', this.themeState.currentTheme))
      }
      .type(ButtonType.Circle)
      .width(36)
      .height(36)
      .backgroundColor(this.getSettingsAnalyticsCardBackground())
      .backgroundBlurStyle(this.getSettingsAnalyticsCardBlurStyle(), this.getSettingsAnalyticsCardBlurOptions())
      .backgroundEffect(this.getSettingsAnalyticsCardBackgroundEffect())
      .border({
        width: this.getSettingsAnalyticsCardBorderWidth(),
        color: this.getSettingsAnalyticsCardBorderColor()
      })
      .borderRadius(18)
      .shadow({
        radius: this.getSettingsAnalyticsCardRadius(),
        color: this.getSettingsAnalyticsCardShadowColor(),
        offsetX: 0,
        offsetY: 2
      })
      .clip(true)
      .onClick(() => {
        this.cycleSourceTypeFilter();
      })

      // 视图切换按钮
      Button() {
        SymbolGlyph(this.sourceViewMode === LibraryViewMode.LIST
          ? $r('sys.symbol.list_bullet')
          : $r('sys.symbol.square_grid_2x2'))
          .fontSize(20)
          .fontColor([ThemeAwareHelper.getTestManagementThemedColor('text_primary', this.themeState.currentTheme)])
      }
      .type(ButtonType.Circle)
      .width(36)
      .height(36)
      .backgroundColor(this.getSettingsAnalyticsCardBackground())
      .backgroundBlurStyle(this.getSettingsAnalyticsCardBlurStyle(), this.getSettingsAnalyticsCardBlurOptions())
      .backgroundEffect(this.getSettingsAnalyticsCardBackgroundEffect())
      .border({
        width: this.getSettingsAnalyticsCardBorderWidth(),
        color: this.getSettingsAnalyticsCardBorderColor()
      })
      .borderRadius(18)
      .shadow({
        radius: this.getSettingsAnalyticsCardRadius(),
        color: this.getSettingsAnalyticsCardShadowColor(),
        offsetX: 0,
        offsetY: 2
      })
      .clip(true)
      .onClick(() => {
        animateTo({
          duration: 250,
          curve: Curve.EaseInOut
        }, () => {
          this.sourceViewMode = this.sourceViewMode === LibraryViewMode.LIST
            ? LibraryViewMode.GRID
            : LibraryViewMode.LIST;
        });
      })
    }
    .width('100%')
    .padding({ left: 16, right: 16, bottom: 12 })
  }

  @Builder
  buildSourceList() {
    Column({ space: 8 }) {
      Text(this.getSourceListTitle())
        .fontSize(16)
        .fontWeight(FontWeight.Medium)
        .fontFamily(this.appFontFamily)
        .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_primary', this.themeState.currentTheme))
        .padding({ left: 16, right: 16 })

      // 图源列表或空状态
      if (this.loadingState.sourceList) {
        // 加载状态
        Column({ space: 16 }) {
          LoadingProgress()
            .width(48)
            .height(48)
            .color(ThemeAwareHelper.getTestManagementThemedColor('accent_blue', this.themeState.currentTheme))

          Text('加载中...')
            .fontSize(14)
            .fontFamily(this.appFontFamily)
            .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_secondary', this.themeState.currentTheme))
        }
        .width('100%')
        .padding(40)
        .justifyContent(FlexAlign.Center)
      } else if (this.filteredSourceList.length === 0) {
        // 空状态提示
        Column({ space: 12 }) {
          Image(this.getSourceTypeFilterIcon())
            .width(64)
            .height(64)
            .opacity(0.3)
            .fillColor(ThemeAwareHelper.getTestManagementThemedColor('text_muted', this.themeState.currentTheme))

          Text(this.getEmptySourceTitle())
            .fontSize(16)
            .fontFamily(this.appFontFamily)
            .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_muted', this.themeState.currentTheme))

          if (!this.sourceSearchKeyword) {
            Column({ space: 8 }) {
              Text(this.getEmptySourceDescription())
                .fontSize(14)
                .fontFamily(this.appFontFamily)
                .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_muted', this.themeState.currentTheme))
                .textAlign(TextAlign.Center)

              Text(this.getEmptySourceHint())
                .fontSize(13)
                .fontFamily(this.appFontFamily)
                .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_muted', this.themeState.currentTheme))
                .opacity(0.8)
                .textAlign(TextAlign.Center)
            }
          }
        }
        .width('100%')
        .padding(40)
        .justifyContent(FlexAlign.Center)
      } else {
        // 根据视图模式显示列表或网格
        Stack() {
          // 列表视图
          if (this.sourceViewMode === LibraryViewMode.LIST) {
            List() {
              LazyForEach(this.sourceListDS, (item: SourceInfo, index: number) => {
                ListItem() {
                  this.buildSourceCard(item)
                }
              }, (item: SourceInfo) => String(item.id))
            }
            .width('100%')
            .layoutWeight(1)
            .padding({ left: 16, right: 16 })
            .cachedCount(5)
            .transition(TransitionEffect.OPACITY.animation({ duration: 200, curve: Curve.EaseInOut }))
          }

          // 网格视图
          if (this.sourceViewMode === LibraryViewMode.GRID) {
            Grid() {
              LazyForEach(this.sourceListDS, (item: SourceInfo, index: number) => {
                GridItem() {
                  this.buildSourceGridCard(item)
                }
              }, (item: SourceInfo) => String(item.id))
            }
            .columnsTemplate(this.getLibraryGridColumnsTemplate())
            .columnsGap(this.gridGap)
            .rowsGap(this.gridGap)
            .width('100%')
            .padding({ left: 16, right: 16 })
            .cachedCount(10)
            .transition(TransitionEffect.OPACITY.animation({ duration: 200, curve: Curve.EaseInOut }))
          }
        }
        .width('100%')
      }
    }
    .width('100%')
  }

  @Builder
  buildSourceCard(source: SourceInfo) {
    Row({ space: 12 }) {
      // 图源图标
      Image(source.iconPath ? source.iconPath : $r('app.media.ic_source_normal'))
        .width(40)
        .height(40)
        .borderRadius(8)

      // 图源信息
      Column({ space: 4 }) {
        Text(source.name)
          .fontSize(14)
          .fontWeight(FontWeight.Medium)
          .fontFamily(this.appFontFamily)
          .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_primary', this.themeState.currentTheme))
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })

        Text(source.baseUrl)
          .fontSize(12)
          .fontFamily(this.appFontFamily)
          .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_secondary', this.themeState.currentTheme))
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
      }
      .layoutWeight(1)
      .alignItems(HorizontalAlign.Start)

      // 状态指示器
      Column({ space: 4 }) {
        if (source.requireProxy) {
          Text('需代理')
            .fontSize(10)
            .fontFamily(this.appFontFamily)
            .fontColor(ThemeAwareHelper.getTestManagementThemedColor('accent_orange', this.themeState.currentTheme))
            .padding({ left: 6, right: 6, top: 2, bottom: 2 })
            .backgroundColor('rgba(255, 152, 0, 0.1)')
            .borderRadius(4)
        }

        Toggle({ type: ToggleType.Switch, isOn: source.isEnabled })
          .selectedColor(ThemeAwareHelper.getTestManagementThemedColor('accent_primary', this.themeState.currentTheme))
          .onChange((isOn: boolean) => {
            // 切换逻辑由父组件处理
          })
      }
    }
    .width('100%')
    .padding(12)
    .backgroundColor(this.getSettingsAnalyticsCardBackground())
    .backgroundBlurStyle(this.getSettingsAnalyticsCardBlurStyle(), this.getSettingsAnalyticsCardBlurOptions())
    .border({
      width: this.getSettingsAnalyticsCardBorderWidth(),
      color: this.getSettingsAnalyticsCardBorderColor()
    })
    .borderRadius(this.userThemeCornerRadius)
    .shadow({
      radius: this.getSettingsAnalyticsCardRadius(),
      color: this.getSettingsAnalyticsCardShadowColor(),
      offsetX: 0,
      offsetY: 2
    })
    .gesture(
      LongPressGesture()
        .onAction(() => {
          this.sourceContextMenu.showMenu(source, String(source.id));
        })
    )
    .onClick(() => {
      this.openSourceSearchDialog(source);
    })
  }

  @Builder
  buildSourceGridCard(source: SourceInfo) {
    Column({ space: 8 }) {
      // 图源图标
      Image(source.iconPath ? source.iconPath : $r('app.media.ic_source_normal'))
        .width(48)
        .height(48)
        .borderRadius(12)

      // 图源名称
      Text(source.name)
        .fontSize(12)
        .fontFamily(this.appFontFamily)
        .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_primary', this.themeState.currentTheme))
        .maxLines(2)
        .textOverflow({ overflow: TextOverflow.Ellipsis })
        .textAlign(TextAlign.Center)

      // 状态指示器
      if (source.requireProxy) {
        Text('需代理')
          .fontSize(10)
          .fontFamily(this.appFontFamily)
          .fontColor(ThemeAwareHelper.getTestManagementThemedColor('accent_orange', this.themeState.currentTheme))
          .padding({ left: 6, right: 6, top: 2, bottom: 2 })
          .backgroundColor('rgba(255, 152, 0, 0.1)')
          .borderRadius(4)
      }
    }
    .width('100%')
    .padding(12)
    .backgroundColor(this.getSettingsAnalyticsCardBackground())
    .backgroundBlurStyle(this.getSettingsAnalyticsCardBlurStyle(), this.getSettingsAnalyticsCardBlurOptions())
    .border({
      width: this.getSettingsAnalyticsCardBorderWidth(),
      color: this.getSettingsAnalyticsCardBorderColor()
    })
    .borderRadius(this.userThemeCornerRadius)
    .shadow({
      radius: this.getSettingsAnalyticsCardRadius(),
      color: this.getSettingsAnalyticsCardShadowColor(),
      offsetX: 0,
      offsetY: 2
    })
    .gesture(
      LongPressGesture()
        .onAction(() => {
          this.sourceContextMenu.showMenu(source, String(source.id));
        })
    )
    .onClick(() => {
      this.openSourceSearchDialog(source);
    })
  }

  @Builder
  buildSourceSearchDialog() {
    Column() {
      Column({ space: 16 }) {
        // 标题
        Row({ space: 8 }) {
          SymbolGlyph($r('sys.symbol.magnifyingglass'))
            .fontSize(20)
            .fontColor([ThemeAwareHelper.getTestManagementThemedColor('accent_primary', this.themeState.currentTheme)])
          Text(`在 ${this.searchTargetSource?.name || '图源'} 中搜索`)
            .fontSize(16)
            .fontWeight(FontWeight.Medium)
            .fontFamily(this.appFontFamily)
            .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_primary', this.themeState.currentTheme))
        }
        .width('100%')

        // 搜索类型选择器
        if (this.sourceSearchTypes.length > 1) {
          Scroll() {
            Row({ space: 8 }) {
              ForEach(this.sourceSearchTypes, (type: SearchTypeOption) => {
                Button(type.label)
                  .fontSize(12)
                  .fontFamily(this.appFontFamily)
                  .height(30)
                  .padding({ left: 12, right: 12 })
                  .backgroundColor(this.selectedSourceSearchType === type.id
                    ? ThemeAwareHelper.getTestManagementThemedColor('accent_primary', this.themeState.currentTheme)
                    : ThemeAwareHelper.getTestManagementThemedColor('comp_background_tertiary', this.themeState.currentTheme))
                  .fontColor(this.selectedSourceSearchType === type.id
                    ? ThemeAwareHelper.getTestManagementThemedColor('text_white', this.themeState.currentTheme)
                    : ThemeAwareHelper.getTestManagementThemedColor('text_secondary', this.themeState.currentTheme))
                  .borderRadius(15)
                  .onClick(() => {
                    this.selectedSourceSearchType = type.id;
                    this.sourceSearchPlaceholder = `搜索${type.label}...`;
                  })
              }, (type: SearchTypeOption) => type.id)
            }
          }
          .width('100%')
          .scrollBar(BarState.Off)
        }

        // 搜索输入框
        Search({ value: this.sourceSearchInput, placeholder: this.sourceSearchPlaceholder })
          .searchButton('搜索')
          .width('100%')
          .onChange((value: string) => {
            this.sourceSearchInput = value;
          })
          .onSubmit(async (value: string) => {
            // 搜索逻辑由父组件处理
          })

        // 取消按钮
        Button('取消')
          .fontSize(14)
          .fontFamily(this.appFontFamily)
          .width('100%')
          .backgroundColor(this.getSettingsAnalyticsCardBackground())
          .backgroundBlurStyle(this.getSettingsAnalyticsCardBlurStyle(), this.getSettingsAnalyticsCardBlurOptions())
          .border({
            width: this.getSettingsAnalyticsCardBorderWidth(),
            color: this.getSettingsAnalyticsCardBorderColor()
          })
          .borderRadius(12)
          .onClick(() => {
            this.closeSourceSearchDialog();
          })
      }
      .width('100%')
      .padding(20)
    }
    .width('100%')
    .height('100%')
    .backgroundColor('rgba(0, 0, 0, 0.5)')
    .justifyContent(FlexAlign.Center)
    .padding(32)
  }

  @Builder
  buildSourceUsageGuide() {
    Column({ space: 12 }) {
      Text('使用说明')
        .fontSize(16)
        .fontWeight(FontWeight.Medium)
        .fontFamily(this.appFontFamily)
        .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_primary', this.themeState.currentTheme))

      Column({ space: 8 }) {
        Text('1. 点击图源卡片可快速搜索该图源')
          .fontSize(13)
          .fontFamily(this.appFontFamily)
          .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_secondary', this.themeState.currentTheme))

        Text('2. 长按图源卡片可查看右键菜单')
          .fontSize(13)
          .fontFamily(this.appFontFamily)
          .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_secondary', this.themeState.currentTheme))

        Text('3. 使用前缀格式可快速定位作品（如 pixiv//id//12345）')
          .fontSize(13)
          .fontFamily(this.appFontFamily)
          .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_secondary', this.themeState.currentTheme))

        Text('4. 点击右上角按钮可切换列表/网格视图')
          .fontSize(13)
          .fontFamily(this.appFontFamily)
          .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_secondary', this.themeState.currentTheme))
      }
    }
    .width('100%')
    .padding(16)
    .backgroundColor(this.getSettingsAnalyticsCardBackground())
    .backgroundBlurStyle(this.getSettingsAnalyticsCardBlurStyle(), this.getSettingsAnalyticsCardBlurOptions())
    .border({
      width: this.getSettingsAnalyticsCardBorderWidth(),
      color: this.getSettingsAnalyticsCardBorderColor()
    })
    .borderRadius(this.userThemeCornerRadius)
    .margin({ left: 16, right: 16 })
  }
}
