# 数据管理功能 API 参考文档

## 概述

本文档提供数据管理功能的完整API参考，包括所有公共接口、方法签名、参数说明和使用示例。

## 目录

1. [ComicInfoParser API](#comicinfoparserapı)
2. [CompressionUtils API](#compressionutilsapi)
3. [DataManagementTest API](#datamanagementtestapi)
4. [UIFunctionalityTest API](#uifunctionalitytestapi)
5. [数据接口定义](#数据接口定义)
6. [错误类型定义](#错误类型定义)
7. [使用示例](#使用示例)

---

## ComicInfoParser API

### 类: ComicInfoParser

漫画信息XML解析器，用于解析ComicInfo.xml文件并转换为TypeScript对象。

#### 构造函数

```typescript
constructor()
```

创建ComicInfoParser实例。

**示例:**
```typescript
const parser = new ComicInfoParser();
```

#### 方法

##### parseXmlString()

```typescript
parseXmlString(xmlString: string): ComicInfo
```

解析XML字符串并返回ComicInfo对象。

**参数:**
- `xmlString` (string): 要解析的XML字符串

**返回值:**
- `ComicInfo`: 解析后的漫画信息对象

**抛出异常:**
- `Error`: XML格式错误或解析失败时抛出

**示例:**
```typescript
const xmlContent = `
<?xml version="1.0"?>
<ComicInfo>
  <Title>示例漫画</Title>
  <Series>示例系列</Series>
  <Number>1</Number>
  <Writer>作者名</Writer>
</ComicInfo>
`;

try {
  const comicInfo = parser.parseXmlString(xmlContent);
  console.log('解析成功:', comicInfo.title);
} catch (error) {
  console.error('解析失败:', error.message);
}
```

#### 静态方法

##### validateComicInfo()

```typescript
static validateComicInfo(comicInfo: ComicInfo): ValidationResult
```

验证ComicInfo对象的有效性。

**参数:**
- `comicInfo` (ComicInfo): 要验证的漫画信息对象

**返回值:**
- `ValidationResult`: 验证结果对象

**示例:**
```typescript
const result = ComicInfoParser.validateComicInfo(comicInfo);
if (!result.isValid) {
  console.error('验证失败:', result.errors);
}
```

##### createDefaultComicInfo()

```typescript
static createDefaultComicInfo(): ComicInfo
```

创建具有默认值的ComicInfo对象。

**返回值:**
- `ComicInfo`: 默认的漫画信息对象

**示例:**
```typescript
const defaultInfo = ComicInfoParser.createDefaultComicInfo();
console.log('默认标题:', defaultInfo.title);
```

---

## CompressionUtils API

### 类: CompressionUtils

压缩文件处理工具，支持ZIP/CBZ文件的解压缩和文件管理。

#### 构造函数

```typescript
constructor()
```

创建CompressionUtils实例。

**示例:**
```typescript
const compressionUtils = new CompressionUtils();
```

#### 方法

##### extractArchive()

```typescript
async extractArchive(archivePath: string, options?: ExtractionOptions): Promise<ExtractionResult>
```

解压缩指定的压缩文件。

**参数:**
- `archivePath` (string): 压缩文件的完整路径
- `options` (ExtractionOptions, 可选): 解压选项

**返回值:**
- `Promise<ExtractionResult>`: 解压结果对象

**示例:**
```typescript
const options: ExtractionOptions = {
  targetDirectory: '/tmp/extract',
  overwrite: true,
  maxFileSize: 100 * 1024 * 1024 // 100MB
};

try {
  const result = await compressionUtils.extractArchive('/path/to/comic.cbz', options);
  if (result.success) {
    console.log('解压成功:', result.extractedPath);
    console.log('文件数量:', result.fileCount);
  } else {
    console.error('解压失败:', result.error);
  }
} catch (error) {
  console.error('操作异常:', error.message);
}
```

##### extractAndFindComicInfo()

```typescript
async extractAndFindComicInfo(archivePath: string): Promise<{result: ExtractionResult, comicInfoPath?: string}>
```

解压缩文件并查找ComicInfo.xml文件。

**参数:**
- `archivePath` (string): 压缩文件的完整路径

**返回值:**
- `Promise<{result: ExtractionResult, comicInfoPath?: string}>`: 包含解压结果和ComicInfo.xml路径的对象

**示例:**
```typescript
try {
  const { result, comicInfoPath } = await compressionUtils.extractAndFindComicInfo('/path/to/comic.cbz');
  
  if (result.success && comicInfoPath) {
    console.log('找到ComicInfo.xml:', comicInfoPath);
    // 读取并解析ComicInfo.xml
  } else {
    console.log('未找到ComicInfo.xml文件');
  }
} catch (error) {
  console.error('操作失败:', error.message);
}
```

##### cleanupDirectory()

```typescript
async cleanupDirectory(directory: string): Promise<void>
```

清理指定目录及其所有内容。

**参数:**
- `directory` (string): 要清理的目录路径

**返回值:**
- `Promise<void>`: 无返回值

**示例:**
```typescript
try {
  await compressionUtils.cleanupDirectory('/tmp/extract');
  console.log('目录清理完成');
} catch (error) {
  console.error('清理失败:', error.message);
}
```

---

## DataManagementTest API

### 类: DataManagementTest

数据管理功能测试工具，提供各种测试方法验证系统功能。

#### 构造函数

```typescript
constructor(dataManager: DataManager)
```

创建DataManagementTest实例。

**参数:**
- `dataManager` (DataManager): 数据管理器实例

**示例:**
```typescript
const testRunner = new DataManagementTest(dataManager);
```

#### 方法

##### runAllTests()

```typescript
async runAllTests(): Promise<boolean>
```

运行所有基础功能测试。

**返回值:**
- `Promise<boolean>`: 所有测试是否通过

**示例:**
```typescript
const allPassed = await testRunner.runAllTests();
if (allPassed) {
  console.log('所有测试通过');
} else {
  console.log('部分测试失败');
}
```

##### testCompleteImportFlow()

```typescript
async testCompleteImportFlow(): Promise<boolean>
```

测试完整的导入流程。

**返回值:**
- `Promise<boolean>`: 测试是否通过

**示例:**
```typescript
const flowTestPassed = await testRunner.testCompleteImportFlow();
console.log('完整流程测试结果:', flowTestPassed ? '通过' : '失败');
```

#### 静态方法

##### runDataManagementTests()

```typescript
static async runDataManagementTests(dataManager: DataManager): Promise<string>
```

运行数据管理测试并返回结果报告。

**参数:**
- `dataManager` (DataManager): 数据管理器实例

**返回值:**
- `Promise<string>`: 测试结果报告

**示例:**
```typescript
const report = await DataManagementTest.runDataManagementTests(dataManager);
console.log('测试报告:\n', report);
```

##### runCompleteImportFlowTest()

```typescript
static async runCompleteImportFlowTest(dataManager: DataManager): Promise<string>
```

运行完整导入流程测试并返回结果报告。

**参数:**
- `dataManager` (DataManager): 数据管理器实例

**返回值:**
- `Promise<string>`: 测试结果报告

**示例:**
```typescript
const flowReport = await DataManagementTest.runCompleteImportFlowTest(dataManager);
console.log('流程测试报告:\n', flowReport);
```

---

## UIFunctionalityTest API

### 类: UIFunctionalityTest

UI功能测试工具，用于验证用户界面的各项功能。

#### 静态方法

##### runUIFunctionalityTests()

```typescript
static async runUIFunctionalityTests(): Promise<UITestResult[]>
```

运行所有UI功能测试。

**返回值:**
- `Promise<UITestResult[]>`: UI测试结果数组

**示例:**
```typescript
const results = await UIFunctionalityTest.runUIFunctionalityTests();
results.forEach(result => {
  console.log(`${result.testName}: ${result.success ? '通过' : '失败'}`);
  console.log(`消息: ${result.message}`);
});
```

##### generateUITestReport()

```typescript
static generateUITestReport(results: UITestResult[]): string
```

生成UI测试报告。

**参数:**
- `results` (UITestResult[]): UI测试结果数组

**返回值:**
- `string`: 格式化的测试报告

**示例:**
```typescript
const results = await UIFunctionalityTest.runUIFunctionalityTests();
const report = UIFunctionalityTest.generateUITestReport(results);
console.log('UI测试报告:\n', report);
```

---

## 数据接口定义

### ComicInfo

漫画信息接口，包含从ComicInfo.xml解析的所有字段。

```typescript
interface ComicInfo {
  title?: string;           // 漫画标题
  series?: string;          // 系列名称
  number?: number;          // 章节号
  summary?: string;         // 内容摘要
  writer?: string;          // 作者
  genre?: string;           // 类型/分类
  web?: string;             // 官方网站
  publishingStatus?: string; // 发布状态
  source?: string;          // 来源
  year?: number;            // 发布年份
  month?: number;           // 发布月份
  day?: number;             // 发布日期
  pageCount?: number;       // 页数
}
```

### ExtractionOptions

解压缩选项接口。

```typescript
interface ExtractionOptions {
  targetDirectory?: string;     // 目标目录路径
  overwrite?: boolean;          // 是否覆盖已存在文件
  maxFileSize?: number;         // 最大文件大小限制（字节）
  allowedExtensions?: string[]; // 允许的文件扩展名列表
}
```

### ExtractionResult

解压缩结果接口。

```typescript
interface ExtractionResult {
  success: boolean;         // 操作是否成功
  extractedPath?: string;   // 解压后的目录路径
  fileCount?: number;       // 解压的文件数量
  totalSize?: number;       // 解压文件的总大小
  warnings: string[];       // 警告信息列表
  error?: string;           // 错误信息
}
```

### ExtractedFileInfo

解压文件信息接口。

```typescript
interface ExtractedFileInfo {
  fileName: string;         // 文件名
  filePath: string;         // 完整文件路径
  fileSize: number;         // 文件大小（字节）
  mimeType: string;         // MIME类型
  isImage: boolean;         // 是否为图片文件
}
```

### ValidationResult

验证结果接口。

```typescript
interface ValidationResult {
  isValid: boolean;         // 是否有效
  errors: string[];         // 错误信息列表
}
```

### UITestResult

UI测试结果接口。

```typescript
interface UITestResult {
  testName: string;         // 测试名称
  success: boolean;         // 测试是否成功
  message: string;          // 结果消息
  duration?: number;        // 执行时长（毫秒）
}
```

### ComicInfoInput

数据库漫画信息输入接口。

```typescript
interface ComicInfoInput {
  title: string;            // 漫画标题
  author: string;           // 作者
  description: string;      // 描述
  coverUrl: string;         // 封面URL
  sourceId: string;         // 来源ID
  status: MangaStatus;      // 状态
  tags: string[];           // 标签列表
  rating: number;           // 评分
  chapterCount: number;     // 章节数
  lastUpdateTime: number;   // 最后更新时间
}
```

### ChapterInfoInput

数据库章节信息输入接口。

```typescript
interface ChapterInfoInput {
  mangaId: string;          // 漫画ID
  title: string;            // 章节标题
  chapterNumber: number;    // 章节号
  pageCount: number;        // 页数
  publishTime: number;      // 发布时间
  sourceUrl: string;        // 来源URL
}
```

### PageInfoInput

数据库页面信息输入接口。

```typescript
interface PageInfoInput {
  chapterId: string;        // 章节ID
  pageNumber: number;       // 页码
  imageUrl: string;         // 图片URL
  width?: number;           // 图片宽度
  height?: number;          // 图片高度
}
```

---

## 错误类型定义

### ParseError

XML解析错误类。

```typescript
class ParseError extends Error {
  constructor(message: string, public xmlContent?: string) {
    super(message);
    this.name = 'ParseError';
  }
}
```

### ExtractionError

文件解压错误类。

```typescript
class ExtractionError extends Error {
  constructor(message: string, public filePath?: string) {
    super(message);
    this.name = 'ExtractionError';
  }
}
```

### ValidationError

数据验证错误类。

```typescript
class ValidationError extends Error {
  constructor(message: string, public validationErrors: string[]) {
    super(message);
    this.name = 'ValidationError';
  }
}
```

---

## 使用示例

### 完整导入流程示例

```typescript
import { ComicInfoParser } from '../Utils/ComicInfoParser';
import { CompressionUtils } from '../Utils/CompressionUtils';
import { DataManager } from '../Framework/Managers/DataManager';

async function importComicFile(filePath: string, dataManager: DataManager): Promise<void> {
  const parser = new ComicInfoParser();
  const compressionUtils = new CompressionUtils();
  
  try {
    // 1. 解压文件并查找ComicInfo.xml
    const { result, comicInfoPath } = await compressionUtils.extractAndFindComicInfo(filePath);
    
    if (!result.success) {
      throw new Error(`解压失败: ${result.error}`);
    }
    
    // 2. 解析ComicInfo.xml（如果存在）
    let comicInfo: ComicInfo;
    if (comicInfoPath) {
      const xmlContent = await fs.readText(comicInfoPath);
      comicInfo = parser.parseXmlString(xmlContent);
    } else {
      comicInfo = ComicInfoParser.createDefaultComicInfo();
      comicInfo.title = path.basename(filePath, path.extname(filePath));
    }
    
    // 3. 验证数据
    const validation = ComicInfoParser.validateComicInfo(comicInfo);
    if (!validation.isValid) {
      console.warn('数据验证警告:', validation.errors);
    }
    
    // 4. 转换为数据库格式
    const comicInfoInput: ComicInfoInput = {
      title: comicInfo.title || '未知标题',
      author: comicInfo.writer || '未知作者',
      description: comicInfo.summary || '',
      coverUrl: '', // 需要单独处理封面
      sourceId: comicInfo.source || 'local',
      status: convertToMangaStatus(comicInfo.publishingStatus),
      tags: comicInfo.genre ? [comicInfo.genre] : [],
      rating: 0,
      chapterCount: 1,
      lastUpdateTime: Date.now()
    };
    
    // 5. 保存到数据库
    const mangaId = await dataManager.addComicInfo(comicInfoInput);
    console.log('漫画导入成功，ID:', mangaId);
    
    // 6. 清理临时文件
    if (result.extractedPath) {
      await compressionUtils.cleanupDirectory(result.extractedPath);
    }
    
  } catch (error) {
    console.error('导入失败:', error.message);
    throw error;
  }
}

// 辅助函数
function convertToMangaStatus(status?: string): MangaStatus {
  switch (status?.toLowerCase()) {
    case 'completed':
      return MangaStatus.COMPLETED;
    case 'ongoing':
      return MangaStatus.ONGOING;
    default:
      return MangaStatus.UNKNOWN;
  }
}
```

### 批量测试示例

```typescript
import { DataManagementTest } from '../Utils/DataManagementTest';
import { UIFunctionalityTest } from '../Utils/UIFunctionalityTest';

async function runAllTests(dataManager: DataManager): Promise<void> {
  console.log('开始运行测试...');
  
  // 1. 运行功能测试
  const functionalReport = await DataManagementTest.runDataManagementTests(dataManager);
  console.log('功能测试报告:\n', functionalReport);
  
  // 2. 运行流程测试
  const flowReport = await DataManagementTest.runCompleteImportFlowTest(dataManager);
  console.log('流程测试报告:\n', flowReport);
  
  // 3. 运行UI测试
  const uiResults = await UIFunctionalityTest.runUIFunctionalityTests();
  const uiReport = UIFunctionalityTest.generateUITestReport(uiResults);
  console.log('UI测试报告:\n', uiReport);
  
  // 4. 生成综合报告
  const passedTests = uiResults.filter(r => r.success).length;
  const totalTests = uiResults.length;
  const passRate = (passedTests / totalTests * 100).toFixed(2);
  
  console.log(`\n测试总结:`);
  console.log(`- 总测试数: ${totalTests}`);
  console.log(`- 通过测试: ${passedTests}`);
  console.log(`- 失败测试: ${totalTests - passedTests}`);
  console.log(`- 通过率: ${passRate}%`);
}
```

### 错误处理示例

```typescript
async function safeImportComic(filePath: string): Promise<boolean> {
  try {
    await importComicFile(filePath, dataManager);
    return true;
  } catch (error) {
    // 根据错误类型进行不同处理
    if (error instanceof ParseError) {
      console.error('XML解析错误:', error.message);
      if (error.xmlContent) {
        console.error('问题XML内容:', error.xmlContent);
      }
    } else if (error instanceof ExtractionError) {
      console.error('文件解压错误:', error.message);
      if (error.filePath) {
        console.error('问题文件:', error.filePath);
      }
    } else if (error instanceof ValidationError) {
      console.error('数据验证错误:', error.message);
      console.error('验证错误详情:', error.validationErrors);
    } else {
      console.error('未知错误:', error.message);
    }
    return false;
  }
}
```

---

## 版本信息

- **API版本**: 1.0.0
- **兼容性**: HarmonyOSNext API 18+
- **最后更新**: 2024年12月

## 支持和反馈

如有API使用问题或建议，请通过以下方式联系：

- 项目文档: `/docs/DataManagementGuide.md`
- 技术文档: `/docs/DataManagementTechnicalDoc.md`
- 日志系统: 使用统一的Logger进行问题追踪