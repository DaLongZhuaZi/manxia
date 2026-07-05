package eu.kanade.tachiyomi.lib.textinterceptor;

import android.graphics.Typeface;
import android.net.Uri;
import android.os.Build;
import android.text.Layout;
import android.text.StaticLayout;
import android.text.TextPaint;
import kotlin.Metadata;
import kotlin.jvm.internal.Intrinsics;

/* JADX INFO: compiled from: TextInterceptor.kt */
/* JADX INFO: loaded from: classes.dex */
@Metadata(d1 = {"\u0000\u001a\n\u0002\u0018\u0002\n\u0002\u0010\u0000\n\u0002\b\u0002\n\u0002\u0010\u000e\n\u0000\n\u0002\u0010\b\n\u0002\b\u0005\bÆ\u0002\u0018\u00002\u00020\u0001B\u0007\b\u0002¢\u0006\u0002\u0010\u0002J\u000e\u0010\u0005\u001a\u00020\u00062\u0006\u0010\u0007\u001a\u00020\u0004J\u0016\u0010\b\u001a\u00020\u00042\u0006\u0010\t\u001a\u00020\u00042\u0006\u0010\n\u001a\u00020\u0004R\u000e\u0010\u0003\u001a\u00020\u0004X\u0086T¢\u0006\u0002\n\u0000¨\u0006\u000b"}, d2 = {"Leu/kanade/tachiyomi/lib/textinterceptor/TextInterceptorHelper;", "", "()V", "HOST", "", "countLines", "", "html", "createUrl", "title", "text", "textinterceptor_release"}, k = 1, mv = {1, 7, 1}, xi = 48)
public final class TextInterceptorHelper {
    public static final String HOST = "tachiyomi-lib-textinterceptor";
    public static final TextInterceptorHelper INSTANCE = new TextInterceptorHelper();

    private TextInterceptorHelper() {
    }

    public final int countLines(String html) {
        StaticLayout staticLayout;
        Intrinsics.checkNotNullParameter(html, "html");
        try {
            String strHtmlToPlainText = TextInterceptorKt.htmlToPlainText(html);
            TextPaint textPaint = new TextPaint();
            textPaint.setColor(-16777216);
            textPaint.setTextSize(35.0f);
            textPaint.setTypeface(Typeface.DEFAULT);
            textPaint.setAntiAlias(true);
            if (Build.VERSION.SDK_INT >= 23) {
                staticLayout = StaticLayout.Builder.obtain(strHtmlToPlainText, 0, strHtmlToPlainText.length(), textPaint, 900).setAlignment(Layout.Alignment.ALIGN_NORMAL).setLineSpacing(1.0f, 1.1f).setIncludePad(true).build();
            } else {
                staticLayout = new StaticLayout(strHtmlToPlainText, textPaint, 900, Layout.Alignment.ALIGN_NORMAL, 1.1f, 1.0f, true);
            }
            Intrinsics.checkNotNullExpressionValue(staticLayout, "if (Build.VERSION.SDK_IN…          )\n            }");
            return staticLayout.getLineCount();
        } catch (Throwable unused) {
            return (html.length() / 22) + 1;
        }
    }

    public final String createUrl(String title, String text) {
        Intrinsics.checkNotNullParameter(title, "title");
        Intrinsics.checkNotNullParameter(text, "text");
        return "http://tachiyomi-lib-textinterceptor/" + Uri.encode(title) + '#' + Uri.encode(text);
    }
}
