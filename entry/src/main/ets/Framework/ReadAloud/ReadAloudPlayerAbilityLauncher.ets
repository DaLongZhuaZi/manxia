import { common, StartOptions, Want } from '@kit.AbilityKit';
import { UIContext } from '@kit.ArkUI';
import { logger } from '../../Utils/Logger';
import { DisplayMode } from '../../Utils/WindowManager';
import { NovelReaderPageParams } from '../../pages/NovelBookshelfPage';
import {
  READ_ALOUD_PLAYER_ABILITY_NAME,
  READ_ALOUD_PLAYER_ABILITY_REFRESH_TRIGGER_KEY
} from './ReadAloudPlayerAbilityConstants';
import {
  ReadAloudPlayerAbilityParams,
  ReadAloudPlayerAbilityParamStore
} from './ReadAloudPlayerAbilityParamStore';

const TAG: string = 'ReadAloudPlayerAbilityLauncher';
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
  params: NovelReaderPageParams | null,
  sourceTag: string,
  reason: string
): void {
  if (!fallbackStack) {
    logger.error(TAG, `独立听书播放器不可用且无回退导航栈: source=${sourceTag}, reason=${reason}`);
    return;
  }

  logger.warn(TAG, `独立听书播放器启动失败，回退主实例导航: source=${sourceTag}, reason=${reason}`);
  if (params) {
    fallbackStack.pushPathByName('ReadAloudPlayerPage', params);
  } else {
    fallbackStack.pushPathByName('ReadAloudPlayerPage', undefined);
  }
}

function buildPlayerWant(instanceId: string): Want {
  const want: Want = {
    bundleName: APP_BUNDLE_NAME,
    abilityName: READ_ALOUD_PLAYER_ABILITY_NAME,
    parameters: {
      'readAloudPlayerAbilityInstanceId': instanceId
    }
  };
  return want;
}

function buildPlayerParams(
  returnHostPage: string,
  returnDisplayMode: DisplayMode | null,
  launchParams: NovelReaderPageParams | null
): ReadAloudPlayerAbilityParams {
  const params = new ReadAloudPlayerAbilityParams();
  params.returnHostPage = returnHostPage;
  params.returnDisplayMode = returnDisplayMode;
  params.launchParams = launchParams;
  return params;
}

export function openReadAloudPlayerInIsolatedAbility(
  uiContext: UIContext | null | undefined,
  fallbackStack: NavPathStack | null | undefined,
  sourceTag: string,
  returnHostPage: string = '',
  returnDisplayMode: DisplayMode | null = null,
  launchParams: NovelReaderPageParams | null = null,
  useSystemStartAnimation: boolean = true
): boolean {
  const abilityContext = getAbilityContext(uiContext);
  if (!abilityContext) {
    fallbackToNavStack(fallbackStack, launchParams, sourceTag, 'UIAbilityContext unavailable');
    return false;
  }

  const store = ReadAloudPlayerAbilityParamStore.getInstance();
  const params = buildPlayerParams(returnHostPage, returnDisplayMode, launchParams);
  const instanceId = store.register(params);
  AppStorage.setOrCreate(READ_ALOUD_PLAYER_ABILITY_REFRESH_TRIGGER_KEY, Date.now());

  const want = buildPlayerWant(instanceId);
  const options: StartOptions = {
    withAnimation: useSystemStartAnimation
  };

  abilityContext.startAbility(want, options).then((): void => {
    logger.info(
      TAG,
      `已启动独立听书播放器实例: source=${sourceTag}, instanceId=${instanceId}, returnHost=${returnHostPage}, systemAnimation=${useSystemStartAnimation}`
    );
  }).catch((error: Object | string | number | boolean): void => {
    store.remove(instanceId);
    fallbackToNavStack(fallbackStack, launchParams, sourceTag, String(error));
  });

  return true;
}
