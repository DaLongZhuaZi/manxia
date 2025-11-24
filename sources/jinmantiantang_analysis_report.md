# 禁漫天堂 (Jinmantiantang) 图源适配分析报告

## 📋 执行摘要

本报告对禁漫天堂 Kotlin 版本进行了全面分析，并提供了将其适配到 ManXia JSON 图源系统的完整方案。该图源具有多个高级特性，包括图片反爬虫机制、动态域名切换、Base64 解码等，需要系统级别的功能扩展才能完整支持。

---

## 1️⃣ Kotlin 源码核心功能分析

### 1.1 主要文件结构

```
jinmantiantang/
├── Jinmantiantang.kt              # 主图源类 (458行)
├── JinmantiantangPreferences.kt   # 配置管理 (162行)
├── ScrambledImageInterceptor.kt   # 图片解扰拦截器 (104行)
└── JinmantiantangUrlActivity.kt   # URL跳转处理 (42行)
```

### 1.2 核心技术特性

#### **A. 图片反爬虫机制 (ScrambledImageInterceptor)**

**技术原理：**
- 针对章节ID ≥ 220980 的漫画，图片被分割并打乱顺序
- 使用 MD5 哈希算法计算分割行数
- 根据章节ID和图片索引动态计算还原参数

**算法详解：**
```kotlin
// 1. 根据章节ID确定分割模数
modulus = if (aid >= 421926) 8
          else if (aid >= 268850) 10
          else 10

// 2. 计算分割行数
rows = 2 * (md5LastCharCode(aid + imgIndex) % modulus) + 2

// 3. 图片还原算法
for (x in 0 until rows) {
    copyH = floor(height / rows)
    py = copyH * x
    y = height - (copyH * (x + 1)) - remainder
    // 从底部向顶部逆序拼接
}
```

**关键点：**
- 图片以 JPEG 格式返回，质量 90%
- 需要在客户端进行实时解码
- 对 `media/photos` 路径下的图片进行处理
- 支持 GZIP 压缩响应

#### **B. 动态域名管理系统**

**域名池：**
```
主站域名：
- 18comic.vip (主站1)
- 18comic.ink (主站2)
- jmcomic-zzz.one (东南亚线路1)
- jmcomic-zzz.org (东南亚线路2)

动态域名（从远程获取）：
- 18comic-ive.club
- 18comic-aspa.org
- 18comic-wantgo.cc
```

**自动更新机制：**
从 GitHub 获取最新域名列表，失败时自动切换域名并提示用户

#### **C. Base64 内容解码**

**应用场景：** 漫画详情页和章节列表使用 Base64 编码隐藏内容

**解码逻辑：**
1. 查找包含 `base64DecodeUtf8` 的 `<script>` 标签
2. 提取 Base64 字符串
3. 解码并注入到 DOM

#### **D. 速率限制 (Rate Limiting)**

**配置参数：**
- 请求数：1-10 请求/时间窗口
- 时间窗口：1-60 秒
- 默认值：1 请求/3秒

**目的：** 防止 IP 被封禁

#### **E. 随机 User-Agent**

使用 `lib:randomua` 库动态切换 User-Agent，支持自定义 UA

---

## 2️⃣ 核心工作流程分析

### 2.1 热门漫画 (popularManga)

**请求：** `GET /albums?o=mv&page={page}`

**选择器：** `div.list-col > div.p-b-15:not([data-group])`

**提取字段：**
- title: children[1].text()
- url: children[0] > a::attr(href)
- thumbnail_url: children[0] > img::attr(data-original/src/data-cfsrc)
- author: children[2] > a::text (多作者用逗号分隔)
- genre: children[3] > a::text (多标签用逗号分隔)

**特殊处理：**
- 过滤用户屏蔽的标签
- 移除广告元素

### 2.2 搜索功能

**三种搜索模式：**

1. **ID搜索：** `JM123456` → `GET /album/{id}`
2. **关键词搜索：** `A +B` (AND) 或 `A B` (OR)
3. **筛选搜索：** `-YAOI -扶他` (排除标签)

### 2.3 漫画详情

**Base64 解码流程：**
1. 查找包含 `base64DecodeUtf8` 的 script 标签
2. 提取并解码 Base64 字符串
3. 注入到 body

**提取字段：**
- title: h1::text
- author: div.panel-body div.tag-block[3] .btn-primary::text
- status: 連載中=1, 完結=2, 其他=0
- description: #intro-block .p-t-5.p-b-5::text

### 2.4 页面列表

**递归分页处理：**
- 提取当前页图片
- 检查下一页链接
- 递归获取所有页面
- 移除 URL 查询参数

---

## 3️⃣ 筛选系统

### 3.1 四大筛选器

**A. CategoryGroup (按类型)**
- 全部、同人、韩漫、美漫、短篇、单本
- 剧情、校园、纯爱、人妻、师生等 60+ 标签

**B. SortFilter (排序)**
- 最新 (o=mr)
- 最多浏览 (o=mv)
- 最多爱心 (o=tf)
- 最多图片 (o=mp)

**C. TimeFilter (时间)**
- 全部、今天、这周、本月

**D. TypeFilter (搜索范围)**
- 站内搜索、作品、作者、标签、登场人物

---

## 4️⃣ 需要的系统扩展功能

### 4.1 ⚠️ 图片解扰模块（核心功能）

**必须实现的功能：**
- MD5 哈希计算
- 图片分割行数计算
- 图片逆序拼接还原

**实现方案：**
在 ArkTS 层使用 `@ohos.image` 和 `@ohos.crypto` 实现

**关键代码逻辑：**
```typescript
// 1. 计算分割行数
rows = 2 * (md5Hash(aid + imgIndex) % modulus) + 2

// 2. 逆序拼接图片
for (x = 0; x < rows; x++) {
    copyHeight = floor(height / rows)
    sourceY = height - (copyHeight * (x + 1)) - remainder
    targetY = copyHeight * x
    // 复制图像区域
}
```

### 4.2 Base64 解码模块

在 WebView 工作流中添加 `base64Decode` 动作类型：
- 查找包含 Base64 的 script 标签
- 提取并解码内容
- 注入到指定位置

### 4.3 动态域名更新模块

**功能：**
- 从远程 URL 获取域名列表
- 自动故障转移
- 用户手动切换域名

### 4.4 速率限制模块

**功能：**
- 限制请求频率
- 防止 IP 被封禁
- 支持全局和按图源限制

### 4.5 标签过滤模块

**功能：**
- 过滤用户屏蔽的标签
- 支持多标签组合
- 大小写不敏感

### 4.6 递归分页处理模块

**功能：**
- 自动获取所有分页内容
- 合并结果
- 限制最大页数

---

## 5️⃣ JSON 配置文件结构

### 5.1 基础元数据

```json
{
  "metadata": {
    "id": "jinmantiantang",
    "name": "禁漫天堂",
    "version": "1.0.0",
    "language": "zh-CN",
    "baseUrl": "https://18comic.vip",
    "nsfw": true
  }
}
```

### 5.2 能力声明

```json
{
  "capabilities": {
    "imageDecoding": true,
    "base64Decoding": true,
    "dynamicDomain": true,
    "userAgentRotation": true
  }
}
```

### 5.3 网络配置

```json
{
  "network": {
    "rateLimit": {
      "enabled": true,
      "requests": 1,
      "period": 3000
    }
  }
}
```

---

## 6️⃣ 实施计划

### 阶段1：基础功能（1-2周）
- [ ] 实现基础工作流（热门、最新、搜索）
- [ ] 实现漫画详情和章节列表
- [ ] 实现 Base64 解码

### 阶段2：图片解扰（2-3周）⚠️ 关键
- [ ] 实现 MD5 哈希计算
- [ ] 实现图片分割算法
- [ ] 实现图片拼接还原
- [ ] 性能优化和测试

### 阶段3：高级功能（1-2周）
- [ ] 实现动态域名管理
- [ ] 实现速率限制
- [ ] 实现标签过滤
- [ ] 实现递归分页

### 阶段4：测试和优化（1周）
- [ ] 完整功能测试
- [ ] 性能优化
- [ ] 错误处理完善
- [ ] 文档编写

---

## 7️⃣ 技术难点和风险

### 7.1 图片解扰算法 ⚠️ 高风险
**难度：** ★★★★★
**风险：** 性能问题、内存占用高
**建议：** 使用原生模块实现，避免在 WebView 中处理

### 7.2 Base64 解码
**难度：** ★★★☆☆
**风险：** DOM 注入可能影响页面结构
**建议：** 在 script 执行前注入

### 7.3 动态域名管理
**难度：** ★★☆☆☆
**风险：** 网络请求失败导致无法访问
**建议：** 实现完善的故障转移机制

### 7.4 速率限制
**难度：** ★★☆☆☆
**风险：** 限制过严影响用户体验
**建议：** 提供可配置选项

---

## 8️⃣ 总结和建议

### 8.1 核心挑战

1. **图片解扰是最大挑战**，必须在原生层实现才能保证性能
2. **Base64 解码** 需要在 WebView 工作流中添加新的动作类型
3. **动态域名管理** 需要完善的网络错误处理机制

### 8.2 优先级建议

**P0（必须实现）：**
- 图片解扰模块
- Base64 解码模块
- 基础工作流

**P1（重要）：**
- 动态域名管理
- 速率限制

**P2（可选）：**
- 标签过滤
- 递归分页优化

### 8.3 预估工作量

**总计：** 5-8 周
- 图片解扰：2-3 周
- 基础功能：1-2 周
- 高级功能：1-2 周
- 测试优化：1 周

### 8.4 技术栈要求

- ArkTS 图像处理
- 加密算法实现
- WebView 高级交互
- 网络请求拦截

---

## 📚 附录

### A. 相关文件清单

- Jinmantiantang.kt (458行)
- JinmantiantangPreferences.kt (162行)
- ScrambledImageInterceptor.kt (104行)
- JinmantiantangUrlActivity.kt (42行)

### B. 参考资源

- Kotlin 源码：keiyoushi-extensions-source/src/zh/jinmantiantang
- 现有 JSON 图源：copymanga_webview.json, komiic_api.json
- 图片解扰算法：ScrambledImageInterceptor.kt

### C. 测试用例

- 章节ID < 220980：无需解扰
- 章节ID ≥ 220980：需要解扰
- 多页章节：递归分页
- 单章节漫画：特殊处理

---

**报告生成时间：** 2024-11-24
**版本：** 1.0
**作者：** ManXia Team
