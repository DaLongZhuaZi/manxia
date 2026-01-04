package eu.kanade.tachiyomi.lib.cryptoaes;

import java.util.List;
import kotlin.Metadata;
import kotlin.collections.CollectionsKt;
import kotlin.jvm.internal.Intrinsics;
import kotlin.sequences.SequencesKt;
import kotlin.text.CharsKt;
import kotlin.text.Regex;
import kotlin.text.StringsKt;

/* compiled from: Deobfuscator.kt */
@Metadata(d1 = {"\u0000\"\n\u0002\u0018\u0002\n\u0002\u0010\u0000\n\u0002\b\u0002\n\u0002\u0010\f\n\u0000\n\u0002\u0010\u000e\n\u0002\b\u0003\n\u0002\u0010\b\n\u0002\b\u0002\bÆ\u0002\u0018\u00002\u00020\u0001B\u0007\b\u0002¢\u0006\u0002\u0010\u0002J\u0010\u0010\u0003\u001a\u00020\u00042\u0006\u0010\u0005\u001a\u00020\u0006H\u0002J\u000e\u0010\u0007\u001a\u00020\u00062\u0006\u0010\b\u001a\u00020\u0006J\u0018\u0010\t\u001a\u00020\n2\u0006\u0010\u000b\u001a\u00020\n2\u0006\u0010\b\u001a\u00020\u0006H\u0002¨\u0006\f"}, d2 = {"Leu/kanade/tachiyomi/lib/cryptoaes/Deobfuscator;", "", "()V", "calculateDigit", "", "inputSubString", "", "deobfuscateJsPassword", "inputString", "getMatchingBracketIndex", "", "openingIndex", "cryptoaes_debug"}, k = 1, mv = {1, 7, 1}, xi = 48)
/* loaded from: classes.dex */
public final class Deobfuscator {
    public static final Deobfuscator INSTANCE = new Deobfuscator();

    private Deobfuscator() {
    }

    public final String deobfuscateJsPassword(String inputString) {
        Intrinsics.checkNotNullParameter(inputString, "inputString");
        int idx = 0;
        List brackets = CollectionsKt.listOf(new Character[]{'[', '('});
        StringBuilder evaluatedString = new StringBuilder();
        while (idx < inputString.length()) {
            char chr = inputString.charAt(idx);
            if (!brackets.contains(Character.valueOf(chr))) {
                idx++;
            } else {
                int closingIndex = getMatchingBracketIndex(idx, inputString);
                if (chr == '[') {
                    String strSubstring = inputString.substring(idx, closingIndex);
                    Intrinsics.checkNotNullExpressionValue(strSubstring, "this as java.lang.String…ing(startIndex, endIndex)");
                    char digit = calculateDigit(strSubstring);
                    evaluatedString.append(digit);
                } else {
                    evaluatedString.append('.');
                    Character orNull = StringsKt.getOrNull(inputString, closingIndex + 1);
                    if (orNull != null && orNull.charValue() == '[') {
                        int skippingIndex = getMatchingBracketIndex(closingIndex + 1, inputString);
                        idx = skippingIndex + 1;
                    }
                }
                idx = closingIndex + 1;
            }
        }
        String string = evaluatedString.toString();
        Intrinsics.checkNotNullExpressionValue(string, "evaluatedString.toString()");
        return string;
    }

    private final int getMatchingBracketIndex(int openingIndex, String inputString) {
        char openingBracket = inputString.charAt(openingIndex);
        char closingBracket = openingBracket == '[' ? ']' : ')';
        int counter = 0;
        int length = inputString.length();
        for (int idx = openingIndex; idx < length; idx++) {
            if (inputString.charAt(idx) == openingBracket) {
                counter++;
            }
            if (inputString.charAt(idx) == closingBracket) {
                counter--;
            }
            if (counter == 0) {
                return idx;
            }
            if (counter < 0) {
                return -1;
            }
        }
        return -1;
    }

    private final char calculateDigit(String inputSubString) {
        boolean z = false;
        int digit = SequencesKt.count(Regex.findAll$default(new Regex("!\\+\\[]"), inputSubString, 0, 2, (Object) null));
        if (digit == 0) {
            if (SequencesKt.count(Regex.findAll$default(new Regex("\\+\\[]"), inputSubString, 0, 2, (Object) null)) == 1) {
                return '0';
            }
            return '-';
        }
        if (1 <= digit && digit < 10) {
            z = true;
        }
        if (z) {
            return CharsKt.digitToChar(digit);
        }
        return '-';
    }
}
