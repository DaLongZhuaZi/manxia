package eu.kanade.tachiyomi.extension.zh.copymanga.api.dto;

import java.text.ParseException;
import java.text.SimpleDateFormat;
import java.util.Date;
import java.util.Locale;
import kotlin.Lazy;
import kotlin.LazyKt;
import kotlin.Metadata;
import kotlin.jvm.functions.Function0;
import kotlin.jvm.internal.Intrinsics;

/* compiled from: ChapterListResult.kt */
@Metadata(d1 = {"\u0000\u0016\n\u0000\n\u0002\u0018\u0002\n\u0002\b\u0005\n\u0002\u0010\t\n\u0000\n\u0002\u0010\u000e\n\u0000\u001a\u000e\u0010\u0006\u001a\u00020\u00072\u0006\u0010\b\u001a\u00020\t\"\u001b\u0010\u0000\u001a\u00020\u00018BX\u0082\u0084\u0002¢\u0006\f\n\u0004\b\u0004\u0010\u0005\u001a\u0004\b\u0002\u0010\u0003¨\u0006\n"}, d2 = {"dateFormat", "Ljava/text/SimpleDateFormat;", "getDateFormat", "()Ljava/text/SimpleDateFormat;", "dateFormat$delegate", "Lkotlin/Lazy;", "parseDate", "", "dateStr", "", "tachiyomi-zh.copymanga-v1.4.78_release"}, k = 2, mv = {1, 7, 1}, xi = 48)
/* loaded from: classes.dex */
public final class ChapterListResultKt {
    private static final Lazy dateFormat$delegate = LazyKt.lazy(new Function0<SimpleDateFormat>() { // from class: eu.kanade.tachiyomi.extension.zh.copymanga.api.dto.ChapterListResultKt$dateFormat$2
        public final SimpleDateFormat invoke() {
            return new SimpleDateFormat("yyyy-MM-dd", Locale.getDefault());
        }
    });

    public static final long parseDate(String str) {
        Intrinsics.checkNotNullParameter(str, "dateStr");
        try {
            Date date = getDateFormat().parse(str);
            if (date != null) {
                return date.getTime();
            }
            return 0L;
        } catch (ParseException unused) {
            return 0L;
        }
    }

    private static final SimpleDateFormat getDateFormat() {
        return (SimpleDateFormat) dateFormat$delegate.getValue();
    }
}
