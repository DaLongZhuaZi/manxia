package eu.kanade.tachiyomi.extension.zh.copymanga.api.dto;

import eu.kanade.tachiyomi.extension.zh.copymanga.CCOption;
import eu.kanade.tachiyomi.extension.zh.copymanga.ResolutionOption;
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
import kotlinx.serialization.json.JsonElement;
import kotlinx.serialization.json.JsonElementSerializer;

/* JADX INFO: compiled from: RecommendResult.kt */
/* JADX INFO: loaded from: classes.dex */
@Metadata(d1 = {"\u0000l\n\u0002\u0018\u0002\n\u0002\u0010\u0000\n\u0000\n\u0002\u0010\b\n\u0000\n\u0002\u0010\u000e\n\u0000\n\u0002\u0010 \n\u0002\u0018\u0002\n\u0002\u0018\u0002\n\u0002\b\u0002\n\u0002\u0018\u0002\n\u0002\b\u0002\n\u0002\u0018\u0002\n\u0002\b\u0003\n\u0002\u0018\u0002\n\u0002\b\u0019\n\u0002\u0010\u000b\n\u0002\b\u0003\n\u0002\u0018\u0002\n\u0002\b\u0002\n\u0002\u0018\u0002\n\u0002\b\u0002\n\u0002\u0010\u0002\n\u0002\b\u0002\n\u0002\u0018\u0002\n\u0000\n\u0002\u0018\u0002\n\u0002\b\u0003\b\u0087\b\u0018\u0000 >2\u00020\u0001:\u0002=>B\u0090\u0001\b\u0017\u0012\u0006\u0010\u0002\u001a\u00020\u0003\u0012\b\u0010\u0004\u001a\u0004\u0018\u00010\u0005\u0012\u0013\u0010\u0006\u001a\u000f\u0012\t\u0012\u00070\b¢\u0006\u0002\b\t\u0018\u00010\u0007\u0012\u0013\u0010\n\u001a\u000f\u0012\t\u0012\u00070\b¢\u0006\u0002\b\t\u0018\u00010\u0007\u0012\u0013\u0010\u000b\u001a\u000f\u0012\t\u0012\u00070\f¢\u0006\u0002\b\t\u0018\u00010\u0007\u0012\n\b\u0001\u0010\r\u001a\u0004\u0018\u00010\u0005\u0012\u000e\u0010\u000e\u001a\n\u0012\u0004\u0012\u00020\u000f\u0018\u00010\u0007\u0012\b\u0010\u0010\u001a\u0004\u0018\u00010\u0005\u0012\u0006\u0010\u0011\u001a\u00020\u0003\u0012\b\u0010\u0012\u001a\u0004\u0018\u00010\u0013¢\u0006\u0002\u0010\u0014Br\u0012\u0006\u0010\u0004\u001a\u00020\u0005\u0012\u0013\b\u0002\u0010\u0006\u001a\r\u0012\t\u0012\u00070\b¢\u0006\u0002\b\t0\u0007\u0012\u0013\b\u0002\u0010\n\u001a\r\u0012\t\u0012\u00070\b¢\u0006\u0002\b\t0\u0007\u0012\u0013\b\u0002\u0010\u000b\u001a\r\u0012\t\u0012\u00070\f¢\u0006\u0002\b\t0\u0007\u0012\u0006\u0010\r\u001a\u00020\u0005\u0012\f\u0010\u000e\u001a\b\u0012\u0004\u0012\u00020\u000f0\u0007\u0012\u0006\u0010\u0010\u001a\u00020\u0005\u0012\u0006\u0010\u0011\u001a\u00020\u0003¢\u0006\u0002\u0010\u0015J\t\u0010#\u001a\u00020\u0005HÆ\u0003J\u0014\u0010$\u001a\r\u0012\t\u0012\u00070\b¢\u0006\u0002\b\t0\u0007HÆ\u0003J\u0014\u0010%\u001a\r\u0012\t\u0012\u00070\b¢\u0006\u0002\b\t0\u0007HÆ\u0003J\u0014\u0010&\u001a\r\u0012\t\u0012\u00070\f¢\u0006\u0002\b\t0\u0007HÆ\u0003J\t\u0010'\u001a\u00020\u0005HÆ\u0003J\u000f\u0010(\u001a\b\u0012\u0004\u0012\u00020\u000f0\u0007HÆ\u0003J\t\u0010)\u001a\u00020\u0005HÆ\u0003J\t\u0010*\u001a\u00020\u0003HÆ\u0003J\u0080\u0001\u0010+\u001a\u00020\u00002\b\b\u0002\u0010\u0004\u001a\u00020\u00052\u0013\b\u0002\u0010\u0006\u001a\r\u0012\t\u0012\u00070\b¢\u0006\u0002\b\t0\u00072\u0013\b\u0002\u0010\n\u001a\r\u0012\t\u0012\u00070\b¢\u0006\u0002\b\t0\u00072\u0013\b\u0002\u0010\u000b\u001a\r\u0012\t\u0012\u00070\f¢\u0006\u0002\b\t0\u00072\b\b\u0002\u0010\r\u001a\u00020\u00052\u000e\b\u0002\u0010\u000e\u001a\b\u0012\u0004\u0012\u00020\u000f0\u00072\b\b\u0002\u0010\u0010\u001a\u00020\u00052\b\b\u0002\u0010\u0011\u001a\u00020\u0003HÆ\u0001J\u0013\u0010,\u001a\u00020-2\b\u0010.\u001a\u0004\u0018\u00010\u0001HÖ\u0003J\t\u0010/\u001a\u00020\u0003HÖ\u0001J\u0016\u00100\u001a\u0002012\u0006\u00102\u001a\u00020\u00052\u0006\u00103\u001a\u000204J\t\u00105\u001a\u00020\u0005HÖ\u0001J!\u00106\u001a\u0002072\u0006\u00108\u001a\u00020\u00002\u0006\u00109\u001a\u00020:2\u0006\u0010;\u001a\u00020<HÇ\u0001R\u0017\u0010\u000e\u001a\b\u0012\u0004\u0012\u00020\u000f0\u0007¢\u0006\b\n\u0000\u001a\u0004\b\u0016\u0010\u0017R\u0011\u0010\u0010\u001a\u00020\u0005¢\u0006\b\n\u0000\u001a\u0004\b\u0018\u0010\u0019R\u001c\u0010\u0006\u001a\r\u0012\t\u0012\u00070\b¢\u0006\u0002\b\t0\u0007¢\u0006\b\n\u0000\u001a\u0004\b\u001a\u0010\u0017R\u001c\u0010\n\u001a\r\u0012\t\u0012\u00070\b¢\u0006\u0002\b\t0\u0007¢\u0006\b\n\u0000\u001a\u0004\b\u001b\u0010\u0017R\u0011\u0010\u0004\u001a\u00020\u0005¢\u0006\b\n\u0000\u001a\u0004\b\u001c\u0010\u0019R\u001c\u0010\r\u001a\u00020\u00058\u0006X\u0087\u0004¢\u0006\u000e\n\u0000\u0012\u0004\b\u001d\u0010\u001e\u001a\u0004\b\u001f\u0010\u0019R\u0011\u0010\u0011\u001a\u00020\u0003¢\u0006\b\n\u0000\u001a\u0004\b \u0010!R\u001c\u0010\u000b\u001a\r\u0012\t\u0012\u00070\f¢\u0006\u0002\b\t0\u0007¢\u0006\b\n\u0000\u001a\u0004\b\"\u0010\u0017¨\u0006?"}, d2 = {"Leu/kanade/tachiyomi/extension/zh/copymanga/api/dto/RecommendComic;", "", "seen1", "", "name", "", "females", "", "Lkotlinx/serialization/json/JsonElement;", "Lkotlinx/serialization/Contextual;", "males", "theme", "Leu/kanade/tachiyomi/extension/zh/copymanga/api/dto/ThemeInfo;", "pathWord", "author", "Leu/kanade/tachiyomi/extension/zh/copymanga/api/dto/AuthorInfo;", "cover", "popular", "serializationConstructorMarker", "Lkotlinx/serialization/internal/SerializationConstructorMarker;", "(ILjava/lang/String;Ljava/util/List;Ljava/util/List;Ljava/util/List;Ljava/lang/String;Ljava/util/List;Ljava/lang/String;ILkotlinx/serialization/internal/SerializationConstructorMarker;)V", "(Ljava/lang/String;Ljava/util/List;Ljava/util/List;Ljava/util/List;Ljava/lang/String;Ljava/util/List;Ljava/lang/String;I)V", "getAuthor", "()Ljava/util/List;", "getCover", "()Ljava/lang/String;", "getFemales", "getMales", "getName", "getPathWord$annotations", "()V", "getPathWord", "getPopular", "()I", "getTheme", "component1", "component2", "component3", "component4", "component5", "component6", "component7", "component8", "copy", "equals", "", "other", "hashCode", "toSManga", "Leu/kanade/tachiyomi/source/model/SManga;", "resolution", "language", "Leu/kanade/tachiyomi/extension/zh/copymanga/CCOption;", "toString", "write$Self", "", "self", "output", "Lkotlinx/serialization/encoding/CompositeEncoder;", "serialDesc", "Lkotlinx/serialization/descriptors/SerialDescriptor;", "$serializer", "Companion", "tachiyomi-zh.copymanga-v1.4.82_release"}, k = 1, mv = {1, 7, 1}, xi = 48)
@Serializable
public final /* data */ class RecommendComic {

    /* JADX INFO: renamed from: Companion, reason: from kotlin metadata */
    public static final Companion INSTANCE = new Companion(null);
    private final List<AuthorInfo> author;
    private final String cover;
    private final List<JsonElement> females;
    private final List<JsonElement> males;
    private final String name;
    private final String pathWord;
    private final int popular;
    private final List<ThemeInfo> theme;

    @SerialName("path_word")
    public static /* synthetic */ void getPathWord$annotations() {
    }

    /* JADX INFO: renamed from: component1, reason: from getter */
    public final String getName() {
        return this.name;
    }

    public final List<JsonElement> component2() {
        return this.females;
    }

    public final List<JsonElement> component3() {
        return this.males;
    }

    public final List<ThemeInfo> component4() {
        return this.theme;
    }

    /* JADX INFO: renamed from: component5, reason: from getter */
    public final String getPathWord() {
        return this.pathWord;
    }

    public final List<AuthorInfo> component6() {
        return this.author;
    }

    /* JADX INFO: renamed from: component7, reason: from getter */
    public final String getCover() {
        return this.cover;
    }

    /* JADX INFO: renamed from: component8, reason: from getter */
    public final int getPopular() {
        return this.popular;
    }

    public final RecommendComic copy(String name, List<? extends JsonElement> females, List<? extends JsonElement> males, List<ThemeInfo> theme, String pathWord, List<AuthorInfo> author, String cover, int popular) {
        Intrinsics.checkNotNullParameter(name, "name");
        Intrinsics.checkNotNullParameter(females, "females");
        Intrinsics.checkNotNullParameter(males, "males");
        Intrinsics.checkNotNullParameter(theme, "theme");
        Intrinsics.checkNotNullParameter(pathWord, "pathWord");
        Intrinsics.checkNotNullParameter(author, "author");
        Intrinsics.checkNotNullParameter(cover, "cover");
        return new RecommendComic(name, females, males, theme, pathWord, author, cover, popular);
    }

    public boolean equals(Object other) {
        if (this == other) {
            return true;
        }
        if (!(other instanceof RecommendComic)) {
            return false;
        }
        RecommendComic recommendComic = (RecommendComic) other;
        return Intrinsics.areEqual(this.name, recommendComic.name) && Intrinsics.areEqual(this.females, recommendComic.females) && Intrinsics.areEqual(this.males, recommendComic.males) && Intrinsics.areEqual(this.theme, recommendComic.theme) && Intrinsics.areEqual(this.pathWord, recommendComic.pathWord) && Intrinsics.areEqual(this.author, recommendComic.author) && Intrinsics.areEqual(this.cover, recommendComic.cover) && this.popular == recommendComic.popular;
    }

    public int hashCode() {
        return (((((((((((((this.name.hashCode() * 31) + this.females.hashCode()) * 31) + this.males.hashCode()) * 31) + this.theme.hashCode()) * 31) + this.pathWord.hashCode()) * 31) + this.author.hashCode()) * 31) + this.cover.hashCode()) * 31) + this.popular;
    }

    public String toString() {
        return "RecommendComic(name=" + this.name + ", females=" + this.females + ", males=" + this.males + ", theme=" + this.theme + ", pathWord=" + this.pathWord + ", author=" + this.author + ", cover=" + this.cover + ", popular=" + this.popular + ')';
    }

    /* JADX INFO: compiled from: RecommendResult.kt */
    @Metadata(d1 = {"\u0000\u0016\n\u0002\u0018\u0002\n\u0002\u0010\u0000\n\u0002\b\u0002\n\u0002\u0018\u0002\n\u0002\u0018\u0002\n\u0000\b\u0086\u0003\u0018\u00002\u00020\u0001B\u0007\b\u0002¢\u0006\u0002\u0010\u0002J\u000f\u0010\u0003\u001a\b\u0012\u0004\u0012\u00020\u00050\u0004HÆ\u0001¨\u0006\u0006"}, d2 = {"Leu/kanade/tachiyomi/extension/zh/copymanga/api/dto/RecommendComic$Companion;", "", "()V", "serializer", "Lkotlinx/serialization/KSerializer;", "Leu/kanade/tachiyomi/extension/zh/copymanga/api/dto/RecommendComic;", "tachiyomi-zh.copymanga-v1.4.82_release"}, k = 1, mv = {1, 7, 1}, xi = 48)
    public static final class Companion {
        public /* synthetic */ Companion(DefaultConstructorMarker defaultConstructorMarker) {
            this();
        }

        private Companion() {
        }

        public final KSerializer<RecommendComic> serializer() {
            return RecommendComic$$serializer.INSTANCE;
        }
    }

    @Deprecated(level = DeprecationLevel.HIDDEN, message = "This synthesized declaration should not be used directly", replaceWith = @ReplaceWith(expression = "", imports = {}))
    public /* synthetic */ RecommendComic(int i, String str, List list, List list2, List list3, @SerialName("path_word") String str2, List list4, String str3, int i2, SerializationConstructorMarker serializationConstructorMarker) {
        if (241 != (i & 241)) {
            PluginExceptionsKt.throwMissingFieldException(i, 241, RecommendComic$$serializer.INSTANCE.getDescriptor());
        }
        this.name = str;
        if ((i & 2) == 0) {
            this.females = CollectionsKt.emptyList();
        } else {
            this.females = list;
        }
        if ((i & 4) == 0) {
            this.males = CollectionsKt.emptyList();
        } else {
            this.males = list2;
        }
        if ((i & 8) == 0) {
            this.theme = CollectionsKt.emptyList();
        } else {
            this.theme = list3;
        }
        this.pathWord = str2;
        this.author = list4;
        this.cover = str3;
        this.popular = i2;
    }

    public RecommendComic(String str, List<? extends JsonElement> list, List<? extends JsonElement> list2, List<ThemeInfo> list3, String str2, List<AuthorInfo> list4, String str3, int i) {
        Intrinsics.checkNotNullParameter(str, "name");
        Intrinsics.checkNotNullParameter(list, "females");
        Intrinsics.checkNotNullParameter(list2, "males");
        Intrinsics.checkNotNullParameter(list3, "theme");
        Intrinsics.checkNotNullParameter(str2, "pathWord");
        Intrinsics.checkNotNullParameter(list4, "author");
        Intrinsics.checkNotNullParameter(str3, "cover");
        this.name = str;
        this.females = list;
        this.males = list2;
        this.theme = list3;
        this.pathWord = str2;
        this.author = list4;
        this.cover = str3;
        this.popular = i;
    }

    @JvmStatic
    public static final void write$Self(RecommendComic self, CompositeEncoder output, SerialDescriptor serialDesc) {
        Intrinsics.checkNotNullParameter(self, "self");
        Intrinsics.checkNotNullParameter(output, "output");
        Intrinsics.checkNotNullParameter(serialDesc, "serialDesc");
        output.encodeStringElement(serialDesc, 0, self.name);
        if (output.shouldEncodeElementDefault(serialDesc, 1) || !Intrinsics.areEqual(self.females, CollectionsKt.emptyList())) {
            output.encodeSerializableElement(serialDesc, 1, new ArrayListSerializer(new ContextualSerializer(Reflection.getOrCreateKotlinClass(JsonElement.class), JsonElementSerializer.INSTANCE, new KSerializer[0])), self.females);
        }
        if (output.shouldEncodeElementDefault(serialDesc, 2) || !Intrinsics.areEqual(self.males, CollectionsKt.emptyList())) {
            output.encodeSerializableElement(serialDesc, 2, new ArrayListSerializer(new ContextualSerializer(Reflection.getOrCreateKotlinClass(JsonElement.class), JsonElementSerializer.INSTANCE, new KSerializer[0])), self.males);
        }
        if (output.shouldEncodeElementDefault(serialDesc, 3) || !Intrinsics.areEqual(self.theme, CollectionsKt.emptyList())) {
            output.encodeSerializableElement(serialDesc, 3, new ArrayListSerializer(new ContextualSerializer(Reflection.getOrCreateKotlinClass(ThemeInfo.class), ThemeInfo$$serializer.INSTANCE, new KSerializer[0])), self.theme);
        }
        output.encodeStringElement(serialDesc, 4, self.pathWord);
        output.encodeSerializableElement(serialDesc, 5, new ArrayListSerializer(AuthorInfo$$serializer.INSTANCE), self.author);
        output.encodeStringElement(serialDesc, 6, self.cover);
        output.encodeIntElement(serialDesc, 7, self.popular);
    }

    public final String getName() {
        return this.name;
    }

    public /* synthetic */ RecommendComic(String str, List list, List list2, List list3, String str2, List list4, String str3, int i, int i2, DefaultConstructorMarker defaultConstructorMarker) {
        this(str, (i2 & 2) != 0 ? CollectionsKt.emptyList() : list, (i2 & 4) != 0 ? CollectionsKt.emptyList() : list2, (i2 & 8) != 0 ? CollectionsKt.emptyList() : list3, str2, list4, str3, i);
    }

    public final List<JsonElement> getFemales() {
        return this.females;
    }

    public final List<JsonElement> getMales() {
        return this.males;
    }

    public final List<ThemeInfo> getTheme() {
        return this.theme;
    }

    public final String getPathWord() {
        return this.pathWord;
    }

    public final List<AuthorInfo> getAuthor() {
        return this.author;
    }

    public final String getCover() {
        return this.cover;
    }

    public final int getPopular() {
        return this.popular;
    }

    public final SManga toSManga(String resolution, CCOption language) {
        Intrinsics.checkNotNullParameter(resolution, "resolution");
        Intrinsics.checkNotNullParameter(language, "language");
        SManga sMangaCreate = SManga.Companion.create();
        sMangaCreate.setUrl("/comic/" + this.pathWord);
        sMangaCreate.setTitle(TranslateKt.translate(this.name, language));
        sMangaCreate.setAuthor(CollectionsKt.joinToString$default(this.author, (CharSequence) null, (CharSequence) null, (CharSequence) null, 0, (CharSequence) null, new Function1<AuthorInfo, CharSequence>() { // from class: eu.kanade.tachiyomi.extension.zh.copymanga.api.dto.RecommendComic$toSManga$1$1
            public final CharSequence invoke(AuthorInfo authorInfo) {
                Intrinsics.checkNotNullParameter(authorInfo, "it");
                return authorInfo.getName();
            }
        }, 31, (Object) null));
        sMangaCreate.setDescription("");
        sMangaCreate.setGenre(CollectionsKt.joinToString$default(this.theme, (CharSequence) null, (CharSequence) null, (CharSequence) null, 0, (CharSequence) null, (Function1) null, 63, (Object) null));
        sMangaCreate.setStatus(0);
        sMangaCreate.setThumbnail_url(ResolutionOption.INSTANCE.translate(this.cover, resolution));
        sMangaCreate.setInitialized(false);
        return sMangaCreate;
    }
}
