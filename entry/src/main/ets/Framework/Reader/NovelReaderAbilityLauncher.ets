import { common, StartOptions, Want } from '@kit.AbilityKit';
import { UIContext } from '@kit.ArkUI';
import { logger } from 'manxia_core/src/main/ets/Utils/Logger';
import { NovelReaderPageParams } from '../../pages/NovelBookshelfPage';
import { NOVEL_READER_ABILITY_NAME } from 'manxia_reader_ui/src/main/ets/Framework/Reader/MangaReaderAbilityConstants';
import { NovelReaderAbilityParamStore } from './NovelReaderAbilityParamStore';
import { isReaderPageMultitonEnabled } from './ReaderPageMultitonSettings';
import { ReaderHostWindowRestoreCoordinator } from 'manxia_reader_ui/src/main/ets/Framework/Reader/ReaderHostWindowRestoreCoordinator';

const TAG: string = 'NovelReaderAbilityLauncher';
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

function fallbackToNavStack(
  fallbackStack: NavPathStack | null | undefined,
  params: NovelReaderPageParams,
  sourceTag: string,
  reason: string
): void {
  if (!fallbackStack) {
    logger.error(TAG, `独立小说阅读器不可用且无回退导航栈: source=${sourceTag}, reason=${reason}`);
    return;
  }

  logger.warn(TAG, `独立小说阅读器启动失败，回退主实例导航: source=${sourceTag}, reason=${reason}`);
  fallbackStack.pushPathByName('NovelReaderPage', params);
}

function buildReaderWant(instanceId: string): Want {
  const want: Want = {
    bundleName: APP_BUNDLE_NAME,
    abilityName: NOVEL_READER_ABILITY_NAME,
    parameters: {
      'novelReaderAbilityInstanceId': instanceId
    }
  };
  return want;
}

export function openNovelReaderInIsolatedAbility(
  uiContext: UIContext | null | undefined,
  fallbackStack: NavPathStack | null | undefined,
  params: NovelReaderPageParams,
  sourceTag: string,
  useSystemStartAnimation: boolean = true
): boolean {
  if (!isReaderPageMultitonEnabled()) {
    return false;
  }

  const abilityContext = getAbilityContext(uiContext);
  if (!abilityContext) {
    logger.warn(TAG, `独立小说阅读器启动上下文不可用，交由调用方同步回退: source=${sourceTag}`);
    return false;
  }

  const store = NovelReaderAbilityParamStore.getInstance();
  const instanceId = store.register(params);
  ReaderHostWindowRestoreCoordinator.requestRestore(sourceTag, instanceId);
  const want = buildReaderWant(instanceId);
  const options: StartOptions = {
    withAnimation: useSystemStartAnimation
  };

  abilityContext.startAbility(want, options).then((): void => {
    logger.info(TAG, `已启动独立小说阅读器实例: source=${sourceTag}, instanceId=${instanceId}, systemAnimation=${useSystemStartAnimation}`);
  }).catch((error: Object | string | number | boolean): void => {
    store.remove(instanceId);
    ReaderHostWindowRestoreCoordinator.clearRestore(instanceId);
    fallbackToNavStack(fallbackStack, params, sourceTag, String(error));
  });

  return true;
}
