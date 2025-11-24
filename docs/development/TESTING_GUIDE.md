# SourceDetailPage WebView系统测试指南

## 🧪 快速测试步骤

### 前提条件
1. 已修复数据库ID问题
2. MainMenuPage已集成全局WebView容器
3. SourceDetailPage已完成WebView重构

---

## 📋 测试场景

### 场景1：测试HTTP系统（向后兼容）

#### 步骤：
1. **删除现有图源**
   - 打开应用，进入"图源"标签
   - 长按现有的"Komiic"图源
   - 确认删除

2. **重新导入HTTP格式图源**
   - 点击"导入图源"按钮
   - 选择`sources/komiic.json`文件
   - 等待导入成功提示

3. **查看日志**
   ```
   预期日志：
   - "图源已添加: Komiic (ID: 1)"  ← 注意ID应该是1或更大
   - "打开图源详情页: Komiic (ID: 1)"
   - "使用HTTP类型图源"
   - "使用HTTP系统加载漫画列表"
   ```

4. **测试功能**
   - 点击图源卡片进入详情页
   - 查看是否能加载漫画列表
   - 切换"热门"、"最新"标签
   - 测试搜索功能

#### 预期结果：
- ✅ 图源导入成功，ID正确
- ✅ 详情页正常显示
- ✅ 使用HTTP系统加载数据
- ✅ 所有标签功能正常

---

### 场景2：测试WebView系统

#### 步骤：
1. **创建WebView格式的测试图源**
   
   创建文件：`sources/test_webview.json`
   ```json
   {
     "metadata": {
       "id": "test_webview",
       "name": "测试WebView图源",
       "version": "2.0.0",
       "type": "webview",
       "description": "用于测试WebView系统",
       "language": "zh-CN"
     },
     "baseUrl": "https://www.bing.com",
     "workflows": {
       "search": {
         "actions": [
           {
             "type": "navigate",
             "url": "{{baseUrl}}/search?q={{keyword}}"
           },
           {
             "type": "wait",
             "timeout": 3000
           },
           {
             "type": "extract",
             "selector": "#b_results .b_algo",
             "fields": {
               "id": {
                 "selector": "h2 a",
                 "attribute": "href"
               },
               "title": {
                 "selector": "h2 a"
               },
               "url": {
                 "selector": "h2 a",
                 "attribute": "href"
               },
               "cover": {
                 "value": "https://via.placeholder.com/150"
               }
             }
           }
         ]
       }
     }
   }
   ```

2. **导入WebView图源**
   - 点击"导入图源"
   - 选择`test_webview.json`
   - 等待导入成功

3. **查看日志**
   ```
   预期日志：
   - "图源已添加: 测试WebView图源 (ID: 2)"
   - "打开图源详情页: 测试WebView图源 (ID: 2)"
   - "检测到WebView类型图源，初始化WebView系统"
   - "开始初始化WebView引擎"
   - "WebView引擎初始化成功"
   - "WebView控制器已附加"
   - "使用WebView系统加载漫画列表"
   ```

4. **测试WebView功能**
   - 点击WebView图源进入详情页
   - 观察WebView初始化日志
   - 等待数据加载
   - 查看是否显示结果

#### 预期结果：
- ✅ WebView图源导入成功
- ✅ WebView引擎初始化成功
- ✅ WebView控制器附加成功
- ✅ 能够执行WebView操作
- ✅ 数据正确转换和显示

---

### 场景3：测试降级机制

#### 步骤：
1. **创建错误的WebView配置**
   
   创建文件：`sources/test_webview_error.json`
   ```json
   {
     "metadata": {
       "id": "test_error",
       "name": "错误配置测试",
       "version": "2.0.0",
       "type": "webview"
     },
     "baseUrl": "https://invalid-url-that-does-not-exist.com",
     "workflows": {
       "search": {
         "actions": [
           {
             "type": "invalid_action"
           }
         ]
       }
     }
   }
   ```

2. **导入并测试**
   - 导入错误配置的图源
   - 尝试打开详情页

3. **查看日志**
   ```
   预期日志：
   - "WebView引擎初始化失败"
   - "检测图源类型失败，降级到HTTP系统"
   - "使用HTTP系统加载漫画列表"
   ```

#### 预期结果：
- ✅ 不会崩溃
- ✅ 自动降级到HTTP系统
- ✅ 显示友好的错误提示

---

## 🔍 调试技巧

### 1. 启用日志悬浮窗
在设置中启用"日志悬浮窗口"，实时查看日志输出。

### 2. 关键日志点
```typescript
// 图源类型检测
"检测到WebView类型图源" → WebView系统
"使用HTTP类型图源" → HTTP系统

// WebView初始化
"开始初始化WebView引擎"
"WebView引擎初始化成功"
"WebView控制器已附加"

// 数据加载
"使用WebView系统加载漫画列表"
"使用HTTP系统加载漫画列表"
"WebView搜索成功，找到 X 条结果"

// 错误处理
"WebView引擎初始化失败"
"检测图源类型失败，降级到HTTP系统"
```

### 3. 数据库检查
使用数据库工具检查`comic_source`表：
```sql
SELECT id, name, configJson FROM comic_source;
```
确认：
- ID是否正确（不是0）
- configJson是否存在
- configJson是否是有效的JSON

---

## 📊 性能监控

### 关键指标
1. **初始化时间**
   - HTTP系统：< 100ms
   - WebView系统：< 2000ms（首次）

2. **数据加载时间**
   - HTTP系统：500ms - 2s
   - WebView系统：2s - 5s

3. **内存占用**
   - HTTP系统：+ 5MB
   - WebView系统：+ 30MB（WebView实例）

---

## ⚠️ 常见问题

### 问题1：图源ID为0
**原因**：旧版本的`addComicSource`返回固定的0  
**解决**：删除图源，重新导入

### 问题2：configJson为undefined
**原因**：数据库字段名不匹配或数据未正确保存  
**解决**：检查数据库，重新导入图源

### 问题3：WebView初始化失败
**原因**：配置格式错误或网络问题  
**解决**：检查配置格式，查看详细错误日志

### 问题4：搜索无结果
**原因**：
- HTTP系统：API返回空数据
- WebView系统：选择器错误或页面结构变化
**解决**：检查日志，调整配置

---

## ✅ 测试检查清单

### 基础功能
- [ ] 图源导入成功
- [ ] 图源列表显示
- [ ] 图源详情页打开
- [ ] 热门标签加载
- [ ] 最新标签加载
- [ ] 搜索功能
- [ ] 分页加载
- [ ] 图源删除

### HTTP系统
- [ ] HTTP图源正常工作
- [ ] 数据正确显示
- [ ] 错误处理正常

### WebView系统
- [ ] WebView图源识别
- [ ] WebView引擎初始化
- [ ] WebView控制器附加
- [ ] 数据提取成功
- [ ] 数据转换正确
- [ ] 降级机制工作

### 性能
- [ ] 加载速度可接受
- [ ] 内存占用合理
- [ ] 无明显卡顿
- [ ] 无内存泄漏

---

## 📝 测试报告模板

```markdown
## 测试报告

**测试日期**: 2025-11-17  
**测试人员**: [姓名]  
**测试版本**: [版本号]

### 测试环境
- 设备型号：
- 系统版本：
- 应用版本：

### 测试结果

#### HTTP系统
- [ ] 通过 / [ ] 失败
- 问题描述：

#### WebView系统
- [ ] 通过 / [ ] 失败
- 问题描述：

#### 降级机制
- [ ] 通过 / [ ] 失败
- 问题描述：

### 性能数据
- 初始化时间：
- 数据加载时间：
- 内存占用：

### 发现的问题
1. 
2. 
3. 

### 建议
1. 
2. 
3. 
```

---

## 🎯 下一步

测试完成后：
1. 记录测试结果
2. 修复发现的问题
3. 优化性能
4. 编写用户文档
5. 准备发布

---

**测试指南版本**: 1.0  
**最后更新**: 2025-11-17 22:45
