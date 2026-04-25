import { UIContext } from '@kit.ArkUI';
import { logger } from '../../Utils/Logger';
import { EBookReaderParams } from '../../pages/EBookReaderRouteTypes';

const TAG = 'EBookReaderRouteNavigator';

export function openEBookReaderRouterPage(
  uiContext: UIContext | null | undefined,
  params: EBookReaderParams,
  sourceTag: string
): boolean {
  const router = uiContext?.getRouter();
  if (!router) {
    logger.error(TAG, `无法打开电子书阅读器：Router 不可用，source=${sourceTag}`);
    return false;
  }

  router.pushUrl({
    url: 'pages/EBookReaderRoutePage',
    params: params
  }).then((): void => {
    logger.info(TAG, `已通过独立路由打开电子书阅读器: source=${sourceTag}, bookId=${params.bookId}`);
  }).catch((error: Object | string | number | boolean): void => {
    logger.error(TAG, `独立路由打开电子书阅读器失败: source=${sourceTag}, error=${String(error)}`);
  });
  return true;
}
