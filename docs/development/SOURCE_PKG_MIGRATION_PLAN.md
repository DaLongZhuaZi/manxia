# 图源包名唯一性修复方案

## 问题描述

当前系统使用自增的数字 `id` 作为图源的主键，导致以下问题：

1. **重复图源**：同一个图源包（相同的 `pkg` 名称）在不同版本或导入方式下被识别为不同的图源
2. **数据孤岛**：旧版本图源的漫画记录无法关联到新版本图源
3. **配置丢失**：删除图源文件后，用户的 Cookie、设置等配置也随之丢失
4. **ID 不一致**：`comic_info.sourceId` 是 TEXT 类型，但 `comic_source.id` 是 INTEGER 类型

## 根本原因

### 当前架构问题

```typescript
// DatabaseSchema.ets - 接口定义（正确）
export interface ComicSourceTable {
  id: string;  // ✅ 使用 UUID
  name: string;
  // ...
}

// DatabaseSchema.ets - SQL 创建语句（错误）
CREATE TABLE IF NOT EXISTS comic_source (
  id INTEGER PRIMARY KEY AUTOINCREMENT,  // ❌ 使用自增 ID
  name TEXT NOT NULL,
  // ...没有 pkg 字段
)

// comic_info 表
CREATE TABLE IF NOT EXISTS comic_info (
  id TEXT PRIMARY KEY,
  sourceId TEXT NOT NULL,  // ✅ 正确使用 TEXT 类型
  // ...
)
```

### 图源配置示例

```json
{
  "metadata": {
    "id": "komiic",  // ← 这是图源的唯一包名
    "name": "Komiic",
    "version": "5.0.0"
  }
}
```

## 修复方案

### 阶段 1：数据库架构调整

#### 1.1 添加 `pkg` 字段并设置唯一约束

```sql
-- 添加 pkg 字段（图源唯一包名）
ALTER TABLE comic_source ADD COLUMN pkg TEXT;

-- 创建唯一索引
CREATE UNIQUE INDEX IF NOT EXISTS idx_comic_source_pkg ON comic_source(pkg);
```

#### 1.2 数据迁移策略

由于 SQLite 不支持直接修改主键，我们采用以下策略：

**选项 A：保留数字 ID，使用 pkg 作为业务主键**
- 优点：无需重建表，迁移简单
- 缺点：存在两套标识系统

**选项 B：重建表，使用 pkg 作为主键**（推荐）
- 优点：架构清晰，符合业务逻辑
- 缺点：需要迁移所有关联数据

### 阶段 2：代码调整

#### 2.1 图源导入逻辑

```typescript
// DataManager.ets - importSourceFromJSON
async importSourceFromJSON(jsonContent: string): Promise<string> {
  const config = JSON.parse(jsonContent);
  const metadata = config.metadata;
  const pkg = metadata.id;  // 使用 metadata.id 作为 pkg
  
  // 检查是否已存在
  const existing = await this.getComicSourceByPkg(pkg);
  
  if (existing) {
    // 更新现有图源（保留 Cookie 和配置）
    await this.updateComicSource(pkg, {
      name: metadata.name,
      version: metadata.version,
      configJson: jsonContent,
      lastUpdateTime: Date.now()
    });
    logger.info(TAG, `图源已更新: ${pkg} v${metadata.version}`);
    return pkg;
  } else {
    // 插入新图源
    await this.addComicSource({
      pkg: pkg,
      name: metadata.name,
      version: metadata.version,
      configJson: jsonContent
    });
    logger.info(TAG, `图源已添加: ${pkg} v${metadata.version}`);
    return pkg;
  }
}
```

#### 2.2 WebView 系统调整

```typescript
// WebViewSourceManager.ets
class WebViewSourceManager {
  // 使用 pkg 而不是数字 ID
  private readonly sourceConfigs: Map<string, WebViewSourceConfig> = new Map();
  
  registerSource(pkg: string, config: WebViewSourceConfig): void {
    this.sourceConfigs.set(pkg, config);
    logger.info(TAG, `注册WebView图源: ${pkg}`);
  }
  
  getWebViewInstance(pkg: string): WebViewInstanceInfo | null {
    const config = this.sourceConfigs.get(pkg);
    if (!config) {
      logger.warn(TAG, `源配置不存在: ${pkg}`);
      return null;
    }
    // ...
  }
}
```

#### 2.3 漫画信息存储调整

```typescript
// DataManager.ets - addComicInfo
async addComicInfo(comic: ComicInfo, sourcePkg: string): Promise<void> {
  const sql = `INSERT INTO comic_info 
               (id, sourceId, externalId, title, ...) 
               VALUES (?, ?, ?, ?, ...)`;
  
  await this.databaseManager.executeSql(sql, [
    generateUUID(),
    sourcePkg,  // ← 使用 pkg 而不是数字 ID
    comic.externalId,
    comic.title,
    // ...
  ]);
}
```

### 阶段 3：数据迁移脚本

#### 3.1 从 configJson 提取 pkg

```typescript
async migrateSourcePkg(): Promise<void> {
  // 1. 查询所有图源
  const sources = await this.databaseManager.querySql(
    'SELECT id, configJson FROM comic_source', []
  );
  
  for (const source of sources) {
    try {
      const config = JSON.parse(source.configJson);
      const pkg = config.metadata?.id;
      
      if (pkg) {
        // 2. 更新 pkg 字段
        await this.databaseManager.executeSql(
          'UPDATE comic_source SET pkg = ? WHERE id = ?',
          [pkg, source.id]
        );
        
        // 3. 更新 comic_info 表的 sourceId
        await this.databaseManager.executeSql(
          'UPDATE comic_info SET sourceId = ? WHERE sourceId = ?',
          [pkg, String(source.id)]
        );
        
        logger.info(TAG, `已迁移图源: ${pkg} (旧ID: ${source.id})`);
      }
    } catch (error) {
      logger.error(TAG, `迁移失败: ${source.id}`, error);
    }
  }
}
```

#### 3.2 合并重复图源

```typescript
async mergeDuplicateSources(): Promise<void> {
  // 1. 查找重复的 pkg
  const duplicates = await this.databaseManager.querySql(`
    SELECT pkg, COUNT(*) as count, GROUP_CONCAT(id) as ids
    FROM comic_source
    WHERE pkg IS NOT NULL
    GROUP BY pkg
    HAVING count > 1
  `, []);
  
  for (const dup of duplicates) {
    const ids = dup.ids.split(',');
    const keepId = ids[0];  // 保留第一个
    
    // 2. 合并 Cookie（取最新的非空值）
    const sources = await this.databaseManager.querySql(
      `SELECT id, cookies, lastUpdateTime 
       FROM comic_source 
       WHERE id IN (${ids.join(',')})
       ORDER BY lastUpdateTime DESC`,
      []
    );
    
    const latestCookies = sources.find(s => s.cookies)?.cookies || '';
    
    // 3. 更新保留的图源
    await this.databaseManager.executeSql(
      'UPDATE comic_source SET cookies = ? WHERE id = ?',
      [latestCookies, keepId]
    );
    
    // 4. 迁移漫画记录到保留的图源
    for (let i = 1; i < ids.length; i++) {
      await this.databaseManager.executeSql(
        'UPDATE comic_info SET sourceId = ? WHERE sourceId = ?',
        [dup.pkg, String(ids[i])]
      );
    }
    
    // 5. 删除重复的图源
    await this.databaseManager.executeSql(
      `DELETE FROM comic_source WHERE id IN (${ids.slice(1).join(',')})`,
      []
    );
    
    logger.info(TAG, `已合并重复图源: ${dup.pkg}, 删除了 ${ids.length - 1} 个重复项`);
  }
}
```

### 阶段 4：API 接口调整

#### 4.1 页面参数传递

```typescript
// SourceDetailPage.ets
interface SourceDetailPageParams {
  sourcePkg: string;  // ← 使用 pkg 而不是 sourceId
}

// 跳转到设置页
this.pathStack.pushPathByName('SourceSettingsPage', {
  sourcePkg: this.sourcePkg
});

// 跳转到登录页
this.pathStack.pushPathByName('SourceLoginPage', {
  sourcePkg: this.sourcePkg,
  loginType: 'webview'
});
```

#### 4.2 Cookie 管理

```typescript
// CookieManager.ets
class CookieManager {
  async getCookie(sourcePkg: string): Promise<string> {
    const result = await this.databaseManager.querySql(
      'SELECT cookies FROM comic_source WHERE pkg = ?',
      [sourcePkg]
    );
    return result[0]?.cookies || '';
  }
  
  async saveCookie(sourcePkg: string, cookies: string): Promise<void> {
    await this.databaseManager.executeSql(
      'UPDATE comic_source SET cookies = ? WHERE pkg = ?',
      [cookies, sourcePkg]
    );
  }
}
```

## 实施步骤

### Step 1: 数据库迁移（优先级：高）

1. ✅ 添加 `pkg` 字段到 `comic_source` 表
2. ✅ 从 `configJson` 提取 `pkg` 并填充
3. ✅ 创建唯一索引 `idx_comic_source_pkg`
4. ✅ 更新 `comic_info.sourceId` 从数字 ID 到 pkg
5. ✅ 合并重复的图源记录

### Step 2: 核心代码调整（优先级：高）

1. ✅ 修改 `DataManager.importSourceFromJSON` 使用 pkg
2. ✅ 修改 `DataManager.addComicSource` 添加 pkg 参数
3. ✅ 修改 `WebViewSourceManager` 使用 pkg 作为键
4. ✅ 修改 `CookieManager` 使用 pkg 查询

### Step 3: 页面和组件调整（优先级：中）

1. ✅ 修改所有页面参数从 `sourceId: number` 到 `sourcePkg: string`
2. ✅ 更新导航参数传递
3. ✅ 更新 UI 显示逻辑

### Step 4: 测试和验证（优先级：高）

1. ✅ 测试图源导入（新图源）
2. ✅ 测试图源更新（已存在的图源）
3. ✅ 测试 Cookie 保留（删除后重新导入）
4. ✅ 测试漫画记录关联（版本升级后）
5. ✅ 测试重复图源合并

## 兼容性考虑

### 向后兼容

为了保证平滑过渡，在迁移期间：

1. **保留数字 ID**：在完全迁移完成前，保留 `id` 字段
2. **双重查询**：优先使用 `pkg`，如果不存在则回退到 `id`
3. **渐进式迁移**：用户首次打开应用时自动执行迁移

```typescript
async getComicSource(identifier: string | number): Promise<ComicSource | null> {
  // 优先尝试 pkg
  if (typeof identifier === 'string') {
    const result = await this.databaseManager.querySql(
      'SELECT * FROM comic_source WHERE pkg = ?',
      [identifier]
    );
    if (result.length > 0) return result[0];
  }
  
  // 回退到数字 ID（兼容旧数据）
  const result = await this.databaseManager.querySql(
    'SELECT * FROM comic_source WHERE id = ?',
    [Number(identifier)]
  );
  return result.length > 0 ? result[0] : null;
}
```

## 预期收益

1. **数据一致性**：同一图源包在不同版本间保持相同标识
2. **配置持久化**：删除图源文件后，Cookie 和设置得以保留
3. **简化管理**：无需担心 ID 冲突，图源管理更加直观
4. **架构清晰**：业务逻辑与数据库主键解耦

## 风险评估

| 风险 | 影响 | 缓解措施 |
|------|------|----------|
| 数据迁移失败 | 高 | 迁移前备份数据库，提供回滚机制 |
| pkg 冲突 | 中 | 使用唯一索引，导入时检查冲突 |
| 性能下降 | 低 | pkg 字段建立索引，查询性能不受影响 |
| 兼容性问题 | 中 | 保留双重查询逻辑，渐进式迁移 |

## 时间估算

- 数据库迁移脚本：2-3 小时
- 核心代码调整：4-6 小时
- 页面和组件调整：3-4 小时
- 测试和验证：2-3 小时
- **总计：11-16 小时**

---

**修复时间**: 2024-11-21  
**修复状态**: 📋 待实施
