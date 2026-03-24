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
import RangeCoderEncoder from './RangeCoder/Encoder';
import BitTreeEncoder from './RangeCoder/BitTreeEncoder';
import Base from './Base';
import BinTree from './lz/BinTree';
import InputStream from '../../util/InputStream';
import OutputStream from '../../util/OutputStream';
import type ICodeProgress from './ICodeProgress';
import Long from "../../util/long/index";

export class Encoder2 {
    m_Encoders: Int16Array = new Int16Array(0x300);

    public Init(): void {
        RangeCoderEncoder.InitBitModels(this.m_Encoders);
    }

    public Encode(rangeEncoder: RangeCoderEncoder, symbol: number): void
    {
        let context: number = 1;
        for (let i = 7; i >= 0; i--) {
            let bit: number = ((symbol >> i) & 1);
            rangeEncoder.Encode(this.m_Encoders, context, bit);
            context = (context << 1) | bit;
        }
    }

    public EncodeMatched(rangeEncoder: RangeCoderEncoder, matchByte: number, symbol: number): void
    {
        let context: number = 1;
        let same: boolean = true;
        for (let i = 7; i >= 0; i--) {
            let bit: number = ((symbol >> i) & 1);
            let state: number = context;
            if (same) {
                let matchBit: number = ((matchByte >> i) & 1);
                state += ((1 + matchBit) << 8);
                same = (matchBit == bit);
            }
            rangeEncoder.Encode(this.m_Encoders, state, bit);
            context = (context << 1) | bit;
        }
    }

    public GetPrice(matchMode: boolean, matchByte: number, symbol: number): number
    {
        let price: number = 0;
        let context: number = 1;
        let i: number = 7;
        if (matchMode) {
            for (; i >= 0; i--) {
                let matchBit: number = (matchByte >> i) & 1;
                let bit: number = (symbol >> i) & 1;
                price += RangeCoderEncoder.GetPrice(this.m_Encoders[((1 + matchBit) << 8) + context], bit);
                context = (context << 1) | bit;
                if (matchBit != bit) {
                    i--;
                    break;
                }
            }
        }
        for (; i >= 0; i--) {
            let bit: number = (symbol >> i) & 1;
            price += RangeCoderEncoder.GetPrice(this.m_Encoders[context], bit);
            context = (context << 1) | bit;
        }
        return price;
    }
}

class LiteralEncoder {
    m_Coders: Encoder2[];
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
        this.m_Coders = new Array<Encoder2>(numStates);
        for (let i = 0; i < numStates; i++)
        this.m_Coders[i] = new Encoder2();
    }

    public Init(): void
    {
        let numStates: number = 1 << (this.m_NumPrevBits + this.m_NumPosBits);
        for (let i = 0; i < numStates; i++)
        this.m_Coders[i].Init();
    }

    public GetSubCoder(pos: number, prevByte: number): Encoder2
    {
        return this.m_Coders[((pos & this.m_PosMask) << this.m_NumPrevBits) + ((prevByte & 0xFF) >>> (8 - this.m_NumPrevBits))];
    }
}

class LenEncoder {
    _choice: Int16Array = new Int16Array(2);
    _lowCoder: BitTreeEncoder[] = new Array<BitTreeEncoder>(Base.kNumPosStatesEncodingMax);
    _midCoder: BitTreeEncoder[] = new Array<BitTreeEncoder>(Base.kNumPosStatesEncodingMax);
    _highCoder: BitTreeEncoder = new BitTreeEncoder(Base.kNumHighLenBits);

    constructor() {
        for (let posState = 0; posState < Base.kNumPosStatesEncodingMax; posState++) {
            this._lowCoder[posState] = new BitTreeEncoder(Base.kNumLowLenBits);
            this._midCoder[posState] = new BitTreeEncoder(Base.kNumMidLenBits);
        }
    }

    public Init(numPosStates: number): void
    {
        RangeCoderEncoder.InitBitModels(this._choice);
        for (let posState = 0; posState < numPosStates; posState++) {
            this._lowCoder[posState].Init();
            this._midCoder[posState].Init();
        }
        this._highCoder.Init();
    }

    public Encode(rangeEncoder: RangeCoderEncoder, symbol: number, posState: number): void
    {
        if (symbol < Base.kNumLowLenSymbols) {
            rangeEncoder.Encode(this._choice, 0, 0);
            this._lowCoder[posState].Encode(rangeEncoder, symbol);
        }
        else {
            symbol -= Base.kNumLowLenSymbols;
            rangeEncoder.Encode(this._choice, 0, 1);
            if (symbol < Base.kNumMidLenSymbols) {
                rangeEncoder.Encode(this._choice, 1, 0);
                this._midCoder[posState].Encode(rangeEncoder, symbol);
            }
            else {
                rangeEncoder.Encode(this._choice, 1, 1);
                this._highCoder.Encode(rangeEncoder, symbol - Base.kNumMidLenSymbols);
            }
        }
    }

    public SetPrices(posState: number, numSymbols: number, prices: Int32Array, st: number): void
    {
        let a0: number = RangeCoderEncoder.GetPriceReducingBits(this._choice[0]);
        let a1: number = RangeCoderEncoder.GetPriceModelTotal(this._choice[0]);
        let b0: number = a1 + RangeCoderEncoder.GetPriceReducingBits(this._choice[1]);
        let b1: number = a1 + RangeCoderEncoder.GetPriceModelTotal(this._choice[1]);
        let i: number = 0;
        for (i = 0; i < Base.kNumLowLenSymbols; i++) {
            if (i >= numSymbols)
            return;
            prices[st + i] = a0 + this._lowCoder[posState].GetPrice(i);
        }
        for (; i < Base.kNumLowLenSymbols + Base.kNumMidLenSymbols; i++) {
            if (i >= numSymbols)
            return;
            prices[st + i] = b0 + this._midCoder[posState].GetPrice(i - Base.kNumLowLenSymbols);
        }
        for (; i < numSymbols; i++)
        prices[st + i] = b1 + this._highCoder.GetPrice(i - Base.kNumLowLenSymbols - Base.kNumMidLenSymbols);
    }
}

class LenPriceTableEncoder extends LenEncoder {
    _prices: Int32Array = new Int32Array(Base.kNumLenSymbols << Base.kNumPosStatesBitsEncodingMax);
    _tableSize: number;
    _counters: Int32Array = new Int32Array(Base.kNumPosStatesEncodingMax);

    public SetTableSize(tableSize: number): void {
        this._tableSize = tableSize;
    }

    public GetPrice(symbol: number, posState: number): number
    {
        return this._prices[posState * Base.kNumLenSymbols + symbol];
    }

    UpdateTable(posState: number): void
    {
        this.SetPrices(posState, this._tableSize, this._prices, posState * Base.kNumLenSymbols);
        this._counters[posState] = this._tableSize;
    }

    public UpdateTables(numPosStates: number): void
    {
        for (let posState = 0; posState < numPosStates; posState++)
        this.UpdateTable(posState);
    }

    public Encode(rangeEncoder: RangeCoderEncoder, symbol: number, posState: number): void
    {
        super.Encode(rangeEncoder, symbol, posState);
        if (--this._counters[posState] == 0)
        this.UpdateTable(posState);
    }
}

class Optimal {
    public State: number;
    public Prev1IsChar: boolean;
    public Prev2: boolean;
    public PosPrev2: number;
    public BackPrev2: number;
    public Price: number;
    public PosPrev: number;
    public BackPrev: number;
    public Backs0: number;
    public Backs1: number;
    public Backs2: number;
    public Backs3: number;

    public MakeAsChar(): void {
        this.BackPrev = -1;
        this.Prev1IsChar = false;
    }

    public MakeAsShortRep(): void {
        this.BackPrev = 0;
        this.Prev1IsChar = false;
    }

    public IsShortRep(): boolean {
        return (this.BackPrev == 0);
    }
}


export default class Encoder {
    public static EMatchFinderTypeBT2: number = 0;
    public static EMatchFinderTypeBT4: number = 1;
    static kIfinityPrice: number = 0xFFFFFFF;
    static g_FastPos: Int8Array = new Int8Array(1 << 11);

    public static staticInit(): void {
        let kFastSlots: number = 22;
        let c: number = 2;
        Encoder.g_FastPos[0] = 0;
        Encoder.g_FastPos[1] = 1;
        for (let slotFast = 2; slotFast < kFastSlots; slotFast++) {
            let k: number = (1 << ((slotFast >> 1) - 1));
            for (let j = 0; j < k; j++, c++)
            Encoder.g_FastPos[c] = slotFast;
        }
    }

    static GetPosSlot(pos: number): number
    {
        if (pos < (1 << 11))
        return Encoder.g_FastPos[pos];
        if (pos < (1 << 21))
        return (Encoder.g_FastPos[pos >> 10] + 20);
        return (Encoder.g_FastPos[pos >> 20] + 40);
    }

    static GetPosSlot2(pos: number): number
    {
        if (pos < (1 << 17))
        return (Encoder.g_FastPos[pos >> 6] + 12);
        if (pos < (1 << 27))
        return (Encoder.g_FastPos[pos >> 16] + 32);
        return (Encoder.g_FastPos[pos >> 26] + 52);
    }

    _state: number = Base.StateInit();
    _previousByte: number;
    _repDistances: Int32Array = new Int32Array(Base.kNumRepDistances);

    BaseInit(): void
    {
        this._state = Base.StateInit();
        this._previousByte = 0;
        for (let i = 0; i < Base.kNumRepDistances; i++)
        this._repDistances[i] = 0;
    }

    static kDefaultDictionaryLogSize: number = 22;
    static kNumFastBytesDefault: number = 0x20;
    public static kNumLenSpecSymbols: number = Base.kNumLowLenSymbols + Base.kNumMidLenSymbols;
    static kNumOpts: number = 1 << 12;
    _optimum: Optimal[] = new Array<Optimal>(Encoder.kNumOpts);
    _matchFinder: BinTree = null;
    _rangeEncoder: RangeCoderEncoder = new RangeCoderEncoder();
    _isMatch: Int16Array = new Int16Array(Base.kNumStates << Base.kNumPosStatesBitsMax);
    _isRep: Int16Array = new Int16Array(Base.kNumStates);
    _isRepG0: Int16Array = new Int16Array(Base.kNumStates);
    _isRepG1: Int16Array = new Int16Array(Base.kNumStates);
    _isRepG2: Int16Array = new Int16Array(Base.kNumStates);
    _isRep0Long: Int16Array = new Int16Array(Base.kNumStates << Base.kNumPosStatesBitsMax);
    _posSlotEncoder: BitTreeEncoder[] = new Array<BitTreeEncoder>(Base.kNumLenToPosStates); // kNumPosSlotBits

    _posEncoders: Int16Array = new Int16Array(Base.kNumFullDistances - Base.kEndPosModelIndex);
    _posAlignEncoder: BitTreeEncoder = new BitTreeEncoder(Base.kNumAlignBits);
    _lenEncoder: LenPriceTableEncoder = new LenPriceTableEncoder();
    _repMatchLenEncoder: LenPriceTableEncoder = new LenPriceTableEncoder();
    _literalEncoder: LiteralEncoder = new LiteralEncoder();
    _matchDistances: Int32Array = new Int32Array(Base.kMatchMaxLen * 2 + 2);
    _numFastBytes: number = Encoder.kNumFastBytesDefault;
    _longestMatchLength: number;
    _numDistancePairs: number;
    _additionalOffset: number;
    _optimumEndIndex: number;
    _optimumCurrentIndex: number;
    _longestMatchWasFound: boolean;
    _posSlotPrices: Int32Array = new Int32Array(1 << (Base.kNumPosSlotBits + Base.kNumLenToPosStatesBits));
    _distancesPrices: Int32Array = new Int32Array(Base.kNumFullDistances << Base.kNumLenToPosStatesBits);
    _alignPrices: Int32Array = new Int32Array(Base.kAlignTableSize);
    _alignPriceCount: number;
    _distTableSize: number = (Encoder.kDefaultDictionaryLogSize * 2);
    _posStateBits: number = 2;
    _posStateMask: number = (4 - 1);
    _numLiteralPosStateBits: number = 0;
    _numLiteralContextBits: number = 3;
    _dictionarySize: number = (1 << Encoder.kDefaultDictionaryLogSize);
    _dictionarySizePrev: number = -1;
    _numFastBytesPrev: number = -1;
    nowPos64: Long;
    _finished: boolean;
    _inStream: InputStream;
    _matchFinderType: number = Encoder.EMatchFinderTypeBT4;
    _writeEndMark: boolean = false;
    _needReleaseMFStream: boolean = false;

    Create(): void
    {
        if (this._matchFinder == null) {
            let bt: BinTree = new BinTree();
            let numHashBytes: number = 4;
            if (this._matchFinderType == Encoder.EMatchFinderTypeBT2)
            numHashBytes = 2;
            bt.SetType(numHashBytes);
            this._matchFinder = bt;
        }
        this._literalEncoder.Create(this._numLiteralPosStateBits, this._numLiteralContextBits);

        if (this._dictionarySize == this._dictionarySizePrev && this._numFastBytesPrev == this._numFastBytes)
        return;
        this._matchFinder.BinTreeCreate(this._dictionarySize, Encoder.kNumOpts, this._numFastBytes, Base.kMatchMaxLen + 1);
        this._dictionarySizePrev = this._dictionarySize;
        this._numFastBytesPrev = this._numFastBytes;
    }

    constructor() {
        for (let i = 0; i < Encoder.kNumOpts; i++)
        this._optimum[i] = new Optimal();
        for (let i = 0; i < Base.kNumLenToPosStates; i++)
        this._posSlotEncoder[i] = new BitTreeEncoder(Base.kNumPosSlotBits);
    }

    SetWriteEndMarkerMode(writeEndMarker: boolean): void
    {
        this._writeEndMark = writeEndMarker;
    }

    Init(): void
    {
        this.BaseInit();
        this._rangeEncoder.Init();

        RangeCoderEncoder.InitBitModels(this._isMatch);
        RangeCoderEncoder.InitBitModels(this._isRep0Long);
        RangeCoderEncoder.InitBitModels(this._isRep);
        RangeCoderEncoder.InitBitModels(this._isRepG0);
        RangeCoderEncoder.InitBitModels(this._isRepG1);
        RangeCoderEncoder.InitBitModels(this._isRepG2);
        RangeCoderEncoder.InitBitModels(this._posEncoders);


        this._literalEncoder.Init();
        for (let i = 0; i < Base.kNumLenToPosStates; i++)
        this._posSlotEncoder[i].Init();


        this._lenEncoder.Init(1 << this._posStateBits);
        this._repMatchLenEncoder.Init(1 << this._posStateBits);

        this._posAlignEncoder.Init();

        this._longestMatchWasFound = false;
        this._optimumEndIndex = 0;
        this._optimumCurrentIndex = 0;
        this._additionalOffset = 0;
    }

    ReadMatchDistances(): number
    {
        let lenRes: number = 0;
        this._numDistancePairs = this._matchFinder.GetMatches(this._matchDistances);
        if (this._numDistancePairs > 0) {
            lenRes = this._matchDistances[this._numDistancePairs - 2];
            if (lenRes == this._numFastBytes)
            lenRes += this._matchFinder.GetMatchLen(parseInt((lenRes - 1) + ''), this._matchDistances[this._numDistancePairs - 1],
                Base.kMatchMaxLen - lenRes);
        }
        this._additionalOffset++;
        return lenRes;
    }

    MovePos(num: number): void
    {
        if (num > 0) {
            this._matchFinder.Skip(num);
            this._additionalOffset += num;
        }
    }

    GetRepLen1Price(state: number, posState: number): number
    {
        return RangeCoderEncoder.GetPriceReducingBits(this._isRepG0[state]) +
        RangeCoderEncoder.GetPriceReducingBits(this._isRep0Long[(state << Base.kNumPosStatesBitsMax) + posState]);
    }

    GetPureRepPrice(repIndex: number, state: number, posState: number): number
    {
        let price: number;
        if (repIndex == 0) {
            price = RangeCoderEncoder.GetPriceReducingBits(this._isRepG0[state]);
            price += RangeCoderEncoder.GetPriceModelTotal(this._isRep0Long[(state << Base.kNumPosStatesBitsMax) + posState]);
        }
        else {
            price = RangeCoderEncoder.GetPriceModelTotal(this._isRepG0[state]);
            if (repIndex == 1)
            price += RangeCoderEncoder.GetPriceReducingBits(this._isRepG1[state]);
            else {
                price += RangeCoderEncoder.GetPriceModelTotal(this._isRepG1[state]);
                price += RangeCoderEncoder.GetPrice(this._isRepG2[state], repIndex - 2);
            }
        }
        return price;
    }

    GetRepPrice(repIndex: number, len: number, state: number, posState: number): number
    {
        let price: number = this._repMatchLenEncoder.GetPrice(len - Base.kMatchMinLen, posState);
        return price + this.GetPureRepPrice(repIndex, state, posState);
    }

    GetPosLenPrice(pos: number, len: number, posState: number): number
    {
        let price: number;
        let lenToPosState: number = Base.GetLenToPosState(len);
        if (pos < Base.kNumFullDistances)
        price = this._distancesPrices[(lenToPosState * Base.kNumFullDistances) + pos];
        else
        price = this._posSlotPrices[(lenToPosState << Base.kNumPosSlotBits) + Encoder.GetPosSlot2(pos)] +
        this._alignPrices[pos & Base.kAlignMask];
        return price + this._lenEncoder.GetPrice(len - Base.kMatchMinLen, posState);
    }

    Backward(cur: number): number
    {
        this._optimumEndIndex = cur;
        let posMem: number = this._optimum[cur].PosPrev;
        let backMem: number = this._optimum[cur].BackPrev;
        do
        {
            if (this._optimum[cur].Prev1IsChar) {
                this._optimum[posMem].MakeAsChar();
                this._optimum[posMem].PosPrev = posMem - 1;
                if (this._optimum[cur].Prev2) {
                    this._optimum[posMem - 1].Prev1IsChar = false;
                    this._optimum[posMem - 1].PosPrev = this._optimum[cur].PosPrev2;
                    this._optimum[posMem - 1].BackPrev = this._optimum[cur].BackPrev2;
                }
            }
            let posPrev: number = posMem;
            let backCur: number = backMem;

            backMem = this._optimum[posPrev].BackPrev;
            posMem = this._optimum[posPrev].PosPrev;

            this._optimum[posPrev].BackPrev = backCur;
            this._optimum[posPrev].PosPrev = cur;
            cur = posPrev;
        }
        while (cur > 0);
        this.backRes = this._optimum[0].BackPrev;
        this._optimumCurrentIndex = this._optimum[0].PosPrev;
        return this._optimumCurrentIndex;
    }

    reps: Int32Array = new Int32Array(Base.kNumRepDistances);
    repLens: Int32Array = new Int32Array(Base.kNumRepDistances);
    backRes: number;

    GetOptimum(position: number): number
    {
        if (this._optimumEndIndex != this._optimumCurrentIndex) {
            let lenRes: number = this._optimum[this._optimumCurrentIndex].PosPrev - this._optimumCurrentIndex;
            this.backRes = this._optimum[this._optimumCurrentIndex].BackPrev;
            this._optimumCurrentIndex = this._optimum[this._optimumCurrentIndex].PosPrev;
            return lenRes;
        }
        this._optimumCurrentIndex = this._optimumEndIndex = 0;

        let lenMain: number, numDistancePairs: number;
        if (!this._longestMatchWasFound) {
            lenMain = this.ReadMatchDistances();
        }
        else {
            lenMain = this._longestMatchLength;
            this._longestMatchWasFound = false;
        }
        numDistancePairs = this._numDistancePairs;

        let numAvailableBytes: number = this._matchFinder.GetNumAvailableBytes() + 1;
        if (numAvailableBytes < 2) {
            this.backRes = -1;
            return 1;
        }
        if (numAvailableBytes > Base.kMatchMaxLen)
        numAvailableBytes = Base.kMatchMaxLen;

        let repMaxIndex: number = 0;
        let i: number;
        for (i = 0; i < Base.kNumRepDistances; i++) {
            this.reps[i] = this._repDistances[i];
            this.repLens[i] = this._matchFinder.GetMatchLen(0 - 1, this.reps[i], Base.kMatchMaxLen);
            if (this.repLens[i] > this.repLens[repMaxIndex])
            repMaxIndex = i;
        }
        if (this.repLens[repMaxIndex] >= this._numFastBytes) {
            this.backRes = repMaxIndex;
            let lenRes: number = this.repLens[repMaxIndex];
            this.MovePos(lenRes - 1);
            return lenRes;
        }

        if (lenMain >= this._numFastBytes) {
            this.backRes = this._matchDistances[numDistancePairs - 1] + Base.kNumRepDistances;
            this.MovePos(lenMain - 1);
            return lenMain;
        }

        let currentByte: number = this._matchFinder.GetIndexByte(0 - 1);
        let matchByte: number = this._matchFinder.GetIndexByte(0 - this._repDistances[0] - 1 - 1);

        if (lenMain < 2 && currentByte != matchByte && this.repLens[repMaxIndex] < 2) {
            this.backRes = -1;
            return 1;
        }

        this._optimum[0].State = this._state;

        let posState: number = (position & this._posStateMask);

        this._optimum[1].Price = RangeCoderEncoder.GetPriceReducingBits(this._isMatch[(this._state << Base.kNumPosStatesBitsMax) + posState]) +
        this._literalEncoder.GetSubCoder(position, this._previousByte).GetPrice(!Base.StateIsCharState(this._state), matchByte, currentByte);
        this._optimum[1].MakeAsChar();

        let matchPrice: number = RangeCoderEncoder.GetPriceModelTotal(this._isMatch[(this._state << Base.kNumPosStatesBitsMax) + posState]);
        let repMatchPrice: number = matchPrice + RangeCoderEncoder.GetPriceModelTotal(this._isRep[this._state]);

        if (matchByte == currentByte) {
            let shortRepPrice: number = repMatchPrice + this.GetRepLen1Price(this._state, posState);
            if (shortRepPrice < this._optimum[1].Price) {
                this._optimum[1].Price = shortRepPrice;
                this._optimum[1].MakeAsShortRep();
            }
        }

        let lenEnd: number = ((lenMain >= this.repLens[repMaxIndex]) ? lenMain : this.repLens[repMaxIndex]);

        if (lenEnd < 2) {
            this.backRes = this._optimum[1].BackPrev;
            return 1;
        }

        this._optimum[1].PosPrev = 0;

        this._optimum[0].Backs0 = this.reps[0];
        this._optimum[0].Backs1 = this.reps[1];
        this._optimum[0].Backs2 = this.reps[2];
        this._optimum[0].Backs3 = this.reps[3];

        let len: number = lenEnd;
        do
        this._optimum[len--].Price = Encoder.kIfinityPrice;
        while (len >= 2);

        for (i = 0; i < Base.kNumRepDistances; i++) {
            let repLen: number = this.repLens[i];
            if (repLen < 2)
            continue;
            let price: number = repMatchPrice + this.GetPureRepPrice(i, this._state, posState);
            do
            {
                let curAndLenPrice: number = price + this._repMatchLenEncoder.GetPrice(repLen - 2, posState);
                let optimum: Optimal = this._optimum[repLen];
                if (curAndLenPrice < optimum.Price) {
                    optimum.Price = curAndLenPrice;
                    optimum.PosPrev = 0;
                    optimum.BackPrev = i;
                    optimum.Prev1IsChar = false;
                }
            }
            while (--repLen >= 2);
        }

        let normalMatchPrice: number = matchPrice + RangeCoderEncoder.GetPriceReducingBits(this._isRep[this._state]);

        len = ((this.repLens[0] >= 2) ? this.repLens[0] + 1 : 2);
        if (len <= lenMain) {
            let offs: number = 0;
            while (len > this._matchDistances[offs])
            offs += 2;
            for (;; len++) {
                let distance: number = this._matchDistances[offs + 1];
                let curAndLenPrice: number = normalMatchPrice + this.GetPosLenPrice(distance, len, posState);
                let optimum: Optimal = this._optimum[len];
                if (curAndLenPrice < optimum.Price) {
                    optimum.Price = curAndLenPrice;
                    optimum.PosPrev = 0;
                    optimum.BackPrev = distance + Base.kNumRepDistances;
                    optimum.Prev1IsChar = false;
                }
                if (len == this._matchDistances[offs]) {
                    offs += 2;
                    if (offs == numDistancePairs)
                    break;
                }
            }
        }

        let cur: number = 0;

        while (true) {
            cur++;
            if (cur == lenEnd)
            return this.Backward(cur);
            let newLen: number = this.ReadMatchDistances();
            numDistancePairs = this._numDistancePairs;
            if (newLen >= this._numFastBytes) {

                this._longestMatchLength = newLen;
                this._longestMatchWasFound = true;
                return this.Backward(cur);
            }
            position++;
            let posPrev: number = this._optimum[cur].PosPrev;
            let state: number;
            if (this._optimum[cur].Prev1IsChar) {
                posPrev--;
                if (this._optimum[cur].Prev2) {
                    state = this._optimum[this._optimum[cur].PosPrev2].State;
                    if (this._optimum[cur].BackPrev2 < Base.kNumRepDistances)
                    state = Base.StateUpdateRep(state);
                    else
                    state = Base.StateUpdateMatch(state);
                }
                else
                state = this._optimum[posPrev].State;
                state = Base.StateUpdateChar(state);
            }
            else
            state = this._optimum[posPrev].State;
            if (posPrev == cur - 1) {
                if (this._optimum[cur].IsShortRep())
                state = Base.StateUpdateShortRep(state);
                else
                state = Base.StateUpdateChar(state);
            }
            else {
                let pos: number;
                if (this._optimum[cur].Prev1IsChar && this._optimum[cur].Prev2) {
                    posPrev = this._optimum[cur].PosPrev2;
                    pos = this._optimum[cur].BackPrev2;
                    state = Base.StateUpdateRep(state);
                }
                else {
                    pos = this._optimum[cur].BackPrev;
                    if (pos < Base.kNumRepDistances)
                    state = Base.StateUpdateRep(state);
                    else
                    state = Base.StateUpdateMatch(state);
                }
                let opt: Optimal = this._optimum[posPrev];
                if (pos < Base.kNumRepDistances) {
                    if (pos == 0) {
                        this.reps[0] = opt.Backs0;
                        this.reps[1] = opt.Backs1;
                        this.reps[2] = opt.Backs2;
                        this.reps[3] = opt.Backs3;
                    }
                    else if (pos == 1) {
                        this.reps[0] = opt.Backs1;
                        this.reps[1] = opt.Backs0;
                        this.reps[2] = opt.Backs2;
                        this.reps[3] = opt.Backs3;
                    }
                    else if (pos == 2) {
                        this.reps[0] = opt.Backs2;
                        this.reps[1] = opt.Backs0;
                        this.reps[2] = opt.Backs1;
                        this.reps[3] = opt.Backs3;
                    }
                    else {
                        this.reps[0] = opt.Backs3;
                        this.reps[1] = opt.Backs0;
                        this.reps[2] = opt.Backs1;
                        this.reps[3] = opt.Backs2;
                    }
                }
                else {
                    this.reps[0] = (pos - Base.kNumRepDistances);
                    this.reps[1] = opt.Backs0;
                    this.reps[2] = opt.Backs1;
                    this.reps[3] = opt.Backs2;
                }
            }
            this._optimum[cur].State = state;
            this._optimum[cur].Backs0 = this.reps[0];
            this._optimum[cur].Backs1 = this.reps[1];
            this._optimum[cur].Backs2 = this.reps[2];
            this._optimum[cur].Backs3 = this.reps[3];
            let curPrice: number = this._optimum[cur].Price;

            currentByte = this._matchFinder.GetIndexByte(0 - 1);
            matchByte = this._matchFinder.GetIndexByte(0 - this.reps[0] - 1 - 1);

            posState = (position & this._posStateMask);

            let curAnd1Price: number = curPrice +
            RangeCoderEncoder.GetPriceReducingBits(this._isMatch[(state << Base.kNumPosStatesBitsMax) + posState]) +
            this._literalEncoder.GetSubCoder(position, this._matchFinder.GetIndexByte(0 - 2)).GetPrice(!Base.StateIsCharState(state), matchByte, currentByte);

            let nextOptimum: Optimal = this._optimum[cur + 1];

            let nextIsChar: boolean = false;
            if (curAnd1Price < nextOptimum.Price) {
                nextOptimum.Price = curAnd1Price;
                nextOptimum.PosPrev = cur;
                nextOptimum.MakeAsChar();
                nextIsChar = true;
            }

            matchPrice = curPrice + RangeCoderEncoder.GetPriceModelTotal(this._isMatch[(state << Base.kNumPosStatesBitsMax) + posState]);
            repMatchPrice = matchPrice + RangeCoderEncoder.GetPriceModelTotal(this._isRep[state]);

            if (matchByte == currentByte &&
            !(nextOptimum.PosPrev < cur && nextOptimum.BackPrev == 0)) {
                let shortRepPrice: number = repMatchPrice + this.GetRepLen1Price(state, posState);
                if (shortRepPrice <= nextOptimum.Price) {
                    nextOptimum.Price = shortRepPrice;
                    nextOptimum.PosPrev = cur;
                    nextOptimum.MakeAsShortRep();
                    nextIsChar = true;
                }
            }

            let numAvailableBytesFull: number = this._matchFinder.GetNumAvailableBytes() + 1;
            numAvailableBytesFull = Math.min(Encoder.kNumOpts - 1 - cur, numAvailableBytesFull);
            numAvailableBytes = numAvailableBytesFull;

            if (numAvailableBytes < 2)
            continue;
            if (numAvailableBytes > this._numFastBytes)
            numAvailableBytes = this._numFastBytes;
            if (!nextIsChar && matchByte != currentByte) {
                // try Literal + rep0
                let t: number = Math.min(numAvailableBytesFull - 1, this._numFastBytes);
                let lenTest2: number = this._matchFinder.GetMatchLen(0, this.reps[0], t);
                if (lenTest2 >= 2) {
                    let state2: number = Base.StateUpdateChar(state);

                    let posStateNext: number = (position + 1) & this._posStateMask;
                    let nextRepMatchPrice: number = curAnd1Price +
                    RangeCoderEncoder.GetPriceModelTotal(this._isMatch[(state2 << Base.kNumPosStatesBitsMax) + posStateNext]) +
                    RangeCoderEncoder.GetPriceModelTotal(this._isRep[state2]);
                    {
                        let offset: number = cur + 1 + lenTest2;
                        while (lenEnd < offset)
                        this._optimum[++lenEnd].Price = Encoder.kIfinityPrice;
                        let curAndLenPrice: number = nextRepMatchPrice + this.GetRepPrice(
                            0, lenTest2, state2, posStateNext);
                        let optimum: Optimal = this._optimum[offset];
                        if (curAndLenPrice < optimum.Price) {
                            optimum.Price = curAndLenPrice;
                            optimum.PosPrev = cur + 1;
                            optimum.BackPrev = 0;
                            optimum.Prev1IsChar = true;
                            optimum.Prev2 = false;
                        }
                    }
                }
            }

            let startLen: number = 2; // speed optimization

            for (let repIndex = 0; repIndex < Base.kNumRepDistances; repIndex++) {
                let lenTest: number = this._matchFinder.GetMatchLen(0 - 1, this.reps[repIndex], numAvailableBytes);
                if (lenTest < 2)
                continue;
                let lenTestTemp: number = lenTest;
                do
                {
                    while (lenEnd < cur + lenTest)
                    this._optimum[++lenEnd].Price = Encoder.kIfinityPrice;
                    let curAndLenPrice: number = repMatchPrice + this.GetRepPrice(repIndex, lenTest, state, posState);
                    let optimum: Optimal = this._optimum[cur + lenTest];
                    if (curAndLenPrice < optimum.Price) {
                        optimum.Price = curAndLenPrice;
                        optimum.PosPrev = cur;
                        optimum.BackPrev = repIndex;
                        optimum.Prev1IsChar = false;
                    }
                }
                while (--lenTest >= 2);
                lenTest = lenTestTemp;

                if (repIndex == 0)
                startLen = lenTest + 1;

                // if (_maxMode)
                if (lenTest < numAvailableBytesFull) {
                    let t: number = Math.min(numAvailableBytesFull - 1 - lenTest, this._numFastBytes);
                    let lenTest2: number = this._matchFinder.GetMatchLen(lenTest, this.reps[repIndex], t);
                    if (lenTest2 >= 2) {
                        let state2: number = Base.StateUpdateRep(state);

                        let posStateNext: number = (position + lenTest) & this._posStateMask;
                        let curAndLenCharPrice: number =
                            repMatchPrice + this.GetRepPrice(repIndex, lenTest, state, posState) +
                            RangeCoderEncoder.GetPriceReducingBits(this._isMatch[(state2 << Base.kNumPosStatesBitsMax) + posStateNext]) +
                            this._literalEncoder.GetSubCoder(position + lenTest,
                            this._matchFinder.GetIndexByte(lenTest - 1 - 1)).GetPrice(true,
                            this._matchFinder.GetIndexByte(lenTest - 1 - (this.reps[repIndex] + 1)),
                            this._matchFinder.GetIndexByte(lenTest - 1));
                        state2 = Base.StateUpdateChar(state2);
                        posStateNext = (position + lenTest + 1) & this._posStateMask;
                        let nextMatchPrice: number = curAndLenCharPrice + RangeCoderEncoder.GetPriceModelTotal(this._isMatch[(state2 << Base.kNumPosStatesBitsMax) + posStateNext]);
                        let nextRepMatchPrice: number = nextMatchPrice + RangeCoderEncoder.GetPriceModelTotal(this._isRep[state2]);

                        // for(; lenTest2 >= 2; lenTest2--)
                        {
                            let offset: number = lenTest + 1 + lenTest2;
                            while (lenEnd < cur + offset)
                            this._optimum[++lenEnd].Price = Encoder.kIfinityPrice;
                            let curAndLenPrice: number = nextRepMatchPrice + this.GetRepPrice(0, lenTest2, state2, posStateNext);
                            let optimum: Optimal = this._optimum[cur + offset];
                            if (curAndLenPrice < optimum.Price) {
                                optimum.Price = curAndLenPrice;
                                optimum.PosPrev = cur + lenTest + 1;
                                optimum.BackPrev = 0;
                                optimum.Prev1IsChar = true;
                                optimum.Prev2 = true;
                                optimum.PosPrev2 = cur;
                                optimum.BackPrev2 = repIndex;
                            }
                        }
                    }
                }
            }

            if (newLen > numAvailableBytes) {
                newLen = numAvailableBytes;
                for (numDistancePairs = 0; newLen > this._matchDistances[numDistancePairs]; numDistancePairs += 2) ;
                this._matchDistances[numDistancePairs] = newLen;
                numDistancePairs += 2;
            }
            if (newLen >= startLen) {
                normalMatchPrice = matchPrice + RangeCoderEncoder.GetPriceReducingBits(this._isRep[state]);
                while (lenEnd < cur + newLen)
                this._optimum[++lenEnd].Price = Encoder.kIfinityPrice;

                let offs: number = 0;
                while (startLen > this._matchDistances[offs])
                offs += 2;

                for (let lenTest = startLen;; lenTest++) {
                    let curBack: number = this._matchDistances[offs + 1];
                    let curAndLenPrice: number = normalMatchPrice + this.GetPosLenPrice(curBack, lenTest, posState);
                    let optimum: Optimal = this._optimum[cur + lenTest];
                    if (curAndLenPrice < optimum.Price) {
                        optimum.Price = curAndLenPrice;
                        optimum.PosPrev = cur;
                        optimum.BackPrev = curBack + Base.kNumRepDistances;
                        optimum.Prev1IsChar = false;
                    }

                    if (lenTest == this._matchDistances[offs]) {
                        if (lenTest < numAvailableBytesFull) {
                            let t: number = Math.min(numAvailableBytesFull - 1 - lenTest, this._numFastBytes);
                            let lenTest2: number = this._matchFinder.GetMatchLen(lenTest, curBack, t);
                            if (lenTest2 >= 2) {
                                let state2: number = Base.StateUpdateMatch(state);

                                let posStateNext: number = (position + lenTest) & this._posStateMask;
                                let curAndLenCharPrice: number = curAndLenPrice +
                                RangeCoderEncoder.GetPriceReducingBits(this._isMatch[(state2 << Base.kNumPosStatesBitsMax) + posStateNext]) +
                                this._literalEncoder.GetSubCoder(position + lenTest,
                                this._matchFinder.GetIndexByte(lenTest - 1 - 1)).GetPrice(true,
                                this._matchFinder.GetIndexByte(lenTest - (curBack + 1) - 1),
                                this._matchFinder.GetIndexByte(lenTest - 1));
                                state2 = Base.StateUpdateChar(state2);
                                posStateNext = (position + lenTest + 1) & this._posStateMask;
                                let nextMatchPrice: number = curAndLenCharPrice + RangeCoderEncoder.GetPriceModelTotal(this._isMatch[(state2 << Base.kNumPosStatesBitsMax) + posStateNext]);
                                let nextRepMatchPrice: number = nextMatchPrice + RangeCoderEncoder.GetPriceModelTotal(this._isRep[state2]);

                                let offset: number = lenTest + 1 + lenTest2;
                                while (lenEnd < cur + offset)
                                this._optimum[++lenEnd].Price = Encoder.kIfinityPrice;
                                curAndLenPrice = nextRepMatchPrice + this.GetRepPrice(0, lenTest2, state2, posStateNext);
                                optimum = this._optimum[cur + offset];
                                if (curAndLenPrice < optimum.Price) {
                                    optimum.Price = curAndLenPrice;
                                    optimum.PosPrev = cur + lenTest + 1;
                                    optimum.BackPrev = 0;
                                    optimum.Prev1IsChar = true;
                                    optimum.Prev2 = true;
                                    optimum.PosPrev2 = cur;
                                    optimum.BackPrev2 = curBack + Base.kNumRepDistances;
                                }
                            }
                        }
                        offs += 2;
                        if (offs == numDistancePairs)
                        break;
                    }
                }
            }
        }
    }

    ChangePair(smallDist: number, bigDist: number): boolean
    {
        let kDif: number = 7;
        return (smallDist < (1 << (32 - kDif)) && bigDist >= (smallDist << kDif));
    }

    WriteEndMarker(posState: number): void
    {
        if (!this._writeEndMark)
        return;

        this._rangeEncoder.Encode(this._isMatch, (this._state << Base.kNumPosStatesBitsMax) + posState, 1);
        this._rangeEncoder.Encode(this._isRep, this._state, 0);
        this._state = Base.StateUpdateMatch(this._state);
        let len: number = Base.kMatchMinLen;
        this._lenEncoder.Encode(this._rangeEncoder, len - Base.kMatchMinLen, posState);
        let posSlot: number = (1 << Base.kNumPosSlotBits) - 1;
        let lenToPosState: number = Base.GetLenToPosState(len);
        this._posSlotEncoder[lenToPosState].Encode(this._rangeEncoder, posSlot);
        let footerBits: number = 30;
        let posReduced: number = (1 << footerBits) - 1;
        this._rangeEncoder.EncodeDirectBits(posReduced >> Base.kNumAlignBits, footerBits - Base.kNumAlignBits);
        this._posAlignEncoder.ReverseEncode(this._rangeEncoder, posReduced & Base.kAlignMask);
    }

    Flush(nowPos: number): void
    {
        this.ReleaseMFStream();
        this.WriteEndMarker(nowPos & this._posStateMask);
        this._rangeEncoder.FlushData();
        this._rangeEncoder.FlushStream();
    }

    public CodeOneBlock(inSize: Array<Long>, outSize: Array<Long>, finished: boolean[]): void
    {
        inSize[0] = Long.fromNumber(0);
        outSize[0] = Long.fromNumber(0);
        finished[0] = true;

        if (this._inStream != null) {
            this._matchFinder.SetStream(this._inStream);
            this._matchFinder.Init();
            this._needReleaseMFStream = true;
            this._inStream = null;
        }

        if (this._finished)
        return;
        this._finished = true;


        let progressPosValuePrev: Long = this.nowPos64;
        if (this.nowPos64.toInt() == 0) {
            if (this._matchFinder.GetNumAvailableBytes() == 0) {
                this.Flush(this.nowPos64.toInt());
                return;
            }

            this.ReadMatchDistances();
            let posState: number = this.nowPos64.toInt() & this._posStateMask;
            this._rangeEncoder.Encode(this._isMatch, (this._state << Base.kNumPosStatesBitsMax) + posState, 0);
            this._state = Base.StateUpdateChar(this._state);
            let curByte: number = this._matchFinder.GetIndexByte(0 - this._additionalOffset);
            this._literalEncoder.GetSubCoder(this.nowPos64.toInt(), this._previousByte).Encode(this._rangeEncoder, curByte);
            this._previousByte = curByte;
            this._additionalOffset--;
            this.nowPos64 = this.nowPos64.add(1);
        }
        if (this._matchFinder.GetNumAvailableBytes() == 0) {
            this.Flush(this.nowPos64.toInt());
            return;
        }
        while (true) {

            let len: number = this.GetOptimum(this.nowPos64.toInt());
            let pos: number = this.backRes;
            let posState: number = (this.nowPos64.toInt()) & this._posStateMask;
            let complexState: number = (this._state << Base.kNumPosStatesBitsMax) + posState;
            if (len == 1 && pos == -1) {
                this._rangeEncoder.Encode(this._isMatch, complexState, 0);
                let curByte: number = this._matchFinder.GetIndexByte(parseInt((0 - this._additionalOffset) + ''));
                let subCoder: Encoder2 = this._literalEncoder.GetSubCoder(this.nowPos64.toInt(), this._previousByte);
                if (!Base.StateIsCharState(this._state)) {
                    let matchByte: number = this._matchFinder.GetIndexByte(parseInt((0 - this._repDistances[0] - 1 - this._additionalOffset) + ''));
                    subCoder.EncodeMatched(this._rangeEncoder, matchByte, curByte);
                }
                else
                subCoder.Encode(this._rangeEncoder, curByte);
                this._previousByte = curByte;
                this._state = Base.StateUpdateChar(this._state);
            }
            else {
                this._rangeEncoder.Encode(this._isMatch, complexState, 1);
                if (pos < Base.kNumRepDistances) {
                    this._rangeEncoder.Encode(this._isRep, this._state, 1);
                    if (pos == 0) {
                        this._rangeEncoder.Encode(this._isRepG0, this._state, 0);
                        if (len == 1)
                        this._rangeEncoder.Encode(this._isRep0Long, complexState, 0);
                        else
                        this._rangeEncoder.Encode(this._isRep0Long, complexState, 1);
                    }
                    else {
                        this._rangeEncoder.Encode(this._isRepG0, this._state, 1);
                        if (pos == 1)
                        this._rangeEncoder.Encode(this._isRepG1, this._state, 0);
                        else {
                            this._rangeEncoder.Encode(this._isRepG1, this._state, 1);
                            this._rangeEncoder.Encode(this._isRepG2, this._state, pos - 2);
                        }
                    }
                    if (len == 1)
                    this._state = Base.StateUpdateShortRep(this._state);
                    else {
                        this._repMatchLenEncoder.Encode(this._rangeEncoder, len - Base.kMatchMinLen, posState);
                        this._state = Base.StateUpdateRep(this._state);
                    }
                    let distance: number = this._repDistances[pos];
                    if (pos != 0) {
                        for (let i = pos; i >= 1; i--)
                        this._repDistances[i] = this._repDistances[i - 1];
                        this._repDistances[0] = distance;
                    }
                }
                else {
                    this._rangeEncoder.Encode(this._isRep, this._state, 0);
                    this._state = Base.StateUpdateMatch(this._state);
                    this._lenEncoder.Encode(this._rangeEncoder, len - Base.kMatchMinLen, posState);
                    pos -= Base.kNumRepDistances;
                    let posSlot: number = Encoder.GetPosSlot(pos);
                    let lenToPosState: number = Base.GetLenToPosState(len);
                    this._posSlotEncoder[lenToPosState].Encode(this._rangeEncoder, posSlot);

                    if (posSlot >= Base.kStartPosModelIndex) {
                        let footerBits: number = parseInt(((posSlot >> 1) - 1) + '');
                        let baseVal: number = ((2 | (posSlot & 1)) << footerBits);
                        let posReduced: number = pos - baseVal;

                        if (posSlot < Base.kEndPosModelIndex)
                        BitTreeEncoder.ReverseEncode(this._posEncoders,
                            baseVal - posSlot - 1, this._rangeEncoder, footerBits, posReduced);
                        else {
                            this._rangeEncoder.EncodeDirectBits(posReduced >> Base.kNumAlignBits, footerBits - Base.kNumAlignBits);
                            this._posAlignEncoder.ReverseEncode(this._rangeEncoder, posReduced & Base.kAlignMask);
                            this._alignPriceCount++;
                        }
                    }
                    let distance: number = pos;
                    for (let i = Base.kNumRepDistances - 1; i >= 1; i--)
                    this._repDistances[i] = this._repDistances[i - 1];
                    this._repDistances[0] = distance;
                    this._matchPriceCount++;
                }
                this._previousByte = this._matchFinder.GetIndexByte(len - 1 - this._additionalOffset);
            }
            this._additionalOffset -= len;
            this.nowPos64 = this.nowPos64.add(len);
            if (this._additionalOffset == 0) {
                // if (!_fastMode)
                if (this._matchPriceCount >= (1 << 7))
                this.FillDistancesPrices();
                if (this._alignPriceCount >= Base.kAlignTableSize)
                this.FillAlignPrices();
                inSize[0] = this.nowPos64;
                outSize[0] = Long.fromNumber(this._rangeEncoder.GetProcessedSizeAdd());
                if (this._matchFinder.GetNumAvailableBytes() == 0) {
                    this.Flush(this.nowPos64.toInt());
                    return;
                }

                if (this.nowPos64.subtract(progressPosValuePrev).toInt() >= (1 << 12)) {
                    this._finished = false;
                    finished[0] = false;
                    return;
                }
            }
        }
    }

    ReleaseMFStream(): void
    {
        if (this._matchFinder != null && this._needReleaseMFStream) {
            this._matchFinder.ReleaseStream();
            this._needReleaseMFStream = false;
        }
    }

    SetOutStream(outStream: OutputStream): void
    {
        this._rangeEncoder.SetStream(outStream);
    }

    ReleaseOutStream(): void
    {
        this._rangeEncoder.ReleaseStream();
    }

    ReleaseStreams(): void
    {
        this.ReleaseMFStream();
        this.ReleaseOutStream();
    }

    SetStreams(inStream: InputStream, outStream: OutputStream,
               inSize: Long, outSize: Long): void
    {
        this._inStream = inStream;
        this._finished = false;
        this.Create();
        this.SetOutStream(outStream);
        this.Init();

        // if (!_fastMode)
        {
            this.FillDistancesPrices();
            this.FillAlignPrices();
        }

        this._lenEncoder.SetTableSize(this._numFastBytes + 1 - Base.kMatchMinLen);
        this._lenEncoder.UpdateTables(1 << this._posStateBits);
        this._repMatchLenEncoder.SetTableSize(this._numFastBytes + 1 - Base.kMatchMinLen);
        this._repMatchLenEncoder.UpdateTables(1 << this._posStateBits);

        this.nowPos64 = Long.fromNumber(0);
    }

    processedInSize: Array<Long> = new Array<Long>(1);
    processedOutSize: Array<Long> = new Array<Long>(1);
    finished: boolean[] = new Array<boolean>(1);

    public Code(inStream: InputStream, outStream: OutputStream,
                inSize: Long, outSize: Long, progress:  ICodeProgress | null): void
    {
        this._needReleaseMFStream = false;
        try {
            this.SetStreams(inStream, outStream, inSize, outSize);
            while (true) {
                this.CodeOneBlock(this.processedInSize, this.processedOutSize, this.finished);
                if (this.finished[0])
                return;
                if (progress != null) {
                    progress.SetProgress(this.processedInSize[0], this.processedOutSize[0]);
                }
            }
        } finally {
            this.ReleaseStreams();
        }
    }

    public static kPropSize: number = 5;
    properties: Int8Array = new Int8Array(Encoder.kPropSize);

    public WriteCoderProperties(outStream: OutputStream): void
    {
        this.properties[0] = parseInt(((this._posStateBits * 5 + this._numLiteralPosStateBits) * 9 + this._numLiteralContextBits) + '');
        for (let i = 0; i < 4; i++)
        this.properties[1 + i] = (this._dictionarySize >> (8 * i));
        outStream.writeBytesOffset(this.properties, 0, Encoder.kPropSize);
    }

    public getUint8(value: number): number {
        let data: string = value.toString(2);
        let zeroString = '00000000'
        if (data.length < 8) {
            data = zeroString.substring(0, 8 - data.length) + data
        } else {
            data = data.substring(data.length - 8, data.length)
        }
        return parseInt(data, 2)
    }

    tempPrices: Int32Array = new Int32Array(Base.kNumFullDistances);
    _matchPriceCount: number;

    FillDistancesPrices(): void
    {
        for (let i = Base.kStartPosModelIndex; i < Base.kNumFullDistances; i++) {
            let posSlot: number = Encoder.GetPosSlot(i);
            let footerBits: number = ((posSlot >> 1) - 1);
            let baseVal: number = ((2 | (posSlot & 1)) << footerBits);
            this.tempPrices[i] = BitTreeEncoder.ReverseGetPrice(this._posEncoders,
                baseVal - posSlot - 1, footerBits, i - baseVal);
        }

        for (let lenToPosState = 0; lenToPosState < Base.kNumLenToPosStates; lenToPosState++) {
            let posSlot: number;
            let encoder: BitTreeEncoder = this._posSlotEncoder[lenToPosState];

            let st: number = (lenToPosState << Base.kNumPosSlotBits);
            for (posSlot = 0; posSlot < this._distTableSize; posSlot++)
            this._posSlotPrices[st + posSlot] = encoder.GetPrice(posSlot);
            for (posSlot = Base.kEndPosModelIndex; posSlot < this._distTableSize; posSlot++)
            this._posSlotPrices[st + posSlot] += ((((posSlot >> 1) - 1) - Base.kNumAlignBits) << RangeCoderEncoder.kNumBitPriceShiftBits);

            let st2: number = lenToPosState * Base.kNumFullDistances;
            let i: number;
            for (i = 0; i < Base.kStartPosModelIndex; i++)
            this._distancesPrices[st2 + i] = this._posSlotPrices[st + i];
            for (; i < Base.kNumFullDistances; i++)
            this._distancesPrices[st2 + i] = this._posSlotPrices[st + Encoder.GetPosSlot(i)] + this.tempPrices[i];
        }
        this._matchPriceCount = 0;
    }

    FillAlignPrices(): void
    {
        for (let i = 0; i < Base.kAlignTableSize; i++)
        this._alignPrices[i] = this._posAlignEncoder.ReverseGetPrice(i);
        this._alignPriceCount = 0;
    }

    public SetAlgorithm(algorithm: number): boolean
    {
        return true;
    }

    public SetDictionarySize(dictionarySize: number): boolean
    {
        let kDicLogSizeMaxCompress: number = 29;
        if (dictionarySize < (1 << Base.kDicLogSizeMin) || dictionarySize > (1 << kDicLogSizeMaxCompress))
        return false;
        this._dictionarySize = dictionarySize;
        let dicLogSize: number;
        for (dicLogSize = 0; dictionarySize > (1 << dicLogSize); dicLogSize++) ;
        this._distTableSize = dicLogSize * 2;
        return true;
    }

    public SetNumFastBytes(numFastBytes: number): boolean
    {
        if (numFastBytes < 5 || numFastBytes > Base.kMatchMaxLen)
        return false;
        this._numFastBytes = numFastBytes;
        return true;
    }

    public SetMatchFinder(matchFinderIndex: number): boolean
    {
        if (matchFinderIndex < 0 || matchFinderIndex > 2)
        return false;
        let matchFinderIndexPrev = this._matchFinderType;
        this._matchFinderType = matchFinderIndex;
        if (this._matchFinder != null && matchFinderIndexPrev != this._matchFinderType) {
            this._dictionarySizePrev = -1;
            this._matchFinder = null;
        }
        return true;
    }

    public SetLcLpPb(lc: number, lp: number, pb: number): boolean
    {
        if (
        lp < 0 || lp > Base.kNumLitPosStatesBitsEncodingMax ||
        lc < 0 || lc > Base.kNumLitContextBitsMax ||
        pb < 0 || pb > Base.kNumPosStatesBitsEncodingMax)
        return false;
        this._numLiteralPosStateBits = lp;
        this._numLiteralContextBits = lc;
        this._posStateBits = pb;
        this._posStateMask = ((1) << this._posStateBits) - 1;
        return true;
    }

    public SetEndMarkerMode(endMarkerMode: boolean): void
    {
        this._writeEndMark = endMarkerMode;
    }
}

Encoder.staticInit()