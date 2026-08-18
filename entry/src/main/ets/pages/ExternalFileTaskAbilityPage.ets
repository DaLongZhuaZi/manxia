import { common } from '@kit.AbilityKit';
import { promptAction } from '@kit.ArkUI';
import fs from '@ohos.file.fs';
import { fileUri as coreFileUri } from '@kit.CoreFileKit';
import { util } from '@kit.ArkTS';
import { logger } from '../Utils/Logger';
import { SafeFileUtils } from '../Utils/SafeFileUtils';
import { DataManagementPage, DataManagementExternalFileParams } from './DataManagementPage';
import { BackupPage, BackupExternalImportParams } from './BackupPage';
import { AvifTestPage, AvifTestPageParams } from './AvifTestPage';
import { FileEditorPage } from './FileEditorPage';
import { SourceManager } from '../Framework/Source/SourceManager';
import { getNovelSourceManager } from '../Framework/Novel/NovelSourceManager';
import { getNovelInitializer } from '../Framework/Novel/NovelInitializer';
import { FontManager, CustomFont } from '../Framework/Managers/FontManager';
import {
  fileEditorService,
  FileEditorOpenParams,
  FileEditorOpenSource,
  FileEditorSaveTargetType
} from '../Framework/Editor/FileEditorService';
import { FileEditorOpenFactory } from '../Framework/Editor/FileEditorOpenFactory';
import { FILE_EDITOR_ABILITY_HOST_MODE } from '../Framework/Editor/FileEditorAbilityConstants';
import {
  ExternalFileTaskParamStore,
  ExternalFileTaskWindowPayload
} from '../Framework/ExternalFile/ExternalFileTaskParamStore';
import {
  ExternalFileTaskFactory,
  ExternalFileTaskKind,
  ExternalFileTaskParams,
  ExternalFileTaskSource
} from '../Framework/ExternalFile/ExternalFileTaskTypes';
import {
  ExternalImportNavigationCoordinator,
  ExternalImportNavigationRequest,
  ExternalImportNavigationSource,
  ExternalImportNavigationTarget
} from '../Framework/ExternalFile/ExternalImportNavigationCoordinator';
import { ImportFlowMonitor, getImportFlowMonitor } from '../Framework/Import/ImportFlowMonitor';
import {
  ImportFlowEntrySource,
  ImportFlowEvent,
  ImportFlowEventType,
  ImportFlowSeverity
} from '../Framework/Import/ImportFlowTypes';

const TAG: string = 'ExternalFileTaskAbilityPage';
const APP_STORAGE_TRANSFER_RECORD_ID: string = 'pendingTransferRecordId';
const APP_STORAGE_TRANSFER_RESULT: string = 'pendingTransferImportResult';
const APP_STORAGE_TRANSFER_TRACKING_ACTIVE: string = 'pendingTransferTrackingActive';
const APP_STORAGE_PENDING_IMPORT_FLOW_ID: string = 'pendingImportFlowId';
let externalFileTaskAbilityPageStorage: LocalStorage = new LocalStorage();

@Entry(externalFileTaskAbilityPageStorage)
@Component
struct ExternalFileTaskAbilityPage {
  @LocalStorageProp('externalFileTaskAbilityInstanceId') private taskInstanceId: string = '';
  @State private pathStack: NavPathStack = new NavPathStack();
  @State private taskParams: ExternalFileTaskParams | null = null;
  @State private statusText: string = '正在准备文件任务';
  @State private errorText: string = '';
  @State private isNavigationDestinationActive: boolean = false;
  @StorageLink('source_features_enabled') private sourceFeaturesEnabled: boolean = false;
  private hasDispatchedTask: boolean = false;
  private importFlowMonitor: ImportFlowMonitor = getImportFlowMonitor();

  aboutToAppear(): void {
    this.resolveTaskLaunchPayload('appear');
    // Navigation mutates the NavPathStack held in @State. Dispatching it
    // synchronously from the first appearance lifecycle races ArkUI's
    // initial render and is rejected as a state change during render.
    // Resolve the payload now, then perform the single dispatch after the
    // first render turn so JSON import can safely open its action menu.
    setTimeout((): void => {
      this.resolveTaskLaunchPayload('deferred');
      this.dispatchInitialTask();
    }, 0);
  }

  private resolveTaskLaunchPayload(source: string): void {
    if (this.taskParams) {
      return;
    }
    const store = ExternalFileTaskParamStore.getInstance();
    const windowId = this.resolveHostWindowId();
    let payload: ExternalFileTaskWindowPayload | null = store.resolveWindowPayload(windowId);
    if (!payload) {
      payload = store.consumePendingPayload();
    }
    if (!payload && this.taskInstanceId.length > 0) {
      const params = store.getParams(this.taskInstanceId);
      if (params) {
        this.taskParams = params;
        logger.info(TAG, `外部文件任务参数已从实例恢复: source=${source}, instanceId=${this.taskInstanceId}`);
        return;
      }
    }
    if (!payload) {
      this.errorText = '未获取到外部文件任务参数';
      logger.error(TAG, `外部文件任务参数未绑定: source=${source}, windowId=${windowId}`);
      return;
    }
    this.taskParams = payload.params;
    this.taskInstanceId = payload.instanceId;
    logger.info(
      TAG,
      `外部文件任务参数已解析: source=${source}, instanceId=${this.taskInstanceId}, windowId=${windowId}, payloadWindowId=${payload.windowId}`
    );
  }

  private resolveHostWindowId(): number {
    try {
      const hostContext = this.getUIContext()?.getHostContext() as common.UIAbilityContext;
      if (!hostContext) {
        return -1;
      }
      const mainWindow = hostContext.windowStage.getMainWindowSync();
      const properties = mainWindow.getWindowProperties();
      return properties.id;
    } catch (error) {
      logger.warn(TAG, `获取外部文件任务页面窗口ID失败: ${String(error)}`);
      return -1;
    }
  }

  private dispatchInitialTask(): void {
    if (this.hasDispatchedTask) {
      return;
    }
    if (!this.taskParams) {
      return;
    }
    this.hasDispatchedTask = true;
    const kind = this.taskParams.kind;
    logger.info(TAG, `分发外部文件任务: instanceId=${this.taskInstanceId}, kind=${kind}`);

    switch (kind) {
      case ExternalFileTaskKind.COMIC:
      case ExternalFileTaskKind.EBOOK:
      case ExternalFileTaskKind.PDF:
      case ExternalFileTaskKind.UNKNOWN:
        this.openDataManagementTask(kind);
        break;
      case ExternalFileTaskKind.BACKUP:
        this.openBackupRestoreTask();
        break;
      case ExternalFileTaskKind.AVIF:
      case ExternalFileTaskKind.IMAGE:
        this.openImagePreviewTask();
        break;
      case ExternalFileTaskKind.JSON:
        this.openJsonTask();
        break;
      case ExternalFileTaskKind.FONT:
        this.openFontTask();
        break;
      case ExternalFileTaskKind.CODE:
        this.openCodeEditorTask();
        break;
      default:
        this.errorText = '暂不支持该文件类型';
        break;
    }
  }

  private openDataManagementTask(kind: ExternalFileTaskKind): void {
    if (!this.taskParams) {
      return;
    }
    const primaryUri = ExternalFileTaskFactory.resolvePrimaryUri(this.taskParams);
    if (primaryUri.length <= 0 && this.taskParams.uris.length <= 0) {
      this.errorText = '文件地址为空';
      return;
    }

    const params: DataManagementExternalFileParams = {
      externalFileTask: ExternalFileTaskFactory.clone(this.taskParams)
    };
    this.statusText = '正在打开文件导入';
    this.isNavigationDestinationActive = true;
    this.pathStack.pushPathByName('DataManagementPage', params);
    logger.info(TAG, `已打开文件导入任务: kind=${kind}, uri=${primaryUri}`);
  }

  private openBackupRestoreTask(): void {
    if (!this.taskParams) {
      return;
    }
    const primaryUri = ExternalFileTaskFactory.resolvePrimaryUri(this.taskParams);
    if (primaryUri.length <= 0) {
      this.errorText = '备份文件地址为空';
      return;
    }
    const store = ExternalFileTaskParamStore.getInstance();
    if (!store.acquireBackupRestoreLock(this.taskInstanceId)) {
      const activeInstanceId = store.getBackupRestoreLockInstanceId();
      this.errorText = '已有备份恢复任务正在进行';
      logger.warn(TAG, `备份恢复任务被串行锁拦截: current=${this.taskInstanceId}, active=${activeInstanceId}`);
      return;
    }

    const params: BackupExternalImportParams = {
      externalBackupUri: primaryUri,
      externalTaskInstanceId: this.taskInstanceId
    };
    this.statusText = '正在打开备份恢复';
    this.isNavigationDestinationActive = true;
    this.pathStack.pushPathByName('BackupPage', params);
    logger.info(TAG, `已打开备份恢复任务: uri=${primaryUri}`);
  }

  private openImagePreviewTask(): void {
    if (!this.taskParams) {
      return;
    }
    const primaryUri = ExternalFileTaskFactory.resolvePrimaryUri(this.taskParams);
    if (primaryUri.length <= 0) {
      this.errorText = '图片地址为空';
      return;
    }
    const params: AvifTestPageParams = {
      fileUri: primaryUri
    };
    this.statusText = '正在打开图片预览';
    this.isNavigationDestinationActive = true;
    this.pathStack.pushPathByName('AvifTestPage', params);
    this.finalizeTrackedTransferImport('imported');
    logger.info(TAG, `已打开图片预览任务: uri=${primaryUri}`);
  }

  private openJsonTask(): void {
    if (!this.taskParams) {
      return;
    }
    const primaryUri = ExternalFileTaskFactory.resolvePrimaryUri(this.taskParams);
    if (primaryUri.length <= 0) {
      this.errorText = 'JSON 文件地址为空';
      return;
    }
    const fileName = ExternalFileTaskFactory.resolveDisplayName(this.taskParams);
    const lowerFileName = fileName.toLowerCase();
    const isStrictJsonFile = lowerFileName.endsWith('.json');
    const fileTypeLabel = lowerFileName.endsWith('.json5') ? 'JSON5' : 'JSON';
    this.statusText = '等待选择 JSON 处理方式';

    if (this.sourceFeaturesEnabled && isStrictJsonFile) {
      this.getUIContext().getPromptAction().showActionMenu({
        title: `导入${fileTypeLabel}文件\n${fileName}`,
        buttons: [
          { text: '导入为书源', color: $r('sys.color.ohos_id_color_text_primary') },
          { text: '导入为图源', color: $r('sys.color.ohos_id_color_text_primary') },
          { text: '使用文件编辑器打开', color: $r('sys.color.ohos_id_color_text_primary') }
        ]
      }).then((result: promptAction.ActionMenuSuccessResponse): void => {
        if (result.index === 0) {
          void this.importJsonAsNovelSource(primaryUri);
        } else if (result.index === 1) {
          void this.importJsonAsMangaSource(primaryUri);
        } else {
          void this.openJsonInEditor(primaryUri);
        }
      }).catch((): void => {
        logger.info(TAG, '用户取消 JSON 文件处理');
        this.statusText = '已取消';
        this.finalizeTrackedTransferImport('import_cancelled');
      });
      return;
    }

    this.getUIContext().getPromptAction().showActionMenu({
      title: `${fileTypeLabel}文件\n${fileName}`,
      buttons: [
        { text: '使用文件编辑器打开', color: $r('sys.color.ohos_id_color_text_primary') }
      ]
    }).then((): void => {
      void this.openJsonInEditor(primaryUri);
    }).catch((): void => {
      logger.info(TAG, '用户取消 JSON5 文件处理');
      this.statusText = '已取消';
      this.finalizeTrackedTransferImport('import_cancelled');
    });
  }

  private openFontTask(): void {
    if (!this.taskParams) {
      return;
    }
    const primaryUri = ExternalFileTaskFactory.resolvePrimaryUri(this.taskParams);
    if (primaryUri.length <= 0) {
      this.errorText = '字体文件地址为空';
      return;
    }
    const fileName = ExternalFileTaskFactory.resolveDisplayName(this.taskParams);
    const displayName = this.removeFontExtension(fileName);
    this.statusText = '等待确认字体导入';

    this.getUIContext().showAlertDialog({
      title: '导入字体',
      message: `确定要导入字体文件吗？\n\n文件名: ${fileName}`,
      autoCancel: true,
      alignment: DialogAlignment.Center,
      primaryButton: {
        value: '取消',
        action: () => {
          logger.info(TAG, '用户取消字体导入');
          this.statusText = '已取消';
          this.finalizeTrackedTransferImport('import_cancelled');
        }
      },
      secondaryButton: {
        value: '确认导入',
        action: () => {
          void this.executeImportFont(primaryUri, displayName);
        }
      }
    });
  }

  private openCodeEditorTask(): void {
    if (!this.taskParams) {
      return;
    }
    const primaryUri = ExternalFileTaskFactory.resolvePrimaryUri(this.taskParams);
    if (primaryUri.length <= 0) {
      this.errorText = '代码文件地址为空';
      return;
    }
    const language = this.taskParams.language.length > 0 ? this.taskParams.language : 'plaintext';
    void this.openExternalFileInEditor(primaryUri, language);
  }

  private finalizeTrackedTransferImport(
    status: 'imported' | 'import_failed' | 'import_cancelled'
  ): void {
    if (!this.taskParams || this.taskParams.source !== ExternalFileTaskSource.TRANSFER) {
      return;
    }
    try {
      const recordId = AppStorage.get<string>(APP_STORAGE_TRANSFER_RECORD_ID);
      const trackingActive = AppStorage.get<boolean>(APP_STORAGE_TRANSFER_TRACKING_ACTIVE);
      if (!trackingActive || !recordId || recordId.trim().length <= 0) {
        return;
      }
      if (this.taskParams.transferRecordId.length > 0 && this.taskParams.transferRecordId !== recordId) {
        logger.warn(TAG, `跳过局域网传书结果回写: taskRecord=${this.taskParams.transferRecordId}, activeRecord=${recordId}`);
        return;
      }

      AppStorage.setOrCreate(APP_STORAGE_TRANSFER_RESULT, status);
      AppStorage.setOrCreate(APP_STORAGE_TRANSFER_TRACKING_ACTIVE, false);
      const importFlowId: string = AppStorage.get<string>(APP_STORAGE_PENDING_IMPORT_FLOW_ID) || '';
      if (importFlowId.length > 0) {
        const event: ImportFlowEvent = new ImportFlowEvent();
        event.sessionId = importFlowId;
        event.eventType = ImportFlowEventType.TRANSFER_RESULT_WRITTEN;
        event.reason = status;
        event.entrySource = ImportFlowEntrySource.LAN_TRANSFER;
        event.transferRecordId = recordId;
        event.success = status !== 'import_failed';
        event.severity = status === 'import_failed' ? ImportFlowSeverity.ERROR : ImportFlowSeverity.INFO;
        event.detail = `external_task_status=${status}`;
        this.importFlowMonitor.record(event);
        this.importFlowMonitor.endSession(importFlowId, status);
        AppStorage.delete(APP_STORAGE_PENDING_IMPORT_FLOW_ID);
      }
      logger.info(TAG, `已回写局域网传书独立任务结果: recordId=${recordId}, status=${status}`);
    } catch (error) {
      logger.warn(TAG, `回写局域网传书独立任务结果失败: ${String(error)}`);
    }
  }

  private resolveAbilityContext(): common.UIAbilityContext | null {
    try {
      const hostContext = this.getUIContext()?.getHostContext() as common.UIAbilityContext;
      return hostContext ? hostContext : null;
    } catch (error) {
      logger.warn(TAG, `获取外部文件任务 AbilityContext 失败: ${String(error)}`);
      return null;
    }
  }

  private async navigateMainAfterSuccessfulImport(
    target: ExternalImportNavigationTarget,
    title: string
  ): Promise<void> {
    const request = new ExternalImportNavigationRequest();
    request.target = target;
    request.source = ExternalImportNavigationSource.EXTERNAL_FILE_TASK;
    request.title = title;
    request.taskInstanceId = this.taskInstanceId;
    ExternalImportNavigationCoordinator.requestNavigation(request);

    const abilityContext = this.resolveAbilityContext();
    const broughtToFront = await ExternalImportNavigationCoordinator.bringEntryAbilityToFront(abilityContext, TAG);
    if (broughtToFront) {
      await ExternalImportNavigationCoordinator.closeCurrentAbility(abilityContext, TAG);
    }
  }

  private async importJsonAsNovelSource(jsonUri: string): Promise<void> {
    try {
      const readablePath = this.resolveReadableImportPath(jsonUri);
      const displayName = this.taskParams
        ? ExternalFileTaskFactory.resolveDisplayName(this.taskParams)
        : ExternalFileTaskFactory.extractFileName(jsonUri);
      this.statusText = '正在校验书源文件';
      logger.info(TAG, `书源导入预检开始: name=${displayName}`);
      if (this.isGrantedExternalUri(readablePath)) {
        // The V2 parser owns the sole open of a picker/file-association URI.
        // Opening it for a separate preflight can invalidate its temporary
        // grant before the stream is created.
        this.statusText = '正在打开授权书源文件';
        logger.info(TAG, '书源导入预检通过: 使用授权 URI 流式读取');
      } else {
        const fileStat = SafeFileUtils.statSyncStrict(readablePath);
        if (fileStat.size <= 0) {
          throw new Error('书源文件为空');
        }
        this.statusText = `正在读取书源文件（${fileStat.size} bytes）`;
        logger.info(TAG, `书源导入预检通过: bytes=${fileStat.size}`);
      }
      await this.ensureNovelModuleReadyForImport();
      const importResult = await getNovelSourceManager().importFromLargeFile(readablePath, {
        onFileReadProgress: (percent: number, _bytesRead: number, _totalBytes: number): void => {
          this.statusText = `正在读取书源文件 ${percent}%`;
        },
        onParseProgress: (parsedCount: number, _sourceName: string): void => {
          this.statusText = `正在解析并编译书源：${parsedCount} 条`;
        },
        onImportProgress: (importedCount: number, totalCount: number, _sourceName: string): void => {
          this.statusText = totalCount > 0
            ? `正在无损写入书源：${importedCount}/${totalCount}`
            : `正在无损写入书源：${importedCount} 条，仍在扫描`;
        }
      });
      const successCount = importResult.successCount;
      const failCount = importResult.failedCount + importResult.skippedCount;
      if (successCount > 0) {
        this.showToast(`成功导入 ${successCount} 个书源${failCount > 0 ? `，${failCount} 个失败` : ''}`);
        this.statusText = failCount > 0 ? '书源部分导入完成' : '书源无损导入完成';
        this.finalizeTrackedTransferImport('imported');
        await this.navigateMainAfterSuccessfulImport(
          ExternalImportNavigationTarget.NOVEL_SOURCE_MANAGEMENT,
          '书源导入完成'
        );
      } else {
        this.errorText = `导入失败：${importResult.errors.length > 0 ? importResult.errors[0] : '没有有效的书源数据'}`;
        this.showToast(this.errorText);
        this.finalizeTrackedTransferImport('import_failed');
      }
    } catch (error) {
      this.errorText = `导入书源失败: ${String(error)}`;
      logger.error(TAG, this.errorText);
      this.showToast('导入书源失败');
      this.finalizeTrackedTransferImport('import_failed');
    }
  }

  /**
   * An isolated external-file Ability has an independent UI lifecycle.  It
   * must establish the same database/source-manager readiness boundary as the
   * regular source-management page before it can persist V2 raw documents.
   */
  private async ensureNovelModuleReadyForImport(): Promise<void> {
    if (getNovelInitializer().isReady()) {
      return;
    }
    const abilityContext = this.resolveAbilityContext();
    if (abilityContext === null) {
      throw new Error('无法获取书源导入所需的 AbilityContext');
    }
    this.statusText = '正在初始化书源模块';
    const initResult = await getNovelInitializer().initialize(abilityContext);
    if (!initResult.success) {
      logger.error(TAG, `书源导入初始化失败: errors=${initResult.errors.length}`);
      throw new Error(`书源模块初始化失败：${initResult.errors.length} 项`);
    }
    logger.info(TAG, `书源导入模块初始化完成: durationMs=${initResult.duration}`);
  }

  private async importJsonAsMangaSource(jsonUri: string): Promise<void> {
    try {
      this.statusText = '正在导入图源';
      const jsonContent = this.readTextFromExternalUri(jsonUri);
      const result = await SourceManager.getInstance().importFromJSON(jsonContent);
      if (result.success) {
        this.showToast(`成功导入图源: ${result.sourceName || '未知'}`);
        this.statusText = '图源导入完成';
        this.finalizeTrackedTransferImport('imported');
        await this.navigateMainAfterSuccessfulImport(
          ExternalImportNavigationTarget.SOURCE_MANAGEMENT,
          '图源导入完成'
        );
      } else {
        this.errorText = `导入失败: ${result.error || '未知错误'}`;
        this.showToast(this.errorText);
        this.finalizeTrackedTransferImport('import_failed');
      }
    } catch (error) {
      this.errorText = `导入图源失败: ${String(error)}`;
      logger.error(TAG, this.errorText);
      this.showToast('导入图源失败');
      this.finalizeTrackedTransferImport('import_failed');
    }
  }

  private async openJsonInEditor(jsonUri: string): Promise<void> {
    await this.openExternalFileInEditor(jsonUri, 'json');
  }

  private async openExternalFileInEditor(uri: string, language: string): Promise<void> {
    try {
      this.statusText = '正在打开文件编辑器';
      const readablePath = this.resolveReadableImportPath(uri);
      const fileName = ExternalFileTaskFactory.extractFileName(uri);
      const content = this.readTextFromReadablePath(readablePath);
      const openParams: FileEditorOpenParams = {
        hostMode: FILE_EDITOR_ABILITY_HOST_MODE,
        content: content,
        language: language,
        readOnly: false,
        title: fileName.length > 0 ? fileName : '外部文件',
        origin: FileEditorOpenSource.EXTERNAL_IMPORT,
        saveTarget: fileEditorService.createSaveTarget(
          FileEditorSaveTargetType.EXTERNAL_DOCUMENT,
          '',
          fileName,
          readablePath,
          '',
          uri,
          false
        )
      };
      const params = FileEditorOpenFactory.createParams(openParams);
      this.isNavigationDestinationActive = true;
      this.pathStack.pushPathByName('FileEditorPage', params);
      this.statusText = '文件编辑器已打开';
      this.finalizeTrackedTransferImport('imported');
    } catch (error) {
      this.errorText = `打开文件编辑器失败: ${String(error)}`;
      logger.error(TAG, this.errorText);
      this.showToast('打开文件编辑器失败');
      this.finalizeTrackedTransferImport('import_failed');
    }
  }

  private async executeImportFont(fontUri: string, displayName: string): Promise<void> {
    try {
      this.statusText = '正在导入字体';
      const readablePath = this.resolveReadableImportPath(fontUri);
      const customFont: CustomFont = await FontManager.getInstance().addCustomFont(displayName, readablePath, this.getUIContext());
      this.showToast(`成功导入字体: ${customFont.displayName}`);
      this.statusText = '字体导入完成';
      this.finalizeTrackedTransferImport('imported');
      await this.navigateMainAfterSuccessfulImport(
        ExternalImportNavigationTarget.FONT_SETTINGS,
        '字体导入完成'
      );
    } catch (error) {
      this.errorText = `导入字体失败: ${String(error)}`;
      logger.error(TAG, this.errorText);
      this.showToast('导入字体失败');
      this.finalizeTrackedTransferImport('import_failed');
    }
  }

  private resolveReadableImportPath(sourceUri: string): string {
    const trimmedUri = sourceUri.trim();
    if (this.isGrantedExternalUri(trimmedUri)) {
      return trimmedUri;
    }
    try {
      return new coreFileUri.FileUri(trimmedUri).path;
    } catch (_error) {
    }
    if (trimmedUri.startsWith('file://docs')) {
      return trimmedUri.replace('file://docs', '');
    }
    if (trimmedUri.startsWith('file://')) {
      return trimmedUri.replace('file://', '');
    }
    return trimmedUri;
  }

  private isGrantedExternalUri(value: string): boolean {
    return value.includes('://');
  }

  private readTextFromExternalUri(uri: string): string {
    return this.readTextFromReadablePath(this.resolveReadableImportPath(uri));
  }

  private readTextFromReadablePath(path: string): string {
    const file = SafeFileUtils.openSyncStrict(path, fs.OpenMode.READ_ONLY);
    try {
      const stat = SafeFileUtils.statSyncStrict(file.fd);
      const buffer = new ArrayBuffer(stat.size);
      SafeFileUtils.readExactSync(file.fd, buffer);
      const textDecoder = util.TextDecoder.create('utf-8');
      return textDecoder.decodeToString(new Uint8Array(buffer));
    } finally {
      SafeFileUtils.closeSync(file);
    }
  }

  private removeFontExtension(fileName: string): string {
    const lowerName = fileName.toLowerCase();
    const extensions: string[] = ['.ttf', '.otf', '.ttc', '.woff', '.woff2'];
    for (let i = 0; i < extensions.length; i++) {
      const extension = extensions[i];
      if (lowerName.endsWith(extension)) {
        return fileName.substring(0, fileName.length - extension.length);
      }
    }
    return fileName.length > 0 ? fileName : '自定义字体';
  }

  private showToast(message: string): void {
    try {
      this.getUIContext().getPromptAction().showToast({ message: message });
    } catch (error) {
      logger.warn(TAG, `显示提示失败: ${String(error)}`);
    }
  }

  @Builder
  private buildDestination(name: string, _param: Object) {
    if (name === 'DataManagementPage') {
      DataManagementPage()
    } else if (name === 'BackupPage') {
      BackupPage()
    } else if (name === 'AvifTestPage') {
      AvifTestPage()
    } else if (name === 'FileEditorPage') {
      FileEditorPage()
    }
  }

  @Builder
  private buildFallbackContent() {
    Column() {
      Text(this.statusText)
        .id('external_file_task_status')
        .fontSize(16)
        .fontColor($r('app.color.text_primary'))
        .maxLines(3)
        .textOverflow({ overflow: TextOverflow.Ellipsis })
        .textAlign(TextAlign.Center)
        .padding({ left: 28, right: 28 })
      if (this.errorText.length > 0) {
        Text(this.errorText)
          .id('external_file_task_error')
          .fontSize(14)
          .fontColor($r('app.color.text_secondary'))
          .maxLines(5)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
          .textAlign(TextAlign.Center)
          .padding({ left: 28, right: 28, top: 12 })
      }
    }
    .width('100%')
    .height('100%')
    .justifyContent(FlexAlign.Center)
    .backgroundColor($r('app.color.background_primary'))
  }

  build() {
    Stack() {
      Navigation(this.pathStack) {
        // Navigation's child slot is not a reliable task-status surface when
        // the external Ability has no destination on its NavPathStack. Keep a
        // neutral content node here and render status as a sibling overlay so
        // file preflight, initialization and import progress are always
        // attached to the first window.
        Column() {
          Blank()
        }
        .width('100%')
        .height('100%')
        .backgroundColor($r('app.color.background_primary'))
      }
      .hideNavBar(true)
      .navDestination(this.buildDestination)
      .mode(NavigationMode.Stack)
      .width('100%')
      .height('100%')
      .backgroundColor($r('app.color.background_primary'))

      if (!this.isNavigationDestinationActive) {
        this.buildFallbackContent()
      }
    }
    .width('100%')
    .height('100%')
    .backgroundColor($r('app.color.background_primary'))
  }
}
