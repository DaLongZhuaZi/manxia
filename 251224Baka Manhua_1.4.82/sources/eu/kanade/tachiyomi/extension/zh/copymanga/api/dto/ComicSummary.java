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
import kotlinx.serialization.internal.PluginExceptionsKt;
import kotlinx.serialization.internal.SerializationConstructorMarker;
import kotlinx.serialization.internal.StringSerializer;
import kotlinx.serialization.json.JsonElement;
import kotlinx.serialization.json.JsonElementSerializer;

/* JADX INFO: compiled from: ComicsListResult.kt */
/* JADX INFO: loaded from: classes.dex */
@Metadata(d1 = {"\u0000p\n\u0002\u0018\u0002\n\u0002\u0010\u0000\n\u0000\n\u0002\u0010\b\n\u0000\n\u0002\u0010\u000e\n\u0002\b\u0002\n\u0002\u0018\u0002\n\u0000\n\u0002\u0010 \n\u0002\u0018\u0002\n\u0002\u0018\u0002\n\u0002\b\u0002\n\u0002\u0018\u0002\n\u0000\n\u0002\u0018\u0002\n\u0002\b\u0004\n\u0002\u0018\u0002\n\u0002\b \n\u0002\u0010\u000b\n\u0002\b\u0003\n\u0002\u0018\u0002\n\u0000\n\u0002\u0018\u0002\n\u0002\b\u0002\n\u0002\u0010\u0002\n\u0002\b\u0002\n\u0002\u0018\u0002\n\u0000\n\u0002\u0018\u0002\n\u0002\b\u0003\b\u0087\b\u0018\u0000 G2\u00020\u0001:\u0002FGB£\u0001\b\u0017\u0012\u0006\u0010\u0002\u001a\u00020\u0003\u0012\b\u0010\u0004\u001a\u0004\u0018\u00010\u0005\u0012\n\b\u0001\u0010\u0006\u001a\u0004\u0018\u00010\u0005\u0012\n\b\u0001\u0010\u0007\u001a\u0004\u0018\u00010\b\u0012\u0013\u0010\t\u001a\u000f\u0012\t\u0012\u00070\u000b¢\u0006\u0002\b\f\u0018\u00010\n\u0012\u0013\u0010\r\u001a\u000f\u0012\t\u0012\u00070\u000b¢\u0006\u0002\b\f\u0018\u00010\n\u0012\u000e\u0010\u000e\u001a\n\u0012\u0004\u0012\u00020\u000f\u0018\u00010\n\u0012\u000e\u0010\u0010\u001a\n\u0012\u0004\u0012\u00020\u0011\u0018\u00010\n\u0012\b\u0010\u0012\u001a\u0004\u0018\u00010\u0005\u0012\u0006\u0010\u0013\u001a\u00020\u0003\u0012\n\b\u0001\u0010\u0014\u001a\u0004\u0018\u00010\u0005\u0012\b\u0010\u0015\u001a\u0004\u0018\u00010\u0016¢\u0006\u0002\u0010\u0017B\u0085\u0001\u0012\u0006\u0010\u0004\u001a\u00020\u0005\u0012\u0006\u0010\u0006\u001a\u00020\u0005\u0012\n\b\u0002\u0010\u0007\u001a\u0004\u0018\u00010\b\u0012\u0013\b\u0002\u0010\t\u001a\r\u0012\t\u0012\u00070\u000b¢\u0006\u0002\b\f0\n\u0012\u0013\b\u0002\u0010\r\u001a\r\u0012\t\u0012\u00070\u000b¢\u0006\u0002\b\f0\n\u0012\f\u0010\u000e\u001a\b\u0012\u0004\u0012\u00020\u000f0\n\u0012\u000e\b\u0002\u0010\u0010\u001a\b\u0012\u0004\u0012\u00020\u00110\n\u0012\u0006\u0010\u0012\u001a\u00020\u0005\u0012\u0006\u0010\u0013\u001a\u00020\u0003\u0012\n\b\u0002\u0010\u0014\u001a\u0004\u0018\u00010\u0005¢\u0006\u0002\u0010\u0018J\t\u0010+\u001a\u00020\u0005HÆ\u0003J\u000b\u0010,\u001a\u0004\u0018\u00010\u0005HÆ\u0003J\t\u0010-\u001a\u00020\u0005HÆ\u0003J\u000b\u0010.\u001a\u0004\u0018\u00010\bHÆ\u0003J\u0014\u0010/\u001a\r\u0012\t\u0012\u00070\u000b¢\u0006\u0002\b\f0\nHÆ\u0003J\u0014\u00100\u001a\r\u0012\t\u0012\u00070\u000b¢\u0006\u0002\b\f0\nHÆ\u0003J\u000f\u00101\u001a\b\u0012\u0004\u0012\u00020\u000f0\nHÆ\u0003J\u000f\u00102\u001a\b\u0012\u0004\u0012\u00020\u00110\nHÆ\u0003J\t\u00103\u001a\u00020\u0005HÆ\u0003J\t\u00104\u001a\u00020\u0003HÆ\u0003J\u0093\u0001\u00105\u001a\u00020\u00002\b\b\u0002\u0010\u0004\u001a\u00020\u00052\b\b\u0002\u0010\u0006\u001a\u00020\u00052\n\b\u0002\u0010\u0007\u001a\u0004\u0018\u00010\b2\u0013\b\u0002\u0010\t\u001a\r\u0012\t\u0012\u00070\u000b¢\u0006\u0002\b\f0\n2\u0013\b\u0002\u0010\r\u001a\r\u0012\t\u0012\u00070\u000b¢\u0006\u0002\b\f0\n2\u000e\b\u0002\u0010\u000e\u001a\b\u0012\u0004\u0012\u00020\u000f0\n2\u000e\b\u0002\u0010\u0010\u001a\b\u0012\u0004\u0012\u00020\u00110\n2\b\b\u0002\u0010\u0012\u001a\u00020\u00052\b\b\u0002\u0010\u0013\u001a\u00020\u00032\n\b\u0002\u0010\u0014\u001a\u0004\u0018\u00010\u0005HÆ\u0001J\u0013\u00106\u001a\u0002072\b\u00108\u001a\u0004\u0018\u00010\u0001HÖ\u0003J\t\u00109\u001a\u00020\u0003HÖ\u0001J\u000e\u0010:\u001a\u00020;2\u0006\u0010<\u001a\u00020=J\t\u0010>\u001a\u00020\u0005HÖ\u0001J!\u0010?\u001a\u00020@2\u0006\u0010A\u001a\u00020\u00002\u0006\u0010B\u001a\u00020C2\u0006\u0010D\u001a\u00020EHÇ\u0001R\u0017\u0010\u000e\u001a\b\u0012\u0004\u0012\u00020\u000f0\n¢\u0006\b\n\u0000\u001a\u0004\b\u0019\u0010\u001aR\u0011\u0010\u0012\u001a\u00020\u0005¢\u0006\b\n\u0000\u001a\u0004\b\u001b\u0010\u001cR\u001e\u0010\u0014\u001a\u0004\u0018\u00010\u00058\u0006X\u0087\u0004¢\u0006\u000e\n\u0000\u0012\u0004\b\u001d\u0010\u001e\u001a\u0004\b\u001f\u0010\u001cR\u001c\u0010\t\u001a\r\u0012\t\u0012\u00070\u000b¢\u0006\u0002\b\f0\n¢\u0006\b\n\u0000\u001a\u0004\b \u0010\u001aR\u001e\u0010\u0007\u001a\u0004\u0018\u00010\b8\u0006X\u0087\u0004¢\u0006\u000e\n\u0000\u0012\u0004\b!\u0010\u001e\u001a\u0004\b\"\u0010#R\u001c\u0010\r\u001a\r\u0012\t\u0012\u00070\u000b¢\u0006\u0002\b\f0\n¢\u0006\b\n\u0000\u001a\u0004\b$\u0010\u001aR\u0011\u0010\u0004\u001a\u00020\u0005¢\u0006\b\n\u0000\u001a\u0004\b%\u0010\u001cR\u001c\u0010\u0006\u001a\u00020\u00058\u0006X\u0087\u0004¢\u0006\u000e\n\u0000\u0012\u0004\b&\u0010\u001e\u001a\u0004\b'\u0010\u001cR\u0011\u0010\u0013\u001a\u00020\u0003¢\u0006\b\n\u0000\u001a\u0004\b(\u0010)R\u0017\u0010\u0010\u001a\b\u0012\u0004\u0012\u00020\u00110\n¢\u0006\b\n\u0000\u001a\u0004\b*\u0010\u001a¨\u0006H"}, d2 = {"Leu/kanade/tachiyomi/extension/zh/copymanga/api/dto/ComicSummary;", "", "seen1", "", "name", "", "pathWord", "freeType", "Leu/kanade/tachiyomi/extension/zh/copymanga/api/dto/FreeType;", "females", "", "Lkotlinx/serialization/json/JsonElement;", "Lkotlinx/serialization/Contextual;", "males", "author", "Leu/kanade/tachiyomi/extension/zh/copymanga/api/dto/AuthorInfo;", "theme", "Leu/kanade/tachiyomi/extension/zh/copymanga/api/dto/ThemeInfo;", "cover", "popular", "datetimeUpdated", "serializationConstructorMarker", "Lkotlinx/serialization/internal/SerializationConstructorMarker;", "(ILjava/lang/String;Ljava/lang/String;Leu/kanade/tachiyomi/extension/zh/copymanga/api/dto/FreeType;Ljava/util/List;Ljava/util/List;Ljava/util/List;Ljava/util/List;Ljava/lang/String;ILjava/lang/String;Lkotlinx/serialization/internal/SerializationConstructorMarker;)V", "(Ljava/lang/String;Ljava/lang/String;Leu/kanade/tachiyomi/extension/zh/copymanga/api/dto/FreeType;Ljava/util/List;Ljava/util/List;Ljava/util/List;Ljava/util/List;Ljava/lang/String;ILjava/lang/String;)V", "getAuthor", "()Ljava/util/List;", "getCover", "()Ljava/lang/String;", "getDatetimeUpdated$annotations", "()V", "getDatetimeUpdated", "getFemales", "getFreeType$annotations", "getFreeType", "()Leu/kanade/tachiyomi/extension/zh/copymanga/api/dto/FreeType;", "getMales", "getName", "getPathWord$annotations", "getPathWord", "getPopular", "()I", "getTheme", "component1", "component10", "component2", "component3", "component4", "component5", "component6", "component7", "component8", "component9", "copy", "equals", "", "other", "hashCode", "toSManga", "Leu/kanade/tachiyomi/source/model/SManga;", "language", "Leu/kanade/tachiyomi/extension/zh/copymanga/CCOption;", "toString", "write$Self", "", "self", "output", "Lkotlinx/serialization/encoding/CompositeEncoder;", "serialDesc", "Lkotlinx/serialization/descriptors/SerialDescriptor;", "$serializer", "Companion", "tachiyomi-zh.copymanga-v1.4.82_release"}, k = 1, mv = {1, 7, 1}, xi = 48)
@Serializable
public final /* data */ class ComicSummary {

    /* JADX INFO: renamed from: Companion, reason: from kotlin metadata */
    public static final Companion INSTANCE = new Companion(null);
    private final List<AuthorInfo> author;
    private final String cover;
    private final String datetimeUpdated;
    private final List<JsonElement> females;
    private final FreeType freeType;
    private final List<JsonElement> males;
    private final String name;
    private final String pathWord;
    private final int popular;
    private final List<ThemeInfo> theme;

    @SerialName("datetime_updated")
    public static /* synthetic */ void getDatetimeUpdated$annotations() {
    }

    @SerialName("free_type")
    public static /* synthetic */ void getFreeType$annotations() {
    }

    @SerialName("path_word")
    public static /* synthetic */ void getPathWord$annotations() {
    }

    /* JADX INFO: renamed from: component1, reason: from getter */
    public final String getName() {
        return this.name;
    }

    /* JADX INFO: renamed from: component10, reason: from getter */
    public final String getDatetimeUpdated() {
        return this.datetimeUpdated;
    }

    /* JADX INFO: renamed from: component2, reason: from getter */
    public final String getPathWord() {
        return this.pathWord;
    }

    /* JADX INFO: renamed from: component3, reason: from getter */
    public final FreeType getFreeType() {
        return this.freeType;
    }

    public final List<JsonElement> component4() {
        return this.females;
    }

    public final List<JsonElement> component5() {
        return this.males;
    }

    public final List<AuthorInfo> component6() {
        return this.author;
    }

    public final List<ThemeInfo> component7() {
        return this.theme;
    }

    /* JADX INFO: renamed from: component8, reason: from getter */
    public final String getCover() {
        return this.cover;
    }

    /* JADX INFO: renamed from: component9, reason: from getter */
    public final int getPopular() {
        return this.popular;
    }

    public final ComicSummary copy(String name, String pathWord, FreeType freeType, List<? extends JsonElement> females, List<? extends JsonElement> males, List<AuthorInfo> author, List<ThemeInfo> theme, String cover, int popular, String datetimeUpdated) {
        Intrinsics.checkNotNullParameter(name, "name");
        Intrinsics.checkNotNullParameter(pathWord, "pathWord");
        Intrinsics.checkNotNullParameter(females, "females");
        Intrinsics.checkNotNullParameter(males, "males");
        Intrinsics.checkNotNullParameter(author, "author");
        Intrinsics.checkNotNullParameter(theme, "theme");
        Intrinsics.checkNotNullParameter(cover, "cover");
        return new ComicSummary(name, pathWord, freeType, females, males, author, theme, cover, popular, datetimeUpdated);
    }

    public boolean equals(Object other) {
        if (this == other) {
            return true;
        }
        if (!(other instanceof ComicSummary)) {
            return false;
        }
        ComicSummary comicSummary = (ComicSummary) other;
        return Intrinsics.areEqual(this.name, comicSummary.name) && Intrinsics.areEqual(this.pathWord, comicSummary.pathWord) && Intrinsics.areEqual(this.freeType, comicSummary.freeType) && Intrinsics.areEqual(this.females, comicSummary.females) && Intrinsics.areEqual(this.males, comicSummary.males) && Intrinsics.areEqual(this.author, comicSummary.author) && Intrinsics.areEqual(this.theme, comicSummary.theme) && Intrinsics.areEqual(this.cover, comicSummary.cover) && this.popular == comicSummary.popular && Intrinsics.areEqual(this.datetimeUpdated, comicSummary.datetimeUpdated);
    }

    public int hashCode() {
        int iHashCode = ((this.name.hashCode() * 31) + this.pathWord.hashCode()) * 31;
        FreeType freeType = this.freeType;
        int iHashCode2 = (((((((((((((iHashCode + (freeType == null ? 0 : freeType.hashCode())) * 31) + this.females.hashCode()) * 31) + this.males.hashCode()) * 31) + this.author.hashCode()) * 31) + this.theme.hashCode()) * 31) + this.cover.hashCode()) * 31) + this.popular) * 31;
        String str = this.datetimeUpdated;
        return iHashCode2 + (str != null ? str.hashCode() : 0);
    }

    public String toString() {
        return "ComicSummary(name=" + this.name + ", pathWord=" + this.pathWord + ", freeType=" + this.freeType + ", females=" + this.females + ", males=" + this.males + ", author=" + this.author + ", theme=" + this.theme + ", cover=" + this.cover + ", popular=" + this.popular + ", datetimeUpdated=" + this.datetimeUpdated + ')';
    }

    /* JADX INFO: compiled from: ComicsListResult.kt */
    @Metadata(d1 = {"\u0000\u0016\n\u0002\u0018\u0002\n\u0002\u0010\u0000\n\u0002\b\u0002\n\u0002\u0018\u0002\n\u0002\u0018\u0002\n\u0000\b\u0086\u0003\u0018\u00002\u00020\u0001B\u0007\b\u0002¢\u0006\u0002\u0010\u0002J\u000f\u0010\u0003\u001a\b\u0012\u0004\u0012\u00020\u00050\u0004HÆ\u0001¨\u0006\u0006"}, d2 = {"Leu/kanade/tachiyomi/extension/zh/copymanga/api/dto/ComicSummary$Companion;", "", "()V", "serializer", "Lkotlinx/serialization/KSerializer;", "Leu/kanade/tachiyomi/extension/zh/copymanga/api/dto/ComicSummary;", "tachiyomi-zh.copymanga-v1.4.82_release"}, k = 1, mv = {1, 7, 1}, xi = 48)
    public static final class Companion {
        public /* synthetic */ Companion(DefaultConstructorMarker defaultConstructorMarker) {
            this();
        }

        private Companion() {
        }

        public final KSerializer<ComicSummary> serializer() {
            return ComicSummary$$serializer.INSTANCE;
        }
    }

    @Deprecated(level = DeprecationLevel.HIDDEN, message = "This synthesized declaration should not be used directly", replaceWith = @ReplaceWith(expression = "", imports = {}))
    public /* synthetic */ ComicSummary(int i, String str, @SerialName("path_word") String str2, @SerialName("free_type") FreeType freeType, List list, List list2, List list3, List list4, String str3, int i2, @SerialName("datetime_updated") String str4, SerializationConstructorMarker serializationConstructorMarker) {
        if (419 != (i & 419)) {
            PluginExceptionsKt.throwMissingFieldException(i, 419, ComicSummary$$serializer.INSTANCE.getDescriptor());
        }
        this.name = str;
        this.pathWord = str2;
        if ((i & 4) == 0) {
            this.freeType = null;
        } else {
            this.freeType = freeType;
        }
        if ((i & 8) == 0) {
            this.females = CollectionsKt.emptyList();
        } else {
            this.females = list;
        }
        if ((i & 16) == 0) {
            this.males = CollectionsKt.emptyList();
        } else {
            this.males = list2;
        }
        this.author = list3;
        if ((i & 64) == 0) {
            this.theme = CollectionsKt.emptyList();
        } else {
            this.theme = list4;
        }
        this.cover = str3;
        this.popular = i2;
        if ((i & 512) == 0) {
            this.datetimeUpdated = null;
        } else {
            this.datetimeUpdated = str4;
        }
    }

    public ComicSummary(String str, String str2, FreeType freeType, List<? extends JsonElement> list, List<? extends JsonElement> list2, List<AuthorInfo> list3, List<ThemeInfo> list4, String str3, int i, String str4) {
        Intrinsics.checkNotNullParameter(str, "name");
        Intrinsics.checkNotNullParameter(str2, "pathWord");
        Intrinsics.checkNotNullParameter(list, "females");
        Intrinsics.checkNotNullParameter(list2, "males");
        Intrinsics.checkNotNullParameter(list3, "author");
        Intrinsics.checkNotNullParameter(list4, "theme");
        Intrinsics.checkNotNullParameter(str3, "cover");
        this.name = str;
        this.pathWord = str2;
        this.freeType = freeType;
        this.females = list;
        this.males = list2;
        this.author = list3;
        this.theme = list4;
        this.cover = str3;
        this.popular = i;
        this.datetimeUpdated = str4;
    }

    @JvmStatic
    public static final void write$Self(ComicSummary self, CompositeEncoder output, SerialDescriptor serialDesc) {
        Intrinsics.checkNotNullParameter(self, "self");
        Intrinsics.checkNotNullParameter(output, "output");
        Intrinsics.checkNotNullParameter(serialDesc, "serialDesc");
        output.encodeStringElement(serialDesc, 0, self.name);
        output.encodeStringElement(serialDesc, 1, self.pathWord);
        if (output.shouldEncodeElementDefault(serialDesc, 2) || self.freeType != null) {
            output.encodeNullableSerializableElement(serialDesc, 2, FreeType$$serializer.INSTANCE, self.freeType);
        }
        if (output.shouldEncodeElementDefault(serialDesc, 3) || !Intrinsics.areEqual(self.females, CollectionsKt.emptyList())) {
            output.encodeSerializableElement(serialDesc, 3, new ArrayListSerializer(new ContextualSerializer(Reflection.getOrCreateKotlinClass(JsonElement.class), JsonElementSerializer.INSTANCE, new KSerializer[0])), self.females);
        }
        if (output.shouldEncodeElementDefault(serialDesc, 4) || !Intrinsics.areEqual(self.males, CollectionsKt.emptyList())) {
            output.encodeSerializableElement(serialDesc, 4, new ArrayListSerializer(new ContextualSerializer(Reflection.getOrCreateKotlinClass(JsonElement.class), JsonElementSerializer.INSTANCE, new KSerializer[0])), self.males);
        }
        output.encodeSerializableElement(serialDesc, 5, new ArrayListSerializer(AuthorInfo$$serializer.INSTANCE), self.author);
        if (output.shouldEncodeElementDefault(serialDesc, 6) || !Intrinsics.areEqual(self.theme, CollectionsKt.emptyList())) {
            output.encodeSerializableElement(serialDesc, 6, new ArrayListSerializer(ThemeInfo$$serializer.INSTANCE), self.theme);
        }
        output.encodeStringElement(serialDesc, 7, self.cover);
        output.encodeIntElement(serialDesc, 8, self.popular);
        if (!output.shouldEncodeElementDefault(serialDesc, 9) && self.datetimeUpdated == null) {
            return;
        }
        output.encodeNullableSerializableElement(serialDesc, 9, StringSerializer.INSTANCE, self.datetimeUpdated);
    }

    public final String getName() {
        return this.name;
    }

    public final String getPathWord() {
        return this.pathWord;
    }

    public final FreeType getFreeType() {
        return this.freeType;
    }

    public /* synthetic */ ComicSummary(String str, String str2, FreeType freeType, List list, List list2, List list3, List list4, String str3, int i, String str4, int i2, DefaultConstructorMarker defaultConstructorMarker) {
        this(str, str2, (i2 & 4) != 0 ? null : freeType, (i2 & 8) != 0 ? CollectionsKt.emptyList() : list, (i2 & 16) != 0 ? CollectionsKt.emptyList() : list2, list3, (i2 & 64) != 0 ? CollectionsKt.emptyList() : list4, str3, i, (i2 & 512) != 0 ? null : str4);
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

    public final int getPopular() {
        return this.popular;
    }

    public final String getDatetimeUpdated() {
        return this.datetimeUpdated;
    }

    public final SManga toSManga(final CCOption language) {
        Intrinsics.checkNotNullParameter(language, "language");
        SManga sMangaCreate = SManga.Companion.create();
        sMangaCreate.setUrl("/comic/" + this.pathWord);
        sMangaCreate.setTitle(TranslateKt.translate(this.name, language));
        sMangaCreate.setAuthor(CollectionsKt.joinToString$default(this.author, (CharSequence) null, (CharSequence) null, (CharSequence) null, 0, (CharSequence) null, new Function1<AuthorInfo, CharSequence>() { // from class: eu.kanade.tachiyomi.extension.zh.copymanga.api.dto.ComicSummary$toSManga$1$1
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
