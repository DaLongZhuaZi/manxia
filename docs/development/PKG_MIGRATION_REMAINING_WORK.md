# 图源 PKG 迁移 - 剩余工作清单

## 已完成的工作 ✅

1. **数据库架构** - 添加 `pkg TEXT UNIQUE NOT NULL` 字段到 `comic_source` 表
2. **DataManager** - 添加基于 pkg 的方法：
   - `importSourceFromJSON` - 支持图源更新（检查 pkg 是否存在）
   - `addComicSource` - 返回 `pkg` 而不是数字 ID
   - `getSourceConfigByPkg` - 通过 pkg 查询图源配置
   - `getComicSourceByPkg` - 通过 pkg 查询图源记录
   - `updateComicSourceCookiesByPkg` - 通过 pkg 更新 Cookie
   - `clearComicSourceCookiesByPkg` - 通过 pkg 清除 Cookie
3. **页面参数接口** - `SourceSettingsPageParams` 改为使用 `sourcePkg: string`
4. **SourceSettingsPage** - 部分修改（`loadSettings` 方法）

## 需要继续完成的工作 🚧

### 1. SourceSettingsPage.ets（高优先级）

需要修改以下方法中所有使用 `this.pageParams.sourceId` 的地方：

```typescript
// 需要修改的方法列表：
- saveSettings()          // 行 146-190
- openLoginPage()         // 行 240-260
- performFormLogin()      // 行 265-295
- onReady()              // 行 710-720
```

**修改模式**：
```typescript
// 旧代码
const sid: number = this.pageParams.sourceId;

// 新代码
const pkg: string = this.pageParams.sourcePkg;
const sourceRecord = await this.dataManager.getComicSourceByPkg(pkg);
if (!sourceRecord) { return; }
const sid: number = sourceRecord.id as number; // 仅用于旧API
```

### 2. SourceLoginPage.ets（高优先级）

```typescript
// 修改参数接口
export interface SourceLoginPageParams {
  sourcePkg: string;  // 改为 pkg
  loginUrl: string;
  loginType: 'webview' | 'form';
}

// 修改所有使用 sourceId 的地方
- onReady() 方法
- handleLoginSuccess() 方法
- 所有 Cookie 保存逻辑
```

### 3. SourceDetailPage.ets（高优先级）

需要修改跳转逻辑，传递 `sourcePkg` 而不是 `sourceId`：

```typescript
// 查找所有 pushPathByName 调用
// 旧代码
this.pathStack.pushPathByName('SourceSettingsPage', {
  sourceId: this.sourceId
});

// 新代码  
this.pathStack.pushPathByName('SourceSettingsPage', {
  sourcePkg: this.sourcePkg  // 需要添加 sourcePkg 状态变量
});
```

**需要添加的状态变量**：
```typescript
@State sourcePkg: string = '';
```

**需要修改的方法**：
- `loadSourceDetail()` - 从数据库记录中提取 pkg
- 所有跳转到 SourceSettingsPage 的地方
- 所有跳转到 SourceLoginPage 的地方

### 4. WebViewAuthManager.ets（中优先级）

修改所有 Cookie 操作方法使用 `pkg`：

```typescript
// 需要修改的方法：
- saveCookies(sourcePkg: string, ...)
- getCookies(sourcePkg: string)
- injectCookiesToWebView(sourcePkg: string, ...)
```

### 5. MainMenuPage.ets（中优先级）

检查图源列表加载和显示逻辑，确保：
- 图源卡片显示正确的信息
- 点击图源时传递 `pkg` 而不是数字 ID

### 6. CookieManager.ets（低优先级）

虽然已经添加了基于 pkg 的 DataManager 方法，但 CookieManager 本身可能需要添加基于 pkg 的便捷方法：

```typescript
async getCookieInfoByPkg(pkg: string): Promise<CookieInfo> {
  const sourceRecord = await this.dataManager.getComicSourceByPkg(pkg);
  if (!sourceRecord) { return { hasCookie: false, cookieCount: 0 }; }
  return this.getCookieInfo(sourceRecord.id as number);
}
```

## 类型转换问题修复

当前有两个类型转换错误：

```typescript
// 错误：类型 "string" 到类型 "number" 的转换可能是错误的
const sid: number = sourceRecord.id as number;

// 修复：先转换为 unknown
const sid: number = sourceRecord.id as unknown as number;
```

但更好的方式是确保 `ComicSourceDatabaseRecord.id` 的类型定义正确。

## 测试检查清单

完成所有修改后，需要测试：

- [ ] 导入新图源（首次导入）
- [ ] 重新导入已存在的图源（更新）
- [ ] 删除图源文件后重新导入（Cookie 保留）
- [ ] 图源设置页面加载
- [ ] 图源登录功能
- [ ] Cookie 保存和读取
- [ ] 漫画列表加载
- [ ] 漫画详情加载
- [ ] 章节加载
- [ ] 图片加载

## 快速修复脚本

由于需要修改的地方很多，建议使用以下策略：

1. **批量替换**：在每个文件中查找 `this.pageParams.sourceId` 并替换为对应的 pkg 逻辑
2. **渐进式修复**：先修复核心流程（导入 → 详情 → 设置 → 登录），再修复其他功能
3. **保留兼容性**：暂时保留旧的数字 ID 方法，标记为 `@deprecated`

## 预计工作量

- SourceSettingsPage: 1-2 小时
- SourceLoginPage: 30 分钟
- SourceDetailPage: 1 小时
- WebViewAuthManager: 30 分钟
- 其他文件: 1 小时
- 测试验证: 1-2 小时

**总计**: 5-7 小时

---

**当前状态**: 约 40% 完成  
**下一步**: 完成 SourceSettingsPage 的剩余方法修改
