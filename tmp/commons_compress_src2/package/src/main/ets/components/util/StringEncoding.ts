/*
 * Copyright (c) 2022 Huawei Device Co., Ltd.
 * Licensed under the Apache License, Version 2.0 (the "License");
 * you may not use this file except in compliance with the License.
 * You may obtain a copy of the License at
 *
 *     http://www.apache.org/licenses/LICENSE-2.0
 *
 * Unless required by applicable law or agreed to in writing, software
 * distributed under the License is distributed on an "AS IS" BASIS,
 * WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
 * See the License for the specific language governing permissions and
 * limitations under the License.
 */
import UnsupportedOperationException from './UnsupportedOperationException';
import CharacterSetECI from './CharacterSetECI';
import { TextDecoder, TextEncoder } from 'text-encoding'

export default class StringEncoding {
    public static customDecoder: (bytes: Uint8Array, encodingName: string) => string;
    public static customEncoder: (s: string, encodingName: string) => Uint8Array;

    public static decode(bytes: Uint8Array, encoding: string | CharacterSetECI): string {

        const encodingName = this.encodingName(encoding);

        if (this.customDecoder) {
            return this.customDecoder(bytes, encodingName);
        }

        if (typeof TextDecoder === 'undefined' || this.shouldDecodeOnFallback(encodingName)) {
            return this.decodeFallback(bytes, encodingName);
        }

        return new TextDecoder(encodingName).decode(bytes);
    }

    private static shouldDecodeOnFallback(encodingName: string): boolean {
        return!StringEncoding.isBrowser() && encodingName === 'ISO-8859-1';
    }

    public static encode(s: string, encoding: string | CharacterSetECI): Uint8Array {

        const encodingName = this.encodingName(encoding);

        if (this.customEncoder) {
            return this.customEncoder(s, encodingName);
        }

        if (typeof TextEncoder === 'undefined') {
            return this.encodeFallback(s);
        }

        return new TextEncoder().encode(s);
    }

    private static isBrowser(): boolean {
        return false;
    }

    public static encodingName(encoding: string | CharacterSetECI): string {
        return typeof encoding === 'string'
            ? encoding
            : encoding.getName();
    }

    public static encodingCharacterSet(encoding: string | CharacterSetECI): CharacterSetECI {

        if (encoding instanceof CharacterSetECI) {
            return encoding;
        }

        return CharacterSetECI.getCharacterSetECIByName(encoding);
    }

    private static decodeFallback(bytes: Uint8Array, encoding: string | CharacterSetECI): string {

        const characterSet = this.encodingCharacterSet(encoding);

        if (StringEncoding.isDecodeFallbackSupported(characterSet)) {

            let s = '';

            for (let i = 0, length = bytes.length; i < length; i++) {

                let h = bytes[i].toString(16);

                if (h.length < 2) {
                    h = '0' + h;
                }

                s += '%' + h;
            }

            return decodeURIComponent(s);
        }

        if (characterSet.equals(CharacterSetECI.UnicodeBigUnmarked)) {
            return String.fromCharCode.apply(null, new Uint16Array(bytes.buffer));
        }

        throw new UnsupportedOperationException(`Encoding ${this.encodingName(encoding)} not supported by fallback.`);
    }

    private static isDecodeFallbackSupported(characterSet: CharacterSetECI) {
        return characterSet.equals(CharacterSetECI.UTF8) ||
        characterSet.equals(CharacterSetECI.ISO8859_1) ||
        characterSet.equals(CharacterSetECI.ASCII);
    }

    private static encodeFallback(s: string): Uint8Array {

        return new Uint8Array(1);
    }
}
