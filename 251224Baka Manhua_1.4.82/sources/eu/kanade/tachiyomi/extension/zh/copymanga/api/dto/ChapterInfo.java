package eu.kanade.tachiyomi.extension.zh.copymanga.api.dto;

import eu.kanade.tachiyomi.extension.zh.copymanga.CCOption;
import eu.kanade.tachiyomi.extension.zh.copymanga.language.TranslateKt;
import eu.kanade.tachiyomi.source.model.SChapter;
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

/* JADX INFO: compiled from: ChapterListResult.kt */
/* JADX INFO: loaded from: classes.dex */
@Metadata(d1 = {"\u0000N\n\u0002\u0018\u0002\n\u0002\u0010\u0000\n\u0000\n\u0002\u0010\b\n\u0002\b\u0002\n\u0002\u0010\u000e\n\u0002\b\u0006\n\u0002\u0018\u0002\n\u0002\b\u0019\n\u0002\u0010\u000b\n\u0002\b\u0003\n\u0002\u0018\u0002\n\u0000\n\u0002\u0018\u0002\n\u0002\b\u0004\n\u0002\u0010\u0002\n\u0002\b\u0002\n\u0002\u0018\u0002\n\u0000\n\u0002\u0018\u0002\n\u0002\b\u0003\b\u0087\b\u0018\u0000 92\u00020\u0001:\u000289Be\b\u0017\u0012\u0006\u0010\u0002\u001a\u00020\u0003\u0012\u0006\u0010\u0004\u001a\u00020\u0003\u0012\b\u0010\u0005\u001a\u0004\u0018\u00010\u0006\u0012\b\u0010\u0007\u001a\u0004\u0018\u00010\u0006\u0012\n\b\u0001\u0010\b\u001a\u0004\u0018\u00010\u0006\u0012\n\b\u0001\u0010\t\u001a\u0004\u0018\u00010\u0006\u0012\n\b\u0001\u0010\n\u001a\u0004\u0018\u00010\u0006\u0012\n\b\u0001\u0010\u000b\u001a\u0004\u0018\u00010\u0006\u0012\b\u0010\f\u001a\u0004\u0018\u00010\r¢\u0006\u0002\u0010\u000eBI\u0012\b\b\u0002\u0010\u0004\u001a\u00020\u0003\u0012\b\b\u0002\u0010\u0005\u001a\u00020\u0006\u0012\b\b\u0002\u0010\u0007\u001a\u00020\u0006\u0012\u0006\u0010\b\u001a\u00020\u0006\u0012\b\b\u0002\u0010\t\u001a\u00020\u0006\u0012\b\b\u0002\u0010\n\u001a\u00020\u0006\u0012\b\b\u0002\u0010\u000b\u001a\u00020\u0006¢\u0006\u0002\u0010\u000fJ\t\u0010\u001e\u001a\u00020\u0003HÆ\u0003J\t\u0010\u001f\u001a\u00020\u0006HÆ\u0003J\t\u0010 \u001a\u00020\u0006HÆ\u0003J\t\u0010!\u001a\u00020\u0006HÆ\u0003J\t\u0010\"\u001a\u00020\u0006HÆ\u0003J\t\u0010#\u001a\u00020\u0006HÆ\u0003J\t\u0010$\u001a\u00020\u0006HÆ\u0003JO\u0010%\u001a\u00020\u00002\b\b\u0002\u0010\u0004\u001a\u00020\u00032\b\b\u0002\u0010\u0005\u001a\u00020\u00062\b\b\u0002\u0010\u0007\u001a\u00020\u00062\b\b\u0002\u0010\b\u001a\u00020\u00062\b\b\u0002\u0010\t\u001a\u00020\u00062\b\b\u0002\u0010\n\u001a\u00020\u00062\b\b\u0002\u0010\u000b\u001a\u00020\u0006HÆ\u0001J\u0013\u0010&\u001a\u00020'2\b\u0010(\u001a\u0004\u0018\u00010\u0001HÖ\u0003J\t\u0010)\u001a\u00020\u0003HÖ\u0001J \u0010*\u001a\u00020+2\u0006\u0010\u0004\u001a\u00020\u00032\u0006\u0010,\u001a\u00020-2\b\u0010.\u001a\u0004\u0018\u00010\u0006J\u000e\u0010/\u001a\u00020+2\u0006\u0010,\u001a\u00020-J\t\u00100\u001a\u00020\u0006HÖ\u0001J!\u00101\u001a\u0002022\u0006\u00103\u001a\u00020\u00002\u0006\u00104\u001a\u0002052\u0006\u00106\u001a\u000207HÇ\u0001R\u001c\u0010\b\u001a\u00020\u00068\u0006X\u0087\u0004¢\u0006\u000e\n\u0000\u0012\u0004\b\u0010\u0010\u0011\u001a\u0004\b\u0012\u0010\u0013R\u001c\u0010\t\u001a\u00020\u00068\u0006X\u0087\u0004¢\u0006\u000e\n\u0000\u0012\u0004\b\u0014\u0010\u0011\u001a\u0004\b\u0015\u0010\u0013R\u001c\u0010\u000b\u001a\u00020\u00068\u0006X\u0087\u0004¢\u0006\u000e\n\u0000\u0012\u0004\b\u0016\u0010\u0011\u001a\u0004\b\u0017\u0010\u0013R\u001c\u0010\n\u001a\u00020\u00068\u0006X\u0087\u0004¢\u0006\u000e\n\u0000\u0012\u0004\b\u0018\u0010\u0011\u001a\u0004\b\u0019\u0010\u0013R\u0011\u0010\u0004\u001a\u00020\u0003¢\u0006\b\n\u0000\u001a\u0004\b\u001a\u0010\u001bR\u0011\u0010\u0007\u001a\u00020\u0006¢\u0006\b\n\u0000\u001a\u0004\b\u001c\u0010\u0013R\u0011\u0010\u0005\u001a\u00020\u0006¢\u0006\b\n\u0000\u001a\u0004\b\u001d\u0010\u0013¨\u0006:"}, d2 = {"Leu/kanade/tachiyomi/extension/zh/copymanga/api/dto/ChapterInfo;", "", "seen1", "", "index", "uuid", "", "name", "comicId", "comicPathWord", "groupPathWord", "datetimeCreated", "serializationConstructorMarker", "Lkotlinx/serialization/internal/SerializationConstructorMarker;", "(IILjava/lang/String;Ljava/lang/String;Ljava/lang/String;Ljava/lang/String;Ljava/lang/String;Ljava/lang/String;Lkotlinx/serialization/internal/SerializationConstructorMarker;)V", "(ILjava/lang/String;Ljava/lang/String;Ljava/lang/String;Ljava/lang/String;Ljava/lang/String;Ljava/lang/String;)V", "getComicId$annotations", "()V", "getComicId", "()Ljava/lang/String;", "getComicPathWord$annotations", "getComicPathWord", "getDatetimeCreated$annotations", "getDatetimeCreated", "getGroupPathWord$annotations", "getGroupPathWord", "getIndex", "()I", "getName", "getUuid", "component1", "component2", "component3", "component4", "component5", "component6", "component7", "copy", "equals", "", "other", "hashCode", "toSChapter", "Leu/kanade/tachiyomi/source/model/SChapter;", "language", "Leu/kanade/tachiyomi/extension/zh/copymanga/CCOption;", "group", "toSMangaCommentChapter", "toString", "write$Self", "", "self", "output", "Lkotlinx/serialization/encoding/CompositeEncoder;", "serialDesc", "Lkotlinx/serialization/descriptors/SerialDescriptor;", "$serializer", "Companion", "tachiyomi-zh.copymanga-v1.4.82_release"}, k = 1, mv = {1, 7, 1}, xi = 48)
@Serializable
public final /* data */ class ChapterInfo {

    /* JADX INFO: renamed from: Companion, reason: from kotlin metadata */
    public static final Companion INSTANCE = new Companion(null);
    private final String comicId;
    private final String comicPathWord;
    private final String datetimeCreated;
    private final String groupPathWord;
    private final int index;
    private final String name;
    private final String uuid;

    public static /* synthetic */ ChapterInfo copy$default(ChapterInfo chapterInfo, int i, String str, String str2, String str3, String str4, String str5, String str6, int i2, Object obj) {
        if ((i2 & 1) != 0) {
            i = chapterInfo.index;
        }
        if ((i2 & 2) != 0) {
            str = chapterInfo.uuid;
        }
        String str7 = str;
        if ((i2 & 4) != 0) {
            str2 = chapterInfo.name;
        }
        String str8 = str2;
        if ((i2 & 8) != 0) {
            str3 = chapterInfo.comicId;
        }
        String str9 = str3;
        if ((i2 & 16) != 0) {
            str4 = chapterInfo.comicPathWord;
        }
        String str10 = str4;
        if ((i2 & 32) != 0) {
            str5 = chapterInfo.groupPathWord;
        }
        String str11 = str5;
        if ((i2 & 64) != 0) {
            str6 = chapterInfo.datetimeCreated;
        }
        return chapterInfo.copy(i, str7, str8, str9, str10, str11, str6);
    }

    @SerialName("comic_id")
    public static /* synthetic */ void getComicId$annotations() {
    }

    @SerialName("comic_path_word")
    public static /* synthetic */ void getComicPathWord$annotations() {
    }

    @SerialName("datetime_created")
    public static /* synthetic */ void getDatetimeCreated$annotations() {
    }

    @SerialName("group_path_word")
    public static /* synthetic */ void getGroupPathWord$annotations() {
    }

    /* JADX INFO: renamed from: component1, reason: from getter */
    public final int getIndex() {
        return this.index;
    }

    /* JADX INFO: renamed from: component2, reason: from getter */
    public final String getUuid() {
        return this.uuid;
    }

    /* JADX INFO: renamed from: component3, reason: from getter */
    public final String getName() {
        return this.name;
    }

    /* JADX INFO: renamed from: component4, reason: from getter */
    public final String getComicId() {
        return this.comicId;
    }

    /* JADX INFO: renamed from: component5, reason: from getter */
    public final String getComicPathWord() {
        return this.comicPathWord;
    }

    /* JADX INFO: renamed from: component6, reason: from getter */
    public final String getGroupPathWord() {
        return this.groupPathWord;
    }

    /* JADX INFO: renamed from: component7, reason: from getter */
    public final String getDatetimeCreated() {
        return this.datetimeCreated;
    }

    public final ChapterInfo copy(int index, String uuid, String name, String comicId, String comicPathWord, String groupPathWord, String datetimeCreated) {
        Intrinsics.checkNotNullParameter(uuid, "uuid");
        Intrinsics.checkNotNullParameter(name, "name");
        Intrinsics.checkNotNullParameter(comicId, "comicId");
        Intrinsics.checkNotNullParameter(comicPathWord, "comicPathWord");
        Intrinsics.checkNotNullParameter(groupPathWord, "groupPathWord");
        Intrinsics.checkNotNullParameter(datetimeCreated, "datetimeCreated");
        return new ChapterInfo(index, uuid, name, comicId, comicPathWord, groupPathWord, datetimeCreated);
    }

    public boolean equals(Object other) {
        if (this == other) {
            return true;
        }
        if (!(other instanceof ChapterInfo)) {
            return false;
        }
        ChapterInfo chapterInfo = (ChapterInfo) other;
        return this.index == chapterInfo.index && Intrinsics.areEqual(this.uuid, chapterInfo.uuid) && Intrinsics.areEqual(this.name, chapterInfo.name) && Intrinsics.areEqual(this.comicId, chapterInfo.comicId) && Intrinsics.areEqual(this.comicPathWord, chapterInfo.comicPathWord) && Intrinsics.areEqual(this.groupPathWord, chapterInfo.groupPathWord) && Intrinsics.areEqual(this.datetimeCreated, chapterInfo.datetimeCreated);
    }

    public int hashCode() {
        return (((((((((((this.index * 31) + this.uuid.hashCode()) * 31) + this.name.hashCode()) * 31) + this.comicId.hashCode()) * 31) + this.comicPathWord.hashCode()) * 31) + this.groupPathWord.hashCode()) * 31) + this.datetimeCreated.hashCode();
    }

    public String toString() {
        return "ChapterInfo(index=" + this.index + ", uuid=" + this.uuid + ", name=" + this.name + ", comicId=" + this.comicId + ", comicPathWord=" + this.comicPathWord + ", groupPathWord=" + this.groupPathWord + ", datetimeCreated=" + this.datetimeCreated + ')';
    }

    /* JADX INFO: compiled from: ChapterListResult.kt */
    @Metadata(d1 = {"\u0000\u0016\n\u0002\u0018\u0002\n\u0002\u0010\u0000\n\u0002\b\u0002\n\u0002\u0018\u0002\n\u0002\u0018\u0002\n\u0000\b\u0086\u0003\u0018\u00002\u00020\u0001B\u0007\b\u0002¢\u0006\u0002\u0010\u0002J\u000f\u0010\u0003\u001a\b\u0012\u0004\u0012\u00020\u00050\u0004HÆ\u0001¨\u0006\u0006"}, d2 = {"Leu/kanade/tachiyomi/extension/zh/copymanga/api/dto/ChapterInfo$Companion;", "", "()V", "serializer", "Lkotlinx/serialization/KSerializer;", "Leu/kanade/tachiyomi/extension/zh/copymanga/api/dto/ChapterInfo;", "tachiyomi-zh.copymanga-v1.4.82_release"}, k = 1, mv = {1, 7, 1}, xi = 48)
    public static final class Companion {
        public /* synthetic */ Companion(DefaultConstructorMarker defaultConstructorMarker) {
            this();
        }

        private Companion() {
        }

        public final KSerializer<ChapterInfo> serializer() {
            return ChapterInfo$$serializer.INSTANCE;
        }
    }

    @Deprecated(level = DeprecationLevel.HIDDEN, message = "This synthesized declaration should not be used directly", replaceWith = @ReplaceWith(expression = "", imports = {}))
    public /* synthetic */ ChapterInfo(int i, int i2, String str, String str2, @SerialName("comic_id") String str3, @SerialName("comic_path_word") String str4, @SerialName("group_path_word") String str5, @SerialName("datetime_created") String str6, SerializationConstructorMarker serializationConstructorMarker) {
        if (8 != (i & 8)) {
            PluginExceptionsKt.throwMissingFieldException(i, 8, ChapterInfo$$serializer.INSTANCE.getDescriptor());
        }
        this.index = (i & 1) == 0 ? 0 : i2;
        if ((i & 2) == 0) {
            this.uuid = "";
        } else {
            this.uuid = str;
        }
        if ((i & 4) == 0) {
            this.name = "";
        } else {
            this.name = str2;
        }
        this.comicId = str3;
        if ((i & 16) == 0) {
            this.comicPathWord = "";
        } else {
            this.comicPathWord = str4;
        }
        if ((i & 32) == 0) {
            this.groupPathWord = "";
        } else {
            this.groupPathWord = str5;
        }
        if ((i & 64) == 0) {
            this.datetimeCreated = "";
        } else {
            this.datetimeCreated = str6;
        }
    }

    public ChapterInfo(int i, String str, String str2, String str3, String str4, String str5, String str6) {
        Intrinsics.checkNotNullParameter(str, "uuid");
        Intrinsics.checkNotNullParameter(str2, "name");
        Intrinsics.checkNotNullParameter(str3, "comicId");
        Intrinsics.checkNotNullParameter(str4, "comicPathWord");
        Intrinsics.checkNotNullParameter(str5, "groupPathWord");
        Intrinsics.checkNotNullParameter(str6, "datetimeCreated");
        this.index = i;
        this.uuid = str;
        this.name = str2;
        this.comicId = str3;
        this.comicPathWord = str4;
        this.groupPathWord = str5;
        this.datetimeCreated = str6;
    }

    @JvmStatic
    public static final void write$Self(ChapterInfo self, CompositeEncoder output, SerialDescriptor serialDesc) {
        Intrinsics.checkNotNullParameter(self, "self");
        Intrinsics.checkNotNullParameter(output, "output");
        Intrinsics.checkNotNullParameter(serialDesc, "serialDesc");
        if (output.shouldEncodeElementDefault(serialDesc, 0) || self.index != 0) {
            output.encodeIntElement(serialDesc, 0, self.index);
        }
        if (output.shouldEncodeElementDefault(serialDesc, 1) || !Intrinsics.areEqual(self.uuid, "")) {
            output.encodeStringElement(serialDesc, 1, self.uuid);
        }
        if (output.shouldEncodeElementDefault(serialDesc, 2) || !Intrinsics.areEqual(self.name, "")) {
            output.encodeStringElement(serialDesc, 2, self.name);
        }
        output.encodeStringElement(serialDesc, 3, self.comicId);
        if (output.shouldEncodeElementDefault(serialDesc, 4) || !Intrinsics.areEqual(self.comicPathWord, "")) {
            output.encodeStringElement(serialDesc, 4, self.comicPathWord);
        }
        if (output.shouldEncodeElementDefault(serialDesc, 5) || !Intrinsics.areEqual(self.groupPathWord, "")) {
            output.encodeStringElement(serialDesc, 5, self.groupPathWord);
        }
        if (!output.shouldEncodeElementDefault(serialDesc, 6) && Intrinsics.areEqual(self.datetimeCreated, "")) {
            return;
        }
        output.encodeStringElement(serialDesc, 6, self.datetimeCreated);
    }

    public /* synthetic */ ChapterInfo(int i, String str, String str2, String str3, String str4, String str5, String str6, int i2, DefaultConstructorMarker defaultConstructorMarker) {
        this((i2 & 1) != 0 ? 0 : i, (i2 & 2) != 0 ? "" : str, (i2 & 4) != 0 ? "" : str2, str3, (i2 & 16) != 0 ? "" : str4, (i2 & 32) != 0 ? "" : str5, (i2 & 64) != 0 ? "" : str6);
    }

    public final int getIndex() {
        return this.index;
    }

    public final String getUuid() {
        return this.uuid;
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

    public final String getGroupPathWord() {
        return this.groupPathWord;
    }

    public final String getDatetimeCreated() {
        return this.datetimeCreated;
    }

    public final SChapter toSChapter(int index, CCOption language, String group) {
        String str;
        Intrinsics.checkNotNullParameter(language, "language");
        SChapter sChapterCreate = SChapter.Companion.create();
        String str2 = group;
        if (str2 == null || str2.length() == 0 || Intrinsics.areEqual(this.groupPathWord, "default")) {
            str = "";
        } else {
            str = group + (char) 65306;
        }
        sChapterCreate.setUrl(this.comicPathWord + "/chapter/" + this.uuid);
        StringBuilder sb = new StringBuilder();
        sb.append(str);
        sb.append(this.name);
        sChapterCreate.setName(TranslateKt.translate(sb.toString(), language));
        sChapterCreate.setDate_upload(ChapterListResultKt.parseDate(this.datetimeCreated) + ((long) index));
        sChapterCreate.setScanlator((String) null);
        return sChapterCreate;
    }

    public final SChapter toSMangaCommentChapter(CCOption language) {
        Intrinsics.checkNotNullParameter(language, "language");
        SChapter sChapterCreate = SChapter.Companion.create();
        sChapterCreate.setUrl("commentList?comicId=" + this.comicId);
        sChapterCreate.setName(TranslateKt.translate("漫畫評論", language));
        sChapterCreate.setDate_upload(System.currentTimeMillis());
        sChapterCreate.setScanlator((String) null);
        return sChapterCreate;
    }
}
