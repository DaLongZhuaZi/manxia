package eu.kanade.tachiyomi.extension.zh.copymanga;

import kotlin.Metadata;

/* JADX INFO: compiled from: Constants.kt */
/* JADX INFO: loaded from: classes.dex */
@Metadata(d1 = {"\u0000\u0014\n\u0002\u0018\u0002\n\u0002\u0010\u0000\n\u0002\b\u0002\n\u0002\u0010\u000e\n\u0002\b\f\bÆ\u0002\u0018\u00002\u00020\u0001B\u0007\b\u0002¢\u0006\u0002\u0010\u0002R\u000e\u0010\u0003\u001a\u00020\u0004X\u0086T¢\u0006\u0002\n\u0000R\u000e\u0010\u0005\u001a\u00020\u0004X\u0086T¢\u0006\u0002\n\u0000R\u000e\u0010\u0006\u001a\u00020\u0004X\u0086T¢\u0006\u0002\n\u0000R\u000e\u0010\u0007\u001a\u00020\u0004X\u0086T¢\u0006\u0002\n\u0000R\u000e\u0010\b\u001a\u00020\u0004X\u0086T¢\u0006\u0002\n\u0000R\u000e\u0010\t\u001a\u00020\u0004X\u0086T¢\u0006\u0002\n\u0000R\u000e\u0010\n\u001a\u00020\u0004X\u0086T¢\u0006\u0002\n\u0000R\u000e\u0010\u000b\u001a\u00020\u0004X\u0086T¢\u0006\u0002\n\u0000R\u000e\u0010\f\u001a\u00020\u0004X\u0086T¢\u0006\u0002\n\u0000R\u000e\u0010\r\u001a\u00020\u0004X\u0086T¢\u0006\u0002\n\u0000R\u000e\u0010\u000e\u001a\u00020\u0004X\u0086T¢\u0006\u0002\n\u0000R\u000e\u0010\u000f\u001a\u00020\u0004X\u0086T¢\u0006\u0002\n\u0000¨\u0006\u0010"}, d2 = {"Leu/kanade/tachiyomi/extension/zh/copymanga/PreferencesKeys;", "", "()V", "COPY_MANGA_TOKEN", "", "ENABLE_LOGIN", "ENABLE_LOGIN_SUMMERY", "HIDE_DEFAULT_CONTINUOUS_CHAPTER", "HOT_MANGA_TOKEN", "LOGIN_CREDENTIALS", "ONLY_UPDATE_LINK", "RESERVE_CHAPTER_COMMENTS", "SHOW_CHAPTER_COMMENTS", "SHOW_MANGA_COMMENTS", "USER_AGENT", "USER_AGENT_SUMMERY", "tachiyomi-zh.copymanga-v1.4.82_release"}, k = 1, mv = {1, 7, 1}, xi = 48)
public final class PreferencesKeys {
    public static final String COPY_MANGA_TOKEN = "v2.key.copy_manga_token";
    public static final String ENABLE_LOGIN = "v2.key.enable_login";
    public static final String ENABLE_LOGIN_SUMMERY = "启用后，将使用登入状态搜寻/载入漫画，重启此选项刷新登入信息\n重新支持透过WebView登入，重启此选项后，会侦测目前选择的WebView域名登入\n拷貝登入狀態 : %s\n熱辣登入狀態 : %s\n";
    public static final String HIDE_DEFAULT_CONTINUOUS_CHAPTER = "v2.key.hide_default_continuous_chapter";
    public static final String HOT_MANGA_TOKEN = "v2.key.hot_manga_token";
    public static final PreferencesKeys INSTANCE = new PreferencesKeys();
    public static final String LOGIN_CREDENTIALS = "v2.key.login_credentials";
    public static final String ONLY_UPDATE_LINK = "v2.key.extension_update_link";
    public static final String RESERVE_CHAPTER_COMMENTS = "v2.key.reserve_chapter_comments";
    public static final String SHOW_CHAPTER_COMMENTS = "v2.key.show_chapter_comments";
    public static final String SHOW_MANGA_COMMENTS = "v2.key.show_manga_comments";
    public static final String USER_AGENT = "v2.key.user_agent";
    public static final String USER_AGENT_SUMMERY = "%s \n用户代理字符串：\n输入 reset 恢复默认\n输入 desktop 设置为 随机 Windows 代理\n输入 mobile 设置为 随机 移动端 代理\n输入 app 設置為 App 默認 代理字串\n输入 none 禁用 User-Agent";

    private PreferencesKeys() {
    }
}
