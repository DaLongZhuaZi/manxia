import { common, StartOptions, Want } from '@kit.AbilityKit';
import { UIContext } from '@kit.ArkUI';
import { logger } from 'manxia_core/src/main/ets/Utils/Logger';
import { FileEditorOpenFactory } from './FileEditorOpenFactory';
import { FileEditorOpenParams } from './FileEditorService';
import {
  FILE_EDITOR_ABILITY_HOST_MODE,
  FILE_EDITOR_ABILITY_NAME
} from './FileEditorAbilityConstants';
import { FileEditorAbilityParamStore } from './FileEditorAbilityParamStore';

const TAG: string = 'FileEditorAbilityLauncher';
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

function reportOpenFailure(sourceTag: string, reason: string): void {
  logger.error(TAG, `独立文件编辑器启动失败: source=${sourceTag}, reason=${reason}`);
}

function buildEditorWant(instanceId: string): Want {
  const want: Want = {
    bundleName: APP_BUNDLE_NAME,
    abilityName: FILE_EDITOR_ABILITY_NAME,
    parameters: {
      'fileEditorAbilityInstanceId': instanceId
    }
  };
  return want;
}

export function openFileEditorInIsolatedAbility(
  uiContext: UIContext | null | undefined,
  params: FileEditorOpenParams,
  sourceTag: string,
  useSystemStartAnimation: boolean = true
): boolean {
  const abilityContext = getAbilityContext(uiContext);
  const isolatedParams: FileEditorOpenParams = {
    instanceId: params.instanceId,
    sessionId: params.sessionId,
    hostMode: FILE_EDITOR_ABILITY_HOST_MODE,
    filePath: params.filePath,
    content: params.content,
    language: params.language,
    readOnly: params.readOnly,
    title: params.title,
    origin: params.origin,
    saveTarget: params.saveTarget
  };
  const editorParams: FileEditorOpenParams = FileEditorOpenFactory.createParams(isolatedParams);
  if (!abilityContext) {
    reportOpenFailure(sourceTag, 'UIAbilityContext unavailable');
    return false;
  }

  const store = FileEditorAbilityParamStore.getInstance();
  const instanceId = store.register(editorParams);
  const want = buildEditorWant(instanceId);
  const options: StartOptions = {
    withAnimation: useSystemStartAnimation
  };

  abilityContext.startAbility(want, options).then((): void => {
    logger.info(TAG, `已启动独立文件编辑器实例: source=${sourceTag}, instanceId=${instanceId}, systemAnimation=${useSystemStartAnimation}`);
  }).catch((error: Object | string | number | boolean): void => {
    store.remove(instanceId);
    reportOpenFailure(sourceTag, String(error));
  });

  return true;
}
