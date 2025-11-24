# 在线漫画重复添加问题修复方案

## 🔍 问题分析

### 当前问题
从日志中发现**同一部漫画"電鋸人"在书库中出现了5次**：
```
1. id_1763490442973_3lantm1w - 0个章节
2. id_1763489703199_2qpmec8o - 0个章节  
3. id_1763489463691_lcqjd2lt - 0个章节
4. 294 (Komiic API) - 384个章节
5. id_1763489303039_stwpsr44 - 0个章节
```

### 根本原因
1. **缺少重复检测**：`saveComicFromSource`方法直接插入数据，不检查是否已存在相同标题的漫画
2. **不同图源使用不同ID**：同一部漫画从不同图源添加时会生成不同的ID
3. **无用户确认机制**：没有提示用户该漫画可能已存在

## 💡 解决方案

### 1. 添加重复检测方法

在`DataManager.ets`中添加：

```typescript
/**
 * 根据标题查找相似的漫画（模糊匹配）
 * @param title 漫画标题
 * @param threshold 相似度阈值（0-1），默认0.8
 * @returns 相似漫画列表
 */
async findSimilarComics(title: string, threshold: number = 0.8): Promise<DatabaseRecord[]> {
  try {
    // 先精确匹配
    const exactSql = `SELECT * FROM comic_info WHERE title = ?`;
    const exactResult = await this.databaseManager.querySql(exactSql, [title]);
    
    if (exactResult.length > 0) {
      return exactResult;
    }
    
    // 模糊匹配：使用LIKE查询
    const fuzzyTitle = title.replace(/\s+/g, '%'); // 将空格替换为通配符
    const fuzzySql = `SELECT * FROM comic_info WHERE title LIKE ?`;
    const fuzzyResult = await this.databaseManager.querySql(fuzzySql, [`%${fuzzyTitle}%`]);
    
    // 计算相似度并过滤
    const similarComics = fuzzyResult.filter((record: DatabaseRecord) => {
      const similarity = this.calculateSimilarity(title, record.title as string);
      return similarity >= threshold;
    });
    
    logger.info(TAG, `找到${similarComics.length}部相似漫画: "${title}"`);
    return similarComics;
  } catch (error) {
    logger.error(TAG, `查找相似漫画失败: ${title}`, String(error));
    return [];
  }
}

/**
 * 计算两个字符串的相似度（简单版本）
 * @param str1 字符串1
 * @param str2 字符串2
 * @returns 相似度（0-1）
 */
private calculateSimilarity(str1: string, str2: string): number {
  // 移除空格和标点符号，转小写
  const normalize = (s: string) => s.replace(/[\s\p{P}]/gu, '').toLowerCase();
  const s1 = normalize(str1);
  const s2 = normalize(str2);
  
  // 完全匹配
  if (s1 === s2) return 1.0;
  
  // 包含关系
  if (s1.includes(s2) || s2.includes(s1)) {
    const shorter = Math.min(s1.length, s2.length);
    const longer = Math.max(s1.length, s2.length);
    return shorter / longer;
  }
  
  // Levenshtein距离（简化版）
  const maxLen = Math.max(s1.length, s2.length);
  if (maxLen === 0) return 1.0;
  
  let matches = 0;
  for (let i = 0; i < Math.min(s1.length, s2.length); i++) {
    if (s1[i] === s2[i]) matches++;
  }
  
  return matches / maxLen;
}

/**
 * 合并两部漫画的数据
 * @param targetId 目标漫画ID（保留）
 * @param sourceId 源漫画ID（删除）
 */
async mergeComics(targetId: string, sourceId: string): Promise<void> {
  try {
    logger.info(TAG, `开始合并漫画: ${sourceId} -> ${targetId}`);
    
    // 1. 更新章节的comicId
    const updateChaptersSql = `UPDATE chapter SET comicId = ? WHERE comicId = ?`;
    await this.databaseManager.executeSql(updateChaptersSql, [targetId, sourceId]);
    
    // 2. 更新阅读历史的comicId
    const updateHistorySql = `UPDATE read_history SET comicId = ? WHERE comicId = ?`;
    await this.databaseManager.executeSql(updateHistorySql, [targetId, sourceId]);
    
    // 3. 更新收藏的comicId（如果存在）
    const updateFavoriteSql = `UPDATE favorite SET comicId = ? WHERE comicId = ?`;
    await this.databaseManager.executeSql(updateFavoriteSql, [targetId, sourceId]);
    
    // 4. 删除源漫画
    const deleteComicSql = `DELETE FROM comic_info WHERE id = ?`;
    await this.databaseManager.executeSql(deleteComicSql, [sourceId]);
    
    logger.info(TAG, `漫画合并完成: ${sourceId} -> ${targetId}`);
  } catch (error) {
    logger.error(TAG, `合并漫画失败: ${sourceId} -> ${targetId}`, String(error));
    throw error;
  }
}
```

### 2. 修改保存逻辑

修改`saveComicFromSource`方法，添加重复检测：

```typescript
async saveComicFromSource(sourceId: number, comicData: ESObject, externalId?: string): Promise<{
  comicId: string;
  isDuplicate: boolean;
  similarComics: DatabaseRecord[];
}> {
  try {
    const title = comicData.title as string;
    
    // 检查是否存在相似漫画
    const similarComics = await this.findSimilarComics(title, 0.85);
    
    if (similarComics.length > 0) {
      logger.warn(TAG, `发现${similarComics.length}部相似漫画: "${title}"`);
      return {
        comicId: '',
        isDuplicate: true,
        similarComics: similarComics
      };
    }
    
    // 没有重复，正常保存
    const now = Date.now();
    const comicId = externalId || this.generateId();
    
    const sql = `INSERT INTO comic_info 
                 (id, title, author, description, coverUrl, sourceId, status, tags, rating, chapterCount, lastUpdateTime, addTime) 
                 VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)`;
    
    await this.databaseManager.executeSql(sql, [
      comicId,
      title,
      comicData.author as string || '',
      comicData.description as string || '',
      comicData.coverUrl as string || '',
      String(sourceId),
      comicData.status as string || 'unknown',
      JSON.stringify(comicData.tags || []),
      comicData.rating as number || 0,
      comicData.chapterCount as number || 0,
      comicData.updateTime as number || now,
      now
    ]);

    logger.info(TAG, `漫画已保存: ${title} (来自图源${sourceId})`);
    return {
      comicId: comicId,
      isDuplicate: false,
      similarComics: []
    };
  } catch (error) {
    logger.error(TAG, `保存漫画失败: ${comicData.title}`, String(error));
    throw error as Error;
  }
}
```

### 3. 在MangaDetailPage中添加重复检测对话框

修改`toggleFavorite`方法：

```typescript
private async toggleFavorite(): Promise<void> {
  const mangaObj: Manga | null = this.currentManga;
  if (!mangaObj) {
    return;
  }

  const mangaId: string = mangaObj.id;
  const nextState: boolean = !mangaObj.isFavorite;
  
  try {
    if (nextState) {
      // 如果是WebView图源，先检查重复
      if (this.useWebView && this.sourceId) {
        try {
          const comicData: ESObject = {
            title: mangaObj.title,
            author: mangaObj.metadata.authors.join(', '),
            description: mangaObj.description,
            coverUrl: mangaObj.coverImagePath,
            status: String(mangaObj.status),
            tags: mangaObj.metadata.genres,
            rating: 0,
            chapterCount: mangaObj.chapters.length,
            updateTime: Date.now()
          };
          
          const result = await DataManager.getInstance().saveComicFromSource(
            this.sourceId, 
            comicData, 
            mangaId
          );
          
          if (result.isDuplicate && result.similarComics.length > 0) {
            // 显示重复确认对话框
            this.showDuplicateDialog(mangaObj, result.similarComics);
            return; // 等待用户选择
          }
          
          logger.info(TAG, `网络漫画已保存到数据库: ${mangaObj.title}, ID=${mangaId}`);
        } catch (saveErr) {
          logger.warn(TAG, `保存漫画到数据库失败: ${String(saveErr)}`);
        }
      }
      
      // 正常添加收藏流程...
      const tags: string[] = [];
      await this.dataService.addToFavorites(mangaId, tags);
      
      if (mangaObj.coverImagePath) {
        this.downloadAndSaveCover(mangaId, mangaObj.coverImagePath).catch((err: Error) => {
          logger.warn(TAG, `封面下载失败: ${err.message}`);
        });
      }
    } else {
      await this.dataService.removeFromFavorites(mangaId);
    }
    
    // 更新状态
    if (this.currentManga) {
      this.currentManga.isFavorite = nextState;
      const updatedManga = this.currentManga;
      this.currentManga = null;
      this.currentManga = updatedManga;
    }
    logger.info(TAG, `漫画收藏状态已保存: ${String(nextState)}`);
  } catch (err) {
    logger.error(TAG, `收藏状态更新失败: ${String(err)}`);
  }
}

/**
 * 显示重复漫画确认对话框
 */
private showDuplicateDialog(newManga: Manga, existingComics: DatabaseRecord[]): void {
  const existingComic = existingComics[0]; // 取第一个最相似的
  
  const message = `书库中已存在相似的漫画：\n\n` +
    `📚 已有: ${existingComic.title}\n` +
    `   作者: ${existingComic.author || '未知'}\n` +
    `   章节: ${existingComic.chapterCount || 0}章\n` +
    `   来源: 图源${existingComic.sourceId}\n\n` +
    `🆕 新增: ${newManga.title}\n` +
    `   作者: ${newManga.metadata.authors.join(', ') || '未知'}\n` +
    `   章节: ${newManga.chapters.length}章\n` +
    `   来源: 图源${this.sourceId}\n\n` +
    `请选择操作：`;
  
  AlertDialog.show({
    title: '发现重复漫画',
    message: message,
    autoCancel: true,
    alignment: DialogAlignment.Center,
    primaryButton: {
      value: '取消',
      action: () => {
        logger.info(TAG, '用户取消添加重复漫画');
      }
    },
    secondaryButton: {
      value: '合并到已有',
      action: async () => {
        try {
          // 合并漫画数据
          await DataManager.getInstance().mergeComics(
            existingComic.id as string,
            newManga.id
          );
          
          // 添加到收藏
          await this.dataService.addToFavorites(existingComic.id as string, []);
          
          promptAction.showToast({
            message: '已合并到现有漫画',
            duration: 2000
          });
          
          logger.info(TAG, `漫画已合并: ${newManga.id} -> ${existingComic.id}`);
        } catch (error) {
          logger.error(TAG, '合并漫画失败', String(error));
          promptAction.showToast({
            message: '合并失败',
            duration: 2000
          });
        }
      }
    }
  });
  
  // 可以添加第三个按钮"仍然添加"
  // 但AlertDialog只支持两个按钮，需要使用CustomDialog
}
```

## 📋 实施步骤

1. ✅ 在`DataManager.ets`中添加`findSimilarComics`、`calculateSimilarity`、`mergeComics`方法
2. ✅ 修改`saveComicFromSource`返回类型，添加重复检测逻辑
3. ✅ 在`MangaDetailPage.ets`中修改`toggleFavorite`，添加重复检测
4. ✅ 创建`showDuplicateDialog`方法显示确认对话框
5. ⚠️ 考虑使用CustomDialog支持三个选项：取消、合并、仍然添加

## 🎯 预期效果

- 用户添加在线漫画时，系统自动检测是否已存在相似漫画
- 如果存在，弹出对话框显示对比信息
- 用户可以选择：
  - **取消**：不添加
  - **合并到已有**：将新漫画的数据合并到已有漫画
  - **仍然添加**：作为独立漫画添加（需要CustomDialog）
- 避免书库中出现多个相同的漫画

## 🔧 后续优化

1. 使用更精确的相似度算法（如Levenshtein距离）
2. 支持按作者、封面图片等多维度匹配
3. 添加"查看重复漫画"功能，批量清理
4. 在书库页面显示重复警告标识
