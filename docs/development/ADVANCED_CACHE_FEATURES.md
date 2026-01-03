# 高级缓存功能实现文档

## 概述

本文档描述了三个高级缓存功能的实现：
1. **可配置的缓存参数系统**
2. **智能预加载策略**
3. **完善的缓存管理UI**

---

## ① 可配置的缓存参数系统

### 实现文件
- **`CacheConfigManager.ets`** - 缓存配置管理器

### 核心功能

#### 1. 配置项
```typescript
interface CacheConfig {
  // 内存缓存配置
  memoryCache: {
    maxCount: number;        // 最大缓存数量（默认50张）
    maxSize: number;         // 最大缓存大小（默认50MB）
    enabled: boolean;        // 是否启用
  };
  
  // 磁盘缓存配置
  diskCache: {
    maxSize: number;         // 最大缓存大小（默认500MB）
    maxAge: number;          // 最大缓存时间（默认7天）
    enabled: boolean;        // 是否启用
    compressionQuality: number; // 压缩质量（默认85）
  };
  
  // 预加载配置
  preload: {
    enabled: boolean;        // 是否启用预加载
    rangeNormal: number;     // 普通模式预加载范围（默认2页）
    rangeWebtoon: number;    // 条漫模式预加载范围（默认3页）
    maxConcurrent: number;   // 最大并发预加载数（默认3）
  };
  
  // 网络配置
  network: {
    maxConcurrent: number;   // 最大并发网络请求数（默认10）
    timeout: number;         // 超时时间（默认30秒）
    retryCount: number;      // 重试次数（默认2次）
  };
}
```

#### 2. 主要方法

**获取配置**
```typescript
const configManager = CacheConfigManager.getInstance();
const config = configManager.getConfig();
```

**更新配置**
```typescript
// 更新内存缓存配置
await configManager.updateMemoryCacheConfig({
  maxSize: 100 * 1024 * 1024  // 100MB
});

// 更新磁盘缓存配置
await configManager.updateDiskCacheConfig({
  maxSize: 1000 * 1024 * 1024,  // 1GB
  maxAge: 14 * 24 * 60 * 60 * 1000  // 14天
});

// 更新预加载配置
await configManager.updatePreloadConfig({
  rangeNormal: 3,
  rangeWebtoon: 5
});
```

**重置配置**
```typescript
await configManager.resetToDefault();
```

**监听配置变更**
```typescript
configManager.addListener((config: CacheConfig) => {
  console.log('配置已更新:', config);
});
```

#### 3. 配置验证

配置管理器会自动验证参数有效性：
- 内存缓存大小必须 > 1MB
- 磁盘缓存大小必须 > 10MB
- 缓存时间必须 > 1小时
- 压缩质量必须在 1-100 之间
- 并发数必须 > 0

#### 4. 持久化存储

配置自动保存到 `preferences`，应用重启后自动加载。

---

## ② 智能预加载策略系统

### 实现文件
- **`SmartPreloadStrategy.ets`** - 智能预加载策略管理器

### 核心功能

#### 1. 学习用户行为

系统会自动记录和分析：
- **页面停留时间** - 判断阅读速度
- **翻页方向** - 分析前翻/后翻偏好
- **网络状况** - WiFi/移动网络
- **阅读习惯** - 快速/正常/慢速

#### 2. 动态调整策略

根据分析结果自动调整预加载范围：

**阅读速度影响**
- 快速阅读（<3秒/页）：增加预加载范围 +2页
- 慢速阅读（>10秒/页）：减少预加载范围 -1页
- 正常阅读：使用配置的基础范围

**翻页方向影响**
- 主要向前翻页（>80%）：向前 +1页，向后 -1页
- 经常回翻（<50%）：向后 +1页

**网络环境影响**
- WiFi环境：向前 +2页，向后 +1页
- 移动网络：使用基础范围

#### 3. 使用方法

**记录阅读行为**
```typescript
const strategy = SmartPreloadStrategy.getInstance();

// 记录翻页行为
strategy.recordBehavior(
  5000,        // 停留时间（毫秒）
  'forward'    // 翻页方向
);
```

**获取当前策略**
```typescript
const currentStrategy = strategy.getCurrentStrategy();
console.log('向前预加载:', currentStrategy.forwardRange);
console.log('向后预加载:', currentStrategy.backwardRange);
console.log('策略原因:', currentStrategy.reason);
```

**获取统计数据**
```typescript
const stats = strategy.getStats();
console.log('总页数:', stats.totalPages);
console.log('向前翻页比例:', stats.forwardRatio);
console.log('平均停留时间:', stats.avgPageDuration);
console.log('阅读速度:', stats.readingSpeed);
console.log('网络类型:', stats.networkType);
```

**获取预加载计划**
```typescript
const plan = strategy.getPreloadPlan(currentIndex, totalPages);
// 返回: [{ index: 1, priority: 9, direction: 'forward' }, ...]
```

**手动刷新策略**
```typescript
await strategy.refreshStrategy();
```

**重置统计数据**
```typescript
strategy.resetStats();
```

#### 4. 策略示例

**场景1：快速阅读 + WiFi**
```
输入：
- 阅读速度：2秒/页（快速）
- 向前翻页：90%
- 网络：WiFi

输出策略：
- 向前预加载：5页（基础2 + 快速2 + WiFi2 - 1）
- 向后预加载：1页（基础1 + WiFi1 - 主要向前1）
- 原因：快速阅读, 主要向前翻页, WiFi环境
```

**场景2：慢速阅读 + 移动网络**
```
输入：
- 阅读速度：12秒/页（慢速）
- 向前翻页：60%
- 网络：移动网络

输出策略：
- 向前预加载：1页（基础2 - 慢速1）
- 向后预加载：0页（基础1 - 慢速1）
- 原因：慢速阅读, 移动网络
```

---

## ③ 完善的缓存管理UI

### 实现文件
- **`CacheManagementPanel.ets`** - 缓存管理面板组件
- **`StorageManagementPage.ets`** - 存储管理页面（已更新）

### 核心功能

#### 1. 磁盘缓存统计

实时显示：
- **缓存数量** - 已缓存的图片数量
- **总大小** - 占用的磁盘空间（MB）
- **使用率** - 相对于最大缓存大小的百分比
- **进度条** - 可视化显示使用率（>80%显示红色警告）

操作：
- **清空缓存** - 一键清空所有磁盘缓存

#### 2. 缓存配置界面

**内存缓存大小**
- 滑块调整：10MB - 200MB
- 步进：10MB
- 实时生效

**磁盘缓存大小**
- 滑块调整：100MB - 2000MB（2GB）
- 步进：100MB
- 实时生效

**预加载开关**
- Toggle开关：启用/禁用预加载
- 实时生效

**预加载范围**（预加载启用时显示）
- 普通模式：0-10页
- 条漫模式：0-10页
- 滑块调整，实时生效

**重置按钮**
- 一键恢复所有配置为默认值
- 需要确认对话框

#### 3. 智能预加载策略监控

**阅读统计**
- 总页数
- 向前翻页数量和比例
- 向后翻页数量
- 平均停留时间（秒）
- 阅读速度（快速/正常/慢速）
- 网络类型（WiFi/移动网络）

**当前策略**
- 向前预加载页数（蓝色高亮）
- 向后预加载页数（蓝色高亮）
- 优先级（1-10）
- 策略原因（文字说明）

**操作**
- **刷新** - 手动刷新所有数据
- **重置统计** - 清空阅读行为历史

#### 4. 使用方法

**在StorageManagementPage中使用**
```typescript
import { CacheManagementPanel } from '../components/CacheManagementPanel';

// 显示缓存管理面板
@Builder
buildCacheManagement() {
  CacheManagementPanel({
    onClose: () => {
      this.showCacheConfig = false;
    }
  })
}
```

**独立使用**
```typescript
CacheManagementPanel()
```

---

## 集成说明

### 1. 初始化

在应用启动时初始化配置管理器：

```typescript
// DataInitializer.ets 或 EntryAbility.ets
import { CacheConfigManager } from '../Framework/Cache/CacheConfigManager';
import { SmartPreloadStrategy } from '../Framework/Cache/SmartPreloadStrategy';

// 初始化配置管理器
const configManager = CacheConfigManager.getInstance();
await configManager.initialize(context);

// 初始化智能预加载策略
const preloadStrategy = SmartPreloadStrategy.getInstance();
await preloadStrategy.initialize();
```

### 2. 在MangaViewer中集成智能预加载

```typescript
// MangaViewer.ets
import { SmartPreloadStrategy } from '../Framework/Cache/SmartPreloadStrategy';

private smartPreloadStrategy: SmartPreloadStrategy = SmartPreloadStrategy.getInstance();
private pageStartTime: number = 0;

// 页面切换时记录行为
private onPageChange(newIndex: number): void {
  const now = Date.now();
  if (this.pageStartTime > 0) {
    const duration = now - this.pageStartTime;
    const direction = newIndex > this.currentPageIndex ? 'forward' : 'backward';
    this.smartPreloadStrategy.recordBehavior(duration, direction);
  }
  this.pageStartTime = now;
  this.currentPageIndex = newIndex;
}

// 获取预加载范围
private getPreloadRange(): number {
  return this.smartPreloadStrategy.getPreloadRange(this.isWebtoonMode());
}
```

### 3. 在OnlineImageLoader中应用配置

```typescript
// OnlineImageLoader.ets
import { CacheConfigManager } from './CacheConfigManager';

private configManager: CacheConfigManager = CacheConfigManager.getInstance();

// 使用配置的并发数
private getMaxConcurrent(): number {
  const config = this.configManager.getNetworkConfig();
  return config.maxConcurrent;
}

// 使用配置的超时时间
private getTimeout(): number {
  const config = this.configManager.getNetworkConfig();
  return config.timeout;
}
```

### 4. 在DiskCacheManager中应用配置

```typescript
// DiskCacheManager.ets
import { CacheConfigManager } from './CacheConfigManager';

private configManager: CacheConfigManager = CacheConfigManager.getInstance();

// 使用配置的缓存大小
private getMaxCacheSize(): number {
  const config = this.configManager.getDiskCacheConfig();
  return config.maxSize;
}

// 使用配置的缓存时间
private getMaxCacheAge(): number {
  const config = this.configManager.getDiskCacheConfig();
  return config.maxAge;
}
```

---

## 性能优化建议

### 1. 配置建议

**低端设备**
```typescript
{
  memoryCache: { maxSize: 30 * 1024 * 1024 },  // 30MB
  diskCache: { maxSize: 300 * 1024 * 1024 },   // 300MB
  preload: { rangeNormal: 1, rangeWebtoon: 2 }
}
```

**中端设备**
```typescript
{
  memoryCache: { maxSize: 50 * 1024 * 1024 },  // 50MB
  diskCache: { maxSize: 500 * 1024 * 1024 },   // 500MB
  preload: { rangeNormal: 2, rangeWebtoon: 3 }
}
```

**高端设备**
```typescript
{
  memoryCache: { maxSize: 100 * 1024 * 1024 }, // 100MB
  diskCache: { maxSize: 1000 * 1024 * 1024 },  // 1GB
  preload: { rangeNormal: 3, rangeWebtoon: 5 }
}
```

### 2. 网络环境建议

**WiFi环境**
- 启用预加载
- 增大预加载范围
- 提高并发数

**移动网络**
- 减小预加载范围
- 降低并发数
- 启用磁盘缓存

**弱网环境**
- 禁用预加载
- 增加超时时间
- 增加重试次数

---

## 监控和调试

### 1. 查看配置摘要

```typescript
const configManager = CacheConfigManager.getInstance();
const summary = configManager.getConfigSummary();
console.log(summary);
// 输出: "内存缓存: 50张/50MB, 磁盘缓存: 500MB/7天, 预加载: 2/3页"
```

### 2. 查看预加载统计

```typescript
const strategy = SmartPreloadStrategy.getInstance();
const stats = strategy.getStats();
console.log('阅读统计:', {
  totalPages: stats.totalPages,
  forwardRatio: stats.forwardRatio,
  readingSpeed: stats.readingSpeed,
  currentStrategy: stats.currentStrategy
});
```

### 3. 查看磁盘缓存统计

```typescript
const diskCache = DiskCacheManager.getInstance();
const stats = diskCache.getStats();
console.log('磁盘缓存:', {
  count: stats.count,
  totalSize: stats.totalSize,
  usagePercent: stats.usagePercent
});
```

---

## 常见问题

### Q1: 配置更新后何时生效？

**A**: 配置更新后立即生效。配置管理器会通知所有监听器，相关组件会自动应用新配置。

### Q2: 智能预加载策略多久更新一次？

**A**: 每记录10次阅读行为后自动更新一次策略。也可以手动调用 `refreshStrategy()` 立即更新。

### Q3: 磁盘缓存满了会怎样？

**A**: 系统会自动使用LRU策略清理最旧的缓存，为新图片腾出空间。

### Q4: 如何禁用智能预加载？

**A**: 在缓存配置中关闭预加载开关：
```typescript
await configManager.updatePreloadConfig({ enabled: false });
```

### Q5: 配置数据存储在哪里？

**A**: 配置保存在应用的 `preferences` 中，路径为 `cache_config`。

---

## 总结

通过这三个高级功能，我们实现了：

✅ **完全可配置的缓存系统**
- 所有缓存参数可调整
- 配置持久化存储
- 实时生效

✅ **智能化的预加载策略**
- 自动学习用户行为
- 动态调整预加载范围
- 适应不同网络环境

✅ **完善的管理界面**
- 实时显示真实数据
- 可视化配置调整
- 策略执行监控

这些功能共同打造了一个**智能、高效、可控**的缓存系统，显著提升了用户体验。
