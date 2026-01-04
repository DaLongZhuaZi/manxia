package eu.kanade.tachiyomi.multisrc.madara;

import kotlin.Metadata;
import kotlin.jvm.internal.Intrinsics;
import kotlin.text.StringsKt;

/* compiled from: Madara.kt */
@Metadata(d1 = {"\u0000\u001e\n\u0002\u0018\u0002\n\u0002\u0010\u0000\n\u0000\n\u0002\u0010\u0011\n\u0002\u0010\u000e\n\u0002\b\u0003\n\u0002\u0010\u000b\n\u0002\b\u0004\u0018\u00002\u00020\u0001B\u0019\u0012\u0012\u0010\u0002\u001a\n\u0012\u0006\b\u0001\u0012\u00020\u00040\u0003\"\u00020\u0004¢\u0006\u0002\u0010\u0005J\u000e\u0010\u0007\u001a\u00020\b2\u0006\u0010\t\u001a\u00020\u0004J\u000e\u0010\n\u001a\u00020\b2\u0006\u0010\t\u001a\u00020\u0004J\u000e\u0010\u000b\u001a\u00020\b2\u0006\u0010\t\u001a\u00020\u0004R\u0018\u0010\u0002\u001a\n\u0012\u0006\b\u0001\u0012\u00020\u00040\u0003X\u0082\u0004¢\u0006\u0004\n\u0002\u0010\u0006¨\u0006\f"}, d2 = {"Leu/kanade/tachiyomi/multisrc/madara/WordSet;", "", "words", "", "", "([Ljava/lang/String;)V", "[Ljava/lang/String;", "anyWordIn", "", "dateString", "endsWith", "startsWith", "madara_debug"}, k = 1, mv = {1, 7, 1}, xi = 48)
/* loaded from: classes.dex */
public final class WordSet {
    private final String[] words;

    public WordSet(String... words) {
        Intrinsics.checkNotNullParameter(words, "words");
        this.words = words;
    }

    public final boolean anyWordIn(String dateString) {
        Intrinsics.checkNotNullParameter(dateString, "dateString");
        Object[] $this$any$iv = this.words;
        for (Object element$iv : $this$any$iv) {
            if (StringsKt.contains(dateString, (CharSequence) element$iv, true)) {
                return true;
            }
        }
        return false;
    }

    public final boolean startsWith(String dateString) {
        Intrinsics.checkNotNullParameter(dateString, "dateString");
        for (String str : this.words) {
            if (StringsKt.startsWith(dateString, str, true)) {
                return true;
            }
        }
        return false;
    }

    public final boolean endsWith(String dateString) {
        Intrinsics.checkNotNullParameter(dateString, "dateString");
        for (String str : this.words) {
            if (StringsKt.endsWith(dateString, str, true)) {
                return true;
            }
        }
        return false;
    }
}
