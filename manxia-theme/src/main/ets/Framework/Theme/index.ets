/**
 * 主题系统统一导出
 * 
 * 使用方式：
 * ```typescript
 * import { AppColors, ThemeColorState, ThemeColorManager, ColorRole } from '../Framework/Theme';
 * ```
 */

// 导出静态颜色访问类
export { AppColors, ColorRole, ThemePalette } from './AppColors';

// 导出响应式主题色状态
export { ThemeColorState, ThemeColorManager, createThemeColors } from './ThemeColors';
export type { ThemeColorUpdateCallback } from './ThemeColors';
