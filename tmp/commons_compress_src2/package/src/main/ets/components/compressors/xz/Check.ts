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
import { sha256 } from 'js-sha256'
import NumberTransform from './NumberTransform'
import XZ from './XZ'
import Long from "../../util/long/index"
import Newcrc32 from './Newcrc32'

export default abstract class Check {
    size: number;
    name: string;

    public abstract updates(buf: Int8Array, off: number, len: number): void;

    public abstract finish(): Int8Array;

    public updateI(buf: Int8Array) {
        this.updates(buf, 0, buf.length);
    }

    public getSize(): number {
        return this.size;
    }

    public getName(): string {
        return this.name
    }

    public static getInstance(checkType: number): any {
        switch (checkType) {
            case XZ.CHECK_NONE:
                return new None();
            case XZ.CHECK_CRC32:
                return new CRC32();
            case XZ.CHECK_CRC64:
                return new CRC64();
            case XZ.CHECK_SHA256:
                try {
                    let hash = new SHA256()
                    return hash;
                } catch (e) {
                }
            default:
                throw new Exception("Unsupported Check ID " + checkType);
        }
    }
}

export class CRC32 extends Check {
    private state = new Newcrc32();

    constructor() {
        super()
        this.size = 4;
        this.name = "CRC32";
    }

    public updates(buf: Int8Array, off: number, len: number) {
        this.state.updates(buf, off, len);
    }

    public finish(): Int8Array {
        let value: Long = this.state.getValue();
        let buf: Int8Array = new Int8Array([value.toNumber(), (value.toNumber() >>> 8), (value.toNumber() >>> 16), (value.toNumber() >>> 24)]);
        this.state.reset();
        return buf;
    }
}

export class None extends Check {
    constructor() {
        super()
        this.size = 0;
        this.name = "None";
    }

    public updates(buf: Int8Array, off: number, len: number) {
    }

    public finish(): Int8Array {
        let empty: Int8Array = new Int8Array(0);
        return empty;
    }
}

export class SHA256 extends Check {
    private shajs

    constructor() {
        super()
        this.size = 32;
        this.name = "SHA-256";
        this.shajs = sha256.create();
    }

    public updates(buf: Int8Array, off: number, len: number): void {
        this.shajs.update(buf);
    }

    public finish(): Int8Array {
        let buf: Int8Array = new Int8Array(this.shajs.digest(0));
        //            sha256.reset();
        return buf;
    }
}

export class CRC64 extends Check {
    private static TABLE: Array<Array<Long>> = new Array<Array<Long>>(4);
    private crc: Long = Long.fromNumber(-1) ;

    constructor() {
        super()
        this.size = 8;
        this.name = "CRC64";
    }

    static staticInit() {
        for (let i = 0;i < 4; i++) {
            CRC64.TABLE[i] = new Array<Long>(256);
        }
    }

    public updates(buf: Int8Array, off: number, len: number) {
        let end: number = off + len;
        let i: number = off;

        for (let end4: number = end - 3; i < end4; i += 4) {
            let tmp: number = this.crc.toInt();
            this.crc = CRC64.TABLE[3][tmp & 255 ^ buf[i] & 255]
                .xor(CRC64.TABLE[2][tmp >>> 8 & 255 ^ buf[i + 1] & 255])
                .xor(this.crc.shiftRightUnsigned(32)).xor(CRC64.TABLE[1][tmp >>> 16 & 255 ^ buf[i + 2] & 255])
                .xor(CRC64.TABLE[0][tmp >>> 24 & 255 ^ buf[i + 3] & 255]);
        }

        while (i < end) {
            this.crc = CRC64.TABLE[0][buf[i++] & 255 ^ this.crc.toInt() & 255].xor(this.crc.shiftRightUnsigned(8));
        }

    }

    public finish(): Int8Array {
        let value: Long = this.crc.not();
        this.crc = Long.fromNumber(-1);
        let buf: Int8Array = new Int8Array(8);

        for (let i = 0; i < buf.length; ++i) {
            buf[i] = NumberTransform.toByte(value.shiftRight(i * 8).toInt());
        }

        return buf;
    }

    static table() {
        let poly64: Long = Long.fromString('-3932672073523589310');
        for (let s = 0; s < 4; ++s) {
            for (let b = 0; b < 256; ++b) {
                let r: Long = (s == 0 ? Long.fromNumber(b) : CRC64.TABLE[s - 1][b]);

                for (let i = 0; i < 8; ++i) {
                    if ((r.and(1)).equals(1)) {
                        r = r.shiftRightUnsigned(1).xor(poly64);
                    } else {
                        r = r.shiftRightUnsigned(1);
                    }
                }
                CRC64.TABLE[s][b] = r;
            }
        }

    }
}

CRC64.staticInit()
CRC64.table()
