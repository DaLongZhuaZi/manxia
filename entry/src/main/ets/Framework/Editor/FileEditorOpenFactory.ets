import {
  fileEditorService,
  FileEditorOpenParams
} from './FileEditorService';

/**
 * 文件编辑器打开参数工厂
 * 确保每次打开都带有独立实例标识，避免同路由组件复用时状态串联。
 */
export class FileEditorOpenFactory {
  public static createParams(params: FileEditorOpenParams): FileEditorOpenParams {
    const instanceId = params.instanceId && params.instanceId.length > 0
      ? params.instanceId
      : fileEditorService.createInstanceId();
    const editorParams: FileEditorOpenParams = {
      instanceId: instanceId,
      sessionId: params.sessionId ?? instanceId,
      hostMode: params.hostMode,
      filePath: params.filePath,
      content: params.content,
      language: params.language,
      readOnly: params.readOnly,
      title: params.title,
      origin: params.origin,
      saveTarget: params.saveTarget
    };
    return editorParams;
  }
}
