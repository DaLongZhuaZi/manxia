# 隐私书库功能实现指南

## 功能概述
实现一个"隐私书库"功能，用户可以将漫画、电子书、小说等内容标记为隐私内容。进入隐私书库需要通过生物识别（指纹/面部识别）或密码验证。

## 已完成的工作

### 1. 数据库层 ✅
- **DatabaseSchema.ets**: 在 `comic_info`、`online_comic_info`、`ebook_info` 表中添加了 `isPrivate INTEGER DEFAULT 0` 字段
- **DatabaseTypes.ets**: 在相关接口中添加了 `isPrivate` 字段

### 2. 数据模型层 ✅
- **DataManager.ets**: 在 `ComicInfoInput`、`ComicInfo`、`OnlineComicInfo` 接口中添加了 `isPrivate` 字段
- **EBookModels.ets**: 在 `EBook` 类中添加了 `isPrivate` 字段和构造函数参数
- **MangaModels.ets**: 需要添加 `isPrivate` 字段（待完成）

### 3. 管理器层 ✅
- **PrivacyModeManager.ets**: 创建了隐私模式管理器
  - 支持生物识别验证（指纹/面部识别）
  - 支持密码验证（备用方案）
  - 提供隐私模式状态管理和监听器机制

### 4. UI组件层 ✅
- **PrivacyAuthDialog.ets**: 创建了密码验证对话框组件
  - `PrivacyAuthDialog`: 密码输入验证对话框
  - `SetPrivacyPasswordDialog`: 设置隐私密码对话框

### 5. 主页面集成 🔄
- **MainMenuPage.ets**: 
  - ✅ 导入了 `PrivacyModeManager`
  - ✅ 添加了隐私模式管理器实例和状态
  - ⏳ 需要在 `aboutToAppear` 中注册隐私模式监听器
  - ⏳ 需要在 `aboutToDisappear` 中清理监听器
  - ⏳ 需要实现长按"书库"按钮触发验证的逻辑
  - ⏳ 需要实现隐私模式UI状态切换（背景层显示"隐私模式"文字和图标）
  - ⏳ 需要实现隐私书库内容筛选逻辑

## 待完成的工作

### 1. MainMenuPage 长按书库按钮实现
需要找到底部导航栏中"书库"按钮的实现位置，添加长按手势：

```typescript
.gesture(
  LongPressGesture({ repeat: false })
    .onAction(() => {
      // 触发震动反馈
      vibrator.startVibration({...});
      // 启动隐私模式验证
      this.handlePrivacyModeAuth();
    })
)
```

### 2. 隐私模式验证流程
```typescript
private async handlePrivacyModeAuth(): Promise<void> {
  // 1. 尝试生物识别
  const success = await this.privacyModeManager.enterPrivacyMode();
  
  if (!success) {
    // 2. 生物识别失败，显示密码输入对话框
    this.showPrivacyPasswordDialog();
  } else {
    // 3. 验证成功，刷新书库
    this.refreshLibraryWithPrivacyMode();
  }
}
```

### 3. 隐私模式UI状态
在隐私模式下：
- 背景层显示"隐私模式"文字
- 显示系统图标 `$r('sys.symbol.key_shield_fill')`
- 书库内容只显示标记为隐私的内容

### 4. 内容筛选逻辑
修改书库加载方法，根据隐私模式状态筛选内容：

```typescript
private async loadLibraryContent(): Promise<void> {
  let allContent = await this.dataManager.getAllContent();
  
  if (this.isPrivacyMode) {
    // 只显示隐私内容
    allContent = allContent.filter(item => item.isPrivate === 1);
  } else {
    // 只显示非隐私内容
    allContent = allContent.filter(item => item.isPrivate !== 1);
  }
  
  // ... 应用其他筛选条件
}
```

### 5. 设置隐私内容功能
在漫画/电子书/小说详情页添加"设置为隐私内容"的开关：

```typescript
// MangaDetailPage.ets, EBookDetailPage.ets 等
private async togglePrivacy(isPrivate: boolean): Promise<void> {
  await this.dataManager.updatePrivacyStatus(this.itemId, isPrivate);
  this.showToast(isPrivate ? '已加入隐私书库' : '已移出隐私书库');
}
```

### 6. 数据库迁移
由于添加了新字段，需要：
- 卸载并重新安装APP以重建数据库
- 或者在 `DatabaseManager.ets` 中添加迁移逻辑（类似 `ensureNSFWColumns`）

## 需要查找的代码位置

1. **底部导航栏"书库"按钮**: 
   - 搜索关键词: `TabIndex.LIBRARY`、`buildLibraryTab`、底部导航栏构建方法
   - 可能在 `MainMenuPage.ets` 的某个 `@Builder` 方法中

2. **书库内容加载方法**:
   - 搜索关键词: `loadLibraryManga`、`loadLibraryEBooks`、`loadLibraryNovels`
   - 需要在这些方法中添加隐私模式筛选

3. **背景层组件**:
   - 已有 `GlobalBackgroundLayer` 组件
   - 需要扩展以支持隐私模式状态显示

## 编译错误修复

当前存在的编译警告（非阻塞性）：
- `PrivacyAuthDialog.ets` 中的异常处理警告
- 这些是 ArkTS 的严格模式警告，可以通过添加 try-catch 包装来修复

## 下一步行动

1. 查找并修改底部导航栏"书库"按钮，添加长按手势
2. 实现隐私模式验证流程和对话框显示
3. 在 `aboutToAppear` 和 `aboutToDisappear` 中添加监听器管理
4. 实现隐私模式UI状态切换
5. 修改书库内容加载逻辑，添加隐私筛选
6. 在详情页添加隐私内容设置功能
7. 测试完整流程
