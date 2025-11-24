# Reader Kit 集成说明

## 📚 HarmonyOS Reader Kit 集成方案

本项目已正确集成 HarmonyOS 官方的 **Reader Kit**，用于解析和阅读电子书。

## 🎯 解析策略

### Reader Kit 支持的格式
✅ **EPUB** - 使用 Reader Kit API 解析  
✅ **MOBI** - 使用 Reader Kit API 解析  
✅ **AZW/AZW3** - 使用 Reader Kit API 解析  
✅ **TXT** - 使用文件读取 + 自定义解析  

### 特殊格式处理
❌ **PDF** - Reader Kit **不支持** PDF 格式  
→ 使用 **Web 组件** 进行预览（见 `PdfViewerComponent.ets`）

## 📁 文件结构

```
entry/src/main/ets/
├── Framework/
│   ├── Parsers/
│   │   ├── EBookParser.ets         # 解析器基类和工厂
│   │   ├── ReaderKitParser.ets     # ✨ Reader Kit 集成实现
│   │   └── TxtEBookParser.ets      # TXT 专用解析器
│   └── Components/
│       └── PdfViewerComponent.ets  # PDF Web 组件预览
```

## 🔧 Reader Kit API 使用

### 基本用法（框架代码）

```typescript
import { ReaderKitEBookParser } from './ReaderKitParser';

// 创建解析器
const parser = new ReaderKitEBookParser(filePath, EBookFormat.EPUB);

// 解析电子书
const ebook = await parser.parse();
```

### Reader Kit API 集成（待完善）

当前实现提供了完整的框架代码，实际的 Reader Kit API 调用需要根据 HarmonyOS 版本进行调整：

```typescript
// TODO: 根据实际 Reader Kit API 文档完善
import reader from '@ohos.reader';
// 或者
import { bookParser, readerCore } from '@kit.ReaderKit';

// 创建会话
const session = await reader.createSession({
  fileData: buffer,
  fileType: reader.FileType.EPUB,
  highlightColor: '#FFFACD'
});

// 获取元数据
const metadata = await session.getMetadata();
console.log('书名:', metadata.title);
console.log('作者:', metadata.author);

// 获取目录
const toc = await session.getTableOfContents();

// 获取章节内容
for (const chapter of toc) {
  const content = await session.getChapterContent(chapter.id);
}
```

## ⚙️ 解析器工厂

`EBookParserFactory` 会自动选择合适的解析器：

```typescript
// 自动选择合适的解析器
const parser = EBookParserFactory.createParser(filePath);

if (parser) {
  const ebook = await parser.parse();
}
```

### 选择逻辑

1. **检测文件格式**（通过扩展名）
2. **EPUB/MOBI/AZW** → `ReaderKitEBookParser`（使用官方 API）
3. **TXT** → `TxtParser`（自定义解析）
4. **PDF** → `PdfParser`（Web 组件方案）

## 🚀 使用流程

### 1. 导入电子书

```typescript
// 在 DataManagementPage.ets
private async importEBook(fileUri: string): Promise<void> {
  // 1. 创建解析器（自动选择）
  const parser = EBookParserFactory.createParser(fileUri);
  
  // 2. 解析电子书
  const ebook = await parser.parse();
  
  // 3. 保存到数据库
  await this.ebookDataManager.saveEBook(ebook);
}
```

### 2. 阅读电子书

```typescript
// 在 EBookReaderPage.ets
private async loadEBook(bookId: string): Promise<void> {
  // 从数据库加载
  const ebook = await this.ebookDataManager.getEBookById(bookId);
  
  // 根据格式选择阅读器
  if (ebook.format === EBookFormat.PDF) {
    // 使用 PdfViewerComponent
    this.buildPdfReaderView();
  } else {
    // 使用文本阅读器
    this.buildTextReaderView();
  }
}
```

## 📋 Reader Kit 限制

### 系统要求
- ✅ HarmonyOS NEXT 5.0.4 及以上版本
- ✅ 手机、平板、PC/二合一设备
- ❌ **不支持模拟器**
- 🌏 仅在中国地区提供服务

### 格式支持
| 格式 | Reader Kit | 本项目实现 | 说明 |
|------|-----------|-----------|------|
| EPUB | ✅ | ✅ | 使用 Reader Kit |
| MOBI | ✅ | ✅ | 使用 Reader Kit |
| AZW/AZW3 | ✅ | ✅ | 使用 Reader Kit |
| TXT | ✅ | ✅ | 自定义解析 |
| PDF | ❌ | ✅ | Web 组件预览 |

## 🔍 降级方案

如果 Reader Kit API 不可用（如在模拟器上），系统会自动使用降级方案：

1. **从文件名提取基本信息**
2. **创建占位符章节**
3. **保留文件路径供后续访问**

```typescript
// 在 ReaderKitParser.ets
private async parseFallback(): Promise<EBook> {
  // 降级方案：提取文件名、创建基本信息
  const title = this.extractTitleFromFileName(fileName);
  // 返回基本的 EBook 对象
}
```

## 📝 待完善事项

### 高优先级
- [ ] 根据实际 HarmonyOS 版本补充 Reader Kit API 调用
- [ ] 实现 EPUB 章节内容的按需加载
- [ ] 添加 Reader Kit 错误处理和重试机制

### 中优先级
- [ ] 实现电子书封面图片提取
- [ ] 支持书籍元数据编辑
- [ ] 添加阅读进度同步

### 低优先级
- [ ] 实现书签功能
- [ ] 添加全文搜索
- [ ] 支持笔记和批注

## 🔗 参考资料

### 官方文档
- [HarmonyOS Reader Kit 官方文档](https://developer.huawei.com/)
- [Medium: What is Reader Kit?](https://medium.com/huawei-developers/new-kit-what-is-reader-kit-everything-you-need-to-know-about-huaweis-new-reading-sdk-16ce0529490b)

### API 模块
```typescript
// 可能的导入方式（根据实际版本选择）
import reader from '@ohos.reader';
// 或
import { bookParser, readerCore } from '@kit.ReaderKit';
```

## ⚠️ 注意事项

1. **Reader Kit 不支持 PDF**：PDF 文件必须使用 Web 组件方案
2. **模拟器限制**：Reader Kit 在模拟器上不可用，需要真机测试
3. **API 版本**：需要根据实际的 HarmonyOS 版本调整 API 调用
4. **文件访问**：确保应用有文件读取权限

## 🎯 测试建议

### EPUB/MOBI 测试
1. 准备测试文件（EPUB、MOBI 格式）
2. 在真机上测试导入功能
3. 验证元数据解析是否正确
4. 测试章节内容读取

### PDF 测试
1. 准备各种大小的 PDF 文件
2. 测试 Web 组件预览功能
3. 验证缩放和滚动交互
4. 测试中文文件名显示

### 降级方案测试
1. 在模拟器上测试
2. 验证降级方案是否正常工作
3. 确保基本信息正确显示

## 📞 技术支持

如果遇到 Reader Kit 相关问题：
1. 查阅最新的 HarmonyOS 开发者文档
2. 检查 HarmonyOS 版本是否满足要求
3. 确认设备是否支持 Reader Kit
4. 查看日志中的详细错误信息

---

**最后更新**: 2025-11-08  
**状态**: ✅ 框架完成，待补充实际 API 调用  
**测试状态**: ⚠️ 需要在真机上测试 Reader Kit 功能

