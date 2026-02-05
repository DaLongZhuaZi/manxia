package eu.kanade.tachiyomi.extension.zh.copymanga;

import eu.kanade.tachiyomi.source.model.Filter;
import eu.kanade.tachiyomi.source.model.FilterList;
import kotlin.Metadata;
import kotlin.Unit;
import kotlin.concurrent.ThreadsKt;
import kotlin.jvm.functions.Function0;
import kotlin.jvm.internal.DefaultConstructorMarker;
import kotlin.jvm.internal.Intrinsics;
import okhttp3.OkHttpClient;

/* compiled from: Filter.kt */
@Metadata(d1 = {"\u0000(\n\u0000\n\u0002\u0010\u0011\n\u0002\u0018\u0002\n\u0002\b\u0004\n\u0002\u0010\u000b\n\u0002\b\u0011\n\u0002\u0018\u0002\n\u0000\n\u0002\u0018\u0002\n\u0000\n\u0002\u0010\u0002\n\u0000\u001a\u000e\u0010\u0018\u001a\u00020\u00192\u0006\u0010\u001a\u001a\u00020\u001b\u001a\u000e\u0010\u001c\u001a\u00020\u001d2\u0006\u0010\u001a\u001a\u00020\u001b\"\u0019\u0010\u0000\u001a\b\u0012\u0004\u0012\u00020\u00020\u0001¢\u0006\n\n\u0002\u0010\u0005\u001a\u0004\b\u0003\u0010\u0004\"\u000e\u0010\u0006\u001a\u00020\u0007X\u0082\u000e¢\u0006\u0002\n\u0000\"\u0019\u0010\b\u001a\b\u0012\u0004\u0012\u00020\u00020\u0001¢\u0006\n\n\u0002\u0010\u0005\u001a\u0004\b\t\u0010\u0004\"\u0019\u0010\n\u001a\b\u0012\u0004\u0012\u00020\u00020\u0001¢\u0006\n\n\u0002\u0010\u0005\u001a\u0004\b\u000b\u0010\u0004\"\u0019\u0010\f\u001a\b\u0012\u0004\u0012\u00020\u00020\u0001¢\u0006\n\n\u0002\u0010\u0005\u001a\u0004\b\r\u0010\u0004\"\u0019\u0010\u000e\u001a\b\u0012\u0004\u0012\u00020\u00020\u0001¢\u0006\n\n\u0002\u0010\u0005\u001a\u0004\b\u000f\u0010\u0004\"\u0019\u0010\u0010\u001a\b\u0012\u0004\u0012\u00020\u00020\u0001¢\u0006\n\n\u0002\u0010\u0005\u001a\u0004\b\u0011\u0010\u0004\"\"\u0010\u0012\u001a\b\u0012\u0004\u0012\u00020\u00020\u0001X\u0086\u000e¢\u0006\u0010\n\u0002\u0010\u0005\u001a\u0004\b\u0013\u0010\u0004\"\u0004\b\u0014\u0010\u0015\"\u0019\u0010\u0016\u001a\b\u0012\u0004\u0012\u00020\u00020\u0001¢\u0006\n\n\u0002\u0010\u0005\u001a\u0004\b\u0017\u0010\u0004¨\u0006\u001e"}, d2 = {"audienceFilter", "", "Leu/kanade/tachiyomi/extension/zh/copymanga/Tag;", "getAudienceFilter", "()[Leu/kanade/tachiyomi/extension/zh/copymanga/Tag;", "[Leu/kanade/tachiyomi/extension/zh/copymanga/Tag;", "fetchedRefreshTheme", "", "freeTypeFilter", "getFreeTypeFilter", "migrateFilter", "getMigrateFilter", "rankFilter", "getRankFilter", "regionFilter", "getRegionFilter", "sortFilter", "getSortFilter", "themeFilter", "getThemeFilter", "setThemeFilter", "([Leu/kanade/tachiyomi/extension/zh/copymanga/Tag;)V", "typeFilter", "getTypeFilter", "getFilterList", "Leu/kanade/tachiyomi/source/model/FilterList;", "client", "Lokhttp3/OkHttpClient;", "resetThemeFilter", "", "tachiyomi-zh.copymanga-v1.4.78_release"}, k = 2, mv = {1, 7, 1}, xi = 48)
/* loaded from: classes.dex */
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

            /* JADX WARN: Removed duplicated region for block: B:26:0x010b  */
            /* JADX WARN: Removed duplicated region for block: B:33:? A[RETURN, SYNTHETIC] */
            /* renamed from: invoke, reason: collision with other method in class */
            /*
                Code decompiled incorrectly, please refer to instructions dump.
                To view partially-correct code enable 'Show inconsistent code' option in preferences
            */
            public final void m1invoke() {
                /*
                    Method dump skipped, instructions count: 324
                    To view this dump change 'Code comments level' option to 'DEBUG'
                */
                throw new UnsupportedOperationException("Method not decompiled: eu.kanade.tachiyomi.extension.zh.copymanga.FilterKt.AnonymousClass1.m1invoke():void");
            }
        }, 31, (Object) null);
    }
}
