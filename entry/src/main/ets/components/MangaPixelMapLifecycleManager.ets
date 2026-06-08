// 职责: 管理 MangaViewer 中 PixelMap 的原生资源生命周期，不触碰 UI 或阅读模式判断。

import { image } from '@kit.ImageKit';
import { ImageCacheManager } from '../Framework/Cache/ImageCacheManager';

export class MangaPixelMapMeta {
  public path: string = '';
  public size: number = 0;
}

export class MangaPixelMapLifecycleResult {
  public changed: boolean = false;
  public releasedCount: number = 0;
}

export class MangaPixelMapLifecycleManager {
  public isUsable(pixelMaps: Map<string, image.PixelMap>, pageId: string): boolean {
    const pixelMap: image.PixelMap | undefined = pixelMaps.get(pageId);
    if (!pixelMap) {
      return false;
    }

    try {
      const info = pixelMap.getImageInfoSync();
      if (!info || !info.size) {
        return false;
      }
      return info.size.width > 0 && info.size.height > 0;
    } catch (_error) {
      return false;
    }
  }

  public incrementEpoch(epochByPage: Map<string, number>, pageId: string): void {
    const current: number | undefined = epochByPage.get(pageId);
    const next: number = current && current > 0 ? current + 1 : 1;
    epochByPage.set(pageId, next);
  }

  public getEpoch(epochByPage: Map<string, number>, pageId: string): number {
    const current: number | undefined = epochByPage.get(pageId);
    if (current && current > 0) {
      return current;
    }
    return 0;
  }

  public dropReference(
    pixelMaps: Map<string, image.PixelMap>,
    metaByPage: Map<string, MangaPixelMapMeta>,
    epochByPage: Map<string, number>,
    pageId: string,
    releasePixelMap: boolean
  ): MangaPixelMapLifecycleResult {
    const result: MangaPixelMapLifecycleResult = new MangaPixelMapLifecycleResult();
    const pixelMap: image.PixelMap | undefined = pixelMaps.get(pageId);
    if (pixelMap) {
      this.evictPixelMap(pixelMap);
      if (releasePixelMap) {
        this.releasePixelMap(pixelMap);
        result.releasedCount = 1;
      }
    }

    const hadPixelMap: boolean = pixelMaps.delete(pageId);
    const hadMeta: boolean = metaByPage.delete(pageId);
    if (hadPixelMap || hadMeta) {
      this.incrementEpoch(epochByPage, pageId);
      result.changed = true;
    }
    return result;
  }

  public releaseAll(pixelMaps: Map<string, image.PixelMap>): MangaPixelMapLifecycleResult {
    const result: MangaPixelMapLifecycleResult = new MangaPixelMapLifecycleResult();
    pixelMaps.forEach((pixelMap: image.PixelMap) => {
      this.evictPixelMap(pixelMap);
      this.releasePixelMap(pixelMap);
      result.releasedCount = result.releasedCount + 1;
    });
    result.changed = result.releasedCount > 0;
    return result;
  }

  public releasePixelMap(pixelMap: image.PixelMap): void {
    try {
      pixelMap.release();
    } catch (_error) {
    }
  }

  public evictPixelMap(pixelMap: image.PixelMap): void {
    try {
      ImageCacheManager.getInstance().evictFromMemoryCacheByPixelMap(pixelMap);
    } catch (_error) {
    }
  }
}
