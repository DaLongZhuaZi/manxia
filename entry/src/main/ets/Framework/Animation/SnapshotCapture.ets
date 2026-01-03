// 文件路径: entry/src/main/ets/Framework/Animation/SnapshotCapture.ets
// 职责: 条目快照捕获工具，用于生成Canvas绘制所需的PixelMap

import { logger } from '../../Utils/Logger';
import { componentSnapshot } from '@kit.ArkUI';
import { image } from '@kit.ImageKit';

const TAG = 'SnapshotCapture';

/**
 * 快照捕获选项
 */
export interface SnapshotOptions {
  scale: number;           // 缩放比例（用于控制快照质量）
  waitTime: number;        // 等待时间（毫秒，确保组件渲染完成）
}

/**
 * 默认快照选项
 */
export const DEFAULT_SNAPSHOT_OPTIONS: SnapshotOptions = {
  scale: 1.0,
  waitTime: 50
};

/**
 * 快照捕获器类
 */
export class SnapshotCapture {
  private uiContext: UIContext | null = null;

  /**
   * 初始化UIContext
   */
  public init(uiContext: UIContext): void {
    this.uiContext = uiContext;
  }

  /**
   * 捕获单个组件的快照
   * @param componentId 组件ID
   * @param options 快照选项
   * @returns PixelMap或null
   */
  public async captureComponent(
    componentId: string,
    options?: Partial<SnapshotOptions>
  ): Promise<PixelMap | null> {
    if (!this.uiContext) {
      logger.error(TAG, 'UIContext未初始化');
      return null;
    }

    const opts: SnapshotOptions = {
      scale: options?.scale ?? DEFAULT_SNAPSHOT_OPTIONS.scale,
      waitTime: options?.waitTime ?? DEFAULT_SNAPSHOT_OPTIONS.waitTime
    };

    try {
      // 等待组件渲染完成
      if (opts.waitTime > 0) {
        await this.delay(opts.waitTime);
      }

      // 捕获快照
      const pixelMap = await componentSnapshot.get(componentId, {
        scale: opts.scale
      });

      if (!pixelMap) {
        logger.warn(TAG, `组件快照捕获失败: ${componentId}`);
        return null;
      }

      logger.debug(TAG, `成功捕获组件快照: ${componentId}`);
      return pixelMap;
    } catch (err) {
      const msg = err instanceof Error ? err.message : String(err);
      logger.error(TAG, `捕获组件快照异常: ${componentId}, ${msg}`);
      return null;
    }
  }

  /**
   * 批量捕获多个组件的快照
   * @param componentIds 组件ID列表
   * @param options 快照选项
   * @returns Map<componentId, PixelMap>
   */
  public async captureComponents(
    componentIds: string[],
    options?: Partial<SnapshotOptions>
  ): Promise<Map<string, PixelMap>> {
    const snapshots = new Map<string, PixelMap>();
    const opts: SnapshotOptions = {
      scale: options?.scale ?? DEFAULT_SNAPSHOT_OPTIONS.scale,
      waitTime: options?.waitTime ?? DEFAULT_SNAPSHOT_OPTIONS.waitTime
    };

    logger.debug(TAG, `开始批量捕获快照: ${componentIds.length}个组件`);

    // 等待渲染完成
    if (opts.waitTime > 0) {
      await this.delay(opts.waitTime);
    }

    // 并发捕获所有快照
    const capturePromises = componentIds.map(async (id) => {
      try {
        const pixelMap = await componentSnapshot.get(id, {
          scale: opts.scale
        });
        if (pixelMap) {
          snapshots.set(id, pixelMap);
        }
      } catch (err) {
        const msg = err instanceof Error ? err.message : String(err);
        logger.warn(TAG, `捕获快照失败: ${id}, ${msg}`);
      }
    });

    await Promise.all(capturePromises);

    logger.debug(TAG, `批量捕获完成: ${snapshots.size}/${componentIds.length}个成功`);
    return snapshots;
  }

  /**
   * 从PixelMap创建ImageBitmap（用于Canvas绘制）
   * @param pixelMap PixelMap对象
   * @returns ImageBitmap或null
   */
  public async createImageBitmap(pixelMap: PixelMap): Promise<ImageBitmap | null> {
    try {
      // HarmonyOS中PixelMap可以直接用于Canvas绘制
      // 这里只是一个占位方法，实际使用时直接传递PixelMap即可
      return null;
    } catch (err) {
      const msg = err instanceof Error ? err.message : String(err);
      logger.error(TAG, `创建ImageBitmap失败: ${msg}`);
      return null;
    }
  }

  /**
   * 释放PixelMap资源
   * @param pixelMap PixelMap对象
   */
  public releasePixelMap(pixelMap: PixelMap): void {
    try {
      pixelMap.release();
    } catch (err) {
      const msg = err instanceof Error ? err.message : String(err);
      logger.warn(TAG, `释放PixelMap失败: ${msg}`);
    }
  }

  /**
   * 批量释放PixelMap资源
   * @param pixelMaps PixelMap映射
   */
  public releasePixelMaps(pixelMaps: Map<string, PixelMap>): void {
    pixelMaps.forEach((pixelMap, id) => {
      try {
        pixelMap.release();
      } catch (err) {
        const msg = err instanceof Error ? err.message : String(err);
        logger.warn(TAG, `释放PixelMap失败: ${id}, ${msg}`);
      }
    });
    pixelMaps.clear();
  }

  /**
   * 延迟工具方法
   */
  private delay(ms: number): Promise<void> {
    return new Promise(resolve => setTimeout(resolve, ms));
  }

  /**
   * 检查组件是否存在
   * @param componentId 组件ID
   * @returns 是否存在
   */
  public async checkComponentExists(componentId: string): Promise<boolean> {
    try {
      const pixelMap = await componentSnapshot.get(componentId, { scale: 0.1 });
      if (pixelMap) {
        pixelMap.release();
        return true;
      }
      return false;
    } catch {
      return false;
    }
  }
}

/**
 * 全局快照捕获器实例
 */
let globalSnapshotCapture: SnapshotCapture | null = null;

/**
 * 获取全局快照捕获器实例
 */
export function getSnapshotCapture(): SnapshotCapture {
  if (!globalSnapshotCapture) {
    globalSnapshotCapture = new SnapshotCapture();
  }
  return globalSnapshotCapture;
}
