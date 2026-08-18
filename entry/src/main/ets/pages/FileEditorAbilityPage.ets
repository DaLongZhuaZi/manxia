import { common } from '@kit.AbilityKit';
import { FrameCallback, UIContext } from '@kit.ArkUI';
import { logger } from '../Utils/Logger';
import { FileEditorPage } from './FileEditorPage';
import { ReaderAbilityBackgroundBlurOverlay } from '../Framework/Reader/ReaderAbilityBackgroundBlurOverlay';
import { FileEditorOpenParams } from '../Framework/Editor/FileEditorService';
import {
  FileEditorAbilityParamStore,
  FileEditorAbilityWindowPayload
} from '../Framework/Editor/FileEditorAbilityParamStore';

const TAG: string = 'FileEditorAbilityPage';

class FileEditorNavigationFrameCallback extends FrameCallback {
  private callback: () => void;
  private hasRun: boolean = false;

  constructor(callback: () => void) {
    super();
    this.callback = callback;
  }

  onFrame(_frameTimeInNano: number): void {
  }

  onIdle(_timeLeftInNano: number): void {
    if (this.hasRun) {
      return;
    }
    this.hasRun = true;
    this.callback();
  }
}

@Entry
@Component
struct FileEditorAbilityPage {
  private pathStack: NavPathStack = new NavPathStack();
  @State private editorParams: FileEditorOpenParams | null = null;
  private editorInstanceId: string = '';
  private hasOpenedEditor: boolean = false;
  private hasScheduledInitialEditorOpen: boolean = false;
  private navigationScheduleGeneration: number = 0;
  private isPageActive: boolean = false;
  private scheduledFrameCallback: FileEditorNavigationFrameCallback | null = null;

  aboutToAppear(): void {
    this.isPageActive = true;
    this.resolveEditorLaunchPayload('appear');
    this.scheduleInitialEditorOpen();
  }

  onPageShow(): void {
    this.isPageActive = true;
    if (this.hasOpenedEditor) {
      return;
    }
    this.resolveEditorLaunchPayload('page_show');
    this.scheduleInitialEditorOpen();
  }

  aboutToDisappear(): void {
    this.isPageActive = false;
    this.navigationScheduleGeneration += 1;
    this.hasScheduledInitialEditorOpen = false;
    this.scheduledFrameCallback = null;
  }

  private scheduleInitialEditorOpen(): void {
    if (!this.isPageActive ||
      this.hasOpenedEditor ||
      this.hasScheduledInitialEditorOpen) {
      return;
    }
    try {
      const uiContext: UIContext = this.getUIContext();
      const scheduleGeneration: number = this.navigationScheduleGeneration + 1;
      this.navigationScheduleGeneration = scheduleGeneration;
      this.hasScheduledInitialEditorOpen = true;
      const frameCallback = new FileEditorNavigationFrameCallback((): void => {
        if (scheduleGeneration !== this.navigationScheduleGeneration) {
          return;
        }
        this.scheduledFrameCallback = null;
        this.hasScheduledInitialEditorOpen = false;
        if (!this.isPageActive || this.hasOpenedEditor) {
          return;
        }
        this.resolveEditorLaunchPayload('frame_idle');
        this.openInitialEditor();
      });
      this.scheduledFrameCallback = frameCallback;
      uiContext.postFrameCallback(frameCallback);
    } catch (error) {
      this.scheduledFrameCallback = null;
      this.hasScheduledInitialEditorOpen = false;
      logger.warn(TAG, `调度独立文件编辑器初始路由失败: ${String(error)}`);
    }
  }

  private resolveEditorLaunchPayload(source: string): void {
    if (this.editorParams) {
      return;
    }
    const store = FileEditorAbilityParamStore.getInstance();
    const windowId = this.resolveHostWindowId();
    let payload: FileEditorAbilityWindowPayload | null = store.resolveWindowPayload(windowId);
    if (!payload) {
      payload = store.consumePendingPayload();
    }
    if (!payload) {
      logger.error(TAG, `独立文件编辑器参数未绑定: source=${source}, windowId=${windowId}`);
      return;
    }
    this.editorParams = payload.params;
    this.editorInstanceId = payload.instanceId;
    logger.info(TAG, `独立文件编辑器参数已解析: source=${source}, instanceId=${this.editorInstanceId}, windowId=${windowId}, payloadWindowId=${payload.windowId}`);
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
      logger.warn(TAG, `获取独立文件编辑器页面窗口ID失败: ${String(error)}`);
      return -1;
    }
  }

  private openInitialEditor(): boolean {
    if (this.hasOpenedEditor) {
      return true;
    }

    if (!this.editorParams) {
      logger.error(TAG, `独立文件编辑器参数为空: instanceId=${this.editorInstanceId}`);
      return false;
    }

    this.pathStack.pushPathByName('FileEditorPage', this.editorParams, false);
    this.hasOpenedEditor = true;
    logger.info(TAG, `打开独立文件编辑器目标页: instanceId=${this.editorInstanceId}`);
    return true;
  }

  @Builder
  private buildDestination(name: string, _param: Object) {
    if (name === 'FileEditorPage') {
      FileEditorPage()
    }
  }

  @Builder
  private buildFallbackContent() {
    Column() {
      Text('文件编辑器启动失败')
        .fontSize(18)
        .fontColor(Color.White)
      Text('未获取到编辑参数')
        .fontSize(13)
        .fontColor(Color.White)
        .opacity(0.6)
        .margin({ top: 8 })
    }
    .width('100%')
    .height('100%')
    .justifyContent(FlexAlign.Center)
    .backgroundColor(Color.Black)
  }

  build() {
    Stack() {
      Navigation(this.pathStack) {
        if (!this.editorParams) {
          this.buildFallbackContent()
        } else {
          Column() {
            Blank()
          }
          .width('100%')
          .height('100%')
          .backgroundColor(Color.Black)
        }
      }
      .hideNavBar(true)
      .navDestination(this.buildDestination)
      .mode(NavigationMode.Stack)
      .width('100%')
      .height('100%')
      .backgroundColor(Color.Black)
      ReaderAbilityBackgroundBlurOverlay()
    }
    .width('100%')
    .height('100%')
    .backgroundColor(Color.Black)
  }
}
