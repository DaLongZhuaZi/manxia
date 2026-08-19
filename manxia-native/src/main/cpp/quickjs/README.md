# QuickJS Engine for HarmonyOS

## 概述
这是QuickJS JavaScript引擎的HarmonyOS移植版本，用于替代/补充现有的JSVM引擎，
以更好地支持Legado书源的JavaScript执行。

## 目录结构
```
quickjs/
├── README.md              # 本文件
├── CMakeLists.txt         # CMake构建配置
├── quickjs/               # QuickJS源码（已下载）
│   ├── quickjs.h
│   ├── quickjs.c
│   ├── quickjs-libc.h
│   ├── quickjs-libc.c
│   └── ...
├── quickjs_napi.cpp       # NAPI绑定层
├── legado_api_full.cpp    # Legado兼容API完整实现
├── legado_api.h           # Legado API头文件
└── types/                 # TypeScript类型定义
    └── libquickjs_engine/
        ├── index.d.ts
        └── oh-package.json5
```

## 如何撤销
如果需要完全撤销QuickJS移植，只需：
1. 删除整个 `entry/src/main/cpp/quickjs/` 目录
2. 从 `entry/src/main/cpp/CMakeLists.txt` 中移除 `add_subdirectory(quickjs)` 行

## 构建说明
QuickJS源码已从官方下载（版本2024-01-13）。

编译项目：
```bash
cd <project_root>
hvigorw assembleHap
```

## 已实现的Legado API
- **java对象**: get, put, log, toast, longToast, base64Encode, base64Decode, hexDecodeToString, md5Encode, encodeURI, randomUUID, androidId, deviceID, ajax
- **source对象**: getVariable, setVariable, getLoginInfo, getLoginInfoMap, getKey, bookSourceUrl, bookSourceName
- **cookie对象**: getCookie, setCookie, removeCookie
- **book对象**: getVariable, putVariable, name, author, bookUrl, durChapterIndex
- **chapter对象**: index, title, url
- **cache对象**: get, put, getMemory, putMemory
- **全局变量**: key, page, result, baseUrl, sourceUrl
- **Polyfills**: JavaImporter, Packages, putLoginInfo

## ArkTS调用示例
```typescript
import quickjs from 'libquickjs_engine.so';

// 初始化引擎
quickjs.init();

// 设置书源信息
quickjs.setSourceInfo(sourceUrl, sourceName, jsLib);

// 执行JS代码
const result = quickjs.execute(code, key, page, prevResult, baseUrl);
if (result.success) {
  console.log('Result:', result.result);
} else {
  console.error('Error:', result.error);
}

// 销毁引擎
quickjs.destroy();
```

## 状态
- [x] 下载QuickJS源码
- [x] 配置CMake编译
- [x] 创建NAPI绑定
- [x] 实现Legado API
- [ ] 集成到LegadoJsEngine
- [ ] 测试书源执行
