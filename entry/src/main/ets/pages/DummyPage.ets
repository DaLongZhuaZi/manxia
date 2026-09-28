/**
 * 组件展示页面 - 使用HdsNavDestination导航模式，支持主题切换
 * 展示各种官方HDS组件的效果和用法
 */
import { HdsNavDestination, HdsNavDestinationAttribute, ScrollEffectType } from '@kit.UIDesignKit';
import { LengthMetrics } from '@kit.ArkUI';
import { ThemeManager, ThemeType } from 'manxia_theme/src/main/ets/Framework/Managers/ThemeManager';
import { ThemeToggle } from 'manxia_theme/src/main/ets/Framework/Components/ThemeToggle';
import { ThemeAwareState, ThemeAwareHelper } from 'manxia_theme/src/main/ets/Framework/Components/ThemeAware';
import { logger } from 'manxia_core/src/main/ets/Utils/Logger';

// 定义标题栏最小高度，用于内容占位
const TITLE_BAR_HEIGHT_MINI: number = 56;
const TAG = 'DummyPage';

// 定义NavDestinationContext接口
interface NavDestinationContext {
  pathStack: NavPathStack;
}

@Component
struct DummyPage {
  private scroller: Scroller = new Scroller();
  @State pathStack: NavPathStack = new NavPathStack();

  // 主题相关状态
  @State themeState: ThemeAwareState = new ThemeAwareState();
  private themeManager: ThemeManager = ThemeManager.getInstance();
  private componentId: string = 'DummyPage';

  // 组件状态
  @State private sliderValue: number = 30;
  @State private stepValue: number = 4;
  @State private isSwitchOn: boolean = true;
  @State private selectedRadio: string = 'B';
  @State private textValue: string = 'HDS Component';
  @State private progressValue: number = 0;
  @State private selectedTabs: number = 0;

  onPageShow() {
    try {
      const stack = AppStorage.get<NavPathStack>('GlobalNavStack');
      if (stack) {
        this.pathStack = stack;
      } else {
        logger.error(TAG, '无法从 AppStorage 获取 GlobalNavStack!');
      }
    } catch (err) {
      logger.error(TAG, 'AppStorage.get 异常', err);
    }
    
    logger.lifecycle(TAG, '组件展示页面即将显示');
  }

  onReady() {
    // 初始化主题感知
    ThemeAwareHelper.initializeThemeAware(
      this.componentId,
      this.themeState,
      (newTheme: ThemeType) => {
        // 主题变化回调
        logger.info('DummyPage', `主题已切换到: ${newTheme}`);
      }
    );
  }

  aboutToDisappear() {
    // 清理主题感知
    ThemeAwareHelper.cleanupThemeAware(this.componentId);
    logger.lifecycle(TAG, '组件展示页面即将消失');
  }

  private goBack(): void {
    try {
      this.pathStack.pop();
    } catch (error) {
      logger.error('DummyPage', '返回失败', String(error));
    }
  }

  @Builder
  buildBasicComponents() {
    Column({ space: 12 }) {
      Text('基础组件')
        .fontSize(18)
        .fontWeight(FontWeight.Medium)
        .fontColor(ThemeAwareHelper.getTestManagementThemedColor('button_text_primary', this.themeState.currentTheme))
        .alignSelf(ItemAlign.Start)
        .margin({ bottom: 8 })

      Column({ space: 16 }) {
        Button('HDS 主要按钮').width('100%').onClick(() => {
          this.getUIContext().getPromptAction().showToast({ message: '主要按钮被点击' })
        })
        .backgroundColor(ThemeAwareHelper.getTestManagementThemedColor('accent_green', this.themeState.currentTheme))
        .fontColor(ThemeAwareHelper.getTestManagementThemedColor('button_text_primary', this.themeState.currentTheme))
        
        Button('HDS 次要按钮', { type: ButtonType.Normal }).width('100%')
          .backgroundColor(ThemeAwareHelper.getTestManagementThemedColor('button_secondary', this.themeState.currentTheme))
          .fontColor(ThemeAwareHelper.getTestManagementThemedColor('button_text_primary', this.themeState.currentTheme))
          .onClick(() => {
            console.log('HDS 次要按钮点击')
          })

        Row({ space: 10 }) {
          Text('开关:')
            .fontColor(ThemeAwareHelper.getTestManagementThemedColor('button_text_primary', this.themeState.currentTheme))
          Toggle({ type: ToggleType.Switch, isOn: this.isSwitchOn })
            .onChange(isOn => this.isSwitchOn = isOn)
        }

        Row({ space: 10 }) {
          Text('单选:')
            .fontColor(ThemeAwareHelper.getTestManagementThemedColor('button_text_primary', this.themeState.currentTheme))
          Row({ space: 10 }) {
            Radio({ value: 'A', group: 'radioGroup' })
              .checked(this.selectedRadio === 'A')
              .onChange(isChecked => { if(isChecked) this.selectedRadio = 'A' })
            Text('选项A')
              .fontColor(ThemeAwareHelper.getTestManagementThemedColor('button_text_primary', this.themeState.currentTheme))
            Radio({ value: 'B', group: 'radioGroup' })
              .checked(this.selectedRadio === 'B')
              .onChange(isChecked => { if(isChecked) this.selectedRadio = 'B' })
            Text('选项B')
              .fontColor(ThemeAwareHelper.getTestManagementThemedColor('button_text_primary', this.themeState.currentTheme))
          }
        }
      }.width('100%').alignItems(HorizontalAlign.Start)
    }
    .width('100%')
    .padding(20)
    .backgroundColor(ThemeAwareHelper.getTestManagementThemedColor('panel_background', this.themeState.currentTheme))
    .borderRadius(16)
    .border({ width: 1, color: ThemeAwareHelper.getTestManagementThemedColor('panel_border', this.themeState.currentTheme) })
  }

  @Builder
  buildInputComponents() {
    Column({ space: 12 }) {
      Text('输入与选择')
        .fontSize(18)
        .fontWeight(FontWeight.Medium)
        .fontColor(ThemeAwareHelper.getTestManagementThemedColor('button_text_primary', this.themeState.currentTheme))
        .alignSelf(ItemAlign.Start)
        .margin({ bottom: 8 })

      Column({ space: 16 }) {
        TextInput({ placeholder: '请输入...', text: this.textValue })
          .onChange(val => this.textValue = val)
          .backgroundColor(ThemeAwareHelper.getTestManagementThemedColor('button_inactive', this.themeState.currentTheme))
          .fontColor(ThemeAwareHelper.getTestManagementThemedColor('button_text_primary', this.themeState.currentTheme))
          .placeholderColor(ThemeAwareHelper.getTestManagementThemedColor('text_muted', this.themeState.currentTheme))
          
        Text(`滑块值: ${this.sliderValue.toFixed(0)}`)
          .fontColor(ThemeAwareHelper.getTestManagementThemedColor('button_text_primary', this.themeState.currentTheme))
        Slider({ value: this.sliderValue, min: 0, max: 100 })
          .onChange(val => this.sliderValue = val)
          .trackColor(ThemeAwareHelper.getTestManagementThemedColor('button_inactive', this.themeState.currentTheme))
          .selectedColor(ThemeAwareHelper.getTestManagementThemedColor('accent_green', this.themeState.currentTheme))
          
        Text(`步进器值: ${this.stepValue}`)
          .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_white', this.themeState.currentTheme))
        Row({ space: 10 }) {
          Button('-')
            .width(40)
            .height(40)
            .backgroundColor(ThemeAwareHelper.getTestManagementThemedColor('button_inactive', this.themeState.currentTheme))
            .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_white', this.themeState.currentTheme))
            .onClick(() => {
              if (this.stepValue > 0) {
                this.stepValue--;
              }
            })
          Text(`${this.stepValue}`)
            .fontSize(16)
            .width(40)
            .textAlign(TextAlign.Center)
            .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_white', this.themeState.currentTheme))
          Button('+')
            .width(40)
            .height(40)
            .backgroundColor(ThemeAwareHelper.getTestManagementThemedColor('accent_green', this.themeState.currentTheme))
            .fontColor(ThemeAwareHelper.getTestManagementThemedColor('button_text_primary', this.themeState.currentTheme))
            .onClick(() => {
              this.stepValue++;
            })
        }

        Tabs() {
          TabContent() { 
            Text('内容一')
              .padding(20)
              .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_white', this.themeState.currentTheme))
          }
          TabContent() { 
            Text('内容二')
              .padding(20)
              .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_white', this.themeState.currentTheme))
          }
          TabContent() { 
            Text('内容三')
              .padding(20)
              .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_white', this.themeState.currentTheme))
          }
        }
        .barMode(BarMode.Fixed)
        .onChange(index => this.selectedTabs = index)

      }.width('100%').alignItems(HorizontalAlign.Start)
    }
    .width('100%')
    .padding(20)
    .backgroundColor(ThemeAwareHelper.getTestManagementThemedColor('panel_background', this.themeState.currentTheme))
    .borderRadius(16)
    .border({ width: 1, color: ThemeAwareHelper.getTestManagementThemedColor('panel_border', this.themeState.currentTheme) })
  }

  @Builder
  buildProgressComponents() {
    Column({ space: 12 }) {
      Text('进度展示')
        .fontSize(18)
        .fontWeight(FontWeight.Medium)
        .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_primary', this.themeState.currentTheme))
        .alignSelf(ItemAlign.Start)
        .margin({ bottom: 8 })

      Column({ space: 16 }) {
        Text('加载进度')
        Progress({ value: this.progressValue, type: ProgressType.Linear })
        Text('环形进度')
        Progress({ value: this.progressValue, type: ProgressType.Ring })
        LoadingProgress().color(ThemeAwareHelper.getTestManagementThemedColor('brand', this.themeState.currentTheme))
      }.width('100%').alignItems(HorizontalAlign.Start)
    }
    .width('100%')
    .padding(20)
    .backgroundColor(ThemeAwareHelper.getTestManagementThemedColor('background_secondary', this.themeState.currentTheme))
    .borderRadius(16)
  }

  build() {
    // [核心] 使用 HdsNavDestination 作为根组件
    HdsNavDestination() {
      // [核心] 使用 Stack 分离背景和内容
      Stack() {
        // 背景层
        Column()
          .width('100%')
          .height('100%')
          .backgroundColor(ThemeAwareHelper.getTestManagementThemedColor('background_primary', this.themeState.currentTheme))
          .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.TOP, SafeAreaEdge.BOTTOM])
        
        // 内容层
        Scroll(this.scroller) {
          Column({ space: 24 }) {
            // [核心] 添加 Blank 占位符
            Blank().height(TITLE_BAR_HEIGHT_MINI)

            // 基础组件
            this.buildBasicComponents()

            // 输入与选择
            this.buildInputComponents()

            // 进度展示
            this.buildProgressComponents()

          }
          .width('100%')
          .padding({ left: 20, right: 20, bottom: 40 })
        }
        .edgeEffect(EdgeEffect.Spring)
        .scrollBar(BarState.Auto)
        .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.TOP, SafeAreaEdge.BOTTOM])
      }
    }
    // [核心] 配置 titleBar，实现滚动模糊效果
    .titleBar({
      padding: {
        start: LengthMetrics.vp(16),
        end: LengthMetrics.vp(16)
      },
      style: {
        originalStyle: {
          backgroundStyle: { backgroundColor: ThemeAwareHelper.getTestManagementThemedColor('panel_background', this.themeState.currentTheme) },
          contentStyle: {
            titleStyle: { mainTitleColor: ThemeAwareHelper.getTestManagementThemedColor('text_primary', this.themeState.currentTheme) },
            backIconStyle: { backgroundColor: ThemeAwareHelper.getTestManagementThemedColor('comp_background_tertiary', this.themeState.currentTheme), iconColor: ThemeAwareHelper.getTestManagementThemedColor('icon_primary', this.themeState.currentTheme) }
          }
        }
      },
      content: {
        title: {
          mainTitle: "🎨 组件展示页面",
        },
        menu: {
          value: [{
            content: {
              label: '重置',
              icon: $r('app.media.SculptureLargeAnimalistA'), // 应该为刷新图标
              isEnabled: true,
              action: () => {
                this.progressValue = 0;
                this.getUIContext().getPromptAction().showToast({ message: '进度已重置' });
              }
            }
          }]
        }
      }
    })
    .onReady((context: NavDestinationContext) => {
      // [核心] 从上下文获取正确的 pathStack 实例
      this.pathStack = context.pathStack;
      this.onPageShow();
    })
    // [核心] HdsNavDestination 自身背景设为透明
    .backgroundColor(Color.Transparent)
  }
}

export { DummyPage }