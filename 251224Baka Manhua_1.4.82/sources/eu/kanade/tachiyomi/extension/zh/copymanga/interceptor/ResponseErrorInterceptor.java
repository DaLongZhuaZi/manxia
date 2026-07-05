package eu.kanade.tachiyomi.extension.zh.copymanga.interceptor;

import eu.kanade.tachiyomi.extension.zh.copymanga.api.ApiResponse;
import eu.kanade.tachiyomi.extension.zh.copymanga.api.ApiResponseKt;
import kotlin.Metadata;
import kotlin.jvm.internal.Intrinsics;
import kotlin.jvm.internal.MagicApiIntrinsics;
import kotlin.jvm.internal.Reflection;
import kotlin.reflect.KType;
import kotlin.reflect.KTypeProjection;
import kotlin.text.StringsKt;
import kotlinx.serialization.SerializersKt;
import kotlinx.serialization.StringFormat;
import kotlinx.serialization.json.JsonElement;
import kotlinx.serialization.modules.SerializersModule;
import okhttp3.Interceptor;
import okhttp3.Response;

/* JADX INFO: compiled from: ResponseErrorInterceptor.kt */
/* JADX INFO: loaded from: classes.dex */
@Metadata(d1 = {"\u0000\u001a\n\u0002\u0018\u0002\n\u0002\u0018\u0002\n\u0002\b\u0002\n\u0002\u0018\u0002\n\u0000\n\u0002\u0018\u0002\n\u0002\b\u0002\u0018\u00002\u00020\u0001:\u0001\u0007B\u0005¢\u0006\u0002\u0010\u0002J\u0010\u0010\u0003\u001a\u00020\u00042\u0006\u0010\u0005\u001a\u00020\u0006H\u0016¨\u0006\b"}, d2 = {"Leu/kanade/tachiyomi/extension/zh/copymanga/interceptor/ResponseErrorInterceptor;", "Lokhttp3/Interceptor;", "()V", "intercept", "Lokhttp3/Response;", "chain", "Lokhttp3/Interceptor$Chain;", "PlainTextException", "tachiyomi-zh.copymanga-v1.4.82_release"}, k = 1, mv = {1, 7, 1}, xi = 48)
public final class ResponseErrorInterceptor implements Interceptor {
    public Response intercept(Interceptor.Chain chain) throws PlainTextException {
        Intrinsics.checkNotNullParameter(chain, "chain");
        Response responseProceed = chain.proceed(chain.request());
        String strPeek = ApiResponseKt.peek(responseProceed);
        if (StringsKt.startsWith$default(strPeek, "error", false, 2, (Object) null)) {
            throw new PlainTextException("参数错误，请尝试在插件设定页面切换平台参数");
        }
        if (StringsKt.startsWith$default(strPeek, "<!DOCTYPE html>", false, 2, (Object) null)) {
            throw new PlainTextException("错误跳转至拷贝404页面，请尝试重新整理，若长时间无法解决则请在Github上提交Issue");
        }
        if (responseProceed.code() == 210) {
            try {
                StringFormat json = ApiResponseKt.getJson();
                SerializersModule serializersModule = json.getSerializersModule();
                KType kTypeTypeOf = Reflection.typeOf(ApiResponse.class, KTypeProjection.Companion.invariant(Reflection.typeOf(JsonElement.class)));
                MagicApiIntrinsics.voidMagicApiCall("kotlinx.serialization.serializer.withModule");
                String message = ((ApiResponse) json.decodeFromString(SerializersKt.serializer(serializersModule, kTypeTypeOf), strPeek)).getMessage();
                if (StringsKt.contains$default(message, "APP", false, 2, (Object) null)) {
                    message = "触发拷贝漫画防盗版机制，请尝试开启VPN/切换节点/更换域名 (现已支持热辣漫画)";
                } else if (StringsKt.contains$default(message, "合法的整数值", false, 2, (Object) null) || StringsKt.contains$default(message, "有效的整數值", false, 2, (Object) null)) {
                    message = message + " 请尝试在插件设定页面切换平台参数 (可先尝试切换1)";
                }
                strPeek = message;
            } catch (Exception unused) {
            }
            throw new PlainTextException("HTTP 210 : " + strPeek);
        }
        if (responseProceed.code() == 404) {
            throw new PlainTextException("HTTP 404 : 请尝试在插件设定页面切换API域名 " + chain.request().url());
        }
        if (responseProceed.code() == 503) {
            throw new PlainTextException("HTTP 503 : 请在WebView检查网站，通常是拷贝寄了导致的");
        }
        return ApiResponseKt.newResponse(responseProceed);
    }

    /* JADX INFO: compiled from: ResponseErrorInterceptor.kt */
    @Metadata(d1 = {"\u0000\u0016\n\u0002\u0018\u0002\n\u0002\u0018\u0002\n\u0002\u0018\u0002\n\u0000\n\u0002\u0010\u000e\n\u0002\b\u0004\b\u0000\u0018\u00002\u00060\u0001j\u0002`\u0002B\r\u0012\u0006\u0010\u0003\u001a\u00020\u0004¢\u0006\u0002\u0010\u0005J\b\u0010\u0006\u001a\u00020\u0004H\u0016J\b\u0010\u0007\u001a\u00020\u0004H\u0016¨\u0006\b"}, d2 = {"Leu/kanade/tachiyomi/extension/zh/copymanga/interceptor/ResponseErrorInterceptor$PlainTextException;", "Ljava/lang/Exception;", "Lkotlin/Exception;", "msg", "", "(Ljava/lang/String;)V", "getLocalizedMessage", "toString", "tachiyomi-zh.copymanga-v1.4.82_release"}, k = 1, mv = {1, 7, 1}, xi = 48)
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
