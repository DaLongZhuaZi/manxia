/**
 * 右键菜单状态管理（@Observed）
 * 用于 Library Manga/EBook/Novel 和 Discover 页的长按菜单，以及图源菜单
 *
 * 使用方式：
 *   @State mangaContextMenu: ContextMenuState<Manga> = new ContextMenuState<Manga>();
 *   mangaContextMenu.showMenu(manga, anchorKey);
 *   mangaContextMenu.item  // 类型为 Manga | null
 */
@Observed
export class ContextMenuState<T> {
  show: boolean = false;
  item: T | null = null;
  anchorKey: string = '';

  showMenu(item: T, anchorKey: string = ''): void {
    this.item = item;
    this.anchorKey = anchorKey;
    this.show = true;
  }

  hide(): void {
    this.show = false;
    this.item = null;
    this.anchorKey = '';
  }
}
