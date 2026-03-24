/**
 * Share Extension Ability
 * 用于接收其他应用通过系统分享功能分享的文件
 * 实现最快速便捷的漫画导入流程
 */

import { UIExtensionAbility, UIExtensionContentSession, Want } from '@kit.AbilityKit';
import { window } from '@kit.ArkUI';
import { fileUri } from '@kit.CoreFileKit';
import { logger } from '../Utils/Logger';

const TAG = 'ShareExtAbility';
// 应用包名（与AppScope/app.json5中的bundleName保持一致）
const APP_BUNDLE_NAME = 'com.dlzz.manxia';

export default class ShareExtAbility extends UIExtensionAbility {
  
  onCreate(): void {
    logger.lifecycle(TAG, 'ShareExtAbility onCreate');
  }

  onSessionCreate(want: Want, session: UIExtensionContentSession): void {
    logger.lifecycle(TAG, 'ShareExtAbility onSessionCreate');
    
    try {
      // 获取分享的文件URI
      const sharedUris = this.extractSharedUris(want);
      
      if (sharedUris.length === 0) {
        logger.warn(TAG, '未找到分享的文件URI');
        return;
      }
      
      logger.info(TAG, `接收到 ${sharedUris.length} 个分享文件`);
      sharedUris.forEach((uri: string, index: number) => {
        logger.info(TAG, `文件 ${index + 1}: ${uri}`);
      });
      
      // 处理分享的文件
      this.handleSharedFiles(sharedUris, session);
      
    } catch (error) {
      logger.error(TAG, '处理分享文件失败', String(error));
    }
  }

  /**
   * 从Want中提取分享的文件URI列表
   */
  private extractSharedUris(want: Want): string[] {
    const uris: string[] = [];
    
    try {
      // 尝试从parameters中获取URI
      if (want.parameters) {
        // 单个文件：uri字段
        if (want.parameters['uri']) {
          const uri = String(want.parameters['uri']);
          logger.info(TAG, `从parameters.uri获取到文件: ${uri}`);
          uris.push(uri);
        }
        
        // 多个文件：uris数组
        if (want.parameters['uris']) {
          const urisArray = want.parameters['uris'] as string[];
          if (Array.isArray(urisArray)) {
            logger.info(TAG, `从parameters.uris获取到 ${urisArray.length} 个文件`);
            uris.push(...urisArray);
          }
        }
        
        // 尝试从ability.params获取（某些应用使用的字段）
        if (want.parameters['ability.params.stream']) {
          const streamUri = String(want.parameters['ability.params.stream']);
          logger.info(TAG, `从ability.params.stream获取到文件: ${streamUri}`);
          uris.push(streamUri);
        }
      }
      
      // 尝试从uri字段获取
      if (want.uri && !uris.includes(want.uri)) {
        logger.info(TAG, `从want.uri获取到文件: ${want.uri}`);
        uris.push(want.uri);
      }
      
    } catch (error) {
      logger.error(TAG, '提取URI失败', String(error));
    }
    
    return uris;
  }

  /**
   * 处理分享的文件
   */
  private async handleSharedFiles(uris: string[], session: UIExtensionContentSession): Promise<void> {
    try {
      // 验证和转换文件URI
      const validUris: string[] = [];
      
      for (const uri of uris) {
        try {
          // 转换为标准文件URI格式
          const normalizedUri = this.normalizeFileUri(uri);
          
          // 验证文件类型
          const fileType = this.getFileType(normalizedUri);
          if (fileType !== 'unknown') {
            validUris.push(normalizedUri);
            logger.info(TAG, `✅ 有效的${fileType}文件: ${normalizedUri}`);
          } else {
            logger.warn(TAG, `⚠️ 不支持的文件类型: ${normalizedUri}`);
          }
        } catch (error) {
          logger.error(TAG, `处理URI失败: ${uri}`, String(error));
        }
      }
      
      if (validUris.length === 0) {
        logger.warn(TAG, '没有找到有效的文件');
        // 通知用户
        this.showToast('未找到支持的文件类型', session);
        return;
      }
      
      // 确定文件类型
      const firstFileType = this.getFileType(validUris[0]);
      
      // 启动主应用并传递文件URI
      await this.launchMainAppWithFiles(validUris, firstFileType);
      
      // 显示成功提示
      this.showToast(`正在导入 ${validUris.length} 个文件...`, session);
      
      // 延迟关闭分享界面
      setTimeout(() => {
        this.context.terminateSelf();
      }, 1000);
      
    } catch (error) {
      logger.error(TAG, '处理分享文件失败', String(error));
      this.showToast('文件导入失败', session);
    }
  }

  /**
   * 标准化文件URI
   */
  private normalizeFileUri(uri: string): string {
    try {
      // 如果URI已经是file://格式，直接返回
      if (uri.startsWith('file://')) {
        return uri;
      }
      
      // 如果URI是content://格式，尝试转换
      if (uri.startsWith('content://')) {
        logger.info(TAG, `转换content URI: ${uri}`);
        // HarmonyOS可以直接使用content URI
        return uri;
      }
      
      // 如果是纯路径，添加file://前缀
      if (uri.startsWith('/')) {
        return `file://${uri}`;
      }
      
      // 尝试使用fileUri模块获取URI字符串
      try {
        const fileUriObj = fileUri.getUriFromPath(uri);
        logger.info(TAG, `使用fileUri转换: ${uri} -> ${fileUriObj}`);
        return fileUriObj;
      } catch (e) {
        logger.warn(TAG, `fileUri转换失败，使用原URI: ${uri}`);
        return uri;
      }
      
    } catch (error) {
      logger.error(TAG, 'URI标准化失败', String(error));
      return uri;
    }
  }

  /**
   * 获取文件类型
   */
  private getFileType(uri: string): string {
    const lowerUri = uri.toLowerCase();
    
    // 漫画压缩包
    if (lowerUri.endsWith('.zip') || lowerUri.endsWith('.cbz') ||
        lowerUri.endsWith('.cbr') || lowerUri.endsWith('.rar') ||
        lowerUri.endsWith('.7z') || lowerUri.endsWith('.tar') ||
        lowerUri.endsWith('.gz') || lowerUri.endsWith('.tgz') ||
        lowerUri.endsWith('.bz2') || lowerUri.endsWith('.xz') ||
        lowerUri.endsWith('.lzma') ||
        lowerUri.includes('.zip?') || lowerUri.includes('.cbz?') ||
        lowerUri.includes('.cbr?') || lowerUri.includes('.rar?') ||
        lowerUri.includes('.7z?') || lowerUri.includes('.tar?') ||
        lowerUri.includes('.gz?') || lowerUri.includes('.tgz?') ||
        lowerUri.includes('.bz2?') || lowerUri.includes('.xz?') ||
        lowerUri.includes('.lzma?')) {
      return 'comic';
    }
    
    // AVIF图片
    if (lowerUri.endsWith('.avif') || lowerUri.includes('.avif?')) {
      return 'avif';
    }
    
    // 其他图片
    if (lowerUri.endsWith('.jpg') || lowerUri.endsWith('.jpeg') || 
        lowerUri.endsWith('.png') || lowerUri.endsWith('.gif') ||
        lowerUri.endsWith('.webp') || lowerUri.endsWith('.bmp')) {
      return 'image';
    }
    
    // PDF
    if (lowerUri.endsWith('.pdf') || lowerUri.includes('.pdf?')) {
      return 'pdf';
    }
    
    // 电子书
    if (lowerUri.endsWith('.epub') || lowerUri.endsWith('.mobi') || 
        lowerUri.endsWith('.azw3') || lowerUri.endsWith('.txt')) {
      return 'ebook';
    }
    
    // 备份文件
    if (lowerUri.endsWith('.mxbackup') || lowerUri.endsWith('.mxbak')) {
      return 'backup';
    }
    
    return 'unknown';
  }

  /**
   * 启动主应用并传递文件URI
   */
  private async launchMainAppWithFiles(uris: string[], fileType: string): Promise<void> {
    try {
      // 使用应用包名常量 - ShareExtAbility和EntryAbility在同一应用包中
      // 直接使用常量避免any/unknown类型问题和ApplicationInfo属性不存在的问题
      const want: Want = {
        bundleName: APP_BUNDLE_NAME,
        abilityName: 'EntryAbility',
        parameters: {
          'share_import_files': uris,
          'share_import_type': fileType,
          'share_import_source': 'system_share'
        }
      };
      
      logger.info(TAG, `启动主应用，传递 ${uris.length} 个文件，bundleName: ${APP_BUNDLE_NAME}`);
      await this.context.startAbility(want);
      
    } catch (error) {
      const errorMsg = error instanceof Error ? error.message : String(error);
      logger.error(TAG, '启动主应用失败', errorMsg);
      throw new Error(`启动主应用失败: ${errorMsg}`);
    }
  }

  /**
   * 显示Toast提示
   */
  private showToast(message: string, session: UIExtensionContentSession): void {
    try {
      logger.info(TAG, `Toast: ${message}`);
      // 注意：在ShareExtensionAbility中，Toast显示需要特殊处理
      // 这里记录日志，实际提示会在主应用中显示
    } catch (error) {
      logger.error(TAG, '显示Toast失败', String(error));
    }
  }

  onSessionDestroy(session: UIExtensionContentSession): void {
    logger.lifecycle(TAG, 'ShareExtAbility onSessionDestroy');
  }

  onForeground(): void {
    logger.lifecycle(TAG, 'ShareExtAbility onForeground');
  }

  onBackground(): void {
    logger.lifecycle(TAG, 'ShareExtAbility onBackground');
  }

  onDestroy(): void {
    logger.lifecycle(TAG, 'ShareExtAbility onDestroy');
  }
}

