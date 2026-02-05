package eu.kanade.tachiyomi.extension.zh.copymanga.api;

import android.content.SharedPreferences;
import eu.kanade.tachiyomi.extension.zh.copymanga.ApiDomainOption;
import eu.kanade.tachiyomi.extension.zh.copymanga.PreferencesKt;
import java.util.ArrayList;
import java.util.List;
import kotlin.Lazy;
import kotlin.LazyKt;
import kotlin.Metadata;
import kotlin.jvm.functions.Function0;
import kotlin.jvm.internal.Intrinsics;
import kotlin.text.StringsKt;
import okhttp3.Headers;

/* compiled from: ApiRepo.kt */
@Metadata(d1 = {"\u0000.\n\u0002\u0018\u0002\n\u0002\u0010\u0000\n\u0002\b\u0002\n\u0002\u0018\u0002\n\u0002\b\u0005\n\u0002\u0010 \n\u0002\u0010\u000e\n\u0002\b\b\n\u0002\u0010\b\n\u0000\n\u0002\u0018\u0002\n\u0002\b\u001f\bÆ\u0002\u0018\u00002\u00020\u0001B\u0007\b\u0002¢\u0006\u0002\u0010\u0002J\u000e\u0010\u001b\u001a\u00020\u000b2\u0006\u0010\u001c\u001a\u00020\u000bJ\u000e\u0010\u001d\u001a\u00020\u000b2\u0006\u0010\u001c\u001a\u00020\u000bJ\u001e\u0010\u001e\u001a\u00020\u000b2\u0006\u0010\u001f\u001a\u00020\u000b2\u0006\u0010 \u001a\u00020\u000b2\u0006\u0010!\u001a\u00020\u0014J\u000e\u0010\"\u001a\u00020\u000b2\u0006\u0010\u001f\u001a\u00020\u000bJ\u000e\u0010#\u001a\u00020\u000b2\u0006\u0010$\u001a\u00020\u0014J\u000e\u0010%\u001a\u00020\u000b2\u0006\u0010$\u001a\u00020\u0014J\u000e\u0010&\u001a\u00020\u000b2\u0006\u0010'\u001a\u00020\u000bJ\u000e\u0010(\u001a\u00020\u000b2\u0006\u0010\u001c\u001a\u00020\u000bJ\u0006\u0010)\u001a\u00020\u000bJ\"\u0010*\u001a\u00020\u000b2\u0006\u0010+\u001a\u00020\u000b2\b\b\u0002\u0010,\u001a\u00020\u00142\b\b\u0002\u0010!\u001a\u00020\u0014J\u000e\u0010-\u001a\u00020\u000b2\u0006\u0010$\u001a\u00020\u0014J\u000e\u0010.\u001a\u00020\u000b2\u0006\u0010$\u001a\u00020\u0014J\u000e\u0010/\u001a\u00020\u000b2\u0006\u0010$\u001a\u00020\u0014J\u000e\u00100\u001a\u00020\u000b2\u0006\u0010$\u001a\u00020\u0014J\u000e\u00101\u001a\u00020\u000b2\u0006\u0010$\u001a\u00020\u0014J\u0006\u00102\u001a\u00020\u000bJ\u000e\u00103\u001a\u00020\u000b2\u0006\u00104\u001a\u00020\u000bR\u0011\u0010\u0003\u001a\u00020\u0004¢\u0006\b\n\u0000\u001a\u0004\b\u0005\u0010\u0006R\u0011\u0010\u0007\u001a\u00020\u0004¢\u0006\b\n\u0000\u001a\u0004\b\b\u0010\u0006R!\u0010\t\u001a\b\u0012\u0004\u0012\u00020\u000b0\n8FX\u0086\u0084\u0002¢\u0006\f\n\u0004\b\u000e\u0010\u000f\u001a\u0004\b\f\u0010\rR\u0014\u0010\u0010\u001a\u00020\u000b8BX\u0082\u0004¢\u0006\u0006\u001a\u0004\b\u0011\u0010\u0012R\u000e\u0010\u0013\u001a\u00020\u0014X\u0082T¢\u0006\u0002\n\u0000R\u001a\u0010\u0015\u001a\u00020\u0016X\u0086.¢\u0006\u000e\n\u0000\u001a\u0004\b\u0017\u0010\u0018\"\u0004\b\u0019\u0010\u001a¨\u00065"}, d2 = {"Leu/kanade/tachiyomi/extension/zh/copymanga/api/ApiRepo;", "", "()V", "COPY_MANGA_HEADER", "Lokhttp3/Headers;", "getCOPY_MANGA_HEADER", "()Lokhttp3/Headers;", "HOT_MANGA_HEADER", "getHOT_MANGA_HEADER", "RATE_LIMIT_DOMAIN", "", "", "getRATE_LIMIT_DOMAIN", "()Ljava/util/List;", "RATE_LIMIT_DOMAIN$delegate", "Lkotlin/Lazy;", "apiUrl", "getApiUrl", "()Ljava/lang/String;", "pageSize", "", "preferences", "Landroid/content/SharedPreferences;", "getPreferences", "()Landroid/content/SharedPreferences;", "setPreferences", "(Landroid/content/SharedPreferences;)V", "chapterCommentUrl", "chapterId", "chapterContentDetailUrl", "chapterListUrl", "comicPath", "group", "offset", "comicDetailUrl", "comicListUrl", "page", "comicRankUrl", "commentUrl2comicId", "commentUrl", "fixChapterId", "loginURL", "mangaCommentUrl", "comicId", "limit", "memberCollectUrl", "newestPageUrl", "newestPageUrl_update", "recommendPageUrl", "searchUrl", "tagList", "url2comicPath", "comicUrl", "tachiyomi-zh.copymanga-v1.4.78_release"}, k = 1, mv = {1, 7, 1}, xi = 48)
/* loaded from: classes.dex */
public final class ApiRepo {
    private static final int pageSize = 21;
    public static SharedPreferences preferences;
    public static final ApiRepo INSTANCE = new ApiRepo();
    private static final Headers COPY_MANGA_HEADER = Headers.Companion.of(new String[]{"Accept", "application/json", "Accept-Language", "en-US,en;q=0.9,zh-TW;q=0.8,zh;q=0.7", "Origin", "https://2025copy.com", "Version", "2025.11.21", "Region", "0", "Webp", "0"});
    private static final Headers HOT_MANGA_HEADER = Headers.Companion.of(new String[]{"Accept", "application/json", "Accept-Language", "en-US,en;q=0.9,zh-TW;q=0.8,zh;q=0.7", "Origin", "https://m.relamanhua.org", "Version", "2025.11.21", "Webp", "1"});

    /* renamed from: RATE_LIMIT_DOMAIN$delegate, reason: from kotlin metadata */
    private static final Lazy RATE_LIMIT_DOMAIN = LazyKt.lazy(new Function0<List<? extends String>>() { // from class: eu.kanade.tachiyomi.extension.zh.copymanga.api.ApiRepo$RATE_LIMIT_DOMAIN$2
        public final List<String> invoke() {
            ApiDomainOption[] apiDomainOptionArrValues = ApiDomainOption.values();
            ArrayList arrayList = new ArrayList(apiDomainOptionArrValues.length);
            for (ApiDomainOption apiDomainOption : apiDomainOptionArrValues) {
                arrayList.add(apiDomainOption.getEntry());
            }
            return arrayList;
        }
    });

    private ApiRepo() {
    }

    public final SharedPreferences getPreferences() {
        SharedPreferences sharedPreferences = preferences;
        if (sharedPreferences != null) {
            return sharedPreferences;
        }
        Intrinsics.throwUninitializedPropertyAccessException("preferences");
        return null;
    }

    public final void setPreferences(SharedPreferences sharedPreferences) {
        Intrinsics.checkNotNullParameter(sharedPreferences, "<set-?>");
        preferences = sharedPreferences;
    }

    private final String getApiUrl() {
        return PreferencesKt.getHttpApiDomain(getPreferences()) + "/api/v3";
    }

    public final Headers getCOPY_MANGA_HEADER() {
        return COPY_MANGA_HEADER;
    }

    public final Headers getHOT_MANGA_HEADER() {
        return HOT_MANGA_HEADER;
    }

    public final List<String> getRATE_LIMIT_DOMAIN() {
        return (List) RATE_LIMIT_DOMAIN.getValue();
    }

    public final String url2comicPath(String comicUrl) {
        Intrinsics.checkNotNullParameter(comicUrl, "comicUrl");
        return StringsKt.substringAfter$default(StringsKt.substringAfter$default(comicUrl, "/comic/", (String) null, 2, (Object) null), "/comic2/", (String) null, 2, (Object) null);
    }

    public final String commentUrl2comicId(String commentUrl) {
        Intrinsics.checkNotNullParameter(commentUrl, "commentUrl");
        return StringsKt.substringAfter$default(commentUrl, "comicId=", (String) null, 2, (Object) null);
    }

    public final String fixChapterId(String chapterId) {
        Intrinsics.checkNotNullParameter(chapterId, "chapterId");
        String strRemovePrefix = StringsKt.removePrefix(chapterId, "/comic/");
        return ApiDomainOption.INSTANCE.isHotManga(PreferencesKt.getApiDomainFromPrefs(getPreferences())) ? strRemovePrefix : StringsKt.replace$default(strRemovePrefix, "/chapter/", "/chapter2/", false, 4, (Object) null);
    }

    public final String loginURL() {
        return getApiUrl() + "/login";
    }

    public final String tagList() {
        return getApiUrl() + "/theme/comic/count?limit=100";
    }

    public final String newestPageUrl(int page) {
        return getApiUrl() + "/update/newest?limit=21&offset=" + ((page - 1) * pageSize);
    }

    public final String newestPageUrl_update(int page) {
        return getApiUrl() + "/comics?limit=21&offset=" + ((page - 1) * pageSize) + "&ordering=-datetime_updated";
    }

    public final String recommendPageUrl(int page) {
        return getApiUrl() + "/recs?pos=3200102&limit=21&offset=" + ((page - 1) * pageSize);
    }

    public final String searchUrl(int page) {
        return getApiUrl() + "/search/comic?limit=21&offset=" + ((page - 1) * pageSize);
    }

    public final String comicListUrl(int page) {
        return getApiUrl() + "/comics?limit=21&offset=" + ((page - 1) * pageSize);
    }

    public final String comicRankUrl(int page) {
        return getApiUrl() + "/ranks?type=1&limit=21&offset=" + ((page - 1) * pageSize);
    }

    public final String comicDetailUrl(String comicPath) {
        Intrinsics.checkNotNullParameter(comicPath, "comicPath");
        return getApiUrl() + "/comic2/" + comicPath;
    }

    public final String chapterListUrl(String comicPath, String group, int offset) {
        Intrinsics.checkNotNullParameter(comicPath, "comicPath");
        Intrinsics.checkNotNullParameter(group, "group");
        return getApiUrl() + "/comic/" + comicPath + "/group/" + group + "/chapters?limit=100&offset=" + offset + "&_update=true";
    }

    public final String chapterContentDetailUrl(String chapterId) {
        Intrinsics.checkNotNullParameter(chapterId, "chapterId");
        return getApiUrl() + "/comic/" + chapterId;
    }

    public static /* synthetic */ String mangaCommentUrl$default(ApiRepo apiRepo, String str, int i, int i2, int i3, Object obj) {
        if ((i3 & 2) != 0) {
            i = 9999;
        }
        if ((i3 & 4) != 0) {
            i2 = 0;
        }
        return apiRepo.mangaCommentUrl(str, i, i2);
    }

    public final String mangaCommentUrl(String comicId, int limit, int offset) {
        String apiUrl;
        Intrinsics.checkNotNullParameter(comicId, "comicId");
        StringBuilder sb = new StringBuilder();
        if (ApiDomainOption.INSTANCE.isHotManga(getApiUrl())) {
            apiUrl = "https://" + ApiDomainOption.COPY5.getEntry() + "/api/v3";
        } else {
            apiUrl = getApiUrl();
        }
        sb.append(apiUrl);
        sb.append("/comments?comic_id=");
        sb.append(comicId);
        sb.append("&limit=");
        sb.append(limit);
        sb.append("&offset=");
        sb.append(offset);
        return sb.toString();
    }

    public final String chapterCommentUrl(String chapterId) {
        String apiUrl;
        Intrinsics.checkNotNullParameter(chapterId, "chapterId");
        StringBuilder sb = new StringBuilder();
        if (PreferencesKt.getUseCopyMangaComment(getPreferences()) && ApiDomainOption.INSTANCE.isHotManga(getApiUrl())) {
            apiUrl = "https://" + ApiDomainOption.COPY5.getEntry() + "/api/v3";
        } else {
            apiUrl = getApiUrl();
        }
        sb.append(apiUrl);
        sb.append("/roasts?limit=100&chapter_id=");
        sb.append(chapterId);
        return sb.toString();
    }

    public final String memberCollectUrl(int page) {
        return getApiUrl() + "/member/collect/comics?limit=21&offset=" + ((page - 1) * pageSize) + "&ordering=-datetime_modifier";
    }
}
