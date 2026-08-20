/** 动画设置契约（R3 批2 类型下沉）。entry AnimationSettingsManager 本地导入并再导出。 */

export interface AnimationSettings {
  // 书籍打开/关闭动画
  bookOpenEnabled: boolean;       // 书籍打开动画开关
  bookCloseEnabled: boolean;      // 书籍关闭动画开关
  bookOpenDuration: number;       // 书籍打开动画时长(ms)
  bookCloseDuration: number;      // 书籍关闭动画时长(ms)
  // 主页面底栏动画
  mainPageBottomBarAnimationEnabled: boolean; // 主页面底栏动画开关（关闭后底栏常驻）
}

export const DEFAULT_ANIMATION_SETTINGS: AnimationSettings = {
  bookOpenEnabled: true,
  bookCloseEnabled: true,
  bookOpenDuration: 400,
  bookCloseDuration: 350,
  mainPageBottomBarAnimationEnabled: false // 默认关闭底栏动画
}

export type AnimationSettingsListener = (settings: AnimationSettings) => void;

