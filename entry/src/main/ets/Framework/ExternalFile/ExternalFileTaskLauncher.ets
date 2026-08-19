import { common, StartOptions, Want } from '@kit.AbilityKit';
import { UIContext } from '@kit.ArkUI';
import { logger } from 'manxia_core/src/main/ets/Utils/Logger';
import {
  EXTERNAL_FILE_TASK_ABILITY_NAME
} from './ExternalFileTaskAbilityConstants';
import { ExternalFileTaskParamStore } from './ExternalFileTaskParamStore';
import { ExternalFileTaskFactory, ExternalFileTaskParams } from './ExternalFileTaskTypes';

const TAG: string = 'ExternalFileTaskLauncher';
const APP_BUNDLE_NAME: string = 'com.dlzz.manxia';

type ExternalFileTaskStartContext = common.UIAbilityContext | common.UIExtensionContext;

interface ExternalFileTaskWantParameters {
  externalFileTaskAbilityInstanceId: string;
  externalFileTaskAbilityParamsJson: string;
}

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

function buildTaskWant(instanceId: string, params: ExternalFileTaskParams): Want {
  const storedParams = ExternalFileTaskFactory.withInstanceId(params, instanceId);
  const wantParameters: ExternalFileTaskWantParameters = {
    externalFileTaskAbilityInstanceId: instanceId,
    externalFileTaskAbilityParamsJson: ExternalFileTaskFactory.serialize(storedParams)
  };
  const want: Want = {
    bundleName: APP_BUNDLE_NAME,
    abilityName: EXTERNAL_FILE_TASK_ABILITY_NAME,
    parameters: wantParameters as Object as Record<string, Object>
  };
  return want;
}

export async function openExternalFileTaskInIsolatedAbilityByContext(
  abilityContext: ExternalFileTaskStartContext | null | undefined,
  params: ExternalFileTaskParams,
  sourceTag: string,
  useSystemStartAnimation: boolean = true
): Promise<boolean> {
  if (!abilityContext) {
    logger.error(TAG, `外部文件独立任务启动失败: source=${sourceTag}, reason=AbilityContext unavailable`);
    return false;
  }

  const store = ExternalFileTaskParamStore.getInstance();
  const instanceId = store.register(params);
  const want = buildTaskWant(instanceId, params);
  const options: StartOptions = {
    withAnimation: useSystemStartAnimation
  };

  try {
    await abilityContext.startAbility(want, options);
    logger.info(TAG, `已启动外部文件独立任务: source=${sourceTag}, instanceId=${instanceId}, kind=${params.kind}`);
    return true;
  } catch (error) {
    store.remove(instanceId);
    logger.warn(TAG, `外部文件独立任务启动失败: source=${sourceTag}, instanceId=${instanceId}, reason=${String(error)}`);
    return false;
  }
}

export async function openExternalFileTaskInIsolatedAbility(
  uiContext: UIContext | null | undefined,
  params: ExternalFileTaskParams,
  sourceTag: string,
  useSystemStartAnimation: boolean = true
): Promise<boolean> {
  return openExternalFileTaskInIsolatedAbilityByContext(
    getAbilityContext(uiContext),
    params,
    sourceTag,
    useSystemStartAnimation
  );
}

export function buildExternalFileTaskWantForFallback(params: ExternalFileTaskParams): Want {
  const store = ExternalFileTaskParamStore.getInstance();
  const instanceId = store.register(params);
  return buildTaskWant(instanceId, params);
}
