# WebView系统集成测试指南

## ✅ 已完成的修复

### 1. 类型错误修复
- ✅ 修复`MangaMetadata`接口字段（移除`tags`，添加`themes`、`demographics`等）
- ✅ 修复`MangaSourceInfo`接口（添加`sourceLanguage`、`requiresLogin`、`apiVersion`）
- ✅ 修复`MangaChapter`接口（使用`publishDate`而不是`publishedAt`）
- ✅ 修复`DownloadStatus`枚举（使用`PENDING`而不是`NOT_DOWNLOADED`）
- ✅ 修复章节过滤方法调用（直接更新`filteredChapters`和`chapterDataSource`）

### 2. 数据转换优化
- ✅ 简化`convertWebViewChapterInfoToMangaChapter`方法
- ✅ 移除不必要的中间转换接口
- ✅ 使用正确的字段名和类型

### 3. 参数传递链路
```
SourceDetailPage.openComicDetail()
  ↓ 传递参数
{
  sourceId: 6,
  comicId: "466",
  title: "膽大黨 (超自然武裝噹噠噹)"
}
  ↓ NavDestination.onReady()
MangaDetailPage.pageParams = context.pathInfo.param
  ↓ loadMangaData()
检测sourceId → 调用isWebViewSource() → loadMangaDataWithWebView()
```

## 🧪 测试步骤

### 测试1: 图源列表加载
**目标**: 验证WebView图源能正确显示漫画列表

1. 启动应用
2. 进入"图源"页面
3. 点击"Komiic"图源
4. **预期结果**:
   - ✅ 显示20条漫画
   - ✅ 每条漫画有标题、状态、浏览量、收藏数
   - ⚠️ 封面图片可能为空（待修复）

**日志关键词**:
```
[SourceDetailPage] WebView搜索成功，找到 20 条结果
[MangaSourceEngine] 转换MangaInfo: id="/comic/466", title="膽大黨..."
[SourceDetailPage] 转换漫画: id="/comic/466" -> "466"
```

### 测试2: 漫画详情页加载（新增）
**目标**: 验证点击漫画后能正确加载详情

1. 在图源列表页点击任意漫画
2. **预期结果**:
   - ✅ 跳转到漫画详情页
   - ✅ 显示漫画标题、描述、作者
   - ✅ 显示章节列表
   - ✅ 封面图片加载（如果有）

**日志关键词**:
```
[MangaDetailPage] 页面参数: {"sourceId":6,"comicId":"466","title":"..."}
[MangaDetailPage] 图源ID: 6, 是否WebView源: true
[MangaDetailPage] 使用WebView系统加载漫画数据
[WebViewSourceManager] 使用缓存的MangaSourceEngine: 6
[MangaDetailPage] 漫画详情获取成功: 膽大黨...
[MangaDetailPage] 章节列表获取成功，共XX章
[MangaDetailPage] WebView漫画数据加载完成
```

### 测试3: 章节列表显示
**目标**: 验证章节列表正确显示

1. 在详情页查看章节列表
2. **预期结果**:
   - ✅ 显示所有章节
   - ✅ 章节标题正确
   - ✅ 章节编号正确
   - ✅ 可以滚动浏览

**日志关键词**:
```
[MangaDetailPage] 转换Manga: id="466", title="膽大黨..."
[MangaDetailPage] 更新过滤后的章节列表
```

### 测试4: 错误处理
**目标**: 验证错误情况的处理

1. 断开网络
2. 尝试加载漫画详情
3. **预期结果**:
   - ✅ 显示错误提示
   - ✅ 提供重试按钮
   - ✅ 不会崩溃

## 🐛 已知问题

### 1. 封面图片为空
**状态**: 部分修复，待验证

**原因**: 
- 图片使用懒加载
- 等待时间可能不足
- 选择器可能需要调整

**解决方案**:
- 已增加等待时间到5秒
- 已添加调试日志
- 需要查看WebView控制台输出

**验证方法**:
查看日志中的：
```
找到 20 个项目
第一个项目HTML: <a class="ComicCard"...
图片元素: [object HTMLImageElement]
图片src: https://public.komiic.com/comics/.../cover.jpg
```

### 2. 章节点击（未实现）
**状态**: 待实现（Phase 3）

**需要**:
- MangaReaderPage集成WebView
- 实现`getPageList()`和`getImageUrl()`调用
- 图片加载和缓存

## 📊 数据流程图

```
┌─────────────────────────────────────────────────────────┐
│                    用户操作流程                          │
└─────────────────────────────────────────────────────────┘
                            │
                            ▼
┌─────────────────────────────────────────────────────────┐
│  1. SourceDetailPage: 显示漫画列表                       │
│     - searchManga("", 1)                                │
│     - 显示20条漫画                                       │
└─────────────────────────────────────────────────────────┘
                            │
                            ▼ 点击漫画
┌─────────────────────────────────────────────────────────┐
│  2. 参数传递                                             │
│     {sourceId: 6, comicId: "466", title: "..."}        │
└─────────────────────────────────────────────────────────┘
                            │
                            ▼
┌─────────────────────────────────────────────────────────┐
│  3. MangaDetailPage: 加载详情                           │
│     - 检测WebView源                                      │
│     - getMangaEngine(6)                                 │
│     - getMangaDetail("466")                             │
│     - getChapterList("466")                             │
│     - 转换数据并显示                                     │
└─────────────────────────────────────────────────────────┘
                            │
                            ▼ 点击章节（待实现）
┌─────────────────────────────────────────────────────────┐
│  4. MangaReaderPage: 阅读漫画                           │
│     - getPageList(chapterId)                            │
│     - getImageUrl(pageUrl) for each page                │
│     - 显示图片                                           │
└─────────────────────────────────────────────────────────┘
```

## 🔍 调试技巧

### 1. 查看WebView控制台输出
在`MangaSourceActionEngine.ets`的`buildMultipleItemsScript`方法中已添加：
```javascript
console.log('找到 ' + items.length + ' 个项目');
console.log('第一个项目HTML:', firstItem.outerHTML.substring(0, 500));
console.log('图片元素:', imgEl);
console.log('图片src:', imgEl ? imgEl.getAttribute('src') : 'null');
```

### 2. 查看数据转换日志
```
[MangaSourceEngine] 转换MangaInfo: id="...", title="...", cover="..."
[SourceDetailPage] 转换漫画: id="..." -> "...", title="...", cover="..."
[MangaDetailPage] 转换Manga: id="...", title="...", cover="..."
```

### 3. 查看引擎缓存
```
[WebViewSourceManager] 使用缓存的MangaSourceEngine: 6
[WebViewSourceManager] 创建新的MangaSourceEngine: 6
```

## ✅ 验收标准

### Phase 2完成标准
- [x] 类型错误全部修复
- [x] 参数传递链路正确
- [ ] 详情页能正确加载（待测试）
- [ ] 章节列表能正确显示（待测试）
- [ ] 封面图片能正确显示（待验证）

### Phase 3完成标准（待实施）
- [ ] 点击章节能进入阅读器
- [ ] 阅读器能加载图片列表
- [ ] 图片能正确显示
- [ ] 图片能缓存到本地

## 📝 下一步计划

1. **立即测试** (15分钟)
   - 运行应用
   - 测试详情页加载
   - 查看日志输出
   - 验证封面图片

2. **修复问题** (30分钟)
   - 根据测试结果调整
   - 修复发现的bug
   - 优化用户体验

3. **实施Phase 3** (2-3小时)
   - MangaReaderPage集成
   - 图片加载实现
   - 缓存机制实现

4. **完整测试** (1小时)
   - 端到端测试
   - 性能测试
   - 用户体验测试

## 🎉 预期最终效果

用户可以：
1. ✅ 浏览Komiic图源的漫画列表
2. ✅ 点击漫画查看详情和章节
3. ⏳ 点击章节在线阅读
4. ⏳ 图片自动缓存

完整的在线漫画阅读体验！🚀
