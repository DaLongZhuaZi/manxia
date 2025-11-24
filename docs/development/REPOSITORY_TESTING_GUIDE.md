# 图源仓库测试指南

## 修复完成

所有 ArkTS 编译错误已修复：

### 修复内容

1. **定义独立接口** (`SourceSubEntry`)
   - 将匿名对象类型改为显式接口定义
   - 符合 `arkts-no-obj-literals-as-types` 规则

2. **包装 throw 语句**
   - 所有 `throw error` 改为 `throw new Error(errorMsg)`
   - 符合 `arkts-limited-throw` 规则

3. **移动接口定义**
   - 将 `SyncResult` 接口从类内部移到外部
   - 避免在类内部使用 `export interface`

4. **类型导入**
   - 在 `MainMenuPage.ets` 中添加 `SyncResult` 类型导入

## 测试仓库文件结构

已创建完整的测试仓库，位于 `test-repository/` 目录：

```
test-repository/
├── index.main.json                              # 仓库索引文件（必需）
├── com.manxia.extension.zh.zaimanhua.json      # 再漫画图源完整配置
└── README.md                                    # 使用说明
```

### 文件说明

#### 1. index.main.json
这是仓库的主索引文件，应用会首先下载这个文件来获取所有可用图源的列表。

**格式**：
```json
[
  {
    "name": "ManXia: Zaimanhua",           // 图源显示名称
    "pkg": "com.manxia.extension.zh.zaimanhua",  // 包名（唯一标识）
    "lang": "zh",                          // 语言代码
    "code": 1,                             // 版本代码
    "version": "1.0.0",                    // 版本号
    "nsfw": 0,                             // 是否NSFW (0=否, 1=是)
    "sources": [                           // 子图源列表
      {
        "name": "再漫画",
        "lang": "zh",
        "id": "524579092615598717",
        "baseUrl": "https://manhua.zaimanhua.com"
      }
    ]
  }
]
```

**关键字段**：
- `pkg`: 必须唯一，用于标识图源和对应的配置文件
- `sources`: 数组，一个图源包可以包含多个子图源
- `id`: 图源的唯一ID，通常是长整型数字字符串

#### 2. com.manxia.extension.zh.zaimanhua.json
完整的图源配置文件，包含：
- 基本元数据（与 index.main.json 中的信息一致）
- 详细的 API 配置
- 完整的工作流定义（search, getMangaDetail, getChapterList 等）
- 设置选项

**文件命名规则**：`{pkg}.json`

## 部署方式

### 方式1：本地测试（推荐用于开发）

使用 Python 快速启动 HTTP 服务器：

```bash
# 进入 test-repository 目录
cd f:\DevEcoStudioProject\manxia\test-repository

# 启动服务器（Python 3）
python -m http.server 8000

# 或使用 Python 2
python -m SimpleHTTPServer 8000
```

**测试地址**：`http://localhost:8000/index.main.json`

**优点**：
- 快速启动
- 无需配置
- 适合本地调试

**注意事项**：
- 确保防火墙允许端口 8000
- 如果端口被占用，可以更改端口号

### 方式2：使用 Node.js (http-server)

```bash
# 安装 http-server（全局）
npm install -g http-server

# 启动服务器
cd f:\DevEcoStudioProject\manxia\test-repository
http-server -p 8000 --cors
```

**测试地址**：`http://localhost:8000/index.main.json`

**优点**：
- 自动启用 CORS
- 更好的性能
- 更多配置选项

### 方式3：GitHub Pages（推荐用于生产）

1. **创建 GitHub 仓库**
   ```bash
   # 初始化 Git 仓库
   cd f:\DevEcoStudioProject\manxia\test-repository
   git init
   git add .
   git commit -m "Initial commit: ManXia sources repository"
   ```

2. **推送到 GitHub**
   ```bash
   # 创建远程仓库后
   git remote add origin https://github.com/your-username/manxia-sources.git
   git branch -M main
   git push -u origin main
   ```

3. **启用 GitHub Pages**
   - 进入仓库 Settings
   - 找到 Pages 选项
   - Source 选择 `main` 分支
   - 保存

4. **获取 URL**
   - 格式：`https://your-username.github.io/manxia-sources/index.main.json`

**优点**：
- 免费
- 稳定可靠
- 自动 HTTPS
- 全球 CDN

### 方式4：Netlify（最简单）

1. **拖拽部署**
   - 访问 [Netlify](https://netlify.com)
   - 注册/登录
   - 将 `test-repository` 文件夹拖拽到部署区域

2. **获取 URL**
   - Netlify 会自动生成一个 URL
   - 格式：`https://random-name.netlify.app/index.main.json`
   - 可以自定义域名

**优点**：
- 最简单的部署方式
- 自动 HTTPS
- 免费额度充足
- 支持自定义域名

### 方式5：Vercel

```bash
# 安装 Vercel CLI
npm install -g vercel

# 部署
cd f:\DevEcoStudioProject\manxia\test-repository
vercel
```

**优点**：
- 部署速度快
- 自动 HTTPS
- 全球 CDN
- 免费额度充足

## 在应用中测试

### 步骤

1. **启动应用**
   - 运行 ManXia 应用

2. **打开图源页面**
   - 点击底部导航栏的"图源"标签

3. **打开仓库弹窗**
   - 点击"导入图源仓库"按钮（或类似按钮）

4. **输入仓库地址**
   - 本地测试：`http://localhost:8000/index.main.json`
   - 在线测试：`https://your-domain.com/index.main.json`

5. **同步仓库**
   - 点击"确认同步"按钮
   - 等待同步完成

6. **查看结果**
   - 同步成功后会显示提示信息
   - 图源列表会自动刷新
   - 可以看到新增的"再漫画"图源

### 预期结果

**成功情况**：
- 显示提示：`同步成功！新增1个图源，更新0个图源`
- 图源列表中出现"再漫画"
- 在 `filesDir/extensions-source/` 目录下生成：
  - `index.main.json`（更新）
  - `com.manxia.extension.zh.zaimanhua.json`（新建）
  - `saved_repositories.json`（更新）

**失败情况**：
- 网络错误：检查 URL 是否正确，服务器是否运行
- 解析错误：检查 JSON 格式是否正确
- CORS 错误：确保服务器启用了 CORS

## 调试技巧

### 1. 查看日志

在应用中查看日志输出：
```
TAG: SourceRepositoryManager
- 开始同步仓库: {url}
- 图源仓库同步成功: {message}
```

### 2. 验证 JSON 格式

使用在线工具验证 JSON：
- [JSONLint](https://jsonlint.com/)
- [JSON Formatter](https://jsonformatter.org/)

### 3. 测试 HTTP 请求

使用 curl 测试：
```bash
curl http://localhost:8000/index.main.json
```

使用浏览器直接访问：
```
http://localhost:8000/index.main.json
```

### 4. 检查文件权限

确保文件可读：
```bash
# Windows
icacls test-repository\index.main.json

# Linux/Mac
ls -la test-repository/index.main.json
```

## 常见问题

### Q1: CORS 错误
**问题**：浏览器控制台显示 CORS 错误

**解决方案**：
- 使用支持 CORS 的服务器（如 http-server --cors）
- 部署到支持 CORS 的在线服务
- 在开发环境中禁用 CORS 检查（不推荐）

### Q2: 404 错误
**问题**：找不到 index.main.json

**解决方案**：
- 检查 URL 路径是否正确
- 确认文件名拼写正确
- 检查服务器是否正常运行

### Q3: JSON 解析错误
**问题**：同步失败，提示 JSON 解析错误

**解决方案**：
- 使用 JSON 验证工具检查格式
- 检查是否有多余的逗号
- 确保所有字符串使用双引号

### Q4: 同步后看不到图源
**问题**：同步成功但图源列表没有更新

**解决方案**：
- 刷新图源列表
- 重启应用
- 检查日志确认是否真的同步成功

## 扩展仓库

### 添加更多图源

1. **准备图源配置**
   - 创建新的图源 JSON 文件
   - 参考 `zaimanhua_api.json` 的格式

2. **更新 index.main.json**
   ```json
   [
     {
       "name": "ManXia: Zaimanhua",
       ...
     },
     {
       "name": "ManXia: NewSource",
       "pkg": "com.manxia.extension.zh.newsource",
       "lang": "zh",
       "code": 1,
       "version": "1.0.0",
       "nsfw": 0,
       "sources": [...]
     }
   ]
   ```

3. **创建图源文件**
   - 文件名：`com.manxia.extension.zh.newsource.json`
   - 包含完整配置

4. **测试**
   - 重新同步仓库
   - 验证新图源是否出现

### 版本管理

**更新图源版本**：
1. 修改图源配置文件
2. 增加 `code` 和 `version` 字段
3. 更新 `index.main.json` 中对应的版本信息
4. 重新部署

**版本号规则**：
- `version`: 语义化版本（如 1.0.0）
- `code`: 整数，每次更新递增

## 生产环境建议

### 1. 使用 CDN
- 部署到支持 CDN 的服务（GitHub Pages, Netlify, Vercel）
- 提高全球访问速度

### 2. 启用 HTTPS
- 所有生产环境必须使用 HTTPS
- 防止中间人攻击

### 3. 版本控制
- 使用 Git 管理仓库
- 为每个版本打 tag

### 4. 自动化部署
- 设置 CI/CD 流程
- 自动验证 JSON 格式
- 自动部署到生产环境

### 5. 监控和日志
- 监控仓库访问情况
- 记录同步错误
- 定期检查图源可用性

## 安全考虑

1. **验证 URL**
   - 只允许 HTTPS URL（生产环境）
   - 验证域名白名单

2. **限制文件大小**
   - index.main.json 不应超过 10MB
   - 单个图源配置不应超过 1MB

3. **内容验证**
   - 验证 JSON 结构
   - 检查必需字段
   - 过滤恶意内容

4. **速率限制**
   - 限制同步频率
   - 防止滥用

## 总结

现在你有了一个完整的测试仓库，可以：

1. ✅ 本地测试图源仓库同步功能
2. ✅ 验证 JSON 格式和数据结构
3. ✅ 部署到在线服务进行远程测试
4. ✅ 扩展添加更多图源

**推荐测试流程**：
1. 先使用本地服务器测试（Python http.server）
2. 验证功能正常后部署到 Netlify 或 GitHub Pages
3. 使用在线 URL 进行最终测试
4. 添加更多图源并重复测试

祝测试顺利！🎉
