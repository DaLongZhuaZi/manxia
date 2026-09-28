import { LegadoJsApiStatus } from './LegadoCompatibilityTypes';

export class LegadoJsApiContract {
  readonly api: string;
  readonly status: LegadoJsApiStatus;
  readonly detail: string;

  constructor(api: string, status: LegadoJsApiStatus, detail: string) {
    this.api = api;
    this.status = status;
    this.detail = detail;
  }
}

export class LegadoJsApiAssessment {
  readonly contracts: LegadoJsApiContract[];
  readonly hasBlockingContract: boolean;
  readonly blockingStatus: LegadoJsApiStatus | null;

  constructor(
    contracts: LegadoJsApiContract[],
    hasBlockingContract: boolean,
    blockingStatus: LegadoJsApiStatus | null
  ) {
    this.contracts = contracts;
    this.hasBlockingContract = hasBlockingContract;
    this.blockingStatus = blockingStatus;
  }
}

/**
 * A script is never treated as compatible just because a same-named function
 * exists.  This registry is the single source of truth for V2 diagnostics.
 */
export class LegadoJsApiContractRegistry {
  private readonly contracts: LegadoJsApiContract[] = [];

  constructor() {
    this.registerDefaults();
  }

  getContract(api: string): LegadoJsApiContract | null {
    for (let i = 0; i < this.contracts.length; i++) {
      if (this.contracts[i].api === api) {
        return this.contracts[i];
      }
    }
    return null;
  }

  getAllContracts(): LegadoJsApiContract[] {
    return this.contracts.slice();
  }

  assess(code: string): LegadoJsApiAssessment {
    const matched: LegadoJsApiContract[] = [];
    const executableCode = this.maskNonExecutableText(code);
    const apiReferences = this.collectApiReferences(executableCode.replace(/\s+/g, ''));
    for (let i = 0; i < apiReferences.length; i++) {
      const api = apiReferences[i];
      const contract = this.resolveContract(api);
      if (contract !== null) {
        matched.push(contract);
      } else {
        matched.push(new LegadoJsApiContract(
          api,
          LegadoJsApiStatus.UNSUPPORTED_API,
          '该 JavaScript API 未在 V2 契约注册表中声明。'
        ));
      }
    }
    let blockingStatus: LegadoJsApiStatus | null = null;
    for (let i = 0; i < matched.length; i++) {
      const status = matched[i].status;
      if (status === LegadoJsApiStatus.UNSUPPORTED_API ||
        status === LegadoJsApiStatus.NEEDS_INTERACTION ||
        status === LegadoJsApiStatus.POLICY_BLOCKED) {
        blockingStatus = status;
        break;
      }
    }
    return new LegadoJsApiAssessment(matched, blockingStatus !== null, blockingStatus);
  }

  private registerDefaults(): void {
    this.add('java.ajax', LegadoJsApiStatus.SUPPORTED, '统一 RequestSpec/ResponseEnvelope 网络契约');
    this.add('java.ajaxAll', LegadoJsApiStatus.SUPPORTED, '批量网络请求由运行时处理');
    this.add('java.connect', LegadoJsApiStatus.SUPPORTED, '同步响应对象兼容层');
    this.add('java.log', LegadoJsApiStatus.SUPPORTED, '规则日志由 V2 运行时采集并脱敏输出');
    this.add('java.toast', LegadoJsApiStatus.SUPPORTED, '规则短提示由 V2 运行时安全呈现');
    this.add('java.longToast', LegadoJsApiStatus.SUPPORTED, '规则提示由 V2 运行时安全呈现');
    this.add('java.put', LegadoJsApiStatus.SUPPORTED, '当前规则变量作用域与副作用回传');
    this.add('source.getVariable', LegadoJsApiStatus.SUPPORTED, '书源变量作用域');
    this.add('source.key', LegadoJsApiStatus.SUPPORTED, '当前书源标识作用域');
    this.add('source.setVariable', LegadoJsApiStatus.SUPPORTED, '书源变量持久化作用域');
    this.add('source.getKey', LegadoJsApiStatus.SUPPORTED, '书源标识作用域');
    this.add('source.bookSourceUrl', LegadoJsApiStatus.SUPPORTED, '当前书源 URL 只读字段');
    this.add('source.bookSourceName', LegadoJsApiStatus.SUPPORTED, '当前书源名称只读字段');
    this.add('source.bookSourceGroup', LegadoJsApiStatus.SUPPORTED, '当前书源分组只读字段');
    this.add('source.bookSourceComment', LegadoJsApiStatus.SUPPORTED, '当前书源备注只读字段');
    this.add('source.bookSourceType', LegadoJsApiStatus.SUPPORTED, '当前书源类型只读字段');
    this.add('source.loginUrl', LegadoJsApiStatus.SUPPORTED, '当前书源登录地址只读字段');
    this.add('source.loginUi', LegadoJsApiStatus.SUPPORTED, '当前书源登录界面配置只读字段');
    this.add('source.loginCheckJs', LegadoJsApiStatus.SUPPORTED, '当前书源登录检查脚本只读字段');
    this.add('source.header', LegadoJsApiStatus.SUPPORTED, '当前书源 Header 配置只读字段');
    this.add('source.variableComment', LegadoJsApiStatus.SUPPORTED, '当前书源变量说明只读字段');
    this.add('source.get', LegadoJsApiStatus.SUPPORTED, '书源数据作用域');
    this.add('source.put', LegadoJsApiStatus.SUPPORTED, '书源数据作用域');
    this.add('source.getLoginInfo', LegadoJsApiStatus.SUPPORTED, '已登录会话读取');
    this.add('source.getLoginInfoMap', LegadoJsApiStatus.SUPPORTED, '已登录会话读取');
    this.add('source.getLoginHeader', LegadoJsApiStatus.SUPPORTED, '已登录会话读取');
    this.add('source.getLoginHeaderMap', LegadoJsApiStatus.SUPPORTED, '已登录会话读取');
    this.add('source.getHeaderMap', LegadoJsApiStatus.SUPPORTED, '书源请求头读取');
    this.add('source.putLoginInfo', LegadoJsApiStatus.NEEDS_INTERACTION, '登录状态写入需要用户已完成认证');
    this.add('source.putLoginHeader', LegadoJsApiStatus.NEEDS_INTERACTION, '登录状态写入需要用户已完成认证');
    this.add('source.removeLoginHeader', LegadoJsApiStatus.NEEDS_INTERACTION, '登录状态修改需要用户确认');
    this.add('java.getElement', LegadoJsApiStatus.SUPPORTED, 'DOM 查询兼容层');
    this.add('java.getElements', LegadoJsApiStatus.SUPPORTED, 'DOM 列表查询兼容层');
    this.add('java.base64Encode', LegadoJsApiStatus.SUPPORTED, 'UTF-8 Base64 编码工具');
    this.add('java.base64Decode', LegadoJsApiStatus.SUPPORTED, 'UTF-8 Base64 解码工具');
    this.add('java.base64DecodeToByteArray', LegadoJsApiStatus.SUPPORTED, 'Base64 二进制解码工具');
    this.add('java.md5Encode', LegadoJsApiStatus.SUPPORTED, 'MD5 摘要工具');
    this.add('java.md5Encode16', LegadoJsApiStatus.SUPPORTED, '16 位 MD5 摘要工具');
    this.add('java.sha1Encode', LegadoJsApiStatus.SUPPORTED, 'SHA-1 摘要工具');
    this.add('java.sha256Encode', LegadoJsApiStatus.SUPPORTED, 'SHA-256 摘要工具');
    this.add('java.HMacHex', LegadoJsApiStatus.SUPPORTED,
      '原版 HMacHex(data, algorithm, key) 标准 HMAC 桥接，失败显式返回 CRYPTO_HMAC_FAILED');
    this.add('java.timeFormat', LegadoJsApiStatus.SUPPORTED,
      '原版 dateFormat（yyyy/MM/dd HH:mm）本地时间格式化，不依赖设备语言');
    this.add('java.timeFormatUTC', LegadoJsApiStatus.SUPPORTED, '固定时区时间格式化');
    this.add('java.t2s', LegadoJsApiStatus.SUPPORTED, '繁体到简体转换兼容层');
    this.add('java.s2t', LegadoJsApiStatus.SUPPORTED, '简体到繁体转换兼容层，复用默认 ArkWeb runtime 的 ChineseUtils.s2t 映射边界');
    this.add('java.hexDecodeToString', LegadoJsApiStatus.SUPPORTED, '十六进制 UTF-8 文本解码兼容层');
    this.add('java.getStringList', LegadoJsApiStatus.SUPPORTED, '规则列表提取兼容层');
    this.add('java.toNumChapter', LegadoJsApiStatus.SUPPORTED, '章节序号转换与原版 StringUtils 语义一致');
    this.add('java.getCookie', LegadoJsApiStatus.SUPPORTED, '书源 Cookie 作用域');
    this.add('java.setCookie', LegadoJsApiStatus.SUPPORTED, '书源 Cookie 作用域');
    this.add('java.get', LegadoJsApiStatus.SUPPORTED,
      '规则变量读取与受控 GET 请求桥接');
    this.add('java.getString', LegadoJsApiStatus.SUPPORTED, '文本网络响应兼容层');
    this.add('java.encodeURI', LegadoJsApiStatus.SUPPORTED, 'Legado 表单编码兼容层');
    this.add('java.post', LegadoJsApiStatus.SUPPORTED, '统一 POST RequestSpec/ResponseEnvelope 网络契约');
    this.add('java.setContent', LegadoJsApiStatus.SUPPORTED, '当前规则内容上下文写入');
    this.add('java.getWebViewUA', LegadoJsApiStatus.SUPPORTED, 'ArkWeb User-Agent 读取');
    this.add('java.webView', LegadoJsApiStatus.UNSUPPORTED_API,
      '原版后台 WebView 嵌套执行尚未映射到 V2 bridge；禁止静默返回空字符串');
    this.add('java.webViewGetSource', LegadoJsApiStatus.UNSUPPORTED_API,
      '原版后台 WebView 资源拦截尚未映射到 V2 bridge；禁止静默返回空字符串');
    this.add('java.webViewGetOverrideUrl', LegadoJsApiStatus.UNSUPPORTED_API,
      '原版后台 WebView 跳转捕获尚未映射到 V2 bridge；禁止静默返回空字符串');
    this.add('java.aesBase64DecodeToString', LegadoJsApiStatus.SUPPORTED,
      '已在真机验证 AES ECB/CBC、PKCS5/PKCS7 与 UTF-8 decryptStr 包装；失败保留 CRYPTO_SYMMETRIC_FAILED。');
    this.add('java.desEncodeToBase64String', LegadoJsApiStatus.SUPPORTED,
      '已在真机验证 DES64 ECB PKCS5/PKCS7 的 Base64 旧 API 包装。');
    this.add('java.createSymmetricCrypto', LegadoJsApiStatus.SUPPORTED,
      '受限支持 AES、DES64、3DES192（DESede/3DES）的 ECB/CBC、NoPadding/PKCS5/PKCS7、UTF-8 key/iv 与 encrypt/decrypt 包装；其他 transformation、非法 key/iv 或 provider 失败显式 CRYPTO_SYMMETRIC_FAILED。');
    this.add('java.randomUUID', LegadoJsApiStatus.SUPPORTED,
      '原版 JsExtensions.randomUUID 的 UUID 字符串契约，由 ArkWeb runtime 生成并验证 toString 语义。');
    this.add('java.util.UUID.randomUUID', LegadoJsApiStatus.SUPPORTED,
      'JavaImporter 注入的 UUID.randomUUID 兼容入口；返回仅暴露 toString() 的 UUID 包装并复用 randomUUID 字符串契约。');
    // JavaImporter imports these namespaces in a large class of real Legado
    // sources (notably encrypted content sources).  The runtime exposes a
    // deliberately bounded subset: System/String, Arrays/Base64/UUID and
    // Cipher/SecretKeySpec/IvParameterSpec.  Rejecting the package names
    // themselves made otherwise executable sources fail before dispatch.
    this.add('java.lang', LegadoJsApiStatus.SUPPORTED,
      'JavaImporter java.lang 的受控 System/String 子集；未知类仍由运行时显式报错。');
    this.add('java.util', LegadoJsApiStatus.SUPPORTED,
      'JavaImporter java.util 的受控 Arrays/UUID 子集；未知类仍由运行时显式报错。');
    this.add('javax.crypto', LegadoJsApiStatus.SUPPORTED,
      'JavaImporter javax.crypto 的受控 Cipher 子集，使用 V2 CryptoJS 同步适配。');
    this.add('javax.crypto.spec', LegadoJsApiStatus.SUPPORTED,
      'JavaImporter javax.crypto.spec 的受控 SecretKeySpec/IvParameterSpec 子集。');
    this.add('java.lang.System.currentTimeMillis', LegadoJsApiStatus.SUPPORTED,
      'ArkWeb 运行时受控时钟桥接');
    this.add('java.lang.System.err.println', LegadoJsApiStatus.SUPPORTED,
      '规则错误日志由 V2 运行时脱敏采集');
    this.add('java.lang.String', LegadoJsApiStatus.SUPPORTED,
      'UTF-8 字节数组兼容包装器');
    this.add('android.util.Base64.encodeToString', LegadoJsApiStatus.SUPPORTED,
      'Android Base64 NO_WRAP 编码兼容层');
    this.add('android.util.Base64.NO_WRAP', LegadoJsApiStatus.SUPPORTED,
      'Android Base64 无换行标志兼容常量');
    this.add('org.jsoup.Jsoup.parse', LegadoJsApiStatus.SUPPORTED,
      'ArkWeb DOM 文档解析兼容层');
    this.add('java.getByteArray', LegadoJsApiStatus.UNSUPPORTED_API, '二进制响应需通过 File/Binary 工作流');
    this.add('java.getInputStream', LegadoJsApiStatus.UNSUPPORTED_API, '输入流尚未映射到 ArkTS 二进制契约');
    this.add('java.encrypt', LegadoJsApiStatus.UNSUPPORTED_API, '加密算法需要按 API 单独验收');
    this.add('java.decrypt', LegadoJsApiStatus.UNSUPPORTED_API, '解密算法需要按 API 单独验收');
    this.add('java.startBrowser', LegadoJsApiStatus.NEEDS_INTERACTION, '浏览器流程必须由用户完成');
    this.add('java.startBrowserAwait', LegadoJsApiStatus.NEEDS_INTERACTION, '浏览器流程必须由用户完成');
    this.add('java.getVerificationCode', LegadoJsApiStatus.NEEDS_INTERACTION, '验证码不自动绕过');
    this.add('java.download', LegadoJsApiStatus.POLICY_BLOCKED, '文件下载必须走 V2 File 工作流');
    this.add('java.imageDecode', LegadoJsApiStatus.POLICY_BLOCKED, '图片解码必须走 V2 二进制解码工作流');
  }

  private add(api: string, status: LegadoJsApiStatus, detail: string): void {
    this.contracts.push(new LegadoJsApiContract(api, status, detail));
  }

  /**
   * A JavaScript member access can continue after an injected API value, for
   * example `source.bookSourceName.includes(...)`.  The Java bridge contract
   * is `source.bookSourceName`; `includes` belongs to the returned string and
   * must not be reclassified as a missing Legado API.  Resolve only to an
   * explicitly registered ancestor, never to a namespace such as `java` or
   * `source`, so unknown bridge APIs remain structured blockers.
   */
  private resolveContract(api: string): LegadoJsApiContract | null {
    let candidate = api;
    while (candidate.includes('.')) {
      const contract = this.getContract(candidate);
      if (contract !== null) {
        return contract;
      }
      const separator = candidate.lastIndexOf('.');
      if (separator <= 0) {
        break;
      }
      candidate = candidate.substring(0, separator);
    }
    return null;
  }

  /**
   * Extract complete, concrete Java bridge paths before comparing them with
   * the contract registry. The former two-segment matcher reduced
   * `java.lang.String` to `java.lang`, so a supported Rhino-compatible call
   * was rejected before the ArkWeb runtime could execute it. `Packages.` is
   * canonicalized instead of being trusted as a blanket Java escape hatch.
   */
  private collectApiReferences(code: string): string[] {
    const references: string[] = [];
    const apiPattern = /(?:Packages\.)?(?:java|source|android|javax|org)\.[A-Za-z_$][A-Za-z0-9_$]*(?:\.[A-Za-z_$][A-Za-z0-9_$]*)*/g;
    const matches = code.match(apiPattern);
    if (!matches) {
      return references;
    }
    for (let i = 0; i < matches.length; i++) {
      let api = matches[i];
      if (api.startsWith('Packages.')) {
        api = api.substring('Packages.'.length);
      }
      if (!this.containsReference(references, api)) {
        references.push(api);
      }
    }
    return references;
  }

  /**
   * The compiler receives complete Legado rule text, not a JavaScript AST.
   * Mask strings, comments and URL literals before namespace scanning so a
   * normal endpoint such as `https://host/android.php` cannot become a fake
   * `android.php` API. Template interpolation is deliberately retained: code
   * inside `${...}` still has to pass the same contract gate.
   */
  private maskNonExecutableText(code: string): string {
    const urlMasked = code.replace(/https?:\/\/[^\s'"`\\<>{}]+/g, (value: string): string => {
      return ' '.repeat(value.length);
    });
    let result = '';
    let mode = 0;
    let escaped = false;
    let templateExpressionDepth = 0;
    let returnToTemplate = false;
    for (let index = 0; index < urlMasked.length; index++) {
      const character = urlMasked.charAt(index);
      const next = index + 1 < urlMasked.length ? urlMasked.charAt(index + 1) : '';
      if (mode === 1 || mode === 2) {
        result += character === '\n' ? '\n' : ' ';
        if (escaped) {
          escaped = false;
        } else if (character === '\\') {
          escaped = true;
        } else if ((mode === 1 && character === "'") || (mode === 2 && character === '"')) {
          mode = 0;
        }
        continue;
      }
      if (mode === 3) {
        if (character === '`') {
          result += ' ';
          mode = 0;
          returnToTemplate = false;
          templateExpressionDepth = 0;
        } else if (character === '$' && next === '{') {
          result += '  ';
          index++;
          mode = 0;
          returnToTemplate = true;
          templateExpressionDepth = 1;
        } else {
          result += character === '\n' ? '\n' : ' ';
        }
        continue;
      }
      if (mode === 4) {
        result += character === '\n' ? '\n' : ' ';
        if (character === '\n') {
          mode = 0;
        }
        continue;
      }
      if (mode === 5) {
        result += character === '\n' ? '\n' : ' ';
        if (character === '*' && next === '/') {
          result += ' ';
          index++;
          mode = 0;
        }
        continue;
      }
      if (character === "'") {
        result += ' ';
        mode = 1;
        escaped = false;
        continue;
      }
      if (character === '"') {
        result += ' ';
        mode = 2;
        escaped = false;
        continue;
      }
      if (character === '`') {
        result += ' ';
        mode = 3;
        continue;
      }
      if (character === '/' && next === '/') {
        result += '  ';
        index++;
        mode = 4;
        continue;
      }
      if (character === '/' && next === '*') {
        result += '  ';
        index++;
        mode = 5;
        continue;
      }
      if (returnToTemplate && character === '{') {
        templateExpressionDepth++;
      } else if (returnToTemplate && character === '}') {
        templateExpressionDepth--;
        if (templateExpressionDepth === 0) {
          result += ' ';
          mode = 3;
          continue;
        }
      }
      result += character;
    }
    return result;
  }

  private containsReference(references: string[], api: string): boolean {
    for (let i = 0; i < references.length; i++) {
      if (references[i] === api) {
        return true;
      }
    }
    return false;
  }
}

let registry: LegadoJsApiContractRegistry | null = null;

export function getLegadoJsApiContractRegistry(): LegadoJsApiContractRegistry {
  if (registry === null) {
    registry = new LegadoJsApiContractRegistry();
  }
  return registry;
}
