import { common, StartOptions, Want } from '@kit.AbilityKit';
import { logger } from 'manxia_core/src/main/ets/Utils/Logger';
import { SOURCE_DETAIL_ABILITY_NAME } from './SourceDetailAbilityConstants';
import { SourceDetailAbilityParamStore } from './SourceDetailAbilityParamStore';

const TAG: string = 'SourceDetailReturnCoordinator';
const APP_BUNDLE_NAME: string = 'com.dlzz.manxia';

export class SourceDetailReturnCoordinator {
  public static async restoreSourceDetailAbility(
    abilityContext: common.UIAbilityContext | null,
    instanceId: string,
    sourceTag: string
  ): Promise<boolean> {
    if (instanceId.length <= 0) {
      logger.warn(TAG, `独立图源详情恢复失败: source=${sourceTag}, reason=empty instanceId`);
      return false;
    }

    const restoredByWindow: boolean = await SourceDetailReturnCoordinator.restoreSourceDetailWindow(
      instanceId,
      sourceTag
    );
    if (restoredByWindow) {
      return true;
    }

    return await SourceDetailReturnCoordinator.startSourceDetailAbility(
      abilityContext,
      instanceId,
      sourceTag
    );
  }

  private static async restoreSourceDetailWindow(instanceId: string, sourceTag: string): Promise<boolean> {
    const sourceWindow = SourceDetailAbilityParamStore.getInstance().getWindowHandle(instanceId);
    if (!sourceWindow) {
      logger.warn(TAG, `未找到独立图源详情窗口句柄，准备兜底拉起: source=${sourceTag}, instanceId=${instanceId}`);
      return false;
    }

    try {
      await sourceWindow.showWindow();
      logger.info(TAG, `已恢复独立图源详情原窗口: source=${sourceTag}, instanceId=${instanceId}`);
      return true;
    } catch (error) {
      logger.warn(TAG, `恢复独立图源详情原窗口失败，准备兜底拉起: source=${sourceTag}, instanceId=${instanceId}, error=${String(error)}`);
      return false;
    }
  }

  private static async startSourceDetailAbility(
    abilityContext: common.UIAbilityContext | null,
    instanceId: string,
    sourceTag: string
  ): Promise<boolean> {
    const storedParamsAvailable: boolean =
      SourceDetailAbilityParamStore.getInstance().getParams(instanceId) !== null;
    if (!storedParamsAvailable) {
      logger.warn(TAG, `兜底拉起独立图源详情取消: source=${sourceTag}, instanceId=${instanceId}, reason=params unavailable`);
      return false;
    }

    if (!abilityContext) {
      logger.warn(TAG, `兜底拉起独立图源详情失败: source=${sourceTag}, reason=AbilityContext unavailable`);
      return false;
    }

    const want: Want = {
      bundleName: APP_BUNDLE_NAME,
      abilityName: SOURCE_DETAIL_ABILITY_NAME,
      parameters: {
        'sourceDetailAbilityInstanceId': instanceId
      }
    };
    const options: StartOptions = {
      withAnimation: true
    };

    try {
      await abilityContext.startAbility(want, options);
      logger.info(TAG, `已兜底拉起独立图源详情: source=${sourceTag}, instanceId=${instanceId}`);
      return true;
    } catch (error) {
      logger.warn(TAG, `兜底拉起独立图源详情失败: source=${sourceTag}, instanceId=${instanceId}, error=${String(error)}`);
      return false;
    }
  }
}
