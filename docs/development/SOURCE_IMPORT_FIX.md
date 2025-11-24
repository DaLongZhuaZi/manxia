# 图源导入修复说明

## 🐛 问题描述

### 错误日志
```
❌ 错误 [JSONSourceParser] 缺少baseUrl
❌ 错误 [MainMenuPage] 图源导入失败: 图源配置验证失败
```

### 根本原因
`SourceManager.importFromJSON()` 方法只使用 `JSONSourceParser` 验证配置，而 `JSONSourceParser` 只支持 HTTP 格式的图源配置。

当导入 WebView 格式的图源时：
1. `JSONSourceParser` 期望 `metadata.baseUrl` 字段
2. 但 WebView 格式使用的是顶层 `baseUrl` 字段
3. 导致验证失败

---

## ✅ 修复方案

### 修改内容
**文件**: `Framework/Source/SourceManager.ets`  
**方法**: `importFromJSON()`

### 修复前
```typescript
async importFromJSON(jsonContent: string): Promise<ImportResult> {
  // 只使用 JSONSourceParser 验证（仅支持HTTP格式）
  const parser = JSONSourceParser.fromJSON(jsonContent);
  if (!parser.validate()) {
    return { success: false, error: '图源配置验证失败' };
  }
  // ...
}
```

### 修复后
```typescript
async importFromJSON(jsonContent: string): Promise<ImportResult> {
  // 解析JSON
  const config: ESObject = JSON.parse(jsonContent) as ESObject;
  const metadata: ESObject = config.metadata as ESObject;
  const configType: string = metadata.type as string || 'http';
  
  // 根据类型选择验证方式
  if (configType === 'webview') {
    // WebView格式验证
    if (!config.baseUrl) {
      return { success: false, error: 'WebView图源缺少baseUrl配置' };
    }
    if (!config.workflows) {
      return { success: false, error: 'WebView图源缺少workflows配置' };
    }
  } else {
    // HTTP格式验证（使用旧的解析器）
    const parser = JSONSourceParser.fromJSON(jsonContent);
    if (!parser.validate()) {
      return { success: false, error: 'HTTP图源配置验证失败' };
    }
  }
  // ...
}
```

---

## 🎯 核心改进

### 1. 自动检测图源类型
```typescript
const configType: string = metadata.type as string || 'http';
```
- 读取 `metadata.type` 字段
- 默认为 `'http'` 以保持向后兼容

### 2. 分别验证
- **WebView 格式**: 检查 `baseUrl` 和 `workflows`
- **HTTP 格式**: 使用 `JSONSourceParser` 验证

### 3. 详细的错误提示
- WebView图源缺少baseUrl配置
- WebView图源缺少workflows配置
- HTTP图源配置验证失败

### 4. 日志记录
```typescript
logger.info(TAG, `图源导入成功: ${sourceName} (ID: ${sourceId}, 类型: ${configType})`);
```
记录导入的图源类型，便于调试

---

## 📋 验证清单

### WebView 格式必需字段
```json
{
  "metadata": {
    "type": "webview",  // ← 必须
    "name": "...",      // ← 必须
    "version": "..."    // ← 必须
  },
  "baseUrl": "...",     // ← 必须
  "workflows": {        // ← 必须
    "search": {...}
  }
}
```

### HTTP 格式必需字段
```json
{
  "metadata": {
    "name": "...",      // ← 必须
    "version": "...",   // ← 必须
    "baseUrl": "..."    // ← 必须（在metadata中）
  },
  "api": {...},         // ← 必须
  "features": {...}     // ← 必须
}
```

---

## 🧪 测试步骤

### 1. 测试 WebView 格式导入
```bash
1. 打开应用，进入"图源"标签
2. 点击"导入图源"
3. 选择 sources/komiic_webview.json
4. 查看日志
```

**预期日志**:
```
✅ "检测到WebView格式图源"
✅ "图源导入成功: Komiic (ID: 1, 类型: webview)"
```

### 2. 测试 HTTP 格式导入
```bash
1. 删除现有图源
2. 点击"导入图源"
3. 选择 sources/komiic.json
4. 查看日志
```

**预期日志**:
```
✅ "检测到HTTP格式图源"
✅ "图源导入成功: Komiic (ID: 1, 类型: http)"
```

### 3. 测试错误处理
```bash
# 测试缺少baseUrl的WebView配置
{
  "metadata": { "type": "webview", "name": "Test" },
  "workflows": {}
}
```

**预期结果**:
```
❌ "WebView图源缺少baseUrl配置"
```

---

## 🔄 完整的导入流程

```
用户选择JSON文件
    ↓
MainMenuPage.importSource()
    ↓
读取文件内容（UTF-8解码）
    ↓
SourceManager.importFromJSON()
    ↓
解析JSON，检查metadata
    ↓
检测配置类型（metadata.type）
    ├─→ type='webview'
    │       ↓
    │   验证baseUrl和workflows
    │       ↓
    │   通过验证
    │
    └─→ 其他类型
            ↓
        使用JSONSourceParser验证
            ↓
        通过验证
    ↓
检查图源是否已存在
    ↓
DataManager.importSourceFromJSON()
    ↓
保存到数据库
    ↓
返回sourceId
    ↓
刷新图源列表
    ↓
显示成功提示
```

---

## 📊 兼容性

| 格式 | metadata.type | 验证器 | 状态 |
|------|---------------|--------|------|
| HTTP | 不指定或'http' | JSONSourceParser | ✅ 支持 |
| WebView | 'webview' | 自定义验证 | ✅ 支持 |
| 其他 | 其他值 | JSONSourceParser | ⚠️ 降级到HTTP |

---

## ⚠️ 注意事项

### 1. 向后兼容
- 没有 `metadata.type` 字段的配置默认为 HTTP 格式
- 旧的图源配置无需修改

### 2. 数据库存储
- 两种格式的配置都存储为原始 JSON 字符串
- 在 `SourceDetailPage` 加载时再次检测类型

### 3. 验证宽松
- WebView 格式只验证必需字段
- 不验证 workflows 的具体内容
- 运行时由 `MangaSourceEngine` 验证

---

## 🎉 修复效果

### 修复前
- ❌ 只能导入 HTTP 格式图源
- ❌ WebView 格式导入失败
- ❌ 错误提示不明确

### 修复后
- ✅ 支持 HTTP 和 WebView 两种格式
- ✅ 自动检测配置类型
- ✅ 详细的错误提示
- ✅ 完整的日志记录

---

## 📚 相关文档

- [WebView 迁移计划](../WEBVIEW_MIGRATION_PLAN.md)
- [Komiic 配置迁移](../sources/KOMIIC_MIGRATION.md)
- [SourceDetailPage 重构报告](../SOURCEPAGE_REFACTOR_COMPLETE.md)

---

**修复日期**: 2025-11-17 22:55  
**修复状态**: ✅ 完成  
**测试状态**: ⏳ 待测试
