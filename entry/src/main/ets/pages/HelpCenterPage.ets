// 文件路径: entry/src/main/ets/pages/HelpCenterPage.ets
/**
 * 帮助中心页面
 * 显示所有帮助文档的入口
 */

import { HdsNavDestination, HdsNavDestinationAttribute, ScrollEffectType } from '@kit.UIDesignKit';
import { LengthMetrics, UIContext } from '@kit.ArkUI';
import { ThemeAwareState, ThemeAwareHelper } from '../Framework/Components/ThemeAware';
import { ThemeManager, ThemeType } from '../Framework/Managers/ThemeManager';
import { FontAwareHelper, FontAwareState } from '../Framework/Components/FontAware';
import { logger } from '../Utils/Logger';
import { getHelpPanelManagerV2 } from '../Framework/Components/HelpPanelV2';

const TAG = 'HelpCenterPage';
const TITLE_BAR_HEIGHT_MINI: number = 56;

interface NavDestinationContext {
  pathStack: NavPathStack;
}

interface HelpDocItem {
  id: string;
  title: string;
  description: string;
  icon: Resource;
  category: string;
}

@Component
export struct HelpCenterPage {
  @State pathStack: NavPathStack = new NavPathStack();
  @State themeState: ThemeAwareState = new ThemeAwareState();
  @State fontState: FontAwareState = new FontAwareState();
  @StorageLink('appFontFamily') appFontFamily: string = 'HarmonyOS Sans';
  private uiContext: UIContext | null = null;
  private scroller: Scroller = new Scroller();

  // 帮助文档列表
  private helpDocs: HelpDocItem[] = [
    {
      id: 'download_sync',
      title: 'Download同步',
      description: '从Download文件夹导入漫画和电子书',
      icon: $r('sys.symbol.folder'),
      category: '导入'
    },
    {
      id: 'file_import',
      title: '文件导入',
      description: '从设备存储导入漫画、电子书和PDF',
      icon: $r('sys.symbol.doc'),
      category: '导入'
    },
    {
      id: 'backup_restore',
      title: '备份与恢复',
      description: '导出和导入应用数据',
      icon: $r('sys.symbol.arrow_clockwise'),
      category: '数据管理'
    },
    {
      id: 'storage_management',
      title: '存储管理',
      description: '管理应用占用的存储空间',
      icon: $r('sys.symbol.externaldrive'),
      category: '数据管理'
    },
    {
      id: 'manga_settings',
      title: '漫画设置',
      description: '配置单部漫画的阅读设置',
      icon: $r('sys.symbol.book'),
      category: '阅读设置'
    },
    {
      id: 'ebook_settings',
      title: '电子书设置',
      description: '配置电子书的阅读体验',
      icon: $r('sys.symbol.text_book_closed'),
      category: '阅读设置'
    },
    {
      id: 'source_settings',
      title: '图源设置',
      description: '配置图源的个性化设置',
      icon: $r('sys.symbol.more'),
      category: '图源'
    }
  ];

  aboutToAppear(): void {
    ThemeAwareHelper.initializeThemeAware(
      TAG,
      this.themeState,
      (newTheme: ThemeType) => {
        logger.info(TAG, `主题切换到: ${newTheme}`);
      },
      (newState: ThemeAwareState) => { this.themeState = newState; }
    );
    FontAwareHelper.initializeFontAware(
      TAG,
      this.fontState,
      (newState: FontAwareState) => {
        this.fontState = newState;
      }
    );
  }

  aboutToDisappear(): void {
    ThemeAwareHelper.cleanupThemeAware(TAG);
    FontAwareHelper.cleanupFontAware(TAG);
  }

  private showHelpContent(docId: string): void {
    switch (docId) {
      case 'download_sync':
        this.showDownloadSyncHelp();
        break;
      case 'file_import':
        this.showFileImportHelp();
        break;
      case 'backup_restore':
        this.showBackupHelp();
        break;
      case 'storage_management':
        this.showStorageHelp();
        break;
      case 'manga_settings':
        this.showMangaSettingsHelp();
        break;
      case 'ebook_settings':
        this.showEBookSettingsHelp();
        break;
      case 'source_settings':
        this.showSourceSettingsHelp();
        break;
    }
  }

  private showDownloadSyncHelp(): void {
    const helpContent = `# Download同步帮助

## 功能介绍

Download同步功能允许您从设备的Download文件夹中导入漫画、电子书、PDF和小说文件，无需申请额外的存储权限。

## 使用步骤

### 1. 连接文件夹
首次使用时，点击"连接Download文件夹"按钮，选择您的Download目录。应用会在其中创建专属文件夹。

### 2. 放置文件
将您要导入的文件放入Download文件夹中：
- **漫画**: 支持 ZIP、CBZ、RAR、CBR、7Z 格式
- **电子书**: 支持 EPUB、MOBI、AZW、AZW3 格式
- **PDF**: 支持 PDF 格式（可转换为漫画或电子书）
- **小说**: 支持 TXT 格式

### 3. 扫描文件
点击"扫描文件"按钮，应用会自动检测可导入的文件。

### 4. 导入内容
- **快速导入**: 一键导入所有同类型文件
- **单独导入**: 点击文件列表中的导入按钮

## 文件状态说明

- ✓ **已导入**: 文件已成功导入到应用
- ○ **未导入**: 文件尚未导入

## 常见问题

**Q: 为什么扫描不到文件？**
A: 请确保文件格式正确，且不在保留文件夹中。

**Q: 导入后原文件会被删除吗？**
A: 不会，原文件保持不变。`;

    getHelpPanelManagerV2().showInlineHelp('Download同步帮助', helpContent);
  }

  private showFileImportHelp(): void {
    const helpContent = `# 文件导入帮助

## 功能介绍

文件导入页面允许您从设备存储导入漫画、电子书和PDF文件到应用中。

## 支持的文件格式

### 漫画文件
- **ZIP/CBZ**: 标准漫画压缩包格式
- **RAR/CBR**: RAR压缩的漫画文件
- **7Z**: 7-Zip压缩格式

### 电子书文件
- **EPUB**: 最常用的电子书格式
- **MOBI/AZW/AZW3**: Kindle电子书格式

### PDF文件
- 可选择导入为漫画或电子书

## 导入方式

### 选择文件导入
1. 点击"选择文件"按钮
2. 在文件选择器中选择要导入的文件
3. 配置导入选项
4. 确认导入

### 批量导入
支持同时选择多个文件进行批量导入。

## ComicInfo.xml支持

如果压缩包中包含ComicInfo.xml文件，将自动读取：
- 标题、作者信息
- 标签和分类
- 简介描述`;

    getHelpPanelManagerV2().showInlineHelp('文件导入帮助', helpContent);
  }

  private showBackupHelp(): void {
    const helpContent = `# 备份与恢复帮助

## 功能介绍

备份与恢复功能允许您导出和导入所有应用数据，包括漫画、电子书、小说的阅读进度、收藏、设置等。

## 本地备份

### 创建备份
1. 切换到"本地备份"标签
2. 点击"创建备份"按钮
3. 选择要备份的内容
4. 等待备份完成

### 恢复备份
1. 在备份列表中找到要恢复的备份
2. 点击"恢复"按钮
3. 选择要恢复的内容
4. 确认恢复操作

## 云端备份 (WebDAV)

WebDAV允许您将备份文件同步到云端服务器，实现多设备数据同步。

### 配置WebDAV
1. 切换到"云端备份"标签
2. 点击"配置WebDAV"
3. 输入服务器地址、用户名、密码
4. 测试连接后保存

### ❗ 重要提示

**大多数WebDAV服务器不允许在根目录创建文件夹！**

请在配置前先在服务器上手动创建备份目录（如 /manxia）：
- 群晖NAS: 在File Station中创建文件夹
- 威联通NAS: 在文件管理器中创建文件夹
- Nextcloud/ownCloud: 在网页端创建文件夹
- 坚果云: 在网页或客户端创建文件夹

### 常见服务器配置示例

**群晖 (Synology)**
- 地址: https://你的NAS地址:5006
- 确保已在控制面板启用WebDAV服务
- HTTPS端口默认5006，HTTP端口5005

**Nextcloud**
- 地址: https://域名/remote.php/dav/files/用户名
- 建议使用应用密码而非登录密码

**坚果云**
- 地址: https://dav.jianguoyun.com/dav
- ❗ 必须使用"应用密码"，不能使用登录密码
- 在账户设置 > 安全选项 > 第三方应用管理 中生成

**Alist**
- 地址: http://你的Alist地址:5244/dav
- 使用Alist的登录用户名和密码

### 常见问题

**Q: 测试连接提示“权限被拒绝(403)”？**
A: 请在服务器上手动创建备份目录（如 /manxia），然后重试。

**Q: 测试连接提示“目录不存在(404)”？**
A: 请检查"基础路径"是否正确，或在服务器上创建该目录。

**Q: 测试连接提示“认证失败(401)”？**
A: 请检查用户名和密码是否正确。如使用坚果云，请确保使用的是"应用密码"。

**Q: 连接超时或无法连接？**
A: 请检查服务器地址是否正确，包括协议(http/https)和端口号。

**Q: 自签名SSL证书怎么办？**
A: 应用已自动支持自签名证书，无需额外配置。

## 注意事项

- 备份不包含实际的图片和文件内容，只包含元数据
- 恢复时会覆盖现有数据，请谨慎操作
- 建议定期创建备份以防数据丢失`;

    getHelpPanelManagerV2().showInlineHelp('备份与恢复帮助', helpContent);
  }

  private showStorageHelp(): void {
    const helpContent = `# 存储管理帮助

## 功能介绍

存储管理页面帮助您了解和管理应用占用的存储空间。

## 存储类型说明

### 缓存数据
- **内存缓存**: 临时存储在内存中的图片
- **磁盘缓存**: 存储在本地的图片缓存
- **永久缓存**: 已下载的漫画章节图片

### 应用数据
- **漫画数据**: 漫画信息、阅读进度、收藏等
- **电子书数据**: 电子书文件和阅读记录
- **小说数据**: 小说内容和阅读进度

## 清理操作

### 清理缓存
点击"清理缓存"可以释放临时缓存空间，不会影响已下载的内容。

## 注意事项

- 清理永久缓存会删除已下载的漫画章节
- 建议定期清理临时缓存以释放空间`;

    getHelpPanelManagerV2().showInlineHelp('存储管理帮助', helpContent);
  }

  private showMangaSettingsHelp(): void {
    const helpContent = `# 漫画设置帮助

## 功能介绍

漫画设置页面允许您为单部漫画配置个性化的阅读设置。

## 阅读方向设置

| 选项 | 说明 |
|------|------|
| 从左到右 | 适合国漫、欧美漫画 |
| 从右到左 | 适合日漫 |
| 垂直滚动 | 条漫模式 |

## 阅读模式设置

- **单页模式**: 每次显示一页
- **双页模式**: 同时显示两页
- **条漫模式**: 垂直连续滚动

## 翻页动画

- **无动画**: 直接切换
- **滑动**: 左右滑动效果
- **卷页**: 仿真翻书效果
- **淡入淡出**: 渐变切换`;

    getHelpPanelManagerV2().showInlineHelp('漫画设置帮助', helpContent);
  }

  private showEBookSettingsHelp(): void {
    const helpContent = `# 电子书设置帮助

## 功能介绍

电子书设置页面允许您配置电子书的阅读体验。

## 字体设置

### 字体大小
拖动滑块调整文字大小，范围12-32像素。

### 行间距
调整行与行之间的距离，让阅读更舒适。

## 背景设置

### 预设背景
- 白色（默认）
- 护眼黄
- 护眼绿
- 夜间模式

## 翻页动画

| 动画类型 | 说明 |
|---------|------|
| 无动画 | 直接切换 |
| 滑动 | 左右滑动效果 |
| 仿真翻页 | 模拟真实翻书 |

## 显示设置

- **页码显示**: 在右下角显示当前页码
- **进度显示**: 显示阅读百分比
- **时间显示**: 在底部显示当前时间`;

    getHelpPanelManagerV2().showInlineHelp('电子书设置帮助', helpContent);
  }

  private showSourceSettingsHelp(): void {
    const helpContent = `# 图源设置帮助

## 功能介绍

图源设置页面允许您配置特定图源的个性化设置。

## 阅读设置

### 阅读方向
- **从左到右**: 适合国漫、欧美漫画
- **从右到左**: 适合日漫
- **垂直滚动**: 条漫模式

## 网络设置

### 镜像站点
如果原站点访问较慢，可以选择镜像站点加速访问。

### User-Agent
自定义请求的User-Agent。

## 登录管理

### 登录状态
显示当前图源的登录状态。

### 清除登录
清除当前图源的登录信息和Cookie。

## 注意事项

- 设置仅对当前图源生效
- 部分设置需要重新加载内容才能生效`;

    getHelpPanelManagerV2().showInlineHelp('图源设置帮助', helpContent);
  }

  @Builder
  buildHelpItem(item: HelpDocItem) {
    Row({ space: 12 }) {
      // 图标
      Column() {
        SymbolGlyph(item.icon)
          .fontSize(24)
          .fontColor([ThemeAwareHelper.getTestManagementThemedColor('accent_primary', this.themeState.currentTheme)])
      }
      .width(48)
      .height(48)
      .justifyContent(FlexAlign.Center)
      .backgroundColor(ThemeAwareHelper.getTestManagementThemedColor('comp_background_tertiary', this.themeState.currentTheme))
      .borderRadius(12)

      // 文字内容
      Column({ space: 4 }) {
        Text(item.title)
          .fontSize(16)
          .fontWeight(FontWeight.Medium)
          .fontFamily(this.appFontFamily)
          .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_primary', this.themeState.currentTheme))
        Text(item.description)
          .fontSize(13)
          .fontFamily(this.appFontFamily)
          .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_secondary', this.themeState.currentTheme))
          .maxLines(2)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
      }
      .layoutWeight(1)
      .alignItems(HorizontalAlign.Start)

      // 箭头
      SymbolGlyph($r('sys.symbol.chevron_right'))
        .fontSize(16)
        .fontColor([ThemeAwareHelper.getTestManagementThemedColor('text_muted', this.themeState.currentTheme)])
    }
    .width('100%')
    .padding(16)
    .backgroundColor(ThemeAwareHelper.getTestManagementThemedColor('panel_background', this.themeState.currentTheme))
    .borderRadius(12)
    .onClick(() => {
      this.showHelpContent(item.id);
    })
  }

  @Builder
  buildCategorySection(category: string, items: HelpDocItem[]) {
    Column({ space: 12 }) {
      // 分类标题
      Text(category)
        .fontSize(14)
        .fontWeight(FontWeight.Medium)
        .fontFamily(this.appFontFamily)
        .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_secondary', this.themeState.currentTheme))
        .width('100%')
        .padding({ left: 4 })

      // 帮助项列表
      ForEach(items, (item: HelpDocItem) => {
        this.buildHelpItem(item)
      }, (item: HelpDocItem) => item.id)
    }
    .width('100%')
  }

  build() {
    HdsNavDestination() {
      Stack() {
        // 背景层
        Column()
          .width('100%')
          .height('100%')
          .backgroundColor(ThemeAwareHelper.getTestManagementThemedColor('background', this.themeState.currentTheme))
          .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.TOP, SafeAreaEdge.BOTTOM])

        // 内容层
        Column() {
          Blank().height(TITLE_BAR_HEIGHT_MINI)

          Scroll(this.scroller) {
            Column({ space: 24 }) {
              // 导入分类
              this.buildCategorySection('导入', this.helpDocs.filter(d => d.category === '导入'))

              // 数据管理分类
              this.buildCategorySection('数据管理', this.helpDocs.filter(d => d.category === '数据管理'))

              // 阅读设置分类
              this.buildCategorySection('阅读设置', this.helpDocs.filter(d => d.category === '阅读设置'))

              // 图源分类
              this.buildCategorySection('图源', this.helpDocs.filter(d => d.category === '图源'))

              Blank().height(20)
            }
            .width('100%')
            .padding({ left: 16, right: 16, top: 8 })
          }
          .layoutWeight(1)
          .scrollBar(BarState.Auto)
          .edgeEffect(EdgeEffect.Spring)
        }
        .width('100%')
        .height('100%')
      }
    }
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
        title: { mainTitle: '帮助中心' }
      }
    })
    .onReady((context: NavDestinationContext) => {
      this.pathStack = context.pathStack;
      this.uiContext = this.getUIContext();
      ThemeAwareHelper.initializeThemeAware(
        TAG,
        this.themeState,
        (newTheme: ThemeType) => {},
        (newState: ThemeAwareState) => { this.themeState = newState; }
      );
    })
    .backgroundColor(Color.Transparent)
  }
}
