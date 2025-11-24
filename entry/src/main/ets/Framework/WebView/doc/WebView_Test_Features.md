# WebView测试页面功能清单

## 📋 功能概览

WebView可配置系统测试页面现已完善，提供全面的WebView测试和调试功能。

## ✅ 已实现功能

### 1. 基础测试模块

#### 1.1 页面加载测试
- **功能**: 加载指定URL并监控加载过程
- **按钮**: "加载页面"
- **日志标记**: 🔵 开始Web基础测试
- **输出内容**:
  - 目标URL
  - WebView控制器状态
  - loadUrl调用状态

#### 1.2 页面标题获取
- **功能**: 获取当前页面标题
- **按钮**: "标题"
- **JavaScript**: `document.title`
- **日志标记**: 🔵 开始获取页面标题
- **输出**: 页面标题文本

#### 1.3 链接数量统计
- **功能**: 统计页面中所有链接数量
- **按钮**: "链接数"
- **JavaScript**: `document.querySelectorAll("a").length`
- **日志标记**: 🔵 开始统计链接数量
- **输出**: 链接总数

#### 1.4 UserAgent获取
- **功能**: 获取浏览器UserAgent字符串
- **按钮**: "UA"
- **JavaScript**: `navigator.userAgent`
- **日志标记**: 🔵 开始获取UserAgent
- **输出**: 完整的UA字符串

### 2. 高级捕获模块

#### 2.1 所有链接捕获
- **功能**: 捕获页面所有链接的详细信息
- **按钮**: "所有链接"
- **日志标记**: 🔵 开始获取所有链接
- **捕获内容**:
  - 链接文本 (textContent)
  - 链接地址 (href)
  - 链接标题 (title)
- **限制**: 最多20个链接
- **输出格式**: JSON数组

**示例输出**:
```json
[
  {
    "text": "首页",
    "href": "https://example.com/",
    "title": "返回首页"
  }
]
```

#### 2.2 所有图片捕获
- **功能**: 捕获页面所有图片的详细信息
- **按钮**: "所有图片"
- **日志标记**: 🔵 开始获取所有图片
- **捕获内容**:
  - 图片源地址 (src)
  - 替代文本 (alt)
  - 图片宽度 (width)
  - 图片高度 (height)
- **限制**: 最多20张图片
- **输出格式**: JSON数组

**示例输出**:
```json
[
  {
    "src": "https://example.com/logo.png",
    "alt": "网站Logo",
    "width": 200,
    "height": 100
  }
]
```

#### 2.3 页面元信息获取
- **功能**: 获取页面完整的元数据信息
- **按钮**: "元信息"
- **日志标记**: 🔵 开始获取页面元信息
- **捕获内容**:
  - 页面标题 (title)
  - 完整URL (url)
  - 域名 (domain)
  - 协议 (protocol)
  - 字符集 (charset)
  - 来源页面 (referrer)
  - 文档状态 (readyState)
  - 最后修改时间 (lastModified)
  - Meta标签数组 (最多10个)
- **输出格式**: JSON对象

**示例输出**:
```json
{
  "title": "示例网站",
  "url": "https://example.com/page",
  "domain": "example.com",
  "protocol": "https:",
  "charset": "UTF-8",
  "referrer": "",
  "readyState": "complete",
  "lastModified": "11/17/2025 18:20:00",
  "meta": [
    {
      "name": "description",
      "content": "网站描述"
    }
  ]
}
```

#### 2.4 Cookie信息获取
- **功能**: 获取页面所有Cookie
- **按钮**: "Cookie"
- **日志标记**: 🔵 开始获取Cookie
- **捕获内容**:
  - 完整Cookie字符串
  - Cookie数量统计
- **输出格式**: JSON对象

**示例输出**:
```json
{
  "cookie": "session=abc123; user=john",
  "cookieCount": 2
}
```

#### 2.5 LocalStorage信息获取
- **功能**: 获取页面LocalStorage数据
- **按钮**: "Storage"
- **日志标记**: 🔵 开始获取LocalStorage
- **捕获内容**:
  - 所有键名数组 (keys)
  - 存储项数量 (count)
  - 前10个键值对 (data)
- **输出格式**: JSON对象

**示例输出**:
```json
{
  "keys": ["theme", "language", "token"],
  "count": 3,
  "data": {
    "theme": "dark",
    "language": "zh-CN",
    "token": "eyJ..."
  }
}
```

#### 2.6 性能信息获取
- **功能**: 获取页面性能指标
- **按钮**: "性能"
- **日志标记**: 🔵 开始获取性能信息
- **捕获内容**:
  - **timing**: 时间指标
    - loadTime: 页面加载总时间
    - domReady: DOM就绪时间
    - responseTime: 响应时间
  - **navigation**: 导航信息
    - type: 导航类型
    - redirectCount: 重定向次数
  - **resources**: 资源统计
    - count: 资源数量
    - totalSize: 总大小（字节）
- **输出格式**: JSON对象

**示例输出**:
```json
{
  "timing": {
    "loadTime": 1523,
    "domReady": 856,
    "responseTime": 234
  },
  "navigation": {
    "type": 0,
    "redirectCount": 0
  },
  "resources": {
    "count": 45,
    "totalSize": 2456789
  }
}
```

#### 2.7 页面源码获取
- **功能**: 获取完整的HTML源码
- **按钮**: "源码"
- **日志标记**: 🔵 开始获取页面源码
- **捕获内容**: 完整的HTML文档
- **显示限制**: 前1000个字符
- **输出**: 源码长度 + 部分内容预览

### 3. WebView事件监听

#### 3.1 控制器附加事件
- **事件**: `onControllerAttached`
- **日志**: ✅ WebView控制器已附加到Web组件
- **触发时机**: WebView控制器成功绑定到Web组件

#### 3.2 页面加载开始
- **事件**: `onPageBegin`
- **日志**: 🟢 页面开始加载: [URL]
- **触发时机**: 页面开始加载时
- **更新状态**: 
  - `webCurrentUrl`
  - `webLoadState = 'loading'`

#### 3.3 页面加载完成
- **事件**: `onPageEnd`
- **日志**: 🟢 页面加载完成: [URL]
- **触发时机**: 页面加载完成时
- **更新状态**: 
  - `webCurrentUrl`
  - `webLoadState = 'loaded'`
- **自动执行**: 获取页面标题

#### 3.4 加载进度更新
- **事件**: `onProgressChange`
- **日志**: 📊 加载进度: [进度]%
- **触发时机**: 页面加载进度变化时
- **日志级别**: DEBUG

#### 3.5 页面加载错误
- **事件**: `onErrorReceive`
- **日志**: ❌ 页面加载错误: [错误信息]
- **触发时机**: 页面加载失败时
- **更新状态**: 
  - `webLoadState = 'error'`
  - `jsOutput` 显示错误信息

#### 3.6 HTTP错误
- **事件**: `onHttpErrorReceive`
- **日志**: ❌ HTTP错误: [状态码]
- **触发时机**: HTTP请求返回错误状态码

#### 3.7 标题接收
- **事件**: `onTitleReceive`
- **日志**: 📄 页面标题: [标题]
- **触发时机**: 页面标题更新时
- **更新状态**: `webPageTitle`

### 4. WebView配置

#### 4.1 JavaScript支持
- **属性**: `.javaScriptAccess(true)`
- **状态**: 已启用
- **必需**: 是（所有JS测试功能依赖此配置）

#### 4.2 DOM存储
- **属性**: `.domStorageAccess(true)`
- **状态**: 已启用
- **用途**: 支持LocalStorage和SessionStorage

#### 4.3 缩放功能
- **属性**: `.zoomAccess(true)`
- **状态**: 已启用
- **用途**: 允许用户缩放页面

#### 4.4 文件访问
- **属性**: `.fileAccess(true)`
- **状态**: 已启用
- **用途**: 允许访问本地文件

### 5. 日志系统

#### 5.1 日志级别
- **INFO** (ℹ️): 一般信息
- **DEBUG** (🔍): 调试信息
- **ERROR** (❌): 错误信息

#### 5.2 日志格式
```
[时间戳] [级别] [TAG] 消息内容
```

#### 5.3 关键日志标记
- 🔵 操作开始
- ✅ 操作成功
- ❌ 操作失败
- 🟢 页面事件
- 📊 进度信息
- 📄 内容信息
- 🔄 生命周期

### 6. UI组件

#### 6.1 WebView显示区域
- **尺寸**: 宽度100%, 高度300px
- **位置**: 页面顶部
- **功能**: 实时显示网页内容

#### 6.2 状态显示
- **加载状态**: idle / loading / loaded / error
- **当前URL**: 实时更新
- **页面标题**: 实时更新

#### 6.3 JS输出区域
- **高度**: 150px
- **滚动**: 支持
- **字体**: monospace（等宽字体）
- **背景**: 浅色背景便于阅读

#### 6.4 按钮布局
- **基础测试**: 4个按钮（加载、标题、链接数、UA）
- **高级捕获**: 7个按钮（链接、图片、元信息、Cookie、Storage、性能、源码）
- **样式**: Capsule类型，不同颜色区分功能

## 🎯 类型安全

### 严格类型检查
所有函数和变量都有明确的类型声明：

```typescript
private async runTitleJsTest(): Promise<void>
private async getAllLinks(): Promise<void>
private async getPageMetaInfo(): Promise<void>
```

### 错误处理
所有异步操作都包含try-catch块：

```typescript
try {
  const result = await this.runWebJavaScript(script);
  // 处理成功
} catch (e) {
  const msg = e instanceof Error ? e.message : String(e);
  // 处理错误
}
```

### JSON解析安全
所有JSON.parse操作都在try-catch保护下执行。

## 📊 性能优化

### 1. 数据限制
- 链接捕获: 最多20个
- 图片捕获: 最多20张
- Meta标签: 最多10个
- LocalStorage: 最多10项
- 源码显示: 最多1000字符

### 2. 日志优化
- 进度日志使用DEBUG级别
- 避免在循环中记录大量日志
- 关键操作使用INFO级别

### 3. UI更新
- 使用@State响应式更新
- 避免不必要的重渲染

## 🔧 使用建议

### 1. 测试流程
1. 输入目标URL
2. 点击"加载页面"
3. 等待页面加载完成（查看日志）
4. 使用各种测试按钮获取信息
5. 查看JS输出区域的结果

### 2. 调试技巧
- 查看控制台日志了解详细执行过程
- 使用emoji标记快速定位日志类型
- 关注错误日志（❌）进行问题排查

### 3. 常见问题
- **JavaScript执行失败**: 确保页面已加载完成
- **获取不到数据**: 检查页面是否有对应元素
- **性能数据为0**: 某些网站可能限制performance API

## 📝 测试用例示例

### 测试用例1: 基础页面加载
```
1. 输入URL: https://www.bing.com
2. 点击"加载页面"
3. 预期: 看到 🟢 页面加载完成
4. 点击"标题"
5. 预期: JS输出显示 "标题: 搜索 - Microsoft 必应"
```

### 测试用例2: 链接捕获
```
1. 确保页面已加载
2. 点击"所有链接"
3. 预期: JS输出显示JSON格式的链接数组
4. 检查: 每个链接包含text、href、title字段
```

### 测试用例3: 性能分析
```
1. 加载一个复杂页面
2. 等待完全加载
3. 点击"性能"
4. 预期: 显示timing、navigation、resources数据
5. 检查: loadTime > 0, resourceCount > 0
```

## 🚀 未来扩展建议

### 可添加功能
1. **网络请求拦截**: 监控所有HTTP请求
2. **页面截图**: 捕获页面可视区域
3. **元素选择器**: 可视化选择页面元素
4. **自动化脚本**: 录制和回放操作序列
5. **数据导出**: 导出测试结果为JSON/CSV
6. **历史记录**: 保存测试历史
7. **对比工具**: 对比不同页面的数据

## 📚 相关文档

- [WebView调试指南](./WebView_Debugging_Guide.md)
- [不可见WebView使用指南](./InvisibleWebView_Usage_Guide.md)
- [HarmonyOS WebView API文档](https://developer.huawei.com/consumer/cn/doc/harmonyos-references-V5/js-apis-webview-V5)

## ✅ 总结

WebView测试页面现已具备：
- ✅ 11个测试功能
- ✅ 7个事件监听器
- ✅ 完善的日志系统
- ✅ 类型安全的代码
- ✅ 友好的UI界面
- ✅ 详细的错误处理

可以满足几乎所有WebView测试和调试需求！
