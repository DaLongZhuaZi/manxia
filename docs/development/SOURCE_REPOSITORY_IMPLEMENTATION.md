# 图源仓库导入功能实现文档

## 概述

本文档描述了图源仓库导入和同步功能的实现，该功能允许用户从在线仓库同步图源配置，并管理多个图源仓库。

## 功能特性

### 1. 仓库管理
- **extensions-source 文件夹**: 在应用数据目录下创建专门的文件夹存储仓库数据
- **index.main.json**: 主索引文件，管理所有已同步的图源
- **单独的图源文件**: 每个图源包都有独立的JSON配置文件
- **已保存仓库列表**: 记录用户添加过的仓库URL和元数据

### 2. 自定义弹窗
- **URL输入**: 支持手动输入仓库地址
- **已保存仓库选择**: 可以从历史记录中选择之前添加的仓库
- **展开/收起**: 已保存仓库列表可以展开或收起
- **同步状态显示**: 实时显示同步进度

### 3. 仓库同步
- **在线下载**: 从指定URL下载图源仓库索引
- **JSON解析**: 解析Tachiyomi格式的图源配置
- **去重合并**: 智能合并新旧图源，避免重复
- **批量保存**: 将图源配置保存到本地文件系统

## 技术实现

### 核心文件

#### 1. SourceRepositoryManager.ets
位置: `entry/src/main/ets/Framework/Source/SourceRepositoryManager.ets`

**主要功能**:
- 初始化仓库目录结构
- 管理 index.main.json 索引文件
- 从URL同步仓库数据
- 保存和加载已保存的仓库配置
- 提供图源搜索功能

**核心接口**:
```typescript
// 图源仓库条目（参考Tachiyomi格式）
interface SourceRepositoryEntry {
  name: string;           // 图源名称
  pkg: string;            // 包名
  apk?: string;           // APK文件名（可选）
  lang: string;           // 语言
  code: number;           // 版本代码
  version: string;        // 版本号
  nsfw: number;           // 是否NSFW (0/1)
  sources: Array<{
    name: string;         // 图源显示名称
    lang: string;         // 语言
    id: string;           // 图源ID
    baseUrl: string;      // 基础URL
  }>;
}

// 图源仓库索引文件
interface SourceRepositoryIndex {
  version: string;                          // 仓库版本
  lastUpdate: number;                       // 最后更新时间
  sources: SourceRepositoryEntry[];         // 图源列表
}

// 已保存的仓库配置
interface SavedRepository {
  id: string;             // 仓库ID
  name: string;           // 仓库名称
  url: string;            // 仓库URL
  lastSync: number;       // 最后同步时间
  sourceCount: number;    // 图源数量
}
```

**关键方法**:
- `initialize(context)`: 初始化仓库管理器，创建必要的目录和文件
- `syncRepositoryFromUrl(url, name)`: 从URL同步仓库
- `getSavedRepositories()`: 获取已保存的仓库列表
- `getRepositorySources()`: 获取仓库中的所有图源
- `searchRepositorySources(keyword)`: 搜索仓库中的图源

#### 2. MainMenuPage.ets 更新
位置: `entry/src/main/ets/pages/MainMenuPage.ets`

**新增状态变量**:
```typescript
@State savedRepositories: SavedRepository[] = [];
@State selectedRepositoryId: string = '';
@State showRepositorySelector: boolean = false;
private repositoryManager: SourceRepositoryManager = SourceRepositoryManager.getInstance();
```

**新增方法**:
- `initializeRepositoryManager()`: 初始化仓库管理器
- `loadSavedRepositories()`: 加载已保存的仓库列表
- `syncSourceRepository()`: 执行仓库同步（已更新为使用RepositoryManager）

**UI组件更新**:
- `buildSourceRepoDialog()`: 增强的弹窗，支持选择已保存仓库

### 数据流程

```
用户操作
  ↓
打开图源仓库弹窗
  ↓
选择已保存仓库 或 输入新URL
  ↓
点击"确认同步"
  ↓
RepositoryManager.syncRepositoryFromUrl()
  ↓
下载仓库JSON → 解析数据 → 合并去重 → 保存文件
  ↓
更新 index.main.json
  ↓
保存仓库配置到 saved_repositories.json
  ↓
刷新UI显示
```

## 文件结构

```
filesDir/extensions-source/
├── index.main.json                    # 主索引文件
├── saved_repositories.json            # 已保存仓库配置
├── eu.kanade.tachiyomi.extension.zh.komiic.json
├── eu.kanade.tachiyomi.extension.zh.manhuagui.json
└── ... (其他图源JSON文件)
```

### index.main.json 格式
```json
{
  "version": "1.0.0",
  "lastUpdate": 1700000000000,
  "sources": [
    {
      "name": "Tachiyomi: Komiic",
      "pkg": "eu.kanade.tachiyomi.extension.zh.komiic",
      "lang": "zh",
      "code": 4,
      "version": "1.4.4",
      "nsfw": 1,
      "sources": [
        {
          "name": "Komiic",
          "lang": "zh",
          "id": "792932060924485302",
          "baseUrl": "https://komiic.com"
        }
      ]
    }
  ]
}
```

### saved_repositories.json 格式
```json
[
  {
    "id": "repo_123456789",
    "name": "官方仓库",
    "url": "https://example.com/index.main.json",
    "lastSync": 1700000000000,
    "sourceCount": 50
  }
]
```

## 使用方法

### 1. 添加新仓库
1. 在主页面点击"图源"标签
2. 点击"导入图源仓库"按钮
3. 输入仓库URL（例如：`https://example.com/sources.json`）
4. 点击"确认同步"

### 2. 使用已保存仓库
1. 打开图源仓库弹窗
2. 点击"展开"查看已保存的仓库
3. 选择要同步的仓库
4. 点击"确认同步"

### 3. 查看同步结果
- 同步成功后会显示提示信息
- 图源列表会自动刷新
- 可以在图源页面看到新增的图源

## 兼容性

### 支持的仓库格式
- **Tachiyomi格式**: 完全兼容Tachiyomi扩展仓库格式
- **自定义格式**: 支持符合定义接口的自定义格式

### 图源格式
参考 `index.main.json.bak` 中的格式：
- 包含基本元数据（name, pkg, version等）
- 支持多语言图源
- 支持NSFW标记
- 每个图源包可包含多个子图源

## 错误处理

### 网络错误
- HTTP请求失败会显示错误码
- 超时设置为30秒
- 失败后不会影响现有数据

### 数据解析错误
- JSON解析失败会回退到空索引
- 单个图源文件保存失败不影响整体同步
- 所有错误都会记录到日志

### 文件系统错误
- 目录创建失败会抛出异常
- 文件读写错误会记录日志并使用默认值

## 性能优化

1. **增量更新**: 只更新变化的图源，不重复下载
2. **批量操作**: 一次性保存所有图源文件
3. **异步处理**: 所有网络和文件操作都是异步的
4. **缓存机制**: 已保存仓库列表缓存在内存中

## 安全考虑

1. **URL验证**: 确保输入的URL格式正确
2. **数据校验**: 验证下载的JSON格式
3. **文件权限**: 只在应用私有目录操作
4. **错误隔离**: 单个图源失败不影响其他图源

## 未来扩展

### 计划功能
1. **仓库版本管理**: 支持仓库版本检查和更新提醒
2. **图源分类**: 按语言、类型等分类显示
3. **批量导入**: 支持从仓库批量导入多个图源
4. **离线模式**: 支持离线查看已同步的图源
5. **仓库订阅**: 自动检查仓库更新

### 可能的改进
1. 添加仓库搜索功能
2. 支持仓库镜像切换
3. 图源评分和推荐系统
4. 社区仓库分享

## 测试建议

### 功能测试
1. 测试添加新仓库
2. 测试选择已保存仓库
3. 测试同步过程
4. 测试错误处理

### 边界测试
1. 空URL输入
2. 无效URL格式
3. 网络断开情况
4. 大量图源同步

### 性能测试
1. 大文件下载
2. 多次重复同步
3. 并发操作

## 相关文件

- `SourceRepositoryManager.ets`: 仓库管理核心逻辑
- `MainMenuPage.ets`: UI集成和用户交互
- `SourceManager.ets`: 图源导入和管理
- `index.main.json.bak`: 参考的仓库格式示例

## 更新日志

### v1.0.0 (2024-11-19)
- 初始实现
- 支持基本的仓库同步功能
- 实现已保存仓库管理
- 添加自定义弹窗UI
- 完成文件系统集成

## 总结

图源仓库功能为用户提供了便捷的图源管理方式，通过在线同步可以快速获取和更新图源配置。系统采用模块化设计，易于维护和扩展。
