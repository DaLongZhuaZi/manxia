import { logger } from '../../Utils/Logger';
import { DisplayMode, WindowManager } from '../../Utils/WindowManager';
import { PageWindowCoordinator } from '../../Utils/PageWindowCoordinator';

const TAG: string = 'ReaderHostWindowRestoreCoordinator';
const PENDING_KEY: string = 'readerHostWindowRestorePending';
const SOURCE_PAGE_KEY: string = 'readerHostWindowRestoreSourcePage';
const INSTANCE_ID_KEY: string = 'readerHostWindowRestoreInstanceId';
const REQUESTED_AT_KEY: string = 'readerHostWindowRestoreRequestedAt';

export class ReaderHostWindowRestoreCoordinator {
  static requestRestore(sourcePageName: string, instanceId: string): void {
    AppStorage.setOrCreate<boolean>(PENDING_KEY, true);
    AppStorage.setOrCreate<string>(SOURCE_PAGE_KEY, sourcePageName);
    AppStorage.setOrCreate<string>(INSTANCE_ID_KEY, instanceId);
    AppStorage.setOrCreate<number>(REQUESTED_AT_KEY, Date.now());
    logger.info(TAG, `已记录独立阅读器返回窗口恢复: source=${sourcePageName}, instanceId=${instanceId}`);
  }

  static clearRestore(instanceId: string): void {
    const storedInstanceId = AppStorage.get<string>(INSTANCE_ID_KEY) || '';
    if (storedInstanceId.length > 0 && storedInstanceId !== instanceId) {
      return;
    }
    ReaderHostWindowRestoreCoordinator.clearRestoreState();
    logger.info(TAG, `已清理独立阅读器返回窗口恢复: instanceId=${instanceId}`);
  }

  static applyPendingRestore(trigger: string): boolean {
    const pending = AppStorage.get<boolean>(PENDING_KEY) === true;
    if (!pending) {
      return false;
    }

    const sourcePageName = AppStorage.get<string>(SOURCE_PAGE_KEY) || '';
    const topPageName = ReaderHostWindowRestoreCoordinator.resolveCurrentMainPageName();
    const targetPageName = topPageName.length > 0 ? topPageName : sourcePageName;
    const targetMode = ReaderHostWindowRestoreCoordinator.resolveTargetMode(targetPageName);

    ReaderHostWindowRestoreCoordinator.clearRestoreState();
    ReaderHostWindowRestoreCoordinator.applyTargetModeRepeatedly(targetMode);
    logger.info(TAG, `已恢复主实例窗口模式: trigger=${trigger}, source=${sourcePageName}, top=${targetPageName}, mode=${targetMode}`);
    return true;
  }

  private static clearRestoreState(): void {
    AppStorage.setOrCreate<boolean>(PENDING_KEY, false);
    AppStorage.setOrCreate<string>(SOURCE_PAGE_KEY, '');
    AppStorage.setOrCreate<string>(INSTANCE_ID_KEY, '');
    AppStorage.setOrCreate<number>(REQUESTED_AT_KEY, 0);
  }

  private static resolveCurrentMainPageName(): string {
    try {
      const stack = AppStorage.get<NavPathStack>('GlobalNavStack');
      if (!stack) {
        return 'MainMenuPage';
      }
      const pathNames = stack.getAllPathName();
      if (pathNames.length <= 0) {
        return 'MainMenuPage';
      }
      return pathNames[pathNames.length - 1];
    } catch (error) {
      logger.warn(TAG, `解析主实例当前页面失败: ${String(error)}`);
      return '';
    }
  }

  private static resolveTargetMode(pageName: string): DisplayMode {
    const resolvedMode = PageWindowCoordinator.resolveDisplayModeForPage(pageName);
    if (resolvedMode) {
      return resolvedMode;
    }
    return DisplayMode.DEFAULT;
  }

  private static applyTargetModeRepeatedly(targetMode: DisplayMode): void {
    WindowManager.setDisplayMode(targetMode);
    setTimeout((): void => {
      WindowManager.setDisplayMode(targetMode);
    }, 96);
    setTimeout((): void => {
      WindowManager.setDisplayMode(targetMode);
    }, 240);
  }
}
