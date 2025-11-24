# CopyManga WebView调试指南

## 🔍 已发现的问题

### 1. ❌ Initialize工作流执行失败
**错误**: `Init error. The WebviewController must be associated with a Web component`

**原因**: 在页面加载时，`initialize`工作流在WebView控制器附加到组件之前就执行了。

**解决方案**: ✅ 已移除`initialize`工作流，Cookie会在第一次访问时自动建立。

---

### 2. ❌ 选择器无法匹配元素
**错误**: `多项提取完成，获取 0 条数据`

**原因**: 
- 选择器`.exemptComicList .exemptComicItem`等无法匹配实际的DOM结构
- 可能网站更新了HTML结构
- 可能需要更长的加载时间

**解决方案**: ✅ 已实施以下改进：
1. 增加等待时间（3秒→5秒）
2. 添加调试脚本输出页面结构
3. 使用通用JavaScript脚本提取，不依赖特定选择器

---

### 3. ⚠️ 连接错误但继续执行
**错误**: `WebView错误: ERR_CONNECTION_CLOSED`

**可能原因**:
- 网络不稳定
- 服务器主动关闭连接
- 反爬虫机制

**当前状态**: 虽然出现错误，但页面最终加载成功（有Cookie保存）

---

## 🔧 已实施的修复

### 修复1: 移除Initialize工作流
```json
// 已删除
"initialize": {
  "description": "初始化会话，建立Cookie",
  "actions": [...]
}
```

### 修复2: 增强Popular工作流
```json
"popular": {
  "actions": [
    {
      "type": "navigate",
      "url": "https://www.2025copy.com",
      "timeout": 8000
    },
    {
      "type": "wait",
      "duration": 5000  // 增加到5秒
    },
    {
      "type": "script",
      "code": "console.log('页面标题:', document.title); ...",  // 调试脚本
      "description": "调试：输出页面结构信息"
    },
    {
      "type": "script",
      "code": "window.scrollTo(0, 800);"
    },
    {
      "type": "wait",
      "duration": 3000  // 增加到3秒
    },
    {
      "type": "script",
      "code": "const results = []; const links = document.querySelectorAll('a[href*=\"/comic/\"]'); ...",
      "description": "使用通用脚本提取漫画列表"
    }
  ]
}
```

**关键改进**:
- ✅ 使用通用选择器`a[href*="/comic/"]`
- ✅ 自动查找父容器
- ✅ 智能提取标题、封面
- ✅ 去重处理
- ✅ 限制返回30条

---

## 📊 预期日志输出

### 成功的日志应该包含：

```
[MangaSourceActionEngine] 导航到: https://www.2025copy.com
[MangaSourceActionEngine] 导航完成: https://www.2025copy.com
[MangaSourceActionEngine] 📱 WebView UserAgent: ...
[MangaSourceActionEngine] 执行脚本: console.log('页面标题:', document.title); ...
// 控制台输出：
页面标题: 拷贝漫画
body类名: ...
找到元素数量: 20+
[MangaSourceActionEngine] 执行脚本: const results = []; ...
// 控制台输出：
通用提取找到: 20 条
[MangaSourceEngine] 提取到 20 条漫画数据
[MangaSourceEngine] 获取热门漫画完成，找到 20 个结果
```

---

## 🐛 调试步骤

### 步骤1: 查看调试输出
运行后查看日志中的console.log输出：
```
页面标题: ?
body类名: ?
找到元素数量: ?
```

### 步骤2: 根据输出调整
如果"找到元素数量"为0，说明：
- 页面未完全加载
- 选择器`a[href*="/comic/"]`不匹配
- 需要更长等待时间

### 步骤3: 手动测试
在浏览器中打开`https://www.2025copy.com`，在控制台执行：
```javascript
// 测试链接数量
document.querySelectorAll('a[href*="/comic/"]').length

// 测试提取脚本
const results = []; 
const links = document.querySelectorAll('a[href*="/comic/"]'); 
const seen = new Set(); 
links.forEach(link => { 
  const href = link.getAttribute('href'); 
  if (!href || seen.has(href)) return; 
  seen.add(href); 
  const parent = link.closest('div[class*="comic"], div[class*="Comic"], li, article'); 
  if (!parent) return; 
  const img = parent.querySelector('img'); 
  const titleEl = parent.querySelector('[class*="title"], [class*="Title"], h1, h2, h3, h4'); 
  if (titleEl || img) { 
    results.push({ 
      id: href, 
      title: titleEl ? titleEl.textContent.trim() : '', 
      cover: img ? (img.getAttribute('data-src') || img.getAttribute('src') || '') : '' 
    }); 
  } 
}); 
console.log('找到:', results.length, '条');
console.log('示例:', results[0]);
```

---

## 🔄 如果仍然失败

### 方案A: 进一步增加等待时间
```json
{
  "type": "wait",
  "duration": 10000  // 10秒
}
```

### 方案B: 使用更宽松的选择器
```javascript
// 查找所有a标签
const links = document.querySelectorAll('a');
// 过滤包含comic的
const comicLinks = Array.from(links).filter(a => a.href.includes('/comic/'));
```

### 方案C: 检查网站是否可访问
```bash
# 测试域名
curl -I https://www.2025copy.com
curl -I https://www.copy20.com
```

### 方案D: 切换到备用域名
修改配置中的baseUrl：
```json
"baseUrl": "https://www.copy20.com"
```

---

## 📝 下一步测试

1. **重新加载图源配置**
2. **查看新的日志输出**
3. **检查调试脚本的console.log输出**
4. **根据输出调整选择器或等待时间**

---

## 💡 临时解决方案

如果WebView方案仍然有问题，可以：

1. **使用API版本**（如果API恢复）
2. **手动在浏览器中测试**，确认网站结构
3. **使用其他可用的图源**（如Komiic）
4. **等待网站维护完成**

---

## 🎯 关键检查点

- [ ] WebView控制器已附加
- [ ] 页面加载完成（onPageEnd触发）
- [ ] Cookie已保存
- [ ] 调试脚本输出了页面信息
- [ ] 通用提取脚本找到了元素
- [ ] 返回的JSON格式正确

---

**最后更新**: 2025-11-22 02:40
**状态**: 等待测试结果
