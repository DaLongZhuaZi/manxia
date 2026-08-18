import { AbilityConstant, UIAbility, Want } from '@kit.AbilityKit';
import { window } from '@kit.ArkUI';
import { logger } from './Utils/Logger';

const TAG: string = 'LegadoArkWebConformanceAbility';
const CONFORMANCE_PAGE: string = 'pages/LegadoArkWebConformancePage';

/**
 * 仅由自动兼容性总控显式启动的 ArkWeb 宿主。
 * 它不参与正常导航，也不处理任何真实书源或用户数据。
 */
export default class LegadoArkWebConformanceAbility extends UIAbility {
  onCreate(_want: Want, _launchParam: AbilityConstant.LaunchParam): void {
    logger.lifecycle(TAG, 'onCreate', 'ArkWeb conformance fixture ability created.');
  }

  onWindowStageCreate(windowStage: window.WindowStage): void {
    windowStage.loadContent(CONFORMANCE_PAGE, (error) => {
      if (error && error.code !== 0) {
        logger.error(TAG, `加载 ArkWeb conformance 页面失败: ${JSON.stringify(error)}`);
        return;
      }
      logger.info(TAG, 'ArkWeb conformance 页面已加载。');
    });
  }

  onDestroy(): void {
    logger.lifecycle(TAG, 'onDestroy', 'ArkWeb conformance fixture ability destroyed.');
  }
}
