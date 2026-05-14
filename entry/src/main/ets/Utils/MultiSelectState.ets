/**
 * 多选状态管理（@Observed）
 * 用于 Library Manga/EBook/Novel 和 Discover 页的多选操作
 */
@Observed
export class MultiSelectState {
  isActive: boolean = false;
  selectedIds: Set<string> = new Set();
  isDeleting: boolean = false;

  toggle(id: string): void {
    const nextSelectedIds: Set<string> = new Set(this.selectedIds);
    if (nextSelectedIds.has(id)) {
      nextSelectedIds.delete(id);
    } else {
      nextSelectedIds.add(id);
    }
    this.selectedIds = nextSelectedIds;
    this.isActive = this.selectedIds.size > 0;
  }

  selectAll(ids: string[]): void {
    this.selectedIds = new Set(ids);
    this.isActive = this.selectedIds.size > 0;
  }

  deselectAll(): void {
    this.selectedIds = new Set();
    this.isActive = false;
  }

  clear(): void {
    this.selectedIds = new Set();
    this.isActive = false;
    this.isDeleting = false;
  }

  has(id: string): boolean {
    return this.selectedIds.has(id);
  }

  get size(): number {
    return this.selectedIds.size;
  }
}
