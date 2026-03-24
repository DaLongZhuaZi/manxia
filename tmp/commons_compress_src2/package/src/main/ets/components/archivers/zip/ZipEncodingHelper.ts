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
import { TextEncoder, TextDecoder } from 'text-encoding';
import type ZipEncoding from './ZipEncoding';
import NioZipEncoding from './NioZipEncoding';
import Charset from '../../util/Charset';
import CharacterSetECI from '../../util/CharacterSetECI';


export default class ZipEncodingHelper {
    static UTF8: string = "UTF8";
    static UTF8_ZIP_ENCODING: ZipEncoding = ZipEncodingHelper.getZipEncoding(ZipEncodingHelper.UTF8);

    public static getZipEncoding(name: string): ZipEncoding {
        let cs: Charset = Charset.defaultCharset();
        if (name != null) {
            try {
                cs = Charset.forName(name);
            } catch (e) {
            }
        }
        let useReplacement: boolean = ZipEncodingHelper.isUTF8(cs.getName());
        return new NioZipEncoding(cs, useReplacement);
    }

    static isUTF8(charsetName: string): boolean {
        if (charsetName == null) {

            charsetName = Charset.defaultCharset().getName();
        }
        let charsetNameCharacterSetECI: CharacterSetECI = CharacterSetECI.getCharacterSetECIByName(charsetName);
        if (CharacterSetECI.UTF8.equals(charsetNameCharacterSetECI)) {
            return true;
        } else {
            return false;
        }
    }

    public static customDecoder: (bytes: Uint8Array, encodingName: string) => string;
    public static customEncoder: (s: string, encodingName: string) => Uint8Array;

    public static decode(bytes: Uint8Array, encoding: string | CharacterSetECI): string {
        const encodingName = this.encodingName(encoding);
        if (this.customDecoder) {
            return this.customDecoder(bytes, encodingName);
        }
        return new TextDecoder(encodingName).decode(bytes);
    }

    public static encode(s: string, encoding: string | CharacterSetECI): Uint8Array {
        const encodingName = this.encodingName(encoding);
        if (this.customEncoder) {
            return this.customEncoder(s, encodingName);
        }
        if (s.length == 0) {

        }

        return new TextEncoder(encodingName, {
            NONSTANDARD_allowLegacyEncoding: true
        }).encode(s);
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

    public static getBytes(str: string, encoding: CharacterSetECI): Uint8Array {
        return ZipEncodingHelper.encode(str, encoding);
    }

    public static getCharAt(charCode: number): string {
        return String.fromCharCode(charCode);
    }

    public static canEncode(ch: number, encoding: CharacterSetECI): boolean {
        let charAt = ZipEncodingHelper.getCharAt(ch);
        let bytes = ZipEncodingHelper.getBytes(charAt, encoding);
        return bytes !== undefined && bytes.length !== 0;
    }
}