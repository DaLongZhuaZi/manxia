# 禁漫天堂图源实施指南

## 📌 概述

本文档提供禁漫天堂图源的详细实施指南，包括系统扩展、代码实现、测试方案等。

---

## 1️⃣ 图片解扰模块实现

### 1.1 核心算法实现（ArkTS）

**文件位置：** `entry/src/main/ets/utils/ImageDescrambler.ets`

```typescript
import image from '@ohos.image';
import cryptoFramework from '@ohos.security.cryptoFramework';
import { Logger } from './Logger';

const TAG = 'ImageDescrambler';

export interface DescramblerConfig {
  scrambleIdThreshold: number;
  modulusRules: Array<{ minAid: number; modulus: number }>;
  outputQuality: number;
}

export class JinmantiantangDescrambler {
  private config: DescramblerConfig;

  constructor(config: DescramblerConfig) {
    this.config = config;
  }

  /**
   * 计算 MD5 哈希的最后一个字符的字符码
   */
  private async md5LastCharCode(input: string): Promise<number> {
    try {
      const md = cryptoFramework.createMd('MD5');
      const inputData = new Uint8Array(Buffer.from(input, 'utf-8'));
      await md.update({ data: inputData });
      const result = await md.digest();
      
      // 获取最后一个字节
      const lastByte = result.data[result.data.length - 1];
      // 转换为16进制字符串并取最后一个字符
      const hexStr = lastByte.toString(16).padStart(2, '0');
      const lastChar = hexStr.charAt(hexStr.length - 1);
      
      return lastChar.charCodeAt(0);
    } catch (error) {
      Logger.error(TAG, `MD5计算失败: ${error}`);
      throw error;
    }
  }

  /**
   * 根据章节ID和图片索引计算分割行数
   */
  private async getRows(aid: number, imgIndex: string): Promise<number> {
    // 根据章节ID确定模数
    let modulus = 10;
    for (const rule of this.config.modulusRules) {
      if (aid >= rule.minAid) {
        modulus = rule.modulus;
        break;
      }
    }

    // 计算分割行数
    const hashCode = await this.md5LastCharCode(aid.toString() + imgIndex);
    const rows = 2 * (hashCode % modulus) + 2;
    
    Logger.info(TAG, `章节ID=${aid}, 图片索引=${imgIndex}, 模数=${modulus}, 行数=${rows}`);
    return rows;
  }

  /**
   * 检查是否需要解扰
   */
  shouldDescramble(url: string, aid: number): boolean {
    return url.includes('media/photos') && aid >= this.config.scrambleIdThreshold;
  }

  /**
   * 解扰图片
   */
  async descrambleImage(
    imageData: ArrayBuffer,
    aid: number,
    imgIndex: string
  ): Promise<ArrayBuffer> {
    try {
      Logger.info(TAG, `开始解扰图片: aid=${aid}, imgIndex=${imgIndex}`);
      const startTime = Date.now();

      // 1. 创建 ImageSource
      const imageSource = image.createImageSource(imageData);
      const imageInfo = await imageSource.getImageInfo();
      
      const width = imageInfo.size.width;
      const height = imageInfo.size.height;
      Logger.info(TAG, `图片尺寸: ${width}x${height}`);

      // 2. 计算分割参数
      const rows = await this.getRows(aid, imgIndex);
      const remainder = height % rows;

      // 3. 创建源 PixelMap
      const sourcePixelMap = await imageSource.createPixelMap();

      // 4. 创建目标 PixelMap
      const resultPixelMap = await image.createPixelMap(
        new ArrayBuffer(width * height * 4),
        {
          size: { width, height },
          pixelFormat: image.PixelMapFormat.RGBA_8888,
          editable: true
        }
      );

      // 5. 逆序拼接图片
      for (let x = 0; x < rows; x++) {
        let copyH = Math.floor(height / rows);
        let py = copyH * x;
        const y = height - (copyH * (x + 1)) - remainder;

        if (x === 0) {
          copyH += remainder;
        } else {
          py += remainder;
        }

        // 读取源区域
        const sourceRegion = {
          x: 0,
          y: y,
          size: { width: width, height: copyH }
        };
        
        const pixels = new ArrayBuffer(width * copyH * 4);
        await sourcePixelMap.readPixelsToBuffer(pixels);

        // 写入目标区域
        const targetRegion = {
          x: 0,
          y: py,
          size: { width: width, height: copyH }
        };
        
        await resultPixelMap.writePixels(targetRegion, pixels);
      }

      // 6. 编码为 JPEG
      const packer = image.createImagePacker();
      const packOpts = {
        format: 'image/jpeg',
        quality: this.config.outputQuality
      };
      
      const resultData = await packer.packing(resultPixelMap, packOpts);
      
      // 7. 清理资源
      sourcePixelMap.release();
      resultPixelMap.release();

      const elapsed = Date.now() - startTime;
      Logger.info(TAG, `图片解扰完成，耗时: ${elapsed}ms`);

      return resultData;
    } catch (error) {
      Logger.error(TAG, `图片解扰失败: ${error}`);
      throw error;
    }
  }

  /**
   * 从URL提取章节ID和图片索引
   */
  extractImageInfo(url: string): { aid: number; imgIndex: string } | null {
    try {
      // URL格式: https://cdn.xxx.com/media/photos/123456/00001.jpg
      const match = url.match(/\/photos\/(\d+)\/(\d+)\./);
      if (match) {
        return {
          aid: parseInt(match[1]),
          imgIndex: match[2]
        };
      }
      return null;
    } catch (error) {
      Logger.error(TAG, `提取图片信息失败: ${error}`);
      return null;
    }
  }
}
```

### 1.2 HTTP拦截器集成

**文件位置：** `entry/src/main/ets/network/ImageInterceptor.ets`

```typescript
import http from '@ohos.net.http';
import { JinmantiantangDescrambler } from '../utils/ImageDescrambler';
import { Logger } from '../utils/Logger';

const TAG = 'ImageInterceptor';

export class ImageInterceptor {
  private descrambler: JinmantiantangDescrambler;
  private enabledSources: Set<string>;

  constructor() {
    this.enabledSources = new Set();
    this.descrambler = new JinmantiantangDescrambler({
      scrambleIdThreshold: 220980,
      modulusRules: [
        { minAid: 421926, modulus: 8 },
        { minAid: 268850, modulus: 10 },
        { minAid: 0, modulus: 10 }
      ],
      outputQuality: 90
    });
  }

  /**
   * 启用指定图源的图片解扰
   */
  enableSource(sourceId: string): void {
    this.enabledSources.add(sourceId);
    Logger.info(TAG, `已启用图源 ${sourceId} 的图片解扰`);
  }

  /**
   * 禁用指定图源的图片解扰
   */
  disableSource(sourceId: string): void {
    this.enabledSources.delete(sourceId);
    Logger.info(TAG, `已禁用图源 ${sourceId} 的图片解扰`);
  }

  /**
   * 拦截并处理图片请求
   */
  async intercept(
    url: string,
    sourceId: string,
    response: ArrayBuffer
  ): Promise<ArrayBuffer> {
    try {
      // 检查是否需要处理
      if (!this.enabledSources.has(sourceId)) {
        return response;
      }

      // 提取图片信息
      const imageInfo = this.descrambler.extractImageInfo(url);
      if (!imageInfo) {
        Logger.warn(TAG, `无法从URL提取图片信息: ${url}`);
        return response;
      }

      // 检查是否需要解扰
      if (!this.descrambler.shouldDescramble(url, imageInfo.aid)) {
        Logger.info(TAG, `图片无需解扰: aid=${imageInfo.aid}`);
        return response;
      }

      // 执行解扰
      Logger.info(TAG, `开始解扰图片: ${url}`);
      return await this.descrambler.descrambleImage(
        response,
        imageInfo.aid,
        imageInfo.imgIndex
      );
    } catch (error) {
      Logger.error(TAG, `图片拦截处理失败: ${error}`);
      // 失败时返回原始数据
      return response;
    }
  }
}

// 全局单例
export const imageInterceptor = new ImageInterceptor();
```

### 1.3 在图片加载中集成

**文件位置：** `entry/src/main/ets/components/MangaImage.ets`

```typescript
import image from '@ohos.image';
import http from '@ohos.net.http';
import { imageInterceptor } from '../network/ImageInterceptor';
import { Logger } from '../utils/Logger';

@Component
export struct MangaImage {
  @Prop imageUrl: string;
  @Prop sourceId: string;
  @State pixelMap: PixelMap | null = null;
  @State loading: boolean = true;
  @State error: string = '';

  async loadImage() {
    try {
      this.loading = true;
      this.error = '';

      // 1. 发起HTTP请求
      const httpRequest = http.createHttp();
      const response = await httpRequest.request(this.imageUrl, {
        method: http.RequestMethod.GET,
        expectDataType: http.HttpDataType.ARRAY_BUFFER
      });

      if (response.responseCode !== 200) {
        throw new Error(`HTTP ${response.responseCode}`);
      }

      // 2. 通过拦截器处理图片
      let imageData = response.result as ArrayBuffer;
      imageData = await imageInterceptor.intercept(
        this.imageUrl,
        this.sourceId,
        imageData
      );

      // 3. 创建 PixelMap
      const imageSource = image.createImageSource(imageData);
      this.pixelMap = await imageSource.createPixelMap();

      this.loading = false;
      Logger.info('MangaImage', `图片加载成功: ${this.imageUrl}`);
    } catch (error) {
      this.loading = false;
      this.error = `加载失败: ${error}`;
      Logger.error('MangaImage', `图片加载失败: ${error}`);
    }
  }

  aboutToAppear() {
    this.loadImage();
  }

  build() {
    if (this.loading) {
      LoadingProgress()
        .width(50)
        .height(50)
    } else if (this.error) {
      Text(this.error)
        .fontSize(12)
        .fontColor(Color.Red)
    } else if (this.pixelMap) {
      Image(this.pixelMap)
        .width('100%')
        .height('100%')
        .objectFit(ImageFit.Contain)
    }
  }
}
```

---

## 2️⃣ Base64解码模块实现

### 2.1 WebView工作流扩展

**文件位置：** `entry/src/main/ets/source/WebViewExecutor.ets`

在现有的 `executeAction` 方法中添加 Base64 解码支持：

```typescript
private async executeBase64Decode(action: any): Promise<any> {
  const selector = action.selector || '#wrapper > script';
  const pattern = action.pattern || 'base64DecodeUtf8\\("([^"]+)"\\)';
  const injectTarget = action.injectTarget || 'body';
  const injectPosition = action.injectPosition || 'beforeend';

  const script = `
    (() => {
      console.log('[Base64解码] 开始查找加密内容');
      const scripts = document.querySelectorAll('${selector}');
      let decoded = false;
      
      for(let script of scripts) {
        const code = script.innerHTML;
        if(code.includes('base64DecodeUtf8')) {
          const regex = /${pattern}/;
          const match = code.match(regex);
          
          if(match && match[1]) {
            try {
              const decodedHtml = atob(match[1]);
              document.querySelector('${injectTarget}')
                .insertAdjacentHTML('${injectPosition}', decodedHtml);
              console.log('[Base64解码] 成功解码并注入，长度: ' + decodedHtml.length);
              decoded = true;
              break;
            } catch(e) {
              console.error('[Base64解码] 解码失败:', e);
            }
          }
        }
      }
      
      return decoded ? 'DECODED' : 'NO_ENCODED_CONTENT';
    })();
  `;

  return await this.webViewController.runJavaScript(script);
}
```

### 2.2 在工作流配置中使用

```json
{
  "type": "base64Decode",
  "selector": "#wrapper > script:contains(base64DecodeUtf8)",
  "pattern": "base64DecodeUtf8\\(\"([^\"]+)\"\\)",
  "injectTarget": "body",
  "injectPosition": "beforeend",
  "description": "解码并注入Base64内容"
}
```

---

## 3️⃣ 动态域名管理实现

### 3.1 域名管理器

**文件位置：** `entry/src/main/ets/source/DomainManager.ets`

```typescript
import http from '@ohos.net.http';
import preferences from '@ohos.data.preferences';
import { Logger } from '../utils/Logger';

const TAG = 'DomainManager';

export interface DomainConfig {
  updateUrl: string;
  format: 'text' | 'json';
  separator?: string;
  updateInterval: number;
  fallbackDomains: string[];
}

export class DomainManager {
  private sourceId: string;
  private config: DomainConfig;
  private currentDomain: string;
  private availableDomains: string[];
  private lastUpdateTime: number = 0;
  private preferences: preferences.Preferences | null = null;

  constructor(sourceId: string, config: DomainConfig, initialDomain: string) {
    this.sourceId = sourceId;
    this.config = config;
    this.currentDomain = initialDomain;
    this.availableDomains = [...config.fallbackDomains];
  }

  /**
   * 初始化（加载保存的域名列表）
   */
  async initialize(): Promise<void> {
    try {
      this.preferences = await preferences.getPreferences(
        getContext(),
        `domain_${this.sourceId}`
      );

      // 加载保存的域名列表
      const saved = await this.preferences.get('domains', '');
      if (saved) {
        this.availableDomains = (saved as string).split(',');
        Logger.info(TAG, `加载已保存的域名列表: ${this.availableDomains.length}个`);
      }

      // 加载当前域名
      const currentDomain = await this.preferences.get('currentDomain', '');
      if (currentDomain) {
        this.currentDomain = currentDomain as string;
      }

      // 检查是否需要更新
      const lastUpdate = await this.preferences.get('lastUpdateTime', 0) as number;
      if (Date.now() - lastUpdate > this.config.updateInterval) {
        await this.updateDomains();
      }
    } catch (error) {
      Logger.error(TAG, `初始化失败: ${error}`);
    }
  }

  /**
   * 获取当前域名
   */
  getCurrentDomain(): string {
    return this.currentDomain;
  }

  /**
   * 获取所有可用域名
   */
  getAvailableDomains(): string[] {
    return [...this.availableDomains];
  }

  /**
   * 从远程更新域名列表
   */
  async updateDomains(): Promise<string[]> {
    try {
      Logger.info(TAG, `开始更新域名列表: ${this.config.updateUrl}`);

      const httpRequest = http.createHttp();
      const response = await httpRequest.request(this.config.updateUrl, {
        method: http.RequestMethod.GET,
        expectDataType: http.HttpDataType.STRING
      });

      if (response.responseCode !== 200) {
        throw new Error(`HTTP ${response.responseCode}`);
      }

      const content = response.result as string;
      let newDomains: string[] = [];

      if (this.config.format === 'text') {
        newDomains = content
          .split(this.config.separator || ',')
          .map(d => d.trim())
          .filter(d => d.length > 0);
      } else {
        const json = JSON.parse(content);
        newDomains = json.domains || [];
      }

      if (newDomains.length > 0) {
        this.availableDomains = [...this.config.fallbackDomains, ...newDomains];
        this.lastUpdateTime = Date.now();

        // 保存到本地
        if (this.preferences) {
          await this.preferences.put('domains', this.availableDomains.join(','));
          await this.preferences.put('lastUpdateTime', this.lastUpdateTime);
          await this.preferences.flush();
        }

        Logger.info(TAG, `域名列表更新成功: ${this.availableDomains.length}个`);
      }

      return this.availableDomains;
    } catch (error) {
      Logger.error(TAG, `更新域名列表失败: ${error}`);
      return this.availableDomains;
    }
  }

  /**
   * 切换到指定域名
   */
  async switchDomain(domain: string): Promise<void> {
    if (!this.availableDomains.includes(domain)) {
      throw new Error(`域名不在可用列表中: ${domain}`);
    }

    this.currentDomain = domain;

    if (this.preferences) {
      await this.preferences.put('currentDomain', domain);
      await this.preferences.flush();
    }

    Logger.info(TAG, `已切换到域名: ${domain}`);
  }

  /**
   * 自动故障转移
   */
  async autoFailover(): Promise<string> {
    const currentIndex = this.availableDomains.indexOf(this.currentDomain);
    const nextIndex = (currentIndex + 1) % this.availableDomains.length;
    const nextDomain = this.availableDomains[nextIndex];

    await this.switchDomain(nextDomain);
    Logger.info(TAG, `自动故障转移: ${this.currentDomain} -> ${nextDomain}`);

    return nextDomain;
  }

  /**
   * 测试域名可用性
   */
  async testDomain(domain: string): Promise<boolean> {
    try {
      const httpRequest = http.createHttp();
      const response = await httpRequest.request(`https://${domain}`, {
        method: http.RequestMethod.GET,
        connectTimeout: 5000,
        readTimeout: 5000
      });

      return response.responseCode === 200;
    } catch (error) {
      Logger.error(TAG, `域名测试失败 ${domain}: ${error}`);
      return false;
    }
  }
}
```

---

## 4️⃣ 速率限制实现

### 4.1 速率限制器

**文件位置：** `entry/src/main/ets/network/RateLimiter.ets`

```typescript
import { Logger } from '../utils/Logger';

const TAG = 'RateLimiter';

interface RateLimitConfig {
  requests: number;
  period: number;  // 毫秒
  scope: 'global' | 'per-source';
}

interface RequestRecord {
  timestamp: number;
}

export class RateLimiter {
  private config: RateLimitConfig;
  private records: Map<string, RequestRecord[]>;

  constructor(config: RateLimitConfig) {
    this.config = config;
    this.records = new Map();
  }

  /**
   * 检查是否允许请求
   */
  canRequest(sourceId: string): boolean {
    const key = this.config.scope === 'global' ? 'global' : sourceId;
    const now = Date.now();
    const records = this.records.get(key) || [];

    // 清理过期记录
    const validRecords = records.filter(
      r => now - r.timestamp < this.config.period
    );

    return validRecords.length < this.config.requests;
  }

  /**
   * 记录请求
   */
  recordRequest(sourceId: string): void {
    const key = this.config.scope === 'global' ? 'global' : sourceId;
    const now = Date.now();
    const records = this.records.get(key) || [];

    // 清理过期记录
    const validRecords = records.filter(
      r => now - r.timestamp < this.config.period
    );

    // 添加新记录
    validRecords.push({ timestamp: now });
    this.records.set(key, validRecords);

    Logger.debug(TAG, `记录请求: ${key}, 当前: ${validRecords.length}/${this.config.requests}`);
  }

  /**
   * 等待直到可以请求
   */
  async waitForSlot(sourceId: string): Promise<void> {
    while (!this.canRequest(sourceId)) {
      const key = this.config.scope === 'global' ? 'global' : sourceId;
      const records = this.records.get(key) || [];
      
      if (records.length > 0) {
        const oldestRecord = records[0];
        const waitTime = this.config.period - (Date.now() - oldestRecord.timestamp);
        
        if (waitTime > 0) {
          Logger.info(TAG, `速率限制，等待 ${waitTime}ms`);
          await new Promise(resolve => setTimeout(resolve, waitTime));
        }
      }
    }
  }

  /**
   * 更新配置
   */
  updateConfig(config: Partial<RateLimitConfig>): void {
    this.config = { ...this.config, ...config };
    Logger.info(TAG, `速率限制配置已更新: ${JSON.stringify(this.config)}`);
  }
}

// 全局单例
export const rateLimiter = new RateLimiter({
  requests: 1,
  period: 3000,
  scope: 'per-source'
});
```

---

## 5️⃣ 测试方案

### 5.1 图片解扰测试

```typescript
// 测试用例
describe('ImageDescrambler', () => {
  it('应该正确计算MD5哈希', async () => {
    const descrambler = new JinmantiantangDescrambler(config);
    const hash = await descrambler['md5LastCharCode']('220980' + '00001');
    expect(hash).toBeGreaterThan(0);
  });

  it('应该正确计算分割行数', async () => {
    const descrambler = new JinmantiantangDescrambler(config);
    const rows = await descrambler['getRows'](220980, '00001');
    expect(rows).toBeGreaterThanOrEqual(2);
    expect(rows % 2).toBe(0);
  });

  it('应该正确解扰图片', async () => {
    // 加载测试图片
    const testImage = await loadTestImage('scrambled.jpg');
    const result = await descrambler.descrambleImage(testImage, 220980, '00001');
    expect(result.byteLength).toBeGreaterThan(0);
  });
});
```

### 5.2 域名管理测试

```typescript
describe('DomainManager', () => {
  it('应该正确加载域名列表', async () => {
    const manager = new DomainManager('jinmantiantang', config, '18comic.vip');
    await manager.initialize();
    const domains = manager.getAvailableDomains();
    expect(domains.length).toBeGreaterThan(0);
  });

  it('应该正确切换域名', async () => {
    await manager.switchDomain('18comic.ink');
    expect(manager.getCurrentDomain()).toBe('18comic.ink');
  });

  it('应该正确执行故障转移', async () => {
    const oldDomain = manager.getCurrentDomain();
    const newDomain = await manager.autoFailover();
    expect(newDomain).not.toBe(oldDomain);
  });
});
```

---

## 6️⃣ 性能优化建议

### 6.1 图片解扰优化

1. **使用缓存：** 解扰后的图片缓存到本地
2. **并行处理：** 使用 Worker 线程并行解扰多张图片
3. **内存管理：** 及时释放 PixelMap 资源
4. **预加载：** 提前解扰下一页图片

### 6.2 网络请求优化

1. **连接复用：** 使用 HTTP/2 或保持连接
2. **请求合并：** 批量获取章节信息
3. **智能重试：** 根据错误类型选择重试策略
4. **域名预热：** 提前测试备用域名

---

## 7️⃣ 部署清单

### 7.1 必须实现的功能

- [x] 图片解扰模块
- [x] Base64 解码模块
- [x] 动态域名管理
- [x] 速率限制
- [ ] 标签过滤
- [ ] 递归分页

### 7.2 配置文件

- [x] jinmantiantang.json
- [x] 图片解扰配置
- [x] 域名管理配置
- [x] 速率限制配置

### 7.3 文档

- [x] 实施指南
- [x] API 文档
- [ ] 用户手册
- [ ] 故障排除指南

---

**文档版本：** 1.0
**最后更新：** 2024-11-24
