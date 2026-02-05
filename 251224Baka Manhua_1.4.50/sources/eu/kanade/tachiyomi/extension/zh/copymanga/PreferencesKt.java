package eu.kanade.tachiyomi.extension.zh.copymanga;

import android.content.Context;
import android.content.SharedPreferences;
import androidx.preference.EditTextPreference;
import androidx.preference.ListPreference;
import androidx.preference.Preference;
import androidx.preference.SwitchPreferenceCompat;
import eu.kanade.tachiyomi.extension.zh.copymanga.special.TokenProvider;
import java.util.Arrays;
import kotlin.Metadata;
import kotlin.Result;
import kotlin.ResultKt;
import kotlin.Unit;
import kotlin.collections.ArraysKt;
import kotlin.jvm.internal.Intrinsics;

/* compiled from: Preferences.kt */
@Metadata(d1 = {"\u0000N\n\u0000\n\u0002\u0010\u000e\n\u0002\u0018\u0002\n\u0002\b\r\n\u0002\u0010\u000b\n\u0002\b\u001d\n\u0002\u0010\u0011\n\u0002\u0018\u0002\n\u0000\n\u0002\u0018\u0002\n\u0002\b\u0003\n\u0002\u0010\u0002\n\u0000\n\u0002\u0018\u0002\n\u0002\u0018\u0002\n\u0002\b\u0004\n\u0002\u0018\u0002\n\u0000\n\u0002\u0018\u0002\n\u0000\n\u0002\u0018\u0002\n\u0002\b\u0006\u001a!\u0010-\u001a\b\u0012\u0004\u0012\u00020/0.2\u0006\u00100\u001a\u0002012\u0006\u00102\u001a\u00020\u0002¢\u0006\u0002\u00103\u001a\n\u00104\u001a\u000205*\u00020\u0002\u001a\n\u00106\u001a\u000207*\u00020\u0002\u001a\n\u0010\b\u001a\u000208*\u00020\u0002\u001a\n\u00109\u001a\u00020\u0001*\u00020\u0002\u001a\n\u0010:\u001a\u00020\u0001*\u00020\u0002\u001a\n\u0010;\u001a\u00020\u0001*\u00020\u0002\u001a\n\u0010<\u001a\u00020=*\u00020\u0002\u001a\n\u0010>\u001a\u00020?*\u00020\u0002\u001a\n\u0010@\u001a\u00020A*\u00020\u0002\u001a\u0012\u0010B\u001a\u000205*\u00020\u00022\u0006\u0010C\u001a\u00020\u0001\u001a\u0012\u0010D\u001a\u000205*\u00020\u00022\u0006\u0010C\u001a\u00020\u0001\u001a\u0012\u0010E\u001a\u000205*\u00020\u00022\u0006\u0010F\u001a\u00020\u0001\"\u0015\u0010\u0000\u001a\u00020\u0001*\u00020\u00028G¢\u0006\u0006\u001a\u0004\b\u0003\u0010\u0004\"\u0015\u0010\u0005\u001a\u00020\u0001*\u00020\u00028F¢\u0006\u0006\u001a\u0004\b\u0006\u0010\u0004\"\u0015\u0010\u0007\u001a\u00020\u0001*\u00020\u00028F¢\u0006\u0006\u001a\u0004\b\b\u0010\u0004\"\u0015\u0010\t\u001a\u00020\u0001*\u00020\u00028F¢\u0006\u0006\u001a\u0004\b\n\u0010\u0004\"\u0015\u0010\u000b\u001a\u00020\u0001*\u00020\u00028F¢\u0006\u0006\u001a\u0004\b\f\u0010\u0004\"\u0015\u0010\r\u001a\u00020\u0001*\u00020\u00028F¢\u0006\u0006\u001a\u0004\b\u000e\u0010\u0004\"\u0015\u0010\u000f\u001a\u00020\u0010*\u00020\u00028F¢\u0006\u0006\u001a\u0004\b\u0011\u0010\u0012\"\u0015\u0010\u0013\u001a\u00020\u0001*\u00020\u00028F¢\u0006\u0006\u001a\u0004\b\u0014\u0010\u0004\"\u0015\u0010\u0015\u001a\u00020\u0001*\u00020\u00028F¢\u0006\u0006\u001a\u0004\b\u0016\u0010\u0004\"\u0015\u0010\u0017\u001a\u00020\u0001*\u00020\u00028F¢\u0006\u0006\u001a\u0004\b\u0018\u0010\u0004\"\u0015\u0010\u0019\u001a\u00020\u0001*\u00020\u00028F¢\u0006\u0006\u001a\u0004\b\u001a\u0010\u0004\"\u0015\u0010\u001b\u001a\u00020\u0001*\u00020\u00028F¢\u0006\u0006\u001a\u0004\b\u001c\u0010\u0004\"\u0015\u0010\u001d\u001a\u00020\u0001*\u00020\u00028F¢\u0006\u0006\u001a\u0004\b\u001e\u0010\u0004\"\u0015\u0010\u001f\u001a\u00020\u0010*\u00020\u00028F¢\u0006\u0006\u001a\u0004\b \u0010\u0012\"\u0015\u0010!\u001a\u00020\u0010*\u00020\u00028F¢\u0006\u0006\u001a\u0004\b\"\u0010\u0012\"\u0015\u0010#\u001a\u00020\u0010*\u00020\u00028F¢\u0006\u0006\u001a\u0004\b$\u0010\u0012\"\u0015\u0010%\u001a\u00020\u0010*\u00020\u00028F¢\u0006\u0006\u001a\u0004\b&\u0010\u0012\"\u0015\u0010'\u001a\u00020\u0001*\u00020\u00028F¢\u0006\u0006\u001a\u0004\b(\u0010\u0004\"\u0015\u0010)\u001a\u00020\u0001*\u00020\u00028F¢\u0006\u0006\u001a\u0004\b*\u0010\u0004\"\u0015\u0010+\u001a\u00020\u0001*\u00020\u00028G¢\u0006\u0006\u001a\u0004\b,\u0010\u0004¨\u0006G"}, d2 = {"apiDomain", "", "Landroid/content/SharedPreferences;", "getApiDomainFromPrefs", "(Landroid/content/SharedPreferences;)Ljava/lang/String;", "ccKeyPref", "getCcKeyPref", "chapterCommentPerformMode", "getChapterCommentPerformMode", "copyMangaToken", "getCopyMangaToken", "customApiDomain", "getCustomApiDomain", "customWebViewDomain", "getCustomWebViewDomain", "enableLogin", "", "getEnableLogin", "(Landroid/content/SharedPreferences;)Z", "hideDefaultContinuousChapter", "getHideDefaultContinuousChapter", "hotMangaToken", "getHotMangaToken", "imageResolutionKey", "getImageResolutionKey", "latestUpdateOptionPref", "getLatestUpdateOptionPref", "loginCredentials", "getLoginCredentials", "platFormOptionKey", "getPlatFormOptionKey", "reserveChapterComments", "getReserveChapterComments", "showChapterComments", "getShowChapterComments", "showMangaComments", "getShowMangaComments", "useCopyMangaComment", "getUseCopyMangaComment", "userAgent", "getUserAgent", "webViewClientKey", "getWebViewClientKey", "webViewDomain", "getWebViewDomainFromPrefs", "initPreferences", "", "Landroidx/preference/Preference;", "context", "Landroid/content/Context;", "preferences", "(Landroid/content/Context;Landroid/content/SharedPreferences;)[Landroidx/preference/Preference;", "clearLoginCredentials", "", "getCCOption", "Leu/kanade/tachiyomi/extension/zh/copymanga/CCOption;", "Leu/kanade/tachiyomi/extension/zh/copymanga/ChapterCommentPerformOption;", "getHttpApiDomain", "getHttpWebViewDomain", "getImageResolution", "getLatestUpdateMode", "Leu/kanade/tachiyomi/extension/zh/copymanga/LatestUpdateOption;", "getUserAgentType", "Leu/kanade/tachiyomi/extension/zh/copymanga/UserAgentType;", "getWebViewClientType", "Leu/kanade/tachiyomi/extension/zh/copymanga/WebViewClientOption;", "setCopyMangaToken", "token", "setHotMangaToken", "updatePlatformIndex", "params", "tachiyomi-zh.copymanga-v1.4.78_release"}, k = 2, mv = {1, 7, 1}, xi = 48)
/* loaded from: classes.dex */
public final class PreferencesKt {
    /* JADX INFO: Access modifiers changed from: private */
    public static final boolean initPreferences$lambda$2$lambda$1(Preference preference, Object obj) {
        return false;
    }

    public static final Preference[] initPreferences(Context context, final SharedPreferences sharedPreferences) {
        Intrinsics.checkNotNullParameter(context, "context");
        Intrinsics.checkNotNullParameter(sharedPreferences, "preferences");
        final Preference editTextPreference = new EditTextPreference(context);
        final Preference editTextPreference2 = new EditTextPreference(context);
        final Preference switchPreferenceCompat = new SwitchPreferenceCompat(context);
        final Preference editTextPreference3 = new EditTextPreference(context);
        final Preference switchPreferenceCompat2 = new SwitchPreferenceCompat(context);
        final Preference listPreference = new ListPreference(context);
        final Preference switchPreferenceCompat3 = new SwitchPreferenceCompat(context);
        initPreferences$ensureDefault(sharedPreferences, ApiDomainOption.KEY, ApiDomainOption.INSTANCE.getDEFAULT());
        initPreferences$ensureDefault(sharedPreferences, WebViewDomainOption.KEY, WebViewDomainOption.INSTANCE.getDEFAULT());
        initPreferences$ensureDefault(sharedPreferences, WebViewClientOption.KEY, WebViewClientOption.INSTANCE.getDEFAULT_KEY());
        initPreferences$ensureDefault(sharedPreferences, LatestUpdateOption.KEY, LatestUpdateOption.INSTANCE.getDEFAULT());
        initPreferences$ensureDefault(sharedPreferences, CCOption.KEY, CCOption.DEFAULT.getEntryKey());
        initPreferences$ensureDefault(sharedPreferences, ChapterCommentPerformOption.KEY, ChapterCommentPerformOption.INSTANCE.getDEFAULT());
        initPreferences$ensureDefault(sharedPreferences, ResolutionOption.KEY, ResolutionOption.INSTANCE.getDEFAULT());
        initPreferences$ensureDefault(sharedPreferences, PlatFormOption.KEY, PlatFormOption.INSTANCE.getDEFAULT());
        initPreferences$ensureDefault(sharedPreferences, ApiDomainOption.KEY_CUSTOM, PluginMetaData.BASE_URL);
        initPreferences$ensureDefault(sharedPreferences, WebViewDomainOption.KEY_CUSTOM, PluginMetaData.BASE_URL);
        initPreferences$ensureDefault(sharedPreferences, PreferencesKeys.USER_AGENT, PluginMetaData.USER_AGENT);
        initPreferences$ensureDefault(sharedPreferences, PreferencesKeys.HIDE_DEFAULT_CONTINUOUS_CHAPTER, "");
        initPreferences$ensureDefault(sharedPreferences, PreferencesKeys.LOGIN_CREDENTIALS, "");
        initPreferences$ensureDefault(sharedPreferences, PreferencesKeys.SHOW_CHAPTER_COMMENTS, false);
        initPreferences$ensureDefault(sharedPreferences, PreferencesKeys.RESERVE_CHAPTER_COMMENTS, false);
        initPreferences$ensureDefault(sharedPreferences, PreferencesKeys.USE_COPYMANGA_COMMENT, true);
        initPreferences$ensureDefault(sharedPreferences, PreferencesKeys.ENABLE_LOGIN, false);
        initPreferences$fixInvalidValue(sharedPreferences, ApiDomainOption.KEY, ApiDomainOption.INSTANCE.getENTRY_KEYS(), ApiDomainOption.INSTANCE.getDEFAULT());
        initPreferences$fixInvalidValue(sharedPreferences, WebViewDomainOption.KEY, WebViewDomainOption.INSTANCE.getENTRY_KEYS(), WebViewDomainOption.INSTANCE.getDEFAULT());
        initPreferences$fixInvalidValue(sharedPreferences, WebViewClientOption.KEY, WebViewClientOption.INSTANCE.getENTRY_KEYS(), WebViewClientOption.INSTANCE.getDEFAULT_KEY());
        initPreferences$fixInvalidValue(sharedPreferences, LatestUpdateOption.KEY, LatestUpdateOption.INSTANCE.getENTRY_KEYS(), LatestUpdateOption.INSTANCE.getDEFAULT());
        initPreferences$fixInvalidValue(sharedPreferences, CCOption.KEY, CCOption.INSTANCE.getENTRY_KEYS(), CCOption.DEFAULT.getEntryKey());
        initPreferences$fixInvalidValue(sharedPreferences, ChapterCommentPerformOption.KEY, ChapterCommentPerformOption.INSTANCE.getENTRY_KEYS(), ChapterCommentPerformOption.INSTANCE.getDEFAULT());
        initPreferences$fixInvalidValue(sharedPreferences, ResolutionOption.KEY, ResolutionOption.INSTANCE.getENTRY_KEYS(), ResolutionOption.INSTANCE.getDEFAULT());
        initPreferences$fixInvalidValue(sharedPreferences, PlatFormOption.KEY, PlatFormOption.INSTANCE.getENTRY_KEYS(), PlatFormOption.INSTANCE.getDEFAULT());
        Preference[] preferenceArr = new Preference[19];
        EditTextPreference editTextPreference4 = new EditTextPreference(context);
        editTextPreference4.setKey(PreferencesKeys.ONLY_UPDATE_LINK);
        editTextPreference4.setTitle("本插件資訊");
        editTextPreference4.setSummary(PluginCommunityInfo.INSTANCE.getSUMMERY());
        editTextPreference4.setDefaultValue(PluginCommunityInfo.INSTANCE.getSUMMERY());
        editTextPreference4.setOnPreferenceChangeListener(new Preference.OnPreferenceChangeListener() { // from class: eu.kanade.tachiyomi.extension.zh.copymanga.PreferencesKt$$ExternalSyntheticLambda0
            public final boolean onPreferenceChange(Preference preference, Object obj) {
                return PreferencesKt.initPreferences$lambda$2$lambda$1(preference, obj);
            }
        });
        Unit unit = Unit.INSTANCE;
        preferenceArr[0] = (Preference) editTextPreference4;
        final ListPreference listPreference2 = new ListPreference(context);
        listPreference2.setKey(ApiDomainOption.KEY);
        listPreference2.setTitle("API 域名");
        listPreference2.setSummary("%s");
        listPreference2.setEntries(ApiDomainOption.INSTANCE.getENTRIES());
        listPreference2.setEntryValues(ApiDomainOption.INSTANCE.getENTRY_KEYS());
        listPreference2.setDefaultValue(ApiDomainOption.INSTANCE.getDEFAULT());
        listPreference2.setOnPreferenceChangeListener(new Preference.OnPreferenceChangeListener() { // from class: eu.kanade.tachiyomi.extension.zh.copymanga.PreferencesKt$$ExternalSyntheticLambda3
            public final boolean onPreferenceChange(Preference preference, Object obj) {
                return PreferencesKt.initPreferences$lambda$5$lambda$4(listPreference2, editTextPreference, preference, obj);
            }
        });
        Unit unit2 = Unit.INSTANCE;
        preferenceArr[1] = (Preference) listPreference2;
        editTextPreference.setKey(ApiDomainOption.KEY_CUSTOM);
        editTextPreference.setTitle("自訂 API 域名");
        editTextPreference.setSummary(getCustomApiDomain(sharedPreferences));
        editTextPreference.setDefaultValue("");
        editTextPreference.setOnPreferenceChangeListener(new Preference.OnPreferenceChangeListener() { // from class: eu.kanade.tachiyomi.extension.zh.copymanga.PreferencesKt$$ExternalSyntheticLambda4
            public final boolean onPreferenceChange(Preference preference, Object obj) {
                return PreferencesKt.initPreferences$lambda$8$lambda$6(editTextPreference, preference, obj);
            }
        });
        try {
            Result.Companion companion = Result.Companion;
            editTextPreference.setVisible(Intrinsics.areEqual(getApiDomainFromPrefs(sharedPreferences), ApiDomainOption.CUSTOM.getEntryKey()));
            Result.constructor-impl(Unit.INSTANCE);
        } catch (Throwable th) {
            Result.Companion companion2 = Result.Companion;
            Result.constructor-impl(ResultKt.createFailure(th));
        }
        Unit unit3 = Unit.INSTANCE;
        preferenceArr[2] = editTextPreference;
        final ListPreference listPreference3 = new ListPreference(context);
        listPreference3.setKey(WebViewDomainOption.KEY);
        listPreference3.setTitle("WebView 链接");
        listPreference3.setSummary("%s");
        listPreference3.setEntries(WebViewDomainOption.INSTANCE.getENTRIES());
        listPreference3.setEntryValues(WebViewDomainOption.INSTANCE.getENTRY_KEYS());
        listPreference3.setDefaultValue(WebViewDomainOption.INSTANCE.getDEFAULT());
        listPreference3.setOnPreferenceChangeListener(new Preference.OnPreferenceChangeListener() { // from class: eu.kanade.tachiyomi.extension.zh.copymanga.PreferencesKt$$ExternalSyntheticLambda5
            public final boolean onPreferenceChange(Preference preference, Object obj) {
                return PreferencesKt.initPreferences$lambda$11$lambda$10(listPreference3, editTextPreference2, preference, obj);
            }
        });
        Unit unit4 = Unit.INSTANCE;
        preferenceArr[3] = (Preference) listPreference3;
        editTextPreference2.setKey(WebViewDomainOption.KEY_CUSTOM);
        editTextPreference2.setTitle("自訂 WebView 域名");
        editTextPreference2.setSummary(getCustomWebViewDomain(sharedPreferences));
        editTextPreference2.setDefaultValue("");
        editTextPreference2.setOnPreferenceChangeListener(new Preference.OnPreferenceChangeListener() { // from class: eu.kanade.tachiyomi.extension.zh.copymanga.PreferencesKt$$ExternalSyntheticLambda6
            public final boolean onPreferenceChange(Preference preference, Object obj) {
                return PreferencesKt.initPreferences$lambda$14$lambda$12(editTextPreference2, preference, obj);
            }
        });
        try {
            Result.Companion companion3 = Result.Companion;
            editTextPreference2.setVisible(Intrinsics.areEqual(getWebViewDomainFromPrefs(sharedPreferences), WebViewDomainOption.CUSTOM.getEntryKey()));
            Result.constructor-impl(Unit.INSTANCE);
        } catch (Throwable th2) {
            Result.Companion companion4 = Result.Companion;
            Result.constructor-impl(ResultKt.createFailure(th2));
        }
        Unit unit5 = Unit.INSTANCE;
        preferenceArr[4] = editTextPreference2;
        ListPreference listPreference4 = new ListPreference(context);
        listPreference4.setKey(WebViewClientOption.KEY);
        listPreference4.setTitle("WebView 客戶端類型");
        listPreference4.setSummary("%s");
        listPreference4.setEntries(WebViewClientOption.INSTANCE.getENTRIES());
        listPreference4.setEntryValues(WebViewClientOption.INSTANCE.getENTRY_KEYS());
        listPreference4.setDefaultValue(WebViewClientOption.INSTANCE.getDEFAULT_KEY());
        Unit unit6 = Unit.INSTANCE;
        preferenceArr[5] = (Preference) listPreference4;
        ListPreference listPreference5 = new ListPreference(context);
        listPreference5.setKey(LatestUpdateOption.KEY);
        listPreference5.setTitle("最新更新列表");
        listPreference5.setSummary("%s");
        listPreference5.setEntries(LatestUpdateOption.INSTANCE.getENTRIES());
        listPreference5.setEntryValues(LatestUpdateOption.INSTANCE.getENTRY_KEYS());
        listPreference5.setDefaultValue(LatestUpdateOption.INSTANCE.getDEFAULT());
        Unit unit7 = Unit.INSTANCE;
        preferenceArr[6] = (Preference) listPreference5;
        ListPreference listPreference6 = new ListPreference(context);
        listPreference6.setKey(CCOption.KEY);
        listPreference6.setTitle("简繁設定");
        listPreference6.setSummary("%s");
        listPreference6.setEntries(CCOption.INSTANCE.getENTRIES());
        listPreference6.setEntryValues(CCOption.INSTANCE.getENTRY_KEYS());
        listPreference6.setDefaultValue(CCOption.DEFAULT.getEntryKey());
        Unit unit8 = Unit.INSTANCE;
        preferenceArr[7] = (Preference) listPreference6;
        switchPreferenceCompat.setKey(PreferencesKeys.ENABLE_LOGIN);
        switchPreferenceCompat.setTitle("启用登入状态浏览");
        String str = String.format(PreferencesKeys.ENABLE_LOGIN_SUMMERY, Arrays.copyOf(new Object[]{TokenProvider.LoginStatus.INSTANCE.token2StatusMessage(getCopyMangaToken(sharedPreferences)), TokenProvider.LoginStatus.INSTANCE.token2StatusMessage(getHotMangaToken(sharedPreferences))}, 2));
        Intrinsics.checkNotNullExpressionValue(str, "format(this, *args)");
        switchPreferenceCompat.setSummary(str);
        switchPreferenceCompat.setDefaultValue(false);
        switchPreferenceCompat.setOnPreferenceChangeListener(new Preference.OnPreferenceChangeListener() { // from class: eu.kanade.tachiyomi.extension.zh.copymanga.PreferencesKt$$ExternalSyntheticLambda7
            public final boolean onPreferenceChange(Preference preference, Object obj) {
                return PreferencesKt.initPreferences$lambda$20$lambda$19(switchPreferenceCompat, switchPreferenceCompat, editTextPreference3, preference, obj);
            }
        });
        Unit unit9 = Unit.INSTANCE;
        preferenceArr[8] = switchPreferenceCompat;
        editTextPreference3.setKey(PreferencesKeys.LOGIN_CREDENTIALS);
        editTextPreference3.setTitle("填寫登入資訊(帳號密碼)");
        editTextPreference3.setSummary("输入帐号密码，分别为拷贝(copy)帐密和热辣(hot)帐密\n请遵照格式分别填写，不填写对应选项则维持未登入状态\n登入状态会在填写完成点选确定后更新，并提示于启用登入选项下方\n若登入信息未更新，可重启启动登入状态浏览选项\n出于资讯安全考虑，输入的帐密会在输入完确认后清空\n帐密填写格式如下所述(一行一项资讯，可一次亦可分別輸入)：\ncopy:帐号名称 密码\nhot:帐号名称 密码\n输入clear清除登入Token");
        editTextPreference3.setDefaultValue("");
        editTextPreference3.setOnPreferenceChangeListener(new Preference.OnPreferenceChangeListener() { // from class: eu.kanade.tachiyomi.extension.zh.copymanga.PreferencesKt$$ExternalSyntheticLambda8
            public final boolean onPreferenceChange(Preference preference, Object obj) {
                return PreferencesKt.initPreferences$lambda$24$lambda$22(switchPreferenceCompat, sharedPreferences, preference, obj);
            }
        });
        try {
            Result.Companion companion5 = Result.Companion;
            editTextPreference3.setVisible(getEnableLogin(sharedPreferences));
            Result.constructor-impl(Unit.INSTANCE);
        } catch (Throwable th3) {
            Result.Companion companion6 = Result.Companion;
            Result.constructor-impl(ResultKt.createFailure(th3));
        }
        Unit unit10 = Unit.INSTANCE;
        preferenceArr[9] = editTextPreference3;
        SwitchPreferenceCompat switchPreferenceCompat4 = new SwitchPreferenceCompat(context);
        switchPreferenceCompat4.setKey(PreferencesKeys.SHOW_MANGA_COMMENTS);
        switchPreferenceCompat4.setTitle("顯示漫畫總評");
        switchPreferenceCompat4.setSummary("在漫畫第一話前插入\"漫畫評論\"章節，顯示漫畫總評\n(注意，此功能將會一次擷取所有漫畫評論，會導致章節獲取時間延長，若過於頻繁使用可能會觸發防盜版，關於漫畫評論依然建議使用webview觀看)\n(目前僅支持Android，若有更優秀的通用替代方案替代 Android Canvas請在Github或群組建議，感謝)");
        switchPreferenceCompat4.setDefaultValue(false);
        Unit unit11 = Unit.INSTANCE;
        preferenceArr[10] = (Preference) switchPreferenceCompat4;
        final SwitchPreferenceCompat switchPreferenceCompat5 = new SwitchPreferenceCompat(context);
        switchPreferenceCompat5.setKey(PreferencesKeys.SHOW_CHAPTER_COMMENTS);
        switchPreferenceCompat5.setTitle("章末吐槽页");
        switchPreferenceCompat5.setSummary("与其相关设定修改后，已加载的章节需要清除章节缓存才生效\n(目前僅支持Android，若有更優秀的通用替代方案替代 Android Canvas請在Github或群組建議，感謝)");
        switchPreferenceCompat5.setDefaultValue(false);
        switchPreferenceCompat5.setOnPreferenceChangeListener(new Preference.OnPreferenceChangeListener() { // from class: eu.kanade.tachiyomi.extension.zh.copymanga.PreferencesKt$$ExternalSyntheticLambda9
            public final boolean onPreferenceChange(Preference preference, Object obj) {
                return PreferencesKt.initPreferences$lambda$28$lambda$27(switchPreferenceCompat5, switchPreferenceCompat2, switchPreferenceCompat3, listPreference, preference, obj);
            }
        });
        Unit unit12 = Unit.INSTANCE;
        preferenceArr[11] = (Preference) switchPreferenceCompat5;
        listPreference.setKey(ChapterCommentPerformOption.KEY);
        listPreference.setTitle("章末吐槽页格式");
        listPreference.setSummary("%s");
        listPreference.setEntries(ChapterCommentPerformOption.INSTANCE.getENTRIES());
        listPreference.setEntryValues(ChapterCommentPerformOption.INSTANCE.getENTRY_KEYS());
        listPreference.setDefaultValue(ChapterCommentPerformOption.INSTANCE.getDEFAULT());
        try {
            Result.Companion companion7 = Result.Companion;
            listPreference.setVisible(getShowChapterComments(sharedPreferences));
            Result.constructor-impl(Unit.INSTANCE);
        } catch (Throwable th4) {
            Result.Companion companion8 = Result.Companion;
            Result.constructor-impl(ResultKt.createFailure(th4));
        }
        Unit unit13 = Unit.INSTANCE;
        preferenceArr[12] = listPreference;
        switchPreferenceCompat2.setKey(PreferencesKeys.RESERVE_CHAPTER_COMMENTS);
        switchPreferenceCompat2.setTitle("倒叙展开评论");
        switchPreferenceCompat2.setSummary("将 新→旧 的吐槽顺序更改为 旧→新");
        switchPreferenceCompat2.setDefaultValue(false);
        try {
            Result.Companion companion9 = Result.Companion;
            switchPreferenceCompat2.setVisible(getShowChapterComments(sharedPreferences));
            Result.constructor-impl(Unit.INSTANCE);
        } catch (Throwable th5) {
            Result.Companion companion10 = Result.Companion;
            Result.constructor-impl(ResultKt.createFailure(th5));
        }
        Unit unit14 = Unit.INSTANCE;
        preferenceArr[13] = switchPreferenceCompat2;
        switchPreferenceCompat3.setKey(PreferencesKeys.USE_COPYMANGA_COMMENT);
        switchPreferenceCompat3.setTitle("使用拷贝漫画吐槽");
        switchPreferenceCompat3.setSummary("在使用热辣漫画域名时，使用拷贝漫画的吐槽");
        switchPreferenceCompat3.setDefaultValue(true);
        try {
            Result.Companion companion11 = Result.Companion;
            switchPreferenceCompat3.setVisible(getShowChapterComments(sharedPreferences));
            Result.constructor-impl(Unit.INSTANCE);
        } catch (Throwable th6) {
            Result.Companion companion12 = Result.Companion;
            Result.constructor-impl(ResultKt.createFailure(th6));
        }
        Unit unit15 = Unit.INSTANCE;
        preferenceArr[14] = switchPreferenceCompat3;
        final ListPreference listPreference7 = new ListPreference(context);
        listPreference7.setKey(ResolutionOption.KEY);
        listPreference7.setTitle("图片分辨率（像素）");
        String str2 = String.format(ResolutionOption.SUMMERY, Arrays.copyOf(new Object[]{getImageResolution(sharedPreferences)}, 1));
        Intrinsics.checkNotNullExpressionValue(str2, "format(this, *args)");
        listPreference7.setSummary(str2);
        listPreference7.setEntries(ResolutionOption.INSTANCE.getENTRIES());
        listPreference7.setEntryValues(ResolutionOption.INSTANCE.getENTRY_KEYS());
        listPreference7.setDefaultValue(ResolutionOption.INSTANCE.getDEFAULT());
        listPreference7.setOnPreferenceChangeListener(new Preference.OnPreferenceChangeListener() { // from class: eu.kanade.tachiyomi.extension.zh.copymanga.PreferencesKt$$ExternalSyntheticLambda10
            public final boolean onPreferenceChange(Preference preference, Object obj) {
                return PreferencesKt.initPreferences$lambda$36$lambda$35(listPreference7, preference, obj);
            }
        });
        Unit unit16 = Unit.INSTANCE;
        preferenceArr[15] = (Preference) listPreference7;
        EditTextPreference editTextPreference5 = new EditTextPreference(context);
        editTextPreference5.setKey(PreferencesKeys.HIDE_DEFAULT_CONTINUOUS_CHAPTER);
        editTextPreference5.setTitle("隐藏默认连载章节");
        editTextPreference5.setSummary("部分作品的默认连载章节陈旧，而新章节却更新在“其他系列”中；在这里填写作品名称（一行一个，简繁体必须与书架中的作品对应）即可在检查更新时隐藏默认的连载章节，只显示其他系列");
        editTextPreference5.setDefaultValue("");
        Unit unit17 = Unit.INSTANCE;
        preferenceArr[16] = (Preference) editTextPreference5;
        ListPreference listPreference8 = new ListPreference(context);
        listPreference8.setKey(PlatFormOption.KEY);
        listPreference8.setTitle("平台参数");
        listPreference8.setSummary("%s");
        listPreference8.setEntries(PlatFormOption.INSTANCE.getENTRIES());
        listPreference8.setEntryValues(PlatFormOption.INSTANCE.getENTRY_KEYS());
        listPreference8.setDefaultValue(PlatFormOption.INSTANCE.getDEFAULT());
        listPreference8.setOnPreferenceChangeListener(new Preference.OnPreferenceChangeListener() { // from class: eu.kanade.tachiyomi.extension.zh.copymanga.PreferencesKt$$ExternalSyntheticLambda1
            public final boolean onPreferenceChange(Preference preference, Object obj) {
                return PreferencesKt.initPreferences$lambda$39$lambda$38(sharedPreferences, preference, obj);
            }
        });
        Unit unit18 = Unit.INSTANCE;
        preferenceArr[17] = (Preference) listPreference8;
        EditTextPreference editTextPreference6 = new EditTextPreference(context);
        editTextPreference6.setKey(PreferencesKeys.USER_AGENT);
        editTextPreference6.setTitle("User-Agent");
        String str3 = String.format(PreferencesKeys.USER_AGENT_SUMMERY, Arrays.copyOf(new Object[]{getUserAgent(sharedPreferences)}, 1));
        Intrinsics.checkNotNullExpressionValue(str3, "format(this, *args)");
        editTextPreference6.setSummary(str3);
        editTextPreference6.setDefaultValue(PluginMetaData.USER_AGENT);
        editTextPreference6.setOnPreferenceChangeListener(new Preference.OnPreferenceChangeListener() { // from class: eu.kanade.tachiyomi.extension.zh.copymanga.PreferencesKt$$ExternalSyntheticLambda2
            public final boolean onPreferenceChange(Preference preference, Object obj) {
                return PreferencesKt.initPreferences$lambda$41$lambda$40(sharedPreferences, preference, obj);
            }
        });
        Unit unit19 = Unit.INSTANCE;
        preferenceArr[18] = (Preference) editTextPreference6;
        return preferenceArr;
    }

    private static final void initPreferences$ensureDefault(SharedPreferences sharedPreferences, String str, Object obj) {
        if (sharedPreferences.contains(str)) {
            return;
        }
        if (obj instanceof Boolean) {
            sharedPreferences.edit().putBoolean(str, ((Boolean) obj).booleanValue()).apply();
        } else if (obj instanceof String) {
            sharedPreferences.edit().putString(str, (String) obj).apply();
        }
    }

    private static final void initPreferences$fixInvalidValue(SharedPreferences sharedPreferences, String str, String[] strArr, String str2) {
        String string = sharedPreferences.getString(str, str2);
        Intrinsics.checkNotNull(string);
        if (ArraysKt.contains(strArr, string)) {
            return;
        }
        sharedPreferences.edit().putString(str, str2).apply();
    }

    /* JADX INFO: Access modifiers changed from: private */
    public static final boolean initPreferences$lambda$5$lambda$4(ListPreference listPreference, EditTextPreference editTextPreference, Preference preference, Object obj) {
        Intrinsics.checkNotNullParameter(listPreference, "$this_apply");
        Intrinsics.checkNotNullParameter(editTextPreference, "$customApiDomainPreferences");
        try {
            Result.Companion companion = Result.Companion;
            editTextPreference.setVisible(Intrinsics.areEqual(obj.toString(), ApiDomainOption.CUSTOM.getEntryKey()));
            Result.constructor-impl(Unit.INSTANCE);
            return true;
        } catch (Throwable th) {
            Result.Companion companion2 = Result.Companion;
            Result.constructor-impl(ResultKt.createFailure(th));
            return true;
        }
    }

    /* JADX INFO: Access modifiers changed from: private */
    public static final boolean initPreferences$lambda$8$lambda$6(EditTextPreference editTextPreference, Preference preference, Object obj) {
        Intrinsics.checkNotNullParameter(editTextPreference, "$this_apply");
        editTextPreference.setSummary(obj.toString());
        return true;
    }

    /* JADX INFO: Access modifiers changed from: private */
    public static final boolean initPreferences$lambda$11$lambda$10(ListPreference listPreference, EditTextPreference editTextPreference, Preference preference, Object obj) {
        Intrinsics.checkNotNullParameter(listPreference, "$this_apply");
        Intrinsics.checkNotNullParameter(editTextPreference, "$customWebViewDomainPreferences");
        try {
            Result.Companion companion = Result.Companion;
            editTextPreference.setVisible(Intrinsics.areEqual(obj.toString(), WebViewDomainOption.CUSTOM.getEntryKey()));
            Result.constructor-impl(Unit.INSTANCE);
            return true;
        } catch (Throwable th) {
            Result.Companion companion2 = Result.Companion;
            Result.constructor-impl(ResultKt.createFailure(th));
            return true;
        }
    }

    /* JADX INFO: Access modifiers changed from: private */
    public static final boolean initPreferences$lambda$14$lambda$12(EditTextPreference editTextPreference, Preference preference, Object obj) {
        Intrinsics.checkNotNullParameter(editTextPreference, "$this_apply");
        editTextPreference.setSummary(obj.toString());
        return true;
    }

    /* JADX INFO: Access modifiers changed from: private */
    public static final boolean initPreferences$lambda$20$lambda$19(SwitchPreferenceCompat switchPreferenceCompat, SwitchPreferenceCompat switchPreferenceCompat2, EditTextPreference editTextPreference, Preference preference, Object obj) {
        Intrinsics.checkNotNullParameter(switchPreferenceCompat, "$enableLoginPreference");
        Intrinsics.checkNotNullParameter(switchPreferenceCompat2, "$this_apply");
        Intrinsics.checkNotNullParameter(editTextPreference, "$loginCreditPreference");
        Intrinsics.checkNotNull(obj, "null cannot be cast to non-null type kotlin.Boolean");
        if (((Boolean) obj).booleanValue()) {
            TokenProvider.V2.INSTANCE.login(switchPreferenceCompat);
            TokenProvider.updateSummary$default(TokenProvider.INSTANCE, switchPreferenceCompat, null, 2, null);
        }
        try {
            Result.Companion companion = Result.Companion;
            editTextPreference.setVisible(((Boolean) obj).booleanValue());
            Result.constructor-impl(Unit.INSTANCE);
            return true;
        } catch (Throwable th) {
            Result.Companion companion2 = Result.Companion;
            Result.constructor-impl(ResultKt.createFailure(th));
            return true;
        }
    }

    /* JADX INFO: Access modifiers changed from: private */
    public static final boolean initPreferences$lambda$24$lambda$22(SwitchPreferenceCompat switchPreferenceCompat, SharedPreferences sharedPreferences, Preference preference, Object obj) {
        Intrinsics.checkNotNullParameter(switchPreferenceCompat, "$enableLoginPreference");
        Intrinsics.checkNotNullParameter(sharedPreferences, "$preferences");
        Intrinsics.checkNotNull(obj, "null cannot be cast to non-null type kotlin.String");
        String str = (String) obj;
        boolean z = str.length() == 0;
        if (!z) {
            TokenProvider.V1.INSTANCE.login(str, switchPreferenceCompat);
        }
        clearLoginCredentials(sharedPreferences);
        return z;
    }

    /* JADX INFO: Access modifiers changed from: private */
    public static final boolean initPreferences$lambda$28$lambda$27(SwitchPreferenceCompat switchPreferenceCompat, SwitchPreferenceCompat switchPreferenceCompat2, SwitchPreferenceCompat switchPreferenceCompat3, ListPreference listPreference, Preference preference, Object obj) {
        Intrinsics.checkNotNullParameter(switchPreferenceCompat, "$this_apply");
        Intrinsics.checkNotNullParameter(switchPreferenceCompat2, "$reserveChapterCommentPreference");
        Intrinsics.checkNotNullParameter(switchPreferenceCompat3, "$useCopyMangaCommentPreference");
        Intrinsics.checkNotNullParameter(listPreference, "$chapterCommentPerformModePreference");
        try {
            Result.Companion companion = Result.Companion;
            Intrinsics.checkNotNull(obj, "null cannot be cast to non-null type kotlin.Boolean");
            switchPreferenceCompat2.setVisible(((Boolean) obj).booleanValue());
            switchPreferenceCompat3.setVisible(((Boolean) obj).booleanValue());
            listPreference.setVisible(((Boolean) obj).booleanValue());
            Result.constructor-impl(Unit.INSTANCE);
            return true;
        } catch (Throwable th) {
            Result.Companion companion2 = Result.Companion;
            Result.constructor-impl(ResultKt.createFailure(th));
            return true;
        }
    }

    /* JADX INFO: Access modifiers changed from: private */
    public static final boolean initPreferences$lambda$36$lambda$35(ListPreference listPreference, Preference preference, Object obj) {
        Intrinsics.checkNotNullParameter(listPreference, "$this_apply");
        String str = String.format(ResolutionOption.SUMMERY, Arrays.copyOf(new Object[]{ResolutionOption.INSTANCE.key2value(obj.toString())}, 1));
        Intrinsics.checkNotNullExpressionValue(str, "format(this, *args)");
        listPreference.setSummary(str);
        return true;
    }

    /* JADX INFO: Access modifiers changed from: private */
    public static final boolean initPreferences$lambda$39$lambda$38(SharedPreferences sharedPreferences, Preference preference, Object obj) {
        Intrinsics.checkNotNullParameter(sharedPreferences, "$preferences");
        updatePlatformIndex(sharedPreferences, obj.toString());
        return true;
    }

    /* JADX INFO: Access modifiers changed from: private */
    public static final boolean initPreferences$lambda$41$lambda$40(SharedPreferences sharedPreferences, Preference preference, Object obj) {
        Intrinsics.checkNotNullParameter(sharedPreferences, "$preferences");
        boolean zAreEqual = Intrinsics.areEqual(obj, "reset");
        if (zAreEqual) {
            sharedPreferences.edit().putString(PreferencesKeys.USER_AGENT, PluginMetaData.USER_AGENT).apply();
        }
        if (zAreEqual) {
            obj = getUserAgent(sharedPreferences);
        }
        String str = String.format(PreferencesKeys.USER_AGENT_SUMMERY, Arrays.copyOf(new Object[]{obj}, 1));
        Intrinsics.checkNotNullExpressionValue(str, "format(this, *args)");
        preference.setSummary(str);
        return true ^ zAreEqual;
    }

    public static final String getApiDomainFromPrefs(SharedPreferences sharedPreferences) {
        Intrinsics.checkNotNullParameter(sharedPreferences, "<this>");
        String string = sharedPreferences.getString(ApiDomainOption.KEY, ApiDomainOption.INSTANCE.getDEFAULT());
        Intrinsics.checkNotNull(string);
        return string;
    }

    public static final String getCustomApiDomain(SharedPreferences sharedPreferences) {
        Intrinsics.checkNotNullParameter(sharedPreferences, "<this>");
        String string = sharedPreferences.getString(ApiDomainOption.KEY_CUSTOM, PluginMetaData.BASE_URL);
        Intrinsics.checkNotNull(string);
        return string;
    }

    public static final String getWebViewDomainFromPrefs(SharedPreferences sharedPreferences) {
        Intrinsics.checkNotNullParameter(sharedPreferences, "<this>");
        String string = sharedPreferences.getString(WebViewDomainOption.KEY, WebViewDomainOption.INSTANCE.getDEFAULT());
        Intrinsics.checkNotNull(string);
        return string;
    }

    public static final String getCustomWebViewDomain(SharedPreferences sharedPreferences) {
        Intrinsics.checkNotNullParameter(sharedPreferences, "<this>");
        String string = sharedPreferences.getString(WebViewDomainOption.KEY_CUSTOM, PluginMetaData.BASE_URL);
        Intrinsics.checkNotNull(string);
        return string;
    }

    public static final String getWebViewClientKey(SharedPreferences sharedPreferences) {
        Intrinsics.checkNotNullParameter(sharedPreferences, "<this>");
        String string = sharedPreferences.getString(WebViewClientOption.KEY, WebViewClientOption.INSTANCE.getDEFAULT_KEY());
        Intrinsics.checkNotNull(string);
        return string;
    }

    public static final String getLatestUpdateOptionPref(SharedPreferences sharedPreferences) {
        Intrinsics.checkNotNullParameter(sharedPreferences, "<this>");
        String string = sharedPreferences.getString(LatestUpdateOption.KEY, LatestUpdateOption.INSTANCE.getDEFAULT());
        Intrinsics.checkNotNull(string);
        return string;
    }

    public static final String getCcKeyPref(SharedPreferences sharedPreferences) {
        Intrinsics.checkNotNullParameter(sharedPreferences, "<this>");
        String string = sharedPreferences.getString(CCOption.KEY, CCOption.DEFAULT.getEntryKey());
        Intrinsics.checkNotNull(string);
        return string;
    }

    public static final boolean getShowMangaComments(SharedPreferences sharedPreferences) {
        Intrinsics.checkNotNullParameter(sharedPreferences, "<this>");
        return sharedPreferences.getBoolean(PreferencesKeys.SHOW_MANGA_COMMENTS, false);
    }

    public static final boolean getShowChapterComments(SharedPreferences sharedPreferences) {
        Intrinsics.checkNotNullParameter(sharedPreferences, "<this>");
        return sharedPreferences.getBoolean(PreferencesKeys.SHOW_CHAPTER_COMMENTS, false);
    }

    public static final boolean getReserveChapterComments(SharedPreferences sharedPreferences) {
        Intrinsics.checkNotNullParameter(sharedPreferences, "<this>");
        return sharedPreferences.getBoolean(PreferencesKeys.RESERVE_CHAPTER_COMMENTS, false);
    }

    /* renamed from: getChapterCommentPerformMode, reason: collision with other method in class */
    public static final String m6getChapterCommentPerformMode(SharedPreferences sharedPreferences) {
        Intrinsics.checkNotNullParameter(sharedPreferences, "<this>");
        String string = sharedPreferences.getString(ChapterCommentPerformOption.KEY, ChapterCommentPerformOption.INSTANCE.getDEFAULT());
        Intrinsics.checkNotNull(string);
        return string;
    }

    public static final boolean getUseCopyMangaComment(SharedPreferences sharedPreferences) {
        Intrinsics.checkNotNullParameter(sharedPreferences, "<this>");
        return sharedPreferences.getBoolean(PreferencesKeys.USE_COPYMANGA_COMMENT, true);
    }

    public static final String getImageResolutionKey(SharedPreferences sharedPreferences) {
        Intrinsics.checkNotNullParameter(sharedPreferences, "<this>");
        String string = sharedPreferences.getString(ResolutionOption.KEY, ResolutionOption.INSTANCE.getDEFAULT());
        Intrinsics.checkNotNull(string);
        return string;
    }

    public static final String getUserAgent(SharedPreferences sharedPreferences) {
        Intrinsics.checkNotNullParameter(sharedPreferences, "<this>");
        String string = sharedPreferences.getString(PreferencesKeys.USER_AGENT, PluginMetaData.USER_AGENT);
        Intrinsics.checkNotNull(string);
        return string;
    }

    public static final String getHideDefaultContinuousChapter(SharedPreferences sharedPreferences) {
        Intrinsics.checkNotNullParameter(sharedPreferences, "<this>");
        String string = sharedPreferences.getString(PreferencesKeys.HIDE_DEFAULT_CONTINUOUS_CHAPTER, "");
        Intrinsics.checkNotNull(string);
        return string;
    }

    public static final String getPlatFormOptionKey(SharedPreferences sharedPreferences) {
        Intrinsics.checkNotNullParameter(sharedPreferences, "<this>");
        String string = sharedPreferences.getString(PlatFormOption.KEY, PlatFormOption.INSTANCE.getDEFAULT());
        Intrinsics.checkNotNull(string);
        return string;
    }

    public static final boolean getEnableLogin(SharedPreferences sharedPreferences) {
        Intrinsics.checkNotNullParameter(sharedPreferences, "<this>");
        return sharedPreferences.getBoolean(PreferencesKeys.ENABLE_LOGIN, false);
    }

    public static final String getLoginCredentials(SharedPreferences sharedPreferences) {
        Intrinsics.checkNotNullParameter(sharedPreferences, "<this>");
        String string = sharedPreferences.getString(PreferencesKeys.LOGIN_CREDENTIALS, "");
        Intrinsics.checkNotNull(string);
        return string;
    }

    public static final String getCopyMangaToken(SharedPreferences sharedPreferences) {
        Intrinsics.checkNotNullParameter(sharedPreferences, "<this>");
        String string = sharedPreferences.getString(PreferencesKeys.COPY_MANGA_TOKEN, "");
        Intrinsics.checkNotNull(string);
        return string;
    }

    public static final String getHotMangaToken(SharedPreferences sharedPreferences) {
        Intrinsics.checkNotNullParameter(sharedPreferences, "<this>");
        String string = sharedPreferences.getString(PreferencesKeys.HOT_MANGA_TOKEN, "");
        Intrinsics.checkNotNull(string);
        return string;
    }

    public static final CCOption getCCOption(SharedPreferences sharedPreferences) {
        Intrinsics.checkNotNullParameter(sharedPreferences, "<this>");
        return CCOption.INSTANCE.key2mode(getCcKeyPref(sharedPreferences));
    }

    public static final String getHttpApiDomain(SharedPreferences sharedPreferences) {
        Intrinsics.checkNotNullParameter(sharedPreferences, "<this>");
        return ApiDomainOption.INSTANCE.toHttpsUrl(getApiDomainFromPrefs(sharedPreferences), getCustomApiDomain(sharedPreferences));
    }

    public static final String getHttpWebViewDomain(SharedPreferences sharedPreferences) {
        Intrinsics.checkNotNullParameter(sharedPreferences, "<this>");
        return WebViewDomainOption.INSTANCE.toHttpsUrl(getWebViewDomainFromPrefs(sharedPreferences), getCustomWebViewDomain(sharedPreferences));
    }

    public static final LatestUpdateOption getLatestUpdateMode(SharedPreferences sharedPreferences) {
        Intrinsics.checkNotNullParameter(sharedPreferences, "<this>");
        return LatestUpdateOption.INSTANCE.key2mode(getLatestUpdateOptionPref(sharedPreferences));
    }

    public static final ChapterCommentPerformOption getChapterCommentPerformMode(SharedPreferences sharedPreferences) {
        Intrinsics.checkNotNullParameter(sharedPreferences, "<this>");
        return ChapterCommentPerformOption.INSTANCE.key2mode(m6getChapterCommentPerformMode(sharedPreferences));
    }

    public static final WebViewClientOption getWebViewClientType(SharedPreferences sharedPreferences) {
        Intrinsics.checkNotNullParameter(sharedPreferences, "<this>");
        return WebViewClientOption.INSTANCE.key2type(getWebViewClientKey(sharedPreferences));
    }

    public static final UserAgentType getUserAgentType(SharedPreferences sharedPreferences) {
        Intrinsics.checkNotNullParameter(sharedPreferences, "<this>");
        return UserAgentType.INSTANCE.getType(getUserAgent(sharedPreferences));
    }

    public static final String getImageResolution(SharedPreferences sharedPreferences) {
        Intrinsics.checkNotNullParameter(sharedPreferences, "<this>");
        return ResolutionOption.INSTANCE.key2value(getImageResolutionKey(sharedPreferences));
    }

    public static final void updatePlatformIndex(SharedPreferences sharedPreferences, String str) {
        Intrinsics.checkNotNullParameter(sharedPreferences, "<this>");
        Intrinsics.checkNotNullParameter(str, "params");
        sharedPreferences.edit().putString(PlatFormOption.KEY, str).apply();
    }

    public static final void clearLoginCredentials(SharedPreferences sharedPreferences) {
        Intrinsics.checkNotNullParameter(sharedPreferences, "<this>");
        sharedPreferences.edit().putString(PreferencesKeys.LOGIN_CREDENTIALS, "").apply();
    }

    public static final void setCopyMangaToken(SharedPreferences sharedPreferences, String str) {
        Intrinsics.checkNotNullParameter(sharedPreferences, "<this>");
        Intrinsics.checkNotNullParameter(str, "token");
        sharedPreferences.edit().putString(PreferencesKeys.COPY_MANGA_TOKEN, str).apply();
    }

    public static final void setHotMangaToken(SharedPreferences sharedPreferences, String str) {
        Intrinsics.checkNotNullParameter(sharedPreferences, "<this>");
        Intrinsics.checkNotNullParameter(str, "token");
        sharedPreferences.edit().putString(PreferencesKeys.HOT_MANGA_TOKEN, str).apply();
    }
}
