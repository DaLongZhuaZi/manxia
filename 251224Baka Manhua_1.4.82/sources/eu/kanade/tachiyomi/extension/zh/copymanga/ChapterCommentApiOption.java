package eu.kanade.tachiyomi.extension.zh.copymanga;

import java.util.ArrayList;
import java.util.Iterator;
import java.util.List;
import kotlin.Metadata;
import kotlin.collections.CollectionsKt;

/* JADX INFO: compiled from: Constants.kt */
/* JADX INFO: loaded from: classes.dex */
@Metadata(d1 = {"\u0000&\n\u0002\u0018\u0002\n\u0002\u0010\u0000\n\u0002\b\u0002\n\u0002\u0010\u000e\n\u0002\b\u0003\n\u0002\u0010\u0011\n\u0002\b\b\n\u0002\u0010 \n\u0002\u0018\u0002\n\u0000\bÆ\u0002\u0018\u00002\u00020\u0001B\u0007\b\u0002¢\u0006\u0002\u0010\u0002R\u0011\u0010\u0003\u001a\u00020\u0004¢\u0006\b\n\u0000\u001a\u0004\b\u0005\u0010\u0006R\u0019\u0010\u0007\u001a\b\u0012\u0004\u0012\u00020\u00040\b¢\u0006\n\n\u0002\u0010\u000b\u001a\u0004\b\t\u0010\nR\u0019\u0010\f\u001a\b\u0012\u0004\u0012\u00020\u00040\b¢\u0006\n\n\u0002\u0010\u000b\u001a\u0004\b\r\u0010\nR\u000e\u0010\u000e\u001a\u00020\u0004X\u0086T¢\u0006\u0002\n\u0000R\u000e\u0010\u000f\u001a\u00020\u0004X\u0086T¢\u0006\u0002\n\u0000R\u0014\u0010\u0010\u001a\b\u0012\u0004\u0012\u00020\u00120\u0011X\u0082\u0004¢\u0006\u0002\n\u0000¨\u0006\u0013"}, d2 = {"Leu/kanade/tachiyomi/extension/zh/copymanga/ChapterCommentApiOption;", "", "()V", "DEFAULT", "", "getDEFAULT", "()Ljava/lang/String;", "ENTRIES", "", "getENTRIES", "()[Ljava/lang/String;", "[Ljava/lang/String;", "ENTRY_KEYS", "getENTRY_KEYS", "KEY", "KEY_CUSTOM", "options", "", "Leu/kanade/tachiyomi/extension/zh/copymanga/ApiDomainOption;", "tachiyomi-zh.copymanga-v1.4.82_release"}, k = 1, mv = {1, 7, 1}, xi = 48)
public final class ChapterCommentApiOption {
    private static final String DEFAULT;
    private static final String[] ENTRIES;
    private static final String[] ENTRY_KEYS;
    public static final ChapterCommentApiOption INSTANCE = new ChapterCommentApiOption();
    public static final String KEY = "v2.pref.chapter_comment_api_domain";
    public static final String KEY_CUSTOM = "v2.pref.chapter_comment_api_domain_custom";
    private static final List<ApiDomainOption> options;

    private ChapterCommentApiOption() {
    }

    static {
        ApiDomainOption[] apiDomainOptionArrValues = ApiDomainOption.values();
        ArrayList arrayList = new ArrayList();
        for (ApiDomainOption apiDomainOption : apiDomainOptionArrValues) {
            if (!ApiDomainOption.INSTANCE.isHotManga(apiDomainOption.getEntryKey())) {
                arrayList.add(apiDomainOption);
            }
        }
        ArrayList arrayList2 = arrayList;
        options = arrayList2;
        ArrayList<ApiDomainOption> arrayList3 = arrayList2;
        ArrayList arrayList4 = new ArrayList(CollectionsKt.collectionSizeOrDefault(arrayList3, 10));
        for (ApiDomainOption apiDomainOption2 : arrayList3) {
            arrayList4.add(apiDomainOption2.getEntry() + '(' + apiDomainOption2.getDescription() + ')');
        }
        ENTRIES = (String[]) arrayList4.toArray(new String[0]);
        List<ApiDomainOption> list = options;
        ArrayList arrayList5 = new ArrayList(CollectionsKt.collectionSizeOrDefault(list, 10));
        Iterator<T> it = list.iterator();
        while (it.hasNext()) {
            arrayList5.add(((ApiDomainOption) it.next()).getEntryKey());
        }
        ENTRY_KEYS = (String[]) arrayList5.toArray(new String[0]);
        DEFAULT = ApiDomainOption.INSTANCE.getDEFAULT();
    }

    public final String[] getENTRIES() {
        return ENTRIES;
    }

    public final String[] getENTRY_KEYS() {
        return ENTRY_KEYS;
    }

    public final String getDEFAULT() {
        return DEFAULT;
    }
}
