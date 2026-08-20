/**
 * RSS 收藏页。
 * 独立展示已收藏条目，支持来源筛选、搜索和跳转详情。
 */

import { HdsNavDestination } from '@kit.UIDesignKit';
import { promptAction } from '@kit.ArkUI';
import { common } from '@kit.AbilityKit';
import { logger } from 'manxia_core/src/main/ets/Utils/Logger';
import { PageLifecycleManager } from 'manxia_core/src/main/ets/Framework/Lifecycle/index';
import { ThemeAwareState, ThemeAwareHelper } from 'manxia_theme/src/main/ets/Framework/Components/ThemeAware';
import { ThemeType } from 'manxia_theme/src/main/ets/Framework/Managers/ThemeManager';
import { FontAwareHelper, FontAwareState } from '../Framework/Components/FontAware';
import { RssFeedItem, RssFetchResult, RssSubscriptionSource } from 'manxia_core/src/main/ets/Models/RssSubscriptionModels';
import { getRssSubscriptionInitializer } from '../Framework/Rss/RssSubscriptionInitializer';
import { getRssSubscriptionManager, RssSubscriptionManager } from '../Framework/Rss/RssSubscriptionManager';
import { RssSubscriptionDetailPageParams } from './RssSubscriptionDetailPage';
import { SettingsImmersiveTitleBar } from './settings/SettingsImmersiveTitleBar';
import { SettingsImmersiveTitleActionItem, SettingsPageTitleBarManager } from './settings/SettingsPageTitleBarManager';
import { GlobalBackgroundLayerMode } from 'manxia_theme/src/main/ets/Framework/Components/GlobalBackgroundLayer';
import { SharedPageBackgroundLayer } from '../Framework/Components/SharedPageBackgroundLayer';
import { SettingsPanelSurfaceHelper } from './settings/SettingsPanelSurfaceHelper';

const TAG = 'RssFavoritesPage';

@Component
export struct RssFavoritesPage {
  @Consume('NavPathStack') pathStack: NavPathStack;

  @State themeState: ThemeAwareState = new ThemeAwareState();
  @State fontState: FontAwareState = new FontAwareState();
  @StorageLink('appFontFamily') appFontFamily: string = 'HarmonyOS Sans';
  @StorageProp('statusBarHeight') statusBarHeight: number = 0;
  @StorageProp('navigationBarHeight') navigationBarHeight: number = 0;
  private readonly componentId: string = `RssFavoritesPage_${Date.now()}`;

  @State allItems: RssFeedItem[] = [];
  @State items: RssFeedItem[] = [];
  @State sources: RssSubscriptionSource[] = [];
  @State isLoading: boolean = true;
  @State showSearchBar: boolean = false;
  @State searchKeyword: string = '';
  @State selectedSourceId: string = '';

  private readonly manager: RssSubscriptionManager = getRssSubscriptionManager();
  private lifecycle = new PageLifecycleManager('RssFavoritesPage', { enableDebug: true });
  private loadVersion: number = 0;

  aboutToAppear(): void {
    ThemeAwareHelper.initializeThemeAware(this.componentId, this.themeState, (_theme: ThemeType) => {
    });
    FontAwareHelper.initializeFontAware(
      this.componentId,
      this.fontState,
      (newState: FontAwareState) => {
        this.fontState = newState;
      }
    );
    this.initializeAndLoad();
  }

  aboutToDisappear(): void {
    this.lifecycle.destroy();
    ThemeAwareHelper.cleanupThemeAware(this.componentId);
    FontAwareHelper.cleanupFontAware(this.componentId);
  }

  onPageShow(): void {
    if (!this.isLoading) {
      this.loadData();
      this.triggerAutoDueRefresh();
    }
  }

  private async initializeAndLoad(): Promise<void> {
    this.isLoading = true;
    try {
      logger.info(TAG, '开始初始化 RSS 收藏页');
      const context = (this.getUIContext().getHostContext() as common.UIAbilityContext) as common.UIAbilityContext;
      await getRssSubscriptionInitializer().initialize(context);
      await this.loadData();
      this.triggerAutoDueRefresh();
      logger.info(TAG, 'RSS 收藏页初始化完成');
    } catch (error) {
      logger.error(TAG, `RSS 收藏页初始化失败: ${String(error)}`);
      this.getUIContext().getPromptAction().showToast({ message: `初始化失败: ${String(error)}` });
    }
    this.isLoading = false;
  }

  private triggerAutoDueRefresh(): void {
    this.manager.maybeRefreshDueSources('RSS收藏页进入').then((results: RssFetchResult[]) => {
      if (results.length > 0) {
        logger.info(TAG, `自动到期刷新完成并更新收藏数据: 更新源=${results.length}`);
        this.loadData();
      }
    }).catch((error: Object | string | number | boolean | null | undefined) => {
      logger.warn(TAG, `触发自动到期刷新失败: ${String(error)}`);
    });
  }

  private async loadData(): Promise<void> {
    const currentVersion = ++this.loadVersion;
    try {
      this.sources = await this.manager.getAllSources(true);
      const list = await this.manager.queryItems({
        sourceId: this.selectedSourceId || undefined,
        starredOnly: true,
        limit: 500
      });
      if (currentVersion !== this.loadVersion) {
        logger.debug(TAG, `忽略过期收藏列表结果: version=${currentVersion}, current=${this.loadVersion}`);
        return;
      }
      this.allItems = list;
      this.applySearchFilter();
      logger.info(TAG, `加载 RSS 收藏完成: 条目=${list.length}`);
    } catch (error) {
      logger.error(TAG, `加载 RSS 收藏失败: ${String(error)}`);
      this.getUIContext().getPromptAction().showToast({ message: '加载收藏失败' });
    }
  }

  private applySearchFilter(): void {
    const keyword = this.searchKeyword.trim().toLowerCase();
    if (keyword.length === 0) {
      this.items = this.allItems.filter(() => true);
      return;
    }
    this.items = this.allItems.filter((item: RssFeedItem) => {
      const title = item.title.toLowerCase();
      const sourceName = item.sourceName.toLowerCase();
      const description = (item.description || '').toLowerCase();
      return title.includes(keyword) || sourceName.includes(keyword) || description.includes(keyword);
    });
  }

  private chooseSource(sourceId: string): void {
    this.selectedSourceId = sourceId;
    logger.info(TAG, `切换收藏来源过滤: ${sourceId.length > 0 ? sourceId : '全部来源'}`);
    this.loadData();
  }

  private formatTime(timestamp: number): string {
    if (timestamp <= 0) {
      return '未知时间';
    }
    const date = new Date(timestamp);
    const year = date.getFullYear();
    const month = `${date.getMonth() + 1}`.padStart(2, '0');
    const day = `${date.getDate()}`.padStart(2, '0');
    const hour = `${date.getHours()}`.padStart(2, '0');
    const minute = `${date.getMinutes()}`.padStart(2, '0');
    return `${year}-${month}-${day} ${hour}:${minute}`;
  }

  private updateLocalFavoriteItemState(itemId: string, isRead: boolean, isStarred: boolean): void {
    const nextItems: RssFeedItem[] = [];
    for (let i = 0; i < this.allItems.length; i++) {
      const current = this.allItems[i];
      if (current.id === itemId) {
        current.isRead = isRead;
        current.isStarred = isStarred;
      }
      if (!current.isStarred) {
        continue;
      }
      nextItems.push(current);
    }
    this.allItems = nextItems;
    this.applySearchFilter();
  }

  private async toggleRead(item: RssFeedItem): Promise<void> {
    try {
      const nextRead = !item.isRead;
      const currentStarred = item.isStarred;
      await this.manager.setItemRead(item.id, nextRead);
      this.updateLocalFavoriteItemState(item.id, nextRead, currentStarred);
    } catch (error) {
      logger.error(TAG, `切换已读状态失败: ${String(error)}`);
      this.getUIContext().getPromptAction().showToast({ message: `操作失败: ${String(error)}` });
    }
  }

  private async toggleStar(item: RssFeedItem): Promise<void> {
    try {
      const nextStarred = !item.isStarred;
      const currentRead = item.isRead;
      await this.manager.setItemStarred(item.id, nextStarred);
      this.updateLocalFavoriteItemState(item.id, currentRead, nextStarred);
    } catch (error) {
      logger.error(TAG, `切换收藏状态失败: ${String(error)}`);
      this.getUIContext().getPromptAction().showToast({ message: `操作失败: ${String(error)}` });
    }
  }

  private openDetail(item: RssFeedItem): void {
    const params: RssSubscriptionDetailPageParams = { itemId: item.id };
    this.pathStack.pushPathByName('RssSubscriptionDetailPage', params);
  }

  private openSubscriptionPage(): void {
    this.pathStack.pushPathByName('RssSubscriptionPage', null);
  }

  private toggleSearchBar(): void {
    this.showSearchBar = !this.showSearchBar;
    if (!this.showSearchBar) {
      this.searchKeyword = '';
      this.applySearchFilter();
    }
  }

  private getTitleBarActions(): SettingsImmersiveTitleActionItem[] {
    return [
      {
        id: 'search',
        label: '搜索',
        symbol: $r('sys.symbol.magnifyingglass'),
        onClick: () => {
          this.toggleSearchBar();
        }
      },
      {
        id: 'refresh',
        label: '刷新',
        symbol: $r('sys.symbol.arrow_clockwise'),
        enabled: !this.isLoading,
        onClick: () => {
          void this.loadData();
        }
      }
    ];
  }

  @Builder
  private buildSourceButton(title: string, selected: boolean, onClick: () => void) {
    Button(title)
      .height(30)
      .fontSize(11)
      .fontFamily(this.appFontFamily)
      .backgroundColor(selected
        ? ThemeAwareHelper.getTestManagementThemedColor('accent_primary', this.themeState.currentTheme)
        : ThemeAwareHelper.getTestManagementThemedColor('panel_background', this.themeState.currentTheme))
      .fontColor(selected
        ? '#FFFFFF'
        : ThemeAwareHelper.getTestManagementThemedColor('text_primary', this.themeState.currentTheme))
      .onClick(() => {
        onClick();
      })
  }

  @Builder
  private buildSearchBar() {
    Row() {
      TextInput({ placeholder: '搜索收藏条目...', text: this.searchKeyword })
        .layoutWeight(1)
        .height(40)
        .backgroundColor(ThemeAwareHelper.getTestManagementThemedColor('panel_background', this.themeState.currentTheme))
        .borderRadius(20)
        .padding({ left: 16, right: 16 })
        .onChange((value: string) => {
          this.searchKeyword = value;
          this.applySearchFilter();
        })

      if (this.searchKeyword.trim().length > 0) {
        Text('取消')
          .fontSize(14)
          .fontFamily(this.appFontFamily)
          .fontColor(ThemeAwareHelper.getTestManagementThemedColor('accent_primary', this.themeState.currentTheme))
          .margin({ left: 12 })
          .onClick(() => {
            this.searchKeyword = '';
            this.applySearchFilter();
          })
      }
    }
    .width('100%')
    .padding({ left: 16, right: 16, top: 8, bottom: 8 })
    .margin({ left: 12, right: 12 })
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
  private buildFilterBar() {
    Scroll() {
      Row({ space: 8 }) {
        this.buildSourceButton('全部来源', this.selectedSourceId.length === 0, () => {
          this.chooseSource('');
        })
        ForEach(this.sources, (source: RssSubscriptionSource) => {
          this.buildSourceButton(source.name, this.selectedSourceId === source.id, () => {
            this.chooseSource(source.id);
          })
        }, (source: RssSubscriptionSource) => source.id)
      }
      .padding({ left: 16, right: 16, top: 8, bottom: 10 })
    }
    .width('100%')
    .scrollable(ScrollDirection.Horizontal)
    .scrollBar(BarState.Off)
    .margin({ left: 12, right: 12, bottom: 8 })
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
  private buildItemCard(item: RssFeedItem) {
    Column({ space: 8 }) {
      Text(item.title)
        .width('100%')
        .fontSize(15)
        .fontWeight(FontWeight.Medium)
        .fontFamily(this.appFontFamily)
        .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_primary', this.themeState.currentTheme))
        .maxLines(2)

      Text(`${item.sourceName} | ${this.formatTime(item.pubDate)}`)
        .width('100%')
        .fontSize(11)
        .fontFamily(this.appFontFamily)
        .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_secondary', this.themeState.currentTheme))

      if ((item.description || '').length > 0) {
        Text(item.description || '')
          .width('100%')
          .fontSize(12)
          .fontFamily(this.appFontFamily)
          .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_secondary', this.themeState.currentTheme))
          .maxLines(3)
      }

      Row({ space: 8 }) {
        Button(item.isRead ? '标未读' : '标已读')
          .height(30)
          .fontSize(12)
          .fontFamily(this.appFontFamily)
          .backgroundColor(ThemeAwareHelper.getTestManagementThemedColor('panel_background', this.themeState.currentTheme))
          .borderRadius(16)
          .onClick(() => {
            this.toggleRead(item);
          })

        Button(item.isStarred ? '取消收藏' : '收藏')
          .height(30)
          .fontSize(12)
          .fontFamily(this.appFontFamily)
          .backgroundColor(ThemeAwareHelper.getTestManagementThemedColor('panel_background', this.themeState.currentTheme))
          .borderRadius(16)
          .onClick(() => {
            this.toggleStar(item);
          })

        Button('详情')
          .height(30)
          .fontSize(12)
          .fontFamily(this.appFontFamily)
          .fontColor('#FFFFFF')
          .backgroundColor(ThemeAwareHelper.getTestManagementThemedColor('accent_primary', this.themeState.currentTheme))
          .borderRadius(16)
          .onClick(() => {
            this.openDetail(item);
          })
      }
      .width('100%')
    }
    .width('100%')
    .padding({ left: 12, right: 12, top: 12, bottom: 12 })
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
    .margin({ bottom: 8 })
    .opacity(item.isRead ? 0.85 : 1)
  }

  build() {
    HdsNavDestination() {
      Stack() {
        SharedPageBackgroundLayer({
          defaultBackgroundColor: ThemeAwareHelper.getTestManagementThemedColor('background', this.themeState.currentTheme),
          mode: GlobalBackgroundLayerMode.IMMERSIVE
        })
          .width('100%')
          .height('100%')
          .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.TOP, SafeAreaEdge.BOTTOM])
          .animation(ThemeAwareHelper.getThemeTransitionAnimation())

        Column() {
          Blank().height(SettingsPageTitleBarManager.getContentTopPadding(this.statusBarHeight))

          Column() {
            this.buildSearchBar()
          }
          .width('100%')
          .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.TOP, SafeAreaEdge.BOTTOM])
          .height(this.showSearchBar ? 56 : 0)
          .opacity(this.showSearchBar ? 1 : 0)
          .clip(true)
          .animation({ duration: 200, curve: Curve.EaseOut })

          this.buildFilterBar()

          if (this.isLoading) {
            Column({ space: 10 }) {
              LoadingProgress()
                .width(36)
                .height(36)
                .color(ThemeAwareHelper.getTestManagementThemedColor('accent_primary', this.themeState.currentTheme))
              Text('加载中...')
                .fontSize(13)
                .fontFamily(this.appFontFamily)
                .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_secondary', this.themeState.currentTheme))
            }
            .width('100%')
            .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.TOP, SafeAreaEdge.BOTTOM])
            .layoutWeight(1)
            .justifyContent(FlexAlign.Center)
            .alignItems(HorizontalAlign.Center)
          } else if (this.items.length === 0) {
            Column({ space: 12 }) {
              Text('暂无收藏条目')
                .fontSize(16)
                .fontWeight(FontWeight.Medium)
                .fontFamily(this.appFontFamily)
                .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_primary', this.themeState.currentTheme))

              Text('可在订阅流中点击“收藏”后回到本页查看')
                .fontSize(13)
                .fontFamily(this.appFontFamily)
                .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_secondary', this.themeState.currentTheme))

              Button('打开订阅流')
                .fontFamily(this.appFontFamily)
                .fontColor('#FFFFFF')
                .backgroundColor(ThemeAwareHelper.getTestManagementThemedColor('accent_primary', this.themeState.currentTheme))
                .borderRadius(20)
                .onClick(() => {
                  this.openSubscriptionPage();
                })
            }
            .width('100%')
            .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.TOP, SafeAreaEdge.BOTTOM])
            .layoutWeight(1)
            .justifyContent(FlexAlign.Center)
            .alignItems(HorizontalAlign.Center)
          } else {
            List() {
              ForEach(this.items, (item: RssFeedItem) => {
                ListItem() {
                  this.buildItemCard(item)
                }
              }, (item: RssFeedItem) => item.id)
            }
            .width('100%')
            .height('100%')
            .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.TOP, SafeAreaEdge.BOTTOM])
            .layoutWeight(1)
            .padding({ left: 12, right: 12, top: 8, bottom: 16 + this.navigationBarHeight })
            .scrollBar(BarState.Auto)
            .edgeEffect(EdgeEffect.Spring)
          }
        }
        .width('100%')
        .height('100%')
        .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.TOP, SafeAreaEdge.BOTTOM])
        .padding({ bottom: this.navigationBarHeight })

        SettingsImmersiveTitleBar({
          themeState: this.themeState,
          title: 'RSS收藏',
          appFontFamily: this.appFontFamily,
          actions: this.getTitleBarActions()
        })
      }
    }
    .hideTitleBar(true)
    .ignoreLayoutSafeArea([LayoutSafeAreaType.SYSTEM], [LayoutSafeAreaEdge.TOP, LayoutSafeAreaEdge.BOTTOM])
    .backgroundColor(Color.Transparent)
  }
}
