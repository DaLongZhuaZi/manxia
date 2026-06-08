import { common } from '@kit.AbilityKit';
import { logger } from '../Utils/Logger';
import { FileEditorPage } from './FileEditorPage';
import { ReaderAbilityBackgroundBlurOverlay } from '../Framework/Reader/ReaderAbilityBackgroundBlurOverlay';
import { FileEditorOpenParams } from '../Framework/Editor/FileEditorService';
import {
  FileEditorAbilityParamStore,
  FileEditorAbilityWindowPayload
} from '../Framework/Editor/FileEditorAbilityParamStore';

const TAG: string = 'FileEditorAbilityPage';

@Entry
@Component
struct FileEditorAbilityPage {
  @State private pathStack: NavPathStack = new NavPathStack();
  @State private editorParams: FileEditorOpenParams | null = null;
  @State private editorInstanceId: string = '';
  private hasOpenedEditor: boolean = false;

  aboutToAppear(): void {
    this.resolveEditorLaunchPayload('appear');
    this.openInitialEditor();
    setTimeout((): void => {
      this.resolveEditorLaunchPayload('deferred');
      this.openInitialEditor();
    }, 0);
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

  private openInitialEditor(): void {
    if (this.hasOpenedEditor) {
      return;
    }

    if (!this.editorParams) {
      logger.error(TAG, `独立文件编辑器参数为空: instanceId=${this.editorInstanceId}`);
      return;
    }

    this.hasOpenedEditor = true;
    logger.info(TAG, `打开独立文件编辑器目标页: instanceId=${this.editorInstanceId}`);
    this.pathStack.pushPathByName('FileEditorPage', this.editorParams);
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
