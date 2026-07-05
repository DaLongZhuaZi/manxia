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

/* JADX INFO: compiled from: NewestResult.kt */
/* JADX INFO: loaded from: classes.dex */
@Metadata(d1 = {"\u0000D\n\u0002\u0018\u0002\n\u0002\u0010\u0000\n\u0000\n\u0002\u0010\b\n\u0000\n\u0002\u0010\u000e\n\u0002\b\u0002\n\u0002\u0018\u0002\n\u0000\n\u0002\u0018\u0002\n\u0002\b\u000e\n\u0002\u0010\u000b\n\u0002\b\u0004\n\u0002\u0010\u0002\n\u0002\b\u0002\n\u0002\u0018\u0002\n\u0000\n\u0002\u0018\u0002\n\u0002\b\u0003\b\u0087\b\u0018\u0000 %2\u00020\u0001:\u0002$%B9\b\u0017\u0012\u0006\u0010\u0002\u001a\u00020\u0003\u0012\b\u0010\u0004\u001a\u0004\u0018\u00010\u0005\u0012\n\b\u0001\u0010\u0006\u001a\u0004\u0018\u00010\u0005\u0012\b\u0010\u0007\u001a\u0004\u0018\u00010\b\u0012\b\u0010\t\u001a\u0004\u0018\u00010\n¢\u0006\u0002\u0010\u000bB\u001d\u0012\u0006\u0010\u0004\u001a\u00020\u0005\u0012\u0006\u0010\u0006\u001a\u00020\u0005\u0012\u0006\u0010\u0007\u001a\u00020\b¢\u0006\u0002\u0010\fJ\t\u0010\u0014\u001a\u00020\u0005HÆ\u0003J\t\u0010\u0015\u001a\u00020\u0005HÆ\u0003J\t\u0010\u0016\u001a\u00020\bHÆ\u0003J'\u0010\u0017\u001a\u00020\u00002\b\b\u0002\u0010\u0004\u001a\u00020\u00052\b\b\u0002\u0010\u0006\u001a\u00020\u00052\b\b\u0002\u0010\u0007\u001a\u00020\bHÆ\u0001J\u0013\u0010\u0018\u001a\u00020\u00192\b\u0010\u001a\u001a\u0004\u0018\u00010\u0001HÖ\u0003J\t\u0010\u001b\u001a\u00020\u0003HÖ\u0001J\t\u0010\u001c\u001a\u00020\u0005HÖ\u0001J!\u0010\u001d\u001a\u00020\u001e2\u0006\u0010\u001f\u001a\u00020\u00002\u0006\u0010 \u001a\u00020!2\u0006\u0010\"\u001a\u00020#HÇ\u0001R\u0011\u0010\u0007\u001a\u00020\b¢\u0006\b\n\u0000\u001a\u0004\b\r\u0010\u000eR\u001c\u0010\u0006\u001a\u00020\u00058\u0006X\u0087\u0004¢\u0006\u000e\n\u0000\u0012\u0004\b\u000f\u0010\u0010\u001a\u0004\b\u0011\u0010\u0012R\u0011\u0010\u0004\u001a\u00020\u0005¢\u0006\b\n\u0000\u001a\u0004\b\u0013\u0010\u0012¨\u0006&"}, d2 = {"Leu/kanade/tachiyomi/extension/zh/copymanga/api/dto/NewestItem;", "", "seen1", "", "name", "", "datetimeCreated", "comic", "Leu/kanade/tachiyomi/extension/zh/copymanga/api/dto/NewestComic;", "serializationConstructorMarker", "Lkotlinx/serialization/internal/SerializationConstructorMarker;", "(ILjava/lang/String;Ljava/lang/String;Leu/kanade/tachiyomi/extension/zh/copymanga/api/dto/NewestComic;Lkotlinx/serialization/internal/SerializationConstructorMarker;)V", "(Ljava/lang/String;Ljava/lang/String;Leu/kanade/tachiyomi/extension/zh/copymanga/api/dto/NewestComic;)V", "getComic", "()Leu/kanade/tachiyomi/extension/zh/copymanga/api/dto/NewestComic;", "getDatetimeCreated$annotations", "()V", "getDatetimeCreated", "()Ljava/lang/String;", "getName", "component1", "component2", "component3", "copy", "equals", "", "other", "hashCode", "toString", "write$Self", "", "self", "output", "Lkotlinx/serialization/encoding/CompositeEncoder;", "serialDesc", "Lkotlinx/serialization/descriptors/SerialDescriptor;", "$serializer", "Companion", "tachiyomi-zh.copymanga-v1.4.82_release"}, k = 1, mv = {1, 7, 1}, xi = 48)
@Serializable
public final /* data */ class NewestItem {

    /* JADX INFO: renamed from: Companion, reason: from kotlin metadata */
    public static final Companion INSTANCE = new Companion(null);
    private final NewestComic comic;
    private final String datetimeCreated;
    private final String name;

    public static /* synthetic */ NewestItem copy$default(NewestItem newestItem, String str, String str2, NewestComic newestComic, int i, Object obj) {
        if ((i & 1) != 0) {
            str = newestItem.name;
        }
        if ((i & 2) != 0) {
            str2 = newestItem.datetimeCreated;
        }
        if ((i & 4) != 0) {
            newestComic = newestItem.comic;
        }
        return newestItem.copy(str, str2, newestComic);
    }

    @SerialName("datetime_created")
    public static /* synthetic */ void getDatetimeCreated$annotations() {
    }

    /* JADX INFO: renamed from: component1, reason: from getter */
    public final String getName() {
        return this.name;
    }

    /* JADX INFO: renamed from: component2, reason: from getter */
    public final String getDatetimeCreated() {
        return this.datetimeCreated;
    }

    /* JADX INFO: renamed from: component3, reason: from getter */
    public final NewestComic getComic() {
        return this.comic;
    }

    public final NewestItem copy(String name, String datetimeCreated, NewestComic comic) {
        Intrinsics.checkNotNullParameter(name, "name");
        Intrinsics.checkNotNullParameter(datetimeCreated, "datetimeCreated");
        Intrinsics.checkNotNullParameter(comic, "comic");
        return new NewestItem(name, datetimeCreated, comic);
    }

    public boolean equals(Object other) {
        if (this == other) {
            return true;
        }
        if (!(other instanceof NewestItem)) {
            return false;
        }
        NewestItem newestItem = (NewestItem) other;
        return Intrinsics.areEqual(this.name, newestItem.name) && Intrinsics.areEqual(this.datetimeCreated, newestItem.datetimeCreated) && Intrinsics.areEqual(this.comic, newestItem.comic);
    }

    public int hashCode() {
        return (((this.name.hashCode() * 31) + this.datetimeCreated.hashCode()) * 31) + this.comic.hashCode();
    }

    public String toString() {
        return "NewestItem(name=" + this.name + ", datetimeCreated=" + this.datetimeCreated + ", comic=" + this.comic + ')';
    }

    /* JADX INFO: compiled from: NewestResult.kt */
    @Metadata(d1 = {"\u0000\u0016\n\u0002\u0018\u0002\n\u0002\u0010\u0000\n\u0002\b\u0002\n\u0002\u0018\u0002\n\u0002\u0018\u0002\n\u0000\b\u0086\u0003\u0018\u00002\u00020\u0001B\u0007\b\u0002¢\u0006\u0002\u0010\u0002J\u000f\u0010\u0003\u001a\b\u0012\u0004\u0012\u00020\u00050\u0004HÆ\u0001¨\u0006\u0006"}, d2 = {"Leu/kanade/tachiyomi/extension/zh/copymanga/api/dto/NewestItem$Companion;", "", "()V", "serializer", "Lkotlinx/serialization/KSerializer;", "Leu/kanade/tachiyomi/extension/zh/copymanga/api/dto/NewestItem;", "tachiyomi-zh.copymanga-v1.4.82_release"}, k = 1, mv = {1, 7, 1}, xi = 48)
    public static final class Companion {
        public /* synthetic */ Companion(DefaultConstructorMarker defaultConstructorMarker) {
            this();
        }

        private Companion() {
        }

        public final KSerializer<NewestItem> serializer() {
            return NewestItem$$serializer.INSTANCE;
        }
    }

    @Deprecated(level = DeprecationLevel.HIDDEN, message = "This synthesized declaration should not be used directly", replaceWith = @ReplaceWith(expression = "", imports = {}))
    public /* synthetic */ NewestItem(int i, String str, @SerialName("datetime_created") String str2, NewestComic newestComic, SerializationConstructorMarker serializationConstructorMarker) {
        if (7 != (i & 7)) {
            PluginExceptionsKt.throwMissingFieldException(i, 7, NewestItem$$serializer.INSTANCE.getDescriptor());
        }
        this.name = str;
        this.datetimeCreated = str2;
        this.comic = newestComic;
    }

    public NewestItem(String str, String str2, NewestComic newestComic) {
        Intrinsics.checkNotNullParameter(str, "name");
        Intrinsics.checkNotNullParameter(str2, "datetimeCreated");
        Intrinsics.checkNotNullParameter(newestComic, "comic");
        this.name = str;
        this.datetimeCreated = str2;
        this.comic = newestComic;
    }

    @JvmStatic
    public static final void write$Self(NewestItem self, CompositeEncoder output, SerialDescriptor serialDesc) {
        Intrinsics.checkNotNullParameter(self, "self");
        Intrinsics.checkNotNullParameter(output, "output");
        Intrinsics.checkNotNullParameter(serialDesc, "serialDesc");
        output.encodeStringElement(serialDesc, 0, self.name);
        output.encodeStringElement(serialDesc, 1, self.datetimeCreated);
        output.encodeSerializableElement(serialDesc, 2, NewestComic$$serializer.INSTANCE, self.comic);
    }

    public final String getName() {
        return this.name;
    }

    public final String getDatetimeCreated() {
        return this.datetimeCreated;
    }

    public final NewestComic getComic() {
        return this.comic;
    }
}
