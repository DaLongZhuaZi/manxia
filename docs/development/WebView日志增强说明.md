# WebView系统日志增强说明

**日期**: 2025-11-18  
**目的**: 为WebView图源系统添加详细的调试日志，帮助诊断问题

---

## 增强的文件

### 1. MangaSourceConfigParser.ets

**位置**: `Framework/WebView/MangaSourceConfigParser.ets`

#### 新增日志

```typescript
parseConfig(jsonContent: string): ParseResult {
  // ✅ 新增：JSON内容长度
  logger.debug(TAG, `JSON内容长度: ${jsonContent.length}`);
  
  // ✅ 新增：JSON解析成功提示
  logger.debug(TAG, `JSON解析成功，开始验证配置`);
  
  // ✅ 增强：配置验证失败详情
  logger.error(TAG, `配置验证失败: ${validationResult.error}`);
  
  // ✅ 新增：基础配置验证通过
  logger.debug(TAG, '基础配置验证通过');
  
  // ✅ 新增：配置转换完成
  logger.debug(TAG, `配置转换完成，警告数量: ${warnings.length}`);
  
  // ✅ 增强：工作流验证失败详情
  logger.error(TAG, `工作流验证失败: ${workflowValidation.error}`);
  
  // ✅ 新增：工作流验证通过
  logger.debug(TAG, '工作流验证通过');
  
  // ✅ 增强：异常详情和堆栈
  logger.error(TAG, `配置解析异常: ${errorMessage}`);
  logger.debug(TAG, `异常堆栈: ${errorStack}`);
}
```

---

### 2. MangaSourceEngine.ets

**位置**: `Framework/WebView/MangaSourceEngine.ets`

#### loadConfig方法

```typescript
async loadConfig(jsonContent: string): Promise<ParseResult> {
  // ✅ 新增：接收到的JSON长度
  logger.debug(TAG, `接收到的JSON长度: ${jsonContent.length}`);
  
  // ✅ 增强：配置加载成功详情
  logger.info(TAG, `配置加载成功: ${summary.name} v${summary.version}`);
  logger.debug(TAG, `工作流数量: ${summary.workflowCount}, 工作流列表: ${summary.workflows.join(', ')}`);
  
  // ✅ 新增：配置警告
  if (parseResult.warnings && parseResult.warnings.length > 0) {
    logger.warn(TAG, `配置警告: ${parseResult.warnings.join('; ')}`);
  }
  
  // ✅ 增强：配置加载失败详情
  logger.error(TAG, `配置加载失败: ${parseResult.error || '未知错误'}`);
}
```

#### searchManga方法

```typescript
async searchManga(keyword: string, page: number = 1): Promise<EngineResult<SearchResult>> {
  // ✅ 增强：搜索开始信息
  logger.info(TAG, `开始搜索漫画: 关键词="${keyword}", 页码=${page}`);
  
  // ✅ 新增：构建操作序列
  logger.debug(TAG, '构建搜索操作序列');
  logger.debug(TAG, `搜索操作序列包含 ${actions.length} 个操作`);
  
  // ✅ 新增：执行上下文
  logger.debug(TAG, `执行上下文变量: ${JSON.stringify(context.variables)}`);
  
  // ✅ 新增：每个操作的执行日志
  logger.debug(TAG, `执行操作 ${i + 1}/${actions.length}: ${action.type}`);
  logger.debug(TAG, `操作 ${i + 1} 结果: success=${result.success}, hasData=${!!result.data}`);
  
  // ✅ 增强：操作失败详情
  logger.error(TAG, `操作 ${i + 1} 失败: ${result.error}`);
  
  // ✅ 新增：提取数据数量
  logger.debug(TAG, `提取到 ${searchResults.length} 条漫画数据`);
  
  // ✅ 增强：错误详情和堆栈
  logger.error(TAG, `搜索失败: ${errorMessage}`);
  logger.debug(TAG, `错误堆栈: ${errorStack}`);
}
```

---

### 3. SourceDetailPage.ets

**位置**: `pages/SourceDetailPage.ets`

#### loadComicsWithWebView方法

```typescript
private async loadComicsWithWebView(): Promise<ComicInfo[]> {
  // ✅ 增强：引擎未初始化错误
  logger.error(TAG, 'WebView引擎未初始化');
  
  // ✅ 新增：搜索参数详情
  logger.info(TAG, `开始WebView搜索: 关键词="${keyword}", 页码=${this.currentPage}, 标签=${this.currentTab}`);
  
  // ✅ 新增：搜索返回结果
  logger.debug(TAG, `WebView搜索返回: success=${result?.success}, hasData=${!!result?.data}, error=${result?.error}`);
  
  // ✅ 增强：搜索成功详情
  logger.info(TAG, `WebView搜索成功，找到 ${result.data.mangas.length} 条结果，耗时 ${result.duration}ms`);
  logger.debug(TAG, `转换后的漫画数量: ${converted.length}`);
  
  // ✅ 增强：搜索失败详情
  logger.error(TAG, `WebView搜索失败: ${errorMsg}`);
  
  // ✅ 增强：异常详情和堆栈
  logger.error(TAG, `WebView加载异常: ${errorMsg}`);
  logger.debug(TAG, `异常堆栈: ${errorStack}`);
}
```

---

## 日志级别说明

### INFO级别
- 主要流程节点（开始、完成）
- 成功的操作结果
- 重要的状态变化

### DEBUG级别
- 详细的执行步骤
- 中间数据和变量
- 操作序列和上下文
- 堆栈跟踪信息

### ERROR级别
- 失败的操作
- 异常情况
- 验证错误

### WARN级别
- 配置警告
- 非致命问题

---

## 预期的完整日志流程

### 成功场景

```
[INFO] [SourceDetailPage] 检测到WebView类型图源
[INFO] [SourceDetailPage] 开始初始化WebView引擎
[INFO] [MangaSourceEngine] 加载漫画图源配置
[DEBUG] [MangaSourceEngine] 接收到的JSON长度: 5879
[INFO] [MangaSourceConfigParser] 开始解析漫画图源配置
[DEBUG] [MangaSourceConfigParser] JSON内容长度: 5879
[DEBUG] [MangaSourceConfigParser] JSON解析成功，开始验证配置
[DEBUG] [MangaSourceConfigParser] 基础配置验证通过
[DEBUG] [MangaSourceConfigParser] 配置转换完成，警告数量: 0
[DEBUG] [MangaSourceConfigParser] 工作流验证通过
[INFO] [MangaSourceConfigParser] 漫画图源配置解析完成
[INFO] [MangaSourceEngine] 配置加载成功: Komiic v2.0.0
[DEBUG] [MangaSourceEngine] 工作流数量: 5, 工作流列表: search, getMangaDetail, getChapterList, getPageList, getImageUrl
[INFO] [SourceDetailPage] WebView引擎初始化成功
[INFO] [SourceDetailPage] 使用WebView系统加载漫画列表
[INFO] [SourceDetailPage] 开始WebView搜索: 关键词="", 页码=1, 标签=popular
[INFO] [MangaSourceEngine] 开始搜索漫画: 关键词="", 页码=1
[DEBUG] [MangaSourceEngine] 构建搜索操作序列
[DEBUG] [MangaSourceEngine] 搜索操作序列包含 4 个操作
[DEBUG] [MangaSourceEngine] 执行上下文变量: {"page":"1"}
[DEBUG] [MangaSourceEngine] 执行操作 1/4: navigate
[DEBUG] [MangaSourceEngine] 操作 1 结果: success=true, hasData=false
[DEBUG] [MangaSourceEngine] 执行操作 2/4: wait
[DEBUG] [MangaSourceEngine] 操作 2 结果: success=true, hasData=false
[DEBUG] [MangaSourceEngine] 执行操作 3/4: script
[DEBUG] [MangaSourceEngine] 操作 3 结果: success=true, hasData=true
[DEBUG] [MangaSourceEngine] 执行操作 4/4: extract
[DEBUG] [MangaSourceEngine] 操作 4 结果: success=true, hasData=true
[DEBUG] [MangaSourceEngine] 提取到 20 条漫画数据
[INFO] [MangaSourceEngine] 搜索完成，找到 20 个结果，耗时 2345ms
[DEBUG] [SourceDetailPage] WebView搜索返回: success=true, hasData=true, error=undefined
[INFO] [SourceDetailPage] WebView搜索成功，找到 20 条结果，耗时 2345ms
[DEBUG] [SourceDetailPage] 转换后的漫画数量: 20
```

### 失败场景（配置解析失败）

```
[INFO] [SourceDetailPage] 检测到WebView类型图源
[INFO] [SourceDetailPage] 开始初始化WebView引擎
[INFO] [MangaSourceEngine] 加载漫画图源配置
[DEBUG] [MangaSourceEngine] 接收到的JSON长度: 5879
[INFO] [MangaSourceConfigParser] 开始解析漫画图源配置
[DEBUG] [MangaSourceConfigParser] JSON内容长度: 5879
[DEBUG] [MangaSourceConfigParser] JSON解析成功，开始验证配置
[DEBUG] [MangaSourceConfigParser] 基础配置验证通过
[DEBUG] [MangaSourceConfigParser] 配置转换完成，警告数量: 0
[ERROR] [MangaSourceConfigParser] 工作流验证失败: 缺少必需的工作流: getImageUrl
[ERROR] [MangaSourceEngine] 配置加载失败: 缺少必需的工作流: getImageUrl
[INFO] [SourceDetailPage] WebView引擎初始化成功
[INFO] [SourceDetailPage] 使用WebView系统加载漫画列表
[ERROR] [SourceDetailPage] WebView加载失败
```

### 失败场景（操作执行失败）

```
[INFO] [MangaSourceEngine] 开始搜索漫画: 关键词="", 页码=1
[DEBUG] [MangaSourceEngine] 构建搜索操作序列
[DEBUG] [MangaSourceEngine] 搜索操作序列包含 4 个操作
[DEBUG] [MangaSourceEngine] 执行上下文变量: {"page":"1"}
[DEBUG] [MangaSourceEngine] 执行操作 1/4: navigate
[DEBUG] [MangaSourceEngine] 操作 1 结果: success=true, hasData=false
[DEBUG] [MangaSourceEngine] 执行操作 2/4: wait
[DEBUG] [MangaSourceEngine] 操作 2 结果: success=true, hasData=false
[DEBUG] [MangaSourceEngine] 执行操作 3/4: script
[DEBUG] [MangaSourceEngine] 操作 3 结果: success=false, hasData=false
[ERROR] [MangaSourceEngine] 操作 3 失败: Script execution failed: ReferenceError: fetch is not defined
[ERROR] [MangaSourceEngine] 搜索失败: 搜索操作失败: Script execution failed: ReferenceError: fetch is not defined
[DEBUG] [MangaSourceEngine] 错误堆栈: Error: 搜索操作失败...
[DEBUG] [SourceDetailPage] WebView搜索返回: success=false, hasData=false, error=搜索操作失败...
[ERROR] [SourceDetailPage] WebView搜索失败: 搜索操作失败...
```

---

## 使用建议

### 1. 开发调试
启用DEBUG级别日志，查看完整的执行流程

### 2. 生产环境
只启用INFO和ERROR级别，减少日志量

### 3. 问题诊断
- 查看ERROR日志定位失败点
- 查看DEBUG日志了解详细流程
- 查看堆栈跟踪定位代码位置

---

## 下一步

现在重新运行应用，查看详细的日志输出，可以准确定位：
1. 配置解析在哪一步失败
2. 哪个工作流验证失败
3. 哪个操作执行失败
4. 具体的错误信息和堆栈

---

**文档创建时间**: 2025-11-18  
**作者**: Cascade AI
