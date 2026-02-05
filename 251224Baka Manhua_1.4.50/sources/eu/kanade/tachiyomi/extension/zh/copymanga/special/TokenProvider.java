package eu.kanade.tachiyomi.extension.zh.copymanga.special;

import android.app.Application;
import android.content.SharedPreferences;
import android.os.Handler;
import android.os.Looper;
import android.util.Base64;
import android.webkit.CookieManager;
import android.webkit.JavascriptInterface;
import android.webkit.WebResourceError;
import android.webkit.WebResourceRequest;
import android.webkit.WebResourceResponse;
import android.webkit.WebView;
import android.webkit.WebViewClient;
import androidx.preference.SwitchPreferenceCompat;
import eu.kanade.tachiyomi.extension.zh.copymanga.ApiDomainOption;
import eu.kanade.tachiyomi.extension.zh.copymanga.PlatFormOption;
import eu.kanade.tachiyomi.extension.zh.copymanga.PreferencesKeys;
import eu.kanade.tachiyomi.extension.zh.copymanga.PreferencesKt;
import eu.kanade.tachiyomi.extension.zh.copymanga.WebViewDomainOption;
import eu.kanade.tachiyomi.extension.zh.copymanga.api.ApiRepo;
import eu.kanade.tachiyomi.extension.zh.copymanga.api.ApiResponse;
import eu.kanade.tachiyomi.extension.zh.copymanga.api.ApiResponseKt;
import eu.kanade.tachiyomi.extension.zh.copymanga.api.dto.LoginResult;
import eu.kanade.tachiyomi.extension.zh.copymanga.special.TokenProvider;
import eu.kanade.tachiyomi.network.RequestsKt;
import java.io.Closeable;
import java.nio.charset.Charset;
import java.util.ArrayList;
import java.util.Arrays;
import java.util.Iterator;
import java.util.List;
import java.util.Map;
import java.util.concurrent.TimeUnit;
import kotlin.Metadata;
import kotlin.Result;
import kotlin.Unit;
import kotlin.collections.CollectionsKt;
import kotlin.concurrent.ThreadsKt;
import kotlin.coroutines.Continuation;
import kotlin.coroutines.intrinsics.IntrinsicsKt;
import kotlin.coroutines.jvm.internal.DebugProbesKt;
import kotlin.io.CloseableKt;
import kotlin.jvm.functions.Function0;
import kotlin.jvm.functions.Function1;
import kotlin.jvm.internal.DefaultConstructorMarker;
import kotlin.jvm.internal.Intrinsics;
import kotlin.jvm.internal.MagicApiIntrinsics;
import kotlin.jvm.internal.Ref;
import kotlin.jvm.internal.Reflection;
import kotlin.random.Random;
import kotlin.ranges.IntRange;
import kotlin.ranges.RangesKt;
import kotlin.reflect.KType;
import kotlin.reflect.KTypeProjection;
import kotlin.text.Charsets;
import kotlin.text.MatchResult;
import kotlin.text.Regex;
import kotlin.text.StringsKt;
import kotlinx.coroutines.CancellableContinuation;
import kotlinx.coroutines.CancellableContinuationImpl;
import kotlinx.serialization.SerializersKt;
import kotlinx.serialization.StringFormat;
import kotlinx.serialization.modules.SerializersModule;
import okhttp3.CacheControl;
import okhttp3.FormBody;
import okhttp3.Headers;
import okhttp3.OkHttpClient;
import okhttp3.Response;
import rx.Observable;
import rx.Single;
import rx.SingleSubscriber;
import rx.functions.Action0;
import rx.functions.Action1;
import uy.kohesive.injekt.InjektKt;
import uy.kohesive.injekt.api.FullTypeReference;

/* compiled from: TokenProvider.kt */
@Metadata(d1 = {"\u00008\n\u0002\u0018\u0002\n\u0002\u0010\u0000\n\u0002\b\u0002\n\u0002\u0018\u0002\n\u0002\b\u0005\n\u0002\u0018\u0002\n\u0002\u0018\u0002\n\u0002\u0010\u0002\n\u0000\n\u0002\u0018\u0002\n\u0002\b\u0006\n\u0002\u0018\u0002\n\u0000\n\u0002\u0018\u0002\n\u0002\b\u0004\bÆ\u0002\u0018\u00002\u00020\u0001:\u0003\u0018\u0019\u001aB\u0007\b\u0002¢\u0006\u0002\u0010\u0002J\u001e\u0010\u0013\u001a\u00020\f2\u0006\u0010\u0014\u001a\u00020\u00152\u000e\b\u0002\u0010\u0016\u001a\b\u0012\u0004\u0012\u00020\f0\u0017R\u001a\u0010\u0003\u001a\u00020\u0004X\u0086.¢\u0006\u000e\n\u0000\u001a\u0004\b\u0005\u0010\u0006\"\u0004\b\u0007\u0010\bR\u001a\u0010\t\u001a\u000e\u0012\u0004\u0012\u00020\u000b\u0012\u0004\u0012\u00020\f0\nX\u0082\u0004¢\u0006\u0002\n\u0000R\u001a\u0010\r\u001a\u00020\u000eX\u0086.¢\u0006\u000e\n\u0000\u001a\u0004\b\u000f\u0010\u0010\"\u0004\b\u0011\u0010\u0012¨\u0006\u001b"}, d2 = {"Leu/kanade/tachiyomi/extension/zh/copymanga/special/TokenProvider;", "", "()V", "client", "Lokhttp3/OkHttpClient;", "getClient", "()Lokhttp3/OkHttpClient;", "setClient", "(Lokhttp3/OkHttpClient;)V", "dispatch", "Lkotlin/Function1;", "Ljava/lang/Runnable;", "", "preferences", "Landroid/content/SharedPreferences;", "getPreferences", "()Landroid/content/SharedPreferences;", "setPreferences", "(Landroid/content/SharedPreferences;)V", "updateSummary", "enableLoginPreferences", "Landroidx/preference/SwitchPreferenceCompat;", "setToken", "Lkotlin/Function0;", "LoginStatus", "V1", "V2", "tachiyomi-zh.copymanga-v1.4.78_release"}, k = 1, mv = {1, 7, 1}, xi = 48)
/* loaded from: classes.dex */
public final class TokenProvider {
    public static final TokenProvider INSTANCE = new TokenProvider();
    public static OkHttpClient client;
    private static final Function1<Runnable, Unit> dispatch;
    public static SharedPreferences preferences;

    private TokenProvider() {
    }

    public final OkHttpClient getClient() {
        OkHttpClient okHttpClient = client;
        if (okHttpClient != null) {
            return okHttpClient;
        }
        Intrinsics.throwUninitializedPropertyAccessException("client");
        return null;
    }

    public final void setClient(OkHttpClient okHttpClient) {
        Intrinsics.checkNotNullParameter(okHttpClient, "<set-?>");
        client = okHttpClient;
    }

    public final SharedPreferences getPreferences() {
        SharedPreferences sharedPreferences = preferences;
        if (sharedPreferences != null) {
            return sharedPreferences;
        }
        Intrinsics.throwUninitializedPropertyAccessException("preferences");
        return null;
    }

    public final void setPreferences(SharedPreferences sharedPreferences) {
        Intrinsics.checkNotNullParameter(sharedPreferences, "<set-?>");
        preferences = sharedPreferences;
    }

    static {
        TokenProvider$dispatch$2 tokenProvider$dispatch$2;
        if (RuntimePlatform.INSTANCE.isTachiDesk()) {
            tokenProvider$dispatch$2 = new Function1<Runnable, Unit>() { // from class: eu.kanade.tachiyomi.extension.zh.copymanga.special.TokenProvider$dispatch$1
                public /* bridge */ /* synthetic */ Object invoke(Object obj) {
                    invoke((Runnable) obj);
                    return Unit.INSTANCE;
                }

                public final void invoke(Runnable runnable) {
                    Intrinsics.checkNotNullParameter(runnable, "runnable");
                    runnable.run();
                }
            };
        } else {
            tokenProvider$dispatch$2 = new Function1<Runnable, Unit>() { // from class: eu.kanade.tachiyomi.extension.zh.copymanga.special.TokenProvider$dispatch$2
                public /* bridge */ /* synthetic */ Object invoke(Object obj) {
                    invoke((Runnable) obj);
                    return Unit.INSTANCE;
                }

                public final void invoke(Runnable runnable) {
                    Intrinsics.checkNotNullParameter(runnable, "runnable");
                    new Handler(Looper.getMainLooper()).post(runnable);
                }
            };
        }
        dispatch = tokenProvider$dispatch$2;
    }

    /* compiled from: TokenProvider.kt */
    @Metadata(d1 = {"\u0000\u0012\n\u0002\u0018\u0002\n\u0002\u0010\u0010\n\u0000\n\u0002\u0010\u000e\n\u0002\b\u000b\b\u0086\u0001\u0018\u0000 \r2\b\u0012\u0004\u0012\u00020\u00000\u0001:\u0001\rB\u0017\b\u0002\u0012\u0006\u0010\u0002\u001a\u00020\u0003\u0012\u0006\u0010\u0004\u001a\u00020\u0003¢\u0006\u0002\u0010\u0005R\u0011\u0010\u0004\u001a\u00020\u0003¢\u0006\b\n\u0000\u001a\u0004\b\u0006\u0010\u0007R\u0011\u0010\u0002\u001a\u00020\u0003¢\u0006\b\n\u0000\u001a\u0004\b\b\u0010\u0007j\u0002\b\tj\u0002\b\nj\u0002\b\u000bj\u0002\b\f¨\u0006\u000e"}, d2 = {"Leu/kanade/tachiyomi/extension/zh/copymanga/special/TokenProvider$LoginStatus;", "", "message", "", "key", "(Ljava/lang/String;ILjava/lang/String;Ljava/lang/String;)V", "getKey", "()Ljava/lang/String;", "getMessage", "NOT_LOGGED_IN", "LOGGED_IN", "LOGIN_FAILED", "LOGIN_EXPIRED", "Companion", "tachiyomi-zh.copymanga-v1.4.78_release"}, k = 1, mv = {1, 7, 1}, xi = 48)
    public enum LoginStatus {
        NOT_LOGGED_IN("未登入", ""),
        LOGGED_IN("已登入", "logged_in:"),
        LOGIN_FAILED("登入失敗", "error:"),
        LOGIN_EXPIRED("登入已過期，请重新登入", "expired:");


        /* renamed from: Companion, reason: from kotlin metadata */
        public static final Companion INSTANCE = new Companion(null);
        private final String key;
        private final String message;

        LoginStatus(String str, String str2) {
            this.message = str;
            this.key = str2;
        }

        public final String getKey() {
            return this.key;
        }

        public final String getMessage() {
            return this.message;
        }

        /* compiled from: TokenProvider.kt */
        @Metadata(d1 = {"\u0000\"\n\u0002\u0018\u0002\n\u0002\u0010\u0000\n\u0002\b\u0002\n\u0002\u0010\u000b\n\u0000\n\u0002\u0010\u000e\n\u0002\b\u0003\n\u0002\u0010\b\n\u0002\b\u0002\b\u0086\u0003\u0018\u00002\u00020\u0001B\u0007\b\u0002¢\u0006\u0002\u0010\u0002J\u000e\u0010\u0003\u001a\u00020\u00042\u0006\u0010\u0005\u001a\u00020\u0006J\u000e\u0010\u0007\u001a\u00020\u00062\u0006\u0010\u0005\u001a\u00020\u0006J\u001c\u0010\b\u001a\u00020\u0006*\u00020\u00062\u0006\u0010\t\u001a\u00020\n2\u0006\u0010\u000b\u001a\u00020\nH\u0002¨\u0006\f"}, d2 = {"Leu/kanade/tachiyomi/extension/zh/copymanga/special/TokenProvider$LoginStatus$Companion;", "", "()V", "isValidToken", "", "token", "", "token2StatusMessage", "maskMiddle", "visibleStart", "", "visibleEnd", "tachiyomi-zh.copymanga-v1.4.78_release"}, k = 1, mv = {1, 7, 1}, xi = 48)
        public static final class Companion {
            public /* synthetic */ Companion(DefaultConstructorMarker defaultConstructorMarker) {
                this();
            }

            private Companion() {
            }

            public final String token2StatusMessage(String token) {
                Intrinsics.checkNotNullParameter(token, "token");
                if (StringsKt.startsWith$default(token, LoginStatus.LOGIN_FAILED.getKey(), false, 2, (Object) null)) {
                    return LoginStatus.LOGIN_FAILED.getMessage() + " (" + ((String) StringsKt.split$default(token, new String[]{":"}, false, 2, 2, (Object) null).get(1)) + ')';
                }
                if (token.length() == 0) {
                    return LoginStatus.NOT_LOGGED_IN.getMessage();
                }
                if (StringsKt.startsWith$default(token, LoginStatus.LOGIN_EXPIRED.getKey(), false, 2, (Object) null)) {
                    return LoginStatus.LOGIN_EXPIRED.getMessage();
                }
                return LoginStatus.LOGGED_IN.getMessage() + '(' + LoginStatus.INSTANCE.maskMiddle(token, 4, 4) + ')';
            }

            public final boolean isValidToken(String token) {
                Intrinsics.checkNotNullParameter(token, "token");
                return (token.length() <= 0 || StringsKt.startsWith$default(token, LoginStatus.LOGIN_FAILED.getKey(), false, 2, (Object) null) || StringsKt.startsWith$default(token, LoginStatus.LOGIN_EXPIRED.getKey(), false, 2, (Object) null)) ? false : true;
            }

            private final String maskMiddle(String str, int i, int i2) {
                if (i + i2 >= str.length()) {
                    return str;
                }
                return StringsKt.take(str, i) + StringsKt.repeat("*", (str.length() - i) - i2) + StringsKt.takeLast(str, i2);
            }
        }
    }

    /* JADX WARN: Multi-variable type inference failed */
    public static /* synthetic */ void updateSummary$default(TokenProvider tokenProvider, SwitchPreferenceCompat switchPreferenceCompat, Function0 function0, int i, Object obj) {
        if ((i & 2) != 0) {
            function0 = new Function0<Unit>() { // from class: eu.kanade.tachiyomi.extension.zh.copymanga.special.TokenProvider.updateSummary.1
                /* renamed from: invoke, reason: collision with other method in class */
                public final void m61invoke() {
                }

                public /* bridge */ /* synthetic */ Object invoke() {
                    m61invoke();
                    return Unit.INSTANCE;
                }
            };
        }
        tokenProvider.updateSummary(switchPreferenceCompat, function0);
    }

    public final void updateSummary(final SwitchPreferenceCompat enableLoginPreferences, final Function0<Unit> setToken) {
        Intrinsics.checkNotNullParameter(enableLoginPreferences, "enableLoginPreferences");
        Intrinsics.checkNotNullParameter(setToken, "setToken");
        dispatch.invoke(new Runnable() { // from class: eu.kanade.tachiyomi.extension.zh.copymanga.special.TokenProvider$$ExternalSyntheticLambda0
            @Override // java.lang.Runnable
            public final void run() {
                TokenProvider.updateSummary$lambda$0(setToken, enableLoginPreferences);
            }
        });
    }

    /* JADX INFO: Access modifiers changed from: private */
    public static final void updateSummary$lambda$0(Function0 function0, SwitchPreferenceCompat switchPreferenceCompat) {
        Intrinsics.checkNotNullParameter(function0, "$setToken");
        Intrinsics.checkNotNullParameter(switchPreferenceCompat, "$enableLoginPreferences");
        function0.invoke();
        LoginStatus.Companion companion = LoginStatus.INSTANCE;
        TokenProvider tokenProvider = INSTANCE;
        String str = String.format(PreferencesKeys.ENABLE_LOGIN_SUMMERY, Arrays.copyOf(new Object[]{companion.token2StatusMessage(PreferencesKt.getCopyMangaToken(tokenProvider.getPreferences())), LoginStatus.INSTANCE.token2StatusMessage(PreferencesKt.getHotMangaToken(tokenProvider.getPreferences()))}, 2));
        Intrinsics.checkNotNullExpressionValue(str, "format(this, *args)");
        switchPreferenceCompat.setSummary(str);
    }

    /* compiled from: TokenProvider.kt */
    @Metadata(d1 = {"\u00000\n\u0002\u0018\u0002\n\u0002\u0010\u0000\n\u0002\b\u0002\n\u0002\u0010\u000e\n\u0002\b\u0004\n\u0002\u0010\u000b\n\u0000\n\u0002\u0010\u0002\n\u0002\b\u0002\n\u0002\u0018\u0002\n\u0000\n\u0002\u0018\u0002\n\u0002\b\u0003\bÀ\u0002\u0018\u00002\u00020\u0001:\u0001\u0012B\u0007\b\u0002¢\u0006\u0002\u0010\u0002J.\u0010\u0003\u001a\u0004\u0018\u00010\u00042\b\u0010\u0005\u001a\u0004\u0018\u00010\u00042\b\u0010\u0006\u001a\u0004\u0018\u00010\u00042\u0006\u0010\u0007\u001a\u00020\u00042\u0006\u0010\b\u001a\u00020\tH\u0002J\u0016\u0010\n\u001a\u00020\u000b2\u0006\u0010\f\u001a\u00020\u00042\u0006\u0010\r\u001a\u00020\u000eJ\u0010\u0010\u000f\u001a\u00020\u00102\u0006\u0010\u0011\u001a\u00020\u0004H\u0002¨\u0006\u0013"}, d2 = {"Leu/kanade/tachiyomi/extension/zh/copymanga/special/TokenProvider$V1;", "", "()V", "getToken", "", "userName", "password", "domain", "clear", "", "login", "", "newCredit", "enableLoginPreferences", "Landroidx/preference/SwitchPreferenceCompat;", "parseLoginCredit", "Leu/kanade/tachiyomi/extension/zh/copymanga/special/TokenProvider$V1$LoginCredit;", "credential", "LoginCredit", "tachiyomi-zh.copymanga-v1.4.78_release"}, k = 1, mv = {1, 7, 1}, xi = 48)
    public static final class V1 {
        public static final V1 INSTANCE = new V1();

        /* compiled from: TokenProvider.kt */
        @Metadata(d1 = {"\u0000\"\n\u0002\u0018\u0002\n\u0002\u0010\u0000\n\u0000\n\u0002\u0010\u000e\n\u0002\b\u0014\n\u0002\u0010\u000b\n\u0002\b\u0002\n\u0002\u0010\b\n\u0002\b\u0002\b\u0086\b\u0018\u00002\u00020\u0001B%\u0012\u0006\u0010\u0002\u001a\u00020\u0003\u0012\u0006\u0010\u0004\u001a\u00020\u0003\u0012\u0006\u0010\u0005\u001a\u00020\u0003\u0012\u0006\u0010\u0006\u001a\u00020\u0003¢\u0006\u0002\u0010\u0007J\t\u0010\u0012\u001a\u00020\u0003HÆ\u0003J\t\u0010\u0013\u001a\u00020\u0003HÆ\u0003J\t\u0010\u0014\u001a\u00020\u0003HÆ\u0003J\t\u0010\u0015\u001a\u00020\u0003HÆ\u0003J1\u0010\u0016\u001a\u00020\u00002\b\b\u0002\u0010\u0002\u001a\u00020\u00032\b\b\u0002\u0010\u0004\u001a\u00020\u00032\b\b\u0002\u0010\u0005\u001a\u00020\u00032\b\b\u0002\u0010\u0006\u001a\u00020\u0003HÆ\u0001J\u0013\u0010\u0017\u001a\u00020\u00182\b\u0010\u0019\u001a\u0004\u0018\u00010\u0001HÖ\u0003J\t\u0010\u001a\u001a\u00020\u001bHÖ\u0001J\t\u0010\u001c\u001a\u00020\u0003HÖ\u0001R\u001a\u0010\u0002\u001a\u00020\u0003X\u0086\u000e¢\u0006\u000e\n\u0000\u001a\u0004\b\b\u0010\t\"\u0004\b\n\u0010\u000bR\u001a\u0010\u0004\u001a\u00020\u0003X\u0086\u000e¢\u0006\u000e\n\u0000\u001a\u0004\b\f\u0010\t\"\u0004\b\r\u0010\u000bR\u001a\u0010\u0005\u001a\u00020\u0003X\u0086\u000e¢\u0006\u000e\n\u0000\u001a\u0004\b\u000e\u0010\t\"\u0004\b\u000f\u0010\u000bR\u001a\u0010\u0006\u001a\u00020\u0003X\u0086\u000e¢\u0006\u000e\n\u0000\u001a\u0004\b\u0010\u0010\t\"\u0004\b\u0011\u0010\u000b¨\u0006\u001d"}, d2 = {"Leu/kanade/tachiyomi/extension/zh/copymanga/special/TokenProvider$V1$LoginCredit;", "", "copyName", "", "copyPassword", "hotName", "hotPassword", "(Ljava/lang/String;Ljava/lang/String;Ljava/lang/String;Ljava/lang/String;)V", "getCopyName", "()Ljava/lang/String;", "setCopyName", "(Ljava/lang/String;)V", "getCopyPassword", "setCopyPassword", "getHotName", "setHotName", "getHotPassword", "setHotPassword", "component1", "component2", "component3", "component4", "copy", "equals", "", "other", "hashCode", "", "toString", "tachiyomi-zh.copymanga-v1.4.78_release"}, k = 1, mv = {1, 7, 1}, xi = 48)
        public static final /* data */ class LoginCredit {
            private String copyName;
            private String copyPassword;
            private String hotName;
            private String hotPassword;

            public static /* synthetic */ LoginCredit copy$default(LoginCredit loginCredit, String str, String str2, String str3, String str4, int i, Object obj) {
                if ((i & 1) != 0) {
                    str = loginCredit.copyName;
                }
                if ((i & 2) != 0) {
                    str2 = loginCredit.copyPassword;
                }
                if ((i & 4) != 0) {
                    str3 = loginCredit.hotName;
                }
                if ((i & 8) != 0) {
                    str4 = loginCredit.hotPassword;
                }
                return loginCredit.copy(str, str2, str3, str4);
            }

            /* renamed from: component1, reason: from getter */
            public final String getCopyName() {
                return this.copyName;
            }

            /* renamed from: component2, reason: from getter */
            public final String getCopyPassword() {
                return this.copyPassword;
            }

            /* renamed from: component3, reason: from getter */
            public final String getHotName() {
                return this.hotName;
            }

            /* renamed from: component4, reason: from getter */
            public final String getHotPassword() {
                return this.hotPassword;
            }

            public final LoginCredit copy(String copyName, String copyPassword, String hotName, String hotPassword) {
                Intrinsics.checkNotNullParameter(copyName, "copyName");
                Intrinsics.checkNotNullParameter(copyPassword, "copyPassword");
                Intrinsics.checkNotNullParameter(hotName, "hotName");
                Intrinsics.checkNotNullParameter(hotPassword, "hotPassword");
                return new LoginCredit(copyName, copyPassword, hotName, hotPassword);
            }

            public boolean equals(Object other) {
                if (this == other) {
                    return true;
                }
                if (!(other instanceof LoginCredit)) {
                    return false;
                }
                LoginCredit loginCredit = (LoginCredit) other;
                return Intrinsics.areEqual(this.copyName, loginCredit.copyName) && Intrinsics.areEqual(this.copyPassword, loginCredit.copyPassword) && Intrinsics.areEqual(this.hotName, loginCredit.hotName) && Intrinsics.areEqual(this.hotPassword, loginCredit.hotPassword);
            }

            public int hashCode() {
                return (((((this.copyName.hashCode() * 31) + this.copyPassword.hashCode()) * 31) + this.hotName.hashCode()) * 31) + this.hotPassword.hashCode();
            }

            public String toString() {
                return "LoginCredit(copyName=" + this.copyName + ", copyPassword=" + this.copyPassword + ", hotName=" + this.hotName + ", hotPassword=" + this.hotPassword + ')';
            }

            public LoginCredit(String str, String str2, String str3, String str4) {
                Intrinsics.checkNotNullParameter(str, "copyName");
                Intrinsics.checkNotNullParameter(str2, "copyPassword");
                Intrinsics.checkNotNullParameter(str3, "hotName");
                Intrinsics.checkNotNullParameter(str4, "hotPassword");
                this.copyName = str;
                this.copyPassword = str2;
                this.hotName = str3;
                this.hotPassword = str4;
            }

            public final String getCopyName() {
                return this.copyName;
            }

            public final void setCopyName(String str) {
                Intrinsics.checkNotNullParameter(str, "<set-?>");
                this.copyName = str;
            }

            public final String getCopyPassword() {
                return this.copyPassword;
            }

            public final void setCopyPassword(String str) {
                Intrinsics.checkNotNullParameter(str, "<set-?>");
                this.copyPassword = str;
            }

            public final String getHotName() {
                return this.hotName;
            }

            public final void setHotName(String str) {
                Intrinsics.checkNotNullParameter(str, "<set-?>");
                this.hotName = str;
            }

            public final String getHotPassword() {
                return this.hotPassword;
            }

            public final void setHotPassword(String str) {
                Intrinsics.checkNotNullParameter(str, "<set-?>");
                this.hotPassword = str;
            }
        }

        private V1() {
        }

        public final void login(String newCredit, final SwitchPreferenceCompat enableLoginPreferences) {
            Intrinsics.checkNotNullParameter(newCredit, "newCredit");
            Intrinsics.checkNotNullParameter(enableLoginPreferences, "enableLoginPreferences");
            final LoginCredit loginCredit = parseLoginCredit(newCredit);
            final boolean zAreEqual = Intrinsics.areEqual(newCredit, "clear");
            ThreadsKt.thread$default(false, false, (ClassLoader) null, (String) null, 0, new Function0<Unit>() { // from class: eu.kanade.tachiyomi.extension.zh.copymanga.special.TokenProvider$V1$login$1
                /* JADX WARN: 'super' call moved to the top of the method (can break code semantics) */
                {
                    super(0);
                }

                public /* bridge */ /* synthetic */ Object invoke() {
                    m54invoke();
                    return Unit.INSTANCE;
                }

                /* renamed from: invoke, reason: collision with other method in class */
                public final void m54invoke() {
                    final String token = TokenProvider.V1.INSTANCE.getToken(loginCredit.getCopyName(), loginCredit.getCopyPassword(), ApiDomainOption.COPY4.getEntryKey(), zAreEqual);
                    if (token != null) {
                        TokenProvider.INSTANCE.updateSummary(enableLoginPreferences, new Function0<Unit>() { // from class: eu.kanade.tachiyomi.extension.zh.copymanga.special.TokenProvider$V1$login$1.1
                            /* JADX WARN: 'super' call moved to the top of the method (can break code semantics) */
                            {
                                super(0);
                            }

                            public /* bridge */ /* synthetic */ Object invoke() {
                                m55invoke();
                                return Unit.INSTANCE;
                            }

                            /* renamed from: invoke, reason: collision with other method in class */
                            public final void m55invoke() {
                                PreferencesKt.setCopyMangaToken(TokenProvider.INSTANCE.getPreferences(), token);
                            }
                        });
                    }
                }
            }, 31, (Object) null);
            ThreadsKt.thread$default(false, false, (ClassLoader) null, (String) null, 0, new Function0<Unit>() { // from class: eu.kanade.tachiyomi.extension.zh.copymanga.special.TokenProvider$V1$login$2
                /* JADX WARN: 'super' call moved to the top of the method (can break code semantics) */
                {
                    super(0);
                }

                public /* bridge */ /* synthetic */ Object invoke() {
                    m56invoke();
                    return Unit.INSTANCE;
                }

                /* renamed from: invoke, reason: collision with other method in class */
                public final void m56invoke() {
                    final String token = TokenProvider.V1.INSTANCE.getToken(loginCredit.getHotName(), loginCredit.getHotPassword(), ApiDomainOption.HOTMANGA2.getEntryKey(), zAreEqual);
                    if (token != null) {
                        TokenProvider.INSTANCE.updateSummary(enableLoginPreferences, new Function0<Unit>() { // from class: eu.kanade.tachiyomi.extension.zh.copymanga.special.TokenProvider$V1$login$2.1
                            /* JADX WARN: 'super' call moved to the top of the method (can break code semantics) */
                            {
                                super(0);
                            }

                            public /* bridge */ /* synthetic */ Object invoke() {
                                m57invoke();
                                return Unit.INSTANCE;
                            }

                            /* renamed from: invoke, reason: collision with other method in class */
                            public final void m57invoke() {
                                PreferencesKt.setHotMangaToken(TokenProvider.INSTANCE.getPreferences(), token);
                            }
                        });
                    }
                }
            }, 31, (Object) null);
        }

        /* JADX INFO: Access modifiers changed from: private */
        public final String getToken(String userName, String password, String domain, boolean clear) {
            String str;
            Headers copy_manga_header;
            String token;
            if (clear) {
                return "";
            }
            String str2 = userName;
            if (str2 == null || StringsKt.isBlank(str2) || (str = password) == null || StringsKt.isBlank(str)) {
                return null;
            }
            try {
                String strValueOf = String.valueOf(RangesKt.random(new IntRange(1000, 9999), Random.Default));
                String str3 = ApiDomainOption.INSTANCE.isHotManga(domain) ? "Offical" : "freeSite";
                String str4 = ApiDomainOption.INSTANCE.isHotManga(domain) ? "2025.02.12" : "2025.05.09";
                String str5 = "https://" + domain + "/api/v3/login";
                V1 v1 = this;
                if (ApiDomainOption.INSTANCE.isHotManga(domain)) {
                    copy_manga_header = ApiRepo.INSTANCE.getHOT_MANGA_HEADER();
                } else {
                    copy_manga_header = ApiRepo.INSTANCE.getCOPY_MANGA_HEADER();
                }
                FormBody.Builder builderAdd = new FormBody.Builder((Charset) null, 1, (DefaultConstructorMarker) null).add("username", userName);
                byte[] bytes = (password + '-' + strValueOf).getBytes(Charsets.UTF_8);
                Intrinsics.checkNotNullExpressionValue(bytes, "this as java.lang.String).getBytes(charset)");
                String strEncodeToString = Base64.encodeToString(bytes, 0);
                Intrinsics.checkNotNullExpressionValue(strEncodeToString, "encodeToString(\"$passwor…s.UTF_8), Base64.DEFAULT)");
                Response response = (Closeable) TokenProvider.INSTANCE.getClient().newCall(RequestsKt.POST$default(str5, copy_manga_header, builderAdd.add("password", strEncodeToString).add("salt", strValueOf).add("source", str3).add("version", str4).add("platform", PlatFormOption.INSTANCE.key2value(PreferencesKt.getPlatFormOptionKey(TokenProvider.INSTANCE.getPreferences()))).build(), (CacheControl) null, 8, (Object) null).newBuilder().build()).execute();
                try {
                    Response response2 = response;
                    if (!response2.isSuccessful()) {
                        token = LoginStatus.LOGIN_FAILED.getKey() + ApiResponseKt.peek(response2);
                    } else {
                        try {
                            if (response2.isSuccessful()) {
                                StringFormat json = ApiResponseKt.getJson();
                                String strString = response2.body().string();
                                SerializersModule serializersModule = json.getSerializersModule();
                                KType kTypeTypeOf = Reflection.typeOf(ApiResponse.class, KTypeProjection.Companion.invariant(Reflection.typeOf(LoginResult.class)));
                                MagicApiIntrinsics.voidMagicApiCall("kotlinx.serialization.serializer.withModule");
                                token = ((LoginResult) ((ApiResponse) json.decodeFromString(SerializersKt.serializer(serializersModule, kTypeTypeOf), strString)).getResults()).getToken();
                            } else {
                                throw new Exception("Error: " + response2.code() + " - " + response2.message());
                            }
                        } catch (Exception e) {
                            throw new Exception("解析失敗，請嘗試更換域名或參數，並在Github Issue聯繫開發者\n" + e.getMessage(), e);
                        }
                    }
                    CloseableKt.closeFinally(response, (Throwable) null);
                    return token;
                } finally {
                }
            } catch (Exception e2) {
                return LoginStatus.LOGIN_FAILED.getKey() + e2.getMessage();
            }
        }

        private final LoginCredit parseLoginCredit(String credential) {
            LoginCredit loginCredit = new LoginCredit("", "", "", "");
            Iterator it = Regex.findAll$default(new Regex("(copy|hot):(\\S+)\\s+(\\S+)"), credential, 0, 2, (Object) null).iterator();
            while (it.hasNext()) {
                MatchResult.Destructured destructured = ((MatchResult) it.next()).getDestructured();
                String str = (String) destructured.getMatch().getGroupValues().get(1);
                String str2 = (String) destructured.getMatch().getGroupValues().get(2);
                String str3 = (String) destructured.getMatch().getGroupValues().get(3);
                if (Intrinsics.areEqual(str, "copy")) {
                    loginCredit.setCopyName(str2);
                    loginCredit.setCopyPassword(str3);
                } else if (Intrinsics.areEqual(str, "hot")) {
                    loginCredit.setHotName(str2);
                    loginCredit.setHotPassword(str3);
                }
            }
            return loginCredit;
        }
    }

    /* compiled from: TokenProvider.kt */
    @Metadata(d1 = {"\u0000*\n\u0002\u0018\u0002\n\u0002\u0010\u0000\n\u0002\b\u0002\n\u0002\u0018\u0002\n\u0002\u0010\u000e\n\u0002\b\u0005\n\u0002\u0010\u0002\n\u0000\n\u0002\u0018\u0002\n\u0000\n\u0002\u0018\u0002\n\u0000\bÀ\u0002\u0018\u00002\u00020\u0001B\u0007\b\u0002¢\u0006\u0002\u0010\u0002J \u0010\u0003\u001a\b\u0012\u0004\u0012\u00020\u00050\u00042\u0006\u0010\u0006\u001a\u00020\u00052\b\b\u0002\u0010\u0007\u001a\u00020\u0005H\u0007J#\u0010\b\u001a\u00020\u00052\u0006\u0010\u0006\u001a\u00020\u00052\b\b\u0002\u0010\u0007\u001a\u00020\u0005H\u0087@ø\u0001\u0000¢\u0006\u0002\u0010\tJ\u000e\u0010\n\u001a\u00020\u000b2\u0006\u0010\f\u001a\u00020\rJ\f\u0010\u000e\u001a\u00020\u000b*\u00020\u000fH\u0002\u0082\u0002\u0004\n\u0002\b\u0019¨\u0006\u0010"}, d2 = {"Leu/kanade/tachiyomi/extension/zh/copymanga/special/TokenProvider$V2;", "", "()V", "getToken", "Lrx/Observable;", "", "url", "cookieName", "getTokenIOS", "(Ljava/lang/String;Ljava/lang/String;Lkotlin/coroutines/Continuation;)Ljava/lang/Object;", "login", "", "enableLoginPreferences", "Landroidx/preference/SwitchPreferenceCompat;", "destroyAll", "Landroid/webkit/WebView;", "tachiyomi-zh.copymanga-v1.4.78_release"}, k = 1, mv = {1, 7, 1}, xi = 48)
    public static final class V2 {
        public static final V2 INSTANCE = new V2();

        private V2() {
        }

        public final void login(SwitchPreferenceCompat enableLoginPreferences) {
            Intrinsics.checkNotNullParameter(enableLoginPreferences, "enableLoginPreferences");
            if (RuntimePlatform.INSTANCE.isTachiDesk()) {
                return;
            }
            ThreadsKt.thread$default(false, false, (ClassLoader) null, (String) null, 0, new TokenProvider$V2$login$1(PreferencesKt.getHttpWebViewDomain(TokenProvider.INSTANCE.getPreferences()) + "/h5", enableLoginPreferences), 31, (Object) null);
        }

        /* JADX INFO: Access modifiers changed from: private */
        public static final void login$setToken(String str, String str2) {
            if (str2.length() == 0) {
                return;
            }
            if (WebViewDomainOption.INSTANCE.isHotManga(str)) {
                PreferencesKt.setHotMangaToken(TokenProvider.INSTANCE.getPreferences(), str2);
            } else {
                PreferencesKt.setCopyMangaToken(TokenProvider.INSTANCE.getPreferences(), str2);
            }
        }

        public static /* synthetic */ Object getTokenIOS$default(V2 v2, String str, String str2, Continuation continuation, int i, Object obj) {
            if ((i & 2) != 0) {
                str2 = "token";
            }
            return v2.getTokenIOS(str, str2, continuation);
        }

        public static /* synthetic */ Observable getToken$default(V2 v2, String str, String str2, int i, Object obj) {
            if ((i & 2) != 0) {
                str2 = "token";
            }
            return v2.getToken(str, str2);
        }

        public final Observable<String> getToken(final String url, final String cookieName) {
            Intrinsics.checkNotNullParameter(url, "url");
            Intrinsics.checkNotNullParameter(cookieName, "cookieName");
            final Ref.ObjectRef objectRef = new Ref.ObjectRef();
            Observable<String> observable = Single.create(new Single.OnSubscribe() { // from class: eu.kanade.tachiyomi.extension.zh.copymanga.special.TokenProvider$V2$$ExternalSyntheticLambda1
                public final void call(Object obj) {
                    TokenProvider.V2.getToken$lambda$3(objectRef, url, cookieName, (SingleSubscriber) obj);
                }
            }).timeout(15L, TimeUnit.SECONDS).doOnError(new Action1() { // from class: eu.kanade.tachiyomi.extension.zh.copymanga.special.TokenProvider$V2$$ExternalSyntheticLambda2
                public final void call(Object obj) {
                    TokenProvider.V2.getToken$lambda$4(objectRef, (Throwable) obj);
                }
            }).doAfterTerminate(new Action0() { // from class: eu.kanade.tachiyomi.extension.zh.copymanga.special.TokenProvider$V2$$ExternalSyntheticLambda3
                public final void call() {
                    TokenProvider.V2.getToken$lambda$5(objectRef);
                }
            }).toObservable();
            Intrinsics.checkNotNullExpressionValue(observable, "create { emitter ->\n    …          .toObservable()");
            return observable;
        }

        /* JADX INFO: Access modifiers changed from: private */
        public static final void getToken$lambda$3(final Ref.ObjectRef objectRef, final String str, final String str2, final SingleSubscriber singleSubscriber) {
            Intrinsics.checkNotNullParameter(objectRef, "$webView");
            Intrinsics.checkNotNullParameter(str, "$url");
            Intrinsics.checkNotNullParameter(str2, "$cookieName");
            new Handler(Looper.getMainLooper()).post(new Runnable() { // from class: eu.kanade.tachiyomi.extension.zh.copymanga.special.TokenProvider$V2$$ExternalSyntheticLambda0
                @Override // java.lang.Runnable
                public final void run() {
                    TokenProvider.V2.getToken$lambda$3$lambda$2(objectRef, str, singleSubscriber, str2);
                }
            });
        }

        /* JADX INFO: Access modifiers changed from: private */
        public static final void getToken$lambda$3$lambda$2(Ref.ObjectRef objectRef, final String str, final SingleSubscriber singleSubscriber, final String str2) {
            WebView webView;
            Intrinsics.checkNotNullParameter(objectRef, "$webView");
            Intrinsics.checkNotNullParameter(str, "$url");
            Intrinsics.checkNotNullParameter(str2, "$cookieName");
            final WebView webView2 = new WebView((Application) InjektKt.getInjekt().getInstance(new FullTypeReference<Application>() { // from class: eu.kanade.tachiyomi.extension.zh.copymanga.special.TokenProvider$V2$getToken$lambda$3$lambda$2$$inlined$get$1
            }.getType()));
            webView2.getSettings().setJavaScriptEnabled(true);
            webView2.getSettings().setDomStorageEnabled(true);
            webView2.getSettings().setDatabaseEnabled(true);
            CookieManager.getInstance().setAcceptCookie(true);
            CookieManager.getInstance().setAcceptThirdPartyCookies(webView2, true);
            webView2.addJavascriptInterface(new Object() { // from class: eu.kanade.tachiyomi.extension.zh.copymanga.special.TokenProvider$V2$getToken$1$1$1$1
                @JavascriptInterface
                public final void sendToken(String token) {
                    Intrinsics.checkNotNullParameter(token, "token");
                    singleSubscriber.onSuccess(token);
                    TokenProvider.V2.INSTANCE.destroyAll(webView2);
                }
            }, "Native");
            webView2.setWebViewClient(new WebViewClient() { // from class: eu.kanade.tachiyomi.extension.zh.copymanga.special.TokenProvider$V2$getToken$1$1$1$2
                @Override // android.webkit.WebViewClient
                public void onReceivedError(WebView view, WebResourceRequest request, WebResourceError error) {
                    Intrinsics.checkNotNullParameter(view, "view");
                    Intrinsics.checkNotNullParameter(request, "request");
                    Intrinsics.checkNotNullParameter(error, "error");
                    singleSubscriber.onError(new RuntimeException("WebView load error: " + ((Object) error.getDescription())));
                    TokenProvider.V2.INSTANCE.destroyAll(view);
                }

                @Override // android.webkit.WebViewClient
                public WebResourceResponse shouldInterceptRequest(WebView view, WebResourceRequest request) {
                    Intrinsics.checkNotNullParameter(view, "view");
                    Intrinsics.checkNotNullParameter(request, "request");
                    String string = request.getUrl().toString();
                    Intrinsics.checkNotNullExpressionValue(string, "request.url.toString()");
                    if (StringsKt.endsWith$default(string, "/system/config/2020/1", false, 2, (Object) null)) {
                        Headers.Companion companion = Headers.Companion;
                        Map<String, String> requestHeaders = request.getRequestHeaders();
                        Intrinsics.checkNotNullExpressionValue(requestHeaders, "request.requestHeaders");
                        String str3 = companion.of(requestHeaders).get("Authorization");
                        if (str3 != null) {
                            SingleSubscriber<? super String> singleSubscriber2 = singleSubscriber;
                            WebView webView3 = webView2;
                            if (StringsKt.startsWith$default(str3, "Token ", false, 2, (Object) null)) {
                                singleSubscriber2.onSuccess(StringsKt.trim(StringsKt.removePrefix(str3, "Token ")).toString());
                                TokenProvider.V2.INSTANCE.destroyAll(webView3);
                            }
                        }
                    }
                    return super.shouldInterceptRequest(view, request);
                }

                @Override // android.webkit.WebViewClient
                public void onPageFinished(WebView view, String finishedUrl) {
                    List listSplit$default;
                    Object next;
                    Intrinsics.checkNotNullParameter(view, "view");
                    Intrinsics.checkNotNullParameter(finishedUrl, "finishedUrl");
                    String cookie = CookieManager.getInstance().getCookie(str);
                    String strSubstringAfter$default = null;
                    if (cookie != null && (listSplit$default = StringsKt.split$default(cookie, new String[]{";"}, false, 0, 6, (Object) null)) != null) {
                        List list = listSplit$default;
                        ArrayList arrayList = new ArrayList(CollectionsKt.collectionSizeOrDefault(list, 10));
                        Iterator it = list.iterator();
                        while (it.hasNext()) {
                            arrayList.add(StringsKt.trim((String) it.next()).toString());
                        }
                        String str3 = str2;
                        Iterator it2 = arrayList.iterator();
                        while (true) {
                            if (!it2.hasNext()) {
                                next = null;
                                break;
                            }
                            next = it2.next();
                            if (StringsKt.startsWith$default((String) next, str3 + '=', false, 2, (Object) null)) {
                                break;
                            }
                        }
                        String str4 = (String) next;
                        if (str4 != null) {
                            strSubstringAfter$default = StringsKt.substringAfter$default(str4, str2 + '=', (String) null, 2, (Object) null);
                        }
                    }
                    if (strSubstringAfter$default != null) {
                        SingleSubscriber<? super String> singleSubscriber2 = singleSubscriber;
                        WebView webView3 = webView2;
                        singleSubscriber2.onSuccess(strSubstringAfter$default);
                        TokenProvider.V2.INSTANCE.destroyAll(webView3);
                    }
                }
            });
            objectRef.element = webView2;
            if (objectRef.element == null) {
                Intrinsics.throwUninitializedPropertyAccessException("webView");
                webView = null;
            } else {
                webView = (WebView) objectRef.element;
            }
            webView.loadUrl(str);
        }

        /* JADX INFO: Access modifiers changed from: private */
        public static final void getToken$lambda$4(Ref.ObjectRef objectRef, Throwable th) {
            WebView webView;
            Intrinsics.checkNotNullParameter(objectRef, "$webView");
            if (objectRef.element == null) {
                Intrinsics.throwUninitializedPropertyAccessException("webView");
                webView = null;
            } else {
                webView = (WebView) objectRef.element;
            }
            webView.destroy();
        }

        /* JADX INFO: Access modifiers changed from: private */
        public static final void getToken$lambda$5(Ref.ObjectRef objectRef) {
            WebView webView;
            Intrinsics.checkNotNullParameter(objectRef, "$webView");
            if (objectRef.element == null) {
                Intrinsics.throwUninitializedPropertyAccessException("webView");
                webView = null;
            } else {
                webView = (WebView) objectRef.element;
            }
            webView.destroy();
        }

        /* JADX INFO: Access modifiers changed from: private */
        public final void destroyAll(WebView webView) {
            try {
                webView.stopLoading();
                webView.removeAllViews();
                webView.destroy();
            } catch (Exception unused) {
            }
        }

        public final Object getTokenIOS(String str, String str2, Continuation<? super String> continuation) {
            Continuation cancellableContinuationImpl = new CancellableContinuationImpl(IntrinsicsKt.intercepted(continuation), 1);
            cancellableContinuationImpl.initCancellability();
            Result.Companion companion = Result.Companion;
            ((CancellableContinuation) cancellableContinuationImpl).resumeWith(Result.constructor-impl(""));
            Object result = cancellableContinuationImpl.getResult();
            if (result == IntrinsicsKt.getCOROUTINE_SUSPENDED()) {
                DebugProbesKt.probeCoroutineSuspended(continuation);
            }
            return result;
        }
    }
}
