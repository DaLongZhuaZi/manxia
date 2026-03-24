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
export default class Base {
    public static kNumRepDistances: number = 4;
    public static kNumStates: number = 12;

    public static StateInit(): number
    {
        return 0;
    }

    public static StateUpdateChar(index: number): number
    {
        if (index < 4)
        return 0;
        if (index < 10)
        return index - 3;
        return index - 6;
    }

    public static StateUpdateMatch(index: number): number
    {
        return (index < 7 ? 7 : 10);
    }

    public static StateUpdateRep(index: number): number
    {
        return (index < 7 ? 8 : 11);
    }

    public static StateUpdateShortRep(index: number): number
    {
        return (index < 7 ? 9 : 11);
    }

    public static StateIsCharState(index: number): boolean
    {
        return index < 7;
    }

    public static kNumPosSlotBits: number = 6;
    public static kDicLogSizeMin: number = 0;
    public static kNumLenToPosStatesBits: number = 2;
    public static kNumLenToPosStates: number = 1 << Base.kNumLenToPosStatesBits;
    public static kMatchMinLen: number = 2;

    public static GetLenToPosState(len: number): number
    {
        len -= Base.kMatchMinLen;
        if (len < Base.kNumLenToPosStates)
        return len;
        return (Base.kNumLenToPosStates - 1);
    }

    public static kNumAlignBits: number = 4;
    public static kAlignTableSize: number = 1 << Base.kNumAlignBits;
    public static kAlignMask: number = (Base.kAlignTableSize - 1);
    public static kStartPosModelIndex: number = 4;
    public static kEndPosModelIndex: number = 14;
    public static kNumPosModels: number = Base.kEndPosModelIndex - Base.kStartPosModelIndex;
    public static kNumFullDistances: number = 1 << (Base.kEndPosModelIndex / 2);
    public static kNumLitPosStatesBitsEncodingMax: number = 4;
    public static kNumLitContextBitsMax: number = 8;
    public static kNumPosStatesBitsMax: number = 4;
    public static kNumPosStatesMax: number = (1 << Base.kNumPosStatesBitsMax);
    public static kNumPosStatesBitsEncodingMax: number = 4;
    public static kNumPosStatesEncodingMax: number = (1 << Base.kNumPosStatesBitsEncodingMax);
    public static kNumLowLenBits: number = 3;
    public static kNumMidLenBits: number = 3;
    public static kNumHighLenBits: number = 8;
    public static kNumLowLenSymbols: number = 1 << Base.kNumLowLenBits;
    public static kNumMidLenSymbols: number = 1 << Base.kNumMidLenBits;
    public static kNumLenSymbols: number = Base.kNumLowLenSymbols + Base.kNumMidLenSymbols +
    (1 << Base.kNumHighLenBits);
    public static kMatchMaxLen: number = Base.kMatchMinLen + Base.kNumLenSymbols - 1;
}
