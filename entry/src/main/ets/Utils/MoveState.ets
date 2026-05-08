/**
 * 移动操作状态管理（@Observed）
 * 用于书库中漫画/电子书/小说的移动到分类/书架操作
 */
import { ContentType } from '../Framework/Data/BookshelfCategoryManager';

@Observed
export class MoveState {
  mangaId: string = '';
  ebookId: string = '';
  novelId: string = '';
  contentType: string = 'manga';
  toShelfItemId: string = '';
  toShelfContentType: ContentType = ContentType.MANGA;

  reset(): void {
    this.mangaId = '';
    this.ebookId = '';
    this.novelId = '';
    this.contentType = 'manga';
  }

  resetShelfMove(): void {
    this.toShelfItemId = '';
    this.toShelfContentType = ContentType.MANGA;
  }
}
