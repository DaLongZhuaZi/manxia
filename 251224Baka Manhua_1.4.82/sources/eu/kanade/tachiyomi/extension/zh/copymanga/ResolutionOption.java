package eu.kanade.tachiyomi.extension.zh.copymanga;

import java.util.ArrayList;
import kotlin.Metadata;
import kotlin.jvm.internal.DefaultConstructorMarker;
import kotlin.jvm.internal.Intrinsics;
import kotlin.text.Regex;

/* JADX WARN: Enum visitor error
jadx.core.utils.exceptions.JadxRuntimeException: Can't remove SSA var: r0v2 eu.kanade.tachiyomi.extension.zh.copymanga.ResolutionOption, still in use, count: 1, list:
  (r0v2 eu.kanade.tachiyomi.extension.zh.copymanga.ResolutionOption) from 0x0038: IGET (r0v2 eu.kanade.tachiyomi.extension.zh.copymanga.ResolutionOption) A[WRAPPED] (LINE:254) eu.kanade.tachiyomi.extension.zh.copymanga.ResolutionOption.entryKey java.lang.String
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
/* JADX INFO: compiled from: Constants.kt */
/* JADX INFO: loaded from: classes.dex */
@Metadata(d1 = {"\u0000\u0012\n\u0002\u0018\u0002\n\u0002\u0010\u0010\n\u0000\n\u0002\u0010\u000e\n\u0002\b\n\b\u0086\u0001\u0018\u0000 \f2\b\u0012\u0004\u0012\u00020\u00000\u0001:\u0001\fB\u0017\b\u0002\u0012\u0006\u0010\u0002\u001a\u00020\u0003\u0012\u0006\u0010\u0004\u001a\u00020\u0003¢\u0006\u0002\u0010\u0005R\u0011\u0010\u0002\u001a\u00020\u0003¢\u0006\b\n\u0000\u001a\u0004\b\u0006\u0010\u0007R\u0011\u0010\u0004\u001a\u00020\u0003¢\u0006\b\n\u0000\u001a\u0004\b\b\u0010\u0007j\u0002\b\tj\u0002\b\nj\u0002\b\u000b¨\u0006\r"}, d2 = {"Leu/kanade/tachiyomi/extension/zh/copymanga/ResolutionOption;", "", "entry", "", "entryKey", "(Ljava/lang/String;ILjava/lang/String;Ljava/lang/String;)V", "getEntry", "()Ljava/lang/String;", "getEntryKey", "PIXEL800", "PIXEL1200", "PIXEL1500", "Companion", "tachiyomi-zh.copymanga-v1.4.82_release"}, k = 1, mv = {1, 7, 1}, xi = 48)
public final class ResolutionOption {
    PIXEL800("800", "resolution.r800"),
    PIXEL1200("1200", "resolution.r1200"),
    PIXEL1500("1500", "resolution.r1500");

    private static final Regex CHAPTER_IMAGE_RESOLUTION_REGEX;
    private static final String DEFAULT = new ResolutionOption("1500", "resolution.r1500").entryKey;
    private static final String[] ENTRIES;
    private static final String[] ENTRY_KEYS;
    public static final String KEY = "v2.pref.resolution";
    public static final String SUMMERY = "%s\n阅读过的部分需要清空缓存才生效";
    private final String entry;
    private final String entryKey;

    /* JADX INFO: renamed from: Companion, reason: from kotlin metadata */
    public static final Companion INSTANCE = new Companion(null);

    public static ResolutionOption valueOf(String str) {
        return (ResolutionOption) Enum.valueOf(ResolutionOption.class, str);
    }

    public static ResolutionOption[] values() {
        return (ResolutionOption[]) $VALUES.clone();
    }

    private ResolutionOption(String str, String str2) {
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
        ResolutionOption[] resolutionOptionArrValues = values();
        ArrayList arrayList = new ArrayList(resolutionOptionArrValues.length);
        for (ResolutionOption resolutionOption : resolutionOptionArrValues) {
            arrayList.add(resolutionOption.entry);
        }
        ENTRIES = (String[]) arrayList.toArray(new String[0]);
        ResolutionOption[] resolutionOptionArrValues2 = values();
        ArrayList arrayList2 = new ArrayList(resolutionOptionArrValues2.length);
        for (ResolutionOption resolutionOption2 : resolutionOptionArrValues2) {
            arrayList2.add(resolutionOption2.entryKey);
        }
        ENTRY_KEYS = (String[]) arrayList2.toArray(new String[0]);
        CHAPTER_IMAGE_RESOLUTION_REGEX = new Regex("\\d+(?=x\\.(?:jpg|webp)$)");
    }

    /* JADX INFO: compiled from: Constants.kt */
    @Metadata(d1 = {"\u0000\"\n\u0002\u0018\u0002\n\u0002\u0010\u0000\n\u0002\b\u0002\n\u0002\u0018\u0002\n\u0000\n\u0002\u0010\u000e\n\u0002\b\u0003\n\u0002\u0010\u0011\n\u0002\b\r\b\u0086\u0003\u0018\u00002\u00020\u0001B\u0007\b\u0002¢\u0006\u0002\u0010\u0002J\u000e\u0010\u0012\u001a\u00020\u00062\u0006\u0010\u0013\u001a\u00020\u0006J\u0016\u0010\u0014\u001a\u00020\u00062\u0006\u0010\u0015\u001a\u00020\u00062\u0006\u0010\u0016\u001a\u00020\u0006R\u000e\u0010\u0003\u001a\u00020\u0004X\u0082\u0004¢\u0006\u0002\n\u0000R\u0011\u0010\u0005\u001a\u00020\u0006¢\u0006\b\n\u0000\u001a\u0004\b\u0007\u0010\bR\u0019\u0010\t\u001a\b\u0012\u0004\u0012\u00020\u00060\n¢\u0006\n\n\u0002\u0010\r\u001a\u0004\b\u000b\u0010\fR\u0019\u0010\u000e\u001a\b\u0012\u0004\u0012\u00020\u00060\n¢\u0006\n\n\u0002\u0010\r\u001a\u0004\b\u000f\u0010\fR\u000e\u0010\u0010\u001a\u00020\u0006X\u0086T¢\u0006\u0002\n\u0000R\u000e\u0010\u0011\u001a\u00020\u0006X\u0086T¢\u0006\u0002\n\u0000¨\u0006\u0017"}, d2 = {"Leu/kanade/tachiyomi/extension/zh/copymanga/ResolutionOption$Companion;", "", "()V", "CHAPTER_IMAGE_RESOLUTION_REGEX", "Lkotlin/text/Regex;", "DEFAULT", "", "getDEFAULT", "()Ljava/lang/String;", "ENTRIES", "", "getENTRIES", "()[Ljava/lang/String;", "[Ljava/lang/String;", "ENTRY_KEYS", "getENTRY_KEYS", "KEY", "SUMMERY", "key2value", "key", "translate", "imageUrl", "resolution", "tachiyomi-zh.copymanga-v1.4.82_release"}, k = 1, mv = {1, 7, 1}, xi = 48)
    public static final class Companion {
        public /* synthetic */ Companion(DefaultConstructorMarker defaultConstructorMarker) {
            this();
        }

        private Companion() {
        }

        public final String getDEFAULT() {
            return ResolutionOption.DEFAULT;
        }

        public final String[] getENTRIES() {
            return ResolutionOption.ENTRIES;
        }

        public final String[] getENTRY_KEYS() {
            return ResolutionOption.ENTRY_KEYS;
        }

        public final String translate(String imageUrl, String resolution) {
            Intrinsics.checkNotNullParameter(imageUrl, "imageUrl");
            Intrinsics.checkNotNullParameter(resolution, "resolution");
            return ResolutionOption.CHAPTER_IMAGE_RESOLUTION_REGEX.replaceFirst(imageUrl, resolution);
        }

        public final String key2value(String key) throws Exception {
            Intrinsics.checkNotNullParameter(key, "key");
            if (Intrinsics.areEqual(key, ResolutionOption.PIXEL800.getEntryKey())) {
                return "800";
            }
            if (Intrinsics.areEqual(key, ResolutionOption.PIXEL1200.getEntryKey())) {
                return "1200";
            }
            if (Intrinsics.areEqual(key, ResolutionOption.PIXEL1500.getEntryKey())) {
                return "1500";
            }
            throw new Exception("Unknown Key for ResolutionOption : " + key);
        }
    }
}
