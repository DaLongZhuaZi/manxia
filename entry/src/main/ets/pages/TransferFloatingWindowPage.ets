import { common } from '@kit.AbilityKit';
import { pasteboard } from '@kit.BasicServicesKit';
import { logger } from 'manxia_core/src/main/ets/Utils/Logger';
import { WindowManager } from 'manxia_theme/src/main/ets/Utils/WindowManager';
import { getLocalTransferServerService, LocalTransferServerService } from 'manxia_network/src/main/ets/Framework/Services/LocalTransferServerService';
import { getTransferConfigManager, TransferConfigManager } from 'manxia_core/src/main/ets/Framework/Managers/TransferConfigManager';
import {
  TransferConfig,
  TransferLocalAddress,
  TransferServerRuntime,
  TransferServerStatus,
  TransferUploadProgressSnapshot,
  cloneTransferLocalAddress,
  cloneTransferUploadProgressSnapshot,
  createEmptyTransferUploadProgressSnapshot
} from 'manxia_core/src/main/ets/Models/TransferModels';

const TAG: string = 'TransferFloatingWindowPage';
const REFRESH_INTERVAL_MS: number = 900;
const FLOATING_TOAST_BOTTOM_VP: number = 10;

interface TransferFloatingViewState {
  renderVersion: number;
  status: TransferServerStatus;
  infoMessage: string;
  primaryAddressText: string;
  pairCodeText: string;
  pairedClientText: string;
  backgroundTransferText: string;
  uploadProgress: TransferUploadProgressSnapshot;
  hasActiveUploadProgress: boolean;
  isBusy: boolean;
}

function createInitialFloatingViewState(): TransferFloatingViewState {
  const progress: TransferUploadProgressSnapshot = createEmptyTransferUploadProgressSnapshot();
  const state: TransferFloatingViewState = {
    renderVersion: 0,
    status: 'stopped',
    infoMessage: '服务未启动。',
    primaryAddressText: '启动后显示访问地址',
    pairCodeText: '未生成',
    pairedClientText: '未配对',
    backgroundTransferText: '关闭',
    uploadProgress: progress,
    hasActiveUploadProgress: false,
    isBusy: false
  };
  return state;
}

function getPrimaryFloatingAddress(addresses: TransferLocalAddress[]): TransferLocalAddress | null {
  for (let index = 0; index < addresses.length; index++) {
    if (addresses[index].isPrimary) {
      return cloneTransferLocalAddress(addresses[index]);
    }
  }
  if (addresses.length > 0) {
    return cloneTransferLocalAddress(addresses[0]);
  }
  return null;
}

function createFloatingViewState(
  renderVersion: number,
  runtime: TransferServerRuntime,
  config: TransferConfig,
  isBusy: boolean
): TransferFloatingViewState {
  const primaryAddress = getPrimaryFloatingAddress(runtime.localAddresses);
  const progress = cloneTransferUploadProgressSnapshot(runtime.uploadProgress);
  const state: TransferFloatingViewState = {
    renderVersion: renderVersion,
    status: runtime.status,
    infoMessage: runtime.infoMessage,
    primaryAddressText: primaryAddress === null ? '启动后显示访问地址' : primaryAddress.url,
    pairCodeText: runtime.session === null ? '未生成' : runtime.session.pairCode,
    pairedClientText: runtime.session === null || runtime.session.clientName.length <= 0 ? '未配对' :
      runtime.session.clientName,
    backgroundTransferText: config.allowBackgroundTransfer ? '允许' : '关闭',
    uploadProgress: progress,
    hasActiveUploadProgress: progress.status === 'receiving',
    isBusy: isBusy
  };
  return state;
}

@Entry
@Component
struct TransferFloatingWindowPage {
  private readonly transferService: LocalTransferServerService = getLocalTransferServerService();
  private readonly configManager: TransferConfigManager = getTransferConfigManager();

  private refreshTimerId: number = -1;
  private dragStartWindowX: number = 0;
  private dragStartWindowY: number = 0;
  private isDraggingWindow: boolean = false;

  @StorageLink('appFontFamily') appFontFamily: string = 'HarmonyOS Sans';
  @State private viewState: TransferFloatingViewState = createInitialFloatingViewState();
  @State private isToastVisible: boolean = false;
  @State private toastMessage: string = '';

  aboutToAppear(): void {
    this.refreshSnapshot();
    this.startRefreshTimer();
  }

  aboutToDisappear(): void {
    this.stopRefreshTimer();
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

  private refreshSnapshot(): void {
    const runtime: TransferServerRuntime = this.transferService.getRuntimeState();
    const config: TransferConfig = this.configManager.getConfig();
    this.viewState = createFloatingViewState(this.viewState.renderVersion + 1, runtime, config, this.viewState.isBusy);
  }

  private setBusyState(isBusy: boolean): void {
    const runtime: TransferServerRuntime = this.transferService.getRuntimeState();
    const config: TransferConfig = this.configManager.getConfig();
    this.viewState = createFloatingViewState(this.viewState.renderVersion + 1, runtime, config, isBusy);
  }

  private resolveAbilityContext(): common.UIAbilityContext | null {
    try {
      const hostContext = this.getUIContext().getHostContext() as common.UIAbilityContext;
      if (!hostContext) {
        return null;
      }
      return hostContext;
    } catch (error) {
      logger.warn(TAG, `获取小窗AbilityContext失败: ${String(error)}`);
      return null;
    }
  }

  private async handleStartService(): Promise<void> {
    if (this.viewState.isBusy) {
      return;
    }
    const abilityContext = this.resolveAbilityContext();
    if (abilityContext === null) {
      this.showLocalToast('无法获取页面上下文');
      return;
    }

    this.setBusyState(true);
    try {
      const runtime = await this.transferService.start(abilityContext);
      this.viewState = createFloatingViewState(
        this.viewState.renderVersion + 1,
        runtime,
        this.configManager.getConfig(),
        false
      );
      this.showLocalToast(runtime.status === 'running' ? '服务已启动' : '启动未完成');
    } catch (error) {
      logger.error(TAG, `小窗启动局域网传书服务失败: ${String(error)}`);
      this.showLocalToast('启动失败');
    } finally {
      this.setBusyState(false);
    }
  }

  private async handleStopService(): Promise<void> {
    if (this.viewState.isBusy) {
      return;
    }
    this.setBusyState(true);
    try {
      const runtime = await this.transferService.stop('通过应用内小窗停止。');
      this.viewState = createFloatingViewState(
        this.viewState.renderVersion + 1,
        runtime,
        this.configManager.getConfig(),
        false
      );
      this.showLocalToast('服务已停止');
    } catch (error) {
      logger.error(TAG, `小窗停止局域网传书服务失败: ${String(error)}`);
      this.showLocalToast('停止失败');
    } finally {
      this.setBusyState(false);
    }
  }

  private async handleCopyAddress(): Promise<void> {
    if (this.viewState.status !== 'running' || this.viewState.primaryAddressText.indexOf('http') !== 0) {
      this.showLocalToast('暂无可复制地址');
      return;
    }
    try {
      const data = pasteboard.createData(pasteboard.MIMETYPE_TEXT_PLAIN, this.viewState.primaryAddressText);
      const systemPasteboard = pasteboard.getSystemPasteboard();
      await systemPasteboard.setData(data);
      this.showLocalToast('地址已复制');
    } catch (error) {
      logger.warn(TAG, `小窗复制地址失败: ${String(error)}`);
      this.showLocalToast('复制失败');
    }
  }

  private handleOpenTransferPage(): void {
    try {
      const globalStack = AppStorage.get<NavPathStack>('GlobalNavStack');
      if (!globalStack) {
        this.showLocalToast('主导航暂不可用');
        return;
      }
      globalStack.pushPathByName('TransferPage', undefined);
      this.showLocalToast('已打开传书页');
    } catch (error) {
      logger.warn(TAG, `小窗打开局域网传书页失败: ${String(error)}`);
      this.showLocalToast('打开失败');
    }
  }

  private async handleCloseWindow(): Promise<void> {
    await WindowManager.closeAppFloatingWindow('小窗按钮关闭');
  }

  private showLocalToast(message: string): void {
    this.toastMessage = message;
    this.isToastVisible = true;
    setTimeout((): void => {
      this.isToastVisible = false;
    }, 1300);
  }

  private getStatusText(): string {
    if (this.viewState.status === 'running') {
      return '运行中';
    }
    if (this.viewState.status === 'starting') {
      return '启动中';
    }
    if (this.viewState.status === 'stopping') {
      return '停止中';
    }
    if (this.viewState.status === 'error') {
      return '异常';
    }
    return '未启动';
  }

  private getProgressText(): string {
    const progress = this.viewState.uploadProgress;
    if (progress.status === 'receiving') {
      return `${Math.round(progress.progressPercent)}% · ${this.getProgressDetailText()}`;
    }
    if (progress.status === 'completed') {
      return `已完成 · ${this.getProgressDetailText()}`;
    }
    if (progress.status === 'failed') {
      return progress.message.length > 0 ? progress.message : '接收失败';
    }
    return '等待上传';
  }

  private getProgressDetailText(): string {
    const progress = this.viewState.uploadProgress;
    const fileName = progress.fileName.length > 0 ? progress.fileName : '未命名文件';
    const sizeText = progress.expectedBytes > 0
      ? `${this.formatByteSize(progress.receivedBytes)} / ${this.formatByteSize(progress.expectedBytes)}`
      : this.formatByteSize(progress.receivedBytes);
    return `${fileName} · ${sizeText}`;
  }

  private getProgressWidth(): string {
    const progress = this.viewState.uploadProgress;
    if (progress.status !== 'receiving' && progress.status !== 'completed') {
      return '0%';
    }
    const percent = Math.max(0, Math.min(100, progress.progressPercent));
    return `${percent}%`;
  }

  private formatByteSize(size: number): string {
    const units: string[] = ['B', 'KB', 'MB', 'GB', 'TB'];
    let value = Math.max(0, size);
    let unitIndex = 0;
    while (value >= 1024 && unitIndex < units.length - 1) {
      value = value / 1024;
      unitIndex += 1;
    }
    const fractionDigits = unitIndex === 0 ? 0 : 1;
    return `${value.toFixed(fractionDigits)} ${units[unitIndex]}`;
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
  private buildInfoRow(label: string, value: string) {
    Row({ space: 8 }) {
      Text(label)
        .fontSize(10)
        .fontFamily(this.appFontFamily)
        .fontColor($r('sys.color.font_secondary'))
        .width(44)
        .maxLines(1)

      Text(value)
        .fontSize(11)
        .fontFamily(this.appFontFamily)
        .fontColor($r('sys.color.font_primary'))
        .layoutWeight(1)
        .maxLines(1)
        .textOverflow({ overflow: TextOverflow.Ellipsis })
    }
    .width('100%')
  }

  @Builder
  private buildHeader() {
    Row({ space: 8 }) {
      Column() {
        SymbolGlyph($r('sys.symbol.computer_share_fill'))
          .fontSize(17)
          .fontColor([$r('sys.color.font_on_primary')])
      }
      .width(30)
      .height(30)
      .justifyContent(FlexAlign.Center)
      .backgroundColor($r('sys.color.brand'))
      .borderRadius(15)

      Column({ space: 2 }) {
        Text('局域网传书')
          .fontSize(13)
          .fontWeight(FontWeight.Bold)
          .fontFamily(this.appFontFamily)
          .fontColor($r('sys.color.font_primary'))
          .maxLines(1)

        Text(this.getStatusText())
          .fontSize(10)
          .fontFamily(this.appFontFamily)
          .fontColor($r('sys.color.font_secondary'))
          .maxLines(1)
      }
      .layoutWeight(1)
      .alignItems(HorizontalAlign.Start)

      this.buildIconButton($r('sys.symbol.arrow_up_left_and_arrow_down_right'), (): void => {
        this.handleOpenTransferPage();
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
  private buildActionBar() {
    Row({ space: 7 }) {
      Button() {
        Text(this.viewState.status === 'running' ? '停止' : '启动')
          .fontSize(11)
          .fontFamily(this.appFontFamily)
          .fontColor($r('sys.color.font_on_primary'))
      }
      .height(30)
      .layoutWeight(1)
      .borderRadius(15)
      .enabled(!this.viewState.isBusy)
      .backgroundColor(this.viewState.status === 'running' ? $r('app.color.color_error') : $r('sys.color.brand'))
      .onClick((): void => {
        if (this.viewState.status === 'running') {
          void this.handleStopService();
        } else {
          void this.handleStartService();
        }
      })

      Button() {
        Text('复制地址')
          .fontSize(11)
          .fontFamily(this.appFontFamily)
          .fontColor($r('sys.color.font_primary'))
      }
      .height(30)
      .layoutWeight(1)
      .borderRadius(15)
      .enabled(this.viewState.status === 'running')
      .backgroundColor($r('sys.color.comp_background_secondary'))
      .onClick((): void => {
        void this.handleCopyAddress();
      })
    }
    .width('100%')
  }

  @Builder
  private buildProgressPanel() {
    Column({ space: 6 }) {
      Row() {
        Text('接收进度')
          .fontSize(10)
          .fontFamily(this.appFontFamily)
          .fontColor($r('sys.color.font_secondary'))
          .width(52)
          .maxLines(1)

        Text(this.getProgressText())
          .fontSize(10)
          .fontFamily(this.appFontFamily)
          .fontColor($r('sys.color.font_primary'))
          .layoutWeight(1)
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
      }
      .width('100%')

      Row() {
        Blank()
          .width(this.getProgressWidth())
          .height(5)
          .backgroundColor($r('sys.color.brand'))
          .borderRadius(2.5)
      }
      .width('100%')
      .height(5)
      .backgroundColor($r('sys.color.comp_background_tertiary'))
      .borderRadius(2.5)
      .clip(true)
    }
    .width('100%')
    .padding({ left: 10, right: 10, top: 8, bottom: 8 })
    .backgroundColor($r('sys.color.comp_background_secondary'))
    .borderRadius(12)
  }

  @Builder
  private buildInfoScroller() {
    Scroll() {
      Column({ space: 6 }) {
        this.buildInfoRow('主地址', this.viewState.primaryAddressText)
        this.buildInfoRow('配对码', this.viewState.pairCodeText)
        this.buildInfoRow('客户端', this.viewState.pairedClientText)
        this.buildInfoRow('后台', this.viewState.backgroundTransferText)
        this.buildInfoRow('状态', this.viewState.infoMessage)
      }
      .width('100%')
      .padding({ left: 10, right: 10, top: 8, bottom: 8 })
    }
    .width('100%')
    .layoutWeight(1)
    .backgroundColor($r('sys.color.comp_background_secondary'))
    .borderRadius(12)
    .scrollBar(BarState.Off)
    .clip(true)
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
        this.buildProgressPanel()
        this.buildInfoScroller()
        this.buildActionBar()
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
    .key(`transfer_float_${this.viewState.renderVersion}_${this.viewState.status}_${this.viewState.uploadProgress.status}`)
  }
}
