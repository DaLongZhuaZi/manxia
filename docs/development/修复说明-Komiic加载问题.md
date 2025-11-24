# Komiic漫画加载问题修复说明

## 问题分析

### 场景一:从图源详情页进入阅读器
**现象**: 图片请求返回HTTP 400错误
**原因**: Cookie字符串包含大量转义字符和嵌套引号,导致服务器无法正确解析

**日志证据**:
```
Cookie: komiic-access-token=...; "_gid=...; \"_gid=...; ...
```

Cookie在数据库中被多次JSON序列化,导致格式错误:
- `\"` 转义引号
- `\\\"` 双重转义引号  
- 多余的独立引号

### 场景二:从书库进入阅读器
**现象**: 卡在"步骤3: 开始获取WebView UserAgent",无法继续
**原因**: WebView未就绪时,`runJavaScript`回调永远不会被调用,导致Promise永远pending

**日志证据**:
```
[00:03:57.964] 📋 步骤3: 开始获取WebView UserAgent
(之后无任何日志输出)
```

## 修复方案

### 修复1: 清理Cookie格式 (CookieManager.ets)

**位置**: `getCookieString()` 方法

**修改内容**:
```typescript
let cookieStr: string = parts.join('; ');

// [修复] 清理Cookie字符串中的转义字符和多余引号
// 移除转义的引号: \" -> "
cookieStr = cookieStr.replace(/\\"/g, '');
// 移除单独的引号: " -> (空)
cookieStr = cookieStr.replace(/"/g, '');
// 移除多余的分号和空格
cookieStr = cookieStr.replace(/;\s*;/g, ';').trim();
```

**效果**: 
- 清理所有转义字符
- 移除多余引号
- 规范化Cookie格式
- 确保服务器能正确解析

### 修复2: WebView UserAgent获取超时保护 (MangaSourceEngine.ets)

**位置**: `getUserAgent()` 和 `getWebViewUserAgent()` 方法

**修改内容**:
```typescript
private async getUserAgent(): Promise<string> {
  return new Promise<string>((resolve, reject) => {
    try {
      // [修复] 添加超时机制，防止WebView未就绪时无限等待
      const timeout = setTimeout(() => {
        reject(new Error('WebView UserAgent获取超时'));
      }, 3000); // 3秒超时
      
      this.engineConfig.webViewController.runJavaScript(
        'navigator.userAgent',
        (error, result) => {
          clearTimeout(timeout);
          if (error) {
            reject(new Error(`获取UserAgent失败: ${error.message}`));
            return;
          }
          resolve(result as string);
        }
      );
    } catch (error) {
      reject(error);
    }
  });
}

public async getWebViewUserAgent(): Promise<string> {
  try {
    const ua: string = await this.getUserAgent();
    return ua;
  } catch (error) {
    // [修复] 如果WebView获取失败，返回默认UserAgent
    logger.warn(TAG, `WebView UserAgent获取失败，使用默认值: ${error}`);
    return 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/142.0.0.0 Safari/537.36';
  }
}
```

**效果**:
- 添加3秒超时机制
- 超时后自动使用默认UserAgent
- 避免无限等待导致流程阻塞
- 确保两个场景都能正常进行

## 修复后的预期行为

### 场景一:从图源详情页进入
1. ✅ Cookie格式正确,不再包含转义字符
2. ✅ 图片请求成功(HTTP 200)
3. ✅ 图片正常加载显示

### 场景二:从书库进入  
1. ✅ WebView UserAgent获取不再阻塞
2. ✅ 3秒内获取成功或使用默认值
3. ✅ 流程继续,图片正常加载

## 技术要点

### Cookie格式规范
- Cookie应该是简单的键值对,用分号和空格分隔
- 不应包含引号(除非值本身需要)
- 不应包含转义字符

**正确格式**:
```
komiic-access-token=xxx; _gid=yyy; _ga=zzz
```

**错误格式**:
```
komiic-access-token=xxx; "_gid=yyy; \"_ga=zzz
```

### WebView异步调用保护
- 所有依赖WebView的异步操作都应该有超时保护
- 超时时间建议3-5秒
- 必须提供fallback机制
- 避免Promise永远pending

## 测试建议

1. **场景一测试**:
   - 从图源详情页进入漫画阅读器
   - 检查图片是否正常加载
   - 查看日志确认Cookie格式正确

2. **场景二测试**:
   - 从书库进入漫画阅读器
   - 确认不会卡在UserAgent获取步骤
   - 检查图片是否正常加载

3. **日志检查**:
   - Cookie应该不包含转义字符
   - UserAgent获取应该在3秒内完成或超时
   - 图片请求应该返回HTTP 200

## 相关文件

- `f:\DevEcoStudioProject\manxia\entry\src\main\ets\Framework\Managers\CookieManager.ets`
- `f:\DevEcoStudioProject\manxia\entry\src\main\ets\Framework\WebView\MangaSourceEngine.ets`
- `f:\DevEcoStudioProject\manxia\entry\src\main\ets\pages\MangaReaderPage.ets`
