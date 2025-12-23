/**
 * 注释节点类
 * 表示 HTML 中的注释内容 <!-- comment -->
 * 
 * 设计参考 node-html-parser 的 CommentNode 类
 */

import { NodeType } from './NodeType';
import { Node } from './Node';

/**
 * 注释节点
 */
export class CommentNode extends Node {
  /**
   * 注释内容
   */
  private _rawText: string;

  constructor(rawText: string, parentNode: Node | null = null, range?: [number, number]) {
    super(NodeType.COMMENT_NODE, parentNode, range);
    this._rawText = rawText;
  }

  /**
   * 获取原始注释内容
   */
  get rawText(): string {
    return this._rawText;
  }

  /**
   * 设置注释内容
   */
  set rawText(val: string) {
    this._rawText = val;
  }

  /**
   * 获取注释文本
   */
  get text(): string {
    return this._rawText;
  }

  /**
   * 克隆节点
   */
  clone(): CommentNode {
    const newRange: [number, number] = [this.range[0], this.range[1]];
    return new CommentNode(this._rawText, null, newRange);
  }

  /**
   * 转换为字符串
   */
  toString(): string {
    return `<!--${this._rawText}-->`;
  }
}
