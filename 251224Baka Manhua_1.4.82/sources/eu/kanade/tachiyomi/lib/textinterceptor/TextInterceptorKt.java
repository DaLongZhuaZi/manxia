package eu.kanade.tachiyomi.lib.textinterceptor;

import android.os.Build;
import android.text.Html;
import kotlin.Metadata;
import kotlin.collections.CollectionsKt;
import kotlin.jvm.functions.Function1;
import kotlin.jvm.internal.Intrinsics;
import kotlin.text.Regex;
import kotlin.text.RegexOption;

/* JADX INFO: compiled from: TextInterceptor.kt */
/* JADX INFO: loaded from: classes.dex */
@Metadata(d1 = {"\u0000\u001e\n\u0000\n\u0002\u0010\u0007\n\u0000\n\u0002\u0010\b\n\u0002\b\u0002\n\u0002\u0010\u000e\n\u0000\n\u0002\u0018\u0002\n\u0002\b\t\u001a\u0010\u0010\u000f\u001a\u00020\u00062\u0006\u0010\u0010\u001a\u00020\u0006H\u0003\"\u000e\u0010\u0000\u001a\u00020\u0001X\u0082T¢\u0006\u0002\n\u0000\"\u000e\u0010\u0002\u001a\u00020\u0003X\u0082T¢\u0006\u0002\n\u0000\"\u000e\u0010\u0004\u001a\u00020\u0001X\u0082T¢\u0006\u0002\n\u0000\"\u000e\u0010\u0005\u001a\u00020\u0006X\u0082T¢\u0006\u0002\n\u0000\"\u000e\u0010\u0007\u001a\u00020\bX\u0082\u0004¢\u0006\u0002\n\u0000\"\u000e\u0010\t\u001a\u00020\u0001X\u0082T¢\u0006\u0002\n\u0000\"\u000e\u0010\n\u001a\u00020\u0001X\u0082T¢\u0006\u0002\n\u0000\"\u000e\u0010\u000b\u001a\u00020\u0006X\u0082T¢\u0006\u0002\n\u0000\"\u000e\u0010\f\u001a\u00020\u0003X\u0082T¢\u0006\u0002\n\u0000\"\u000e\u0010\r\u001a\u00020\u0001X\u0082T¢\u0006\u0002\n\u0000\"\u000e\u0010\u000e\u001a\u00020\u0001X\u0082T¢\u0006\u0002\n\u0000¨\u0006\u0011"}, d2 = {"BODY_FONT_SIZE", "", "EXTRA_PARAGRAPH_SPACING", "", "HEADING_FONT_SIZE", "HOST", "", "HTML_LINE_BREAK", "Lkotlin/text/Regex;", "SPACING_ADD", "SPACING_MULT", "TAG", "WIDTH", "X_PADDING", "Y_PADDING", "htmlToPlainText", "html", "textinterceptor_release"}, k = 2, mv = {1, 7, 1}, xi = 48)
public final class TextInterceptorKt {
    private static final float BODY_FONT_SIZE = 35.0f;
    private static final int EXTRA_PARAGRAPH_SPACING = 15;
    private static final float HEADING_FONT_SIZE = 50.0f;
    private static final String HOST = "tachiyomi-lib-textinterceptor";
    private static final Regex HTML_LINE_BREAK = new Regex("<br\\s*/?>", RegexOption.IGNORE_CASE);
    private static final float SPACING_ADD = 1.0f;
    private static final float SPACING_MULT = 1.1f;
    private static final String TAG = "TextInterceptor";
    private static final int WIDTH = 1000;
    private static final float X_PADDING = 50.0f;
    private static final float Y_PADDING = 25.0f;

    /* JADX INFO: Access modifiers changed from: private */
    public static final String htmlToPlainText(String str) {
        return CollectionsKt.joinToString$default(Regex.split$default(HTML_LINE_BREAK, str, 0, 2, (Object) null), "\n", (CharSequence) null, (CharSequence) null, 0, (CharSequence) null, new Function1<String, CharSequence>() { // from class: eu.kanade.tachiyomi.lib.textinterceptor.TextInterceptorKt.htmlToPlainText.1
            public final CharSequence invoke(String str2) {
                Intrinsics.checkNotNullParameter(str2, "segment");
                if (Build.VERSION.SDK_INT >= 24) {
                    return Html.fromHtml(str2, 0).toString();
                }
                return Html.fromHtml(str2).toString();
            }
        }, 30, (Object) null);
    }
}
