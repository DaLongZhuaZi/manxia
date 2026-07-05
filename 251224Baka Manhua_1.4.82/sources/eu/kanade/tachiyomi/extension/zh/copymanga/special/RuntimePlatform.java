package eu.kanade.tachiyomi.extension.zh.copymanga.special;

import kotlin.Lazy;
import kotlin.LazyKt;
import kotlin.Metadata;
import kotlin.Result;
import kotlin.ResultKt;
import kotlin.jvm.functions.Function0;

/* JADX INFO: compiled from: RuntimePlatform.kt */
/* JADX INFO: loaded from: classes.dex */
@Metadata(d1 = {"\u0000\u0014\n\u0002\u0018\u0002\n\u0002\u0010\u0000\n\u0002\b\u0002\n\u0002\u0010\u000b\n\u0002\b\u0004\bÆ\u0002\u0018\u00002\u00020\u0001B\u0007\b\u0002¢\u0006\u0002\u0010\u0002R\u001b\u0010\u0003\u001a\u00020\u00048FX\u0086\u0084\u0002¢\u0006\f\n\u0004\b\u0006\u0010\u0007\u001a\u0004\b\u0003\u0010\u0005¨\u0006\b"}, d2 = {"Leu/kanade/tachiyomi/extension/zh/copymanga/special/RuntimePlatform;", "", "()V", "isTachiDesk", "", "()Z", "isTachiDesk$delegate", "Lkotlin/Lazy;", "tachiyomi-zh.copymanga-v1.4.82_release"}, k = 1, mv = {1, 7, 1}, xi = 48)
public final class RuntimePlatform {
    public static final RuntimePlatform INSTANCE = new RuntimePlatform();

    /* JADX INFO: renamed from: isTachiDesk$delegate, reason: from kotlin metadata */
    private static final Lazy isTachiDesk = LazyKt.lazy(new Function0<Boolean>() { // from class: eu.kanade.tachiyomi.extension.zh.copymanga.special.RuntimePlatform.isTachiDesk.2
        /* JADX INFO: renamed from: invoke, reason: merged with bridge method [inline-methods] */
        public final Boolean m55invoke() {
            Object obj;
            RuntimePlatform runtimePlatform = RuntimePlatform.INSTANCE;
            try {
                Result.Companion companion = Result.Companion;
                obj = Result.constructor-impl(Class.forName("io.javalin.Javalin"));
            } catch (Throwable th) {
                Result.Companion companion2 = Result.Companion;
                obj = Result.constructor-impl(ResultKt.createFailure(th));
            }
            return Boolean.valueOf(Result.isSuccess-impl(obj));
        }
    });

    private RuntimePlatform() {
    }

    public final boolean isTachiDesk() {
        return ((Boolean) isTachiDesk.getValue()).booleanValue();
    }
}
