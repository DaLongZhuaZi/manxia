// Responsibility: choose the concrete ArkUI Image input for normal manga reader surfaces.

import { image } from '@kit.ImageKit';
import {
  ImageSourceType,
  MangaPage
} from '../Models/MangaModels';

export type MangaDisplayInputValue = Resource | string | image.PixelMap;

export class MangaDisplayInputRequest {
  public page: MangaPage | null = null;
  public pagePixelMap: image.PixelMap | null = null;
  public localCachePixelMap: image.PixelMap | null = null;
  public resourceInput: MangaDisplayInputValue = $r('app.media.ic_image');
  public fallbackInput: MangaDisplayInputValue = $r('app.media.ic_image');
  public allowNetworkResourceWithoutPixelMap: boolean = false;
  public preferLocalCachePixelMap: boolean = false;
}

export class MangaDisplayInputResult {
  public input: MangaDisplayInputValue = $r('app.media.ic_image');
  public sourceKind: string = 'fallback';
}

export class MangaDisplayInputResolver {
  public resolve(request: MangaDisplayInputRequest): MangaDisplayInputResult {
    const result: MangaDisplayInputResult = new MangaDisplayInputResult();
    if (!request.page) {
      result.input = request.fallbackInput;
      result.sourceKind = 'fallback';
      return result;
    }

    if (request.pagePixelMap) {
      result.input = request.pagePixelMap;
      result.sourceKind = 'page_pixel_map';
      return result;
    }

    if (request.preferLocalCachePixelMap && request.localCachePixelMap) {
      result.input = request.localCachePixelMap;
      result.sourceKind = 'local_cache_pixel_map';
      return result;
    }

    if (request.page.sourceType === ImageSourceType.NETWORK && !request.allowNetworkResourceWithoutPixelMap) {
      result.input = request.fallbackInput;
      result.sourceKind = 'network_fallback';
      return result;
    }

    result.input = request.resourceInput;
    result.sourceKind = 'resource';
    return result;
  }
}
