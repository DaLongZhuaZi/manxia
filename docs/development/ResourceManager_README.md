# ResourceManager 资源管理器重构说明

## 概述

本次重构基于HarmonyOS Next官方API，实现了一个功能完整、性能优化的资源管理框架，支持元数据定义、依赖关系管理、智能缓存、预加载、统计监控等高级功能。

## 主要特性

### 1. 官方API集成
- **@kit.LocalizationKit**: 用于应用内静态资源访问
- **@kit.MediaLibraryKit**: 用于系统媒体资源访问
- **@kit.CoreFileKit**: 用于文件选择和外部文件访问
- **@ohos.file.fs**: 用于文件系统操作

### 2. 资源元数据管理
- 支持JSON配置文件定义资源信息
- 包含类型、路径、依赖关系、预加载策略等
- 支持多设备和多语言适配

### 3. 依赖关系管理
- 自动解析和加载资源依赖
- 支持复杂依赖树结构
- 确保依赖资源优先加载

### 4. 智能缓存系统
- 内存缓存实现，支持TTL过期
- 自动内存使用量估算
- 缓存命中率统计
- 支持手动缓存清理

### 5. 预加载机制
- 支持关键资源预加载
- 基于优先级的加载策略
- 在AbilityStage生命周期中执行

### 6. 多媒体资源支持
- 图片资源（PNG、JPG等）
- 音频资源（MP3、WAV等）
- 视频资源（MP4、AVI等）
- 字体资源（TTF、OTF等）
- JSON配置文件
- 文本文件
- 二进制数据

### 7. 内存管理
- 智能内存使用量估算
- 自动内存清理机制
- 内存使用统计和监控
- 支持手动内存释放

### 8. 统计与监控
- 资源加载统计
- 缓存命中率分析
- 内存使用监控
- 平均加载时间统计

## 文件结构

```
entry/src/main/
├── ets/Framework/Core/
│   └── ResourceManager.ets          # 重构后的资源管理器
├── ets/Framework/Examples/
│   └── ResourceManagerExample.ets   # 使用示例
└── resources/rawfile/
    └── resources_metadata.json      # 资源元数据配置
```

## 配置文件说明

### resources_metadata.json

```json
{
  "resource_id": {
    "type": "IMAGE|AUDIO|VIDEO|TEXT|JSON|BINARY|FONT",
    "path": "资源路径",
    "priority": 1-10,
    "preload": true|false,
    "persistent": true|false,
    "dependencies": ["依赖资源ID"],
    "metadata": {
      "description": "资源描述",
      "format": "文件格式",
      "其他自定义属性": "值"
    }
  }
}
```

**字段说明：**
- `type`: 资源类型枚举
- `path`: 资源路径，支持app.media.、app.rawfile.、外部文件路径
- `priority`: 优先级（1-10，10最高）
- `preload`: 是否预加载
- `persistent`: 是否持久化缓存
- `dependencies`: 依赖的其他资源ID数组
- `metadata`: 自定义元数据

## 使用方法

### 1. 基础初始化

```typescript
import { ResourceManager } from '../Framework/Core/ResourceManager';

// 获取单例实例
const resourceManager = ResourceManager.getInstance();

// 初始化
await resourceManager.initialize();
```

### 2. 在AbilityStage中预加载

```typescript
import { AbilityStage } from '@kit.AbilityKit';
import { ResourceManager } from '../Framework/Core/ResourceManager';

export default class MyAbilityStage extends AbilityStage {
  async onCreate() {
    const resourceManager = ResourceManager.getInstance();
    await resourceManager.initialize();
    
    // 预加载关键资源
    await resourceManager.preloadCriticalResources();
  }
}
```

### 3. 加载资源

```typescript
// 加载图片
const logoImage = await resourceManager.loadResource<PixelMap>('image_logo');

// 加载配置文件
const config = await resourceManager.loadResource<Record<string, any>>('config_game');

// 加载音频
const audioData = await resourceManager.loadResource<Uint8Array>('audio_bgm');
```

### 4. 动态注册资源

```typescript
import { ResourceDescriptor, ResourceType } from '../Framework/Core/ResourceManager';

const descriptor: ResourceDescriptor = {
  id: 'dynamic_texture',
  type: ResourceType.IMAGE,
  path: 'app.media.dynamic_texture',
  priority: 5,
  preload: false,
  persistent: false
};

resourceManager.registerResource(descriptor);
```

### 5. 缓存管理

```typescript
// 获取缓存统计
const cacheStats = resourceManager.getCacheStatistics();
logger.info('ResourceManager', `缓存大小: ${cacheStats.size}, 内存使用: ${cacheStats.memoryUsage} bytes`);

// 清理缓存
resourceManager.clearCache();
```

### 6. 内存管理

```typescript
// 获取资源统计
const stats = resourceManager.getStatistics();
logger.info('ResourceManager', `内存使用: ${stats.memoryUsage} bytes`);
logger.info('ResourceManager', `缓存命中率: ${stats.cacheHitRate}%`);

// 执行内存清理
await resourceManager.cleanupMemory();
```

### 7. 在UI组件中使用

```typescript
@Component
struct MyComponent {
  @State private image: PixelMap | null = null;
  private resourceManager = ResourceManager.getInstance();

  async aboutToAppear() {
    this.image = await this.resourceManager.loadResource('image_logo');
  }

  build() {
    Column() {
      if (this.image) {
        Image(this.image)
          .width(200)
          .height(200)
      }
    }
  }
}
```

## 资源路径规范

### 1. 应用内静态资源
- 媒体资源: `app.media.resource_name`
- 原始文件: `app.rawfile.path/to/file`
- 字符串资源: `app.string.resource_name`

### 2. 外部文件
- 绝对路径: `/data/storage/el2/base/haps/entry/files/resource.png`
- 相对路径: `files/resource.png`

## 性能优化建议

### 1. 预加载策略
- 将关键资源设置为 `preload: true`
- 合理设置资源优先级（priority）
- 在AbilityStage中执行预加载

### 2. 缓存策略
- 频繁使用的资源设置为 `persistent: true`
- 定期清理不必要的缓存
- 监控内存使用情况

### 3. 依赖管理
- 合理设计资源依赖关系
- 避免循环依赖
- 将共同依赖提取为独立资源

### 4. 内存管理
- 及时释放不再使用的资源
- 使用 `cleanupMemory()` 进行定期清理
- 监控内存使用统计

## 错误处理

资源管理器集成了完整的错误处理机制：

```typescript
try {
  const resource = await resourceManager.loadResource('some_resource');
} catch (error) {
  if (error.code === 'RESOURCE_NOT_REGISTERED') {
    // 处理资源未注册错误
  } else if (error.code === 'RESOURCE_LOAD_FAILED') {
    // 处理资源加载失败错误
  }
}
```

## 事件系统

资源管理器支持事件监听：

```typescript
import { eventBus, GameEvent } from '../Framework/EventBus';

// 监听资源加载完成事件
eventBus.subscribe(GameEvent.RESOURCE_LOADED, (payload) => {
  logger.info('EventBus', `资源加载完成: ${payload.resourceId}`);
});

// 监听资源加载失败事件
eventBus.subscribe(GameEvent.RESOURCE_LOAD_FAILED, (payload) => {
  logger.error('EventBus', `资源加载失败: ${payload.resourceId}`);
});
```

## 注意事项

1. **权限申请**: 访问系统媒体资源需要申请相应权限（如 `ohos.permission.READ_IMAGEVIDEO`）
2. **内存限制**: 注意监控内存使用，避免内存溢出
3. **线程安全**: 资源管理器是线程安全的，可在多线程环境中使用
4. **生命周期**: 在应用退出时调用 `dispose()` 释放资源
5. **路径格式**: 确保资源路径格式正确，区分应用内资源和外部文件

## 示例项目

完整的使用示例请参考 `ResourceManagerExample.ets` 文件，包含：
- 基础资源加载
- 依赖关系管理
- 动态资源注册
- 缓存管理
- 内存管理
- 多媒体资源加载
- UI组件集成

通过这些示例，您可以快速了解和使用重构后的资源管理器的各项功能。