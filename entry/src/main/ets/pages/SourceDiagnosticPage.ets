/**
 * 图源诊断中心
 */

import { HdsNavDestination } from '@kit.UIDesignKit';
import { logger } from 'manxia_core/src/main/ets/Utils/Logger';
import { ThemeAwareHelper, ThemeAwareState } from 'manxia_theme/src/main/ets/Framework/Components/ThemeAware';
import { ThemeManager, ThemeType } from 'manxia_theme/src/main/ets/Framework/Managers/ThemeManager';
import { FontAwareHelper, FontAwareState } from 'manxia_theme/src/main/ets/Framework/Components/FontAware';
import { SharedPageBackgroundLayer } from 'manxia_theme/src/main/ets/Framework/Components/SharedPageBackgroundLayer';
import { GlobalBackgroundLayerMode } from 'manxia_theme/src/main/ets/Framework/Components/GlobalBackgroundLayer';
import { SettingsImmersiveTitleBar } from './settings/SettingsImmersiveTitleBar';
import { SettingsImmersiveTitleActionItem, SettingsPageTitleBarManager } from 'manxia_features_ui/src/main/ets/pages/settings/SettingsPageTitleBarManager';
import { SettingsPanelSurfaceHelper } from 'manxia_features_ui/src/main/ets/pages/settings/SettingsPanelSurfaceHelper';
import { sourceDiagnosticManager } from 'manxia_source_engine/src/main/ets/Framework/SourceEditor/SourceDiagnosticManager';
import {
  ActionExecutionTrace,
  SourceDiagnosticEvent,
  SourceExecutionTrace,
  WorkflowExecutionTrace
} from 'manxia_source_engine/src/main/ets/Framework/SourceEditor/SourceDiagnosticTypes';
import { SourceDiagnosticPageParams } from 'manxia_source_engine/src/main/ets/Framework/SourceEditor/SourceEditorTypes';

const TAG = 'SourceDiagnosticPage';

@Component
export struct SourceDiagnosticPage {
  @State pathStack: NavPathStack = new NavPathStack();
  @State themeState: ThemeAwareState = new ThemeAwareState();
  @State fontState: FontAwareState = new FontAwareState();
  @StorageLink('appFontFamily') appFontFamily: string = 'HarmonyOS Sans';
  @StorageProp('statusBarHeight') statusBarHeight: number = 0;
  @StorageProp('navigationBarHeight') navigationBarHeight: number = 0;

  @State traces: SourceExecutionTrace[] = [];
  @State selectedTraceId: string = '';
  @State exportText: string = '';
  @State sourceId: number = 0;
  @State sourceName: string = '';

  private componentId: string = `SourceDiagnosticPage_${Date.now()}`;
  private themeManager: ThemeManager = ThemeManager.getInstance();

  aboutToAppear() {
    ThemeAwareHelper.initializeThemeAware(this.componentId, this.themeState, (theme: ThemeType) => {
      logger.info(TAG, `主题切换: ${theme}`);
    });
    FontAwareHelper.initializeFontAware(this.componentId, this.fontState, (newState: FontAwareState) => {
      this.fontState = newState;
    });
  }

  aboutToDisappear() {
    ThemeAwareHelper.cleanupThemeAware(this.componentId);
    FontAwareHelper.cleanupFontAware(this.componentId);
  }

  private loadParams(params: SourceDiagnosticPageParams | null): void {
    if (params) {
      this.sourceId = params.sourceId || 0;
      this.sourceName = params.sourceName || '';
      this.selectedTraceId = params.traceId || '';
    }
    this.refreshTraces();
  }

  private refreshTraces(): void {
    const allTraces: SourceExecutionTrace[] = sourceDiagnosticManager.getRecentTraces();
    const filtered: SourceExecutionTrace[] = [];
    for (let i = 0; i < allTraces.length; i++) {
      const trace = allTraces[i];
      const matchesSource: boolean = this.sourceId <= 0 || trace.sourceId === this.sourceId;
      const matchesTrace: boolean = this.selectedTraceId.length <= 0 || trace.traceId === this.selectedTraceId;
      if (matchesSource && matchesTrace) {
        filtered.push(trace);
      }
    }
    this.traces = filtered;
    if (this.traces.length > 0 && this.selectedTraceId.length <= 0) {
      this.selectedTraceId = this.traces[0].traceId;
    }
    this.refreshExportText();
  }

  private refreshExportText(): void {
    if (this.selectedTraceId.length > 0) {
      this.exportText = sourceDiagnosticManager.exportTraceText(this.selectedTraceId);
    } else if (this.traces.length > 0) {
      this.exportText = sourceDiagnosticManager.exportTraceText(this.traces[0].traceId);
    } else {
      this.exportText = '';
    }
  }

  private handleBack(): boolean {
    try {
      this.pathStack.pop();
      return true;
    } catch (error) {
      logger.warn(TAG, `返回失败: ${String(error)}`);
      return false;
    }
  }

  private getTitleBarActions(): SettingsImmersiveTitleActionItem[] {
    return [{
      id: 'refresh',
      symbol: $r('sys.symbol.arrow_clockwise'),
      label: '刷新',
      onClick: () => {
        this.refreshTraces();
      },
      enabled: true
    }];
  }

  private getResultText(success: boolean): string {
    return success ? '成功' : '失败';
  }

  private formatDuration(duration: number): string {
    return `${duration}ms`;
  }

  build() {
    HdsNavDestination() {
      Stack() {
        SharedPageBackgroundLayer({
          defaultBackgroundColor: ThemeAwareHelper.getTestManagementThemedColor('background_dark', this.themeState.currentTheme),
          mode: GlobalBackgroundLayerMode.IMMERSIVE
        })
          .width('100%')
          .height('100%')
          .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.TOP, SafeAreaEdge.BOTTOM])

        Column() {
          Blank().height(SettingsPageTitleBarManager.getContentTopPadding(this.statusBarHeight))

          if (this.traces.length === 0) {
            this.buildEmptyView()
          } else {
            this.buildTraceList()
          }
        }
        .width('100%')
        .height('100%')

        SettingsImmersiveTitleBar({
          themeState: this.themeState,
          title: this.sourceName.length > 0 ? `${this.sourceName}诊断` : '图源诊断',
          appFontFamily: this.appFontFamily,
          actions: this.getTitleBarActions()
        })
      }
      .width('100%')
      .height('100%')
    }
    .hideTitleBar(true)
    .ignoreLayoutSafeArea([LayoutSafeAreaType.SYSTEM], [LayoutSafeAreaEdge.TOP, LayoutSafeAreaEdge.BOTTOM])
    .backgroundColor(Color.Transparent)
    .onBackPressed(() => {
      return this.handleBack();
    })
    .onReady((context: NavDestinationContext) => {
      this.pathStack = context.pathStack;
      const params = context.pathInfo.param as SourceDiagnosticPageParams | null;
      this.loadParams(params);
    })
  }

  @Builder
  private buildEmptyView() {
    Column({ space: 12 }) {
      SymbolGlyph($r('sys.symbol.magnifyingglass'))
        .fontSize(42)
        .fontColor([ThemeAwareHelper.getTestManagementThemedColor('text_tertiary', this.themeState.currentTheme)])
      Text('暂无诊断记录')
        .fontSize(16)
        .fontFamily(this.appFontFamily)
        .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_secondary', this.themeState.currentTheme))
      Button('刷新')
        .height(36)
        .onClick(() => {
          this.refreshTraces();
        })
    }
    .width('100%')
    .height('100%')
    .justifyContent(FlexAlign.Center)
    .alignItems(HorizontalAlign.Center)
  }

  @Builder
  private buildTraceList() {
    Scroll() {
      Column({ space: 14 }) {
        ForEach(this.traces, (trace: SourceExecutionTrace) => {
          this.buildTraceCard(trace)
        }, (trace: SourceExecutionTrace) => trace.traceId)

        if (this.exportText.length > 0) {
          this.buildExportPanel()
        }

        Blank().height(24 + this.navigationBarHeight)
      }
      .width('100%')
      .padding({ left: 16, right: 16, bottom: 12 })
    }
    .layoutWeight(1)
    .scrollBar(BarState.Auto)
    .edgeEffect(EdgeEffect.Spring)
  }

  @Builder
  private buildTraceCard(trace: SourceExecutionTrace) {
    Column({ space: 12 }) {
      Row() {
        Column({ space: 4 }) {
          Text(`${trace.workflowName} · ${this.getResultText(trace.success)}`)
            .fontSize(16)
            .fontWeight(FontWeight.Medium)
            .fontFamily(this.appFontFamily)
            .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_primary', this.themeState.currentTheme))
          Text(`${trace.sourceName} · ${this.formatDuration(trace.duration)} · ${trace.traceId}`)
            .fontSize(11)
            .fontFamily(this.appFontFamily)
            .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_muted', this.themeState.currentTheme))
            .maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
        }
        .layoutWeight(1)
        .alignItems(HorizontalAlign.Start)

        Button('导出')
          .height(32)
          .fontSize(12)
          .onClick(() => {
            this.selectedTraceId = trace.traceId;
            this.refreshExportText();
            this.getUIContext().getPromptAction().showToast({ message: '已生成脱敏诊断文本' });
          })
      }
      .width('100%')

      if (trace.errorMessage.length > 0) {
        Text(trace.errorMessage)
          .fontSize(13)
          .fontFamily(this.appFontFamily)
          .fontColor(ThemeAwareHelper.getTestManagementThemedColor('color_error', this.themeState.currentTheme))
      }

      ForEach(trace.workflows, (workflow: WorkflowExecutionTrace) => {
        this.buildWorkflowTrace(workflow)
      }, (workflow: WorkflowExecutionTrace) => `${workflow.traceId}_${workflow.workflowName}`)

      this.buildEventList(trace.events)
    }
    .width('100%')
    .padding(14)
    .backgroundColor(SettingsPanelSurfaceHelper.getBackground(this.themeState.currentTheme))
    .linearGradient(SettingsPanelSurfaceHelper.getSurfaceGradient(this.themeState.currentTheme))
    .borderRadius(SettingsPanelSurfaceHelper.getRadius(this.themeState.currentTheme))
    .border({
      width: SettingsPanelSurfaceHelper.getBorderWidth(this.themeState.currentTheme),
      color: SettingsPanelSurfaceHelper.getBorderColor(this.themeState.currentTheme)
    })
  }

  @Builder
  private buildWorkflowTrace(workflow: WorkflowExecutionTrace) {
    Column({ space: 8 }) {
      Text(`Action ${workflow.actions.length}`)
        .fontSize(12)
        .fontFamily(this.appFontFamily)
        .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_secondary', this.themeState.currentTheme))
      ForEach(workflow.actions, (action: ActionExecutionTrace) => {
        this.buildActionTrace(action)
      }, (action: ActionExecutionTrace) => `${action.traceId}_${action.actionIndex}_${action.startTime}`)
    }
    .width('100%')
  }

  @Builder
  private buildActionTrace(action: ActionExecutionTrace) {
    Row({ space: 10 }) {
      Text(String(action.actionIndex + 1))
        .fontSize(12)
        .fontWeight(FontWeight.Bold)
        .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_white', this.themeState.currentTheme))
        .width(24)
        .height(24)
        .textAlign(TextAlign.Center)
        .backgroundColor(action.success ? ThemeAwareHelper.getTestManagementThemedColor('accent_green', this.themeState.currentTheme) : ThemeAwareHelper.getTestManagementThemedColor('color_error', this.themeState.currentTheme))
        .borderRadius(12)

      Column({ space: 3 }) {
        Text(`${action.actionType} · ${this.getResultText(action.success)} · ${this.formatDuration(action.duration)}`)
          .fontSize(13)
          .fontFamily(this.appFontFamily)
          .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_primary', this.themeState.currentTheme))
        if (action.actionDescription.length > 0) {
          Text(action.actionDescription)
            .fontSize(11)
            .fontFamily(this.appFontFamily)
            .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_muted', this.themeState.currentTheme))
        }
        if (action.errorMessage.length > 0) {
          Text(action.errorMessage)
            .fontSize(11)
            .fontFamily(this.appFontFamily)
            .fontColor(ThemeAwareHelper.getTestManagementThemedColor('color_error', this.themeState.currentTheme))
        }
        if (action.currentUrl.length > 0) {
          Text(action.currentUrl)
            .fontSize(10)
            .fontFamily(this.appFontFamily)
            .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_tertiary', this.themeState.currentTheme))
            .maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
        }
      }
      .layoutWeight(1)
      .alignItems(HorizontalAlign.Start)
    }
    .width('100%')
  }

  @Builder
  private buildEventList(events: SourceDiagnosticEvent[]) {
    Column({ space: 4 }) {
      Text('事件')
        .fontSize(12)
        .fontFamily(this.appFontFamily)
        .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_secondary', this.themeState.currentTheme))
      ForEach(events.slice(0, 8), (event: SourceDiagnosticEvent) => {
        Text(`[${event.level}] ${event.kind} ${event.message}`)
          .fontSize(10)
          .fontFamily(this.appFontFamily)
          .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_tertiary', this.themeState.currentTheme))
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
      }, (event: SourceDiagnosticEvent) => event.id)
    }
    .width('100%')
  }

  @Builder
  private buildExportPanel() {
    Column({ space: 8 }) {
      Text('脱敏诊断文本')
        .fontSize(14)
        .fontWeight(FontWeight.Medium)
        .fontFamily(this.appFontFamily)
        .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_primary', this.themeState.currentTheme))
      TextArea({ text: this.exportText })
        .fontSize(11)
        .fontFamily(this.appFontFamily)
        .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_secondary', this.themeState.currentTheme))
        .height(180)
        .backgroundColor(ThemeAwareHelper.getTestManagementThemedColor('background_secondary', this.themeState.currentTheme))
    }
    .width('100%')
    .padding(14)
    .backgroundColor(SettingsPanelSurfaceHelper.getBackground(this.themeState.currentTheme))
    .borderRadius(SettingsPanelSurfaceHelper.getRadius(this.themeState.currentTheme))
  }
}
