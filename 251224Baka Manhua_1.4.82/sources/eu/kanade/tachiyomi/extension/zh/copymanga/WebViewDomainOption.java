package eu.kanade.tachiyomi.extension.zh.copymanga;

import java.util.ArrayList;
import java.util.Collection;
import java.util.Iterator;
import kotlin.Metadata;
import kotlin.collections.CollectionsKt;
import kotlin.jvm.internal.DefaultConstructorMarker;
import kotlin.jvm.internal.Intrinsics;
import kotlin.text.StringsKt;

/* JADX INFO: compiled from: Constants.kt */
/* JADX INFO: loaded from: classes.dex */
@Metadata(d1 = {"\u0000\u0012\n\u0002\u0018\u0002\n\u0002\u0010\u0010\n\u0000\n\u0002\u0010\u000e\n\u0002\b\u0011\b\u0086\u0001\u0018\u0000 \u00132\b\u0012\u0004\u0012\u00020\u00000\u0001:\u0001\u0013B\u001f\b\u0002\u0012\u0006\u0010\u0002\u001a\u00020\u0003\u0012\u0006\u0010\u0004\u001a\u00020\u0003\u0012\u0006\u0010\u0005\u001a\u00020\u0003¢\u0006\u0002\u0010\u0006R\u0011\u0010\u0005\u001a\u00020\u0003¢\u0006\b\n\u0000\u001a\u0004\b\u0007\u0010\bR\u0011\u0010\u0002\u001a\u00020\u0003¢\u0006\b\n\u0000\u001a\u0004\b\t\u0010\bR\u0011\u0010\u0004\u001a\u00020\u0003¢\u0006\b\n\u0000\u001a\u0004\b\n\u0010\bj\u0002\b\u000bj\u0002\b\fj\u0002\b\rj\u0002\b\u000ej\u0002\b\u000fj\u0002\b\u0010j\u0002\b\u0011j\u0002\b\u0012¨\u0006\u0014"}, d2 = {"Leu/kanade/tachiyomi/extension/zh/copymanga/WebViewDomainOption;", "", "entry", "", "entryKey", "description", "(Ljava/lang/String;ILjava/lang/String;Ljava/lang/String;Ljava/lang/String;)V", "getDescription", "()Ljava/lang/String;", "getEntry", "getEntryKey", "COPY1", "COPY2", "COPY3", "COPY4", "COPY5", "HOTMANGA_MOBILE", "HOTMANGA_DESKTOP", "CUSTOM", "Companion", "tachiyomi-zh.copymanga-v1.4.82_release"}, k = 1, mv = {1, 7, 1}, xi = 48)
public enum WebViewDomainOption {
    COPY1("www.mangacopy.com", "www.mangacopy.com", "國際服"),
    COPY2("www.copy20.com", "www.copy20.com", "大陸專線"),
    COPY3("www.2025copy.com", "www.2025copy.com", "大陸專線2"),
    COPY4("www.2026copy.com", "www.2026copy.com", "大陸專線3"),
    COPY5("www.copy3000.com", "www.copy3000.com", "大陸專線4"),
    HOTMANGA_MOBILE("m.manga2025.com", "m.manga2025.com", "熱辣漫畫 (移動端)"),
    HOTMANGA_DESKTOP("www.manga2025.com", "www.manga2025.com", "熱辣漫畫 (桌面端)"),
    CUSTOM("custom", "custom", "自訂義");


    /* JADX INFO: renamed from: Companion, reason: from kotlin metadata */
    public static final Companion INSTANCE = new Companion(null);
    private static final String DEFAULT;
    private static final String[] ENTRIES;
    private static final String[] ENTRY_KEYS;
    public static final String KEY = "v2.pref.web_view_link";
    public static final String KEY_CUSTOM = "v2.pref.web_view_link_custom";
    private final String description;
    private final String entry;
    private final String entryKey;

    WebViewDomainOption(String str, String str2, String str3) {
        this.entry = str;
        this.entryKey = str2;
        this.description = str3;
    }

    public final String getEntry() {
        return this.entry;
    }

    public final String getEntryKey() {
        return this.entryKey;
    }

    public final String getDescription() {
        return this.description;
    }

    static {
        WebViewDomainOption[] webViewDomainOptionArrValues = values();
        ArrayList arrayList = new ArrayList(webViewDomainOptionArrValues.length);
        for (WebViewDomainOption webViewDomainOption : webViewDomainOptionArrValues) {
            arrayList.add(webViewDomainOption.entry + '(' + webViewDomainOption.description + ')');
        }
        ENTRIES = (String[]) arrayList.toArray(new String[0]);
        WebViewDomainOption[] webViewDomainOptionArrValues2 = values();
        ArrayList arrayList2 = new ArrayList(webViewDomainOptionArrValues2.length);
        for (WebViewDomainOption webViewDomainOption2 : webViewDomainOptionArrValues2) {
            arrayList2.add(webViewDomainOption2.entryKey);
        }
        ENTRY_KEYS = (String[]) arrayList2.toArray(new String[0]);
        DEFAULT = COPY5.entryKey;
    }

    /* JADX INFO: compiled from: Constants.kt */
    @Metadata(d1 = {"\u0000,\n\u0002\u0018\u0002\n\u0002\u0010\u0000\n\u0002\b\u0002\n\u0002\u0010\u000e\n\u0002\b\u0003\n\u0002\u0010\u0011\n\u0002\b\b\n\u0002\u0010\u000b\n\u0002\b\u0005\n\u0002\u0018\u0002\n\u0002\b\u0005\b\u0086\u0003\u0018\u00002\u00020\u0001B\u0007\b\u0002¢\u0006\u0002\u0010\u0002J\u000e\u0010\u0010\u001a\u00020\u00112\u0006\u0010\u0012\u001a\u00020\u0004J\u001e\u0010\u0013\u001a\u00020\u00042\u0006\u0010\u0014\u001a\u00020\u00042\u0006\u0010\u0015\u001a\u00020\u00042\u0006\u0010\u0016\u001a\u00020\u0017J\u001e\u0010\u0018\u001a\u00020\u00042\u0006\u0010\u0014\u001a\u00020\u00042\u0006\u0010\u0019\u001a\u00020\u00042\u0006\u0010\u0016\u001a\u00020\u0017J\u0016\u0010\u001a\u001a\u00020\u00042\u0006\u0010\u0012\u001a\u00020\u00042\u0006\u0010\u001b\u001a\u00020\u0004R\u0011\u0010\u0003\u001a\u00020\u0004¢\u0006\b\n\u0000\u001a\u0004\b\u0005\u0010\u0006R\u0019\u0010\u0007\u001a\b\u0012\u0004\u0012\u00020\u00040\b¢\u0006\n\n\u0002\u0010\u000b\u001a\u0004\b\t\u0010\nR\u0019\u0010\f\u001a\b\u0012\u0004\u0012\u00020\u00040\b¢\u0006\n\n\u0002\u0010\u000b\u001a\u0004\b\r\u0010\nR\u000e\u0010\u000e\u001a\u00020\u0004X\u0086T¢\u0006\u0002\n\u0000R\u000e\u0010\u000f\u001a\u00020\u0004X\u0086T¢\u0006\u0002\n\u0000¨\u0006\u001c"}, d2 = {"Leu/kanade/tachiyomi/extension/zh/copymanga/WebViewDomainOption$Companion;", "", "()V", "DEFAULT", "", "getDEFAULT", "()Ljava/lang/String;", "ENTRIES", "", "getENTRIES", "()[Ljava/lang/String;", "[Ljava/lang/String;", "ENTRY_KEYS", "getENTRY_KEYS", "KEY", "KEY_CUSTOM", "isHotManga", "", "key", "toChapterUrl", "domainUrl", "chapterUrl", "webViewType", "Leu/kanade/tachiyomi/extension/zh/copymanga/WebViewClientOption;", "toComicUrl", "comicId", "toHttpsUrl", "custom", "tachiyomi-zh.copymanga-v1.4.82_release"}, k = 1, mv = {1, 7, 1}, xi = 48)
    public static final class Companion {
        public /* synthetic */ Companion(DefaultConstructorMarker defaultConstructorMarker) {
            this();
        }

        private Companion() {
        }

        public final String[] getENTRIES() {
            return WebViewDomainOption.ENTRIES;
        }

        public final String[] getENTRY_KEYS() {
            return WebViewDomainOption.ENTRY_KEYS;
        }

        public final String getDEFAULT() {
            return WebViewDomainOption.DEFAULT;
        }

        public final boolean isHotManga(String key) {
            Intrinsics.checkNotNullParameter(key, "key");
            WebViewDomainOption[] webViewDomainOptionArrValues = WebViewDomainOption.values();
            ArrayList arrayList = new ArrayList();
            for (WebViewDomainOption webViewDomainOption : webViewDomainOptionArrValues) {
                if (StringsKt.contains$default(webViewDomainOption.name(), "HOTMANGA", false, 2, (Object) null)) {
                    arrayList.add(webViewDomainOption);
                }
            }
            ArrayList arrayList2 = arrayList;
            ArrayList arrayList3 = new ArrayList(CollectionsKt.collectionSizeOrDefault(arrayList2, 10));
            Iterator it = arrayList2.iterator();
            while (it.hasNext()) {
                arrayList3.add(((WebViewDomainOption) it.next()).getEntryKey());
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
            if (Intrinsics.areEqual(key, WebViewDomainOption.CUSTOM.getEntryKey())) {
                key = custom;
            }
            if (StringsKt.startsWith$default(key, "https://", false, 2, (Object) null) || StringsKt.startsWith$default(key, "http://", false, 2, (Object) null)) {
                return key;
            }
            return "https://" + key;
        }

        public final String toComicUrl(String domainUrl, String comicId, WebViewClientOption webViewType) {
            Intrinsics.checkNotNullParameter(domainUrl, "domainUrl");
            Intrinsics.checkNotNullParameter(comicId, "comicId");
            Intrinsics.checkNotNullParameter(webViewType, "webViewType");
            String str = isHotManga(domainUrl) ? "v2h5" : "h5";
            if (webViewType == WebViewClientOption.DESKTOP) {
                return domainUrl + "/comic/" + comicId;
            }
            return domainUrl + '/' + str + "/details/comic/" + comicId;
        }

        public final String toChapterUrl(String domainUrl, String chapterUrl, WebViewClientOption webViewType) {
            Intrinsics.checkNotNullParameter(domainUrl, "domainUrl");
            Intrinsics.checkNotNullParameter(chapterUrl, "chapterUrl");
            Intrinsics.checkNotNullParameter(webViewType, "webViewType");
            String str = isHotManga(domainUrl) ? "v2h5" : "h5";
            if (webViewType == WebViewClientOption.DESKTOP) {
                return domainUrl + "/comic/" + chapterUrl;
            }
            return domainUrl + '/' + str + "/comicContent/" + chapterUrl;
        }
    }
}
