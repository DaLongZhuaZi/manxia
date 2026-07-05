package eu.kanade.tachiyomi.extension.zh.copymanga.api.dto;

import eu.kanade.tachiyomi.extension.zh.copymanga.CCOption;
import eu.kanade.tachiyomi.extension.zh.copymanga.language.TranslateKt;
import eu.kanade.tachiyomi.source.model.SManga;
import java.util.List;
import kotlin.Deprecated;
import kotlin.DeprecationLevel;
import kotlin.Metadata;
import kotlin.ReplaceWith;
import kotlin.collections.CollectionsKt;
import kotlin.jvm.JvmStatic;
import kotlin.jvm.functions.Function1;
import kotlin.jvm.internal.DefaultConstructorMarker;
import kotlin.jvm.internal.Intrinsics;
import kotlin.jvm.internal.Reflection;
import kotlinx.serialization.ContextualSerializer;
import kotlinx.serialization.KSerializer;
import kotlinx.serialization.SerialName;
import kotlinx.serialization.Serializable;
import kotlinx.serialization.descriptors.SerialDescriptor;
import kotlinx.serialization.encoding.CompositeEncoder;
import kotlinx.serialization.internal.ArrayListSerializer;
import kotlinx.serialization.internal.IntSerializer;
import kotlinx.serialization.internal.PluginExceptionsKt;
import kotlinx.serialization.internal.SerializationConstructorMarker;
import kotlinx.serialization.json.JsonElement;
import kotlinx.serialization.json.JsonElementSerializer;

/* JADX INFO: compiled from: CollectResult.kt */
/* JADX INFO: loaded from: classes.dex */
@Metadata(d1 = {"\u0000n\n\u0002\u0018\u0002\n\u0002\u0010\u0000\n\u0000\n\u0002\u0010\b\n\u0000\n\u0002\u0010\u000e\n\u0000\n\u0002\u0010\u000b\n\u0002\b\u0003\n\u0002\u0010 \n\u0002\u0018\u0002\n\u0002\u0018\u0002\n\u0002\b\u0002\n\u0002\u0018\u0002\n\u0000\n\u0002\u0018\u0002\n\u0002\b\u0007\n\u0002\u0018\u0002\n\u0000\n\u0002\u0018\u0002\n\u0002\b3\n\u0002\u0018\u0002\n\u0000\n\u0002\u0018\u0002\n\u0002\b\u0002\n\u0002\u0010\u0002\n\u0002\b\u0002\n\u0002\u0018\u0002\n\u0000\n\u0002\u0018\u0002\n\u0002\b\u0003\b\u0087\b\u0018\u0000 \\2\u00020\u0001:\u0002[\\BÜ\u0001\b\u0017\u0012\u0006\u0010\u0002\u001a\u00020\u0003\u0012\b\u0010\u0004\u001a\u0004\u0018\u00010\u0005\u0012\b\b\u0001\u0010\u0006\u001a\u00020\u0007\u0012\b\u0010\b\u001a\u0004\u0018\u00010\u0005\u0012\n\b\u0001\u0010\t\u001a\u0004\u0018\u00010\u0005\u0012\u0013\u0010\n\u001a\u000f\u0012\t\u0012\u00070\f¢\u0006\u0002\b\r\u0018\u00010\u000b\u0012\u0013\u0010\u000e\u001a\u000f\u0012\t\u0012\u00070\f¢\u0006\u0002\b\r\u0018\u00010\u000b\u0012\u000e\u0010\u000f\u001a\n\u0012\u0004\u0012\u00020\u0010\u0018\u00010\u000b\u0012\u0013\u0010\u0011\u001a\u000f\u0012\t\u0012\u00070\u0012¢\u0006\u0002\b\r\u0018\u00010\u000b\u0012\b\u0010\u0013\u001a\u0004\u0018\u00010\u0005\u0012\b\u0010\u0014\u001a\u0004\u0018\u00010\u0003\u0012\u0006\u0010\u0015\u001a\u00020\u0003\u0012\n\b\u0001\u0010\u0016\u001a\u0004\u0018\u00010\u0005\u0012\n\b\u0001\u0010\u0017\u001a\u0004\u0018\u00010\u0005\u0012\n\b\u0001\u0010\u0018\u001a\u0004\u0018\u00010\u0005\u0012\b\u0010\u0019\u001a\u0004\u0018\u00010\u001a\u0012\b\u0010\u001b\u001a\u0004\u0018\u00010\u001c¢\u0006\u0002\u0010\u001dB²\u0001\u0012\u0006\u0010\u0004\u001a\u00020\u0005\u0012\u0006\u0010\u0006\u001a\u00020\u0007\u0012\u0006\u0010\b\u001a\u00020\u0005\u0012\u0006\u0010\t\u001a\u00020\u0005\u0012\u0013\b\u0002\u0010\n\u001a\r\u0012\t\u0012\u00070\f¢\u0006\u0002\b\r0\u000b\u0012\u0013\b\u0002\u0010\u000e\u001a\r\u0012\t\u0012\u00070\f¢\u0006\u0002\b\r0\u000b\u0012\f\u0010\u000f\u001a\b\u0012\u0004\u0012\u00020\u00100\u000b\u0012\u0013\b\u0002\u0010\u0011\u001a\r\u0012\t\u0012\u00070\u0012¢\u0006\u0002\b\r0\u000b\u0012\u0006\u0010\u0013\u001a\u00020\u0005\u0012\n\b\u0002\u0010\u0014\u001a\u0004\u0018\u00010\u0003\u0012\u0006\u0010\u0015\u001a\u00020\u0003\u0012\u0006\u0010\u0016\u001a\u00020\u0005\u0012\u0006\u0010\u0017\u001a\u00020\u0005\u0012\u0006\u0010\u0018\u001a\u00020\u0005\u0012\n\b\u0002\u0010\u0019\u001a\u0004\u0018\u00010\u001a¢\u0006\u0002\u0010\u001eJ\t\u0010;\u001a\u00020\u0005HÆ\u0003J\u0010\u0010<\u001a\u0004\u0018\u00010\u0003HÆ\u0003¢\u0006\u0002\u00107J\t\u0010=\u001a\u00020\u0003HÆ\u0003J\t\u0010>\u001a\u00020\u0005HÆ\u0003J\t\u0010?\u001a\u00020\u0005HÆ\u0003J\t\u0010@\u001a\u00020\u0005HÆ\u0003J\u000b\u0010A\u001a\u0004\u0018\u00010\u001aHÆ\u0003J\t\u0010B\u001a\u00020\u0007HÆ\u0003J\t\u0010C\u001a\u00020\u0005HÆ\u0003J\t\u0010D\u001a\u00020\u0005HÆ\u0003J\u0014\u0010E\u001a\r\u0012\t\u0012\u00070\f¢\u0006\u0002\b\r0\u000bHÆ\u0003J\u0014\u0010F\u001a\r\u0012\t\u0012\u00070\f¢\u0006\u0002\b\r0\u000bHÆ\u0003J\u000f\u0010G\u001a\b\u0012\u0004\u0012\u00020\u00100\u000bHÆ\u0003J\u0014\u0010H\u001a\r\u0012\t\u0012\u00070\u0012¢\u0006\u0002\b\r0\u000bHÆ\u0003J\t\u0010I\u001a\u00020\u0005HÆ\u0003JÏ\u0001\u0010J\u001a\u00020\u00002\b\b\u0002\u0010\u0004\u001a\u00020\u00052\b\b\u0002\u0010\u0006\u001a\u00020\u00072\b\b\u0002\u0010\b\u001a\u00020\u00052\b\b\u0002\u0010\t\u001a\u00020\u00052\u0013\b\u0002\u0010\n\u001a\r\u0012\t\u0012\u00070\f¢\u0006\u0002\b\r0\u000b2\u0013\b\u0002\u0010\u000e\u001a\r\u0012\t\u0012\u00070\f¢\u0006\u0002\b\r0\u000b2\u000e\b\u0002\u0010\u000f\u001a\b\u0012\u0004\u0012\u00020\u00100\u000b2\u0013\b\u0002\u0010\u0011\u001a\r\u0012\t\u0012\u00070\u0012¢\u0006\u0002\b\r0\u000b2\b\b\u0002\u0010\u0013\u001a\u00020\u00052\n\b\u0002\u0010\u0014\u001a\u0004\u0018\u00010\u00032\b\b\u0002\u0010\u0015\u001a\u00020\u00032\b\b\u0002\u0010\u0016\u001a\u00020\u00052\b\b\u0002\u0010\u0017\u001a\u00020\u00052\b\b\u0002\u0010\u0018\u001a\u00020\u00052\n\b\u0002\u0010\u0019\u001a\u0004\u0018\u00010\u001aHÆ\u0001¢\u0006\u0002\u0010KJ\u0013\u0010L\u001a\u00020\u00072\b\u0010M\u001a\u0004\u0018\u00010\u0001HÖ\u0003J\t\u0010N\u001a\u00020\u0003HÖ\u0001J\u000e\u0010O\u001a\u00020P2\u0006\u0010Q\u001a\u00020RJ\t\u0010S\u001a\u00020\u0005HÖ\u0001J!\u0010T\u001a\u00020U2\u0006\u0010V\u001a\u00020\u00002\u0006\u0010W\u001a\u00020X2\u0006\u0010Y\u001a\u00020ZHÇ\u0001R\u0017\u0010\u000f\u001a\b\u0012\u0004\u0012\u00020\u00100\u000b¢\u0006\b\n\u0000\u001a\u0004\b\u001f\u0010 R\u001c\u0010\u0006\u001a\u00020\u00078\u0006X\u0087\u0004¢\u0006\u000e\n\u0000\u0012\u0004\b!\u0010\"\u001a\u0004\b#\u0010$R\u0013\u0010\u0019\u001a\u0004\u0018\u00010\u001a¢\u0006\b\n\u0000\u001a\u0004\b%\u0010&R\u0011\u0010\u0013\u001a\u00020\u0005¢\u0006\b\n\u0000\u001a\u0004\b'\u0010(R\u001c\u0010\u0016\u001a\u00020\u00058\u0006X\u0087\u0004¢\u0006\u000e\n\u0000\u0012\u0004\b)\u0010\"\u001a\u0004\b*\u0010(R\u001c\u0010\n\u001a\r\u0012\t\u0012\u00070\f¢\u0006\u0002\b\r0\u000b¢\u0006\b\n\u0000\u001a\u0004\b+\u0010 R\u001c\u0010\u0017\u001a\u00020\u00058\u0006X\u0087\u0004¢\u0006\u000e\n\u0000\u0012\u0004\b,\u0010\"\u001a\u0004\b-\u0010(R\u001c\u0010\u0018\u001a\u00020\u00058\u0006X\u0087\u0004¢\u0006\u000e\n\u0000\u0012\u0004\b.\u0010\"\u001a\u0004\b/\u0010(R\u001c\u0010\u000e\u001a\r\u0012\t\u0012\u00070\f¢\u0006\u0002\b\r0\u000b¢\u0006\b\n\u0000\u001a\u0004\b0\u0010 R\u0011\u0010\b\u001a\u00020\u0005¢\u0006\b\n\u0000\u001a\u0004\b1\u0010(R\u001c\u0010\t\u001a\u00020\u00058\u0006X\u0087\u0004¢\u0006\u000e\n\u0000\u0012\u0004\b2\u0010\"\u001a\u0004\b3\u0010(R\u0011\u0010\u0015\u001a\u00020\u0003¢\u0006\b\n\u0000\u001a\u0004\b4\u00105R\u0015\u0010\u0014\u001a\u0004\u0018\u00010\u0003¢\u0006\n\n\u0002\u00108\u001a\u0004\b6\u00107R\u001c\u0010\u0011\u001a\r\u0012\t\u0012\u00070\u0012¢\u0006\u0002\b\r0\u000b¢\u0006\b\n\u0000\u001a\u0004\b9\u0010 R\u0011\u0010\u0004\u001a\u00020\u0005¢\u0006\b\n\u0000\u001a\u0004\b:\u0010(¨\u0006]"}, d2 = {"Leu/kanade/tachiyomi/extension/zh/copymanga/api/dto/CollectComic;", "", "seen1", "", "uuid", "", "bDisplay", "", "name", "pathWord", "females", "", "Lkotlinx/serialization/json/JsonElement;", "Lkotlinx/serialization/Contextual;", "males", "author", "Leu/kanade/tachiyomi/extension/zh/copymanga/api/dto/AuthorInfo;", "theme", "Leu/kanade/tachiyomi/extension/zh/copymanga/api/dto/ThemeInfo;", "cover", "status", "popular", "datetimeUpdated", "lastChapterId", "lastChapterName", "browse", "Leu/kanade/tachiyomi/extension/zh/copymanga/api/dto/Browse;", "serializationConstructorMarker", "Lkotlinx/serialization/internal/SerializationConstructorMarker;", "(ILjava/lang/String;ZLjava/lang/String;Ljava/lang/String;Ljava/util/List;Ljava/util/List;Ljava/util/List;Ljava/util/List;Ljava/lang/String;Ljava/lang/Integer;ILjava/lang/String;Ljava/lang/String;Ljava/lang/String;Leu/kanade/tachiyomi/extension/zh/copymanga/api/dto/Browse;Lkotlinx/serialization/internal/SerializationConstructorMarker;)V", "(Ljava/lang/String;ZLjava/lang/String;Ljava/lang/String;Ljava/util/List;Ljava/util/List;Ljava/util/List;Ljava/util/List;Ljava/lang/String;Ljava/lang/Integer;ILjava/lang/String;Ljava/lang/String;Ljava/lang/String;Leu/kanade/tachiyomi/extension/zh/copymanga/api/dto/Browse;)V", "getAuthor", "()Ljava/util/List;", "getBDisplay$annotations", "()V", "getBDisplay", "()Z", "getBrowse", "()Leu/kanade/tachiyomi/extension/zh/copymanga/api/dto/Browse;", "getCover", "()Ljava/lang/String;", "getDatetimeUpdated$annotations", "getDatetimeUpdated", "getFemales", "getLastChapterId$annotations", "getLastChapterId", "getLastChapterName$annotations", "getLastChapterName", "getMales", "getName", "getPathWord$annotations", "getPathWord", "getPopular", "()I", "getStatus", "()Ljava/lang/Integer;", "Ljava/lang/Integer;", "getTheme", "getUuid", "component1", "component10", "component11", "component12", "component13", "component14", "component15", "component2", "component3", "component4", "component5", "component6", "component7", "component8", "component9", "copy", "(Ljava/lang/String;ZLjava/lang/String;Ljava/lang/String;Ljava/util/List;Ljava/util/List;Ljava/util/List;Ljava/util/List;Ljava/lang/String;Ljava/lang/Integer;ILjava/lang/String;Ljava/lang/String;Ljava/lang/String;Leu/kanade/tachiyomi/extension/zh/copymanga/api/dto/Browse;)Leu/kanade/tachiyomi/extension/zh/copymanga/api/dto/CollectComic;", "equals", "other", "hashCode", "toSManga", "Leu/kanade/tachiyomi/source/model/SManga;", "language", "Leu/kanade/tachiyomi/extension/zh/copymanga/CCOption;", "toString", "write$Self", "", "self", "output", "Lkotlinx/serialization/encoding/CompositeEncoder;", "serialDesc", "Lkotlinx/serialization/descriptors/SerialDescriptor;", "$serializer", "Companion", "tachiyomi-zh.copymanga-v1.4.82_release"}, k = 1, mv = {1, 7, 1}, xi = 48)
@Serializable
public final /* data */ class CollectComic {

    /* JADX INFO: renamed from: Companion, reason: from kotlin metadata */
    public static final Companion INSTANCE = new Companion(null);
    private final List<AuthorInfo> author;
    private final boolean bDisplay;
    private final Browse browse;
    private final String cover;
    private final String datetimeUpdated;
    private final List<JsonElement> females;
    private final String lastChapterId;
    private final String lastChapterName;
    private final List<JsonElement> males;
    private final String name;
    private final String pathWord;
    private final int popular;
    private final Integer status;
    private final List<ThemeInfo> theme;
    private final String uuid;

    @SerialName("b_display")
    public static /* synthetic */ void getBDisplay$annotations() {
    }

    @SerialName("datetime_updated")
    public static /* synthetic */ void getDatetimeUpdated$annotations() {
    }

    @SerialName("last_chapter_id")
    public static /* synthetic */ void getLastChapterId$annotations() {
    }

    @SerialName("last_chapter_name")
    public static /* synthetic */ void getLastChapterName$annotations() {
    }

    @SerialName("path_word")
    public static /* synthetic */ void getPathWord$annotations() {
    }

    /* JADX INFO: renamed from: component1, reason: from getter */
    public final String getUuid() {
        return this.uuid;
    }

    /* JADX INFO: renamed from: component10, reason: from getter */
    public final Integer getStatus() {
        return this.status;
    }

    /* JADX INFO: renamed from: component11, reason: from getter */
    public final int getPopular() {
        return this.popular;
    }

    /* JADX INFO: renamed from: component12, reason: from getter */
    public final String getDatetimeUpdated() {
        return this.datetimeUpdated;
    }

    /* JADX INFO: renamed from: component13, reason: from getter */
    public final String getLastChapterId() {
        return this.lastChapterId;
    }

    /* JADX INFO: renamed from: component14, reason: from getter */
    public final String getLastChapterName() {
        return this.lastChapterName;
    }

    /* JADX INFO: renamed from: component15, reason: from getter */
    public final Browse getBrowse() {
        return this.browse;
    }

    /* JADX INFO: renamed from: component2, reason: from getter */
    public final boolean getBDisplay() {
        return this.bDisplay;
    }

    /* JADX INFO: renamed from: component3, reason: from getter */
    public final String getName() {
        return this.name;
    }

    /* JADX INFO: renamed from: component4, reason: from getter */
    public final String getPathWord() {
        return this.pathWord;
    }

    public final List<JsonElement> component5() {
        return this.females;
    }

    public final List<JsonElement> component6() {
        return this.males;
    }

    public final List<AuthorInfo> component7() {
        return this.author;
    }

    public final List<ThemeInfo> component8() {
        return this.theme;
    }

    /* JADX INFO: renamed from: component9, reason: from getter */
    public final String getCover() {
        return this.cover;
    }

    public final CollectComic copy(String uuid, boolean bDisplay, String name, String pathWord, List<? extends JsonElement> females, List<? extends JsonElement> males, List<AuthorInfo> author, List<ThemeInfo> theme, String cover, Integer status, int popular, String datetimeUpdated, String lastChapterId, String lastChapterName, Browse browse) {
        Intrinsics.checkNotNullParameter(uuid, "uuid");
        Intrinsics.checkNotNullParameter(name, "name");
        Intrinsics.checkNotNullParameter(pathWord, "pathWord");
        Intrinsics.checkNotNullParameter(females, "females");
        Intrinsics.checkNotNullParameter(males, "males");
        Intrinsics.checkNotNullParameter(author, "author");
        Intrinsics.checkNotNullParameter(theme, "theme");
        Intrinsics.checkNotNullParameter(cover, "cover");
        Intrinsics.checkNotNullParameter(datetimeUpdated, "datetimeUpdated");
        Intrinsics.checkNotNullParameter(lastChapterId, "lastChapterId");
        Intrinsics.checkNotNullParameter(lastChapterName, "lastChapterName");
        return new CollectComic(uuid, bDisplay, name, pathWord, females, males, author, theme, cover, status, popular, datetimeUpdated, lastChapterId, lastChapterName, browse);
    }

    public boolean equals(Object other) {
        if (this == other) {
            return true;
        }
        if (!(other instanceof CollectComic)) {
            return false;
        }
        CollectComic collectComic = (CollectComic) other;
        return Intrinsics.areEqual(this.uuid, collectComic.uuid) && this.bDisplay == collectComic.bDisplay && Intrinsics.areEqual(this.name, collectComic.name) && Intrinsics.areEqual(this.pathWord, collectComic.pathWord) && Intrinsics.areEqual(this.females, collectComic.females) && Intrinsics.areEqual(this.males, collectComic.males) && Intrinsics.areEqual(this.author, collectComic.author) && Intrinsics.areEqual(this.theme, collectComic.theme) && Intrinsics.areEqual(this.cover, collectComic.cover) && Intrinsics.areEqual(this.status, collectComic.status) && this.popular == collectComic.popular && Intrinsics.areEqual(this.datetimeUpdated, collectComic.datetimeUpdated) && Intrinsics.areEqual(this.lastChapterId, collectComic.lastChapterId) && Intrinsics.areEqual(this.lastChapterName, collectComic.lastChapterName) && Intrinsics.areEqual(this.browse, collectComic.browse);
    }

    /* JADX WARN: Multi-variable type inference failed */
    /* JADX WARN: Type inference failed for: r1v1, types: [int] */
    /* JADX WARN: Type inference failed for: r1v28 */
    /* JADX WARN: Type inference failed for: r1v29 */
    public int hashCode() {
        int iHashCode = this.uuid.hashCode() * 31;
        boolean z = this.bDisplay;
        ?? r1 = z;
        if (z) {
            r1 = 1;
        }
        int iHashCode2 = (((((((((((((((iHashCode + r1) * 31) + this.name.hashCode()) * 31) + this.pathWord.hashCode()) * 31) + this.females.hashCode()) * 31) + this.males.hashCode()) * 31) + this.author.hashCode()) * 31) + this.theme.hashCode()) * 31) + this.cover.hashCode()) * 31;
        Integer num = this.status;
        int iHashCode3 = (((((((((iHashCode2 + (num == null ? 0 : num.hashCode())) * 31) + this.popular) * 31) + this.datetimeUpdated.hashCode()) * 31) + this.lastChapterId.hashCode()) * 31) + this.lastChapterName.hashCode()) * 31;
        Browse browse = this.browse;
        return iHashCode3 + (browse != null ? browse.hashCode() : 0);
    }

    public String toString() {
        return "CollectComic(uuid=" + this.uuid + ", bDisplay=" + this.bDisplay + ", name=" + this.name + ", pathWord=" + this.pathWord + ", females=" + this.females + ", males=" + this.males + ", author=" + this.author + ", theme=" + this.theme + ", cover=" + this.cover + ", status=" + this.status + ", popular=" + this.popular + ", datetimeUpdated=" + this.datetimeUpdated + ", lastChapterId=" + this.lastChapterId + ", lastChapterName=" + this.lastChapterName + ", browse=" + this.browse + ')';
    }

    /* JADX INFO: compiled from: CollectResult.kt */
    @Metadata(d1 = {"\u0000\u0016\n\u0002\u0018\u0002\n\u0002\u0010\u0000\n\u0002\b\u0002\n\u0002\u0018\u0002\n\u0002\u0018\u0002\n\u0000\b\u0086\u0003\u0018\u00002\u00020\u0001B\u0007\b\u0002¢\u0006\u0002\u0010\u0002J\u000f\u0010\u0003\u001a\b\u0012\u0004\u0012\u00020\u00050\u0004HÆ\u0001¨\u0006\u0006"}, d2 = {"Leu/kanade/tachiyomi/extension/zh/copymanga/api/dto/CollectComic$Companion;", "", "()V", "serializer", "Lkotlinx/serialization/KSerializer;", "Leu/kanade/tachiyomi/extension/zh/copymanga/api/dto/CollectComic;", "tachiyomi-zh.copymanga-v1.4.82_release"}, k = 1, mv = {1, 7, 1}, xi = 48)
    public static final class Companion {
        public /* synthetic */ Companion(DefaultConstructorMarker defaultConstructorMarker) {
            this();
        }

        private Companion() {
        }

        public final KSerializer<CollectComic> serializer() {
            return CollectComic$$serializer.INSTANCE;
        }
    }

    @Deprecated(level = DeprecationLevel.HIDDEN, message = "This synthesized declaration should not be used directly", replaceWith = @ReplaceWith(expression = "", imports = {}))
    public /* synthetic */ CollectComic(int i, String str, @SerialName("b_display") boolean z, String str2, @SerialName("path_word") String str3, List list, List list2, List list3, List list4, String str4, Integer num, int i2, @SerialName("datetime_updated") String str5, @SerialName("last_chapter_id") String str6, @SerialName("last_chapter_name") String str7, Browse browse, SerializationConstructorMarker serializationConstructorMarker) {
        if (15695 != (i & 15695)) {
            PluginExceptionsKt.throwMissingFieldException(i, 15695, CollectComic$$serializer.INSTANCE.getDescriptor());
        }
        this.uuid = str;
        this.bDisplay = z;
        this.name = str2;
        this.pathWord = str3;
        this.females = (i & 16) == 0 ? CollectionsKt.emptyList() : list;
        this.males = (i & 32) == 0 ? CollectionsKt.emptyList() : list2;
        this.author = list3;
        this.theme = (i & 128) == 0 ? CollectionsKt.emptyList() : list4;
        this.cover = str4;
        if ((i & 512) == 0) {
            this.status = null;
        } else {
            this.status = num;
        }
        this.popular = i2;
        this.datetimeUpdated = str5;
        this.lastChapterId = str6;
        this.lastChapterName = str7;
        if ((i & 16384) == 0) {
            this.browse = null;
        } else {
            this.browse = browse;
        }
    }

    public CollectComic(String str, boolean z, String str2, String str3, List<? extends JsonElement> list, List<? extends JsonElement> list2, List<AuthorInfo> list3, List<ThemeInfo> list4, String str4, Integer num, int i, String str5, String str6, String str7, Browse browse) {
        Intrinsics.checkNotNullParameter(str, "uuid");
        Intrinsics.checkNotNullParameter(str2, "name");
        Intrinsics.checkNotNullParameter(str3, "pathWord");
        Intrinsics.checkNotNullParameter(list, "females");
        Intrinsics.checkNotNullParameter(list2, "males");
        Intrinsics.checkNotNullParameter(list3, "author");
        Intrinsics.checkNotNullParameter(list4, "theme");
        Intrinsics.checkNotNullParameter(str4, "cover");
        Intrinsics.checkNotNullParameter(str5, "datetimeUpdated");
        Intrinsics.checkNotNullParameter(str6, "lastChapterId");
        Intrinsics.checkNotNullParameter(str7, "lastChapterName");
        this.uuid = str;
        this.bDisplay = z;
        this.name = str2;
        this.pathWord = str3;
        this.females = list;
        this.males = list2;
        this.author = list3;
        this.theme = list4;
        this.cover = str4;
        this.status = num;
        this.popular = i;
        this.datetimeUpdated = str5;
        this.lastChapterId = str6;
        this.lastChapterName = str7;
        this.browse = browse;
    }

    @JvmStatic
    public static final void write$Self(CollectComic self, CompositeEncoder output, SerialDescriptor serialDesc) {
        Intrinsics.checkNotNullParameter(self, "self");
        Intrinsics.checkNotNullParameter(output, "output");
        Intrinsics.checkNotNullParameter(serialDesc, "serialDesc");
        output.encodeStringElement(serialDesc, 0, self.uuid);
        output.encodeBooleanElement(serialDesc, 1, self.bDisplay);
        output.encodeStringElement(serialDesc, 2, self.name);
        output.encodeStringElement(serialDesc, 3, self.pathWord);
        if (output.shouldEncodeElementDefault(serialDesc, 4) || !Intrinsics.areEqual(self.females, CollectionsKt.emptyList())) {
            output.encodeSerializableElement(serialDesc, 4, new ArrayListSerializer(new ContextualSerializer(Reflection.getOrCreateKotlinClass(JsonElement.class), JsonElementSerializer.INSTANCE, new KSerializer[0])), self.females);
        }
        if (output.shouldEncodeElementDefault(serialDesc, 5) || !Intrinsics.areEqual(self.males, CollectionsKt.emptyList())) {
            output.encodeSerializableElement(serialDesc, 5, new ArrayListSerializer(new ContextualSerializer(Reflection.getOrCreateKotlinClass(JsonElement.class), JsonElementSerializer.INSTANCE, new KSerializer[0])), self.males);
        }
        output.encodeSerializableElement(serialDesc, 6, new ArrayListSerializer(AuthorInfo$$serializer.INSTANCE), self.author);
        if (output.shouldEncodeElementDefault(serialDesc, 7) || !Intrinsics.areEqual(self.theme, CollectionsKt.emptyList())) {
            output.encodeSerializableElement(serialDesc, 7, new ArrayListSerializer(new ContextualSerializer(Reflection.getOrCreateKotlinClass(ThemeInfo.class), ThemeInfo$$serializer.INSTANCE, new KSerializer[0])), self.theme);
        }
        output.encodeStringElement(serialDesc, 8, self.cover);
        if (output.shouldEncodeElementDefault(serialDesc, 9) || self.status != null) {
            output.encodeNullableSerializableElement(serialDesc, 9, IntSerializer.INSTANCE, self.status);
        }
        output.encodeIntElement(serialDesc, 10, self.popular);
        output.encodeStringElement(serialDesc, 11, self.datetimeUpdated);
        output.encodeStringElement(serialDesc, 12, self.lastChapterId);
        output.encodeStringElement(serialDesc, 13, self.lastChapterName);
        if (!output.shouldEncodeElementDefault(serialDesc, 14) && self.browse == null) {
            return;
        }
        output.encodeNullableSerializableElement(serialDesc, 14, Browse$$serializer.INSTANCE, self.browse);
    }

    public final String getUuid() {
        return this.uuid;
    }

    public final boolean getBDisplay() {
        return this.bDisplay;
    }

    public final String getName() {
        return this.name;
    }

    public final String getPathWord() {
        return this.pathWord;
    }

    public /* synthetic */ CollectComic(String str, boolean z, String str2, String str3, List list, List list2, List list3, List list4, String str4, Integer num, int i, String str5, String str6, String str7, Browse browse, int i2, DefaultConstructorMarker defaultConstructorMarker) {
        this(str, z, str2, str3, (i2 & 16) != 0 ? CollectionsKt.emptyList() : list, (i2 & 32) != 0 ? CollectionsKt.emptyList() : list2, list3, (i2 & 128) != 0 ? CollectionsKt.emptyList() : list4, str4, (i2 & 512) != 0 ? null : num, i, str5, str6, str7, (i2 & 16384) != 0 ? null : browse);
    }

    public final List<JsonElement> getFemales() {
        return this.females;
    }

    public final List<JsonElement> getMales() {
        return this.males;
    }

    public final List<AuthorInfo> getAuthor() {
        return this.author;
    }

    public final List<ThemeInfo> getTheme() {
        return this.theme;
    }

    public final String getCover() {
        return this.cover;
    }

    public final Integer getStatus() {
        return this.status;
    }

    public final int getPopular() {
        return this.popular;
    }

    public final String getDatetimeUpdated() {
        return this.datetimeUpdated;
    }

    public final String getLastChapterId() {
        return this.lastChapterId;
    }

    public final String getLastChapterName() {
        return this.lastChapterName;
    }

    public final Browse getBrowse() {
        return this.browse;
    }

    public final SManga toSManga(final CCOption language) {
        Intrinsics.checkNotNullParameter(language, "language");
        SManga sMangaCreate = SManga.Companion.create();
        sMangaCreate.setUrl("/comic/" + this.pathWord);
        sMangaCreate.setTitle(TranslateKt.translate(this.name, language));
        sMangaCreate.setAuthor(CollectionsKt.joinToString$default(this.author, (CharSequence) null, (CharSequence) null, (CharSequence) null, 0, (CharSequence) null, new Function1<AuthorInfo, CharSequence>() { // from class: eu.kanade.tachiyomi.extension.zh.copymanga.api.dto.CollectComic$toSManga$1$1
            {
                super(1);
            }

            public final CharSequence invoke(AuthorInfo authorInfo) {
                Intrinsics.checkNotNullParameter(authorInfo, "it");
                return TranslateKt.translate(authorInfo.getName(), language);
            }
        }, 31, (Object) null));
        sMangaCreate.setDescription("");
        sMangaCreate.setGenre("");
        sMangaCreate.setStatus(0);
        sMangaCreate.setThumbnail_url(this.cover);
        sMangaCreate.setInitialized(false);
        return sMangaCreate;
    }
}
