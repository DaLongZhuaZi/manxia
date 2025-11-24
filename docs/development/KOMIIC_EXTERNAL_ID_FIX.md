# Komiic 外部章节ID修复说明

## 问题描述

从书库进入的在线漫画（Komiic图源），在阅读时出现402错误。原因是漫画阅读器使用的是内部章节ID（格式：`id_xxx`），而不是外部章节ID，导致无法正确构建Komiic的Referer请求头。

Komiic图源要求的Referer格式：
```
https://komiic.com/comic/{外部漫画ID}/chapter/{外部章节ID}/images/all
```

但系统使用的是：
```
https://komiic.com/comic/{内部漫画ID}/chapter/{内部章节ID}/images/all
```

## 修复方案

### 1. 数据库章节加载 - 添加externalId字段

**文件**: `MangaDetailPage.ets`

#### 修复位置1: 在线章节加载（online_chapter表）
```typescript
// 行号: 1714-1733
const chapter: MangaChapter = {
  id: ch.id,
  title: ch.title,
  chapterNumber: ch.chapterNumber,
  pages: [],
  publishDate: ch.publishTime || Date.now(),
  language: 'zh-CN',
  scanlationGroup: '',
  isDownloaded: isDownloaded,
  downloadProgress: isDownloaded ? 100 : 0,
  downloadStatus: isDownloaded ? DownloadStatus.COMPLETED : DownloadStatus.PENDING,
  localPath: undefined,
  externalId: ch.externalId // [修复] 从数据库读取外部章节ID
};
```

#### 修复位置2: 兼容旧数据加载（chapter表）
```typescript
// 行号: 1750-1770
const chapter: MangaChapter = {
  id: ch.id,
  title: ch.title,
  chapterNumber: ch.index,
  pages: [],
  publishDate: ch.publishTime || Date.now(),
  language: 'zh-CN',
  scanlationGroup: '',
  isDownloaded: ch.isDownloaded || false,
  downloadProgress: ch.isDownloaded ? 100 : 0,
  downloadStatus: ch.isDownloaded ? DownloadStatus.COMPLETED : DownloadStatus.PENDING,
  localPath: ch.downloadPath,
  externalId: ch.externalId // [修复] 从数据库读取外部章节ID
};
```

#### 修复位置3: WebView加载时的数据库缓存
```typescript
// 行号: 1368-1384
const chapter: MangaChapter = {
  id: ch.id,
  title: ch.title,
  chapterNumber: ch.index,
  pages: [],
  publishDate: ch.publishTime || Date.now(),
  language: 'zh-CN',
  scanlationGroup: '',
  isDownloaded: ch.isDownloaded || false,
  downloadProgress: ch.isDownloaded ? 100 : 0,
  downloadStatus: ch.isDownloaded ? DownloadStatus.COMPLETED : DownloadStatus.PENDING,
  localPath: ch.downloadPath,
  externalId: ch.externalId // [修复] 传递外部ID
};
```

### 2. WebView章节转换 - 正确使用externalId

**文件**: `MangaDetailPage.ets`

```typescript
// 行号: 1848-1891
private convertWebViewChapterInfoToMangaChapter(chapters: WebViewChapterInfo[]): MangaChapter[] {
  return chapters.map((ch, index) => {
    // [修复] 优先使用ch.externalId作为外部ID，如果没有则使用ch.id
    let externalChapterId = ch.externalId || ch.id || ch.url;
    
    // 如果从URL提取，取最后一段作为ID
    if (!ch.externalId && !ch.id && externalChapterId.includes('/')) {
      const parts = externalChapterId.split('/');
      externalChapterId = parts[parts.length - 1] || `chapter_${index}`;
    }
    
    // 内部ID使用ch.id（如果存在），否则使用externalId
    let chapterId = ch.id || externalChapterId;
    
    const chapter: MangaChapter = {
      id: chapterId,
      title: ch.title,
      chapterNumber: ch.number || (index + 1),
      pages: [],
      publishDate: publishMs,
      language: 'zh',
      scanlationGroup: '',
      isDownloaded: false,
      downloadStatus: DownloadStatus.PENDING,
      downloadProgress: 0,
      localPath: undefined,
      externalId: externalChapterId // [修复] 保存外部ID（Komiic的真实章节ID）
    };
    logger.debug(TAG, `📄 转换章节: title="${ch.title}", id=${chapterId}, externalId=${externalChapterId}`);
    return chapter;
  });
}
```

### 3. 漫画阅读器 - 已有的外部ID查询逻辑

**文件**: `MangaReaderPage.ets`

阅读器已经实现了从数据库查询外部ID的逻辑（行号: 969-980）：

```typescript
// [修复] 如果chapterId是内部ID格式，从数据库查询真实的externalId
if (targetChapterId.startsWith('id_')) {
  try {
    const dbChapterRecord = await DataManager.getInstance().getChapterById(targetChapterId);
    if (dbChapterRecord && dbChapterRecord.externalId) {
      targetChapterId = dbChapterRecord.externalId as string;
      logger.info(TAG, `🔍 [早期] 从数据库获取外部章节ID: ${targetChapterId}`);
    }
  } catch (err) {
    logger.warn(TAG, `⚠️ [早期] 获取外部章节ID失败: ${String(err)}`);
  }
}

// 3. 如果是 Komiic 且有 ID，立即设置 Headers
if (isKomiic && targetMangaId && targetChapterId) {
  // 构造 Referer，使用真实的外部ID
  const referer = `https://komiic.com/comic/${targetMangaId}/chapter/${targetChapterId}/images/all`;
  
  this.networkHeaders = {
    userAgent: 'Mozilla/5.0 (Linux; Android 10; K) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/124.0.0.0 Mobile Safari/537.36',
    referer: referer,
    origin: referer,
    accept: 'image/avif,image/webp,image/png,image/jpeg;q=0.9,*/*;q=0.5',
    acceptLanguage: 'zh-CN,zh;q=0.9,en-US;q=0.8,en;q=0.7',
    cookie: cookies
  } as RequestHeaders;
  
  logger.info(TAG, `🚀 [初始化抢跑] 预设 Komiic Referer: ${referer}`);
}
```

## 数据流程

### 完整流程

1. **图源页面** → 获取漫画和章节列表（包含externalId）
2. **保存到数据库** → `saveOnlineMangaToDatabase()` 保存externalId到chapter表
3. **书库加载** → `loadOnlineMangaFromDatabaseOnly()` 从数据库读取章节（包含externalId）
4. **点击章节** → `MangaDetailPage` 传递章节ID（优先使用externalId）
5. **阅读器初始化** → `MangaReaderPage` 查询数据库获取externalId
6. **构建Referer** → 使用外部ID构建正确的Komiic Referer URL
7. **图片请求** → 所有WebView请求携带正确的Referer

### 关键点

- **内部ID**: 格式为 `id_xxx`，用于本地数据库管理
- **外部ID**: Komiic的真实章节ID（如 `id_1763746015186_608myk02`），用于API请求
- **优先级**: 传递参数时优先使用externalId，如果没有则使用内部ID，阅读器会自动查询数据库获取externalId

## 测试验证

### 测试步骤

1. 从图源页面添加Komiic漫画到书库
2. 从书库进入漫画详情页
3. 点击章节开始阅读
4. 检查日志中的Referer URL是否正确
5. 验证图片是否正常加载（不再出现402错误）

### 预期日志

```
🔍 [早期] 从数据库获取外部章节ID: id_1763746015186_608myk02
🚀 [初始化抢跑] 预设 Komiic Referer: https://komiic.com/comic/id_1763746013217_a7wn479e/chapter/id_1763746015186_608myk02/images/all
```

## 注意事项

1. **已有数据**: 对于已经保存到数据库但没有externalId的章节，需要重新从图源加载
2. **数据库字段**: 确保chapter表有externalId字段（DataManager已支持）
3. **兼容性**: 代码同时支持新旧数据格式，向后兼容

## 相关文件

- `MangaDetailPage.ets` - 漫画详情页，负责加载和保存章节数据
- `MangaReaderPage.ets` - 漫画阅读器，负责构建Referer
- `DataManager.ets` - 数据管理器，提供数据库操作
- `MangaSourceTypes.ets` - 定义了ChapterInfo接口（包含externalId字段）

## 修复时间

2024-11-22
