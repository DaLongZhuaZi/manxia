import { window } from '@kit.ArkUI';
import { BusinessError } from '@kit.BasicServicesKit';
import { logger } from '../../Utils/Logger';
import { READER_ABILITY_WINDOW_BACKGROUND_KEY } from './MangaReaderAbilityConstants';

export class ReaderAbilityWindowLifecycleController {
  private tag: string;
  private instanceId: string;
  private localStorage: LocalStorage;
  private pauseToken: string;
  private windowStage: window.WindowStage | null = null;
  private mainWindow: window.Window | null = null;
  private windowStageEventCallback: ((event: window.WindowStageEventType) => void) | null = null;
  private isWindowInBackground: boolean = false;
  private isPrivacyModeEnabled: boolean = false;

  constructor(tag: string, instanceId: string, localStorage: LocalStorage) {
    this.tag = tag;
    this.instanceId = instanceId;
    this.localStorage = localStorage;
    this.pauseToken = `${tag}:${instanceId}`;
    this.localStorage.setOrCreate<boolean>(READER_ABILITY_WINDOW_BACKGROUND_KEY, false);
  }

  public attach(windowStage: window.WindowStage): void {
    this.detach();
    this.windowStage = windowStage;
    this.windowStageEventCallback = (event: window.WindowStageEventType): void => {
      this.handleWindowStageEvent(event);
    };
    try {
      this.mainWindow = this.resolveMainWindow(windowStage);
      windowStage.on('windowStageEvent', this.windowStageEventCallback);
      this.applyWindowBackgroundState(false, 'attach');
      logger.info(this.tag, `独立阅读器窗口生命周期监听已注册: instanceId=${this.instanceId}`);
    } catch (error) {
      this.windowStageEventCallback = null;
      this.windowStage = null;
      this.mainWindow = null;
      logger.warn(this.tag, `注册独立阅读器窗口生命周期监听失败: ${String(error)}`);
    }
  }

  public detach(): void {
    if (this.windowStage && this.windowStageEventCallback) {
      try {
        this.windowStage.off('windowStageEvent', this.windowStageEventCallback);
      } catch (error) {
        logger.warn(this.tag, `解除独立阅读器窗口生命周期监听失败: ${String(error)}`);
      }
    }
    this.applyWindowBackgroundState(false, 'detach');
    this.windowStageEventCallback = null;
    this.windowStage = null;
    this.mainWindow = null;
  }

  public markAbilityForeground(): void {
    this.applyWindowBackgroundState(false, 'ability.onForeground');
  }

  public markAbilityBackground(): void {
    this.applyWindowBackgroundState(true, 'ability.onBackground');
  }

  private handleWindowStageEvent(event: window.WindowStageEventType): void {
    const nextBackground = this.resolveWindowBackgroundState(event);
    const eventName = this.getWindowStageEventName(event);
    if (nextBackground === null) {
      logger.debug(this.tag, `独立阅读器窗口事件已忽略: instanceId=${this.instanceId}, event=${eventName}`);
      return;
    }
    this.applyWindowBackgroundState(nextBackground, eventName);
  }

  private applyWindowBackgroundState(isInBackground: boolean, source: string): void {
    if (this.isWindowInBackground === isInBackground) {
      this.localStorage.setOrCreate<boolean>(READER_ABILITY_WINDOW_BACKGROUND_KEY, isInBackground);
      this.applyPrivacyMode(isInBackground, source);
      return;
    }

    this.isWindowInBackground = isInBackground;
    this.localStorage.setOrCreate<boolean>(READER_ABILITY_WINDOW_BACKGROUND_KEY, isInBackground);

    if (isInBackground) {
      logger.info(this.tag, `独立阅读器窗口已进入后台: instanceId=${this.instanceId}, source=${source}`);
      this.applyPrivacyMode(true, source);
      logger.pauseBackgroundOutput(this.pauseToken);
      return;
    }

    logger.resumeBackgroundOutput(this.pauseToken);
    this.applyPrivacyMode(false, source);
    logger.info(this.tag, `独立阅读器窗口已恢复前台: instanceId=${this.instanceId}, source=${source}`);
  }

  private resolveMainWindow(windowStage: window.WindowStage): window.Window | null {
    try {
      return windowStage.getMainWindowSync();
    } catch (error) {
      logger.warn(this.tag, `获取独立阅读器主窗口失败: instanceId=${this.instanceId}, reason=${String(error)}`);
      return null;
    }
  }

  private shouldEnablePrivacyMode(isInBackground: boolean): boolean {
    if (!isInBackground) {
      return false;
    }
    return AppStorage.get<boolean>('backgroundBlurEnabled') === true;
  }

  private getWindowLifecycleErrorMessage(error: BusinessError | Error): string {
    const message = (error as Error).message ?? '';
    if (message.length > 0) {
      return message;
    }
    return String(error);
  }

  private getWindowLifecycleErrorCode(error: BusinessError | Error): number {
    return (error as BusinessError).code;
  }

  private isWindowLifecycleAbnormalError(error: BusinessError | Error): boolean {
    if (this.getWindowLifecycleErrorCode(error) === 1300002) {
      return true;
    }
    const message = this.getWindowLifecycleErrorMessage(error);
    return message.includes('window state is abnormal') ||
      message.includes('not created or destroyed') ||
      message.includes('Get top window failed');
  }

  private applyPrivacyMode(isInBackground: boolean, source: string): void {
    const shouldEnable = this.shouldEnablePrivacyMode(isInBackground);
    if (this.isPrivacyModeEnabled === shouldEnable) {
      return;
    }
    if (!this.mainWindow) {
      logger.warn(this.tag, `独立阅读器隐私窗口模式跳过: instanceId=${this.instanceId}, enabled=${shouldEnable}, source=${source}`);
      this.isPrivacyModeEnabled = false;
      return;
    }

    this.isPrivacyModeEnabled = shouldEnable;
    this.mainWindow.setWindowPrivacyMode(shouldEnable).then((): void => {
      logger.info(this.tag, `独立阅读器隐私窗口模式已更新: instanceId=${this.instanceId}, enabled=${shouldEnable}, source=${source}`);
    }).catch((error: BusinessError): void => {
      if (source === 'detach' && !shouldEnable && this.isWindowLifecycleAbnormalError(error)) {
        this.isPrivacyModeEnabled = false;
        logger.debug(
          this.tag,
          `独立阅读器隐私窗口模式关闭跳过: instanceId=${this.instanceId}, enabled=${shouldEnable}, ` +
            `source=${source}, code=${this.getWindowLifecycleErrorCode(error)}, ` +
            `windowLifecycle=destroyed_or_detached, reason=${this.getWindowLifecycleErrorMessage(error)}`
        );
        return;
      }
      logger.warn(this.tag, `独立阅读器隐私窗口模式更新失败: instanceId=${this.instanceId}, enabled=${shouldEnable}, source=${source}, reason=${JSON.stringify(error)}`);
      this.isPrivacyModeEnabled = !shouldEnable;
    });
  }

  private resolveWindowBackgroundState(event: window.WindowStageEventType): boolean | null {
    switch (event) {
      case window.WindowStageEventType.HIDDEN:
      case window.WindowStageEventType.PAUSED:
        return true;
      case window.WindowStageEventType.SHOWN:
      case window.WindowStageEventType.ACTIVE:
      case window.WindowStageEventType.RESUMED:
        return false;
      case window.WindowStageEventType.INACTIVE:
        return null;
      default:
        return null;
    }
  }

  private getWindowStageEventName(event: window.WindowStageEventType): string {
    switch (event) {
      case window.WindowStageEventType.SHOWN:
        return 'SHOWN';
      case window.WindowStageEventType.ACTIVE:
        return 'ACTIVE';
      case window.WindowStageEventType.INACTIVE:
        return 'INACTIVE';
      case window.WindowStageEventType.HIDDEN:
        return 'HIDDEN';
      case window.WindowStageEventType.RESUMED:
        return 'RESUMED';
      case window.WindowStageEventType.PAUSED:
        return 'PAUSED';
      default:
        return 'UNKNOWN';
    }
  }
}
