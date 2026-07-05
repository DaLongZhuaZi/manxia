package eu.kanade.tachiyomi.extension.zh.copymanga;

import java.util.ArrayList;
import kotlin.Metadata;
import kotlin.jvm.internal.DefaultConstructorMarker;
import kotlin.jvm.internal.Intrinsics;

/* JADX WARN: Enum visitor error
jadx.core.utils.exceptions.JadxRuntimeException: Can't remove SSA var: r0v0 eu.kanade.tachiyomi.extension.zh.copymanga.ChapterCommentPerformOption, still in use, count: 1, list:
  (r0v0 eu.kanade.tachiyomi.extension.zh.copymanga.ChapterCommentPerformOption) from 0x002a: IGET (r0v0 eu.kanade.tachiyomi.extension.zh.copymanga.ChapterCommentPerformOption) A[WRAPPED] (LINE:285) eu.kanade.tachiyomi.extension.zh.copymanga.ChapterCommentPerformOption.entryKey java.lang.String
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
@Metadata(d1 = {"\u0000\u0012\n\u0002\u0018\u0002\n\u0002\u0010\u0010\n\u0000\n\u0002\u0010\u000e\n\u0002\b\t\b\u0086\u0001\u0018\u0000 \u000b2\b\u0012\u0004\u0012\u00020\u00000\u0001:\u0001\u000bB\u0017\b\u0002\u0012\u0006\u0010\u0002\u001a\u00020\u0003\u0012\u0006\u0010\u0004\u001a\u00020\u0003¢\u0006\u0002\u0010\u0005R\u0011\u0010\u0002\u001a\u00020\u0003¢\u0006\b\n\u0000\u001a\u0004\b\u0006\u0010\u0007R\u0011\u0010\u0004\u001a\u00020\u0003¢\u0006\b\n\u0000\u001a\u0004\b\b\u0010\u0007j\u0002\b\tj\u0002\b\n¨\u0006\f"}, d2 = {"Leu/kanade/tachiyomi/extension/zh/copymanga/ChapterCommentPerformOption;", "", "entry", "", "entryKey", "(Ljava/lang/String;ILjava/lang/String;Ljava/lang/String;)V", "getEntry", "()Ljava/lang/String;", "getEntryKey", "SEPARATE", "MERGE", "Companion", "tachiyomi-zh.copymanga-v1.4.82_release"}, k = 1, mv = {1, 7, 1}, xi = 48)
public final class ChapterCommentPerformOption {
    SEPARATE("分页 (适合手机)", "chapter_comment.separate"),
    MERGE("合併 (适合平板)", "chapter_comment.merge");

    private static final String DEFAULT = new ChapterCommentPerformOption("分页 (适合手机)", "chapter_comment.separate").entryKey;
    private static final String[] ENTRIES;
    private static final String[] ENTRY_KEYS;
    public static final String KEY = "v2.pref.chapter_comment_perform";
    private final String entry;
    private final String entryKey;

    /* JADX INFO: renamed from: Companion, reason: from kotlin metadata */
    public static final Companion INSTANCE = new Companion(null);

    public static ChapterCommentPerformOption valueOf(String str) {
        return (ChapterCommentPerformOption) Enum.valueOf(ChapterCommentPerformOption.class, str);
    }

    public static ChapterCommentPerformOption[] values() {
        return (ChapterCommentPerformOption[]) $VALUES.clone();
    }

    private ChapterCommentPerformOption(String str, String str2) {
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
        ChapterCommentPerformOption[] chapterCommentPerformOptionArrValues = values();
        ArrayList arrayList = new ArrayList(chapterCommentPerformOptionArrValues.length);
        for (ChapterCommentPerformOption chapterCommentPerformOption : chapterCommentPerformOptionArrValues) {
            arrayList.add(chapterCommentPerformOption.entry);
        }
        ENTRIES = (String[]) arrayList.toArray(new String[0]);
        ChapterCommentPerformOption[] chapterCommentPerformOptionArrValues2 = values();
        ArrayList arrayList2 = new ArrayList(chapterCommentPerformOptionArrValues2.length);
        for (ChapterCommentPerformOption chapterCommentPerformOption2 : chapterCommentPerformOptionArrValues2) {
            arrayList2.add(chapterCommentPerformOption2.entryKey);
        }
        ENTRY_KEYS = (String[]) arrayList2.toArray(new String[0]);
    }

    /* JADX INFO: compiled from: Constants.kt */
    @Metadata(d1 = {"\u0000$\n\u0002\u0018\u0002\n\u0002\u0010\u0000\n\u0002\b\u0002\n\u0002\u0010\u000e\n\u0002\b\u0003\n\u0002\u0010\u0011\n\u0002\b\u0007\n\u0002\u0018\u0002\n\u0002\b\u0002\b\u0086\u0003\u0018\u00002\u00020\u0001B\u0007\b\u0002¢\u0006\u0002\u0010\u0002J\u000e\u0010\u000f\u001a\u00020\u00102\u0006\u0010\u0011\u001a\u00020\u0004R\u0011\u0010\u0003\u001a\u00020\u0004¢\u0006\b\n\u0000\u001a\u0004\b\u0005\u0010\u0006R\u0019\u0010\u0007\u001a\b\u0012\u0004\u0012\u00020\u00040\b¢\u0006\n\n\u0002\u0010\u000b\u001a\u0004\b\t\u0010\nR\u0019\u0010\f\u001a\b\u0012\u0004\u0012\u00020\u00040\b¢\u0006\n\n\u0002\u0010\u000b\u001a\u0004\b\r\u0010\nR\u000e\u0010\u000e\u001a\u00020\u0004X\u0086T¢\u0006\u0002\n\u0000¨\u0006\u0012"}, d2 = {"Leu/kanade/tachiyomi/extension/zh/copymanga/ChapterCommentPerformOption$Companion;", "", "()V", "DEFAULT", "", "getDEFAULT", "()Ljava/lang/String;", "ENTRIES", "", "getENTRIES", "()[Ljava/lang/String;", "[Ljava/lang/String;", "ENTRY_KEYS", "getENTRY_KEYS", "KEY", "key2mode", "Leu/kanade/tachiyomi/extension/zh/copymanga/ChapterCommentPerformOption;", "key", "tachiyomi-zh.copymanga-v1.4.82_release"}, k = 1, mv = {1, 7, 1}, xi = 48)
    public static final class Companion {
        public /* synthetic */ Companion(DefaultConstructorMarker defaultConstructorMarker) {
            this();
        }

        private Companion() {
        }

        public final String getDEFAULT() {
            return ChapterCommentPerformOption.DEFAULT;
        }

        public final String[] getENTRIES() {
            return ChapterCommentPerformOption.ENTRIES;
        }

        public final String[] getENTRY_KEYS() {
            return ChapterCommentPerformOption.ENTRY_KEYS;
        }

        public final ChapterCommentPerformOption key2mode(String key) throws Exception {
            ChapterCommentPerformOption chapterCommentPerformOption;
            Intrinsics.checkNotNullParameter(key, "key");
            ChapterCommentPerformOption[] chapterCommentPerformOptionArrValues = ChapterCommentPerformOption.values();
            int length = chapterCommentPerformOptionArrValues.length;
            int i = 0;
            while (true) {
                if (i >= length) {
                    chapterCommentPerformOption = null;
                    break;
                }
                chapterCommentPerformOption = chapterCommentPerformOptionArrValues[i];
                if (Intrinsics.areEqual(chapterCommentPerformOption.getEntryKey(), key)) {
                    break;
                }
                i++;
            }
            if (chapterCommentPerformOption != null) {
                return chapterCommentPerformOption;
            }
            throw new Exception("Unknown Key for ChapterCommentPerformOption : " + key);
        }
    }
}
