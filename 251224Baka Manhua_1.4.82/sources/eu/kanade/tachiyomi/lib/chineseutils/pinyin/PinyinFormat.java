package eu.kanade.tachiyomi.lib.chineseutils.pinyin;

/* JADX INFO: loaded from: classes.dex */
public class PinyinFormat {
    private CaseType caseType;
    private boolean onlyPinyin;
    private String separator;
    private ToneType toneType;
    private YuCharType yuCharType;
    public static final PinyinFormat DEFAULT_PINYIN_FORMAT = new PinyinFormat();
    public static final PinyinFormat UNICODE_PINYIN_FORMAT = new PinyinFormat(YuCharType.WITH_U_UNICODE, ToneType.WITH_TONE_MARK);
    public static final PinyinFormat TONELESS_PINYIN_FORMAT = new PinyinFormat(YuCharType.WITH_V, ToneType.WITHOUT_TONE);
    public static final PinyinFormat ABBR_PINYIN_FORMAT = new PinyinFormat(YuCharType.WITH_U_AND_COLON, ToneType.WITH_ABBR, CaseType.LOWERCASE, "", true);

    public PinyinFormat() {
        this.yuCharType = YuCharType.WITH_U_AND_COLON;
        this.toneType = ToneType.WITH_TONE_NUMBER;
        this.caseType = CaseType.LOWERCASE;
        this.separator = Pinyin.SPACE;
        this.onlyPinyin = false;
    }

    public PinyinFormat(YuCharType yuCharType, ToneType toneType, CaseType caseType, String str, boolean z) {
        this.yuCharType = YuCharType.WITH_U_AND_COLON;
        this.toneType = ToneType.WITH_TONE_NUMBER;
        CaseType caseType2 = CaseType.LOWERCASE;
        this.yuCharType = yuCharType;
        this.toneType = toneType;
        this.caseType = caseType;
        this.separator = str;
        this.onlyPinyin = z;
    }

    public PinyinFormat(YuCharType yuCharType, ToneType toneType, CaseType caseType, String str) {
        this(yuCharType, toneType, caseType, str, false);
    }

    public PinyinFormat(YuCharType yuCharType, ToneType toneType, CaseType caseType) {
        this(yuCharType, toneType, caseType, Pinyin.SPACE);
    }

    public PinyinFormat(YuCharType yuCharType, ToneType toneType) {
        this(yuCharType, toneType, CaseType.LOWERCASE);
    }

    public YuCharType getYuCharType() {
        return this.yuCharType;
    }

    public void setYuCharType(YuCharType yuCharType) {
        this.yuCharType = yuCharType;
    }

    public CaseType getCaseType() {
        return this.caseType;
    }

    public void setCaseType(CaseType caseType) {
        this.caseType = caseType;
    }

    public ToneType getToneType() {
        return this.toneType;
    }

    public void setToneType(ToneType toneType) {
        this.toneType = toneType;
    }

    public String getSeparator() {
        return this.separator;
    }

    public void setSeparator(String str) {
        this.separator = str;
    }

    public boolean isOnlyPinyin() {
        return this.onlyPinyin;
    }

    public void setOnlyPinyin(boolean z) {
        this.onlyPinyin = z;
    }
}
