# AGENTS

本文件是本仓库统一的代理工作规范，已整合以下规则来源：

- `.trae/rules/project_rules.md`
- `.windsurf/rules/projectrules.md`
- `.kiro/steering/projectrules.md`
- `.cursor/rules/projectrules.mdc`

目标是让 Codex、OpenCode、Claude Code 等支持 `AGENTS.md` 的代理都能读取同一份规则。

## 1. 适用范围与优先级

- 用户明确指令优先于本文件。
- 本文件优先于分散在 `.trae`、`.windsurf`、`.kiro`、`.cursor` 中的同类规则文件。
- 每次进行文件读取、写入、修改时，必须显式使用 UTF-8 编码；禁止依赖系统默认编码。支持编码选项的写回操作统一使用 UTF-8（建议无 BOM）。
- 在 Windows 环境下，只要目标 shell 支持，默认优先使用 PowerShell 7（`pwsh`）执行命令，以规避 Windows PowerShell 5.1（`powershell.exe`）及传统 cmd 的默认编码（如 GBK）导致的乱码、日志输出与管道处理等 UTF-8 问题；当 `pwsh` 不可用时再回退到其他可用 shell，且回退后仍需按本条规范显式处理 UTF-8 编码。
- 涉及 HarmonyOS Next 导入、引用、编译、运行、API 能力、废弃接口迁移时，必须优先参考最新官方文档与官方最佳实践。
- 需要解决报错或解释报错时，必须先查官方文档和相关声明定义，再结合源文件分析原因，最后给出修复方案。
- 修复方案必须保持原功能等价，避免引入新的问题。
- 对侵入性较强或高风险的修改，优先先做同目录 `*.bak` 备份再执行改动。
- 修复问题时默认不自动执行编译、打包、hvigor 构建或预览器运行；只有在用户明确要求，或当前任务本身就是编译/构建/运行问题排查时，才进行相关操作。
- 但对 WebView、在线阅读、图源、页面交互、浏览器脚本、DOM 结构、跳转流程、下载链路、接口响应、前端行为验证等任务，若 Codex 当前环境可直接访问目标页面或目标服务，则应优先由 Codex 直接完成测试、验证、脚本执行、回归检查与结果确认，不再默认要求用户手动重复这些步骤。
- 只有在登录态、验证码、设备绑定、系统权限、真机能力、网络限制或 Codex 工具能力边界导致无法自动化完成时，才回退为用户手动执行控制台脚本、手动点击操作、手动真机复测或补充外部证据。
- 修复完成后，必须再次检查是否符合 ArkTS 规则与本项目规范。
- 每次修复后都应回顾本次问题是否值得沉淀为长期规则；只有真正可复用的规则才能补充到本文件，不要为一次性问题临时加规则。
- 忽略本仓库中的 `--allowArbitraryExtensions` 相关问题，除非用户明确要求处理。

## 2. 项目定位

- 这是一个 HarmonyOS Next 项目，主要使用 ArkTS 开发。
- 当前仓库配置已升级到更高 API，现以仓库中的实际配置为准；例如根目录 `build-profile.json5` 当前目标版本已是 `targetSdkVersion: 6.1.0(23)` / `compatibleSdkVersion: 6.1.0(23)`。
- 历史规则中提到 API 18，这些内容只能作为背景参考，不能再作为当前开发约束；涉及 API 21、API 23 及之后的能力时，必须以最新官方文档和当前仓库实现为准。
- 历史规则中提到 ECS 架构；实际仓库中也存在 managers、services、pages、EventBus、WebView 引擎、WindowManager、主题系统等实现方式。修改代码时应优先保持目标目录现有模式，不要强行按单一架构重写。
- 项目当前定位为纯应用软件，不再包含游戏相关的 C++ 底层逻辑。
- 优先使用官方最新 API，尽量不引入新的第三方插件。

### 2.0 多模块依赖与 OhmUrl 解析

- 在任意 HAR 模块内以 `manxia_xxx/src/main/ets/...` 形式跨模块导入时，必须先在该模块自身的 `oh-package.json5` 中显式声明对应依赖（`file:../xxx`）；HAR 编译只按自身依赖闭包解析，不会继承根 `oh-package.json5` 或 entry 的依赖提升。
- 出现 `Failed to resolve OhmUrl ... "undefined" module` 报错时，优先排查“导入方模块是否声明了被导入模块的依赖”，而不是怀疑文件名或大小写；同时确认 `模块名`（下划线）与 `目录名`（连字符，如 `manxia-network`）的对应关系。
- 新增模块依赖后需重新执行 `ohpm install` 刷新对应模块的 `oh_modules` 软链；若 DevEco Studio 占用锁文件导致 EPERM，由用户在 IDE 内同步即可，代理不必强行处理。
- 声明依赖前先检查是否形成循环依赖（例如基础模块反向引用上层 UI 模块）。
- HAR 转 HSP 的完整配套改动：① src/main/module.json5 的 `type` 改 `shared` 并加 `deliveryWithInstall: true`；② **模块根目录 hvigorfile.ts 的 `harTasks` 必须同步改为 `hspTasks`**（否则报 00303278 Configuration Error "Unable to get plugin in hvigorfile.ts"）；③ 转换后用全模块 grep 复核无任何 HAR 依赖该模块（HAR 不依赖 HSP）。回退 = type 改回 har + hvigorfile.ts 改回 harTasks。
- **⚠️ 本项目已于 2026-06-09 放弃 HSP 迁移**（运行时 record 解析不匹配 + 收益成本不匹配），全部模块维持 HAR，详见 docs/HSP_MIGRATION_PLAN.md 头部决策记录。未经用户明确要求，不要重新发起 HSP 相关改动；P0 的依赖显式化治理（各模块 oh-package 显式声明）仍有效并必须遵守。
- HAR→HSP 后**编译通过但启动瞬间闪退、报 `cannot find record '&pkg/path&version'`（ReferenceError，无传统 crash 日志）**：这是模块类型/版本变更后增量构建缓存残留旧版 record 请求所致。排查顺序：① hilog 抓 JS_ERROR/AppKit 行确认 record 名称；② 字节级比对 entry abc 请求格式与 HSP abc 提供格式（abc 为 PANDA 二进制，可用 Format-Hex/字节扫描，注意受限模式可能使 ReadAllBytes 返回全零假数据，须用 Format-Hex 或 Get-Content -AsByteStream 复核）；③ 全量清理（停 daemon + 删全部模块 build 目录 + .hvigor + IDE Invalidate Caches）后重建重装；④ 仍不匹配则改用 HSP index.ets 桶导出 + 包名导入（HSP 官方推荐消费方式，深度路径对 HSP 不保证运行时可解析）。

### 2.1 本机 SDK 路径

- 当前机器已确认的 HarmonyOS SDK 主目录为 `F:\HarmonyOS\SDK`。
- 当前机器已确认安装的 HarmonyOS SDK 版本目录包括：
  - `F:\HarmonyOS\SDK\23`
  - `F:\HarmonyOS\SDK\20`
  - `F:\HarmonyOS\SDK\18`
- 当前机器已确认的 DevEco Studio 安装目录为 `F:\DevEco Studio`。
- DevEco Studio 安装目录下的 SDK 根目录为 `F:\DevEco Studio\sdk`。
- DevEco Studio 安装目录下默认 OpenHarmony SDK 目录为 `F:\DevEco Studio\sdk\default\openharmony`。
- DevEco Studio 安装目录下默认 HMS SDK 目录为 `F:\DevEco Studio\sdk\default\hms`。
- 涉及 SDK 路径、toolchains、previewer、hvigor、编译环境或 IDE 绑定目录排查时，优先先核对以上路径，不要凭空假设其他 SDK 安装位置。

### 2.2 本机已验证的常用构建命令

- 本机命令行可用的 Hvigor 入口已实测确认为：`F:\DevEco Studio\tools\hvigor\bin\hvigorw.bat`。
- 在 PowerShell 中执行 HarmonyOS 构建命令前，优先先显式设置：
  - `$env:DEVECO_SDK_HOME='F:\DevEco Studio\sdk'`
- 执行任何 `hvigorw.bat` 命令前，必须先确认当前工作目录就是仓库根目录 `F:\DevEcoStudioProject\manxia`；不要在 `C:\Users\...` 等无关目录直接执行，否则 Hvigor 会按当前目录解析 `hvigor\hvigor-config.json5`，并触发类似 `00304004 Not Found` / `Hvigor config file <cwd>\hvigor\hvigor-config.json5 does not exist` 的误导性报错。
- 不要先后反复尝试 `hvigor`、`hvigorw`、`ohpm`、猜测 SDK 路径等无根据写法；除非上述已验证入口失效，否则默认直接使用该入口和该环境变量，避免无效试错浪费 tokens。
- 已在本仓库根目录 `F:\DevEcoStudioProject\manxia` 实测通过的常用命令包括：
  - `& 'F:\DevEco Studio\tools\hvigor\bin\hvigorw.bat' -v`
  - `& 'F:\DevEco Studio\tools\hvigor\bin\hvigorw.bat' tasks --no-daemon`
  - `& 'F:\DevEco Studio\tools\hvigor\bin\hvigorw.bat' taskTree --no-daemon`
  - `& 'F:\DevEco Studio\tools\hvigor\bin\hvigorw.bat' buildInfo --no-daemon`
  - `& 'F:\DevEco Studio\tools\hvigor\bin\hvigorw.bat' clean --no-daemon`
- 已验证可用的 daemon 管理命令包括：
  - `& 'F:\DevEco Studio\tools\hvigor\bin\hvigorw.bat' --status-daemon`
  - `& 'F:\DevEco Studio\tools\hvigor\bin\hvigorw.bat' --stop-daemon`
  - `& 'F:\DevEco Studio\tools\hvigor\bin\hvigorw.bat' --stop-daemon-all`
- 已验证语法正确、能够进入实际构建流程的命令包括：
  - `& 'F:\DevEco Studio\tools\hvigor\bin\hvigorw.bat' assembleApp -p product=default -p buildMode=debug --no-daemon --stacktrace`
  - `& 'F:\DevEco Studio\tools\hvigor\bin\hvigorw.bat' assembleHap --no-daemon --stacktrace`
- 本机已验证的 HDC 入口为：`F:\DevEco Studio\sdk\default\openharmony\toolchains\hdc.exe`。
- 在已连接设备上覆盖安装并启动 APP 时，优先使用以下命令；执行前仍需确认当前工作目录是仓库根目录，并优先使用最新构建出的 signed HAP：
  - 查看已连接设备：`& 'F:\DevEco Studio\sdk\default\openharmony\toolchains\hdc.exe' list targets`
  - 覆盖安装最新 HAP：`& 'F:\DevEco Studio\sdk\default\openharmony\toolchains\hdc.exe' -t <deviceId> install -r 'F:\DevEcoStudioProject\manxia\entry\build\default\outputs\default\entry-default-signed.hap'`
  - **（已废弃 2026-06-09：HSP 迁移已放弃，本节仅作历史记录保留）HSP 依赖安装**：HDC 单包安装 HAP 会报 9568305 "依赖的模块不存在"。命令行安装必须 HAP+HSP 一起装（目录方式，与 IDE bm install -p 一致）：
    ```powershell
    $hdc = 'F:\DevEco Studio\sdk\default\openharmony\toolchains\hdc.exe'
    & $hdc -t <deviceId> shell mkdir data/local/tmp/manxia_install
    & $hdc -t <deviceId> file send 'F:\DevEcoStudioProject\manxia\entry\build\default\outputs\default\entry-default-signed.hap' data/local/tmp/manxia_install
    & $hdc -t <deviceId> file send 'F:\DevEcoStudioProject\manxia\manxia-reader-ui\build\default\outputs\default\manxia_reader_ui-default-signed.hsp' data/local/tmp/manxia_install
    & $hdc -t <deviceId> shell bm install -p data/local/tmp/manxia_install
    & $hdc -t <deviceId> shell rm -rf data/local/tmp/manxia_install
    ```
    每转换一个 HSP 就多 send 一个对应 `-default-signed.hsp`；HSP 产物路径为 `<模块目录>/build/default/outputs/default/<模块名>-default-signed.hsp`。IDE 运行/调试则推荐在 Run > Edit Configurations 勾选 Auto Dependencies（或 Deploy Multi Hap Packages）自动带上 HSP。
  - 启动主入口：`& 'F:\DevEco Studio\sdk\default\openharmony\toolchains\hdc.exe' -t <deviceId> shell aa start -a EntryAbility -b com.dlzz.manxia -m entry`
  - 验证进程：`& 'F:\DevEco Studio\sdk\default\openharmony\toolchains\hdc.exe' -t <deviceId> shell pidof com.dlzz.manxia`
  - 当前已实测连接设备 ID 示例：`2UCUT24724009680`。该 ID 只能作为当前机器当前设备的便利记录，实际执行前必须以 `list targets` 输出为准。
- 当前仓库在本机执行完整构建时，已观测到一个明确的本地原生缓存问题：`entry\.cxx\default\default\debug\arm64-v8a` 下旧的 CMake 生成器为 `Visual Studio 17 2022`，而当前 HarmonyOS 构建链使用 `Ninja`，会导致 `BuildNativeWithCmake` 失败。
- 因此，如果再次遇到 `generator : Ninja does not match the generator used previously: Visual Studio 17 2022`，应优先判断为本地 `.cxx` / `CMakeCache.txt` 缓存冲突，而不是 Hvigor 命令写错。
- 遇到上述缓存冲突时，先在仓库根目录停止 daemon、记录报错、定位到具体 `.cxx` 目录；只有在当前任务本身就是构建排障，且用户允许处理构建缓存时，才继续清理对应 CMake 缓存。
- 对当前仓库，优先清理的目标是报错中明确指向的二进制目录 `entry\.cxx\default\default\debug\arm64-v8a`，不要无差别清空整个项目、整个 `entry` 或其他无关缓存目录。
- 如果清理 `entry\.cxx` 或其子目录时出现 `Access is denied`、`UnauthorizedAccessException`、无法改名、无法删除等错误，应优先判断为该目录的 ACL / 所有权 / 继承链异常，而不是继续误判为 Hvigor 命令问题；这类场景下必须明确说明需要管理员 PowerShell 或手动修复目录权限后再清缓存。

## 3. ArkTS 硬性语言与类型规则

### 3.1 类型安全

- 禁止使用 `any`、`unknown`，包括但不限于：
  - 函数参数类型
  - 函数返回值类型
  - 变量声明类型
  - 接口属性类型
  - 泛型约束
  - 双重断言中间态，如 `as unknown as TargetType`
- 必须为数据结构提供明确的类、接口或类型别名。
- 重点关注 `null`、未类型化对象字面量、`any`/`unknown` 的使用，确保整体类型安全。
- 所有对象字面量都必须对应明确声明的类或接口，不要依赖未类型化对象字面量。
- 配置文件和资源文件必须定义明确类型接口，并通过类型断言确保类型安全。
- JSON 配置应提供完整的 ArkTS/TypeScript 接口定义。
- 使用 `error` 时必须保证其类型不是 `any` 或 `unknown`，必要时进行显式转换或非空处理。

### 3.2 类型断言与泛型

- 类型转换必须使用 `as` 语法；不要使用其他类型断言形式。
- 类型声明时不要使用 `is`，统一使用 `as`。
- ArkTS 调用泛型函数时，必须显式标注泛型参数，不要依赖编译器自动推断。
- `typeof` 只能用于表达式上下文，不能用于类型上下文。

### 3.3 禁止的语言模式

- 禁止将构造函数作为函数参数或类型签名直接使用；应优先使用类继承体系或抽象工厂模式。
- 禁止使用结构类型系统，应改为名义类型系统。
- 禁止动态解构变量声明；应使用显式属性访问。
- 禁止函数参数解构声明；应改用显式对象参数和属性提取。
- 禁止使用 `in` 操作符和 `hasOwnProperty`；应使用 `Object.keys(...).includes(...)` 并结合显式类型断言。
- 禁止通过 `Function.apply` 和 `Function.call` 动态修改 `this`。
- 禁止在独立函数中使用 `this`。
- 禁止将类本身当作普通对象操作。
- 禁止使用 `globalThis`；应改用单例模式或受控管理器。
- 禁止使用 `ESObject`。
- 禁止使用索引签名定义对象类型。
- 禁止依赖字符串索引签名进行动态访问。
- 禁止使用对象扩展运算符 `...` 合并普通对象；对象属性应显式赋值。
- 禁止使用 definite assignment assertion。

### 3.4 属性访问与数组规则

- 应进行显式空值检查，避免对可能为 `null` 的对象进行属性访问或调用。
- 避免索引访问模式，如 `object['key']`、`object[fieldName]`；优先使用点语法和显式 helper。
- 如果必须处理动态字段，优先先枚举 `Object.keys()`，再通过显式类型断言访问。
- `Object.entries()` 的返回值类型必须显式声明为 `[string, T][]` 等明确形式。
- 避免使用非推断类型的数组字面量。
- 对于 `Map` 初始化，优先先声明泛型类型，再通过 `set()` 逐项添加，而不是直接在构造函数里传复杂数组字面量。
- 扩展运算符只能用于数组或从数组派生的类，不能用于普通对象。

### 3.5 异常与构造一致性

- `throw` 不能抛出任意类型，优先抛出 `Error` 或其他明确类型错误对象。
- 类定义中的构造参数必须与所有实例化调用在类型、数量、顺序上完全一致。
- 内部类访问外部类属性时，必须通过构造参数传递或显式属性声明完成，不得访问不存在的属性。

## 4. 日志与问题分析流程

- 日志系统统一使用 `entry/src/main/ets/Utils/Logger.ets`。
- 优先使用以下日志方法：
  - `logger.debug`
  - `logger.info`
  - `logger.warn`
  - `logger.error`
  - `logger.lifecycle`
  - `logger.startup`
  - `logger.stateChange`
  - `logger.performance`
- 日志分析时，先定位日志提到的代码，再结合源文件、官方文档和最佳实践解释原因，然后再给出方案。
- 处理导入模块问题时，先检查源文件是否正确导出以及导出名称是否正确；如果是 HarmonyOS 模块，再去官方文档确认模块名与导出名。

### 4.1 大文件与上下文保护规则

- 对非日志、非关键文档、非用户明确要求全文查看的内容，默认禁止一次性整文件输出。
- 查看代码、配置、普通文档时，默认先定位、再局部读取：
  - 先用 `rg` / `Select-String` 搜关键词、函数名、类名、常量名、标题。
  - 再用 `Get-Content -Encoding UTF8 | Select-Object -Skip N -First M` 读取命中位置附近上下文。
- 单次局部读取默认控制在必要范围内，通常以 `20` 到 `160` 行为宜；除非确有必要，不要一次读取数百上千行。
- 大于约 `500` 行的文件，默认不应整文件展开；必须先搜索命中点，再按片段分段读取。
- 如果只是为了确认定义、调用、导出、常量值、标题或配置项，不要顺手把整个文件内容输出出来。
- 并行查看多个文件时，优先同时读取多个“小窗口片段”，不要并行展开多个大文件全文。
- 当 `rg` 不可用、缺失或被系统限制时，再退回 `Get-ChildItem ... | Select-String ...`；不要因为工具切换而放宽上下文控制。

### 4.2 日志与长文档的精准提取规则

- 对日志、构建输出、长文档、说明文、抓包文本等大量文本，必须先做“目标收缩”，再做“上下文提取”。
- 日志分析优先按以下维度收缩范围：
  - 时间戳
  - TAG / 模块名
  - 错误码
  - 文件名 / 页面名 / 类名
  - 关键词，如 `ERROR`、`WARN`、`Exception`、`failed`、`compile`
- 优先使用精准提取方式，而不是全文阅读：
  - `Select-String -Pattern ... -Context 2,4`
  - 多关键词组合筛选
  - 先筛时间段，再读该时间段附近的连续片段
- 对重复日志，不要逐条通读全部重复项；应优先提取：
  - 首次出现位置
  - 代表性样本
  - 最后一次出现位置
  - 重复次数或影响范围
- 分析长文档时，优先先定位目录、标题、章节名、关键术语，再只读取命中的章节片段；不要默认从头到尾通读整份文档。
- 输出分析结论时，优先引用最关键的少量原文证据，再用自己的话概括；避免把大量日志或文档原文直接搬进回复，浪费 tokens。
- 如果问题已经可以由精准命中片段解释清楚，就不要继续扩大阅读范围；只有证据不足时再逐步扩展上下文。

## 5. 资源、配置与文件规则

- 所有字体颜色必须优先使用系统资源，不要硬编码颜色值；遵循 `entry/src/main/ets/Data/ResourceMap.ets` 中的资源定义。
- JSON 配置文件应放在 `entry/src/main/resources/rawfile/` 下。
- `rawfile` 目录下的资源通过 `$rawfile('relative/path')` 使用，不需要额外在 `ResourceMap.ets` 中单独映射。
- `rawfile` 适合放配置文件、数据文件、音频、视频等静态资源。
- 编辑 `entry/src/main/resources/rawfile/resources_metadata.json` 时，必须使用 HarmonyOS 资源映射路径，而不是直接写文件路径：
  - 图片资源：`app.media.xxx`
  - 音频资源：`app.audio.xxx`
  - 字符串资源：`app.string.xxx`
  - 字体资源：`app.font.xxx`
  - 颜色资源：`app.color.xxx`
  - rawfile 资源：`app.rawfile.xxx`
- `ResourceMap.ets` 的职责是维护映射路径字符串到 `Resource` 对象的映射关系，并通过 `$r()` 在编译时完成资源绑定。
- 系统资源名称必须与 `ResourceMap.ets` 中的定义保持一致，避免出现 `Unknown resource name` 编译错误。
- 项目存在同名文件时必须确认正确路径，例如：
  - `entry/src/main/ets/Framework/Debug/ConsolePanel.ets`
  - `entry/src/main/ets/Framework/Components/ConsolePanel.ets`
- 修改同名文件前，必须先确认其职责范围，避免改错文件。

## 6. 页面、导航与沉浸式布局规范

### 6.1 页面入口与测试页

- 所有独立入口页面文件都必须在 `entry/src/main/resources/base/profile/main_pages.json` 中管理。
- 测试工具和调试页面应统一通过 `entry/src/main/ets/pages/TestManagementPage.ets` 进行管理和展示。
- 新增测试页面时，应按当前项目真实路由接入方式完成注册，并确保能从测试管理页进入。
- 测试页面必须有清晰的返回路径，通常返回 `TestManagementPage` 或对应上级页面。
- 测试页面需要适当记录日志，统一走 Logger 系统。

### 6.2 导航规则

- 历史规则要求禁止使用 `router` 模块并统一使用导航栈方案；当前仓库中实际主要使用 `NavPathStack`。
- 新增页面跳转时，优先沿用当前仓库现有的 `NavPathStack` / `AppStorage.get<NavPathStack>('GlobalNavStack')` 模式。
- 不要主动重新引入已弱化或已移除的旧导航假设，例如必须依赖 `PageRoutes.ets`、`SystemIntegrationManager`、`GameStateManager` 等，除非用户明确要求回迁或目标文件当前仍依赖这套方案。
- 如果目标文件已经使用 `this.getUIContext().getRouter()`，则在该文件内保持一致，不要混用多套导航方式。

### 6.3 沉浸式显示

- 所有页面组件必须尽量遵循当前项目的沉浸式显示方案，而不是停留在旧版简单全屏规则。
- 推荐采用 `Stack` 双层布局：
  - 背景层使用 `expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.TOP, SafeAreaEdge.BOTTOM])`
  - 内容层通过 `padding` 或标题栏管理器预留安全区域
- 页面组件通常应声明：
  - `@StorageProp('statusBarHeight') statusBarHeight: number = 0`
  - `@StorageProp('navigationBarHeight') navigationBarHeight: number = 0`
- 在设置页、搜索页、带自定义标题栏的页面中，优先复用 `SettingsPageTitleBarManager.ets`、`SettingsImmersiveTitleBar.ets` 等现有方案，不要手写一套新的沉浸式标题栏。
- 当前仓库已广泛使用 `ignoreLayoutSafeArea([LayoutSafeAreaType.SYSTEM], [...])`、自定义标题栏桥接层、顶部玻璃材质和安全区协调逻辑；修改此类页面时应延续目标文件现有实现。
- 页面窗口显示策略已不只是“是否沉浸式”，还涉及 `PageWindowCoordinator`、`PageWindowPolicy`、`WindowManager`、`DisplayMode` 等统一窗口模式管理；涉及整页体验时应优先复用这些机制。
- 背景图片、背景色、浮层和底部面板等装饰元素也应正确扩展到系统栏区域，保证真正的全屏沉浸式效果。
- `List` 组件必须显式设置 `width` 和 `height`，避免布局警告。

## 7. UI 组件、动画与构建规则

- 页面入场动画、属性动画和统一动画状态管理，优先复用目标模块已有实现。
- 项目中存在 `entry/src/main/ets/Framework/Animation/AnimatedComponent.ets` 作为动画基类；在已经采用该体系的模块中应沿用这一模式。
- 历史规则要求按钮优先使用 `AnimatedButton`；但当前仓库中已有部分页面回退到原生 ArkUI `Button`。因此处理按钮时应以目标文件现状为准，不要强行回迁或强行替换。
- 所有动画相关状态变量必须使用 `@State` 装饰器管理，并在动画结束后及时清理状态，避免内存泄漏。
- 复杂页面应将 UI 构建逻辑拆分成多个 `@Builder` 方法，提高可读性和维护性。
- `@Builder` 方法参数必须与调用处在类型、数量、顺序上完全匹配。
- 枚举类型必须使用完整枚举成员，不要用字符串字面量代替。
- 长列表渲染优先使用 `LazyForEach`。
- 自定义组件必须遵循单一职责原则。
- 组件外部输入优先使用 `@Prop`，内部状态优先使用 `@State`。
- 组件接口需要清晰区分必需参数和可选参数。
- API 升级后，动画与视觉设计已不再局限于旧的基础属性动画；修改相关页面时应优先复用现有的玻璃拟态、背景模糊、分层阴影、渐变、高光和过渡方案。
- 在主题和视觉相关页面中，优先复用 `ThemeManager.ets`、`ThemeAware.ets`、`AppColors.ets` 等现有主题系统，而不是直接散落硬编码颜色和样式。
- 对于设置页及新式页面标题栏，优先延续现有 `HdsNavigation...`、沉浸式玻璃标题栏和主题色联动实现。
- 如果目标文件仍使用旧式全局 `animateTo(...)` 且当前模块运行稳定，应优先遵循目标文件既有模式；新增实现或大范围重构时，再优先迁移到 `UIContext.animateTo(...)` 与当前模块已采用的方案保持一致。

## 8. `@Watch` 装饰器规范

- `@Watch` 只用于监听由状态装饰器管理的变量，如 `@State`、`@Prop`、`@Link`。
- `@Watch` 参数必须是字符串形式的方法名，例如 `@Watch('onCountChange')`。
- 被 `@Watch` 指向的回调方法必须是组件成员函数。
- 被 `@Watch` 指向的方法不能是 `private`。
- 推荐的回调函数签名是：`(changedPropertyName?: string) => void`。
- `@Watch` 在首次初始化时不会触发，只会在后续状态变化后同步触发。
- 不要在 `@Watch` 回调中直接或间接修改同一个被监听状态，避免死循环。
- `@Watch` 回调应尽量保持快速、同步、轻量。
- 除非所在模块已有成熟模式，否则不建议在 `@Watch` 中使用 `async/await`。

## 9. HarmonyOS API 迁移与废弃约束

- `decode()` 已废弃，统一使用 `decodeToString()`。
- 全局 `animateTo()` 已废弃，应使用 `UIContext.animateTo(...)`。
- 在 `@Component` 中，应在 `aboutToAppear()` 中通过 `this.getUIContext()` 获取 `UIContext`，并做好空值检查。
- 触发动画时，优先在回调中修改 `@State` 变量，而不是直接操作组件实例。
- 如需等组件完成渲染后再执行动画，可使用 `setTimeout(..., 0)` 作为过渡。
- `getContext()` 已废弃，应使用 `this.getUIContext()?.getHostContext()`，并在需要时显式断言为 `common.UIAbilityContext`。
- 旧式 `router.replaceUrl()` 模式应迁移为 `this.getUIContext().getRouter().replaceUrl()` 或目标文件现有导航实现。
- API 升级后，窗口显示与系统栏控制也应优先复用当前项目的 `WindowManager`、`PageWindowCoordinator`、`PageWindowPolicy` 等能力，而不是沿用早期的单页局部写法。

## 10. 单例、全局状态与预览器环境

- 不使用 `globalThis` 管理全局状态，优先使用单例模式。
- 单例类应提供：
  - 私有构造函数
  - 静态 `getInstance()` 方法
  - 必要的生命周期管理方法，如 `reset...()`、`destroyInstance()`
- 访问预览器环境时，应优先使用 `entry/src/main/ets/Framework/Managers/PreviewerEnvironmentManager.ets`。
- 历史规则中提到通过间接方式访问全局对象；如无充分理由，不要自行扩大全局对象访问面。

## 11. EventBus 与事件系统规范

- 页面导航或跨模块通信相关事件，优先复用 `entry/src/main/ets/Framework/EventBus.ets`。
- 事件载荷类型应实现 `IEventPayload`。
- 页面组件必须在合适的生命周期中订阅和取消订阅事件，避免泄漏和重复触发。
- 事件处理应保证类型安全，不要传递未类型化载荷。
- 历史规则中已有页面导航相关事件约定时，应优先沿用目标模块现有事件命名与负载结构。

## 12. WebView 图源引擎架构规范

### 12.1 设计原则

- 图源隔离
- 按需激活
- 最小影响

### 12.2 核心架构

- `MangaSourceEngine`：图源引擎主控制器，负责工作流执行。
- `MangaSourceActionEngine`：操作执行引擎，负责 `navigate`、`wait`、`extract`、`script` 等操作。
- 图源配置解析器负责解析 JSON 配置文件。
- 图片拦截器负责图片解扰和处理，通常以单例形式存在。

### 12.3 图源配置文件规范

- 当前最新图源仓库以 `manxia-extensions-source/` 为准，不再把根目录 `sources/*.json` 视为主图源仓库。
- 图源仓库索引文件为 `manxia-extensions-source/index.main.json`。
- 每个图源使用独立文件夹，文件夹名通常与 `pkg` 字段一致，例如 `manxia-extensions-source/com.manxia.extension.zh.copymangawebview/`。
- 每个图源目录至少包含 `source.json`，并可按需包含 `icon.webp`、`icon.png`、`icon.jpg` 等图标资源。
- `source.json` 结构应清晰分层，通常包括：
  - `metadata`
  - `capabilities`
  - `network`
  - `workflows`
- 每个图源必须独立配置，互不干扰。
- 根目录 `sources/` 下的 JSON 如仍存在，通常只应视为历史配置、兼容样例、测试资源或迁移遗留；除非用户明确要求，否则不要把它们当作当前主图源来源。

### 12.4 图片处理流程

- 图源加载时，应先通过仓库索引定位对应 `pkg/source.json`，再注册该图源的图片处理配置。
- 在线仓库结构与本地同步后的 `filesDir/extensions-source/` 结构应保持一致，避免仓库格式与运行时路径不匹配。
- 图片拦截器根据 `sourceId` 和 URL 模式判断是否需要拦截处理。
- 只有匹配 `urlPattern` 的图片才允许进入特殊处理逻辑。
- 处理完成后应缓存结果，避免重复处理。

### 12.5 特殊图源适配原则

- 特殊逻辑必须隔离在该图源的 `source.json` 配置和专用解扰器中。
- 特殊处理必须通过明确的开关和 URL 模式进行条件激活。
- 不允许为了兼容单个图源而污染核心引擎。
- 失败时必须具备降级策略，优先返回原始数据，确保基本功能可用。

### 12.6 禁漫天堂类图源的特殊说明

- 图片解扰应由专用 descrambler 实现。
- Base64 解码可在 workflow 的 `script` 操作中完成。
- 动态域名通过 settings 配置与自动更新机制处理。
- 网络速率限制应通过 `network.rateLimit` 控制。
- URL 模式必须足够精确，避免误伤其他资源。

### 12.7 新图源接入流程

- 在 `manxia-extensions-source/` 目录下创建新的图源文件夹，目录名与 `pkg` 保持一致。
- 在该目录中创建 `source.json`，并按需添加图标文件。
- 在 `manxia-extensions-source/index.main.json` 中注册新的图源条目。
- 定义 `metadata`、`capabilities`、`workflows` 等配置。
- 如需特殊图片处理，实现独立 descrambler 类。
- 在图片解扰初始化流程中注册新的算法。
- 在配置中明确指定 `imageDescrambler`、`algorithm`、`urlPattern`。

### 12.8 调试、性能与错误处理

- 每个图源操作都应有详细日志。
- 使用清晰的 TAG 区分不同模块，如引擎、拦截器、配置解析器等。
- 记录关键指标：耗时、成功/失败状态、数据量等。
- 图片处理结果应使用缓存，并控制缓存容量与淘汰策略。
- 所有关键流程都应使用 `try-catch` 保护。
- 特殊处理失败时优先回退原始数据，不中断用户体验。

### 12.9 图源相关禁止事项

- 禁止修改核心引擎代码去硬适配某一个图源。
- 禁止在全局范围无条件启用特殊处理逻辑。
- 禁止让一个图源的配置影响其他图源。
- 禁止在没有 `urlPattern` 匹配的情况下处理图片。
- 优先用 workflow 配置解决问题，不要把图源特例硬编码进核心流程。

### 12.10 图源联调协作流程

- 图源联调主目录固定为 `F:\DevEcoStudioProject\manxia\manxia-extensions-source`；处理问题时优先读取相关 ArkTS 源文件、`manxia-extensions-source/index.main.json` 与目标图源目录下的 `source.json`，不要在未读源码和配置前直接盲改图源 JSON。
- 图源问题的输入依据可以来自用户描述、运行日志、浏览器控制台报错、页面 DOM 变化、网络请求结果、接口响应结构变化、图片链接失效、章节列表异常等。
- 当 Codex 可直接使用内置浏览器、Browser skill 或其他可用自动化能力访问目标站点时，应优先由 Codex 自行完成页面检查、控制台脚本执行、DOM 提取、网络与接口分析、按钮点击、表单提交、多级跳转跟踪、最终链接识别、下载链路验证与回归测试。
- 在修改图源 JSON 前，优先由 Codex 自行获取证据并完成验证；不再默认要求用户手动执行浏览器控制台脚本。只有在自动化能力受限时，才退回为让用户手动执行脚本并回传结果。
- 如果需要提供控制台脚本，无论由 Codex 自行执行还是由用户手动执行，都必须给出完整可运行版本，不要只给零散片段；脚本应尽量包含明确的输出标签、必要的容错、结构化结果整理，并优先使用 `console.log`、`console.table`、`copy(...)` 等方式输出。
- 控制台脚本或自动化流程应围绕当前问题收集足够证据，例如当前 URL、关键 DOM 选择器、章节/分页/图片列表、全局变量、接口返回片段、跳转目标、懒加载属性、加密前后字段、请求参数、响应状态、最终资源地址与实际落地页等，但应避免采集与问题无关的大量噪音数据。
- 在拿到足够证据后，再修改对应图源目录下的 `source.json`、索引信息或该图源专属配置；如修改风险较高，优先先做同目录 `*.bak` 备份。
- 修改完成后，优先由 Codex 自行完成端到端复测，至少覆盖与本次修复直接相关的关键链路；例如搜索、详情、章节/分页、下载源列表、多级跳转、最终文件链接、下载按钮行为、失败降级与回退逻辑。只有当真机特性或环境限制使 Codex 无法完成验证时，才由用户补充真机复测。
- 如果问题仍未解决，继续按“读取源码和图源 JSON -> 由 Codex 直接执行浏览器调试或补充脚本 -> 收集新证据 -> 修改图源 JSON 或相关实现 -> 由 Codex 复测”的循环推进，直到问题定位清楚；必要时再要求用户补充受限环境下的验证结果。
- 如果证据表明问题不属于图源 JSON 可修复范围，而是核心引擎、站点鉴权、反爬机制、WebView 行为或 HarmonyOS 平台限制，应明确说明判断依据和边界，再决定是否升级为更高层级修复任务。

## 13. Hypium Driver UI 自动化测试规范

### 13.1 工具与环境

- 本项目配套的 DevEco Testing Hypium 工具包位于 `F:\DevEcoStudioProject\devecotesting-hypium-6.1.0.210`。
- 当前验证版本为 `hypium==6.1.0.210`，并配套使用同版本的 `xdevice`、`xdevice-devicetest`、`xdevice-ohos`。
- 当前项目 `.venv` 已安装并验证可导入：`from hypium.action.device.uidriver import UiDriver`、`from hypium.uidriver.by import BY`。
- HDC 入口为 `F:\DevEco Studio\sdk\default\openharmony\toolchains\hdc.exe`。运行 Driver 脚本前，必须把其所在目录加入 `PATH`，或者由脚本的 `--hdc-path` / `HDC_PATH` 配置完成。
- 先执行 `hdc list targets`，再使用明确的设备 SN；当前已验证设备示例为 `2UCUT24724009680`，实际执行时必须以实时输出为准。

### 13.2 Driver 模式与测试工程模式

- 独立 Python 脚本使用 Driver 模式：`driver = UiDriver.connect(device_sn="...")`。
- 通过 `UiDriver.connect` 创建的 Driver 在结束时必须调用 `driver.close()`，释放 UI Agent、端口转发和设备连接资源；推荐使用 `try/finally`。
- Hypium 测试工程的 testcase 中使用 `UiDriver(self.device1)`，不要在 testcase 中再次调用 `UiDriver.connect()`，也不要主动调用 `close()`。
- `python -m hypium --help` 在当前版本打印帮助后可能继续进入 xDevice 流程并因缺少配置报 `NoneType.config`；独立 Driver 脚本直接运行 Python 文件，不以该命令验证 Driver 能力。

### 13.3 推荐 Driver 流程

```python
from hypium.action.device.uidriver import UiDriver
from hypium.uidriver.by import BY

driver = UiDriver.connect(device_sn="2UCUT24724009680")
try:
    driver.unlock()
    driver.start_app("com.dlzz.manxia", "EntryAbility", wait_time=1)
    driver.wait_for_idle(idle_time=0.2, timeout=10)
    driver.check_current_window(bundle_name="com.dlzz.manxia")
    driver.capture_screen("initial.jpeg")
    target = driver.wait_for_component(BY.text("目标文本"), timeout=30)
    if target is not None and target.isEnabled() and target.isClickable():
        target.click()
        driver.wait_for_idle(idle_time=0.2, timeout=10)
        driver.capture_screen("after-click.jpeg")
finally:
    driver.close()
```

- 常用实例方法包括 `unlock`、`start_app`、`stop_app`、`wait_for_idle`、`wait_for_component`、`find_component`、`find_all_components`、`check_current_window`、`get_current_window`、`get_display_size`、`capture_screen`、`go_home`、`go_back`、`input_text` 和 `clear_text`。
- `driver.device_sn` 是属性，不是函数；应写 `driver.device_sn`，不能写 `driver.device_sn()`。
- 当前 6.1.0.210 包内的 `capture_screen` 只接受 JPEG；截图文件使用 `.jpeg` 扩展名，不要使用 `.png`。
- 推荐通过 `BY.id`、`BY.key`、`BY.text`、`BY.type`、`BY.hint` 定位；XPath 只在选择器能力确实需要时使用，并先在实际设备验证。
- 控件对象方法使用包内的 camelCase 名称，例如 `getText()`、`getId()`、`getKey()`、`getType()`、`getBounds()`、`isEnabled()`、`isClickable()`、`click()`。

### 13.4 动态 UI 与低风险操作

- `wait_for_idle()` 只表示当前 UI 在短时间内没有动作，不表示业务数据、卡片同步或异步网络加载已经完成；有明确目标时优先使用 `wait_for_component(selector, timeout=...)`。
- 控件对象是当前 UI 树的代理。页面刷新、懒加载或路由变化后，旧代理可能报 `Widget ... does not exist on current UI`；必须在截图或状态确认后立即重新定位并操作，不要先长时间枚举再复用代理。
- 控件探测应限制类型和数量，避免枚举整个动态 UI 树造成超时和大量陈旧代理告警；探测结果用于证据，不应替代稳定的业务断言。
- 只有在控件明确匹配、`isEnabled()` 和 `isClickable()` 都为真时才执行点击。优先选择筛选、导航、打开详情等可恢复操作，避免删除、分享、切换持久化设置或提交网络表单。
- 完成冒烟测试后默认 `go_home()`，必要时重新 `start_app()` 并再次 `check_current_window()`，最后恢复桌面并 `close()`。
- 当前环境可能输出 `tracker dependency is not ok` 或关闭阶段的 `No more threads can be created in the system` 文本；应结合进程退出码、`result.json` 的 `status`、Hypium task log 和实际截图判断，不要只依据这两条环境告警下结论。
- 独立 Driver 的控制台 JSON 在 `finally` 之前打印；`driver.close()` 是否真正成功必须以落盘后的 `result.json.driver_closed` 和 `close_error` 为准。
- 不可点击的装饰性 `Text` 不是合格的自动化入口。测试不得回退为坐标点击；应使用其可点击且有稳定 `id/key` 的宿主控件，或将缺失的可访问性标识登记为 UI 治理问题。
- 需要触发应用迁移后取得静止数据库快照时，使用 Driver 冒烟脚本的 `--stop-app-first --stop-after-launch`。该模式由 `UiDriver` 完成停启，捕获启动证据后停止应用，并跳过默认的枚举与重启流程；HDC 仅可用于后续只读文件诊断。

### 13.5 本项目已验证的 Driver 冒烟结果

- 设备 `2UCUT24724009680`（型号 `ADA-AL00U`，`phone`，分辨率 `1224x2776`）已成功执行 `unlock -> start_app -> wait_for_idle -> check_current_window`。
- `check_current_window(bundle_name="com.dlzz.manxia")` 已返回成功，当前入口为 `EntryAbility`。
- 通过 `BY.text("漫匣使用手册")` 等待并点击真实可交互文本，截图确认从书库页进入该书详情页。
- 点击后执行 `go_home -> start_app -> check_current_window`，再次启动断言通过，最后恢复桌面并释放 Driver。
- 可复用脚本位于 `.codex/skills/hypium-driver/scripts/driver_smoke.py`；它默认只探测，不盲点业务控件。需要点击时显式传入 `--click-text` 或 `--click-key`，并将证据输出到指定目录。

## 14. 历史规则中的已废弃约束

以下内容来自历史规则，保留为背景说明，但不应再作为新增开发的正向目标：

- 项目已转型为纯应用软件，不再保留游戏相关核心逻辑。
- 原有 C++ 底层集成开发规范已废弃。
- 原有 C++ 与 ArkTS 交互最佳实践已废弃。
- 原有 Native C++ 模块规范化开发规则已废弃。
- 不应再为游戏场景设计新的架构前提。

## 15. 提交修改前的简明检查清单

- 是否先核对了最新 HarmonyOS 官方文档与目标模块源码。
- 是否避免了 `any`、`unknown`、未类型化对象字面量、危险空值访问。
- 是否使用了 `Logger.ets` 和项目既有日志风格。
- 是否正确使用资源映射、`rawfile`、接口定义与类型断言。
- 是否沿用了目标文件已有的导航方式与架构模式。
- 是否确认了同名文件的正确路径。
- 是否在需要时为高风险修改创建了 `*.bak` 备份。
- 是否在新增独立页面或测试页时完成了对应入口接入。
- 是否在图源相关改动中保持图源隔离、按需激活、失败降级。
- 是否在图源联调中先读取源码与 `source.json`，并优先由 Codex 直接完成浏览器调试、脚本执行、链路验证与回归；只有受限时才退回为用户手动脚本。
- 是否对本次修改涉及的关键流程完成了足够的端到端验证，而不是只停留在静态改配置。
- 是否在完成修复后再次检查 ArkTS 兼容性与本文件规则。
