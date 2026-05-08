/**
 * 字符串相似度工具模块
 * 提供归一化、编辑距离、N-gram 相似度等算法
 */

// 需要去除的中英文标点和特殊字符
const PUNCTUATION_REGEX: RegExp = /[《》〈〉「」『』【】〔〕（）\(\)\[\]\{\}""''""''…·～~!！?？,，.。;；:：、\-—_/\\|#@\$%\^&\*\+=`'"<> 　]/g;

/**
 * 文本归一化：去除标点、合并空格、转小写
 */
export function normalizeText(text: string): string {
  if (!text) {
    return '';
  }
  let result = text.replace(PUNCTUATION_REGEX, ' ');
  result = result.replace(/\s+/g, ' ');
  result = result.trim();
  result = result.toLowerCase();
  return result;
}

/**
 * Levenshtein 编辑距离
 * 使用两行滚动数组优化空间
 */
export function levenshteinDistance(a: string, b: string): number {
  const lenA: number = a.length;
  const lenB: number = b.length;

  if (lenA === 0) {
    return lenB;
  }
  if (lenB === 0) {
    return lenA;
  }

  let prev: number[] = new Array<number>(lenB + 1);
  let curr: number[] = new Array<number>(lenB + 1);

  for (let j: number = 0; j <= lenB; j++) {
    prev[j] = j;
  }

  for (let i: number = 1; i <= lenA; i++) {
    curr[0] = i;
    for (let j: number = 1; j <= lenB; j++) {
      const cost: number = a.charAt(i - 1) === b.charAt(j - 1) ? 0 : 1;
      const deletion: number = prev[j] + 1;
      const insertion: number = curr[j - 1] + 1;
      const substitution: number = prev[j - 1] + cost;
      curr[j] = Math.min(deletion, insertion, substitution);
    }
    const temp: number[] = prev;
    prev = curr;
    curr = temp;
  }

  return prev[lenB];
}

/**
 * 基于编辑距离的相似度，返回 0.0 ~ 1.0
 */
export function levenshteinSimilarity(a: string, b: string): number {
  if (a.length === 0 && b.length === 0) {
    return 1.0;
  }
  if (a.length === 0 || b.length === 0) {
    return 0.0;
  }

  const maxLen: number = Math.max(a.length, b.length);
  const distance: number = levenshteinDistance(a, b);
  return 1.0 - (distance / maxLen);
}

/**
 * N-gram Jaccard 相似度
 * 将字符串拆成 n-gram 集合，计算交集/并集比
 */
export function ngramSimilarity(a: string, b: string, n: number = 2): number {
  if (a.length === 0 && b.length === 0) {
    return 1.0;
  }
  if (a.length < n && b.length < n) {
    return a === b ? 1.0 : 0.0;
  }

  const ngramsA: Set<string> = buildNgramSet(a, n);
  const ngramsB: Set<string> = buildNgramSet(b, n);

  let intersectionSize: number = 0;
  ngramsA.forEach((value: string) => {
    if (ngramsB.has(value)) {
      intersectionSize++;
    }
  });

  const unionSize: number = ngramsA.size + ngramsB.size - intersectionSize;
  if (unionSize === 0) {
    return 0.0;
  }

  return intersectionSize / unionSize;
}

/**
 * 构建 n-gram 集合
 */
function buildNgramSet(text: string, n: number): Set<string> {
  const result: Set<string> = new Set<string>();
  const len: number = text.length;
  for (let i: number = 0; i <= len - n; i++) {
    result.add(text.substring(i, i + n));
  }
  return result;
}

/**
 * 综合相似度：Levenshtein 与 N-gram 加权组合
 * 默认权重: levenshtein 0.6, ngram 0.4
 */
export function combinedSimilarity(a: string, b: string, levenshteinWeight: number = 0.6): number {
  const levSim: number = levenshteinSimilarity(a, b);
  const ngramSim: number = ngramSimilarity(a, b, 2);
  const ngramWeight: number = 1.0 - levenshteinWeight;
  return levenshteinWeight * levSim + ngramWeight * ngramSim;
}
