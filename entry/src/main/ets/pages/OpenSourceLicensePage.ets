// 文件路径: entry/src/main/ets/pages/OpenSourceLicensePage.ets
// 职责: 开源许可页面，展示本项目使用的开源组件及其许可证信息
// 最后编辑: 2025-11-29

import { HdsNavDestination, HdsNavDestinationAttribute, ScrollEffectType } from '@kit.UIDesignKit';
import { ThemeAwareState, ThemeAwareHelper } from 'manxia_theme/src/main/ets/Framework/Components/ThemeAware';
import { ThemeManager, ThemeType } from 'manxia_theme/src/main/ets/Framework/Managers/ThemeManager';
import { logger } from 'manxia_core/src/main/ets/Utils/Logger';
import { PageLifecycleManager } from 'manxia_core/src/main/ets/Framework/Lifecycle/index';
import { DisplayMode } from 'manxia_theme/src/main/ets/Utils/WindowManager';
import { PageWindowCoordinator } from 'manxia_theme/src/main/ets/Utils/PageWindowCoordinator';
import { SettingsImmersiveTitleBar } from './settings/SettingsImmersiveTitleBar';
import { SettingsPageTitleBarManager } from 'manxia_features_ui/src/main/ets/pages/settings/SettingsPageTitleBarManager';
import { SettingsPanelSurfaceHelper } from 'manxia_features_ui/src/main/ets/pages/settings/SettingsPanelSurfaceHelper';

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

  private getPageBackgroundResource(): ResourceStr {
    return $r('app.media.mangabook');
  }

  private getPageBackgroundTint(): string {
    return this.themeState.currentTheme === ThemeType.DARK
      ? 'rgba(7, 10, 16, 0.28)'
      : 'rgba(246, 249, 252, 0.18)';
  }

  private getPageBackgroundScrimColors(): [ResourceColor, number][] {
    if (this.themeState.currentTheme === ThemeType.DARK) {
      return [
        ['rgba(7, 10, 16, 0.08)', 0.0] as [ResourceColor, number],
        ['rgba(7, 10, 16, 0.2)', 0.52] as [ResourceColor, number],
        ['rgba(7, 10, 16, 0.44)', 1.0] as [ResourceColor, number]
      ];
    }
    return [
      ['rgba(255, 255, 255, 0.02)', 0.0] as [ResourceColor, number],
      ['rgba(246, 249, 252, 0.08)', 0.52] as [ResourceColor, number],
      ['rgba(238, 244, 250, 0.22)', 1.0] as [ResourceColor, number]
    ];
  }

  @Builder
  private buildPageBackground() {
    Stack() {
      Image(this.getPageBackgroundResource())
        .width('100%')
        .height('100%')
        .objectFit(ImageFit.Cover)
        .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.TOP, SafeAreaEdge.BOTTOM])

      Column()
        .width('100%')
        .height('100%')
        .backgroundColor(this.getPageBackgroundTint())
        .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.TOP, SafeAreaEdge.BOTTOM])

      Column()
        .width('100%')
        .height('100%')
        .linearGradient({
          direction: GradientDirection.Bottom,
          colors: this.getPageBackgroundScrimColors()
        })
        .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.TOP, SafeAreaEdge.BOTTOM])
    }
    .width('100%')
    .height('100%')
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
    .backgroundColor(SettingsPanelSurfaceHelper.getBackground(this.themeState.currentTheme))
    .linearGradient(SettingsPanelSurfaceHelper.getSurfaceGradient(this.themeState.currentTheme))
    .backgroundBlurStyle(
      SettingsPanelSurfaceHelper.getBlurStyle(this.themeState.currentTheme),
      SettingsPanelSurfaceHelper.getBlurOptions(this.themeState.currentTheme)
    )
    .backgroundEffect(SettingsPanelSurfaceHelper.getBackgroundEffect(this.themeState.currentTheme))
    .borderRadius(12)
    .clip(true)
    .border({
      width: SettingsPanelSurfaceHelper.getBorderWidth(this.themeState.currentTheme),
      color: SettingsPanelSurfaceHelper.getBorderColor(this.themeState.currentTheme)
    })
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
    .backgroundBlurStyle(
      SettingsPanelSurfaceHelper.getBlurStyle(this.themeState.currentTheme),
      SettingsPanelSurfaceHelper.getBlurOptions(this.themeState.currentTheme)
    )
    .margin({ bottom: 12 })
  }

  build() {
    HdsNavDestination() {
      Stack() {
        this.buildPageBackground()

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
              Blank().height(SettingsPageTitleBarManager.getContentTopPadding(this.statusBarHeight))

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
              .backgroundColor(SettingsPanelSurfaceHelper.getBackground(this.themeState.currentTheme))
              .linearGradient(SettingsPanelSurfaceHelper.getSurfaceGradient(this.themeState.currentTheme))
              .backgroundBlurStyle(
                SettingsPanelSurfaceHelper.getBlurStyle(this.themeState.currentTheme),
                SettingsPanelSurfaceHelper.getBlurOptions(this.themeState.currentTheme)
              )
              .backgroundEffect(SettingsPanelSurfaceHelper.getBackgroundEffect(this.themeState.currentTheme))
              .borderRadius(SettingsPanelSurfaceHelper.getRadius(this.themeState.currentTheme))
              .clip(true)
              .border({
                width: SettingsPanelSurfaceHelper.getBorderWidth(this.themeState.currentTheme),
                color: SettingsPanelSurfaceHelper.getBorderColor(this.themeState.currentTheme)
              })
              .shadow({
                radius: SettingsPanelSurfaceHelper.getRadius(this.themeState.currentTheme) + 4,
                color: SettingsPanelSurfaceHelper.getShadowColor(this.themeState.currentTheme),
                offsetX: 0,
                offsetY: 8
              })
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

              // 内置字体
              this.buildSectionTitle('内置字体', $r('sys.symbol.textformat'))
              this.buildParagraph('以下字体随应用打包提供，用户无需导入即可在字体管理与各阅读器中使用：')

              this.buildLibraryItem(
                'Smiley Sans 得意黑',
                '2.0.1',
                'SIL OFL 1.1',
                '内置中文字体（Smiley Sans Oblique）；版权归属 atelierAnchor'
              )

              // PDF 渲染引擎
              this.buildSectionTitle('PDF 渲染引擎', $r('sys.symbol.doc_text'))
              this.buildParagraph('以下引擎已纳入引入评估与集成流程：')

              this.buildLibraryItem(
                'PDFium',
                '规划引入',
                'BSD-3-Clause',
                '开源 PDF 渲染引擎（已完成源码获取与构建方案评估；当前版本仍使用系统 PDF Kit 渲染）'
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
              .backgroundColor(SettingsPanelSurfaceHelper.getBackground(this.themeState.currentTheme))
              .linearGradient(SettingsPanelSurfaceHelper.getSurfaceGradient(this.themeState.currentTheme))
              .backgroundBlurStyle(
                SettingsPanelSurfaceHelper.getBlurStyle(this.themeState.currentTheme),
                SettingsPanelSurfaceHelper.getBlurOptions(this.themeState.currentTheme)
              )
              .backgroundEffect(SettingsPanelSurfaceHelper.getBackgroundEffect(this.themeState.currentTheme))
              .borderRadius(SettingsPanelSurfaceHelper.getRadius(this.themeState.currentTheme))
              .clip(true)
              .border({
                width: SettingsPanelSurfaceHelper.getBorderWidth(this.themeState.currentTheme),
                color: SettingsPanelSurfaceHelper.getBorderColor(this.themeState.currentTheme)
              })
              .shadow({
                radius: SettingsPanelSurfaceHelper.getRadius(this.themeState.currentTheme) + 4,
                color: SettingsPanelSurfaceHelper.getShadowColor(this.themeState.currentTheme),
                offsetX: 0,
                offsetY: 8
              })
              .margin({ bottom: 16 })

              // SIL Open Font License 1.1 全文（内置字体 Smiley Sans 得意黑）
              this.buildSectionTitle('SIL Open Font License 1.1', $r('sys.symbol.doc_text'))

              Column() {
                Text(`Copyright (c) 2022--2024, atelierAnchor <https://atelier-anchor.com>,
with Reserved Font Name <Smiley> and <得意黑>.

This Font Software is licensed under the SIL Open Font License, Version 1.1.
This license is copied below, and is also available with a FAQ at:
http://scripts.sil.org/OFL

-----------------------------------------------------------
SIL OPEN FONT LICENSE Version 1.1 - 26 February 2007
-----------------------------------------------------------

PREAMBLE
The goals of the Open Font License (OFL) are to stimulate worldwide
development of collaborative font projects, to support the font creation
efforts of academic and linguistic communities, and to provide a free and
open framework in which fonts may be shared and improved in partnership
with others.

The OFL allows the licensed fonts to be used, studied, modified and
redistributed freely as long as they are not sold by themselves. The
fonts, including any derivative works, can be bundled, embedded, 
redistributed and/or sold with any software provided that any reserved
names are not used by derivative works. The fonts and derivatives,
however, cannot be released under any other type of license. The
requirement for fonts to remain under this license does not apply
to any document created using the fonts or their derivatives.

DEFINITIONS
"Font Software" refers to the set of files released by the Copyright
Holder(s) under this license and clearly marked as such. This may
include source files, build scripts and documentation.

"Reserved Font Name" refers to any names specified as such after the
copyright statement(s).

"Original Version" refers to the collection of Font Software components as
distributed by the Copyright Holder(s).

"Modified Version" refers to any derivative made by adding to, deleting,
or substituting -- in part or in whole -- any of the components of the
Original Version, by changing formats or by porting the Font Software to a
new environment.

"Author" refers to any designer, engineer, programmer, technical
writer or other person who contributed to the Font Software.

PERMISSION & CONDITIONS
Permission is hereby granted, free of charge, to any person obtaining
a copy of the Font Software, to use, study, copy, merge, embed, modify,
redistribute, and sell modified and unmodified copies of the Font
Software, subject to the following conditions:

1) Neither the Font Software nor any of its individual components,
in Original or Modified Versions, may be sold by itself.

2) Original or Modified Versions of the Font Software may be bundled,
redistributed and/or sold with any software, provided that each copy
contains the above copyright notice and this license. These can be
included either as stand-alone text files, human-readable headers or
in the appropriate machine-readable metadata fields within text or
binary files as long as those fields can be easily viewed by the user.

3) No Modified Version of the Font Software may use the Reserved Font
Name(s) unless explicit written permission is granted by the corresponding
Copyright Holder. This restriction only applies to the primary font name as
presented to the users.

4) The name(s) of the Copyright Holder(s) or the Author(s) of the Font
Software shall not be used to promote, endorse or advertise any
Modified Version, except to acknowledge the contribution(s) of the
Copyright Holder(s) and the Author(s) or with their explicit written
permission.

5) The Font Software, modified or unmodified, in part or in whole,
must be distributed entirely under this license, and must not be
distributed under any other license. The requirement for fonts to
remain under this license does not apply to any document created
using the Font Software.

TERMINATION
This license becomes null and void if any of the above conditions are
not met.

DISCLAIMER
THE FONT SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND,
EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO ANY WARRANTIES OF
MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT
OF COPYRIGHT, PATENT, TRADEMARK, OR OTHER RIGHT. IN NO EVENT SHALL THE
COPYRIGHT HOLDER BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY,
INCLUDING ANY GENERAL, SPECIAL, INDIRECT, INCIDENTAL, OR CONSEQUENTIAL
DAMAGES, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING
FROM, OUT OF THE USE OR INABILITY TO USE THE FONT SOFTWARE OR FROM
OTHER DEALINGS IN THE FONT SOFTWARE.`)
                  .fontSize(12)
                  .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_secondary', this.themeState.currentTheme))
                  .lineHeight(18)
                  .width('100%')
              }
              .width('100%')
              .padding(16)
              .backgroundColor(SettingsPanelSurfaceHelper.getBackground(this.themeState.currentTheme))
              .linearGradient(SettingsPanelSurfaceHelper.getSurfaceGradient(this.themeState.currentTheme))
              .backgroundBlurStyle(
                SettingsPanelSurfaceHelper.getBlurStyle(this.themeState.currentTheme),
                SettingsPanelSurfaceHelper.getBlurOptions(this.themeState.currentTheme)
              )
              .backgroundEffect(SettingsPanelSurfaceHelper.getBackgroundEffect(this.themeState.currentTheme))
              .borderRadius(SettingsPanelSurfaceHelper.getRadius(this.themeState.currentTheme))
              .clip(true)
              .border({
                width: SettingsPanelSurfaceHelper.getBorderWidth(this.themeState.currentTheme),
                color: SettingsPanelSurfaceHelper.getBorderColor(this.themeState.currentTheme)
              })
              .shadow({
                radius: SettingsPanelSurfaceHelper.getRadius(this.themeState.currentTheme) + 4,
                color: SettingsPanelSurfaceHelper.getShadowColor(this.themeState.currentTheme),
                offsetX: 0,
                offsetY: 8
              })
              .margin({ bottom: 16 })

              // BSD-3-Clause 全文（PDFium）
              this.buildSectionTitle('BSD-3-Clause 许可证', $r('sys.symbol.doc_text'))

              Column() {
                Text(`Copyright 2014 The PDFium Authors

 Redistribution and use in source and binary forms, with or without
 modification, are permitted provided that the following conditions are
 met:

    * Redistributions of source code must retain the above copyright
 notice, this list of conditions and the following disclaimer.
    * Redistributions in binary form must reproduce the above
 copyright notice, this list of conditions and the following disclaimer
 in the documentation and/or other materials provided with the
 distribution.
    * Neither the name of Google Inc. nor the names of its
 contributors may be used to endorse or promote products derived from
 this software without specific prior written permission.

 THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS
 "AS IS" AND ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT
 LIMITED TO, THE IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR
 A PARTICULAR PURPOSE ARE DISCLAIMED. IN NO EVENT SHALL THE COPYRIGHT
 OWNER OR CONTRIBUTORS BE LIABLE FOR ANY DIRECT, INDIRECT, INCIDENTAL,
 SPECIAL, EXEMPLARY, OR CONSEQUENTIAL DAMAGES (INCLUDING, BUT NOT
 LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS OR SERVICES; LOSS OF USE,
 DATA, OR PROFITS; OR BUSINESS INTERRUPTION) HOWEVER CAUSED AND ON ANY
 THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY, OR TORT
 (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE
 OF THIS SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.


                                 Apache License`)
                  .fontSize(12)
                  .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_secondary', this.themeState.currentTheme))
                  .lineHeight(18)
                  .width('100%')
              }
              .width('100%')
              .padding(16)
              .backgroundColor(SettingsPanelSurfaceHelper.getBackground(this.themeState.currentTheme))
              .linearGradient(SettingsPanelSurfaceHelper.getSurfaceGradient(this.themeState.currentTheme))
              .backgroundBlurStyle(
                SettingsPanelSurfaceHelper.getBlurStyle(this.themeState.currentTheme),
                SettingsPanelSurfaceHelper.getBlurOptions(this.themeState.currentTheme)
              )
              .backgroundEffect(SettingsPanelSurfaceHelper.getBackgroundEffect(this.themeState.currentTheme))
              .borderRadius(SettingsPanelSurfaceHelper.getRadius(this.themeState.currentTheme))
              .clip(true)
              .border({
                width: SettingsPanelSurfaceHelper.getBorderWidth(this.themeState.currentTheme),
                color: SettingsPanelSurfaceHelper.getBorderColor(this.themeState.currentTheme)
              })
              .shadow({
                radius: SettingsPanelSurfaceHelper.getRadius(this.themeState.currentTheme) + 4,
                color: SettingsPanelSurfaceHelper.getShadowColor(this.themeState.currentTheme),
                offsetX: 0,
                offsetY: 8
              })
              .margin({ bottom: 16 })

              this.buildTipBox('声明', '所有参考的代码都已根据HarmonyOS平台特性和ArkTS语言规范进行了完全重写，严格遵守所有参考项目的开源许可证要求。', 'info')

              // 底部间距
              Blank().height(24 + this.navigationBarHeight)
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
        SettingsImmersiveTitleBar({
          themeState: this.themeState,
          title: '开源许可',
          contentPadding: 20,
          maxContentWidth: 1200
        })
      }
    }
    .backgroundColor(Color.Transparent)
    .hideTitleBar(true)
    .ignoreLayoutSafeArea([LayoutSafeAreaType.SYSTEM], [LayoutSafeAreaEdge.TOP, LayoutSafeAreaEdge.BOTTOM])
    .onWillAppear(() => {
      PageWindowCoordinator.applyPagePolicy('OpenSourceLicensePage', this.getUIContext());
    })
    .onWillShow(() => {
      PageWindowCoordinator.reapplyPagePolicy('OpenSourceLicensePage', this.getUIContext());
    })
  }
}
