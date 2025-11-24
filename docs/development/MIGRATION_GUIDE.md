# 漫画系统迁移指南

## 概述

本指南说明如何将现有代码迁移到新的类型系统。新系统彻底解决了以下问题：

1. ✅ **类型混淆**：在线漫画不再被错误识别为本地漫画
2. ✅ **数据加载策略**：实现"优先缓存，按需网络"
3. ✅ **图源识别**：使用name而不是ID
4. ✅ **数据重复**：数据库层面防止重复

## 新架构组件

### 核心类型系统

**文件**: `Framework/Types/MangaTypes.ets`

```typescript
// 漫画类型
export enum MangaSourceType {
  LOCAL = 'LOCAL',    // 本地漫画
  ONLINE = 'ONLINE'   // 在线漫画
}

// 在线漫画
export interface OnlineManga extends MangaBase {
  sourceType: MangaSourceType.ONLINE;
  sourceName: string;  // 图源名称（如：komiic）
  sourceId: number;
  externalId: string;
  isInLibrary: boolean;
}

// 本地漫画
export interface LocalManga extends MangaBase {
  sourceType: MangaSourceType.LOCAL;
  localPath: string;
}
```

### 数据加载器

**文件**: `Framework/Managers/MangaDataLoader.ets`

```typescript
const loader = MangaDataLoader.getInstance();

// 加载漫画详情（自动判断缓存）
const result = await loader.loadMangaDetail(mangaId, forceRefresh);

// 判断类型
if (isOnlineManga(result.manga)) {
  console.log(`图源: ${result.manga.sourceName}`);
} else {
  console.log(`本地路径: ${result.manga.localPath}`);
}
```

### 类型适配器

**文件**: `Framework/Adapters/MangaTypeAdapter.ets`

```typescript
// 旧类型 -> 新类型
const manga = MangaTypeAdapter.convertToManga(legacyComicInfo, sourceName);
const chapters = MangaTypeAdapter.convertToChapters(legacyChapters);

// 新类型 -> 旧类型
const legacyComicInfo = MangaTypeAdapter.convertFromManga(manga);
```

## 迁移步骤

### 1. MangaDetailPage 迁移

#### 旧代码（问题）
```typescript
// ❌ 错误：使用sourceId判断类型
if (this.pageParams.sourceId) {
  this.useWebView = await this.webViewManager.isWebViewSource(this.sourceId);
}

// ❌ 错误：复杂的加载逻辑
if (this.useWebView && this.sourceId > 0) {
  if (!this.isRefreshing) {
    await this.loadOnlineMangaFromDatabaseOnly();
  } else {
    await this.loadMangaDataWithWebView();
  }
}
```

#### 新代码（正确）
```typescript
// ✅ 使用新的数据加载器
import { MangaDetailDataLoader } from './helpers/MangaDetailDataLoader';

private detailLoader = new MangaDetailDataLoader();

async loadMangaData(): Promise<void> {
  try {
    // 一行代码搞定所有逻辑
    const result = await this.detailLoader.loadMangaDetail(
      this.pageParams.mangaId,
      this.isRefreshing  // 是否强制刷新
    );
    
    // 使用结果
    this.currentManga = result.manga;
    this.currentManga.chapters = result.chapters;
    
    // 根据数据来源显示提示
    if (result.dataSource === 'cache' && result.needsRefresh) {
      console.log('使用缓存数据，建议刷新');
    }
    
    this.isLoading = false;
  } catch (error) {
    this.loadError = error.message;
    this.isLoading = false;
  }
}
```

### 2. MangaReaderPage 迁移

#### 旧代码（问题）
```typescript
// ❌ 错误：通过sourceId判断类型
if (this.pageParams?.sourceId) {
  readerParams.manga = this.currentManga;
  readerParams.sourceId = this.pageParams.sourceId;
  readerParams.contentType = chapter.isDownloaded 
    ? MangaReaderContentType.OnlineDownloaded 
    : MangaReaderContentType.OnlineUndownloaded;
} else {
  readerParams.contentType = MangaReaderContentType.Local;
}
```

#### 新代码（正确）
```typescript
// ✅ 使用新的类型系统
import { MangaDataLoader } from '../Framework/Managers/MangaDataLoader';
import { isOnlineManga, isOnlineChapter } from '../Framework/Types/MangaTypes';

private dataLoader = MangaDataLoader.getInstance();

async initializeMangaReader(params: MangaReaderPageParams): Promise<void> {
  // 加载漫画数据
  const result = await this.dataLoader.loadMangaDetail(params.mangaId);
  const manga = result.manga;
  
  // 根据类型判断
  if (isOnlineManga(manga)) {
    // 在线漫画
    this.sourceName = manga.sourceName;
    this.sourceId = manga.sourceId;
    
    // 加载章节页面
    const chapterResult = await this.dataLoader.loadChapterPages(
      params.chapterId,
      manga
    );
    
    this.pages = chapterResult.pages;
  } else {
    // 本地漫画
    this.localPath = manga.localPath;
    // 直接加载本地文件
  }
}
```

### 3. 图源识别迁移

#### 旧代码（问题）
```typescript
// ❌ 错误：使用ID传递
readerParams.sourceId = this.pageParams.sourceId;

// ❌ 错误：通过ID查找
const source = await dataManager.getComicSourceById(sourceId);
```

#### 新代码（正确）
```typescript
// ✅ 使用name传递
readerParams.sourceName = 'komiic';

// ✅ 通过name查找
const loader = MangaDataLoader.getInstance();
const sourceId = await loader.getSourceIdByName('komiic');
const sourceName = await loader.getSourceNameById(8);
```

## 数据库迁移

### 运行迁移脚本

```typescript
import { checkAndExecuteMigration } from './Framework/Database/MigrationScripts';

// 在应用启动时执行
const store = DatabaseManager.getInstance().getStore();
await checkAndExecuteMigration(store, currentVersion);
```

### 迁移内容

1. **清理重复数据**
   - 扫描并删除重复的章节
   - 保留最新的记录

2. **添加唯一性约束**
   - `chapter(comicId, externalId)`
   - `page(chapterId, pageNumber)`
   - `online_chapter(comicId, externalId)`

3. **更新插入策略**
   - 使用 `INSERT OR IGNORE` 防止重复

## 常见问题

### Q1: 如何判断漫画类型？

```typescript
import { isOnlineManga, isLocalManga } from '../Framework/Types/MangaTypes';

if (isOnlineManga(manga)) {
  // 在线漫画
  console.log(`图源: ${manga.sourceName}`);
  console.log(`外部ID: ${manga.externalId}`);
} else if (isLocalManga(manga)) {
  // 本地漫画
  console.log(`本地路径: ${manga.localPath}`);
}
```

### Q2: 如何强制刷新数据？

```typescript
const loader = MangaDataLoader.getInstance();

// forceRefresh = true 强制从网络加载
const result = await loader.loadMangaDetail(mangaId, true);
```

### Q3: 如何处理缓存过期？

```typescript
const result = await loader.loadMangaDetail(mangaId);

if (result.needsRefresh) {
  // 显示"数据可能已过期"提示
  // 提供刷新按钮
}
```

### Q4: 旧代码会立即失效吗？

不会。适配器确保向后兼容：

```typescript
// 旧代码仍然可以工作
const comicInfo = await DataManager.getInstance().getComicById(mangaId);

// 但建议迁移到新代码
const result = await MangaDataLoader.getInstance().loadMangaDetail(mangaId);
```

## 迁移检查清单

- [ ] 移除所有通过 `sourceId` 判断类型的代码
- [ ] 使用 `isOnlineManga` / `isLocalManga` 类型守卫
- [ ] 使用 `MangaDataLoader` 加载数据
- [ ] 使用 `sourceName` 而不是 `sourceId` 识别图源
- [ ] 运行数据库迁移脚本
- [ ] 测试本地漫画加载
- [ ] 测试在线漫画加载
- [ ] 测试已下载章节加载
- [ ] 测试未下载章节加载

## 性能优化

### 缓存策略

- **默认缓存时间**: 24小时
- **自动判断**: 缓存未过期时使用缓存
- **手动刷新**: 用户下拉刷新时强制网络加载

### 数据库优化

- **唯一性索引**: 加速查询，防止重复
- **批量插入**: 使用 `INSERT OR IGNORE` 提升性能
- **事务处理**: 确保数据一致性

## 测试建议

### 单元测试

```typescript
// 测试类型转换
test('convertToManga should handle online manga', () => {
  const legacy = { sourceId: 8, externalId: '123' };
  const manga = MangaTypeAdapter.convertToManga(legacy, 'komiic');
  expect(isOnlineManga(manga)).toBe(true);
  expect(manga.sourceName).toBe('komiic');
});

// 测试数据加载
test('loadMangaDetail should use cache when not expired', async () => {
  const result = await loader.loadMangaDetail(mangaId, false);
  expect(result.dataSource).toBe('cache');
});
```

### 集成测试

1. 创建测试漫画（本地和在线）
2. 测试详情页加载
3. 测试阅读器加载
4. 测试刷新功能
5. 测试离线模式

## 回滚方案

如果遇到问题需要回滚：

1. **代码回滚**: Git回退到迁移前的commit
2. **数据库回滚**: 使用备份恢复数据库
3. **渐进式迁移**: 先迁移部分功能，逐步推进

## 支持

如有问题，请查看：
- `REFACTORING_PLAN.md` - 详细的重构计划
- `Framework/Types/MangaTypes.ets` - 类型定义
- `Framework/Managers/MangaDataLoader.ets` - 数据加载器
- `Framework/Adapters/MangaTypeAdapter.ets` - 类型适配器
