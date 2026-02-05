package eu.kanade.tachiyomi.extension.zh.copymanga.interceptor;

import android.content.SharedPreferences;
import eu.kanade.tachiyomi.extension.zh.copymanga.ApiDomainOption;
import eu.kanade.tachiyomi.extension.zh.copymanga.PreferencesKt;
import eu.kanade.tachiyomi.extension.zh.copymanga.api.ApiResponseKt;
import eu.kanade.tachiyomi.extension.zh.copymanga.special.TokenProvider;
import kotlin.Metadata;
import kotlin.jvm.internal.Intrinsics;
import kotlin.text.StringsKt;
import okhttp3.Interceptor;
import okhttp3.Request;
import okhttp3.Response;

/* compiled from: AuthorizationInterceptor.kt */
@Metadata(d1 = {"\u0000 \n\u0002\u0018\u0002\n\u0002\u0018\u0002\n\u0000\n\u0002\u0018\u0002\n\u0002\b\u0002\n\u0002\u0018\u0002\n\u0000\n\u0002\u0018\u0002\n\u0002\b\u0002\u0018\u00002\u00020\u0001:\u0001\tB\r\u0012\u0006\u0010\u0002\u001a\u00020\u0003¢\u0006\u0002\u0010\u0004J\u0010\u0010\u0005\u001a\u00020\u00062\u0006\u0010\u0007\u001a\u00020\bH\u0016R\u000e\u0010\u0002\u001a\u00020\u0003X\u0082\u0004¢\u0006\u0002\n\u0000¨\u0006\n"}, d2 = {"Leu/kanade/tachiyomi/extension/zh/copymanga/interceptor/AuthorizationInterceptor;", "Lokhttp3/Interceptor;", "preferences", "Landroid/content/SharedPreferences;", "(Landroid/content/SharedPreferences;)V", "intercept", "Lokhttp3/Response;", "chain", "Lokhttp3/Interceptor$Chain;", "AuthorizationFailedException", "tachiyomi-zh.copymanga-v1.4.78_release"}, k = 1, mv = {1, 7, 1}, xi = 48)
/* loaded from: classes.dex */
public final class AuthorizationInterceptor implements Interceptor {
    private final SharedPreferences preferences;

    public AuthorizationInterceptor(SharedPreferences sharedPreferences) {
        Intrinsics.checkNotNullParameter(sharedPreferences, "preferences");
        this.preferences = sharedPreferences;
    }

    public Response intercept(Interceptor.Chain chain) throws AuthorizationFailedException {
        String copyMangaToken;
        String strHeader;
        Intrinsics.checkNotNullParameter(chain, "chain");
        String apiDomainFromPrefs = PreferencesKt.getApiDomainFromPrefs(this.preferences);
        Request request = chain.request();
        if (!StringsKt.contains$default(request.url().toString(), apiDomainFromPrefs, false, 2, (Object) null)) {
            return chain.proceed(chain.request());
        }
        if (StringsKt.contains$default(request.url().toString(), "/system/config/2020/1", false, 2, (Object) null) && (strHeader = request.header("Authorization")) != null && StringsKt.startsWith$default(strHeader, "Token", false, 2, (Object) null)) {
            if (ApiDomainOption.INSTANCE.isHotManga(apiDomainFromPrefs)) {
                PreferencesKt.setHotMangaToken(this.preferences, StringsKt.trim(StringsKt.removePrefix(strHeader, "Token ")).toString());
            } else if (ApiDomainOption.INSTANCE.isCopyManga(apiDomainFromPrefs)) {
                PreferencesKt.setCopyMangaToken(this.preferences, StringsKt.trim(StringsKt.removePrefix(strHeader, "Token ")).toString());
            }
        }
        Request.Builder builderNewBuilder = request.newBuilder();
        if (ApiDomainOption.INSTANCE.isHotManga(apiDomainFromPrefs)) {
            copyMangaToken = PreferencesKt.getHotMangaToken(this.preferences);
        } else {
            copyMangaToken = ApiDomainOption.INSTANCE.isCopyManga(apiDomainFromPrefs) ? PreferencesKt.getCopyMangaToken(this.preferences) : "";
        }
        if (PreferencesKt.getEnableLogin(this.preferences) && TokenProvider.LoginStatus.INSTANCE.isValidToken(copyMangaToken)) {
            builderNewBuilder.addHeader("Authorization", "Token " + copyMangaToken);
        }
        Response responseProceed = chain.proceed(builderNewBuilder.build());
        if (responseProceed.code() == 401 && PreferencesKt.getEnableLogin(this.preferences)) {
            if (ApiDomainOption.INSTANCE.isHotManga(apiDomainFromPrefs) && PreferencesKt.getHotMangaToken(this.preferences).length() > 0) {
                PreferencesKt.setHotMangaToken(this.preferences, TokenProvider.LoginStatus.LOGIN_EXPIRED.getKey());
            } else if (ApiDomainOption.INSTANCE.isCopyManga(apiDomainFromPrefs) && PreferencesKt.getCopyMangaToken(this.preferences).length() > 0) {
                PreferencesKt.setCopyMangaToken(this.preferences, TokenProvider.LoginStatus.LOGIN_EXPIRED.getKey());
            }
            if (StringsKt.contains$default(responseProceed.request().url().toString(), "/api/v3/member/collect", false, 2, (Object) null)) {
                throw new AuthorizationFailedException("获取" + (ApiDomainOption.INSTANCE.isCopyManga(apiDomainFromPrefs) ? "拷貝" : "熱辣") + "源站书柜失败\n请在插键设置中开启 \"启用登入状态浏览\" 并登入\n提示 : 可透过在插键设定中切换API域名选择获取拷贝/热辣的书柜");
            }
        }
        return ApiResponseKt.newResponse(responseProceed);
    }

    /* compiled from: AuthorizationInterceptor.kt */
    @Metadata(d1 = {"\u0000\u0016\n\u0002\u0018\u0002\n\u0002\u0018\u0002\n\u0002\u0018\u0002\n\u0000\n\u0002\u0010\u000e\n\u0002\b\u0004\b\u0000\u0018\u00002\u00060\u0001j\u0002`\u0002B\r\u0012\u0006\u0010\u0003\u001a\u00020\u0004¢\u0006\u0002\u0010\u0005J\b\u0010\u0006\u001a\u00020\u0004H\u0016J\b\u0010\u0007\u001a\u00020\u0004H\u0016¨\u0006\b"}, d2 = {"Leu/kanade/tachiyomi/extension/zh/copymanga/interceptor/AuthorizationInterceptor$AuthorizationFailedException;", "Ljava/lang/Exception;", "Lkotlin/Exception;", "msg", "", "(Ljava/lang/String;)V", "getLocalizedMessage", "toString", "tachiyomi-zh.copymanga-v1.4.78_release"}, k = 1, mv = {1, 7, 1}, xi = 48)
    public static final class AuthorizationFailedException extends Exception {
        /* JADX WARN: 'super' call moved to the top of the method (can break code semantics) */
        public AuthorizationFailedException(String str) {
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
