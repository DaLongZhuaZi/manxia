import { common } from '@kit.AbilityKit';
import { logger } from '../Utils/Logger';
import { distributedDataSyncManager, SyncReadingState } from '../Framework/Distributed/DistributedDataSyncManager';
import { ContinuationTriggeredPayload } from '../Framework/EventBus';
import { REMOTE_CONTROL_ABILITY_INSTANCE_ID_KEY } from '../Framework/RemoteControl/RemoteControlAbilityConstants';

const TAG = 'RemoteControlPage';

@Component
export struct RemoteControlPage {
  @Consume('NavPathStack') pageStack: NavPathStack;
  @LocalStorageProp(REMOTE_CONTROL_ABILITY_INSTANCE_ID_KEY) private remoteControlAbilityInstanceId: string = '';
  
  @State private sessionId: string = '';
  @State private bookId: string = '';
  @State private chapterIndex: number = 0;
  @State private pageIndex: number = 0;
  @State private readingOffset: number = 0;
  @State private isLocal: boolean = false;
  @State private sourceType: string = '';
  @State private connectionStatus: 'connecting' | 'online' | 'offline' | 'error' = 'connecting';
  @State private errorMessage: string = '';
  private callbacksRegistered: boolean = false;

  private onRemoteDataChanged = (state: SyncReadingState) => {
    if (state.sessionId !== this.sessionId) {
      return;
    }
    // [修复] 目标端回执：当前书籍格式不支持自动朗读（仅 TXT 文本阅读器支持）
    if (state.instructionType === 'ack_toggle_auto_read_unsupported') {
      const formatText = state.instructionPayload.length > 0 ? state.instructionPayload : '当前格式';
      this.getUIContext().getPromptAction().showToast({ message: `目标书籍不支持自动朗读（${formatText}，仅支持TXT）` });
      return;
    }
    if (state.instructionType !== 'cmd:next_page'
      && state.instructionType !== 'cmd:prev_page'
      && state.instructionType !== 'cmd:next_chapter'
      && state.instructionType !== 'cmd:prev_chapter'
      && state.instructionType !== 'cmd:toggle_auto_read') {
      // 只更新进度字段，忽略我们自己发出的指令回声
      this.chapterIndex = state.chapterIndex;
      this.pageIndex = state.pageIndex;
      this.readingOffset = state.offset;
    }
  };

  private onRemoteStatusChanged = (status: 'online' | 'offline' | 'restored' | 'error', message?: string) => {
    // [修复] 仅在状态真正变化时提示/更新，避免 DataObject 与独立连接通道先后播报 online 造成重复 toast
    const effectiveStatus: 'online' | 'offline' | 'error' = status === 'restored' ? 'online' : status;
    const changed = this.connectionStatus !== effectiveStatus;
    this.connectionStatus = effectiveStatus;
    
    if (status === 'error' && message) {
      this.errorMessage = message;
      if (changed) {
        this.getUIContext().getPromptAction().showToast({ message: `连接异常: ${message}` });
      }
    } else if (status === 'offline') {
      if (changed) {
        this.getUIContext().getPromptAction().showToast({ message: '目标设备已离线' });
      }
    } else if (status === 'online') {
      if (changed) {
        this.getUIContext().getPromptAction().showToast({ message: '已连接目标设备' });
      }
    }
  };
  
  aboutToAppear() {
    logger.info(TAG, 'RemoteControlPage aboutToAppear');
  }

  aboutToDisappear() {
    logger.info(TAG, 'RemoteControlPage aboutToDisappear');
    // 断开遥控器连接，但不需要终止分布式会话（因为目标端可能还要继续阅读）
    this.detachRemoteCallbacks();
  }

  private onReady(context: NavDestinationContext) {
    const params = context.pathInfo.param as ContinuationTriggeredPayload;
    if (params) {
      this.detachRemoteCallbacks();
      this.sessionId = params.sessionId;
      this.bookId = params.bookId;
      this.chapterIndex = params.chapterIndex;
      this.pageIndex = params.pageIndex;
      this.readingOffset = params.offset;
      this.isLocal = params.isLocal;
      this.sourceType = params.sourceType;
      logger.info(TAG, `遥控页就绪: sessionId=${this.sessionId}, bookId=${this.bookId}, chapter=${this.chapterIndex}, page=${this.pageIndex}, offset=${this.readingOffset}, sourceType=${this.sourceType}`);

      // 遥控端（主设备）已持有分布式会话对象，无需重新 joinSession，
      // 只需重新挂载进度回调，接收被控端回传的最新状态。
      const latestState = distributedDataSyncManager.getCurrentState();
      if (latestState && latestState.sessionId === this.sessionId) {
        this.chapterIndex = latestState.chapterIndex;
        this.pageIndex = latestState.pageIndex;
        this.readingOffset = latestState.offset;
        logger.info(TAG, `遥控页已同步分布式会话最新状态: chapter=${this.chapterIndex}, page=${this.pageIndex}, offset=${this.readingOffset}`);
      } else {
        logger.warn(TAG, `遥控页未匹配到当前分布式会话状态（session 可能未建立或已失效）: currentSession=${latestState ? latestState.sessionId : '(none)'}`);
      }

      this.attachRemoteCallbacks();
      // [修复] 写入页面就绪 token：源端 ContinuationStateHelper 据此区分
      // "遥控器 Ability 已创建"与"遥控器页面真正渲染"——
      // 接续握手期间发起的 0ms 启动可能只创建 Ability 而窗口被吞掉（僵尸实例），
      // 只有页面就绪才算拉起成功。
      AppStorage.setOrCreate('remoteControlPageReadyToken', Date.now());
      // [诊断] 输出本端会话状态（会话对象、状态事件流水），用于判断 DataObject 会话是否跨设备建立
      distributedDataSyncManager.diagnoseSession('遥控端就绪');
    }
  }

  private attachRemoteCallbacks(): void {
    if (this.callbacksRegistered) {
      return;
    }
    distributedDataSyncManager.addOnDataChangedCallback(this.onRemoteDataChanged);
    distributedDataSyncManager.addOnStatusChangedCallback(this.onRemoteStatusChanged);
    this.callbacksRegistered = true;
  }

  private detachRemoteCallbacks(): void {
    if (!this.callbacksRegistered) {
      return;
    }
    distributedDataSyncManager.removeOnDataChangedCallback(this.onRemoteDataChanged);
    distributedDataSyncManager.removeOnStatusChangedCallback(this.onRemoteStatusChanged);
    this.callbacksRegistered = false;
  }

  private isHostedByIsolatedAbility(): boolean {
    return this.remoteControlAbilityInstanceId.length > 0;
  }

  private async closeRemoteControl(leaveSession: boolean, reason: string): Promise<void> {
    if (leaveSession) {
      distributedDataSyncManager.leaveSession();
    }
    this.detachRemoteCallbacks();

    if (this.isHostedByIsolatedAbility()) {
      try {
        const hostContext = this.getUIContext()?.getHostContext() as common.UIAbilityContext;
        if (!hostContext) {
          logger.warn(TAG, `独立遥控器关闭失败，回退页面栈: reason=${reason}`);
          this.pageStack.pop();
          return;
        }
        logger.info(TAG, `独立遥控器关闭: reason=${reason}, instanceId=${this.remoteControlAbilityInstanceId}`);
        await hostContext.terminateSelf();
        return;
      } catch (error) {
        logger.warn(TAG, `独立遥控器关闭异常，回退页面栈: reason=${reason}, error=${String(error)}`);
      }
    }

    this.pageStack.pop();
  }

  private sendCommand(cmd: string) {
    if (this.connectionStatus === 'error' || this.connectionStatus === 'offline') {
      this.getUIContext().getPromptAction().showToast({ message: '发送失败：连接已断开' });
      return;
    }
    distributedDataSyncManager.sendInstruction(cmd, '');
  }

  build() {
    NavDestination() {
      Column() {
        // 顶部导航与状态栏
        Row() {
          Button({ type: ButtonType.Circle, stateEffect: true }) {
            SymbolGlyph($r('sys.symbol.chevron_left'))
              .fontSize(24)
              .fontColor([$r('sys.color.font_primary')])
          }
          .backgroundColor(Color.Transparent)
          .width(48)
          .height(48)
          .onClick(() => {
            void this.closeRemoteControl(false, 'back');
          })

          Text('遥控器模式')
            .fontSize(20)
            .fontWeight(FontWeight.Bold)
            .fontColor($r('sys.color.font_primary'))
            .layoutWeight(1)
            .textAlign(TextAlign.Center)

          Button({ type: ButtonType.Circle, stateEffect: true }) {
            SymbolGlyph($r('sys.symbol.xmark'))
              .fontSize(24)
              .fontColor([$r('sys.color.font_primary')])
          }
          .backgroundColor(Color.Transparent)
          .width(48)
          .height(48)
          .onClick(() => {
            void this.closeRemoteControl(true, 'leave_session');
          })
        }
        .width('100%')
        .padding({ top: 12, left: 16, right: 16, bottom: 12 })
        .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.TOP])

        // 状态展示区
        Column({ space: 16 }) {
          SymbolGlyph(this.connectionStatus === 'online' ? $r('sys.symbol.computer_share_fill') : $r('sys.symbol.xmark_circle_fill'))
            .fontSize(64)
            .fontColor([this.connectionStatus === 'online' ? $r('sys.color.brand') : $r('sys.color.font_tertiary')])
            
          Text(this.connectionStatus === 'connecting' ? '正在连接目标设备...' : 
               this.connectionStatus === 'online' ? '已连接至目标设备' : 
               this.connectionStatus === 'offline' ? '目标设备已离线' : '连接发生错误')
            .fontSize(16)
            .fontColor(this.connectionStatus === 'error' ? $r('app.color.color_error') : $r('sys.color.font_secondary'))

          Text(`书籍 ID: ${this.bookId}`)
            .fontSize(14)
            .fontColor($r('sys.color.font_tertiary'))
            .maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis })

          Row({ space: 24 }) {
            Column({ space: 8 }) {
              Text('当前章节')
                .fontSize(14)
                .fontColor($r('sys.color.font_tertiary'))
              Text(`${this.chapterIndex + 1}`)
                .fontSize(28)
                .fontWeight(FontWeight.Medium)
                .fontColor($r('sys.color.font_primary'))
            }.alignItems(HorizontalAlign.Center)

            Divider().vertical(true).height(40).color($r('sys.color.comp_divider'))

            Column({ space: 8 }) {
              Text('当前页码/偏移')
                .fontSize(14)
                .fontColor($r('sys.color.font_tertiary'))
              Text(this.sourceType === 'novel' ? `${this.readingOffset}` : `${this.pageIndex + 1}`)
                .fontSize(28)
                .fontWeight(FontWeight.Medium)
                .fontColor($r('sys.color.font_primary'))
            }.alignItems(HorizontalAlign.Center)
          }
          .padding(24)
          .backgroundColor($r('sys.color.comp_background_tertiary'))
          .borderRadius(16)
          .margin({ top: 24 })
        }
        .layoutWeight(1)
        .justifyContent(FlexAlign.Center)
        .width('100%')

        // 控制区
        Column({ space: 24 }) {
          Row({ space: 24 }) {
            // 上一章
            Button({ type: ButtonType.Circle, stateEffect: true }) {
              SymbolGlyph($r('sys.symbol.arrow_left'))
                .fontSize(28)
                .fontColor([$r('sys.color.font_primary')])
            }
            .backgroundColor($r('sys.color.comp_background_secondary'))
            .width(64)
            .height(64)
            .onClick(() => this.sendCommand('cmd:prev_chapter'))

            // 自动阅读/播放
            Button({ type: ButtonType.Circle, stateEffect: true }) {
              SymbolGlyph($r('sys.symbol.play'))
                .fontSize(32)
                .fontColor([Color.White])
            }
            .backgroundColor($r('sys.color.brand'))
            .width(80)
            .height(80)
            .onClick(() => this.sendCommand('cmd:toggle_auto_read'))

            // 下一章
            Button({ type: ButtonType.Circle, stateEffect: true }) {
              SymbolGlyph($r('sys.symbol.arrow_right'))
                .fontSize(28)
                .fontColor([$r('sys.color.font_primary')])
            }
            .backgroundColor($r('sys.color.comp_background_secondary'))
            .width(64)
            .height(64)
            .onClick(() => this.sendCommand('cmd:next_chapter'))
          }
          .justifyContent(FlexAlign.Center)
          .width('100%')

          Row({ space: 16 }) {
            // 上一页
            Button({ type: ButtonType.Capsule, stateEffect: true }) {
              Row({ space: 8 }) {
                SymbolGlyph($r('sys.symbol.chevron_left'))
                  .fontSize(20)
                  .fontColor([$r('sys.color.font_primary')])
                Text('上一页')
                  .fontSize(16)
                  .fontColor($r('sys.color.font_primary'))
              }
            }
            .backgroundColor($r('sys.color.comp_background_secondary'))
            .layoutWeight(1)
            .height(56)
            .onClick(() => this.sendCommand('cmd:prev_page'))

            // 下一页
            Button({ type: ButtonType.Capsule, stateEffect: true }) {
              Row({ space: 8 }) {
                Text('下一页')
                  .fontSize(16)
                  .fontColor($r('sys.color.font_primary'))
                SymbolGlyph($r('sys.symbol.chevron_right'))
                  .fontSize(20)
                  .fontColor([$r('sys.color.font_primary')])
              }
            }
            .backgroundColor($r('sys.color.comp_background_secondary'))
            .layoutWeight(1)
            .height(56)
            .onClick(() => this.sendCommand('cmd:next_page'))
          }
          .width('100%')
          .padding({ left: 24, right: 24 })
        }
        .padding({ bottom: 48 })
        .width('100%')
      }
      .width('100%')
      .height('100%')
      .backgroundColor($r('sys.color.background_primary'))
    }
    .hideTitleBar(true)
    .onReady((context: NavDestinationContext) => {
      this.onReady(context);
    })
  }
}

@Builder
export function RemoteControlPageBuilder() {
  RemoteControlPage()
}
