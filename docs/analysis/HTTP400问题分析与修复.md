# HTTP 400 错误问题分析与修复

## 问题现象

两个场景(从书库加载、从图源详情页加载)都出现图片请求返回HTTP 400错误。

## 根本原因

### 日志证据

**书库加载log.txt**:
```
refererLen=19, cookieLen=181
```

**komiic加载log.txt**:
```
refererLen=19, cookieLen=959
```

**关键发现**: `refererLen=19` 表示Referer是 `https://komiic.com/` (正好19个字符)

### 问题分析

Komiic服务器要求图片请求必须携带正确的Referer:
```
https://komiic.com/comic/{mangaId}/chapter/{chapterId}/images/all
```

但实际发送的Referer是:
```
https://komiic.com/
```

**这就是服务器返回400的原因 - Referer验证失败!**

## 代码问题定位

在 `MangaReaderPage.ets` 的 `updateNetworkHeadersForChapter()` 函数中:

```typescript
// 获取外部 Chapter ID
let externalChapterId = chapter.id;
// 简单尝试去除可能的前缀，或者这里假设 chapter.id 已经是外部ID
// 如果是从数据库加载的，可能需要额外的逻辑查找 externalId，但通常 ID 已经被保留

// 构造正确的 Referer
let newReferer = `https://komiic.com/comic/${externalMangaId}/chapter/${externalChapterId}/images/all`;
const needFallback: boolean = (externalMangaId.length === 0) || (externalMangaId.startsWith('id_')) || (externalChapterId.length === 0) || (externalChapterId.startsWith('id_'));
if (needFallback) {
  newReferer = 'https://komiic.com/';  // ❌ 问题在这里!
}
```

**问题**:
1. 没有使用 `chapter.externalId` 来获取真实的Komiic章节ID
2. 当检测到内部ID格式(`id_`开头)时,直接fallback到基础URL
3. 导致所有图片请求都使用错误的Referer

## 修复方案

### 修改内容

在 `updateNetworkHeadersForChapter()` 函数中添加对 `externalId` 的支持:

```typescript
if (isKomiic) {
  // 获取外部 Manga ID
  let externalMangaId = this.pageParams?.mangaId || manga.id;
  
  // [修复] 优先使用 manga.sourceInfo.externalId
  if (externalMangaId.startsWith('id_')) {
    if (manga.sourceInfo?.externalId) {
      externalMangaId = manga.sourceInfo.externalId;
      logger.info(TAG, `✅ 使用manga.sourceInfo.externalId: ${externalMangaId}`);
    } else if (manga.sourceInfo?.sourceUrl) {
      // 尝试从sourceUrl提取ID
      const match = manga.sourceInfo.sourceUrl.match(/\/comic\/(\d+)/);
      if (match && match[1]) {
        externalMangaId = match[1];
        logger.info(TAG, `✅ 从sourceUrl提取mangaId: ${externalMangaId}`);
      }
    }
  }

  // [修复] 获取外部 Chapter ID - 优先使用 chapter.externalId
  let externalChapterId = chapter.id;
  if (externalChapterId.startsWith('id_') && chapter.externalId) {
    externalChapterId = chapter.externalId;
    logger.info(TAG, `✅ 使用chapter.externalId: ${externalChapterId}`);
  }
  
  // 构造正确的 Referer
  let newReferer = `https://komiic.com/comic/${externalMangaId}/chapter/${externalChapterId}/images/all`;
  const needFallback: boolean = (externalMangaId.length === 0) || (externalMangaId.startsWith('id_')) || (externalChapterId.length === 0) || (externalChapterId.startsWith('id_'));
  if (needFallback) {
    logger.warn(TAG, `⚠️ 无法获取有效的外部ID, mangaId=${externalMangaId}, chapterId=${externalChapterId}, 使用fallback`);
    newReferer = 'https://komiic.com/';
  } else {
    logger.info(TAG, `✅ 构造完整Referer: ${newReferer}`);
  }
}
```

### 修复要点

1. **优先使用 `manga.sourceInfo.externalId`**: 这是存储真实Komiic漫画ID的字段
2. **备选方案**: 如果没有externalId,从sourceUrl中提取数字ID
3. **使用 `chapter.externalId`**: 获取真实的Komiic章节ID
4. **添加详细日志**: 方便追踪ID的来源和转换过程
5. **只在真正无法获取ID时才fallback**: 避免不必要的fallback

## 预期效果

修复后的Referer应该是:
```
https://komiic.com/comic/4572/chapter/160435/images/all
```

而不是:
```
https://komiic.com/
```

这样服务器就能正确验证请求来源,返回HTTP 200而不是400。

## 验证方法

重新测试两个场景,检查日志中的:
1. `refererLen` 应该大于19 (完整Referer的长度)
2. 应该看到日志: `✅ 使用chapter.externalId: 160435`
3. 应该看到日志: `✅ 构造完整Referer: https://komiic.com/comic/4572/chapter/160435/images/all`
4. 图片请求应该返回HTTP 200,而不是400

## 相关文件

- `f:\DevEcoStudioProject\manxia\entry\src\main\ets\pages\MangaReaderPage.ets` (line 800-834)
- `f:\DevEcoStudioProject\manxia\entry\src\main\ets\Models\MangaModels.ets` (MangaChapter接口包含externalId字段)

## 技术要点

### Komiic API的Referer验证机制

Komiic服务器对图片请求有严格的Referer验证:
- ✅ 正确: `https://komiic.com/comic/{mangaId}/chapter/{chapterId}/images/all`
- ❌ 错误: `https://komiic.com/`
- ❌ 错误: 空Referer

### 内部ID vs 外部ID

- **内部ID**: 应用内部生成的唯一标识,格式为 `id_1763738698638_tw5pioc0`
- **外部ID**: 图源网站的真实ID,格式为数字 `4572`、`160435`
- **存储位置**: 
  - 漫画外部ID: `manga.sourceInfo.externalId`
  - 章节外部ID: `chapter.externalId`

### Cookie清理

之前的Cookie修复(移除转义字符)已经生效:
- 书库场景: `cookieLen=181` (只有access token,正常)
- 图源详情页场景: `cookieLen=959` (包含所有Cookie,也正常)

Cookie格式已经不是问题,主要问题在Referer。
