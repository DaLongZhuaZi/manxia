import { common, StartOptions, Want } from '@kit.AbilityKit';
import { UIContext } from '@kit.ArkUI';
import { logger } from 'manxia_core/src/main/ets/Utils/Logger';
import { EBookReaderParams } from '../../pages/EBookReaderRouteTypes';
import { EBOOK_READER_ABILITY_NAME } from './MangaReaderAbilityConstants';
import { EBookReaderAbilityParamStore } from './EBookReaderAbilityParamStore';
import { isReaderPageMultitonEnabled } from './ReaderPageMultitonSettings';
import { ReaderHostWindowRestoreCoordinator } from './ReaderHostWindowRestoreCoordinator';

const TAG: string = 'EBookReaderAbilityLauncher';
const APP_BUNDLE_NAME: string = 'com.dlzz.manxia';

function getAbilityContext(uiContext: UIContext | null | undefined): common.UIAbilityContext | null {
  if (!uiContext) {
    return null;
  }
  const hostContext = uiContext.getHostContext();
  if (!hostContext) {
    return null;
  }
  return hostContext as common.UIAbilityContext;
}

function fallbackToRoutePage(
  fallbackStack: NavPathStack | null | undefined,
  params: EBookReaderParams,
  sourceTag: string,
  reason: string,
  onStartFailure?: () => void
): void {
  if (onStartFailure) {
    logger.warn(TAG, `独立电子书阅读器启动失败，执行自定义回退: source=${sourceTag}, reason=${reason}`);
    onStartFailure();
    return;
  }

  if (!fallbackStack) {
    logger.error(TAG, `独立电子书阅读器不可用且无回退导航栈: source=${sourceTag}, reason=${reason}`);
    return;
  }

  logger.warn(TAG, `独立电子书阅读器启动失败，回退主实例路由页: source=${sourceTag}, reason=${reason}`);
  fallbackStack.pushPathByName('EBookReaderRoutePage', params);
}

function buildReaderWant(instanceId: string): Want {
  const want: Want = {
    bundleName: APP_BUNDLE_NAME,
    abilityName: EBOOK_READER_ABILITY_NAME,
    parameters: {
      'eBookReaderAbilityInstanceId': instanceId
    }
  };
  return want;
}

export function openEBookReaderInIsolatedAbility(
  uiContext: UIContext | null | undefined,
  fallbackStack: NavPathStack | null | undefined,
  params: EBookReaderParams,
  sourceTag: string,
  useSystemStartAnimation: boolean = true,
  onStartFailure?: () => void
): boolean {
  if (!isReaderPageMultitonEnabled()) {
    return false;
  }

  const abilityContext = getAbilityContext(uiContext);
  if (!abilityContext) {
    logger.warn(TAG, `独立电子书阅读器启动上下文不可用，交由调用方同步回退: source=${sourceTag}`);
    return false;
  }

  const store = EBookReaderAbilityParamStore.getInstance();
  const instanceId = store.register(params);
  ReaderHostWindowRestoreCoordinator.requestRestore(sourceTag, instanceId);
  const want = buildReaderWant(instanceId);
  const options: StartOptions = {
    withAnimation: useSystemStartAnimation
  };

  abilityContext.startAbility(want, options).then((): void => {
    logger.info(TAG, `已启动独立电子书阅读器实例: source=${sourceTag}, instanceId=${instanceId}, systemAnimation=${useSystemStartAnimation}`);
  }).catch((error: Object | string | number | boolean): void => {
    store.remove(instanceId);
    ReaderHostWindowRestoreCoordinator.clearRestore(instanceId);
    fallbackToRoutePage(fallbackStack, params, sourceTag, String(error), onStartFailure);
  });

  return true;
}
