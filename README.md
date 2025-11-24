<<<<<<< HEAD
# 漫匣 (ManXia)

<div align="center">

**一款基于 HarmonyOS Next 的现代化漫画阅读应用**

[![HarmonyOS](https://img.shields.io/badge/HarmonyOS-Next-blue)](https://developer.huawei.com/consumer/cn/harmonyos/)
[![ArkTS](https://img.shields.io/badge/Language-ArkTS-green)](https://developer.huawei.com/consumer/cn/doc/harmonyos-guides/arkts-get-started-0000001504769321)
[![License](https://img.shields.io/badge/License-MIT-yellow.svg)](LICENSE)

</div>

## 📖 项目简介

漫匣是一款专为 HarmonyOS Next 平台开发的漫画阅读应用，采用纯 ArkTS 架构，提供流畅的阅读体验和丰富的功能特性。

### ✨ 核心特性

- 🎨 **现代化UI设计** - 遵循 HarmonyOS 设计规范，支持深色/浅色主题自动切换
- 📚 **多图源支持** - 支持 WebView 和 API 两种图源类型，可扩展的图源系统
- 🔍 **智能搜索** - 支持跨图源搜索，快速定位想看的漫画
- 📖 **优秀的阅读体验** - 支持单页/双页模式，图片预加载，流畅翻页
- 💾 **本地管理** - 支持本地漫画导入，电子书阅读（EPUB/PDF）
- 🔐 **图源登录** - 支持图源账号登录，访问个人收藏和历史记录
- 🎯 **图片处理** - 支持特殊图源的图片解扰算法（如禁漫天堂）
- 🌐 **离线阅读** - 支持漫画下载，随时随地阅读

### 🏗️ 技术架构

- **开发语言**: ArkTS (HarmonyOS Next API 19)
- **架构模式**: ECS (Entity-Component-System)
- **UI框架**: ArkUI
- **数据存储**: 关系型数据库 (RDB)
- **网络请求**: HTTP Client + WebView
- **图片处理**: Image Kit + 自定义解扰算法

## 🚀 快速开始

### 环境要求

- DevEco Studio 5.0.0 或更高版本
- HarmonyOS Next SDK (API 19)
- Node.js 16.0.0 或更高版本

### 安装步骤

1. 克隆项目
```bash
git clone https://github.com/DaLongZhuaZi/manxia.git
cd manxia
```

2. 安装依赖
```bash
ohpm install
```

3. 打开项目
- 使用 DevEco Studio 打开项目
- 等待依赖下载完成

4. 运行项目
- 连接 HarmonyOS Next 设备或启动模拟器
- 点击运行按钮

## 📂 项目结构

```
manxia/
├── entry/                          # 主模块
│   └── src/main/
│       ├── ets/                    # ArkTS 源代码
│       │   ├── Framework/          # 核心框架
│       │   │   ├── WebView/        # WebView 图源引擎
│       │   │   ├── ImageProcessing/# 图片处理系统
│       │   │   ├── Data/           # 数据管理
│       │   │   ├── Managers/       # 系统管理器
│       │   │   └── Components/     # UI 组件
│       │   ├── Pages/              # 页面组件
│       │   └── Utils/              # 工具类
│       └── resources/              # 资源文件
├── sources/                        # 图源配置文件
├── docs/                           # 文档目录
│   ├── development/                # 开发文档
│   ├── analysis/                   # 分析报告
│   └── logs/                       # 日志文件
├── keiyoushi-extensions-source/    # Keiyoushi 扩展源参考
├── copymanga-copy20/               # 拷贝漫画源参考
└── manxia-extensions-source/       # 自定义扩展源

```

## 🎯 主要功能

### 1. 图源系统

支持两种图源类型：

#### WebView 图源
- 基于 WebView 的网页抓取
- 支持复杂的网页交互和 JavaScript 执行
- 配置文件驱动，易于扩展
- 示例：禁漫天堂、拷贝漫画

#### API 图源
- 基于 HTTP API 的数据获取
- 性能更好，响应更快
- 支持复杂的认证和加密
- 示例：Komiic、PicaComic

### 2. 图片处理

- **图片解扰**: 支持禁漫天堂等特殊图源的图片解扰算法
- **图片缓存**: 智能缓存机制，减少网络请求
- **图片预加载**: 提前加载下一页，流畅阅读体验
- **懒加载**: 优化内存使用，支持大量图片

### 3. 阅读器

- **单页模式**: 传统的上下滚动阅读
- **双页模式**: 模拟实体书的翻页效果
- **缩放功能**: 双击放大，捏合缩放
- **进度保存**: 自动记录阅读进度

### 4. 本地管理

- **漫画导入**: 支持 ZIP/CBZ 格式
- **电子书阅读**: 支持 EPUB/PDF 格式
- **书库管理**: 分类、排序、搜索
- **阅读历史**: 记录阅读轨迹

## 🔧 配置说明

### 图源配置

图源配置文件位于 `sources/` 目录，采用 JSON 格式：

```json
{
  "metadata": {
    "id": "source_id",
    "name": "图源名称",
    "version": "1.0.0",
    "baseUrl": "https://example.com"
  },
  "capabilities": {
    "urlResolver": true,
    "pagination": true,
    "imageDecoding": false
  },
  "workflows": {
    "popular": { /* 热门漫画工作流 */ },
    "search": { /* 搜索工作流 */ },
    "getMangaDetail": { /* 获取详情工作流 */ }
  }
}
```

详细配置说明请参考 [图源配置文档](docs/development/)

## 📚 开源致谢

本项目在开发过程中参考和使用了以下开源项目的代码和思路，特此致谢：

### 核心参考项目

#### 1. Keiyoushi Extensions
- **项目地址**: https://github.com/keiyoushi/extensions
- **使用内容**: 图源扩展架构设计、部分图源实现参考
- **许可证**: Apache License 2.0
- **说明**: Keiyoushi 是 Tachiyomi 的社区维护版本，提供了大量的漫画图源扩展。本项目参考了其扩展架构设计和部分图源的实现逻辑，并根据 HarmonyOS 平台特性进行了重新实现。

#### 2. CopyManga Copy20
- **项目地址**: https://github.com/stevenyomi/copymanga-copy20
- **使用内容**: 拷贝漫画图源的 API 接口分析和实现参考
- **许可证**: MIT License
- **说明**: 该项目提供了拷贝漫画的 API 接口文档和实现示例，本项目参考了其 API 调用方式和数据结构设计。

### 技术栈

- **HarmonyOS Next SDK** - 华为官方 SDK
- **ArkTS** - HarmonyOS 官方开发语言
- **ArkUI** - HarmonyOS 官方 UI 框架

### 图源实现参考

本项目的图源实现参考了多个开源项目的思路和代码：

- **禁漫天堂图源**: 参考 Keiyoushi Extensions 中的 JMComic 实现
- **拷贝漫画图源**: 参考 CopyManga Copy20 项目
- **Komiic 图源**: 参考官方 API 文档和社区实现
- **图片解扰算法**: 参考 Tachiyomi 社区的解扰算法实现

### 特别说明

1. **代码重写**: 所有参考的代码都已根据 HarmonyOS 平台特性和 ArkTS 语言规范进行了完全重写
2. **架构适配**: 采用了适合 HarmonyOS 的 ECS 架构，与原项目架构有本质区别
3. **功能扩展**: 在参考基础上增加了许多原创功能和优化
4. **许可证遵守**: 严格遵守所有参考项目的开源许可证要求

## 📄 许可证

本项目采用 MIT License 开源协议。

```
MIT License

Copyright (c) 2025 ManXia Team

Permission is hereby granted, free of charge, to any person obtaining a copy
of this software and associated documentation files (the "Software"), to deal
in the Software without restriction, including without limitation the rights
to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
copies of the Software, and to permit persons to whom the Software is
furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all
copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
SOFTWARE.
```

## 🤝 贡献指南

欢迎提交 Issue 和 Pull Request！

### 贡献流程

1. Fork 本项目
2. 创建特性分支 (`git checkout -b feature/AmazingFeature`)
3. 提交更改 (`git commit -m 'Add some AmazingFeature'`)
4. 推送到分支 (`git push origin feature/AmazingFeature`)
5. 提交 Pull Request

### 开发规范

- 遵循 ArkTS 编码规范
- 遵循项目规则文件 `.trae/rules/project_rules.md`
- 编写清晰的提交信息
- 添加必要的注释和文档

## 📮 联系方式

- **Issues**: https://github.com/DaLongZhuaZi/manxia/issues
- **Discussions**: https://github.com/DaLongZhuaZi/manxia/discussions

## 🌟 Star History

如果这个项目对你有帮助，请给我们一个 Star ⭐️

## ⚠️ 免责声明

1. 本项目仅供学习交流使用，请勿用于商业用途
2. 使用本项目访问的内容版权归原作者所有
3. 请支持正版漫画，尊重作者的劳动成果
4. 使用本项目产生的任何法律责任由使用者自行承担

---

<div align="center">
Made with ❤️ by ManXia Team
</div>
=======
# 漫匣
>>>>>>> fcebfc6841662c6267b2eb97be23e4e9771025ea
