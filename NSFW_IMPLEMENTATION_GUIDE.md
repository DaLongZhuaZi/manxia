# NSFW内容识别和管理机制完整指南

## 概述

本系统已实现完整的SFW/NSFW内容分类和一键SFW模式功能，支持图源、漫画、电子书、小说的成人内容标记和过滤。

---

## 1. NSFW字段识别机制

### 1.1 图源NSFW识别

**配置文件位置：** `manxia-extensions-source/[pkg]/source.json`

**字段定义：**
```json
{
  "metadata": {
    "id": "com.manxia.extension.zh.copymangawebview",
    "name": "拷贝漫画 (WebView)",
    "nsfw": true,  // ← NSFW标记字段
    "tags": ["chinese", "webview", "popular"]
  }
}
```

**支持的值：**
- `true` / `1` - 标记为NSFW内容源
- `false` / `0` - 标记为SFW内容源
- 未设置 - 默认为SFW

**解析位置：**
- 文件：`Framework/Data/DataManager.ets`
- 方法：`importSourceFromJSON()`
- 代码：`isNSFW: metadata.nsfw === true || metadata.nsfw === 1`

**数据库存储：**
- 表：`comic_source`
- 字段：`isNSFW INTEGER DEFAULT 0`

### 1.2 漫画NSFW自动继承

**继承规则：**
1. **从图源继承** - 当从NSFW图源获取漫画时，自动标记为NSFW
2. **从标签判断** - 检查漫画标签/分类中是否包含NSFW相关关键词
3. **手动设置** - 用户可在漫画详情页手动调整

**实现位置：**
需要在以下位置添加自动继承逻辑：

```typescript
// 在保存漫画信息时
async saveComicInfo(comic: ComicInfo, sourceId: number) {
  // 1. 获取图源的NSFW状态
  const source = await this.getComicSource(sourceId);
  const sourceIsNSFW = source?.isNSFW === 1;
  
  // 2. 检查标签中的NSFW关键词
  const nsfwKeywords = ['nsfw', '18+', 'adult', '成人', 'R18', 'H', '里番'];
  const tagsLower = (comic.tags || []).map(t => t.toLowerCase()).join(',');
  const hasNSFWTag = nsfwKeywords.some(keyword => tagsLower.includes(keyword));
  
  // 3. 自动设置NSFW标记
  comic.isNSFW = sourceIsNSFW || hasNSFWTag;
}
```

### 1.3 本地导入NSFW设置

**需要添加的位置：**

#### 漫画导入
- 文件：`pages/DataManagementPage.ets`
- 位置：本地漫画导入对话框
- 添加：NSFW开关选项

```typescript
@State importIsNSFW: boolean = false;

// 在导入对话框中添加
Toggle({ type: ToggleType.Switch, isOn: this.importIsNSFW })
  .onChange((isOn: boolean) => {
    this.importIsNSFW = isOn;
  })

// 保存时使用
const comicData = {
  // ... 其他字段
  isNSFW: this.importIsNSFW
};
```

#### 电子书导入
- 文件：`pages/EBookManagementPage.ets` (如果存在)
- 添加：导入时的NSFW开关

#### 小说导入
- 文件：`pages/NovelManagementPage.ets` (如果存在)
- 添加：导入时的NSFW开关

---

## 2. NSFW手动调整功能

### 2.1 漫画详情页添加NSFW开关

**文件：** `pages/MangaDetailPage.ets`

**需要添加的代码：**

```typescript
// 1. 添加状态变量
@State mangaIsNSFW: boolean = false;

// 2. 在加载漫画详情时读取
private async loadMangaDetail() {
  // ... 现有代码
  this.mangaIsNSFW = manga.isNSFW === true;
}

// 3. 在详情页UI中添加NSFW开关（建议放在设置或操作区域）
Row() {
  Text('成人内容(NSFW)')
    .fontSize(14)
  Toggle({ type: ToggleType.Switch, isOn: this.mangaIsNSFW })
    .onChange(async (isOn: boolean) => {
      this.mangaIsNSFW = isOn;
      await this.updateMangaNSFW(isOn);
    })
}

// 4. 添加更新方法
private async updateMangaNSFW(isNSFW: boolean): Promise<void> {
  try {
    const sql = 'UPDATE comic_info SET isNSFW = ? WHERE id = ?';
    await this.dataManager.executeSql(sql, [isNSFW ? 1 : 0, this.mangaId]);
    promptAction.showToast({
      message: isNSFW ? '已标记为NSFW内容' : '已标记为SFW内容'
    });
  } catch (error) {
    logger.error(TAG, `更新NSFW状态失败: ${error}`);
  }
}
```

### 2.2 电子书详情页添加NSFW开关

**文件：** `pages/EBookDetailPage.ets`

类似漫画详情页的实现。

### 2.3 小说详情页添加NSFW开关

**文件：** `pages/NovelDetailPage.ets`

类似漫画详情页的实现。

---

## 3. 内容过滤应用

### 3.1 使用ContentFilterManager

**核心类：** `Framework/Managers/ContentFilterManager.ets`

**基本用法：**

```typescript
import { ContentFilterManager } from '../Framework/Managers/ContentFilterManager';

const filterManager = ContentFilterManager.getInstance();

// 方法1: 过滤列表
const allMangas: Manga[] = [...];
const filteredMangas = filterManager.filterContentList(allMangas);

// 方法2: 判断单个内容
if (filterManager.shouldFilterContent(manga.isNSFW)) {
  // 隐藏这个内容
  return;
}

// 方法3: 获取统计信息
const stats = filterManager.getFilterStats(allMangas);
console.log(`总数: ${stats.total}, NSFW: ${stats.nsfw}, 已过滤: ${stats.filtered}`);
```

### 3.2 需要应用过滤的页面

#### 图源列表页面
**文件：** `pages/SourceManagementPage.ets`

```typescript
private async loadSources() {
  const sources = await this.dataManager.getAllComicSources();
  const filterManager = ContentFilterManager.getInstance();
  this.sourceList = filterManager.filterContentList(sources);
}
```

#### 漫画列表/搜索页面
**文件：** `pages/SearchPage.ets`, `pages/GlobalSearchPage.ets`

```typescript
private async searchComics(query: string) {
  const results = await this.dataManager.searchComics(query);
  const filterManager = ContentFilterManager.getInstance();
  this.searchResults = filterManager.filterContentList(results);
}
```

#### 推荐/发现页面
**文件：** `pages/MainMenuPage.ets` 或相关页面

```typescript
private async loadRecommendations() {
  const mangas = await this.dataService.getPopularMangas();
  const filterManager = ContentFilterManager.getInstance();
  this.recommendations = filterManager.filterContentList(mangas);
}
```

#### 收藏/历史页面
**文件：** `pages/FavoritesPage.ets`, `pages/HistoryPage.ets`

```typescript
private async loadFavorites() {
  const favorites = await this.dataManager.getFavorites();
  const filterManager = ContentFilterManager.getInstance();
  this.favoriteList = filterManager.filterContentList(favorites);
}
```

### 3.3 监听SFW模式变化

```typescript
// 在页面初始化时添加监听器
aboutToAppear() {
  const filterManager = ContentFilterManager.getInstance();
  this.sfwModeListener = (enabled: boolean) => {
    // SFW模式变化时重新加载列表
    this.loadData();
  };
  filterManager.addListener(this.sfwModeListener);
}

// 在页面销毁时移除监听器
aboutToDisappear() {
  if (this.sfwModeListener) {
    const filterManager = ContentFilterManager.getInstance();
    filterManager.removeListener(this.sfwModeListener);
  }
}
```

---

## 4. 数据库迁移

### 4.1 检查数据库版本

**文件：** `Framework/Database/DatabaseManager.ets`

当前数据库版本应该是 **13** 或更高。

### 4.2 添加迁移脚本（如果需要）

如果数据库版本低于支持NSFW字段的版本，需要添加迁移：

```typescript
// 在 MIGRATION_SCRIPTS 中添加
{
  version: 14,
  script: `
    ALTER TABLE comic_source ADD COLUMN isNSFW INTEGER DEFAULT 0;
    ALTER TABLE comic_info ADD COLUMN isNSFW INTEGER DEFAULT 0;
  `
}
```

---

## 5. 使用示例

### 5.1 图源配置示例

**NSFW图源：**
```json
{
  "metadata": {
    "id": "com.manxia.extension.zh.picacomic",
    "name": "哔咔漫画",
    "nsfw": true,
    "tags": ["chinese", "authenticated", "popular"]
  }
}
```

**SFW图源：**
```json
{
  "metadata": {
    "id": "com.manxia.extension.zh.mh1234",
    "name": "漫画1234",
    "nsfw": false,
    "tags": ["chinese", "webview", "free"]
  }
}
```

### 5.2 用户操作流程

1. **启用SFW模式**
   - 打开：全局设置 > 调试设置（高级模式）> SFW模式
   - 切换开关即可

2. **查看过滤效果**
   - 所有NSFW图源和漫画将被隐藏
   - 列表自动刷新

3. **手动调整漫画NSFW状态**
   - 打开漫画详情页
   - 找到NSFW开关
   - 切换即可

4. **本地导入时设置NSFW**
   - 在导入对话框中
   - 勾选"NSFW内容"选项
   - 完成导入

---

## 6. 待完成的工作

### 高优先级
- [ ] 在`DataManager.ets`中实现漫画NSFW自动继承逻辑
- [ ] 在`MangaDetailPage.ets`添加NSFW手动调整开关
- [ ] 在`DataManagementPage.ets`本地导入对话框添加NSFW开关
- [ ] 在主要列表页面应用`ContentFilterManager`过滤

### 中优先级
- [ ] 在`EBookDetailPage.ets`添加NSFW开关
- [ ] 在`NovelDetailPage.ets`添加NSFW开关
- [ ] 电子书和小说导入时添加NSFW开关

### 低优先级
- [ ] 添加NSFW内容统计显示
- [ ] 添加批量NSFW标记功能
- [ ] 添加NSFW内容模糊预览选项

---

## 7. 测试检查清单

- [ ] 图源导入时正确解析`nsfw`字段
- [ ] NSFW图源的漫画自动标记为NSFW
- [ ] SFW模式开关正常工作
- [ ] 启用SFW模式后NSFW内容被隐藏
- [ ] 关闭SFW模式后NSFW内容显示
- [ ] 漫画详情页NSFW开关正常工作
- [ ] 本地导入时NSFW开关正常工作
- [ ] 数据库正确存储NSFW标记
- [ ] 过滤逻辑在所有列表页面生效

---

## 8. 技术细节

### 8.1 数据库字段

| 表名 | 字段名 | 类型 | 默认值 | 说明 |
|------|--------|------|--------|------|
| comic_source | isNSFW | INTEGER | 0 | 图源NSFW标记 |
| comic_info | isNSFW | INTEGER | 0 | 漫画NSFW标记 |

### 8.2 TypeScript接口

```typescript
// 图源
interface ComicSourceTable {
  isNSFW: boolean;
}

// 漫画
interface Manga {
  isNSFW?: boolean;
}

// 图源信息
interface MangaSourceInfo {
  isNSFW?: boolean;
}

// 小说
interface NovelInfo {
  isNSFW?: boolean;
}

interface NovelSourceInfo {
  isNSFW?: boolean;
}
```

### 8.3 设置键

```typescript
// SettingsManager
static readonly SFW_MODE_ENABLED = 'sfw_mode_enabled';
```

---

## 9. 常见问题

**Q: 为什么有些漫画没有被过滤？**
A: 可能是该漫画的`isNSFW`字段未设置。需要手动在详情页调整或重新从NSFW图源导入。

**Q: 如何批量标记NSFW内容？**
A: 目前需要逐个在详情页调整。批量标记功能在待开发列表中。

**Q: SFW模式会影响已下载的内容吗？**
A: 是的，SFW模式会隐藏所有标记为NSFW的内容，包括已下载的。

**Q: 可以为不同图源设置不同的NSFW策略吗？**
A: 目前是全局SFW模式。如需细粒度控制，可以在图源管理页面禁用特定的NSFW图源。

---

## 10. 更新日志

**v1.0.0 (2025-12-30)**
- ✅ 数据库添加`isNSFW`字段
- ✅ 数据模型添加`isNSFW`属性
- ✅ 创建`ContentFilterManager`过滤管理器
- ✅ 全局设置页面添加SFW模式开关
- ✅ 图源导入时解析`nsfw`字段
- ⏳ 待完成：自动继承、手动调整、本地导入开关

---

**文档维护者：** ManXia Team  
**最后更新：** 2025-12-30
