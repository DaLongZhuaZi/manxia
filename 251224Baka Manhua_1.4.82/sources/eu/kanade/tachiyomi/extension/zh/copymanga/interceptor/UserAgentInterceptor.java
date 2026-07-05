package eu.kanade.tachiyomi.extension.zh.copymanga.interceptor;

import android.content.SharedPreferences;
import eu.kanade.tachiyomi.extension.zh.copymanga.PluginMetaData;
import eu.kanade.tachiyomi.extension.zh.copymanga.PreferencesKt;
import eu.kanade.tachiyomi.extension.zh.copymanga.UserAgentType;
import eu.kanade.tachiyomi.extension.zh.copymanga.interceptor.UserAgentInterceptor;
import eu.kanade.tachiyomi.network.NetworkHelper;
import eu.kanade.tachiyomi.network.RequestsKt;
import java.io.Closeable;
import java.io.IOException;
import java.util.List;
import kotlin.Deprecated;
import kotlin.DeprecationLevel;
import kotlin.Lazy;
import kotlin.LazyKt;
import kotlin.LazyThreadSafetyMode;
import kotlin.Metadata;
import kotlin.NoWhenBranchMatchedException;
import kotlin.ReplaceWith;
import kotlin.ResultKt;
import kotlin.Unit;
import kotlin.collections.CollectionsKt;
import kotlin.coroutines.Continuation;
import kotlin.coroutines.intrinsics.IntrinsicsKt;
import kotlin.coroutines.jvm.internal.DebugMetadata;
import kotlin.coroutines.jvm.internal.SuspendLambda;
import kotlin.io.CloseableKt;
import kotlin.jvm.JvmStatic;
import kotlin.jvm.functions.Function0;
import kotlin.jvm.functions.Function2;
import kotlin.jvm.internal.DefaultConstructorMarker;
import kotlin.jvm.internal.Intrinsics;
import kotlin.jvm.internal.MagicApiIntrinsics;
import kotlin.jvm.internal.Reflection;
import kotlin.random.Random;
import kotlin.reflect.KType;
import kotlin.text.StringsKt;
import kotlinx.coroutines.BuildersKt;
import kotlinx.coroutines.CoroutineScope;
import kotlinx.coroutines.Dispatchers;
import kotlinx.serialization.KSerializer;
import kotlinx.serialization.Serializable;
import kotlinx.serialization.SerializersKt;
import kotlinx.serialization.StringFormat;
import kotlinx.serialization.descriptors.SerialDescriptor;
import kotlinx.serialization.encoding.CompositeEncoder;
import kotlinx.serialization.internal.ArrayListSerializer;
import kotlinx.serialization.internal.PluginExceptionsKt;
import kotlinx.serialization.internal.SerializationConstructorMarker;
import kotlinx.serialization.internal.StringSerializer;
import kotlinx.serialization.json.Json;
import kotlinx.serialization.json.JsonKt;
import kotlinx.serialization.modules.SerializersModule;
import okhttp3.CacheControl;
import okhttp3.Headers;
import okhttp3.Interceptor;
import okhttp3.Request;
import okhttp3.Response;

/* JADX INFO: compiled from: UserAgentInterceptor.kt */
/* JADX INFO: loaded from: classes.dex */
@Metadata(d1 = {"\u0000,\n\u0002\u0018\u0002\n\u0002\u0018\u0002\n\u0000\n\u0002\u0018\u0002\n\u0002\b\u0002\n\u0002\u0018\u0002\n\u0002\b\u0005\n\u0002\u0018\u0002\n\u0000\n\u0002\u0018\u0002\n\u0002\b\u0003\n\u0002\u0018\u0002\u0018\u00002\u00020\u0001:\u0001\u000fB\r\u0012\u0006\u0010\u0002\u001a\u00020\u0003¢\u0006\u0002\u0010\u0004J\u0010\u0010\u000b\u001a\u00020\f2\u0006\u0010\r\u001a\u00020\u000eH\u0016R\u000e\u0010\u0002\u001a\u00020\u0003X\u0082\u0004¢\u0006\u0002\n\u0000R\u001b\u0010\u0005\u001a\u00020\u00068BX\u0082\u0084\u0002¢\u0006\f\n\u0004\b\t\u0010\n\u001a\u0004\b\u0007\u0010\b¨\u0006\u0010²\u0006\n\u0010\u0011\u001a\u00020\u0012X\u008a\u0084\u0002"}, d2 = {"Leu/kanade/tachiyomi/extension/zh/copymanga/interceptor/UserAgentInterceptor;", "Lokhttp3/Interceptor;", "preferences", "Landroid/content/SharedPreferences;", "(Landroid/content/SharedPreferences;)V", "userAgentList", "Leu/kanade/tachiyomi/extension/zh/copymanga/interceptor/UserAgentInterceptor$UserAgentListResult;", "getUserAgentList", "()Leu/kanade/tachiyomi/extension/zh/copymanga/interceptor/UserAgentInterceptor$UserAgentListResult;", "userAgentList$delegate", "Lkotlin/Lazy;", "intercept", "Lokhttp3/Response;", "chain", "Lokhttp3/Interceptor$Chain;", "UserAgentListResult", "tachiyomi-zh.copymanga-v1.4.82_release", "network", "Leu/kanade/tachiyomi/network/NetworkHelper;"}, k = 1, mv = {1, 7, 1}, xi = 48)
public final class UserAgentInterceptor implements Interceptor {
    private final SharedPreferences preferences;

    /* JADX INFO: renamed from: userAgentList$delegate, reason: from kotlin metadata */
    private final Lazy userAgentList;

    /* JADX INFO: compiled from: UserAgentInterceptor.kt */
    @Metadata(k = 3, mv = {1, 7, 1}, xi = 48)
    public /* synthetic */ class WhenMappings {
        public static final /* synthetic */ int[] $EnumSwitchMapping$0;

        static {
            int[] iArr = new int[UserAgentType.values().length];
            try {
                iArr[UserAgentType.NONE.ordinal()] = 1;
            } catch (NoSuchFieldError unused) {
            }
            try {
                iArr[UserAgentType.APP.ordinal()] = 2;
            } catch (NoSuchFieldError unused2) {
            }
            try {
                iArr[UserAgentType.CUSTOM.ordinal()] = 3;
            } catch (NoSuchFieldError unused3) {
            }
            try {
                iArr[UserAgentType.DESKTOP.ordinal()] = 4;
            } catch (NoSuchFieldError unused4) {
            }
            try {
                iArr[UserAgentType.MOBILE.ordinal()] = 5;
            } catch (NoSuchFieldError unused5) {
            }
            $EnumSwitchMapping$0 = iArr;
        }
    }

    public UserAgentInterceptor(SharedPreferences sharedPreferences) {
        Intrinsics.checkNotNullParameter(sharedPreferences, "preferences");
        this.preferences = sharedPreferences;
        this.userAgentList = LazyKt.lazy(LazyThreadSafetyMode.SYNCHRONIZED, new Function0<UserAgentListResult>() { // from class: eu.kanade.tachiyomi.extension.zh.copymanga.interceptor.UserAgentInterceptor$userAgentList$2

            /* JADX INFO: renamed from: eu.kanade.tachiyomi.extension.zh.copymanga.interceptor.UserAgentInterceptor$userAgentList$2$1, reason: invalid class name */
            /* JADX INFO: compiled from: UserAgentInterceptor.kt */
            @Metadata(d1 = {"\u0000\n\n\u0000\n\u0002\u0018\u0002\n\u0002\u0018\u0002\u0010\u0000\u001a\u00020\u0001*\u00020\u0002H\u008a@"}, d2 = {"<anonymous>", "Leu/kanade/tachiyomi/extension/zh/copymanga/interceptor/UserAgentInterceptor$UserAgentListResult;", "Lkotlinx/coroutines/CoroutineScope;"}, k = 3, mv = {1, 7, 1}, xi = 48)
            @DebugMetadata(c = "eu.kanade.tachiyomi.extension.zh.copymanga.interceptor.UserAgentInterceptor$userAgentList$2$1", f = "UserAgentInterceptor.kt", i = {}, l = {}, m = "invokeSuspend", n = {}, s = {})
            static final class AnonymousClass1 extends SuspendLambda implements Function2<CoroutineScope, Continuation<? super UserAgentInterceptor.UserAgentListResult>, Object> {
                int label;

                AnonymousClass1(Continuation<? super AnonymousClass1> continuation) {
                    super(2, continuation);
                }

                public final Continuation<Unit> create(Object obj, Continuation<?> continuation) {
                    return new AnonymousClass1(continuation);
                }

                public final Object invoke(CoroutineScope coroutineScope, Continuation<? super UserAgentInterceptor.UserAgentListResult> continuation) {
                    return create(coroutineScope, continuation).invokeSuspend(Unit.INSTANCE);
                }

                public final Object invokeSuspend(Object obj) {
                    IntrinsicsKt.getCOROUTINE_SUSPENDED();
                    if (this.label != 0) {
                        throw new IllegalStateException("call to 'resume' before 'invoke' with coroutine");
                    }
                    ResultKt.throwOnFailure(obj);
                    try {
                        StringFormat stringFormatJson$default = JsonKt.Json$default((Json) null, UserAgentInterceptor$userAgentList$2$1$json$1.INSTANCE, 1, (Object) null);
                        Response response = (Closeable) invokeSuspend$lambda$0(LazyKt.lazy(UserAgentInterceptor$userAgentList$2$1$invokeSuspend$$inlined$injectLazy$1.INSTANCE)).getClient().newCall(RequestsKt.GET$default("https://keiyoushi.github.io/user-agents/user-agents.json", (Headers) null, (CacheControl) null, 6, (Object) null)).execute();
                        try {
                            StringFormat stringFormat = stringFormatJson$default;
                            String strString = response.body().string();
                            SerializersModule serializersModule = stringFormat.getSerializersModule();
                            KType kTypeTypeOf = Reflection.typeOf(UserAgentInterceptor.UserAgentListResult.class);
                            MagicApiIntrinsics.voidMagicApiCall("kotlinx.serialization.serializer.withModule");
                            UserAgentInterceptor.UserAgentListResult userAgentListResult = (UserAgentInterceptor.UserAgentListResult) stringFormat.decodeFromString(SerializersKt.serializer(serializersModule, kTypeTypeOf), strString);
                            CloseableKt.closeFinally(response, (Throwable) null);
                            return userAgentListResult;
                        } finally {
                        }
                    } catch (IOException unused) {
                        return new UserAgentInterceptor.UserAgentListResult(CollectionsKt.listOf(PluginMetaData.USER_AGENT), CollectionsKt.listOf("Mozilla/5.0 (Android 14; Mobile; rv:136.0) Gecko/136.0 Firefox/136."));
                    }
                }

                private static final NetworkHelper invokeSuspend$lambda$0(Lazy<NetworkHelper> lazy) {
                    return (NetworkHelper) lazy.getValue();
                }
            }

            /* JADX INFO: renamed from: invoke, reason: merged with bridge method [inline-methods] */
            public final UserAgentInterceptor.UserAgentListResult m54invoke() {
                return (UserAgentInterceptor.UserAgentListResult) BuildersKt.runBlocking(Dispatchers.getIO(), new AnonymousClass1(null));
            }
        });
    }

    /* JADX INFO: Thrown type has an unknown type hierarchy: kotlin.NoWhenBranchMatchedException */
    public Response intercept(Interceptor.Chain chain) throws NoWhenBranchMatchedException {
        String str;
        Intrinsics.checkNotNullParameter(chain, "chain");
        Request request = chain.request();
        Request.Builder builderNewBuilder = chain.request().newBuilder();
        int i = WhenMappings.$EnumSwitchMapping$0[PreferencesKt.getUserAgentType(this.preferences).ordinal()];
        if (i == 1) {
            return chain.proceed(builderNewBuilder.removeHeader("User-Agent").build());
        }
        if (i == 2) {
            return chain.proceed(request);
        }
        if (i == 3) {
            String userAgent = PreferencesKt.getUserAgent(this.preferences);
            if (StringsKt.isBlank(userAgent)) {
                return chain.proceed(request);
            }
            str = userAgent;
        } else if (i == 4) {
            str = (String) CollectionsKt.random(getUserAgentList().getDesktop(), Random.Default);
        } else {
            if (i != 5) {
                throw new NoWhenBranchMatchedException();
            }
            str = (String) CollectionsKt.random(getUserAgentList().getMobile(), Random.Default);
        }
        return chain.proceed(builderNewBuilder.header("User-Agent", str).build());
    }

    private final UserAgentListResult getUserAgentList() {
        return (UserAgentListResult) this.userAgentList.getValue();
    }

    /* JADX INFO: Access modifiers changed from: private */
    /* JADX INFO: compiled from: UserAgentInterceptor.kt */
    @Metadata(d1 = {"\u0000B\n\u0002\u0018\u0002\n\u0002\u0010\u0000\n\u0000\n\u0002\u0010\b\n\u0000\n\u0002\u0010 \n\u0002\u0010\u000e\n\u0002\b\u0002\n\u0002\u0018\u0002\n\u0002\b\t\n\u0002\u0010\u000b\n\u0002\b\u0004\n\u0002\u0010\u0002\n\u0002\b\u0002\n\u0002\u0018\u0002\n\u0000\n\u0002\u0018\u0002\n\u0002\b\u0003\b\u0083\b\u0018\u0000 \u001f2\u00020\u0001:\u0002\u001e\u001fB9\b\u0017\u0012\u0006\u0010\u0002\u001a\u00020\u0003\u0012\u000e\u0010\u0004\u001a\n\u0012\u0004\u0012\u00020\u0006\u0018\u00010\u0005\u0012\u000e\u0010\u0007\u001a\n\u0012\u0004\u0012\u00020\u0006\u0018\u00010\u0005\u0012\b\u0010\b\u001a\u0004\u0018\u00010\t¢\u0006\u0002\u0010\nB!\u0012\f\u0010\u0004\u001a\b\u0012\u0004\u0012\u00020\u00060\u0005\u0012\f\u0010\u0007\u001a\b\u0012\u0004\u0012\u00020\u00060\u0005¢\u0006\u0002\u0010\u000bJ\u000f\u0010\u000f\u001a\b\u0012\u0004\u0012\u00020\u00060\u0005HÆ\u0003J\u000f\u0010\u0010\u001a\b\u0012\u0004\u0012\u00020\u00060\u0005HÆ\u0003J)\u0010\u0011\u001a\u00020\u00002\u000e\b\u0002\u0010\u0004\u001a\b\u0012\u0004\u0012\u00020\u00060\u00052\u000e\b\u0002\u0010\u0007\u001a\b\u0012\u0004\u0012\u00020\u00060\u0005HÆ\u0001J\u0013\u0010\u0012\u001a\u00020\u00132\b\u0010\u0014\u001a\u0004\u0018\u00010\u0001HÖ\u0003J\t\u0010\u0015\u001a\u00020\u0003HÖ\u0001J\t\u0010\u0016\u001a\u00020\u0006HÖ\u0001J!\u0010\u0017\u001a\u00020\u00182\u0006\u0010\u0019\u001a\u00020\u00002\u0006\u0010\u001a\u001a\u00020\u001b2\u0006\u0010\u001c\u001a\u00020\u001dHÇ\u0001R\u0017\u0010\u0004\u001a\b\u0012\u0004\u0012\u00020\u00060\u0005¢\u0006\b\n\u0000\u001a\u0004\b\f\u0010\rR\u0017\u0010\u0007\u001a\b\u0012\u0004\u0012\u00020\u00060\u0005¢\u0006\b\n\u0000\u001a\u0004\b\u000e\u0010\r¨\u0006 "}, d2 = {"Leu/kanade/tachiyomi/extension/zh/copymanga/interceptor/UserAgentInterceptor$UserAgentListResult;", "", "seen1", "", "desktop", "", "", "mobile", "serializationConstructorMarker", "Lkotlinx/serialization/internal/SerializationConstructorMarker;", "(ILjava/util/List;Ljava/util/List;Lkotlinx/serialization/internal/SerializationConstructorMarker;)V", "(Ljava/util/List;Ljava/util/List;)V", "getDesktop", "()Ljava/util/List;", "getMobile", "component1", "component2", "copy", "equals", "", "other", "hashCode", "toString", "write$Self", "", "self", "output", "Lkotlinx/serialization/encoding/CompositeEncoder;", "serialDesc", "Lkotlinx/serialization/descriptors/SerialDescriptor;", "$serializer", "Companion", "tachiyomi-zh.copymanga-v1.4.82_release"}, k = 1, mv = {1, 7, 1}, xi = 48)
    @Serializable
    static final /* data */ class UserAgentListResult {

        /* JADX INFO: renamed from: Companion, reason: from kotlin metadata */
        public static final Companion INSTANCE = new Companion(null);
        private final List<String> desktop;
        private final List<String> mobile;

        /* JADX WARN: Multi-variable type inference failed */
        public static /* synthetic */ UserAgentListResult copy$default(UserAgentListResult userAgentListResult, List list, List list2, int i, Object obj) {
            if ((i & 1) != 0) {
                list = userAgentListResult.desktop;
            }
            if ((i & 2) != 0) {
                list2 = userAgentListResult.mobile;
            }
            return userAgentListResult.copy(list, list2);
        }

        public final List<String> component1() {
            return this.desktop;
        }

        public final List<String> component2() {
            return this.mobile;
        }

        public final UserAgentListResult copy(List<String> desktop, List<String> mobile) {
            Intrinsics.checkNotNullParameter(desktop, "desktop");
            Intrinsics.checkNotNullParameter(mobile, "mobile");
            return new UserAgentListResult(desktop, mobile);
        }

        public boolean equals(Object other) {
            if (this == other) {
                return true;
            }
            if (!(other instanceof UserAgentListResult)) {
                return false;
            }
            UserAgentListResult userAgentListResult = (UserAgentListResult) other;
            return Intrinsics.areEqual(this.desktop, userAgentListResult.desktop) && Intrinsics.areEqual(this.mobile, userAgentListResult.mobile);
        }

        public int hashCode() {
            return (this.desktop.hashCode() * 31) + this.mobile.hashCode();
        }

        public String toString() {
            return "UserAgentListResult(desktop=" + this.desktop + ", mobile=" + this.mobile + ')';
        }

        /* JADX INFO: compiled from: UserAgentInterceptor.kt */
        @Metadata(d1 = {"\u0000\u0016\n\u0002\u0018\u0002\n\u0002\u0010\u0000\n\u0002\b\u0002\n\u0002\u0018\u0002\n\u0002\u0018\u0002\n\u0000\b\u0086\u0003\u0018\u00002\u00020\u0001B\u0007\b\u0002¢\u0006\u0002\u0010\u0002J\u000f\u0010\u0003\u001a\b\u0012\u0004\u0012\u00020\u00050\u0004HÆ\u0001¨\u0006\u0006"}, d2 = {"Leu/kanade/tachiyomi/extension/zh/copymanga/interceptor/UserAgentInterceptor$UserAgentListResult$Companion;", "", "()V", "serializer", "Lkotlinx/serialization/KSerializer;", "Leu/kanade/tachiyomi/extension/zh/copymanga/interceptor/UserAgentInterceptor$UserAgentListResult;", "tachiyomi-zh.copymanga-v1.4.82_release"}, k = 1, mv = {1, 7, 1}, xi = 48)
        public static final class Companion {
            public /* synthetic */ Companion(DefaultConstructorMarker defaultConstructorMarker) {
                this();
            }

            private Companion() {
            }

            public final KSerializer<UserAgentListResult> serializer() {
                return UserAgentInterceptor$UserAgentListResult$$serializer.INSTANCE;
            }
        }

        @Deprecated(level = DeprecationLevel.HIDDEN, message = "This synthesized declaration should not be used directly", replaceWith = @ReplaceWith(expression = "", imports = {}))
        public /* synthetic */ UserAgentListResult(int i, List list, List list2, SerializationConstructorMarker serializationConstructorMarker) {
            if (3 != (i & 3)) {
                PluginExceptionsKt.throwMissingFieldException(i, 3, UserAgentInterceptor$UserAgentListResult$$serializer.INSTANCE.getDescriptor());
            }
            this.desktop = list;
            this.mobile = list2;
        }

        public UserAgentListResult(List<String> list, List<String> list2) {
            Intrinsics.checkNotNullParameter(list, "desktop");
            Intrinsics.checkNotNullParameter(list2, "mobile");
            this.desktop = list;
            this.mobile = list2;
        }

        @JvmStatic
        public static final void write$Self(UserAgentListResult self, CompositeEncoder output, SerialDescriptor serialDesc) {
            Intrinsics.checkNotNullParameter(self, "self");
            Intrinsics.checkNotNullParameter(output, "output");
            Intrinsics.checkNotNullParameter(serialDesc, "serialDesc");
            output.encodeSerializableElement(serialDesc, 0, new ArrayListSerializer(StringSerializer.INSTANCE), self.desktop);
            output.encodeSerializableElement(serialDesc, 1, new ArrayListSerializer(StringSerializer.INSTANCE), self.mobile);
        }

        public final List<String> getDesktop() {
            return this.desktop;
        }

        public final List<String> getMobile() {
            return this.mobile;
        }
    }
}
