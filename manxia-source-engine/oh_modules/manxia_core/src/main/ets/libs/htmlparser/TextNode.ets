/**
 * 文本节点类
 * 表示 HTML 中的纯文本内容
 * 
 * 设计参考 node-html-parser 的 TextNode 类
 */

import { NodeType } from './NodeType';
import { Node } from './Node';

/**
 * 文本节点
 */
export class TextNode extends Node {
  /**
   * 原始文本内容
   */
  private _rawText: string;

  constructor(rawText: string, parentNode: Node | null = null, range?: [number, number]) {
    super(NodeType.TEXT_NODE, parentNode, range);
    this._rawText = rawText;
  }

  /**
   * 获取原始文本
   */
  get rawText(): string {
    return this._rawText;
  }

  /**
   * 设置原始文本
   */
  set rawText(val: string) {
    this._rawText = val;
  }

  /**
   * 获取文本内容（解码 HTML 实体）
   */
  get text(): string {
    return this.decodeHtmlEntities(this._rawText);
  }

  /**
   * 检查是否为纯空白文本
   */
  get isWhitespace(): boolean {
    return /^\s*$/.test(this._rawText);
  }

  /**
   * 克隆节点
   */
  clone(): TextNode {
    const newRange: [number, number] = [this.range[0], this.range[1]];
    return new TextNode(this._rawText, null, newRange);
  }

  /**
   * 转换为字符串
   */
  toString(): string {
    return this._rawText;
  }
}
