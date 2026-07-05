package eu.kanade.tachiyomi.lib.textinterceptor;

import android.util.Log;
import eu.kanade.tachiyomi.lib.chineseutils.pinyin.Pinyin;
import java.net.URLDecoder;
import java.nio.charset.Charset;
import java.nio.charset.StandardCharsets;
import java.util.ArrayList;
import java.util.Iterator;
import java.util.List;
import kotlin.Metadata;
import kotlin.Result;
import kotlin.ResultKt;
import kotlin.collections.CollectionsKt;
import kotlin.jvm.internal.Intrinsics;
import kotlin.ranges.RangesKt;
import kotlin.text.Regex;
import kotlin.text.StringsKt;
import okhttp3.HttpUrl;
import okhttp3.Interceptor;
import okhttp3.MediaType;
import okhttp3.Protocol;
import okhttp3.Request;
import okhttp3.Response;
import okhttp3.ResponseBody;

/* JADX INFO: compiled from: TextInterceptorSvg.kt */
/* JADX INFO: loaded from: classes.dex */
@Metadata(d1 = {"\u00008\n\u0002\u0018\u0002\n\u0002\u0018\u0002\n\u0002\b\u0002\n\u0002\u0010\u0007\n\u0000\n\u0002\u0010\b\n\u0002\b\u0002\n\u0002\u0010\u000e\n\u0002\b\u0003\n\u0002\u0018\u0002\n\u0000\n\u0002\u0018\u0002\n\u0002\b\u0003\n\u0002\u0010 \n\u0002\b\u0003\u0018\u0000 \u00152\u00020\u0001:\u0001\u0015B\u0005¢\u0006\u0002\u0010\u0002J\u0018\u0010\u0003\u001a\u00020\u00042\u0006\u0010\u0005\u001a\u00020\u00062\u0006\u0010\u0007\u001a\u00020\u0004H\u0002J\u0010\u0010\b\u001a\u00020\t2\u0006\u0010\n\u001a\u00020\tH\u0002J\u0018\u0010\u000b\u001a\u00020\u00042\u0006\u0010\n\u001a\u00020\t2\u0006\u0010\u0007\u001a\u00020\u0004H\u0002J\u0010\u0010\f\u001a\u00020\r2\u0006\u0010\u000e\u001a\u00020\u000fH\u0016J\u0010\u0010\u0010\u001a\u00020\t2\u0006\u0010\u0011\u001a\u00020\tH\u0002J&\u0010\u0012\u001a\b\u0012\u0004\u0012\u00020\t0\u00132\u0006\u0010\n\u001a\u00020\t2\u0006\u0010\u0007\u001a\u00020\u00042\u0006\u0010\u0014\u001a\u00020\u0004H\u0002¨\u0006\u0016"}, d2 = {"Leu/kanade/tachiyomi/lib/textinterceptor/TextInterceptorSvg;", "Lokhttp3/Interceptor;", "()V", "calculateHeight", "", "lineCount", "", "fontSize", "escapeXml", "", "text", "estimateTextWidth", "intercept", "Lokhttp3/Response;", "chain", "Lokhttp3/Interceptor$Chain;", "textFixer", "html", "wrapText", "", "maxWidth", "Companion", "textinterceptor_release"}, k = 1, mv = {1, 7, 1}, xi = 48)
public final class TextInterceptorSvg implements Interceptor {
    private static final float BODY_FONT_SIZE = 35.0f;
    private static final int EXTRA_PARAGRAPH_SPACING = 15;
    private static final float HEADING_FONT_SIZE = 50.0f;
    private static final String HOST = "tachiyomi-lib-textinterceptor";
    private static final float SPACING_ADD = 1.0f;
    private static final float SPACING_MULT = 1.1f;
    private static final int WIDTH = 1000;
    private static final float X_PADDING = 50.0f;
    private static final float Y_PADDING = 25.0f;

    private final float calculateHeight(int lineCount, float fontSize) {
        return lineCount * ((fontSize * SPACING_MULT) + SPACING_ADD);
    }

    public Response intercept(Interceptor.Chain chain) {
        Object objBuild;
        List<String> listEmptyList;
        Intrinsics.checkNotNullParameter(chain, "chain");
        Request request = chain.request();
        HttpUrl httpUrlUrl = request.url();
        if (!Intrinsics.areEqual(httpUrlUrl.host(), "tachiyomi-lib-textinterceptor")) {
            return chain.proceed(request);
        }
        try {
            Result.Companion companion = Result.Companion;
            TextInterceptorSvg textInterceptorSvg = this;
            int i = 0;
            String str = (String) CollectionsKt.getOrNull(httpUrlUrl.pathSegments(), 0);
            if (str == null) {
                str = "";
            }
            String strEncodedFragment = httpUrlUrl.encodedFragment();
            if (strEncodedFragment == null) {
                strEncodedFragment = "";
            }
            try {
                strEncodedFragment = strEncodedFragment.length() > 0 ? URLDecoder.decode(strEncodedFragment, "UTF-8") : "";
            } catch (Exception unused) {
            }
            String strTextFixer = textFixer(str);
            Intrinsics.checkNotNullExpressionValue(strEncodedFragment, "bodyText");
            String strTextFixer2 = textFixer(strEncodedFragment);
            if (strTextFixer.length() > 0) {
                listEmptyList = wrapText(strTextFixer, 50.0f, 900.0f);
            } else {
                listEmptyList = CollectionsKt.emptyList();
            }
            List<String> listSplit$default = StringsKt.split$default(strTextFixer2, new char[]{'\n'}, false, 0, 6, (Object) null);
            ArrayList arrayList = new ArrayList(CollectionsKt.collectionSizeOrDefault(listSplit$default, 10));
            for (String str2 : listSplit$default) {
                arrayList.add(str2.length() == 0 ? CollectionsKt.listOf("") : wrapText(str2, BODY_FONT_SIZE, 900.0f));
            }
            ArrayList arrayList2 = arrayList;
            float fCalculateHeight = 0.0f;
            float fCalculateHeight2 = !listEmptyList.isEmpty() ? calculateHeight(listEmptyList.size(), 50.0f) : 0.0f;
            Iterator it = arrayList2.iterator();
            while (it.hasNext()) {
                fCalculateHeight += calculateHeight(((List) it.next()).size(), BODY_FONT_SIZE);
            }
            int iCoerceAtLeast = RangesKt.coerceAtLeast((int) (fCalculateHeight2 + fCalculateHeight + (RangesKt.coerceAtLeast(r9.size() - 1, 0) * EXTRA_PARAGRAPH_SPACING) + 50.0f), 1);
            StringBuilder sb = new StringBuilder();
            sb.append("<svg width=\"1000\" height=\"" + iCoerceAtLeast + "\" viewBox=\"0 0 1000 " + iCoerceAtLeast + "\" version=\"1.1\" xmlns=\"http://www.w3.org/2000/svg\">\n");
            sb.append("  <rect width=\"100%\" height=\"100%\" fill=\"white\"/>\n");
            boolean zIsEmpty = listEmptyList.isEmpty();
            float f = Y_PADDING;
            if (!zIsEmpty) {
                sb.append("  <g font-family=\"sans-serif\" font-size=\"50.0\" font-weight=\"bold\" fill=\"black\">\n");
                Iterator<String> it2 = listEmptyList.iterator();
                while (it2.hasNext()) {
                    sb.append("    <text x=\"50.0\" y=\"" + (40.0f + f) + "\">" + escapeXml(it2.next()) + "</text>\n");
                    f += 56.0f;
                }
                sb.append("  </g>\n");
            }
            sb.append("  <g font-family=\"sans-serif\" font-size=\"35.0\" font-weight=\"normal\" fill=\"black\">\n");
            Iterator it3 = arrayList2.iterator();
            while (it3.hasNext()) {
                int i2 = i + 1;
                for (String str3 : (List) it3.next()) {
                    if (str3.length() > 0) {
                        sb.append("    <text x=\"50.0\" y=\"" + (f + 28.0f) + "\">" + escapeXml(str3) + "</text>\n");
                    }
                    f += 39.5f;
                }
                if (i < arrayList2.size() - 1) {
                    f += EXTRA_PARAGRAPH_SPACING;
                }
                i = i2;
            }
            sb.append("  </g>\n");
            sb.append("</svg>");
            Response.Builder builderMessage = new Response.Builder().request(request).protocol(Protocol.HTTP_1_1).code(200).message("OK");
            ResponseBody.Companion companion2 = ResponseBody.Companion;
            String string = sb.toString();
            Intrinsics.checkNotNullExpressionValue(string, "svgBuilder\n             …              .toString()");
            Charset charset = StandardCharsets.UTF_8;
            Intrinsics.checkNotNullExpressionValue(charset, "UTF_8");
            byte[] bytes = string.getBytes(charset);
            Intrinsics.checkNotNullExpressionValue(bytes, "this as java.lang.String).getBytes(charset)");
            objBuild = Result.constructor-impl(builderMessage.body(companion2.create(bytes, MediaType.Companion.get("image/*"))).build());
        } catch (Throwable th) {
            Result.Companion companion3 = Result.Companion;
            objBuild = Result.constructor-impl(ResultKt.createFailure(th));
        }
        Throwable th2 = Result.exceptionOrNull-impl(objBuild);
        if (th2 != null) {
            Log.e("TextInterceptorSvg", "Error generating response: " + th2.getMessage(), th2);
            objBuild = new Response.Builder().request(request).protocol(Protocol.HTTP_1_1).code(500).message("Internal Server Error").body(ResponseBody.Companion.create("Generation Failed", MediaType.Companion.get("text/plain"))).build();
        }
        return (Response) objBuild;
    }

    private final List<String> wrapText(String text, float fontSize, float maxWidth) {
        List<String> listSplit$default = StringsKt.split$default(text, new String[]{Pinyin.SPACE}, false, 0, 6, (Object) null);
        ArrayList arrayList = new ArrayList();
        StringBuilder sb = new StringBuilder();
        float f = 0.0f;
        for (String str : listSplit$default) {
            float fEstimateTextWidth = estimateTextWidth(str, fontSize);
            StringBuilder sb2 = sb;
            float fEstimateTextWidth2 = sb2.length() > 0 ? estimateTextWidth(Pinyin.SPACE, fontSize) : 0.0f;
            if (f + fEstimateTextWidth2 + fEstimateTextWidth <= maxWidth) {
                if (sb2.length() > 0) {
                    sb.append(Pinyin.SPACE);
                }
                sb.append(str);
                f += fEstimateTextWidth2 + fEstimateTextWidth;
            } else {
                String string = sb.toString();
                Intrinsics.checkNotNullExpressionValue(string, "currentLine.toString()");
                arrayList.add(string);
                sb = new StringBuilder(str);
                f = fEstimateTextWidth;
            }
        }
        if (sb.length() > 0) {
            String string2 = sb.toString();
            Intrinsics.checkNotNullExpressionValue(string2, "currentLine.toString()");
            arrayList.add(string2);
        }
        return arrayList;
    }

    private final float estimateTextWidth(String text, float fontSize) {
        float f;
        float f2;
        int length = text.length();
        float f3 = 0.0f;
        for (int i = 0; i < length; i++) {
            char cCharAt = text.charAt(i);
            if (cCharAt == 'i' || cCharAt == 'l' || cCharAt == 'I' || cCharAt == '.' || cCharAt == ',' || cCharAt == '!' || cCharAt == ':' || cCharAt == ';' || cCharAt == '\'' || cCharAt == '\"' || cCharAt == '|') {
                f = 0.28f * fontSize;
            } else {
                if (cCharAt == 'm' || cCharAt == 'M' || cCharAt == 'w' || cCharAt == 'W' || cCharAt == '@' || cCharAt == '%') {
                    f2 = 0.88f;
                } else if (('A' > cCharAt || cCharAt >= '[') && ('0' > cCharAt || cCharAt >= ':')) {
                    if (cCharAt != ' ') {
                        f2 = 0.55f;
                    }
                    f = 0.28f * fontSize;
                } else {
                    f2 = 0.7f;
                }
                f = fontSize * f2;
            }
            f3 += f;
        }
        return f3;
    }

    private final String textFixer(String html) {
        return StringsKt.replace$default(StringsKt.replace$default(StringsKt.replace$default(StringsKt.replace$default(StringsKt.replace$default(StringsKt.replace$default(new Regex("<[^>]*>").replace(html, ""), "&lt;", "<", false, 4, (Object) null), "&gt;", ">", false, 4, (Object) null), "&amp;", "&", false, 4, (Object) null), "&quot;", "\"", false, 4, (Object) null), "&apos;", "'", false, 4, (Object) null), "&nbsp;", Pinyin.SPACE, false, 4, (Object) null);
    }

    private final String escapeXml(String text) {
        return StringsKt.replace$default(StringsKt.replace$default(StringsKt.replace$default(StringsKt.replace$default(StringsKt.replace$default(text, "&", "&amp;", false, 4, (Object) null), "<", "&lt;", false, 4, (Object) null), ">", "&gt;", false, 4, (Object) null), "\"", "&quot;", false, 4, (Object) null), "'", "&apos;", false, 4, (Object) null);
    }
}
