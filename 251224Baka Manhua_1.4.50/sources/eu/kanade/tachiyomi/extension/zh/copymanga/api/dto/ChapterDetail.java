package eu.kanade.tachiyomi.extension.zh.copymanga.api.dto;

import android.net.Uri;
import eu.kanade.tachiyomi.extension.zh.copymanga.ResolutionOption;
import eu.kanade.tachiyomi.source.model.Page;
import java.util.ArrayList;
import java.util.Comparator;
import java.util.List;
import kotlin.Deprecated;
import kotlin.DeprecationLevel;
import kotlin.Metadata;
import kotlin.Pair;
import kotlin.ReplaceWith;
import kotlin.collections.CollectionsKt;
import kotlin.comparisons.ComparisonsKt;
import kotlin.jvm.JvmStatic;
import kotlin.jvm.internal.DefaultConstructorMarker;
import kotlin.jvm.internal.Intrinsics;
import kotlinx.serialization.KSerializer;
import kotlinx.serialization.SerialName;
import kotlinx.serialization.Serializable;
import kotlinx.serialization.descriptors.SerialDescriptor;
import kotlinx.serialization.encoding.CompositeEncoder;
import kotlinx.serialization.internal.ArrayListSerializer;
import kotlinx.serialization.internal.IntSerializer;
import kotlinx.serialization.internal.PluginExceptionsKt;
import kotlinx.serialization.internal.SerializationConstructorMarker;
import kotlinx.serialization.internal.StringSerializer;

/* compiled from: ContentResult.kt */
@Metadata(d1 = {"\u0000R\n\u0002\u0018\u0002\n\u0002\u0010\u0000\n\u0000\n\u0002\u0010\b\n\u0002\b\u0002\n\u0002\u0010\u000e\n\u0002\b\u000e\n\u0002\u0010 \n\u0002\u0018\u0002\n\u0002\b\u0002\n\u0002\u0010\u000b\n\u0000\n\u0002\u0018\u0002\n\u0002\b5\n\u0002\u0018\u0002\n\u0002\b\u0003\n\u0002\u0010\u0002\n\u0002\b\u0002\n\u0002\u0018\u0002\n\u0000\n\u0002\u0018\u0002\n\u0002\b\u0003\b\u0087\b\u0018\u0000 \\2\u00020\u0001:\u0002[\\BÙ\u0001\b\u0017\u0012\u0006\u0010\u0002\u001a\u00020\u0003\u0012\u0006\u0010\u0004\u001a\u00020\u0003\u0012\b\u0010\u0005\u001a\u0004\u0018\u00010\u0006\u0012\u0006\u0010\u0007\u001a\u00020\u0003\u0012\u0006\u0010\b\u001a\u00020\u0003\u0012\u0006\u0010\t\u001a\u00020\u0003\u0012\b\u0010\n\u001a\u0004\u0018\u00010\u0006\u0012\n\b\u0001\u0010\u000b\u001a\u0004\u0018\u00010\u0006\u0012\n\b\u0001\u0010\f\u001a\u0004\u0018\u00010\u0006\u0012\n\b\u0001\u0010\r\u001a\u0004\u0018\u00010\u0006\u0012\n\b\u0001\u0010\u000e\u001a\u0004\u0018\u00010\u0006\u0012\u0006\u0010\u000f\u001a\u00020\u0003\u0012\b\u0010\u0010\u001a\u0004\u0018\u00010\u0006\u0012\n\b\u0001\u0010\u0011\u001a\u0004\u0018\u00010\u0006\u0012\b\u0010\u0012\u001a\u0004\u0018\u00010\u0006\u0012\b\u0010\u0013\u001a\u0004\u0018\u00010\u0006\u0012\u000e\u0010\u0014\u001a\n\u0012\u0004\u0012\u00020\u0016\u0018\u00010\u0015\u0012\u000e\u0010\u0017\u001a\n\u0012\u0004\u0012\u00020\u0003\u0018\u00010\u0015\u0012\b\b\u0001\u0010\u0018\u001a\u00020\u0019\u0012\b\u0010\u001a\u001a\u0004\u0018\u00010\u001b¢\u0006\u0002\u0010\u001cB±\u0001\u0012\u0006\u0010\u0004\u001a\u00020\u0003\u0012\u0006\u0010\u0005\u001a\u00020\u0006\u0012\u0006\u0010\u0007\u001a\u00020\u0003\u0012\u0006\u0010\b\u001a\u00020\u0003\u0012\u0006\u0010\t\u001a\u00020\u0003\u0012\u0006\u0010\n\u001a\u00020\u0006\u0012\u0006\u0010\u000b\u001a\u00020\u0006\u0012\u0006\u0010\f\u001a\u00020\u0006\u0012\n\b\u0002\u0010\r\u001a\u0004\u0018\u00010\u0006\u0012\u0006\u0010\u000e\u001a\u00020\u0006\u0012\u0006\u0010\u000f\u001a\u00020\u0003\u0012\u0006\u0010\u0010\u001a\u00020\u0006\u0012\u0006\u0010\u0011\u001a\u00020\u0006\u0012\n\b\u0002\u0010\u0012\u001a\u0004\u0018\u00010\u0006\u0012\n\b\u0002\u0010\u0013\u001a\u0004\u0018\u00010\u0006\u0012\f\u0010\u0014\u001a\b\u0012\u0004\u0012\u00020\u00160\u0015\u0012\u0010\b\u0002\u0010\u0017\u001a\n\u0012\u0004\u0012\u00020\u0003\u0018\u00010\u0015\u0012\u0006\u0010\u0018\u001a\u00020\u0019¢\u0006\u0002\u0010\u001dJ\t\u0010:\u001a\u00020\u0003HÆ\u0003J\t\u0010;\u001a\u00020\u0006HÆ\u0003J\t\u0010<\u001a\u00020\u0003HÆ\u0003J\t\u0010=\u001a\u00020\u0006HÆ\u0003J\t\u0010>\u001a\u00020\u0006HÆ\u0003J\u000b\u0010?\u001a\u0004\u0018\u00010\u0006HÆ\u0003J\u000b\u0010@\u001a\u0004\u0018\u00010\u0006HÆ\u0003J\u000f\u0010A\u001a\b\u0012\u0004\u0012\u00020\u00160\u0015HÆ\u0003J\u0011\u0010B\u001a\n\u0012\u0004\u0012\u00020\u0003\u0018\u00010\u0015HÆ\u0003J\t\u0010C\u001a\u00020\u0019HÆ\u0003J\t\u0010D\u001a\u00020\u0006HÆ\u0003J\t\u0010E\u001a\u00020\u0003HÆ\u0003J\t\u0010F\u001a\u00020\u0003HÆ\u0003J\t\u0010G\u001a\u00020\u0003HÆ\u0003J\t\u0010H\u001a\u00020\u0006HÆ\u0003J\t\u0010I\u001a\u00020\u0006HÆ\u0003J\t\u0010J\u001a\u00020\u0006HÆ\u0003J\u000b\u0010K\u001a\u0004\u0018\u00010\u0006HÆ\u0003JÑ\u0001\u0010L\u001a\u00020\u00002\b\b\u0002\u0010\u0004\u001a\u00020\u00032\b\b\u0002\u0010\u0005\u001a\u00020\u00062\b\b\u0002\u0010\u0007\u001a\u00020\u00032\b\b\u0002\u0010\b\u001a\u00020\u00032\b\b\u0002\u0010\t\u001a\u00020\u00032\b\b\u0002\u0010\n\u001a\u00020\u00062\b\b\u0002\u0010\u000b\u001a\u00020\u00062\b\b\u0002\u0010\f\u001a\u00020\u00062\n\b\u0002\u0010\r\u001a\u0004\u0018\u00010\u00062\b\b\u0002\u0010\u000e\u001a\u00020\u00062\b\b\u0002\u0010\u000f\u001a\u00020\u00032\b\b\u0002\u0010\u0010\u001a\u00020\u00062\b\b\u0002\u0010\u0011\u001a\u00020\u00062\n\b\u0002\u0010\u0012\u001a\u0004\u0018\u00010\u00062\n\b\u0002\u0010\u0013\u001a\u0004\u0018\u00010\u00062\u000e\b\u0002\u0010\u0014\u001a\b\u0012\u0004\u0012\u00020\u00160\u00152\u0010\b\u0002\u0010\u0017\u001a\n\u0012\u0004\u0012\u00020\u0003\u0018\u00010\u00152\b\b\u0002\u0010\u0018\u001a\u00020\u0019HÆ\u0001J\u0013\u0010M\u001a\u00020\u00192\b\u0010N\u001a\u0004\u0018\u00010\u0001HÖ\u0003J\t\u0010O\u001a\u00020\u0003HÖ\u0001J\u0016\u0010P\u001a\n\u0012\u0004\u0012\u00020Q\u0018\u00010\u00152\u0006\u0010R\u001a\u00020\u0006J\t\u0010S\u001a\u00020\u0006HÖ\u0001J!\u0010T\u001a\u00020U2\u0006\u0010V\u001a\u00020\u00002\u0006\u0010W\u001a\u00020X2\u0006\u0010Y\u001a\u00020ZHÇ\u0001R\u001c\u0010\u000b\u001a\u00020\u00068\u0006X\u0087\u0004¢\u0006\u000e\n\u0000\u0012\u0004\b\u001e\u0010\u001f\u001a\u0004\b \u0010!R\u001c\u0010\f\u001a\u00020\u00068\u0006X\u0087\u0004¢\u0006\u000e\n\u0000\u0012\u0004\b\"\u0010\u001f\u001a\u0004\b#\u0010!R\u0017\u0010\u0014\u001a\b\u0012\u0004\u0012\u00020\u00160\u0015¢\u0006\b\n\u0000\u001a\u0004\b$\u0010%R\u0011\u0010\u0007\u001a\u00020\u0003¢\u0006\b\n\u0000\u001a\u0004\b&\u0010'R\u001c\u0010\u0011\u001a\u00020\u00068\u0006X\u0087\u0004¢\u0006\u000e\n\u0000\u0012\u0004\b(\u0010\u001f\u001a\u0004\b)\u0010!R\u001e\u0010\r\u001a\u0004\u0018\u00010\u00068\u0006X\u0087\u0004¢\u0006\u000e\n\u0000\u0012\u0004\b*\u0010\u001f\u001a\u0004\b+\u0010!R\u001c\u0010\u000e\u001a\u00020\u00068\u0006X\u0087\u0004¢\u0006\u000e\n\u0000\u0012\u0004\b,\u0010\u001f\u001a\u0004\b-\u0010!R\u0011\u0010\u0004\u001a\u00020\u0003¢\u0006\b\n\u0000\u001a\u0004\b.\u0010'R\u001c\u0010\u0018\u001a\u00020\u00198\u0006X\u0087\u0004¢\u0006\u000e\n\u0000\u0012\u0004\b/\u0010\u001f\u001a\u0004\b\u0018\u00100R\u0011\u0010\n\u001a\u00020\u0006¢\u0006\b\n\u0000\u001a\u0004\b1\u0010!R\u0011\u0010\u0010\u001a\u00020\u0006¢\u0006\b\n\u0000\u001a\u0004\b2\u0010!R\u0013\u0010\u0013\u001a\u0004\u0018\u00010\u0006¢\u0006\b\n\u0000\u001a\u0004\b3\u0010!R\u0011\u0010\b\u001a\u00020\u0003¢\u0006\b\n\u0000\u001a\u0004\b4\u0010'R\u0013\u0010\u0012\u001a\u0004\u0018\u00010\u0006¢\u0006\b\n\u0000\u001a\u0004\b5\u0010!R\u0011\u0010\t\u001a\u00020\u0003¢\u0006\b\n\u0000\u001a\u0004\b6\u0010'R\u0011\u0010\u000f\u001a\u00020\u0003¢\u0006\b\n\u0000\u001a\u0004\b7\u0010'R\u0011\u0010\u0005\u001a\u00020\u0006¢\u0006\b\n\u0000\u001a\u0004\b8\u0010!R\u0019\u0010\u0017\u001a\n\u0012\u0004\u0012\u00020\u0003\u0018\u00010\u0015¢\u0006\b\n\u0000\u001a\u0004\b9\u0010%¨\u0006]"}, d2 = {"Leu/kanade/tachiyomi/extension/zh/copymanga/api/dto/ChapterDetail;", "", "seen1", "", "index", "uuid", "", "count", "ordered", "size", "name", "comicId", "comicPathWord", "groupId", "groupPathWord", "type", "news", "datetimeCreated", "prev", "next", "contents", "", "Leu/kanade/tachiyomi/extension/zh/copymanga/api/dto/ContentItem;", "words", "isLong", "", "serializationConstructorMarker", "Lkotlinx/serialization/internal/SerializationConstructorMarker;", "(IILjava/lang/String;IIILjava/lang/String;Ljava/lang/String;Ljava/lang/String;Ljava/lang/String;Ljava/lang/String;ILjava/lang/String;Ljava/lang/String;Ljava/lang/String;Ljava/lang/String;Ljava/util/List;Ljava/util/List;ZLkotlinx/serialization/internal/SerializationConstructorMarker;)V", "(ILjava/lang/String;IIILjava/lang/String;Ljava/lang/String;Ljava/lang/String;Ljava/lang/String;Ljava/lang/String;ILjava/lang/String;Ljava/lang/String;Ljava/lang/String;Ljava/lang/String;Ljava/util/List;Ljava/util/List;Z)V", "getComicId$annotations", "()V", "getComicId", "()Ljava/lang/String;", "getComicPathWord$annotations", "getComicPathWord", "getContents", "()Ljava/util/List;", "getCount", "()I", "getDatetimeCreated$annotations", "getDatetimeCreated", "getGroupId$annotations", "getGroupId", "getGroupPathWord$annotations", "getGroupPathWord", "getIndex", "isLong$annotations", "()Z", "getName", "getNews", "getNext", "getOrdered", "getPrev", "getSize", "getType", "getUuid", "getWords", "component1", "component10", "component11", "component12", "component13", "component14", "component15", "component16", "component17", "component18", "component2", "component3", "component4", "component5", "component6", "component7", "component8", "component9", "copy", "equals", "other", "hashCode", "toPageList", "Leu/kanade/tachiyomi/source/model/Page;", "resolution", "toString", "write$Self", "", "self", "output", "Lkotlinx/serialization/encoding/CompositeEncoder;", "serialDesc", "Lkotlinx/serialization/descriptors/SerialDescriptor;", "$serializer", "Companion", "tachiyomi-zh.copymanga-v1.4.78_release"}, k = 1, mv = {1, 7, 1}, xi = 48)
@Serializable
/* loaded from: classes.dex */
public final /* data */ class ChapterDetail {

    /* renamed from: Companion, reason: from kotlin metadata */
    public static final Companion INSTANCE = new Companion(null);
    private final String comicId;
    private final String comicPathWord;
    private final List<ContentItem> contents;
    private final int count;
    private final String datetimeCreated;
    private final String groupId;
    private final String groupPathWord;
    private final int index;
    private final boolean isLong;
    private final String name;
    private final String news;
    private final String next;
    private final int ordered;
    private final String prev;
    private final int size;
    private final int type;
    private final String uuid;
    private final List<Integer> words;

    @SerialName("comic_id")
    public static /* synthetic */ void getComicId$annotations() {
    }

    @SerialName("comic_path_word")
    public static /* synthetic */ void getComicPathWord$annotations() {
    }

    @SerialName("datetime_created")
    public static /* synthetic */ void getDatetimeCreated$annotations() {
    }

    @SerialName("group_id")
    public static /* synthetic */ void getGroupId$annotations() {
    }

    @SerialName("group_path_word")
    public static /* synthetic */ void getGroupPathWord$annotations() {
    }

    @SerialName("is_long")
    public static /* synthetic */ void isLong$annotations() {
    }

    /* renamed from: component1, reason: from getter */
    public final int getIndex() {
        return this.index;
    }

    /* renamed from: component10, reason: from getter */
    public final String getGroupPathWord() {
        return this.groupPathWord;
    }

    /* renamed from: component11, reason: from getter */
    public final int getType() {
        return this.type;
    }

    /* renamed from: component12, reason: from getter */
    public final String getNews() {
        return this.news;
    }

    /* renamed from: component13, reason: from getter */
    public final String getDatetimeCreated() {
        return this.datetimeCreated;
    }

    /* renamed from: component14, reason: from getter */
    public final String getPrev() {
        return this.prev;
    }

    /* renamed from: component15, reason: from getter */
    public final String getNext() {
        return this.next;
    }

    public final List<ContentItem> component16() {
        return this.contents;
    }

    public final List<Integer> component17() {
        return this.words;
    }

    /* renamed from: component18, reason: from getter */
    public final boolean getIsLong() {
        return this.isLong;
    }

    /* renamed from: component2, reason: from getter */
    public final String getUuid() {
        return this.uuid;
    }

    /* renamed from: component3, reason: from getter */
    public final int getCount() {
        return this.count;
    }

    /* renamed from: component4, reason: from getter */
    public final int getOrdered() {
        return this.ordered;
    }

    /* renamed from: component5, reason: from getter */
    public final int getSize() {
        return this.size;
    }

    /* renamed from: component6, reason: from getter */
    public final String getName() {
        return this.name;
    }

    /* renamed from: component7, reason: from getter */
    public final String getComicId() {
        return this.comicId;
    }

    /* renamed from: component8, reason: from getter */
    public final String getComicPathWord() {
        return this.comicPathWord;
    }

    /* renamed from: component9, reason: from getter */
    public final String getGroupId() {
        return this.groupId;
    }

    public final ChapterDetail copy(int index, String uuid, int count, int ordered, int size, String name, String comicId, String comicPathWord, String groupId, String groupPathWord, int type, String news, String datetimeCreated, String prev, String next, List<ContentItem> contents, List<Integer> words, boolean isLong) {
        Intrinsics.checkNotNullParameter(uuid, "uuid");
        Intrinsics.checkNotNullParameter(name, "name");
        Intrinsics.checkNotNullParameter(comicId, "comicId");
        Intrinsics.checkNotNullParameter(comicPathWord, "comicPathWord");
        Intrinsics.checkNotNullParameter(groupPathWord, "groupPathWord");
        Intrinsics.checkNotNullParameter(news, "news");
        Intrinsics.checkNotNullParameter(datetimeCreated, "datetimeCreated");
        Intrinsics.checkNotNullParameter(contents, "contents");
        return new ChapterDetail(index, uuid, count, ordered, size, name, comicId, comicPathWord, groupId, groupPathWord, type, news, datetimeCreated, prev, next, contents, words, isLong);
    }

    public boolean equals(Object other) {
        if (this == other) {
            return true;
        }
        if (!(other instanceof ChapterDetail)) {
            return false;
        }
        ChapterDetail chapterDetail = (ChapterDetail) other;
        return this.index == chapterDetail.index && Intrinsics.areEqual(this.uuid, chapterDetail.uuid) && this.count == chapterDetail.count && this.ordered == chapterDetail.ordered && this.size == chapterDetail.size && Intrinsics.areEqual(this.name, chapterDetail.name) && Intrinsics.areEqual(this.comicId, chapterDetail.comicId) && Intrinsics.areEqual(this.comicPathWord, chapterDetail.comicPathWord) && Intrinsics.areEqual(this.groupId, chapterDetail.groupId) && Intrinsics.areEqual(this.groupPathWord, chapterDetail.groupPathWord) && this.type == chapterDetail.type && Intrinsics.areEqual(this.news, chapterDetail.news) && Intrinsics.areEqual(this.datetimeCreated, chapterDetail.datetimeCreated) && Intrinsics.areEqual(this.prev, chapterDetail.prev) && Intrinsics.areEqual(this.next, chapterDetail.next) && Intrinsics.areEqual(this.contents, chapterDetail.contents) && Intrinsics.areEqual(this.words, chapterDetail.words) && this.isLong == chapterDetail.isLong;
    }

    /* JADX WARN: Multi-variable type inference failed */
    public int hashCode() {
        int iHashCode = ((((((((((((((this.index * 31) + this.uuid.hashCode()) * 31) + this.count) * 31) + this.ordered) * 31) + this.size) * 31) + this.name.hashCode()) * 31) + this.comicId.hashCode()) * 31) + this.comicPathWord.hashCode()) * 31;
        String str = this.groupId;
        int iHashCode2 = (((((((((iHashCode + (str == null ? 0 : str.hashCode())) * 31) + this.groupPathWord.hashCode()) * 31) + this.type) * 31) + this.news.hashCode()) * 31) + this.datetimeCreated.hashCode()) * 31;
        String str2 = this.prev;
        int iHashCode3 = (iHashCode2 + (str2 == null ? 0 : str2.hashCode())) * 31;
        String str3 = this.next;
        int iHashCode4 = (((iHashCode3 + (str3 == null ? 0 : str3.hashCode())) * 31) + this.contents.hashCode()) * 31;
        List<Integer> list = this.words;
        int iHashCode5 = (iHashCode4 + (list != null ? list.hashCode() : 0)) * 31;
        boolean z = this.isLong;
        int i = z;
        if (z != 0) {
            i = 1;
        }
        return iHashCode5 + i;
    }

    public String toString() {
        return "ChapterDetail(index=" + this.index + ", uuid=" + this.uuid + ", count=" + this.count + ", ordered=" + this.ordered + ", size=" + this.size + ", name=" + this.name + ", comicId=" + this.comicId + ", comicPathWord=" + this.comicPathWord + ", groupId=" + this.groupId + ", groupPathWord=" + this.groupPathWord + ", type=" + this.type + ", news=" + this.news + ", datetimeCreated=" + this.datetimeCreated + ", prev=" + this.prev + ", next=" + this.next + ", contents=" + this.contents + ", words=" + this.words + ", isLong=" + this.isLong + ')';
    }

    /* compiled from: ContentResult.kt */
    @Metadata(d1 = {"\u0000\u0016\n\u0002\u0018\u0002\n\u0002\u0010\u0000\n\u0002\b\u0002\n\u0002\u0018\u0002\n\u0002\u0018\u0002\n\u0000\b\u0086\u0003\u0018\u00002\u00020\u0001B\u0007\b\u0002¢\u0006\u0002\u0010\u0002J\u000f\u0010\u0003\u001a\b\u0012\u0004\u0012\u00020\u00050\u0004HÆ\u0001¨\u0006\u0006"}, d2 = {"Leu/kanade/tachiyomi/extension/zh/copymanga/api/dto/ChapterDetail$Companion;", "", "()V", "serializer", "Lkotlinx/serialization/KSerializer;", "Leu/kanade/tachiyomi/extension/zh/copymanga/api/dto/ChapterDetail;", "tachiyomi-zh.copymanga-v1.4.78_release"}, k = 1, mv = {1, 7, 1}, xi = 48)
    public static final class Companion {
        public /* synthetic */ Companion(DefaultConstructorMarker defaultConstructorMarker) {
            this();
        }

        private Companion() {
        }

        public final KSerializer<ChapterDetail> serializer() {
            return ChapterDetail$$serializer.INSTANCE;
        }
    }

    @Deprecated(level = DeprecationLevel.HIDDEN, message = "This synthesized declaration should not be used directly", replaceWith = @ReplaceWith(expression = "", imports = {}))
    public /* synthetic */ ChapterDetail(int i, int i2, String str, int i3, int i4, int i5, String str2, @SerialName("comic_id") String str3, @SerialName("comic_path_word") String str4, @SerialName("group_id") String str5, @SerialName("group_path_word") String str6, int i6, String str7, @SerialName("datetime_created") String str8, String str9, String str10, List list, List list2, @SerialName("is_long") boolean z, SerializationConstructorMarker serializationConstructorMarker) {
        if (171775 != (i & 171775)) {
            PluginExceptionsKt.throwMissingFieldException(i, 171775, ChapterDetail$$serializer.INSTANCE.getDescriptor());
        }
        this.index = i2;
        this.uuid = str;
        this.count = i3;
        this.ordered = i4;
        this.size = i5;
        this.name = str2;
        this.comicId = str3;
        this.comicPathWord = str4;
        if ((i & 256) == 0) {
            this.groupId = null;
        } else {
            this.groupId = str5;
        }
        this.groupPathWord = str6;
        this.type = i6;
        this.news = str7;
        this.datetimeCreated = str8;
        if ((i & 8192) == 0) {
            this.prev = null;
        } else {
            this.prev = str9;
        }
        if ((i & 16384) == 0) {
            this.next = null;
        } else {
            this.next = str10;
        }
        this.contents = list;
        if ((i & 65536) == 0) {
            this.words = null;
        } else {
            this.words = list2;
        }
        this.isLong = z;
    }

    public ChapterDetail(int i, String str, int i2, int i3, int i4, String str2, String str3, String str4, String str5, String str6, int i5, String str7, String str8, String str9, String str10, List<ContentItem> list, List<Integer> list2, boolean z) {
        Intrinsics.checkNotNullParameter(str, "uuid");
        Intrinsics.checkNotNullParameter(str2, "name");
        Intrinsics.checkNotNullParameter(str3, "comicId");
        Intrinsics.checkNotNullParameter(str4, "comicPathWord");
        Intrinsics.checkNotNullParameter(str6, "groupPathWord");
        Intrinsics.checkNotNullParameter(str7, "news");
        Intrinsics.checkNotNullParameter(str8, "datetimeCreated");
        Intrinsics.checkNotNullParameter(list, "contents");
        this.index = i;
        this.uuid = str;
        this.count = i2;
        this.ordered = i3;
        this.size = i4;
        this.name = str2;
        this.comicId = str3;
        this.comicPathWord = str4;
        this.groupId = str5;
        this.groupPathWord = str6;
        this.type = i5;
        this.news = str7;
        this.datetimeCreated = str8;
        this.prev = str9;
        this.next = str10;
        this.contents = list;
        this.words = list2;
        this.isLong = z;
    }

    @JvmStatic
    public static final void write$Self(ChapterDetail self, CompositeEncoder output, SerialDescriptor serialDesc) {
        Intrinsics.checkNotNullParameter(self, "self");
        Intrinsics.checkNotNullParameter(output, "output");
        Intrinsics.checkNotNullParameter(serialDesc, "serialDesc");
        output.encodeIntElement(serialDesc, 0, self.index);
        output.encodeStringElement(serialDesc, 1, self.uuid);
        output.encodeIntElement(serialDesc, 2, self.count);
        output.encodeIntElement(serialDesc, 3, self.ordered);
        output.encodeIntElement(serialDesc, 4, self.size);
        output.encodeStringElement(serialDesc, 5, self.name);
        output.encodeStringElement(serialDesc, 6, self.comicId);
        output.encodeStringElement(serialDesc, 7, self.comicPathWord);
        if (output.shouldEncodeElementDefault(serialDesc, 8) || self.groupId != null) {
            output.encodeNullableSerializableElement(serialDesc, 8, StringSerializer.INSTANCE, self.groupId);
        }
        output.encodeStringElement(serialDesc, 9, self.groupPathWord);
        output.encodeIntElement(serialDesc, 10, self.type);
        output.encodeStringElement(serialDesc, 11, self.news);
        output.encodeStringElement(serialDesc, 12, self.datetimeCreated);
        if (output.shouldEncodeElementDefault(serialDesc, 13) || self.prev != null) {
            output.encodeNullableSerializableElement(serialDesc, 13, StringSerializer.INSTANCE, self.prev);
        }
        if (output.shouldEncodeElementDefault(serialDesc, 14) || self.next != null) {
            output.encodeNullableSerializableElement(serialDesc, 14, StringSerializer.INSTANCE, self.next);
        }
        output.encodeSerializableElement(serialDesc, 15, new ArrayListSerializer(ContentItem$$serializer.INSTANCE), self.contents);
        if (output.shouldEncodeElementDefault(serialDesc, 16) || self.words != null) {
            output.encodeNullableSerializableElement(serialDesc, 16, new ArrayListSerializer(IntSerializer.INSTANCE), self.words);
        }
        output.encodeBooleanElement(serialDesc, 17, self.isLong);
    }

    public /* synthetic */ ChapterDetail(int i, String str, int i2, int i3, int i4, String str2, String str3, String str4, String str5, String str6, int i5, String str7, String str8, String str9, String str10, List list, List list2, boolean z, int i6, DefaultConstructorMarker defaultConstructorMarker) {
        this(i, str, i2, i3, i4, str2, str3, str4, (i6 & 256) != 0 ? null : str5, str6, i5, str7, str8, (i6 & 8192) != 0 ? null : str9, (i6 & 16384) != 0 ? null : str10, list, (i6 & 65536) != 0 ? null : list2, z);
    }

    public final int getIndex() {
        return this.index;
    }

    public final String getUuid() {
        return this.uuid;
    }

    public final int getCount() {
        return this.count;
    }

    public final int getOrdered() {
        return this.ordered;
    }

    public final int getSize() {
        return this.size;
    }

    public final String getName() {
        return this.name;
    }

    public final String getComicId() {
        return this.comicId;
    }

    public final String getComicPathWord() {
        return this.comicPathWord;
    }

    public final String getGroupId() {
        return this.groupId;
    }

    public final String getGroupPathWord() {
        return this.groupPathWord;
    }

    public final int getType() {
        return this.type;
    }

    public final String getNews() {
        return this.news;
    }

    public final String getDatetimeCreated() {
        return this.datetimeCreated;
    }

    public final String getPrev() {
        return this.prev;
    }

    public final String getNext() {
        return this.next;
    }

    public final List<ContentItem> getContents() {
        return this.contents;
    }

    public final List<Integer> getWords() {
        return this.words;
    }

    public final boolean isLong() {
        return this.isLong;
    }

    public final List<Page> toPageList(String resolution) {
        Intrinsics.checkNotNullParameter(resolution, "resolution");
        String url = ((ContentItem) CollectionsKt.first(this.contents)).getUrl();
        if (url == null || url.length() == 0) {
            return null;
        }
        List<Integer> list = this.words;
        if (list == null || list.isEmpty()) {
            List<ContentItem> list2 = this.contents;
            ArrayList arrayList = new ArrayList(CollectionsKt.collectionSizeOrDefault(list2, 10));
            int i = 0;
            for (Object obj : list2) {
                int i2 = i + 1;
                if (i < 0) {
                    CollectionsKt.throwIndexOverflow();
                }
                ContentItem contentItem = (ContentItem) obj;
                ResolutionOption.Companion companion = ResolutionOption.INSTANCE;
                String url2 = contentItem.getUrl();
                Intrinsics.checkNotNull(url2);
                arrayList.add(new Page(i, ResolutionOption.INSTANCE.translate(contentItem.getUrl(), resolution), companion.translate(url2, resolution), (Uri) null, 8, (DefaultConstructorMarker) null));
                i = i2;
            }
            return arrayList;
        }
        List listSortedWith = CollectionsKt.sortedWith(CollectionsKt.zip(this.contents, this.words), new Comparator() { // from class: eu.kanade.tachiyomi.extension.zh.copymanga.api.dto.ChapterDetail$toPageList$$inlined$sortedBy$1
            @Override // java.util.Comparator
            public final int compare(T t, T t2) {
                return ComparisonsKt.compareValues((Integer) ((Pair) t).getSecond(), (Integer) ((Pair) t2).getSecond());
            }
        });
        ArrayList arrayList2 = new ArrayList(CollectionsKt.collectionSizeOrDefault(listSortedWith, 10));
        int i3 = 0;
        for (Object obj2 : listSortedWith) {
            int i4 = i3 + 1;
            if (i3 < 0) {
                CollectionsKt.throwIndexOverflow();
            }
            ContentItem contentItem2 = (ContentItem) ((Pair) obj2).component1();
            ResolutionOption.Companion companion2 = ResolutionOption.INSTANCE;
            String url3 = contentItem2.getUrl();
            Intrinsics.checkNotNull(url3);
            arrayList2.add(new Page(i3, ResolutionOption.INSTANCE.translate(contentItem2.getUrl(), resolution), companion2.translate(url3, resolution), (Uri) null, 8, (DefaultConstructorMarker) null));
            i3 = i4;
        }
        return arrayList2;
    }
}
