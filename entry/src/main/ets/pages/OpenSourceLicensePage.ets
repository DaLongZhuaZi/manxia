// 文件路径: entry/src/main/ets/pages/OpenSourceLicensePage.ets
// 职责: 开源许可页面，展示本项目使用的开源组件及其许可证信息
// 最后编辑: 2025-11-29

import { HdsNavDestination, HdsNavDestinationAttribute, ScrollEffectType } from '@kit.UIDesignKit';
import { ThemeAwareState, ThemeAwareHelper } from '../Framework/Components/ThemeAware';
import { ThemeManager, ThemeType } from '../Framework/Managers/ThemeManager';
import { logger } from '../Utils/Logger';
import { PageLifecycleManager } from '../Framework/Lifecycle';
import { DisplayMode } from '../Utils/WindowManager';
import { PageWindowCoordinator } from '../Utils/PageWindowCoordinator';
import { withSafeAreaTitleBar } from '../Utils/HdsTitleBarSafeAreaHelper';

const TAG = 'OpenSourceLicensePage';
/**
 * 开源许可页面
 * 展示本项目使用的开源组件及其许可证信息
 */
@Component
export struct OpenSourceLicensePage {
  @Consume('NavPathStack') pathStack: NavPathStack;
  @StorageProp('statusBarHeight') statusBarHeight: number = 0;
  @StorageProp('navigationBarHeight') navigationBarHeight: number = 0;

  // 主题状态
  @State themeState: ThemeAwareState = new ThemeAwareState();
  private themeManager: ThemeManager = ThemeManager.getInstance();
  private componentId: string = `OpenSourceLicensePage_${Date.now()}`;
  private previousDisplayMode: DisplayMode = DisplayMode.DEFAULT;

  // 滚动控制器
  private scroller: Scroller = new Scroller();

  aboutToAppear(): void {
    logger.lifecycle(TAG, 'aboutToAppear');
    this.previousDisplayMode = PageWindowCoordinator.captureCurrentDisplayMode();
    PageWindowCoordinator.applyPagePolicy('OpenSourceLicensePage', this.getUIContext());

    // 初始化主题状态
    ThemeAwareHelper.initializeThemeAware(
      this.componentId,
      this.themeState,
      (newTheme: ThemeType) => {
        logger.info(TAG, `主题已切换到: ${newTheme}`);
      },
      (newState: ThemeAwareState) => {
        this.themeState = newState;
      }
    );
  }

  private lifecycle = new PageLifecycleManager('OpenSourceLicensePage', { enableDebug: true });

  aboutToDisappear(): void {
    logger.lifecycle(TAG, 'aboutToDisappear');
    PageWindowCoordinator.restoreDisplayMode(this.previousDisplayMode, this.getUIContext());
    this.lifecycle.destroy();
    ThemeAwareHelper.cleanupThemeAware(this.componentId);
  }

  /**
   * 返回上一页
   */
  private goBack(): void {
    try {
      this.pathStack.pop();
      logger.info(TAG, '返回上一页');
    } catch (error) {
      logger.error(TAG, `返回失败: ${String(error)}`);
    }
  }

  /**
   * 构建章节标题
   */
  @Builder
  buildSectionTitle(title: string, icon: Resource) {
    Row({ space: 8 }) {
      SymbolGlyph(icon)
        .fontSize(24)
        .fontColor([ThemeAwareHelper.getTestManagementThemedColor('accent_primary', this.themeState.currentTheme)])

      Text(title)
        .fontSize(20)
        .fontWeight(FontWeight.Bold)
        .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_primary', this.themeState.currentTheme))
    }
    .width('100%')
    .margin({ top: 24, bottom: 12 })
  }

  /**
   * 构建子标题
   */
  @Builder
  buildSubTitle(title: string) {
    Text(title)
      .fontSize(18)
      .fontWeight(FontWeight.Medium)
      .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_primary', this.themeState.currentTheme))
      .width('100%')
      .margin({ top: 16, bottom: 8 })
  }

  /**
   * 构建段落文本
   */
  @Builder
  buildParagraph(text: string) {
    Text(text)
      .fontSize(15)
      .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_secondary', this.themeState.currentTheme))
      .lineHeight(24)
      .width('100%')
      .margin({ bottom: 12 })
  }

  /**
   * 构建开源库项
   */
  @Builder
  buildLibraryItem(name: string, version: string, license: string, description: string) {
    Column({ space: 8 }) {
      Row() {
        Text(name)
          .fontSize(16)
          .fontWeight(FontWeight.Medium)
          .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_primary', this.themeState.currentTheme))
          .layoutWeight(1)

        Text(version)
          .fontSize(14)
          .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_muted', this.themeState.currentTheme))
      }
      .width('100%')

      Text(description)
        .fontSize(14)
        .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_secondary', this.themeState.currentTheme))
        .width('100%')

      Row() {
        Text('许可证: ')
          .fontSize(13)
          .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_muted', this.themeState.currentTheme))

        Text(license)
          .fontSize(13)
          .fontColor(ThemeAwareHelper.getTestManagementThemedColor('accent_blue', this.themeState.currentTheme))
      }
      .width('100%')
    }
    .width('100%')
    .padding(16)
    .backgroundColor(ThemeAwareHelper.getTestManagementThemedColor('comp_background_secondary', this.themeState.currentTheme))
    .borderRadius(8)
    .margin({ bottom: 12 })
  }

  /**
   * 构建提示框
   */
  @Builder
  buildTipBox(title: string, content: string, type: 'info' | 'warning' | 'success' = 'info') {
    Column({ space: 8 }) {
      Row({ space: 8 }) {
        SymbolGlyph(type === 'info' ? $r('sys.symbol.lightbulb') : 
                   type === 'warning' ? $r('sys.symbol.exclamationmark_triangle') : 
                   $r('sys.symbol.checkmark_circle'))
          .fontSize(18)
          .fontColor([type === 'info' ? Color.White : 
                     type === 'warning' ? '#F57C00' : '#4CAF50'])

        Text(title)
          .fontSize(16)
          .fontWeight(FontWeight.Medium)
          .fontColor(type === 'info' ? Color.White : ThemeAwareHelper.getTestManagementThemedColor('text_primary', this.themeState.currentTheme))
      }
      .width('100%')

      Text(content)
        .fontSize(14)
        .fontColor(type === 'info' ? '#FFFFFFCC' : ThemeAwareHelper.getTestManagementThemedColor('text_secondary', this.themeState.currentTheme))
        .lineHeight(20)
        .width('100%')
    }
    .width('100%')
    .padding(12)
    .backgroundColor(type === 'info'
      ? ThemeAwareHelper.getTestManagementThemedColor('accent_primary', this.themeState.currentTheme)
      : type === 'warning'
        ? '#FFF3E0'
        : '#E8F5E9')
    .borderRadius(8)
    .margin({ bottom: 12 })
  }

  build() {
    HdsNavDestination() {
      Stack() {
        // 背景层
        Column()
          .width('100%')
          .height('100%')
          .backgroundColor(ThemeAwareHelper.getTestManagementThemedColor('background_primary', this.themeState.currentTheme))
          .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.TOP, SafeAreaEdge.BOTTOM])

        // 内容层
        Column() {
          // 顶部导航栏
          /*
          Row() {
            Button() {
              SymbolGlyph($r('sys.symbol.arrow_left'))
                .fontSize(24)
                .fontColor([ThemeAwareHelper.getTestManagementThemedColor('text_primary', this.themeState.currentTheme)])
            }
            .width(40)
            .height(40)
            .backgroundColor(Color.Transparent)
            .onClick(() => {
              this.goBack();
            })

            Text('开源许可')
              .fontSize(20)
              .fontWeight(FontWeight.Bold)
              .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_primary', this.themeState.currentTheme))
              .layoutWeight(1)
              .textAlign(TextAlign.Center)

            // 占位符保持标题居中
            Column()
              .width(40)
              .height(40)
          }
          .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.TOP, SafeAreaEdge.BOTTOM])
          .width('100%')
          .height(56)
          .padding({ left: 16, right: 16 })
          */

          // 滚动内容
          Scroll(this.scroller) {
            Column() {
              // 项目信息
              this.buildSectionTitle('项目信息', $r('sys.symbol.computer_host_fill'))
              this.buildParagraph('漫匣（ManXia）是一款基于HarmonyOS Next的现代化漫画阅读应用，采用纯ArkTS架构开发。')

              Column({ space: 8 }) {
                Row() {
                  Text('项目名称')
                    .fontSize(14)
                    .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_muted', this.themeState.currentTheme))
                    .width(100)
                  Text('漫匣 (ManXia)')
                    .fontSize(14)
                    .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_primary', this.themeState.currentTheme))
                }
                Row() {
                  Text('开发者')
                    .fontSize(14)
                    .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_muted', this.themeState.currentTheme))
                    .width(100)
                  Text('DaLongZhuaZi')
                    .fontSize(14)
                    .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_primary', this.themeState.currentTheme))
                }
                Row() {
                  Text('开源协议')
                    .fontSize(14)
                    .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_muted', this.themeState.currentTheme))
                    .width(100)
                  Text('MIT License')
                    .fontSize(14)
                    .fontColor(ThemeAwareHelper.getTestManagementThemedColor('accent_blue', this.themeState.currentTheme))
                }
                Row() {
                  Text('项目地址')
                    .fontSize(14)
                    .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_muted', this.themeState.currentTheme))
                    .width(100)
                  Text('github.com/DaLongZhuaZi/manxia')
                    .fontSize(14)
                    .fontColor(ThemeAwareHelper.getTestManagementThemedColor('accent_blue', this.themeState.currentTheme))
                }
              }
              .width('100%')
              .padding(16)
              .backgroundColor(ThemeAwareHelper.getTestManagementThemedColor('comp_background_secondary', this.themeState.currentTheme))
              .borderRadius(8)
              .margin({ bottom: 16 })

              // 第三方开源库
              this.buildSectionTitle('第三方开源库', $r('sys.symbol.flag_fill'))
              this.buildParagraph('本应用使用了以下开源组件，感谢这些优秀项目的贡献者：')

              this.buildLibraryItem(
                '@ohos/commons-compress',
                '^2.0.6',
                'Apache-2.0',
                '支持TAR/GZ/BZ2/XZ等流式压缩格式的解压缩功能'
              )

              this.buildLibraryItem(
                '@ohos/oh7zip',
                '1.0.3',
                'Apache-2.0',
                '提供7Z/LZMA等复杂压缩包的解压能力，并支持密码压缩包'
              )

              this.buildLibraryItem(
                '@ohos/minizip',
                '1.0.4',
                'Apache-2.0',
                '为ZIP/CBZ提供密码解压与文件名编码兼容能力'
              )

              this.buildLibraryItem(
                '@ohos/unrar',
                '2.0.4',
                'Apache-2.0',
                '提供RAR/CBR压缩包解压能力，并支持加密压缩包'
              )

              this.buildLibraryItem(
                'pako',
                '2.1.0',
                'MIT',
                'GZip压缩/解压支持库'
              )

              this.buildLibraryItem(
                'js-sha256',
                '0.11.0',
                'MIT',
                'SHA256哈希计算库'
              )

              this.buildLibraryItem(
                'lz4js',
                '0.2.0',
                'MIT',
                'LZ4压缩/解压支持库'
              )

              this.buildLibraryItem(
                'snappyjs',
                '0.7.0',
                'MIT',
                'Snappy压缩/解压支持库'
              )

              this.buildLibraryItem(
                'text-encoding',
                '0.7.0',
                'Unlicense',
                '文本编码转换库'
              )

              // 参考项目
              this.buildSectionTitle('参考项目', $r('sys.symbol.hand_thumbsup_fill'))
              this.buildParagraph('本项目在开发过程中参考了以下开源项目的代码和思路：')

              this.buildLibraryItem(
                'Keiyoushi Extensions',
                '-',
                'Apache-2.0',
                '图源扩展架构设计、部分图源实现参考'
              )

              this.buildLibraryItem(
                'CopyManga Copy20',
                '-',
                '未明确声明',
                '拷贝漫画图源的API接口分析和实现参考'
              )

              this.buildLibraryItem(
                'legado / 阅读3.0',
                '-',
                'GPL-3.0',
                '书源规则设计思路、小说解析架构参考'
              )

              // MIT许可证全文
              this.buildSectionTitle('MIT许可证', $r('sys.symbol.doc_text'))

              Column() {
                Text(`MIT License

Copyright (c) 2025 ManXia Team

Permission is hereby granted, free of charge, to any person obtaining a copy of this software and associated documentation files (the "Software"), to deal in the Software without restriction, including without limitation the rights to use, copy, modify, merge, publish, distribute, sublicense, and/or sell copies of the Software, and to permit persons to whom the Software is furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE.`)
                  .fontSize(12)
                  .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_secondary', this.themeState.currentTheme))
                  .lineHeight(18)
                  .width('100%')
              }
              .width('100%')
              .padding(16)
              .backgroundColor(ThemeAwareHelper.getTestManagementThemedColor('comp_background_secondary', this.themeState.currentTheme))
              .borderRadius(8)
              .margin({ bottom: 16 })

              this.buildTipBox('声明', '所有参考的代码都已根据HarmonyOS平台特性和ArkTS语言规范进行了完全重写，严格遵守所有参考项目的开源许可证要求。', 'info')

              // 底部间距
              Column()
                .height(40)
            }
            .width('100%')
            .padding({ left: 20, right: 20, top: 16, bottom: 20 })
          }
          .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.TOP, SafeAreaEdge.BOTTOM])
          .layoutWeight(1)
          .scrollBar(BarState.Auto)
          .edgeEffect(EdgeEffect.Spring)
        }
        .width('100%')
        .height('100%')
        .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.TOP, SafeAreaEdge.BOTTOM])
      }
    }
    .backgroundColor(Color.Transparent)
    .titleBar(withSafeAreaTitleBar({
      style: {
        originalStyle: {
          backgroundStyle: {
            backgroundColor: ThemeAwareHelper.getTestManagementThemedColor('panel_background', this.themeState.currentTheme)
          },
          contentStyle: {
            titleStyle: {
              mainTitleColor: ThemeAwareHelper.getTestManagementThemedColor('text_primary', this.themeState.currentTheme)
            },
            backIconStyle: {
              backgroundColor: ThemeAwareHelper.getTestManagementThemedColor('comp_background_tertiary', this.themeState.currentTheme),
              iconColor: ThemeAwareHelper.getTestManagementThemedColor('icon_primary', this.themeState.currentTheme)
            }
          }
        }
      },
      content: {
        title: { mainTitle: '开源许可' }
      }
    }))
    .onWillAppear(() => {
      PageWindowCoordinator.applyPagePolicy('OpenSourceLicensePage', this.getUIContext());
    })
    .onWillShow(() => {
      PageWindowCoordinator.reapplyPagePolicy('OpenSourceLicensePage', this.getUIContext());
    })
  }
}
