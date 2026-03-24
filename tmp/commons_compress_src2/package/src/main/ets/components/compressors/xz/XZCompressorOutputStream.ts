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
import XZ from './XZ';
import OutputStream from '../../util/OutputStream'
import CompressorOutputStream from '../CompressorOutputStream'
import XZOutputStream from './XZOutputStream'
import ArrayCache from './ArrayCache'
import LZMA2Options from './LZMA2Options'
import FilterOptions from './FilterOptions'

export default class XZCompressorOutputStream extends CompressorOutputStream {
    private out: XZOutputStream;

    constructor(outputStream: OutputStream) {
        super()
        let presetLZMA2Options: FilterOptions = new LZMA2Options()
        let filterArray: Array<FilterOptions> = new Array<FilterOptions>(presetLZMA2Options)
        this.out = new XZOutputStream(outputStream, filterArray, XZ.CHECK_CRC64, ArrayCache.getDefaultCache())
    }

    public write(b: number): void {
        this.out.write(b);
    }

    public writeBytesOffset(buf: Int8Array, off: number, len: number) {
        this.out.writeBytesOffset(buf, off, len);
    }

    public flush() {
        this.out.flush();
    }

    public finish() {
        this.out.finish();
    }

    public close() {
        this.out.close();
    }
}
