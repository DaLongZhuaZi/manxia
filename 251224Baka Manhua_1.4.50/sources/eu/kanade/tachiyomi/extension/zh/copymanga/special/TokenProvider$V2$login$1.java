package eu.kanade.tachiyomi.extension.zh.copymanga.special;

import androidx.preference.SwitchPreferenceCompat;
import eu.kanade.tachiyomi.extension.zh.copymanga.special.TokenProvider;
import kotlin.Metadata;
import kotlin.Unit;
import kotlin.jvm.functions.Function0;
import kotlin.jvm.functions.Function1;
import kotlin.jvm.internal.Intrinsics;
import kotlin.jvm.internal.Lambda;
import rx.Observable;
import rx.functions.Action1;

/* compiled from: TokenProvider.kt */
@Metadata(d1 = {"\u0000\b\n\u0000\n\u0002\u0010\u0002\n\u0000\u0010\u0000\u001a\u00020\u0001H\n¢\u0006\u0002\b\u0002"}, d2 = {"<anonymous>", "", "invoke"}, k = 3, mv = {1, 7, 1}, xi = 48)
/* loaded from: classes.dex */
final class TokenProvider$V2$login$1 extends Lambda implements Function0<Unit> {
    final /* synthetic */ SwitchPreferenceCompat $enableLoginPreferences;
    final /* synthetic */ String $url;

    /* JADX WARN: 'super' call moved to the top of the method (can break code semantics) */
    TokenProvider$V2$login$1(String str, SwitchPreferenceCompat switchPreferenceCompat) {
        super(0);
        this.$url = str;
        this.$enableLoginPreferences = switchPreferenceCompat;
    }

    public /* bridge */ /* synthetic */ Object invoke() {
        m58invoke();
        return Unit.INSTANCE;
    }

    /* renamed from: invoke, reason: collision with other method in class */
    public final void m58invoke() {
        Observable token$default = TokenProvider.V2.getToken$default(TokenProvider.V2.INSTANCE, this.$url, null, 2, null);
        final SwitchPreferenceCompat switchPreferenceCompat = this.$enableLoginPreferences;
        final String str = this.$url;
        final Function1<String, Unit> function1 = new Function1<String, Unit>() { // from class: eu.kanade.tachiyomi.extension.zh.copymanga.special.TokenProvider$V2$login$1.1
            /* JADX WARN: 'super' call moved to the top of the method (can break code semantics) */
            {
                super(1);
            }

            public /* bridge */ /* synthetic */ Object invoke(Object obj) {
                invoke((String) obj);
                return Unit.INSTANCE;
            }

            public final void invoke(final String str2) {
                TokenProvider tokenProvider = TokenProvider.INSTANCE;
                SwitchPreferenceCompat switchPreferenceCompat2 = switchPreferenceCompat;
                final String str3 = str;
                tokenProvider.updateSummary(switchPreferenceCompat2, new Function0<Unit>() { // from class: eu.kanade.tachiyomi.extension.zh.copymanga.special.TokenProvider.V2.login.1.1.1
                    /* JADX WARN: 'super' call moved to the top of the method (can break code semantics) */
                    {
                        super(0);
                    }

                    public /* bridge */ /* synthetic */ Object invoke() {
                        m59invoke();
                        return Unit.INSTANCE;
                    }

                    /* renamed from: invoke, reason: collision with other method in class */
                    public final void m59invoke() {
                        String str4 = str3;
                        String str5 = str2;
                        Intrinsics.checkNotNullExpressionValue(str5, "token");
                        TokenProvider.V2.login$setToken(str4, str5);
                    }
                });
            }
        };
        Action1 action1 = new Action1() { // from class: eu.kanade.tachiyomi.extension.zh.copymanga.special.TokenProvider$V2$login$1$$ExternalSyntheticLambda0
            public final void call(Object obj) {
                TokenProvider$V2$login$1.invoke$lambda$0(function1, obj);
            }
        };
        final SwitchPreferenceCompat switchPreferenceCompat2 = this.$enableLoginPreferences;
        final String str2 = this.$url;
        token$default.subscribe(action1, new Action1() { // from class: eu.kanade.tachiyomi.extension.zh.copymanga.special.TokenProvider$V2$login$1$$ExternalSyntheticLambda1
            public final void call(Object obj) {
                TokenProvider$V2$login$1.invoke$lambda$1(switchPreferenceCompat2, str2, (Throwable) obj);
            }
        });
    }

    /* JADX INFO: Access modifiers changed from: private */
    public static final void invoke$lambda$0(Function1 function1, Object obj) {
        Intrinsics.checkNotNullParameter(function1, "$tmp0");
        function1.invoke(obj);
    }

    /* JADX INFO: Access modifiers changed from: private */
    public static final void invoke$lambda$1(SwitchPreferenceCompat switchPreferenceCompat, final String str, final Throwable th) {
        Intrinsics.checkNotNullParameter(switchPreferenceCompat, "$enableLoginPreferences");
        Intrinsics.checkNotNullParameter(str, "$url");
        TokenProvider.INSTANCE.updateSummary(switchPreferenceCompat, new Function0<Unit>() { // from class: eu.kanade.tachiyomi.extension.zh.copymanga.special.TokenProvider$V2$login$1$2$1
            /* JADX WARN: 'super' call moved to the top of the method (can break code semantics) */
            {
                super(0);
            }

            public /* bridge */ /* synthetic */ Object invoke() {
                m60invoke();
                return Unit.INSTANCE;
            }

            /* renamed from: invoke, reason: collision with other method in class */
            public final void m60invoke() {
                TokenProvider.V2.login$setToken(str, TokenProvider.LoginStatus.LOGIN_FAILED.getKey() + th.getMessage());
            }
        });
    }
}
