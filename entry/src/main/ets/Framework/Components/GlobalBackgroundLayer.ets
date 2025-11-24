/**
 * 全局背景层组件
 * 用于显示自定义主题的背景图片
 * 所有页面都应该使用此组件作为背景层
 */
import { logger } from '../../Utils/Logger';
import { CUSTOM_THEME_KEYS } from '../Managers/ThemeManager';
import fs from '@ohos.file.fs';
import { deviceInfo } from '@kit.BasicServicesKit';

const TAG = 'GlobalBackgroundLayer';

@Component
export struct GlobalBackgroundLayer {
  // 监听全局背景图片路径
  @StorageProp(CUSTOM_THEME_KEYS.BACKGROUND_IMAGE) backgroundImagePath: string = '';
  @StorageProp(CUSTOM_THEME_KEYS.IS_CUSTOM_THEME_ACTIVE) isCustomThemeActive: boolean = false;
  @StorageProp(CUSTOM_THEME_KEYS.CURRENT_THEME_ID) currentCustomThemeId: string = '';
  
  // 默认背景色（当没有自定义主题时）
  @Prop defaultBackgroundColor: ResourceStr = $r('app.color.background');

  build() {
    Stack() {
      if (this.isCustomThemeActive && this.backgroundImagePath) {
        // 显示自定义背景图片
        Image('file://' + this.backgroundImagePath)
          .width('100%')
          .height('100%')
          .objectFit(ImageFit.Cover)
          .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.TOP, SafeAreaEdge.BOTTOM])
          .onError((error: ImageError) => {
            logger.error(TAG, `背景图片加载失败: ${JSON.stringify(error)}`);
          })
      } else if (this.isCustomThemeActive) {
        // 路径为空时，使用媒体资源回退（a_* / b_* 按设备类型）
        Image(this.getFallbackMediaResource())
          .width('100%')
          .height('100%')
          .objectFit(ImageFit.Cover)
          .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.TOP, SafeAreaEdge.BOTTOM])
      } else {
        // 显示默认背景色
        Column()
          .width('100%')
          .height('100%')
          .backgroundColor(this.defaultBackgroundColor)
          .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.TOP, SafeAreaEdge.BOTTOM])
      }
    }
    .width('100%')
    .height('100%')
  }

  // 根据设备类型与当前主题ID选择媒体资源
  private getFallbackMediaResource(): ResourceStr {
    const setId: string = (this.currentCustomThemeId === 'secondary_custom_theme') ? 'b' : 'a';
    const devType: string = String(deviceInfo.deviceType);
    if (setId === 'a') {
      if (devType === 'foldable') { return $r('app.media.a_1'); }
      if (devType === 'phone') { return $r('app.media.a_2'); }
      // tablet 或 2in1 或其他
      return $r('app.media.a_3');
    } else {
      if (devType === 'foldable') { return $r('app.media.b_1'); }
      if (devType === 'phone') { return $r('app.media.b_2'); }
      return $r('app.media.b_3');
    }
  }
}

