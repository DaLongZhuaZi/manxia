/**
 * 全局帮助信息面板组件 V2
 * 
 * ⚠️ 此文件已重构为兼容层，实际实现已迁移到 ContentPanel.ets
 * 新代码请直接使用 ContentPanel.ets 中的 ContentPanelManager 和 ContentPanelOverlay
 * 
 * 文件路径: entry/src/main/ets/Framework/Components/HelpPanelV2.ets
 */

// 从 ContentPanel 重新导出所有内容以保持向后兼容
export {
  // 类型和枚举
  ContentSource as HelpContentSource,
  PanelMode as HelpPanelMode,
  PanelFontSize as HelpFontSize,
  ContentPanelType,
  
  // 接口
  ContentTab as HelpTab,
  ContentPanelConfig as HelpPanelConfig,
  PanelStyleConfig,
  FloatBallConfig,
  
  // 管理器
  ContentPanelManager as HelpPanelManagerV2,
  getContentPanelManager as getHelpPanelManagerV2,
  
  // 组件
  ContentPanelOverlay as HelpPanelOverlayV2
} from 'manxia_core/src/main/ets/Framework/Components/ContentPanel';

// 为了兼容性，也导出 ContentPanel 的原始名称
export {
  ContentSource,
  PanelMode,
  PanelFontSize,
  ContentPanelManager,
  getContentPanelManager,
  ContentPanelOverlay
} from 'manxia_core/src/main/ets/Framework/Components/ContentPanel';
