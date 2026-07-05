package eu.kanade.tachiyomi.extension.zh.copymanga.interceptor;

import android.content.SharedPreferences;
import eu.kanade.tachiyomi.extension.zh.copymanga.ApiDomainOption;
import eu.kanade.tachiyomi.extension.zh.copymanga.PlatFormOption;
import eu.kanade.tachiyomi.extension.zh.copymanga.PreferencesKt;
import java.util.Iterator;
import java.util.List;
import kotlin.Metadata;
import kotlin.Pair;
import kotlin.collections.CollectionsKt;
import kotlin.jvm.internal.Intrinsics;
import okhttp3.Headers;
import okhttp3.Interceptor;
import okhttp3.Request;
import okhttp3.Response;

/* JADX INFO: compiled from: HeadersInterceptor.kt */
/* JADX INFO: loaded from: classes.dex */
@Metadata(d1 = {"\u00002\n\u0002\u0018\u0002\n\u0002\u0018\u0002\n\u0000\n\u0002\u0018\u0002\n\u0002\b\u0002\n\u0002\u0018\u0002\n\u0002\b\u0003\n\u0002\u0010 \n\u0002\u0010\u000e\n\u0002\b\u0003\n\u0002\u0018\u0002\n\u0000\n\u0002\u0018\u0002\n\u0000\u0018\u00002\u00020\u0001B\r\u0012\u0006\u0010\u0002\u001a\u00020\u0003¢\u0006\u0002\u0010\u0004J\u0010\u0010\u000e\u001a\u00020\u000f2\u0006\u0010\u0010\u001a\u00020\u0011H\u0016R\u0011\u0010\u0005\u001a\u00020\u0006¢\u0006\b\n\u0000\u001a\u0004\b\u0007\u0010\bR\u000e\u0010\u0002\u001a\u00020\u0003X\u0082\u0004¢\u0006\u0002\n\u0000R\u0017\u0010\t\u001a\b\u0012\u0004\u0012\u00020\u000b0\n¢\u0006\b\n\u0000\u001a\u0004\b\f\u0010\r¨\u0006\u0012"}, d2 = {"Leu/kanade/tachiyomi/extension/zh/copymanga/interceptor/HeadersInterceptor;", "Lokhttp3/Interceptor;", "preferences", "Landroid/content/SharedPreferences;", "(Landroid/content/SharedPreferences;)V", "insertHeader", "Lokhttp3/Headers;", "getInsertHeader", "()Lokhttp3/Headers;", "removeHeader", "", "", "getRemoveHeader", "()Ljava/util/List;", "intercept", "Lokhttp3/Response;", "chain", "Lokhttp3/Interceptor$Chain;", "tachiyomi-zh.copymanga-v1.4.82_release"}, k = 1, mv = {1, 7, 1}, xi = 48)
public final class HeadersInterceptor implements Interceptor {
    private final Headers insertHeader;
    private final SharedPreferences preferences;
    private final List<String> removeHeader;

    public HeadersInterceptor(SharedPreferences sharedPreferences) {
        Intrinsics.checkNotNullParameter(sharedPreferences, "preferences");
        this.preferences = sharedPreferences;
        this.insertHeader = Headers.Companion.of(new String[]{"sec-fetch-dest", "document", "sec-fetch-mode", "navigate", "sec-fetch-site", "same-origin", "sec-fetch-user", "?1", "upgrade-insecure-requests", "1"});
        this.removeHeader = CollectionsKt.listOf("Cache-Control");
    }

    public final Headers getInsertHeader() {
        return this.insertHeader;
    }

    public final List<String> getRemoveHeader() {
        return this.removeHeader;
    }

    public Response intercept(Interceptor.Chain chain) throws Exception {
        Intrinsics.checkNotNullParameter(chain, "chain");
        Request.Builder builderNewBuilder = chain.request().newBuilder();
        for (Pair pair : ApiDomainOption.INSTANCE.getOptionByHttp(chain.request().url().toString()).getHeaders()) {
            builderNewBuilder.addHeader((String) pair.component1(), (String) pair.component2());
        }
        String strKey2value = PlatFormOption.INSTANCE.key2value(PreferencesKt.getPlatFormOptionKey(this.preferences));
        if (strKey2value.length() > 0) {
            builderNewBuilder.addHeader("platform", strKey2value);
        }
        for (Pair pair2 : this.insertHeader) {
            builderNewBuilder.addHeader((String) pair2.component1(), (String) pair2.component2());
        }
        Iterator<T> it = this.removeHeader.iterator();
        while (it.hasNext()) {
            builderNewBuilder.removeHeader((String) it.next());
        }
        return chain.proceed(builderNewBuilder.build());
    }
}
