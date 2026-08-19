import { logger } from 'manxia_core/src/main/ets/Utils/Logger';

const TAG: string = 'ContinuationRestorePage';

/**
 * 跨端接续恢复中转页：
 * 目标端由阅读器/听书 Ability 接续启动时，本页作为过渡界面展示"正在恢复阅读"，
 * 同时 ContinuationStateHelper 将接续导航转交 EntryAbility；
 * EntryAbility 前台接管确认后，接续启动的 Ability 会被终止，本页随之销毁。
 */
@Entry
@Component
struct ContinuationRestorePage {
  aboutToAppear(): void {
    logger.info(TAG, '接续恢复中转页已显示：等待转交入口 Ability 处理接续导航');
  }

  aboutToDisappear(): void {
    logger.info(TAG, '接续恢复中转页已销毁');
  }

  build() {
    Column({ space: 16 }) {
      LoadingProgress()
        .width(48)
        .height(48)
        .color(Color.White)

      Text('正在恢复阅读位置…')
        .fontSize(17)
        .fontColor(Color.White)

      Text('内容已从其他设备接续到本机')
        .fontSize(13)
        .fontColor(Color.White)
        .opacity(0.65)
    }
    .width('100%')
    .height('100%')
    .justifyContent(FlexAlign.Center)
    .backgroundColor(Color.Black)
    .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.TOP, SafeAreaEdge.BOTTOM])
    .ignoreLayoutSafeArea([LayoutSafeAreaType.SYSTEM], [LayoutSafeAreaEdge.TOP, LayoutSafeAreaEdge.BOTTOM])
  }
}
