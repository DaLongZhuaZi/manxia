/**
 * HDS 风格底栏组件
 * 基于 HdsTabs 实现，自定义 tabBar Builder 控制选中态样式
 * HdsTabs 提供浮动胶囊、材质光效、触摸反馈等系统级动效
 */

import {
  BlurStrategy,
  DividerMode,
  hdsMaterial,
  HdsDividerStyle,
  HdsBarWidthRangeOptions,
  HdsTabs,
  HdsTabsBackgroundStyle,
  HdsTabsController,
  HdsTabsFloatingStyle,
  SystemMaterialParams
} from '@kit.UIDesignKit';
import { ThemeType } from 'manxia_theme/src/main/ets/Framework/Managers/ThemeManager';

const HDS_BAR_SIDE_GUARD: number = 8;
const HDS_GLASS_BAR_OPACITY_RATIO: number = 0.82;
const HDS_GLASS_BAR_MAX_OPACITY: number = 0.90;
const HDS_GLASS_BAR_MIN_OPACITY: number = 0.68;
const HDS_GLASS_LIGHT_HIGHLIGHT_OPACITY: number = 0.50;
const HDS_GLASS_DARK_HIGHLIGHT_OPACITY: number = 0.34;
const HDS_GLOBAL_MATERIAL_LEVEL: number = -1;
const HDS_VERTICAL_BAR_WIDTH: number = 68;
const HDS_VERTICAL_BAR_SIDE_MARGIN: number = 8;
const HDS_VERTICAL_BAR_BOTTOM_MARGIN: number = 8;
const HDS_VERTICAL_TAB_ITEM_HEIGHT: number = 56;
const HDS_VERTICAL_BAR_VERTICAL_PADDING: number = 16;

export interface HdsBottomBarTabConfig {
  title: string;
  icon: Resource;
  selectedIcon: Resource;
  systemIcon?: Resource;
  useSystemIcon?: boolean;
  hasMultiColor?: boolean;
  applyFillColor?: boolean;
  index: number;
  required: boolean;
}

@Component
export struct HdsStyleBottomBar {
  @Prop @Watch('onSelectedIndexChanged') selectedIndex: number = 0;
  @Prop @Watch('onVisibleTabConfigsChanged') visibleTabConfigs: HdsBottomBarTabConfig[] = [];
  @Prop tabBarOpacity: number = 1.0;
  @Prop themeType: ThemeType = ThemeType.LIGHT;
  @Prop hasSourceUpdate: boolean = false;
  @Prop isPrivacyMode: boolean = false;
  @Prop vertical: boolean = false;
  @Prop barPosition: BarPosition = BarPosition.End;
  @Prop showSearchTab: boolean = false;
  @Prop verticalScrollable: boolean = false;
  @Prop verticalBarHeight: number = 0;
  @Prop verticalContainerHeight: number = 0;
  @StorageProp('visual_effects_effective_material_level') effectiveMaterialLevel: number = 10;
  @StorageProp('userTheme_hdsTabOpacityRatio') hdsTabOpacityRatio: number = HDS_GLASS_BAR_OPACITY_RATIO;
  @StorageProp('userTheme_hdsTabMinOpacity') hdsTabMinOpacity: number = HDS_GLASS_BAR_MIN_OPACITY;
  @StorageProp('userTheme_hdsTabMaxOpacity') hdsTabMaxOpacity: number = HDS_GLASS_BAR_MAX_OPACITY;
  @StorageProp('userTheme_hdsTabLightHighlightOpacity') hdsTabLightHighlightOpacity: number = HDS_GLASS_LIGHT_HIGHLIGHT_OPACITY;
  @StorageProp('userTheme_hdsTabDarkHighlightOpacity') hdsTabDarkHighlightOpacity: number = HDS_GLASS_DARK_HIGHLIGHT_OPACITY;
  @StorageProp('userTheme_hdsTabMaterialLevel') hdsTabMaterialLevel: number = hdsMaterial.MaterialLevel.EXQUISITE;
  @StorageProp('userTheme_hdsTabBlurEnabled') hdsTabBlurEnabled: boolean = true;
  @StorageProp('userTheme_hdsTabSideMargin') hdsTabSideMargin: number = HDS_BAR_SIDE_GUARD;
  @StorageProp('userTheme_hdsTabBottomMargin') hdsTabBottomMargin: number = 0;
  onChangeCallback: (actualIndex: number) => void = (): void => {};
  longPressCallback: (tabIndex: number) => void = (): void => {};
  searchCallback: () => void = (): void => {};
  controllerRefCallback: (controller: HdsTabsController) => void = (): void => {};
  setSyncingCallback: (setter: (syncing: boolean) => void) => void = (): void => {};
  @State private visualSelectedIndex: number = 0;

  private controller: HdsTabsController = new HdsTabsController();
  private isSyncingIndex: boolean = false;

  aboutToAppear(): void {
    this.updateVisualSelectedIndex(this.selectedIndex);
    this.controllerRefCallback(this.controller);
    this.setSyncingCallback((syncing: boolean): void => {
      this.isSyncingIndex = syncing;
    });
  }

  onSelectedIndexChanged(): void {
    this.updateVisualSelectedIndex(this.selectedIndex);
  }

  onVisibleTabConfigsChanged(): void {
    this.updateVisualSelectedIndex(this.selectedIndex);
  }

  private shouldShowSearchTab(): boolean {
    return this.vertical && this.showSearchTab;
  }

  private getSearchTabOffset(): number {
    return this.shouldShowSearchTab() ? 1 : 0;
  }

  private getSafeRealSelectedIndex(index: number): number {
    const tabCount: number = this.visibleTabConfigs.length;
    if (tabCount <= 0) {
      return 0;
    }
    if (index >= 0 && index < tabCount) {
      return index;
    }
    return 0;
  }

  private getSafeSelectedIndex(index: number): number {
    if (this.visibleTabConfigs.length <= 0) {
      return 0;
    }
    return this.getSafeRealSelectedIndex(index) + this.getSearchTabOffset();
  }

  private isSearchTabIndex(index: number): boolean {
    return this.shouldShowSearchTab() && index === 0;
  }

  private getRealIndexForVisualIndex(index: number): number {
    return this.getSafeRealSelectedIndex(index - this.getSearchTabOffset());
  }

  private getVerticalTabCount(): number {
    return this.visibleTabConfigs.length + this.getSearchTabOffset();
  }

  private getPreferredVerticalBarHeight(): number {
    const tabCount: number = Math.max(1, this.getVerticalTabCount());
    return tabCount * HDS_VERTICAL_TAB_ITEM_HEIGHT + HDS_VERTICAL_BAR_VERTICAL_PADDING;
  }

  private getEffectiveVerticalBarHeight(): number {
    if (this.verticalBarHeight > 0) {
      return Math.max(HDS_VERTICAL_TAB_ITEM_HEIGHT, this.verticalBarHeight);
    }
    return this.getPreferredVerticalBarHeight();
  }

  private getEffectiveVerticalContainerHeight(): number {
    if (this.verticalContainerHeight > 0) {
      return Math.max(this.getEffectiveVerticalBarHeight(), this.verticalContainerHeight);
    }
    return this.getEffectiveVerticalBarHeight() + HDS_VERTICAL_BAR_BOTTOM_MARGIN * 2;
  }

  private updateVisualSelectedIndex(index: number): number {
    const safeIndex: number = this.getSafeSelectedIndex(index);
    if (this.visualSelectedIndex !== safeIndex) {
      this.visualSelectedIndex = safeIndex;
    }
    return safeIndex;
  }

  private restoreCurrentSelectedTab(): void {
    const safeIndex: number = this.updateVisualSelectedIndex(this.selectedIndex);
    this.isSyncingIndex = true;
    this.controller.changeIndex(safeIndex);
    this.isSyncingIndex = false;
  }

  private isTabSelected(actualIndex: number): boolean {
    return this.visualSelectedIndex === actualIndex;
  }

  private getActiveColor(): string {
    return this.themeType === ThemeType.DARK ? '#8BD8FF' : '#006EDC';
  }

  private getInactiveColor(): string {
    return this.themeType === ThemeType.DARK ? '#EDF6FF' : '#111827';
  }

  private getNavigationColor(selected: boolean): string {
    return selected ? this.getActiveColor() : this.getInactiveColor();
  }

  /**
   * Keep HDS tab identities aligned with the classic MainMenu bottom bar.
   * These identifiers are both accessibility contracts and stable anchors for
   * selector-only Hypium UI automation.
   */
  private getSemanticTabId(tabIndex: number): string {
    switch (tabIndex) {
      case 0:
        return 'guide_main_tab_home';
      case 1:
        return 'guide_main_tab_library';
      case 2:
        return 'guide_main_tab_discover';
      case 3:
        return 'guide_main_tab_source';
      case 4:
        return 'guide_main_tab_book_source';
      case 5:
        return 'guide_main_tab_suwayomi';
      case 6:
        return 'guide_main_tab_settings';
      default:
        return `guide_main_tab_${tabIndex}`;
    }
  }

  private handleSemanticTabClick(actualIndex: number): void {
    if (this.isSearchTabIndex(actualIndex)) {
      this.searchCallback();
      this.restoreCurrentSelectedTab();
      return;
    }
    const realIndex: number = this.getRealIndexForVisualIndex(actualIndex);
    this.updateVisualSelectedIndex(realIndex);
    // The custom tab-bar builder owns the click target, so HdsTabs does not
    // reliably commit its own selection before the parent Swiper re-renders.
    // Commit the visual index explicitly, then forward the actual Swiper index.
    this.isSyncingIndex = true;
    this.controller.changeIndex(this.getSafeSelectedIndex(realIndex));
    this.isSyncingIndex = false;
    if (!this.isSyncingIndex && this.selectedIndex !== realIndex) {
      this.onChangeCallback(realIndex);
    }
  }

  private getSystemIcon(config: HdsBottomBarTabConfig): Resource {
    if (this.isPrivacyMode && config.index === 1) {
      return $r('sys.symbol.lock');
    }
    if (config.systemIcon) {
      return config.systemIcon;
    }
    return $r('sys.symbol.bookshelf');
  }

  private getGlassBarOpacity(): number {
    const baseOpacity: number = Math.max(0, Math.min(1, this.tabBarOpacity));
    if (baseOpacity <= 0) {
      return 0;
    }
    const ratio: number = Math.max(0, Math.min(1, this.hdsTabOpacityRatio));
    const minOpacity: number = Math.max(0, Math.min(1, this.hdsTabMinOpacity));
    const maxOpacity: number = Math.max(minOpacity, Math.min(1, this.hdsTabMaxOpacity));
    const glassOpacity: number = baseOpacity * ratio;
    return Math.min(maxOpacity, Math.max(minOpacity, glassOpacity));
  }

  private getGlassMaterialLevel(): hdsMaterial.MaterialLevel {
    const configuredLevel: number = this.hdsTabMaterialLevel;
    const rawLevel: number = configuredLevel === HDS_GLOBAL_MATERIAL_LEVEL
      ? this.effectiveMaterialLevel
      : configuredLevel;
    if (rawLevel === hdsMaterial.MaterialLevel.ADAPTIVE) {
      return hdsMaterial.MaterialLevel.EXQUISITE;
    }
    if (rawLevel === hdsMaterial.MaterialLevel.EXQUISITE ||
      rawLevel === hdsMaterial.MaterialLevel.GENTLE ||
      rawLevel === hdsMaterial.MaterialLevel.SMOOTH) {
      return rawLevel as hdsMaterial.MaterialLevel;
    }
    return hdsMaterial.MaterialLevel.EXQUISITE;
  }

  private getGlassHighlightOpacity(): number {
    const rawOpacity: number = this.themeType === ThemeType.DARK
      ? this.hdsTabDarkHighlightOpacity
      : this.hdsTabLightHighlightOpacity;
    return Math.max(0, Math.min(1, rawOpacity));
  }

  private getGlassLightColor(): ResourceColor {
    return `rgba(255, 255, 255, ${this.getGlassHighlightOpacity()})`;
  }

  private getItemTextShadowColor(selected: boolean): ResourceColor {
    if (this.themeType === ThemeType.DARK) {
      return selected ? 'rgba(0, 0, 0, 0.46)' : 'rgba(0, 0, 0, 0.58)';
    }
    return selected ? 'rgba(255, 255, 255, 0.60)' : 'rgba(255, 255, 255, 0.78)';
  }

  private getBlurStrategy(): BlurStrategy {
    return this.hdsTabBlurEnabled ? BlurStrategy.ENABLE : BlurStrategy.DISABLE;
  }

  private getBarBackgroundBlurStyle(): BlurStyle {
    return this.hdsTabBlurEnabled ? BlurStyle.COMPONENT_THICK : BlurStyle.NONE;
  }

  private getBarSideMargin(): number {
    if (this.vertical) {
      return HDS_VERTICAL_BAR_SIDE_MARGIN;
    }
    return Math.max(0, Math.min(24, this.hdsTabSideMargin));
  }

  private getBarBottomMargin(): number {
    if (this.vertical) {
      return HDS_VERTICAL_BAR_BOTTOM_MARGIN;
    }
    return Math.max(-8, Math.min(16, this.hdsTabBottomMargin));
  }

  private buildVerticalBarWidth(): HdsBarWidthRangeOptions {
    const width: HdsBarWidthRangeOptions = {
      smallWidth: HDS_VERTICAL_BAR_WIDTH,
      mediumWidth: HDS_VERTICAL_BAR_WIDTH,
      largeWidth: HDS_VERTICAL_BAR_WIDTH
    };
    return width;
  }

  private buildFloatingStyle(): HdsTabsFloatingStyle {
    const materialLevel: hdsMaterial.MaterialLevel = this.getGlassMaterialLevel();
    const materialParams: SystemMaterialParams = {
      materialType: hdsMaterial.MaterialType.IMMERSIVE,
      materialLevel: materialLevel
    };
    const gradientMask: HdsTabsBackgroundStyle = {
      maskColor: Color.Transparent,
      maskHeight: 0
    };
    if (this.vertical) {
      // 竖向侧边栏浮动样式
      // barWidth: 控制胶囊的水平宽度（68vp），barSideMargin: 在竖向模式下控制 bar 的上下边距
      // （类比横向时 barSideMargin 控制左右边距），使胶囊在高度方向两端内缩，呈现圆角胶囊形
      // barBottomMargin: 竖向时控制胶囊距侧边的偏移量
      const verticalStyle: HdsTabsFloatingStyle = {
        barWidth: this.buildVerticalBarWidth(),
        barSideMargin: this.getBarSideMargin(),
        barBottomMargin: this.getBarBottomMargin(),
        gradientMask: gradientMask,
        adaptToHandedness: false,
        lightColor: this.getGlassLightColor(),
        systemMaterialEffect: materialParams,
        thermoCtrl: true,
        barOpacity: this.getGlassBarOpacity()
      };
      return verticalStyle;
    }

    const style: HdsTabsFloatingStyle = {
      barSideMargin: this.getBarSideMargin(),
      barBottomMargin: this.getBarBottomMargin(),
      gradientMask: gradientMask,
      adaptToHandedness: true,
      lightColor: this.getGlassLightColor(),
      systemMaterialEffect: materialParams,
      thermoCtrl: true,
      barOpacity: this.getGlassBarOpacity()
    };
    return style;
  }

  private buildDividerStyle(): HdsDividerStyle {
    const style: HdsDividerStyle = {
      mode: DividerMode.NONE
    };
    return style;
  }

  private buildTransparentTabsBackgroundStyle(): HdsTabsBackgroundStyle {
    const style: HdsTabsBackgroundStyle = {
      maskColor: Color.Transparent,
      maskHeight: 0
    };
    return style;
  }

  @Builder
  private buildTabsContent(): void {
    if (this.shouldShowSearchTab()) {
      TabContent() {
      }
      .backgroundColor(Color.Transparent)
      .tabBar(this.buildSearchTabBarItem())
    }

    ForEach(this.visibleTabConfigs, (cfg: HdsBottomBarTabConfig, idx: number): void => {
      TabContent() {
      }
      .backgroundColor(Color.Transparent)
      .tabBar(this.buildTabBarItem(cfg, idx + this.getSearchTabOffset()))
    }, (cfg: HdsBottomBarTabConfig, _idx: number): string => `hds_tab_${cfg.index}`)
  }

  private handleHdsTabsSelected(index: number): void {
    if (!this.isSearchTabIndex(index)) {
      this.updateVisualSelectedIndex(this.getRealIndexForVisualIndex(index));
    }
  }

  private handleHdsTabsChange(index: number): void {
    if (this.isSearchTabIndex(index)) {
      this.searchCallback();
      this.restoreCurrentSelectedTab();
      return;
    }

    const realIndex: number = this.getRealIndexForVisualIndex(index);
    this.updateVisualSelectedIndex(realIndex);
    if (!this.isSyncingIndex && this.selectedIndex !== realIndex) {
      this.onChangeCallback(realIndex);
    }
  }

  build(): void {
    if (this.vertical) {
      // 竖向侧边栏：直接以 HdsTabs 为根节点
      HdsTabs({
        controller: this.controller,
        index: this.visualSelectedIndex
      }) {
        this.buildTabsContent()
      }
      .width('100%')
      .height(this.getEffectiveVerticalContainerHeight())
      .vertical(true)
      .barPosition(this.barPosition)
      .barMode(this.verticalScrollable ? BarMode.Scrollable : BarMode.Fixed)
      .barWidth(HDS_VERTICAL_BAR_WIDTH)
      .barHeight(this.getEffectiveVerticalBarHeight())
      .barOverlap(true)
      .divider(this.buildDividerStyle())
      .barBackgroundColor(Color.Transparent)
      .barBackgroundBlurStyle(this.getBarBackgroundBlurStyle())
      .barBackgroundStyle(this.buildTransparentTabsBackgroundStyle())
      .blurStrategy(this.getBlurStrategy())
      .barFloatingStyle(this.buildFloatingStyle())
      .onSelected((index: number): void => {
        this.handleHdsTabsSelected(index);
      })
      .onChange((index: number): void => {
        this.handleHdsTabsChange(index);
      })
    } else {
      HdsTabs({
        controller: this.controller,
        index: this.visualSelectedIndex
      }) {
        this.buildTabsContent()
      }
      .width('100%')
      .height(56)
      .barPosition(BarPosition.End)
      .barMode(BarMode.Fixed)
      .barOverlap(true)
      .divider(this.buildDividerStyle())
      .barBackgroundColor(Color.Transparent)
      .barBackgroundBlurStyle(this.getBarBackgroundBlurStyle())
      .barBackgroundStyle(this.buildTransparentTabsBackgroundStyle())
      .blurStrategy(this.getBlurStrategy())
      .barFloatingStyle(this.buildFloatingStyle())
      .onSelected((index: number): void => {
        this.handleHdsTabsSelected(index);
      })
      .onChange((index: number): void => {
        this.handleHdsTabsChange(index);
      })
    }
  }

  @Builder
  buildSearchTabBarItem(): void {
    if (this.vertical) {
      Stack({ alignContent: Alignment.Center }) {
        Column({ space: 4 }) {
          SymbolGlyph($r('sys.symbol.magnifyingglass'))
            .fontSize(24)
            .fontColor([this.getNavigationColor(false)])
            .renderingStrategy(SymbolRenderingStrategy.SINGLE)

          Text('搜索')
            .width('100%')
            .fontSize(10)
            .fontColor(this.getNavigationColor(false))
            .fontWeight(FontWeight.Normal)
            .maxLines(1)
            .textAlign(TextAlign.Center)
            .textShadow({
              radius: 2,
              color: this.getItemTextShadowColor(false),
              offsetX: 0,
              offsetY: 1
            })
        }
        .width(HDS_VERTICAL_BAR_WIDTH)
        .height(HDS_VERTICAL_TAB_ITEM_HEIGHT)
        .alignItems(HorizontalAlign.Center)
        .justifyContent(FlexAlign.Center)
      }
      .width(HDS_VERTICAL_BAR_WIDTH)
      .height(HDS_VERTICAL_TAB_ITEM_HEIGHT)
    } else {
      Column({ space: 4 }) {
        SymbolGlyph($r('sys.symbol.magnifyingglass'))
          .fontSize(24)
          .fontColor([this.getNavigationColor(false)])
          .renderingStrategy(SymbolRenderingStrategy.SINGLE)

        Text('搜索')
          .fontSize(10)
          .fontColor(this.getNavigationColor(false))
          .fontWeight(FontWeight.Normal)
          .maxLines(1)
          .textAlign(TextAlign.Center)
          .textShadow({
            radius: 2,
            color: this.getItemTextShadowColor(false),
            offsetX: 0,
            offsetY: 1
          })
      }
      .width('100%')
      .height(56)
      .justifyContent(FlexAlign.Center)
      .padding({ left: 4, right: 4 })
    }
  }

  @Builder
  buildTabBarItem(config: HdsBottomBarTabConfig, actualIndex: number): void {
    if (this.vertical) {
      Stack({ alignContent: Alignment.Center }) {
        Column({ space: 4 }) {
          Stack() {
            if (config.useSystemIcon) {
              SymbolGlyph(this.getSystemIcon(config))
                .fontSize(24)
                .fontColor([this.getNavigationColor(this.isTabSelected(actualIndex))])
                .renderingStrategy(SymbolRenderingStrategy.SINGLE)
            } else if (config.applyFillColor === false) {
              Image(this.isTabSelected(actualIndex) ? config.selectedIcon : config.icon)
                .width(24)
                .height(24)
            } else {
              Image(this.isTabSelected(actualIndex) ? config.selectedIcon : config.icon)
                .width(24)
                .height(24)
                .fillColor(this.getNavigationColor(this.isTabSelected(actualIndex)))
            }

            if (config.index === 3 && this.hasSourceUpdate) {
              Circle()
                .width(8)
                .height(8)
                .fill('#FF4444')
                .position({ x: 16, y: 0 })
            }
          }
          .width(24)
          .height(24)
          .opacity(this.isTabSelected(actualIndex) ? 1 : (this.themeType === ThemeType.DARK ? 0.92 : 0.94))

          Text(config.title)
            .width('100%')
            .fontSize(10)
            .fontColor(this.getNavigationColor(this.isTabSelected(actualIndex)))
            .fontWeight(this.isTabSelected(actualIndex) ? FontWeight.Medium : FontWeight.Normal)
            .maxLines(2)
            .textAlign(TextAlign.Center)
            .textShadow({
              radius: this.isTabSelected(actualIndex) ? 3 : 2,
              color: this.getItemTextShadowColor(this.isTabSelected(actualIndex)),
              offsetX: 0,
              offsetY: 1
            })
        }
        .width(HDS_VERTICAL_BAR_WIDTH)
        .height(HDS_VERTICAL_TAB_ITEM_HEIGHT)
        .alignItems(HorizontalAlign.Center)
        .justifyContent(FlexAlign.Center)
      }
      .width(HDS_VERTICAL_BAR_WIDTH)
      .height(HDS_VERTICAL_TAB_ITEM_HEIGHT)
      .id(this.getSemanticTabId(config.index))
      .onClick((): void => {
        this.handleSemanticTabClick(actualIndex);
      })
      .gesture(
        LongPressGesture({ repeat: false, duration: 500 })
          .onAction((): void => {
            this.longPressCallback(config.index);
          })
      )
    } else {
      Column({ space: 4 }) {
        Stack() {
          if (config.useSystemIcon) {
            SymbolGlyph(this.getSystemIcon(config))
              .fontSize(24)
              .fontColor([this.getNavigationColor(this.isTabSelected(actualIndex))])
              .renderingStrategy(SymbolRenderingStrategy.SINGLE)
          } else if (config.applyFillColor === false) {
            Image(this.isTabSelected(actualIndex) ? config.selectedIcon : config.icon)
              .width(24)
              .height(24)
          } else {
            Image(this.isTabSelected(actualIndex) ? config.selectedIcon : config.icon)
              .width(24)
              .height(24)
              .fillColor(this.getNavigationColor(this.isTabSelected(actualIndex)))
          }

          if (config.index === 3 && this.hasSourceUpdate) {
            Circle()
              .width(8)
              .height(8)
              .fill('#FF4444')
              .position({ x: 16, y: 0 })
          }
        }
        .width(24)
        .height(24)
        .opacity(this.isTabSelected(actualIndex) ? 1 : (this.themeType === ThemeType.DARK ? 0.92 : 0.94))

        Text(config.title)
          .fontSize(12)
          .fontColor(this.getNavigationColor(this.isTabSelected(actualIndex)))
          .fontWeight(this.isTabSelected(actualIndex) ? FontWeight.Medium : FontWeight.Normal)
          .maxLines(1)
          .textAlign(TextAlign.Center)
          .textShadow({
            radius: this.isTabSelected(actualIndex) ? 3 : 2,
            color: this.getItemTextShadowColor(this.isTabSelected(actualIndex)),
            offsetX: 0,
            offsetY: 1
          })
      }
      .width('100%')
      .height(44)
      .justifyContent(FlexAlign.Center)
      .padding({ left: 4, right: 4 })
      .id(this.getSemanticTabId(config.index))
      .onClick((): void => {
        this.handleSemanticTabClick(actualIndex);
      })
      .gesture(
        LongPressGesture({ repeat: false, duration: 500 })
          .onAction((): void => {
            this.longPressCallback(config.index);
          })
      )
    }
  }
}
