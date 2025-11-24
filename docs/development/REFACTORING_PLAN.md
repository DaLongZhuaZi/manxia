# 漫画系统重构计划

## 问题总结

当前漫画系统存在以下严重架构问题：

### 1. 类型混淆
- **问题**：在线漫画加入书库后被错误识别为本地漫画
- **根因**：没有明确的 `sourceType` 字段区分本地和在线漫画
- **影响**：导致在线漫画无法正确请求图片，Cookie无法正确应用

### 2. 数据加载策略混乱
- **问题**：没有"优先使用缓存，按需请求"的清晰策略
- **根因**：每次都尝试从网络加载，或者完全依赖缓存
- **影响**：性能差，用户体验不佳

### 3. 图源识别错误
- **问题**：使用图源ID而不是name来识别图源
- **根因**：ID可能在不同环境下不一致
- **影响**：图源匹配失败，无法正确加载数据

### 4. 章节重复
- **问题**：数据库中存在重复章节
- **根因**：缺少唯一性约束
- **影响**：用户看到重复内容，数据不一致

## 重构方案

### 阶段一：类型系统重构 ✅

**已完成的工作：**

1. **创建新的类型系统** (`MangaTypes.ets`)
   - 定义 `MangaSourceType` 枚举：明确区分 `LOCAL` 和 `ONLINE`
   - 定义 `LocalManga` 和 `OnlineManga` 接口
   - 定义 `LocalChapter` 和 `OnlineChapter` 接口
   - 提供类型守卫函数

2. **创建类型适配器** (`MangaTypeAdapter.ets`)
   - 将旧的数据库类型转换为新类型
   - 将新类型转换回数据库类型
   - 处理标签解析、下载状态等

3. **创建数据加载器** (`MangaDataLoader.ets`)
   - 实现"优先缓存，按需网络"策略
   - 自动判断缓存是否过期
   - 支持强制刷新

### 阶段二：数据库层修复 ✅

**已完成的工作：**

1. **添加唯一性约束** (`DatabaseSchema.ets`)
   - chapter表：`UNIQUE(comicId, externalId)`
   - page表：`UNIQUE(chapterId, pageNumber)`
   - online_comic_info表：`UNIQUE(sourceId, externalId)`
   - online_chapter表：`UNIQUE(comicId, externalId)`

2. **增强批量插入** (`DatabaseManager.ets`)
   - 添加冲突解决策略参数
   - 支持 `REPLACE`、`IGNORE`、`FAIL` 三种策略

3. **创建迁移脚本** (`MigrationScripts.ets`)
   - 清理现有重复数据
   - 创建唯一性索引

### 阶段三：DataManager扩展 ⏳

**需要完成的工作：**

1. **添加缺失的查询方法**
   ```typescript
   // 在 DataManager.ets 中添加
   async getChaptersByMangaId(mangaId: string): Promise<ChapterInfo[]>
   async getPagesByChapterId(chapterId: string): Promise<PageInfo[]>
   ```

2. **添加图源名称查询**
   ```typescript
   async getSourceByName(name: string): Promise<ComicSource | null>
   ```

3. **添加 sourceType 字段到数据库**
   - 修改 `comic_info` 表schema
   - 添加迁移脚本更新现有数据

### 阶段四：UI层重构 ⏳

**需要完成的工作：**

1. **MangaDetailPage 重构**
   - 使用 `MangaDataLoader` 加载数据
   - 优先显示缓存，后台刷新
   - 使用图源name而不是ID

2. **MangaReaderPage 重构**
   - 使用新的类型系统
   - 根据 `sourceType` 判断加载策略
   - 优先使用本地图片，按需网络加载

3. **参数传递修复**
   - 使用 `sourceName` 而不是 `sourceId`
   - 传递完整的 `Manga` 对象而不是分散的参数

## 实施步骤

### 立即执行（高优先级）

1. **在 DataManager 中添加缺失方法**
   ```typescript
   // f:/DevEcoStudioProject/manxia/entry/src/main/ets/Framework/Data/DataManager.ets
   
   public async getChaptersByMangaId(mangaId: string): Promise<ChapterInfo[]> {
     const sql = 'SELECT * FROM chapter WHERE comicId = ? ORDER BY chapterNumber ASC';
     const result = await this.databaseManager.querySql(sql, [mangaId]);
     return result.map(r => this.convertToChapterInfo(r));
   }
   
   public async getPagesByChapterId(chapterId: string): Promise<PageInfo[]> {
     return await this.getChapterPages(chapterId); // 已存在
   }
   
   public async getSourceByName(name: string): Promise<ComicSource | null> {
     const sources = await this.getAllComicSources();
     return sources.find(s => s.name === name) || null;
   }
   ```

2. **修复 MangaDetailPage 的图源识别**
   - 将所有使用 `sourceId` 的地方改为使用 `sourceName`
   - 在需要时通过 `getSourceByName` 获取 `sourceId`

3. **修复 MangaReaderPage 的类型判断**
   - 使用 `isOnlineManga` 判断而不是检查 `sourceId`
   - 使用 `isOnlineChapter` 判断而不是检查 `externalId`

### 后续优化（中优先级）

1. **数据库schema升级**
   - 添加 `sourceType` 字段
   - 运行迁移脚本

2. **完善网络加载逻辑**
   - 在 `MangaDataLoader` 中实现真正的网络请求
   - 集成 `MangaSourceEngine`

3. **添加缓存管理**
   - 缓存过期策略
   - 手动清理缓存功能

### 长期改进（低优先级）

1. **性能优化**
   - 章节列表虚拟滚动
   - 图片懒加载和预加载

2. **用户体验**
   - 下拉刷新
   - 加载状态指示器
   - 离线模式

## 注意事项

1. **向后兼容**
   - 使用适配器保证旧代码继续工作
   - 逐步迁移而不是一次性重写

2. **数据安全**
   - 运行迁移脚本前备份数据库
   - 提供回滚机制

3. **测试**
   - 测试本地漫画加载
   - 测试在线漫画加载
   - 测试已下载章节加载
   - 测试未下载章节加载

## 当前状态

- ✅ 新类型系统已创建
- ✅ 类型适配器已创建
- ✅ 数据加载器框架已创建
- ✅ 数据库唯一性约束已添加
- ⏳ DataManager 方法需要补充
- ⏳ UI层需要重构
- ⏳ 网络加载逻辑待实现

## 下一步行动

1. 在 `DataManager.ets` 中添加 `getChaptersByMangaId` 方法
2. 修复 `MangaDataLoader` 中的类型错误
3. 更新 `MangaDetailPage` 使用新的数据加载器
4. 更新 `MangaReaderPage` 使用新的类型系统
