# 隐私模式与NSFW过滤实现指南

## 问题分析

### 核心问题

根据日志分析，发现两个主要问题：

#### 1. 隐私模式筛选失败
```
普通模式筛选: 原始1个, 非隐私内容0个  ❌ 应该是1个
隐私模式筛选: 原始1个, 隐私内容0个  ❌ 应该是1个
```

**原因**：数据库字段正确存储（`isPrivate=1`），但MainMenuPage使用**内存筛选**而非数据库查询，导致效率低下且容易出错。

#### 2. NSFW状态未显示
```
NSFW状态: false  ❌ 数据库中isNSFW=1
```

**原因**：
- 数据库字段正确存储和读取
- 但详情页面（MangaDetailPage等）未实现NSFW状态显示
- 未实现SFW模式过滤

### 根本原因

**缺少统一的数据库查询方法**：
- 没有 `getPrivateComics()` - 查询 `WHERE isPrivate = 1`
- 没有 `getNonPrivateComics()` - 查询 `WHERE isPrivate = 0 OR isPrivate IS NULL`
- 没有 `getSFWComics()` - 查询 `WHERE isNSFW = 0 OR isNSFW IS NULL`
- 没有 `getNSFWComics()` - 查询 `WHERE isNSFW = 1`

## 解决方案

### 第一步：添加统一查询方法

#### 1. DataManager.ets（漫画）

添加8个新方法：

```typescript
// 本地漫画
public async getPrivateComics(): Promise<ComicInfo[]>
public async getNonPrivateComics(): Promise<ComicInfo[]>
public async getSFWComics(): Promise<ComicInfo[]>
public async getNSFWComics(): Promise<ComicInfo[]>

// 在线漫画
public async getPrivateOnlineComics(): Promise<OnlineComicInfo[]>
public async getNonPrivateOnlineComics(): Promise<OnlineComicInfo[]>
public async getSFWOnlineComics(): Promise<OnlineComicInfo[]>
public async getNSFWOnlineComics(): Promise<OnlineComicInfo[]>
```

**实现示例**：
```typescript
public async getPrivateComics(): Promise<ComicInfo[]> {
  try {
    const records = await this.databaseManager.query(
      'comic_info',
      undefined,
      'isPrivate = ?',
      [1],
      'lastUpdateTime DESC'
    );
    logger.info(TAG, `查询到 ${records.length} 条隐私本地漫画`);
    return records.map(record => this.convertRecordToComicInfo(record as ComicInfoDatabaseRecord));
  } catch (error) {
    logger.error(TAG, `获取隐私漫画失败: ${error}`);
    throw error as Error;
  }
}
```

#### 2. EBookDataManager.ets（电子书）

添加4个新方法：

```typescript
public async getPrivateEBooks(): Promise<EBook[]>
public async getNonPrivateEBooks(): Promise<EBook[]>
public async getSFWEBooks(): Promise<EBook[]>
public async getNSFWEBooks(): Promise<EBook[]>
```

**实现示例**：
```typescript
public async getPrivateEBooks(): Promise<EBook[]> {
  try {
    const sql = `SELECT * FROM ebook_info WHERE isPrivate = 1 ORDER BY lastUpdateTime DESC`;
    const records = await this.dbManager.querySql(sql, []);
    
    const ebooks: EBook[] = [];
    for (const record of records) {
      const ebook = await this.buildEBookFromRecord(record);
      ebooks.push(ebook);
    }

    logger.info(TAG, `查询到 ${ebooks.length} 本隐私电子书`);
    return ebooks;
  } catch (error) {
    logger.error(TAG, `获取隐私电子书列表失败: ${String(error instanceof Error ? error.message : error)}`);
    return [];
  }
}
```

#### 3. NovelDataManager.ets（小说）

添加4个新方法：

```typescript
async getPrivateBooks(): Promise<NovelBook[]>
async getNonPrivateBooks(): Promise<NovelBook[]>
async getSFWBooks(): Promise<NovelBook[]>
async getNSFWBooks(): Promise<NovelBook[]>
```

**实现示例**：
```typescript
async getPrivateBooks(): Promise<NovelBook[]> {
  const store = this.getStore();
  const rs = await store.querySql(
    'SELECT * FROM novel_book WHERE isPrivate = 1 ORDER BY lastReadTime DESC'
  );
  return this.parseBookResults(rs);
}
```

### 第二步：更新MainMenuPage使用新方法

**当前实现（错误）**：
```typescript
// ❌ 加载所有数据，然后在内存中筛选
const allComics = await dataManager.getAllComics();
const filtered = allComics.filter(manga => manga.isPrivate === true);
```

**正确实现**：
```typescript
// ✅ 直接从数据库查询需要的数据
private async loadMangaList(): Promise<void> {
  const dataManager = DataManager.getInstance();
  
  if (this.isPrivacyMode) {
    // 隐私模式：直接查询隐私内容
    const localPrivate = await dataManager.getPrivateComics();
    const onlinePrivate = await dataManager.getPrivateOnlineComics();
    this.mangaList = [...localPrivate, ...onlinePrivate];
  } else {
    // 普通模式：直接查询非隐私内容
    const localNonPrivate = await dataManager.getNonPrivateComics();
    const onlineNonPrivate = await dataManager.getNonPrivateOnlineComics();
    this.mangaList = [...localNonPrivate, ...onlineNonPrivate];
  }
  
  // 应用其他筛选（未读、阅读中等）
  this.applyLibraryFilter();
}
```

### 第三步：实现SFW模式过滤

#### 在ContentFilterManager中

```typescript
public filterContentList<T extends { isNSFW?: boolean }>(items: T[]): T[] {
  if (!this.isSFWModeEnabled()) {
    return items;
  }
  
  // SFW模式：过滤掉NSFW内容
  return items.filter(item => !item.isNSFW);
}
```

#### 在详情页面中

**MangaDetailPage.ets**：
```typescript
aboutToAppear() {
  // 检查SFW模式
  const sfwEnabled = this.contentFilterManager.isSFWModeEnabled();
  
  if (sfwEnabled && this.manga?.isNSFW) {
    // 显示警告并阻止访问
    this.showToast('SFW模式已启用，无法查看NSFW内容');
    this.pathStack.pop();
    return;
  }
  
  // 显示NSFW标记
  if (this.manga?.isNSFW) {
    // 在UI中显示NSFW徽章
  }
}
```

## 数据库字段说明

### comic_info 表
```sql
isPrivate INTEGER DEFAULT 0,  -- 0=普通, 1=隐私
isNSFW INTEGER DEFAULT 0      -- 0=SFW, 1=NSFW
```

### online_comic_info 表
```sql
isPrivate INTEGER DEFAULT 0,
isNSFW INTEGER DEFAULT 0
```

### ebook_info 表
```sql
isPrivate INTEGER DEFAULT 0,
isNSFW INTEGER DEFAULT 0
```

### novel_book 表
```sql
isPrivate INTEGER DEFAULT 0,
isNSFW INTEGER DEFAULT 0
```

## 字段转换逻辑

### 数据库 → TypeScript
```typescript
// DataManager.convertRecordToComicInfo()
isPrivate: (record.isPrivate !== undefined && record.isPrivate !== null) 
  ? (record.isPrivate === 1) 
  : false,
isNSFW: (record.isNSFW !== undefined && record.isNSFW !== null) 
  ? (record.isNSFW === 1) 
  : false
```

### TypeScript → Manga对象
```typescript
// ComicConverter.convertComicInfoToMangaAsync()
isNSFW: comic.isNSFW === 1 || comic.isNSFW === true,
isPrivate: comic.isPrivate === 1 || comic.isPrivate === true
```

## 使用示例

### 1. 切换隐私模式时刷新列表

```typescript
private onPrivacyModeChange = (isPrivate: boolean): void => {
  this.isPrivacyMode = isPrivate;
  
  // 重新加载所有内容（使用正确的查询方法）
  this.loadMangaList();
  this.loadEBookList();
  this.loadNovelList();
};
```

### 2. 切换SFW模式时过滤内容

```typescript
private onSFWModeChange = (enabled: boolean): void => {
  // 重新应用筛选
  this.applyLibraryFilter();
  this.applyEBookFilter();
  this.applyNovelFilter();
};
```

### 3. 在详情页检查访问权限

```typescript
aboutToAppear() {
  // 加载数据
  await this.loadMangaData();
  
  // SFW模式检查
  if (this.contentFilterManager.isSFWModeEnabled() && this.manga?.isNSFW) {
    promptAction.showToast({
      message: 'SFW模式已启用，无法查看NSFW内容',
      duration: 2000
    });
    this.pathStack.pop();
    return;
  }
}
```

## 性能优化

### 优化前（内存筛选）
```
1. 查询所有漫画（1000条）
2. 在内存中筛选隐私内容（1条）
性能：O(n)，内存占用高
```

### 优化后（数据库查询）
```
1. 直接查询隐私漫画（1条）
性能：O(1)，内存占用低
```

## 测试检查清单

- [ ] 普通模式显示非隐私内容
- [ ] 隐私模式显示隐私内容
- [ ] 切换模式时正确刷新列表
- [ ] SFW模式过滤NSFW内容
- [ ] 详情页显示NSFW标记
- [ ] SFW模式阻止访问NSFW详情页
- [ ] 漫画、电子书、小说都正确筛选
- [ ] 本地和在线内容都正确筛选

## 注意事项

1. **数据库字段类型**：使用 `INTEGER`（0/1），不是 `BOOLEAN`
2. **NULL值处理**：`isPrivate IS NULL` 视为非隐私内容
3. **类型转换**：数据库 `1` → TypeScript `true`
4. **查询性能**：直接数据库查询比内存筛选快10-100倍
5. **UI一致性**：所有内容类型（漫画/电子书/小说）使用相同的筛选逻辑

## 相关文件

- `DataManager.ets` - 漫画数据管理
- `EBookDataManager.ets` - 电子书数据管理
- `NovelDataManager.ets` - 小说数据管理
- `MainMenuPage.ets` - 主页面筛选逻辑
- `MangaDetailPage.ets` - 漫画详情页
- `EBookDetailPage.ets` - 电子书详情页
- `NovelDetailPage.ets` - 小说详情页
- `ContentFilterManager.ets` - NSFW过滤管理器
- `PrivacyModeManager.ets` - 隐私模式管理器
