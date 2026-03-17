# 标注系统手写笔能力调研（HarmonyOS）

## 文档目标
- 汇总与标注系统相关的手写笔能力与官方案例。
- 为后续“笔/手指分流、压感样式、跨设备手写协同”提供设计依据。

## 官方能力与可落地方向

### 1. 手写笔引擎能力（Pencil Engine）
- 官方能力点：笔刷、笔迹编辑、报点预测、一笔成形、双击手写笔交互。
- 在标注系统中的对应场景：
  - 划线/圈注/箭头等笔迹标注。
  - 划线跟手优化（减少延迟与锯齿）。
  - 手写笔双击切换“划线/橡皮/想法”。
- 参考：
  - https://developer.huawei.com/consumer/cn/hms/huawei-pencilengine/

### 2. ArkUI 触控与手势输入能力
- 官方能力点：触控事件、手势能力、输入来源区分（可用于区分手写笔与手指）。
- 在标注系统中的对应场景：
  - “笔输入=标注，手指输入=翻页/滚动”的交互隔离。
  - 长按划线时屏蔽翻页误触。
  - 对同一段文本提供手写笔优先交互通道。
- 参考：
  - https://developer.huawei.com/consumer/cn/arkui/arkui-stage/
  - https://gitee.com/openharmony/docs/raw/OpenHarmony-5.0.3-Release/zh-cn/application-dev/reference/apis-arkui/_ark_u_i___event_module.md
  - https://gitee.com/openharmony/docs/blob/6ef3072be96ddb9e029f1ee7f303c27f4747b94a/en/application-dev/reference/apis-arkui/arkui-ts/ts-universal-events-touch.md
  - https://gitee.com/openharmony/docs/blob/506ba90bfe3cb5c60491f5fa547dd0fe4f06e20e/en/application-dev/reference/arkui-ts/ts-gesture-settings.md

### 3. 官方分布式手写案例（Codelab）
- 官方案例方向：分布式拉起 + 分布式数据管理 + 跨设备实时绘制。
- 在标注系统中的对应场景：
  - 手机阅读时划线，平板灵感页实时同步展示。
  - 跨设备接续编辑“想法/引用卡片”。
- 参考：
  - https://developer.huawei.com/consumer/cn/codelab/HarmonyOS-JSDistributeDraw/

### 4. 跨设备数据与文件能力
- 官方能力点：跨设备同步、分布式文件访问、跨设备拖拽/剪贴板链路。
- 在标注系统中的对应场景：
  - 引用卡片跨设备拖拽到笔记页。
  - 标注导出文件在多设备可见。
- 参考：
  - https://developer.huawei.com/consumer/cn/app/knowledge-map/
  - https://gitee.com/openharmony/docs/blob/32eee9f190d2c80cbb79a2c609da1adf79876558/en/application-dev/file-management/distributed-fs-overview.md?skip_mobile=true

## 建议分期（手写笔专项）

### P0（当前可落地）
- 笔/手指分流。
- 手写笔触发的划线工具栏快捷入口。
- 手写笔模式下禁用翻页误触。

### P1（增强体验）
- 压感与倾角映射到划线粗细/透明度。
- 报点预测增强跟手。
- 双击笔切换工具。

### P2（鸿蒙特色）
- 跨设备实时手写标注同步。
- 跨设备拖拽引用卡片与剪贴板接力。

## 说明
- 上述“落地方向”是基于官方能力页面与官方案例进行的产品映射。
- 最终接入需结合当前项目 API 版本与设备实际支持情况做二次验证。
