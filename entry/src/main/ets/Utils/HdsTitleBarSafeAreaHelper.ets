import { HdsNavigationTitleBarOptions } from '@kit.UIDesignKit';

export function withSafeAreaTitleBar(
  options?: HdsNavigationTitleBarOptions
): HdsNavigationTitleBarOptions {
  const source: HdsNavigationTitleBarOptions = options ?? {};
  return {
    padding: source.padding,
    style: source.style,
    content: source.content,
    enableHoverMode: source.enableHoverMode,
    avoidLayoutSafeArea: true,
    enableComponentSafeArea: true
  };
}
