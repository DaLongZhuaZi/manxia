1.这是一个HarmonyOSNext项目，使用ArkTS开发,API版本为18，使用ECS架构进行设计
2.项目的导入、引用、编译、运行等操作均需要按照HarmonyOSNext的规范和最新的官方文档进行
3.忽略“未设置“--allowArbitraryExtensions””问题
4.不要使用any、unknown等任意类型，并且在任何地方传递变量时都要进行严格的类型检查和转换
5.优先使用官方已有的最新API，尽量不引入第三方插件
6.重点关注null类型问题、未类型化对象字面量和any类型使用，确保代码的类型安全性
7.严格遵守HarmonyOSNext的内存管理规则，避免内存泄漏和过度使用
8.类型声明时不要使用is关键字，而是使用as
9.使用throw时要格外注意，"throw" statements cannot accept values of arbitrary types (arkts-limited-throw) 
10.typeof 操作符只能用在表达式上下文中，而不能用在类型上下文中
11.日志系统统一由/ets/Utils/Logger.ets实现，方法为logger.debug,logger.info,logger.warn,logger.error,logger.lifecycle,logger.startup,logger.stateChange,logger.performance
12.禁止将构造函数作为函数参数或类型签名直接使用，应该优先使用类继承体系替代动态构造函数参数，对于需要灵活创建对象的场景，采用抽象工厂设计模式，并且保持类型系统的完整性，避免使用any或unknown类型，Constructor function type is not supported (arkts-no-ctor-signatures-funcs) 
13.禁止动态解构赋值的声明方式，应该优先使用显式属性访问替代解构语法，并且对数组操作时采用传统循环+索引方式，以及通过类型断言明确复杂结构的类型定义，还有在JSON解析等场景使用显式字段映射，Destructuring variable declarations are not supported (arkts-no-destruct-decls) 
14.禁止使用未类型化的对象字面量，应该优先使用明确的接口定义替代动态类型描述符，并且对对嵌套对象需要逐层定义接口类型，迁移旧代码时要特别注意补充缺失的类型声明，Object literal must correspond to some explicitly declared class or interface (arkts-no-untyped-obj-literals) 
14.禁止使用any、unknown类型，应该优先使用明确的类型定义替代动态类型描述符，并且要确保类型系统的完整性，Use explicit types instead of "any", "unknown" (arkts-no-any-unknown) 
15.禁止使用结构类型系统，要改为使用名义类型系统，Structural typing is not supported (arkts-no-structural-typing) 
16.禁止使用in操作符和hasOwnProperty方法，而是要使用Object.keys().includes()进行属性检查，并且结合显式类型断言和接口定义，"in" operator is not supported (arkts-no-in) 
17.问题解决标准流程：解决或者解释报错时，一定要先搜索最新的官方文档、最佳实践，然后结合源文件以及声明、定义等分析解释错误，接着给出解决方案，要保证功能实现和原来的功能一致，并且要避免引入新的问题，然后进行涉及文件备份（备份为*.bak），然后再执行修复计划，修复完成后一定要再次检查代码是否符合arkts规则
18.禁止通过Function.apply和Function.call动态修改函数执行上下文（this值），而是使用箭头函数或类方法替代，如果有依赖于call的上下文设置，则要重构为对象方法调用的形式，"Function.apply", "Function.call" are not supported (arkts-no-func-apply-call) 
19.禁止将类本身作为普通对象进行操作（如直接访问类名或静态方法）而是要改用实例替代类引用，或者通过实例方法替代反射，以及使用箭头函数绑定实例上下文，Classes cannot be used as objects (arkts-no-classes-as-obj) 
20.应当进行显式空值检查，避免对可能为null的对象进行属性访问，Cannot invoke an object which is possibly 'null'
21.类型转换必须使用 as 语法，禁止其他形式的类型断言，Only "as T" syntax is supported for type casts (arkts-as-casts)
22.decode方法已经被弃用，应该使用decodeToString方法
23.日志分析标准流程：首先找到日志中提到的相关代码，然后结合日志信息和源文件进行分析解释，并且要结合最新的官方文档和最佳实践，然后根据分析结果给出解决方案
24.使用error时一定要注意其类型不能为any、unknown，要进行类型转换或者添加非空断言，Use explicit types instead of "any", "unknown" (arkts-no-any-unknown) 
25.在 ArkTS 中调用泛型函数时，必须显式标注泛型参数类型，禁止依赖编译器自动推断，Type inference in case of generic function calls is limited (arkts-no-inferred-generic-params) 
26.ESObject属于动态类型描述符，在ArkTS当中不被支持，应该改为使用明确的接口替代动态类型描述符
Usage of 'ESObject' type is restricted (arkts-limited-esobj)
27.不支持使用globalThis，而是应该使用单例模式来管理全局状态，并且注意单例对象的生命周期，确保全局状态的一致性和可维护性，"globalThis" is not supported (arkts-no-globalthis) 
28.类定义中的构造参数必须与实际构造调用的参数在类型、数量、顺序上完全一致，确保整个项目中同一类的所有实例化都使用相同的构造签名，避免类型不匹配导致的运行时错误
29.每次进行修复后都要回顾项目规则，确保本次出现的问题已经被归纳到项目规则中，没有的话需要补充，并且要确保项目规则的变更是必要的，而不是为了修复某个问题而临时增加的规则
30.配置文件和资源文件必须定义明确的类型接口，使用类型断言确保类型安全，避免any和unknown类型的使用
31.内部类访问外部类属性时，必须通过构造函数参数传递或明确的属性声明，不能直接访问不存在的属性
32.JSON配置文件应该放置在rawfile目录下，并提供完整的TypeScript接口定义，确保类型安全
33.使用Object.entries时必须明确声明返回值类型为[string, T][]，避免any类型推断，确保类型安全
34.避免函数参数解构声明，要改用显式对象参数+属性提取，Destructuring parameter declarations are not supported (arkts-no-destruct-params)
35.不要使用索引访问，避免使用索引访问来定义对象类型，Indexed access is not supported for fields (arkts-no-props-by-index)
36.It is possible to spread only arrays or classes derived from arrays into the rest parameter or array literals (arkts-no-spread)
37.禁止使用索引签名，避免使用索引签名来定义对象类型，已存在的索引签名应该使用显式定义属性，Indexed signatures are not supported (arkts-no-indexed-signatures) 
38.遇到某个类型缺少字符串索引签名，导致无法通过动态键访问验证，应该使用显式定义属性，禁止使用索引签名
39.对于预览器环境检测，应使用PreviewerEnvironmentManager单例类替代直接访问globalThis，该单例提供缓存机制和安全的全局对象访问方式
40.单例类必须提供私有构造函数、静态getInstance方法、以及适当的生命周期管理方法（如resetEnvironmentCheck和destroyInstance）
41.访问全局对象时应使用间接方式（如new Function('return this')）而非直接使用globalThis，并包含适当的错误处理机制
42.禁止使用hasOwnProperty方法和动态属性访问，应该使用Object.keys().includes()检查属性存在性，并使用显式类型断言进行属性访问，确保类型安全
43.所有字体颜色必须使用系统资源而非硬编码颜色值，按照ResourceMap.ets文件中的颜色定义进行引用
44.List组件必须显式设置width和height属性以避免布局警告，推荐使用width('100%')和具体的height值或百分比
45.@Builder方法的参数必须与调用时传递的参数完全匹配，包括参数类型、数量和顺序，避免参数不匹配导致的编译错误
46.枚举类型必须使用完整的枚举值引用而非字符串字面量，确保类型安全和IDE支持
47.项目中存在同名文件时必须明确区分其职责和路径：
   - /Framework/Debug/ConsolePanel.ets：核心调试面板逻辑类，负责日志收集、命令执行、设置管理等后端功能
   - /Framework/Components/ConsolePanel.ets：UI组件类，负责界面渲染、用户交互、数据绑定等前端显示
   - 修改时必须确认正确的文件路径，避免混淆导致功能异常
   - 类似的同名文件还可能包括Manager、System等，都需要根据目录结构明确其职责范围
48.沉浸式显示设计规范（强制执行）：
   - 所有页面组件必须实现完全沉浸式显示，采用Stack双层布局设计
   - 背景层：使用expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.TOP, SafeAreaEdge.BOTTOM])扩展到状态栏和导航栏区域
   - 内容层：通过padding预留安全区域，使用@StorageProp('statusBarHeight')和@StorageProp('navigationBarHeight')获取系统栏高度
   - 页面组件必须声明沉浸式状态属性：@StorageProp('statusBarHeight') statusBarHeight: number = 0; @StorageProp('navigationBarHeight') navigationBarHeight: number = 0;
   - 布局结构：Stack() { 背景层.expandSafeArea(), 内容层.padding({ top: statusBarHeight, bottom: navigationBarHeight }) }
   - 所有新创建的页面组件都必须遵循此沉浸式设计规范，确保游戏界面的一致性和现代化体验
   - 背景图片、背景色等装饰元素也必须使用expandSafeArea扩展到系统栏区域，实现真正的全屏沉浸式效果
49.对于各种导入模块的问题，应该优先检查源文件中是否有正确的导出以及导出的名称，若是鸿蒙的模块，则要搜索相关的鸿蒙文档，确认是否有对应的模块和导出名称，并且学习正确的使用方法或者最佳实现
50.禁止在独立函数中使用this关键字，独立函数是指不依赖于类实例的函数，而this关键字通常用于类方法中引用类实例，在独立函数中使用this会导致类型错误，Using "this" inside stand-alone functions is not supported (arkts-no-standalone-this)
51.测试页面管理规范：
   - 所有测试工具和调试页面必须统一通过TestManagementPage进行管理和展示
   - 新增测试页面时必须在PageRoutes.ets中添加对应的路由配置
   - 测试页面必须在Index.ets的路由系统中注册，包括导入、路由配置、事件处理和页面渲染
   - 测试页面必须遵循沉浸式显示设计规范，实现完整的Stack双层布局
   - TestManagementPage中的测试项目列表必须包含完整的测试项目信息（id、title、description、icon、routeName、isAvailable）
   - 测试页面的返回按钮必须正确导航回TestManagementPage或MainMenuPage，确保用户体验的一致性
   - 所有测试页面都必须实现适当的日志记录，使用统一的Logger系统记录用户操作和测试结果
52.Navigation + 属性动画架构规范（强制执行）：
   - 项目采用基于Navigation组件的统一路由管理系统，所有页面跳转必须通过SystemIntegrationManager进行
   - 页面路由配置必须在PageRoutes.ets中统一定义，包括路由名称、动画类型、权限要求等
   - GameStateManager已移除，统一使用SystemIntegrationManager进行页面导航和状态管理
   - 所有UI组件必须继承或使用AnimatedComponent基类，实现统一的动画能力
   - 按钮组件必须使用AnimatedButton替代原生Button，提供丰富的交互动画效果
   - 页面入场动画必须使用AnimationType枚举定义的标准动画类型，确保动画效果的一致性
   - 动画延迟时间必须合理设置，避免过长的等待时间影响用户体验
   - 页面组件必须实现aboutToAppear生命周期中的入场动画序列，提供流畅的视觉体验
   - 所有动画相关的状态变量必须使用@State装饰器，确保动画状态的响应式更新
   - 复杂页面必须将UI构建逻辑拆分为多个@Builder方法，提高代码可读性和维护性
53.组件设计规范：
   - AnimatedComponent作为所有可动画组件的基类，提供统一的动画接口和状态管理
   - AnimatedButton提供标准的按钮交互动画，包括按压、悬停、焦点、成功、错误、水波纹和加载动画
   - 自定义组件必须遵循单一职责原则，每个组件只负责特定的UI功能
   - 组件参数必须使用@Prop装饰器接收外部数据，使用@State管理内部状态
   - 组件必须提供清晰的接口定义，包括必需参数和可选参数的明确区分
54.事件系统规范：
   - 页面导航相关事件必须通过EventBus系统进行发布和订阅
   - 新增的页面导航事件类型：PAGE_CHANGED、PAGE_ANIMATION_START、PAGE_ANIMATION_END、NAVIGATION_ERROR、NAVIGATION_BACK
   - 事件载荷类必须实现IEventPayload接口，确保事件数据的类型安全
   - 页面组件必须在适当的生命周期方法中订阅和取消订阅相关事件
55.性能优化规范：
   - 动画执行期间必须避免频繁的状态更新，使用批量更新机制
   - 长列表渲染必须使用LazyForEach替代ForEach，提高渲染性能
   - 图片资源必须使用SVG格式替代位图格式，减少包体积并支持矢量缩放
   - 动画完成后必须及时清理动画状态，避免内存泄漏
56.代码组织规范：
   - Framework/Managers目录：存放核心管理类（SystemIntegrationManager、AnimationManager等）
   - Framework/Navigation目录：存放路由配置和导航相关工具类
   - Framework/Components目录：存放可复用的UI组件
   - 文件命名必须使用PascalCase，与类名保持一致
   - 导入语句必须按照系统模块、第三方模块、项目模块的顺序组织
   - 每个文件必须包含清晰的职责注释，说明该文件的主要功能和用途
57.禁止使用非推断类型的数组字面量（arkts-no-noninferrable-arr-literals）：
   - 明确指定数组元素类型，避免使用非推断类型的数组字面量（如：[1, 2, 3]），确保类型安全和IDE支持
   - 对于推断类型的数组字面量（如：['a', 'b', 'c']），可以使用类型别名或联合类型来增强代码可读性
   - 对于Map构造函数中的数组字面量，应该使用Map的泛型类型声明和set方法逐个添加元素，而不是在构造函数中直接传入数组字面量
58.animateTo方法已完全废弃（HarmonyOS API 19）：
   - **废弃说明**：全局animateTo方法已在API 19中完全废弃，不再支持直接调用
   - **正确用法**：必须通过UIContext.animateTo执行动画，在@Component组件中使用this.getUIContext()获取当前组件的UI上下文
   - **获取UIContext**：在组件的aboutToAppear生命周期中调用this.getUIContext()获取UI上下文实例
   - **推荐使用模式**：
     ```typescript
     @Component
     struct MyComponent {
       @State animValue: number = 0;
       private uiContext: UIContext | undefined = undefined;
       
       aboutToAppear(): void {
         this.uiContext = this.getUIContext();
         if (!this.uiContext) {
           console.error('获取UIContext失败');
           return;
         }
         
         setTimeout(() => {
           this.startAnimation();
         }, 0);
       }
       
       private startAnimation(): void {
         if (this.uiContext) {
           const animateOptions: AnimateParam = { duration: 300, curve: Curve.EaseOut };
           this.uiContext.animateTo(animateOptions, () => {
             this.animValue = 100; // 修改状态变量，不是直接操作组件
           });
         }
       }
     }
     ```
   - **关键要点**：
     * 在动画回调中只能修改@State状态变量，不能直接操作组件实例
     * 必须在aboutToAppear中获取UIContext并存储为实例变量
     * 使用setTimeout确保组件完全渲染后再执行动画
     * 必须进行空值检查，避免UIContext为undefined时的调用错误
   - **错误示例**：在回调中直接调用组件方法如LoadingProgress().rotate()是错误的
   - **必须导入**：需要从@kit.ArkUI导入curves、UIContext等相关类型
59.扩展运算符使用限制（arkts-no-spread）：
   - 禁止在对象字面量中使用扩展运算符（...），应该使用显式的属性赋值
   - 对于需要合并对象属性的场景，应该逐个赋值属性而不是使用扩展运算符
   - 扩展运算符只能用于数组或从数组派生的类，不能用于普通对象
60.未类型化对象字面量修复规范（arkts-no-untyped-obj-literals）：
   - 所有对象字面量必须对应明确声明的类或接口
   - 为动画配置、选项参数等对象字面量提供明确的接口定义
   - 使用类型断言（as Type）来确保对象字面量符合预期的类型
   - 避免使用匿名对象类型，应该定义具名接口或类型别名
61.HarmonyOS系统资源名称映射规范（强制执行）：
   - 参考文件ResourceMap.ets，确保所有系统资源名称与文件中定义的一致
   - 所有系统颜色资源必须使用正确的资源名称格式，避免"Unknown resource name"编译错误
   - 使用系统资源的优势：自动适配系统深色/浅色模式、保持界面一致性、提供更好的可访问性支持
62. **getContext 已完全废弃 (HarmonyOS API 19)**：
   - **废弃说明**：`getContext()` 方法已完全废弃，包括有参和无参调用
   - **正确用法**：使用 `this.getUIContext()?.getHostContext()` 获取上下文
   - **必须导入**：`import { common } from '@kit.AbilityKit';`
   - **使用场景**：在@Component组件中获取UIAbilityContext，用于调用terminateSelf()等方法
   - **示例代码**：
     ```typescript
     import { common } from '@kit.AbilityKit';   
     // 在@Component组件方法中
     const context = this.getUIContext()?.getHostContext() as common.UIAbilityContext;
     if (context) {
       context.terminateSelf();
     } else {
       // 处理获取失败的情况
       console.error('无法获取UIAbilityContext');
     }
     ```
   - **注意事项**：
     - 必须在@Component装饰的组件中使用
     - 需要进行空值检查，因为getUIContext()可能返回undefined
     - 适用于组件级别的上下文获取
   - **其他废弃API迁移**：
     - `router.replaceUrl()` → `this.getUIContext().getRouter().replaceUrl()`
     - 类似的UI相关API都需要通过UIContext获取
63. **rawfile资源访问规范**：
   - rawfile目录下的文件不需要在ResourceMap.ets中单独映射
   - 直接使用相对路径访问rawfile资源：`$rawfile('path/to/file.json')`
   - rawfile适用于配置文件、数据文件、音频、视频等静态资源
   - 与element资源不同，rawfile资源在运行时按需加载，不会增加应用启动时间
63. **C++底层集成开发规范（已废弃）**：
   - **废弃说明**：项目已转型为纯应用软件，不再包含游戏相关的C++底层逻辑
   - **迁移指导**：原有的C++模块已被移除，相关功能已迁移到ArkTS实现
   - **架构变更**：项目现在采用纯ArkTS架构，专注于应用功能而非游戏逻辑
64. **C++与ArkTS交互最佳实践（已废弃）**：
   - **废弃说明**：随着C++模块的移除，跨语言交互规范不再适用
   - **替代方案**：使用ArkTS原生API和HarmonyOS系统服务实现相关功能
65. **游戏核心逻辑C++实现规范（已废弃）**：
   - **废弃说明**：项目不再包含游戏逻辑，相关规范已废弃
   - **功能转换**：原有的游戏逻辑已转换为通用的应用功能模块
66. **HarmonyOS资源映射路径规范（强制执行）**：
   - **资源引用原则**：在resources_metadata.json中必须使用映射路径字符串（如"app.media.logo"、"app.rawfile.config_game_config"），而不是直接的文件路径
   - **映射路径格式**：
     * 图片资源："app.media.资源名称"（如"app.media.logo"）
     * 音频资源："app.audio.资源名称"（如"app.audio.game_music"）
     * 字符串资源："app.string.资源名称"（如"app.string.welcome_message"）
     * 其他资源类型：根据HarmonyOS的资源类型定义，如"app.font.字体名称"、"app.color.颜色名称"等
     * 资源名称不包含文件扩展名，由HarmonyOS编译器自动处理
   - **ResourceMap.ets文件职责**：
     * 维护映射路径字符串到Resource对象的映射关系
     * 使用$r()语法在编译时将字符串关联到真实的Resource对象
     * 提供imageMap、audioMap、stringMap、fontMap、colorMap和统一的resourceMap导出
     * 提供getResource()和hasResource()工具函数
   - **编译优化优势**：
     * 映射路径字符串在JSON中具有良好的可读性和可维护性
     * $r()语法确保资源在编译时被正确优化和打包
     * 支持资源的自动压缩、格式转换和多分辨率适配
   - **使用示例**：
     ```typescript
     // resources_metadata.json中的配置
     "image_logo": {
       "type": "IMAGE",
       "path": "app.media.logo",  // 映射路径字符串
       "priority": 9
     }
     
     // ResourceMap.ets中的映射
     export const imageMap: Record<string, Resource> = {
       'app.media.logo': $r('app.media.logo')  // 编译时优化
     };
     ```
   - **禁止使用**：直接文件路径（如"images/logo.svg"）会绕过HarmonyOS的资源优化机制
   - **资源类型支持**：图片资源（app.media.*）、音频资源（app.audio.*）、字符串资源（app.string.*）、字体资源（app.font.*）、颜色资源（app.color.*）等
   67.Definite assignment assertions are not supported (arkts-no-definite-assignment)
68. **Native C++模块规范化开发规范（已废弃）**：
   - **废弃说明**：项目已转型为纯应用软件，不再使用Native C++模块
   - **迁移指导**：原有的C++模块已被移除，相关功能已迁移到ArkTS实现
   - **架构简化**：项目现在采用纯ArkTS架构，简化了开发和维护复杂度
69.所有独立的入口页面文件都必须在src/main/resources/base/profile/main_pages.json进行管理
70.禁止使用router模块进行页面跳转，必须使用navPathStack进行页面跳转
72. **纯应用软件开发规范（强制执行）**：
   - **项目定位**：项目已转型为纯应用软件，专注于提供实用的应用功能而非游戏体验
   - **架构简化**：采用纯ArkTS架构，移除了所有游戏相关的复杂逻辑和C++底层模块
   - **功能导向**：所有功能模块都应围绕应用的核心价值进行设计，提供清晰的用户价值
   - **UI/UX设计**：界面设计应遵循HarmonyOS设计规范，提供简洁、直观的用户体验
   - **性能优化**：专注于应用启动速度、响应性能和内存使用效率的优化
   - **代码质量**：保持高质量的代码标准，确保可维护性和可扩展性
   - **用户体验**：优先考虑用户需求和使用场景，提供流畅的交互体验
   71. **@Watch装饰器使用规范（强制执行）**：
   - **基本用法**：@Watch用于监听状态变量的变化，当状态变量变化时，@Watch的回调方法将被调用 <mcreference link="https://developer.huawei.com/consumer/cn/doc/harmonyos-guides/arkts-watch" index="2">2</mcreference>
   - **装饰器参数**：@Watch参数为必选，且参数类型必须是string，格式为@Watch('methodName')，其中methodName是自定义组件的成员函数名 <mcreference link="https://developer.huawei.com/consumer/cn/doc/harmonyos-guides/arkts-watch" index="2">2</mcreference>
   - **回调函数签名**：被@Watch装饰的函数签名必须为`(changedPropertyName?: string) => void`，该函数是自定义组件的成员函数 <mcreference link="https://developer.huawei.com/consumer/cn/doc/harmonyos-guides/arkts-watch" index="2">2</mcreference>
   - **访问修饰符限制**：被@Watch装饰的函数不能是private的，必须是public或不指定访问修饰符（默认为public）
   - **可监听变量类型**：@Watch可监听所有装饰器装饰的状态变量（如@State、@Prop、@Link等），不允许监听常规变量 <mcreference link="https://developer.huawei.com/consumer/cn/doc/harmonyos-guides/arkts-watch" index="2">2</mcreference>
   - **装饰器顺序**：装饰器顺序不影响实际功能，建议@State、@Prop、@Link等装饰器在@Watch装饰器之前，以保持整体风格的一致 <mcreference link="https://developer.huawei.com/consumer/cn/doc/harmonyos-guides/arkts-watch" index="2">2</mcreference>
   - **触发时机**：@Watch回调在自定义组件的属性变更之后同步执行，在第一次初始化时不会被调用，只有在后续状态改变时才会调用 <mcreference link="https://developer.huawei.com/consumer/cn/doc/harmonyos-guides/arkts-watch" index="2">2</mcreference>
   - **性能注意事项**：
     * 避免在@Watch回调中直接或间接修改同一个状态变量，防止无限循环 <mcreference link="https://developer.huawei.com/consumer/cn/doc/harmonyos-guides/arkts-watch" index="2">2</mcreference>
     * 回调函数应仅执行快速运算，避免延迟组件重新渲染 <mcreference link="https://developer.huawei.com/consumer/cn/doc/harmonyos-guides/arkts-watch" index="2">2</mcreference>
     * 不建议在@Watch函数中调用async await，因为异步行为可能导致重新渲染速度的性能问题 <mcreference link="https://developer.huawei.com/consumer/cn/doc/harmonyos-guides/arkts-watch" index="2">2</mcreference>
   - **使用示例**：
     ```typescript
     @Component
     struct MyComponent {
       @State @Watch('onCountChange') count: number = 0;
       @Prop @Watch('onDataChange') data: string = '';
       
       // 正确：public函数或不指定访问修饰符
       onCountChange(propName: string): void {
         console.log(`${propName} changed to: ${this.count}`);
       }
       
       // 正确：不指定访问修饰符（默认public）
       onDataChange(): void {
         console.log('Data changed');
       }
       
       // 错误：不能使用private
       // private onPrivateChange(): void { }
     }
     ```
   - **错误处理**：
     * @Watch参数必须是声明的方法名,否则编译期会报错 <mcreference link="https://developer.huawei.com/consumer/cn/doc/harmonyos-guides/arkts-watch" index="2">2</mcreference>
     * 常规变量不能被@Watch装饰,否则编译期会报错 <mcreference link="https://developer.huawei.com/consumer/cn/doc/harmonyos-guides/arkts-watch" index="2">2</mcreference>
73. **WebView图源引擎架构规范（强制执行）**：
   - **设计原则**：图源隔离、按需激活、最小影响
   - **核心架构**：
     * MangaSourceEngine：图源引擎主控制器，负责工作流执行
     * MangaSourceActionEngine：操作执行引擎，负责navigate、wait、extract、script等操作
     * MangaSourceConfigParser：配置解析器，负责解析JSON配置文件
     * ImageInterceptor：图片拦截器（单例），负责图片解扰和处理
   - **图源配置文件规范**：
     * 位置：sources/*.json
     * 结构：metadata（元数据）、capabilities（能力声明）、network（网络配置）、workflows（工作流定义）
     * 每个图源独立配置，互不干扰
   - **图片处理流程**：
     1. 图源加载时，通过`configureDescramblerForSource(sourceId, config)`注册图片处理配置
     2. ImageInterceptor根据sourceId和URL模式判断是否需要拦截处理
     3. 只有匹配urlPattern的图片才会被处理，其他图片直接返回原始数据
     4. 处理完成后缓存结果，避免重复处理
   - **特殊图源适配原则**（以禁漫天堂为例）：
     * **隔离性**：特殊处理逻辑只在该图源的配置文件和专用解扰器中实现
     * **条件激活**：通过`imageDescrambler.enabled`和`urlPattern`精确控制激活条件
     * **最小影响**：不修改核心引擎代码，不影响其他图源的正常工作
     * **降级策略**：处理失败时返回原始数据，确保基本功能可用
   - **禁漫天堂图源特殊处理**：
     * 图片解扰：通过`JinmantiantangDescrambler`实现MD5哈希分割算法
     * Base64解码：在workflow的script操作中实现，注入到DOM
     * 动态域名：通过settings.domain配置和autoUpdate机制
     * 速率限制：通过network.rateLimit配置控制请求频率
     * URL模式匹配：`urlPattern: "media/photos"`确保只处理需要解扰的图片
   - **新图源添加流程**：
     1. 在sources/目录创建新的JSON配置文件
     2. 定义metadata、capabilities、workflows等配置
     3. 如需特殊图片处理，实现专用的Descrambler类
     4. 在ImageDescramblerInitializer中注册新的解扰算法
     5. 配置imageDescrambler节点，指定algorithm和urlPattern
   - **调试和日志**：
     * 每个图源操作都有详细的日志记录
     * 使用TAG标识不同的模块（MangaSourceEngine、ImageInterceptor等）
     * 记录操作耗时、成功/失败状态、数据量等关键信息
   - **性能优化**：
     * 图片处理结果缓存（MAX_CACHE_SIZE=50）
     * LRU缓存策略，自动清理最旧条目
     * 支持按图源清理缓存
   - **错误处理**：
     * 所有操作都有try-catch保护
     * 失败时返回原始数据，不中断用户体验
     * 详细的错误日志便于问题定位
   - **禁止事项**：
     * 禁止修改核心引擎代码以适配特定图源
     * 禁止在全局范围内启用特殊处理逻辑
     * 禁止让一个图源的配置影响其他图源
     * 禁止在没有urlPattern匹配的情况下处理图片
   - **最佳实践**：
     * 优先使用workflow配置实现功能，避免硬编码
     * 复杂逻辑使用script操作在WebView中执行
     * 图片处理使用独立的Descrambler类，通过注册机制集成
     * 配置文件中明确声明capabilities，便于引擎优化
     * 使用settings节点提供用户可配置选项