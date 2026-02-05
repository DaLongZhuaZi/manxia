package keiyoushi.utils;

import android.app.Application;
import android.content.SharedPreferences;
import eu.kanade.tachiyomi.source.online.HttpSource;
import kotlin.Lazy;
import kotlin.LazyKt;
import kotlin.Metadata;
import kotlin.Unit;
import kotlin.jvm.functions.Function0;
import kotlin.jvm.functions.Function1;
import kotlin.jvm.internal.Intrinsics;
import kotlin.jvm.internal.Lambda;
import uy.kohesive.injekt.InjektKt;

/* compiled from: Preferences.kt */
@Metadata(d1 = {"\u0000&\n\u0000\n\u0002\u0018\u0002\n\u0000\n\u0002\u0010\t\n\u0002\u0018\u0002\n\u0000\n\u0002\u0018\u0002\n\u0002\u0010\u0002\n\u0002\u0018\u0002\n\u0000\n\u0002\u0018\u0002\n\u0000\u001a\u0011\u0010\u0000\u001a\u00020\u00012\u0006\u0010\u0002\u001a\u00020\u0003H\u0086\b\u001a+\u0010\u0000\u001a\u00020\u0001*\u00020\u00042\u0019\b\u0002\u0010\u0005\u001a\u0013\u0012\u0004\u0012\u00020\u0001\u0012\u0004\u0012\u00020\u00070\u0006¢\u0006\u0002\b\bH\u0086\bø\u0001\u0000\u001a1\u0010\t\u001a\b\u0012\u0004\u0012\u00020\u00010\n*\u00020\u00042\u0019\b\u0006\u0010\u0005\u001a\u0013\u0012\u0004\u0012\u00020\u0001\u0012\u0004\u0012\u00020\u00070\u0006¢\u0006\u0002\b\bH\u0086\bø\u0001\u0000\u0082\u0002\u0007\n\u0005\b\u009920\u0001¨\u0006\u000b"}, d2 = {"getPreferences", "Landroid/content/SharedPreferences;", "sourceId", "", "Leu/kanade/tachiyomi/source/online/HttpSource;", "migration", "Lkotlin/Function1;", "", "Lkotlin/ExtensionFunctionType;", "getPreferencesLazy", "Lkotlin/Lazy;", "core_release"}, k = 2, mv = {1, 7, 1}, xi = 48)
/* loaded from: classes.dex */
public final class PreferencesKt {
    public static /* synthetic */ SharedPreferences getPreferences$default(HttpSource httpSource, Function1 function1, int i, Object obj) {
        if ((i & 1) != 0) {
            function1 = new Function1<SharedPreferences, Unit>() { // from class: keiyoushi.utils.PreferencesKt.getPreferences.1
                public final void invoke(SharedPreferences sharedPreferences) {
                    Intrinsics.checkNotNullParameter(sharedPreferences, "$this$null");
                }

                public /* bridge */ /* synthetic */ Object invoke(Object obj2) {
                    invoke((SharedPreferences) obj2);
                    return Unit.INSTANCE;
                }
            };
        }
        Intrinsics.checkNotNullParameter(httpSource, "<this>");
        Intrinsics.checkNotNullParameter(function1, "migration");
        long id = httpSource.getId();
        SharedPreferences sharedPreferences = ((Application) InjektKt.getInjekt().getInstance(new PreferencesKt$getPreferences$$inlined$get$1().getType())).getSharedPreferences("source_" + id, 0);
        Intrinsics.checkNotNullExpressionValue(sharedPreferences, "Injekt.get<Application>(…ource_$sourceId\", 0x0000)");
        function1.invoke(sharedPreferences);
        return sharedPreferences;
    }

    public static final SharedPreferences getPreferences(HttpSource httpSource, Function1<? super SharedPreferences, Unit> function1) {
        Intrinsics.checkNotNullParameter(httpSource, "<this>");
        Intrinsics.checkNotNullParameter(function1, "migration");
        long id = httpSource.getId();
        SharedPreferences sharedPreferences = ((Application) InjektKt.getInjekt().getInstance(new PreferencesKt$getPreferences$$inlined$get$1().getType())).getSharedPreferences("source_" + id, 0);
        Intrinsics.checkNotNullExpressionValue(sharedPreferences, "Injekt.get<Application>(…ource_$sourceId\", 0x0000)");
        function1.invoke(sharedPreferences);
        return sharedPreferences;
    }

    /* compiled from: Preferences.kt */
    @Metadata(d1 = {"\u0000\b\n\u0000\n\u0002\u0018\u0002\n\u0000\u0010\u0000\u001a\u00020\u0001H\n¢\u0006\u0002\b\u0002"}, d2 = {"<anonymous>", "Landroid/content/SharedPreferences;", "invoke"}, k = 3, mv = {1, 7, 1}, xi = 176)
    /* renamed from: keiyoushi.utils.PreferencesKt$getPreferencesLazy$2, reason: invalid class name */
    public static final class AnonymousClass2 extends Lambda implements Function0<SharedPreferences> {
        final /* synthetic */ Function1<SharedPreferences, Unit> $migration;
        final /* synthetic */ HttpSource $this_getPreferencesLazy;

        /* JADX WARN: 'super' call moved to the top of the method (can break code semantics) */
        /* JADX WARN: Multi-variable type inference failed */
        public AnonymousClass2(HttpSource httpSource, Function1<? super SharedPreferences, Unit> function1) {
            super(0);
            this.$this_getPreferencesLazy = httpSource;
            this.$migration = function1;
        }

        /* renamed from: invoke, reason: merged with bridge method [inline-methods] */
        public final SharedPreferences m62invoke() {
            HttpSource httpSource = this.$this_getPreferencesLazy;
            Function1<SharedPreferences, Unit> function1 = this.$migration;
            long id = httpSource.getId();
            SharedPreferences sharedPreferences = ((Application) InjektKt.getInjekt().getInstance(new PreferencesKt$getPreferences$$inlined$get$1().getType())).getSharedPreferences("source_" + id, 0);
            Intrinsics.checkNotNullExpressionValue(sharedPreferences, "Injekt.get<Application>(…ource_$sourceId\", 0x0000)");
            function1.invoke(sharedPreferences);
            return sharedPreferences;
        }
    }

    public static /* synthetic */ Lazy getPreferencesLazy$default(HttpSource httpSource, Function1 function1, int i, Object obj) {
        if ((i & 1) != 0) {
            function1 = new Function1<SharedPreferences, Unit>() { // from class: keiyoushi.utils.PreferencesKt.getPreferencesLazy.1
                public final void invoke(SharedPreferences sharedPreferences) {
                    Intrinsics.checkNotNullParameter(sharedPreferences, "$this$null");
                }

                public /* bridge */ /* synthetic */ Object invoke(Object obj2) {
                    invoke((SharedPreferences) obj2);
                    return Unit.INSTANCE;
                }
            };
        }
        Intrinsics.checkNotNullParameter(httpSource, "<this>");
        Intrinsics.checkNotNullParameter(function1, "migration");
        return LazyKt.lazy(new AnonymousClass2(httpSource, function1));
    }

    public static final Lazy<SharedPreferences> getPreferencesLazy(HttpSource httpSource, Function1<? super SharedPreferences, Unit> function1) {
        Intrinsics.checkNotNullParameter(httpSource, "<this>");
        Intrinsics.checkNotNullParameter(function1, "migration");
        return LazyKt.lazy(new AnonymousClass2(httpSource, function1));
    }

    public static final SharedPreferences getPreferences(long j) {
        SharedPreferences sharedPreferences = ((Application) InjektKt.getInjekt().getInstance(new PreferencesKt$getPreferences$$inlined$get$1().getType())).getSharedPreferences("source_" + j, 0);
        Intrinsics.checkNotNullExpressionValue(sharedPreferences, "Injekt.get<Application>(…ource_$sourceId\", 0x0000)");
        return sharedPreferences;
    }
}
