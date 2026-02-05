package eu.kanade.tachiyomi.extension.zh.copymanga;

import eu.kanade.tachiyomi.source.model.Filter;
import java.util.ArrayList;
import kotlin.Metadata;
import kotlin.jvm.internal.DefaultConstructorMarker;

/* compiled from: Filter.kt */
@Metadata(d1 = {"\u0000\u0010\n\u0002\u0018\u0002\n\u0002\u0018\u0002\n\u0002\u0010\u000e\n\u0002\b\u0002\b\u0000\u0018\u00002\b\u0012\u0004\u0012\u00020\u00020\u0001B\u0005¢\u0006\u0002\u0010\u0003¨\u0006\u0004"}, d2 = {"Leu/kanade/tachiyomi/extension/zh/copymanga/RankFilter;", "Leu/kanade/tachiyomi/source/model/Filter$Select;", "", "()V", "tachiyomi-zh.copymanga-v1.4.78_release"}, k = 1, mv = {1, 7, 1}, xi = 48)
/* loaded from: classes.dex */
public final class RankFilter extends Filter.Select<String> {
    public RankFilter() {
        Tag[] rankFilter = FilterKt.getRankFilter();
        ArrayList arrayList = new ArrayList(rankFilter.length);
        for (Tag tag : rankFilter) {
            arrayList.add(tag.getName());
        }
        super("排行榜", arrayList.toArray(new String[0]), 0, 4, (DefaultConstructorMarker) null);
    }
}
