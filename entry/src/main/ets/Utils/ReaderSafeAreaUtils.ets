export class ReaderSafeAreaUtils {
  static readonly DEFAULT_STATUS_BAR_INSET: number = 24;
  static readonly TOP_TOOLBAR_ROW_HEIGHT: number = 56;

  static getStatusBarInset(statusBarHeight: number): number {
    return statusBarHeight > 0 ? statusBarHeight : ReaderSafeAreaUtils.DEFAULT_STATUS_BAR_INSET;
  }

  static getTopToolbarHeight(
    statusBarHeight: number,
    rowHeight: number = ReaderSafeAreaUtils.TOP_TOOLBAR_ROW_HEIGHT
  ): number {
    return ReaderSafeAreaUtils.getStatusBarInset(statusBarHeight) + rowHeight;
  }
}
