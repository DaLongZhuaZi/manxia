# ManXia 图源系统缺失功能清单

## 完成日期
2025-11-17

## 核心功能

### ✅ 已实现
- [x] 数据库图源表结构
- [x] DataManager图源管理方法
- [x] 图源页面UI框架
- [x] 搜索功能UI
- [x] JSON格式定义
- [x] JSON Schema验证

### ⏳ 待实现

#### 1. 图源解析引擎 🔴 高优先级

**文件**: `Framework/Source/SourceParser.ets`

**功能**:
- [ ] JSON配置文件加载
- [ ] 变量替换引擎（{{baseUrl}}等）
- [ ] JSONPath解析器
- [ ] HTML解析器（CSS选择器）
- [ ] 响应数据映射
- [ ] 错误处理和重试逻辑

**依赖**:
- JSONPath库（需要引入或实现）
- HTML解析库（如果支持HTML源）

#### 2. 图源导入功能 🔴 高优先级

**文件**: `Framework/Source/SourceImporter.ets`

**功能**:
- [ ] JSON文件选择和读取
- [ ] ZIP压缩包解压
- [ ] 配置验证（JSON Schema）
- [ ] 图标文件提取
- [ ] 保存到数据库
- [ ] 导入进度显示
- [ ] 错误提示

**UI组件**:
- [ ] 文件选择对话框
- [ ] 导入进度对话框
- [ ] 导入结果提示

#### 3. 图源执行引擎 🔴 高优先级

**文件**: `Framework/Source/SourceExecutor.ets`

**功能**:
- [ ] HTTP请求构建
- [ ] 请求头管理
- [ ] 速率限制实现
- [ ] 重试机制
- [ ] 响应解析
- [ ] 数据转换
- [ ] 缓存管理

**依赖**:
- HTTP客户端（已有）
- 速率限制器（需实现）

#### 4. 图源测试功能 🟡 中优先级

**文件**: `Framework/Source/SourceTester.ets`

**功能**:
- [ ] 测试热门列表
- [ ] 测试搜索功能
- [ ] 测试详情获取
- [ ] 测试章节列表
- [ ] 测试图片加载
- [ ] 生成测试报告
- [ ] 性能测试

**UI组件**:
- [ ] 测试进度显示
- [ ] 测试结果展示
- [ ] 错误日志查看

#### 5. 图源编辑器 🟡 中优先级

**文件**: `pages/SourceEditorPage.ets`

**功能**:
- [ ] JSON配置编辑
- [ ] 语法高亮
- [ ] 自动补全
- [ ] 实时验证
- [ ] 预览功能
- [ ] 保存和导出

**UI组件**:
- [ ] 代码编辑器
- [ ] 验证错误提示
- [ ] 预览面板

#### 6. 图源市场 🟢 低优先级

**文件**: `pages/SourceMarketPage.ets`

**功能**:
- [ ] 在线图源浏览
- [ ] 图源评分和评论
- [ ] 一键安装
- [ ] 自动更新
- [ ] 图源推荐

#### 7. 认证支持 🟡 中优先级

**文件**: `Framework/Source/SourceAuth.ets`

**功能**:
- [ ] Basic认证
- [ ] Bearer Token
- [ ] OAuth2流程
- [ ] Cookie管理
- [ ] 会话保持
- [ ] 登录状态检查

#### 8. 高级解析功能 🟡 中优先级

**功能**:
- [ ] 正则表达式提取
- [ ] XPath支持
- [ ] 自定义JavaScript执行（安全沙箱）
- [ ] 图片URL解密
- [ ] 动态内容加载
- [ ] WebView集成

#### 9. 分页支持 🟡 中优先级

**类型**:
- [ ] Offset分页
- [ ] Page分页
- [ ] Cursor分页
- [ ] 无限滚动
- [ ] 自动加载更多

#### 10. 过滤器系统 🟡 中优先级

**类型**:
- [ ] 文本输入
- [ ] 单选下拉
- [ ] 多选下拉
- [ ] 复选框
- [ ] 日期范围
- [ ] 数字范围
- [ ] 排序选项

## 数据结构

### 需要添加的数据库字段

#### comic_source表
```sql
ALTER TABLE comic_source ADD COLUMN configJson TEXT;  -- 已存在
ALTER TABLE comic_source ADD COLUMN iconPath TEXT;    -- 图标本地路径
ALTER TABLE comic_source ADD COLUMN rating REAL;      -- 评分
ALTER TABLE comic_source ADD COLUMN downloadCount INTEGER; -- 下载次数
ALTER TABLE comic_source ADD COLUMN isOfficial INTEGER; -- 是否官方源
```

#### 新表：source_settings
```sql
CREATE TABLE IF NOT EXISTS source_settings (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  sourceId INTEGER NOT NULL,
  settingKey TEXT NOT NULL,
  settingValue TEXT NOT NULL,
  createTime INTEGER NOT NULL,
  updateTime INTEGER NOT NULL,
  FOREIGN KEY (sourceId) REFERENCES comic_source(id),
  UNIQUE (sourceId, settingKey)
);
```

#### 新表：source_test_results
```sql
CREATE TABLE IF NOT EXISTS source_test_results (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  sourceId INTEGER NOT NULL,
  testType TEXT NOT NULL,
  isSuccess INTEGER NOT NULL,
  responseTime INTEGER,
  errorMessage TEXT,
  testTime INTEGER NOT NULL,
  FOREIGN KEY (sourceId) REFERENCES comic_source(id)
);
```

## API设计

### SourceManager接口

```typescript
interface SourceManager {
  // 导入
  importFromJson(jsonPath: string): Promise<number>;
  importFromZip(zipPath: string): Promise<number>;
  
  // 执行
  executePopular(sourceId: number, page: number): Promise<Comic[]>;
  executeLatest(sourceId: number, page: number): Promise<Comic[]>;
  executeSearch(sourceId: number, keyword: string, filters: ESObject): Promise<Comic[]>;
  executeDetail(sourceId: number, comicId: string): Promise<ComicDetail>;
  executePages(sourceId: number, chapterId: string): Promise<PageInfo[]>;
  
  // 测试
  testSource(sourceId: number): Promise<TestResult>;
  
  // 管理
  enableSource(sourceId: number): Promise<void>;
  disableSource(sourceId: number): Promise<void>;
  updateSource(sourceId: number, config: ESObject): Promise<void>;
  deleteSource(sourceId: number): Promise<void>;
  
  // 设置
  getSourceSettings(sourceId: number): Promise<ESObject>;
  saveSourceSettings(sourceId: number, settings: ESObject): Promise<void>;
}
```

## 技术挑战

### 1. JSONPath实现
- **问题**: HarmonyOS可能没有现成的JSONPath库
- **解决方案**: 
  - 自己实现简化版JSONPath
  - 或使用正则表达式替代
  - 或引入第三方库

### 2. HTML解析
- **问题**: 需要CSS选择器支持
- **解决方案**:
  - 使用WebView的DOM API
  - 实现简单的CSS选择器解析器
  - 限制只支持基本选择器

### 3. JavaScript执行
- **问题**: 某些源需要执行JavaScript
- **解决方案**:
  - 使用WebView执行
  - 实现安全沙箱
  - 或不支持此类源

### 4. 反爬虫对抗
- **问题**: 很多网站有反爬虫机制
- **解决方案**:
  - User-Agent轮换
  - 请求延迟
  - Cookie管理
  - 可能需要WebView模拟

### 5. 图片加密
- **问题**: 某些源的图片URL是加密的
- **解决方案**:
  - 支持自定义解密函数
  - 使用WebView获取真实URL
  - 或不支持此类源

## 开发优先级

### 第一阶段（核心功能）
1. ✅ JSON格式定义
2. ⏳ 图源解析引擎
3. ⏳ 图源导入功能
4. ⏳ 图源执行引擎（基础）

### 第二阶段（完善功能）
5. ⏳ 图源测试功能
6. ⏳ 认证支持
7. ⏳ 高级解析功能
8. ⏳ 分页和过滤器

### 第三阶段（增强功能）
9. ⏳ 图源编辑器
10. ⏳ 图源市场
11. ⏳ 性能优化
12. ⏳ 错误恢复

## 依赖库需求

### 必需
- [ ] JSONPath解析器
- [ ] HTTP客户端（已有）
- [ ] 数据库ORM（已有）

### 可选
- [ ] HTML解析器
- [ ] 正则表达式引擎（系统自带）
- [ ] ZIP解压库
- [ ] 图片处理库

## 测试计划

### 单元测试
- [ ] JSON解析测试
- [ ] 变量替换测试
- [ ] 数据映射测试
- [ ] 错误处理测试

### 集成测试
- [ ] 完整流程测试
- [ ] 多图源测试
- [ ] 并发测试
- [ ] 性能测试

### 用户测试
- [ ] 导入流程测试
- [ ] 搜索功能测试
- [ ] 阅读流程测试
- [ ] 错误场景测试

## 文档需求

- [ ] 图源开发指南
- [ ] API文档
- [ ] 故障排除指南
- [ ] 最佳实践
- [ ] 示例图源集合

## 时间估算

- 图源解析引擎：3-5天
- 图源导入功能：2-3天
- 图源执行引擎：5-7天
- 图源测试功能：2-3天
- 认证支持：3-4天
- 高级解析功能：5-7天
- 图源编辑器：4-5天
- 图源市场：7-10天

**总计**: 约30-45天（一人全职开发）

---

**创建日期**: 2025-11-17  
**状态**: 规划中  
**优先级**: 高（核心功能）
