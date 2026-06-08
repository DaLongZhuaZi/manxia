import { ImageSourceType, MangaPage } from '../Models/MangaModels';

// 职责: 统一解析漫画页面的本地文件路径，不参与加载、缓存或 UI 状态管理。
export class MangaPagePathResolver {
  public getLocalFilePath(page: MangaPage): string | undefined {
    if (page.sourceType !== ImageSourceType.LOCAL) {
      return undefined;
    }

    let candidate: string = '';
    if (page.localPath && page.localPath.length > 0) {
      candidate = page.localPath;
    } else if (page.imagePath && page.imagePath.length > 0) {
      candidate = page.imagePath;
    } else if (page.imageUrl && page.imageUrl.length > 0) {
      candidate = page.imageUrl;
    }

    if (!candidate || candidate.length === 0) {
      return undefined;
    }
    if (candidate.startsWith('file://')) {
      return candidate.substring(7);
    }
    if (candidate.startsWith('/')) {
      return candidate;
    }
    if (candidate.startsWith('storage/') || candidate.startsWith('data/')) {
      return '/' + candidate;
    }
    return undefined;
  }
}
