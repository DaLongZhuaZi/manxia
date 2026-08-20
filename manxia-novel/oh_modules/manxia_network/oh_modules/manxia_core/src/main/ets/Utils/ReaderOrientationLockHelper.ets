import { UIContext } from '@kit.ArkUI';
import {
  OrientationLockManager,
  OrientationLockPriority,
  OrientationLockStrategy
} from './OrientationLockManager';

export class ReaderOrientationLockHelper {
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
