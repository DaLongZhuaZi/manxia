package eu.kanade.tachiyomi.extension.zh.copymanga.api.dto;

import kotlin.Deprecated;
import kotlin.DeprecationLevel;
import kotlin.Metadata;
import kotlin.ReplaceWith;
import kotlin.jvm.JvmStatic;
import kotlin.jvm.internal.DefaultConstructorMarker;
import kotlin.jvm.internal.Intrinsics;
import kotlinx.serialization.KSerializer;
import kotlinx.serialization.SerialName;
import kotlinx.serialization.Serializable;
import kotlinx.serialization.descriptors.SerialDescriptor;
import kotlinx.serialization.encoding.CompositeEncoder;
import kotlinx.serialization.internal.PluginExceptionsKt;
import kotlinx.serialization.internal.SerializationConstructorMarker;

/* compiled from: RankResult.kt */
@Metadata(d1 = {"\u0000D\n\u0002\u0018\u0002\n\u0002\u0010\u0000\n\u0000\n\u0002\u0010\b\n\u0002\b\u0007\n\u0002\u0018\u0002\n\u0000\n\u0002\u0018\u0002\n\u0002\b\u0019\n\u0002\u0010\u000b\n\u0002\b\u0003\n\u0002\u0010\u000e\n\u0000\n\u0002\u0010\u0002\n\u0002\b\u0002\n\u0002\u0018\u0002\n\u0000\n\u0002\u0018\u0002\n\u0002\b\u0003\b\u0087\b\u0018\u0000 42\u00020\u0001:\u000234B[\b\u0017\u0012\u0006\u0010\u0002\u001a\u00020\u0003\u0012\u0006\u0010\u0004\u001a\u00020\u0003\u0012\b\b\u0001\u0010\u0005\u001a\u00020\u0003\u0012\b\b\u0001\u0010\u0006\u001a\u00020\u0003\u0012\b\b\u0001\u0010\u0007\u001a\u00020\u0003\u0012\b\b\u0001\u0010\b\u001a\u00020\u0003\u0012\u0006\u0010\t\u001a\u00020\u0003\u0012\b\u0010\n\u001a\u0004\u0018\u00010\u000b\u0012\b\u0010\f\u001a\u0004\u0018\u00010\r¢\u0006\u0002\u0010\u000eB=\u0012\u0006\u0010\u0004\u001a\u00020\u0003\u0012\u0006\u0010\u0005\u001a\u00020\u0003\u0012\u0006\u0010\u0006\u001a\u00020\u0003\u0012\u0006\u0010\u0007\u001a\u00020\u0003\u0012\u0006\u0010\b\u001a\u00020\u0003\u0012\u0006\u0010\t\u001a\u00020\u0003\u0012\u0006\u0010\n\u001a\u00020\u000b¢\u0006\u0002\u0010\u000fJ\t\u0010\u001e\u001a\u00020\u0003HÆ\u0003J\t\u0010\u001f\u001a\u00020\u0003HÆ\u0003J\t\u0010 \u001a\u00020\u0003HÆ\u0003J\t\u0010!\u001a\u00020\u0003HÆ\u0003J\t\u0010\"\u001a\u00020\u0003HÆ\u0003J\t\u0010#\u001a\u00020\u0003HÆ\u0003J\t\u0010$\u001a\u00020\u000bHÆ\u0003JO\u0010%\u001a\u00020\u00002\b\b\u0002\u0010\u0004\u001a\u00020\u00032\b\b\u0002\u0010\u0005\u001a\u00020\u00032\b\b\u0002\u0010\u0006\u001a\u00020\u00032\b\b\u0002\u0010\u0007\u001a\u00020\u00032\b\b\u0002\u0010\b\u001a\u00020\u00032\b\b\u0002\u0010\t\u001a\u00020\u00032\b\b\u0002\u0010\n\u001a\u00020\u000bHÆ\u0001J\u0013\u0010&\u001a\u00020'2\b\u0010(\u001a\u0004\u0018\u00010\u0001HÖ\u0003J\t\u0010)\u001a\u00020\u0003HÖ\u0001J\t\u0010*\u001a\u00020+HÖ\u0001J!\u0010,\u001a\u00020-2\u0006\u0010.\u001a\u00020\u00002\u0006\u0010/\u001a\u0002002\u0006\u00101\u001a\u000202HÇ\u0001R\u0011\u0010\n\u001a\u00020\u000b¢\u0006\b\n\u0000\u001a\u0004\b\u0010\u0010\u0011R\u001c\u0010\b\u001a\u00020\u00038\u0006X\u0087\u0004¢\u0006\u000e\n\u0000\u0012\u0004\b\u0012\u0010\u0013\u001a\u0004\b\u0014\u0010\u0015R\u0011\u0010\t\u001a\u00020\u0003¢\u0006\b\n\u0000\u001a\u0004\b\u0016\u0010\u0015R\u001c\u0010\u0007\u001a\u00020\u00038\u0006X\u0087\u0004¢\u0006\u000e\n\u0000\u0012\u0004\b\u0017\u0010\u0013\u001a\u0004\b\u0018\u0010\u0015R\u001c\u0010\u0006\u001a\u00020\u00038\u0006X\u0087\u0004¢\u0006\u000e\n\u0000\u0012\u0004\b\u0019\u0010\u0013\u001a\u0004\b\u001a\u0010\u0015R\u0011\u0010\u0004\u001a\u00020\u0003¢\u0006\b\n\u0000\u001a\u0004\b\u001b\u0010\u0015R\u001c\u0010\u0005\u001a\u00020\u00038\u0006X\u0087\u0004¢\u0006\u000e\n\u0000\u0012\u0004\b\u001c\u0010\u0013\u001a\u0004\b\u001d\u0010\u0015¨\u00065"}, d2 = {"Leu/kanade/tachiyomi/extension/zh/copymanga/api/dto/ListItem;", "", "seen1", "", "sort", "sortLast", "riseSort", "riseNum", "dateType", "popular", "comic", "Leu/kanade/tachiyomi/extension/zh/copymanga/api/dto/ComicInfo;", "serializationConstructorMarker", "Lkotlinx/serialization/internal/SerializationConstructorMarker;", "(IIIIIIILeu/kanade/tachiyomi/extension/zh/copymanga/api/dto/ComicInfo;Lkotlinx/serialization/internal/SerializationConstructorMarker;)V", "(IIIIIILeu/kanade/tachiyomi/extension/zh/copymanga/api/dto/ComicInfo;)V", "getComic", "()Leu/kanade/tachiyomi/extension/zh/copymanga/api/dto/ComicInfo;", "getDateType$annotations", "()V", "getDateType", "()I", "getPopular", "getRiseNum$annotations", "getRiseNum", "getRiseSort$annotations", "getRiseSort", "getSort", "getSortLast$annotations", "getSortLast", "component1", "component2", "component3", "component4", "component5", "component6", "component7", "copy", "equals", "", "other", "hashCode", "toString", "", "write$Self", "", "self", "output", "Lkotlinx/serialization/encoding/CompositeEncoder;", "serialDesc", "Lkotlinx/serialization/descriptors/SerialDescriptor;", "$serializer", "Companion", "tachiyomi-zh.copymanga-v1.4.78_release"}, k = 1, mv = {1, 7, 1}, xi = 48)
@Serializable
/* loaded from: classes.dex */
public final /* data */ class ListItem {

    /* renamed from: Companion, reason: from kotlin metadata */
    public static final Companion INSTANCE = new Companion(null);
    private final ComicInfo comic;
    private final int dateType;
    private final int popular;
    private final int riseNum;
    private final int riseSort;
    private final int sort;
    private final int sortLast;

    public static /* synthetic */ ListItem copy$default(ListItem listItem, int i, int i2, int i3, int i4, int i5, int i6, ComicInfo comicInfo, int i7, Object obj) {
        if ((i7 & 1) != 0) {
            i = listItem.sort;
        }
        if ((i7 & 2) != 0) {
            i2 = listItem.sortLast;
        }
        int i8 = i2;
        if ((i7 & 4) != 0) {
            i3 = listItem.riseSort;
        }
        int i9 = i3;
        if ((i7 & 8) != 0) {
            i4 = listItem.riseNum;
        }
        int i10 = i4;
        if ((i7 & 16) != 0) {
            i5 = listItem.dateType;
        }
        int i11 = i5;
        if ((i7 & 32) != 0) {
            i6 = listItem.popular;
        }
        int i12 = i6;
        if ((i7 & 64) != 0) {
            comicInfo = listItem.comic;
        }
        return listItem.copy(i, i8, i9, i10, i11, i12, comicInfo);
    }

    @SerialName("date_type")
    public static /* synthetic */ void getDateType$annotations() {
    }

    @SerialName("rise_num")
    public static /* synthetic */ void getRiseNum$annotations() {
    }

    @SerialName("rise_sort")
    public static /* synthetic */ void getRiseSort$annotations() {
    }

    @SerialName("sort_last")
    public static /* synthetic */ void getSortLast$annotations() {
    }

    /* renamed from: component1, reason: from getter */
    public final int getSort() {
        return this.sort;
    }

    /* renamed from: component2, reason: from getter */
    public final int getSortLast() {
        return this.sortLast;
    }

    /* renamed from: component3, reason: from getter */
    public final int getRiseSort() {
        return this.riseSort;
    }

    /* renamed from: component4, reason: from getter */
    public final int getRiseNum() {
        return this.riseNum;
    }

    /* renamed from: component5, reason: from getter */
    public final int getDateType() {
        return this.dateType;
    }

    /* renamed from: component6, reason: from getter */
    public final int getPopular() {
        return this.popular;
    }

    /* renamed from: component7, reason: from getter */
    public final ComicInfo getComic() {
        return this.comic;
    }

    public final ListItem copy(int sort, int sortLast, int riseSort, int riseNum, int dateType, int popular, ComicInfo comic) {
        Intrinsics.checkNotNullParameter(comic, "comic");
        return new ListItem(sort, sortLast, riseSort, riseNum, dateType, popular, comic);
    }

    public boolean equals(Object other) {
        if (this == other) {
            return true;
        }
        if (!(other instanceof ListItem)) {
            return false;
        }
        ListItem listItem = (ListItem) other;
        return this.sort == listItem.sort && this.sortLast == listItem.sortLast && this.riseSort == listItem.riseSort && this.riseNum == listItem.riseNum && this.dateType == listItem.dateType && this.popular == listItem.popular && Intrinsics.areEqual(this.comic, listItem.comic);
    }

    public int hashCode() {
        return (((((((((((this.sort * 31) + this.sortLast) * 31) + this.riseSort) * 31) + this.riseNum) * 31) + this.dateType) * 31) + this.popular) * 31) + this.comic.hashCode();
    }

    public String toString() {
        return "ListItem(sort=" + this.sort + ", sortLast=" + this.sortLast + ", riseSort=" + this.riseSort + ", riseNum=" + this.riseNum + ", dateType=" + this.dateType + ", popular=" + this.popular + ", comic=" + this.comic + ')';
    }

    /* compiled from: RankResult.kt */
    @Metadata(d1 = {"\u0000\u0016\n\u0002\u0018\u0002\n\u0002\u0010\u0000\n\u0002\b\u0002\n\u0002\u0018\u0002\n\u0002\u0018\u0002\n\u0000\b\u0086\u0003\u0018\u00002\u00020\u0001B\u0007\b\u0002¢\u0006\u0002\u0010\u0002J\u000f\u0010\u0003\u001a\b\u0012\u0004\u0012\u00020\u00050\u0004HÆ\u0001¨\u0006\u0006"}, d2 = {"Leu/kanade/tachiyomi/extension/zh/copymanga/api/dto/ListItem$Companion;", "", "()V", "serializer", "Lkotlinx/serialization/KSerializer;", "Leu/kanade/tachiyomi/extension/zh/copymanga/api/dto/ListItem;", "tachiyomi-zh.copymanga-v1.4.78_release"}, k = 1, mv = {1, 7, 1}, xi = 48)
    public static final class Companion {
        public /* synthetic */ Companion(DefaultConstructorMarker defaultConstructorMarker) {
            this();
        }

        private Companion() {
        }

        public final KSerializer<ListItem> serializer() {
            return ListItem$$serializer.INSTANCE;
        }
    }

    @Deprecated(level = DeprecationLevel.HIDDEN, message = "This synthesized declaration should not be used directly", replaceWith = @ReplaceWith(expression = "", imports = {}))
    public /* synthetic */ ListItem(int i, int i2, @SerialName("sort_last") int i3, @SerialName("rise_sort") int i4, @SerialName("rise_num") int i5, @SerialName("date_type") int i6, int i7, ComicInfo comicInfo, SerializationConstructorMarker serializationConstructorMarker) {
        if (127 != (i & 127)) {
            PluginExceptionsKt.throwMissingFieldException(i, 127, ListItem$$serializer.INSTANCE.getDescriptor());
        }
        this.sort = i2;
        this.sortLast = i3;
        this.riseSort = i4;
        this.riseNum = i5;
        this.dateType = i6;
        this.popular = i7;
        this.comic = comicInfo;
    }

    public ListItem(int i, int i2, int i3, int i4, int i5, int i6, ComicInfo comicInfo) {
        Intrinsics.checkNotNullParameter(comicInfo, "comic");
        this.sort = i;
        this.sortLast = i2;
        this.riseSort = i3;
        this.riseNum = i4;
        this.dateType = i5;
        this.popular = i6;
        this.comic = comicInfo;
    }

    @JvmStatic
    public static final void write$Self(ListItem self, CompositeEncoder output, SerialDescriptor serialDesc) {
        Intrinsics.checkNotNullParameter(self, "self");
        Intrinsics.checkNotNullParameter(output, "output");
        Intrinsics.checkNotNullParameter(serialDesc, "serialDesc");
        output.encodeIntElement(serialDesc, 0, self.sort);
        output.encodeIntElement(serialDesc, 1, self.sortLast);
        output.encodeIntElement(serialDesc, 2, self.riseSort);
        output.encodeIntElement(serialDesc, 3, self.riseNum);
        output.encodeIntElement(serialDesc, 4, self.dateType);
        output.encodeIntElement(serialDesc, 5, self.popular);
        output.encodeSerializableElement(serialDesc, 6, ComicInfo$$serializer.INSTANCE, self.comic);
    }

    public final int getSort() {
        return this.sort;
    }

    public final int getSortLast() {
        return this.sortLast;
    }

    public final int getRiseSort() {
        return this.riseSort;
    }

    public final int getRiseNum() {
        return this.riseNum;
    }

    public final int getDateType() {
        return this.dateType;
    }

    public final int getPopular() {
        return this.popular;
    }

    public final ComicInfo getComic() {
        return this.comic;
    }
}
