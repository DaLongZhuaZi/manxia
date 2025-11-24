# 图源仓库弹窗问题修复

## 问题分析

点击"图源仓库"按钮后没有弹窗出现。

### 根本原因

`CustomDialogController` 的 `builder` 参数传递方式错误。

**错误代码**：
```typescript
this.sourceRepoDialogController = new CustomDialogController({
  builder: this.buildSourceRepoDialog(),  // ❌ 错误：直接调用函数
  alignment: DialogAlignment.Center,
  autoCancel: true,
  cornerRadius: 16,
  customStyle: true
});
```

**问题说明**：
- `builder` 参数需要一个**函数引用**，而不是函数调用的结果
- `this.buildSourceRepoDialog()` 会立即执行并返回 `void`
- 传递 `void` 给 `builder` 导致弹窗无法正确创建

## 修复方案

### 修复后的代码

```typescript
this.sourceRepoDialogController = new CustomDialogController({
  builder: () => {
    this.buildSourceRepoDialog();  // ✅ 正确：传递箭头函数
  },
  alignment: DialogAlignment.Center,
  autoCancel: true,
  cornerRadius: 16,
  customStyle: true
});
```

### 完整修复

在 `openSourceRepoDialog()` 方法中：

1. **修复 builder 参数**：使用箭头函数包装
2. **添加错误处理**：捕获可能的异常
3. **添加日志**：便于调试

```typescript
private async openSourceRepoDialog(): Promise<void> {
  try {
    this.sourceRepoUrl = '';
    this.selectedRepositoryId = '';
    this.showRepositorySelector = false;
    await this.loadSavedRepositories();
    
    // 创建弹窗控制器
    this.sourceRepoDialogController = new CustomDialogController({
      builder: () => {
        this.buildSourceRepoDialog();
      },
      alignment: DialogAlignment.Center,
      autoCancel: true,
      cornerRadius: 16,
      customStyle: true
    });
    
    this.sourceRepoDialogController.open();
    logger.info(TAG, '图源仓库弹窗已打开');
  } catch (error) {
    logger.error(TAG, '打开图源仓库弹窗失败', String(error));
    this.showToast('打开弹窗失败，请重试');
  }
}
```

## HarmonyOS 弹窗的两种方式

### 方式1：使用 @CustomDialog（推荐）

```typescript
@CustomDialog
struct MyDialog {
  controller: CustomDialogController;
  
  build() {
    Column() {
      Text('对话框内容')
    }
  }
}

// 使用
dialogController = new CustomDialogController({
  builder: MyDialog({ /* 参数 */ }),
  alignment: DialogAlignment.Center
});
```

**优点**：
- 类型安全
- 更好的组件化
- 推荐的官方方式

### 方式2：使用 @Builder

```typescript
@Builder
buildMyDialog() {
  Column() {
    Text('对话框内容')
  }
}

// 使用
dialogController = new CustomDialogController({
  builder: () => {
    this.buildMyDialog();  // 注意：需要箭头函数包装
  },
  alignment: DialogAlignment.Center
});
```

**注意事项**：
- 必须使用箭头函数包装 `@Builder` 方法
- 不能直接调用 `this.buildMyDialog()`

## 测试验证

修复后，点击"图源仓库"按钮应该：

1. ✅ 弹出对话框
2. ✅ 显示"图源仓库"标题
3. ✅ 显示输入框和按钮
4. ✅ 如果有已保存的仓库，显示"展开"按钮
5. ✅ 控制台输出日志：`图源仓库弹窗已打开`

## 常见错误模式

### ❌ 错误1：直接调用函数
```typescript
builder: this.buildDialog()  // 返回 void
```

### ❌ 错误2：传递函数名（没有调用）
```typescript
builder: this.buildDialog  // this 上下文丢失
```

### ✅ 正确：使用箭头函数
```typescript
builder: () => {
  this.buildDialog();
}
```

### ✅ 或者使用 bind
```typescript
builder: this.buildDialog.bind(this)
```

## 相关文件

- **MainMenuPage.ets** (第 1602-1626 行)：修复的方法
- **MainMenuPage.ets** (第 3394-3514 行)：`buildSourceRepoDialog()` 定义

## 总结

问题已修复。核心要点：
- `CustomDialogController` 的 `builder` 需要函数引用
- 使用箭头函数包装 `@Builder` 方法调用
- 添加适当的错误处理和日志

现在点击"图源仓库"按钮应该能正常显示弹窗了！
