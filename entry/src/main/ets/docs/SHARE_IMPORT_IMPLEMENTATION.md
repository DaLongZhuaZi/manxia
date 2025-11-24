# 系统分享导入功能实现文档

## 概述

本文档描述了HarmonyOS系统级分享功能的实现，使用户可以从文件管理器或其他应用通过"分享"功能直接将漫画文件导入到本应用，实现最快速便捷的导入流程。

## 技术方案

### 核心组件

#### 1. ShareExtAbility（Share Extension Ability）
- **位置**: `entry/src/main/ets/ShareExtAbility/ShareExtAbility.ets`
- **功能**: 接收其他应用通过系统分享功能分享的文件
- **关键实现**:
  - 继承 `UIExtensionAbility`
  - 在 `onSessionCreate` 回调中接收分享数据
  - 从 `Want` 对象中提取文件URI列表
  - 验证文件类型（支持 `.zip`, `.cbz`）
  - 启动主应用并传递文件信息

#### 2. EntryAbility 增强
- **位置**: `entry/src/main/ets/EntryAbility.ets`
- **功能**: 接收从 ShareExtAbility 传递的参数
- **关键实现**:
  - 新增 `handleShareImport()` 方法
  - 在 `onCreate` 和 `onNewWant` 中检查 `share_import_files` 参数
  - 将文件信息保存到 `AppStorage` 供后续页面使用

#### 3. MainMenuPage 增强
- **位置**: `entry/src/main/ets/pages/MainMenuPage.ets`
- **功能**: 检测系统分享导入并导航到数据管理页面
- **关键实现**:
  - 新增 `checkPendingShareImport()` 方法
  - 在 `checkPendingFileImport()` 中优先检查系统分享
  - 设置 `shareImportPending` 标记
  - 导航到 DataManagementPage

#### 4. DataManagementPage 增强
- **位置**: `entry/src/main/ets/pages/DataManagementPage.ets`
- **功能**: 批量处理系统分享导入的文件
- **关键实现**:
  - 新增 `checkPendingShareImport()` 方法
  - 新增 `handlePendingShareFiles()` 方法
  - 自动将分享文件添加到选中列表
  - 自动开始导入流程

### 配置文件

#### module.json5 配置
```json
{
  "extensionAbilities": [
    {
      "name": "ShareExtAbility",
      "srcEntry": "./ets/ShareExtAbility/ShareExtAbility.ets",
      "type": "share",
      "exported": true,
      "description": "接收系统分享的漫画文件",
      "skills": [
        {
          "entities": ["entity.system.default"],
          "actions": ["ohos.want.action.sendData"],
          "uris": [
            { "scheme": "file", "utd": "general.comic-archive" },
            { "scheme": "file", "utd": "general.archive" },
            { "scheme": "content" }
          ]
        }
      ]
    }
  ]
}
```

**关键配置说明**:
- `type: "share"`: 声明为分享扩展能力
- `exported: true`: 允许其他应用调用
- `actions: ["ohos.want.action.sendData"]`: 响应系统分享动作
- `uris`: 支持的文件类型（漫画归档、通用归档、content URI）

## 数据流转

### 1. 用户从文件管理器分享文件

```
文件管理器
  ↓ 用户点击"分享"
系统分享菜单（显示本应用）
  ↓ 用户选择本应用
ShareExtAbility.onSessionCreate()
  ↓ 提取文件URI
ShareExtAbility.handleSharedFiles()
  ↓ 验证文件类型
ShareExtAbility.launchMainAppWithFiles()
  ↓ 启动主应用，传递参数
EntryAbility.onCreate/onNewWant()
  ↓ 接收参数
EntryAbility.handleShareImport()
  ↓ 保存到AppStorage
MainMenuPage.checkPendingFileImport()
  ↓ 检测分享导入
MainMenuPage.checkPendingShareImport()
  ↓ 设置标记并导航
DataManagementPage.checkPendingShareImport()
  ↓ 读取文件列表
DataManagementPage.handlePendingShareFiles()
  ↓ 自动开始导入
导入完成
```

### 2. AppStorage 数据键

| 键名 | 类型 | 说明 |
|------|------|------|
| `pendingShareFiles` | `string[]` | 待导入的文件URI列表 |
| `pendingShareType` | `string` | 分享类型（'comic' / 'ebook'） |
| `pendingShareSource` | `string` | 分享来源标识（'system_share'） |
| `shareImportPending` | `boolean` | 分享导入待处理标记 |

### 3. Want 参数传递

从 ShareExtAbility 传递到 EntryAbility 的参数：

```typescript
{
  bundleName: 'com.dlzz.manxia',
  abilityName: 'EntryAbility',
  parameters: {
    'share_import_files': string[],    // 文件URI列表
    'share_import_type': 'comic',      // 文件类型
    'share_import_source': 'system_share' // 来源标识
  }
}
```

## 文件URI处理

### 支持的URI格式

1. **file:// URI**: 标准文件路径
   ```
   file:///data/storage/el2/base/files/comics/example.zip
   ```

2. **content:// URI**: 内容提供者URI（HarmonyOS直接支持）
   ```
   content://com.example.fileprovider/shared/example.zip
   ```

### URI 标准化

ShareExtAbility 中的 `normalizeFileUri()` 方法处理不同格式的URI：

```typescript
private normalizeFileUri(uri: string): string {
  // file:// 格式直接返回
  if (uri.startsWith('file://')) return uri;
  
  // content:// 格式直接返回（HarmonyOS支持）
  if (uri.startsWith('content://')) return uri;
  
  // 纯路径添加file://前缀
  if (uri.startsWith('/')) return `file://${uri}`;
  
  // 使用fileUri模块转换
  try {
    return fileUri.getUriFromPath(uri);
  } catch {
    return uri; // 转换失败使用原URI
  }
}
```

### 文件类型验证

```typescript
private isValidComicFile(uri: string): boolean {
  const lowerUri = uri.toLowerCase();
  return lowerUri.endsWith('.zip') || 
         lowerUri.endsWith('.cbz') ||
         lowerUri.includes('.zip?') ||
         lowerUri.includes('.cbz?');
}
```

## 用户体验优化

### 1. 自动化流程
- ✅ 接收分享后自动启动应用
- ✅ 自动导航到数据管理页面
- ✅ 自动添加文件到选中列表
- ✅ 自动开始导入流程（延迟1秒，给用户查看时间）

### 2. 错误处理
- ✅ 文件类型验证（只支持ZIP/CBZ）
- ✅ URI转换异常处理
- ✅ 空文件列表检测
- ✅ 完整的日志记录

### 3. 日志记录
所有关键步骤都有详细的日志输出：

```typescript
// ShareExtAbility
logger.lifecycle(TAG, 'ShareExtAbility onCreate');
logger.info(TAG, `接收到 ${sharedUris.length} 个分享文件`);
logger.info(TAG, `✅ 有效的漫画文件: ${normalizedUri}`);

// EntryAbility
logger.info(TAG, `📤 通过系统分享接收文件: ${shareFiles.length} 个`);

// MainMenuPage
logger.info(TAG, `📤 检测到系统分享文件: ${pendingShareFiles.length} 个`);

// DataManagementPage
logger.info(TAG, `开始处理 ${fileUris.length} 个分享文件`);
logger.info(TAG, `✅ 已接收 ${fileUris.length} 个漫画文件，准备导入`);
```

## 测试场景

### 1. 基本分享流程
1. 打开文件管理器
2. 长按漫画文件（ZIP/CBZ格式）
3. 点击"分享"按钮
4. 在分享菜单中选择"漫匣"应用
5. 应用自动打开并导航到数据管理页面
6. 文件自动添加到选中列表
7. 导入流程自动开始

### 2. 批量分享
1. 在文件管理器中选择多个漫画文件
2. 点击"分享"按钮
3. 选择"漫匣"应用
4. 所有文件自动添加到导入列表
5. 根据用户设置的批量策略进行导入

### 3. 应用已打开场景
1. "漫匣"应用已在后台运行
2. 从文件管理器分享文件
3. 应用从后台切换到前台
4. EntryAbility 的 `onNewWant` 被调用
5. 正常处理分享文件

### 4. 不支持的文件类型
1. 分享非ZIP/CBZ文件（如TXT、JPG等）
2. ShareExtAbility 验证文件类型
3. 显示提示："未找到支持的漫画文件（ZIP/CBZ）"
4. 不启动主应用

## API 依赖

### 核心依赖包
```typescript
import { UIExtensionAbility, UIExtensionContentSession, Want } from '@kit.AbilityKit';
import { window } from '@kit.ArkUI';
import { fileUri } from '@kit.CoreFileKit';
```

### fileUri 模块使用
```typescript
import { fileUri } from '@kit.CoreFileKit';

// 从路径获取URI
const uri = fileUri.getUriFromPath('/path/to/file.zip');

// 从URI获取路径（如果需要）
const path = fileUri.getPathFromUri(uri);
```

## 安全考虑

1. **文件类型验证**: 严格限制只接受 `.zip` 和 `.cbz` 文件
2. **URI验证**: 对接收到的URI进行格式验证和标准化
3. **错误处理**: 所有异常都被捕获并记录，不会导致应用崩溃
4. **权限管理**: ShareExtAbility 只接收用户明确分享的文件，不访问其他数据

## 限制和注意事项

1. **文件格式**: 目前仅支持 ZIP 和 CBZ 格式的漫画文件
2. **文件大小**: 受系统和应用内存限制，建议单个文件不超过 500MB
3. **批量导入**: 一次性分享建议不超过 50 个文件，避免性能问题
4. **URI有效性**: 分享的文件URI必须是应用有权访问的，否则导入会失败

## 未来优化方向

1. **进度反馈**: 在 ShareExtAbility 中显示简单的进度界面
2. **文件预览**: 在导入前显示文件缩略图和元数据
3. **智能分类**: 根据文件名或元数据自动分类到不同系列
4. **云端同步**: 支持从云盘分享导入
5. **格式扩展**: 支持更多漫画格式（RAR、7Z等）

## 相关文件清单

| 文件路径 | 说明 |
|---------|------|
| `entry/src/main/ets/ShareExtAbility/ShareExtAbility.ets` | Share Extension Ability 实现 |
| `entry/src/main/ets/EntryAbility.ets` | 主 Ability，处理分享参数 |
| `entry/src/main/ets/pages/MainMenuPage.ets` | 主菜单页面，检测分享导入 |
| `entry/src/main/ets/pages/DataManagementPage.ets` | 数据管理页面，处理导入 |
| `entry/src/main/module.json5` | 模块配置，注册 ShareExtAbility |
| `entry/src/main/ets/docs/SHARE_IMPORT_IMPLEMENTATION.md` | 本文档 |

## 版本历史

- **v1.0** (2025-01-09): 首次实现系统分享导入功能
  - 支持单个和多个文件分享
  - 自动化导入流程
  - 完整的错误处理和日志记录

## 参考资料

1. [HarmonyOS UIExtensionAbility 开发指南](https://developer.huawei.com/consumer/cn/doc/harmonyos-guides/uiextensionability)
2. [HarmonyOS Share Kit 使用说明](https://developer.huawei.com/consumer/cn/doc/harmonyos-guides/share-kit)
3. [@ohos.file.fileuri 模块参考](https://developer.huawei.com/consumer/cn/doc/harmonyos-references/js-apis-file-fileuri)
4. [Want 对象说明](https://developer.huawei.com/consumer/cn/doc/harmonyos-references/js-apis-app-ability-want)

---

**作者**: AI Assistant  
**日期**: 2025-01-09  
**版本**: 1.0

