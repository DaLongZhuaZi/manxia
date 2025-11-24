# 页面健康检查系统使用指南

## 概述

页面健康检查系统是一个全面的页面监控和诊断工具，用于实时监控页面的健康状态、性能指标和用户交互情况。

## 核心功能

### 1. 健康状态监控
- **HEALTHY**: 页面运行正常
- **WARNING**: 页面有警告，但仍可正常使用
- **ERROR**: 页面出现错误，可能影响功能
- **UNKNOWN**: 页面状态未知

### 2. 性能指标收集
- 帧率 (FPS)
- 渲染耗时
- 内存使用量
- CPU使用率
- 网络请求数
- 缓存命中率

### 3. 用户交互统计
- 交互次数统计
- 最后交互时间
- 交互类型记录

### 4. 健康评分系统
- 基于多维度指标的0-100分评分
- 实时计算页面健康程度
- 可视化健康状态

## 使用方法

### 1. 页面集成

所有页面都应该使用 `BasePageWithHealth` 基类：

```typescript
import { BasePageWithHealth } from '../Framework/Base/BasePageWithHealth';
import { PageHealthStatus } from '../Framework/Managers/NavigationLifecycleManager';

@Component
export struct YourPage {
  // 页面健康检查基类
  private healthChecker = new BasePageWithHealth('YourPageName');
  
  aboutToAppear() {
    // 初始化页面健康检查
    this.healthChecker.onPageShow();
    this.healthChecker.onRenderStart();
  }
  
  aboutToDisappear() {
    // 清理页面健康检查
    this.healthChecker.onPageHide();
    this.healthChecker.onDestroy();
  }
}
```

### 2. 生命周期方法

#### 页面显示/隐藏
```typescript
// 页面显示时
this.healthChecker.onPageShow();

// 页面隐藏时
this.healthChecker.onPageHide();
```

#### 渲染生命周期
```typescript
// 开始渲染
this.healthChecker.onRenderStart();

// 渲染完成
this.healthChecker.onRenderComplete();
```

#### 加载生命周期
```typescript
// 加载完成
this.healthChecker.onLoadComplete();
```

### 3. 用户交互报告

```typescript
// 报告用户交互
this.healthChecker.onUserInteraction('button_click');
this.healthChecker.onUserInteraction('scroll');
this.healthChecker.onUserInteraction('touch');
```

### 4. 错误和警告报告

```typescript
// 报告错误
this.healthChecker.reportError('网络请求失败');

// 报告警告
this.healthChecker.reportWarning('加载时间过长');
```

### 5. 手动健康状态更新

```typescript
import { PageHealthStatus, PageHealthDetails } from '../Framework/Managers/NavigationLifecycleManager';

// 更新健康状态
this.healthChecker.updateHealthStatus(PageHealthStatus.HEALTHY, {
  isVisible: true,
  renderTime: 16,
  memoryUsage: 50 * 1024 * 1024, // 50MB
  performanceMetrics: {
    frameRate: 60,
    renderDuration: 16,
    cpuUsage: 25
  }
});
```

## 健康检查日志

### 日志级别和格式

#### 信息日志
```
🆕 创建页面健康信息: LoadingPage
👁️ 页面显示 [MainMenuPage]
🚀 页面加载完成 [GamePage] - 耗时: 1200ms
```

#### 状态变化日志
```
🟢 页面健康状态变化 [LoadingPage]: UNKNOWN → HEALTHY (评分: 85)
⚠️ 页面健康状态变化 [GamePage]: HEALTHY → WARNING (评分: 65)
```

#### 详细健康信息
```
📊 页面健康详情 [GamePage]: 渲染时间: 16ms, 内存使用: 45.2MB, 帧率: 58fps, CPU: 23%
```

#### 健康检查汇总
```
📈 页面健康检查完成 - 健康: 2, 警告: 1, 错误: 0, 未知: 0 (健康率: 75%)
```

#### 问题页面详情
```
🚨 问题页面详情:
⚠️ GamePage (评分: 65) - 帧率过低
❌ LoadingPage (评分: 30) - 加载超时
```

### 性能警告日志

```
🧠 页面内存使用过高 [GamePage]: 150.5MB
🎯 页面帧率过低 [GamePage]: 12fps
⏱️ 页面渲染耗时过长 [LoadingPage]: 120ms
💻 页面CPU使用率过高 [GamePage]: 85%
⚠️ 页面长时间未更新 [MainMenuPage]: 2分30秒 (阈值: 30秒)
```

## 健康评分系统

### 评分规则

#### 基础分数: 100分

#### 扣分项目
- 每个错误: -20分
- 每个警告: -5分
- ERROR状态: -30分
- WARNING状态: -15分
- UNKNOWN状态: -10分

#### 性能加分/扣分
- 帧率 ≥60fps: +5分
- 帧率 ≥30fps: +2分
- 帧率 <15fps: -10分
- 渲染时间 ≤16ms: +3分
- 渲染时间 ≤33ms: +1分
- 渲染时间 >100ms: -5分
- 内存使用 <50MB: +2分
- 内存使用 >200MB: -5分

#### 交互活跃度加分
- 用户交互次数 / 10，最多+5分

### 评分图标
- 🟢 90-100分: 优秀
- 🟡 70-89分: 良好
- 🟠 50-69分: 一般
- 🔴 0-49分: 需要改进

## 最佳实践

### 1. 及时报告状态变化
```typescript
// 在关键操作前后报告状态
this.healthChecker.onRenderStart();
// ... 执行渲染操作
this.healthChecker.onRenderComplete();
```

### 2. 捕获和报告错误
```typescript
try {
  // 执行可能出错的操作
  await this.loadData();
} catch (error) {
  this.healthChecker.reportError(`数据加载失败: ${error.message}`);
}
```

### 3. 监控性能指标
```typescript
// 定期更新性能指标
setInterval(() => {
  this.healthChecker.updateHealthStatus(PageHealthStatus.HEALTHY, {
    performanceMetrics: {
      frameRate: this.getCurrentFPS(),
      memoryUsage: this.getMemoryUsage(),
      cpuUsage: this.getCPUUsage()
    }
  });
}, 5000);
```

### 4. 用户交互追踪
```typescript
// 在所有用户交互点添加报告
Button('确定')
  .onClick(() => {
    this.healthChecker.onUserInteraction('confirm_button');
    this.handleConfirm();
  })
```

## 故障排除

### 常见问题

1. **页面长时间未更新警告**
   - 确保在页面活动时定期调用健康检查方法
   - 检查是否有阻塞主线程的操作

2. **内存使用过高警告**
   - 检查是否有内存泄漏
   - 及时清理不需要的资源

3. **帧率过低警告**
   - 优化渲染逻辑
   - 减少复杂的UI操作

4. **健康评分过低**
   - 查看详细日志找出问题原因
   - 针对性优化相关指标

### 调试技巧

1. **启用详细日志**
   ```typescript
   // 在开发环境启用debug级别日志
   logger.setLevel('debug');
   ```

2. **查看健康检查汇总**
   - 每5秒自动输出健康检查汇总
   - 关注健康率变化趋势

3. **监控问题页面**
   - 重点关注WARNING和ERROR状态的页面
   - 查看具体错误信息和性能指标

## 配置选项

### 健康检查间隔
```typescript
// 在NavigationLifecycleManager中配置
private readonly HEALTH_CHECK_INTERVAL = 5000; // 5秒
```

### 超时阈值
```typescript
// 页面状态更新超时阈值
private readonly HEALTH_CHECK_STALE_THRESHOLD = 30000; // 30秒
```

### 性能阈值
```typescript
// 可以在BasePageWithHealth中自定义阈值
private readonly MEMORY_WARNING_THRESHOLD = 100 * 1024 * 1024; // 100MB
private readonly FPS_WARNING_THRESHOLD = 15; // 15fps
private readonly RENDER_TIME_WARNING_THRESHOLD = 100; // 100ms
```

通过正确使用页面健康检查系统，可以实时监控应用的健康状态，及时发现和解决问题，提升用户体验。