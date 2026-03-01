/**
 * RSS subscription feed page.
 * Shows aggregated entries from all subscription sources.
 */

import { HdsNavDestination } from '@kit.UIDesignKit';
import { LengthMetrics, promptAction } from '@kit.ArkUI';
import { common } from '@kit.AbilityKit';
import { logger } from '../Utils/Logger';
import { PageLifecycleManager } from '../Framework/Lifecycle';
import { ThemeAwareState, ThemeAwareHelper } from '../Framework/Components/ThemeAware';
import { ThemeType } from '../Framework/Managers/ThemeManager';
import { FontAwareHelper, FontAwareState } from '../Framework/Components/FontAware';
import { RssFeedItem, RssFetchResult, RssSubscriptionSource } from '../Models/RssSubscriptionModels';
import { getRssSubscriptionInitializer } from '../Framework/Rss/RssSubscriptionInitializer';
import { getRssSubscriptionManager, RssSubscriptionManager } from '../Framework/Rss/RssSubscriptionManager';
import { RssSubscriptionDetailPageParams } from './RssSubscriptionDetailPage';

const TAG = 'RssSubscriptionPage';
const TITLE_BAR_HEIGHT_MINI = 56;

type FeedFilterMode = 'all' | 'unread' | 'starred';

@Component
export struct RssSubscriptionPage {
  @Consume('NavPathStack') pathStack: NavPathStack;

  @State themeState: ThemeAwareState = new ThemeAwareState();
  @State fontState: FontAwareState = new FontAwareState();
  @StorageLink('appFontFamily') appFontFamily: string = 'HarmonyOS Sans';
  private readonly componentId: string = `RssSubscriptionPage_${Date.now()}`;

  @State allItems: RssFeedItem[] = [];
  @State items: RssFeedItem[] = [];
  @State sources: RssSubscriptionSource[] = [];
  @State isLoading: boolean = true;
  @State isRefreshing: boolean = false;
  @State isBatchOperating: boolean = false;
  @State progressText: string = '';
  @State selectedSourceId: string = '';
  @State filterMode: FeedFilterMode = 'all';
  @State unreadCount: number = 0;
  @State showSearchBar: boolean = false;
  @State searchKeyword: string = '';

  private readonly manager: RssSubscriptionManager = getRssSubscriptionManager();
  private itemsLoadVersion: number = 0;
  private lifecycle = new PageLifecycleManager('RssSubscriptionPage', { enableDebug: true });

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
      this.loadAllData();
      this.triggerAutoDueRefresh();
    }
  }

  private async initializeAndLoad(): Promise<void> {
    this.isLoading = true;
    try {
      logger.info(TAG, '开始初始化订阅源页面');
      const context = getContext(this) as common.UIAbilityContext;
      await getRssSubscriptionInitializer().initialize(context);
      await this.loadAllData();
      this.triggerAutoDueRefresh();
      logger.info(TAG, '订阅源页面初始化完成');
    } catch (error) {
      logger.error(TAG, `初始化订阅源页面失败: ${String(error)}`);
      promptAction.showToast({ message: `初始化失败: ${String(error)}` });
    }
    this.isLoading = false;
  }

  private triggerAutoDueRefresh(): void {
    this.manager.maybeRefreshDueSources('订阅流页面进入').then((results: RssFetchResult[]) => {
      if (results.length > 0) {
        logger.info(TAG, `自动到期刷新完成并更新订阅流: 更新源=${results.length}`);
        this.loadAllData();
      }
    }).catch((error: Object | string | number | boolean | null | undefined) => {
      logger.warn(TAG, `触发自动到期刷新失败: ${String(error)}`);
    });
  }

  private async loadAllData(): Promise<void> {
    try {
      this.sources = await this.manager.getAllSources(true);
      this.unreadCount = await this.manager.getUnreadCount(this.selectedSourceId || undefined);
      await this.loadItemsOnly();
    } catch (error) {
      logger.warn(TAG, `加载订阅源总数据失败: ${String(error)}`);
      promptAction.showToast({ message: '加载订阅流失败' });
    }
  }

  private async loadItemsOnly(): Promise<void> {
    const loadVersion = ++this.itemsLoadVersion;
    try {
      const resultItems = await this.manager.queryItems({
        sourceId: this.selectedSourceId || undefined,
        unreadOnly: this.filterMode === 'unread',
        starredOnly: this.filterMode === 'starred',
        limit: 400
      });
      const unreadCount = await this.manager.getUnreadCount(this.selectedSourceId || undefined);
      if (loadVersion !== this.itemsLoadVersion) {
        logger.debug(TAG, `忽略过期订阅条目加载结果: version=${loadVersion}, current=${this.itemsLoadVersion}`);
        return;
      }
      this.allItems = resultItems;
      this.unreadCount = unreadCount;
      this.applySearchFilter();
    } catch (error) {
      logger.warn(TAG, `加载订阅条目失败: ${String(error)}`);
      promptAction.showToast({ message: '加载订阅条目失败' });
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

  private onSearchChange(keyword: string): void {
    this.searchKeyword = keyword;
    logger.debug(TAG, `订阅条目搜索关键词变更: ${keyword}`);
    this.applySearchFilter();
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

  private chooseFilter(mode: FeedFilterMode): void {
    logger.info(TAG, `切换订阅条目过滤模式: ${mode}`);
    this.filterMode = mode;
    this.loadItemsOnly();
  }

  private chooseSource(sourceId: string): void {
    logger.info(TAG, `切换订阅来源过滤: ${sourceId.length > 0 ? sourceId : '全部来源'}`);
    this.selectedSourceId = sourceId;
    this.loadItemsOnly();
  }

  private async refreshAll(): Promise<void> {
    if (this.isRefreshing) {
      return;
    }
    this.isRefreshing = true;
    this.progressText = '准备中...';
    try {
      logger.info(TAG, '开始批量刷新订阅源');
      const results = await this.manager.refreshAll((progress) => {
        const detail = progress.success
          ? `新增${progress.insertedCount || 0}/总${progress.itemCount || 0}`
          : `失败: ${progress.error || '未知错误'}`;
        this.progressText = `${progress.current}/${progress.total} ${progress.sourceName} ${detail}`;
      });
      const success = results.filter((item) => item.success).length;
      const failed = results.length - success;
      const failedResults = results.filter((item) => !item.success);
      for (let i = 0; i < failedResults.length; i++) {
        const failedItem = failedResults[i];
        logger.warn(TAG, `订阅源刷新失败明细: source=${failedItem.sourceName}, error=${failedItem.error || '未知错误'}`);
      }
      promptAction.showToast({ message: `刷新完成，成功 ${success}，失败 ${failed}` });
      logger.info(TAG, `批量刷新订阅源完成: 成功=${success}, 失败=${failed}`);
      await this.loadAllData();
    } catch (error) {
      logger.error(TAG, `批量刷新订阅源失败: ${String(error)}`);
      promptAction.showToast({ message: `刷新失败: ${String(error)}` });
    }
    this.progressText = '';
    this.isRefreshing = false;
  }

  private async refreshDueSources(): Promise<void> {
    if (this.isRefreshing) {
      return;
    }
    this.isRefreshing = true;
    this.progressText = '准备中...';
    try {
      logger.info(TAG, '开始刷新到期订阅源');
      const results = await this.manager.refreshDueSources((progress) => {
        const detail = progress.success
          ? `新增${progress.insertedCount || 0}/总${progress.itemCount || 0}`
          : `失败: ${progress.error || '未知错误'}`;
        this.progressText = `${progress.current}/${progress.total} ${progress.sourceName} ${detail}`;
      });
      if (results.length === 0) {
        promptAction.showToast({ message: '暂无到期订阅源' });
        logger.info(TAG, '刷新到期订阅源完成: 无到期源');
      } else {
        const success = results.filter((item) => item.success).length;
        const failed = results.length - success;
        const failedResults = results.filter((item) => !item.success);
        for (let i = 0; i < failedResults.length; i++) {
          const failedItem = failedResults[i];
          logger.warn(TAG, `到期刷新失败明细: source=${failedItem.sourceName}, error=${failedItem.error || '未知错误'}`);
        }
        promptAction.showToast({ message: `到期刷新完成，成功 ${success}，失败 ${failed}` });
        logger.info(TAG, `刷新到期订阅源完成: 总数=${results.length}, 成功=${success}, 失败=${failed}`);
      }
      await this.loadAllData();
    } catch (error) {
      logger.error(TAG, `刷新到期订阅源失败: ${String(error)}`);
      promptAction.showToast({ message: `到期刷新失败: ${String(error)}` });
    }
    this.progressText = '';
    this.isRefreshing = false;
  }

  private async markAllRead(): Promise<void> {
    if (this.isBatchOperating) {
      return;
    }
    this.isBatchOperating = true;
    try {
      logger.info(TAG, `开始标记全部已读: sourceId=${this.selectedSourceId || 'all'}`);
      await this.manager.markAllRead(this.selectedSourceId || undefined);
      await this.loadItemsOnly();
      promptAction.showToast({ message: '已标记为已读' });
    } catch (error) {
      logger.error(TAG, `标记全部已读失败: ${String(error)}`);
      promptAction.showToast({ message: `操作失败: ${String(error)}` });
    }
    this.isBatchOperating = false;
  }

  private async clearReadItems(): Promise<void> {
    if (this.isBatchOperating) {
      return;
    }
    this.isBatchOperating = true;
    try {
      logger.info(TAG, `开始清理已读条目: sourceId=${this.selectedSourceId || 'all'}`);
      const deletedCount = await this.manager.clearReadItems(this.selectedSourceId || undefined);
      await this.loadItemsOnly();
      if (deletedCount > 0) {
        promptAction.showToast({ message: `已清理 ${deletedCount} 条已读内容` });
      } else {
        promptAction.showToast({ message: '当前没有可清理的已读条目' });
      }
      logger.info(TAG, `清理已读条目完成: sourceId=${this.selectedSourceId || 'all'}, 删除=${deletedCount}`);
    } catch (error) {
      logger.error(TAG, `清理已读条目失败: ${String(error)}`);
      promptAction.showToast({ message: `清理失败: ${String(error)}` });
    }
    this.isBatchOperating = false;
  }

  private getBatchScopeText(): string {
    if (this.selectedSourceId.length === 0) {
      return '全部来源';
    }
    for (let i = 0; i < this.sources.length; i++) {
      const source = this.sources[i];
      if (source.id === this.selectedSourceId) {
        return source.name;
      }
    }
    return '当前来源';
  }

  private showBatchActionMenu(): void {
    if (this.isBatchOperating) {
      return;
    }
    const scopeText = this.getBatchScopeText();
    promptAction.showActionMenu({
      title: `批量操作（${scopeText}）`,
      buttons: [
        { text: '标记已读', color: $r('sys.color.ohos_id_color_text_primary_activated') },
        { text: '清理已读', color: $r('sys.color.ohos_id_color_text_primary') },
        { text: '取消', color: $r('sys.color.ohos_id_color_text_secondary') }
      ]
    }).then((result: promptAction.ActionMenuSuccessResponse) => {
      if (result.index === 0) {
        this.markAllRead();
        return;
      }
      if (result.index === 1) {
        this.clearReadItems();
        return;
      }
    }).catch(() => {
      logger.debug(TAG, '批量操作菜单已关闭');
    });
  }

  private updateLocalItemState(itemId: string, isRead: boolean, isStarred: boolean): void {
    const nextItems: RssFeedItem[] = [];
    for (let i = 0; i < this.allItems.length; i++) {
      const current = this.allItems[i];
      if (current.id === itemId) {
        current.isRead = isRead;
        current.isStarred = isStarred;
      }
      if (this.filterMode === 'unread' && current.isRead) {
        continue;
      }
      if (this.filterMode === 'starred' && !current.isStarred) {
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
      this.updateLocalItemState(item.id, nextRead, currentStarred);
      this.unreadCount = await this.manager.getUnreadCount(this.selectedSourceId || undefined);
    } catch (error) {
      logger.error(TAG, `更新已读状态失败: itemId=${item.id}, ${String(error)}`);
      promptAction.showToast({ message: `更新失败: ${String(error)}` });
    }
  }

  private async toggleStarred(item: RssFeedItem): Promise<void> {
    try {
      const nextStarred = !item.isStarred;
      const currentRead = item.isRead;
      await this.manager.setItemStarred(item.id, nextStarred);
      this.updateLocalItemState(item.id, currentRead, nextStarred);
    } catch (error) {
      logger.error(TAG, `更新收藏状态失败: itemId=${item.id}, ${String(error)}`);
      promptAction.showToast({ message: `更新失败: ${String(error)}` });
    }
  }

  private openItem(item: RssFeedItem): void {
    logger.info(TAG, `打开订阅条目详情: itemId=${item.id}`);
    const params: RssSubscriptionDetailPageParams = {
      itemId: item.id
    };
    this.pathStack.pushPathByName('RssSubscriptionDetailPage', params);
  }

  private openManagementPage(): void {
    this.pathStack.pushPathByName('RssSubscriptionManagementPage', null);
  }

  private openFavoritesPage(): void {
    this.pathStack.pushPathByName('RssFavoritesPage', null);
  }

  @Builder
  private buildFilterBar() {
    Column({ space: 10 }) {
      Row({ space: 8 }) {
        this.buildModeButton('全部', this.filterMode === 'all', () => {
          this.chooseFilter('all');
        })
        this.buildModeButton(`未读(${this.unreadCount})`, this.filterMode === 'unread', () => {
          this.chooseFilter('unread');
        })
        this.buildModeButton('收藏', this.filterMode === 'starred', () => {
          this.chooseFilter('starred');
        })
      }
      .width('100%')

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
        .padding({ right: 16 })
      }
      .scrollable(ScrollDirection.Horizontal)
      .scrollBar(BarState.Off)
      .width('100%')

      if (this.isRefreshing && this.progressText.length > 0) {
        Text(`刷新进度: ${this.progressText}`)
          .fontSize(12)
          .fontFamily(this.appFontFamily)
          .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_secondary', this.themeState.currentTheme))
          .width('100%')
      }

      if (this.isBatchOperating) {
        Text('批量操作执行中...')
          .fontSize(12)
          .fontFamily(this.appFontFamily)
          .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_secondary', this.themeState.currentTheme))
          .width('100%')
      }
    }
    .width('100%')
    .padding({ left: 16, right: 16, bottom: 10 })
    .backgroundColor(ThemeAwareHelper.getTestManagementThemedColor('background_secondary', this.themeState.currentTheme))
  }

  @Builder
  private buildSearchBar() {
    Row() {
      TextInput({ placeholder: '搜索标题、来源或摘要...', text: this.searchKeyword })
        .layoutWeight(1)
        .height(40)
        .backgroundColor(ThemeAwareHelper.getTestManagementThemedColor('panel_background', this.themeState.currentTheme))
        .borderRadius(20)
        .padding({ left: 16, right: 16 })
        .onChange((value: string) => {
          this.onSearchChange(value);
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
    .backgroundColor(ThemeAwareHelper.getTestManagementThemedColor('background_secondary', this.themeState.currentTheme))
  }

  @Builder
  private buildModeButton(title: string, selected: boolean, onClick: () => void) {
    Button(title)
      .height(34)
      .fontSize(12)
      .fontFamily(this.appFontFamily)
      .backgroundColor(selected
        ? ThemeAwareHelper.getTestManagementThemedColor('accent_primary', this.themeState.currentTheme)
        : ThemeAwareHelper.getTestManagementThemedColor('comp_background_tertiary', this.themeState.currentTheme))
      .fontColor(selected
        ? '#FFFFFF'
        : ThemeAwareHelper.getTestManagementThemedColor('text_primary', this.themeState.currentTheme))
      .onClick(() => {
        onClick();
      })
  }

  @Builder
  private buildSourceButton(title: string, selected: boolean, onClick: () => void) {
    Button(title)
      .height(30)
      .fontSize(11)
      .fontFamily(this.appFontFamily)
      .backgroundColor(selected
        ? ThemeAwareHelper.getTestManagementThemedColor('comp_background_tertiary', this.themeState.currentTheme)
        : ThemeAwareHelper.getTestManagementThemedColor('panel_background', this.themeState.currentTheme))
      .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_primary', this.themeState.currentTheme))
      .onClick(() => {
        onClick();
      })
  }

  @Builder
  private buildItemCard(item: RssFeedItem) {
    Row() {
      Column()
        .width(4)
        .height(40)
        .borderRadius(2)
        .backgroundColor(item.isRead
          ? ThemeAwareHelper.getTestManagementThemedColor('text_muted', this.themeState.currentTheme)
          : ThemeAwareHelper.getTestManagementThemedColor('accent_primary', this.themeState.currentTheme))

      Column({ space: 8 }) {
        Text(item.title)
          .fontSize(15)
          .fontWeight(FontWeight.Medium)
          .fontFamily(this.appFontFamily)
          .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_primary', this.themeState.currentTheme))
          .maxLines(2)
          .width('100%')

        Row() {
          Text(item.sourceName)
            .fontSize(11)
            .fontFamily(this.appFontFamily)
            .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_secondary', this.themeState.currentTheme))
          Text('  |  ')
            .fontSize(11)
            .fontFamily(this.appFontFamily)
            .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_secondary', this.themeState.currentTheme))
          Text(this.formatTime(item.pubDate))
            .fontSize(11)
            .fontFamily(this.appFontFamily)
            .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_secondary', this.themeState.currentTheme))
        }
        .width('100%')

        if (item.description && item.description.length > 0) {
          Text(item.description)
            .fontSize(12)
            .fontFamily(this.appFontFamily)
            .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_secondary', this.themeState.currentTheme))
            .maxLines(3)
            .width('100%')
        }

        Row({ space: 8 }) {
          Button(item.isRead ? '标未读' : '标已读')
            .fontSize(12)
            .height(30)
            .fontFamily(this.appFontFamily)
            .backgroundColor(ThemeAwareHelper.getTestManagementThemedColor('panel_background', this.themeState.currentTheme))
            .borderRadius(16)
            .onClick(() => {
              this.toggleRead(item);
            })
          Button(item.isStarred ? '取消收藏' : '收藏')
            .fontSize(12)
            .height(30)
            .fontFamily(this.appFontFamily)
            .backgroundColor(ThemeAwareHelper.getTestManagementThemedColor('panel_background', this.themeState.currentTheme))
            .borderRadius(16)
            .onClick(() => {
              this.toggleStarred(item);
            })
          Button('详情')
            .fontSize(12)
            .height(30)
            .fontFamily(this.appFontFamily)
            .fontColor('#FFFFFF')
            .backgroundColor(ThemeAwareHelper.getTestManagementThemedColor('accent_primary', this.themeState.currentTheme))
            .borderRadius(16)
            .onClick(() => {
              this.openItem(item);
            })
        }
        .width('100%')
      }
      .layoutWeight(1)
      .alignItems(HorizontalAlign.Start)
      .margin({ left: 12 })
    }
    .width('100%')
    .padding({ left: 12, right: 16, top: 12, bottom: 12 })
    .backgroundColor(ThemeAwareHelper.getTestManagementThemedColor('background_secondary', this.themeState.currentTheme))
    .borderRadius(8)
    .margin({ bottom: 8 })
    .opacity(item.isRead ? 0.8 : 1)
    .onClick(() => {
      this.openItem(item);
    })
  }

  build() {
    HdsNavDestination() {
      Stack() {
        Column()
          .width('100%')
          .height('100%')
          .backgroundColor(ThemeAwareHelper.getTestManagementThemedColor('background', this.themeState.currentTheme))
          .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.TOP, SafeAreaEdge.BOTTOM])
          .animation(ThemeAwareHelper.getThemeTransitionAnimation())

        Column() {
          Blank().height(TITLE_BAR_HEIGHT_MINI)
          Column() {
            this.buildSearchBar()
          }
          .width('100%')
          .height(this.showSearchBar ? 56 : 0)
          .opacity(this.showSearchBar ? 1 : 0)
          .clip(true)
          .animation({ duration: 200, curve: Curve.EaseOut })

          this.buildFilterBar()

          if (this.isLoading) {
            Column() {
              LoadingProgress()
                .width(36)
                .height(36)
                .color(ThemeAwareHelper.getTestManagementThemedColor('accent_primary', this.themeState.currentTheme))
              Text('加载中...')
                .fontSize(13)
                .fontFamily(this.appFontFamily)
                .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_secondary', this.themeState.currentTheme))
                .margin({ top: 10 })
            }
            .width('100%')
            .layoutWeight(1)
            .justifyContent(FlexAlign.Center)
            .alignItems(HorizontalAlign.Center)
          } else if (this.sources.length === 0) {
            Column({ space: 12 }) {
              Text('暂无订阅源')
                .fontSize(16)
                .fontWeight(FontWeight.Medium)
                .fontFamily(this.appFontFamily)
              Text('先添加 RSS 订阅源，再回到本页查看内容')
                .fontSize(13)
                .fontFamily(this.appFontFamily)
                .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_secondary', this.themeState.currentTheme))
              Button('去管理页添加')
                .fontFamily(this.appFontFamily)
                .backgroundColor(ThemeAwareHelper.getTestManagementThemedColor('accent_primary', this.themeState.currentTheme))
                .fontColor('#FFFFFF')
                .borderRadius(20)
                .onClick(() => {
                  this.openManagementPage();
                })
            }
            .width('100%')
            .layoutWeight(1)
            .justifyContent(FlexAlign.Center)
            .alignItems(HorizontalAlign.Center)
          } else if (this.items.length === 0) {
            Column({ space: 10 }) {
              Text(this.searchKeyword.trim().length > 0 ? '未找到匹配条目' : '暂无条目')
                .fontSize(16)
                .fontWeight(FontWeight.Medium)
                .fontFamily(this.appFontFamily)
              Text(this.searchKeyword.trim().length > 0 ? '请尝试修改搜索关键词' : '可以点击右上角刷新，或切换筛选条件')
                .fontSize(13)
                .fontFamily(this.appFontFamily)
                .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_secondary', this.themeState.currentTheme))
              if (this.searchKeyword.trim().length > 0) {
                Button('清空搜索')
                  .fontFamily(this.appFontFamily)
                  .fontColor('#FFFFFF')
                  .backgroundColor(ThemeAwareHelper.getTestManagementThemedColor('accent_primary', this.themeState.currentTheme))
                  .borderRadius(20)
                  .onClick(() => {
                    this.searchKeyword = '';
                    this.applySearchFilter();
                  })
              }
            }
            .width('100%')
            .layoutWeight(1)
            .justifyContent(FlexAlign.Center)
            .alignItems(HorizontalAlign.Center)
          } else {
            List({ space: 0 }) {
              ForEach(this.items, (item: RssFeedItem) => {
                ListItem() {
                  this.buildItemCard(item)
                }
              }, (item: RssFeedItem) => item.id)
            }
            .width('100%')
            .layoutWeight(1)
            .padding({ left: 12, right: 12, top: 8 })
            .scrollBar(BarState.Auto)
            .edgeEffect(EdgeEffect.Spring)
          }
        }
        .width('100%')
        .height('100%')
      }
      .width('100%')
      .height('100%')
    }
    .titleBar({
      padding: {
        start: LengthMetrics.vp(2),
        end: LengthMetrics.vp(2)
      },
      style: {
        originalStyle: {
          backgroundStyle: {
            backgroundColor: ThemeAwareHelper.getTestManagementThemedColor('panel_background', this.themeState.currentTheme)
          },
          contentStyle: {
            titleStyle: {
              mainTitleColor: ThemeAwareHelper.getTestManagementThemedColor('text_primary', this.themeState.currentTheme)
            },
            backIconStyle: {
              backgroundColor: ThemeAwareHelper.getTestManagementThemedColor('comp_background_tertiary', this.themeState.currentTheme),
              iconColor: ThemeAwareHelper.getTestManagementThemedColor('icon_primary', this.themeState.currentTheme)
            }
          }
        }
      },
      content: {
        title: { mainTitle: '订阅源' },
        menu: {
          value: [{
            content: {
              label: '搜索',
              icon: $r('sys.symbol.magnifyingglass'),
              isEnabled: true,
              action: () => {
                this.showSearchBar = !this.showSearchBar;
                if (!this.showSearchBar) {
                  this.searchKeyword = '';
                  this.applySearchFilter();
                }
              }
            }
          }, {
            content: {
              label: '管理',
              icon: $r('sys.symbol.gearshape'),
              isEnabled: true,
              action: () => {
                this.openManagementPage();
              }
            }
          }, {
            content: {
              label: '收藏',
              icon: $r('sys.symbol.star'),
              isEnabled: true,
              action: () => {
                this.openFavoritesPage();
              }
            }
          }, {
            content: {
              label: '刷新',
              icon: $r('sys.symbol.arrow_clockwise'),
              isEnabled: !this.isRefreshing,
              action: () => {
                this.refreshAll();
              }
            }
          }, {
            content: {
              label: '刷新到期',
              icon: $r('sys.symbol.arrow_clockwise'),
              isEnabled: !this.isRefreshing,
              action: () => {
                this.refreshDueSources();
              }
            }
          }, {
            content: {
              label: '批量',
              icon: $r('sys.symbol.ellipsis_circle'),
              isEnabled: this.items.length > 0 && !this.isBatchOperating,
              action: () => {
                this.showBatchActionMenu();
              }
            }
          }]
        }
      }
    })
    .backgroundColor(Color.Transparent)
  }
}


