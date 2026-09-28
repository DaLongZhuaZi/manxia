import { common } from '@kit.AbilityKit';
import { FrameCallback, UIContext } from '@kit.ArkUI';
import { logger } from 'manxia_core/src/main/ets/Utils/Logger';
import { SourceDetailPage } from './SourceDetailPage';
import type { SourceDetailParams } from './SourceDetailPage';
import { SourceSettingsPage } from './SourceSettingsPage';
import { SourceLoginPage } from './SourceLoginPage';
import {
  SOURCE_DETAIL_ABILITY_HOST_MULTITON,
  SOURCE_DETAIL_ABILITY_INSTANCE_ID_KEY
} from 'manxia_source_engine/src/main/ets/Framework/Source/SourceDetailAbilityConstants';
import {
  SourceDetailAbilityParamStore,
  SourceDetailAbilityWindowPayload
} from '../Framework/Source/SourceDetailAbilityParamStore';

const TAG: string = 'SourceDetailAbilityPage';
let sourceDetailAbilityPageStorage: LocalStorage = new LocalStorage();

class SourceDetailNavigationFrameCallback extends FrameCallback {
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

@Entry(sourceDetailAbilityPageStorage)
@Component
struct SourceDetailAbilityPage {
  @Provide('NavPathStack') pathStack: NavPathStack = new NavPathStack();
  @State private sourceDetailParams: SourceDetailParams | null = null;
  @LocalStorageProp(SOURCE_DETAIL_ABILITY_INSTANCE_ID_KEY) private sourceDetailInstanceId: string = '';
  private hasOpenedSourceDetail: boolean = false;
  private hasScheduledInitialSourceDetailOpen: boolean = false;
  private navigationScheduleGeneration: number = 0;
  private isPageActive: boolean = false;
  private scheduledFrameCallback: SourceDetailNavigationFrameCallback | null = null;

  aboutToAppear(): void {
    this.isPageActive = true;
    this.resolveSourceDetailLaunchPayload('appear');
    this.scheduleInitialSourceDetailOpen();
  }

  onPageShow(): void {
    this.isPageActive = true;
    if (this.hasOpenedSourceDetail) {
      return;
    }
    this.resolveSourceDetailLaunchPayload('page_show');
    this.scheduleInitialSourceDetailOpen();
  }

  aboutToDisappear(): void {
    this.isPageActive = false;
    this.navigationScheduleGeneration += 1;
    this.hasScheduledInitialSourceDetailOpen = false;
    this.scheduledFrameCallback = null;
  }

  private scheduleInitialSourceDetailOpen(): void {
    if (!this.isPageActive ||
      this.hasOpenedSourceDetail ||
      this.hasScheduledInitialSourceDetailOpen) {
      return;
    }
    try {
      const uiContext: UIContext = this.getUIContext();
      const scheduleGeneration: number = this.navigationScheduleGeneration + 1;
      this.navigationScheduleGeneration = scheduleGeneration;
      this.hasScheduledInitialSourceDetailOpen = true;
      const frameCallback = new SourceDetailNavigationFrameCallback((): void => {
        if (scheduleGeneration !== this.navigationScheduleGeneration) {
          return;
        }
        this.scheduledFrameCallback = null;
        this.hasScheduledInitialSourceDetailOpen = false;
        if (!this.isPageActive || this.hasOpenedSourceDetail) {
          return;
        }
        this.resolveSourceDetailLaunchPayload('frame_idle');
        this.openInitialSourceDetail();
      });
      this.scheduledFrameCallback = frameCallback;
      uiContext.postFrameCallback(frameCallback);
    } catch (error) {
      this.scheduledFrameCallback = null;
      this.hasScheduledInitialSourceDetailOpen = false;
      logger.warn(TAG, `调度独立图源详情初始路由失败: ${String(error)}`);
    }
  }

  private resolveSourceDetailLaunchPayload(source: string): void {
    if (this.sourceDetailParams) {
      return;
    }

    const store = SourceDetailAbilityParamStore.getInstance();
    const windowId = this.resolveHostWindowId();
    let payload: SourceDetailAbilityWindowPayload | null = store.resolveWindowPayload(windowId);
    if (!payload) {
      payload = store.consumePendingPayload();
    }
    if (!payload && this.sourceDetailInstanceId.length > 0) {
      const params = store.getParams(this.sourceDetailInstanceId);
      if (params) {
        this.sourceDetailParams = this.buildIsolatedSourceDetailParams(params);
        logger.info(TAG, `独立图源详情参数已从实例恢复: source=${source}, instanceId=${this.sourceDetailInstanceId}`);
        return;
      }
    }
    if (!payload) {
      logger.error(TAG, `独立图源详情参数未绑定: source=${source}, windowId=${windowId}`);
      return;
    }

    this.sourceDetailInstanceId = payload.instanceId;
    this.sourceDetailParams = this.buildIsolatedSourceDetailParams(payload.params);
    logger.info(TAG, `独立图源详情参数已解析: source=${source}, instanceId=${this.sourceDetailInstanceId}, windowId=${windowId}, payloadWindowId=${payload.windowId}`);
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
      logger.warn(TAG, `获取独立图源详情页面窗口ID失败: ${String(error)}`);
      return -1;
    }
  }

  private openInitialSourceDetail(): boolean {
    if (this.hasOpenedSourceDetail) {
      return true;
    }

    if (!this.sourceDetailParams) {
      logger.error(TAG, `独立图源详情参数为空: instanceId=${this.sourceDetailInstanceId}`);
      return false;
    }

    this.pathStack.pushPathByName('SourceDetailPage', this.sourceDetailParams, false);
    this.hasOpenedSourceDetail = true;
    logger.info(TAG, `打开独立图源详情目标页: instanceId=${this.sourceDetailInstanceId}, sourceId=${this.sourceDetailParams.sourceId}`);
    return true;
  }

  private buildIsolatedSourceDetailParams(source: SourceDetailParams | null): SourceDetailParams | null {
    if (!source) {
      return null;
    }

    const windowKey = (source.sourceDetailWindowKey || '').length > 0
      ? source.sourceDetailWindowKey
      : this.sourceDetailInstanceId;
    const params: SourceDetailParams = {
      sourceId: source.sourceId,
      initialTab: source.initialTab,
      searchKeyword: source.searchKeyword,
      searchType: source.searchType,
      fromGlobalSearch: source.fromGlobalSearch,
      globalSearchSessionId: source.globalSearchSessionId,
      sourceDetailAbilityInstanceId: this.sourceDetailInstanceId,
      sourceDetailWindowKey: windowKey,
      sourceDetailHostMode: SOURCE_DETAIL_ABILITY_HOST_MULTITON,
      sourceName: source.sourceName,
      sourcePkg: source.sourcePkg,
      comicId: source.comicId,
      comicTitle: source.comicTitle
    };
    return params;
  }

  @Builder
  private buildDestination(name: string, _param: Object) {
    if (name === 'SourceDetailPage') {
      SourceDetailPage()
    } else if (name === 'SourceSettingsPage') {
      SourceSettingsPage()
    } else if (name === 'SourceLoginPage') {
      SourceLoginPage()
    }
  }

  @Builder
  private buildFallbackContent() {
    Column() {
      Text('图源详情启动失败')
        .fontSize(18)
        .fontColor($r('sys.color.font_primary'))
      Text('未获取到图源详情参数')
        .fontSize(13)
        .fontColor($r('sys.color.font_secondary'))
        .margin({ top: 8 })
    }
    .width('100%')
    .height('100%')
    .justifyContent(FlexAlign.Center)
    .backgroundColor($r('sys.color.background_primary'))
  }

  build() {
    Navigation(this.pathStack) {
      if (!this.sourceDetailParams) {
        this.buildFallbackContent()
      } else {
        Column() {
          Blank()
        }
        .width('100%')
        .height('100%')
        .backgroundColor($r('sys.color.background_primary'))
      }
    }
    .hideNavBar(true)
    .navDestination(this.buildDestination)
    .mode(NavigationMode.Stack)
    .width('100%')
    .height('100%')
    .backgroundColor($r('sys.color.background_primary'))
  }
}
