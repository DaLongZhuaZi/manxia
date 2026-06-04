/**
 * 订阅源调试页。
 * 用于快速验证订阅源抓取、规则预览，并输出调试日志。
 */

import { HdsNavDestination } from '@kit.UIDesignKit';
import { promptAction } from '@kit.ArkUI';
import { common } from '@kit.AbilityKit';
import { logger } from '../Utils/Logger';
import { PageLifecycleManager } from '../Framework/Lifecycle';
import { ThemeAwareState, ThemeAwareHelper } from '../Framework/Components/ThemeAware';
import { ThemeType } from '../Framework/Managers/ThemeManager';
import { FontAwareHelper, FontAwareState } from '../Framework/Components/FontAware';
import { RssSubscriptionSource } from '../Models/RssSubscriptionModels';
import { getRssSubscriptionInitializer } from '../Framework/Rss/RssSubscriptionInitializer';
import { getRssSubscriptionManager, RssSubscriptionManager } from '../Framework/Rss/RssSubscriptionManager';
import { SettingsImmersiveTitleBar } from './settings/SettingsImmersiveTitleBar';
import { SettingsImmersiveTitleActionItem, SettingsPageTitleBarManager } from './settings/SettingsPageTitleBarManager';
import { GlobalBackgroundLayerMode } from '../Framework/Components/GlobalBackgroundLayer';
import { SharedPageBackgroundLayer } from '../Framework/Components/SharedPageBackgroundLayer';
import { SettingsPanelSurfaceHelper } from './settings/SettingsPanelSurfaceHelper';

const TAG = 'RssSourceDebugPage';

export interface RssSourceDebugPageParams {
  sourceId?: string;
}

interface RssSourceDebugPathInfo {
  param?: Object;
}

interface RssSourceDebugContext {
  pathInfo: RssSourceDebugPathInfo;
}

@Component
export struct RssSourceDebugPage {
  @Consume('NavPathStack') pathStack: NavPathStack;

  @State themeState: ThemeAwareState = new ThemeAwareState();
  @State fontState: FontAwareState = new FontAwareState();
  @StorageLink('appFontFamily') appFontFamily: string = 'HarmonyOS Sans';
  @StorageProp('statusBarHeight') statusBarHeight: number = 0;
  @StorageProp('navigationBarHeight') navigationBarHeight: number = 0;
  private readonly componentId: string = `RssSourceDebugPage_${Date.now()}`;

  @State sources: RssSubscriptionSource[] = [];
  @State selectedSourceId: string = '';
  @State selectedSource: RssSubscriptionSource | null = null;
  @State previewLimitText: string = '12';
  @State isLoading: boolean = true;
  @State isRunning: boolean = false;
  @State debugOutput: string = '';

  private initialSourceId: string = '';
  private readonly manager: RssSubscriptionManager = getRssSubscriptionManager();
  private lifecycle = new PageLifecycleManager('RssSourceDebugPage', { enableDebug: true });

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
  }

  aboutToDisappear(): void {
    this.lifecycle.destroy();
    ThemeAwareHelper.cleanupThemeAware(this.componentId);
    FontAwareHelper.cleanupFontAware(this.componentId);
  }

  private appendDebugLine(line: string): void {
    const now = new Date();
    const hour = `${now.getHours()}`.padStart(2, '0');
    const minute = `${now.getMinutes()}`.padStart(2, '0');
    const second = `${now.getSeconds()}`.padStart(2, '0');
    const text = `[${hour}:${minute}:${second}] ${line}`;
    if (this.debugOutput.length === 0) {
      this.debugOutput = text;
      return;
    }
    this.debugOutput = `${this.debugOutput}\n${text}`;
  }

  private selectSource(sourceId: string): void {
    this.selectedSourceId = sourceId;
    for (let i = 0; i < this.sources.length; i++) {
      if (this.sources[i].id === sourceId) {
        this.selectedSource = this.sources[i];
        this.appendDebugLine(`切换调试源: ${this.sources[i].name}`);
        return;
      }
    }
    this.selectedSource = null;
  }

  private formatTime(timestamp: number): string {
    if (timestamp <= 0) {
      return '从未';
    }
    const date = new Date(timestamp);
    const year = date.getFullYear();
    const month = `${date.getMonth() + 1}`.padStart(2, '0');
    const day = `${date.getDate()}`.padStart(2, '0');
    const hour = `${date.getHours()}`.padStart(2, '0');
    const minute = `${date.getMinutes()}`.padStart(2, '0');
    return `${year}-${month}-${day} ${hour}:${minute}`;
  }

  private getNextDueTimeText(source: RssSubscriptionSource): string {
    if (!source.autoUpdate) {
      return '已关闭自动更新';
    }
    const interval = source.updateIntervalMin > 0 ? source.updateIntervalMin : 180;
    const base = source.lastSuccessTime > 0 ? source.lastSuccessTime : source.lastCheckTime;
    if (base <= 0) {
      return '首次刷新将立即执行';
    }
    return this.formatTime(base + interval * 60 * 1000);
  }

  private async initializeAndLoad(): Promise<void> {
    this.isLoading = true;
    try {
      const context = (this.getUIContext().getHostContext() as common.UIAbilityContext) as common.UIAbilityContext;
      await getRssSubscriptionInitializer().initialize(context);
      this.sources = await this.manager.getAllSources(false);
      if (this.sources.length === 0) {
        this.appendDebugLine('当前无订阅源，请先到订阅源管理页创建');
      } else {
        const preferredId = this.initialSourceId.length > 0 ? this.initialSourceId : this.sources[0].id;
        this.selectSource(preferredId);
      }
      logger.info(TAG, `订阅源调试页初始化完成: sources=${this.sources.length}`);
    } catch (error) {
      const errorText = String(error);
      logger.error(TAG, `订阅源调试页初始化失败: ${errorText}`);
      this.appendDebugLine(`初始化失败: ${errorText}`);
      this.getUIContext().getPromptAction().showToast({ message: `初始化失败: ${errorText}` });
    }
    this.isLoading = false;
  }

  private async runRefreshDebug(): Promise<void> {
    if (this.isRunning || !this.selectedSource) {
      return;
    }
    this.isRunning = true;
    try {
      this.appendDebugLine(`开始刷新订阅源: ${this.selectedSource.name}`);
      const result = await this.manager.refreshSource(this.selectedSource.id);
      if (result.success) {
        this.appendDebugLine(`刷新成功: 状态=${result.statusCode}, 总=${result.itemCount}, 新增=${result.insertedCount}, 耗时=${result.durationMs}ms`);
      } else {
        this.appendDebugLine(`刷新失败: 状态=${result.statusCode}, 错误=${result.error || '未知错误'}, 耗时=${result.durationMs}ms`);
      }
      this.sources = await this.manager.getAllSources(false);
      this.selectSource(this.selectedSource.id);
    } catch (error) {
      this.appendDebugLine(`刷新异常: ${String(error)}`);
    }
    this.isRunning = false;
  }

  private async runRulePreviewDebug(): Promise<void> {
    if (this.isRunning || !this.selectedSource) {
      return;
    }
    const previewLimit = Math.max(1, parseInt(this.previewLimitText || '12', 10) || 12);
    this.isRunning = true;
    try {
      this.appendDebugLine(`开始规则预览: source=${this.selectedSource.name}, limit=${previewLimit}`);
      const result = await this.manager.previewSourceRules(this.selectedSource.id, previewLimit);
      this.appendDebugLine(`规则命中=${result.total}, 返回=${result.items.length}, 地址=${result.requestUrl}`);
      if (result.warning.length > 0) {
        this.appendDebugLine(`规则提示: ${result.warning}`);
      }
      const maxPrint = result.items.length > 8 ? 8 : result.items.length;
      for (let i = 0; i < maxPrint; i++) {
        const item = result.items[i];
        this.appendDebugLine(`预览${i + 1}: ${item.title}`);
      }
      if (result.items.length > maxPrint) {
        this.appendDebugLine(`其余 ${result.items.length - maxPrint} 条已省略`);
      }
    } catch (error) {
      this.appendDebugLine(`规则预览失败: ${String(error)}`);
    }
    this.isRunning = false;
  }

  private clearDebugOutput(): void {
    this.debugOutput = '';
    this.appendDebugLine('已清空调试输出');
  }

  @Builder
  private buildSourceButton(source: RssSubscriptionSource) {
    Text(source.name)
      .textAlign(TextAlign.Center)
      .height(30)
      .fontSize(11)
      .fontFamily(this.appFontFamily)
      .fontColor(this.selectedSourceId === source.id
        ? '#FFFFFF'
        : ThemeAwareHelper.getTestManagementThemedColor('text_primary', this.themeState.currentTheme))
      .backgroundColor(this.selectedSourceId === source.id
        ? ThemeAwareHelper.getTestManagementThemedColor('accent_primary', this.themeState.currentTheme)
        : ThemeAwareHelper.getTestManagementThemedColor('panel_background', this.themeState.currentTheme))
      .borderRadius(15)
      .padding({ left: 10, right: 10 })
      .onClick(() => {
        this.selectSource(source.id);
      })
  }

  private getTitleBarActions(): SettingsImmersiveTitleActionItem[] {
    return [
      {
        id: 'refresh',
        label: '刷新',
        symbol: $r('sys.symbol.arrow_clockwise'),
        enabled: !this.isLoading,
        onClick: () => {
          void this.initializeAndLoad();
        }
      }
    ];
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
            .layoutWeight(1)
            .justifyContent(FlexAlign.Center)
            .alignItems(HorizontalAlign.Center)
          } else {
            Scroll() {
              Column({ space: 10 }) {
                Column({ space: 10 }) {
                  Text('调试源选择')
                    .width('100%')
                    .fontSize(14)
                    .fontWeight(FontWeight.Medium)
                    .fontFamily(this.appFontFamily)
                    .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_primary', this.themeState.currentTheme))

                  Scroll() {
                    Row({ space: 8 }) {
                      ForEach(this.sources, (source: RssSubscriptionSource) => {
                        this.buildSourceButton(source)
                      }, (source: RssSubscriptionSource) => source.id)
                    }
                    .width('100%')
                  }
                  .width('100%')
                  .scrollable(ScrollDirection.Horizontal)
                  .scrollBar(BarState.Off)

                  if (this.selectedSource) {
                    Column({ space: 6 }) {
                      Text(`名称: ${this.selectedSource.name}`)
                        .width('100%')
                        .fontSize(12)
                        .fontFamily(this.appFontFamily)

                      Text(`URL: ${this.selectedSource.url}`)
                        .width('100%')
                        .fontSize(12)
                        .fontFamily(this.appFontFamily)

                      Text(`最近成功: ${this.formatTime(this.selectedSource.lastSuccessTime)}`)
                        .width('100%')
                        .fontSize(12)
                        .fontFamily(this.appFontFamily)

                      Text(`下次到期: ${this.getNextDueTimeText(this.selectedSource)}`)
                        .width('100%')
                        .fontSize(12)
                        .fontFamily(this.appFontFamily)
                        .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_secondary', this.themeState.currentTheme))
                    }
                    .width('100%')
                    .padding(12)
                    .backgroundColor(ThemeAwareHelper.getTestManagementThemedColor('background_secondary', this.themeState.currentTheme))
                    .borderRadius(10)

                    Row({ space: 10 }) {
                      TextInput({ placeholder: '预览条数', text: $$this.previewLimitText })
                        .width('30%')
                        .height(36)
                        .fontSize(12)
                        .fontFamily(this.appFontFamily)
                        .backgroundColor(ThemeAwareHelper.getTestManagementThemedColor('panel_background', this.themeState.currentTheme))
                        .borderRadius(8)

                      Button(this.isRunning ? '执行中...' : '刷新源')
                        .height(36)
                        .layoutWeight(1)
                        .fontSize(12)
                        .fontFamily(this.appFontFamily)
                        .fontColor('#FFFFFF')
                        .backgroundColor(ThemeAwareHelper.getTestManagementThemedColor('accent_primary', this.themeState.currentTheme))
                        .borderRadius(18)
                        .enabled(!this.isRunning)
                        .onClick(() => {
                          this.runRefreshDebug();
                        })

                      Button(this.isRunning ? '执行中...' : '规则预览')
                        .height(36)
                        .layoutWeight(1)
                        .fontSize(12)
                        .fontFamily(this.appFontFamily)
                        .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_primary', this.themeState.currentTheme))
                        .backgroundColor(ThemeAwareHelper.getTestManagementThemedColor('panel_background', this.themeState.currentTheme))
                        .borderRadius(18)
                        .enabled(!this.isRunning)
                        .onClick(() => {
                          this.runRulePreviewDebug();
                        })
                    }
                    .width('100%')
                  }
                }
                .width('100%')
                .padding({ left: 16, right: 16, top: 12, bottom: 12 })
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

                Column({ space: 10 }) {
                  Row() {
                    Button('清空输出')
                      .height(32)
                      .fontSize(12)
                      .fontFamily(this.appFontFamily)
                      .backgroundColor(ThemeAwareHelper.getTestManagementThemedColor('panel_background', this.themeState.currentTheme))
                      .borderRadius(16)
                      .onClick(() => {
                        this.clearDebugOutput();
                      })
                  }
                  .width('100%')
                  .justifyContent(FlexAlign.End)

                  Column({ space: 6 }) {
                    Text('调试输出')
                      .width('100%')
                      .fontSize(14)
                      .fontWeight(FontWeight.Medium)
                      .fontFamily(this.appFontFamily)
                      .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_primary', this.themeState.currentTheme))

                    Scroll() {
                      Text(this.debugOutput.length > 0 ? this.debugOutput : '暂无调试输出')
                        .width('100%')
                        .fontSize(12)
                        .fontFamily(this.appFontFamily)
                        .lineHeight(20)
                        .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_primary', this.themeState.currentTheme))
                        .textAlign(TextAlign.Start)
                    }
                    .width('100%')
                    .height(320)
                    .padding(10)
                    .backgroundColor(ThemeAwareHelper.getTestManagementThemedColor('background_secondary', this.themeState.currentTheme))
                    .borderRadius(10)
                    .scrollBar(BarState.Auto)
                    .edgeEffect(EdgeEffect.Spring)
                  }
                  .width('100%')
                }
                .width('100%')
                .padding({ left: 16, right: 16, top: 12, bottom: 12 })
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
              .width('100%')
              .padding({ left: 12, right: 12, top: 8, bottom: 18 + this.navigationBarHeight })
            }
            .width('100%')
            .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.TOP, SafeAreaEdge.BOTTOM])
            .layoutWeight(1)
            .scrollBar(BarState.Off)
            .edgeEffect(EdgeEffect.Spring)
          }
        }
        .width('100%')
        .height('100%')
        .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.TOP, SafeAreaEdge.BOTTOM])
        .padding({ bottom: this.navigationBarHeight })

        SettingsImmersiveTitleBar({
          themeState: this.themeState,
          title: '订阅源调试',
          appFontFamily: this.appFontFamily,
          actions: this.getTitleBarActions()
        })
      }
    }
    .hideTitleBar(true)
    .ignoreLayoutSafeArea([LayoutSafeAreaType.SYSTEM], [LayoutSafeAreaEdge.TOP, LayoutSafeAreaEdge.BOTTOM])
    .onReady((context: RssSourceDebugContext) => {
      const param = context.pathInfo.param as RssSourceDebugPageParams | null;
      this.initialSourceId = param && param.sourceId ? param.sourceId : '';
      this.initializeAndLoad();
    })
    .backgroundColor(Color.Transparent)
  }
}
