package eu.kanade.tachiyomi.extension.zh.copymanga;

import eu.kanade.tachiyomi.lib.chineseutils.pinyin.Pinyin;
import java.util.ArrayList;
import kotlin.Metadata;
import kotlin.jvm.internal.DefaultConstructorMarker;
import kotlin.jvm.internal.Intrinsics;

/* JADX WARN: Enum visitor error
jadx.core.utils.exceptions.JadxRuntimeException: Can't remove SSA var: r0v2 eu.kanade.tachiyomi.extension.zh.copymanga.PlatFormOption, still in use, count: 1, list:
  (r0v2 eu.kanade.tachiyomi.extension.zh.copymanga.PlatFormOption) from 0x0070: IGET (r0v2 eu.kanade.tachiyomi.extension.zh.copymanga.PlatFormOption) A[WRAPPED] (LINE:296) eu.kanade.tachiyomi.extension.zh.copymanga.PlatFormOption.entryKey java.lang.String
	at jadx.core.utils.InsnRemover.removeSsaVar(InsnRemover.java:162)
	at jadx.core.utils.InsnRemover.unbindResult(InsnRemover.java:127)
	at jadx.core.utils.InsnRemover.lambda$unbindInsns$1(InsnRemover.java:99)
	at java.base/java.util.ArrayList.forEach(Unknown Source)
	at jadx.core.utils.InsnRemover.unbindInsns(InsnRemover.java:98)
	at jadx.core.utils.InsnRemover.removeAllAndUnbind(InsnRemover.java:252)
	at jadx.core.dex.visitors.EnumVisitor.convertToEnum(EnumVisitor.java:180)
	at jadx.core.dex.visitors.EnumVisitor.visit(EnumVisitor.java:100)
 */
/* JADX WARN: Failed to restore enum class, 'enum' modifier and super class removed */
/* compiled from: Constants.kt */
@Metadata(d1 = {"\u0000\u0012\n\u0002\u0018\u0002\n\u0002\u0010\u0010\n\u0000\n\u0002\u0010\u000e\n\u0002\b\u000e\b\u0086\u0001\u0018\u0000 \u00102\b\u0012\u0004\u0012\u00020\u00000\u0001:\u0001\u0010B\u0017\b\u0002\u0012\u0006\u0010\u0002\u001a\u00020\u0003\u0012\u0006\u0010\u0004\u001a\u00020\u0003¢\u0006\u0002\u0010\u0005R\u0011\u0010\u0002\u001a\u00020\u0003¢\u0006\b\n\u0000\u001a\u0004\b\u0006\u0010\u0007R\u0011\u0010\u0004\u001a\u00020\u0003¢\u0006\b\n\u0000\u001a\u0004\b\b\u0010\u0007j\u0002\b\tj\u0002\b\nj\u0002\b\u000bj\u0002\b\fj\u0002\b\rj\u0002\b\u000ej\u0002\b\u000f¨\u0006\u0011"}, d2 = {"Leu/kanade/tachiyomi/extension/zh/copymanga/PlatFormOption;", "", "entry", "", "entryKey", "(Ljava/lang/String;ILjava/lang/String;Ljava/lang/String;)V", "getEntry", "()Ljava/lang/String;", "getEntryKey", "NONE", "BLANK", "ONE", "TWO", "THREE", "FOUR", "FIVE", "Companion", "tachiyomi-zh.copymanga-v1.4.78_release"}, k = 1, mv = {1, 7, 1}, xi = 48)
/* loaded from: classes.dex */
public final class PlatFormOption {
    NONE("無", "platform.none"),
    BLANK("空格", "platform.blank"),
    ONE("1", "platform.one"),
    TWO("2", "platform.two"),
    THREE("3", "platform.three"),
    FOUR("4", "platform.four"),
    FIVE("5", "platform.five");

    private static final String DEFAULT = new PlatFormOption("1", "platform.one").entryKey;
    private static final String[] ENTRIES;
    private static final String[] ENTRY_KEYS;
    public static final String KEY = "v2.pref.platform";
    private final String entry;
    private final String entryKey;

    /* renamed from: Companion, reason: from kotlin metadata */
    public static final Companion INSTANCE = new Companion(null);

    public static PlatFormOption valueOf(String str) {
        return (PlatFormOption) Enum.valueOf(PlatFormOption.class, str);
    }

    public static PlatFormOption[] values() {
        return (PlatFormOption[]) $VALUES.clone();
    }

    private PlatFormOption(String str, String str2) {
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
        PlatFormOption[] platFormOptionArrValues = values();
        ArrayList arrayList = new ArrayList(platFormOptionArrValues.length);
        for (PlatFormOption platFormOption : platFormOptionArrValues) {
            arrayList.add(platFormOption.entry);
        }
        ENTRIES = (String[]) arrayList.toArray(new String[0]);
        PlatFormOption[] platFormOptionArrValues2 = values();
        ArrayList arrayList2 = new ArrayList(platFormOptionArrValues2.length);
        for (PlatFormOption platFormOption2 : platFormOptionArrValues2) {
            arrayList2.add(platFormOption2.entryKey);
        }
        ENTRY_KEYS = (String[]) arrayList2.toArray(new String[0]);
    }

    /* compiled from: Constants.kt */
    @Metadata(d1 = {"\u0000\u001c\n\u0002\u0018\u0002\n\u0002\u0010\u0000\n\u0002\b\u0002\n\u0002\u0010\u000e\n\u0002\b\u0003\n\u0002\u0010\u0011\n\u0002\b\t\b\u0086\u0003\u0018\u00002\u00020\u0001B\u0007\b\u0002¢\u0006\u0002\u0010\u0002J\u000e\u0010\u000f\u001a\u00020\u00042\u0006\u0010\u0010\u001a\u00020\u0004R\u0011\u0010\u0003\u001a\u00020\u0004¢\u0006\b\n\u0000\u001a\u0004\b\u0005\u0010\u0006R\u0019\u0010\u0007\u001a\b\u0012\u0004\u0012\u00020\u00040\b¢\u0006\n\n\u0002\u0010\u000b\u001a\u0004\b\t\u0010\nR\u0019\u0010\f\u001a\b\u0012\u0004\u0012\u00020\u00040\b¢\u0006\n\n\u0002\u0010\u000b\u001a\u0004\b\r\u0010\nR\u000e\u0010\u000e\u001a\u00020\u0004X\u0086T¢\u0006\u0002\n\u0000¨\u0006\u0011"}, d2 = {"Leu/kanade/tachiyomi/extension/zh/copymanga/PlatFormOption$Companion;", "", "()V", "DEFAULT", "", "getDEFAULT", "()Ljava/lang/String;", "ENTRIES", "", "getENTRIES", "()[Ljava/lang/String;", "[Ljava/lang/String;", "ENTRY_KEYS", "getENTRY_KEYS", "KEY", "key2value", "key", "tachiyomi-zh.copymanga-v1.4.78_release"}, k = 1, mv = {1, 7, 1}, xi = 48)
    public static final class Companion {
        public /* synthetic */ Companion(DefaultConstructorMarker defaultConstructorMarker) {
            this();
        }

        private Companion() {
        }

        public final String getDEFAULT() {
            return PlatFormOption.DEFAULT;
        }

        public final String[] getENTRIES() {
            return PlatFormOption.ENTRIES;
        }

        public final String[] getENTRY_KEYS() {
            return PlatFormOption.ENTRY_KEYS;
        }

        public final String key2value(String key) throws Exception {
            Intrinsics.checkNotNullParameter(key, "key");
            if (Intrinsics.areEqual(key, PlatFormOption.NONE.getEntryKey())) {
                return "";
            }
            if (Intrinsics.areEqual(key, PlatFormOption.BLANK.getEntryKey())) {
                return Pinyin.SPACE;
            }
            if (Intrinsics.areEqual(key, PlatFormOption.ONE.getEntryKey())) {
                return "1";
            }
            if (Intrinsics.areEqual(key, PlatFormOption.TWO.getEntryKey())) {
                return "2";
            }
            if (Intrinsics.areEqual(key, PlatFormOption.THREE.getEntryKey())) {
                return "3";
            }
            if (Intrinsics.areEqual(key, PlatFormOption.FOUR.getEntryKey())) {
                return "4";
            }
            if (Intrinsics.areEqual(key, PlatFormOption.FIVE.getEntryKey())) {
                return "5";
            }
            throw new Exception("Unknown Key for Platform : " + key);
        }
    }
}
