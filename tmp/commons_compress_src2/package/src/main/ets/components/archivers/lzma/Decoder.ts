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
import InputStream from '../../util/InputStream';
import OutputStream from '../../util/OutputStream';
import OutWindow from './lz/OutWindow';
import BitTreeDecoder from './RangeCoder/BitTreeDecoder';
import RangeCoderDecoder from './RangeCoder/Decoder';
import Base from './Base';
import Long from "../../util/long/index";

export class LenDecoder {
    m_Choice: Int16Array = new Int16Array(2);
    m_LowCoder: BitTreeDecoder[] = new Array<BitTreeDecoder>(Base.kNumPosStatesMax);
    m_MidCoder: BitTreeDecoder[] = new Array<BitTreeDecoder>(Base.kNumPosStatesMax);
    m_HighCoder: BitTreeDecoder = new BitTreeDecoder(Base.kNumHighLenBits);
    m_NumPosStates: number = 0;

    public Create(numPosStates: number): void
    {
        for (; this.m_NumPosStates < numPosStates; this.m_NumPosStates++) {
            this.m_LowCoder[this.m_NumPosStates] = new BitTreeDecoder(Base.kNumLowLenBits);
            this.m_MidCoder[this.m_NumPosStates] = new BitTreeDecoder(Base.kNumMidLenBits);
        }
    }

    public Init(): void
    {
        RangeCoderDecoder.InitBitModels(this.m_Choice);
        for (let posState = 0; posState < this.m_NumPosStates; posState++) {
            this.m_LowCoder[posState].Init();
            this.m_MidCoder[posState].Init();
        }
        this.m_HighCoder.Init();
    }

    public Decode(rangeDecoder: RangeCoderDecoder, posState: number): number
    {
        if (rangeDecoder.DecodeBit(this.m_Choice, 0) == 0)
        return this.m_LowCoder[posState].Decode(rangeDecoder);
        let symbolValue: number = Base.kNumLowLenSymbols;
        if (rangeDecoder.DecodeBit(this.m_Choice, 1) == 0)
        symbolValue += this.m_MidCoder[posState].Decode(rangeDecoder);
        else
        symbolValue += Base.kNumMidLenSymbols + this.m_HighCoder.Decode(rangeDecoder);
        return symbolValue;
    }
}

class Decoder2 {
    m_Decoders: Int16Array = new Int16Array(0x300);

    public Init(): void
    {
        RangeCoderDecoder.InitBitModels(this.m_Decoders);
    }

    public DecodeNormal(rangeDecoder: RangeCoderDecoder): number
    {
        let symbolValue: number = 1;
        do
        symbolValue = (symbolValue << 1) | rangeDecoder.DecodeBit(this.m_Decoders, symbolValue);
        while (symbolValue < 0x100);
        return symbolValue;
    }

    public DecodeWithMatchByte(rangeDecoder: RangeCoderDecoder, matchByte: number): number
    {
        let symbolValue: number = 1;
        do
        {
            let matchBit: number = (matchByte >> 7) & 1;
            matchByte <<= 1;
            let bit: number = rangeDecoder.DecodeBit(this.m_Decoders, ((1 + matchBit) << 8) + symbolValue);
            symbolValue = (symbolValue << 1) | bit;
            if (matchBit != bit) {
                while (symbolValue < 0x100)
                symbolValue = (symbolValue << 1) | rangeDecoder.DecodeBit(this.m_Decoders, symbolValue);
                break;
            }
        }
        while (symbolValue < 0x100);
        return symbolValue;
    }
}

class LiteralDecoder {
    m_Coders: Decoder2[];
    m_NumPrevBits: number;
    m_NumPosBits: number;
    m_PosMask: number;

    public Create(numPosBits: number, numPrevBits: number): void
    {
        if (this.m_Coders != null && this.m_NumPrevBits == numPrevBits && this.m_NumPosBits == numPosBits)
        return;
        this.m_NumPosBits = numPosBits;
        this.m_PosMask = (1 << numPosBits) - 1;
        this.m_NumPrevBits = numPrevBits;
        let numStates: number = 1 << (this.m_NumPrevBits + this.m_NumPosBits);
        this.m_Coders = new Array<Decoder2>(numStates);
        for (let i = 0; i < numStates; i++)
        this.m_Coders[i] = new Decoder2();
    }

    public Init(): void
    {
        let numStates: number = 1 << (this.m_NumPrevBits + this.m_NumPosBits);
        for (let i = 0; i < numStates; i++)
        this.m_Coders[i].Init();
    }

    GetDecoder(pos: number, prevByte: number): Decoder2
    {
        return this.m_Coders[((pos & this.m_PosMask) << this.m_NumPrevBits) + ((prevByte & 0xFF) >>> (8 - this.m_NumPrevBits))];
    }
}

export default class Decoder {
    m_OutWindow: OutWindow = new OutWindow();
    m_RangeDecoder: RangeCoderDecoder = new RangeCoderDecoder();
    m_IsMatchDecoders: Int16Array = new Int16Array(Base.kNumStates << Base.kNumPosStatesBitsMax);
    m_IsRepDecoders: Int16Array = new Int16Array(Base.kNumStates);
    m_IsRepG0Decoders: Int16Array = new Int16Array(Base.kNumStates);
    m_IsRepG1Decoders: Int16Array = new Int16Array(Base.kNumStates);
    m_IsRepG2Decoders: Int16Array = new Int16Array(Base.kNumStates);
    m_IsRep0LongDecoders: Int16Array = new Int16Array(Base.kNumStates << Base.kNumPosStatesBitsMax);
    m_PosSlotDecoder: BitTreeDecoder[] = new Array<BitTreeDecoder>(Base.kNumLenToPosStates);
    m_PosDecoders: Int16Array = new Int16Array(Base.kNumFullDistances - Base.kEndPosModelIndex);
    m_PosAlignDecoder: BitTreeDecoder = new BitTreeDecoder(Base.kNumAlignBits);
    m_LenDecoder: LenDecoder = new LenDecoder();
    m_RepLenDecoder: LenDecoder = new LenDecoder();
    m_LiteralDecoder: LiteralDecoder = new LiteralDecoder();
    m_DictionarySize: number = -1;
    m_DictionarySizeCheck: number = -1;
    m_PosStateMask: number;

    constructor() {
        for (let i = 0; i < Base.kNumLenToPosStates; i++)
        this.m_PosSlotDecoder[i] = new BitTreeDecoder(Base.kNumPosSlotBits);
    }

    public SetDictionarySize(dictionarySize: number): boolean
    {
        if (dictionarySize < 0)
        return false;
        if (this.m_DictionarySize != dictionarySize) {
            this.m_DictionarySize = dictionarySize;
            this.m_DictionarySizeCheck = Math.max(this.m_DictionarySize, 1);
            this.m_OutWindow.Create(Math.max(this.m_DictionarySizeCheck, (1 << 12)));
        }
        return true;
    }

    public SetLcLpPb(lc: number, lp: number, pb: number) {
        if (lc > Base.kNumLitContextBitsMax || lp > 4 || pb > Base.kNumPosStatesBitsMax)
        return false;
        this.m_LiteralDecoder.Create(lp, lc);
        let numPosStates: number = 1 << pb;
        this.m_LenDecoder.Create(numPosStates);
        this.m_RepLenDecoder.Create(numPosStates);
        this.m_PosStateMask = numPosStates - 1;
        return true;
    }

    Init(): void
    {
        this.m_OutWindow.Init(false);

        RangeCoderDecoder.InitBitModels(this.m_IsMatchDecoders);
        RangeCoderDecoder.InitBitModels(this.m_IsRep0LongDecoders);
        RangeCoderDecoder.InitBitModels(this.m_IsRepDecoders);
        RangeCoderDecoder.InitBitModels(this.m_IsRepG0Decoders);
        RangeCoderDecoder.InitBitModels(this.m_IsRepG1Decoders);
        RangeCoderDecoder.InitBitModels(this.m_IsRepG2Decoders);
        RangeCoderDecoder.InitBitModels(this.m_PosDecoders);

        this.m_LiteralDecoder.Init();
        let i: number;
        for (i = 0; i < Base.kNumLenToPosStates; i++)
        this.m_PosSlotDecoder[i].Init();
        this.m_LenDecoder.Init();
        this.m_RepLenDecoder.Init();
        this.m_PosAlignDecoder.Init();
        this.m_RangeDecoder.Init();
    }

    public Code(inStream: InputStream, outStream: OutputStream,
                outSize: Long): boolean
    {
        this.m_RangeDecoder.SetStream(inStream);
        this.m_OutWindow.SetStream(outStream);
        this.Init();

        let state: number = Base.StateInit();
        let rep0 = 0, rep1 = 0, rep2 = 0, rep3 = 0;

        let nowPos64: number = 0;
        let prevByte: number = 0;
        while (outSize.lessThan(0) || outSize.gt(nowPos64)) {
            let posState: number = parseInt((nowPos64 & this.m_PosStateMask) + '');
            if (this.m_RangeDecoder.DecodeBit(this.m_IsMatchDecoders, (state << Base.kNumPosStatesBitsMax) + posState) == 0) {
                let decoder2: Decoder2 = this.m_LiteralDecoder.GetDecoder(parseInt(nowPos64 + ''), prevByte);
                if (!Base.StateIsCharState(state))
                prevByte = decoder2.DecodeWithMatchByte(this.m_RangeDecoder, this.m_OutWindow.GetByte(rep0));
                else
                prevByte = decoder2.DecodeNormal(this.m_RangeDecoder);
                this.m_OutWindow.PutByte(prevByte);
                state = Base.StateUpdateChar(state);
                nowPos64++;
            }
            else {
                let len: number;
                if (this.m_RangeDecoder.DecodeBit(this.m_IsRepDecoders, state) == 1) {
                    len = 0;
                    if (this.m_RangeDecoder.DecodeBit(this.m_IsRepG0Decoders, state) == 0) {
                        if (this.m_RangeDecoder.DecodeBit(this.m_IsRep0LongDecoders, (state << Base.kNumPosStatesBitsMax) + posState) == 0) {
                            state = Base.StateUpdateShortRep(state);
                            len = 1;
                        }
                    }
                    else {
                        let distance: number;
                        if (this.m_RangeDecoder.DecodeBit(this.m_IsRepG1Decoders, state) == 0)
                        distance = rep1;
                        else {
                            if (this.m_RangeDecoder.DecodeBit(this.m_IsRepG2Decoders, state) == 0)
                            distance = rep2;
                            else {
                                distance = rep3;
                                rep3 = rep2;
                            }
                            rep2 = rep1;
                        }
                        rep1 = rep0;
                        rep0 = distance;
                    }
                    if (len == 0) {
                        len = this.m_RepLenDecoder.Decode(this.m_RangeDecoder, posState) + Base.kMatchMinLen;
                        state = Base.StateUpdateRep(state);
                    }
                }
                else {
                    rep3 = rep2;
                    rep2 = rep1;
                    rep1 = rep0;
                    len = Base.kMatchMinLen + this.m_LenDecoder.Decode(this.m_RangeDecoder, posState);
                    state = Base.StateUpdateMatch(state);
                    let posSlot: number = this.m_PosSlotDecoder[Base.GetLenToPosState(len)].Decode(this.m_RangeDecoder);
                    if (posSlot >= Base.kStartPosModelIndex) {
                        let numDirectBits: number = (posSlot >> 1) - 1;
                        rep0 = ((2 | (posSlot & 1)) << numDirectBits);
                        if (posSlot < Base.kEndPosModelIndex)
                        rep0 += BitTreeDecoder.ReverseDecode(this.m_PosDecoders,
                            rep0 - posSlot - 1, this.m_RangeDecoder, numDirectBits);
                        else {
                            rep0 += (this.m_RangeDecoder.DecodeDirectBits(
                                numDirectBits - Base.kNumAlignBits) << Base.kNumAlignBits);
                            rep0 += this.m_PosAlignDecoder.ReverseDecode(this.m_RangeDecoder);
                            if (rep0 < 0) {
                                if (rep0 == -1)
                                break;
                                return false;
                            }
                        }
                    }
                    else
                    rep0 = posSlot;
                }
                if (rep0 >= nowPos64 || rep0 >= this.m_DictionarySizeCheck) {
                    // m_OutWindow.Flush();
                    return false;
                }
                this.m_OutWindow.CopyBlock(rep0, len);
                nowPos64 += len;
                prevByte = this.m_OutWindow.GetByte(0);
            }
        }
        this.m_OutWindow.Flush();
        this.m_OutWindow.ReleaseStream();
        this.m_RangeDecoder.ReleaseStream();
        return true;
    }

    public SetDecoderProperties(properties: Int8Array): boolean
    {
        if (properties.length < 5)
        return false;
        let val: number = properties[0] & 0xFF;
        let lc: number = val % 9;
        let remainder: number = val / 9;
        let lp: number = remainder % 5;
        let pb: number = remainder / 5;
        let dictionarySize: number = 0;
        for (let i = 0; i < 4; i++)
        dictionarySize += (parseInt(properties[1 + i] + '') & 0xFF) << (i * 8);
        if (!this.SetLcLpPb(lc, lp, pb))
        return false;
        return this.SetDictionarySize(dictionarySize);
    }
}