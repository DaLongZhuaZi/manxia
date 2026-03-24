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
import Charset from '../../util/Charset';
import type ZipEncoding from './ZipEncoding';
import ZipEncodingHelper from './ZipEncodingHelper';
import type CharsetAccessor from './CharsetAccessor';

export default class NioZipEncoding implements ZipEncoding, CharsetAccessor {
    private charset: Charset;
    private useReplacement: boolean;
    private static REPLACEMENT: number = '?'.charCodeAt(0);
    private static REPLACEMENT_BYTES: Int32Array = new Int32Array([NioZipEncoding.REPLACEMENT]);
    private static REPLACEMENT_STRING: string = String.fromCharCode(NioZipEncoding.REPLACEMENT);
    private static HEX_CHARS: Int32Array = new Int32Array([
        '0'.charCodeAt(0), '1'.charCodeAt(0), '2'.charCodeAt(0), '3'.charCodeAt(0), '4'.charCodeAt(0), '5'.charCodeAt(0),
        '6'.charCodeAt(0), '7'.charCodeAt(0), '8'.charCodeAt(0), '9'.charCodeAt(0), 'A'.charCodeAt(0), 'B'.charCodeAt(0),
        'C'.charCodeAt(0), 'D'.charCodeAt(0), 'E'.charCodeAt(0), 'F'.charCodeAt(0)]);

    constructor(charset: Charset, useReplacement: boolean) {
        this.charset = charset;
        this.useReplacement = useReplacement;
    }

    public getCharset(): Charset {
        return this.charset;
    }

    public canEncode(name: string): boolean {
        let isCanEncode: boolean = true;
        for (let i = 0; i < name.length; i++) {
            if (!ZipEncodingHelper.canEncode(name.charCodeAt(i), this.charset)) {
                isCanEncode = false;
                break
            }
        }
        return isCanEncode;
    }

    public encode(name: string): Int8Array {
        let outUint8Array: Uint8Array = ZipEncodingHelper.encode(name, this.charset);
        return new Int8Array(outUint8Array.buffer);
    }

    public decode(data: Int8Array): string {
        return ZipEncodingHelper.decode(new Uint8Array(data.buffer), this.charset);
    }
}