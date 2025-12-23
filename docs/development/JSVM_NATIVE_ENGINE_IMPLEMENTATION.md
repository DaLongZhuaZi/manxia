# JSVM Native Engine 实现文档

## 概述

本文档描述了基于 HarmonyOS NEXT JSVM-API 实现的原生 JavaScript 执行引擎，用于替代 WebView 方案执行 Legado 书源的 JS 规则。

## 架构设计

```
┌─────────────────────────────────────────────────────────────┐
│                      ArkTS 层                                │
│  ┌─────────────────┐    ┌─────────────────────────────────┐ │
│  │ LegadoJsEngine  │───▶│ NativeJsEngine                  │ │
│  │ (统一入口)       │    │ (ArkTS封装层)                    │ │
│  └─────────────────┘    └─────────────────────────────────┘ │
└─────────────────────────────────┬───────────────────────────┘
                                  │ import from 'libjsvm_engine.so'
┌─────────────────────────────────▼───────────────────────────┐
│                    Native C++ 层                             │
│  ┌─────────────────────────────────────────────────────────┐│
│  │ jsvm_engine.cpp                                         ││
│  │ - NapiCreateVm()      创建虚拟机实例                     ││
│  │ - NapiDestroyVm()     销毁虚拟机实例                     ││
│  │ - NapiExecuteJs()     执行JS代码                         ││
│  │ - NapiSetGlobalString() 设置全局字符串变量               ││
│  │ - NapiSetGlobalNumber() 设置全局数字变量                 ││
│  └─────────────────────────────────────────────────────────┘│
└─────────────────────────────────┬───────────────────────────┘
                                  │ libjsvm.so
┌─────────────────────────────────▼───────────────────────────┐
│                    JSVM 引擎层                               │
│  HarmonyOS JSVM-API (解释器模式，无需JIT权限)                │
└─────────────────────────────────────────────────────────────┘
```

## 文件结构

```
entry/src/main/
├── cpp/                              # Native C++ 代码
│   ├── CMakeLists.txt               # CMake 编译配置
│   ├── jsvm_engine.cpp              # JSVM 引擎核心实现
│   └── types/
│       └── libjsvm_engine/
│           ├── index.d.ts           # TypeScript 类型定义
│           └── oh-package.json5     # 模块配置
└── ets/
    └── Framework/
        └── Novel/
            ├── NativeJsEngine.ets   # ArkTS 封装层
            └── LegadoJsEngine.ets   # 统一入口（已集成Native引擎）
```

## 核心接口

### ArkTS 层 (NativeJsEngine.ets)

```typescript
// 创建引擎实例
const engine = new NativeJsEngine();
await engine.initialize();

// 执行JS代码
const result = await engine.execute(jsCode, {
  result: '上一步结果',
  baseUrl: 'https://example.com',
  key: '搜索关键字',
  page: 1,
  sourceUrl: '书源URL',
  variables: { customVar: 'value' }
});

// 销毁引擎
engine.destroy();
```

### Native 层 (jsvm_engine.cpp)

| 函数 | 说明 |
|------|------|
| `createVm()` | 创建虚拟机实例，返回 vmId |
| `destroyVm(vmId)` | 销毁指定虚拟机实例 |
| `executeJs(vmId, code)` | 执行JS代码，返回 `{success, result}` |
| `setGlobalString(vmId, name, value)` | 设置全局字符串变量 |
| `setGlobalNumber(vmId, name, value)` | 设置全局数字变量 |
| `getVmCount()` | 获取当前活跃的虚拟机数量 |

## 特性

### 1. 无需 JIT 权限
- 使用 JSVM 解释器模式执行
- 无需申请 `ohos.permission.kernel.ALLOW_EXECUTABLE_FORT_MEMORY` 权限
- 适用于普通应用

### 2. 高性能
- 直接在 Native 层执行，无需 WebView 开销
- 支持虚拟机实例池，避免重复创建销毁
- 使用懒编译（lazy compile）减少启动开销

### 3. Legado 兼容
- 内置 `java` 对象模拟（timeFormat, base64Decode 等）
- 内置 `cookie` 对象模拟
- 内置 `source` 对象模拟
- 支持上下文变量注入（result, baseUrl, key, page 等）

### 4. 降级机制
- Native 引擎初始化失败时自动降级到 WebView
- WebView 不可用时降级到简单表达式求值

## 编译说明

### 前置条件
1. DevEco Studio 5.0+ 
2. HarmonyOS NEXT SDK (API 12+)
3. 项目需要启用 Native 编译支持

### 编译步骤

1. **确保 NDK 配置正确**
   
   在 `entry/build-profile.json5` 中确认包含：
   ```json5
   {
     "buildOption": {
       "externalNativeOptions": {
         "path": "./src/main/cpp/CMakeLists.txt",
         "arguments": "",
         "cppFlags": ""
       }
     }
   }
   ```

2. **同步项目依赖**
   ```bash
   # 在项目根目录执行
   ohpm install
   ```

3. **编译项目**
   ```bash
   # 使用 DevEco Studio 编译，或命令行：
   hvigorw assembleHap
   ```

### 常见问题

**Q: 编译时找不到 libjsvm.so？**

A: 确保 SDK 版本为 HarmonyOS NEXT (API 12+)，JSVM-API 从 API 12 开始提供。

**Q: 运行时 Native 引擎初始化失败？**

A: 检查日志中的错误信息，常见原因：
- 设备不支持 JSVM（模拟器可能不支持）
- SDK 版本过低

**Q: JS 执行结果不正确？**

A: 
- 检查 JS 代码是否使用了不支持的 API
- 复杂的网络请求（java.connect 等）需要在 ArkTS 层实现

## 限制

1. **不支持网络请求**
   - `java.ajax()`, `java.connect()`, `java.get()` 等需要在 ArkTS 层实现
   - Native 层仅提供纯 JS 执行能力

2. **性能**
   - 解释器模式性能低于 JIT 模式
   - 对于简单的 JS 规则影响不大

3. **调试**
   - Native 层调试需要使用 LLDB
   - 建议在 ArkTS 层添加日志

## 后续优化

1. [ ] 实现 HTTP 请求桥接（java.ajax 等）
2. [ ] 添加 Code Cache 支持提升热启动性能
3. [ ] 实现更多 Legado JsExtensions 函数
4. [ ] 添加 JS 执行超时控制
