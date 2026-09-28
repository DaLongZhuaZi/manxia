/**
 * 滑动手势状态管理（@Observed）
 * 用于 Library Manga/EBook/Novel 列表项的左滑操作
 */
@Observed
export class SwipeGestureState {
  activeId: string = '';
  isActive: boolean = false;
  offset: number = 0;
  readonly threshold: number = 80;

  reset(): void {
    this.activeId = '';
    this.isActive = false;
    this.offset = 0;
  }

  activate(id: string): void {
    this.activeId = id;
    this.isActive = true;
    this.offset = 0;
  }
}
