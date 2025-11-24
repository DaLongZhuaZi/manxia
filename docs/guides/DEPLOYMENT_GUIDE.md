# 部署指南

本指南详细介绍如何构建、测试和部署 RimWorld Framework 应用程序。

## 📋 目录

- [环境准备](#环境准备)
- [构建配置](#构建配置)
- [开发环境部署](#开发环境部署)
- [测试环境部署](#测试环境部署)
- [生产环境部署](#生产环境部署)
- [性能优化](#性能优化)
- [监控和日志](#监控和日志)
- [故障排除](#故障排除)

## 🛠️ 环境准备

### 系统要求

```yaml
# 开发环境要求
development:
  os: Windows 10/11, macOS 10.15+, Ubuntu 18.04+
  node: ">= 16.0.0"
  npm: ">= 8.0.0"
  deveco_studio: ">= 4.0.0"
  hdc: ">= 2.0.0"

# 目标设备要求
target_device:
  harmony_os: ">= 4.0.0"
  api_level: ">= 9"
  memory: ">= 4GB"
  storage: ">= 32GB"
```

### 开发工具安装

```bash
# 1. 安装 DevEco Studio
# 下载地址: https://developer.harmonyos.com/cn/develop/deveco-studio

# 2. 配置 SDK
# 在 DevEco Studio 中配置 HarmonyOS SDK

# 3. 安装 HDC 工具
# HDC 工具用于设备连接和调试

# 4. 验证安装
hdc version
```

## ⚙️ 构建配置

### 项目配置文件

```json
// build-profile.json5
{
  "app": {
    "signingConfigs": [
      {
        "name": "default",
        "type": "HarmonyOS",
        "material": {
          "certpath": "cert/signing-cert.p7b",
          "storePassword": "your_store_password",
          "keyAlias": "your_key_alias",
          "keyPassword": "your_key_password",
          "profile": "cert/signing-profile.p7b",
          "signAlg": "SHA256withECDSA",
          "storeFile": "cert/signing-cert.p12"
        }
      }
    ],
    "compileSdkVersion": 9,
    "compatibleSdkVersion": 9,
    "products": [
      {
        "name": "default",
        "signingConfig": "default",
        "compileSdkVersion": 9,
        "compatibleSdkVersion": 9
      }
    ]
  },
  "modules": [
    {
      "name": "entry",
      "srcPath": "./entry",
      "targets": [
        {
          "name": "default",
          "applyToProducts": ["default"]
        }
      ]
    }
  ]
}
```

### 模块配置

```json
// entry/build-profile.json5
{
  "apiType": "stageMode",
  "buildOption": {
    "sourceOption": {
      "workers": [
        "./src/main/ets/workers/DataWorker.ts"
      ]
    },
    "arkOptions": {
      "obfuscation": {
        "ruleOptions": {
          "enable": true,
          "files": ["./obfuscation-rules.txt"]
        },
        "consumerFiles": ["./consumer-rules.txt"]
      }
    }
  },
  "targets": [
    {
      "name": "default",
      "runtimeOS": "HarmonyOS"
    }
  ]
}
```

### 混淆配置

```text
# obfuscation-rules.txt
# 保持框架核心类不被混淆
-keep class com.rimworld.framework.** { *; }

# 保持导航相关类
-keep class **.*Navigation* { *; }
-keep class **.*Router* { *; }

# 保持动画相关类
-keep class **.*Animation* { *; }

# 保持事件相关类
-keep class **.*Event* { *; }

# 保持日志相关类
-keep class **.*Logger* { *; }

# 保持资源管理类
-keep class **.*Resource* { *; }

# 保持游戏系统类
-keep class **.*Game* { *; }
-keep class **.*Game* { *; }
```

## 🔧 开发环境部署

### 本地开发服务器

```bash
# 1. 安装依赖
npm install

# 2. 启动开发服务器
npm run dev

# 3. 启动预览服务器
npm run serve

# 4. 启动热重载
npm run dev:hot
```

### 开发环境配置

```typescript
// config/development.ts
export const developmentConfig = {
  // 服务器配置
  server: {
    host: 'localhost',
    port: 9000,
    https: false,
    proxy: {
      '/api': {
        target: 'http://localhost:3000',
        changeOrigin: true,
        pathRewrite: {
          '^/api': ''
        }
      }
    }
  },
  
  // 日志配置
  logging: {
    level: 'debug',
    console: true,
    file: false
  },
  
  // 调试配置
  debug: {
    enabled: true,
    showPerformanceMetrics: true,
    showMemoryUsage: true,
    enableHotReload: true
  },
  
  // 资源配置
  resources: {
    baseUrl: '/assets',
    cacheEnabled: false,
    compressionEnabled: false
  }
};
```

### 开发工具脚本

```json
// package.json
{
  "scripts": {
    "dev": "hvigor assembleHap --mode module -p module=entry@default",
    "dev:debug": "hvigor assembleHap --mode module -p module=entry@default --debug",
    "build": "hvigor assembleHap --mode module -p module=entry@default --release",
    "clean": "hvigor clean",
    "test": "npm run test:unit && npm run test:integration",
    "test:unit": "jest --config jest.config.js",
    "test:integration": "jest --config jest.integration.config.js",
    "lint": "eslint src/**/*.ts",
    "lint:fix": "eslint src/**/*.ts --fix",
    "format": "prettier --write src/**/*.ts",
    "analyze": "hvigor assembleHap --mode module -p module=entry@default --analyze",
    "profile": "hvigor assembleHap --mode module -p module=entry@default --profile"
  }
}
```

## 🧪 测试环境部署

### 测试配置

```typescript
// config/testing.ts
export const testingConfig = {
  // 服务器配置
  server: {
    host: 'test.rimworld.local',
    port: 443,
    https: true
  },
  
  // 日志配置
  logging: {
    level: 'info',
    console: true,
    file: true,
    fileRotation: true,
    maxFileSize: '10MB',
    maxFiles: 5
  },
  
  // 测试配置
  testing: {
    mockData: true,
    simulateErrors: true,
    performanceMonitoring: true,
    coverageReporting: true
  },
  
  // 资源配置
  resources: {
    baseUrl: 'https://cdn-test.rimworld.com/assets',
    cacheEnabled: true,
    compressionEnabled: true,
    cdnEnabled: true
  }
};
```

### 自动化测试

```bash
#!/bin/bash
# scripts/test-deploy.sh

set -e

echo "开始测试环境部署..."

# 1. 清理构建目录
echo "清理构建目录..."
npm run clean

# 2. 安装依赖
echo "安装依赖..."
npm ci

# 3. 运行代码检查
echo "运行代码检查..."
npm run lint

# 4. 运行单元测试
echo "运行单元测试..."
npm run test:unit

# 5. 构建应用
echo "构建应用..."
npm run build:test

# 6. 运行集成测试
echo "运行集成测试..."
npm run test:integration

# 7. 运行端到端测试
echo "运行端到端测试..."
npm run test:e2e

# 8. 生成测试报告
echo "生成测试报告..."
npm run test:report

# 9. 部署到测试环境
echo "部署到测试环境..."
npm run deploy:test

echo "测试环境部署完成!"
```

### 测试环境监控

```typescript
// monitoring/test-monitor.ts
class TestEnvironmentMonitor {
  private metrics: Map<string, any> = new Map();
  private alerts: Alert[] = [];
  
  public startMonitoring(): void {
    // 性能监控
    this.monitorPerformance();
    
    // 内存监控
    this.monitorMemory();
    
    // 错误监控
    this.monitorErrors();
    
    // 用户行为监控
    this.monitorUserBehavior();
  }
  
  private monitorPerformance(): void {
    setInterval(() => {
      const performanceData = this.collectPerformanceData();
      this.metrics.set('performance', performanceData);
      
      if (performanceData.responseTime > 1000) {
        this.createAlert('PERFORMANCE_SLOW', '响应时间过慢');
      }
    }, 30000); // 每30秒检查一次
  }
  
  private monitorMemory(): void {
    setInterval(() => {
      const memoryData = this.collectMemoryData();
      this.metrics.set('memory', memoryData);
      
      if (memoryData.usage > 0.8) {
        this.createAlert('MEMORY_HIGH', '内存使用率过高');
      }
    }, 60000); // 每分钟检查一次
  }
  
  private createAlert(type: string, message: string): void {
    const alert: Alert = {
      id: `alert_${Date.now()}`,
      type,
      message,
      timestamp: new Date(),
      severity: this.calculateSeverity(type)
    };
    
    this.alerts.push(alert);
    this.sendAlert(alert);
  }
}
```

## 🚀 生产环境部署

### 生产配置

```typescript
// config/production.ts
export const productionConfig = {
  // 服务器配置
  server: {
    host: 'app.rimworld.com',
    port: 443,
    https: true,
    compression: true,
    caching: true
  },
  
  // 安全配置
  security: {
    enableCSP: true,
    enableHSTS: true,
    enableXSSProtection: true,
    enableFrameGuard: true,
    rateLimiting: {
      enabled: true,
      maxRequests: 100,
      windowMs: 60000
    }
  },
  
  // 日志配置
  logging: {
    level: 'warn',
    console: false,
    file: true,
    fileRotation: true,
    maxFileSize: '50MB',
    maxFiles: 10,
    remoteLogging: true
  },
  
  // 性能配置
  performance: {
    enableGzip: true,
    enableBrotli: true,
    enableCaching: true,
    cacheMaxAge: 31536000, // 1年
    enableCDN: true,
    enableLazyLoading: true
  },
  
  // 监控配置
  monitoring: {
    enabled: true,
    metricsInterval: 60000,
    alerting: true,
    healthCheck: true
  }
};
```

### 生产部署脚本

```bash
#!/bin/bash
# scripts/production-deploy.sh

set -e

echo "开始生产环境部署..."

# 检查环境变量
if [ -z "$PRODUCTION_KEY" ]; then
  echo "错误: 未设置 PRODUCTION_KEY 环境变量"
  exit 1
fi

# 1. 备份当前版本
echo "备份当前版本..."
./scripts/backup-current.sh

# 2. 清理构建目录
echo "清理构建目录..."
npm run clean

# 3. 安装生产依赖
echo "安装生产依赖..."
npm ci --only=production

# 4. 运行完整测试套件
echo "运行完整测试套件..."
npm run test:full

# 5. 构建生产版本
echo "构建生产版本..."
npm run build:production

# 6. 运行安全扫描
echo "运行安全扫描..."
npm run security:scan

# 7. 运行性能测试
echo "运行性能测试..."
npm run test:performance

# 8. 生成构建报告
echo "生成构建报告..."
npm run build:report

# 9. 部署到生产环境
echo "部署到生产环境..."
npm run deploy:production

# 10. 运行健康检查
echo "运行健康检查..."
./scripts/health-check.sh

# 11. 发送部署通知
echo "发送部署通知..."
./scripts/notify-deployment.sh

echo "生产环境部署完成!"
```

### 蓝绿部署

```typescript
// deployment/blue-green.ts
class BlueGreenDeployment {
  private currentEnvironment: 'blue' | 'green' = 'blue';
  private environments = {
    blue: {
      url: 'https://blue.rimworld.com',
      status: 'active'
    },
    green: {
      url: 'https://green.rimworld.com',
      status: 'standby'
    }
  };
  
  public async deploy(version: string): Promise<void> {
    const targetEnv = this.currentEnvironment === 'blue' ? 'green' : 'blue';
    
    try {
      // 1. 部署到目标环境
      await this.deployToEnvironment(targetEnv, version);
      
      // 2. 运行健康检查
      await this.healthCheck(targetEnv);
      
      // 3. 运行烟雾测试
      await this.smokeTest(targetEnv);
      
      // 4. 切换流量
      await this.switchTraffic(targetEnv);
      
      // 5. 验证切换
      await this.verifySwitch(targetEnv);
      
      // 6. 更新当前环境
      this.currentEnvironment = targetEnv;
      
      logger.info('蓝绿部署完成', { version, environment: targetEnv });
      
    } catch (error) {
      logger.error('蓝绿部署失败', error);
      
      // 回滚操作
      await this.rollback();
      throw error;
    }
  }
  
  private async deployToEnvironment(env: 'blue' | 'green', version: string): Promise<void> {
    // 部署到指定环境
  }
  
  private async healthCheck(env: 'blue' | 'green'): Promise<void> {
    // 健康检查
  }
  
  private async smokeTest(env: 'blue' | 'green'): Promise<void> {
    // 烟雾测试
  }
  
  private async switchTraffic(env: 'blue' | 'green'): Promise<void> {
    // 切换流量
  }
  
  private async rollback(): Promise<void> {
    // 回滚操作
  }
}
```

## ⚡ 性能优化

### 构建优化

```typescript
// build/optimization.ts
export const buildOptimization = {
  // 代码分割
  codeSplitting: {
    enabled: true,
    chunks: {
      vendor: ['@ohos/*'],
      common: ['./src/common/**'],
      pages: ['./src/pages/**']
    }
  },
  
  // 压缩配置
  compression: {
    enabled: true,
    algorithm: 'gzip',
    level: 9,
    threshold: 1024
  },
  
  // 资源优化
  assets: {
    imageOptimization: true,
    fontSubsetting: true,
    cssMinification: true,
    jsMinification: true
  },
  
  // 缓存配置
  caching: {
    enabled: true,
    strategy: 'content-hash',
    maxAge: 31536000 // 1年
  }
};
```

### 运行时优化

```typescript
// performance/runtime-optimization.ts
class RuntimeOptimizer {
  private performanceObserver: PerformanceObserver;
  private memoryMonitor: MemoryMonitor;
  
  constructor() {
    this.setupPerformanceMonitoring();
    this.setupMemoryMonitoring();
  }
  
  private setupPerformanceMonitoring(): void {
    this.performanceObserver = new PerformanceObserver((list) => {
      const entries = list.getEntries();
      
      entries.forEach(entry => {
        if (entry.duration > 100) {
          logger.performance('性能警告', {
            name: entry.name,
            duration: entry.duration,
            type: entry.entryType
          });
        }
      });
    });
    
    this.performanceObserver.observe({ 
      entryTypes: ['measure', 'navigation', 'resource'] 
    });
  }
  
  private setupMemoryMonitoring(): void {
    setInterval(() => {
      const memoryInfo = this.getMemoryInfo();
      
      if (memoryInfo.usedJSHeapSize > memoryInfo.totalJSHeapSize * 0.8) {
        logger.performance('内存使用率过高', memoryInfo);
        this.triggerGarbageCollection();
      }
    }, 30000);
  }
  
  private getMemoryInfo(): any {
    // 获取内存信息
    return {
      usedJSHeapSize: 0,
      totalJSHeapSize: 0,
      jsHeapSizeLimit: 0
    };
  }
  
  private triggerGarbageCollection(): void {
    // 触发垃圾回收
  }
}
```

## 📊 监控和日志

### 应用监控

```typescript
// monitoring/app-monitor.ts
class ApplicationMonitor {
  private metrics: MetricsCollector;
  private alertManager: AlertManager;
  
  constructor() {
    this.metrics = new MetricsCollector();
    this.alertManager = new AlertManager();
    this.startMonitoring();
  }
  
  private startMonitoring(): void {
    // 应用性能监控
    this.monitorApplicationPerformance();
    
    // 用户体验监控
    this.monitorUserExperience();
    
    // 错误监控
    this.monitorErrors();
    
    // 业务指标监控
    this.monitorBusinessMetrics();
  }
  
  private monitorApplicationPerformance(): void {
    setInterval(() => {
      const metrics = {
        responseTime: this.measureResponseTime(),
        throughput: this.measureThroughput(),
        errorRate: this.calculateErrorRate(),
        cpuUsage: this.getCpuUsage(),
        memoryUsage: this.getMemoryUsage()
      };
      
      this.metrics.record('app_performance', metrics);
      
      // 检查阈值
      if (metrics.responseTime > 1000) {
        this.alertManager.sendAlert('HIGH_RESPONSE_TIME', metrics);
      }
      
      if (metrics.errorRate > 0.05) {
        this.alertManager.sendAlert('HIGH_ERROR_RATE', metrics);
      }
    }, 60000);
  }
  
  private monitorUserExperience(): void {
    // 页面加载时间
    this.trackPageLoadTime();
    
    // 用户交互响应时间
    this.trackInteractionTime();
    
    // 用户满意度指标
    this.trackUserSatisfaction();
  }
}
```

### 日志聚合

```typescript
// logging/log-aggregator.ts
class LogAggregator {
  private logBuffer: LogEntry[] = [];
  private batchSize: number = 100;
  private flushInterval: number = 30000;
  
  constructor() {
    this.startBatchProcessing();
  }
  
  public addLog(entry: LogEntry): void {
    this.logBuffer.push(entry);
    
    if (this.logBuffer.length >= this.batchSize) {
      this.flushLogs();
    }
  }
  
  private startBatchProcessing(): void {
    setInterval(() => {
      if (this.logBuffer.length > 0) {
        this.flushLogs();
      }
    }, this.flushInterval);
  }
  
  private async flushLogs(): Promise<void> {
    const logs = this.logBuffer.splice(0, this.batchSize);
    
    try {
      await this.sendLogsToServer(logs);
    } catch (error) {
      // 发送失败，重新加入缓冲区
      this.logBuffer.unshift(...logs);
      logger.error('日志发送失败', error);
    }
  }
  
  private async sendLogsToServer(logs: LogEntry[]): Promise<void> {
    // 发送日志到服务器
  }
}
```

## 🔧 故障排除

### 常见问题

```typescript
// troubleshooting/common-issues.ts
export const commonIssues = {
  // 构建问题
  buildIssues: {
    'MODULE_NOT_FOUND': {
      description: '模块未找到错误',
      solutions: [
        '检查模块路径是否正确',
        '确认依赖是否已安装',
        '清理 node_modules 并重新安装',
        '检查 tsconfig.json 配置'
      ]
    },
    
    'COMPILATION_ERROR': {
      description: '编译错误',
      solutions: [
        '检查 TypeScript 语法错误',
        '确认类型定义是否正确',
        '检查导入导出语句',
        '更新 TypeScript 版本'
      ]
    }
  },
  
  // 运行时问题
  runtimeIssues: {
    'NAVIGATION_ERROR': {
      description: '导航错误',
      solutions: [
        '检查页面路径配置',
        '确认页面组件是否存在',
        '检查导航参数格式',
        '查看导航栈状态'
      ]
    },
    
    'ANIMATION_ERROR': {
      description: '动画错误',
      solutions: [
        '检查动画配置参数',
        '确认目标元素是否存在',
        '检查动画时序',
        '查看动画冲突'
      ]
    }
  },
  
  // 性能问题
  performanceIssues: {
    'MEMORY_LEAK': {
      description: '内存泄漏',
      solutions: [
        '检查事件监听器是否正确移除',
        '确认定时器是否已清理',
        '检查循环引用',
        '使用内存分析工具'
      ]
    },
    
    'SLOW_RENDERING': {
      description: '渲染缓慢',
      solutions: [
        '优化组件渲染逻辑',
        '使用虚拟列表',
        '减少不必要的重渲染',
        '优化图片资源'
      ]
    }
  }
};
```

### 诊断工具

```typescript
// troubleshooting/diagnostic-tools.ts
class DiagnosticTools {
  public static async runDiagnostics(): Promise<DiagnosticReport> {
    const report: DiagnosticReport = {
      timestamp: new Date(),
      system: await this.getSystemInfo(),
      performance: await this.getPerformanceInfo(),
      memory: await this.getMemoryInfo(),
      network: await this.getNetworkInfo(),
      errors: await this.getErrorInfo()
    };
    
    return report;
  }
  
  private static async getSystemInfo(): Promise<SystemInfo> {
    return {
      platform: 'HarmonyOS',
      version: '4.0.0',
      device: 'Unknown',
      screen: {
        width: 1080,
        height: 2340,
        density: 3.0
      }
    };
  }
  
  private static async getPerformanceInfo(): Promise<PerformanceInfo> {
    return {
      fps: 60,
      frameDrops: 0,
      renderTime: 16.67,
      jsExecutionTime: 5.2
    };
  }
  
  private static async getMemoryInfo(): Promise<MemoryInfo> {
    return {
      total: 8 * 1024 * 1024 * 1024, // 8GB
      used: 2 * 1024 * 1024 * 1024,  // 2GB
      available: 6 * 1024 * 1024 * 1024, // 6GB
      jsHeapSize: 50 * 1024 * 1024 // 50MB
    };
  }
  
  public static generateReport(report: DiagnosticReport): string {
    return `
# 诊断报告

## 系统信息
- 平台: ${report.system.platform}
- 版本: ${report.system.version}
- 设备: ${report.system.device}

## 性能信息
- FPS: ${report.performance.fps}
- 掉帧数: ${report.performance.frameDrops}
- 渲染时间: ${report.performance.renderTime}ms

## 内存信息
- 总内存: ${(report.memory.total / 1024 / 1024 / 1024).toFixed(2)}GB
- 已用内存: ${(report.memory.used / 1024 / 1024 / 1024).toFixed(2)}GB
- JS堆大小: ${(report.memory.jsHeapSize / 1024 / 1024).toFixed(2)}MB

## 错误信息
${report.errors.map(error => `- ${error.message}`).join('\n')}
    `;
  }
}
```

### 自动修复工具

```bash
#!/bin/bash
# scripts/auto-fix.sh

echo "运行自动修复工具..."

# 1. 清理缓存
echo "清理缓存..."
npm run clean
rm -rf node_modules/.cache
rm -rf .hvigor

# 2. 重新安装依赖
echo "重新安装依赖..."
rm -rf node_modules
npm install

# 3. 修复代码格式
echo "修复代码格式..."
npm run lint:fix
npm run format

# 4. 更新依赖
echo "检查依赖更新..."
npm audit fix

# 5. 重新构建
echo "重新构建..."
npm run build

echo "自动修复完成!"
```

---

*最后更新: 2024年12月*