/**
 * 图源编辑器应用内工作流检查小窗
 */

import { common } from '@kit.AbilityKit';
import { logger } from 'manxia_core/src/main/ets/Utils/Logger';
import { SafeUtils } from 'manxia_core/src/main/ets/Utils/SafeUtils';
import { WindowManager } from '../Utils/WindowManager';
import { interactiveSourceEditorService } from '../Framework/SourceEditor/InteractiveSourceEditorService';
import {
  SourceEditorGuidePhase,
  SourceEditorWorkflowGuideStep,
  SourceEditorWorkflowPreviewStatus,
  SourceInteractiveEditorPageParams,
  SourceSaveMode
} from 'manxia_source_engine/src/main/ets/Framework/SourceEditor/SourceEditorTypes';
import {
  createEmptySourceEditorInspectorSnapshot,
  SOURCE_EDITOR_INSPECTOR_SNAPSHOT_JSON_KEY,
  SOURCE_EDITOR_INSPECTOR_SNAPSHOT_SIGNAL_KEY,
  SourceEditorInspectorSnapshot,
  sourceEditorInspectorStateManager
} from 'manxia_source_engine/src/main/ets/Framework/SourceEditor/SourceEditorInspectorStateManager';

const TAG: string = 'SourceEditorFloatingInspectorPage';
const REFRESH_INTERVAL_MS: number = 250;
const FLOATING_TOAST_BOTTOM_VP: number = 10;
const FLOATING_BUTTON_DEFAULT: number = 0;
const FLOATING_BUTTON_PRIMARY: number = 1;
const FLOATING_BUTTON_SUCCESS: number = 2;
const FLOATING_BUTTON_DANGER: number = 3;
const PREVIEW_PANEL_HEIGHT_VP: number = 150;
const SELECTION_PANEL_HEIGHT_VP: number = 122;

@Entry
@Component
struct SourceEditorFloatingInspectorPage {
  private refreshTimerId: number = -1;
  private dragStartWindowX: number = 0;
  private dragStartWindowY: number = 0;
  private isDraggingWindow: boolean = false;
  private lastAppliedSnapshotSignal: number = -1;

  @StorageLink('appFontFamily') appFontFamily: string = 'HarmonyOS Sans';
  @StorageLink(SOURCE_EDITOR_INSPECTOR_SNAPSHOT_JSON_KEY) private inspectorSnapshotJson: string = '';
  @StorageLink(SOURCE_EDITOR_INSPECTOR_SNAPSHOT_SIGNAL_KEY) @Watch('onSnapshotStorageChanged')
  private inspectorSnapshotSignal: number = -1;
  @State private viewState: SourceEditorInspectorSnapshot = createEmptySourceEditorInspectorSnapshot();
  @State private displayRenderVersion: number = 0;
  @State private displayHasStep: boolean = false;
  @State private displayProgressText: string = '未生成向导';
  @State private displayGuidePhase: SourceEditorGuidePhase = SourceEditorGuidePhase.PREVIEW;
  @State private displayGuidePhaseText: string = '检查当前工作流';
  @State private displaySaveMessage: string = '';
  @State private displayTaskLabel: string = '';
  @State private displayTaskDescription: string = '';
  @State private displayExpectedDomLabel: string = '';
  @State private displaySelectionInstruction: string = '';
  @State private displayActionCount: number = 0;
  @State private displayPreviewStatus: SourceEditorWorkflowPreviewStatus = SourceEditorWorkflowPreviewStatus.WAITING;
  @State private displayPreviewStatusText: string = '等待';
  @State private displaySelectorCount: number = 0;
  @State private displayScriptCount: number = 0;
  @State private displayPreviewSummary: string = '等待页面加载';
  @State private displayPreviewDetail: string = '';
  @State private displayPreviewSampleTitle: string = '';
  @State private displayPreviewSampleUrl: string = '';
  @State private displayPreviewErrorMessage: string = '';
  @State private displayPreviewAdviceText: string = '页面加载完成后会自动识别；若停留过久，请确认网页已打开到目标区域。';
  @State private displaySelectionMessage: string = '点击“不正常”后，在页面上选择当前工作流需要的 DOM。';
  @State private displaySelectionDetail: string = '';
  @State private displaySelectionScore: number = 0;
  @State private displayRecommendedSelector: string = '';
  @State private isSaving: boolean = false;
  @State private isToastVisible: boolean = false;
  @State private toastMessage: string = '';

  aboutToAppear(): void {
    const abilityContext = this.resolveAbilityContext();
    if (abilityContext !== null) {
      interactiveSourceEditorService.setAbilityContext(abilityContext);
    }
    this.refreshSnapshot();
    this.startRefreshTimer();
  }

  aboutToDisappear(): void {
    this.stopRefreshTimer();
  }

  private resolveAbilityContext(): common.UIAbilityContext | null {
    try {
      const hostContext = this.getUIContext().getHostContext() as common.UIAbilityContext;
      if (!hostContext) {
        return null;
      }
      return hostContext;
    } catch (error) {
      logger.warn(TAG, `获取图源检查器AbilityContext失败: ${String(error)}`);
      return null;
    }
  }

  private startRefreshTimer(): void {
    this.stopRefreshTimer();
    this.refreshTimerId = setInterval((): void => {
      this.refreshSnapshot();
    }, REFRESH_INTERVAL_MS);
  }

  private stopRefreshTimer(): void {
    if (this.refreshTimerId >= 0) {
      clearInterval(this.refreshTimerId);
      this.refreshTimerId = -1;
    }
  }

  onSnapshotStorageChanged(changedPropertyName?: string): void {
    this.refreshSnapshot();
  }

  private refreshSnapshot(): void {
    if (this.inspectorSnapshotSignal >= 0 && this.inspectorSnapshotJson.length > 0) {
      const snapshot: SourceEditorInspectorSnapshot =
        SafeUtils.parseObj<SourceEditorInspectorSnapshot>(this.inspectorSnapshotJson);
      if (this.isValidSnapshot(snapshot)) {
        if (this.inspectorSnapshotSignal !== this.lastAppliedSnapshotSignal ||
          snapshot.renderVersion !== this.viewState.renderVersion) {
          this.viewState = snapshot;
          this.lastAppliedSnapshotSignal = this.inspectorSnapshotSignal;
          this.applyDisplaySnapshot(snapshot);
          this.logAppliedSnapshot(snapshot, 'storage');
        }
        return;
      }
    }

    const fallbackSnapshot: SourceEditorInspectorSnapshot = sourceEditorInspectorStateManager.getSnapshot();
    if (!this.viewState.hasDraft && fallbackSnapshot.renderVersion !== this.viewState.renderVersion) {
      this.viewState = fallbackSnapshot;
      this.lastAppliedSnapshotSignal = fallbackSnapshot.renderVersion;
      this.applyDisplaySnapshot(fallbackSnapshot);
      this.logAppliedSnapshot(fallbackSnapshot, 'manager');
    }
  }

  private applyDisplaySnapshot(snapshot: SourceEditorInspectorSnapshot): void {
    this.displayRenderVersion = snapshot.renderVersion;
    this.displayGuidePhase = snapshot.guidePhase;
    this.displayGuidePhaseText = snapshot.guidePhaseText;
    this.displaySaveMessage = snapshot.saveMessage;
    if (snapshot.workflowCount <= 0) {
      this.displayProgressText = '未生成向导';
    } else {
      this.displayProgressText = `${snapshot.guideIndex + 1}/${snapshot.workflowCount}`;
    }

    const step: SourceEditorWorkflowGuideStep | null = snapshot.currentStep;
    if (step === null) {
      this.displayHasStep = false;
      this.displayTaskLabel = '';
      this.displayTaskDescription = '';
      this.displayExpectedDomLabel = '';
      this.displaySelectionInstruction = '';
      this.displayActionCount = 0;
      this.displayPreviewStatus = SourceEditorWorkflowPreviewStatus.WAITING;
      this.displayPreviewStatusText = this.getPreviewStatusText(SourceEditorWorkflowPreviewStatus.WAITING);
      this.displaySelectorCount = 0;
      this.displayScriptCount = 0;
      this.displayPreviewSummary = '等待页面加载';
      this.displayPreviewDetail = '';
      this.displayPreviewSampleTitle = '';
      this.displayPreviewSampleUrl = '';
      this.displayPreviewErrorMessage = '';
      this.displayPreviewAdviceText =
        this.getPreviewAdviceText(SourceEditorWorkflowPreviewStatus.WAITING);
      this.displaySelectionMessage = '点击“不正常”后，在页面上选择当前工作流需要的 DOM。';
      this.displaySelectionDetail = '';
      this.displaySelectionScore = 0;
      this.displayRecommendedSelector = '';
      this.logDisplaySnapshot();
      return;
    }

    this.displayHasStep = true;
    this.displayExpectedDomLabel = step.expectedDomLabel;
    this.displaySelectionInstruction = step.selectionInstruction;
    this.displayActionCount = step.actionCount;
    this.displayPreviewStatus = step.preview.status;
    this.displaySelectorCount = step.preview.selectorCount;
    this.displayScriptCount = step.preview.scriptCount;
    if (snapshot.guidePhase === SourceEditorGuidePhase.COMPLETE) {
      this.displayTaskLabel = '检查完成';
      this.displayTaskDescription = `已完成 ${snapshot.workflowCount} 个工作流检查，请保存本地派生副本。`;
      this.displayPreviewStatus = SourceEditorWorkflowPreviewStatus.OK;
      this.displayPreviewStatusText = '完成';
      this.displayPreviewSummary = `全部工作流已检查完成，最后检查项：${step.label}`;
      this.displayPreviewDetail = step.preview.summary.length > 0 ? step.preview.summary : step.description;
      this.displayPreviewAdviceText = '当前图源的搜索、详情、章节、图片流程已完成检查。请点击“保存副本”，保存后再到本地图源中试用。';
    } else {
      this.displayTaskLabel = step.label;
      this.displayTaskDescription = step.description;
      this.displayPreviewStatusText = this.getPreviewStatusText(step.preview.status);
      this.displayPreviewSummary = step.preview.summary;
      this.displayPreviewDetail = step.preview.detail;
      this.displayPreviewAdviceText = this.getPreviewAdviceText(step.preview.status);
    }
    this.displayPreviewSampleTitle = step.preview.sampleTitle;
    this.displayPreviewSampleUrl = step.preview.sampleUrl;
    this.displayPreviewErrorMessage = step.preview.errorMessage;
    this.displaySelectionMessage = step.selectionAssessment.message;
    this.displaySelectionDetail = step.selectionAssessment.detail;
    this.displaySelectionScore = step.selectionAssessment.score;
    this.displayRecommendedSelector = step.selectionAssessment.recommendedSelector;
    this.logDisplaySnapshot();
  }

  private logDisplaySnapshot(): void {
    logger.debug(
      TAG,
      `显示检查器状态: version=${this.displayRenderVersion}, status=${this.displayPreviewStatus}, ` +
        `statusText=${this.displayPreviewStatusText}, selector=${this.displaySelectorCount}, ` +
        `script=${this.displayScriptCount}, summary=${this.displayPreviewSummary}`
    );
  }

  private isValidSnapshot(snapshot: SourceEditorInspectorSnapshot): boolean {
    return typeof snapshot.renderVersion === 'number' &&
      typeof snapshot.hasDraft === 'boolean' &&
      typeof snapshot.sourceName === 'string' &&
      typeof snapshot.guidePhaseText === 'string';
  }

  private logAppliedSnapshot(snapshot: SourceEditorInspectorSnapshot, source: string): void {
    const step: SourceEditorWorkflowGuideStep | null = snapshot.currentStep;
    if (step === null) {
      logger.debug(TAG, `应用检查器快照: source=${source}, version=${snapshot.renderVersion}, step=null`);
      return;
    }
    logger.debug(
      TAG,
      `应用检查器快照: source=${source}, version=${snapshot.renderVersion}, status=${step.preview.status}, ` +
        `selector=${step.preview.selectorCount}, script=${step.preview.scriptCount}`
    );
  }

  private async handleSaveLocalFork(): Promise<void> {
    if (this.isSaving) {
      return;
    }
    const draft = sourceEditorInspectorStateManager.getCurrentDraft();
    if (draft === null) {
      this.showLocalToast('草稿未就绪');
      return;
    }
    this.isSaving = true;
    try {
      const result = await interactiveSourceEditorService.saveDraft(draft, SourceSaveMode.LOCAL_FORK);
      sourceEditorInspectorStateManager.updateSaveMessage(result.message);
      this.refreshSnapshot();
      this.showLocalToast(result.message);
    } catch (error) {
      const message = `保存失败: ${String(error)}`;
      sourceEditorInspectorStateManager.updateSaveMessage(message);
      this.refreshSnapshot();
      this.showLocalToast('保存失败');
      logger.error(TAG, message);
    } finally {
      this.isSaving = false;
    }
  }

  private handleOpenEditorPage(): void {
    try {
      const draft = sourceEditorInspectorStateManager.getCurrentDraft();
      if (draft === null) {
        this.showLocalToast('草稿未就绪');
        return;
      }
      const globalStack = AppStorage.get<NavPathStack>('GlobalNavStack');
      if (!globalStack) {
        this.showLocalToast('主导航暂不可用');
        return;
      }
      const params: SourceInteractiveEditorPageParams = {
        sourceId: draft.sourceId,
        sourceName: draft.sourceName,
        sourcePkg: draft.sourcePkg,
        initialUrl: draft.testUrl,
        createNew: draft.sourceId <= 0
      };
      globalStack.pushPathByName('SourceInteractiveEditorPage', params);
      this.showLocalToast('已打开编辑页');
    } catch (error) {
      logger.warn(TAG, `小窗打开图源编辑页失败: ${String(error)}`);
      this.showLocalToast('打开失败');
    }
  }

  private async handleCloseWindow(): Promise<void> {
    await WindowManager.closeAppFloatingWindow('图源检查器小窗按钮关闭');
  }

  private handleWorkflowNormal(): void {
    sourceEditorInspectorStateManager.markCurrentWorkflowNormal();
    this.refreshSnapshot();
    this.showLocalToast('已进入下一步');
  }

  private handleWorkflowAbnormal(): void {
    sourceEditorInspectorStateManager.markCurrentWorkflowAbnormal();
    this.refreshSnapshot();
    this.showLocalToast('请在页面上点选目标 DOM');
  }

  private handlePreviousWorkflow(): void {
    sourceEditorInspectorStateManager.moveToPreviousWorkflow();
    this.refreshSnapshot();
  }

  private showLocalToast(message: string): void {
    this.toastMessage = message;
    this.isToastVisible = true;
    setTimeout((): void => {
      this.isToastVisible = false;
    }, 1300);
  }

  private getDisplayValue(value: string): string {
    return value.length > 0 ? value : '-';
  }

  private getProgressText(): string {
    return this.displayProgressText;
  }

  private getPreviewStatusText(status: SourceEditorWorkflowPreviewStatus): string {
    if (status === SourceEditorWorkflowPreviewStatus.RUNNING) {
      return '识别中';
    }
    if (status === SourceEditorWorkflowPreviewStatus.OK) {
      return '已识别';
    }
    if (status === SourceEditorWorkflowPreviewStatus.EMPTY) {
      return '未命中';
    }
    if (status === SourceEditorWorkflowPreviewStatus.ERROR) {
      return '异常';
    }
    return '等待';
  }

  private getPreviewStatusTitle(status: SourceEditorWorkflowPreviewStatus): string {
    if (status === SourceEditorWorkflowPreviewStatus.OK) {
      return '识别成功';
    }
    if (status === SourceEditorWorkflowPreviewStatus.RUNNING) {
      return '正在识别';
    }
    if (status === SourceEditorWorkflowPreviewStatus.EMPTY) {
      return '未找到匹配内容';
    }
    if (status === SourceEditorWorkflowPreviewStatus.ERROR) {
      return '识别异常';
    }
    return '等待页面加载';
  }

  private getPreviewPanelTitle(): string {
    if (this.displayGuidePhase === SourceEditorGuidePhase.COMPLETE) {
      return '完成结果';
    }
    return '识别结果';
  }

  private getPreviewStatusBadgeText(): string {
    if (this.displayGuidePhase === SourceEditorGuidePhase.COMPLETE) {
      return '可以保存';
    }
    return this.getPreviewStatusTitle(this.displayPreviewStatus);
  }

  private getPreviewAdviceText(status: SourceEditorWorkflowPreviewStatus): string {
    if (status === SourceEditorWorkflowPreviewStatus.OK) {
      return '请检查样本是否符合预期。符合就点“正常”，不符合就点“不正常”重新选择。';
    }
    if (status === SourceEditorWorkflowPreviewStatus.RUNNING) {
      return '正在读取页面和执行规则，请等待识别完成。';
    }
    if (status === SourceEditorWorkflowPreviewStatus.EMPTY) {
      return '请先在网页中滚动或翻到目标内容区域，再点“不正常”重新选择对应 DOM。';
    }
    if (status === SourceEditorWorkflowPreviewStatus.ERROR) {
      return '请先切到目标内容所在区域，再重新选择对应 DOM；脚本或选择器可能需要调整。';
    }
    return '页面加载完成后会自动识别；若停留过久，请确认网页已打开到目标区域。';
  }

  private getPreviewStatusColor(status: SourceEditorWorkflowPreviewStatus): Resource {
    if (status === SourceEditorWorkflowPreviewStatus.OK) {
      return $r('app.color.color_success');
    }
    if (status === SourceEditorWorkflowPreviewStatus.EMPTY) {
      return $r('app.color.color_warning');
    }
    if (status === SourceEditorWorkflowPreviewStatus.ERROR) {
      return $r('app.color.color_error');
    }
    if (status === SourceEditorWorkflowPreviewStatus.RUNNING) {
      return $r('app.color.color_info');
    }
    return $r('sys.color.brand');
  }

  private getDisplayStatusColor(): Resource {
    if (this.displayGuidePhase === SourceEditorGuidePhase.COMPLETE) {
      return $r('app.color.color_info');
    }
    return this.getPreviewStatusColor(this.displayPreviewStatus);
  }

  private getButtonBackgroundColor(style: number): Resource {
    if (style === FLOATING_BUTTON_SUCCESS) {
      return $r('app.color.color_success');
    }
    if (style === FLOATING_BUTTON_DANGER) {
      return $r('app.color.color_error');
    }
    if (style === FLOATING_BUTTON_PRIMARY) {
      return $r('sys.color.brand');
    }
    return $r('sys.color.comp_background_secondary');
  }

  private getButtonTextColor(style: number): Resource {
    if (style === FLOATING_BUTTON_DEFAULT) {
      return $r('sys.color.font_primary');
    }
    return $r('sys.color.font_on_primary');
  }

  private getSelectionGuideText(): string {
    if (this.displayGuidePhase === SourceEditorGuidePhase.NEED_SELECTION) {
      if (this.displayExpectedDomLabel.length > 0) {
        return `请先在网页中滚动或翻到「${this.displayExpectedDomLabel}」所在区域，再点选对应 DOM。`;
      }
      return '请先在网页中滚动或翻到目标内容区域，再点选对应 DOM。';
    }
    return this.displaySelectionMessage;
  }

  private beginDragWindow(): void {
    const rect = WindowManager.getAppFloatingWindowRect();
    if (rect === null) {
      this.isDraggingWindow = false;
      return;
    }
    this.dragStartWindowX = rect.left;
    this.dragStartWindowY = rect.top;
    this.isDraggingWindow = true;
  }

  private updateDragWindow(event: GestureEvent): void {
    if (!this.isDraggingWindow) {
      return;
    }
    void WindowManager.moveAppFloatingWindowByVpOffset(
      this.dragStartWindowX,
      this.dragStartWindowY,
      event.offsetX,
      event.offsetY
    );
  }

  private endDragWindow(): void {
    this.isDraggingWindow = false;
  }

  @Builder
  private buildIconButton(icon: Resource, onClick: () => void) {
    Button() {
      SymbolGlyph(icon)
        .fontSize(15)
        .fontColor([$r('sys.color.font_primary')])
    }
    .width(30)
    .height(30)
    .borderRadius(15)
    .backgroundColor($r('sys.color.comp_background_secondary'))
    .onClick((): void => {
      onClick();
    })
  }

  @Builder
  private buildHeader() {
    Row({ space: 8 }) {
      Column() {
        SymbolGlyph($r('sys.symbol.magnifyingglass'))
          .fontSize(17)
          .fontColor([$r('sys.color.font_on_primary')])
      }
      .width(30)
      .height(30)
      .justifyContent(FlexAlign.Center)
      .backgroundColor($r('sys.color.brand'))
      .borderRadius(15)

      Column({ space: 2 }) {
        Text('图源检查器')
          .fontSize(13)
          .fontWeight(FontWeight.Bold)
          .fontFamily(this.appFontFamily)
          .fontColor($r('sys.color.font_primary'))
          .maxLines(1)

        Text(`${this.getProgressText()} · ${this.displayGuidePhaseText}`)
          .fontSize(10)
          .fontFamily(this.appFontFamily)
          .fontColor($r('sys.color.font_secondary'))
          .maxLines(1)
      }
      .layoutWeight(1)
      .alignItems(HorizontalAlign.Start)

      this.buildIconButton($r('sys.symbol.arrow_up_left_and_arrow_down_right'), (): void => {
        this.handleOpenEditorPage();
      })

      this.buildIconButton($r('sys.symbol.xmark'), (): void => {
        void this.handleCloseWindow();
      })
    }
    .width('100%')
    .gesture(
      PanGesture({ fingers: 1, direction: PanDirection.All, distance: 2 })
        .onActionStart((_event: GestureEvent): void => {
          this.beginDragWindow();
        })
        .onActionUpdate((event: GestureEvent): void => {
          this.updateDragWindow(event);
        })
        .onActionEnd((_event: GestureEvent): void => {
          this.endDragWindow();
        })
    )
  }

  @Builder
  private buildCurrentStep() {
    Column({ space: 6 }) {
      Row({ space: 8 }) {
        Text(this.displayTaskLabel)
          .fontSize(14)
          .fontWeight(FontWeight.Bold)
          .fontFamily(this.appFontFamily)
          .fontColor($r('sys.color.font_primary'))
          .maxLines(1)

        Text(this.displayPreviewStatusText)
          .fontSize(10)
          .fontFamily(this.appFontFamily)
          .fontColor($r('sys.color.font_on_primary'))
          .padding({ left: 8, right: 8, top: 2, bottom: 2 })
          .backgroundColor(this.getDisplayStatusColor())
          .borderRadius(10)
          .maxLines(1)
      }
      .width('100%')

      Text(this.displayTaskDescription)
        .fontSize(10)
        .fontFamily(this.appFontFamily)
        .fontColor($r('sys.color.font_secondary'))
        .maxLines(2)
        .textOverflow({ overflow: TextOverflow.Ellipsis })

      Row({ space: 8 }) {
        this.buildMetricText('动作', `${this.displayActionCount}`)
        this.buildMetricText('选择器', `${this.displaySelectorCount}`)
        this.buildMetricText('脚本', `${this.displayScriptCount}`)
      }
      .width('100%')
    }
    .width('100%')
    .padding({ left: 10, right: 10, top: 8, bottom: 8 })
    .backgroundColor($r('sys.color.comp_background_secondary'))
    .borderRadius(12)
  }

  @Builder
  private buildMetricText(label: string, value: string) {
    Row({ space: 4 }) {
      Text(label)
        .fontSize(10)
        .fontFamily(this.appFontFamily)
        .fontColor($r('sys.color.font_secondary'))
        .maxLines(1)
      Text(value)
        .fontSize(10)
        .fontWeight(FontWeight.Medium)
        .fontFamily(this.appFontFamily)
        .fontColor($r('sys.color.font_primary'))
        .maxLines(1)
    }
    .layoutWeight(1)
  }

  @Builder
  private buildPreviewPanel() {
    Row({ space: 8 }) {
      Column()
        .width(4)
        .height('100%')
        .backgroundColor(this.getDisplayStatusColor())
        .borderRadius(2)

      Scroll() {
        Column({ space: 7 }) {
          Row({ space: 6 }) {
            Text(this.getPreviewPanelTitle())
              .fontSize(12)
              .fontWeight(FontWeight.Bold)
              .fontFamily(this.appFontFamily)
              .fontColor(this.getDisplayStatusColor())
              .maxLines(1)

            Text(this.getPreviewStatusBadgeText())
              .fontSize(11)
              .fontFamily(this.appFontFamily)
              .fontColor($r('sys.color.font_on_primary'))
              .padding({ left: 8, right: 8, top: 2, bottom: 2 })
              .backgroundColor(this.getDisplayStatusColor())
              .borderRadius(10)
              .maxLines(1)
          }
          .width('100%')

          Text(this.displayPreviewSummary)
            .fontSize(13)
            .fontWeight(FontWeight.Medium)
            .fontFamily(this.appFontFamily)
            .fontColor($r('sys.color.font_primary'))
            .maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis })

          Text(this.displayPreviewAdviceText)
            .fontSize(12)
            .fontWeight(FontWeight.Medium)
            .fontFamily(this.appFontFamily)
            .fontColor(this.getDisplayStatusColor())
            .maxLines(2)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
            .lineHeight(17)

          Text(this.displayPreviewDetail.length > 0 ? this.displayPreviewDetail : this.displaySelectionInstruction)
            .fontSize(11)
            .fontFamily(this.appFontFamily)
            .fontColor($r('sys.color.font_secondary'))
            .maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
            .lineHeight(16)

          if (this.displayPreviewSampleTitle.length > 0 || this.displayPreviewSampleUrl.length > 0) {
            Text(`${this.getDisplayValue(this.displayPreviewSampleTitle)} · ${this.getDisplayValue(this.displayPreviewSampleUrl)}`)
              .fontSize(10)
              .fontFamily(this.appFontFamily)
              .fontColor($r('sys.color.font_secondary'))
              .maxLines(1)
              .textOverflow({ overflow: TextOverflow.Ellipsis })
          }

          if (this.displayPreviewErrorMessage.length > 0) {
            Text(this.displayPreviewErrorMessage)
              .fontSize(11)
              .fontFamily(this.appFontFamily)
              .fontColor($r('app.color.color_error'))
              .maxLines(1)
              .textOverflow({ overflow: TextOverflow.Ellipsis })
          }
        }
        .width('100%')
        .alignItems(HorizontalAlign.Start)
      }
      .layoutWeight(1)
      .height('100%')
      .scrollable(ScrollDirection.Vertical)
      .scrollBar(BarState.Auto)
    }
    .width('100%')
    .height(PREVIEW_PANEL_HEIGHT_VP)
    .padding({ left: 10, right: 10, top: 9, bottom: 9 })
    .backgroundColor($r('sys.color.comp_background_secondary'))
    .border({
      width: 1,
      color: this.getDisplayStatusColor()
    })
    .borderRadius(12)
  }

  @Builder
  private buildSelectionPanel() {
    Scroll() {
      Column({ space: 7 }) {
        Text(this.getSelectionGuideText())
          .fontSize(13)
          .fontWeight(FontWeight.Medium)
          .fontFamily(this.appFontFamily)
          .fontColor(this.displayGuidePhase === SourceEditorGuidePhase.NEED_SELECTION ?
            $r('app.color.color_warning') : $r('sys.color.font_primary'))
          .maxLines(3)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
          .lineHeight(18)

        if (this.displayGuidePhase === SourceEditorGuidePhase.NEED_SELECTION &&
          this.displaySelectionInstruction.length > 0) {
          Text(this.displaySelectionInstruction)
            .fontSize(11)
            .fontFamily(this.appFontFamily)
            .fontColor($r('sys.color.font_secondary'))
            .maxLines(2)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
            .lineHeight(16)
        }

        if (this.displayGuidePhase === SourceEditorGuidePhase.SELECTION_REVIEW) {
          Text(`${this.displaySelectionDetail} · ${this.displaySelectionScore}/100`)
            .fontSize(10)
            .fontFamily(this.appFontFamily)
            .fontColor($r('sys.color.font_secondary'))
            .maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
          Text(this.displayRecommendedSelector)
            .fontSize(10)
            .fontFamily('monospace')
            .fontColor($r('sys.color.font_secondary'))
            .maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
        }
      }
      .width('100%')
      .alignItems(HorizontalAlign.Start)
    }
    .width('100%')
    .height(SELECTION_PANEL_HEIGHT_VP)
    .scrollable(ScrollDirection.Vertical)
    .scrollBar(BarState.Auto)
    .padding({ left: 10, right: 10, top: 8, bottom: 8 })
    .backgroundColor($r('sys.color.comp_background_secondary'))
    .borderRadius(12)
  }

  @Builder
  private buildTextButton(label: string, style: number, onClick: () => void) {
    Button() {
      Text(label)
        .fontSize(12)
        .fontWeight(style === FLOATING_BUTTON_DEFAULT ? FontWeight.Regular : FontWeight.Medium)
        .fontFamily(this.appFontFamily)
        .fontColor(this.getButtonTextColor(style))
        .maxLines(1)
        .textAlign(TextAlign.Center)
    }
    .height(32)
    .layoutWeight(1)
    .borderRadius(16)
    .backgroundColor(this.getButtonBackgroundColor(style))
    .onClick((): void => {
      onClick();
    })
  }

  @Builder
  private buildActionBar() {
    if (this.displayGuidePhase === SourceEditorGuidePhase.PREVIEW) {
      Row({ space: 7 }) {
        this.buildTextButton('上一步', FLOATING_BUTTON_DEFAULT, (): void => {
          this.handlePreviousWorkflow();
        })
        this.buildTextButton('不正常', FLOATING_BUTTON_DANGER, (): void => {
          this.handleWorkflowAbnormal();
        })
        this.buildTextButton('正常', FLOATING_BUTTON_SUCCESS, (): void => {
          this.handleWorkflowNormal();
        })
      }
      .width('100%')
    } else if (this.displayGuidePhase === SourceEditorGuidePhase.NEED_SELECTION) {
      Row({ space: 7 }) {
        this.buildTextButton('重新触发', FLOATING_BUTTON_DEFAULT, (): void => {
          this.handleWorkflowAbnormal();
        })
        this.buildTextButton('等待点选', FLOATING_BUTTON_PRIMARY, (): void => {
          this.showLocalToast(this.displayExpectedDomLabel);
        })
      }
      .width('100%')
    } else if (this.displayGuidePhase === SourceEditorGuidePhase.SELECTION_REVIEW) {
      Row({ space: 7 }) {
        this.buildTextButton('重新选择', FLOATING_BUTTON_DANGER, (): void => {
          this.handleWorkflowAbnormal();
        })
        this.buildTextButton('采用', FLOATING_BUTTON_SUCCESS, (): void => {
          this.handleWorkflowNormal();
        })
      }
      .width('100%')
    } else {
      Row({ space: 7 }) {
        this.buildTextButton('保存副本', FLOATING_BUTTON_SUCCESS, (): void => {
          void this.handleSaveLocalFork();
        })
        this.buildTextButton('关闭', FLOATING_BUTTON_DEFAULT, (): void => {
          void this.handleCloseWindow();
        })
      }
      .width('100%')
    }
  }

  @Builder
  private buildEmptyState() {
    Column({ space: 8 }) {
      Text('等待编辑器数据')
        .fontSize(12)
        .fontWeight(FontWeight.Medium)
        .fontFamily(this.appFontFamily)
        .fontColor($r('sys.color.font_primary'))
      Text('暂无草稿')
        .fontSize(10)
        .fontFamily(this.appFontFamily)
        .fontColor($r('sys.color.font_secondary'))
        .maxLines(1)
    }
    .width('100%')
    .layoutWeight(1)
    .justifyContent(FlexAlign.Center)
    .alignItems(HorizontalAlign.Center)
    .backgroundColor($r('sys.color.comp_background_secondary'))
    .borderRadius(12)
  }

  @Builder
  private buildToast() {
    if (this.isToastVisible) {
      Text(this.toastMessage)
        .fontSize(12)
        .fontFamily(this.appFontFamily)
        .fontColor($r('sys.color.font_on_primary'))
        .padding({ left: 12, right: 12, top: 7, bottom: 7 })
        .backgroundColor($r('sys.color.font_primary'))
        .borderRadius(16)
        .align(Alignment.Bottom)
        .margin({ bottom: FLOATING_TOAST_BOTTOM_VP })
    }
  }

  build() {
    Stack() {
      Column({ space: 8 }) {
        this.buildHeader()
        if (this.displayHasStep) {
          this.buildCurrentStep()
          if (this.displayGuidePhase === SourceEditorGuidePhase.NEED_SELECTION ||
            this.displayGuidePhase === SourceEditorGuidePhase.SELECTION_REVIEW) {
            this.buildSelectionPanel()
          } else {
            this.buildPreviewPanel()
          }
          this.buildActionBar()
          if (this.displaySaveMessage.length > 0) {
            Text(this.displaySaveMessage)
              .fontSize(10)
              .fontFamily(this.appFontFamily)
              .fontColor($r('sys.color.font_secondary'))
              .maxLines(1)
              .textOverflow({ overflow: TextOverflow.Ellipsis })
          }
        } else {
          this.buildEmptyState()
        }
      }
      .width('100%')
      .height('100%')
      .padding(10)

      this.buildToast()
    }
    .width('100%')
    .height('100%')
    .backgroundColor($r('sys.color.comp_background_primary'))
    .borderRadius(18)
    .clip(true)
  }
}
