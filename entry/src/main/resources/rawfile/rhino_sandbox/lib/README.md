# Rhino Sandbox 本地库

本目录包含Rhino WASM沙箱所需的本地化库文件。

## 文件说明

### 必需文件

1. **rhino-1.7.14.jar** - Mozilla Rhino JavaScript引擎
   - 下载地址: https://github.com/mozilla/rhino/releases/download/Rhino1_7_14_Release/rhino-1.7.14.jar
   - 大小: 约1.2MB

2. **jsoup-1.17.2.jar** - Java HTML解析器
   - 下载地址: https://jsoup.org/packages/jsoup-1.17.2.jar
   - 大小: 约400KB

### CheerpJ运行时（可选）

CheerpJ是将Java字节码转换为WebAssembly的商业工具。由于其运行时文件较大（约50MB+），
建议使用CDN加载或联系Leaning Technologies获取本地部署许可。

- 官网: https://cheerpj.com/
- CDN: https://cjrtnc.leaningtech.com/3.0/

## 下载脚本

### Windows (PowerShell)
```powershell
# 下载Rhino
Invoke-WebRequest -Uri "https://github.com/mozilla/rhino/releases/download/Rhino1_7_14_Release/rhino-1.7.14.jar" -OutFile "rhino-1.7.14.jar"

# 下载Jsoup
Invoke-WebRequest -Uri "https://jsoup.org/packages/jsoup-1.17.2.jar" -OutFile "jsoup-1.17.2.jar"
```

### Linux/macOS
```bash
# 下载Rhino
curl -L -o rhino-1.7.14.jar https://github.com/mozilla/rhino/releases/download/Rhino1_7_14_Release/rhino-1.7.14.jar

# 下载Jsoup
curl -L -o jsoup-1.17.2.jar https://jsoup.org/packages/jsoup-1.17.2.jar
```

## 注意事项

1. 这些JAR文件需要通过CheerpJ转换为可在浏览器中运行的格式
2. 如果不使用CheerpJ，离线模式将使用纯JavaScript实现
3. 确保文件放置在正确的目录中
