package eu.kanade.tachiyomi.extension.zh.copymanga;

import java.util.ArrayList;
import kotlin.Metadata;
import kotlin.jvm.internal.DefaultConstructorMarker;
import kotlin.jvm.internal.Intrinsics;

/* compiled from: Constants.kt */
@Metadata(d1 = {"\u0000\u0012\n\u0002\u0018\u0002\n\u0002\u0010\u0010\n\u0000\n\u0002\u0010\u000e\n\u0002\b\n\b\u0086\u0001\u0018\u0000 \f2\b\u0012\u0004\u0012\u00020\u00000\u0001:\u0001\fB\u0017\b\u0002\u0012\u0006\u0010\u0002\u001a\u00020\u0003\u0012\u0006\u0010\u0004\u001a\u00020\u0003¢\u0006\u0002\u0010\u0005R\u0011\u0010\u0002\u001a\u00020\u0003¢\u0006\b\n\u0000\u001a\u0004\b\u0006\u0010\u0007R\u0011\u0010\u0004\u001a\u00020\u0003¢\u0006\b\n\u0000\u001a\u0004\b\b\u0010\u0007j\u0002\b\tj\u0002\b\nj\u0002\b\u000b¨\u0006\r"}, d2 = {"Leu/kanade/tachiyomi/extension/zh/copymanga/CCOption;", "", "entry", "", "entryKey", "(Ljava/lang/String;ILjava/lang/String;Ljava/lang/String;)V", "getEntry", "()Ljava/lang/String;", "getEntryKey", "DEFAULT", "SIMPLIFIED", "TRADITIONAL", "Companion", "tachiyomi-zh.copymanga-v1.4.78_release"}, k = 1, mv = {1, 7, 1}, xi = 48)
/* loaded from: classes.dex */
public enum CCOption {
    DEFAULT("默認", "lan.default"),
    SIMPLIFIED("简体", "lan.zh-cn"),
    TRADITIONAL("繁體", "lan.zh-tw");


    /* renamed from: Companion, reason: from kotlin metadata */
    public static final Companion INSTANCE = new Companion(null);
    private static final String[] ENTRIES;
    private static final String[] ENTRY_KEYS;
    public static final String KEY = "v2.pref.lan_option";
    private final String entry;
    private final String entryKey;

    CCOption(String str, String str2) {
        this.entry = str;
        this.entryKey = str2;
    }

    public final String getEntry() {
        return this.entry;
    }

    public final String getEntryKey() {
        return this.entryKey;
    }

    static {
        CCOption[] cCOptionArrValues = values();
        ArrayList arrayList = new ArrayList(cCOptionArrValues.length);
        for (CCOption cCOption : cCOptionArrValues) {
            arrayList.add(cCOption.entry);
        }
        ENTRIES = (String[]) arrayList.toArray(new String[0]);
        CCOption[] cCOptionArrValues2 = values();
        ArrayList arrayList2 = new ArrayList(cCOptionArrValues2.length);
        for (CCOption cCOption2 : cCOptionArrValues2) {
            arrayList2.add(cCOption2.entryKey);
        }
        ENTRY_KEYS = (String[]) arrayList2.toArray(new String[0]);
    }

    /* compiled from: Constants.kt */
    @Metadata(d1 = {"\u0000 \n\u0002\u0018\u0002\n\u0002\u0010\u0000\n\u0002\b\u0002\n\u0002\u0010\u0011\n\u0002\u0010\u000e\n\u0002\b\u0007\n\u0002\u0018\u0002\n\u0002\b\u0002\b\u0086\u0003\u0018\u00002\u00020\u0001B\u0007\b\u0002¢\u0006\u0002\u0010\u0002J\u000e\u0010\f\u001a\u00020\r2\u0006\u0010\u000e\u001a\u00020\u0005R\u0019\u0010\u0003\u001a\b\u0012\u0004\u0012\u00020\u00050\u0004¢\u0006\n\n\u0002\u0010\b\u001a\u0004\b\u0006\u0010\u0007R\u0019\u0010\t\u001a\b\u0012\u0004\u0012\u00020\u00050\u0004¢\u0006\n\n\u0002\u0010\b\u001a\u0004\b\n\u0010\u0007R\u000e\u0010\u000b\u001a\u00020\u0005X\u0086T¢\u0006\u0002\n\u0000¨\u0006\u000f"}, d2 = {"Leu/kanade/tachiyomi/extension/zh/copymanga/CCOption$Companion;", "", "()V", "ENTRIES", "", "", "getENTRIES", "()[Ljava/lang/String;", "[Ljava/lang/String;", "ENTRY_KEYS", "getENTRY_KEYS", "KEY", "key2mode", "Leu/kanade/tachiyomi/extension/zh/copymanga/CCOption;", "key", "tachiyomi-zh.copymanga-v1.4.78_release"}, k = 1, mv = {1, 7, 1}, xi = 48)
    public static final class Companion {
        public /* synthetic */ Companion(DefaultConstructorMarker defaultConstructorMarker) {
            this();
        }

        private Companion() {
        }

        public final String[] getENTRIES() {
            return CCOption.ENTRIES;
        }

        public final String[] getENTRY_KEYS() {
            return CCOption.ENTRY_KEYS;
        }

        public final CCOption key2mode(String key) throws Exception {
            CCOption cCOption;
            Intrinsics.checkNotNullParameter(key, "key");
            CCOption[] cCOptionArrValues = CCOption.values();
            int length = cCOptionArrValues.length;
            int i = 0;
            while (true) {
                if (i >= length) {
                    cCOption = null;
                    break;
                }
                cCOption = cCOptionArrValues[i];
                if (Intrinsics.areEqual(cCOption.getEntryKey(), key)) {
                    break;
                }
                i++;
            }
            if (cCOption != null) {
                return cCOption;
            }
            throw new Exception("Unknown Key for CCOption : " + key);
        }
    }
}
