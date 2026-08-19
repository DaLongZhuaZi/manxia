// 文件路径: entry/src/main/ets/pages/HelpCenterPage.ets
/**
 * 帮助中心页面
 * 显示所有帮助文档的入口，支持搜索功能
 * 数据来源：HelpData.ets 集中管理
 */

import { HdsNavDestination, HdsNavDestinationAttribute, ScrollEffectType } from '@kit.UIDesignKit';
import { LengthMetrics, UIContext, promptAction } from '@kit.ArkUI';
import { ThemeAwareState, ThemeAwareHelper } from '../Framework/Components/ThemeAware';
import { ThemeManager, ThemeType } from '../Framework/Managers/ThemeManager';
import { FontAwareHelper, FontAwareState } from '../Framework/Components/FontAware';
import { logger } from 'manxia_core/src/main/ets/Utils/Logger';
import { getHelpPanelManagerV2 } from '../Framework/Components/HelpPanelV2';
import { HELP_ITEMS_DATA, HELP_CATEGORIES, HelpItemData } from 'manxia_core/src/main/ets/Data/HelpData';
import { AppGuideFlowId, AppGuideFlowSummary, AppGuideManager } from '../Framework/Managers/AppGuideManager';
import { SettingsImmersiveTitleBar } from './settings/SettingsImmersiveTitleBar';
import { SettingsPageTitleBarManager } from './settings/SettingsPageTitleBarManager';
import { GlobalBackgroundLayerMode } from '../Framework/Components/GlobalBackgroundLayer';
import { SharedPageBackgroundLayer } from '../Framework/Components/SharedPageBackgroundLayer';
import { SettingsPanelSurfaceHelper } from './settings/SettingsPanelSurfaceHelper';

const TAG = 'HelpCenterPage';
const TITLE_BAR_HEIGHT_MINI: number = 56;

interface NavDestinationContext {
  pathStack: NavPathStack;
}

// 图标映射表：根据帮助项 id 返回对应的系统图标
function getHelpItemIcon(id: string): Resource {
  switch (id) {
    case 'quick_start':
      return $r('sys.symbol.play_circle');
    case 'reader_guide':
      return $r('sys.symbol.book_open_fill');
    case 'library_management':
      return $r('sys.symbol.book_open_fill');
    case 'file_import':
      return $r('sys.symbol.folder_badge_plus');
    case 'download_sync':
      return $r('sys.symbol.square_and_arrow_down');
    case 'backup_restore':
      return $r('sys.symbol.arrow_2_circlepath');
    case 'storage_management':
      return $r('sys.symbol.externaldrive');
    case 'manga_settings':
      return $r('sys.symbol.slider_horizontal_2_square');
    case 'ebook_settings':
      return $r('sys.symbol.text_book_closed');
    case 'source_settings':
      return $r('sys.symbol.slider_horizontal_2_square');
    case 'source_guide':
      return $r('sys.symbol.picture');
    case 'faq':
      return $r('sys.symbol.questionmark_circle');
    default:
      return $r('sys.symbol.doc_plaintext');
  }
}

@Component
export struct HelpCenterPage {
  @State pathStack: NavPathStack = new NavPathStack();
  @State themeState: ThemeAwareState = new ThemeAwareState();
  @State fontState: FontAwareState = new FontAwareState();
  @StorageLink('appFontFamily') appFontFamily: string = 'HarmonyOS Sans';
  @StorageProp('statusBarHeight') statusBarHeight: number = 0;
  @StorageProp('navigationBarHeight') navigationBarHeight: number = 0;
  @StorageLink('source_features_enabled') sourceFeaturesEnabled: boolean = false;
  private uiContext: UIContext | null = null;
  private scroller: Scroller = new Scroller();

  // 搜索相关状态
  @State searchKeyword: string = '';
  // 入场动画状态
  @State private pageReady: boolean = false;
  @State private guideFlows: AppGuideFlowSummary[] = [];
  private appGuideManager: AppGuideManager = AppGuideManager.getInstance();

  aboutToAppear(): void {
    ThemeAwareHelper.initializeThemeAware(
      TAG,
      this.themeState,
      (newTheme: ThemeType) => {
        logger.info(TAG, `主题切换到: ${newTheme}`);
      },
      (newState: ThemeAwareState) => { this.themeState = newState; }
    );
    FontAwareHelper.initializeFontAware(
      TAG,
      this.fontState,
      (newState: FontAwareState) => {
        this.fontState = newState;
      }
    );
    void this.appGuideManager.initialize().then(() => {
      this.guideFlows = this.appGuideManager.getHelpCenterFlowSummaries();
    });
    // 延迟触发入场动画
    setTimeout(() => {
      this.getUIContext().animateTo({ duration: 400, curve: Curve.EaseOut }, () => {
        this.pageReady = true;
      });
    }, 50);
  }

  aboutToDisappear(): void {
    ThemeAwareHelper.cleanupThemeAware(TAG);
    FontAwareHelper.cleanupFontAware(TAG);
  }

  /**
   * 获取过滤后的帮助项列表
   */
  private getAvailableHelpItems(): HelpItemData[] {
    if (this.sourceFeaturesEnabled) {
      return HELP_ITEMS_DATA;
    }
    return HELP_ITEMS_DATA.filter((item: HelpItemData) => item.category !== '图源');
  }

  private getFilteredItems(): HelpItemData[] {
    const keyword = this.searchKeyword.trim().toLowerCase();
    const availableItems = this.getAvailableHelpItems();
    if (keyword.length === 0) {
      return availableItems;
    }
    return availableItems.filter((item: HelpItemData) => {
      return item.title.toLowerCase().includes(keyword) ||
        item.description.toLowerCase().includes(keyword) ||
        item.category.toLowerCase().includes(keyword) ||
        item.content.toLowerCase().includes(keyword);
    });
  }

  /**
   * 获取过滤后存在条目的分类列表
   */
  private getVisibleCategories(): string[] {
    const filteredItems = this.getFilteredItems();
    const categories = this.sourceFeaturesEnabled
      ? HELP_CATEGORIES
      : HELP_CATEGORIES.filter((category: string) => category !== '图源');
    return categories.filter((category: string) => {
      return filteredItems.some((item: HelpItemData) => item.category === category);
    });
  }

  /**
   * 获取指定分类下的过滤后条目
   */
  private getItemsForCategory(category: string): HelpItemData[] {
    return this.getFilteredItems().filter((item: HelpItemData) => item.category === category);
  }

  private getFilteredGuideFlows(): AppGuideFlowSummary[] {
    const keyword = this.searchKeyword.trim().toLowerCase();
    const visibleGuideFlows = this.sourceFeaturesEnabled
      ? this.guideFlows
      : this.guideFlows.filter((item: AppGuideFlowSummary) =>
          !item.title.includes('图源') &&
          !item.title.includes('书源') &&
          !item.description.includes('图源') &&
          !item.description.includes('书源')
        );
    if (keyword.length === 0) {
      return visibleGuideFlows;
    }
    return visibleGuideFlows.filter((item: AppGuideFlowSummary) => {
      return item.title.toLowerCase().includes(keyword) ||
        item.description.toLowerCase().includes(keyword);
    });
  }

  private async replayGuideFlow(flow: AppGuideFlowSummary): Promise<void> {
    try {
      await this.appGuideManager.startFlow(flow.id, 'manual');
      if (flow.id === AppGuideFlowId.MAIN_MENU_CORE) {
        if (this.pathStack.size() > 0) {
          this.pathStack.pop();
        }
        return;
      }

      const globalStack = AppStorage.get<NavPathStack>('GlobalNavStack');
      if (!globalStack || !flow.helpCenterRouteName || flow.helpCenterRouteName.length <= 0) {
        this.getUIContext().getPromptAction().showToast({
          message: '当前引导需要在对应页面内重播',
          duration: 1800
        });
        return;
      }
      globalStack.pushPathByName(flow.helpCenterRouteName, undefined);
    } catch (error) {
      logger.error(TAG, `重播引导失败: ${String(error)}`);
      this.getUIContext().getPromptAction().showToast({
        message: '重播引导失败',
        duration: 1800
      });
    }
  }

  /**
   * 显示帮助内容
   */
  private showHelpContent(item: HelpItemData): void {
    getHelpPanelManagerV2().showInlineHelp(item.title, item.content);
  }

  @Builder
  buildSearchBar() {
    Row({ space: 8 }) {
      SymbolGlyph($r('sys.symbol.magnifyingglass'))
        .fontSize(20)
        .fontColor([ThemeAwareHelper.getTestManagementThemedColor('text_muted', this.themeState.currentTheme)])

      TextInput({ placeholder: '搜索帮助内容...', text: this.searchKeyword })
        .layoutWeight(1)
        .height(36)
        .fontSize(14)
        .fontFamily(this.appFontFamily)
        .backgroundColor(Color.Transparent)
        .placeholderColor(ThemeAwareHelper.getTestManagementThemedColor('text_muted', this.themeState.currentTheme))
        .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_primary', this.themeState.currentTheme))
        .onChange((value: string) => {
          this.searchKeyword = value;
        })

      if (this.searchKeyword.length > 0) {
        SymbolGlyph($r('sys.symbol.xmark_circle_fill'))
          .fontSize(18)
          .fontColor([ThemeAwareHelper.getTestManagementThemedColor('text_muted', this.themeState.currentTheme)])
          .onClick(() => {
            this.searchKeyword = '';
          })
      }
    }
    .width('100%')
    .height(48)
    .padding({ left: 14, right: 14 })
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
  buildHelpItem(item: HelpItemData) {
    Row({ space: 12 }) {
      // 图标
      Column() {
        SymbolGlyph(getHelpItemIcon(item.id))
          .fontSize(24)
          .fontColor([ThemeAwareHelper.getTestManagementThemedColor('accent_primary', this.themeState.currentTheme)])
      }
      .width(48)
      .height(48)
      .justifyContent(FlexAlign.Center)
      .backgroundColor(ThemeAwareHelper.getTestManagementThemedColor('comp_background_tertiary', this.themeState.currentTheme))
      .borderRadius(12)

      // 文字内容
      Column({ space: 4 }) {
        Text(item.title)
          .fontSize(16)
          .fontWeight(FontWeight.Medium)
          .fontFamily(this.appFontFamily)
          .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_primary', this.themeState.currentTheme))
        Text(item.description)
          .fontSize(13)
          .fontFamily(this.appFontFamily)
          .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_secondary', this.themeState.currentTheme))
          .maxLines(2)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
      }
      .layoutWeight(1)
      .alignItems(HorizontalAlign.Start)

      // 箭头
      SymbolGlyph($r('sys.symbol.chevron_right'))
        .fontSize(16)
        .fontColor([ThemeAwareHelper.getTestManagementThemedColor('text_muted', this.themeState.currentTheme)])
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
    .opacity(this.pageReady ? 1 : 0)
    .translate({ y: this.pageReady ? 0 : 12 })
    .animation({ duration: 350, curve: Curve.EaseOut })
    .scale({ x: 1, y: 1 })
    .stateStyles({
      pressed: {
        .scale({ x: 0.97, y: 0.97 })
        .opacity(0.9)
      }
    })
    .transition(TransitionEffect.OPACITY.animation({ duration: 250, curve: Curve.EaseOut })
      .combine(TransitionEffect.translate({ y: 6 })))
    .onClick(() => {
      this.showHelpContent(item);
    })
  }

  @Builder
  buildCategorySection(category: string) {
    Column({ space: 12 }) {
      // 分类标题
      Text(category)
        .fontSize(14)
        .fontWeight(FontWeight.Medium)
        .fontFamily(this.appFontFamily)
        .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_secondary', this.themeState.currentTheme))
        .width('100%')
        .padding({ left: 4 })
        .transition(TransitionEffect.OPACITY.animation({ duration: 250, curve: Curve.EaseOut })
          .combine(TransitionEffect.translate({ y: 6 })))

      // 帮助项列表
      ForEach(this.getItemsForCategory(category), (item: HelpItemData) => {
        this.buildHelpItem(item)
      }, (item: HelpItemData) => item.id)
    }
    .width('100%')
    .transition(TransitionEffect.OPACITY.animation({ duration: 300, curve: Curve.EaseOut })
      .combine(TransitionEffect.translate({ y: 8 })))
  }

  @Builder
  buildGuideReplayItem(item: AppGuideFlowSummary) {
    Column({ space: 10 }) {
      Row({ space: 12 }) {
        Column() {
          SymbolGlyph($r('sys.symbol.play_circle'))
            .fontSize(24)
            .fontColor([ThemeAwareHelper.getTestManagementThemedColor('accent_primary', this.themeState.currentTheme)])
        }
        .width(48)
        .height(48)
        .justifyContent(FlexAlign.Center)
        .backgroundColor(ThemeAwareHelper.getTestManagementThemedColor('comp_background_tertiary', this.themeState.currentTheme))
        .borderRadius(12)

        Column({ space: 4 }) {
          Text(item.title)
            .fontSize(16)
            .fontWeight(FontWeight.Medium)
            .fontFamily(this.appFontFamily)
            .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_primary', this.themeState.currentTheme))
          Text(item.description)
            .fontSize(13)
            .fontFamily(this.appFontFamily)
            .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_secondary', this.themeState.currentTheme))
            .maxLines(2)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
        }
        .layoutWeight(1)
        .alignItems(HorizontalAlign.Start)
      }
      .width('100%')

      Button('重播引导')
        .width('100%')
        .height(34)
        .fontSize(13)
        .fontFamily(this.appFontFamily)
        .fontColor(Color.White)
        .backgroundColor(ThemeAwareHelper.getTestManagementThemedColor('accent_primary', this.themeState.currentTheme))
        .borderRadius(10)
        .onClick(() => {
          void this.replayGuideFlow(item);
        })
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
    .opacity(this.pageReady ? 1 : 0)
    .translate({ y: this.pageReady ? 0 : 12 })
    .animation({ duration: 350, curve: Curve.EaseOut })
  }

  @Builder
  buildGuideReplaySection() {
    if (this.getFilteredGuideFlows().length > 0) {
      Column({ space: 12 }) {
        Text('引导回放')
          .fontSize(14)
          .fontWeight(FontWeight.Medium)
          .fontFamily(this.appFontFamily)
          .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_secondary', this.themeState.currentTheme))
          .width('100%')
          .padding({ left: 4 })

        ForEach(this.getFilteredGuideFlows(), (item: AppGuideFlowSummary) => {
          this.buildGuideReplayItem(item)
        }, (item: AppGuideFlowSummary) => item.id)
      }
      .width('100%')
      .transition(TransitionEffect.OPACITY.animation({ duration: 300, curve: Curve.EaseOut })
        .combine(TransitionEffect.translate({ y: 8 })))
    }
  }

  @Builder
  buildEmptySearchResult() {
    Column({ space: 16 }) {
      SymbolGlyph($r('sys.symbol.magnifyingglass'))
        .fontSize(48)
        .fontColor([ThemeAwareHelper.getTestManagementThemedColor('text_muted', this.themeState.currentTheme)])

      Text('未找到相关帮助内容')
        .fontSize(16)
        .fontFamily(this.appFontFamily)
        .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_secondary', this.themeState.currentTheme))

      Text('尝试使用其他关键词搜索')
        .fontSize(13)
        .fontFamily(this.appFontFamily)
        .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_muted', this.themeState.currentTheme))
    }
    .width('100%')
    .padding({ left: 20, right: 20, top: 56, bottom: 56 })
    .justifyContent(FlexAlign.Center)
    .alignItems(HorizontalAlign.Center)
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
    .transition(TransitionEffect.OPACITY.animation({ duration: 300, curve: Curve.EaseOut })
      .combine(TransitionEffect.scale({ x: 0.95, y: 0.95 })))
  }

  build() {
    HdsNavDestination() {
      Stack() {
        // 背景层
        SharedPageBackgroundLayer({
          defaultBackgroundColor: ThemeAwareHelper.getTestManagementThemedColor('background', this.themeState.currentTheme),
          mode: GlobalBackgroundLayerMode.IMMERSIVE
        })
          .width('100%')
          .height('100%')
          .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.TOP, SafeAreaEdge.BOTTOM])

        // 内容层
        Column() {
          Blank().height(SettingsPageTitleBarManager.getContentTopPadding(this.statusBarHeight))

          Scroll(this.scroller) {
            Column({ space: 24 }) {
              // 搜索栏（带入场动画）
              Column() {
                this.buildSearchBar()
              }
              .opacity(this.pageReady ? 1 : 0)
              .translate({ y: this.pageReady ? 0 : -8 })
              .animation({ duration: 300, curve: Curve.EaseOut })

              // 搜索结果统计
              if (this.searchKeyword.length > 0) {
                Text(`找到 ${this.getFilteredItems().length} 条相关内容`)
                  .fontSize(13)
                  .fontFamily(this.appFontFamily)
                  .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_muted', this.themeState.currentTheme))
                  .width('100%')
                  .padding({ left: 4 })
                  .transition(TransitionEffect.OPACITY.animation({ duration: 200, curve: Curve.EaseOut }))
              }

              // 按分类动态渲染
              if (this.getFilteredItems().length > 0) {
                ForEach(this.getVisibleCategories(), (category: string) => {
                  this.buildCategorySection(category)
                }, (category: string) => category)
              } else {
                this.buildEmptySearchResult()
              }

              this.buildGuideReplaySection()

              Blank().height(20 + this.navigationBarHeight)
            }
            .width('100%')
            .padding({ left: 16, right: 16, top: 8 })
          }
          .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.TOP, SafeAreaEdge.BOTTOM])
          .layoutWeight(1)
          .scrollBar(BarState.Auto)
          .edgeEffect(EdgeEffect.Spring)
        }
        .width('100%')
        .height('100%')
        .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.TOP, SafeAreaEdge.BOTTOM])

        SettingsImmersiveTitleBar({
          themeState: this.themeState,
          title: '帮助中心',
          appFontFamily: this.appFontFamily,
          pathStack: this.pathStack
        })
      }
    }
    .hideTitleBar(true)
    .ignoreLayoutSafeArea([LayoutSafeAreaType.SYSTEM], [LayoutSafeAreaEdge.TOP, LayoutSafeAreaEdge.BOTTOM])
    /*
    .titleBar({
      padding: {
        start: LengthMetrics.vp(16),
        end: LengthMetrics.vp(16)
      },
      style: {
        originalStyle: {
          backgroundStyle: { backgroundColor: ThemeAwareHelper.getTestManagementThemedColor('panel_background', this.themeState.currentTheme) },
          contentStyle: {
            titleStyle: { mainTitleColor: ThemeAwareHelper.getTestManagementThemedColor('text_primary', this.themeState.currentTheme) },
            backIconStyle: { backgroundColor: ThemeAwareHelper.getTestManagementThemedColor('comp_background_tertiary', this.themeState.currentTheme), iconColor: ThemeAwareHelper.getTestManagementThemedColor('icon_primary', this.themeState.currentTheme) }
          }
        }
      },
      content: {
        title: { mainTitle: '帮助中心' }
      }
    })
    */
    .onReady((context: NavDestinationContext) => {
      this.pathStack = context.pathStack;
      this.uiContext = this.getUIContext();
      ThemeAwareHelper.initializeThemeAware(
        TAG,
        this.themeState,
        (newTheme: ThemeType) => {},
        (newState: ThemeAwareState) => { this.themeState = newState; }
      );
    })
    .backgroundColor(Color.Transparent)
  }
}
