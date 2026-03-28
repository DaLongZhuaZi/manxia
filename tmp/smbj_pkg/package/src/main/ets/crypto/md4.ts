/*
 * (The MIT License)

 * Copyright (c) 2021 Huawei Device Co., Ltd.

 * Permission is hereby granted, free of charge, to any person obtaining
 * a copy of this software and associated documentation files (the
 * 'Software'), to deal in the Software without restriction, including
 * without limitation the rights to use, copy, modify, merge, publish,
 * distribute, sublicense, and/or sell copies of the Software, and to
 * permit persons to whom the Software is furnished to do so, subject to
 * the following conditions:

 * The above copyright notice and this permission notice shall be
 * included in all copies or substantial portions of the Software.

 * THE SOFTWARE IS PROVIDED 'AS IS', WITHOUT WARRANTY OF ANY KIND,
 * EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF
 * MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT.
 * IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY
 * CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER IN AN ACTION OF CONTRACT,
 * TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN CONNECTION WITH THE
 * SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE.
 */

import {Buffer} from '../buffer/index'

export class MD4 {
  private static A: number;
  private static B: number;
  private static C: number;
  private static D: number;
  private static input: string;
  private static X: number[] = new Array(16);

  private static F(X: number, Y: number, Z: number): number {
    return (X & Y) | ((~X) & Z);
  }

  private static G(X: number, Y: number, Z: number): number {
    return (X & Y) | (X & Z) | (Y & Z);
  }

  private static H(X: number, Y: number, Z: number): number {
    return X ^ Y ^ Z;
  }

  private static lshift(x: number, s: number): number {
    if (s == 0) {
      return x;
    }
    return (((x << s) & 0xFFFFFFFF) | ((x >> (32 - s)) & (0x7FFFFFFF >> (31 - s))));
  }

  private static ROUND1(a: number, b: number, c: number, d: number, k: number, s: number): number {
    return (MD4.lshift(a + MD4.F(b, c, d) + MD4.X[k], s));
  }

  private static ROUND2(a: number, b: number, c: number, d: number, k: number, s: number): number {
    return (MD4.lshift(a + MD4.G(b, c, d) + MD4.X[k] + 0x5A827999, s));
  }

  private static ROUND3(a: number, b: number, c: number, d: number, k: number, s: number): number {
    return (MD4.lshift(a + MD4.H(b, c, d) + MD4.X[k] + 0x6ED9EBA1, s));
  }

  private static mdfour64(M: number[]) {
    var j: number;
    var AA: number, BB: number, CC: number, DD: number;

    for (j = 0; j < 16; j++) {
      MD4.X[j] = M[j];
    }

    AA = MD4.A;
    BB = MD4.B;
    CC = MD4.C;
    DD = MD4.D;

    MD4.A = MD4.ROUND1(MD4.A, MD4.B, MD4.C, MD4.D, 0, 3);
    MD4.D = MD4.ROUND1(MD4.D, MD4.A, MD4.B, MD4.C, 1, 7);
    MD4.C = MD4.ROUND1(MD4.C, MD4.D, MD4.A, MD4.B, 2, 11);
    MD4.B = MD4.ROUND1(MD4.B, MD4.C, MD4.D, MD4.A, 3, 19);
    MD4.A = MD4.ROUND1(MD4.A, MD4.B, MD4.C, MD4.D, 4, 3);
    MD4.D = MD4.ROUND1(MD4.D, MD4.A, MD4.B, MD4.C, 5, 7);
    MD4.C = MD4.ROUND1(MD4.C, MD4.D, MD4.A, MD4.B, 6, 11);
    MD4.B = MD4.ROUND1(MD4.B, MD4.C, MD4.D, MD4.A, 7, 19);
    MD4.A = MD4.ROUND1(MD4.A, MD4.B, MD4.C, MD4.D, 8, 3);
    MD4.D = MD4.ROUND1(MD4.D, MD4.A, MD4.B, MD4.C, 9, 7);
    MD4.C = MD4.ROUND1(MD4.C, MD4.D, MD4.A, MD4.B, 10, 11);
    MD4.B = MD4.ROUND1(MD4.B, MD4.C, MD4.D, MD4.A, 11, 19);
    MD4.A = MD4.ROUND1(MD4.A, MD4.B, MD4.C, MD4.D, 12, 3);
    MD4.D = MD4.ROUND1(MD4.D, MD4.A, MD4.B, MD4.C, 13, 7);
    MD4.C = MD4.ROUND1(MD4.C, MD4.D, MD4.A, MD4.B, 14, 11);
    MD4.B = MD4.ROUND1(MD4.B, MD4.C, MD4.D, MD4.A, 15, 19);

    MD4.A = MD4.ROUND2(MD4.A, MD4.B, MD4.C, MD4.D, 0, 3);
    MD4.D = MD4.ROUND2(MD4.D, MD4.A, MD4.B, MD4.C, 4, 5);
    MD4.C = MD4.ROUND2(MD4.C, MD4.D, MD4.A, MD4.B, 8, 9);
    MD4.B = MD4.ROUND2(MD4.B, MD4.C, MD4.D, MD4.A, 12, 13);
    MD4.A = MD4.ROUND2(MD4.A, MD4.B, MD4.C, MD4.D, 1, 3);
    MD4.D = MD4.ROUND2(MD4.D, MD4.A, MD4.B, MD4.C, 5, 5);
    MD4.C = MD4.ROUND2(MD4.C, MD4.D, MD4.A, MD4.B, 9, 9);
    MD4.B = MD4.ROUND2(MD4.B, MD4.C, MD4.D, MD4.A, 13, 13);
    MD4.A = MD4.ROUND2(MD4.A, MD4.B, MD4.C, MD4.D, 2, 3);
    MD4.D = MD4.ROUND2(MD4.D, MD4.A, MD4.B, MD4.C, 6, 5);
    MD4.C = MD4.ROUND2(MD4.C, MD4.D, MD4.A, MD4.B, 10, 9);
    MD4.B = MD4.ROUND2(MD4.B, MD4.C, MD4.D, MD4.A, 14, 13);
    MD4.A = MD4.ROUND2(MD4.A, MD4.B, MD4.C, MD4.D, 3, 3);
    MD4.D = MD4.ROUND2(MD4.D, MD4.A, MD4.B, MD4.C, 7, 5);
    MD4.C = MD4.ROUND2(MD4.C, MD4.D, MD4.A, MD4.B, 11, 9);
    MD4.B = MD4.ROUND2(MD4.B, MD4.C, MD4.D, MD4.A, 15, 13);

    MD4.A = MD4.ROUND3(MD4.A, MD4.B, MD4.C, MD4.D, 0, 3);
    MD4.D = MD4.ROUND3(MD4.D, MD4.A, MD4.B, MD4.C, 8, 9);
    MD4.C = MD4.ROUND3(MD4.C, MD4.D, MD4.A, MD4.B, 4, 11);
    MD4.B = MD4.ROUND3(MD4.B, MD4.C, MD4.D, MD4.A, 12, 15);
    MD4.A = MD4.ROUND3(MD4.A, MD4.B, MD4.C, MD4.D, 2, 3);
    MD4.D = MD4.ROUND3(MD4.D, MD4.A, MD4.B, MD4.C, 10, 9);
    MD4.C = MD4.ROUND3(MD4.C, MD4.D, MD4.A, MD4.B, 6, 11);
    MD4.B = MD4.ROUND3(MD4.B, MD4.C, MD4.D, MD4.A, 14, 15);
    MD4.A = MD4.ROUND3(MD4.A, MD4.B, MD4.C, MD4.D, 1, 3);
    MD4.D = MD4.ROUND3(MD4.D, MD4.A, MD4.B, MD4.C, 9, 9);
    MD4.C = MD4.ROUND3(MD4.C, MD4.D, MD4.A, MD4.B, 5, 11);
    MD4.B = MD4.ROUND3(MD4.B, MD4.C, MD4.D, MD4.A, 13, 15);
    MD4.A = MD4.ROUND3(MD4.A, MD4.B, MD4.C, MD4.D, 3, 3);
    MD4.D = MD4.ROUND3(MD4.D, MD4.A, MD4.B, MD4.C, 11, 9);
    MD4.C = MD4.ROUND3(MD4.C, MD4.D, MD4.A, MD4.B, 7, 11);
    MD4.B = MD4.ROUND3(MD4.B, MD4.C, MD4.D, MD4.A, 15, 15);

    MD4.A += AA;
    MD4.B += BB;
    MD4.C += CC;
    MD4.D += DD;

    MD4.A &= 0xFFFFFFFF;
    MD4.B &= 0xFFFFFFFF;
    MD4.C &= 0xFFFFFFFF;
    MD4.D &= 0xFFFFFFFF;
  }

  private static copy64(M: number[], buf: Uint8Array, offset: number) {
    var i: number;

    for (i = 0; i < 16; i++) {
      M[i] = ((buf[offset + i * 4 + 3] << 24) & 0xFF000000)
      | ((buf[offset + i * 4 + 2] << 16) & 0xFF0000)
      | ((buf[offset + i * 4 + 1] << 8) & 0xFF00)
      | ((buf[offset + i * 4 + 0]) & 0xFF);
    }
  }

  private  static copy4(out: Uint8Array, offset: number, x: number) {

    out[offset] = Uint8Array.of(x & 0xFF)[0];
    out[1 + offset] = Uint8Array.of((x >> 8) & 0xFF)[0];
    out[2 + offset] = Uint8Array.of((x >> 16) & 0xFF)[0];
    out[3 + offset] = Uint8Array.of((x >> 24) & 0xFF)[0];
  }

  private  static mdfour(byte: Uint8Array): Uint8Array {
    var out = new Uint8Array(16);
    var buf = new Uint8Array(128);
    var n = byte.length;
    var M = new Array(16);
    var b = n * 8;
    var i;
    var offset;

    MD4.A = 0x67452301;
    MD4.B = 0xefcdab89;
    MD4.C = 0x98badcfe;
    MD4.D = 0x10325476;

    offset = 0;
    while (n > 64) {
      MD4.copy64(M, byte, offset);
      MD4.mdfour64(M);
      offset += 64;
      n -= 64;
    }

    for (i = 0; i < 128; i++) {
      buf[i] = (i + offset < byte.length) ? byte[offset + i] : 0;
    }
    buf[n] = -128;

    if (n <= 55) {
      MD4.copy4(buf, 56, b);
      MD4.copy64(M, buf, 0);
      MD4.mdfour64(M);
    } else {
      MD4.copy4(buf, 120, b);
      MD4.copy64(M, buf, 0);
      MD4.mdfour64(M);
      MD4.copy64(M, buf, 64);
      MD4.mdfour64(M);
    }

    for (i = 0; i < 128; i++) {
      buf[i] = 0;
    }
    MD4.copy64(M, buf, 0);

    MD4.copy4(out, 0, MD4.A);
    MD4.copy4(out, 4, MD4.B);
    MD4.copy4(out, 8, MD4.C);
    MD4.copy4(out, 12, MD4.D);

    MD4.A = MD4.B = MD4.C = MD4.D = 0;
    return out;
  }

  private static stringToUint8Array(str) {
    let arr = [];
    for (let i = 0, j = str.length; i < j; ++i) {
      arr.push(str.charCodeAt(i));
    }
    return new Uint8Array(arr);
  }

  private static getByteOfByte(bytes: Uint8Array): Uint8Array {
    return MD4.mdfour(bytes);
  }

  public static update(data: Buffer) {
    MD4.input = data.toString();
  }

  public static digest() {
    return Buffer.from(MD4.getByteOfByte(MD4.stringToUint8Array(MD4.input)))
  }
}



