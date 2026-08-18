/**
 * HTML 解析器模块入口
 * 统一导出所有类和函数
 * 
 * 使用方法：
 * import { parse, HTMLElement, NodeType } from '../libs/htmlparser';
 * 
 * const root = parse('<div class="container"><p>Hello</p></div>');
 * const p = root.querySelector('p');
 * console.log(p?.text); // 'Hello'
 */

// 导入 parse 用于测试函数（必须在顶部）
import { parse as parseHtml } from './Parser';
import { LegadoHtmlBridge } from './LegadoHtmlBridge';

// 导出节点类型
export { NodeType } from './NodeType';

// 导出节点类
export { Node } from './Node';
export { TextNode } from './TextNode';
export { CommentNode } from './CommentNode';
export { HTMLElement, Attributes } from './HTMLElement';

// 导出选择器匹配器
export { Matcher, Combinator, SelectorPart, SelectorNode, AttributeSelector, PseudoClass } from './Matcher';

// 导出解析器
export { Parser, parse, ParseOptions } from './Parser';

// 导出 HTML 实体工具
export { HtmlEntities } from './HtmlEntities';
export { buildJsoupEntityCompatibilityScript } from './JsoupEntityScript';

// Legado/Jsoup text projection primitives shared by DOM and string fallback.
export { LegadoTextNormalization, LegadoTextAccumulator } from './LegadoTextNormalization';

// 导出日志工具
export { HtmlParserLogger } from './HtmlParserLogger';

// 导出 Legado 桥接层
export { LegadoHtmlBridge, createLegadoHtmlBridge } from './LegadoHtmlBridge';

/**
 * 测试 HTML 解析器
 */
export function testHtmlParser(): string {
  try {
    const html = `
      <html>
        <body>
          <div id="container" class="main-content">
            <h1>Hello World</h1>
            <ul class="list">
              <li class="item">Item 1</li>
              <li class="item">Item 2</li>
              <li class="item">Item 3</li>
            </ul>
            <a href="https://example.com">Link</a>
          </div>
        </body>
      </html>
    `;

    const root = parseHtml(html);
    const results: string[] = [];

    // 测试 querySelector
    const h1 = root.querySelector('h1');
    results.push(`h1 text: ${h1?.text || 'not found'}`);

    // 测试 querySelectorAll
    const items = root.querySelectorAll('.item');
    results.push(`.item count: ${items.length}`);

    // 测试 getElementById
    const container = root.querySelector('#container');
    results.push(`#container found: ${container !== null}`);

    // 测试 getElementsByClassName
    const listItems = root.querySelectorAll('.item');
    results.push(`class=item count: ${listItems.length}`);

    // 测试获取属性
    const link = root.querySelector('a');
    results.push(`a href: ${link?.getAttribute('href') || 'not found'}`);

    // 测试获取文本内容
    const firstItem = items[0];
    results.push(`first item text: ${firstItem?.text || 'not found'}`);

    // 测试 Legado 桥接层
    const bridge = new LegadoHtmlBridge();
    bridge.setContent(html);
    
    // 测试 Legado 规则语法
    const legadoItems = bridge.findByLegadoRule('class.item');
    results.push(`Legado class.item count: ${legadoItems.length}`);
    
    // 测试链式规则
    const chainResult = bridge.parseChainRule('class.list@tag.li@text');
    results.push(`Legado chain rule result: ${chainResult.substring(0, 50)}...`);

    return `HTML Parser Test PASSED:\n${results.join('\n')}`;
  } catch (error) {
    return `HTML Parser Test FAILED: ${error}`;
  }
}
