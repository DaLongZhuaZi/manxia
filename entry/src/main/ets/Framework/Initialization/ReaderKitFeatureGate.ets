/**
 * ReaderKit 临时开关（用于模拟器/调试环境）。
 * 需要重新启用 ReaderKit 时，将其改为 `true`。
 */
export const READER_KIT_ENABLED: boolean = true;

export function isReaderKitEnabled(): boolean {
  return READER_KIT_ENABLED;
}
