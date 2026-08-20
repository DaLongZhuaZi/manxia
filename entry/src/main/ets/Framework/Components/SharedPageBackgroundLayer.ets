import { SettingKeys } from 'manxia_core/src/main/ets/Framework/Managers/SettingsManager';
import { GlobalBackgroundLayer, GlobalBackgroundLayerMode } from 'manxia_theme/src/main/ets/Framework/Components/GlobalBackgroundLayer';

@Component
export struct SharedPageBackgroundLayer {
  @StorageProp(SettingKeys.NON_MAIN_PAGE_GLOBAL_BACKGROUND_ENABLED)
  nonMainPageGlobalBackgroundEnabled: boolean = true;

  @Prop defaultBackgroundColor: ResourceStr = $r('app.color.background');
  @Prop mode: GlobalBackgroundLayerMode = GlobalBackgroundLayerMode.DEFAULT;
  @Prop enableScrimLayer: boolean = true;
  @Prop enableAtmosphereLayer: boolean = true;
  @Prop renderFallbackLayer: boolean = true;

  build() {
    if (this.nonMainPageGlobalBackgroundEnabled) {
      GlobalBackgroundLayer({
        defaultBackgroundColor: this.defaultBackgroundColor,
        mode: this.mode,
        enableScrimLayer: this.enableScrimLayer,
        enableAtmosphereLayer: this.enableAtmosphereLayer
      })
    } else if (this.renderFallbackLayer) {
      Column()
        .width('100%')
        .height('100%')
        .backgroundColor(this.defaultBackgroundColor)
        .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.TOP, SafeAreaEdge.BOTTOM])
    } else {
      Column()
        .width('0vp')
        .height('0vp')
        .opacity(0)
    }
  }
}
