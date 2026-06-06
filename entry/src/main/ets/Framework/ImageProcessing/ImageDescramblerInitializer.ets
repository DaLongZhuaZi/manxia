/**
 * 图片解扰器初始化模块
 * 在应用启动时注册所有解扰算法
 */

import { logger } from '../../Utils/Logger';
import { ImageDescramblerRegistry } from './ImageDescramblerRegistry';
import { JinmantiantangDescrambler } from './JinmantiantangDescrambler';
import { ImageInterceptor } from './ImageInterceptor';

const TAG = 'ImageDescramblerInitializer';

/**
 * 初始化图片解扰系统
 */
export function initializeImageDescrambler(): void {
  try {
    logger.info(TAG, '开始初始化图片解扰系统');
    
    // 1. 获取注册中心实例
    const registry = ImageDescramblerRegistry.getInstance();
    
    // 2. 注册禁漫天堂解扰算法
    const jinmantiantangDescrambler = new JinmantiantangDescrambler();
    registry.register(jinmantiantangDescrambler);
    logger.info(TAG, `已注册解扰算法: ${jinmantiantangDescrambler.name} v${jinmantiantangDescrambler.version}`);
    
    // 3. 获取拦截器实例（确保单例已创建）
    const interceptor = ImageInterceptor.getInstance();
    logger.info(TAG, '图片拦截器已初始化');
    
    // 4. 列出所有已注册的算法
    const algorithms = registry.list();
    logger.info(TAG, `图片解扰系统初始化完成，已注册${algorithms.length}个算法: ${algorithms.join(', ')}`);
    
  } catch (error) {
    logger.error(TAG, `图片解扰系统初始化失败: ${error}`);
    throw error;
  }
}

/**
 * 为图源配置解扰器
 * 从JSON配置中读取解扰参数并注册到拦截器
 */
export function configureDescramblerForSource(sourceId: number, config: Record<string, Object | undefined>): void {
  try {
    // 检查是否有imageDescrambler配置
    const descramblerConfig = config.imageDescrambler as Record<string, Object | undefined> | undefined;
    if (!descramblerConfig) {
      logger.debug(TAG, `图源${sourceId}未配置图片解扰`);
      return;
    }
    
    const enabled = descramblerConfig.enabled as boolean;
    if (!enabled) {
      logger.debug(TAG, `图源${sourceId}的图片解扰已禁用`);
      return;
    }
    
    // 注册到拦截器
    const interceptor = ImageInterceptor.getInstance();
    interceptor.registerSource(sourceId, {
      algorithm: descramblerConfig.algorithm as string || 'jinmantiantang',
      enabled: true,
      urlPattern: descramblerConfig.urlPattern as string || 'media/photos',
      parameters: descramblerConfig as Record<string, Object | undefined>
    });
    
    logger.info(TAG, `已为图源${sourceId}配置图片解扰: algorithm=${descramblerConfig.algorithm}`);
    
  } catch (error) {
    logger.error(TAG, `为图源${sourceId}配置解扰器失败: ${error}`);
  }
}

/**
 * 清理图源的解扰配置
 */
export function cleanupDescramblerForSource(sourceId: number): void {
  try {
    const interceptor = ImageInterceptor.getInstance();
    interceptor.unregisterSource(sourceId);
    interceptor.clearCache(sourceId);
    logger.info(TAG, `已清理图源${sourceId}的解扰配置`);
  } catch (error) {
    logger.error(TAG, `清理图源${sourceId}的解扰配置失败: ${error}`);
  }
}
