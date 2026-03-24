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
import Exception from '../../util/Exception'
import InputStream from '../../util/InputStream'
import Newcrc32 from './Newcrc32'
import NumberTransform from "./NumberTransform";
import Util from './Util'
import XZ from './XZ'
import StreamFlags from './StreamFlags'
import Long from "../../util/long/index"

export default class DecoderUtil extends Util {
    constructor() {
        super();
    }

    public static isCRC32Valid(buf: Int8Array, off: number, len: number, ref_off: number): boolean {
        let crc32: Newcrc32 = new Newcrc32();
        crc32.updates(buf, off, len);
        let value = crc32.getValue();

        for (let i: number = 0; i < 4; ++i) {
            let intArray = value.shr(i * 8).toInt()
            if (NumberTransform.toByte(intArray) != buf[ref_off + i]) {

                return false;
            }
        }

        return true;
    }

    public static decodeStreamHeader(buf: Int8Array): StreamFlags {
        for (let i = 0; i < XZ.HEADER_MAGIC.length; ++i) {
            if (buf[i] != XZ.HEADER_MAGIC[i]) {
                throw new Exception('Input is not in the XZ format');
            }
        }

        if (!this.isCRC32Valid(buf, XZ.HEADER_MAGIC.length, 2, XZ.HEADER_MAGIC.length + 2)) {
            throw new Exception("XZ Stream Header is corrupt");
        } else {
            try {
                return this.decodeStreamFlags(buf, XZ.HEADER_MAGIC.length);
            } catch (e) {
                throw new Exception("Unsupported options in XZ Stream Header");
            }
        }
    }

    public static decodeStreamFooter(buf: Int8Array): StreamFlags{
        if (buf[10] == XZ.FOOTER_MAGIC[0] && buf[11] == XZ.FOOTER_MAGIC[1]) {
            if (!this.isCRC32Valid(buf, 4, 6, 0)) {
                throw new Exception("XZ Stream Footer is corrupt");
            } else {
                let streamFlags: StreamFlags;
                try {
                    streamFlags = this.decodeStreamFlags(buf, 8);
                } catch (e) {
                    throw new Exception("Unsupported options in XZ Stream Footer");
                }

                streamFlags.backwardSize = Long.fromNumber(0);

                for (let i = 0; i < 4; ++i) {
                    streamFlags.backwardSize = streamFlags.backwardSize.or(((buf[i + 4] & 255) << (i * 8)));
                }

                streamFlags.backwardSize = (streamFlags.backwardSize.add(1)).multiply(4);
                return streamFlags;
            }
        } else {
            throw new Exception("XZ Stream Footer is corrupt");
        }
    }

    private static decodeStreamFlags(buf: Int8Array, off: number): StreamFlags {
        if (buf[off] == 0 && (buf[off + 1] & 255) < 16) {
            let streamFlags = new StreamFlags();
            streamFlags.checkType = buf[off + 1];
            return streamFlags;
        } else {
            throw new Exception();
        }
    }

    public static areStreamFlagsEqual(a: StreamFlags, b: StreamFlags): boolean {
        return a.checkType == b.checkType;
    }

    public static decodeVLI(inputStream: InputStream): Long {
        let b = inputStream.read();
        if (b == -1) {
            throw new Exception();
        } else {
            let num = Long.fromNumber(b & 127);

            for (let i = 0; (b & 128) != 0; num = num.or(Long.fromNumber((b & 127) << i * 7))) {
                ++i;
                if (i >= 9) {
                    throw new Exception();
                }

                b = inputStream.read();
                if (b == -1) {
                    throw new Exception();
                }

                if (b == 0) {
                    throw new Exception();
                }
            }

            return num;
        }
    }
}
