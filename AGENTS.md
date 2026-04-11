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
- 涉及 HarmonyOS Next 导入、引用、编译、运行、API 能力、废弃接口迁移时，必须优先参考最新官方文档与官方最佳实践。
- 需要解决报错或解释报错时，必须先查官方文档和相关声明定义，再结合源文件分析原因，最后给出修复方案。
- 修复方案必须保持原功能等价，避免引入新的问题。
- 对侵入性较强或高风险的修改，优先先做同目录 `*.bak` 备份再执行改动。
- 修复问题时默认不自动执行编译、打包、hvigor 构建或预览器运行；只有在用户明确要求，或当前任务本身就是编译/构建/运行问题排查时，才进行相关操作。
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
- 在修改图源 JSON 前，必须先给出一份可以直接在目标站点浏览器控制台运行的完整脚本，由用户手动执行后回传结果。
- 控制台脚本必须是完整可运行版本，不要只给零散片段；脚本应尽量包含明确的输出标签、必要的容错、结构化结果整理，并优先使用 `console.log`、`console.table`、`copy(...)` 等方式输出，方便用户完整回传。
- 控制台脚本应围绕当前问题收集足够证据，例如当前 URL、关键 DOM 选择器、章节/分页/图片列表、全局变量、接口返回片段、跳转目标、懒加载属性、加密前后字段、请求参数与响应状态等，但应避免采集与问题无关的大量噪音数据。
- 用户运行脚本并反馈结果后，再根据结果修改对应图源目录下的 `source.json`、索引信息或该图源专属配置；如修改风险较高，优先先做同目录 `*.bak` 备份。
- 修改完成后由用户进行真机测试；如果问题仍未解决，继续按“读取源码和图源 JSON -> 输出新的完整浏览器控制台脚本 -> 用户回传结果 -> 修改图源 JSON -> 用户真机复测”的循环推进，直到问题定位清楚。
- 如果证据表明问题不属于图源 JSON 可修复范围，而是核心引擎、站点鉴权、反爬机制、WebView 行为或 HarmonyOS 平台限制，应明确说明判断依据和边界，再决定是否升级为更高层级修复任务。

## 13. 历史规则中的已废弃约束

以下内容来自历史规则，保留为背景说明，但不应再作为新增开发的正向目标：

- 项目已转型为纯应用软件，不再保留游戏相关核心逻辑。
- 原有 C++ 底层集成开发规范已废弃。
- 原有 C++ 与 ArkTS 交互最佳实践已废弃。
- 原有 Native C++ 模块规范化开发规则已废弃。
- 不应再为游戏场景设计新的架构前提。

## 14. 提交修改前的简明检查清单

- 是否先核对了最新 HarmonyOS 官方文档与目标模块源码。
- 是否避免了 `any`、`unknown`、未类型化对象字面量、危险空值访问。
- 是否使用了 `Logger.ets` 和项目既有日志风格。
- 是否正确使用资源映射、`rawfile`、接口定义与类型断言。
- 是否沿用了目标文件已有的导航方式与架构模式。
- 是否确认了同名文件的正确路径。
- 是否在需要时为高风险修改创建了 `*.bak` 备份。
- 是否在新增独立页面或测试页时完成了对应入口接入。
- 是否在图源相关改动中保持图源隔离、按需激活、失败降级。
- 是否在图源联调中先读取源码与 `source.json`，并先给出了可直接执行的完整浏览器控制台脚本。
- 是否在完成修复后再次检查 ArkTS 兼容性与本文件规则。
