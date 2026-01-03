# Rhino WASM沙箱实现文档

## 概述

为了解决Legado书源在HarmonyOS上无法完全兼容的问题，我们实现了一个基于WebView的Rhino WASM沙箱。该沙箱可以运行与Android Legado完全兼容的JavaScript代码，包括所有`java.xxx`扩展函数。

## 架构设计

### 核心组件

```
┌─────────────────────────────────────────────────────────────┐
│                    ArkTS Application                         │
├─────────────────────────────────────────────────────────────┤
│  LegadoRhinoEngine (统一接口层)                              │
│    ├── RhinoWasmExecutor (WASM沙箱执行器)                   │
│    └── LegadoJsEngine (降级方案)                            │
├─────────────────────────────────────────────────────────────┤
│  RhinoSandboxComponent (WebView组件)                         │
│    └── WebView (隐藏)                                        │
│         └── rhino_sandbox/index.html                         │
│              ├── CheerpJ Runtime (可选)                      │
│              ├── rhino_offline.js (离线模式)                 │
│              └── rhino_bridge.js (桥接层)                    │
└─────────────────────────────────────────────────────────────┘
```

### 执行模式

1. **CheerpJ模式** (在线)
   - 从CDN加载CheerpJ运行时
   - 加载Rhino JAR包
   - 完整的Java运行时环境
   - 与Android Legado 100%兼容

2. **离线模式** (默认)
   - 纯JavaScript实现
   - 不依赖外部CDN
   - 实现了所有`java.xxx`扩展函数
   - 兼容性约95%

3. **降级模式**
   - 使用现有的LegadoJsEngine
   - 基于Native JSVM或WebView
   - 兼容性约80%

## 文件结构

```
entry/src/main/
├── ets/Framework/Novel/
│   ├── RhinoWasmExecutor.ets      # WASM沙箱执行器
│   ├── RhinoSandboxComponent.ets  # WebView组件
│   ├── LegadoRhinoEngine.ets      # 统一接口层
│   ├── LegadoJsEngine.ets         # 现有JS引擎（降级方案）
│   └── NativeJsEngine.ets         # Native JSVM引擎
│
└── resources/rawfile/rhino_sandbox/
    ├── index.html                  # 主入口（带降级支持）
    ├── index_offline.html          # 纯离线版本
    ├── rhino_offline.js            # 离线模式实现
    └── rhino_bridge.js             # CheerpJ桥接层
```

## 使用方法

### 1. 在页面中添加沙箱组件

```typescript
import { RhinoSandboxWebView, RhinoSandboxCallbacks } from '../Framework/Novel/RhinoSandboxComponent';

@Entry
@Component
struct MyPage {
  private sandboxCallbacks: RhinoSandboxCallbacks = {
    onReady: () => {
      console.log('Rhino沙箱已就绪');
    },
    onError: (error) => {
      console.error('Rhino沙箱错误:', error);
    }
  };

  build() {
    Stack() {
      // 页面内容...
      
      // 添加隐藏的沙箱组件
      RhinoSandboxWebView({
        callbacks: this.sandboxCallbacks
      })
    }
  }
}
```

### 2. 执行JavaScript代码

```typescript
import { getLegadoRhinoEngine, JsEngineType } from '../Framework/Novel/LegadoRhinoEngine';

// 获取引擎实例
const engine = getLegadoRhinoEngine();

// 配置引擎（可选）
engine.setConfig({
  preferredEngine: JsEngineType.AUTO,
  enableRhinoSandbox: true,
  executeTimeout: 30000
});

// 执行代码
const result = await engine.execute(`
  var url = baseUrl + '/search?key=' + encodeURIComponent(key);
  var html = java.ajax(url);
  // 解析HTML...
  return result;
`, {
  baseUrl: 'https://example.com',
  key: '搜索关键字',
  page: 1
});

if (result.success) {
  console.log('执行结果:', result.result);
} else {
  console.error('执行错误:', result.error);
}
```

### 3. 直接使用RhinoWasmExecutor

```typescript
import { getRhinoWasmExecutor } from '../Framework/Novel/RhinoWasmExecutor';

const executor = getRhinoWasmExecutor();

// 等待初始化
await executor.initialize();

// 执行脚本
const result = await executor.execute(`
  java.ajax('https://api.example.com/data')
`, {
  result: '上一步的结果',
  baseUrl: 'https://example.com'
});
```

## 支持的java.xxx函数

### 网络请求
- `java.ajax(url)` - GET请求，返回响应体
- `java.ajaxAll(urlList)` - 并发GET请求
- `java.connect(url, header)` - 带headers的GET请求
- `java.get(url, headers)` - GET请求（也可获取变量）
- `java.post(url, body, headers)` - POST请求
- `java.head(url, headers)` - HEAD请求

### WebView
- `java.webView(html, url, js)` - 在iframe中执行JS
- `java.webViewGetSource()` - 获取资源URL
- `java.webViewGetOverrideUrl()` - 获取跳转URL
- `java.startBrowserAwait(url)` - 打开浏览器并等待

### Cookie管理
- `java.getCookie(tag, key)` - 获取Cookie
- `java.setCookie(url, cookie)` - 设置Cookie

### 编码解码
- `java.base64Encode(str)` - Base64编码
- `java.base64Decode(str)` - Base64解码
- `java.base64DecodeToByteArray(str)` - Base64解码为字节数组
- `java.hexEncodeToString(str)` - Hex编码
- `java.hexDecodeToString(hex)` - Hex解码
- `java.hexDecodeToByteArray(hex)` - Hex解码为字节数组
- `java.md5Encode(str)` - MD5编码
- `java.md5Encode16(str)` - MD5编码（16位）

### 工具函数
- `java.timeFormat(timestamp)` - 时间格式化
- `java.timeFormatUTC(timestamp, format, sh)` - UTC时间格式化
- `java.encodeURI(str)` - URL编码
- `java.decodeURI(str)` - URL解码
- `java.htmlFormat(str)` - HTML格式化
- `java.randomUUID()` - 生成UUID
- `java.splitNotBlank(str, regex)` - 字符串分割
- `java.getAbsoluteURL(baseUrl, path)` - 获取绝对URL
- `java.log(msg)` - 日志输出
- `java.strToBytes(str, charset)` - 字符串转字节
- `java.bytesToStr(bytes, charset)` - 字节转字符串

### 文件操作
- `java.cacheFile(url)` - 缓存文件
- `java.importScript(path)` - 导入脚本
- `java.readTxtFile(path)` - 读取文本文件

## 内置对象

### source对象
```javascript
source.getKey()           // 获取书源URL
source.bookSourceUrl      // 书源URL
source.getVariable()      // 获取书源变量
source.setVariable(value) // 设置书源变量
source.getLoginInfo()     // 获取登录信息
source.putLoginInfo(info) // 保存登录信息
source.getLoginHeader()   // 获取登录头
source.putLoginHeader(h)  // 保存登录头
```

### book对象
```javascript
book.name                 // 书名
book.author               // 作者
book.bookUrl              // 书籍URL
book.getVariable(key)     // 获取书籍变量
book.putVariable(k, v)    // 设置书籍变量
```

### chapter对象
```javascript
chapter.index             // 章节索引
chapter.title             // 章节标题
chapter.url               // 章节URL
chapter.getVariable(key)  // 获取章节变量
chapter.putVariable(k, v) // 设置章节变量
```

### cookie对象
```javascript
cookie.getCookie(url)     // 获取Cookie
cookie.setCookie(url, v)  // 设置Cookie
cookie.removeCookie(url)  // 删除Cookie
```

### cache对象
```javascript
cache.get(key)            // 获取缓存
cache.put(key, value)     // 设置缓存
cache.getMemory(key)      // 获取内存缓存
cache.putMemory(k, v)     // 设置内存缓存
```

## 上下文变量

执行脚本时可以通过context传入以下变量：

- `result` - 上一步的结果/页面内容
- `baseUrl` - 基础URL
- `sourceUrl` - 书源URL
- `key` - 搜索关键字
- `page` - 页码
- `book` - 书籍信息对象
- `chapter` - 章节信息对象
- `variables` - 自定义变量

## 注意事项

1. **网络请求限制**
   - WebView中的XMLHttpRequest受同源策略限制
   - 跨域请求可能需要服务器支持CORS
   - 建议通过ArkTS层代理网络请求

2. **性能考虑**
   - 首次初始化需要加载WebView，可能需要几秒钟
   - 建议在应用启动时预初始化沙箱
   - 大量脚本执行建议使用队列管理

3. **兼容性**
   - CheerpJ模式需要网络连接
   - 离线模式不支持真正的Java类
   - 某些复杂的Rhino特性可能不支持

4. **调试**
   - 可以通过WebView的console输出查看日志
   - 沙箱事件通过`__RHINO_SANDBOX_EVENT__:`前缀输出

## 本地化配置

### 已集成的本地库

本地JAR文件位于 `rawfile/rhino_sandbox/lib/` 目录：

| 文件 | 版本 | 大小 | 说明 |
|------|------|------|------|
| `rhino-1.7.14.jar` | 1.7.14 | 1.38MB | Mozilla Rhino JavaScript引擎 |
| `jsoup-1.17.2.jar` | 1.17.2 | 445KB | Java HTML解析器 |

### 配置选项

在 `index.html` 中可以配置以下选项：

```javascript
window.rhinoConfig = {
    // 本地JAR文件路径
    rhinoJarPath: 'lib/rhino-1.7.14.jar',
    jsoupJarPath: 'lib/jsoup-1.17.2.jar',
    
    // CheerpJ配置
    useCheerpJ: true,           // 是否尝试使用CheerpJ
    cheerpjTimeout: 10000,      // CheerpJ加载超时（毫秒）
    preferOffline: false,       // 是否优先使用离线模式
    
    // CheerpJ CDN地址（可配置为本地地址）
    cheerpjCdn: 'https://cjrtnc.leaningtech.com/3.0/cj3loader.js'
};
```

### Jsoup DOM解析

离线模式提供完整的Jsoup兼容API：

```javascript
// 解析HTML
var doc = java.parseHtml(html, baseUrl);

// CSS选择器
var elements = java.selectElements(html, 'div.item');
var text = java.selectText(html, 'h1.title');
var href = java.selectAttr(html, 'a.link', 'href');

// 批量获取
var texts = java.selectTextList(html, 'li');
var hrefs = java.selectAttrList(html, 'a', 'href');

// 清理HTML
var clean = java.cleanHtml(html);

// 使用Jsoup对象（兼容Java代码）
var doc = Jsoup.parse(html);
var title = doc.select('title').text();
var links = doc.select('a[href]');
```

### Jsoup Elements API

```javascript
// 文档操作
doc.title()                    // 获取标题
doc.body()                     // 获取body元素
doc.select(cssQuery)           // CSS选择器查询
doc.selectFirst(cssQuery)      // 获取第一个匹配元素
doc.getElementById(id)         // 根据ID获取
doc.getElementsByTag(tag)      // 根据标签获取
doc.getElementsByClass(cls)    // 根据class获取

// 元素操作
el.tagName()                   // 标签名
el.id()                        // ID
el.className()                 // class名
el.hasClass(name)              // 检查class
el.attr(name)                  // 获取属性
el.hasAttr(name)               // 检查属性
el.absUrl(attrName)            // 获取绝对URL
el.text()                      // 文本内容
el.ownText()                   // 自身文本
el.html()                      // 内部HTML
el.outerHtml()                 // 外部HTML
el.data()                      // 数据内容
el.val()                       // 表单值

// 遍历
el.children()                  // 子元素
el.parent()                    // 父元素
el.nextElementSibling()        // 下一个兄弟
el.previousElementSibling()    // 上一个兄弟

// 元素集合
elements.size()                // 数量
elements.isEmpty()             // 是否为空
elements.first()               // 第一个
elements.last()                // 最后一个
elements.get(index)            // 指定索引
elements.each(callback)        // 遍历
elements.text()                // 所有文本
elements.eachText()            // 文本数组
elements.attr(name)            // 第一个元素属性
elements.eachAttr(name)        // 属性数组
```

## 后续优化

1. **本地CheerpJ部署**
   - 联系Leaning Technologies获取本地部署许可
   - 将CheerpJ运行时（约50MB+）打包到应用中
   - 配置 `cheerpjCdn` 为本地路径

2. **性能优化**
   - 实现脚本预编译缓存
   - 添加执行结果缓存
   - 优化大型HTML解析性能

3. **兼容性增强**
   - 添加更多Rhino特有功能支持
   - 完善XPath解析能力
   - 增加正则表达式扩展
