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

/* JADX INFO: compiled from: SearchResult.kt */
/* JADX INFO: loaded from: classes.dex */
@Metadata(d1 = {"\u0000X\n\u0002\u0018\u0002\n\u0002\u0010\u0000\n\u0000\n\u0002\u0010\b\n\u0000\n\u0002\u0010\u000e\n\u0002\b\u0005\n\u0002\u0010 \n\u0002\u0018\u0002\n\u0002\b\u0002\n\u0002\u0018\u0002\n\u0002\b\u001a\n\u0002\u0010\u000b\n\u0002\b\u0003\n\u0002\u0018\u0002\n\u0000\n\u0002\u0018\u0002\n\u0002\b\u0002\n\u0002\u0010\u0002\n\u0002\b\u0002\n\u0002\u0018\u0002\n\u0000\n\u0002\u0018\u0002\n\u0002\b\u0003\b\u0087\b\u0018\u0000 :2\u00020\u0001:\u00029:Be\b\u0017\u0012\u0006\u0010\u0002\u001a\u00020\u0003\u0012\b\u0010\u0004\u001a\u0004\u0018\u00010\u0005\u0012\b\u0010\u0006\u001a\u0004\u0018\u00010\u0005\u0012\n\b\u0001\u0010\u0007\u001a\u0004\u0018\u00010\u0005\u0012\b\u0010\b\u001a\u0004\u0018\u00010\u0005\u0012\b\u0010\t\u001a\u0004\u0018\u00010\u0003\u0012\u000e\u0010\n\u001a\n\u0012\u0004\u0012\u00020\f\u0018\u00010\u000b\u0012\u0006\u0010\r\u001a\u00020\u0003\u0012\b\u0010\u000e\u001a\u0004\u0018\u00010\u000f¢\u0006\u0002\u0010\u0010BK\u0012\u0006\u0010\u0004\u001a\u00020\u0005\u0012\n\b\u0002\u0010\u0006\u001a\u0004\u0018\u00010\u0005\u0012\u0006\u0010\u0007\u001a\u00020\u0005\u0012\u0006\u0010\b\u001a\u00020\u0005\u0012\n\b\u0002\u0010\t\u001a\u0004\u0018\u00010\u0003\u0012\f\u0010\n\u001a\b\u0012\u0004\u0012\u00020\f0\u000b\u0012\u0006\u0010\r\u001a\u00020\u0003¢\u0006\u0002\u0010\u0011J\t\u0010 \u001a\u00020\u0005HÆ\u0003J\u000b\u0010!\u001a\u0004\u0018\u00010\u0005HÆ\u0003J\t\u0010\"\u001a\u00020\u0005HÆ\u0003J\t\u0010#\u001a\u00020\u0005HÆ\u0003J\u0010\u0010$\u001a\u0004\u0018\u00010\u0003HÆ\u0003¢\u0006\u0002\u0010\u0017J\u000f\u0010%\u001a\b\u0012\u0004\u0012\u00020\f0\u000bHÆ\u0003J\t\u0010&\u001a\u00020\u0003HÆ\u0003J^\u0010'\u001a\u00020\u00002\b\b\u0002\u0010\u0004\u001a\u00020\u00052\n\b\u0002\u0010\u0006\u001a\u0004\u0018\u00010\u00052\b\b\u0002\u0010\u0007\u001a\u00020\u00052\b\b\u0002\u0010\b\u001a\u00020\u00052\n\b\u0002\u0010\t\u001a\u0004\u0018\u00010\u00032\u000e\b\u0002\u0010\n\u001a\b\u0012\u0004\u0012\u00020\f0\u000b2\b\b\u0002\u0010\r\u001a\u00020\u0003HÆ\u0001¢\u0006\u0002\u0010(J\u0013\u0010)\u001a\u00020*2\b\u0010+\u001a\u0004\u0018\u00010\u0001HÖ\u0003J\t\u0010,\u001a\u00020\u0003HÖ\u0001J\u000e\u0010-\u001a\u00020.2\u0006\u0010/\u001a\u000200J\t\u00101\u001a\u00020\u0005HÖ\u0001J!\u00102\u001a\u0002032\u0006\u00104\u001a\u00020\u00002\u0006\u00105\u001a\u0002062\u0006\u00107\u001a\u000208HÇ\u0001R\u0013\u0010\u0006\u001a\u0004\u0018\u00010\u0005¢\u0006\b\n\u0000\u001a\u0004\b\u0012\u0010\u0013R\u0017\u0010\n\u001a\b\u0012\u0004\u0012\u00020\f0\u000b¢\u0006\b\n\u0000\u001a\u0004\b\u0014\u0010\u0015R\u0015\u0010\t\u001a\u0004\u0018\u00010\u0003¢\u0006\n\n\u0002\u0010\u0018\u001a\u0004\b\u0016\u0010\u0017R\u0011\u0010\b\u001a\u00020\u0005¢\u0006\b\n\u0000\u001a\u0004\b\u0019\u0010\u0013R\u0011\u0010\u0004\u001a\u00020\u0005¢\u0006\b\n\u0000\u001a\u0004\b\u001a\u0010\u0013R\u001c\u0010\u0007\u001a\u00020\u00058\u0006X\u0087\u0004¢\u0006\u000e\n\u0000\u0012\u0004\b\u001b\u0010\u001c\u001a\u0004\b\u001d\u0010\u0013R\u0011\u0010\r\u001a\u00020\u0003¢\u0006\b\n\u0000\u001a\u0004\b\u001e\u0010\u001f¨\u0006;"}, d2 = {"Leu/kanade/tachiyomi/extension/zh/copymanga/api/dto/SearchComic;", "", "seen1", "", "name", "", "alias", "pathWord", "cover", "ban", "author", "", "Leu/kanade/tachiyomi/extension/zh/copymanga/api/dto/SearchComicAuthorVO;", "popular", "serializationConstructorMarker", "Lkotlinx/serialization/internal/SerializationConstructorMarker;", "(ILjava/lang/String;Ljava/lang/String;Ljava/lang/String;Ljava/lang/String;Ljava/lang/Integer;Ljava/util/List;ILkotlinx/serialization/internal/SerializationConstructorMarker;)V", "(Ljava/lang/String;Ljava/lang/String;Ljava/lang/String;Ljava/lang/String;Ljava/lang/Integer;Ljava/util/List;I)V", "getAlias", "()Ljava/lang/String;", "getAuthor", "()Ljava/util/List;", "getBan", "()Ljava/lang/Integer;", "Ljava/lang/Integer;", "getCover", "getName", "getPathWord$annotations", "()V", "getPathWord", "getPopular", "()I", "component1", "component2", "component3", "component4", "component5", "component6", "component7", "copy", "(Ljava/lang/String;Ljava/lang/String;Ljava/lang/String;Ljava/lang/String;Ljava/lang/Integer;Ljava/util/List;I)Leu/kanade/tachiyomi/extension/zh/copymanga/api/dto/SearchComic;", "equals", "", "other", "hashCode", "toSManga", "Leu/kanade/tachiyomi/source/model/SManga;", "language", "Leu/kanade/tachiyomi/extension/zh/copymanga/CCOption;", "toString", "write$Self", "", "self", "output", "Lkotlinx/serialization/encoding/CompositeEncoder;", "serialDesc", "Lkotlinx/serialization/descriptors/SerialDescriptor;", "$serializer", "Companion", "tachiyomi-zh.copymanga-v1.4.82_release"}, k = 1, mv = {1, 7, 1}, xi = 48)
@Serializable
public final /* data */ class SearchComic {

    /* JADX INFO: renamed from: Companion, reason: from kotlin metadata */
    public static final Companion INSTANCE = new Companion(null);
    private final String alias;
    private final List<SearchComicAuthorVO> author;
    private final Integer ban;
    private final String cover;
    private final String name;
    private final String pathWord;
    private final int popular;

    /* JADX WARN: Multi-variable type inference failed */
    public static /* synthetic */ SearchComic copy$default(SearchComic searchComic, String str, String str2, String str3, String str4, Integer num, List list, int i, int i2, Object obj) {
        if ((i2 & 1) != 0) {
            str = searchComic.name;
        }
        if ((i2 & 2) != 0) {
            str2 = searchComic.alias;
        }
        String str5 = str2;
        if ((i2 & 4) != 0) {
            str3 = searchComic.pathWord;
        }
        String str6 = str3;
        if ((i2 & 8) != 0) {
            str4 = searchComic.cover;
        }
        String str7 = str4;
        if ((i2 & 16) != 0) {
            num = searchComic.ban;
        }
        Integer num2 = num;
        if ((i2 & 32) != 0) {
            list = searchComic.author;
        }
        List list2 = list;
        if ((i2 & 64) != 0) {
            i = searchComic.popular;
        }
        return searchComic.copy(str, str5, str6, str7, num2, list2, i);
    }

    @SerialName("path_word")
    public static /* synthetic */ void getPathWord$annotations() {
    }

    /* JADX INFO: renamed from: component1, reason: from getter */
    public final String getName() {
        return this.name;
    }

    /* JADX INFO: renamed from: component2, reason: from getter */
    public final String getAlias() {
        return this.alias;
    }

    /* JADX INFO: renamed from: component3, reason: from getter */
    public final String getPathWord() {
        return this.pathWord;
    }

    /* JADX INFO: renamed from: component4, reason: from getter */
    public final String getCover() {
        return this.cover;
    }

    /* JADX INFO: renamed from: component5, reason: from getter */
    public final Integer getBan() {
        return this.ban;
    }

    public final List<SearchComicAuthorVO> component6() {
        return this.author;
    }

    /* JADX INFO: renamed from: component7, reason: from getter */
    public final int getPopular() {
        return this.popular;
    }

    public final SearchComic copy(String name, String alias, String pathWord, String cover, Integer ban, List<SearchComicAuthorVO> author, int popular) {
        Intrinsics.checkNotNullParameter(name, "name");
        Intrinsics.checkNotNullParameter(pathWord, "pathWord");
        Intrinsics.checkNotNullParameter(cover, "cover");
        Intrinsics.checkNotNullParameter(author, "author");
        return new SearchComic(name, alias, pathWord, cover, ban, author, popular);
    }

    public boolean equals(Object other) {
        if (this == other) {
            return true;
        }
        if (!(other instanceof SearchComic)) {
            return false;
        }
        SearchComic searchComic = (SearchComic) other;
        return Intrinsics.areEqual(this.name, searchComic.name) && Intrinsics.areEqual(this.alias, searchComic.alias) && Intrinsics.areEqual(this.pathWord, searchComic.pathWord) && Intrinsics.areEqual(this.cover, searchComic.cover) && Intrinsics.areEqual(this.ban, searchComic.ban) && Intrinsics.areEqual(this.author, searchComic.author) && this.popular == searchComic.popular;
    }

    public int hashCode() {
        int iHashCode = this.name.hashCode() * 31;
        String str = this.alias;
        int iHashCode2 = (((((iHashCode + (str == null ? 0 : str.hashCode())) * 31) + this.pathWord.hashCode()) * 31) + this.cover.hashCode()) * 31;
        Integer num = this.ban;
        return ((((iHashCode2 + (num != null ? num.hashCode() : 0)) * 31) + this.author.hashCode()) * 31) + this.popular;
    }

    public String toString() {
        return "SearchComic(name=" + this.name + ", alias=" + this.alias + ", pathWord=" + this.pathWord + ", cover=" + this.cover + ", ban=" + this.ban + ", author=" + this.author + ", popular=" + this.popular + ')';
    }

    /* JADX INFO: compiled from: SearchResult.kt */
    @Metadata(d1 = {"\u0000\u0016\n\u0002\u0018\u0002\n\u0002\u0010\u0000\n\u0002\b\u0002\n\u0002\u0018\u0002\n\u0002\u0018\u0002\n\u0000\b\u0086\u0003\u0018\u00002\u00020\u0001B\u0007\b\u0002¢\u0006\u0002\u0010\u0002J\u000f\u0010\u0003\u001a\b\u0012\u0004\u0012\u00020\u00050\u0004HÆ\u0001¨\u0006\u0006"}, d2 = {"Leu/kanade/tachiyomi/extension/zh/copymanga/api/dto/SearchComic$Companion;", "", "()V", "serializer", "Lkotlinx/serialization/KSerializer;", "Leu/kanade/tachiyomi/extension/zh/copymanga/api/dto/SearchComic;", "tachiyomi-zh.copymanga-v1.4.82_release"}, k = 1, mv = {1, 7, 1}, xi = 48)
    public static final class Companion {
        public /* synthetic */ Companion(DefaultConstructorMarker defaultConstructorMarker) {
            this();
        }

        private Companion() {
        }

        public final KSerializer<SearchComic> serializer() {
            return SearchComic$$serializer.INSTANCE;
        }
    }

    @Deprecated(level = DeprecationLevel.HIDDEN, message = "This synthesized declaration should not be used directly", replaceWith = @ReplaceWith(expression = "", imports = {}))
    public /* synthetic */ SearchComic(int i, String str, String str2, @SerialName("path_word") String str3, String str4, Integer num, List list, int i2, SerializationConstructorMarker serializationConstructorMarker) {
        if (109 != (i & 109)) {
            PluginExceptionsKt.throwMissingFieldException(i, 109, SearchComic$$serializer.INSTANCE.getDescriptor());
        }
        this.name = str;
        if ((i & 2) == 0) {
            this.alias = null;
        } else {
            this.alias = str2;
        }
        this.pathWord = str3;
        this.cover = str4;
        if ((i & 16) == 0) {
            this.ban = null;
        } else {
            this.ban = num;
        }
        this.author = list;
        this.popular = i2;
    }

    public SearchComic(String str, String str2, String str3, String str4, Integer num, List<SearchComicAuthorVO> list, int i) {
        Intrinsics.checkNotNullParameter(str, "name");
        Intrinsics.checkNotNullParameter(str3, "pathWord");
        Intrinsics.checkNotNullParameter(str4, "cover");
        Intrinsics.checkNotNullParameter(list, "author");
        this.name = str;
        this.alias = str2;
        this.pathWord = str3;
        this.cover = str4;
        this.ban = num;
        this.author = list;
        this.popular = i;
    }

    @JvmStatic
    public static final void write$Self(SearchComic self, CompositeEncoder output, SerialDescriptor serialDesc) {
        Intrinsics.checkNotNullParameter(self, "self");
        Intrinsics.checkNotNullParameter(output, "output");
        Intrinsics.checkNotNullParameter(serialDesc, "serialDesc");
        output.encodeStringElement(serialDesc, 0, self.name);
        if (output.shouldEncodeElementDefault(serialDesc, 1) || self.alias != null) {
            output.encodeNullableSerializableElement(serialDesc, 1, StringSerializer.INSTANCE, self.alias);
        }
        output.encodeStringElement(serialDesc, 2, self.pathWord);
        output.encodeStringElement(serialDesc, 3, self.cover);
        if (output.shouldEncodeElementDefault(serialDesc, 4) || self.ban != null) {
            output.encodeNullableSerializableElement(serialDesc, 4, IntSerializer.INSTANCE, self.ban);
        }
        output.encodeSerializableElement(serialDesc, 5, new ArrayListSerializer(SearchComicAuthorVO$$serializer.INSTANCE), self.author);
        output.encodeIntElement(serialDesc, 6, self.popular);
    }

    public /* synthetic */ SearchComic(String str, String str2, String str3, String str4, Integer num, List list, int i, int i2, DefaultConstructorMarker defaultConstructorMarker) {
        this(str, (i2 & 2) != 0 ? null : str2, str3, str4, (i2 & 16) != 0 ? null : num, list, i);
    }

    public final String getName() {
        return this.name;
    }

    public final String getAlias() {
        return this.alias;
    }

    public final String getPathWord() {
        return this.pathWord;
    }

    public final String getCover() {
        return this.cover;
    }

    public final Integer getBan() {
        return this.ban;
    }

    public final List<SearchComicAuthorVO> getAuthor() {
        return this.author;
    }

    public final int getPopular() {
        return this.popular;
    }

    public final SManga toSManga(final CCOption language) {
        Intrinsics.checkNotNullParameter(language, "language");
        SManga sMangaCreate = SManga.Companion.create();
        sMangaCreate.setUrl("/comic/" + this.pathWord);
        sMangaCreate.setTitle(TranslateKt.translate(this.name, language));
        sMangaCreate.setAuthor(CollectionsKt.joinToString$default(this.author, (CharSequence) null, (CharSequence) null, (CharSequence) null, 0, (CharSequence) null, new Function1<SearchComicAuthorVO, CharSequence>() { // from class: eu.kanade.tachiyomi.extension.zh.copymanga.api.dto.SearchComic$toSManga$1$1
            {
                super(1);
            }

            public final CharSequence invoke(SearchComicAuthorVO searchComicAuthorVO) {
                Intrinsics.checkNotNullParameter(searchComicAuthorVO, "it");
                return TranslateKt.translate(searchComicAuthorVO.getName(), language);
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
