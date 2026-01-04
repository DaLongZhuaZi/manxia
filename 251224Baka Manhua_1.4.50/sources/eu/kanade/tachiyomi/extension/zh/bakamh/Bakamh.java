package eu.kanade.tachiyomi.extension.zh.bakamh;

import android.app.AlertDialog;
import android.app.Application;
import android.content.Context;
import android.content.DialogInterface;
import android.content.SharedPreferences;
import androidx.preference.ListPreference;
import androidx.preference.Preference;
import androidx.preference.PreferenceScreen;
import eu.kanade.tachiyomi.multisrc.madara.Madara;
import eu.kanade.tachiyomi.source.ConfigurableSource;
import eu.kanade.tachiyomi.source.model.SChapter;
import java.text.SimpleDateFormat;
import java.util.Locale;
import kotlin.Lazy;
import kotlin.LazyKt;
import kotlin.Metadata;
import kotlin.jvm.functions.Function0;
import kotlin.jvm.internal.Intrinsics;
import okhttp3.Headers;
import org.jsoup.nodes.Element;
import uy.kohesive.injekt.InjektKt;
import uy.kohesive.injekt.api.FullTypeReference;
import uy.kohesive.injekt.api.InjektFactory;

/* compiled from: Bakamh.kt */
@Metadata(d1 = {"\u0000J\n\u0002\u0018\u0002\n\u0002\u0018\u0002\n\u0002\u0018\u0002\n\u0002\b\u0002\n\u0002\u0010\u000e\n\u0002\b\u0007\n\u0002\u0018\u0002\n\u0002\b\u0005\n\u0002\u0018\u0002\n\u0000\n\u0002\u0018\u0002\n\u0002\b\u0002\n\u0002\u0018\u0002\n\u0000\n\u0002\u0010\u0002\n\u0000\n\u0002\u0018\u0002\n\u0002\b\u0002\n\u0002\u0018\u0002\n\u0002\b\u0002\u0018\u0000  2\u00020\u00012\u00020\u0002:\u0001 B\u0005¢\u0006\u0002\u0010\u0003J\u0010\u0010\u0012\u001a\u00020\u00132\u0006\u0010\u0014\u001a\u00020\u0015H\u0014J\b\u0010\u0016\u001a\u00020\u0005H\u0014J\b\u0010\u0017\u001a\u00020\u0018H\u0014J\u0010\u0010\u0019\u001a\u00020\u001a2\u0006\u0010\u001b\u001a\u00020\u001cH\u0016J\u0010\u0010\u001d\u001a\u00020\u001a2\u0006\u0010\u001e\u001a\u00020\u001fH\u0002R\u001b\u0010\u0004\u001a\u00020\u00058VX\u0096\u0084\u0002¢\u0006\f\n\u0004\b\b\u0010\t\u001a\u0004\b\u0006\u0010\u0007R\u0014\u0010\n\u001a\u00020\u0005X\u0096D¢\u0006\b\n\u0000\u001a\u0004\b\u000b\u0010\u0007R#\u0010\f\u001a\n \u000e*\u0004\u0018\u00010\r0\r8BX\u0082\u0084\u0002¢\u0006\f\n\u0004\b\u0011\u0010\t\u001a\u0004\b\u000f\u0010\u0010¨\u0006!"}, d2 = {"Leu/kanade/tachiyomi/extension/zh/bakamh/Bakamh;", "Leu/kanade/tachiyomi/multisrc/madara/Madara;", "Leu/kanade/tachiyomi/source/ConfigurableSource;", "()V", "baseUrl", "", "getBaseUrl", "()Ljava/lang/String;", "baseUrl$delegate", "Lkotlin/Lazy;", "mangaDetailsSelectorStatus", "getMangaDetailsSelectorStatus", "preferences", "Landroid/content/SharedPreferences;", "kotlin.jvm.PlatformType", "getPreferences", "()Landroid/content/SharedPreferences;", "preferences$delegate", "chapterFromElement", "Leu/kanade/tachiyomi/source/model/SChapter;", "element", "Lorg/jsoup/nodes/Element;", "chapterListSelector", "headersBuilder", "Lokhttp3/Headers$Builder;", "setupPreferenceScreen", "", "screen", "Landroidx/preference/PreferenceScreen;", "showRestartDialog", "context", "Landroid/content/Context;", "Companion", "tachiyomi-zh.bakamh-v1.4.50_debug"}, k = 1, mv = {1, 7, 1}, xi = 48)
/* loaded from: classes3.dex */
public final class Bakamh extends Madara implements ConfigurableSource {
    private static final String DEFAULT_DOMAIN = "https://bakamh.ru";
    private static final String[] DOMAIN_LIST = {"https://bakamh.com", DEFAULT_DOMAIN, "https://baka1.my", "https://baka2.de", "https://baka3.me"};
    private static final String DOMAIN_PREF_KEY = "preferred_domain";

    /* renamed from: baseUrl$delegate, reason: from kotlin metadata */
    private final Lazy baseUrl;
    private final String mangaDetailsSelectorStatus;

    /* renamed from: preferences$delegate, reason: from kotlin metadata */
    private final Lazy preferences;

    public Bakamh() {
        super("巴卡漫画", DEFAULT_DOMAIN, "zh", new SimpleDateFormat("yyyy 年 M 月 d 日", Locale.CHINESE));
        this.preferences = LazyKt.lazy(new Function0<SharedPreferences>() { // from class: eu.kanade.tachiyomi.extension.zh.bakamh.Bakamh$preferences$2
            {
                super(0);
            }

            /* renamed from: invoke, reason: merged with bridge method [inline-methods] */
            public final SharedPreferences m1invoke() {
                InjektFactory $receiver$iv = InjektKt.getInjekt();
                return ((Application) $receiver$iv.getInstance(new FullTypeReference<Application>() { // from class: eu.kanade.tachiyomi.extension.zh.bakamh.Bakamh$preferences$2$invoke$$inlined$get$1
                }.getType())).getSharedPreferences("source_" + this.this$0.getId(), 0);
            }
        });
        this.baseUrl = LazyKt.lazy(new Function0<String>() { // from class: eu.kanade.tachiyomi.extension.zh.bakamh.Bakamh$baseUrl$2
            {
                super(0);
            }

            public final String invoke() {
                String string = this.this$0.getPreferences().getString("preferred_domain", "https://bakamh.ru");
                return string == null ? "https://bakamh.ru" : string;
            }
        });
        this.mangaDetailsSelectorStatus = ".post-content_item:contains(状态) .summary-content";
    }

    /* JADX INFO: Access modifiers changed from: private */
    public final SharedPreferences getPreferences() {
        return (SharedPreferences) this.preferences.getValue();
    }

    @Override // eu.kanade.tachiyomi.multisrc.madara.Madara
    public String getBaseUrl() {
        return (String) this.baseUrl.getValue();
    }

    public void setupPreferenceScreen(final PreferenceScreen screen) {
        Intrinsics.checkNotNullParameter(screen, "screen");
        final Preference listPreference = new ListPreference(screen.getContext());
        listPreference.setKey(DOMAIN_PREF_KEY);
        listPreference.setTitle("选择域名");
        listPreference.setEntries(DOMAIN_LIST);
        listPreference.setEntryValues(DOMAIN_LIST);
        listPreference.setDefaultValue(DEFAULT_DOMAIN);
        listPreference.setSummary("%s\n\n注意：切换域名后需要重启应用才能生效");
        listPreference.setOnPreferenceChangeListener(new Preference.OnPreferenceChangeListener() { // from class: eu.kanade.tachiyomi.extension.zh.bakamh.Bakamh$$ExternalSyntheticLambda0
            public final boolean onPreferenceChange(Preference preference, Object obj) {
                return Bakamh.setupPreferenceScreen$lambda$1$lambda$0(listPreference, this, screen, preference, obj);
            }
        });
        Preference p0 = listPreference;
        screen.addPreference(p0);
    }

    /* JADX INFO: Access modifiers changed from: private */
    public static final boolean setupPreferenceScreen$lambda$1$lambda$0(ListPreference $this_apply, Bakamh this$0, PreferenceScreen $screen, Preference preference, Object newValue) {
        Intrinsics.checkNotNullParameter($this_apply, "$this_apply");
        Intrinsics.checkNotNullParameter(this$0, "this$0");
        Intrinsics.checkNotNullParameter($screen, "$screen");
        Intrinsics.checkNotNull(newValue, "null cannot be cast to non-null type kotlin.String");
        String selected = (String) newValue;
        int index = $this_apply.findIndexOfValue(selected);
        CharSequence charSequence = $this_apply.getEntryValues()[index];
        Intrinsics.checkNotNull(charSequence, "null cannot be cast to non-null type kotlin.String");
        String entry = (String) charSequence;
        this$0.getPreferences().edit().putString($this_apply.getKey(), entry).apply();
        Context context = $screen.getContext();
        Intrinsics.checkNotNullExpressionValue(context, "screen.context");
        this$0.showRestartDialog(context);
        return true;
    }

    private final void showRestartDialog(Context context) {
        new AlertDialog.Builder(context).setTitle("提示").setMessage("域名已更改，请重启应用以使设置生效").setPositiveButton("确定", new DialogInterface.OnClickListener() { // from class: eu.kanade.tachiyomi.extension.zh.bakamh.Bakamh$$ExternalSyntheticLambda1
            @Override // android.content.DialogInterface.OnClickListener
            public final void onClick(DialogInterface dialogInterface, int i) {
                Bakamh.showRestartDialog$lambda$2(dialogInterface, i);
            }
        }).show();
    }

    /* JADX INFO: Access modifiers changed from: private */
    public static final void showRestartDialog$lambda$2(DialogInterface dialogInterface, int i) {
    }

    @Override // eu.kanade.tachiyomi.multisrc.madara.Madara
    public String getMangaDetailsSelectorStatus() {
        return this.mangaDetailsSelectorStatus;
    }

    @Override // eu.kanade.tachiyomi.multisrc.madara.Madara
    protected String chapterListSelector() {
        return "div.tab-content li:has(a[chapter-data-url])";
    }

    @Override // eu.kanade.tachiyomi.multisrc.madara.Madara
    protected Headers.Builder headersBuilder() {
        return super.headersBuilder().add("User-Agent", "Mozilla/5.0 (Linux; U; Android 16; zh-cn; 24129PN74C Build/BP2A.250605.031.A3) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/135.0.7049.79 Mobile Safari/537.36 XiaoMi/MiuiBrowser/20.9.1021219").add("Accept-Encoding", "gzip").add("sec-ch-ua", "0").add("accept-language", "zh-CN,zh;q=0.9,en-US;q=0.8,en;q=0.7");
    }

    @Override // eu.kanade.tachiyomi.multisrc.madara.Madara
    protected SChapter chapterFromElement(Element element) {
        Intrinsics.checkNotNullParameter(element, "element");
        SChapter $this$chapterFromElement_u24lambda_u243 = SChapter.Companion.create();
        Element urlElement = element.selectFirst("a");
        Intrinsics.checkNotNull(urlElement);
        String strAttr = urlElement.attr("abs:chapter-data-url");
        Intrinsics.checkNotNullExpressionValue(strAttr, "urlElement.attr(\"abs:chapter-data-url\")");
        $this$chapterFromElement_u24lambda_u243.setUrl(strAttr);
        String strText = urlElement.text();
        Intrinsics.checkNotNullExpressionValue(strText, "urlElement.text()");
        $this$chapterFromElement_u24lambda_u243.setName(strText);
        return $this$chapterFromElement_u24lambda_u243;
    }
}
