package eu.kanade.tachiyomi.extension.zh.copymanga.interceptor;

import eu.kanade.tachiyomi.extension.zh.copymanga.api.ApiRepo;
import java.util.Collection;
import java.util.Iterator;
import java.util.List;
import java.util.concurrent.atomic.AtomicLong;
import kotlin.Metadata;
import kotlin.Unit;
import kotlin.jvm.internal.Intrinsics;
import kotlin.text.StringsKt;
import okhttp3.Interceptor;
import okhttp3.Request;
import okhttp3.Response;

/* JADX INFO: compiled from: RateLimitInterceptor.kt */
/* JADX INFO: loaded from: classes.dex */
@Metadata(d1 = {"\u0000*\n\u0002\u0018\u0002\n\u0002\u0018\u0002\n\u0002\b\u0002\n\u0002\u0018\u0002\n\u0000\n\u0002\u0010\u0000\n\u0000\n\u0002\u0010\t\n\u0000\n\u0002\u0018\u0002\n\u0000\n\u0002\u0018\u0002\n\u0000\u0018\u00002\u00020\u0001B\u0005¢\u0006\u0002\u0010\u0002J\u0010\u0010\t\u001a\u00020\n2\u0006\u0010\u000b\u001a\u00020\fH\u0016R\u000e\u0010\u0003\u001a\u00020\u0004X\u0082\u0004¢\u0006\u0002\n\u0000R\u000e\u0010\u0005\u001a\u00020\u0006X\u0082\u0004¢\u0006\u0002\n\u0000R\u000e\u0010\u0007\u001a\u00020\bX\u0082D¢\u0006\u0002\n\u0000¨\u0006\r"}, d2 = {"Leu/kanade/tachiyomi/extension/zh/copymanga/interceptor/RateLimitInterceptor;", "Lokhttp3/Interceptor;", "()V", "lastRequestTime", "Ljava/util/concurrent/atomic/AtomicLong;", "lock", "", "periodMillis", "", "intercept", "Lokhttp3/Response;", "chain", "Lokhttp3/Interceptor$Chain;", "tachiyomi-zh.copymanga-v1.4.82_release"}, k = 1, mv = {1, 7, 1}, xi = 48)
public final class RateLimitInterceptor implements Interceptor {
    private final Object lock = new Object();
    private final AtomicLong lastRequestTime = new AtomicLong(0);
    private final long periodMillis = 100;

    public Response intercept(Interceptor.Chain chain) {
        Intrinsics.checkNotNullParameter(chain, "chain");
        Request request = chain.request();
        List<String> rate_limit_domain = ApiRepo.INSTANCE.getRATE_LIMIT_DOMAIN();
        if (!(rate_limit_domain instanceof Collection) || !rate_limit_domain.isEmpty()) {
            Iterator<T> it = rate_limit_domain.iterator();
            while (it.hasNext()) {
                if (StringsKt.contains$default(request.url().toString(), (String) it.next(), false, 2, (Object) null)) {
                    synchronized (this.lock) {
                        long jCurrentTimeMillis = this.periodMillis - (System.currentTimeMillis() - this.lastRequestTime.get());
                        if (jCurrentTimeMillis > 0) {
                            try {
                                Thread.sleep(jCurrentTimeMillis);
                            } catch (InterruptedException unused) {
                            }
                        }
                        this.lastRequestTime.set(System.currentTimeMillis());
                        Unit unit = Unit.INSTANCE;
                    }
                    return chain.proceed(request);
                }
            }
        }
        return chain.proceed(request);
    }
}
