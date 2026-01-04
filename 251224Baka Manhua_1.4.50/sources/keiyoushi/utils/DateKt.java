package keiyoushi.utils;

import java.text.ParseException;
import java.text.SimpleDateFormat;
import java.util.Date;
import kotlin.Metadata;
import kotlin.jvm.internal.Intrinsics;

/* compiled from: Date.kt */
@Metadata(d1 = {"\u0000\u0012\n\u0000\n\u0002\u0010\t\n\u0002\u0018\u0002\n\u0000\n\u0002\u0010\u000e\n\u0000\u001a\u0017\u0010\u0000\u001a\u00020\u0001*\u00020\u00022\b\u0010\u0003\u001a\u0004\u0018\u00010\u0004H\u0086\b¨\u0006\u0005"}, d2 = {"tryParse", "", "Ljava/text/SimpleDateFormat;", "date", "", "core_debug"}, k = 2, mv = {1, 7, 1}, xi = 48)
/* loaded from: classes.dex */
public final class DateKt {
    public static final long tryParse(SimpleDateFormat $this$tryParse, String date) {
        Intrinsics.checkNotNullParameter($this$tryParse, "<this>");
        if (date == null) {
            return 0L;
        }
        try {
            Date date2 = $this$tryParse.parse(date);
            if (date2 != null) {
                return date2.getTime();
            }
            return 0L;
        } catch (ParseException e) {
            return 0L;
        }
    }
}
