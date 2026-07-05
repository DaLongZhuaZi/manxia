package eu.kanade.tachiyomi.extension.zh.copymanga;

import java.util.ArrayList;
import kotlin.Metadata;
import kotlin.jvm.internal.DefaultConstructorMarker;
import kotlin.jvm.internal.Intrinsics;

/* JADX INFO: compiled from: Constants.kt */
/* JADX INFO: loaded from: classes.dex */
@Metadata(d1 = {"\u0000\u0012\n\u0002\u0018\u0002\n\u0002\u0010\u0010\n\u0000\n\u0002\u0010\u000e\n\u0002\b\t\b\u0086\u0001\u0018\u0000 \u000b2\b\u0012\u0004\u0012\u00020\u00000\u0001:\u0001\u000bB\u0017\b\u0002\u0012\u0006\u0010\u0002\u001a\u00020\u0003\u0012\u0006\u0010\u0004\u001a\u00020\u0003¢\u0006\u0002\u0010\u0005R\u0011\u0010\u0002\u001a\u00020\u0003¢\u0006\b\n\u0000\u001a\u0004\b\u0006\u0010\u0007R\u0011\u0010\u0004\u001a\u00020\u0003¢\u0006\b\n\u0000\u001a\u0004\b\b\u0010\u0007j\u0002\b\tj\u0002\b\n¨\u0006\f"}, d2 = {"Leu/kanade/tachiyomi/extension/zh/copymanga/WebViewClientOption;", "", "entry", "", "entryKey", "(Ljava/lang/String;ILjava/lang/String;Ljava/lang/String;)V", "getEntry", "()Ljava/lang/String;", "getEntryKey", "MOBILE", "DESKTOP", "Companion", "tachiyomi-zh.copymanga-v1.4.82_release"}, k = 1, mv = {1, 7, 1}, xi = 48)
public final class WebViewClientOption extends Enum<WebViewClientOption> {
    private static final String DEFAULT_KEY = new WebViewClientOption("桌面端", "web_view.desktop").entryKey;
    public static final WebViewClientOption DESKTOP;
    private static final String[] ENTRIES;
    private static final String[] ENTRY_KEYS;
    public static final String KEY = "v2.pref.web_view_client";
    private final String entry;
    private final String entryKey;
    public static final WebViewClientOption MOBILE = new WebViewClientOption("移動端", "web_view.mobile");
    private static final /* synthetic */ WebViewClientOption[] $VALUES = $values();

    /* JADX INFO: renamed from: Companion, reason: from kotlin metadata */
    public static final Companion INSTANCE = new Companion(null);

    private static final /* synthetic */ WebViewClientOption[] $values() {
        return new WebViewClientOption[]{MOBILE, DESKTOP};
    }

    public static WebViewClientOption valueOf(String str) {
        return (WebViewClientOption) Enum.valueOf(WebViewClientOption.class, str);
    }

    public static WebViewClientOption[] values() {
        return (WebViewClientOption[]) $VALUES.clone();
    }

    private WebViewClientOption(String str, int i, String str2, String str3) {
        super(str, i);
        this.entry = str2;
        this.entryKey = str3;
    }

    public final String getEntry() {
        return this.entry;
    }

    public final String getEntryKey() {
        return this.entryKey;
    }

    static {
        WebViewClientOption webViewClientOption = new WebViewClientOption("桌面端", "web_view.desktop");
        DESKTOP = webViewClientOption;
        $VALUES = $values();
        INSTANCE = new Companion(null);
        DEFAULT_KEY = webViewClientOption.entryKey;
        WebViewClientOption[] webViewClientOptionArrValues = values();
        ArrayList arrayList = new ArrayList(webViewClientOptionArrValues.length);
        for (WebViewClientOption webViewClientOption2 : webViewClientOptionArrValues) {
            arrayList.add(webViewClientOption2.entry);
        }
        ENTRIES = (String[]) arrayList.toArray(new String[0]);
        WebViewClientOption[] webViewClientOptionArrValues2 = values();
        ArrayList arrayList2 = new ArrayList(webViewClientOptionArrValues2.length);
        for (WebViewClientOption webViewClientOption3 : webViewClientOptionArrValues2) {
            arrayList2.add(webViewClientOption3.entryKey);
        }
        ENTRY_KEYS = (String[]) arrayList2.toArray(new String[0]);
    }

    /* JADX INFO: compiled from: Constants.kt */
    @Metadata(d1 = {"\u0000$\n\u0002\u0018\u0002\n\u0002\u0010\u0000\n\u0002\b\u0002\n\u0002\u0010\u000e\n\u0002\b\u0003\n\u0002\u0010\u0011\n\u0002\b\u0007\n\u0002\u0018\u0002\n\u0002\b\u0002\b\u0086\u0003\u0018\u00002\u00020\u0001B\u0007\b\u0002¢\u0006\u0002\u0010\u0002J\u000e\u0010\u000f\u001a\u00020\u00102\u0006\u0010\u0011\u001a\u00020\u0004R\u0011\u0010\u0003\u001a\u00020\u0004¢\u0006\b\n\u0000\u001a\u0004\b\u0005\u0010\u0006R\u0019\u0010\u0007\u001a\b\u0012\u0004\u0012\u00020\u00040\b¢\u0006\n\n\u0002\u0010\u000b\u001a\u0004\b\t\u0010\nR\u0019\u0010\f\u001a\b\u0012\u0004\u0012\u00020\u00040\b¢\u0006\n\n\u0002\u0010\u000b\u001a\u0004\b\r\u0010\nR\u000e\u0010\u000e\u001a\u00020\u0004X\u0086T¢\u0006\u0002\n\u0000¨\u0006\u0012"}, d2 = {"Leu/kanade/tachiyomi/extension/zh/copymanga/WebViewClientOption$Companion;", "", "()V", "DEFAULT_KEY", "", "getDEFAULT_KEY", "()Ljava/lang/String;", "ENTRIES", "", "getENTRIES", "()[Ljava/lang/String;", "[Ljava/lang/String;", "ENTRY_KEYS", "getENTRY_KEYS", "KEY", "key2type", "Leu/kanade/tachiyomi/extension/zh/copymanga/WebViewClientOption;", "key", "tachiyomi-zh.copymanga-v1.4.82_release"}, k = 1, mv = {1, 7, 1}, xi = 48)
    public static final class Companion {
        public /* synthetic */ Companion(DefaultConstructorMarker defaultConstructorMarker) {
            this();
        }

        private Companion() {
        }

        public final String getDEFAULT_KEY() {
            return WebViewClientOption.DEFAULT_KEY;
        }

        public final String[] getENTRIES() {
            return WebViewClientOption.ENTRIES;
        }

        public final String[] getENTRY_KEYS() {
            return WebViewClientOption.ENTRY_KEYS;
        }

        public final WebViewClientOption key2type(String key) throws Exception {
            WebViewClientOption webViewClientOption;
            Intrinsics.checkNotNullParameter(key, "key");
            WebViewClientOption[] webViewClientOptionArrValues = WebViewClientOption.values();
            int length = webViewClientOptionArrValues.length;
            int i = 0;
            while (true) {
                if (i >= length) {
                    webViewClientOption = null;
                    break;
                }
                webViewClientOption = webViewClientOptionArrValues[i];
                if (Intrinsics.areEqual(webViewClientOption.getEntryKey(), key)) {
                    break;
                }
                i++;
            }
            if (webViewClientOption != null) {
                return webViewClientOption;
            }
            throw new Exception("Unknown Key for WebViewClientOption : " + key);
        }
    }
}
