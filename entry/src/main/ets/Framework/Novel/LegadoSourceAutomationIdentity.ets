/**
 * Produces an injective ArkUI/Hypium-safe token for a source identity.
 * Raw source URLs can contain selector-significant characters such as '#'.
 */
export function getLegadoSourceAutomationToken(sourceId: string): string {
  let token = '';
  for (let index = 0; index < sourceId.length; index++) {
    const code = sourceId.charCodeAt(index);
    const isDigit = code >= 48 && code <= 57;
    const isUppercase = code >= 65 && code <= 90;
    const isLowercase = code >= 97 && code <= 122;
    if (isDigit || isUppercase || isLowercase) {
      token += sourceId.charAt(index);
    } else {
      token += `_${code.toString(16)}_`;
    }
  }
  return token;
}
