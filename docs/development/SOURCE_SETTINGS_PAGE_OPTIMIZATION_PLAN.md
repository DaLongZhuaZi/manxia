# 图源设置页面优化方案

## 当前问题

1. **标题显示"暂不可用"** - 实际功能已实现
2. **缺少说明文本** - 用户不知道各选项作用  
3. **交互单一** - 只有TextInput和Toggle
4. **布局简陋** - 缺少视觉层次
5. **Toast不可见** - showToast只记录日志

## 优化方案

### 1. 添加Popup说明

为每个设置项添加问号图标，点击显示详细说明：

```typescript
@Builder
SettingItemWithHelp(title: string, helpText: string, content: () => void) {
  Row() {
    Row() {
      Text(title)
        .fontSize(14)
        .fontColor(this.getColor('text_secondary'))
      Image($r('app.media.ic_help'))
        .width(16)
        .height(16)
        .margin({ left: 4 })
        .bindPopup(this.showHelp, {
          message: helpText,
          placement: Placement.Top,
          enableArrow: true
        })
    }
    .layoutWeight(1)
    
    content()
  }
  .width('100%')
  .padding({ top: 12, bottom: 12 })
}
```

### 2. 使用Slider替代数字输入

```typescript
// 首页每页条目数: 10-100
Slider({
  value: this.homeItemsPerPage,
  min: 10,
  max: 100,
  step: 5
})
.onChange((value: number) => {
  this.homeItemsPerPage = value;
})

Text(`${this.homeItemsPerPage} 条`)
  .fontSize(14)
  .fontColor(this.getColor('text_primary'))
```

### 3. 实现真正的Toast

```typescript
import { promptAction } from '@kit.ArkUI';

private showToast(message: string): void {
  promptAction.showToast({
    message: message,
    duration: 2000,
    bottom: 100
  });
  logger.info(TAG, message);
}
```

### 4. 优化布局层次

```typescript
// 使用卡片式分组
Column() {
  // 分组标题
  Row() {
    Image($r('app.media.ic_settings'))
      .width(20)
      .height(20)
    Text('基础设置')
      .fontSize(16)
      .fontWeight(FontWeight.Medium)
      .margin({ left: 8 })
  }
  .margin({ bottom: 16 })
  
  // 设置项
  Divider()
  this.SettingItemWithHelp(...)
  Divider()
  this.SettingItemWithHelp(...)
}
.padding(16)
.borderRadius(12)
.backgroundColor(this.getColor('card_background'))
.shadow({...})
```

### 5. 添加Cookie管理增强功能

```typescript
// Cookie状态卡片
Column() {
  Row() {
    Text('Cookie状态')
      .fontSize(14)
      .fontColor(this.getColor('text_secondary'))
    Blank()
    Text(this.cookieStatusText)
      .fontSize(12)
      .fontColor(this.hasCookie ? Color.Green : Color.Orange)
  }
  
  // Cookie操作按钮组
  Row() {
    Button('查看Cookie')
      .onClick(() => this.viewCookieDetails())
    Button('清除Cookie')
      .onClick(() => this.clearCookie())
    Button('自动获取')
      .onClick(() => this.fetchCookieWithoutLogin())
  }
  .justifyContent(FlexAlign.SpaceBetween)
}
```

### 6. 添加表单验证

```typescript
private validateSettings(): boolean {
  if (this.homeItemsPerPage < 10 || this.homeItemsPerPage > 100) {
    this.showToast('每页条目数应在10-100之间');
    return false;
  }
  
  if (this.loginUrl && !this.isValidUrl(this.loginUrl)) {
    this.showToast('登录页地址格式不正确');
    return false;
  }
  
  return true;
}

private isValidUrl(url: string): boolean {
  return url.startsWith('http://') || url.startsWith('https://');
}
```

## 实施步骤

1. 修改标题，移除"暂不可用"
2. 实现真正的Toast提示
3. 为每个设置项添加说明文本
4. 使用Slider替代数字输入框
5. 优化卡片式布局
6. 添加表单验证
7. 增强Cookie管理功能

## 设置项说明文本

- **首页每页条目数**: 控制图源首页每次加载的漫画数量，范围10-100
- **阅读器预加载数量**: 阅读时提前加载的图片页数，提高翻页流畅度
- **预加载当前章节**: 打开章节时自动预加载所有图片
- **预加载下一章节**: 阅读到最后几页时自动预加载下一章节
- **边看边下载**: 阅读时自动下载当前章节到本地
- **登录页地址**: 图源的登录页面URL，用于WebView登录
- **账号/密码选择器**: CSS选择器，用于自动填充登录表单
- **提交按钮选择器**: CSS选择器，用于自动点击登录按钮
