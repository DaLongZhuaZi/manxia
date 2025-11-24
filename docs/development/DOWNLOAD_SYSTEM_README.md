# 下载系统和通知系统实现文档

## 概述

本文档描述了漫匣应用中完整的下载管理系统和通知系统的实现。

## 系统架构

### 1. 通知管理器 (NotificationManager.ets)

**位置**: `entry/src/main/ets/Framework/Managers/NotificationManager.ets`

**核心功能**:
- ✅ 通知权限管理（首次启动自动请求）
- ✅ 多种通知类型支持
- ✅ 下载进度实时通知
- ✅ 通知管理（取消单个/全部）

**主要方法**:
```typescript
// 检查通知权限
checkPermission(): Promise<boolean>

// 请求通知权限（应用首次启动时调用）
requestPermission(context?: UIAbilityContext): Promise<boolean>

// 发送通知
sendNotification(config: NotificationConfig): Promise<boolean>

// 发送下载进度通知
sendDownloadProgressNotification(taskId, fileName, current, total): Promise<boolean>

// 发送下载完成通知
sendDownloadCompleteNotification(taskId, fileName): Promise<boolean>

// 发送下载失败通知
sendDownloadFailedNotification(taskId, fileName, reason): Promise<boolean>
```

**通知类型**:
- `DOWNLOAD_PROGRESS` - 下载进度
- `DOWNLOAD_COMPLETE` - 下载完成
- `DOWNLOAD_FAILED` - 下载失败
- `UPDATE_AVAILABLE` - 更新可用
- `CHAPTER_UPDATE` - 章节更新

### 2. 下载管理器 (DownloadManager.ets)

**位置**: `entry/src/main/ets/Framework/Download/DownloadManager.ets`

**核心功能**:
- ✅ 任务队列管理
- ✅ 并发控制（最大3个并发）
- ✅ 断点续传支持
- ✅ 进度跟踪和通知
- ✅ 文件管理（自动创建目录）
- ✅ 数据持久化

**主要方法**:
```typescript
// 创建下载任务
createDownloadTask(
  mangaId: string,
  mangaTitle: string,
  chapterId: string,
  chapterTitle: string,
  imageUrls: string[]
): Promise<string>

// 暂停任务
pauseTask(taskId: string): Promise<boolean>

// 恢复任务
resumeTask(taskId: string): Promise<boolean>

// 删除任务
deleteTask(taskId: string): Promise<boolean>

// 获取任务信息
getTask(taskId: string): DownloadTaskInfo | undefined

// 获取所有任务
getAllTasks(): DownloadTaskInfo[]

// 获取指定漫画的所有任务
getTasksByManga(mangaId: string): DownloadTaskInfo[]
```

**任务状态**:
```typescript
enum TaskStatus {
  PENDING = 'pending',      // 等待中
  DOWNLOADING = 'downloading', // 下载中
  PAUSED = 'paused',        // 已暂停
  COMPLETED = 'completed',  // 已完成
  FAILED = 'failed'         // 失败
}
```

**下载配置**:
```typescript
{
  maxConcurrent: 3,    // 最大并发数
  retryCount: 3,       // 重试次数
  timeout: 30000       // 超时时间(ms)
}
```

**文件存储结构**:
```
{context.filesDir}/downloads/
  ├── {mangaId}/
  │   ├── {chapterId}/
  │   │   ├── page_1.jpg
  │   │   ├── page_2.jpg
  │   │   └── ...
  │   └── ...
  └── ...
```

### 3. 应用初始化 (EntryAbility.ets)

**位置**: `entry/src/main/ets/EntryAbility.ets`

**初始化流程**:
```typescript
onCreate() {
  // 1. 设置全局上下文
  setContext(this.context);
  
  // 2. 初始化设备适配管理器
  DeviceAdaptationManager.getInstance();
  
  // 3. 初始化数据管理系统
  initializeDataSystem();
}

initializeNotificationAndDownload() {
  // 1. 请求通知权限（首次启动）
  notificationManager.requestPermission(this.context);
  
  // 2. 初始化下载管理器
  downloadManager.setContext(this.context);
}
```

### 4. 漫画详情页集成 (MangaDetailPage.ets)

**位置**: `entry/src/main/ets/pages/MangaDetailPage.ets`

**功能**:
- ✅ 章节多选模式
- ✅ 批量下载按钮
- ✅ 下载任务创建
- ✅ WebView图源支持

**使用流程**:
1. 用户点击多选按钮进入多选模式
2. 选择要下载的章节（复选框）
3. 点击"下载"按钮
4. 系统获取章节图片URL列表
5. 创建下载任务并加入队列
6. 显示下载结果提示

**关键代码**:
```typescript
private async downloadSelectedChapters(): Promise<void> {
  // 1. 获取选中的章节
  const selectedChapterList = manga.chapters.filter(
    ch => this.selectedChapters.has(ch.id)
  );
  
  // 2. 导入下载管理器
  const { MangaDownloadManager } = await import('../Framework/Download/DownloadManager');
  const downloadManager = MangaDownloadManager.getInstance();
  
  // 3. 为每个章节创建下载任务
  for (const chapter of selectedChapterList) {
    // 获取图片URL列表
    let imageUrls = [];
    if (this.useWebView && this.mangaEngine) {
      const result = await this.mangaEngine.getPageList(chapter.id, manga.id);
      imageUrls = result.data.map(page => page.imageUrl);
    }
    
    // 创建下载任务
    await downloadManager.createDownloadTask(
      manga.id,
      manga.title,
      chapter.id,
      chapter.title,
      imageUrls
    );
  }
}
```

### 5. 下载管理页面 (DownloadManagerPage.ets)

**位置**: `entry/src/main/ets/pages/DownloadManagerPage.ets`

**功能**:
- ✅ 实时显示所有下载任务
- ✅ 任务状态过滤（全部/下载中/已完成等）
- ✅ 单个任务操作（暂停/继续/删除）
- ✅ 批量操作（全部暂停/全部继续）
- ✅ 实时进度更新（每秒刷新）

**UI组件**:
- 过滤栏：全部、下载中、已完成
- 批量操作栏：全部暂停、全部继续
- 任务列表：显示进度、速度、剩余时间
- 操作按钮：暂停/继续、删除

**实时更新机制**:
```typescript
private startUpdateTimer(): void {
  this.updateTimer = setInterval(() => {
    this.refreshTasks();
  }, 1000);
}

private refreshTasks(): void {
  const tasks = this.downloadManager.getAllTasks();
  this.downloadTasks = tasks.map(task => ({
    id: task.id,
    mangaTitle: task.mangaTitle,
    chapterTitle: task.chapterTitle,
    progress: task.progress,
    status: this.convertTaskStatus(task.status),
    totalPages: task.totalCount,
    downloadedPages: task.downloadedCount,
    speed: this.calculateSpeed(task),
    remainingTime: this.calculateRemainingTime(task)
  }));
}
```

## 数据流程

### 下载流程

```
用户操作
  ↓
MangaDetailPage.downloadSelectedChapters()
  ↓
MangaDownloadManager.createDownloadTask()
  ↓
添加到下载队列
  ↓
MangaDownloadManager.processQueue()
  ↓
并发下载（最多3个）
  ↓
MangaDownloadManager.downloadTask()
  ↓
下载单个文件（使用request.downloadFile）
  ↓
更新进度 → 发送通知
  ↓
保存到数据库
  ↓
完成 → 发送完成通知
```

### 通知流程

```
下载进度更新
  ↓
NotificationManager.sendDownloadProgressNotification()
  ↓
构建通知内容
  ↓
notificationManager.publish()
  ↓
系统通知栏显示
```

## 使用示例

### 1. 创建下载任务

```typescript
const downloadManager = MangaDownloadManager.getInstance();

const taskId = await downloadManager.createDownloadTask(
  'manga_123',           // 漫画ID
  '示例漫画',            // 漫画标题
  'chapter_456',         // 章节ID
  '第1话',              // 章节标题
  [                      // 图片URL列表
    'https://example.com/page1.jpg',
    'https://example.com/page2.jpg',
    'https://example.com/page3.jpg'
  ]
);

console.log(`下载任务已创建: ${taskId}`);
```

### 2. 管理下载任务

```typescript
const downloadManager = MangaDownloadManager.getInstance();

// 暂停任务
await downloadManager.pauseTask(taskId);

// 恢复任务
await downloadManager.resumeTask(taskId);

// 删除任务
await downloadManager.deleteTask(taskId);

// 获取任务信息
const task = downloadManager.getTask(taskId);
console.log(`进度: ${task.progress}%`);
```

### 3. 发送通知

```typescript
const notificationManager = AppNotificationManager.getInstance();

// 发送下载进度通知
await notificationManager.sendDownloadProgressNotification(
  'task_123',
  '示例漫画 - 第1话',
  5,   // 已下载5张
  20   // 总共20张
);

// 发送完成通知
await notificationManager.sendDownloadCompleteNotification(
  'task_123',
  '示例漫画 - 第1话'
);
```

## 技术特点

1. **单例模式**: 通知管理器和下载管理器都使用单例，全局共享
2. **异步处理**: 所有下载操作都是异步的，不阻塞UI
3. **并发控制**: 最多3个并发下载任务，避免资源过度占用
4. **错误处理**: 完善的try-catch和错误日志
5. **通知集成**: 下载进度实时推送到系统通知栏
6. **数据持久化**: 下载任务保存到数据库，应用重启后可恢复
7. **实时更新**: 下载管理页面每秒自动刷新任务状态

## 注意事项

1. **权限请求**: 应用首次启动时会自动请求通知权限
2. **存储空间**: 下载前应检查可用存储空间
3. **网络状态**: 建议在WiFi环境下载大量内容
4. **内存管理**: 大量并发下载可能占用较多内存
5. **错误恢复**: 下载失败的任务可以手动重试

## 未来优化方向

1. ✨ 支持更多并发数配置
2. ✨ 添加下载速度限制
3. ✨ 支持WiFi自动下载
4. ✨ 添加下载完成后的自动操作
5. ✨ 优化大文件下载性能
6. ✨ 添加下载统计和分析

## 相关文件

- `entry/src/main/ets/Framework/Managers/NotificationManager.ets` - 通知管理器
- `entry/src/main/ets/Framework/Download/DownloadManager.ets` - 下载管理器
- `entry/src/main/ets/EntryAbility.ets` - 应用入口和初始化
- `entry/src/main/ets/pages/MangaDetailPage.ets` - 漫画详情页（下载入口）
- `entry/src/main/ets/pages/DownloadManagerPage.ets` - 下载管理页面
- `entry/src/main/ets/Framework/Types/StatusEnums.ets` - 状态枚举定义

## 版本历史

- **v1.0.0** (2024-11-18)
  - ✅ 实现通知管理器
  - ✅ 实现下载管理器
  - ✅ 集成到漫画详情页
  - ✅ 实现下载管理页面
  - ✅ 添加实时进度更新
