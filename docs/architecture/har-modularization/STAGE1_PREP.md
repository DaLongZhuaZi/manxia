# 漫匣 HAR 模块化 — Stage 1 实操前准备（manxia-native 实证调查）

> 时间：2026-08-20 01:50（goal round 1）
> 性质：非侵入调查 + 草稿文档；**不修改任何 build 配置、不移动任何源码**（门禁 M0 未过）。
> 目的：把 Stage 1 的执行从"经验性计划"升级为"文件级可执行计划"，降低实操期返工。

---

## 1. 实证结论：真正的迁移体量很小（远小于目录总大小）

### 1.1 关键事实
- `entry/src/main/cpp` 下磁盘文件约 16,000+ 个，但 **git 只跟踪 349 个文件**；其余绝大多数是构建产物/下载的第三方源码，已被 `.gitignore` 忽略（`**/build`、`.cxx`、`**/CMakeFiles`、`**/CMakeCache.txt`、`**/Makefile`、`*.bak`，以及 `webdav/curl-8.5.0/|mbedtls-3.5.1/|libssh2-1.11.0/` 整目录忽略）。
- 结论：**本阶段物理移动的"源码"= 349 个已跟踪文件**；风险 R2（"177MB 大目录迁移"）应修正为"少量文件移动 + 本机未跟踪依赖目录就地维持（build-*/install-* 等不移动、留在原模块或随模块调整）"。
- ⚠️ 但存在**本地构建依赖**问题：`webdav` 编译依赖本机 `curl-8.5.0/mbedtls-3.5.1/libssh2-1.11.0` 源码 + 已入库的 prebuilt `install-curl-https-arm64/lib/libcurl.so`；`transfer_rtc` 依赖本机 `install-libdatachannel-arm64`、`install-mbedtls-rtc-arm64` 预编译库。**迁移方案必须保证这些本地产物被新模块正确引用**（详见 §4 决策项 D1）。

### 1.2 已跟踪文件清单（349 个，按子项目）
| 子项目 | 已跟踪文件数 | 关键内容（so 来源） | 输出 .so |
|---|---|---|---|
| cpp 根 | 2 | `CMakeLists.txt`（jsvm_engine + 4 个 add_subdirectory）、`jsvm_engine.cpp` | `libjsvm_engine.so` |
| quickjs | 72 | `CMakeLists.txt`、`legado_api.h`、`legado_api_full.cpp`、`quickjs_napi.cpp`、`quickjs/`(QuickJS 源码树)、`types/libquickjs_engine/` | `libquickjs_engine.so` |
| webdav | 54 | `CMakeLists.txt`、`webdav_client.cpp/.h`、`ftp_client.cpp/.h`、`network_scanner`、`smb_client`、`smb_napi`、`scanner_napi`、`curl_global`、`include/curl/*`、`install-curl-https-arm64/**`(含已入库 prebuilt `libcurl.so`)、各种 build_*.bat | `libwebdav_native.so` |
| avif | 12 | `CMakeLists.txt`、`avif_decoder.cpp/.h`、`avif_napi.cpp`、`README`、`build_*.bat/.sh`、`thirdparty/libavif/include/avif/*.h` | `libavif_decoder.so` |
| transfer_rtc | 5 | `CMakeLists.txt`、`transfer_rtc_native.cpp`、`mbedtls_rtc_config.h`、`build_*.ps1/.bat` | `libtransfer_rtc_native.so` |
| third_party | 195 | `libsmb2` 源码树（SMB 支持，当前被 webdav CMake 引用） | —（静态/随 webdav） |
| types | 8 | 4 个 `index.d.ts + oh-package.json5`（libjsvm_engine / libwebdav_native / libavif_decoder / libtransfer_rtc_native） | —（类型包） |

另有残留目录待清理：`entry/src/main/cpp/webdav(1)`（Windows 副本残留，git 中仅部分条目，cleanup 候选）。

### 1.3 每处 CMake 的 target → so 名映射（ArkTS import 名的依据）
- 根：`add_library(jsvm_engine SHARED jsvm_engine.cpp)` → `libjsvm_engine.so`
- quickjs：`add_library(quickjs_engine SHARED ...)` → `libquickjs_engine.so`
- webdav/avif/transfer_rtc：各子目录 CMakeLists 分别产出 `libwebdav_native.so` / `libavif_decoder.so` / `libtransfer_rtc_native.so`
- ArkTS 侧 import 语句（**一字不可改**）：
  `import quickjs from 'libquickjs_engine.so'`、`import avifDecoderNativeImport from 'libavif_decoder.so'`、`import webdavNativeModuleImport from 'libwebdav_native.so'`、`import transferRtcNativeModuleImport from 'libtransfer_rtc_native.so'`、`import jsvmEngineModule from 'libjsvm_engine.so'`

---

## 2. 最小可行性实验方案（Step 1，用户编译验证用）

> 目的：用**最小改动**验证 R0.1 方案 A（types 跟随 manxia-native，entry 只依赖模块名）是否可行；可行则铺开到 4 个 so，不可行则降级方案 B（entry 用 `file:../manxia-native/src/main/cpp/types/*` 直引）。

### 2.1 步骤（仅 quickjs 一个 so）
1. 建 `manxia-native/` 骨架（3 个文件，见 §3 草稿）。
2. `git mv entry/src/main/cpp/quickjs manxia-native/src/main/cpp/quickjs`（72 个已跟踪文件）。
3. 根 `entry/src/main/cpp/CMakeLists.txt` 删除 `add_subdirectory(quickjs)`（备份 .bak_harmod）。
4. `manxia-native/src/main/cpp/CMakeLists.txt` 建：仅包含 quickjs 的 `add_subdirectory(quickjs)`（首版直接以 quickjs 子目录为模块级 CMake 内容）。
5. 配置接线（方案 A）：
   - 根 `build-profile.json5` modules 增加 `manxia-native`；根 `oh-package.json5` 增加 `"manxia_native": "file:./manxia-native"`。
   - `manxia-native/oh-package.json5` devDependencies 声明 `"libquickjs_engine.so": "file:./src/main/cpp/quickjs/types/libquickjs_engine"`。
   - `entry/oh-package.json5` devDependencies 删除 `libquickjs_engine.so` 条目。
6. 静态核对：grep `libquickjs_engine` 全 ets 仍 exist 且 import 名未变。
7. **用户编译** `hvigorw assembleHap --no-daemon`，验收：编译通过 + 小说/图源 JS 执行（经 NativeJsEngine 或 Legado 引擎 quickjs 路径）可用 + JsvmPlaygroundPage 可运行。

### 2.2 结果分支
- ✅ 编译通过：确认方案 A 可行 → 铺开 avif/webdav/transfer_rtc/jsvm_engine 到 manxia-native（每 so 一个独立小步 + 用户复验）。
- ❌ 失败（so 无法解析/打包）：降级方案 B —— `entry/oh-package.json5` 保留全部 `lib*.so` 条目，但 file: 指向 `../manxia-native/src/main/cpp/<子>/types/<so>`；同时把 manxia-native 的 types 目录统一到 `manxia-native/src/main/cpp/types/` 位置以便引用一致性。

---

## 3. manxia-native 骨架草稿（拷贝即用，先不落库）

### 3.1 manxia-native/build-profile.json5
```json5
{
  "apiType": "stageMode",
  "buildOption": {
    "externalNativeOptions": {
      "path": "./src/main/cpp/CMakeLists.txt",
      "arguments": "",
      "cppFlags": ""
    }
  },
  "buildOptionSet": [],
  "targets": [ { "name": "default" } ]
}
```

### 3.2 manxia-native/oh-package.json5（方案 A 全量版：4+1 个 so）
```json5
{
  "name": "manxia_native",
  "version": "1.0.0",
  "description": "漫匣原生能力模块：AVIF 解码 / JSVM+QuickJS 引擎 / WebDAV(SMB+curl) / 局域网传书 RTC",
  "main": "",
  "author": "",
  "license": "",
  "dependencies": {},
  "devDependencies": {
    "libjsvm_engine.so": "file:./src/main/cpp/types/libjsvm_engine",
    "libquickjs_engine.so": "file:./src/main/cpp/quickjs/types/libquickjs_engine",
    "libwebdav_native.so": "file:./src/main/cpp/types/libwebdav_native",
    "libavif_decoder.so": "file:./src/main/cpp/types/libavif_decoder",
    "libtransfer_rtc_native.so": "file:./src/main/cpp/types/libtransfer_rtc_native"
  }
}
```

### 3.3 manxia-native/hvigorfile.ts
```ts
import { harTasks } from '@ohos/hvigor-ohos-plugin';
export default {
  system: harTasks,
  plugins: []
};
```

### 3.3b manxia-native/src/main/module.json5（HAR 必需，M1 首轮反馈后补充）
> HAR 模块也必须包含 src/main/module.json5，且 type 必须是 "har"（HAP 用 "entry"/"feature"，HSP 用 "shared"）。后续新建任何 HAR 静态库模块都必须带此文件。内容如下：
> ⚠️ 命名规则（M1 第二轮报错 00303038 教训）：module.name 必须匹配 `^[a-zA-Z][0-9a-zA-Z_.]*$`（**不允许连字符 -**）。模块名/包名（build-profile modules[].name、oh-package name、根 oh-package 依赖 key、module.json5 name）统一用下划线，如 `manxia_native`；目录名可用连字符（srcPath/file: 路径不受限）。
```
{
  "module": {
    "name": "manxia_native",
    "type": "har",
    "deviceTypes": ["phone", "tablet", "2in1"]
  }
}
```

### 3.4 根配置改动 diff 摘要（实操时逐项执行）
- 根 build-profile.json5：`modules` 追加 `{ name: "manxia_native", srcPath: "./manxia-native", targets: [{name:"default", applyToProducts:["default"]}] }`
- 根 oh-package.json5：`dependencies` 增加 `manxia-native: file:./manxia-native`
- entry/build-profile.json5：删除 `externalNativeOptions`（native 整体移走）
- entry/oh-package.json5：删除已迁走 so 的 `lib*.so` 条目（方案 A）
- entry/src/main/cpp/CMakeLists.txt：按迁移进度逐条删除对应 `add_subdirectory`；最终删空后移除整目录（历史产物 `webdav(1)` 一并清理）

---

## 4. 需要用户决策的开放项（进入 Stage 1 实操前）

| 编号 | 决策项 | 说明 | 建议 |
|---|---|---|---|
| D1 | 本地第三方/预编译产物的归属 | `webdav` 的 curl/mbedtls/libssh2 源码（gitignore）与 `install-curl-https-arm64`（已入库）、`transfer_rtc` 的 `install-libdatachannel-arm64`/mbedtls 预编译（gitignore）在迁移后如何被新模块引用 | 首版：产物目录随源码一起物理移动到 manxia-native 对应相对路径（CMake 相对路径引用不变），git 入库策略另行评估 |
| D2 | libsmb2（third_party）是否留在 entry | SMB 由 webdav 模块使用，但与 webdav 并非同一 so | 随 manxia-native 一并迁移（依赖 webdav 的 CMake include 相对路径），保持整体性 |
| D3 | 是否先做"基线干净化" | 当前分支有未提交改动 + 未跟踪文件 | 建议用户先 commit/stash 无关改动，再开 Stage 1（避免混搅回滚） |
| D4 | webdav(1) 残留目录 | Windows 副本残留 | 进入清理子任务，列清单经确认后删除 |

---

## 5. 回滚红线（Stage 1）
- 已跟踪文件：`git checkout -- entry/src/main/cpp <-> git mv 反向`（迁移用 `git mv`，保留历史）。
- 配置改动：先在根/模块每个配置文件上 `copy x x.bak_harmod`，回滚=还原 .bak_harmod。
- 本地未跟踪依赖目录（curl 源码、install-* 预编译）：移动而非删除，回滚=移回。
- 每次 so 迁移都是一次可独立回滚的小步，**禁止多 so 一次性合并提交**。
