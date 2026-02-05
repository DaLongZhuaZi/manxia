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
import kotlinx.serialization.json.JsonElement;
import kotlinx.serialization.json.JsonElementSerializer;

/* compiled from: RankResult.kt */
@Metadata(d1 = {"\u0000j\n\u0002\u0018\u0002\n\u0002\u0010\u0000\n\u0000\n\u0002\u0010\b\n\u0000\n\u0002\u0010\u000e\n\u0002\b\u0002\n\u0002\u0010 \n\u0002\u0018\u0002\n\u0002\u0018\u0002\n\u0002\b\u0002\n\u0002\u0018\u0002\n\u0000\n\u0002\u0018\u0002\n\u0002\b\u0003\n\u0002\u0018\u0002\n\u0002\b\u0019\n\u0002\u0010\u000b\n\u0002\b\u0003\n\u0002\u0018\u0002\n\u0000\n\u0002\u0018\u0002\n\u0002\b\u0002\n\u0002\u0010\u0002\n\u0002\b\u0002\n\u0002\u0018\u0002\n\u0000\n\u0002\u0018\u0002\n\u0002\b\u0003\b\u0087\b\u0018\u0000 =2\u00020\u0001:\u0002<=B\u0090\u0001\b\u0017\u0012\u0006\u0010\u0002\u001a\u00020\u0003\u0012\b\u0010\u0004\u001a\u0004\u0018\u00010\u0005\u0012\n\b\u0001\u0010\u0006\u001a\u0004\u0018\u00010\u0005\u0012\u0013\u0010\u0007\u001a\u000f\u0012\t\u0012\u00070\t¢\u0006\u0002\b\n\u0018\u00010\b\u0012\u0013\u0010\u000b\u001a\u000f\u0012\t\u0012\u00070\t¢\u0006\u0002\b\n\u0018\u00010\b\u0012\u000e\u0010\f\u001a\n\u0012\u0004\u0012\u00020\r\u0018\u00010\b\u0012\u0013\u0010\u000e\u001a\u000f\u0012\t\u0012\u00070\u000f¢\u0006\u0002\b\n\u0018\u00010\b\u0012\b\u0010\u0010\u001a\u0004\u0018\u00010\u0005\u0012\u0006\u0010\u0011\u001a\u00020\u0003\u0012\b\u0010\u0012\u001a\u0004\u0018\u00010\u0013¢\u0006\u0002\u0010\u0014Bl\u0012\u0006\u0010\u0004\u001a\u00020\u0005\u0012\u0006\u0010\u0006\u001a\u00020\u0005\u0012\u0011\u0010\u0007\u001a\r\u0012\t\u0012\u00070\t¢\u0006\u0002\b\n0\b\u0012\u0011\u0010\u000b\u001a\r\u0012\t\u0012\u00070\t¢\u0006\u0002\b\n0\b\u0012\f\u0010\f\u001a\b\u0012\u0004\u0012\u00020\r0\b\u0012\u0011\u0010\u000e\u001a\r\u0012\t\u0012\u00070\u000f¢\u0006\u0002\b\n0\b\u0012\u0006\u0010\u0010\u001a\u00020\u0005\u0012\u0006\u0010\u0011\u001a\u00020\u0003¢\u0006\u0002\u0010\u0015J\t\u0010#\u001a\u00020\u0005HÆ\u0003J\t\u0010$\u001a\u00020\u0005HÆ\u0003J\u0014\u0010%\u001a\r\u0012\t\u0012\u00070\t¢\u0006\u0002\b\n0\bHÆ\u0003J\u0014\u0010&\u001a\r\u0012\t\u0012\u00070\t¢\u0006\u0002\b\n0\bHÆ\u0003J\u000f\u0010'\u001a\b\u0012\u0004\u0012\u00020\r0\bHÆ\u0003J\u0014\u0010(\u001a\r\u0012\t\u0012\u00070\u000f¢\u0006\u0002\b\n0\bHÆ\u0003J\t\u0010)\u001a\u00020\u0005HÆ\u0003J\t\u0010*\u001a\u00020\u0003HÆ\u0003J\u0080\u0001\u0010+\u001a\u00020\u00002\b\b\u0002\u0010\u0004\u001a\u00020\u00052\b\b\u0002\u0010\u0006\u001a\u00020\u00052\u0013\b\u0002\u0010\u0007\u001a\r\u0012\t\u0012\u00070\t¢\u0006\u0002\b\n0\b2\u0013\b\u0002\u0010\u000b\u001a\r\u0012\t\u0012\u00070\t¢\u0006\u0002\b\n0\b2\u000e\b\u0002\u0010\f\u001a\b\u0012\u0004\u0012\u00020\r0\b2\u0013\b\u0002\u0010\u000e\u001a\r\u0012\t\u0012\u00070\u000f¢\u0006\u0002\b\n0\b2\b\b\u0002\u0010\u0010\u001a\u00020\u00052\b\b\u0002\u0010\u0011\u001a\u00020\u0003HÆ\u0001J\u0013\u0010,\u001a\u00020-2\b\u0010.\u001a\u0004\u0018\u00010\u0001HÖ\u0003J\t\u0010/\u001a\u00020\u0003HÖ\u0001J\u000e\u00100\u001a\u0002012\u0006\u00102\u001a\u000203J\t\u00104\u001a\u00020\u0005HÖ\u0001J!\u00105\u001a\u0002062\u0006\u00107\u001a\u00020\u00002\u0006\u00108\u001a\u0002092\u0006\u0010:\u001a\u00020;HÇ\u0001R\u0017\u0010\f\u001a\b\u0012\u0004\u0012\u00020\r0\b¢\u0006\b\n\u0000\u001a\u0004\b\u0016\u0010\u0017R\u0011\u0010\u0010\u001a\u00020\u0005¢\u0006\b\n\u0000\u001a\u0004\b\u0018\u0010\u0019R\u001c\u0010\u0007\u001a\r\u0012\t\u0012\u00070\t¢\u0006\u0002\b\n0\b¢\u0006\b\n\u0000\u001a\u0004\b\u001a\u0010\u0017R\u001c\u0010\u000b\u001a\r\u0012\t\u0012\u00070\t¢\u0006\u0002\b\n0\b¢\u0006\b\n\u0000\u001a\u0004\b\u001b\u0010\u0017R\u0011\u0010\u0004\u001a\u00020\u0005¢\u0006\b\n\u0000\u001a\u0004\b\u001c\u0010\u0019R\u001c\u0010\u0006\u001a\u00020\u00058\u0006X\u0087\u0004¢\u0006\u000e\n\u0000\u0012\u0004\b\u001d\u0010\u001e\u001a\u0004\b\u001f\u0010\u0019R\u0011\u0010\u0011\u001a\u00020\u0003¢\u0006\b\n\u0000\u001a\u0004\b \u0010!R\u001c\u0010\u000e\u001a\r\u0012\t\u0012\u00070\u000f¢\u0006\u0002\b\n0\b¢\u0006\b\n\u0000\u001a\u0004\b\"\u0010\u0017¨\u0006>"}, d2 = {"Leu/kanade/tachiyomi/extension/zh/copymanga/api/dto/ComicInfo;", "", "seen1", "", "name", "", "pathWord", "females", "", "Lkotlinx/serialization/json/JsonElement;", "Lkotlinx/serialization/Contextual;", "males", "author", "Leu/kanade/tachiyomi/extension/zh/copymanga/api/dto/AuthorInfo;", "theme", "Leu/kanade/tachiyomi/extension/zh/copymanga/api/dto/ThemeInfo;", "cover", "popular", "serializationConstructorMarker", "Lkotlinx/serialization/internal/SerializationConstructorMarker;", "(ILjava/lang/String;Ljava/lang/String;Ljava/util/List;Ljava/util/List;Ljava/util/List;Ljava/util/List;Ljava/lang/String;ILkotlinx/serialization/internal/SerializationConstructorMarker;)V", "(Ljava/lang/String;Ljava/lang/String;Ljava/util/List;Ljava/util/List;Ljava/util/List;Ljava/util/List;Ljava/lang/String;I)V", "getAuthor", "()Ljava/util/List;", "getCover", "()Ljava/lang/String;", "getFemales", "getMales", "getName", "getPathWord$annotations", "()V", "getPathWord", "getPopular", "()I", "getTheme", "component1", "component2", "component3", "component4", "component5", "component6", "component7", "component8", "copy", "equals", "", "other", "hashCode", "toSManga", "Leu/kanade/tachiyomi/source/model/SManga;", "language", "Leu/kanade/tachiyomi/extension/zh/copymanga/CCOption;", "toString", "write$Self", "", "self", "output", "Lkotlinx/serialization/encoding/CompositeEncoder;", "serialDesc", "Lkotlinx/serialization/descriptors/SerialDescriptor;", "$serializer", "Companion", "tachiyomi-zh.copymanga-v1.4.78_release"}, k = 1, mv = {1, 7, 1}, xi = 48)
@Serializable
/* loaded from: classes.dex */
public final /* data */ class ComicInfo {

    /* renamed from: Companion, reason: from kotlin metadata */
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

    /* renamed from: component1, reason: from getter */
    public final String getName() {
        return this.name;
    }

    /* renamed from: component2, reason: from getter */
    public final String getPathWord() {
        return this.pathWord;
    }

    public final List<JsonElement> component3() {
        return this.females;
    }

    public final List<JsonElement> component4() {
        return this.males;
    }

    public final List<AuthorInfo> component5() {
        return this.author;
    }

    public final List<ThemeInfo> component6() {
        return this.theme;
    }

    /* renamed from: component7, reason: from getter */
    public final String getCover() {
        return this.cover;
    }

    /* renamed from: component8, reason: from getter */
    public final int getPopular() {
        return this.popular;
    }

    public final ComicInfo copy(String name, String pathWord, List<? extends JsonElement> females, List<? extends JsonElement> males, List<AuthorInfo> author, List<ThemeInfo> theme, String cover, int popular) {
        Intrinsics.checkNotNullParameter(name, "name");
        Intrinsics.checkNotNullParameter(pathWord, "pathWord");
        Intrinsics.checkNotNullParameter(females, "females");
        Intrinsics.checkNotNullParameter(males, "males");
        Intrinsics.checkNotNullParameter(author, "author");
        Intrinsics.checkNotNullParameter(theme, "theme");
        Intrinsics.checkNotNullParameter(cover, "cover");
        return new ComicInfo(name, pathWord, females, males, author, theme, cover, popular);
    }

    public boolean equals(Object other) {
        if (this == other) {
            return true;
        }
        if (!(other instanceof ComicInfo)) {
            return false;
        }
        ComicInfo comicInfo = (ComicInfo) other;
        return Intrinsics.areEqual(this.name, comicInfo.name) && Intrinsics.areEqual(this.pathWord, comicInfo.pathWord) && Intrinsics.areEqual(this.females, comicInfo.females) && Intrinsics.areEqual(this.males, comicInfo.males) && Intrinsics.areEqual(this.author, comicInfo.author) && Intrinsics.areEqual(this.theme, comicInfo.theme) && Intrinsics.areEqual(this.cover, comicInfo.cover) && this.popular == comicInfo.popular;
    }

    public int hashCode() {
        return (((((((((((((this.name.hashCode() * 31) + this.pathWord.hashCode()) * 31) + this.females.hashCode()) * 31) + this.males.hashCode()) * 31) + this.author.hashCode()) * 31) + this.theme.hashCode()) * 31) + this.cover.hashCode()) * 31) + this.popular;
    }

    public String toString() {
        return "ComicInfo(name=" + this.name + ", pathWord=" + this.pathWord + ", females=" + this.females + ", males=" + this.males + ", author=" + this.author + ", theme=" + this.theme + ", cover=" + this.cover + ", popular=" + this.popular + ')';
    }

    /* compiled from: RankResult.kt */
    @Metadata(d1 = {"\u0000\u0016\n\u0002\u0018\u0002\n\u0002\u0010\u0000\n\u0002\b\u0002\n\u0002\u0018\u0002\n\u0002\u0018\u0002\n\u0000\b\u0086\u0003\u0018\u00002\u00020\u0001B\u0007\b\u0002¢\u0006\u0002\u0010\u0002J\u000f\u0010\u0003\u001a\b\u0012\u0004\u0012\u00020\u00050\u0004HÆ\u0001¨\u0006\u0006"}, d2 = {"Leu/kanade/tachiyomi/extension/zh/copymanga/api/dto/ComicInfo$Companion;", "", "()V", "serializer", "Lkotlinx/serialization/KSerializer;", "Leu/kanade/tachiyomi/extension/zh/copymanga/api/dto/ComicInfo;", "tachiyomi-zh.copymanga-v1.4.78_release"}, k = 1, mv = {1, 7, 1}, xi = 48)
    public static final class Companion {
        public /* synthetic */ Companion(DefaultConstructorMarker defaultConstructorMarker) {
            this();
        }

        private Companion() {
        }

        public final KSerializer<ComicInfo> serializer() {
            return ComicInfo$$serializer.INSTANCE;
        }
    }

    @Deprecated(level = DeprecationLevel.HIDDEN, message = "This synthesized declaration should not be used directly", replaceWith = @ReplaceWith(expression = "", imports = {}))
    public /* synthetic */ ComicInfo(int i, String str, @SerialName("path_word") String str2, List list, List list2, List list3, List list4, String str3, int i2, SerializationConstructorMarker serializationConstructorMarker) {
        if (255 != (i & 255)) {
            PluginExceptionsKt.throwMissingFieldException(i, 255, ComicInfo$$serializer.INSTANCE.getDescriptor());
        }
        this.name = str;
        this.pathWord = str2;
        this.females = list;
        this.males = list2;
        this.author = list3;
        this.theme = list4;
        this.cover = str3;
        this.popular = i2;
    }

    public ComicInfo(String str, String str2, List<? extends JsonElement> list, List<? extends JsonElement> list2, List<AuthorInfo> list3, List<ThemeInfo> list4, String str3, int i) {
        Intrinsics.checkNotNullParameter(str, "name");
        Intrinsics.checkNotNullParameter(str2, "pathWord");
        Intrinsics.checkNotNullParameter(list, "females");
        Intrinsics.checkNotNullParameter(list2, "males");
        Intrinsics.checkNotNullParameter(list3, "author");
        Intrinsics.checkNotNullParameter(list4, "theme");
        Intrinsics.checkNotNullParameter(str3, "cover");
        this.name = str;
        this.pathWord = str2;
        this.females = list;
        this.males = list2;
        this.author = list3;
        this.theme = list4;
        this.cover = str3;
        this.popular = i;
    }

    @JvmStatic
    public static final void write$Self(ComicInfo self, CompositeEncoder output, SerialDescriptor serialDesc) {
        Intrinsics.checkNotNullParameter(self, "self");
        Intrinsics.checkNotNullParameter(output, "output");
        Intrinsics.checkNotNullParameter(serialDesc, "serialDesc");
        output.encodeStringElement(serialDesc, 0, self.name);
        output.encodeStringElement(serialDesc, 1, self.pathWord);
        output.encodeSerializableElement(serialDesc, 2, new ArrayListSerializer(new ContextualSerializer(Reflection.getOrCreateKotlinClass(JsonElement.class), JsonElementSerializer.INSTANCE, new KSerializer[0])), self.females);
        output.encodeSerializableElement(serialDesc, 3, new ArrayListSerializer(new ContextualSerializer(Reflection.getOrCreateKotlinClass(JsonElement.class), JsonElementSerializer.INSTANCE, new KSerializer[0])), self.males);
        output.encodeSerializableElement(serialDesc, 4, new ArrayListSerializer(AuthorInfo$$serializer.INSTANCE), self.author);
        output.encodeSerializableElement(serialDesc, 5, new ArrayListSerializer(new ContextualSerializer(Reflection.getOrCreateKotlinClass(ThemeInfo.class), ThemeInfo$$serializer.INSTANCE, new KSerializer[0])), self.theme);
        output.encodeStringElement(serialDesc, 6, self.cover);
        output.encodeIntElement(serialDesc, 7, self.popular);
    }

    public final String getName() {
        return this.name;
    }

    public final String getPathWord() {
        return this.pathWord;
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

    public final SManga toSManga(final CCOption language) {
        Intrinsics.checkNotNullParameter(language, "language");
        SManga sMangaCreate = SManga.Companion.create();
        sMangaCreate.setUrl("/comic/" + this.pathWord);
        sMangaCreate.setTitle(TranslateKt.translate(this.name, language));
        sMangaCreate.setAuthor(CollectionsKt.joinToString$default(this.author, (CharSequence) null, (CharSequence) null, (CharSequence) null, 0, (CharSequence) null, new Function1<AuthorInfo, CharSequence>() { // from class: eu.kanade.tachiyomi.extension.zh.copymanga.api.dto.ComicInfo$toSManga$1$1
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
