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
  HdsTabs,
  HdsTabsBackgroundStyle,
  HdsTabsController,
  HdsTabsFloatingStyle,
  SystemMaterialParams
} from '@kit.UIDesignKit';
import { ThemeType } from '../Managers/ThemeManager';

const HDS_BAR_SIDE_GUARD: number = 8;
const HDS_GLASS_BAR_OPACITY_RATIO: number = 0.72;
const HDS_GLASS_BAR_MAX_OPACITY: number = 0.82;
const HDS_GLASS_BAR_MIN_OPACITY: number = 0.56;
const HDS_GLASS_LIGHT_HIGHLIGHT_OPACITY: number = 0.42;
const HDS_GLASS_DARK_HIGHLIGHT_OPACITY: number = 0.22;
const HDS_GLOBAL_MATERIAL_LEVEL: number = -1;

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
  @StorageProp('visual_effects_effective_material_level') effectiveMaterialLevel: number = 10;
  @StorageProp('userTheme_hdsTabOpacityRatio') hdsTabOpacityRatio: number = HDS_GLASS_BAR_OPACITY_RATIO;
  @StorageProp('userTheme_hdsTabMinOpacity') hdsTabMinOpacity: number = HDS_GLASS_BAR_MIN_OPACITY;
  @StorageProp('userTheme_hdsTabMaxOpacity') hdsTabMaxOpacity: number = HDS_GLASS_BAR_MAX_OPACITY;
  @StorageProp('userTheme_hdsTabLightHighlightOpacity') hdsTabLightHighlightOpacity: number = HDS_GLASS_LIGHT_HIGHLIGHT_OPACITY;
  @StorageProp('userTheme_hdsTabDarkHighlightOpacity') hdsTabDarkHighlightOpacity: number = HDS_GLASS_DARK_HIGHLIGHT_OPACITY;
  @StorageProp('userTheme_hdsTabMaterialLevel') hdsTabMaterialLevel: number = HDS_GLOBAL_MATERIAL_LEVEL;
  @StorageProp('userTheme_hdsTabBlurEnabled') hdsTabBlurEnabled: boolean = true;
  @StorageProp('userTheme_hdsTabSideMargin') hdsTabSideMargin: number = HDS_BAR_SIDE_GUARD;
  @StorageProp('userTheme_hdsTabBottomMargin') hdsTabBottomMargin: number = 0;
  onChangeCallback: (actualIndex: number) => void = (): void => {};
  longPressCallback: (tabIndex: number) => void = (): void => {};
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

  private getSafeSelectedIndex(index: number): number {
    const tabCount: number = this.visibleTabConfigs.length;
    if (tabCount <= 0) {
      return 0;
    }
    if (index >= 0 && index < tabCount) {
      return index;
    }
    return 0;
  }

  private updateVisualSelectedIndex(index: number): number {
    const safeIndex: number = this.getSafeSelectedIndex(index);
    if (this.visualSelectedIndex !== safeIndex) {
      this.visualSelectedIndex = safeIndex;
    }
    return safeIndex;
  }

  private isTabSelected(actualIndex: number): boolean {
    return this.visualSelectedIndex === actualIndex;
  }

  private getActiveColor(): string {
    return this.themeType === ThemeType.DARK ? '#6EC8FF' : '#0A84FF';
  }

  private getInactiveColor(): string {
    return this.themeType === ThemeType.DARK ? '#D6DEE8' : '#4B5563';
  }

  private getNavigationColor(selected: boolean): string {
    return selected ? this.getActiveColor() : this.getInactiveColor();
  }

  private getSystemIcon(config: HdsBottomBarTabConfig): Resource {
    if (this.isPrivacyMode && config.index === 1) {
      return $r('sys.symbol.lock');
    }
    if (config.systemIcon) {
      return config.systemIcon;
    }
    return $r('sys.symbol.books_vertical_fill');
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

  private getBlurStrategy(): BlurStrategy {
    return this.hdsTabBlurEnabled ? BlurStrategy.ENABLE : BlurStrategy.DISABLE;
  }

  private getBarSideMargin(): number {
    return Math.max(0, Math.min(24, this.hdsTabSideMargin));
  }

  private getBarBottomMargin(): number {
    return Math.max(-8, Math.min(16, this.hdsTabBottomMargin));
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

  build(): void {
    Stack({ alignContent: Alignment.Center }) {
      HdsTabs({
        controller: this.controller,
        index: this.visualSelectedIndex
      }) {
        ForEach(this.visibleTabConfigs, (cfg: HdsBottomBarTabConfig, idx: number): void => {
          TabContent() {
          }
          .backgroundColor(Color.Transparent)
          .tabBar(this.buildTabBarItem(cfg, idx))
        }, (cfg: HdsBottomBarTabConfig, _idx: number): string => `hds_tab_${cfg.index}`)
      }
      .width('100%')
      .height(56)
      .barPosition(BarPosition.End)
      .barMode(BarMode.Fixed)
      .barOverlap(true)
      .divider(this.buildDividerStyle())
      .barBackgroundColor(Color.Transparent)
      .barBackgroundBlurStyle(BlurStyle.NONE)
      .barBackgroundStyle(this.buildTransparentTabsBackgroundStyle())
      .blurStrategy(this.getBlurStrategy())
      .barFloatingStyle(this.buildFloatingStyle())
      .onSelected((index: number): void => {
        this.updateVisualSelectedIndex(index);
      })
      .onChange((index: number): void => {
        const safeIndex: number = this.updateVisualSelectedIndex(index);
        if (!this.isSyncingIndex && this.selectedIndex !== safeIndex) {
          this.onChangeCallback(safeIndex);
        }
      })
    }
    .width('100%')
    .height(56)
    .backgroundColor(Color.Transparent)
  }

  @Builder
  buildTabBarItem(config: HdsBottomBarTabConfig, actualIndex: number): void {
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
      .opacity(this.isTabSelected(actualIndex) ? 1 : (this.themeType === ThemeType.DARK ? 0.84 : 0.88))

      Text(config.title)
        .fontSize(12)
        .fontColor(this.getNavigationColor(this.isTabSelected(actualIndex)))
        .fontWeight(this.isTabSelected(actualIndex) ? FontWeight.Medium : FontWeight.Normal)
        .maxLines(1)
        .textAlign(TextAlign.Center)
    }
    .width('100%')
    .height(44)
    .justifyContent(FlexAlign.Center)
    .padding({ left: 4, right: 4 })
    .gesture(
      LongPressGesture({ repeat: false, duration: 500 })
        .onAction((): void => {
          this.longPressCallback(config.index);
        })
    )
  }
}
