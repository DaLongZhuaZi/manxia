/**
 * Legado/Jsoup text projection primitives.
 *
 * Jsoup normalises ordinary text one TextNode at a time while carrying the
 * last-space state across adjacent nodes. Preserve-whitespace tags bypass
 * that normalisation, and the public text/ownText projections trim only the
 * Java String.trim() range (U+0000..U+0020).
 */
export class LegadoTextNormalization {
  static isActuallyWhitespace(code: number): boolean {
    return code === 0x20 || code === 0x09 || code === 0x0A ||
      code === 0x0C || code === 0x0D || code === 0xA0;
  }

  static isInvisibleChar(code: number): boolean {
    return code === 0x200B || code === 0x00AD;
  }

  static isPreserveWhitespaceTag(tagName: string): boolean {
    const normalized = tagName.toLowerCase();
    return normalized === 'pre' || normalized === 'plaintext' ||
      normalized === 'title' || normalized === 'textarea';
  }

  static isDataTag(tagName: string): boolean {
    const normalized = tagName.toLowerCase();
    return normalized === 'script' || normalized === 'style';
  }

  static isBlockTag(tagName: string): boolean {
    const normalized = tagName.toLowerCase();
    const blockTags: string[] = [
      'html', 'head', 'body', 'frameset', 'script', 'noscript', 'style', 'meta',
      'link', 'title', 'frame', 'noframes', 'section', 'nav', 'aside', 'hgroup',
      'header', 'footer', 'p', 'h1', 'h2', 'h3', 'h4', 'h5', 'h6', 'ul', 'ol',
      'pre', 'div', 'blockquote', 'hr', 'address', 'figure', 'figcaption', 'form',
      'fieldset', 'ins', 'del', 'dl', 'dt', 'dd', 'li', 'table', 'caption', 'thead',
      'tfoot', 'tbody', 'colgroup', 'col', 'tr', 'th', 'td', 'video', 'audio',
      'canvas', 'details', 'menu', 'plaintext', 'template', 'article', 'main',
      'svg', 'math', 'center', 'dir', 'applet', 'marquee', 'listing'
    ];
    return blockTags.includes(normalized);
  }

  /**
   * Jsoup's Element.text() tail rule checks Tag.formatAsBlock() for an
   * immediately following element. This is intentionally separate from
   * isBlockTag(): Jsoup marks a small set of known block tags as inline when
   * formatting adjacent text, while unknown tags retain the generic block
   * formatting default.
   */
  static isFormatAsBlockTag(tagName: string): boolean {
    const normalized = tagName.toLowerCase();
    const formatAsInlineTags: string[] = [
      'title', 'a', 'p', 'h1', 'h2', 'h3', 'h4', 'h5', 'h6', 'pre',
      'address', 'li', 'th', 'td', 'script', 'style', 'ins', 'del', 's'
    ];
    const inlineTags: string[] = [
      'object', 'base', 'font', 'tt', 'i', 'b', 'u', 'big', 'small', 'em',
      'strong', 'dfn', 'code', 'samp', 'kbd', 'var', 'cite', 'abbr', 'time',
      'acronym', 'mark', 'ruby', 'rt', 'rp', 'rtc', 'a', 'img', 'br', 'wbr',
      'map', 'q', 'sub', 'sup', 'bdo', 'iframe', 'embed', 'span', 'input',
      'select', 'textarea', 'label', 'button', 'optgroup', 'option', 'legend',
      'datalist', 'keygen', 'output', 'progress', 'meter', 'area', 'param',
      'source', 'track', 'summary', 'command', 'device', 'basefont', 'bgsound',
      'menuitem', 'data', 'bdi', 'strike', 'nobr', 'rb', 'text', 'mi', 'mo',
      'msup', 'mn', 'mtext'
    ];
    return !formatAsInlineTags.includes(normalized) && !inlineTags.includes(normalized);
  }

  static trimJavaWhitespace(value: string): string {
    let start = 0;
    let end = value.length;
    while (start < end && value.charCodeAt(start) <= 0x20) {
      start++;
    }
    while (end > start && value.charCodeAt(end - 1) <= 0x20) {
      end--;
    }
    return value.substring(start, end);
  }
}

export class LegadoTextAccumulator {
  private output: string = '';
  private lastCharIsSpace: boolean = false;

  appendText(value: string, preserveWhitespace: boolean): void {
    if (value.length === 0) {
      return;
    }
    if (preserveWhitespace) {
      this.output += value;
      this.lastCharIsSpace = value.charAt(value.length - 1) === ' ';
      return;
    }

    for (let index = 0; index < value.length; index++) {
      const code = value.charCodeAt(index);
      if (LegadoTextNormalization.isActuallyWhitespace(code)) {
        if (!this.lastCharIsSpace) {
          this.output += ' ';
          this.lastCharIsSpace = true;
        }
        continue;
      }
      if (LegadoTextNormalization.isInvisibleChar(code)) {
        continue;
      }
      this.output += value.charAt(index);
      this.lastCharIsSpace = false;
    }
  }

  appendLineBreak(): void {
    if (this.output.length > 0 && !this.lastCharIsSpace && !this.output.endsWith('\n')) {
      this.output += '\n';
    }
    this.lastCharIsSpace = false;
  }

  appendBlockBoundary(): void {
    this.appendLineBreak();
  }

  /**
   * Jsoup 1.16.2 Element.text()/ownText() use an ASCII space for block and
   * br boundaries. Keep the legacy line-break operation available for the
   * reader formatter, but never use it for these Jsoup projections.
   */
  appendJsoupSpaceBoundary(): void {
    if (this.output.length > 0 && !this.lastCharIsSpace) {
      this.output += ' ';
    }
    this.lastCharIsSpace = this.output.length > 0 && this.output.charAt(this.output.length - 1) === ' ';
  }

  hasOutput(): boolean {
    return this.output.length > 0;
  }

  endsWithSpace(): boolean {
    return this.lastCharIsSpace;
  }

  get length(): number {
    return this.output.length;
  }

  toTrimmedString(): string {
    return LegadoTextNormalization.trimJavaWhitespace(this.output);
  }
}
