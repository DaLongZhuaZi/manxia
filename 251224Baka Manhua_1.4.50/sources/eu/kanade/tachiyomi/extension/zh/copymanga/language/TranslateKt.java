package eu.kanade.tachiyomi.extension.zh.copymanga.language;

import eu.kanade.tachiyomi.extension.zh.copymanga.CCOption;
import eu.kanade.tachiyomi.lib.chineseutils.ChineseUtils;
import kotlin.Metadata;
import kotlin.jvm.internal.Intrinsics;

/* compiled from: Translate.kt */
@Metadata(d1 = {"\u0000\u0010\n\u0000\n\u0002\u0010\u000e\n\u0002\b\u0002\n\u0002\u0018\u0002\n\u0000\u001a\u0016\u0010\u0000\u001a\u00020\u00012\u0006\u0010\u0002\u001a\u00020\u00012\u0006\u0010\u0003\u001a\u00020\u0004¨\u0006\u0005"}, d2 = {"translate", "", "text", "type", "Leu/kanade/tachiyomi/extension/zh/copymanga/CCOption;", "tachiyomi-zh.copymanga-v1.4.78_release"}, k = 2, mv = {1, 7, 1}, xi = 48)
/* loaded from: classes.dex */
public final class TranslateKt {

    /* compiled from: Translate.kt */
    @Metadata(k = 3, mv = {1, 7, 1}, xi = 48)
    public /* synthetic */ class WhenMappings {
        public static final /* synthetic */ int[] $EnumSwitchMapping$0;

        static {
            int[] iArr = new int[CCOption.values().length];
            try {
                iArr[CCOption.TRADITIONAL.ordinal()] = 1;
            } catch (NoSuchFieldError unused) {
            }
            try {
                iArr[CCOption.SIMPLIFIED.ordinal()] = 2;
            } catch (NoSuchFieldError unused2) {
            }
            $EnumSwitchMapping$0 = iArr;
        }
    }

    public static final String translate(String str, CCOption cCOption) {
        Intrinsics.checkNotNullParameter(str, "text");
        Intrinsics.checkNotNullParameter(cCOption, "type");
        int i = WhenMappings.$EnumSwitchMapping$0[cCOption.ordinal()];
        if (i == 1) {
            String traditional = ChineseUtils.toTraditional(str);
            Intrinsics.checkNotNullExpressionValue(traditional, "toTraditional(text)");
            return traditional;
        }
        if (i != 2) {
            return str;
        }
        String simplified = ChineseUtils.toSimplified(str);
        Intrinsics.checkNotNullExpressionValue(simplified, "toSimplified(text)");
        return simplified;
    }
}
