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

/* JADX INFO: compiled from: ContentResult.kt */
/* JADX INFO: loaded from: classes.dex */
@Metadata(d1 = {"\u0000D\n\u0002\u0018\u0002\n\u0002\u0010\u0000\n\u0000\n\u0002\u0010\b\n\u0000\n\u0002\u0010\u000e\n\u0002\b\u0003\n\u0002\u0018\u0002\n\u0000\n\u0002\u0018\u0002\n\u0002\b\u0010\n\u0002\u0010\u000b\n\u0002\b\u0004\n\u0002\u0010\u0002\n\u0002\b\u0002\n\u0002\u0018\u0002\n\u0000\n\u0002\u0018\u0002\n\u0002\b\u0003\b\u0087\b\u0018\u0000 (2\u00020\u0001:\u0002'(BC\b\u0017\u0012\u0006\u0010\u0002\u001a\u00020\u0003\u0012\b\u0010\u0004\u001a\u0004\u0018\u00010\u0005\u0012\b\u0010\u0006\u001a\u0004\u0018\u00010\u0005\u0012\n\b\u0001\u0010\u0007\u001a\u0004\u0018\u00010\u0005\u0012\b\u0010\b\u001a\u0004\u0018\u00010\t\u0012\b\u0010\n\u001a\u0004\u0018\u00010\u000b¢\u0006\u0002\u0010\fB)\u0012\u0006\u0010\u0004\u001a\u00020\u0005\u0012\u0006\u0010\u0006\u001a\u00020\u0005\u0012\u0006\u0010\u0007\u001a\u00020\u0005\u0012\n\b\u0002\u0010\b\u001a\u0004\u0018\u00010\t¢\u0006\u0002\u0010\rJ\t\u0010\u0016\u001a\u00020\u0005HÆ\u0003J\t\u0010\u0017\u001a\u00020\u0005HÆ\u0003J\t\u0010\u0018\u001a\u00020\u0005HÆ\u0003J\u000b\u0010\u0019\u001a\u0004\u0018\u00010\tHÆ\u0003J3\u0010\u001a\u001a\u00020\u00002\b\b\u0002\u0010\u0004\u001a\u00020\u00052\b\b\u0002\u0010\u0006\u001a\u00020\u00052\b\b\u0002\u0010\u0007\u001a\u00020\u00052\n\b\u0002\u0010\b\u001a\u0004\u0018\u00010\tHÆ\u0001J\u0013\u0010\u001b\u001a\u00020\u001c2\b\u0010\u001d\u001a\u0004\u0018\u00010\u0001HÖ\u0003J\t\u0010\u001e\u001a\u00020\u0003HÖ\u0001J\t\u0010\u001f\u001a\u00020\u0005HÖ\u0001J!\u0010 \u001a\u00020!2\u0006\u0010\"\u001a\u00020\u00002\u0006\u0010#\u001a\u00020$2\u0006\u0010%\u001a\u00020&HÇ\u0001R\u0011\u0010\u0004\u001a\u00020\u0005¢\u0006\b\n\u0000\u001a\u0004\b\u000e\u0010\u000fR\u001c\u0010\u0007\u001a\u00020\u00058\u0006X\u0087\u0004¢\u0006\u000e\n\u0000\u0012\u0004\b\u0010\u0010\u0011\u001a\u0004\b\u0012\u0010\u000fR\u0013\u0010\b\u001a\u0004\u0018\u00010\t¢\u0006\b\n\u0000\u001a\u0004\b\u0013\u0010\u0014R\u0011\u0010\u0006\u001a\u00020\u0005¢\u0006\b\n\u0000\u001a\u0004\b\u0015\u0010\u000f¨\u0006)"}, d2 = {"Leu/kanade/tachiyomi/extension/zh/copymanga/api/dto/ComicSummaryFace;", "", "seen1", "", "name", "", "uuid", "pathWord", "restrict", "Leu/kanade/tachiyomi/extension/zh/copymanga/api/dto/FreeType;", "serializationConstructorMarker", "Lkotlinx/serialization/internal/SerializationConstructorMarker;", "(ILjava/lang/String;Ljava/lang/String;Ljava/lang/String;Leu/kanade/tachiyomi/extension/zh/copymanga/api/dto/FreeType;Lkotlinx/serialization/internal/SerializationConstructorMarker;)V", "(Ljava/lang/String;Ljava/lang/String;Ljava/lang/String;Leu/kanade/tachiyomi/extension/zh/copymanga/api/dto/FreeType;)V", "getName", "()Ljava/lang/String;", "getPathWord$annotations", "()V", "getPathWord", "getRestrict", "()Leu/kanade/tachiyomi/extension/zh/copymanga/api/dto/FreeType;", "getUuid", "component1", "component2", "component3", "component4", "copy", "equals", "", "other", "hashCode", "toString", "write$Self", "", "self", "output", "Lkotlinx/serialization/encoding/CompositeEncoder;", "serialDesc", "Lkotlinx/serialization/descriptors/SerialDescriptor;", "$serializer", "Companion", "tachiyomi-zh.copymanga-v1.4.82_release"}, k = 1, mv = {1, 7, 1}, xi = 48)
@Serializable
public final /* data */ class ComicSummaryFace {

    /* JADX INFO: renamed from: Companion, reason: from kotlin metadata */
    public static final Companion INSTANCE = new Companion(null);
    private final String name;
    private final String pathWord;
    private final FreeType restrict;
    private final String uuid;

    public static /* synthetic */ ComicSummaryFace copy$default(ComicSummaryFace comicSummaryFace, String str, String str2, String str3, FreeType freeType, int i, Object obj) {
        if ((i & 1) != 0) {
            str = comicSummaryFace.name;
        }
        if ((i & 2) != 0) {
            str2 = comicSummaryFace.uuid;
        }
        if ((i & 4) != 0) {
            str3 = comicSummaryFace.pathWord;
        }
        if ((i & 8) != 0) {
            freeType = comicSummaryFace.restrict;
        }
        return comicSummaryFace.copy(str, str2, str3, freeType);
    }

    @SerialName("path_word")
    public static /* synthetic */ void getPathWord$annotations() {
    }

    /* JADX INFO: renamed from: component1, reason: from getter */
    public final String getName() {
        return this.name;
    }

    /* JADX INFO: renamed from: component2, reason: from getter */
    public final String getUuid() {
        return this.uuid;
    }

    /* JADX INFO: renamed from: component3, reason: from getter */
    public final String getPathWord() {
        return this.pathWord;
    }

    /* JADX INFO: renamed from: component4, reason: from getter */
    public final FreeType getRestrict() {
        return this.restrict;
    }

    public final ComicSummaryFace copy(String name, String uuid, String pathWord, FreeType restrict) {
        Intrinsics.checkNotNullParameter(name, "name");
        Intrinsics.checkNotNullParameter(uuid, "uuid");
        Intrinsics.checkNotNullParameter(pathWord, "pathWord");
        return new ComicSummaryFace(name, uuid, pathWord, restrict);
    }

    public boolean equals(Object other) {
        if (this == other) {
            return true;
        }
        if (!(other instanceof ComicSummaryFace)) {
            return false;
        }
        ComicSummaryFace comicSummaryFace = (ComicSummaryFace) other;
        return Intrinsics.areEqual(this.name, comicSummaryFace.name) && Intrinsics.areEqual(this.uuid, comicSummaryFace.uuid) && Intrinsics.areEqual(this.pathWord, comicSummaryFace.pathWord) && Intrinsics.areEqual(this.restrict, comicSummaryFace.restrict);
    }

    public int hashCode() {
        int iHashCode = ((((this.name.hashCode() * 31) + this.uuid.hashCode()) * 31) + this.pathWord.hashCode()) * 31;
        FreeType freeType = this.restrict;
        return iHashCode + (freeType == null ? 0 : freeType.hashCode());
    }

    public String toString() {
        return "ComicSummaryFace(name=" + this.name + ", uuid=" + this.uuid + ", pathWord=" + this.pathWord + ", restrict=" + this.restrict + ')';
    }

    /* JADX INFO: compiled from: ContentResult.kt */
    @Metadata(d1 = {"\u0000\u0016\n\u0002\u0018\u0002\n\u0002\u0010\u0000\n\u0002\b\u0002\n\u0002\u0018\u0002\n\u0002\u0018\u0002\n\u0000\b\u0086\u0003\u0018\u00002\u00020\u0001B\u0007\b\u0002¢\u0006\u0002\u0010\u0002J\u000f\u0010\u0003\u001a\b\u0012\u0004\u0012\u00020\u00050\u0004HÆ\u0001¨\u0006\u0006"}, d2 = {"Leu/kanade/tachiyomi/extension/zh/copymanga/api/dto/ComicSummaryFace$Companion;", "", "()V", "serializer", "Lkotlinx/serialization/KSerializer;", "Leu/kanade/tachiyomi/extension/zh/copymanga/api/dto/ComicSummaryFace;", "tachiyomi-zh.copymanga-v1.4.82_release"}, k = 1, mv = {1, 7, 1}, xi = 48)
    public static final class Companion {
        public /* synthetic */ Companion(DefaultConstructorMarker defaultConstructorMarker) {
            this();
        }

        private Companion() {
        }

        public final KSerializer<ComicSummaryFace> serializer() {
            return ComicSummaryFace$$serializer.INSTANCE;
        }
    }

    @Deprecated(level = DeprecationLevel.HIDDEN, message = "This synthesized declaration should not be used directly", replaceWith = @ReplaceWith(expression = "", imports = {}))
    public /* synthetic */ ComicSummaryFace(int i, String str, String str2, @SerialName("path_word") String str3, FreeType freeType, SerializationConstructorMarker serializationConstructorMarker) {
        if (7 != (i & 7)) {
            PluginExceptionsKt.throwMissingFieldException(i, 7, ComicSummaryFace$$serializer.INSTANCE.getDescriptor());
        }
        this.name = str;
        this.uuid = str2;
        this.pathWord = str3;
        if ((i & 8) == 0) {
            this.restrict = null;
        } else {
            this.restrict = freeType;
        }
    }

    public ComicSummaryFace(String str, String str2, String str3, FreeType freeType) {
        Intrinsics.checkNotNullParameter(str, "name");
        Intrinsics.checkNotNullParameter(str2, "uuid");
        Intrinsics.checkNotNullParameter(str3, "pathWord");
        this.name = str;
        this.uuid = str2;
        this.pathWord = str3;
        this.restrict = freeType;
    }

    @JvmStatic
    public static final void write$Self(ComicSummaryFace self, CompositeEncoder output, SerialDescriptor serialDesc) {
        Intrinsics.checkNotNullParameter(self, "self");
        Intrinsics.checkNotNullParameter(output, "output");
        Intrinsics.checkNotNullParameter(serialDesc, "serialDesc");
        output.encodeStringElement(serialDesc, 0, self.name);
        output.encodeStringElement(serialDesc, 1, self.uuid);
        output.encodeStringElement(serialDesc, 2, self.pathWord);
        if (!output.shouldEncodeElementDefault(serialDesc, 3) && self.restrict == null) {
            return;
        }
        output.encodeNullableSerializableElement(serialDesc, 3, FreeType$$serializer.INSTANCE, self.restrict);
    }

    public /* synthetic */ ComicSummaryFace(String str, String str2, String str3, FreeType freeType, int i, DefaultConstructorMarker defaultConstructorMarker) {
        this(str, str2, str3, (i & 8) != 0 ? null : freeType);
    }

    public final String getName() {
        return this.name;
    }

    public final String getUuid() {
        return this.uuid;
    }

    public final String getPathWord() {
        return this.pathWord;
    }

    public final FreeType getRestrict() {
        return this.restrict;
    }
}
