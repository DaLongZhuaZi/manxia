# PDF 引擎（PDFium）落地方案

> 状态：**调研完成，待评审**　｜　调研日期：2026-09-11
> 相关资产：tmp/pdfium-research/（位于仓库内、不在编译与打包路径）

---

## 0. 结论摘要

1. **PDFium 可行且许可友好**：BSD-3-Clause；OpenHarmony 生态已有**自包含、可交叉编译**的移植版本（含全部第三方依赖与自带 clang / GN / Ninja），**无需 gclient sync**。
2. **构建必须在 Linux（本机 WSL2 Ubuntu）完成**：仓库只带 buildtools/linux64（无 Windows 工具链），build.sh 为 bash；F: 仅剩 64.9 GB，构建须放在 WSL 原生文件系统（/home 可用 934 GB）。
3. **体积可接受**：WASM 版引擎本体实测 **3.80 MB**；原生 libpdfium.so（arm64 release、不含 XFA/V8、strip）预计 **8–15 MB**；当前 HAP 全条目 STORED 不压缩 → 1:1 计入，建议**仅出 arm64**。
4. **关键边界**：PDFium 与 HMS PDF Kit 一样是**忠实渲染器**，**不能改字体/行高/字重/字色**（PDF 为固定版式）。字体可控必须另做**文本重排模式**，那是独立工作流，与是否引入引擎无关。
5. 引入引擎的真实收益：**兼容性**（异常/损坏 PDF、更全的字体回退与 CMap）、**渲染一致性**、**自主可控**（不受 HMS 版本约束）、**可深度定制**（页面缓存 / 文本层 / 批注模型）。

---

## 1. 目标与非目标

### 目标
- 作为**可选**渲染内核，覆盖 HMS PDF Kit 渲染异常的场景（实测：中文 searchKey 返回 0；扫描件无文本层）。
- 提供可控的文本层与几何信息，为「自建索引 / 划重点 / 重排模式」打底。
- 保持阅读器 UX 不变（工具栏、目录、搜索、批注入口沿用）。

### 非目标
- 不改变 PDF 排版（改字号/字体/行高）——PDFium 做不到，需重排模式。
- 不替换 HMS PDF Kit 的全部能力（其缩放/适配/连续滚动/页间距/方向/旋转/双页/大纲/搜索/批注/保存已覆盖，且**体积成本为 0**）。
- 不解决扫描件检索（需 OCR）。

---

## 2. 已获取资产（实测）

| 资产 | 位置 | 体积 | 说明 |
|---|---|---|---|
| PDFium OpenHarmony 移植 | tmp/pdfium-research/ohos-pdfium | **1535.87 MB**，63,314 文件 | 含完整构建链与依赖，无历史 out/ |
| 自带 LLVM/Clang | third_party/llvm-build | 351.70 MB | 交叉编译工具链 |
| ICU | third_party/icu | 204.32 MB | 1,755 个源码文件 |
| Skia | third_party/skia | 150.91 MB | 5,667 个源码文件 |
| libc++ / libc++abi | third_party/libc++ | 51.06 MB | |
| freetype/jpeg/zlib/lcms/tiff/png/openjpeg | third_party/* | 合计约 27 MB | 真实源码，无需下载 |
| GN / Ninja | third_party/depot_tools{gn,ninja}、buildtools/linux64/gn | — | **Linux 二进制，无 win 版** |
| NotoSansCJK | third_party/NotoSansCJK | **0 MB（空）** | 仅测试字体；库构建不受影响 |
| PDFium WASM 包 | tmp/pdfium-research/hyzyla-pdfium-2.1.13.tgz | 4.84 MB（pdfium.wasm **3.80 MB**） | 备选/对照 |

### 许可证
LICENSE（13,126 B）= PDFium Authors **BSD-3-Clause**：允许闭源商用；需**保留版权声明、条件与免责声明**；不得以作者名义背书。第三方（Skia/ICU/freetype 等）许可需一并汇总。

---

## 3. 构建方案

### 3.1 构建契约（来自仓库 build.sh）

~~~
./build.sh -t pdfium -A arm64 -r     # release / arm64 → out/rk3568_64
./build.sh -t pdfium -A arm   -r     # 32 位 → out/rk3568
~~~

脚本硬编码 GN 参数：

~~~
target_os="ohos"
is_component_build=true
use_sysroot=false
use_custom_libcxx=false
clang_use_chrome_plugins=false
use_ozone=false
build_chromium_with_ohos_src=false
~~~

release 追加 is_debug=false / is_official_build=true；实际调用：

~~~
third_party/depot_tools/gn gen out/rk3568_64 --args="..."
third_party/depot_tools/ninja -C out/rk3568_64 -j<16> pdfium
~~~

### 3.2 OHOS SDK
ohos_sdk/ 仅含 .install（**未内置 SDK**），执行后从华为镜像下载：

~~~
https://mirrors.huaweicloud.com/openharmony/os/5.1.0-Release/ohos-sdk-windows_linux-public.tar.gz
SDK_API_VERSION=18；items = ets / js / native / previewer / toolchains
~~~

本机已有 DevEco SDK（API 23），但脚本要求 **5.1.0-Release / API 18** native 包，能否替换需 P1 实测（风险 R2）。

### 3.3 执行环境（必须）
- **WSL2 Ubuntu**（已确认：x86_64 / Python 3.12.3 / git 2.43.0 / 16 核 / /home 剩 934 GB）。
- 源码放 **WSL 原生文件系统**（如 ~/pdfium），**不要**放 /mnt/f（跨文件系统极慢）。

---

## 4. 集成方案（建议 A）

### 方案 A：HAR 承载 .so + NAPI 桥（推荐）

~~~
manxia-pdfium/                       # 新建 HAR 模块
  src/main/cpp/
    libs/arm64-v8a/libpdfium.so      # 预编译产物
    napi/pdfium_napi.cpp             # 打开文档 / 渲染页 / 取文本 / 取大纲
  src/main/ets/Framework/PdfiumEngine.ets   # ArkTS 封装（Promise + 串行任务队列）
~~~

- 优点：与现有模块化一致；引擎只做解析/渲染，UI 复用现有阅读器。
- 注意：.so 会随依赖它的 HAP 打包；必须配置 ABI 过滤（仅 arm64）。

### 方案 B：独立 Ability 进程（崩溃隔离）
- 引擎跑在独立进程，经 IPC 返回 PixelMap/文件。
- 优点：native 崩溃不带走主应用；缺点：复杂度与延迟更高。
- 建议：P2 先用 A，P3 若稳定性不达标再评估 B。

---

## 5. 分阶段计划

| 阶段 | 内容 | 产出 | 验收标准 | 预估 |
|---|---|---|---|---|
| **P0 环境就绪** | WSL 内建工作区、取 API18 SDK、gn gen 通过 | 可用构建环境 | gn gen 无错 | 1–2 天 |
| **P1 产出 .so** | ./build.sh -t pdfium -A arm64 -r | libpdfium.so(arm64) | **实测体积**；file 显示 aarch64；依赖可满足 | 2–4 天（16 核约 1–3 小时/次） |
| **P2 NAPI 桥** | 打开/页数/渲染页/取文本/取大纲 | manxia-pdfium HAR | 902MB/7163 页样本不崩；首页渲染 < 800ms | 3–5 天 |
| **P3 接入阅读器** | PixelMap 渲染 + 翻页/缩放/连续滚动 | 可切换内核 | 与 PDF Kit 版功能对齐；内存峰值可测 | 3–5 天 |
| **P4 功能对齐** | 大纲 / 搜索 / 划重点 / 文本复制 | 对齐现有 PDF 功能 | 中文搜索可用（用引擎文本层） | 5–8 天 |
| **P5 体积体验** | 关 XFA/V8、strip、仅 arm64、页面缓存 | 体积/内存达标 | 包体增量 ≤ 15 MB | 1–2 天 |
| **P6（可选）重排模式** | 文本抽取 + 版式分析 + ArkUI 排版 | 字体/行高/字重/字色可控 | 单栏 PDF 可读性可接受 | 独立立项 |

---

## 6. 体积预算

| 配置 | libpdfium.so (arm64) | 备注 |
|---|---|---|
| release + 无 XFA + 无 V8 + strip | **8–15 MB** | 推荐基线 |
| + XFA | +3–6 MB | 仅确有 XFA 需求时 |
| + V8 | +8–12 MB | 建议关闭（安全面更大） |
| 三 ABI 全出 | ×3 | **禁止**，只出 arm64 |
| WASM 对照（实测） | pdfium.wasm = **3.80 MB** | 仅体量参照 |

> 打包约束：当前 HAP **全部条目 STORED 不压缩**，.so 体积 1:1 计入包体。

---

## 7. 许可合规
- 保留 PDFium LICENSE（BSD-3）全文与版权声明，并在「开源许可」页面展示。
- 汇总第三方：Skia(BSD)、ICU(Unicode)、freetype(FTL/GPLv2 双许可，**选 FTL**)、libjpeg-turbo(BSD/IJG)、zlib、lcms(MIT)、libpng、libtiff、libopenjpeg、abseil(Apache-2.0)、libc++(Apache-2.0 with LLVM exception)。

---

## 8. 风险与缓解

| 编号 | 风险 | 影响 | 缓解 |
|---|---|---|---|
| R1 | 构建链仅 Linux | 中 | 固定 WSL2；提供 tools/build-pdfium.sh |
| R2 | 移植版要求 API18 native SDK，项目是 6.1.0(23) | 高 | P1 先用 API18 构建，再在 API23 设备验证加载；不兼容则用 DevEco 23 native SDK 重配 GN |
| R3 | native 崩溃带走整个应用 | 高 | 独立 Ability 进程（方案 B）或严格资源上限 + 重启 |
| R4 | 包体 +8~15 MB | 中 | 仅 arm64、关 XFA/V8、strip、体积门禁 |
| R5 | 构建产物 10–30 GB | 中 | out/ 留在 WSL，不入仓库 |
| R6 | NotoSansCJK 为空 | 低 | 仅影响 pdf_test |
| R7 | 引擎文本层中文仍不可靠 | 中 | 保留现有自建索引兜底 |
| R8 | 引擎升级与安全补丁维护 | 中 | 固定 commit，脚本化构建并记录校验和 |

---

## 9. 回滚方案
- 阅读器增加内核开关（SettingKeys: pdf_render_engine = hmspdfkit | pdfium），默认仍用 HMS PDF Kit。
- 引擎代码集中在 manxia-pdfium 单模块，移除该模块即回滚，不影响既有 PDF 流程。

---

## 10. 立即执行的下一步（P0）
1. WSL 内建 ~/pdfium 工作区，从 tmp/pdfium-research/ohos-pdfium 复制或重新 clone。
2. 执行 ohos_sdk/.install（或指向本机 SDK）取得 API18 native 包，运行 ./build.sh -t pdfium -A arm64 -r。
3. **实测 libpdfium.so 体积与依赖**，用数据校准第 6 节预算，据此决定是否进入 P2。

---

## 附：决策要点
- HMS PDF Kit **体积成本为 0** 且已覆盖大部分渲染能力 → 引入 PDFium 的动机是**兼容性与自主可控**，而非补齐设置项。
- 用户最关心的**字体/排版可控**只能由**重排模式**解决，不要把期望压在引擎上。
