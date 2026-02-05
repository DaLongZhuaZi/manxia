package eu.kanade.tachiyomi.extension.zh.copymanga;

import kotlin.Metadata;
import kotlin.jvm.internal.DefaultConstructorMarker;
import kotlin.jvm.internal.Intrinsics;

/* compiled from: Constants.kt */
@Metadata(d1 = {"\u0000\u0012\n\u0002\u0018\u0002\n\u0002\u0010\u0010\n\u0000\n\u0002\u0010\u000e\n\u0002\b\n\b\u0086\u0001\u0018\u0000 \f2\b\u0012\u0004\u0012\u00020\u00000\u0001:\u0001\fB\u000f\b\u0002\u0012\u0006\u0010\u0002\u001a\u00020\u0003¢\u0006\u0002\u0010\u0004R\u0011\u0010\u0002\u001a\u00020\u0003¢\u0006\b\n\u0000\u001a\u0004\b\u0005\u0010\u0006j\u0002\b\u0007j\u0002\b\bj\u0002\b\tj\u0002\b\nj\u0002\b\u000b¨\u0006\r"}, d2 = {"Leu/kanade/tachiyomi/extension/zh/copymanga/UserAgentType;", "", "key", "", "(Ljava/lang/String;ILjava/lang/String;)V", "getKey", "()Ljava/lang/String;", "DESKTOP", "MOBILE", "APP", "CUSTOM", "NONE", "Companion", "tachiyomi-zh.copymanga-v1.4.78_release"}, k = 1, mv = {1, 7, 1}, xi = 48)
/* loaded from: classes.dex */
public enum UserAgentType {
    DESKTOP("desktop"),
    MOBILE("mobile"),
    APP("app"),
    CUSTOM("custom"),
    NONE("none");


    /* renamed from: Companion, reason: from kotlin metadata */
    public static final Companion INSTANCE = new Companion(null);
    private final String key;

    UserAgentType(String str) {
        this.key = str;
    }

    public final String getKey() {
        return this.key;
    }

    /* compiled from: Constants.kt */
    @Metadata(d1 = {"\u0000\u0018\n\u0002\u0018\u0002\n\u0002\u0010\u0000\n\u0002\b\u0002\n\u0002\u0018\u0002\n\u0000\n\u0002\u0010\u000e\n\u0000\b\u0086\u0003\u0018\u00002\u00020\u0001B\u0007\b\u0002¢\u0006\u0002\u0010\u0002J\u000e\u0010\u0003\u001a\u00020\u00042\u0006\u0010\u0005\u001a\u00020\u0006¨\u0006\u0007"}, d2 = {"Leu/kanade/tachiyomi/extension/zh/copymanga/UserAgentType$Companion;", "", "()V", "getType", "Leu/kanade/tachiyomi/extension/zh/copymanga/UserAgentType;", "key", "", "tachiyomi-zh.copymanga-v1.4.78_release"}, k = 1, mv = {1, 7, 1}, xi = 48)
    public static final class Companion {
        public /* synthetic */ Companion(DefaultConstructorMarker defaultConstructorMarker) {
            this();
        }

        private Companion() {
        }

        public final UserAgentType getType(String key) {
            UserAgentType userAgentType;
            Intrinsics.checkNotNullParameter(key, "key");
            UserAgentType[] userAgentTypeArrValues = UserAgentType.values();
            int length = userAgentTypeArrValues.length;
            int i = 0;
            while (true) {
                if (i >= length) {
                    userAgentType = null;
                    break;
                }
                userAgentType = userAgentTypeArrValues[i];
                if (Intrinsics.areEqual(userAgentType.getKey(), key)) {
                    break;
                }
                i++;
            }
            return userAgentType == null ? UserAgentType.CUSTOM : userAgentType;
        }
    }
}
