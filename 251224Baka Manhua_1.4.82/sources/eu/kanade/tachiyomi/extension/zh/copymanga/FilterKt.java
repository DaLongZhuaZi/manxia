package eu.kanade.tachiyomi.extension.zh.copymanga;

import eu.kanade.tachiyomi.extension.zh.copymanga.api.ApiRepo;
import eu.kanade.tachiyomi.extension.zh.copymanga.api.ApiResponse;
import eu.kanade.tachiyomi.extension.zh.copymanga.api.ApiResponseKt;
import eu.kanade.tachiyomi.extension.zh.copymanga.api.dto.ThemeDetail;
import eu.kanade.tachiyomi.extension.zh.copymanga.api.dto.ThemeResult;
import eu.kanade.tachiyomi.network.RequestsKt;
import eu.kanade.tachiyomi.source.model.Filter;
import eu.kanade.tachiyomi.source.model.FilterList;
import java.util.ArrayList;
import java.util.List;
import kotlin.Metadata;
import kotlin.Result;
import kotlin.ResultKt;
import kotlin.Unit;
import kotlin.collections.CollectionsKt;
import kotlin.concurrent.ThreadsKt;
import kotlin.jvm.functions.Function0;
import kotlin.jvm.internal.DefaultConstructorMarker;
import kotlin.jvm.internal.Intrinsics;
import kotlin.jvm.internal.MagicApiIntrinsics;
import kotlin.jvm.internal.Reflection;
import kotlin.reflect.KType;
import kotlin.reflect.KTypeProjection;
import kotlinx.serialization.SerializersKt;
import kotlinx.serialization.StringFormat;
import kotlinx.serialization.modules.SerializersModule;
import okhttp3.CacheControl;
import okhttp3.Headers;
import okhttp3.OkHttpClient;
import okhttp3.Response;

/* JADX INFO: compiled from: Filter.kt */
/* JADX INFO: loaded from: classes.dex */
@Metadata(d1 = {"\u0000(\n\u0000\n\u0002\u0010\u0011\n\u0002\u0018\u0002\n\u0002\b\u0004\n\u0002\u0010\u000b\n\u0002\b\u0011\n\u0002\u0018\u0002\n\u0000\n\u0002\u0018\u0002\n\u0000\n\u0002\u0010\u0002\n\u0000\u001a\u000e\u0010\u0018\u001a\u00020\u00192\u0006\u0010\u001a\u001a\u00020\u001b\u001a\u000e\u0010\u001c\u001a\u00020\u001d2\u0006\u0010\u001a\u001a\u00020\u001b\"\u0019\u0010\u0000\u001a\b\u0012\u0004\u0012\u00020\u00020\u0001¢\u0006\n\n\u0002\u0010\u0005\u001a\u0004\b\u0003\u0010\u0004\"\u000e\u0010\u0006\u001a\u00020\u0007X\u0082\u000e¢\u0006\u0002\n\u0000\"\u0019\u0010\b\u001a\b\u0012\u0004\u0012\u00020\u00020\u0001¢\u0006\n\n\u0002\u0010\u0005\u001a\u0004\b\t\u0010\u0004\"\u0019\u0010\n\u001a\b\u0012\u0004\u0012\u00020\u00020\u0001¢\u0006\n\n\u0002\u0010\u0005\u001a\u0004\b\u000b\u0010\u0004\"\u0019\u0010\f\u001a\b\u0012\u0004\u0012\u00020\u00020\u0001¢\u0006\n\n\u0002\u0010\u0005\u001a\u0004\b\r\u0010\u0004\"\u0019\u0010\u000e\u001a\b\u0012\u0004\u0012\u00020\u00020\u0001¢\u0006\n\n\u0002\u0010\u0005\u001a\u0004\b\u000f\u0010\u0004\"\u0019\u0010\u0010\u001a\b\u0012\u0004\u0012\u00020\u00020\u0001¢\u0006\n\n\u0002\u0010\u0005\u001a\u0004\b\u0011\u0010\u0004\"\"\u0010\u0012\u001a\b\u0012\u0004\u0012\u00020\u00020\u0001X\u0086\u000e¢\u0006\u0010\n\u0002\u0010\u0005\u001a\u0004\b\u0013\u0010\u0004\"\u0004\b\u0014\u0010\u0015\"\u0019\u0010\u0016\u001a\b\u0012\u0004\u0012\u00020\u00020\u0001¢\u0006\n\n\u0002\u0010\u0005\u001a\u0004\b\u0017\u0010\u0004¨\u0006\u001e"}, d2 = {"audienceFilter", "", "Leu/kanade/tachiyomi/extension/zh/copymanga/Tag;", "getAudienceFilter", "()[Leu/kanade/tachiyomi/extension/zh/copymanga/Tag;", "[Leu/kanade/tachiyomi/extension/zh/copymanga/Tag;", "fetchedRefreshTheme", "", "freeTypeFilter", "getFreeTypeFilter", "migrateFilter", "getMigrateFilter", "rankFilter", "getRankFilter", "regionFilter", "getRegionFilter", "sortFilter", "getSortFilter", "themeFilter", "getThemeFilter", "setThemeFilter", "([Leu/kanade/tachiyomi/extension/zh/copymanga/Tag;)V", "typeFilter", "getTypeFilter", "getFilterList", "Leu/kanade/tachiyomi/source/model/FilterList;", "client", "Lokhttp3/OkHttpClient;", "resetThemeFilter", "", "tachiyomi-zh.copymanga-v1.4.82_release"}, k = 2, mv = {1, 7, 1}, xi = 48)
public final class FilterKt {
    private static boolean fetchedRefreshTheme;
    private static final Tag[] typeFilter = {new Tag("全部", ""), new Tag("名称", "name"), new Tag("作者", "author"), new Tag("汉化组", "local")};
    private static final Tag[] rankFilter = {new Tag("不查看", ""), new Tag("日榜(上升最快)", "day"), new Tag("周榜(最近7天)", "week"), new Tag("月榜(最近30天)", "month"), new Tag("总榜单(即热门排序)", "total")};
    private static final Tag[] audienceFilter = {new Tag("默認(男頻)", "male"), new Tag("男频", "male"), new Tag("女频", "female")};
    private static final Tag[] sortFilter = {new Tag("热门", "popular"), new Tag("更新时间", "datetime_updated")};
    private static final Tag[] regionFilter = {new Tag("全部", ""), new Tag("日本", "japan"), new Tag("韩国", "korea"), new Tag("欧美", "west"), new Tag("已完结", "finish")};
    private static final Tag[] freeTypeFilter = {new Tag("全部", ""), new Tag("免费", "1"), new Tag("付费", "2")};
    private static final Tag[] migrateFilter = {new Tag("無", ""), new Tag("源站收藏 (切换域名获取拷贝/热辣的收藏)", "migrate")};
    private static Tag[] themeFilter = new Tag[0];

    public static final Tag[] getTypeFilter() {
        return typeFilter;
    }

    public static final Tag[] getRankFilter() {
        return rankFilter;
    }

    public static final Tag[] getAudienceFilter() {
        return audienceFilter;
    }

    public static final Tag[] getSortFilter() {
        return sortFilter;
    }

    public static final Tag[] getRegionFilter() {
        return regionFilter;
    }

    public static final Tag[] getFreeTypeFilter() {
        return freeTypeFilter;
    }

    public static final Tag[] getMigrateFilter() {
        return migrateFilter;
    }

    public static final Tag[] getThemeFilter() {
        return themeFilter;
    }

    public static final void setThemeFilter(Tag[] tagArr) {
        Intrinsics.checkNotNullParameter(tagArr, "<set-?>");
        themeFilter = tagArr;
    }

    public static final FilterList getFilterList(OkHttpClient okHttpClient) {
        ThemeFilter themeFilter2;
        Intrinsics.checkNotNullParameter(okHttpClient, "client");
        if (!fetchedRefreshTheme || themeFilter.length == 0) {
            resetThemeFilter(okHttpClient);
            themeFilter2 = (Filter.Select) new RefreshThemeInfo();
        } else {
            themeFilter2 = new ThemeFilter();
        }
        return new FilterList(new Filter[]{(Filter) new Filter.Header("\"本插件唯一更新地址為Github(made by thenano)\""), (Filter) new Filter.Separator((String) null, 1, (DefaultConstructorMarker) null), (Filter) new TypeFilter(), (Filter) new Filter.Separator((String) null, 1, (DefaultConstructorMarker) null), (Filter) new RankFilter(), (Filter) new AudienceFilter(), (Filter) new Filter.Separator((String) null, 1, (DefaultConstructorMarker) null), (Filter) new Filter.Header("搜索文本，查看排行榜時無效"), (Filter) new SortFilter(), (Filter) new RegionFilter(), themeFilter2, (Filter) new FreeTypeFilter(), (Filter) new Filter.Separator((String) null, 1, (DefaultConstructorMarker) null), (Filter) new Filter.Header("使用時其他篩選均無效"), (Filter) new MigrateFilter()});
    }

    public static final void resetThemeFilter(final OkHttpClient okHttpClient) {
        Intrinsics.checkNotNullParameter(okHttpClient, "client");
        ThreadsKt.thread$default(false, false, (ClassLoader) null, (String) null, 0, new Function0<Unit>() { // from class: eu.kanade.tachiyomi.extension.zh.copymanga.FilterKt.resetThemeFilter.1
            /* JADX WARN: 'super' call moved to the top of the method (can break code semantics) */
            {
                super(0);
            }

            public /* bridge */ /* synthetic */ Object invoke() {
                m1invoke();
                return Unit.INSTANCE;
            }

            /* JADX INFO: renamed from: invoke, reason: collision with other method in class */
            public final void m1invoke() {
                int count;
                Object obj;
                Response responseExecute;
                OkHttpClient okHttpClient2 = okHttpClient;
                try {
                    Result.Companion companion = Result.Companion;
                    responseExecute = okHttpClient2.newCall(RequestsKt.GET$default(ApiRepo.INSTANCE.tagList(), (Headers) null, (CacheControl) null, 6, (Object) null)).execute();
                    try {
                    } catch (Exception e) {
                        throw new Exception("解析失敗，請嘗試更換域名或參數，並在Github Issue聯繫開發者\n" + e.getMessage(), e);
                    }
                } catch (Throwable th) {
                    th = th;
                    count = 0;
                }
                if (responseExecute.isSuccessful()) {
                    StringFormat json = ApiResponseKt.getJson();
                    String strString = responseExecute.body().string();
                    SerializersModule serializersModule = json.getSerializersModule();
                    KType kTypeTypeOf = Reflection.typeOf(ApiResponse.class, KTypeProjection.Companion.invariant(Reflection.typeOf(ThemeResult.class)));
                    MagicApiIntrinsics.voidMagicApiCall("kotlinx.serialization.serializer.withModule");
                    List<ThemeDetail> themeList = ((ThemeResult) ((ApiResponse) json.decodeFromString(SerializersKt.serializer(serializersModule, kTypeTypeOf), strString)).getResults()).getThemeList();
                    ArrayList arrayList = new ArrayList(CollectionsKt.collectionSizeOrDefault(themeList, 10));
                    count = 0;
                    for (ThemeDetail themeDetail : themeList) {
                        try {
                            count += themeDetail.getCount();
                            arrayList.add(new Tag(themeDetail.getName() + " (" + themeDetail.getCount() + ')', themeDetail.getPathWord()));
                        } catch (Throwable th2) {
                            th = th2;
                            Result.Companion companion2 = Result.Companion;
                            obj = Result.constructor-impl(ResultKt.createFailure(th));
                        }
                    }
                    obj = Result.constructor-impl(arrayList);
                    if (Result.isSuccess-impl(obj)) {
                        List listMutableListOf = CollectionsKt.mutableListOf(new Tag[]{new Tag("全部 (" + count + ')', "")});
                        listMutableListOf.addAll((List) obj);
                        FilterKt.setThemeFilter((Tag[]) listMutableListOf.toArray(new Tag[0]));
                        FilterKt.fetchedRefreshTheme = true;
                        return;
                    }
                    return;
                }
                throw new Exception("Error: " + responseExecute.code() + " - " + responseExecute.message());
            }
        }, 31, (Object) null);
    }
}
