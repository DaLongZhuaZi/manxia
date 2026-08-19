/**
 * WebDAV错误分析工具
 * 智能解析WebDAV错误，提供用户友好的解决建议
 * 
 * 文件路径: entry/src/main/ets/Framework/WebDAV/WebDAVErrorAnalyzer.ets
 */

import { logger } from 'manxia_core/src/main/ets/Utils/Logger';

const TAG = 'WebDAVErrorAnalyzer';

/**
 * WebDAV错误类型枚举
 */
export enum WebDAVErrorType {
  UNKNOWN = 'unknown',
  AUTH_FAILED = 'auth_failed',
  FORBIDDEN = 'forbidden',
  NOT_FOUND = 'not_found',
  METHOD_NOT_ALLOWED = 'method_not_allowed',
  CONFLICT = 'conflict',
  SSL_ERROR = 'ssl_error',
  NETWORK_ERROR = 'network_error',
  TIMEOUT = 'timeout',
  SERVER_ERROR = 'server_error',
  QUOTA_EXCEEDED = 'quota_exceeded',
  INVALID_URL = 'invalid_url',
  DIRECTORY_NOT_EXIST = 'directory_not_exist',
  CANNOT_CREATE_ROOT = 'cannot_create_root'
}

/**
 * 分析结果接口
 */
export interface WebDAVErrorAnalysis {
  errorType: WebDAVErrorType;
  title: string;
  description: string;
  suggestions: string[];
  canAutoFix: boolean;
  autoFixAction?: 'create_directory' | 'retry' | 'none';
  originalError: string;
}

/**
 * 常见WebDAV服务器配置信息
 */
export interface WebDAVServerGuide {
  name: string;
  urlFormat: string;
  example: string;
  notes: string[];
}

/**
 * 常见WebDAV服务器配置指南
 */
export const WEBDAV_SERVER_GUIDES: WebDAVServerGuide[] = [
  {
    name: '群晖 (Synology)',
    urlFormat: 'https://你的NAS地址:5006/目录名',
    example: 'https://192.168.1.100:5006 或 https://your.domain.com:5006',
    notes: [
      '确保在控制面板中启用了WebDAV服务',
      '默认HTTPS端口为5006，HTTP端口为5005',
      '建议使用HTTPS连接以保护数据安全',
      '需要在服务器上预先创建备份目录（如 /manxia）',
      '如使用自签名证书，应用会自动信任'
    ]
  },
  {
    name: '威联通 (QNAP)',
    urlFormat: 'https://你的NAS地址/share.cgi',
    example: 'https://192.168.1.100/share.cgi',
    notes: [
      '在控制面板 > 网络服务 > WebDAV 中启用',
      '使用标准HTTPS端口443',
      '需要在服务器上预先创建备份目录'
    ]
  },
  {
    name: 'Nextcloud',
    urlFormat: 'https://域名/remote.php/dav/files/用户名',
    example: 'https://cloud.example.com/remote.php/dav/files/admin',
    notes: [
      'WebDAV路径需要包含 /remote.php/dav/files/用户名',
      '用户名区分大小写',
      '可以使用应用密码代替主密码'
    ]
  },
  {
    name: 'ownCloud',
    urlFormat: 'https://域名/remote.php/webdav',
    example: 'https://owncloud.example.com/remote.php/webdav',
    notes: [
      'WebDAV路径为 /remote.php/webdav',
      '建议生成专用的应用密码'
    ]
  },
  {
    name: '坚果云',
    urlFormat: 'https://dav.jianguoyun.com/dav',
    example: 'https://dav.jianguoyun.com/dav',
    notes: [
      '需要在坚果云账户设置中生成应用密码',
      '不能使用登录密码，必须使用应用密码',
      '基础路径设置为您的文件夹路径，如 /我的坚果云/漫侠备份'
    ]
  },
  {
    name: 'Alist',
    urlFormat: 'https://你的Alist地址/dav',
    example: 'http://192.168.1.100:5244/dav',
    notes: [
      '确保Alist已启用WebDAV功能',
      '默认WebDAV路径为 /dav',
      '使用Alist的登录用户名和密码'
    ]
  },
  {
    name: 'Box',
    urlFormat: 'https://dav.box.com/dav',
    example: 'https://dav.box.com/dav',
    notes: [
      '使用Box账户的邮箱作为用户名',
      '可能需要使用应用专用密码'
    ]
  }
];

/**
 * WebDAV错误分析器
 */
export class WebDAVErrorAnalyzer {
  
  /**
   * 分析错误信息
   */
  static analyze(error: string | Error, statusCode?: number, basePath?: string): WebDAVErrorAnalysis {
    const errorStr = error instanceof Error ? error.message : String(error);
    const msg = errorStr.toLowerCase();
    const path = basePath || '/manxia';
    
    logger.info(TAG, `分析WebDAV错误: statusCode=${statusCode}, error=${errorStr}`);
    
    // 根据状态码优先判断
    if (statusCode) {
      return WebDAVErrorAnalyzer.analyzeByStatusCode(statusCode, errorStr, path);
    }
    
    // 根据错误信息判断
    return WebDAVErrorAnalyzer.analyzeByErrorMessage(msg, errorStr, path);
  }
  
  /**
   * 根据HTTP状态码分析错误
   */
  private static analyzeByStatusCode(statusCode: number, originalError: string, basePath: string): WebDAVErrorAnalysis {
    switch (statusCode) {
      case 401:
        return {
          errorType: WebDAVErrorType.AUTH_FAILED,
          title: '认证失败',
          description: '用户名或密码错误，服务器拒绝了您的登录请求。',
          suggestions: [
            '请检查用户名是否正确（注意大小写）',
            '请检查密码是否正确',
            '如使用坚果云等服务，需要使用"应用密码"而非登录密码',
            '如使用Nextcloud/ownCloud，可尝试生成专用的应用密码'
          ],
          canAutoFix: false,
          originalError
        };
        
      case 403:
        return {
          errorType: WebDAVErrorType.FORBIDDEN,
          title: '权限被拒绝',
          description: `服务器拒绝了访问请求。这通常是因为没有权限创建目录或访问指定路径。`,
          suggestions: [
            `⚠️ 大多数WebDAV服务器不允许直接在根目录创建文件夹`,
            `请在服务器上手动创建备份目录: "${basePath}"`,
            '确认您的账户有写入权限',
            '检查服务器是否限制了WebDAV访问范围',
            '如使用群晖NAS，请先在File Station中创建目录'
          ],
          canAutoFix: false,
          originalError
        };
        
      case 404:
        return {
          errorType: WebDAVErrorType.NOT_FOUND,
          title: '目录不存在',
          description: `指定的目录 "${basePath}" 在服务器上不存在。`,
          suggestions: [
            `请在WebDAV服务器上手动创建目录: "${basePath}"`,
            '或修改"基础路径"为服务器上已存在的目录',
            '确认服务器地址是否正确',
            '如使用Nextcloud，路径格式应为 /remote.php/dav/files/用户名'
          ],
          canAutoFix: true,
          autoFixAction: 'create_directory',
          originalError
        };
        
      case 405:
        return {
          errorType: WebDAVErrorType.METHOD_NOT_ALLOWED,
          title: '操作不支持',
          description: '服务器不支持此WebDAV操作，可能是服务器配置问题。',
          suggestions: [
            '确认服务器已启用完整的WebDAV支持（包括MKCOL、PUT等方法）',
            '检查服务器防火墙是否阻止了某些HTTP方法',
            '联系服务器管理员确认WebDAV配置'
          ],
          canAutoFix: false,
          originalError
        };
        
      case 409:
        return {
          errorType: WebDAVErrorType.CONFLICT,
          title: '冲突',
          description: '操作与服务器当前状态冲突，可能是父目录不存在或文件已被锁定。',
          suggestions: [
            '检查父目录是否存在',
            '稍后重试操作',
            '如果是上传冲突，可尝试删除服务器上的同名文件后重试'
          ],
          canAutoFix: false,
          originalError
        };
        
      case 507:
        return {
          errorType: WebDAVErrorType.QUOTA_EXCEEDED,
          title: '存储空间不足',
          description: '服务器存储空间已满，无法完成上传。',
          suggestions: [
            '清理服务器上的旧备份文件',
            '增加服务器存储空间',
            '减小备份文件大小（可在备份选项中排除部分数据）'
          ],
          canAutoFix: false,
          originalError
        };
        
      default:
        if (statusCode >= 500) {
          return {
            errorType: WebDAVErrorType.SERVER_ERROR,
            title: '服务器错误',
            description: `服务器返回错误 (${statusCode})，这通常是服务器端的问题。`,
            suggestions: [
              '稍后重试操作',
              '检查服务器状态和日志',
              '联系服务器管理员'
            ],
            canAutoFix: true,
            autoFixAction: 'retry',
            originalError
          };
        }
        return WebDAVErrorAnalyzer.createUnknownError(originalError);
    }
  }
  
  /**
   * 根据错误信息分析
   */
  private static analyzeByErrorMessage(msg: string, originalError: string, basePath: string): WebDAVErrorAnalysis {
    // SSL证书错误
    if (msg.includes('ssl') || msg.includes('certificate') || msg.includes('cert')) {
      return {
        errorType: WebDAVErrorType.SSL_ERROR,
        title: 'SSL证书错误',
        description: 'SSL/TLS证书验证失败。这可能是因为服务器使用了自签名证书。',
        suggestions: [
          '应用已尝试自动信任自签名证书',
          '如仍有问题，请检查服务器证书是否过期',
          '确认服务器地址是否正确（https而非http）',
          '可尝试更新设备时间以确保证书验证正常'
        ],
        canAutoFix: false,
        originalError
      };
    }
    
    // 连接超时
    if (msg.includes('timeout') || msg.includes('超时') || msg.includes('timed out')) {
      return {
        errorType: WebDAVErrorType.TIMEOUT,
        title: '连接超时',
        description: '连接服务器超时，服务器响应太慢或网络连接不稳定。',
        suggestions: [
          '检查网络连接是否正常',
          '确认服务器地址是否正确',
          '确认服务器是否在线运行',
          '如果服务器在内网，确保设备已连接到正确的网络',
          '尝试增加超时时间或稍后重试'
        ],
        canAutoFix: true,
        autoFixAction: 'retry',
        originalError
      };
    }
    
    // 网络连接错误
    if (msg.includes('connect') || msg.includes('network') || msg.includes('unable to resolve') || 
        msg.includes('host') || msg.includes('unreachable')) {
      return {
        errorType: WebDAVErrorType.NETWORK_ERROR,
        title: '网络连接失败',
        description: '无法连接到服务器，请检查网络和服务器状态。',
        suggestions: [
          '检查设备网络连接',
          '确认服务器地址格式正确（包含协议如 https://）',
          '确认端口号正确（群晖默认5006，标准HTTPS为443）',
          '如服务器在内网，确保设备已连接到同一网络',
          '检查服务器是否在线'
        ],
        canAutoFix: false,
        originalError
      };
    }
    
    // URL格式错误
    if (msg.includes('invalid url') || msg.includes('malformed') || msg.includes('url格式')) {
      return {
        errorType: WebDAVErrorType.INVALID_URL,
        title: '地址格式错误',
        description: '服务器地址格式不正确，请按正确格式输入。',
        suggestions: [
          '确保地址以 http:// 或 https:// 开头',
          '检查是否有多余的空格或特殊字符',
          '端口号应使用冒号分隔，如 :5006',
          '参考示例：https://192.168.1.100:5006'
        ],
        canAutoFix: false,
        originalError
      };
    }
    
    // 403相关
    if (msg.includes('403') || msg.includes('forbidden') || msg.includes('permission denied')) {
      return WebDAVErrorAnalyzer.analyzeByStatusCode(403, originalError, basePath);
    }
    
    // 401相关
    if (msg.includes('401') || msg.includes('unauthorized') || msg.includes('authentication')) {
      return WebDAVErrorAnalyzer.analyzeByStatusCode(401, originalError, basePath);
    }
    
    // 404相关
    if (msg.includes('404') || msg.includes('not found')) {
      return WebDAVErrorAnalyzer.analyzeByStatusCode(404, originalError, basePath);
    }
    
    return WebDAVErrorAnalyzer.createUnknownError(originalError);
  }
  
  /**
   * 创建未知错误分析结果
   */
  private static createUnknownError(originalError: string): WebDAVErrorAnalysis {
    return {
      errorType: WebDAVErrorType.UNKNOWN,
      title: '未知错误',
      description: '发生了未知错误，请查看详细信息。',
      suggestions: [
        '检查服务器地址、用户名和密码是否正确',
        '确认服务器WebDAV服务已启用',
        '检查网络连接',
        '稍后重试或联系技术支持'
      ],
      canAutoFix: false,
      originalError
    };
  }
  
  /**
   * 生成用户友好的错误信息
   */
  static formatErrorForUser(analysis: WebDAVErrorAnalysis): string {
    let message = `❌ ${analysis.title}\n\n`;
    message += `${analysis.description}\n\n`;
    message += `💡 建议：\n`;
    analysis.suggestions.forEach((suggestion, index) => {
      message += `${index + 1}. ${suggestion}\n`;
    });
    return message;
  }
  
  /**
   * 生成简短的错误提示（用于Toast）
   */
  static formatShortError(analysis: WebDAVErrorAnalysis): string {
    return `${analysis.title}: ${analysis.suggestions[0]}`;
  }
  
  /**
   * 获取指定服务器类型的配置指南
   */
  static getServerGuide(serverType: string): WebDAVServerGuide | undefined {
    const typeLower = serverType.toLowerCase();
    return WEBDAV_SERVER_GUIDES.find(guide => 
      guide.name.toLowerCase().includes(typeLower) || 
      typeLower.includes(guide.name.toLowerCase().split(' ')[0])
    );
  }
  
  /**
   * 获取所有服务器配置指南
   */
  static getAllServerGuides(): WebDAVServerGuide[] {
    return WEBDAV_SERVER_GUIDES;
  }
  
  /**
   * 检测服务器URL可能是哪种类型
   */
  static detectServerType(url: string): string {
    const urlLower = url.toLowerCase();
    
    if (urlLower.includes('jianguoyun') || urlLower.includes('nutstore')) {
      return '坚果云';
    }
    if (urlLower.includes('nextcloud') || urlLower.includes('remote.php/dav/files')) {
      return 'Nextcloud';
    }
    if (urlLower.includes('owncloud') || urlLower.includes('remote.php/webdav')) {
      return 'ownCloud';
    }
    if (urlLower.includes('box.com')) {
      return 'Box';
    }
    if (urlLower.includes(':5006') || urlLower.includes(':5005')) {
      return '群晖 (Synology)';
    }
    if (urlLower.includes('share.cgi')) {
      return '威联通 (QNAP)';
    }
    if (urlLower.includes(':5244') || urlLower.includes('/dav')) {
      return 'Alist';
    }
    
    return '通用WebDAV';
  }
}

/**
 * 便捷函数：分析错误并返回用户友好的信息
 */
export function analyzeWebDAVError(error: string | Error, statusCode?: number, basePath?: string): string {
  const analysis = WebDAVErrorAnalyzer.analyze(error, statusCode, basePath);
  return WebDAVErrorAnalyzer.formatErrorForUser(analysis);
}

/**
 * 便捷函数：获取简短错误提示
 */
export function getShortWebDAVError(error: string | Error, statusCode?: number, basePath?: string): string {
  const analysis = WebDAVErrorAnalyzer.analyze(error, statusCode, basePath);
  return WebDAVErrorAnalyzer.formatShortError(analysis);
}
