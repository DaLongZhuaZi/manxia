/**
 * HTML 节点基类
 * 所有节点类型的基础类，提供通用的节点操作
 * 
 * 设计参考 node-html-parser 的 Node 类
 * 保留完整扩展性，支持将来移植更多功能
 */

import { NodeType } from './NodeType';
import { HtmlEntities } from './HtmlEntities';

/**
 * 节点基类
 */
export class Node {
  /**
   * 节点类型
   */
  nodeType: NodeType;

  /**
   * 父节点
   */
  parentNode: Node | null = null;

  /**
   * 子节点列表
   */
  childNodes: Node[] = [];

  /**
   * 节点在源码中的位置范围 [start, end]
   * 用于调试和错误定位
   */
  range: [number, number] = [-1, -1];

  constructor(nodeType: NodeType, parentNode: Node | null = null, range?: [number, number]) {
    this.nodeType = nodeType;
    this.parentNode = parentNode;
    if (range) {
      this.range = range;
    }
  }

  /**
   * 获取原始文本内容（子类需要重写）
   */
  get rawText(): string {
    return '';
  }

  /**
   * 设置原始文本内容（子类需要重写）
   */
  set rawText(_val: string) {
    // 子类实现
  }

  /**
   * 获取内部文本（同 rawText）
   */
  get innerText(): string {
    return this.rawText;
  }

  /**
   * 获取文本内容（会解码 HTML 实体）
   */
  get textContent(): string {
    return this.decodeHtmlEntities(this.rawText);
  }

  /**
   * 设置文本内容
   */
  set textContent(val: string) {
    this.rawText = this.encodeHtmlEntities(val);
  }

  /**
   * 移除当前节点
   */
  remove(): Node {
    if (this.parentNode) {
      const children = this.parentNode.childNodes;
      const self = this;
      this.parentNode.childNodes = children.filter((child: Node): boolean => {
        return self !== child;
      });
      this.parentNode = null;
    }
    return this;
  }

  /**
   * 获取前一个兄弟节点
   */
  get previousSibling(): Node | null {
    if (!this.parentNode) return null;
    const siblings = this.parentNode.childNodes;
    const index = siblings.indexOf(this);
    return index > 0 ? siblings[index - 1] : null;
  }

  /**
   * 获取后一个兄弟节点
   */
  get nextSibling(): Node | null {
    if (!this.parentNode) return null;
    const siblings = this.parentNode.childNodes;
    const index = siblings.indexOf(this);
    return index >= 0 && index < siblings.length - 1 ? siblings[index + 1] : null;
  }

  /**
   * 克隆节点（子类需要重写）
   */
  clone(): Node {
    const newRange: [number, number] = [this.range[0], this.range[1]];
    return new Node(this.nodeType, null, newRange);
  }

  /**
   * 解码 HTML 实体
   */
  protected decodeHtmlEntities(text: string): string {
    return HtmlEntities.decode(text);
  }

  /**
   * 编码 HTML 实体
   */
  protected encodeHtmlEntities(text: string): string {
    return HtmlEntities.encode(text);
  }
}
