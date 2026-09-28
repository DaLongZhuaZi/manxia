/**
 * JSVM / Rhino shared Jsoup entity decoder script.
 * Generated from Jsoup 1.16.2 EntitiesData.java. Do not edit manually.
 * This module only re-exports the generated decoder constant; it must not
 * maintain an independent entity table, scan rule or decode algorithm.
 */
import { JSOUP_JS_DECODER_SCRIPT } from './JsoupEntityData';

export function buildJsoupEntityCompatibilityScript(): string {
  return JSOUP_JS_DECODER_SCRIPT;
}