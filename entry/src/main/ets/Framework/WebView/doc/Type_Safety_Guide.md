# ArkTS类型安全指南

## 问题说明

ArkTS编译器要求所有变量和表达式都有明确的类型，不允许使用`any`或`unknown`类型。

### 常见错误

```
ERROR: 10605008 ArkTS Compiler Error
Error Message: Use explicit types instead of "any", "unknown" (arkts-no-any-unknown)
```

## 解决方案

### 1. JSON.parse类型声明

#### ❌ 错误写法
```typescript
const result = await this.runWebJavaScript(script);
const data = JSON.parse(result);  // 错误：data类型为any
```

#### ✅ 正确写法
```typescript
// 先定义接口
interface DataType {
  name: string;
  value: number;
}

// 使用类型断言
const result = await this.runWebJavaScript(script);
const data: DataType = JSON.parse(result) as DataType;
```

### 2. 数组类型声明

#### ❌ 错误写法
```typescript
const links = JSON.parse(result);  // 错误：links类型为any
```

#### ✅ 正确写法
```typescript
interface LinkInfo {
  text: string;
  href: string;
  title: string;
}

const links: LinkInfo[] = JSON.parse(result) as LinkInfo[];
```

### 3. 嵌套对象类型声明

#### ❌ 错误写法
```typescript
const perfInfo = JSON.parse(result);  // 错误：perfInfo类型为any
```

#### ✅ 正确写法
```typescript
interface PerformanceTiming {
  loadTime: number;
  domReady: number;
  responseTime: number;
}

interface PerformanceNavigation {
  type: number;
  redirectCount: number;
}

interface PerformanceResources {
  count: number;
  totalSize: number;
}

interface PerformanceData {
  timing: PerformanceTiming;
  navigation: PerformanceNavigation;
  resources: PerformanceResources;
}

const perfInfo: PerformanceData = JSON.parse(result) as PerformanceData;
```

## WebView测试页面类型定义

### 已定义的接口

#### 1. LinkInfo - 链接信息
```typescript
interface LinkInfo {
  text: string;      // 链接文本
  href: string;      // 链接地址
  title: string;     // 链接标题
}
```

**使用示例：**
```typescript
const links: LinkInfo[] = JSON.parse(result) as LinkInfo[];
```

#### 2. ImageInfo - 图片信息
```typescript
interface ImageInfo {
  src: string;       // 图片源地址
  alt: string;       // 替代文本
  width: number;     // 图片宽度
  height: number;    // 图片高度
}
```

**使用示例：**
```typescript
const images: ImageInfo[] = JSON.parse(result) as ImageInfo[];
```

#### 3. MetaTag - Meta标签
```typescript
interface MetaTag {
  name: string;      // 标签名称
  content: string;   // 标签内容
}
```

#### 4. PageMetaInfo - 页面元信息
```typescript
interface PageMetaInfo {
  title: string;         // 页面标题
  url: string;           // 完整URL
  domain: string;        // 域名
  protocol: string;      // 协议
  charset: string;       // 字符集
  referrer: string;      // 来源页面
  readyState: string;    // 文档状态
  lastModified: string;  // 最后修改时间
  meta: MetaTag[];       // Meta标签数组
}
```

**使用示例：**
```typescript
const metaInfo: PageMetaInfo = JSON.parse(result) as PageMetaInfo;
```

#### 5. CookieData - Cookie信息
```typescript
interface CookieData {
  cookie: string;        // 完整Cookie字符串
  cookieCount: number;   // Cookie数量
}
```

**使用示例：**
```typescript
const cookieInfo: CookieData = JSON.parse(result) as CookieData;
```

#### 6. StorageData - LocalStorage信息
```typescript
interface StorageData {
  keys: string[];                    // 所有键名
  count: number;                     // 存储项数量
  data: Record<string, string>;      // 键值对数据
}
```

**使用示例：**
```typescript
const storageInfo: StorageData = JSON.parse(result) as StorageData;
```

#### 7. PerformanceData - 性能信息
```typescript
interface PerformanceTiming {
  loadTime: number;      // 页面加载时间
  domReady: number;      // DOM就绪时间
  responseTime: number;  // 响应时间
}

interface PerformanceNavigation {
  type: number;          // 导航类型
  redirectCount: number; // 重定向次数
}

interface PerformanceResources {
  count: number;         // 资源数量
  totalSize: number;     // 总大小（字节）
}

interface PerformanceData {
  timing: PerformanceTiming;
  navigation: PerformanceNavigation;
  resources: PerformanceResources;
}
```

**使用示例：**
```typescript
const perfInfo: PerformanceData = JSON.parse(result) as PerformanceData;
```

## 最佳实践

### 1. 接口定义位置
将所有接口定义放在文件顶部，便于查找和维护：

```typescript
// 文件顶部
interface LinkInfo { ... }
interface ImageInfo { ... }
interface PageMetaInfo { ... }
// ... 其他接口

// 然后是组件定义
@Component
struct MyComponent { ... }
```

### 2. 接口命名规范
- 使用PascalCase命名（首字母大写）
- 名称应清晰描述数据结构
- 避免使用缩写（除非是通用缩写如URL、ID）

**示例：**
```typescript
✅ interface PageMetaInfo { ... }
✅ interface PerformanceData { ... }
❌ interface PMI { ... }
❌ interface perfdata { ... }
```

### 3. 类型断言
使用`as`关键字进行类型断言：

```typescript
const data: DataType = JSON.parse(result) as DataType;
```

**注意：** 类型断言不会进行运行时检查，需要确保数据结构匹配。

### 4. 可选属性
如果某些属性可能不存在，使用`?`标记为可选：

```typescript
interface UserInfo {
  name: string;      // 必需
  age?: number;      // 可选
  email?: string;    // 可选
}
```

### 5. 联合类型
如果属性可能有多种类型，使用联合类型：

```typescript
interface Response {
  status: 'success' | 'error' | 'pending';
  data: string | number | null;
}
```

### 6. Record类型
用于定义键值对对象：

```typescript
// 键为string，值为string
data: Record<string, string>

// 键为string，值为number
scores: Record<string, number>
```

## 错误处理

### 类型安全的错误处理
```typescript
try {
  const result = await someAsyncOperation();
  const data: DataType = JSON.parse(result) as DataType;
} catch (e) {
  // 类型安全的错误消息提取
  const msg = e instanceof Error ? e.message : String(e);
  logger.error(TAG, `操作失败: ${msg}`);
}
```

## 常见问题

### Q1: 为什么需要类型断言？
**A:** JSON.parse返回的是`any`类型，ArkTS不允许使用`any`，所以需要明确指定类型。

### Q2: 类型断言会进行运行时检查吗？
**A:** 不会。类型断言只是告诉编译器"相信我，这个数据是这个类型"，不会进行实际的类型检查。

### Q3: 如果JSON数据结构不匹配怎么办？
**A:** 会导致运行时错误。建议在生产环境中添加数据验证：

```typescript
function isValidData(data: ESObject): data is DataType {
  return typeof data === 'object' &&
         'name' in data &&
         typeof data.name === 'string';
}

const parsed = JSON.parse(result);
if (isValidData(parsed)) {
  const data: DataType = parsed;
  // 安全使用data
} else {
  logger.error(TAG, '数据格式不正确');
}
```

### Q4: Record<string, string>和{[key: string]: string}有什么区别？
**A:** 在ArkTS中，推荐使用`Record<string, string>`而不是索引签名`{[key: string]: string}`，因为后者可能导致类型安全问题。

## 总结

### 核心原则
1. ✅ 所有变量都要有明确的类型
2. ✅ 使用接口定义复杂数据结构
3. ✅ JSON.parse必须配合类型断言
4. ✅ 错误处理要类型安全
5. ✅ 避免使用any和unknown

### 修复步骤
1. 定义数据结构接口
2. 使用类型断言声明变量类型
3. 确保所有JSON.parse都有明确类型
4. 编译验证无错误

### 工具推荐
- 使用IDE的类型提示功能
- 定期运行编译检查
- 使用ESLint/TSLint检查代码质量

---

**文档版本**: v1.0.0  
**更新日期**: 2025-11-17  
**适用范围**: HarmonyOS ArkTS开发
