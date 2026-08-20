import { common, StartOptions, Want } from '@kit.AbilityKit';
import { UIContext } from '@kit.ArkUI';
import { logger } from 'manxia_core/src/main/ets/Utils/Logger';
import type { SourceDetailParams } from '../../pages/SourceDetailPage';
import { SOURCE_DETAIL_ABILITY_NAME } from 'manxia_source_engine/src/main/ets/Framework/Source/SourceDetailAbilityConstants';
import { SourceDetailAbilityParamStore } from './SourceDetailAbilityParamStore';

const TAG: string = 'SourceDetailAbilityLauncher';
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
  params: SourceDetailParams,
  sourceTag: string,
  reason: string
): void {
  if (!fallbackStack) {
    logger.error(TAG, `独立图源详情不可用且无回退导航栈: source=${sourceTag}, reason=${reason}`);
    return;
  }

  logger.warn(TAG, `独立图源详情启动失败，回退主实例导航: source=${sourceTag}, reason=${reason}`);
  if ((params.sourceDetailWindowKey || '').length <= 0) {
    fallbackStack.removeByName('SourceDetailPage');
  }
  fallbackStack.pushPathByName('SourceDetailPage', params);
}

function buildSourceDetailWant(instanceId: string): Want {
  const want: Want = {
    bundleName: APP_BUNDLE_NAME,
    abilityName: SOURCE_DETAIL_ABILITY_NAME,
    parameters: {
      'sourceDetailAbilityInstanceId': instanceId
    }
  };
  return want;
}

export function openSourceDetailInIsolatedAbility(
  uiContext: UIContext | null | undefined,
  fallbackStack: NavPathStack | null | undefined,
  params: SourceDetailParams,
  sourceTag: string,
  useSystemStartAnimation: boolean = true
): boolean {
  const abilityContext = getAbilityContext(uiContext);
  if (!abilityContext) {
    fallbackToNavStack(fallbackStack, params, sourceTag, 'UIAbilityContext unavailable');
    return false;
  }

  const store = SourceDetailAbilityParamStore.getInstance();
  const instanceId = store.register(params);
  const want = buildSourceDetailWant(instanceId);
  const options: StartOptions = {
    withAnimation: useSystemStartAnimation
  };

  abilityContext.startAbility(want, options).then((): void => {
    logger.info(TAG, `已启动独立图源详情实例: source=${sourceTag}, instanceId=${instanceId}, sourceId=${params.sourceId}`);
  }).catch((error: Object | string | number | boolean): void => {
    store.remove(instanceId);
    fallbackToNavStack(fallbackStack, params, sourceTag, String(error));
  });

  return true;
}
