import { UIContext } from '@kit.ArkUI';
import { logger } from './Logger';
import { ISettingsManagerFacade, SettingsManagerHolder } from '../Framework/Contracts/ISettingsManagerFacade';
import { SettingKeys } from '../Framework/Contracts/SettingKeys';
import {
  OrientationLockManager,
  OrientationLockPriority,
  OrientationLockStrategy
} from './OrientationLockManager';

const TAG: string = 'ReaderOrientationLockHelper';

/**
 * 全局「锁定方向」设置的作用域。
 * TEXT  = 全局小说/文本阅读设置（GLOBAL_TEXT_LOCK_DEVICE_ORIENTATION）
 * EBOOK = 全局电子书阅读设置（GLOBAL_EBOOK_LOCK_DEVICE_ORIENTATION）
 */
export enum ReaderOrientationLockScope {
  TEXT = 'TEXT',
  EBOOK = 'EBOOK'
}

export class ReaderOrientationLockHelper {
  /**
   * 读取全局方向锁开关。
   * 全局开关是"总开关"语义：只要全局打开，所有阅读都锁定方向，
   * 不再被单本书已保存的 lockDeviceOrientation=false 影子覆盖。
   */
  static isGlobalOrientationLockEnabled(scope: ReaderOrientationLockScope): boolean {
    try {
      const settingsManager: ISettingsManagerFacade = SettingsManagerHolder.get();
      const key: string = scope === ReaderOrientationLockScope.TEXT
        ? SettingKeys.GLOBAL_TEXT_LOCK_DEVICE_ORIENTATION
        : SettingKeys.GLOBAL_EBOOK_LOCK_DEVICE_ORIENTATION;
      return settingsManager.getBoolean(key, false);
    } catch (error) {
      logger.warn(TAG, `读取全局方向锁失败: scope=${scope}, error=${String(error)}`);
      return false;
    }
  }

  /**
   * 合并"全局开关"与"书籍级开关"，得到最终是否需要锁定方向。
   * 语义：全局开 = 一律锁定；全局关 = 由书籍级开关（阅读器内开关）决定。
   */
  static resolveOrientationLockEnabled(
    scope: ReaderOrientationLockScope,
    primary: boolean,
    secondary: boolean = false
  ): boolean {
    return primary || secondary || ReaderOrientationLockHelper.isGlobalOrientationLockEnabled(scope);
  }

  static syncCurrentOrientationLock(
    owner: string,
    token: string,
    enabled: boolean,
    uiContext?: UIContext
  ): string {
    if (enabled) {
      if (token.length > 0) {
        const updated = OrientationLockManager.updatePageLock(
          token,
          OrientationLockStrategy.LOCK_CURRENT,
          uiContext,
          OrientationLockPriority.PAGE
        );
        if (updated) {
          return token;
        }
      }
      return OrientationLockManager.acquirePageLock(
        owner,
        OrientationLockStrategy.LOCK_CURRENT,
        uiContext,
        OrientationLockPriority.PAGE
      );
    }

    if (token.length > 0) {
      OrientationLockManager.releaseLock(token, uiContext);
    }
    return '';
  }

  static release(token: string, uiContext?: UIContext): string {
    if (token.length > 0) {
      OrientationLockManager.releaseLock(token, uiContext);
    }
    return '';
  }
}
