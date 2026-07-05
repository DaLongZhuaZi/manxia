package eu.kanade.tachiyomi.extension.zh.copymanga;

import eu.kanade.tachiyomi.extension.zh.copymanga.api.ApiRepo;
import java.util.ArrayList;
import java.util.Collection;
import java.util.Iterator;
import kotlin.Metadata;
import kotlin.collections.CollectionsKt;
import kotlin.jvm.internal.DefaultConstructorMarker;
import kotlin.jvm.internal.Intrinsics;
import kotlin.text.StringsKt;
import okhttp3.Headers;

/* JADX INFO: compiled from: Constants.kt */
/* JADX INFO: loaded from: classes.dex */
@Metadata(d1 = {"\u0000\u001a\n\u0002\u0018\u0002\n\u0002\u0010\u0010\n\u0000\n\u0002\u0010\u000e\n\u0002\b\u0003\n\u0002\u0018\u0002\n\u0002\b\u0017\b\u0086\u0001\u0018\u0000 \u001d2\b\u0012\u0004\u0012\u00020\u00000\u0001:\u0001\u001dB'\b\u0002\u0012\u0006\u0010\u0002\u001a\u00020\u0003\u0012\u0006\u0010\u0004\u001a\u00020\u0003\u0012\u0006\u0010\u0005\u001a\u00020\u0003\u0012\u0006\u0010\u0006\u001a\u00020\u0007¢\u0006\u0002\u0010\bR\u0011\u0010\u0005\u001a\u00020\u0003¢\u0006\b\n\u0000\u001a\u0004\b\t\u0010\nR\u0011\u0010\u0002\u001a\u00020\u0003¢\u0006\b\n\u0000\u001a\u0004\b\u000b\u0010\nR\u0011\u0010\u0004\u001a\u00020\u0003¢\u0006\b\n\u0000\u001a\u0004\b\f\u0010\nR\u0011\u0010\u0006\u001a\u00020\u0007¢\u0006\b\n\u0000\u001a\u0004\b\r\u0010\u000ej\u0002\b\u000fj\u0002\b\u0010j\u0002\b\u0011j\u0002\b\u0012j\u0002\b\u0013j\u0002\b\u0014j\u0002\b\u0015j\u0002\b\u0016j\u0002\b\u0017j\u0002\b\u0018j\u0002\b\u0019j\u0002\b\u001aj\u0002\b\u001bj\u0002\b\u001c¨\u0006\u001e"}, d2 = {"Leu/kanade/tachiyomi/extension/zh/copymanga/ApiDomainOption;", "", "entry", "", "entryKey", "description", "headers", "Lokhttp3/Headers;", "(Ljava/lang/String;ILjava/lang/String;Ljava/lang/String;Ljava/lang/String;Lokhttp3/Headers;)V", "getDescription", "()Ljava/lang/String;", "getEntry", "getEntryKey", "getHeaders", "()Lokhttp3/Headers;", "COPY1", "COPY3", "COPY4", "COPY5", "COPY6", "COPY7", "HOTMANGA", "HOTMANGA2", "HOTMANGA3", "HOTMANGA4", "HOTMANGA5", "HOTMANGA6", "HOTMANGA7", "CUSTOM", "Companion", "tachiyomi-zh.copymanga-v1.4.82_release"}, k = 1, mv = {1, 7, 1}, xi = 48)
public enum ApiDomainOption {
    COPY1("api.mangacopy.com", "api.mangacopy.com", "國際服", ApiRepo.INSTANCE.getCOPY_MANGA_HEADER()),
    COPY3("mapi.copy20.com", "mapi.copy20.com", "大陸專線1", ApiRepo.INSTANCE.getCOPY_MANGA_HEADER()),
    COPY4("mapi.copy2000.site", "mapi.copy2000.site", "大陸專線2", ApiRepo.INSTANCE.getCOPY_MANGA_HEADER()),
    COPY5("api.2025copy.com", "api.2025copy.com", "大陸專線3", ApiRepo.INSTANCE.getCOPY_MANGA_HEADER()),
    COPY6("api.2026copy.com", "api.2026copy.com", "大陸專線4", ApiRepo.INSTANCE.getCOPY_MANGA_HEADER()),
    COPY7("api.copy3000.com", "api.copy3000.com", "大陸專線 拷貝新站", ApiRepo.INSTANCE.getCOPY_MANGA_HEADER()),
    HOTMANGA("mapi.hotmangasd.com", "mapi.hotmangasd.com", "熱辣漫畫", ApiRepo.INSTANCE.getHOT_MANGA_HEADER()),
    HOTMANGA2("api.manga2025.com", "api.manga2025.com", "熱辣漫畫 線路2", ApiRepo.INSTANCE.getHOT_MANGA_HEADER()),
    HOTMANGA3("mapi.hotmangasf.com", "mapi.hotmangasf.com", "熱辣漫畫 線路3", ApiRepo.INSTANCE.getHOT_MANGA_HEADER()),
    HOTMANGA4("mapi.hotmangasg.com", "mapi.hotmangasg.com", "熱辣漫畫 線路4", ApiRepo.INSTANCE.getHOT_MANGA_HEADER()),
    HOTMANGA5("mapi.elfgjfghkk.club", "mapi.elfgjfghkk.club", "熱辣漫畫 線路5", ApiRepo.INSTANCE.getHOT_MANGA_HEADER()),
    HOTMANGA6("mapi.fgjfghkk.club", "mapi.fgjfghkk.club", "熱辣漫畫 線路6", ApiRepo.INSTANCE.getHOT_MANGA_HEADER()),
    HOTMANGA7("mapi.fgjfghkkcenter.club", "mapi.fgjfghkkcenter.club", "熱辣漫畫 線路7", ApiRepo.INSTANCE.getHOT_MANGA_HEADER()),
    CUSTOM("custom", "custom", "自訂義", ApiRepo.INSTANCE.getCOPY_MANGA_HEADER());


    /* JADX INFO: renamed from: Companion, reason: from kotlin metadata */
    public static final Companion INSTANCE = new Companion(null);
    private static final String DEFAULT;
    private static final String[] ENTRIES;
    private static final String[] ENTRY_KEYS;
    public static final String KEY = "v2.pref.api_domain";
    public static final String KEY_CUSTOM = "v2.pref.api_domain_custom";
    private final String description;
    private final String entry;
    private final String entryKey;
    private final Headers headers;

    ApiDomainOption(String str, String str2, String str3, Headers headers) {
        this.entry = str;
        this.entryKey = str2;
        this.description = str3;
        this.headers = headers;
    }

    public final String getDescription() {
        return this.description;
    }

    public final String getEntry() {
        return this.entry;
    }

    public final String getEntryKey() {
        return this.entryKey;
    }

    public final Headers getHeaders() {
        return this.headers;
    }

    static {
        ApiDomainOption[] apiDomainOptionArrValues = values();
        ArrayList arrayList = new ArrayList(apiDomainOptionArrValues.length);
        for (ApiDomainOption apiDomainOption : apiDomainOptionArrValues) {
            arrayList.add(apiDomainOption.entry + '(' + apiDomainOption.description + ')');
        }
        ENTRIES = (String[]) arrayList.toArray(new String[0]);
        ApiDomainOption[] apiDomainOptionArrValues2 = values();
        ArrayList arrayList2 = new ArrayList(apiDomainOptionArrValues2.length);
        for (ApiDomainOption apiDomainOption2 : apiDomainOptionArrValues2) {
            arrayList2.add(apiDomainOption2.entryKey);
        }
        ENTRY_KEYS = (String[]) arrayList2.toArray(new String[0]);
        DEFAULT = COPY7.entryKey;
    }

    /* JADX INFO: compiled from: Constants.kt */
    @Metadata(d1 = {"\u0000,\n\u0002\u0018\u0002\n\u0002\u0010\u0000\n\u0002\b\u0002\n\u0002\u0010\u000e\n\u0002\b\u0003\n\u0002\u0010\u0011\n\u0002\b\b\n\u0002\u0018\u0002\n\u0002\b\u0002\n\u0002\u0010\u000b\n\u0002\b\u0005\b\u0086\u0003\u0018\u00002\u00020\u0001B\u0007\b\u0002¢\u0006\u0002\u0010\u0002J\u000e\u0010\u0010\u001a\u00020\u00112\u0006\u0010\u0012\u001a\u00020\u0004J\u000e\u0010\u0013\u001a\u00020\u00142\u0006\u0010\u0015\u001a\u00020\u0004J\u000e\u0010\u0016\u001a\u00020\u00142\u0006\u0010\u0015\u001a\u00020\u0004J\u0016\u0010\u0017\u001a\u00020\u00042\u0006\u0010\u0015\u001a\u00020\u00042\u0006\u0010\u0018\u001a\u00020\u0004R\u0011\u0010\u0003\u001a\u00020\u0004¢\u0006\b\n\u0000\u001a\u0004\b\u0005\u0010\u0006R\u0019\u0010\u0007\u001a\b\u0012\u0004\u0012\u00020\u00040\b¢\u0006\n\n\u0002\u0010\u000b\u001a\u0004\b\t\u0010\nR\u0019\u0010\f\u001a\b\u0012\u0004\u0012\u00020\u00040\b¢\u0006\n\n\u0002\u0010\u000b\u001a\u0004\b\r\u0010\nR\u000e\u0010\u000e\u001a\u00020\u0004X\u0086T¢\u0006\u0002\n\u0000R\u000e\u0010\u000f\u001a\u00020\u0004X\u0086T¢\u0006\u0002\n\u0000¨\u0006\u0019"}, d2 = {"Leu/kanade/tachiyomi/extension/zh/copymanga/ApiDomainOption$Companion;", "", "()V", "DEFAULT", "", "getDEFAULT", "()Ljava/lang/String;", "ENTRIES", "", "getENTRIES", "()[Ljava/lang/String;", "[Ljava/lang/String;", "ENTRY_KEYS", "getENTRY_KEYS", "KEY", "KEY_CUSTOM", "getOptionByHttp", "Leu/kanade/tachiyomi/extension/zh/copymanga/ApiDomainOption;", "url", "isCopyManga", "", "key", "isHotManga", "toHttpsUrl", "custom", "tachiyomi-zh.copymanga-v1.4.82_release"}, k = 1, mv = {1, 7, 1}, xi = 48)
    public static final class Companion {
        public /* synthetic */ Companion(DefaultConstructorMarker defaultConstructorMarker) {
            this();
        }

        private Companion() {
        }

        public final String[] getENTRIES() {
            return ApiDomainOption.ENTRIES;
        }

        public final String[] getENTRY_KEYS() {
            return ApiDomainOption.ENTRY_KEYS;
        }

        public final String getDEFAULT() {
            return ApiDomainOption.DEFAULT;
        }

        public final ApiDomainOption getOptionByHttp(String url) {
            ApiDomainOption apiDomainOption;
            Intrinsics.checkNotNullParameter(url, "url");
            ApiDomainOption[] apiDomainOptionArrValues = ApiDomainOption.values();
            int length = apiDomainOptionArrValues.length;
            int i = 0;
            while (true) {
                apiDomainOption = null;
                if (i >= length) {
                    break;
                }
                ApiDomainOption apiDomainOption2 = apiDomainOptionArrValues[i];
                if (StringsKt.contains$default(url, apiDomainOption2.getEntry(), false, 2, (Object) null)) {
                    apiDomainOption = apiDomainOption2;
                    break;
                }
                i++;
            }
            return apiDomainOption == null ? ApiDomainOption.CUSTOM : apiDomainOption;
        }

        public final boolean isHotManga(String key) {
            Intrinsics.checkNotNullParameter(key, "key");
            ApiDomainOption[] apiDomainOptionArrValues = ApiDomainOption.values();
            ArrayList arrayList = new ArrayList();
            for (ApiDomainOption apiDomainOption : apiDomainOptionArrValues) {
                if (StringsKt.contains$default(apiDomainOption.name(), "HOTMANGA", false, 2, (Object) null)) {
                    arrayList.add(apiDomainOption);
                }
            }
            ArrayList arrayList2 = arrayList;
            ArrayList arrayList3 = new ArrayList(CollectionsKt.collectionSizeOrDefault(arrayList2, 10));
            Iterator it = arrayList2.iterator();
            while (it.hasNext()) {
                arrayList3.add(((ApiDomainOption) it.next()).getEntryKey());
            }
            ArrayList arrayList4 = arrayList3;
            if ((arrayList4 instanceof Collection) && arrayList4.isEmpty()) {
                return false;
            }
            Iterator it2 = arrayList4.iterator();
            while (it2.hasNext()) {
                if (StringsKt.contains$default(key, (String) it2.next(), false, 2, (Object) null)) {
                    return true;
                }
            }
            return false;
        }

        public final boolean isCopyManga(String key) {
            Intrinsics.checkNotNullParameter(key, "key");
            ApiDomainOption[] apiDomainOptionArrValues = ApiDomainOption.values();
            ArrayList arrayList = new ArrayList();
            for (ApiDomainOption apiDomainOption : apiDomainOptionArrValues) {
                if (StringsKt.contains$default(apiDomainOption.name(), "COPY", false, 2, (Object) null)) {
                    arrayList.add(apiDomainOption);
                }
            }
            ArrayList arrayList2 = arrayList;
            ArrayList arrayList3 = new ArrayList(CollectionsKt.collectionSizeOrDefault(arrayList2, 10));
            Iterator it = arrayList2.iterator();
            while (it.hasNext()) {
                arrayList3.add(((ApiDomainOption) it.next()).getEntryKey());
            }
            ArrayList arrayList4 = arrayList3;
            if ((arrayList4 instanceof Collection) && arrayList4.isEmpty()) {
                return false;
            }
            Iterator it2 = arrayList4.iterator();
            while (it2.hasNext()) {
                if (StringsKt.contains$default(key, (String) it2.next(), false, 2, (Object) null)) {
                    return true;
                }
            }
            return false;
        }

        public final String toHttpsUrl(String key, String custom) {
            Intrinsics.checkNotNullParameter(key, "key");
            Intrinsics.checkNotNullParameter(custom, "custom");
            if (Intrinsics.areEqual(key, ApiDomainOption.CUSTOM.getEntryKey())) {
                key = custom;
            }
            if (StringsKt.startsWith$default(key, "https://", false, 2, (Object) null) || StringsKt.startsWith$default(key, "http://", false, 2, (Object) null)) {
                return key;
            }
            return "https://" + key;
        }
    }
}
