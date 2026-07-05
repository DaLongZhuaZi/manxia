package eu.kanade.tachiyomi.lib.chineseutils.pinyin;

/* JADX INFO: loaded from: classes.dex */
public class PinyinFormatter {
    public static String formatPinyin(String str, PinyinFormat pinyinFormat) {
        if (ToneType.WITH_ABBR == pinyinFormat.getToneType()) {
            str = abbr(str);
        } else {
            if (ToneType.WITH_TONE_MARK == pinyinFormat.getToneType() && (YuCharType.WITH_V == pinyinFormat.getYuCharType() || YuCharType.WITH_U_AND_COLON == pinyinFormat.getYuCharType())) {
                pinyinFormat.setYuCharType(YuCharType.WITH_U_UNICODE);
            }
            int i = AnonymousClass1.$SwitchMap$eu$kanade$tachiyomi$lib$chineseutils$pinyin$ToneType[pinyinFormat.getToneType().ordinal()];
            if (i == 1) {
                str = str.replaceAll("[1-5]", "");
            } else if (i == 2) {
                str = convertToneNumber2ToneMark(str.replaceAll("u:", "v"));
            }
            int i2 = AnonymousClass1.$SwitchMap$eu$kanade$tachiyomi$lib$chineseutils$pinyin$YuCharType[pinyinFormat.getYuCharType().ordinal()];
            if (i2 == 1) {
                str = str.replaceAll("u:", "v");
            } else if (i2 == 2) {
                str = str.replaceAll("u:", "ü");
            }
        }
        int i3 = AnonymousClass1.$SwitchMap$eu$kanade$tachiyomi$lib$chineseutils$pinyin$CaseType[pinyinFormat.getCaseType().ordinal()];
        if (i3 != 1) {
            return i3 != 2 ? str : capitalize(str);
        }
        return str.toUpperCase();
    }

    /* JADX INFO: renamed from: eu.kanade.tachiyomi.lib.chineseutils.pinyin.PinyinFormatter$1, reason: invalid class name */
    static /* synthetic */ class AnonymousClass1 {
        static final /* synthetic */ int[] $SwitchMap$eu$kanade$tachiyomi$lib$chineseutils$pinyin$CaseType;
        static final /* synthetic */ int[] $SwitchMap$eu$kanade$tachiyomi$lib$chineseutils$pinyin$ToneType;
        static final /* synthetic */ int[] $SwitchMap$eu$kanade$tachiyomi$lib$chineseutils$pinyin$YuCharType;

        static {
            int[] iArr = new int[CaseType.values().length];
            $SwitchMap$eu$kanade$tachiyomi$lib$chineseutils$pinyin$CaseType = iArr;
            try {
                iArr[CaseType.UPPERCASE.ordinal()] = 1;
            } catch (NoSuchFieldError unused) {
            }
            try {
                $SwitchMap$eu$kanade$tachiyomi$lib$chineseutils$pinyin$CaseType[CaseType.CAPITALIZE.ordinal()] = 2;
            } catch (NoSuchFieldError unused2) {
            }
            int[] iArr2 = new int[YuCharType.values().length];
            $SwitchMap$eu$kanade$tachiyomi$lib$chineseutils$pinyin$YuCharType = iArr2;
            try {
                iArr2[YuCharType.WITH_V.ordinal()] = 1;
            } catch (NoSuchFieldError unused3) {
            }
            try {
                $SwitchMap$eu$kanade$tachiyomi$lib$chineseutils$pinyin$YuCharType[YuCharType.WITH_U_UNICODE.ordinal()] = 2;
            } catch (NoSuchFieldError unused4) {
            }
            int[] iArr3 = new int[ToneType.values().length];
            $SwitchMap$eu$kanade$tachiyomi$lib$chineseutils$pinyin$ToneType = iArr3;
            try {
                iArr3[ToneType.WITHOUT_TONE.ordinal()] = 1;
            } catch (NoSuchFieldError unused5) {
            }
            try {
                $SwitchMap$eu$kanade$tachiyomi$lib$chineseutils$pinyin$ToneType[ToneType.WITH_TONE_MARK.ordinal()] = 2;
            } catch (NoSuchFieldError unused6) {
            }
        }
    }

    public static String abbr(String str) {
        return (str == null || str.length() == 0) ? str : str.substring(0, 1);
    }

    public static String capitalize(String str) {
        int length;
        if (str == null || (length = str.length()) == 0) {
            return str;
        }
        StringBuilder sb = new StringBuilder(length);
        sb.append(Character.toTitleCase(str.charAt(0)));
        sb.append(str.substring(1));
        return sb.toString();
    }

    private static String convertToneNumber2ToneMark(String str) {
        String lowerCase = str.toLowerCase();
        if (!lowerCase.matches("[a-z]*[1-5]?")) {
            return lowerCase;
        }
        if (lowerCase.matches("[a-z]*[1-5]")) {
            int numericValue = Character.getNumericValue(lowerCase.charAt(lowerCase.length() - 1));
            char cCharAt = 'a';
            int iIndexOf = lowerCase.indexOf(97);
            int iIndexOf2 = lowerCase.indexOf(101);
            int iIndexOf3 = lowerCase.indexOf("ou");
            if (-1 == iIndexOf) {
                if (-1 == iIndexOf2) {
                    if (-1 != iIndexOf3) {
                        cCharAt = "ou".charAt(0);
                        iIndexOf = iIndexOf3;
                    } else {
                        iIndexOf = lowerCase.length() - 1;
                        while (true) {
                            if (iIndexOf < 0) {
                                cCharAt = '$';
                                iIndexOf = -1;
                                break;
                            }
                            if (String.valueOf(lowerCase.charAt(iIndexOf)).matches("[aeiouv]")) {
                                cCharAt = lowerCase.charAt(iIndexOf);
                                break;
                            }
                            iIndexOf--;
                        }
                    }
                } else {
                    iIndexOf = iIndexOf2;
                    cCharAt = 'e';
                }
            }
            if ('$' == cCharAt || -1 == iIndexOf) {
                return lowerCase;
            }
            char cCharAt2 = "āáăàaēéĕèeīíĭìiōóŏòoūúŭùuǖǘǚǜü".charAt(("aeiouv".indexOf(cCharAt) * 5) + (numericValue - 1));
            StringBuffer stringBuffer = new StringBuffer();
            stringBuffer.append(lowerCase.substring(0, iIndexOf).replaceAll("v", "ü"));
            stringBuffer.append(cCharAt2);
            stringBuffer.append(lowerCase.substring(iIndexOf + 1, lowerCase.length() - 1).replaceAll("v", "ü"));
            return stringBuffer.toString();
        }
        return lowerCase.replaceAll("v", "ü");
    }
}
