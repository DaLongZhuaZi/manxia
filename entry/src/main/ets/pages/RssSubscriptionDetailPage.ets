/**
 * RSS 订阅条目详情页。
 * 展示标题、来源、摘要、正文，并支持正文抓取刷新。
 */

import { HdsNavDestination } from '@kit.UIDesignKit';
import { LengthMetrics, promptAction } from '@kit.ArkUI';
import { common } from '@kit.AbilityKit';
import { logger } from 'manxia_core/src/main/ets/Utils/Logger';
import { PageLifecycleManager } from 'manxia_core/src/main/ets/Framework/Lifecycle/index';
import { ThemeAwareState, ThemeAwareHelper } from 'manxia_theme/src/main/ets/Framework/Components/ThemeAware';
import { ThemeType } from 'manxia_theme/src/main/ets/Framework/Managers/ThemeManager';
import { FontAwareHelper, FontAwareState } from 'manxia_theme/src/main/ets/Framework/Components/FontAware';
import { RssFeedItem, RssSubscriptionSource } from 'manxia_core/src/main/ets/Models/RssSubscriptionModels';
import { getRssSubscriptionInitializer } from '../Framework/Rss/RssSubscriptionInitializer';
import { getRssSubscriptionManager, RssSubscriptionManager } from '../Framework/Rss/RssSubscriptionManager';
import { DisplayMode } from 'manxia_theme/src/main/ets/Utils/WindowManager';
import { PageWindowCoordinator } from 'manxia_theme/src/main/ets/Utils/PageWindowCoordinator';

const TAG = 'RssSubscriptionDetailPage';
const TITLE_BAR_HEIGHT_MINI = 56;

export interface RssSubscriptionDetailPageParams {
  itemId: string;
}

interface RssDetailPathInfo {
  param?: Object;
}

interface NavDestinationContext {
  pathInfo: RssDetailPathInfo;
}

@Component
export struct RssSubscriptionDetailPage {
  @Consume('NavPathStack') pathStack: NavPathStack;

  @State themeState: ThemeAwareState = new ThemeAwareState();
  @State fontState: FontAwareState = new FontAwareState();
  @StorageLink('appFontFamily') appFontFamily: string = 'HarmonyOS Sans';
  private readonly componentId: string = `RssSubscriptionDetailPage_${Date.now()}`;

  @State item: RssFeedItem | null = null;
  @State source: RssSubscriptionSource | null = null;
  @State isLoading: boolean = true;
  @State isRefreshingContent: boolean = false;
  @State errorText: string = '';

  private itemId: string = '';
  private readonly manager: RssSubscriptionManager = getRssSubscriptionManager();
  private lifecycle = new PageLifecycleManager('RssSubscriptionDetailPage', { enableDebug: true });
  private previousDisplayMode: DisplayMode = DisplayMode.DEFAULT;

  aboutToAppear(): void {
    this.previousDisplayMode = PageWindowCoordinator.captureCurrentDisplayMode();
    PageWindowCoordinator.applyPagePolicy('RssSubscriptionDetailPage', this.getUIContext());
    ThemeAwareHelper.initializeThemeAware(this.componentId, this.themeState, (_theme: ThemeType) => {
    });
    FontAwareHelper.initializeFontAware(
      this.componentId,
      this.fontState,
      (newState: FontAwareState) => {
        this.fontState = newState;
      }
    );
  }

  aboutToDisappear(): void {
    PageWindowCoordinator.restoreDisplayMode(this.previousDisplayMode, this.getUIContext());
    this.lifecycle.destroy();
    ThemeAwareHelper.cleanupThemeAware(this.componentId);
    FontAwareHelper.cleanupFontAware(this.componentId);
  }

  private async initializeAndLoad(): Promise<void> {
    this.isLoading = true;
    this.errorText = '';
    try {
      logger.info(TAG, `开始初始化订阅条目详情页: itemId=${this.itemId}`);
      const context = (this.getUIContext().getHostContext() as common.UIAbilityContext) as common.UIAbilityContext;
      await getRssSubscriptionInitializer().initialize(context);
      await this.loadItemDetail(true);
      logger.info(TAG, `订阅条目详情页初始化完成: itemId=${this.itemId}`);
    } catch (error) {
      const errorText = String(error);
      this.errorText = errorText;
      logger.error(TAG, `初始化订阅条目详情页失败: ${errorText}`);
      this.getUIContext().getPromptAction().showToast({ message: `加载失败: ${errorText}` });
    }
    this.isLoading = false;
  }

  private async loadItemDetail(markRead: boolean): Promise<void> {
    if (this.itemId.length === 0) {
      throw new Error('条目参数缺失');
    }

    const loadedItem = await this.manager.getItemById(this.itemId);
    if (!loadedItem) {
      throw new Error('条目不存在或已被删除');
    }
    this.source = await this.manager.getSourceById(loadedItem.sourceId);

    if (markRead && !loadedItem.isRead) {
      await this.manager.setItemRead(loadedItem.id, true);
      const refreshedItem = await this.manager.getItemById(this.itemId);
      this.item = refreshedItem || loadedItem;
      return;
    }
    this.item = loadedItem;
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

  private getDisplayDescription(): string {
    if (!this.item || !this.item.description) {
      return '';
    }
    return this.item.description.trim();
  }

  private getDisplayContent(): string {
    if (!this.item) {
      return '';
    }
    const content = this.item.content ? this.item.content.trim() : '';
    if (content.length > 0) {
      return content;
    }
    const description = this.getDisplayDescription();
    if (description.length > 0) {
      return description;
    }
    return '暂无正文，可点击“刷新正文”尝试抓取。';
  }

  private hasOriginalLink(): boolean {
    return this.item !== null && this.item.link.length > 0;
  }

  private updateLocalReadState(isRead: boolean): void {
    if (!this.item) {
      return;
    }
    this.item.isRead = isRead;
  }

  private updateLocalStarState(isStarred: boolean): void {
    if (!this.item) {
      return;
    }
    this.item.isStarred = isStarred;
  }

  private async toggleRead(): Promise<void> {
    if (!this.item) {
      return;
    }
    try {
      const nowRead = !this.item.isRead;
      await this.manager.setItemRead(this.item.id, nowRead);
      this.updateLocalReadState(nowRead);
      this.getUIContext().getPromptAction().showToast({ message: nowRead ? '已标记为已读' : '已标记为未读' });
    } catch (error) {
      logger.error(TAG, `更新已读状态失败: ${String(error)}`);
      this.getUIContext().getPromptAction().showToast({ message: `更新失败: ${String(error)}` });
    }
  }

  private async toggleStarred(): Promise<void> {
    if (!this.item) {
      return;
    }
    try {
      const nowStarred = !this.item.isStarred;
      await this.manager.setItemStarred(this.item.id, nowStarred);
      this.updateLocalStarState(nowStarred);
      this.getUIContext().getPromptAction().showToast({ message: nowStarred ? '已收藏' : '已取消收藏' });
    } catch (error) {
      logger.error(TAG, `更新收藏状态失败: ${String(error)}`);
      this.getUIContext().getPromptAction().showToast({ message: `更新失败: ${String(error)}` });
    }
  }

  private async openOriginalLink(): Promise<void> {
    if (!this.item || this.item.link.length === 0) {
      this.getUIContext().getPromptAction().showToast({ message: '当前条目没有原文链接' });
      return;
    }
    try {
      logger.info(TAG, `打开订阅条目原文: itemId=${this.item.id}`);
      const context = (this.getUIContext().getHostContext() as common.UIAbilityContext) as common.UIAbilityContext;
      await context.openLink(this.item.link, { appLinkingOnly: false });
    } catch (error) {
      logger.error(TAG, `打开订阅条目原文失败: ${String(error)}`);
      this.getUIContext().getPromptAction().showToast({ message: `打开失败: ${String(error)}` });
    }
  }

  private async refreshContent(): Promise<void> {
    if (!this.item || this.isRefreshingContent) {
      return;
    }
    this.isRefreshingContent = true;
    try {
      logger.info(TAG, `开始刷新订阅条目正文: itemId=${this.item.id}`);
      const result = await this.manager.refreshItemContent(this.item.id);
      if (!result.success) {
        throw new Error(result.error || '正文抓取失败');
      }
      if (this.item) {
        this.item.content = result.content;
        this.item.description = result.description;
      }
      this.getUIContext().getPromptAction().showToast({ message: '正文刷新成功' });
    } catch (error) {
      logger.error(TAG, `刷新订阅条目正文失败: ${String(error)}`);
      this.getUIContext().getPromptAction().showToast({ message: `刷新失败: ${String(error)}` });
    }
    this.isRefreshingContent = false;
  }

  @Builder
  private buildActionButtons(item: RssFeedItem | null) {
    if (item) {
      Row({ space: 8 }) {
        Button(item.isRead ? '标未读' : '标已读')
          .height(34)
          .fontSize(12)
          .fontFamily(this.appFontFamily)
          .backgroundColor(ThemeAwareHelper.getTestManagementThemedColor('panel_background', this.themeState.currentTheme))
          .onClick(() => {
            this.toggleRead();
          })

        Button(item.isStarred ? '取消收藏' : '收藏')
          .height(34)
          .fontSize(12)
          .fontFamily(this.appFontFamily)
          .backgroundColor(ThemeAwareHelper.getTestManagementThemedColor('panel_background', this.themeState.currentTheme))
          .onClick(() => {
            this.toggleStarred();
          })

        Button(this.isRefreshingContent ? '刷新中...' : '刷新正文')
          .height(34)
          .fontSize(12)
          .fontFamily(this.appFontFamily)
          .fontColor('#FFFFFF')
          .backgroundColor(ThemeAwareHelper.getTestManagementThemedColor('accent_primary', this.themeState.currentTheme))
          .enabled(!this.isRefreshingContent)
          .onClick(() => {
            this.refreshContent();
          })

        Button('打开原文')
          .height(34)
          .fontSize(12)
          .fontFamily(this.appFontFamily)
          .fontColor('#FFFFFF')
          .backgroundColor('#2F54EB')
          .onClick(() => {
            this.openOriginalLink();
          })
      }
      .width('100%')
    }
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
          .height('100%')
          .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.TOP, SafeAreaEdge.BOTTOM])
          .justifyContent(FlexAlign.Center)
          .alignItems(HorizontalAlign.Center)
        } else {
          Column() {
            Blank().height(TITLE_BAR_HEIGHT_MINI)
            Scroll() {
              Column({ space: 10 }) {
                if (this.errorText.length > 0) {
                  Text(`加载失败: ${this.errorText}`)
                    .width('100%')
                    .fontSize(13)
                    .fontFamily(this.appFontFamily)
                    .fontColor(ThemeAwareHelper.getTestManagementThemedColor('color_error', this.themeState.currentTheme))
                } else if (this.item) {
                  Text(this.item.title)
                    .width('100%')
                    .fontSize(20)
                    .fontWeight(FontWeight.Bold)
                    .fontFamily(this.appFontFamily)
                    .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_primary', this.themeState.currentTheme))

                  Text(`${this.item.sourceName} | ${this.formatTime(this.item.pubDate)}`)
                    .width('100%')
                    .fontSize(12)
                    .fontFamily(this.appFontFamily)
                    .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_secondary', this.themeState.currentTheme))

                  if (this.source && this.source.groupName && this.source.groupName.trim().length > 0) {
                    Text(`分组: ${this.source.groupName}`)
                      .width('100%')
                      .fontSize(12)
                      .fontFamily(this.appFontFamily)
                      .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_tertiary', this.themeState.currentTheme))
                  }

                  this.buildActionButtons(this.item)

                  if (this.getDisplayDescription().length > 0) {
                    Column({ space: 6 }) {
                      Text('摘要')
                        .width('100%')
                        .fontSize(14)
                        .fontWeight(FontWeight.Medium)
                        .fontFamily(this.appFontFamily)
                        .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_primary', this.themeState.currentTheme))
                      Text(this.getDisplayDescription())
                        .width('100%')
                        .fontSize(13)
                        .lineHeight(22)
                        .fontFamily(this.appFontFamily)
                        .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_secondary', this.themeState.currentTheme))
                    }
                    .width('100%')
                    .padding(12)
                    .backgroundColor(ThemeAwareHelper.getTestManagementThemedColor('background_secondary', this.themeState.currentTheme))
                    .borderRadius(10)
                  }

                  Column({ space: 6 }) {
                    Text('正文')
                      .width('100%')
                      .fontSize(14)
                      .fontWeight(FontWeight.Medium)
                      .fontFamily(this.appFontFamily)
                      .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_primary', this.themeState.currentTheme))
                    Text(this.getDisplayContent())
                      .width('100%')
                      .fontSize(14)
                      .lineHeight(24)
                      .fontFamily(this.appFontFamily)
                      .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_primary', this.themeState.currentTheme))
                  }
                  .width('100%')
                  .padding(12)
                  .backgroundColor(ThemeAwareHelper.getTestManagementThemedColor('background_secondary', this.themeState.currentTheme))
                  .borderRadius(10)
                }
              }
              .width('100%')
              .padding({ left: 12, right: 12, top: 8, bottom: 20 })
            }
            .width('100%')
            .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.TOP, SafeAreaEdge.BOTTOM])
            .layoutWeight(1)
            .scrollBar(BarState.Auto)
            .edgeEffect(EdgeEffect.Spring)
          }
          .width('100%')
          .height('100%')
          .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.TOP, SafeAreaEdge.BOTTOM])
        }
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
        title: { mainTitle: '订阅详情' },
        menu: {
          value: [{
            content: {
              label: '刷新正文',
              icon: $r('sys.symbol.arrow_clockwise'),
              isEnabled: !this.isRefreshingContent && !this.isLoading,
              action: () => {
                this.refreshContent();
              }
            }
          }, {
            content: {
              label: '原文',
              icon: $r('sys.symbol.arrow_up_right'),
              isEnabled: this.hasOriginalLink(),
              action: () => {
                this.openOriginalLink();
              }
            }
          }]
        }
      }
    })
    .onReady((context: NavDestinationContext) => {
      const param = context.pathInfo.param as RssSubscriptionDetailPageParams | null;
      this.itemId = param && param.itemId ? param.itemId : '';
      this.initializeAndLoad();
    })
    .backgroundColor(Color.Transparent)
  }
}
