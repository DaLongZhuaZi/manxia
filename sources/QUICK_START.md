# 图源系统快速开始指南

## 1. 导入Komiic图源

### 方法1：通过代码导入

```typescript
import { SourceManager } from '../Framework/Source/SourceManager';
import { fileIo } from '@kit.CoreFileKit';

// 读取komiic.json文件
const filePath = '/path/to/sources/komiic.json';
const file = fileIo.openSync(filePath, fileIo.OpenMode.READ_ONLY);
const buffer = new ArrayBuffer(1024 * 1024);
const readLen = fileIo.readSync(file.fd, buffer);
fileIo.closeSync(file);

const jsonContent = String.fromCharCode.apply(null, 
  Array.from(new Uint8Array(buffer, 0, readLen)));

// 导入图源
const manager = SourceManager.getInstance();
const result = await manager.importFromJSON(jsonContent);

if (result.success) {
  console.log(`✅ 图源导入成功: ${result.sourceName}`);
  console.log(`图源ID: ${result.sourceId}`);
} else {
  console.error(`❌ 导入失败: ${result.error}`);
}
```

### 方法2：通过UI导入（待实现）

在图源管理页面点击"导入"按钮，选择`komiic.json`文件。

## 2. 测试图源

```typescript
import { SourceManager } from '../Framework/Source/SourceManager';

const manager = SourceManager.getInstance();

// 获取所有图源
const sources = await manager.getAllSources();
console.log(`共有${sources.length}个图源`);

// 测试第一个图源
if (sources.length > 0) {
  const sourceId = sources[0].id;
  const testResult = await manager.testSource(sourceId);
  
  console.log(`测试结果: ${testResult.success ? '✅ 通过' : '❌ 失败'}`);
  console.log(`通过: ${testResult.passedTests}/${testResult.totalTests}`);
  console.log(`耗时: ${testResult.duration}ms`);
  
  // 打印详细报告
  const report = manager.generateTestReport(testResult);
  console.log(report);
}
```

## 3. 使用图源搜索漫画

```typescript
import { SourceManager } from '../Framework/Source/SourceManager';

const manager = SourceManager.getInstance();

// 获取启用的图源
const sources = await manager.getEnabledSources();

if (sources.length > 0) {
  const sourceId = sources[0].id;
  
  // 搜索漫画
  const comics = await manager.search(sourceId, "海贼王", 1, 20);
  
  console.log(`找到${comics.length}个结果:`);
  comics.forEach((comic, index) => {
    console.log(`${index + 1}. ${comic.title} - ${comic.author}`);
  });
}
```

## 4. 获取漫画详情

```typescript
import { SourceManager } from '../Framework/Source/SourceManager';

const manager = SourceManager.getInstance();
const sourceId = 1; // 图源ID
const comicId = "123"; // 漫画ID

// 获取详情
const detail = await manager.getDetail(sourceId, comicId);

console.log(`标题: ${detail.title}`);
console.log(`作者: ${detail.author}`);
console.log(`描述: ${detail.description}`);
console.log(`状态: ${detail.status}`);
console.log(`标签: ${detail.tags?.join(', ')}`);

// 章节列表
if (detail.chapters) {
  console.log(`\n章节列表 (${detail.chapters.length}章):`);
  detail.chapters.forEach((chapter, index) => {
    console.log(`${index + 1}. ${chapter.title}`);
  });
}
```

## 5. 获取章节图片

```typescript
import { SourceManager } from '../Framework/Source/SourceManager';

const manager = SourceManager.getInstance();
const sourceId = 1;
const chapterId = "456";

// 获取图片列表
const pages = await manager.getPages(sourceId, chapterId);

console.log(`共${pages.length}页:`);
pages.forEach((page, index) => {
  console.log(`第${index + 1}页: ${page.url}`);
  if (page.width && page.height) {
    console.log(`  尺寸: ${page.width}x${page.height}`);
  }
});
```

## 6. 管理图源

```typescript
import { SourceManager } from '../Framework/Source/SourceManager';

const manager = SourceManager.getInstance();

// 获取所有图源
const sources = await manager.getAllSources();

// 启用/禁用图源
await manager.enableSource(sourceId);
await manager.disableSource(sourceId);

// 更新优先级
await manager.updatePriority(sourceId, 10);

// 删除图源
await manager.deleteSource(sourceId);

// 清除缓存
manager.clearCache();
```

## 7. 在UI中集成

### 在图源管理页面

```typescript
import { SourceManager, SourceInfo } from '../Framework/Source/SourceManager';

@Component
export struct SourceManagementPage {
  private sourceManager: SourceManager = SourceManager.getInstance();
  @State sourceList: SourceInfo[] = [];
  @State isLoading: boolean = false;

  async aboutToAppear() {
    await this.loadSources();
  }

  async loadSources() {
    this.isLoading = true;
    this.sourceList = await this.sourceManager.getAllSources();
    this.isLoading = false;
  }

  async onImport(jsonContent: string) {
    const result = await this.sourceManager.importFromJSON(jsonContent);
    if (result.success) {
      // 显示成功提示
      await this.loadSources();
    } else {
      // 显示错误提示
    }
  }

  async onTest(sourceId: number) {
    const result = await this.sourceManager.testSource(sourceId);
    const report = this.sourceManager.generateTestReport(result);
    // 显示测试报告
  }

  async onToggle(sourceId: number, enabled: boolean) {
    if (enabled) {
      await this.sourceManager.enableSource(sourceId);
    } else {
      await this.sourceManager.disableSource(sourceId);
    }
  }
}
```

### 在搜索页面

```typescript
import { SourceManager, ComicInfo } from '../Framework/Source/SourceManager';

@Component
export struct SearchPage {
  private sourceManager: SourceManager = SourceManager.getInstance();
  @State searchResults: ComicInfo[] = [];
  @State keyword: string = '';

  async onSearch() {
    const sources = await this.sourceManager.getEnabledSources();
    if (sources.length === 0) {
      // 提示：没有启用的图源
      return;
    }

    // 使用第一个图源搜索
    const sourceId = sources[0].id;
    this.searchResults = await this.sourceManager.search(
      sourceId, 
      this.keyword, 
      1, 
      20
    );
  }
}
```

## 8. 错误处理

```typescript
import { SourceManager } from '../Framework/Source/SourceManager';

const manager = SourceManager.getInstance();

try {
  const comics = await manager.search(sourceId, keyword, 1, 20);
  // 处理结果
} catch (error) {
  console.error('搜索失败:', error);
  
  // 根据错误类型处理
  if (error.message.includes('图源不存在')) {
    // 图源已被删除
  } else if (error.message.includes('网络')) {
    // 网络错误
  } else {
    // 其他错误
  }
}
```

## 9. 性能优化建议

### 使用缓存
```typescript
// 图源列表缓存
private sourcesCache: SourceInfo[] | null = null;
private cacheTime: number = 0;
private CACHE_DURATION = 5 * 60 * 1000; // 5分钟

async getSources(): Promise<SourceInfo[]> {
  const now = Date.now();
  if (this.sourcesCache && now - this.cacheTime < this.CACHE_DURATION) {
    return this.sourcesCache;
  }
  
  this.sourcesCache = await this.sourceManager.getAllSources();
  this.cacheTime = now;
  return this.sourcesCache;
}
```

### 并发控制
```typescript
// 限制同时搜索的图源数量
const sources = await manager.getEnabledSources();
const maxConcurrent = 3;

for (let i = 0; i < sources.length; i += maxConcurrent) {
  const batch = sources.slice(i, i + maxConcurrent);
  const results = await Promise.all(
    batch.map(source => manager.search(source.id, keyword, 1, 20))
  );
  // 处理结果
}
```

## 10. 调试技巧

### 启用详细日志
```typescript
import { logger } from '../Utils/Logger';

// 在开发环境启用调试日志
logger.setLevel('debug');
```

### 查看图源配置
```typescript
import { DataManager } from '../Framework/Data/DataManager';

const dataManager = DataManager.getInstance();
const config = await dataManager.getSourceConfig(sourceId);
console.log('图源配置:', JSON.stringify(config, null, 2));
```

### 测试JSONPath表达式
```typescript
import { jsonPath } from '../Framework/Utils/JSONPathParser';

const data = { /* 响应数据 */ };
const result = jsonPath(data, '$.data.items[0].title');
console.log('解析结果:', result);
```

## 常见问题

### Q: 导入图源失败？
A: 检查JSON格式是否正确，必需字段是否完整。

### Q: 搜索没有结果？
A: 检查图源是否启用，网络是否正常，关键词是否正确。

### Q: 图片加载失败？
A: 检查imageHeaders配置，确保Referer等请求头正确。

### Q: 如何调试图源？
A: 使用测试功能，查看详细的错误信息和日志。

---

**提示**: 首次使用建议先导入并测试Komiic图源，确保系统正常工作。
