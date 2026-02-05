package eu.kanade.tachiyomi.extension.zh.copymanga.interceptor;

import java.net.ConnectException;
import java.net.SocketException;
import java.net.SocketTimeoutException;
import java.net.UnknownHostException;
import javax.net.ssl.SSLHandshakeException;
import javax.net.ssl.SSLPeerUnverifiedException;
import kotlin.Metadata;
import kotlin.Result;
import kotlin.ResultKt;
import kotlin.jvm.internal.Intrinsics;
import kotlin.text.StringsKt;
import okhttp3.Interceptor;
import okhttp3.Response;

/* compiled from: ExceptionInterceptor.kt */
@Metadata(d1 = {"\u0000\u001a\n\u0002\u0018\u0002\n\u0002\u0018\u0002\n\u0002\b\u0002\n\u0002\u0018\u0002\n\u0000\n\u0002\u0018\u0002\n\u0002\b\u0002\u0018\u00002\u00020\u0001:\u0001\u0007B\u0005¢\u0006\u0002\u0010\u0002J\u0010\u0010\u0003\u001a\u00020\u00042\u0006\u0010\u0005\u001a\u00020\u0006H\u0016¨\u0006\b"}, d2 = {"Leu/kanade/tachiyomi/extension/zh/copymanga/interceptor/ExceptionInterceptor;", "Lokhttp3/Interceptor;", "()V", "intercept", "Lokhttp3/Response;", "chain", "Lokhttp3/Interceptor$Chain;", "PlainTextException", "tachiyomi-zh.copymanga-v1.4.78_release"}, k = 1, mv = {1, 7, 1}, xi = 48)
/* loaded from: classes.dex */
public final class ExceptionInterceptor implements Interceptor {
    public Response intercept(Interceptor.Chain chain) throws PlainTextException {
        Object obj;
        String str;
        Intrinsics.checkNotNullParameter(chain, "chain");
        try {
            Result.Companion companion = Result.Companion;
            ExceptionInterceptor exceptionInterceptor = this;
            obj = Result.constructor-impl(chain.proceed(chain.request()));
        } catch (Throwable th) {
            Result.Companion companion2 = Result.Companion;
            obj = Result.constructor-impl(ResultKt.createFailure(th));
        }
        Throwable th2 = Result.exceptionOrNull-impl(obj);
        if (th2 != null) {
            if (th2 instanceof SSLHandshakeException ? true : th2 instanceof SSLPeerUnverifiedException) {
                str = "SSL 封鎖，切換 API 域名或 VPN (" + th2.getMessage() + ')';
            } else if (th2 instanceof UnknownHostException) {
                str = "DNS 污染，請切換 DNS (" + th2.getMessage() + ')';
            } else if (th2 instanceof ConnectException) {
                str = "代理/節點故障，請切換 VPN (" + th2.getMessage() + ')';
            } else if (th2 instanceof SocketException) {
                String message = th2.getMessage();
                if (message != null && StringsKt.contains(message, "reset", true)) {
                    str = "Reset，連線被阻擋 (" + th2.getMessage() + ')';
                } else {
                    str = "網路錯誤 (" + th2.getMessage() + ')';
                }
            } else if (th2 instanceof SocketTimeoutException) {
                str = "連線逾時，請切換節點 (" + th2.getMessage() + ')';
            } else {
                str = "未知網路錯誤 (" + th2.getMessage() + ')';
            }
            throw new PlainTextException(str);
        }
        return (Response) obj;
    }

    /* compiled from: ExceptionInterceptor.kt */
    @Metadata(d1 = {"\u0000\u0016\n\u0002\u0018\u0002\n\u0002\u0018\u0002\n\u0002\u0018\u0002\n\u0000\n\u0002\u0010\u000e\n\u0002\b\u0004\b\u0000\u0018\u00002\u00060\u0001j\u0002`\u0002B\r\u0012\u0006\u0010\u0003\u001a\u00020\u0004¢\u0006\u0002\u0010\u0005J\b\u0010\u0006\u001a\u00020\u0004H\u0016J\b\u0010\u0007\u001a\u00020\u0004H\u0016¨\u0006\b"}, d2 = {"Leu/kanade/tachiyomi/extension/zh/copymanga/interceptor/ExceptionInterceptor$PlainTextException;", "Ljava/lang/Exception;", "Lkotlin/Exception;", "msg", "", "(Ljava/lang/String;)V", "getLocalizedMessage", "toString", "tachiyomi-zh.copymanga-v1.4.78_release"}, k = 1, mv = {1, 7, 1}, xi = 48)
    public static final class PlainTextException extends Exception {
        /* JADX WARN: 'super' call moved to the top of the method (can break code semantics) */
        public PlainTextException(String str) {
            super(str);
            Intrinsics.checkNotNullParameter(str, "msg");
        }

        @Override // java.lang.Throwable
        public String toString() {
            String message = getMessage();
            return message == null ? "" : message;
        }

        @Override // java.lang.Throwable
        public String getLocalizedMessage() {
            String message = getMessage();
            return message == null ? "" : message;
        }
    }
}
