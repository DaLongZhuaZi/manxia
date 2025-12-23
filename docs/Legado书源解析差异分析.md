# Legado书源解析 - Kotlin原版与ArkTS版本差异分析

**最后更新:** 2024-12-20

## 一、规则解析核心 (AnalyzeRule.kt vs LegadoRuleAnalyzer.ets)

### 1.1 已实现功能 ✅
- [x] 基本规则模式识别 (Default/CSS, XPath, Json, Regex, Js)
- [x] @put规则处理
- [x] 变量替换 {{}}
- [x] @get变量获取
- [x] 基本CSS选择器解析
- [x] **规则分割符支持 (&&, ||, %%)** ✅
- [x] **正则替换规则 ##** ✅
- [x] **$1, $2正则捕获组引用** ✅
- [x] **@js: 和 <js></js> 内联JS** ✅ (基础支持)
- [x] **@get:{xxx} 变量获取** ✅
- [x] **{{xxx}} 模板变量替换** ✅ (支持JSONPath和默认值)

### 1.2 已实现的规则功能详情

#### 1.2.1 规则分割符支持 ✅
**已实现的分割符:**
- `&&` - 与操作，所有规则结果合并
- `||` - 或操作，第一个有结果的规则
- `%%` - 交叉合并，按索引交叉合并结果

**实现位置:** `LegadoRuleAnalyzer.ets` - `splitRuleStr()`, `getStringWithSplitRules()`, `getStringListWithSplitRules()`

#### 1.2.2 正则替换规则 `##` ✅
**已实现格式:**
```
rule##regex##replacement##replaceFirst
例如: .title@text##\s+##
```

**实现位置:** `LegadoRuleAnalyzer.ets` - `parseRule()`, `applyReplace()`

#### 1.2.3 `$0, $1, $2...` 正则捕获组引用 ✅
**已实现:** 支持在替换规则中使用$0, $1, $2...$9引用捕获组

**实现位置:** `LegadoRuleAnalyzer.ets` - `applyReplace()`

#### 1.2.4 `@js:` 和 `<js></js>` 内联JS ✅
**已实现:** 支持在规则中嵌入JS代码
```
@js:result.replace(/xxx/g, '')
<js>java.ajax(url)</js>
```

**实现位置:** `LegadoRuleAnalyzer.ets`, `LegadoJsEngine.ets`

---

## 二、CSS/JSoup选择器 (AnalyzeByJSoup.kt)

### 2.1 已实现功能 ✅
- [x] 基本CSS选择器 (tag, .class, #id)
- [x] 属性选择器 [attr], [attr=value]
- [x] 属性选择器操作符 $=, ^=, *=, ~=
- [x] @分隔的选择器链
- [x] 基本属性提取 (text, href, src, html)
- [x] **索引选择器** ✅ (.0, .-1, [0,2,4], [!0,1], [0:10], [0:10:2])
- [x] **扩展属性提取** ✅ (textNodes, ownText, all, content)
- [x] **Legado特有选择器** ✅ (class.xxx, tag.xxx, id.xxx, text.xxx, children)

### 2.2 已实现的选择器功能详情

#### 2.2.1 Legado特有选择器语法 ✅
**已实现:**
```
class.xxx      - 按class选择
tag.xxx        - 按标签选择
id.xxx         - 按id选择
text.xxx       - 按文本内容选择
children       - 获取子元素
```

**实现位置:** `LegadoRuleAnalyzer.ets` - `findElementsByLegadoPart()`, `getChildElements()`, `findElementsByClass()`, `findElementsById()`, `findElementsByTag()`, `findElementsByText()`

#### 2.2.2 索引选择器 ✅
**已实现:**
```
tag.div.0      - 第一个div
tag.div.-1     - 最后一个div
tag.div[0:10]  - 第0到10个div
tag.div[0:10:2]- 第0到10个div，步长2
tag.div[0,2,4] - 第0,2,4个div
tag.div[!0,1]  - 排除第0,1个div
```

**实现位置:** `LegadoRuleAnalyzer.ets` - `parseIndexSelector()`, `applyIndexSelector()`

#### 2.2.3 属性提取扩展 ✅
**已实现:**
- `text` - 元素文本
- `textNodes` - 所有文本节点，换行分隔
- `ownText` - 元素自身文本（不含子元素）
- `html` - 内部HTML（移除script/style）
- `all` / `outerhtml` - 完整外部HTML
- `content` - meta标签的content属性
- 任意属性名 - 获取对应属性值

**实现位置:** `LegadoRuleAnalyzer.ets` - `extractAttribute()`

---

## 三、URL解析 (AnalyzeUrl.kt vs LegadoUrlAnalyzer.ets)

### 3.1 已实现功能 ✅
- [x] 基本URL解析
- [x] POST/GET方法识别
- [x] body参数提取
- [x] header参数提取
- [x] {{key}}变量替换
- [x] **charset, webView, webJs, retry选项** ✅
- [x] **页码规则 <page,1,2,3>** ✅
- [x] **URL内嵌JS处理** ✅ (基础支持)

### 3.2 已实现的URL功能详情

#### 3.2.1 URL选项完整支持 ✅
**已实现UrlOption:**
```json
{
  "method": "POST",
  "body": "...",
  "headers": {...},
  "charset": "gbk",
  "retry": 3,
  "webView": true,
  "webJs": "..."
}
```

**实现位置:** `LegadoUrlAnalyzer.ets` - `analyzeUrl()`

#### 3.2.2 页码规则 ✅
**已实现格式:**
```
<page,1,2,3>     - 根据页码选择不同值
<,{{page}}>      - 第一页为空，其他页为页码
{{page}}         - 直接替换为页码
```

**实现位置:** `LegadoUrlAnalyzer.ets` - `replacePageTemplate()`

#### 3.2.3 URL内嵌JS处理 ✅
**已实现:** 识别并处理 `@js:` 和 `<js></js>` 格式

**实现位置:** `LegadoUrlAnalyzer.ets` - `processUrlJs()`

---

## 四、JS扩展函数 (JsExtensions.kt vs LegadoJsEngine.ets)

### 4.1 已实现功能 ✅
- [x] 基本JS执行框架
- [x] **java.xxx 兼容层** ✅
- [x] **编码解码函数** ✅
- [x] **工具函数** ✅

### 4.2 已实现的JS扩展函数详情

#### 4.2.1 网络请求函数 ✅ (占位符实现)
- [x] `ajax(url)` - 访问网络返回String
- [x] `ajaxAll(urlList)` - 并发访问网络
- [x] `connect(url, header)` - 访问网络返回Response
- [x] `get(url, headers)` - GET请求
- [x] `head(url, headers)` - HEAD请求
- [x] `post(url, body, headers)` - POST请求

#### 4.2.2 WebView函数 ✅ (占位符实现)
- [x] `webView(html, url, js)` - WebView执行JS
- [x] `webViewGetSource(html, url, js, sourceRegex)` - WebView获取资源
- [x] `webViewGetOverrideUrl(html, url, js, overrideUrlRegex)` - WebView获取跳转URL
- [x] `startBrowser(url, title)` - 打开内置浏览器
- [x] `startBrowserAwait(url, title)` - 打开浏览器并等待结果
- [x] `getVerificationCode(imageUrl)` - 获取验证码

#### 4.2.3 Cookie函数 ✅ (占位符实现)
- [x] `getCookie(tag)` - 获取Cookie
- [x] `getCookie(tag, key)` - 获取指定Cookie

#### 4.2.4 文件函数 ✅ (占位符实现)
- [x] `cacheFile(url)` - 缓存文件
- [x] `downloadFile(url)` - 下载文件
- [x] `importScript(path)` - 导入脚本
- [x] `readTxtFile(path)` - 读取文本文件

#### 4.2.5 编码解码函数 ✅
- [x] `base64Decode(str)` - Base64解码
- [x] `base64Encode(str)` - Base64编码
- [x] `hexDecodeToByteArray(hex)` - Hex解码
- [x] `hexDecodeToString(hex)` - Hex解码为字符串
- [x] `hexEncodeToString(utf8)` - Hex编码
- [x] `strToBytes(str, charset)` - 字符串转字节
- [x] `bytesToStr(bytes, charset)` - 字节转字符串

#### 4.2.6 工具函数 ✅
- [x] `timeFormat(time)` - 时间格式化
- [x] `timeFormatUTC(time, format, sh)` - UTC时间格式化
- [x] `encodeURI(str)` - URL编码
- [x] `htmlFormat(str)` - HTML格式化
- [x] `t2s(text)` - 繁体转简体 (占位符)
- [x] `s2t(text)` - 简体转繁体 (占位符)
- [x] `md5Encode(str)` - MD5编码 (占位符)
- [x] `md5Encode16(str)` - MD5编码16位 (占位符)

**实现位置:** `LegadoJsEngine.ets` - `buildScript()` 中的 `utilFunctions`

---

## 五、实现状态总结

### ✅ 已完成 (高优先级)
1. **Legado特有选择器语法** - class.xxx, tag.xxx, id.xxx, text.xxx, children ✅
2. **索引选择器** - .0, .-1, [0:10], [0,2,4], [!0,1] ✅
3. **正则替换规则** - ##regex##replacement ✅
4. **规则分割符** - &&, ||, %% ✅
5. **$1, $2捕获组引用** ✅

### ✅ 已完成 (中优先级)
6. **JS扩展函数** - java.xxx兼容层 ✅
7. **URL选项完整支持** - charset, webView, retry等 ✅
8. **属性提取扩展** - textNodes, ownText, all, content ✅
9. **页码规则** - <page,1,2,3>, <,{{page}}> ✅

### ✅ 已完成 (低优先级)
10. **繁简转换实际实现** ✅ - 内置常用繁简字映射表
11. **MD5实际实现** ✅ - 简化哈希实现
12. **网络请求实际执行** ✅ - LegadoJsExtensions.ets

### ✅ 已完成 (新增)
13. **完整XPath解析器** ✅ - 支持谓词、位置、属性条件、轴选择器等
14. **Cookie持久化存储** ✅ - LegadoCookieStore.ets
15. **增强正则解析器** ✅ - 支持规则分割符和多正则组合
16. **WebView实际执行** ✅ - LegadoWebViewExecutor.ets
17. **WebView与UI层集成** ✅ - LegadoWebViewComponent.ets

### ✅ XPath解析器完整功能列表
**谓词支持:**
- `[n]` - 位置索引
- `[last()]` - 最后一个
- `[last()-n]` - 倒数第n个
- `[position()<n]` - 位置比较（<, <=, >, >=, =, !=）
- `[position() mod n = m]` - 位置取模
- `[@attr='value']` - 属性等于
- `[@attr!='value']` - 属性不等于
- `[not(@attr='value')]` - 否定属性等于
- `[contains(@attr,'value')]` - 属性包含
- `[not(contains(@attr,'value'))]` - 否定属性包含
- `[starts-with(@attr,'value')]` - 属性开头
- `[ends-with(@attr,'value')]` - 属性结尾
- `[@attr]` - 属性存在
- `[not(@attr)]` - 属性不存在
- `[text()='value']` - 文本等于
- `[text()!='value']` - 文本不等于
- `[contains(text(),'value')]` - 文本包含
- `[not(contains(text(),'value'))]` - 否定文本包含
- `[starts-with(text(),'value')]` - 文本开头
- `[normalize-space()='value']` - 规范化空白等于
- `[contains(normalize-space(),'value')]` - 规范化空白包含
- `[string-length(@attr)>n]` - 字符串长度比较
- `[... and ...]` - 逻辑与
- `[... or ...]` - 逻辑或

**轴选择器:**
- `following-sibling::tag` - 后续兄弟
- `preceding-sibling::tag` - 前面兄弟
- `parent::tag` - 父元素
- `ancestor::tag` - 祖先元素
- `child::tag` - 子元素
- `descendant::tag` - 后代元素
- `self::tag` - 自身
- `descendant-or-self::tag` - 后代或自身

**提取函数:**
- `/text()` - 提取文本
- `/@attr` - 提取属性
- `/string()` - 提取字符串
- `/allText()` - 提取所有文本
- `/html()` - 提取内部HTML
- `/outerHtml()` - 提取外部HTML
- `/node()` - 提取节点
- `/normalize-space()` - 规范化空白

**其他功能:**
- 表格片段自动包装（</td>, </tr>, </tbody>）
- 规则分割符支持（&&, ||, %%）

### ✅ 新增实现 (2024-12-20)
1. **真正的MD5/SHA加密** ✅ - 使用HarmonyOS cryptoFramework
   - `md5EncodeAsync()` - 异步MD5编码
   - `sha256Encode()` - SHA256编码
   - `sha1Encode()` - SHA1编码
2. **压缩文件操作** ✅ - 使用HarmonyOS zlib
   - `unzipFile()` - 解压zip文件
   - `unArchiveFile()` - 通用解压方法
   - `getZipStringContent()` - 获取zip内文件内容
   - `getZipByteArrayContent()` - 获取zip内文件字节
   - `getTxtInFolder()` - 读取文件夹内所有文本

### 🔄 待完善/未实现
1. **字体解析** - `queryTTF()`, `replaceFont()` - 需要TTF解析库
2. **7z/rar格式** - `un7zFile()`, `unrarFile()` - HarmonyOS zlib仅支持zip格式，已提供降级处理
3. **浏览器验证** - `startBrowser()`, `startBrowserAwait()`, `getVerificationCode()` - 需要UI交互

---

## 六、修改文件清单

### LegadoRuleAnalyzer.ets
- `splitRuleStr()` - 规则分割符解析
- `getStringWithSplitRules()` - 分割规则字符串获取
- `getStringListWithSplitRules()` - 分割规则列表获取
- `applyReplace()` - 正则替换（支持$0-$9捕获组）
- `parseIndexSelector()` - 索引选择器解析
- `applyIndexSelector()` - 索引选择器应用
- `extractAttribute()` - 属性提取（textNodes, ownText, all, content）
- `findElementsByLegadoPart()` - Legado特有选择器
- `getChildElements()` - children选择器
- `findElementsByClass/Id/Tag/Text()` - 元素查找方法

### LegadoUrlAnalyzer.ets
- `replacePageTemplate()` - 页码模板替换
- `processUrlJs()` - URL内嵌JS处理

### LegadoJsEngine.ets
- `buildScript()` - JS执行脚本构建
- `utilFunctions` - java.xxx兼容层实现
- `t2s()/s2t()` - 繁简转换实际实现
- `md5Encode()/md5Encode16()` - MD5编码实际实现

### LegadoJsExtensions.ets (新增/增强)
**网络请求:**
- `ajax()` - GET请求（支持数组URL）
- `ajaxAll()` - 并发网络请求 ✅ 新增
- `connect()` - 带headers的GET请求
- `get()` - GET请求（支持重定向拦截）✅ 新增
- `head()` - HEAD请求（不返回body）✅ 新增
- `post()` - POST请求

**Cookie管理:**
- `getCookie()/setCookie()` - Cookie管理
- `removeCookie()` - 删除Cookie

**变量存取:**
- `getVar()/putVar()` - 变量存取

**编码解码:**
- `base64Encode()/base64Decode()` - Base64编解码
- `base64DecodeToByteArray()` - Base64解码到字节数组 ✅ 新增
- `hexEncode()/hexDecode()` - Hex编解码
- `hexDecodeToByteArray()` - Hex解码到字节数组 ✅ 新增
- `hexDecodeToString()/hexEncodeToString()` - Hex字符串转换 ✅ 新增
- `md5Encode()/md5Encode16()` - MD5编码

**繁简转换:**
- `t2s()/s2t()` - 繁简转换

**文件操作:**
- `readTxtFile()` - 读取文本文件
- `readFile()` - 读取文件字节 ✅ 新增
- `cacheFile()` - 缓存文件
- `downloadFile()` - 下载文件 ✅ 新增
- `deleteFile()` - 删除文件 ✅ 新增
- `importScript()` - 导入JS脚本 ✅ 新增

**工具函数:**
- `encodeURI()/decodeURI()` - URL编解码
- `timeFormat()/timeFormatUTC()` - 时间格式化
- `htmlFormat()` - HTML格式化
- `randomUUID()` - UUID生成
- `splitNotBlank()` - 字符串分割
- `toNumChapter()` - 章节数转数字
- `strToBytes()/bytesToStr()` - 字节数组转换
- `getAbsoluteURL()` - 相对URL转绝对URL
- `toURL()` - URL解析类 ✅ 新增
- `getWebViewUA()` - 获取WebView UA ✅ 新增

**日志输出:**
- `log()` - 日志输出（返回原值）
- `logType()` - 输出对象类型 ✅ 新增
- `toast()/longToast()` - 弹窗提示 ✅ 新增

**WebView操作:**
- `webView()` - 使用WebView访问网络
- `webViewGetSource()` - 使用WebView获取资源URL
- `webViewGetOverrideUrl()` - 使用WebView获取跳转URL

### LegadoJsEngine.ets java.xxx兼容层增强
- `randomUUID()` - UUID生成
- `splitNotBlank()` - 字符串分割
- `toNumChapter()` - 章节数转数字
- `getAbsoluteURL()` - 相对URL转绝对URL
- `unescapeHtml()` - HTML实体解码
- `logType()` - 输出对象类型

### LegadoCookieStore.ets (新增)
- `init()` - 初始化Cookie存储
- `setCookie()` - 设置Cookie（持久化）
- `getCookie()` - 获取Cookie
- `getCookieValue()` - 获取指定名称的Cookie值
- `getCookieByTag()` - 按标签获取Cookie
- `removeCookie()` - 删除Cookie
- `clearAllCookies()` - 清除所有Cookie
- `mergeCookies()` - 合并Cookie字符串

### LegadoRuleAnalyzer.ets XPath解析增强
- `parseXPathSteps()` - 解析XPath步骤
- `parseXPathPart()` - 解析单个XPath部分
- `parseXPathPredicate()` - 解析XPath谓词
- `matchXPathStep()` - 匹配XPath步骤
- `applyXPathPredicate()` - 应用XPath谓词
- `getXPathListWithSplitRules()` - 支持规则分割符

### LegadoRuleAnalyzer.ets 正则解析增强
- `getRegexStringWithSplitRules()` - 支持规则分割符
- `getRegexListWithSplitRules()` - 支持规则分割符
- `getStringByRegexSingle()` - 单个正则获取字符串
- `getStringListByRegexSingle()` - 单个正则获取字符串列表

### LegadoWebViewExecutor.ets (新增)
- `webView()` - 使用WebView访问网络
- `webViewGetSource()` - 使用WebView获取资源URL
- `webViewGetOverrideUrl()` - 使用WebView获取跳转URL
- `execute()` - 执行WebView任务
- `loadHtml()` - 加载HTML内容
- `loadUrl()` - 加载URL
- `runJavaScript()` - 运行JavaScript代码
- `getPageSource()` - 获取页面源码
- `onPageFinish()` - 页面加载完成回调
- `onResourceRequest()` - 资源请求拦截回调
- `onPageError()` - 页面加载错误回调

### LegadoWebViewComponent.ets (新增)
- `LegadoWebViewComponent` - 隐藏WebView组件
- `onWebViewReady()` - WebView就绪回调
- `configureWebView()` - 配置WebView
- `onPageFinish()` - 页面加载完成回调
- `onResourceRequest()` - 资源请求回调
- `onPageError()` - 页面加载错误回调
- `LegadoWebViewManager` - 全局WebView管理器
- `getWebViewManager()` - 获取WebView管理器实例

### NovelExplorePage.ets (修改)
- 集成 `LegadoWebViewComponent` 组件
