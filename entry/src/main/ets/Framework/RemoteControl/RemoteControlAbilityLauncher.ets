import { common, StartOptions, Want } from '@kit.AbilityKit';
import { UIContext } from '@kit.ArkUI';
import { logger } from '../../Utils/Logger';
import { ContinuationTriggeredPayload } from '../EventBus';
import {
  REMOTE_CONTROL_ABILITY_NAME,
  REMOTE_CONTROL_ABILITY_REFRESH_TRIGGER_KEY
} from './RemoteControlAbilityConstants';
import { RemoteControlAbilityParamStore } from './RemoteControlAbilityParamStore';

const TAG: string = 'RemoteControlAbilityLauncher';
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
  params: ContinuationTriggeredPayload,
  sourceTag: string,
  reason: string
): void {
  if (!fallbackStack) {
    logger.error(TAG, `独立遥控器不可用且无回退导航栈: source=${sourceTag}, reason=${reason}`);
    return;
  }

  logger.warn(TAG, `独立遥控器启动失败，回退主实例导航: source=${sourceTag}, reason=${reason}`);
  fallbackStack.pushPathByName('RemoteControlPage', params);
}

function buildRemoteControlWant(instanceId: string): Want {
  const want: Want = {
    bundleName: APP_BUNDLE_NAME,
    abilityName: REMOTE_CONTROL_ABILITY_NAME,
    parameters: {
      'remoteControlAbilityInstanceId': instanceId
    }
  };
  return want;
}

export function openRemoteControlInIsolatedAbility(
  uiContext: UIContext | null | undefined,
  fallbackStack: NavPathStack | null | undefined,
  params: ContinuationTriggeredPayload,
  sourceTag: string,
  useSystemStartAnimation: boolean = true
): boolean {
  const abilityContext = getAbilityContext(uiContext);
  if (!abilityContext) {
    fallbackToNavStack(fallbackStack, params, sourceTag, 'UIAbilityContext unavailable');
    return false;
  }

  const store = RemoteControlAbilityParamStore.getInstance();
  const instanceId = store.register(params);
  AppStorage.setOrCreate(REMOTE_CONTROL_ABILITY_REFRESH_TRIGGER_KEY, Date.now());
  const want = buildRemoteControlWant(instanceId);
  const options: StartOptions = {
    withAnimation: useSystemStartAnimation
  };

  abilityContext.startAbility(want, options).then((): void => {
    logger.info(TAG, `已启动独立遥控器实例: source=${sourceTag}, instanceId=${instanceId}, sessionId=${params.sessionId}`);
  }).catch((error: Object | string | number | boolean): void => {
    store.remove(instanceId);
    fallbackToNavStack(fallbackStack, params, sourceTag, String(error));
  });

  return true;
}
