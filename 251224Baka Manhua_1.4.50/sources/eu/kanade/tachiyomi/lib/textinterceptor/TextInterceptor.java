package eu.kanade.tachiyomi.lib.textinterceptor;

import android.graphics.Bitmap;
import android.graphics.Canvas;
import android.graphics.Typeface;
import android.net.Uri;
import android.os.Build;
import android.text.Html;
import android.text.Layout;
import android.text.StaticLayout;
import android.text.TextPaint;
import android.util.Log;
import java.io.ByteArrayOutputStream;
import java.util.ArrayList;
import java.util.Iterator;
import java.util.List;
import kotlin.Metadata;
import kotlin.collections.CollectionsKt;
import kotlin.jvm.internal.Intrinsics;
import kotlin.ranges.RangesKt;
import kotlin.text.StringsKt;
import okhttp3.HttpUrl;
import okhttp3.Interceptor;
import okhttp3.MediaType;
import okhttp3.Protocol;
import okhttp3.Request;
import okhttp3.Response;
import okhttp3.ResponseBody;

/* compiled from: TextInterceptor.kt */
@Metadata(d1 = {"\u00008\n\u0002\u0018\u0002\n\u0002\u0018\u0002\n\u0002\b\u0002\n\u0002\u0018\u0002\n\u0000\n\u0002\u0018\u0002\n\u0000\n\u0002\u0010\u000e\n\u0002\b\u0002\n\u0002\u0010\u0002\n\u0002\u0018\u0002\n\u0000\n\u0002\u0018\u0002\n\u0000\n\u0002\u0010\u0007\n\u0002\b\u0002\u0018\u00002\u00020\u0001B\u0005¢\u0006\u0002\u0010\u0002J\u0010\u0010\u0003\u001a\u00020\u00042\u0006\u0010\u0005\u001a\u00020\u0006H\u0016J\u0010\u0010\u0007\u001a\u00020\b2\u0006\u0010\t\u001a\u00020\bH\u0003J$\u0010\n\u001a\u00020\u000b*\u00020\f2\u0006\u0010\r\u001a\u00020\u000e2\u0006\u0010\u000f\u001a\u00020\u00102\u0006\u0010\u0011\u001a\u00020\u0010H\u0002¨\u0006\u0012"}, d2 = {"Leu/kanade/tachiyomi/lib/textinterceptor/TextInterceptor;", "Lokhttp3/Interceptor;", "()V", "intercept", "Lokhttp3/Response;", "chain", "Lokhttp3/Interceptor$Chain;", "textFixer", "", "html", "draw", "", "Landroid/text/StaticLayout;", "canvas", "Landroid/graphics/Canvas;", "x", "", "y", "textinterceptor_release"}, k = 1, mv = {1, 7, 1}, xi = 48)
/* loaded from: classes.dex */
public final class TextInterceptor implements Interceptor {
    public Response intercept(Interceptor.Chain chain) {
        Intrinsics.checkNotNullParameter(chain, "chain");
        Request request = chain.request();
        HttpUrl httpUrlUrl = request.url();
        if (!Intrinsics.areEqual(httpUrlUrl.host(), TextInterceptorHelper.HOST)) {
            return chain.proceed(request);
        }
        long jCurrentTimeMillis = System.currentTimeMillis();
        String str = (String) CollectionsKt.getOrNull(httpUrlUrl.pathSegments(), 0);
        if (str == null) {
            str = "";
        }
        String strEncodedFragment = httpUrlUrl.encodedFragment();
        String strDecode = Uri.decode(strEncodedFragment != null ? strEncodedFragment : "");
        int length = strDecode.length();
        StaticLayout staticLayout = null;
        if (str.length() <= 0) {
            str = null;
        }
        if (str != null) {
            String strTextFixer = textFixer(str);
            TextPaint textPaint = new TextPaint();
            textPaint.setColor(-16777216);
            textPaint.setTextSize(50.0f);
            textPaint.setTypeface(Typeface.DEFAULT_BOLD);
            textPaint.setAntiAlias(true);
            staticLayout = new StaticLayout(strTextFixer, textPaint, 900, Layout.Alignment.ALIGN_NORMAL, 1.1f, 1.0f, true);
        }
        Intrinsics.checkNotNullExpressionValue(strDecode, "rawHtml");
        List listSplit$default = StringsKt.split$default(textFixer(strDecode), new char[]{'\n'}, false, 0, 6, (Object) null);
        TextPaint textPaint2 = new TextPaint();
        textPaint2.setColor(-16777216);
        textPaint2.setTextSize(35.0f);
        textPaint2.setTypeface(Typeface.DEFAULT);
        textPaint2.setAntiAlias(true);
        List list = listSplit$default;
        ArrayList arrayList = new ArrayList(CollectionsKt.collectionSizeOrDefault(list, 10));
        Iterator it = list.iterator();
        while (it.hasNext()) {
            arrayList.add(new StaticLayout((String) it.next(), textPaint2, 900, Layout.Alignment.ALIGN_NORMAL, 1.1f, 1.0f, true));
        }
        ArrayList arrayList2 = arrayList;
        int height = staticLayout != null ? staticLayout.getHeight() : 0;
        Iterator it2 = arrayList2.iterator();
        int height2 = 0;
        while (it2.hasNext()) {
            height2 += ((StaticLayout) it2.next()).getHeight();
        }
        Bitmap bitmapCreateBitmap = Bitmap.createBitmap(1000, (int) (height2 + (RangesKt.coerceAtLeast(listSplit$default.size() - 1, 0) * 15) + height + 50.0f), Bitmap.Config.ARGB_8888);
        Intrinsics.checkNotNullExpressionValue(bitmapCreateBitmap, "createBitmap(WIDTH, imgH… Bitmap.Config.ARGB_8888)");
        Canvas canvas = new Canvas(bitmapCreateBitmap);
        canvas.drawColor(-1);
        if (staticLayout != null) {
            draw(staticLayout, canvas, 50.0f, 25.0f);
        }
        float height3 = height + 25.0f;
        Iterator it3 = arrayList2.iterator();
        while (it3.hasNext()) {
            draw((StaticLayout) it3.next(), canvas, 50.0f, height3);
            height3 += r10.getHeight() + 15;
        }
        long jCurrentTimeMillis2 = System.currentTimeMillis() - jCurrentTimeMillis;
        StringBuilder sb = new StringBuilder("render finished in ");
        sb.append(jCurrentTimeMillis2);
        sb.append("ms, titleLen=");
        String str2 = (String) CollectionsKt.getOrNull(httpUrlUrl.pathSegments(), 0);
        sb.append(str2 != null ? str2.length() : 0);
        sb.append(", bodyLen=");
        sb.append(length);
        Log.i("TextInterceptor", sb.toString());
        ByteArrayOutputStream byteArrayOutputStream = new ByteArrayOutputStream();
        bitmapCreateBitmap.compress(Bitmap.CompressFormat.PNG, 100, byteArrayOutputStream);
        Response.Builder builderMessage = new Response.Builder().request(request).protocol(Protocol.HTTP_1_1).code(200).message("OK");
        ResponseBody.Companion companion = ResponseBody.Companion;
        byte[] byteArray = byteArrayOutputStream.toByteArray();
        Intrinsics.checkNotNullExpressionValue(byteArray, "out.toByteArray()");
        return builderMessage.body(companion.create(byteArray, MediaType.Companion.get("image/png"))).build();
    }

    private final String textFixer(String html) {
        if (Build.VERSION.SDK_INT >= 24) {
            return Html.fromHtml(html, 0).toString();
        }
        return Html.fromHtml(html).toString();
    }

    private final void draw(StaticLayout staticLayout, Canvas canvas, float f, float f2) {
        canvas.save();
        canvas.translate(f, f2);
        staticLayout.draw(canvas);
        canvas.restore();
    }
}
