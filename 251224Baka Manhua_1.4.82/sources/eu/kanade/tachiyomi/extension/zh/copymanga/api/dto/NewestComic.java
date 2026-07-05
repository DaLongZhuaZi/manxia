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
import kotlinx.serialization.KSerializer;
import kotlinx.serialization.SerialName;
import kotlinx.serialization.Serializable;
import kotlinx.serialization.descriptors.SerialDescriptor;
import kotlinx.serialization.encoding.CompositeEncoder;
import kotlinx.serialization.internal.ArrayListSerializer;
import kotlinx.serialization.internal.PluginExceptionsKt;
import kotlinx.serialization.internal.SerializationConstructorMarker;

/* JADX INFO: compiled from: NewestResult.kt */
/* JADX INFO: loaded from: classes.dex */
@Metadata(d1 = {"\u0000`\n\u0002\u0018\u0002\n\u0002\u0010\u0000\n\u0000\n\u0002\u0010\b\n\u0000\n\u0002\u0010\u000e\n\u0002\b\u0002\n\u0002\u0010 \n\u0002\u0018\u0002\n\u0000\n\u0002\u0018\u0002\n\u0002\b\u0005\n\u0002\u0018\u0002\n\u0002\b\u001b\n\u0002\u0010\u000b\n\u0002\b\u0003\n\u0002\u0018\u0002\n\u0002\b\u0002\n\u0002\u0018\u0002\n\u0002\b\u0002\n\u0002\u0010\u0002\n\u0002\b\u0002\n\u0002\u0018\u0002\n\u0000\n\u0002\u0018\u0002\n\u0002\b\u0003\b\u0087\b\u0018\u0000 >2\u00020\u0001:\u0002=>By\b\u0017\u0012\u0006\u0010\u0002\u001a\u00020\u0003\u0012\b\u0010\u0004\u001a\u0004\u0018\u00010\u0005\u0012\n\b\u0001\u0010\u0006\u001a\u0004\u0018\u00010\u0005\u0012\u000e\u0010\u0007\u001a\n\u0012\u0004\u0012\u00020\t\u0018\u00010\b\u0012\u000e\u0010\n\u001a\n\u0012\u0004\u0012\u00020\u000b\u0018\u00010\b\u0012\b\u0010\f\u001a\u0004\u0018\u00010\u0005\u0012\u0006\u0010\r\u001a\u00020\u0003\u0012\n\b\u0001\u0010\u000e\u001a\u0004\u0018\u00010\u0005\u0012\n\b\u0001\u0010\u000f\u001a\u0004\u0018\u00010\u0005\u0012\b\u0010\u0010\u001a\u0004\u0018\u00010\u0011¢\u0006\u0002\u0010\u0012BS\u0012\u0006\u0010\u0004\u001a\u00020\u0005\u0012\u0006\u0010\u0006\u001a\u00020\u0005\u0012\f\u0010\u0007\u001a\b\u0012\u0004\u0012\u00020\t0\b\u0012\u000e\b\u0002\u0010\n\u001a\b\u0012\u0004\u0012\u00020\u000b0\b\u0012\u0006\u0010\f\u001a\u00020\u0005\u0012\u0006\u0010\r\u001a\u00020\u0003\u0012\u0006\u0010\u000e\u001a\u00020\u0005\u0012\u0006\u0010\u000f\u001a\u00020\u0005¢\u0006\u0002\u0010\u0013J\t\u0010#\u001a\u00020\u0005HÆ\u0003J\t\u0010$\u001a\u00020\u0005HÆ\u0003J\u000f\u0010%\u001a\b\u0012\u0004\u0012\u00020\t0\bHÆ\u0003J\u000f\u0010&\u001a\b\u0012\u0004\u0012\u00020\u000b0\bHÆ\u0003J\t\u0010'\u001a\u00020\u0005HÆ\u0003J\t\u0010(\u001a\u00020\u0003HÆ\u0003J\t\u0010)\u001a\u00020\u0005HÆ\u0003J\t\u0010*\u001a\u00020\u0005HÆ\u0003Je\u0010+\u001a\u00020\u00002\b\b\u0002\u0010\u0004\u001a\u00020\u00052\b\b\u0002\u0010\u0006\u001a\u00020\u00052\u000e\b\u0002\u0010\u0007\u001a\b\u0012\u0004\u0012\u00020\t0\b2\u000e\b\u0002\u0010\n\u001a\b\u0012\u0004\u0012\u00020\u000b0\b2\b\b\u0002\u0010\f\u001a\u00020\u00052\b\b\u0002\u0010\r\u001a\u00020\u00032\b\b\u0002\u0010\u000e\u001a\u00020\u00052\b\b\u0002\u0010\u000f\u001a\u00020\u0005HÆ\u0001J\u0013\u0010,\u001a\u00020-2\b\u0010.\u001a\u0004\u0018\u00010\u0001HÖ\u0003J\t\u0010/\u001a\u00020\u0003HÖ\u0001J\u0016\u00100\u001a\u0002012\u0006\u00102\u001a\u00020\u00052\u0006\u00103\u001a\u000204J\t\u00105\u001a\u00020\u0005HÖ\u0001J!\u00106\u001a\u0002072\u0006\u00108\u001a\u00020\u00002\u0006\u00109\u001a\u00020:2\u0006\u0010;\u001a\u00020<HÇ\u0001R\u0017\u0010\u0007\u001a\b\u0012\u0004\u0012\u00020\t0\b¢\u0006\b\n\u0000\u001a\u0004\b\u0014\u0010\u0015R\u0011\u0010\f\u001a\u00020\u0005¢\u0006\b\n\u0000\u001a\u0004\b\u0016\u0010\u0017R\u001c\u0010\u000e\u001a\u00020\u00058\u0006X\u0087\u0004¢\u0006\u000e\n\u0000\u0012\u0004\b\u0018\u0010\u0019\u001a\u0004\b\u001a\u0010\u0017R\u001c\u0010\u000f\u001a\u00020\u00058\u0006X\u0087\u0004¢\u0006\u000e\n\u0000\u0012\u0004\b\u001b\u0010\u0019\u001a\u0004\b\u001c\u0010\u0017R\u0011\u0010\u0004\u001a\u00020\u0005¢\u0006\b\n\u0000\u001a\u0004\b\u001d\u0010\u0017R\u001c\u0010\u0006\u001a\u00020\u00058\u0006X\u0087\u0004¢\u0006\u000e\n\u0000\u0012\u0004\b\u001e\u0010\u0019\u001a\u0004\b\u001f\u0010\u0017R\u0011\u0010\r\u001a\u00020\u0003¢\u0006\b\n\u0000\u001a\u0004\b \u0010!R\u0017\u0010\n\u001a\b\u0012\u0004\u0012\u00020\u000b0\b¢\u0006\b\n\u0000\u001a\u0004\b\"\u0010\u0015¨\u0006?"}, d2 = {"Leu/kanade/tachiyomi/extension/zh/copymanga/api/dto/NewestComic;", "", "seen1", "", "name", "", "pathWord", "author", "", "Leu/kanade/tachiyomi/extension/zh/copymanga/api/dto/AuthorInfo;", "theme", "Leu/kanade/tachiyomi/extension/zh/copymanga/api/dto/ThemeInfo;", "cover", "popular", "datetimeUpdated", "lastChapterName", "serializationConstructorMarker", "Lkotlinx/serialization/internal/SerializationConstructorMarker;", "(ILjava/lang/String;Ljava/lang/String;Ljava/util/List;Ljava/util/List;Ljava/lang/String;ILjava/lang/String;Ljava/lang/String;Lkotlinx/serialization/internal/SerializationConstructorMarker;)V", "(Ljava/lang/String;Ljava/lang/String;Ljava/util/List;Ljava/util/List;Ljava/lang/String;ILjava/lang/String;Ljava/lang/String;)V", "getAuthor", "()Ljava/util/List;", "getCover", "()Ljava/lang/String;", "getDatetimeUpdated$annotations", "()V", "getDatetimeUpdated", "getLastChapterName$annotations", "getLastChapterName", "getName", "getPathWord$annotations", "getPathWord", "getPopular", "()I", "getTheme", "component1", "component2", "component3", "component4", "component5", "component6", "component7", "component8", "copy", "equals", "", "other", "hashCode", "toSManga", "Leu/kanade/tachiyomi/source/model/SManga;", "resolution", "language", "Leu/kanade/tachiyomi/extension/zh/copymanga/CCOption;", "toString", "write$Self", "", "self", "output", "Lkotlinx/serialization/encoding/CompositeEncoder;", "serialDesc", "Lkotlinx/serialization/descriptors/SerialDescriptor;", "$serializer", "Companion", "tachiyomi-zh.copymanga-v1.4.82_release"}, k = 1, mv = {1, 7, 1}, xi = 48)
@Serializable
public final /* data */ class NewestComic {

    /* JADX INFO: renamed from: Companion, reason: from kotlin metadata */
    public static final Companion INSTANCE = new Companion(null);
    private final List<AuthorInfo> author;
    private final String cover;
    private final String datetimeUpdated;
    private final String lastChapterName;
    private final String name;
    private final String pathWord;
    private final int popular;
    private final List<ThemeInfo> theme;

    @SerialName("datetime_updated")
    public static /* synthetic */ void getDatetimeUpdated$annotations() {
    }

    @SerialName("last_chapter_name")
    public static /* synthetic */ void getLastChapterName$annotations() {
    }

    @SerialName("path_word")
    public static /* synthetic */ void getPathWord$annotations() {
    }

    /* JADX INFO: renamed from: component1, reason: from getter */
    public final String getName() {
        return this.name;
    }

    /* JADX INFO: renamed from: component2, reason: from getter */
    public final String getPathWord() {
        return this.pathWord;
    }

    public final List<AuthorInfo> component3() {
        return this.author;
    }

    public final List<ThemeInfo> component4() {
        return this.theme;
    }

    /* JADX INFO: renamed from: component5, reason: from getter */
    public final String getCover() {
        return this.cover;
    }

    /* JADX INFO: renamed from: component6, reason: from getter */
    public final int getPopular() {
        return this.popular;
    }

    /* JADX INFO: renamed from: component7, reason: from getter */
    public final String getDatetimeUpdated() {
        return this.datetimeUpdated;
    }

    /* JADX INFO: renamed from: component8, reason: from getter */
    public final String getLastChapterName() {
        return this.lastChapterName;
    }

    public final NewestComic copy(String name, String pathWord, List<AuthorInfo> author, List<ThemeInfo> theme, String cover, int popular, String datetimeUpdated, String lastChapterName) {
        Intrinsics.checkNotNullParameter(name, "name");
        Intrinsics.checkNotNullParameter(pathWord, "pathWord");
        Intrinsics.checkNotNullParameter(author, "author");
        Intrinsics.checkNotNullParameter(theme, "theme");
        Intrinsics.checkNotNullParameter(cover, "cover");
        Intrinsics.checkNotNullParameter(datetimeUpdated, "datetimeUpdated");
        Intrinsics.checkNotNullParameter(lastChapterName, "lastChapterName");
        return new NewestComic(name, pathWord, author, theme, cover, popular, datetimeUpdated, lastChapterName);
    }

    public boolean equals(Object other) {
        if (this == other) {
            return true;
        }
        if (!(other instanceof NewestComic)) {
            return false;
        }
        NewestComic newestComic = (NewestComic) other;
        return Intrinsics.areEqual(this.name, newestComic.name) && Intrinsics.areEqual(this.pathWord, newestComic.pathWord) && Intrinsics.areEqual(this.author, newestComic.author) && Intrinsics.areEqual(this.theme, newestComic.theme) && Intrinsics.areEqual(this.cover, newestComic.cover) && this.popular == newestComic.popular && Intrinsics.areEqual(this.datetimeUpdated, newestComic.datetimeUpdated) && Intrinsics.areEqual(this.lastChapterName, newestComic.lastChapterName);
    }

    public int hashCode() {
        return (((((((((((((this.name.hashCode() * 31) + this.pathWord.hashCode()) * 31) + this.author.hashCode()) * 31) + this.theme.hashCode()) * 31) + this.cover.hashCode()) * 31) + this.popular) * 31) + this.datetimeUpdated.hashCode()) * 31) + this.lastChapterName.hashCode();
    }

    public String toString() {
        return "NewestComic(name=" + this.name + ", pathWord=" + this.pathWord + ", author=" + this.author + ", theme=" + this.theme + ", cover=" + this.cover + ", popular=" + this.popular + ", datetimeUpdated=" + this.datetimeUpdated + ", lastChapterName=" + this.lastChapterName + ')';
    }

    /* JADX INFO: compiled from: NewestResult.kt */
    @Metadata(d1 = {"\u0000\u0016\n\u0002\u0018\u0002\n\u0002\u0010\u0000\n\u0002\b\u0002\n\u0002\u0018\u0002\n\u0002\u0018\u0002\n\u0000\b\u0086\u0003\u0018\u00002\u00020\u0001B\u0007\b\u0002¢\u0006\u0002\u0010\u0002J\u000f\u0010\u0003\u001a\b\u0012\u0004\u0012\u00020\u00050\u0004HÆ\u0001¨\u0006\u0006"}, d2 = {"Leu/kanade/tachiyomi/extension/zh/copymanga/api/dto/NewestComic$Companion;", "", "()V", "serializer", "Lkotlinx/serialization/KSerializer;", "Leu/kanade/tachiyomi/extension/zh/copymanga/api/dto/NewestComic;", "tachiyomi-zh.copymanga-v1.4.82_release"}, k = 1, mv = {1, 7, 1}, xi = 48)
    public static final class Companion {
        public /* synthetic */ Companion(DefaultConstructorMarker defaultConstructorMarker) {
            this();
        }

        private Companion() {
        }

        public final KSerializer<NewestComic> serializer() {
            return NewestComic$$serializer.INSTANCE;
        }
    }

    @Deprecated(level = DeprecationLevel.HIDDEN, message = "This synthesized declaration should not be used directly", replaceWith = @ReplaceWith(expression = "", imports = {}))
    public /* synthetic */ NewestComic(int i, String str, @SerialName("path_word") String str2, List list, List list2, String str3, int i2, @SerialName("datetime_updated") String str4, @SerialName("last_chapter_name") String str5, SerializationConstructorMarker serializationConstructorMarker) {
        if (247 != (i & 247)) {
            PluginExceptionsKt.throwMissingFieldException(i, 247, NewestComic$$serializer.INSTANCE.getDescriptor());
        }
        this.name = str;
        this.pathWord = str2;
        this.author = list;
        if ((i & 8) == 0) {
            this.theme = CollectionsKt.emptyList();
        } else {
            this.theme = list2;
        }
        this.cover = str3;
        this.popular = i2;
        this.datetimeUpdated = str4;
        this.lastChapterName = str5;
    }

    public NewestComic(String str, String str2, List<AuthorInfo> list, List<ThemeInfo> list2, String str3, int i, String str4, String str5) {
        Intrinsics.checkNotNullParameter(str, "name");
        Intrinsics.checkNotNullParameter(str2, "pathWord");
        Intrinsics.checkNotNullParameter(list, "author");
        Intrinsics.checkNotNullParameter(list2, "theme");
        Intrinsics.checkNotNullParameter(str3, "cover");
        Intrinsics.checkNotNullParameter(str4, "datetimeUpdated");
        Intrinsics.checkNotNullParameter(str5, "lastChapterName");
        this.name = str;
        this.pathWord = str2;
        this.author = list;
        this.theme = list2;
        this.cover = str3;
        this.popular = i;
        this.datetimeUpdated = str4;
        this.lastChapterName = str5;
    }

    @JvmStatic
    public static final void write$Self(NewestComic self, CompositeEncoder output, SerialDescriptor serialDesc) {
        Intrinsics.checkNotNullParameter(self, "self");
        Intrinsics.checkNotNullParameter(output, "output");
        Intrinsics.checkNotNullParameter(serialDesc, "serialDesc");
        output.encodeStringElement(serialDesc, 0, self.name);
        output.encodeStringElement(serialDesc, 1, self.pathWord);
        output.encodeSerializableElement(serialDesc, 2, new ArrayListSerializer(AuthorInfo$$serializer.INSTANCE), self.author);
        if (output.shouldEncodeElementDefault(serialDesc, 3) || !Intrinsics.areEqual(self.theme, CollectionsKt.emptyList())) {
            output.encodeSerializableElement(serialDesc, 3, new ArrayListSerializer(ThemeInfo$$serializer.INSTANCE), self.theme);
        }
        output.encodeStringElement(serialDesc, 4, self.cover);
        output.encodeIntElement(serialDesc, 5, self.popular);
        output.encodeStringElement(serialDesc, 6, self.datetimeUpdated);
        output.encodeStringElement(serialDesc, 7, self.lastChapterName);
    }

    public final String getName() {
        return this.name;
    }

    public final String getPathWord() {
        return this.pathWord;
    }

    public final List<AuthorInfo> getAuthor() {
        return this.author;
    }

    public /* synthetic */ NewestComic(String str, String str2, List list, List list2, String str3, int i, String str4, String str5, int i2, DefaultConstructorMarker defaultConstructorMarker) {
        this(str, str2, list, (i2 & 8) != 0 ? CollectionsKt.emptyList() : list2, str3, i, str4, str5);
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

    public final String getLastChapterName() {
        return this.lastChapterName;
    }

    public final SManga toSManga(String resolution, CCOption language) {
        Intrinsics.checkNotNullParameter(resolution, "resolution");
        Intrinsics.checkNotNullParameter(language, "language");
        SManga sMangaCreate = SManga.Companion.create();
        sMangaCreate.setUrl("/comic/" + this.pathWord);
        sMangaCreate.setTitle(TranslateKt.translate(this.name, language));
        sMangaCreate.setAuthor(CollectionsKt.joinToString$default(this.author, (CharSequence) null, (CharSequence) null, (CharSequence) null, 0, (CharSequence) null, new Function1<AuthorInfo, CharSequence>() { // from class: eu.kanade.tachiyomi.extension.zh.copymanga.api.dto.NewestComic$toSManga$1$1
            public final CharSequence invoke(AuthorInfo authorInfo) {
                Intrinsics.checkNotNullParameter(authorInfo, "it");
                return authorInfo.getName();
            }
        }, 31, (Object) null));
        sMangaCreate.setDescription("");
        sMangaCreate.setGenre(CollectionsKt.joinToString$default(this.theme, (CharSequence) null, (CharSequence) null, (CharSequence) null, 0, (CharSequence) null, new Function1<ThemeInfo, CharSequence>() { // from class: eu.kanade.tachiyomi.extension.zh.copymanga.api.dto.NewestComic$toSManga$1$2
            public final CharSequence invoke(ThemeInfo themeInfo) {
                Intrinsics.checkNotNullParameter(themeInfo, "it");
                return themeInfo.getName();
            }
        }, 31, (Object) null));
        sMangaCreate.setStatus(0);
        sMangaCreate.setThumbnail_url(ResolutionOption.INSTANCE.translate(this.cover, resolution));
        sMangaCreate.setInitialized(false);
        return sMangaCreate;
    }
}
