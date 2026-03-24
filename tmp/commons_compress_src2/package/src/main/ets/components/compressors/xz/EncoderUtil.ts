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
import OutputStream from '../../util/OutputStream'
import Util from './Util'
import Newcrc32 from './Newcrc32'
import NumberTransform from "./NumberTransform";
import Long from "../../util/long/index"

export default class EncoderUtil extends Util {
    constructor() {
        super()
    }

    public static writeCRC32(out: OutputStream, buf: Int8Array): void {
        let crc32 = new Newcrc32();
        crc32.updateArray(buf);
        let value: Long = crc32.getValue();

        for (let i: number = 0; i < 4; ++i) {
            let intArray = value.shiftRightUnsigned(i * 8).toInt()
            out.write(NumberTransform.toByte(intArray));
        }
    }

    public static encodeVLI(out: OutputStream, num: Long): void {
        while (num.greaterThanOrEqual(128)) {
            out.write(NumberTransform.toByte(num.or(128)));
            num = num.shiftRightUnsigned(7);
        }
        out.write(NumberTransform.toByte(num.toNumber()));
    }
}
