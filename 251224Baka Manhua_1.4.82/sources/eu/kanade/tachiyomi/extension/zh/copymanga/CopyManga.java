package eu.kanade.tachiyomi.extension.zh.copymanga;

import android.app.Application;
import android.content.Context;
import android.content.SharedPreferences;
import androidx.preference.Preference;
import androidx.preference.PreferenceScreen;
import eu.kanade.tachiyomi.extension.zh.copymanga.api.ApiRepo;
import eu.kanade.tachiyomi.extension.zh.copymanga.api.ApiResponse;
import eu.kanade.tachiyomi.extension.zh.copymanga.api.ApiResponseKt;
import eu.kanade.tachiyomi.extension.zh.copymanga.api.dto.ChapterInfo;
import eu.kanade.tachiyomi.extension.zh.copymanga.api.dto.ChapterListResult;
import eu.kanade.tachiyomi.extension.zh.copymanga.api.dto.CollectInfo;
import eu.kanade.tachiyomi.extension.zh.copymanga.api.dto.CollectResult;
import eu.kanade.tachiyomi.extension.zh.copymanga.api.dto.ComicDetailResult;
import eu.kanade.tachiyomi.extension.zh.copymanga.api.dto.ComicSummary;
import eu.kanade.tachiyomi.extension.zh.copymanga.api.dto.ComicsListResult;
import eu.kanade.tachiyomi.extension.zh.copymanga.api.dto.GroupInfo;
import eu.kanade.tachiyomi.extension.zh.copymanga.api.dto.ListItem;
import eu.kanade.tachiyomi.extension.zh.copymanga.api.dto.NewestItem;
import eu.kanade.tachiyomi.extension.zh.copymanga.api.dto.NewestResult;
import eu.kanade.tachiyomi.extension.zh.copymanga.api.dto.RankResult;
import eu.kanade.tachiyomi.extension.zh.copymanga.api.dto.RecommendResult;
import eu.kanade.tachiyomi.extension.zh.copymanga.api.dto.Recommendation;
import eu.kanade.tachiyomi.extension.zh.copymanga.api.dto.SearchComic;
import eu.kanade.tachiyomi.extension.zh.copymanga.api.dto.SearchResult;
import eu.kanade.tachiyomi.extension.zh.copymanga.interceptor.AuthorizationInterceptor;
import eu.kanade.tachiyomi.extension.zh.copymanga.interceptor.ExceptionInterceptor;
import eu.kanade.tachiyomi.extension.zh.copymanga.interceptor.HeadersInterceptor;
import eu.kanade.tachiyomi.extension.zh.copymanga.interceptor.RateLimitInterceptor;
import eu.kanade.tachiyomi.extension.zh.copymanga.interceptor.ResponseErrorInterceptor;
import eu.kanade.tachiyomi.extension.zh.copymanga.interceptor.UserAgentInterceptor;
import eu.kanade.tachiyomi.extension.zh.copymanga.special.TokenProvider;
import eu.kanade.tachiyomi.lib.textinterceptor.TextInterceptor;
import eu.kanade.tachiyomi.network.RequestsKt;
import eu.kanade.tachiyomi.source.ConfigurableSource;
import eu.kanade.tachiyomi.source.model.Filter;
import eu.kanade.tachiyomi.source.model.FilterList;
import eu.kanade.tachiyomi.source.model.MangasPage;
import eu.kanade.tachiyomi.source.model.Page;
import eu.kanade.tachiyomi.source.model.SChapter;
import eu.kanade.tachiyomi.source.model.SManga;
import eu.kanade.tachiyomi.source.online.HttpSource;
import java.util.ArrayList;
import java.util.Comparator;
import java.util.Iterator;
import java.util.List;
import java.util.Map;
import java.util.Set;
import java.util.concurrent.Callable;
import java.util.concurrent.TimeUnit;
import kotlin.Metadata;
import kotlin.NoWhenBranchMatchedException;
import kotlin.Unit;
import kotlin.collections.CollectionsKt;
import kotlin.comparisons.ComparisonsKt;
import kotlin.jvm.internal.DefaultConstructorMarker;
import kotlin.jvm.internal.Intrinsics;
import kotlin.jvm.internal.MagicApiIntrinsics;
import kotlin.jvm.internal.Reflection;
import kotlin.reflect.KType;
import kotlin.reflect.KTypeProjection;
import kotlin.text.StringsKt;
import kotlinx.serialization.SerializersKt;
import kotlinx.serialization.StringFormat;
import kotlinx.serialization.modules.SerializersModule;
import okhttp3.CacheControl;
import okhttp3.CookieJar;
import okhttp3.Headers;
import okhttp3.HttpUrl;
import okhttp3.OkHttpClient;
import okhttp3.Request;
import okhttp3.Response;
import rx.Observable;
import uy.kohesive.injekt.InjektKt;
import uy.kohesive.injekt.api.FullTypeReference;

/* JADX INFO: compiled from: CopyManga.kt */
/* JADX INFO: loaded from: classes.dex */
@Metadata(d1 = {"\u0000\u0084\u0001\n\u0002\u0018\u0002\n\u0002\u0018\u0002\n\u0002\u0018\u0002\n\u0002\b\u0002\n\u0002\u0010\u000e\n\u0002\b\u0003\n\u0002\u0018\u0002\n\u0002\b\u0005\n\u0002\u0018\u0002\n\u0002\b\u0005\n\u0002\u0018\u0002\n\u0000\n\u0002\u0010\u000b\n\u0002\b\u0004\n\u0002\u0010 \n\u0002\u0018\u0002\n\u0000\n\u0002\u0018\u0002\n\u0000\n\u0002\u0018\u0002\n\u0000\n\u0002\u0018\u0002\n\u0000\n\u0002\u0018\u0002\n\u0000\n\u0002\u0018\u0002\n\u0002\b\u0003\n\u0002\u0018\u0002\n\u0002\b\u0003\n\u0002\u0018\u0002\n\u0002\b\u0002\n\u0002\u0010\b\n\u0002\b\n\n\u0002\u0010\u0002\n\u0000\n\u0002\u0018\u0002\n\u0000\u0018\u00002\u00020\u00012\u00020\u0002B\u0005¢\u0006\u0002\u0010\u0003J\b\u0010\u001a\u001a\u00020\tH\u0002J\u0016\u0010\u001b\u001a\b\u0012\u0004\u0012\u00020\u001d0\u001c2\u0006\u0010\u001e\u001a\u00020\u001fH\u0014J\u0010\u0010 \u001a\u00020!2\u0006\u0010\"\u001a\u00020#H\u0014J\u001c\u0010$\u001a\u000e\u0012\n\u0012\b\u0012\u0004\u0012\u00020\u001d0\u001c0%2\u0006\u0010\"\u001a\u00020#H\u0016J\u001c\u0010&\u001a\u000e\u0012\n\u0012\b\u0012\u0004\u0012\u00020'0\u001c0%2\u0006\u0010(\u001a\u00020\u001dH\u0016J\u0010\u0010)\u001a\u00020\u00052\u0006\u0010(\u001a\u00020\u001dH\u0016J\b\u0010*\u001a\u00020+H\u0016J\u0010\u0010,\u001a\u00020\u00052\u0006\u0010\"\u001a\u00020#H\u0016J\u0010\u0010-\u001a\u00020\u00052\u0006\u0010\u001e\u001a\u00020\u001fH\u0014J\u0010\u0010.\u001a\u00020/2\u0006\u0010\u001e\u001a\u00020\u001fH\u0014J\u0010\u00100\u001a\u00020!2\u0006\u00101\u001a\u000202H\u0014J\u0010\u00103\u001a\u00020#2\u0006\u0010\u001e\u001a\u00020\u001fH\u0014J\u0010\u00104\u001a\u00020!2\u0006\u0010\"\u001a\u00020#H\u0016J\u0016\u00105\u001a\b\u0012\u0004\u0012\u00020'0\u001c2\u0006\u0010\u001e\u001a\u00020\u001fH\u0014J\u0010\u00106\u001a\u00020/2\u0006\u0010\u001e\u001a\u00020\u001fH\u0014J\u0010\u00107\u001a\u00020!2\u0006\u00101\u001a\u000202H\u0014J\u0010\u00108\u001a\u00020/2\u0006\u0010\u001e\u001a\u00020\u001fH\u0014J \u00109\u001a\u00020!2\u0006\u00101\u001a\u0002022\u0006\u0010:\u001a\u00020\u00052\u0006\u0010;\u001a\u00020+H\u0014J\u0010\u0010<\u001a\u00020=2\u0006\u0010>\u001a\u00020?H\u0016R\u0014\u0010\u0004\u001a\u00020\u0005X\u0096D¢\u0006\b\n\u0000\u001a\u0004\b\u0006\u0010\u0007R\u001a\u0010\b\u001a\u00020\tX\u0096\u000e¢\u0006\u000e\n\u0000\u001a\u0004\b\n\u0010\u000b\"\u0004\b\f\u0010\rR\u000e\u0010\u000e\u001a\u00020\u000fX\u0082\u0004¢\u0006\u0002\n\u0000R\u0014\u0010\u0010\u001a\u00020\u0005X\u0096D¢\u0006\b\n\u0000\u001a\u0004\b\u0011\u0010\u0007R\u0014\u0010\u0012\u001a\u00020\u0005X\u0096D¢\u0006\b\n\u0000\u001a\u0004\b\u0013\u0010\u0007R\u000e\u0010\u0014\u001a\u00020\u0015X\u0082\u0004¢\u0006\u0002\n\u0000R\u0014\u0010\u0016\u001a\u00020\u0017X\u0096D¢\u0006\b\n\u0000\u001a\u0004\b\u0018\u0010\u0019¨\u0006@"}, d2 = {"Leu/kanade/tachiyomi/extension/zh/copymanga/CopyManga;", "Leu/kanade/tachiyomi/source/online/HttpSource;", "Leu/kanade/tachiyomi/source/ConfigurableSource;", "()V", "baseUrl", "", "getBaseUrl", "()Ljava/lang/String;", "client", "Lokhttp3/OkHttpClient;", "getClient", "()Lokhttp3/OkHttpClient;", "setClient", "(Lokhttp3/OkHttpClient;)V", "httpCache", "Lokhttp3/CacheControl;", "lang", "getLang", "name", "getName", "preferences", "Landroid/content/SharedPreferences;", "supportsLatest", "", "getSupportsLatest", "()Z", "buildClient", "chapterListParse", "", "Leu/kanade/tachiyomi/source/model/SChapter;", "response", "Lokhttp3/Response;", "chapterListRequest", "Lokhttp3/Request;", "manga", "Leu/kanade/tachiyomi/source/model/SManga;", "fetchChapterList", "Lrx/Observable;", "fetchPageList", "Leu/kanade/tachiyomi/source/model/Page;", "chapter", "getChapterUrl", "getFilterList", "Leu/kanade/tachiyomi/source/model/FilterList;", "getMangaUrl", "imageUrlParse", "latestUpdatesParse", "Leu/kanade/tachiyomi/source/model/MangasPage;", "latestUpdatesRequest", "page", "", "mangaDetailsParse", "mangaDetailsRequest", "pageListParse", "popularMangaParse", "popularMangaRequest", "searchMangaParse", "searchMangaRequest", "query", "filters", "setupPreferenceScreen", "", "screen", "Landroidx/preference/PreferenceScreen;", "tachiyomi-zh.copymanga-v1.4.82_release"}, k = 1, mv = {1, 7, 1}, xi = 48)
public final class CopyManga extends HttpSource implements ConfigurableSource {
    private OkHttpClient client;
    private final CacheControl httpCache;
    private final SharedPreferences preferences;
    private final String lang = PluginMetaData.LANG;
    private final String baseUrl = PluginMetaData.BASE_URL;
    private final String name = PluginMetaData.APP_NAME;
    private final boolean supportsLatest = true;

    /* JADX INFO: compiled from: CopyManga.kt */
    @Metadata(k = 3, mv = {1, 7, 1}, xi = 48)
    public /* synthetic */ class WhenMappings {
        public static final /* synthetic */ int[] $EnumSwitchMapping$0;
        public static final /* synthetic */ int[] $EnumSwitchMapping$1;

        static {
            int[] iArr = new int[LatestUpdateOption.values().length];
            try {
                iArr[LatestUpdateOption.NEW_BOOKS.ordinal()] = 1;
            } catch (NoSuchFieldError unused) {
            }
            try {
                iArr[LatestUpdateOption.LATEST_UPDATE.ordinal()] = 2;
            } catch (NoSuchFieldError unused2) {
            }
            $EnumSwitchMapping$0 = iArr;
            int[] iArr2 = new int[ChapterCommentPerformOption.values().length];
            try {
                iArr2[ChapterCommentPerformOption.SEPARATE.ordinal()] = 1;
            } catch (NoSuchFieldError unused3) {
            }
            try {
                iArr2[ChapterCommentPerformOption.MERGE.ordinal()] = 2;
            } catch (NoSuchFieldError unused4) {
            }
            $EnumSwitchMapping$1 = iArr2;
        }
    }

    public CopyManga() {
        long id = getId();
        SharedPreferences sharedPreferences = ((Application) InjektKt.getInjekt().getInstance(new FullTypeReference<Application>() { // from class: eu.kanade.tachiyomi.extension.zh.copymanga.CopyManga$special$$inlined$getPreferences$default$1
        }.getType())).getSharedPreferences("source_" + id, 0);
        Intrinsics.checkNotNullExpressionValue(sharedPreferences, "Injekt.get<Application>(…ource_$sourceId\", 0x0000)");
        Unit unit = Unit.INSTANCE;
        this.preferences = sharedPreferences;
        this.httpCache = new CacheControl.Builder().maxStale(300, TimeUnit.SECONDS).build();
        this.client = buildClient();
        ApiRepo.INSTANCE.setPreferences(sharedPreferences);
        TokenProvider.INSTANCE.setClient(getClient());
        TokenProvider.INSTANCE.setPreferences(sharedPreferences);
    }

    public String getLang() {
        return this.lang;
    }

    public String getBaseUrl() {
        return this.baseUrl;
    }

    public String getName() {
        return this.name;
    }

    public boolean getSupportsLatest() {
        return this.supportsLatest;
    }

    public OkHttpClient getClient() {
        return this.client;
    }

    public void setClient(OkHttpClient okHttpClient) {
        Intrinsics.checkNotNullParameter(okHttpClient, "<set-?>");
        this.client = okHttpClient;
    }

    private final OkHttpClient buildClient() {
        return getNetwork().getCloudflareClient().newBuilder().callTimeout(30L, TimeUnit.SECONDS).cookieJar(CookieJar.NO_COOKIES).retryOnConnectionFailure(true).addInterceptor(new ExceptionInterceptor()).addInterceptor(new RateLimitInterceptor()).addInterceptor(new ResponseErrorInterceptor()).addInterceptor(new TextInterceptor()).addInterceptor(new AuthorizationInterceptor(this.preferences)).addInterceptor(new HeadersInterceptor(this.preferences)).addInterceptor(new UserAgentInterceptor(this.preferences)).build();
    }

    protected Request chapterListRequest(SManga manga) {
        Intrinsics.checkNotNullParameter(manga, "manga");
        throw new UnsupportedOperationException();
    }

    protected List<SChapter> chapterListParse(Response response) {
        Intrinsics.checkNotNullParameter(response, "response");
        throw new UnsupportedOperationException();
    }

    public Observable<List<SChapter>> fetchChapterList(final SManga manga) {
        Intrinsics.checkNotNullParameter(manga, "manga");
        Observable<List<SChapter>> observableFromCallable = Observable.fromCallable(new Callable() { // from class: eu.kanade.tachiyomi.extension.zh.copymanga.CopyManga$$ExternalSyntheticLambda1
            @Override // java.util.concurrent.Callable
            public final Object call() {
                return CopyManga.fetchChapterList$lambda$6(this.f$0, manga);
            }
        });
        Intrinsics.checkNotNullExpressionValue(observableFromCallable, "fromCallable {\n         …)\n            }\n        }");
        return observableFromCallable;
    }

    /* JADX INFO: Access modifiers changed from: private */
    public static final List fetchChapterList$lambda$6(CopyManga copyManga, SManga sManga) throws Exception {
        Intrinsics.checkNotNullParameter(copyManga, "this$0");
        Intrinsics.checkNotNullParameter(sManga, "$manga");
        Response responseExecute = copyManga.getClient().newCall(copyManga.mangaDetailsRequest(sManga)).execute();
        try {
            if (responseExecute.isSuccessful()) {
                StringFormat json = ApiResponseKt.getJson();
                String strString = responseExecute.body().string();
                SerializersModule serializersModule = json.getSerializersModule();
                KType kTypeTypeOf = Reflection.typeOf(ApiResponse.class, KTypeProjection.Companion.invariant(Reflection.typeOf(ComicDetailResult.class)));
                MagicApiIntrinsics.voidMagicApiCall("kotlinx.serialization.serializer.withModule");
                ComicDetailResult comicDetailResult = (ComicDetailResult) ((ApiResponse) json.decodeFromString(SerializersKt.serializer(serializersModule, kTypeTypeOf), strString)).getResults();
                String strUrl2comicPath = ApiRepo.INSTANCE.url2comicPath(sManga.getUrl());
                Set<Map.Entry<String, GroupInfo>> setEntrySet = comicDetailResult.getGroups().entrySet();
                ArrayList arrayList = new ArrayList();
                Iterator it = setEntrySet.iterator();
                while (it.hasNext()) {
                    GroupInfo groupInfo = (GroupInfo) ((Map.Entry) it.next()).getValue();
                    ArrayList arrayList2 = new ArrayList();
                    int total = Integer.MAX_VALUE;
                    int i = 0;
                    while (arrayList2.size() < total) {
                        Response responseExecute2 = copyManga.getClient().newCall(RequestsKt.GET$default(ApiRepo.INSTANCE.chapterListUrl(strUrl2comicPath, groupInfo.getPathWord(), i), (Headers) null, (CacheControl) null, 6, (Object) null)).execute();
                        try {
                            if (responseExecute2.isSuccessful()) {
                                StringFormat json2 = ApiResponseKt.getJson();
                                String strString2 = responseExecute2.body().string();
                                SerializersModule serializersModule2 = json2.getSerializersModule();
                                String str = strUrl2comicPath;
                                Iterator it2 = it;
                                KType kTypeTypeOf2 = Reflection.typeOf(ApiResponse.class, KTypeProjection.Companion.invariant(Reflection.typeOf(ChapterListResult.class)));
                                MagicApiIntrinsics.voidMagicApiCall("kotlinx.serialization.serializer.withModule");
                                ChapterListResult chapterListResult = (ChapterListResult) ((ApiResponse) json2.decodeFromString(SerializersKt.serializer(serializersModule2, kTypeTypeOf2), strString2)).getResults();
                                CollectionsKt.addAll(arrayList2, chapterListResult.getList());
                                total = chapterListResult.getTotal();
                                i += 100;
                                strUrl2comicPath = str;
                                it = it2;
                            } else {
                                throw new Exception("Error: " + responseExecute2.code() + " - " + responseExecute2.message());
                            }
                        } catch (Exception e) {
                            throw new Exception("解析失敗，請嘗試更換域名或參數，並在Github Issue聯繫開發者\n" + e.getMessage(), e);
                        }
                    }
                    String str2 = strUrl2comicPath;
                    Iterator it3 = it;
                    List listSortedWith = CollectionsKt.sortedWith(arrayList2, new Comparator() { // from class: eu.kanade.tachiyomi.extension.zh.copymanga.CopyManga$fetchChapterList$lambda$6$lambda$4$$inlined$compareByDescending$1
                        /* JADX WARN: Multi-variable type inference failed */
                        @Override // java.util.Comparator
                        public final int compare(T t, T t2) {
                            return ComparisonsKt.compareValues(Integer.valueOf(((ChapterInfo) t2).getIndex()), Integer.valueOf(((ChapterInfo) t).getIndex()));
                        }
                    });
                    ArrayList arrayList3 = new ArrayList();
                    for (Object obj : listSortedWith) {
                        if (!StringsKt.split$default(PreferencesKt.getHideDefaultContinuousChapter(copyManga.preferences), new String[]{"\n"}, false, 0, 6, (Object) null).contains(((ChapterInfo) obj).getName())) {
                            arrayList3.add(obj);
                        }
                    }
                    ArrayList arrayList4 = arrayList3;
                    ArrayList arrayList5 = new ArrayList(CollectionsKt.collectionSizeOrDefault(arrayList4, 10));
                    int i2 = 0;
                    for (Object obj2 : arrayList4) {
                        int i3 = i2 + 1;
                        if (i2 < 0) {
                            CollectionsKt.throwIndexOverflow();
                        }
                        arrayList5.add(((ChapterInfo) obj2).toSChapter(i2, PreferencesKt.getCCOption(copyManga.preferences), groupInfo.getName()));
                        i2 = i3;
                    }
                    CollectionsKt.addAll(arrayList, arrayList5);
                    strUrl2comicPath = str2;
                    it = it3;
                }
                List mutableList = CollectionsKt.toMutableList(arrayList);
                if (PreferencesKt.getShowMangaComments(copyManga.preferences)) {
                    mutableList.add(new ChapterInfo(0, (String) null, (String) null, comicDetailResult.getComic().getUuid(), (String) null, (String) null, (String) null, 119, (DefaultConstructorMarker) null).toSMangaCommentChapter(PreferencesKt.getCCOption(copyManga.preferences)));
                }
                return mutableList;
            }
            throw new Exception("Error: " + responseExecute.code() + " - " + responseExecute.message());
        } catch (Exception e2) {
            throw new Exception("解析失敗，請嘗試更換域名或參數，並在Github Issue聯繫開發者\n" + e2.getMessage(), e2);
        }
    }

    protected String imageUrlParse(Response response) {
        Intrinsics.checkNotNullParameter(response, "response");
        throw new UnsupportedOperationException();
    }

    /* JADX INFO: Thrown type has an unknown type hierarchy: kotlin.NoWhenBranchMatchedException */
    protected Request latestUpdatesRequest(int page) throws NoWhenBranchMatchedException {
        int i = WhenMappings.$EnumSwitchMapping$0[PreferencesKt.getLatestUpdateMode(this.preferences).ordinal()];
        if (i == 1) {
            return RequestsKt.GET$default(ApiRepo.INSTANCE.newestPageUrl(page), (Headers) null, this.httpCache, 2, (Object) null);
        }
        if (i == 2) {
            return RequestsKt.GET$default(ApiRepo.INSTANCE.newestPageUrl_update(page), (Headers) null, this.httpCache, 2, (Object) null);
        }
        throw new NoWhenBranchMatchedException();
    }

    protected MangasPage latestUpdatesParse(Response response) throws Exception {
        Intrinsics.checkNotNullParameter(response, "response");
        String string = response.request().url().toString();
        if (!StringsKt.contains$default(string, "/update/newest", false, 2, (Object) null)) {
            if (!StringsKt.contains$default(string, "/comics", false, 2, (Object) null)) {
                throw new Exception("未知的最新更新接口");
            }
            try {
                if (response.isSuccessful()) {
                    StringFormat json = ApiResponseKt.getJson();
                    String strString = response.body().string();
                    SerializersModule serializersModule = json.getSerializersModule();
                    KType kTypeTypeOf = Reflection.typeOf(ApiResponse.class, KTypeProjection.Companion.invariant(Reflection.typeOf(ComicsListResult.class)));
                    MagicApiIntrinsics.voidMagicApiCall("kotlinx.serialization.serializer.withModule");
                    ComicsListResult comicsListResult = (ComicsListResult) ((ApiResponse) json.decodeFromString(SerializersKt.serializer(serializersModule, kTypeTypeOf), strString)).getResults();
                    if (comicsListResult.getList().isEmpty()) {
                        throw new Exception("没有找到最新更新的漫画");
                    }
                    List<ComicSummary> list = comicsListResult.getList();
                    ArrayList arrayList = new ArrayList(CollectionsKt.collectionSizeOrDefault(list, 10));
                    Iterator<T> it = list.iterator();
                    while (it.hasNext()) {
                        arrayList.add(((ComicSummary) it.next()).toSManga(PreferencesKt.getCCOption(this.preferences)));
                    }
                    return new MangasPage(arrayList, comicsListResult.hasNext());
                }
                throw new Exception("Error: " + response.code() + " - " + response.message());
            } catch (Exception e) {
                throw new Exception("解析失敗，請嘗試更換域名或參數，並在Github Issue聯繫開發者\n" + e.getMessage(), e);
            }
        }
        try {
            if (response.isSuccessful()) {
                StringFormat json2 = ApiResponseKt.getJson();
                String strString2 = response.body().string();
                SerializersModule serializersModule2 = json2.getSerializersModule();
                KType kTypeTypeOf2 = Reflection.typeOf(ApiResponse.class, KTypeProjection.Companion.invariant(Reflection.typeOf(NewestResult.class)));
                MagicApiIntrinsics.voidMagicApiCall("kotlinx.serialization.serializer.withModule");
                NewestResult newestResult = (NewestResult) ((ApiResponse) json2.decodeFromString(SerializersKt.serializer(serializersModule2, kTypeTypeOf2), strString2)).getResults();
                if (newestResult.getList().isEmpty()) {
                    throw new Exception("没有找到最新上架的漫画");
                }
                List<NewestItem> list2 = newestResult.getList();
                ArrayList arrayList2 = new ArrayList(CollectionsKt.collectionSizeOrDefault(list2, 10));
                Iterator<T> it2 = list2.iterator();
                while (it2.hasNext()) {
                    arrayList2.add(((NewestItem) it2.next()).getComic().toSManga(PreferencesKt.getImageResolution(this.preferences), PreferencesKt.getCCOption(this.preferences)));
                }
                return new MangasPage(arrayList2, newestResult.hasNext());
            }
            throw new Exception("Error: " + response.code() + " - " + response.message());
        } catch (Exception e2) {
            throw new Exception("解析失敗，請嘗試更換域名或參數，並在Github Issue聯繫開發者\n" + e2.getMessage(), e2);
        }
    }

    public Request mangaDetailsRequest(SManga manga) {
        Intrinsics.checkNotNullParameter(manga, "manga");
        return RequestsKt.GET$default(ApiRepo.INSTANCE.comicDetailUrl(ApiRepo.INSTANCE.url2comicPath(manga.getUrl())), (Headers) null, (CacheControl) null, 6, (Object) null);
    }

    protected List<Page> pageListParse(Response response) {
        Intrinsics.checkNotNullParameter(response, "response");
        throw new UnsupportedOperationException();
    }

    public Observable<List<Page>> fetchPageList(final SChapter chapter) {
        Intrinsics.checkNotNullParameter(chapter, "chapter");
        Observable<List<Page>> observableFromCallable = Observable.fromCallable(new Callable() { // from class: eu.kanade.tachiyomi.extension.zh.copymanga.CopyManga$$ExternalSyntheticLambda0
            @Override // java.util.concurrent.Callable
            public final Object call() {
                return CopyManga.fetchPageList$lambda$22(this.f$0, chapter);
            }
        });
        Intrinsics.checkNotNullExpressionValue(observableFromCallable, "fromCallable {\n         …       pageList\n        }");
        return observableFromCallable;
    }

    /* JADX WARN: Removed duplicated region for block: B:9:0x003a  */
    /*
        Code decompiled incorrectly, please refer to instructions dump.
        To view partially-correct code enable 'Show inconsistent code' option in preferences
    */
    private static final void fetchPageList$lambda$22$appendMergedComments(java.util.List<eu.kanade.tachiyomi.source.model.Page> r11, java.util.List<eu.kanade.tachiyomi.extension.zh.copymanga.api.dto.CommentInfo> r12) {
        /*
            java.lang.Iterable r12 = (java.lang.Iterable) r12
            java.util.ArrayList r0 = new java.util.ArrayList
            r1 = 10
            int r1 = kotlin.collections.CollectionsKt.collectionSizeOrDefault(r12, r1)
            r0.<init>(r1)
            java.util.Collection r0 = (java.util.Collection) r0
            java.util.Iterator r12 = r12.iterator()
        L13:
            boolean r1 = r12.hasNext()
            if (r1 == 0) goto L6a
            java.lang.Object r1 = r12.next()
            eu.kanade.tachiyomi.extension.zh.copymanga.api.dto.CommentInfo r1 = (eu.kanade.tachiyomi.extension.zh.copymanga.api.dto.CommentInfo) r1
            java.lang.String r2 = r1.getParentUserName()
            if (r2 == 0) goto L3a
            java.lang.StringBuilder r3 = new java.lang.StringBuilder
            java.lang.String r4 = "@"
            r3.<init>(r4)
            r3.append(r2)
            r2 = 32
            r3.append(r2)
            java.lang.String r2 = r3.toString()
            if (r2 != 0) goto L3c
        L3a:
            java.lang.String r2 = ""
        L3c:
            java.lang.StringBuilder r3 = new java.lang.StringBuilder
            r3.<init>()
            java.lang.String r4 = r1.getUserName()
            r3.append(r4)
            java.lang.String r4 = " : "
            r3.append(r4)
            r3.append(r2)
            java.lang.String r5 = r1.getComment()
            r9 = 4
            r10 = 0
            java.lang.String r6 = "\n"
            java.lang.String r7 = "<br>"
            r8 = 0
            java.lang.String r1 = kotlin.text.StringsKt.replace$default(r5, r6, r7, r8, r9, r10)
            r3.append(r1)
            java.lang.String r1 = r3.toString()
            r0.add(r1)
            goto L13
        L6a:
            java.util.List r0 = (java.util.List) r0
            java.util.Collection r0 = (java.util.Collection) r0
            java.util.List r12 = kotlin.collections.CollectionsKt.toMutableList(r0)
            java.lang.String r0 = "<br><br>已无更多吐槽"
            r12.add(r0)
            r1 = r12
            java.lang.Iterable r1 = (java.lang.Iterable) r1
            java.lang.String r12 = "<br>"
            r2 = r12
            java.lang.CharSequence r2 = (java.lang.CharSequence) r2
            r8 = 62
            r9 = 0
            r3 = 0
            r4 = 0
            r5 = 0
            r6 = 0
            r7 = 0
            java.lang.String r12 = kotlin.collections.CollectionsKt.joinToString$default(r1, r2, r3, r4, r5, r6, r7, r8, r9)
            eu.kanade.tachiyomi.source.model.Page r7 = new eu.kanade.tachiyomi.source.model.Page
            int r1 = r11.size()
            eu.kanade.tachiyomi.lib.textinterceptor.TextInterceptorHelper r0 = eu.kanade.tachiyomi.lib.textinterceptor.TextInterceptorHelper.INSTANCE
            java.lang.String r2 = "漫畫吐槽"
            java.lang.String r3 = r0.createUrl(r2, r12)
            r5 = 8
            java.lang.String r2 = ""
            r0 = r7
            r0.<init>(r1, r2, r3, r4, r5, r6)
            r11.add(r7)
            return
        */
        throw new UnsupportedOperationException("Method not decompiled: eu.kanade.tachiyomi.extension.zh.copymanga.CopyManga.fetchPageList$lambda$22$appendMergedComments(java.util.List, java.util.List):void");
    }

    /* JADX WARN: Removed duplicated region for block: B:9:0x0041  */
    /*
        Code decompiled incorrectly, please refer to instructions dump.
        To view partially-correct code enable 'Show inconsistent code' option in preferences
    */
    private static final void fetchPageList$lambda$22$appendSeparateComments(java.util.List<eu.kanade.tachiyomi.source.model.Page> r19, java.util.List<eu.kanade.tachiyomi.extension.zh.copymanga.api.dto.CommentInfo> r20) {
        /*
            Method dump skipped, instruction units count: 345
            To view this dump change 'Code comments level' option to 'DEBUG'
        */
        throw new UnsupportedOperationException("Method not decompiled: eu.kanade.tachiyomi.extension.zh.copymanga.CopyManga.fetchPageList$lambda$22$appendSeparateComments(java.util.List, java.util.List):void");
    }

    /* JADX INFO: Access modifiers changed from: private */
    /* JADX WARN: Removed duplicated region for block: B:76:0x02d2  */
    /* JADX WARN: Removed duplicated region for block: B:80:0x02e9  */
    /*
        Code decompiled incorrectly, please refer to instructions dump.
        To view partially-correct code enable 'Show inconsistent code' option in preferences
    */
    public static final java.util.List fetchPageList$lambda$22(eu.kanade.tachiyomi.extension.zh.copymanga.CopyManga r18, eu.kanade.tachiyomi.source.model.SChapter r19) {
        /*
            Method dump skipped, instruction units count: 791
            To view this dump change 'Code comments level' option to 'DEBUG'
        */
        throw new UnsupportedOperationException("Method not decompiled: eu.kanade.tachiyomi.extension.zh.copymanga.CopyManga.fetchPageList$lambda$22(eu.kanade.tachiyomi.extension.zh.copymanga.CopyManga, eu.kanade.tachiyomi.source.model.SChapter):java.util.List");
    }

    protected Request popularMangaRequest(int page) {
        return RequestsKt.GET$default(ApiRepo.INSTANCE.recommendPageUrl(page), (Headers) null, (CacheControl) null, 6, (Object) null);
    }

    protected Request searchMangaRequest(int page, String query, FilterList filters) {
        HttpUrl.Builder builderNewBuilder;
        String string;
        Intrinsics.checkNotNullParameter(query, "query");
        Intrinsics.checkNotNullParameter(filters, "filters");
        Iterable iterable = (Iterable) filters;
        ArrayList arrayList = new ArrayList();
        for (Object obj : iterable) {
            if (obj instanceof TypeFilter) {
                arrayList.add(obj);
            }
        }
        int iIntValue = ((Number) ((TypeFilter) CollectionsKt.first(arrayList)).getState()).intValue();
        ArrayList arrayList2 = new ArrayList();
        for (Object obj2 : iterable) {
            if (obj2 instanceof RankFilter) {
                arrayList2.add(obj2);
            }
        }
        int iIntValue2 = ((Number) ((RankFilter) CollectionsKt.first(arrayList2)).getState()).intValue();
        ArrayList arrayList3 = new ArrayList();
        for (Object obj3 : iterable) {
            if (obj3 instanceof AudienceFilter) {
                arrayList3.add(obj3);
            }
        }
        int iIntValue3 = ((Number) ((AudienceFilter) CollectionsKt.first(arrayList3)).getState()).intValue();
        ArrayList arrayList4 = new ArrayList();
        for (Object obj4 : iterable) {
            if (obj4 instanceof MigrateFilter) {
                arrayList4.add(obj4);
            }
        }
        int iIntValue4 = ((Number) ((MigrateFilter) CollectionsKt.first(arrayList4)).getState()).intValue();
        if (!StringsKt.isBlank(query)) {
            builderNewBuilder = HttpUrl.Companion.get(ApiRepo.INSTANCE.searchUrl(page)).newBuilder();
            builderNewBuilder.addQueryParameter("q", query);
            builderNewBuilder.addQueryParameter("q_type", FilterKt.getTypeFilter()[iIntValue].getPathWord());
        } else if (iIntValue4 > 0) {
            builderNewBuilder = HttpUrl.Companion.get(ApiRepo.INSTANCE.memberCollectUrl(page)).newBuilder();
        } else if (iIntValue2 > 0 || iIntValue3 > 0) {
            builderNewBuilder = HttpUrl.Companion.get(ApiRepo.INSTANCE.comicRankUrl(page)).newBuilder();
            builderNewBuilder.addQueryParameter("date_type", FilterKt.getRankFilter()[iIntValue2].getPathWord());
            builderNewBuilder.addQueryParameter("audience_type", FilterKt.getAudienceFilter()[iIntValue3].getPathWord());
        } else {
            builderNewBuilder = HttpUrl.Companion.get(ApiRepo.INSTANCE.comicListUrl(page)).newBuilder();
            ArrayList arrayList5 = new ArrayList();
            for (Object obj5 : iterable) {
                if (obj5 instanceof RegionFilter) {
                    arrayList5.add(obj5);
                }
            }
            int iIntValue5 = ((Number) ((RegionFilter) CollectionsKt.first(arrayList5)).getState()).intValue();
            if (iIntValue5 > 0) {
                builderNewBuilder.addQueryParameter("top", FilterKt.getRegionFilter()[iIntValue5].getPathWord());
            }
            ArrayList arrayList6 = new ArrayList();
            for (Object obj6 : iterable) {
                if (obj6 instanceof ThemeFilter) {
                    arrayList6.add(obj6);
                }
            }
            ThemeFilter themeFilter = (ThemeFilter) CollectionsKt.firstOrNull(arrayList6);
            Integer num = themeFilter != null ? (Integer) themeFilter.getState() : null;
            if (num != null && num.intValue() > 0) {
                builderNewBuilder.addQueryParameter("theme", FilterKt.getThemeFilter()[num.intValue()].getPathWord());
            }
            ArrayList arrayList7 = new ArrayList();
            for (Object obj7 : iterable) {
                if (obj7 instanceof FreeTypeFilter) {
                    arrayList7.add(obj7);
                }
            }
            int iIntValue6 = ((Number) ((FreeTypeFilter) CollectionsKt.first(arrayList7)).getState()).intValue();
            if (iIntValue6 > 0) {
                builderNewBuilder.addQueryParameter("free_type", FilterKt.getFreeTypeFilter()[iIntValue6].getPathWord());
            }
            ArrayList arrayList8 = new ArrayList();
            for (Object obj8 : iterable) {
                if (obj8 instanceof SortFilter) {
                    arrayList8.add(obj8);
                }
            }
            SortFilter sortFilter = (SortFilter) CollectionsKt.firstOrNull(arrayList8);
            Filter.Sort.Selection selection = sortFilter != null ? (Filter.Sort.Selection) sortFilter.getState() : null;
            if (selection != null) {
                StringBuilder sb = new StringBuilder();
                sb.append(!selection.getAscending() ? "-" : "");
                sb.append(FilterKt.getSortFilter()[selection.getIndex()].getPathWord());
                string = sb.toString();
            } else {
                string = "-datetime_updated";
            }
            builderNewBuilder.addQueryParameter("ordering", string);
        }
        builderNewBuilder.addQueryParameter("_update", "true");
        return RequestsKt.GET$default(builderNewBuilder.build(), (Headers) null, (CacheControl) null, 6, (Object) null);
    }

    protected MangasPage searchMangaParse(Response response) throws Exception {
        Integer intOrNull;
        Intrinsics.checkNotNullParameter(response, "response");
        String string = response.request().url().toString();
        String str = string;
        if (!StringsKt.contains$default(str, "/api/v3/member/collect", false, 2, (Object) null)) {
            if (!StringsKt.contains$default(str, "/api/v3/search/comic", false, 2, (Object) null)) {
                if (StringsKt.contains$default(str, "/api/v3/ranks", false, 2, (Object) null)) {
                    try {
                        if (response.isSuccessful()) {
                            StringFormat json = ApiResponseKt.getJson();
                            String strString = response.body().string();
                            SerializersModule serializersModule = json.getSerializersModule();
                            KType kTypeTypeOf = Reflection.typeOf(ApiResponse.class, KTypeProjection.Companion.invariant(Reflection.typeOf(RankResult.class)));
                            MagicApiIntrinsics.voidMagicApiCall("kotlinx.serialization.serializer.withModule");
                            RankResult rankResult = (RankResult) ((ApiResponse) json.decodeFromString(SerializersKt.serializer(serializersModule, kTypeTypeOf), strString)).getResults();
                            if (rankResult.getList().isEmpty()) {
                                throw new Exception("没有找到相关漫画");
                            }
                            List<ListItem> list = rankResult.getList();
                            ArrayList arrayList = new ArrayList(CollectionsKt.collectionSizeOrDefault(list, 10));
                            Iterator<T> it = list.iterator();
                            while (it.hasNext()) {
                                arrayList.add(((ListItem) it.next()).getComic().toSManga(PreferencesKt.getCCOption(this.preferences)));
                            }
                            return new MangasPage(arrayList, rankResult.hasNext());
                        }
                        throw new Exception("Error: " + response.code() + " - " + response.message());
                    } catch (Exception e) {
                        throw new Exception("解析失敗，請嘗試更換域名或參數，並在Github Issue聯繫開發者\n" + e.getMessage(), e);
                    }
                }
                try {
                    if (response.isSuccessful()) {
                        StringFormat json2 = ApiResponseKt.getJson();
                        String strString2 = response.body().string();
                        SerializersModule serializersModule2 = json2.getSerializersModule();
                        KType kTypeTypeOf2 = Reflection.typeOf(ApiResponse.class, KTypeProjection.Companion.invariant(Reflection.typeOf(ComicsListResult.class)));
                        MagicApiIntrinsics.voidMagicApiCall("kotlinx.serialization.serializer.withModule");
                        ComicsListResult comicsListResult = (ComicsListResult) ((ApiResponse) json2.decodeFromString(SerializersKt.serializer(serializersModule2, kTypeTypeOf2), strString2)).getResults();
                        if (comicsListResult.getList().isEmpty()) {
                            throw new Exception("没有找到相关漫画(若此为异常，可尝试切换平台参数/切换域名/开启vpn)");
                        }
                        List<ComicSummary> list2 = comicsListResult.getList();
                        ArrayList arrayList2 = new ArrayList(CollectionsKt.collectionSizeOrDefault(list2, 10));
                        Iterator<T> it2 = list2.iterator();
                        while (it2.hasNext()) {
                            arrayList2.add(((ComicSummary) it2.next()).toSManga(PreferencesKt.getCCOption(this.preferences)));
                        }
                        return new MangasPage(arrayList2, comicsListResult.hasNext());
                    }
                    throw new Exception("Error: " + response.code() + " - " + response.message());
                } catch (Exception e2) {
                    throw new Exception("解析失敗，請嘗試更換域名或參數，並在Github Issue聯繫開發者\n" + e2.getMessage(), e2);
                }
            }
            try {
                if (response.isSuccessful()) {
                    StringFormat json3 = ApiResponseKt.getJson();
                    String strString3 = response.body().string();
                    SerializersModule serializersModule3 = json3.getSerializersModule();
                    KType kTypeTypeOf3 = Reflection.typeOf(ApiResponse.class, KTypeProjection.Companion.invariant(Reflection.typeOf(SearchResult.class)));
                    MagicApiIntrinsics.voidMagicApiCall("kotlinx.serialization.serializer.withModule");
                    SearchResult searchResult = (SearchResult) ((ApiResponse) json3.decodeFromString(SerializersKt.serializer(serializersModule3, kTypeTypeOf3), strString3)).getResults();
                    if (searchResult.getList().isEmpty()) {
                        throw new Exception("没有找到相关漫画");
                    }
                    List<SearchComic> list3 = searchResult.getList();
                    ArrayList arrayList3 = new ArrayList(CollectionsKt.collectionSizeOrDefault(list3, 10));
                    Iterator<T> it3 = list3.iterator();
                    while (it3.hasNext()) {
                        arrayList3.add(((SearchComic) it3.next()).toSManga(PreferencesKt.getCCOption(this.preferences)));
                    }
                    return new MangasPage(arrayList3, searchResult.hasNext());
                }
                throw new Exception("Error: " + response.code() + " - " + response.message());
            } catch (Exception e3) {
                throw new Exception("解析失敗，請嘗試更換域名或參數，並在Github Issue聯繫開發者\n" + e3.getMessage(), e3);
            }
        }
        try {
            if (response.isSuccessful()) {
                StringFormat json4 = ApiResponseKt.getJson();
                String strString4 = response.body().string();
                SerializersModule serializersModule4 = json4.getSerializersModule();
                KType kTypeTypeOf4 = Reflection.typeOf(ApiResponse.class, KTypeProjection.Companion.invariant(Reflection.typeOf(CollectResult.class)));
                MagicApiIntrinsics.voidMagicApiCall("kotlinx.serialization.serializer.withModule");
                CollectResult collectResult = (CollectResult) ((ApiResponse) json4.decodeFromString(SerializersKt.serializer(serializersModule4, kTypeTypeOf4), strString4)).getResults();
                List<CollectInfo> list4 = collectResult.getList();
                ArrayList arrayList4 = new ArrayList(CollectionsKt.collectionSizeOrDefault(list4, 10));
                Iterator<T> it4 = list4.iterator();
                while (it4.hasNext()) {
                    arrayList4.add(((CollectInfo) it4.next()).getComic().toSManga(PreferencesKt.getCCOption(this.preferences)));
                }
                List mutableList = CollectionsKt.toMutableList(arrayList4);
                String strQueryParameter = HttpUrl.Companion.get(string).queryParameter("offset");
                if (((strQueryParameter == null || (intOrNull = StringsKt.toIntOrNull(strQueryParameter)) == null) ? 0 : intOrNull.intValue()) == 0) {
                    mutableList.add(0, collectResult.infoComic(PreferencesKt.getApiDomainFromPrefs(this.preferences), PreferencesKt.getCCOption(this.preferences)));
                }
                return new MangasPage(mutableList, collectResult.hasNext());
            }
            throw new Exception("Error: " + response.code() + " - " + response.message());
        } catch (Exception e4) {
            throw new Exception("解析失敗，請嘗試更換域名或參數，並在Github Issue聯繫開發者\n" + e4.getMessage(), e4);
        }
    }

    public String getMangaUrl(SManga manga) {
        Intrinsics.checkNotNullParameter(manga, "manga");
        return WebViewDomainOption.INSTANCE.toComicUrl(PreferencesKt.getHttpWebViewDomain(this.preferences), ApiRepo.INSTANCE.url2comicPath(manga.getUrl()), PreferencesKt.getWebViewClientType(this.preferences));
    }

    public String getChapterUrl(SChapter chapter) {
        Intrinsics.checkNotNullParameter(chapter, "chapter");
        return WebViewDomainOption.INSTANCE.toChapterUrl(PreferencesKt.getHttpWebViewDomain(this.preferences), ApiRepo.INSTANCE.url2comicPath(chapter.getUrl()), PreferencesKt.getWebViewClientType(this.preferences));
    }

    public FilterList getFilterList() {
        return FilterKt.getFilterList(getClient());
    }

    public void setupPreferenceScreen(PreferenceScreen screen) {
        Intrinsics.checkNotNullParameter(screen, "screen");
        Context context = screen.getContext();
        Intrinsics.checkNotNullExpressionValue(context, "screen.context");
        for (Preference preference : PreferencesKt.initPreferences(context, this.preferences)) {
            screen.addPreference(preference);
        }
    }

    protected SManga mangaDetailsParse(Response response) throws Exception {
        Intrinsics.checkNotNullParameter(response, "response");
        try {
            if (response.isSuccessful()) {
                StringFormat json = ApiResponseKt.getJson();
                String strString = response.body().string();
                SerializersModule serializersModule = json.getSerializersModule();
                KType kTypeTypeOf = Reflection.typeOf(ApiResponse.class, KTypeProjection.Companion.invariant(Reflection.typeOf(ComicDetailResult.class)));
                MagicApiIntrinsics.voidMagicApiCall("kotlinx.serialization.serializer.withModule");
                return ((ComicDetailResult) ((ApiResponse) json.decodeFromString(SerializersKt.serializer(serializersModule, kTypeTypeOf), strString)).getResults()).getComic().toSManga(PreferencesKt.getImageResolution(this.preferences), PreferencesKt.getCCOption(this.preferences));
            }
            throw new Exception("Error: " + response.code() + " - " + response.message());
        } catch (Exception e) {
            throw new Exception("解析失敗，請嘗試更換域名或參數，並在Github Issue聯繫開發者\n" + e.getMessage(), e);
        }
    }

    protected MangasPage popularMangaParse(Response response) throws Exception {
        Intrinsics.checkNotNullParameter(response, "response");
        try {
            if (response.isSuccessful()) {
                StringFormat json = ApiResponseKt.getJson();
                String strString = response.body().string();
                SerializersModule serializersModule = json.getSerializersModule();
                KType kTypeTypeOf = Reflection.typeOf(ApiResponse.class, KTypeProjection.Companion.invariant(Reflection.typeOf(RecommendResult.class)));
                MagicApiIntrinsics.voidMagicApiCall("kotlinx.serialization.serializer.withModule");
                List<Recommendation> list = ((RecommendResult) ((ApiResponse) json.decodeFromString(SerializersKt.serializer(serializersModule, kTypeTypeOf), strString)).getResults()).getList();
                ArrayList arrayList = new ArrayList(CollectionsKt.collectionSizeOrDefault(list, 10));
                Iterator<T> it = list.iterator();
                while (it.hasNext()) {
                    arrayList.add(((Recommendation) it.next()).getComic().toSManga(PreferencesKt.getImageResolution(this.preferences), PreferencesKt.getCCOption(this.preferences)));
                }
                return new MangasPage(arrayList, true);
            }
            throw new Exception("Error: " + response.code() + " - " + response.message());
        } catch (Exception e) {
            throw new Exception("解析失敗，請嘗試更換域名或參數，並在Github Issue聯繫開發者\n" + e.getMessage(), e);
        }
    }
}
